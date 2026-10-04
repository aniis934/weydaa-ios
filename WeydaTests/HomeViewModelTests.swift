import Combine
import Foundation
import XCTest
@testable import Weyda

/// Accueil (`HomeViewModel`) : chargement parallèle, échec partiel, tout en échec → erreur puis relance au retour
/// du réseau, rafraîchir, favori d'un visiteur → connexion, « Pour vous » qui suit la session ; recherche de la
/// feuille des catégories. Android n'a pas de test de l'accueil : cas tirés de `HomeViewModel.kt` (et de
/// `CategoriesFilterTest.kt` pour la feuille). Données fictives.
final class HomeViewModelTests: XCTestCase {
    @MainActor
    private func makeModel(
        _ api: FakeWeydaAPI,
        session: AnyPublisher<User?, Never> = Just<User?>(nil).eraseToAnyPublisher(),
        online: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher(),
        loginRequests: FakeWeydaAPI.Box<Int> = FakeWeydaAPI.Box(0)
    ) -> HomeViewModel {
        HomeViewModel(
            annonces: AnnonceRepository(api: api),
            categories: CategoryRepository(api: api),
            geo: GeoRepository(api: api),
            favorites: FavoritesRepository(api: api),
            session: session,
            online: online,
            onLoginRequired: { loginRequests.value += 1 }
        )
    }

    // MARK: - Chargement

