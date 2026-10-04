import Combine
import Foundation

// État du fil de discussion et logique pure qui l'accompagne — portage de `ChatUiState` / `OfferDialogState`
// (ChatViewModel.kt). Données `nonisolated` : l'écran les reçoit telles quelles, les tests les lisent.

// MARK: - Saisie d'une offre

/// Saisie d'un montant : nouvelle offre (fil ou fiche) ou contre-offre — `OfferDialogState` (Android). Le montant est un
/// entier de dinars, borné comme côté serveur (`offerAmount`, Zod).
nonisolated struct OfferDialogState: Equatable, Sendable {
    var action: OfferAction
    /// Chiffres latins seulement (`sanitize`) : un clavier arabe écrit « ١٢٣ », le serveur attend « 123 ».
    var amount: String = ""
    /// Montant de l'offre à laquelle on répond (contre-offre).
    var currentOffer: Double? = nil
    var askingPrice: Double? = nil

    /// Borne serveur (`offerAmount` de src/lib/validations.ts) : 1 à 9 999 999 999 dinars.
    static let maxAmount: Int = 9_999_999_999
    /// Chiffres gardés à la saisie (`take(10)` d'Android).
    static let maxDigits: Int = 10

    var parsedAmount: Int? { OfferDialogState.parse(amount) }

    var isValid: Bool { parsedAmount != nil }

    /// Montant envoyable, ou nil (vide, zéro, au-delà de la borne).
    static func parse(_ text: String) -> Int? {
        let digits = Validators.asciiDigits(text)
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        guard value >= 1, value <= maxAmount else { return nil }
        return value
    }

    /// Saisie nettoyée : chiffres latins, 10 au plus (« 1 900 000 » → « 1900000 »).
    static func sanitize(_ text: String) -> String {
        String(Validators.asciiDigits(text).prefix(maxDigits))
    }
}

// MARK: - État du fil

/// État du fil — `ChatUiState` (Android). Les messages d'erreur sont déjà traduits (`ErrorMapper`).
nonisolated struct ChatState: Equatable, Sendable {
    /// Longueur maximale d'un message (`messageSchema` du serveur, en unités UTF-16 comme Zod).
    static let messageMax: Int = 2000

    var isLoading: Bool = true
    var isLoadingOlder: Bool = false
    var hasMore: Bool = false
    var conversation: Conversation? = nil
    /// Ordre chronologique croissant (le plus ancien en tête).
    var messages: [ChatMessage] = []
    var userId: String = ""
    var draft: String = ""
    var isSending: Bool = false
    var isArchived: Bool = false
    /// J'ai bloqué l'interlocuteur (lu sur `GET /api/conversations/{id}`, puis suivi localement).
    var isBlocked: Bool = false
    var isBlockBusy: Bool = false
    /// Confirmation « Bloquer cet utilisateur » affichée (bloquer coupe la conversation ; débloquer est sans risque).
    var isBlockConfirmPending: Bool = false
    /// L'interlocuteur écrit (broadcast `typing` de son client, effacé après 3 s sans nouvelle).
    var isPartnerTyping: Bool = false
    /// L'interlocuteur a ce fil ouvert (présence du canal, comme le point vert du site).
    var isPartnerOnline: Bool = false
    var isReportBusy: Bool = false
    /// Panne réseau pendant un signalement : affichée DANS la feuille, restée ouverte.
    var reportError: String? = nil
    /// Message dont la suppression attend confirmation.
    var pendingDelete: ChatMessage? = nil
    /// Feuille du montant (offre ou contre-offre) ; nil = fermée.
    var offerDialog: OfferDialogState? = nil
    var isOfferBusy: Bool = false
    /// Panne réseau pendant l'envoi d'une offre : affichée sous le champ, la feuille reste ouverte.
    var offerError: String? = nil
    /// Échec du premier chargement (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    /// Bannière à montrer une fois (archivée + « Annuler », bloqué, signalement envoyé, refus du serveur…), effacée par
    /// `bannerDismissed()`.
    var banner: WeydaBanner? = nil

    /// L'autre partie du fil.
    var partner: ConversationPartner? { conversation?.partner(userId) }

    /// Nom affiché de l'interlocuteur ; compte supprimé → « Compte supprimé ».
    var partnerName: String { TextCheck.nonBlank(partner?.name) ?? L10n.chatDeletedUser }

    /// Le profil public de l'interlocuteur peut s'ouvrir (compte existant).
    var hasPartnerProfile: Bool {
        guard let partner else { return false }
        return !TextCheck.isBlank(partner.id) && !TextCheck.isBlank(partner.name)
    }

    /// Identifiant de l'annonce du fil (fiche à ouvrir).
    var annonceId: String? {
        TextCheck.nonBlank(conversation?.annonce?.id) ?? TextCheck.nonBlank(conversation?.annonceId)
    }

    /// Actions d'offre proposables à l'utilisateur dans l'état courant du fil.
    var offerActions: Set<OfferAction> {
        guard !TextCheck.isBlank(userId) else { return [] }
        return OfferRules.availableActions(userId: userId, messages: messages, annonce: conversation?.annonce)
    }

    /// « Faire une offre » sous le fil : aucune offre ouverte, annonce qui en accepte, conversation non bloquée.
    var canMakeOffer: Bool { !isBlocked && offerActions.contains(.new) }

    func isActionableOffer(_ message: ChatMessage) -> Bool {
        !TextCheck.isBlank(userId) && OfferRules.isActionable(message, by: userId, messages: messages)
    }

    /// Mon dernier message lu par l'autre partie (une seule mention « Lu » dans le fil, comme Android).
    var lastReadOwnMessageId: String? {
        messages.last(where: { $0.isMine(userId) && $0.readAt != nil })?.id
    }

    var canSend: Bool { !TextCheck.isBlank(draft) && !isSending }
}

