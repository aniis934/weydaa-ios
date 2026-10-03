import Foundation
import XCTest
@testable import Weyda

/// Liens universels : chaque chemin que l'AASA du site (lot A, `src/lib/apple-app-site-association.ts`) confie à l'app,
/// sur weydaa.com ET www.weydaa.com, dans les trois langues, ouvre le bon écran (`DeepLinks.resolve`) ; les
/// arborescences exclues restent au navigateur. Puis la réception (`IncomingNavigation`) : appui ou lien reçu avant que
/// l'interface soit prête rejoué, doublon `onOpenURL` / `onContinueUserActivity` ignoré, page sans écran natif rendue à
/// Safari.
final class UniversalLinksTests: XCTestCase {
    private static let hosts = ["https://weydaa.com", "https://www.weydaa.com"]
    private static let languages = ["fr", "ar", "en"]

    /// `NATIVE_PATHS` de l'AASA (un exemple concret par motif), le lien du mot de passe oublié (avec `token`) et l'URL
    /// SEO d'une annonce (`/{langue}/*/*`), avec l'écran attendu.
    private static func nativeLinks() -> [(path: String, target: DeepLinkTarget)] {
        [
            ("/annonce/cm123abc", .listing(idOrSlug: "cm123abc")),
            ("/annonce/cm123abc/modifier", .editListing(id: "cm123abc")),
            ("/profil/user42", .seller(id: "user42")),
            ("/c/vehicules", .listings(params: ["category": "vehicules"])),
            ("/annonces", .listings(params: [:])),
            ("/annonces?q=clio+4&wilaya=16&utm_source=share", .listings(params: ["q": "clio 4", "wilaya": "16"])),
            ("/categories", .listings(params: [:])),
            ("/deposer", .post),
            ("/dashboard", .profile),
            ("/dashboard/settings", .profile),
            ("/dashboard/messages", .messages),
            ("/dashboard/messages/conv42", .conversation(id: "conv42")),
            ("/dashboard/annonces", .myListings),
            ("/dashboard/favorites", .favorites),
            ("/auth/reinitialiser-mdp?token=abc123", .resetPassword(token: "abc123")),
            ("/vehicules/clio-4-2019-ab12", .listing(idOrSlug: "clio-4-2019-ab12")),
        ]
    }

