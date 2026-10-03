import Combine
import Foundation
import XCTest
@testable import Weyda

/// Contact et offre depuis la fiche — les règles de `DetailViewModel.sendFirstMessage` / `confirmOffer` (Android) :
/// premier message envoyé sur l'id RÉEL de l'annonce puis fil ouvert, offre initiale, 409 `offerAlreadyOpen` qui ouvre la
/// conversation existante sans erreur, refus et pannes affichés dans la feuille, actions absentes pour le propriétaire
/// et sur une annonce gratuite. Données fictives.
final class DetailMessagingTests: XCTestCase {
    // MARK: - Données

    private static func listing(priceType: String = "NEGOTIABLE", price: Double? = 1_850_000, sellerId: String = "u1") -> AnnonceDTO {
        AnnonceDTO(
            id: "cm_real_id",
            slug: "clio-4-2019",
            title: "Clio 4",
            description: String(repeating: "d", count: 30),
            price: price,
            priceType: priceType,
            status: "ACTIVE",
            hasPhone: false,
            createdAt: "2026-09-01T10:00:00.000Z",
            category: CategoryRefDTO(
                id: "cat_voit",
                slug: "voitures",
                nameFr: "Voitures",
                parent: ParentRefDTO(slug: "vehicules")
            ),
            user: UserRefDTO(id: sellerId, name: "Karim B.")
        )
    }

    private static func member(_ id: String = "u9") -> User {
        User(id: id, name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: true)
    }

    /// Fiche ouverte par son slug (comme depuis un lien) : le reste (avis, similaires, libellés) échoue en silence.
    @MainActor
    private func makeAPI(_ annonce: AnnonceDTO = DetailMessagingTests.listing()) -> FakeWeydaAPI {
        let api = FakeWeydaAPI()
        api.onGetAnnonce = { _ in annonce }
        api.onIsFavorite = { _ in IsFavoriteDTO(isFavorite: false) }
        return api
    }

    @MainActor
    private func makeModel(_ api: FakeWeydaAPI, user: User? = DetailMessagingTests.member()) -> DetailViewModel {
        DetailViewModel(
            idOrSlug: "clio-4-2019",
            annonces: AnnonceRepository(api: api),
            favorites: FavoritesRepository(api: api),
            reviews: ReviewsRepository(api: api),
            attributes: AttributeRepository(api: api),
            conversations: ConversationsRepository(api: api),
            reports: ReportsRepository(api: api),
            sessionUser: Just(user).eraseToAnyPublisher(),
            locale: { "fr" }
        )
    }

    // MARK: - Contacter

    @MainActor
    func testContactSendsTheFirstMessageOnTheRealIdThenOpensTheThread() async {
        let api = makeAPI()
        let body = FakeWeydaAPI.Box<CreateConversationRequestDTO?>(nil)
        api.onCreateConversation = { request in
            body.value = request
            return ConversationCreatedDTO(conversationId: "c1")
        }
        let model = makeModel(api)
        await model.load()

        model.openContact()
        XCTAssertEqual(model.state.contactMessage, "")
        model.updateContactMessage("  Bonjour, est-ce encore disponible ?  ")
        await model.sendFirstMessage()?.value

        XCTAssertEqual(body.value?.annonceId, "cm_real_id")
        XCTAssertEqual(body.value?.message, "Bonjour, est-ce encore disponible ?")
        XCTAssertNil(model.state.contactMessage)
        XCTAssertFalse(model.state.isContacting)
        XCTAssertNil(model.state.contactError)
        XCTAssertEqual(model.state.openConversationId, "c1")

        model.conversationOpened()
        XCTAssertNil(model.state.openConversationId)
    }

    @MainActor
    func testARefusedContactStaysOpenWithTheReason() async {
        let api = makeAPI()
        api.onCreateConversation = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"userBlocked"}"#) }
        let model = makeModel(api)
        await model.load()

        model.openContact()
        model.updateContactMessage("Bonjour")
        await model.sendFirstMessage()?.value
        XCTAssertEqual(model.state.contactError, L10n.errorUserBlocked)
        XCTAssertEqual(model.state.contactMessage, "Bonjour")
        XCTAssertNil(model.state.openConversationId)

