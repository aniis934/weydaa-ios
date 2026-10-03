import Foundation
import os
import UserNotifications

/// Fil de discussion affiché à l'écran, recopié dans une boîte verrouillée : le délégué des notifications le lit hors du
/// fil principal (`ConversationsRepository.visibleConversationId` est sur le MainActor).
nonisolated final class PushForegroundFilter: Sendable {
    private let visible = OSAllocatedUnfairLock<String?>(initialState: nil)

    var visibleConversationId: String? {
        visible.withLock { $0 }
    }

    func setVisibleConversation(_ id: String?) {
        visible.withLock { $0 = id }
    }

    /// Bannière au premier plan ? Pas pour le fil déjà à l'écran (Android : pas de notification en double).
    func shouldPresent(_ payload: PushPayload) -> Bool {
        payload.isShown(whileViewing: visibleConversationId)
    }
}

/// Délégué du centre de notifications — équivalent iOS de `WeydaMessagingService` (Android), qui affiche et ouvre les
/// push. Ici le SYSTÈME affiche l'alerte (bloc `aps` du serveur, déjà traduit) ; l'app décide seulement :
/// - au premier plan : bannière + son + pastille, sauf pour le fil visible ;
/// - à l'appui : ouverture de l'écran visé (`onOpen`, sur le fil principal par l'`AppDelegate`).
/// Type `nonisolated` : iOS appelle ces méthodes sur un fil quelconque ; les données utiles sont extraites tout de suite
/// en `PushPayload` (`Sendable`) et le gestionnaire de complétion est appelé dans la méthode même — aucun objet
/// UserNotifications ne change de fil.
nonisolated final class PushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let foreground: PushForegroundFilter
    private let onOpen: @Sendable (PushPayload) -> Void

    init(foreground: PushForegroundFilter, onOpen: @escaping @Sendable (PushPayload) -> Void) {
        self.foreground = foreground
        self.onOpen = onOpen
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        if foreground.shouldPresent(payload) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        let opened = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        completionHandler()
        if opened {
            onOpen(payload)
        }
    }
}
