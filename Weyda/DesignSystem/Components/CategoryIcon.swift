import SwiftUI

/// Visuels d'une catégorie racine, à partir de son `slug` (stable côté serveur). Le champ `icon` de l'API est un
/// emoji : l'app ne l'affiche pas (ni la couleur de la marque, ni le même dessin d'un téléphone à l'autre).
/// - `artworkName` : l'illustration 3D du site (fond pastel), celle des vignettes de catégorie — accueil, feuille
///   des catégories, dépôt, puces, fiche : Assets.xcassets/CategoryArt, généré par scripts/convert-category-art.mjs.
/// - `assetName` : le pictogramme Lucide (ISC) teinté, pour les petits repères (critères d'alerte, ≤ 16 pt) :
///   Assets.xcassets/Categories, généré par scripts/convert-icons.mjs (miroir de `CategoryIcons`, Android).
/// Une catégorie inconnue tombe sur le carton « Autres ».
nonisolated enum CategoryIcon {
    static func assetName(forSlug slug: String?) -> String {
        switch slug {
        case "vehicules": "ic_cat_vehicules"
        case "immobilier": "ic_cat_immobilier"
        case "electronique": "ic_cat_electronique"
        case "emploi": "ic_cat_emploi"
        case "electromenager": "ic_cat_electromenager"
        case "mode": "ic_cat_mode"
        case "maison": "ic_cat_maison"
        case "services": "ic_cat_services"
        case "animaux": "ic_cat_animaux"
        case "loisirs": "ic_cat_loisirs"
        case "materiel-pro": "ic_cat_materiel_pro"
        case "artisanat": "ic_cat_artisanat"
        case "voyage": "ic_cat_voyage"
        default: "ic_cat_autres"
        }
    }

    /// L'illustration 3D d'une catégorie racine (même repli : « Autres »).
    static func artworkName(forSlug slug: String?) -> String {
        "art_" + String(assetName(forSlug: slug).dropFirst("ic_".count))
    }

    /// Tuile « Toutes les catégories ».
    static let all = "ic_cat_all"
    /// Puce de ville.
    static let place = "ic_map_pin"

    /// Les slugs racines connus (démonstration, tests).
    static let knownSlugs = [
        "vehicules", "immobilier", "electronique", "emploi", "electromenager", "mode", "maison",
        "services", "animaux", "loisirs", "materiel-pro", "artisanat", "voyage", "autres",
    ]
}

/// L'icône d'une catégorie, teintée (gabarit), à la taille demandée.
struct CategoryIconImage: View {
    let assetName: String
    var size: CGFloat = WeydaSize.icon

    var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Ce que montre une vignette de catégorie : l'illustration d'une catégorie racine, ou la tuile « Toutes ».
nonisolated enum CategoryArtworkContent: Hashable, Sendable {
    case category(slug: String?)
    case all
}

/// Vignette d'une catégorie — l'illustration 3D du site, fond pastel compris, à bords arrondis continus (tuiles,
/// lignes) ou en disque (puces, pastilles) ; « Toutes » : même forme, vert pâle de la marque et pictogramme de
/// grille. Décorative : le libellé voisin porte le nom. Un liseré très fin la détache d'un fond de teinte voisine.
struct CategoryArtwork: View {
    enum Outline {
        case rounded
        case circle
    }

    private let content: CategoryArtworkContent
    private let size: CGFloat
    private let outline: Outline

    /// Part du côté occupée par le pictogramme de la tuile « Toutes » ; épaisseur du liseré (un demi-point).
    private static let glyphRatio: CGFloat = 0.42
    private static let strokeWidth: CGFloat = 0.5

    init(_ content: CategoryArtworkContent, size: CGFloat, outline: Outline = .rounded) {
        self.content = content
        self.size = size
        self.outline = outline
    }

    var body: some View {
        outlined
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var outlined: some View {
        switch outline {
        case .rounded:
            artwork
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(WeydaPalette.artworkStroke, lineWidth: Self.strokeWidth)
                }
        case .circle:
            artwork
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(WeydaPalette.artworkStroke, lineWidth: Self.strokeWidth)
                }
        }
    }

    private var cornerRadius: CGFloat {
        size * WeydaRadius.artworkRatio
    }

    @ViewBuilder
    private var artwork: some View {
        switch content {
        case .category(let slug):
            Image(CategoryIcon.artworkName(forSlug: slug))
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: size, height: size)
        case .all:
            WeydaPalette.categoryTile
                .frame(width: size, height: size)
                .overlay {
                    CategoryIconImage(assetName: CategoryIcon.all, size: size * Self.glyphRatio)
                        .foregroundStyle(WeydaColor.primary)
                }
        }
    }
}
