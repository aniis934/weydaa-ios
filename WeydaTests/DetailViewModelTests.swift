import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage de DetailViewModelTest.kt et des règles d'affichage de ReportsTest.kt (Android) : fiche ouverte par son
/// slug, introuvable, panne, actions permises, signalement, numéro, vue comptée, compléments, caractéristiques.
/// Données fictives.
final class DetailViewModelTests: XCTestCase {
    // MARK: - Données

    /// Annonce « Clio 4 » du vendeur `u1` (Android : `AnnonceDto(id = "cm_real_id", slug = "clio-4-2019", …)`).
    static func clio(
        status: String = "ACTIVE",
        priceType: String = "NEGOTIABLE",
        hasPhone: Bool = true,
        sellerId: String = "u1"
    ) -> AnnonceDTO {
        AnnonceDTO(
            id: "cm_real_id",
            slug: "clio-4-2019",
            title: "Clio 4",
            description: String(repeating: "d", count: 30),
            price: 1_850_000,
            priceType: priceType,
            status: status,
            hasPhone: hasPhone,
            createdAt: "2026-09-01T10:00:00.000Z",
            attributes: ["make": "renault", "model": "clio-4", "year": 2019],
            category: CategoryRefDTO(
                id: "cat_voit",
                slug: "voitures",
                nameFr: "Voitures",
                parent: ParentRefDTO(slug: "vehicules")
            ),
            user: UserRefDTO(id: sellerId, name: "Karim B.")
        )
    }

    static func member(_ id: String = "u9") -> User {
        User(id: id, name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: true)
    }

