import Combine
import Foundation
import XCTest
@testable import Weyda

/// Parties ViewModel de ConversationsTest.kt (Android) — archivage optimiste et retour arrière, pagination par
/// curseur, pastille de l'onglet, changement de compte — mêmes cas ; les parties repository sont dans
/// `MessagingRepositoriesTests`. En plus (iOS) : interlocuteurs bloqués masqués (App Store 1.2), relecture sur
/// `touched` et au retour sur l'écran, segment, recherche et textes d'une rangée. Données fictives.
final class ConversationsViewModelTests: XCTestCase {
    private static let me = "user_1"
    private static let other = "user_2"

    private static func conversation(
        _ id: String,
        lastSender: String = other,
        readAt: String? = nil,
        deleted: Bool = false,
        content: String = "dernier message"
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
                    content: deleted ? "" : content,
                    createdAt: "2026-09-07T12:10:00.000Z",
                    senderId: lastSender,
                    readAt: readAt,
                    deletedAt: deleted ? "2026-09-07T12:11:00.000Z" : nil
                ),
            ],
            topic: "conv:\(id):abc"
        )
    }

    /// Session ouverte au nom d'Amina (`user_1`), dépôt de la messagerie sur la fausse API.
    @MainActor
    private func makeContext() -> (api: FakeWeydaAPI, session: SessionManager, repository: ConversationsRepository) {
        let api = FakeWeydaAPI()
        let session = FakeWeydaAPI.makeSession()
        session.signIn(FakeWeydaAPI.tokens())
        return (api, session, ConversationsRepository(api: api))
    }

    @MainActor
    private func makeModel(_ context: (api: FakeWeydaAPI, session: SessionManager, repository: ConversationsRepository)) -> ConversationsViewModel {
        ConversationsViewModel(conversations: context.repository, session: context.session.$user.eraseToAnyPublisher())
    }

    // MARK: - Cas d'Android

    @MainActor
    func testArchivingRemovesTheRowAndAFailurePutsItBack() async throws {
        let context = makeContext()
        context.api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [
                ConversationsViewModelTests.conversation("c1"),
                ConversationsViewModelTests.conversation("c2"),
            ])
        }
        context.api.onArchiveConversation = { _ in throw FakeWeydaAPI.apiError(500) }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1", "c2"])

        let first = try XCTUnwrap(model.state.items.first)
        let task = model.toggleArchive(first)
        XCTAssertEqual(model.state.items.map { $0.id }, ["c2"])
        await task?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1", "c2"])
        XCTAssertEqual(model.state.notice, L10n.errorServer)
    }

    @MainActor
    func testSuccessfulArchivingLeavesTheListAndNotifies() async throws {
        let context = makeContext()
        context.api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1")])
        }
        let archived = FakeWeydaAPI.Box<[String]>([])
        context.api.onArchiveConversation = { id in
            archived.value.append(id)
            return SimpleResponseDTO()
        }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(context.repository.unreadCount, 1)

        let first = try XCTUnwrap(model.state.items.first)
        await model.toggleArchive(first)?.value
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertEqual(model.state.notice, L10n.chatArchived)
        XCTAssertEqual(archived.value, ["c1"])
        // En plus d'Android : la conversation non lue a quitté la boîte de réception, la pastille suit.
        XCTAssertEqual(context.repository.unreadCount, 0)
    }

    @MainActor
    func testTheNextPageIsAppendedWithoutDuplicates() async throws {
        let context = makeContext()
        let cursors = FakeWeydaAPI.Box<[String?]>([])
        context.api.onGetConversations = { cursor, _, _ in
            cursors.value.append(cursor)
            if cursor == nil {
                return ConversationsPageDTO(
                    conversations: [ConversationsViewModelTests.conversation("c1"), ConversationsViewModelTests.conversation("c2")],
                    nextCursor: "c2"
                )
            }
            return ConversationsPageDTO(
                conversations: [ConversationsViewModelTests.conversation("c2"), ConversationsViewModelTests.conversation("c3")],
                nextCursor: nil
            )
        }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertTrue(model.state.hasMore)

        await model.loadMore()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1", "c2", "c3"])
        XCTAssertFalse(model.state.hasMore)
        XCTAssertEqual(cursors.value, [nil, "c2"])
        // Plus de curseur : plus de page suivante.
        XCTAssertNil(model.loadMore())
    }

    @MainActor
    func testTheArchivesSegmentDoesNotChangeTheBadge() async throws {
        let context = makeContext()
        context.api.onGetConversations = { _, _, archived in
            if archived == true {
                return ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("a1")])
            }
            return ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1")])
        }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(context.repository.unreadCount, 1)

        await model.setArchived(true)?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1"])
        XCTAssertTrue(model.state.archived)
        XCTAssertEqual(context.repository.unreadCount, 1)
    }

    @MainActor
    func testAccountChangeDropsThePreviousListAndIdentity() async throws {
        // Le ViewModel de l'onglet Messages peut survivre à une déconnexion.
        let context = makeContext()
        context.api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1")])
        }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1"])
        XCTAssertEqual(model.state.userId, Self.me)

        context.session.signOut()
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertEqual(model.state.userId, "")
        XCTAssertFalse(model.state.isLoading)
    }

    // MARK: - En plus (iOS)

    @MainActor
    func testBlockedPartnersAreReadWithTheListAndTheirPreviewIsHidden() async throws {
        let context = makeContext()
        context.api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1", content: "message à masquer")])
        }
        let limits = FakeWeydaAPI.Box<[Int]>([])
        context.api.onGetBlockedUsers = { _, limit in
            limits.value.append(limit)
            return BlockedUsersPageDTO(users: [BlockedUserDTO(id: ConversationsViewModelTests.other, name: "Yacine")])
        }
        let model = makeModel(context)
        await model.appear()?.value
        let conversation = try XCTUnwrap(model.state.items.first)
        XCTAssertEqual(limits.value, [ConversationsViewModel.blockedLimit])
        XCTAssertTrue(model.state.isBlocked(conversation))
        let preview = ConversationsText.preview(for: conversation, userId: Self.me, isBlocked: true)
        XCTAssertEqual(preview.text, L10n.inboxBlockedPreview)
        XCTAssertTrue(preview.isPlaceholder)
        // Le contenu masqué ne se trouve pas par la recherche ; l'interlocuteur, si.
        XCTAssertTrue(model.state.visibleItems(matching: "masquer").isEmpty)
        XCTAssertEqual(model.state.visibleItems(matching: "yacine").map { $0.id }, ["c1"])
        XCTAssertFalse(ConversationsText.accessibilityLabel(for: conversation, userId: Self.me, isBlocked: true).contains("masquer"))
    }

    @MainActor
    func testABlockedListFailureIsIgnored() async throws {
        let context = makeContext()
        context.api.onGetConversations = { _, _, _ in
            ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1")])
        }
        // Route absente avant le déploiement du lot serveur B.
        context.api.onGetBlockedUsers = { _, _ in throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1"])
        XCTAssertNil(model.state.errorMessage)
        XCTAssertTrue(model.state.blockedIds.isEmpty)
        let first = try XCTUnwrap(model.state.items.first)
        XCTAssertFalse(model.state.isBlocked(first))
    }

    @MainActor
    func testTouchedAndReturningToTheScreenReloadTheFirstPageSilently() async throws {
        let context = makeContext()
        let pages = FakeWeydaAPI.Box<[[ConversationDTO]]>([
            [ConversationsViewModelTests.conversation("c1"), ConversationsViewModelTests.conversation("c2", readAt: "2026-09-07T12:11:00.000Z")],
            [ConversationsViewModelTests.conversation("c2"), ConversationsViewModelTests.conversation("c1", readAt: "2026-09-07T12:11:00.000Z")],
            [ConversationsViewModelTests.conversation("c3"), ConversationsViewModelTests.conversation("c2")],
        ])
        context.api.onGetConversations = { _, _, _ in
            let next = pages.value.isEmpty ? [] : pages.value.removeFirst()
            return ConversationsPageDTO(conversations: next)
        }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1", "c2"])
        XCTAssertEqual(context.repository.unreadCount, 1)

        // Message reçu sur le canal personnel : l'ordre et la pastille suivent, sans écran de chargement.
        context.repository.notifyTouched()
        XCTAssertFalse(model.state.isLoading)
        await model.listTask?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c2", "c1"])
        XCTAssertEqual(context.repository.unreadCount, 1)

        // Retour depuis un fil.
        await model.appear()?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["c3", "c2"])
        XCTAssertEqual(context.repository.unreadCount, 2)
        XCTAssertEqual(context.api.count("getConversations"), 3)
    }

    @MainActor
    func testPullToRefreshFailureKeepsTheListAndGivesANotice() async throws {
        let context = makeContext()
        let fails = FakeWeydaAPI.Box(false)
        context.api.onGetConversations = { _, _, _ in
            if fails.value { throw FakeWeydaAPI.apiError(500) }
            return ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1")])
        }
        let model = makeModel(context)
        await model.appear()?.value

        fails.value = true
        await model.pullToRefresh()
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1"])
        XCTAssertFalse(model.state.isRefreshing)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.notice, L10n.errorServer)

        // Relecture silencieuse (retour sur l'écran) : aucun message.
        model.noticeShown()
        await model.appear()?.value
        XCTAssertNil(model.state.notice)
    }

    @MainActor
    func testALoadErrorShowsTheErrorStateAndRetryRecovers() async throws {
        let context = makeContext()
        let fails = FakeWeydaAPI.Box(true)
        context.api.onGetConversations = { _, _, _ in
            if fails.value { throw FakeWeydaAPI.apiError(500) }
            return ConversationsPageDTO(conversations: [ConversationsViewModelTests.conversation("c1")])
        }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorServer)
        XCTAssertFalse(model.state.isLoading)

        fails.value = false
        await model.load().value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.items.map { $0.id }, ["c1"])
    }

    @MainActor
    func testSelectingTheSameSegmentDoesNothing() async throws {
        let context = makeContext()
        context.api.onGetConversations = { _, _, _ in ConversationsPageDTO() }
        let model = makeModel(context)
        await model.appear()?.value
        XCTAssertNil(model.setArchived(false))
        XCTAssertEqual(context.api.count("getConversations"), 1)
    }

    // MARK: - Textes d'une rangée

    @MainActor
    func testRowPreviewTexts() throws {
        let deleted = ConversationsViewModelTests.conversation("c1", deleted: true).toDomain()
        XCTAssertEqual(ConversationsText.preview(for: deleted, userId: Self.me, isBlocked: false).text, L10n.chatMessageDeleted)
        XCTAssertTrue(ConversationsText.preview(for: deleted, userId: Self.me, isBlocked: false).isPlaceholder)

        let mine = ConversationsViewModelTests.conversation("c2", lastSender: Self.me, content: "J'arrive").toDomain()
        XCTAssertEqual(ConversationsText.preview(for: mine, userId: Self.me, isBlocked: false).text, L10n.chatLastMessageYou("J'arrive"))
        XCTAssertFalse(ConversationsText.preview(for: mine, userId: Self.me, isBlocked: false).isPlaceholder)

        var empty = ConversationsViewModelTests.conversation("c3").toDomain()
        empty.lastMessage = nil
        XCTAssertEqual(ConversationsText.preview(for: empty, userId: Self.me, isBlocked: false).text, L10n.chatStartConversation)

        var gone = ConversationsViewModelTests.conversation("c4").toDomain()
        gone.seller.name = ""
        XCTAssertEqual(ConversationsText.partnerName(gone, userId: Self.me), L10n.chatDeletedUser)
        XCTAssertEqual(ConversationsText.partnerName(gone, userId: Self.other), "Amina")

        XCTAssertEqual(InboxText.initial(of: "  amina k."), "A")
        XCTAssertNil(InboxText.initial(of: "   "))
        XCTAssertNil(InboxText.initial(of: nil))
    }

    @MainActor
    func testRowAccessibilityLabelAnnouncesUnreadFirst() throws {
        let unread = ConversationsViewModelTests.conversation("c1").toDomain()
        let label = ConversationsText.accessibilityLabel(for: unread, userId: Self.me, isBlocked: false)
        XCTAssertTrue(label.hasPrefix(L10n.chatUnread + ", Yacine"))
        XCTAssertTrue(label.contains("Clio 4"))
        XCTAssertTrue(label.contains("dernier message"))

        let read = ConversationsViewModelTests.conversation("c2", readAt: "2026-09-07T12:11:00.000Z").toDomain()
        XCTAssertFalse(ConversationsText.accessibilityLabel(for: read, userId: Self.me, isBlocked: false).contains(L10n.chatUnread))
    }
}

