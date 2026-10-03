import Combine
import Foundation

/// Onglet Annonces — portage de `ListingsViewModel` (ui/listings, Android) : recherche (suggestions, historique,
/// « Vouliez-vous dire »), catégorie et sous-catégorie, filtres (feuille + puces), résultats paginés avec facettes,
/// tirer pour rafraîchir, relance au retour du réseau, alerte (recherche sauvegardée), favoris.
///
/// Critères d'ouverture (accueil, liens `/annonces?…`) : `start(with:)`, appelé par la vue à chaque ouverture de
/// l'onglet. Une alerte ouverte ailleurs dépose ses paramètres dans `SearchRepository.pendingParams`.
final class ListingsViewModel: ObservableObject {
    @Published private(set) var state = ListingsState()
    /// Suggestions serveur (dès 2 caractères) et historique local, partagé avec l'accueil.
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var history: [String] = []
    /// Cœurs des lignes (source de vérité : `FavoritesRepository`).
    @Published private(set) var favoriteIds: Set<String> = []

    /// Tâches en cours (recherche, page suivante, catalogue…) : `waitUntilIdle()` des tests.
    private(set) var activeWork = 0

    private let annonces: AnnonceRepository
    private let categoryRepository: CategoryRepository
    private let geo: GeoRepository
    private let attributeRepository: AttributeRepository
    private let searchRepository: SearchRepository
    private let favorites: FavoritesRepository
    private let savedSearches: SavedSearchesRepository
    /// Langue des libellés d'attributs (fixée par les tests ; sinon celle de l'app).
    private let locale: @MainActor @Sendable () -> String
    private let engine: SuggestionsEngine

    private var started = false
    private var categoriesLoading = false
    private var wilayasLoading = false
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var attributesTask: Task<Void, Never>?
    private var communesTask: Task<Void, Never>?
    /// Change à chaque recherche : la réponse (page 1 ou suivante) d'une recherche remplacée est ignorée.
    private var generation = 0
    /// Alerte ouverte avant le chargement des catégories : appliquée dès leur arrivée.
    private var paramsAwaitingCategories: [String: String]?
    /// Options de selects dépendants déjà demandées (une requête par valeur du parent).
    private var requestedDependentKeys: Set<String> = []
    private var wasOffline = false
    private var subscriptions: Set<AnyCancellable> = []

    init(
        annonces: AnnonceRepository,
        categories: CategoryRepository,
        geo: GeoRepository,
        attributes: AttributeRepository,
        search: SearchRepository,
        favorites: FavoritesRepository,
        savedSearches: SavedSearchesRepository,
        online: AnyPublisher<Bool, Never>? = nil,
        locale: @escaping @MainActor @Sendable () -> String = { WeydaLocale.language },
        suggestionsDebounce: TimeInterval = SuggestionsEngine.debounceInterval
    ) {
        self.annonces = annonces
        self.categoryRepository = categories
        self.geo = geo
        self.attributeRepository = attributes
        self.searchRepository = search
        self.favorites = favorites
        self.savedSearches = savedSearches
        self.locale = locale
        let repository = search
        self.engine = SuggestionsEngine(
            fetch: { [repository] query, language in
                try await repository.suggestions(query, locale: language)
            },
            history: repository.$history.eraseToAnyPublisher(),
            loadHistory: { [repository] in
                repository.loadHistory()
            },
            remember: { [repository] text in
                _ = repository.remember(text)
            },
            clearHistory: { [repository] in
                repository.clearHistory()
            },
            locale: locale,
            debounce: suggestionsDebounce
        )
        observe(online: online)
    }

    // MARK: - Ouverture

