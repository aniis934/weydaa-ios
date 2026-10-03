import Foundation

// Portage de data/remote/dto/SavedSearchDtos.kt — recherches sauvegardées (docs/API-CONTRACT.md §4) :
// GET → { searches, max: 5 }, POST { params } → 201 { search } ou 200 { search, duplicate: true },
// DELETE /api/saved-searches/{id}.

nonisolated struct SavedSearchDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String = ""
    /// Clés d'URL du site (`q, category, subcategory, wilaya, commune, priceMin/Max, priceType, attr_*`).
    var params: [String: String]? = nil
    var createdAt: String = ""
}

nonisolated extension SavedSearchDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        name = container.lenientString("name") ?? ""
        params = container.lenientStringMap("params")
        createdAt = container.lenientString("createdAt") ?? ""
    }
}

nonisolated struct SavedSearchesDTO: Decodable, Hashable, Sendable {
    var searches: [SavedSearchDTO] = []
    var max: Int = 5
}

nonisolated extension SavedSearchesDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        searches = container.lenientList(SavedSearchDTO.self, "searches")
        max = container.lenientInt("max") ?? 5
    }
}

nonisolated struct SavedSearchCreateRequestDTO: Encodable, Hashable, Sendable {
    var params: [String: String]
}

nonisolated struct SavedSearchCreatedDTO: Decodable, Hashable, Sendable {
    var search: SavedSearchDTO
    var duplicate: Bool = false
}

nonisolated extension SavedSearchCreatedDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        search = try container.decode(SavedSearchDTO.self, forKey: "search")
        duplicate = container.lenientBool("duplicate") ?? false
    }
}