    /// Les sections partent ENSEMBLE : chaque route attend que les six d'un visiteur soient parties. Chargées l'une
    /// après l'autre, la première attendrait en vain (borne de 2 000 tours) et le pic resterait à 1.
    @MainActor
    func testTheSectionsLoadInParallel() async {
        let api = FakeWeydaAPI()
        let started = FakeWeydaAPI.Box(0)
        let peak = FakeWeydaAPI.Box(0)
        let expected = 6
        let gate: @MainActor @Sendable () async -> Void = {
            started.value += 1
            var turns = 0
            while started.value < expected && turns < 2_000 {
                turns += 1
                await Task.yield()
            }
            peak.value = max(peak.value, started.value)
        }
        api.onGetCategories = {
            await gate()
            return [HomeTestData.vehicles]
        }
        api.onGetAnnonces = { call in
            await gate()
            return call.featured == 1 ? HomeTestData.page(["f1"], featured: true) : HomeTestData.page(["f1", "r1"])
        }
        api.onGetTrending = { _ in
            await gate()
            return AnnonceListDTO(annonces: [HomeTestData.annonce("t1")])
        }
        api.onGetTopWilayas = { _ in
            await gate()
            return HomeTestData.ranked
        }
        api.onGetWilayas = {
            await gate()
            return HomeTestData.wilayas
        }
        let model = makeModel(api)
        await model.load()

        XCTAssertEqual(peak.value, expected)
        XCTAssertEqual(api.count("getRecommendations"), 0, "visiteur : pas de requête « Pour vous »")
        let state = model.state
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isError)
        XCTAssertEqual(state.categories.map { $0.slug }, ["vehicules"])
        XCTAssertEqual(state.featured.map { $0.id }, ["f1"])
        XCTAssertEqual(state.recent.map { $0.id }, ["r1"])
        XCTAssertEqual(state.trending.map { $0.id }, ["t1"])
        XCTAssertTrue(state.forYou.isEmpty)
        XCTAssertEqual(state.popularWilayas.map { $0.id }, [16, 31])
        // « À la une » : 8 annonces récentes ; « Récentes » : 20 lues (les « À la une » en sont retirées).
        let featuredCall = api.searchCalls.first { $0.featured == 1 }
        XCTAssertEqual(featuredCall?.limit, HomeFeed.featuredLimit)
        XCTAssertEqual(featuredCall?.sort, "newest")
        let recentCall = api.searchCalls.first { $0.featured == nil }
        XCTAssertEqual(recentCall?.limit, HomeFeed.recentFetchLimit)
        XCTAssertEqual(recentCall?.sort, "newest")
    }

    /// Une section en échec n'empêche pas les autres : catégories et tendances tombent, le reste s'affiche ; sans
    /// classement des villes, le repli prend les grandes wilayas dans leur ordre (Alger, Oran, Constantine…).
    @MainActor
    func testAFailingSectionDoesNotStopTheOthers() async {
        let api = FakeWeydaAPI()
        api.onGetCategories = { throw FakeWeydaAPI.apiError(500) }
        api.onGetAnnonces = { call in
            call.featured == 1 ? HomeTestData.page(["f1"], featured: true) : HomeTestData.page(["f1", "r1", "r2"])
        }
        api.onGetTrending = { _ in throw URLError(.timedOut) }
        api.onGetTopWilayas = { _ in throw FakeWeydaAPI.apiError(500) }
        api.onGetWilayas = { HomeTestData.wilayas }
        let model = makeModel(api)
        await model.load()

        let state = model.state
        XCTAssertFalse(state.isError)
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.categories.isEmpty)
        XCTAssertTrue(state.trending.isEmpty)
        XCTAssertEqual(state.featured.map { $0.id }, ["f1"])
        XCTAssertEqual(state.recent.map { $0.id }, ["r1", "r2"], "les annonces « À la une » sont retirées des récentes")
        XCTAssertEqual(state.popularWilayas.map { $0.id }, [16, 31, 25])
        XCTAssertTrue(state.hasContent)
    }

    /// Catégories, « À la une » et récentes en échec : écran d'erreur avec la cause traduite ; au retour du réseau,
    /// l'écran se recharge seul (Android : `launchOnReconnect`).
    @MainActor
    func testEverythingFailingShowsTheErrorThenTheReturningNetworkReloads() async {
        let api = FakeWeydaAPI()
        let offline = URLError(.notConnectedToInternet)
        api.onGetCategories = { throw offline }
        api.onGetAnnonces = { _ in throw offline }
        let online = PassthroughSubject<Bool, Never>()
        let model = makeModel(api, online: online.eraseToAnyPublisher())
        await model.load()

        XCTAssertTrue(model.state.isError)
        XCTAssertFalse(model.state.isLoading)
        XCTAssertEqual(model.state.errorMessage, L10n.errorOffline)

        api.onGetCategories = { [HomeTestData.vehicles] }
        api.onGetAnnonces = { _ in HomeTestData.page(["r1"]) }
        online.send(false)
        online.send(true)
        var turns = 0
        while (model.state.isError || model.state.isLoading) && turns < 1_000 {
            turns += 1
            await Task.yield()
        }
        XCTAssertFalse(model.state.isError)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.categories.map { $0.slug }, ["vehicules"])
        XCTAssertEqual(api.count("getCategories"), 2)
    }

    /// Tirer pour rafraîchir : une section en échec garde son contenu, les autres sont remplacées ; le catalogue
    /// reste en mémoire ; l'indicateur s'éteint.
    @MainActor
    func testRefreshKeepsTheSectionsThatFailAndReplacesTheOthers() async {
        let api = FakeWeydaAPI()
        api.onGetCategories = { [HomeTestData.vehicles] }
        api.onGetAnnonces = { call in
            call.featured == 1 ? HomeTestData.page(["f1"], featured: true) : HomeTestData.page(["r1"])
        }
        api.onGetTrending = { _ in AnnonceListDTO(annonces: [HomeTestData.annonce("t1")]) }
        let model = makeModel(api)
        await model.load()
        XCTAssertEqual(model.state.recent.map { $0.id }, ["r1"])

        api.onGetAnnonces = { call in
            if call.featured == 1 {
                throw FakeWeydaAPI.apiError(503)
            }
            return HomeTestData.page(["r2", "r1"])
        }
        api.onGetTrending = { _ in throw URLError(.timedOut) }
        await model.refresh()

        let state = model.state
        XCTAssertFalse(state.isRefreshing)
        XCTAssertFalse(state.isError)
        XCTAssertEqual(state.featured.map { $0.id }, ["f1"])
        XCTAssertEqual(state.trending.map { $0.id }, ["t1"])
        XCTAssertEqual(state.recent.map { $0.id }, ["r2", "r1"])
        XCTAssertEqual(api.count("getCategories"), 1, "catalogue gardé en mémoire")
    }

    // MARK: - Favoris et session

    /// Cœur touché par un visiteur : demande de connexion, rien n'est envoyé ; par un membre : bascule optimiste
    /// envoyée au serveur, le cœur se remplit.
    @MainActor
    func testAVisitorHeartAsksToLogInWhileAMemberHeartToggles() async {
        let api = FakeWeydaAPI()
        let session = CurrentValueSubject<User?, Never>(nil)
        let logins = FakeWeydaAPI.Box(0)
        let model = makeModel(api, session: session.eraseToAnyPublisher(), loginRequests: logins)
        let listing = HomeTestData.annonce("a1").toDomain()

        model.toggleFavorite(listing)
        XCTAssertEqual(logins.value, 1)
        XCTAssertFalse(model.isLoggedIn)
        XCTAssertEqual(api.count("addFavorite"), 0)
        XCTAssertTrue(model.favoriteIds.isEmpty)

        api.onAddFavorite = { body in FavoriteDTO(id: "fav-1", annonceId: body.annonceId) }
        session.send(HomeTestData.member)
        XCTAssertTrue(model.isLoggedIn)
        model.toggleFavorite(listing)
        var turns = 0
        while api.count("addFavorite") == 0 && turns < 1_000 {
            turns += 1
            await Task.yield()
        }
        XCTAssertEqual(api.count("addFavorite"), 1)
        XCTAssertTrue(model.favoriteIds.contains("a1"))
        XCTAssertEqual(logins.value, 1)
        XCTAssertNil(model.banner)
    }

    /// Cœur refusé par le serveur : le cœur revient à son état (repository) et une bannière d'erreur le dit (les
    /// échecs étaient muets avant la phase 8) ; fermée, elle disparaît.
    @MainActor
    func testARefusedHeartShowsAnErrorBanner() async {
        let api = FakeWeydaAPI()
        let session = CurrentValueSubject<User?, Never>(HomeTestData.member)
        let model = makeModel(api, session: session.eraseToAnyPublisher())
        let listing = HomeTestData.annonce("a1").toDomain()
        api.onAddFavorite = { _ in throw FakeWeydaAPI.apiError(500) }

        await model.toggleFavorite(listing)?.value
        XCTAssertFalse(model.favoriteIds.contains("a1"))
        XCTAssertEqual(model.banner?.kind, WeydaBanner.Kind.error)
        XCTAssertNil(model.banner?.action)
        model.bannerDismissed()
        XCTAssertNil(model.banner)
    }

    /// « Pour vous » : chargé pour un membre, vidé à la déconnexion (sans requête), relu à la connexion suivante.
    @MainActor
    func testForYouFollowsTheSession() async {
        let api = FakeWeydaAPI()
        api.onGetCategories = { [HomeTestData.vehicles] }
        api.onGetAnnonces = { _ in HomeTestData.page(["r1"]) }
        api.onGetRecommendations = { AnnonceListDTO(annonces: [HomeTestData.annonce("y1")]) }
        let session = CurrentValueSubject<User?, Never>(HomeTestData.member)
        let model = makeModel(api, session: session.eraseToAnyPublisher())
        await model.load()
        XCTAssertTrue(model.isLoggedIn)
        XCTAssertEqual(model.state.forYou.map { $0.id }, ["y1"])

        session.send(nil)
        XCTAssertFalse(model.isLoggedIn)
        XCTAssertTrue(model.state.forYou.isEmpty)
        XCTAssertEqual(api.count("getRecommendations"), 1)

        session.send(HomeTestData.member)
        var turns = 0
        while model.state.forYou.isEmpty && turns < 1_000 {
            turns += 1
            await Task.yield()
        }
        XCTAssertEqual(model.state.forYou.map { $0.id }, ["y1"])
        XCTAssertEqual(api.count("getRecommendations"), 2)
    }

    // MARK: - Feuille des catégories

    /// Recherche sans casse ni accents, dans les trois langues, racines puis sous-catégories (`CategoriesFilterTest.kt`,
    /// étendu aux sous-catégories) ; un choix donne les critères de l'onglet Annonces.
    func testTheCategorySheetSearchIgnoresCaseAccentsAndLanguage() {
        let categories = [
            HomeTestData.category("electronique", "Électronique", "الإلكترونيات", "Electronics", children: [
                HomeTestData.category("smartphones", "Smartphones", "هواتف ذكية", "Smartphones"),
            ]).toDomain(),
            HomeTestData.category("electromenager", "Électroménager", "الأجهزة المنزلية", "Home Appliances", children: [
                HomeTestData.category("petit-electromenager", "Petit électroménager", "أجهزة صغيرة", "Small Appliances"),
            ]).toDomain(),
            HomeTestData.category("vehicules", "Véhicules", "المركبات", "Vehicles", children: [
                HomeTestData.category("voitures", "Voitures", "سيارات", "Cars"),
            ]).toDomain(),
        ]
        XCTAssertTrue(CategorySearch.hits(in: categories, query: "   ").isEmpty)
        XCTAssertEqual(
            CategorySearch.hits(in: categories, query: "ELECTRO").map { $0.id },
            ["electronique", "electromenager", "electromenager/petit-electromenager"]
        )
        XCTAssertEqual(CategorySearch.hits(in: categories, query: "véhi").map { $0.id }, ["vehicules"])
        XCTAssertEqual(CategorySearch.hits(in: categories, query: "سيار").map { $0.id }, ["vehicules/voitures"])
        XCTAssertEqual(
            CategorySearch.hits(in: categories, query: "appliance").map { $0.id },
            ["electromenager", "electromenager/petit-electromenager"]
        )
        XCTAssertTrue(CategorySearch.hits(in: categories, query: "xyz").isEmpty)

        let car = CategorySearch.hits(in: categories, query: "cars").first
        XCTAssertEqual(car?.choice.launch, ListingsLaunch(category: "vehicules", subcategory: "voitures"))
        XCTAssertEqual(CategorySheetChoice.category(slug: "vehicules").launch, ListingsLaunch(category: "vehicules"))
        XCTAssertEqual(CategorySheetChoice.all.launch, ListingsLaunch())
    }
}