    @MainActor
    private func makeModel(_ idOrSlug: String, api: FakeWeydaAPI, user: User? = nil) -> DetailViewModel {
        DetailViewModel(
            idOrSlug: idOrSlug,
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

    /// Fausse API d'une fiche qui se charge : le reste (similaires, avis, libellés) échoue en silence.
    @MainActor
    private func makeAPI() -> FakeWeydaAPI {
        let api = FakeWeydaAPI()
        api.onGetAnnonce = { idOrSlug in
            XCTAssertTrue(idOrSlug == "clio-4-2019" || idOrSlug == "cm_real_id")
            return Self.clio()
        }
        api.onIsFavorite = { _ in IsFavoriteDTO(isFavorite: false) }
        return api
    }

    // MARK: - DetailViewModelTest.kt

    @MainActor
    func testOpenedBySlugTheHeartFollowsAndTogglesTheRealId() async {
        let api = makeAPI()
        let sent = FakeWeydaAPI.Box<[String]>([])
        api.onAddFavorite = { body in
            sent.value.append(body.annonceId)
            return FavoriteDTO(annonceId: body.annonceId)
        }
        let model = makeModel("clio-4-2019", api: api, user: Self.member())
        await model.load()
        XCTAssertEqual(model.state.listing?.id, "cm_real_id")
        XCTAssertFalse(model.state.isFavorite)

        await model.toggleFavorite()
        // Le serveur reçoit l'id réel (le slug donnait 404), et le cœur se remplit.
        XCTAssertEqual(sent.value, ["cm_real_id"])
        XCTAssertTrue(model.state.isFavorite)
    }

    @MainActor
    func testNotFoundGivesADedicatedStateInsteadOfRetryingForever() async {
        let api = FakeWeydaAPI()
        api.onGetAnnonce = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
        let model = makeModel("disparue", api: api)
        await model.load()
        XCTAssertTrue(model.state.isError)
        XCTAssertTrue(model.state.isNotFound)
        XCTAssertFalse(model.state.isLoading)
        XCTAssertNil(model.state.listing)
    }

    @MainActor
    func testServerFailureKeepsItsCauseWithoutTheNotFoundState() async {
        let api = FakeWeydaAPI()
        api.onGetAnnonce = { _ in throw FakeWeydaAPI.apiError(500) }
        let model = makeModel("cm_real_id", api: api)
        await model.load()
        XCTAssertTrue(model.state.isError)
        XCTAssertFalse(model.state.isNotFound)
        XCTAssertEqual(model.state.errorMessage, L10n.errorServer)
    }

    // MARK: - ReportsTest.kt (règles d'affichage)

    func testReportIsOfferedOnSomeoneElsesListingOnly() {
        let listing = Self.clio().toDomain()
        XCTAssertFalse(DetailState(isLoading: false, listing: listing, userId: "u1").canReport)
        XCTAssertTrue(DetailState(isLoading: false, listing: listing, userId: "u9").canReport)
        // Visiteur : le menu est offert, l'écran renvoie vers la connexion.
        XCTAssertTrue(DetailState(isLoading: false, listing: listing).canReport)
        // Rien à signaler tant que l'annonce n'est pas chargée.
        XCTAssertFalse(DetailState(userId: "u9").canReport)
        // Une annonce vendue reste signalable, contrairement à « Contacter ».
        let sold = Self.clio(status: "SOLD").toDomain()
        XCTAssertTrue(DetailState(isLoading: false, listing: sold, userId: "u9").canReport)
        XCTAssertFalse(DetailState(isLoading: false, listing: sold, userId: "u9").canContact)
    }

    func testTheFiveReasonsHaveDistinctLabelsAndAUserReportDropsDuplicate() {
        let labels = ReportReason.allCases.map { $0.label }
        XCTAssertEqual(labels.count, 5)
        XCTAssertEqual(Set(labels).count, 5)
        XCTAssertEqual(ReportReason.choices(targetsUser: false), ReportReason.allCases)
        XCTAssertFalse(ReportReason.choices(targetsUser: true).contains(.duplicate))
        XCTAssertEqual(ReportReason.initial(targetsUser: false), .spam)
        XCTAssertEqual(ReportReason.initial(targetsUser: true), .fraud)
    }

    // MARK: - Actions permises (DetailUiState)

    func testContactOfferPhoneAndEditFollowTheSiteRules() {
        let listing = Self.clio().toDomain()
        let buyer = DetailState(isLoading: false, listing: listing, userId: "u9")
        XCTAssertTrue(buyer.canContact)
        XCTAssertTrue(buyer.canMakeOffer)
        XCTAssertTrue(buyer.canShowPhone)
        XCTAssertFalse(buyer.canEdit)
        XCTAssertTrue(buyer.hasActions)

        // Annonce gratuite : pas d'offre ; sans numéro : pas de bouton numéro.
        let free = DetailState(isLoading: false, listing: Self.clio(priceType: "FREE", hasPhone: false).toDomain(), userId: "u9")
        XCTAssertTrue(free.canContact)
        XCTAssertFalse(free.canMakeOffer)
        XCTAssertFalse(free.canShowPhone)

        // Propriétaire : ni contact ni numéro ni signalement, « Modifier » tant que l'annonce n'est pas vendue.
        let owner = DetailState(isLoading: false, listing: listing, userId: "u1")
        XCTAssertTrue(owner.isOwner)
        XCTAssertFalse(owner.canContact)
        XCTAssertFalse(owner.canShowPhone)
        XCTAssertTrue(owner.canEdit)
        let soldOwner = DetailState(isLoading: false, listing: Self.clio(status: "SOLD").toDomain(), userId: "u1")
        XCTAssertFalse(soldOwner.canEdit)
        XCTAssertFalse(soldOwner.hasActions)

        // Annonce vendue vue par un acheteur : aucune action en bas.
        let soldBuyer = DetailState(isLoading: false, listing: Self.clio(status: "SOLD").toDomain(), userId: "u9")
        XCTAssertFalse(soldBuyer.hasActions)
    }

    // MARK: - Signalement

    @MainActor
    func testReportSentOrRefusedClosesTheSheetButANetworkFailureKeepsIt() async {
        let api = makeAPI()
        let model = makeModel("cm_real_id", api: api, user: Self.member())
        await model.load()

        let sent = FakeWeydaAPI.Box<ReportRequestDTO?>(nil)
        api.onReport = { body in
            sent.value = body
            return ReportDTO(id: "rep1")
        }
        model.openReport()
        XCTAssertTrue(model.isReportPresented)
        await model.confirmReport(reason: .fraud, details: "  Le vendeur demande un acompte.  ")
        XCTAssertEqual(sent.value?.annonceId, "cm_real_id")
        XCTAssertEqual(sent.value?.reason, "FRAUD")
        XCTAssertEqual(sent.value?.details, "Le vendeur demande un acompte.")
        XCTAssertFalse(model.isReportPresented)
        XCTAssertEqual(model.state.notice, L10n.reportSent)
        model.noticeShown()
        XCTAssertNil(model.state.notice)

        // Déjà signalé (409) : verdict du serveur, la feuille se ferme avec le message.
        api.onReport = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"alreadyReported"}"#) }
        model.openReport()
        await model.confirmReport(reason: .spam, details: "")
        XCTAssertFalse(model.isReportPresented)
        XCTAssertEqual(model.state.notice, L10n.errorAlreadyReported)
        model.noticeShown()

        // Panne réseau : la feuille reste ouverte (précisions gardées), l'erreur s'affiche dedans.
        api.onReport = { _ in throw URLError(.notConnectedToInternet) }
        model.openReport()
        await model.confirmReport(reason: .other, details: "Précisions")
        XCTAssertTrue(model.isReportPresented)
        XCTAssertEqual(model.state.reportError, L10n.errorOffline)
        XCTAssertNil(model.state.notice)
        XCTAssertFalse(model.state.isReportBusy)
    }

    @MainActor
    func testTheOwnerCannotOpenTheReportSheet() async {
        let api = makeAPI()
        let model = makeModel("cm_real_id", api: api, user: Self.member("u1"))
        await model.load()
        model.openReport()
        XCTAssertFalse(model.isReportPresented)
    }

    // MARK: - Numéro du vendeur

    @MainActor
    func testThePhoneIsRevealedOnceThenAFailureBecomesANotice() async {
        let api = makeAPI()
        api.onGetContactPhone = { id in
            XCTAssertEqual(id, "cm_real_id")
            return ContactPhoneDTO(phone: "0555 00 00 00")
        }
        let model = makeModel("clio-4-2019", api: api, user: Self.member())
        await model.load()
        await model.revealPhone()
        XCTAssertEqual(model.state.revealedPhone, "0555 00 00 00")
        XCTAssertFalse(model.state.isRevealingPhone)
        // Déjà révélé : aucun nouvel appel (5 révélations par heure côté serveur).
        await model.revealPhone()
        XCTAssertEqual(api.count("getContactPhone"), 1)

        let other = makeModel("cm_real_id", api: api, user: Self.member())
        await other.load()
        api.onGetContactPhone = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"noPhoneNumber"}"#) }
        await other.revealPhone()
        XCTAssertNil(other.state.revealedPhone)
        XCTAssertEqual(other.state.notice, L10n.errorNoPhone)
    }

