import Foundation
import XCTest
@testable import Weyda

/// `PushPayload` : lecture du `userInfo` d'un push tel que le serveur l'envoie (lot B, `src/lib/fcm.ts` : clés `data` à
/// la racine du payload APNs, à côté de `aps`), écran visé à l'appui, bannière masquée pour le fil visible. Données
/// fictives.
final class PushPayloadTests: XCTestCase {

    /// Push « nouveau message » livré par FCM à iOS : clés `data`, bloc `aps` (alerte traduite, `thread-id`, pastille) et
    /// clés techniques de Firebase.
    private static func messageUserInfo(
        conversationId: String = "mock-c1",
        url: String = "/ar/dashboard/messages/mock-c1"
    ) -> [AnyHashable: Any] {
        let alert: [String: Any] = [
            "title": "Amina K.",
            "body": "Je peux descendre à 3 050 000 DA, pas moins.",
        ]
        let aps: [String: Any] = [
            "alert": alert,
            "sound": "default",
            "thread-id": conversationId,
            "badge": 3,
        ]
        return [
            "aps": aps,
            "type": "MESSAGE",
            "title": "Amina K.",
            "body": "Je peux descendre à 3 050 000 DA, pas moins.",
            "url": url,
            "conversationId": conversationId,
            "notificationId": "notif-7",
            "gcm.message_id": "1759500000000001",
            "google.c.a.e": "1",
            "google.c.sender.id": "000000000000",
        ]
    }

    // MARK: - Lecture du userInfo

    func testMessagePushIsReadFromTheDataKeys() {
        let payload = PushPayload(userInfo: Self.messageUserInfo())
        XCTAssertEqual(payload.type, "MESSAGE")
        XCTAssertEqual(payload.title, "Amina K.")
        XCTAssertEqual(payload.body, "Je peux descendre à 3 050 000 DA, pas moins.")
        XCTAssertEqual(payload.url, "/ar/dashboard/messages/mock-c1")
        XCTAssertEqual(payload.conversationId, "mock-c1")
        XCTAssertEqual(payload.notificationId, "notif-7")
        XCTAssertNil(payload.annonceId)
        XCTAssertEqual(payload.target(language: "fr"), .conversation(id: "mock-c1"))
    }

    func testOfferAndListingPushesKeepTheirIdentifiers() {
        let offer: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Contre-offre reçue", "body": "3 050 000 DA"] as [String: Any]] as [String: Any],
            "type": "OFFER_COUNTER",
            "title": "Amina K.",
            "body": "3 050 000 DA",
            "url": "/fr/dashboard/messages/mock-c1",
            "conversationId": "mock-c1",
            "annonceId": "mock-a2",
            "notificationId": "notif-8",
        ]
        let payload = PushPayload(userInfo: offer)
        XCTAssertEqual(payload.type, "OFFER_COUNTER")
        XCTAssertEqual(payload.annonceId, "mock-a2")
        XCTAssertEqual(payload.target(language: "fr"), .conversation(id: "mock-c1"))

