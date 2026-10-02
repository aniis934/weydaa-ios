import SwiftUI

/// Trace le W. `progress` = part du tracé déjà écrite (0 = rien, 1 = W complet) ; `tail` fait
/// courir un segment au lieu de partir du début (indicateur d'attente).
struct WeydaMark<Fill: ShapeStyle>: View {
    let fill: Fill
    var progress: CGFloat = 1
    var tail: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let from = min(max(tail, 0), 1)
            let to = max(min(max(progress, 0), 1), from)
            WeydaMarkPath.path(in: CGRect(origin: .zero, size: proxy.size))
                .trimmedPath(from: from, to: to)
                .stroke(fill, style: StrokeStyle(
                    lineWidth: side * WeydaMarkPath.stroke / WeydaMarkPath.viewport,
                    lineCap: .round,
                    lineJoin: .round
                ))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Le W EXTRUDÉ : deux copies vert foncé décalées en diagonale, puis le tracé par-dessus. C'est
/// ce relief qui fait reconnaître le logo. Les trois couches partagent le même `progress` : le
/// relief s'écrit avec le tracé. Sens forcé de gauche à droite : l'ombre d'un logo ne se
/// retourne pas en arabe.
struct WeydaMarkExtruded: View {
    let size: CGFloat
    var progress: CGFloat = 1
    var front: Color = WeydaBrandColor.mark
    var near: Color = WeydaBrandColor.extrusionNear
    var far: Color = WeydaBrandColor.extrusionFar

    var body: some View {
        let unit = size / WeydaMarkPath.viewport
        ZStack(alignment: .topLeading) {
            WeydaMark(fill: far, progress: progress)
                .frame(width: size, height: size)
                .offset(x: unit * WeydaMarkPath.shadowFar, y: unit * WeydaMarkPath.shadowFar)
            WeydaMark(fill: near, progress: progress)
                .frame(width: size, height: size)
                .offset(x: unit * WeydaMarkPath.shadowNear, y: unit * WeydaMarkPath.shadowNear)
            WeydaMark(fill: front, progress: progress)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// L'icône de l'app, en vue : le W extrudé sur le dégradé emerald, dans la courbe de l'icône
/// iOS. C'est le lien visuel entre l'écran d'accueil du téléphone et l'intérieur de l'app
/// (connexion, garde visiteur). Mêmes proportions que `scripts/render-icon.mjs` (0,56).
struct WeydaTile: View {
    let size: CGFloat
    var progress: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: size * WeydaRadius.iconRatio, style: .continuous)
            .fill(LinearGradient(
                colors: WeydaPalette.iconGradient,
                startPoint: UnitPoint(x: 0, y: 0),
                endPoint: UnitPoint(x: 1, y: 1)
            ))
            .frame(width: size, height: size)
            .overlay {
                WeydaMarkExtruded(size: size * 0.56, progress: progress)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }
}

/// Indicateur d'attente maison : le W s'écrit puis se résorbe, en boucle. Il remplace la roue
/// système partout où l'app fait patienter. « Réduire les animations » → W fixe, estompé.
struct WeydaLoader: View {
    private let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 1.5

    init(color: Color = WeydaColor.primary) {
        self.color = color
    }

    var body: some View {
        Group {
            if reduceMotion {
                WeydaMark(fill: color.opacity(0.4))
            } else {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let phase = elapsed.truncatingRemainder(dividingBy: Self.period) / Self.period
                    // La tête part devant, la queue la rattrape : le W s'écrit, puis se résorbe.
                    WeydaMark(
                        fill: color,
                        progress: Self.easeInOut(min(phase * 1.7, 1)),
                        tail: Self.easeInOut(min(max((phase - 0.41) * 1.7, 0), 1))
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.loading)
    }

    nonisolated static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - (-2 * x + 2) * (-2 * x + 2) / 2
    }
}

/// Le mot « Weydaa ». Chaque lettre entre séparément (`reveal` 0 → 1) : décalage, montée,
/// opacité. Sens forcé de gauche à droite : un nom propre en alphabet latin ne se retourne pas
/// avec l'interface (sinon « aadyeW » en arabe). VoiceOver lit le nom de l'app, pas six lettres.
struct WeydaWordmark: View {
    var color: Color = WeydaBrandColor.mark
    var style: WeydaTextStyle = .mark
    var reveal: CGFloat = 1

    private static let letters: [String] = ["W", "e", "y", "d", "a", "a"]

    var body: some View {
        HStack(spacing: style.tracking) {
            ForEach(Array(Self.letters.enumerated()), id: \.offset) { index, letter in
                let local = min(max((reveal - CGFloat(index) * 0.10) / 0.45, 0), 1)
                Text(verbatim: letter)
                    .font(style.font)
                    .foregroundStyle(color)
                    .opacity(local)
                    .offset(y: (1 - local) * 10)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.appName)
    }
}
