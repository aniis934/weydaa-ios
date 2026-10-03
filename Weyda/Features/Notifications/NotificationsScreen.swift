import SwiftUI

/// Actions de l'écran des notifications (branchées par `NotificationsView` sur le ViewModel et le routeur).
struct NotificationsActions {
    var onOpen: (AppNotification) -> Void
    var onDelete: (AppNotification) -> Void
    var onMarkAllRead: () -> Void
    var onRetry: () -> Void
    var onLoadMore: () -> Void
    var onNoticeShown: () -> Void
}

/// Cloche d'un membre, sans état propre — portage de `NotificationsScreen` : rangées dans une `List` native (appui =
/// marquer lue puis ouvrir la cible, glisser = supprimer), « Tout marquer comme lu » dans la barre tant qu'il reste
/// des non lues, page suivante en approchant du bas, états (squelettes, erreur, vide), message bref. Grand titre :
/// la barre garde toute sa largeur pour le bouton.
struct NotificationsScreen: View {
    private let state: NotificationsState
    private let actions: NotificationsActions

    /// La page suivante se demande quand l'une des 3 dernières rangées paraît (Android : même seuil).
    private static let prefetchDistance = 3

    init(state: NotificationsState, actions: NotificationsActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.surface)
            .safeAreaInset(edge: .top, spacing: 0) {
                OfflineBanner()
            }
            .navigationTitle(L10n.notificationsTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if state.unreadCount > 0 && !state.isLoading {
                        Button(L10n.notificationsMarkAllRead, action: actions.onMarkAllRead)
                            .tint(WeydaColor.primary)
                            .accessibilityIdentifier("notifications.markAll")
                    }
                }
            }
            .floatingNotice(state.notice, onShown: actions.onNoticeShown)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.notifications")
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            InboxRowSkeletons(showsThumb: false)
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: actions.onRetry)
        } else if state.items.isEmpty {
            InboxScrollableState {
                EmptyState(systemImage: "bell", title: L10n.notificationsEmpty)
            }
        } else {
            list
        }
    }

    private var list: some View {
        let items: [AppNotification] = state.items
        let trailing: Set<String> = Set(items.suffix(Self.prefetchDistance).map { $0.id })
        return List {
            ForEach(items) { notification in
                row(for: notification, isTrailing: trailing.contains(notification.id))
            }
            if state.isLoadingMore {
                InlineLoader()
                    .listRowSeparator(.hidden)
                    .listRowBackground(WeydaColor.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Une rangée : appui = ouvrir ; glisser vers le bord de fin = supprimer (aussi proposé à VoiceOver).
    private func row(for notification: AppNotification, isTrailing: Bool) -> some View {
        Button {
            actions.onOpen(notification)
        } label: {
            NotificationRow(notification: notification)
        }
        .listRowInsets(EdgeInsets(top: WeydaSpace.sm, leading: WeydaSpace.screen, bottom: WeydaSpace.sm, trailing: WeydaSpace.screen))
        .listRowBackground(WeydaColor.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                actions.onDelete(notification)
            } label: {
                Label(L10n.chatDelete, systemImage: "trash")
            }
            .accessibilityLabel(L10n.notificationDelete)
        }
        .accessibilityLabel(NotificationsText.accessibilityLabel(for: notification))
        .accessibilityIdentifier("notification.row.\(notification.id)")
        .onAppear {
            if isTrailing {
                actions.onLoadMore()
            }
        }
    }
}

// MARK: - Rangée

/// Une notification : pictogramme du type sur sa pastille de couleur, libellé du type et ancienneté, titre (gras si
/// non lue), corps sur deux lignes, point vert « non lu ».
private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: WeydaSpace.md) {
            NotificationKindIcon(kind: notification.kind)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                NotificationRowHeader(
                    kind: notification.kind,
                    date: Format.relativeTime(notification.createdAt),
                    unread: !notification.read
                )
                Text(notification.title)
                    .weydaText(.titleSmall)
                    .fontWeight(notification.read ? Font.Weight.medium : Font.Weight.bold)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let detail = TextCheck.nonBlank(notification.body) {
                    Text(detail)
                        .weydaText(.bodyMedium)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, WeydaSpace.xxs)
        .contentShape(Rectangle())
    }
}

/// Libellé du type (vert si non lue), ancienneté, point « non lu ».
private struct NotificationRowHeader: View {
    let kind: NotificationKind
    let date: String
    let unread: Bool

