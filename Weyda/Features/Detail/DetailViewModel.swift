import Combine
import Foundation

/// État de la fiche d'une annonce — `DetailUiState` (DetailViewModel.kt). Données pures (`nonisolated`) : l'écran
/// les reçoit telles quelles, les tests les lisent.
nonisolated struct DetailState: Equatable, Sendable {
    /// Premier chargement (squelette) ; « Réessayer » le remet à vrai.
    var isLoading: Bool = true
    /// Échec du chargement ; `errorMessage` dit pourquoi (hors ligne, serveur…).
    var isError: Bool = false
    var errorMessage: String? = nil
    /// 404 : annonce supprimée, vendue puis purgée, ou jamais publiée — « Réessayer » tournerait en boucle.
    var isNotFound: Bool = false
    var listing: Listing? = nil
    /// Avis du vendeur (3 premiers) ; nil tant qu'ils ne sont pas chargés ou en échec (section masquée).
    var reviews: ReviewSummary? = nil
    /// Définitions d'attributs de la catégorie : libellés traduits des clés, des options et des unités.
    var attributeSet: AttributeSet? = nil
    /// Utilisateur connecté ("" = visiteur).
    var userId: String = ""
    /// Cœur de la barre d'outils, toujours sur l'id RÉEL de l'annonce (jamais le slug d'un lien).
    var isFavorite: Bool = false
    /// « Annonces similaires » : même catégorie, sans l'annonce courante.
    var similar: [Listing] = []
    /// Numéro du vendeur, révélé à la demande (`GET /api/annonces/{id}/contact`, connexion requise, 5 / h).
    var revealedPhone: String? = nil
    var isRevealingPhone: Bool = false
    var isReportBusy: Bool = false
    /// Panne réseau pendant l'envoi d'un signalement : affichée DANS la feuille, restée ouverte.
    var reportError: String? = nil
    /// Message bref à montrer une fois (signalement envoyé, refus du serveur…), effacé par `noticeShown()`.
    var notice: String? = nil

    var isLoggedIn: Bool { !TextCheck.isBlank(userId) }

    var isOwner: Bool {
        guard isLoggedIn, let sellerId = listing?.seller?.id else { return false }
        return sellerId == userId
    }

    /// « Contacter » : annonce active qui n'est pas la mienne.
    var canContact: Bool {
        guard let listing else { return false }
        return !isOwner && listing.listingStatus == .active
    }

    /// « Faire une offre » : comme le site, exclu sur une annonce gratuite.
    var canMakeOffer: Bool {
        canContact && listing?.priceType != .free
    }

    /// « Signaler » : toute annonce chargée qui n'est pas la mienne (vendue comprise).
    var canReport: Bool {
        listing != nil && !isOwner
    }

    /// « Afficher le numéro » : annonce active d'un vendeur qui en a indiqué un.
    var canShowPhone: Bool {
        guard let listing else { return false }
        return !isOwner && listing.hasPhone && listing.listingStatus == .active
    }

    /// « Modifier » (propriétaire) : tant que l'annonce n'est pas vendue.
    var canEdit: Bool {
        guard let listing else { return false }
        return isOwner && listing.listingStatus != .sold
    }

    /// La barre d'actions du bas a au moins un bouton.
    var hasActions: Bool {
        canMakeOffer || canContact || canShowPhone || canEdit
    }

    /// Lignes « Caractéristiques » prêtes à afficher.
    var attributeRows: [DetailAttributeRow] {
        guard let listing else { return [] }
        return DetailAttributeRow.rows(attributes: listing.attributes, set: attributeSet)
    }
}

/// Fiche d'une annonce — portage de `DetailViewModel` (Android) : détail par id ou par slug, puis, en parallèle,
/// cœur resynchronisé, vue comptée, libellés des caractéristiques, avis du vendeur et annonces similaires ;
/// numéro à la demande, signalement. La messagerie (contacter, offre) arrive en phase 5 : `DetailView` s'en charge.
final class DetailViewModel: ObservableObject {
    @Published private(set) var state = DetailState()
    /// Feuille « Signaler » ouverte : liée à la présentation (un glissement vers le bas la ferme aussi).
    @Published var isReportPresented: Bool = false

