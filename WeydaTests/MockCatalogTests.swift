#if DEBUG
import Foundation
import XCTest
@testable import Weyda

/// Données simulées du catalogue (`MockFixtures/routes-catalog.json` + `catalog/`) lues par les VRAIS repositories
/// à travers `LiveWeydaAPI` et l'API simulée : JSON valides, routes les plus précises servies (top, communes,
/// contexte `ctx_make`), repli vide pour une catégorie sans fichier.
final class MockCatalogTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testCategoriesWilayasRankingAndCommunes() async throws {
        let api = try makeAPI()
        let categories = try await CategoryRepository(api: api).roots()
        XCTAssertEqual(categories.count, 14)
        XCTAssertEqual(categories.first?.slug, "vehicules")
        XCTAssertEqual(categories.last?.slug, "autres")
        XCTAssertEqual(categories.first?.children.count, 6)
        XCTAssertTrue(categories.allSatisfy { $0.listingsCount > 0 && !$0.name.ar.isEmpty && !$0.name.en.isEmpty })
        // Chaque catégorie racine a son icône Lucide (seule « autres » prend le carton).
        XCTAssertTrue(categories.allSatisfy { $0.slug == "autres" || CategoryIcon.assetName(forSlug: $0.slug) != "ic_cat_autres" })

        let geo = GeoRepository(api: api)
        let wilayas = try await geo.wilayas()
        XCTAssertEqual(wilayas.count, 58)
        let ranking = try await geo.topWilayas(limit: 10)
        XCTAssertEqual(ranking.count, 10)
        XCTAssertEqual(ranking.first?.id, 16)
        let algiers = try await geo.communes(wilayaId: 16)
        XCTAssertEqual(algiers.count, 57)
        XCTAssertTrue(algiers.allSatisfy { $0.wilayaId == 16 })
        let oran = try await geo.communes(wilayaId: 31)
        XCTAssertFalse(oran.isEmpty)
    }

    @MainActor
    func testAttributesDependentModelsAndEmptyFallback() async throws {
        let api = try makeAPI()
        let repository = AttributeRepository(api: api)
        let vehicles = try await repository.attributes(categorySlug: "vehicules", locale: "fr")
        let make = try XCTUnwrap(vehicles.attribute("make"))
        XCTAssertTrue(make.isRequired)
        XCTAssertEqual(make.optionLabel("renault"), "Renault")
        XCTAssertEqual(vehicles.attribute("mileage")?.unitLabel, "km")
        XCTAssertEqual(vehicles.subcategories.count, 6)

        let models = try await repository.dependentOptions(
            categorySlug: "vehicules",
            subcategory: nil,
            key: "model",
            context: ["make": "renault"],
            locale: "fr"
        )
        XCTAssertFalse(models.isEmpty)

        let realEstate = try await repository.attributes(categorySlug: "immobilier", locale: "fr")
        XCTAssertFalse(realEstate.attributes.isEmpty)
        let electronics = try await repository.attributes(categorySlug: "electronique", locale: "fr")
        XCTAssertNotNil(electronics.attribute("brand"))
        let jobs = try await repository.attributes(categorySlug: "emploi", locale: "fr")
        XCTAssertTrue(jobs.isEmpty)
    }
}
#endif