    /// Arborescences `WEB_ONLY_ROOTS/*` exclues par l'AASA : jamais un écran natif.
    private static let webOnlyPaths = [
        "/a-propos/equipe", "/admin/annonces", "/annonces/clio", "/auth/connexion", "/auth/verifier-email",
        "/categories/vehicules", "/cgu/v2", "/confidentialite/cookies", "/contact/form", "/dashboard/notifications",
        "/deposer/etape-2", "/mentions-legales/hebergeur", "/moderateur/signalements", "/suppression-compte/confirmer",
    ]

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), string)
    }

    // MARK: - Chemins de l'AASA

    func testEveryAASAPathOpensItsScreenOnBothHostsAndInEveryLanguage() throws {
        for host in Self.hosts {
            for language in Self.languages {
                for link in Self.nativeLinks() {
                    let full = "\(host)/\(language)\(link.path)"
                    let resolved = DeepLinks.resolve(try url(full))
                    XCTAssertEqual(resolved, link.target, full)
                    XCTAssertFalse(DeepLinks.opensInBrowser(try url(full)), full)
                }
            }
        }
    }

    func testExcludedSitePagesStayInTheBrowser() throws {
        for host in Self.hosts {
            for language in Self.languages {
                for path in Self.webOnlyPaths {
                    let full = "\(host)/\(language)\(path)"
                    XCTAssertNil(DeepLinks.resolve(try url(full)), full)
                    XCTAssertTrue(DeepLinks.opensInBrowser(try url(full)), full)
                }
            }
        }
        // Lien du mot de passe oublié sans jeton : la page du site.
        XCTAssertNil(DeepLinks.resolve(try url("https://weydaa.com/fr/auth/reinitialiser-mdp")))
    }

    func testLinksWithoutLanguageOtherHostsOrSchemesAreNotForTheApp() throws {
        XCTAssertNil(DeepLinks.resolve(try url("https://weydaa.com/annonce/cm123abc")), "l'AASA exige la langue")
        XCTAssertNil(DeepLinks.resolve(try url("https://weydaa.com/de/annonce/cm123abc")))
        XCTAssertNil(DeepLinks.resolve(try url("http://weydaa.com/fr/annonce/cm123abc")))
        XCTAssertNil(DeepLinks.resolve(try url("https://api.weydaa.com/fr/annonce/cm123abc")))
        XCTAssertNil(DeepLinks.resolve(try url("https://weydaa.com.evil.example/fr/annonce/cm123abc")))
        XCTAssertFalse(DeepLinks.opensInBrowser(try url("https://evil.example/fr/cgu")))
        XCTAssertEqual(DeepLinks.resolve(try url("https://WWW.WEYDAA.COM/fr/annonce/cm123abc")), .listing(idOrSlug: "cm123abc"))
        XCTAssertEqual(DeepLinks.resolve(try url("https://weydaa.com/fr/dashboard/messages/conv42/")), .conversation(id: "conv42"))
    }

    /// Les motifs `/annonce/*`, `/profil/*`, `/c/*`, `/dashboard/messages/*` et `/{langue}/*/*` de l'AASA couvrent aussi
    /// des chemins plus profonds que les écrans natifs : l'app les reçoit et les rend au navigateur.
    func testDeeperPathsReceivedByTheAppGoBackToTheBrowser() throws {
        for path in ["/fr/annonce/cm123abc/photos", "/ar/profil/user42/avis", "/en/c/vehicules/voitures",
                     "/fr/dashboard/messages/conv42/details", "/fr/vehicules/voitures/clio-4"] {
            let link = try url("https://weydaa.com\(path)")
            XCTAssertNil(DeepLinks.resolve(link), path)
            XCTAssertTrue(DeepLinks.opensInBrowser(link), path)
        }
    }

    // MARK: - Réception (IncomingNavigation)

    @MainActor
    func testATapOrLinkReceivedBeforeTheInterfaceIsReadyIsReplayed() throws {
        let navigation = IncomingNavigation(openInBrowser: { _ in XCTFail("aucun navigateur attendu") })
        let router = AppRouter(initialTab: .home, launchRoute: nil)

        // Lancement à froid par l'appui sur un push « nouveau message » (chemin du lot B, langue de l'appareil).
        let payload = PushPayload(type: "MESSAGE", url: "/ar/dashboard/messages/mock-c1", conversationId: "mock-c1")
        let target = try XCTUnwrap(payload.target())
        navigation.open(target)
        XCTAssertEqual(router.stack(for: .home), [], "rien tant que le routeur n'est pas branché")

        navigation.attach(router)
        XCTAssertEqual(router.stack(for: .home), [.chat(conversationId: "mock-c1", archived: false)])

        // Interface prête : ouvert tout de suite.
        navigation.handleLink(try url("https://www.weydaa.com/fr/annonce/mock-a2"))
        XCTAssertEqual(router.stack(for: .home), [.chat(conversationId: "mock-c1", archived: false), .detail(idOrSlug: "mock-a2")])
    }

    @MainActor
    func testTheSameLinkDeliveredTwiceIsHandledOnce() throws {
        let opened = FakeWeydaAPI.Box<[URL]>([])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let navigation = IncomingNavigation(openInBrowser: { opened.value.append($0) }, now: { clock })
        let router = AppRouter(initialTab: .home, launchRoute: nil)
        navigation.attach(router)

        // Écran natif : `onOpenURL` puis `onContinueUserActivity` avec le même lien → traité une fois.
        let post = try url("https://weydaa.com/fr/deposer")
        navigation.handleLink(post)
        XCTAssertEqual(router.selectedTab, .post)
        router.select(.home)
        navigation.handleLink(post)
        XCTAssertEqual(router.selectedTab, .home, "doublon ignoré")
        clock = clock.addingTimeInterval(IncomingNavigation.duplicateWindow + 1)
        navigation.handleLink(post)
        XCTAssertEqual(router.selectedTab, .post, "nouvel appui, plus tard : ouvert")

        // Page du site sans écran natif : Safari, une seule fois même si le lien revient aussitôt.
        let terms = try url("https://weydaa.com/fr/cgu")
        navigation.handleLink(terms)
        clock = clock.addingTimeInterval(IncomingNavigation.duplicateWindow + 1)
        navigation.handleLink(terms)
        XCTAssertEqual(opened.value, [terms])
        clock = clock.addingTimeInterval(IncomingNavigation.browserWindow + 1)
        navigation.handleLink(terms)
        XCTAssertEqual(opened.value, [terms, terms])
    }

    @MainActor
    func testUnknownAppSchemeLinksAndForeignSitesAreIgnored() throws {
        let opened = FakeWeydaAPI.Box<[URL]>([])
        let navigation = IncomingNavigation(openInBrowser: { opened.value.append($0) })
        let router = AppRouter(initialTab: .home, launchRoute: nil)
        navigation.attach(router)

        navigation.handleLink(try url("weydaa://cgu"))
        navigation.handleLink(try url("https://evil.example/fr/annonce/x"))
        XCTAssertEqual(opened.value, [])
        XCTAssertEqual(router.stack(for: .home), [])
        XCTAssertEqual(router.selectedTab, .home)

        navigation.handleLink(try url("weydaa://dashboard/favorites"))
        XCTAssertEqual(router.stack(for: .home), [.favorites])
    }
}
