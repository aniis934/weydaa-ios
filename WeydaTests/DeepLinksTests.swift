import XCTest
@testable import Weyda

/// Portage de `DeepLinksTest.kt` (Android), plus les entrées propres à iOS (URL complète, schéma de l'app,
/// chemins des notifications).
final class DeepLinksTests: XCTestCase {

    private func listing(_ string: String) -> Bool {
        guard let url = URL(string: string), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return DeepLinks.isListingLink(scheme: components.scheme, host: components.host, pathSegments: DeepLinks.pathSegments(of: url))
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), string)
    }

    private func resolve(_ string: String) throws -> DeepLinkTarget? {
        let link = try url(string)
        return DeepLinks.resolve(link)
    }

    private func opensInBrowser(_ string: String) throws -> Bool {
        let link = try url(string)
        return DeepLinks.opensInBrowser(link)
    }

    // MARK: - Cas d'Android

    func testBothListingUrlFormsOpenInTheApp() {
        XCTAssertTrue(listing("https://weydaa.com/fr/annonce/cm123abc"))
        XCTAssertTrue(listing("https://www.weydaa.com/ar/vehicules/clio-4-2019-ab12"))
        XCTAssertTrue(listing("https://WEYDAA.com/en/immobilier/villa-a-oran-x7f2?utm_source=share"))
    }

    func testSitePagesThatAreNotListingsGoBackToTheBrowser() {
        // Le lien de l'e-mail « mot de passe oublié » : le capter empêchait de changer son mot de passe.
        XCTAssertFalse(listing("https://weydaa.com/fr/auth/reinitialiser-mdp?token=abc"))
        XCTAssertFalse(listing("https://weydaa.com/fr/auth/verifier-email"))
        XCTAssertFalse(listing("https://weydaa.com/fr/dashboard/messages"))
        XCTAssertFalse(listing("https://weydaa.com/fr/dashboard/messages/conv42"))
        XCTAssertFalse(listing("https://weydaa.com/ar/profil/user42"))
        XCTAssertFalse(listing("https://weydaa.com/en/c/vehicules"))
        XCTAssertFalse(listing("https://weydaa.com/fr/annonce/cm123abc/modifier"))
        XCTAssertFalse(listing("https://weydaa.com/fr/annonces"))
        XCTAssertFalse(listing("https://weydaa.com/fr"))
    }

    func testAnotherHostSchemeOrUnknownLocaleIsNeverAListing() {
        XCTAssertFalse(listing("https://evil.example/fr/annonce/cm123abc"))
        XCTAssertFalse(listing("https://weydaa.com.evil.example/fr/annonce/cm123abc"))
        XCTAssertFalse(listing("http://weydaa.com/fr/annonce/cm123abc"))
        XCTAssertFalse(listing("https://weydaa.com/de/annonce/cm123abc"))
        XCTAssertFalse(DeepLinks.isListingLink(scheme: nil, host: nil, pathSegments: []))
    }

    func testWeydaHostOnlyAcceptsHttpsOnTheTwoSiteHosts() {
        XCTAssertTrue(DeepLinks.isWeydaHost(scheme: "https", host: "weydaa.com"))
        XCTAssertTrue(DeepLinks.isWeydaHost(scheme: "https", host: "www.weydaa.com"))
        XCTAssertFalse(DeepLinks.isWeydaHost(scheme: "http", host: "weydaa.com"))
        XCTAssertFalse(DeepLinks.isWeydaHost(scheme: "https", host: "api.weydaa.com"))
        XCTAssertFalse(DeepLinks.isWeydaHost(scheme: "https", host: nil))
    }

    func testResolveGivesTheListingTargetAndNothingForPagesWithoutANativeScreen() {
        XCTAssertEqual(DeepLinks.resolve(scheme: "https", host: "weydaa.com", pathSegments: ["fr", "annonce", "cm123abc"]), .listing(idOrSlug: "cm123abc"))
        XCTAssertEqual(DeepLinks.resolve(scheme: "https", host: "www.weydaa.com", pathSegments: ["ar", "vehicules", "clio-4-ab12"]), .listing(idOrSlug: "clio-4-ab12"))
        XCTAssertNil(DeepLinks.resolve(scheme: "https", host: "weydaa.com", pathSegments: ["fr", "auth", "reinitialiser-mdp"]))
        XCTAssertNil(DeepLinks.resolve(scheme: "https", host: "evil.example", pathSegments: ["fr", "annonce", "cm123abc"]))
    }

    // MARK: - URL complètes (liens universels)

    func testEveryNativeScreenIsReachable() throws {
        XCTAssertEqual(try resolve("https://weydaa.com/fr/annonce/cm123abc/modifier"), .editListing(id: "cm123abc"))
        XCTAssertEqual(try resolve("https://weydaa.com/ar/profil/user42"), .seller(id: "user42"))
        XCTAssertEqual(try resolve("https://weydaa.com/en/c/vehicules"), .listings(params: ["category": "vehicules"]))
        XCTAssertEqual(try resolve("https://weydaa.com/fr/categories"), .listings(params: [:]))
        XCTAssertEqual(try resolve("https://weydaa.com/fr/deposer"), .post)
        XCTAssertEqual(try resolve("https://weydaa.com/fr/dashboard"), .profile)
        XCTAssertEqual(try resolve("https://weydaa.com/fr/dashboard/settings"), .profile)
        XCTAssertEqual(try resolve("https://weydaa.com/fr/dashboard/messages"), .messages)
        XCTAssertEqual(try resolve("https://www.weydaa.com/fr/dashboard/messages/conv42/"), .conversation(id: "conv42"))
        XCTAssertEqual(try resolve("https://weydaa.com/fr/dashboard/annonces"), .myListings)
        XCTAssertEqual(try resolve("https://weydaa.com/fr/dashboard/favorites"), .favorites)
        XCTAssertEqual(try resolve("https://weydaa.com/fr/auth/reinitialiser-mdp?token=abc123"), .resetPassword(token: "abc123"))
        XCTAssertNil(try resolve("https://weydaa.com/fr/auth/reinitialiser-mdp?token=%20"))
    }

    func testSearchKeepsOnlyKnownNonBlankParametersWithPlusAsSpace() throws {
        let target = try resolve("https://weydaa.com/fr/annonces?q=clio+4&category=vehicules&priceMin=&wilaya=16&utm_source=x&q=golf")
        XCTAssertEqual(target, .listings(params: ["q": "clio 4", "category": "vehicules", "wilaya": "16"]))
        XCTAssertEqual(try resolve("https://weydaa.com/ar/annonces?q=golf%207"), .listings(params: ["q": "golf 7"]))
    }

    func testPercentEncodedSegmentsAreDecoded() throws {
        XCTAssertEqual(try resolve("https://weydaa.com/fr/annonce/caf%C3%A9-ab12"), .listing(idOrSlug: "café-ab12"))
    }

    func testSitePagesWithoutANativeScreenOpenInTheBrowser() throws {
        XCTAssertTrue(try opensInBrowser("https://weydaa.com/fr/cgu"))
        XCTAssertTrue(try opensInBrowser("https://weydaa.com/fr/auth/verifier-email"))
        XCTAssertFalse(try opensInBrowser("https://weydaa.com/fr/annonce/cm123abc"))
        XCTAssertFalse(try opensInBrowser("https://evil.example/fr/cgu"))
        XCTAssertFalse(try opensInBrowser("weydaa://cgu"))
    }

    // MARK: - Schéma de l'app et notifications

    func testAppSchemeUsesTheSitePathsWithAnOptionalLocale() throws {
        XCTAssertEqual(try resolve("weydaa://annonce/cm123abc"), .listing(idOrSlug: "cm123abc"))
        XCTAssertEqual(try resolve("weydaa://fr/dashboard/messages/conv42"), .conversation(id: "conv42"))
        XCTAssertEqual(try resolve("weydaa:///en/deposer"), .post)
        XCTAssertEqual(try resolve("WEYDAA://dashboard/favorites"), .favorites)
        XCTAssertNil(try resolve("weydaa://"))
        XCTAssertNil(try resolve("weydaa://cgu"))
        XCTAssertNil(try resolve("autre://annonce/cm123abc"))
    }

    func testPushNotificationPathsAreAttachedToTheSite() {
        XCTAssertEqual(DeepLinks.resolve(sitePath: "/fr/dashboard/messages/conv42"), .conversation(id: "conv42"))
        XCTAssertEqual(DeepLinks.resolve(sitePath: "/ar/annonce/clio-4-ab12"), .listing(idOrSlug: "clio-4-ab12"))
        XCTAssertNil(DeepLinks.resolve(sitePath: "dashboard/messages"))
        XCTAssertEqual(DeepLinks.siteURL.absoluteString, "https://weydaa.com")
    }
}
