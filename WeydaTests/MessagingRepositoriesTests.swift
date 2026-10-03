import Combine
import Foundation
import XCTest
@testable import Weyda

/// Parties repository de NotificationsTest.kt et ConversationsTest.kt (Android) : pastilles, canal personnel,
/// temps réel, curseur, archives, offres. Données fictives.
final class MessagingRepositoriesTests: XCTestCase {
    private static let me = "user_1"
    private static let other = "user_2"

    // MARK: - Notifications

    private static func notification(_ id: String, read: Bool = false, url: String? = nil, type: String = "MESSAGE") -> NotificationDTO {
        NotificationDTO(id: id, type: type, title: "Yacine", body: "Bonjour", url: url, read: read, createdAt: "2026-09-07T12:12:43.698Z")
    }

    private static func notificationsPage(_ items: [NotificationDTO], unread: Int, page: Int = 1, totalPages: Int = 1) -> NotificationsPageDTO {
        NotificationsPageDTO(
            notifications: items,
            unreadCount: unread,
            total: items.count,
            totalPages: totalPages,
            page: page,
            topic: "user:user_1:0000000000000000"
        )
    }

    @MainActor
    func testTheFirstPageRemembersThePersonalChannelAndTheCounter() async throws {
        let api = FakeWeydaAPI()
        let repository = NotificationsRepository(api: api)
        api.onGetNotifications = { _, _ in
            MessagingRepositoriesTests.notificationsPage(
                [MessagingRepositoriesTests.notification("n1"), MessagingRepositoriesTests.notification("n2", read: true)],
                unread: 1
            )
        }
        let page = try await repository.page()
        XCTAssertEqual(page.items.map { $0.id }, ["n1", "n2"])
        XCTAssertEqual(repository.topic, "user:user_1:0000000000000000")
        XCTAssertEqual(repository.unreadCount, 1)
        XCTAssertFalse(page.hasMore)
    }

    @MainActor
    func testSignOutForgetsTheChannelAndTheBadge() async throws {
        let api = FakeWeydaAPI()
        let repository = NotificationsRepository(api: api)
        api.onGetNotifications = { _, _ in
            MessagingRepositoriesTests.notificationsPage([MessagingRepositoriesTests.notification("n1")], unread: 1)
        }
        _ = try await repository.page()
        repository.reset()
        XCTAssertEqual(repository.unreadCount, 0)
        XCTAssertNil(repository.topic)
    }

    @MainActor
    func testMarkReadDeleteAndMarkAllUpdateTheBadge() async throws {
        let api = FakeWeydaAPI()
        let repository = NotificationsRepository(api: api)
        api.onGetNotifications = { page, limit in
            XCTAssertEqual(limit, 50)
            return MessagingRepositoriesTests.notificationsPage([MessagingRepositoriesTests.notification("n1")], unread: 3, page: page, totalPages: 2)
        }
        _ = try await repository.page(page: 1, limit: 200)
        XCTAssertEqual(repository.unreadCount, 3)
        // Une page suivante ne touche pas à la pastille.
        _ = try await repository.page(page: 2, limit: 200)
        XCTAssertEqual(repository.unreadCount, 3)

        api.onMarkNotificationRead = { _ in SimpleResponseDTO() }
        try await repository.markRead(id: "n1")
        XCTAssertEqual(repository.unreadCount, 2)

        api.onDeleteNotification = { _ in SimpleResponseDTO() }
        try await repository.delete(id: "n2", wasUnread: false)
        XCTAssertEqual(repository.unreadCount, 2)
        try await repository.delete(id: "n3", wasUnread: true)
        XCTAssertEqual(repository.unreadCount, 1)

        api.onMarkAllNotificationsRead = { MarkAllReadDTO(updated: 1) }
        let updated = try await repository.markAllRead()
        XCTAssertEqual(updated, 1)
        XCTAssertEqual(repository.unreadCount, 0)

        // Refus du serveur : la pastille n'est pas touchée.
        try await repository.markRead(id: "n9")
        XCTAssertEqual(repository.unreadCount, 0)
        api.onMarkAllNotificationsRead = { throw FakeWeydaAPI.apiError(500) }
        _ = try await repository.page(page: 1, limit: 200)
        do {
            _ = try await repository.markAllRead()
            XCTFail("erreur serveur attendue")
        } catch is APIError {}
        XCTAssertEqual(repository.unreadCount, 3)
    }

