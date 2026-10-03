import SwiftUI
import UIKit

// Briques du fil de discussion : liste des messages (défilement, pages précédentes), bulles, cartes d'offre,
// « écrit… », composeur, encart « bloqué », squelette, portrait. Les noms commencent par « Chat » : aucun ne croise
// ceux de la liste des conversations.

/// Mesures du fil.
nonisolated enum ChatMetrics {
    /// Place laissée libre du côté opposé à l'auteur : une bulle ne prend jamais toute la largeur.
    static let oppositeMargin: CGFloat = 52
    /// Largeur maximale d'une carte d'offre (Android : bulles plafonnées à 300 dp).
    static let offerMaxWidth: CGFloat = 300
    static let offerMinWidth: CGFloat = 220
    /// Pastille de l'icône d'une carte d'offre.
    static let offerIcon: CGFloat = 28
    /// Hauteur visible du raccourci « Faire une offre » (la zone touchable fait 44 pt).
    static let chipHeight: CGFloat = 34
    /// Le compteur de caractères apparaît à 200 caractères de la limite.
    static let counterThreshold: Int = ChatState.messageMax - 200
}

// MARK: - Liste des messages

/// Demande de défilement (une nouvelle demande remplace la précédente).
nonisolated struct ChatScrollRequest: Equatable {
    let serial: Int
    let target: String
    let anchor: UnitPoint
    let animated: Bool
    let delayNanoseconds: UInt64
    /// Second passage du premier placement (hauteurs des bulles hors écran d'abord estimées).
    let isCorrection: Bool
}

/// Repères de défilement qui ne sont pas des messages.
nonisolated enum ChatScrollTarget {
    static let bottom = "chat.scroll.bottom"
    static let typing = "chat.scroll.typing"
}

/// Messages en ordre chronologique dans une `LazyVStack`, un séparateur au début de chaque jour : ouverture en bas du
/// fil, retour en bas à chaque message envoyé (ou reçu si l'on y était déjà — sinon l'utilisateur lisait l'historique et
/// la liste lui était arrachée), pages précédentes chargées en remontant, la position conservée. Le défilement et la
/// pagination suivent les MESSAGES (premier / dernier), jamais les séparateurs : une page plus ancienne du même jour
/// déplace le séparateur sans fausser l'ancre.
struct ChatMessageList: View {
    private let items: [ChatTimelineItem]
    private let partnerName: String
    private let hasMore: Bool
    private let isPartnerTyping: Bool
    private let offerActions: Set<OfferAction>
    private let isOfferBusy: Bool
    private let bottomRequest: Int
    private let onLoadOlder: () -> Void
    private let onDelete: (ChatMessage) -> Void
    private let onRespond: (OfferAction) -> Void
    private let onCounter: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Demande en attente (délai éventuel), puis demande à exécuter : le défilement lui-même se fait dans un
    /// `onChange` synchrone, le seul endroit où le `ScrollViewProxy` est utilisé.
    @State private var scroll: ChatScrollRequest? = nil
    @State private var due: ChatScrollRequest? = nil
    @State private var serial: Int = 0
    /// Le bas du fil est à l'écran (repère de fin réalisé par la pile paresseuse).
    @State private var isAtBottom: Bool = true
    /// Premier placement en bas fait : avant, le haut du fil est brièvement à l'écran et ne doit pas charger le passé.
    @State private var isReady: Bool = false
    @State private var isOlderLoaderVisible: Bool = false
    /// Message du haut au moment de demander la page précédente : la vue y revient une fois la page arrivée.
    @State private var olderAnchor: String? = nil

    /// Attente avant de redescendre quand le clavier s'ouvre (le temps de son animation).
    private static let keyboardDelay: UInt64 = 350_000_000
    /// Second passage du premier placement en bas.
    private static let correctionDelay: UInt64 = 120_000_000

