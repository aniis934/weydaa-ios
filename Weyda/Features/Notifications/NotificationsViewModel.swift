import Combine
import Foundation

/// État de la cloche — portage de `NotificationsUiState` (NotificationsViewModel.kt).
nonisolated struct NotificationsState: Equatable, Sendable {
    var items: [AppNotification] = []
    var isLoading: Bool = true
    var isLoadingMore: Bool = false
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    var hasMore: Bool = false
    /// Non lues (serveur, puis tenu à jour localement : ouverture, suppression, « tout lu », temps réel).
    var unreadCount: Int = 0
    /// Erreur du chargement complet (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    /// Message bref (échec d'une action ou d'une page suivante), effacé par `noticeShown()`.
    var notice: String? = nil
}

/// Écran à ouvrir pour la cible d'une notification (`AppNotification.target`, déduite de son `url`) — la
/// navigation de `NotificationsRoute` (Android). Logique pure, testable.
nonisolated enum NotificationsNavigation {
    static func route(for target: NotificationTarget) -> AppRoute {
        switch target {
        case .listing(let idOrSlug):
            return .detail(idOrSlug: idOrSlug)
        case .conversation(let id):
            return .chat(conversationId: id, archived: false)
        case .seller(let id):
            return .seller(id: id)
        case .myListings:
            return .myListings
        }
    }
}

