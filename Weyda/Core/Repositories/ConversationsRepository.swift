import Combine
import Foundation

/// Résultat de l'ouverture d'un échange depuis une annonce. `created` est faux quand le serveur a répondu 409
/// `offerAlreadyOpen` : rien n'a été écrit, on ouvre simplement la conversation existante (comme le site).
nonisolated struct ConversationEntry: Hashable, Sendable {
    let conversationId: String
    let created: Bool
}

/// Messagerie (`/api/conversations*`, `/api/annonces/{id}/offers`, `/api/users/{id}/block`) — portage de
/// `ConversationsRepository`. Session requise partout ; l'envoi exige en plus un e-mail vérifié
/// (403 `emailNotVerified`).
final class ConversationsRepository: ObservableObject {
    /// Conversations dont le dernier message vient de l'autre partie et n'est pas lu (pastille de l'onglet).
    @Published private(set) var unreadCount = 0

    /// Fil affiché à l'écran (`nil` sinon) : un push de ce fil n'est pas notifié, le message arrive en direct.
    var visibleConversationId: String?

    /// Une conversation a bougé (message reçu sur le canal personnel) : l'onglet Messages relit sa liste.
    var touched: AnyPublisher<Void, Never> { touchedSubject.eraseToAnyPublisher() }

    private let api: any WeydaAPI
    private let touchedSubject = PassthroughSubject<Void, Never>()

    init(api: any WeydaAPI) {
        self.api = api
    }

    func publishUnread(_ count: Int) {
        unreadCount = Swift.max(count, 0)
    }

    func notifyTouched() {
        touchedSubject.send(())
    }

    /// Relit la première page pour rafraîchir la pastille (démarrage, retour de session).
    @discardableResult
    func refreshUnread(userId: String) async throws -> Int {
        let page = try await list()
        let count = page.items.filter { $0.isUnreadFor(userId) }.count
        publishUnread(count)
        return count
    }

    /// Page de conversations (curseur) ; `archived` = archives de l'utilisateur (seul cas où le paramètre part).
    func list(cursor: String? = nil, archived: Bool = false, limit: Int = 20) async throws -> ConversationPage {
        try await api.getConversations(
            cursor: cursor,
            limit: RepositorySupport.clamp(limit, 1, 50),
            archived: archived ? true : nil
        ).toDomain()
    }

    /// Fil complet (messages croissants) ; l'appel marque aussi les messages reçus comme lus.
    func thread(id: String, cursor: String? = nil, limit: Int = 50) async throws -> ChatThread {
        try await api.getConversation(id: id, cursor: cursor, limit: RepositorySupport.clamp(limit, 1, 100)).toDomain()
    }

    func send(conversationId: String, content: String) async throws -> ChatMessage {
        let body = SendMessageRequestDTO(content: content.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await api.sendMessage(id: conversationId, body).toDomain(fallbackConversationId: conversationId)
    }

    /// Suppression douce côté serveur ; 403 `deletionWindowExpired` au-delà de 5 minutes.
    func deleteMessage(conversationId: String, messageId: String) async throws {
        _ = try await api.deleteMessage(id: conversationId, messageId: messageId)
    }

    /// POST = archiver, DELETE = désarchiver (le serveur n'a pas de bascule).
    func setArchived(conversationId: String, archived: Bool) async throws {
        if archived {
            _ = try await api.archiveConversation(id: conversationId)
        } else {
            _ = try await api.unarchiveConversation(id: conversationId)
        }
    }

    /// Négociation dans le fil ; le montant (dinars entiers) n'est envoyé que pour new / counter.
    func offerAction(conversationId: String, action: OfferAction, amount: Int? = nil) async throws -> ChatMessage {
        let body = OfferActionRequestDTO(action: action.wire, amount: action.needsAmount ? amount : nil)
        return try await api.postOfferAction(id: conversationId, body).toDomain(fallbackConversationId: conversationId)
    }

    /// « Contacter le vendeur » : crée ou réutilise la conversation ET envoie le premier message.
    func startConversation(annonceId: String, message: String) async throws -> ConversationEntry {
        let body = CreateConversationRequestDTO(
            annonceId: annonceId,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let dto = try await api.createConversation(body)
        return ConversationEntry(conversationId: dto.conversationId, created: true)
    }

    /// « Faire une offre » depuis l'annonce ; 409 `offerAlreadyOpen` (avec `conversationId`) = conversation à ouvrir
    /// telle quelle, sans erreur. Sans `conversationId`, le 409 reste une erreur.
    func makeOffer(annonceId: String, amount: Int) async throws -> ConversationEntry {
        do {
            let dto = try await api.initiateOffer(id: annonceId, OfferInitiateRequestDTO(amount: amount))
            return ConversationEntry(conversationId: dto.conversationId, created: true)
        } catch let error as APIError where error.code == "offerAlreadyOpen" {
            guard let existing = TextCheck.nonBlank(error.conversationId) else { throw error }
            return ConversationEntry(conversationId: existing, created: false)
        }
    }

    func setBlocked(userId: String, blocked: Bool) async throws {
        if blocked {
            _ = try await api.blockUser(id: userId)
        } else {
            _ = try await api.unblockUser(id: userId)
        }
    }

    /// Numéro du vendeur quand l'annonce ne l'expose pas (404 `noPhoneNumber`, 401 `loginRequired`).
    func revealPhone(annonceId: String) async throws -> String {
        try await api.getContactPhone(id: annonceId).phone
    }
}
