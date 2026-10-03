import SwiftUI

/// Étape 1 — catégorie (Android : `CategoryStep`, PostSteps.kt) : grille des catégories racines (icône Lucide de la
/// marque), puis la liste des sous-catégories de la racine choisie, l'erreur « Choisissez une catégorie » et
/// l'attente des caractéristiques. Chargement et échec (réessayer) des catégories à la place de la grille.
struct PostCategoryStep: View {
    private let state: PostListingState
    private let actions: PostListingActions

    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: WeydaSpace.sm, alignment: .top),
        count: 3
    )
    /// Hauteur réservée au chargement et à l'erreur (Android : 240 dp).
    private static let placeholderHeight: CGFloat = 240

    init(state: PostListingState, actions: PostListingActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        if state.categoriesLoading {
            LoadingState()
                .frame(height: Self.placeholderHeight)
        } else if state.categoriesError {
            ErrorState(message: L10n.errorGeneric, onRetry: actions.retryCategories)
                .frame(minHeight: Self.placeholderHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                PostFormSectionLabel(L10n.postChooseCategory, isRequired: true)
                LazyVGrid(columns: Self.columns, spacing: WeydaSpace.sm) {
                    ForEach(state.categories) { category in
                        PostCategoryTile(
                            category: category,
                            isSelected: category.id == state.parentCategoryId,
                            action: { actions.selectParent(category.id) }
                        )
                    }
                }
                .padding(.top, WeydaSpace.md)
                if state.needsSubcategory {
                    PostFormSectionLabel(L10n.postChooseSubcategory, isRequired: true)
                        .padding(.top, WeydaSpace.xl)
                    PostSubcategoryList(
                        subcategories: state.subcategories,
                        selectedId: state.subcategoryId,
                        onSelect: actions.selectSubcategory
                    )
                    .padding(.top, WeydaSpace.sm)
                }
                if let error = state.categoryError {
                    Text(error)
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, WeydaSpace.sm)
                        .accessibilityIdentifier("post.category.error")
                }
                if state.attributesLoading {
                    InlineLoader()
                }
            }
            .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: state.parentCategoryId)
        }
    }
}

/// Tuile d'une catégorie racine : pastille teintée portant l'icône, nom sur deux lignes (place réservée : les
/// tuiles d'une rangée gardent la même hauteur). Choisie : pastille cerclée de vert, nom en vert.
private struct PostCategoryTile: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void

    private static let badgeSide: CGFloat = 56
    private static let iconSide: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        Button(action: action) {
            VStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
                badge
                Text(category.name.resolve())
                    .weydaText(.labelMedium)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WeydaSpace.sm + WeydaSpace.xxs)
            .padding(.horizontal, WeydaSpace.xs)
            .background(tileColor, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(WeydaPressStyle())
        .accessibilityLabel(category.name.resolve())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("post.category.\(category.slug)")
    }

    private var badge: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        return shape
            .fill(badgeColor)
            .frame(width: Self.badgeSide, height: Self.badgeSide)
            .overlay {
                CategoryIconImage(assetName: CategoryIcon.assetName(forSlug: category.slug), size: Self.iconSide)
                    .foregroundStyle(WeydaColor.primary)
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(WeydaColor.primary, lineWidth: 2)
                }
            }
    }

    private var tileColor: Color {
        isSelected ? WeydaColor.primaryContainer.opacity(0.35) : WeydaColor.surface
    }

    private var badgeColor: Color {
        isSelected ? WeydaColor.primaryContainer : WeydaPalette.categoryTile
    }

    private var titleColor: Color {
        isSelected ? WeydaColor.primary : WeydaColor.onSurface
    }
}

/// Sous-catégories de la racine choisie : une liste groupée à coche, comme les Réglages d'iOS (Android : puces
/// `FilterChip` ; une liste garde les libellés longs entiers et se lit mieux à VoiceOver).
private struct PostSubcategoryList: View {
    let subcategories: [Category]
    let selectedId: String?
    let onSelect: (String) -> Void

    var body: some View {
        PostFormCard {
            VStack(spacing: 0) {
                ForEach(subcategories) { subcategory in
                    if subcategory.id != subcategories.first?.id {
                        Divider()
                            .padding(.leading, WeydaSpace.lg)
                    }
                    row(subcategory)
                }
            }
        }
    }

    private func row(_ subcategory: Category) -> some View {
        let isSelected = subcategory.id == selectedId
        return Button {
            onSelect(subcategory.id)
        } label: {
            HStack(spacing: WeydaSpace.sm) {
                Text(subcategory.name.resolve())
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WeydaColor.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, WeydaSpace.lg)
            .padding(.vertical, WeydaSpace.sm)
            .frame(minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("post.subcategory.\(subcategory.slug)")
    }
}
