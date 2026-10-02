import Combine
import Foundation
import os

// MARK: - Transport (injectable)

/// Événement d'une socket, toujours remis sur le MainActor par le transport — jamais pendant l'appel à `open`.
nonisolated enum RealtimeSocketEvent: Hashable, Sendable {
    case opened
    case message(String)
    /// Fermée ou tombée (échec réseau, fermeture serveur) ; plus rien n'arrive ensuite.
    case closed
}

/// Connexion ouverte par un transport.
@MainActor
protocol RealtimeSocket: AnyObject {
    func send(_ text: String)
    /// Fermeture volontaire : aucun événement n'est plus remis ensuite.
    func close()
}

/// Transport WebSocket : `URLSessionWebSocketTask` en production, un faux dans les tests (aucun réseau).
@MainActor
protocol RealtimeTransport: AnyObject {
    func open(url: URL, onEvent: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void) -> any RealtimeSocket
}

// MARK: - Réglages, abonnement, présence

/// Délais du protocole (Android : battement 30 s, reconnexion exponentielle 1 s → 30 s). Réglables pour les tests.
nonisolated struct RealtimeTiming: Hashable, Sendable {
    var heartbeat: TimeInterval = 30
    var baseBackoff: TimeInterval = 1
    var maxBackoff: TimeInterval = 30

    /// 1, 2, 4, 8, 16 s puis le plafond.
    func backoff(attempt: Int) -> TimeInterval {
        min(maxBackoff, baseBackoff * Double(1 << min(max(attempt, 0), 5)))
    }
}

