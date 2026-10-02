import Foundation

/// Règle de saisie non respectée : la clé du catalogue (l'équivalent des `R.string.validation_*` renvoyés par
/// `Validators.kt`). `text` donne la phrase traduite. Couvre aussi les messages vérifiés directement par les
/// écrans Android (confirmation du mot de passe, bio, catégorie, formulaire de contact).
nonisolated enum ValidationMessage: String, CaseIterable, Sendable {
    case nameMin = "validation_name_min"
    case nameMax = "validation_name_max"
    case email = "validation_email"
    case passwordMin = "validation_password_min"
    case passwordUppercase = "validation_password_uppercase"
    case passwordDigit = "validation_password_digit"
    case passwordRequired = "validation_password_required"
    case passwordMismatch = "validation_password_mismatch"
    case phone = "validation_phone"
    case countryCode = "validation_country_code"
    case code = "validation_code"
    case titleMin = "validation_title_min"
    case titleMax = "validation_title_max"
    case descriptionMin = "validation_description_min"
    case descriptionMax = "validation_description_max"
    case priceInvalid = "validation_price_invalid"
    case priceNegative = "validation_price_negative"
    case categoryRequired = "validation_category_required"
    case bioMax = "validation_bio_max"
    case subjectMin = "validation_subject_min"
    case messageMin = "validation_message_min"
    case attrRequired = "validation_attr_required"
    case attrOption = "validation_attr_option"
    case attrNumber = "validation_attr_number"
    case attrMin = "validation_attr_min"
    case attrMax = "validation_attr_max"
    case attrTextMax = "validation_attr_text_max"

    /// Phrase traduite (accès typés : une clé absente du catalogue ne compile pas).
    var text: String {
        switch self {
        case .nameMin: L10n.validationNameMin
        case .nameMax: L10n.validationNameMax
        case .email: L10n.validationEmail
        case .passwordMin: L10n.validationPasswordMin
        case .passwordUppercase: L10n.validationPasswordUppercase
        case .passwordDigit: L10n.validationPasswordDigit
        case .passwordRequired: L10n.validationPasswordRequired
        case .passwordMismatch: L10n.validationPasswordMismatch
        case .phone: L10n.validationPhone
        case .countryCode: L10n.validationCountryCode
        case .code: L10n.validationCode
        case .titleMin: L10n.validationTitleMin
        case .titleMax: L10n.validationTitleMax
        case .descriptionMin: L10n.validationDescriptionMin
        case .descriptionMax: L10n.validationDescriptionMax
        case .priceInvalid: L10n.validationPriceInvalid
        case .priceNegative: L10n.validationPriceNegative
        case .categoryRequired: L10n.validationCategoryRequired
        case .bioMax: L10n.validationBioMax
        case .subjectMin: L10n.validationSubjectMin
        case .messageMin: L10n.validationMessageMin
        case .attrRequired: L10n.validationAttrRequired
        case .attrOption: L10n.validationAttrOption
        case .attrNumber: L10n.validationAttrNumber
        case .attrMin: L10n.validationAttrMin
        case .attrMax: L10n.validationAttrMax
        case .attrTextMax: L10n.validationAttrTextMax
        }
    }
}

