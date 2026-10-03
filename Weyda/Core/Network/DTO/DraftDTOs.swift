import Foundation

// Portage de data/remote/dto/DraftDtos.kt — brouillon du dépôt d'annonce et réponse d'envoi de photo.

/// Brouillon du formulaire « Déposer une annonce », sérialisé en JSON sur l'appareil (survit à la fermeture
/// de l'app). Jamais envoyé au serveur. Lecture tolérante : un brouillon d'une version antérieure reste lisible.
nonisolated struct PostDraftDTO: Codable, Hashable, Sendable {
    /// Compte auteur du brouillon : un autre compte connecté sur le même téléphone ne le voit jamais.
    var ownerId: String? = nil
    /// Édition : numéro de contact déjà porté par l'annonce.
    var listingPhone: String? = nil
    /// Édition : l'utilisateur a modifié quelque chose (confirmation avant d'abandonner).
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
    /// Nom de l'étape courante de l'assistant.
    var step: String = "CATEGORY"
    /// Photos choisies : référence locale + résultat d'envoi si déjà envoyée.
    var photos: [PhotoDraftDTO] = []
}

nonisolated extension PostDraftDTO {
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
        photos = container.lenientList(PhotoDraftDTO.self, "photos")
    }
}

nonisolated struct PhotoDraftDTO: Codable, Hashable, Sendable {
    /// Référence locale de la photo (Android : URI du contenu ; iOS : identifiant ou chemin local).
    var localUri: String
    var url: String? = nil
    var thumbnailUrl: String? = nil
    var publicId: String? = nil
}

nonisolated extension PhotoDraftDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        localUri = try container.requiredString("localUri")
        url = container.lenientString("url")
        thumbnailUrl = container.lenientString("thumbnailUrl")
        publicId = container.lenientString("publicId")
    }
}

/// `POST /api/upload` → `{ url, thumbnailUrl, publicId }` (à passer dans `images[]` de POST /api/annonces).
nonisolated struct UploadResponseDTO: Decodable, Hashable, Sendable {
    var url: String
    var thumbnailUrl: String = ""
    var publicId: String
}

nonisolated extension UploadResponseDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        url = try container.requiredString("url")
        thumbnailUrl = container.lenientString("thumbnailUrl") ?? ""
        publicId = try container.requiredString("publicId")
    }
}
