import Foundation
import XCTest
@testable import Weyda

/// Brouillon du dépôt : format `PostDraft` (lecture tolérante, aller-retour), stockage sur disque (dossier créé à la
/// demande, exclu des sauvegardes, écriture atomique, effacement) et en mémoire. Brouillons simulés du tour lisibles.
final class PostDraftStoreTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PostDraftStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Format

    func testUnBrouillonMinimalPrendLesValeursParDefautDAndroid() throws {
        let draft = try JSONDecoder().decode(PostDraft.self, from: Data(#"{"title":"x"}"#.utf8))
        XCTAssertEqual(draft.title, "x")
        XCTAssertNil(draft.ownerId)
        XCTAssertFalse(draft.dirty)
        XCTAssertEqual(draft.priceType, "FIXED")
        XCTAssertEqual(draft.step, "CATEGORY")
        XCTAssertEqual(draft.price, "")
        XCTAssertTrue(draft.attributeValues.isEmpty)
        XCTAssertTrue(draft.photos.isEmpty)
        XCTAssertFalse(draft.showPhone)
    }

    func testLectureTolerantePourUnBrouillonAncienOuAbime() throws {
        let raw = """
        {
          "ownerId": "user_1", "dirty": "true", "wilayaId": "16", "communeId": 1601.0, "price": 2500,
          "attributeValues": { "make": "renault", "year": 2018, "broken": null },
          "unknownField": [1, 2, 3],
          "photos": [
            { "localRef": "abc", "url": "https://cdn/1.webp", "publicId": "annonces/1.webp" },
            { "localUri": "content://p/2" },
            { "url": "https://cdn/sans-reference.webp" }
          ]
        }
        """
        let draft = try JSONDecoder().decode(PostDraft.self, from: Data(raw.utf8))
        XCTAssertEqual(draft.ownerId, "user_1")
        XCTAssertTrue(draft.dirty)
        XCTAssertEqual(draft.wilayaId, 16)
        XCTAssertEqual(draft.communeId, 1601)
        XCTAssertEqual(draft.price, "2500")
        XCTAssertEqual(draft.attributeValues, ["make": "renault", "year": "2018"])
        // Photo sans référence ignorée ; `localUri` d'Android accepté.
        XCTAssertEqual(draft.photos.map { $0.localRef }, ["abc", "content://p/2"])
        XCTAssertEqual(draft.photos.first?.publicId, "annonces/1.webp")
        XCTAssertNil(draft.photos.first?.thumbnailUrl)
    }

    func testAllerRetourSansPerte() throws {
        let draft = PostDraft(
            ownerId: "user_1",
            listingPhone: "021123456",
            dirty: true,
            parentCategoryId: "cat_veh",
            subcategoryId: "cat_voit",
            attributeValues: ["make": "renault"],
            title: "Renault Clio 4 2018",
            description: "Très bon état général.",
            priceType: "NEGOTIABLE",
            price: "1950000",
            wilayaId: 16,
            communeId: 1601,
            showPhone: true,
            step: "PHOTOS",
            photos: [
                PostDraft.Photo(localRef: "abc"),
                PostDraft.Photo(localRef: "def", url: "https://cdn/1.webp", thumbnailUrl: "https://cdn/1_thumb.webp", publicId: "annonces/1.webp"),
            ]
        )
        let data = try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(PostDraft.self, from: data), draft)
    }

    // MARK: - Disque

    func testFichierCreeALaDemandeExcluDesSauvegardesReecritPuisEfface() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("PostDrafts", isDirectory: true).appendingPathComponent("post_draft.json")
        let store = FilePostDraftStore(fileURL: fileURL)
        XCTAssertNil(store.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path), "rien n'est créé sans brouillon")

        store.write(#"{"title":"premier"}"#)
        store.write(#"{"title":"second"}"#)
        XCTAssertEqual(store.read(), #"{"title":"second"}"#)  // la lecture attend les écritures en attente
        let values = try fileURL.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        // Une autre instance (relancement de l'app) relit le même fichier.
        XCTAssertEqual(FilePostDraftStore(fileURL: fileURL).read(), #"{"title":"second"}"#)

        store.clear()
        XCTAssertNil(store.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testEmplacementStandard() {
        let store = FilePostDraftStore.standard()
        XCTAssertEqual(store.fileURL.lastPathComponent, "post_draft.json")
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, "PostDrafts")
    }

    // MARK: - Mémoire

    func testBrouillonEnMemoire() {
        let store = InMemoryPostDraftStore(#"{"title":"x"}"#)
        XCTAssertEqual(store.read(), #"{"title":"x"}"#)
        store.write("y")
        XCTAssertEqual(store.read(), "y")
        store.clear()
        XCTAssertNil(store.read())
        XCTAssertNil(InMemoryPostDraftStore().read())
    }

    // MARK: - Brouillons simulés du tour (`-WeydaPostDraft <nom>`)

    #if DEBUG
    func testBrouillonsSimulesLisiblesEtCoherents() throws {
        let folder = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent(MockRoutes.directory, isDirectory: true)
            .appendingPathComponent("post", isDirectory: true)
            .appendingPathComponent("drafts", isDirectory: true)
        let expected: [String: String] = [
            "step-category": "CATEGORY",
            "step-attributes": "ATTRIBUTES",
            "step-details": "DETAILS",
            "step-photos": "PHOTOS",
            "step-location": "LOCATION",
            "step-review": "REVIEW",
            "photos-failed": "PHOTOS",
            "details-invalid": "DETAILS",
        ]
        for (name, step) in expected {
            let data = try Data(contentsOf: folder.appendingPathComponent("\(name).json"))
            let draft = try JSONDecoder().decode(PostDraft.self, from: data)
            XCTAssertEqual(draft.ownerId, MockSessionFixture.userId, name)
            XCTAssertEqual(draft.step, step, name)
            XCTAssertNotNil(PostStep(rawValue: draft.step), name)
            XCTAssertEqual(draft.parentCategoryId, "cat_vehicules", name)
            XCTAssertEqual(draft.subcategoryId, "sub_voitures", name)
            XCTAssertTrue(draft.showPhone, name)
        }
        let review = try JSONDecoder().decode(PostDraft.self, from: Data(contentsOf: folder.appendingPathComponent("step-review.json")))
        XCTAssertEqual(review.title, "Renault Clio 4 GT Line 2019")
        XCTAssertEqual(review.priceType, "NEGOTIABLE")
        XCTAssertEqual(review.wilayaId, 16)
        XCTAssertEqual(review.photos.count, 3)
        XCTAssertTrue(review.photos.allSatisfy { $0.url != nil && $0.publicId != nil })

        // 2 photos envoyées + 1 sans fichier local (échec à l'envoi).
        let failed = try JSONDecoder().decode(PostDraft.self, from: Data(contentsOf: folder.appendingPathComponent("photos-failed.json")))
        XCTAssertEqual(failed.photos.filter { $0.url == nil }.count, 1)
        XCTAssertTrue(failed.photos.allSatisfy { PostPhotoStore.isLocalRef($0.localRef) })

        let invalid = try JSONDecoder().decode(PostDraft.self, from: Data(contentsOf: folder.appendingPathComponent("details-invalid.json")))
        XCTAssertNotNil(Validators.title(invalid.title))
        XCTAssertNotNil(Validators.description(invalid.description))
    }
    #endif
}
