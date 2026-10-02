import Foundation

/// Paramètre de requête (`?nom=valeur`). Type propre plutôt qu'`URLQueryItem` : la requête reste
/// `Sendable` quel que soit le SDK.
nonisolated struct APIQueryItem: Hashable, Sendable {
    let name: String
    let value: String

    init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

/// Fichier d'un envoi multipart/form-data (`POST api/upload` : champ `file`, ≤ 5 Mo, jpeg/png/webp/gif).
nonisolated struct MultipartFile: Hashable, Sendable {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data

    init(fieldName: String = "file", fileName: String, mimeType: String, data: Data) {
        self.fieldName = fieldName
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

/// Corps d'une requête.
nonisolated enum APIBody: Sendable {
    /// Aucun corps.
    case empty
    /// Valeur encodée en JSON au moment de l'envoi (hors du fil principal). Les optionnels `nil` sont
    /// omis, comme `explicitNulls = false` sur Android.
    case json(any Encodable & Sendable)
    /// JSON déjà encodé : quand il faut des `null` EXPLICITES (édition complète d'une annonce, Android
    /// `editAnnonce` : le serveur ne touche qu'aux champs présents).
    case rawJSON(Data)
    /// multipart/form-data, un seul fichier.
    case multipart(MultipartFile)
}

/// Requête vers l'API Weyda, indépendante d'URLSession (équivalent d'une méthode Retrofit de `WeydaApi.kt`).
nonisolated struct APIRequest: Sendable {
    var method: HTTPMethod
    /// Chemin RELATIF à `AppConfig.apiBaseURL`, sans barre initiale : `api/annonces`, `api/users/me`…
    /// Segments variables encodés par `APIRequest.segment(_:)`. Une URL absolue est acceptée, mais elle ne
    /// reçoit jamais de Bearer hors de l'hôte de l'API.
    var path: String
    var query: [APIQueryItem]
    var body: APIBody
    /// Vrai = Bearer de la session joint s'il y en a une. Sans effet sur un client sans autorisation
    /// (`AppContainer.authClient`) ni sur `/api/auth/token*` (jamais de Bearer, comme `AuthInterceptor`).
    var authenticated: Bool

    init(
        _ method: HTTPMethod,
        _ path: String,
        query: [APIQueryItem] = [],
        body: APIBody = .empty,
        authenticated: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.authenticated = authenticated
    }
}

// MARK: - Fabriques

nonisolated extension APIRequest {
    static func get(_ path: String, query: [APIQueryItem] = []) -> APIRequest {
        APIRequest(.get, path, query: query)
    }

    /// POST sans corps (vue d'une annonce, archivage, blocage…).
    static func post(_ path: String) -> APIRequest {
        APIRequest(.post, path)
    }

    static func post(_ path: String, json body: some Encodable & Sendable) -> APIRequest {
        APIRequest(.post, path, body: .json(body))
    }

    static func put(_ path: String, json body: some Encodable & Sendable) -> APIRequest {
        APIRequest(.put, path, body: .json(body))
    }

    /// PATCH sans corps (`api/notifications` : tout marquer comme lu).
    static func patch(_ path: String) -> APIRequest {
        APIRequest(.patch, path)
    }

    static func patch(_ path: String, json body: some Encodable & Sendable) -> APIRequest {
        APIRequest(.patch, path, body: .json(body))
    }

    static func delete(_ path: String, query: [APIQueryItem] = []) -> APIRequest {
        APIRequest(.delete, path, query: query)
    }

    /// DELETE AVEC corps (`api/users/me/account`, `api/push/fcm`) : `@HTTP(hasBody = true)` sur Android.
    static func delete(_ path: String, json body: some Encodable & Sendable) -> APIRequest {
        APIRequest(.delete, path, body: .json(body))
    }

    /// Envoi d'une image (`POST api/upload`, multipart, champ `file`).
    static func upload(_ file: MultipartFile, path: String = "api/upload") -> APIRequest {
        APIRequest(.post, path, body: .multipart(file))
    }
}

// MARK: - Paramètres et chemin

nonisolated extension APIRequest {
    /// Ajoute `?name=value` ; `nil` = paramètre omis (comme `@Query` de Retrofit).
    mutating func addQuery(_ name: String, _ value: String?) {
        guard let value else { return }
        query.append(APIQueryItem(name, value))
    }

    mutating func addQuery(_ name: String, _ value: Int?) {
        addQuery(name, value.map { String($0) })
    }

    /// Entier sans décimale (« 1500 »), sinon notation décimale à point, indépendante de la langue.
    mutating func addQuery(_ name: String, _ value: Double?) {
        addQuery(name, value.map { Self.queryValue($0) })
    }

    /// `true` / `false`, comme Retrofit.
    mutating func addQuery(_ name: String, _ value: Bool?) {
        addQuery(name, value.map { $0 ? "true" : "false" })
    }

    static func queryValue(_ value: Double) -> String {
        if value.rounded() == value, let integer = Int(exactly: value) {
            return String(integer)
        }
        return String(value)
    }

    /// Segment de chemin encodé (identifiant, slug avec espaces ou lettres arabes…) :
    /// `"api/annonces/" + APIRequest.segment(slug)`. La barre oblique est encodée elle aussi.
    static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// URL complète. `+` est encodé dans les paramètres (URLComponents le laisse tel quel, et le serveur le
    /// lirait comme une espace ; Retrofit l'encode).
    func url(relativeTo baseURL: URL) throws -> URL {
        guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            let items = query.map { URLQueryItem(name: $0.name, value: $0.value) }
            components.queryItems = (components.queryItems ?? []) + items
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
