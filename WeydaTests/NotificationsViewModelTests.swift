import Combine
import Foundation
import XCTest
@testable import Weyda

/// Parties ViewModel de NotificationsTest.kt (Android) — tout marquer comme lu (optimiste, retour arrière), ouverture,
/// suppression, temps réel sans doublon, pagination — mêmes cas ; les parties repository (canal, pastille) sont dans
/// `MessagingRepositoriesTests`. En plus (iOS) : retour arrière d'une suppression, relecture, navigation vers la
/// cible, textes d'une rangée. Données fictives.
final class NotificationsViewModelTests: XCTestCase {
    private static func dto(_ id: String, read: Bool = false, url: String? = nil, type: String = "MESSAGE") -> NotificationDTO {
        NotificationDTO(id: id, type: type, title: "Yacine", body: "Bonjour", url: url, read: read, createdAt: "2026-09-07T12:12:43.698Z")
    }

    private static func page(_ items: [NotificationDTO], unread: Int, page: Int = 1, totalPages: Int = 1) -> NotificationsPageDTO {
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
    private func makeModel(_ api: FakeWeydaAPI) -> (model: NotificationsViewModel, repository: NotificationsRepository) {
        let repository = NotificationsRepository(api: api)
        return (NotificationsViewModel(notifications: repository), repository)
    }

    // MARK: - Cas d'Android

    @MainActor
    func testMarkAllReadIsOptimisticAndRolledBackWhenTheServerRefuses() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { _, _ in
            NotificationsViewModelTests.page([NotificationsViewModelTests.dto("n1"), NotificationsViewModelTests.dto("n2")], unread: 2)
        }
        api.onMarkAllNotificationsRead = { throw FakeWeydaAPI.apiError(500) }
        let (model, _) = makeModel(api)
        await model.appear()?.value
        XCTAssertEqual(model.state.unreadCount, 2)

        let task = model.markAllRead()
        XCTAssertEqual(model.state.unreadCount, 0)
        XCTAssertTrue(model.state.items.allSatisfy { $0.read })
        await task?.value
        XCTAssertEqual(model.state.unreadCount, 2)
        XCTAssertTrue(model.state.items.allSatisfy { !$0.read })
        XCTAssertEqual(model.state.notice, L10n.errorServer)
    }

    @MainActor
    func testMarkAllReadSuccess() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { _, _ in
            NotificationsViewModelTests.page([NotificationsViewModelTests.dto("n1"), NotificationsViewModelTests.dto("n2")], unread: 2)
        }
        api.onMarkAllNotificationsRead = { MarkAllReadDTO(updated: 2) }
        let (model, repository) = makeModel(api)
        await model.appear()?.value

