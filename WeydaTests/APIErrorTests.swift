import XCTest
@testable import Weyda

/// Portage d'`ApiExceptionTest.kt` : lecture du corps `{ error, … }` des réponses en erreur.
final class APIErrorTests: XCTestCase {
    private func apiError(_ status: Int, _ body: String, retryAfter: String? = nil) -> APIError {
        APIError(status: status, body: Data(body.utf8), retryAfterHeader: retryAfter)
    }

    func testCodeAndBodyExtrasAreExtracted() {
        let error = apiError(400, #"{"error":"incorrectCode","remainingAttempts":2}"#)
        XCTAssertEqual(error.status, 400)
        XCTAssertEqual(error.code, "incorrectCode")
        XCTAssertEqual(error.remainingAttempts, 2)
        XCTAssertNil(error.retryAfterSeconds)
    }

    func testAttributeErrorsAndMaxImagesAreExposed() {
        let attributes = apiError(400, #"{"error":"invalidAttributes","attributeErrors":{"year":"below_min"}}"#)
        XCTAssertEqual(attributes.attributeErrors, ["year": "below_min"])
        XCTAssertEqual(apiError(400, #"{"error":"maxImagesExceeded","maxImages":5}"#).maxImages, 5)
        XCTAssertTrue(apiError(500, "").attributeErrors.isEmpty)
    }

    func testRetryAfterComesFromTheBodyThenTheHeader() {
        XCTAssertEqual(apiError(429, #"{"error":"rateLimitCooldown","retryAfter":45}"#).retryAfterSeconds, 45)
        XCTAssertEqual(apiError(429, #"{"error":"rateLimited"}"#, retryAfter: "900").retryAfterSeconds, 900)
        // Le corps l'emporte sur l'en-tête ; une date HTTP en en-tête n'est pas un délai en secondes.
        XCTAssertEqual(apiError(429, #"{"error":"rateLimited","retryAfter":60}"#, retryAfter: "900").retryAfterSeconds, 60)
        XCTAssertNil(apiError(429, #"{"error":"rateLimited"}"#, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT").retryAfterSeconds)
    }

    func testZodFieldErrorsAreFlattenedToTheirFirstKey() {
        let body = #"{"error":"invalidData","details":{"formErrors":[],"fieldErrors":{"email":["validation.emailInvalid"],"password":["validation.passwordMin8","validation.passwordDigit"]}}}"#
        XCTAssertEqual(
            apiError(400, body).fieldErrors,
            ["email": "validation.emailInvalid", "password": "validation.passwordMin8"]
        )
    }

    func testEmptyOrNonJSONBodyFallsBackToTheStatusCode() {
        XCTAssertEqual(apiError(401, "").code, "unauthorized")
        XCTAssertEqual(apiError(403, "").code, "forbidden")
        XCTAssertEqual(apiError(404, "<html>").code, "notFound")
        XCTAssertEqual(apiError(429, "").code, "rateLimited")
        XCTAssertEqual(apiError(502, "").code, "serverError")
        XCTAssertEqual(APIError(status: 404, body: nil).code, "notFound")
        XCTAssertTrue(apiError(401, "").isUnauthorized)
        XCTAssertTrue(apiError(403, #"{"error":"emailNotVerified"}"#).isEmailNotVerified)
        XCTAssertFalse(apiError(401, #"{"error":"emailNotVerified"}"#).isEmailNotVerified)
    }

    func testBothFieldErrorShapesAreRead() throws {
        let nested = try JSONSerialization.jsonObject(
            with: Data(#"{"fieldErrors":{"title":["validation.titleMin5"]},"formErrors":[]}"#.utf8)
        )
        XCTAssertEqual(APIError.parseFieldErrors(nested), ["title": "validation.titleMin5"])
        // PUT /api/annonces/{id} et POST /api/saved-searches envoient la map directement.
        let flat = try JSONSerialization.jsonObject(with: Data(#"{"price":["validation.priceNegative"]}"#.utf8))
        XCTAssertEqual(APIError.parseFieldErrors(flat), ["price": "validation.priceNegative"])
        XCTAssertEqual(APIError.parseFieldErrors(nil), [:])
    }

    func testOfferAlreadyOpenCarriesTheConversation() {
        let error = apiError(409, #"{"error":"offerAlreadyOpen","conversationId":"conv_1"}"#)
        XCTAssertEqual(error.code, "offerAlreadyOpen")
        XCTAssertEqual(error.conversationId, "conv_1")
    }

    func testLenientNumbersAndHeaderFromTheHTTPResponse() throws {
        XCTAssertEqual(apiError(400, #"{"error":"incorrectCode","remainingAttempts":"3"}"#).remainingAttempts, 3)
        let url = try XCTUnwrap(URL(string: "https://api.weydaa.test/api/auth/token"))
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 423, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": " 600 "])
        )
        let locked = APIError(response: response, body: Data(#"{"error":"accountLocked"}"#.utf8))
        XCTAssertEqual(locked.status, 423)
        XCTAssertEqual(locked.code, "accountLocked")
        XCTAssertEqual(locked.retryAfterSeconds, 600)
    }
}
