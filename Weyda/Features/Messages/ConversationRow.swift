import SwiftUI

// Rangée d'une conversation (onglet Messages) et briques partagées par les écrans de la boîte de réception
// (conversations, notifications, utilisateurs bloqués) : avatar, pastille « non lu », squelettes, état défilant.
// Noms préfixés « Inbox » / « Conversation » : aucun ne croise ceux du fil (`Chat…`).

// MARK: - Textes (logique pure, testable)

/// Aperçu du dernier message d'une rangée : le texte, et s'il s'agit d'une mention de l'app (message supprimé,
/// interlocuteur bloqué, conversation vide) plutôt que d'un texte écrit par quelqu'un — affichée en italique.
nonisolated struct ConversationRowPreview: Equatable, Sendable {
    let text: String
    let isPlaceholder: Bool
    /// Pictogramme posé devant (interlocuteur bloqué), nil sinon.
    let symbol: String?
}

/// Textes d'une conversation de la liste — portage de `lastMessagePreview` et des libellés de `ConversationRow`
/// (ConversationsScreen.kt).
nonisolated enum ConversationsText {
    /// Pictogramme d'un aperçu masqué (interlocuteur bloqué).
    static let blockedSymbol = "hand.raised.fill"

    /// Nom de l'interlocuteur ; compte supprimé (nom vide) → « Compte supprimé ».
    static func partnerName(_ conversation: Conversation, userId: String) -> String {
        TextCheck.ifBlank(conversation.partner(userId).name, L10n.chatDeletedUser)
    }

    /// Aperçu : « Utilisateur bloqué » à la place du contenu d'un interlocuteur bloqué (App Store 1.2) ; sinon le
    /// dernier message (« Message supprimé » s'il l'a été), préfixé « Vous : » quand il est de moi ; sans message,
    /// l'invitation à démarrer la conversation.
    static func preview(for conversation: Conversation, userId: String, isBlocked: Bool) -> ConversationRowPreview {
        if isBlocked {
            return ConversationRowPreview(text: L10n.inboxBlockedPreview, isPlaceholder: true, symbol: blockedSymbol)
        }
        guard let last = conversation.lastMessage else {
            return ConversationRowPreview(text: L10n.chatStartConversation, isPlaceholder: true, symbol: nil)
        }
        let body: String = last.isDeleted ? L10n.chatMessageDeleted : last.content
        let text: String = last.senderId == userId ? L10n.chatLastMessageYou(body) : body
        return ConversationRowPreview(text: text, isPlaceholder: last.isDeleted, symbol: nil)
    }

    /// Date affichée : celle de la conversation (dernier mouvement), à défaut celle du dernier message.
    static func date(of conversation: Conversation) -> Date? {
        conversation.updatedAt ?? conversation.lastMessage?.createdAt
    }

    /// Recherche locale : celle du modèle (nom, annonce, dernier message), sans le message d'un interlocuteur bloqué.
    static func matches(_ conversation: Conversation, query: String, userId: String, isBlocked: Bool) -> Bool {
        guard isBlocked else { return conversation.matches(query: query, userId: userId) }
        var hidden = conversation
        hidden.lastMessage = nil
        return hidden.matches(query: query, userId: userId)
    }

    /// Ce que VoiceOver lit pour une rangée : « non lu » d'abord (le gras et la pastille ne se voient pas), puis
    /// l'interlocuteur, l'annonce, l'aperçu et l'ancienneté.
    static func accessibilityLabel(
        for conversation: Conversation,
        userId: String,
        isBlocked: Bool,
        now: Date = Date()
    ) -> String {
        var parts: [String] = []
        if conversation.isUnreadFor(userId) {
            parts.append(L10n.chatUnread)
        }
        parts.append(partnerName(conversation, userId: userId))
        if let title = TextCheck.nonBlank(conversation.annonce?.title) {
            parts.append(title)
        }
        parts.append(preview(for: conversation, userId: userId, isBlocked: isBlocked).text)
        if let time = TextCheck.nonBlank(Format.relativeTime(date(of: conversation), now: now)) {
            parts.append(time)
        }
        return parts.joined(separator: ", ")
    }
}

