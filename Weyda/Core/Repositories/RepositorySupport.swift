import Foundation

/// Petites règles communes des repositories (bornes de pagination, longueurs du serveur).
nonisolated enum RepositorySupport {
    /// `coerceIn(lower, upper)` de Kotlin : bornes de `limit` acceptées par le serveur (au-delà → 400).
    static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        Swift.min(Swift.max(value, lower), upper)
    }

    /// Texte coupé à `max` unités UTF-16 — la longueur que comptent Zod (serveur) et Kotlin (`take`) — sans jamais
    /// couper un caractère (émoji, lettre accentuée composée) : un texte trop long n'est pas refusé en 400.
    static func truncatedUTF16(_ text: String, max: Int) -> String {
        guard text.utf16.count > max else { return text }
        var result = ""
        var count = 0
        for character in text {
            let width = character.utf16.count
            if count + width > max { break }
            result.append(character)
            count += width
        }
        return result
    }

    /// Texte sans blancs de bord, `nil` s'il est vide (`trim().takeIf { it.isNotEmpty() }`).
    static func trimmedOrNil(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// `trim().take(max).takeIf { it.isNotEmpty() }` (Kotlin) : sans blancs de bord, coupé à `max` unités UTF-16,
    /// `nil` s'il ne reste rien (le serveur attend `null`, pas une chaîne vide).
    static func trimmedAndCut(_ text: String?, max: Int) -> String? {
        guard let trimmed = trimmedOrNil(text) else { return nil }
        let cut = truncatedUTF16(trimmed, max: max)
        return cut.isEmpty ? nil : cut
    }
}

/// Erreurs propres aux repositories (traduites par `ErrorMapper` en message générique).
nonisolated enum RepositoryError: Error, Sendable, Equatable {
    /// `GET api/wilayas?top=` : le serveur ne classe pas les wilayas (version antérieure, 58 wilayas sans compte).
    case rankingUnsupported
}
