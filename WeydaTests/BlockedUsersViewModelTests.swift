import Foundation
import XCTest
@testable import Weyda

/// « Utilisateurs bloqués » (propre à iOS, App Store 1.2 — pas d'équivalent Android) : liste paginée de
/// `GET /api/users/me/blocked`, déblocage confirmé (`DELETE /api/users/{id}/block`), erreurs, textes d'une ligne.
/// Données fictives.
final class BlockedUsersViewModelTests: XCTestCase {
    private static func blocked(_ id: String, name: String? = "Lyes A.", at: String? = "2026-09-30T22:50:00.000Z") -> BlockedUserDTO {
        BlockedUserDTO(id: id, name: name, avatar: nil, blockedAt: at)
    }

    @MainActor
    private func makeModel(_ api: FakeWeydaAPI) -> BlockedUsersViewModel {
        BlockedUsersViewModel(conversations: ConversationsRepository(api: api))
    }

    @MainActor
    func testTheListLoadsOnceWithDeletedAccounts() async throws {
        let api = FakeWeydaAPI()
        let requests = FakeWeydaAPI.Box<[String]>([])
        api.onGetBlockedUsers = { page, limit in
            requests.value.append("\(page)|\(limit)")
            return BlockedUsersPageDTO(
                users: [BlockedUsersViewModelTests.blocked("u6"), BlockedUsersViewModelTests.blocked("u9", name: nil)],
                total: 2,
                page: 1,
                totalPages: 1
            )
        }
        let model = makeModel(api)
        XCTAssertTrue(model.state.isLoading)
        await model.appear()?.value
        XCTAssertFalse(model.state.isLoading)
        XCTAssertEqual(model.state.items.map { $0.id }, ["u6", "u9"])
        XCTAssertEqual(requests.value, ["1|\(BlockedUsersViewModel.pageSize)"])
        XCTAssertFalse(model.state.canLoadMore)

        let deleted = try XCTUnwrap(model.state.items.last)
        XCTAssertNil(deleted.name)
        XCTAssertEqual(BlockedUsersText.name(of: deleted), L10n.chatDeletedUser)
        let named = try XCTUnwrap(model.state.items.first)
        XCTAssertEqual(BlockedUsersText.name(of: named), "Lyes A.")

        // Retour sur l'écran : pas de nouvelle requête.
        XCTAssertNil(model.appear())
        XCTAssertEqual(requests.value.count, 1)
    }

    @MainActor
    func testUnblockingAfterConfirmationRemovesTheRow() async throws {
        let api = FakeWeydaAPI()
        api.onGetBlockedUsers = { _, _ in
            BlockedUsersPageDTO(users: [BlockedUsersViewModelTests.blocked("u6"), BlockedUsersViewModelTests.blocked("u9", name: nil)])
        }
        let unblocked = FakeWeydaAPI.Box<[String]>([])
        api.onUnblockUser = { id in
            unblocked.value.append(id)
            return SimpleResponseDTO()
        }
        let model = makeModel(api)
        await model.appear()?.value
        let user = try XCTUnwrap(model.state.items.first)

        // Annuler : rien ne part.
        model.askUnblock(user)
        XCTAssertEqual(model.state.pendingUnblock, user)
        model.dismissUnblock()
        XCTAssertNil(model.state.pendingUnblock)
        XCTAssertNil(model.confirmUnblock())
        XCTAssertTrue(unblocked.value.isEmpty)

        model.askUnblock(user)
        let task = model.confirmUnblock()
        XCTAssertNil(model.state.pendingUnblock)
        XCTAssertEqual(model.state.busyId, "u6")
        await task?.value
        XCTAssertEqual(unblocked.value, ["u6"])
        XCTAssertEqual(model.state.items.map { $0.id }, ["u9"])
        XCTAssertNil(model.state.busyId)
        XCTAssertEqual(model.state.notice, L10n.chatUnblockedDone)
        XCTAssertEqual(api.calls.filter { $0 == "blockUser" }.count, 0)
    }

