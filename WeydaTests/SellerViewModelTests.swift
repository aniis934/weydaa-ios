import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage des parties ViewModel de SellerProfileTest.kt (Android) : fiche du vendeur, vitrine paginée, compte banni,
/// vitrine en échec, avis montrés ; en plus : signaler / bloquer depuis le profil, mon propre profil. « Laisser un
/// avis » (SellerReviewTest) arrive avec la phase 6. Données fictives.
final class SellerViewModelTests: XCTestCase {
    // MARK: - Données

    static func profileDTO() -> UserRefDTO {
        UserRefDTO(
            id: "u9",
            name: "Yacine B.",
            createdAt: "2024-05-02T08:00:00.000Z",
            emailVerified: "2024-05-03T08:00:00.000Z",
            bio: "  Vendeur particulier à Alger.  ",
            isRecommended: true,
            ratingCount: 4,
            ratingSum: 18,
            responseMinutes: 30,
            count: CountDTO(annonces: 14)
        )
    }

    static func annonce(_ id: String) -> AnnonceDTO {
        AnnonceDTO(id: id, title: "Annonce \(id)", createdAt: "2026-09-01T10:00:00.000Z")
    }

    static func member(_ id: String = "u1") -> User {
        User(id: id, name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: true)
    }

    /// Par défaut : aucun avis (les tests concernés le redéfinissent).
    @MainActor
    private func makeAPI() -> FakeWeydaAPI {
        let api = FakeWeydaAPI()
        api.onGetReviews = { _, _, _ in ReviewsDTO() }
        return api
    }

    @MainActor
    private func makeModel(api: FakeWeydaAPI, user: User? = nil) -> SellerViewModel {
        SellerViewModel(
            id: "u9",
            sellers: SellerRepository(api: api),
            favorites: FavoritesRepository(api: api),
            reviews: ReviewsRepository(api: api),
            reports: ReportsRepository(api: api),
            conversations: ConversationsRepository(api: api),
            sessionUser: Just(user).eraseToAnyPublisher()
        )
    }

    // MARK: - SellerProfileTest.kt

    @MainActor
    func testSellerSheetBadgesAverageRatingAndCleanedBio() async {
        let api = makeAPI()
        api.onPublicProfile = { id in
            XCTAssertEqual(id, "u9")
            return Self.profileDTO()
        }
        api.onPublicAnnonces = { _, _, _ in AnnoncesPageDTO(annonces: [], total: 0, page: 1, totalPages: 0) }

        let model = makeModel(api: api)
        await model.load()

        let seller = model.state.seller
        XCTAssertEqual(seller?.name, "Yacine B.")
        XCTAssertEqual(seller?.rating ?? 0, 4.5, accuracy: 1e-9)
        XCTAssertEqual(seller?.emailVerified, true)
        XCTAssertEqual(seller?.isRecommended, true)
        XCTAssertEqual(seller?.isFastResponder, true)
        XCTAssertEqual(seller?.activeListings, 14)
        XCTAssertEqual(seller?.bio, "Vendeur particulier à Alger.")
        XCTAssertEqual(TrustBadge.badges(for: Self.profileDTO().toDomain()), [.recommended, .verified, .fastResponder])
        // Vitrine vide : ce n'est pas une erreur, la fiche reste affichée.
        XCTAssertNil(model.state.errorMessage)
        XCTAssertFalse(model.state.isLoading)
        XCTAssertTrue(model.state.items.isEmpty)
    }