    /// Identifiant OU slug reçu (lien profond, notification) ; l'id réel arrive avec la fiche.
    let idOrSlug: String

    private let annonces: AnnonceRepository
    private let favorites: FavoritesRepository
    private let reviewsRepository: ReviewsRepository
    private let attributesRepository: AttributeRepository
    private let conversations: ConversationsRepository
    private let reports: ReportsRepository
    /// Langue des libellés d'attributs (fixée par les tests). Changer de langue relance l'app sur iOS : pas de
    /// rechargement à chaud comme `onLocaleChanged` d'Android.
    private let locale: () -> String
    private var favoriteIds: Set<String> = []
    private var subscriptions: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var hasStarted: Bool = false
    private var viewCounted: Bool = false

    init(
        idOrSlug: String,
        annonces: AnnonceRepository,
        favorites: FavoritesRepository,
        reviews: ReviewsRepository,
        attributes: AttributeRepository,
        conversations: ConversationsRepository,
        reports: ReportsRepository,
        sessionUser: AnyPublisher<User?, Never>,
        locale: @escaping () -> String = { WeydaLocale.language }
    ) {
        self.idOrSlug = idOrSlug
        self.annonces = annonces
        self.favorites = favorites
        self.reviewsRepository = reviews
        self.attributesRepository = attributes
        self.conversations = conversations
        self.reports = reports
        self.locale = locale
        // Connexion faite DEPUIS la fiche : sans ce suivi, le propriétaire verrait « Contacter » sur sa propre annonce.
        sessionUser
            .map { $0?.id ?? "" }
            .removeDuplicates()
            .sink { [weak self] userId in
                self?.state.userId = userId
            }
            .store(in: &subscriptions)
        // Source de vérité partagée des cœurs : la fiche suit les autres écrans (et inversement).
        favorites.$ids
            .sink { [weak self] ids in
                self?.favoriteIds = ids
                self?.syncFavorite()
            }
            .store(in: &subscriptions)
    }

    // MARK: - Chargement

