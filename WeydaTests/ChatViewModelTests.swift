import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage de ChatViewModelTest.kt (Android), cas par cas, puis les règles propres au fil iOS : blocage, archivage,
/// signalement, « écrit… », présence, fil visible (push), refus d'une offre, lignes du fil, sens d'écriture. Données
/// fictives ; horloge fixe (`reference`) : les fenêtres de temps ne dépendent pas de l'heure du test.
final class ChatViewModelTests: XCTestCase {
    /// L'utilisateur connecté du jeu d'essai porte l'id `user_1` (comme `tokenResponse` d'Android).
    private static let me = "user_1"
    private static let other = "user_2"
    private static let reference = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Données

    private static func iso(_ minutesAgo: Double) -> String {
        DateParsing.isoString(reference.addingTimeInterval(-minutesAgo * 60))
    }

    private static func message(
        _ id: String,
        sender: String,
        content: String,
        minutesAgo: Double = 10,
        offerKind: String? = nil,
        amount: Double = 1_800_000
    ) -> MessageDTO {
        var metadata: JSONValue? = nil
        if let offerKind {
            metadata = .object(["kind": .string(offerKind), "amount": .number(amount)])
        }
        return MessageDTO(
            id: id,
            conversationId: "c1",
            senderId: sender,
            content: content,
            createdAt: iso(minutesAgo),
            type: offerKind == nil ? "TEXT" : "OFFER",
            metadata: metadata
        )
    }

    private static func thread(
        _ messages: [MessageDTO],
        hasMore: Bool = false,
        nextCursor: String? = nil,
        blocked: Bool = false,
        status: String = "ACTIVE"
    ) -> ConversationDetailDTO {
        ConversationDetailDTO(
            id: "c1",
            buyerId: me,
            sellerId: other,
            annonceId: "a1",
            updatedAt: iso(1),
            annonce: ConversationAnnonceDTO(id: "a1", title: "Clio 4", status: status, price: 1_950_000, priceType: "FIXED"),
            buyer: UserRefDTO(id: me, name: "Amina"),
            seller: UserRefDTO(id: other, name: "Yacine"),
            messages: messages,
            hasMore: hasMore,
            nextCursor: nextCursor,
            topic: "conv:c1:abc",
            isBlockedByMe: blocked
        )
    }

