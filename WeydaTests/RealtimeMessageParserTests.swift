import XCTest
@testable import Weyda

/// Portage COMPLET de `RealtimeMessageParserTest.kt` (Android) — protocole Phoenix de Supabase Realtime
/// (`vsn=1.0.0`) : encodage des trames et décodage des broadcasts. Plus les trames propres à iOS (présence,
/// « écrit… », notification prête pour la liste).
final class RealtimeMessageParserTests: XCTestCase {
    private let topic = "conv:cmray1b1e000a80ezfbw8q9g5:1a2b3c4d5e6f7890"
    /// 2026-09-09T10:00:00Z.
    private let tenOClock = Date(timeIntervalSince1970: 1_788_948_000)

    private func object(_ text: String) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        return try XCTUnwrap(value.objectValue)
    }

    private func frame(_ text: String) throws -> RealtimeFrame {
        try XCTUnwrap(PhoenixProtocol.parse(text), "trame illisible : \(text)")
    }

    // MARK: - Cas d'Android

    func testSocketURLSwitchesToWssAndCarriesTheAnonKey() {
        XCTAssertEqual(
            PhoenixProtocol.socketURLString(supabaseURL: "https://projet.supabase.co/", anonKey: "anon-key"),
            "wss://projet.supabase.co/realtime/v1/websocket?apikey=anon-key&vsn=1.0.0"
        )
        // iOS : URL tirée de la configuration ; sans hôte ou sans clé, pas de socket (client inerte).
        XCTAssertEqual(
            PhoenixProtocol.socketURL(supabaseURL: URL(string: "https://projet.supabase.co"), anonKey: "anon-key")?.absoluteString,
            "wss://projet.supabase.co/realtime/v1/websocket?apikey=anon-key&vsn=1.0.0"
        )
        XCTAssertNil(PhoenixProtocol.socketURL(supabaseURL: nil, anonKey: "anon-key"))
        XCTAssertNil(PhoenixProtocol.socketURL(supabaseURL: URL(string: "https://projet.supabase.co"), anonKey: "  "))
    }

    func testJoinTargetsTheRealtimeChannelRefusesTheEchoAndCarriesTheToken() {
        let frame = PhoenixProtocol.joinFrame(topic: topic, ref: "1", accessToken: "anon-key")
        XCTAssertTrue(frame.contains("\"topic\":\"realtime:\(topic)\""), frame)
        XCTAssertTrue(frame.contains("\"event\":\"phx_join\""), frame)
        XCTAssertTrue(frame.contains("\"self\":false"), frame)
        XCTAssertTrue(frame.contains("\"access_token\":\"anon-key\""), frame)
        XCTAssertTrue(frame.contains("\"join_ref\":\"1\""), frame)
    }

    func testHeartbeatAndLeaveAreWellFormed() {
        XCTAssertEqual(PhoenixProtocol.heartbeatFrame(ref: "7"), #"{"topic":"phoenix","event":"heartbeat","payload":{},"ref":"7"}"#)
        XCTAssertTrue(PhoenixProtocol.leaveFrame(topic: topic, ref: "8").contains("\"event\":\"phx_leave\""))
    }

    func testMessageNewBroadcastBecomesAThreadMessage() throws {
        let text = """
            {"topic":"realtime:\(topic)","event":"broadcast","ref":null,
             "payload":{"type":"broadcast","event":"message_new","payload":{
               "id":"m10","content":"Toujours dispo ?","createdAt":"2026-09-09T10:00:00Z",
               "senderId":"user_2","readAt":null,"type":"TEXT","metadata":null}}}
            """
        let parsed = try frame(text)
        guard case .broadcast = parsed else { return XCTFail("broadcast attendu : \(parsed)") }
        XCTAssertEqual(parsed.topic, topic)

        guard case .messageNew(let message)? = PhoenixProtocol.toEvent(parsed, conversationId: "c1") else {
            return XCTFail("message attendu")
        }
        XCTAssertEqual(message.id, "m10")
        XCTAssertEqual(message.conversationId, "c1")
        XCTAssertEqual(message.senderId, "user_2")
        XCTAssertEqual(message.type, .text)
        XCTAssertEqual(message.createdAt, tenOClock)
        XCTAssertNil(message.readAt)
    }

    func testOfferBroadcastCarriesKindAndAmount() throws {
        let text = """
            {"topic":"realtime:\(topic)","event":"broadcast","payload":{"type":"broadcast","event":"message_new",
            "payload":{"id":"m11","content":"💰 1 800 000 DA","createdAt":"2026-09-09T10:05:00Z","senderId":"user_2",
            "readAt":null,"type":"OFFER","metadata":{"kind":"COUNTER","amount":1800000}}}}
            """
        let parsed = try frame(text)
        guard case .messageNew(let message)? = PhoenixProtocol.toEvent(parsed, conversationId: "c1") else {
            return XCTFail("offre attendue")
        }
        XCTAssertEqual(message.type, .offer)
        XCTAssertEqual(message.offer?.kind, .counter)
        XCTAssertEqual(message.offer?.amount, 1_800_000)
    }

    func testDeletionAndReadReceipt() throws {
        let deleted = """
            {"topic":"realtime:\(topic)","event":"broadcast","payload":{"type":"broadcast",
            "event":"message_deleted","payload":{"conversationId":"c1","messageId":"m3"}}}
            """
        let deletedFrame = try frame(deleted)
        XCTAssertEqual(PhoenixProtocol.toEvent(deletedFrame), .messageDeleted(conversationId: "c1", messageId: "m3"))

        let read = """
            {"topic":"realtime:\(topic)","event":"broadcast","payload":{"type":"broadcast",
            "event":"messages_read","payload":{"readerId":"user_2","readAt":"2026-09-09T11:00:00Z"}}}
            """
        let readFrame = try frame(read)
        XCTAssertEqual(PhoenixProtocol.toEvent(readFrame), .messagesRead(readerId: "user_2", readAt: tenOClock.addingTimeInterval(3_600)))
    }

    func testPersonalChannelSignalsTouchedConversationsAndNotifications() throws {
        let userTopic = "user_1:abcdef0123456789"
        let touched = """
            {"topic":"realtime:user:\(userTopic)","event":"broadcast","payload":{"type":"broadcast",
            "event":"new_message","payload":{"conversationId":"c9","senderId":"user_2","senderName":"Karim B.",
            "content":"Bonjour","createdAt":"2026-09-09T12:00:00Z"}}}
            """
        let touchedFrame = try frame(touched)
        XCTAssertEqual(touchedFrame.topic, "user:\(userTopic)")
        guard case let .conversationTouched(conversationId, senderId, senderName, preview, createdAt)? = PhoenixProtocol.toEvent(touchedFrame) else {
            return XCTFail("conversation touchée attendue")
        }
        XCTAssertEqual(conversationId, "c9")
        XCTAssertEqual(senderId, "user_2")
        XCTAssertEqual(senderName, "Karim B.")
        XCTAssertEqual(preview, "Bonjour")
        XCTAssertEqual(createdAt, tenOClock.addingTimeInterval(7_200))

        let notif = """
            {"topic":"realtime:user:\(userTopic)","event":"broadcast","payload":{"type":"broadcast",
            "event":"notification","payload":{"id":"n1","type":"MESSAGE","title":"Karim B.","body":"Bonjour",
            "url":"/dashboard/messages/c9","read":false}}}
            """
        let notifFrame = try frame(notif)
        guard case .notificationReceived(let notification)? = PhoenixProtocol.toEvent(notifFrame) else {
            return XCTFail("notification attendue")
        }
        XCTAssertEqual(notification.id, "n1")
        XCTAssertEqual(notification.url, "/dashboard/messages/c9")

        // iOS : entrée de liste prête pour la cloche (conversion de NotificationsRepository.onRealtime, Android).
        let item = notification.toAppNotification(now: tenOClock)
        XCTAssertEqual(item.kind, .message)
        XCTAssertFalse(item.read)
        XCTAssertEqual(item.createdAt, tenOClock)
        XCTAssertEqual(item.target, .conversation(id: "c9"))
    }

    func testJoinReplyClosedChannelUnknownEventAndUnreadableFrame() throws {
        let ok = #"{"topic":"realtime:\#(topic)","event":"phx_reply","ref":"1","payload":{"status":"ok","response":{}}}"#
        XCTAssertEqual(PhoenixProtocol.parse(ok), .reply(topic: topic, status: "ok", ref: "1"))

        let closed = #"{"topic":"realtime:\#(topic)","event":"phx_error","payload":{}}"#
        XCTAssertEqual(PhoenixProtocol.parse(closed), .closed(topic: topic, event: "phx_error", ref: nil))

        let system = #"{"topic":"realtime:\#(topic)","event":"system","payload":{"status":"ok"}}"#
        XCTAssertEqual(PhoenixProtocol.parse(system), .other(topic: topic, event: "system"))

        XCTAssertNil(PhoenixProtocol.parse("pas du json"))
        XCTAssertNil(PhoenixProtocol.parse(#"{"event":"broadcast"}"#))
    }

    func testUnknownOrIncompleteBroadcastGivesNoEvent() throws {
        let unknown = """
            {"topic":"realtime:\(topic)","event":"broadcast","payload":{"type":"broadcast",
            "event":"presence_ping","payload":{"userId":"user_2"}}}
            """
        let unknownFrame = try frame(unknown)
        XCTAssertNil(PhoenixProtocol.toEvent(unknownFrame))

        let incomplete = """
            {"topic":"realtime:\(topic)","event":"broadcast","payload":{"type":"broadcast",
            "event":"messages_read","payload":{}}}
            """
        let incompleteFrame = try frame(incomplete)
        XCTAssertNil(PhoenixProtocol.toEvent(incompleteFrame))
    }

    func testPhxCloseCarriesTheReferenceOfTheClosedChannel() {
        // C'est elle qui distingue une vraie chute du canal courant de l'accusé d'un ancien join / d'un leave.
        let parsed = PhoenixProtocol.parse(#"{"topic":"realtime:conv:c1:abc","event":"phx_close","payload":{},"ref":"7"}"#)
        XCTAssertEqual(parsed, .closed(topic: "conv:c1:abc", event: "phx_close", ref: "7"))
    }

    // MARK: - Propres à iOS

    func testTypingAndPresenceFrames() throws {
        let typing = #"{"topic":"realtime:\#(topic)","event":"broadcast","payload":{"type":"broadcast","event":"typing","payload":{"userId":"user_2"}}}"#
        let typingFrame = try frame(typing)
        XCTAssertEqual(PhoenixProtocol.toEvent(typingFrame), .typing(userId: "user_2", isTyping: true))
        let stopped = #"{"topic":"realtime:\#(topic)","event":"broadcast","payload":{"type":"broadcast","event":"stopped_typing","payload":{"userId":"user_2"}}}"#
        let stoppedFrame = try frame(stopped)
        XCTAssertEqual(PhoenixProtocol.toEvent(stoppedFrame), .typing(userId: "user_2", isTyping: false))

        let state = #"{"topic":"realtime:\#(topic)","event":"presence_state","payload":{"user_1":{"metas":[]},"user_2":{"metas":[]}}}"#
        let diff = #"{"topic":"realtime:\#(topic)","event":"presence_diff","payload":{"joins":{"user_3":{"metas":[]}},"leaves":{"user_2":{"metas":[]}}}}"#
        let stateFrame = try frame(state)
        let diffFrame = try frame(diff)
        XCTAssertEqual(stateFrame, .presence(topic: topic, joins: ["user_1", "user_2"], leaves: [], replace: true))
        XCTAssertEqual(diffFrame, .presence(topic: topic, joins: ["user_3"], leaves: ["user_2"], replace: false))

        var presence = RealtimePresence()
        let fromState = presence.apply(stateFrame)
        XCTAssertTrue(fromState)
        XCTAssertEqual(presence.present, ["user_1", "user_2"])
        let fromDiff = presence.apply(diffFrame)
        XCTAssertTrue(fromDiff)
        XCTAssertEqual(presence.present, ["user_1", "user_3"])
        let fromTyping = presence.apply(typingFrame)
        XCTAssertFalse(fromTyping)
        XCTAssertEqual(presence.present, ["user_1", "user_3"])
    }

    /// Envois de NOTRE client : mêmes enveloppes que `channel.send` / `channel.track` du site.
    func testOutgoingBroadcastAndTrackFramesFollowTheSiteFormat() throws {
        let broadcast = try object(PhoenixProtocol.broadcastFrame(topic: topic, event: "typing", payload: ["userId": .string("user_1")], ref: "5"))
        XCTAssertEqual(broadcast["topic"]?.stringValue, "realtime:\(topic)")
        XCTAssertEqual(broadcast["event"]?.stringValue, "broadcast")
        XCTAssertEqual(broadcast["ref"]?.stringValue, "5")
        XCTAssertEqual(broadcast["payload"]?["type"]?.stringValue, "broadcast")
        XCTAssertEqual(broadcast["payload"]?["event"]?.stringValue, "typing")
        XCTAssertEqual(broadcast["payload"]?["payload"]?["userId"]?.stringValue, "user_1")

        let track = try object(PhoenixProtocol.trackFrame(topic: topic, userId: "user_1", ref: "6"))
        XCTAssertEqual(track["event"]?.stringValue, "presence")
        XCTAssertEqual(track["payload"]?["type"]?.stringValue, "presence")
        XCTAssertEqual(track["payload"]?["event"]?.stringValue, "track")
        XCTAssertEqual(track["payload"]?["payload"]?["userId"]?.stringValue, "user_1")

        let join = try object(PhoenixProtocol.joinFrame(topic: topic, ref: "2", accessToken: "anon-key", presenceKey: "user_1"))
        XCTAssertEqual(join["payload"]?["config"]?["presence"]?["key"]?.stringValue, "user_1")
        XCTAssertEqual(join["payload"]?["config"]?["broadcast"]?["ack"]?.boolValue, false)
        XCTAssertEqual(join["payload"]?["config"]?["postgres_changes"]?.arrayValue, [])
    }
}
