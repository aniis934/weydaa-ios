import Foundation

// Portage de data/remote/dto/Dtos.kt : réponses JSON de src/app/api (docs/API-CONTRACT.md, dépôt privé).
// Tous les champs non garantis ont la valeur par défaut d'Android (tolérance aux évolutions de l'API) ;
// lecture tolérante : voir LenientDecoding.swift. `init(from:)` dans une extension : l'initialiseur membre à
// membre (avec ces défauts) reste disponible pour les tests et l'API simulée.
//
// `ApiErrorDto` (Android) n'est pas porté ici : le corps d'erreur `{ error, … }` est décodé par le client
// réseau (`APIError`, agent NETWORK) ; aucun mapper n'en a besoin.

/// `GET /api/annonces`, `GET /api/users/{id}/annonces`, `GET /api/users/me/annonces`.
nonisolated struct AnnoncesPageDTO: Decodable, Hashable, Sendable {
    var annonces: [AnnonceDTO] = []
    var total: Int = 0
    var page: Int = 1
    var totalPages: Int = 1
    /// Avec `withFacets=1` sur une catégorie à attributs : clé → valeurs comptées.
    var facets: [String: [FacetValueDTO]]? = nil
}

nonisolated extension AnnoncesPageDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        annonces = container.lenientList(AnnonceDTO.self, "annonces")
        total = container.lenientInt("total") ?? 0
        page = container.lenientInt("page") ?? 1
        totalPages = container.lenientInt("totalPages") ?? 1
        if let raw = try? container.decodeIfPresent([String: [DTOLossy<FacetValueDTO>]].self, forKey: "facets") {
            facets = raw.mapValues { values in values.compactMap { $0.value } }
        }
    }
}

nonisolated struct FacetValueDTO: Decodable, Hashable, Sendable {
    var value: String
    var count: Int = 0
}

nonisolated extension FacetValueDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        value = try container.requiredString("value")
        count = container.lenientInt("count") ?? 0
    }
}

nonisolated struct AnnonceDTO: Decodable, Hashable, Sendable {
    var id: String
    var slug: String? = nil
    var title: String
    var description: String = ""
    /// Prisma Decimal sérialisé en nombre JSON (texte toléré) ; `nil` si gratuit / sur demande.
    var price: Double? = nil
    var priceType: String = "FIXED"
    var status: String = "ACTIVE"
    var views: Int = 0
    var isFeatured: Bool = false
    /// Propriétaire seulement : le numéro n'est plus exposé publiquement (voir `hasPhone`).
    var phone: String? = nil
    /// Le vendeur affiche un numéro, à révéler par `GET /api/annonces/{id}/contact` (connexion requise).
    var hasPhone: Bool? = nil
    var createdAt: String = ""
    var updatedAt: String = ""
    var expiresAt: String? = nil
    var userId: String = ""
    var categoryId: String = ""
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    var renewalCount: Int = 0
    var attributes: JSONValue? = nil
    /// Liste : 1 image au plus (la première). Détail : toutes, triées par `order`.
    var images: [ImageDTO] = []
    var category: CategoryRefDTO? = nil
    var wilaya: WilayaDTO? = nil
    var commune: CommuneDTO? = nil
    var user: UserRefDTO? = nil
    /// Seulement dans GET /api/users/me/annonces (motif d'un rejet / verdict IA).
    var aiModeration: AiModerationDTO? = nil
}

nonisolated extension AnnonceDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        slug = container.lenientString("slug")
        title = try container.requiredString("title")
        description = container.lenientString("description") ?? ""
        price = container.lenientDouble("price")
        priceType = container.lenientString("priceType") ?? "FIXED"
        status = container.lenientString("status") ?? "ACTIVE"
        views = container.lenientInt("views") ?? 0
        isFeatured = container.lenientBool("isFeatured") ?? false
        phone = container.lenientString("phone")
        hasPhone = container.lenientBool("hasPhone")
        createdAt = container.lenientString("createdAt") ?? ""
        updatedAt = container.lenientString("updatedAt") ?? ""
        expiresAt = container.lenientString("expiresAt")
        userId = container.lenientString("userId") ?? ""
        categoryId = container.lenientString("categoryId") ?? ""
        wilayaId = container.lenientInt("wilayaId")
        communeId = container.lenientInt("communeId")
        renewalCount = container.lenientInt("renewalCount") ?? 0
        attributes = container.lenientJSON("attributes")
        images = container.lenientList(ImageDTO.self, "images")
        category = container.lenientObject(CategoryRefDTO.self, "category")
        wilaya = container.lenientObject(WilayaDTO.self, "wilaya")
        commune = container.lenientObject(CommuneDTO.self, "commune")
        user = container.lenientObject(UserRefDTO.self, "user")
        aiModeration = container.lenientObject(AiModerationDTO.self, "aiModeration")
    }
}

nonisolated struct AiModerationDTO: Decodable, Hashable, Sendable {
    var decision: String = ""
    var confidence: Double? = nil
    /// JSON libre (souvent un tableau de textes).
    var reasons: JSONValue? = nil
    var suggestedCategory: String? = nil
    var descriptionSuggestions: String? = nil
}

nonisolated extension AiModerationDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        decision = container.lenientString("decision") ?? ""
        confidence = container.lenientDouble("confidence")
        reasons = container.lenientJSON("reasons")
        suggestedCategory = container.lenientString("suggestedCategory")
        descriptionSuggestions = container.lenientString("descriptionSuggestions")
    }
}

nonisolated struct ImageDTO: Decodable, Hashable, Sendable {
    var id: String = ""
    var url: String
    var publicId: String = ""
    var order: Int = 0
}

nonisolated extension ImageDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = container.lenientString("id") ?? ""
        url = try container.requiredString("url")
        publicId = container.lenientString("publicId") ?? ""
        order = container.lenientInt("order") ?? 0
    }
}