    /// Premier affichage de l'onglet (une fois), puis chaque ouverture avec des critères. Sans critère (`nil`,
    /// `ListingsLaunch()` : onglet touché, « Voir tout »), la recherche en cours est gardée.
    func start(with launch: ListingsLaunch?) {
        let params: [String: String] = launch.map { Self.parameters(of: $0) } ?? [:]
        guard started else {
            started = true
            if let launch, !params.isEmpty {
                // Comme les arguments de navigation d'Android : valeurs prises telles quelles, recherche immédiate
                // (une sous-catégorie passée pour `category` est résolue à l'arrivée des catégories).
                update { s in
                    s.query = TextCheck.nonBlank(launch.q) ?? ""
                    s.categorySlug = TextCheck.nonBlank(launch.category)
                    s.filters = ListingFilters(
                        subcategory: TextCheck.nonBlank(launch.subcategory),
                        wilayaId: launch.wilaya,
                        featuredOnly: launch.featured
                    )
                }
            }
            loadCatalog()
            if let slug = state.categorySlug {
                loadAttributes(slug, subcategory: state.filters.subcategory)
            }
            search()
            return
        }
        guard !params.isEmpty else { return }
        apply(params: params)
    }

    /// Critères d'ouverture → clés d'URL du site (celles des alertes) ; vide = aucun critère.
    static func parameters(of launch: ListingsLaunch) -> [String: String] {
        var params: [String: String] = [:]
        if let q = TextCheck.nonBlank(launch.q) { params["q"] = q }
        if let category = TextCheck.nonBlank(launch.category) { params["category"] = category }
        if let subcategory = TextCheck.nonBlank(launch.subcategory) { params["subcategory"] = subcategory }
        if let wilaya = launch.wilaya { params["wilaya"] = String(wilaya) }
        if launch.featured { params["featured"] = "1" }
        return params
    }

    // MARK: - Recherche et suggestions

    func onQueryChange(_ value: String) {
        update { $0.query = value }
        engine.onQueryChange(value)
    }

    /// Catégorie → filtre catégorie (mot-clé effacé ; une sous-catégorie sélectionne sa racine) ; wilaya → filtre
    /// localisation ; annonce → recherche du texte.
    func onSuggestionPick(_ suggestion: Suggestion) {
        engine.clearSuggestions()
        switch suggestion.type {
        case .category:
            update { $0.query = "" }
            guard let slug = suggestion.slug else { return }
            selectSuggestedCategory(slug)
        case .wilaya:
            // Comme le site : le mot tapé (« oran ») n'est pas un mot-clé, sinon on ne garderait que les annonces
            // d'Oran dont le TEXTE contient « oran ».
            guard let wilayaId = suggestion.id else { return }
            update { $0.query = "" }
            updateFilters { filters in
                filters.wilayaId = wilayaId
                filters.communeId = nil
            }
        case .listing:
            update { $0.query = suggestion.text }
            search()
        }
    }

    /// « Vouliez-vous dire … ? » : la correction devient le mot-clé.
    func onDidYouMean(_ suggestion: String) {
        update { s in
            s.query = suggestion
            s.didYouMean = nil
        }
        search()
    }

    func onHistoryPick(_ text: String) {
        update { $0.query = text }
        search()
    }

    func clearHistory() {
        engine.clearHistory()
    }

    /// Changer de catégorie efface sous-catégorie, attributs et facettes ; lieu, prix et tri sont gardés.
    func onCategorySelect(_ slug: String?) {
        selectCategory(slug, subcategory: nil)
    }

    /// Puce de sous-catégorie en accès rapide (sous les catégories) : nouvel appui = retrait.
    func onSubcategoryToggle(_ slug: String) {
        let selected = state.filters.subcategory == slug
        updateFilters { filters in
            filters.subcategory = selected ? nil : slug
            filters.attributes = [:]
        }
    }

    func toggleFavorite(_ listing: Listing) {
        favorites.toggleDetached(listing.id)
    }

    // MARK: - Filtres

    /// Les communes suivent le brouillon de la feuille : à l'ouverture, elles sont réalignées sur la wilaya
    /// APPLIQUÉE (venue de l'accueil, d'une suggestion ou d'une alerte), sinon « Commune » resterait vide.
    func openFilters() {
        update { $0.showFilters = true }
        onFilterWilayaChange(state.filters.wilayaId)
    }

    func closeFilters() {
        update { $0.showFilters = false }
    }

