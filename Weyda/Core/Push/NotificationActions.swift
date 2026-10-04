import Foundation
import os
import UserNotifications

/// Catégories APNs posées par le serveur (`aps.category`, lot B : `src/lib/fcm.ts` → `apnsCategory`).
nonisolated enum NotificationCategoryID {
    /// Nouveau message : bouton « Répondre » avec champ de saisie.
    static let message = "MESSAGE"
    /// Offre ou contre-offre reçue : « Accepter » / « Refuser ».
    static let offer = "OFFER"
}

/// Identifiants des boutons d'action des notifications.
nonisolated enum NotificationActionID {
    static let reply = "weyda.reply"
    static let acceptOffer = "weyda.offer.accept"
    static let declineOffer = "weyda.offer.decline"
}

/// Action demandée depuis une notification, sans ouvrir l'app — extraite TOUT DE SUITE de la réponse système (non
/// `Sendable`) en une valeur qui peut changer de fil. Logique pure.
nonisolated struct PushQuickAction: Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// Réponse saisie dans la notification (texte déjà nettoyé, jamais vide).
        case reply(String)
        /// Accepter ou refuser la dernière offre du fil.
        case offer(OfferAction)
    }

    let conversationId: String
    /// Notification du serveur à marquer lue une fois l'action faite (nil si la charge n'en porte pas).
    let notificationId: String?
    let kind: Kind

    /// nil = pas une action rapide : appui simple, notification balayée, bouton inconnu, réponse vide, ou fil introuvable
    /// dans la charge (`conversationId`, sinon le lien `/…/dashboard/messages/<id>`).
    static func from(actionIdentifier: String, payload: PushPayload, userText: String?) -> PushQuickAction? {
        guard let conversationId = payload.threadId else { return nil }
        let kind: Kind
        switch actionIdentifier {
        case NotificationActionID.reply:
            let text = (userText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            kind = .reply(text)
        case NotificationActionID.acceptOffer:
            kind = .offer(.accept)
        case NotificationActionID.declineOffer:
            kind = .offer(.decline)
        default:
            return nil
        }
        return PushQuickAction(conversationId: conversationId, notificationId: payload.notificationId, kind: kind)
    }
}

/// Catégories enregistrées au lancement, AVANT la pose du délégué des notifications.
nonisolated enum NotificationCategories {
    static func all() -> Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: NotificationActionID.reply,
            title: L10n.pushActionReply,
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: L10n.chatSend,
            textInputPlaceholder: L10n.chatMessagePlaceholder
        )
        // Accepter engage la vente : appareil déverrouillé exigé. Refuser reste possible écran verrouillé.
        let accept = UNNotificationAction(
            identifier: NotificationActionID.acceptOffer,
            title: L10n.offerAccept,
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark")
        )
        let decline = UNNotificationAction(
            identifier: NotificationActionID.declineOffer,
            title: L10n.offerDecline,
            options: [.destructive],
            icon: UNNotificationActionIcon(systemImageName: "xmark")
        )
        return [
            UNNotificationCategory(identifier: NotificationCategoryID.message, actions: [reply], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: NotificationCategoryID.offer, actions: [accept, decline], intentIdentifiers: [], options: []),
        ]
    }
}

/// Exécute une action rapide avec la session et les repositories de l'app (aussi quand l'app a été lancée en
/// arrière-plan par l'action : aucune scène, aucun écran). Réussite : notification du serveur marquée lue, pastille
/// relue. Échec (déconnecté, e-mail non vérifié, hors ligne, offre déjà traitée) : notification locale « ouvrez Weydaa ».
///
/// Risque connu (accepté pour la v1) : le serveur applique « accepter / refuser » à la DERNIÈRE offre du fil ; une vieille
/// notification agit donc sur l'offre la plus récente.
final class PushActionPerformer {
    nonisolated enum Outcome: Hashable, Sendable {
        case done
        case failed
    }

    private static let logger = Logger(subsystem: "com.weydaa.app", category: "push")

    private let conversations: ConversationsRepository
    private let notifications: NotificationsRepository
    private let isSignedIn: () -> Bool
    private let reportFailure: (PushQuickAction) -> Void

    init(
        conversations: ConversationsRepository,
        notifications: NotificationsRepository,
        isSignedIn: @escaping () -> Bool,
        reportFailure: @escaping (PushQuickAction) -> Void = PushActionFailureNotice.post
    ) {
        self.conversations = conversations
        self.notifications = notifications
        self.isSignedIn = isSignedIn
        self.reportFailure = reportFailure
    }

    @discardableResult
    func perform(_ action: PushQuickAction) async -> Outcome {
        guard isSignedIn() else {
            reportFailure(action)
            return .failed
        }
        do {
            switch action.kind {
            case .reply(let text):
                _ = try await conversations.send(conversationId: action.conversationId, content: text)
            case .offer(let offerAction):
                _ = try await conversations.offerAction(conversationId: action.conversationId, action: offerAction)
            }
        } catch {
            Self.logger.notice("Action de notification refusée : \(String(describing: error), privacy: .public)")
            reportFailure(action)
            return .failed
        }
        if let notificationId = action.notificationId {
            try? await notifications.markRead(id: notificationId)
        }
        // Pastille de l'icône = notifications non lues (relue ici : la socket est fermée en arrière-plan).
        _ = try? await notifications.page(page: 1, limit: 20)
        return .done
    }
}

/// Notification locale d'échec : « Action impossible depuis la notification. Ouvrez Weydaa pour réessayer. » ; l'appui
/// ouvre le fil (`conversationId` dans la charge, lu par `PushPayload.target()`).
nonisolated enum PushActionFailureNotice {
    static func post(_ action: PushQuickAction) {
        let content = UNMutableNotificationContent()
        content.body = L10n.pushActionFailed
        content.sound = .default
        content.threadIdentifier = action.conversationId
        content.userInfo = ["conversationId": action.conversationId]
        let request = UNNotificationRequest(
            identifier: "weyda.action.failed.\(action.conversationId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
