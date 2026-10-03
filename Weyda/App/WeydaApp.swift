import SwiftUI

@main
struct WeydaApp: App {
    /// Firebase, notifications système, jeton APNs et liens entrants (créé avant les `@StateObject` ci-dessous).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .onAppear {
                    // Interface prête : l'appui sur une notification reçu au lancement est rejoué, le fil visible est
                    // suivi pour les bannières.
                    appDelegate.attach(container: container, router: router)
                }
                .onOpenURL { url in
                    // Schéma `weydaa://` (et lien universel si SwiftUI le livre ici) : l'écran visé s'empile sur
                    // l'onglet courant ; une page du site sans écran natif repart au navigateur.
                    appDelegate.handleLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Lien universel (`https://weydaa.com/…`, `https://www.weydaa.com/…`, chemins de l'AASA du site).
                    guard let url = activity.webpageURL else { return }
                    appDelegate.handleLink(url)
                }
        }
        // Premier plan / arrière-plan : socket temps réel ouverte ou fermée, pastilles relues au retour.
        .onChange(of: scenePhase) { phase in
            container.scenePhaseChanged(phase)
        }
    }
}
