import os
import UIKit
import UserNotifications

/// Délégué d'application (`@UIApplicationDelegateAdaptor` dans `WeydaApp`) : Firebase, jeton APNs, notifications
/// système, liens entrants — ce que font `WeydaApp.kt`, `MainActivity` et `WeydaMessagingService` sur Android.
///
/// Il est créé AVANT les `@StateObject` de `WeydaApp` : ce qui arrive avant que l'interface soit prête (appui sur une
/// notification qui lance l'app, jeton APNs) est gardé jusqu'à `attach(container:router:)`, appelé par `WeydaApp` au
/// premier affichage.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(subsystem: "com.weydaa.app", category: "push")

    /// Copie du fil visible, lue par le délégué des notifications hors du fil principal.
    private let foreground = PushForegroundFilter()
    /// Gardé ici : `UNUserNotificationCenter.delegate` est une référence faible.
    private var notificationDelegate: PushNotificationDelegate?
    private lazy var navigation = IncomingNavigation()
    private var container: AppContainer?
    /// Jeton APNs reçu avant `attach` : transmis au registre à ce moment-là.
    private var apnsTokenReceived = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Sans GoogleService-Info.plist, en API simulée ou pendant les tests : aucun branchement système (ni délégué, ni
        // inscription APNs) — la CI et les captures restent identiques.
        guard FirebasePush.prepare() else { return true }
        // Délégué posé AVANT la fin du lancement : l'appui qui a lancé l'app est livré ici (puis gardé jusqu'à `attach`).
        let delegate = PushNotificationDelegate(foreground: foreground) { [weak self] payload in
            Task { @MainActor [weak self] in
                self?.openNotification(payload)
            }
        }
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        // À chaque lancement (recommandation d'Apple) ; n'affiche rien : l'autorisation de notifier est demandée plus
        // tard, à la première ouverture de Messages (`PushRegistrar.requestAuthorizationIfNeeded`).
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebasePush.setAPNsToken(deviceToken)
        apnsTokenReceived = true
        container?.push.apnsTokenDidArrive()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Self.logger.notice("Inscription APNs impossible : \(error.localizedDescription, privacy: .public)")
    }

    /// Interface prête (`WeydaApp`, premier affichage) : fil visible recopié pour le délégué des notifications, jeton
    /// APNs déjà reçu transmis au registre, écran demandé entre-temps ouvert. Sans effet au second appel.
    func attach(container: AppContainer, router: AppRouter) {
        guard self.container == nil else { return }
        self.container = container
        let foreground = self.foreground
        foreground.setVisibleConversation(container.conversations.visibleConversationId)
        container.conversations.visibleConversationObserver = { id in
            foreground.setVisibleConversation(id)
        }
        if apnsTokenReceived {
            container.push.apnsTokenDidArrive()
        }
        navigation.attach(router)
    }

    /// Lien universel (`onContinueUserActivity`) ou schéma `weydaa://` (`onOpenURL`) : écran natif, sinon Safari.
    func handleLink(_ url: URL) {
        navigation.handleLink(url)
    }

    /// Appui sur une notification : l'écran du lien (`/…/dashboard/messages/<id>` → le fil), ouvert sur l'onglet courant.
    private func openNotification(_ payload: PushPayload) {
        guard let target = payload.target() else { return }
        navigation.open(target)
    }
}
