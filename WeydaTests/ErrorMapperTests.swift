import XCTest
@testable import Weyda

/// Portage d'`ErrorMapperTest.kt` (+ cas iOS : annulation, erreurs d'image, délais et essais restants).
/// Les messages sont comparés aux chaînes du catalogue (`L10n`) de la langue du simulateur.
final class ErrorMapperTests: XCTestCase {
    private struct Boom: Error {}

    func testKnownServerCodesHaveDedicatedMessages() {
        XCTAssertEqual(ErrorMapper.message(code: "invalidCredentials"), L10n.errorInvalidCredentials)
        XCTAssertEqual(ErrorMapper.message(code: "invalidGoogleToken", status: 401), L10n.errorInvalidGoogleToken)
        XCTAssertEqual(ErrorMapper.message(code: "googleEmailMissing", status: 403), L10n.errorGoogleEmailMissing)
        XCTAssertEqual(ErrorMapper.message(code: "accountLocked", status: 423), L10n.errorAccountLocked)
        XCTAssertEqual(ErrorMapper.message(code: "emailNotVerified", status: 403), L10n.errorEmailNotVerified)
        XCTAssertEqual(ErrorMapper.message(code: "emailExists", status: 409), L10n.errorEmailExists)
        XCTAssertEqual(ErrorMapper.message(code: "unauthorized", status: 401), L10n.errorSessionExpired)
        XCTAssertEqual(ErrorMapper.message(code: "incorrectCode", status: 400), L10n.errorIncorrectCode)
    }

    func testMessagingOffersAndAccountCodesHaveDedicatedMessages() {
        XCTAssertEqual(ErrorMapper.message(code: "deletionWindowExpired", status: 403), L10n.chatDeletionWindowExpired)
        XCTAssertEqual(ErrorMapper.message(code: "alreadyDeleted", status: 400), L10n.chatMessageDeleted)
        XCTAssertEqual(ErrorMapper.message(code: "offerAlreadyOpen", status: 409), L10n.errorOfferAlreadyOpen)
        XCTAssertEqual(ErrorMapper.message(code: "noOpenOffer", status: 409), L10n.errorNoOpenOffer)
        XCTAssertEqual(ErrorMapper.message(code: "cannotRespondOwnOffer", status: 409), L10n.errorCannotRespondOwnOffer)
        XCTAssertEqual(ErrorMapper.message(code: "annonceUnavailable", status: 409), L10n.errorAnnonceUnavailable)
        XCTAssertEqual(ErrorMapper.message(code: "offerNotAllowed", status: 400), L10n.errorOfferNotAllowed)
        XCTAssertEqual(ErrorMapper.message(code: "cannotContactSelf", status: 400), L10n.errorCannotContactSelf)
        XCTAssertEqual(ErrorMapper.message(code: "userDeleted", status: 403), L10n.errorUserDeleted)
        XCTAssertEqual(ErrorMapper.message(code: "cannotBlockSelf", status: 400), L10n.errorCannotBlockSelf)
        XCTAssertEqual(ErrorMapper.message(code: "noPhoneNumber", status: 404), L10n.errorNoPhone)
        XCTAssertEqual(ErrorMapper.message(code: "adminAccountCannotBeDeleted", status: 403), L10n.errorAdminCannotDelete)
        XCTAssertEqual(ErrorMapper.message(code: "incorrectPassword", status: 400), L10n.errorIncorrectPassword)
        XCTAssertEqual(ErrorMapper.message(code: "passwordRequired", status: 400), L10n.validationPasswordRequired)
    }

