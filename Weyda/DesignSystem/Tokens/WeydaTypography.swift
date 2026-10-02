import SwiftUI

/// Échelle typographique — miroir de `WeydaTypography` (Android), posée sur les styles de texte
/// d'iOS pour suivre la taille de texte de l'utilisateur (Dynamic Type) : SF Pro, zéro octet de
/// fonte, l'arabe couvert par SF Arabic. La personnalité vient des GRAISSES et du CRÉNAGE :
///  · titres  heavy, interlettrage NÉGATIF → compact, affirmé, « marque » ;
///  · corps   regular ;
///  · labels  medium, interlettrage POSITIF → les petits textes restent lisibles.
nonisolated enum WeydaTextStyle: Sendable, CaseIterable {
    case headlineLarge, headlineMedium, headlineSmall
    case titleLarge, titleMedium, titleSmall
    case bodyLarge, bodyMedium, bodySmall
    case labelLarge, labelMedium, labelSmall
    /// Le prix : l'information n° 1 d'une petite annonce.
    case price, priceLarge
    /// Le mot « Weydaa » écrit à côté du W.
    case mark

    var font: Font {
        switch self {
        case .headlineLarge: .system(.largeTitle, weight: .heavy)
        case .headlineMedium: .system(.title, weight: .heavy)
        case .headlineSmall: .system(.title2, weight: .heavy)
        case .titleLarge: .system(.title3, weight: .bold)
        case .titleMedium: .system(.callout, weight: .semibold)
        case .titleSmall: .system(.subheadline, weight: .semibold)
        case .bodyLarge: .body
        case .bodyMedium: .subheadline
        case .bodySmall: .caption
        case .labelLarge: .system(.subheadline, weight: .medium)
        case .labelMedium: .system(.caption, weight: .medium)
        case .labelSmall: .system(.caption2, weight: .medium)
        case .price: .system(.headline, weight: .heavy)
        case .priceLarge: .system(.title, weight: .heavy)
        case .mark: .system(.title, weight: .black)
        }
    }

    /// Interlettrage en points (Android : letterSpacing en sp).
    var tracking: CGFloat {
        switch self {
        case .headlineLarge: -0.5
        case .headlineMedium: -0.4
        case .headlineSmall: -0.3
        case .titleLarge: -0.2
        case .titleMedium: 0
        case .titleSmall: 0.1
        case .bodyLarge, .bodyMedium: 0.1
        case .bodySmall: 0.2
        case .labelLarge: 0.1
        case .labelMedium: 0.4
        case .labelSmall: 0.5
        case .price: -0.3
        case .priceLarge: -0.6
        case .mark: -1.0
        }
    }
}

extension View {
    /// Applique un style de l'échelle Weyda (police + interlettrage).
    func weydaText(_ style: WeydaTextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