    @MainActor
    func testARefusedUnblockKeepsTheRowAndShowsTheError() async throws {
        let api = FakeWeydaAPI()
        api.onGetBlockedUsers = { _, _ in
            BlockedUsersPageDTO(users: [BlockedUsersViewModelTests.blocked("u6")])
        }
        api.onUnblockUser = { _ in throw FakeWeydaAPI.apiError(500) }
        let model = makeModel(api)
        await model.appear()?.value
        let user = try XCTUnwrap(model.state.items.first)

        model.askUnblock(user)
        await model.confirmUnblock()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["u6"])
        XCTAssertNil(model.state.busyId)
        XCTAssertEqual(model.state.notice, L10n.errorServer)
        model.noticeShown()
        XCTAssertNil(model.state.notice)
    }

    @MainActor
    func testALoadErrorShowsTheErrorStateAndRetryRecovers() async throws {
        let api = FakeWeydaAPI()
        let fails = FakeWeydaAPI.Box(true)
        api.onGetBlockedUsers = { _, _ in
            if fails.value { throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
            return BlockedUsersPageDTO()
        }
        let model = makeModel(api)
        await model.appear()?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorNotFound)
        XCTAssertTrue(model.state.items.isEmpty)

        fails.value = false
        await model.load().value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertTrue(model.state.items.isEmpty)  // état vide : « comment bloquer »
        XCTAssertFalse(model.state.isLoading)
    }

    @MainActor
    func testTheNextPageIsAppendedWithoutDuplicates() async throws {
        let api = FakeWeydaAPI()
        api.onGetBlockedUsers = { page, _ in
            if page == 1 {
                return BlockedUsersPageDTO(
                    users: [BlockedUsersViewModelTests.blocked("u1"), BlockedUsersViewModelTests.blocked("u2")],
                    total: 3,
                    page: 1,
                    totalPages: 2
                )
            }
            return BlockedUsersPageDTO(
                users: [BlockedUsersViewModelTests.blocked("u2"), BlockedUsersViewModelTests.blocked("u3")],
                total: 3,
                page: 2,
                totalPages: 2
            )
        }
        let model = makeModel(api)
        await model.appear()?.value
        XCTAssertTrue(model.state.canLoadMore)

        await model.loadMore()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["u1", "u2", "u3"])
        XCTAssertFalse(model.state.canLoadMore)
        XCTAssertNil(model.loadMore())
    }

    @MainActor
    func testPullToRefreshReplacesTheList() async throws {
        let api = FakeWeydaAPI()
        let users = FakeWeydaAPI.Box<[BlockedUserDTO]>([BlockedUsersViewModelTests.blocked("u6")])
        api.onGetBlockedUsers = { _, _ in BlockedUsersPageDTO(users: users.value) }
        let model = makeModel(api)
        await model.appear()?.value

        users.value = [BlockedUsersViewModelTests.blocked("u7"), BlockedUsersViewModelTests.blocked("u6")]
        await model.pullToRefresh()
        XCTAssertEqual(model.state.items.map { $0.id }, ["u7", "u6"])
        XCTAssertFalse(model.state.isRefreshing)
    }

    func testBlockedSinceUsesTheLocalizedDate() throws {
        let user = BlockedUser(id: "u6", name: "Lyes A.", avatarUrl: nil, blockedAt: DateParsing.parseInstant("2026-09-30T22:50:00.000Z"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let locale = WeydaLocale.latinDigits(language: "fr", region: "DZ")
        let text = try XCTUnwrap(BlockedUsersText.blockedSince(user, locale: locale, timeZone: utc))
        XCTAssertEqual(text, L10n.inboxBlockedOn(Format.date(user.blockedAt, locale: locale, timeZone: utc)))
        XCTAssertTrue(text.contains("2026"))

        let undated = BlockedUser(id: "u9", name: nil, avatarUrl: nil, blockedAt: nil)
        XCTAssertNil(BlockedUsersText.blockedSince(undated))
    }
}
