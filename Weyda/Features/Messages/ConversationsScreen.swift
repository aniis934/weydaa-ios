import SwiftUI

/// Actions de l'écran des conversations (branchées par `ConversationsView` sur le ViewModel et le routeur).
struct ConversationsActions {
    var onOpen: (Conversation) -> Void
    var onToggleArchive: (Conversation) -> Void
    /// « Voir l'annonce » de l'appui long (identifiant de l'annonce).
    var onOpenListing: (String) -> Void
    var onRetry: () -> Void
    var onLoadMore: () -> Void
    /// « Annuler » de la bannière.
    var onBannerAction: (BannerAction) -> Void
    var onBannerDismissed: () -> Void
}

/// Onglet Messages d'un membre, sans état propre — portage de `ConversationsScreen` : grand titre, sélecteur
/// Conversations / Archives (segmenté natif), recherche locale (`.searchable`), rangées dans une `List` native (glisser
/// pour archiver ou désarchiver ; appui long : archiver, voir l'annonce), page suivante en approchant du bas, états
/// (squelettes, erreur, vide, aucun résultat), bannière (« Annuler » après un archivage). L'onglet touché de nouveau
/// remonte la liste en haut.
struct ConversationsScreen: View {
    private let state: ConversationsState
    private let query: Binding<String>
    private let archived: Binding<Bool>
    private let actions: ConversationsActions
    /// Onglet Messages touché alors qu'il est déjà à sa racine : retour à la première conversation.
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    /// La page suivante se demande quand l'une des 3 dernières rangées paraît (Android : même seuil).
    private static let prefetchDistance = 3

    init(state: ConversationsState, query: Binding<String>, archived: Binding<Bool>, actions: ConversationsActions) {
        self.state = state
        self.query = query
        self.archived = archived
        self.actions = actions
    }

