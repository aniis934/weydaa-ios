import Foundation
import XCTest
@testable import Weyda

/// Photos locales du dépôt : référence SHA-256, écriture unique, relecture, suppression, purge, aucun accès hors du
/// dossier. Chaque test a son dossier temporaire.
final class PostPhotoStoreTests: XCTestCase {
    private func makeStore() -> PostPhotoStore {
        PostPhotoStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("PostPhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("new", isDirectory: true))
    }

    private func cleanUp(_ store: PostPhotoStore) {
        try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent())
    }

    func testReferenceSha256Hexadecimale() {
        // Vecteur de référence FIPS 180-2 : SHA-256("abc").
        XCTAssertEqual(
            PostPhotoStore.ref(for: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertTrue(PostPhotoStore.isLocalRef(PostPhotoStore.ref(for: Data())))
        XCTAssertFalse(PostPhotoStore.isLocalRef("https://cdn/old1.webp"))
        XCTAssertFalse(PostPhotoStore.isLocalRef("../" + String(repeating: "a", count: 61)))
        XCTAssertFalse(PostPhotoStore.isLocalRef(String(repeating: "A", count: 64)))
    }

    func testEnregistrementUniqueDossierCreeExcluDesSauvegardesPuisRelecture() async throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let photo = Data("photo-1".utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))

        let ref = try await store.save(photo)
        XCTAssertEqual(ref, PostPhotoStore.ref(for: photo))
        XCTAssertEqual(store.fileURL(for: ref), store.directory.appendingPathComponent(ref))
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let loaded = try await store.load(ref)
        XCTAssertEqual(loaded, photo)

        // Même photo : même référence, fichier existant gardé tel quel (pas de réécriture).
        try Data("témoin".utf8).write(to: store.fileURL(for: ref))
        let again = try await store.save(photo)
        XCTAssertEqual(again, ref)
        let kept = try await store.load(ref)
        XCTAssertEqual(kept, Data("témoin".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        XCTAssertEqual(names, [ref])
    }

    func testRelectureImpossibleSansFichierOuAvecUneReferenceInvalide() async {
        let store = makeStore()
        defer { cleanUp(store) }
        do {
            _ = try await store.load(PostPhotoStore.ref(for: Data("absente".utf8)))
            XCTFail("fichier absent : erreur attendue")
        } catch {}
        do {
            _ = try await store.load("../../Library/Preferences/x")
            XCTFail("référence invalide : erreur attendue")
        } catch {}
    }

    func testSuppressionEtPurgeLimiteesAuDossier() async throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let first = try await store.save(Data("photo-1".utf8))
        let second = try await store.save(Data("photo-2".utf8))
        let third = try await store.save(Data("photo-3".utf8))
        // Un fichier voisin, hors du dossier des photos : jamais touché.
        let outside = store.directory.deletingLastPathComponent().appendingPathComponent("voisin.txt")
        try Data("x".utf8).write(to: outside)

        store.remove(first)
        store.remove("https://cdn/old1.webp")   // photo en ligne d'une édition : sans effet
        store.remove("../voisin.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))

        store.purge(keeping: [second])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: second).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: third).path))

        store.purge(keeping: [])
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        XCTAssertTrue(names.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))

        // Dossier absent : rien à faire, aucune erreur.
        makeStore().purge(keeping: [])
    }

    func testEmplacementsStandards() {
        XCTAssertEqual(PostPhotoStore.standard(namespace: "new").directory.lastPathComponent, "new")
        XCTAssertEqual(PostPhotoStore.standard(namespace: "edit").directory.deletingLastPathComponent().lastPathComponent, "PostDrafts")
    }
}
