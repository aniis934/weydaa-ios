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
/// - à l'appui : ouverture de l'écran visé (`onOpen`, sur le fil principal par l'`AppDelegate`) ;
/// - sur un bouton d'action (« Répondre », « Accepter », « Refuser », phase 8) : l'action, sans ouvrir l'app (`onAction`),
///   puis seulement le gestionnaire de complétion (iOS laisse l'app vivre jusque-là).
/// Type `nonisolated` : iOS appelle ces méthodes sur un fil quelconque ; les données utiles sont extraites tout de suite
/// en `PushPayload` / `PushQuickAction` (`Sendable`) — aucun objet UserNotifications ne change de fil.
nonisolated final class PushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let foreground: PushForegroundFilter
    private let onOpen: @Sendable (PushPayload) -> Void
    private let onAction: @Sendable (PushQuickAction) async -> Void

    init(
        foreground: PushForegroundFilter,
        onOpen: @escaping @Sendable (PushPayload) -> Void,
        onAction: @escaping @Sendable (PushQuickAction) async -> Void = { _ in }
    ) {
        self.foreground = foreground
        self.onOpen = onOpen
        self.onAction = onAction
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
        let identifier = response.actionIdentifier
        if identifier == UNNotificationDefaultActionIdentifier {
            completionHandler()
            onOpen(payload)
            return
        }
        let userText = (response as? UNTextInputNotificationResponse)?.userText
        guard let action = PushQuickAction.from(actionIdentifier: identifier, payload: payload, userText: userText) else {
            completionHandler()
            return
        }
        // Le gestionnaire de complétion n'est pas `Sendable` : enveloppé pour être appelé à la fin de l'action.
        let completion = PushCompletion(completionHandler)
        let onAction = self.onAction
        Task {
            await onAction(action)
            completion.finish()
        }
    }
}

/// Gestionnaire de complétion d'une réponse à une notification, appelé une fois l'action faite. `@unchecked` : UIKit
/// accepte l'appel depuis n'importe quel fil, une seule fois (garanti ici par l'unique appel de `finish`).
nonisolated final class PushCompletion: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func finish() {
        handler()
    }
}
