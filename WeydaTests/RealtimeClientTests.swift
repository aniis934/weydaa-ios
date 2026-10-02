import XCTest
@testable import Weyda

/// Client temps réel sur un FAUX transport (aucun réseau) : format du join, battement, reconnexion et nouveau
/// join, distribution par canal, présence, arrière-plan, « écrit… », flux, client inerte sans configuration.
/// Les délais sont réduits à quelques millisecondes (`RealtimeTiming`).
final class RealtimeClientTests: XCTestCase {
    private let supabaseURL = URL(string: "https://projet.supabase.co")
    private let conv = "conv:c1:1a2b3c4d5e6f7890"
    private let user = "user:u1:abcdef0123456789"

    @MainActor
    private func makeClient(
        _ transport: FakeRealtimeTransport,
        heartbeat: TimeInterval = 30,
        startActive: Bool = true
    ) -> RealtimeClient {
        RealtimeClient(
            supabaseURL: supabaseURL,
            anonKey: "anon-key",
            transport: transport,
            timing: RealtimeTiming(heartbeat: heartbeat, baseBackoff: 0.01, maxBackoff: 0.05),
            startActive: startActive
        )
    }

    /// Attend une condition (les minuteries du client sont réelles, très courtes ici) ; faux au bout de `timeout`.
    @MainActor
    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    private func broadcast(_ channel: String, _ event: String, _ payload: String) -> String {
        "{\"topic\":\"realtime:\(channel)\",\"event\":\"broadcast\",\"payload\":{\"type\":\"broadcast\",\"event\":\"\(event)\",\"payload\":\(payload)}}"
    }

    private func reply(_ channel: String, ref: String, status: String) -> String {
        "{\"topic\":\"\(channel)\",\"event\":\"phx_reply\",\"ref\":\"\(ref)\",\"payload\":{\"status\":\"\(status)\",\"response\":{}}}"
    }

    // MARK: - Configuration et join

    @MainActor
    func testWithoutConfigurationTheClientIsInert() {
        let transport = FakeRealtimeTransport()
        let clients = [
            RealtimeClient(supabaseURL: nil, anonKey: "anon-key", transport: transport),
            RealtimeClient(supabaseURL: supabaseURL, anonKey: "  ", transport: transport),
            RealtimeClient(config: AppConfig(info: [:]), transport: transport),
        ]
        for client in clients {
            XCTAssertFalse(client.isEnabled)
            let subscription = client.subscribe(topic: conv) { _ in }
            client.sendTyping(topic: conv, userId: "user_1", isTyping: true)
            client.setActive(false)
            client.setActive(true)
            subscription.cancel()
            XCTAssertEqual(client.state, .disconnected)
        }
        XCTAssertTrue(transport.sockets.isEmpty)
    }

    @MainActor
    func testJoinIsSentOnOpenInTheSiteFormat() throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        XCTAssertTrue(client.isEnabled)
        let subscription = client.subscribe(topic: conv, presenceKey: "user_1") { _ in }
        defer { subscription.cancel() }
        XCTAssertEqual(transport.urls.map(\.absoluteString), ["wss://projet.supabase.co/realtime/v1/websocket?apikey=anon-key&vsn=1.0.0"])
        XCTAssertEqual(client.state, .connecting)
        let socket = try XCTUnwrap(transport.sockets.last)
        XCTAssertTrue(socket.sent.isEmpty, "rien n'est envoyé avant l'ouverture")

        socket.open()
        XCTAssertEqual(client.state, .connected)
        let join = try XCTUnwrap(socket.frames("phx_join").first)
        XCTAssertEqual(join["topic"]?.stringValue, "realtime:\(conv)")
        XCTAssertEqual(join["ref"], join["join_ref"])
        XCTAssertEqual(join["payload"]?["access_token"]?.stringValue, "anon-key")
        XCTAssertEqual(join["payload"]?["config"]?["broadcast"]?["self"]?.boolValue, false)
        XCTAssertEqual(join["payload"]?["config"]?["presence"]?["key"]?.stringValue, "user_1")

