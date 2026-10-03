import Foundation

/// Traduction des erreurs (réseau, `{ error: "cleI18n" }` du serveur, Zod par champ, image) en messages —
/// portage d'`ui/common/ErrorMapper.kt`. Pur : testable sans interface.
nonisolated enum ErrorMapper {
    /// Message à afficher ; `nil` = annulation (`CancellationError`, `URLError.cancelled`) : ne rien afficher.
    static func message(for error: any Error) -> String? {
        if isCancellation(error) { return nil }
        if let apiError = error as? APIError {
            return message(code: apiError.code, status: apiError.status)
        }
        if let imageError = error as? ImagePreparationError {
            if case .tooLarge = imageError { return L10n.errorUploadTooLarge }
            return L10n.errorPhotoRead
        }
        if let urlError = error as? URLError {
            // URL mal formée = défaut de l'app (Android : IllegalArgumentException), pas le réseau.
            switch urlError.code {
            case .badURL, .unsupportedURL: return L10n.errorGeneric
            default: return L10n.errorOffline
            }
        }
        return L10n.errorGeneric
    }

    /// Vrai pour une annulation (écran quitté, recherche remplacée…) : jamais présentée comme une erreur.
    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Message suivi du délai imposé par le serveur (« Réessayez dans N min. »), comme l'écran de connexion
    /// Android (compte verrouillé, trop de tentatives).
    static func messageWithRetryHint(for error: any Error) -> String? {
        guard let text = message(for: error) else { return nil }
        guard let seconds = (error as? APIError)?.retryAfterSeconds, seconds > 0 else { return text }
        return text + " " + L10n.authRetryIn(retryMinutes(seconds))
    }

    /// Message suivi des essais restants (code de vérification de l'e-mail), comme l'écran Android.
    static func messageWithAttemptsHint(for error: any Error) -> String? {
        guard let text = message(for: error) else { return nil }
        guard let attempts = (error as? APIError)?.remainingAttempts else { return text }
        return text + " " + L10n.authVerifyAttemptsLeft(attempts)
    }

    /// Minutes entamées : 61 s → 2 min (Android : `(retry + 59) / 60`, sans débordement possible ici).
    static func retryMinutes(_ seconds: Int) -> Int {
        seconds / 60 + (seconds % 60 > 0 ? 1 : 0)
    }

    // MARK: - Codes du serveur

    /// Code i18n du serveur → message (`apiCodeRes` Android) ; code inconnu → repli selon le statut HTTP.
    static func message(code: String, status: Int = 0) -> String {
        switch code {
        case "invalidCredentials": return L10n.errorInvalidCredentials
        case "invalidGoogleToken": return L10n.errorInvalidGoogleToken
        case "googleEmailMissing": return L10n.errorGoogleEmailMissing
        case "accountLocked": return L10n.errorAccountLocked
        case "accountSuspended": return L10n.errorAccountSuspended
        // 403 `unauthorized` = ni propriétaire ni participant (annonces, conversations) : ce n'est pas une
        // session expirée, et l'annoncer comme telle enverrait l'utilisateur se reconnecter pour rien.
        case "unauthorized": return status == 403 ? L10n.errorForbidden : L10n.errorSessionExpired
        case "loginRequired", "invalidRefreshToken": return L10n.errorSessionExpired
        case "emailNotVerified": return L10n.errorEmailNotVerified
        case "googleReauthMismatch": return L10n.errorGoogleReauthMismatch
        case "invalidOrExpiredLink", "linkExpired": return L10n.resetInvalidLink
        case "cannotReportSelf": return L10n.errorCannotReportSelf
        case "emailExists", "emailAlreadyUsed": return L10n.errorEmailExists
        case "rateLimited", "rateLimitError", "tooManyAttempts": return L10n.errorRateLimited
        case "rateLimitCooldown": return L10n.errorCodeCooldown
        case "dailyLimitReached": return L10n.errorDailyLimit
        case "incorrectCode": return L10n.errorIncorrectCode
        case "codeExpired": return L10n.errorCodeExpired
        case "noCodePending": return L10n.errorNoCodePending
        case "emailChanged": return L10n.errorEmailChanged
        case "emailSendFailed": return L10n.errorEmailSendFailed
        case "incorrectPassword": return L10n.errorIncorrectPassword
        case "passwordChangeNotAllowed", "accountDeletionNotAllowed": return L10n.errorPasswordChangeNotAllowed
        case "adminAccountCannotBeDeleted": return L10n.errorAdminCannotDelete
        case "passwordRequired": return L10n.validationPasswordRequired
        case "userNotFound", "accountNotFound": return L10n.errorUserNotFound
        case "invalidData", "invalidEmail", "invalidCode": return L10n.errorInvalidData
        case "notFound", "conversationNotFound": return L10n.errorNotFound
        case "userBlocked": return L10n.errorUserBlocked
        case "userDeleted": return L10n.errorUserDeleted
        case "cannotContactSelf": return L10n.errorCannotContactSelf
        case "cannotBlockSelf": return L10n.errorCannotBlockSelf
        case "deletionWindowExpired": return L10n.chatDeletionWindowExpired
        case "alreadyDeleted": return L10n.chatMessageDeleted
        case "offerAlreadyOpen": return L10n.errorOfferAlreadyOpen
        case "noOpenOffer": return L10n.errorNoOpenOffer
        case "cannotRespondOwnOffer": return L10n.errorCannotRespondOwnOffer
        case "annonceUnavailable": return L10n.errorAnnonceUnavailable
        case "offerNotAllowed": return L10n.errorOfferNotAllowed
        case "noPhoneNumber": return L10n.errorNoPhone
        case "fileTooLarge": return L10n.errorUploadTooLarge
        case "unsupportedFileType", "invalidFile": return L10n.errorUploadBadFormat
        case "noFileProvided", "uploadError", "uploadServiceNotConfigured": return L10n.errorUploadFailed
        case "maxImagesExceeded": return L10n.errorMaxImages
        case "invalidAttributes": return L10n.errorInvalidAttributes
        case "renewalLimitReached": return L10n.errorRenewalLimit
        case "alreadyFavorited": return L10n.errorAlreadyFavorited
        case "alreadyReported": return L10n.errorAlreadyReported
        case "notEligible": return L10n.errorReviewNotEligible
        case "ownReviewError": return L10n.errorOwnReview
        case "savedSearchEmpty": return L10n.errorSavedSearchEmpty
        case "savedSearchLimit": return L10n.alertLimit
        case "invalidAnnonceId", "invalidReference", "duplicateEntry": return L10n.errorInvalidData
        case "notRenewable": return L10n.errorNotRenewable
        case "forbiddenTransition", "invalidStatus", "invalidAction": return L10n.errorForbidden
        case "categoryNotFound": return L10n.errorCategoryNotFound
        case "serverError": return L10n.errorServer
        default: return message(status: status)
        }
    }

    /// Repli pour un code inconnu.
    static func message(status: Int) -> String {
        switch status {
        case 401: return L10n.errorSessionExpired
        case 403: return L10n.errorForbidden
        case 404: return L10n.errorNotFound
        case 429: return L10n.errorRateLimited
        case 500...599: return L10n.errorServer
        default: return L10n.errorGeneric
        }
    }

    // MARK: - Erreurs par champ

    /// Clé Zod `validation.xxx` (src/lib/validations.ts) → message du champ ; `nil` si inconnue.
    static func validationMessage(_ key: String) -> String? {
        let prefix = "validation."
        let name = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
        switch name {
        case "nameMin2": return L10n.validationNameMin
        case "nameMax50": return L10n.validationNameMax
        case "emailInvalid": return L10n.validationEmail
        case "passwordMin8": return L10n.validationPasswordMin
        case "passwordUppercase": return L10n.validationPasswordUppercase
        case "passwordDigit": return L10n.validationPasswordDigit
        case "passwordRequired": return L10n.validationPasswordRequired
        case "phoneInvalid": return L10n.validationPhone
        case "countryCodeInvalid": return L10n.validationCountryCode
        case "titleMin5": return L10n.validationTitleMin
        case "titleMax100": return L10n.validationTitleMax
        case "descriptionMin20": return L10n.validationDescriptionMin
        case "descriptionMax5000": return L10n.validationDescriptionMax
        case "priceNegative": return L10n.validationPriceNegative
        case "categoryRequired": return L10n.validationCategoryRequired
        case "maxImages8": return L10n.errorMaxImages
        default: return nil
        }
    }

    /// Code d'un attribut refusé par le serveur (`attributeErrors`, validateListingAttributes) → message.
    static func attributeMessage(_ code: String) -> String {
        switch code {
        case "required": return L10n.validationAttrRequired
        case "invalid_number": return L10n.validationAttrNumber
        case "below_min": return L10n.validationAttrMin
        case "above_max": return L10n.validationAttrMax
        case "too_long", "invalid_text": return L10n.validationAttrTextMax
        default: return L10n.validationAttrOption
        }
    }

    /// Erreurs par champ d'une réponse 400 `invalidData` (champ → message), vide sinon.
    static func fieldMessages(for error: any Error) -> [String: String] {
        guard let apiError = error as? APIError else { return [:] }
        var messages: [String: String] = [:]
        for (field, key) in apiError.fieldErrors {
            if let message = validationMessage(key) { messages[field] = message }
        }
        return messages
    }

    /// Attributs refusés d'une annonce (clé → message), vide sinon.
    static func attributeMessages(for error: any Error) -> [String: String] {
        guard let apiError = error as? APIError else { return [:] }
        return apiError.attributeErrors.mapValues { attributeMessage($0) }
    }
}
