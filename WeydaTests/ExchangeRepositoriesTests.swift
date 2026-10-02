import Foundation
import XCTest
@testable import Weyda

/// Portage de SavedSearchesRepositoryTest.kt, UploadRepositoryTest.kt et des parties repository de ReportsTest.kt
/// (Android) : alertes, envoi de photo, signalements. Données fictives.
final class ExchangeRepositoriesTests: XCTestCase {
    // MARK: - Alertes

    @MainActor
    func testSavedSearchesListCreateWithoutBlankValuesDuplicateAndDelete() async throws {
        let api = FakeWeydaAPI()
        let repository = SavedSearchesRepository(api: api)
        api.onGetSavedSearches = {
            SavedSearchesDTO(
                searches: [
                    SavedSearchDTO(id: "s1", name: "clio · Alger", params: ["q": "clio", "wilaya": "16"], createdAt: "2026-09-08T10:00:00.000Z"),
                ],
                max: 5
            )
        }
        let list = try await repository.list()
        XCTAssertEqual(list.first?.name, "clio · Alger")
        XCTAssertEqual(list.first?.params, ["q": "clio", "wilaya": "16"])
        XCTAssertNotNil(list.first?.createdAt)

        api.onCreateSavedSearch = { body in
            XCTAssertEqual(body.params, ["q": "golf", "attr_make": "volkswagen"])
            return SavedSearchCreatedDTO(search: SavedSearchDTO(id: "s2", name: "golf · +1", params: body.params))
        }
        let created = try await repository.create(params: ["q": "golf", "priceMin": "", "attr_make": "volkswagen"])
        XCTAssertFalse(created.duplicate)
        XCTAssertEqual(created.search.id, "s2")

        api.onCreateSavedSearch = { body in
            SavedSearchCreatedDTO(search: SavedSearchDTO(id: "s2", name: "golf", params: body.params), duplicate: true)
        }
        let duplicate = try await repository.create(params: ["q": "golf"])
        XCTAssertTrue(duplicate.duplicate)

        api.onCreateSavedSearch = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"savedSearchLimit"}"#) }
        do {
            _ = try await repository.create(params: ["q": "x"])
            XCTFail("limite attendue")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "savedSearchLimit")
        }

        api.onDeleteSavedSearch = { id in
            XCTAssertEqual(id, "s1")
            return SimpleResponseDTO()
        }
        try await repository.delete(id: "s1")
        XCTAssertEqual(api.count("deleteSavedSearch"), 1)
    }

    // MARK: - Envoi de photo

    @MainActor
    func testUploadSendsThePreparedJPEGAsMultipartFileAndReturnsUrlAndPublicId() async throws {
        let api = FakeWeydaAPI()
        let uploads = UploadRepository(api: api, prepare: { data in Data("JPEG-".utf8) + data })
        api.onUpload = { file in
            XCTAssertEqual(file.fieldName, "file")
            XCTAssertEqual(file.fileName, "photo.jpg")
            XCTAssertEqual(file.mimeType, "image/jpeg")
            XCTAssertEqual(String(decoding: file.data, as: UTF8.self), "JPEG-photo-1")
            return UploadResponseDTO(
                url: "https://cdn.example.com/x.webp",
                thumbnailUrl: "https://cdn.example.com/x_thumb.webp",
                publicId: "annonces/x.webp"
            )
        }
        let image = try await uploads.upload(imageData: Data("photo-1".utf8))
        XCTAssertEqual(image.url, "https://cdn.example.com/x.webp")
        XCTAssertEqual(image.thumbnailUrl, "https://cdn.example.com/x_thumb.webp")
        XCTAssertEqual(image.publicId, "annonces/x.webp")
    }

    @MainActor
    func testUnreadableImageFailsWithoutNetworkAndServerErrorsPropagate() async throws {
        let api = FakeWeydaAPI()
        let uploads = UploadRepository(api: api, prepare: { data in
            if data.isEmpty { throw CocoaError(.fileReadCorruptFile) }
            if data.count > 10 { throw ImagePreparationError.tooLarge }
            return data
        })
        api.onUpload = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"fileTooLarge"}"#) }

        do {
            _ = try await uploads.upload(imageData: Data())
            XCTFail("image illisible attendue")
        } catch let error as ImagePreparationError {
            XCTAssertEqual(error, .unreadable)
        }
        do {
            _ = try await uploads.upload(imageData: Data(repeating: 1, count: 64))
            XCTFail("image trop lourde attendue")
        } catch let error as ImagePreparationError {
            XCTAssertEqual(error, .tooLarge)
        }
        XCTAssertEqual(api.count("upload"), 0)

        do {
            _ = try await uploads.upload(imageData: Data("ok".utf8))
            XCTFail("refus du serveur attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "fileTooLarge")
        }
        XCTAssertEqual(api.count("upload"), 1)
    }

    // MARK: - Signalements

    @MainActor
    func testReportSendsTheReasonAsIsAndCleansTheDetails() async throws {
        let api = FakeWeydaAPI()
        let repository = ReportsRepository(api: api)
        let sent = FakeWeydaAPI.Box<ReportRequestDTO?>(nil)
        api.onReport = { body in
            sent.value = body
            return ReportDTO(id: "rep1", annonceId: body.annonceId ?? "", reason: body.reason)
        }

        try await repository.report(annonceId: "a1", reason: .fraud, details: "  Le vendeur demande un acompte.  ")
        XCTAssertEqual(sent.value?.annonceId, "a1")
        XCTAssertEqual(sent.value?.reason, "FRAUD")
        XCTAssertEqual(sent.value?.details, "Le vendeur demande un acompte.")

        // Détails vides ou blancs : le serveur attend `null`, pas une chaîne vide.
        try await repository.report(annonceId: "a1", reason: .spam, details: "   ")
        XCTAssertNil(sent.value?.details)
        try await repository.report(annonceId: "a1", reason: .spam, details: nil)
        XCTAssertNil(sent.value?.details)

        // 1000 caractères au maximum côté Zod : on coupe plutôt que de récolter un 400.
        try await repository.report(annonceId: "a1", reason: .other, details: String(repeating: "x", count: 1500))
        XCTAssertEqual(sent.value?.details?.count, ReportReason.detailsMax)

        try await repository.reportUser(userId: "u2", conversationId: "c1", reason: .inappropriate, details: nil)
        XCTAssertNil(sent.value?.annonceId)
        XCTAssertEqual(sent.value?.reportedUserId, "u2")
        XCTAssertEqual(sent.value?.conversationId, "c1")
        XCTAssertEqual(sent.value?.reason, "INAPPROPRIATE")
    }

    @MainActor
    func testAnAlreadySentReportIsTranslated() async throws {
        let api = FakeWeydaAPI()
        api.onReport = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"alreadyReported"}"#) }
        do {
            try await ReportsRepository(api: api).report(annonceId: "a1", reason: .spam, details: nil)
            XCTFail("409 attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "alreadyReported")
            XCTAssertEqual(ErrorMapper.message(for: error), L10n.errorAlreadyReported)
        }
    }

    func testTheFiveReasonsAreTheServerEnum() {
        XCTAssertEqual(ReportReason.allCases.map { $0.rawValue }, ["SPAM", "INAPPROPRIATE", "FRAUD", "DUPLICATE", "OTHER"])
    }
}
