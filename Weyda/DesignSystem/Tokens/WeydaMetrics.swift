import CoreGraphics

/// Échelle d'espacement à pas de 4 pt — miroir de `WeydaSpace` (Android, en dp). `screen` est la
/// marge latérale de TOUS les écrans : cartes, titres de section et barres restent alignés.
nonisolated enum WeydaSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Marge latérale de référence (gouttière des écrans).
    static let screen: CGFloat = 16
    /// Écart entre deux cartes d'une même grille / liste.
    static let gutter: CGFloat = 12
    /// Respiration au-dessus d'un titre de section.
    static let section: CGFloat = 24
}

nonisolated enum WeydaSize {
    /// Cible tactile minimale (Apple HIG : 44 pt ; Android : 48 dp).
    static let touchTarget: CGFloat = 44
    static let icon: CGFloat = 20
    static let iconLarge: CGFloat = 28
    /// Pictogramme d'un état vide / d'attente.
    static let stateIcon: CGFloat = 44
    static let avatar: CGFloat = 56
    static let avatarSmall: CGFloat = 40
    /// Vignette d'une ligne de résultat.
    static let rowThumbWidth: CGFloat = 116
    static let rowThumbHeight: CGFloat = 92
    /// Carte du carrousel « À la une » (≈ 70 % de la largeur d'un iPhone, comme le site).
    static let carouselCard: CGFloat = 232
    /// Illustration d'une catégorie sur l'accueil (= taille de référence des images @2x/@3x : 192 px à l'écran,
    /// pixel pour pixel), et la cellule (illustration + libellé) qui la porte.
    static let categoryArtwork: CGFloat = 64
    static let categoryCell: CGFloat = 76
    /// Illustration d'une catégorie dans une ligne de liste (feuille des catégories) et dans une puce.
    static let categoryArtworkRow: CGFloat = 40
    static let categoryArtworkChip: CGFloat = 24
    /// Hauteur du bandeau de marque de l'accueil.
    static let brandHeader: CGFloat = 132
    /// Largeur maximale du contenu (iPad en mode iPhone, paysage) et d'un formulaire.
    static let contentMaxWidth: CGFloat = 840
    static let formMaxWidth: CGFloat = 560
    /// Le W de l'écran de lancement (= SplashMark de l'écran système, 160 pt).
    static let launchMark: CGFloat = 160
}

/// Rayons — miroir de `WeydaShape` (Android). Les capsules (recherche, boutons pleine largeur)
/// utilisent `Capsule()` ; toujours `style: .continuous` (courbe iOS).
nonisolated enum WeydaRadius {
    /// Pastilles, badges, petits conteneurs de texte.
    static let badge: CGFloat = 8
    /// Vignette image dans une ligne de liste ; champ de saisie.
    static let thumb: CGFloat = 12
    static let field: CGFloat = 12
    /// Carte annonce / conversation / notification : la forme la plus fréquente.
    static let card: CGFloat = 16
    /// Blocs de section (en-tête d'accueil, encarts).
    static let panel: CGFloat = 20
    /// Feuille modale ancrée en bas.
    static let sheet: CGFloat = 28
    /// Bulle de conversation : coin côté auteur rentré.
    static let bubble: CGFloat = 18
    static let bubbleTail: CGFloat = 4
    /// Tuile-logo : même courbe que l'icône iOS (≈ 22,37 % du côté).
    static let iconRatio: CGFloat = 0.2237
    /// Illustration de catégorie : rayon = 27 % du côté (site : `rounded-2xl` sur 56 px ≈ 29 %).
    static let artworkRatio: CGFloat = 0.27
}
