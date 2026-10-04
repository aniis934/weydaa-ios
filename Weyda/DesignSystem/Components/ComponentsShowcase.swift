#if DEBUG
import SwiftUI

/// Démonstration des composants communs (Debug), section « Composants » de `DesignShowcaseView` — relue dans les
/// captures (`-WeydaScreen components`, fr / ar / en, clair / sombre). Annonces FICTIVES construites en code,
/// photos dessinées par l'API simulée (`-WeydaMockAPI YES`). Intitulés techniques en `verbatim` : cet écran
/// n'existe pas dans l'app publiée. Les composants « bord à bord » (en-têtes, rangées) sont montrés sur toute la
/// largeur, comme dans un écran.
struct ComponentsShowcase: View {
    @State private var favorites: Set<String> = ["demo-2"]
    @State private var query: String = "Clio 4"
    @State private var selectedChip: Int = 1

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.section) {
            cards
            carousel
            rows
            details
            chips
            categories
            headers
            search
            states
            skeletons
            login
        }
    }

    // MARK: Annonces

    private var cards: some View {
        DemoGroup(title: "ListingCard") {
            HStack(alignment: .top, spacing: WeydaSpace.gutter) {
                ForEach(Array(ShowcaseFixtures.listings.prefix(2))) { listing in
                    Button {} label: {
                        ListingCard(listing: listing, isFavorite: favorites.contains(listing.id), onFavorite: { toggle(listing.id) })
                    }
                    .buttonStyle(.weydaCard)
                }
            }
        }
    }

    private var carousel: some View {
        DemoGroup(title: "ListingCarouselCard") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: WeydaSpace.gutter) {
                    ForEach(ShowcaseFixtures.listings) { listing in
                        Button {} label: {
                            ListingCarouselCard(listing: listing, isFavorite: favorites.contains(listing.id), onFavorite: { toggle(listing.id) })
                        }
                        .buttonStyle(.weydaCard)
                    }
                }
                .padding(.horizontal, WeydaSpace.screen)
            }
            .padding(.horizontal, -WeydaSpace.screen)
        }
    }

    private var rows: some View {
        DemoGroup(title: "ListingRow") {
            VStack(spacing: WeydaSpace.gutter) {
                ForEach(Array(ShowcaseFixtures.listings.suffix(3))) { listing in
                    Button {} label: {
                        ListingRow(listing: listing, isFavorite: favorites.contains(listing.id), onFavorite: { toggle(listing.id) })
                    }
                    .buttonStyle(.weydaCard)
                }
                ListingRow(listing: ShowcaseFixtures.listings[0])
            }
        }
    }

    private var details: some View {
        DemoGroup(title: "PriceText · LocationLine · RatingStars · FeaturedBadge · FavoriteButton") {
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                PriceText(price: 12_500, priceType: .fixed)
                PriceText(price: 2_850_000, priceType: .negotiable)
                PriceText(price: nil, priceType: .free)
                PriceText(price: nil, priceType: .fixed)
                PriceText(price: 1_250_000, priceType: .negotiable, style: .priceLarge)
                LocationLine(wilaya: ShowcaseFixtures.algiers, commune: ShowcaseFixtures.babEzzouar)
                HStack(spacing: WeydaSpace.lg) {
                    RatingStars(rating: 4.5)
                    RatingStars(rating: 3, size: 18)
                }
                HStack(spacing: WeydaSpace.sm) {
                    FeaturedBadge()
                    FeaturedBadge(compact: true)
                    FavoriteButton(isFavorite: true, action: {})
                    FavoriteButton(isFavorite: false, action: {})
                    FavoriteButton(isFavorite: false, onPhoto: true, action: {})
                }
            }
        }
    }

    // MARK: Puces et catégories

    private var chips: some View {
        DemoGroup(title: "WeydaChip") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WeydaSpace.sm) {
                    WeydaChip(title: L10n.allCategories, isSelected: selectedChip == 0, action: { selectedChip = 0 })
                    WeydaChip(
                        title: ShowcaseFixtures.vehicles.resolve(),
                        isSelected: selectedChip == 1,
                        artwork: .category(slug: "vehicules"),
                        action: { selectedChip = 1 }
                    )
                    WeydaChip(
                        title: ShowcaseFixtures.algiers.resolve(),
                        isSelected: selectedChip == 2,
                        iconAsset: CategoryIcon.place,
                        action: { selectedChip = 2 }
                    )
                    WeydaChip(title: L10n.filtersFeaturedChip, isSelected: true, onRemove: {}, action: {})
                    WeydaChip(title: ShowcaseFixtures.oran.resolve(), onRemove: {}, action: {})
                }
                .padding(.horizontal, WeydaSpace.screen)
            }
            .padding(.horizontal, -WeydaSpace.screen)
        }
    }

    private var categories: some View {
        DemoGroup(title: "CategoryShortcut · CategoryTile") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: WeydaSpace.sm) {
                    ForEach(ShowcaseFixtures.categories) { category in
                        CategoryShortcut(
                            title: category.name.resolve(),
                            artwork: .category(slug: category.slug),
                            action: {}
                        )
                    }
                }
                .padding(.horizontal, WeydaSpace.screen)
            }
            .padding(.horizontal, -WeydaSpace.screen)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: WeydaSpace.sm), count: 4),
                alignment: .center,
                spacing: WeydaSpace.sm
            ) {
                ForEach(Array(ShowcaseFixtures.categories.prefix(4))) { category in
                    CategoryTile(
                        title: category.name.resolve(),
                        artwork: .category(slug: category.slug),
                        count: category.count,
                        action: {}
                    )
                }
            }
        }
    }

    // MARK: En-têtes, recherche, états

    private var headers: some View {
        DemoGroup(title: "SectionHeader") {
            VStack(spacing: 0) {
                SectionHeader(title: L10n.sectionRecent, actionTitle: L10n.seeAll, action: {})
                SectionHeader(title: L10n.sectionFeatured, action: {})
                SectionHeader(title: L10n.sectionCategories)
            }
            .padding(.horizontal, -WeydaSpace.screen)
        }
    }

    private var search: some View {
        DemoGroup(title: "SearchEntryButton · WeydaSearchField") {
            SearchEntryButton(placeholder: L10n.searchHint, action: {})
            WeydaSearchField(text: $query, placeholder: L10n.searchHint, onSubmit: {})
        }
    }

    private var states: some View {
        DemoGroup(title: "OfflineBanner · EmptyState · ErrorState · InlineLoader") {
            OfflineBannerLabel()
                .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
            DemoBox {
                EmptyState(
                    systemImage: "magnifyingglass",
                    title: L10n.emptyResults,
                    message: L10n.emptyResultsHint,
                    actionTitle: L10n.filtersReset,
                    action: {}
                )
            }
            DemoBox {
                ErrorState(message: L10n.errorOffline, onRetry: {})
            }
            DemoBox {
                InlineLoader()
            }
        }
    }

    private var skeletons: some View {
        DemoGroup(title: "Skeletons") {
            VStack(alignment: .leading, spacing: WeydaSpace.md) {
                ChipSkeletonRow()
                CategoryShortcutSkeletonRow()
                ListingCardSkeletonRow()
                ListingRowSkeletons(count: 2)
            }
            .padding(.horizontal, -WeydaSpace.screen)
            HStack(alignment: .top, spacing: WeydaSpace.gutter) {
                ListingCardSkeleton()
                ListingCardSkeleton()
            }
            SkeletonBlock(width: 160, height: 12)
        }
    }

    private var login: some View {
        DemoGroup(title: "LoginRequired") {
            DemoBox {
                LoginRequired(title: L10n.loginRequiredTitle, message: L10n.loginRequiredBody, onLogin: {})
                    .frame(height: 440)
            }
        }
    }

    private func toggle(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
    }
}

