import Combine
import Foundation

/// Notifications in-app (`/api/notifications*`) — portage de `NotificationsRepository`.
///
/// `unreadCount` alimente la pastille de la cloche depuis n'importe quel écran ; `topic` est le canal Realtime
/// personnel signé renvoyé par le serveur (écouté par le conteneur une fois le temps réel branché). Les
/// notifications arrivées en direct sont republiées par `incoming` pour l'écran ouvert.
final class NotificationsRepository: ObservableObject {
    @Published private(set) var unreadCount = 0

    /// Canal personnel `user:{id}:{hmac}` mémorisé au premier chargement (`nil` tant qu'inconnu).
    private(set) var topic: String?

    /// Notifications reçues en direct (déjà comptées dans `unreadCount`).
    var incoming: AnyPublisher<AppNotification, Never> { incomingSubject.eraseToAnyPublisher() }

    private let api: any WeydaAPI
    private let incomingSubject = PassthroughSubject<AppNotification, Never>()

    init(api: any WeydaAPI) {
        self.api = api
    }

    /// Page de notifications (`limit` 1–50) ; la première page fixe aussi la pastille et le canal.
    func page(page: Int = 1, limit: Int = 20) async throws -> NotificationPage {
        let result = try await api.getNotifications(page: page, limit: RepositorySupport.clamp(limit, 1, 50)).toDomain()
        if !TextCheck.isBlank(result.topic) {
            topic = result.topic
        }
        if page == 1 {
            unreadCount = result.unreadCount
        }
        return result
    }

    /// Tout marquer comme lu ; renvoie le nombre mis à jour par le serveur.
    @discardableResult
    func markAllRead() async throws -> Int {
        let updated = try await api.markAllNotificationsRead().updated
        unreadCount = 0
        return updated
    }

    func markRead(id: String) async throws {
        _ = try await api.markNotificationRead(id: id)
        unreadCount = Swift.max(unreadCount - 1, 0)
    }

    /// Suppression définitive (404 si elle n'est pas à moi) ; la pastille baisse si elle n'était pas lue.
    func delete(id: String, wasUnread: Bool) async throws {
        _ = try await api.deleteNotification(id: id)
        if wasUnread {
            unreadCount = Swift.max(unreadCount - 1, 0)
        }
    }

    /// Trame `notification` du canal personnel : pastille incrémentée, écran ouvert prévenu.
    func onRealtime(_ event: RealtimeNotification) {
        onRealtime(event.toAppNotification())
    }

    /// Même effet à partir d'une notification déjà convertie (non lue, URL vide → `nil`, date absente → maintenant).
    func onRealtime(_ notification: AppNotification) {
        var received = notification
        received.read = false
        received.url = TextCheck.nonBlank(received.url)
        if received.createdAt == nil {
            received.createdAt = Date()
        }
        unreadCount += 1
        incomingSubject.send(received)
    }

    /// Déconnexion : plus de pastille, plus de canal.
    func reset() {
        unreadCount = 0
        topic = nil
    }
}
