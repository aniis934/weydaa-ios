import Foundation
import UIKit

/// Écrans demandés de l'extérieur — appui sur une notification, lien universel (`https://weydaa.com/…`), schéma
/// `weydaa://` — miroir du canal `deepLinks` de `MainActivity` (Android) : ce qui arrive avant que l'interface soit prête
/// (lancement à froid par une notification) est gardé, puis rejoué quand `WeydaApp` branche le routeur (`attach`).
/// Tenu par l'`AppDelegate`.
final class IncomingNavigation {
    /// `onOpenURL` et `onContinueUserActivity` peuvent livrer le MÊME lien universel : traité une fois.
    static let duplicateWindow: TimeInterval = 1
    /// Un lien rendu au navigateur ne l'est pas deux fois de suite (garde-fou contre un aller-retour app ↔ Safari).
    static let browserWindow: TimeInterval = 30

    private var router: AppRouter?
    private var pending: DeepLinkTarget?
    private var lastLink: (url: URL, date: Date)?
    private var lastBrowserLink: (url: URL, date: Date)?
    private let openInBrowser: (URL) -> Void
    private let now: () -> Date

    init(
        openInBrowser: @escaping (URL) -> Void = { url in UIApplication.shared.open(url) },
        now: @escaping () -> Date = { Date() }
    ) {
        self.openInBrowser = openInBrowser
        self.now = now
    }

    /// Interface prête (`WeydaApp`, premier affichage) : l'écran demandé entre-temps s'ouvre.
    func attach(_ router: AppRouter) {
        self.router = router
        if let target = pending {
            pending = nil
            router.open(target)
        }
    }

    /// Ouvre l'écran visé, ou le garde jusqu'à `attach` (le plus récent l'emporte).
    func open(_ target: DeepLinkTarget) {
        guard let router else {
            pending = target
            return
        }
        router.open(target)
    }

    /// Lien entrant : écran natif (`DeepLinks`) ; une page du site sans écran natif repart au navigateur (comme
    /// `MainActivity.sanitize`, Android) ; tout autre lien est ignoré.
    func handleLink(_ url: URL) {
        let date = now()
        if let last = lastLink, last.url == url, date.timeIntervalSince(last.date) < Self.duplicateWindow {
            return
        }
        lastLink = (url: url, date: date)
        if let target = DeepLinks.resolve(url) {
            open(target)
            return
        }
        guard DeepLinks.opensInBrowser(url) else { return }
        if let last = lastBrowserLink, last.url == url, date.timeIntervalSince(last.date) < Self.browserWindow {
            return
        }
        lastBrowserLink = (url: url, date: date)
        openInBrowser(url)
    }
}
