#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import os

/// Photos des annonces FICTIVES de l'API simulée, dessinées à la demande (Core Graphics seul : utilisable
/// hors du fil principal) : un fond dégradé et la silhouette de l'objet. Aucune vraie photo dans le dépôt
/// public, et les captures restent identiques d'un tour à l'autre (couleurs tirées du NOM, pas du hasard).
///
/// Nom attendu : `<objet>-<n>.webp` (1200 × 900) ou `<objet>-<n>_thumb.webp` (miniature 400 × 300), par
/// exemple `car-1.webp`. Objets : car, phone, laptop, house, sofa, tv, fridge, bike, watch, dress, pet,
/// tools, job, travel ; tout autre nom → un carton.
nonisolated enum MockPhotos {
    private static let cache = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    static func jpeg(named fileName: String) -> Data {
        if let cached = cache.withLock({ $0[fileName] }) { return cached }
        let data = render(fileName)
        cache.withLock { $0[fileName] = data }
        return data
    }

    private static func render(_ fileName: String) -> Data {
        let base = (fileName as NSString).deletingPathExtension
        let isThumb = base.hasSuffix("_thumb")
        let key = isThumb ? String(base.dropLast("_thumb".count)) : base
        let kind = key.split(separator: "-").first.map(String.init) ?? key
        let size = isThumb ? CGSize(width: 400, height: 300) : CGSize(width: 1200, height: 900)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return Data() }

        let hue = Double(stableHash(key) % 360) / 360
        drawBackground(in: context, size: size, hue: hue, space: space)
        drawSilhouette(kind, in: context, size: size, hue: hue)

        guard let image = context.makeImage() else { return Data() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return output as Data
    }

    // MARK: Dessin

    private static func drawBackground(in context: CGContext, size: CGSize, hue: Double, space: CGColorSpace) {
        let top = color(hue: hue, saturation: 0.18, brightness: 0.97)
        let bottom = color(hue: hue, saturation: 0.32, brightness: 0.82)
        if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                options: []
            )
        }
        // Ombre portée au sol, sous l'objet.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10))
        context.fillEllipse(in: CGRect(x: size.width * 0.2, y: size.height * 0.1, width: size.width * 0.6, height: size.height * 0.08))
    }

    /// Les silhouettes sont décrites dans un carré unité (y vers le haut), centré sur l'image.
    private static func drawSilhouette(_ kind: String, in context: CGContext, size: CGSize, hue: Double) {
        let side = min(size.width, size.height) * 0.72
        let origin = CGPoint(x: (size.width - side) / 2, y: size.height * 0.14)
        let pen = Pen(context: context, origin: origin, side: side)
        let body = color(hue: hue, saturation: 0.55, brightness: 0.45)
        let light = color(hue: hue, saturation: 0.08, brightness: 0.99)
        let dark = color(hue: hue, saturation: 0.35, brightness: 0.22)

        switch kind {
        case "car":
            pen.polygon([(0.22, 0.46), (0.33, 0.66), (0.68, 0.66), (0.80, 0.46)], body)
            pen.roundedRect(0.04, 0.22, 0.92, 0.26, 0.08, body)
            pen.polygon([(0.28, 0.48), (0.36, 0.62), (0.48, 0.62), (0.48, 0.48)], light)
            pen.polygon([(0.52, 0.48), (0.52, 0.62), (0.65, 0.62), (0.74, 0.48)], light)
            for x in [0.26, 0.74] {
                pen.circle(x, 0.22, 0.10, dark)
                pen.circle(x, 0.22, 0.045, light)
            }
        case "phone":
            pen.roundedRect(0.31, 0.02, 0.38, 0.92, 0.07, dark)
            pen.roundedRect(0.335, 0.05, 0.33, 0.86, 0.05, light)
            pen.roundedRect(0.44, 0.85, 0.12, 0.035, 0.017, dark)
        case "laptop":
            pen.roundedRect(0.16, 0.30, 0.68, 0.48, 0.03, dark)
            pen.roundedRect(0.19, 0.33, 0.62, 0.42, 0.015, light)
            pen.polygon([(0.04, 0.30), (0.96, 0.30), (0.90, 0.22), (0.10, 0.22)], body)
        case "house":
            pen.polygon([(0.10, 0.56), (0.50, 0.90), (0.90, 0.56)], dark)
            pen.roundedRect(0.18, 0.08, 0.64, 0.50, 0.01, light)
            pen.roundedRect(0.44, 0.08, 0.12, 0.24, 0.01, body)
            pen.roundedRect(0.25, 0.36, 0.12, 0.12, 0.01, body)
            pen.roundedRect(0.63, 0.36, 0.12, 0.12, 0.01, body)
        case "sofa":
            pen.roundedRect(0.14, 0.36, 0.72, 0.30, 0.06, body)
            pen.roundedRect(0.08, 0.18, 0.84, 0.22, 0.05, body)
            pen.roundedRect(0.03, 0.18, 0.13, 0.32, 0.05, dark)
            pen.roundedRect(0.84, 0.18, 0.13, 0.32, 0.05, dark)
            pen.roundedRect(0.12, 0.10, 0.04, 0.09, 0.015, dark)
            pen.roundedRect(0.84, 0.10, 0.04, 0.09, 0.015, dark)
        case "tv":
            pen.roundedRect(0.06, 0.30, 0.88, 0.54, 0.03, dark)
            pen.roundedRect(0.09, 0.33, 0.82, 0.48, 0.015, light)
            pen.polygon([(0.40, 0.30), (0.60, 0.30), (0.66, 0.16), (0.34, 0.16)], body)
        case "fridge":
            pen.roundedRect(0.28, 0.02, 0.44, 0.92, 0.05, light)
            pen.roundedRect(0.28, 0.60, 0.44, 0.012, 0.004, dark)
            pen.roundedRect(0.33, 0.66, 0.025, 0.14, 0.012, dark)
            pen.roundedRect(0.33, 0.36, 0.025, 0.18, 0.012, dark)
        case "bike":
            for x in [0.24, 0.76] {
                pen.circle(x, 0.28, 0.17, dark)
                pen.circle(x, 0.28, 0.13, light)
            }
            pen.polygon([(0.24, 0.28), (0.45, 0.58), (0.70, 0.58), (0.76, 0.28), (0.72, 0.28), (0.66, 0.54), (0.47, 0.54), (0.28, 0.28)], body)
        case "watch":
            pen.roundedRect(0.38, 0.0, 0.24, 0.98, 0.06, dark)
            pen.circle(0.5, 0.49, 0.22, body)
            pen.circle(0.5, 0.49, 0.18, light)
        case "dress":
            pen.polygon([(0.38, 0.92), (0.62, 0.92), (0.60, 0.62), (0.80, 0.06), (0.20, 0.06), (0.40, 0.62)], body)
        case "pet":
            pen.circle(0.50, 0.32, 0.20, body)
            for (x, y) in [(0.26, 0.58), (0.42, 0.72), (0.58, 0.72), (0.74, 0.58)] {
                pen.circle(x, y, 0.09, body)
            }
        case "tools", "job", "travel":
            pen.roundedRect(0.38, 0.62, 0.24, 0.16, 0.04, dark)
            pen.roundedRect(0.42, 0.62, 0.16, 0.10, 0.03, light)
            pen.roundedRect(0.10, 0.10, 0.80, 0.56, 0.06, kind == "job" ? dark : body)
            pen.roundedRect(0.10, 0.34, 0.80, 0.03, 0.01, light)
        default:
            pen.polygon([(0.20, 0.62), (0.50, 0.78), (0.80, 0.62), (0.50, 0.46)], light)
            pen.polygon([(0.20, 0.62), (0.50, 0.46), (0.50, 0.08), (0.20, 0.24)], body)
            pen.polygon([(0.50, 0.46), (0.80, 0.62), (0.80, 0.24), (0.50, 0.08)], dark)
        }
    }

    // MARK: Outils

    /// Dessine dans le carré unité posé sur l'image.
    nonisolated private struct Pen {
        let context: CGContext
        let origin: CGPoint
        let side: CGFloat

        private func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(x) * side, y: origin.y + CGFloat(y) * side)
        }

        func polygon(_ points: [(Double, Double)], _ fill: CGColor) {
            guard let first = points.first else { return }
            context.beginPath()
            context.move(to: point(first.0, first.1))
            for next in points.dropFirst() {
                context.addLine(to: point(next.0, next.1))
            }
            context.closePath()
            context.setFillColor(fill)
            context.fillPath()
        }

        func roundedRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double, _ fill: CGColor) {
            let rect = CGRect(origin: point(x, y), size: CGSize(width: CGFloat(width) * side, height: CGFloat(height) * side))
            // CGPath(roundedRect:) exige un rayon ≤ la moitié du côté le plus court.
            let corner = min(CGFloat(radius) * side, rect.width / 2, rect.height / 2)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.setFillColor(fill)
            context.fillPath()
        }

        func circle(_ x: Double, _ y: Double, _ radius: Double, _ fill: CGColor) {
            let r = CGFloat(radius) * side
            let center = point(x, y)
            context.setFillColor(fill)
            context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
    }

    /// Hachage FNV-1a : stable d'un lancement à l'autre (contrairement à `hashValue`).
    private static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    private static func color(hue: Double, saturation: Double, brightness: Double) -> CGColor {
        let h = (hue - floor(hue)) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let rgb: (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return CGColor(srgbRed: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m, alpha: 1)
    }
}
#endif
