import Foundation

/// État de l'onglet Annonces — portage de `ListingsUiState` (ui/listings/ListingsViewModel.kt, Android) : recherche,
/// catégorie, résultats paginés, filtres (feuille + puces), catalogue, facettes, alerte. Données pures.
nonisolated struct ListingsState: Equatable, Sendable {
    var query: String = ""
    var categorySlug: String? = nil
    /// Catégories racines (puces en tête de l'écran), avec leurs sous-catégories.
    var categories: [Category] = []
    var items: [Listing] = []
    var total: Int = 0
    var page: Int = 1
    var totalPages: Int = 1
    var isLoading: Bool = true
    var isLoadingMore: Bool = false
    /// La page suivante a échoué : « Réessayer » en bas de liste (le défilement ne relance plus).
    var loadMoreFailed: Bool = false
    /// Tirer pour rafraîchir : la liste reste affichée pendant la requête.
    var isRefreshing: Bool = false
    var isError: Bool = false
    /// Message de l'erreur plein écran (`ErrorMapper`) — Android : `errorRes`.
    var errorMessage: String? = nil
    /// Correction proposée quand un mot-clé ne donne rien (« Vouliez-vous dire … ? »).
    var didYouMean: String? = nil
    var filters: ListingFilters = ListingFilters()
    var showFilters: Bool = false
    var wilayas: [Wilaya] = []
    /// Communes de la wilaya choisie dans la feuille de filtres (brouillon), réalignées à son ouverture.
    var communes: [Commune] = []
    /// Attributs de la catégorie : libellés des facettes et des puces, plages, oui / non.
    var attributeSet: AttributeSet? = nil
    var facets: [String: [FacetValue]] = [:]
    /// Options des selects dépendants (modèles d'une marque…), rangées par `ListingsState.dependentKey`.
    var dependentOptions: [String: [AttributeOption]] = [:]
    var isSavingSearch: Bool = false
    /// Message éphémère (alerte créée ou déjà existante, échec d'un rafraîchissement) — le Snackbar d'Android.
    var notice: ListingsNotice? = nil
}

nonisolated extension ListingsState {
    /// Clés d'URL du site pour `POST /api/saved-searches` (tri exclu) — `toSearchParams` (Android).
    func toSearchParams() -> [String: String] {
        var params: [String: String] = [:]
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty { params["q"] = keyword }
        if let categorySlug { params["category"] = categorySlug }
        if let subcategory = filters.subcategory { params["subcategory"] = subcategory }
        if let wilayaId = filters.wilayaId { params["wilaya"] = String(wilayaId) }
        if let communeId = filters.communeId { params["commune"] = String(communeId) }
        if let priceType = filters.priceType { params["priceType"] = priceType.rawValue }
        if !TextCheck.isBlank(filters.priceMin) { params["priceMin"] = filters.priceMin }
        if !TextCheck.isBlank(filters.priceMax) { params["priceMax"] = filters.priceMax }
        for (key, value) in filters.attributes where !TextCheck.isBlank(value) {
            params["attr_\(key)"] = value
        }
        if filters.featuredOnly { params["featured"] = "1" }
        return params
    }

    /// « Créer une alerte » : au moins un critère, et pas d'envoi en cours.
    var canSaveSearch: Bool { !isSavingSearch && !toSearchParams().isEmpty }

    var canLoadMore: Bool {
        page < totalPages && !isLoading && !isLoadingMore && !loadMoreFailed && !isRefreshing
    }

    var hasQuery: Bool { !TextCheck.isBlank(query) }

    var selectedCategory: Category? {
        guard let categorySlug else { return nil }
        return categories.first { $0.slug == categorySlug }
    }

    var selectedSubcategory: Category? {
        guard let subcategory = filters.subcategory else { return nil }
        return selectedCategory?.children.first { $0.slug == subcategory }
    }

    var selectedWilaya: Wilaya? {
        guard let wilayaId = filters.wilayaId else { return nil }
        return wilayas.first { $0.id == wilayaId }
    }

    var selectedCommune: Commune? {
        guard let communeId = filters.communeId else { return nil }
        return communes.first { $0.id == communeId }
    }

    /// Clé des options d'un select dépendant : l'attribut et la valeur de son parent (`model=renault`).
    static func dependentKey(_ key: String, parentValue: String) -> String {
        "\(key)=\(parentValue)"
    }
}

