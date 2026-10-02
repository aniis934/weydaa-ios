import Foundation
import XCTest
@testable import Weyda

/// Portage d'AuthRepositoryTest.kt (Android) : connexion, Google, inscription, code e-mail, profil, mot de passe,
/// mes annonces — plus Apple (lot serveur A), la langue du compte et les données personnelles. Données fictives.
final class AuthRepositoryTests: XCTestCase {
    @MainActor
    func testLoginNormalizesTheEmailOpensTheSessionAndReturnsTheUser() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        api.onLogin = { body in
            XCTAssertEqual(body.email, "amina@example.com")
            return FakeWeydaAPI.tokens(emailVerified: false)
        }
        let user = try await auth.login(email: "  Amina@Example.com ", password: "Secret123")
        XCTAssertEqual(user.id, "user_1")
        XCTAssertFalse(user.emailVerified)
        XCTAssertTrue(auth.isLoggedIn)
        XCTAssertEqual(session.accessToken, "access-1")
    }

    @MainActor
    func testRefusedLoginKeepsTheServerCodeAndNoSession() async throws {
        let api = FakeWeydaAPI()
        let auth = AuthRepository(api: api, session: FakeWeydaAPI.makeSession())
        api.onLogin = { _ in throw FakeWeydaAPI.apiError(423, #"{"error":"accountLocked"}"#, retryAfter: "300") }
        do {
            _ = try await auth.login(email: "test@example.com", password: "x")
            XCTFail("refus attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "accountLocked")
            XCTAssertEqual(error.retryAfterSeconds, 300)
        }
        XCTAssertFalse(auth.isLoggedIn)
    }

    @MainActor
    func testGoogleLoginSendsTheTokenAndLocaleOpensTheSessionAndPropagatesTheServerCode() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        api.onLoginWithGoogle = { body in
            XCTAssertEqual(body.idToken, "google-id-token")
            XCTAssertEqual(body.locale, "ar")
            var response = FakeWeydaAPI.tokens(access: "access-g")
            response.isNewUser = true
            return response
        }
        let user = try await auth.loginWithGoogle(idToken: "google-id-token", locale: "ar")
        XCTAssertEqual(user.id, "user_1")
        XCTAssertTrue(user.emailVerified)
        XCTAssertEqual(session.accessToken, "access-g")

        session.signOut()
        api.onLoginWithGoogle = { _ in throw FakeWeydaAPI.apiError(401, #"{"error":"invalidGoogleToken"}"#) }
        do {
            _ = try await auth.loginWithGoogle(idToken: "bad", locale: "fr")
            XCTFail("refus attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "invalidGoogleToken")
        }
        XCTAssertFalse(auth.isLoggedIn)
    }

    @MainActor
    func testAppleLoginSendsIdentityCodeNonceNameAndLocale() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        api.onLoginWithApple = { body in
            XCTAssertEqual(body.identityToken, "apple-identity")
            XCTAssertEqual(body.authorizationCode, "code-1")
            XCTAssertEqual(body.nonce, "nonce-1")
            XCTAssertEqual(body.name, AppleNameDTO(givenName: "Amina", familyName: nil))
            XCTAssertEqual(body.locale, "fr")
            return FakeWeydaAPI.tokens(access: "access-a")
        }
        let user = try await auth.loginWithApple(
            identityToken: "apple-identity",
            authorizationCode: "code-1",
            nonce: "nonce-1",
            givenName: "  Amina ",
            familyName: "  ",
            locale: "fr"
        )
        XCTAssertEqual(user.id, "user_1")
        XCTAssertEqual(session.accessToken, "access-a")
    }

    @MainActor
    func testRegisterSignsInAndSendsTheCountryCodeOnlyWithAPhone() async throws {
        let api = FakeWeydaAPI()
        let auth = AuthRepository(api: api, session: FakeWeydaAPI.makeSession())
        api.onRegister = { body in
            XCTAssertEqual(body.phone, "0555000000")
            XCTAssertEqual(body.phoneCountryCode, "+213")
            return RegisterResponseDTO(id: "user_1", email: body.email)
        }
        api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        let user = try await auth.register(name: "Amina", email: "amina@example.com", password: "Secret123", phone: "0555000000")
        XCTAssertEqual(user.email, "amina@example.com")
        XCTAssertTrue(auth.isLoggedIn)

        api.onRegister = { body in
            XCTAssertNil(body.phone)
            XCTAssertNil(body.phoneCountryCode)
            return RegisterResponseDTO(id: "u2")
        }
        _ = try await auth.register(name: "Amina", email: "autre@example.com", password: "Secret123", phone: "  ")
    }

    @MainActor
    func testRegisterRetryAfterAFailedSignInLogsIntoTheAccountJustCreated() async throws {
        let api = FakeWeydaAPI()
        let auth = AuthRepository(api: api, session: FakeWeydaAPI.makeSession())
        api.onRegister = { _ in RegisterResponseDTO(id: "user_1") }
        api.onLogin = { _ in throw URLError(.timedOut) }
        do {
            _ = try await auth.register(name: "Amina", email: "amina@example.com", password: "Secret123", phone: nil)
            XCTFail("connexion en échec attendue")
        } catch is URLError {}

        // Le serveur répond « e-mail déjà utilisé » pour NOTRE compte : connexion directe.
        api.onRegister = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"emailExists"}"#) }
        api.onLogin = { _ in FakeWeydaAPI.tokens() }
        let user = try await auth.register(name: "Amina", email: " Amina@example.com", password: "Secret123", phone: nil)
        XCTAssertEqual(user.id, "user_1")
        XCTAssertTrue(auth.isLoggedIn)
    }

    @MainActor
    func testConfirmEmailMarksTheUserVerifiedAndResendReturnsTheValidity() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        _ = try await auth.login(email: "amina@example.com", password: "Secret123")

        api.onResend = { SimpleResponseDTO(expiresIn: 600) }
        let validity = try await auth.resendVerificationCode()
        XCTAssertEqual(validity, 600)

        api.onConfirm = { body in
            XCTAssertEqual(body.code, "123456")
            return SimpleResponseDTO()
        }
        try await auth.confirmEmail(code: " 123456 ")
        XCTAssertEqual(session.user?.emailVerified, true)

        api.onConfirm = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"incorrectCode","remainingAttempts":1}"#) }
        do {
            try await auth.confirmEmail(code: "000000")
            XCTFail("code refusé attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.remainingAttempts, 1)
        }
    }

    @MainActor
    func testMeMergesTheProfileWithTheSessionEmailVerified() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        let users = UserRepository(api: api, session: session)
        api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: true) }
        _ = try await auth.login(email: "amina@example.com", password: "Secret123")
        api.onMe = {
            MeDTO(id: "user_1", name: "Amina", email: "amina@example.com", phone: "0555000000", isRecommended: true, bio: "Pro")
        }
        let me = try await users.me()
        XCTAssertTrue(me.emailVerified)
        XCTAssertTrue(me.isRecommended)
        XCTAssertEqual(me.maxImages, 8)
        XCTAssertEqual(session.user?.phone, "0555000000")
    }

    @MainActor
    func testUpdateProfileMergesThePartialAnswerAndInvalidatesAChangedEmail() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        let users = UserRepository(api: api, session: session)
        api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: true) }
        _ = try await auth.login(email: "amina@example.com", password: "Secret123")
        api.onUpdateMe = { body in
            XCTAssertEqual(body.email, "new@example.com")
            XCTAssertEqual(body.phoneCountryCode, "+213")
            return MeDTO(id: "user_1", name: body.name, email: "new@example.com", phone: body.phone, bio: body.bio)
        }
        let updated = try await users.updateProfile(name: "Amina B.", email: "new@example.com", phone: "0555000000", bio: "Bio")
        XCTAssertEqual(updated.email, "new@example.com")
        XCTAssertFalse(updated.emailVerified)
        XCTAssertEqual(session.user?.name, "Amina B.")
    }

    @MainActor
    func testChangePasswordSignsOutLocally() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        let users = UserRepository(api: api, session: session)
        api.onLogin = { _ in FakeWeydaAPI.tokens() }
        _ = try await auth.login(email: "amina@example.com", password: "Secret123")
        api.onChangePassword = { body in
            XCTAssertEqual(body.newPassword, "Secret456")
            return SimpleResponseDTO()
        }
        try await users.changePassword(current: "Secret123", new: "Secret456", confirm: "Secret456")
        XCTAssertFalse(auth.isLoggedIn)
    }

    @MainActor
    func testMyListingsSendsTheStatusAndBoundsTheLimit() async throws {
        let api = FakeWeydaAPI()
        let users = UserRepository(api: api, session: FakeWeydaAPI.makeSession())
        api.onMyAnnonces = { status, page, limit in
            XCTAssertEqual(status, "PENDING")
            XCTAssertEqual(page, 2)
            XCTAssertEqual(limit, 48)
            return AnnoncesPageDTO(total: 0, page: 2, totalPages: 2)
        }
        let page = try await users.myListings(status: .pending, page: 2, limit: 500)
        XCTAssertEqual(page.page, 2)
    }

    @MainActor
    func testSyncLocaleIsSilentOnFailure() async throws {
        let api = FakeWeydaAPI()
        let users = UserRepository(api: api, session: FakeWeydaAPI.makeSession())
        api.onUpdateLocale = { body in
            XCTAssertEqual(body.locale, "ar")
            return MeDTO(id: "user_1")
        }
        let saved = await users.syncLocale("ar")
        XCTAssertTrue(saved)
        api.onUpdateLocale = { _ in throw URLError(.notConnectedToInternet) }
        let failed = await users.syncLocale("ar")
        XCTAssertFalse(failed)
    }

    @MainActor
    func testExportGoesToTheExportsFolderAndDeletionSignsOut() async throws {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("weyda-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let repository = AccountDataRepository(api: api, session: session, temporaryDirectory: temporary)
        api.onExportData = { destination in
            let target = try XCTUnwrap(destination)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: target)
            return target
        }
        let file = try await repository.export()
        XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent, AccountDataRepository.exportDirectoryName)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("weydaa-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        repository.clearLocalFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        session.signIn(FakeWeydaAPI.tokens())
        api.onDeleteAccount = { body in
            XCTAssertEqual(body.password, "Secret123")
            XCTAssertNil(body.googleIdToken)
            return SimpleResponseDTO()
        }
        try await repository.deleteAccount(password: "Secret123")
        XCTAssertFalse(session.isLoggedIn)

        session.signIn(FakeWeydaAPI.tokens())
        api.onDeleteAccount = { body in
            XCTAssertNil(body.password)
            XCTAssertEqual(body.appleIdentityToken, "apple-identity")
            XCTAssertEqual(body.nonce, "nonce-1")
            XCTAssertEqual(body.appleAuthorizationCode, "code-1")
            return SimpleResponseDTO()
        }
        try await repository.deleteAppleAccount(identityToken: "apple-identity", nonce: "nonce-1", authorizationCode: "code-1")
        XCTAssertFalse(session.isLoggedIn)
    }
}
