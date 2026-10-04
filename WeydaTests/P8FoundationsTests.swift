import Foundation
import XCTest
@testable import Weyda

/// Briques partagées de la phase 8 : vendeur d'une annonce, lien du profil, menu d'appui long, raccourcis de l'icône,
/// règle de la demande de note, route de fiche avec source de zoom.
final class P8FoundationsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "P8FoundationsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func listing(_ json: String) throws -> Listing {
        try JSONDecoder().decode(AnnonceDTO.self, from: Data(json.utf8)).toDomain()
    }

    // MARK: - Vendeur d'une annonce

    func testSellerIdComesFromUserIdThenFromTheIncludedUser() throws {
        XCTAssertEqual(try listing(#"{"id":"a1","title":"T","userId":"u1"}"#).sellerId, "u1")
        XCTAssertEqual(try listing(#"{"id":"a1","title":"T","userId":"u1","user":{"id":"u9","name":"N"}}"#).sellerId, "u1")
        XCTAssertEqual(try listing(#"{"id":"a1","title":"T","user":{"id":"u2","name":"N"}}"#).sellerId, "u2")
        XCTAssertNil(try listing(#"{"id":"a1","title":"T"}"#).sellerId)
        XCTAssertNil(try listing(#"{"id":"a1","title":"T","userId":"  "}"#).sellerId)
    }

    func testSellerWebURLIsTheSiteProfilePageInTheAppLanguage() {
        XCTAssertEqual(SellerLinks.webURL(sellerId: "u1", language: "ar")?.absoluteString, "https://weydaa.com/ar/profil/u1")
        XCTAssertEqual(SellerLinks.webURL(sellerId: " u1 ", language: "fr")?.absoluteString, "https://weydaa.com/fr/profil/u1")
        XCTAssertNil(SellerLinks.webURL(sellerId: "  ", language: "fr"))
    }

    func testCardMenuHidesTheSellerEntryOnTheUsersOwnListing() throws {
        let item = try listing(#"{"id":"a1","title":"T","userId":"u1"}"#)
        XCTAssertEqual(ListingCardMenu(listing: item, currentUserId: nil).sellerId, "u1")
        XCTAssertEqual(ListingCardMenu(listing: item, currentUserId: "u2").sellerId, "u1")
        XCTAssertNil(ListingCardMenu(listing: item, currentUserId: "u1").sellerId)
        XCTAssertNotNil(ListingCardMenu(listing: item, currentUserId: nil).shareURL)
        XCTAssertTrue(ListingCardMenu(listing: item, currentUserId: nil).canFavorite)
        XCTAssertFalse(ListingCardMenu(listing: item, currentUserId: nil, canFavorite: false).canFavorite)
    }

    // MARK: - Route de fiche

    func testDetailRouteWithoutZoomSourceEqualsTheOldRoute() {
        XCTAssertEqual(AppRoute.detail(idOrSlug: "a1"), AppRoute.detail(idOrSlug: "a1", zoomSource: nil))
        XCTAssertNotEqual(AppRoute.detail(idOrSlug: "a1"), AppRoute.detail(idOrSlug: "a1", zoomSource: "home.featured.a1"))
    }

    // MARK: - Raccourcis de l'icône

    func testShortcutTypesRoundTripAndUnknownTypesAreIgnored() {
        for action in ShortcutAction.allCases {
            XCTAssertEqual(ShortcutAction(shortcutType: action.type), action)
        }
        XCTAssertNil(ShortcutAction(shortcutType: "com.weydaa.app.shortcut.inconnu"))
        XCTAssertNil(ShortcutAction(shortcutType: "post"))
    }

    func testShortcutTargets() {
        XCTAssertEqual(ShortcutAction.post.target(), .post)
        XCTAssertEqual(ShortcutAction.messages.target(), .messages)
        guard case .listings(let params) = ShortcutAction.search.target() else {
            return XCTFail("Rechercher doit ouvrir l'onglet Annonces")
        }
        XCTAssertEqual(ListingsLaunch(params: params), ListingsLaunch(focusSearch: true), "aucun critère, champ focalisé")
    }

    func testSiteLinksNeverFocusTheSearchField() throws {
        let url = try XCTUnwrap(URL(string: "https://weydaa.com/fr/annonces?q=clio&_focus=search"))
        guard case .listings(let params) = DeepLinks.resolve(url) else {
            return XCTFail("lien /annonces attendu")
        }
        XCTAssertFalse(ListingsLaunch(params: params).focusSearch)
    }

    // MARK: - Demande de note

    func testReviewIsRequestedAtTheSecondPositiveMomentOncePerVersion() {
        let prompter = ReviewPrompter(defaults: defaults, version: "1.0", isEnabled: true)
        XCTAssertFalse(prompter.record(.listingPublished), "1er moment : trop tôt")
        XCTAssertTrue(prompter.record(.reviewSent), "2e moment : demander")
        XCTAssertFalse(prompter.record(.listingSold), "déjà demandé pour cette version")
        XCTAssertFalse(ReviewPrompter(defaults: defaults, version: "1.0", isEnabled: true).record(.offerAccepted))
        XCTAssertTrue(ReviewPrompter(defaults: defaults, version: "1.1", isEnabled: true).record(.offerAccepted),
                      "nouvelle version : de nouveau permis")
    }

    func testReviewIsNeverRequestedWhenDisabled() {
        let prompter = ReviewPrompter(defaults: defaults, version: "1.0", isEnabled: false)
        for moment in PositiveMoment.allCases {
            XCTAssertFalse(prompter.record(moment))
        }
        XCTAssertEqual(defaults.integer(forKey: ReviewPrompter.momentsKey), 0, "rien n'est compté")
        XCTAssertFalse(ReviewPrompter.isAllowed, "jamais pendant les tests unitaires")
    }
}
