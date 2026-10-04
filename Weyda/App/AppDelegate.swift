import os
import UIKit
import UserNotifications

/// Délégué d'application (`@UIApplicationDelegateAdaptor` dans `WeydaApp`) : conteneur de l'app, Firebase, jeton APNs,
/// notifications système (appui et boutons d'action), raccourcis de l'icône, liens entrants — ce que font `WeydaApp.kt`,
/// `MainActivity` et `WeydaMessagingService` sur Android.
///
/// Il est créé AVANT les `@StateObject` de `WeydaApp` : ce qui arrive avant que l'interface soit prête (appui sur une
/// notification ou raccourci qui lance l'app) est gardé jusqu'à `attach(router:)`, appelé par `WeydaApp` au premier
/// affichage.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(subsystem: "com.weydaa.app", category: "push")

    /// Le délégué vivant. `UIApplication.shared.delegate` est l'adaptateur de SwiftUI, pas cette classe : le délégué de
    /// scène (`SceneDelegate`, raccourcis de l'icône) passe par ici.
    static weak var current: AppDelegate?

    /// Conteneur de l'app (session, repositories), créé au LANCEMENT et non par la scène : une action de notification
    /// (« Répondre », « Accepter ») peut lancer l'app en arrière-plan sans qu'aucune scène se connecte. Un seul conteneur,
    /// donc une seule session : jamais deux rotations concurrentes du jeton de rafraîchissement.
    private(set) lazy var container = AppContainer()

    /// Copie du fil visible, lue par le délégué des notifications hors du fil principal.
    private let foreground = PushForegroundFilter()
    /// Gardé ici : `UNUserNotificationCenter.delegate` est une référence faible.
    private var notificationDelegate: PushNotificationDelegate?
    private lazy var navigation = IncomingNavigation()
    private lazy var quickActions = PushActionPerformer(
        conversations: container.conversations,
        notifications: container.notifications,
        isSignedIn: { [weak self] in self?.container.sessionManager.user != nil }
    )
    private var isAttached = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.current = self
        let foreground = self.foreground
        foreground.setVisibleConversation(container.conversations.visibleConversationId)
        container.conversations.visibleConversationObserver = { id in
            foreground.setVisibleConversation(id)
        }
        installShortcutItems(application)
        // Sans GoogleService-Info.plist, en API simulée ou pendant les tests : aucun branchement système (ni catégories,
        // ni délégué, ni inscription APNs) — la CI et les captures restent identiques.
        guard FirebasePush.prepare() else { return true }
        // Boutons d'action (« Répondre », « Accepter », « Refuser ») : catégories enregistrées AVANT le délégué.
        UNUserNotificationCenter.current().setNotificationCategories(NotificationCategories.all())
        // Délégué posé AVANT la fin du lancement : l'appui qui a lancé l'app est livré ici (puis gardé jusqu'à `attach`).
        let delegate = PushNotificationDelegate(
            foreground: foreground,
            onOpen: { [weak self] payload in
                Task { @MainActor [weak self] in
                    self?.openNotification(payload)
                }
            },
            onAction: { [weak self] action in
                await self?.performQuickAction(action)
            }
        )
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        // À chaque lancement (recommandation d'Apple) ; n'affiche rien : l'autorisation de notifier est demandée plus
        // tard, à la première ouverture de Messages (`PushRegistrar.requestAuthorizationIfNeeded`).
        application.registerForRemoteNotifications()
        return true
    }

    /// Scène de l'app : SwiftUI garde la fenêtre, `SceneDelegate` reçoit les raccourcis de l'icône (dans une app à scènes,
    /// `application(_:performActionFor:)` n'est jamais appelé).
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebasePush.setAPNsToken(deviceToken)
        container.push.apnsTokenDidArrive()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Self.logger.notice("Inscription APNs impossible : \(error.localizedDescription, privacy: .public)")
    }

    /// Interface prête (`WeydaApp`, premier affichage) : l'écran demandé entre-temps (notification, raccourci, lien)
    /// s'ouvre. Sans effet au second appel.
    func attach(router: AppRouter) {
        guard !isAttached else { return }
        isAttached = true
        navigation.attach(router)
    }

    /// Lien universel (`onContinueUserActivity`) ou schéma `weydaa://` (`onOpenURL`) : écran natif, sinon Safari.
    func handleLink(_ url: URL) {
        navigation.handleLink(url)
    }

    /// Raccourci de l'icône (`SceneDelegate`) : Déposer, Rechercher, Messages ; faux pour un article inconnu.
    @discardableResult
    func handleShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = ShortcutAction(shortcutType: item.type) else { return false }
        navigation.open(action.target())
        return true
    }

    /// Articles DYNAMIQUES posés à chaque lancement : titres dans la langue courante de l'app.
    private func installShortcutItems(_ application: UIApplication) {
        application.shortcutItems = ShortcutAction.allCases.map { (action: ShortcutAction) -> UIApplicationShortcutItem in
            UIApplicationShortcutItem(
                type: action.type,
                localizedTitle: action.title,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: action.symbol),
                userInfo: nil
            )
        }
    }

    /// Appui sur une notification : l'écran du lien (`/…/dashboard/messages/<id>` → le fil), ouvert sur l'onglet courant.
    private func openNotification(_ payload: PushPayload) {
        guard let target = payload.target() else { return }
        navigation.open(target)
    }

    /// Bouton d'action d'une notification : envoyé avec la session de l'app, même sans écran.
    private func performQuickAction(_ action: PushQuickAction) async {
        await quickActions.perform(action)
    }
}