        // Un second abonné au même topic ne le rejoint pas deux fois (Phoenix fermerait le premier canal), et son
        // départ ne quitte pas le canal tant qu'un abonné reste.
        let second = client.subscribe(topic: conv) { _ in }
        XCTAssertEqual(socket.frames("phx_join").count, 1)
        second.cancel()
        XCTAssertTrue(socket.frames("phx_leave").isEmpty)
        XCTAssertEqual(transport.sockets.count, 1)
    }

    @MainActor
    func testAnAcceptedJoinAnnouncesPresenceAndARefusedOneIsRetried() async throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let subscription = client.subscribe(topic: conv, presenceKey: "user_1") { _ in }
        defer { subscription.cancel() }
        let socket = try XCTUnwrap(transport.sockets.last)
        socket.open()

        let ref = try XCTUnwrap(socket.lastJoinRef(for: "realtime:\(conv)"))
        socket.receive(reply("realtime:\(conv)", ref: ref, status: "ok"))
        let track = try XCTUnwrap(socket.frames("presence").first)
        XCTAssertEqual(track["payload"]?["event"]?.stringValue, "track")
        XCTAssertEqual(track["payload"]?["payload"]?["userId"]?.stringValue, "user_1")

        // Refus du join courant : nouveau join après le délai (10 ms ici).
        socket.receive(reply("realtime:\(conv)", ref: ref, status: "error"))
        let retried = await eventually { socket.frames("phx_join").count == 2 }
        XCTAssertTrue(retried)
    }

    @MainActor
    func testAStaleCloseIsIgnoredButTheCurrentChannelIsRejoined() async throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let subscription = client.subscribe(topic: conv) { _ in }
        defer { subscription.cancel() }
        let socket = try XCTUnwrap(transport.sockets.last)
        socket.open()

        // Accusé d'un ancien canal (référence étrangère) : rien.
        socket.receive("{\"topic\":\"realtime:\(conv)\",\"event\":\"phx_close\",\"payload\":{},\"ref\":\"999\"}")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(socket.frames("phx_join").count, 1)

        // Chute du canal courant : il est rejoint, sur la même socket.
        socket.receive("{\"topic\":\"realtime:\(conv)\",\"event\":\"phx_error\",\"payload\":{}}")
        let rejoined = await eventually { socket.frames("phx_join").count == 2 }
        XCTAssertTrue(rejoined)
        XCTAssertEqual(transport.sockets.count, 1)
    }

    // MARK: - Distribution

    @MainActor
    func testFramesAreRoutedToTheirOwnChannelOnASingleSocket() throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let conversation = Recorder<RealtimeFrame>()
        let personal = Recorder<RealtimeFrame>()
        let first = client.subscribe(topic: conv) { conversation.record($0) }
        let second = client.subscribe(topic: user) { personal.record($0) }
        defer {
            first.cancel()
            second.cancel()
        }
        XCTAssertEqual(transport.sockets.count, 1, "une seule socket pour tous les topics")
        let socket = try XCTUnwrap(transport.sockets.last)
        socket.open()
        XCTAssertEqual(Set(socket.joinedTopics()), ["realtime:\(conv)", "realtime:\(user)"])

        socket.receive(broadcast(conv, "typing", "{\"userId\":\"user_2\"}"))
        socket.receive(broadcast(user, "notification", "{\"id\":\"n1\",\"type\":\"MESSAGE\",\"title\":\"Karim B.\",\"body\":\"Bonjour\"}"))
        socket.receive(broadcast("conv:autre:0000", "typing", "{\"userId\":\"user_3\"}"))

        XCTAssertEqual(conversation.values.map(\.topic), [conv])
        XCTAssertEqual(personal.values.map(\.topic), [user])
        XCTAssertEqual(PhoenixProtocol.toEvent(conversation.values[0]), .typing(userId: "user_2", isTyping: true))
    }

    // MARK: - Battement et reconnexion

    @MainActor
    func testHeartbeatsKeepAnAnsweringSocketAndAnUnansweredOneIsReopened() async throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport, heartbeat: 0.25)
        let subscription = client.subscribe(topic: conv) { _ in }
        defer { subscription.cancel() }
        let first = try XCTUnwrap(transport.sockets.last)
        first.open()

        let beat = await eventually { !first.frames("heartbeat").isEmpty }
        XCTAssertTrue(beat)
        let heartbeat = try XCTUnwrap(first.frames("heartbeat").first)
        XCTAssertEqual(heartbeat["topic"]?.stringValue, "phoenix")
        let ref = try XCTUnwrap(heartbeat["ref"]?.stringValue)
        // Réponse reçue : la connexion vit, le battement suivant part sur la même socket.
        first.receive(reply("phoenix", ref: ref, status: "ok"))
        let secondBeat = await eventually { first.frames("heartbeat").count >= 2 }
        XCTAssertTrue(secondBeat)
        XCTAssertEqual(transport.sockets.count, 1)

        // Sans réponse : au battement suivant la socket est jugée morte, fermée et rouverte.
        let reopened = await eventually { transport.sockets.count == 2 }
        XCTAssertTrue(reopened)
        XCTAssertTrue(first.isClosed)
        XCTAssertEqual(client.state, .connecting)
        let second = try XCTUnwrap(transport.sockets.last)
        second.open()
        XCTAssertEqual(second.joinedTopics(), ["realtime:\(conv)"])
        XCTAssertEqual(client.state, .connected)
    }

    @MainActor
    func testTopicsAreRejoinedAfterTheSocketDrops() async throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let conversation = Recorder<RealtimeFrame>()
        let first = client.subscribe(topic: conv) { conversation.record($0) }
        let second = client.subscribe(topic: user) { _ in }
        defer {
            first.cancel()
            second.cancel()
        }
        let dropped = try XCTUnwrap(transport.sockets.last)
        dropped.open()
        dropped.drop()
        XCTAssertEqual(client.state, .connecting)

        let reconnected = await eventually { transport.sockets.count == 2 }
        XCTAssertTrue(reconnected)
        let fresh = try XCTUnwrap(transport.sockets.last)
        XCTAssertTrue(fresh.sent.isEmpty)
        fresh.open()
        XCTAssertEqual(Set(fresh.joinedTopics()), ["realtime:\(conv)", "realtime:\(user)"])

        // Ce qui arriverait encore de l'ancienne socket est ignoré.
        dropped.receive(broadcast(conv, "typing", "{\"userId\":\"user_2\"}"))
        XCTAssertTrue(conversation.values.isEmpty)
        fresh.receive(broadcast(conv, "typing", "{\"userId\":\"user_2\"}"))
        XCTAssertEqual(conversation.values.count, 1)
    }

    @MainActor
    func testTheLastUnsubscribeLeavesAndClosesTheSocket() throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let subscription = client.subscribe(topic: conv) { _ in }
        let socket = try XCTUnwrap(transport.sockets.last)
        socket.open()

        subscription.cancel()
        subscription.cancel() // sans effet la seconde fois
        XCTAssertEqual(socket.frames("phx_leave").count, 1)
        XCTAssertEqual(socket.frames("phx_leave").first?["topic"]?.stringValue, "realtime:\(conv)")
        XCTAssertTrue(socket.isClosed)
        XCTAssertEqual(client.state, .disconnected)

        // Un nouvel abonné rouvre une socket.
        let again = client.subscribe(topic: conv) { _ in }
        XCTAssertEqual(transport.sockets.count, 2)
        again.cancel()
    }

    // MARK: - Premier plan / arrière-plan

    @MainActor
    func testBackgroundClosesTheSocketAndForegroundRejoins() throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let subscription = client.subscribe(topic: conv) { _ in }
        defer { subscription.cancel() }
        let first = try XCTUnwrap(transport.sockets.last)
        first.open()

        client.setActive(false)
        XCTAssertTrue(first.isClosed)
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertTrue(first.frames("phx_leave").isEmpty, "l'abonné reste inscrit")

        client.setActive(true)
        XCTAssertEqual(transport.sockets.count, 2)
        let second = try XCTUnwrap(transport.sockets.last)
        second.open()
        XCTAssertEqual(second.joinedTopics(), ["realtime:\(conv)"])
    }

    @MainActor
    func testAClientStartedInTheBackgroundWaitsForTheForeground() {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport, startActive: false)
        let subscription = client.subscribe(topic: user) { _ in }
        defer { subscription.cancel() }
        XCTAssertTrue(transport.sockets.isEmpty)
        client.setActive(true)
        XCTAssertEqual(transport.sockets.count, 1)
    }

    // MARK: - « Écrit… »

    @MainActor
    func testTypingIsBroadcastOnlyOnAJoinedChannel() throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let subscription = client.subscribe(topic: conv) { _ in }
        defer { subscription.cancel() }
        let socket = try XCTUnwrap(transport.sockets.last)

        client.sendTyping(topic: conv, userId: "user_1", isTyping: true)
        XCTAssertTrue(socket.frames("broadcast").isEmpty, "rien avant l'ouverture")

        socket.open()
        client.sendTyping(topic: conv, userId: "user_1", isTyping: true)
        client.sendTyping(topic: conv, userId: "user_1", isTyping: false)
        client.sendTyping(topic: "conv:non-rejoint:0000", userId: "user_1", isTyping: true)
        let frames = socket.frames("broadcast")
        XCTAssertEqual(frames.map { $0["payload"]?["event"]?.stringValue }, ["typing", "stopped_typing"])
        XCTAssertEqual(frames.first?["topic"]?.stringValue, "realtime:\(conv)")
        XCTAssertEqual(frames.first?["payload"]?["payload"]?["userId"]?.stringValue, "user_1")
    }

    // MARK: - Flux

    @MainActor
    func testUserEventsStreamDecodesEventsAndLeavesWhenTheReaderStops() async throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let events = Recorder<RealtimeEvent>()
        let stream = client.userEvents(topic: user)
        let reader = Task { @MainActor in
            for await event in stream { events.record(event) }
        }
        let socket = try XCTUnwrap(transport.sockets.last)
        socket.open()
        XCTAssertEqual(socket.joinedTopics(), ["realtime:\(user)"])
        socket.receive(broadcast(user, "new_message", "{\"conversationId\":\"c9\",\"senderId\":\"user_2\",\"senderName\":\"Karim B.\",\"content\":\"Bonjour\"}"))
        socket.receive(broadcast(user, "notification", "{\"id\":\"n1\",\"type\":\"MESSAGE\",\"title\":\"Karim B.\",\"body\":\"Bonjour\"}"))

        let received = await eventually { events.values.count == 2 }
        XCTAssertTrue(received)
        guard case .conversationTouched(let conversationId, _, _, _, _)? = events.values.first else {
            return XCTFail("conversation touchée attendue")
        }
        XCTAssertEqual(conversationId, "c9")
        guard case .notificationReceived(let notification)? = events.values.last else {
            return XCTFail("notification attendue")
        }
        XCTAssertEqual(notification.id, "n1")

        // La lecture s'arrête (écran quitté, déconnexion) : l'abonnement est libéré, le canal quitté.
        reader.cancel()
        let left = await eventually { !socket.frames("phx_leave").isEmpty }
        XCTAssertTrue(left)
        XCTAssertEqual(client.state, .disconnected)
    }

    @MainActor
    func testConversationUpdatesCarryPresenceAndEventsOnOneSubscription() async throws {
        let transport = FakeRealtimeTransport()
        let client = makeClient(transport)
        let updates = Recorder<ConversationRealtimeUpdate>()
        let stream = client.conversationUpdates(topic: conv, conversationId: "c1", presenceKey: "user_1")
        let reader = Task { @MainActor in
            for await update in stream { updates.record(update) }
        }
        defer { reader.cancel() }
        let socket = try XCTUnwrap(transport.sockets.last)
        socket.open()
        XCTAssertEqual(socket.joinedTopics(), ["realtime:\(conv)"])

        socket.receive("{\"topic\":\"realtime:\(conv)\",\"event\":\"presence_state\",\"payload\":{\"user_1\":{\"metas\":[]},\"user_2\":{\"metas\":[]}}}")
        socket.receive("{\"topic\":\"realtime:\(conv)\",\"event\":\"presence_diff\",\"payload\":{\"joins\":{},\"leaves\":{\"user_2\":{\"metas\":[]}}}}")
        socket.receive(broadcast(conv, "message_new", "{\"id\":\"m1\",\"content\":\"Bonjour\",\"createdAt\":\"2026-09-09T10:00:00Z\",\"senderId\":\"user_2\",\"type\":\"TEXT\"}"))

        let received = await eventually { updates.values.count == 3 }
        XCTAssertTrue(received)
        XCTAssertEqual(updates.values.first, .presence(["user_1", "user_2"]))
        XCTAssertEqual(updates.values.dropFirst().first, .presence(["user_1"]))
        guard case .event(.messageNew(let message))? = updates.values.last else {
            return XCTFail("message attendu")
        }
        XCTAssertEqual(message.conversationId, "c1")
        XCTAssertEqual(message.id, "m1")
    }
}