    /// Wilaya choisie dans la feuille : charge ses communes (le brouillon reste dans la feuille).
    func onFilterWilayaChange(_ wilayaId: Int?) {
        communesTask?.cancel()
        update { $0.communes = [] }
        guard let wilayaId else { return }
        communesTask = run { [weak self] in
            guard let self else { return }
            guard let list = try? await self.geo.communes(wilayaId: wilayaId), !Task.isCancelled else { return }
            self.update { $0.communes = list }
        }
    }

    func applyFilters(_ filters: ListingFilters) {
        let previousSubcategory = state.filters.subcategory
        update { s in
            s.filters = filters
            s.showFilters = false
        }
        if filters.subcategory != previousSubcategory, let slug = state.categorySlug {
            loadAttributes(slug, subcategory: filters.subcategory)
        }
        search()
    }

    /// Modification des filtres appliqués (puces) puis nouvelle recherche.
    func updateFilters(_ change: (inout ListingFilters) -> Void) {
        var filters = state.filters
        change(&filters)
        applyFilters(filters)
    }

    /// Retrait d'une puce de filtre actif.
    func removeFilter(_ kind: ListingsChipKind) {
        applyFilters(ListingsFilterRules.removing(kind, from: state.filters))
    }

    func clearFilters() {
        applyFilters(ListingFilters())
    }

    /// Feuille de filtres : options des selects dépendants (modèles d'une marque) dont le parent a une valeur dans le
    /// brouillon — `ctx_<parent>` côté API. Une requête par valeur de parent ; un échec laisse la facette complète.
    func loadDependentOptions(subcategory: String?, attributes: [String: String]) {
        guard let slug = state.categorySlug, let attributeSet = state.attributeSet else { return }
        let language = locale()
        for definition in attributeSet.attributes where definition.filterable {
            guard let parent = definition.dependsOn, let parentValue = TextCheck.nonBlank(attributes[parent]) else { continue }
            let key = ListingsState.dependentKey(definition.key, parentValue: parentValue)
            guard state.dependentOptions[key] == nil, !requestedDependentKeys.contains(key) else { continue }
            requestedDependentKeys.insert(key)
            let attributeKey = definition.key
            run { [weak self] in
                guard let self else { return }
                do {
                    let options = try await self.attributeRepository.dependentOptions(
                        categorySlug: slug,
                        subcategory: subcategory,
                        key: attributeKey,
                        context: [parent: parentValue],
                        locale: language
                    )
                    guard self.state.categorySlug == slug else { return }
                    self.update { $0.dependentOptions[key] = options }
                } catch {
                    self.requestedDependentKeys.remove(key)
                }
            }
        }
    }

    // MARK: - Alerte

