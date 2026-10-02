import Foundation

// Portage de data/remote/dto/ReviewDtos.kt — avis (docs/API-CONTRACT.md §4).

/// GET /api/reviews?targetId=&page=&limit= (public) : avis reçus par un vendeur + moyenne.
nonisolated struct ReviewsDTO: Decodable, Hashable, Sendable {
    var reviews: [ReviewDTO] = []
    var total: Int = 0
    var totalPages: Int = 1
    var page: Int = 1
    var ratingCount: Int = 0
    var average: Double = 0
}

nonisolated extension ReviewsDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        reviews = container.lenientList(ReviewDTO.self, "reviews")
        total = container.lenientInt("total") ?? 0
        totalPages = container.lenientInt("totalPages") ?? 1
        page = container.lenientInt("page") ?? 1
        ratingCount = container.lenientInt("ratingCount") ?? 0
        average = container.lenientDouble("average") ?? 0
    }
}

nonisolated struct ReviewDTO: Decodable, Hashable, Sendable {
    var id: String
    var rating: Int = 0
    var comment: String? = nil
    var createdAt: String = ""
    var updatedAt: String = ""
    var author: UserRefDTO? = nil
}

nonisolated extension ReviewDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        rating = container.lenientInt("rating") ?? 0
        comment = container.lenientString("comment")
        createdAt = container.lenientString("createdAt") ?? ""
        updatedAt = container.lenientString("updatedAt") ?? ""
        author = container.lenientObject(UserRefDTO.self, "author")
    }
}

/// GET /api/reviews/eligibility?targetId= : puis-je noter ce vendeur, et l'ai-je déjà fait ?
nonisolated struct ReviewEligibilityDTO: Decodable, Hashable, Sendable {
    var canReview: Bool = false
    var existingReview: ExistingReviewDTO? = nil
}

nonisolated extension ReviewEligibilityDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        canReview = container.lenientBool("canReview") ?? false
        existingReview = container.lenientObject(ExistingReviewDTO.self, "existingReview")
    }
}

nonisolated struct ExistingReviewDTO: Decodable, Hashable, Sendable {
    var rating: Int = 0
    var comment: String? = nil
}

nonisolated extension ExistingReviewDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        rating = container.lenientInt("rating") ?? 0
        comment = container.lenientString("comment")
    }
}

/// POST /api/reviews : création ou modification de MON avis sur un vendeur.
nonisolated struct ReviewCreateRequestDTO: Encodable, Hashable, Sendable {
    var targetId: String
    /// Entier de 1 à 5 (`reviewSchema`).
    var rating: Int
    /// `MyReview.commentMax` caractères au maximum, nettoyé côté serveur.
    var comment: String? = nil
}