    private static func domain(
        _ id: String,
        _ sender: String,
        _ minutesAgo: Double,
        readAt: Date? = nil,
        deleted: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            conversationId: "c1",
            senderId: sender,
            content: "m\(id)",
            createdAt: reference.addingTimeInterval(-minutesAgo * 60),
            readAt: readAt,
            deletedAt: deleted ? reference : nil
        )
    }

    @MainActor
    private func makeModel(
        _ api: FakeWeydaAPI,
        archived: Bool = false,
        conversations: ConversationsRepository? = nil,
        realtime: ChatRealtime? = nil,
        clock: FakeWeydaAPI.Box<Date>? = nil
    ) -> ChatViewModel {
        let time = clock ?? FakeWeydaAPI.Box(Self.reference)
        return ChatViewModel(
            conversationId: "c1",
            archived: archived,
            userId: Self.me,
            conversations: conversations ?? ConversationsRepository(api: api),
            notifications: NotificationsRepository(api: api),
            reports: ReportsRepository(api: api),
            realtime: realtime ?? ChatRealtime.inert,
            now: { time.value }
        )
    }

    // MARK: - ChatViewModelTest.kt

    func testMergeMessagesDedupesByIdTheIncomingVersionWinsInChronologicalOrder() {
        let current = [Self.domain("b", Self.me, 5), Self.domain("a", Self.other, 10)]
        let incoming = [Self.domain("b", Self.me, 5, readAt: Self.reference), Self.domain("c", Self.other, 1)]
        let merged = ChatViewModel.mergeMessages(current, incoming)
        XCTAssertEqual(merged.map { $0.id }, ["a", "b", "c"])
        XCTAssertNotNil(merged.first(where: { $0.id == "b" })?.readAt)
    }

    @MainActor
    func testLoadThenOlderPageMergesWithoutDuplicates() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, cursor, _ in
            if cursor == nil {
                return ChatViewModelTests.thread(
                    [ChatViewModelTests.message("m3", sender: ChatViewModelTests.other, content: "récent", minutesAgo: 2)],
                    hasMore: true,
                    nextCursor: "m3"
                )
            }
            XCTAssertEqual(cursor, "m3")
            return ChatViewModelTests.thread([
                ChatViewModelTests.message("m1", sender: ChatViewModelTests.me, content: "ancien", minutesAgo: 40),
                ChatViewModelTests.message("m3", sender: ChatViewModelTests.other, content: "récent", minutesAgo: 2),
            ])
        }
        let model = makeModel(api)
        await model.load()?.value
        XCTAssertEqual(model.state.messages.map { $0.id }, ["m3"])
        XCTAssertTrue(model.state.hasMore)
        XCTAssertFalse(model.state.isLoading)

        await model.loadOlder()?.value
        XCTAssertEqual(model.state.messages.map { $0.id }, ["m1", "m3"])
        XCTAssertFalse(model.state.hasMore)
        // Début du fil atteint : plus de page à demander.
        XCTAssertNil(model.loadOlder())
    }

    @MainActor
    func testSendingAddsTheMessageAndClearsTheDraft() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        let sent = FakeWeydaAPI.Box<String?>(nil)
        api.onSendMessage = { _, body in
            sent.value = body.content
            return ChatViewModelTests.message("m2", sender: ChatViewModelTests.me, content: body.content, minutesAgo: 0)
        }
        let model = makeModel(api)
        await model.load()?.value
        model.updateDraft("  Toujours dispo ?  ")
        await model.send()?.value

        XCTAssertEqual(sent.value, "Toujours dispo ?")
        XCTAssertEqual(model.state.messages.map { $0.id }, ["m1", "m2"])
        XCTAssertEqual(model.state.draft, "")
        XCTAssertFalse(model.state.isSending)
    }

    @MainActor
    func testDeletingOutsideTheFiveMinuteWindowShowsANoticeWithoutNetwork() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.me, content: "trop vieux", minutesAgo: 9)])
        }
        let model = makeModel(api)
        await model.load()?.value

        model.askDelete(model.state.messages[0])
        XCTAssertNil(model.state.pendingDelete)
        XCTAssertEqual(model.state.notice, L10n.chatDeletionWindowExpired)
        XCTAssertEqual(api.count("deleteMessage"), 0)
    }

    @MainActor
    func testDeletingInsideTheWindowAsksThenMarksTheMessageDeleted() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.me, content: "oups", minutesAgo: 1)])
        }
        api.onDeleteMessage = { conversationId, messageId in
            XCTAssertEqual(conversationId, "c1")
            XCTAssertEqual(messageId, "m1")
            return SimpleResponseDTO()
        }
        let model = makeModel(api)
        await model.load()?.value

        model.askDelete(model.state.messages[0])
        XCTAssertEqual(model.state.pendingDelete?.id, "m1")
        await model.confirmDelete()?.value
        XCTAssertNil(model.state.pendingDelete)
        XCTAssertTrue(model.state.messages[0].isDeleted)
        XCTAssertEqual(model.state.messages[0].content, "")
    }

    @MainActor
    func testAcceptingAnOpenOfferSendsAcceptWithoutAmount() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([
                ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "offre", minutesAgo: 3, offerKind: "NEW"),
            ])
        }
        let request = FakeWeydaAPI.Box<OfferActionRequestDTO?>(nil)
        api.onPostOfferAction = { _, body in
            request.value = body
            return ChatViewModelTests.message("m2", sender: ChatViewModelTests.me, content: "accepte", minutesAgo: 0, offerKind: "ACCEPTED")
        }
        let model = makeModel(api)
        await model.load()?.value
        XCTAssertEqual(model.state.offerActions, Set<OfferAction>([.counter, .accept, .decline]))
        XCTAssertTrue(model.state.isActionableOffer(model.state.messages[0]))

        await model.respondToOffer(.accept)?.value
        XCTAssertEqual(request.value?.action, "accept")
        XCTAssertNil(request.value?.amount)
        XCTAssertEqual(model.state.messages.last?.offer?.kind, .accepted)
        XCTAssertFalse(model.state.isOfferBusy)
    }

    @MainActor
    func testCounterOfferDialogRecallsTheOpenAmountAndSendsTheTypedOne() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([
                ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "offre", minutesAgo: 3, offerKind: "NEW", amount: 1_800_000),
            ])
        }
        let request = FakeWeydaAPI.Box<OfferActionRequestDTO?>(nil)
        api.onPostOfferAction = { _, body in
            request.value = body
            return ChatViewModelTests.message("m2", sender: ChatViewModelTests.me, content: "contre", minutesAgo: 0, offerKind: "COUNTER", amount: 1_900_000)
        }
        let model = makeModel(api)
        await model.load()?.value

        model.openOfferDialog(.counter)
        XCTAssertEqual(model.state.offerDialog?.currentOffer, 1_800_000)
        XCTAssertEqual(model.state.offerDialog?.askingPrice, 1_950_000)
        model.updateOfferAmount("1 900 000")
        XCTAssertEqual(model.state.offerDialog?.amount, "1900000")
        await model.confirmOfferDialog()?.value

        XCTAssertEqual(request.value?.action, "counter")
        XCTAssertEqual(request.value?.amount, 1_900_000)
        XCTAssertEqual(model.state.messages.last?.type, .offer)
        XCTAssertEqual(model.state.messages.last?.offer, OfferMeta(kind: .counter, amount: 1_900_000))
        XCTAssertNil(model.state.offerDialog)
    }

    @MainActor
    func testRealtimeIncomingMessageIsInsertedOnce() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.me, content: "bonjour", minutesAgo: 5)])
        }
        let model = makeModel(api)
        await model.load()?.value

        let incoming = Self.domain("m2", Self.other, 0)
        model.applyRealtime(.messageNew(incoming))
        model.applyRealtime(.messageNew(incoming))
        XCTAssertEqual(model.state.messages.map { $0.id }, ["m1", "m2"])
    }

    @MainActor
    func testRealtimeReadReceiptOnlyTouchesMyPendingMessages() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([
                ChatViewModelTests.message("m1", sender: ChatViewModelTests.me, content: "à moi", minutesAgo: 5),
                ChatViewModelTests.message("m2", sender: ChatViewModelTests.other, content: "à lui", minutesAgo: 4),
            ])
        }
        let model = makeModel(api)
        await model.load()?.value

        let readAt = Self.reference
        model.applyRealtime(.messagesRead(readerId: Self.other, readAt: readAt))
        XCTAssertEqual(model.state.messages.first(where: { $0.id == "m1" })?.readAt, readAt)
        XCTAssertNil(model.state.messages.first(where: { $0.id == "m2" })?.readAt)
        XCTAssertEqual(model.state.lastReadOwnMessageId, "m1")

        // Mon propre accusé (autre appareil) ne change rien.
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m3", sender: ChatViewModelTests.me, content: "encore", minutesAgo: 1)])
        }
        await model.load()?.value
        model.applyRealtime(.messagesRead(readerId: Self.me, readAt: Self.reference))
        XCTAssertNil(model.state.messages.first(where: { $0.id == "m3" })?.readAt)
    }

    @MainActor
    func testRealtimeDeletionHidesAKnownMessageAndIgnoresOthers() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "oups", minutesAgo: 2)])
        }
        let model = makeModel(api)
        await model.load()?.value

        model.applyRealtime(.messageDeleted(conversationId: "c1", messageId: "inconnu"))
        XCTAssertFalse(model.state.messages[0].isDeleted)

        model.applyRealtime(.messageDeleted(conversationId: "c1", messageId: "m1"))
        XCTAssertTrue(model.state.messages[0].isDeleted)
        XCTAssertEqual(model.state.messages[0].content, "")
    }

    @MainActor
    func testInvalidOfferMetadataLeavesAPlainMessage() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([
                MessageDTO(id: "m1", senderId: ChatViewModelTests.other, content: "offre", createdAt: ChatViewModelTests.iso(2), type: "OFFER", metadata: nil),
            ])
        }
        let model = makeModel(api)
        await model.load()?.value
        XCTAssertNil(model.state.messages[0].offer)
        XCTAssertEqual(model.state.offerActions, Set<OfferAction>([.new]))
        XCTAssertTrue(model.state.canMakeOffer)
    }

    // MARK: - Fil iOS : chargement, blocage, archivage

    @MainActor
    func testFailedLoadShowsTheCauseThenRetrySucceeds() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in throw FakeWeydaAPI.apiError(500) }
        let model = makeModel(api)
        await model.load()?.value
        XCTAssertFalse(model.state.isLoading)
        XCTAssertEqual(model.state.errorMessage, L10n.errorServer)
        XCTAssertNil(model.state.conversation)

        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        await model.load()?.value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.partnerName, "Yacine")
        XCTAssertEqual(model.state.annonceId, "a1")
    }

    @MainActor
    func testABlockedThreadOffersUnblockAndBlockingAsksFirst() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread(
                [ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "insistant", minutesAgo: 5)],
                blocked: true
            )
        }
        let unblocked = FakeWeydaAPI.Box<[String]>([])
        api.onUnblockUser = { id in
            unblocked.value.append(id)
            return SimpleResponseDTO()
        }
        let blocked = FakeWeydaAPI.Box<[String]>([])
        api.onBlockUser = { id in
            blocked.value.append(id)
            return SimpleResponseDTO()
        }
        let model = makeModel(api)
        await model.load()?.value
        XCTAssertTrue(model.state.isBlocked)
        // Bloqué : pas de raccourci « Faire une offre » (le composeur est remplacé par l'encart).
        XCTAssertFalse(model.state.canMakeOffer)

        await model.setBlocked(false)?.value
        XCTAssertEqual(unblocked.value, [Self.other])
        XCTAssertFalse(model.state.isBlocked)
        XCTAssertEqual(model.state.notice, L10n.chatUnblockedDone)

        // Bloquer passe par une confirmation ; l'annuler n'appelle rien.
        model.askBlock()
        XCTAssertTrue(model.state.isBlockConfirmPending)
        model.dismissConfirmations()
        XCTAssertFalse(model.state.isBlockConfirmPending)
        XCTAssertTrue(blocked.value.isEmpty)

        model.askBlock()
        await model.confirmBlock()?.value
        XCTAssertEqual(blocked.value, [Self.other])
        XCTAssertTrue(model.state.isBlocked)
        XCTAssertFalse(model.state.isBlockConfirmPending)
        XCTAssertEqual(model.state.notice, L10n.chatBlockedDone)
    }

    @MainActor
    func testArchiveTogglesAndAnnouncesAndAnArchivedThreadUnarchives() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        api.onArchiveConversation = { _ in SimpleResponseDTO() }
        api.onUnarchiveConversation = { _ in SimpleResponseDTO() }
        let model = makeModel(api)
        await model.load()?.value
        await model.toggleArchive()?.value
        XCTAssertTrue(model.state.isArchived)
        XCTAssertEqual(model.state.notice, L10n.chatArchived)

        let archived = makeModel(api, archived: true)
        await archived.toggleArchive()?.value
        XCTAssertFalse(archived.state.isArchived)
        XCTAssertEqual(archived.state.notice, L10n.chatUnarchived)
        XCTAssertEqual(api.count("archiveConversation"), 1)
        XCTAssertEqual(api.count("unarchiveConversation"), 1)
    }

    // MARK: - Signaler l'interlocuteur

    @MainActor
    func testReportingThePartnerSendsTheThreadAsContextThenCloses() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "arnaque", minutesAgo: 5)])
        }
        let body = FakeWeydaAPI.Box<ReportRequestDTO?>(nil)
        api.onReport = { request in
            body.value = request
            return ReportDTO()
        }
        let model = makeModel(api)
        await model.load()?.value
        model.openReport()
        XCTAssertTrue(model.isReportPresented)

        await model.confirmReport(reason: .fraud, details: "  Demande un virement avant de venir.  ")?.value
        XCTAssertEqual(body.value?.reportedUserId, Self.other)
        XCTAssertEqual(body.value?.conversationId, "c1")
        XCTAssertNil(body.value?.annonceId)
        XCTAssertEqual(body.value?.reason, "FRAUD")
        XCTAssertEqual(body.value?.details, "Demande un virement avant de venir.")
        XCTAssertFalse(model.isReportPresented)
        XCTAssertEqual(model.state.notice, L10n.reportSent)
    }

    @MainActor
    func testReportOfflineKeepsTheSheetAndAServerVerdictClosesIt() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "arnaque", minutesAgo: 5)])
        }
        api.onReport = { _ in throw URLError(.notConnectedToInternet) }
        let model = makeModel(api)
        await model.load()?.value
        model.openReport()
        await model.confirmReport(reason: .spam, details: "")?.value
        XCTAssertTrue(model.isReportPresented)
        XCTAssertEqual(model.state.reportError, L10n.errorOffline)
        XCTAssertFalse(model.state.isReportBusy)

        api.onReport = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"alreadyReported"}"#) }
        await model.confirmReport(reason: .spam, details: "")?.value
        XCTAssertFalse(model.isReportPresented)
        XCTAssertEqual(model.state.notice, L10n.errorAlreadyReported)
    }

    // MARK: - Offres : refus et pannes

    @MainActor
    func testOfferServerVerdictClosesTheSheetButANetworkFailureKeepsIt() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        api.onPostOfferAction = { _, _ in throw URLError(.notConnectedToInternet) }
        let model = makeModel(api)
        await model.load()?.value

        model.openOfferDialog(.new)
        XCTAssertNil(model.state.offerDialog?.currentOffer)
        model.updateOfferAmount("1700000")
        await model.confirmOfferDialog()?.value
        XCTAssertNotNil(model.state.offerDialog)
        XCTAssertEqual(model.state.offerDialog?.amount, "1700000")
        XCTAssertEqual(model.state.offerError, L10n.errorOffline)

        api.onPostOfferAction = { _, _ in throw FakeWeydaAPI.apiError(409, #"{"error":"offerAlreadyOpen"}"#) }
        await model.confirmOfferDialog()?.value
        XCTAssertNil(model.state.offerDialog)
        XCTAssertNil(model.state.offerError)
        XCTAssertEqual(model.state.notice, L10n.errorOfferAlreadyOpen)
    }

    @MainActor
    func testAnInvalidAmountIsNeverSent() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        let model = makeModel(api)
        await model.load()?.value
        model.openOfferDialog(.new)
        model.updateOfferAmount("0")
        XCTAssertNil(model.confirmOfferDialog())
        model.updateOfferAmount("")
        XCTAssertNil(model.confirmOfferDialog())
        // Accepter / refuser ne passent jamais par la feuille, et « nouvelle offre » ne s'envoie pas sans montant.
        XCTAssertNil(model.respondToOffer(.new))
        XCTAssertEqual(api.count("postOfferAction"), 0)
    }

    func testOfferAmountParsingFollowsTheServerBounds() {
        XCTAssertNil(OfferDialogState.parse(""))
        XCTAssertNil(OfferDialogState.parse("0"))
        XCTAssertEqual(OfferDialogState.parse("1"), 1)
        XCTAssertEqual(OfferDialogState.parse("9999999999"), 9_999_999_999)
        XCTAssertNil(OfferDialogState.parse("10000000000"))
        // Clavier arabe : chiffres ramenés en ASCII.
        XCTAssertEqual(OfferDialogState.parse("\u{0661}\u{0662}\u{0663}"), 123)
        XCTAssertEqual(OfferDialogState.sanitize("3 050 000 DA"), "3050000")
        XCTAssertEqual(OfferDialogState.sanitize("123456789012"), "1234567890")
    }

    // MARK: - Saisie, « écrit… », présence

    @MainActor
    func testTypingIsThrottledAndStoppedWhenTheFieldEmpties() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        let signals = FakeWeydaAPI.Box<[Bool]>([])
        let topics = FakeWeydaAPI.Box<[String]>([])
        let realtime = ChatRealtime(
            isEnabled: true,
            updates: { _, _, _ in
                AsyncStream(ConversationRealtimeUpdate.self) { continuation in
                    continuation.finish()
                }
            },
            sendTyping: { topic, userId, isTyping in
                XCTAssertEqual(userId, ChatViewModelTests.me)
                topics.value.append(topic)
                signals.value.append(isTyping)
            },
            reconnections: Empty<Void, Never>().eraseToAnyPublisher()
        )
        let clock = FakeWeydaAPI.Box(Self.reference)
        let model = makeModel(api, realtime: realtime, clock: clock)
        await model.load()?.value

        model.updateDraft("B")
        clock.value = Self.reference.addingTimeInterval(1)
        model.updateDraft("Bo")
        clock.value = Self.reference.addingTimeInterval(3.5)
        model.updateDraft("Bon")
        model.updateDraft("")
        XCTAssertEqual(signals.value, [true, true, false])
        XCTAssertEqual(Set(topics.value), ["conv:c1:abc"])
    }

    @MainActor
    func testTheDraftIsCappedAtTheServerLength() {
        let model = makeModel(FakeWeydaAPI())
        model.updateDraft(String(repeating: "a", count: ChatState.messageMax + 50))
        XCTAssertEqual(model.state.draft.utf16.count, ChatState.messageMax)
        // Un brouillon blanc ne part pas.
        model.updateDraft("   ")
        XCTAssertFalse(model.state.canSend)
        XCTAssertNil(model.send())
    }

    @MainActor
    func testPresenceAndTypingOfThePartnerOnly() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        let model = makeModel(api)
        await model.load()?.value

        model.apply(.presence([Self.me, Self.other]))
        XCTAssertTrue(model.state.isPartnerOnline)
        model.apply(.presence([Self.me]))
        XCTAssertFalse(model.state.isPartnerOnline)

        model.apply(.event(.typing(userId: Self.me, isTyping: true)))
        XCTAssertFalse(model.state.isPartnerTyping)
        model.apply(.event(.typing(userId: Self.other, isTyping: true)))
        XCTAssertTrue(model.state.isPartnerTyping)
        model.apply(.event(.typing(userId: Self.other, isTyping: false)))
        XCTAssertFalse(model.state.isPartnerTyping)
    }

    @MainActor
    func testTheOpenThreadIsMarkedVisibleForPushUntilItDisappears() async {
        let api = FakeWeydaAPI()
        api.onGetConversation = { _, _, _ in
            ChatViewModelTests.thread([ChatViewModelTests.message("m1", sender: ChatViewModelTests.other, content: "bonjour", minutesAgo: 5)])
        }
        let conversations = ConversationsRepository(api: api)
        let model = makeModel(api, conversations: conversations)

        await model.appear()?.value
        XCTAssertEqual(conversations.visibleConversationId, "c1")
        XCTAssertEqual(model.state.messages.map { $0.id }, ["m1"])
        model.disappear()
        XCTAssertNil(conversations.visibleConversationId)

        // Un autre fil ouvert entre-temps garde sa marque.
        _ = model.appear()
        conversations.visibleConversationId = "c9"
        model.disappear()
        XCTAssertEqual(conversations.visibleConversationId, "c9")
        // Un seul chargement « plein » : le retour relit en silence (après un court délai).
        XCTAssertEqual(api.count("getConversation"), 1)
    }

    // MARK: - Lignes du fil

    func testTimelineRowsCarryReceiptGroupsActionsAndDeletion() {
        let userId = Self.me
        var counter = Self.domain("o1", Self.other, 3)
        counter.type = .offer
        counter.offer = OfferMeta(kind: .counter, amount: 3_050_000)
        let messages = [
            Self.domain("a", userId, 30, readAt: Self.reference),
            Self.domain("b", userId, 29, readAt: Self.reference),
            Self.domain("c", Self.other, 20),
            counter,
            Self.domain("d", userId, 1),
        ]
        // Fuseau fixé : les cinq messages (30 dernières minutes) tombent le même jour civil.
        let utc = ChatDayGrouping.deviceCalendar(timeZone: TimeZone(identifier: "UTC") ?? .current)
        let rows = ChatTimeline.rows(messages: messages, userId: userId, now: Self.reference, calendar: utc)
        XCTAssertEqual(rows.map { $0.id }, ["a", "b", "c", "o1", "d"])
        // « Lu » une seule fois, sous mon DERNIER message lu.
        XCTAssertEqual(rows.filter { $0.showsReadReceipt }.map { $0.id }, ["b"])
        // Suites du même auteur : a+b ; c seul ; la carte d'offre toujours à part.
        XCTAssertEqual(rows.map { $0.startsGroup }, [true, false, true, true, true])
        XCTAssertEqual(rows.map { $0.endsGroup }, [false, true, true, true, true])
        // Boutons de réponse : seulement l'offre ouverte de l'autre partie.
        XCTAssertEqual(rows.filter { $0.isActionableOffer }.map { $0.id }, ["o1"])
        // Supprimable : mon message de moins de 5 minutes.
        XCTAssertEqual(rows.filter { $0.canDelete }.map { $0.id }, ["d"])
        XCTAssertEqual(rows.filter { $0.isMine }.map { $0.id }, ["a", "b", "d"])
    }

    func testUserTextDirectionFollowsItsFirstStrongLetter() {
        XCTAssertTrue(ChatTextDirection.isRightToLeft("مرحبا، هل ما زال متاحا؟"))
        XCTAssertTrue(ChatTextDirection.isRightToLeft("3 050 000 دج"))
        XCTAssertFalse(ChatTextDirection.isRightToLeft("Bonjour, toujours dispo ?"))
        XCTAssertFalse(ChatTextDirection.isRightToLeft("205 000 DA, d'accord"))
        XCTAssertFalse(ChatTextDirection.isRightToLeft(""))
    }

    func testListingBannerTexts() {
        let free = ConversationAnnonce(id: "a24", title: "Canapé", imageUrl: nil, status: .active, price: nil, priceType: .free)
        XCTAssertEqual(ChatListingText.price(free), L10n.priceFree)
        XCTAssertNil(ChatListingText.status(free.status))
        let sold = ConversationAnnonce(id: "a17", title: "MacBook", imageUrl: nil, status: .sold, price: 135_000, priceType: .fixed)
        XCTAssertEqual(ChatListingText.price(sold), Format.amount(135_000))
        XCTAssertEqual(ChatListingText.status(sold.status), L10n.statusSold)
        let onRequest = ConversationAnnonce(id: "a9", title: "Studio", imageUrl: nil)
        XCTAssertNil(ChatListingText.price(onRequest))
    }
}

