import Foundation
import os
import XCTest
@testable import Weyda

/// `LiveWeydaAPI` contre un faux réseau (`RouteProtocol`) : chemins, paramètres, méthodes, Bearer présent ou absent,
/// corps (JSON, JSON brut, multipart), téléchargement. Hôte en `.test` (réservé, jamais résolu), données fictives.
final class LiveWeydaAPITests: XCTestCase {
    private static let base = "https://api.weydaa.test/"
    private static let token = #"{"accessToken":"a","refreshToken":"r","user":{"id":"u1"}}"#

    private func makeAPI(reply: @escaping RouteReplyHandler = { _ in .json(200, "{}") }) throws -> LiveWeydaAPI {
        RouteServer.shared.reset(reply)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RouteProtocol.self]
        let session = URLSession(configuration: configuration)
        let baseURL = try XCTUnwrap(URL(string: Self.base))
        let authorization = APIAuthorization(
            accessToken: { "access-1" },
            refreshAfterUnauthorized: { _ in nil }
        )
        let client = APIClient(baseURL: baseURL, session: session, authorization: authorization, language: "fr")
        let authClient = APIClient(baseURL: baseURL, session: session, language: "fr")
        return LiveWeydaAPI(client: client, authClient: authClient)
    }

    // MARK: - Recherche et catalogue

    func testSearchBuildsTheQueryAndCarriesTheBearer() async throws {
        let api = try makeAPI { _ in .json(200, #"{"annonces":[],"total":0,"page":1,"totalPages":1}"#) }
        _ = try await api.getAnnonces(
            q: "clio 4+",
            category: "vehicules",
            subcategory: nil,
            wilaya: 16,
            commune: nil,
            priceType: "FIXED",
            priceMin: 1500,
            priceMax: 12.5,
            sort: "newest",
            featured: 1,
            page: 2,
            limit: 24,
            locale: nil,
            withFacets: nil,
            attrs: ["attr_year_min": "2015", "attr_make": "renault"]
        )
        let request = try XCTUnwrap(RouteServer.shared.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.path, "/api/annonces")
        let query = request.query
        XCTAssertEqual(query["q"], "clio 4+")
        XCTAssertEqual(query["category"], "vehicules")
        XCTAssertEqual(query["wilaya"], "16")
        XCTAssertEqual(query["priceType"], "FIXED")
        XCTAssertEqual(query["priceMin"], "1500")
        XCTAssertEqual(query["priceMax"], "12.5")
        XCTAssertEqual(query["sort"], "newest")
        XCTAssertEqual(query["featured"], "1")
        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["limit"], "24")
        XCTAssertEqual(query["attr_make"], "renault")
        XCTAssertEqual(query["attr_year_min"], "2015")
        XCTAssertNil(query["subcategory"])
        XCTAssertNil(query["commune"])
        XCTAssertNil(query["locale"])
        XCTAssertNil(query["withFacets"])
        XCTAssertEqual(request.header("Authorization"), "Bearer access-1")
    }

    func testCatalogQueriesAndBareArraysDecodeWithoutBreaking() async throws {
        let api = try makeAPI { request in
            switch request.url.path {
            case "/api/categories":
                return .json(200, #"[{"id":"c1","slug":"vehicules","nameFr":"Véhicules"},{"slug":"sans-id"}]"#)
            case "/api/favorites":
                return .json(200, #"[{"id":"a1","title":"T","favoritedAt":"2026-09-07T12:00:00.000Z"}]"#)
            case "/api/wilayas":
                return .json(200, #"[{"id":16,"nameFr":"Alger","nameAr":"الجزائر","listingsCount":12}]"#)
            default:
                return .json(200, "{}")
            }
        }
        let categories = try await api.getCategories()
        XCTAssertEqual(categories.map { $0.slug }, ["vehicules"])
        let favorites = try await api.getFavorites()
        XCTAssertEqual(favorites.map { $0.id }, ["a1"])
        _ = try await api.getCommunes(wilayaId: 16)
        let top = try await api.getTopWilayas(top: 10)
        XCTAssertEqual(top.first?.listingsCount, 12)
        _ = try await api.getAttributes(slug: "vehicules", subcategory: "voitures", locale: "ar", context: ["ctx_make": "renault"])

        let requests = RouteServer.shared.requests
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests[2].query, ["wilayaId": "16"])
        XCTAssertEqual(requests[3].query, ["top": "10"])
        XCTAssertEqual(requests[4].url.path, "/api/categories/vehicules/attributes")
        XCTAssertEqual(requests[4].query, ["subcategory": "voitures", "locale": "ar", "ctx_make": "renault"])
    }

    // MARK: - Authentification

    func testAuthRoutesArePostsWithoutBearer() async throws {
        let api = try makeAPI { request in
            switch request.url.path {
            case "/api/auth/register":
                return .json(201, #"{"id":"u1"}"#)
            case "/api/auth/forgot-password", "/api/auth/reset-password":
                return .json(200, #"{"success":true}"#)
            default:
                return .json(200, LiveWeydaAPITests.token)
            }
        }
        _ = try await api.login(LoginRequestDTO(email: "test@example.com", password: "Secret123"))
        _ = try await api.refresh(RefreshRequestDTO(refreshToken: "r"))
        _ = try await api.loginWithGoogle(GoogleLoginRequestDTO(idToken: "g", locale: "ar"))
        _ = try await api.loginWithApple(AppleLoginRequestDTO(identityToken: "i", nonce: "n", locale: "en"))
        _ = try await api.register(RegisterRequestDTO(name: "Amina", email: "test@example.com", password: "Secret123"))
        _ = try await api.forgotPassword(ForgotPasswordRequestDTO(email: "test@example.com", locale: "fr"))
        _ = try await api.resetPassword(ResetPasswordRequestDTO(token: "t", password: "Secret123"))

        let requests = RouteServer.shared.requests
        XCTAssertEqual(requests.map { $0.url.path }, [
            "/api/auth/token",
            "/api/auth/token/refresh",
            "/api/auth/google",
            "/api/auth/apple",
            "/api/auth/register",
            "/api/auth/forgot-password",
            "/api/auth/reset-password",
        ])
        for request in requests {
            XCTAssertEqual(request.method, "POST")
            XCTAssertNil(request.header("Authorization"), request.url.path)
            XCTAssertEqual(request.header("Content-Type"), "application/json; charset=utf-8")
        }
        let apple = try XCTUnwrap(requests[3].jsonObject)
        XCTAssertEqual(apple["identityToken"] as? String, "i")
        XCTAssertEqual(apple["nonce"] as? String, "n")
        XCTAssertEqual(apple["locale"] as? String, "en")
        XCTAssertNil(apple["name"])
        XCTAssertNil(apple["authorizationCode"])
        let register = try XCTUnwrap(requests[4].jsonObject)
        XCTAssertNil(register["phone"])
    }

    func testEmailVerificationSendsAnEmptyObjectWithTheBearer() async throws {
        let api = try makeAPI { _ in .json(200, #"{"success":true,"expiresIn":600}"#) }
        let response = try await api.resendVerificationCode()
        XCTAssertEqual(response.expiresIn, 600)
        let request = try XCTUnwrap(RouteServer.shared.requests.first)
        XCTAssertEqual(request.url.path, "/api/email-verify")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "{}")
        XCTAssertEqual(request.header("Authorization"), "Bearer access-1")
    }

    // MARK: - Annonces

    func testEditSendsTheRawBodyWithExplicitNulls() async throws {
        let api = try makeAPI { _ in .json(200, #"{"id":"a1","title":"T"}"#) }
        let submission = ListingSubmission(title: "T", description: "d", price: nil, priceType: .free, categoryId: "c")
        let body = try submission.toUpdateBody()
        _ = try await api.editAnnonce(id: "a1", body: body)
        let request = try XCTUnwrap(RouteServer.shared.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.path, "/api/annonces/a1")
        XCTAssertEqual(request.header("Content-Type"), "application/json; charset=utf-8")
        let text = String(decoding: request.body, as: UTF8.self)
        XCTAssertTrue(text.contains(#""price":null"#), text)
        XCTAssertTrue(text.contains(#""wilayaId":null"#), text)
    }

    func testPathSegmentsAreEncodedAndBodilessRoutesHaveNoBody() async throws {
        let api = try makeAPI { request in
            request.url.path.hasSuffix("/view") ? .json(200, #"{"counted":true}"#) : .json(200, #"{"id":"a1","title":"T"}"#)
        }
        _ = try await api.getAnnonce(idOrSlug: "clio 4/ab")
        let counted = try await api.countView(id: "a1")
        XCTAssertTrue(counted.counted)

        let requests = RouteServer.shared.requests
        XCTAssertEqual(requests[0].url.absoluteString, "https://api.weydaa.test/api/annonces/clio%204%2Fab")
        XCTAssertEqual(requests[1].method, "POST")
        XCTAssertEqual(requests[1].url.path, "/api/annonces/a1/view")
        XCTAssertTrue(requests[1].body.isEmpty)
    }

    func testMessagingNotificationsAndAccountRoutes() async throws {
        let api = try makeAPI { _ in .json(200, #"{"success":true}"#) }
        _ = try await api.getConversations(cursor: "c2", limit: 20, archived: true)
        _ = try await api.archiveConversation(id: "c1")
        _ = try await api.unarchiveConversation(id: "c1")
        _ = try await api.deleteMessage(id: "c1", messageId: "m1")
        _ = try await api.getNotifications(page: 2, limit: 50)
        _ = try await api.markAllNotificationsRead()
        _ = try await api.deleteAccount(DeleteAccountRequestDTO(password: "Secret123"))
        _ = try await api.removeFavorite(annonceId: "a1")

        let requests = RouteServer.shared.requests
        XCTAssertEqual(requests.map { "\($0.method) \($0.url.path)" }, [
            "GET /api/conversations",
            "POST /api/conversations/c1/archive",
            "DELETE /api/conversations/c1/archive",
            "DELETE /api/conversations/c1/messages/m1",
            "GET /api/notifications",
            "PATCH /api/notifications",
            "DELETE /api/users/me/account",
            "DELETE /api/favorites/a1",
        ])
        XCTAssertEqual(requests[0].query, ["cursor": "c2", "limit": "20", "archived": "true"])
        XCTAssertEqual(requests[4].query, ["page": "2", "limit": "50"])
        XCTAssertTrue(requests[5].body.isEmpty)
        let deletion = try XCTUnwrap(requests[6].jsonObject)
        XCTAssertEqual(deletion["password"] as? String, "Secret123")
        XCTAssertNil(deletion["googleIdToken"])
    }

    func testUploadIsAMultipartFileField() async throws {
        let api = try makeAPI { _ in .json(200, #"{"url":"https://cdn.example.com/x.webp","publicId":"annonces/x.webp"}"#) }
        let uploaded = try await api.upload(MultipartFile(fileName: "photo.jpg", mimeType: "image/jpeg", data: Data("JPEG".utf8)))
        XCTAssertEqual(uploaded.publicId, "annonces/x.webp")
        let request = try XCTUnwrap(RouteServer.shared.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/upload")
        XCTAssertTrue(request.header("Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let text = String(decoding: request.body, as: UTF8.self)
        XCTAssertTrue(text.contains(#"name="file"; filename="photo.jpg""#), text)
        XCTAssertTrue(text.contains("JPEG"))
    }

    func testExportDownloadsIntoTheRequestedFile() async throws {
        let api = try makeAPI { _ in .json(200, #"{"user":{"id":"u1"}}"#) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("weyda-live-api-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("export.json")
        let file = try await api.exportData(to: target)
        XCTAssertEqual(file, target)
        XCTAssertEqual(try Data(contentsOf: file), Data(#"{"user":{"id":"u1"}}"#.utf8))
        XCTAssertEqual(RouteServer.shared.requests.first?.url.path, "/api/users/me/export")
    }
}

extension LiveWeydaAPITests {
    typealias RouteReplyHandler = @Sendable (RouteRequest) -> RouteReply

    /// Requête vue par le faux serveur (corps relu depuis le flux : URLSession ne transmet pas `httpBody`).
    struct RouteRequest: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        /// Paramètres de la requête, décodés.
        var query: [String: String] {
            var result: [String: String] = [:]
            for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                result[item.name] = item.value ?? ""
            }
            return result
        }

        /// Corps JSON relu en dictionnaire (assertions sur les clés présentes ou omises).
        var jsonObject: [String: Any]? {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    struct RouteReply: Sendable {
        var status: Int
        var body: Data

        static func json(_ status: Int, _ body: String) -> RouteReply {
            RouteReply(status: status, body: Data(body.utf8))
        }
    }

    /// État du faux serveur, partagé avec `RouteProtocol` (instancié par URLSession sur ses propres fils) : protégé
    /// par un verrou. Les tests de la classe s'exécutent l'un après l'autre ; chacun le réinitialise.
    final class RouteServer: Sendable {
        static let shared = RouteServer()

        private struct State: Sendable {
            var handler: RouteReplyHandler = { _ in RouteReply(status: 404, body: Data()) }
            var requests: [RouteRequest] = []
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        func reset(_ handler: @escaping RouteReplyHandler) {
            state.withLock { $0 = State(handler: handler) }
        }

        func respond(to request: RouteRequest) -> RouteReply {
            let handler: RouteReplyHandler = state.withLock { state in
                state.requests.append(request)
                return state.handler
            }
            return handler(request)
        }

        var requests: [RouteRequest] {
            state.withLock { $0.requests }
        }
    }

    /// Faux réseau des tests de `LiveWeydaAPI` : répond selon le gestionnaire de `RouteServer`.
    final class RouteProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let seen = RouteRequest(
                method: request.httpMethod ?? "GET",
                url: url,
                headers: request.allHTTPHeaderFields ?? [:],
                body: Self.body(of: request)
            )
            let reply = RouteServer.shared.respond(to: seen)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=utf-8"]
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
}
