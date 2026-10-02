import Foundation

/// Annonces (`/api/annonces*`) — portage d'`AnnonceRepository` (data/repository/Repositories.kt) : recherche,
/// sections de l'accueil, détail, dépôt, édition, vendu, suppression, renouvellement.
final class AnnonceRepository {
    private let api: any WeydaAPI

    init(api: any WeydaAPI) {
        self.api = api
    }

    /// Recherche : mot-clé blanc omis, `limit` borné à 1–48, filtres d'attributs vides retirés puis préfixés
    /// `attr_`, `featured` / `withFacets` envoyés à 1 seulement quand ils sont demandés.
    func search(_ query: ListingQuery) async throws -> ListingPage {
        var attrs: [String: String] = [:]
        for (key, value) in query.attributes where !TextCheck.isBlank(value) {
            attrs["attr_\(key)"] = value
        }
        let dto = try await api.getAnnonces(
            q: TextCheck.nonBlank(query.q),
            category: query.category,
            subcategory: query.subcategory,
            wilaya: query.wilaya,
            commune: query.commune,
            priceType: query.priceType?.rawValue,
            priceMin: query.priceMin,
            priceMax: query.priceMax,
            sort: query.sort,
            featured: query.featured ? 1 : nil,
            page: query.page,
            limit: RepositorySupport.clamp(query.limit, 1, 48),
            locale: nil,
            withFacets: query.withFacets ? 1 : nil,
            attrs: attrs
        )
        return dto.toDomain()
    }

    /// Section « À la une » de l'accueil.
    func featured(limit: Int = 8) async throws -> [Listing] {
        try await search(ListingQuery(sort: "newest", featured: true, limit: limit)).items
    }

    /// Section « Annonces récentes ».
    func recent(limit: Int = 12) async throws -> [Listing] {
        try await search(ListingQuery(sort: "newest", limit: limit)).items
    }

    /// « Tendances » (vues sur 7 jours), comme l'accueil du site.
    func trending(limit: Int = 12) async throws -> [Listing] {
        try await api.getTrending(limit: limit).annonces.map { $0.toDomain() }
    }

    /// « Pour vous » du compte connecté ; liste vide pour un visiteur ou sans signal.
    func recommendations() async throws -> [Listing] {
        try await api.getRecommendations().annonces.map { $0.toDomain() }
    }

    /// Annonces de la même catégorie, sans l'annonce courante (section « Annonces similaires »).
    func similar(to listing: Listing, limit: Int = 8) async throws -> [Listing] {
        guard let category = listing.categorySlug else { return [] }
        let page = try await search(ListingQuery(category: category, sort: "newest", limit: limit + 1))
        return Array(page.items.filter { $0.id != listing.id }.prefix(limit))
    }

    /// Correction proposée pour un mot-clé ; `nil` si aucune, ou si elle ne fait que répéter la saisie.
    func didYouMean(_ q: String) async throws -> String? {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = try await api.didYouMean(q: text).suggestion
        guard let suggestion = TextCheck.nonBlank(suggestion) else { return nil }
        return suggestion.compare(text, options: .caseInsensitive) == .orderedSame ? nil : suggestion
    }

    /// Compte une vue (sans effet pour le propriétaire ; limité côté serveur). Échec silencieux.
    func countView(id: String) async {
        _ = try? await api.countView(id: id)
    }

    /// Détail par id ou par slug (lien profond).
    func detail(idOrSlug: String) async throws -> Listing {
        try await api.getAnnonce(idOrSlug: idOrSlug).toDomain()
    }

    /// Dépôt : 403 `emailNotVerified`, 400 `invalidAttributes` (+ `attributeErrors`) / `maxImagesExceeded`,
    /// 429 `rateLimitError`.
    func create(_ s: ListingSubmission) async throws -> Listing {
        try await api.createAnnonce(s.toRequest()).toDomain()
    }

    /// Édition complète (mêmes champs que le dépôt, `null` explicites pour vider) ; titre ou description
    /// modifiés → retour en PENDING.
    func update(id: String, _ s: ListingSubmission) async throws -> Listing {
        let body = try s.toUpdateBody()
        return try await api.editAnnonce(id: id, body: body).toDomain()
    }

    /// ACTIVE → SOLD (seule transition permise au propriétaire).
    func markSold(id: String) async throws -> Listing {
        try await api.updateAnnonce(id: id, UpdateAnnonceRequestDTO(status: ListingStatus.sold.rawValue)).toDomain()
    }

    func delete(id: String) async throws {
        _ = try await api.deleteAnnonce(id: id)
    }

    /// Renouvellements restants (`nil` pour un ADMIN). 400 `renewalLimitReached` / `notRenewable`.
    func renew(id: String) async throws -> Int? {
        try await api.patchAnnonce(id: id, PatchAnnonceRequestDTO(action: "renew")).renewalsRemaining
    }
}