/// Message éphémère de l'écran (bandeau en bas, lu par VoiceOver).
nonisolated enum ListingsNotice: Hashable, Sendable {
    case alertCreated
    case alertDuplicate
    /// Message déjà traduit (`ErrorMapper`).
    case message(String)

    var text: String {
        switch self {
        case .alertCreated: return L10n.alertCreated
        case .alertDuplicate: return L10n.alertDuplicate
        case .message(let text): return text
        }
    }
}

/// Tris de `GET /api/annonces` — `SORT_OPTIONS` (FiltersSheet.kt). `rawValue` = valeur envoyée à l'API.
nonisolated enum ListingSort: String, CaseIterable, Sendable {
    case relevance
    case newest
    case oldest
    case priceAsc
    case priceDesc
    case mostViewed

    var title: String {
        switch self {
        case .relevance: return L10n.sortRelevance
        case .newest: return L10n.sortNewest
        case .oldest: return L10n.sortOldest
        case .priceAsc: return L10n.sortPriceAsc
        case .priceDesc: return L10n.sortPriceDesc
        case .mostViewed: return L10n.sortMostViewed
        }
    }

    /// Les tris proposés sans mot-clé (la pertinence n'a de sens qu'avec un mot-clé).
    static let standard: [ListingSort] = [.newest, .oldest, .priceAsc, .priceDesc, .mostViewed]

    static func options(hasQuery: Bool) -> [ListingSort] {
        hasQuery ? [.relevance] + standard : standard
    }

    /// Tri appliqué quand aucun n'est choisi : la pertinence avec un mot-clé, sinon les plus récentes.
    static func defaultSort(hasQuery: Bool) -> ListingSort {
        hasQuery ? .relevance : .newest
    }
}

/// Filtre actif retirable d'une puce (barre au-dessus des résultats).
nonisolated enum ListingsChipKind: Hashable, Sendable {
    case subcategory
    case sort
    case location
    case priceType
    case price
    case featured
    case attribute(String)
}

/// Puce d'un filtre actif : son libellé et ce qu'elle retire.
nonisolated struct ListingsChip: Hashable, Sendable, Identifiable {
    let kind: ListingsChipKind
    let title: String

    var id: ListingsChipKind { kind }
}

/// Valeur d'une facette dans la feuille de filtres : « Renault (12) ».
nonisolated struct ListingsFacetChoice: Hashable, Sendable, Identifiable {
    let value: String
    let label: String
    let count: Int

    var id: String { value }
}

/// Une facette (attribut à valeurs comptées par le serveur) et ses valeurs proposées.
nonisolated struct ListingsFacetSection: Hashable, Sendable, Identifiable {
    let key: String
    let title: String
    let choices: [ListingsFacetChoice]

    var id: String { key }
}