// MARK: - Lignes du fil

/// Une bulle (ou une carte d'offre) prête à afficher.
nonisolated struct ChatTimelineRow: Equatable, Sendable, Identifiable {
    let message: ChatMessage
    let isMine: Bool
    /// Premier d'une suite de messages du même auteur : plus d'air au-dessus.
    let startsGroup: Bool
    /// Dernier d'une suite : la bulle porte son coin rentré, côté auteur.
    let endsGroup: Bool
    /// « Lu » sous mon dernier message lu.
    let showsReadReceipt: Bool
    /// L'offre OUVERTE du fil (`OfferRules.openOffer` : la dernière offre, si elle est NEW ou COUNTER). Une offre plus
    /// ancienne est dépassée, même si son type reste NEW ou COUNTER.
    let isOpenOffer: Bool
    /// Offre ouverte de l'AUTRE partie, la seule qui porte des boutons de réponse.
    let isActionableOffer: Bool
    /// Supprimable maintenant (mon message, fenêtre de 5 minutes du serveur).
    let canDelete: Bool

    var id: String { message.id }

    /// « En attente de réponse… » : seulement sur MON offre encore ouverte — `showWaiting = isLatest && isPending && isMine`
    /// du fil du site (ChatInterface.tsx) ; une offre dépassée n'affiche plus d'attente.
    var showsWaitingForReply: Bool { isMine && isOpenOffer && !message.isDeleted }
}

/// Élément affiché du fil : séparateur de jour ou message. Identifiants stables : `chat.day.<AAAA-MM-JJ>` pour un jour,
/// l'id du message sinon (le défilement et la pagination s'appuient sur les messages).
nonisolated enum ChatTimelineItem: Equatable, Sendable, Identifiable {
    case day(ChatDay)
    case message(ChatTimelineRow)

    var id: String {
        switch self {
        case .day(let day): day.id
        case .message(let row): row.id
        }
    }
}

