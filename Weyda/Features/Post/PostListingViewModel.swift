import Combine
import Foundation

/// Machine à étapes du dépôt d'annonce — portage de `PostListingViewModel` (Android). Validation locale par étape
/// (miroir de PostAdWizard + annonceSchema + validateListingAttributes), brouillon écrit à chaque modification de
/// l'utilisateur et restauré au démarrage, photos envoyées une à une, renvoi sur l'étape fautive après un refus.
///
/// Chaque action qui lance du travail renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les tests l'attendent ;
/// les chargements en cascade (catégories → attributs → options dépendantes) s'attendent par `waitForIdle()`.
///
/// Écarts iOS assumés : pas d'`onLocaleChanged` (changer la langue de l'app dans Réglages relance l'app) ; le brouillon
/// d'une ÉDITION vit en mémoire (iOS ne tue pas l'app pendant l'appareil photo comme Android peut le faire) ; les photos
/// sont des octets copiés dans `photoStore` (Android : URI `content://` relisible).
final class PostListingViewModel: ObservableObject {
    @Published private(set) var state: PostListingState
    /// Note App Store : passe à vrai quand une PUBLICATION (pas une modification) est le bon moment (`ReviewPrompter`).
    @Published private(set) var asksForReview: Bool = false

    /// Fichiers des photos choisies (aperçu local : `photoStore.fileURL(for: item.localRef)`).
    let photoStore: PostPhotoStore

    /// Travail lancé par le ViewModel : une seule fabrique de tâches (`start`), suivies pour `waitForIdle()`.
    private nonisolated enum Job: Sendable {
        case categories
        case editing(id: String)
        case wilayas
        case communes(wilayaId: Int)
        case attributes(parentSlug: String, subcategorySlug: String?, language: String)
        case dependent(key: String, parentSlug: String, subcategorySlug: String?, context: [String: String], language: String)
        case profile
        case pickPhotos(images: [Data], after: Task<Void, Never>?, generation: Int)
        case uploads(generation: Int)
        case submit(ListingSubmission)
    }

    /// Issue de l'envoi d'une photo (message déjà traduit en cas d'échec).
    private nonisolated enum PhotoOutcome: Sendable {
        case uploaded(UploadedImage)
        case failed(String)
    }

    /// Id de l'annonce à modifier ; nil = nouveau dépôt.
    private let editingId: String?
    private let drafts: any PostDraftStore
    private let annonces: AnnonceRepository
    private let categoryRepository: CategoryRepository
    private let attributeRepository: AttributeRepository
    private let geo: GeoRepository
    private let auth: AuthRepository
    private let users: UserRepository
    private let uploads: UploadRepository
    /// Langue des libellés d'attributs (fixée par les tests ; sinon celle de l'app).
    private let locale: () -> String
    private let reviewPrompter: ReviewPrompter

    /// Annonce lue avant les catégories (édition) : appliquée dès que celles-ci arrivent.
    private var editing: Listing?
    /// Compte auteur du brouillon courant (voir `onAccountChanged`).
    private var draftOwnerId: String? = nil
    /// Dernier compte vu sur la session (le premier envoi du publieur est la valeur courante : ignoré).
    private var observedUserId: String? = nil
    private var userSubscription: AnyCancellable?

    private var attributesTask: Task<Void, Never>?
    private var dependentTask: Task<Void, Never>?
    private var communesTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    /// Dernier choix de photos en cours d'écriture : les choix suivants l'attendent (doublons et places comptés juste).
    private var pickTask: Task<Void, Never>?
    /// Change à chaque remise à zéro du formulaire : un envoi ou un choix de photos lancé avant est ignoré.
    private var generation = 0

    private var inFlight: [Int: Task<Void, Never>] = [:]
    private var nextTaskID = 0

