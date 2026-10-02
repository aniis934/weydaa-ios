import SwiftUI

/// Icône vectorielle d'une catégorie racine, à partir de son `slug` (stable côté serveur) —
/// miroir de `CategoryIcons` (Android). Le champ `icon` de l'API est un emoji : l'app ne
/// l'affiche pas (ni la couleur de la marque, ni le même dessin d'un téléphone à l'autre).
/// Jeu Lucide (ISC), celui du site : Assets.xcassets/Categories, généré par scripts/convert-icons.mjs.
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
