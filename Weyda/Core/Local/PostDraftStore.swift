import Foundation
import os

// Brouillon du formulaire « Déposer une annonce » — portage de PostDraftDto (data/remote/dto/DraftDtos.kt) et des
// `DraftStore` d'ui/post/PostListingViewModel.kt (PreferencesDraftStore, InMemoryDraftStore).

/// Brouillon sérialisé en JSON : sur disque pour un nouveau dépôt (survit à la fermeture de l'app et au retour hors
/// de l'onglet), en mémoire pour une édition. Jamais envoyé au serveur. Lecture tolérante (`decodeIfPresent` + défauts
/// d'Android) : un brouillon d'une version antérieure, ou un champ illisible, ne fait pas perdre le reste.
nonisolated struct PostDraft: Codable, Hashable, Sendable {
    /// Photo choisie : fichier local + résultat d'envoi si elle est déjà partie (Android : `PhotoDraftDto`).
    nonisolated struct Photo: Codable, Hashable, Sendable {
        /// Nom du fichier dans `PostPhotoStore` (SHA-256) ; édition : URL distante (Android : `localUri`).
        var localRef: String
        var url: String? = nil
        var thumbnailUrl: String? = nil
        var publicId: String? = nil
    }

    /// Compte auteur du brouillon : un autre compte connecté sur le même téléphone ne le voit jamais.
    var ownerId: String? = nil
    /// Édition : numéro de contact déjà porté par l'annonce (voir `PostListingState.listingPhone`).
    var listingPhone: String? = nil
    /// L'utilisateur a modifié quelque chose (confirmation avant d'abandonner une édition).
    var dirty: Bool = false
    var parentCategoryId: String? = nil
    var subcategoryId: String? = nil
    var attributeValues: [String: String] = [:]
    var title: String = ""
    var description: String = ""
    var priceType: String = "FIXED"
    var price: String = ""
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    var showPhone: Bool = false
    /// Valeur brute de l'étape courante (`PostStep.rawValue`).
    var step: String = "CATEGORY"
    var photos: [Photo] = []
}

nonisolated extension PostDraft {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        ownerId = container.lenientString("ownerId")
        listingPhone = container.lenientString("listingPhone")
        dirty = container.lenientBool("dirty") ?? false
        parentCategoryId = container.lenientString("parentCategoryId")
        subcategoryId = container.lenientString("subcategoryId")
        attributeValues = container.lenientStringMap("attributeValues") ?? [:]
        title = container.lenientString("title") ?? ""
        description = container.lenientString("description") ?? ""
        priceType = container.lenientString("priceType") ?? "FIXED"
        price = container.lenientString("price") ?? ""
        wilayaId = container.lenientInt("wilayaId")
        communeId = container.lenientInt("communeId")
        showPhone = container.lenientBool("showPhone") ?? false
        step = container.lenientString("step") ?? "CATEGORY"
        photos = container.lenientList(PostDraft.Photo.self, "photos")
    }
}

nonisolated extension PostDraft.Photo {
    /// `localRef` obligatoire (une photo sans référence est ignorée par la liste) ; `localUri` d'Android accepté.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        let reference = TextCheck.nonBlank(container.lenientString("localRef"))
            ?? TextCheck.nonBlank(container.lenientString("localUri"))
        guard let reference else {
            throw DecodingError.keyNotFound(
                DTOKey("localRef"),
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Photo de brouillon sans localRef")
            )
        }
        localRef = reference
        url = container.lenientString("url")
        thumbnailUrl = container.lenientString("thumbnailUrl")
        publicId = container.lenientString("publicId")
    }
}

/// Persistance du brouillon (fichier pour un nouveau dépôt, mémoire pour une édition et les tests) — `DraftStore`.
nonisolated protocol PostDraftStore: Sendable {
    func read() -> String?
    func write(_ value: String)
    func clear()
}

/// Emplacements communs du brouillon et de ses photos : `Application Support/PostDrafts/`, exclu des sauvegardes
/// iCloud (Android : backup_rules.xml) — un brouillon n'a rien à faire sur un autre appareil.
nonisolated enum PostDraftFiles {
    static var root: URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        return base.appendingPathComponent("PostDrafts", isDirectory: true)
    }

    /// Crée le dossier à la demande (intermédiaires compris) et l'exclut des sauvegardes.
    static func ensureDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var marked = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? marked.setResourceValues(values)
    }
}

/// Brouillon du NOUVEAU dépôt sur disque — `PreferencesDraftStore` (Android). Écritures en tâche de fond sur une file
/// série (comme `SharedPreferences.apply`) : la saisie n'attend jamais le disque ; une lecture attend les écritures en
/// attente (même file), elle voit donc toujours la dernière valeur. Écriture atomique : un arrêt brutal laisse
/// l'ancien brouillon ou le nouveau, jamais un fichier tronqué.
nonisolated final class FilePostDraftStore: PostDraftStore {
    let fileURL: URL
    private let queue: DispatchQueue

    private static let logger = Logger(subsystem: "com.weydaa.app", category: "post-draft")

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.queue = DispatchQueue(label: "com.weydaa.app.post-draft", qos: .utility)
    }

    /// `Application Support/PostDrafts/post_draft.json`.
    static func standard() -> FilePostDraftStore {
        FilePostDraftStore(fileURL: PostDraftFiles.root.appendingPathComponent("post_draft.json", isDirectory: false))
    }

    func read() -> String? {
        let url = fileURL
        return queue.sync { () -> String? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    func write(_ value: String) {
        let url = fileURL
        queue.async {
            FilePostDraftStore.store(value, at: url)
        }
    }

    func clear() {
        let url = fileURL
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func store(_ value: String, at url: URL) {
        do {
            try PostDraftFiles.ensureDirectory(url.deletingLastPathComponent())
            try Data(value.utf8).write(to: url, options: [.atomic])
        } catch {
            // Disque plein, dossier protégé… : le brouillon est un confort, la saisie continue.
            logger.error("Brouillon non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Brouillon en mémoire : édition (iOS ne tue pas l'app pendant l'appareil photo comme Android peut le faire) et
/// tests — `InMemoryDraftStore`. Verrou : lisible et modifiable depuis n'importe quel fil.
nonisolated final class InMemoryPostDraftStore: PostDraftStore {
    private let storage: OSAllocatedUnfairLock<String?>

    init(_ value: String? = nil) {
        self.storage = OSAllocatedUnfairLock(initialState: value)
    }

    func read() -> String? {
        storage.withLock { $0 }
    }

    func write(_ value: String) {
        storage.withLock { $0 = value }
    }

    func clear() {
        storage.withLock { $0 = nil }
    }
}
