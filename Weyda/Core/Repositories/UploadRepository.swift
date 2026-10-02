import Foundation

/// `POST /api/upload` (multipart, champ `file`, ≤ 5 Mo) : photo préparée en mémoire par `ImagePreparer` (JPEG
/// 1600 px, sans métadonnées) puis envoyée avec le client authentifié — portage d'`UploadRepository`.
/// 403 `emailNotVerified`, 429 + `Retry-After: 600`.
final class UploadRepository {
    private let api: any WeydaAPI
    private let prepare: @Sendable (Data) async throws -> Data

    /// `prepare` : préparation de l'image (remplaçable dans les tests) ; par défaut `ImagePreparer().prepare(_:)`,
    /// exécuté hors du fil principal.
    init(api: any WeydaAPI, prepare: @escaping @Sendable (Data) async throws -> Data = { try await ImagePreparer().prepare($0) }) {
        self.api = api
        self.prepare = prepare
    }

    /// Image illisible ou trop lourde → `ImagePreparationError` (traduite par `ErrorMapper`), sans aucun appel réseau.
    func upload(imageData: Data) async throws -> UploadedImage {
        let jpeg: Data
        do {
            jpeg = try await prepare(imageData)
        } catch let error as ImagePreparationError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ImagePreparationError.unreadable
        }
        let file = MultipartFile(fileName: "photo.jpg", mimeType: "image/jpeg", data: jpeg)
        return try await api.upload(file).toDomain()
    }
}
