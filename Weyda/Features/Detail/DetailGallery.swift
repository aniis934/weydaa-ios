import SwiftUI

/// Galerie de la fiche — portage d'`ImageGallery` (Gallery.kt), comme `ImageGallery.tsx` du site : photo au format
/// 4:3 SANS rognage (le défaut, l'accessoire ou la plaque que l'acheteur cherche peut être au bord), glissement
/// d'une photo à l'autre, compteur « 2 / 8 », miniatures dessous, appui = plein écran avec zoom.
/// `topInset` : hauteur de la barre d'état et de la barre de navigation quand la photo passe dessous (fiche) — voile
/// sombre en haut de la photo, pastille « À la une » décalée sous le bouton retour.
struct DetailGallery: View {
    private let images: [String]
    private let isFeatured: Bool
    private let topInset: CGFloat
    @State private var page: Int = 0
    @State private var fullscreenPage: Int = 0
    @State private var isFullscreen: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(images: [String], isFeatured: Bool, topInset: CGFloat = 0) {
        self.images = images
        self.isFeatured = isFeatured
        self.topInset = topInset
    }

    var body: some View {
        VStack(spacing: 0) {
            pager
            if images.count > 1 {
                thumbnails
            }
        }
        // Retour du plein écran : la galerie reprend à la photo regardée en dernier (Android aussi).
        .fullScreenCover(isPresented: $isFullscreen, onDismiss: { page = fullscreenPage }) {
            DetailFullscreenGallery(images: images, page: $fullscreenPage, onClose: { isFullscreen = false })
        }
    }

    // MARK: - Photo

    @ViewBuilder
    private var pager: some View {
        if images.isEmpty {
            ListingCoverImage(url: nil)
                .overlay(alignment: .top) { DetailTopScrim(topInset: topInset) }
                .overlay(alignment: .topLeading) { featuredBadge }
        } else {
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    photos
                }
                .background(WeydaPalette.imagePlaceholder)
                .clipped()
                .overlay(alignment: .top) { DetailTopScrim(topInset: topInset) }
                .overlay(alignment: .bottomTrailing) { counter }
                // Un seul élément VoiceOver : « Photo 2 sur 8 », balayer vers le haut / le bas change de photo,
                // toucher deux fois ouvre le plein écran.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.detailPhotoCounter(page + 1, images.count))
                .accessibilityHint(L10n.detailOpenGallery)
                .accessibilityAddTraits([.isButton, .isImage])
                .accessibilityAction {
                    openFullscreen(at: page)
                }
                .accessibilityAdjustableAction { direction in
                    adjust(direction)
                }
                .accessibilityIdentifier("detail.gallery")
                // Posé APRÈS l'élément VoiceOver de la galerie : « À la une » est lu à part (il disparaissait avec les
                // enfants ignorés). Même rendu : coin opposé au compteur, au-dessus de la photo.
                .overlay(alignment: .topLeading) { featuredBadge }
        }
    }

    /// Sur la fiche, la galerie passe sous la barre d'état : chaque page occupe TOUT le cadre 4:3 (une page ne doit pas
    /// se décaler de la hauteur des barres du haut) — le cadre lui-même est rogné par `pager`.
    private var photos: some View {
        TabView(selection: $page) {
            ForEach(images.indices, id: \.self) { index in
                RemoteImage(urlString: images[index], contentMode: .fit)
                    .ignoresSafeArea(edges: .top)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openFullscreen(at: index)
                    }
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .top)
    }

    /// Sous la barre de navigation (la photo passe dessous) : jamais sous le bouton retour.
    @ViewBuilder
    private var featuredBadge: some View {
        if isFeatured {
            FeaturedBadge()
                .padding(WeydaSpace.md)
                .padding(.top, topInset)
        }
    }

    @ViewBuilder
    private var counter: some View {
        if images.count > 1 {
            DetailPhotoCounter(current: page + 1, total: images.count)
                .padding(WeydaSpace.md)
        }
    }

    // MARK: - Miniatures

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WeydaSpace.sm) {
                    ForEach(images.indices, id: \.self) { index in
                        thumbnail(index)
                            .id(index)
                    }
                }
                .padding(.horizontal, WeydaSpace.screen)
                .padding(.vertical, WeydaSpace.sm)
            }
            .onChange(of: page) { newPage in
                reveal(newPage, in: proxy)
            }
        }
    }

    private func thumbnail(_ index: Int) -> some View {
        let selected = index == page
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous)
        let stroke: Color = selected ? WeydaColor.primary : WeydaPalette.cardOutline
        let width: CGFloat = selected ? 2 : 1
        return Button {
            select(index)
        } label: {
            RemoteImage(urlString: thumbnailUrl(images[index]), fallbackURLString: images[index])
                .frame(width: DetailGalleryMetrics.thumbSide, height: DetailGalleryMetrics.thumbSide)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(stroke, lineWidth: width)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.detailPhotoCounter(index + 1, images.count))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Actions

    private func openFullscreen(at index: Int) {
        fullscreenPage = index
        isFullscreen = true
    }

    private func select(_ index: Int) {
        if reduceMotion {
            page = index
        } else {
            withAnimation(.easeInOut(duration: WeydaDuration.medium)) {
                page = index
            }
        }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        if direction == .increment && page < images.count - 1 {
            page += 1
        } else if direction == .decrement && page > 0 {
            page -= 1
        }
    }

    /// La miniature de la photo affichée reste visible dans la rangée.
    private func reveal(_ index: Int, in proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: WeydaDuration.medium)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }
}

