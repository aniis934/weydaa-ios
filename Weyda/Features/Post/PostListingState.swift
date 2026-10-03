import Foundation

// Portage de ui/post/PostListingViewModel.kt (Android) : types de l'assistant « Déposer une annonce ».
// Tout est `nonisolated` (données pures) : l'état se copie, se compare et se teste hors du fil principal.
// Les `@StringRes Int?` d'Android deviennent des `String?` DÉJÀ traduits (`ValidationMessage.text`, `ErrorMapper`).

/// Étapes de l'assistant, dans l'ordre du site (PostAdWizard) ; `.attributes` seulement si la catégorie en a.
nonisolated enum PostStep: String, CaseIterable, Codable, Sendable {
    case category = "CATEGORY"
    case attributes = "ATTRIBUTES"
    case details = "DETAILS"
    case photos = "PHOTOS"
    case location = "LOCATION"
    case review = "REVIEW"
}

nonisolated enum PhotoStatus: String, Codable, Sendable {
    case uploading = "UPLOADING"
    case done = "DONE"
    case failed = "FAILED"
}

/// Photo du formulaire : fichier local (aperçu immédiat) puis résultat d'envoi (aperçu distant, repris par le
/// brouillon). Android : `PhotoItem(localUri, upload, status, errorRes)`.
nonisolated struct PhotoItem: Hashable, Sendable, Identifiable {
    /// Nom du fichier local (PostPhotoStore) ; pour une photo déjà en ligne (édition) : son URL distante.
    var localRef: String
    var upload: UploadedImage? = nil
    var status: PhotoStatus = .uploading
    /// Échec d'envoi, déjà traduit (Android : `errorRes`).
    var errorMessage: String? = nil

    var id: String { localRef }

    /// Aperçu distant (miniature si fournie, sinon l'image) une fois envoyée ; nil → aperçu local.
    /// Android : `displayUrl = upload?.thumbnailUrl ?: upload?.url ?: localUri`.
    var remoteURL: URL? {
        guard let upload else { return nil }
        return URL(string: TextCheck.nonBlank(upload.thumbnailUrl) ?? upload.url)
    }
}

