import SwiftUI

/*
 * Squelettes de chargement — portage de `components/Skeletons.kt`. Partout où la FORME de ce qui arrive est
 * connue, ils remplacent l'indicateur plein écran : l'écran est déjà composé quand les données tombent, rien ne
 * saute, et l'attente paraît plus courte. `LoadingState` reste pour les attentes de forme inconnue.
 * Les blocs sont masqués à VoiceOver ; chaque rangée de squelettes est lue une fois « Chargement… ».
 */

extension View {
    /// Scintillement : un reflet balaie la forme en diagonale (1,25 s, comme Android), toutes les formes de
    /// l'écran en phase. Immobile avec « Réduire les animations », et pendant les captures (`-WeydaFreezeMotion`).
    func weydaShimmer(active: Bool = true) -> some View {
        modifier(WeydaShimmer(active: active))
    }
}

/// Bloc gris scintillant. `width` nil = toute la largeur proposée.
struct SkeletonBlock: View {
    private let width: CGFloat?
    private let height: CGFloat
    private let radius: CGFloat

    init(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = WeydaRadius.badge) {
        self.width = width
        self.height = height
        self.radius = radius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(WeydaPalette.skeleton)
            .frame(width: width, height: height)
            .weydaShimmer()
            .accessibilityHidden(true)
    }
}

/// Fantôme d'une carte verticale (`ListingCard`) : prend la largeur proposée (grille) ; carrousel :
/// `.frame(width: WeydaSize.carouselCard)`, ou directement `ListingCardSkeletonRow()`.
struct ListingCardSkeleton: View {
    init() {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(WeydaPalette.skeleton)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .weydaShimmer()
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                SkeletonBlock(height: SkeletonLine.text)
                SkeletonBlock(width: SkeletonLine.short, height: SkeletonLine.text)
                SkeletonBlock(width: SkeletonLine.price, height: SkeletonLine.priceHeight)
                    .padding(.top, WeydaSpace.xs)
            }
            .padding(WeydaSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WeydaColor.surface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Fantôme d'une ligne de résultat (`ListingRow`).
struct ListingRowSkeleton: View {
    init() {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        HStack(alignment: .top, spacing: WeydaSpace.md) {
            SkeletonBlock(width: WeydaSize.rowThumbWidth, height: WeydaSize.rowThumbHeight, radius: WeydaRadius.thumb)
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                SkeletonBlock(height: SkeletonLine.text)
                SkeletonBlock(width: SkeletonLine.short, height: SkeletonLine.text)
                SkeletonBlock(width: SkeletonLine.price, height: SkeletonLine.priceHeight)
                    .padding(.top, WeydaSpace.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WeydaSpace.sm)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Liste de fantômes de lignes — l'écran Annonces pendant sa première requête. Porte la gouttière latérale.
struct ListingRowSkeletons: View {
    private let count: Int

    init(count: Int = 6) {
        self.count = count
    }

    var body: some View {
        VStack(spacing: WeydaSpace.gutter) {
            ForEach(0..<max(count, 0), id: \.self) { _ in
                ListingRowSkeleton()
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.vertical, WeydaSpace.sm)
        .skeletonAccessibility()
    }
}

/// Rangée de fantômes de cartes à la largeur du carrousel « À la une » (la deuxième dépasse du bord, comme le
/// vrai carrousel). Porte la gouttière latérale.
struct ListingCardSkeletonRow: View {
    init() {}

    var body: some View {
        HStack(alignment: .top, spacing: WeydaSpace.gutter) {
            ForEach(0..<2, id: \.self) { _ in
                ListingCardSkeleton()
                    .frame(width: WeydaSize.carouselCard)
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .skeletonAccessibility()
    }
}

/// Rangée de fantômes de tuiles — les catégories de l'accueil (même forme que l'illustration). Porte la gouttière
/// latérale.
struct CategoryShortcutSkeletonRow: View {
    init() {}

    var body: some View {
        HStack(alignment: .top, spacing: WeydaSpace.sm) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(spacing: WeydaSpace.sm) {
                    SkeletonBlock(
                        width: WeydaSize.categoryArtwork,
                        height: WeydaSize.categoryArtwork,
                        radius: WeydaSize.categoryArtwork * WeydaRadius.artworkRatio
                    )
                    SkeletonBlock(width: SkeletonLine.label, height: SkeletonLine.labelHeight)
                }
                .padding(.vertical, WeydaSpace.sm)
                .frame(width: WeydaSize.categoryCell)
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .skeletonAccessibility()
    }
}

/// Rangée de fantômes de puces — les villes de l'accueil. Porte la gouttière latérale.
struct ChipSkeletonRow: View {
    init() {}

    /// Largeurs variées, comme des noms de villes (Android : 96, 78, 110, 84).
    private static let widths: [CGFloat] = [96, 78, 110, 84]

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            ForEach(Self.widths.indices, id: \.self) { index in
                SkeletonBlock(width: Self.widths[index], height: SkeletonLine.chip, radius: SkeletonLine.chip / 2)
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .skeletonAccessibility()
    }
}

/// Gabarits des lignes de texte fantômes (hauteurs et largeurs d'Android, en points).
private enum SkeletonLine {
    static let text: CGFloat = 12
    static let short: CGFloat = 104
    static let price: CGFloat = 88
    static let priceHeight: CGFloat = 16
    static let label: CGFloat = 48
    static let labelHeight: CGFloat = 10
    static let chip: CGFloat = 36
}

private extension View {
    /// Une rangée de fantômes = un seul élément VoiceOver, « Chargement… ».
    func skeletonAccessibility() -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.loading)
    }
}

/// Le reflet est un calque masqué par la forme elle-même : il en suit les coins arrondis.
private struct WeydaShimmer: ViewModifier {
    private let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(active: Bool) {
        self.active = active
    }

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion && !LaunchOptions.freezeMotion {
                ShimmerSweep()
                    .mask { content }
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ShimmerSweep: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: ShimmerClock.frameInterval)) { context in
            let head = ShimmerClock.head(at: context.date)
            LinearGradient(
                colors: [
                    WeydaPalette.skeletonHighlight.opacity(0),
                    WeydaPalette.skeletonHighlight,
                    WeydaPalette.skeletonHighlight.opacity(0),
                ],
                startPoint: UnitPoint(x: head - ShimmerClock.halfWidth, y: 0),
                endPoint: UnitPoint(x: head + ShimmerClock.halfWidth, y: 1)
            )
        }
        .accessibilityHidden(true)
    }
}

/// Horloge commune du scintillement : toutes les formes à l'écran balayent ensemble.
nonisolated enum ShimmerClock {
    static let period: Double = 1.25
    static let halfWidth: Double = 0.35
    static let frameInterval: Double = 1.0 / 60.0

    /// Position de la tête du reflet, en largeurs de la forme : de -0,5 à 1,5 sur une période, puis recommence.
    static func head(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        let progress = elapsed.truncatingRemainder(dividingBy: period) / period
        return -0.5 + progress * 2
    }
}
