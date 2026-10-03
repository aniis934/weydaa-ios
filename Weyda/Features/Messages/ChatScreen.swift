import SwiftUI

/// Actions du fil, branchées par `ChatView` (ViewModel, routeur) — `ChatActions` (Android).
struct ChatActions {
    var retry: () -> Void
    var loadOlder: () -> Void
    var draftChanged: (String) -> Void
    var send: () -> Void
    var askDelete: (ChatMessage) -> Void
    var makeOffer: () -> Void
    var counterOffer: () -> Void
    var respondOffer: (OfferAction) -> Void
    var openListing: () -> Void
    var openProfile: () -> Void
    var toggleArchive: () -> Void
    var block: () -> Void
    var unblock: () -> Void
    var report: () -> Void
    var noticeShown: () -> Void
}

/// Fil d'une conversation, sans état — portage de `ChatScreen` (Android) : en-tête (interlocuteur, « En ligne » /
/// « écrit… »), annonce du fil, bulles et cartes d'offre, composeur (ou encart « bloqué »), menu (annonce, profil,
/// archiver, bloquer, signaler). Squelette pendant le premier chargement, erreur avec « Réessayer ».
struct ChatScreen: View {
    private let state: ChatState
    private let emailVerified: Bool
    private let actions: ChatActions

    init(state: ChatState, emailVerified: Bool, actions: ChatActions) {
        self.state = state
        self.emailVerified = emailVerified
        self.actions = actions
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                OfflineBanner()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.chat")
    }

    /// Titre de la barre (bouton retour de l'écran suivant, VoiceOver) ; l'en-tête visible est `ChatHeaderTitle`.
    private var navigationTitle: String {
        state.conversation == nil ? "" : state.partnerName
    }

    @ViewBuilder
    private var content: some View {
        if let conversation = state.conversation {
            ChatThreadContent(state: state, conversation: conversation, emailVerified: emailVerified, actions: actions)
        } else if let message = state.errorMessage, !state.isLoading {
            ErrorState(message: message, onRetry: actions.retry)
        } else {
            ChatSkeleton()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if state.conversation != nil {
                ChatHeaderTitle(state: state, onOpenProfile: actions.openProfile)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if state.conversation != nil {
                ChatMenu(state: state, actions: actions)
            }
        }
    }
}

// MARK: - Fil chargé

/// Annonce du fil en haut, messages, puis le composeur (ou l'encart « bloqué ») en bas ; le message bref se pose
/// juste au-dessus du composeur.
private struct ChatThreadContent: View {
    private let state: ChatState
    private let conversation: Conversation
    private let emailVerified: Bool
    private let actions: ChatActions
    /// Champ de saisie touché : le fil redescend en bas une fois le clavier ouvert.
    @State private var bottomRequest: Int = 0

    init(state: ChatState, conversation: Conversation, emailVerified: Bool, actions: ChatActions) {
        self.state = state
        self.conversation = conversation
        self.emailVerified = emailVerified
        self.actions = actions
    }

    var body: some View {
        messages
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let annonce = conversation.annonce {
                    ChatListingBanner(annonce: annonce, onOpen: actions.openListing)
                }
            }
            // Message bref AVANT le composeur : il se pose juste au-dessus de lui.
            .floatingNotice(state.notice, onShown: actions.noticeShown)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
    }

    @ViewBuilder
    private var messages: some View {
        if state.messages.isEmpty {
            EmptyState(
                systemImage: "bubble.left.and.bubble.right",
                title: L10n.chatStartConversation,
                message: L10n.chatSendMessageTo(state.partnerName)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ChatMessageList(
                items: timelineItems,
                partnerName: state.partnerName,
                hasMore: state.hasMore,
                isPartnerTyping: state.isPartnerTyping,
                offerActions: state.offerActions,
                isOfferBusy: state.isOfferBusy,
                bottomRequest: bottomRequest,
                onLoadOlder: actions.loadOlder,
                onDelete: actions.askDelete,
                onRespond: actions.respondOffer,
                onCounter: actions.counterOffer
            )
        }
    }

    /// Lignes du fil et séparateurs de jour, dans le fuseau de l'appareil.
    private var timelineItems: [ChatTimelineItem] {
        let calendar = ChatDayGrouping.deviceCalendar()
        let rows = ChatTimeline.rows(messages: state.messages, userId: state.userId, now: Date(), calendar: calendar)
        return ChatTimeline.items(rows: rows, calendar: calendar)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if state.isBlocked {
            ChatBlockedBar(isBusy: state.isBlockBusy, onUnblock: actions.unblock)
        } else {
            ChatComposer(
                draft: state.draft,
                isSending: state.isSending,
                canMakeOffer: state.canMakeOffer,
                emailVerified: emailVerified,
                onDraftChange: actions.draftChanged,
                onSend: actions.send,
                onMakeOffer: actions.makeOffer,
                onFocus: {
                    bottomRequest += 1
                }
            )
        }
    }
}

// MARK: - En-tête

/// Interlocuteur au centre de la barre : portrait (point vert s'il a le fil ouvert), nom, puis « En train d'écrire… »
/// / « En ligne » en vert, sinon le titre de l'annonce. Toucher ouvre son profil public.
private struct ChatHeaderTitle: View {
    let state: ChatState
    let onOpenProfile: () -> Void

    private static let avatarSide: CGFloat = 32

