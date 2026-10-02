import Foundation
import XCTest
@testable import Weyda

/// Fausse API des tests de repositories — portage de `FakeWeydaApi.kt` (Android) : chaque route est une closure
/// remplaçable ; une route non configurée lève `Unsupported`. Chaque appel est enregistré (`calls`, nom de la
/// route) ; `getAnnonces` garde aussi ses paramètres (`searchCalls`). Isolée sur le MainActor, comme les
/// repositories qui l'appellent : les tests la configurent sans précaution de concurrence.
@MainActor
final class FakeWeydaAPI: WeydaAPI {
    struct Unsupported: Error, CustomStringConvertible {
        let endpoint: String
        var description: String { "route non configurée dans FakeWeydaAPI : \(endpoint)" }
    }

    /// Valeur partagée entre un test et les gestionnaires (corps reçu, compteur) — une référence plutôt qu'une
    /// variable capturée. `@unchecked` : test et gestionnaires s'exécutent tous sur le MainActor.
    final class Box<Value>: @unchecked Sendable {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    /// Paramètres reçus par `getAnnonces`.
    struct SearchCall: Equatable, Sendable {
        let q: String?
        let category: String?
        let subcategory: String?
        let wilaya: Int?
        let commune: Int?
        let priceType: String?
        let priceMin: Double?
        let priceMax: Double?
        let sort: String?
        let featured: Int?
        let page: Int
        let limit: Int
        let locale: String?
        let withFacets: Int?
        let attrs: [String: String]
    }

    /// Routes appelées, dans l'ordre (`"getAnnonces"`, `"login"`…).
    private(set) var calls: [String] = []
    private(set) var searchCalls: [SearchCall] = []

    // MARK: Gestionnaires (non configuré = `Unsupported`, sauf les routes « silencieuses » comme Android)