nonisolated struct CategoryRefDTO: Decodable, Hashable, Sendable {
    var id: String? = nil
    var slug: String
    var nameFr: String
    var nameAr: String = ""
    var nameEn: String = ""
    var parentId: String? = nil
    /// Détail seulement : slug de la catégorie racine.
    var parent: ParentRefDTO? = nil
}

nonisolated extension CategoryRefDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = container.lenientString("id")
        slug = try container.requiredString("slug")
        nameFr = try container.requiredString("nameFr")
        nameAr = container.lenientString("nameAr") ?? ""
        nameEn = container.lenientString("nameEn") ?? ""
        parentId = container.lenientString("parentId")
        parent = container.lenientObject(ParentRefDTO.self, "parent")
    }
}

nonisolated struct ParentRefDTO: Decodable, Hashable, Sendable {
    var slug: String = ""
}

nonisolated extension ParentRefDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        slug = container.lenientString("slug") ?? ""
    }
}

nonisolated struct WilayaDTO: Decodable, Hashable, Sendable {
    var id: Int
    var nameFr: String
    var nameAr: String = ""
    var wilayaId: Int? = nil
    /// Présent seulement sur `GET /api/wilayas?top=` : annonces actives dans la wilaya.
    var listingsCount: Int = 0
}

nonisolated extension WilayaDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredInt("id")
        nameFr = try container.requiredString("nameFr")
        nameAr = container.lenientString("nameAr") ?? ""
        wilayaId = container.lenientInt("wilayaId")
        listingsCount = container.lenientInt("listingsCount") ?? 0
    }
}

nonisolated struct CommuneDTO: Decodable, Hashable, Sendable {
    var id: Int
    var nameFr: String
    var nameAr: String = ""
    var wilayaId: Int? = nil
}

nonisolated extension CommuneDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredInt("id")
        nameFr = try container.requiredString("nameFr")
        nameAr = container.lenientString("nameAr") ?? ""
        wilayaId = container.lenientInt("wilayaId")
    }
}

/// Bloc `user` d'une annonce, auteur d'un avis, interlocuteur d'une conversation, profil public `GET /api/users/{id}`.
nonisolated struct UserRefDTO: Decodable, Hashable, Sendable {
    /// Absent de certaines projections (`POST /api/reviews` renvoie `author: { name }` seul).
    var id: String = ""
    var name: String? = nil
    var avatar: String? = nil
    var createdAt: String? = nil
    /// Date ISO de vérification (détail d'annonce et profil public) : sa seule présence vaut « vérifié ».
    var emailVerified: String? = nil
    /// Profil public seulement (`GET /api/users/{id}`).
    var bio: String? = nil
    var isRecommended: Bool = false
    var ratingCount: Int = 0
    var ratingSum: Int = 0
    var responseMinutes: Int? = nil
    /// Clé JSON `_count`.
    var count: CountDTO? = nil
}

nonisolated extension UserRefDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = container.lenientString("id") ?? ""
        name = container.lenientString("name")
        avatar = container.lenientString("avatar")
        createdAt = container.lenientString("createdAt")
        emailVerified = container.lenientString("emailVerified")
        bio = container.lenientString("bio")
        isRecommended = container.lenientBool("isRecommended") ?? false
        ratingCount = container.lenientInt("ratingCount") ?? 0
        ratingSum = container.lenientInt("ratingSum") ?? 0
        responseMinutes = container.lenientInt("responseMinutes")
        count = container.lenientObject(CountDTO.self, "_count")
    }
}

/// `GET /api/categories` : tableau nu des catégories racines (`DTOLossyList<CategoryDTO>`).
nonisolated struct CategoryDTO: Decodable, Hashable, Sendable {
    var id: String
    var slug: String
    var nameFr: String
    var nameAr: String = ""
    var nameEn: String = ""
    var icon: String? = nil
    var color: String? = nil
    var parentId: String? = nil
    var displayOrder: Int = 0
    var isActive: Bool = true
    var image: String? = nil
    /// Clé JSON `_count`.
    var count: CountDTO? = nil
    var children: [CategoryDTO] = []
}

nonisolated extension CategoryDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        slug = try container.requiredString("slug")
        nameFr = try container.requiredString("nameFr")
        nameAr = container.lenientString("nameAr") ?? ""
        nameEn = container.lenientString("nameEn") ?? ""
        icon = container.lenientString("icon")
        color = container.lenientString("color")
        parentId = container.lenientString("parentId")
        displayOrder = container.lenientInt("displayOrder") ?? 0
        isActive = container.lenientBool("isActive") ?? true
        image = container.lenientString("image")
        count = container.lenientObject(CountDTO.self, "_count")
        children = container.lenientList(CategoryDTO.self, "children")
    }
}

nonisolated struct CountDTO: Decodable, Hashable, Sendable {
    var annonces: Int = 0
}

nonisolated extension CountDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        annonces = container.lenientInt("annonces") ?? 0
    }
}

nonisolated struct SuggestionsDTO: Decodable, Hashable, Sendable {
    var suggestions: [SuggestionDTO] = []
}

nonisolated extension SuggestionsDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        suggestions = container.lenientList(SuggestionDTO.self, "suggestions")
    }
}

/// `{ text, type: category|wilaya|listing, slug? (catégorie), id? (wilaya) }`.
nonisolated struct SuggestionDTO: Decodable, Hashable, Sendable {
    var text: String
    var type: String
    var slug: String? = nil
    var id: Int? = nil
}

nonisolated extension SuggestionDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        text = try container.requiredString("text")
        type = try container.requiredString("type")
        slug = container.lenientString("slug")
        id = container.lenientInt("id")
    }
}