    var body: some View {
        Button(action: onOpenProfile) {
            HStack(spacing: WeydaSpace.sm) {
                ChatPartnerAvatar(
                    name: state.partnerName,
                    url: state.partner?.avatarUrl,
                    size: Self.avatarSide,
                    isOnline: state.isPartnerOnline
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.partnerName)
                        .weydaText(.titleSmall)
                        .foregroundStyle(WeydaColor.onSurface)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .weydaText(.labelSmall)
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.hasPartnerProfile)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(state.hasPartnerProfile ? L10n.chatUiViewProfile : ""))
        .accessibilityIdentifier("chat.header")
    }

    /// Sous-titre : « écrit… » / « En ligne » en priorité, sinon l'annonce du fil.
    private var subtitle: String? {
        if state.isPartnerTyping { return L10n.chatTyping }
        if state.isPartnerOnline { return L10n.chatOnline }
        return TextCheck.nonBlank(state.conversation?.annonce?.title)
    }

    private var subtitleColor: Color {
        state.isPartnerTyping || state.isPartnerOnline ? WeydaColor.primary : WeydaColor.onSurfaceVariant
    }
}

// MARK: - Menu

/// « Plus d'actions » : voir l'annonce, voir le profil, archiver / désarchiver, bloquer (avec confirmation) /
/// débloquer, signaler l'interlocuteur.
private struct ChatMenu: View {
    let state: ChatState
    let actions: ChatActions

    var body: some View {
        Menu {
            if state.annonceId != nil {
                Button(action: actions.openListing) {
                    Label(L10n.chatViewListing, systemImage: "tag")
                }
                .accessibilityIdentifier("chat.menu.listing")
            }
            if state.hasPartnerProfile {
                Button(action: actions.openProfile) {
                    Label(L10n.chatUiViewProfile, systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("chat.menu.profile")
            }
            Divider()
            archiveButton
            blockButton
            Button(role: .destructive, action: actions.report) {
                Label(L10n.reportUserAction, systemImage: "flag")
            }
            .accessibilityIdentifier("chat.menu.report")
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(L10n.chatMoreActions)
        }
        .accessibilityIdentifier("chat.menu")
    }

    private var archiveButton: some View {
        let title: String = state.isArchived ? L10n.chatUnarchive : L10n.chatArchive
        let symbol: String = state.isArchived ? "tray.and.arrow.up" : "archivebox"
        return Button(action: actions.toggleArchive) {
            Label(title, systemImage: symbol)
        }
        .accessibilityIdentifier("chat.menu.archive")
    }

    @ViewBuilder
    private var blockButton: some View {
        if state.isBlocked {
            Button(action: actions.unblock) {
                Label(L10n.chatUnblockUser, systemImage: "hand.raised.slash")
            }
            .accessibilityIdentifier("chat.menu.unblock")
        } else {
            Button(role: .destructive, action: actions.block) {
                Label(L10n.chatBlockUser, systemImage: "hand.raised")
            }
            .accessibilityIdentifier("chat.menu.block")
        }
    }
}

// MARK: - Annonce du fil

/// Bandeau de l'annonce sous la barre (Android : `AnnonceHeader`) : vignette, titre, prix et statut s'il n'est plus en
/// ligne (« Vendue »…) ; toucher ouvre la fiche. Fond translucide : le fil défile dessous.
private struct ChatListingBanner: View {
    let annonce: ConversationAnnonce
    let onOpen: () -> Void

    private static let thumbSide: CGFloat = 44

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: WeydaSpace.md) {
                thumbnail
                VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                    Text(annonce.title)
                        .weydaText(.titleSmall)
                        .foregroundStyle(WeydaColor.onSurface)
                        .lineLimit(1)
                    details
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(WeydaPressStyle())
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(L10n.chatViewListing))
        .accessibilityIdentifier("chat.listing")
    }

    private var thumbnail: some View {
        RemoteImage(urlString: annonce.imageUrl.map(thumbnailUrl), fallbackURLString: annonce.imageUrl)
            .frame(width: Self.thumbSide, height: Self.thumbSide)
            .overlay {
                if annonce.imageUrl == nil {
                    Image(systemName: "photo")
                        .font(.footnote)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var details: some View {
        let price: String? = ChatListingText.price(annonce)
        let status: String? = ChatListingText.status(annonce.status)
        if price != nil || status != nil {
            HStack(spacing: WeydaSpace.sm) {
                if let price {
                    Text(price)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.primary)
                        .lineLimit(1)
                }
                if let status {
                    Text(status)
                        .weydaText(.labelSmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .padding(.horizontal, WeydaSpace.sm)
                        .padding(.vertical, WeydaSpace.xxs)
                        .background(
                            WeydaColor.surfaceContainer,
                            in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous)
                        )
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Textes du bandeau de l'annonce (logique pure).
nonisolated enum ChatListingText {
    /// « Gratuit », « 3 150 000 DA », ou rien (prix sur demande).
    static func price(_ annonce: ConversationAnnonce) -> String? {
        if annonce.priceType == .free { return L10n.priceFree }
        guard let price = annonce.price else { return nil }
        return Format.amount(price)
    }

    /// Statut d'une annonce qui n'est plus en ligne ; nil si active (ou inconnu, comme dans la liste).
    static func status(_ status: ListingStatus?) -> String? {
        switch status {
        case .sold: L10n.statusSold
        case .expired: L10n.statusExpired
        case .pending: L10n.statusPending
        case .rejected: L10n.statusRejected
        case .active, nil: nil
        }
    }
}
