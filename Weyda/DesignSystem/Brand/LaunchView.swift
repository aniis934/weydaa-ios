import SwiftUI

/// Écran de lancement — la seule animation « spectacle » de l'app (miroir de WeydaLaunch, Android).
///
/// Il PROLONGE l'écran système au lieu de le remplacer : même fond (LaunchBackground = Emerald700),
/// même W fantôme à la même taille (SplashMark, 160 pt, centré). Le raccord est invisible, et
/// aucune attente n'est ajoutée au démarrage.
///
/// Déroulé (1 000 ms, puis 260 ms de sortie ; départ différé de 120 ms, le temps que la première
/// image — la plus coûteuse — soit passée : sinon l'horloge saute et le W apparaît d'un coup) :
///   0 → 580 ms     le W s'écrit d'un seul trait par-dessus son fantôme
///   0 → 420 ms     une lueur emerald monte derrière lui (le fond part plat, comme l'écran système)
///   500 → 750 ms   un reflet balaie le tracé en diagonale
///   520 → 920 ms   les six lettres de « Weydaa » montent l'une après l'autre
///   750 → 1000 ms  la signature apparaît en bas
///   sortie         l'ensemble grandit de 4 % et se fond dans l'accueil
///
/// « Réduire les animations » actif → l'écran est sauté intégralement (RootView ne le monte pas).
struct LaunchView: View {
    /// Image figée de la chorégraphie (captures automatiques) ; nil = animation réelle.
    private let frozenClock: Double?
    private let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date? = nil

    // Initialiseur explicite : un `@State private` rend privé l'initialiseur synthétisé.
    init(frozenClock: Double? = nil, onFinished: @escaping () -> Void) {
        self.frozenClock = frozenClock
        self.onFinished = onFinished
    }

    private static let total: Double = 1.0
    private static let exit: Double = 0.26
    private static let startDelay: Duration = .milliseconds(120)

    var body: some View {
        TimelineView(.animation(paused: frozenClock != nil)) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) } ?? 0
            let clock = frozenClock ?? min(elapsed / Self.total, 1)
            let exit = frozenClock == nil ? weydaPhase(elapsed, from: Self.total, to: Self.total + Self.exit) : 0
            LaunchFrame(clock: clock, exit: exit)
        }
        .task { await run() }
        .accessibilityHidden(true)
    }

    private func run() async {
        guard frozenClock == nil else { return }
        guard !reduceMotion else {
            onFinished()
            return
        }
        try? await Task.sleep(for: Self.startDelay)
        start = Date()
        try? await Task.sleep(for: .milliseconds(Int((Self.total + Self.exit) * 1000)))
        onFinished()
    }
}

/// Une image de la chorégraphie pour une horloge donnée (0 → 1) et une sortie (0 → 1).
private struct LaunchFrame: View {
    let clock: Double
    let exit: Double

    private var draw: Double { WeydaCurve.emphasized(weydaPhase(clock, from: 0, to: 0.58)) }
    private var glow: Double { WeydaCurve.standardDecelerate(weydaPhase(clock, from: 0, to: 0.42)) }
    private var sheen: Double { weydaPhase(clock, from: 0.50, to: 0.75) }
    private var word: Double { weydaPhase(clock, from: 0.52, to: 0.92) }
    private var tagline: Double { WeydaCurve.emphasizedDecelerate(weydaPhase(clock, from: 0.75, to: 1)) }
    private var exitEased: Double { WeydaCurve.emphasizedAccelerate(exit) }

    var body: some View {
        ZStack {
            WeydaBrandColor.launchBackground
            // Lueur : le fond démarre PLAT (identique à l'écran système) puis prend du relief.
            RadialGradient(
                colors: [WeydaBrandColor.launchGlow, WeydaBrandColor.launchGlow.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: 340
            )
            .opacity(glow)

            // Le W est centré SEUL, exactement là où l'écran système posait le sien.
            mark

            // Le mot est décalé sous le W : dans la même colonne, il pousserait le W vers le haut
            // et le raccord avec l'écran système deviendrait visible.
            WeydaWordmark(reveal: word)
                .offset(y: WeydaSize.launchMark / 2 + 36)

            VStack {
                Spacer()
                Text(L10n.tagline)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaBrandColor.launchTagline)
                    .multilineTextAlignment(.center)
                    .opacity(tagline)
                    .offset(y: (1 - tagline) * 16)
                    .padding(.horizontal, WeydaSpace.screen)
                    .padding(.bottom, 72)
            }
        }
        .ignoresSafeArea()
        .scaleEffect(1 + exitEased * 0.04)
        .opacity(1 - exitEased)
    }

    private var mark: some View {
        ZStack {
            // Fantôme : ce que l'écran système affichait déjà, il sert de guide au tracé.
            WeydaMark(fill: WeydaBrandColor.mark.opacity(WeydaBrandColor.ghostMarkOpacity))
                .frame(width: WeydaSize.launchMark, height: WeydaSize.launchMark)
            WeydaMarkExtruded(
                size: WeydaSize.launchMark,
                progress: draw,
                near: WeydaBrandColor.extrusionNear,
                far: WeydaBrandColor.launchExtrusionFar
            )
            if sheen > 0 && sheen < 1 {
                // Reflet : le W redessiné avec un dégradé étroit qui glisse en diagonale.
                let x = -0.4 + sheen * 1.6
                WeydaMark(fill: LinearGradient(
                    stops: [
                        .init(color: WeydaBrandColor.launchSheen.opacity(0), location: 0),
                        .init(color: WeydaBrandColor.launchSheen, location: 0.5),
                        .init(color: WeydaBrandColor.launchSheen.opacity(0), location: 1),
                    ],
                    startPoint: UnitPoint(x: x, y: 0),
                    endPoint: UnitPoint(x: x + 0.34, y: 1)
                ))
                .frame(width: WeydaSize.launchMark, height: WeydaSize.launchMark)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
