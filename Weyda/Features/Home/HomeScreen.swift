import SwiftUI

/// Gestes de l'accueil, branchés par `HomeView` sur le routeur et le ViewModel. L'écran ne navigue lui-même que
/// vers la fiche d'une annonce (`NavigationLink(value:)`, pile de l'onglet).
struct HomeActions {
    var retry: () -> Void
    var openSearch: () -> Void
    var openCategory: (Category) -> Void
    var showAllCategories: () -> Void
    var seeAllFeatured: () -> Void
    var seeAllRecent: () -> Void
    var openWilaya: (Wilaya) -> Void
    var toggleFavorite: (Listing) -> Void
    var openNotifications: () -> Void
    var post: () -> Void
}

/// Accueil SANS état — portage de `HomeScreen` (Android), sur le modèle des grandes places de marché mobiles
/// (Leboncoin : la structure, pas l'habillage). Ordre de lecture : Recherche → Catégories → À la une → Tendances →
/// Pour vous → Récentes → Villes → Déposer. Le logotype tient dans la barre de navigation (toujours en vue) ; les
/// sections défilent : rangées horizontales (catégories, carrousels accrochés, villes) et grille des récentes.
/// Premier chargement : les formes à venir (squelettes) ; tout en échec : `ErrorState` ; hors ligne : bandeau.
struct HomeScreen: View {
    private let state: HomeState
    private let favoriteIds: Set<String>
    private let notificationsUnread: Int?
    private let actions: HomeActions

    /// - Parameter notificationsUnread: pastille de la cloche ; nil = visiteur, pas de cloche.
    init(state: HomeState, favoriteIds: Set<String>, notificationsUnread: Int?, actions: HomeActions) {
        self.state = state
        self.favoriteIds = favoriteIds
        self.notificationsUnread = notificationsUnread
        self.actions = actions
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.background)
            .weydaOfflineBanner()
            .navigationTitle(AppTab.home.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HomeBrandLockup()
                }
                if let notificationsUnread {
                    ToolbarItem(placement: .primaryAction) {
                        HomeNotificationsButton(unread: notificationsUnread, action: actions.openNotifications)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.home")
    }

    @ViewBuilder
    private var content: some View {
        if state.isError {
            ErrorState(message: state.errorMessage ?? L10n.errorGeneric, onRetry: actions.retry)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SearchEntryButton(placeholder: L10n.searchHint, action: actions.openSearch)
                        .accessibilityIdentifier("home.search")
                        .padding(.horizontal, WeydaSpace.screen)
                        .padding(.top, WeydaSpace.sm)
                    if state.isLoading {
                        HomeSkeleton()
                            .transition(.opacity)
                    } else {
                        HomeSections(state: state, favoriteIds: favoriteIds, actions: actions)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, WeydaSpace.xxl)
                // Les sections se posent en fondu à l'arrivée des données, une seule fois (rien ne bouge si
                // « Réduire les animations » est actif).
                .weydaAnimation(.easeOut(duration: WeydaDuration.medium), value: state.isLoading)
            }
        }
    }
}

/// Mesures propres à l'accueil.
private nonisolated enum HomeLayout {
    /// Gouttière moins le retrait de la pastille dans sa cellule : le premier cercle tombe sous le titre de section.
    static let categoryInset: CGFloat = WeydaSpace.screen - (WeydaSize.categoryCell - WeydaSize.categoryCircle) / 2
    /// Le W à côté du mot « Weydaa », dans la barre.
    static let markSide: CGFloat = 24
    /// Tuile de l'icône de l'app dans l'invitation à déposer.
    static let promptTile: CGFloat = 56
    /// Très grand texte : réduction permise aux libellés courts (pastilles de catégorie), plutôt qu'un « … ».
    static let labelMinScale: CGFloat = 0.7
}

/// Textes de l'invitation à déposer (chaînes propres à iOS, reprises du site).
private nonisolated enum HomeCopy {
    static var postPromptTitle: String { L10n.homeCtaTitle }
    static var postPromptMessage: String? { L10n.homeCtaSubtitle }
}

// MARK: - Sections

