import XCTest
@testable import Weyda

/// Règles de l'historique de recherche — portage du test « historique » de `SuggestionsEngineTest.kt` (Android).
/// Chaque test a son propre domaine UserDefaults, effacé à la fin.
final class SearchHistoryStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SearchHistoryStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeStore() -> SearchHistoryStore {
        SearchHistoryStore(defaults: defaults)
    }

    func testNewestFirstWithoutDuplicatesTenEntriesAtMostThenCleared() {
        defaults.set(["clio", "golf"], forKey: SearchHistoryStore.defaultsKey)
        let store = makeStore()
        XCTAssertEqual(store.entries(), ["clio", "golf"])

        XCTAssertEqual(store.remember("  Golf "), ["Golf", "clio"])
        XCTAssertEqual(store.entries(), ["Golf", "clio"])

        store.remember("x") // trop court : ignoré
        XCTAssertEqual(store.entries(), ["Golf", "clio"])

        for index in 0..<12 { store.remember("recherche \(index)") }
        XCTAssertEqual(store.entries().count, 10)
        XCTAssertEqual(store.entries().first, "recherche 11")

        store.clear()
        XCTAssertEqual(store.entries(), [])
    }

    /// Accueil et Annonces lisent le même stockage : une déconnexion vide l'historique pour tous.
    func testTwoStoresOnTheSameDefaultsShareTheHistory() {
        let home = makeStore()
        let listings = makeStore()
        home.remember("golf")
        XCTAssertEqual(listings.entries(), ["golf"])
        listings.clear()
        XCTAssertEqual(home.entries(), [])
    }

    func testAnUnreadableValueGivesAnEmptyHistory() {
        defaults.set(42, forKey: SearchHistoryStore.defaultsKey)
        let store = makeStore()
        XCTAssertEqual(store.entries(), [])
        XCTAssertEqual(store.remember("golf"), ["golf"])
    }

    func testAStoredListLongerThanTheLimitIsCappedOnRead() {
        defaults.set((1...15).map { "recherche \($0)" }, forKey: SearchHistoryStore.defaultsKey)
        XCTAssertEqual(makeStore().entries().count, SearchHistoryStore.maxEntries)
    }
}
