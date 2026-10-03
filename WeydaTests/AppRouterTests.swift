import SwiftUI
import XCTest
@testable import Weyda

/// Routeur de la coquille : piles par onglet, ouverture de l'onglet Annonces, retour à la racine, liens
/// profonds → écrans (équivalent de `NavHostController.open`, WeydaRoot.kt), `-WeydaRoute` analysé et appliqué.
final class AppRouterTests: XCTestCase {

    @MainActor
    private func makeRouter(tab: AppTab = .home, route: String? = nil) -> AppRouter {
        AppRouter(initialTab: tab, launchRoute: route)
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), string)
    }

    // MARK: - Piles

    @MainActor
    func testPushStacksOnTheSelectedTabOnly() {
        let router = makeRouter()
        router.push(.detail(idOrSlug: "a1"))
        router.push(.seller(id: "u1"))
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1"), .seller(id: "u1")])
        XCTAssertEqual(router.stack(for: .listings), [])
        XCTAssertEqual(router.selectedTab, .home)
    }

    @MainActor
    func testSameRouteTwiceInARowIsPushedOnce() {
        let router = makeRouter()
        router.push(.detail(idOrSlug: "a1"))
        router.push(.detail(idOrSlug: "a1"))
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")])
        // Une autre annonce (« similaires ») s'empile bien.
        router.push(.detail(idOrSlug: "a2"))
        XCTAssertEqual(router.stack(for: .home).count, 2)
    }

    @MainActor
    func testWebPageIsPresentedNotPushed() {
        let router = makeRouter(tab: .account)
        router.push(.about)
        router.push(.webPage(.privacy))
        XCTAssertEqual(router.presentedWebPage, .privacy)
        XCTAssertEqual(router.stack(for: .account), [.about])
    }

    @MainActor
    func testPopAndPopToRoot() {
        let router = makeRouter()
        router.push(.detail(idOrSlug: "a1"))
        router.push(.seller(id: "u1"))
        router.pop()
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")])
        router.popToRoot(.home)
        XCTAssertEqual(router.stack(for: .home), [])
        router.pop()
        XCTAssertEqual(router.stack(for: .home), [])
    }

    @MainActor
    func testPathBindingFollowsTheStackAndIgnoresADoubleTap() {
        let router = makeRouter()
        let path = router.path(for: .home)
        path.wrappedValue = [.about]
        XCTAssertEqual(router.stack(for: .home), [.about])
        XCTAssertEqual(path.wrappedValue, [.about])
        // Double appui sur un lien pendant la transition : la même route une seconde fois.
        path.wrappedValue = [.about, .about]
        XCTAssertEqual(router.stack(for: .home), [.about])
        path.wrappedValue = [.about, .contact]
        XCTAssertEqual(router.stack(for: .home), [.about, .contact])
        // Retour (bouton ou glissement).
        path.wrappedValue = []
        XCTAssertEqual(router.stack(for: .home), [])
    }

    // MARK: - Onglets

    @MainActor
    func testTappingTheActiveTabPopsItToItsRoot() {
        let router = makeRouter()
        router.push(.detail(idOrSlug: "a1"))
        router.tabSelection.wrappedValue = .listings
        XCTAssertEqual(router.selectedTab, .listings)
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")], "changer d'onglet garde la pile")
        router.tabSelection.wrappedValue = .home
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")])
        router.tabSelection.wrappedValue = .home
        XCTAssertEqual(router.stack(for: .home), [], "toucher l'onglet actif remonte à la racine")
        XCTAssertEqual(router.selectedTab, .home)
    }

    @MainActor
    func testOpenListingsSelectsTheTabAtItsRootWithCriteria() {
        let router = makeRouter(tab: .listings)
        router.push(.detail(idOrSlug: "old"))
        router.select(.home)
        router.openListings(ListingsLaunch(q: "clio", category: "vehicules"))
        XCTAssertEqual(router.selectedTab, .listings)
        XCTAssertEqual(router.stack(for: .listings), [], "les résultats, pas la fiche ouverte avant")
        XCTAssertEqual(router.listingsLaunch, ListingsLaunch(q: "clio", category: "vehicules"))
        XCTAssertEqual(router.consumeListingsLaunch(), ListingsLaunch(q: "clio", category: "vehicules"))
        XCTAssertNil(router.listingsLaunch)
        XCTAssertNil(router.consumeListingsLaunch())
    }

    @MainActor
    func testRequestLoginShowsTheProfileTabAtItsRoot() {
        let router = makeRouter(tab: .account)
        router.push(.about)
        router.select(.home)
        router.push(.detail(idOrSlug: "a1"))
        router.requestLogin()
        XCTAssertEqual(router.selectedTab, .account)
        XCTAssertEqual(router.stack(for: .account), [])
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")], "l'annonce reste ouverte dans l'Accueil")
    }

    // MARK: - Liens profonds

    @MainActor
    func testSiteLinksOpenTheMatchingScreens() throws {
        let router = makeRouter()
        let links: [(String, AppRoute)] = [
            ("https://weydaa.com/fr/annonce/cm123abc", .detail(idOrSlug: "cm123abc")),
            ("https://www.weydaa.com/ar/vehicules/clio-4-2019-ab12", .detail(idOrSlug: "clio-4-2019-ab12")),
            ("https://weydaa.com/fr/profil/u42", .seller(id: "u42")),
            ("https://weydaa.com/en/dashboard/messages/c9", .chat(conversationId: "c9", archived: false)),
            ("https://weydaa.com/fr/annonce/x1/modifier", .editListing(id: "x1")),
            ("https://weydaa.com/fr/dashboard/annonces", .myListings),
            ("https://weydaa.com/fr/dashboard/favorites", .favorites),
        ]
        for (link, route) in links {
            router.popToRoot(.home)
            let target = try XCTUnwrap(DeepLinks.resolve(try url(link)), link)
            router.open(target)
            XCTAssertEqual(router.stack(for: .home), [route], link)
            XCTAssertEqual(router.selectedTab, .home, link)
        }
    }

    @MainActor
    func testSearchLinksOpenTheListingsTab() throws {
        let router = makeRouter()
        let search = try XCTUnwrap(DeepLinks.resolve(try url("https://weydaa.com/fr/annonces?q=golf+7&wilaya=16&featured=1&priceMin=100")))
        router.open(search)
        XCTAssertEqual(router.selectedTab, .listings)
        XCTAssertEqual(router.listingsLaunch, ListingsLaunch(q: "golf 7", wilaya: 16, featured: true))

        router.select(.home)
        let category = try XCTUnwrap(DeepLinks.resolve(try url("weydaa://fr/c/immobilier")))
        router.open(category)
        XCTAssertEqual(router.selectedTab, .listings)
        XCTAssertEqual(router.listingsLaunch, ListingsLaunch(category: "immobilier"))
    }

    @MainActor
    func testTabLinksSelectTheirTab() {
        let router = makeRouter()
        router.open(.post)
        XCTAssertEqual(router.selectedTab, .post)
        router.open(.messages)
        XCTAssertEqual(router.selectedTab, .messages)
        router.open(.profile)
        XCTAssertEqual(router.selectedTab, .account)
        router.open(.resetPassword(token: "t0k3n"))
        XCTAssertEqual(router.selectedTab, .account)
        XCTAssertEqual(router.stack(for: .account), [])
    }

    @MainActor
    func testADeepLinkClosesThePresentedWebPage() {
        let router = makeRouter()
        router.push(.webPage(.terms))
        router.open(.listing(idOrSlug: "a1"))
        XCTAssertNil(router.presentedWebPage)
        XCTAssertEqual(router.stack(for: .home), [.detail(idOrSlug: "a1")])
    }

    // MARK: - -WeydaRoute

    func testLaunchRoutesAreParsed() {
        XCTAssertEqual(LaunchRoute.parse("detail:mock-a3"), .route(.detail(idOrSlug: "mock-a3")))
        XCTAssertEqual(LaunchRoute.parse(" seller:mock-u2 "), .route(.seller(id: "mock-u2")))
        XCTAssertEqual(LaunchRoute.parse("about"), .route(.about))
        XCTAssertEqual(LaunchRoute.parse("web:cgu"), .route(.webPage(.terms)))
        XCTAssertEqual(LaunchRoute.parse("web:privacy"), .route(.webPage(.privacy)))
        XCTAssertEqual(LaunchRoute.parse("tab:listings"), .tab(.listings))
        XCTAssertEqual(LaunchRoute.parse("tab:profile"), .tab(.account))
        XCTAssertEqual(LaunchRoute.parse("chat:c1"), .route(.chat(conversationId: "c1", archived: false)))
        XCTAssertEqual(LaunchRoute.parse("myListings"), .route(.myListings))
        XCTAssertEqual(LaunchRoute.parse("editListing:x9"), .route(.editListing(id: "x9")))
        XCTAssertEqual(LaunchRoute.parse("listings"), .listings(ListingsLaunch()))
        XCTAssertEqual(
            LaunchRoute.parse("listings:q=clio&category=vehicules"),
            .listings(ListingsLaunch(q: "clio", category: "vehicules"))
        )
        XCTAssertEqual(
            LaunchRoute.parse("listings:q=golf%207&subcategory=voitures&wilaya=31&featured=true"),
            .listings(ListingsLaunch(q: "golf 7", subcategory: "voitures", wilaya: 31, featured: true))
        )
        for invalid in ["", "detail:", "seller: ", "tab:nowhere", "web:nope", "nope", "detail"] {
            XCTAssertNil(LaunchRoute.parse(invalid), invalid)
        }
    }

    @MainActor
    func testLaunchRouteIsAppliedAtStartup() {
        let about = makeRouter(route: "about")
        XCTAssertEqual(about.selectedTab, .account)
        XCTAssertEqual(about.stack(for: .account), [.about])

        let detail = makeRouter(route: "detail:mock-a3")
        XCTAssertEqual(detail.selectedTab, .home)
        XCTAssertEqual(detail.stack(for: .home), [.detail(idOrSlug: "mock-a3")])

        let listings = makeRouter(route: "listings:q=clio")
        XCTAssertEqual(listings.selectedTab, .listings)
        XCTAssertEqual(listings.listingsLaunch, ListingsLaunch(q: "clio"))

        let tab = makeRouter(route: "tab:messages")
        XCTAssertEqual(tab.selectedTab, .messages)

        let chat = makeRouter(route: "chat:c1")
        XCTAssertEqual(chat.selectedTab, .messages)
        XCTAssertEqual(chat.stack(for: .messages), [.chat(conversationId: "c1", archived: false)])

        let unknown = makeRouter(tab: .listings, route: "nope")
        XCTAssertEqual(unknown.selectedTab, .listings)
        XCTAssertEqual(unknown.stack(for: .listings), [])
    }

    // MARK: - Critères et pages

    func testListingsLaunchFromSiteParameters() {
        let launch = ListingsLaunch(params: ["q": "  ", "category": "mode", "wilaya": "abc", "featured": "1"])
        XCTAssertEqual(launch, ListingsLaunch(category: "mode", featured: true))
        XCTAssertEqual(ListingsLaunch.parameters("?a=1&a=2&b&c=d%26e"), ["a": "1", "b": "", "c": "d&e"])
    }

    func testWebPagesUseTheSitePathsInTheAppLanguage() {
        XCTAssertEqual(WebPage.allCases.map(\.rawValue), ["cgu", "confidentialite", "mentions-legales", "a-propos", "suppression-compte"])
        XCTAssertEqual(WebPage.terms.url(language: "ar").absoluteString, "https://weydaa.com/ar/cgu")
        XCTAssertEqual(WebPage.accountDeletion.url(language: "en").absoluteString, "https://weydaa.com/en/suppression-compte")
        XCTAssertEqual(WebPage.notice.url(language: "fr").absoluteString, "https://weydaa.com/fr/mentions-legales")
    }
}

