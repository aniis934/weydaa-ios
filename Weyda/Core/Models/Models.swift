import Foundation

// Portage de model/Models.kt (app Android) : types du domaine, indépendants de l'API et de l'interface.
// Tous `nonisolated` (le projet isole par défaut sur le MainActor) : utilisables depuis le réseau, le
// décodage et les vues. Propriétés en `var` = le `copy()` des data classes Kotlin
// (`var copie = annonce; copie.slug = "…"`). Initialiseurs : ceux, membre à membre, générés par Swift
// (valeurs par défaut = celles d'Android). `OfferRules` est porté à part (agent UTILS).

/* ───────── Aides texte (équivalents Kotlin) ───────── */

/// Équivalents de `isBlank`, `isNullOrBlank`, `takeIf { it.isNotBlank() }` et `ifBlank { }` de Kotlin,
/// regroupés dans un espace de noms plutôt qu'en extensions de `String` (aucune collision possible avec
/// une extension d'un autre fichier du module).
nonisolated enum TextCheck {
    /// Vide ou fait de blancs (`isBlank`) ; `nil` compte comme blanc (`isNullOrBlank`).
    static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.allSatisfy { $0.isWhitespace }
    }

    /// La valeur si elle n'est pas blanche, sinon `nil` (`takeIf { it.isNotBlank() }`).
    static func nonBlank(_ value: String?) -> String? {
        isBlank(value) ? nil : value
    }

    /// La valeur, ou le repli si elle est blanche (`ifBlank { repli }`).
    static func ifBlank(_ value: String, _ fallback: @autoclosure () -> String) -> String {
        isBlank(value) ? fallback() : value
    }
}

/* ───────── Annonces ───────── */

/// Nom traduit fr/ar/en, résolu selon la langue de l'app (`ar` / `en` vides → repli sur le français).
nonisolated struct LocalizedName: Hashable, Codable, Sendable {
    let fr: String
    let ar: String
    let en: String

    /// `ar` / `en` absents = le français, comme les défauts du constructeur Kotlin (`ar: String = fr`).
    init(fr: String, ar: String? = nil, en: String? = nil) {
        self.fr = fr
        self.ar = ar ?? fr
        self.en = en ?? fr
    }

    func resolve(_ language: String = WeydaLocale.language) -> String {
        switch language {
        case "ar": return TextCheck.ifBlank(ar, fr)
        case "en": return TextCheck.ifBlank(en, fr)
        default: return fr
        }
    }
}

nonisolated extension LocalizedName {
    // Lecture tolérante (cache local) : `ar` / `en` absents → le français.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        let french = try container.requiredString("fr")
        self.init(fr: french, ar: container.lenientString("ar"), en: container.lenientString("en"))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DTOKey.self)
        try container.encode(fr, forKey: "fr")
        try container.encode(ar, forKey: "ar")
        try container.encode(en, forKey: "en")
    }
}

nonisolated enum PriceType: String, CaseIterable, Codable, Sendable {
    case fixed = "FIXED"
    case negotiable = "NEGOTIABLE"
    case free = "FREE"

    /// Valeur inconnue ou absente → prix fixe (comme Android).
    static func from(_ raw: String?) -> PriceType {
        allCases.first { $0.rawValue == raw } ?? .fixed
    }
}

nonisolated enum ListingStatus: String, CaseIterable, Codable, Sendable {
    case pending = "PENDING"
    case active = "ACTIVE"
    case sold = "SOLD"
    case expired = "EXPIRED"
    case rejected = "REJECTED"

    /// Valeur inconnue ou absente → active (comme Android).
    static func from(_ raw: String?) -> ListingStatus {
        allCases.first { $0.rawValue == raw } ?? .active
    }
}

/// Verdict de modération IA (uniquement sur « mes annonces »).
nonisolated struct ModerationVerdict: Hashable, Sendable {
    var decision: String
    var confidence: Double?
    var reasons: [String]
    var suggestions: String?
}