    init(
        editingId: String?,
        drafts: any PostDraftStore,
        photoStore: PostPhotoStore,
        annonces: AnnonceRepository,
        categories: CategoryRepository,
        attributes: AttributeRepository,
        geo: GeoRepository,
        auth: AuthRepository,
        users: UserRepository,
        uploads: UploadRepository,
        userUpdates: AnyPublisher<User?, Never>,
        locale: @escaping () -> String = { WeydaLocale.language },
        reviewPrompter: ReviewPrompter = ReviewPrompter(isEnabled: false)
    ) {
        self.editingId = editingId
        self.drafts = drafts
        self.photoStore = photoStore
        self.annonces = annonces
        self.categoryRepository = categories
        self.attributeRepository = attributes
        self.geo = geo
        self.auth = auth
        self.users = users
        self.uploads = uploads
        self.locale = locale
        self.reviewPrompter = reviewPrompter
        let user = auth.user
        var initial = PostListingState()
        initial.userPhone = TextCheck.nonBlank(user?.phone)
        initial.maxPhotos = user?.maxImages ?? 5
        initial.emailVerified = user?.emailVerified ?? true
        initial.editingId = editingId
        initial.editLoading = editingId != nil
        self.state = initial
        self.draftOwnerId = user?.id
        self.observedUserId = user?.id

        // Édition : un brouillon présent est repris au lieu de relire l'annonce (Android : retour après la mort du
        // processus). Sur iOS le brouillon d'édition est en mémoire, neuf à chaque ouverture : l'annonce est relue.
        let restored = restoreDraft()
        // Fichiers que le brouillon ne cite plus (photos d'un dépôt abandonné, d'un autre compte) : effacés.
        photoStore.purge(keeping: Set(state.photos.map { $0.localRef }))
        if let editingId, !restored {
            start(.editing(id: editingId))
        }
        loadCategories()
        start(.wilayas)
        if let wilayaId = state.wilayaId {
            loadCommunes(wilayaId)
        }
        refreshProfile()
        // Au changement de compte, ni le brouillon ni le téléphone du précédent ne doivent s'afficher — et encore
        // moins partir dans l'annonce du suivant. `emailVerified` est suivi en direct (bandeau « Vérifier »).
        userSubscription = userUpdates.sink { [weak self] user in
            self?.sessionUserChanged(user)
        }
        // Brouillon : photos choisies mais pas encore envoyées → reprise de la file.
        if state.photos.contains(where: { $0.status == .uploading }) {
            processUploadQueue()
        }
    }

    /// Nouveau dépôt : `container.postDrafts` + `container.postPhotos` (disque, survit à la fermeture) ;
    /// édition : brouillon en mémoire + `PostPhotoStore.standard(namespace: "edit")`.
    static func make(container: AppContainer, editingId: String?) -> PostListingViewModel {
        let stores = storage(editingId: editingId, newDrafts: container.postDrafts, newPhotos: container.postPhotos)
        return PostListingViewModel(
            editingId: editingId,
            drafts: stores.drafts,
            photoStore: stores.photos,
            annonces: container.annonces,
            categories: container.categories,
            attributes: container.attributes,
            geo: container.geo,
            auth: container.auth,
            users: container.users,
            uploads: container.uploads,
            userUpdates: container.sessionManager.$user.eraseToAnyPublisher(),
            reviewPrompter: container.reviewPrompter
        )
    }

    /// Stockage du brouillon selon le mode (séparé de `make` pour les tests) : jamais le brouillon disque du nouveau
    /// dépôt pour une édition — elle l'écraserait.
    static func storage(
        editingId: String?,
        newDrafts: FilePostDraftStore,
        newPhotos: PostPhotoStore
    ) -> (drafts: any PostDraftStore, photos: PostPhotoStore) {
        if editingId == nil {
            let drafts: any PostDraftStore = newDrafts
            return (drafts: drafts, photos: newPhotos)
        }
        let drafts: any PostDraftStore = InMemoryPostDraftStore()
        return (drafts: drafts, photos: PostPhotoStore.standard(namespace: "edit"))
    }

    /// Pour les tests : attend toutes les tâches lancées, y compris celles qu'elles lancent à leur tour (catégories →
    /// attributs → options dépendantes, file d'envoi) — l'équivalent d'`advanceUntilIdle()`.
    func waitForIdle() async {
        while let task = inFlight.values.first {
            await task.value
        }
    }

    // MARK: - Chargements

    @discardableResult
    func loadCategories() -> Task<Void, Never>? {
        start(.categories)
    }

    /// « Réessayer » après un échec de lecture de l'annonce à modifier.
    @discardableResult
    func loadEditing() -> Task<Void, Never>? {
        guard let editingId else { return nil }
        return start(.editing(id: editingId))
    }

    // MARK: - Catégorie

    @discardableResult
    func onSelectParent(_ id: String) -> Task<Void, Never>? {
        guard state.parentCategoryId != id else { return nil }
        attributesTask?.cancel()
        dependentTask?.cancel()
        update { s in
            s.parentCategoryId = id
            s.subcategoryId = nil
            s.categoryError = nil
            s.attributeSet = nil
            // Chargement annulé : l'indicateur ne doit pas rester allumé (iOS ; Android le laissait au suivant).
            s.attributesLoading = false
            s.attributeValues = [:]
            s.attributeErrors = [:]
            s.dependentOptions = [:]
        }
        return state.needsSubcategory ? nil : loadAttributes()
    }