    /// Sélecteur dans une pile, AU-DESSUS de la liste, et non dans un `safeAreaInset` : sur iOS 26, l'effet de bord
    /// de défilement de la barre de navigation recouvre l'encart du haut (constat de la phase 3).
    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            ConversationsSegmentBar(archived: archived)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeydaColor.surface)
        .navigationTitle(L10n.navMessages)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.chatSearchPlaceholder)
        .weydaBanner(state.banner, onAction: actions.onBannerAction, onDismiss: actions.onBannerDismissed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.conversations")
    }

    /// Chaque état a sa propre vue : un nouveau segment repart du haut de la liste (Android le faisait à la main).
    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            InboxRowSkeletons()
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: actions.onRetry)
        } else if state.items.isEmpty {
            InboxScrollableState {
                emptyMessage
            }
        } else if shownItems.isEmpty {
            InboxScrollableState {
                EmptyState(systemImage: "magnifyingglass", title: L10n.chatSearchEmpty)
            }
        } else {
            list
        }
    }

    /// Conversations qui répondent à la recherche (toutes si le champ est vide).
    private var shownItems: [Conversation] {
        state.visibleItems(matching: query.wrappedValue)
    }

    /// La liste dans un `ScrollViewReader` : l'onglet touché de nouveau (pile vide) remonte à la première rangée
    /// affichée (identité de son `ForEach` = l'id de la conversation).
    private var list: some View {
        let items: [Conversation] = shownItems
        let trailing: Set<String> = Set(items.suffix(Self.prefetchDistance).map { $0.id })
        let topId: String = items.first?.id ?? ""
        let signal: Int = scrollToTopSignal
        return ScrollViewReader { proxy in
            List {
                ForEach(items) { conversation in
                    row(for: conversation, isTrailing: trailing.contains(conversation.id))
                }
                if state.isLoadingMore {
                    InlineLoader()
                        .listRowSeparator(.hidden)
                        .listRowBackground(WeydaColor.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollsToTop(on: signal, proxy: proxy, to: topId)
        }
    }

    /// Une rangée : appui = le fil ; glisser vers le bord de fin = archiver (désarchiver dans les archives), action
    /// aussi proposée à VoiceOver par la liste ; appui long = menu (voir l'annonce, archiver) avec l'aperçu de la
    /// rangée.
    private func row(for conversation: Conversation, isTrailing: Bool) -> some View {
        let isBlocked: Bool = state.isBlocked(conversation)
        let label: String = ConversationsText.accessibilityLabel(for: conversation, userId: state.userId, isBlocked: isBlocked)
        let userId: String = state.userId
        return Button {
            actions.onOpen(conversation)
        } label: {
            ConversationRow(conversation: conversation, userId: userId, isBlocked: isBlocked)
        }
        .listRowInsets(EdgeInsets(top: WeydaSpace.sm, leading: WeydaSpace.screen, bottom: WeydaSpace.sm, trailing: WeydaSpace.screen))
        .listRowBackground(WeydaColor.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                actions.onToggleArchive(conversation)
            } label: {
                Label(archiveTitle, systemImage: archiveSymbol)
            }
            .tint(WeydaColor.primary)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("conversation.row.\(conversation.id)")
        .contextMenu {
            ConversationMenuItems(
                conversation: conversation,
                archived: state.archived,
                onToggleArchive: actions.onToggleArchive,
                onOpenListing: actions.onOpenListing
            )
        } preview: {
            ConversationMenuPreview(conversation: conversation, userId: userId, isBlocked: isBlocked)
        }
        .onAppear {
            if isTrailing {
                actions.onLoadMore()
            }
        }
    }

    /// Action du glissement : archiver (boîte de réception) ou désarchiver (archives).
    private var archiveTitle: String {
        state.archived ? L10n.chatUnarchive : L10n.chatArchive
    }

    private var archiveSymbol: String {
        state.archived ? "tray.and.arrow.up" : "archivebox"
    }

    /// Boîte de réception vide : comment démarrer une conversation ; archives vides : la simple mention.
    @ViewBuilder
    private var emptyMessage: some View {
        if state.archived {
            EmptyState(systemImage: "archivebox", title: L10n.chatNoArchives)
        } else {
            EmptyState(
                systemImage: "bubble.left.and.bubble.right",
                title: L10n.chatNoConversations,
                message: L10n.chatNoConversationsDesc
            )
        }
    }
}

/// Entrées de l'appui long sur une conversation : voir l'annonce (si elle est connue), puis archiver (désarchiver dans
/// les archives) — les mêmes règles que le glissement, qui reste.
private struct ConversationMenuItems: View {
    private let conversation: Conversation
    private let archived: Bool
    private let onToggleArchive: (Conversation) -> Void
    private let onOpenListing: (String) -> Void

    init(
        conversation: Conversation,
        archived: Bool,
        onToggleArchive: @escaping (Conversation) -> Void,
        onOpenListing: @escaping (String) -> Void
    ) {
        self.conversation = conversation
        self.archived = archived
        self.onToggleArchive = onToggleArchive
        self.onOpenListing = onOpenListing
    }

    var body: some View {
        if let listingId = ConversationsText.listingId(of: conversation) {
            Button {
                onOpenListing(listingId)
            } label: {
                Label(L10n.menuOpenListing, systemImage: "tag")
            }
            .accessibilityIdentifier("conversation.menu.listing.\(conversation.id)")
        }
        Button {
            onToggleArchive(conversation)
        } label: {
            Label(archiveTitle, systemImage: archiveSymbol)
        }
        .accessibilityIdentifier("conversation.menu.archive.\(conversation.id)")
    }

    private var archiveTitle: String {
        archived ? L10n.chatUnarchive : L10n.chatArchive
    }

    private var archiveSymbol: String {
        archived ? "tray.and.arrow.up" : "archivebox"
    }
}

/// Aperçu de l'appui long : la rangée elle-même, à largeur fixe, sur le fond de la liste.
private struct ConversationMenuPreview: View {
    private let conversation: Conversation
    private let userId: String
    private let isBlocked: Bool

    /// Tient sur le plus petit iPhone (375 pt) avec les marges du menu.
    private static let width: CGFloat = 340

    init(conversation: Conversation, userId: String, isBlocked: Bool) {
        self.conversation = conversation
        self.userId = userId
        self.isBlocked = isBlocked
    }

    var body: some View {
        ConversationRow(conversation: conversation, userId: userId, isBlocked: isBlocked)
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.md)
            .frame(width: Self.width)
            .background(WeydaColor.surface)
    }
}

/// Sélecteur segmenté natif « Conversations / Archives ».
private struct ConversationsSegmentBar: View {
    let archived: Binding<Bool>

    var body: some View {
        Picker(L10n.navMessages, selection: archived) {
            Text(L10n.chatTabConversations)
                .tag(false)
            Text(L10n.chatTabArchives)
                .tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.top, WeydaSpace.xs)
        .padding(.bottom, WeydaSpace.sm)
        .accessibilityIdentifier("conversations.archives")
    }
}
