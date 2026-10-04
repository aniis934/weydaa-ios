import Combine
import Foundation

/// Fil d'une conversation — portage de `ChatViewModel` (Android) : chargement (`GET /api/conversations/{id}`, qui marque
/// aussi les messages reçus comme lus), pagination vers le passé par curseur, envoi, suppression dans les 5 minutes,
/// offres (`POST …/offers`), archivage, blocage, signalement de l'interlocuteur, temps réel (messages, suppressions,
/// accusés de lecture, « écrit… », présence).
///
/// Chaque action qui lance du travail renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
/// `mergeMessages` est la fusion de la pagination, de l'envoi et du temps réel : dédoublonnage par id, la version la plus
/// récente gagne, ordre chronologique.
///
/// Écarts iOS assumés : le temps réel ne tourne que pendant que l'écran est affiché (`appear` / `disappear`) — au retour,
/// la dernière page est relue (Android : abonnement tant que le ViewModel vit, relecture si un message est arrivé hors
/// écran) ; le brouillon vit dans le ViewModel (iOS ne tue pas l'app pendant un appel comme Android peut le faire) ;
/// la feuille d'offre reste ouverte pendant l'envoi et montre une panne réseau sous le champ (Android : boîte fermée tout
/// de suite, échec en Snackbar) ; un verdict du serveur la ferme, l'annonce et relit le fil.
final class ChatViewModel: ObservableObject {
    @Published private(set) var state: ChatState
    /// Feuille « Signaler » (liée à la présentation : un glissement vers le bas la ferme aussi).
    @Published var isReportPresented: Bool = false
    /// Message parti (réponse du serveur reçue) : retour haptique branché par `ChatView` ; nil dans les tests.
    var onMessageSent: (() -> Void)?
    /// Offre envoyée, contre-offre, acceptation ou refus aboutis (action en paramètre) : retour haptique de `ChatView`.
    var onOfferSent: ((OfferAction) -> Void)?

    let conversationId: String

    private let conversations: ConversationsRepository
    private let notifications: NotificationsRepository?
    private let reports: ReportsRepository?
    private let realtime: ChatRealtime
    private let now: () -> Date

    /// Curseur de la page précédente (id du plus ancien message reçu) ; nil = début du fil atteint.
    private var nextCursor: String?
    /// Topic signé du fil (`conv:{id}:{hmac}`), pour nos broadcasts « écrit… » ; vide tant que le fil n'est pas chargé.
    private var topic: String = ""
    private var hasStarted = false
    private var isVisible = false
    /// Un message de l'autre partie est arrivé en direct et n'a pas encore été marqué lu côté serveur.
    private var hasUnseenIncoming = false
    private var lastTypingSentAt: Date?
    private var loadTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var reconnectSubscription: AnyCancellable?
    private var resyncTask: Task<Void, Never>?
    private var stoppedTypingTask: Task<Void, Never>?
    private var typingResetTask: Task<Void, Never>?

    init(
        conversationId: String,
        archived: Bool,
        userId: String,
        conversations: ConversationsRepository,
        notifications: NotificationsRepository? = nil,
        reports: ReportsRepository? = nil,
        realtime: ChatRealtime = .inert,
        now: @escaping () -> Date = { Date() }
    ) {
        self.conversationId = conversationId
        self.conversations = conversations
        self.notifications = notifications
        self.reports = reports
        self.realtime = realtime
        self.now = now
        var initial = ChatState()
        initial.userId = userId
        initial.isArchived = archived
        self.state = initial
    }

    // MARK: - Fusion

