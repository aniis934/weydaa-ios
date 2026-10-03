import SwiftUI
import UIKit

/// Plein écran de la galerie — portage de `FullscreenGallery` (Gallery.kt) : fond noir, glissement d'une photo à
/// l'autre, pincement ou double-toucher pour zoomer (×4 au plus), et pour sortir « Fermer », un glissement vers le
/// bas (photo non zoomée) ou le geste « retour » de VoiceOver. Une photo zoomée se déplace sous le doigt ; arrivée
/// au bord, le glissement passe à la photo voisine (comme Photos).
struct DetailFullscreenGallery: View {
    private let images: [String]
    @Binding private var page: Int
    private let onClose: () -> Void
    @State private var zoomed: Bool = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(images: [String], page: Binding<Int>, onClose: @escaping () -> Void) {
        self.images = images
        self._page = page
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .top) {
            DetailGalleryColor.backdrop
                .opacity(backdropOpacity)
                .ignoresSafeArea()
            pages
                .offset(y: dragOffset)
            topBar
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.gallery")
        .accessibilityAction(.escape) {
            onClose()
        }
    }

    /// Le noir s'éclaircit à mesure que la photo descend : on voit qu'on est en train de fermer.
    private var backdropOpacity: Double {
        1 - min(Double(dragOffset) / 600, 0.6)
    }

    private var pages: some View {
        TabView(selection: $page) {
            ForEach(images.indices, id: \.self) { index in
                DetailZoomablePhoto(url: images[index], isCurrent: index == page) { isZoomed in
                    if index == page {
                        zoomed = isZoomed
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.detailPhotoCounter(index + 1, images.count))
                .accessibilityAddTraits(.isImage)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .simultaneousGesture(dismissDrag, including: zoomed ? .subviews : .all)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: WeydaSpace.sm) {
            if images.count > 1 {
                DetailPhotoCounter(current: page + 1, total: images.count)
            }
            Spacer(minLength: WeydaSpace.sm)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DetailGalleryColor.onScrim)
                    .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                    .background(DetailGalleryColor.scrim, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.close)
            .accessibilityIdentifier("gallery.close")
        }
        .padding(.horizontal, WeydaSpace.lg)
        .padding(.top, WeydaSpace.sm)
        .opacity(dragOffset > 0 ? 0 : 1)
    }

    /// Glisser vers le bas une photo non zoomée : elle suit le doigt, puis ferme ou revient en place.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let vertical = value.translation.height
                guard vertical > 0, abs(vertical) > abs(value.translation.width) else { return }
                dragOffset = vertical
            }
            .onEnded { value in
                let far = dragOffset > DetailGalleryMetrics.dismissDistance
                let flung = dragOffset > 0 && value.predictedEndTranslation.height > DetailGalleryMetrics.dismissPrediction
                if far || flung {
                    onClose()
                } else {
                    settleBack()
                }
            }
    }

    private func settleBack() {
        if reduceMotion {
            dragOffset = 0
        } else {
            withAnimation(WeydaSpring.interactive) {
                dragOffset = 0
            }
        }
    }
}

/// Une photo du plein écran : chargée en pleine définition (le zoom va jusqu'à ×4), puis confiée au zoom UIKit.
private struct DetailZoomablePhoto: View {
    private let url: String
    private let isCurrent: Bool
    private let onZoomChange: (Bool) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage? = nil
    @State private var failed: Bool = false

    init(url: String, isCurrent: Bool, onZoomChange: @escaping (Bool) -> Void) {
        self.url = url
        self.isCurrent = isCurrent
        self.onZoomChange = onZoomChange
    }

    var body: some View {
        ZStack {
            if let image {
                DetailZoomableImageView(image: image, isCurrent: isCurrent, onZoomChange: onZoomChange)
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(DetailGalleryColor.onScrim)
                    .opacity(0.6)
            } else {
                ProgressView()
                    .tint(DetailGalleryColor.onScrim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard image == nil else { return }
        guard let target = URL(string: url) else {
            failed = true
            return
        }
        // Taille demandée au plafond du pipeline : l'image n'est jamais réduite (elle fait 1200 px au plus).
        let request = ImageRequest(
            url: target,
            pixelWidth: ImageRequest.maxPixels,
            pixelHeight: ImageRequest.maxPixels,
            scale: displayScale
        )
        do {
            let loaded = try await ImagePipeline.shared.image(for: request)
            image = loaded
        } catch {
            if !ErrorMapper.isCancellation(error) {
                failed = true
            }
        }
    }
}

/// Le zoom natif d'iOS : `UIScrollView` (pincement, inertie, rebond) autour d'une `UIImageView`.
private struct DetailZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isCurrent: Bool
    let onZoomChange: (Bool) -> Void

    func makeUIView(context: Context) -> DetailZoomingScrollView {
        let view = DetailZoomingScrollView(frame: .zero)
        view.onZoomChange = onZoomChange
        view.display(image)
        return view
    }

    func updateUIView(_ view: DetailZoomingScrollView, context: Context) {
        view.onZoomChange = onZoomChange
        view.display(image)
        // Photo quittée : elle revient à sa taille (elle sera entière si on y revient).
        if !isCurrent {
            view.resetZoom()
        }
    }
}

/// Défilement + zoom d'une photo, centrée tant qu'elle est plus petite que l'écran.
private final class DetailZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    var onZoomChange: ((Bool) -> Void)?

    private let imageView = UIImageView()
    /// Taille pour laquelle la photo a été ajustée : une rotation ou un premier affichage la recalcule.
    private var fittedSize: CGSize = .zero
    private var reportedZoom: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = DetailGalleryMetrics.maxZoom
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func display(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        zoomScale = minimumZoomScale
        fittedSize = .zero
        setNeedsLayout()
    }

    func resetZoom() {
        guard zoomScale > minimumZoomScale else { return }
        setZoomScale(minimumZoomScale, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize {
            fittedSize = bounds.size
            zoomScale = minimumZoomScale
            fitImage()
        }
        centerImage()
    }

    /// Photo entière dans le cadre (« ajuster »), à l'échelle 1.
    private func fitImage() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
    }

    /// Marges qui gardent la photo au centre tant qu'elle ne remplit pas l'écran.
    private func centerImage() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets {
            contentInset = insets
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        let zoomed = zoomScale > minimumZoomScale + 0.01
        guard zoomed != reportedZoom else { return }
        reportedZoom = zoomed
        onZoomChange?(zoomed)
    }

    /// Double-toucher : ×2,5 autour du point touché, ou retour à la photo entière.
    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: animated)
            return
        }
        let point = recognizer.location(in: imageView)
        let scale = DetailGalleryMetrics.doubleTapZoom
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let target = CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        zoom(to: target, animated: animated)
    }
}
