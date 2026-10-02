import XCTest
@testable import Weyda

/// Portage de `PagingTest.kt` (Android).
final class PagingTests: XCTestCase {
    private struct Row: Equatable {
        let id: String
        var label: String

        init(_ id: String, label: String? = nil) {
            self.id = id
            self.label = label ?? id
        }
    }

    func testSilentReloadReplacesTheStartAndKeepsTheFollowingPages() {
        let loaded = (1...40).map { Row("a\($0)") }
        // Deux nouvelles lignes en tête : la page 1 fraîche (20) décale tout de deux rangs.
        let fresh = [Row("n1"), Row("n2")] + (1...18).map { Row("a\($0)") }
        let merged = Paging.mergeFirstPage(current: loaded, fresh: fresh) { $0.id }
        XCTAssertEqual(Array(merged.prefix(20)), fresh)
        // La suite (a21…a40) est conservée, sans doublon. Compromis assumé : a19 / a20, poussés hors de la
        // page 1 par les nouveautés, ne reviennent qu'au prochain rechargement complet.
        XCTAssertEqual(merged.dropFirst(20).map(\.id), (21...40).map { "a\($0)" })
        XCTAssertEqual(merged.count, Set(merged.map(\.id)).count)
    }

    func testARowMovedUpToPageOneAppearsOnce() {
        let loaded = (1...30).map { Row("a\($0)") }
        let fresh = [Row("a25", label: "nouveau message")] + (1...19).map { Row("a\($0)") }
        let merged = Paging.mergeFirstPage(current: loaded, fresh: fresh) { $0.id }
        XCTAssertEqual(merged.filter { $0.id == "a25" }.count, 1)
        XCTAssertEqual(merged.first { $0.id == "a25" }?.label, "nouveau message")
    }

    func testASinglePageLoadedIsReplacedEntirely() {
        let loaded = [Row("a1"), Row("a2")]
        let fresh = [Row("a2"), Row("a3"), Row("a4")]
        XCTAssertEqual(Paging.mergeFirstPage(current: loaded, fresh: fresh) { $0.id }, fresh)
    }

    /// Fonction de Models.swift (agent DATA), testée ici comme dans `PagingTest.kt`.
    func testThumbnailSuffixOnStorageWebpImagesOnly() {
        let base = "https://x.supabase.co/storage/v1/object/public/weyda-images/annonces/abc"
        XCTAssertEqual(thumbnailUrl("\(base).webp"), "\(base)_thumb.webp")
        XCTAssertEqual(thumbnailUrl("\(base)_thumb.webp"), "\(base)_thumb.webp")
        XCTAssertEqual(thumbnailUrl("https://cdn.example/photo.jpg"), "https://cdn.example/photo.jpg")
    }
}
