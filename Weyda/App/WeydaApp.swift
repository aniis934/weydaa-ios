import SwiftUI

@main
struct WeydaApp: App {
    @StateObject private var container = AppContainer()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.sessionManager)
                .environmentObject(container.connectivity)
                .environmentObject(router)
                .onOpenURL { url in
                    // Lien universel ou schéma `weydaa://` (DeepLinks) : l'écran visé s'empile sur l'onglet
                    // courant. Un lien du site sans écran natif est ignoré ici (liens universels : phase 5).
                    guard let target = DeepLinks.resolve(url) else { return }
                    router.open(target)
                }
        }
        // Premier plan / arrière-plan : socket temps réel ouverte ou fermée, pastilles relues au retour.
        .onChange(of: scenePhase) { phase in
            container.scenePhaseChanged(phase)
        }
    }
}
