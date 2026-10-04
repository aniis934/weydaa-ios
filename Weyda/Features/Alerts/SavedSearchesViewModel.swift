import Foundation

/// Catalogue déjà chargé par l'app (caches mémoire de `CategoryRepository` et `GeoRepository`) : de quoi écrire les
/// critères d'une alerte dans la langue de l'app.
nonisolated struct AlertCatalog: Equatable, Sendable {
    var categories: [Category] = []
    var wilayas: [Wilaya] = []
    /// Communes des seules wilayas dont une alerte vise une commune.
    var communes: [Int: [Commune]] = [:]
}

/// État de « Mes alertes » — portage de `SavedSearchesUiState` (SavedSearchesScreen.kt), plus le catalogue des
/// libellés et la bannière du bas.
nonisolated struct SavedSearchesState: Equatable, Sendable {
    var items: [SavedSearch] = []
    var isLoading: Bool = true
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    /// Erreur du chargement complet (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    var catalog: AlertCatalog = AlertCatalog()
    /// Bannière du bas : « Alerte supprimée » + « Annuler », refus du serveur, rafraîchissement impossible ; effacée
    /// par `bannerDismissed()`.
    var banner: WeydaBanner? = nil
}

/// Suppression d'alerte en attente (« Annuler » encore possible) : l'alerte et sa place dans la liste.
private nonisolated struct DeferredAlertDeletion: Sendable {
    let alert: SavedSearch
    let index: Int
}

/// « Mes alertes » (recherches sauvegardées) — portage de `SavedSearchesViewModel` (Android) : liste, suppression
/// DIFFÉRÉE sans boîte de confirmation (la ligne part tout de suite, « Annuler » la remet ; la requête part à la
/// fermeture de la bannière, à la suppression suivante ou en quittant l'écran ; l'alerte revient à sa place si le
/// serveur refuse), ouverture (les paramètres sont déposés dans `SearchRepository.pendingParams`, que l'onglet Annonces
/// applique de lui-même — y compris s'il n'a encore jamais été affiché : il les lit à sa création). Les critères se
/// lisent avec le catalogue (catégories, wilayas, communes), chargé en silence. Chaque action renvoie sa tâche
/// (`@discardableResult`).
final class SavedSearchesViewModel: ObservableObject {
    @Published private(set) var state = SavedSearchesState()
    /// Alertes au plus par compte (compteur « n / 5 »).
    let limit: Int

    /// Préfixe de l'action « Annuler » d'une suppression : `alert:<id>`.
    static let undoPrefix = "alert:"

    private let savedSearches: SavedSearchesRepository
    private let search: SearchRepository
    private let categories: CategoryRepository
    private let geo: GeoRepository
    private var loadTask: Task<Void, Never>?
    /// Dernier remplissage du catalogue : le suivant l'attend (les caches des repositories rendent la suite immédiate).
    private var catalogTask: Task<Void, Never>?
    private var hasAppeared = false
    /// Suppressions en attente ou envoyées et pas encore confirmées : une relecture ne doit pas les rendre.
    private var pendingDeletions: Set<String> = []
    /// Suppression que la bannière propose encore d'annuler (pas encore envoyée).
    private var deferred: DeferredAlertDeletion?

    init(savedSearches: SavedSearchesRepository, search: SearchRepository, categories: CategoryRepository, geo: GeoRepository) {
        self.savedSearches = savedSearches
        self.search = search
        self.categories = categories
        self.geo = geo
        self.limit = SavedSearchesRepository.maxSavedSearches
    }

    // MARK: - Chargement

    /// Premier affichage : chargement complet ; chaque retour sur l'écran : relecture silencieuse — une alerte créée
    /// depuis l'onglet Annonces y paraît.
    @discardableResult
    func appear() -> Task<Void, Never>? {
        guard hasAppeared else {
            hasAppeared = true
            return load()
        }
        return refreshSilently()
    }