    /// Premier affichage (`.task`) : une seule fois, même si la vue réapparaît.
    func loadIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load()
    }

    /// Fiche puis compléments. Le travail vit dans une tâche du ViewModel (le `viewModelScope` d'Android) : ouvrir
    /// le profil du vendeur pendant le chargement — la vue disparaît, sa `.task` est annulée — ne l'interrompt pas.
    func load() async {
        loadTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    /// Tirer pour rafraîchir : la fiche reste affichée, un échec devient un message bref.
    func refresh() async {
        guard state.listing != nil else {
            await load()
            return
        }
        do {
            let listing = try await annonces.detail(idOrSlug: idOrSlug)
            state.listing = listing
            syncFavorite()
            async let labels: Void = loadAttributeLabels(for: listing)
            async let sellerReviews: Void = loadReviews(for: listing)
            async let similarListings: Void = loadSimilar(to: listing)
            _ = await (labels, sellerReviews, similarListings)
        } catch {
            if let message = ErrorMapper.message(for: error) {
                state.notice = message
            }
        }
    }

    private func performLoad() async {
        var next = state
        next.isLoading = true
        next.isError = false
        next.errorMessage = nil
        next.isNotFound = false
        state = next
        do {
            let listing = try await annonces.detail(idOrSlug: idOrSlug)
            guard !Task.isCancelled else { return }
            next = state
            next.listing = listing
            next.isLoading = false
            state = next
            syncFavorite()
            await loadCompanions(for: listing)
        } catch {
            // Annulation (nouveau chargement lancé) : rien à afficher, le suivant s'en charge.
            guard let message = ErrorMapper.message(for: error) else { return }
            next = state
            next.isLoading = false
            next.isError = true
            next.errorMessage = message
            next.isNotFound = (error as? APIError)?.status == 404
            state = next
        }
    }

    /// Ce qui accompagne la fiche, en parallèle ; chaque échec est silencieux (section masquée), comme Android.
    private func loadCompanions(for listing: Listing) async {
        async let favorite: Void = refreshFavorite(listing.id)
        async let view: Void = countView(of: listing)
        async let labels: Void = loadAttributeLabels(for: listing)
        async let sellerReviews: Void = loadReviews(for: listing)
        async let similarListings: Void = loadSimilar(to: listing)
        _ = await (favorite, view, labels, sellerReviews, similarListings)
    }

    /// Le lien peut porter un slug : l'état serveur du cœur est relu sur l'id réel.
    private func refreshFavorite(_ id: String) async {
        _ = try? await favorites.refresh(id)
    }

    /// Vue comptée comme sur le site (le serveur ignore le propriétaire et les rafales), une fois par ouverture.
    private func countView(of listing: Listing) async {
        guard !viewCounted else { return }
        if state.isLoggedIn, listing.seller?.id == state.userId { return }
        viewCounted = true
        await annonces.countView(id: listing.id)
    }

    /// Libellés traduits des caractéristiques ; contexte = valeurs de l'annonce (libellé du modèle ← marque).
    private func loadAttributeLabels(for listing: Listing) async {
        guard !listing.attributes.isEmpty else { return }
        guard let parent = TextCheck.nonBlank(listing.parentCategorySlug) ?? TextCheck.nonBlank(listing.categorySlug) else {
            return
        }
        let subcategory: String? = listing.categorySlug == parent ? nil : listing.categorySlug
        let set = try? await attributesRepository.attributes(
            categorySlug: parent,
            subcategory: subcategory,
            locale: locale(),
            context: listing.attributes
        )
        guard let set else { return }
        state.attributeSet = set
    }

    private func loadReviews(for listing: Listing) async {
        guard let sellerId = TextCheck.nonBlank(listing.seller?.id) else { return }
        guard let summary = try? await reviewsRepository.forSeller(sellerId) else { return }
        state.reviews = summary
    }

    private func loadSimilar(to listing: Listing) async {
        guard let items = try? await annonces.similar(to: listing) else { return }
        state.similar = items
    }

    // MARK: - Favori

    /// Bascule optimiste sur l'id RÉEL (un slug donnait 404). Le dépôt annule un refus ; il est annoncé ici.
    func toggleFavorite() async {
        let id = state.listing?.id ?? idOrSlug
        do {
            _ = try await favorites.toggle(id)
        } catch {
            if let message = ErrorMapper.message(for: error) {
                state.notice = message
            }
        }
    }

    private func syncFavorite() {
        let id = state.listing?.id ?? idOrSlug
        let favorite = favoriteIds.contains(id)
        if state.isFavorite != favorite {
            state.isFavorite = favorite
        }
    }

    // MARK: - Numéro du vendeur

    /// Le numéro n'est pas dans la fiche publique : le serveur le donne à un membre connecté, avec un débit limité
    /// (5 / h par compte, 2 / h par annonce) — comme le bouton du site.
    func revealPhone() async {
        guard let listing = state.listing, !state.isRevealingPhone, state.revealedPhone == nil else { return }
        state.isRevealingPhone = true
        do {
            let phone = try await conversations.revealPhone(annonceId: listing.id)
            var next = state
            next.isRevealingPhone = false
            if let number = TextCheck.nonBlank(phone) {
                next.revealedPhone = number
            } else {
                next.notice = L10n.errorNoPhone
            }
            state = next
        } catch {
            var next = state
            next.isRevealingPhone = false
            next.notice = ErrorMapper.message(for: error) ?? next.notice
            state = next
        }
    }

    // MARK: - Signalement

    func openReport() {
        guard state.canReport else { return }
        state.reportError = nil
        isReportPresented = true
    }

    /// Verdict du serveur (envoyé, déjà signalé, refus) : la feuille se ferme et le message s'affiche sur la fiche.
    /// Panne réseau : elle reste ouverte, les précisions saisies ne sont pas perdues.
    func confirmReport(reason: ReportReason, details: String) async {
        guard let listing = state.listing, !state.isReportBusy else { return }
        state.isReportBusy = true
        state.reportError = nil
        do {
            try await reports.report(annonceId: listing.id, reason: reason, details: details)
            state.isReportBusy = false
            isReportPresented = false
            state.notice = L10n.reportSent
        } catch {
            state.isReportBusy = false
            guard let message = ErrorMapper.message(for: error) else { return }
            if error is APIError {
                isReportPresented = false
                state.notice = message
            } else {
                state.reportError = message
            }
        }
    }

    // MARK: - Messages brefs

    func noticeShown() {
        state.notice = nil
    }
}

