import SwiftUI

/// L'appui se voit — `pressScale` d'Android : sous le doigt, l'élément se rentre légèrement (une carte de 250 pt
/// sans recul laisse douter d'avoir touché la bonne). « Réduire les animations » : il s'estompe un instant au lieu
/// de bouger. Cartes enveloppées dans un lien : `.buttonStyle(.weydaCard)`.
struct WeydaPressStyle: ButtonStyle {
    private let pressedScale: CGFloat

    init(pressedScale: CGFloat = 0.975) {
        self.pressedScale = pressedScale
    }

    func makeBody(configuration: Configuration) -> some View {
        WeydaPressLabel(configuration: configuration, pressedScale: pressedScale)
    }
}

extension ButtonStyle where Self == WeydaPressStyle {
    /// Carte d'annonce (ou toute carte) enveloppée dans un `NavigationLink` / `Button` : retrait de 2,5 %.
    static var weydaCard: WeydaPressStyle { WeydaPressStyle() }
}

private struct WeydaPressLabel: View {
    private let configuration: ButtonStyleConfiguration
    private let pressedScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(configuration: ButtonStyleConfiguration, pressedScale: CGFloat) {
        self.configuration = configuration
        self.pressedScale = pressedScale
    }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? pressedScale : 1)
            .opacity(pressed && reduceMotion ? 0.6 : 1)
            .weydaAnimation(WeydaSpring.interactive, value: pressed)
    }
}