/// Abonnement à un topic : tant qu'il vit, le canal est rejoint. `cancel()` le quitte (sans effet la seconde
/// fois) ; il n'y a pas d'annulation automatique à la libération — les flux `AsyncStream` du client, eux,
/// annulent leur abonnement dès que la tâche qui les lit s'arrête.
nonisolated struct RealtimeSubscription: Sendable {
    private let onCancel: @MainActor @Sendable () -> Void

    init(onCancel: @escaping @MainActor @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    /// Abonnement refusé (client inerte, topic vide) : `cancel()` ne fait rien.
    static let inactive = RealtimeSubscription(onCancel: {})

    @MainActor
    func cancel() {
        onCancel()
    }
}

/// Présents sur un fil (ids), tenus à jour par `presence_state` / `presence_diff` — `RealtimeClient.presence` (Android).
nonisolated struct RealtimePresence: Hashable, Sendable {
    private(set) var present: Set<String> = []

    /// Applique une trame ; vrai si c'était une trame de présence (l'ensemble a pu changer).
    @discardableResult
    mutating func apply(_ frame: RealtimeFrame) -> Bool {
        guard case let .presence(_, joins, leaves, replace) = frame else { return false }
        if replace { present.removeAll() }
        present.formUnion(joins)
        present.subtract(leaves)
        return true
    }
}

/// Ce qu'un fil ouvert reçoit sur UN seul abonnement : événements métier et présence (point « En ligne »).
nonisolated enum ConversationRealtimeUpdate: Hashable, Sendable {
    case event(RealtimeEvent)
    case presence(Set<String>)
}

// MARK: - Client

/// Client temps réel Supabase — portage de `data/realtime/RealtimeClient.kt` (WebSocket + protocole Phoenix,
/// aucune dépendance).
///
/// Une seule WebSocket multiplexe tous les topics écoutés : elle s'ouvre au premier abonné, se ferme au dernier.
/// Les topics sont ceux SIGNÉS HMAC renvoyés par l'API (`conv:{id}:{hmac}`, `user:{id}:{hmac}`), jamais calculés
/// ici. Battement toutes les 30 s ; un battement resté sans réponse vaut connexion morte (changement de réseau,
/// NAT expiré) et rouvre la socket ; reconnexion exponentielle plafonnée à 30 s, puis tous les topics encore
/// écoutés sont rejoints. Un topic n'est rejoint qu'une fois par socket et chaque join mémorise sa référence :
/// un `phx_close` qui en porte une autre (ancien canal, accusé de notre `phx_leave`) est ignoré — sinon chaque
/// fermeture relancerait un join, en boucle.
///
/// Sur le MainActor : l'état (`state`) est observé par les écrans, les transports remettent leurs événements
/// sur le fil principal, aucun verrou n'est nécessaire. Sans URL Supabase ou sans clé anon, le client est
/// INERTE (`isEnabled` faux) : l'app fonctionne en HTTP seul.
final class RealtimeClient: ObservableObject {
    nonisolated enum State: String, Hashable, Sendable {
        case disconnected, connecting, connected
    }

    /// Une reconnexion (passage à `connected` après une coupure) : un fil ouvert relit sa dernière page, car
    /// un broadcast n'est jamais rejoué.
    @Published private(set) var state: State = .disconnected

    /// Faux sans URL Supabase ou sans clé anon (build sans secrets) : l'app reste en HTTP seul.
    let isEnabled: Bool

    private let socketURL: URL?
    private let anonKey: String
    private let transport: any RealtimeTransport
    private let timing: RealtimeTiming
    private let logger = Logger(subsystem: "com.weydaa.app", category: "realtime")

    private var subscribers: [String: [Int: @MainActor (RealtimeFrame) -> Void]] = [:]
    /// Clé de présence par topic (notre id sur un fil) : déclarée au join, annoncée par `track` après.
    private var presenceKeys: [String: String] = [:]
    /// Référence du dernier `phx_join` envoyé par topic = identité du canal courant.
    private var joinRefs: [String: String] = [:]
    private var rejoinAttempts: [String: Int] = [:]
    private var socket: (any RealtimeSocket)?
    /// Change à chaque socket et à chaque remise à zéro : les événements et minuteries d'avant sont ignorés.
    private var generation = 0
    /// Vrai entre l'ouverture et la fermeture : avant, les joins sont laissés à l'ouverture.
    private var opened = false
    private var pendingHeartbeat: String?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var attempts = 0
    private var refCounter = 0
    private var subscriptionCounter = 0
    /// Application au premier plan. En arrière-plan la socket est fermée ; les abonnés restent inscrits.
    private var active: Bool

    init(
        supabaseURL: URL?,
        anonKey: String?,
        transport: any RealtimeTransport = URLSessionRealtimeTransport(),
        timing: RealtimeTiming = RealtimeTiming(),
        startActive: Bool = true
    ) {
        let url = PhoenixProtocol.socketURL(supabaseURL: supabaseURL, anonKey: anonKey)
        self.socketURL = url
        self.anonKey = TextCheck.nonBlank(anonKey) ?? ""
        self.isEnabled = url != nil
        self.transport = transport
        self.timing = timing
        self.active = startActive
    }

    /// Hôte et clé lus dans la configuration (`Config/*.xcconfig`, coffre de la CI).
    convenience init(
        config: AppConfig,
        transport: any RealtimeTransport = URLSessionRealtimeTransport(),
        timing: RealtimeTiming = RealtimeTiming(),
        startActive: Bool = true
    ) {
        self.init(
            supabaseURL: config.supabaseURL,
            anonKey: config.supabaseAnonKey,
            transport: transport,
            timing: timing,
            startActive: startActive
        )
    }

    var isConnected: Bool { state == .connected }

    // MARK: - Premier plan / arrière-plan

    /// Premier plan (`scenePhase == .active`) / arrière-plan. En arrière-plan, garder la socket réveillerait la
    /// radio toutes les 30 s pour des événements que personne ne voit (et iOS suspend l'app de toute façon). Au
    /// retour, la socket se rouvre et rejoint tous les topics encore écoutés.
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if value {
            if socket == nil, !subscribers.isEmpty { connect() }
        } else {
            let closing = socket
            resetConnection()
            closing?.close()
            logger.debug("arrière-plan : socket fermée")
        }
    }

    // MARK: - Abonnements

    /// Trames brutes d'un topic, remises à `onFrame` sur le MainActor. Le premier abonné d'un topic le rejoint
    /// (et ouvre la socket au besoin), le dernier le quitte (et ferme la socket s'il n'en reste aucun).
    /// `presenceKey` : notre id sur un fil — le join le déclare et `track` l'annonce, comme le fil du site.
    func subscribe(
        topic: String,
        presenceKey: String? = nil,
        onFrame: @escaping @MainActor (RealtimeFrame) -> Void
    ) -> RealtimeSubscription {
        guard isEnabled, !TextCheck.isBlank(topic) else { return .inactive }
        subscriptionCounter += 1
        let id = subscriptionCounter
        if let key = TextCheck.nonBlank(presenceKey) { presenceKeys[topic] = key }
        let isFirst = subscribers[topic]?.isEmpty ?? true
        subscribers[topic, default: [:]][id] = onFrame
        if isFirst {
            // Socket en cours d'ouverture : l'ouverture rejoindra tous les topics inscrits (un join envoyé
            // maintenant serait doublé).
            if socket == nil {
                connect()
            } else if opened {
                join(topic)
            }
        }
        return RealtimeSubscription { [weak self] in
            self?.release(topic: topic, id: id)
        }
    }

    /// Trames brutes d'un topic ; l'abonnement vit tant que la tâche qui lit le flux tourne.
    func frames(topic: String, presenceKey: String? = nil) -> AsyncStream<RealtimeFrame> {
        AsyncStream { continuation in
            let subscription = subscribe(topic: topic, presenceKey: presenceKey) { frame in
                continuation.yield(frame)
            }
            continuation.onTermination = { _ in
                Task { @MainActor in subscription.cancel() }
            }
        }
    }

    /// Canal personnel (`user:{id}:{hmac}`) : `conversationTouched` (liste, pastille) et `notificationReceived` (cloche).
    func userEvents(topic: String) -> AsyncStream<RealtimeEvent> {
        AsyncStream { continuation in
            let subscription = subscribe(topic: topic) { frame in
                if let event = PhoenixProtocol.toEvent(frame) { continuation.yield(event) }
            }
            continuation.onTermination = { _ in
                Task { @MainActor in subscription.cancel() }
            }
        }
    }

    /// Fil d'une conversation : `messageNew`, `messageDeleted`, `messagesRead`, `typing`.
    func conversationEvents(topic: String, conversationId: String, presenceKey: String? = nil) -> AsyncStream<RealtimeEvent> {
        AsyncStream { continuation in
            let subscription = subscribe(topic: topic, presenceKey: presenceKey) { frame in
                if let event = PhoenixProtocol.toEvent(frame, conversationId: conversationId) { continuation.yield(event) }
            }
            continuation.onTermination = { _ in
                Task { @MainActor in subscription.cancel() }
            }
        }
    }

    /// Fil ouvert : événements ET présence sur un seul abonnement (Android : `frames` partagé par `shareIn`).
    func conversationUpdates(
        topic: String,
        conversationId: String,
        presenceKey: String? = nil
    ) -> AsyncStream<ConversationRealtimeUpdate> {
        AsyncStream { continuation in
            let tracker = PresenceTracker()
            let subscription = subscribe(topic: topic, presenceKey: presenceKey) { frame in
                if tracker.presence.apply(frame) {
                    continuation.yield(.presence(tracker.presence.present))
                } else if let event = PhoenixProtocol.toEvent(frame, conversationId: conversationId) {
                    continuation.yield(.event(event))
                }
            }
            continuation.onTermination = { _ in
                Task { @MainActor in subscription.cancel() }
            }
        }
    }

    // MARK: - Envois éphémères

    /// Broadcast sur un topic déjà rejoint (« est en train d'écrire »). Ignoré hors connexion : ce signal ne vaut
    /// que dans l'instant.
    func broadcast(topic: String, event: String, payload: [String: JSONValue]) {
        guard let socket, opened, joinRefs[topic] != nil else { return }
        socket.send(PhoenixProtocol.broadcastFrame(topic: topic, event: event, payload: payload, ref: nextRef()))
    }

    /// « Écrit… » / « a cessé d'écrire », même charge utile que le site (`{ userId }`). Le rythme (au plus toutes
    /// les 2 s, arrêt après 3 s sans frappe) appartient à l'écran, comme `ChatViewModel.signalTyping` (Android).
    func sendTyping(topic: String, userId: String, isTyping: Bool) {
        broadcast(topic: topic, event: isTyping ? "typing" : "stopped_typing", payload: ["userId": .string(userId)])
    }

    // MARK: - Cycle de vie de la connexion

    private func release(topic: String, id: Int) {
        guard var handlers = subscribers[topic] else { return }
        guard handlers.removeValue(forKey: id) != nil else { return }
        if !handlers.isEmpty {
            subscribers[topic] = handlers
            return
        }
        subscribers[topic] = nil
        presenceKeys[topic] = nil
        joinRefs[topic] = nil
        rejoinAttempts[topic] = nil
        if let socket, opened {
            socket.send(PhoenixProtocol.leaveFrame(topic: topic, ref: nextRef()))
        }
        disconnectIfIdle()
    }

    private func connect() {
        guard let socketURL, socket == nil, active else { return }
        generation += 1
        let current = generation
        opened = false
        state = .connecting
        socket = transport.open(url: socketURL) { [weak self] event in
            self?.handle(event, generation: current)
        }
        logger.debug("connexion…")
    }

    private func handle(_ event: RealtimeSocketEvent, generation: Int) {
        guard generation == self.generation, socket != nil else { return }
        switch event {
        case .opened:
            didOpen()
        case .message(let text):
            didReceive(text)
        case .closed:
            logger.debug("socket tombée")
            scheduleReconnect()
        }
    }

    private func didOpen() {
        guard !opened else { return }
        opened = true
        attempts = 0
        state = .connected
        for topic in subscribers.keys { join(topic) }
        startHeartbeat()
        let joined = subscribers.count
        logger.debug("connecté, \(joined, privacy: .public) topic(s) rejoint(s)")
    }

    private func didReceive(_ text: String) {
        // Toute trame reçue prouve que la connexion vit : le battement en attente est acquitté.
        pendingHeartbeat = nil
        guard let frame = PhoenixProtocol.parse(text) else { return }
        switch frame {
        case let .reply(topic, status, ref):
            onReply(topic: topic, status: status, ref: ref)
        case let .closed(topic, _, ref):
            onChannelClosed(topic: topic, ref: ref)
        default:
            break
        }
        dispatch(frame)
    }

    private func dispatch(_ frame: RealtimeFrame) {
        guard let handlers = subscribers[frame.topic]?.values else { return }
        // Copie : un abonné peut se désabonner pendant la distribution.
        for handler in Array(handlers) { handler(frame) }
    }

    /// Réponse au join courant d'un topic : `ok` remet le délai de rejoin à zéro et annonce notre présence, un
    /// refus replanifie le join.
    private func onReply(topic: String, status: String, ref: String?) {
        guard topic != PhoenixProtocol.heartbeatTopic, let ref, joinRefs[topic] == ref else { return }
        guard status == "ok" else {
            rejoinLater(topic)
            return
        }
        rejoinAttempts[topic] = nil
        if let key = presenceKeys[topic], let socket {
            socket.send(PhoenixProtocol.trackFrame(topic: topic, userId: key, ref: nextRef()))
        }
    }

    /// Le canal est tombé côté serveur : on le rejoint sans rouvrir la socket — sauf `phx_close` périmé.
    private func onChannelClosed(topic: String, ref: String?) {
        if let ref, joinRefs[topic] != ref { return }
        rejoinLater(topic)
    }

    /// Rejoint `topic` après un délai croissant, s'il est toujours écouté sur la même socket.
    private func rejoinLater(_ topic: String) {
        guard socket != nil, subscribers[topic] != nil else { return }
        let attempt = rejoinAttempts[topic, default: 0]
        rejoinAttempts[topic] = attempt + 1
        let wait = Self.nanoseconds(timing.backoff(attempt: attempt))
        let current = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard let self, self.generation == current, self.opened, self.subscribers[topic] != nil else { return }
            self.join(topic)
        }
    }

    /// Envoie un `phx_join` et mémorise sa référence : c'est elle qui identifie le canal courant du topic.
    private func join(_ topic: String) {
        guard let socket else { return }
        let ref = nextRef()
        joinRefs[topic] = ref
        socket.send(PhoenixProtocol.joinFrame(topic: topic, ref: ref, accessToken: anonKey, presenceKey: presenceKeys[topic] ?? ""))
    }

    /// Ferme la socket s'il ne reste aucun abonné.
    private func disconnectIfIdle() {
        guard subscribers.isEmpty else { return }
        let closing = socket
        resetConnection()
        closing?.close()
        logger.debug("déconnecté")
    }

    /// Plus de socket ni de minuterie (arrière-plan, plus aucun abonné).
    private func resetConnection() {
        generation += 1
        socket = nil
        opened = false
        attempts = 0
        pendingHeartbeat = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        joinRefs.removeAll()
        rejoinAttempts.removeAll()
        state = .disconnected
    }

    /// La socket courante est tombée (échec, fermeture serveur, battement sans réponse) : nouvelle tentative
    /// après un délai croissant, tant qu'il reste des abonnés et que l'app est au premier plan.
    private func scheduleReconnect() {
        generation += 1
        socket = nil
        opened = false
        pendingHeartbeat = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        joinRefs.removeAll()
        guard !subscribers.isEmpty, active else {
            state = .disconnected
            return
        }
        state = .connecting
        guard reconnectTask == nil else { return }
        let wait = Self.nanoseconds(timing.backoff(attempt: attempts))
        attempts += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard let self, !Task.isCancelled else { return }
            // La tâche se retire AVANT de rouvrir : si la nouvelle socket tombe aussitôt (hors ligne), la
            // tentative suivante doit pouvoir être planifiée.
            self.reconnectTask = nil
            if !self.subscribers.isEmpty { self.connect() }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        let current = generation
        let interval = Self.nanoseconds(timing.heartbeat)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                if !self.beat() { return }
            }
        }
    }

    /// Un battement ; faux si le précédent est resté sans réponse : la connexion est à moitié morte (TCP mettrait
    /// de longues minutes à s'en apercevoir), la socket est rouverte.
    private func beat() -> Bool {
        guard let socket else { return false }
        if pendingHeartbeat != nil {
            logger.debug("battement sans réponse, réouverture")
            scheduleReconnect()
            socket.close()
            return false
        }
        let ref = nextRef()
        pendingHeartbeat = ref
        socket.send(PhoenixProtocol.heartbeatFrame(ref: ref))
        return true
    }

    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    private nonisolated static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(seconds, 0) * 1_000_000_000)
    }
}

