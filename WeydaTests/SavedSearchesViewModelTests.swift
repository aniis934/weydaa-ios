import Foundation
import XCTest
@testable import Weyda

/// « Mes alertes » — règles de `SavedSearchesViewModel` (SavedSearchesScreen.kt, Android) : liste et catalogue des
/// libellés, erreur et « Réessayer », suppression confirmée (optimiste, retour arrière, 404 = déjà faite), ouverture
/// (paramètres déposés pour l'onglet Annonces), relecture au retour ; critères lisibles (logique pure). Données fictives.
final class SavedSearchesViewModelTests: XCTestCase {
    private static func alert(
        _ id: String,
        name: String = "clio · Alger",
        params: [String: String] = ["q": "clio", "wilaya": "16"]
    ) -> SavedSearchDTO {
        SavedSearchDTO(id: id, name: name, params: params, createdAt: "2026-09-08T10:00:00.000Z")
    }

    // MARK: - ViewModel

    @MainActor
    func testTheListLoadsWithItsCriteriaInClearWords() async throws {
        let env = AlertsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetSavedSearches = {
            SavedSearchesDTO(
                searches: [
                    SavedSearchesViewModelTests.alert(
                        "s1",
                        params: ["q": "clio", "category": "vehicules", "subcategory": "voitures", "wilaya": "16", "commune": "1605"]
                    ),
                    SavedSearchesViewModelTests.alert(
                        "s2",
                        name: "Immobilier · Oran",
                        params: ["category": "immobilier", "wilaya": "31", "priceMax": "25000000", "attr_rooms": "3"]
                    ),
                ],
                max: 5
            )
        }
        let model = env.makeModel()
        XCTAssertTrue(model.state.isLoading)
        await model.appear()?.value
        XCTAssertFalse(model.state.isLoading)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.items.map { $0.id }, ["s1", "s2"])
        XCTAssertEqual(model.limit, SavedSearchesRepository.maxSavedSearches)
        // Communes lues pour la seule wilaya dont une alerte vise une commune.
        XCTAssertEqual(env.api.count("getCommunes"), 1)

        let first = try XCTUnwrap(model.state.items.first)
        let french = SavedSearchCriteria.criteria(for: first.params, catalog: model.state.catalog, language: "fr")
        XCTAssertEqual(french.map { $0.kind }, [AlertCriterionKind.keyword, .category, .location])
        XCTAssertEqual(french.map { $0.title }, [L10n.listsAlertKeyword("clio"), "Voitures", "Bab Ezzouar, Alger"])
        XCTAssertEqual(french.map { $0.icon }, [
            AlertCriterionIcon.symbol("magnifyingglass"),
            .asset(CategoryIcon.assetName(forSlug: "vehicules")),
            .asset(CategoryIcon.place),
        ])
        let arabic = SavedSearchCriteria.criteria(for: first.params, catalog: model.state.catalog, language: "ar")
        XCTAssertEqual(arabic.map { $0.title }, [L10n.listsAlertKeyword("clio"), "سيارات", "باب الزوار، الجزائر"])

