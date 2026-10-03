import Foundation

/// Client HTTP de l'API Weyda — équivalent d'OkHttp + Retrofit (Android : `AppContainer.kt`,
/// `AuthInterceptor.kt`, `SafeCall.kt`). Sans état modifiable : utilisable depuis n'importe quel fil.
///
/// - En-têtes communs : `User-Agent: WeydaIOS/<version>`, `Accept: application/json`,
///   `Accept-Language: <langue de l'app>` (le serveur en déduit la langue des e-mails et des push).
/// - Bearer de la session UNIQUEMENT vers l'hôte de l'API, et jamais sur `/api/auth/token*`.
/// - 401 sur une requête partie avec un Bearer → rotation des jetons (partagée, dans la session), puis
///   UN seul rejeu avec le nouveau jeton (`TokenAuthenticator`).
/// - Réponse non 2xx → `APIError` ; erreur de transport → `URLError` inchangée (hors ligne, délai…) ;
///   JSON illisible → `DecodingError`. L'annulation remonte en `URLError.cancelled` / `CancellationError`.
/// - Réseau ET décodage hors du fil principal (`@concurrent`).
nonisolated final class APIClient: Sendable {
    /// `User-Agent` de l'app : `WeydaIOS/<CFBundleShortVersionString>` (Android : `WeydaAndroid/<version>`).
    static let defaultUserAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "WeydaIOS/\(version ?? "1.0")"
    }()

    let baseURL: URL
    private let session: URLSession
    private let authorization: APIAuthorization
    private let language: String
    private let userAgent: String

    /// - Parameters:
    ///   - baseURL: `AppConfig.apiBaseURL` (`https://weydaa.com/`).
    ///   - session: `AppContainer.apiSession` (cookies coupés ; API simulée en Debug).
    ///   - authorization: `.none` (client des jetons) ou `SessionManager.authorization`.
    init(
        baseURL: URL,
        session: URLSession,
        authorization: APIAuthorization = .none,
        language: String = WeydaLocale.language,
        userAgent: String = APIClient.defaultUserAgent
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authorization = authorization
        self.language = language
        self.userAgent = userAgent
    }

    // MARK: - API publique

    /// Envoie la requête et décode la réponse JSON (2xx).
    @concurrent
    func send<Response: Decodable & Sendable>(
        _ request: APIRequest,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await exchange(request)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Envoie la requête sans lire la réponse (`{ success: true }`, 204, corps vide…).
    @concurrent
    func perform(_ request: APIRequest) async throws {
        _ = try await exchange(request)
    }

    /// Corps brut d'une réponse 2xx (formats que le décodage commun ne couvre pas).
    @concurrent
    func data(for request: APIRequest) async throws -> Data {
        try await exchange(request)
    }

    /// Téléchargement vers un fichier (export RGPD `GET api/users/me/export`). Renvoie `destination`, ou à
    /// défaut un fichier unique du dossier temporaire : à déplacer ou effacer par l'appelant. Non 2xx →
    /// `APIError` (429 + `Retry-After` : 2 exports / 24 h), aucun fichier laissé.
    @concurrent
    func download(_ request: APIRequest, to destination: URL? = nil) async throws -> URL {
        let prepared = try await prepare(request)
        var urlRequest = prepared.urlRequest
        var (location, response) = try await loadFile(urlRequest)
        if let fresh = await replayToken(after: response, sentBearer: prepared.bearer) {
            Self.removeFile(at: location)
            urlRequest.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            (location, response) = try await loadFile(urlRequest)
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? Data(contentsOf: location)
            Self.removeFile(at: location)
            throw APIError(response: response, body: body)
        }
        let target = destination ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("weyda-download-\(UUID().uuidString)", isDirectory: false)
        do {
            let files = FileManager.default
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: target.path) {
                try files.removeItem(at: target)
            }
            try files.moveItem(at: location, to: target)
        } catch {
            Self.removeFile(at: location)
            throw error
        }
        return target
    }

    // MARK: - Échange

    /// Bearer, envoi, rotation + rejeu unique sur 401, statut → `APIError`. Renvoie le corps (2xx).
    private func exchange(_ request: APIRequest) async throws -> Data {
        let prepared = try await prepare(request)
        var urlRequest = prepared.urlRequest
        var (data, response) = try await loadData(urlRequest)
        if let fresh = await replayToken(after: response, sentBearer: prepared.bearer) {
            urlRequest.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            (data, response) = try await loadData(urlRequest)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError(response: response, body: data)
        }
        return data
    }

    /// Requête prête à partir, et le jeton joint (`nil` = partie sans Bearer, donc jamais rejouée).
    private func prepare(_ request: APIRequest) async throws -> (urlRequest: URLRequest, bearer: String?) {
        let url = try request.url(relativeTo: baseURL)
        var bearer: String?
        if request.authenticated, Self.mayCarryBearer(url, apiHost: baseURL.host) {
            bearer = await authorization.accessToken()
        }
        let urlRequest = try makeURLRequest(request, url: url, bearer: bearer)
        return (urlRequest, bearer)
    }

    /// Nouveau jeton pour rejouer une requête refusée (401), seulement si elle portait un Bearer.
    private func replayToken(after response: HTTPURLResponse, sentBearer: String?) async -> String? {
        guard response.statusCode == 401, let sentBearer else { return nil }
        return await authorization.refreshAfterUnauthorized(sentBearer)
    }

    private func loadData(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func loadFile(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (location, response) = try await session.download(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            Self.removeFile(at: location)
            throw URLError(.badServerResponse)
        }
        return (location, http)
    }

    // MARK: - Construction

    private func makeURLRequest(_ request: APIRequest, url: URL, bearer: String?) throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(language, forHTTPHeaderField: "Accept-Language")
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        switch request.body {
        case .empty:
            break
        case .json(let value):
            urlRequest.httpBody = try Self.encodeJSON(value)
            urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        case .rawJSON(let data):
            urlRequest.httpBody = data
            urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        case .multipart(let file):
            let boundary = "WeydaBoundary-\(UUID().uuidString)"
            urlRequest.httpBody = Self.multipartBody(file, boundary: boundary)
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    /// Garde-fou d'`AuthInterceptor` : hôte de l'API seulement (une URL absolue vers un stockage ou un CDN
    /// n'emporte jamais le jeton), et jamais les routes d'émission / rotation de jetons.
    static func mayCarryBearer(_ url: URL, apiHost: String?) -> Bool {
        guard let host = url.host?.lowercased(), let apiHost = apiHost?.lowercased(), host == apiHost else {
            return false
        }
        return !url.path.hasPrefix("/api/auth/token")
    }

    private static func encodeJSON(_ value: any Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func multipartBody(_ file: MultipartFile, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        let disposition = "form-data; name=\"\(headerSafe(file.fieldName))\"; filename=\"\(headerSafe(file.fileName))\""
        body.append(Data("Content-Disposition: \(disposition)\r\n".utf8))
        body.append(Data("Content-Type: \(headerSafe(file.mimeType))\r\n\r\n".utf8))
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// Guillemets et retours à la ligne neutralisés dans une valeur d'en-tête multipart.
    private static func headerSafe(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private static func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
