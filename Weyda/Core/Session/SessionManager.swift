import Foundation

/// État de session unique de l'app — portage de `data/session/SessionManager.kt`. Jetons en mémoire (lus par
/// le client HTTP via `authorization`), utilisateur observable par l'interface, persistance par `SessionStorage`.
///
/// Toutes les mutations ont lieu sur le fil principal (isolation par défaut), sans suspension entre lecture
/// et écriture : elles sont atomiques sans verrou (le `Mutex` d'Android). Seule la rotation attend le réseau :
/// - UN SEUL refresh en vol, partagé par tous les appels concurrents (`refreshTask`) ;
/// - une `generation` qui change à chaque remplacement de session (connexion, déconnexion, rotation) : le
///   résultat d'un refresh terminé APRÈS une déconnexion ou un changement de compte est ignoré — la session
///   ne « ressuscite » pas, et une requête de l'ancien compte n'est jamais rejouée avec le jeton du nouveau.
final class SessionManager: ObservableObject {
    @Published private(set) var user: User?

    /// Vrai quand la dernière fermeture de session n'a PAS été demandée par l'utilisateur (refresh refusé :
    /// mot de passe changé ailleurs, compte suspendu, jeton expiré). Le brouillon d'annonce survit alors à la
    /// déconnexion et le même compte le retrouve en se reconnectant ; une déconnexion volontaire l'efface.
    private(set) var lastSignOutExpired = false

    private var tokens: AuthTokens?
    private var generation = 0
    private var refreshTask: Task<String?, Never>?

    private let storage: any SessionStorage
    private let refreshCall: @Sendable (_ refreshToken: String) async throws -> TokenResponseDTO
    private let now: () -> Date

    /// - Parameters:
    ///   - refreshCall: rotation `POST api/auth/token/refresh`, par un client SANS autorisation.
    ///   - now: horloge (tests : instant fixe), comme le `Clock` d'Android.
    init(
        storage: any SessionStorage,
        refreshCall: @escaping @Sendable (_ refreshToken: String) async throws -> TokenResponseDTO,
        now: @escaping () -> Date = { Date() }
    ) {
        self.storage = storage
        self.refreshCall = refreshCall
        self.now = now
    }

    var isLoggedIn: Bool { tokens != nil && user != nil }

    var accessToken: String? { tokens?.accessToken }

    var currentTokens: AuthTokens? { tokens }

    /// Branchement du client HTTP authentifié (`AppContainer.apiClient`) : jeton courant, et rotation partagée
    /// après un 401.
    var authorization: APIAuthorization {
        APIAuthorization(
            accessToken: { [weak self] in
                await self?.accessToken
            },
            refreshAfterUnauthorized: { [weak self] failedAccessToken in
                await self?.refreshIfNeeded(failedAccessToken: failedAccessToken)
            }
        )
    }

    /// À appeler une fois au démarrage (AppContainer), après la purge d'une installation précédente.
    func restore() {
        let storedTokens = storage.readTokens()
        let storedUser = storage.readUser()
        guard let storedTokens, let storedUser, !storedTokens.isRefreshExpired(now: now()) else {
            if storedTokens != nil || storedUser != nil { storage.clear() }
            replaceSession(tokens: nil, user: nil)
            return
        }
        replaceSession(tokens: storedTokens, user: storedUser)
    }

    func signIn(_ response: TokenResponseDTO) {
        lastSignOutExpired = false
        apply(response)
    }

    /// Profil modifié (e-mail vérifié, `GET /api/users/me`…). Sans session : rien n'est recréé.
    func updateUser(_ transform: (User) -> User) {
        guard let current = user else { return }
        let updated = transform(current)
        storage.writeUser(updated)
        user = updated
    }

    func signOut() {
        lastSignOutExpired = false
        clearSession()
    }

    /// Rafraîchit les jetons si `failedAccessToken` est encore le jeton courant ; sinon renvoie le jeton déjà
    /// renouvelé par un appel concurrent. `nil` = session perdue (refresh refusé) ou panne réseau (on ne
    /// déconnecte pas sur une panne transitoire).
    func refreshIfNeeded(failedAccessToken: String) async -> String? {
        guard let current = tokens else { return nil }
        if current.accessToken != failedAccessToken { return current.accessToken }
        if let inFlight = refreshTask { return await inFlight.value }

        let startedGeneration = generation
        let refreshToken = current.refreshToken
        let refreshCall = self.refreshCall
        let task = Task<String?, Never> {
            do {
                let response = try await refreshCall(refreshToken)
                return self.finishRefresh(response, startedGeneration: startedGeneration)
            } catch {
                return self.failRefresh(error, startedGeneration: startedGeneration)
            }
        }
        refreshTask = task
        return await task.value
    }

    /// Rafraîchissement proactif quand le jeton d'accès arrive à expiration (appelé par les repositories).
    func refreshIfExpiringSoon(within seconds: TimeInterval = 60) async -> String? {
        guard let current = tokens else { return nil }
        guard current.isAccessExpiring(within: seconds, now: now()) else { return current.accessToken }
        return await refreshIfNeeded(failedAccessToken: current.accessToken)
    }

    // MARK: - Mutations

    private func apply(_ response: TokenResponseDTO) {
        let newTokens = response.toTokens(now: now())
        let newUser = response.user.toDomain(previous: user)
        storage.writeTokens(newTokens)
        storage.writeUser(newUser)
        replaceSession(tokens: newTokens, user: newUser)
    }

    /// La mémoire d'abord : même si l'effacement du trousseau échoue, plus aucune requête ne part avec
    /// l'ancien jeton.
    private func clearSession() {
        replaceSession(tokens: nil, user: nil)
        storage.clear()
    }

    /// Tout remplacement de session clôt le refresh en vol : son résultat sera ignoré (`generation`).
    private func replaceSession(tokens newTokens: AuthTokens?, user newUser: User?) {
        generation += 1
        refreshTask = nil
        tokens = newTokens
        user = newUser
    }

    private func finishRefresh(_ response: TokenResponseDTO, startedGeneration: Int) -> String? {
        // Session remplacée pendant le refresh (déconnexion, autre compte) : résultat ignoré.
        guard startedGeneration == generation else { return nil }
        apply(response)
        return response.accessToken
    }

    private func failRefresh(_ error: any Error, startedGeneration: Int) -> String? {
        guard startedGeneration == generation else { return nil }
        refreshTask = nil
        // Refus du serveur (jeton révoqué, mot de passe changé, compte suspendu) : session fermée, « expirée ».
        if let apiError = error as? APIError, apiError.status == 401 || apiError.status == 403 {
            lastSignOutExpired = true
            clearSession()
        }
        return nil
    }
}