    /// Fusionne deux listes de messages : dédoublonnage par id (la version entrante gagne : accusé de lecture,
    /// suppression), puis ordre chronologique (date absente en dernier, id en départage) — `mergeMessages` (Android).
    nonisolated static func mergeMessages(_ current: [ChatMessage], _ incoming: [ChatMessage]) -> [ChatMessage] {
        guard !incoming.isEmpty else { return current }
        var byId: [String: ChatMessage] = [:]
        byId.reserveCapacity(current.count + incoming.count)
        for message in current {
            byId[message.id] = message
        }
        for message in incoming {
            byId[message.id] = message
        }
        return byId.values.sorted { (lhs: ChatMessage, rhs: ChatMessage) -> Bool in
            let left = lhs.createdAt ?? Date.distantFuture
            let right = rhs.createdAt ?? Date.distantFuture
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Cycle de vie de l'écran

    /// L'écran s'affiche : fil marqué « visible » (un push de ce fil n'est pas notifié), premier chargement, puis à
    /// chaque retour : temps réel rebranché et dernière page relue (ce qui est arrivé hors écran est marqué lu).
    @discardableResult
    func appear() -> Task<Void, Never>? {
        isVisible = true
        conversations.visibleConversationId = conversationId
        guard hasStarted else {
            hasStarted = true
            return load()
        }
        startRealtime()
        if state.conversation != nil {
            resync()
        }
        return nil
    }

    /// L'écran disparaît (autre écran poussé, retour, onglet changé) : « écrit… » arrêté, temps réel coupé.
    func disappear() {
        isVisible = false
        if conversations.visibleConversationId == conversationId {
            conversations.visibleConversationId = nil
        }
        signalTyping(false)
        stopRealtime()
        resyncTask?.cancel()
        resyncTask = nil
    }

    // MARK: - Chargement

    @discardableResult
    func load() -> Task<Void, Never>? {
        loadTask?.cancel()
        mutate { s in
            s.isLoading = true
            s.errorMessage = nil
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        return task
    }

    private func performLoad() async {
        do {
            let thread = try await conversations.thread(id: conversationId)
            guard !Task.isCancelled else { return }
            nextCursor = thread.nextCursor
            topic = thread.conversation.topic
            mutate { s in
                s.isLoading = false
                s.conversation = thread.conversation
                s.messages = ChatViewModel.mergeMessages([], thread.messages)
                s.hasMore = thread.hasMore
                s.isBlocked = thread.isBlockedByMe
            }
            startRealtime()
            await refreshBadges()
        } catch {
            // Annulation (nouveau chargement lancé) : rien à afficher, le suivant s'en charge.
            guard let message = ErrorMapper.message(for: error) else { return }
            mutate { s in
                s.isLoading = false
                s.errorMessage = message
            }
        }
    }

    /// Le `GET` du fil vient de marquer des messages lus : pastille de l'onglet relue, et notifications MESSAGE de ce
    /// fil, que le serveur (lot B) marque lues en même temps (cloche).
    private func refreshBadges() async {
        let userId = state.userId
        guard !TextCheck.isBlank(userId) else { return }
        _ = try? await conversations.refreshUnread(userId: userId)
        if let notifications {
            _ = try? await notifications.page(page: 1)
        }
    }

    /// Page précédente (messages plus anciens) ; le curseur est l'id du plus ancien message reçu.
    @discardableResult
    func loadOlder() -> Task<Void, Never>? {
        guard let cursor = nextCursor else { return nil }
        guard !state.isLoading, !state.isLoadingOlder else { return nil }
        mutate { $0.isLoadingOlder = true }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                let thread = try await self.conversations.thread(id: self.conversationId, cursor: cursor)
                self.nextCursor = thread.nextCursor
                self.mutate { s in
                    s.isLoadingOlder = false
                    s.messages = ChatViewModel.mergeMessages(s.messages, thread.messages)
                    s.hasMore = thread.hasMore
                }
            } catch {
                let message = ErrorMapper.message(for: error)
                self.mutate { s in
                    s.isLoadingOlder = false
                    if let message {
                        s.notice = message
                    }
                }
            }
        }
        return task
    }

    // MARK: - Saisie et envoi

    /// Texte du composeur (coupé à 2000 unités UTF-16 comme le serveur) ; signale « écrit… » à l'interlocuteur.
    func updateDraft(_ value: String) {
        let capped = RepositorySupport.truncatedUTF16(value, max: ChatState.messageMax)
        guard capped != state.draft else { return }
        mutate { $0.draft = capped }
        signalTyping(!TextCheck.isBlank(capped))
    }

    /// « Est en train d'écrire » pour l'interlocuteur, comme le fil du site : `typing` au plus toutes les 2 s pendant la
    /// frappe, `stopped_typing` après 3 s sans frappe, à l'envoi ou quand le champ se vide.
    private func signalTyping(_ typing: Bool) {
        guard realtime.isEnabled, !TextCheck.isBlank(topic), !TextCheck.isBlank(state.userId) else { return }
        stoppedTypingTask?.cancel()
        stoppedTypingTask = nil
        guard typing else {
            if lastTypingSentAt != nil {
                realtime.sendTyping(topic, state.userId, false)
            }
            lastTypingSentAt = nil
            return
        }
        let current = now()
        let throttled: Bool
        if let last = lastTypingSentAt {
            throttled = current.timeIntervalSince(last) <= ChatTiming.typingThrottle
        } else {
            throttled = false
        }
        if !throttled {
            realtime.sendTyping(topic, state.userId, true)
            lastTypingSentAt = current
        }
        stoppedTypingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: ChatTiming.typingIdleNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.signalTyping(false)
        }
    }