/// Aides communes de la boîte de réception.
nonisolated enum InboxText {
    /// Initiale d'un nom pour l'avatar (« Amina K. » → « A ») ; nom absent ou blanc → nil (silhouette).
    static func initial(of name: String?) -> String? {
        guard let trimmed = TextCheck.nonBlank(name)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let first = trimmed.first else { return nil }
        return String(first).uppercased()
    }
}

// MARK: - Rangée

/// Une conversation : avatar (pastille verte si non lue), nom et ancienneté, titre de l'annonce, aperçu du
/// dernier message sur deux lignes, vignette de l'annonce. Non lue : nom et aperçu en gras, date en vert. Vue pure :
/// l'écran l'enveloppe dans un bouton (ouverture du fil) et porte le glissement pour archiver.
struct ConversationRow: View {
    private let conversation: Conversation
    private let userId: String
    private let isBlocked: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    static let avatarSide: CGFloat = 52
    static let thumbSide: CGFloat = 52

    init(conversation: Conversation, userId: String, isBlocked: Bool) {
        self.conversation = conversation
        self.userId = userId
        self.isBlocked = isBlocked
    }

    var body: some View {
        let partner: ConversationPartner = conversation.partner(userId)
        let unread: Bool = conversation.isUnreadFor(userId)
        HStack(alignment: .center, spacing: WeydaSpace.md) {
            InboxAvatar(name: TextCheck.nonBlank(partner.name), url: partner.avatarUrl, size: Self.avatarSide, showsUnreadDot: unread)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                ConversationRowHeader(
                    name: ConversationsText.partnerName(conversation, userId: userId),
                    date: Format.relativeTime(ConversationsText.date(of: conversation)),
                    unread: unread
                )
                if let title = TextCheck.nonBlank(conversation.annonce?.title) {
                    Text(title)
                        .weydaText(.labelMedium)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .lineLimit(listingTitleLines)
                }
                ConversationPreviewLine(
                    preview: ConversationsText.preview(for: conversation, userId: userId, isBlocked: isBlocked),
                    unread: unread
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // En très grand texte, la vignette céderait trop de place au texte : elle s'efface.
            if !typeSize.isAccessibilitySize, let imageUrl = TextCheck.nonBlank(conversation.annonce?.imageUrl) {
                ConversationListingThumb(url: imageUrl)
            }
        }
        .padding(.vertical, WeydaSpace.xxs)
        .contentShape(Rectangle())
    }

    /// Titre de l'annonce : une ligne aux tailles normales, deux en très grand texte.
    private var listingTitleLines: Int {
        typeSize.isAccessibilitySize ? 2 : 1
    }
}

/// Nom de l'interlocuteur (gras si non lue) et ancienneté du dernier message (verte si non lue). Très grand texte :
/// l'ancienneté passe SOUS le nom — sur la même ligne, le nom se tronquait (« Ami… », « Sofian… »).
private struct ConversationRowHeader: View {
    private let name: String
    private let date: String
    private let unread: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(name: String, date: String, unread: Bool) {
        self.name = name
        self.date = date
        self.unread = unread
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                nameText
                    .lineLimit(2)
                if !date.isEmpty {
                    dateText
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                nameText
                    .lineLimit(1)
                Spacer(minLength: WeydaSpace.xs)
                if !date.isEmpty {
                    dateText
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
    }

    private var nameText: some View {
        Text(name)
            .weydaText(.titleMedium)
            .fontWeight(unread ? Font.Weight.bold : Font.Weight.semibold)
            .foregroundStyle(WeydaColor.onSurface)
    }

    private var dateText: some View {
        Text(date)
            .weydaText(.labelMedium)
            .foregroundStyle(unread ? WeydaColor.primary : WeydaColor.onSurfaceVariant)
    }
}

/// Aperçu du dernier message, deux lignes au plus ; mention de l'app en italique (pictogramme devant pour un
/// interlocuteur bloqué).
private struct ConversationPreviewLine: View {
    let preview: ConversationRowPreview
    let unread: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.xs) {
            if let symbol = preview.symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            styledText
                .weydaText(.bodyMedium)
                .fontWeight(unread && !preview.isPlaceholder ? Font.Weight.semibold : Font.Weight.regular)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(unread && !preview.isPlaceholder ? WeydaColor.onSurface : WeydaColor.onSurfaceVariant)
    }

    private var styledText: Text {
        let text = Text(preview.text)
        return preview.isPlaceholder ? text.italic() : text
    }
}

/// Vignette de l'annonce de la conversation (miniature `_thumb`, repli sur la photo entière).
private struct ConversationListingThumb: View {
    let url: String