nonisolated struct Seller: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var avatarUrl: String?
    var memberSince: Date?
    var isRecommended: Bool = false
    var emailVerified: Bool = false
    var ratingCount: Int = 0
    var ratingSum: Int = 0
    var responseMinutes: Int? = nil
    var activeListings: Int = 0
    /// Présentation libre, servie par le profil public seulement.
    var bio: String? = nil

    /// Note moyenne sur 5, `nil` sans avis.
    var rating: Double? {
        ratingCount > 0 ? Double(ratingSum) / Double(ratingCount) : nil
    }

    /// Badge « répond vite » du site : temps de réponse médian ≤ 60 min.
    var isFastResponder: Bool {
        guard let responseMinutes else { return false }
        return responseMinutes <= 60
    }
}

nonisolated struct Listing: Hashable, Sendable, Identifiable {
    var id: String
    var slug: String?
    var title: String
    var description: String
    var price: Double?
    var priceType: PriceType
    var status: String
    var views: Int
    var isFeatured: Bool
    var phone: String?
    var createdAt: Date?
    var images: [String]
    var category: LocalizedName?
    var categorySlug: String?
    var wilaya: LocalizedName?
    var commune: LocalizedName?
    var seller: Seller?
    var attributes: [String: String]
    var expiresAt: Date? = nil
    var renewalCount: Int = 0
    var parentCategorySlug: String? = nil
    var moderation: ModerationVerdict? = nil
    /// Images avec `publicId` (édition : PUT images = remplacement intégral).
    var imageRefs: [UploadedImage] = []
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    /// Le vendeur affiche un numéro (révélé à la demande, connexion requise).
    var hasPhone: Bool = false
    /// Identifiant du vendeur (`userId` de l'API, présent même quand `user` n'est pas inclus) : « Voir le vendeur » du
    /// menu d'appui long.
    var sellerId: String? = nil

    static let maxRenewals = 3

    var coverImage: String? { images.first }

    /// Miniature 400 px de la photo principale (vignettes des listes) ; repli sur `coverImage` si absente.
    var coverThumbnail: String? {
        coverImage.map { thumbnailUrl($0) }
    }

    var listingStatus: ListingStatus { ListingStatus.from(status) }

    /// Renouvellements restants (PATCH renew) : 3 au maximum.
    var renewalsLeft: Int {
        Swift.max(Self.maxRenewals - renewalCount, 0)
    }

    /// Renouvelable : expirée, ou active et expirant sous 7 jours. Le statut compte : `expiresAt` court aussi
    /// sur une annonce refusée, en attente ou vendue, et « Renouveler » la remettrait en ligne (le serveur
    /// applique la même règle).
    func isRenewable(now: Date = Date()) -> Bool {
        let current = listingStatus
        if current == .expired { return true }
        guard current == .active, let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(7 * 24 * 3600)
    }

    /// URL web de l'annonce (partage), comme `ListingCard.tsx` : l'URL SEO `/{locale}/{catégorie}/{slug}`
    /// quand les deux sont connus, sinon `/{locale}/annonce/{id}` — un repli `/annonces/{id}` ne correspond à
    /// aucune page du site (lien partagé en 404).
    func webUrl(host: String, locale: String = "fr") -> String {
        var trimmedHost = host
        while trimmedHost.hasSuffix("/") {
            trimmedHost.removeLast()
        }
        let base = "\(trimmedHost)/\(locale)"
        if let slug, let categorySlug, !TextCheck.isBlank(slug), !TextCheck.isBlank(categorySlug) {
            return "\(base)/\(categorySlug)/\(slug)"
        }
        return "\(base)/annonce/\(id)"
    }
}

nonisolated struct ListingPage: Hashable, Sendable {
    var items: [Listing]
    var total: Int
    var page: Int
    var totalPages: Int
    var facets: [String: [FacetValue]] = [:]

    var hasMore: Bool { page < totalPages }
}

nonisolated enum SuggestionType: String, CaseIterable, Sendable {
    case category = "CATEGORY"
    case wilaya = "WILAYA"
    case listing = "LISTING"

    /// Insensible à la casse (le serveur envoie `category`, `wilaya`, `listing`) ; inconnu → annonce.
    static func from(_ raw: String?) -> SuggestionType {
        guard let raw else { return .listing }
        let upper = raw.uppercased()
        return allCases.first { $0.rawValue == upper } ?? .listing
    }
}

