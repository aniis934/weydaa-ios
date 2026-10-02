import SwiftUI

@main
struct WeydaApp: App {
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
        }
        // Premier plan / arrière-plan : socket temps réel ouverte ou fermée, pastilles relues au retour.
        .onChange(of: scenePhase) { phase in
            container.scenePhaseChanged(phase)
        }
    }
}
