import Foundation
import XCTest
@testable import Weyda

/// Portage de CatalogRepositoriesTest.kt et CategoriesFilterTest.kt (Android), plus les catégories racines et
/// les annonces (paramètres de recherche, similaires, « vouliez-vous dire », édition). Données fictives.
final class CatalogRepositoriesTests: XCTestCase {
    // MARK: - Attributs

    @MainActor
    func testAttributesSendSubcategoryLocaleAndContextThenServeTheCache() async throws {
        let api = FakeWeydaAPI()
        let repository = AttributeRepository(api: api)
        api.onGetAttributes = { slug, subcategory, locale, context in
            XCTAssertEqual(slug, "vehicules")
            XCTAssertEqual(subcategory, "voitures")
            XCTAssertEqual(locale, "ar")
            XCTAssertEqual(context, ["ctx_make": "renault"])
            return AttributesResponseDTO(attributes: [
                AttributeDTO(key: "model", type: "select", options: ["clio", "megane"], dependsOn: "make"),
            ])
        }
        let first = try await repository.attributes(
            categorySlug: "vehicules",
            subcategory: "voitures",
            locale: "ar",
            context: ["make": "renault", "year": ""]
        )
        XCTAssertEqual(first.attribute("model")?.options.map { $0.value }, ["clio", "megane"])

        let second = try await repository.attributes(
            categorySlug: "vehicules",
            subcategory: "voitures",
            locale: "ar",
            context: ["make": "renault"]
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(api.count("getAttributes"), 1)

        // Contexte différent = autre entrée.
        api.onGetAttributes = { _, _, _, _ in AttributesResponseDTO() }
        _ = try await repository.attributes(categorySlug: "vehicules", subcategory: "voitures", locale: "ar", context: ["make": "peugeot"])
        XCTAssertEqual(api.count("getAttributes"), 2)
    }

    @MainActor
    func testDependentOptionsReturnTheDependentSelectOrEmpty() async throws {
        let api = FakeWeydaAPI()
        let repository = AttributeRepository(api: api)
        api.onGetAttributes = { _, _, _, context in
            guard context["ctx_brand"] == "apple" else { return AttributesResponseDTO() }
            return AttributesResponseDTO(attributes: [
                AttributeDTO(key: "model", type: "select", options: ["iphone-15"], optionLabels: ["iphone-15": "iPhone 15"]),
            ])
        }
        let options = try await repository.dependentOptions(
            categorySlug: "electronique",
            subcategory: "smartphones",
            key: "model",
            context: ["brand": "apple"]
        )
        XCTAssertEqual(options.map { $0.label }, ["iPhone 15"])
        let none = try await repository.dependentOptions(
            categorySlug: "electronique",
            subcategory: "smartphones",
            key: "model",
            context: ["brand": "nokia"]
        )
        XCTAssertTrue(none.isEmpty)
    }

    @MainActor
    func testAnAttributesErrorIsNotCached() async throws {
        let api = FakeWeydaAPI()
        let repository = AttributeRepository(api: api)
        let attempts = FakeWeydaAPI.Box(0)
        api.onGetAttributes = { _, _, _, _ in
            attempts.value += 1
            if attempts.value == 1 { throw URLError(.notConnectedToInternet) }
            return AttributesResponseDTO()
        }
        do {
            _ = try await repository.attributes(categorySlug: "immobilier")
            XCTFail("échec réseau attendu")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
        let set = try await repository.attributes(categorySlug: "immobilier")
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(attempts.value, 2)
    }

    // MARK: - Géographie

    @MainActor
    func testGeoCachesWilayasAndCommunesPerWilayaAndPropagatesServerErrors() async throws {
        let api = FakeWeydaAPI()
        let geo = GeoRepository(api: api)
        api.onGetWilayas = {
            [WilayaDTO(id: 16, nameFr: "Alger", nameAr: "الجزائر"), WilayaDTO(id: 31, nameFr: "Oran", nameAr: "وهران")]
        }
        api.onGetCommunes = { id in
            guard id == 16 else { throw FakeWeydaAPI.apiError(400, #"{"error":"invalidWilayaId"}"#) }
            return [CommuneDTO(id: 1601, nameFr: "Bab Ezzouar", wilayaId: 16)]
        }

        let wilayas = try await geo.wilayas()
        XCTAssertEqual(wilayas.map { $0.id }, [16, 31])
        _ = try await geo.wilayas()
        XCTAssertEqual(api.count("getWilayas"), 1)

        let communes = try await geo.communes(wilayaId: 16)
        XCTAssertEqual(communes.first?.name.resolve("fr"), "Bab Ezzouar")
        _ = try await geo.communes(wilayaId: 16)
        XCTAssertEqual(api.count("getCommunes"), 1)

        do {
            _ = try await geo.communes(wilayaId: 999)
            XCTFail("400 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "invalidWilayaId")
        }
        do {
            _ = try await geo.communes(wilayaId: 999)
            XCTFail("une erreur n'est pas gardée en cache")
        } catch is APIError {}
        XCTAssertEqual(api.count("getCommunes"), 3)
    }

    @MainActor
    func testTopWilayasServedThenCached() async throws {
        let api = FakeWeydaAPI()
        let geo = GeoRepository(api: api)
        api.onGetTopWilayas = { top in
            XCTAssertEqual(top, 3)
            return [
                WilayaDTO(id: 31, nameFr: "Oran", nameAr: "وهران", listingsCount: 42),
                WilayaDTO(id: 16, nameFr: "Alger", nameAr: "الجزائر", listingsCount: 40),
            ]
        }
        let first = try await geo.topWilayas(limit: 3)
        XCTAssertEqual(first.map { $0.id }, [31, 16])
        XCTAssertEqual(first.first?.listingsCount, 42)
        _ = try await geo.topWilayas(limit: 3)
        XCTAssertEqual(api.count("getTopWilayas"), 1)
    }

    @MainActor
    func testTopWilayasFromAServerIgnoringTopFail() async throws {
        let api = FakeWeydaAPI()
        let geo = GeoRepository(api: api)
        api.onGetTopWilayas = { _ in (1...58).map { WilayaDTO(id: $0, nameFr: "W\($0)") } }
        do {
            _ = try await geo.topWilayas(limit: 10)
            XCTFail("58 wilayas sans compte : pas un classement")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .rankingUnsupported)
        }
        api.onGetTopWilayas = { _ in [WilayaDTO(id: 1, nameFr: "Adrar")] }
        do {
            _ = try await geo.topWilayas(limit: 10)
            XCTFail("sans listingsCount, ce n'est pas un classement")
        } catch is RepositoryError {}
    }

    // MARK: - Catégories

    @MainActor
    func testCategoryRootsAreFilteredOrderedAndCached() async throws {
        let api = FakeWeydaAPI()
        let repository = CategoryRepository(api: api)
        api.onGetCategories = {
            [
                CategoryDTO(id: "c2", slug: "immobilier", nameFr: "Immobilier", displayOrder: 2),
                CategoryDTO(id: "c9", slug: "ancienne", nameFr: "Ancienne", displayOrder: 0, isActive: false),
                CategoryDTO(id: "c1", slug: "vehicules", nameFr: "Véhicules", displayOrder: 1),
            ]
        }
        let roots = try await repository.roots()
        XCTAssertEqual(roots.map { $0.slug }, ["vehicules", "immobilier"])
        _ = try await repository.roots()
        XCTAssertEqual(api.count("getCategories"), 1)
        _ = try await repository.roots(forceRefresh: true)
        XCTAssertEqual(api.count("getCategories"), 2)
    }

    /// Filtre de la feuille « Catégories » de l'accueil (CategoriesFilterTest.kt).
    private func category(_ slug: String, _ fr: String, _ ar: String, _ en: String) -> Weyda.Category {
        Weyda.Category(id: slug, slug: slug, name: LocalizedName(fr: fr, ar: ar, en: en), icon: nil, color: nil, listingsCount: 0, children: [])
    }

    private var sampleCategories: [Weyda.Category] {
        [
            category("electronique", "Électronique", "الإلكترونيات", "Electronics"),
            category("electromenager", "Électroménager", "الأجهزة المنزلية", "Home Appliances"),
            category("vehicules", "Véhicules", "المركبات", "Vehicles"),
        ]
    }

    func testCategoryFilterEmptyOrBlankReturnsAllInOrder() {
        XCTAssertEqual(CategoryFilter.filter(sampleCategories, query: ""), sampleCategories)
        XCTAssertEqual(CategoryFilter.filter(sampleCategories, query: "   "), sampleCategories)
    }

    func testCategoryFilterIgnoresAccentsAndCaseOnFrench() {
        XCTAssertEqual(CategoryFilter.filter(sampleCategories, query: "ELECTRO").map { $0.slug }, ["electronique", "electromenager"])
        XCTAssertEqual(CategoryFilter.filter(sampleCategories, query: "véhi").map { $0.slug }, ["vehicules"])
    }

    func testCategoryFilterAlsoSearchesArabicAndEnglishNames() {
        XCTAssertEqual(CategoryFilter.filter(sampleCategories, query: "المرك").map { $0.slug }, ["vehicules"])
        XCTAssertEqual(CategoryFilter.filter(sampleCategories, query: "appliance").map { $0.slug }, ["electromenager"])
        XCTAssertTrue(CategoryFilter.filter(sampleCategories, query: "xyz").isEmpty)
    }

    // MARK: - Annonces

    @MainActor
    func testSearchSendsCleanParameters() async throws {
        let api = FakeWeydaAPI()
        let repository = AnnonceRepository(api: api)
        api.onGetAnnonces = { _ in AnnoncesPageDTO() }
        let query = ListingQuery(
            q: "   ",
            category: "vehicules",
            wilaya: 16,
            priceType: .negotiable,
            priceMin: 1000,
            sort: "priceAsc",
            featured: true,
            page: 2,
            limit: 500,
            attributes: ["make": "renault", "fuel": " "],
            withFacets: true
        )
        _ = try await repository.search(query)
        let call = try XCTUnwrap(api.searchCalls.last)
        XCTAssertNil(call.q)
        XCTAssertEqual(call.category, "vehicules")
        XCTAssertEqual(call.wilaya, 16)
        XCTAssertEqual(call.priceType, "NEGOTIABLE")
        XCTAssertEqual(call.priceMin, 1000)
        XCTAssertEqual(call.sort, "priceAsc")
        XCTAssertEqual(call.featured, 1)
        XCTAssertEqual(call.page, 2)
        XCTAssertEqual(call.limit, 48)
        XCTAssertEqual(call.withFacets, 1)
        XCTAssertEqual(call.attrs, ["attr_make": "renault"])
        XCTAssertNil(call.locale)

        _ = try await repository.recent(limit: 0)
        let recent = try XCTUnwrap(api.searchCalls.last)
        XCTAssertNil(recent.featured)
        XCTAssertNil(recent.withFacets)
        XCTAssertEqual(recent.limit, 1)
        XCTAssertEqual(recent.sort, "newest")

        _ = try await repository.featured()
        let featured = try XCTUnwrap(api.searchCalls.last)
        XCTAssertEqual(featured.featured, 1)
        XCTAssertEqual(featured.limit, 8)
    }

    @MainActor
    func testSimilarExcludesTheListingItselfAndNeedsACategory() async throws {
        let api = FakeWeydaAPI()
        let repository = AnnonceRepository(api: api)
        api.onGetAnnonces = { call in
            XCTAssertEqual(call.category, "vehicules")
            XCTAssertEqual(call.limit, 3)
            return AnnoncesPageDTO(annonces: [
                AnnonceDTO(id: "a1", title: "A"),
                AnnonceDTO(id: "a2", title: "B"),
                AnnonceDTO(id: "a3", title: "C"),
            ])
        }
        var listing = AnnonceDTO(id: "a2", title: "B").toDomain()
        listing.categorySlug = "vehicules"
        let similar = try await repository.similar(to: listing, limit: 2)
        XCTAssertEqual(similar.map { $0.id }, ["a1", "a3"])

        listing.categorySlug = nil
        let none = try await repository.similar(to: listing)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(api.count("getAnnonces"), 1)
    }

    @MainActor
    func testDidYouMeanIgnoresBlankAndRepeatedSuggestions() async throws {
        let api = FakeWeydaAPI()
        let repository = AnnonceRepository(api: api)
        api.onDidYouMean = { q in
            switch q {
            case "clio": return DidYouMeanDTO(suggestion: "CLIO")
            case "peugot": return DidYouMeanDTO(suggestion: "peugeot")
            default: return DidYouMeanDTO(suggestion: "  ")
            }
        }
        let repeated = try await repository.didYouMean("  clio ")
        XCTAssertNil(repeated)
        let fixed = try await repository.didYouMean("peugot")
        XCTAssertEqual(fixed, "peugeot")
        let blank = try await repository.didYouMean("xyz")
        XCTAssertNil(blank)
    }

    @MainActor
    func testEditSendsExplicitNullsThenSoldAndRenew() async throws {
        let api = FakeWeydaAPI()
        let repository = AnnonceRepository(api: api)
        api.onEditAnnonce = { id, body in
            XCTAssertEqual(id, "a1")
            XCTAssertEqual(body["price"], JSONValue.null)
            XCTAssertEqual(body["wilayaId"], JSONValue.null)
            XCTAssertEqual(body["attributes"], JSONValue.object([:]))
            XCTAssertEqual(body["phone"], JSONValue.string(""))
            return AnnonceDTO(id: id, title: "Canapé à donner")
        }
        let submission = ListingSubmission(
            title: "Canapé à donner",
            description: String(repeating: "d", count: 30),
            price: nil,
            priceType: .free,
            categoryId: "cat_maison"
        )
        let updated = try await repository.update(id: "a1", submission)
        XCTAssertEqual(updated.id, "a1")

        api.onUpdateAnnonce = { id, body in
            XCTAssertEqual(body.status, "SOLD")
            return AnnonceDTO(id: id, title: "T", status: "SOLD")
        }
        let sold = try await repository.markSold(id: "a1")
        XCTAssertEqual(sold.listingStatus, ListingStatus.sold)

        api.onPatchAnnonce = { _, body in
            XCTAssertEqual(body.action, "renew")
            return RenewResponseDTO(renewalsRemaining: 2)
        }
        let left = try await repository.renew(id: "a1")
        XCTAssertEqual(left, 2)

        // Vue comptée : silencieuse même en échec.
        api.onCountView = { _ in throw URLError(.timedOut) }
        await repository.countView(id: "a1")
        XCTAssertEqual(api.count("countView"), 1)
    }
}
