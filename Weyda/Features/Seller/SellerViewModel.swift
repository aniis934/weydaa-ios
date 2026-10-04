import Combine
import Foundation

/// État du profil public d'un vendeur — `SellerUiState` (SellerViewModel.kt). La note et le commentaire de la feuille
/// « Laisser un avis » sont des propriétés du ViewModel (liaisons de `ReviewSheet`). Données pures.
nonisolated struct SellerState: Equatable, Sendable {
    /// Identifiant du vendeur affiché (celui de la route).
    var sellerId: String = ""
    var isLoading: Bool = true
    /// La fiche fait foi pour l'erreur : sans elle il n'y a pas d'écran ; une vitrine vide reste normale.
    var errorMessage: String? = nil
    var seller: Seller? = nil
    /// Vitrine : annonces actives, page par page (12).
    var items: [Listing] = []
    var total: Int = 0
    var page: Int = 1
    var hasMore: Bool = false
    var isLoadingMore: Bool = false
    /// Avis reçus (5 premiers) ; nil tant qu'ils ne sont pas chargés ou en échec (section masquée).
    var reviews: ReviewSummary? = nil
    /// Cœurs de la vitrine (source de vérité partagée des favoris).
    var favoriteIds: Set<String> = []
    /// Utilisateur connecté ("" = visiteur).
    var userId: String = ""
    /// Bloqué depuis cet écran (l'API du profil ne dit pas si je l'ai déjà bloqué).
    var isBlocked: Bool = false
    var isBlockBusy: Bool = false
    var isReportBusy: Bool = false
    /// Panne réseau pendant l'envoi d'un signalement : affichée DANS la feuille, restée ouverte.
    var reportError: String? = nil
    /// Message bref à montrer une fois, effacé par `noticeShown()`.
    var notice: String? = nil
    /// Droit de noter ce vendeur (contact avéré, e-mail vérifié) : bouton « Laisser un avis ». Demandé pour un membre
    /// qui n'est pas le vendeur ; un échec ne le change pas (au premier chargement : bouton masqué).
    var canReview: Bool = false
    /// Un avis de moi existe déjà : le bouton devient « Modifier mon avis ».
    var hasMyReview: Bool = false
    /// Mon avis courant est relu avant d'ouvrir la feuille (bouton occupé, second appui ignoré).
    var isReviewOpening: Bool = false
    /// Feuille ouverte sur mon avis existant (titre « Modifier mon avis », note et commentaire repris).
    var isReviewEditing: Bool = false
    var isReviewBusy: Bool = false
    /// Panne réseau pendant l'envoi d'un avis : affichée DANS la feuille, restée ouverte.
    var reviewError: String? = nil

    var isLoggedIn: Bool { !TextCheck.isBlank(userId) }

    /// Mon propre profil : ni signalement ni blocage, ni avis.
    var isOwnProfile: Bool { isLoggedIn && userId == sellerId }

    /// Le droit de noter se demande au serveur : membre connecté, sur le profil d'un autre.
    var asksReviewEligibility: Bool { isLoggedIn && !isOwnProfile }

    /// Menu « Signaler / Bloquer » offert.
    var canModerate: Bool { seller != nil && !isOwnProfile }
}

/// Profil public d'un vendeur — portage de `SellerViewModel` (Android), comme `/[locale]/profil/[id]` : sa fiche,
/// sa vitrine paginée et ses avis ; laisser ou modifier mon avis ; signaler ou bloquer cet utilisateur.
final class SellerViewModel: ObservableObject {
    /// Avis montrés sur le profil (Android : REVIEWS_SHOWN).
    static let reviewsShown = 5
    /// Note proposée par une feuille d'avis neuve (Android : DEFAULT_RATING).
    nonisolated static let defaultRating = 5

    @Published private(set) var state = SellerState()
    /// Feuille « Signaler cet utilisateur » ouverte.
    @Published var isReportPresented: Bool = false
    /// Confirmation « Bloquer cet utilisateur » affichée.
    @Published var isBlockConfirmPresented: Bool = false
    /// Feuille « Laisser un avis » / « Modifier mon avis » ouverte (`openReview()`).
    @Published var isReviewPresented: Bool = false
    /// Note et commentaire de la feuille d'avis (liaisons de `ReviewSheet`) ; bornés par le repository à l'envoi.
    @Published var reviewRating: Int = SellerViewModel.defaultRating
    @Published var reviewComment: String = ""

