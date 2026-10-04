import SwiftUI
import UIKit

/// Actions de la fiche, branchées par `DetailView` (ViewModel, routeur, session) — `DetailContactActions` et
/// `DetailReportActions` d'Android réunies.
struct DetailActions {
    var retry: () -> Void
    var refresh: () async -> Void
    var back: () -> Void
    var toggleFavorite: () -> Void
    /// Cœur d'une annonce similaire (menu d'appui long de sa carte).
    var toggleSimilarFavorite: (Listing) -> Void
    var report: () -> Void
    var submitReport: (ReportReason, String) -> Void
    var openSeller: (String) -> Void
    var edit: () -> Void
    var contact: () -> Void
    var makeOffer: () -> Void
    /// Bouton du numéro : connexion demandée au visiteur, sinon révélation.
    var phone: () -> Void
    /// Menu du numéro révélé : appeler, copier le numéro.
    var callPhone: () -> Void
    var copyPhone: () -> Void
    /// Bannière fermée (délai écoulé ou glissement).
    var noticeShown: () -> Void
}

/// Fiche d'une annonce, sans état métier — portage de `DetailScreen` (Android) : squelette, annonce introuvable,
/// erreur avec « Réessayer », puis la galerie, le prix, le titre, le lieu, les caractéristiques, la description, le
/// vendeur, ses avis, les conseils de sécurité et les annonces similaires ; favori, partage et « Signaler » dans la
/// barre de navigation, actions de contact en bas.
///
/// Barre du haut : la barre SYSTÈME (retour par glissement, verre d'iOS 26), transparente au-dessus de la photo — la
/// galerie passe sous la barre d'état, un voile sombre garde les boutons lisibles. Photo dépassée par le défilement :
/// barre visible et titre de l'annonce au centre (seul état local de l'écran : `isCollapsed`).
struct DetailScreen: View {
    private let state: DetailState
    private let sharePreview: UIImage?
    @Binding private var isReportPresented: Bool
    private let actions: DetailActions
    /// La photo est passée sous la barre : barre visible, titre de l'annonce. N'est écrit que quand il change.
    @State private var isCollapsed: Bool = false

    init(state: DetailState, sharePreview: UIImage?, isReportPresented: Binding<Bool>, actions: DetailActions) {
        self.state = state
        self.sharePreview = sharePreview
        self._isReportPresented = isReportPresented
        self.actions = actions
    }