/// Présence accumulée par `conversationUpdates` (une boîte : l'état change d'une trame à l'autre).
private final class PresenceTracker {
    var presence = RealtimePresence()
}

// MARK: - Transport de production

/// Une `URLSessionWebSocketTask` par connexion, sur une session sans cookies ni cache (la clé anon voyage
/// dans l'URL, jamais de jeton Bearer).
final class URLSessionRealtimeTransport: RealtimeTransport {
    private let session: URLSession

    init(session: URLSession = URLSessionRealtimeTransport.makeSession()) {
        self.session = session
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    func open(url: URL, onEvent: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void) -> any RealtimeSocket {
        let socket = URLSessionRealtimeSocket(task: session.webSocketTask(with: url), onEvent: onEvent)
        socket.start()
        return socket
    }
}

/// Socket de production. L'ouverture est connue par le délégué de la tâche (et, en secours, par le premier
/// « pong ») ; la réception s'enchaîne sur la file de la session et chaque texte est remis au MainActor ; une
/// fermeture volontaire coupe tout événement suivant.
final class URLSessionRealtimeSocket: RealtimeSocket {
    private let task: URLSessionWebSocketTask
    private let onEvent: @MainActor @Sendable (RealtimeSocketEvent) -> Void
    private var didSignalOpen = false
    private var finished = false

