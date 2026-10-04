import SwiftUI

extension View {
    /// Mode vitrine des captures de la fiche App Store (`-WeydaStoreCaption <1…8>`, Debug et API simulée seulement) :
    /// la vue — la racine de l'app — passe réduite sous une légende de marque (`StoreFrame`). Sans l'argument, et
    /// toujours en Release, la vue telle quelle.
    @ViewBuilder
    func storeFrame() -> some View {
        #if DEBUG
        if let number = LaunchOptions.storeCaption, let caption = StoreCaption(rawValue: number) {
            StoreFrame(caption: caption, content: self)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Les 8 légendes de la fiche, dans l'ordre de `docs/store/screenshots.md` (chaînes du catalogue, fr / ar / en).
nonisolated enum StoreCaption: Int, CaseIterable, Sendable {
    case home = 1
    case listings
    case detail
    case chat
    case post
    case seller
    case lists
    case dark

    var text: String {
        switch self {
        case .home: L10n.storeCaption1
        case .listings: L10n.storeCaption2
        case .detail: L10n.storeCaption3
        case .chat: L10n.storeCaption4
        case .post: L10n.storeCaption5
        case .seller: L10n.storeCaption6
        case .lists: L10n.storeCaption7
        case .dark: L10n.storeCaption8
        }
    }
}

/// Géométrie de la vitrine (logique pure, en points), tirée de la zone sûre de l'écran (`container`).
///  · L'app est MISE EN PAGE en pleine largeur, sur la hauteur de la zone sûre moins `edgeGap` en haut et en bas : elle
///    ne touche aucun bord de la zone sûre, donc ni SwiftUI (TabView) ni UIKit (barres) n'y ajoutent la marge de l'île
///    ou de l'indicateur d'accueil — la barre de navigation tient le haut du cadre, celle des onglets le bas, et la
///    hauteur utile est celle du vrai téléphone entre ses deux marges (mêmes cadrages que le tour de captures).
///  · Elle est ensuite RÉDUITE au rendu seulement (`scale`) et descendue (`offsetY`) : la légende prend le haut
///    (`captionHeight`). Le rendu réduit reste lui aussi dans la zone sûre.
nonisolated struct StoreFrameLayout: Equatable, Sendable {
    /// ≈ 80 % : marges latérales ≈ 44 pt sur l'iPhone 17 Pro Max, place pour deux lignes de légende.
    static let preferredScale: CGFloat = 0.8
    static let minimumScale: CGFloat = 0.6
    static let edgeGap: CGFloat = 2
    /// Écart entre le bas du cadre et le bas de la zone sûre.
    static let bottomMargin: CGFloat = 4
    /// Place minimale de la légende (W + deux lignes) : en deçà, l'app est réduite davantage.
    static let minimumCaptionHeight: CGFloat = 120

    /// Taille de MISE EN PAGE de l'app (avant réduction).
    let appSize: CGSize
    let scale: CGFloat
    /// Décalage vertical du rendu réduit (depuis le centre de la zone sûre).
    let offsetY: CGFloat
    /// Hauteur de la bande de légende, depuis le haut de la zone sûre jusqu'au haut du cadre.
    let captionHeight: CGFloat

    init(container: CGSize) {
        let appHeight = max(container.height - 2 * Self.edgeGap, 1)
        let fitting = (container.height - Self.bottomMargin - Self.minimumCaptionHeight) / appHeight
        let scale = max(Self.minimumScale, min(Self.preferredScale, fitting))
        let cardHeight = appHeight * scale
        let cardBottom = container.height - Self.bottomMargin
        self.appSize = CGSize(width: container.width, height: appHeight)
        self.scale = scale
        self.offsetY = (cardBottom - cardHeight / 2) - container.height / 2
        self.captionHeight = max(cardBottom - cardHeight, 0)
    }

    /// Rayon en points de mise en page : une fois réduit, le coin visible vaut `WeydaRadius.sheet`.
    var cornerRadius: CGFloat {
        WeydaRadius.sheet / scale
    }
}

/// Mesures et couleurs propres à la vitrine.
private nonisolated enum StoreFrameStyle {
    /// Le W de la légende : discret, la légende reste le message.
    static let markSize: CGFloat = 28
    /// Ombre teintée de vert foncé (Emerald950, l'extrusion du W : une ombre noire salit le fond de marque) ; rayon et
    /// décalage en points de mise en page.
    static let shadow = Color(rgb: WeydaRamp.emerald950, opacity: 0.45)
    static let shadowRadius: CGFloat = 30
    static let shadowY: CGFloat = 16
    /// Légende trop longue pour deux lignes (arabe, anglais) : réduite plutôt que tronquée.
    static let captionMinScale: CGFloat = 0.7
}

/// Vitrine d'une capture de la fiche App Store (Debug) : fond vert de la marque, légende en haut (W de la marque, texte
/// en grand et en gras, centré, 2 lignes au plus, de droite à gauche en arabe), puis l'app réduite dans un cadre aux
/// coins continus, ombre douce. Sans Mac ni compte Apple, c'est la seule façon d'avoir des légendes arabes composées
/// par le système. Barre d'état masquée : en clair, l'heure noire sur le vert jurait, et la capture devient une image
/// de fiche (comme les vitrines des grandes apps) plutôt qu'un écran de téléphone. Le cadre ne reçoit aucun appui
/// utile (coordonnées réduites) : chaque capture s'ouvre directement sur son état par les arguments de lancement.
struct StoreFrame<Content: View>: View {
    private let caption: StoreCaption
    private let content: Content

    init(caption: StoreCaption, content: Content) {
        self.caption = caption
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            StoreFrameCanvas(caption: caption, layout: StoreFrameLayout(container: proxy.size), content: content)
        }
        .background(WeydaBrandColor.launchBackground)
        .statusBarHidden(true)
    }
}

/// La légende en haut, l'app réduite dessous ; la zone sûre de l'écran pour tout repère.
private struct StoreFrameCanvas<Content: View>: View {
    let caption: StoreCaption
    let layout: StoreFrameLayout
    let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            StoreAppCard(layout: layout, content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StoreCaptionBand(text: caption.text)
                .frame(maxWidth: .infinity)
                .frame(height: layout.captionHeight)
        }
    }
}

/// L'app mise en page à sa taille (`appSize`), découpée en coins continus, posée sur une ombre douce, puis réduite et
/// descendue AU RENDU seulement (`scaleEffect`, `offset` : la mise en page de l'app ne change pas).
private struct StoreAppCard<Content: View>: View {
    let layout: StoreFrameLayout
    let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        content
            .frame(width: layout.appSize.width, height: layout.appSize.height)
            .clipShape(shape)
            .background {
                // Ombre portée par une forme SwiftUI (fiable) plutôt que par les vues UIKit de l'app.
                shape
                    .fill(WeydaColor.background)
                    .shadow(color: StoreFrameStyle.shadow, radius: StoreFrameStyle.shadowRadius, x: 0, y: StoreFrameStyle.shadowY)
            }
            .scaleEffect(layout.scale)
            .offset(y: layout.offsetY)
    }
}

/// Le W de la marque (relief vert foncé, comme l'écran de lancement) et la légende, en blanc sur le vert. Taille de
/// texte figée au réglage par défaut : la vitrine est une image, pas un écran à lire en grand texte.
private struct StoreCaptionBand: View {
    let text: String

    var body: some View {
        VStack(spacing: WeydaSpace.sm) {
            WeydaMarkExtruded(
                size: StoreFrameStyle.markSize,
                near: WeydaBrandColor.extrusionNear,
                far: WeydaBrandColor.launchExtrusionFar
            )
            Text(text)
                .weydaText(.headlineLarge)
                .foregroundStyle(WeydaBrandColor.mark)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(StoreFrameStyle.captionMinScale)
                .accessibilityIdentifier("store.caption")
        }
        .padding(.horizontal, WeydaSpace.xxl)
        .padding(.vertical, WeydaSpace.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(.large)
    }
}
#endif
