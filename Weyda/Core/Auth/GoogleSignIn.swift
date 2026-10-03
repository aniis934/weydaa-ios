import AuthenticationServices
import CryptoKit
import Foundation

/// Échec de la connexion Google sur l'appareil (l'annulation, elle, devient `CancellationError` : rien à afficher).
nonisolated enum GoogleSignInError: Error, Sendable, Equatable {
    /// Aucun identifiant client iOS dans la configuration (`WEYDA_GOOGLE_IOS_CLIENT_ID`) : bouton masqué.
    case notConfigured
    /// Le retour ne porte pas l'état de NOTRE demande (réponse forgée ou ancienne) : refusé.
    case stateMismatch
    /// Google a refusé ou interrompu l'autorisation, ou la page n'a pas pu s'ouvrir.
    case authorizationFailed
    /// L'échange du code contre les jetons a été refusé.
    case tokenExchangeFailed
    /// Réponse de jetons sans `id_token`.
    case missingIDToken
}

/// PKCE (RFC 7636) : un vérificateur aléatoire gardé par l'app, son défi S256 envoyé à Google. Une app n'ayant pas de
/// secret client, c'est ce qui empêche une autre app d'échanger un code intercepté.
nonisolated enum PKCE {
    /// Octets aléatoires en base64url sans remplissage : 32 octets → 43 caractères (minimum de la RFC).
    static func verifier(byteCount: Int = 32) -> String {
        base64URL(Data(SecureRandom.bytes(byteCount)))
    }

    /// `BASE64URL(SHA256(ASCII(verifier)))`.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Client OAuth « iOS » de Google : autorisation par code + PKCE, retour par le schéma = identifiant client inversé,
/// échange du code sans secret. Logique pure : testée sans réseau ni fenêtre.
nonisolated struct GoogleOAuthClient: Hashable, Sendable {
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private static let clientSuffix = ".apps.googleusercontent.com"

    let clientID: String
    /// Identifiant client inversé : « 123-abc.apps.googleusercontent.com » → « com.googleusercontent.apps.123-abc ».
    let redirectScheme: String

    var redirectURI: String { redirectScheme + ":/oauth2redirect" }

    /// nil si l'identifiant est vide ou n'a pas la forme d'un identifiant client Google.
    init?(clientID: String?) {
        guard let raw = clientID?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasSuffix(Self.clientSuffix),
              raw.count > Self.clientSuffix.count else { return nil }
        self.clientID = raw
        redirectScheme = raw.split(separator: ".").reversed().joined(separator: ".")
    }

    /// Page d'autorisation : code + PKCE S256, `state` contre la falsification, choix du compte, langue de l'app.
    func authorizationURL(state: String, codeChallenge: String, language: String = WeydaLocale.language) -> URL? {
        var components = URLComponents(string: Self.authorizationEndpoint)
        components?.percentEncodedQuery = Self.formEncoded([
            (name: "client_id", value: clientID),
            (name: "redirect_uri", value: redirectURI),
            (name: "response_type", value: "code"),
            (name: "scope", value: "openid email profile"),
            (name: "code_challenge", value: codeChallenge),
            (name: "code_challenge_method", value: "S256"),
            (name: "state", value: state),
            (name: "prompt", value: "select_account"),
            (name: "hl", value: language),
        ])
        return components?.url
    }

    /// Échange du code (client iOS : pas de secret, le vérificateur PKCE en tient lieu).
    func tokenRequest(code: String, codeVerifier: String) -> URLRequest? {
        guard let url = URL(string: Self.tokenEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncoded([
            (name: "code", value: code),
            (name: "client_id", value: clientID),
            (name: "redirect_uri", value: redirectURI),
            (name: "grant_type", value: "authorization_code"),
            (name: "code_verifier", value: codeVerifier),
        ]).utf8)
        return request
    }

    /// Code d'autorisation du retour de Google. Refusé si `state` n'est pas celui de la demande ; `access_denied`
    /// (l'utilisateur a refusé) = annulation.
    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard value("state") == expectedState else { throw GoogleSignInError.stateMismatch }
        if let error = value("error") {
            if error == "access_denied" { throw CancellationError() }
            throw GoogleSignInError.authorizationFailed
        }
        guard let code = TextCheck.nonBlank(value("code")) else { throw GoogleSignInError.authorizationFailed }
        return code
    }

    /// `id_token` de la réponse de jetons.
    static func idToken(from data: Data) throws -> String {
        let object = try? JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any],
              let token = TextCheck.nonBlank(json["id_token"] as? String) else {
            throw GoogleSignInError.missingIDToken
        }
        return token
    }

    /// Échange du code chez Google ; seul l'`id_token` en revient. Statut hors 2xx → `tokenExchangeFailed`.
    /// (`URLSession.data(for:)` attend hors du fil principal ; la réponse, minuscule, est lue chez l'appelant.)
    static func exchange(_ request: URLRequest, session: URLSession) async throws -> String {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleSignInError.tokenExchangeFailed
        }
        return try idToken(from: data)
    }

    /// Session de l'échange de jetons : éphémère (aucun cookie, aucun cache des jetons sur disque).
    static func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral)
    }

    /// `application/x-www-form-urlencoded` strict : tout sauf les caractères non réservés est encodé (un code Google
    /// contient « / », l'URI de retour « : »).
    static func formEncoded(_ fields: [(name: String, value: String)]) -> String {
        fields.map { field in "\(field.name)=\(encode(field.value))" }.joined(separator: "&")
    }

    private static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

