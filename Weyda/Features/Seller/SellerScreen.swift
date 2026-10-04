import SwiftUI

/// Actions du profil vendeur, branchées par `SellerView` (ViewModel, routeur, session).
struct SellerActions {
    var retry: () -> Void
    var refresh: () async -> Void
    var loadMore: () -> Void
    var toggleFavorite: (Listing) -> Void
    var report: () -> Void
    var submitReport: (ReportReason, String) -> Void
    /// « Bloquer » touché (connexion demandée au visiteur, sinon confirmation).
    var requestBlock: () -> Void
    /// Blocage confirmé.
    var block: () -> Void
    var unblock: () -> Void
    /// Bannière fermée (délai écoulé ou glissement).
    var noticeShown: () -> Void
    /// « Laisser un avis » / « Modifier mon avis » touché (mon avis courant est relu, puis la feuille s'ouvre).
    var openReview: () -> Void
    /// « Publier » dans la feuille d'avis.
    var submitReview: () -> Void
    /// « Annuler » dans la feuille d'avis.
    var cancelReview: () -> Void
    /// Feuille d'avis refermée, quelle qu'en soit la raison (la note sur l'App Store se demande après).
    var reviewSheetDismissed: () -> Void
}

/// Profil public d'un vendeur, sans état — portage de `SellerScreen` (Android) : en-tête (portrait, nom, ancienneté,
/// note, badges, présentation), avis reçus et « Laisser un avis » / « Modifier mon avis » (`ReviewSheet`) pour un
/// membre éligible, puis sa vitrine d'annonces en ligne, paginée (zoom depuis la carte sur iOS 18, appui long = favori,
/// Partager). Barre : « Partager le profil », menu « Signaler cet utilisateur / Bloquer » (exigence des magasins pour
/// le contenu publié par les utilisateurs) ; « Bloquer » se confirme dans une feuille d'actions.
struct SellerScreen: View {
    private let state: SellerState
    @Binding private var isReportPresented: Bool
    @Binding private var isBlockConfirmPresented: Bool
    @Binding private var isReviewPresented: Bool
    @Binding private var reviewRating: Int
    @Binding private var reviewComment: String
    private let actions: SellerActions

    init(
        state: SellerState,
        isReportPresented: Binding<Bool>,
        isBlockConfirmPresented: Binding<Bool>,
        isReviewPresented: Binding<Bool>,
        reviewRating: Binding<Int>,
        reviewComment: Binding<String>,
        actions: SellerActions
    ) {
        self.state = state
        self._isReportPresented = isReportPresented
        self._isBlockConfirmPresented = isBlockConfirmPresented
        self._isReviewPresented = isReviewPresented
        self._reviewRating = reviewRating
        self._reviewComment = reviewComment
        self.actions = actions
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .weydaOfflineBanner()
            .sheet(isPresented: $isReportPresented) {
                ReportSheet(
                    targetsUser: true,
                    isBusy: state.isReportBusy,
                    errorMessage: state.reportError,
                    onSubmit: actions.submitReport,
                    onCancel: { isReportPresented = false }
                )
            }
            .sheet(isPresented: $isReviewPresented, onDismiss: actions.reviewSheetDismissed) {
                ReviewSheet(
                    sellerName: state.seller?.name ?? "",
                    isEditing: state.isReviewEditing,
                    rating: $reviewRating,
                    comment: $reviewComment,
                    isBusy: state.isReviewBusy,
                    errorMessage: state.reviewError,
                    onSubmit: actions.submitReview,
                    onCancel: actions.cancelReview
                )
            }
            // Feuille d'actions iOS, à la place de l'alerte d'avant (sur iPhone : `app.sheets` dans les tests).
            .confirmationDialog(L10n.chatBlockUser, isPresented: $isBlockConfirmPresented, titleVisibility: .visible) {
                Button(L10n.chatBlockUser, role: .destructive, action: actions.block)
                    .accessibilityIdentifier("seller.block.confirm")
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.chatBlockConfirmBody)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.seller")
    }

