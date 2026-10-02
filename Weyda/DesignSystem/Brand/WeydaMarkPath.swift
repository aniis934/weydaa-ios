import SwiftUI

/// Le W de Weydaa, relevé au pixel sur le logo d'origine : trois colonnes parallèles inclinées à
/// 19°, deux cuvettes en U, extrémités et jointures arrondies, double extrusion vert foncé
/// décalée en diagonale. Le tracé est CONTINU : il s'écrit d'un seul geste.
///
/// SOURCE UNIQUE côté iOS. Le même tracé vit dans `WEYDA_W_PATH_DATA` (app Android) et dans
/// `scripts/render-icon.mjs` (icône de l'app, W de l'écran de démarrage) : toute retouche est à
/// reporter à l'identique des trois côtés, puis `node scripts/render-icon.mjs`.
///
/// Repère normalisé 100 × 100, W visuel centré sur (50, 50).
nonisolated enum WeydaMarkPath {
    static let data = "M29.51,20.5 L14.41,63.72 C7.04,84.75 29.95,84.75 39.11,63.72 "
        + "L57.97,20.5 L43.23,63.72 C36.09,84.75 64.32,84.75 71.69,63.72 L86.79,20.5"
    static let viewport: CGFloat = 100
    static let stroke: CGFloat = 14.4
    /// Décalages de l'extrusion, en unités du repère (relevés : 9/432 et 18/432 en diagonale).
    static let shadowNear: CGFloat = 3.09
    static let shadowFar: CGFloat = 6.17

    nonisolated enum Command: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case curve(control1: CGPoint, control2: CGPoint, end: CGPoint)
    }

    static let commands: [Command] = parse(data)

    /// Lit un tracé SVG limité aux commandes absolues M, L et C (celles du W).
    static func parse(_ data: String) -> [Command] {
        var spaced = ""
        for character in data {
            switch character {
            case "M", "L", "C": spaced += " \(character) "
            case ",": spaced += " "
            default: spaced.append(character)
            }
        }
        let tokens = spaced.split(separator: " ").map(String.init)
        var commands: [Command] = []
        var index = 0
        var current = "M"

        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let token = tokens[index]
            if token == "M" || token == "L" || token == "C" {
                current = token
                index += 1
                continue
            }
            switch current {
            case "M":
                commands.append(.move(point()))
                current = "L"
            case "L":
                commands.append(.line(point()))
            default:
                let control1 = point()
                let control2 = point()
                let end = point()
                commands.append(.curve(control1: control1, control2: control2, end: end))
            }
        }
        return commands
    }

    /// Le tracé mis à l'échelle et centré dans `rect` (carré inscrit).
    static func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / viewport
        let originX = rect.midX - side / 2
        let originY = rect.midY - side / 2
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * scale, y: originY + p.y * scale)
        }
        var path = Path()
        for command in commands {
            switch command {
            case .move(let p):
                path.move(to: map(p))
            case .line(let p):
                path.addLine(to: map(p))
            case .curve(let control1, let control2, let end):
                path.addCurve(to: map(end), control1: map(control1), control2: map(control2))
            }
        }
        return path
    }
}
