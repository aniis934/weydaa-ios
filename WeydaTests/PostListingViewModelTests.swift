import Combine
import Foundation
import XCTest
@testable import Weyda

/// Banc d'essai de l'assistant — le `setUp` de PostListingViewModelTest.kt : fausse API (catalogue Véhicules › Voitures /
/// Motos + Services, Alger / Oran, profil d'Amina avec téléphone), session en mémoire, brouillon en mémoire, photos dans
/// un dossier temporaire, préparation d'image qui refuse les octets contenant « bad ». Données FICTIVES.
@MainActor
private final class PostFixture {
    let api: FakeWeydaAPI
    let session: SessionManager
    let auth: AuthRepository
    let users: UserRepository
    let drafts: InMemoryPostDraftStore
    let photoDirectory: URL
    let photos: PostPhotoStore
    /// Nombre d'envois de photo (`https://cdn/<n>.webp`).
    let uploadCount: FakeWeydaAPI.Box<Int>

    init(refreshCall: @escaping @Sendable (String) async throws -> TokenResponseDTO = { _ in throw URLError(.unsupportedURL) }) {
        let api = FakeWeydaAPI()
        let session = SessionManager(storage: InMemorySessionStorage(), refreshCall: refreshCall)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostListingTests-\(UUID().uuidString)", isDirectory: true)
        let count = FakeWeydaAPI.Box(0)
        self.api = api
        self.session = session
        self.auth = AuthRepository(api: api, session: session)
        self.users = UserRepository(api: api, session: session)
        self.drafts = InMemoryPostDraftStore()
        self.photoDirectory = directory
        self.photos = PostPhotoStore(directory: directory)
        self.uploadCount = count

        api.onMe = { MeDTO(id: "user_1", name: "Amina", email: "amina@example.com", phone: "0550123456") }
        api.onUpload = { _ in
            count.value += 1
            return PostFixture.uploaded(count.value)
        }
        api.onGetCategories = { PostFixture.categories() }
        api.onGetWilayas = { () -> [WilayaDTO] in
            [WilayaDTO(id: 16, nameFr: "Alger"), WilayaDTO(id: 31, nameFr: "Oran")]
        }
        api.onGetCommunes = { (id: Int) -> [CommuneDTO] in
            [CommuneDTO(id: id * 100 + 1, nameFr: "Commune \(id)", wilayaId: id)]
        }
        api.onGetAttributes = { slug, subcategory, _, context in
            PostFixture.catalogAttributes(slug, subcategory, context)
        }
    }