    private var title: String {
        TextCheck.nonBlank(state.seller?.name) ?? L10n.sellerProfileTitle
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            SellerSkeleton()
        } else if let seller = state.seller, state.errorMessage == nil {
            loaded(seller)
        } else {
            ErrorState(message: state.errorMessage ?? L10n.errorGeneric, onRetry: actions.retry)
        }
    }

    private func loaded(_ seller: Seller) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WeydaSpace.gutter) {
                SellerHeader(seller: seller)
                    .padding(.bottom, WeydaSpace.sm)
                if let reviews = state.reviews, !reviews.reviews.isEmpty {
                    ReviewsHeader(summary: reviews)
                        .padding(.top, WeydaSpace.sm)
                    if state.canReview {
                        reviewButton
                    }
                    ForEach(reviews.reviews) { review in
                        ReviewCard(review: review)
                    }
                } else if state.canReview {
                    // Aucun avis encore : la section s'ouvre quand même pour le membre qui peut en laisser un.
                    emptyReviewsHeader
                    reviewButton
                }
                showcaseHeader
                if state.items.isEmpty {
                    EmptyState(systemImage: "magnifyingglass", title: L10n.sellerNoListings)
                } else {
                    ForEach(state.items) { listing in
                        row(listing)
                    }
                }
                if state.isLoadingMore {
                    InlineLoader()
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.lg)
        }
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor in
            await actions.refresh()
        }
        .weydaBanner(state.banner, onAction: { _ in }, onDismiss: actions.noticeShown)
    }

    /// « Laisser un avis » / « Modifier mon avis » (Android : OutlinedButton sous l'en-tête, toute la largeur).
    private var reviewButton: some View {
        SellerReviewButton(isEditing: state.hasMyReview, isBusy: state.isReviewOpening, action: actions.openReview)
    }

    /// « Avis — Aucun avis pour le moment » : la section des avis, encore vide.
    private var emptyReviewsHeader: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
            DetailSectionTitle(L10n.reviewsTitle)
            Text(L10n.reviewsEmpty)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, WeydaSpace.sm)
    }

    /// « 14 annonces en ligne », sous un filet.
    private var showcaseHeader: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            Divider()
            DetailSectionTitle(L10n.sellerListings(state.total))
        }
        .padding(.top, WeydaSpace.sm)
    }

    /// Une annonce de la vitrine ; les deux dernières lignes affichées demandent la page suivante. Zoom depuis la carte
    /// (clé `seller.<id>`, la même dans la route) ; appui long : favori, Partager (pas « Voir le vendeur » : on y est).
    private func row(_ listing: Listing) -> some View {
        let zoomKey: String = "seller.\(listing.id)"
        let isFavorite: Bool = state.favoriteIds.contains(listing.id)
        return NavigationLink(value: AppRoute.detail(idOrSlug: listing.id, zoomSource: zoomKey)) {
            ListingRow(
                listing: listing,
                isFavorite: isFavorite,
                onFavorite: { actions.toggleFavorite(listing) }
            )
            .listingZoomSource(id: zoomKey)
        }
        .buttonStyle(.weydaCard)
        .accessibilityIdentifier("seller.row.\(listing.id)")
        .listingContextMenu(
            listing,
            menu: ListingCardMenu(listing: listing, currentUserId: state.isLoggedIn ? state.userId : nil),
            isFavorite: isFavorite,
            onFavorite: { actions.toggleFavorite(listing) },
            onSeller: nil
        )
        .onAppear {
            if SellerPaging.isNearEnd(listing.id, in: state.items) {
                actions.loadMore()
            }
        }
    }

    // MARK: - Barre de navigation

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if state.seller != nil, let url = SellerLinks.webURL(sellerId: state.sellerId) {
                ShareLink(item: url, subject: Text(title)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L10n.sellerShare)
                .accessibilityIdentifier("seller.share")
            }
            if state.canModerate {
                Menu {
                    Button(action: actions.report) {
                        Label(L10n.reportUserAction, systemImage: "flag")
                    }
                    .accessibilityIdentifier("seller.report")
                    blockButton
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(L10n.chatMoreActions)
                }
                .accessibilityIdentifier("seller.menu")
            }
        }
    }

    @ViewBuilder
    private var blockButton: some View {
        if state.isBlocked {
            Button(action: actions.unblock) {
                Label(L10n.chatUnblockUser, systemImage: "hand.raised.slash")
            }
        } else {
            Button(role: .destructive, action: actions.requestBlock) {
                Label(L10n.chatBlockUser, systemImage: "hand.raised")
            }
            .accessibilityIdentifier("seller.block")
        }
    }
}