/// Les sections chargées ; une section vide (ou en échec) n'apparaît pas.
private struct HomeSections: View {
    let state: HomeState
    let favoriteIds: Set<String>
    let actions: HomeActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.categories.isEmpty {
                HomeSectionHeader(title: L10n.sectionCategories, actionTitle: L10n.seeAll, action: actions.showAllCategories)
                HomeCategoryRow(
                    categories: state.categories,
                    onOpen: actions.openCategory,
                    onShowAll: actions.showAllCategories
                )
            }
            if !state.featured.isEmpty {
                HomeSectionHeader(title: L10n.sectionFeatured, actionTitle: L10n.seeAll, action: actions.seeAllFeatured)
                HomeCarousel(listings: state.featured, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            if !state.trending.isEmpty {
                HomeSectionHeader(title: L10n.homeTrending)
                HomeCarousel(listings: state.trending, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            if !state.forYou.isEmpty {
                HomeSectionHeader(title: L10n.homeForYou)
                HomeCarousel(listings: state.forYou, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            if !state.recent.isEmpty {
                HomeSectionHeader(title: L10n.sectionRecent, actionTitle: L10n.seeAll, action: actions.seeAllRecent)
                HomeRecentGrid(listings: state.recent, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            HomeBrowseAllButton(action: actions.seeAllRecent)
            if !state.popularWilayas.isEmpty {
                HomeSectionHeader(title: L10n.sectionPopularCities)
                HomeCityRow(wilayas: state.popularWilayas, onOpen: actions.openWilaya)
            }
            HomePostPrompt(action: actions.post)
        }
    }
}

/// Toutes les catégories racines en pastilles rondes qui défilent, puis « Toutes » (la feuille complète). Très grand
/// texte : `HomeCategoryBubble` (cellule élargie, libellé jamais tronqué ni coupé au milieu d'un mot).
private struct HomeCategoryRow: View {
    private let categories: [Category]
    private let onOpen: (Category) -> Void
    private let onShowAll: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(categories: [Category], onOpen: @escaping (Category) -> Void, onShowAll: @escaping () -> Void) {
        self.categories = categories
        self.onOpen = onOpen
        self.onShowAll = onShowAll
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if dynamicTypeSize.isAccessibilitySize {
                largeCells
            } else {
                regularCells
            }
        }
    }

    /// Tailles normales : la rangée validée, inchangée.
    private var regularCells: some View {
        HStack(alignment: .top, spacing: WeydaSpace.xs) {
            ForEach(categories) { category in
                CategoryCircle(
                    title: category.name.resolve(),
                    iconAsset: CategoryIcon.assetName(forSlug: category.slug),
                    action: { onOpen(category) }
                )
                .accessibilityIdentifier("home.category.\(category.slug)")
            }
            CategoryCircle(title: L10n.categoryAllTile, iconAsset: CategoryIcon.all, action: onShowAll)
                .accessibilityIdentifier("home.categories.all")
        }
        .padding(.horizontal, HomeLayout.categoryInset)
    }

    /// Très grand texte : mêmes identifiants, cellules élargies, un peu plus d'air entre elles.
    private var largeCells: some View {
        HStack(alignment: .top, spacing: WeydaSpace.sm) {
            ForEach(categories) { category in
                HomeCategoryBubble(
                    title: category.name.resolve(),
                    iconAsset: CategoryIcon.assetName(forSlug: category.slug),
                    action: { onOpen(category) }
                )
                .accessibilityIdentifier("home.category.\(category.slug)")
            }
            HomeCategoryBubble(title: L10n.categoryAllTile, iconAsset: CategoryIcon.all, action: onShowAll)
                .accessibilityIdentifier("home.categories.all")
        }
        .padding(.horizontal, HomeLayout.categoryInset)
    }
}

/// Pastille de catégorie en très grand texte — celle de `CategoryCircle` (cercle teinté, icône, appui), dans une
/// cellule dont la largeur suit la taille du texte (76 pt à la taille par défaut, comme la cellule normale) : dans
/// 76 pt fixes, « Véhicules » / « المركبات » finissaient en « Véhic… » / « …المركبا ». Libellé : une ligne par mot
/// au plus (deux lignes), réduit jusqu'à 70 % plutôt que tronqué — jamais un mot coupé en deux.
private struct HomeCategoryBubble: View {
    private let title: String
    private let iconAsset: String
    private let action: () -> Void
    @ScaledMetric(relativeTo: .caption) private var cellWidth: CGFloat = WeydaSize.categoryCell

    init(title: String, iconAsset: String, action: @escaping () -> Void) {
        self.title = title
        self.iconAsset = iconAsset
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: WeydaSpace.sm) {
                Circle()
                    .fill(WeydaPalette.categoryTile)
                    .frame(width: WeydaSize.categoryCircle, height: WeydaSize.categoryCircle)
                    .overlay {
                        CategoryIconImage(assetName: iconAsset, size: WeydaSize.iconLarge)
                            .foregroundStyle(WeydaColor.primary)
                    }
                Text(title)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(LabelLines.limit(for: title, maxLines: 2))
                    .minimumScaleFactor(HomeLayout.labelMinScale)
            }
            .padding(.vertical, WeydaSpace.sm)
            .frame(width: max(cellWidth, WeydaSize.categoryCell))
            .contentShape(Rectangle())
        }
        .buttonStyle(WeydaPressStyle(pressedScale: 0.94))
        .accessibilityLabel(title)
    }
}

/// Carrousel de cartes (À la une, Tendances, Pour vous) : chaque carte ouvre la fiche, le cœur bascule le favori.
private struct HomeCarousel: View {
    let listings: [Listing]
    let favoriteIds: Set<String>
    let onFavorite: (Listing) -> Void

    var body: some View {
        HomeSnappingRow {
            ForEach(listings) { listing in
                NavigationLink(value: AppRoute.detail(idOrSlug: listing.id)) {
                    ListingCarouselCard(
                        listing: listing,
                        isFavorite: favoriteIds.contains(listing.id),
                        onFavorite: { onFavorite(listing) }
                    )
                }
                .buttonStyle(.weydaCard)
            }
        }
    }
}

/// Rangée horizontale de cartes. iOS 17+ : accrochée (une carte s'arrête toujours entière, alignée sur la marge,
/// comme le carrousel d'Android) ; iOS 16 : défilement libre, même marge.
private struct HomeSnappingRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: WeydaSpace.gutter) {
                    content
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, WeydaSpace.screen, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: WeydaSpace.gutter) {
                    content
                }
                .padding(.horizontal, WeydaSpace.screen)
            }
        }
    }
}

