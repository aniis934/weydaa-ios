import SwiftUI

/// Actions de la fiche, branchées par `DetailView` (ViewModel, routeur, session) — `DetailContactActions` et
/// `DetailReportActions` d'Android réunies.
struct DetailActions {
    var retry: () -> Void
    var refresh: () async -> Void
    var back: () -> Void
    var toggleFavorite: () -> Void
    var report: () -> Void
    var submitReport: (ReportReason, String) -> Void
    var openSeller: (String) -> Void
    var edit: () -> Void
    var contact: () -> Void
    var makeOffer: () -> Void
    var phone: () -> Void
    var noticeShown: () -> Void
}

/// Fiche d'une annonce, sans état — portage de `DetailScreen` (Android) : squelette, annonce introuvable, erreur
/// avec « Réessayer », puis la galerie, le prix, le titre, le lieu, les caractéristiques, la description, le
/// vendeur, ses avis, les conseils de sécurité et les annonces similaires ; favori, partage et « Signaler » dans la
/// barre de navigation, actions de contact en bas.
struct DetailScreen: View {
    private let state: DetailState
    @Binding private var isReportPresented: Bool
    private let actions: DetailActions

    init(state: DetailState, isReportPresented: Binding<Bool>, actions: DetailActions) {
        self.state = state
        self._isReportPresented = isReportPresented
        self.actions = actions
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                OfflineBanner()
            }
            .sheet(isPresented: $isReportPresented) {
                ReportSheet(
                    targetsUser: false,
                    isBusy: state.isReportBusy,
                    errorMessage: state.reportError,
                    onSubmit: actions.submitReport,
                    onCancel: { isReportPresented = false }
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.detail")
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            DetailSkeleton()
        } else if state.isNotFound {
            // Supprimée, vendue puis purgée, ou jamais publiée : « Réessayer » tournerait en boucle.
            EmptyState(
                systemImage: "info.circle",
                title: L10n.detailNotFoundTitle,
                message: L10n.detailNotFoundMessage,
                actionTitle: L10n.back,
                action: actions.back
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let listing = state.listing, !state.isError {
            loaded(listing)
        } else {
            ErrorState(message: state.errorMessage ?? L10n.errorGeneric, onRetry: actions.retry)
        }
    }

    // MARK: - Fiche chargée

    private func loaded(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailGallery(images: listing.images, isFeatured: listing.isFeatured)
                sections(of: listing)
                    .padding(.horizontal, WeydaSpace.screen)
                if !state.similar.isEmpty {
                    DetailSimilarSection(listings: state.similar)
                        .padding(.top, WeydaSpace.sm)
                }
            }
            .padding(.bottom, WeydaSpace.xxl)
        }
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor in
            await actions.refresh()
        }
        // Message bref AVANT la barre d'actions : il se pose juste au-dessus d'elle.
        .floatingNotice(state.notice, onShown: actions.noticeShown)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.hasActions {
                DetailActionBar(
                    state: state,
                    onOffer: actions.makeOffer,
                    onPhone: actions.phone,
                    onEdit: actions.edit,
                    onContact: actions.contact
                )
            }
        }
    }

    private func sections(of listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xxl) {
            let rows = state.attributeRows
            DetailSummary(listing: listing, isOwner: state.isOwner, onEdit: actions.edit)
            if !rows.isEmpty {
                DetailAttributesSection(rows: rows)
            }
            DetailDescription(text: listing.description)
            if let seller = listing.seller {
                VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                    DetailSectionTitle(L10n.detailSeller)
                    DetailSellerCard(seller: seller) {
                        actions.openSeller(seller.id)
                    }
                }
                if let reviews = state.reviews {
                    DetailReviewsSection(summary: reviews)
                }
            }
            if !state.isOwner {
                DetailSafetyTips()
            }
        }
        .padding(.top, WeydaSpace.lg)
    }

    // MARK: - Barre de navigation

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let listing = state.listing, !state.isNotFound {
                if !state.isOwner {
                    FavoriteButton(isFavorite: state.isFavorite, action: actions.toggleFavorite)
                        .accessibilityIdentifier("detail.favorite")
                }
                if let url = DetailLinks.webURL(for: listing) {
                    ShareLink(item: url, subject: Text(listing.title), message: Text(listing.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L10n.share)
                    .accessibilityIdentifier("detail.share")
                }
                if state.canReport {
                    Menu {
                        Button(action: actions.report) {
                            Label(L10n.reportAction, systemImage: "flag")
                        }
                        .accessibilityIdentifier("detail.report")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(L10n.chatMoreActions)
                    }
                    .accessibilityIdentifier("detail.menu")
                }
            }
        }
    }
}

// MARK: - En-tête

