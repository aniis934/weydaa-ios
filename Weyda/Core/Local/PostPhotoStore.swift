import CryptoKit
import Foundation

/// Photos choisies pour une annonce, copiées dans un dossier de l'app le temps du dépôt. Android gardait l'URI
/// `content://` du sélecteur (relisible plus tard) ; iOS remet des OCTETS (PhotosPicker, appareil photo) : sans copie,
/// une photo pas encore envoyée serait perdue à la fermeture de l'app, et le brouillon ne pourrait pas la renvoyer.
///
/// Nom du fichier = SHA-256 des octets (hexadécimal) : une même photo choisie deux fois a la même référence (doublon
/// écarté par l'assistant) et n'est écrite qu'une fois. Dossier créé à la demande, exclu des sauvegardes iCloud ;
/// `purge(keeping:)` au démarrage efface ce que le brouillon ne cite plus.
nonisolated struct PostPhotoStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/PostDrafts/<namespace>/` : "new" (nouveau dépôt) ou "edit" (édition).
    static func standard(namespace: String) -> PostPhotoStore {
        PostPhotoStore(directory: PostDraftFiles.root.appendingPathComponent(namespace, isDirectory: true))
    }

    /// Référence d'une photo : SHA-256 des octets en hexadécimal minuscule (64 caractères).
    static func ref(for data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var characters: [UInt8] = []
        characters.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            characters.append(digits[Int(byte >> 4)])
            characters.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: characters, as: UTF8.self)
    }

    /// Vrai pour une référence de fichier local (64 chiffres hexadécimaux). Une URL distante (photo d'une annonce en
    /// édition) ou une valeur abîmée n'est jamais un chemin : aucun accès hors du dossier n'est possible.
    static func isLocalRef(_ ref: String) -> Bool {
        ref.utf8.count == 64 && ref.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Fichier d'une photo locale (aperçu : `LocalPhotoThumbnail(fileURL:)`).
    func fileURL(for ref: String) -> URL {
        directory.appendingPathComponent(Self.isLocalRef(ref) ? ref : "_", isDirectory: false)
    }

    /// Copie les octets (hors du fil principal) et renvoie leur référence ; fichier déjà présent → même référence,
    /// sans réécriture.
    @concurrent
    func save(_ data: Data) async throws -> String {
        let ref = Self.ref(for: data)
        let url = fileURL(for: ref)
        if FileManager.default.fileExists(atPath: url.path) { return ref }
        try PostDraftFiles.ensureDirectory(directory)
        try data.write(to: url, options: [.atomic])
        return ref
    }

    /// Octets d'une photo locale ; absente ou référence invalide → erreur (l'assistant affiche « illisible »).
    @concurrent
    func load(_ ref: String) async throws -> Data {
        guard Self.isLocalRef(ref) else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: fileURL(for: ref))
    }

    func remove(_ ref: String) {
        guard Self.isLocalRef(ref) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: ref))
    }

    /// Efface tous les fichiers du dossier sauf `refs` (démarrage : photos d'un brouillon abandonné ; `[]` = tout).
    func purge(keeping refs: Set<String>) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !refs.contains(name) {
            try? manager.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }
}