    var onGetAnnonces: @MainActor (SearchCall) async throws -> AnnoncesPageDTO = { _ in throw Unsupported(endpoint: "getAnnonces") }
    var onGetAnnonce: @MainActor (String) async throws -> AnnonceDTO = { _ in throw Unsupported(endpoint: "getAnnonce") }
    var onGetCategories: @MainActor () async throws -> [CategoryDTO] = { throw Unsupported(endpoint: "getCategories") }
    var onGetWilayas: @MainActor () async throws -> [WilayaDTO] = { throw Unsupported(endpoint: "getWilayas") }
    var onGetCommunes: @MainActor (Int) async throws -> [CommuneDTO] = { _ in throw Unsupported(endpoint: "getCommunes") }
    var onGetTopWilayas: @MainActor (Int) async throws -> [WilayaDTO] = { _ in throw Unsupported(endpoint: "getTopWilayas") }
    /// (slug, subcategory, locale, context `ctx_*`)
    var onGetAttributes: @MainActor (String, String?, String, [String: String]) async throws -> AttributesResponseDTO = { _, _, _, _ in
        throw Unsupported(endpoint: "getAttributes")
    }
    var onPublicProfile: @MainActor (String) async throws -> UserRefDTO = { _ in throw Unsupported(endpoint: "publicProfile") }
    /// (id, page, limit)
    var onPublicAnnonces: @MainActor (String, Int, Int) async throws -> AnnoncesPageDTO = { _, _, _ in throw Unsupported(endpoint: "publicAnnonces") }
    /// (targetId, page, limit)
    var onGetReviews: @MainActor (String, Int, Int) async throws -> ReviewsDTO = { _, _, _ in throw Unsupported(endpoint: "getReviews") }
    var onReport: @MainActor (ReportRequestDTO) async throws -> ReportDTO = { _ in throw Unsupported(endpoint: "report") }
    var onContact: @MainActor (ContactRequestDTO) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "contact") }
    var onRegisterFcmToken: @MainActor (FcmTokenRequestDTO) async throws -> SimpleResponseDTO = { _ in SimpleResponseDTO() }
    var onGetTrending: @MainActor (Int) async throws -> AnnonceListDTO = { _ in AnnonceListDTO() }
    var onGetRecommendations: @MainActor () async throws -> AnnonceListDTO = { AnnonceListDTO() }
    var onDidYouMean: @MainActor (String) async throws -> DidYouMeanDTO = { _ in DidYouMeanDTO() }
    var onUpdateLocale: @MainActor (LocaleUpdateRequestDTO) async throws -> MeDTO = { _ in throw Unsupported(endpoint: "updateLocale") }
    var onCountView: @MainActor (String) async throws -> ViewCountDTO = { _ in ViewCountDTO(counted: true) }
    var onReviewEligibility: @MainActor (String) async throws -> ReviewEligibilityDTO = { _ in throw Unsupported(endpoint: "reviewEligibility") }
    var onSubmitReview: @MainActor (ReviewCreateRequestDTO) async throws -> ReviewDTO = { _ in throw Unsupported(endpoint: "submitReview") }
    /// (q, locale)
    var onGetSuggestions: @MainActor (String, String) async throws -> SuggestionsDTO = { _, _ in throw Unsupported(endpoint: "getSuggestions") }
    var onLogin: @MainActor (LoginRequestDTO) async throws -> TokenResponseDTO = { _ in throw Unsupported(endpoint: "login") }
    var onRefresh: @MainActor (RefreshRequestDTO) async throws -> TokenResponseDTO = { _ in throw Unsupported(endpoint: "refresh") }
    var onLoginWithGoogle: @MainActor (GoogleLoginRequestDTO) async throws -> TokenResponseDTO = { _ in throw Unsupported(endpoint: "loginWithGoogle") }
    var onLoginWithApple: @MainActor (AppleLoginRequestDTO) async throws -> TokenResponseDTO = { _ in throw Unsupported(endpoint: "loginWithApple") }
    var onRegister: @MainActor (RegisterRequestDTO) async throws -> RegisterResponseDTO = { _ in throw Unsupported(endpoint: "register") }
    var onForgotPassword: @MainActor (ForgotPasswordRequestDTO) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "forgotPassword") }
    var onResetPassword: @MainActor (ResetPasswordRequestDTO) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "resetPassword") }
    var onResend: @MainActor () async throws -> SimpleResponseDTO = { throw Unsupported(endpoint: "resendVerificationCode") }
    var onConfirm: @MainActor (CodeRequestDTO) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "confirmEmail") }
    var onMe: @MainActor () async throws -> MeDTO = { throw Unsupported(endpoint: "me") }
    var onUpdateMe: @MainActor (UpdateProfileRequestDTO) async throws -> MeDTO = { _ in throw Unsupported(endpoint: "updateMe") }
    var onChangePassword: @MainActor (ChangePasswordRequestDTO) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "changePassword") }
    var onMyStats: @MainActor () async throws -> UserStatsDTO = { throw Unsupported(endpoint: "myStats") }
    var onExportData: @MainActor (URL?) async throws -> URL = { _ in throw Unsupported(endpoint: "exportData") }
    var onDeleteAccount: @MainActor (DeleteAccountRequestDTO) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "deleteAccount") }
    var onCreateAnnonce: @MainActor (CreateAnnonceRequestDTO) async throws -> AnnonceDTO = { _ in throw Unsupported(endpoint: "createAnnonce") }
    var onUpdateAnnonce: @MainActor (String, UpdateAnnonceRequestDTO) async throws -> AnnonceDTO = { _, _ in throw Unsupported(endpoint: "updateAnnonce") }
    /// Le corps tel qu'il part sur le fil, relu en JSON : les tests portent sur les `null` explicites.
    var onEditAnnonce: @MainActor (String, JSONValue) async throws -> AnnonceDTO = { _, _ in throw Unsupported(endpoint: "editAnnonce") }
    var onDeleteAnnonce: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "deleteAnnonce") }
    var onPatchAnnonce: @MainActor (String, PatchAnnonceRequestDTO) async throws -> RenewResponseDTO = { _, _ in throw Unsupported(endpoint: "patchAnnonce") }
    var onGetSavedSearches: @MainActor () async throws -> SavedSearchesDTO = { throw Unsupported(endpoint: "getSavedSearches") }
    var onCreateSavedSearch: @MainActor (SavedSearchCreateRequestDTO) async throws -> SavedSearchCreatedDTO = { _ in
        throw Unsupported(endpoint: "createSavedSearch")
    }
    var onDeleteSavedSearch: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "deleteSavedSearch") }
    var onGetFavorites: @MainActor () async throws -> [AnnonceDTO] = { throw Unsupported(endpoint: "getFavorites") }
    var onAddFavorite: @MainActor (FavoriteRequestDTO) async throws -> FavoriteDTO = { _ in throw Unsupported(endpoint: "addFavorite") }
    var onRemoveFavorite: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "removeFavorite") }
    var onIsFavorite: @MainActor (String) async throws -> IsFavoriteDTO = { _ in throw Unsupported(endpoint: "isFavorite") }
    var onUpload: @MainActor (MultipartFile) async throws -> UploadResponseDTO = { _ in throw Unsupported(endpoint: "upload") }
    /// (status, page, limit)
    var onMyAnnonces: @MainActor (String?, Int, Int) async throws -> AnnoncesPageDTO = { _, _, _ in throw Unsupported(endpoint: "myAnnonces") }
    /// (cursor, limit, archived)
    var onGetConversations: @MainActor (String?, Int, Bool?) async throws -> ConversationsPageDTO = { _, _, _ in
        throw Unsupported(endpoint: "getConversations")
    }
    var onCreateConversation: @MainActor (CreateConversationRequestDTO) async throws -> ConversationCreatedDTO = { _ in
        throw Unsupported(endpoint: "createConversation")
    }
    /// (id, cursor, limit)
    var onGetConversation: @MainActor (String, String?, Int) async throws -> ConversationDetailDTO = { _, _, _ in
        throw Unsupported(endpoint: "getConversation")
    }
    var onSendMessage: @MainActor (String, SendMessageRequestDTO) async throws -> MessageDTO = { _, _ in throw Unsupported(endpoint: "sendMessage") }
    var onDeleteMessage: @MainActor (String, String) async throws -> SimpleResponseDTO = { _, _ in throw Unsupported(endpoint: "deleteMessage") }
    var onArchiveConversation: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "archiveConversation") }
    var onUnarchiveConversation: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "unarchiveConversation") }
    var onPostOfferAction: @MainActor (String, OfferActionRequestDTO) async throws -> MessageDTO = { _, _ in throw Unsupported(endpoint: "postOfferAction") }
    var onInitiateOffer: @MainActor (String, OfferInitiateRequestDTO) async throws -> ConversationCreatedDTO = { _, _ in
        throw Unsupported(endpoint: "initiateOffer")
    }
    var onGetContactPhone: @MainActor (String) async throws -> ContactPhoneDTO = { _ in throw Unsupported(endpoint: "getContactPhone") }
    var onBlockUser: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "blockUser") }
    var onUnblockUser: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "unblockUser") }
    /// (page, limit)
    var onGetNotifications: @MainActor (Int, Int) async throws -> NotificationsPageDTO = { _, _ in throw Unsupported(endpoint: "getNotifications") }
    var onMarkAllNotificationsRead: @MainActor () async throws -> MarkAllReadDTO = { throw Unsupported(endpoint: "markAllNotificationsRead") }
    var onMarkNotificationRead: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "markNotificationRead") }
    var onDeleteNotification: @MainActor (String) async throws -> SimpleResponseDTO = { _ in throw Unsupported(endpoint: "deleteNotification") }

    init() {}

    private func record(_ endpoint: String) {
        calls.append(endpoint)
    }

    /// Nombre d'appels d'une route.
    func count(_ endpoint: String) -> Int {
        calls.filter { $0 == endpoint }.count
    }

    // MARK: - WeydaAPI

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
        record("getAnnonces")
        let call = SearchCall(
            q: q, category: category, subcategory: subcategory, wilaya: wilaya, commune: commune, priceType: priceType,
            priceMin: priceMin, priceMax: priceMax, sort: sort, featured: featured, page: page, limit: limit,
            locale: locale, withFacets: withFacets, attrs: attrs
        )
        searchCalls.append(call)
        return try await onGetAnnonces(call)
    }

    func getAnnonce(idOrSlug: String) async throws -> AnnonceDTO {
        record("getAnnonce")
        return try await onGetAnnonce(idOrSlug)
    }

    func getCategories() async throws -> [CategoryDTO] {
        record("getCategories")
        return try await onGetCategories()
    }

    func getWilayas() async throws -> [WilayaDTO] {
        record("getWilayas")
        return try await onGetWilayas()
    }

    func getCommunes(wilayaId: Int) async throws -> [CommuneDTO] {
        record("getCommunes")
        return try await onGetCommunes(wilayaId)
    }

    func getTopWilayas(top: Int) async throws -> [WilayaDTO] {
        record("getTopWilayas")
        return try await onGetTopWilayas(top)
    }

    func getAttributes(slug: String, subcategory: String?, locale: String, context: [String: String]) async throws -> AttributesResponseDTO {
        record("getAttributes")
        return try await onGetAttributes(slug, subcategory, locale, context)
    }

    func publicProfile(id: String) async throws -> UserRefDTO {
        record("publicProfile")
        return try await onPublicProfile(id)
    }

    func publicAnnonces(id: String, page: Int, limit: Int) async throws -> AnnoncesPageDTO {
        record("publicAnnonces")
        return try await onPublicAnnonces(id, page, limit)
    }

    func getReviews(targetId: String, page: Int, limit: Int) async throws -> ReviewsDTO {
        record("getReviews")
        return try await onGetReviews(targetId, page, limit)
    }

    func report(_ body: ReportRequestDTO) async throws -> ReportDTO {
        record("report")
        return try await onReport(body)
    }

    func contact(_ body: ContactRequestDTO) async throws -> SimpleResponseDTO {
        record("contact")
        return try await onContact(body)
    }

    func registerFcmToken(_ body: FcmTokenRequestDTO) async throws -> SimpleResponseDTO {
        record("registerFcmToken")
        return try await onRegisterFcmToken(body)
    }

    func getTrending(limit: Int) async throws -> AnnonceListDTO {
        record("getTrending")
        return try await onGetTrending(limit)
    }

    func getRecommendations() async throws -> AnnonceListDTO {
        record("getRecommendations")
        return try await onGetRecommendations()
    }

    func didYouMean(q: String) async throws -> DidYouMeanDTO {
        record("didYouMean")
        return try await onDidYouMean(q)
    }

    func updateLocale(_ body: LocaleUpdateRequestDTO) async throws -> MeDTO {
        record("updateLocale")
        return try await onUpdateLocale(body)
    }

    func countView(id: String) async throws -> ViewCountDTO {
        record("countView")
        return try await onCountView(id)
    }

    func reviewEligibility(targetId: String) async throws -> ReviewEligibilityDTO {
        record("reviewEligibility")
        return try await onReviewEligibility(targetId)
    }

    func submitReview(_ body: ReviewCreateRequestDTO) async throws -> ReviewDTO {
        record("submitReview")
        return try await onSubmitReview(body)
    }

    func getSuggestions(q: String, locale: String) async throws -> SuggestionsDTO {
        record("getSuggestions")
        return try await onGetSuggestions(q, locale)
    }

    func login(_ body: LoginRequestDTO) async throws -> TokenResponseDTO {
        record("login")
        return try await onLogin(body)
    }

    func refresh(_ body: RefreshRequestDTO) async throws -> TokenResponseDTO {
        record("refresh")
        return try await onRefresh(body)
    }

    func loginWithGoogle(_ body: GoogleLoginRequestDTO) async throws -> TokenResponseDTO {
        record("loginWithGoogle")
        return try await onLoginWithGoogle(body)
    }

    func loginWithApple(_ body: AppleLoginRequestDTO) async throws -> TokenResponseDTO {
        record("loginWithApple")
        return try await onLoginWithApple(body)
    }

    func register(_ body: RegisterRequestDTO) async throws -> RegisterResponseDTO {
        record("register")
        return try await onRegister(body)
    }

    func forgotPassword(_ body: ForgotPasswordRequestDTO) async throws -> SimpleResponseDTO {
        record("forgotPassword")
        return try await onForgotPassword(body)
    }

    func resetPassword(_ body: ResetPasswordRequestDTO) async throws -> SimpleResponseDTO {
        record("resetPassword")
        return try await onResetPassword(body)
    }

    func resendVerificationCode() async throws -> SimpleResponseDTO {
        record("resendVerificationCode")
        return try await onResend()
    }

    func confirmEmail(_ body: CodeRequestDTO) async throws -> SimpleResponseDTO {
        record("confirmEmail")
        return try await onConfirm(body)
    }

    func me() async throws -> MeDTO {
        record("me")
        return try await onMe()
    }

    func updateMe(_ body: UpdateProfileRequestDTO) async throws -> MeDTO {
        record("updateMe")
        return try await onUpdateMe(body)
    }

    func changePassword(_ body: ChangePasswordRequestDTO) async throws -> SimpleResponseDTO {
        record("changePassword")
        return try await onChangePassword(body)
    }

    func myStats() async throws -> UserStatsDTO {
        record("myStats")
        return try await onMyStats()
    }

    func exportData(to destination: URL?) async throws -> URL {
        record("exportData")
        return try await onExportData(destination)
    }

    func deleteAccount(_ body: DeleteAccountRequestDTO) async throws -> SimpleResponseDTO {
        record("deleteAccount")
        return try await onDeleteAccount(body)
    }

    func createAnnonce(_ body: CreateAnnonceRequestDTO) async throws -> AnnonceDTO {
        record("createAnnonce")
        return try await onCreateAnnonce(body)
    }

    func updateAnnonce(id: String, _ body: UpdateAnnonceRequestDTO) async throws -> AnnonceDTO {
        record("updateAnnonce")
        return try await onUpdateAnnonce(id, body)
    }

    func editAnnonce(id: String, body: Data) async throws -> AnnonceDTO {
        record("editAnnonce")
        let json = (try? JSONDecoder().decode(JSONValue.self, from: body)) ?? .null
        return try await onEditAnnonce(id, json)
    }

    func deleteAnnonce(id: String) async throws -> SimpleResponseDTO {
        record("deleteAnnonce")
        return try await onDeleteAnnonce(id)
    }

    func patchAnnonce(id: String, _ body: PatchAnnonceRequestDTO) async throws -> RenewResponseDTO {
        record("patchAnnonce")
        return try await onPatchAnnonce(id, body)
    }

    func getSavedSearches() async throws -> SavedSearchesDTO {
        record("getSavedSearches")
        return try await onGetSavedSearches()
    }

    func createSavedSearch(_ body: SavedSearchCreateRequestDTO) async throws -> SavedSearchCreatedDTO {
        record("createSavedSearch")
        return try await onCreateSavedSearch(body)
    }

    func deleteSavedSearch(id: String) async throws -> SimpleResponseDTO {
        record("deleteSavedSearch")
        return try await onDeleteSavedSearch(id)
    }

    func getFavorites() async throws -> [AnnonceDTO] {
        record("getFavorites")
        return try await onGetFavorites()
    }

    func addFavorite(_ body: FavoriteRequestDTO) async throws -> FavoriteDTO {
        record("addFavorite")
        return try await onAddFavorite(body)
    }

    func removeFavorite(annonceId: String) async throws -> SimpleResponseDTO {
        record("removeFavorite")
        return try await onRemoveFavorite(annonceId)
    }

    func isFavorite(annonceId: String) async throws -> IsFavoriteDTO {
        record("isFavorite")
        return try await onIsFavorite(annonceId)
    }

    func upload(_ file: MultipartFile) async throws -> UploadResponseDTO {
        record("upload")
        return try await onUpload(file)
    }

    func myAnnonces(status: String?, page: Int, limit: Int) async throws -> AnnoncesPageDTO {
        record("myAnnonces")
        return try await onMyAnnonces(status, page, limit)
    }

    func getConversations(cursor: String?, limit: Int, archived: Bool?) async throws -> ConversationsPageDTO {
        record("getConversations")
        return try await onGetConversations(cursor, limit, archived)
    }

    func createConversation(_ body: CreateConversationRequestDTO) async throws -> ConversationCreatedDTO {
        record("createConversation")
        return try await onCreateConversation(body)
    }

    func getConversation(id: String, cursor: String?, limit: Int) async throws -> ConversationDetailDTO {
        record("getConversation")
        return try await onGetConversation(id, cursor, limit)
    }

    func sendMessage(id: String, _ body: SendMessageRequestDTO) async throws -> MessageDTO {
        record("sendMessage")
        return try await onSendMessage(id, body)
    }

    func deleteMessage(id: String, messageId: String) async throws -> SimpleResponseDTO {
        record("deleteMessage")
        return try await onDeleteMessage(id, messageId)
    }

    func archiveConversation(id: String) async throws -> SimpleResponseDTO {
        record("archiveConversation")
        return try await onArchiveConversation(id)
    }

    func unarchiveConversation(id: String) async throws -> SimpleResponseDTO {
        record("unarchiveConversation")
        return try await onUnarchiveConversation(id)
    }

    func postOfferAction(id: String, _ body: OfferActionRequestDTO) async throws -> MessageDTO {
        record("postOfferAction")
        return try await onPostOfferAction(id, body)
    }

    func initiateOffer(id: String, _ body: OfferInitiateRequestDTO) async throws -> ConversationCreatedDTO {
        record("initiateOffer")
        return try await onInitiateOffer(id, body)
    }

    func getContactPhone(id: String) async throws -> ContactPhoneDTO {
        record("getContactPhone")
        return try await onGetContactPhone(id)
    }

    func blockUser(id: String) async throws -> SimpleResponseDTO {
        record("blockUser")
        return try await onBlockUser(id)
    }

    func unblockUser(id: String) async throws -> SimpleResponseDTO {
        record("unblockUser")
        return try await onUnblockUser(id)
    }

    func getNotifications(page: Int, limit: Int) async throws -> NotificationsPageDTO {
        record("getNotifications")
        return try await onGetNotifications(page, limit)
    }

    func markAllNotificationsRead() async throws -> MarkAllReadDTO {
        record("markAllNotificationsRead")
        return try await onMarkAllNotificationsRead()
    }

    func markNotificationRead(id: String) async throws -> SimpleResponseDTO {
        record("markNotificationRead")
        return try await onMarkNotificationRead(id)
    }

    func deleteNotification(id: String) async throws -> SimpleResponseDTO {
        record("deleteNotification")
        return try await onDeleteNotification(id)
    }

    // MARK: - Aides des tests

    /// Erreur telle que le client la produit pour une réponse `{ "error": "code", … }` (Android : `httpError`).
    nonisolated static func apiError(_ status: Int, _ body: String = #"{"error":"serverError"}"#, retryAfter: String? = nil) -> APIError {
        APIError(status: status, body: Data(body.utf8), retryAfterHeader: retryAfter)
    }

    /// Réponse de connexion fictive (Android : `tokenResponse`).
    nonisolated static func tokens(
        access: String = "access-1",
        refresh: String = "refresh-1",
        emailVerified: Bool = true
    ) -> TokenResponseDTO {
        TokenResponseDTO(
            accessToken: access,
            refreshToken: refresh,
            expiresIn: 3600,
            refreshExpiresIn: 2_592_000,
            user: AuthUserDTO(id: "user_1", name: "Amina", email: "amina@example.com", avatar: nil, role: "USER", emailVerified: emailVerified)
        )
    }

    /// Session en mémoire pour les tests (aucune rotation possible).
    static func makeSession() -> SessionManager {
        SessionManager(storage: InMemorySessionStorage(), refreshCall: { _ in throw URLError(.unsupportedURL) })
    }
}
