import Combine
import XCTest
@testable import Weyda

/// Portage de `SuggestionsEngineTest.kt` (Android) : anti-rebond et requête unique, rien sous 2 caractères,
/// erreur = liste vide, historique (en tête, sans doublon, 10 au plus) PARTAGÉ entre accueil et Annonces.
/// L'historique passe par `SearchHistoryStore` (vraies règles) derrière un faux dépôt.
final class SuggestionsEngineTests: XCTestCase {

    @MainActor
    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    @MainActor
    private func makeEngine(server: FakeSuggestionServer, debounce: TimeInterval = 0.05) -> SuggestionsEngine {
        SuggestionsEngine(
            fetch: { [server] query, locale in try server.fetch(query, locale: locale) },
            locale: { "fr" },
            debounce: debounce
        )
    }

    @MainActor
    private func makeEngine(repository: FakeSearchRepository) -> SuggestionsEngine {
        SuggestionsEngine(
            fetch: { _, _ in [] },
            history: repository.$history.eraseToAnyPublisher(),
            loadHistory: { [repository] in repository.loadHistory() },
            remember: { [repository] text in repository.remember(text) },
            clearHistory: { [repository] in repository.clearHistory() },
            locale: { "fr" }
        )
    }

    @MainActor
    func testDebounceSendsOneRequestForFastTypingAndNothingUnderTwoCharacters() async throws {
        let server = FakeSuggestionServer()
        server.answer = .success([
            Suggestion(text: "Voitures", type: .category, slug: "voitures"),
            Suggestion(text: "Alger", type: .wilaya, id: 16),
            Suggestion(text: "Clio 4", type: .listing),
        ])
        let engine = makeEngine(server: server)

        engine.onQueryChange("c")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(server.calls.isEmpty)

        // Frappe rapide : seule la dernière valeur sort de l'anti-rebond (espaces retirés).
        engine.onQueryChange("cl")
        engine.onQueryChange("cli")
        engine.onQueryChange("clio ")
        let answered = await eventually { engine.suggestions.count == 3 }
        XCTAssertTrue(answered)
        XCTAssertEqual(server.calls, ["clio"])
        XCTAssertEqual(server.locales, ["fr"])
        XCTAssertEqual(engine.suggestions.map(\.type), [.category, .wilaya, .listing])
        XCTAssertEqual(engine.suggestions.first?.slug, "voitures")
        XCTAssertEqual(engine.suggestions.dropFirst().first?.id, 16)

        // Effacer le champ vide la liste immédiatement, sans requête.
        engine.onQueryChange("")
        XCTAssertTrue(engine.suggestions.isEmpty)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(server.calls.count, 1)

        // Une erreur serveur = liste vide, pas d'exception.
        server.answer = .failure(URLError(.badServerResponse))
        engine.onQueryChange("mo")
        let asked = await eventually { server.calls.count == 2 }
        XCTAssertTrue(asked)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(engine.suggestions.isEmpty)
    }

    /// iOS : la liste refermée ne se rouvre pas, et le même mot relance bien une requête.
    @MainActor
    func testClearingClosesTheListAndTheSameWordCanBeSearchedAgain() async throws {
        let server = FakeSuggestionServer()
        server.answer = .success([Suggestion(text: "Golf 7", type: .listing)])
        let engine = makeEngine(server: server)

        engine.onQueryChange("golf")
        let first = await eventually { !engine.suggestions.isEmpty }
        XCTAssertTrue(first)

        engine.clearSuggestions()
        XCTAssertTrue(engine.suggestions.isEmpty)

        engine.onQueryChange("golf")
        let second = await eventually { server.calls.count == 2 && !engine.suggestions.isEmpty }
        XCTAssertTrue(second)
        XCTAssertEqual(server.calls, ["golf", "golf"])
    }

    @MainActor
    func testHistoryNewestFirstWithoutDuplicatesTenAtMostThenCleared() async throws {
        let suite = "SuggestionsEngineTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["clio", "golf"], forKey: SearchHistoryStore.defaultsKey)
        let repository = FakeSearchRepository(store: SearchHistoryStore(defaults: defaults))
        let engine = makeEngine(repository: repository)

        let loaded = await eventually { engine.history == ["clio", "golf"] }
        XCTAssertTrue(loaded)

        await engine.remember("  Golf ").value
        XCTAssertEqual(engine.history, ["Golf", "clio"])

        await engine.remember("x").value // trop court : ignoré
        XCTAssertEqual(engine.history, ["Golf", "clio"])

        for index in 0..<12 {
            await engine.remember("recherche \(index)").value
        }
        XCTAssertEqual(engine.history.count, 10)
        XCTAssertEqual(engine.history.first, "recherche 11")

        await engine.clearHistory().value
        XCTAssertTrue(engine.history.isEmpty)
    }

    @MainActor
    func testHistoryIsSharedAndClearedForEveryScreenAtSignOut() async throws {
        let suite = "SuggestionsEngineTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["clio"], forKey: SearchHistoryStore.defaultsKey)
        let repository = FakeSearchRepository(store: SearchHistoryStore(defaults: defaults))
        let home = makeEngine(repository: repository)
        let listings = makeEngine(repository: repository)

        let loaded = await eventually { home.history == ["clio"] && listings.history == ["clio"] }
        XCTAssertTrue(loaded)

        await home.remember("golf").value
        XCTAssertEqual(listings.history, ["golf", "clio"])

        // Déconnexion (conteneur) : l'historique est vidé via le dépôt, les deux écrans le voient.
        repository.clearHistory()
        XCTAssertTrue(home.history.isEmpty)
        XCTAssertTrue(listings.history.isEmpty)
    }
}

/// Faux `GET /api/search/suggestions` : enregistre les requêtes, répond la valeur programmée.
@MainActor
final class FakeSuggestionServer {
    var answer: Result<[Suggestion], any Error> = .success([])
    private(set) var calls: [String] = []
    private(set) var locales: [String] = []

    func fetch(_ query: String, locale: String) throws -> [Suggestion] {
        calls.append(query)
        locales.append(locale)
        return try answer.get()
    }
}

/// Faux `SearchRepository` (signature du contrat) : historique publié, règles de `SearchHistoryStore`.
@MainActor
final class FakeSearchRepository: ObservableObject {
    @Published private(set) var history: [String] = []
    private let store: SearchHistoryStore

    init(store: SearchHistoryStore) {
        self.store = store
    }

    func loadHistory() {
        history = store.entries()
    }

    func remember(_ query: String) {
        history = store.remember(query)
    }

    func clearHistory() {
        store.clear()
        history = []
    }
}