/// Compteur « 2 / 8 » sur la photo. Isolé de gauche à droite : en arabe, « 1 / 2 » s'affichait « 2 / 1 ».
struct DetailPhotoCounter: View {
    private let current: Int
    private let total: Int

    init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }

    var body: some View {
        Text(Format.ltrIsolate("\(current) / \(total)"))
            .weydaText(.labelMedium)
            .foregroundStyle(DetailGalleryColor.onScrim)
            .padding(.horizontal, WeydaSpace.sm)
            .padding(.vertical, WeydaSpace.xxs)
            .background(DetailGalleryColor.scrim, in: Capsule())
            .accessibilityLabel(L10n.detailPhotoCounter(current, total))
    }
}

/// Voile dégradé sombre en haut de la photo, sous la barre d'état et la barre de navigation transparente : la barre
/// d'état et les boutons restent lisibles sur une photo claire. Décoratif (ni appui, ni VoiceOver) ; rien quand la
/// photo ne passe pas sous les barres (`topInset` nul, hors ligne).
struct DetailTopScrim: View {
    private let topInset: CGFloat

    init(topInset: CGFloat) {
        self.topInset = topInset
    }

    var body: some View {
        if topInset > 0 {
            LinearGradient(
                colors: [DetailGalleryColor.scrim, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: topInset + WeydaSpace.xxxl)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Couleurs de la galerie : elles se posent sur une photo ou sur le noir du plein écran, pas sur le thème
/// (Android : `Color.Black` 55 % et blanc).
nonisolated enum DetailGalleryColor {
    static let backdrop = Color(rgb: WeydaRamp.black)
    static let scrim = Color(rgb: WeydaRamp.black, opacity: 0.55)
    static let onScrim = Color(rgb: WeydaRamp.white)
}

/// Mesures de la galerie (Android : THUMB_SIZE, ZOOM_MAX, ZOOM_DOUBLE_TAP).
nonisolated enum DetailGalleryMetrics {
    static let thumbSide: CGFloat = 56
    static let maxZoom: CGFloat = 4
    static let doubleTapZoom: CGFloat = 2.5
    /// Glisser vers le bas au-delà de cette distance (ou d'un geste vif) ferme le plein écran.
    static let dismissDistance: CGFloat = 120
    static let dismissPrediction: CGFloat = 320
}
