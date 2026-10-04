import Foundation
import UserNotifications
import XCTest
@testable import Weyda

/// Boutons d'action des notifications (phase 8) : lecture de la réponse système, catégories enregistrées, exécution avec
/// les repositories (fausse API) — l'interface système elle-même n'est pas photographiable (test réel au premier TestFlight).
final class NotificationActionsTests: XCTestCase {
    private static let message = PushPayload(
        type: "MESSAGE",
        url: "/fr/dashboard/messages/c1",
        conversationId: "c1",
        notificationId: "n1"
    )

    // MARK: - Lecture de la réponse

    func testReplyCarriesTheTrimmedTextAndTheConversation() {
        let action = PushQuickAction.from(actionIdentifier: NotificationActionID.reply, payload: Self.message, userText: "  Bonjour  ")
        XCTAssertEqual(action, PushQuickAction(conversationId: "c1", notificationId: "n1", kind: .reply("Bonjour")))
    }

    func testEmptyReplyAndPlainTapsAreNotQuickActions() {
        XCTAssertNil(PushQuickAction.from(actionIdentifier: NotificationActionID.reply, payload: Self.message, userText: "   "))
        XCTAssertNil(PushQuickAction.from(actionIdentifier: NotificationActionID.reply, payload: Self.message, userText: nil))
        XCTAssertNil(PushQuickAction.from(actionIdentifier: UNNotificationDefaultActionIdentifier, payload: Self.message, userText: nil))
        XCTAssertNil(PushQuickAction.from(actionIdentifier: UNNotificationDismissActionIdentifier, payload: Self.message, userText: nil))
        XCTAssertNil(PushQuickAction.from(actionIdentifier: "inconnu", payload: Self.message, userText: nil))
    }

    func testOfferButtonsAcceptOrDeclineAndTheThreadComesFromTheLinkWhenNeeded() {
        let offer = PushPayload(type: "OFFER_RECEIVED", url: "/ar/dashboard/messages/c7")
        XCTAssertEqual(
            PushQuickAction.from(actionIdentifier: NotificationActionID.acceptOffer, payload: offer, userText: nil),
            PushQuickAction(conversationId: "c7", notificationId: nil, kind: .offer(.accept))
        )
        XCTAssertEqual(
            PushQuickAction.from(actionIdentifier: NotificationActionID.declineOffer, payload: offer, userText: nil)?.kind,
            .offer(.decline)
        )
        let noThread = PushPayload(type: "OFFER_RECEIVED", url: "/fr/annonces")
        XCTAssertNil(PushQuickAction.from(actionIdentifier: NotificationActionID.acceptOffer, payload: noThread, userText: nil))
    }

    func testCategoriesMatchTheServerAndAcceptNeedsAnUnlockedDevice() throws {
        let categories = NotificationCategories.all()
        XCTAssertEqual(Set(categories.map { $0.identifier }), ["MESSAGE", "OFFER"])
        let message = try XCTUnwrap(categories.first { $0.identifier == NotificationCategoryID.message })
        XCTAssertEqual(message.actions.map { $0.identifier }, [NotificationActionID.reply])
        XCTAssertTrue(message.actions.first is UNTextInputNotificationAction)
        let offer = try XCTUnwrap(categories.first { $0.identifier == NotificationCategoryID.offer })
        XCTAssertEqual(offer.actions.map { $0.identifier }, [NotificationActionID.acceptOffer, NotificationActionID.declineOffer])
        XCTAssertTrue(offer.actions[0].options.contains(.authenticationRequired))
        XCTAssertTrue(offer.actions[1].options.contains(.destructive))
    }

    // MARK: - Exécution

    @MainActor
    private func makePerformer(
        api: FakeWeydaAPI,
        signedIn: Bool = true,
        failures: FakeWeydaAPI.Box<[PushQuickAction]>
    ) -> PushActionPerformer {
        PushActionPerformer(
            conversations: ConversationsRepository(api: api),
            notifications: NotificationsRepository(api: api),
            isSignedIn: { signedIn },
            reportFailure: { action in failures.value.append(action) }
        )
    }