    @discardableResult
    func send() -> Task<Void, Never>? {
        let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !state.isSending else { return nil }
        signalTyping(false)
        mutate { $0.isSending = true }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await self.conversations.send(conversationId: self.conversationId, content: text)
                // Le champ reste éditable pendant l'envoi : on ne vide que le texte parti, pas la suite déjà tapée
                // sur un réseau lent.
                self.mutate { s in
                    s.isSending = false
                    if s.draft.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                        s.draft = ""
                    }
                    s.messages = ChatViewModel.mergeMessages(s.messages, [message])
                }
                self.onMessageSent?()
            } catch {
                let message = ErrorMapper.message(for: error)
                self.mutate { s in
                    s.isSending = false
                    if let message {
                        s.notice = message
                    }
                }
            }
        }
        return task
    }

    // MARK: - Suppression

    /// Appui long « Supprimer » : hors de la fenêtre de 5 minutes, un message local suffit (aucun appel réseau).
    func askDelete(_ message: ChatMessage) {
        guard message.isDeletableBy(state.userId, now: now()) else {
            mutate { $0.notice = L10n.chatDeletionWindowExpired }
            return
        }
        mutate { $0.pendingDelete = message }
    }

    func dismissDelete() {
        guard state.pendingDelete != nil else { return }
        mutate { $0.pendingDelete = nil }
    }

    @discardableResult
    func confirmDelete() -> Task<Void, Never>? {
        guard let message = state.pendingDelete else { return nil }
        mutate { $0.pendingDelete = nil }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.conversations.deleteMessage(conversationId: self.conversationId, messageId: message.id)
                var deleted = message
                deleted.content = ""
                deleted.deletedAt = self.now()
                self.mutate { s in
                    s.messages = ChatViewModel.mergeMessages(s.messages, [deleted])
                }
            } catch {
                if let text = ErrorMapper.message(for: error) {
                    self.mutate { $0.notice = text }
                }
            }
        }
        return task
    }

    // MARK: - Offres

    /// Feuille du montant : nouvelle offre ou contre-offre (le montant ouvert et le prix demandé sont rappelés).
    func openOfferDialog(_ action: OfferAction) {
        guard action.needsAmount else { return }
        let open: Double? = OfferRules.openOffer(state.messages)?.offer?.amount
        mutate { s in
            s.offerError = nil
            s.offerDialog = OfferDialogState(
                action: action,
                currentOffer: action == .counter ? open : nil,
                askingPrice: s.conversation?.annonce?.price
            )
        }
    }

    func updateOfferAmount(_ value: String) {
        guard var dialog = state.offerDialog else { return }
        let clean = OfferDialogState.sanitize(value)
        guard clean != dialog.amount || state.offerError != nil else { return }
        dialog.amount = clean
        mutate { s in
            s.offerDialog = dialog
            s.offerError = nil
        }
    }

    func dismissOfferDialog() {
        guard state.offerDialog != nil, !state.isOfferBusy else { return }
        mutate { s in
            s.offerDialog = nil
            s.offerError = nil
        }
    }

    @discardableResult
    func confirmOfferDialog() -> Task<Void, Never>? {
        guard let dialog = state.offerDialog, let amount = dialog.parsedAmount else { return nil }
        return submitOffer(dialog.action, amount: amount, fromDialog: true)
    }

    /// Accepter / refuser : pas de saisie, le montant est celui de l'offre ouverte.
    @discardableResult
    func respondToOffer(_ action: OfferAction) -> Task<Void, Never>? {
        guard !action.needsAmount else { return nil }
        return submitOffer(action, amount: nil, fromDialog: false)
    }

    private func submitOffer(_ action: OfferAction, amount: Int?, fromDialog: Bool) -> Task<Void, Never>? {
        guard !state.isOfferBusy else { return nil }
        mutate { s in
            s.isOfferBusy = true
            s.offerError = nil
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await self.conversations.offerAction(
                    conversationId: self.conversationId,
                    action: action,
                    amount: amount
                )
                self.mutate { s in
                    s.isOfferBusy = false
                    s.messages = ChatViewModel.mergeMessages(s.messages, [message])
                    if fromDialog {
                        s.offerDialog = nil
                    }
                }
                self.onOfferSent?(action)
            } catch {
                self.offerFailed(error, fromDialog: fromDialog)
            }
        }
        return task
    }

    /// Panne réseau : la feuille reste ouverte, rien n'est perdu. Verdict du serveur (offre déjà ouverte, annonce
    /// vendue…) : la feuille se ferme, le message s'affiche et le fil est relu — il a changé sous nos yeux.
    private func offerFailed(_ error: any Error, fromDialog: Bool) {
        guard let message = ErrorMapper.message(for: error) else {
            mutate { $0.isOfferBusy = false }
            return
        }
        let isVerdict = error is APIError
        mutate { s in
            s.isOfferBusy = false
            if fromDialog && !isVerdict && s.offerDialog != nil {
                s.offerError = message
            } else {
                if fromDialog {
                    s.offerDialog = nil
                }
                s.notice = message
            }
        }
        if isVerdict {
            resync()
        }
    }

    // MARK: - Archivage et blocage

    @discardableResult
    func toggleArchive() -> Task<Void, Never>? {
        let target = !state.isArchived
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.conversations.setArchived(conversationId: self.conversationId, archived: target)
                self.mutate { s in
                    s.isArchived = target
                    s.notice = target ? L10n.chatArchived : L10n.chatUnarchived
                }
                // La liste (Conversations / Archives) se relit.
                self.conversations.notifyTouched()
            } catch {
                if let text = ErrorMapper.message(for: error) {
                    self.mutate { $0.notice = text }
                }
            }
        }
        return task
    }

    /// « Bloquer cet utilisateur » : confirmation d'abord (bloquer coupe la conversation).
    func askBlock() {
        guard !state.isBlocked, state.partner != nil else { return }
        mutate { $0.isBlockConfirmPending = true }
    }

    /// Ferme les confirmations encore ouvertes (blocage, suppression).
    func dismissConfirmations() {
        guard state.isBlockConfirmPending || state.pendingDelete != nil else { return }
        mutate { s in
            s.isBlockConfirmPending = false
            s.pendingDelete = nil
        }
    }

    @discardableResult
    func confirmBlock() -> Task<Void, Never>? {
        guard state.isBlockConfirmPending else { return nil }
        mutate { $0.isBlockConfirmPending = false }
        return setBlocked(true)
    }

    @discardableResult
    func setBlocked(_ blocked: Bool) -> Task<Void, Never>? {
        guard let partnerId = TextCheck.nonBlank(state.partner?.id), !state.isBlockBusy else { return nil }
        mutate { $0.isBlockBusy = true }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.conversations.setBlocked(userId: partnerId, blocked: blocked)
                self.mutate { s in
                    s.isBlockBusy = false
                    s.isBlocked = blocked
                    s.notice = blocked ? L10n.chatBlockedDone : L10n.chatUnblockedDone
                }
                self.conversations.notifyTouched()
            } catch {
                let message = ErrorMapper.message(for: error)
                self.mutate { s in
                    s.isBlockBusy = false
                    if let message {
                        s.notice = message
                    }
                }
            }
        }
        return task
    }

    // MARK: - Signaler l'interlocuteur

    func openReport() {
        guard state.partner != nil, reports != nil else { return }
        mutate { $0.reportError = nil }
        isReportPresented = true
    }

    /// Signalement de l'interlocuteur, avec ce fil pour contexte. Verdict du serveur (envoyé, déjà signalé, refus) :
    /// la feuille se ferme et le message s'affiche. Panne réseau : elle reste ouverte, les précisions sont gardées.
    @discardableResult
    func confirmReport(reason: ReportReason, details: String) -> Task<Void, Never>? {
        guard let partnerId = TextCheck.nonBlank(state.partner?.id), let reports, !state.isReportBusy else { return nil }
        mutate { s in
            s.isReportBusy = true
            s.reportError = nil
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                try await reports.reportUser(
                    userId: partnerId,
                    conversationId: self.conversationId,
                    reason: reason,
                    details: details
                )
                self.mutate { s in
                    s.isReportBusy = false
                    s.notice = L10n.reportSent
                }
                self.isReportPresented = false
            } catch {
                self.reportFailed(error)
            }
        }
        return task
    }

    private func reportFailed(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else {
            mutate { $0.isReportBusy = false }
            return
        }
        if error is APIError {
            mutate { s in
                s.isReportBusy = false
                s.notice = message
            }
            isReportPresented = false
        } else {
            mutate { s in
                s.isReportBusy = false
                s.reportError = message
            }
        }
    }

    // MARK: - Messages brefs

    func noticeShown() {
        guard state.notice != nil else { return }
        mutate { $0.notice = nil }
    }

    // MARK: - Temps réel

    /// Abonnement au topic signé du fil tant que l'écran est affiché : messages et offres arrivent sans rechargement,
    /// la suppression et l'accusé de lecture se propagent, « écrit… » et la présence s'affichent. Le fil reste correct
    /// sans temps réel (connexion impossible, clé absente, API simulée).
    private func startRealtime() {
        guard isVisible, realtimeTask == nil, realtime.isEnabled, let topic = TextCheck.nonBlank(topic) else { return }
        let stream = realtime.updates(topic, conversationId, TextCheck.nonBlank(state.userId))
        realtimeTask = Task { [weak self] in
            for await update in stream {
                guard let self else { return }
                self.apply(update)
            }
        }
        // Un broadcast n'est jamais rejoué : ce qui a été diffusé pendant une coupure (veille, changement de réseau)
        // est perdu. À chaque RE-connexion, la dernière page est relue.
        reconnectSubscription = realtime.reconnections.sink { [weak self] in
            self?.resync()
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        reconnectSubscription?.cancel()
        reconnectSubscription = nil
        typingResetTask?.cancel()
        typingResetTask = nil
        if state.isPartnerTyping || state.isPartnerOnline {
            mutate { s in
                s.isPartnerTyping = false
                s.isPartnerOnline = false
            }
        }
    }

    /// Une trame du fil : événement métier ou présence.
    func apply(_ update: ConversationRealtimeUpdate) {
        switch update {
        case .event(let event):
            applyRealtime(event)
        case .presence(let present):
            let partnerId: String? = TextCheck.nonBlank(state.partner?.id)
            let online = partnerId.map { present.contains($0) } ?? false
            if state.isPartnerOnline != online {
                mutate { $0.isPartnerOnline = online }
            }
        }
    }

    func applyRealtime(_ event: RealtimeEvent) {
        switch event {
        case .messageNew(let message):
            mutate { s in
                s.messages = ChatViewModel.mergeMessages(s.messages, [message])
            }
            if !message.isMine(state.userId) {
                // Lu seulement si l'écran est réellement affiché ; sinon au retour.
                hasUnseenIncoming = true
                if isVisible {
                    resync()
                }
            }
        case .messageDeleted(_, let messageId):
            guard let target = state.messages.first(where: { $0.id == messageId }) else { return }
            var deleted = target
            deleted.content = ""
            deleted.deletedAt = now()
            mutate { s in
                s.messages = ChatViewModel.mergeMessages(s.messages, [deleted])
            }
        case .messagesRead(let readerId, let readAt):
            // L'autre partie a ouvert le fil : tous mes messages en attente passent à « lu ». Mon propre accusé
            // (autre appareil) ne change rien.
            let userId = state.userId
            guard readerId != userId else { return }
            let date = readAt ?? now()
            mutate { s in
                s.messages = s.messages.map { (message: ChatMessage) -> ChatMessage in
                    guard message.isMine(userId), message.readAt == nil else { return message }
                    var read = message
                    read.readAt = date
                    return read
                }
            }
        case .typing(let userId, let isTyping):
            guard userId != state.userId else { return }
            mutate { $0.isPartnerTyping = isTyping }
            typingResetTask?.cancel()
            typingResetTask = nil
            guard isTyping else { return }
            typingResetTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: ChatTiming.typingTimeoutNanoseconds)
                guard !Task.isCancelled, let self else { return }
                self.mutate { $0.isPartnerTyping = false }
            }
        default:
            break
        }
    }

    /// Relit la dernière page sans indicateur. Ce `GET` marque aussi le fil comme lu côté serveur : il tient à jour
    /// l'accusé de lecture de l'autre partie et la pastille de l'onglet quand un message arrive fil affiché.
    private func resync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: ChatTiming.resyncDebounceNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.hasUnseenIncoming = false
            if let thread = try? await self.conversations.thread(id: self.conversationId) {
                guard !Task.isCancelled else { return }
                self.mutate { s in
                    s.messages = ChatViewModel.mergeMessages(s.messages, thread.messages)
                    s.isBlocked = thread.isBlockedByMe
                }
            }
            let userId = self.state.userId
            if !TextCheck.isBlank(userId) {
                _ = try? await self.conversations.refreshUnread(userId: userId)
            }
        }
    }

    // MARK: - Démonstration (captures)

    #if DEBUG
    /// `-WeydaChatDemo typing` (API simulée, sans temps réel) : l'interlocuteur « en ligne » qui écrit.
    func showTypingDemo() {
        guard state.conversation != nil else { return }
        mutate { s in
            s.isPartnerOnline = true
            s.isPartnerTyping = true
        }
    }
    #endif

    // MARK: - Interne

    /// Une seule publication par changement d'état.
    private func mutate(_ transform: (inout ChatState) -> Void) {
        var next = state
        transform(&next)
        state = next
    }
}