    var body: some View {
        HStack(alignment: .center, spacing: WeydaSpace.sm) {
            Text(NotificationsText.kindLabel(kind))
                .weydaText(.labelMedium)
                .foregroundStyle(unread ? WeydaColor.primary : WeydaColor.onSurfaceVariant)
                .lineLimit(1)
            Spacer(minLength: WeydaSpace.xs)
            if !date.isEmpty {
                Text(date)
                    .weydaText(.labelSmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if unread {
                InboxUnreadDot()
            }
        }
    }
}

/// Pictogramme du type, sur une pastille ronde de sa couleur (taille qui suit le texte).
private struct NotificationKindIcon: View {
    private let kind: NotificationKind
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    init(kind: NotificationKind) {
        self.kind = kind
    }

    var body: some View {
        let tone: NotificationTone = NotificationsText.tone(for: kind)
        Image(systemName: NotificationsText.symbol(for: kind))
            .font(.body.weight(.semibold))
            .foregroundStyle(tone.content)
            .frame(width: side, height: side)
            .background(tone.container, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Textes et couleurs (logique pure, testable)

/// Famille de couleur d'une notification (pastille du pictogramme), prise dans les couples fond / contenu du thème.
nonisolated enum NotificationTone: Sendable {
    /// Messages et offres : la marque.
    case brand
    /// Annonce approuvée, offre acceptée.
    case success
    /// Annonce expirée, avis reçu.
    case warning
    /// Annonce rejetée, offre refusée.
    case danger
    /// Favoris (baisse de prix, vendu).
    case favorite
    /// Alerte de recherche, type inconnu.
    case neutral

    var container: Color {
        switch self {
        case .brand, .success: WeydaColor.primaryContainer
        case .warning: WeydaColor.tertiaryContainer
        case .danger: WeydaColor.errorContainer
        case .favorite: WeydaColor.secondaryContainer
        case .neutral: WeydaColor.surfaceContainer
        }
    }

    var content: Color {
        switch self {
        case .brand: WeydaColor.onPrimaryContainer
        case .success: WeydaPalette.success
        case .warning: WeydaColor.onTertiaryContainer
        case .danger: WeydaColor.onErrorContainer
        case .favorite: WeydaColor.onSecondaryContainer
        case .neutral: WeydaColor.onSurfaceVariant
        }
    }
}

/// Textes d'une notification — `kindLabel` (NotificationsScreen.kt), pictogrammes SF Symbols, lecture VoiceOver.
nonisolated enum NotificationsText {
    /// Libellé du type, traduit par l'app (le titre et le corps, eux, sont écrits par le serveur).
    static func kindLabel(_ kind: NotificationKind) -> String {
        switch kind {
        case .message: L10n.notificationTypeMessage
        case .review: L10n.notificationTypeReview
        case .annonceApproved: L10n.notificationTypeAnnonceApproved
        case .annonceRejected: L10n.notificationTypeAnnonceRejected
        case .annonceExpired: L10n.notificationTypeAnnonceExpired
        case .offerReceived: L10n.notificationTypeOfferReceived
        case .offerAccepted: L10n.notificationTypeOfferAccepted
        case .offerRejected: L10n.notificationTypeOfferRejected
        case .offerCounter: L10n.notificationTypeOfferCounter
        case .favoritePriceDrop: L10n.notificationTypeFavoritePriceDrop
        case .favoriteSold: L10n.notificationTypeFavoriteSold
        case .searchAlert: L10n.notificationTypeSearchAlert
        case .unknown: L10n.notificationsTitle
        }
    }

    /// Pictogramme SF Symbols (iOS 16) du type.
    static func symbol(for kind: NotificationKind) -> String {
        switch kind {
        case .message: "bubble.left.fill"
        case .review: "star.fill"
        case .annonceApproved: "checkmark.seal.fill"
        case .annonceRejected: "xmark.octagon.fill"
        case .annonceExpired: "hourglass"
        case .offerReceived: "tag.fill"
        case .offerAccepted: "hand.thumbsup.fill"
        case .offerRejected: "hand.thumbsdown.fill"
        case .offerCounter: "arrow.left.arrow.right"
        case .favoritePriceDrop: "arrow.down.circle.fill"
        case .favoriteSold: "heart.slash.fill"
        case .searchAlert: "bell.badge.fill"
        case .unknown: "bell.fill"
        }
    }

    static func tone(for kind: NotificationKind) -> NotificationTone {
        switch kind {
        case .message, .offerReceived, .offerCounter: .brand
        case .annonceApproved, .offerAccepted: .success
        case .annonceExpired, .review: .warning
        case .annonceRejected, .offerRejected: .danger
        case .favoritePriceDrop, .favoriteSold: .favorite
        case .searchAlert, .unknown: .neutral
        }
    }

    /// Ce que VoiceOver lit pour une rangée : « non lu » d'abord, puis le type, le titre, le corps, l'ancienneté.
    static func accessibilityLabel(for notification: AppNotification, now: Date = Date()) -> String {
        var parts: [String] = []
        if !notification.read {
            parts.append(L10n.chatUnread)
        }
        parts.append(kindLabel(notification.kind))
        if let title = TextCheck.nonBlank(notification.title) {
            parts.append(title)
        }
        if let detail = TextCheck.nonBlank(notification.body) {
            parts.append(detail)
        }
        if let time = TextCheck.nonBlank(Format.relativeTime(notification.createdAt, now: now)) {
            parts.append(time)
        }
        return parts.joined(separator: ", ")
    }
}