/// Bandeau d'état, prix, titre, catégorie et lieu, ancienneté, vues, expiration, référence.
private struct DetailSummary: View {
    let listing: Listing
    let isOwner: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            if listing.listingStatus != .active {
                DetailStatusBanner(status: listing.listingStatus, isOwner: isOwner, onEdit: onEdit)
                    .padding(.bottom, WeydaSpace.xs)
            }
            PriceText(price: listing.price, priceType: listing.priceType, style: .priceLarge)
            Text(listing.title)
                .weydaText(.titleLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            DetailPills(listing: listing)
                .padding(.top, WeydaSpace.xxs)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(DetailText.postedLine(listing))
                Text(DetailText.referenceLine(listing))
            }
            .weydaText(.bodySmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .padding(.top, WeydaSpace.xxs)
        }
    }
}

/// Catégorie et lieu en pastilles (Android : deux AssistChip) ; en colonne si elles ne tiennent pas côte à côte.
private struct DetailPills: View {
    let listing: Listing

    var body: some View {
        let category: String? = listing.category.map { $0.resolve() }
        let place: String? = ListingText.place(wilaya: listing.wilaya, commune: listing.commune)
        let icon: String = CategoryIcon.assetName(forSlug: listing.parentCategorySlug ?? listing.categorySlug)
        if category != nil || place != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WeydaSpace.sm) {
                    pills(category: category, place: place, icon: icon)
                }
                VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                    pills(category: category, place: place, icon: icon)
                }
            }
        }
    }

    @ViewBuilder
    private func pills(category: String?, place: String?, icon: String) -> some View {
        if let category {
            DetailPill(iconAsset: icon, text: category)
        }
        if let place {
            DetailPill(iconAsset: CategoryIcon.place, text: place)
        }
    }
}

private struct DetailPill: View {
    private let iconAsset: String
    private let text: String
    @ScaledMetric(relativeTo: .caption) private var iconSide: CGFloat = 14

    init(iconAsset: String, text: String) {
        self.iconAsset = iconAsset
        self.text = text
    }

    var body: some View {
        HStack(spacing: WeydaSpace.xs) {
            CategoryIconImage(assetName: iconAsset, size: iconSide)
                .foregroundStyle(WeydaColor.primary)
            Text(text)
                .weydaText(.labelMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(.horizontal, WeydaSpace.md)
        .padding(.vertical, WeydaSpace.xs + WeydaSpace.xxs)
        .background(WeydaColor.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(WeydaColor.outlineVariant, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Caractéristiques et description

/// Caractéristiques : libellé à gauche, valeur à droite, sur une carte.
private struct DetailAttributesSection: View {
    let rows: [DetailAttributeRow]

    var body: some View {
        if !rows.isEmpty {
            let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                DetailSectionTitle(L10n.postStepAttributes)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider()
                        }
                        DetailAttributeLine(row: row)
                    }
                }
                .padding(.horizontal, WeydaSpace.md)
                .background(WeydaColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.attributes")
        }
    }
}

private struct DetailAttributeLine: View {
    let row: DetailAttributeRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.md) {
            Text(row.label)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.value)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, WeydaSpace.sm + WeydaSpace.xxs)
        .accessibilityElement(children: .combine)
    }
}

private struct DetailDescription: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            DetailSectionTitle(L10n.detailDescription)
            Text(text)
                .weydaText(.bodyLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Chargement

/// Fantôme de la fiche : la photo 4:3, le prix, le titre et quelques lignes — rien ne saute à l'arrivée.
private struct DetailSkeleton: View {
    /// Gabarits des blocs fantômes (en points), à la taille des textes qu'ils annoncent.
    private enum Line {
        static let price: CGFloat = 140
        static let priceHeight: CGFloat = 28
        static let title: CGFloat = 18
        static let titleEnd: CGFloat = 220
        static let pill: CGFloat = 110
        static let pillWide: CGFloat = 130
        static let pillHeight: CGFloat = 30
        static let meta: CGFloat = 180
        static let metaHeight: CGFloat = 12
        static let card: CGFloat = 120
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(WeydaPalette.skeleton)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .weydaShimmer()
            VStack(alignment: .leading, spacing: WeydaSpace.md) {
                SkeletonBlock(width: Line.price, height: Line.priceHeight)
                SkeletonBlock(height: Line.title)
                SkeletonBlock(width: Line.titleEnd, height: Line.title)
                HStack(spacing: WeydaSpace.sm) {
                    SkeletonBlock(width: Line.pill, height: Line.pillHeight, radius: Line.pillHeight / 2)
                    SkeletonBlock(width: Line.pillWide, height: Line.pillHeight, radius: Line.pillHeight / 2)
                }
                SkeletonBlock(width: Line.meta, height: Line.metaHeight)
                SkeletonBlock(height: Line.card, radius: WeydaRadius.card)
                    .padding(.top, WeydaSpace.lg)
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.top, WeydaSpace.lg)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.loading)
    }
}