    func vm(
        store: (any PostDraftStore)? = nil,
        editingId: String? = nil,
        reviewPrompter: ReviewPrompter = ReviewPrompter(isEnabled: false)
    ) -> PostListingViewModel {
        PostListingViewModel(
            editingId: editingId,
            drafts: store ?? drafts,
            photoStore: photos,
            annonces: AnnonceRepository(api: api),
            categories: CategoryRepository(api: api),
            attributes: AttributeRepository(api: api),
            geo: GeoRepository(api: api),
            auth: auth,
            users: users,
            uploads: UploadRepository(api: api, prepare: { data in try await PostFixture.prepare(data) }),
            userUpdates: session.$user.eraseToAnyPublisher(),
            locale: { "fr" },
            reviewPrompter: reviewPrompter
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    /// Android : `ImagePreparer { uri -> if (uri.contains("bad")) throw IOException(...) else ... }`.
    nonisolated static func prepare(_ data: Data) async throws -> Data {
        if String(decoding: data, as: UTF8.self).contains("bad") {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    nonisolated static func uploaded(_ n: Int) -> UploadResponseDTO {
        UploadResponseDTO(url: "https://cdn/\(n).webp", thumbnailUrl: "https://cdn/\(n)_thumb.webp", publicId: "annonces/\(n).webp")
    }

    nonisolated static func categories() -> [CategoryDTO] {
        [
            CategoryDTO(
                id: "cat_veh",
                slug: "vehicules",
                nameFr: "Véhicules",
                children: [
                    CategoryDTO(id: "cat_voit", slug: "voitures", nameFr: "Voitures"),
                    CategoryDTO(id: "cat_moto", slug: "motos", nameFr: "Motos"),
                ]
            ),
            CategoryDTO(id: "cat_srv", slug: "services", nameFr: "Services"),
        ]
    }

    /// Voitures : marque (requise), modèle (dépendant de la marque : options seulement avec `ctx_make=renault`),
    /// année (requise, 1970–2027), couleur (texte libre) ; toute autre catégorie : aucun attribut.
    nonisolated static func catalogAttributes(_ slug: String, _ subcategory: String?, _ context: [String: String]) -> AttributesResponseDTO {
        guard slug == "vehicules", subcategory == "voitures" else { return AttributesResponseDTO() }
        let models: [String] = context["ctx_make"] == "renault" ? ["clio", "megane"] : []
        return AttributesResponseDTO(attributes: [
            AttributeDTO(key: "make", type: "select", requirement: "required", options: ["renault", "peugeot"]),
            AttributeDTO(key: "model", type: "select", requirement: "recommended", options: models, dependsOn: "make"),
            AttributeDTO(key: "year", type: "number", requirement: "required", min: 1970, max: 2027),
            AttributeDTO(key: "color", type: "text", requirement: "optional"),
        ])
    }
}

/// Portage de PostListingViewModelTest.kt (Android), cas par cas (mêmes noms, mêmes scénarios) : `advanceUntilIdle()`
/// → `await vm.waitForIdle()`, URI `content://p/<n>` → octets de même texte (référence = SHA-256). En plus (iOS) :
/// doublon par SHA-256, fichiers purgés / effacés, photo retirée pendant son envoi, brouillon d'édition en mémoire,
/// appareil photo indisponible, e-mail vérifié suivi en direct.
final class PostListingViewModelTests: XCTestCase {
    private static func photo(_ name: String) -> Data {
        Data("content://p/\(name)".utf8)
    }

    private static func ref(_ name: String) -> String {
        PostPhotoStore.ref(for: photo(name))
    }

    /// Parcours complet Véhicules › Voitures jusqu'au récapitulatif (Android : `filledVm`).
    @MainActor
    private func filledVm(
        _ fixture: PostFixture,
        reviewPrompter: ReviewPrompter = ReviewPrompter(isEnabled: false)
    ) async -> PostListingViewModel {
        let vm = fixture.vm(reviewPrompter: reviewPrompter)
        await vm.waitForIdle()
        vm.onSelectParent("cat_veh")
        vm.onSelectSubcategory("cat_voit")
        await vm.waitForIdle()
        vm.next()
        vm.onAttributeChange("make", "renault")
        await vm.waitForIdle()
        vm.onAttributeChange("model", "clio")
        vm.onAttributeChange("year", "2018")
        vm.onAttributeChange("color", "rouge")
        vm.next()
        vm.onTitleChange("Renault Clio 4 2018")
        vm.onDescriptionChange("Très bon état général, entretien à jour, jamais accidentée.")
        vm.onPriceTypeChange(.negotiable)
        vm.onPriceChange("1950000")
        vm.next()
        vm.onPhotosPicked([Self.photo("1"), Self.photo("2")])
        await vm.waitForIdle()
        vm.next()
        vm.onWilayaChange(16)
        await vm.waitForIdle()
        vm.onCommuneChange(1601)
        vm.onShowPhoneChange(true)
        vm.next()
        XCTAssertEqual(vm.state.step, .review)
        return vm
    }

    // MARK: - Portage d'Android

    @MainActor
    func testCategorieSuivantRefuseSansSelectionSousCategorieObligatoireAttributsCharges() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.categories.count, 2)
        XCTAssertEqual(vm.state.steps, [.category, .details, .photos, .location, .review])

        vm.next()
        XCTAssertEqual(vm.state.categoryError, L10n.validationCategoryRequired)
        XCTAssertEqual(vm.state.step, .category)

        vm.onSelectParent("cat_veh")
        await vm.waitForIdle()
        XCTAssertTrue(vm.state.needsSubcategory)
        XCTAssertFalse(vm.state.isCategoryComplete)
        XCTAssertNil(vm.state.attributeSet)
        vm.next()
        XCTAssertEqual(vm.state.categoryError, L10n.validationCategoryRequired)
        XCTAssertEqual(vm.state.step, .category)

        vm.onSelectSubcategory("cat_voit")
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.categoryId, "cat_voit")
        XCTAssertTrue(vm.state.hasAttributes)
        XCTAssertTrue(vm.state.steps.contains(.attributes))
        vm.next()
        XCTAssertEqual(vm.state.step, .attributes)
    }

    @MainActor
    func testCategorieSansEnfantIdRacinePasDEtapeAttributs() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_srv")
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.categoryId, "cat_srv")
        XCTAssertFalse(vm.state.hasAttributes)
        vm.next()
        XCTAssertEqual(vm.state.step, .details)
        XCTAssertEqual(vm.state.stepIndex, 1)
    }

    @MainActor
    func testAttributsRequisSelectDependantRechargeAvecCtxChangementDeParentEffaceLEnfant() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_veh")
        vm.onSelectSubcategory("cat_voit")
        await vm.waitForIdle()
        vm.next()
        XCTAssertEqual(vm.state.step, .attributes)

        vm.next()
        XCTAssertEqual(vm.state.attributeErrors, ["make": L10n.validationAttrRequired, "year": L10n.validationAttrRequired])

        let model = try XCTUnwrap(vm.state.attributeSet?.attribute("model"))
        XCTAssertFalse(vm.state.isAttributeEnabled(model))
        vm.onAttributeChange("make", "renault")
        await vm.waitForIdle()
        XCTAssertTrue(vm.state.isAttributeEnabled(model))
        XCTAssertEqual(vm.state.optionsFor(model).map { $0.value }, ["clio", "megane"])
        XCTAssertNil(vm.state.attributeErrors["make"])

        vm.onAttributeChange("model", "clio")
        vm.onAttributeChange("year", "1950")
        vm.next()
        XCTAssertEqual(vm.state.attributeErrors["year"], L10n.validationAttrMin)

        vm.onAttributeChange("make", "peugeot")
        await vm.waitForIdle()
        XCTAssertNil(vm.state.attributeValues["model"])
        XCTAssertTrue(vm.state.optionsFor(model).isEmpty)

        vm.onAttributeChange("year", "2018")
        vm.next()
        XCTAssertTrue(vm.state.attributeErrors.isEmpty)
        XCTAssertEqual(vm.state.step, .details)
    }

    @MainActor
    func testInfosEtPrixValidationGratuitEffaceLePrixChiffresSeulement() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_srv")
        await vm.waitForIdle()
        vm.next()
        XCTAssertEqual(vm.state.step, .details)

        vm.onTitleChange("Abc")
        vm.onDescriptionChange("Trop court")
        vm.next()
        XCTAssertEqual(vm.state.titleError, L10n.validationTitleMin)
        XCTAssertEqual(vm.state.descriptionError, L10n.validationDescriptionMin)
        XCTAssertEqual(vm.state.step, .details)

        vm.onTitleChange("Cours de maths à domicile")
        vm.onDescriptionChange("Professeur expérimenté, tous niveaux, déplacement dans tout Alger.")
        vm.onPriceChange("1 500 DA")
        XCTAssertEqual(vm.state.price, "1500")
        vm.onPriceTypeChange(.free)
        XCTAssertEqual(vm.state.price, "")
        vm.onPriceTypeChange(.negotiable)
        vm.onPriceChange("2000")
        vm.next()
        XCTAssertEqual(vm.state.step, .photos)
        vm.next()
        XCTAssertEqual(vm.state.step, .location)
        vm.back()
        XCTAssertEqual(vm.state.step, .photos)
    }

    @MainActor
    func testLocalisationCommunesChargeesParWilayaEtEffaceesAuChangement() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.wilayas.count, 2)
        // Téléphone relu depuis /users/me (absent de la réponse token) → bascule « afficher mon numéro » disponible.
        XCTAssertEqual(vm.state.userPhone, "0550123456")
        vm.onShowPhoneChange(true)
        XCTAssertTrue(vm.state.showPhone)
        vm.onWilayaChange(16)
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.communes.count, 1)
        XCTAssertEqual(vm.state.communes.first?.id, 1601)
        vm.onCommuneChange(1601)
        XCTAssertEqual(vm.state.selectedCommune?.name.resolve("fr"), "Commune 16")

        vm.onWilayaChange(31)
        XCTAssertNil(vm.state.communeId)
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.communes.count, 1)
        XCTAssertEqual(vm.state.communes.first?.id, 3101)

        vm.onWilayaChange(nil)
        XCTAssertTrue(vm.state.communes.isEmpty)
        XCTAssertNil(vm.state.selectedWilaya)
    }

    @MainActor
    func testBrouillonRestaureLesChampsLEtapeLesAttributsEtLesOptionsDependantes() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let first = fixture.vm()
        await first.waitForIdle()
        first.onSelectParent("cat_veh")
        first.onSelectSubcategory("cat_voit")
        await first.waitForIdle()
        first.next()
        first.onAttributeChange("make", "renault")
        await first.waitForIdle()
        first.onAttributeChange("model", "clio")
        first.onAttributeChange("year", "2018")
        first.next()
        first.onTitleChange("Renault Clio 4 2018")
        first.onDescriptionChange("Très bon état général, entretien à jour, jamais accidentée.")
        first.onPriceChange("1950000")
        first.onWilayaChange(16)
        await first.waitForIdle()
        first.onCommuneChange(1601)

        let second = fixture.vm()
        await second.waitForIdle()
        let s = second.state
        XCTAssertEqual(s.step, .details)
        XCTAssertEqual(s.categoryId, "cat_voit")
        XCTAssertEqual(s.attributeValues, ["make": "renault", "model": "clio", "year": "2018"])
        XCTAssertTrue(s.hasAttributes)
        let model = try XCTUnwrap(s.attributeSet?.attribute("model"))
        XCTAssertEqual(s.optionsFor(model).map { $0.value }, ["clio", "megane"])
        XCTAssertEqual(s.title, "Renault Clio 4 2018")
        XCTAssertEqual(s.price, "1950000")
        XCTAssertEqual(s.wilayaId, 16)
        XCTAssertEqual(s.communeId, 1601)
        XCTAssertEqual(s.selectedCommune?.id, 1601)

        second.clearDraft()
        XCTAssertNil(fixture.drafts.read())
        XCTAssertEqual(second.state.step, .category)
        XCTAssertEqual(second.state.categories.count, 2)
    }

    @MainActor
    func testPhotosLimite5UploadsSequentielsRetirerPrincipaleEchecReessayerSuivantBloque() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.maxPhotos, 5)
        vm.goTo(.photos)

        // État pendant le premier envoi (Android : vérifié juste après le choix, avant `advanceUntilIdle`).
        let duringFirstUpload = FakeWeydaAPI.Box<[Bool]>([])
        let count = fixture.uploadCount
        fixture.api.onUpload = { [vm] _ in
            if duringFirstUpload.value.isEmpty {
                duringFirstUpload.value = [vm.state.isUploading, vm.state.canGoNext]
            }
            count.value += 1
            return PostFixture.uploaded(count.value)
        }
        await vm.onPhotosPicked((0..<6).map { Self.photo("\($0)") })?.value
        XCTAssertEqual(vm.state.photos.count, 5)
        XCTAssertEqual(vm.state.photosNotice, L10n.postPhotosLimit(5))
        XCTAssertEqual(vm.state.photosBanner?.kind, .info)
        await vm.waitForIdle()
        XCTAssertEqual(duringFirstUpload.value, [true, false])
        XCTAssertTrue(vm.state.photos.allSatisfy { $0.status == .done })
        XCTAssertEqual(fixture.uploadCount.value, 5)
        XCTAssertEqual(vm.state.remainingPhotoSlots, 0)
        XCTAssertEqual(vm.state.photos[0].remoteURL?.absoluteString, "https://cdn/1_thumb.webp")
        XCTAssertTrue(vm.state.canGoNext)

        vm.onRemovePhoto(at: 0)
        XCTAssertEqual(vm.state.photos.count, 4)
        XCTAssertNil(vm.state.photosNotice)
        vm.onMakeMainPhoto(at: 2)
        XCTAssertEqual(vm.state.photos[0].localRef, Self.ref("3"))
        XCTAssertEqual(vm.state.photos.map { $0.localRef }, ["3", "1", "2", "4"].map { Self.ref($0) })

        fixture.api.onUpload = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"fileTooLarge"}"#) }
        vm.onPhotosPicked([Self.photo("big")])
        await vm.waitForIdle()
        let failed = vm.state.photos.last
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertEqual(failed?.errorMessage, L10n.errorUploadTooLarge)
        vm.next()
        XCTAssertEqual(vm.state.step, .photos)
        XCTAssertEqual(vm.state.errorMessage, L10n.postPhotosFailedHint)

        fixture.api.onUpload = { _ in
            count.value += 1
            return UploadResponseDTO(url: "https://cdn/ok.webp", publicId: "annonces/ok.webp")
        }
        vm.onRetryPhoto(at: 4)
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.photos.last?.status, .done)
        XCTAssertEqual(vm.state.photos.last?.remoteURL?.absoluteString, "https://cdn/ok.webp")
        XCTAssertEqual(vm.state.uploadedImages.count, 5)
        vm.next()
        XCTAssertEqual(vm.state.step, .location)
    }

    @MainActor
    func testPhotosImageIllisibleLimite8PourUnVendeurRecommandeBrouillonReprendLesEnvois() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onMe = { MeDTO(id: "user_1", email: "amina@example.com", isRecommended: true) }
        let vm = fixture.vm()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.maxPhotos, 8)
        XCTAssertNil(vm.state.userPhone)

        vm.onPhotosPicked([Self.photo("bad"), Self.photo("1")])
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.photos[0].status, .failed)
        XCTAssertEqual(vm.state.photos[0].errorMessage, L10n.errorPhotoRead)
        XCTAssertEqual(vm.state.photos[1].status, .done)

        // Brouillon : la photo envoyée est restaurée telle quelle, celle en échec (sans envoi) repart en file.
        fixture.api.onUpload = { _ in UploadResponseDTO(url: "https://cdn/late.webp", publicId: "annonces/late.webp") }
        let store = InMemoryPostDraftStore(fixture.drafts.read())
        let second = fixture.vm(store: store)
        XCTAssertEqual(second.state.photos[0].status, .uploading)
        XCTAssertEqual(second.state.photos[1].status, .done)
        await second.waitForIdle()
        XCTAssertEqual(second.state.photos[0].status, .failed) // toujours illisible
        XCTAssertEqual(second.state.photos[1].upload?.url, "https://cdn/1.webp")
    }

    @MainActor
    func testSoumissionCorpsPostTypeResultatBrouillonEfface() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = await filledVm(fixture)
        let received = FakeWeydaAPI.Box<CreateAnnonceRequestDTO?>(nil)
        fixture.api.onCreateAnnonce = { body in
            received.value = body
            return AnnonceDTO(id: "a1", title: body.title, status: "ACTIVE", aiModeration: AiModerationDTO(decision: "APPROVE"))
        }
        vm.next()
        XCTAssertTrue(vm.state.isSubmitting)
        XCTAssertFalse(vm.state.canGoNext)
        await vm.waitForIdle()
        XCTAssertFalse(vm.state.isSubmitting)
        XCTAssertEqual(vm.state.result?.id, "a1")
        XCTAssertEqual(vm.state.result?.status, "ACTIVE")
        XCTAssertNil(fixture.drafts.read())
        XCTAssertFalse(vm.asksForReview, "demande de note inerte par défaut")

        let body = try XCTUnwrap(received.value)
        XCTAssertEqual(body.title, "Renault Clio 4 2018")
        XCTAssertEqual(body.price, 1_950_000)
        XCTAssertEqual(body.priceType, "NEGOTIABLE")
        XCTAssertEqual(body.categoryId, "cat_voit")
        XCTAssertEqual(body.subcategorySlug, "voitures")
        XCTAssertEqual(body.wilayaId, 16)
        XCTAssertEqual(body.communeId, 1601)
        XCTAssertEqual(body.phone, "0550123456")
        XCTAssertEqual(body.images.map { $0.url }, ["https://cdn/1.webp", "https://cdn/2.webp"])
        XCTAssertEqual(body.images.first?.publicId, "annonces/1.webp")
        let attributes = try XCTUnwrap(body.attributes)
        XCTAssertEqual(attributes["make"], .string("renault"))
        XCTAssertEqual(attributes["year"], .number(2018))
        XCTAssertEqual(attributes["color"]?.stringValue, "rouge")

        vm.clearDraft()
        XCTAssertNil(vm.state.result)
        XCTAssertEqual(vm.state.step, .category)
    }

    /// Publication = moment positif (2e moment : la note est demandée) ; le compteur part d'un moment déjà vécu.
    @MainActor
    func testPublicationDemandeLaNoteAuDeuxiemeMomentPositif() async throws {
        let suiteName = "PostReview-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(1, forKey: ReviewPrompter.momentsKey)
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = await filledVm(fixture, reviewPrompter: ReviewPrompter(defaults: defaults, version: "1.0", isEnabled: true))
        XCTAssertEqual(vm.state.step, .review)
        fixture.api.onCreateAnnonce = { body in AnnonceDTO(id: "a1", title: body.title, status: "PENDING") }
        vm.next()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.result?.id, "a1")
        XCTAssertTrue(vm.asksForReview)
    }

    @MainActor
    func testSoumissionGratuitSansPrixNiTelephoneMasqueAttributsVidesOmis() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_srv")
        await vm.waitForIdle()
        vm.next()
        vm.onTitleChange("Cours de maths")
        vm.onDescriptionChange("Professeur expérimenté, tous niveaux, à domicile.")
        vm.onPriceTypeChange(.free)
        vm.next()
        vm.next()
        vm.next()
        let received = FakeWeydaAPI.Box<CreateAnnonceRequestDTO?>(nil)
        fixture.api.onCreateAnnonce = { body in
            received.value = body
            return AnnonceDTO(id: "a2", title: body.title, status: "PENDING")
        }
        vm.submit()
        await vm.waitForIdle()
        let body = try XCTUnwrap(received.value)
        XCTAssertNil(body.price)
        XCTAssertEqual(body.priceType, "FREE")
        XCTAssertNil(body.phone)
        XCTAssertNil(body.subcategorySlug)
        XCTAssertNil(body.attributes)
        XCTAssertTrue(body.images.isEmpty)
        XCTAssertEqual(vm.state.result?.status, "PENDING")
    }

    @MainActor
    func testSoumissionErreursServeurRenvoientSurLEtapeFautive() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = await filledVm(fixture)
        fixture.api.onCreateAnnonce = { _ in
            throw FakeWeydaAPI.apiError(400, #"{"error":"invalidAttributes","attributeErrors":{"year":"above_max","make":"invalid_option"}}"#)
        }
        vm.next()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.step, .attributes)
        XCTAssertEqual(vm.state.attributeErrors, ["year": L10n.validationAttrMax, "make": L10n.validationAttrOption])
        XCTAssertEqual(vm.state.errorMessage, L10n.errorInvalidAttributes)
        XCTAssertNil(vm.state.result)

        vm.goTo(.review)
        fixture.api.onCreateAnnonce = { _ in
            throw FakeWeydaAPI.apiError(400, #"{"error":"invalidData","details":{"fieldErrors":{"title":["validation.titleMax100"]}}}"#)
        }
        vm.submit()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.step, .details)
        XCTAssertEqual(vm.state.titleError, L10n.validationTitleMax)

        vm.goTo(.review)
        fixture.api.onCreateAnnonce = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"maxImagesExceeded","maxImages":5}"#) }
        vm.submit()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.step, .photos)
        XCTAssertEqual(vm.state.errorMessage, L10n.errorMaxImages)

        vm.goTo(.review)
        fixture.api.onCreateAnnonce = { _ in throw FakeWeydaAPI.apiError(429, #"{"error":"rateLimitError"}"#) }
        vm.submit()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.step, .review)
        XCTAssertEqual(vm.state.errorMessage, L10n.errorPostRateLimited)

        fixture.api.onCreateAnnonce = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"emailNotVerified"}"#) }
        vm.submit()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.errorMessage, L10n.errorEmailNotVerified)
        XCTAssertFalse(vm.state.isSubmitting)
    }

    @MainActor
    func testEditionPreRemplissageDepuisLAnnonceOptionsDependantesPutCompletResultat() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onGetAnnonce = { id in
            XCTAssertEqual(id, "a9")
            return AnnonceDTO(
                id: "a9",
                title: "Clio 4 à vendre",
                description: "Très bon état général, entretien à jour, jamais accidentée.",
                price: 1_900_000,
                priceType: "NEGOTIABLE",
                status: "ACTIVE",
                phone: "0550123456",
                wilayaId: 16,
                communeId: 1601,
                attributes: .object(["make": .string("renault"), "model": .string("clio"), "year": .number(2018)]),
                images: [
                    ImageDTO(url: "https://cdn/old2.webp", publicId: "annonces/old2.webp", order: 1),
                    ImageDTO(url: "https://cdn/old1.webp", publicId: "annonces/old1.webp", order: 0),
                ],
                category: CategoryRefDTO(id: "cat_voit", slug: "voitures", nameFr: "Voitures", parent: ParentRefDTO(slug: "vehicules"))
            )
        }
        let vm = fixture.vm(editingId: "a9")
        XCTAssertTrue(vm.state.isEditing)
        XCTAssertTrue(vm.state.editLoading)
        await vm.waitForIdle()
        let s = vm.state
        XCTAssertFalse(s.editLoading)
        XCTAssertEqual(s.step, .review)
        XCTAssertEqual(s.parentCategoryId, "cat_veh")
        XCTAssertEqual(s.subcategoryId, "cat_voit")
        XCTAssertEqual(s.attributeValues, ["make": "renault", "model": "clio", "year": "2018"])
        let model = try XCTUnwrap(s.attributeSet?.attribute("model"))
        XCTAssertEqual(s.optionsFor(model).map { $0.value }, ["clio", "megane"])
        XCTAssertEqual(s.price, "1900000")
        XCTAssertEqual(s.priceType, .negotiable)
        XCTAssertEqual(s.wilayaId, 16)
        XCTAssertEqual(s.communeId, 1601)
        XCTAssertEqual(s.communes.count, 1)
        XCTAssertTrue(s.showPhone)
        XCTAssertEqual(s.photos.map { $0.localRef }, ["https://cdn/old1.webp", "https://cdn/old2.webp"])
        XCTAssertTrue(s.photos.allSatisfy { $0.status == .done })
        XCTAssertTrue(s.canGoNext)

        vm.goTo(.photos)
        vm.onRemovePhoto(at: 0)
        vm.onPhotosPicked([Self.photo("new")])
        await vm.waitForIdle()
        vm.goTo(.review)
        vm.onShowPhoneChange(false)
        let sent = FakeWeydaAPI.Box<JSONValue?>(nil)
        fixture.api.onEditAnnonce = { id, body in
            XCTAssertEqual(id, "a9")
            sent.value = body
            return AnnonceDTO(id: id, title: body["title"]?.stringValue ?? "", status: "PENDING")
        }
        vm.next()
        await vm.waitForIdle()
        let body = try XCTUnwrap(sent.value)
        XCTAssertNil(body["status"])
        XCTAssertEqual(body["title"], .string("Clio 4 à vendre"))
        XCTAssertEqual(
            body["images"]?.arrayValue?.compactMap { $0["publicId"]?.stringValue },
            ["annonces/old2.webp", "annonces/1.webp"]
        )
        XCTAssertEqual(body["phone"], .string(""))
        XCTAssertEqual(body["attributes"]?["year"], .number(2018))
        XCTAssertEqual(vm.state.result?.status, "PENDING")
        XCTAssertTrue(vm.state.isEditing)
    }

    @MainActor
    func testEditionAnnonceIntrouvableErreurAvecNouvelleTentative() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onGetAnnonce = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
        let vm = fixture.vm(editingId: "zz")
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.editError, L10n.errorNotFound)
        fixture.api.onGetAnnonce = { _ in
            AnnonceDTO(
                id: "zz",
                title: "Titre valide",
                description: String(repeating: "d", count: 30),
                category: CategoryRefDTO(slug: "services", nameFr: "Services")
            )
        }
        await vm.loadEditing()?.value
        await vm.waitForIdle()
        XCTAssertNil(vm.state.editError)
        XCTAssertEqual(vm.state.parentCategoryId, "cat_srv")
        XCTAssertEqual(vm.state.title, "Titre valide")
    }

    @MainActor
    func testBrouillonEtapeAttributsRestaureeSurUneCategorieSansAttributsBasculeSurDetails() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let store = InMemoryPostDraftStore(#"{"parentCategoryId":"cat_srv","step":"ATTRIBUTES","title":"x"}"#)
        let vm = fixture.vm(store: store)
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.step, .details)
        XCTAssertEqual(vm.state.title, "x")
    }

    @MainActor
    func testAttributsIllisiblesSuivantRelanceLeChargementRienNePartSansEux() async {
        // Un échec pris pour « catégorie sans attributs » faisait disparaître l'étape : l'annonce d'un véhicule
        // partait sans marque ni année (le serveur ne valide les attributs que s'ils sont présents).
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let offline = FakeWeydaAPI.Box(true)
        fixture.api.onGetAttributes = { slug, subcategory, _, context in
            if offline.value { throw URLError(.notConnectedToInternet) }
            return PostFixture.catalogAttributes(slug, subcategory, context)
        }
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_veh")
        vm.onSelectSubcategory("cat_voit")
        await vm.waitForIdle()
        XCTAssertTrue(vm.state.attributesError)
        XCTAssertNil(vm.state.attributeSet)
        XCTAssertEqual(vm.state.errorMessage, L10n.errorOffline)

        vm.next()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.step, .category)

        offline.value = false
        vm.next() // relance, n'avance pas encore
        await vm.waitForIdle()
        XCTAssertFalse(vm.state.attributesError)
        XCTAssertNil(vm.state.errorMessage)
        XCTAssertTrue(vm.state.hasAttributes)
        XCTAssertEqual(vm.state.step, .category)
        vm.next()
        XCTAssertEqual(vm.state.step, .attributes)
    }

    @MainActor
    func testChangementDeCompteNiLeBrouillonNiLeTelephoneDuPrecedentNePassentAuSuivant() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: true) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_srv")
        await vm.waitForIdle()
        vm.onTitleChange("Brouillon privé de A")
        vm.onShowPhoneChange(true)
        XCTAssertEqual(vm.state.contactPhone, "0550123456")
        XCTAssertTrue(fixture.drafts.read()?.contains("Brouillon privé de A") ?? false)

        // Le ViewModel de l'onglet peut survivre à la déconnexion.
        fixture.auth.logout()
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.title, "")
        XCTAssertNil(vm.state.parentCategoryId)
        XCTAssertNil(vm.state.contactPhone)
        XCTAssertFalse(vm.state.showPhone)
        XCTAssertNil(fixture.drafts.read())
    }

    @MainActor
    func testEditionLeNumeroDeContactDeLAnnonceNEstPasRemplaceParCeluiDuProfil() async {
        // Un fixe est accepté sur une annonce, pas sur un profil : les deux numéros peuvent différer.
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onGetAnnonce = { id in
            AnnonceDTO(
                id: id,
                title: "Local commercial à louer",
                description: String(repeating: "d", count: 30),
                price: 90_000,
                priceType: "FIXED",
                status: "ACTIVE",
                phone: "021123456",
                category: CategoryRefDTO(id: "cat_srv", slug: "services", nameFr: "Services")
            )
        }
        let vm = fixture.vm(editingId: "a7")
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.userPhone, "0550123456")
        XCTAssertEqual(vm.state.contactPhone, "021123456")
        XCTAssertTrue(vm.state.showPhone)

        let sentPhone = FakeWeydaAPI.Box<String?>(nil)
        fixture.api.onEditAnnonce = { id, body in
            sentPhone.value = body["phone"]?.stringValue
            return AnnonceDTO(id: id, title: "Local commercial à louer", status: "ACTIVE")
        }
        vm.next()
        await vm.waitForIdle()
        XCTAssertEqual(sentPhone.value, "021123456")
    }

    @MainActor
    func testSessionExpireeLeBrouillonResteASonAuteurUnAutreCompteNeLeVoitJamais() async throws {
        let fixture = PostFixture(refreshCall: { _ in
            throw FakeWeydaAPI.apiError(401, #"{"error":"invalidRefreshToken"}"#)
        })
        defer { fixture.cleanUp() }
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: true) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onSelectParent("cat_srv")
        await vm.waitForIdle()
        vm.onTitleChange("Brouillon de A")

        // Refresh refusé pendant un envoi : la session tombe sans action de l'utilisateur.
        _ = await fixture.session.refreshIfNeeded(failedAccessToken: "access-1")
        await vm.waitForIdle()
        XCTAssertNil(fixture.auth.user)
        XCTAssertEqual(vm.state.title, "Brouillon de A")
        XCTAssertTrue(fixture.drafts.read()?.contains("Brouillon de A") ?? false)

        // Le même compte se reconnecte : il retrouve son brouillon.
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.title, "Brouillon de A")

        // La session retombe, puis un AUTRE compte se connecte : le brouillon de A disparaît.
        _ = await fixture.session.refreshIfNeeded(failedAccessToken: "access-1")
        await vm.waitForIdle()
        fixture.api.onLogin = { _ in
            TokenResponseDTO(
                accessToken: "access-2",
                refreshToken: "refresh-2",
                expiresIn: 3600,
                refreshExpiresIn: 2_592_000,
                user: AuthUserDTO(id: "user_2", name: "Bilal", email: "b@example.com", avatar: nil, role: "USER", emailVerified: true)
            )
        }
        _ = try await fixture.auth.login(email: "b@example.com", password: "Secret123")
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.title, "")
        XCTAssertNil(fixture.drafts.read())
    }

    @MainActor
    func testBrouillonDUnAutreCompteJamaisRestaureEfface() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: true) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        let store = InMemoryPostDraftStore(#"{"ownerId":"user_9","title":"Annonce de B","step":"DETAILS"}"#)
        let vm = fixture.vm(store: store)
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.title, "")
        XCTAssertEqual(vm.state.step, .category)
        XCTAssertNil(store.read())
    }

    @MainActor
    func testEditionModificationsSuiviesBrouillonReprisApresLaMortDuProcessus() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onGetAnnonce = { id in
            AnnonceDTO(
                id: id,
                title: "Local commercial à louer",
                description: String(repeating: "d", count: 30),
                price: 90_000,
                priceType: "FIXED",
                status: "ACTIVE",
                phone: "021123456",
                category: CategoryRefDTO(id: "cat_srv", slug: "services", nameFr: "Services")
            )
        }
        let store = InMemoryPostDraftStore()
        let vm = fixture.vm(store: store, editingId: "a7")
        await vm.waitForIdle()
        XCTAssertFalse(vm.state.isDirty)
        vm.onTitleChange("Local commercial à louer, centre-ville")
        XCTAssertTrue(vm.state.isDirty)

        // Recréation avec le brouillon d'édition : repris tel quel, l'annonce n'est pas relue, le numéro propre à
        // l'annonce est conservé (sur iOS ce brouillon vit en mémoire ; la règle reste celle d'Android).
        let reloaded = FakeWeydaAPI.Box(false)
        fixture.api.onGetAnnonce = { id in
            reloaded.value = true
            return AnnonceDTO(id: id, title: "x", description: "y")
        }
        let restored = fixture.vm(store: InMemoryPostDraftStore(store.read()), editingId: "a7")
        await restored.waitForIdle()
        XCTAssertFalse(reloaded.value)
        XCTAssertEqual(restored.state.title, "Local commercial à louer, centre-ville")
        XCTAssertEqual(restored.state.listingPhone, "021123456")
        XCTAssertTrue(restored.state.isDirty)
        XCTAssertFalse(restored.state.editLoading)
    }

    // MARK: - Propres à iOS

    @MainActor
    func testPhotosDoublonParSha256AjouteeUneSeuleFois() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        await vm.onPhotosPicked([Self.photo("a"), Self.photo("a"), Self.photo("b")])?.value
        XCTAssertEqual(vm.state.photos.map { $0.localRef }, [Self.ref("a"), Self.ref("b")])
        XCTAssertNil(vm.state.photosNotice, "un doublon n'est pas un dépassement de la limite")
        await vm.waitForIdle()

        // La même photo choisie de nouveau (même octets, même SHA-256) : ignorée.
        await vm.onPhotosPicked([Self.photo("b")])?.value
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.photos.count, 2)
        XCTAssertEqual(fixture.uploadCount.value, 2)
        let file = vm.photoStore.fileURL(for: Self.ref("a"))
        XCTAssertEqual(try? Data(contentsOf: file), Self.photo("a"))
    }

    @MainActor
    func testPhotosFichiersPurgesAuDemarrageEffacesParClearDraftEtApresPublication() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let manager = FileManager.default
        try manager.createDirectory(at: fixture.photoDirectory, withIntermediateDirectories: true)
        let kept = Self.ref("kept")
        try Self.photo("kept").write(to: fixture.photos.fileURL(for: kept))
        let orphan = Self.ref("orphan")
        try Self.photo("orphan").write(to: fixture.photos.fileURL(for: orphan))
        fixture.drafts.write(#"{"photos":[{"localRef":"\#(kept)"}]}"#)

        // Démarrage : le fichier que le brouillon ne cite plus disparaît ; la photo restaurée repart en file.
        let vm = fixture.vm()
        XCTAssertFalse(manager.fileExists(atPath: fixture.photos.fileURL(for: orphan).path))
        XCTAssertTrue(manager.fileExists(atPath: fixture.photos.fileURL(for: kept).path))
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.photos.first?.status, .done)
        XCTAssertEqual(vm.state.photos.first?.upload?.url, "https://cdn/1.webp")

        // « Déposer une autre annonce » : brouillon ET fichiers effacés.
        vm.clearDraft()
        XCTAssertNil(fixture.drafts.read())
        XCTAssertFalse(manager.fileExists(atPath: fixture.photos.fileURL(for: kept).path))

        // Publication réussie : idem.
        await vm.onPhotosPicked([Self.photo("next")])?.value
        await vm.waitForIdle()
        XCTAssertTrue(manager.fileExists(atPath: fixture.photos.fileURL(for: Self.ref("next")).path))
        fixture.api.onCreateAnnonce = { body in AnnonceDTO(id: "a3", title: body.title, status: "PENDING") }
        await vm.submit()?.value
        XCTAssertEqual(vm.state.result?.id, "a3")
        XCTAssertNil(fixture.drafts.read())
        XCTAssertFalse(manager.fileExists(atPath: fixture.photos.fileURL(for: Self.ref("next")).path))
    }

    @MainActor
    func testPhotoRetireePendantSonEnvoiEstIgnoree() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        let count = fixture.uploadCount
        // Pendant le PREMIER envoi, l'utilisateur retire cette photo : la réponse arrive pour une photo disparue.
        fixture.api.onUpload = { [vm] _ in
            count.value += 1
            if count.value == 1 { vm.onRemovePhoto(at: 0) }
            return PostFixture.uploaded(count.value)
        }
        vm.onPhotosPicked([Self.photo("a"), Self.photo("b")])
        await vm.waitForIdle()
        XCTAssertEqual(vm.state.photos.map { $0.localRef }, [Self.ref("b")])
        XCTAssertEqual(vm.state.photos.first?.upload?.url, "https://cdn/2.webp")
        XCTAssertEqual(count.value, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vm.photoStore.fileURL(for: Self.ref("a")).path))
    }

    @MainActor
    func testEditionBrouillonEnMemoireJamaisSurLeBrouillonDisque() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let file = FilePostDraftStore(fileURL: fixture.photoDirectory.appendingPathComponent("post_draft.json"))
        let newPhotos = PostPhotoStore(directory: fixture.photoDirectory.appendingPathComponent("new", isDirectory: true))

        let fresh = PostListingViewModel.storage(editingId: nil, newDrafts: file, newPhotos: newPhotos)
        XCTAssertTrue((fresh.drafts as? FilePostDraftStore) === file)
        XCTAssertEqual(fresh.photos.directory, newPhotos.directory)

        let edit = PostListingViewModel.storage(editingId: "a7", newDrafts: file, newPhotos: newPhotos)
        XCTAssertTrue(edit.drafts is InMemoryPostDraftStore)
        XCTAssertEqual(edit.photos.directory.lastPathComponent, "edit")
        XCTAssertNotEqual(edit.photos.directory, newPhotos.directory)

        fixture.api.onGetAnnonce = { id in
            AnnonceDTO(
                id: id,
                title: "Local commercial à louer",
                description: String(repeating: "d", count: 30),
                category: CategoryRefDTO(id: "cat_srv", slug: "services", nameFr: "Services")
            )
        }
        let vm = fixture.vm(store: edit.drafts, editingId: "a7")
        await vm.waitForIdle()
        vm.onTitleChange("Local commercial à louer, centre-ville")
        XCTAssertTrue(edit.drafts.read()?.contains("centre-ville") ?? false)
        XCTAssertNil(file.read(), "une édition n'écrit jamais dans le brouillon du nouveau dépôt")
    }

    @MainActor
    func testAppareilPhotoIndisponibleAvisPuisEfface() async {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        let vm = fixture.vm()
        await vm.waitForIdle()
        vm.onCameraUnavailable()
        XCTAssertEqual(vm.state.photosNotice, L10n.postWizCameraUnavailable)
        XCTAssertEqual(vm.state.photosBanner?.kind, .error)
        XCTAssertFalse(vm.state.isDirty, "un avis n'est pas une saisie")
        vm.photosNoticeShown()
        XCTAssertNil(vm.state.photosNotice)
    }

    @MainActor
    func testEmailVerifieSuiviEnDirect() async throws {
        let fixture = PostFixture()
        defer { fixture.cleanUp() }
        fixture.api.onLogin = { _ in FakeWeydaAPI.tokens(emailVerified: false) }
        _ = try await fixture.auth.login(email: "amina@example.com", password: "Secret123")
        let vm = fixture.vm()
        await vm.waitForIdle()
        XCTAssertFalse(vm.state.emailVerified)

        fixture.api.onConfirm = { _ in SimpleResponseDTO() }
        try await fixture.auth.confirmEmail(code: "123456")
        XCTAssertTrue(vm.state.emailVerified)
    }
}