/// « Annonces récentes » : grille de deux colonnes, cartes de hauteur égale. Très grand texte : une seule colonne
/// (dans une demi-largeur, le prix ne tenait plus, même sur deux lignes).
private struct HomeRecentGrid: View {
    private let listings: [Listing]
    private let favoriteIds: Set<String>
    private let onFavorite: (Listing) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: WeydaSpace.gutter, alignment: .top),
        GridItem(.flexible(), spacing: WeydaSpace.gutter, alignment: .top),
    ]
    private static let singleColumn: [GridItem] = [
        GridItem(.flexible(), spacing: WeydaSpace.gutter, alignment: .top),
    ]

    init(listings: [Listing], favoriteIds: Set<String>, onFavorite: @escaping (Listing) -> Void) {
        self.listings = listings
        self.favoriteIds = favoriteIds
        self.onFavorite = onFavorite
    }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? Self.singleColumn : Self.columns
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: WeydaSpace.gutter) {
            ForEach(listings) { listing in
                NavigationLink(value: AppRoute.detail(idOrSlug: listing.id)) {
                    ListingCard(
                        listing: listing,
                        isFavorite: favoriteIds.contains(listing.id),
                        onFavorite: { onFavorite(listing) }
                    )
                }
                .buttonStyle(.weydaCard)
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
    }
}

/// En-tête de section de l'accueil : `SectionHeader` aux tailles normales (inchangé) ; en très grand texte, « Voir
/// tout » passe SOUS le titre — à côté, le titre se coupait d'un trait d'union (« Catégo-ries »).
private struct HomeSectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            SectionHeader(title: title, actionTitle: actionTitle, action: action)
        }
    }

    /// Mêmes styles et marges que `SectionHeader`, le titre sur toute la largeur, l'action dessous.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .weydaText(.titleLarge)
                .foregroundStyle(WeydaColor.onBackground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: WeydaSize.touchTarget, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let action {
                Button(action: action) {
                    Text(actionTitle ?? L10n.seeAll)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: WeydaSize.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.top, WeydaSpace.section - WeydaSpace.sm)
        .padding(.bottom, WeydaSpace.xs)
    }
}

