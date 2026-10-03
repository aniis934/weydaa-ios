import Combine
import Foundation

/// Données de l'accueil — portage de `HomeUiState` (ui/home/HomeViewModel.kt). Valeur pure : `nonisolated`.
nonisolated struct HomeState: Equatable, Sendable {
    /// Premier chargement : l'écran montre les formes à venir (squelettes).
    var isLoading: Bool = true
    /// Tirer pour rafraîchir : le contenu reste affiché pendant le rechargement.
    var isRefreshing: Bool = false
    /// Catégories, « À la une » ET récentes en échec : écran d'erreur avec « Réessayer ».
    var isError: Bool = false
    /// Cause traduite de l'échec complet (hors ligne, serveur…), par `ErrorMapper`.
    var errorMessage: String? = nil
    /// Catégories racines, avec leurs sous-catégories (feuille des catégories).
    var categories: [Category] = []
    /// « À la une » (`featured=1`).
    var featured: [Listing] = []
    /// « Tendances » : les plus consultées sur 7 jours.
    var trending: [Listing] = []
    /// « Pour vous » (compte connecté, d'après ses favoris et ses alertes) ; vide = section masquée.
    var forYou: [Listing] = []
    /// « Annonces récentes », sans celles déjà « À la une » (comme le site), `HomeFeed.recentCount` au plus.
    var recent: [Listing] = []
    /// Villes : classement du serveur (`?top=`) quand il répond, sinon les grandes wilayas de `HomeFeed`.
    var popularWilayas: [Wilaya] = []

    var hasContent: Bool {
        !categories.isEmpty || !featured.isEmpty || !recent.isEmpty
    }
}

/// Règles de l'accueil : constantes et calculs purs de `HomeViewModel.kt`.
nonisolated enum HomeFeed {
    static let featuredLimit = 8
    /// Un peu plus que `recentCount` : les annonces déjà « À la une » sont retirées des récentes.
    static let recentFetchLimit = 20
    static let recentCount = 12
    static let trendingLimit = 12
    /// Villes de REPLI quand le classement du serveur ne répond pas : les dix wilayas les plus peuplées (Alger,
    /// Oran, Constantine, Annaba, Blida, Sétif, Tizi Ouzou, Béjaïa, Batna, Tlemcen), dans cet ordre. Sa taille fixe
    /// aussi le nombre de villes demandé au classement (`POPULAR_WILAYAS`, Android).
    static let popularWilayaIds: [Int] = [16, 31, 25, 23, 9, 19, 15, 6, 5, 13]

    /// Récentes de l'accueil : sans les annonces « À la une » du même chargement, `recentCount` au plus.
    static func recent(_ listings: [Listing], excluding featured: [Listing]) -> [Listing] {
        let featuredIds = Set(featured.map { $0.id })
        return Array(listings.filter { !featuredIds.contains($0.id) }.prefix(recentCount))
    }

    /// Classement du serveur s'il est connu et non vide ; sinon les wilayas de repli présentes dans `all`.
    static func popularWilayas(ranked: [Wilaya]?, all: [Wilaya]) -> [Wilaya] {
        if let ranked, !ranked.isEmpty {
            return ranked
        }
        var byId: [Int: Wilaya] = [:]
        for wilaya in all where byId[wilaya.id] == nil {
            byId[wilaya.id] = wilaya
        }
        return popularWilayaIds.compactMap { byId[$0] }
    }
}

/// Les quatre listes d'annonces de l'accueil.
nonisolated enum HomeListingSection: Sendable {
    case featured
    case recent
    case trending
    case forYou
}

/// Un chargement de l'accueil : chaque section réussit ou échoue seule.
nonisolated struct HomeLoadResult: Sendable {
    var categories: Result<[Category], any Error>
    var featured: Result<[Listing], any Error>
    var recent: Result<[Listing], any Error>
    var trending: Result<[Listing], any Error>
    var forYou: Result<[Listing], any Error>
    var rankedWilayas: Result<[Wilaya], any Error>
    var wilayas: Result<[Wilaya], any Error>
}