    /// Chargement complet (premier affichage, « Réessayer »), puis le catalogue des libellés.
    @discardableResult
    func load() -> Task<Void, Never> {
        loadTask?.cancel()
        state.isLoading = true
        state.isRefreshing = false
        state.errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await self.savedSearches.list()
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.items = self.shown(list)
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.errorMessage = ErrorMapper.message(for: error) ?? L10n.errorGeneric
                return
            }
            await self.loadCatalog().value
        }
        loadTask = task
        return task
    }

    /// Tirer pour rafraîchir : la liste reçue remplace l'ancienne ; un échec la laisse et donne un message.
    func pullToRefresh() async {
        let current = state
        guard !current.isLoading, !current.isRefreshing else { return }
        guard current.errorMessage == nil else {
            await load().value
            return
        }
        state.isRefreshing = true
        do {
            let list = try await savedSearches.list()
            state.items = shown(list)
        } catch {
            showError(error)
        }
        state.isRefreshing = false
        await loadCatalog().value
    }

    // MARK: - Ouverture

    /// Dépose les paramètres pour l'onglet Annonces (qui les applique puis relance la recherche) ; l'écran bascule
    /// ensuite sur cet onglet, revenu à sa racine.
    func open(_ alert: SavedSearch) {
        search.pendingParams = alert.params
    }

    // MARK: - Suppression

    /// Glisser → « Supprimer l'alerte » : la ligne part tout de suite et la bannière « Alerte supprimée » propose
    /// « Annuler ». La requête n'est PAS encore envoyée : elle part à la fermeture de la bannière, à la suppression
    /// suivante (renvoyée ici : la suppression précédente, envoyée maintenant) ou en quittant l'écran.
    @discardableResult
    func delete(_ alert: SavedSearch) -> Task<Void, Never>? {
        let previous = commitPendingDeletion()
        guard let index = state.items.firstIndex(where: { $0.id == alert.id }) else { return previous }
        state.items.remove(at: index)
        pendingDeletions.insert(alert.id)
        deferred = DeferredAlertDeletion(alert: alert, index: index)
        // Pas de vibration ici : le glissement plein en donne déjà une (UIKit).
        state.banner = WeydaBanner(
            L10n.listsAlertDeleted,
            symbol: "trash",
            kind: .info,
            action: .undo(Self.undoPrefix + alert.id)
        )
        return previous
    }

    /// Action de la bannière. « Annuler » : la suppression en attente est abandonnée, l'alerte revient à SA place
    /// (rien n'a été envoyé).
    func bannerAction(_ action: BannerAction) {
        state.banner = nil
        guard let pending = deferred, action.id == Self.undoPrefix + pending.alert.id else { return }
        deferred = nil
        let alert = pending.alert
        pendingDeletions.remove(alert.id)
        if !state.items.contains(where: { $0.id == alert.id }) {
            state.items.insert(alert, at: min(pending.index, state.items.count))
        }
    }

    /// La bannière s'est fermée (délai écoulé, glissée) : la suppression en attente part au serveur.
    @discardableResult
    func bannerDismissed() -> Task<Void, Never>? {
        state.banner = nil
        return commitPendingDeletion()
    }

    /// L'écran disparaît (retour, autre onglet, alerte ouverte) : la suppression en attente part — jamais perdue — et
    /// « Annuler » n'est plus proposé.
    @discardableResult
    func disappear() -> Task<Void, Never>? {
        guard deferred != nil else { return nil }
        if state.banner?.action != nil {
            state.banner = nil
        }
        return commitPendingDeletion()
    }

    // MARK: - Interne

    /// Relecture sans indicateur (retour sur l'écran) ; un échec est ignoré.
    private func refreshSilently() -> Task<Void, Never>? {
        let current = state
        guard !current.isLoading, !current.isRefreshing, current.errorMessage == nil else { return nil }
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            guard let list = try? await self.savedSearches.list(), !Task.isCancelled else { return }
            self.state.items = self.shown(list)
            await self.loadCatalog().value
        }
        loadTask = task
        return task
    }

    /// Envoie la suppression en attente (s'il y en a une). La tâche tient le repository, pas l'écran : elle aboutit
    /// même si l'écran a disparu entre-temps.
    private func commitPendingDeletion() -> Task<Void, Never>? {
        guard let pending = deferred else { return nil }
        deferred = nil
        let alert = pending.alert
        let index = pending.index
        let repository = savedSearches
        return Task { [weak self] in
            do {
                try await repository.delete(id: alert.id)
                self?.deletionFinished(alert, at: index, error: nil)
            } catch {
                self?.deletionFinished(alert, at: index, error: error)
            }
        }
    }

    /// Réponse du serveur : succès (ou 404 = déjà supprimée, sur le site par exemple) → rien de plus, « Alerte
    /// supprimée » a déjà été dit ; refus → l'alerte revient à sa place avec le message d'erreur.
    private func deletionFinished(_ alert: SavedSearch, at index: Int, error: (any Error)?) {
        pendingDeletions.remove(alert.id)
        guard let error, !Self.isAlreadyDeleted(error) else { return }
        // Un rechargement a pu la remettre entre-temps : deux fois le même identifiant ferait planter la liste.
        if !state.items.contains(where: { $0.id == alert.id }) {
            state.items.insert(alert, at: min(index, state.items.count))
        }
        showError(error)
    }

    /// Bannière d'erreur (rien pour une annulation).
    private func showError(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else { return }
        state.banner = WeydaBanner(message, symbol: "exclamationmark.circle", kind: .error)
    }

    private static func isAlreadyDeleted(_ error: any Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        return apiError.status == 404
    }

    /// Remplit le catalogue (échecs silencieux : l'alerte garde son nom, sans les puces manquantes).
    @discardableResult
    private func loadCatalog() -> Task<Void, Never> {
        let previous = catalogTask
        let task = Task { [weak self] in
            _ = await previous?.value
            await self?.fillCatalog()
        }
        catalogTask = task
        return task
    }

    private func fillCatalog() async {
        if state.catalog.categories.isEmpty, let roots = try? await categories.roots() {
            state.catalog.categories = roots
        }
        if state.catalog.wilayas.isEmpty, let list = try? await geo.wilayas() {
            state.catalog.wilayas = list
        }
        for wilayaId in SavedSearchCriteria.communeWilayas(in: state.items) where state.catalog.communes[wilayaId] == nil {
            if let list = try? await geo.communes(wilayaId: wilayaId) {
                state.catalog.communes[wilayaId] = list
            }
        }
    }

    private func shown(_ list: [SavedSearch]) -> [SavedSearch] {
        let pending = pendingDeletions
        guard !pending.isEmpty else { return list }
        return list.filter { !pending.contains($0.id) }
    }
}

