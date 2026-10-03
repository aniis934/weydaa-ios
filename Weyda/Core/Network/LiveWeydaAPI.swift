import Foundation

/// `WeydaAPI` sur le vrai réseau (`APIClient`) — l'équivalent des deux interfaces Retrofit d'Android :
/// `client` porte le Bearer de la session (rotation + rejeu sur 401), `authClient` n'en porte jamais (`authApi` :
/// connexion, rotation, inscription, mot de passe oublié). Sans état : utilisable depuis n'importe quel fil ; le
/// réseau et le décodage partent hors du fil principal (`APIClient` est `@concurrent`).
nonisolated struct LiveWeydaAPI: WeydaAPI {
    let client: APIClient
    let authClient: APIClient

    init(client: APIClient, authClient: APIClient) {
        self.client = client
        self.authClient = authClient
    }

    // MARK: - Public

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
    ) async throws -> AnnoncesPageDTO {
        var request = APIRequest.get("api/annonces")
        request.addQuery("q", q)
        request.addQuery("category", category)
        request.addQuery("subcategory", subcategory)
        request.addQuery("wilaya", wilaya)
        request.addQuery("commune", commune)
        request.addQuery("priceType", priceType)
        request.addQuery("priceMin", priceMin)
        request.addQuery("priceMax", priceMax)
        request.addQuery("sort", sort)
        request.addQuery("featured", featured)
        request.addQuery("page", page)
        request.addQuery("limit", limit)
        request.addQuery("locale", locale)
        request.addQuery("withFacets", withFacets)
        Self.addQueryMap(attrs, to: &request)
        return try await client.send(request, as: AnnoncesPageDTO.self)
    }

    func getAnnonce(idOrSlug: String) async throws -> AnnonceDTO {
        try await client.send(.get("api/annonces/\(APIRequest.segment(idOrSlug))"), as: AnnonceDTO.self)
    }

    func getCategories() async throws -> [CategoryDTO] {
        try await client.send(.get("api/categories"), as: DTOLossyList<CategoryDTO>.self).items
    }

    func getWilayas() async throws -> [WilayaDTO] {
        try await client.send(.get("api/wilayas"), as: DTOLossyList<WilayaDTO>.self).items
    }

    func getCommunes(wilayaId: Int) async throws -> [CommuneDTO] {
        var request = APIRequest.get("api/wilayas")
        request.addQuery("wilayaId", wilayaId)
        return try await client.send(request, as: DTOLossyList<CommuneDTO>.self).items
    }

    func getTopWilayas(top: Int) async throws -> [WilayaDTO] {
        var request = APIRequest.get("api/wilayas")
        request.addQuery("top", top)
        return try await client.send(request, as: DTOLossyList<WilayaDTO>.self).items
    }

    func getAttributes(slug: String, subcategory: String?, locale: String, context: [String: String]) async throws -> AttributesResponseDTO {
        var request = APIRequest.get("api/categories/\(APIRequest.segment(slug))/attributes")
        request.addQuery("subcategory", subcategory)
        request.addQuery("locale", locale)
        Self.addQueryMap(context, to: &request)
        return try await client.send(request, as: AttributesResponseDTO.self)
    }

    func publicProfile(id: String) async throws -> UserRefDTO {
        try await client.send(.get("api/users/\(APIRequest.segment(id))"), as: UserRefDTO.self)
    }

    func publicAnnonces(id: String, page: Int, limit: Int) async throws -> AnnoncesPageDTO {
        var request = APIRequest.get("api/users/\(APIRequest.segment(id))/annonces")
        request.addQuery("page", page)
        request.addQuery("limit", limit)
        return try await client.send(request, as: AnnoncesPageDTO.self)
    }

    func getReviews(targetId: String, page: Int, limit: Int) async throws -> ReviewsDTO {
        var request = APIRequest.get("api/reviews")
        request.addQuery("targetId", targetId)
        request.addQuery("page", page)
        request.addQuery("limit", limit)
        return try await client.send(request, as: ReviewsDTO.self)
    }

    func report(_ body: ReportRequestDTO) async throws -> ReportDTO {
        try await client.send(.post("api/reports", json: body), as: ReportDTO.self)
    }

    func contact(_ body: ContactRequestDTO) async throws -> SimpleResponseDTO {
        try await client.send(.post("api/contact", json: body), as: SimpleResponseDTO.self)
    }

    func registerFcmToken(_ body: FcmTokenRequestDTO) async throws -> SimpleResponseDTO {
        try await client.send(.post("api/push/fcm", json: body), as: SimpleResponseDTO.self)
    }

    func getTrending(limit: Int) async throws -> AnnonceListDTO {
        var request = APIRequest.get("api/annonces/trending")
        request.addQuery("limit", limit)
        return try await client.send(request, as: AnnonceListDTO.self)
    }

    func getRecommendations() async throws -> AnnonceListDTO {
        try await client.send(.get("api/recommendations"), as: AnnonceListDTO.self)
    }

    func didYouMean(q: String) async throws -> DidYouMeanDTO {
        var request = APIRequest.get("api/search/did-you-mean")
        request.addQuery("q", q)
        return try await client.send(request, as: DidYouMeanDTO.self)
    }

    func updateLocale(_ body: LocaleUpdateRequestDTO) async throws -> MeDTO {
        try await client.send(.put("api/users/me", json: body), as: MeDTO.self)
    }

    func countView(id: String) async throws -> ViewCountDTO {
        try await client.send(.post("api/annonces/\(APIRequest.segment(id))/view"), as: ViewCountDTO.self)
    }

    func reviewEligibility(targetId: String) async throws -> ReviewEligibilityDTO {
        var request = APIRequest.get("api/reviews/eligibility")
        request.addQuery("targetId", targetId)
        return try await client.send(request, as: ReviewEligibilityDTO.self)
    }

    func submitReview(_ body: ReviewCreateRequestDTO) async throws -> ReviewDTO {
        try await client.send(.post("api/reviews", json: body), as: ReviewDTO.self)
    }

    func getSuggestions(q: String, locale: String) async throws -> SuggestionsDTO {
        var request = APIRequest.get("api/search/suggestions")
        request.addQuery("q", q)
        request.addQuery("locale", locale)
        return try await client.send(request, as: SuggestionsDTO.self)
    }

    // MARK: - Authentification (client sans jeton)

    func login(_ body: LoginRequestDTO) async throws -> TokenResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/token", body), as: TokenResponseDTO.self)
    }

    func refresh(_ body: RefreshRequestDTO) async throws -> TokenResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/token/refresh", body), as: TokenResponseDTO.self)
    }

    func loginWithGoogle(_ body: GoogleLoginRequestDTO) async throws -> TokenResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/google", body), as: TokenResponseDTO.self)
    }

    func loginWithApple(_ body: AppleLoginRequestDTO) async throws -> TokenResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/apple", body), as: TokenResponseDTO.self)
    }

    func register(_ body: RegisterRequestDTO) async throws -> RegisterResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/register", body), as: RegisterResponseDTO.self)
    }

    func forgotPassword(_ body: ForgotPasswordRequestDTO) async throws -> SimpleResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/forgot-password", body), as: SimpleResponseDTO.self)
    }

    func resetPassword(_ body: ResetPasswordRequestDTO) async throws -> SimpleResponseDTO {
        try await authClient.send(Self.anonymous("api/auth/reset-password", body), as: SimpleResponseDTO.self)
    }

    func resendVerificationCode() async throws -> SimpleResponseDTO {
        try await client.send(.post("api/email-verify", json: [String: String]()), as: SimpleResponseDTO.self)
    }

    func confirmEmail(_ body: CodeRequestDTO) async throws -> SimpleResponseDTO {
        try await client.send(.post("api/email-verify/confirm", json: body), as: SimpleResponseDTO.self)
    }

    // MARK: - Compte

    func me() async throws -> MeDTO {
        try await client.send(.get("api/users/me"), as: MeDTO.self)
    }

    func updateMe(_ body: UpdateProfileRequestDTO) async throws -> MeDTO {
        try await client.send(.put("api/users/me", json: body), as: MeDTO.self)
    }

    func changePassword(_ body: ChangePasswordRequestDTO) async throws -> SimpleResponseDTO {
        try await client.send(.put("api/users/me/password", json: body), as: SimpleResponseDTO.self)
    }

    func myStats() async throws -> UserStatsDTO {
        try await client.send(.get("api/users/me/stats"), as: UserStatsDTO.self)
    }

    func exportData(to destination: URL?) async throws -> URL {
        try await client.download(.get("api/users/me/export"), to: destination)
    }

    func deleteAccount(_ body: DeleteAccountRequestDTO) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/users/me/account", json: body), as: SimpleResponseDTO.self)
    }

    func createAnnonce(_ body: CreateAnnonceRequestDTO) async throws -> AnnonceDTO {
        try await client.send(.post("api/annonces", json: body), as: AnnonceDTO.self)
    }

    func updateAnnonce(id: String, _ body: UpdateAnnonceRequestDTO) async throws -> AnnonceDTO {
        try await client.send(.put("api/annonces/\(APIRequest.segment(id))", json: body), as: AnnonceDTO.self)
    }

    func editAnnonce(id: String, body: Data) async throws -> AnnonceDTO {
        let request = APIRequest(.put, "api/annonces/\(APIRequest.segment(id))", body: .rawJSON(body))
        return try await client.send(request, as: AnnonceDTO.self)
    }

    func deleteAnnonce(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/annonces/\(APIRequest.segment(id))"), as: SimpleResponseDTO.self)
    }

    func patchAnnonce(id: String, _ body: PatchAnnonceRequestDTO) async throws -> RenewResponseDTO {
        try await client.send(.patch("api/annonces/\(APIRequest.segment(id))", json: body), as: RenewResponseDTO.self)
    }

    // MARK: - Recherches sauvegardées

    func getSavedSearches() async throws -> SavedSearchesDTO {
        try await client.send(.get("api/saved-searches"), as: SavedSearchesDTO.self)
    }

    func createSavedSearch(_ body: SavedSearchCreateRequestDTO) async throws -> SavedSearchCreatedDTO {
        try await client.send(.post("api/saved-searches", json: body), as: SavedSearchCreatedDTO.self)
    }

    func deleteSavedSearch(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/saved-searches/\(APIRequest.segment(id))"), as: SimpleResponseDTO.self)
    }

    // MARK: - Favoris

    func getFavorites() async throws -> [AnnonceDTO] {
        try await client.send(.get("api/favorites"), as: DTOLossyList<AnnonceDTO>.self).items
    }

    func addFavorite(_ body: FavoriteRequestDTO) async throws -> FavoriteDTO {
        try await client.send(.post("api/favorites", json: body), as: FavoriteDTO.self)
    }

    func removeFavorite(annonceId: String) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/favorites/\(APIRequest.segment(annonceId))"), as: SimpleResponseDTO.self)
    }

    func isFavorite(annonceId: String) async throws -> IsFavoriteDTO {
        try await client.send(.get("api/favorites/\(APIRequest.segment(annonceId))"), as: IsFavoriteDTO.self)
    }

    func upload(_ file: MultipartFile) async throws -> UploadResponseDTO {
        try await client.send(.upload(file), as: UploadResponseDTO.self)
    }

    func myAnnonces(status: String?, page: Int, limit: Int) async throws -> AnnoncesPageDTO {
        var request = APIRequest.get("api/users/me/annonces")
        request.addQuery("status", status)
        request.addQuery("page", page)
        request.addQuery("limit", limit)
        return try await client.send(request, as: AnnoncesPageDTO.self)
    }

    // MARK: - Messagerie

    func getConversations(cursor: String?, limit: Int, archived: Bool?) async throws -> ConversationsPageDTO {
        var request = APIRequest.get("api/conversations")
        request.addQuery("cursor", cursor)
        request.addQuery("limit", limit)
        request.addQuery("archived", archived)
        return try await client.send(request, as: ConversationsPageDTO.self)
    }

    func createConversation(_ body: CreateConversationRequestDTO) async throws -> ConversationCreatedDTO {
        try await client.send(.post("api/conversations", json: body), as: ConversationCreatedDTO.self)
    }

    func getConversation(id: String, cursor: String?, limit: Int) async throws -> ConversationDetailDTO {
        var request = APIRequest.get("api/conversations/\(APIRequest.segment(id))")
        request.addQuery("cursor", cursor)
        request.addQuery("limit", limit)
        return try await client.send(request, as: ConversationDetailDTO.self)
    }

    func sendMessage(id: String, _ body: SendMessageRequestDTO) async throws -> MessageDTO {
        try await client.send(.post("api/conversations/\(APIRequest.segment(id))/messages", json: body), as: MessageDTO.self)
    }

    func deleteMessage(id: String, messageId: String) async throws -> SimpleResponseDTO {
        let path = "api/conversations/\(APIRequest.segment(id))/messages/\(APIRequest.segment(messageId))"
        return try await client.send(.delete(path), as: SimpleResponseDTO.self)
    }

    func archiveConversation(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.post("api/conversations/\(APIRequest.segment(id))/archive"), as: SimpleResponseDTO.self)
    }

    func unarchiveConversation(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/conversations/\(APIRequest.segment(id))/archive"), as: SimpleResponseDTO.self)
    }

    func postOfferAction(id: String, _ body: OfferActionRequestDTO) async throws -> MessageDTO {
        try await client.send(.post("api/conversations/\(APIRequest.segment(id))/offers", json: body), as: MessageDTO.self)
    }

    func initiateOffer(id: String, _ body: OfferInitiateRequestDTO) async throws -> ConversationCreatedDTO {
        try await client.send(.post("api/annonces/\(APIRequest.segment(id))/offers", json: body), as: ConversationCreatedDTO.self)
    }

    func getContactPhone(id: String) async throws -> ContactPhoneDTO {
        try await client.send(.get("api/annonces/\(APIRequest.segment(id))/contact"), as: ContactPhoneDTO.self)
    }

    func blockUser(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.post("api/users/\(APIRequest.segment(id))/block"), as: SimpleResponseDTO.self)
    }

    func unblockUser(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/users/\(APIRequest.segment(id))/block"), as: SimpleResponseDTO.self)
    }

    func getBlockedUsers(page: Int, limit: Int) async throws -> BlockedUsersPageDTO {
        var request = APIRequest.get("api/users/me/blocked")
        request.addQuery("page", page)
        request.addQuery("limit", limit)
        return try await client.send(request, as: BlockedUsersPageDTO.self)
    }

    // MARK: - Notifications

    func getNotifications(page: Int, limit: Int) async throws -> NotificationsPageDTO {
        var request = APIRequest.get("api/notifications")
        request.addQuery("page", page)
        request.addQuery("limit", limit)
        return try await client.send(request, as: NotificationsPageDTO.self)
    }

    func markAllNotificationsRead() async throws -> MarkAllReadDTO {
        try await client.send(.patch("api/notifications"), as: MarkAllReadDTO.self)
    }

    func markNotificationRead(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.patch("api/notifications/\(APIRequest.segment(id))"), as: SimpleResponseDTO.self)
    }

    func deleteNotification(id: String) async throws -> SimpleResponseDTO {
        try await client.send(.delete("api/notifications/\(APIRequest.segment(id))"), as: SimpleResponseDTO.self)
    }

    // MARK: - Aides

    /// Route d'authentification : POST JSON, jamais de Bearer (`authenticated: false`, en plus du client sans jeton).
    private static func anonymous(_ path: String, _ body: some Encodable & Sendable) -> APIRequest {
        APIRequest(.post, path, body: .json(body), authenticated: false)
    }

    /// `@QueryMap` de Retrofit : clés triées (URL stable, donc cache CDN et tests prévisibles).
    private static func addQueryMap(_ map: [String: String], to request: inout APIRequest) {
        for key in map.keys.sorted() {
            request.addQuery(key, map[key])
        }
    }
}