        // Reprendre la saisie efface l'erreur.
        model.updateContactMessage("Bonjour !")
        XCTAssertNil(model.state.contactError)
    }

    @MainActor
    func testABlankMessageIsNotSentAndCancelClosesTheSheet() async {
        let api = makeAPI()
        let model = makeModel(api)
        await model.load()

        model.openContact()
        model.updateContactMessage("   ")
        XCTAssertNil(model.sendFirstMessage())
        XCTAssertEqual(api.count("createConversation"), 0)

        model.dismissContact()
        XCTAssertNil(model.state.contactMessage)
    }

    @MainActor
    func testTheOwnerCannotContactNorMakeAnOffer() async {
        let api = makeAPI(Self.listing(sellerId: "u9"))
        let model = makeModel(api, user: Self.member("u9"))
        await model.load()
        XCTAssertTrue(model.state.isOwner)

        model.openContact()
        XCTAssertNil(model.state.contactMessage)
        model.openOfferDialog()
        XCTAssertNil(model.state.offerDialog)
    }

    // MARK: - Faire une offre

    @MainActor
    func testAnOfferFromTheListingRecallsThePriceAndOpensTheThread() async {
        let api = makeAPI()
        let sent = FakeWeydaAPI.Box<[Int]>([])
        api.onInitiateOffer = { id, body in
            XCTAssertEqual(id, "cm_real_id")
            sent.value.append(body.amount)
            return ConversationCreatedDTO(conversationId: "c5")
        }
        let model = makeModel(api)
        await model.load()

        model.openOfferDialog()
        XCTAssertEqual(model.state.offerDialog?.action, .new)
        XCTAssertEqual(model.state.offerDialog?.askingPrice, 1_850_000)
        XCTAssertNil(model.state.offerDialog?.currentOffer)
        model.updateOfferAmount("1 800 000")
        XCTAssertEqual(model.state.offerDialog?.amount, "1800000")
        await model.confirmOffer()?.value

        XCTAssertEqual(sent.value, [1_800_000])
        XCTAssertNil(model.state.offerDialog)
        XCTAssertFalse(model.state.isOfferBusy)
        XCTAssertEqual(model.state.openConversationId, "c5")
    }

    @MainActor
    func testAnAlreadyOpenOfferOpensTheExistingThreadWithoutError() async {
        let api = makeAPI()
        api.onInitiateOffer = { _, _ in
            throw FakeWeydaAPI.apiError(409, #"{"error":"offerAlreadyOpen","conversationId":"c9"}"#)
        }
        let model = makeModel(api)
        await model.load()

        model.openOfferDialog()
        model.updateOfferAmount("1700000")
        await model.confirmOffer()?.value
        XCTAssertEqual(model.state.openConversationId, "c9")
        XCTAssertNil(model.state.offerError)
        XCTAssertNil(model.state.offerDialog)
    }

    @MainActor
    func testAnOfferFailureStaysInTheSheetAndAnInvalidAmountIsNotSent() async {
        let api = makeAPI()
        api.onInitiateOffer = { _, _ in throw URLError(.notConnectedToInternet) }
        let model = makeModel(api)
        await model.load()

        model.openOfferDialog()
        model.updateOfferAmount("0")
        XCTAssertNil(model.confirmOffer())
        XCTAssertEqual(api.count("initiateOffer"), 0)

        model.updateOfferAmount("1700000")
        await model.confirmOffer()?.value
        XCTAssertEqual(model.state.offerError, L10n.errorOffline)
        XCTAssertEqual(model.state.offerDialog?.amount, "1700000")
        XCTAssertNil(model.state.openConversationId)

        model.dismissOfferDialog()
        XCTAssertNil(model.state.offerDialog)
        XCTAssertNil(model.state.offerError)
    }

    @MainActor
    func testNoOfferOnAFreeListing() async {
        let api = makeAPI(Self.listing(priceType: "FREE", price: nil))
        let model = makeModel(api)
        await model.load()
        XCTAssertTrue(model.state.canContact)
        XCTAssertFalse(model.state.canMakeOffer)

        model.openOfferDialog()
        XCTAssertNil(model.state.offerDialog)
        model.openContact()
        XCTAssertEqual(model.state.contactMessage, "")
    }
}
