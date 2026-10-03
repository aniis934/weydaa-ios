import Foundation
import XCTest
@testable import Weyda

/// « Mes données » (AccountDataViewModel.kt, sans test Android : cas tirés de l'écran et du contrat de la phase 3) :
/// choix de la preuve (mot de passe, Google, Apple), export partagé une fois puis repartageable, suppression confirmée
/// qui ferme la session, refus et annulations. Données fictives.
final class AccountDataViewModelTests: XCTestCase {
    /// Fausse API + session ouverte (Amina, `user_1`) + repository écrivant dans un dossier jetable.
    @MainActor
    private struct Fixture {
        let api: FakeWeydaAPI
        let session: SessionManager
        let accountData: AccountDataRepository
        let directory: URL
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        session.signIn(FakeWeydaAPI.tokens())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weyda-account-data-\(UUID().uuidString)", isDirectory: true)
        let accountData = AccountDataRepository(api: api, session: session, temporaryDirectory: directory)
        return Fixture(api: api, session: session, accountData: accountData, directory: directory)
    }

    @MainActor
    private func makeModel(
        _ fixture: Fixture,
        methods: AccountSignInMethods? = nil,
        apple: @escaping @MainActor () async throws -> AppleCredential = { throw URLError(.cancelled) },
        google: @escaping @MainActor () async throws -> String = { throw URLError(.cancelled) }
    ) -> AccountDataViewModel {
        AccountDataViewModel(
            accountData: fixture.accountData,
            user: fixture.session.user,
            loadSignInMethods: {
                guard let methods else { throw URLError(.notConnectedToInternet) }
                return methods
            },
            appleCredential: apple,
            googleIDToken: google
        )
    }

    // MARK: - Preuve demandée

    func testDeletionMethodPrefersThePasswordThenAppleThenGoogle() {
        XCTAssertEqual(AccountDeletionMethod.resolve(hasPassword: true, providers: ["credentials", "google"]), .password)
        XCTAssertEqual(AccountDeletionMethod.resolve(hasPassword: true, providers: nil), .password)
        XCTAssertEqual(AccountDeletionMethod.resolve(hasPassword: false, providers: ["google"]), .google)
        XCTAssertEqual(AccountDeletionMethod.resolve(hasPassword: false, providers: ["Apple"]), .apple)
        XCTAssertEqual(AccountDeletionMethod.resolve(hasPassword: false, providers: ["google", "apple"]), .apple)
        // Serveur antérieur au lot A (pas de `providers`) : « sans mot de passe » = Google, comme Android.
        XCTAssertEqual(AccountDeletionMethod.resolve(hasPassword: false, providers: nil), .google)
        XCTAssertEqual(AccountSignInMethods(hasPassword: false, providers: ["apple"]).deletionMethod, .apple)
    }

    @MainActor
    func testTheSessionChoosesTheProofUntilTheServerAnswersAndAFailureKeepsIt() async {
        let fixture = makeFixture()
        fixture.session.updateUser { user in
            var google = user
            google.hasPassword = false
            return google
        }
        let model = makeModel(fixture)
        XCTAssertEqual(model.state.method, .google)
        XCTAssertTrue(model.state.canAskDelete)  // aucune saisie pour un compte Google
        await model.loadIfNeeded()?.value  // le serveur ne répond pas : la preuve de la session reste
        XCTAssertEqual(model.state.method, .google)
        XCTAssertNil(model.loadIfNeeded())  // une seule relecture

        let apple = makeModel(fixture, methods: AccountSignInMethods(hasPassword: false, providers: ["apple"]))
        await apple.loadIfNeeded()?.value
        XCTAssertEqual(apple.state.method, .apple)
    }

    // MARK: - Export

