import SwiftUI
import UIKit

// Rampes de marque — miroir EXACT de ui/theme/Color.kt (Android) et du Tailwind du site :
// emerald #10b981 + accent rouge, neutres slate. Une seule source de vérité : aucune couleur
// n'est définie ailleurs dans l'app (sauf LaunchBackground / AccentColor de l'Asset Catalog,
// que le système lit avant le premier rendu SwiftUI).

nonisolated enum WeydaRamp {
    static let emerald50: UInt32 = 0xECFDF5
    static let emerald100: UInt32 = 0xD1FAE5
    static let emerald200: UInt32 = 0xA7F3D0
    static let emerald300: UInt32 = 0x6EE7B7
    static let emerald400: UInt32 = 0x34D399
    static let emerald500: UInt32 = 0x10B981
    static let emerald600: UInt32 = 0x059669
    static let emerald700: UInt32 = 0x047857
    static let emerald800: UInt32 = 0x065F46
    static let emerald900: UInt32 = 0x064E3B
    static let emerald950: UInt32 = 0x022C22

    static let red100: UInt32 = 0xFEE2E2
    static let red300: UInt32 = 0xFCA5A5
    static let red500: UInt32 = 0xEF4444
    static let red600: UInt32 = 0xDC2626
    static let red700: UInt32 = 0xB91C1C
    static let red900: UInt32 = 0x7F1D1D

    static let amber100: UInt32 = 0xFEF3C7
    static let amber400: UInt32 = 0xFBBF24
    static let amber500: UInt32 = 0xF59E0B
    static let amber700: UInt32 = 0xB45309
    static let amber900: UInt32 = 0x78350F

    static let slate50: UInt32 = 0xF8FAFC
    static let slate100: UInt32 = 0xF1F5F9
    static let slate200: UInt32 = 0xE2E8F0
    static let slate300: UInt32 = 0xCBD5E1
    static let slate400: UInt32 = 0x94A3B8
    static let slate500: UInt32 = 0x64748B
    static let slate600: UInt32 = 0x475569
    static let slate700: UInt32 = 0x334155
    static let slate800: UInt32 = 0x1E293B
    static let slate900: UInt32 = 0x0F172A
    static let slate950: UInt32 = 0x020617

    static let white: UInt32 = 0xFFFFFF
    static let black: UInt32 = 0x000000
}

nonisolated extension UIColor {
    /// Couleur sRGB depuis 0xRRGGBB.
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

nonisolated extension Color {
    /// Couleur fixe, identique en clair et en sombre.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Couleur qui suit l'apparence du système (clair / sombre).
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkOpacity)
                : UIColor(rgb: light, alpha: lightOpacity)
        })
    }
}

/// Rôles de couleur — miroir du ColorScheme Material 3 d'Android (Theme.kt), clair puis sombre.
/// Le fond clair n'est pas blanc mais Slate50 : les cartes blanches s'en détachent sans ombre.
/// Le fond sombre reste au-dessus du noir pur (Slate950) : le noir absolu écrase les photos.
nonisolated enum WeydaColor {
    static let primary = Color(light: WeydaRamp.emerald600, dark: WeydaRamp.emerald400)
    static let onPrimary = Color(light: WeydaRamp.white, dark: WeydaRamp.emerald950)
    static let primaryContainer = Color(light: WeydaRamp.emerald100, dark: WeydaRamp.emerald800)
    static let onPrimaryContainer = Color(light: WeydaRamp.emerald900, dark: WeydaRamp.emerald100)

    /// Accent rouge de la marque.
    static let secondary = Color(light: WeydaRamp.red600, dark: WeydaRamp.red500)
    static let onSecondary = Color(rgb: WeydaRamp.white)
    static let secondaryContainer = Color(light: WeydaRamp.red100, dark: WeydaRamp.red900)
    static let onSecondaryContainer = Color(light: WeydaRamp.red900, dark: WeydaRamp.red100)

    static let tertiary = Color(light: WeydaRamp.amber700, dark: WeydaRamp.amber400)
    static let onTertiary = Color(light: WeydaRamp.white, dark: WeydaRamp.amber900)
    static let tertiaryContainer = Color(light: WeydaRamp.amber100, dark: WeydaRamp.amber900)
    static let onTertiaryContainer = Color(light: WeydaRamp.amber900, dark: WeydaRamp.amber100)

    static let background = Color(light: WeydaRamp.slate50, dark: WeydaRamp.slate950)
    static let onBackground = Color(light: WeydaRamp.slate900, dark: WeydaRamp.slate100)
    static let surface = Color(light: WeydaRamp.white, dark: WeydaRamp.slate900)
    static let onSurface = Color(light: WeydaRamp.slate900, dark: WeydaRamp.slate100)
    static let surfaceVariant = Color(light: WeydaRamp.slate100, dark: WeydaRamp.slate800)
    static let onSurfaceVariant = Color(light: WeydaRamp.slate600, dark: WeydaRamp.slate400)
    static let surfaceContainer = Color(light: WeydaRamp.slate100, dark: WeydaRamp.slate800)
    static let surfaceContainerHigh = Color(light: WeydaRamp.slate200, dark: WeydaRamp.slate700)

    static let outline = Color(light: WeydaRamp.slate400, dark: WeydaRamp.slate600)
    static let outlineVariant = Color(light: WeydaRamp.slate200, dark: WeydaRamp.slate800)

    static let error = Color(light: WeydaRamp.red700, dark: WeydaRamp.red500)
    static let onError = Color(rgb: WeydaRamp.white)
    static let errorContainer = Color(light: WeydaRamp.red100, dark: WeydaRamp.red900)
    static let onErrorContainer = Color(light: WeydaRamp.red900, dark: WeydaRamp.red100)
}

