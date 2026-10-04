import Combine
import Foundation
import XCTest
@testable import Weyda

/// « Laisser un avis » depuis le profil public (`GET /api/reviews/eligibility`, `POST /api/reviews`) — portage de
/// SellerReviewTest (SellerProfileTest.kt, Android), cas par cas, et des parties ViewModel de ReviewsRepositoryTest.kt ;
/// en plus : visiteur et propre profil sans requête, éligibilité silencieuse, chaque refus du serveur, panne réseau
/// gardée dans la feuille, droit perdu à l'ouverture, connexion depuis le profil. Données fictives.
final class SellerReviewTests: XCTestCase {
    // MARK: - Données

    static func member(_ id: String = "u1") -> User {
        User(id: id, name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: true)
    }

    /// Fiche du vendeur, vitrine vide et un avis reçu (Android : `setUp` de SellerReviewTest) ; l'éligibilité est
    /// définie par chaque test.
    @MainActor
    private func makeAPI() -> FakeWeydaAPI {
        let api = FakeWeydaAPI()
        api.onPublicProfile = { _ in UserRefDTO(id: "u9", name: "Yacine B.", ratingCount: 1, ratingSum: 4) }
        api.onPublicAnnonces = { _, _, _ in AnnoncesPageDTO(annonces: [], total: 0, page: 1, totalPages: 0) }
        api.onGetReviews = { _, _, limit in
            XCTAssertEqual(limit, SellerViewModel.reviewsShown)
            return ReviewsDTO(
                reviews: [ReviewDTO(id: "r1", rating: 4, comment: "Vendeur sérieux", createdAt: "2026-09-01T10:00:00.000Z")],
                total: 1,
                ratingCount: 1,
                average: 4
            )
        }
        return api
    }

    @MainActor
    private func makeModel(api: FakeWeydaAPI, session: AnyPublisher<User?, Never>) -> SellerViewModel {
        SellerViewModel(
            id: "u9",
            sellers: SellerRepository(api: api),
            favorites: FavoritesRepository(api: api),
            reviews: ReviewsRepository(api: api),
            reports: ReportsRepository(api: api),
            conversations: ConversationsRepository(api: api),
            sessionUser: session
        )
    }

    @MainActor
    private func makeModel(api: FakeWeydaAPI, user: User?) -> SellerViewModel {
        makeModel(api: api, session: Just(user).eraseToAnyPublisher())
    }

    /// Laisse tourner les tâches du ViewModel (fil principal) jusqu'à la condition, 2 s au plus.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - SellerReviewTest (Android)

    @MainActor
    func testWithoutContactWithTheSellerThereIsNoReviewButton() async {
        let api = makeAPI()
        api.onReviewEligibility = { target in
            XCTAssertEqual(target, "u9")
            return ReviewEligibilityDTO(canReview: false)
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()

        XCTAssertFalse(model.state.canReview)
        XCTAssertFalse(model.state.hasMyReview)
        XCTAssertEqual(model.state.reviews?.reviews.count, 1)
        XCTAssertEqual(api.count("reviewEligibility"), 1)
        // Sans bouton, une ouverture forcée ne fait rien (pas de requête, pas de feuille).
        await model.openReview()
        XCTAssertFalse(model.isReviewPresented)
        XCTAssertEqual(api.count("reviewEligibility"), 1)
    }

    @MainActor
    func testAnExistingReviewOpensTheSheetReadyToEdit() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in
            ReviewEligibilityDTO(canReview: true, existingReview: ExistingReviewDTO(rating: 3, comment: "  Correct.  "))
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        XCTAssertTrue(model.state.canReview)
        XCTAssertTrue(model.state.hasMyReview)

        await model.openReview()
        XCTAssertTrue(model.isReviewPresented)
        XCTAssertEqual(model.reviewRating, 3)
        XCTAssertEqual(model.reviewComment, "Correct.")
        XCTAssertTrue(model.state.isReviewEditing)
        XCTAssertFalse(model.state.isReviewOpening)
        // Mon avis courant est relu à l'ouverture (la feuille ne doit pas écraser un avis modifié ailleurs).
        XCTAssertEqual(api.count("reviewEligibility"), 2)
    }

