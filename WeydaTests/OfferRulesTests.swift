import XCTest
@testable import Weyda

/// Portage de `OfferRulesTest.kt` (Android) — miroir des règles serveur de `src/lib/offers.ts`.
final class OfferRulesTests: XCTestCase {
    private let me = "user_1"
    private let other = "user_2"
    private let base = Date(timeIntervalSince1970: 1_788_948_000) // 2026-09-09T10:00:00Z, comme Android

    private func offer(_ id: String, _ sender: String, _ kind: OfferKind, amount: Double = 1_000_000, seconds: TimeInterval = 0) -> ChatMessage {
        ChatMessage(
            id: id, conversationId: "c1", senderId: sender, content: "offre",
            createdAt: base.addingTimeInterval(seconds), readAt: nil, deletedAt: nil,
            type: .offer, offer: OfferMeta(kind: kind, amount: amount)
        )
    }

    private func text(_ id: String, _ sender: String, seconds: TimeInterval = 0) -> ChatMessage {
        ChatMessage(
            id: id, conversationId: "c1", senderId: sender, content: "bonjour",
            createdAt: base.addingTimeInterval(seconds), readAt: nil, deletedAt: nil
        )
    }

    private let activeAnnonce = ConversationAnnonce(
        id: "a1", title: "Clio 4", imageUrl: nil, status: .active, price: 1_950_000, priceType: .fixed
    )

    func testWithoutAnyOfferOnlyANewOfferIsPossible() {
        let messages = [text("m1", me)]
        XCTAssertEqual(OfferRules.availableActions(userId: me, messages: messages, annonce: activeAnnonce), [.new])
        XCTAssertEqual(OfferRules.deniedReason(.accept, userId: me, messages: messages, annonce: activeAnnonce), "noOpenOffer")
    }

    func testOpenOfferFromTheOtherPartyCanBeAnsweredButNotDoubled() {
        let messages = [text("m1", me), offer("m2", other, .new, seconds: 10)]
        let actions = OfferRules.availableActions(userId: me, messages: messages, annonce: activeAnnonce)
        XCTAssertEqual(actions, [.counter, .accept, .decline])
        XCTAssertEqual(OfferRules.deniedReason(.new, userId: me, messages: messages, annonce: activeAnnonce), "offerAlreadyOpen")
        XCTAssertTrue(OfferRules.isActionable(messages[1], by: me, messages: messages))
    }

    func testNobodyAnswersTheirOwnOffer() {
        let messages = [offer("m1", me, .new)]
        XCTAssertEqual(OfferRules.deniedReason(.accept, userId: me, messages: messages, annonce: activeAnnonce), "cannotRespondOwnOffer")
        XCTAssertEqual(OfferRules.availableActions(userId: me, messages: messages, annonce: activeAnnonce), [])
        XCTAssertFalse(OfferRules.isActionable(messages[0], by: me, messages: messages))
    }

    func testAfterADeclineTheNegotiationIsClosedAndANewOfferCanStart() {
        let messages = [offer("m1", me, .new, seconds: 10), offer("m2", other, .declined, seconds: 20)]
        XCTAssertNil(OfferRules.openOffer(messages))
        XCTAssertEqual(OfferRules.availableActions(userId: me, messages: messages, annonce: activeAnnonce), [.new])
    }

    func testOnlyTheLatestOfferCarriesTheActions() {
        let messages = [
            offer("m1", other, .new, seconds: 10),
            offer("m2", me, .counter, seconds: 20),
            offer("m3", other, .counter, seconds: 30),
        ]
        XCTAssertEqual(OfferRules.openOffer(messages)?.id, "m3")
        XCTAssertFalse(OfferRules.isActionable(messages[0], by: me, messages: messages))
        XCTAssertTrue(OfferRules.isActionable(messages[2], by: me, messages: messages))
    }

    func testSoldOrFreeListingOnlyAllowsDeclining() {
        let messages = [offer("m1", other, .new)]
        var sold = activeAnnonce
        sold.status = .sold
        XCTAssertEqual(OfferRules.availableActions(userId: me, messages: messages, annonce: sold), [.decline])
        XCTAssertEqual(OfferRules.deniedReason(.accept, userId: me, messages: messages, annonce: sold), "annonceUnavailable")

        var free = activeAnnonce
        free.priceType = .free
        XCTAssertEqual(OfferRules.availableActions(userId: me, messages: messages, annonce: free), [.decline])
    }

    func testATextMessageDoesNotOpenANegotiation() {
        let messages = [offer("m1", other, .new, seconds: 10), text("m2", me, seconds: 20)]
        XCTAssertEqual(OfferRules.openOffer(messages)?.id, "m1")
    }

    /// Comme le serveur : une dernière offre aux métadonnées illisibles n'est pas remplacée par une plus ancienne.
    func testAnUnreadableLatestOfferIsNotReplacedByAnOlderOne() {
        var broken = offer("m2", other, .new, seconds: 20)
        broken.offer = nil
        let messages = [offer("m1", other, .new, seconds: 10), broken]
        XCTAssertNil(OfferRules.latestOffer(messages))
        XCTAssertEqual(OfferRules.availableActions(userId: me, messages: messages, annonce: activeAnnonce), [.new])
    }
}