        let second = try XCTUnwrap(model.state.items.last)
        let secondCriteria = SavedSearchCriteria.criteria(for: second.params, catalog: model.state.catalog, language: "fr")
        XCTAssertEqual(secondCriteria.map { $0.kind }, [AlertCriterionKind.category, .location, .price, .attributes])
        let expectedPrice: String = try XCTUnwrap(ListingsFilterRules.priceTitle(min: "", max: "25000000"))
        XCTAssertEqual(secondCriteria.map { $0.title }, ["Immobilier", "Oran", expectedPrice, L10n.listsAlertMoreFilters(1)])
    }

    @MainActor
    func testWithoutTheCatalogTheAlertKeepsItsNameAndOnlyTheKeyword() async throws {
        let env = AlertsTestEnvironment(catalog: false)
        defer { env.tearDown() }
        env.api.onGetSavedSearches = {
            SavedSearchesDTO(searches: [SavedSearchesViewModelTests.alert("s1", params: ["q": "clio", "category": "vehicules", "wilaya": "16"])])
        }
        let model = env.makeModel()
        await model.appear()?.value
        XCTAssertNil(model.state.errorMessage)
        let alert = try XCTUnwrap(model.state.items.first)
        XCTAssertEqual(alert.name, "clio · Alger")
        let criteria = SavedSearchCriteria.criteria(for: alert.params, catalog: model.state.catalog, language: "fr")
        XCTAssertEqual(criteria.map { $0.kind }, [AlertCriterionKind.keyword])
    }

    @MainActor
    func testAFailedLoadShowsTheErrorAndRetryReloads() async throws {
        let env = AlertsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetSavedSearches = { throw FakeWeydaAPI.apiError(500) }
        let model = env.makeModel()
        await model.appear()?.value
        XCTAssertFalse(model.state.isLoading)
        XCTAssertNotNil(model.state.errorMessage)

        env.api.onGetSavedSearches = { SavedSearchesDTO(searches: [SavedSearchesViewModelTests.alert("s1")]) }
        await model.load().value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.items.map { $0.id }, ["s1"])
    }

    @MainActor
    func testDeletionIsDeferredUntilTheBannerClosesAndARefusalPutsTheAlertBack() async throws {
        let env = AlertsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetSavedSearches = {
            SavedSearchesDTO(searches: ["s1", "s2", "s3"].map { SavedSearchesViewModelTests.alert($0) })
        }
        let deleted = FakeWeydaAPI.Box<[String]>([])
        env.api.onDeleteSavedSearch = { id in
            deleted.value.append(id)
            return SimpleResponseDTO()
        }
        let model = env.makeModel()
        await model.appear()?.value
        let second = try XCTUnwrap(model.state.items.first(where: { $0.id == "s2" }))

        // Supprimer : la ligne part tout de suite, « Alerte supprimée » + « Annuler » ; rien n'est encore envoyé.
        XCTAssertNil(model.delete(second))
        XCTAssertEqual(model.state.items.map { $0.id }, ["s1", "s3"])
        XCTAssertEqual(model.state.banner?.message, L10n.listsAlertDeleted)
        let action = try XCTUnwrap(model.state.banner?.action)
        XCTAssertEqual(action, BannerAction.undo(SavedSearchesViewModel.undoPrefix + "s2"))
        XCTAssertTrue(deleted.value.isEmpty)

        // Annuler : l'alerte revient à SA place, rien ne part, même quand la bannière se ferme ensuite.
        model.bannerAction(action)
        XCTAssertNil(model.state.banner)
        XCTAssertEqual(model.state.items.map { $0.id }, ["s1", "s2", "s3"])
        XCTAssertNil(model.bannerDismissed())
        XCTAssertTrue(deleted.value.isEmpty)

        // Supprimer puis laisser la bannière se fermer : la requête part à ce moment-là.
        model.delete(second)
        let task = model.bannerDismissed()
        XCTAssertNil(model.state.banner)
        await task?.value
        XCTAssertEqual(deleted.value, ["s2"])
        XCTAssertEqual(model.state.items.map { $0.id }, ["s1", "s3"])
        XCTAssertNil(model.state.banner)

        // Refus du serveur : l'alerte revient à SA place, avec le message d'erreur.
        env.api.onDeleteSavedSearch = { _ in throw FakeWeydaAPI.apiError(500) }
        let first = try XCTUnwrap(model.state.items.first)
        model.delete(first)
        XCTAssertEqual(model.state.items.map { $0.id }, ["s3"])
        await model.bannerDismissed()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["s1", "s3"])
        XCTAssertEqual(model.state.banner?.kind, WeydaBanner.Kind.error)
        XCTAssertNil(model.state.banner?.action)
        model.bannerDismissed()

        // 404 : déjà supprimée (sur le site) — c'est fait, elle ne revient pas, aucun message d'erreur.
        env.api.onDeleteSavedSearch = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
        model.delete(first)
        await model.bannerDismissed()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["s3"])
        XCTAssertNil(model.state.banner)
    }

    /// Une suppression en attente n'est jamais perdue : la suivante l'envoie (et la remplace dans la bannière), quitter
    /// l'écran aussi ; une relecture ne rend pas une alerte en attente.
    @MainActor
    func testAPendingDeletionIsSentByTheNextOneAndWhenLeavingTheScreen() async throws {
        let env = AlertsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetSavedSearches = {
            SavedSearchesDTO(searches: ["s1", "s2", "s3"].map { SavedSearchesViewModelTests.alert($0) })
        }
        let deleted = FakeWeydaAPI.Box<[String]>([])
        env.api.onDeleteSavedSearch = { id in
            deleted.value.append(id)
            return SimpleResponseDTO()
        }
        let model = env.makeModel()
        await model.appear()?.value
        let first = try XCTUnwrap(model.state.items.first(where: { $0.id == "s1" }))
        let second = try XCTUnwrap(model.state.items.first(where: { $0.id == "s2" }))

        model.delete(first)
        // Retour sur l'écran pendant l'attente : la relecture ne rend pas l'alerte.
        await model.appear()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["s2", "s3"])
        XCTAssertTrue(deleted.value.isEmpty)

        // Suppression suivante : la précédente part, « Annuler » vise désormais la nouvelle.
        let previous = model.delete(second)
        XCTAssertNotNil(previous)
        await previous?.value
        XCTAssertEqual(deleted.value, ["s1"])
        XCTAssertEqual(model.state.items.map { $0.id }, ["s3"])
        XCTAssertEqual(model.state.banner?.action, BannerAction.undo(SavedSearchesViewModel.undoPrefix + "s2"))

        // L'ancienne action « Annuler » n'a plus d'effet.
        model.bannerAction(BannerAction.undo(SavedSearchesViewModel.undoPrefix + "s1"))
        XCTAssertEqual(model.state.items.map { $0.id }, ["s3"])
        XCTAssertEqual(deleted.value, ["s1"])

        // Quitter l'écran : la suppression en attente (s2) part.
        let leaving = model.disappear()
        XCTAssertNotNil(leaving)
        await leaving?.value
        XCTAssertEqual(deleted.value, ["s1", "s2"])
        XCTAssertNil(model.state.banner)
        XCTAssertNil(model.disappear())
    }

    @MainActor
    func testOpeningAnAlertHandsItsParametersToTheListingsTab() async throws {
        let env = AlertsTestEnvironment()
        defer { env.tearDown() }
        let params: [String: String] = ["q": "golf", "category": "voitures", "wilaya": "31", "attr_make": "volkswagen"]
        env.api.onGetSavedSearches = { SavedSearchesDTO(searches: [SavedSearchesViewModelTests.alert("s1", params: params)]) }
        let model = env.makeModel()
        await model.appear()?.value
        let alert = try XCTUnwrap(model.state.items.first)
        XCTAssertNil(env.search.pendingParams)
        model.open(alert)
        // L'onglet Annonces les applique de lui-même (ListingsViewModelTests : même avant son premier affichage).
        XCTAssertEqual(env.search.pendingParams, params)
    }

    @MainActor
    func testReturningToTheScreenShowsAnAlertCreatedMeanwhileAndARefreshFailureKeepsTheList() async throws {
        let env = AlertsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetSavedSearches = { SavedSearchesDTO(searches: [SavedSearchesViewModelTests.alert("s1")]) }
        let model = env.makeModel()
        await model.appear()?.value

        // Alerte créée depuis l'onglet Annonces, puis retour sur l'écran : relecture sans squelettes.
        env.api.onGetSavedSearches = {
            SavedSearchesDTO(searches: [SavedSearchesViewModelTests.alert("s2"), SavedSearchesViewModelTests.alert("s1")])
        }
        let again = model.appear()
        XCTAssertFalse(model.state.isLoading)
        await again?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["s2", "s1"])
        XCTAssertEqual(env.api.count("getSavedSearches"), 2)

        // Tirer pour rafraîchir : un échec garde la liste et donne un message.
        env.api.onGetSavedSearches = { throw FakeWeydaAPI.apiError(500) }
        await model.pullToRefresh()
        XCTAssertEqual(model.state.items.map { $0.id }, ["s2", "s1"])
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.banner?.kind, .error)
        XCTAssertFalse(model.state.isRefreshing)
    }

    // MARK: - Critères (logique pure)

    func testCriteriaReadEveryKindOfParameter() {
        let vehicles = CategoryDTO(
            id: "cat_veh",
            slug: "vehicules",
            nameFr: "Véhicules",
            children: [CategoryDTO(id: "cat_voit", slug: "voitures", nameFr: "Voitures")]
        ).toDomain()
        let catalog = AlertCatalog(categories: [vehicles], wilayas: [WilayaDTO(id: 16, nameFr: "Alger").toDomain()])

        // Sous-catégorie passée pour `category` (l'onglet Annonces l'accepte) : son nom, l'icône de sa racine.
        let child = SavedSearchCriteria.criteria(for: ["category": "voitures"], catalog: catalog, language: "fr")
        XCTAssertEqual(child.map { $0.title }, ["Voitures"])
        XCTAssertEqual(child.map { $0.icon }, [AlertCriterionIcon.asset(CategoryIcon.assetName(forSlug: "vehicules"))])

        // Sous-catégorie inconnue → la racine ; catégorie et wilaya inconnues → rien (le nom de l'alerte suffit).
        let unknownChild = SavedSearchCriteria.criteria(for: ["category": "vehicules", "subcategory": "inconnue"], catalog: catalog, language: "fr")
        XCTAssertEqual(unknownChild.map { $0.title }, ["Véhicules"])
        XCTAssertTrue(SavedSearchCriteria.criteria(for: ["category": "inconnue", "wilaya": "99"], catalog: catalog, language: "fr").isEmpty)
        XCTAssertTrue(SavedSearchCriteria.criteria(for: ["category": "vehicules"], catalog: AlertCatalog(), language: "fr").isEmpty)

        let all = SavedSearchCriteria.criteria(
            for: [
                "q": "  golf 7 ", "wilaya": "16", "priceType": "NEGOTIABLE", "priceMin": "100000", "priceMax": "2000000",
                "featured": "1", "attr_make": "volkswagen", "attr_year_min": "2015",
            ],
            catalog: catalog,
            language: "fr"
        )
        XCTAssertEqual(all.map { $0.kind }, [AlertCriterionKind.keyword, .location, .priceType, .price, .featured, .attributes])
        let expected: [String] = [
            L10n.listsAlertKeyword("golf 7"),
            "Alger",
            ListingsFilterRules.priceTypeTitle(.negotiable),
            L10n.filtersPriceBetween(Format.integer(100_000), Format.integer(2_000_000)),
            L10n.filtersFeaturedChip,
            L10n.listsAlertMoreFilters(2),
        ]
        XCTAssertEqual(all.map { $0.title }, expected)
    }

    func testChipRowsCounterCommunesAndSpokenLabel() {
        let kinds: [AlertCriterionKind] = [.keyword, .category, .location, .price, .featured]
        let chips: [AlertCriterion] = kinds.map { kind in
            AlertCriterion(kind: kind, title: kind.rawValue, icon: .symbol("star"))
        }
        XCTAssertEqual(SavedSearchCriteria.rows(chips, perRow: 2).map { $0.count }, [2, 2, 1])
        XCTAssertEqual(SavedSearchCriteria.rows(chips, perRow: 0).map { $0.count }, [1, 1, 1, 1, 1])
        XCTAssertEqual(SavedSearchCriteria.rows(chips, perRow: 9).count, 1)
        XCTAssertTrue(SavedSearchCriteria.rows([], perRow: 3).isEmpty)

        XCTAssertEqual(SavedSearchCriteria.usage(count: 3, limit: 5), L10n.listsAlertsUsage(Format.ltrIsolate("3 / 5")))

        let alerts: [SavedSearch] = [
            SavedSearch(id: "s1", name: "a", params: ["wilaya": "31", "commune": "3107"], createdAt: nil),
            SavedSearch(id: "s2", name: "b", params: ["wilaya": "16"], createdAt: nil),
            SavedSearch(id: "s3", name: "c", params: ["wilaya": "16", "commune": "1605"], createdAt: nil),
            SavedSearch(id: "s4", name: "d", params: ["wilaya": "31", "commune": "3101"], createdAt: nil),
        ]
        XCTAssertEqual(SavedSearchCriteria.communeWilayas(in: alerts), [16, 31])

        let undated = SavedSearch(id: "s1", name: "clio · Alger", params: [:], createdAt: nil)
        XCTAssertNil(SavedSearchCriteria.createdOn(undated))
        XCTAssertEqual(SavedSearchCriteria.accessibilityLabel(for: undated, criteria: Array(chips.prefix(2))), "clio · Alger, keyword, category")
        let dated = SavedSearch(id: "s1", name: "clio · Alger", params: [:], createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertNotNil(SavedSearchCriteria.createdOn(dated))
    }
}