    init(
        items: [ChatTimelineItem],
        partnerName: String,
        hasMore: Bool,
        isPartnerTyping: Bool,
        offerActions: Set<OfferAction>,
        isOfferBusy: Bool,
        bottomRequest: Int,
        onLoadOlder: @escaping () -> Void,
        onDelete: @escaping (ChatMessage) -> Void,
        onRespond: @escaping (OfferAction) -> Void,
        onCounter: @escaping () -> Void
    ) {
        self.items = items
        self.partnerName = partnerName
        self.hasMore = hasMore
        self.isPartnerTyping = isPartnerTyping
        self.offerActions = offerActions
        self.isOfferBusy = isOfferBusy
        self.bottomRequest = bottomRequest
        self.onLoadOlder = onLoadOlder
        self.onDelete = onDelete
        self.onRespond = onRespond
        self.onCounter = onCounter
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if hasMore {
                        olderLoader
                    }
                    ForEach(items) { item in
                        itemView(item)
                            .id(item.id)
                    }
                    if isPartnerTyping {
                        ChatTypingBubble()
                            .padding(.top, WeydaSpace.md)
                            .id(ChatScrollTarget.typing)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(ChatScrollTarget.bottom)
                        .onAppear {
                            isAtBottom = true
                        }
                        .onDisappear {
                            isAtBottom = false
                        }
                }
                .padding(.horizontal, WeydaSpace.md)
                .padding(.bottom, WeydaSpace.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(ChatBottomAnchor())
            .onAppear {
                request(ChatScrollTarget.bottom, anchor: .bottom, animated: false)
            }
            .onChange(of: lastRow?.id) { _ in
                lastRowChanged()
            }
            .onChange(of: firstRowId) { _ in
                firstRowChanged()
            }
            .onChange(of: isPartnerTyping) { typing in
                if typing && isAtBottom {
                    request(ChatScrollTarget.bottom, anchor: .bottom, animated: true)
                }
            }
            .onChange(of: bottomRequest) { _ in
                request(ChatScrollTarget.bottom, anchor: .bottom, animated: true, delay: Self.keyboardDelay)
            }
            .onChange(of: due) { request in
                perform(request, proxy: proxy)
            }
            .task(id: scroll) {
                await release(scroll)
            }
        }
    }

    /// Séparateur de jour ou ligne de message.
    @ViewBuilder
    private func itemView(_ item: ChatTimelineItem) -> some View {
        switch item {
        case .day(let day):
            ChatDaySeparator(title: ChatDayGrouping.label(for: day))
                .padding(.top, WeydaSpace.lg)
                .padding(.bottom, WeydaSpace.xs)
        case .message(let row):
            ChatMessageRow(
                row: row,
                partnerName: partnerName,
                offerActions: offerActions,
                isOfferBusy: isOfferBusy,
                onDelete: onDelete,
                onRespond: onRespond,
                onCounter: onCounter
            )
            .padding(.top, row.startsGroup ? WeydaSpace.md : WeydaSpace.xxs)
        }
    }

    /// Dernier message affiché (les séparateurs ne comptent pas).
    private var lastRow: ChatTimelineRow? {
        for item in items.reversed() {
            if case .message(let row) = item {
                return row
            }
        }
        return nil
    }

    /// Premier message affiché : l'ancre de la page précédente.
    private var firstRowId: String? {
        for item in items {
            if case .message(let row) = item {
                return row.id
            }
        }
        return nil
    }

    /// Haut du fil : indicateur qui demande la page précédente quand il arrive à l'écran.
    private var olderLoader: some View {
        InlineLoader()
            .onAppear {
                isOlderLoaderVisible = true
                loadOlderIfReady()
            }
            .onDisappear {
                isOlderLoaderVisible = false
            }
    }

    private func loadOlderIfReady() {
        guard isReady, hasMore else { return }
        olderAnchor = firstRowId
        onLoadOlder()
    }

    /// Nouveau dernier message : retour en bas s'il est de moi, ou si j'y étais déjà.
    private func lastRowChanged() {
        guard let last = lastRow else { return }
        if last.isMine || isAtBottom {
            request(ChatScrollTarget.bottom, anchor: .bottom, animated: true)
        }
    }

