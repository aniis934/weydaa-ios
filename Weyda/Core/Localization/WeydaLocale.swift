import Foundation

/// Langue et formats de l'app.
///
/// La langue suit le réglage « langue de l'app » d'iOS (Réglages › Weydaa › Langue) : la voie
/// Apple, la seule fiable pour l'arabe de droite à gauche. Changer de langue relance l'app, donc
/// ces valeurs sont figées pour la durée d'un lancement.
nonisolated enum WeydaLocale {
    /// Langues de l'app, dans l'ordre du catalogue.
    static let supported = ["fr", "ar", "en"]

    /// Langue de l'interface : fr, ar ou en.
    static let language: String = {
        let preferred = Bundle.main.preferredLocalizations.first ?? "fr"
        return supported.contains(preferred) ? preferred : "fr"
    }()

    /// Locale de formatage : la langue de l'interface, la région du téléphone (Algérie par
    /// défaut) et les chiffres LATINS forcés, y compris en arabe (comme LatinDigits sur Android :
    /// les prix et numéros de l'annonce s'écrivent comme sur le site).
    static let formatting: Locale = latinDigits(language: language, region: Locale.current.region?.identifier)

    static func latinDigits(language: String, region: String?) -> Locale {
        Locale(identifier: "\(language)_\(region ?? "DZ")@numbers=latn")
    }

    /// Vrai si l'interface se lit de droite à gauche.
    static var isRightToLeft: Bool { language == "ar" }
}

nonisolated extension L10n {
    /// Recherche d'une clé du catalogue (Localizable.xcstrings), formatée avec chiffres latins.
    /// Les pluriels (fr / ar / en, dont les six formes de l'arabe) sont résolus par le système.
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: WeydaLocale.formatting, arguments: arguments)
    }
}
