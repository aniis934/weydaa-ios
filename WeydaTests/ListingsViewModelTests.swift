import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage de `ListingsViewModelTest.kt` (Android), mêmes cas et mêmes données, puis les règles propres à iOS :
/// critères d'ouverture de l'onglet, sous-catégorie suggérée, « Vouliez-vous dire », rafraîchissement, retour du
/// réseau, page suivante en échec, selects dépendants, puces et facettes. `waitUntilIdle()` remplace
/// `advanceUntilIdle()`. (`CategoriesFilterTest.kt` — filtre de la feuille Catégories de l'accueil — est déjà porté
/// dans `CatalogRepositoriesTests`.)
final class ListingsViewModelTests: XCTestCase {

    @MainActor
    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }

    // MARK: - Portage d'Android

    @MainActor
    func testAlertSendsTheSiteParametersThenNoticesCreatedDuplicateAndLimit() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: ListingsLaunch(q: "clio"))
        await vm.waitUntilIdle()
        vm.onCategorySelect("vehicules")
        await vm.waitUntilIdle()
        vm.applyFilters(ListingFilters(
            subcategory: "voitures",
            wilayaId: 16,
            priceMax: "2000000",
            sort: "priceAsc",
            attributes: ["make": "renault"]
        ))
        await vm.waitUntilIdle()
        XCTAssertEqual(
            vm.state.toSearchParams(),
            ["q": "clio", "category": "vehicules", "subcategory": "voitures", "wilaya": "16", "priceMax": "2000000", "attr_make": "renault"]
        )
        XCTAssertTrue(vm.state.canSaveSearch)

        env.api.onCreateSavedSearch = { body in
            SavedSearchCreatedDTO(search: SavedSearchDTO(id: "s1", name: "clio · Véhicules", params: body.params))
        }
        vm.saveSearch()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.notice, .alertCreated)
        vm.noticeShown()

        env.api.onCreateSavedSearch = { body in
            SavedSearchCreatedDTO(search: SavedSearchDTO(id: "s1", name: "clio", params: body.params), duplicate: true)
        }
        vm.saveSearch()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.notice, .alertDuplicate)

        env.api.onCreateSavedSearch = { _ in
            throw FakeWeydaAPI.apiError(400, #"{"error":"savedSearchLimit"}"#)
        }
        vm.saveSearch()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.notice, .message(L10n.alertLimit))

        vm.clearFilters()
        vm.onQueryChange("")
        await vm.waitUntilIdle()
        XCTAssertTrue(vm.state.canSaveSearch) // une catégorie seule suffit
        vm.onCategorySelect(nil)
        await vm.waitUntilIdle()
        XCTAssertFalse(vm.state.canSaveSearch)
    }

    @MainActor
    func testOpenedAlertIsAppliedWithItsSubcategoryResolvedEvenBeforeCategoriesLoad() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        env.search.pendingParams = [
            "q": "golf", "category": "voitures", "wilaya": "31", "priceType": "NEGOTIABLE", "attr_make": "volkswagen",
        ]
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        let state = vm.state
        XCTAssertEqual(state.query, "golf")
        XCTAssertEqual(state.categorySlug, "vehicules")
        XCTAssertEqual(state.filters.subcategory, "voitures")
        XCTAssertEqual(state.filters.wilayaId, 31)
        XCTAssertEqual(state.filters.priceType, .negotiable)
        XCTAssertEqual(state.filters.attributes, ["make": "volkswagen"])
        XCTAssertNil(env.search.pendingParams)
        let call = try XCTUnwrap(env.api.searchCalls.last { $0.q == "golf" })
        XCTAssertEqual(call.category, "vehicules")
        XCTAssertEqual(call.subcategory, "voitures")
        XCTAssertEqual(call.attrs, ["attr_make": "volkswagen"])

        env.search.pendingParams = ["category": "services"]
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.categorySlug, "services")
        XCTAssertEqual(vm.state.query, "")
        XCTAssertNil(vm.state.filters.wilayaId)
    }

    @MainActor
    func testSuggestionsFilterByCategoryOrWilayaSearchAListingAndFeedTheHistory() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()

        vm.onSuggestionPick(Suggestion(text: "Véhicules", type: .category, slug: "vehicules"))
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.category, "vehicules")
        XCTAssertEqual(vm.state.query, "")

        vm.onSuggestionPick(Suggestion(text: "Alger", type: .wilaya, id: 16))
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.wilaya, 16)
        XCTAssertEqual(env.lastCall?.category, "vehicules")

        vm.onSuggestionPick(Suggestion(text: "Clio 4", type: .listing))
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.q, "Clio 4")
        XCTAssertEqual(env.lastCall?.sort, "relevance")
        XCTAssertEqual(vm.history, ["Clio 4"])

        vm.onHistoryPick("golf")
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.q, "golf")
        XCTAssertEqual(vm.history, ["golf", "Clio 4"])
    }

    @MainActor
    func testWilayaLaunchArgumentIsTheInitialFilter() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: ListingsLaunch(wilaya: 31))
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.wilaya, 31)
        XCTAssertEqual(vm.state.filters.activeCount, 1)
    }

    @MainActor
    func testDefaultSearchSortsByNewestWithoutFacetsAndLoadsTheCatalog() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.searchCalls.count, 1)
        let call = try XCTUnwrap(env.api.searchCalls.first)
        XCTAssertNil(call.q)
        XCTAssertNil(call.category)
        XCTAssertEqual(call.sort, "newest")
        XCTAssertNil(call.withFacets)
        XCTAssertTrue(call.attrs.isEmpty)
        XCTAssertEqual(vm.state.wilayas.count, 2)
        XCTAssertEqual(vm.state.categories.count, 2)
        XCTAssertEqual(vm.state.filters.activeCount, 0)
        XCTAssertTrue(vm.state.facets.isEmpty)
    }

    @MainActor
    func testCategoryAsksFacetsOnTheFirstPageOnlyAndLoadsAttributesForTheirLabels() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.onCategorySelect("vehicules")
        await vm.waitUntilIdle()
        let call = try XCTUnwrap(env.lastCall)
        XCTAssertEqual(call.category, "vehicules")
        XCTAssertEqual(call.withFacets, 1)
        XCTAssertEqual(vm.state.facets["make"]?.map(\.count), [42])
        XCTAssertEqual(vm.state.attributeSet?.attribute("make")?.label, "Marque")
        XCTAssertEqual(vm.state.selectedCategory?.slug, "vehicules")

        vm.loadMore()
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.page, 2)
        XCTAssertNil(env.lastCall?.withFacets)
        XCTAssertEqual(vm.state.items.map(\.id), ["a1", "a2"])
    }

    @MainActor
    func testAppliedFiltersSendEveryParameterPrefixAttributesAndRestartAtPageOne() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: ListingsLaunch(q: "clio"))
        await vm.waitUntilIdle()
        XCTAssertEqual(env.lastCall?.sort, "relevance")
        vm.onCategorySelect("vehicules")
        await vm.waitUntilIdle()
        vm.loadMore()
        await vm.waitUntilIdle()

        vm.onFilterWilayaChange(16)
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.communes.count, 1)
        vm.applyFilters(ListingFilters(
            subcategory: "voitures",
            wilayaId: 16,
            communeId: 1601,
            priceType: .negotiable,
            priceMin: "100000",
            priceMax: "2000000",
            sort: "priceAsc",
            attributes: ["make": "renault"]
        ))
        await vm.waitUntilIdle()
        let call = try XCTUnwrap(env.lastCall)
        XCTAssertEqual(call.q, "clio")
        XCTAssertEqual(call.category, "vehicules")
        XCTAssertEqual(call.subcategory, "voitures")
        XCTAssertEqual(call.wilaya, 16)
        XCTAssertEqual(call.commune, 1601)
        XCTAssertEqual(call.priceType, "NEGOTIABLE")
        XCTAssertEqual(call.priceMin, 100_000)
        XCTAssertEqual(call.priceMax, 2_000_000)
        XCTAssertEqual(call.sort, "priceAsc")
        XCTAssertEqual(call.page, 1)
        XCTAssertEqual(call.withFacets, 1)
        XCTAssertEqual(call.attrs, ["attr_make": "renault"])
        XCTAssertEqual(vm.state.filters.activeCount, 8)
        XCTAssertFalse(vm.state.showFilters)

        // Retirer un filtre depuis les puces.
        vm.updateFilters { filters in
            filters.wilayaId = nil
            filters.communeId = nil
        }
        await vm.waitUntilIdle()
        XCTAssertNil(env.lastCall?.wilaya)
        XCTAssertNil(env.lastCall?.commune)
        XCTAssertEqual(vm.state.filters.activeCount, 6)

        vm.clearFilters()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.filters.activeCount, 0)
        XCTAssertEqual(env.lastCall?.attrs, [:])
        XCTAssertEqual(env.lastCall?.sort, "relevance")
    }

    @MainActor
    func testFacetsServerErrorRetriesWithoutFacetsAndShowsTheList() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetAnnonces = { call in
            if call.withFacets == 1 {
                throw FakeWeydaAPI.apiError(500)
            }
            return AnnoncesPageDTO(annonces: [AnnonceDTO(id: "a1", title: "T")], total: 1, page: 1, totalPages: 1)
        }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.onCategorySelect("vehicules")
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.searchCalls.suffix(2).map(\.withFacets), [1, nil])
        XCTAssertFalse(vm.state.isError)
        XCTAssertEqual(vm.state.items.count, 1)
        XCTAssertTrue(vm.state.facets.isEmpty)
    }

    @MainActor
    func testChangingCategoryResetsSubcategoryAttributesAndFacets() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.onCategorySelect("vehicules")
        await vm.waitUntilIdle()
        vm.applyFilters(ListingFilters(subcategory: "voitures", wilayaId: 16, attributes: ["make": "renault"]))
        await vm.waitUntilIdle()
        vm.onCategorySelect("services")
        await vm.waitUntilIdle()
        let filters = vm.state.filters
        XCTAssertNil(filters.subcategory)
        XCTAssertTrue(filters.attributes.isEmpty)
        XCTAssertEqual(filters.wilayaId, 16)
        XCTAssertEqual(env.lastCall?.category, "services")
        vm.onCategorySelect(nil)
        await vm.waitUntilIdle()
        XCTAssertNil(vm.state.attributeSet)
        XCTAssertTrue(vm.state.facets.isEmpty)
    }

    @MainActor
    func testAListingPushedBackToTheNextPageIsNotDuplicated() async throws {
        // Pagination par offset : une annonce publiée entre deux pages ramène « a1 » en tête de la page 2.
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetAnnonces = { call in
            let ids = call.page == 1 ? ["a0", "a1"] : ["a1", "a2"]
            return AnnoncesPageDTO(annonces: ids.map { AnnonceDTO(id: $0, title: "T") }, total: 3, page: call.page, totalPages: 2)
        }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.loadMore()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.items.map(\.id), ["a0", "a1", "a2"])
    }

    @MainActor
    func testANextPageInFlightIsDroppedByANewSearch() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let gate = FakeWeydaAPI.Box(false)
        env.api.onGetAnnonces = { call in
            if call.page == 2 {
                while !gate.value {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
            }
            let id = "\(call.category ?? "tout")-\(call.page)"
            return AnnoncesPageDTO(annonces: [AnnonceDTO(id: id, title: "T")], total: 30, page: call.page, totalPages: 2)
        }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.loadMore() // page 2 de « tout » suspendue côté réseau
        let inFlight = await eventually { env.api.searchCalls.count == 2 }
        XCTAssertTrue(inFlight)
        vm.onCategorySelect("services")
        await vm.waitUntilIdle()
        gate.value = true
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.items.map(\.id), ["services-1"])
        XCTAssertFalse(vm.state.isLoadingMore)
    }

    @MainActor
    func testWilayaSuggestionDropsTheTypedWordAndCommunesFollowTheAppliedFilter() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.onQueryChange("oran")
        vm.onSuggestionPick(Suggestion(text: "Oran", type: .wilaya, id: 31))
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.query, "")
        XCTAssertNil(env.lastCall?.q)
        XCTAssertEqual(env.lastCall?.wilaya, 31)

        XCTAssertTrue(vm.state.communes.isEmpty)
        vm.openFilters()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.communes.map(\.id), [3101])
        XCTAssertTrue(vm.state.showFilters)
    }

    // MARK: - iOS : ouverture de l'onglet, suggestions, correction

    @MainActor
    func testLaunchAfterStartReplacesTheSearchAndAnEmptyLaunchKeepsIt() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        let searches = env.api.searchCalls.count

        vm.start(with: ListingsLaunch()) // onglet touché, « Voir tout » : rien ne change
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.searchCalls.count, searches)

        vm.start(with: ListingsLaunch(category: "voitures", wilaya: 16))
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.categorySlug, "vehicules")
        XCTAssertEqual(vm.state.filters.subcategory, "voitures")
        XCTAssertEqual(vm.state.filters.wilayaId, 16)
        let call = try XCTUnwrap(env.lastCall)
        XCTAssertEqual(call.category, "vehicules")
        XCTAssertEqual(call.subcategory, "voitures")
        XCTAssertEqual(call.wilaya, 16)

        vm.start(with: ListingsLaunch(q: "golf", featured: true))
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.query, "golf")
        XCTAssertNil(vm.state.categorySlug)
        XCTAssertNil(vm.state.filters.wilayaId)
        XCTAssertTrue(vm.state.filters.featuredOnly)
        XCTAssertEqual(env.lastCall?.featured, 1)
        XCTAssertNil(env.lastCall?.category)
    }

    @MainActor
    func testFirstLaunchWithASubcategorySelectsItsRootOnceCategoriesArrive() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: ListingsLaunch(category: "voitures"))
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.categorySlug, "vehicules")
        XCTAssertEqual(vm.state.filters.subcategory, "voitures")
        let call = try XCTUnwrap(env.api.searchCalls.last { $0.category == "vehicules" })
        XCTAssertEqual(call.subcategory, "voitures")
    }

    @MainActor
    func testSubcategorySuggestionSelectsItsRootCategory() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.onQueryChange("voit")
        vm.onSuggestionPick(Suggestion(text: "Voitures", type: .category, slug: "voitures"))
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.query, "")
        XCTAssertEqual(vm.state.categorySlug, "vehicules")
        XCTAssertEqual(vm.state.filters.subcategory, "voitures")
        XCTAssertEqual(env.lastCall?.category, "vehicules")
        XCTAssertEqual(env.lastCall?.subcategory, "voitures")
    }

    @MainActor
    func testEmptyResultAsksDidYouMeanAndTheCorrectionBecomesTheKeyword() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetAnnonces = { call in
            let ids: [String] = call.q == "clio" ? ["a1"] : []
            return AnnoncesPageDTO(
                annonces: ids.map { AnnonceDTO(id: $0, title: "T") },
                total: ids.count,
                page: 1,
                totalPages: ids.isEmpty ? 0 : 1
            )
        }
        env.api.onDidYouMean = { q in
            DidYouMeanDTO(suggestion: q == "clyo" ? "clio" : nil)
        }
        let vm = env.makeViewModel()
        vm.start(with: ListingsLaunch(q: "clyo"))
        await vm.waitUntilIdle()
        XCTAssertTrue(vm.state.items.isEmpty)
        XCTAssertFalse(vm.state.isError)
        XCTAssertEqual(vm.state.didYouMean, "clio")

        vm.onDidYouMean("clio")
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.query, "clio")
        XCTAssertNil(vm.state.didYouMean)
        XCTAssertEqual(env.lastCall?.q, "clio")
        XCTAssertEqual(vm.state.items.count, 1)
    }

    // MARK: - iOS : rafraîchir, réseau, page suivante, selects dépendants

    @MainActor
    func testPullToRefreshKeepsTheListAndReportsAFailureAsANotice() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.items.count, 1)

        env.api.onGetAnnonces = { _ in throw URLError(.notConnectedToInternet) }
        await vm.refresh()
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.state.items.count, 1)
        XCTAssertFalse(vm.state.isRefreshing)
        XCTAssertFalse(vm.state.isError)
        XCTAssertEqual(vm.state.notice, .message(L10n.errorOffline))
        XCTAssertEqual(vm.state.notice?.banner.kind, WeydaBanner.Kind.error)
    }

    /// Cœur d'une ligne refusé par le serveur : le cœur revient (repository) et la bannière d'erreur le dit (muet avant
    /// la phase 8) ; alerte créée = bannière de réussite.
    @MainActor
    func testARefusedHeartBecomesAnErrorNotice() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        env.api.onAddFavorite = { _ in throw FakeWeydaAPI.apiError(500) }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        let listing = try XCTUnwrap(vm.state.items.first)

        vm.toggleFavorite(listing)
        await vm.waitUntilIdle()
        XCTAssertFalse(vm.favoriteIds.contains(listing.id))
        XCTAssertEqual(vm.state.notice, .message(L10n.errorServer))
        XCTAssertEqual(ListingsNotice.alertCreated.banner.kind, WeydaBanner.Kind.success)
        XCTAssertEqual(ListingsNotice.alertDuplicate.banner.kind, WeydaBanner.Kind.info)
    }

    @MainActor
    func testBackOnlineRetriesASearchLeftInError() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let failing = FakeWeydaAPI.Box(true)
        env.api.onGetAnnonces = { call in
            if failing.value {
                throw URLError(.notConnectedToInternet)
            }
            return AnnoncesPageDTO(annonces: [AnnonceDTO(id: "a1", title: "T")], total: 1, page: call.page, totalPages: 1)
        }
        let online = PassthroughSubject<Bool, Never>()
        let vm = env.makeViewModel(online: online.eraseToAnyPublisher())
        vm.start(with: nil)
        await vm.waitUntilIdle()
        XCTAssertTrue(vm.state.isError)
        XCTAssertEqual(vm.state.errorMessage, L10n.errorOffline)

        online.send(true) // déjà en ligne : pas de relance
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.searchCalls.count, 1)

        failing.value = false
        online.send(false)
        online.send(true)
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.searchCalls.count, 2)
        XCTAssertFalse(vm.state.isError)
        XCTAssertEqual(vm.state.items.map(\.id), ["a1"])
    }

    @MainActor
    func testNextPageFailureOffersRetryThenLoadsThePage() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        let failing = FakeWeydaAPI.Box(true)
        env.api.onGetAnnonces = { call in
            if call.page == 2 && failing.value {
                throw URLError(.timedOut)
            }
            return AnnoncesPageDTO(annonces: [AnnonceDTO(id: "a\(call.page)", title: "T")], total: 30, page: call.page, totalPages: 2)
        }
        let vm = env.makeViewModel()
        vm.start(with: nil)
        await vm.waitUntilIdle()
        vm.loadMore()
        await vm.waitUntilIdle()
        XCTAssertTrue(vm.state.loadMoreFailed)
        XCTAssertFalse(vm.state.canLoadMore)
        let calls = env.api.searchCalls.count
        vm.loadMore() // le défilement ne relance plus
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.searchCalls.count, calls)

        failing.value = false
        vm.retryLoadMore()
        await vm.waitUntilIdle()
        XCTAssertFalse(vm.state.loadMoreFailed)
        XCTAssertEqual(vm.state.items.map(\.id), ["a1", "a2"])
    }

    @MainActor
    func testDependentOptionsAreLoadedOncePerParentValue() async throws {
        let env = ListingsTestEnvironment()
        defer { env.tearDown() }
        env.api.onGetAttributes = { _, _, _, context in
            if context["ctx_make"] == "renault" {
                return AttributesResponseDTO(attributes: [
                    AttributeDTO(
                        key: "model",
                        type: "select",
                        filterable: true,
                        options: ["clio-4"],
                        dependsOn: "make",
                        optionLabels: ["clio-4": "Clio 4"]
                    ),
                ])
            }
            return AttributesResponseDTO(attributes: [
                AttributeDTO(key: "make", type: "select", filterable: true, options: ["renault"]),
                AttributeDTO(key: "model", type: "select", filterable: true, dependsOn: "make"),
            ])
        }
        let vm = env.makeViewModel()
        vm.start(with: ListingsLaunch(category: "vehicules"))
        await vm.waitUntilIdle()
        vm.loadDependentOptions(subcategory: nil, attributes: ["make": "renault"])
        await vm.waitUntilIdle()
        let key = ListingsState.dependentKey("model", parentValue: "renault")
        XCTAssertEqual(vm.state.dependentOptions[key]?.map(\.label), ["Clio 4"])

        let requests = env.api.count("getAttributes")
        vm.loadDependentOptions(subcategory: nil, attributes: ["make": "renault"])
        await vm.waitUntilIdle()
        XCTAssertEqual(env.api.count("getAttributes"), requests)
    }

    // MARK: - iOS : règles pures des filtres

    func testActiveChipsFollowAndroidOrderAndEachRemovesItsOwnFilter() {
        var state = ListingsState()
        state.categories = [
            CategoryDTO(
                id: "cat_veh",
                slug: "vehicules",
                nameFr: "Véhicules",
                children: [CategoryDTO(id: "cat_voit", slug: "voitures", nameFr: "Voitures")]
            ).toDomain(),
        ]
        state.categorySlug = "vehicules"
        state.wilayas = [WilayaDTO(id: 16, nameFr: "Alger").toDomain()]
        state.communes = [CommuneDTO(id: 1605, nameFr: "Bab Ezzouar", wilayaId: 16).toDomain()]
        state.attributeSet = AttributesResponseDTO(attributes: [
            AttributeDTO(key: "make", type: "select", filterable: true, options: ["renault"], label: "Marque", optionLabels: ["renault": "Renault"]),
            AttributeDTO(key: "year", type: "number", filterable: true, filterType: "range", label: "Année"),
            AttributeDTO(key: "exchange_possible", type: "boolean", filterable: true, filterType: "boolean", label: "Échange possible"),
        ]).toDomain()
        state.filters = ListingFilters(
            subcategory: "voitures",
            wilayaId: 16,
            communeId: 1605,
            priceType: .negotiable,
            priceMin: "100000",
            priceMax: "2000000",
            sort: "priceAsc",
            attributes: ["exchange_possible": "true", "year_min": "2015", "make": "renault"],
            featuredOnly: true
        )

        let chips = ListingsFilterRules.activeChips(for: state, language: "fr")
        XCTAssertEqual(chips.map(\.title), [
            "Voitures",
            L10n.sortPriceAsc,
            "Alger · Bab Ezzouar",
            L10n.postPriceNegotiable,
            L10n.filtersPriceBetween(Format.integer(100_000), Format.integer(2_000_000)),
            L10n.filtersFeaturedChip,
            L10n.filtersAttrValue("Marque", "Renault"),
            L10n.filtersAttrMin("Année", "2015"),
            "Échange possible",
        ])
        XCTAssertEqual(chips.map(\.kind), [
            .subcategory, .sort, .location, .priceType, .price, .featured,
            .attribute("make"), .attribute("year_min"), .attribute("exchange_possible"),
        ])

        let filters = state.filters
        XCTAssertNil(ListingsFilterRules.removing(.location, from: filters).wilayaId)
        XCTAssertNil(ListingsFilterRules.removing(.location, from: filters).communeId)
        XCTAssertTrue(ListingsFilterRules.removing(.subcategory, from: filters).attributes.isEmpty)
        XCTAssertEqual(ListingsFilterRules.removing(.price, from: filters).priceMax, "")
        XCTAssertNil(ListingsFilterRules.removing(.sort, from: filters).sort)
        XCTAssertEqual(
            ListingsFilterRules.removing(.attribute("make"), from: filters).attributes,
            ["exchange_possible": "true", "year_min": "2015"]
        )
        XCTAssertEqual(ListingsFilterRules.removing(.featured, from: filters).activeCount, filters.activeCount - 1)

        // Pertinence (choisie explicitement) : comptée comme filtre, sans puce (comme Android).
        var relevance = ListingsState()
        relevance.filters = ListingFilters(sort: "relevance")
        XCTAssertTrue(ListingsFilterRules.activeChips(for: relevance, language: "fr").isEmpty)
        XCTAssertEqual(relevance.filters.activeCount, 1)
    }

    func testFacetSectionsFollowTheAttributeOrderAndWaitForTheParentOfADependentSelect() {
        var state = ListingsState()
        state.attributeSet = AttributesResponseDTO(attributes: [
            AttributeDTO(
                key: "make",
                type: "select",
                filterable: true,
                options: ["renault", "volkswagen"],
                label: "Marque",
                optionLabels: ["renault": "Renault", "volkswagen": "Volkswagen"]
            ),
            AttributeDTO(key: "model", type: "select", filterable: true, dependsOn: "make", label: "Modèle"),
            AttributeDTO(key: "fuel", type: "select", filterable: true, options: ["diesel"], label: "Carburant", optionLabels: ["diesel": "Diesel"]),
        ]).toDomain()
        state.facets = [
            "zz_extra": [FacetValue(value: "x", count: 1)],
            "fuel": [FacetValue(value: "diesel", count: 5)],
            "model": [FacetValue(value: "clio-4", count: 2), FacetValue(value: "golf-7", count: 1)],
            "make": [FacetValue(value: "renault", count: 3), FacetValue(value: "volkswagen", count: 1)],
        ]

        // Sans marque choisie : pas de modèle ; ordre des attributs, puis les clés inconnues.
        let withoutParent = ListingsFilterRules.facetSections(state: state, attributes: [:])
        XCTAssertEqual(withoutParent.map(\.key), ["make", "fuel", "zz_extra"])
        XCTAssertEqual(withoutParent.first?.choices.map(\.label), ["Renault", "Volkswagen"])
        XCTAssertEqual(withoutParent.first.map { ListingsFilterRules.facetTitle($0.choices[0]) }, "Renault (\(Format.count(3)))")

        // Marque choisie : modèles comptés, libellés repliés tant que les options ne sont pas connues…
        let parentChosen = ListingsFilterRules.facetSections(state: state, attributes: ["make": "renault"])
        XCTAssertEqual(parentChosen.map(\.key), ["make", "model", "fuel", "zz_extra"])
        XCTAssertEqual(parentChosen[1].choices.map(\.label), ["Clio 4", "Golf 7"])

        // … puis réduits aux modèles de la marque.
        state.dependentOptions[ListingsState.dependentKey("model", parentValue: "renault")] = [
            AttributeOption(value: "clio-4", label: "Clio IV"),
        ]
        let withOptions = ListingsFilterRules.facetSections(state: state, attributes: ["make": "renault"])
        XCTAssertEqual(withOptions[1].choices.map(\.label), ["Clio IV"])

        // 12 valeurs au plus.
        state.facets["fuel"] = (1...20).map { FacetValue(value: "v\($0)", count: $0) }
        let capped = ListingsFilterRules.facetSections(state: state, attributes: [:])
        XCTAssertEqual(capped.first { $0.key == "fuel" }?.choices.count, ListingsFilterRules.maxFacetValues)
    }

    func testChoosingAnotherParentClearsItsDependentSelect() {
        let attributeSet = AttributesResponseDTO(attributes: [
            AttributeDTO(key: "make", type: "select", filterable: true, options: ["renault", "volkswagen"]),
            AttributeDTO(key: "model", type: "select", filterable: true, dependsOn: "make"),
        ]).toDomain()
        var filters = ListingFilters(attributes: ["make": "renault", "model": "clio-4"])
        filters = ListingsFilterRules.toggling(filters, key: "make", value: "volkswagen", attributeSet: attributeSet)
        XCTAssertEqual(filters.attributes, ["make": "volkswagen"])
        filters = ListingsFilterRules.toggling(filters, key: "model", value: "golf-7", attributeSet: attributeSet)
        XCTAssertEqual(filters.attributes, ["make": "volkswagen", "model": "golf-7"])
        filters = ListingsFilterRules.toggling(filters, key: "make", value: "volkswagen", attributeSet: attributeSet)
        XCTAssertEqual(filters.attributes, [:])

        XCTAssertEqual(ListingsFilterRules.settingAttribute(filters, key: "year_min", value: "2015").attributes, ["year_min": "2015"])
        let blank = ListingsFilterRules.settingAttribute(ListingFilters(attributes: ["year_min": "2015"]), key: "year_min", value: " ")
        XCTAssertEqual(blank.attributes, [:])
    }

    func testSearchParametersKeepFeaturedAndDropBlankAttributes() {
        var state = ListingsState()
        state.query = "  golf  "
        state.filters = ListingFilters(sort: "priceAsc", attributes: ["make": "volkswagen", "model": " "], featuredOnly: true)
        XCTAssertEqual(state.toSearchParams(), ["q": "golf", "attr_make": "volkswagen", "featured": "1"])
        XCTAssertNil(ListingsFilterRules.priceTitle(min: "", max: ""))
        XCTAssertEqual(ListingsFilterRules.priceTitle(min: "", max: "50000"), L10n.filtersPriceTo(Format.integer(50_000)))
        XCTAssertEqual(ListingsFilterRules.baseAttributeKey("mileage_max"), "mileage")
    }
}

