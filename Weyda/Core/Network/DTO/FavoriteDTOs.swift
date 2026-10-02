import Foundation

// Portage de data/remote/dto/FavoriteDtos.kt — favoris (docs/API-CONTRACT.md §4) : GET /api/favorites (tableau
// nu d'annonces + favoritedAt → `DTOLossyList<AnnonceDTO>`), POST { annonceId } → 201 ligne Favorite,
// DELETE /api/favorites/{annonceId}, GET /api/favorites/{annonceId}.

nonisolated struct FavoriteRequestDTO: Encodable, Hashable, Sendable {
    var annonceId: String
}

nonisolated struct FavoriteDTO: Decodable, Hashable, Sendable {
    var id: String = ""
    var userId: String = ""
    var annonceId: String = ""
    var createdAt: String = ""
}

nonisolated extension FavoriteDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = container.lenientString("id") ?? ""
        userId = container.lenientString("userId") ?? ""
        annonceId = container.lenientString("annonceId") ?? ""
        createdAt = container.lenientString("createdAt") ?? ""
    }
}

nonisolated struct IsFavoriteDTO: Decodable, Hashable, Sendable {
    var isFavorite: Bool = false
}

nonisolated extension IsFavoriteDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        isFavorite = container.lenientBool("isFavorite") ?? false
    }
}
