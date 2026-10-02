import Combine
import Foundation

/// Suggestions serveur (`GET /api/search/suggestions`, ≥ 2 caractères) + historique local partagé — portage de
/// `SearchRepository`. L'historique vit dans `SearchHistoryStore` (une seule instance, celle du conteneur) ; ce
/// repository en publie l'état pour l'accueil ET l'écran Annonces : après une déconnexion (historique effacé), le
/// compte suivant ne voit plus les recherches du précédent.
final class SearchRepository: ObservableObject {
    /// Recherches récentes, la plus récente d'abord (10 au plus).
    @Published private(set) var history: [String] = []

    /// Paramètres déposés par un autre écran (alerte ouverte) ; l'écran Annonces les consomme et remet `nil`.
    @Published var pendingParams: [String: String]? = nil

    static let maxHistory = SearchHistoryStore.maxEntries
    static let minQuery = SearchHistoryStore.minQueryLength

    private let api: any WeydaAPI
    private let store: SearchHistoryStore
    private var historyLoaded = false

    init(api: any WeydaAPI, history: SearchHistoryStore) {
        self.api = api
        self.store = history
    }

    func suggestions(_ q: String, locale: String = WeydaLocale.language) async throws -> [Suggestion] {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await api.getSuggestions(q: text, locale: locale).suggestions.map { $0.toDomain() }
    }

    /// Lit l'historique au premier appel ; ensuite `history` suffit.
    func loadHistory() {
        guard !historyLoaded else { return }
        historyLoaded = true
        history = store.entries()
    }

    /// Ajoute en tête (sans doublon, casse ignorée, 10 au plus) ; une requête de moins de 2 caractères est ignorée.
    @discardableResult
    func remember(_ q: String) -> [String] {
        let updated = store.remember(q)
        historyLoaded = true
        history = updated
        return updated
    }

    func clearHistory() {
        store.clear()
        historyLoaded = true
        history = []
    }
}