/// « Voir toutes les annonces » : l'onglet Annonces sans critère (Android : `home_browse_all`).
private struct HomeBrowseAllButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.homeBrowseAll)
                .weydaText(.labelLarge)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.top, WeydaSpace.xl)
        .accessibilityIdentifier("home.browseAll")
    }
}

/// Villes populaires : puces à épingle ; une ville ouvre l'onglet Annonces filtré sur sa wilaya.
private struct HomeCityRow: View {
    let wilayas: [Wilaya]
    let onOpen: (Wilaya) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeydaSpace.sm) {
                ForEach(wilayas) { wilaya in
                    WeydaChip(title: wilaya.name.resolve(), iconAsset: CategoryIcon.place, action: { onOpen(wilaya) })
                        .accessibilityIdentifier("home.city.\(wilaya.id)")
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
        }
    }
}

/// Invitation à déposer : la tuile de l'icône de l'app (la marque passe par le logotype, pas par un aplat de
/// couleur), une phrase, le bouton — il bascule sur l'onglet Déposer.
private struct HomePostPrompt: View {
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.panel, style: .continuous)
        VStack(spacing: WeydaSpace.lg) {
            WeydaTile(size: HomeLayout.promptTile)
            VStack(spacing: WeydaSpace.xs) {
                Text(HomeCopy.postPromptTitle)
                    .weydaText(.titleLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message = HomeCopy.postPromptMessage {
                    Text(message)
                        .weydaText(.bodyMedium)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
            }
            Button(action: action) {
                Text(L10n.postTitle)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.onPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(WeydaColor.primary)
            .accessibilityIdentifier("home.post")
        }
        .padding(WeydaSpace.xl)
        .frame(maxWidth: .infinity)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.top, WeydaSpace.section)
    }
}

// MARK: - Barre de navigation

/// Logotype de la barre : le W et le mot « Weydaa », vert de la marque, toujours de gauche à droite.
private struct HomeBrandLockup: View {
    var body: some View {
        HStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
            WeydaMark(fill: WeydaColor.primary)
                .frame(width: HomeLayout.markSide, height: HomeLayout.markSide)
            WeydaWordmark(color: WeydaColor.primary, style: .mark)
        }
        .environment(\.layoutDirection, .leftToRight)
        // Un logotype garde sa taille (Dynamic Type le ferait déborder de la barre) : 25 pt, le mot d'Android.
        .dynamicTypeSize(.xSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.appName)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Cloche d'un compte connecté, pastille rouge des notifications non lues (« 99+ » au-delà).
private struct HomeNotificationsButton: View {
    private let unread: Int
    private let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    init(unread: Int, action: @escaping () -> Void) {
        self.unread = unread
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        badge
                    }
                }
        }
        .accessibilityLabel(L10n.notificationsTitle)
        .accessibilityValue(unread > 0 ? Format.badge(unread, cap: 99) : "")
    }

    private var badge: some View {
        Text(Format.badge(unread, cap: 99))
            .weydaText(.labelSmall)
            .foregroundStyle(WeydaColor.onSecondary)
            .padding(.horizontal, WeydaSpace.xs)
            .background(WeydaColor.secondary, in: Capsule())
            .fixedSize()
            .offset(x: badgeShift, y: -WeydaSpace.sm)
            .accessibilityHidden(true)
    }

    /// La pastille déborde vers l'extérieur de la cloche, du côté de la fin de ligne (RTL compris).
    private var badgeShift: CGFloat {
        layoutDirection == .rightToLeft ? -WeydaSpace.sm : WeydaSpace.sm
    }
}

// MARK: - Squelettes

/// Premier chargement : les formes des sections à venir (Android : squelettes par section).
private struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.sectionCategories)
            CategoryCircleSkeletonRow()
            SectionHeader(title: L10n.sectionFeatured)
            ListingCardSkeletonRow()
            SectionHeader(title: L10n.sectionRecent)
            HomeGridSkeleton()
        }
    }
}

/// Fantômes de la première rangée de la grille des récentes.
private struct HomeGridSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: WeydaSpace.gutter) {
            ListingCardSkeleton()
            ListingCardSkeleton()
        }
        .padding(.horizontal, WeydaSpace.screen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.loading)
    }
}