/// Règle de pagination de la vitrine (logique pure, testée) — Android : dernier élément visible ≥ taille - 2.
nonisolated enum SellerPaging {
    static func isNearEnd(_ id: String, in items: [Listing]) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        return index >= items.count - 2
    }
}

/// Identité du vendeur : portrait, nom, ancienneté, note, badges de confiance et présentation.
private struct SellerHeader: View {
    let seller: Seller

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            HStack(alignment: .center, spacing: WeydaSpace.md) {
                SellerAvatar(url: seller.avatarUrl, size: WeydaSize.avatar)
                VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                    Text(TextCheck.ifBlank(seller.name, "—"))
                        .weydaText(.headlineSmall)
                        .foregroundStyle(WeydaColor.onBackground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let since = seller.memberSince {
                        Text(L10n.memberSince(Format.monthYear(since)))
                            .weydaText(.bodySmall)
                            .foregroundStyle(WeydaColor.onSurfaceVariant)
                    }
                    if let rating = seller.rating {
                        Text(L10n.sellerRating(rating, seller.ratingCount))
                            .weydaText(.labelLarge)
                            .foregroundStyle(WeydaColor.primary)
                            .accessibilityLabel(DetailRatingText.spoken(rating, count: seller.ratingCount))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !TrustBadge.badges(for: seller).isEmpty {
                TrustBadges(seller: seller)
            }
            if let bio = seller.bio {
                Text(bio)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seller.header")
    }
}

/// Bouton « Laisser un avis » / « Modifier mon avis » : contour vert, toute la largeur ; le libellé passe à la ligne
/// plutôt que d'être tronqué (texte agrandi) ; un indicateur pendant que mon avis courant est relu.
private struct SellerReviewButton: View {
    let isEditing: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Label(title, systemImage: isEditing ? "square.and.pencil" : "star")
                    .weydaText(.labelLarge)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel(isBusy ? L10n.loading : title)
        .accessibilityIdentifier("seller.review.open")
    }

    private var title: String {
        isEditing ? L10n.reviewEdit : L10n.reviewLeave
    }
}

/// Fantôme du profil : l'en-tête puis des lignes d'annonces (Android : ListingRowSkeletons).
private struct SellerSkeleton: View {
    /// Gabarits des blocs fantômes (en points) : le nom, puis l'ancienneté.
    private enum Line {
        static let name: CGFloat = 160
        static let nameHeight: CGFloat = 20
        static let meta: CGFloat = 120
        static let metaHeight: CGFloat = 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.lg) {
            HStack(spacing: WeydaSpace.md) {
                SkeletonBlock(width: WeydaSize.avatar, height: WeydaSize.avatar, radius: WeydaSize.avatar / 2)
                VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                    SkeletonBlock(width: Line.name, height: Line.nameHeight)
                    SkeletonBlock(width: Line.meta, height: Line.metaHeight)
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
            .accessibilityHidden(true)
            ListingRowSkeletons(count: 4)
            Spacer(minLength: 0)
        }
        .padding(.top, WeydaSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
