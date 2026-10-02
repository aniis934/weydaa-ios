import Foundation
import XCTest
@testable import Weyda

/// Portage de ReviewsRepositoryTest.kt et des parties repository de SellerProfileTest.kt (Android) : avis du
/// vendeur, éligibilité, dépôt, fiche et vitrine du profil public. Données fictives.
final class ReviewsRepositoryTests: XCTestCase {
    private static func profileDTO() -> UserRefDTO {
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

    // MARK: - Avis

    @MainActor
    func testSellerReviewsBoundedLimitClampedRatingBlankCommentIsNil() async throws {
        let api = FakeWeydaAPI()
        api.onGetReviews = { target, page, limit in
            XCTAssertEqual(target, "u9")
            XCTAssertEqual(page, 1)
            XCTAssertEqual(limit, 3)
            return ReviewsDTO(
                reviews: [
                    ReviewDTO(
                        id: "r1",
                        rating: 5,
                        comment: "Très bon vendeur",
                        createdAt: "2026-09-01T10:00:00.000Z",
                        author: UserRefDTO(id: "u1", name: "Amina")
                    ),
                    ReviewDTO(id: "r2", rating: 9, comment: "  ", author: nil),
                ],
                total: 7,
                ratingCount: 7,
                average: 4.6
            )
        }
        let summary = try await ReviewsRepository(api: api).forSeller("u9")
        XCTAssertEqual(summary.total, 7)
        XCTAssertEqual(summary.average, 4.6, accuracy: 1e-9)
        XCTAssertEqual(summary.reviews[0].authorName, "Amina")
        XCTAssertEqual(summary.reviews[0].rating, 5)
        XCTAssertEqual(summary.reviews[1].rating, 5)
        XCTAssertNil(summary.reviews[1].comment)
        XCTAssertNil(summary.reviews[1].authorName)
    }

    func testTheRealReviewSubmissionResponseDecodesWithAnAuthorWithoutId() throws {
        // Forme exacte de POST /api/reviews (`author: { name }` + isNew) : un DTO intolérant faisait échouer le
        // décodage alors que l'avis était enregistré.
        let body = #"{"id":"r1","authorId":"u1","targetId":"u9","rating":4,"comment":"Sérieux","createdAt":"2026-09-01T10:00:00.000Z","updatedAt":"2026-09-01T10:00:00.000Z","author":{"name":"Amina"},"isNew":true}"#
        let dto = try JSONDecoder().decode(ReviewDTO.self, from: Data(body.utf8))
        XCTAssertEqual(dto.id, "r1")
        XCTAssertEqual(dto.rating, 4)
        XCTAssertEqual(dto.author?.name, "Amina")
    }

    func testSellerBadgesFastResponderAndAverageRating() {
        let fast = Seller(id: "u", name: "N", avatarUrl: nil, memberSince: nil, ratingCount: 2, ratingSum: 9, responseMinutes: 45)
        XCTAssertTrue(fast.isFastResponder)
        XCTAssertEqual(fast.rating ?? 0, 4.5, accuracy: 1e-9)
        XCTAssertFalse(Seller(id: "u", name: "N", avatarUrl: nil, memberSince: nil, responseMinutes: 120).isFastResponder)
        XCTAssertNil(Seller(id: "u", name: "N", avatarUrl: nil, memberSince: nil).rating)
    }

    @MainActor
    func testEligibilityCleansTheExistingReview() async throws {
        let api = FakeWeydaAPI()
        api.onReviewEligibility = { target in
            XCTAssertEqual(target, "u9")
            return ReviewEligibilityDTO(canReview: true, existingReview: ExistingReviewDTO(rating: 3, comment: "  Correct.  "))
        }
        let eligibility = try await ReviewsRepository(api: api).eligibility(sellerId: "u9")
        XCTAssertTrue(eligibility.canReview)
        XCTAssertEqual(eligibility.existing, MyReview(rating: 3, comment: "Correct."))
    }

    @MainActor
    func testSubmitClampsTheRatingAndCutsTheComment() async throws {
        let api = FakeWeydaAPI()
        let repository = ReviewsRepository(api: api)
        let sent = FakeWeydaAPI.Box<ReviewCreateRequestDTO?>(nil)
        api.onSubmitReview = { body in
            sent.value = body
            return ReviewDTO(id: "r2", rating: body.rating)
        }
        try await repository.submit(sellerId: "u9", rating: 9, comment: String(repeating: "x", count: 1500))
        XCTAssertEqual(sent.value?.targetId, "u9")
        XCTAssertEqual(sent.value?.rating, 5)
        XCTAssertEqual(sent.value?.comment?.count, MyReview.commentMax)

        try await repository.submit(sellerId: "u9", rating: 0, comment: "   ")
        XCTAssertEqual(sent.value?.rating, 1)
        XCTAssertNil(sent.value?.comment)

        api.onSubmitReview = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"notEligible"}"#) }
        do {
            try await repository.submit(sellerId: "u9", rating: 4, comment: nil)
            XCTFail("refus attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "notEligible")
        }
    }

    // MARK: - Profil public (SellerProfileTest.kt, parties repository)

    @MainActor
    func testSellerProfileBadgesRatingAndCleanBio() async throws {
        let api = FakeWeydaAPI()
        api.onPublicProfile = { id in
            XCTAssertEqual(id, "u9")
            return ReviewsRepositoryTests.profileDTO()
        }
        let seller = try await SellerRepository(api: api).profile(id: "u9")
        XCTAssertEqual(seller.name, "Yacine B.")
        XCTAssertEqual(seller.rating ?? 0, 4.5, accuracy: 1e-9)
        XCTAssertTrue(seller.emailVerified)
        XCTAssertTrue(seller.isRecommended)
        XCTAssertTrue(seller.isFastResponder)
        XCTAssertEqual(seller.activeListings, 14)
        XCTAssertEqual(seller.bio, "Vendeur particulier à Alger.")
    }

    @MainActor
    func testShowcasePagesOf12AndPaginationEndsOnTheLastPage() async throws {
        let api = FakeWeydaAPI()
        let sellers = SellerRepository(api: api)
        api.onPublicAnnonces = { _, page, limit in
            XCTAssertEqual(limit, SellerRepository.pageSize)
            if page == 1 {
                return AnnoncesPageDTO(
                    annonces: [AnnonceDTO(id: "a1", title: "Annonce a1"), AnnonceDTO(id: "a2", title: "Annonce a2")],
                    total: 3,
                    page: 1,
                    totalPages: 2
                )
            }
            return AnnoncesPageDTO(annonces: [AnnonceDTO(id: "a3", title: "Annonce a3")], total: 3, page: 2, totalPages: 2)
        }
        let first = try await sellers.listings(id: "u9")
        XCTAssertEqual(first.items.map { $0.id }, ["a1", "a2"])
        XCTAssertTrue(first.hasMore)
        let second = try await sellers.listings(id: "u9", page: 2)
        XCTAssertEqual(second.items.map { $0.id }, ["a3"])
        XCTAssertFalse(second.hasMore)
    }

    @MainActor
    func testABannedAccountAnswers404UserNotFound() async throws {
        let api = FakeWeydaAPI()
        api.onPublicProfile = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"userNotFound"}"#) }
        do {
            _ = try await SellerRepository(api: api).profile(id: "u9")
            XCTFail("404 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "userNotFound")
            XCTAssertEqual(ErrorMapper.message(for: error), L10n.errorUserNotFound)
        }
        XCTAssertEqual(api.count("publicAnnonces"), 0)
    }
}
