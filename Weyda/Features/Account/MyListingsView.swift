import SwiftUI

/// « Mes annonces » — portage de `MyListingsRoute` / `MyListingsScreen` (MyListingsScreen.kt) : onglets par statut,
/// badges, note de modération IA sous une annonce refusée, ouverture de la fiche. Les actions (modifier, vendu,
/// renouveler, supprimer) arrivent avec la phase 4 : leur logique est dans le ViewModel, pas encore leurs boutons.
struct MyListingsView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.myListingsTitle) { _ in
            MyListingsHost(model: MyListingsViewModel(users: container.users, annonces: container.annonces))
        }
    }
}

/// Possède le ViewModel ; recharge en silence à chaque retour sur l'écran.
private struct MyListingsHost: View {
    @StateObject private var model: MyListingsViewModel
    @EnvironmentObject private var router: AppRouter

    init(model: @autoclosure @escaping () -> MyListingsViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        MyListingsScreen(
            state: model.state,
            onFilter: { status in _ = model.setFilter(status) },
            onRetry: { _ = model.load() },
            onLoadMore: { _ = model.loadMore() },
            onPost: { router.select(.post) },
            onNoticeShown: { model.noticeShown() }
        )
        .refreshable { [model] in
            await model.pullToRefresh()
        }
        .onAppear {
            _ = model.appear()
        }
    }
}

/// Écran sans état : puces de statut fixées en haut, puis la liste (squelettes, erreur, vide, annonces).
struct MyListingsScreen: View {
    private let state: MyListingsState
    private let onFilter: (ListingStatus?) -> Void
    private let onRetry: () -> Void
    private let onLoadMore: () -> Void
    private let onPost: () -> Void
    private let onNoticeShown: () -> Void

    /// La page suivante se demande quand l'une des 4 dernières annonces paraît (Android : même seuil).
    private static let prefetchDistance = 4

    init(
        state: MyListingsState,
        onFilter: @escaping (ListingStatus?) -> Void,
        onRetry: @escaping () -> Void,
        onLoadMore: @escaping () -> Void,
        onPost: @escaping () -> Void,
        onNoticeShown: @escaping () -> Void
    ) {
        self.state = state
        self.onFilter = onFilter
        self.onRetry = onRetry
        self.onLoadMore = onLoadMore
        self.onPost = onPost
        self.onNoticeShown = onNoticeShown
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    OfflineBanner()
                    MyListingsFilterBar(selected: state.filter, onSelect: onFilter)
                }
                .background(WeydaColor.background)
            }
            .navigationTitle(L10n.myListingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .accountNotice(state.notice, onShown: onNoticeShown)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.myListings")
    }

    /// Chaque état a sa propre vue défilante : un nouveau filtre repart du haut de la liste (Android le
    /// faisait à la main, `scrollToItem(0)`).
    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            ScrollView {
                ListingRowSkeletons()
            }
            .scrollDisabled(true)
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: onRetry)
        } else if state.items.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        let trailing: Set<String> = Set(state.items.suffix(Self.prefetchDistance).map(\.id))
        return ScrollView {
            LazyVStack(spacing: WeydaSpace.gutter) {
                ForEach(state.items) { listing in
                    NavigationLink(value: AppRoute.detail(idOrSlug: listing.id)) {
                        MyListingRow(listing: listing)
                    }
                    .buttonStyle(.weydaCard)
                    .accessibilityIdentifier("myListings.row.\(listing.id)")
                    .onAppear {
                        if trailing.contains(listing.id) {
                            onLoadMore()
                        }
                    }
                }
                if state.isLoadingMore {
                    InlineLoader()
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.md)
        }
    }

    /// Aucune annonce : sans filtre, une invitation à déposer ; avec un filtre, le retour à « Toutes ». Défilant,
    /// pour que « tirer pour rafraîchir » reste possible.
    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                emptyMessage
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private var emptyMessage: some View {
        if state.filter == nil {
            EmptyState(
                systemImage: AppRoute.myListings.symbol,
                title: L10n.emptyResults,
                actionTitle: L10n.postTitle,
                action: onPost
            )
        } else {
            EmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: L10n.emptyResults,
                actionTitle: L10n.filterAll,
                action: { onFilter(nil) }
            )
        }
    }
}

// MARK: - Puces de statut

/// Un onglet de statut (nil = toutes), dans l'ordre d'Android.
nonisolated struct MyListingsFilter: Identifiable, Hashable, Sendable {
    let id: String
    let status: ListingStatus?

    static let all: [MyListingsFilter] = [
        MyListingsFilter(id: "all", status: nil),
        MyListingsFilter(id: "active", status: .active),
        MyListingsFilter(id: "pending", status: .pending),
        MyListingsFilter(id: "sold", status: .sold),
        MyListingsFilter(id: "expired", status: .expired),
        MyListingsFilter(id: "rejected", status: .rejected),
    ]

    var title: String {
        guard let status else { return L10n.filterAll }
        return MyListingsText.statusTitle(status)
    }
}

private struct MyListingsFilterBar: View {
    let selected: ListingStatus?
    let onSelect: (ListingStatus?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeydaSpace.sm) {
                ForEach(MyListingsFilter.all) { filter in
                    WeydaChip(
                        title: filter.title,
                        isSelected: filter.status == selected,
                        action: { onSelect(filter.status) }
                    )
                    .accessibilityIdentifier("myListings.filter.\(filter.id)")
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.xs)
        }
    }
}