    @MainActor
    func testARealtimeNotificationRaisesTheBadgeAndReachesTheOpenScreen() async throws {
        let api = FakeWeydaAPI()
        let repository = NotificationsRepository(api: api)
        let received = FakeWeydaAPI.Box<[AppNotification]>([])
        let subscription = repository.incoming.sink { notification in
            received.value.append(notification)
        }
        // Forme déjà convertie (`RealtimeNotification.toAppNotification()`), « lue » et sans date à dessein.
        let event = AppNotification(
            id: "n9",
            kind: .offerReceived,
            title: "Sofiane",
            body: "1 800 000 DA",
            url: "/dashboard/messages/c3",
            read: true,
            createdAt: nil
        )
        repository.onRealtime(event)
        repository.onRealtime(event)
        XCTAssertEqual(repository.unreadCount, 2)
        XCTAssertEqual(received.value.map { $0.id }, ["n9", "n9"])
        XCTAssertEqual(received.value.first?.kind, NotificationKind.offerReceived)
        XCTAssertEqual(received.value.first?.read, false)
        XCTAssertNotNil(received.value.first?.createdAt)
        XCTAssertEqual(received.value.first?.target, NotificationTarget.conversation(id: "c3"))
        subscription.cancel()
    }

    // MARK: - Conversations

    private static func conversation(
        _ id: String,
        lastSender: String = other,
        readAt: String? = nil,
        deleted: Bool = false
    ) -> ConversationDTO {
        ConversationDTO(
            id: id,
            annonceId: "a\(id)",
            buyerId: me,
            sellerId: other,
            updatedAt: "2026-09-07T12:10:00.000Z",
            annonce: ConversationAnnonceDTO(id: "a\(id)", title: "Clio 4"),
            buyer: UserRefDTO(id: me, name: "Amina"),
            seller: UserRefDTO(id: other, name: "Yacine"),
            messages: [
                MessagePreviewDTO(
                    content: deleted ? "" : "dernier message",
                    createdAt: "2026-09-07T12:10:00.000Z",
                    senderId: lastSender,
                    readAt: readAt,
                    deletedAt: deleted ? "2026-09-07T12:11:00.000Z" : nil
                ),
            ],
            topic: "conv:\(id):abc"
        )
    }