    @discardableResult
    func onSelectSubcategory(_ id: String) -> Task<Void, Never>? {
        guard state.subcategoryId != id else { return nil }
        dependentTask?.cancel()
        update { s in
            s.subcategoryId = id
            s.categoryError = nil
            s.attributeSet = nil
            s.attributeValues = [:]
            s.attributeErrors = [:]
            s.dependentOptions = [:]
        }
        return loadAttributes()
    }

    // MARK: - Attributs

    /// Valeur vide = attribut retiré ; les selects qui en dépendent sont vidés puis rechargés avec le nouveau contexte.
    /// Attribut NUMBER : chiffres latins et « . » décimal (`Validators.asciiDecimal`, Android : dans l'écran).
    @discardableResult
    func onAttributeChange(_ key: String, _ value: String) -> Task<Void, Never>? {
        let definitions = state.attributeSet?.attributes ?? []
        let dependents: [String] = definitions.filter { $0.dependsOn == key }.map { $0.key }
        let isNumber = definitions.first { $0.key == key }?.type == .number
        let cleaned = isNumber ? String(Validators.asciiDecimal(value).prefix(12)) : value
        update { s in
            if TextCheck.isBlank(cleaned) {
                s.attributeValues[key] = nil
            } else {
                s.attributeValues[key] = cleaned
            }
            s.attributeErrors[key] = nil
            for dependent in dependents {
                s.attributeValues[dependent] = nil
                s.attributeErrors[dependent] = nil
                s.dependentOptions[dependent] = nil
            }
        }
        guard !TextCheck.isBlank(cleaned) else { return nil }
        var last: Task<Void, Never>? = nil
        for dependent in dependents {
            last = refreshDependent(dependent)
        }
        return last
    }

    // MARK: - Infos & prix

    func onTitleChange(_ value: String) {
        update { s in
            s.title = RepositorySupport.truncatedUTF16(value, max: PostListingState.titleMax + 20)
            s.titleError = nil
        }
    }

    func onDescriptionChange(_ value: String) {
        update { s in
            s.description = RepositorySupport.truncatedUTF16(value, max: PostListingState.descriptionMax + 200)
            s.descriptionError = nil
        }
    }

    func onPriceTypeChange(_ type: PriceType) {
        update { s in
            s.priceType = type
            if type == .free { s.price = "" }
            s.priceError = nil
        }
    }

    /// Chiffres seulement (clavier arabe compris, « 1 500 DA » → « 1500 »), 10 au plus.
    func onPriceChange(_ value: String) {
        update { s in
            s.price = String(Validators.asciiDigits(value).prefix(10))
            s.priceError = nil
        }
    }

    // MARK: - Photos

    /// Octets des photos choisies (galerie ou appareil) : écrits dans `photoStore` (SHA-256 = nom : une même photo
    /// choisie deux fois n'est ajoutée qu'une fois), places restantes respectées (excédent → `photosBanner`), file
    /// d'envoi lancée. Android : `onPhotosPicked(uris)`.
    @discardableResult
    func onPhotosPicked(_ images: [Data]) -> Task<Void, Never>? {
        let picked = images.filter { !$0.isEmpty }
        guard !picked.isEmpty else { return nil }
        let task = start(.pickPhotos(images: picked, after: pickTask, generation: generation))
        pickTask = task
        return task
    }

    /// Pas d'appareil photo utilisable : avis sur l'étape, la galerie reste disponible (Android : `error_no_app`).
    func onCameraUnavailable() {
        state.photosBanner = AccountBanner.failure(L10n.postWizCameraUnavailable)
    }

    func onRemovePhoto(at index: Int) {
        guard state.photos.indices.contains(index) else { return }
        let removed = state.photos[index]
        update { s in
            s.photos.remove(at: index)
            s.photosBanner = nil
            s.errorMessage = nil
        }
        // Le fichier local ne sert plus (une photo en ligne d'une édition n'a pas de fichier : sans effet).
        if !state.photos.contains(where: { $0.localRef == removed.localRef }) {
            photoStore.remove(removed.localRef)
        }
    }

    /// Déplace la photo en première position (= photo principale).
    func onMakeMainPhoto(at index: Int) {
        let photos = state.photos
        guard index > 0, index < photos.count else { return }
        update { s in
            let main = s.photos.remove(at: index)
            s.photos.insert(main, at: 0)
        }
    }

    @discardableResult
    func onRetryPhoto(at index: Int) -> Task<Void, Never>? {
        guard state.photos.indices.contains(index), state.photos[index].status == .failed else { return nil }
        update { s in
            s.photos[index].status = .uploading
            s.photos[index].errorMessage = nil
            s.errorMessage = nil
        }
        return processUploadQueue()
    }

