import os
import XCTest
@testable import Weyda

/// Client HTTP contre un serveur de test en mémoire (`StubURLProtocol`) : en-têtes, Bearer (posé, absent,
/// jamais hors de l'hôte de l'API), rotation + rejeu unique sur 401, erreurs, corps, téléchargement.
/// Données FICTIVES uniquement ; hôte en `.test` (réservé, jamais résolu).
final class APIClientTests: XCTestCase {
    private static let base = "https://api.weydaa.test/"

    private struct Profile: Decodable, Sendable {
        let id: String
    }

    private struct Credentials: Encodable, Sendable {
        let email: String
        let password: String
    }

    private func makeClient(
        accessToken: String? = "access-1",
        refresh: RefreshRecorder = RefreshRecorder(freshToken: nil),
        language: String = "fr",
        handler: @escaping StubHandler
    ) throws -> APIClient {
        StubServer.shared.reset(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let authorization = APIAuthorization(
            accessToken: { accessToken },
            refreshAfterUnauthorized: { failedAccessToken in await refresh.refresh(failedAccessToken) }
        )
        let baseURL = try XCTUnwrap(URL(string: Self.base))
        return APIClient(
            baseURL: baseURL,
            session: URLSession(configuration: configuration),
            authorization: authorization,
            language: language
        )
    }

    // MARK: - En-têtes et Bearer

    func testCommonHeadersAndBearerTowardTheAPIHost() async throws {
        let client = try makeClient(language: "ar") { _ in .json(200, #"{"id":"user_1"}"#) }
        let profile = try await client.send(.get("api/users/me"), as: Profile.self)
        XCTAssertEqual(profile.id, "user_1")

        let request = try XCTUnwrap(StubServer.shared.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://api.weydaa.test/api/users/me")
        XCTAssertEqual(request.header("Authorization"), "Bearer access-1")
        XCTAssertEqual(request.header("Accept"), "application/json")
        XCTAssertEqual(request.header("Accept-Language"), "ar")
        XCTAssertEqual(request.header("User-Agent"), APIClient.defaultUserAgent)
        XCTAssertTrue(APIClient.defaultUserAgent.hasPrefix("WeydaIOS/"))
    }

    func testTokenEndpointsNeverCarryTheBearer() async throws {
        let recorder = RefreshRecorder(freshToken: "access-2")
        let client = try makeClient(refresh: recorder) { request in
            request.url.path == "/api/auth/token"
                ? .json(401, #"{"error":"invalidCredentials"}"#)
                : .json(200, "{}")
        }
        do {
            try await client.perform(.post("api/auth/token", json: Credentials(email: "test@example.com", password: "Motdepasse1")))
            XCTFail("401 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.code, "invalidCredentials")
        }
        try await client.perform(.post("api/auth/token/refresh", json: ["refreshToken": "refresh-1"]))

        let requests = StubServer.shared.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].header("Authorization"))
        XCTAssertNil(requests[1].header("Authorization"))
        // Un 401 sans Bearer ne déclenche aucune rotation.
        let refreshed = await recorder.failedTokens
        XCTAssertTrue(refreshed.isEmpty)
    }

    func testBearerNeverLeavesTheAPIHost() async throws {
        let client = try makeClient { _ in .json(200, "{}") }
        try await client.perform(.get("https://cdn.example.com/files/a.json"))
        try await client.perform(APIRequest(.get, "api/annonces", authenticated: false))

        let requests = StubServer.shared.requests
        XCTAssertEqual(requests.map(\.url.host), ["cdn.example.com", "api.weydaa.test"])
        XCTAssertNil(requests[0].header("Authorization"))
        XCTAssertNil(requests[1].header("Authorization"))

        let otherHost = try XCTUnwrap(URL(string: "https://evil.example/api/users/me"))
        let upperCase = try XCTUnwrap(URL(string: "https://API.weydaa.test/api/users/me"))
        let refresh = try XCTUnwrap(URL(string: "https://api.weydaa.test/api/auth/token/refresh"))
        XCTAssertFalse(APIClient.mayCarryBearer(otherHost, apiHost: "api.weydaa.test"))
        XCTAssertTrue(APIClient.mayCarryBearer(upperCase, apiHost: "api.weydaa.test"))
        XCTAssertFalse(APIClient.mayCarryBearer(refresh, apiHost: "api.weydaa.test"))
    }

    // MARK: - 401 → rotation → rejeu unique

    func testUnauthorizedRefreshesThenReplaysOnceWithTheNewToken() async throws {
        let recorder = RefreshRecorder(freshToken: "access-2")
        let client = try makeClient(refresh: recorder) { request in
            request.header("Authorization") == "Bearer access-2"
                ? .json(200, #"{"id":"user_1"}"#)
                : .json(401, #"{"error":"unauthorized"}"#)
        }
        let profile = try await client.send(.get("api/users/me"), as: Profile.self)
        XCTAssertEqual(profile.id, "user_1")

        let headers = StubServer.shared.requests.map { $0.header("Authorization") }
        XCTAssertEqual(headers, ["Bearer access-1", "Bearer access-2"])
        let refreshed = await recorder.failedTokens
        XCTAssertEqual(refreshed, ["access-1"])
    }

    func testASecondUnauthorizedIsNotReplayedAgain() async throws {
        let recorder = RefreshRecorder(freshToken: "access-2")
        let client = try makeClient(refresh: recorder) { _ in .json(401, #"{"error":"unauthorized"}"#) }
        do {
            _ = try await client.send(.get("api/users/me"), as: Profile.self)
            XCTFail("401 attendu")
        } catch let error as APIError {
            XCTAssertTrue(error.isUnauthorized)
        }
        XCTAssertEqual(StubServer.shared.requests.count, 2)
        let refreshed = await recorder.failedTokens
        XCTAssertEqual(refreshed, ["access-1"])
    }

    func testUnauthorizedWithoutReplayKeepsTheServerError() async throws {
        // Rotation impossible (session perdue) : pas de rejeu, l'erreur du serveur remonte.
        let lost = RefreshRecorder(freshToken: nil)
        let client = try makeClient(refresh: lost) { _ in .json(401, #"{"error":"loginRequired"}"#) }
        do {
            try await client.perform(.get("api/annonces/abc/contact"))
            XCTFail("401 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "loginRequired")
        }
        XCTAssertEqual(StubServer.shared.requests.count, 1)
        let lostCalls = await lost.failedTokens
        XCTAssertEqual(lostCalls, ["access-1"])

        // Visiteur (aucun jeton) : pas de Bearer, donc ni rotation ni rejeu.
        let visitor = RefreshRecorder(freshToken: "access-2")
        let anonymous = try makeClient(accessToken: nil, refresh: visitor) { _ in .json(401, "") }
        do {
            try await anonymous.perform(.get("api/favorites"))
            XCTFail("401 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "unauthorized")
        }
        XCTAssertEqual(StubServer.shared.requests.count, 1)
        XCTAssertNil(StubServer.shared.requests.first?.header("Authorization"))
        let visitorCalls = await visitor.failedTokens
        XCTAssertTrue(visitorCalls.isEmpty)
    }

    /// Branchement d'`AppContainer` : le client authentifié lit la session, et un 401 passe par SA rotation.
    @MainActor
    func testSessionAuthorizationRotatesOnUnauthorizedAndReplays() async throws {
        let user = AuthUserDTO(id: "user_1", name: "Karim B.", email: "test@example.com", emailVerified: true)
        let rotated = TokenResponseDTO(accessToken: "access-2", refreshToken: "refresh-2", user: user)
        let session = SessionManager(storage: InMemorySessionStorage(), refreshCall: { _ in rotated })
        session.signIn(TokenResponseDTO(accessToken: "access-1", refreshToken: "refresh-1", user: user))

        StubServer.shared.reset { request in
            request.header("Authorization") == "Bearer access-2"
                ? .json(200, #"{"id":"user_1"}"#)
                : .json(401, #"{"error":"unauthorized"}"#)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let baseURL = try XCTUnwrap(URL(string: Self.base))
        let client = APIClient(
            baseURL: baseURL,
            session: URLSession(configuration: configuration),
            authorization: session.authorization
        )

        let profile = try await client.send(.get("api/users/me"), as: Profile.self)
        XCTAssertEqual(profile.id, "user_1")
        XCTAssertEqual(session.accessToken, "access-2")
        XCTAssertEqual(StubServer.shared.requests.map { $0.header("Authorization") }, ["Bearer access-1", "Bearer access-2"])
    }

    // MARK: - Erreurs

    func testErrorResponsesBecomeAPIErrors() async throws {
        let client = try makeClient { request in
            if request.url.path == "/api/auth/register" {
                return .json(400, #"{"error":"invalidData","details":{"fieldErrors":{"email":["validation.emailInvalid"]},"formErrors":[]}}"#)
            }
            return .json(429, #"{"error":"rateLimited"}"#, headers: ["Retry-After": "900"])
        }
        do {
            try await client.perform(.post("api/auth/register", json: Credentials(email: "pas-un-email", password: "x")))
            XCTFail("400 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.fieldErrors, ["email": "validation.emailInvalid"])
        }
        do {
            try await client.perform(.get("api/annonces"))
            XCTFail("429 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "rateLimited")
            XCTAssertEqual(error.retryAfterSeconds, 900)
        }
    }

    func testTransportErrorsPassThroughUnchanged() async throws {
        let client = try makeClient { _ in StubReply(failure: URLError(.notConnectedToInternet)) }
        do {
            try await client.perform(.get("api/categories"))
            XCTFail("erreur réseau attendue")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
            XCTAssertEqual(ErrorMapper.message(for: error), L10n.errorOffline)
        }
    }

    func testEmptyResponsesAreAcceptedWhenNothingIsExpected() async throws {
        let client = try makeClient { _ in StubReply(status: 204) }
        try await client.perform(.delete("api/favorites/abc"))
        let data = try await client.data(for: .patch("api/notifications"))
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(StubServer.shared.requests.map(\.method), ["DELETE", "PATCH"])
    }

    // MARK: - Corps et paramètres

    func testJSONBodyIsEncodedWithItsContentType() async throws {
        let client = try makeClient { _ in .json(200, "{}") }
        try await client.perform(.post("api/auth/token", json: Credentials(email: "test@example.com", password: "Motdepasse1")))

        let request = try XCTUnwrap(StubServer.shared.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.header("Content-Type"), "application/json; charset=utf-8")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: String])
        XCTAssertEqual(json, ["email": "test@example.com", "password": "Motdepasse1"])
    }

    func testUploadIsMultipartWithTheFileField() async throws {
        let client = try makeClient { _ in .json(200, #"{"url":"u","thumbnailUrl":"t","publicId":"p"}"#) }
        let file = MultipartFile(fileName: "photo.jpg", mimeType: "image/jpeg", data: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try await client.perform(.upload(file))

        let request = try XCTUnwrap(StubServer.shared.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/upload")
        let contentType = try XCTUnwrap(request.header("Content-Type"))
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(prefix))
        let boundary = String(contentType.dropFirst(prefix.count))
        XCTAssertEqual(request.body, APIClient.multipartBody(file, boundary: boundary))
        let text = String(decoding: request.body, as: UTF8.self)
        XCTAssertTrue(text.contains(#"Content-Disposition: form-data; name="file"; filename="photo.jpg""#))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
    }

    func testQueryParametersAreEncodedLikeRetrofit() async throws {
        let client = try makeClient { _ in .json(200, "{}") }
        var request = APIRequest.get("api/annonces")
        request.addQuery("q", "a+b c")
        request.addQuery("wilaya", 16)
        request.addQuery("priceMin", 1500.0)
        request.addQuery("priceMax", 12.5)
        request.addQuery("archived", true)
        request.addQuery("category", nil as String?)
        try await client.perform(request)

        let url = try XCTUnwrap(StubServer.shared.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        XCTAssertEqual(query, "q=a%2Bb%20c&wilaya=16&priceMin=1500&priceMax=12.5&archived=true")
    }

    func testPathSegmentsAreEncoded() throws {
        XCTAssertEqual(APIRequest.segment("voiture rouge/2"), "voiture%20rouge%2F2")
        XCTAssertEqual(APIRequest.segment("clio-4-dci"), "clio-4-dci")
        let base = try XCTUnwrap(URL(string: Self.base))
        let url = try APIRequest.get("api/annonces/" + APIRequest.segment("سيارة")).url(relativeTo: base)
        XCTAssertEqual(url.absoluteString, "https://api.weydaa.test/api/annonces/%D8%B3%D9%8A%D8%A7%D8%B1%D8%A9")
        XCTAssertEqual(APIRequest.queryValue(1500), "1500")
        XCTAssertEqual(APIRequest.queryValue(12.5), "12.5")
    }

    // MARK: - Téléchargement

    func testDownloadWritesTheExportToAFile() async throws {
        let export = #"{"user":{"name":"Karim B."}}"#
        let client = try makeClient { request in
            request.url.path == "/api/users/me/export" ? .json(200, export) : .json(404, "")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("weyda-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("export.json", isDirectory: false)

        let file = try await client.download(.get("api/users/me/export"), to: destination)
        XCTAssertEqual(file, destination)
        XCTAssertEqual(try Data(contentsOf: file), Data(export.utf8))
        XCTAssertEqual(StubServer.shared.requests.first?.header("Authorization"), "Bearer access-1")
    }

    func testDownloadRateLimitBecomesAnAPIError() async throws {
        let client = try makeClient { _ in .json(429, #"{"error":"rateLimited"}"#, headers: ["Retry-After": "3600"]) }
        do {
            _ = try await client.download(.get("api/users/me/export"))
            XCTFail("429 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "rateLimited")
            XCTAssertEqual(error.retryAfterSeconds, 3600)
        }
    }
}

// MARK: - Serveur de test (types imbriqués : aucun nom global partagé avec les autres fichiers de tests)

extension APIClientTests {
    typealias StubHandler = @Sendable (StubRequest) -> StubReply

    /// Requête vue par le serveur de test (corps relu depuis le flux : URLSession ne transmet pas `httpBody`).
    struct StubRequest: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    struct StubReply: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// Erreur de transport simulée (hors ligne, délai…) à la place d'une réponse.
        var failure: URLError?

        static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> StubReply {
            StubReply(status: status, headers: headers, body: Data(body.utf8))
        }
    }

    /// État du serveur de test, partagé avec `StubURLProtocol` (instancié par URLSession sur ses propres fils) :
    /// protégé par un verrou. Les tests d'une classe s'exécutent l'un après l'autre ; chacun le réinitialise.
    final class StubServer: Sendable {
        static let shared = StubServer()

        private struct State: Sendable {
            var handler: StubHandler = { _ in StubReply(status: 404) }
            var requests: [StubRequest] = []
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        func reset(_ handler: @escaping StubHandler) {
            state.withLock { $0 = State(handler: handler) }
        }

        func respond(to request: StubRequest) -> StubReply {
            let handler: StubHandler = state.withLock { state in
                state.requests.append(request)
                return state.handler
            }
            return handler(request)
        }

        var requests: [StubRequest] {
            state.withLock { $0.requests }
        }
    }

    /// Faux réseau des tests du client : répond selon le gestionnaire de `StubServer`.
    final class StubURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let seen = StubRequest(
                method: request.httpMethod ?? "GET",
                url: url,
                headers: request.allHTTPHeaderFields ?? [:],
                body: Self.body(of: request)
            )
            let reply = StubServer.shared.respond(to: seen)
            if let failure = reply.failure {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            var headers = reply.headers
            if headers["Content-Type"] == nil {
                headers["Content-Type"] = "application/json; charset=utf-8"
            }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func body(of request: URLRequest) -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    /// Rotation simulée : mémorise les jetons refusés, répond avec `freshToken` (`nil` = session perdue).
    actor RefreshRecorder {
        private(set) var failedTokens: [String] = []
        private let freshToken: String?

        init(freshToken: String?) {
            self.freshToken = freshToken
        }

        func refresh(_ failedToken: String) -> String? {
            failedTokens.append(failedToken)
            return freshToken
        }
    }
}
