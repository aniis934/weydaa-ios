import SwiftUI

/// Choix fait dans la feuille des catégories.
nonisolated enum CategorySheetChoice: Hashable, Sendable {
    /// « Toutes les catégories » : l'onglet Annonces sans critère.
    case all
    case category(slug: String)
    case subcategory(category: String, subcategory: String)

    /// Critères d'ouverture de l'onglet Annonces.
    var launch: ListingsLaunch {
        switch self {
        case .all:
            return ListingsLaunch()
        case .category(let slug):
            return ListingsLaunch(category: slug)
        case .subcategory(let category, let subcategory):
            return ListingsLaunch(category: category, subcategory: subcategory)
        }
    }
}

/// Résultat de la recherche de la feuille : une catégorie racine, ou l'une de ses sous-catégories.
nonisolated struct CategorySearchHit: Hashable, Sendable, Identifiable {
    let root: Category
    let subcategory: Category?

    var id: String {
        guard let subcategory else { return root.slug }
        return "\(root.slug)/\(subcategory.slug)"
    }

    var choice: CategorySheetChoice {
        guard let subcategory else { return .category(slug: root.slug) }
        return .subcategory(category: root.slug, subcategory: subcategory.slug)
    }
}

/// Recherche locale de la feuille — portage de `filterCategories` (CategoriesSheet.kt), étendu aux sous-catégories :
/// sans casse ni accents (`foldedForSearch`), dans les trois langues à la fois (« electro » trouve « Électronique »
/// et « Électroménager », « سيار » trouve « Voitures »). Ordre du catalogue, une racine avant ses sous-catégories.
nonisolated enum CategorySearch {
    /// Requête vide ou blanche : aucun résultat (la feuille montre alors la liste complète).
    static func hits(in categories: [Category], query: String) -> [CategorySearchHit] {
        let needle = query.foldedForSearch()
        guard !needle.isEmpty else { return [] }
        var hits: [CategorySearchHit] = []
        for root in categories {
            if matches(root.name, needle: needle) {
                hits.append(CategorySearchHit(root: root, subcategory: nil))
            }
            for child in root.children where matches(child.name, needle: needle) {
                hits.append(CategorySearchHit(root: root, subcategory: child))
            }
        }
        return hits
    }

    static func matches(_ name: LocalizedName, needle: String) -> Bool {
        name.fr.foldedForSearch().contains(needle)
            || name.ar.foldedForSearch().contains(needle)
            || name.en.foldedForSearch().contains(needle)
    }
}