#if DEBUG
/// Données simulées de la boîte de réception (`MockFixtures/routes-inbox.json` + `inbox/`) lues par les VRAIS
/// repositories à travers `LiveWeydaAPI` et l'API simulée : conversations c1…c5 (une non lue, une avec un
/// interlocuteur bloqué), archives c6, bloqués (dont un compte supprimé), 8 notifications dont 3 non lues — telles
/// que le tour 9i les capture.
final class MockInboxFixturesTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testConversationsArchivesAndBlockedUsers() async throws {
        let repository = ConversationsRepository(api: try makeAPI())
        let me = MockSessionFixture.userId
        let inbox = try await repository.list()
        XCTAssertEqual(inbox.items.map { $0.id }, ["mock-c1", "mock-c2", "mock-c3", "mock-c4", "mock-c5"])
        XCTAssertNil(inbox.nextCursor)
        XCTAssertEqual(inbox.items.filter { $0.isUnreadFor(me) }.map { $0.id }, ["mock-c1"])
        XCTAssertEqual(inbox.items.map { $0.partner(me).name }, ["Amina K.", "Sofiane T.", "Karim B.", "Yacine M.", "Lyes A."])
        XCTAssertTrue(inbox.items.allSatisfy { $0.topic == "conv:\($0.id):mock" && $0.annonce?.imageUrl != nil })