// MARK: - Faux transport

/// Transport sans réseau : chaque `open` crée une fausse socket que le test pilote côté « serveur ».
@MainActor
final class FakeRealtimeTransport: RealtimeTransport {
    private(set) var sockets: [FakeRealtimeSocket] = []
    private(set) var urls: [URL] = []

    func open(url: URL, onEvent: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void) -> any RealtimeSocket {
        let socket = FakeRealtimeSocket(onEvent: onEvent)
        sockets.append(socket)
        urls.append(url)
        return socket
    }
}

@MainActor
final class FakeRealtimeSocket: RealtimeSocket {
    private let onEvent: @MainActor @Sendable (RealtimeSocketEvent) -> Void
    private(set) var sent: [String] = []
    private(set) var isClosed = false

    init(onEvent: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void) {
        self.onEvent = onEvent
    }

    func send(_ text: String) {
        sent.append(text)
    }

    func close() {
        isClosed = true
    }

    // Côté « serveur ».
    func open() { onEvent(.opened) }
    func receive(_ text: String) { onEvent(.message(text)) }
    func drop() { onEvent(.closed) }

    /// Trames envoyées d'un type d'événement (`phx_join`, `heartbeat`, `broadcast`…), décodées.
    func frames(_ event: String) -> [[String: JSONValue]] {
        sent.compactMap { (text: String) -> [String: JSONValue]? in
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
                  let object = value.objectValue,
                  object["event"]?.stringValue == event
            else { return nil }
            return object
        }
    }

    func joinedTopics() -> [String] {
        frames("phx_join").compactMap { $0["topic"]?.stringValue }
    }

    func lastJoinRef(for channel: String) -> String? {
        let joins = frames("phx_join").filter { $0["topic"]?.stringValue == channel }
        return joins.last?["ref"]?.stringValue
    }
}

/// Valeurs reçues par un abonné (boîte : les closures du client ne capturent pas de variable mutable).
@MainActor
final class Recorder<Value> {
    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}