    func photosNoticeShown() {
        state.photosBanner = nil
    }

    // MARK: - Localisation

    @discardableResult
    func onWilayaChange(_ id: Int?) -> Task<Void, Never>? {
        communesTask?.cancel()
        update { s in
            s.wilayaId = id
            s.communeId = nil
            s.communes = []
            s.communesLoading = false
        }
        guard let id else { return nil }
        return loadCommunes(id)
    }

    func onCommuneChange(_ id: Int?) {
        update { s in s.communeId = id }
    }

    func onShowPhoneChange(_ show: Bool) {
        update { s in s.showPhone = show }
    }

    // MARK: - Navigation

    /// Valide l'étape puis avance ; à la dernière, publie. Tant que la catégorie n'est pas résolue et ses attributs
    /// connus, le bouton relance le chargement qui a échoué (le message d'erreur est déjà affiché).
    @discardableResult
    func next() -> Task<Void, Never>? {
        let s = state
        guard s.canGoNext else { return nil }
        if s.categories.isEmpty {
            return loadCategories()
        }
        if s.isCategoryComplete && s.attributeSet == nil {
            return loadAttributes()
        }
        guard validateStep(s.step, in: s) else { return nil }
        if s.step == .review {
            return submit()
        }
        let steps = state.steps
        if let index = steps.firstIndex(of: state.step), index < steps.count - 1 {
            let following = steps[index + 1]
            update { s in
                s.step = following
                s.errorMessage = nil
            }
        }
        return nil
    }

    func back() {
        let s = state
        guard let index = s.steps.firstIndex(of: s.step), index > 0 else { return }
        let previous = s.steps[index - 1]
        update { s in
            s.step = previous
            s.errorMessage = nil
        }
    }

    /// Depuis le récapitulatif : retour direct sur une étape (si elle existe pour cette catégorie).
    func goTo(_ step: PostStep) {
        guard state.steps.contains(step) else { return }
        update { s in
            s.step = step
            s.errorMessage = nil
        }
    }

    // MARK: - Soumission