nonisolated struct Review: Hashable, Sendable, Identifiable {
    var id: String
    var rating: Int
    var comment: String?
    var createdAt: Date?
    var authorName: String?
    var authorAvatar: String?
}

/// Avis d'un vendeur (première page) + note moyenne calculée par le serveur sur tous les avis.
nonisolated struct ReviewSummary: Hashable, Sendable {
    var reviews: [Review]
    var total: Int
    var ratingCount: Int
    var average: Double
}

/// Mon avis sur un vendeur, tel que le serveur me le renvoie (`existingReview`).
nonisolated struct MyReview: Hashable, Sendable {
    var rating: Int
    var comment: String?

    /// Longueur maximale du commentaire acceptée par `reviewSchema` (Zod).
    static let commentMax = 1000
}

/// Réponse de `GET /api/reviews/eligibility` : droit de noter + avis déjà déposé.
nonisolated struct ReviewEligibility: Hashable, Sendable {
    var canReview: Bool
    var existing: MyReview?
}

/// Recherche sauvegardée (alerte) : nom composé par le serveur, `params` = clés d'URL du site.
nonisolated struct SavedSearch: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var params: [String: String]
    var createdAt: Date?
}

/// Suggestion de `GET /api/search/suggestions` : `slug` pour une catégorie, `id` pour une wilaya.
nonisolated struct Suggestion: Hashable, Sendable {
    var text: String
    var type: SuggestionType
    var slug: String? = nil
    var id: Int? = nil
}

/// Valeur d'attribut et nombre d'annonces correspondantes (facettes de recherche).
nonisolated struct FacetValue: Hashable, Sendable {
    var value: String
    var count: Int
}

nonisolated struct Category: Hashable, Sendable, Identifiable {
    var id: String
    var slug: String
    var name: LocalizedName
    /// Emoji du serveur : ne pas l'afficher, utiliser `CategoryIcon.assetName(forSlug:)`.
    var icon: String?
    var color: String?
    var listingsCount: Int
    var children: [Category]
}

/* ───────── Catalogue : attributs dynamiques, sous-catégories, géographie ───────── */

nonisolated enum AttributeType: String, CaseIterable, Codable, Sendable {
    case select = "SELECT"
    case number = "NUMBER"
    case boolean = "BOOLEAN"
    case text = "TEXT"

    /// Insensible à la casse (le serveur envoie `select`, `number`…) ; inconnu → texte libre.
    static func from(_ raw: String?) -> AttributeType {
        guard let raw else { return .text }
        let upper = raw.uppercased()
        return allCases.first { $0.rawValue == upper } ?? .text
    }
}

nonisolated enum Requirement: String, CaseIterable, Codable, Sendable {
    case `required` = "REQUIRED"
    case recommended = "RECOMMENDED"
    case `optional` = "OPTIONAL"

    /// Insensible à la casse (le serveur envoie `required`…) ; inconnu → facultatif.
    static func from(_ raw: String?) -> Requirement {
        guard let raw else { return .optional }
        let upper = raw.uppercased()
        return allCases.first { $0.rawValue == upper } ?? .optional
    }
}

/// Option d'un select : clé technique envoyée à l'API + libellé déjà traduit par le serveur.
nonisolated struct AttributeOption: Hashable, Sendable {
    let value: String
    let label: String
}

