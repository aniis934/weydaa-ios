import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photo illisible ou trop lourde pour l'envoi (`ErrorMapper` la traduit : « Impossible de lire cette image. »,
/// « L'image dépasse la taille maximale de 5 Mo. »).
nonisolated enum ImagePreparationError: Error, Sendable, Equatable {
    /// Données vides, corrompues, ou qui ne sont pas une image (équivalent de `ImageReadException`).
    case unreadable
    /// Image démesurée (dimensions) ou JPEG impossible à faire passer sous la limite d'envoi.
    case tooLarge
}

/// Photo choisie (galerie, appareil) → octets JPEG prêts pour `POST /api/upload` — portage de
/// `data/upload/ImagePreparer.kt` (BitmapImagePreparer, Android).
///
/// Décodage ImageIO réduit à la source (le côté long ramené à `maxSide`, sans charger l'original en mémoire),
/// orientation EXIF appliquée aux pixels, transparence posée sur du blanc, puis JPEG à qualité dégressive
/// jusqu'à passer sous `maxBytes`. Aucune métadonnée n'est recopiée : ni EXIF, ni GPS (la position du domicile
/// d'un vendeur ne part jamais avec la photo). Le serveur reconvertit ensuite en WebP 1200 px
/// (src/lib/supabase.ts) : inutile d'envoyer plus de 1600 px.
nonisolated struct ImagePreparer: Sendable {
    var maxSide: Int = 1600
    /// Sous la limite serveur de 5 Mo, avec une marge pour l'enveloppe multipart.
    var maxBytes: Int = 4 * 1024 * 1024
    /// Qualités essayées dans l'ordre (85 = valeur Android).
    var qualities: [Double] = [0.85, 0.75, 0.65, 0.55, 0.45]
    /// Garde-fou contre une image démesurée (≈ 200 mégapixels ; un capteur 48 Mpx passe largement).
    var maxSourcePixels: Int = 200_000_000

    /// Version asynchrone : décodage et encodage hors du fil principal.
    @concurrent
    func prepare(_ data: Data) async throws -> Data {
        try prepareSynchronously(data)
    }

    /// Fichier local (appareil photo, export temporaire) ; illisible → `.unreadable`.
    @concurrent
    func prepare(fileAt url: URL) async throws -> Data {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw ImagePreparationError.unreadable
        }
        return try prepareSynchronously(data)
    }

    /// Cœur synchrone (tests, appelants déjà hors du fil principal).
    func prepareSynchronously(_ data: Data) throws -> Data {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else {
            throw ImagePreparationError.unreadable
        }
        guard width * height <= maxSourcePixels else { throw ImagePreparationError.tooLarge }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxSide, max(width, height)),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImagePreparationError.unreadable
        }
        let image = Self.flattenedIfTransparent(decoded) ?? decoded

        for quality in qualities {
            guard let jpeg = Self.jpegData(image, quality: quality) else { throw ImagePreparationError.unreadable }
            if jpeg.count <= maxBytes { return jpeg }
        }
        throw ImagePreparationError.tooLarge
    }

    /// JPEG sans métadonnées : seule l'image (pixels + profil de couleur) est écrite.
    private static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Le JPEG n'a pas de transparence : posée telle quelle, elle deviendrait noire (capture d'écran, PNG
    /// détouré). On la pose sur du blanc, comme le ferait un aperçu.
    private static func flattenedIfTransparent(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return nil
        default:
            break
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