    @MainActor
    func testShowcasePageTwoIsAppendedAndPaginationStopsAtTheEnd() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in Self.profileDTO() }
        api.onPublicAnnonces = { _, page, limit in
            XCTAssertEqual(limit, 12)
            if page == 1 {
                return AnnoncesPageDTO(annonces: [Self.annonce("a1"), Self.annonce("a2")], total: 3, page: 1, totalPages: 2)
            }
            return AnnoncesPageDTO(annonces: [Self.annonce("a3")], total: 3, page: 2, totalPages: 2)
        }

        let model = makeModel(api: api)
        await model.load()
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2"])
        XCTAssertTrue(model.state.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2", "a3"])
        XCTAssertFalse(model.state.hasMore)
        XCTAssertFalse(model.state.isLoadingMore)

        // Plus rien à charger : un nouvel appel ne relance aucune requête.
        api.onPublicAnnonces = { _, _, _ in
            XCTFail("pagination relancée alors que tout est chargé")
            return AnnoncesPageDTO()
        }
        await model.loadMore()
        XCTAssertEqual(model.state.items.count, 3)
        XCTAssertEqual(api.count("publicAnnonces"), 2)
    }

    @MainActor
    func testBannedAccount404ShowsAnErrorWithoutAskingForTheShowcase() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"userNotFound"}"#) }
        api.onPublicAnnonces = { _, _, _ in
            XCTFail("vitrine demandée sans fiche")
            return AnnoncesPageDTO()
        }

        let model = makeModel(api: api)
        await model.load()

        XCTAssertNil(model.state.seller)
        XCTAssertEqual(model.state.errorMessage, L10n.errorUserNotFound)
        XCTAssertEqual(api.count("publicAnnonces"), 0)
        XCTAssertFalse(model.state.canModerate)
    }

    @MainActor
    func testShowcaseFailureKeepsTheSheetWithoutPagination() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in Self.profileDTO() }
        api.onPublicAnnonces = { _, _, _ in throw FakeWeydaAPI.apiError(500, #"{"error":"serverError"}"#) }

        let model = makeModel(api: api)
        await model.load()

        XCTAssertEqual(model.state.seller?.name, "Yacine B.")
        XCTAssertNil(model.state.errorMessage)
        XCTAssertFalse(model.state.hasMore)
        XCTAssertFalse(model.state.isLoadingMore)
    }

    @MainActor
    func testAPageOverlapIsNotShownTwice() async {
        // Pagination par décalage : une annonce publiée entre deux pages ramène la dernière de la page 1 en tête de
        // la page 2.
        let api = makeAPI()
        api.onPublicProfile = { _ in Self.profileDTO() }
        api.onPublicAnnonces = { _, page, _ in
            if page == 1 {
                return AnnoncesPageDTO(annonces: [Self.annonce("a1"), Self.annonce("a2")], total: 4, page: 1, totalPages: 2)
            }
            return AnnoncesPageDTO(annonces: [Self.annonce("a2"), Self.annonce("a3")], total: 4, page: 2, totalPages: 2)
        }
        let model = makeModel(api: api)
        await model.load()
        await model.loadMore()
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2", "a3"])
    }

    // MARK: - Avis (SellerReviewTest.kt, lecture seule)

    @MainActor
    func testTheFirstFiveReviewsAreShown() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in UserRefDTO(id: "u9", name: "Yacine B.", ratingCount: 1, ratingSum: 4) }
        api.onPublicAnnonces = { _, _, _ in AnnoncesPageDTO(annonces: [], total: 0, page: 1, totalPages: 0) }
        api.onGetReviews = { target, _, limit in
            XCTAssertEqual(target, "u9")
            XCTAssertEqual(limit, SellerViewModel.reviewsShown)
            return ReviewsDTO(
                reviews: [ReviewDTO(id: "r1", rating: 4, comment: "Vendeur sérieux", createdAt: "2026-09-01T10:00:00.000Z")],
                total: 1,
                ratingCount: 1,
                average: 4
            )
        }
        let model = makeModel(api: api)
        await model.load()
        XCTAssertEqual(model.state.reviews?.reviews.count, 1)
        XCTAssertEqual(model.state.reviews?.average ?? 0, 4, accuracy: 1e-9)
        // Visiteur : l'éligibilité (bouton « Laisser un avis ») n'est jamais demandée (membre seulement, phase 6).
        XCTAssertEqual(api.count("reviewEligibility"), 0)
    }

    // MARK: - Signaler / bloquer

    @MainActor
    func testReportingTheSellerSendsTheUserWithoutAListing() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in Self.profileDTO() }
        api.onPublicAnnonces = { _, _, _ in AnnoncesPageDTO() }
        let sent = FakeWeydaAPI.Box<ReportRequestDTO?>(nil)
        api.onReport = { body in
            sent.value = body
            return ReportDTO(id: "rep1")
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()

        model.openReport()
        XCTAssertTrue(model.isReportPresented)
        await model.confirmReport(reason: .fraud, details: "  Demande un acompte par virement.  ")
        XCTAssertEqual(sent.value?.reportedUserId, "u9")
        XCTAssertNil(sent.value?.annonceId)
        XCTAssertNil(sent.value?.conversationId)
        XCTAssertEqual(sent.value?.reason, "FRAUD")
        XCTAssertEqual(sent.value?.details, "Demande un acompte par virement.")
        XCTAssertFalse(model.isReportPresented)
        XCTAssertEqual(model.state.notice, L10n.reportSent)

        // Refus du serveur (soi-même, déjà signalé…) : la feuille se ferme avec le message.
        model.noticeShown()
        api.onReport = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"alreadyReported"}"#) }
        model.openReport()
        await model.confirmReport(reason: .spam, details: "")
        XCTAssertFalse(model.isReportPresented)
        XCTAssertEqual(model.state.notice, L10n.errorAlreadyReported)
    }

    @MainActor
    func testBlockingAsksForConfirmationThenUnblockingIsImmediate() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in Self.profileDTO() }
        api.onPublicAnnonces = { _, _, _ in AnnoncesPageDTO() }
        let blocked = FakeWeydaAPI.Box<[String]>([])
        api.onBlockUser = { id in
            blocked.value.append("block \(id)")
            return SimpleResponseDTO()
        }
        api.onUnblockUser = { id in
            blocked.value.append("unblock \(id)")
            return SimpleResponseDTO()
        }
        let model = makeModel(api: api, user: Self.member())
        await model.load()

        model.requestBlock()
        XCTAssertTrue(model.isBlockConfirmPresented)
        await model.setBlocked(true)
        XCTAssertTrue(model.state.isBlocked)
        XCTAssertEqual(model.state.notice, L10n.chatBlockedDone)

        await model.setBlocked(false)
        XCTAssertFalse(model.state.isBlocked)
        XCTAssertEqual(model.state.notice, L10n.chatUnblockedDone)
        XCTAssertEqual(blocked.value, ["block u9", "unblock u9"])

        // Échec : l'état ne change pas, le message s'affiche.
        api.onBlockUser = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"cannotBlockSelf"}"#) }
        await model.setBlocked(true)
        XCTAssertFalse(model.state.isBlocked)
        XCTAssertFalse(model.state.isBlockBusy)
        XCTAssertNotNil(model.state.notice)
    }

    @MainActor
    func testMyOwnProfileOffersNeitherReportNorBlock() async {
        let api = makeAPI()
        api.onPublicProfile = { _ in Self.profileDTO() }
        api.onPublicAnnonces = { _, _, _ in AnnoncesPageDTO() }
        let model = makeModel(api: api, user: Self.member("u9"))
        await model.load()
        XCTAssertTrue(model.state.isOwnProfile)
        XCTAssertFalse(model.state.canModerate)
        model.openReport()
        model.requestBlock()
        XCTAssertFalse(model.isReportPresented)
        XCTAssertFalse(model.isBlockConfirmPresented)
    }

    // MARK: - Règles pures

    func testPaginationStartsNearTheEndOfTheShowcase() {
        let items = ["a1", "a2", "a3", "a4"].map { Self.annonce($0).toDomain() }
        XCTAssertFalse(SellerPaging.isNearEnd("a1", in: items))
        XCTAssertFalse(SellerPaging.isNearEnd("a2", in: items))
        XCTAssertTrue(SellerPaging.isNearEnd("a3", in: items))
        XCTAssertTrue(SellerPaging.isNearEnd("a4", in: items))
        XCTAssertFalse(SellerPaging.isNearEnd("inconnue", in: items))
    }

    func testTheSpokenRatingReadsTheAverageThenTheCount() {
        XCTAssertEqual(
            DetailRatingText.spoken(4.5, count: 12),
            "\(RatingStarSymbols.spokenLabel(4.5)) (\(Format.count(12)))"
        )
    }
}