/// Définition d'un attribut de catégorie (miroir de `AttributeDefinition` côté serveur), libellés résolus pour
/// la langue demandée. `options` est vide pour un select dépendant tant que son parent (`dependsOn`) n'a pas
/// de valeur : recharger avec le contexte (`ctx_<clé>=<valeur>`).
nonisolated struct AttributeDefinition: Hashable, Sendable {
    var key: String
    var label: String
    var type: AttributeType
    var requirement: Requirement
    var options: [AttributeOption] = []
    var dependsOn: String? = nil
    var min: Double? = nil
    var max: Double? = nil
    var step: Double? = nil
    var unit: String? = nil
    var unitLabel: String? = nil
    var rangePresets: [Double] = []
    var filterable: Bool = false
    var filterType: String = "exact"

    var isRequired: Bool { requirement == .required }
    var isDependent: Bool { dependsOn != nil }

    /// Libellé d'une option ; repli = capitalisation de la clé technique (`classe-a` → « Classe A »), comme le web.
    func optionLabel(_ value: String) -> String {
        options.first { $0.value == value }?.label ?? Self.displayLabel(value)
    }

    /// Repli de libellé identique au serveur sans i18n : `tiret-mots` → « Tiret Mots » (seul le tiret sépare).
    static func displayLabel(_ key: String) -> String {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        let words: [String] = parts.map { (part: Substring) -> String in
            part.prefix(1).uppercased() + String(part.dropFirst())
        }
        return words.joined(separator: " ")
    }
}

nonisolated struct Subcategory: Hashable, Sendable {
    var slug: String
    var parentSlug: String
    var name: LocalizedName
}

/// Réponse complète de `/api/categories/{slug}/attributes` pour une catégorie racine (+ sous-catégorie).
nonisolated struct AttributeSet: Hashable, Sendable {
    var attributes: [AttributeDefinition] = []
    var subcategories: [Subcategory] = []

    var isEmpty: Bool { attributes.isEmpty && subcategories.isEmpty }

    func attribute(_ key: String) -> AttributeDefinition? {
        attributes.first { $0.key == key }
    }
}

/// `listingsCount` n'est renseigné que par le classement `GET /api/wilayas?top=` (accueil).
nonisolated struct Wilaya: Hashable, Sendable, Identifiable {
    var id: Int
    var name: LocalizedName
    var listingsCount: Int = 0
}

/// Valeur saisie pour un attribut, avec son type (encodage JSON typé pour l'API).
nonisolated struct AttributeValue: Hashable, Sendable {
    var type: AttributeType
    var raw: String
}

/// Annonce à créer (POST /api/annonces) ou à modifier : champs de l'assistant validés localement.
nonisolated struct ListingSubmission: Hashable, Sendable {
    var title: String
    var description: String
    var price: Double?
    var priceType: PriceType
    var categoryId: String
    var subcategorySlug: String? = nil
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    /// Téléphone du profil si « afficher mon numéro », sinon `nil` (absent du JSON).
    var phone: String? = nil
    var images: [UploadedImage] = []
    var attributes: [String: AttributeValue] = [:]
}

/// Image envoyée sur le stockage (POST /api/upload) ; `url` + `publicId` sont attendus par POST /api/annonces.
nonisolated struct UploadedImage: Hashable, Sendable {
    var url: String
    var thumbnailUrl: String?
    var publicId: String
}

nonisolated struct Commune: Hashable, Sendable, Identifiable {
    var id: Int
    var wilayaId: Int
    var name: LocalizedName
}

nonisolated struct ListingQuery: Hashable, Sendable {
    var q: String? = nil
    var category: String? = nil
    var subcategory: String? = nil
    var wilaya: Int? = nil
    var commune: Int? = nil
    var priceType: PriceType? = nil
    var priceMin: Double? = nil
    var priceMax: Double? = nil
    var sort: String? = nil
    var featured: Bool = false
    var page: Int = 1
    var limit: Int = 24
    /// Filtres d'attributs `attr_<clé>=valeur` (plages : `<clé>_min` / `<clé>_max`).
    var attributes: [String: String] = [:]
    var withFacets: Bool = false
}

/// Filtres de l'écran Annonces (feuille de filtres + puces actives), indépendants de la catégorie choisie.
nonisolated struct ListingFilters: Hashable, Sendable {
    var subcategory: String? = nil
    var wilayaId: Int? = nil
    var communeId: Int? = nil
    var priceType: PriceType? = nil
    var priceMin: String = ""
    var priceMax: String = ""
    /// `nil` = tri par défaut du serveur (newest, relevance avec un mot-clé).
    var sort: String? = nil
    var attributes: [String: String] = [:]
    /// « Annonces à la une seulement » (`featured=1`), comme l'interrupteur du site.
    var featuredOnly: Bool = false

    var activeCount: Int {
        let flags: [Bool] = [
            subcategory != nil,
            wilayaId != nil,
            communeId != nil,
            priceType != nil,
            !TextCheck.isBlank(priceMin),
            !TextCheck.isBlank(priceMax),
            sort != nil,
            featuredOnly,
        ]
        return flags.filter { $0 }.count + attributes.count
    }
}