    @MainActor
    private func stubNotifications(_ api: FakeWeydaAPI, unread: Int) {
        api.onMarkNotificationRead = { _ in SimpleResponseDTO() }
        api.onGetNotifications = { _, _ in
            NotificationsPageDTO(notifications: [], unreadCount: unread, total: 0, totalPages: 1, page: 1, topic: "")
        }
    }

    @MainActor
    func testReplySendsTheMessageMarksTheNotificationReadAndRefreshesTheBadge() async {
        let api = FakeWeydaAPI()
        let failures = FakeWeydaAPI.Box<[PushQuickAction]>([])
        let sent = FakeWeydaAPI.Box<[String]>([])
        api.onSendMessage = { id, body in
            sent.value.append("\(id):\(body.content)")
            return MessageDTO(id: "m1", conversationId: id, senderId: "me", content: body.content)
        }
        stubNotifications(api, unread: 2)
        let performer = makePerformer(api: api, failures: failures)
        let outcome = await performer.perform(PushQuickAction(conversationId: "c1", notificationId: "n1", kind: .reply("Bonjour")))
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(sent.value, ["c1:Bonjour"])
        XCTAssertEqual(api.calls, ["sendMessage", "markNotificationRead", "getNotifications"])
        XCTAssertTrue(failures.value.isEmpty)
    }

    @MainActor
    func testAcceptPostsTheOfferAction() async {
        let api = FakeWeydaAPI()
        let failures = FakeWeydaAPI.Box<[PushQuickAction]>([])
        let actions = FakeWeydaAPI.Box<[String]>([])
        api.onPostOfferAction = { id, body in
            actions.value.append("\(id):\(body.action)")
            return MessageDTO(id: "m2", conversationId: id, senderId: "me", type: "OFFER")
        }
        stubNotifications(api, unread: 0)
        let performer = makePerformer(api: api, failures: failures)
        let outcome = await performer.perform(PushQuickAction(conversationId: "c7", notificationId: nil, kind: .offer(.accept)))
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(actions.value, ["c7:accept"])
        XCTAssertEqual(api.calls, ["postOfferAction", "getNotifications"], "sans identifiant de notification : rien à marquer lu")
    }

    @MainActor
    func testRefusalsAndSignedOutReportAFailureWithoutMarkingAnythingRead() async {
        let api = FakeWeydaAPI()
        let failures = FakeWeydaAPI.Box<[PushQuickAction]>([])
        api.onSendMessage = { _, _ in throw FakeWeydaAPI.apiError(403, #"{"error":"emailNotVerified"}"#) }
        api.onPostOfferAction = { _, _ in throw FakeWeydaAPI.apiError(409, #"{"error":"offerNotPending"}"#) }
        stubNotifications(api, unread: 1)
        let performer = makePerformer(api: api, failures: failures)
        let reply = PushQuickAction(conversationId: "c1", notificationId: "n1", kind: .reply("Bonjour"))
        let accept = PushQuickAction(conversationId: "c7", notificationId: "n2", kind: .offer(.accept))
        let replied = await performer.perform(reply)
        let accepted = await performer.perform(accept)
        XCTAssertEqual(replied, .failed)
        XCTAssertEqual(accepted, .failed)
        XCTAssertEqual(failures.value, [reply, accept])
        XCTAssertEqual(api.calls, ["sendMessage", "postOfferAction"])

        let signedOut = makePerformer(api: api, signedIn: false, failures: failures)
        let outcome = await signedOut.perform(reply)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(api.calls, ["sendMessage", "postOfferAction"], "déconnecté : aucun appel réseau")
        XCTAssertEqual(failures.value.count, 3)
    }
}
