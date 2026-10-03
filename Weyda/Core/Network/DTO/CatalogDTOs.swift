import Foundation

// Portage de data/remote/dto/CatalogDtos.kt — attributs dynamiques par catégorie (docs/API-CONTRACT.md §2) :
// GET /api/categories/{slug}/attributes?subcategory=&locale=&ctx_<clé>=
// Définitions statiques côté serveur (src/data/attributes/types.ts) + libellés traduits additifs
// (src/lib/attribute-labels.ts). Catégorie sans attributs → { attributes: [], subcategories: [] }.

nonisolated struct AttributesResponseDTO: Decodable, Hashable, Sendable {
    var attributes: [AttributeDTO] = []
    var subcategories: [SubcategoryDTO] = []
}

nonisolated extension AttributesResponseDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        attributes = container.lenientList(AttributeDTO.self, "attributes")
        subcategories = container.lenientList(SubcategoryDTO.self, "subcategories")
    }
}

nonisolated struct AttributeDTO: Decodable, Hashable, Sendable {
    var key: String
    /// select | number | boolean | text
    var type: String = "text"
    /// required | recommended | optional
    var requirement: String = "optional"
    var filterable: Bool = false
    /// exact | range | boolean
    var filterType: String = "exact"
    /// Clés techniques (toujours présent, `[]` hors select ou select dépendant sans contexte).
    var options: [String] = []
    /// Select dépendant : clé de l'attribut parent (ex. `model` ← `make`).
    var dependsOn: String? = nil
    var min: Double? = nil
    var max: Double? = nil
    var step: Double? = nil
    /// Clé d'unité technique (ex. `km`), libellé dans `unitLabel`.
    var unit: String? = nil
    var rangePresets: [Double] = []
    var showFor: [String] = []
    var hideFor: [String] = []
    // Champs localisés (ajoutés le 2026-09-08, selon `locale`).
    var label: String? = nil
    var optionLabels: [String: String] = [:]
    var unitLabel: String? = nil
}

nonisolated extension AttributeDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        key = try container.requiredString("key")
        type = container.lenientString("type") ?? "text"
        requirement = container.lenientString("requirement") ?? "optional"
        filterable = container.lenientBool("filterable") ?? false
        filterType = container.lenientString("filterType") ?? "exact"
        options = container.lenientStringList("options")
        dependsOn = container.lenientString("dependsOn")
        min = container.lenientDouble("min")
        max = container.lenientDouble("max")
        step = container.lenientDouble("step")
        unit = container.lenientString("unit")
        rangePresets = container.lenientDoubleList("rangePresets")
        showFor = container.lenientStringList("showFor")
        hideFor = container.lenientStringList("hideFor")
        label = container.lenientString("label")
        optionLabels = container.lenientStringMap("optionLabels") ?? [:]
        unitLabel = container.lenientString("unitLabel")
    }
}

nonisolated struct SubcategoryDTO: Decodable, Hashable, Sendable {
    var slug: String
    var parentSlug: String = ""
    var nameFr: String = ""
    var nameAr: String = ""
    var nameEn: String = ""
}

nonisolated extension SubcategoryDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        slug = try container.requiredString("slug")
        parentSlug = container.lenientString("parentSlug") ?? ""
        nameFr = container.lenientString("nameFr") ?? ""
        nameAr = container.lenientString("nameAr") ?? ""
        nameEn = container.lenientString("nameEn") ?? ""
    }
}