nonisolated extension HomeState {
    /// Fusion d'un chargement (Android : `load`) : une section en échec garde son contenu précédent ; l'écran
    /// d'erreur n'apparaît que si catégories, « À la une » ET récentes échouent — jamais à la place d'un écran plein
    /// qu'on rafraîchit, ni pour une annulation (aucun message).
    func applying(_ result: HomeLoadResult, refreshing: Bool) -> HomeState {
        let loadedFeatured: [Listing]? = Self.value(of: result.featured)
        let loadedRecent: [Listing]? = Self.value(of: result.recent).map { listings in
            HomeFeed.recent(listings, excluding: loadedFeatured ?? [])
        }
        let cities: [Wilaya] = HomeFeed.popularWilayas(
            ranked: Self.value(of: result.rankedWilayas),
            all: Self.value(of: result.wilayas) ?? []
        )
        let categoriesError: (any Error)? = Self.error(of: result.categories)
        let recentError: (any Error)? = Self.error(of: result.recent)
        let allFailed: Bool = categoriesError != nil && Self.error(of: result.featured) != nil && recentError != nil
        let cause: (any Error)? = categoriesError ?? recentError
        let message: String? = cause.flatMap { ErrorMapper.message(for: $0) }

        var next = self
        next.isLoading = false
        next.isRefreshing = false
        next.isError = allFailed && message != nil && !(refreshing && hasContent)
        next.errorMessage = next.isError ? message : nil
        next.categories = Self.value(of: result.categories) ?? categories
        next.featured = loadedFeatured ?? featured
        next.recent = loadedRecent ?? recent
        next.trending = Self.value(of: result.trending) ?? trending
        next.forYou = Self.value(of: result.forYou) ?? forYou
        if !cities.isEmpty {
            next.popularWilayas = cities
        }
        return next
    }

    private static func value<Value>(of result: Result<Value, any Error>) -> Value? {
        if case .success(let value) = result {
            return value
        }
        return nil
    }

    private static func error<Value>(of result: Result<Value, any Error>) -> (any Error)? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }
}

/// Accueil — portage de `HomeViewModel` (Android) : sections chargées EN PARALLÈLE et indépendantes (une section
/// en échec n'empêche pas les autres), tirer pour rafraîchir, relance au retour du réseau quand l'écran est en
/// erreur, « Pour vous » relu à chaque changement de compte, cœurs des cartes (visiteur → connexion).
final class HomeViewModel: ObservableObject {
    @Published private(set) var state = HomeState()
    /// Cœurs des cartes : les favoris du compte (`FavoritesRepository.ids`, source de vérité de toute l'app).
    @Published private(set) var favoriteIds: Set<String> = []
    /// Un compte est connecté : cloche des notifications, « Pour vous », bascule des favoris.
    @Published private(set) var isLoggedIn = false

    private let annonces: AnnonceRepository
    private let categories: CategoryRepository
    private let geo: GeoRepository
    private let favorites: FavoritesRepository
    /// Visiteur qui touche un cœur : `router.requestLogin()`.
    private let onLoginRequired: () -> Void

