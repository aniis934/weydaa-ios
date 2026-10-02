import Foundation
import SwiftUI
import UIKit

/// Injection de dépendances manuelle — miroir d'`AppContainer` (Android). Créé une fois par
/// `WeydaApp`, transmis par l'environnement SwiftUI. Les repositories et le temps réel s'y ajoutent
/// à la vague suivante de la phase 1.
final class AppContainer: ObservableObject {
    let config: AppConfig
    /// Session HTTP de l'API : cookies coupés (l'app s'authentifie par jeton Bearer, jamais par
    /// cookie de session web). En API simulée (Debug), les réponses viennent de MockFixtures.
    let apiSession: URLSession
    /// Client SANS jeton : connexion (`api/auth/token`, Google), rotation (`…/token/refresh`), inscription,
    /// mot de passe oublié (Android : `authApi`).
    let authClient: APIClient
    /// Session unique (jetons + utilisateur), restaurée du trousseau au démarrage.
    let sessionManager: SessionManager
    /// Client authentifié : Bearer de la session, rotation des jetons et rejeu sur 401 (Android : `api`).
    let apiClient: APIClient
    /// En ligne / hors ligne : un seul moniteur pour toute l'app (bandeau, relance des écrans en erreur).
    let connectivity: ConnectivityMonitor

    init(config: AppConfig = .current, mockAPI: Bool = LaunchOptions.mockAPI) {
        self.config = config
        let apiSession = Self.makeAPISession(mockAPI: mockAPI)
        self.apiSession = apiSession

        let authClient = APIClient(baseURL: config.apiBaseURL, session: apiSession)
        self.authClient = authClient

        // Lecture du trousseau de quelques ms au démarrage : la session est connue avant le premier écran.
        let sessionManager = SessionManager(
            storage: Self.makeSessionStorage(mockAPI: mockAPI),
            refreshCall: { refreshToken in
                try await authClient.send(
                    .post("api/auth/token/refresh", json: RefreshRequestDTO(refreshToken: refreshToken)),
                    as: TokenResponseDTO.self
                )
            }
        )
        sessionManager.restore()
        self.sessionManager = sessionManager

        self.apiClient = APIClient(
            baseURL: config.apiBaseURL,
            session: apiSession,
            authorization: sessionManager.authorization
        )
        self.connectivity = ConnectivityMonitor()
    }

    private static func makeAPISession(mockAPI: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        #if DEBUG
        if mockAPI {
            configuration.protocolClasses = [MockURLProtocol.self]
        }
        #endif
        return URLSession(configuration: configuration)
    }

    /// Trousseau, purgé au premier lancement d'une nouvelle installation. En API simulée (Debug) : session
    /// en mémoire, jamais dans le trousseau — chaque lancement du tour de captures part du même état.
    private static func makeSessionStorage(mockAPI: Bool) -> any SessionStorage {
        #if DEBUG
        if mockAPI {
            return InMemorySessionStorage()
        }
        #endif
        let keychain = KeychainSessionStorage()
        keychain.purgeIfFreshInstall(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        return keychain
    }
}
