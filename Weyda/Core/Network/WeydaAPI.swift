import Foundation

/// Endpoints de l'API Weyda — portage de `data/remote/WeydaApi.kt` (Retrofit) : une méthode par route, mêmes
/// noms ; corps et réponses = DTO (`Weyda/Core/Network/DTO/`). Contrat complet : `docs/API-CONTRACT.md` (dépôt privé).
///
/// Implémenté par `LiveWeydaAPI` (client HTTP réel, `APIClient`) et, dans les tests, par `FakeWeydaAPI`.
/// Les repositories ne voient que ce protocole.
///
/// Pas de valeur par défaut ici : un protocole Swift ne peut pas en porter, et une surcharge « avec défauts » en
/// extension masquerait statiquement l'implémentation du type conforme. Les défauts de `WeydaApi.kt` (`page = 1`,
/// `limit = 24`, `locale = "fr"`…) sont passés explicitement par les repositories.
///
/// Routes d'authentification (`login`, `refresh`, `loginWithGoogle`, `loginWithApple`, `register`,
/// `forgotPassword`, `resetPassword`) : jamais de jeton Bearer (Android : `authApi`).
nonisolated protocol WeydaAPI: Sendable {
    // MARK: Public

    /// Liste / recherche. `sort` : newest | oldest | priceAsc | priceDesc | mostViewed | relevance ;
    /// `featured` / `withFacets` : 1 ou nil ; `attrs` : `attr_<clé>` → valeur (déjà préfixées).
    func getAnnonces(
        q: String?,
        category: String?,
        subcategory: String?,
        wilaya: Int?,
        commune: Int?,
        priceType: String?,
        priceMin: Double?,
        priceMax: Double?,
        sort: String?,
        featured: Int?,
        page: Int,
        limit: Int,
        locale: String?,
        withFacets: Int?,
        attrs: [String: String]
    ) async throws -> AnnoncesPageDTO

    /// Détail par id (cuid) OU par slug (liens profonds).
    func getAnnonce(idOrSlug: String) async throws -> AnnonceDTO

    /// Catégories racines (avec `children`), triées par `displayOrder`. Cache 1 h côté serveur.
    func getCategories() async throws -> [CategoryDTO]

    /// Les 58 wilayas.
    func getWilayas() async throws -> [WilayaDTO]

    /// Communes d'une wilaya, triées par nom FR. 400 `invalidWilayaId`.
    func getCommunes(wilayaId: Int) async throws -> [CommuneDTO]

    /// Wilayas les plus fournies en annonces actives, classées, avec `listingsCount` (1 ≤ top ≤ 20). Un serveur
    /// antérieur ignore `top` et renvoie les 58 wilayas : `GeoRepository` le détecte.
    func getTopWilayas(top: Int) async throws -> [WilayaDTO]

    /// Attributs d'une catégorie racine, filtrés par sous-catégorie, libellés selon `locale` ;
    /// `context` = `ctx_<clé>` → valeur (déjà préfixées) pour les selects dépendants.
    func getAttributes(slug: String, subcategory: String?, locale: String, context: [String: String]) async throws -> AttributesResponseDTO

    /// Profil public d'un vendeur. 404 `userNotFound` si le compte est banni ou supprimé.
    func publicProfile(id: String) async throws -> UserRefDTO

    /// Annonces actives d'un vendeur (page profil). `limit` 1–48.
    func publicAnnonces(id: String, page: Int, limit: Int) async throws -> AnnoncesPageDTO

    /// Avis reçus par un utilisateur (public). `limit` 1–50.
    func getReviews(targetId: String, page: Int, limit: Int) async throws -> ReviewsDTO

    /// Signaler une annonce ou un utilisateur (session + e-mail vérifié). 409 `alreadyReported`.
    func report(_ body: ReportRequestDTO) async throws -> ReportDTO

    /// Formulaire « Nous contacter » (session facultative, 3 envois / 15 min / IP).
    func contact(_ body: ContactRequestDTO) async throws -> SimpleResponseDTO

    /// Jeton push de l'appareil ↔ compte connecté (upsert par jeton).
    func registerFcmToken(_ body: FcmTokenRequestDTO) async throws -> SimpleResponseDTO

    /// Classement « Tendances » de l'accueil (vues des 7 derniers jours), cache CDN 5 min.
    func getTrending(limit: Int) async throws -> AnnonceListDTO

    /// « Pour vous » : d'après les favoris et alertes du compte connecté (vide pour un visiteur).
    func getRecommendations() async throws -> AnnonceListDTO

    /// Correction orthographique d'une recherche sans résultat.
    func didYouMean(q: String) async throws -> DidYouMeanDTO

    /// Langue du compte (e-mails, notifications) : suit la langue de l'application.
    func updateLocale(_ body: LocaleUpdateRequestDTO) async throws -> MeDTO

    /// Vue d'une fiche (une par IP et par annonce toutes les 30 min, jamais le propriétaire).
    func countView(id: String) async throws -> ViewCountDTO

    /// Puis-je noter ce vendeur ? Visiteur ou auto-avis → `canReview: false`, jamais d'erreur.
    func reviewEligibility(targetId: String) async throws -> ReviewEligibilityDTO

    /// Déposer ou modifier mon avis. 403 `notEligible` / `emailNotVerified` / `userBlocked`, 400 `ownReviewError`.
    func submitReview(_ body: ReviewCreateRequestDTO) async throws -> ReviewDTO

    /// Suggestions de recherche (≥ 2 caractères), jamais d'erreur (`{ suggestions: [] }`).
    func getSuggestions(q: String, locale: String) async throws -> SuggestionsDTO

    // MARK: Authentification (sans Bearer)

    func login(_ body: LoginRequestDTO) async throws -> TokenResponseDTO

    func refresh(_ body: RefreshRequestDTO) async throws -> TokenResponseDTO

    func loginWithGoogle(_ body: GoogleLoginRequestDTO) async throws -> TokenResponseDTO

    /// `POST api/auth/apple` — lot serveur A, pas encore déployé (404 `notFound` d'ici là).
    func loginWithApple(_ body: AppleLoginRequestDTO) async throws -> TokenResponseDTO

    func register(_ body: RegisterRequestDTO) async throws -> RegisterResponseDTO

    func forgotPassword(_ body: ForgotPasswordRequestDTO) async throws -> SimpleResponseDTO

    /// 400 `invalidOrExpiredLink` / `linkExpired`, 429 `tooManyAttempts`.
    func resetPassword(_ body: ResetPasswordRequestDTO) async throws -> SimpleResponseDTO

    /// Renvoi du code à 6 chiffres (session requise, délai 60 s, 5 / 24 h). Corps `{}`.
    func resendVerificationCode() async throws -> SimpleResponseDTO

    func confirmEmail(_ body: CodeRequestDTO) async throws -> SimpleResponseDTO

    // MARK: Compte

    func me() async throws -> MeDTO

    /// Ne renvoie que quelques champs (id, name, email, phone, phoneCountryCode, bio).
    func updateMe(_ body: UpdateProfileRequestDTO) async throws -> MeDTO

    /// Le serveur change `sessionVersion` : la session courante devient invalide.
    func changePassword(_ body: ChangePasswordRequestDTO) async throws -> SimpleResponseDTO

    func myStats() async throws -> UserStatsDTO

    /// Portabilité (loi 18-07) : le JSON complet, écrit dans `destination` (ou un fichier temporaire) ; renvoie
    /// son emplacement. 2 exports / 24 h (429 + `Retry-After`).
    func exportData(to destination: URL?) async throws -> URL

    /// Droit à l'effacement. 400 `incorrectPassword` / `accountDeletionNotAllowed`, 403 `adminAccountCannotBeDeleted`.
    func deleteAccount(_ body: DeleteAccountRequestDTO) async throws -> SimpleResponseDTO

    /// Création (201) ; statut PENDING sauf approbation IA → ACTIVE. 10 / 24 h.
    func createAnnonce(_ body: CreateAnnonceRequestDTO) async throws -> AnnonceDTO

    /// Mise à jour partielle (propriétaire) ; 400 `invalidAttributes` / `forbiddenTransition`, 404 `notFound`.
    func updateAnnonce(id: String, _ body: UpdateAnnonceRequestDTO) async throws -> AnnonceDTO

    /// Édition complète par l'assistant : `body` = `ListingSubmission.toUpdateBody()`, déjà encodé, avec des
    /// `null` EXPLICITES (le serveur ne touche qu'aux champs présents).
    func editAnnonce(id: String, body: Data) async throws -> AnnonceDTO

    /// Suppression douce (archive 30 j).
    func deleteAnnonce(id: String) async throws -> SimpleResponseDTO

    /// `{ action: "renew" }` → +60 j ; 400 `renewalLimitReached` / `notRenewable`.
    func patchAnnonce(id: String, _ body: PatchAnnonceRequestDTO) async throws -> RenewResponseDTO

    // MARK: Recherches sauvegardées (5 au maximum)

    func getSavedSearches() async throws -> SavedSearchesDTO

    /// 201 `{ search }` ou 200 `{ search, duplicate: true }` ; 400 `savedSearchEmpty` / `savedSearchLimit`.
    func createSavedSearch(_ body: SavedSearchCreateRequestDTO) async throws -> SavedSearchCreatedDTO

    func deleteSavedSearch(id: String) async throws -> SimpleResponseDTO

    // MARK: Favoris (403 emailNotVerified, même en lecture)

    func getFavorites() async throws -> [AnnonceDTO]

    func addFavorite(_ body: FavoriteRequestDTO) async throws -> FavoriteDTO

    func removeFavorite(annonceId: String) async throws -> SimpleResponseDTO

    /// 200 `{ isFavorite: false }` même sans session.
    func isFavorite(annonceId: String) async throws -> IsFavoriteDTO

    /// Image d'annonce (multipart, champ `file`, ≤ 5 Mo) → `{ url, thumbnailUrl, publicId }`. 429 (30 / 10 min).
    func upload(_ file: MultipartFile) async throws -> UploadResponseDTO

    /// Mes annonces, tous statuts (+ `aiModeration`).
    func myAnnonces(status: String?, page: Int, limit: Int) async throws -> AnnoncesPageDTO

    // MARK: Messagerie

    /// Conversations, plus récente en tête ; `archived = true` = archives. Curseur, pas de `hasMore`.
    func getConversations(cursor: String?, limit: Int, archived: Bool?) async throws -> ConversationsPageDTO

    /// Crée (ou réutilise) la conversation de l'annonce ET envoie le premier message. 10 / h.
    func createConversation(_ body: CreateConversationRequestDTO) async throws -> ConversationCreatedDTO

    /// Fil complet ; marque les messages reçus comme lus. 404 `conversationNotFound`.
    func getConversation(id: String, cursor: String?, limit: Int) async throws -> ConversationDetailDTO

    /// 20 messages / min / conversation ; 403 `emailNotVerified` / `userBlocked` / `userDeleted`.
    func sendMessage(id: String, _ body: SendMessageRequestDTO) async throws -> MessageDTO

    /// Suppression douce, expéditeur seulement, fenêtre de 5 min (403 `deletionWindowExpired`).
    func deleteMessage(id: String, messageId: String) async throws -> SimpleResponseDTO

    func archiveConversation(id: String) async throws -> SimpleResponseDTO

    func unarchiveConversation(id: String) async throws -> SimpleResponseDTO

    /// Négociation dans le fil : new / counter / accept / decline.
    func postOfferAction(id: String, _ body: OfferActionRequestDTO) async throws -> MessageDTO

    /// Offre initiale depuis l'annonce ; 409 `{ error: "offerAlreadyOpen", conversationId }`.
    func initiateOffer(id: String, _ body: OfferInitiateRequestDTO) async throws -> ConversationCreatedDTO

    /// Numéro du vendeur (5 / h / utilisateur, 2 / h / annonce) ; 404 `noPhoneNumber`.
    func getContactPhone(id: String) async throws -> ContactPhoneDTO

    func blockUser(id: String) async throws -> SimpleResponseDTO

    func unblockUser(id: String) async throws -> SimpleResponseDTO

    /// Utilisateurs que j'ai bloqués, plus récent en tête (lot serveur B ; 404 tant qu'il n'est pas déployé). `limit` 1–100.
    func getBlockedUsers(page: Int, limit: Int) async throws -> BlockedUsersPageDTO

    // MARK: Notifications in-app

    /// Liste paginée + `unreadCount` + `topic` (canal personnel signé).
    func getNotifications(page: Int, limit: Int) async throws -> NotificationsPageDTO

    func markAllNotificationsRead() async throws -> MarkAllReadDTO

    func markNotificationRead(id: String) async throws -> SimpleResponseDTO

    func deleteNotification(id: String) async throws -> SimpleResponseDTO
}
