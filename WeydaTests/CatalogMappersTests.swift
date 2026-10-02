import Foundation
import XCTest
@testable import Weyda

/// Portage de CatalogMappersTest.kt (Android) : forme réelle de GET /api/categories/{slug}/attributes.
final class CatalogMappersTests: XCTestCase {
    private static let payload = """
    {"attributes":[
      {"key":"make","type":"select","requirement":"required","filterable":true,"filterType":"exact",
       "options":["renault","peugeot","mercedes-benz"],"showFor":["voitures"],
       "label":"Marque","optionLabels":{"renault":"Renault","peugeot":"Peugeot"}},
      {"key":"model","type":"select","requirement":"recommended","filterable":true,"filterType":"exact",
       "options":[],"dependsOn":"make","label":"Modèle","optionLabels":{}},
      {"key":"mileage","type":"number","requirement":"recommended","filterable":true,"filterType":"range",
       "options":[],"min":0,"max":999999,"step":1000,"unit":"km","rangePresets":[50000,100000],
       "label":"Kilométrage","optionLabels":{},"unitLabel":"km"},
      {"key":"new_field","type":"rocket","requirement":"mandatory","options":[],"futureFlag":true}
    ],
    "subcategories":[{"slug":"voitures","parentSlug":"vehicules","nameFr":"Voitures","nameAr":"سيارات","nameEn":"Cars"}]}
    """

    private func decodeSet(_ json: String) throws -> AttributeSet {
        try JSONDecoder().decode(AttributesResponseDTO.self, from: Data(json.utf8)).toDomain()
    }

    func testAttributesTypesRequirementOptionLabelsBoundsAndUnit() throws {
        let set = try decodeSet(Self.payload)
        XCTAssertEqual(set.attributes.count, 4)

        let make = try XCTUnwrap(set.attribute("make"))
        XCTAssertEqual(make.type, AttributeType.select)
        XCTAssertEqual(make.requirement, Requirement.required)
        XCTAssertTrue(make.isRequired)
        XCTAssertEqual(make.label, "Marque")
        XCTAssertEqual(make.optionLabel("renault"), "Renault")
        // Option sans libellé serveur → capitalisation comme le web.
        XCTAssertEqual(make.optionLabel("mercedes-benz"), "Mercedes Benz")
        XCTAssertEqual(make.optionLabel("inconnu"), "Inconnu")
        XCTAssertEqual(make.optionLabel("classe-a"), "Classe A")

        let model = try XCTUnwrap(set.attribute("model"))
        XCTAssertTrue(model.isDependent)
        XCTAssertEqual(model.dependsOn, "make")
        XCTAssertTrue(model.options.isEmpty)

        let mileage = try XCTUnwrap(set.attribute("mileage"))
        XCTAssertEqual(mileage.type, AttributeType.number)
        XCTAssertEqual(mileage.min, 0)
        XCTAssertEqual(mileage.max, 999_999)
        XCTAssertEqual(mileage.step, 1000)
        XCTAssertEqual(mileage.unitLabel, "km")
        XCTAssertEqual(mileage.rangePresets, [50_000, 100_000])
        XCTAssertFalse(mileage.isRequired)
    }

    func testUnknownValuesFallBackToTextOptionalAndKeyLabel() throws {
        let set = try decodeSet(Self.payload)
        let unknown = try XCTUnwrap(set.attribute("new_field"))
        XCTAssertEqual(unknown.type, AttributeType.text)
        XCTAssertEqual(unknown.requirement, Requirement.optional)
        XCTAssertEqual(unknown.label, "New_field")
        XCTAssertNil(unknown.unitLabel)
    }

    func testSubcategoriesAndCategoryWithoutAttributes() throws {
        let set = try decodeSet(Self.payload)
        XCTAssertEqual(set.subcategories.count, 1)
        let sub = try XCTUnwrap(set.subcategories.first)
        XCTAssertEqual(sub.slug, "voitures")
        XCTAssertEqual(sub.parentSlug, "vehicules")
        XCTAssertEqual(sub.name.resolve("en"), "Cars")
        XCTAssertEqual(sub.name.resolve("ar"), "سيارات")

        let empty = try decodeSet(#"{"attributes":[],"subcategories":[]}"#)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.attribute("make"))
    }

    func testWilayaAndCommune() {
        let wilaya = WilayaDTO(id: 16, nameFr: "Alger", nameAr: "الجزائر").toDomain()
        XCTAssertEqual(wilaya.id, 16)
        XCTAssertEqual(wilaya.name.resolve("ar"), "الجزائر")
        XCTAssertEqual(wilaya.name.resolve("en"), "Alger")

        let commune = CommuneDTO(id: 1601, nameFr: "Bab Ezzouar", nameAr: "باب الزوار", wilayaId: 16).toDomain()
        XCTAssertEqual(commune.wilayaId, 16)
        XCTAssertEqual(commune.name.resolve("fr"), "Bab Ezzouar")
    }
}
