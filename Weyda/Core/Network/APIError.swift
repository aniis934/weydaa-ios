import Foundation

/// Erreur HTTP normalisée de l'API Weyda (`{ "error": "cleI18n", … }`) — portage d'`ApiException`
/// (Android). Produite par `APIClient` pour toute réponse non 2xx ; traduite par `ErrorMapper`.
nonisolated struct APIError: Error, Sendable, Equatable {
    let status: Int
    /// Clé i18n renvoyée par le serveur (`unauthorized`, `invalidCredentials`, `emailNotVerified`…).
    let code: String
    /// Délai imposé : `retryAfter` du corps, sinon en-tête `Retry-After` (secondes).
    let retryAfterSeconds: Int?
    /// Essais restants après `incorrectCode` (code de vérification de l'e-mail).
    let remainingAttempts: Int?
    /// Erreurs Zod par champ : nom du champ → première clé `validation.*`.
    let fieldErrors: [String: String]
    /// Attributs de catégorie refusés : clé → code (`required`, `below_min`…).
    let attributeErrors: [String: String]
    /// `maxImagesExceeded` : plafond de photos du compte (Android : `body?.maxImages`).
    let maxImages: Int?
    /// `offerAlreadyOpen` : conversation où l'offre est déjà ouverte (Android : `body?.conversationId`).
    let conversationId: String?

    init(
        status: Int,
        code: String,
        retryAfterSeconds: Int? = nil,
        remainingAttempts: Int? = nil,
        fieldErrors: [String: String] = [:],
        attributeErrors: [String: String] = [:],
        maxImages: Int? = nil,
        conversationId: String? = nil
    ) {
        self.status = status
        self.code = code
        self.retryAfterSeconds = retryAfterSeconds
        self.remainingAttempts = remainingAttempts
        self.fieldErrors = fieldErrors
        self.attributeErrors = attributeErrors
        self.maxImages = maxImages
        self.conversationId = conversationId
    }

    var isUnauthorized: Bool { status == 401 }

    var isEmailNotVerified: Bool { status == 403 && code == "emailNotVerified" }
}

// MARK: - Décodage d'une réponse d'erreur

nonisolated extension APIError {
    /// Réponse non 2xx : corps JSON de l'API s'il est lisible (lecture champ par champ, tolérante),
    /// sinon code par défaut selon le statut (`toApiException` sur Android).
    init(status: Int, body: Data?, retryAfterHeader: String? = nil) {
        var root: [String: Any] = [:]
        if let body, !body.isEmpty,
           let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            root = object
        }
        var attributes: [String: String] = [:]
        for (key, value) in root["attributeErrors"] as? [String: Any] ?? [:] {
            if let text = value as? String { attributes[key] = text }
        }
        let serverCode = (root["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let headerDelay = retryAfterHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        self.init(
            status: status,
            code: serverCode ?? Self.defaultCode(for: status),
            retryAfterSeconds: Self.intValue(root["retryAfter"]) ?? headerDelay,
            remainingAttempts: Self.intValue(root["remainingAttempts"]),
            fieldErrors: Self.parseFieldErrors(root["details"]),
            attributeErrors: attributes,
            maxImages: Self.intValue(root["maxImages"]),
            conversationId: root["conversationId"] as? String
        )
    }

    init(response: HTTPURLResponse, body: Data?) {
        self.init(
            status: response.statusCode,
            body: body,
            retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After")
        )
    }

    /// Code quand le corps ne dit rien (vide, HTML d'un proxy…) — `defaultCode` Android.
    static func defaultCode(for status: Int) -> String {
        switch status {
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 404: return "notFound"
        case 429: return "rateLimited"
        default: return "serverError"
        }
    }

    /// `{ fieldErrors: { email: ["validation.emailInvalid"] } }` → `["email": "validation.emailInvalid"]`.
    /// Deux formes côté serveur : `details = flatten()` (l'objet ci-dessus) pour la plupart des routes, et
    /// `details = flatten().fieldErrors` (la map directement) pour `PUT /api/annonces/{id}` et
    /// `POST /api/saved-searches` — sans la seconde, une édition refusée ne désignait jamais le champ fautif.
    static func parseFieldErrors(_ details: Any?) -> [String: String] {
        guard let root = details as? [String: Any] else { return [:] }
        let fields = root["fieldErrors"] as? [String: Any] ?? root
        var result: [String: String] = [:]
        for (field, messages) in fields {
            let first: Any
            if let list = messages as? [Any] {
                guard let head = list.first else { continue }
                first = head
            } else {
                first = messages
            }
            if let text = first as? String {
                result[field] = text
            } else if let number = first as? NSNumber {
                result[field] = number.stringValue
            }
        }
        return result
    }

    /// Entier JSON tolérant : nombre, ou chaîne numérique (`isLenient` sur Android).
    private static func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(exactly: number.rounded()) }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