        let priceDrop: [AnyHashable: Any] = [
            "type": "FAVORITE_PRICE_DROP",
            "title": "Baisse de prix",
            "body": "Renault Clio 4 GT Line 2019",
            "url": "/en/annonce/mock-a10",
            "annonceId": "mock-a10",
            "notificationId": "notif-9",
        ]
        XCTAssertEqual(PushPayload(userInfo: priceDrop).target(language: "fr"), .listing(idOrSlug: "mock-a10"))
    }

    func testTitleAndBodyFallBackOnTheSystemAlertAndValuesAreReadTolerantly() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Annonce approuvée", "body": "Lenovo ThinkPad T14"] as [String: Any]] as [String: Any],
            "type": "  ",
            "title": "",
            "notificationId": NSNumber(value: 12),
            "url": "  /fr/dashboard/annonces  ",
        ]
        let payload = PushPayload(userInfo: userInfo)
        XCTAssertNil(payload.type, "valeur blanche ignorée")
        XCTAssertEqual(payload.title, "Annonce approuvée")
        XCTAssertEqual(payload.body, "Lenovo ThinkPad T14")
        XCTAssertEqual(payload.notificationId, "12")
        XCTAssertEqual(payload.url, "/fr/dashboard/annonces")
        XCTAssertEqual(payload.target(language: "fr"), .myListings)

        let plainAlert: [AnyHashable: Any] = ["aps": ["alert": "Nouveau message"] as [String: Any]]
        let plain = PushPayload(userInfo: plainAlert)
        XCTAssertNil(plain.title)
        XCTAssertEqual(plain.body, "Nouveau message")
        XCTAssertNil(plain.target(language: "fr"))

        XCTAssertEqual(PushPayload(userInfo: [:]), PushPayload())
    }

    // MARK: - Écran visé

    func testEveryServerPathOpensTheRightScreen() {
        let cases: [(String, DeepLinkTarget)] = [
            ("/fr/dashboard/messages/mock-c3", .conversation(id: "mock-c3")),
            ("/ar/annonce/mock-a25", .listing(idOrSlug: "mock-a25")),
            ("/en/profil/mock-me", .seller(id: "mock-me")),
            ("/fr/dashboard/annonces", .myListings),
            ("/fr/dashboard/favorites", .favorites),
            ("/fr/dashboard/messages", .messages),
            ("https://weydaa.com/fr/annonce/mock-a10", .listing(idOrSlug: "mock-a10")),
            ("https://www.weydaa.com/ar/vehicules/clio-4-2019-ab12", .listing(idOrSlug: "clio-4-2019-ab12")),
        ]
        for (url, expected) in cases {
            XCTAssertEqual(PushPayload(url: url).target(language: "fr"), expected, url)
        }
    }

    func testAPathWithoutLanguageGetsTheLanguageOfTheApp() {
        XCTAssertEqual(PushPayload(url: "/dashboard/messages/mock-c1").target(language: "en"), .conversation(id: "mock-c1"))
        XCTAssertEqual(PushPayload.localizedPath("/dashboard/annonces", language: "ar"), "/ar/dashboard/annonces")
        XCTAssertEqual(PushPayload.localizedPath("/ar/annonce/mock-a1", language: "fr"), "/ar/annonce/mock-a1")
        XCTAssertEqual(PushPayload.localizedPath("/en", language: "fr"), "/en")
        XCTAssertEqual(PushPayload.localizedPath("/annonces?q=clio", language: "en"), "/en/annonces?q=clio")
        XCTAssertEqual(PushPayload.localizedPath("/", language: "ar"), "/ar")
        XCTAssertEqual(PushPayload.localizedPath("/deposer", language: "de"), "/fr/deposer", "langue inconnue → français")
    }

    func testIdentifiersAreUsedWhenTheLinkHasNoNativeScreen() {
        XCTAssertEqual(PushPayload(url: "/fr/cgu", conversationId: "mock-c2").target(language: "fr"), .conversation(id: "mock-c2"))
        XCTAssertEqual(PushPayload(annonceId: "mock-a17").target(language: "fr"), .listing(idOrSlug: "mock-a17"))
        XCTAssertNil(PushPayload(url: "https://evil.example/fr/annonce/x").target(language: "fr"))
        XCTAssertNil(PushPayload(type: "REVIEW").target(language: "fr"))
    }

    // MARK: - Bannière au premier plan

    func testTheBannerIsHiddenOnlyForTheVisibleThread() {
        let payload = PushPayload(userInfo: Self.messageUserInfo())
        XCTAssertTrue(payload.isShown(whileViewing: nil))
        XCTAssertTrue(payload.isShown(whileViewing: "mock-c2"))
        XCTAssertFalse(payload.isShown(whileViewing: "mock-c1"))

        // Sans `conversationId`, le fil se lit dans le lien.
        let fromLink = PushPayload(url: "/fr/dashboard/messages/mock-c4")
        XCTAssertEqual(fromLink.threadId, "mock-c4")
        XCTAssertFalse(fromLink.isShown(whileViewing: "mock-c4"))

        // Une notification qui ne vise pas un fil s'affiche toujours.
        let approved = PushPayload(type: "ANNONCE_APPROVED", url: "/fr/dashboard/annonces")
        XCTAssertNil(approved.threadId)
        XCTAssertTrue(approved.isShown(whileViewing: "mock-c1"))
    }

    func testTheForegroundFilterFollowsTheVisibleThread() {
        let filter = PushForegroundFilter()
        let payload = PushPayload(userInfo: Self.messageUserInfo(conversationId: "mock-c5", url: "/fr/dashboard/messages/mock-c5"))
        XCTAssertNil(filter.visibleConversationId)
        XCTAssertTrue(filter.shouldPresent(payload))
        filter.setVisibleConversation("mock-c5")
        XCTAssertEqual(filter.visibleConversationId, "mock-c5")
        XCTAssertFalse(filter.shouldPresent(payload))
        filter.setVisibleConversation(nil)
        XCTAssertTrue(filter.shouldPresent(payload))
    }
}
