import Foundation
import os

/// Historique local des recherches — portage de `data/local/SearchHistoryStore.kt` ET des règles de
/// `SearchRepository.remember` / `clearHistory` (Android) : 10 entrées au plus, la plus récente en tête, sans
/// doublon (casse ignorée), requêtes de moins de 2 caractères ignorées. Stocké dans UserDefaults (tableau de
/// chaînes) : un historique est un confort, une valeur illisible le rend simplement vide, jamais fatal.
///
/// Partagé par l'accueil et l'écran Annonces (une seule instance, dans le conteneur) ; à vider à la
/// déconnexion, sinon le compte suivant verrait les recherches du précédent (constaté sur Android).
///
/// `@unchecked Sendable` : UserDefaults est sûr entre fils ; le verrou rend atomique le couple lecture +
/// écriture de `remember` (deux recherches simultanées ne s'écrasent pas).
nonisolated final class SearchHistoryStore: @unchecked Sendable {
    static let maxEntries = 10
    static let minQueryLength = 2
    static let defaultsKey = "weyda.search.history"

    private let defaults: UserDefaults
    private let key: String
    private let lock = OSAllocatedUnfairLock()

    init(defaults: UserDefaults = .standard, key: String = SearchHistoryStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// L'historique, le plus récent d'abord.
    func entries() -> [String] {
        lock.withLockUnchecked { read() }
    }

    /// Ajoute en tête (sans doublon, insensible à la casse), borne à `maxEntries` ; renvoie la liste à jour.
    /// Une requête trop courte est ignorée (liste inchangée).
    @discardableResult
    func remember(_ query: String) -> [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return lock.withLockUnchecked {
            let current = read()
            guard text.count >= Self.minQueryLength else { return current }
            let others = current.filter { $0.compare(text, options: .caseInsensitive) != .orderedSame }
            let updated = Array(([text] + others).prefix(Self.maxEntries))
            defaults.set(updated, forKey: key)
            return updated
        }
    }

    /// Efface tout (bouton « Effacer », déconnexion).
    func clear() {
        lock.withLockUnchecked { defaults.removeObject(forKey: key) }
    }

    /// Valeur absente ou d'un autre type → historique vide.
    private func read() -> [String] {
        guard let stored = defaults.stringArray(forKey: key) else { return [] }
        return Array(stored.prefix(Self.maxEntries))
    }
}
