import SwiftUI

/// Étape 1 — catégorie (Android : `CategoryStep`, PostSteps.kt) : grille des catégories racines (illustrations 3D,
/// comme l'étape « Catégorie » du site), puis la liste des sous-catégories de la racine choisie, l'erreur
/// « Choisissez une catégorie » et l'attente des caractéristiques. Chargement et échec (réessayer) des catégories
/// à la place de la grille.
struct PostCategoryStep: View {
    private let state: PostListingState
    private let actions: PostListingActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: WeydaSpace.sm, alignment: .top),
        count: 3
    )
    /// Très grand texte : deux colonnes (à trois, « الإلكترونيات » se coupait en « الإلكترونيا / ت »).
    private static let largeColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: WeydaSpace.sm, alignment: .top),
        count: 2
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
                LazyVGrid(columns: gridColumns, spacing: WeydaSpace.sm) {
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

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? Self.largeColumns : Self.columns
    }
}

/// Tuile d'une catégorie racine : l'illustration, nom sur deux lignes (place réservée : les tuiles d'une rangée
/// gardent la même hauteur). Choisie : illustration cerclée de vert et cochée, nom en vert.
private struct PostCategoryTile: View {
    private let category: Category
    private let isSelected: Bool
    private let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let badgeSide: CGFloat = 56
    /// Anneau de sélection : écart à l'illustration, épaisseur ; coche posée sur son coin (sans décalage : le coin
    /// suit le sens de lecture).
    private static let ringGap: CGFloat = 3
    private static let ringWidth: CGFloat = 2
    private static let checkSide: CGFloat = 18
    /// Très grand texte : réduction permise au nom plutôt qu'un mot coupé en deux.
    private static let largeTitleMinScale: CGFloat = 0.7

    init(category: Category, isSelected: Bool, action: @escaping () -> Void) {
        self.category = category
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        Button(action: action) {
            VStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
                badge
                title
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

    /// Tailles normales : deux lignes réservées (inchangé). Très grand texte : une ligne par mot au plus (deux
    /// lignes), réduite jusqu'à 70 % — jamais « الإلكترونيا / ت » ; deux lignes toujours réservées (texte caché),
    /// pour que les tuiles d'une rangée gardent la même hauteur.
    @ViewBuilder
    private var title: some View {
        let name: String = category.name.resolve()
        if dynamicTypeSize.isAccessibilitySize {
            ZStack(alignment: .top) {
                Text(verbatim: " ")
                    .weydaText(.labelMedium)
                    .lineLimit(2, reservesSpace: true)
                    .hidden()
                Text(name)
                    .weydaText(.labelMedium)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(LabelLines.limit(for: name, maxLines: 2))
                    .minimumScaleFactor(Self.largeTitleMinScale)
            }
        } else {
            Text(name)
                .weydaText(.labelMedium)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
        }
    }

    /// L'illustration ; choisie, un anneau vert l'entoure à distance (comme un fond d'écran choisi dans Réglages)
    /// et une coche s'y pose — le choix ne repose pas sur la seule couleur. L'anneau a toujours sa place réservée :
    /// rien ne bouge à la sélection.
    private var badge: some View {
        let ring = RoundedRectangle(
            cornerRadius: Self.badgeSide * WeydaRadius.artworkRatio + Self.ringGap,
            style: .continuous
        )
        return CategoryArtwork(.category(slug: category.slug), size: Self.badgeSide)
            .padding(Self.ringGap)
            .overlay {
                ring.strokeBorder(isSelected ? WeydaColor.primary : Color.clear, lineWidth: Self.ringWidth)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: Self.checkSide, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(WeydaColor.onPrimary, WeydaColor.primary)
                        .background(WeydaColor.surface, in: Circle())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
    }

    private var tileColor: Color {
        isSelected ? WeydaColor.primaryContainer.opacity(0.35) : WeydaColor.surface
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
