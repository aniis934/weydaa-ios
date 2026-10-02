import Foundation

// Portage de data/remote/dto/MessagingDtos.kt — messagerie (docs/API-CONTRACT.md §4) :
//  - GET  /api/conversations                 → { conversations, nextCursor } (curseur, PAS de hasMore)
//  - POST /api/conversations                 → 201 { conversationId, message }
//  - GET  /api/conversations/{id}            → conversation + { messages (asc), hasMore, nextCursor, topic }
//  - POST /api/conversations/{id}/messages   → 201 message brut
//  - DELETE .../messages/{messageId}         → { success } (suppression douce, fenêtre 5 min)
//  - POST / DELETE .../archive               → archiver / désarchiver (pas de bascule)
//  - POST /api/annonces/{id}/offers          → 201 { conversationId, message } ; 409 { offerAlreadyOpen, conversationId }
//  - POST /api/conversations/{id}/offers     → 201 message de type OFFER

nonisolated struct ConversationsPageDTO: Decodable, Hashable, Sendable {
    var conversations: [ConversationDTO] = []
    var nextCursor: String? = nil
}

nonisolated extension ConversationsPageDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        conversations = container.lenientList(ConversationDTO.self, "conversations")
        nextCursor = container.lenientString("nextCursor")
    }
}

nonisolated struct ConversationDTO: Decodable, Hashable, Sendable {
    var id: String
    var annonceId: String = ""
    var buyerId: String = ""
    var sellerId: String = ""
    var createdAt: String = ""
    var updatedAt: String = ""
    var annonce: ConversationAnnonceDTO? = nil
    var buyer: UserRefDTO? = nil
    var seller: UserRefDTO? = nil
    /// Liste : dernier message seulement (`content` vidé s'il est supprimé).
    var messages: [MessagePreviewDTO] = []
    /// Canal Realtime signé de la conversation (`conv:{id}:{hmac}`).
    var topic: String = ""
}

nonisolated extension ConversationDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        annonceId = container.lenientString("annonceId") ?? ""
        buyerId = container.lenientString("buyerId") ?? ""
        sellerId = container.lenientString("sellerId") ?? ""
        createdAt = container.lenientString("createdAt") ?? ""
        updatedAt = container.lenientString("updatedAt") ?? ""
        annonce = container.lenientObject(ConversationAnnonceDTO.self, "annonce")
        buyer = container.lenientObject(UserRefDTO.self, "buyer")
        seller = container.lenientObject(UserRefDTO.self, "seller")
        messages = container.lenientList(MessagePreviewDTO.self, "messages")
        topic = container.lenientString("topic") ?? ""
    }
}

/// Liste : `{ id, title, images[1] }` ; détail : + `status`, `price` (nombre), `priceType`.
nonisolated struct ConversationAnnonceDTO: Decodable, Hashable, Sendable {
    var id: String = ""
    var title: String = ""
    var status: String? = nil
    var price: Double? = nil
    var priceType: String? = nil
    var images: [ImageDTO] = []
}

nonisolated extension ConversationAnnonceDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = container.lenientString("id") ?? ""
        title = container.lenientString("title") ?? ""
        status = container.lenientString("status")
        price = container.lenientDouble("price")
        priceType = container.lenientString("priceType")
        images = container.lenientList(ImageDTO.self, "images")
    }
}

nonisolated struct MessagePreviewDTO: Decodable, Hashable, Sendable {
    var content: String = ""
    var createdAt: String = ""
    var senderId: String = ""
    var readAt: String? = nil
    var deletedAt: String? = nil
}

nonisolated extension MessagePreviewDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        content = container.lenientString("content") ?? ""
        createdAt = container.lenientString("createdAt") ?? ""
        senderId = container.lenientString("senderId") ?? ""
        readAt = container.lenientString("readAt")
        deletedAt = container.lenientString("deletedAt")
    }
}