    var body: some View {
        RemoteImage(urlString: thumbnailUrl(url), fallbackURLString: url)
            .frame(width: ConversationRow.thumbSide, height: ConversationRow.thumbSide)
            .background(WeydaPalette.imagePlaceholder)
            .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Briques partagées

/// Avatar rond : photo du profil, sinon l'initiale sur le vert pâle de la marque, sinon (compte supprimé) une
/// silhouette — `PartnerAvatar` (Android). Pastille verte facultative au coin haut (« non lu »), cerclée du fond.
struct InboxAvatar: View {
    private let name: String?
    private let url: String?
    private let size: CGFloat
    private let showsUnreadDot: Bool

    init(name: String?, url: String?, size: CGFloat, showsUnreadDot: Bool = false) {
        self.name = name
        self.url = url
        self.size = size
        self.showsUnreadDot = showsUnreadDot
    }

    var body: some View {
        Circle()
            .fill(WeydaColor.primaryContainer)
            .overlay {
                portrait
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                if showsUnreadDot {
                    InboxUnreadDot(side: InboxUnreadDot.avatarSide)
                        .overlay {
                            Circle().strokeBorder(WeydaColor.surface, lineWidth: 2)
                        }
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var portrait: some View {
        if let url = TextCheck.nonBlank(url) {
            RemoteImage(urlString: url)
        } else if let initial = InboxText.initial(of: name) {
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(WeydaColor.onPrimaryContainer)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(WeydaColor.onPrimaryContainer)
        }
    }
}

/// Pastille « non lu » : un point vert, discret (lu par VoiceOver via l'étiquette de la rangée, pas ici).
struct InboxUnreadDot: View {
    private let side: CGFloat

    /// Pastille posée sur un avatar ; pastille d'une rangée de notification.
    static let avatarSide: CGFloat = 14
    static let rowSide: CGFloat = 10

    init(side: CGFloat = InboxUnreadDot.rowSide) {
        self.side = side
    }

    var body: some View {
        Circle()
            .fill(WeydaColor.primary)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Fantômes de rangées (avatar rond, deux lignes, vignette facultative) pendant le premier chargement, lus une
/// fois « Chargement… » par VoiceOver.
struct InboxRowSkeletons: View {
    private let count: Int
    private let showsThumb: Bool

    init(count: Int = 7, showsThumb: Bool = true) {
        self.count = count
        self.showsThumb = showsThumb
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<max(count, 0), id: \.self) { _ in
                    InboxRowSkeleton(showsThumb: showsThumb)
                }
            }
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.loading)
    }
}

private struct InboxRowSkeleton: View {
    let showsThumb: Bool

    private static let titleWidth: CGFloat = 140
    private static let lineWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: WeydaSpace.md) {
            SkeletonBlock(width: ConversationRow.avatarSide, height: ConversationRow.avatarSide, radius: ConversationRow.avatarSide / 2)
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                SkeletonBlock(width: Self.titleWidth, height: 12)
                SkeletonBlock(height: 10)
                SkeletonBlock(width: Self.lineWidth, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsThumb {
                SkeletonBlock(width: ConversationRow.thumbSide, height: ConversationRow.thumbSide, radius: WeydaRadius.thumb)
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.vertical, WeydaSpace.md)
    }
}

/// État plein écran (vide, aucun résultat) placé dans une vue défilante : « tirer pour rafraîchir » reste possible
/// et un très grand texte n'est jamais rogné.
struct InboxScrollableState<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}
