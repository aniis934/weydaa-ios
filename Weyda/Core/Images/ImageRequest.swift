import Foundation
import ImageIO
import UIKit

/// Une image à une taille d'affichage : URL + taille cible en PIXELS (points × échelle de l'écran, passée par
/// l'appelant : jamais `UIScreen.main` hors du fil principal). Les tailles sont arrondies au palier de 64 px
/// supérieur : des cellules voisines (172,5 pt, 173 pt…) partagent la même entrée du cache mémoire.
nonisolated struct ImageRequest: Hashable, Sendable {
    let url: URL
    /// 0 = dimension inconnue (aucune réduction sur cet axe).
    let pixelWidth: Int
    let pixelHeight: Int
    /// Échelle de l'image produite (taille en points = pixels / échelle).
    let scale: CGFloat

    static let step = 64
    /// Au-delà, aucune vue de l'app n'a besoin de plus (plein écran 3x d'un iPhone Pro Max ≈ 1 320 × 2 868 px).
    static let maxPixels = 4096

    init(url: URL, targetSize: CGSize, scale: CGFloat) {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        self.init(
            url: url,
            pixelWidth: ImageRequest.bucket(targetSize.width * safeScale),
            pixelHeight: ImageRequest.bucket(targetSize.height * safeScale),
            scale: safeScale
        )
    }

    init(url: URL, pixelWidth: Int, pixelHeight: Int, scale: CGFloat) {
        self.url = url
        self.pixelWidth = max(pixelWidth, 0)
        self.pixelHeight = max(pixelHeight, 0)
        self.scale = scale
    }

    /// La même taille pour une autre URL (image complète en repli d'une miniature absente).
    func with(url other: URL) -> ImageRequest {
        ImageRequest(url: other, pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale)
    }

    /// Clé du cache mémoire et des chargements en vol.
    var cacheKey: String { "\(url.absoluteString)#\(pixelWidth)x\(pixelHeight)@\(scale)" }

    /// Vue mesurée : tant que sa taille est nulle, la vue ne lance rien.
    var hasTargetSize: Bool { pixelWidth > 0 || pixelHeight > 0 }

    static func bucket(_ pixels: CGFloat) -> Int {
        guard pixels.isFinite, pixels > 0 else { return 0 }
        let needed = Int(min(pixels, CGFloat(maxPixels)).rounded(.up))
        return min((needed + step - 1) / step * step, maxPixels)
    }

    /// Côté long à décoder pour COUVRIR la cible (mode « remplir », qui suffit aussi à « ajuster ») sans jamais
    /// agrandir ; nil = taille d'origine.
    func maxPixelSize(imageWidth: Int, imageHeight: Int) -> Int? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let scaleX = pixelWidth > 0 ? Double(pixelWidth) / Double(imageWidth) : 0
        let scaleY = pixelHeight > 0 ? Double(pixelHeight) / Double(imageHeight) : 0
        let factor = max(scaleX, scaleY)
        guard factor > 0, factor < 1 else { return nil }
        return max(1, Int((Double(max(imageWidth, imageHeight)) * factor).rounded(.up)))
    }
}

/// Décodage ImageIO, à appeler hors du fil principal : réduction à la source (`CGImageSourceCreateThumbnailAtIndex`,
/// l'original n'est jamais décodé en entier), orientation EXIF appliquée, bitmap décodé tout de suite (rien ne
/// reste à décompresser au moment de l'affichage). WebP, HEIC, JPEG, PNG : natifs.
nonisolated enum ImageDecoder {
    /// nil = octets illisibles (pas une image, fichier tronqué).
    static func decode(_ data: Data, for request: ImageRequest) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Orientations 5 à 8 : l'image affichée est tournée d'un quart de tour.
        if let orientation = properties?[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize = request.maxPixelSize(imageWidth: width, imageHeight: height) {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: bitmap, scale: request.scale, orientation: .up)
    }
}