    var body: some View {
        // Largeur de l'écran et hauteur des barres du haut (barre d'état + barre de navigation) : la photo, qui passe
        // dessous, en tient compte (voile, pastille « À la une », seuil de la barre repliée).
        GeometryReader { proxy in
            content(header: DetailHeaderMetrics(width: proxy.size.width, topInset: proxy.safeAreaInsets.top))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeydaColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .toolbarBackground(barBackground, for: .navigationBar)
        // Au-dessus de la photo (voile sombre) : barre d'état claire ; barre repliée : l'apparence du système.
        .toolbarColorScheme(barColorScheme, for: .navigationBar)
        .weydaAnimation(.easeInOut(duration: WeydaDuration.medium), value: isBarCollapsed)
        .onChange(of: state.isLoading) { loading in
            // Nouveau chargement : la fiche repart du haut (photo sous la barre transparente).
            if loading && isCollapsed {
                isCollapsed = false
            }
        }
        .weydaOfflineBanner()
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
    private func content(header: DetailHeaderMetrics) -> some View {
        if state.isLoading {
            // Le squelette passe sous les barres comme la fiche chargée : rien ne saute à l'arrivée.
            DetailSkeleton(topInset: header.topInset)
                .ignoresSafeArea(edges: .top)
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
            loaded(listing, header: header)
        } else {
            ErrorState(message: state.errorMessage ?? L10n.errorGeneric, onRetry: actions.retry)
        }
    }

    // MARK: - Barre du haut

    /// Fiche chargée (pas en chargement, ni en erreur).
    private var isLoadedContent: Bool {
        state.listing != nil && !state.isLoading && !state.isError && !state.isNotFound
    }

    /// La photo (ou son fantôme) occupe le haut de l'écran, sous les barres.
    private var showsPhotoHeader: Bool {
        state.isLoading || isLoadedContent
    }

    private var isBarCollapsed: Bool {
        isCollapsed && isLoadedContent
    }

    /// Transparente au-dessus de la photo, visible (matériau du système) une fois la photo dépassée ; automatique sur
    /// les écrans d'erreur (aucune photo dessous).
    private var barBackground: Visibility {
        guard showsPhotoHeader else { return .automatic }
        return isBarCollapsed ? .visible : .hidden
    }

    private var barColorScheme: ColorScheme? {
        guard showsPhotoHeader && !isBarCollapsed else { return nil }
        return ColorScheme.dark
    }

    /// iOS 26 : pastilles blanches derrière les boutons de la barre tant qu'ils sont posés sur la photo (comme le cœur
    /// des cartes, `FavoriteButton(onPhoto: true)`).
    private var usesPhotoPills: Bool {
        if #available(iOS 26.0, *) {
            return showsPhotoHeader && !isBarCollapsed
        }
        return false
    }

    private func setCollapsed(_ collapsed: Bool) {
        if isCollapsed != collapsed {
            isCollapsed = collapsed
        }
    }

    // MARK: - Fiche chargée

    private func loaded(_ listing: Listing, header: DetailHeaderMetrics) -> some View {
        let threshold: CGFloat = header.collapseThreshold
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailScrollProbe(threshold: threshold, onCollapse: { (collapsed: Bool) in setCollapsed(collapsed) })
                DetailGallery(images: listing.images, isFeatured: listing.isFeatured, topInset: header.topInset)
                sections(of: listing)
                    .padding(.horizontal, WeydaSpace.screen)
                if !state.similar.isEmpty {
                    DetailSimilarSection(
                        listings: state.similar,
                        favoriteIds: state.favoriteIds,
                        currentUserId: state.isLoggedIn ? state.userId : nil,
                        onFavorite: actions.toggleSimilarFavorite,
                        onSeller: actions.openSeller
                    )
                    .padding(.top, WeydaSpace.sm)
                }
            }
            .padding(.bottom, WeydaSpace.xxl)
        }
        .coordinateSpace(name: DetailScrollSpace.name)
        .modifier(DetailScrollObserver(threshold: threshold, onCollapse: { (collapsed: Bool) in setCollapsed(collapsed) }))
        // La galerie passe sous la barre d'état et la barre de navigation (transparente au-dessus de la photo).
        .ignoresSafeArea(edges: .top)
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor in
            await actions.refresh()
        }
        // Bannière AVANT la barre d'actions : elle se pose juste au-dessus d'elle.
        .weydaBanner(state.banner, onAction: { _ in }, onDismiss: actions.noticeShown)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.hasActions {
                DetailActionBar(
                    state: state,
                    onOffer: actions.makeOffer,
                    onPhone: actions.phone,
                    onCall: actions.callPhone,
                    onCopyPhone: actions.copyPhone,
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
        // Titre de l'annonce, seulement la photo dépassée (VoiceOver ne le lit pas deux fois au-dessus du titre).
        ToolbarItem(placement: .principal) {
            collapsedTitle
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let listing = state.listing, !state.isNotFound {
                if !state.isOwner {
                    FavoriteButton(isFavorite: state.isFavorite, onPhoto: usesPhotoPills, action: actions.toggleFavorite)
                        .accessibilityIdentifier("detail.favorite")
                }
                if let url = DetailLinks.webURL(for: listing) {
                    DetailShareButton(
                        url: url,
                        title: listing.title,
                        message: DetailText.shareMessage(listing),
                        preview: sharePreview,
                        onPhoto: usesPhotoPills
                    )
                }
                if state.canReport {
                    Menu {
                        Button(action: actions.report) {
                            Label(L10n.reportAction, systemImage: "flag")
                        }
                        .accessibilityIdentifier("detail.report")
                    } label: {
                        DetailToolbarGlyph(systemName: usesPhotoPills ? "ellipsis" : "ellipsis.circle", onPhoto: usesPhotoPills)
                            .accessibilityLabel(L10n.chatMoreActions)
                    }
                    .accessibilityIdentifier("detail.menu")
                }
            }
        }
    }

    @ViewBuilder
    private var collapsedTitle: some View {
        if isBarCollapsed, let listing = state.listing {
            Text(listing.title)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detail.barTitle")
        }
    }
}

