import Foundation

// Lecture tolérante des réponses de l'API, équivalent de la configuration `WeydaJson` d'Android
// (`ignoreUnknownKeys`, `coerceInputValues`, `isLenient`) : clé inconnue ignorée, champ absent ou `null`
// → valeur par défaut d'Android, nombre reçu en texte (`"1500"`) accepté, texte reçu en nombre accepté.
// Les DTO écrivent leur `init(from:)` à la main (dans une extension, pour garder l'initialiseur membre à
// membre) avec ces aides et des clés littérales : `container.lenientString("slug")`.

/// Clé de décodage libre (littéral texte), utilisée par tous les `init(from:)` écrits à la main.
nonisolated struct DTOKey: CodingKey, Hashable, Sendable, ExpressibleByStringLiteral {
    let stringValue: String
    let intValue: Int?

    init(_ name: String) {
        stringValue = name
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    init(stringLiteral value: String) {
        self.init(value)
    }
}

/// Élément de tableau décodé « sans casse » : un élément illisible donne `nil` au lieu de faire échouer
/// tout le tableau (Android, plus strict, rejetait alors toute la réponse).
nonisolated struct DTOLossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// Tableau JSON nu (`GET /api/categories`, `/api/wilayas`, `/api/favorites`) décodé sans casse :
/// `try decoder.decode(DTOLossyList<CategoryDTO>.self, from: data).items`.
nonisolated struct DTOLossyList<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let elements = try container.decode([DTOLossy<Element>].self)
        items = elements.compactMap { $0.value }
    }
}

nonisolated extension DTOLossyList: Sendable where Element: Sendable {}

nonisolated extension KeyedDecodingContainer where K == DTOKey {
    /// Valeur JSON brute ; `nil` si la clé est absente ou vaut `null`.
    func lenientJSON(_ key: DTOKey) -> JSONValue? {
        try? decodeIfPresent(JSONValue.self, forKey: key)
    }

    /// Texte ; un nombre ou un booléen est converti en texte (`isLenient`). Objet, tableau, `null` → `nil`.
    func lenientString(_ key: DTOKey) -> String? {
        do {
            return try decodeIfPresent(String.self, forKey: key)
        } catch {
            return lenientJSON(key)?.textValue
        }
    }

    /// Entier ; accepte `12.0` et `"12"`. Illisible → `nil` (le DTO applique alors le défaut d'Android).
    func lenientInt(_ key: DTOKey) -> Int? {
        do {
            return try decodeIfPresent(Int.self, forKey: key)
        } catch {
            return lenientJSON(key)?.intValue
        }
    }

    /// Nombre ; accepte le texte numérique (`"45000"`), comme le prix d'un ancien serveur.
    func lenientDouble(_ key: DTOKey) -> Double? {
        do {
            return try decodeIfPresent(Double.self, forKey: key)
        } catch {
            return lenientJSON(key)?.doubleValue
        }
    }

    /// Booléen ; accepte `"true"` / `"false"`.
    func lenientBool(_ key: DTOKey) -> Bool? {
        do {
            return try decodeIfPresent(Bool.self, forKey: key)
        } catch {
            return lenientJSON(key)?.boolValue
        }
    }

    /// Objet imbriqué ; absent, `null` ou illisible → `nil`.
    func lenientObject<T: Decodable>(_ type: T.Type, _ key: DTOKey) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// Tableau d'objets ; absent ou `null` → `[]`, élément illisible ignoré.
    func lenientList<T: Decodable>(_ type: T.Type, _ key: DTOKey) -> [T] {
        guard let elements = try? decodeIfPresent([DTOLossy<T>].self, forKey: key) else { return [] }
        return elements.compactMap { $0.value }
    }

    /// Tableau de textes (nombres convertis) ; absent → `[]`.
    func lenientStringList(_ key: DTOKey) -> [String] {
        guard let elements = lenientJSON(key)?.arrayValue else { return [] }
        return elements.compactMap { $0.textValue }
    }

    /// Tableau de nombres (textes numériques acceptés) ; absent → `[]`.
    func lenientDoubleList(_ key: DTOKey) -> [Double] {
        guard let elements = lenientJSON(key)?.arrayValue else { return [] }
        return elements.compactMap { $0.doubleValue }
    }

    /// Objet `{ clé: texte }` ; valeurs `null`, objets ou tableaux ignorés. Absent → `nil`.
    func lenientStringMap(_ key: DTOKey) -> [String: String]? {
        guard let object = lenientJSON(key)?.objectValue else { return nil }
        return object.compactMapValues { $0.textValue }
    }

    /// Date du stockage local : nombre = secondes depuis la date de référence d'Apple (2001, comme `Date`
    /// elle-même : aller-retour exact), texte = date ISO 8601 (forme du serveur). Absente ou illisible → `nil`.
    func lenientStoredDate(_ key: DTOKey) -> Date? {
        if let seconds = lenientDouble(key) {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return DateParsing.parseInstant(lenientString(key))
    }

    /// Texte obligatoire (champ Kotlin sans valeur par défaut) : absent ou `null` → erreur de décodage.
    func requiredString(_ key: DTOKey) throws -> String {
        guard let value = lenientString(key) else { throw missing(key) }
        return value
    }

    /// Entier obligatoire : absent, `null` ou illisible → erreur de décodage.
    func requiredInt(_ key: DTOKey) throws -> Int {
        guard let value = lenientInt(key) else { throw missing(key) }
        return value
    }

    /// Nombre obligatoire : absent, `null` ou illisible → erreur de décodage.
    func requiredDouble(_ key: DTOKey) throws -> Double {
        guard let value = lenientDouble(key) else { throw missing(key) }
        return value
    }

    private func missing(_ key: DTOKey) -> DecodingError {
        DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Champ obligatoire absent : \(key.stringValue)")
        )
    }
}
