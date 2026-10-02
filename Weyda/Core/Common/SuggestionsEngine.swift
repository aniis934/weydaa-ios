import Combine
import Foundation

/// Suggestions de recherche avec anti-rebond (300 ms) et abandon de la requête précédente, plus l'historique
/// local — portage de `ui/common/SuggestionsEngine.kt`. Partagé par l'accueil et l'écran Annonces.
///
/// Découplé du dépôt par des closures (le `SearchRepository` les fournit) : testable sans réseau.
/// - `fetch(q, langue)` : `GET /api/search/suggestions` (appelé seulement à partir de 2 caractères) ;
/// - `history` : l'historique PARTAGÉ (`search.$history`) — tous les moteurs voient la même liste, vidée pour
///   tous à la déconnexion ;
/// - `loadHistory` / `remember` / `clearHistory` : actions du dépôt.
final class SuggestionsEngine: ObservableObject {
    static let debounceInterval: TimeInterval = 0.3
    /// `SearchRepository.MIN_QUERY` (Android) : en dessous, ni requête ni suggestion.
    static let minQueryLength = 2

    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var history: [String] = []

    private let fetch: @MainActor @Sendable (_ query: String, _ locale: String) async throws -> [Suggestion]
    private let rememberAction: @MainActor @Sendable (String) async -> Void
    private let clearHistoryAction: @MainActor @Sendable () async -> Void
    /// Langue relue à chaque requête (elle peut changer pendant la vie de l'écran).
    private let locale: @MainActor @Sendable () -> String
    private let debounce: TimeInterval

    private var query = ""
    /// Dernière valeur sortie de l'anti-rebond (`distinctUntilChanged`) ; nil après `clearSuggestions`.
    private var lastDebounced: String?
    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var historySubscription: AnyCancellable?

    init(
        fetch: @escaping @MainActor @Sendable (_ query: String, _ locale: String) async throws -> [Suggestion],
        history: AnyPublisher<[String], Never> = Empty<[String], Never>().eraseToAnyPublisher(),
        loadHistory: @escaping @MainActor @Sendable () async -> Void = {},
        remember: @escaping @MainActor @Sendable (String) async -> Void = { _ in },
        clearHistory: @escaping @MainActor @Sendable () async -> Void = {},
        locale: @escaping @MainActor @Sendable () -> String = { WeydaLocale.language },
        debounce: TimeInterval = SuggestionsEngine.debounceInterval
    ) {
        self.fetch = fetch
        self.rememberAction = remember
        self.clearHistoryAction = clearHistory
        self.locale = locale
        self.debounce = debounce
        historySubscription = history.sink { [weak self] entries in
            self?.history = entries
        }
        Task { await loadHistory() }
    }

    /// Saisie : anti-rebond, puis requête si la valeur a changé ; le champ vidé (ou trop court) vide la liste
    /// tout de suite, sans requête.
    func onQueryChange(_ value: String) {
        query = value
        if Self.trimmedLength(value) < Self.minQueryLength { suggestions = [] }
        debounceTask?.cancel()
        let wait = UInt64(max(debounce, 0) * 1_000_000_000)
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: wait)
            } catch {
                return
            }
            self?.debounced(value)
        }
    }

    /// Après une recherche lancée ou une suggestion choisie : la liste se referme. La requête repart de zéro —
    /// sinon retaper le même mot serait jugé « inchangé » et ne proposerait plus rien.
    func clearSuggestions() {
        query = ""
        lastDebounced = nil
        debounceTask?.cancel()
        fetchTask?.cancel()
        suggestions = []
    }

    /// Mémorise une recherche (règles du dépôt : 2 caractères au moins, sans doublon, 10 au plus).
    @discardableResult
    func remember(_ text: String) -> Task<Void, Never> {
        let action = rememberAction
        return Task { await action(text) }
    }

    @discardableResult
    func clearHistory() -> Task<Void, Never> {
        let action = clearHistoryAction
        return Task { await action() }
    }

    // MARK: - Interne

    /// Valeur sortie de l'anti-rebond : nouvelle requête (la précédente est abandonnée, comme `mapLatest`).
    private func debounced(_ value: String) {
        guard value != lastDebounced else { return }
        lastDebounced = value
        fetchTask?.cancel()
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minQueryLength else {
            suggestions = []
            return
        }
        let fetcher = self.fetch
        let language = locale()
        fetchTask = Task { [weak self] in
            // Une erreur serveur = liste vide, jamais d'exception.
            let results = (try? await fetcher(text, language)) ?? []
            guard !Task.isCancelled, let self else { return }
            // Une réponse partie avant `clearSuggestions` ne rouvre pas la liste après coup.
            self.suggestions = Self.trimmedLength(self.query) < Self.minQueryLength ? [] : results
        }
    }

    private nonisolated static func trimmedLength(_ value: String) -> Int {
        value.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}
