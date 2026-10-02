import Foundation

// Portage de data/remote/dto/NotificationDtos.kt — notifications in-app (docs/API-CONTRACT.md §4) :
//  - GET    /api/notifications?page=&limit=  → { notifications, unreadCount, total, totalPages, page, topic }
//  - PATCH  /api/notifications               → { success, updated } (tout marquer comme lu)
//  - PATCH  /api/notifications/{id}          → { success } (une seule, 404 si pas la mienne)
//  - DELETE /api/notifications/{id}          → { success }

nonisolated struct NotificationsPageDTO: Decodable, Hashable, Sendable {
    var notifications: [NotificationDTO] = []
    var unreadCount: Int = 0
    var total: Int = 0
    var totalPages: Int = 1
    var page: Int = 1
    /// Canal Realtime personnel signé (`user:{id}:{hmac}`) : cloche et badges en direct.
    var topic: String = ""
}

nonisolated extension NotificationsPageDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        notifications = container.lenientList(NotificationDTO.self, "notifications")
        unreadCount = container.lenientInt("unreadCount") ?? 0
        total = container.lenientInt("total") ?? 0
        totalPages = container.lenientInt("totalPages") ?? 1
        page = container.lenientInt("page") ?? 1
        topic = container.lenientString("topic") ?? ""
    }
}

nonisolated struct NotificationDTO: Decodable, Hashable, Sendable {
    var id: String
    var userId: String = ""
    var type: String = ""
    var title: String = ""
    var body: String? = nil
    /// Chemin du site **sans langue** (`/annonce/{idOuSlug}`, `/dashboard/messages/{id}`, `/profil/{id}`).
    var url: String? = nil
    var read: Bool = false
    var metadata: JSONValue? = nil
    var createdAt: String = ""
}

nonisolated extension NotificationDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        userId = container.lenientString("userId") ?? ""
        type = container.lenientString("type") ?? ""
        title = container.lenientString("title") ?? ""
        body = container.lenientString("body")
        url = container.lenientString("url")
        read = container.lenientBool("read") ?? false
        metadata = container.lenientJSON("metadata")
        createdAt = container.lenientString("createdAt") ?? ""
    }
}

/// `PATCH /api/notifications` : nombre de notifications passées à lues.
nonisolated struct MarkAllReadDTO: Decodable, Hashable, Sendable {
    var success: Bool = true
    var updated: Int = 0
}

nonisolated extension MarkAllReadDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        success = container.lenientBool("success") ?? true
        updated = container.lenientInt("updated") ?? 0
    }
}