#if DEBUG
/// Données simulées du fil (`MockFixtures/routes-chat.json` + `chat/`) lues par les vrais repositories : les six fils
/// du tableau de CONTRACTS-P5.md et les réponses des écritures (contact, offre, envoi, blocage, signalement).
final class MockChatFixturesTests: XCTestCase {
    private static let me = "mock-me"

    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testTheSixThreadsMatchTheInboxTable() async throws {
        let repository = ConversationsRepository(api: try makeAPI())
        let me = Self.me

        let c1 = try await repository.thread(id: "mock-c1")
        XCTAssertEqual(c1.conversation.partner(me).name, "Amina K.")
        XCTAssertFalse(c1.conversation.isSeller(me))
        XCTAssertEqual(c1.messages.last?.content, "Je peux descendre à 3 050 000 DA, pas moins. Elle a fait sa vidange le mois dernier.")
        let open = try XCTUnwrap(OfferRules.openOffer(c1.messages))
        XCTAssertEqual(open.offer, OfferMeta(kind: .counter, amount: 3_050_000))
        XCTAssertTrue(OfferRules.isActionable(open, by: me, messages: c1.messages))
        XCTAssertTrue(c1.messages.contains(where: { $0.isDeleted && $0.isMine(me) }))
        XCTAssertNil(c1.messages.last?.readAt)
        XCTAssertEqual(c1.conversation.topic, "conv:mock-c1:mock")

        let c2 = try await repository.thread(id: "mock-c2")
        XCTAssertEqual(c2.conversation.partner(me).name, "Sofiane T.")
        XCTAssertTrue(c2.conversation.isSeller(me))
        XCTAssertEqual(c2.messages.last?.senderId, me)

        let c3 = try await repository.thread(id: "mock-c3")
        XCTAssertEqual(OfferRules.latestOffer(c3.messages)?.offer, OfferMeta(kind: .accepted, amount: 205_000))
        XCTAssertNil(OfferRules.openOffer(c3.messages))

        let c4 = try await repository.thread(id: "mock-c4")
        XCTAssertEqual(c4.conversation.annonce?.priceType, .free)
        XCTAssertTrue(OfferRules.availableActions(userId: me, messages: c4.messages, annonce: c4.conversation.annonce).isEmpty)
        XCTAssertNotNil(c4.messages.last?.readAt)

        let c5 = try await repository.thread(id: "mock-c5")
        XCTAssertTrue(c5.isBlockedByMe)
        XCTAssertEqual(c5.conversation.partner(me).id, "mock-u6")

        let c6 = try await repository.thread(id: "mock-c6")
        XCTAssertEqual(c6.conversation.annonce?.status, .sold)
        XCTAssertFalse(c6.conversation.annonce?.acceptsOffers ?? true)

        for thread in [c1, c2, c3, c4, c5, c6] {
            XCTAssertTrue((6...14).contains(thread.messages.count), thread.conversation.id)
            XCTAssertFalse(thread.hasMore, thread.conversation.id)
            XCTAssertNotNil(thread.conversation.annonce?.imageUrl, thread.conversation.id)
        }
    }

