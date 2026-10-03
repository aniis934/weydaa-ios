import SwiftUI

/// Racine : la coquille à onglets, recouverte au démarrage par l'animation de lancement.
struct RootView: View {
    @State private var tab: AppTab = LaunchOptions.initialTab ?? .home
    @State private var launchDone: Bool = LaunchOptions.skipLaunch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
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
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if LaunchOptions.screen == "showcase" {
            NavigationStack { DesignShowcaseView() }
        } else if LaunchOptions.screen == "data" {
            NavigationStack { DataShowcaseView() }
        } else {
            MainTabView(selection: $tab)
        }
        #else
        MainTabView(selection: $tab)
        #endif
    }
}

/// Barre d'onglets native (Liquid Glass d'elle-même sur iOS 26+) ; une pile de navigation par onglet.
struct MainTabView: View {
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    PlaceholderScreen(tab: tab)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.symbol)
                }
                .tag(tab)
            }
        }
    }
}
