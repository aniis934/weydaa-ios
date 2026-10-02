import Foundation

// Portage de data/remote/dto/AnnonceRequestDtos.kt — POST /api/annonces (annonceSchema, docs/API-CONTRACT.md §4).
// `images` est toujours encodé (requis, même vide) ; un champ `nil` est omis (`explicitNulls = false`).
// Pour l'édition complète (PUT avec des `null` EXPLICITES), voir `ListingSubmission.toUpdateBody()` (Mappers.swift).

nonisolated struct ImageRefDTO: Encodable, Hashable, Sendable {
    var url: String
    var publicId: String
}

nonisolated struct CreateAnnonceRequestDTO: Encodable, Hashable, Sendable {
    var title: String
    var description: String
    var price: Double? = nil
    var priceType: String
    var categoryId: String
    var subcategorySlug: String? = nil
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    var phone: String? = nil
    var images: [ImageRefDTO]
    /// Valeurs typées : nombre → nombre JSON, booléen → booléen JSON, sinon texte (validateListingAttributes).
    var attributes: [String: JSONValue]? = nil
}

/// PUT /api/annonces/{id} (annonceUpdateSchema, partiel) : seuls les champs présents changent ; `images` =
/// remplacement intégral ; `status = "SOLD"` = seule transition permise au propriétaire (depuis ACTIVE).
/// Titre ou description modifiés → retour en PENDING.
nonisolated struct UpdateAnnonceRequestDTO: Encodable, Hashable, Sendable {
    var status: String? = nil
    var title: String? = nil
    var description: String? = nil
    var price: Double? = nil
    var priceType: String? = nil
    var categoryId: String? = nil
    var subcategorySlug: String? = nil
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    var phone: String? = nil
    var images: [ImageRefDTO]? = nil
    var attributes: [String: JSONValue]? = nil
}

/// PATCH /api/annonces/{id} : `renew` (propriétaire, 3 au maximum) ou `hard_delete` (ADMIN).
nonisolated struct PatchAnnonceRequestDTO: Encodable, Hashable, Sendable {
    var action: String
}

/// Réponse du renouvellement ; `renewalsRemaining` nil pour un ADMIN.
nonisolated struct RenewResponseDTO: Decodable, Hashable, Sendable {
    var success: Bool = true
    var renewalsRemaining: Int? = nil
}

nonisolated extension RenewResponseDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        success = container.lenientBool("success") ?? true
        renewalsRemaining = container.lenientInt("renewalsRemaining")
    }
}