/// Fausse API (catalogue : 2 catégories avec une sous-catégorie, Alger et Oran, une commune par wilaya) et historique
/// de recherche dans une suite UserDefaults jetable.
@MainActor
private final class AlertsTestEnvironment {
    let api: FakeWeydaAPI
    let search: SearchRepository
    private let suiteName: String
    private let defaults: UserDefaults

    init(catalog: Bool = true) {
        let api = FakeWeydaAPI()
        self.api = api
        let suiteName = "SavedSearchesViewModelTests-\(UUID().uuidString)"
        self.suiteName = suiteName
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        self.defaults = defaults
        self.search = SearchRepository(api: api, history: SearchHistoryStore(defaults: defaults))
        guard catalog else { return }
        api.onGetCategories = {
            [
                CategoryDTO(
                    id: "cat_veh",
                    slug: "vehicules",
                    nameFr: "Véhicules",
                    nameAr: "المركبات",
                    nameEn: "Vehicles",
                    children: [CategoryDTO(id: "cat_voit", slug: "voitures", nameFr: "Voitures", nameAr: "سيارات", nameEn: "Cars")]
                ),
                CategoryDTO(
                    id: "cat_imm",
                    slug: "immobilier",
                    nameFr: "Immobilier",
                    nameAr: "العقارات",
                    nameEn: "Real Estate",
                    children: [CategoryDTO(id: "cat_va", slug: "vente-appartement", nameFr: "Vente appartement")]
                ),
            ]
        }
        api.onGetWilayas = {
            [WilayaDTO(id: 16, nameFr: "Alger", nameAr: "الجزائر"), WilayaDTO(id: 31, nameFr: "Oran", nameAr: "وهران")]
        }
        api.onGetCommunes = { id in
            [CommuneDTO(id: id * 100 + 5, nameFr: "Bab Ezzouar", nameAr: "باب الزوار", wilayaId: id)]
        }
    }