    /// Page précédente arrivée : le message qui était en haut y reste. Dès iOS 17, l'ancre de défilement du bas
    /// (`defaultScrollAnchor`) garde déjà la position quand le contenu grandit par le haut.
    private func firstRowChanged() {
        guard let anchor = olderAnchor else { return }
        olderAnchor = nil
        if #unavailable(iOS 17.0) {
            request(anchor, anchor: .top, animated: false)
        }
    }

    private func request(
        _ target: String,
        anchor: UnitPoint,
        animated: Bool,
        delay: UInt64 = 0,
        isCorrection: Bool = false
    ) {
        serial += 1
        scroll = ChatScrollRequest(
            serial: serial,
            target: target,
            anchor: anchor,
            animated: animated,
            delayNanoseconds: delay,
            isCorrection: isCorrection
        )
    }

    /// Laisse la mise en page se faire (ou le clavier s'ouvrir), puis rend la demande exécutable ; une demande plus
    /// récente annule celle-ci (`task(id:)`).
    private func release(_ request: ChatScrollRequest?) async {
        guard let request else { return }
        if request.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: request.delayNanoseconds)
        } else {
            await Task.yield()
        }
        guard !Task.isCancelled else { return }
        due = request
    }

    private func perform(_ request: ChatScrollRequest?, proxy: ScrollViewProxy) {
        guard let request else { return }
        if request.animated && !reduceMotion {
            withAnimation(.easeOut(duration: WeydaDuration.medium)) {
                proxy.scrollTo(request.target, anchor: request.anchor)
            }
        } else {
            proxy.scrollTo(request.target, anchor: request.anchor)
        }
        guard !isReady else { return }
        if request.isCorrection {
            isReady = true
            if isOlderLoaderVisible {
                loadOlderIfReady()
            }
        } else {
            // Les hauteurs des bulles encore jamais affichées sont estimées : un second passage corrige la position.
            self.request(request.target, anchor: request.anchor, animated: false, delay: Self.correctionDelay, isCorrection: true)
        }
    }
}

/// iOS 17+ : le fil s'ouvre en bas et y reste quand le contenu ou la place change (clavier, page précédente).
private struct ChatBottomAnchor: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.defaultScrollAnchor(.bottom)
        } else {
            content
        }
    }
}

// MARK: - Une ligne

/// Une bulle ou une carte d'offre, du côté de son auteur (mes messages côté fin : à droite en français, à gauche en
/// arabe), puis « Lu » sous mon dernier message lu.
struct ChatMessageRow: View {
    private let row: ChatTimelineRow
    private let partnerName: String
    private let offerActions: Set<OfferAction>
    private let isOfferBusy: Bool
    private let onDelete: (ChatMessage) -> Void
    private let onRespond: (OfferAction) -> Void
    private let onCounter: () -> Void

    init(
        row: ChatTimelineRow,
        partnerName: String,
        offerActions: Set<OfferAction>,
        isOfferBusy: Bool,
        onDelete: @escaping (ChatMessage) -> Void,
        onRespond: @escaping (OfferAction) -> Void,
        onCounter: @escaping () -> Void
    ) {
        self.row = row
        self.partnerName = partnerName
        self.offerActions = offerActions
        self.isOfferBusy = isOfferBusy
        self.onDelete = onDelete
        self.onRespond = onRespond
        self.onCounter = onCounter
    }