/// Un groupe de la démonstration : nom technique du composant, puis le composant.
private struct DemoGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            Text(verbatim: title)
                .weydaText(.labelMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cadre pour les états qui occupent tout un écran.
private struct DemoBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(WeydaColor.background, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
                    .strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
    }
}

/// Catégorie de démonstration (le vrai catalogue vient de l'API).
nonisolated struct ShowcaseCategory: Hashable, Sendable, Identifiable {
    let slug: String
    let name: LocalizedName
    let count: Int

    var id: String { slug }
}

/// Données FICTIVES de la démonstration : wilayas réelles, prix plausibles en DA, textes rédigés comme par des
/// vendeurs (en français). Photos `https://photos.mock.weydaa/annonces/<objet>-<n>.webp` (MockPhotos).
nonisolated enum ShowcaseFixtures {
    static let algiers = LocalizedName(fr: "Alger", ar: "الجزائر", en: "Algiers")
    static let oran = LocalizedName(fr: "Oran", ar: "وهران", en: "Oran")
    static let constantine = LocalizedName(fr: "Constantine", ar: "قسنطينة", en: "Constantine")
    static let setif = LocalizedName(fr: "Sétif", ar: "سطيف", en: "Setif")
    static let tiziOuzou = LocalizedName(fr: "Tizi Ouzou", ar: "تيزي وزو", en: "Tizi Ouzou")
    static let babEzzouar = LocalizedName(fr: "Bab Ezzouar", ar: "باب الزوار", en: "Bab Ezzouar")
    static let birElDjir = LocalizedName(fr: "Bir El Djir", ar: "بئر الجير", en: "Bir El Djir")
    static let vehicles = LocalizedName(fr: "Véhicules", ar: "مركبات", en: "Vehicles")

    static let listings: [Listing] = [
        listing(
            "demo-1", "Renault Clio 4 GT Line 2019, première main", price: 2_850_000, type: .negotiable,
            featured: true, photo: "car-1", wilaya: algiers, commune: babEzzouar, hoursAgo: 2
        ),
        listing(
            "demo-2", "iPhone 13 Pro 256 Go, très bon état", price: 145_000, type: .fixed,
            photo: "phone-1", wilaya: oran, commune: birElDjir, hoursAgo: 5
        ),
        listing(
            "demo-3", "Canapé d'angle 5 places, tissu gris", price: 85_000, type: .negotiable,
            photo: "sofa-1", wilaya: constantine, commune: nil, hoursAgo: 26
        ),
        listing(
            "demo-4", "MacBook Air M1 8 Go / 256 Go", price: 165_000, type: .fixed,
            featured: true, photo: "laptop-1", wilaya: setif, commune: nil, hoursAgo: 72
        ),
        listing(
            "demo-5", "Chaton à donner, 3 mois, très joueur", price: nil, type: .free,
            photo: "pet-1", wilaya: tiziOuzou, commune: nil, hoursAgo: 1
        ),
        listing(
            "demo-6", "Villa F5 avec jardin, quartier calme", price: nil, type: .fixed,
            featured: true, photo: "house-1", wilaya: algiers, commune: nil, hoursAgo: 220
        ),
        listing(
            "demo-7", "Cours particuliers de mathématiques, lycée", price: 2_000, type: .fixed,
            photo: nil, wilaya: algiers, commune: babEzzouar, hoursAgo: 4
        ),
    ]

    static let categories: [ShowcaseCategory] = [
        ShowcaseCategory(slug: "vehicules", name: vehicles, count: 12_480),
        ShowcaseCategory(slug: "immobilier", name: LocalizedName(fr: "Immobilier", ar: "عقارات", en: "Real estate"), count: 8_315),
        ShowcaseCategory(slug: "electronique", name: LocalizedName(fr: "Électronique", ar: "إلكترونيات", en: "Electronics"), count: 6_027),
        ShowcaseCategory(
            slug: "electromenager",
            name: LocalizedName(fr: "Électroménager", ar: "أجهزة كهرومنزلية", en: "Home appliances"),
            count: 3_412
        ),
        ShowcaseCategory(slug: "mode", name: LocalizedName(fr: "Mode", ar: "موضة", en: "Fashion"), count: 2_950),
        ShowcaseCategory(
            slug: "maison",
            name: LocalizedName(fr: "Maison et jardin", ar: "المنزل والحديقة", en: "Home & garden"),
            count: 2_104
        ),
    ]

    private static func listing(
        _ id: String,
        _ title: String,
        price: Double?,
        type: PriceType,
        featured: Bool = false,
        photo: String?,
        wilaya: LocalizedName?,
        commune: LocalizedName?,
        hoursAgo: Double
    ) -> Listing {
        Listing(
            id: id,
            slug: nil,
            title: title,
            description: "",
            price: price,
            priceType: type,
            status: ListingStatus.active.rawValue,
            views: 0,
            isFeatured: featured,
            phone: nil,
            createdAt: Date(timeIntervalSinceNow: -hoursAgo * 3600),
            images: photo.map { ["https://photos.mock.weydaa/annonces/\($0).webp"] } ?? [],
            category: nil,
            categorySlug: nil,
            wilaya: wilaya,
            commune: commune,
            seller: nil,
            attributes: [:]
        )
    }
}
#endif
