import Foundation

/// Trame Phoenix reçue de Supabase Realtime (protocole v1, `vsn=1.0.0`) — portage de `RealtimeFrame` (Android).
/// `topic` est le topic Weyda NU (`conv:{id}:{hmac}`), sans le préfixe `realtime:` du canal.
nonisolated enum RealtimeFrame: Hashable, Sendable {
    /// `event:"broadcast"` : le vrai nom d'événement et sa charge utile sont imbriqués.
    case broadcast(topic: String, event: String, payload: [String: JSONValue])
    /// Réponse à un `phx_join` / `heartbeat` (`status` = ok | error | timeout).
    case reply(topic: String, status: String, ref: String?)
    /// `phx_error` / `phx_close` : le canal est tombé, il faut le rejoindre. `ref` = `join_ref` du canal fermé
    /// (sérialiseur v1) : un `phx_close` qui porte une AUTRE référence que le join courant accuse seulement
    /// réception d'un ancien canal (notre `phx_leave`, un join remplacé) — à ignorer.
    case closed(topic: String, event: String, ref: String?)
    /// Présence : `presence_state` (état complet, `replace` vrai) ou `presence_diff` (arrivées / départs). Les
    /// clés sont celles données au `phx_join` : l'id de l'utilisateur, comme le fil du site (`presence.key`).
    case presence(topic: String, joins: Set<String>, leaves: Set<String>, replace: Bool)
    case other(topic: String, event: String)

    var topic: String {
        switch self {
        case .broadcast(let topic, _, _), .reply(let topic, _, _), .closed(let topic, _, _),
             .presence(let topic, _, _, _), .other(let topic, _):
            return topic
        }
    }
}

/// Notification in-app reçue en direct sur le canal personnel (événement `notification` : cloche).
nonisolated struct RealtimeNotification: Hashable, Sendable {
    var id: String
    var type: String
    var title: String
    var body: String
    var url: String?
    var createdAt: Date?

    /// Entrée de la liste des notifications, non lue — la conversion de `NotificationsRepository.onRealtime`
    /// (Android) : type inconnu → `.unknown`, URL vide → nil, date absente → maintenant.
    func toAppNotification(now: Date = Date()) -> AppNotification {
        AppNotification(
            id: id,
            kind: NotificationKind.from(type),
            title: title,
            body: body,
            url: TextCheck.nonBlank(url),
            read: false,
            createdAt: createdAt ?? now
        )
    }
}

/// Événement métier issu d'un broadcast (`src/lib/realtime.ts` côté serveur, `ChatInterface.tsx` pour « écrit… »)
/// — mêmes cas que `RealtimeEvent` (Android).
nonisolated enum RealtimeEvent: Hashable, Sendable {
    /// `convTopic` : message ou offre ajouté au fil.
    case messageNew(ChatMessage)
    /// `convTopic` : message supprimé (suppression douce).
    case messageDeleted(conversationId: String, messageId: String)
    /// `convTopic` : l'autre partie a ouvert le fil, mes messages passent à « lu ».
    case messagesRead(readerId: String, readAt: Date?)
    /// `userTopic` : un message est arrivé dans une de mes conversations (liste + pastille).
    case conversationTouched(conversationId: String, senderId: String, senderName: String, preview: String, createdAt: Date?)
    /// `convTopic` : l'autre partie écrit (`typing`) ou s'est arrêtée (`stopped_typing`), envoyé par son client.
    case typing(userId: String, isTyping: Bool)
    /// `userTopic` : notification in-app (cloche).
    case notificationReceived(RealtimeNotification)
}