    @MainActor
    func testExportOpensTheShareSheetOnceThenStaysShareable() async throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.api.onExportData = { destination in
            let target = try XCTUnwrap(destination)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: target)
            return target
        }
        let model = makeModel(fixture)
        let export = model.export()
        XCTAssertTrue(model.state.isExporting)
        XCTAssertNil(model.export())  // un seul export à la fois
        await export?.value
        let file = try XCTUnwrap(model.state.exportFile)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("weydaa-"))
        XCTAssertEqual(model.state.pendingShare, file)
        XCTAssertFalse(model.state.isExporting)
        XCTAssertNil(model.state.exportError)

        model.exportShared()
        XCTAssertNil(model.state.pendingShare)
        XCTAssertEqual(model.state.exportFile, file)
        XCTAssertEqual(fixture.api.count("exportData"), 1)
    }

    @MainActor
    func testExportRefusedShowsTheMessage() async {
        let fixture = makeFixture()
        fixture.api.onExportData = { _ in throw FakeWeydaAPI.apiError(429, #"{"error":"rateLimited"}"#, retryAfter: "3600") }
        let model = makeModel(fixture)
        await model.export()?.value
        XCTAssertEqual(model.state.exportError, L10n.errorRateLimited)
        XCTAssertNil(model.state.exportFile)
        XCTAssertNil(model.state.pendingShare)
        XCTAssertFalse(model.state.isExporting)
    }

    // MARK: - Suppression

    @MainActor
    func testPasswordDeletionIsConfirmedThenClosesTheSession() async {
        let fixture = makeFixture()
        let model = makeModel(fixture)
        XCTAssertEqual(model.state.method, .password)
        XCTAssertFalse(model.state.canAskDelete)
        model.askDelete()  // mot de passe vide : rien
        XCTAssertFalse(model.state.confirmDelete)
        model.updatePassword("   ")
        model.askDelete()  // que des blancs : rien non plus
        XCTAssertFalse(model.state.confirmDelete)

        model.updatePassword("Secret123")
        model.askDelete()
        XCTAssertTrue(model.state.confirmDelete)
        model.dismissDelete()
        XCTAssertFalse(model.state.confirmDelete)
        XCTAssertEqual(fixture.api.count("deleteAccount"), 0)

        model.askDelete()
        fixture.api.onDeleteAccount = { body in
            XCTAssertEqual(body.password, "Secret123")
            XCTAssertNil(body.googleIdToken)
            XCTAssertNil(body.appleIdentityToken)
            return SimpleResponseDTO()
        }
        let deletion = model.confirmDelete()
        XCTAssertFalse(model.state.confirmDelete)
        XCTAssertTrue(model.state.isDeleting)
        XCTAssertFalse(model.state.canAskDelete)
        await deletion?.value
        XCTAssertTrue(model.state.deleted)
        XCTAssertFalse(model.state.isDeleting)
        XCTAssertEqual(model.state.password, "")  // quitte la mémoire
        XCTAssertFalse(fixture.session.isLoggedIn)
    }

    @MainActor
    func testIncorrectPasswordKeepsTheSessionAndShowsTheError() async {
        let fixture = makeFixture()
        let model = makeModel(fixture)
        model.updatePassword("Faux1234")
        fixture.api.onDeleteAccount = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"incorrectPassword"}"#) }
        await model.confirmDelete()?.value
        XCTAssertEqual(model.state.deleteError, L10n.errorIncorrectPassword)
        XCTAssertFalse(model.state.isDeleting)
        XCTAssertFalse(model.state.deleted)
        XCTAssertTrue(fixture.session.isLoggedIn)
        model.updatePassword("Secret123")  // nouvelle saisie : l'erreur s'efface
        XCTAssertNil(model.state.deleteError)
    }

    @MainActor
    func testGoogleAccountIsConfirmedWithAFreshGoogleToken() async {
        let fixture = makeFixture()
        let model = makeModel(
            fixture,
            methods: AccountSignInMethods(hasPassword: false, providers: ["google"]),
            google: { "google-id-token" }
        )
        await model.loadIfNeeded()?.value
        XCTAssertEqual(model.state.method, .google)
        model.askDelete()
        XCTAssertTrue(model.state.confirmDelete)
        fixture.api.onDeleteAccount = { body in
            XCTAssertNil(body.password)
            XCTAssertEqual(body.googleIdToken, "google-id-token")
            return SimpleResponseDTO()
        }
        await model.confirmDelete()?.value
        XCTAssertTrue(model.state.deleted)
        XCTAssertFalse(fixture.session.isLoggedIn)
    }

    @MainActor
    func testAppleAccountSendsIdentityTokenRawNonceAndCode() async {
        let fixture = makeFixture()
        let credential = AppleCredential(
            identityToken: "apple-identity",
            authorizationCode: "apple-code",
            rawNonce: "nonce-clair",
            givenName: nil,
            familyName: nil,
            email: nil
        )
        let model = makeModel(
            fixture,
            methods: AccountSignInMethods(hasPassword: false, providers: ["apple"]),
            apple: { credential }
        )
        await model.loadIfNeeded()?.value
        XCTAssertEqual(model.state.method, .apple)
        fixture.api.onDeleteAccount = { body in
            XCTAssertNil(body.password)
            XCTAssertNil(body.googleIdToken)
            XCTAssertEqual(body.appleIdentityToken, "apple-identity")
            XCTAssertEqual(body.nonce, "nonce-clair")
            XCTAssertEqual(body.appleAuthorizationCode, "apple-code")
            return SimpleResponseDTO()
        }
        await model.confirmDelete()?.value
        XCTAssertTrue(model.state.deleted)
        XCTAssertFalse(fixture.session.isLoggedIn)
    }

    @MainActor
    func testCancelledReauthenticationShowsNothingAndDeletesNothing() async {
        let fixture = makeFixture()
        let model = makeModel(
            fixture,
            methods: AccountSignInMethods(hasPassword: false, providers: ["apple"]),
            apple: { throw CancellationError() }
        )
        await model.loadIfNeeded()?.value
        await model.confirmDelete()?.value
        XCTAssertNil(model.state.deleteError)
        XCTAssertFalse(model.state.isDeleting)
        XCTAssertFalse(model.state.deleted)
        XCTAssertTrue(fixture.session.isLoggedIn)
        XCTAssertEqual(fixture.api.count("deleteAccount"), 0)

        // Reconnexion acceptée mais refusée par le serveur (autre compte Apple) : le message s'affiche.
        let mismatch = makeModel(
            fixture,
            methods: AccountSignInMethods(hasPassword: false, providers: ["google"]),
            google: { "other-google-token" }
        )
        await mismatch.loadIfNeeded()?.value
        fixture.api.onDeleteAccount = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"googleReauthMismatch"}"#) }
        await mismatch.confirmDelete()?.value
        XCTAssertEqual(mismatch.state.deleteError, L10n.errorGoogleReauthMismatch)
        XCTAssertTrue(fixture.session.isLoggedIn)
    }
}

