#if DEBUG
import Foundation

/// API simulée (Debug seulement) : répond avec les fichiers de `MockFixtures/` au lieu du réseau.
/// Activée par `-WeydaMockAPI YES` (tour de captures, tests d'interface) : la prod n'est jamais
/// touchée et chaque capture est reproductible.
///
/// Dépôt PUBLIC : les fixtures sont FICTIVES (aucun nom, téléphone, e-mail ni photo d'un vrai
/// utilisateur). Le dossier est exclu des builds Release (EXCLUDED_SOURCE_FILE_NAMES).
nonisolated final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = MockRoutes.shared.reply(method: request.httpMethod ?? "GET", path: url.path)
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
}

/// Une route simulée : méthode + chemin exact → fichier de réponse (et statut HTTP).
nonisolated struct MockRoute: Decodable, Sendable {
    let method: String
    let path: String
    let fixture: String?
    let status: Int?
}

/// Table des routes, lue une fois dans `MockFixtures/routes.json`.
nonisolated final class MockRoutes: Sendable {
    static let shared = MockRoutes(bundle: .main)

    static let directory = "MockFixtures"
    private static let notFound = Data(#"{"error":"notFound"}"#.utf8)

    private let routes: [MockRoute]
    private let fixtures: [String: Data]

    init(bundle: Bundle) {
        let decoder = JSONDecoder()
        let routes = bundle.url(forResource: "routes", withExtension: "json", subdirectory: Self.directory)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decoder.decode([MockRoute].self, from: $0) } ?? []
        var fixtures: [String: Data] = [:]
        for route in routes {
            guard let name = route.fixture, fixtures[name] == nil else { continue }
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            if let url = bundle.url(forResource: base, withExtension: ext, subdirectory: Self.directory),
               let data = try? Data(contentsOf: url) {
                fixtures[name] = data
            }
        }
        self.routes = routes
        self.fixtures = fixtures
    }

    /// Réponse pour une requête ; route inconnue → 404 `{ "error": "notFound" }` (comme l'API).
    func reply(method: String, path: String) -> (status: Int, body: Data) {
        guard let route = routes.first(where: { $0.method == method.uppercased() && $0.path == path }) else {
            return (404, Self.notFound)
        }
        let body = route.fixture.flatMap { fixtures[$0] } ?? Data()
        return (route.status ?? 200, body)
    }
}
#endif