    func testTheCallAddressKeepsOnlyTheDialableNumber() {
        XCTAssertEqual(DetailLinks.callURL(for: "0555 00 00 00")?.absoluteString, "tel:0555000000")
        XCTAssertEqual(DetailLinks.callURL(for: "+213 555-00-00-00")?.absoluteString, "tel:+213555000000")
        // Une extension ou un texte saisis par le vendeur ne s'ajoutent pas au numéro.
        XCTAssertEqual(DetailLinks.callURL(for: "0555 00 00 00 #12")?.absoluteString, "tel:0555000000")
        XCTAssertEqual(DetailLinks.callURL(for: "0555 00 00 00 après 18 h")?.absoluteString, "tel:0555000000")
        XCTAssertNil(DetailLinks.callURL(for: "pas de numéro"))
    }

    // MARK: - Vue comptée, compléments

    @MainActor
    func testTheViewIsCountedOnceAndNeverForTheOwner() async {
        let api = makeAPI()
        let visitor = makeModel("cm_real_id", api: api)
        await visitor.load()
        await visitor.load()
        XCTAssertEqual(api.count("countView"), 1)

        let ownerAPI = makeAPI()
        let owner = makeModel("cm_real_id", api: ownerAPI, user: Self.member("u1"))
        await owner.load()
        XCTAssertEqual(ownerAPI.count("countView"), 0)
    }

    @MainActor
    func testSimilarReviewsAndAttributeLabelsArriveWithTheListing() async {
        let api = makeAPI()
        api.onGetAnnonces = { call in
            XCTAssertEqual(call.category, "voitures")
            XCTAssertEqual(call.sort, "newest")
            XCTAssertEqual(call.limit, 9)
            return AnnoncesPageDTO(annonces: [Self.clio(), AnnonceDTO(id: "a2", title: "Clio 5")], total: 2)
        }
        api.onGetReviews = { target, _, limit in
            XCTAssertEqual(target, "u1")
            XCTAssertEqual(limit, 3)
            return ReviewsDTO(
                reviews: [ReviewDTO(id: "r1", rating: 5, comment: "Vendeur sérieux", createdAt: "2026-09-01T10:00:00.000Z")],
                total: 1,
                ratingCount: 1,
                average: 5
            )
        }
        api.onGetAttributes = { slug, subcategory, locale, context in
            XCTAssertEqual(slug, "vehicules")
            XCTAssertEqual(subcategory, "voitures")
            XCTAssertEqual(locale, "fr")
            // Contexte = valeurs de l'annonce (libellé du modèle ← marque).
            XCTAssertEqual(context["ctx_make"], "renault")
            return AttributesResponseDTO(attributes: [
                AttributeDTO(key: "make", type: "select", options: ["renault"], label: "Marque", optionLabels: ["renault": "Renault"]),
            ])
        }
        let model = makeModel("cm_real_id", api: api)
        await model.load()
        XCTAssertEqual(model.state.similar.map { $0.id }, ["a2"])
        XCTAssertEqual(model.state.reviews?.reviews.first?.comment, "Vendeur sérieux")
        let make = model.state.attributeRows.first { $0.key == "make" }
        XCTAssertEqual(make?.label, "Marque")
        XCTAssertEqual(make?.value, "Renault")
    }