    @MainActor
    func testWritesAnswerLikeTheServer() async throws {
        let api = try makeAPI()
        let repository = ConversationsRepository(api: api)
        let started = try await repository.startConversation(annonceId: "mock-a2", message: "Bonjour, est-ce encore disponible ?")
        XCTAssertEqual(started.conversationId, "mock-c1")
        let offered = try await repository.makeOffer(annonceId: "mock-a2", amount: 2_900_000)
        XCTAssertEqual(offered, ConversationEntry(conversationId: "mock-c1", created: true))
        let sent = try await repository.send(conversationId: "mock-c2", content: "Merci")
        XCTAssertEqual(sent.conversationId, "mock-c2")
        XCTAssertEqual(sent.senderId, Self.me)
        let reply = try await repository.offerAction(conversationId: "mock-c1", action: .accept)
        XCTAssertEqual(reply.type, .offer)
        XCTAssertEqual(reply.offer?.kind, .accepted)
        try await repository.deleteMessage(conversationId: "mock-c1", messageId: "mock-c1-m6")
        try await repository.setBlocked(userId: "mock-u6", blocked: true)
        try await ReportsRepository(api: api).reportUser(userId: "mock-u6", conversationId: "mock-c5", reason: .fraud, details: nil)
    }
}
#endif
