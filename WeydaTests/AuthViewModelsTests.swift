import AuthenticationServices
import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage d'`AuthViewModelsTest.kt` (Android), mêmes cas : connexion (validation locale, succès, verrou, erreurs Zod,
/// Google), inscription (règles, e-mail déjà pris, Google), code e-mail (compte à rebours, envoi au 6e chiffre, code
/// effacé, renvoi). En plus : Apple, mot de passe oublié, nouveau mot de passe, enchaînement de la feuille de
/// connexion (fermeture, code e-mail), routeur. Données FICTIVES.
final class AuthViewModelsTests: XCTestCase {
    private static let googleClientID = "123456-abcdef.apps.googleusercontent.com"

    // MARK: - Aides

    private struct Fixture {
        let api: FakeWeydaAPI
        let session: SessionManager
        let auth: AuthRepository
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        return Fixture(api: api, session: session, auth: AuthRepository(api: api, session: session))
    }

    /// Apple et Google en API simulée (aucune fenêtre), e-mails en français.
    @MainActor
    private func makeSocial(_ auth: AuthRepository, googleClientID: String? = AuthViewModelsTests.googleClientID) -> SocialSignIn {
        SocialSignIn(
            auth: auth,
            apple: AppleSignInCoordinator(simulated: true),
            google: GoogleSignInCoordinator(clientID: googleClientID, simulated: true),
            locale: "fr"
        )
    }

    /// Attend la tâche d'une action ; une action ignorée (`nil`) fait échouer le test.
    @MainActor
    private func run(_ task: Task<Void, Never>?, file: StaticString = #filePath, line: UInt = #line) async {
        guard let task else {
            XCTFail("action ignorée", file: file, line: line)
            return
        }
        await task.value
    }

    private static func member(_ id: String = "user_1", verified: Bool) -> User {
        User(id: id, name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: verified)
    }

    // MARK: - Connexion (AuthViewModelsTest.kt)