    init(task: URLSessionWebSocketTask, onEvent: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void) {
        self.task = task
        self.onEvent = onEvent
    }

    func start() {
        let relay: @MainActor @Sendable (RealtimeSocketEvent) -> Void = { [weak self] event in
            self?.deliver(event)
        }
        task.delegate = RealtimeSocketDelegate(relay: relay)
        task.resume()
        task.sendPing { error in
            guard error == nil else { return }
            Task { @MainActor in relay(.opened) }
        }
        URLSessionRealtimeSocket.receiveNext(task, relay: relay)
    }

    func send(_ text: String) {
        guard !finished else { return }
        // Un échec d'envoi n'est pas traité ici : la réception le verra (fermeture) et le client se reconnectera.
        task.send(.string(text)) { _ in }
    }

    func close() {
        guard !finished else { return }
        finished = true
        task.cancel(with: .normalClosure, reason: nil)
    }

    private func deliver(_ event: RealtimeSocketEvent) {
        guard !finished else { return }
        switch event {
        case .opened:
            guard !didSignalOpen else { return }
            didSignalOpen = true
        case .closed:
            finished = true
        case .message:
            break
        }
        onEvent(event)
    }

    /// Réception en chaîne : chaque message relance la suivante ; une erreur (fermeture, réseau) clôt la socket.
    private nonisolated static func receiveNext(
        _ task: URLSessionWebSocketTask,
        relay: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void
    ) {
        task.receive { result in
            switch result {
            case .success(let message):
                if let text = URLSessionRealtimeSocket.text(of: message) {
                    Task { @MainActor in relay(.message(text)) }
                }
                URLSessionRealtimeSocket.receiveNext(task, relay: relay)
            case .failure:
                Task { @MainActor in relay(.closed) }
            }
        }
    }

    private nonisolated static func text(of message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8)
        @unknown default:
            return nil
        }
    }
}

/// Délégué de la tâche WebSocket : appelé sur la file de la session, il remet chaque événement au MainActor.
nonisolated final class RealtimeSocketDelegate: NSObject, URLSessionWebSocketDelegate, Sendable {
    private let relay: @MainActor @Sendable (RealtimeSocketEvent) -> Void

    init(relay: @escaping @MainActor @Sendable (RealtimeSocketEvent) -> Void) {
        self.relay = relay
        super.init()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol selectedProtocol: String?) {
        let relay = self.relay
        Task { @MainActor in relay(.opened) }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let relay = self.relay
        Task { @MainActor in relay(.closed) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let relay = self.relay
        Task { @MainActor in relay(.closed) }
    }
}
