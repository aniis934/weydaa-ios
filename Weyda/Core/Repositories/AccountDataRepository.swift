import Foundation

/// Conformité loi 18-07 : portabilité (`GET /api/users/me/export`) et droit à l'effacement
/// (`DELETE /api/users/me/account`) — portage d'`AccountDataRepository`.
///
/// L'export est écrit dans le dossier temporaire de l'app (`tmp/exports`), partagé ensuite par la feuille de partage
/// du système : rien ne transite par un stockage public, et le fichier disparaît à la fermeture de session.
final class AccountDataRepository {
    /// Sous-dossiers de `tmp` qui contiennent des données personnelles : l'export JSON et les photos prises pour un
    /// dépôt (pleine résolution). À effacer dès que la session se ferme.
    static let exportDirectoryName = "exports"
    static let cameraDirectoryName = "camera"

    private let api: any WeydaAPI
    private let session: SessionManager
    private let temporaryDirectory: URL

    init(api: any WeydaAPI, session: SessionManager, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.api = api
        self.session = session
        self.temporaryDirectory = temporaryDirectory
    }

    var exportDirectory: URL {
        temporaryDirectory.appendingPathComponent(Self.exportDirectoryName, isDirectory: true)
    }

    var cameraDirectory: URL {
        temporaryDirectory.appendingPathComponent(Self.cameraDirectoryName, isDirectory: true)
    }

    /// Télécharge le JSON d'export (les exports précédents sont effacés) et renvoie le fichier prêt à partager,
    /// `weydaa-AAAA-MM-JJ.json`. 2 exports / 24 h (429 + `Retry-After`).
    func export() async throws -> URL {
        let directory = exportDirectory
        try? FileManager.default.removeItem(at: directory)
        let target = directory.appendingPathComponent("weydaa-\(Self.dateStamp(Date())).json", isDirectory: false)
        return try await api.exportData(to: target)
    }

    /// Efface l'export et les captures laissés dans `tmp` (déconnexion, session révoquée, compte supprimé) : rien ne
    /// reste pour le prochain utilisateur de l'appareil.
    func clearLocalFiles() {
        for directory in [exportDirectory, cameraDirectory] {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Captures de plus de `maxAge` (24 h) jamais envoyées — dépôt abandonné : supprimées (appelé au démarrage, hors
    /// du fil principal).
    nonisolated static func purgeStaleCaptures(in directory: URL, maxAge: TimeInterval = 24 * 3600, now: Date = Date()) {
        let files = FileManager.default
        guard let entries = try? files.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let limit = now.addingTimeInterval(-maxAge)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < limit {
                try? files.removeItem(at: entry)
            }
        }
    }

    /// Compte avec mot de passe. 400 `incorrectPassword` / `accountDeletionNotAllowed` (compte Google ou Apple),
    /// 403 `adminAccountCannotBeDeleted`. Succès = session fermée localement.
    func deleteAccount(password: String) async throws {
        try await delete(DeleteAccountRequestDTO(password: password))
    }

    /// Compte créé avec Google : l'effacement est confirmé par un id_token Google frais du même compte.
    func deleteGoogleAccount(idToken: String) async throws {
        try await delete(DeleteAccountRequestDTO(googleIdToken: idToken))
    }

    /// Compte créé avec Apple (lot serveur A) : jeton d'identité frais + nonce clair + code d'autorisation, que le
    /// serveur utilise pour révoquer l'accès Apple avant l'effacement (exigence de l'App Store).
    func deleteAppleAccount(identityToken: String, nonce: String, authorizationCode: String?) async throws {
        try await delete(DeleteAccountRequestDTO(appleIdentityToken: identityToken, nonce: nonce, appleAuthorizationCode: authorizationCode))
    }

    private func delete(_ body: DeleteAccountRequestDTO) async throws {
        _ = try await api.deleteAccount(body)
        session.signOut()
    }

    /// `AAAA-MM-JJ` dans le fuseau du téléphone, chiffres latins.
    private static func dateStamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