/// Règles des filtres de l'écran Annonces, pures et testables : puces actives (ActiveFiltersRow, Android), facettes et
/// attributs de la feuille (FiltersSheet.kt), modifications du brouillon.
nonisolated enum ListingsFilterRules {
    /// Valeurs de facette proposées au plus (Android : `MAX_FACET_VALUES`).
    static let maxFacetValues = 12

    // MARK: - Puces actives

    /// Puces des filtres actifs, dans l'ordre d'Android : sous-catégorie, tri, lieu, type de prix, prix, « À la une »,
    /// attributs (ordre des attributs de la catégorie : un dictionnaire Swift n'en a pas).
    static func activeChips(for state: ListingsState, language: String = WeydaLocale.language) -> [ListingsChip] {
        let filters = state.filters
        var chips: [ListingsChip] = []
        if let subcategory = state.selectedSubcategory {
            chips.append(ListingsChip(kind: .subcategory, title: subcategory.name.resolve(language)))
        }
        if let raw = filters.sort, let sort = ListingSort.standard.first(where: { $0.rawValue == raw }) {
            chips.append(ListingsChip(kind: .sort, title: sort.title))
        }
        if let wilaya = state.selectedWilaya {
            let parts: [String] = [wilaya.name.resolve(language), state.selectedCommune?.name.resolve(language)].compactMap { $0 }
            chips.append(ListingsChip(kind: .location, title: parts.joined(separator: " · ")))
        }
        if let priceType = filters.priceType {
            chips.append(ListingsChip(kind: .priceType, title: priceTypeTitle(priceType)))
        }
        if let title = priceTitle(min: filters.priceMin, max: filters.priceMax) {
            chips.append(ListingsChip(kind: .price, title: title))
        }
        if filters.featuredOnly {
            chips.append(ListingsChip(kind: .featured, title: L10n.filtersFeaturedChip))
        }
        for key in orderedAttributeKeys(filters.attributes, attributeSet: state.attributeSet) {
            guard let value = filters.attributes[key] else { continue }
            chips.append(ListingsChip(kind: .attribute(key), title: attributeTitle(key: key, value: value, state: state)))
        }
        return chips
    }

    /// Ce que retire une puce (Android : `actions.onUpdate { … }`).
    static func removing(_ kind: ListingsChipKind, from filters: ListingFilters) -> ListingFilters {
        var result = filters
        switch kind {
        case .subcategory:
            result.subcategory = nil
            result.attributes = [:]
        case .sort:
            result.sort = nil
        case .location:
            result.wilayaId = nil
            result.communeId = nil
        case .priceType:
            result.priceType = nil
        case .price:
            result.priceMin = ""
            result.priceMax = ""
        case .featured:
            result.featuredOnly = false
        case .attribute(let key):
            result.attributes[key] = nil
        }
        return result
    }

    /// Libellé d'un type de prix (puces du filtre et de la feuille).
    static func priceTypeTitle(_ type: PriceType) -> String {
        switch type {
        case .fixed: return L10n.postPriceFixed
        case .negotiable: return L10n.postPriceNegotiable
        case .free: return L10n.postPriceFree
        }
    }

    /// « 100 000 – 2 000 000 DA », « ≥ 100 000 DA », « ≤ 2 000 000 DA » ; nil sans borne.
    static func priceTitle(min: String, max: String) -> String? {
        let low: String? = TextCheck.nonBlank(min).map { displayAmount($0) }
        let high: String? = TextCheck.nonBlank(max).map { displayAmount($0) }
        if let low, let high { return L10n.filtersPriceBetween(low, high) }
        if let low { return L10n.filtersPriceFrom(low) }
        if let high { return L10n.filtersPriceTo(high) }
        return nil
    }

    /// Montant saisi, chiffres groupés (« 2 000 000 ») ; tel quel s'il ne se lit pas comme un nombre.
    static func displayAmount(_ raw: String) -> String {
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)) else { return raw }
        return Format.integer(value)
    }

    /// Clé d'attribut sans le suffixe de plage (`year_min` → `year`).
    static func baseAttributeKey(_ key: String) -> String {
        if key.hasSuffix("_min") || key.hasSuffix("_max") {
            return String(key.dropLast(4))
        }
        return key
    }

    /// « Marque : Renault », « Année ≥ 2015 », « Échange possible » (booléen).
    static func attributeTitle(key: String, value: String, state: ListingsState) -> String {
        let baseKey = baseAttributeKey(key)
        let definition = state.attributeSet?.attribute(baseKey) ?? state.attributeSet?.attribute(key)
        let name = definition?.label ?? AttributeDefinition.displayLabel(baseKey.replacingOccurrences(of: "_", with: "-"))
        if key.hasSuffix("_min") { return L10n.filtersAttrMin(name, value) }
        if key.hasSuffix("_max") { return L10n.filtersAttrMax(name, value) }
        if value == "true" && definition?.filterType == "boolean" { return name }
        return L10n.filtersAttrValue(name, optionLabel(value, definition: definition, state: state))
    }

    /// Libellé d'une valeur : options du select dépendant si elles sont connues, sinon celles de l'attribut.
    static func optionLabel(_ value: String, definition: AttributeDefinition?, state: ListingsState) -> String {
        guard let definition else { return value }
        if let parent = definition.dependsOn, let parentValue = state.filters.attributes[parent] {
            let key = ListingsState.dependentKey(definition.key, parentValue: parentValue)
            if let option = state.dependentOptions[key]?.first(where: { $0.value == value }) {
                return option.label
            }
        }
        return definition.optionLabel(value)
    }

    /// Ordre stable des filtres d'attributs : celui des attributs de la catégorie (minimum avant maximum), puis les
    /// clés inconnues par ordre alphabétique.
    static func orderedAttributeKeys(_ attributes: [String: String], attributeSet: AttributeSet?) -> [String] {
        let order: [String] = attributeSet?.attributes.map { $0.key } ?? []
        func rank(_ key: String) -> (Int, Int, String) {
            let index = order.firstIndex(of: baseAttributeKey(key)) ?? order.count
            var suffix = 0
            if key.hasSuffix("_min") {
                suffix = 1
            } else if key.hasSuffix("_max") {
                suffix = 2
            }
            return (index, suffix, key)
        }
        return attributes.keys.sorted { rank($0) < rank($1) }
    }

    // MARK: - Feuille de filtres

    /// Attributs filtrables d'un type de filtre (`range`, `boolean`), sans doublon de clé, dans l'ordre du serveur.
    static func filterableAttributes(_ attributeSet: AttributeSet?, filterType: String) -> [AttributeDefinition] {
        var seen: Set<String> = []
        var result: [AttributeDefinition] = []
        for definition in attributeSet?.attributes ?? [] where definition.filterable && definition.filterType == filterType {
            if seen.insert(definition.key).inserted {
                result.append(definition)
            }
        }
        return result
    }

    /// Titre d'une plage : « Kilométrage (km) ».
    static func rangeTitle(_ definition: AttributeDefinition) -> String {
        guard let unit = TextCheck.nonBlank(definition.unitLabel) else { return definition.label }
        return "\(definition.label) (\(unit))"
    }

    /// Facettes proposées dans la feuille, dans l'ordre des attributs de la catégorie (puis les clés inconnues, par
    /// ordre alphabétique) ; 12 valeurs au plus. Un select dépendant (modèle ← marque) n'apparaît qu'une fois son
    /// parent choisi dans le brouillon, réduit aux options de ce parent quand le serveur les a données (comme le site).
    static func facetSections(state: ListingsState, attributes: [String: String]) -> [ListingsFacetSection] {
        let attributeSet = state.attributeSet
        var keys: [String] = []
        var seen: Set<String> = []
        for definition in attributeSet?.attributes ?? [] where seen.insert(definition.key).inserted {
            keys.append(definition.key)
        }
        keys += state.facets.keys.filter { !seen.contains($0) }.sorted()

        var sections: [ListingsFacetSection] = []
        for key in keys {
            guard let values = state.facets[key], !values.isEmpty else { continue }
            let definition = attributeSet?.attribute(key)
            var parentLabels: [String: String]? = nil
            if let parent = definition?.dependsOn {
                guard let parentValue = TextCheck.nonBlank(attributes[parent]) else { continue }
                if let options = state.dependentOptions[ListingsState.dependentKey(key, parentValue: parentValue)] {
                    parentLabels = Dictionary(options.map { ($0.value, $0.label) }, uniquingKeysWith: { first, _ in first })
                }
            }
            var choices: [ListingsFacetChoice] = []
            for facet in values {
                let label: String
                if let parentLabels {
                    guard let known = parentLabels[facet.value] else { continue }
                    label = known
                } else {
                    label = definition?.optionLabel(facet.value) ?? facet.value
                }
                choices.append(ListingsFacetChoice(value: facet.value, label: label, count: facet.count))
                if choices.count == maxFacetValues { break }
            }
            guard !choices.isEmpty else { continue }
            sections.append(ListingsFacetSection(key: key, title: definition?.label ?? key, choices: choices))
        }
        return sections
    }

    /// « Renault (12) ».
    static func facetTitle(_ choice: ListingsFacetChoice) -> String {
        "\(choice.label) (\(Format.count(choice.count)))"
    }

    /// Choix d'une valeur de facette dans le brouillon (nouvel appui = retrait). Changer de parent (marque) vide les
    /// selects qui en dépendent (modèle) : leurs valeurs ne valent plus.
    static func toggling(_ filters: ListingFilters, key: String, value: String, attributeSet: AttributeSet?) -> ListingFilters {
        var result = filters
        if result.attributes[key] == value {
            result.attributes[key] = nil
        } else {
            result.attributes[key] = value
        }
        for definition in attributeSet?.attributes ?? [] where definition.dependsOn == key {
            result.attributes[definition.key] = nil
        }
        return result
    }

    /// Ajoute ou retire (valeur vide) un filtre d'attribut — `withAttribute` (Android).
    static func settingAttribute(_ filters: ListingFilters, key: String, value: String) -> ListingFilters {
        var result = filters
        result.attributes[key] = TextCheck.isBlank(value) ? nil : value
        return result
    }
}
