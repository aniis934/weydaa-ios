import SwiftUI

/// « Utilisateurs bloqués » (écran poussé depuis le Profil, interface fixée de la phase 5) — propre à iOS : l'App
/// Store (Guideline 1.2) demande qu'un utilisateur puisse revoir et lever ses blocages. Écran de membre
/// (`AccountMemberGate`). Liste groupée comme les Réglages d'iOS (Contacts bloqués) : avatar, nom (ou « Compte
/// supprimé »), date du blocage, « Débloquer » après confirmation.
struct BlockedUsersView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.blockedUsersTitle) { _ in
            BlockedUsersHost(model: BlockedUsersViewModel(conversations: container.conversations))
        }
    }
}

/// Possède le ViewModel ; branche la confirmation du déblocage sur son état.
private struct BlockedUsersHost: View {
    @StateObject private var model: BlockedUsersViewModel

    init(model: @autoclosure @escaping () -> BlockedUsersViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        BlockedUsersScreen(
            state: model.state,
            isConfirmationPresented: confirmationBinding,
            actions: actions
        )
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor [model] in
            await model.pullToRefresh()
        }
        .onAppear {
            _ = model.appear()
        }
    }

    private var actions: BlockedUsersActions {
        let model = self.model
        return BlockedUsersActions(
            onUnblock: { (user: BlockedUser) in
                model.askUnblock(user)
            },
            onConfirm: {
                _ = model.confirmUnblock()
            },
            onCancel: {
                model.dismissUnblock()
            },
            onRetry: {
                _ = model.load()
            },
            onLoadMore: {
                _ = model.loadMore()
            },
            onNoticeShown: {
                model.noticeShown()
            }
        )
    }

    /// Boîte de confirmation, ouverte tant qu'un déblocage attend (`pendingUnblock`). Un appui sur l'un de ses
    /// boutons la referme et SwiftUI repasse la liaison à « faux » — peut-être AVANT d'exécuter l'action du bouton,
    /// qui lit encore la demande : l'effacement est donc reporté au tour suivant (sans effet si le bouton l'a fait).
    private var confirmationBinding: Binding<Bool> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.pendingUnblock != nil } },
            set: { presented in
                guard !presented else { return }
                Task { @MainActor in
                    model.dismissUnblock()
                }
            }
        )
    }
}

/// Actions de l'écran (branchées par l'hôte sur le ViewModel).
struct BlockedUsersActions {
    var onUnblock: (BlockedUser) -> Void
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onRetry: () -> Void
    var onLoadMore: () -> Void
    var onNoticeShown: () -> Void
}

/// Écran sans état : squelettes, erreur, vide (comment bloquer), ou la liste et sa note de bas de section ;
/// confirmation du déblocage (une alerte : « Débloquer » n'est pas destructif) et bannière qui le suit.
struct BlockedUsersScreen: View {
    private let state: BlockedUsersState
    private let isConfirmationPresented: Binding<Bool>
    private let actions: BlockedUsersActions

    /// La page suivante se demande quand l'une des 3 dernières lignes paraît.
    private static let prefetchDistance = 3