/* ───────── Session ───────── */

/// Utilisateur connecté. `Codable` : c'est aussi le format de stockage local (pas de `StoredUserDto` sur iOS).
nonisolated struct User: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var name: String?
    var email: String
    var avatarUrl: String?
    var role: String
    var emailVerified: Bool
    var phone: String? = nil
    var phoneCountryCode: String? = nil
    var bio: String? = nil
    var isRecommended: Bool = false
    var memberSince: Date? = nil
    /// Faux pour un compte créé avec Google (lu sur `/users/me`).
    var hasPassword: Bool = true

    var displayName: String {
        if let name, !TextCheck.isBlank(name) { return name }
        guard let at = email.firstIndex(of: "@") else { return email }
        return String(email[..<at])
    }

    var isStaff: Bool { role == "ADMIN" || role == "MODERATOR" }

    /// Nombre max de photos par annonce (5, 8 pour les vendeurs recommandés).
    var maxImages: Int { isRecommended ? 8 : 5 }
}

nonisolated extension User {
    // Stockage local tolérant (défauts de `StoredUserDto` Android). Date en secondes depuis la date de
    // référence d'Apple (aller-retour exact, indépendant de la stratégie de dates de l'encodeur) ; une date
    // ISO 8601 est aussi acceptée en lecture.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        name = container.lenientString("name")
        email = container.lenientString("email") ?? ""
        avatarUrl = container.lenientString("avatarUrl")
        role = container.lenientString("role") ?? "USER"
        emailVerified = container.lenientBool("emailVerified") ?? false
        phone = container.lenientString("phone")
        phoneCountryCode = container.lenientString("phoneCountryCode")
        bio = container.lenientString("bio")
        isRecommended = container.lenientBool("isRecommended") ?? false
        memberSince = container.lenientStoredDate("memberSince")
        hasPassword = container.lenientBool("hasPassword") ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DTOKey.self)
        try container.encode(id, forKey: "id")
        try container.encodeIfPresent(name, forKey: "name")
        try container.encode(email, forKey: "email")
        try container.encodeIfPresent(avatarUrl, forKey: "avatarUrl")
        try container.encode(role, forKey: "role")
        try container.encode(emailVerified, forKey: "emailVerified")
        try container.encodeIfPresent(phone, forKey: "phone")
        try container.encodeIfPresent(phoneCountryCode, forKey: "phoneCountryCode")
        try container.encodeIfPresent(bio, forKey: "bio")
        try container.encode(isRecommended, forKey: "isRecommended")
        try container.encodeIfPresent(memberSince?.timeIntervalSinceReferenceDate, forKey: "memberSince")
        try container.encode(hasPassword, forKey: "hasPassword")
    }
}

/// Jetons mobiles (`POST /api/auth/token`) : opaques, l'expiration vient de `expiresIn`.
nonisolated struct AuthTokens: Hashable, Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: Date
    var refreshExpiresAt: Date

    /// Vrai si le jeton d'accès expire dans moins de `seconds` (ou a expiré) : à rafraîchir avant l'appel.
    func isAccessExpiring(within seconds: TimeInterval, now: Date = Date()) -> Bool {
        accessExpiresAt <= now.addingTimeInterval(seconds)
    }

    func isRefreshExpired(now: Date = Date()) -> Bool {
        refreshExpiresAt <= now
    }
}