// MARK: - Ligne d'annonce

/// Textes d'une annonce de « Mes annonces ». Logique pure, testable.
nonisolated enum MyListingsText {
    static func statusTitle(_ status: ListingStatus) -> String {
        switch status {
        case .active: L10n.statusActive
        case .pending: L10n.statusPending
        case .sold: L10n.statusSold
        case .expired: L10n.statusExpired
        case .rejected: L10n.statusRejected
        }
    }

    /// Motifs de modération à montrer (3 au plus) : seulement sur une annonce qui n'est pas en ligne.
    static func moderationReasons(for listing: Listing) -> [String] {
        guard listing.listingStatus != .active, let verdict = listing.moderation else { return [] }
        let reasons = verdict.reasons.filter { !TextCheck.isBlank($0) }
        return Array(reasons.prefix(3))
    }

    /// « 128 vues · il y a 3 j » (les morceaux vides disparaissent).
    static func meta(for listing: Listing, now: Date = Date()) -> String {
        let age: String? = TextCheck.nonBlank(Format.relativeTime(listing.createdAt, now: now))
        return [L10n.detailViews(listing.views), age].compactMap { $0 }.joined(separator: " · ")
    }

    /// Ce que VoiceOver lit pour une ligne : statut, titre, prix, vues et ancienneté, motifs de modération.
    static func accessibilityLabel(for listing: Listing, now: Date = Date()) -> String {
        var parts: [String] = [statusTitle(listing.listingStatus), listing.title, Format.price(listing.price, type: listing.priceType)]
        if let mention = Format.negotiableLabel(price: listing.price, type: listing.priceType) {
            parts.append(mention)
        }
        parts.append(meta(for: listing, now: now))
        let reasons = moderationReasons(for: listing)
        if !reasons.isEmpty {
            parts.append(L10n.moderationReason)
            parts.append(contentsOf: reasons)
        }
        return parts.joined(separator: ", ")
    }
}

/// Carte d'une annonce du membre : vignette, statut, titre, prix, vues et ancienneté ; note de modération dessous.
/// Une seule entité pour VoiceOver.
private struct MyListingRow: View {
    let listing: Listing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        let reasons = MyListingsText.moderationReasons(for: listing)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: WeydaSpace.md) {
                MyListingThumbnail(listing: listing)
                details
            }
            .padding(WeydaSpace.sm)
            if !reasons.isEmpty {
                MyListingModerationNote(reasons: reasons)
            }
        }
        .background(WeydaColor.surface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MyListingsText.accessibilityLabel(for: listing))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            MyListingStatusBadge(status: listing.listingStatus)
            Text(listing.title)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            PriceText(price: listing.price, priceType: listing.priceType)
            Text(MyListingsText.meta(for: listing))
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Vignette 116 × 92 (comme `ListingRow`) ; sans photo, un pictogramme sur le fond d'attente.
private struct MyListingThumbnail: View {
    let listing: Listing

    var body: some View {
        Group {
            if listing.coverImage == nil {
                ZStack {
                    WeydaPalette.imagePlaceholder
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                }
            } else {
                RemoteImage(urlString: listing.coverThumbnail, fallbackURLString: listing.coverImage)
            }
        }
        .frame(width: WeydaSize.rowThumbWidth, height: WeydaSize.rowThumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Pastille de statut — couples fond / texte du thème (Android : un blanc en dur tombait à 1,7:1 sur les teintes
/// claires du mode sombre).
private struct MyListingStatusBadge: View {
    let status: ListingStatus

    var body: some View {
        Text(MyListingsText.statusTitle(status))
            .weydaText(.labelSmall)
            .fontWeight(.bold)
            .textCase(.uppercase)
            .foregroundStyle(content)
            .lineLimit(1)
            .padding(.horizontal, WeydaSpace.xs + WeydaSpace.xxs)
            .padding(.vertical, WeydaSpace.xxs)
            .background(container, in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
    }

    private var container: Color {
        switch status {
        case .active: WeydaColor.primary
        case .pending: WeydaColor.tertiary
        case .sold, .expired: WeydaColor.surfaceContainerHigh
        case .rejected: WeydaColor.error
        }
    }

    private var content: Color {
        switch status {
        case .active: WeydaColor.onPrimary
        case .pending: WeydaColor.onTertiary
        case .sold, .expired: WeydaColor.onSurfaceVariant
        case .rejected: WeydaColor.onError
        }
    }
}

/// « Motif de la modération » et ses raisons (3 au plus), sous une annonce refusée, en attente ou expirée.
private struct MyListingModerationNote: View {
    private let reasons: [String]
    /// Puce centrée sur la première ligne du motif, quelle que soit la taille du texte.
    @ScaledMetric(relativeTo: .caption) private var bulletTop: CGFloat = 6

    private static let bulletSide: CGFloat = 4

    init(reasons: [String]) {
        self.reasons = reasons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            HStack(spacing: WeydaSpace.xs) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L10n.moderationReason)
                    .weydaText(.labelMedium)
            }
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            ForEach(Array(reasons.enumerated()), id: \.offset) { item in
                HStack(alignment: .top, spacing: WeydaSpace.sm) {
                    Circle()
                        .fill(WeydaColor.onSurfaceVariant)
                        .frame(width: Self.bulletSide, height: Self.bulletSide)
                        .padding(.top, bulletTop)
                    Text(item.element)
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.onSurface)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, WeydaSpace.md)
        .padding(.vertical, WeydaSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surfaceContainer)
    }
}
