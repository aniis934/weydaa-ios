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
    /// Bannière du bas : « Notification supprimée » + « Annuler », échec d'une action, d'une page suivante ou d'un
    /// rafraîchissement ; effacée par `bannerDismissed()`.
    var banner: WeydaBanner? = nil
}

/// Suppression en attente (« Annuler » encore possible) : la notification, sa place et son état « non lu ».
private nonisolated struct DeferredNotificationDeletion: Sendable {
    let notification: AppNotification
    let index: Int
    let wasUnread: Bool
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
/// marquer une notification (optimiste, retour arrière ciblé), suppression DIFFÉRÉE avec « Annuler » (l'API n'a pas
/// d'inverse : la rangée part et le compteur baisse tout de suite, la requête part à la fermeture de la bannière, à la
/// suppression suivante ou en quittant l'écran), notifications reçues en direct (`NotificationsRepository.incoming`)
/// placées en tête sans rechargement. Chaque action renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les
/// tests l'attendent.
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var state = NotificationsState()

    /// Préfixe de l'action « Annuler » d'une suppression : `notification:<id>`.
    static let undoPrefix = "notification:"

    /// Chargement, relecture ou page suivante en vol (une seule à la fois).
    private(set) var listTask: Task<Void, Never>?

    private let notifications: NotificationsRepository
    /// Dernière page chargée.
    private var page = 1
    private var hasAppeared = false
    private var hasLoaded = false
    private var wasOffline = false
    private var subscriptions: Set<AnyCancellable> = []
    /// Suppressions en attente ou envoyées et pas encore confirmées : ni une relecture ni le temps réel ne doivent
    /// rendre leur rangée.
    private var pendingDeletions: Set<String> = []
    /// Suppression que la bannière propose encore d'annuler (pas encore envoyée).
    private var deferred: DeferredNotificationDeletion?

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
                self.state.items = self.shown(result.items)
                self.state.hasMore = result.hasMore
                self.state.unreadCount = self.unreadExcludingDeferred(result.unreadCount)
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
                self.state.items += self.shown(result.items).filter { !known.contains($0.id) }
                self.state.hasMore = result.hasMore
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoadingMore = false
                self.showError(error)
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
        // La suppression en attente vise désormais une notification lue : « Annuler » la remet lue, et l'envoi ne
        // baissera pas la pastille une seconde fois.
        if let pending = deferred, pending.wasUnread {
            var read = pending.notification
            read.read = true
            deferred = DeferredNotificationDeletion(notification: read, index: pending.index, wasUnread: false)
        }
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
                self.showError(error)
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

    /// Glisser → « Supprimer » : la ligne part et le compteur de l'écran baisse tout de suite, la bannière
    /// « Notification supprimée » propose « Annuler ». La requête n'est PAS encore envoyée (l'API n'a pas d'inverse) :
    /// elle part à la fermeture de la bannière, à la suppression suivante (renvoyée ici : la suppression précédente,
    /// envoyée maintenant) ou en quittant l'écran. La pastille de l'app (`NotificationsRepository.unreadCount`) baisse
    /// à l'envoi, une seule fois (`delete(id:wasUnread:)`).
    @discardableResult
    func delete(_ notification: AppNotification) -> Task<Void, Never>? {
        let previous = commitPendingDeletion()
        guard let position = state.items.firstIndex(where: { $0.id == notification.id }) else { return previous }
        let removed = state.items[position]
        let wasUnread = !removed.read
        state.items.remove(at: position)
        if wasUnread {
            state.unreadCount = max(state.unreadCount - 1, 0)
        }
        pendingDeletions.insert(removed.id)
        deferred = DeferredNotificationDeletion(notification: removed, index: position, wasUnread: wasUnread)
        // Pas de vibration ici : le glissement plein en donne déjà une (UIKit).
        state.banner = InboxBanner.undoable(L10n.notificationDeleted, symbol: "trash", undoId: Self.undoPrefix + removed.id)
        return previous
    }

    /// Action de la bannière. « Annuler » : la suppression en attente est abandonnée, la notification revient à SA
    /// place avec son état « non lu » (rien n'a été envoyé).
    func bannerAction(_ action: BannerAction) {
        state.banner = nil
        guard let pending = deferred, action.id == Self.undoPrefix + pending.notification.id else { return }
        deferred = nil
        pendingDeletions.remove(pending.notification.id)
        putBack(pending)
    }

    /// La bannière s'est fermée (délai écoulé, glissée) : la suppression en attente part au serveur.
    @discardableResult
    func bannerDismissed() -> Task<Void, Never>? {
        state.banner = nil
        return commitPendingDeletion()
    }

    /// L'écran disparaît (retour, notification ouverte, autre onglet) : la suppression en attente part — jamais
    /// perdue — et « Annuler » n'est plus proposé.
    @discardableResult
    func disappear() -> Task<Void, Never>? {
        guard deferred != nil else { return nil }
        if state.banner?.action != nil {
            state.banner = nil
        }
        return commitPendingDeletion()
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
                let fresh: [AppNotification] = self.shown(result.items)
                let keepTail = self.state.items.count > fresh.count
                if !keepTail {
                    self.page = 1
                    self.state.hasMore = result.hasMore
                }
                self.state.items = Paging.mergeFirstPage(current: self.state.items, fresh: fresh, id: { $0.id })
                self.state.isRefreshing = false
                self.state.errorMessage = nil
                self.state.unreadCount = self.unreadExcludingDeferred(result.unreadCount)
            } catch {
                self.state.isRefreshing = false
                guard !Task.isCancelled else { return }
                if pulled {
                    self.showError(error)
                }
            }
        }
        listTask = task
        return task
    }

    /// Notification reçue en direct : en tête, une seule fois (la pastille du repository, elle, compte chaque trame) ;
    /// jamais une notification en cours de suppression.
    private func receive(_ notification: AppNotification) {
        guard !pendingDeletions.contains(notification.id) else { return }
        guard !state.items.contains(where: { $0.id == notification.id }) else { return }
        state.items.insert(notification, at: 0)
        state.unreadCount += 1
    }

    /// Envoie la suppression en attente (s'il y en a une). La tâche tient le repository, pas l'écran : elle aboutit
    /// même si l'écran a disparu entre-temps ; le repository baisse la pastille de l'app si elle n'était pas lue.
    private func commitPendingDeletion() -> Task<Void, Never>? {
        guard let pending = deferred else { return nil }
        deferred = nil
        let repository = notifications
        let id = pending.notification.id
        let wasUnread = pending.wasUnread
        return Task { [weak self] in
            do {
                try await repository.delete(id: id, wasUnread: wasUnread)
                self?.deletionFinished(pending, error: nil)
            } catch {
                self?.deletionFinished(pending, error: error)
            }
        }
    }

    /// Réponse du serveur : succès → rien de plus (« Notification supprimée » a déjà été dit) ; refus → seule CETTE
    /// ligne revient, à sa place, avec le message d'erreur (restaurer un instantané ferait réapparaître une autre
    /// notification supprimée entre-temps et disparaître celles arrivées en direct).
    private func deletionFinished(_ pending: DeferredNotificationDeletion, error: (any Error)?) {
        pendingDeletions.remove(pending.notification.id)
        guard let error else { return }
        putBack(pending)
        showError(error)
    }

    /// La ligne revient à SA place, avec son état « non lu ». Un rechargement a pu la remettre entre-temps : deux fois
    /// le même identifiant ferait planter la liste.
    private func putBack(_ pending: DeferredNotificationDeletion) {
        let id = pending.notification.id
        guard !state.items.contains(where: { $0.id == id }) else { return }
        state.items.insert(pending.notification, at: min(pending.index, state.items.count))
        if pending.wasUnread {
            state.unreadCount += 1
        }
    }

    /// Bannière d'erreur (rien pour une annulation).
    private func showError(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else { return }
        state.banner = InboxBanner.error(message)
    }

    /// Les notifications en cours de suppression ne reviennent pas avec une relecture.
    private func shown(_ items: [AppNotification]) -> [AppNotification] {
        let pending = pendingDeletions
        guard !pending.isEmpty else { return items }
        return items.filter { !pending.contains($0.id) }
    }

    /// Compteur du serveur, moins la suppression en attente (pas encore envoyée) d'une notification non lue.
    private func unreadExcludingDeferred(_ serverCount: Int) -> Int {
        guard let pending = deferred, pending.wasUnread else { return serverCount }
        return max(serverCount - 1, 0)
    }

    /// Retour du réseau : un écran resté en erreur (rien d'affiché) se recharge de lui-même.
    private func connectivityChanged(isOnline: Bool) {
        let reconnected = isOnline && wasOffline
        wasOffline = !isOnline
        guard reconnected, state.errorMessage != nil, state.items.isEmpty else { return }
        load()
    }
}