/// Tokens hors rôles — miroir de `WeydaPalette` (Android) : dégradés de marque, voiles sur
/// photo, squelettes, bulles, états sémantiques.
nonisolated enum WeydaPalette {
    /// Surfaces de marque portant du TEXTE BLANC : volontairement sombre (4,5:1 garanti).
    static let brandGradient: [Color] = [
        Color(light: WeydaRamp.emerald700, dark: WeydaRamp.emerald800),
        Color(light: WeydaRamp.emerald900, dark: WeydaRamp.emerald950),
    ]
    /// Tuile-logo (rejoue l'icône de l'app) : vert vif, extrusion vert foncé par-dessus.
    static let iconGradient: [Color] = [
        Color(rgb: WeydaRamp.emerald500),
        Color(light: WeydaRamp.emerald600, dark: WeydaRamp.emerald700),
    ]
    /// Voile posé sur une photo pour garantir 4,5:1 au texte blanc.
    static let photoScrim: [Color] = [
        Color(rgb: WeydaRamp.black, opacity: 0),
        Color(light: WeydaRamp.black, dark: WeydaRamp.black, lightOpacity: 0.6, darkOpacity: 0.7),
    ]
    static let imagePlaceholder = Color(light: WeydaRamp.slate100, dark: WeydaRamp.slate800)
    static let skeleton = Color(light: WeydaRamp.slate200, dark: WeydaRamp.slate800)
    static let skeletonHighlight = Color(light: WeydaRamp.slate100, dark: WeydaRamp.slate700)
    /// Contour hairline des cartes (le contenu de liste ne porte pas d'ombre).
    static let cardOutline = Color(light: WeydaRamp.slate200, dark: WeydaRamp.slate800)
    static let bubbleOwn = Color(light: WeydaRamp.emerald600, dark: WeydaRamp.emerald700)
    static let onBubbleOwn = Color(light: WeydaRamp.white, dark: WeydaRamp.emerald50)
    static let bubbleOther = Color(light: WeydaRamp.slate100, dark: WeydaRamp.slate800)
    static let onBubbleOther = Color(light: WeydaRamp.slate900, dark: WeydaRamp.slate100)
    /// États sémantiques : succès = vendu, avertissement = modération.
    static let success = Color(light: WeydaRamp.emerald700, dark: WeydaRamp.emerald400)
    static let onSuccess = Color(light: WeydaRamp.white, dark: WeydaRamp.emerald950)
    static let warning = Color(light: WeydaRamp.amber500, dark: WeydaRamp.amber400)
    static let onWarning = Color(rgb: WeydaRamp.amber900)
    /// Fond des tuiles de catégorie (l'icône prend `primary`).
    static let categoryTile = Color(light: WeydaRamp.emerald50, dark: WeydaRamp.emerald950)
    /// Pastille « À la une ».
    static let featured = Color(light: WeydaRamp.amber500, dark: WeydaRamp.amber400)
    static let onFeatured = Color(rgb: WeydaRamp.amber900)
}

/// Couleurs fixes de la marque (écran de lancement, extrusion du W) : elles ne suivent pas le thème.
nonisolated enum WeydaBrandColor {
    static let launchBackground = Color(rgb: WeydaRamp.emerald700)
    static let launchGlow = Color(rgb: WeydaRamp.emerald600)
    static let launchSheen = Color(rgb: WeydaRamp.emerald300)
    static let launchTagline = Color(rgb: WeydaRamp.emerald100)
    static let extrusionNear = Color(rgb: WeydaRamp.emerald950)
    static let extrusionFar = Color(rgb: WeydaRamp.emerald800)
    static let launchExtrusionFar = Color(rgb: WeydaRamp.emerald900)
    static let mark = Color(rgb: WeydaRamp.white)
    static let ghostMarkOpacity: Double = 0.14
}
