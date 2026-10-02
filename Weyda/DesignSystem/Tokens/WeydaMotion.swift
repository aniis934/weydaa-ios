import SwiftUI

/// Durées en secondes — miroir de `WeydaDuration` (Android, en ms). Au-delà de `long`, seul
/// l'écran de lancement a le droit d'aller.
nonisolated enum WeydaDuration {
    static let instant: Double = 0.09
    static let short: Double = 0.16
    static let medium: Double = 0.24
    static let long: Double = 0.36
    static let slow: Double = 0.52
    /// Tracé du W : la seule animation de l'app qui dépasse 500 ms.
    static let brand: Double = 0.9
}

/// Courbe de Bézier cubique (points de contrôle Material 3 « expressive », les mêmes qu'Android).
/// Sert deux fois : `animation(duration:)` pour SwiftUI, et l'appel direct `curve(t)` pour les
/// horloges dessinées à la main (écran de lancement, TimelineView).
nonisolated struct WeydaCurve: Sendable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    /// Mouvements que l'œil suit (transition d'écran, arrivée d'un panneau).
    static let emphasized = WeydaCurve(x1: 0.2, y1: 0, x2: 0, y2: 1)
    static let emphasizedDecelerate = WeydaCurve(x1: 0.05, y1: 0.7, x2: 0.1, y2: 1)
    static let emphasizedAccelerate = WeydaCurve(x1: 0.3, y1: 0, x2: 0.8, y2: 0.15)
    static let standard = WeydaCurve(x1: 0.2, y1: 0, x2: 0, y2: 1)
    static let standardDecelerate = WeydaCurve(x1: 0, y1: 0, x2: 0, y2: 1)
    static let standardAccelerate = WeydaCurve(x1: 0.3, y1: 0, x2: 1, y2: 1)

    func animation(duration: Double) -> Animation {
        .timingCurve(x1, y1, x2, y2, duration: duration)
    }

    /// Valeur de la courbe pour une progression `x` ∈ [0, 1] (résolution de Newton puis dichotomie).
    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-6 { return sampleY(t) }
            let slope = sampleDerivativeX(t)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0..<32 {
            let value = sampleX(t)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sampleY(t)
    }

    private func sampleX(_ t: Double) -> Double { bezier(t, x1, x2) }
    private func sampleY(_ t: Double) -> Double { bezier(t, y1, y2) }
    private func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
    private func sampleDerivativeX(_ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
    }
}

nonisolated enum WeydaSpring {
    /// Micro-interactions (appui, cœur favori) — ressort « medium bouncy » d'Android.
    static let interactive: Animation = .spring(response: 0.35, dampingFraction: 0.6)
}

/// Ramène une horloge globale [0, 1] sur une sous-phase [start, end], bornée.
nonisolated func weydaPhase(_ t: Double, from start: Double, to end: Double) -> Double {
    min(max((t - start) / (end - start), 0), 1)
}

extension View {
    /// `animation(_:value:)` qui s'efface quand « Réduire les animations » est actif — l'équivalent
    /// de `weydaTween` (Android). Toute animation de l'app passe par ici ou lit
    /// `accessibilityReduceMotion` elle-même.
    func weydaAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(WeydaAnimationModifier(animation: animation, value: value))
    }
}

private struct WeydaAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