    /// Garde-fou de parité : chaque code traité par Android a son message (aucun ne retombe sur le repli).
    func testEveryAndroidCodeIsMapped() {
        let codes = [
            "invalidCredentials", "invalidGoogleToken", "googleEmailMissing", "accountLocked", "accountSuspended",
            "unauthorized", "loginRequired", "invalidRefreshToken", "emailNotVerified", "googleReauthMismatch",
            "invalidOrExpiredLink", "linkExpired", "cannotReportSelf", "emailExists", "emailAlreadyUsed",
            "rateLimited", "rateLimitError", "tooManyAttempts", "rateLimitCooldown", "dailyLimitReached",
            "incorrectCode", "codeExpired", "noCodePending", "emailChanged", "emailSendFailed", "incorrectPassword",
            "passwordChangeNotAllowed", "accountDeletionNotAllowed", "adminAccountCannotBeDeleted", "passwordRequired",
            "userNotFound", "accountNotFound", "invalidData", "invalidEmail", "invalidCode", "notFound",
            "conversationNotFound", "userBlocked", "userDeleted", "cannotContactSelf", "cannotBlockSelf",
            "deletionWindowExpired", "alreadyDeleted", "offerAlreadyOpen", "noOpenOffer", "cannotRespondOwnOffer",
            "annonceUnavailable", "offerNotAllowed", "noPhoneNumber", "fileTooLarge", "unsupportedFileType",
            "invalidFile", "noFileProvided", "uploadError", "uploadServiceNotConfigured", "maxImagesExceeded",
            "invalidAttributes", "renewalLimitReached", "alreadyFavorited", "alreadyReported", "notEligible",
            "ownReviewError", "savedSearchEmpty", "savedSearchLimit", "invalidAnnonceId", "invalidReference",
            "duplicateEntry", "notRenewable", "forbiddenTransition", "invalidStatus", "invalidAction",
            "categoryNotFound", "serverError",
        ]
        XCTAssertEqual(codes.count, 73)
        for code in codes {
            XCTAssertNotEqual(ErrorMapper.message(code: code, status: 418), L10n.errorGeneric, code)
        }
        XCTAssertEqual(ErrorMapper.message(code: "savedSearchLimit"), L10n.alertLimit)
        XCTAssertEqual(ErrorMapper.message(code: "linkExpired"), L10n.resetInvalidLink)
        XCTAssertEqual(ErrorMapper.message(code: "fileTooLarge"), L10n.errorUploadTooLarge)
    }

    func testUnknownCodeFallsBackOnTheHTTPStatus() {
        XCTAssertEqual(ErrorMapper.message(code: "whatever", status: 401), L10n.errorSessionExpired)
        XCTAssertEqual(ErrorMapper.message(code: "whatever", status: 403), L10n.errorForbidden)
        XCTAssertEqual(ErrorMapper.message(code: "whatever", status: 404), L10n.errorNotFound)
        XCTAssertEqual(ErrorMapper.message(code: "whatever", status: 429), L10n.errorRateLimited)
        XCTAssertEqual(ErrorMapper.message(code: "whatever", status: 503), L10n.errorServer)
        XCTAssertEqual(ErrorMapper.message(code: "whatever", status: 418), L10n.errorGeneric)
    }