/// Logique pure des composants communs (textes d'une carte, étoiles).
final class ComponentsLogicTests: XCTestCase {
    private let algiers = LocalizedName(fr: "Alger", ar: "الجزائر", en: "Algiers")
    private let commune = LocalizedName(fr: "Bab Ezzouar", ar: "باب الزوار", en: "Bab Ezzouar")

    func testPlaceIsCommuneThenWilayaInTheAppLanguage() {
        XCTAssertEqual(ListingText.place(wilaya: algiers, commune: commune, language: "fr"), "Bab Ezzouar, Alger")
        XCTAssertEqual(ListingText.place(wilaya: algiers, commune: nil, language: "en"), "Algiers")
        XCTAssertEqual(ListingText.place(wilaya: algiers, commune: commune, language: "ar"), "باب الزوار، الجزائر")
        XCTAssertNil(ListingText.place(wilaya: nil, commune: nil, language: "fr"))
    }

    func testAccessibilityLabelReadsTitlePricePlaceAndFeatured() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let listing = Listing(
            id: "a1",
            slug: nil,
            title: "Renault Clio 4",
            description: "",
            price: 2_850_000,
            priceType: .negotiable,
            status: "ACTIVE",
            views: 0,
            isFeatured: true,
            phone: nil,
            createdAt: nil,
            images: [],
            category: nil,
            categorySlug: nil,
            wilaya: algiers,
            commune: nil,
            seller: nil,
            attributes: [:]
        )
        let label = ListingText.accessibilityLabel(for: listing, now: now, language: "fr")
        XCTAssertTrue(label.hasPrefix("Renault Clio 4, "), label)
        XCTAssertTrue(label.contains(Format.price(2_850_000, type: .negotiable)), label)
        XCTAssertTrue(label.contains(L10n.priceNegotiable), label)
        XCTAssertTrue(label.contains("Alger"), label)
        XCTAssertTrue(label.hasSuffix(L10n.featuredBadge), label)
        // Sans date : pas de « · » orphelin dans la ligne lieu / ancienneté.
        XCTAssertEqual(ListingText.meta(for: listing, now: now, language: "fr"), "Alger")
    }

    func testStarsRoundToTheNearestHalf() {
        func stars(_ rating: Double) -> [String] {
            (0..<RatingStarSymbols.maxStars).map { RatingStarSymbols.symbol(at: $0, rating: rating) }
        }
        XCTAssertEqual(stars(3.5), ["star.fill", "star.fill", "star.fill", "star.leadinghalf.filled", "star"])
        XCTAssertEqual(stars(4.24), ["star.fill", "star.fill", "star.fill", "star.fill", "star"])
        XCTAssertEqual(stars(4.26), ["star.fill", "star.fill", "star.fill", "star.fill", "star.leadinghalf.filled"])
        XCTAssertEqual(stars(7), Array(repeating: "star.fill", count: 5))
        XCTAssertEqual(stars(-1), Array(repeating: "star", count: 5))
        XCTAssertEqual(RatingStarSymbols.spokenStars(4.4), 4)
        XCTAssertEqual(RatingStarSymbols.spokenStars(4.6), 5)
    }

    func testShimmerHeadSweepsFromBeforeToAfterTheShape() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(ShimmerClock.head(at: start), -0.5, accuracy: 1e-9)
        let middle = Date(timeIntervalSinceReferenceDate: ShimmerClock.period / 2)
        XCTAssertEqual(ShimmerClock.head(at: middle), 0.5, accuracy: 1e-9)
    }
}