    @MainActor
    func testListGivesThePartnerUnreadStateAndCursor() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [MessagingRepositoriesTests.conversation("c1")], nextCursor: "c1")
        }
        let page = try await repository.list()
        XCTAssertEqual(page.items.count, 1)
        let conversation = try XCTUnwrap(page.items.first)
        XCTAssertEqual(conversation.partner(Self.me).name, "Yacine")
        XCTAssertEqual(conversation.partner(Self.other).name, "Amina")
        XCTAssertTrue(conversation.isUnreadFor(Self.me))
        XCTAssertFalse(conversation.isUnreadFor(Self.other))
        XCTAssertEqual(conversation.topic, "conv:c1:abc")
        XCTAssertEqual(page.nextCursor, "c1")
    }

    @MainActor
    func testADeletedLastMessageGivesAnEmptyPreviewMarkedDeleted() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [MessagingRepositoriesTests.conversation("c1", deleted: true)])
        }
        let page = try await repository.list()
        let conversation = try XCTUnwrap(page.items.first)
        XCTAssertEqual(conversation.lastMessage?.isDeleted, true)
        XCTAssertEqual(conversation.lastMessage?.content, "")
    }

    @MainActor
    func testOnlyTheArchivesSegmentSendsArchived() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        let flags = FakeWeydaAPI.Box<[Bool?]>([])
        api.onGetConversations = { _, limit, archived in
            XCTAssertEqual(limit, 20)
            flags.value.append(archived)
            return ConversationsPageDTO()
        }
        _ = try await repository.list(archived: false)
        _ = try await repository.list(archived: true)
        XCTAssertEqual(flags.value, [nil, true])
    }

    @MainActor
    func testAnAlreadyOpenOfferReturnsTheExistingConversationWithoutError() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onInitiateOffer = { _, _ in
            throw FakeWeydaAPI.apiError(409, #"{"error":"offerAlreadyOpen","conversationId":"c9"}"#)
        }
        let entry = try await repository.makeOffer(annonceId: "a1", amount: 1_800_000)
        XCTAssertEqual(entry, ConversationEntry(conversationId: "c9", created: false))
    }

    @MainActor
    func testAnAcceptedInitialOfferCreatesTheConversation() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onInitiateOffer = { id, body in
            XCTAssertEqual(id, "a1")
            XCTAssertEqual(body.amount, 1_800_000)
            return ConversationCreatedDTO(conversationId: "c5")
        }
        let entry = try await repository.makeOffer(annonceId: "a1", amount: 1_800_000)
        XCTAssertEqual(entry, ConversationEntry(conversationId: "c5", created: true))
    }

    @MainActor
    func testA409WithoutConversationIdStaysAnError() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onInitiateOffer = { _, _ in throw FakeWeydaAPI.apiError(409, #"{"error":"offerAlreadyOpen"}"#) }
        do {
            _ = try await repository.makeOffer(annonceId: "a1", amount: 1000)
            XCTFail("erreur attendue")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "offerAlreadyOpen")
        }
    }

    @MainActor
    func testTheBadgeCountsConversationsWhoseLastReceivedMessageIsUnread() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [
                MessagingRepositoriesTests.conversation("c1", lastSender: MessagingRepositoriesTests.other),
                MessagingRepositoriesTests.conversation("c2", lastSender: MessagingRepositoriesTests.other, readAt: "2026-09-07T12:11:00.000Z"),
                MessagingRepositoriesTests.conversation("c3", lastSender: MessagingRepositoriesTests.me),
            ])
        }
        let count = try await repository.refreshUnread(userId: Self.me)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(repository.unreadCount, 1)
        repository.publishUnread(-4)
        XCTAssertEqual(repository.unreadCount, 0)
    }

    @MainActor
    func testUnarchiveCallsDeleteAndOfferActionsSendTheAmountOnlyWhenNeeded() async throws {
        let api = FakeWeydaAPI()
        let repository = ConversationsRepository(api: api)
        api.onUnarchiveConversation = { id in
            XCTAssertEqual(id, "c7")
            return SimpleResponseDTO()
        }
        try await repository.setArchived(conversationId: "c7", archived: false)
        XCTAssertEqual(api.calls, ["unarchiveConversation"])

        let bodies = FakeWeydaAPI.Box<[OfferActionRequestDTO]>([])
        api.onPostOfferAction = { _, body in
            bodies.value.append(body)
            return MessageDTO(id: "m1", conversationId: "", senderId: "user_1", type: "OFFER")
        }
        let accepted = try await repository.offerAction(conversationId: "c7", action: .accept, amount: 1500)
        XCTAssertEqual(accepted.conversationId, "c7")
        _ = try await repository.offerAction(conversationId: "c7", action: .counter, amount: 1500)
        XCTAssertEqual(bodies.value.map { $0.action }, ["accept", "counter"])
        XCTAssertEqual(bodies.value.map { $0.amount }, [nil, 1500])
    }

    @MainActor
    func testTouchedIsPublished() {
        let repository = ConversationsRepository(api: FakeWeydaAPI())
        let touches = FakeWeydaAPI.Box(0)
        let subscription = repository.touched.sink { touches.value += 1 }
        repository.notifyTouched()
        repository.notifyTouched()
        XCTAssertEqual(touches.value, 2)
        subscription.cancel()
    }
}