/// Cloche — portage de `NotificationsViewModel` : liste paginée (`GET /api/notifications`), tout marquer comme lu,
/// marquer / supprimer une notification (optimistes, retour arrière ciblé), notifications reçues en direct
/// (`NotificationsRepository.incoming`) placées en tête sans rechargement. Chaque action renvoie sa tâche
/// (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var state = NotificationsState()

    /// Chargement, relecture ou page suivante en vol (une seule à la fois).
    private(set) var listTask: Task<Void, Never>?

    private let notifications: NotificationsRepository
    /// Dernière page chargée.
    private var page = 1
    private var hasAppeared = false
    private var hasLoaded = false
    private var wasOffline = false
    private var subscriptions: Set<AnyCancellable> = []

    /// - Parameter online: connectivité (`connectivity.$isOnline`) ; rien = pas de relance automatique (tests).
    init(
        notifications: NotificationsRepository,
        online: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher()
    ) {
        self.notifications = notifications
        notifications.incoming
            .sink { [weak self] notification in
                self?.receive(notification)
            }
            .store(in: &subscriptions)
        online
            .removeDuplicates()
            .sink { [weak self] isOnline in
                self?.connectivityChanged(isOnline: isOnline)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Chargement

    /// Premier affichage : chargement ; retour sur l'écran (fiche, fil ouvert depuis une notification) : relecture
    /// silencieuse — le serveur marque lues les notifications MESSAGE d'un fil ouvert.
    @discardableResult
    func appear() -> Task<Void, Never>? {
        guard hasAppeared else {
            hasAppeared = true
            return load()
        }
        return refresh(pulled: false)
    }

    @discardableResult
    func load() -> Task<Void, Never> {
        listTask?.cancel()
        state.isLoading = true
        state.isLoadingMore = false
        state.isRefreshing = false
        state.errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.notifications.page(page: 1)
                guard !Task.isCancelled else { return }
                self.page = 1
                self.hasLoaded = true
                self.state.isLoading = false
                self.state.items = result.items
                self.state.hasMore = result.hasMore
                self.state.unreadCount = result.unreadCount
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.errorMessage = ErrorMapper.message(for: error) ?? L10n.errorGeneric
            }
        }
        listTask = task
        return task
    }

    /// Tirer pour rafraîchir : première page relue, pages suivantes déjà chargées gardées.
    func pullToRefresh() async {
        guard hasLoaded else {
            await load().value
            return
        }
        await refresh(pulled: true)?.value
    }

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        let current = state
        guard current.hasMore, !current.isLoading, !current.isLoadingMore, !current.isRefreshing else { return nil }
        state.isLoadingMore = true
        let next = page + 1
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.notifications.page(page: next)
                guard !Task.isCancelled else { return }
                self.page = result.page
                // Pagination par décalage : une notification arrivée entre deux pages décale la suivante.
                let known: Set<String> = Set(self.state.items.map { $0.id })
                self.state.isLoadingMore = false
                self.state.items += result.items.filter { !known.contains($0.id) }
                self.state.hasMore = result.hasMore
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoadingMore = false
                self.state.notice = ErrorMapper.message(for: error)
            }
        }
        listTask = task
        return task
    }

    // MARK: - Actions

    /// « Tout marquer comme lu », optimiste : les pastilles disparaissent tout de suite, le serveur suit. Refus :
    /// retour arrière CIBLÉ (pas d'instantané) — les lignes supprimées ou arrivées entre-temps restent.
    @discardableResult
    func markAllRead() -> Task<Void, Never>? {
        guard state.unreadCount > 0 else { return nil }
        let unreadIds: Set<String> = Set(state.items.filter { !$0.read }.map { $0.id })
        state.items = state.items.map { (item: AppNotification) -> AppNotification in
            var read = item
            read.read = true
            return read
        }
        state.unreadCount = 0
        return Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.notifications.markAllRead()
            } catch {
                let restored: [AppNotification] = self.state.items.map { (item: AppNotification) -> AppNotification in
                    guard unreadIds.contains(item.id) else { return item }
                    var unread = item
                    unread.read = false
                    return unread
                }
                self.state.items = restored
                self.state.unreadCount = restored.filter { !$0.read }.count
                if let message = ErrorMapper.message(for: error) {
                    self.state.notice = message
                }
            }
        }
    }

    /// Ouverture : la notification est marquée lue si besoin (une seule fois) ; l'écran ouvre sa cible.
    @discardableResult
    func open(_ notification: AppNotification) -> Task<Void, Never>? {
        // L'état de la liste fait foi (« tout lu » a pu passer depuis l'affichage de la ligne).
        let current: AppNotification = state.items.first(where: { $0.id == notification.id }) ?? notification
        guard !current.read else { return nil }
        let id = current.id
        state.items = state.items.map { (item: AppNotification) -> AppNotification in
            guard item.id == id else { return item }
            var read = item
            read.read = true
            return read
        }
        state.unreadCount = max(state.unreadCount - 1, 0)
        return Task { [weak self] in
            guard let self else { return }
            // Échec ignoré, comme Android : la pastille du serveur se recale au prochain chargement.
            _ = try? await self.notifications.markRead(id: id)
        }
    }

    /// Suppression optimiste ; refus : seule CETTE ligne revient, à sa place (restaurer un instantané ferait
    /// réapparaître une autre notification supprimée entre-temps et disparaître celles arrivées en direct).
    @discardableResult
    func delete(_ notification: AppNotification) -> Task<Void, Never>? {
        guard let position = state.items.firstIndex(where: { $0.id == notification.id }) else { return nil }
        let removed = state.items[position]
        let wasUnread = !removed.read
        state.items.remove(at: position)
        if wasUnread {
            state.unreadCount = max(state.unreadCount - 1, 0)
        }
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.notifications.delete(id: removed.id, wasUnread: wasUnread)
            } catch {
                if !self.state.items.contains(where: { $0.id == removed.id }) {
                    self.state.items.insert(removed, at: min(position, self.state.items.count))
                    if wasUnread {
                        self.state.unreadCount += 1
                    }
                }
                if let message = ErrorMapper.message(for: error) {
                    self.state.notice = message
                }
            }
        }
    }

    func noticeShown() {
        state.notice = nil
    }

    // MARK: - Interne

    /// Relecture de la première page : `pulled` = tirer pour rafraîchir (indicateur, message en cas d'échec).
    private func refresh(pulled: Bool) -> Task<Void, Never>? {
        let current = state
        guard hasLoaded, !current.isLoading, !current.isLoadingMore, !current.isRefreshing else { return nil }
        if pulled {
            state.isRefreshing = true
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.notifications.page(page: 1)
                guard !Task.isCancelled else { return }
                let keepTail = self.state.items.count > result.items.count
                if !keepTail {
                    self.page = 1
                    self.state.hasMore = result.hasMore
                }
                self.state.items = Paging.mergeFirstPage(current: self.state.items, fresh: result.items, id: { $0.id })
                self.state.isRefreshing = false
                self.state.errorMessage = nil
                self.state.unreadCount = result.unreadCount
            } catch {
                self.state.isRefreshing = false
                guard !Task.isCancelled else { return }
                if pulled, let message = ErrorMapper.message(for: error) {
                    self.state.notice = message
                }
            }
        }
        listTask = task
        return task
    }

    /// Notification reçue en direct : en tête, une seule fois (la pastille du repository, elle, compte chaque trame).
    private func receive(_ notification: AppNotification) {
        guard !state.items.contains(where: { $0.id == notification.id }) else { return }
        state.items.insert(notification, at: 0)
        state.unreadCount += 1
    }

    /// Retour du réseau : un écran resté en erreur (rien d'affiché) se recharge de lui-même.
    private func connectivityChanged(isOnline: Bool) {
        let reconnected = isOnline && wasOffline
        wasOffline = !isOnline
        guard reconnected, state.errorMessage != nil, state.items.isEmpty else { return }
        load()
    }
}