        let archives = try await repository.list(archived: true)
        XCTAssertEqual(archives.items.map { $0.id }, ["mock-c6"])

        let blocked = try await repository.blockedUsers(page: 1, limit: ConversationsViewModel.blockedLimit)
        XCTAssertEqual(blocked.items.map { $0.id }, ["mock-u6", "mock-u9"])
        XCTAssertNil(blocked.items.last?.name)
        XCTAssertFalse(blocked.hasMore)
        try await repository.setBlocked(userId: "mock-u6", blocked: false)
        try await repository.setArchived(conversationId: "mock-c2", archived: true)
        try await repository.setArchived(conversationId: "mock-c6", archived: false)

        // L'écran tel que le tour le capture (session simulée `-WeydaLoggedIn`) : non lue en tête, aperçu de Lyes A.
        // masqué, pastille à 1.
        let session = SessionManager(
            storage: InMemorySessionStorage(tokens: MockSessionFixture.tokens(), user: MockSessionFixture.user(emailVerified: true)),
            refreshCall: { _ in throw URLError(.unsupportedURL) }
        )
        session.restore()
        let model = ConversationsViewModel(conversations: repository, session: session.$user.eraseToAnyPublisher())
        await model.appear()?.value
        XCTAssertEqual(model.state.userId, me)
        XCTAssertEqual(repository.unreadCount, 1)
        XCTAssertEqual(model.state.blockedIds, ["mock-u6", "mock-u9"])
        let c5 = try XCTUnwrap(model.state.items.last)
        XCTAssertTrue(model.state.isBlocked(c5))
        XCTAssertEqual(ConversationsText.preview(for: c5, userId: me, isBlocked: true).text, L10n.inboxBlockedPreview)
        XCTAssertEqual(model.state.items.filter { model.state.isBlocked($0) }.map { $0.id }, ["mock-c5"])
    }

    @MainActor
    func testNotifications() async throws {
        let repository = NotificationsRepository(api: try makeAPI())
        let page = try await repository.page()
        XCTAssertEqual(page.items.count, 8)
        XCTAssertEqual(page.unreadCount, 3)
        XCTAssertEqual(page.items.filter { !$0.read }.count, 3)
        XCTAssertEqual(repository.unreadCount, 3)
        XCTAssertNil(repository.topic)  // `topic: ""` : pas de temps réel en API simulée
        XCTAssertFalse(page.hasMore)
        let kinds: [NotificationKind] = page.items.map { $0.kind }
        XCTAssertEqual(kinds, [
            .message, .offerCounter, .annonceApproved, .offerAccepted, .review, .favoritePriceDrop, .searchAlert, .annonceExpired,
        ])
        let targets: [NotificationTarget?] = page.items.map { $0.target }
        let expected: [NotificationTarget?] = [
            NotificationTarget.conversation(id: "mock-c1"), NotificationTarget.conversation(id: "mock-c1"), NotificationTarget.myListings,
            NotificationTarget.conversation(id: "mock-c3"), NotificationTarget.seller(id: "mock-me"),
            NotificationTarget.listing(idOrSlug: "mock-a10"), NotificationTarget.listing(idOrSlug: "mock-a25"), NotificationTarget.myListings,
        ]
        XCTAssertEqual(targets, expected)

        try await repository.markRead(id: "mock-n1")
        try await repository.delete(id: "mock-n2", wasUnread: true)
        XCTAssertEqual(repository.unreadCount, 1)
        let updated = try await repository.markAllRead()
        XCTAssertEqual(updated, 3)
        XCTAssertEqual(repository.unreadCount, 0)
    }
}
#endif