/// Mise en lignes du fil (logique pure, testée).
nonisolated enum ChatTimeline {
    /// Lignes précédées d'un séparateur à chaque nouveau jour civil (un message sans date reste avec le jour en cours ;
    /// un message daté dans le futur est rangé sous AUJOURD'HUI, voir `ChatDayGrouping.day`).
    static func items(
        rows: [ChatTimelineRow],
        calendar: Calendar = ChatDayGrouping.deviceCalendar(),
        now: Date = Date()
    ) -> [ChatTimelineItem] {
        var items: [ChatTimelineItem] = []
        items.reserveCapacity(rows.count + 4)
        var currentKey: String? = nil
        for row in rows {
            if let date = row.message.createdAt {
                let current = ChatDayGrouping.day(of: date, calendar: calendar, now: now)
                if current.key != currentKey {
                    items.append(.day(current))
                    currentKey = current.key
                }
            }
            items.append(.message(row))
        }
        return items
    }

    static func rows(
        messages: [ChatMessage],
        userId: String,
        now: Date,
        calendar: Calendar = ChatDayGrouping.deviceCalendar()
    ) -> [ChatTimelineRow] {
        let readId: String? = messages.last(where: { $0.isMine(userId) && $0.readAt != nil })?.id
        let openOfferId: String? = OfferRules.openOffer(messages)?.id
        let hasUser = !TextCheck.isBlank(userId)
        var rows: [ChatTimelineRow] = []
        rows.reserveCapacity(messages.count)
        for index in messages.indices {
            let message = messages[index]
            let previous: ChatMessage? = index > messages.startIndex ? messages[index - 1] : nil
            let next: ChatMessage? = index + 1 < messages.endIndex ? messages[index + 1] : nil
            let isMine = message.isMine(userId)
            // `openOffer` ne renvoie que la DERNIÈRE offre, et seulement si elle est NEW ou COUNTER.
            let isOpenOffer = openOfferId != nil && message.id == openOfferId
            let actionable = hasUser && isOpenOffer && message.senderId != userId
            rows.append(
                ChatTimelineRow(
                    message: message,
                    isMine: isMine,
                    startsGroup: !continues(previous, message, calendar: calendar, now: now),
                    endsGroup: !continues(message, next, calendar: calendar, now: now),
                    showsReadReceipt: isMine && message.id == readId,
                    isOpenOffer: isOpenOffer,
                    isActionableOffer: actionable,
                    canDelete: message.isDeletableBy(userId, now: now)
                )
            )
        }
        return rows
    }

    /// Deux messages texte consécutifs du même auteur, le même jour, forment une suite ; une carte d'offre est toujours
    /// à part, et un séparateur de jour coupe la suite.
    private static func continues(_ first: ChatMessage?, _ second: ChatMessage?, calendar: Calendar, now: Date) -> Bool {
        guard let first, let second else { return false }
        guard first.senderId == second.senderId, first.type == .text, second.type == .text else { return false }
        guard let firstDate = first.createdAt, let secondDate = second.createdAt else { return true }
        let firstKey = ChatDayGrouping.day(of: firstDate, calendar: calendar, now: now).key
        return firstKey == ChatDayGrouping.day(of: secondDate, calendar: calendar, now: now).key
    }
}

// MARK: - Jours du fil

/// Un jour civil du fil (séparateur « Aujourd'hui », « Hier », « 28 sept. 2026 »).
nonisolated struct ChatDay: Hashable, Sendable, Identifiable {
    /// Clé stable du jour dans le calendrier utilisé (« 2026-10-04 »).
    let key: String
    /// Minuit du jour, dans le fuseau du calendrier.
    let start: Date

    /// Identifiant de la ligne du séparateur (jamais égal à un id de message).
    var id: String { "chat.day.\(key)" }
}

/// Messages d'un même jour civil, dans l'ordre du fil ; `day` nil = messages sans date en tête de fil.
nonisolated struct ChatDayGroup: Equatable, Sendable {
    let day: ChatDay?
    var messages: [ChatMessage]
}

/// Regroupement des messages par jour civil (logique pure, testée) et libellé du séparateur.
nonisolated enum ChatDayGrouping {
    /// Calendrier grégorien dans le fuseau de l'appareil (comme `Format`) ; les tests injectent le leur.
    static func deviceCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Jour civil d'un instant dans `calendar` (minuit pile appartient au nouveau jour), BORNÉ au jour courant : un fil
    /// n'affiche jamais « Demain ». Un message daté dans le futur (horloge du téléphone en retard sur celle du serveur,
    /// données simulées) est rangé et libellé comme aujourd'hui ; la clé est celle du jour borné. L'ordre des messages
    /// (chronologique) n'est pas touché.
    static func day(of date: Date, calendar: Calendar, now: Date = Date()) -> ChatDay {
        let bounded: Date = date > now ? now : date
        let parts = calendar.dateComponents([.year, .month, .day], from: bounded)
        let key = padded(parts.year ?? 0, width: 4) + "-" + padded(parts.month ?? 0, width: 2) + "-" + padded(parts.day ?? 0, width: 2)
        return ChatDay(key: key, start: calendar.startOfDay(for: bounded))
    }

    /// Messages consécutifs regroupés par jour civil, dans l'ordre du fil (ordre chronologique croissant). Un message
    /// sans date reste avec le jour en cours.
    static func groups(
        _ messages: [ChatMessage],
        calendar: Calendar = ChatDayGrouping.deviceCalendar(),
        now: Date = Date()
    ) -> [ChatDayGroup] {
        var groups: [ChatDayGroup] = []
        for message in messages {
            guard let date = message.createdAt else {
                if groups.isEmpty {
                    groups.append(ChatDayGroup(day: nil, messages: [message]))
                } else {
                    groups[groups.count - 1].messages.append(message)
                }
                continue
            }
            let current = Self.day(of: date, calendar: calendar, now: now)
            if let last = groups.last, last.day?.key == current.key {
                groups[groups.count - 1].messages.append(message)
            } else {
                groups.append(ChatDayGroup(day: current, messages: [message]))
            }
        }
        return groups
    }

    /// « Aujourd'hui », « Hier », sinon la date moyenne (« 28 sept. 2026 ») : libellés relatifs du SYSTÈME (aucune chaîne
    /// du catalogue), chiffres latins, fuseau du calendrier. `DateFormatter` n'est pas Sendable : un par appel.
    static func label(for day: ChatDay, calendar: Calendar = ChatDayGrouping.deviceCalendar(), locale: Locale = WeydaLocale.formatting) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        // Après la locale : la changer réinitialise le calendrier du formateur.
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        // « Aujourd'hui » plutôt qu'« aujourd'hui » : le libellé est seul dans sa capsule.
        formatter.formattingContext = .beginningOfSentence
        return Format.latinDigits(formatter.string(from: day.start))
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
    }
}