nonisolated extension AuthTokens {
    // Dates en secondes depuis la date de référence d'Apple (2001, comme `Date` elle-même) : aller-retour
    // exact, format indépendant de la stratégie de dates de l'encodeur.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        accessToken = try container.requiredString("accessToken")
        refreshToken = try container.requiredString("refreshToken")
        let accessSeconds = try container.requiredDouble("accessExpiresAt")
        let refreshSeconds = try container.requiredDouble("refreshExpiresAt")
        accessExpiresAt = Date(timeIntervalSinceReferenceDate: accessSeconds)
        refreshExpiresAt = Date(timeIntervalSinceReferenceDate: refreshSeconds)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DTOKey.self)
        try container.encode(accessToken, forKey: "accessToken")
        try container.encode(refreshToken, forKey: "refreshToken")
        try container.encode(accessExpiresAt.timeIntervalSinceReferenceDate, forKey: "accessExpiresAt")
        try container.encode(refreshExpiresAt.timeIntervalSinceReferenceDate, forKey: "refreshExpiresAt")
    }
}

nonisolated struct UserStats: Hashable, Sendable {
    var totalViews: Int
    var activeCount: Int
    var pendingCount: Int
    var soldCount: Int
    var expiredCount: Int
    var favoritesReceived: Int
    var messagesReceived: Int
}

/* ───────── Messagerie ───────── */

nonisolated enum MessageType: String, CaseIterable, Sendable {
    case text = "TEXT"
    case offer = "OFFER"

    /// Valeur inconnue ou absente → texte.
    static func from(_ raw: String?) -> MessageType {
        allCases.first { $0.rawValue == raw } ?? .text
    }
}

/// État d'une offre dans le fil (miroir de `OfferKind`, src/lib/offers.ts).
nonisolated enum OfferKind: String, CaseIterable, Sendable {
    case new = "NEW"
    case counter = "COUNTER"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"

    /// Une offre NEW ou COUNTER attend une réponse : c'est elle qui porte les boutons d'action.
    var isOpen: Bool { self == .new || self == .counter }

    /// `nil` si inconnue (l'offre est alors ignorée, comme sur Android).
    static func from(_ raw: String?) -> OfferKind? {
        allCases.first { $0.rawValue == raw }
    }
}

/// Action d'offre envoyée au serveur (`POST /api/conversations/{id}/offers`) ; `rawValue` = valeur « fil ».
nonisolated enum OfferAction: String, CaseIterable, Sendable {
    case new = "new"
    case counter = "counter"
    case accept = "accept"
    case decline = "decline"

    var wire: String { rawValue }

    var needsAmount: Bool { self == .new || self == .counter }
}

/// `metadata` d'un message de type OFFER : montant en dinars.
nonisolated struct OfferMeta: Hashable, Sendable {
    var kind: OfferKind
    var amount: Double
}

nonisolated struct ChatMessage: Hashable, Sendable, Identifiable {
    var id: String
    var conversationId: String
    var senderId: String
    var content: String
    var createdAt: Date?
    var readAt: Date?
    var deletedAt: Date?
    var type: MessageType = .text
    /// Non nul seulement pour un message OFFER dont `metadata` est exploitable.
    var offer: OfferMeta? = nil

    /// Fenêtre de suppression du serveur (5 min) et marge d'écart d'horloge téléphone / serveur (2 min).
    static let deleteWindowSeconds: TimeInterval = 5 * 60
    static let clockSkewToleranceSeconds: TimeInterval = 2 * 60

    var isDeleted: Bool { deletedAt != nil }

    func isMine(_ userId: String) -> Bool { senderId == userId }

    /// Suppression possible : mon message, non supprimé, dans la fenêtre serveur de 5 minutes. `createdAt` vient
    /// de l'horloge du SERVEUR et `now` de celle du téléphone : une marge absorbe leur écart, sinon un téléphone
    /// en avance refusait de supprimer un message tout juste envoyé. Le serveur tranche de toute façon
    /// (403 `deletionWindowExpired`).
    func isDeletableBy(_ userId: String, now: Date = Date()) -> Bool {
        guard senderId == userId, deletedAt == nil, let createdAt else { return false }
        let limit = now.addingTimeInterval(-(Self.deleteWindowSeconds + Self.clockSkewToleranceSeconds))
        return createdAt > limit
    }
}

/// Aperçu du dernier message d'une conversation (la liste ne renvoie ni id ni type).
nonisolated struct LastMessage: Hashable, Sendable {
    var content: String
    var createdAt: Date?
    var senderId: String
    var readAt: Date?
    var isDeleted: Bool
}

