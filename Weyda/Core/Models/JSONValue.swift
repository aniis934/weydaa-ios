import Foundation

/// Valeur JSON libre, équivalent du `JsonElement` de kotlinx.serialization (Android) : champs sans schéma
/// fixe (`attributes` d'une annonce, `metadata` d'un message ou d'une notification, `details` d'une erreur
/// Zod). Un `[String: Any]` ne serait pas `Sendable` : on garde une énumération de valeurs.
///
/// Les nombres sont des `Double` (comme `JSON.parse` côté serveur). À l'encodage, un nombre entier s'écrit
/// sans décimale (`2015`, pas `2015.0`), comme `JsonPrimitive(n.toLong())` sur Android.
nonisolated enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

nonisolated extension JSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Ordre voulu : un booléen n'est jamais lu comme nombre (ni l'inverse) par JSONDecoder.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Valeur JSON illisible")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            if let integer = Int64(exactly: value) {
                try container.encode(integer)
            } else if value.isFinite {
                try container.encode(value)
            } else {
                // JSON n'a ni NaN ni infini : `null` plutôt qu'un échec d'encodage.
                try container.encodeNil()
            }
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }
}

nonisolated extension JSONValue {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Contenu textuel d'une valeur simple, comme `JsonPrimitive.contentOrNull` : texte tel quel, nombre écrit
    /// (`2015`, `1200.5`), booléen `true`/`false` ; `nil` pour `null`, un objet ou un tableau.
    var textValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return Self.text(of: value)
        case .bool(let value): return value ? "true" : "false"
        case .null, .array, .object: return nil
        }
    }

    /// Texte seulement (pas de conversion d'un nombre ou d'un booléen).
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Nombre, ou texte numérique (`"1500"`), comme `JsonPrimitive.doubleOrNull`.
    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else { return nil }
            return number
        case .null, .bool, .array, .object:
            return nil
        }
    }

    /// Entier exact (`12` ou `12.0`, `"12"`) ; `nil` pour `12.5`.
    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(exactly: value)
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if let integer = Int(trimmed) { return integer }
            return Double(trimmed).flatMap { Int(exactly: $0) }
        case .null, .bool, .array, .object:
            return nil
        }
    }

    /// Booléen, ou texte `"true"` / `"false"` (mode `isLenient` d'Android).
    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            if value == "true" { return true }
            if value == "false" { return false }
            return nil
        case .null, .number, .array, .object:
            return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let values) = self { return values }
        return nil
    }

    /// Champ d'un objet (`nil` si absent ou si la valeur n'est pas un objet).
    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Écriture d'un nombre JSON : entier sans décimale, sinon la forme la plus courte (`1200.5`).
    static func text(of number: Double) -> String {
        if let integer = Int64(exactly: number) { return String(integer) }
        return String(number)
    }
}

// Littéraux : `let body: JSONValue = ["price": 1200, "tags": ["a", "b"]]` (tests et corps de requête).
nonisolated extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

nonisolated extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

nonisolated extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) {
        self = .number(value)
    }
}

nonisolated extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

nonisolated extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

nonisolated extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        var object: [String: JSONValue] = [:]
        for (key, value) in elements {
            object[key] = value
        }
        self = .object(object)
    }
}