/// Une ligne « Caractéristiques » : libellé traduit et valeur lisible (logique pure, testée).
nonisolated struct DetailAttributeRow: Hashable, Sendable, Identifiable {
    let key: String
    let label: String
    let value: String

    var id: String { key }

    /// Dans l'ordre des définitions de la catégorie (celui du formulaire et du site), puis les clés inconnues par
    /// ordre alphabétique : un dictionnaire Swift n'a pas d'ordre (Android suivait l'ordre du JSON).
    static func rows(attributes: [String: String], set: AttributeSet?) -> [DetailAttributeRow] {
        var keys: [String] = []
        var seen: Set<String> = []
        for definition in set?.attributes ?? [] where attributes[definition.key] != nil && !seen.contains(definition.key) {
            keys.append(definition.key)
            seen.insert(definition.key)
        }
        keys += attributes.keys.filter { !seen.contains($0) }.sorted()
        return keys.compactMap { key -> DetailAttributeRow? in
            guard let raw = attributes[key], !TextCheck.isBlank(raw) else { return nil }
            let definition = set?.attribute(key)
            return DetailAttributeRow(
                key: key,
                label: Self.label(for: key, definition: definition),
                value: Self.display(raw, definition: definition)
            )
        }
    }

    /// Libellé traduit du serveur ; sinon la clé mise en forme (`body_type` → « Body Type »), comme Android.
    static func label(for key: String, definition: AttributeDefinition?) -> String {
        TextCheck.nonBlank(definition?.label) ?? AttributeDefinition.displayLabel(key.replacingOccurrences(of: "_", with: "-"))
    }

    /// Oui / Non, libellé de l'option, nombre suivi de son unité. Un nombre AVEC unité est groupé (« 145 000 km »,
    /// Android : « 145000 km ») ; sans unité il reste tel quel : une année ne s'écrit pas « 2 019 ».
    static func display(_ raw: String, definition: AttributeDefinition?) -> String {
        guard let definition else { return raw }
        switch definition.type {
        case .boolean:
            return raw == "true" ? L10n.attrYes : L10n.attrNo
        case .select:
            return definition.optionLabel(raw)
        case .number:
            guard let unit = TextCheck.nonBlank(definition.unitLabel) else { return raw }
            let number: String = Double(raw).map { Format.decimal($0) } ?? raw
            return "\(number) \(unit)"
        case .text:
            return raw
        }
    }
}

/// Adresses tirées d'une annonce (logique pure, testée).
nonisolated enum DetailLinks {
    /// Page de l'annonce sur le site, dans la langue de l'app (partage, contact provisoire) — jamais l'hôte de l'API.
    static func webURL(for listing: Listing, language: String = WeydaLocale.language) -> URL? {
        URL(string: listing.webUrl(host: DeepLinks.siteURL.absoluteString, locale: language))
    }

    /// `tel:` du numéro révélé : sa partie numérique seulement. Ce qui suit (« #12 », « (après 18 h) ») est laissé
    /// de côté et rien de saisi par le vendeur ne peut détourner l'adresse (Android : `Uri.fromParts("tel", …)`).
    /// nil sans chiffre.
    static func callURL(for phone: String) -> URL? {
        let allowed: Set<Character> = ["+", " ", "-", ".", "(", ")", "\u{00A0}"]
        var dialable = ""
        for character in Format.latinDigits(phone) {
            if character.isASCII && character.isNumber {
                dialable.append(character)
            } else if character == "+" && dialable.isEmpty {
                dialable.append(character)
            } else if !allowed.contains(character) {
                break
            }
        }
        guard dialable.contains(where: { $0.isNumber }) else { return nil }
        return URL(string: "tel:\(dialable)")
    }
}
