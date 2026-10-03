import AuthenticationServices
import Foundation
import os
import XCTest
@testable import Weyda

/// « Continuer avec Google » sans SDK (Android : Credential Manager) : identifiant client et schéma de retour, PKCE
/// (RFC 7636), URL d'autorisation, lecture du retour (state, refus, code), échange du code contre l'`id_token`
/// (faux réseau), coordinateur inactif sans identifiant et simulé en API simulée. Identifiants FICTIFS.
final class GoogleSignInTests: XCTestCase {
    private static let clientID = "123456-abcdef.apps.googleusercontent.com"

    private func client() throws -> GoogleOAuthClient {
        try XCTUnwrap(GoogleOAuthClient(clientID: Self.clientID))
    }

    private func items(_ url: URL?) throws -> [String: String] {
        let components = try XCTUnwrap(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    // MARK: - Identifiant client

    func testClientIDGivesTheReversedRedirectScheme() throws {
        let client = try client()
        XCTAssertEqual(client.clientID, Self.clientID)
        XCTAssertEqual(client.redirectScheme, "com.googleusercontent.apps.123456-abcdef")
        XCTAssertEqual(client.redirectURI, "com.googleusercontent.apps.123456-abcdef:/oauth2redirect")
        XCTAssertNotNil(GoogleOAuthClient(clientID: "  \(Self.clientID)\n"), "blancs retirés")
    }

    func testEmptyOrMalformedClientIDDisablesGoogle() {
        XCTAssertNil(GoogleOAuthClient(clientID: nil))
        XCTAssertNil(GoogleOAuthClient(clientID: ""))
        XCTAssertNil(GoogleOAuthClient(clientID: "   "))
        XCTAssertNil(GoogleOAuthClient(clientID: "123-abc"))
        XCTAssertNil(GoogleOAuthClient(clientID: ".apps.googleusercontent.com"))
    }

    // MARK: - PKCE

    func testPKCEChallengeMatchesTheRFC7636Example() {
        // RFC 7636, annexe B.
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testPKCEVerifierIsRandomBase64URLWithoutPadding() {
        let first = PKCE.verifier()
        XCTAssertEqual(first.count, 43, "32 octets → 43 caractères, minimum de la RFC")
        XCTAssertNotEqual(first, PKCE.verifier())
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(first.allSatisfy { allowed.contains($0) }, first)
        XCTAssertEqual(PKCE.base64URL(Data([0xFB, 0xFF])), "-_8")
    }

    // MARK: - URL d'autorisation

    func testAuthorizationURLAsksForACodeWithPKCEStateAndAccountChoice() throws {
        let url = try client().authorizationURL(state: "etat-42", codeChallenge: "defi-S256", language: "ar")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "accounts.google.com")
        XCTAssertEqual(url?.path, "/o/oauth2/v2/auth")
        let query = try items(url)
        XCTAssertEqual(query["client_id"], Self.clientID)
        XCTAssertEqual(query["redirect_uri"], "com.googleusercontent.apps.123456-abcdef:/oauth2redirect")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["scope"], "openid email profile")
        XCTAssertEqual(query["code_challenge"], "defi-S256")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], "etat-42")
        XCTAssertEqual(query["prompt"], "select_account")
        XCTAssertEqual(query["hl"], "ar")
        // Encodage strict : le « : » et le « / » de l'URI de retour sont encodés dans la requête.
        let absolute = url?.absoluteString ?? ""
        XCTAssertTrue(absolute.contains("redirect_uri=com.googleusercontent.apps.123456-abcdef%3A%2Foauth2redirect"), absolute)
        XCTAssertTrue(absolute.contains("scope=openid%20email%20profile"), absolute)
    }

    // MARK: - Retour de Google

    func testCallbackGivesTheCodeOnlyForOurState() throws {
        let ok = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123456-abcdef:/oauth2redirect?state=etat-42&code=4%2F0Abc-def"))
        XCTAssertEqual(try GoogleOAuthClient.authorizationCode(from: ok, expectedState: "etat-42"), "4/0Abc-def")

        XCTAssertThrowsError(try GoogleOAuthClient.authorizationCode(from: ok, expectedState: "autre")) { error in
            XCTAssertEqual(error as? GoogleSignInError, .stateMismatch)
        }
        let noState = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123456-abcdef:/oauth2redirect?code=abc"))
        XCTAssertThrowsError(try GoogleOAuthClient.authorizationCode(from: noState, expectedState: "etat-42")) { error in
            XCTAssertEqual(error as? GoogleSignInError, .stateMismatch)
        }
    }

    func testRefusalIsSilentAndOtherErrorsAreFailures() throws {
        let denied = try XCTUnwrap(URL(string: "scheme:/oauth2redirect?state=s&error=access_denied"))
        XCTAssertThrowsError(try GoogleOAuthClient.authorizationCode(from: denied, expectedState: "s")) { error in
            XCTAssertTrue(error is CancellationError)
            XCTAssertNil(ErrorMapper.message(for: error))
        }
        let failed = try XCTUnwrap(URL(string: "scheme:/oauth2redirect?state=s&error=server_error"))
        XCTAssertThrowsError(try GoogleOAuthClient.authorizationCode(from: failed, expectedState: "s")) { error in
            XCTAssertEqual(error as? GoogleSignInError, .authorizationFailed)
        }
        let noCode = try XCTUnwrap(URL(string: "scheme:/oauth2redirect?state=s&code="))
        XCTAssertThrowsError(try GoogleOAuthClient.authorizationCode(from: noCode, expectedState: "s")) { error in
            XCTAssertEqual(error as? GoogleSignInError, .authorizationFailed)
        }
    }

    func testClosedWebSessionIsACancellation() {
        let closed = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        )
        XCTAssertTrue(GoogleSignInCoordinator.mapSessionError(closed) is CancellationError)
        XCTAssertEqual(GoogleSignInCoordinator.mapSessionError(nil) as? GoogleSignInError, .authorizationFailed)
        XCTAssertEqual(
            GoogleSignInCoordinator.mapSessionError(URLError(.notConnectedToInternet)) as? GoogleSignInError,
            .authorizationFailed
        )
    }

    // MARK: - Échange du code

    func testTokenRequestIsAFormPostWithTheVerifierAndNoSecret() throws {
        let request = try XCTUnwrap(try client().tokenRequest(code: "4/0Abc+def", codeVerifier: "verif-123"))
        XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertEqual(
            body,
            "code=4%2F0Abc%2Bdef"
                + "&client_id=123456-abcdef.apps.googleusercontent.com"
                + "&redirect_uri=com.googleusercontent.apps.123456-abcdef%3A%2Foauth2redirect"
                + "&grant_type=authorization_code"
                + "&code_verifier=verif-123"
        )
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testTokenResponseGivesTheIDToken() throws {
        XCTAssertEqual(try GoogleOAuthClient.idToken(from: Data(#"{"id_token":"eyJ.google","access_token":"x"}"#.utf8)), "eyJ.google")
        XCTAssertThrowsError(try GoogleOAuthClient.idToken(from: Data(#"{"access_token":"x"}"#.utf8))) { error in
            XCTAssertEqual(error as? GoogleSignInError, .missingIDToken)
        }
        XCTAssertThrowsError(try GoogleOAuthClient.idToken(from: Data("pas du json".utf8))) { error in
            XCTAssertEqual(error as? GoogleSignInError, .missingIDToken)
        }
    }

    func testExchangeAgainstAFakeTokenEndpoint() async throws {
        let request = try XCTUnwrap(try client().tokenRequest(code: "c", codeVerifier: "v"))

        TokenEndpointStub.reply(status: 200, body: #"{"id_token":"eyJ.google.id"}"#)
        let idToken = try await GoogleOAuthClient.exchange(request, session: TokenEndpointStub.session())
        XCTAssertEqual(idToken, "eyJ.google.id")
        XCTAssertEqual(TokenEndpointStub.lastMethod(), "POST")

        TokenEndpointStub.reply(status: 400, body: #"{"error":"invalid_grant"}"#)
        do {
            _ = try await GoogleOAuthClient.exchange(request, session: TokenEndpointStub.session())
            XCTFail("refus attendu")
        } catch {
            XCTAssertEqual(error as? GoogleSignInError, .tokenExchangeFailed)
            XCTAssertEqual(ErrorMapper.message(for: error), L10n.errorGoogleSignIn)
        }
    }

    // MARK: - Coordinateur

    @MainActor
    func testCoordinatorIsInactiveWithoutClientIDAndSimulatedInMockMode() async throws {
        let inactive = GoogleSignInCoordinator(clientID: "", simulated: true)
        XCTAssertFalse(inactive.isConfigured)
        do {
            _ = try await inactive.signIn()
            XCTFail("identifiant client requis")
        } catch {
            XCTAssertEqual(error as? GoogleSignInError, .notConfigured)
        }

        let simulated = GoogleSignInCoordinator(clientID: Self.clientID, simulated: true)
        XCTAssertTrue(simulated.isConfigured)
        let token = try await simulated.signIn()
        XCTAssertEqual(token, GoogleSignInCoordinator.simulatedIDToken)
    }
}

// MARK: - Faux point d'échange (types imbriqués : aucun nom global partagé avec les autres fichiers de tests)

extension GoogleSignInTests {
    /// Répond à toute requête avec le statut et le corps fixés par le test (protégés par un verrou : URLSession
    /// instancie le protocole sur ses propres fils).
    final class TokenEndpointStub: URLProtocol {
        private struct State: Sendable {
            var status: Int = 200
            var body = Data()
            var lastMethod: String?
        }

        private static let state = OSAllocatedUnfairLock(initialState: State())

        static func reply(status: Int, body: String) {
            state.withLock { current in
                current.status = status
                current.body = Data(body.utf8)
                current.lastMethod = nil
            }
        }

        static func lastMethod() -> String? {
            state.withLock { $0.lastMethod }
        }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TokenEndpointStub.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let method = request.httpMethod
            let reply: State = Self.state.withLock { current in
                current.lastMethod = method
                return current
            }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
