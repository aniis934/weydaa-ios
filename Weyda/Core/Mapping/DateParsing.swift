import Foundation

/// Dates de l'API : ISO 8601 en UTC, avec ou sans millisecondes (`2026-09-07T12:12:43.698Z`, `…T12:12:43Z`),
/// équivalent de `parseInstant` (data/mapper/Mappers.kt). Les DTO gardent les dates en texte, les mappers les
/// convertissent ici. `ISO8601DateFormatter` n'est pas `Sendable` : il est créé à chaque appel, jamais partagé.
nonisolated enum DateParsing {
    /// Date lue, ou `nil` si absente, vide ou illisible (comme `runCatching { Instant.parse(it) }.getOrNull()`).
    static func parseInstant(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        guard raw.firstIndex(of: ".") != nil else {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        // Fraction inhabituelle (microsecondes…) : on la retire plutôt que de perdre la date.
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: withoutFraction(raw))
    }

    /// ISO 8601 UTC avec millisecondes, la forme du serveur (stockage local).
    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// `…T12:12:43.698123Z` → `…T12:12:43Z`.
    private static func withoutFraction(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        var end = raw.index(after: dot)
        while end < raw.endIndex, raw[end].isASCII, raw[end].isNumber {
            end = raw.index(after: end)
        }
        return String(raw[..<dot]) + String(raw[end...])
    }
}
