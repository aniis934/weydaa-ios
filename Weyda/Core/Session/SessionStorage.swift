import Foundation

/// Persistance de la session (jetons + utilisateur) — portage de `SessionStorage` (Android). Trousseau en
/// prod (`KeychainSessionStorage`), mémoire dans les tests et les aperçus.
///
/// Appelée seulement par `SessionManager`, sur le fil principal. Synchrone et tolérante : jamais d'exception,
/// un échec de lecture vaut « rien d'enregistré » et un échec d'écriture laisse la session en mémoire
/// (il faudra se reconnecter au prochain lancement), comme `SessionStore` sur Android.
protocol SessionStorage {
    func readTokens() -> AuthTokens?
    func writeTokens(_ tokens: AuthTokens?)
    func readUser() -> User?
    func writeUser(_ user: User?)
    func clear()
}

/// Session en mémoire (tests, aperçus SwiftUI).
final class InMemorySessionStorage: SessionStorage {
    var tokens: AuthTokens?
    var user: User?

    init(tokens: AuthTokens? = nil, user: User? = nil) {
        self.tokens = tokens
        self.user = user
    }

    func readTokens() -> AuthTokens? { tokens }

    func writeTokens(_ tokens: AuthTokens?) { self.tokens = tokens }

    func readUser() -> User? { user }

    func writeUser(_ user: User?) { self.user = user }

    func clear() {
        tokens = nil
        user = nil
    }
}