    var body: some View {
        let alignment: HorizontalAlignment = row.isMine ? .trailing : .leading
        VStack(alignment: alignment, spacing: WeydaSpace.xxs) {
            HStack(spacing: 0) {
                if row.isMine {
                    Spacer(minLength: ChatMetrics.oppositeMargin)
                }
                bubble
                if !row.isMine {
                    Spacer(minLength: ChatMetrics.oppositeMargin)
                }
            }
            if row.showsReadReceipt {
                ChatReadReceipt()
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bubble: some View {
        if row.message.type == .offer, let offer = row.message.offer {
            ChatOfferCard(
                message: row.message,
                offer: offer,
                isMine: row.isMine,
                showsWaiting: row.showsWaitingForReply,
                actions: buttons,
                isBusy: isOfferBusy,
                canDelete: row.canDelete,
                onRespond: onRespond,
                onCounter: onCounter,
                onDelete: deleteAction
            )
        } else {
            ChatTextBubble(
                message: row.message,
                isMine: row.isMine,
                hasTail: row.endsGroup,
                canDelete: row.canDelete,
                speaker: speaker,
                onDelete: deleteAction
            )
        }
    }

    /// Boutons de la carte : seulement sur l'offre ouverte de l'AUTRE partie, et seulement ceux que l'état du fil
    /// permet (accepter et contrer disparaissent sur une annonce vendue ; refuser reste pour clore proprement).
    private var buttons: [OfferAction] {
        guard row.isActionableOffer else { return [] }
        let order: [OfferAction] = [.accept, .counter, .decline]
        return order.filter { offerActions.contains($0) }
    }

    private var speaker: String {
        row.isMine ? "" : partnerName
    }

    private var deleteAction: () -> Void {
        let message = row.message
        let onDelete = self.onDelete
        return { onDelete(message) }
    }
}

/// Séparateur de jour : petite capsule centrée et discrète (« Aujourd'hui », « Hier », « 28 sept. 2026 »). Titre pour
/// VoiceOver : le rotor « En-têtes » saute d'un jour à l'autre.
private struct ChatDaySeparator: View {
    let title: String

    var body: some View {
        Text(title)
            .weydaText(.labelSmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .lineLimit(1)
            .padding(.horizontal, WeydaSpace.md)
            .padding(.vertical, WeydaSpace.xs)
            .background(WeydaColor.surfaceContainer, in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// « ✓ Lu » sous mon dernier message lu par l'autre partie.
private struct ChatReadReceipt: View {
    var body: some View {
        HStack(spacing: WeydaSpace.xxs) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(L10n.chatRead)
                .weydaText(.labelSmall)
        }
        .foregroundStyle(WeydaColor.onSurfaceVariant)
        .padding(.horizontal, WeydaSpace.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bulle de texte

/// Bulle de texte : mes messages en vert (`bubbleOwn`), les siens en gris contrasté (`bubbleOther`, 4,5:1), heure en
/// bas ; le dernier d'une suite porte son coin rentré côté auteur. Message supprimé : « Message supprimé » en
/// italique dans une bulle vide. Appui long : copier, et supprimer dans les 5 minutes.
private struct ChatTextBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let hasTail: Bool
    let canDelete: Bool
    /// Nom de l'auteur pour VoiceOver ; vide = moi.
    let speaker: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: WeydaSpace.xxs) {
            messageText
            Text(Format.time(message.createdAt))
                .weydaText(.labelSmall)
                .foregroundStyle(timeColor)
        }
        .padding(.horizontal, WeydaSpace.md)
        .padding(.vertical, WeydaSpace.sm)
        .background {
            background
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: WeydaRadius.bubble, style: .continuous))
        .modifier(ChatBubbleMenu(copyText: copyText, canDelete: canDelete, onDelete: onDelete))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(Format.time(message.createdAt))
        .modifier(ChatDeleteAction(canDelete: canDelete, onDelete: onDelete))
    }

    @ViewBuilder
    private var messageText: some View {
        if message.isDeleted {
            Text(L10n.chatMessageDeleted)
                .italic()
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        } else {
            // Texte saisi par un utilisateur : sens de lecture d'après sa première lettre (`dir="auto"` du site).
            let direction: LayoutDirection = ChatTextDirection.isRightToLeft(message.content) ? .rightToLeft : .leftToRight
            Text(message.content)
                .weydaText(.bodyLarge)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, direction)
        }
    }

    @ViewBuilder
    private var background: some View {
        if message.isDeleted {
            RoundedRectangle(cornerRadius: WeydaRadius.bubble, style: .continuous)
                .strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        } else {
            ChatBubbleBackground(isMine: isMine, hasTail: hasTail, fill: fillColor)
        }
    }

    private var fillColor: Color {
        isMine ? WeydaPalette.bubbleOwn : WeydaPalette.bubbleOther
    }

    private var textColor: Color {
        isMine ? WeydaPalette.onBubbleOwn : WeydaPalette.onBubbleOther
    }

    private var timeColor: Color {
        if message.isDeleted { return WeydaColor.onSurfaceVariant }
        return isMine ? WeydaPalette.onBubbleOwn.opacity(0.8) : WeydaColor.onSurfaceVariant
    }

    private var copyText: String? {
        message.isDeleted || TextCheck.isBlank(message.content) ? nil : message.content
    }

    /// « Vous : texte » / « Amina : texte » (VoiceOver), l'heure en valeur.
    private var accessibilityText: String {
        let content: String = message.isDeleted ? L10n.chatMessageDeleted : message.content
        if TextCheck.isBlank(speaker) {
            return L10n.chatLastMessageYou(content)
        }
        return L10n.chatUiMessageFrom(speaker, content)
    }
}

/// Fond d'une bulle : rectangle arrondi, et coin rentré côté auteur pour la dernière bulle d'une suite. Deux formes
/// superposées (pas de `Shape` maison) ; `bottomTrailing` / `bottomLeading` se retournent d'eux-mêmes en arabe.
private struct ChatBubbleBackground: View {
    let isMine: Bool
    let hasTail: Bool
    let fill: Color

    var body: some View {
        let corner: Alignment = isMine ? .bottomTrailing : .bottomLeading
        ZStack(alignment: corner) {
            RoundedRectangle(cornerRadius: WeydaRadius.bubble, style: .continuous)
                .fill(fill)
            if hasTail {
                RoundedRectangle(cornerRadius: WeydaRadius.bubbleTail, style: .continuous)
                    .fill(fill)
                    .frame(width: WeydaRadius.bubble, height: WeydaRadius.bubble)
            }
        }
    }
}

/// Menu de l'appui long : « Copier » (texte), « Supprimer le message » (le mien, dans les 5 minutes).
private struct ChatBubbleMenu: ViewModifier {
    let copyText: String?
    let canDelete: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if copyText != nil || canDelete {
            content.contextMenu {
                if let copyText {
                    Button {
                        UIPasteboard.general.string = copyText
                    } label: {
                        Label(L10n.chatUiCopy, systemImage: "doc.on.doc")
                    }
                }
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.chatDeleteMessage, systemImage: "trash")
                    }
                }
            }
        } else {
            content
        }
    }
}