#if DEBUG
/// Données simulées de l'accueil (`MockFixtures/routes-home.json` + `home/`) lues par le VRAI ViewModel à travers
/// `LiveWeydaAPI` et l'API simulée : JSON valides, routes servies, accueil d'un visiteur tel que le tour le capture.
final class HomeMockFixturesTests: XCTestCase {
    @MainActor
    func testAVisitorHomeOverTheMockAPI() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        let api = LiveWeydaAPI(client: client, authClient: client)
        let model = HomeViewModel(
            annonces: AnnonceRepository(api: api),
            categories: CategoryRepository(api: api),
            geo: GeoRepository(api: api),
            favorites: FavoritesRepository(api: api),
            session: Just<User?>(nil).eraseToAnyPublisher(),
            onLoginRequired: {}
        )
        await model.load()

        let state = model.state
        XCTAssertFalse(state.isError)
        XCTAssertEqual(state.categories.count, 14)
        XCTAssertEqual(state.featured.map { $0.id }, ["mock-a2", "mock-a3", "mock-a6", "mock-a9", "mock-a13", "mock-a17"])
        XCTAssertTrue(state.featured.allSatisfy { $0.isFeatured })
        XCTAssertEqual(
            state.recent.map { $0.id },
            ["mock-a1", "mock-a4", "mock-a5", "mock-a7", "mock-a8", "mock-a10",
             "mock-a11", "mock-a12", "mock-a14", "mock-a15", "mock-a16", "mock-a18"]
        )
        XCTAssertEqual(
            state.trending.map { $0.id },
            ["mock-a13", "mock-a10", "mock-a7", "mock-a14", "mock-a12", "mock-a6", "mock-a15", "mock-a11"]
        )
        XCTAssertTrue(state.forYou.isEmpty)
        XCTAssertEqual(state.popularWilayas.count, 10)
        XCTAssertEqual(state.popularWilayas.first?.id, 16)

