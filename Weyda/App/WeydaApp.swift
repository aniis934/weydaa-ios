import SwiftUI

@main
struct WeydaApp: App {
    /// Conteneur de l'app, Firebase, notifications système, jeton APNs, raccourcis et liens entrants (créé avant les
    /// `@StateObject` ci-dessous). Le conteneur lui appartient : une action de notification peut lancer l'app sans scène.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.container)
                .environmentObject(appDelegate.container.sessionManager)
                .environmentObject(appDelegate.container.connectivity)
                .environmentObject(router)
                .onAppear {
                    // Interface prête : l'écran demandé au lancement (notification, raccourci, lien) s'ouvre.
                    appDelegate.attach(router: router)
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
            appDelegate.container.scenePhaseChanged(phase)
        }
    }
}