    @MainActor
    func testCompanionFailuresAreSilent() async {
        // Similaires, avis et libellés non configurés : la fiche s'affiche quand même, sections masquées.
        let api = makeAPI()
        let model = makeModel("cm_real_id", api: api)
        await model.load()
        XCTAssertFalse(model.state.isError)
        XCTAssertNotNil(model.state.listing)
        XCTAssertTrue(model.state.similar.isEmpty)
        XCTAssertNil(model.state.reviews)
        XCTAssertNil(model.state.attributeSet)
        // Libellés de repli tant que les définitions manquent.
        XCTAssertEqual(model.state.attributeRows.map { $0.key }, ["make", "model", "year"])
        XCTAssertEqual(model.state.attributeRows.first?.label, "Make")
    }

    // MARK: - Caractéristiques

    func testAttributeRowsFollowTheCategoryOrderWithReadableValues() {
        let set = AttributeSet(attributes: [
            AttributeDefinition(
                key: "make",
                label: "Marque",
                type: .select,
                requirement: .required,
                options: [AttributeOption(value: "renault", label: "Renault")]
            ),
            AttributeDefinition(key: "year", label: "Année", type: .number, requirement: .required),
            AttributeDefinition(key: "mileage", label: "Kilométrage", type: .number, requirement: .recommended, unitLabel: "km"),
            AttributeDefinition(key: "exchange_possible", label: "Échange possible", type: .boolean, requirement: .optional),
        ])
        let rows = DetailAttributeRow.rows(
            attributes: [
                "mileage": "145000",
                "make": "renault",
                "year": "2017",
                "exchange_possible": "true",
                "zz_extra": "x",
                "body_type": "suv",
                "empty": " ",
            ],
            set: set
        )
        XCTAssertEqual(rows.map { $0.key }, ["make", "year", "mileage", "exchange_possible", "body_type", "zz_extra"])
        XCTAssertEqual(rows[0].value, "Renault")
        // Une année sans unité reste telle quelle ; un nombre avec unité est groupé.
        XCTAssertEqual(rows[1].value, "2017")
        XCTAssertEqual(rows[2].value, Format.decimal(145_000) + " km")
        XCTAssertEqual(rows[3].value, L10n.attrYes)
        XCTAssertEqual(rows[4].label, "Body Type")
        XCTAssertEqual(rows[4].value, "suv")
    }

    func testTextLinesOfTheSheet() {
        var listing = Self.clio().toDomain()
        XCTAssertEqual(DetailText.reference(of: "cm_abcdefgh12345678"), Format.ltrIsolate("12345678"))
        XCTAssertTrue(DetailText.referenceLine(listing).hasSuffix(L10n.detailReference(Format.ltrIsolate("_REAL_ID"))))
        listing.views = 3
        XCTAssertTrue(DetailText.postedLine(listing).hasSuffix(L10n.detailViews(3)))
        let seller = Seller(id: "u1", name: "Karim B.", avatarUrl: nil, memberSince: nil, activeListings: 4)
        XCTAssertEqual(DetailText.sellerMeta(seller), L10n.sellerListings(4))
        XCTAssertNil(DetailText.sellerMeta(Seller(id: "u2", name: "N", avatarUrl: nil, memberSince: nil)))
    }

    func testTheShareLinkIsTheSitesSeoAddress() {
        let listing = Self.clio().toDomain()
        XCTAssertEqual(DetailLinks.webURL(for: listing, language: "ar")?.absoluteString, "https://weydaa.com/ar/voitures/clio-4-2019")
    }

