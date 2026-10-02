import SwiftUI

/// Puce unique de l'app (catégories, villes, filtres actifs, tri) — portage de `WeydaChip` (CategoryChip.kt).
/// Sélectionnée, elle prend le vert de la marque en aplat : le filtre actif se repère d'un coup d'œil. Capsule
/// visuelle de 36 pt dans une cible de 44 pt. `onRemove` : croix à la fin, bouton séparé (« Retirer ce filtre »).
struct WeydaChip: View {
    private let title: String
    private let isSelected: Bool
    private let iconAsset: String?
    private let onRemove: (() -> Void)?
    private let action: () -> Void

    init(
        title: String,
        isSelected: Bool = false,
        iconAsset: String? = nil,
        onRemove: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.iconAsset = iconAsset
        self.onRemove = onRemove
        self.action = action
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                label
            }
            // Style simple (léger estompage) : la capsule entoure aussi la croix, elle ne doit pas se déformer.
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(contentColor)
                        .padding(.trailing, WeydaSpace.md)
                        .padding(.leading, WeydaSpace.xxs)
                        .frame(minHeight: WeydaSize.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.filtersRemove)
                .accessibilityValue(title)
            }
        }
        .background {
            Capsule()
                .fill(isSelected ? WeydaColor.primary : WeydaColor.surface)
                .overlay {
                    Capsule().strokeBorder(isSelected ? WeydaColor.primary : WeydaColor.outlineVariant, lineWidth: 1)
                }
                .padding(.vertical, WeydaSpace.xs)
        }
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: isSelected)
    }

    private var label: some View {
        HStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
            if let iconAsset {
                CategoryIconImage(assetName: iconAsset, size: WeydaSize.icon - WeydaSpace.xxs)
                    .foregroundStyle(isSelected ? WeydaColor.onPrimary : WeydaColor.primary)
            }
            Text(title)
                .weydaText(.labelLarge)
                .foregroundStyle(contentColor)
                .lineLimit(1)
        }
        .padding(.leading, WeydaSpace.md)
        .padding(.trailing, onRemove == nil ? WeydaSpace.md : WeydaSpace.xxs)
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
    }

    private var contentColor: Color {
        isSelected ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant
    }
}

/// Pastille ronde d'une catégorie — la rangée de l'accueil (CategoryCircle, Android) : cercle teinté portant
/// l'icône Lucide, libellé sur deux lignes, largeur fixe pour un pas de défilement régulier ; l'appui enfonce la
/// pastille (la rangée se parcourt au pouce).
struct CategoryCircle: View {
    private let title: String
    private let iconAsset: String
    private let action: () -> Void

    init(title: String, iconAsset: String, action: @escaping () -> Void) {
        self.title = title
        self.iconAsset = iconAsset
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: WeydaSpace.sm) {
                Circle()
                    .fill(WeydaPalette.categoryTile)
                    .frame(width: WeydaSize.categoryCircle, height: WeydaSize.categoryCircle)
                    .overlay {
                        CategoryIconImage(assetName: iconAsset, size: WeydaSize.iconLarge)
                            .foregroundStyle(WeydaColor.primary)
                    }
                CategoryLabel(title: title)
            }
            .padding(.vertical, WeydaSpace.sm)
            .frame(width: WeydaSize.categoryCell)
            .contentShape(Rectangle())
        }
        .buttonStyle(WeydaPressStyle(pressedScale: 0.94))
        .accessibilityLabel(title)
    }
}

/// Tuile de catégorie (feuille des catégories, grille) : carré teinté portant l'icône, libellé, puis le nombre
/// d'annonces quand il est connu (« 1 234 annonces »).
struct CategoryTile: View {
    private let title: String
    private let iconAsset: String
    private let count: Int?
    private let action: () -> Void

    init(title: String, iconAsset: String, count: Int?, action: @escaping () -> Void) {
        self.title = title
        self.iconAsset = iconAsset
        self.count = count
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: WeydaSpace.sm) {
                RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
                    .fill(WeydaPalette.categoryTile)
                    .frame(width: WeydaSize.avatar, height: WeydaSize.avatar)
                    .overlay {
                        CategoryIconImage(assetName: iconAsset, size: WeydaSize.iconLarge)
                            .foregroundStyle(WeydaColor.primary)
                    }
                VStack(spacing: WeydaSpace.xxs) {
                    CategoryLabel(title: title)
                    if let count {
                        Text(L10n.resultsCount(count))
                            .weydaText(.labelSmall)
                            .foregroundStyle(WeydaColor.onSurfaceVariant)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(.vertical, WeydaSpace.sm)
            .padding(.horizontal, WeydaSpace.xs)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
        }
        .buttonStyle(WeydaPressStyle(pressedScale: 0.96))
    }
}

/// Libellé de catégorie : deux lignes au plus, hauteur de deux lignes toujours réservée (la rangée reste
/// alignée). Un mot seul trop long (« Électroménager ») est réduit sur UNE ligne au lieu d'être coupé en son
/// milieu — Android y arrivait par la césure, que SwiftUI n'expose pas.
private struct CategoryLabel: View {
    let title: String

    var body: some View {
        ZStack(alignment: .top) {
            Text(verbatim: " ")
                .weydaText(.labelMedium)
                .lineLimit(2, reservesSpace: true)
                .hidden()
            if title.contains(" ") {
                Text(title)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            } else {
                Text(title)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