        let first = try XCTUnwrap(state.recent.first)
        XCTAssertEqual(first.categorySlug, "smartphones")
        XCTAssertEqual(first.wilaya?.fr, "Alger")
        XCTAssertEqual(first.wilayaId, 16)
        XCTAssertEqual(first.coverImage, "https://photos.mock.weydaa/annonces/phone-1.webp")
        XCTAssertEqual(first.coverThumbnail, "https://photos.mock.weydaa/annonces/phone-1_thumb.webp")
        XCTAssertEqual(first.price, 215_000)
        XCTAssertEqual(first.priceType, .negotiable)
        XCTAssertNotNil(first.createdAt)

        // La liste de référence (ids partagés avec Annonces et Détail) : 24 annonces en page 1 sur 30 au total ;
        // la page 2 (6 annonces plus anciennes, `mock-a25…a30`) vient des données de l'onglet Annonces.
        let all = try await AnnonceRepository(api: api).search(ListingQuery())
        XCTAssertEqual(all.items.map { $0.id }, (1...24).map { "mock-a\($0)" })
        XCTAssertEqual(all.total, 30)
        XCTAssertTrue(all.hasMore)
        let free = try XCTUnwrap(all.items.last)
        XCTAssertEqual(free.priceType, .free)
        XCTAssertNil(free.price)
    }
}
#endif

