import AuthenticationServices
import Foundation
import XCTest
@testable import Weyda

/// « Se connecter avec Apple » (sans équivalent Android) : nonce aléatoire et son SHA-256, lecture de la réponse
/// d'Apple, erreurs du système (annulation silencieuse), autorisation simulée. Données FICTIVES.
final class AppleSignInTests: XCTestCase {

    // MARK: - Nonce

    func testNonceIsRandomURLSafeAndLongEnoughForTheServer() {
        let first = AppleNonce.random()
        let second = AppleNonce.random()
        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
        let allowed = Set(AppleNonce.alphabet)
        XCTAssertTrue(first.allSatisfy { allowed.contains($0) }, first)
        XCTAssertEqual(AppleNonce.alphabet.count, 64, "64 symboles : aucun biais de modulo")
        // Le serveur exige 16 à 256 caractères.
        XCTAssertEqual(AppleNonce.random(length: 16).count, 16)
        XCTAssertEqual(AppleNonce.random(length: 256).count, 256)
    }

    func testNonceHashIsLowercaseHexSHA256() {
        // Vecteurs du NIST (FIPS 180-2).
        XCTAssertEqual(
            AppleNonce.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            AppleNonce.sha256(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(AppleNonce.sha256("nonce-1").count, 64)
    }

    func testSecureRandomReturnsTheRequestedNumberOfBytes() {
        XCTAssertEqual(SecureRandom.bytes(32).count, 32)
        XCTAssertEqual(SecureRandom.bytes(0).count, 0)
        XCTAssertEqual(SecureRandom.bytes(-3).count, 0)
        XCTAssertNotEqual(SecureRandom.bytes(16), SecureRandom.bytes(16))
    }

    // MARK: - Réponse d'Apple

    func testCredentialKeepsTokensNameAndNonce() throws {
        var name = PersonNameComponents()
        name.givenName = "Karim"
        name.familyName = "  "
        let credential = try AppleSignInCoordinator.credential(
            identityToken: Data("eyJ.identity.token".utf8),
            authorizationCode: Data("c0de-apple".utf8),
            fullName: name,
            email: "karim.b@privaterelay.example.com",
            rawNonce: "nonce-clair"
        )
        XCTAssertEqual(credential.identityToken, "eyJ.identity.token")
        XCTAssertEqual(credential.authorizationCode, "c0de-apple")
        XCTAssertEqual(credential.rawNonce, "nonce-clair")
        XCTAssertEqual(credential.givenName, "Karim")
        XCTAssertNil(credential.familyName, "un nom blanc n'est pas envoyé")
        XCTAssertEqual(credential.email, "karim.b@privaterelay.example.com")
    }

    func testCredentialWithoutNameOrCodeAfterTheFirstAuthorization() throws {
        let credential = try AppleSignInCoordinator.credential(
            identityToken: Data("tok".utf8),
            authorizationCode: nil,
            fullName: nil,
            email: nil,
            rawNonce: "n"
        )
        XCTAssertNil(credential.authorizationCode)
        XCTAssertNil(credential.givenName)
        XCTAssertNil(credential.familyName)
        XCTAssertNil(credential.email)
    }

    func testMissingOrBlankIdentityTokenIsAnInvalidResponse() {
        XCTAssertThrowsError(
            try AppleSignInCoordinator.credential(
                identityToken: nil, authorizationCode: nil, fullName: nil, email: nil, rawNonce: "n"
            )
        ) { error in
            XCTAssertEqual(error as? AppleSignInError, .invalidResponse)
        }
        XCTAssertThrowsError(
            try AppleSignInCoordinator.credential(
                identityToken: Data("  ".utf8), authorizationCode: nil, fullName: nil, email: nil, rawNonce: "n"
            )
        ) { error in
            XCTAssertEqual(error as? AppleSignInError, .invalidResponse)
        }
    }

    // MARK: - Erreurs du système

    func testCancelledAuthorizationIsSilentOtherFailuresAreReported() {
        let cancelled = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.canceled.rawValue)
        XCTAssertTrue(AppleSignInCoordinator.mapError(cancelled) is CancellationError)
        XCTAssertTrue(AppleSignInCoordinator.mapError(CancellationError()) is CancellationError)

        // Sans l'entitlement « Sign in with Apple » (ou sans compte iCloud), le système répond « inconnu » (1000).
        let unknown = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.unknown.rawValue)
        XCTAssertEqual(AppleSignInCoordinator.mapError(unknown) as? AppleSignInError, .failed)
        XCTAssertEqual(AppleSignInCoordinator.mapError(URLError(.timedOut)) as? AppleSignInError, .failed)
        XCTAssertEqual(ErrorMapper.message(for: AppleSignInCoordinator.mapError(unknown)), L10n.errorAppleUnavailable)
    }

    // MARK: - Coordinateur

    @MainActor
    func testSimulatedAuthorizationOpensNoWindowAndUsesAFreshNonce() async throws {
        let coordinator = AppleSignInCoordinator(simulated: true)
        XCTAssertTrue(coordinator.isSimulated)
        let first = try await coordinator.signIn()
        let second = try await coordinator.signIn()
        XCTAssertEqual(first.identityToken, "mock-apple-identity-token")
        XCTAssertEqual(first.authorizationCode, "mock-apple-authorization-code")
        XCTAssertEqual(first.rawNonce.count, 32)
        XCTAssertNotEqual(first.rawNonce, second.rawNonce)
    }

    /// Bouton système : `prepare` pose la portée et le SHA-256 du nonce ; la fin rend le nonce CLAIR ; un échec ou une
    /// réponse sans demande préparée ne laisse rien passer.
    @MainActor
    func testSystemButtonRequestCarriesTheHashedNonceAndTheFailureIsMapped() throws {
        let coordinator = AppleSignInCoordinator(simulated: false)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        coordinator.prepare(request)
        XCTAssertEqual(Set(request.requestedScopes ?? []), [.fullName, .email])
        XCTAssertEqual(request.nonce?.count, 64)

        let cancelled = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.canceled.rawValue)
        XCTAssertThrowsError(try coordinator.credential(from: .failure(cancelled))) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let failed = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.failed.rawValue)
        XCTAssertThrowsError(try coordinator.credential(from: .failure(failed))) { error in
            XCTAssertEqual(error as? AppleSignInError, .failed)
        }
    }
}
