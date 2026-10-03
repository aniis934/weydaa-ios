#if DEBUG
import Foundation

/// API simulée (Debug seulement) : répond avec les fichiers de `MockFixtures/` au lieu du réseau.
/// Activée par `-WeydaMockAPI YES` (tour de captures, tests d'interface) : la prod n'est jamais
/// touchée et chaque capture est reproductible. Sert aussi les photos des annonces fictives
/// (dessinées par `MockPhotos`), pour la session d'images comme pour celle de l'API.
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
        let reply = MockRoutes.shared.reply(method: request.httpMethod ?? "GET", url: url)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": reply.contentType]
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

/// Réponse simulée : statut, corps et type de contenu.
nonisolated struct MockReply: Sendable {
    let status: Int
    let body: Data
    let contentType: String
}

/// Une route simulée, lue dans `MockFixtures/routes*.json` :
///   - `path` : chemin exact, `*` = un segment quelconque, `**` final = tout le reste ;
///   - `host` (facultatif) : hôte exact ; `query` (facultatif) : paramètres qui doivent avoir CES valeurs ;
///   - `fixture` : fichier de réponse (sous-dossiers permis), `status` : 200 par défaut ;
///   - `photo` : vrai = image fictive dessinée d'après le nom du fichier demandé (`MockPhotos`).
/// Quand plusieurs routes conviennent, la plus précise gagne (segments littéraux, puis contraintes de requête).
nonisolated struct MockRoute: Decodable, Sendable {
    let method: String
    let path: String
    let host: String?
    let query: [String: String]?
    let fixture: String?
    let status: Int?
    let photo: Bool?

    var specificity: Int {
        let literal = path.split(separator: "/").filter { $0 != "*" && $0 != "**" }.count
        return literal * 100 + (query?.count ?? 0)
    }

    func matches(method: String, host: String?, segments: [Substring], query: [String: String]) -> Bool {
        guard self.method.uppercased() == method.uppercased() else { return false }
        if let expectedHost = self.host, expectedHost != host { return false }
        guard Self.pathMatches(pattern: path.split(separator: "/"), segments: segments) else { return false }
        for (key, value) in self.query ?? [:] where query[key] != value {
            return false
        }
        return true
    }

    private static func pathMatches(pattern: [Substring], segments: [Substring]) -> Bool {
        for (index, part) in pattern.enumerated() {
            if part == "**" { return index == pattern.count - 1 }
            guard index < segments.count else { return false }
            if part != "*" && part != segments[index] { return false }
        }
        return pattern.count == segments.count
    }
}

/// Table des routes, lue une fois dans tous les fichiers `MockFixtures/routes*.json` (un fichier par
/// domaine : catalogue, annonces, compte… — plusieurs personnes peuvent en ajouter sans conflit).
nonisolated final class MockRoutes: Sendable {
    static let shared = MockRoutes(bundle: .main)

    static let directory = "MockFixtures"
    private static let notFound = Data(#"{"error":"notFound"}"#.utf8)
    private static let json = "application/json; charset=utf-8"

    private let routes: [MockRoute]
    private let root: URL?

    convenience init(bundle: Bundle) {
        let files = (bundle.urls(forResourcesWithExtension: "json", subdirectory: Self.directory) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("routes") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        var routes: [MockRoute] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let decoded = try? decoder.decode([MockRoute].self, from: data) else { continue }
            routes.append(contentsOf: decoded)
        }
        self.init(routes: routes, root: bundle.resourceURL?.appendingPathComponent(Self.directory, isDirectory: true))
    }

    init(routes: [MockRoute], root: URL?) {
        self.routes = routes
        self.root = root
    }

    /// Nombre de routes chargées (tests).
    var count: Int { routes.count }

    /// Réponse pour une requête ; route inconnue → 404 `{ "error": "notFound" }` (comme l'API).
    func reply(method: String, url: URL) -> MockReply {
        let segments = url.path.split(separator: "/")
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        let candidates = routes.filter { $0.matches(method: method, host: url.host, segments: segments, query: query) }
        guard let route = candidates.max(by: { $0.specificity < $1.specificity }) else {
            return MockReply(status: 404, body: Self.notFound, contentType: Self.json)
        }
        let status = route.status ?? 200
        if route.photo == true {
            return MockReply(status: status, body: MockPhotos.jpeg(named: url.lastPathComponent), contentType: "image/jpeg")
        }
        guard let fixture = route.fixture, let root else {
            return MockReply(status: status, body: Data(), contentType: Self.json)
        }
        let body = (try? Data(contentsOf: root.appendingPathComponent(fixture))) ?? Data()
        return MockReply(status: status, body: body, contentType: Self.contentType(of: fixture))
    }

    /// Compatibilité phase 0 : chemin seul, sans requête ni hôte.
    func reply(method: String, path: String) -> (status: Int, body: Data) {
        let url = URL(string: "https://weydaa.com\(path)") ?? URL(fileURLWithPath: path)
        let reply = reply(method: method, url: url)
        return (reply.status, reply.body)
    }

    private static func contentType(of fixture: String) -> String {
        switch (fixture as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "webp": "image/webp"
        case "json": json
        default: "application/octet-stream"
        }
    }
}
#endif