/// « Continuer avec Google » SANS SDK — l'équivalent du Credential Manager d'Android : la page de Google dans une session
/// web du système (`ASWebAuthenticationSession`), code + PKCE, échange du code chez Google, puis l'`id_token` part à
/// `AuthRepository.loginWithGoogle` (audience « iOS » acceptée par le serveur, lot A). Inactif sans identifiant client
/// (vide aujourd'hui : bouton masqué). En API simulée : jeton factice, aucune fenêtre.
final class GoogleSignInCoordinator {
    static let simulatedIDToken = "mock-google-id-token"

    let isSimulated: Bool
    private let client: GoogleOAuthClient?
    private let session: URLSession
    /// Session web en cours : elle doit être retenue pendant l'autorisation.
    private var webSession: ASWebAuthenticationSession?
    private var presenter: AuthPresentationContext?

    init(
        clientID: String? = AppConfig.current.googleIOSClientID,
        simulated: Bool = AuthSimulation.isEnabled,
        session: URLSession = GoogleOAuthClient.makeSession()
    ) {
        client = GoogleOAuthClient(clientID: clientID)
        isSimulated = simulated
        self.session = session
    }

    /// Faux sans identifiant client : le bouton Google est masqué (comme Android sans `serverClientId`).
    var isConfigured: Bool { client != nil }

    /// id_token Google du compte choisi. Fenêtre fermée ou accès refusé → `CancellationError` ; demande déjà en
    /// cours (double appui) → `CancellationError` aussi.
    func signIn() async throws -> String {
        guard let client else { throw GoogleSignInError.notConfigured }
        if isSimulated { return Self.simulatedIDToken }
        guard webSession == nil else { throw CancellationError() }
        let verifier = PKCE.verifier()
        let state = PKCE.verifier(byteCount: 16)
        guard let url = client.authorizationURL(state: state, codeChallenge: PKCE.challenge(for: verifier)) else {
            throw GoogleSignInError.authorizationFailed
        }
        let callback = try await authorize(url: url, callbackScheme: client.redirectScheme)
        let code = try GoogleOAuthClient.authorizationCode(from: callback, expectedState: state)
        guard let request = client.tokenRequest(code: code, codeVerifier: verifier) else {
            throw GoogleSignInError.tokenExchangeFailed
        }
        return try await GoogleOAuthClient.exchange(request, session: session)
    }

    /// Ouvre la page de Google et attend le retour sur le schéma de l'app.
    private func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let anchor = AuthPresentationContext()
        defer {
            webSession = nil
            presenter = nil
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
            let resume = SingleResume(continuation)
            // `@Sendable` explicite : le rappel n'hérite pas du fil principal (le système l'appelle sur la file de
            // son choix) et ne touche que `resume`, protégé par son verrou.
            let completion: @Sendable (URL?, (any Error)?) -> Void = { callbackURL, error in
                if let callbackURL {
                    resume.resume(with: .success(callbackURL))
                } else {
                    resume.resume(with: .failure(GoogleSignInCoordinator.mapSessionError(error)))
                }
            }
            let authentication = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme,
                completionHandler: completion
            )
            authentication.presentationContextProvider = anchor
            // Cookies partagés avec Safari : un compte Google déjà ouvert évite de retaper son mot de passe.
            authentication.prefersEphemeralWebBrowserSession = false
            webSession = authentication
            presenter = anchor
            if !authentication.start() {
                resume.resume(with: .failure(GoogleSignInError.authorizationFailed))
            }
        }
    }

    /// Fenêtre fermée par l'utilisateur → annulation silencieuse ; autre échec → `authorizationFailed`.
    nonisolated static func mapSessionError(_ error: (any Error)?) -> any Error {
        guard let error else { return GoogleSignInError.authorizationFailed }
        if error is CancellationError { return error }
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
           nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
            return CancellationError()
        }
        return GoogleSignInError.authorizationFailed
    }
}
