import Combine
import Foundation

/// État du profil public d'un vendeur — `SellerUiState` (SellerViewModel.kt), sans la boîte « Laisser un avis »
/// (phase 6). Données pures.
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

    var isLoggedIn: Bool { !TextCheck.isBlank(userId) }

    /// Mon propre profil : ni signalement ni blocage.
    var isOwnProfile: Bool { isLoggedIn && userId == sellerId }

    /// Menu « Signaler / Bloquer » offert.
    var canModerate: Bool { seller != nil && !isOwnProfile }
}

/// Profil public d'un vendeur — portage de `SellerViewModel` (Android), comme `/[locale]/profil/[id]` : sa fiche,
/// sa vitrine paginée et ses avis ; signaler ou bloquer cet utilisateur. « Laisser un avis » arrive en phase 6.
final class SellerViewModel: ObservableObject {
    /// Avis montrés sur le profil (Android : REVIEWS_SHOWN).
    static let reviewsShown = 5

    @Published private(set) var state = SellerState()
    /// Feuille « Signaler cet utilisateur » ouverte.
    @Published var isReportPresented: Bool = false
    /// Confirmation « Bloquer cet utilisateur » affichée.
    @Published var isBlockConfirmPresented: Bool = false

    let sellerId: String

    private let sellers: SellerRepository
    private let favorites: FavoritesRepository
    private let reviewsRepository: ReviewsRepository
    private let reports: ReportsRepository
    private let conversations: ConversationsRepository
    private var subscriptions: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?
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
                self?.state.userId = userId
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

    /// Avis reçus ; un échec est sans conséquence (section masquée).
    private func loadReviews() async {
        guard let summary = try? await reviewsRepository.forSeller(sellerId, limit: Self.reviewsShown) else { return }
        state.reviews = summary
    }

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