// MARK: - Critères lisibles

/// Pictogramme d'un critère : icône du jeu Lucide de l'app (catégorie, lieu) ou symbole SF.
nonisolated enum AlertCriterionIcon: Hashable, Sendable {
    case asset(String)
    case symbol(String)
}

nonisolated enum AlertCriterionKind: String, Hashable, Sendable {
    case keyword, category, location, priceType, price, featured, attributes
}

/// Un critère d'alerte en clair (« « clio » », « Voitures », « Bab Ezzouar, Alger », « ≤ 150 000 DA »…).
nonisolated struct AlertCriterion: Hashable, Sendable, Identifiable {
    let kind: AlertCriterionKind
    let title: String
    let icon: AlertCriterionIcon

    var id: AlertCriterionKind { kind }
}

/// Critères d'une alerte, lus dans ses `params` (clés d'URL du site) avec le catalogue de l'app, dans l'ordre des puces
/// de l'onglet Annonces. Un libellé introuvable (catalogue pas encore chargé, slug inconnu) n'est pas montré : le nom
/// de l'alerte, composé par le serveur, reste le repli. Logique pure, testable.
nonisolated enum SavedSearchCriteria {
    static func criteria(for params: [String: String], catalog: AlertCatalog, language: String = WeydaLocale.language) -> [AlertCriterion] {
        var result: [AlertCriterion] = []
        if let keyword = TextCheck.nonBlank(params["q"]) {
            let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(AlertCriterion(kind: .keyword, title: L10n.listsAlertKeyword(text), icon: .symbol("magnifyingglass")))
        }
        if let categoryChip = categoryCriterion(params, catalog: catalog, language: language) {
            result.append(categoryChip)
        }
        if let locationChip = locationCriterion(params, catalog: catalog, language: language) {
            result.append(locationChip)
        }
        if let raw = params["priceType"], let type = PriceType.allCases.first(where: { $0.rawValue == raw }) {
            result.append(AlertCriterion(kind: .priceType, title: ListingsFilterRules.priceTypeTitle(type), icon: .symbol("tag")))
        }
        if let price = ListingsFilterRules.priceTitle(min: params["priceMin"] ?? "", max: params["priceMax"] ?? "") {
            result.append(AlertCriterion(kind: .price, title: price, icon: .symbol("banknote")))
        }
        if params["featured"] == "1" || params["featured"] == "true" {
            result.append(AlertCriterion(kind: .featured, title: L10n.filtersFeaturedChip, icon: .symbol("star")))
        }
        // Filtres d'attributs : leur nombre seulement (« +2 filtres », comme le nom composé par le serveur) — leurs
        // libellés demanderaient les définitions de chaque catégorie.
        let attributeCount: Int = params.keys.filter { $0.hasPrefix("attr_") }.count
        if attributeCount > 0 {
            result.append(AlertCriterion(kind: .attributes, title: L10n.listsAlertMoreFilters(attributeCount), icon: .symbol("slider.horizontal.3")))
        }
        return result
    }

    /// Sous-catégorie (celle des paramètres, ou une sous-catégorie passée pour `category`, que l'onglet Annonces
    /// accepte aussi), sinon la catégorie racine ; icône de la racine.
    static func categoryCriterion(_ params: [String: String], catalog: AlertCatalog, language: String) -> AlertCriterion? {
        let roots: [Category] = catalog.categories
        let rawCategory: String? = TextCheck.nonBlank(params["category"])
        let rawSubcategory: String? = TextCheck.nonBlank(params["subcategory"])
        guard !roots.isEmpty, rawCategory != nil || rawSubcategory != nil else { return nil }
        let root: Category? = roots.first(where: { $0.slug == rawCategory })
        let parents: [Category] = root.map { [$0] } ?? roots
        let childSlug: String? = rawSubcategory ?? (root == nil ? rawCategory : nil)
        if let childSlug, let match = child(childSlug, in: parents) {
            let title = match.child.name.resolve(language)
            if !TextCheck.isBlank(title) {
                return AlertCriterion(kind: .category, title: title, icon: .asset(CategoryIcon.assetName(forSlug: match.parent.slug)))
            }
        }
        guard let root else { return nil }
        let title = root.name.resolve(language)
        guard !TextCheck.isBlank(title) else { return nil }
        return AlertCriterion(kind: .category, title: title, icon: .asset(CategoryIcon.assetName(forSlug: root.slug)))
    }

    /// « Bab Ezzouar, Alger » (commune si elle est connue, puis wilaya), épingle de l'app.
    static func locationCriterion(_ params: [String: String], catalog: AlertCatalog, language: String) -> AlertCriterion? {
        guard let raw = params["wilaya"], let wilayaId = Int(raw),
              let wilaya = catalog.wilayas.first(where: { $0.id == wilayaId }) else { return nil }
        var commune: Commune? = nil
        if let rawCommune = params["commune"], let communeId = Int(rawCommune) {
            commune = catalog.communes[wilayaId]?.first(where: { $0.id == communeId })
        }
        guard let place = ListingText.place(wilaya: wilaya.name, commune: commune?.name, language: language) else { return nil }
        return AlertCriterion(kind: .location, title: place, icon: .asset(CategoryIcon.place))
    }

    /// Wilayas dont il faut les communes (alertes qui visent une commune), sans doublon, dans l'ordre.
    static func communeWilayas(in alerts: [SavedSearch]) -> [Int] {
        var ids: Set<Int> = []
        for alert in alerts {
            guard alert.params["commune"] != nil, let raw = alert.params["wilaya"], let id = Int(raw) else { continue }
            ids.insert(id)
        }
        return ids.sorted()
    }

    /// Les puces par lignes de `perRow` (au moins 1) : les mises en page proposées à `ViewThatFits`.
    static func rows(_ criteria: [AlertCriterion], perRow: Int) -> [[AlertCriterion]] {
        let size = max(perRow, 1)
        var result: [[AlertCriterion]] = []
        var start = 0
        while start < criteria.count {
            let end = min(start + size, criteria.count)
            result.append(Array(criteria[start..<end]))
            start = end
        }
        return result
    }

    /// « Créée le 1 oct. 2026 » ; nil sans date.
    static func createdOn(_ alert: SavedSearch, locale: Locale = WeydaLocale.formatting, timeZone: TimeZone = .current) -> String? {
        guard let date = alert.createdAt else { return nil }
        return L10n.alertsCreatedOn(Format.date(date, locale: locale, timeZone: timeZone))
    }

    /// Compteur « Alertes : 3 / 5 » (fragment isolé de gauche à droite : « 3 / 5 » reste dans cet ordre en arabe).
    static func usage(count: Int, limit: Int) -> String {
        L10n.listsAlertsUsage(Format.ltrIsolate("\(count) / \(limit)"))
    }

    /// Ce que VoiceOver lit pour une alerte : nom, critères, date de création.
    static func accessibilityLabel(for alert: SavedSearch, criteria: [AlertCriterion]) -> String {
        var parts: [String] = [alert.name]
        parts.append(contentsOf: criteria.map { $0.title })
        if let created = createdOn(alert) {
            parts.append(created)
        }
        return parts.joined(separator: ", ")
    }

    private static func child(_ slug: String, in parents: [Category]) -> (parent: Category, child: Category)? {
        for parent in parents {
            if let match = parent.children.first(where: { $0.slug == slug }) {
                return (parent, match)
            }
        }
        return nil
    }
}