// MARK: - Sens d'écriture d'un message

/// Sens de lecture d'un texte saisi par un utilisateur — le `dir="auto"` du site : la première lettre « forte »
/// décide (un message en français dans l'app en arabe reste lu de gauche à droite, et inversement).
nonisolated enum ChatTextDirection {
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if isRightToLeftLetter(value) { return true }
            if scalar.properties.isAlphabetic { return false }
        }
        return false
    }

    /// Hébreu, arabe, syriaque, thâna, n'ko, arabe étendu et formes de présentation.
    private static func isRightToLeftLetter(_ value: UInt32) -> Bool {
        (0x0590...0x08FF).contains(value) || (0xFB1D...0xFDFF).contains(value) || (0xFE70...0xFEFF).contains(value)
    }
}

// MARK: - Rythmes

/// Délais du fil, ceux d'Android (`TYPING_*`, `RESYNC_DEBOUNCE_MS`).
nonisolated enum ChatTiming {
    /// « Écrit… » envoyé au plus toutes les 2 s pendant la frappe.
    static let typingThrottle: TimeInterval = 2
    /// Arrêt (« stopped_typing ») après 3 s sans frappe.
    static let typingIdleNanoseconds: UInt64 = 3_000_000_000
    /// Sans « stopped_typing » (onglet fermé, réseau coupé), l'indicateur de l'autre s'éteint seul après 3 s.
    static let typingTimeoutNanoseconds: UInt64 = 3_000_000_000
    /// Plusieurs messages en rafale = une seule relecture du fil.
    static let resyncDebounceNanoseconds: UInt64 = 600_000_000
}

// MARK: - Temps réel

/// Branchement du fil sur le temps réel, par closures : les tests n'ouvrent aucune socket, l'app passe
/// `ChatRealtime.live(container.realtime)`.
struct ChatRealtime {
    /// Faux sans configuration Supabase (et en API simulée) : le fil reste correct en HTTP seul.
    var isEnabled: Bool
    /// Événements ET présence du fil, sur un seul abonnement (notre id sert de clé de présence).
    var updates: @MainActor (_ topic: String, _ conversationId: String, _ presenceKey: String?) -> AsyncStream<ConversationRealtimeUpdate>
    /// « Écrit… » / « a cessé d'écrire » (broadcast éphémère).
    var sendTyping: @MainActor (_ topic: String, _ userId: String, _ isTyping: Bool) -> Void
    /// Passage à `.connected` APRÈS une coupure : un broadcast n'est jamais rejoué, le fil relit sa dernière page.
    var reconnections: AnyPublisher<Void, Never>

    /// Client de l'app : une seule WebSocket pour tous les fils et le canal personnel.
    static func live(_ client: RealtimeClient) -> ChatRealtime {
        ChatRealtime(
            isEnabled: client.isEnabled,
            updates: { topic, conversationId, presenceKey in
                client.conversationUpdates(topic: topic, conversationId: conversationId, presenceKey: presenceKey)
            },
            sendTyping: { topic, userId, isTyping in
                client.sendTyping(topic: topic, userId: userId, isTyping: isTyping)
            },
            // Comme Android : `state.map { it == CONNECTED }.distinctUntilChanged().filter { it }.drop(1)` — la valeur
            // courante est émise d'abord ; la première connexion n'est pas une reconnexion.
            reconnections: client.$state
                .map { (state: RealtimeClient.State) -> Bool in state == .connected }
                .removeDuplicates()
                .filter { (connected: Bool) -> Bool in connected }
                .dropFirst()
                .map { (_: Bool) -> Void in () }
                .eraseToAnyPublisher()
        )
    }

    /// Sans temps réel (tests, aperçus).
    static var inert: ChatRealtime {
        ChatRealtime(
            isEnabled: false,
            updates: { _, _, _ in
                AsyncStream(ConversationRealtimeUpdate.self) { continuation in
                    continuation.finish()
                }
            },
            sendTyping: { _, _, _ in },
            reconnections: Empty<Void, Never>().eraseToAnyPublisher()
        )
    }
}
