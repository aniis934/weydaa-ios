import Foundation

/// Arguments de lancement (`-Clé valeur`, lus via UserDefaults) — utilisés par les tests
/// d'interface et le tour de captures, sans effet sur l'app installée normalement.
///   -WeydaSkipLaunch YES      saute l'animation de lancement
///   -WeydaLaunchFrame 0.62    affiche une image figée de l'animation (capture)
///   -WeydaTab messages        onglet ouvert au démarrage
///   -WeydaRoute detail:x      écran ouvert au démarrage (formats : `LaunchRoute.parse`) ; feuille de connexion :
///                login · register · forgot · verify · reset:<jeton>   (`AuthEntry.launchEntry`)
///   -WeydaFreezeMotion YES    fige les animations décoratives sans fin (scintillement des squelettes) :
///                             captures reproductibles, et l'outil de test n'attend pas un « repos » qui ne vient pas
///   -WeydaScreen showcase     écran de démonstration du système de design (Debug) ;
///                components   la démonstration des composants seule
///   -WeydaScreen data         démonstration de la couche données : vrais repositories sur l'API simulée (Debug)
///   -WeydaMockAPI YES         API simulée : réponses figées de MockFixtures (Debug)
///   -WeydaLoggedIn YES        avec l'API simulée : session ouverte d'emblée (utilisateur fictif de référence,
///                  unverified  e-mail vérifié — ou à vérifier avec `unverified`) ; sans effet sur l'API réelle
nonisolated enum LaunchOptions {
    /// Session simulée demandée par `-WeydaLoggedIn` (captures des écrans de membre).
    nonisolated enum MockSession: Sendable {
        case verified
        case unverified
    }

    private static var defaults: UserDefaults { .standard }

    static var skipLaunch: Bool { defaults.bool(forKey: "WeydaSkipLaunch") || isRunningUnitTests }

    static var launchFrame: Double? {
        defaults.string(forKey: "WeydaLaunchFrame").flatMap { Double($0) }
    }

    static var initialTab: AppTab? {
        defaults.string(forKey: "WeydaTab").flatMap(AppTab.init(rawValue:))
    }

    /// Route de démarrage brute (`detail:mock-a3`, `listings:q=clio`…), analysée par `LaunchRoute.parse`.
    static var route: String? { defaults.string(forKey: "WeydaRoute") }

    static var freezeMotion: Bool { defaults.bool(forKey: "WeydaFreezeMotion") }

    static var screen: String? { defaults.string(forKey: "WeydaScreen") }

    static var mockAPI: Bool { defaults.bool(forKey: "WeydaMockAPI") }

    /// `-WeydaLoggedIn YES` → `.verified`, `-WeydaLoggedIn unverified` → `.unverified`, sinon nil. Lue par
    /// `AppContainer`, seulement en API simulée.
    static var mockSession: MockSession? {
        guard let raw = defaults.string(forKey: "WeydaLoggedIn")?.lowercased() else { return nil }
        switch raw {
        case "yes", "true", "1", "verified": return .verified
        case "unverified": return .unverified
        default: return nil
        }
    }

    /// Vrai pendant les tests unitaires (l'app sert d'hôte) : pas d'animation de lancement.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