    /// « Créer une alerte » (membre connecté : la vue envoie un visiteur vers la connexion).
    func saveSearch() {
        guard state.canSaveSearch else { return }
        let params = state.toSearchParams()
        update { s in
            s.isSavingSearch = true
            s.notice = nil
        }
        run { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.savedSearches.create(params: params)
                self.update { s in
                    s.isSavingSearch = false
                    s.notice = outcome.duplicate ? .alertDuplicate : .alertCreated
                }
            } catch {
                let message = ErrorMapper.message(for: error)
                self.update { s in
                    s.isSavingSearch = false
                    s.notice = message.map { ListingsNotice.message($0) }
                }
            }
        }
    }

    func noticeShown() {
        update { $0.notice = nil }
    }

    // MARK: - Résultats

    func search() {
        search(refreshing: false)
    }

    /// Tirer pour rafraîchir : même recherche, la liste reste affichée jusqu'à la réponse ; le catalogue manquant
    /// (catégories, wilayas) est relu au passage.
    func refresh() async {
        guard !state.isLoading, !state.isRefreshing else { return }
        loadCatalog()
        await search(refreshing: true).value
    }

    /// « Réessayer » en bas de liste après l'échec d'une page suivante.
    func retryLoadMore() {
        update { $0.loadMoreFailed = false }
        loadMore()
    }

    func loadMore() {
        guard state.canLoadMore else { return }
        let token = generation
        let query = currentQuery(page: state.page + 1)
        update { $0.isLoadingMore = true }
        loadMoreTask = run { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.annonces.search(query)
                guard token == self.generation, !Task.isCancelled else { return }
                self.update { s in
                    // Pagination par OFFSET côté serveur : une annonce publiée entre deux pages décale tout d'un rang
                    // et la dernière de la page N revient en tête de N+1 — jamais deux fois la même ligne.
                    let known = Set(s.items.map { $0.id })
                    s.isLoadingMore = false
                    s.items += result.items.filter { !known.contains($0.id) }
                    s.page = result.page
                    s.totalPages = result.totalPages
                    s.total = result.total
                }
            } catch {
                guard token == self.generation, !Task.isCancelled else { return }
                self.update { s in
                    s.isLoadingMore = false
                    s.loadMoreFailed = true
                }
            }
        }
    }

    /// Tests : attend la fin du travail lancé (l'`advanceUntilIdle` d'Android), 5 s au plus.
    func waitUntilIdle(timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while activeWork > 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    // MARK: - Interne : recherche

    @discardableResult
    private func search(refreshing: Bool) -> Task<Void, Never> {
        if !refreshing {
            engine.clearSuggestions()
            let keyword = state.query
            if !TextCheck.isBlank(keyword) {
                let remembered = engine.remember(keyword)
                run { await remembered.value }
            }
        }
        searchTask?.cancel()
        // La page suivante de l'ANCIENNE recherche ne doit pas s'ajouter aux nouveaux résultats.
        loadMoreTask?.cancel()
        generation += 1
        let token = generation
        update { s in
            s.isLoadingMore = false
            s.loadMoreFailed = false
            if refreshing {
                s.isRefreshing = true
            } else {
                s.isLoading = true
                s.isError = false
                s.errorMessage = nil
                s.items = []
                s.page = 1
                s.didYouMean = nil
            }
        }
        let query = currentQuery(page: 1)
        let task = run { [weak self] in
            await self?.performSearch(query, refreshing: refreshing, token: token)
        }
        searchTask = task
        return task
    }

    private func performSearch(_ query: ListingQuery, refreshing: Bool, token: Int) async {
        var outcome: Result<ListingPage, any Error>
        do {
            outcome = .success(try await annonces.search(query))
        } catch {
            outcome = .failure(error)
        }
        // Repli : si le calcul des facettes échoue côté serveur, la liste reste utilisable sans facettes.
        if case .failure(let error) = outcome, query.withFacets, !ErrorMapper.isCancellation(error), !Task.isCancelled {
            var plain = query
            plain.withFacets = false
            do {
                outcome = .success(try await annonces.search(plain))
            } catch {
                outcome = .failure(error)
            }
        }
        guard token == generation, !Task.isCancelled else { return }
        switch outcome {
        case .success(let result):
            applyFirstPage(result, refreshing: refreshing)
            if result.items.isEmpty, let keyword = TextCheck.nonBlank(query.q) {
                let correction = try? await annonces.didYouMean(keyword)
                guard token == generation, !Task.isCancelled else { return }
                if let correction {
                    update { $0.didYouMean = correction }
                }
            }
        case .failure(let error):
            // Une annulation qui n'est pas la nôtre (la nôtre est écartée plus haut) : message générique plutôt
            // qu'une attente sans fin.
            let message = ErrorMapper.message(for: error) ?? L10n.errorGeneric
            update { s in
                if refreshing && !s.items.isEmpty {
                    // Un rafraîchissement raté garde la liste affichée ; l'erreur passe en message.
                    s.isRefreshing = false
                    s.notice = .message(message)
                } else {
                    s.isLoading = false
                    s.isRefreshing = false
                    s.isError = true
                    s.errorMessage = message
                }
            }
        }
    }

    private func applyFirstPage(_ result: ListingPage, refreshing: Bool) {
        update { s in
            if refreshing {
                // La page 1 fraîche remplace le début de la liste ; les pages suivantes déjà lues restent (Paging).
                let merged = Paging.mergeFirstPage(current: s.items, fresh: result.items, id: { $0.id })
                if merged.count <= result.items.count {
                    s.page = result.page
                }
                s.items = merged
            } else {
                s.items = result.items
                s.page = result.page
            }
            s.isLoading = false
            s.isRefreshing = false
            s.isError = false
            s.errorMessage = nil
            s.total = result.total
            s.totalPages = result.totalPages
            s.facets = result.facets
        }
    }

    private func currentQuery(page: Int) -> ListingQuery {
        let current = state
        let hasQuery = current.hasQuery
        let filters = current.filters
        return ListingQuery(
            q: hasQuery ? current.query : nil,
            category: current.categorySlug,
            subcategory: filters.subcategory,
            wilaya: filters.wilayaId,
            commune: filters.communeId,
            priceType: filters.priceType,
            priceMin: Double(filters.priceMin),
            priceMax: Double(filters.priceMax),
            sort: filters.sort ?? ListingSort.defaultSort(hasQuery: hasQuery).rawValue,
            featured: filters.featuredOnly,
            page: page,
            limit: 24,
            attributes: filters.attributes,
            // Les facettes ne sont calculées que sur la première page d'une catégorie.
            withFacets: current.categorySlug != nil && page == 1
        )
    }

    // MARK: - Interne : catégories, catalogue, paramètres

    private func selectCategory(_ slug: String?, subcategory: String?) {
        attributesTask?.cancel()
        update { s in
            s.categorySlug = slug
            s.filters.subcategory = subcategory
            s.filters.attributes = [:]
            s.facets = [:]
            s.attributeSet = nil
            s.dependentOptions = [:]
        }
        requestedDependentKeys = []
        if let slug {
            loadAttributes(slug, subcategory: subcategory)
        }
        search()
    }

    /// Suggestion de catégorie : une sous-catégorie (« Climatiseur / Chauffage ») sélectionne sa racine et devient
    /// le filtre — les puces restent justes (Android passait le slug tel quel).
    private func selectSuggestedCategory(_ slug: String) {
        if let root = rootCategory(containing: slug) {
            selectCategory(root.slug, subcategory: slug)
        } else {
            selectCategory(slug, subcategory: nil)
        }
    }

    /// Racine dont `slug` est une sous-catégorie ; nil si `slug` est une racine ou s'il est inconnu.
    private func rootCategory(containing slug: String) -> Category? {
        let roots = state.categories
        guard !roots.contains(where: { $0.slug == slug }) else { return nil }
        return roots.first { root in root.children.contains { $0.slug == slug } }
    }

    /// Ouverture avec une sous-catégorie pour `category` (lien `/annonces?category=voitures`) : sa racine est
    /// sélectionnée à l'arrivée des catégories, la sous-catégorie devient le filtre.
    private func resolveChildCategory() {
        guard let slug = state.categorySlug, let root = rootCategory(containing: slug) else { return }
        selectCategory(root.slug, subcategory: state.filters.subcategory ?? slug)
    }

    /// Paramètres d'une alerte ou d'un lien (clés d'URL du site) : `category` peut être une sous-catégorie, résolue
    /// vers sa racine + le filtre. Toute la recherche est remplacée — `applyParams` (Android).
    private func apply(params: [String: String]) {
        let roots = state.categories
        guard !roots.isEmpty else {
            paramsAwaitingCategories = params
            if started { loadCatalog() }
            return
        }
        let raw = params["category"]
        let root: Category? = roots.first(where: { $0.slug == raw })
            ?? roots.first(where: { category in category.children.contains { $0.slug == raw } })
        var subcategory = params["subcategory"]
        if subcategory == nil, let raw, let root, root.slug != raw {
            subcategory = raw
        }
        var attributes: [String: String] = [:]
        for (key, value) in params where key.hasPrefix("attr_") {
            attributes[String(key.dropFirst(5))] = value
        }
        let priceType: PriceType? = params["priceType"].flatMap { value in PriceType.allCases.first { $0.rawValue == value } }
        attributesTask?.cancel()
        update { s in
            s.query = params["q"] ?? ""
            s.categorySlug = root?.slug ?? raw
            s.filters = ListingFilters(
                subcategory: subcategory,
                wilayaId: params["wilaya"].flatMap { Int($0) },
                communeId: params["commune"].flatMap { Int($0) },
                priceType: priceType,
                priceMin: params["priceMin"] ?? "",
                priceMax: params["priceMax"] ?? "",
                attributes: attributes,
                featuredOnly: params["featured"] == "1"
            )
            s.facets = [:]
            s.attributeSet = nil
            s.dependentOptions = [:]
        }
        requestedDependentKeys = []
        if let slug = state.categorySlug {
            loadAttributes(slug, subcategory: subcategory)
        }
        // La puce de la commune d'une alerte a besoin de son nom.
        onFilterWilayaChange(state.filters.wilayaId)
        search()
    }

    private func takePendingParams() {
        guard let params = searchRepository.pendingParams else { return }
        searchRepository.pendingParams = nil
        apply(params: params)
    }

    private func categoriesLoaded() {
        if let params = paramsAwaitingCategories {
            paramsAwaitingCategories = nil
            apply(params: params)
        } else {
            resolveChildCategory()
        }
    }

    /// Catégories (puces) et wilayas (feuille, puce de lieu) : échec silencieux comme Android, nouvel essai au
    /// retour du réseau et au rafraîchissement.
    private func loadCatalog() {
        if state.categories.isEmpty && !categoriesLoading {
            categoriesLoading = true
            run { [weak self] in
                guard let self else { return }
                let roots = try? await self.categoryRepository.roots()
                self.categoriesLoading = false
                guard let roots, !roots.isEmpty else { return }
                self.update { $0.categories = roots }
                self.categoriesLoaded()
            }
        }
        if state.wilayas.isEmpty && !wilayasLoading {
            wilayasLoading = true
            run { [weak self] in
                guard let self else { return }
                let list = try? await self.geo.wilayas()
                self.wilayasLoading = false
                guard let list else { return }
                self.update { $0.wilayas = list }
            }
        }
    }

    /// Définitions d'attributs de la catégorie (libellés des facettes et des puces, plages, oui / non).
    private func loadAttributes(_ slug: String, subcategory: String?) {
        attributesTask?.cancel()
        let language = locale()
        attributesTask = run { [weak self] in
            guard let self else { return }
            let set = try? await self.attributeRepository.attributes(
                categorySlug: slug,
                subcategory: subcategory,
                locale: language
            )
            guard let set, !Task.isCancelled else { return }
            self.update { $0.attributeSet = set }
        }
    }

    // MARK: - Interne : abonnements, tâches

    private func observe(online: AnyPublisher<Bool, Never>?) {
        engine.$suggestions
            .sink { [weak self] value in self?.suggestions = value }
            .store(in: &subscriptions)
        engine.$history
            .sink { [weak self] value in self?.history = value }
            .store(in: &subscriptions)
        favorites.$ids
            .sink { [weak self] value in self?.favoriteIds = value }
            .store(in: &subscriptions)
        // `@Published` publie AVANT d'écrire la valeur : la lecture (et la remise à nil) passe par une tâche, qui
        // s'exécute une fois l'écriture terminée.
        searchRepository.$pendingParams
            .sink { [weak self] params in
                guard params != nil, let self else { return }
                self.run { [weak self] in
                    self?.takePendingParams()
                }
            }
            .store(in: &subscriptions)
        if let online {
            online
                .sink { [weak self] isOnline in self?.connectivityChanged(isOnline) }
                .store(in: &subscriptions)
        }
    }

    /// Retour du réseau (hors ligne → en ligne, jamais au démarrage) : un écran resté en erreur faute de connexion se
    /// recharge seul — `launchOnReconnect` (Android).
    private func connectivityChanged(_ isOnline: Bool) {
        guard isOnline else {
            wasOffline = true
            return
        }
        guard wasOffline else { return }
        wasOffline = false
        guard started else { return }
        loadCatalog()
        if state.isError {
            search()
        }
    }

    private func update(_ change: (inout ListingsState) -> Void) {
        var copy = state
        change(&copy)
        state = copy
    }

    /// Lance une tâche suivie par `activeWork` (MainActor, comme tout l'écran).
    @discardableResult
    private func run(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        activeWork += 1
        return Task { [weak self] in
            await operation()
            self?.activeWork -= 1
        }
    }
}