        await model.markAllRead()?.value
        XCTAssertTrue(model.state.items.allSatisfy { $0.read })
        XCTAssertEqual(model.state.unreadCount, 0)
        XCTAssertEqual(repository.unreadCount, 0)
        // Plus rien à marquer : aucun appel de plus.
        XCTAssertNil(model.markAllRead())
        XCTAssertEqual(api.count("markAllNotificationsRead"), 1)
    }

    @MainActor
    func testOpeningAnUnreadNotificationMarksItReadOnlyOnce() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { _, _ in
            NotificationsViewModelTests.page([NotificationsViewModelTests.dto("n1"), NotificationsViewModelTests.dto("n2", read: true)], unread: 1)
        }
        let marked = FakeWeydaAPI.Box(0)
        api.onMarkNotificationRead = { _ in
            marked.value += 1
            return SimpleResponseDTO()
        }
        let (model, _) = makeModel(api)
        await model.appear()?.value

        let unread = try XCTUnwrap(model.state.items.first(where: { $0.id == "n1" }))
        await model.open(unread)?.value
        XCTAssertEqual(marked.value, 1)
        XCTAssertEqual(model.state.unreadCount, 0)
        XCTAssertEqual(model.state.items.first(where: { $0.id == "n1" })?.read, true)

        // Déjà lue (ou la même ligne touchée deux fois) : aucun appel supplémentaire.
        let read = try XCTUnwrap(model.state.items.first(where: { $0.id == "n2" }))
        XCTAssertNil(model.open(read))
        XCTAssertNil(model.open(unread))
        XCTAssertEqual(marked.value, 1)
    }

    @MainActor
    func testDeletingRemovesTheRowAndDecrementsWhenItWasUnread() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { _, _ in
            NotificationsViewModelTests.page([NotificationsViewModelTests.dto("n1"), NotificationsViewModelTests.dto("n2", read: true)], unread: 1)
        }
        api.onDeleteNotification = { _ in SimpleResponseDTO() }
        let (model, repository) = makeModel(api)
        await model.appear()?.value

        let first = try XCTUnwrap(model.state.items.first(where: { $0.id == "n1" }))
        await model.delete(first)?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["n2"])
        XCTAssertEqual(model.state.unreadCount, 0)
        XCTAssertEqual(repository.unreadCount, 0)
    }

    @MainActor
    func testARealtimeNotificationGoesOnTopWithoutDuplicate() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { _, _ in
            NotificationsViewModelTests.page([NotificationsViewModelTests.dto("n1", read: true)], unread: 0)
        }
        let (model, repository) = makeModel(api)
        await model.appear()?.value

        let event = AppNotification(
            id: "n9",
            kind: .offerReceived,
            title: "Sofiane",
            body: "1 800 000 DA",
            url: "/dashboard/messages/c3",
            read: false,
            createdAt: Date()
        )
        repository.onRealtime(event)
        repository.onRealtime(event)

        XCTAssertEqual(model.state.items.map { $0.id }, ["n9", "n1"])
        XCTAssertEqual(model.state.items.first?.kind, NotificationKind.offerReceived)
        XCTAssertEqual(model.state.unreadCount, 1)
        XCTAssertEqual(repository.unreadCount, 2)
    }

    @MainActor
    func testTheNextPageIsAppendedWithoutDuplicates() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { requested, _ in
            if requested == 1 {
                return NotificationsViewModelTests.page(
                    [NotificationsViewModelTests.dto("n1"), NotificationsViewModelTests.dto("n2")],
                    unread: 2,
                    page: 1,
                    totalPages: 2
                )
            }
            return NotificationsViewModelTests.page(
                [NotificationsViewModelTests.dto("n2"), NotificationsViewModelTests.dto("n3")],
                unread: 2,
                page: 2,
                totalPages: 2
            )
        }
        let (model, _) = makeModel(api)
        await model.appear()?.value
        XCTAssertTrue(model.state.hasMore)

        await model.loadMore()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["n1", "n2", "n3"])
        XCTAssertFalse(model.state.hasMore)
        XCTAssertNil(model.loadMore())
    }

    // MARK: - En plus (iOS)

    @MainActor
    func testADeleteRefusedByTheServerPutsOnlyThatRowBackInPlace() async throws {
        let api = FakeWeydaAPI()
        api.onGetNotifications = { _, _ in
            NotificationsViewModelTests.page(
                [NotificationsViewModelTests.dto("n1"), NotificationsViewModelTests.dto("n2"), NotificationsViewModelTests.dto("n3", read: true)],
                unread: 2
            )
        }
        api.onDeleteNotification = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
        let (model, repository) = makeModel(api)
        await model.appear()?.value

        let second = try XCTUnwrap(model.state.items.first(where: { $0.id == "n2" }))
        let task = model.delete(second)
        XCTAssertEqual(model.state.items.map { $0.id }, ["n1", "n3"])
        XCTAssertEqual(model.state.unreadCount, 1)
        await task?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["n1", "n2", "n3"])
        XCTAssertEqual(model.state.unreadCount, 2)
        XCTAssertEqual(model.state.notice, L10n.errorNotFound)
        XCTAssertEqual(repository.unreadCount, 2)
    }

    @MainActor
    func testReturningToTheScreenReloadsSilentlyAndALoadErrorCanBeRetried() async throws {
        let api = FakeWeydaAPI()
        let fails = FakeWeydaAPI.Box(true)
        let unread = FakeWeydaAPI.Box(2)
        api.onGetNotifications = { _, _ in
            if fails.value { throw FakeWeydaAPI.apiError(500) }
            return NotificationsViewModelTests.page(
                [NotificationsViewModelTests.dto("n1", read: unread.value == 0), NotificationsViewModelTests.dto("n2", read: unread.value == 0)],
                unread: unread.value
            )
        }
        let (model, _) = makeModel(api)
        await model.appear()?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorServer)

        fails.value = false
        await model.load().value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.unreadCount, 2)

        // Retour d'un fil : le serveur a marqué lues les notifications MESSAGE de ce fil.
        unread.value = 0
        let task = model.appear()
        XCTAssertFalse(model.state.isLoading)
        XCTAssertFalse(model.state.isRefreshing)
        await task?.value
        XCTAssertEqual(model.state.unreadCount, 0)
        XCTAssertEqual(model.state.items.first?.read, true)
    }

    @MainActor
    func testANotificationOpensTheScreenOfItsTarget() {
        XCTAssertEqual(NotificationsNavigation.route(for: .listing(idOrSlug: "clio-4-2018")), AppRoute.detail(idOrSlug: "clio-4-2018"))
        XCTAssertEqual(NotificationsNavigation.route(for: .conversation(id: "c7")), AppRoute.chat(conversationId: "c7", archived: false))
        XCTAssertEqual(NotificationsNavigation.route(for: .seller(id: "u2")), AppRoute.seller(id: "u2"))
        XCTAssertEqual(NotificationsNavigation.route(for: .myListings), AppRoute.myListings)
    }

    @MainActor
    func testRowTexts() {
        for kind in NotificationKind.allCases {
            XCTAssertFalse(NotificationsText.kindLabel(kind).isEmpty)
            XCTAssertFalse(NotificationsText.symbol(for: kind).isEmpty)
        }
        XCTAssertEqual(NotificationsText.kindLabel(.offerCounter), L10n.notificationTypeOfferCounter)
        XCTAssertEqual(NotificationsText.kindLabel(.unknown), L10n.notificationsTitle)

        let unread = NotificationsViewModelTests.dto("n1").toDomain()
        let label = NotificationsText.accessibilityLabel(for: unread)
        XCTAssertTrue(label.hasPrefix(L10n.chatUnread + ", " + L10n.notificationTypeMessage + ", Yacine, Bonjour"))
        var read = unread
        read.read = true
        XCTAssertFalse(NotificationsText.accessibilityLabel(for: read).contains(L10n.chatUnread))
    }
}
