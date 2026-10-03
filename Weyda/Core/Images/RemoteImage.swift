import SwiftUI
import UIKit

/// Image distante (photo d'annonce, avatar) — l'équivalent de `ListingImage` / `AsyncImage` de Coil (Android).
///
/// Occupe exactement la place que lui donne son parent : l'appelant fixe un cadre ou un rapport
/// largeur / hauteur, l'arrivée de l'image ne déplace donc rien. Fond `imagePlaceholder` pendant le chargement,
/// fondu court à l'arrivée (aucun avec « Réduire les animations ») ; une image déjà en mémoire s'affiche tout de
/// suite, sans fondu. Réduite à la taille affichée (pixels = points × échelle de l'écran). Décorative pour
/// VoiceOver : la carte qui la porte annonce déjà le titre.
struct RemoteImage: View {
    private let url: URL?
    private let fallbackURL: URL?
    private let contentMode: ContentMode
    private let pipeline: ImagePipeline

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedImage? = nil

    /// `fallbackURL` : image chargée si `url` échoue (miniature absente d'une ancienne annonce → image complète).
    init(url: URL?, fallbackURL: URL? = nil, contentMode: ContentMode = .fill, pipeline: ImagePipeline = .shared) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.contentMode = contentMode
        self.pipeline = pipeline
    }

    /// Variante pour les URL en texte des modèles (`listing.coverThumbnail`, `seller.avatarUrl`…).
    init(urlString: String?, fallbackURLString: String? = nil, contentMode: ContentMode = .fill, pipeline: ImagePipeline = .shared) {
        self.init(
            url: urlString.flatMap { URL(string: $0) },
            fallbackURL: fallbackURLString.flatMap { URL(string: $0) },
            contentMode: contentMode,
            pipeline: pipeline
        )
    }

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size)
        }
        .accessibilityHidden(true)
    }

    private func content(size: CGSize) -> some View {
        let request: ImageRequest? = url.map { ImageRequest(url: $0, targetSize: size, scale: displayScale) }
        let image = displayedImage(for: request)
        // En mode « ajuster », les bandes autour de l'image restent transparentes une fois l'image arrivée.
        let placeholderOpacity: Double = image == nil || contentMode == .fill ? 1 : 0
        return ZStack {
            WeydaPalette.imagePlaceholder
                .opacity(placeholderOpacity)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: loaded?.url)
        .task(id: request) {
            await load(request)
        }
    }

    /// Image exacte en mémoire, sinon la dernière reçue pour cette URL (pendant un changement de taille).
    private func displayedImage(for request: ImageRequest?) -> UIImage? {
        guard let request else { return nil }
        if let cached = pipeline.cachedImage(for: request) { return cached }
        if let loaded, loaded.url == request.url { return loaded.image }
        return nil
    }

    private func load(_ request: ImageRequest?) async {
        guard let request, request.hasTargetSize, pipeline.cachedImage(for: request) == nil else { return }
        do {
            let image = try await pipeline.image(for: request)
            if !Task.isCancelled { loaded = LoadedImage(url: request.url, image: image) }
        } catch {
            // Annulée (cellule recyclée) : rien. Sinon, image de repli si elle diffère.
            guard !Task.isCancelled, let fallbackURL, fallbackURL != request.url else { return }
            guard let image = try? await pipeline.image(for: request.with(url: fallbackURL)), !Task.isCancelled else { return }
            loaded = LoadedImage(url: request.url, image: image)
        }
    }
}

/// Dernière image reçue par une `RemoteImage`, rattachée à l'URL demandée (pas à celle du repli).
private struct LoadedImage {
    let url: URL
    let image: UIImage
}
