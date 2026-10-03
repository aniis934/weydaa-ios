import Foundation

/// Profil public d'un vendeur : sa fiche (`GET /api/users/{id}`) et sa vitrine (`GET /api/users/{id}/annonces`,
/// annonces actives seulement), comme la page `/[locale]/profil/[id]` du site — portage de `SellerRepository`.
final class SellerRepository {
    /// Même page que la vitrine du site (12 annonces).
    static let pageSize = 12

    private let api: any WeydaAPI

    init(api: any WeydaAPI) {
        self.api = api
    }

    /// 404 `userNotFound` : compte banni ou supprimé.
    func profile(id: String) async throws -> Seller {
        try await api.publicProfile(id: id).toDomain()
    }

    /// `limit` : `pageSize` (12) par défaut, borné à 1–48.
    func listings(id: String, page: Int = 1, limit: Int = 12) async throws -> ListingPage {
        try await api.publicAnnonces(id: id, page: page, limit: RepositorySupport.clamp(limit, 1, 48)).toDomain()
    }
}

/// Avis reçus par un vendeur (`GET /api/reviews`, public) et dépôt de mon avis — portage de `ReviewsRepository`.
final class ReviewsRepository {
    private let api: any WeydaAPI

    init(api: any WeydaAPI) {
        self.api = api
    }

    /// Première page des avis (`limit` 1–50) et moyenne calculée par le serveur sur tous les avis.
    func forSeller(_ sellerId: String, limit: Int = 3) async throws -> ReviewSummary {
        try await api.getReviews(targetId: sellerId, page: 1, limit: RepositorySupport.clamp(limit, 1, 50)).toDomain()
    }

    /// Droit de noter ce vendeur (contact avéré, e-mail vérifié) et avis déjà déposé le cas échéant.
    func eligibility(sellerId: String) async throws -> ReviewEligibility {
        let dto = try await api.reviewEligibility(targetId: sellerId)
        let existing = dto.existingReview.map { review in
            MyReview(rating: review.rating, comment: RepositorySupport.trimmedOrNil(review.comment))
        }
        return ReviewEligibility(canReview: dto.canReview, existing: existing)
    }

    /// Dépose ou remplace mon avis (le serveur fait un upsert et recalcule la note du vendeur) : note bornée à 1–5,
    /// commentaire nettoyé et coupé à `MyReview.commentMax`.
    func submit(sellerId: String, rating: Int, comment: String?) async throws {
        let body = ReviewCreateRequestDTO(
            targetId: sellerId,
            rating: RepositorySupport.clamp(rating, 1, 5),
            comment: RepositorySupport.trimmedAndCut(comment, max: MyReview.commentMax)
        )
        _ = try await api.submitReview(body)
    }
}

/// Signalements (`POST /api/reports`, session + e-mail vérifié ; 409 `alreadyReported`) — portage de `ReportsRepository`.
final class ReportsRepository {
    private let api: any WeydaAPI

    init(api: any WeydaAPI) {
        self.api = api
    }

    /// Signalement d'une annonce : motif en clair (`FRAUD`…), précisions nettoyées.
    func report(annonceId: String, reason: ReportReason, details: String?) async throws {
        let body = ReportRequestDTO(annonceId: annonceId, reason: reason.rawValue, details: Self.clean(details))
        _ = try await api.report(body)
    }

    /// Signalement d'un UTILISATEUR (contenu publié par les utilisateurs), depuis un fil (`conversationId`, contexte
    /// pour la modération) ou un profil vendeur. 400 `cannotReportSelf`, 409 `alreadyReported`.
    func reportUser(userId: String, conversationId: String?, reason: ReportReason, details: String?) async throws {
        let body = ReportRequestDTO(
            reportedUserId: userId,
            conversationId: conversationId,
            reason: reason.rawValue,
            details: Self.clean(details)
        )
        _ = try await api.report(body)
    }

    /// Le serveur borne `details` à 1000 caractères : on coupe plutôt que de récolter un 400 ; vide → `nil`.
    private static func clean(_ details: String?) -> String? {
        RepositorySupport.trimmedAndCut(details, max: ReportReason.detailsMax)
    }
}
