import Foundation

/// Catégories racines (`GET /api/categories`), gardées en mémoire pour la durée du lancement — portage de
/// `CategoryRepository` (Repositories.kt). Catégories inactives retirées, ordre `displayOrder` (stable).
final class CategoryRepository {
    private let api: any WeydaAPI
    private var cache: [Category]?

    init(api: any WeydaAPI) {
        self.api = api
    }

    func roots(forceRefresh: Bool = false) async throws -> [Category] {
        if !forceRefresh, let cache { return cache }
        let dtos = try await api.getCategories()
        let roots = StableOrder.sorted(dtos.filter { $0.isActive }) { $0.displayOrder }.map { $0.toDomain() }
        cache = roots
        return roots
    }
}

/// Filtre de la feuille « Catégories » de l'accueil — portage de `filterCategories` (ui/home/CategoriesSheet.kt) :
/// insensible à la casse et aux accents, sur les noms français, arabe ET anglais ; requête vide = tout, dans l'ordre.
nonisolated enum CategoryFilter {
    static func filter(_ categories: [Category], query: String) -> [Category] {
        let needle = fold(query)
        if needle.isEmpty { return categories }
        return categories.filter { category in
            fold(category.name.fr).contains(needle)
                || fold(category.name.ar).contains(needle)
                || fold(category.name.en).contains(needle)
        }
    }

    /// Blancs de bord retirés, minuscules, décomposition NFD, toutes les marques (`\p{M}`) supprimées.
    static func fold(_ text: String) -> String {
        let decomposed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().decomposedStringWithCanonicalMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where !isMark(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }
}

/// Attributs dynamiques d'une catégorie (formulaire de dépôt, filtres) — portage d'`AttributeRepository`.
/// Réponses mises en cache par (catégorie, sous-catégorie, langue, contexte) : définitions statiques côté
/// serveur (cache CDN 1 h). 32 entrées au plus, la plus ancienne sort la première. Une erreur n'est pas gardée.
final class AttributeRepository {
    private nonisolated struct Key: Hashable, Sendable {
        let category: String
        let subcategory: String?
        let locale: String
        let context: [String: String]
    }

    static let maxEntries = 32

    private let api: any WeydaAPI
    private var cache: [Key: AttributeSet] = [:]
    /// Ordre d'insertion des clés (`LinkedHashMap` Android) : la plus ancienne est évincée.
    private var insertionOrder: [Key] = []

    init(api: any WeydaAPI) {
        self.api = api
    }

    /// `context` = valeurs courantes du formulaire pour les selects dépendants (`make` → options de `model`) ;
    /// valeurs vides ignorées, clés envoyées en `ctx_<clé>`.
    func attributes(
        categorySlug: String,
        subcategory: String? = nil,
        locale: String = WeydaLocale.language,
        context: [String: String] = [:]
    ) async throws -> AttributeSet {
        let key = Key(
            category: categorySlug,
            subcategory: TextCheck.nonBlank(subcategory),
            locale: locale,
            context: context.filter { !TextCheck.isBlank($0.value) }
        )
        if let cached = cache[key] { return cached }
        var query: [String: String] = [:]
        for (name, value) in key.context {
            query["ctx_\(name)"] = value
        }
        let set = try await api.getAttributes(slug: categorySlug, subcategory: key.subcategory, locale: locale, context: query).toDomain()
        store(set, for: key)
        return set
    }

    /// Options d'un select dépendant (ex. `model`) pour les valeurs courantes du formulaire ; vide s'il est absent.
    func dependentOptions(
        categorySlug: String,
        subcategory: String?,
        key: String,
        context: [String: String],
        locale: String = WeydaLocale.language
    ) async throws -> [AttributeOption] {
        let set = try await attributes(categorySlug: categorySlug, subcategory: subcategory, locale: locale, context: context)
        return set.attribute(key)?.options ?? []
    }

    private func store(_ set: AttributeSet, for key: Key) {
        if cache[key] == nil {
            if cache.count >= Self.maxEntries, let oldest = insertionOrder.first {
                insertionOrder.removeFirst()
                cache[oldest] = nil
            }
            insertionOrder.append(key)
        }
        cache[key] = set
    }
}

/// Wilayas (58) et communes par wilaya, gardées pour la durée du lancement (données quasi statiques, CDN 24 h) —
/// portage de `GeoRepository`.
final class GeoRepository {
    private let api: any WeydaAPI
    private var wilayaCache: [Wilaya]?
    private var communeCache: [Int: [Commune]] = [:]
    private var topCache: [Wilaya]?

    init(api: any WeydaAPI) {
        self.api = api
    }

    func wilayas() async throws -> [Wilaya] {
        if let wilayaCache { return wilayaCache }
        let list = try await api.getWilayas().map { $0.toDomain() }
        wilayaCache = list
        return list
    }

    /// 400 `invalidWilayaId` propagé (et non gardé).
    func communes(wilayaId: Int) async throws -> [Commune] {
        if let cached = communeCache[wilayaId] { return cached }
        let list = try await api.getCommunes(wilayaId: wilayaId).map { $0.toDomain() }
        communeCache[wilayaId] = list
        return list
    }

    /// Wilayas classées par nombre d'annonces actives (`?top=`). Un serveur qui ne connaît pas encore le paramètre
    /// renvoie les 58 wilayas non classées : échec (`RepositoryError.rankingUnsupported`) plutôt que d'afficher
    /// Adrar en tête des « villes principales » — l'appelant garde alors sa liste de repli.
    func topWilayas(limit: Int = 10) async throws -> [Wilaya] {
        if let topCache { return topCache }
        let list = try await api.getTopWilayas(top: limit).map { $0.toDomain() }
        guard list.count <= limit, list.allSatisfy({ $0.listingsCount > 0 }) else {
            throw RepositoryError.rankingUnsupported
        }
        topCache = list
        return list
    }
}