    init(state: BlockedUsersState, isConfirmationPresented: Binding<Bool>, actions: BlockedUsersActions) {
        self.state = state
        self.isConfirmationPresented = isConfirmationPresented
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeydaColor.background)
        .navigationTitle(L10n.blockedUsersTitle)
        .navigationBarTitleDisplayMode(.inline)
        .weydaBanner(state.banner, onAction: { _ in }, onDismiss: actions.onNoticeShown)
        .alert(L10n.inboxUnblockConfirmTitle, isPresented: isConfirmationPresented, presenting: state.pendingUnblock) { _ in
            Button(L10n.inboxUnblock, action: actions.onConfirm)
            Button(L10n.cancel, role: .cancel, action: actions.onCancel)
        } message: { _ in
            Text(L10n.inboxUnblockConfirmBody)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.blockedUsers")
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            InboxRowSkeletons(count: 4, showsThumb: false)
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: actions.onRetry)
        } else if state.items.isEmpty {
            InboxScrollableState {
                EmptyState(
                    systemImage: "hand.raised",
                    title: L10n.inboxBlockedEmptyTitle,
                    message: L10n.inboxBlockedEmptyBody
                )
            }
        } else {
            list
        }
    }

    private var list: some View {
        let items: [BlockedUser] = state.items
        let trailing: Set<String> = Set(items.suffix(Self.prefetchDistance).map { $0.id })
        let busyId: String? = state.busyId
        return List {
            Section {
                ForEach(items) { user in
                    BlockedUserRow(
                        user: user,
                        isBusy: busyId == user.id,
                        isLocked: busyId != nil,
                        onUnblock: { actions.onUnblock(user) }
                    )
                    .listRowBackground(WeydaColor.surface)
                    .onAppear {
                        if trailing.contains(user.id) {
                            actions.onLoadMore()
                        }
                    }
                }
                if state.isLoadingMore {
                    InlineLoader()
                        .listRowBackground(WeydaColor.surface)
                }
            } footer: {
                Text(L10n.inboxBlockedFooter)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

/// Une personne bloquée : avatar (initiale, ou silhouette pour un compte supprimé), nom, date du blocage, bouton
/// « Débloquer » (remplacé par l'indicateur pendant SON déblocage ; désactivé pendant celui d'un autre). Très grand
/// texte : le bouton passe SOUS le nom et la date, qui s'écrivent en entier (« Débloquer » et la date étaient coupés).
private struct BlockedUserRow: View {
    private let user: BlockedUser
    private let isBusy: Bool
    private let isLocked: Bool
    private let onUnblock: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(user: BlockedUser, isBusy: Bool, isLocked: Bool, onUnblock: @escaping () -> Void) {
        self.user = user
        self.isBusy = isBusy
        self.isLocked = isLocked
        self.onUnblock = onUnblock
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: WeydaSpace.md) {
                avatar
                VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                    identity
                        .accessibilityElement(children: .combine)
                    unblockControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: WeydaSize.touchTarget)
            .padding(.vertical, WeydaSpace.xs)
        } else {
            HStack(spacing: WeydaSpace.md) {
                avatar
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                unblockControl
            }
            .frame(minHeight: WeydaSize.touchTarget)
            .padding(.vertical, WeydaSpace.xxs)
        }
    }

    private var avatar: some View {
        InboxAvatar(name: user.name, url: user.avatarUrl, size: WeydaSize.avatarSmall)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
            Text(BlockedUsersText.name(of: user))
                .weydaText(.bodyLarge)
                .fontWeight(.semibold)
                .foregroundStyle(user.name == nil ? WeydaColor.onSurfaceVariant : WeydaColor.onSurface)
                .lineLimit(nameLineLimit)
            if let since = BlockedUsersText.blockedSince(user) {
                Text(since)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(dateLineLimit)
            }
        }
    }

    /// Tailles normales : nom sur 2 lignes, date sur 1 ; très grand texte : autant de lignes qu'il faut (nil).
    private var nameLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 2
    }

    private var dateLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 1
    }

    @ViewBuilder
    private var unblockControl: some View {
        if isBusy {
            WeydaLoader()
                .frame(width: BlockedUsersText.loaderSide, height: BlockedUsersText.loaderSide)
                .frame(minWidth: WeydaSize.touchTarget, minHeight: WeydaSize.touchTarget)
                .accessibilityLabel(L10n.loading)
        } else {
            Button(action: onUnblock) {
                Text(L10n.inboxUnblock)
                    .weydaText(.labelLarge)
                    .lineLimit(unblockLineLimit)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(WeydaColor.primary)
            .disabled(isLocked)
            .accessibilityLabel(L10n.inboxUnblockNamed(BlockedUsersText.name(of: user)))
            .accessibilityIdentifier("blocked.unblock.\(user.id)")
        }
    }

    /// Sous le nom, le bouton a toute la largeur : une ligne par mot au plus (« إلغاء الحظر »), jamais tronqué.
    private var unblockLineLimit: Int {
        guard dynamicTypeSize.isAccessibilitySize else { return 1 }
        return LabelLines.limit(for: L10n.inboxUnblock, maxLines: 2)
    }
}

/// Textes d'une ligne de « Utilisateurs bloqués ». Logique pure, testable.
nonisolated enum BlockedUsersText {
    /// Côté du W qui s'écrit pendant un déblocage.
    static let loaderSide: CGFloat = 22

    /// Nom, ou « Compte supprimé » (le blocage d'un compte supprimé reste listé).
    static func name(of user: BlockedUser) -> String {
        TextCheck.nonBlank(user.name) ?? L10n.chatDeletedUser
    }

    /// « Bloqué le 30 sept. 2026 » ; nil sans date.
    static func blockedSince(_ user: BlockedUser, locale: Locale = WeydaLocale.formatting, timeZone: TimeZone = .current) -> String? {
        guard let date = user.blockedAt else { return nil }
        return L10n.inboxBlockedOn(Format.date(date, locale: locale, timeZone: timeZone))
    }
}