/// Encodage et décodage du protocole Phoenix de Supabase Realtime — portage de `PhoenixProtocol` (Android).
/// Pur : aucune dépendance au réseau ni à l'interface.
nonisolated enum PhoenixProtocol {
    static let channelPrefix = "realtime:"
    static let heartbeatTopic = "phoenix"

    /// `wss://{ref}.supabase.co/realtime/v1/websocket?apikey=…&vsn=1.0.0` (le http(s) devient ws(s)).
    static func socketURLString(supabaseURL: String, anonKey: String) -> String {
        var base = supabaseURL
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("https://") {
            base = "wss://" + String(base.dropFirst("https://".count))
        } else if base.hasPrefix("http://") {
            base = "ws://" + String(base.dropFirst("http://".count))
        }
        return "\(base)/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"
    }

    /// URL de la socket, ou nil si l'hôte ou la clé anon manquent (l'app reste alors en HTTP seul).
    static func socketURL(supabaseURL: URL?, anonKey: String?) -> URL? {
        guard let supabaseURL, let key = TextCheck.nonBlank(anonKey) else { return nil }
        return URL(string: socketURLString(supabaseURL: supabaseURL.absoluteString, anonKey: key))
    }

    /// `phx_join` sur `realtime:{topic}`. `broadcast.self = false` : le serveur ne nous renvoie pas nos propres
    /// envois, comme le client web. `access_token` = clé anon, le topic étant déjà signé HMAC par le serveur.
    static func joinFrame(topic: String, ref: String, accessToken: String, presenceKey: String = "") -> String {
        let broadcast: JSONValue = .object(["ack": .bool(false), "self": .bool(false)])
        let presence: JSONValue = .object(["key": .string(presenceKey)])
        let config: JSONValue = .object(["broadcast": broadcast, "presence": presence, "postgres_changes": .array([])])
        let payload: JSONValue = .object(["config": config, "access_token": .string(accessToken)])
        let frame: JSONValue = .object([
            "topic": .string(channelPrefix + topic),
            "event": .string("phx_join"),
            "payload": payload,
            "ref": .string(ref),
            "join_ref": .string(ref),
        ])
        return encode(frame)
    }

    /// Broadcast émis par NOTRE client (« est en train d'écrire »), comme `channel.send({ type: "broadcast" })` du
    /// site. Seuls les événements éphémères passent par là ; les messages restent écrits par l'API.
    static func broadcastFrame(topic: String, event: String, payload: [String: JSONValue], ref: String) -> String {
        let envelope: JSONValue = .object(["type": .string("broadcast"), "event": .string(event), "payload": .object(payload)])
        let frame: JSONValue = .object([
            "topic": .string(channelPrefix + topic),
            "event": .string("broadcast"),
            "payload": envelope,
            "ref": .string(ref),
        ])
        return encode(frame)
    }

    /// `channel.track({ userId })` : annonce notre présence sur le fil (point « En ligne » chez l'autre).
    static func trackFrame(topic: String, userId: String, ref: String) -> String {
        let envelope: JSONValue = .object([
            "type": .string("presence"),
            "event": .string("track"),
            "payload": .object(["userId": .string(userId)]),
        ])
        let frame: JSONValue = .object([
            "topic": .string(channelPrefix + topic),
            "event": .string("presence"),
            "payload": envelope,
            "ref": .string(ref),
        ])
        return encode(frame)
    }

    static func leaveFrame(topic: String, ref: String) -> String {
        let frame: JSONValue = .object([
            "topic": .string(channelPrefix + topic),
            "event": .string("phx_leave"),
            "payload": .object([:]),
            "ref": .string(ref),
        ])
        return encode(frame)
    }

    /// Écrit à la main, dans l'ordre d'Android : `{"topic":"phoenix","event":"heartbeat","payload":{},"ref":"7"}`.
    static func heartbeatFrame(ref: String) -> String {
        "{\"topic\":\"\(heartbeatTopic)\",\"event\":\"heartbeat\",\"payload\":{},\"ref\":\(encode(.string(ref)))}"
    }

    /// `realtime:conv:abc:1234` → `conv:abc:1234` (le topic tel que le renvoie l'API).
    static func bareTopic(_ channel: String) -> String {
        channel.hasPrefix(channelPrefix) ? String(channel.dropFirst(channelPrefix.count)) : channel
    }

    /// Trame lue, ou nil si le texte n'est pas une trame Phoenix (JSON illisible, topic ou événement absent).
    static func parse(_ text: String) -> RealtimeFrame? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
              let object = root.objectValue,
              let channel = object["topic"]?.textValue,
              let event = object["event"]?.textValue
        else {
            return nil
        }
        let topic = bareTopic(channel)
        switch event {
        case "broadcast":
            guard let envelope = object["payload"]?.objectValue, let inner = envelope["event"]?.textValue else { return nil }
            return .broadcast(topic: topic, event: inner, payload: envelope["payload"]?.objectValue ?? [:])
        case "phx_reply":
            let status = object["payload"]?["status"]?.textValue ?? "error"
            return .reply(topic: topic, status: status, ref: object["ref"]?.textValue)
        case "phx_error", "phx_close":
            return .closed(topic: topic, event: event, ref: object["ref"]?.textValue)
        case "presence_state":
            return .presence(topic: topic, joins: keys(of: object["payload"]), leaves: [], replace: true)
        case "presence_diff":
            let diff = object["payload"]
            return .presence(topic: topic, joins: keys(of: diff?["joins"]), leaves: keys(of: diff?["leaves"]), replace: false)
        default:
            return .other(topic: topic, event: event)
        }
    }

    /// Traduit un broadcast en événement métier. `conversationId` est celui du fil écouté : la charge utile de
    /// `message_new` ne le porte pas (le topic est signé, il n'est pas déchiffrable ici).
    static func toEvent(_ frame: RealtimeFrame, conversationId: String = "") -> RealtimeEvent? {
        guard case let .broadcast(_, event, payload) = frame else { return nil }
        func string(_ key: String) -> String? { payload[key]?.textValue }
        switch event {
        case "message_new":
            guard let message = decodeMessage(payload) else { return nil }
            return .messageNew(message.toDomain(fallbackConversationId: conversationId))
        case "message_deleted":
            guard let messageId = string("messageId") else { return nil }
            return .messageDeleted(conversationId: string("conversationId") ?? conversationId, messageId: messageId)
        case "typing", "stopped_typing":
            guard let userId = string("userId") else { return nil }
            return .typing(userId: userId, isTyping: event == "typing")
        case "messages_read":
            guard let readerId = string("readerId") else { return nil }
            return .messagesRead(readerId: readerId, readAt: DateParsing.parseInstant(string("readAt")))
        case "new_message":
            guard let id = string("conversationId") else { return nil }
            return .conversationTouched(
                conversationId: id,
                senderId: string("senderId") ?? "",
                senderName: string("senderName") ?? "",
                preview: string("content") ?? "",
                createdAt: DateParsing.parseInstant(string("createdAt"))
            )
        case "notification":
            guard let id = string("id") else { return nil }
            let notification = RealtimeNotification(
                id: id,
                type: string("type") ?? "",
                title: string("title") ?? "",
                body: string("body") ?? "",
                url: string("url"),
                createdAt: DateParsing.parseInstant(string("createdAt"))
            )
            return .notificationReceived(notification)
        default:
            return nil
        }
    }

    // MARK: - Interne

    /// Message du fil : décodé par le DTO tolérant de l'API (mêmes règles que `GET /api/conversations/{id}`).
    private static func decodeMessage(_ payload: [String: JSONValue]) -> MessageDTO? {
        guard let data = try? JSONEncoder().encode(JSONValue.object(payload)) else { return nil }
        return try? JSONDecoder().decode(MessageDTO.self, from: data)
    }

    private static func keys(of value: JSONValue?) -> Set<String> {
        guard let object = value?.objectValue else { return [] }
        return Set(object.keys)
    }

    /// JSON compact, clés triées (trames reproductibles), barres obliques non échappées.
    private static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