    func makeModel() -> SavedSearchesViewModel {
        SavedSearchesViewModel(
            savedSearches: SavedSearchesRepository(api: api),
            search: search,
            categories: CategoryRepository(api: api),
            geo: GeoRepository(api: api)
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

#if DEBUG
/// Données simulées de LISTS (`MockFixtures/routes-lists.json` + `lists/`) lues par les VRAIS repositories à travers
/// `LiveWeydaAPI` et l'API simulée : JSON valides, routes servies (celles du tour 10l).
final class MockListsFixturesTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testFavoritesFixtures() async throws {
        let api = try makeAPI()
        let favorites = FavoritesRepository(api: api)
        let listings = try await favorites.list()
        XCTAssertEqual(listings.map(\.id), ["mock-a3", "mock-a25", "mock-a17", "mock-a10", "mock-a14"])
        XCTAssertTrue(listings.allSatisfy { $0.images.count == 1 })
        XCTAssertEqual(favorites.ids.count, 5)
        // La fiche relit l'état du cœur : plein pour les cinq favoris simulés.
        let isFavorite = try await favorites.refresh("mock-a3")
        XCTAssertTrue(isFavorite)
        let removed = try await favorites.toggle("mock-a17")
        XCTAssertFalse(removed)
        let added = try await favorites.toggle("mock-a1")
        XCTAssertTrue(added)
    }

    @MainActor
    func testAlertsFixturesAndTheOpenedAlertResults() async throws {
        let api = try makeAPI()
        let repository = SavedSearchesRepository(api: api)
        let alerts = try await repository.list()
        XCTAssertEqual(alerts.map(\.id), ["mock-s1", "mock-s2", "mock-s3", "mock-s4"])
        XCTAssertEqual(alerts.first?.params, ["q": "clio", "category": "vehicules", "wilaya": "16"])
        XCTAssertTrue(alerts.allSatisfy { $0.createdAt != nil })
        try await repository.delete(id: "mock-s2")

        // « Clio à Alger » ouverte dans l'onglet Annonces : la Clio d'Alger seule.
        let results = try await AnnonceRepository(api: api).search(
            ListingQuery(q: "clio", category: "vehicules", wilaya: 16, sort: "relevance", withFacets: true)
        )
        XCTAssertEqual(results.items.map(\.id), ["mock-a25"])
        XCTAssertEqual(results.total, 1)
    }
}
#endif