/// État de l'assistant — portage de `PostListingUiState` (mêmes champs, mêmes règles calculées).
nonisolated struct PostListingState: Equatable, Sendable {
    /// Longueurs de `annonceSchema` (compteurs de l'écran) — `TITLE_MAX` / `DESCRIPTION_MAX` d'Android.
    static let titleMax = 100
    static let descriptionMax = 5000

    /* Catégorie */
    var categories: [Category] = []
    var categoriesLoading = true
    var categoriesError = false
    var parentCategoryId: String? = nil
    var subcategoryId: String? = nil
    var categoryError: String? = nil

    /* Attributs dynamiques */
    var attributeSet: AttributeSet? = nil
    var attributesLoading = false
    /// Le chargement des attributs a échoué : `attributeSet` reste nil. Le prendre pour « catégorie sans attributs »
    /// faisait disparaître l'étape, et l'annonce (véhicule, immobilier…) partait sans ses champs obligatoires — le
    /// serveur ne valide les attributs que s'ils sont présents.
    var attributesError = false
    var attributeValues: [String: String] = [:]
    var attributeErrors: [String: String] = [:]
    /// Options des selects dépendants chargées avec le contexte courant (clé → options).
    var dependentOptions: [String: [AttributeOption]] = [:]

    /* Infos & prix */
    var title = ""
    var description = ""
    var priceType: PriceType = .fixed
    var price = ""
    var titleError: String? = nil
    var descriptionError: String? = nil
    var priceError: String? = nil

    /* Photos */
    var photos: [PhotoItem] = []
    /// 5, ou 8 pour un vendeur recommandé (`User.maxImages`, relu sur /users/me).
    var maxPhotos = 5
    /// Message transitoire de l'étape photos (limite atteinte…), effacé par `photosNoticeShown()`.
    var photosNotice: String? = nil

    /* Localisation + téléphone */
    var wilayas: [Wilaya] = []
    var wilayaId: Int? = nil
    var communes: [Commune] = []
    var communesLoading = false
    var communeId: Int? = nil
    /// Téléphone du profil ; voir `contactPhone`.
    var userPhone: String? = nil
    /// Édition : numéro de contact DÉJÀ porté par l'annonce. Il peut différer de celui du profil (un fixe est accepté
    /// sur une annonce, pas sur un profil) : une simple retouche du titre ne doit pas le remplacer.
    var listingPhone: String? = nil
    var showPhone = false

    /* Navigation / soumission */
    var step: PostStep = .category
    var isSubmitting = false
    var errorMessage: String? = nil
    /// Annonce créée ou mise à jour (écran résultat) ; nil tant que le formulaire est en cours.
    var result: Listing? = nil

    /* Édition (PUT) */
    var editingId: String? = nil
    var editLoading = false
    var editError: String? = nil
    /// L'utilisateur a saisi ou modifié quelque chose (édition : confirmation avant d'abandonner).
    var isDirty = false
    /// E-mail du compte vérifié : sinon le serveur refuse photos et publication (bandeau « Vérifier »).
    var emailVerified = true

    // MARK: - Règles calculées (identiques à Android)

    var isEditing: Bool { editingId != nil }

    var parentCategory: Category? {
        categories.first { $0.id == parentCategoryId }
    }

    var subcategories: [Category] { parentCategory?.children ?? [] }

    var needsSubcategory: Bool { !subcategories.isEmpty }

    var subcategory: Category? {
        subcategories.first { $0.id == subcategoryId }
    }

    /// `categoryId` envoyé à l'API : la sous-catégorie si la racine en a, sinon la racine.
    var categoryId: String? { needsSubcategory ? subcategoryId : parentCategoryId }

    var isCategoryComplete: Bool { categoryId != nil }

    var hasAttributes: Bool { !(attributeSet?.attributes.isEmpty ?? true) }

    var steps: [PostStep] {
        var list: [PostStep] = [.category]
        if hasAttributes { list.append(.attributes) }
        list.append(contentsOf: [.details, .photos, .location, .review])
        return list
    }

    var stepIndex: Int { Swift.max(steps.firstIndex(of: step) ?? 0, 0) }

    var isFirstStep: Bool { stepIndex == 0 }

    var isLastStep: Bool { step == .review }

    var isUploading: Bool { photos.contains { $0.status == .uploading } }

    var remainingPhotoSlots: Int { Swift.max(maxPhotos - photos.count, 0) }

    /// Images envoyées, dans l'ordre d'affichage (la première = principale).
    var uploadedImages: [UploadedImage] { photos.compactMap { $0.upload } }

    /// Numéro envoyé si « afficher mon numéro » ; nil = pas de bascule du tout.
    var contactPhone: String? { listingPhone ?? userPhone }

    /// « Suivant » / « Publier » : inactif pendant une soumission, un envoi (étape photos) et tant que catégories ou
    /// attributs se chargent — à TOUTE étape : un brouillon restauré sur le récapitulatif calculait sinon
    /// `categoryId` sur une liste de catégories encore vide et publiait sans les attributs saisis.
    var canGoNext: Bool {
        !isSubmitting && !categoriesLoading && !attributesLoading && !(step == .photos && isUploading)
    }

    var selectedWilaya: Wilaya? {
        wilayas.first { $0.id == wilayaId }
    }

    var selectedCommune: Commune? {
        communes.first { $0.id == communeId }
    }

    func optionsFor(_ definition: AttributeDefinition) -> [AttributeOption] {
        dependentOptions[definition.key] ?? definition.options
    }

    /// Un select dépendant reste désactivé tant que son parent n'a pas de valeur.
    func isAttributeEnabled(_ definition: AttributeDefinition) -> Bool {
        guard let parent = definition.dependsOn else { return true }
        return !TextCheck.isBlank(attributeValues[parent])
    }

    /// Corps de POST /api/annonces (valeurs déjà validées étape par étape) ; attributs vides omis.
    func toSubmission() -> ListingSubmission {
        var typed: [String: AttributeValue] = [:]
        for definition in attributeSet?.attributes ?? [] {
            if let value = attributeValues[definition.key], !TextCheck.isBlank(value) {
                typed[definition.key] = AttributeValue(type: definition.type, raw: value)
            }
        }
        let amount: Double? = priceType == .free ? nil : Double(price.replacingOccurrences(of: " ", with: ""))
        return ListingSubmission(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            price: amount,
            priceType: priceType,
            categoryId: categoryId ?? "",
            subcategorySlug: subcategory?.slug,
            wilayaId: wilayaId,
            communeId: communeId,
            phone: showPhone ? contactPhone : nil,
            images: uploadedImages,
            attributes: typed
        )
    }
}