    @discardableResult
    func submit() -> Task<Void, Never>? {
        let s = state
        guard !s.isSubmitting, !s.isUploading else { return nil }
        if s.photos.contains(where: { $0.status == .failed }) {
            update { s in
                s.step = .photos
                s.errorMessage = L10n.postPhotosFailedHint
            }
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        return start(.submit(s.toSubmission()))
    }

    // MARK: - Brouillon

    /// « Déposer une autre annonce » (et changement de compte) : brouillon et fichiers effacés, formulaire vierge.
    /// Catégories, wilayas, téléphone et limite de photos sont gardés. iOS : les chargements en vol sont aussi
    /// annulés (Android n'annulait que les envois) et `emailVerified` / `editingId` sont conservés.
    func clearDraft() {
        drafts.clear()
        generation += 1
        uploadTask?.cancel()
        uploadTask = nil
        pickTask?.cancel()
        pickTask = nil
        attributesTask?.cancel()
        attributesTask = nil
        dependentTask?.cancel()
        dependentTask = nil
        communesTask?.cancel()
        communesTask = nil
        photoStore.purge(keeping: [])
        let current = state
        var fresh = PostListingState()
        fresh.categories = current.categories
        fresh.categoriesLoading = false
        fresh.wilayas = current.wilayas
        fresh.userPhone = current.userPhone
        fresh.maxPhotos = current.maxPhotos
        fresh.emailVerified = current.emailVerified
        fresh.editingId = editingId
        state = fresh
    }

    // MARK: - Tâches

    @discardableResult
    private func start(_ job: Job) -> Task<Void, Never> {
        let id = nextTaskID
        nextTaskID += 1
        let task = Task { [weak self] in
            await self?.perform(job)
            self?.inFlight[id] = nil
        }
        inFlight[id] = task
        return task
    }

    private func perform(_ job: Job) async {
        switch job {
        case .categories:
            await runLoadCategories()
        case .editing(let id):
            await runLoadEditing(id)
        case .wilayas:
            await runLoadWilayas()
        case .communes(let wilayaId):
            await runLoadCommunes(wilayaId)
        case .attributes(let parentSlug, let subcategorySlug, let language):
            await runLoadAttributes(parentSlug: parentSlug, subcategorySlug: subcategorySlug, language: language)
        case .dependent(let key, let parentSlug, let subcategorySlug, let context, let language):
            await runRefreshDependent(
                key: key,
                parentSlug: parentSlug,
                subcategorySlug: subcategorySlug,
                context: context,
                language: language
            )
        case .profile:
            await runRefreshProfile()
        case .pickPhotos(let images, let previous, let generation):
            await runPickPhotos(images, after: previous, generation: generation)
        case .uploads(let generation):
            await runUploadQueue(generation: generation)
        case .submit(let submission):
            await runSubmit(submission)
        }
    }

    // MARK: - Chargements (interne)

    private func runLoadCategories() async {
        var loading = state
        loading.categoriesLoading = true
        loading.categoriesError = false
        state = loading
        do {
            let list = try await categoryRepository.roots()
            var loaded = state
            loaded.categoriesLoading = false
            loaded.categories = list
            state = loaded
            // Brouillon restauré ou édition : la catégorie n'est connue que maintenant → attributs.
            if let editing {
                applyEditing(editing)
            }
            if state.isCategoryComplete {
                loadAttributes()
            }
        } catch {
            var failed = state
            failed.categoriesLoading = false
            failed.categoriesError = true
            state = failed
        }
    }

    private func runLoadEditing(_ id: String) async {
        state.editLoading = true
        state.editError = nil
        do {
            let listing = try await annonces.detail(idOrSlug: id)
            editing = listing
            state.editLoading = false
            if !state.categories.isEmpty {
                applyEditing(listing)
                loadAttributes()
            }
        } catch {
            var failed = state
            failed.editLoading = false
            failed.editError = ErrorMapper.message(for: error)
            state = failed
        }
    }

    /// Pré-remplit le formulaire depuis l'annonce (catégories déjà chargées : ids résolus par slug). Pas une saisie de
    /// l'utilisateur : ni `isDirty`, ni brouillon écrit (comme Android).
    private func applyEditing(_ listing: Listing) {
        let parentSlug = listing.parentCategorySlug ?? listing.categorySlug
        let parent = state.categories.first { $0.slug == parentSlug }
        let sub = parent?.children.first { $0.slug == listing.categorySlug }
        var s = state
        s.parentCategoryId = parent?.id
        s.subcategoryId = sub?.id
        s.attributeValues = listing.attributes
        s.title = listing.title
        s.description = listing.description
        s.priceType = listing.priceType
        s.price = listing.price.map { Self.priceText($0) } ?? ""
        s.wilayaId = listing.wilayaId
        s.communeId = listing.communeId
        s.listingPhone = TextCheck.nonBlank(listing.phone)
        s.showPhone = !TextCheck.isBlank(listing.phone)
        s.photos = listing.imageRefs.map { PhotoItem(localRef: $0.url, upload: $0, status: .done) }
        s.step = .review
        state = s
        if let wilayaId = listing.wilayaId {
            loadCommunes(wilayaId)
        }
        editing = nil
    }

    /// Prix entier sans décimale (« 1900000 »), sinon tel quel (Android : `toLong()` ou `toString()`).
    private static func priceText(_ price: Double) -> String {
        if price.truncatingRemainder(dividingBy: 1) == 0, Swift.abs(price) < 1e15 {
            return String(Int64(price))
        }
        return String(price)
    }

    private func runLoadWilayas() async {
        guard let list = try? await geo.wilayas() else { return }
        state.wilayas = list
    }

    @discardableResult
    private func loadCommunes(_ wilayaId: Int) -> Task<Void, Never> {
        communesTask?.cancel()
        let task = start(.communes(wilayaId: wilayaId))
        communesTask = task
        return task
    }

    private func runLoadCommunes(_ wilayaId: Int) async {
        // Une tâche annulée avant d'avoir commencé ne touche à rien (Android : jamais lancée).
        guard !Task.isCancelled else { return }
        state.communesLoading = true
        do {
            let list = try await geo.communes(wilayaId: wilayaId)
            guard !Task.isCancelled else { return }
            var loaded = state
            loaded.communesLoading = false
            loaded.communes = list
            state = loaded
        } catch {
            guard !Task.isCancelled else { return }
            var failed = state
            failed.communesLoading = false
            failed.communes = []
            state = failed
        }
    }

    @discardableResult
    private func loadAttributes() -> Task<Void, Never>? {
        let s = state
        guard let parentSlug = s.parentCategory?.slug else { return nil }
        attributesTask?.cancel()
        let task = start(.attributes(parentSlug: parentSlug, subcategorySlug: s.subcategory?.slug, language: locale()))
        attributesTask = task
        return task
    }

    private func runLoadAttributes(parentSlug: String, subcategorySlug: String?, language: String) async {
        guard !Task.isCancelled else { return }
        var loading = state
        // Nouvelle tentative : le message de l'échec précédent ne reste pas affiché par-dessus un succès.
        if loading.attributesError {
            loading.errorMessage = nil
        }
        loading.attributesLoading = true
        loading.attributesError = false
        state = loading
        do {
            let set = try await attributeRepository.attributes(
                categorySlug: parentSlug,
                subcategory: subcategorySlug,
                locale: language
            )
            guard !Task.isCancelled else { return }
            var loaded = state
            loaded.attributesLoading = false
            loaded.attributeSet = set
            // Une étape ATTRIBUTES restaurée sans attributs → on continue sur DETAILS.
            if loaded.step == .attributes && set.attributes.isEmpty {
                loaded.step = .details
            }
            state = loaded
            // Brouillon ou édition : options des selects dépendants dont le parent a une valeur.
            let values = state.attributeValues
            for definition in set.attributes {
                guard let parent = definition.dependsOn, !TextCheck.isBlank(values[parent]) else { continue }
                refreshDependent(definition.key)
            }
        } catch {
            guard !Task.isCancelled else { return }
            // `attributeSet` reste nil : « Suivant » relance le chargement au lieu d'avancer (voir `next`).
            var failed = state
            failed.attributesLoading = false
            failed.attributesError = true
            failed.errorMessage = ErrorMapper.message(for: error)
            state = failed
        }
    }

    @discardableResult
    private func refreshDependent(_ key: String) -> Task<Void, Never>? {
        let s = state
        guard let parentSlug = s.parentCategory?.slug else { return nil }
        dependentTask?.cancel()
        let task = start(.dependent(
            key: key,
            parentSlug: parentSlug,
            subcategorySlug: s.subcategory?.slug,
            context: s.attributeValues,
            language: locale()
        ))
        dependentTask = task
        return task
    }

    private func runRefreshDependent(
        key: String,
        parentSlug: String,
        subcategorySlug: String?,
        context: [String: String],
        language: String
    ) async {
        guard !Task.isCancelled else { return }
        let options = try? await attributeRepository.dependentOptions(
            categorySlug: parentSlug,
            subcategory: subcategorySlug,
            key: key,
            context: context,
            locale: language
        )
        guard let options, !Task.isCancelled else { return }
        state.dependentOptions[key] = options
    }

    /// La réponse de connexion ne porte ni téléphone ni `isRecommended` : profil relu (bascule téléphone, 5 / 8 photos).
    private func refreshProfile() {
        start(.profile)
    }

    private func runRefreshProfile() async {
        guard let me = try? await users.me() else { return }
        var s = state
        s.userPhone = TextCheck.nonBlank(me.phone)
        s.maxPhotos = me.maxImages
        state = s
    }

    // MARK: - Photos (interne)

    private func runPickPhotos(_ images: [Data], after previous: Task<Void, Never>?, generation started: Int) async {
        if let previous {
            await previous.value
        }
        guard started == generation, !Task.isCancelled else { return }
        // Doublons : déjà dans le formulaire, ou deux fois dans le même choix.
        var known = Set(state.photos.map { $0.localRef })
        var fresh: [(ref: String, data: Data)] = []
        for data in images {
            let ref = PostPhotoStore.ref(for: data)
            if known.insert(ref).inserted {
                fresh.append((ref: ref, data: data))
            }
        }
        let accepted = Array(fresh.prefix(state.remainingPhotoSlots))
        var saved: [String] = []
        var saveFailed = false
        for item in accepted {
            do {
                let ref = try await photoStore.save(item.data)
                saved.append(ref)
            } catch {
                // Disque plein… : la photo est écartée, un avis l'explique.
                saveFailed = true
            }
        }
        guard started == generation, !Task.isCancelled else {
            // Formulaire remis à zéro pendant l'écriture : ces fichiers ne serviront pas.
            for ref in saved where !state.photos.contains(where: { $0.localRef == ref }) {
                photoStore.remove(ref)
            }
            return
        }
        let present = Set(state.photos.map { $0.localRef })
        let added = Array(saved.filter { !present.contains($0) }.prefix(state.remainingPhotoSlots))
        let limited = fresh.count > accepted.count
        update { s in
            s.photos += added.map { PhotoItem(localRef: $0) }
            if limited {
                s.photosBanner = WeydaBanner(L10n.postPhotosLimit(s.maxPhotos), symbol: "photo.on.rectangle", kind: .info)
            } else if saveFailed {
                s.photosBanner = AccountBanner.failure(L10n.errorPhotoRead)
            } else {
                s.photosBanner = nil
            }
            s.errorMessage = nil
        }
        if !added.isEmpty {
            processUploadQueue()
        }
    }

    @discardableResult
    private func processUploadQueue() -> Task<Void, Never>? {
        if let uploadTask { return uploadTask }
        let task = start(.uploads(generation: generation))
        uploadTask = task
        return task
    }

    /// Envois séquentiels (30 / 10 min côté serveur) ; une photo retirée pendant l'envoi est simplement ignorée.
    private func runUploadQueue(generation started: Int) async {
        while started == generation, !Task.isCancelled {
            guard let next = state.photos.first(where: { $0.status == .uploading && $0.upload == nil }) else {
                uploadTask = nil
                return
            }
            let ref = next.localRef
            let outcome = await uploadPhoto(ref)
            guard started == generation, !Task.isCancelled else { return }
            update { s in
                s.photos = s.photos.map { (photo: PhotoItem) -> PhotoItem in
                    guard photo.localRef == ref, photo.status == .uploading else { return photo }
                    var updated = photo
                    switch outcome {
                    case .uploaded(let image):
                        updated.upload = image
                        updated.status = .done
                        updated.errorMessage = nil
                    case .failed(let message):
                        updated.status = .failed
                        updated.errorMessage = message
                    }
                    return updated
                }
            }
        }
    }

    /// Fichier relu (absent → « illisible », Android : `ImageReadException`) puis envoyé.
    private func uploadPhoto(_ ref: String) async -> PhotoOutcome {
        let data: Data
        do {
            data = try await photoStore.load(ref)
        } catch {
            return .failed(L10n.errorPhotoRead)
        }
        do {
            let image = try await uploads.upload(imageData: data)
            return .uploaded(image)
        } catch {
            return .failed(ErrorMapper.message(for: error) ?? L10n.errorGeneric)
        }
    }

    // MARK: - Soumission (interne)

    private func runSubmit(_ submission: ListingSubmission) async {
        do {
            let listing: Listing
            if let editingId {
                listing = try await annonces.update(id: editingId, submission)
            } else {
                listing = try await annonces.create(submission)
            }
            drafts.clear()
            photoStore.purge(keeping: [])
            var done = state
            done.isSubmitting = false
            done.result = listing
            state = done
            // L'écran de résultat paraît : une vibration de réussite, une seule (pas de bannière ici).
            Haptics.success()
            // Note App Store : une publication compte, une modification non.
            if editingId == nil {
                asksForReview = reviewPrompter.record(.listingPublished)
            }
        } catch {
            submitFailed(error)
        }
    }

    /// Renvoie l'utilisateur sur l'étape fautive quand le serveur précise le champ.
    private func submitFailed(_ error: any Error) {
        let apiError = error as? APIError
        let fields = ErrorMapper.fieldMessages(for: error)
        if let apiError, !apiError.attributeErrors.isEmpty {
            let attributeErrors = ErrorMapper.attributeMessages(for: error)
            update { s in
                s.isSubmitting = false
                if s.steps.contains(.attributes) { s.step = .attributes }
                s.attributeErrors = attributeErrors
                s.errorMessage = L10n.errorInvalidAttributes
            }
        } else if !fields.isEmpty {
            update { s in
                s.isSubmitting = false
                s.step = .details
                s.titleError = fields["title"]
                s.descriptionError = fields["description"]
                s.priceError = fields["price"]
                s.errorMessage = L10n.errorInvalidData
            }
        } else if let apiError, apiError.code == "maxImagesExceeded" {
            let message = ErrorMapper.message(for: error)
            update { s in
                s.isSubmitting = false
                s.step = .photos
                s.maxPhotos = apiError.maxImages ?? s.maxPhotos
                s.errorMessage = message
            }
        } else if let apiError, apiError.status == 429 {
            update { s in
                s.isSubmitting = false
                s.errorMessage = L10n.errorPostRateLimited
            }
        } else {
            let message = ErrorMapper.message(for: error)
            update { s in
                s.isSubmitting = false
                s.errorMessage = message
            }
        }
    }

    // MARK: - Validation

    private func validateStep(_ step: PostStep, in s: PostListingState) -> Bool {
        switch step {
        case .category:
            if s.isCategoryComplete { return true }
            update { s in s.categoryError = L10n.validationCategoryRequired }
            return false
        case .attributes:
            let errors = Validators.attributes(
                s.attributeSet?.attributes ?? [],
                values: s.attributeValues,
                optionsFor: { s.optionsFor($0) }
            )
            let messages: [String: String] = errors.mapValues { $0.text }
            update { s in s.attributeErrors = messages }
            return errors.isEmpty
        case .details:
            let titleError = Validators.title(s.title)?.text
            let descriptionError = Validators.description(s.description)?.text
            let priceError = Validators.price(s.price, type: s.priceType)?.text
            update { s in
                s.titleError = titleError
                s.descriptionError = descriptionError
                s.priceError = priceError
            }
            return titleError == nil && descriptionError == nil && priceError == nil
        case .photos:
            guard s.photos.contains(where: { $0.status == .failed }) else { return true }
            update { s in s.errorMessage = L10n.postPhotosFailedHint }
            return false
        case .location, .review:
            return true
        }
    }

    // MARK: - Session

    private func sessionUserChanged(_ user: User?) {
        let id = user?.id
        if id != observedUserId {
            observedUserId = id
            onAccountChanged(user)
        }
        let verified = user?.emailVerified ?? true
        if state.emailVerified != verified {
            state.emailVerified = verified
        }
    }

    /// Déconnexion volontaire ou connexion d'un AUTRE compte : le brouillon est effacé. Session tombée d'elle-même
    /// (refresh refusé pendant un envoi de photo…) : il est gardé, et le même compte le retrouve en se reconnectant.
    /// `user` vient du publieur (`$user` émet AVANT le changement : `auth.user` a encore l'ancienne valeur).
    private func onAccountChanged(_ user: User?) {
        let keepDraft: Bool
        if let user {
            keepDraft = user.id == draftOwnerId
        } else {
            keepDraft = auth.sessionExpired
        }
        if !keepDraft && editingId == nil {
            clearDraft()
        }
        if let user {
            draftOwnerId = user.id
        }
        var s = state
        s.userPhone = TextCheck.nonBlank(user?.phone)
        s.maxPhotos = user?.maxImages ?? 5
        s.showPhone = keepDraft && s.showPhone
        state = s
        if user != nil {
            refreshProfile()
        }
    }

    // MARK: - Brouillon (interne)

    /// Modification venue de l'utilisateur : état marqué modifié, brouillon écrit.
    private func update(_ transform: (inout PostListingState) -> Void) {
        var next = state
        transform(&next)
        next.isDirty = true
        state = next
        persist()
    }

    private func persist() {
        let s = state
        let draft = PostDraft(
            ownerId: draftOwnerId ?? auth.user?.id,
            listingPhone: s.listingPhone,
            dirty: s.isDirty,
            parentCategoryId: s.parentCategoryId,
            subcategoryId: s.subcategoryId,
            attributeValues: s.attributeValues,
            title: s.title,
            description: s.description,
            priceType: s.priceType.rawValue,
            price: s.price,
            wilayaId: s.wilayaId,
            communeId: s.communeId,
            showPhone: s.showPhone,
            step: s.step.rawValue,
            photos: s.photos.map { (photo: PhotoItem) -> PostDraft.Photo in
                PostDraft.Photo(
                    localRef: photo.localRef,
                    url: photo.upload?.url,
                    thumbnailUrl: photo.upload?.thumbnailUrl,
                    publicId: photo.upload?.publicId
                )
            }
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        drafts.write(String(decoding: data, as: UTF8.self))
    }

    /// Reprend le brouillon enregistré ; `false` s'il n'y en a pas, s'il est illisible, ou s'il appartient à un autre
    /// compte (il est alors effacé).
    private func restoreDraft() -> Bool {
        guard let raw = drafts.read(),
              let draft = try? JSONDecoder().decode(PostDraft.self, from: Data(raw.utf8)) else { return false }
        let currentUser = auth.user?.id
        if let owner = draft.ownerId, let currentUser, owner != currentUser {
            drafts.clear()
            return false
        }
        draftOwnerId = draft.ownerId ?? currentUser
        var s = state
        s.listingPhone = draft.listingPhone
        s.isDirty = draft.dirty
        s.editLoading = false
        s.parentCategoryId = draft.parentCategoryId
        s.subcategoryId = draft.subcategoryId
        s.attributeValues = draft.attributeValues
        s.title = draft.title
        s.description = draft.description
        s.priceType = PriceType.from(draft.priceType)
        s.price = draft.price
        s.wilayaId = draft.wilayaId
        s.communeId = draft.communeId
        s.showPhone = draft.showPhone && (s.userPhone != nil || draft.listingPhone != nil)
        s.step = PostStep(rawValue: draft.step) ?? .category
        s.photos = draft.photos.map { (photo: PostDraft.Photo) -> PhotoItem in
            var upload: UploadedImage? = nil
            if let url = photo.url, let publicId = photo.publicId {
                upload = UploadedImage(url: url, thumbnailUrl: photo.thumbnailUrl, publicId: publicId)
            }
            return PhotoItem(localRef: photo.localRef, upload: upload, status: upload == nil ? .uploading : .done)
        }
        state = s
        return true
    }
}
