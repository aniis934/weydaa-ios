import UIKit

/// Délégué de la scène, déclaré par `AppDelegate.application(_:configurationForConnecting:options:)` : SwiftUI garde la
/// fenêtre et le reste ; seuls les raccourcis de l'icône passent ici (démarrage à froid : `connectionOptions.shortcutItem` ;
/// app déjà lancée : `windowScene(_:performActionFor:completionHandler:)`). L'écran visé est gardé jusqu'à ce que
/// l'interface soit prête (`IncomingNavigation`).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        AppDelegate.current?.handleShortcut(item)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = AppDelegate.current?.handleShortcut(shortcutItem) ?? false
        completionHandler(handled)
    }
}