    private var userId: String?
    /// La première valeur de session est l'état de départ (lu par le premier chargement), pas un changement.
    private var sessionKnown = false
    private var wasOffline = false
    /// Change à chaque chargement : seul le plus récent écrit l'état (« Réessayer » pendant une attente).
    private var generation = 0
    private var initialLoad: Task<Void, Never>?
    private var forYouLoad: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - session: utilisateur de la session (`sessionManager.$user`).
    ///   - online: connectivité (`connectivity.$isOnline`) ; rien = pas de relance automatique (tests).
    init(
        annonces: AnnonceRepository,
        categories: CategoryRepository,
        geo: GeoRepository,
        favorites: FavoritesRepository,
        session: AnyPublisher<User?, Never>,
        online: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher(),
        onLoginRequired: @escaping () -> Void
    ) {
        self.annonces = annonces
        self.categories = categories
        self.geo = geo
        self.favorites = favorites
        self.onLoginRequired = onLoginRequired
        favorites.$ids
            .removeDuplicates()
            .sink { [weak self] ids in
                self?.favoriteIds = ids
            }
            .store(in: &subscriptions)
        session
            .map { user in user?.id }
            .removeDuplicates()
            .sink { [weak self] id in
                self?.sessionChanged(to: id)
            }
            .store(in: &subscriptions)
        online
            .removeDuplicates()
            .sink { [weak self] isOnline in
                self?.connectivityChanged(isOnline: isOnline)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Chargement

    /// Premier affichage (`.task`) : un seul chargement, mené à son terme même si l'écran disparaît entre-temps
    /// (changement d'onglet pendant l'attente) — les sections sont prêtes au retour.
    func loadIfNeeded() async {
        let task: Task<Void, Never>
        if let initialLoad {
            task = initialLoad
        } else {
            task = Task { await self.load() }
            initialLoad = task
        }
        await task.value
    }

    /// Chargement complet : premier affichage, « Réessayer », retour du réseau.
    func load() async {
        await load(refreshing: false)
    }

    /// Tirer pour rafraîchir : les sections restent affichées ; une section en échec garde son contenu.
    func refresh() async {
        guard !state.isLoading, !state.isRefreshing else { return }
        await load(refreshing: true)
    }

    /// « Réessayer » de l'écran d'erreur.
    func retry() {
        guard !state.isLoading else { return }
        Task { await self.load() }
    }

    private func load(refreshing: Bool) async {
        generation += 1
        let current = generation
        if refreshing {
            state.isRefreshing = true
        } else {
            state.isLoading = true
            state.isError = false
            state.errorMessage = nil
        }
        // Sept requêtes à la fois (Android : `async`), chacune réduite à un `Result` : un échec n'annule pas les autres.
        async let categoriesResult = self.fetchCategories()
        async let featuredResult = self.fetchListings(.featured)
        async let recentResult = self.fetchListings(.recent)
        async let trendingResult = self.fetchListings(.trending)
        async let forYouResult = self.fetchListings(.forYou)
        async let rankedResult = self.fetchRankedWilayas()
        async let wilayasResult = self.fetchWilayas()
        let loadedCategories = await categoriesResult
        let loadedFeatured = await featuredResult
        let loadedRecent = await recentResult
        let loadedTrending = await trendingResult
        let loadedForYou = await forYouResult
        let loadedRanking = await rankedResult
        let loadedWilayas = await wilayasResult
        // Un chargement plus récent a été lancé pendant l'attente : c'est lui qui écrira l'état.
        guard current == generation else { return }
        let result = HomeLoadResult(
            categories: loadedCategories,
            featured: loadedFeatured,
            recent: loadedRecent,
            trending: loadedTrending,
            forYou: loadedForYou,
            rankedWilayas: loadedRanking,
            wilayas: loadedWilayas
        )
        state = state.applying(result, refreshing: refreshing)
    }

    private func fetchCategories() async -> Result<[Category], any Error> {
        do {
            let roots = try await categories.roots()
            return .success(roots)
        } catch {
            return .failure(error)
        }
    }

    private func fetchListings(_ section: HomeListingSection) async -> Result<[Listing], any Error> {
        do {
            let listings: [Listing]
            switch section {
            case .featured:
                listings = try await annonces.featured(limit: HomeFeed.featuredLimit)
            case .recent:
                listings = try await annonces.recent(limit: HomeFeed.recentFetchLimit)
            case .trending:
                listings = try await annonces.trending(limit: HomeFeed.trendingLimit)
            case .forYou:
                // Visiteur : rien à recommander (le serveur répondrait une liste vide), aucune requête.
                guard userId != nil else { return .success([]) }
                listings = try await annonces.recommendations()
            }
            return .success(listings)
        } catch {
            return .failure(error)
        }
    }

    private func fetchRankedWilayas() async -> Result<[Wilaya], any Error> {
        do {
            let ranked = try await geo.topWilayas(limit: HomeFeed.popularWilayaIds.count)
            return .success(ranked)
        } catch {
            return .failure(error)
        }
    }

    private func fetchWilayas() async -> Result<[Wilaya], any Error> {
        do {
            let wilayas = try await geo.wilayas()
            return .success(wilayas)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Favoris

    /// Cœur touché : un membre bascule le favori (optimiste ; un refus du serveur est annulé et publié par le
    /// repository) ; un visiteur est invité à se connecter — comme `HomeRoute` (Android).
    func toggleFavorite(_ listing: Listing) {
        guard isLoggedIn else {
            onLoginRequired()
            return
        }
        favorites.toggleDetached(listing.id)
    }

    // MARK: - Session et réseau

    private func sessionChanged(to id: String?) {
        let previous = userId
        userId = id
        isLoggedIn = id != nil
        guard sessionKnown else {
            sessionKnown = true
            return
        }
        guard previous != id else { return }
        reloadForYou()
    }

    /// « Pour vous » relu au changement de compte, vidé à la déconnexion (Android : `loadForYou`).
    private func reloadForYou() {
        forYouLoad?.cancel()
        forYouLoad = nil
        guard let expected = userId else {
            state.forYou = []
            return
        }
        forYouLoad = Task { [weak self] in
            guard let self else { return }
            let list: [Listing] = (try? await self.annonces.recommendations()) ?? []
            guard !Task.isCancelled, self.userId == expected else { return }
            self.state.forYou = list
        }
    }

    /// Retour du réseau : un écran en erreur se recharge seul (Android : `launchOnReconnect`).
    private func connectivityChanged(isOnline: Bool) {
        let reconnected = isOnline && wasOffline
        wasOffline = !isOnline
        guard reconnected, state.isError else { return }
        retry()
    }
}
