import UIKit

/// Retours haptiques discrets, propres à iOS : un générateur UIKit créé à la demande, sur le fil principal (les
/// générateurs sont des objets UIKit, isolés au MainActor). Rien ne vibre si l'appareil n'a pas de moteur haptique, si
/// l'utilisateur a coupé les vibrations du système, ou dans le simulateur : c'est iOS qui décide, rien à régler ici.
/// Branchés là où une action ABOUTIT (message envoyé, offre envoyée ou acceptée), pas à l'appui : un échec ne doit pas
/// « vibrer comme une réussite ». Exception : le favori, optimiste — le cœur se remplit à l'appui, le choc l'accompagne.
nonisolated enum Haptics {
    /// Réussite marquée : offre envoyée, offre acceptée.
    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Échec d'une action (bannière d'erreur) : le motif « erreur » du système.
    @MainActor
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Avertissement (action à confirmer, limite atteinte).
    @MainActor
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Changement de sélection (valeur choisie dans une série).
    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Petit choc : message envoyé, favori ajouté.
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