    func testNetworkAndUnknownErrors() {
        XCTAssertEqual(ErrorMapper.message(for: URLError(.cannotFindHost)), L10n.errorOffline)
        XCTAssertEqual(ErrorMapper.message(for: URLError(.timedOut)), L10n.errorOffline)
        XCTAssertEqual(ErrorMapper.message(for: URLError(.notConnectedToInternet)), L10n.errorOffline)
        XCTAssertEqual(
            ErrorMapper.message(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)),
            L10n.errorOffline
        )
        XCTAssertEqual(ErrorMapper.message(for: URLError(.badURL)), L10n.errorGeneric)
        XCTAssertEqual(ErrorMapper.message(for: Boom()), L10n.errorGeneric)
        let corrupted = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))
        XCTAssertEqual(ErrorMapper.message(for: corrupted), L10n.errorGeneric)
        XCTAssertEqual(ErrorMapper.message(for: APIError(status: 403, code: "accountSuspended")), L10n.errorAccountSuspended)
    }

    func testCancellationIsNeverShown() {
        XCTAssertNil(ErrorMapper.message(for: CancellationError()))
        XCTAssertNil(ErrorMapper.message(for: URLError(.cancelled)))
        XCTAssertNil(ErrorMapper.message(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertNil(ErrorMapper.messageWithRetryHint(for: CancellationError()))
        XCTAssertTrue(ErrorMapper.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(ErrorMapper.isCancellation(URLError(.timedOut)))
    }

    func testImagePreparationErrors() {
        XCTAssertEqual(ErrorMapper.message(for: ImagePreparationError.unreadable), L10n.errorPhotoRead)
        XCTAssertEqual(ErrorMapper.message(for: ImagePreparationError.tooLarge), L10n.errorUploadTooLarge)
    }

    func testZodFieldErrorsBecomeFieldMessages() {
        let error = APIError(
            status: 400,
            code: "invalidData",
            fieldErrors: ["email": "validation.emailInvalid", "x": "validation.unknown"]
        )
        XCTAssertEqual(ErrorMapper.fieldMessages(for: error), ["email": L10n.validationEmail])
        XCTAssertEqual(ErrorMapper.validationMessage("validation.passwordUppercase"), L10n.validationPasswordUppercase)
        XCTAssertEqual(ErrorMapper.validationMessage("phoneInvalid"), L10n.validationPhone)
        XCTAssertNil(ErrorMapper.validationMessage("validation.unknown"))
        XCTAssertEqual(ErrorMapper.fieldMessages(for: URLError(.timedOut)), [:])
    }

    func testUnauthorized403IsNotAnExpiredSession() {
        XCTAssertEqual(ErrorMapper.message(code: "unauthorized", status: 403), L10n.errorForbidden)
        XCTAssertEqual(ErrorMapper.message(code: "unauthorized", status: 401), L10n.errorSessionExpired)
        XCTAssertEqual(ErrorMapper.message(code: "invalidReference", status: 400), L10n.errorInvalidData)
    }

    func testAttributeErrorsBecomeMessages() {
        XCTAssertEqual(ErrorMapper.attributeMessage("required"), L10n.validationAttrRequired)
        XCTAssertEqual(ErrorMapper.attributeMessage("below_min"), L10n.validationAttrMin)
        XCTAssertEqual(ErrorMapper.attributeMessage("too_long"), L10n.validationAttrTextMax)
        XCTAssertEqual(ErrorMapper.attributeMessage("invalid_option"), L10n.validationAttrOption)
        let error = APIError(status: 400, code: "invalidAttributes", attributeErrors: ["year": "above_max"])
        XCTAssertEqual(ErrorMapper.attributeMessages(for: error), ["year": L10n.validationAttrMax])
    }

    func testRetryDelayAndRemainingAttemptsAreAppended() {
        let locked = APIError(status: 423, code: "accountLocked", retryAfterSeconds: 600)
        XCTAssertEqual(ErrorMapper.messageWithRetryHint(for: locked), L10n.errorAccountLocked + " " + L10n.authRetryIn(10))
        let soon = APIError(status: 429, code: "rateLimited", retryAfterSeconds: 61)
        XCTAssertEqual(ErrorMapper.messageWithRetryHint(for: soon), L10n.errorRateLimited + " " + L10n.authRetryIn(2))
        let noDelay = APIError(status: 401, code: "invalidCredentials")
        XCTAssertEqual(ErrorMapper.messageWithRetryHint(for: noDelay), L10n.errorInvalidCredentials)

        let wrongCode = APIError(status: 400, code: "incorrectCode", remainingAttempts: 2)
        XCTAssertEqual(
            ErrorMapper.messageWithAttemptsHint(for: wrongCode),
            L10n.errorIncorrectCode + " " + L10n.authVerifyAttemptsLeft(2)
        )
        XCTAssertEqual(ErrorMapper.retryMinutes(60), 1)
        XCTAssertEqual(ErrorMapper.retryMinutes(61), 2)
        XCTAssertEqual(ErrorMapper.retryMinutes(Int.max), Int.max / 60 + 1)
    }
}
