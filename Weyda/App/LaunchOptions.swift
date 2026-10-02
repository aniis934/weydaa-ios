import Foundation

/// Arguments de lancement (`-Clé valeur`, lus via UserDefaults) — utilisés par les tests
/// d'interface et le tour de captures, sans effet sur l'app installée normalement.
///   -WeydaSkipLaunch YES      saute l'animation de lancement
///   -WeydaLaunchFrame 0.62    affiche une image figée de l'animation (capture)
///   -WeydaTab messages        onglet ouvert au démarrage
///   -WeydaScreen showcase     écran de démonstration du système de design (Debug)
///   -WeydaMockAPI YES         API simulée : réponses figées de MockFixtures (Debug)
nonisolated enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    static var skipLaunch: Bool { defaults.bool(forKey: "WeydaSkipLaunch") || isRunningUnitTests }

    static var launchFrame: Double? {
        defaults.string(forKey: "WeydaLaunchFrame").flatMap { Double($0) }
    }

    static var initialTab: AppTab? {
        defaults.string(forKey: "WeydaTab").flatMap(AppTab.init(rawValue:))
    }

    static var screen: String? { defaults.string(forKey: "WeydaScreen") }

    static var mockAPI: Bool { defaults.bool(forKey: "WeydaMockAPI") }

    /// Vrai pendant les tests unitaires (l'app sert d'hôte) : pas d'animation de lancement.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