nonisolated struct ConversationDetailDTO: Decodable, Hashable, Sendable {
    var id: String
    var buyerId: String = ""
    var sellerId: String = ""
    var annonceId: String = ""
    var createdAt: String = ""
    var updatedAt: String = ""
    var annonce: ConversationAnnonceDTO? = nil
    var buyer: UserRefDTO? = nil
    var seller: UserRefDTO? = nil
    /// Ordre chronologique croissant ; `content` vidé pour un message supprimé.
    var messages: [MessageDTO] = []
    /// Une page plus ancienne existe ; `nextCursor` = id du plus ancien message renvoyé.
    var hasMore: Bool = false
    var nextCursor: String? = nil
    var topic: String = ""
    /// J'ai bloqué l'interlocuteur (le fil propose alors « Débloquer »).
    var isBlockedByMe: Bool = false
}

nonisolated extension ConversationDetailDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        buyerId = container.lenientString("buyerId") ?? ""
        sellerId = container.lenientString("sellerId") ?? ""
        annonceId = container.lenientString("annonceId") ?? ""
        createdAt = container.lenientString("createdAt") ?? ""
        updatedAt = container.lenientString("updatedAt") ?? ""
        annonce = container.lenientObject(ConversationAnnonceDTO.self, "annonce")
        buyer = container.lenientObject(UserRefDTO.self, "buyer")
        seller = container.lenientObject(UserRefDTO.self, "seller")
        messages = container.lenientList(MessageDTO.self, "messages")
        hasMore = container.lenientBool("hasMore") ?? false
        nextCursor = container.lenientString("nextCursor")
        topic = container.lenientString("topic") ?? ""
        isBlockedByMe = container.lenientBool("isBlockedByMe") ?? false
    }
}

/// Message brut (réponses d'envoi, détail d'une conversation, événement temps réel `message_new`).
nonisolated struct MessageDTO: Decodable, Hashable, Sendable {
    var id: String
    var conversationId: String = ""
    var senderId: String = ""
    var content: String = ""
    var createdAt: String = ""
    var readAt: String? = nil
    var deletedAt: String? = nil
    var deletedBy: String? = nil
    /// `TEXT` | `OFFER`.
    var type: String = "TEXT"
    /// Offres : `{ kind: NEW|COUNTER|ACCEPTED|DECLINED, amount: number }`.
    var metadata: JSONValue? = nil
    var sender: UserRefDTO? = nil
}

nonisolated extension MessageDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        conversationId = container.lenientString("conversationId") ?? ""
        senderId = container.lenientString("senderId") ?? ""
        content = container.lenientString("content") ?? ""
        createdAt = container.lenientString("createdAt") ?? ""
        readAt = container.lenientString("readAt")
        deletedAt = container.lenientString("deletedAt")
        deletedBy = container.lenientString("deletedBy")
        type = container.lenientString("type") ?? "TEXT"
        metadata = container.lenientJSON("metadata")
        sender = container.lenientObject(UserRefDTO.self, "sender")
    }
}

nonisolated struct CreateConversationRequestDTO: Encodable, Hashable, Sendable {
    var annonceId: String
    var message: String
}

/// Réponse commune de `POST /api/conversations` et `POST /api/annonces/{id}/offers`.
nonisolated struct ConversationCreatedDTO: Decodable, Hashable, Sendable {
    var conversationId: String = ""
    var message: MessageDTO? = nil
}

nonisolated extension ConversationCreatedDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        conversationId = container.lenientString("conversationId") ?? ""
        message = container.lenientObject(MessageDTO.self, "message")
    }
}

nonisolated struct SendMessageRequestDTO: Encodable, Hashable, Sendable {
    var content: String
}

/// Montant entier en dinars (Zod : `int().positive().max(9 999 999 999)`).
nonisolated struct OfferInitiateRequestDTO: Encodable, Hashable, Sendable {
    var amount: Int
}

/// `action` = new | counter | accept | decline (`OfferAction.wire`) ; `amount` requis pour new / counter, omis sinon.
nonisolated struct OfferActionRequestDTO: Encodable, Hashable, Sendable {
    var action: String
    var amount: Int? = nil
}

/// `GET /api/annonces/{id}/contact` : numéro révélé (5 / h / utilisateur, 2 / h / annonce).
nonisolated struct ContactPhoneDTO: Decodable, Hashable, Sendable {
    var phone: String = ""
}

nonisolated extension ContactPhoneDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        phone = container.lenientString("phone") ?? ""
    }
}
