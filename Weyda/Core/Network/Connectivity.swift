import Foundation
import Network

/// En ligne / hors ligne, pour le bandeau « hors ligne » et la relance des écrans en erreur — portage de
/// `ConnectivityObserver.kt` et d'`AppContainer.online` (Android).
///
/// UNE seule instance pour toute l'app (`AppContainer.connectivity`) : un seul `NWPathMonitor`, sur une file
/// privée, qui suit le chemin réseau que l'app utilise réellement (passer du Wi-Fi aux données mobiles ne
/// fait pas clignoter le bandeau). Démarre « en ligne » (comme Android) : pas de bandeau à tort avant la
/// première mesure. Le moniteur vit aussi longtemps que l'app (jamais arrêté).
///
/// Tour de captures (`-WeydaForceOffline YES`, Debug + API simulée seulement) : « hors ligne » d'emblée et pour toute la
/// session, sans démarrer le moniteur (sa première mesure remettrait « en ligne ») ; l'API simulée répond quand même.
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    init() {
        if LaunchOptions.forceOffline {
            isOnline = false
            return
        }
        // Appelé sur la file du moniteur : closure explicitement @Sendable (sinon elle hériterait de
        // l'isolation MainActor de l'initialiseur, et Swift 6 l'arrêterait hors du fil principal).
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            guard let self else { return }
            Task { @MainActor in
                self.update(isOnline: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.weydaa.app.connectivity", qos: .utility))
    }

    private func update(isOnline online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
    }
}
