import SwiftUI

/// Puce unique de l'app (catégories, villes, filtres actifs, tri) — portage de `WeydaChip` (CategoryChip.kt).
/// Sélectionnée, elle prend le vert de la marque en aplat : le filtre actif se repère d'un coup d'œil. Capsule
/// visuelle de 36 pt dans une cible de 44 pt. `onRemove` : croix à la fin, bouton séparé (« Retirer ce filtre »).
/// `artwork` (puces de catégorie) : l'illustration en disque de 24 pt au début, concentrique à la capsule ; il suit
/// la taille du texte (40 pt au plus) pour ne pas devenir un point à côté d'un très grand libellé.
struct WeydaChip: View {
    private let title: String
    private let isSelected: Bool
    private let iconAsset: String?
    private let artwork: CategoryArtworkContent?
    private let onRemove: (() -> Void)?
    private let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var scaledArtworkSide: CGFloat = WeydaSize.categoryArtworkChip

    /// Retrait du disque d'illustration : (capsule 36 pt − disque 24 pt) / 2 — même écart tout autour.
    private static let artworkInset: CGFloat = WeydaSpace.xs + WeydaSpace.xxs

    init(
        title: String,
        isSelected: Bool = false,
        iconAsset: String? = nil,
        artwork: CategoryArtworkContent? = nil,
        onRemove: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.iconAsset = iconAsset
        self.artwork = artwork
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
            if let artwork {
                CategoryArtwork(artwork, size: artworkSide, outline: .circle)
            } else if let iconAsset {
                CategoryIconImage(assetName: iconAsset, size: WeydaSize.icon - WeydaSpace.xxs)
                    .foregroundStyle(isSelected ? WeydaColor.onPrimary : WeydaColor.primary)
            }
            Text(title)
                .weydaText(.labelLarge)
                .foregroundStyle(contentColor)
                .lineLimit(1)
        }
        .padding(.leading, artwork == nil ? WeydaSpace.md : Self.artworkInset)
        .padding(.trailing, onRemove == nil ? WeydaSpace.md : WeydaSpace.xxs)
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
    }

    private var contentColor: Color {
        isSelected ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant
    }

    private var artworkSide: CGFloat {
        min(scaledArtworkSide, WeydaSize.categoryArtworkChipMax)
    }
}

/// Raccourci de catégorie — la rangée de l'accueil, comme sur le site (`HomeCategoryBar`) : l'illustration 3D en
/// tuile arrondie de 64 pt, libellé sur deux lignes, largeur fixe pour un pas de défilement régulier ; l'appui
/// enfonce la tuile (la rangée se parcourt au pouce).
struct CategoryShortcut: View {
    private let title: String
    private let artwork: CategoryArtworkContent
    private let action: () -> Void

    init(title: String, artwork: CategoryArtworkContent, action: @escaping () -> Void) {
        self.title = title
        self.artwork = artwork
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: WeydaSpace.sm) {
                CategoryArtwork(artwork, size: WeydaSize.categoryArtwork)
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

/// Tuile de catégorie (grille) : l'illustration 3D, libellé, puis le nombre d'annonces quand il est connu
/// (« 1 234 annonces »).
struct CategoryTile: View {
    private let title: String
    private let artwork: CategoryArtworkContent
    private let count: Int?
    private let action: () -> Void

    init(title: String, artwork: CategoryArtworkContent, count: Int?, action: @escaping () -> Void) {
        self.title = title
        self.artwork = artwork
        self.count = count
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: WeydaSpace.sm) {
                CategoryArtwork(artwork, size: WeydaSize.avatar)
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