// MARK: - Barre du haut : mesures, défilement, boutons

/// Mesures de l'en-tête photo (logique pure) : largeur de l'écran et hauteur des barres du haut (barre d'état +
/// barre de navigation), que la photo 4:3 passe dessous.
nonisolated struct DetailHeaderMetrics: Equatable, Sendable {
    let width: CGFloat
    let topInset: CGFloat

    /// Défilement au-delà duquel la photo est entièrement passée sous la barre : hauteur de la photo (largeur × 3/4)
    /// moins les barres du haut (barre d'état et ~44 pt de barre de navigation).
    var collapseThreshold: CGFloat {
        max(width * 3.0 / 4.0 - topInset, 1)
    }
}

/// Repère nommé du `ScrollView` de la fiche (lecture du défilement sur iOS 16-17).
private nonisolated enum DetailScrollSpace {
    static let name: String = "detail.scroll"
}

/// iOS 16-17 : lecture du défilement par un repère de hauteur nulle en tête du contenu (position dans le repère nommé
/// du `ScrollView`). N'appelle `onCollapse` que quand le booléen change. Rien sur iOS 18+ (`DetailScrollObserver`).
private struct DetailScrollProbe: View {
    let threshold: CGFloat
    let onCollapse: (Bool) -> Void

    var body: some View {
        if #available(iOS 18.0, *) {
            EmptyView()
        } else {
            GeometryReader { proxy in
                let space: CoordinateSpace = .named(DetailScrollSpace.name)
                let collapsed: Bool = -proxy.frame(in: space).minY > threshold
                Color.clear
                    .onChange(of: collapsed) { value in
                        onCollapse(value)
                    }
            }
            .frame(height: 0)
            .accessibilityHidden(true)
        }
    }
}

/// iOS 18+ : `onScrollGeometryChange` — décalage depuis la position de repos (marges du contenu comprises) comparé au
/// seuil ; l'action ne part que quand le booléen change.
private struct DetailScrollObserver: ViewModifier {
    let threshold: CGFloat
    let onCollapse: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            let limit: CGFloat = threshold
            content.onScrollGeometryChange(for: Bool.self) { (geometry: ScrollGeometry) -> Bool in
                geometry.contentOffset.y + geometry.contentInsets.top > limit
            } action: { (_: Bool, collapsed: Bool) in
                onCollapse(collapsed)
            }
        } else {
            content
        }
    }
}

/// « Partager » de la fiche : lien du site, titre et prix ; aperçu avec la photo de couverture quand elle est prête
/// (`DetailViewModel.sharePreview`), le titre seul sinon.
private struct DetailShareButton: View {
    let url: URL
    let title: String
    let message: String
    let preview: UIImage?
    let onPhoto: Bool

    var body: some View {
        shareLink
            .accessibilityLabel(L10n.share)
            .accessibilityIdentifier("detail.share")
    }

    @ViewBuilder
    private var shareLink: some View {
        if let preview {
            ShareLink(
                item: url,
                subject: Text(title),
                message: Text(message),
                preview: SharePreview(title, image: Image(uiImage: preview))
            ) {
                DetailToolbarGlyph(systemName: "square.and.arrow.up", onPhoto: onPhoto)
            }
        } else {
            ShareLink(item: url, subject: Text(title), message: Text(message), preview: SharePreview(title)) {
                DetailToolbarGlyph(systemName: "square.and.arrow.up", onPhoto: onPhoto)
            }
        }
    }
}

/// Pictogramme d'un bouton de la barre ; posé sur la photo (iOS 26), sur une pastille blanche cerclée, comme le cœur
/// des cartes (`FavoriteButton(onPhoto: true)`) — lisible sur n'importe quelle photo.
private struct DetailToolbarGlyph: View {
    let systemName: String
    let onPhoto: Bool

