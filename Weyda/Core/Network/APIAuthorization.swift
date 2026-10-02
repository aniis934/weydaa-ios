import Foundation

/// Branchement du client HTTP sur la session — rôle d'`AuthInterceptor` + `TokenAuthenticator` (Android).
/// Des closures plutôt qu'un protocole : la session vit sur le fil principal, le client hors de lui.
nonisolated struct APIAuthorization: Sendable {
    /// Jeton d'accès courant ; `nil` = visiteur, la requête part sans Bearer.
    var accessToken: @Sendable () async -> String?
    /// Après un 401 sur une requête partie avec `failedAccessToken` : nouveau jeton (rotation partagée,
    /// une seule à la fois), ou `nil` (session perdue, réseau coupé) → le 401 remonte tel quel.
    var refreshAfterUnauthorized: @Sendable (_ failedAccessToken: String) async -> String?

    init(
        accessToken: @escaping @Sendable () async -> String?,
        refreshAfterUnauthorized: @escaping @Sendable (_ failedAccessToken: String) async -> String?
    ) {
        self.accessToken = accessToken
        self.refreshAfterUnauthorized = refreshAfterUnauthorized
    }

    /// Client sans authentification : connexion, rotation, inscription, mot de passe oublié.
    static let none = APIAuthorization(accessToken: { nil }, refreshAfterUnauthorized: { _ in nil })
}
