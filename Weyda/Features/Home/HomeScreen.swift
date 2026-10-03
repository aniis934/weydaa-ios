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
            .safeAreaInset(edge: .top, spacing: 0) {
                OfflineBanner()
            }
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
                SectionHeader(title: L10n.sectionCategories, actionTitle: L10n.seeAll, action: actions.showAllCategories)
                HomeCategoryRow(
                    categories: state.categories,
                    onOpen: actions.openCategory,
                    onShowAll: actions.showAllCategories
                )
            }
            if !state.featured.isEmpty {
                SectionHeader(title: L10n.sectionFeatured, actionTitle: L10n.seeAll, action: actions.seeAllFeatured)
                HomeCarousel(listings: state.featured, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            if !state.trending.isEmpty {
                SectionHeader(title: L10n.homeTrending)
                HomeCarousel(listings: state.trending, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            if !state.forYou.isEmpty {
                SectionHeader(title: L10n.homeForYou)
                HomeCarousel(listings: state.forYou, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            if !state.recent.isEmpty {
                SectionHeader(title: L10n.sectionRecent, actionTitle: L10n.seeAll, action: actions.seeAllRecent)
                HomeRecentGrid(listings: state.recent, favoriteIds: favoriteIds, onFavorite: actions.toggleFavorite)
            }
            HomeBrowseAllButton(action: actions.seeAllRecent)
            if !state.popularWilayas.isEmpty {
                SectionHeader(title: L10n.sectionPopularCities)
                HomeCityRow(wilayas: state.popularWilayas, onOpen: actions.openWilaya)
            }
            HomePostPrompt(action: actions.post)
        }
    }
}

/// Toutes les catégories racines en pastilles rondes qui défilent, puis « Toutes » (la feuille complète).
private struct HomeCategoryRow: View {
    let categories: [Category]
    let onOpen: (Category) -> Void
    let onShowAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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

/// « Annonces récentes » : grille de deux colonnes, cartes de hauteur égale.
private struct HomeRecentGrid: View {
    let listings: [Listing]
    let favoriteIds: Set<String>
    let onFavorite: (Listing) -> Void

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: WeydaSpace.gutter, alignment: .top),
        GridItem(.flexible(), spacing: WeydaSpace.gutter, alignment: .top),
    ]

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: WeydaSpace.gutter) {
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