nonisolated struct ConversationPartner: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var avatarUrl: String?
}

/// Annonce rattachée à la conversation ; `status` / `price` / `priceType` seulement dans le détail.
nonisolated struct ConversationAnnonce: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var imageUrl: String?
    var status: ListingStatus? = nil
    var price: Double? = nil
    var priceType: PriceType? = nil

    /// Le serveur refuse new / counter / accept hors annonce ACTIVE et sur une annonce gratuite.
    var acceptsOffers: Bool { status == .active && priceType != .free }
}

nonisolated struct Conversation: Hashable, Sendable, Identifiable {
    var id: String
    var annonceId: String
    var annonce: ConversationAnnonce?
    var buyer: ConversationPartner
    var seller: ConversationPartner
    var updatedAt: Date?
    var lastMessage: LastMessage? = nil
    /// Canal Realtime signé (`conv:{id}:{hmac}`), non calculable côté client.
    var topic: String = ""

    func partner(_ userId: String) -> ConversationPartner {
        buyer.id == userId ? seller : buyer
    }

    func isSeller(_ userId: String) -> Bool { seller.id == userId }

    /// Non lue : le dernier message vient de l'autre partie et n'a pas de `readAt`.
    func isUnreadFor(_ userId: String) -> Bool {
        guard let lastMessage else { return false }
        return lastMessage.senderId != userId && lastMessage.readAt == nil
    }

    /// Recherche de la liste (comme le site) : nom de l'interlocuteur, titre de l'annonce, dernier message.
    /// Insensible à la casse et aux accents (« electro » trouve « Électroménager »).
    func matches(query: String, userId: String) -> Bool {
        let needle = query.foldedForSearch()
        if TextCheck.isBlank(needle) { return true }
        var haystacks: [String] = [partner(userId).name]
        if let title = annonce?.title { haystacks.append(title) }
        if let content = lastMessage?.content { haystacks.append(content) }
        return haystacks.contains { $0.foldedForSearch().contains(needle) }
    }
}

nonisolated extension String {
    /// Minuscules sans diacritiques (é → e, ç → c) pour les recherches locales, comme `foldForSearch` Android :
    /// minuscules, blancs de bord retirés, décomposition NFD, puis suppression des marques non espaçantes (Mn).
    /// Les lettres arabes restent (seuls leurs signes diacritiques, des Mn, disparaissent, comme sur Android).
    func foldedForSearch() -> String {
        let decomposed = lowercased().trimmingCharacters(in: .whitespacesAndNewlines).decomposedStringWithCanonicalMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars)
    }
}

/// Page de la liste des conversations (curseur : `nextCursor` nil = fin).
nonisolated struct ConversationPage: Hashable, Sendable {
    var items: [Conversation]
    var nextCursor: String?
}

/// Conversation ouverte : messages en ordre croissant, pagination vers le passé.
nonisolated struct ChatThread: Hashable, Sendable {
    var conversation: Conversation
    var messages: [ChatMessage]
    var hasMore: Bool
    var nextCursor: String?
    /// J'ai bloqué l'interlocuteur.
    var isBlockedByMe: Bool = false
}

/// Utilisateur que J'AI bloqué (écran « Utilisateurs bloqués », App Store 1.2) ; `name` nil = compte supprimé.
nonisolated struct BlockedUser: Hashable, Sendable, Identifiable {
    var id: String
    var name: String?
    var avatarUrl: String?
    var blockedAt: Date?
}

nonisolated struct BlockedUsersPage: Hashable, Sendable {
    var items: [BlockedUser]
    var total: Int
    var page: Int
    var totalPages: Int

    var hasMore: Bool { page < totalPages }
}

/* ───────── Notifications in-app ───────── */

