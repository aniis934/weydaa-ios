import SwiftUI

/// Note en étoiles (avis, moyenne d'un vendeur) — portage de `RatingStars.kt`, demi-étoiles en plus pour les
/// moyennes. Les glyphes seuls sont illisibles pour VoiceOver : la note est annoncée en clair (« 4 étoiles
/// sur 5 »). En arabe, les étoiles se remplissent depuis la droite (sens de lecture).
struct RatingStars: View {
    private let rating: Double
    private let size: CGFloat
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    init(rating: Double, size: CGFloat = 14) {
        self.rating = rating
        self.size = size
    }

    var body: some View {
        HStack(spacing: WeydaSpace.xxs) {
            ForEach(0..<RatingStarSymbols.maxStars, id: \.self) { index in
                Image(systemName: RatingStarSymbols.symbol(at: index, rating: rating))
                    .font(.system(size: size * scale))
            }
        }
        .foregroundStyle(WeydaColor.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RatingStarSymbols.spokenLabel(rating))
    }
}

/// Règles d'affichage d'une note (logique pure, testée).
nonisolated enum RatingStarSymbols {
    static let maxStars = 5

    /// Étoile `index` (0 à 4) pour une note arrondie à la demi-étoile : pleine, moitié (côté début de lecture), vide.
    static func symbol(at index: Int, rating: Double) -> String {
        let halves = Int((min(max(rating, 0), Double(maxStars)) * 2).rounded())
        let full = halves / 2
        if index < full { return "star.fill" }
        if index == full && halves % 2 == 1 { return "star.leadinghalf.filled" }
        return "star"
    }

    /// Annonce VoiceOver : « 4 étoiles sur 5 » pour une note entière, « 4,5 sur 5 » pour une moyenne (chiffres latins).
    static func spokenLabel(_ rating: Double) -> String {
        let tenths = (min(max(rating, 0), Double(maxStars)) * 10).rounded() / 10
        if tenths == tenths.rounded() { return L10n.reviewStar(Int(tenths)) }
        return L10n.ratingOutOfFive(tenths.formatted(.number.precision(.fractionLength(1)).locale(WeydaLocale.formatting)))
    }

    /// Étoiles annoncées (le catalogue n'a qu'un pluriel entier) : la note arrondie à l'entier le plus proche.
    static func spokenStars(_ rating: Double) -> Int {
        Int(min(max(rating, 0), Double(maxStars)).rounded())
    }
}