#if DEBUG
/// Données simulées du compte (`MockFixtures/routes-account.json` + `account/`) lues par les VRAIS repositories à
/// travers `LiveWeydaAPI` et l'API simulée : utilisateur de référence identique à la session simulée, 6 annonces de
/// statuts variés filtrables, statistiques cohérentes, export, contact, suppression.
final class MockAccountFixturesTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testReferenceUserListingsByStatusAndStats() async throws {
        let api = try makeAPI()
        // `GET /api/users/me` = l'utilisateur de la session simulée (`-WeydaLoggedIn`), à l'identique.
        let me = try await api.me()
        XCTAssertEqual(me.toDomain(emailVerified: true), MockSessionFixture.user(emailVerified: true))
        XCTAssertEqual(me.providers, ["credentials"])
        XCTAssertEqual(me.hasPassword, true)

        let users = UserRepository(api: api, session: FakeWeydaAPI.makeSession())
        let all = try await users.myListings()
        XCTAssertEqual(all.items.map { $0.id }, ["mock-m3", "mock-m6", "mock-m1", "mock-m4", "mock-m2", "mock-m5"])
        XCTAssertEqual(Set(all.items.map { $0.listingStatus }), Set(ListingStatus.allCases))
        XCTAssertTrue(all.items.allSatisfy { $0.coverImage != nil && $0.commune != nil })
        for status in ListingStatus.allCases {
            let page = try await users.myListings(status: status)
            XCTAssertFalse(page.items.isEmpty, status.rawValue)
            XCTAssertTrue(page.items.allSatisfy { $0.listingStatus == status }, status.rawValue)
        }
        let rejected = try await users.myListings(status: .rejected)
        XCTAssertEqual(rejected.items.map { $0.id }, ["mock-m6"])
        XCTAssertEqual(MyListingsText.moderationReasons(for: rejected.items[0]).count, 2)

        let stats = try await users.stats()
        XCTAssertEqual(stats.totalViews, all.items.reduce(0) { $0 + $1.views })
        XCTAssertEqual(stats.activeCount, all.items.filter { $0.listingStatus == .active }.count)
        XCTAssertEqual(stats.pendingCount, all.items.filter { $0.listingStatus == .pending }.count)
        XCTAssertEqual(stats.soldCount, all.items.filter { $0.listingStatus == .sold }.count)
        XCTAssertEqual(stats.expiredCount, all.items.filter { $0.listingStatus == .expired }.count)
    }

    @MainActor
    func testProfileUpdateLocaleExportContactAndDeletion() async throws {
        let api = try makeAPI()
        let session = FakeWeydaAPI.makeSession()
        let users = UserRepository(api: api, session: session)
        let saved = await users.syncLocale("ar")
        XCTAssertTrue(saved)
        let updated = try await api.updateMe(UpdateProfileRequestDTO(name: "Yacine Benali"))
        XCTAssertEqual(updated.id, "mock-me")
        _ = try await api.changePassword(
            ChangePasswordRequestDTO(currentPassword: "Ancien123", newPassword: "Nouveau123", confirmPassword: "Nouveau123")
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weyda-mock-account-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountData = AccountDataRepository(api: api, session: session, temporaryDirectory: directory)
        let file = try await accountData.export()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let profile = json?["profile"] as? [String: Any]
        XCTAssertEqual(profile?["id"] as? String, "mock-me")

        let sent = try await api.contact(
            ContactRequestDTO(name: "Test", email: "test@example.com", subject: "Sujet", message: "Message de test.")
        )
        XCTAssertTrue(sent.success)
        try await accountData.deleteAccount(password: "Secret123")
        XCTAssertFalse(session.isLoggedIn)
    }
}
#endif
