import Foundation

/// État de « Utilisateurs bloqués » (propre à iOS : App Store Guideline 1.2 — l'utilisateur doit pouvoir revoir
/// et lever ses blocages ; l'écran n'existe pas sur Android).
nonisolated struct BlockedUsersState: Equatable, Sendable {
    var items: [BlockedUser] = []
    var page: Int = 1
    var totalPages: Int = 1
    var isLoading: Bool = true
    var isLoadingMore: Bool = false
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    /// Erreur du chargement complet (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    /// Utilisateur en cours de déblocage (indicateur sur sa ligne, boutons des autres désactivés).
    var busyId: String? = nil
    /// Déblocage à confirmer (nil = aucune boîte de dialogue).
    var pendingUnblock: BlockedUser? = nil
    /// Bannière brève (débloqué : succès ; échec : erreur), effacée par `noticeShown()`.
    var banner: WeydaBanner? = nil

    var canLoadMore: Bool { page < totalPages && !isLoading && !isLoadingMore }

    /// Texte de la bannière (nil = aucune).
    var notice: String? { banner?.message }
}

/// Utilisateurs que j'ai bloqués (`GET /api/users/me/blocked`, lot serveur B), page par page ; « Débloquer » après
/// confirmation (`DELETE /api/users/{id}/block`) retire la ligne. Chaque action renvoie sa tâche
/// (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
final class BlockedUsersViewModel: ObservableObject {
    static let pageSize = 20

    @Published private(set) var state = BlockedUsersState()

    private let conversations: ConversationsRepository
    private var loadTask: Task<Void, Never>?
    private var hasAppeared = false

    init(conversations: ConversationsRepository) {
        self.conversations = conversations
    }

    /// Premier affichage seulement : l'écran n'ouvre rien d'où l'on reviendrait avec une liste changée.
    @discardableResult
    func appear() -> Task<Void, Never>? {
        guard !hasAppeared else { return nil }
        hasAppeared = true
        return load()
    }

    @discardableResult
    func load() -> Task<Void, Never> {
        loadTask?.cancel()
        state.isLoading = true
        state.isLoadingMore = false
        state.isRefreshing = false
        state.errorMessage = nil
        let limit = Self.pageSize
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.conversations.blockedUsers(page: 1, limit: limit)
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.items = page.items
                self.state.page = page.page
                self.state.totalPages = page.totalPages
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.errorMessage = ErrorMapper.message(for: error) ?? L10n.errorGeneric
            }
        }
        loadTask = task
        return task
    }

    /// Tirer pour rafraîchir : la première page remplace la liste ; un échec laisse la liste et donne un message.
    func pullToRefresh() async {
        let current = state
        guard !current.isLoading, !current.isLoadingMore, !current.isRefreshing, current.busyId == nil else { return }
        guard current.errorMessage == nil else {
            await load().value
            return
        }
        state.isRefreshing = true
        do {
            let page = try await conversations.blockedUsers(page: 1, limit: Self.pageSize)
            state.items = page.items
            state.page = page.page
            state.totalPages = page.totalPages
        } catch {
            if let message = ErrorMapper.message(for: error) {
                state.banner = AccountBanner.failure(message)
            }
        }
        state.isRefreshing = false
    }

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        let current = state
        guard current.canLoadMore, !current.isRefreshing else { return nil }
        state.isLoadingMore = true
        let next = current.page + 1
        let limit = Self.pageSize
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.conversations.blockedUsers(page: next, limit: limit)
                guard !Task.isCancelled else { return }
                // Pagination par décalage : un déblocage entre deux pages décale la suivante, sans doublon.
                let known: Set<String> = Set(self.state.items.map { $0.id })
                self.state.isLoadingMore = false
                self.state.items += page.items.filter { !known.contains($0.id) }
                self.state.page = page.page
                self.state.totalPages = page.totalPages
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoadingMore = false
                self.state.banner = ErrorMapper.message(for: error).map { AccountBanner.failure($0) }
            }
        }
        loadTask = task
        return task
    }

    // MARK: - Déblocage

    func askUnblock(_ user: BlockedUser) {
        guard state.busyId == nil else { return }
        state.pendingUnblock = user
    }

    func dismissUnblock() {
        state.pendingUnblock = nil
    }

    /// Déblocage confirmé : la ligne part, « Utilisateur débloqué » ; refus du serveur : la ligne reste, le message
    /// d'erreur s'affiche. Une liste vidée alors qu'il reste des pages se recharge.
    @discardableResult
    func confirmUnblock() -> Task<Void, Never>? {
        guard let user = state.pendingUnblock else { return nil }
        state.pendingUnblock = nil
        guard state.busyId == nil else { return nil }
        state.busyId = user.id
        state.banner = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.conversations.setBlocked(userId: user.id, blocked: false)
                self.state.items.removeAll { $0.id == user.id }
                self.state.banner = AccountBanner.success(L10n.chatUnblockedDone)
                self.state.busyId = nil
                if self.state.items.isEmpty && self.state.page < self.state.totalPages {
                    self.load()
                }
            } catch {
                self.state.busyId = nil
                if let message = ErrorMapper.message(for: error) {
                    self.state.banner = AccountBanner.failure(message)
                }
            }
        }
    }

    func noticeShown() {
        state.banner = nil
    }
}
