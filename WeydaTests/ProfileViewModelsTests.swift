import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage de ProfileViewModelsTest.kt (Android) : profil (profil complet + statistiques, déconnexion), mes annonces
/// (filtre, pagination, actions vendu / renouveler / supprimer), modifier le profil, changer le mot de passe — mêmes cas.
/// En plus : textes d'une ligne de « Mes annonces » (motifs de modération). Données fictives.
final class ProfileViewModelsTests: XCTestCase {
    /// Session ouverte au nom d'Amina (`user_1`), e-mail vérifié — le `setUp` d'Android.
    @MainActor
    private func signedIn() async throws -> (api: FakeWeydaAPI, session: SessionManager, auth: AuthRepository, users: UserRepository) {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        let auth = AuthRepository(api: api, session: session)
        let users = UserRepository(api: api, session: session)
        api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: true) }
        _ = try await auth.login(email: "amina@example.com", password: "Secret123")
        return (api, session, auth, users)
    }

    @MainActor
    private func makeProfile(_ context: (api: FakeWeydaAPI, session: SessionManager, auth: AuthRepository, users: UserRepository)) -> ProfileViewModel {
        ProfileViewModel(
            users: context.users,
            auth: context.auth,
            userUpdates: context.session.$user.eraseToAnyPublisher()
        )
    }

    // MARK: - Profil

    @MainActor
    func testProfileLoadsMeAndStatsAndAStatsErrorKeepsTheProfile() async throws {
        let context = try await signedIn()
        context.api.onMe = { MeDTO(id: "user_1", name: "Amina", email: "amina@example.com", isRecommended: true) }
        context.api.onMyStats = { UserStatsDTO(activeCount: 3, soldCount: 7) }
        let model = makeProfile(context)
        await model.refreshTask?.value
        XCTAssertEqual(model.state.stats?.activeCount, 3)
        XCTAssertEqual(model.state.user?.isRecommended, true)
        XCTAssertNil(model.state.errorMessage)

        context.api.onMyStats = { throw FakeWeydaAPI.apiError(500) }
        model.refresh()
        await model.refreshTask?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorServer)
        XCTAssertEqual(model.state.stats?.activeCount, 3)  // conservées
        XCTAssertFalse(model.state.isRefreshing)
    }

    @MainActor
    func testProfileLogoutClearsTheObservedUser() async throws {
        let context = try await signedIn()
        context.api.onMe = { throw FakeWeydaAPI.apiError(500) }
        context.api.onMyStats = { throw FakeWeydaAPI.apiError(500) }
        let model = makeProfile(context)
        await model.refreshTask?.value
        XCTAssertEqual(model.state.user?.id, "user_1")
        model.logout()
        XCTAssertNil(model.state.user)
        XCTAssertFalse(context.auth.isLoggedIn)
    }

    // MARK: - Mes annonces

    @MainActor
    func testMyListingsFilterPaginationAndConcatenation() async throws {
        let context = try await signedIn()
        let calls = FakeWeydaAPI.Box<[String]>([])
        context.api.onMyAnnonces = { status, page, _ in
            calls.value.append("\(status ?? "nil")|\(page)")
            return AnnoncesPageDTO(
                annonces: [AnnonceDTO(id: "a\(page)", title: "T\(page)", status: status ?? "ACTIVE")],
                total: 2,
                page: page,
                totalPages: 2
            )
        }
        let model = MyListingsViewModel(users: context.users, annonces: AnnonceRepository(api: context.api))
        await model.appear()?.value
        XCTAssertEqual(calls.value, ["nil|1"])
        XCTAssertEqual(model.state.items.count, 1)
        XCTAssertTrue(model.state.canLoadMore)

        await model.loadMore()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2"])
        XCTAssertFalse(model.state.canLoadMore)

        await model.setFilter(.rejected)?.value
        XCTAssertEqual(calls.value.last, "REJECTED|1")
        XCTAssertEqual(model.state.items.count, 1)
        XCTAssertEqual(model.state.items.first?.listingStatus, .rejected)
        XCTAssertNil(model.setFilter(.rejected))  // même filtre : pas de rechargement
        XCTAssertEqual(calls.value.count, 3)
    }

    @MainActor
    func testMyListingsMarkSoldDeleteRenewAndErrorsAsNotices() async throws {
        let context = try await signedIn()
        let api = context.api
        api.onMyAnnonces = { _, _, _ in
            AnnoncesPageDTO(
                annonces: [
                    AnnonceDTO(id: "a1", title: "Active", status: "ACTIVE"),
                    AnnonceDTO(id: "a2", title: "Expirée", status: "EXPIRED", renewalCount: 1),
                ],
                total: 2,
                page: 1,
                totalPages: 1
            )
        }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let model = MyListingsViewModel(users: context.users, annonces: AnnonceRepository(api: api), now: { now })
        await model.appear()?.value
        let active = model.state.items[0]
        let expired = model.state.items[1]
        XCTAssertTrue(expired.isRenewable())
        XCTAssertEqual(expired.renewalsLeft, 2)
        XCTAssertFalse(active.isRenewable())
        // `expiresAt` court aussi sur une annonce refusée, en attente ou vendue : jamais renouvelable
        // (« Renouveler » la remettrait en ligne sans modération).
        var soon = active
        soon.expiresAt = Date().addingTimeInterval(3600)
        XCTAssertTrue(soon.isRenewable())
        for status in ["REJECTED", "PENDING", "SOLD"] {
            var other = soon
            other.status = status
            XCTAssertFalse(other.isRenewable(), status)
        }

        // Vendu : confirmation puis PUT status=SOLD.
        model.askMarkSold(active)
        XCTAssertEqual(model.state.pendingAction, .markSold(active))
        model.dismissAction()
        XCTAssertNil(model.state.pendingAction)
        model.askMarkSold(active)
        api.onUpdateAnnonce = { id, body in
            XCTAssertEqual(id, "a1")
            XCTAssertEqual(body.status, "SOLD")
            XCTAssertNil(body.title)
            return AnnonceDTO(id: id, title: "Active", status: "SOLD")
        }
        let sold = model.confirmAction()
        XCTAssertEqual(model.state.busyId, "a1")
        await sold?.value
        XCTAssertNil(model.state.busyId)
        XCTAssertEqual(model.state.items[0].listingStatus, .sold)
        XCTAssertEqual(model.state.notice, L10n.myListingSoldDone)
        model.noticeShown()
        XCTAssertNil(model.state.notice)

        // Renouvellement : PATCH renew → ACTIVE, compteur relu depuis `renewalsRemaining`, échéance à +60 jours.
        api.onPatchAnnonce = { id, body in
            XCTAssertEqual(id, "a2")
            XCTAssertEqual(body.action, "renew")
            return RenewResponseDTO(renewalsRemaining: 1)
        }
        await model.renew(expired)?.value
        let renewed = model.state.items[1]
        XCTAssertEqual(renewed.listingStatus, .active)
        XCTAssertEqual(renewed.renewalCount, 2)
        XCTAssertEqual(renewed.expiresAt, now.addingTimeInterval(60 * 24 * 3600))
        XCTAssertEqual(model.state.notice, L10n.myListingRenewed)

        // Renouvellement refusé : message du serveur, liste intacte.
        api.onPatchAnnonce = { _, _ in throw FakeWeydaAPI.apiError(400, #"{"error":"renewalLimitReached","remaining":0}"#) }
        await model.renew(renewed)?.value
        XCTAssertEqual(model.state.notice, L10n.errorRenewalLimit)
        XCTAssertEqual(model.state.items.count, 2)

        // Suppression : DELETE puis retrait de la liste.
        model.askDelete(model.state.items[0])
        api.onDeleteAnnonce = { id in
            XCTAssertEqual(id, "a1")
            return SimpleResponseDTO()
        }
        await model.confirmAction()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["a2"])
        XCTAssertEqual(model.state.total, 1)
        XCTAssertEqual(model.state.notice, L10n.myListingDeleted)
    }

    @MainActor
    func testMyListingsLoadFailureShowsTheErrorAndRetryRecovers() async throws {
        let context = try await signedIn()
        context.api.onMyAnnonces = { _, _, _ in throw FakeWeydaAPI.apiError(500) }
        let model = MyListingsViewModel(users: context.users, annonces: AnnonceRepository(api: context.api))
        await model.appear()?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorServer)
        XCTAssertFalse(model.state.isLoading)
        // Rechargement silencieux impossible tant que rien n'est chargé.
        XCTAssertNil(model.refresh())

        context.api.onMyAnnonces = { _, page, _ in
            AnnoncesPageDTO(annonces: [AnnonceDTO(id: "a1", title: "T1")], total: 1, page: page, totalPages: 1)
        }
        await model.load().value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1"])
    }

    func testModerationReasonsOnlyOffLineAndAtMostThree() {
        var verdict = ModerationVerdict(decision: "REJECT", confidence: 0.9, reasons: ["A", " ", "B", "C", "D"], suggestions: nil)
        let rejected = AnnonceDTO(id: "a1", title: "T", status: "REJECTED").toDomain()
        var listing = rejected
        listing.moderation = verdict
        XCTAssertEqual(MyListingsText.moderationReasons(for: listing), ["A", "B", "C"])
        listing.status = "ACTIVE"
        XCTAssertEqual(MyListingsText.moderationReasons(for: listing), [])
        verdict.reasons = []
        var pending = rejected
        pending.status = "PENDING"
        pending.moderation = verdict
        XCTAssertEqual(MyListingsText.moderationReasons(for: pending), [])
        XCTAssertEqual(MyListingsFilter.all.map { $0.status }, [nil, .active, .pending, .sold, .expired, .rejected])
    }

    // MARK: - Modifier le profil

    @MainActor
    func testEditProfilePrefilledValidatedAndMerged() async throws {
        let context = try await signedIn()
        let api = context.api
        api.onMe = { MeDTO(id: "user_1", name: "Amina", email: "amina@example.com", phone: "0550123456", bio: "Bio") }
        _ = try await context.users.me()
        let model = EditProfileViewModel(users: context.users, auth: context.auth)
        XCTAssertEqual(model.state.name, "Amina")
        XCTAssertEqual(model.state.phone, "0550123456")
        XCTAssertFalse(model.state.emailChanged)
        XCTAssertFalse(model.state.canSubmit)  // profil complet pas encore relu
        await model.loadIfNeeded()?.value
        XCTAssertTrue(model.state.canSubmit)

        model.onBioChange(String(repeating: "x", count: 501))
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.state.bioError, L10n.validationBioMax)

        model.onBioChange("Nouvelle bio")
        model.onEmailChange("new@example.com")
        XCTAssertTrue(model.state.emailChanged)
        api.onUpdateMe = { body in
            MeDTO(id: "user_1", name: body.name, email: body.email ?? "amina@example.com", phone: body.phone, bio: body.bio)
        }
        await model.submit()?.value
        XCTAssertTrue(model.state.saved)
        XCTAssertEqual(context.auth.user?.email, "new@example.com")
        XCTAssertEqual(context.auth.user?.emailVerified, false)
    }

    @MainActor
    func testEditProfilePhoneAndBioComeFromTheServerNeverFromAnIncompleteSession() async throws {
        // Session fraîche : la réponse de connexion ne porte ni téléphone ni bio. Enregistrer sur cette base les
        // effaçait côté serveur (PUT = remplacement). Le formulaire attend donc le vrai profil.
        let context = try await signedIn()
        let api = context.api
        api.onMe = { MeDTO(id: "user_1", name: "Amina", email: "amina@example.com", phone: "0550123456", bio: "Bio") }
        let sent = FakeWeydaAPI.Box<String?>("jamais envoyé")
        api.onUpdateMe = { body in
            sent.value = body.phone
            return MeDTO(id: "user_1", name: body.name, email: "amina@example.com", phone: body.phone, bio: body.bio)
        }
        let model = EditProfileViewModel(users: context.users, auth: context.auth)
        XCTAssertEqual(model.state.phone, "")
        XCTAssertNil(model.submit())  // ignoré tant que le profil n'est pas chargé
        await model.loadIfNeeded()?.value
        XCTAssertEqual(sent.value, "jamais envoyé")
        XCTAssertEqual(model.state.phone, "0550123456")
        XCTAssertEqual(model.state.bio, "Bio")

        model.onNameChange("Amina B.")
        await model.submit()?.value
        XCTAssertEqual(sent.value, "0550123456")

        // Profil illisible : envoi bloqué, nouvelle tentative possible.
        api.onMe = { throw FakeWeydaAPI.apiError(500) }
        let offline = EditProfileViewModel(users: context.users, auth: context.auth)
        await offline.loadIfNeeded()?.value
        XCTAssertEqual(offline.state.loadErrorMessage, L10n.errorServer)
        XCTAssertFalse(offline.state.canSubmit)
        api.onMe = { MeDTO(id: "user_1", name: "Amina", email: "amina@example.com") }
        await offline.load().value
        XCTAssertNil(offline.state.loadErrorMessage)
        XCTAssertTrue(offline.state.canSubmit)
    }

    @MainActor
    func testEditProfileServerFieldErrorsGoUnderTheirFields() async throws {
        let context = try await signedIn()
        context.api.onMe = { MeDTO(id: "user_1", name: "Amina", email: "amina@example.com") }
        let model = EditProfileViewModel(users: context.users, auth: context.auth)
        await model.loadIfNeeded()?.value
        context.api.onUpdateMe = { _ in
            throw FakeWeydaAPI.apiError(400, #"{"error":"invalidData","details":{"fieldErrors":{"email":["validation.emailInvalid"]}}}"#)
        }
        await model.submit()?.value
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertFalse(model.state.saved)
        model.onEmailChange("amina@example.com")
        XCTAssertNil(model.state.emailError)
    }

    // MARK: - Changer le mot de passe

    @MainActor
    func testChangePasswordLocalRulesConfirmationAndSignOutAfterSuccess() async throws {
        let context = try await signedIn()
        let model = ChangePasswordViewModel(users: context.users)
        model.onCurrentChange("old")
        model.onNewChange("Abcdef12")
        model.onConfirmationChange("Abcdef13")
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.state.confirmationError, L10n.changePasswordMismatch)

        model.onConfirmationChange("Abcdef12")
        context.api.onChangePassword = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"incorrectPassword"}"#) }
        await model.submit()?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorIncorrectPassword)
        XCTAssertTrue(context.auth.isLoggedIn)

        context.api.onChangePassword = { body in
            XCTAssertEqual(body.currentPassword, "old")
            XCTAssertEqual(body.newPassword, "Abcdef12")
            XCTAssertEqual(body.confirmPassword, "Abcdef12")
            return SimpleResponseDTO()
        }
        await model.submit()?.value
        XCTAssertTrue(model.state.done)
        XCTAssertFalse(context.auth.isLoggedIn)
        // Les trois mots de passe quittent la mémoire.
        XCTAssertEqual(model.state.currentPassword, "")
        XCTAssertEqual(model.state.newPassword, "")
        XCTAssertEqual(model.state.confirmation, "")
    }
}