/// Suppression proposée à VoiceOver comme action nommée (Android : `onLongClickLabel`).
private struct ChatDeleteAction: ViewModifier {
    let canDelete: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canDelete {
            content.accessibilityAction(named: Text(L10n.chatDeleteMessage), onDelete)
        } else {
            content
        }
    }
}

// MARK: - Carte d'offre

/// Une offre du fil : état (« Offre reçue », « Contre-offre envoyée », « Offre acceptée »…), montant, puis — sur
/// l'offre ouverte de l'autre partie — « Accepter », « Contrer », « Refuser » ; sur la mienne encore ouverte,
/// « En attente de réponse… ».
private struct ChatOfferCard: View {
    let message: ChatMessage
    let offer: OfferMeta
    let isMine: Bool
    /// Mon offre encore ouverte (une offre dépassée par la suite du fil n'attend plus rien).
    let showsWaiting: Bool
    let actions: [OfferAction]
    let isBusy: Bool
    let canDelete: Bool
    let onRespond: (OfferAction) -> Void
    let onCounter: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            summary
            if !actions.isEmpty {
                ChatOfferButtons(actions: actions, isBusy: isBusy, onRespond: onRespond, onCounter: onCounter)
            }
        }
        .padding(WeydaSpace.md)
        .frame(minWidth: ChatMetrics.offerMinWidth, maxWidth: ChatMetrics.offerMaxWidth, alignment: .leading)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .contentShape(.contextMenuPreview, shape)
        .modifier(ChatBubbleMenu(copyText: nil, canDelete: canDelete, onDelete: onDelete))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.offer.\(message.id)")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            HStack(spacing: WeydaSpace.sm) {
                Image(systemName: ChatOfferStyle.symbol(offer.kind))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: ChatMetrics.offerIcon, height: ChatMetrics.offerIcon)
                    .background(accent.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Text(ChatOfferStyle.title(offer.kind, isMine: isMine))
                    .weydaText(.labelLarge)
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Format.amount(offer.amount))
                .strikethrough(offer.kind == .declined)
                .weydaText(.titleLarge)
                .foregroundStyle(amountColor)
                .fixedSize(horizontal: false, vertical: true)
            if message.isDeleted {
                Text(L10n.chatMessageDeleted)
                    .italic()
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            } else if showsWaiting {
                Label(L10n.offerWaitingResponse, systemImage: "clock")
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
            Text(Format.time(message.createdAt))
                .weydaText(.labelSmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Vert pour une offre ouverte ou acceptée, rouge pour un refus.
    private var accent: Color {
        switch offer.kind {
        case .new, .counter: WeydaColor.primary
        case .accepted: WeydaPalette.success
        case .declined: WeydaColor.error
        }
    }

    private var amountColor: Color {
        offer.kind == .declined ? WeydaColor.onSurfaceVariant : WeydaColor.onSurface
    }

    /// L'offre qui attend MA réponse ressort (contour vert) ; les autres gardent le filet des cartes.
    private var borderColor: Color {
        actions.isEmpty ? WeydaPalette.cardOutline : WeydaColor.primary
    }

    private var borderWidth: CGFloat {
        actions.isEmpty ? 1 : 1.5
    }
}

/// Libellés et pictogrammes d'une offre (logique pure) — `offerLabel` (Android).
nonisolated enum ChatOfferStyle {
    static func title(_ kind: OfferKind, isMine: Bool) -> String {
        switch kind {
        case .new: isMine ? L10n.offerSent : L10n.offerReceived
        case .counter: isMine ? L10n.offerCounterSent : L10n.offerCounterReceived
        case .accepted: L10n.offerAccepted
        case .declined: L10n.offerDeclined
        }
    }

    static func symbol(_ kind: OfferKind) -> String {
        switch kind {
        case .new: "tag.fill"
        case .counter: "arrow.left.arrow.right"
        case .accepted: "checkmark"
        case .declined: "xmark"
        }
    }
}

/// « Accepter », « Contrer », « Refuser » : sur une ligne si elle suffit, sinon « Accepter » au-dessus des deux autres,
/// sinon en colonne (texte agrandi, arabe). Hauteur 44 pt au moins.
private struct ChatOfferButtons: View {
    let actions: [OfferAction]
    let isBusy: Bool
    let onRespond: (OfferAction) -> Void
    let onCounter: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WeydaSpace.sm) {
                ForEach(actions, id: \.self) { action in
                    button(action)
                }
            }
            VStack(spacing: WeydaSpace.sm) {
                ForEach(primary, id: \.self) { action in
                    button(action)
                }
                HStack(spacing: WeydaSpace.sm) {
                    ForEach(secondary, id: \.self) { action in
                        button(action)
                    }
                }
            }
            VStack(spacing: WeydaSpace.sm) {
                ForEach(actions, id: \.self) { action in
                    button(action)
                }
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .disabled(isBusy)
    }

    private var primary: [OfferAction] {
        actions.filter { $0 == .accept }
    }

    private var secondary: [OfferAction] {
        actions.filter { $0 != .accept }
    }

    @ViewBuilder
    private func button(_ action: OfferAction) -> some View {
        switch action {
        case .accept:
            Button {
                onRespond(.accept)
            } label: {
                label(L10n.offerAccept, color: WeydaColor.onPrimary)
            }
            .buttonStyle(.borderedProminent)
            .tint(WeydaColor.primary)
            .accessibilityIdentifier("chat.offer.accept")
        case .counter:
            Button(action: onCounter) {
                label(L10n.offerCounter, color: WeydaColor.primary)
            }
            .buttonStyle(.bordered)
            .tint(WeydaColor.primary)
            .accessibilityIdentifier("chat.offer.counter")
        case .decline:
            Button {
                onRespond(.decline)
            } label: {
                label(L10n.offerDecline, color: WeydaColor.error)
            }
            .buttonStyle(.bordered)
            .tint(WeydaColor.error)
            .accessibilityIdentifier("chat.offer.decline")
        case .new:
            EmptyView()
        }
    }

    private func label(_ title: String, color: Color) -> some View {
        Text(title)
            .weydaText(.labelLarge)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - « Écrit… »

/// Bulle « … » de l'interlocuteur qui écrit (le sous-titre de l'en-tête le dit aussi). Points immobiles si
/// « Réduire les animations » est actif (ou pendant le tour de captures).
struct ChatTypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        HStack(spacing: 0) {
            dots
                .padding(.horizontal, WeydaSpace.md)
                .padding(.vertical, WeydaSpace.md)
                .background {
                    ChatBubbleBackground(isMine: false, hasTail: true, fill: WeydaPalette.bubbleOther)
                }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.chatTyping)
        .accessibilityIdentifier("chat.typing")
    }

    @ViewBuilder
    private var dots: some View {
        if reduceMotion || LaunchOptions.freezeMotion {
            ChatTypingDots(time: nil)
        } else {
            TimelineView(.animation(minimumInterval: ChatTypingClock.frameInterval)) { context in
                ChatTypingDots(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

private struct ChatTypingDots: View {
    /// Horloge de l'animation ; nil = points immobiles.
    let time: TimeInterval?

    private static let side: CGFloat = 7

    var body: some View {
        HStack(spacing: WeydaSpace.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(WeydaColor.onSurfaceVariant)
                    .frame(width: Self.side, height: Self.side)
                    .opacity(ChatTypingClock.opacity(dot: index, time: time))
            }
        }
    }
}

/// Vague des trois points (logique pure).
nonisolated enum ChatTypingClock {
    static let period: Double = 1.2
    static let frameInterval: Double = 1.0 / 30.0

    static func opacity(dot index: Int, time: TimeInterval?) -> Double {
        guard let time else { return 0.6 }
        let phase = (time / period - Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        let wave = 0.5 + 0.5 * sin(2 * Double.pi * phase)
        return 0.3 + 0.7 * wave
    }
}

// MARK: - Composeur

/// Barre de saisie (Android : `ChatComposer`) : bandeau « Vérifiez votre email » si besoin, raccourci « Faire une
/// offre » quand aucune n'est ouverte, champ multiligne (2000 caractères, compteur près de la limite) et bouton
/// d'envoi (désactivé si vide ou pendant l'envoi). Le texte vit ici pendant la frappe et suit le brouillon du ViewModel
/// (vidé après l'envoi).
struct ChatComposer: View {
    private let draft: String
    private let isSending: Bool
    private let canMakeOffer: Bool
    private let emailVerified: Bool
    private let onDraftChange: (String) -> Void
    private let onSend: () -> Void
    private let onMakeOffer: () -> Void
    private let onFocus: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        draft: String,
        isSending: Bool,
        canMakeOffer: Bool,
        emailVerified: Bool,
        onDraftChange: @escaping (String) -> Void,
        onSend: @escaping () -> Void,
        onMakeOffer: @escaping () -> Void,
        onFocus: @escaping () -> Void
    ) {
        self.draft = draft
        self.isSending = isSending
        self.canMakeOffer = canMakeOffer
        self.emailVerified = emailVerified
        self.onDraftChange = onDraftChange
        self.onSend = onSend
        self.onMakeOffer = onMakeOffer
        self.onFocus = onFocus
        _text = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            if !emailVerified {
                VerifyEmailBanner()
            }
            if canMakeOffer {
                offerShortcut
            }
            HStack(alignment: .bottom, spacing: WeydaSpace.sm) {
                field
                sendButton
            }
            if text.utf16.count >= ChatMetrics.counterThreshold {
                Text(L10n.postCharCount(text.utf16.count, ChatState.messageMax))
                    .weydaText(.labelSmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, WeydaSpace.md)
        .padding(.top, WeydaSpace.sm)
        .padding(.bottom, WeydaSpace.sm)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .onChange(of: text) { value in
            textChanged(value)
        }
        .onChange(of: draft) { value in
            if value != text {
                text = value
            }
        }
        .onChange(of: isFocused) { focused in
            if focused {
                onFocus()
            }
        }
    }

    private var canSend: Bool {
        !TextCheck.isBlank(text) && !isSending
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.panel, style: .continuous)
        return TextField(L10n.chatMessagePlaceholder, text: $text, axis: .vertical)
            .lineLimit(1...5)
            .weydaText(.bodyLarge)
            .focused($isFocused)
            .accessibilityIdentifier("chat.composer")
            .padding(.horizontal, WeydaSpace.md + WeydaSpace.xxs)
            .padding(.vertical, WeydaSpace.sm + WeydaSpace.xxs)
            .frame(minHeight: WeydaSize.touchTarget)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(isFocused ? WeydaColor.primary : WeydaPalette.cardOutline, lineWidth: 1)
            }
    }

    private var sendButton: some View {
        let active = canSend || isSending
        return Button(action: send) {
            ZStack {
                Circle()
                    .fill(active ? WeydaColor.primary : WeydaColor.surfaceContainerHigh)
                if isSending {
                    ProgressView()
                        .tint(WeydaColor.onPrimary)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(active ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant)
                }
            }
            .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
        }
        .buttonStyle(WeydaPressStyle(pressedScale: 0.92))
        .disabled(!canSend)
        .accessibilityLabel(isSending ? L10n.loading : L10n.chatSend)
        .accessibilityIdentifier("chat.send")
    }

    private var offerShortcut: some View {
        Button(action: onMakeOffer) {
            Label(L10n.offerMake, systemImage: "tag")
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onPrimaryContainer)
                .padding(.horizontal, WeydaSpace.md)
                .frame(minHeight: ChatMetrics.chipHeight)
                .background(WeydaColor.primaryContainer, in: Capsule())
                .padding(.vertical, (WeydaSize.touchTarget - ChatMetrics.chipHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeydaPressStyle())
        .accessibilityIdentifier("chat.offer.make")
    }

    /// Coupé à 2000 unités UTF-16 (et non ignoré : un collage trop long disparaissait sans explication sur Android).
    private func textChanged(_ value: String) {
        let capped = RepositorySupport.truncatedUTF16(value, max: ChatState.messageMax)
        if capped != value {
            text = capped
            return
        }
        onDraftChange(value)
    }

    private func send() {
        guard canSend else { return }
        onSend()
    }
}

// MARK: - Interlocuteur bloqué

/// À la place du composeur quand j'ai bloqué l'interlocuteur : explication et « Débloquer » (sans confirmation, comme
/// Android : débloquer est sans risque).
struct ChatBlockedBar: View {
    private let isBusy: Bool
    private let onUnblock: () -> Void

    init(isBusy: Bool, onUnblock: @escaping () -> Void) {
        self.isBusy = isBusy
        self.onUnblock = onUnblock
    }

    var body: some View {
        VStack(spacing: WeydaSpace.md) {
            HStack(alignment: .top, spacing: WeydaSpace.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.body)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityHidden(true)
                Text(L10n.chatUiBlockedNotice)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button(action: onUnblock) {
                ZStack {
                    Text(L10n.chatUiUnblock)
                        .weydaText(.labelLarge)
                        .opacity(isBusy ? 0 : 1)
                    if isBusy {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(WeydaColor.primary)
            .disabled(isBusy)
            .accessibilityLabel(isBusy ? L10n.loading : L10n.chatUiUnblock)
            .accessibilityIdentifier("chat.unblock")
        }
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.vertical, WeydaSpace.md)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Squelette

/// Premier chargement : des bulles fantômes de part et d'autre (la forme du fil est connue).
struct ChatSkeleton: View {
    private static let widths: [CGFloat] = [190, 130, 230, 160, 210, 110, 170]
    private static let bubbleHeight: CGFloat = 40

    init() {}

    var body: some View {
        VStack(spacing: WeydaSpace.md) {
            ForEach(Self.widths.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    if index % 2 == 1 {
                        Spacer(minLength: 0)
                    }
                    SkeletonBlock(width: Self.widths[index], height: Self.bubbleHeight, radius: WeydaRadius.bubble)
                    if index % 2 == 0 {
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WeydaSpace.md)
        .padding(.top, WeydaSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.loading)
    }
}

// MARK: - Portrait

/// Portrait rond de l'interlocuteur ; sans photo, son initiale sur la pastille verte (Android : `PartnerAvatar`).
/// Point vert quand il a le fil ouvert.
struct ChatPartnerAvatar: View {
    private let name: String
    private let url: String?
    private let size: CGFloat
    private let isOnline: Bool

    init(name: String, url: String?, size: CGFloat, isOnline: Bool = false) {
        self.name = name
        self.url = url
        self.size = size
        self.isOnline = isOnline
    }

    var body: some View {
        Circle()
            .fill(WeydaColor.primaryContainer)
            .overlay {
                if let url = TextCheck.nonBlank(url) {
                    RemoteImage(urlString: url)
                } else {
                    Text(verbatim: initial)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(WeydaColor.onPrimaryContainer)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(WeydaPalette.success)
                        .frame(width: size * 0.32, height: size * 0.32)
                        .overlay {
                            Circle().strokeBorder(WeydaColor.surface, lineWidth: 2)
                        }
                }
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
