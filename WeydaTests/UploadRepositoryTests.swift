import Foundation
import XCTest
@testable import Weyda

/// Portage d'UploadRepositoryTest.kt (Android), mêmes cas, `prepare` injecté (Android : `ImagePreparer` factice qui
/// refuse les URI contenant « bad »). En plus (iOS) : erreurs typées de préparation conservées, annulation propagée
/// sans appel réseau. Données fictives.
final class UploadRepositoryTests: XCTestCase {
    /// Préparation factice : « JPEGDATA- » + octets reçus ; « bad » → erreur quelconque (devient `.unreadable`).
    private static func prepare(_ data: Data) async throws -> Data {
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("bad") { throw CocoaError(.fileReadCorruptFile) }
        if text.contains("huge") { throw ImagePreparationError.tooLarge }
        if text.contains("cancel") { throw CancellationError() }
        return Data("JPEGDATA-".utf8) + data
    }

    @MainActor
    private func makeRepository(_ api: FakeWeydaAPI) -> UploadRepository {
        UploadRepository(api: api, prepare: { data in try await UploadRepositoryTests.prepare(data) })
    }

    @MainActor
    func testEnvoieLImagePrepareeEnMultipartChampFileEtRenvoieUrlEtPublicId() async throws {
        let api = FakeWeydaAPI()
        let sent = FakeWeydaAPI.Box<MultipartFile?>(nil)
        api.onUpload = { file in
            sent.value = file
            return UploadResponseDTO(url: "https://cdn/x.webp", thumbnailUrl: "https://cdn/x_thumb.webp", publicId: "annonces/x.webp")
        }
        let image = try await makeRepository(api).upload(imageData: Data("content://p/1".utf8))

        let file = try XCTUnwrap(sent.value)
        XCTAssertEqual(file.fieldName, "file")
        XCTAssertEqual(file.fileName, "photo.jpg")
        XCTAssertEqual(file.mimeType, "image/jpeg")
        XCTAssertEqual(String(decoding: file.data, as: UTF8.self), "JPEGDATA-content://p/1")
        XCTAssertEqual(image.url, "https://cdn/x.webp")
        XCTAssertEqual(image.thumbnailUrl, "https://cdn/x_thumb.webp")
        XCTAssertEqual(image.publicId, "annonces/x.webp")
    }

    @MainActor
    func testImageIllisibleSansAppelReseauErreurServeurPropagee() async {
        let api = FakeWeydaAPI()
        api.onUpload = { _ in throw FakeWeydaAPI.apiError(400, #"{"error":"fileTooLarge"}"#) }
        let uploads = makeRepository(api)

        do {
            _ = try await uploads.upload(imageData: Data("content://p/bad".utf8))
            XCTFail("image illisible attendue")
        } catch {
            XCTAssertEqual(error as? ImagePreparationError, .unreadable)
        }
        XCTAssertEqual(api.count("upload"), 0)

        do {
            _ = try await uploads.upload(imageData: Data("content://p/2".utf8))
            XCTFail("refus du serveur attendu")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, "fileTooLarge")
            XCTAssertEqual(ErrorMapper.message(for: error), L10n.errorUploadTooLarge)
        }
        XCTAssertEqual(api.count("upload"), 1)
    }

    @MainActor
    func testErreurTypeeDePreparationEtAnnulationConserveesSansAppelReseau() async {
        let api = FakeWeydaAPI()
        api.onUpload = { _ in UploadResponseDTO(url: "https://cdn/x.webp", publicId: "annonces/x.webp") }
        let uploads = makeRepository(api)

        do {
            _ = try await uploads.upload(imageData: Data("content://p/huge".utf8))
            XCTFail("image trop lourde attendue")
        } catch {
            XCTAssertEqual(error as? ImagePreparationError, .tooLarge)
            XCTAssertEqual(ErrorMapper.message(for: error), L10n.errorUploadTooLarge)
        }
        do {
            _ = try await uploads.upload(imageData: Data("content://p/cancel".utf8))
            XCTFail("annulation attendue")
        } catch {
            XCTAssertTrue(error is CancellationError)
            XCTAssertNil(ErrorMapper.message(for: error), "une annulation ne s'affiche jamais")
        }
        XCTAssertEqual(api.count("upload"), 0)
    }
}