/// Fausse API configurée comme le `setUp` d'Android (2 catégories, 2 wilayas, une commune par wilaya, l'attribut
/// « Marque », 2 pages de résultats, facette `make` sur demande) ; historique dans une suite UserDefaults jetable.
@MainActor
private final class ListingsTestEnvironment {
    let api: FakeWeydaAPI
    let search: SearchRepository
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        let api = FakeWeydaAPI()
        self.api = api
        let suiteName = "ListingsViewModelTests-\(UUID().uuidString)"
        self.suiteName = suiteName
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        self.defaults = defaults
        self.search = SearchRepository(api: api, history: SearchHistoryStore(defaults: defaults))

        api.onGetCategories = {
            [
                CategoryDTO(
                    id: "cat_veh",
                    slug: "vehicules",
                    nameFr: "Véhicules",
                    children: [CategoryDTO(id: "cat_voit", slug: "voitures", nameFr: "Voitures")]
                ),
                CategoryDTO(id: "cat_srv", slug: "services", nameFr: "Services"),
            ]
        }
        api.onGetWilayas = {
            [WilayaDTO(id: 16, nameFr: "Alger"), WilayaDTO(id: 31, nameFr: "Oran")]
        }
        api.onGetCommunes = { id in
            [CommuneDTO(id: id * 100 + 1, nameFr: "Commune \(id)", wilayaId: id)]
        }
        api.onGetAttributes = { _, _, _, _ in
            AttributesResponseDTO(attributes: [
                AttributeDTO(key: "make", type: "select", options: ["renault"], label: "Marque", optionLabels: ["renault": "Renault"]),
            ])
        }
        api.onGetSuggestions = { _, _ in
            SuggestionsDTO()
        }
        api.onGetAnnonces = { call in
            let facets: [String: [FacetValueDTO]]? = call.withFacets == 1 ? ["make": [FacetValueDTO(value: "renault", count: 42)]] : nil
            return AnnoncesPageDTO(
                annonces: [AnnonceDTO(id: "a\(call.page)", title: "T")],
                total: 30,
                page: call.page,
                totalPages: 2,
                facets: facets
            )
        }
    }

    var lastCall: FakeWeydaAPI.SearchCall? { api.searchCalls.last }

    func makeViewModel(online: AnyPublisher<Bool, Never>? = nil) -> ListingsViewModel {
        ListingsViewModel(
            annonces: AnnonceRepository(api: api),
            categories: CategoryRepository(api: api),
            geo: GeoRepository(api: api),
            attributes: AttributeRepository(api: api),
            search: search,
            favorites: FavoritesRepository(api: api),
            savedSearches: SavedSearchesRepository(api: api),
            online: online,
            locale: { "fr" },
            suggestionsDebounce: 0.01
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

#if DEBUG
/// Données simulées de la recherche (`MockFixtures/routes-search.json` + `search/`) lues par les VRAIS repositories à
/// travers `LiveWeydaAPI` et l'API simulée : JSON valides, routes les plus précises servies (celles du tour).
final class MockSearchFixturesTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testKeywordCategoryAndCorrectionFixtures() async throws {
        let api = try makeAPI()
        let annonces = AnnonceRepository(api: api)

        let clio = try await annonces.search(ListingQuery(q: "clio", sort: "relevance"))
        XCTAssertEqual(clio.items.map(\.id), ["mock-a2", "mock-a25", "mock-a26"])
        XCTAssertEqual(clio.total, 3)

        let vehicles = try await annonces.search(ListingQuery(category: "vehicules", sort: "newest", withFacets: true))
        XCTAssertEqual(vehicles.items.count, 7)
        XCTAssertEqual(vehicles.facets["make"]?.first, FacetValue(value: "renault", count: 3))
        XCTAssertEqual(vehicles.facets["fuel"]?.first, FacetValue(value: "diesel", count: 5))

        let oranCars = try await annonces.search(ListingQuery(category: "vehicules", subcategory: "voitures", wilaya: 31, withFacets: true))
        XCTAssertEqual(oranCars.items.map(\.id), ["mock-a2", "mock-a26"])

        let algiers = try await annonces.search(ListingQuery(wilaya: 16))
        XCTAssertTrue(algiers.items.allSatisfy { $0.wilayaId == 16 })

        let nothing = try await annonces.search(ListingQuery(q: "clyo", sort: "relevance"))
        XCTAssertTrue(nothing.items.isEmpty)
        let correction = try await annonces.didYouMean("clyo")
        XCTAssertEqual(correction, "clio")
        let none = try await annonces.didYouMean("zzz")
        XCTAssertNil(none)

        let next = try await annonces.search(ListingQuery(sort: "newest", page: 2))
        XCTAssertEqual(next.page, 2)
        XCTAssertFalse(next.hasMore)
        XCTAssertEqual(next.items.count, 6)
    }

    @MainActor
    func testSuggestionFixtures() async throws {
        let api = try makeAPI()
        let suggestions = try await api.getSuggestions(q: "cl", locale: "fr").suggestions.map { $0.toDomain() }
        XCTAssertEqual(suggestions.first?.type, .category)
        XCTAssertEqual(suggestions.first?.slug, "climatiseur")
        XCTAssertEqual(suggestions.filter { $0.type == .listing }.count, 4)
        let arabic = try await api.getSuggestions(q: "cl", locale: "ar").suggestions
        XCTAssertEqual(arabic.first?.text, "مكيف / تدفئة")
        let unknown = try await api.getSuggestions(q: "xy", locale: "fr").suggestions
        XCTAssertTrue(unknown.isEmpty)
    }
}
#endif