/// Feuille « Catégories » de l'accueil — portage de `CategoriesSheet.kt` (la feuille homonyme de Leboncoin) : toutes
/// les catégories racines, avec leur icône Lucide et leur nombre d'annonces ; une racine ouvre ses sous-catégories ;
/// la recherche (barre de la feuille) porte sur les racines ET les sous-catégories. Un choix ferme la feuille et ouvre
/// l'onglet Annonces (`onSelect`, branché par `HomeView`).
struct CategoriesSheet: View {
    private let categories: [Category]
    private let onSelect: (CategorySheetChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    init(categories: [Category], onSelect: @escaping (CategorySheetChoice) -> Void) {
        self.categories = categories
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            CategoriesSheetList(categories: categories, query: query, onSelect: onSelect)
                .navigationTitle(L10n.sectionCategories)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L10n.categoriesSearchHint
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.close) {
                            dismiss()
                        }
                    }
                }
                .navigationDestination(for: CategorySheetRoute.self) { route in
                    SubcategoriesList(root: route.root, onSelect: onSelect)
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Écran des sous-catégories d'une racine, poussé dans la feuille.
private nonisolated struct CategorySheetRoute: Hashable, Sendable {
    let root: Category
}

/// Liste de la feuille : « Toutes les catégories » puis les racines ; pendant une recherche, les correspondances.
private struct CategoriesSheetList: View {
    let categories: [Category]
    let query: String
    let onSelect: (CategorySheetChoice) -> Void

    var body: some View {
        List {
            if query.foldedForSearch().isEmpty {
                browseSections
            } else {
                searchSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WeydaColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.categories")
    }

    @ViewBuilder
    private var browseSections: some View {
        Section {
            Button {
                onSelect(.all)
            } label: {
                CategorySheetRow(title: L10n.categoriesAllRow, subtitle: nil, artwork: .all)
            }
            .listRowBackground(WeydaColor.surface)
            .accessibilityIdentifier("categories.row.all")
        }
        Section {
            ForEach(categories) { root in
                rootRow(root)
                    .listRowBackground(WeydaColor.surface)
            }
        }
    }

    /// Une racine qui a des sous-catégories les ouvre ; une racine seule (« Autres ») ouvre directement les annonces.
    @ViewBuilder
    private func rootRow(_ root: Category) -> some View {
        let row = CategorySheetRow(
            title: root.name.resolve(),
            subtitle: L10n.resultsCount(root.listingsCount),
            artwork: .category(slug: root.slug)
        )
        if root.children.isEmpty {
            Button {
                onSelect(.category(slug: root.slug))
            } label: {
                row
            }
            .accessibilityIdentifier("categories.row.\(root.slug)")
        } else {
            NavigationLink(value: CategorySheetRoute(root: root)) {
                row
            }
            .accessibilityIdentifier("categories.row.\(root.slug)")
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        let hits = CategorySearch.hits(in: categories, query: query)
        if hits.isEmpty {
            Text(L10n.categoriesEmpty)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WeydaSpace.xxl)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(hits) { hit in
                    Button {
                        onSelect(hit.choice)
                    } label: {
                        hitRow(hit)
                    }
                    .listRowBackground(WeydaColor.surface)
                    .accessibilityIdentifier("categories.hit.\(hit.id)")
                }
            }
        }
    }

    /// Sous-catégorie trouvée : son nom, puis sa racine et son nombre d'annonces.
    private func hitRow(_ hit: CategorySearchHit) -> CategorySheetRow {
        let artwork = CategoryArtworkContent.category(slug: hit.root.slug)
        guard let subcategory = hit.subcategory else {
            return CategorySheetRow(
                title: hit.root.name.resolve(),
                subtitle: L10n.resultsCount(hit.root.listingsCount),
                artwork: artwork
            )
        }
        let place = "\(hit.root.name.resolve()) · \(L10n.resultsCount(subcategory.listingsCount))"
        return CategorySheetRow(title: subcategory.name.resolve(), subtitle: place, artwork: artwork)
    }
}

/// Sous-catégories d'une racine : « Voir tout » (la racine entière), puis chacune avec son nombre d'annonces.
private struct SubcategoriesList: View {
    let root: Category
    let onSelect: (CategorySheetChoice) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onSelect(.category(slug: root.slug))
                } label: {
                    CategorySheetRow(
                        title: L10n.seeAll,
                        subtitle: L10n.resultsCount(root.listingsCount),
                        artwork: .category(slug: root.slug)
                    )
                }
                .listRowBackground(WeydaColor.surface)
                .accessibilityIdentifier("categories.sub.all")
            }
            Section(L10n.filtersSubcategories) {
                ForEach(root.children) { child in
                    Button {
                        onSelect(.subcategory(category: root.slug, subcategory: child.slug))
                    } label: {
                        CategorySheetRow(
                            title: child.name.resolve(),
                            subtitle: L10n.resultsCount(child.listingsCount),
                            artwork: nil
                        )
                    }
                    .listRowBackground(WeydaColor.surface)
                    .accessibilityIdentifier("categories.sub.\(child.slug)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WeydaColor.background)
        .navigationTitle(root.name.resolve())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.subcategories")
    }
}

/// Ligne de la feuille : l'illustration de la catégorie en tuile de 40 pt (racines ; comme les icônes des
/// Réglages), libellé, puis le nombre d'annonces. VoiceOver la lit d'un trait (« Véhicules, 1 284 annonces »).
private struct CategorySheetRow: View {
    let title: String
    let subtitle: String?
    let artwork: CategoryArtworkContent?

    var body: some View {
        HStack(spacing: WeydaSpace.md) {
            if let artwork {
                CategoryArtwork(artwork, size: WeydaSize.categoryArtworkRow)
            }
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(title)
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