/// Données fictives des tests de l'accueil.
private enum HomeTestData {
    static func annonce(_ id: String, featured: Bool = false) -> AnnonceDTO {
        AnnonceDTO(id: id, title: "Annonce \(id)", isFeatured: featured)
    }

    static func page(_ ids: [String], featured: Bool = false) -> AnnoncesPageDTO {
        AnnoncesPageDTO(annonces: ids.map { annonce($0, featured: featured) }, total: ids.count, page: 1, totalPages: 1)
    }

    static func category(_ slug: String, _ fr: String, _ ar: String, _ en: String, children: [CategoryDTO] = []) -> CategoryDTO {
        CategoryDTO(id: "cat_\(slug)", slug: slug, nameFr: fr, nameAr: ar, nameEn: en, children: children)
    }

    static let vehicles: CategoryDTO = category("vehicules", "Véhicules", "المركبات", "Vehicles")

    /// Classement du serveur (`?top=`) : wilayas comptées.
    static let ranked: [WilayaDTO] = [
        WilayaDTO(id: 16, nameFr: "Alger", nameAr: "الجزائر", listingsCount: 1873),
        WilayaDTO(id: 31, nameFr: "Oran", nameAr: "وهران", listingsCount: 942),
    ]

    /// `GET /api/wilayas` (sans compte) : le repli garde l'ordre de `HomeFeed.popularWilayaIds`.
    static let wilayas: [WilayaDTO] = [
        WilayaDTO(id: 1, nameFr: "Adrar", nameAr: "أدرار"),
        WilayaDTO(id: 16, nameFr: "Alger", nameAr: "الجزائر"),
        WilayaDTO(id: 25, nameFr: "Constantine", nameAr: "قسنطينة"),
        WilayaDTO(id: 31, nameFr: "Oran", nameAr: "وهران"),
    ]

    static let member = User(
        id: "u1",
        name: "Karim B.",
        email: "karim@example.com",
        avatarUrl: nil,
        role: "USER",
        emailVerified: true
    )
}
