import SwiftUI

/// Racine : la coquille à onglets, recouverte au démarrage par l'animation de lancement. Les pages légales
/// (`AppRoute.webPage`) et la connexion (`AppRouter.authFlow` → `AuthFlowView`) s'ouvrent ici en feuille, au-dessus
/// de tout.
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var launchDone: Bool = LaunchOptions.skipLaunch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Initialiseur explicite : les propriétés `private` rendraient privé l'initialiseur synthétisé.
    init() {}

    var body: some View {
        ZStack {
            content
                // Connexion, inscription, mot de passe, code e-mail : une feuille avec sa propre pile, fermée
                // d'elle-même une fois connecté (ou glissée vers le bas : `authFlow` revient alors à nil).
                .sheet(item: $router.authFlow) { entry in
                    AuthFlowView(entry: entry)
                }
            if let frame = LaunchOptions.launchFrame {
                LaunchView(frozenClock: frame, onFinished: {})
            } else if !launchDone && !reduceMotion {
                // La surcouche est opaque : elle reçoit les appuis, rien ne s'active dessous à l'aveugle.
                LaunchView { launchDone = true }
                    .zIndex(1)
            }
        }
        // Chiffres latins partout, y compris en arabe (comme LatinDigits sur Android).
        .environment(\.locale, WeydaLocale.formatting)
        .sheet(item: $router.presentedWebPage) { page in
            WebPageView(page: page)
                .onDisappear {
                    // « Fermer » de Safari peut fermer la feuille côté UIKit : l'état est remis à zéro dans tous
                    // les cas, sinon la même page ne se rouvrirait plus.
                    if router.presentedWebPage == page {
                        router.presentedWebPage = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if LaunchOptions.screen == "showcase" {
            NavigationStack { DesignShowcaseView() }
        } else if LaunchOptions.screen == "components" {
            NavigationStack { DesignShowcaseView(componentsOnly: true) }
        } else if LaunchOptions.screen == "data" {
            NavigationStack { DataShowcaseView() }
        } else {
            MainTabView()
        }
        #else
        MainTabView()
        #endif
    }
}

/// Barre d'onglets native (Liquid Glass d'elle-même sur iOS 26+) ; une pile de navigation par onglet, tenue par
/// le routeur. Toucher l'onglet déjà actif remonte sa pile à la racine (`AppRouter.tabSelection`).
struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter

    init() {}

    var body: some View {
        TabView(selection: router.tabSelection) {
            ForEach(AppTab.allCases) { tab in
                TabStack(tab: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .tag(tab)
            }
        }
    }
}

/// La pile d'un onglet : sa racine, puis les écrans poussés (`AppRoute`).
private struct TabStack: View {
    @EnvironmentObject private var router: AppRouter
    private let tab: AppTab

    init(tab: AppTab) {
        self.tab = tab
    }

    var body: some View {
        NavigationStack(path: router.path(for: tab)) {
            TabRoot(tab: tab)
                .appRouteDestinations()
        }
    }
}

/// Écran racine de chaque onglet. Messages reste provisoire (phase 5) ; Déposer : l'assistant de dépôt (phase 4,
/// invitation à se connecter pour un visiteur) ; Profil : visiteur (connexion) ou membre, selon la session
/// (`ProfileView`, phase 3).
private struct TabRoot: View {
    private let tab: AppTab

    init(tab: AppTab) {
        self.tab = tab
    }

    var body: some View {
        switch tab {
        case .home:
            HomeView()
        case .listings:
            ListingsView()
        case .post:
            PostListingView()
        case .messages:
            PlaceholderScreen(tab: tab)
        case .account:
            ProfileView()
        }
    }
}