/// Miroir de `NotificationType` (prisma/schema.prisma) ; `unknown` = type ajouté côté serveur.
nonisolated enum NotificationKind: String, CaseIterable, Sendable {
    case message = "MESSAGE"
    case review = "REVIEW"
    case annonceApproved = "ANNONCE_APPROVED"
    case annonceRejected = "ANNONCE_REJECTED"
    case annonceExpired = "ANNONCE_EXPIRED"
    case offerReceived = "OFFER_RECEIVED"
    case offerAccepted = "OFFER_ACCEPTED"
    case offerRejected = "OFFER_REJECTED"
    case offerCounter = "OFFER_COUNTER"
    case favoritePriceDrop = "FAVORITE_PRICE_DROP"
    case favoriteSold = "FAVORITE_SOLD"
    case searchAlert = "SEARCH_ALERT"
    case unknown = "UNKNOWN"

    static func from(_ raw: String?) -> NotificationKind {
        allCases.first { $0.rawValue == raw } ?? .unknown
    }
}

/// Écran à ouvrir quand on touche une notification (déduit de son `url` côté site).
nonisolated enum NotificationTarget: Hashable, Sendable {
    case listing(idOrSlug: String)
    case conversation(id: String)
    /// Profil public (notification d'avis reçu).
    case seller(id: String)
    /// « Mes annonces » (annonce approuvée / refusée / expirée).
    case myListings
}

nonisolated struct AppNotification: Hashable, Sendable, Identifiable {
    var id: String
    var kind: NotificationKind
    var title: String
    var body: String
    var url: String?
    var read: Bool
    var createdAt: Date?

    /// `/annonce/{idOuSlug}` → détail (l'API accepte l'un ou l'autre) ; `/dashboard/messages/{id}` → fil ;
    /// `/profil/{id}` → profil du vendeur (avis) ; `/dashboard/annonces` → Mes annonces. Préfixe de langue toléré.
    var target: NotificationTarget? {
        guard let url else { return nil }
        let path = url.firstIndex(of: "?").map { String(url[..<$0]) } ?? url
        let raw: [String] = path.split(separator: "/")
            .map { String($0) }
            .filter { !TextCheck.isBlank($0) }
        let hasLanguage = raw.first.map { ["fr", "ar", "en"].contains($0) } ?? false
        let segments = hasLanguage ? Array(raw.dropFirst()) : raw
        if segments.count >= 2 && segments[0] == "annonce" {
            return .listing(idOrSlug: segments[1])
        }
        if segments.count >= 3 && segments[0] == "dashboard" && segments[1] == "messages" {
            return .conversation(id: segments[2])
        }
        if segments.count >= 2 && segments[0] == "profil" {
            return .seller(id: segments[1])
        }
        if segments == ["dashboard", "annonces"] {
            return .myListings
        }
        return nil
    }
}

nonisolated struct NotificationPage: Hashable, Sendable {
    var items: [AppNotification]
    var unreadCount: Int
    var total: Int
    var page: Int
    var totalPages: Int
    /// Canal Realtime personnel signé, à écouter pour la cloche et les badges.
    var topic: String

    var hasMore: Bool { page < totalPages }
}

/// Motif d'un signalement — miroir de l'enum `ReportReason` (prisma/schema.prisma), dans l'ordre proposé
/// par le site (`report.reasons.*`).
nonisolated enum ReportReason: String, CaseIterable, Codable, Sendable {
    case spam = "SPAM"
    case inappropriate = "INAPPROPRIATE"
    case fraud = "FRAUD"
    case duplicate = "DUPLICATE"
    case other = "OTHER"

    /// Longueur maximale de `details` acceptée par `reportSchema` (Zod).
    static let detailsMax = 1000
}

/// Miniature d'une image du stockage : `{uuid}.webp` → `{uuid}_thumb.webp` (400 px, créée à chaque envoi —
/// même convention que `getThumbnailUrl` du site) ; toute autre URL est rendue telle quelle. Fonction libre
/// comme sur Android ; depuis un type qui a lui-même une propriété `thumbnailUrl`, écrire `Weyda.thumbnailUrl(_:)`.
nonisolated func thumbnailUrl(_ url: String) -> String {
    guard url.hasSuffix(".webp"), !url.hasSuffix("_thumb.webp") else { return url }
    return String(url.dropLast(".webp".count)) + "_thumb.webp"
}