/// Validation locale — portage de `ui/common/Validators.kt`, miroir des schémas Zod du serveur
/// (src/lib/validations.ts : registerSchema, loginSchema, updateProfileSchema, annonceSchema +
/// validateListingAttributes de src/data/attributes/index.ts). Renvoie le message, ou nil si la valeur est valide.
///
/// Les longueurs sont comptées en unités UTF-16, comme `String.length` en Kotlin ET en JavaScript (Zod) :
/// un émoji compte double des deux côtés, l'app ne laisse donc rien passer que le serveur refuserait.
nonisolated enum Validators {

    // MARK: - Compte

    static func name(_ value: String) -> ValidationMessage? {
        let length = trimmed(value).utf16.count
        if length < 2 { return .nameMin }
        if length > 50 { return .nameMax }
        return nil
    }

    static func email(_ value: String) -> ValidationMessage? {
        isEmail(trimmed(value)) ? nil : .email
    }

    /// Règles d'inscription : ≥ 8 caractères, une majuscule, un chiffre — au sens du serveur, `/[A-Z]/` et
    /// `/[0-9]/` (ASCII). « É » ou « ٣ » passaient un test Unicode puis le serveur refusait avec un message
    /// générique.
    static func password(_ value: String) -> ValidationMessage? {
        if value.utf16.count < 8 { return .passwordMin }
        if !value.utf8.contains(where: { (65...90).contains($0) }) { return .passwordUppercase }
        if !value.utf8.contains(where: { (48...57).contains($0) }) { return .passwordDigit }
        return nil
    }

    /// Connexion : seule la présence est exigée (`loginSchema`).
    static func passwordRequired(_ value: String) -> ValidationMessage? {
        value.isEmpty ? .passwordRequired : nil
    }

    /// Téléphone optionnel : vide accepté, sinon mobile algérien. Espaces tolérés à la saisie.
    static func mobilePhone(_ value: String) -> ValidationMessage? {
        let compact = value.replacingOccurrences(of: " ", with: "")
        return compact.isEmpty || isMobilePhone(compact) ? nil : .phone
    }

    /// Téléphone de contact d'une annonce : mobile ou fixe.
    static func contactPhone(_ value: String) -> ValidationMessage? {
        let compact = value.replacingOccurrences(of: " ", with: "")
        return compact.isEmpty || isContactPhone(compact) ? nil : .phone
    }

    /// Code de vérification : exactement six chiffres.
    static func code6(_ value: String) -> ValidationMessage? {
        let code = trimmed(value)
        let valid = code.count == 6 && code.allSatisfy { asciiDigit($0) != nil }
        return valid ? nil : .code
    }

    /// Normalise un numéro saisi (espaces retirés) pour l'API.
    static func normalizePhone(_ value: String) -> String {
        trimmed(value.replacingOccurrences(of: " ", with: ""))
    }

    /// Mobile uniquement (05/06/07), comme `mobilePhoneRegex` du serveur : `^(?:0|\+213)[5-7]\d{8}$`.
    static func isMobilePhone(_ compact: String) -> Bool {
        matchesAlgerianPhone(compact, firstDigits: 5...7)
    }

    /// Mobile + fixe (02 à 07), comme `contactPhoneRegex` : `^(?:0|\+213)[2-7]\d{8}$`.
    static func isContactPhone(_ compact: String) -> Bool {
        matchesAlgerianPhone(compact, firstDigits: 2...7)
    }

    // MARK: - Chiffres saisis

    /// Ne garde que les chiffres, ramenés en ASCII. Un clavier arabe produit « ٠١٢٣ » (et le persan
    /// « ۰۱۲۳ ») : sans cela, prix « invalide », filtre de prix ignoré, code de vérification rejeté.
    static func asciiDigits(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            if let digit = decimalDigitValue(scalar) { result += String(digit) }
        }
        return result
    }

    /// Comme `asciiDigits`, en gardant le séparateur décimal (attributs numériques : surface, cylindrée…).
    /// iOS : le pavé décimal écrit le séparateur de la langue (« , » en français, « ٫ » en arabe) ; il devient
    /// le « . » attendu par l'API au lieu d'être supprimé (« 12,5 » donnait « 125 »).
    static func asciiDecimal(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            if scalar == "." || scalar == "," || scalar == "\u{066B}" {
                result += "."
            } else if let digit = decimalDigitValue(scalar) {
                result += String(digit)
            }
        }
        return result
    }

    // MARK: - Annonce (annonceSchema)

    static func title(_ value: String) -> ValidationMessage? {
        let length = trimmed(value).utf16.count
        if length < 5 { return .titleMin }
        if length > 100 { return .titleMax }
        return nil
    }

    static func description(_ value: String) -> ValidationMessage? {
        let length = trimmed(value).utf16.count
        if length < 20 { return .descriptionMin }
        if length > 5000 { return .descriptionMax }
        return nil
    }

    /// Prix optionnel (null accepté par le serveur), ignoré si gratuit, jamais négatif.
    static func price(_ value: String, type: PriceType) -> ValidationMessage? {
        if type == .free || TextCheck.isBlank(value) { return nil }
        guard let number = Double(value.replacingOccurrences(of: " ", with: "")), number.isFinite else {
            return .priceInvalid
        }
        return number < 0 ? .priceNegative : nil
    }

    /// Un attribut (miroir de validateListingAttributes) ; `options` = options courantes (selects dépendants :
    /// vides tant que le parent n'a pas de valeur, la valeur est alors acceptée et le serveur tranche).
    static func attribute(_ definition: AttributeDefinition, value: String?, options: [AttributeOption]) -> ValidationMessage? {
        let text = trimmed(value ?? "")
        if text.isEmpty { return definition.isRequired ? .attrRequired : nil }
        switch definition.type {
        case .select:
            if options.isEmpty { return nil }
            return options.contains(where: { $0.value == text }) ? nil : .attrOption
        case .number:
            guard let number = Double(text), number.isFinite else { return .attrNumber }
            if let lower = definition.min, number < lower { return .attrMin }
            if let upper = definition.max, number > upper { return .attrMax }
            return nil
        case .boolean:
            return text == "true" || text == "false" ? nil : .attrOption
        case .text:
            return text.utf16.count > 200 ? .attrTextMax : nil
        }
    }

    /// Tous les attributs d'une catégorie → clé → message (vide si tout est valide).
    static func attributes(
        _ definitions: [AttributeDefinition],
        values: [String: String],
        optionsFor: (AttributeDefinition) -> [AttributeOption]
    ) -> [String: ValidationMessage] {
        var errors: [String: ValidationMessage] = [:]
        for definition in definitions {
            if let message = attribute(definition, value: values[definition.key], options: optionsFor(definition)) {
                errors[definition.key] = message
            }
        }
        return errors
    }

    // MARK: - Interne

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$` : une partie locale, un seul « @ », un domaine avec un point précédé d'au
    /// moins un caractère et suivi d'au moins deux, aucun blanc.
    private static func isEmail(_ value: String) -> Bool {
        if value.contains(where: { $0.isWhitespace }) { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = Array(parts[1])
        for index in domain.indices where domain[index] == "." {
            if index >= 1, domain.count - index - 1 >= 2 { return true }
        }
        return false
    }

    /// `0` ou `+213`, puis exactement neuf chiffres ASCII dont le premier est dans `firstDigits`.
    private static func matchesAlgerianPhone(_ value: String, firstDigits: ClosedRange<UInt8>) -> Bool {
        let national: Substring
        if value.hasPrefix("+213") {
            national = value.dropFirst(4)
        } else if value.hasPrefix("0") {
            national = value.dropFirst()
        } else {
            return false
        }
        let digits = national.compactMap { asciiDigit($0) }
        guard national.count == 9, digits.count == 9, let first = digits.first else { return false }
        return firstDigits.contains(first)
    }

    /// Valeur d'un chiffre ASCII 0-9 (comme `\d` en Java et en JavaScript), nil sinon.
    private static func asciiDigit(_ character: Character) -> UInt8? {
        guard let ascii = character.asciiValue, (48...57).contains(ascii) else { return nil }
        return ascii - 48
    }

    /// Chiffre décimal de n'importe quelle écriture (catégorie Unicode Nd, comme `Character.digit` en Java).
    private static func decimalDigitValue(_ scalar: Unicode.Scalar) -> Int? {
        guard scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue else { return nil }
        return Int(value)
    }
}