    @MainActor
    func testLoginValidatesLocallyBeforeAnyNetworkCall() {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens() }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onEmailChange("pas-un-email")
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        XCTAssertEqual(model.state.passwordError, L10n.validationPasswordRequired)
        XCTAssertEqual(fixture.api.count("login"), 0)
        XCTAssertNil(model.state.success)
    }

    @MainActor
    func testLoginSuccessCarriesTheUserAndForgetsThePassword() async {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens() }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onEmailChange("amina@example.com")
        model.onPasswordChange("Secret123")
        XCTAssertTrue(model.state.canSubmit)
        await run(model.submit())
        XCTAssertFalse(model.state.isSubmitting)
        XCTAssertEqual(model.state.success?.id, "user_1")
        XCTAssertEqual(model.state.password, "")
        XCTAssertTrue(fixture.auth.isLoggedIn)
    }

    @MainActor
    func testRefusedLoginShowsTheServerMessageAndTheLockDelay() async {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in throw FakeWeydaAPI.apiError(423, #"{"error":"accountLocked"}"#, retryAfter: "600") }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onEmailChange("amina@example.com")
        model.onPasswordChange("x")
        await run(model.submit())
        XCTAssertEqual(model.state.errorMessage, L10n.errorAccountLocked + " " + L10n.authRetryIn(10))
        XCTAssertEqual(model.state.retryAfterSeconds, 600)
        XCTAssertNil(model.state.success)
        XCTAssertFalse(model.state.isSubmitting)
        // La saisie efface l'erreur globale.
        model.onPasswordChange("y")
        XCTAssertNil(model.state.errorMessage)
    }

    @MainActor
    func testLoginZodErrorsGoUnderTheirFields() async {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in
            throw FakeWeydaAPI.apiError(400, #"{"error":"invalidData","details":{"fieldErrors":{"email":["validation.emailInvalid"]}}}"#)
        }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onEmailChange("amina@example.com")
        model.onPasswordChange("x")
        await run(model.submit())
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        XCTAssertNil(model.state.errorMessage)
    }

    @MainActor
    func testGoogleLoginIsBusyAtOnceSucceedsMapsServerErrorsAndShowsLocalFailures() async {
        let fixture = makeFixture()
        fixture.api.onLoginWithGoogle = { body in
            XCTAssertEqual(body.idToken, "id-token")
            XCTAssertEqual(body.locale, "fr")
            return FakeWeydaAPI.tokens()
        }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        let task = model.signInWithGoogle(idToken: "id-token")
        XCTAssertTrue(model.state.isGoogleSubmitting)
        XCTAssertFalse(model.state.canSubmit)
        XCTAssertNil(model.signInWithGoogle(idToken: "id-token"), "double appui ignoré")
        await run(task)
        XCTAssertFalse(model.state.isGoogleSubmitting)
        XCTAssertEqual(model.state.success?.id, "user_1")
        XCTAssertTrue(fixture.auth.isLoggedIn)

        fixture.api.onLoginWithGoogle = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"googleEmailMissing"}"#) }
        let second = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        await run(second.signInWithGoogle(idToken: "id-token"))
        XCTAssertEqual(second.state.errorMessage, L10n.errorGoogleEmailMissing)
        XCTAssertNil(second.state.success)

        second.onSocialFailed(GoogleSignInError.authorizationFailed)
        XCTAssertEqual(second.state.errorMessage, L10n.errorGoogleSignIn)
        second.onEmailChange("a")
        XCTAssertNil(second.state.errorMessage)
        // Fenêtre fermée : annulation, rien à afficher.
        second.onSocialFailed(CancellationError())
        XCTAssertNil(second.state.errorMessage)
    }

    @MainActor
    func testContinueWithGoogleGoesThroughTheCoordinatorThenTheServer() async {
        let fixture = makeFixture()
        fixture.api.onLoginWithGoogle = { body in
            XCTAssertEqual(body.idToken, GoogleSignInCoordinator.simulatedIDToken)
            return FakeWeydaAPI.tokens()
        }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        XCTAssertTrue(model.social.showsGoogle)
        await run(model.continueWithGoogle())
        XCTAssertEqual(model.state.success?.id, "user_1")

        // Sans identifiant client : bouton masqué ; un appel quand même → « services Google indisponibles ».
        let unconfigured = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth, googleClientID: nil))
        XCTAssertFalse(unconfigured.social.showsGoogle)
        await run(unconfigured.continueWithGoogle())
        XCTAssertEqual(unconfigured.state.errorMessage, L10n.errorGoogleUnavailable)
        XCTAssertFalse(unconfigured.state.isGoogleSubmitting)
    }

    // MARK: - Apple (iOS)

    @MainActor
    func testAppleLoginSendsTheClearNonceTheNameAndTheLocale() async {
        let fixture = makeFixture()
        fixture.api.onLoginWithApple = { body in
            XCTAssertEqual(body.identityToken, "apple-identity")
            XCTAssertEqual(body.authorizationCode, "apple-code")
            XCTAssertEqual(body.nonce, "nonce-clair")
            XCTAssertEqual(body.name, AppleNameDTO(givenName: "Karim", familyName: "Bensalem"))
            XCTAssertEqual(body.locale, "fr")
            return FakeWeydaAPI.tokens()
        }
        let model = LoginViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        let credential = AppleCredential(
            identityToken: "apple-identity",
            authorizationCode: "apple-code",
            rawNonce: "nonce-clair",
            givenName: "Karim",
            familyName: "Bensalem",
            email: nil
        )
        let task = model.signInWithApple(credential)
        XCTAssertTrue(model.state.isAppleSubmitting)
        XCTAssertFalse(model.state.isGoogleSubmitting)
        XCTAssertFalse(model.state.canSubmit)
        await run(task)
        XCTAssertFalse(model.state.isAppleSubmitting)
        XCTAssertEqual(model.state.success?.id, "user_1")
        XCTAssertTrue(fixture.auth.isLoggedIn)
    }

    @MainActor
    func testAppleRefusalAndClosedAppleSheet() async {
        let fixture = makeFixture()
        fixture.api.onLoginWithApple = { _ in throw FakeWeydaAPI.apiError(401, #"{"error":"invalidAppleToken"}"#) }
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        await run(model.continueWithSimulatedApple())
        XCTAssertEqual(model.state.errorMessage, L10n.errorInvalidAppleToken)
        XCTAssertFalse(model.state.isAppleSubmitting)
        XCTAssertNil(model.state.success)

        model.onNameChange("Amina")
        let cancelled = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.canceled.rawValue)
        XCTAssertNil(model.completeApple(.failure(cancelled)))
        XCTAssertNil(model.state.errorMessage, "feuille Apple fermée : rien à afficher")
        let unavailable = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.unknown.rawValue)
        XCTAssertNil(model.completeApple(.failure(unavailable)))
        XCTAssertEqual(model.state.errorMessage, L10n.errorAppleUnavailable)
        XCTAssertEqual(fixture.api.count("loginWithApple"), 1)
    }

    @MainActor
    func testSimulatedAppleRegistrationSendsAFreshNonce() async {
        let fixture = makeFixture()
        let nonces = FakeWeydaAPI.Box<[String]>([])
        fixture.api.onLoginWithApple = { body in
            XCTAssertEqual(body.identityToken, "mock-apple-identity-token")
            nonces.value.append(body.nonce)
            return FakeWeydaAPI.tokens(emailVerified: true)
        }
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        XCTAssertTrue(model.social.isAppleSimulated)
        await run(model.continueWithSimulatedApple())
        XCTAssertNotNil(model.state.success)
        XCTAssertEqual(nonces.value.first?.count, 32)
    }

    // MARK: - Inscription (AuthViewModelsTest.kt)

    @MainActor
    func testGoogleRegistrationIsTheSameFlowAsTheLogin() async {
        let fixture = makeFixture()
        fixture.api.onLoginWithGoogle = { _ in
            var response = FakeWeydaAPI.tokens()
            response.isNewUser = true
            return response
        }
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        let task = model.signInWithGoogle(idToken: "id-token")
        XCTAssertTrue(model.state.isGoogleSubmitting)
        await run(task)
        XCTAssertNotNil(model.state.success)
        XCTAssertTrue(fixture.auth.isLoggedIn)
    }

    @MainActor
    func testRegisterChecksTheRulesThenRegistersAndSignsIn() async {
        let fixture = makeFixture()
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onNameChange("A")
        model.onEmailChange("amina@example.com")
        model.onPasswordChange("abc")
        model.onPhoneChange("0210123456")
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.state.nameError, L10n.validationNameMin)
        XCTAssertNil(model.state.emailError)
        XCTAssertEqual(model.state.passwordError, L10n.validationPasswordMin)
        XCTAssertEqual(model.state.phoneError, L10n.validationPhone)
        XCTAssertEqual(fixture.api.count("register"), 0)

        fixture.api.onRegister = { body in
            XCTAssertEqual(body.name, "Amina")
            XCTAssertEqual(body.phone, "0550123456")
            XCTAssertEqual(body.phoneCountryCode, "+213")
            return RegisterResponseDTO(id: "user_1")
        }
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        model.onNameChange("Amina")
        model.onPasswordChange("Secret123")
        model.onPhoneChange("0550 12 34 56")
        XCTAssertNil(model.state.phoneError, "la saisie efface l'erreur du champ")
        await run(model.submit())
        XCTAssertEqual(model.state.success?.emailVerified, false)
        XCTAssertEqual(model.state.password, "")
        XCTAssertFalse(model.state.isSubmitting)
    }

    @MainActor
    func testRegisterWithAnEmailAlreadyUsed() async {
        let fixture = makeFixture()
        fixture.api.onRegister = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"emailExists"}"#) }
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onNameChange("Amina")
        model.onEmailChange("amina@example.com")
        model.onPasswordChange("Secret123")
        await run(model.submit())
        XCTAssertEqual(model.state.errorMessage, L10n.errorEmailExists)
        XCTAssertNil(model.state.success)
    }

    /// Captures (`-WeydaAuthDemo invalid`) : le formulaire en erreur, sans réseau, une seule fois.
    @MainActor
    func testCaptureDemoShowsEveryFieldError() {
        let fixture = makeFixture()
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.applyCaptureDemo(nil)
        XCTAssertNil(model.state.nameError)
        model.applyCaptureDemo("invalid")
        XCTAssertEqual(model.state.nameError, L10n.validationNameMin)
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        XCTAssertEqual(model.state.passwordError, L10n.validationPasswordMin)
        XCTAssertEqual(model.state.phoneError, L10n.validationPhone)
        XCTAssertEqual(fixture.api.count("register"), 0)
    }

    // MARK: - Code e-mail (AuthViewModelsTest.kt)

    @MainActor
    func testVerifyStartsWithTheCooldownSubmitsAtTheSixthDigitAndClearsAWrongCode() async throws {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        let confirmed = FakeWeydaAPI.Box<String?>(nil)
        fixture.api.onConfirm = { body in
            if body.code == "000000" {
                throw FakeWeydaAPI.apiError(400, #"{"error":"incorrectCode","remainingAttempts":2}"#)
            }
            confirmed.value = body.code
            return SimpleResponseDTO()
        }
        let clock = FakeWeydaAPI.Box(Date(timeIntervalSince1970: 1_000))
        let model = VerifyEmailViewModel(auth: fixture.auth, now: { clock.value }, tick: { throw CancellationError() })
        XCTAssertEqual(model.state.email, "amina@example.com")
        XCTAssertEqual(model.state.cooldownSeconds, 60)
        XCTAssertFalse(model.state.canResend)

        XCTAssertNil(model.onCodeChange("12"), "pas d'envoi avant le 6e chiffre")
        await run(model.onCodeChange("00-00 00x"))
        XCTAssertEqual(model.state.errorMessage, L10n.errorIncorrectCode + " " + L10n.authVerifyAttemptsLeft(2))
        XCTAssertEqual(model.state.remainingAttempts, 2)
        XCTAssertEqual(model.state.code, "")

        // Chiffres arabes ramenés en ASCII.
        await run(model.onCodeChange("١٢٣٤٥٦"))
        XCTAssertEqual(confirmed.value, "123456")
        XCTAssertTrue(model.state.verified)
        XCTAssertEqual(fixture.auth.user?.emailVerified, true)
    }

    @MainActor
    func testTheCountdownFreesTheResendWhichRestartsSixtySeconds() async throws {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        let resends = FakeWeydaAPI.Box(0)
        fixture.api.onResend = {
            resends.value += 1
            return SimpleResponseDTO(expiresIn: 600)
        }
        let clock = FakeWeydaAPI.Box(Date(timeIntervalSince1970: 1_000))
        let model = VerifyEmailViewModel(auth: fixture.auth, now: { clock.value }, tick: { throw CancellationError() })

        clock.value = clock.value.addingTimeInterval(30)
        XCTAssertEqual(model.refreshCooldown(), 30)
        XCTAssertEqual(model.state.cooldownSeconds, 30)
        XCTAssertNil(model.resend(), "ignoré pendant le compte à rebours")
        XCTAssertEqual(resends.value, 0)

        clock.value = clock.value.addingTimeInterval(30)
        XCTAssertEqual(model.refreshCooldown(), 0)
        XCTAssertEqual(model.state.cooldownSeconds, 0)
        XCTAssertTrue(model.state.canResend)

        await run(model.resend())
        XCTAssertEqual(resends.value, 1)
        XCTAssertTrue(model.state.resent)
        XCTAssertEqual(model.state.cooldownSeconds, 60)
        clock.value = clock.value.addingTimeInterval(60)
        XCTAssertEqual(model.refreshCooldown(), 0)
        XCTAssertTrue(model.state.canResend)
    }

    /// Feuille ouverte depuis le bandeau (aucun code envoyé à l'instant) : renvoi possible tout de suite ; un refus du
    /// serveur avec délai relance le compte à rebours de ce délai.
    @MainActor
    func testResendWithoutInitialCooldownAndServerDelay() async throws {
        let fixture = makeFixture()
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        fixture.api.onResend = { throw FakeWeydaAPI.apiError(429, #"{"error":"rateLimitCooldown","retryAfter":42}"#) }
        let model = VerifyEmailViewModel(
            auth: fixture.auth,
            startsWithCooldown: false,
            now: { Date(timeIntervalSince1970: 0) },
            tick: { throw CancellationError() }
        )
        XCTAssertEqual(model.state.cooldownSeconds, 0)
        XCTAssertTrue(model.state.canResend)
        await run(model.resend())
        XCTAssertEqual(model.state.errorMessage, L10n.errorCodeCooldown)
        XCTAssertEqual(model.state.cooldownSeconds, 42)
        XCTAssertFalse(model.state.resent)
        XCTAssertFalse(model.state.isResending)
    }

    // MARK: - Mot de passe oublié

    @MainActor
    func testForgotPasswordValidatesThenConfirmsTheNormalizedAddress() async {
        let fixture = makeFixture()
        fixture.api.onForgotPassword = { body in
            XCTAssertEqual(body.email, "amina@example.com")
            XCTAssertEqual(body.locale, "ar")
            return SimpleResponseDTO()
        }
        let model = ForgotPasswordViewModel(auth: fixture.auth, locale: "ar")
        model.onEmailChange("pas-un-email")
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        XCTAssertEqual(fixture.api.count("forgotPassword"), 0)

        model.onEmailChange("  Amina@Example.com ")
        XCTAssertNil(model.state.emailError)
        await run(model.submit())
        XCTAssertEqual(model.state.sentTo, "amina@example.com")
        XCTAssertFalse(model.state.isSubmitting)
    }

    @MainActor
    func testForgotPasswordRateLimitIsShown() async {
        let fixture = makeFixture()
        fixture.api.onForgotPassword = { _ in throw FakeWeydaAPI.apiError(429, #"{"error":"rateLimitError"}"#, retryAfter: "3600") }
        let model = ForgotPasswordViewModel(auth: fixture.auth, locale: "fr")
        model.onEmailChange("amina@example.com")
        await run(model.submit())
        XCTAssertEqual(model.state.errorMessage, L10n.errorRateLimited)
        XCTAssertNil(model.state.sentTo)
    }

    // MARK: - Nouveau mot de passe

    @MainActor
    func testResetPasswordRulesSuccessAndExpiredLink() async {
        let fixture = makeFixture()
        let blank = ResetPasswordViewModel(token: "  ", auth: fixture.auth)
        XCTAssertTrue(blank.state.invalidLink)
        blank.onPasswordChange("Secret123")
        blank.onConfirmChange("Secret123")
        XCTAssertNil(blank.submit())

        let model = ResetPasswordViewModel(token: "jeton-1", auth: fixture.auth)
        XCTAssertFalse(model.state.invalidLink)
        model.onPasswordChange("abc")
        model.onConfirmChange("abd")
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.state.passwordError, L10n.validationPasswordMin)
        XCTAssertEqual(model.state.confirmError, L10n.validationPasswordMismatch)
        XCTAssertEqual(fixture.api.count("resetPassword"), 0)

        fixture.api.onResetPassword = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"invalidOrExpiredLink"}"#) }
        model.onPasswordChange("Secret123")
        model.onConfirmChange("Secret123")
        await run(model.submit())
        XCTAssertEqual(model.state.errorMessage, L10n.resetInvalidLink)
        XCTAssertFalse(model.state.isDone)

        fixture.api.onResetPassword = { body in
            XCTAssertEqual(body.token, "jeton-1")
            XCTAssertEqual(body.password, "Secret123")
            return SimpleResponseDTO()
        }
        await run(model.submit())
        XCTAssertTrue(model.state.isDone)
        XCTAssertEqual(model.state.password, "")
        XCTAssertEqual(model.state.confirm, "")
    }

    // MARK: - Feuille de connexion

    @MainActor
    func testTheSheetClosesOnceSignedInWithAVerifiedEmail() {
        let users = PassthroughSubject<User?, Never>()
        let flow = AuthFlowModel(entry: .login, currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        users.send(nil)
        XCTAssertEqual(flow.root, .login)
        flow.show(.forgotPassword)
        XCTAssertEqual(flow.current, .forgotPassword)
        users.send(Self.member(verified: true))
        XCTAssertTrue(flow.isFinished)
    }

    @MainActor
    func testAnUnverifiedAccountMovesToTheCodeStep() {
        let users = PassthroughSubject<User?, Never>()
        let flow = AuthFlowModel(entry: .login, currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        flow.show(.register)
        users.send(Self.member(verified: false))
        XCTAssertFalse(flow.isFinished)
        XCTAssertEqual(flow.root, .verifyEmail)
        XCTAssertEqual(flow.path, [])
        XCTAssertTrue(flow.codeJustSent, "le code vient de partir avec l'inscription")
        // Code accepté (même compte, vérifié) : l'écran de réussite reste, « Continuer » fermera.
        users.send(Self.member(verified: true))
        XCTAssertFalse(flow.isFinished)
        XCTAssertEqual(flow.root, .verifyEmail)
        flow.finish()
        XCTAssertTrue(flow.isFinished)

        let afterLogin = AuthFlowModel(entry: .login, currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        users.send(Self.member("user_2", verified: false))
        XCTAssertEqual(afterLogin.root, .verifyEmail)
        XCTAssertFalse(afterLogin.codeJustSent, "connexion : aucun code n'est parti")
    }

    @MainActor
    func testRegisteringThroughTheRealSessionReachesTheCodeStep() async {
        let fixture = makeFixture()
        let flow = AuthFlowModel(
            entry: .register,
            currentUser: fixture.session.user,
            sessionUser: fixture.session.$user.eraseToAnyPublisher()
        )
        fixture.api.onRegister = { _ in RegisterResponseDTO(id: "user_1") }
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        let model = RegisterViewModel(auth: fixture.auth, social: makeSocial(fixture.auth))
        model.onNameChange("Amina")
        model.onEmailChange("amina@example.com")
        model.onPasswordChange("Secret123")
        await run(model.submit())
        XCTAssertEqual(flow.root, .verifyEmail)
        XCTAssertTrue(flow.codeJustSent)
        XCTAssertFalse(flow.isFinished)
    }

    @MainActor
    func testVerifyNeedsAnAccountAndAClosedSessionGoesBackToTheLogin() {
        let users = PassthroughSubject<User?, Never>()
        let visitor = AuthFlowModel(entry: .verifyEmail, currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        XCTAssertEqual(visitor.root, .login)

        let member = Self.member(verified: false)
        let flow = AuthFlowModel(entry: .verifyEmail, currentUser: member, sessionUser: users.eraseToAnyPublisher())
        users.send(member)
        XCTAssertEqual(flow.root, .verifyEmail)
        XCTAssertFalse(flow.isFinished)
        users.send(nil)
        XCTAssertEqual(flow.root, .login)
        XCTAssertFalse(flow.isFinished)
    }

    @MainActor
    func testLoginAndRegisterNeverStackEndlessly() {
        let users = PassthroughSubject<User?, Never>()
        let flow = AuthFlowModel(entry: .login, currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        flow.show(.register)
        XCTAssertEqual(flow.path, [.register])
        flow.show(.login)
        XCTAssertEqual(flow.path, [], "retour à la connexion de la racine")
        flow.show(.forgotPassword)
        flow.show(.login)
        XCTAssertEqual(flow.path, [])

        let fromRegister = AuthFlowModel(entry: .register, currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        fromRegister.show(.login)
        fromRegister.show(.forgotPassword)
        XCTAssertEqual(fromRegister.path, [.login, .forgotPassword])
        fromRegister.show(.login)
        XCTAssertEqual(fromRegister.path, [.login])
        fromRegister.show(.register)
        XCTAssertEqual(fromRegister.path, [])

        let reset = AuthFlowModel(entry: .resetPassword(token: "t"), currentUser: nil, sessionUser: users.eraseToAnyPublisher())
        reset.restart(at: .login)
        XCTAssertEqual(reset.root, .login)
        XCTAssertEqual(reset.path, [])
    }

    // MARK: - Routeur

    @MainActor
    func testTheSignInSheetOpensOverTheCurrentScreen() {
        let router = AppRouter(initialTab: .home, launchRoute: nil)
        router.push(.detail(idOrSlug: "a1"))
        router.requestLogin()
        XCTAssertEqual(router.authFlow, .login)
        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")], "l'annonce reste dessous")
        router.requestEmailVerification()
        XCTAssertEqual(router.authFlow, .verifyEmail)
        router.open(.resetPassword(token: "t0k3n"))
        XCTAssertEqual(router.authFlow, .resetPassword(token: "t0k3n"))
        router.open(.listing(idOrSlug: "a2"))
        XCTAssertNil(router.authFlow, "un autre lien ferme la feuille")
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1"), .detail(idOrSlug: "a2")])
    }

    @MainActor
    func testLaunchRouteOpensTheSheetAboveTheProfileTab() {
        let router = AppRouter(initialTab: .home, launchRoute: "register")
        XCTAssertEqual(router.authFlow, .register)
        XCTAssertEqual(router.selectedTab, .account)
        let screen = AppRouter(initialTab: .home, launchRoute: "detail:mock-a3")
        XCTAssertNil(screen.authFlow)
    }

    func testLaunchEntriesOfTheCaptureTour() {
        XCTAssertEqual(AuthEntry.launchEntry("login"), .login)
        XCTAssertEqual(AuthEntry.launchEntry(" Register "), .register)
        XCTAssertEqual(AuthEntry.launchEntry("forgot"), .forgotPassword)
        XCTAssertEqual(AuthEntry.launchEntry("verify"), .verifyEmail)
        XCTAssertEqual(AuthEntry.launchEntry("reset:abc123"), .resetPassword(token: "abc123"))
        XCTAssertNil(AuthEntry.launchEntry("reset:  "))
        XCTAssertNil(AuthEntry.launchEntry("detail:mock-a3"))
        XCTAssertEqual(AuthEntry.resetPassword(token: "x").id, "reset:x")
        XCTAssertNotEqual(AuthEntry.login.id, AuthEntry.register.id)
    }

    // MARK: - API simulée (captures)

    #if DEBUG
    func testMockAuthRoutesAnswerWithTheReferenceUser() throws {
        func reply(_ method: String, _ path: String) throws -> MockReply {
            MockRoutes.shared.reply(method: method, url: try XCTUnwrap(URL(string: "https://weydaa.com\(path)")))
        }
        let reference = MockSessionFixture.user(emailVerified: true)
        for path in ["/api/auth/token", "/api/auth/token/refresh", "/api/auth/google", "/api/auth/apple"] {
            let token = try reply("POST", path)
            XCTAssertEqual(token.status, 200, path)
            let decoded = try JSONDecoder().decode(TokenResponseDTO.self, from: token.body)
            XCTAssertEqual(decoded.user.id, reference.id, path)
            XCTAssertEqual(decoded.user.name, reference.name, path)
            XCTAssertEqual(decoded.user.email, reference.email, path)
            XCTAssertTrue(decoded.user.emailVerified, path)
        }
        let register = try reply("POST", "/api/auth/register")
        XCTAssertEqual(register.status, 201)
        XCTAssertEqual(try JSONDecoder().decode(RegisterResponseDTO.self, from: register.body).id, reference.id)
        let code = try reply("POST", "/api/email-verify")
        XCTAssertEqual(try JSONDecoder().decode(SimpleResponseDTO.self, from: code.body).expiresIn, 600)
        for path in ["/api/email-verify/confirm", "/api/auth/forgot-password", "/api/auth/reset-password"] {
            let simple = try reply("POST", path)
            XCTAssertEqual(simple.status, 200, path)
            XCTAssertTrue(try JSONDecoder().decode(SimpleResponseDTO.self, from: simple.body).success, path)
        }
    }
    #endif
}
