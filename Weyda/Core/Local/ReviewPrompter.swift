import Foundation
import os

/// Moment où l'utilisateur vient d'obtenir ce qu'il voulait — le seul où demander une note a du sens.
nonisolated enum PositiveMoment: String, CaseIterable, Sendable {
    /// Annonce publiée (une modification ne compte pas).
    case listingPublished
    /// Offre acceptée par le vendeur.
    case offerAccepted
    /// Avis envoyé sur un vendeur.
    case reviewSent
    /// Annonce marquée vendue.
    case listingSold
}

/// Quand demander une note sur l'App Store : au 2e moment positif au moins, une fois par version de l'app
/// (`CFBundleShortVersionString`), jamais en API simulée ni pendant les tests. iOS décide ensuite seul d'afficher ou non
/// la demande (3 fois par an au plus) ; on ne fait que choisir le bon moment. Tenu par `AppContainer`.
///
/// `@unchecked Sendable` : UserDefaults est sûr entre fils ; le verrou rend atomique le couple lecture + écriture.
nonisolated final class ReviewPrompter: @unchecked Sendable {
    static let minimumMoments = 2
    static let momentsKey = "weyda.review.moments"
    static let lastVersionKey = "weyda.review.lastVersion"

    private let defaults: UserDefaults
    private let version: String
    private let isEnabled: Bool
    private let lock = OSAllocatedUnfairLock()

    init(defaults: UserDefaults = .standard, version: String = ReviewPrompter.appVersion, isEnabled: Bool = ReviewPrompter.isAllowed) {
        self.defaults = defaults
        self.version = version
        self.isEnabled = isEnabled
    }

    /// Version affichée de l'app (« 1.0 ») ; « 0 » si illisible.
    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// Jamais en API simulée (captures) ni pendant les tests unitaires.
    static var isAllowed: Bool {
        !LaunchOptions.mockAPI && !LaunchOptions.isRunningUnitTests
    }

    /// Compte le moment ; vrai = demander la note MAINTENANT (2e moment au moins, pas encore demandé pour cette version).
    @discardableResult
    func record(_ moment: PositiveMoment) -> Bool {
        guard isEnabled else { return false }
        return lock.withLockUnchecked {
            let count = defaults.integer(forKey: Self.momentsKey) + 1
            defaults.set(count, forKey: Self.momentsKey)
            guard count >= Self.minimumMoments else { return false }
            guard defaults.string(forKey: Self.lastVersionKey) != version else { return false }
            defaults.set(version, forKey: Self.lastVersionKey)
            return true
        }
    }
}
