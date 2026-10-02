import Foundation
import SwiftUI

/// Injection de dépendances manuelle — miroir d'`AppContainer` (Android). Créé une fois par
/// `WeydaApp`, transmis par l'environnement SwiftUI. Les repositories, la session et le temps
/// réel s'y ajoutent à partir de la phase 1.
final class AppContainer: ObservableObject {
    let config: AppConfig
    /// Session HTTP de l'API : cookies coupés (l'app s'authentifie par jeton Bearer, jamais par
    /// cookie de session web). En API simulée (Debug), les réponses viennent de MockFixtures.
    let apiSession: URLSession

    init(config: AppConfig = .current, mockAPI: Bool = LaunchOptions.mockAPI) {
        self.config = config
        self.apiSession = Self.makeAPISession(mockAPI: mockAPI)
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
}
