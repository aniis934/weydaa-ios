import Foundation
import XCTest
@testable import Weyda

/// Portage de MappersTest.kt (Android) : mêmes cas, mêmes attentes.
final class MappersTests: XCTestCase {
    func testUnknownPriceTypeFallsBackToFixed() {
        XCTAssertEqual(PriceType.from("???"), PriceType.fixed)
        XCTAssertEqual(PriceType.from("FREE"), PriceType.free)
        XCTAssertEqual(PriceType.from("NEGOTIABLE"), PriceType.negotiable)
    }

    func testUpdateBodyWritesExplicitNullsToClearPriceLocationAndAttributes() throws {
        // Annonce passée en « gratuit », localisation retirée, catégorie changée : le serveur ne touche
        // qu'aux champs PRÉSENTS, un champ omis garderait donc son ancienne valeur en base.
        let submission = ListingSubmission(
            title: "Canapé à donner",
            description: String(repeating: "d", count: 30),
            price: nil,
            priceType: .free,
            categoryId: "cat_maison"
        )
        let body = try submission.toUpdateBody()
        let wire = try XCTUnwrap(String(data: body, encoding: .utf8))
        let fragments = [
            #""price":null"#,
            #""wilayaId":null"#,
            #""communeId":null"#,
            #""attributes":{}"#,
            #""phone":"""#,
            #""images":[]"#,
        ]
        for fragment in fragments {
            XCTAssertTrue(wire.contains(fragment), "\(fragment) absent de \(wire)")
        }
    }

    func testImagesAreSortedByOrder() {
        let dto = AnnonceDTO(
            id: "a",
            title: "t",
            images: [ImageDTO(url: "b", order: 1), ImageDTO(url: "a", order: 0)]
        )
        XCTAssertEqual(dto.toDomain().images, ["a", "b"])
    }

    func testAPIResponseWithUnknownFieldsIsDecoded() throws {
        let payload = """
        {"annonces":[{"id":"x","title":"T","price":1200.5,"priceType":"NEGOTIABLE","extra":1,
         "images":[{"id":"i","url":"https://x/y.webp","publicId":"annonces/y.webp","order":0}],
         "category":{"slug":"vehicules","nameFr":"Véhicules","nameAr":"سيارات","nameEn":"Vehicles"},
         "wilaya":{"id":16,"nameFr":"Alger","nameAr":"الجزائر"},
         "createdAt":"2026-09-07T12:12:43.698Z"}],
         "total":1,"page":1,"totalPages":1}
        """
        let page = try JSONDecoder().decode(AnnoncesPageDTO.self, from: Data(payload.utf8)).toDomain()
        XCTAssertEqual(page.items.count, 1)
        let listing = try XCTUnwrap(page.items.first)
        XCTAssertEqual(listing.price, 1200.5)
        XCTAssertEqual(listing.priceType, PriceType.negotiable)
        XCTAssertEqual(listing.wilaya?.resolve("fr"), "Alger")
        XCTAssertEqual(listing.wilaya?.resolve("ar"), "الجزائر")
        XCTAssertEqual(listing.category?.resolve("en"), "Vehicles")
        XCTAssertNotNil(listing.createdAt)
        // Sans slug : la page /annonce/{id} du site (qui redirige vers l'URL SEO), jamais /{catégorie}/{id}.
        XCTAssertEqual(listing.webUrl(host: "https://weydaa.com/"), "https://weydaa.com/fr/annonce/x")
        var withSlug = listing
        withSlug.slug = "clio-4-ab12"
        XCTAssertEqual(
            withSlug.webUrl(host: "https://weydaa.com/", locale: "ar"),
            "https://weydaa.com/ar/vehicules/clio-4-ab12"
        )
        withSlug.categorySlug = nil
        XCTAssertEqual(withSlug.webUrl(host: "https://weydaa.com"), "https://weydaa.com/fr/annonce/x")
    }
}