    let sellerId: String

    private let sellers: SellerRepository
    private let favorites: FavoritesRepository
    private let reviewsRepository: ReviewsRepository
    private let reports: ReportsRepository
    private let conversations: ConversationsRepository
    private var subscriptions: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
    private var eligibilityTask: Task<Void, Never>?
    private var hasStarted: Bool = false

    init(
        id: String,
        sellers: SellerRepository,
        favorites: FavoritesRepository,
        reviews: ReviewsRepository,
        reports: ReportsRepository,
        conversations: ConversationsRepository,
        sessionUser: AnyPublisher<User?, Never>
    ) {
        self.sellerId = id
        self.sellers = sellers
        self.favorites = favorites
        self.reviewsRepository = reviews
        self.reports = reports
        self.conversations = conversations
        state.sellerId = id
        sessionUser
            .map { $0?.id ?? "" }
            .removeDuplicates()
            .sink { [weak self] userId in
                self?.sessionChanged(userId)
            }
            .store(in: &subscriptions)
        favorites.$ids
            .sink { [weak self] ids in
                self?.state.favoriteIds = ids
            }
            .store(in: &subscriptions)
    }

    // MARK: - Chargement

    func loadIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load()
    }

    /// Fiche, puis première page de la vitrine et avis. Tâche du ViewModel : ouvrir une annonce pendant le
    /// chargement ne l'interrompt pas.
    func load() async {
        loadTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    /// Tirer pour rafraîchir : fiche et avis relus ; la première page REMPLACE le début de la vitrine et les pages
    /// déjà chargées restent (la position de lecture n'est pas perdue — `Paging.mergeFirstPage`).
    func refresh() async {
        guard state.seller != nil else {
            await load()
            return
        }
        do {
            let seller = try await sellers.profile(id: sellerId)
            state.seller = seller
            async let firstPage: Void = mergeFirstPage()
            async let sellerReviews: Void = loadReviews()
            _ = await (firstPage, sellerReviews)
        } catch {
            if let message = ErrorMapper.message(for: error) {
                state.notice = message
            }
        }
    }

    /// Page suivante, quand la fin de la vitrine approche.
    func loadMore() async {
        guard state.hasMore, !state.isLoadingMore, !state.isLoading else { return }
        state.isLoadingMore = true
        await loadPage(state.page + 1)
    }

    private func performLoad() async {
        var next = state
        next.isLoading = true
        next.errorMessage = nil
        state = next
        do {
            let seller = try await sellers.profile(id: sellerId)
            guard !Task.isCancelled else { return }
            next = state
            next.seller = seller
            next.isLoading = false
            state = next
            async let firstPage: Void = loadPage(1)
            async let sellerReviews: Void = loadReviews()
            _ = await (firstPage, sellerReviews)
        } catch {
            // 404 `userNotFound` : compte banni ou supprimé. La vitrine n'est pas demandée.
            guard let message = ErrorMapper.message(for: error) else { return }
            next = state
            next.isLoading = false
            next.errorMessage = message
            state = next
        }
    }

    /// Une page de la vitrine ; un échec laisse la fiche affichée et arrête simplement la pagination.
    private func loadPage(_ page: Int) async {
        do {
            let result = try await sellers.listings(id: sellerId, page: page)
            var next = state
            if page == 1 {
                next.items = result.items
            } else {
                // Pagination par décalage : une annonce publiée entre deux pages ramène la dernière de la page N en
                // tête de la page N+1 — le même identifiant deux fois casserait la liste.
                let known = Set(next.items.map { $0.id })
                next.items += result.items.filter { !known.contains($0.id) }
            }
            next.total = result.total
            next.page = result.page
            next.hasMore = result.hasMore
            next.isLoadingMore = false
            state = next
        } catch {
            var next = state
            next.isLoadingMore = false
            next.hasMore = false
            state = next
        }
    }

    private func mergeFirstPage() async {
        guard let result = try? await sellers.listings(id: sellerId, page: 1) else { return }
        var next = state
        next.items = Paging.mergeFirstPage(current: next.items, fresh: result.items) { $0.id }
        next.total = result.total
        if next.page <= 1 {
            next.page = result.page
            next.hasMore = result.hasMore
        }
        state = next
    }

    /// Avis reçus, puis mon droit de noter (Android : `loadReviews`) ; deux échecs sans conséquence (section ou bouton
    /// masqués).
    private func loadReviews() async {
        if let summary = try? await reviewsRepository.forSeller(sellerId, limit: Self.reviewsShown) {
            state.reviews = summary
        }
        await loadEligibility()
    }

    /// Mon droit de noter ce vendeur, et si je l'ai déjà noté. Visiteur ou mon propre profil : aucune requête, pas de
    /// bouton. Échec silencieux : le bouton reste tel quel.
    private func loadEligibility() async {
        guard state.asksReviewEligibility else {
            if state.canReview || state.hasMyReview {
                var next = state
                next.canReview = false
                next.hasMyReview = false
                state = next
            }
            return
        }
        guard let eligibility = try? await reviewsRepository.eligibility(sellerId: sellerId) else { return }
        var next = state
        next.canReview = eligibility.canReview
        next.hasMyReview = eligibility.existing != nil
        state = next
    }

    /// Connexion ou déconnexion pendant que le profil est affiché : le droit de noter se relit (Android :
    /// `refreshEligibility`, après une connexion faite depuis ce profil) ou s'efface.
    private func sessionChanged(_ userId: String) {
        guard userId != state.userId else { return }
        state.userId = userId
        // Profil pas encore chargé : le chargement en cours lira la nouvelle session.
        guard state.seller != nil else { return }
        eligibilityTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.loadEligibility()
        }
        eligibilityTask = task
    }

    // MARK: - Laisser un avis

    /// « Laisser un avis » / « Modifier mon avis » : mon avis courant est relu d'abord — la feuille sert aussi à le
    /// corriger, et ouverte vide elle ÉCRASERAIT l'avis existant (le serveur fait un upsert) : en cas d'échec, le
    /// message plutôt que la feuille (Android : `openReviewDialog`).
    func openReview() async {
        guard state.canReview, !state.isReviewOpening, !state.isReviewBusy, !isReviewPresented else { return }
        state.isReviewOpening = true
        do {
            let eligibility = try await reviewsRepository.eligibility(sellerId: sellerId)
            var next = state
            next.isReviewOpening = false
            next.canReview = eligibility.canReview
            next.hasMyReview = eligibility.existing != nil
            guard eligibility.canReview else {
                // Droit perdu depuis le chargement (blocage…) : le bouton disparaît, la raison s'affiche.
                next.notice = L10n.errorReviewNotEligible
                state = next
                return
            }
            next.isReviewEditing = eligibility.existing != nil
            next.reviewError = nil
            state = next
            reviewRating = RepositorySupport.clamp(eligibility.existing?.rating ?? Self.defaultRating, 1, RatingStarSymbols.maxStars)
            reviewComment = eligibility.existing?.comment ?? ""
            isReviewPresented = true
        } catch {
            var next = state
            next.isReviewOpening = false
            if let message = ErrorMapper.message(for: error) {
                next.notice = message
            }
            state = next
        }
    }

    /// « Annuler » ou glissement : la saisie est abandonnée (la prochaine ouverture repart de mon avis courant).
    func dismissReview() {
        guard !state.isReviewBusy else { return }
        isReviewPresented = false
        if state.reviewError != nil {
            state.reviewError = nil
        }
    }

    /// Envoi (`POST /api/reviews`). Verdict du serveur (403 `notEligible` / `emailNotVerified` / `userBlocked`, 400
    /// `ownReviewError`…) : la feuille se ferme, le message s'affiche sur le profil. Panne réseau : elle reste ouverte
    /// avec le message, l'avis rédigé n'est pas perdu (Android : `confirmReview`).
    func confirmReview() async {
        guard isReviewPresented, !state.isReviewBusy else { return }
        var next = state
        next.isReviewBusy = true
        next.reviewError = nil
        state = next
        do {
            try await reviewsRepository.submit(sellerId: sellerId, rating: reviewRating, comment: reviewComment)
            next = state
            next.isReviewBusy = false
            next.canReview = true
            next.hasMyReview = true
            next.notice = L10n.reviewSent
            state = next
            isReviewPresented = false
            await reloadAfterReview()
        } catch {
            next = state
            next.isReviewBusy = false
            guard let message = ErrorMapper.message(for: error) else {
                state = next
                return
            }
            if error is APIError {
                next.notice = message
                state = next
                isReviewPresented = false
            } else {
                next.reviewError = message
                state = next
            }
        }
    }

    /// La note du vendeur et ses avis viennent d'être recalculés par le serveur ; deux échecs sans conséquence. Mon
    /// droit de noter n'est pas relu : l'envoi vient de le prouver.
    private func reloadAfterReview() async {
        if let seller = try? await sellers.profile(id: sellerId) {
            state.seller = seller
        }
        if let summary = try? await reviewsRepository.forSeller(sellerId, limit: Self.reviewsShown) {
            state.reviews = summary
        }
    }

    #if DEBUG
    /// Tour de captures (Debug, API simulée) : `-WeydaReviewDemo open` ouvre la feuille une fois le profil chargé ;
    /// `filled` la remplit aussi (4 étoiles et un commentaire FICTIF dans la langue de l'app), sans clavier.
    func showReviewDemo(_ demo: String) async {
        await openReview()
        guard demo == "filled", isReviewPresented else { return }
        reviewRating = 4
        reviewComment = SellerReviewDemo.comment(language: WeydaLocale.language)
    }
    #endif

    // MARK: - Favoris

    func toggleFavorite(_ listing: Listing) async {
        do {
            _ = try await favorites.toggle(listing.id)
        } catch {
            if let message = ErrorMapper.message(for: error) {
                state.notice = message
            }
        }
    }

    // MARK: - Signaler / bloquer (contenu publié par les utilisateurs : exigence des magasins d'applications)

    func openReport() {
        guard state.canModerate else { return }
        state.reportError = nil
        isReportPresented = true
    }

    /// Verdict du serveur (envoyé, déjà signalé, refus) : la feuille se ferme, le message s'affiche sur le profil.
    /// Panne réseau : elle reste ouverte, les précisions saisies ne sont pas perdues.
    func confirmReport(reason: ReportReason, details: String) async {
        guard !state.isReportBusy else { return }
        state.isReportBusy = true
        state.reportError = nil
        do {
            try await reports.reportUser(userId: sellerId, conversationId: nil, reason: reason, details: details)
            state.isReportBusy = false
            isReportPresented = false
            state.notice = L10n.reportSent
        } catch {
            state.isReportBusy = false
            guard let message = ErrorMapper.message(for: error) else { return }
            if error is APIError {
                isReportPresented = false
                state.notice = message
            } else {
                state.reportError = message
            }
        }
    }

    /// « Bloquer » demande confirmation ; « Débloquer » agit tout de suite (comme Android).
    func requestBlock() {
        guard state.canModerate else { return }
        isBlockConfirmPresented = true
    }

    func setBlocked(_ blocked: Bool) async {
        guard !state.isBlockBusy else { return }
        state.isBlockBusy = true
        do {
            try await conversations.setBlocked(userId: sellerId, blocked: blocked)
            var next = state
            next.isBlockBusy = false
            next.isBlocked = blocked
            next.notice = blocked ? L10n.chatBlockedDone : L10n.chatUnblockedDone
            state = next
        } catch {
            var next = state
            next.isBlockBusy = false
            next.notice = ErrorMapper.message(for: error) ?? next.notice
            state = next
        }
    }

    // MARK: - Messages brefs

    func noticeShown() {
        state.notice = nil
    }
}

#if DEBUG
/// Commentaire FICTIF de la feuille remplie du tour de captures (`-WeydaReviewDemo filled`) : un contenu saisi par un
/// membre, pas un texte de l'interface — d'où une phrase par langue ici plutôt qu'une clé du catalogue.
nonisolated enum SellerReviewDemo {
    static func comment(language: String) -> String {
        switch language {
        case "ar": "بائع دقيق في الموعد ومتعاون، والسلعة مطابقة للإعلان. أنصح بالتعامل معه."
        case "en": "Punctual and helpful seller, the item matched the listing. Recommended."
        default: "Vendeur ponctuel et arrangeant, l'article était conforme à l'annonce. Je recommande."
        }
    }
}
#endif
