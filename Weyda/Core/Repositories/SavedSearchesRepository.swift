import Foundation

/// Résultat d'une création d'alerte : `duplicate` = une alerte identique existait déjà (200 au lieu de 201).
nonisolated struct SaveSearchOutcome: Hashable, Sendable {
    let search: SavedSearch
    let duplicate: Bool
}

/// Recherches sauvegardées = alertes (`/api/saved-searches`, 5 au maximum, session requise, 403 `emailNotVerified`
/// à la création) — portage de `SavedSearchesRepository`. `params` = clés d'URL du site (`q, category, subcategory,
/// wilaya, commune, priceMin/Max, priceType, attr_*`) ; le nom est composé par le serveur.
final class SavedSearchesRepository {
    static let maxSavedSearches = 5

    private let api: any WeydaAPI

    init(api: any WeydaAPI) {
        self.api = api
    }

    func list() async throws -> [SavedSearch] {
        try await api.getSavedSearches().searches.map { $0.toDomain() }
    }

    /// Valeurs vides retirées. 400 `savedSearchEmpty` (aucun filtre retenu) / `savedSearchLimit` (5 déjà).
    func create(params: [String: String]) async throws -> SaveSearchOutcome {
        let kept = params.filter { !TextCheck.isBlank($0.value) }
        let dto = try await api.createSavedSearch(SavedSearchCreateRequestDTO(params: kept))
        return SaveSearchOutcome(search: dto.search.toDomain(), duplicate: dto.duplicate)
    }

    func delete(id: String) async throws {
        _ = try await api.deleteSavedSearch(id: id)
    }
}