    @MainActor
    func testPublishingClampsTheRatingCutsTheCommentAndReloadsTheProfile() async {
        let api = makeAPI()
        let sent = FakeWeydaAPI.Box<ReviewCreateRequestDTO?>(nil)
        // Le serveur fait un upsert : après publication, l'éligibilité renvoie mon avis.
        api.onReviewEligibility = { _ in
            ReviewEligibilityDTO(
                canReview: true,
                existingReview: sent.value.map { ExistingReviewDTO(rating: $0.rating, comment: $0.comment) }
            )
        }
        api.onSubmitReview = { body in
            sent.value = body
            return ReviewDTO(id: "r2", rating: body.rating)
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        XCTAssertFalse(model.state.hasMyReview)

        await model.openReview()
        XCTAssertTrue(model.isReviewPresented)
        XCTAssertFalse(model.state.isReviewEditing)
        XCTAssertEqual(model.reviewRating, SellerViewModel.defaultRating)
        XCTAssertEqual(model.reviewComment, "")

        model.reviewRating = 9
        model.reviewComment = String(repeating: "x", count: 1500)
        await model.confirmReview()

        XCTAssertEqual(sent.value?.targetId, "u9")
        XCTAssertEqual(sent.value?.rating, 5)
        XCTAssertEqual(sent.value?.comment?.count, MyReview.commentMax)
        XCTAssertFalse(model.isReviewPresented)
        XCTAssertFalse(model.state.isReviewBusy)
        XCTAssertTrue(model.state.hasMyReview)
        XCTAssertEqual(model.state.notice, L10n.reviewSent)
        // Note du vendeur et avis recalculés par le serveur : fiche et avis relus.
        XCTAssertEqual(api.count("publicProfile"), 2)
        XCTAssertEqual(api.count("getReviews"), 2)

        // Rouverte, la feuille reprend mon avis.
        model.noticeShown()
        await model.openReview()
        XCTAssertTrue(model.state.isReviewEditing)
        XCTAssertEqual(model.reviewRating, 5)
        XCTAssertEqual(model.reviewComment.count, MyReview.commentMax)
    }

    @MainActor
    func testAServerRefusal403NotEligibleIsShownAsAMessage() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in ReviewEligibilityDTO(canReview: true) }
        api.onSubmitReview = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"notEligible"}"#) }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        await model.openReview()
        await model.confirmReview()

        XCTAssertFalse(model.isReviewPresented)
        XCTAssertNil(model.state.reviewError)
        XCTAssertEqual(model.state.notice, L10n.errorReviewNotEligible)
        model.noticeShown()
        XCTAssertNil(model.state.notice)
    }

    // MARK: - En plus d'Android

    @MainActor
    func testEveryServerVerdictClosesTheSheetWithItsTranslatedMessage() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in ReviewEligibilityDTO(canReview: true) }
        let model = makeModel(api: api, user: Self.member())
        await model.load()

        let verdicts: [(status: Int, code: String, message: String)] = [
            (403, "emailNotVerified", L10n.errorEmailNotVerified),
            (403, "userBlocked", L10n.errorUserBlocked),
            (400, "ownReviewError", L10n.errorOwnReview),
        ]
        for verdict in verdicts {
            let status = verdict.status
            let body = "{\"error\":\"\(verdict.code)\"}"
            api.onSubmitReview = { _ in throw FakeWeydaAPI.apiError(status, body) }
            model.noticeShown()
            await model.openReview()
            XCTAssertTrue(model.isReviewPresented, verdict.code)
            await model.confirmReview()
            XCTAssertFalse(model.isReviewPresented, verdict.code)
            XCTAssertFalse(model.state.isReviewBusy, verdict.code)
            XCTAssertEqual(model.state.notice, verdict.message, verdict.code)
        }
    }

    @MainActor
    func testANetworkFailureKeepsTheSheetOpenWithTheDraft() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in ReviewEligibilityDTO(canReview: true) }
        api.onSubmitReview = { _ in throw URLError(.notConnectedToInternet) }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        await model.openReview()

        model.reviewRating = 2
        model.reviewComment = "Annonce conforme, mais vendeur difficile à joindre."
        await model.confirmReview()

        XCTAssertTrue(model.isReviewPresented)
        XCTAssertFalse(model.state.isReviewBusy)
        XCTAssertEqual(model.state.reviewError, L10n.errorOffline)
        XCTAssertNil(model.state.notice)
        XCTAssertEqual(model.reviewRating, 2)
        XCTAssertEqual(model.reviewComment, "Annonce conforme, mais vendeur difficile à joindre.")

        // Réseau revenu : le nouvel envoi passe, l'erreur disparaît.
        api.onSubmitReview = { body in ReviewDTO(id: "r3", rating: body.rating) }
        await model.confirmReview()
        XCTAssertFalse(model.isReviewPresented)
        XCTAssertNil(model.state.reviewError)
        XCTAssertEqual(model.state.notice, L10n.reviewSent)
    }

    @MainActor
    func testCancellingClosesTheSheetAndClearsTheError() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in ReviewEligibilityDTO(canReview: true) }
        api.onSubmitReview = { _ in throw URLError(.timedOut) }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        await model.openReview()
        await model.confirmReview()
        XCTAssertNotNil(model.state.reviewError)

        model.dismissReview()
        XCTAssertFalse(model.isReviewPresented)
        XCTAssertNil(model.state.reviewError)
        // Envoi sans feuille ouverte : ignoré.
        await model.confirmReview()
        XCTAssertEqual(api.count("submitReview"), 1)
    }

    @MainActor
    func testVisitorAndOwnProfileNeverAskForTheRightToReview() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in
            XCTFail("éligibilité demandée pour un visiteur ou sur mon propre profil")
            return ReviewEligibilityDTO(canReview: true)
        }
        let visitor = makeModel(api: api, user: nil)
        await visitor.load()
        XCTAssertFalse(visitor.state.canReview)

        let own = makeModel(api: api, user: Self.member("u9"))
        await own.load()
        XCTAssertTrue(own.state.isOwnProfile)
        XCTAssertFalse(own.state.canReview)
        XCTAssertEqual(api.count("reviewEligibility"), 0)
    }

    @MainActor
    func testAnEligibilityFailureIsSilent() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in throw FakeWeydaAPI.apiError(500, #"{"error":"serverError"}"#) }
        let model = makeModel(api: api, user: Self.member())
        await model.load()

        XCTAssertEqual(model.state.seller?.name, "Yacine B.")
        XCTAssertFalse(model.state.canReview)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertNil(model.state.notice)
    }

    @MainActor
    func testAnOpeningFailureShowsTheMessageInsteadOfAnEmptySheet() async {
        let api = makeAPI()
        let offline = FakeWeydaAPI.Box<Bool>(false)
        api.onReviewEligibility = { _ in
            if offline.value {
                throw URLError(.notConnectedToInternet)
            }
            return ReviewEligibilityDTO(canReview: true, existingReview: ExistingReviewDTO(rating: 4, comment: "Bien"))
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        XCTAssertTrue(model.state.hasMyReview)

        // Sans mon avis courant, la feuille s'ouvrirait vide et l'envoi ÉCRASERAIT l'avis existant.
        offline.value = true
        await model.openReview()
        XCTAssertFalse(model.isReviewPresented)
        XCTAssertFalse(model.state.isReviewOpening)
        XCTAssertEqual(model.state.notice, L10n.errorOffline)
    }

    @MainActor
    func testARightLostSinceLoadingHidesTheButtonWithTheReason() async {
        let api = makeAPI()
        let allowed = FakeWeydaAPI.Box<Bool>(true)
        api.onReviewEligibility = { _ in ReviewEligibilityDTO(canReview: allowed.value) }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        XCTAssertTrue(model.state.canReview)

        allowed.value = false
        await model.openReview()
        XCTAssertFalse(model.isReviewPresented)
        XCTAssertFalse(model.state.canReview)
        XCTAssertEqual(model.state.notice, L10n.errorReviewNotEligible)
    }

    @MainActor
    func testAnOutOfRangeExistingRatingIsBroughtBackToOneStar() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in
            ReviewEligibilityDTO(canReview: true, existingReview: ExistingReviewDTO(rating: 0, comment: nil))
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()
        await model.openReview()
        XCTAssertEqual(model.reviewRating, 1)
        XCTAssertEqual(model.reviewComment, "")
    }

    @MainActor
    func testLoggingInFromTheProfileReadsTheRightToReview() async {
        let api = makeAPI()
        api.onReviewEligibility = { _ in ReviewEligibilityDTO(canReview: true) }
        let session = CurrentValueSubject<User?, Never>(nil)
        let model = makeModel(api: api, session: session.eraseToAnyPublisher())
        await model.load()
        XCTAssertFalse(model.state.canReview)
        XCTAssertEqual(api.count("reviewEligibility"), 0)

        // Connexion faite depuis ce profil (Android : `refreshEligibility`).
        session.send(Self.member())
        await waitUntil { model.state.canReview }
        XCTAssertTrue(model.state.canReview)
        XCTAssertEqual(api.count("reviewEligibility"), 1)

        // Déconnexion : le bouton disparaît, sans requête.
        session.send(nil)
        await waitUntil { !model.state.canReview }
        XCTAssertFalse(model.state.canReview)
        XCTAssertEqual(api.count("reviewEligibility"), 1)
    }
}

#if DEBUG
/// Données simulées des avis (`MockFixtures/routes-reviews.json` + `reviews/`) lues par le vrai repository : droit de
/// noter Karim (mock-u1, sans avis), avis existant sur Amina (mock-u2), refus pour les autres, publication.
final class MockReviewsFixturesTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testEligibilityAndPublicationAnswerLikeTheServer() async throws {
        let repository = ReviewsRepository(api: try makeAPI())

        let karim = try await repository.eligibility(sellerId: "mock-u1")
        XCTAssertTrue(karim.canReview)
        XCTAssertNil(karim.existing)

        let amina = try await repository.eligibility(sellerId: "mock-u2")
        XCTAssertTrue(amina.canReview)
        XCTAssertEqual(amina.existing?.rating, 4)
        XCTAssertFalse(TextCheck.isBlank(amina.existing?.comment))

        let other = try await repository.eligibility(sellerId: "mock-u3")
        XCTAssertFalse(other.canReview)
        XCTAssertNil(other.existing)

        try await repository.submit(sellerId: "mock-u1", rating: 4, comment: SellerReviewDemo.comment(language: "fr"))
    }
}
#endif