    var body: some View {
        if onPhoto {
            Image(systemName: systemName)
                .font(.system(size: DetailToolbarPill.glyph, weight: .semibold))
                .foregroundStyle(DetailToolbarPill.ink)
                .frame(width: DetailToolbarPill.side, height: DetailToolbarPill.side)
                .background {
                    Circle()
                        .fill(DetailToolbarPill.fill)
                        .overlay {
                            Circle().strokeBorder(DetailToolbarPill.stroke, lineWidth: 1)
                        }
                }
        } else {
            Image(systemName: systemName)
        }
    }
}

/// Pastille des boutons de la barre sur photo : les valeurs de celle du cœur des cartes (`FavoritePill`).
private nonisolated enum DetailToolbarPill {
    static let side: CGFloat = WeydaSize.touchTarget - WeydaSpace.md
    static let glyph: CGFloat = WeydaSize.icon - WeydaSpace.xs
    static let fill = Color(rgb: WeydaRamp.white, opacity: 0.92)
    static let stroke = Color(rgb: WeydaRamp.slate200, opacity: 0.9)
    static let ink = Color(rgb: WeydaRamp.slate700)
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
        let artwork = CategoryArtworkContent.category(slug: listing.parentCategorySlug ?? listing.categorySlug)
        if category != nil || place != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WeydaSpace.sm) {
                    pills(category: category, place: place, artwork: artwork)
                }
                VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                    pills(category: category, place: place, artwork: artwork)
                }
            }
        }
    }

    @ViewBuilder
    private func pills(category: String?, place: String?, artwork: CategoryArtworkContent) -> some View {
        if let category {
            DetailPill(leading: .artwork(artwork), text: category)
        }
        if let place {
            DetailPill(leading: .glyph(CategoryIcon.place), text: place)
        }
    }
}

/// Pastille de catégorie (l'illustration en disque, concentrique à la capsule) ou de lieu (pictogramme) : une ligne
/// aux tailles normales ; en très grand texte, le lieu entier (« Bab Ezzouar, Alger ») passe à la ligne plutôt que
/// d'être tronqué. Les deux pastilles ont la même hauteur (disque 20 + 2 × 4 = ligne 16 + 2 × 6).
private struct DetailPill: View {
    enum Leading {
        case artwork(CategoryArtworkContent)
        case glyph(String)
    }

    private let leading: Leading
    private let text: String
    @ScaledMetric(relativeTo: .caption) private var iconSide: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var artworkSide: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(leading: Leading, text: String) {
        self.leading = leading
        self.text = text
    }

    var body: some View {
        HStack(spacing: contentSpacing) {
            leadingView
            Text(text)
                .weydaText(.labelMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .lineLimit(textLineLimit)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, WeydaSpace.md)
        .padding(.vertical, verticalInset)
        .background(WeydaColor.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(WeydaColor.outlineVariant, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .artwork(let artwork):
            CategoryArtwork(artwork, size: artworkSide, outline: .circle)
        case .glyph(let name):
            CategoryIconImage(assetName: name, size: iconSide)
                .foregroundStyle(WeydaColor.primary)
        }
    }

    private var isArtwork: Bool {
        if case .artwork = leading { return true }
        return false
    }

    private var contentSpacing: CGFloat {
        isArtwork ? WeydaSpace.xs + WeydaSpace.xxs : WeydaSpace.xs
    }

    private var leadingInset: CGFloat {
        isArtwork ? WeydaSpace.xs : WeydaSpace.md
    }

    private var verticalInset: CGFloat {
        isArtwork ? WeydaSpace.xs : WeydaSpace.xs + WeydaSpace.xxs
    }

    /// nil = autant de lignes qu'il faut (tailles d'accessibilité).
    private var textLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 1
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

/// Fantôme de la fiche : la photo 4:3 (sous les barres, voile compris, comme la fiche chargée), le prix, le titre et
/// quelques lignes — rien ne saute à l'arrivée.
private struct DetailSkeleton: View {
    /// Hauteur des barres du haut, que la photo passe dessous.
    let topInset: CGFloat

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
                .overlay(alignment: .top) {
                    DetailTopScrim(topInset: topInset)
                }
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
