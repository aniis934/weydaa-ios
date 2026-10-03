import Foundation
import XCTest
@testable import Weyda

/// Passage contre la VRAIE API (`AppConfig.current.apiBaseURL`, weydaa.com), en LECTURE SEULE : GET publics
/// seulement, peu nombreux (≈ 16 requêtes, sous les limites de débit). Sauté sauf si `WEYDA_LIVE_API=1` (ios-ci
/// lancé à la main avec live=true). Chaque réponse est décodée par `LiveWeydaAPI` puis convertie en modèle, et des
/// invariants sont vérifiés. Rien n'est écrit ; les journaux ne contiennent que des COMPTEURS (aucun nom, titre ni
/// téléphone : les assertions qui pourraient en afficher un comparent sans montrer la valeur).
final class LiveAPITests: XCTestCase {
    private func liveAPI() throws -> LiveWeydaAPI {
        guard ProcessInfo.processInfo.environment["WEYDA_LIVE_API"] == "1" else {
            throw XCTSkip("API réelle : WEYDA_LIVE_API=1 requis (ios-ci lancé à la main avec live=true)")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        let client = APIClient(baseURL: AppConfig.current.apiBaseURL, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    private func page(
        _ api: LiveWeydaAPI,
        category: String? = nil,
        featured: Int? = nil,
        withFacets: Int? = nil
    ) async throws -> ListingPage {
        try await api.getAnnonces(
            q: nil,
            category: category,
            subcategory: nil,
            wilaya: nil,
            commune: nil,
            priceType: nil,
            priceMin: nil,
            priceMax: nil,
            sort: "newest",
            featured: featured,
            page: 1,
            limit: 12,
            locale: nil,
            withFacets: withFacets,
            attrs: [:]
        ).toDomain()
    }

    func testCatalogCategoriesWilayasRankingAndAttributes() async throws {
        let api = try liveAPI()
        let categories = try await api.getCategories().map { $0.toDomain() }
        XCTAssertGreaterThanOrEqual(categories.count, 10)
        XCTAssertTrue(categories.allSatisfy { !$0.id.isEmpty && !$0.slug.isEmpty && !$0.name.fr.isEmpty })
        XCTAssertTrue(categories.contains { $0.slug == "vehicules" })
        XCTAssertTrue(categories.allSatisfy { $0.listingsCount >= 0 })

        let wilayas = try await api.getWilayas().map { $0.toDomain() }
        XCTAssertEqual(wilayas.count, 58)
        XCTAssertEqual(Set(wilayas.map { $0.id }).count, 58)

        let ranking = try await api.getTopWilayas(top: 10).map { $0.toDomain() }
        XCTAssertLessThanOrEqual(ranking.count, 10)
        XCTAssertTrue(ranking.allSatisfy { $0.listingsCount > 0 })
        let counts = ranking.map { $0.listingsCount }
        XCTAssertEqual(counts, counts.sorted(by: >))

        let attributes = try await api.getAttributes(slug: "vehicules", subcategory: nil, locale: "fr", context: [:]).toDomain()
        XCTAssertFalse(attributes.attributes.isEmpty)
        XCTAssertFalse(attributes.subcategories.isEmpty)
        let make = try XCTUnwrap(attributes.attribute("make"))
        XCTAssertFalse(make.options.isEmpty)
        XCTAssertTrue(make.options.allSatisfy { !$0.label.isEmpty })
        let withMake = try await api.getAttributes(slug: "vehicules", subcategory: nil, locale: "fr", context: ["ctx_make": "renault"]).toDomain()
        let model = try XCTUnwrap(withMake.attribute("model"))
        XCTAssertFalse(model.options.isEmpty)

        print("API réelle — catalogue : \(categories.count) catégories, \(wilayas.count) wilayas, \(ranking.count) villes classées, \(attributes.attributes.count) attributs, \(model.options.count) modèles")
    }

    func testListingsDetailSellerShowcaseAndReviews() async throws {
        let api = try liveAPI()
        let latest = try await page(api)
        XCTAssertFalse(latest.items.isEmpty)
        XCTAssertGreaterThanOrEqual(latest.total, latest.items.count)
        for listing in latest.items {
            XCTAssertFalse(listing.id.isEmpty)
            XCTAssertFalse(listing.title.isEmpty)
            XCTAssertGreaterThanOrEqual(listing.price ?? 0, 0)
            XCTAssertEqual(listing.listingStatus, ListingStatus.active)
            XCTAssertTrue(listing.phone == nil, "numéro exposé dans la liste publique")
        }

        let featured = try await page(api, featured: 1)
        XCTAssertTrue(featured.items.allSatisfy { $0.isFeatured })
        let vehicles = try await page(api, category: "vehicules", withFacets: 1)
        XCTAssertTrue(vehicles.items.allSatisfy { $0.listingStatus == .active })

        let first = try XCTUnwrap(latest.items.first)
        let byId = try await api.getAnnonce(idOrSlug: first.id).toDomain()
        XCTAssertEqual(byId.id, first.id)
        XCTAssertTrue(byId.images.allSatisfy { $0.hasPrefix("https://") })
        if let slug = byId.slug {
            let bySlug = try await api.getAnnonce(idOrSlug: slug).toDomain()
            XCTAssertEqual(bySlug.id, first.id)
        }

        let seller = try XCTUnwrap(byId.seller)
        XCTAssertFalse(seller.id.isEmpty)
        let profile = try await api.publicProfile(id: seller.id).toDomain()
        XCTAssertEqual(profile.id, seller.id)
        XCTAssertGreaterThanOrEqual(profile.activeListings, 1)
        let showcase = try await api.publicAnnonces(id: seller.id, page: 1, limit: 12).toDomain()
        XCTAssertFalse(showcase.items.isEmpty)
        XCTAssertTrue(showcase.items.allSatisfy { $0.listingStatus == .active && $0.phone == nil })
        let reviews = try await api.getReviews(targetId: seller.id, page: 1, limit: 5).toDomain()
        XCTAssertTrue(reviews.reviews.allSatisfy { (0...5).contains($0.rating) })
        XCTAssertGreaterThanOrEqual(reviews.average, 0)
        XCTAssertLessThanOrEqual(reviews.average, 5)

        print("API réelle — annonces : \(latest.items.count) / \(latest.total), à la une : \(featured.items.count), véhicules : \(vehicles.items.count) (\(vehicles.facets.count) facettes), vitrine : \(showcase.items.count), avis : \(reviews.total)")
    }

    func testSuggestionsDidYouMeanAndTrending() async throws {
        let api = try liveAPI()
        let suggestions = try await api.getSuggestions(q: "clio", locale: "fr").suggestions.map { $0.toDomain() }
        XCTAssertLessThanOrEqual(suggestions.count, 8)
        XCTAssertTrue(suggestions.allSatisfy { !$0.text.isEmpty })

        let correction = try await api.didYouMean(q: "peugot")
        let trending = try await api.getTrending(limit: 12).annonces.map { $0.toDomain() }
        XCTAssertLessThanOrEqual(trending.count, 12)
        XCTAssertTrue(trending.allSatisfy { !$0.id.isEmpty && $0.phone == nil })

        print("API réelle — suggestions : \(suggestions.count), tendances : \(trending.count), correction proposée : \(correction.suggestion != nil)")
    }
}