    func testStatusBannerTextsMatchTheSite() {
        XCTAssertNil(DetailStatusContent(status: .active))
        XCTAssertEqual(DetailStatusContent(status: .sold)?.title, L10n.detailStatusSold)
        XCTAssertEqual(DetailStatusContent(status: .pending)?.isEditable, false)
        XCTAssertEqual(DetailStatusContent(status: .rejected)?.isEditable, true)
        XCTAssertEqual(DetailStatusContent(status: .expired)?.isEditable, true)
    }
}

#if DEBUG
/// Données simulées de la fiche et du profil (`MockFixtures/routes-detail.json` + `detail/`) lues par les VRAIS
/// repositories à travers `LiveWeydaAPI` et l'API simulée : JSON conformes aux DTO, routes les plus précises servies.
final class MockDetailFixturesTests: XCTestCase {
    private func makeAPI() throws -> LiveWeydaAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://weydaa.com/"))
        let client = APIClient(baseURL: base, session: URLSession(configuration: configuration))
        return LiveWeydaAPI(client: client, authClient: client)
    }

    @MainActor
    func testTheVehicleSheetBySlugTheSoldSheetAndTheMissingOne() async throws {
        let api = try makeAPI()
        let annonces = AnnonceRepository(api: api)
        let clio = try await annonces.detail(idOrSlug: "renault-clio-4-gt-line-2019-diesel-oran")
        XCTAssertEqual(clio.id, "mock-a2")
        XCTAssertEqual(clio.images.count, 8)
        XCTAssertEqual(clio.attributes.count, 10)
        XCTAssertEqual(clio.parentCategorySlug, "vehicules")
        XCTAssertEqual(clio.commune?.fr, "Bir El Djir")
        XCTAssertEqual(clio.seller?.name, "Amina K.")
        XCTAssertTrue(clio.seller?.emailVerified == true)
        XCTAssertTrue(clio.hasPhone)

        // Les autres voitures en ligne (accueil + page 2 de LISTINGS), plus récentes d'abord, sans la fiche ouverte.
        let similar = try await annonces.similar(to: clio)
        XCTAssertEqual(similar.map { $0.id }, ["mock-a10", "mock-a14", "mock-a25", "mock-a26", "mock-a27"])

        // Fiche vendue, hors des listes (identifiant hors de la série mock-aN des annonces en ligne).
        let sold = try await annonces.detail(idOrSlug: "mock-sold-1")
        XCTAssertEqual(sold.listingStatus, .sold)

        do {
            _ = try await annonces.detail(idOrSlug: "mock-gone")
            XCTFail("404 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
        }

        // Les 30 annonces en ligne de l'API simulée (accueil mock-a1…a24, recherche mock-a25…a30) ont leur fiche.
        for index in 1...30 {
            let listing = try await annonces.detail(idOrSlug: "mock-a\(index)")
            XCTAssertNotNil(listing.seller, "mock-a\(index)")
            XCTAssertNotNil(listing.commune, "mock-a\(index)")
        }
    }

    @MainActor
    func testProfilesShowcasesAndReviews() async throws {
        let api = try makeAPI()
        let sellers = SellerRepository(api: api)
        let karim = try await sellers.profile(id: "mock-u1")
        XCTAssertEqual(karim.name, "Karim B.")
        XCTAssertTrue(karim.isRecommended)
        XCTAssertTrue(karim.isFastResponder)
        XCTAssertEqual(karim.activeListings, 5)
        let showcase = try await sellers.listings(id: "mock-u1")
        XCTAssertEqual(showcase.items.count, 5)
        XCTAssertFalse(showcase.hasMore)
        XCTAssertTrue(showcase.items.first?.isFeatured == true)

        let reviews = ReviewsRepository(api: api)
        let onSheet = try await reviews.forSeller("mock-u1")
        XCTAssertEqual(onSheet.reviews.count, 3)
        let onProfile = try await reviews.forSeller("mock-u1", limit: SellerViewModel.reviewsShown)
        XCTAssertEqual(onProfile.reviews.count, 5)
        XCTAssertEqual(onProfile.ratingCount, 23)
        let none = try await reviews.forSeller("mock-u5")
        XCTAssertTrue(none.reviews.isEmpty)

        for index in 1...6 {
            let seller = try await sellers.profile(id: "mock-u\(index)")
            XCTAssertFalse(seller.name.isEmpty)
        }
    }
}
#endif
