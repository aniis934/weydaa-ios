import Foundation

/// Action à confirmer (boîte de dialogue) avant l'appel au serveur — `ListingAction` (Android). Les boutons
/// arrivent avec la phase 4 ; la logique, portée d'Android avec ses tests, est déjà là.
nonisolated enum MyListingAction: Hashable, Sendable {
    case markSold(Listing)
    case delete(Listing)

    var listing: Listing {
        switch self {
        case .markSold(let listing), .delete(let listing):
            return listing
        }
    }
}

/// État de « Mes annonces » — portage de `MyListingsUiState`.
nonisolated struct MyListingsState: Equatable, Sendable {
    /// Onglet de statut choisi (nil = toutes).
    var filter: ListingStatus? = nil
    var items: [Listing] = []
    var total: Int = 0
    var page: Int = 1
    var totalPages: Int = 1
    var isLoading: Bool = true
    var isLoadingMore: Bool = false
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    var errorMessage: String? = nil
    /// Annonce dont une action (vendu / suppression / renouvellement) est en cours.
    var busyId: String? = nil
    /// Confirmation demandée (nil = aucune boîte de dialogue).
    var pendingAction: MyListingAction? = nil
    /// Message transitoire, effacé par `noticeShown()`.
    var notice: String? = nil

    var canLoadMore: Bool { page < totalPages && !isLoading && !isLoadingMore }
}

/// Annonces du membre par statut, pagination, rechargement silencieux au retour sur l'écran — portage de
/// `MyListingsViewModel`. Chaque action renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les tests
/// l'attendent.
final class MyListingsViewModel: ObservableObject {
    @Published private(set) var state = MyListingsState()

    private let users: UserRepository
    private let annonces: AnnonceRepository
    private let now: () -> Date
    private var loadTask: Task<Void, Never>?
    /// Page suivante ou rechargement silencieux en vol : annulés par `load`, ils appartiennent à l'ancien filtre.
    private var secondaryTask: Task<Void, Never>?
    private var hasAppeared = false
    private var hasLoaded = false

    init(users: UserRepository, annonces: AnnonceRepository, now: @escaping () -> Date = { Date() }) {
        self.users = users
        self.annonces = annonces
        self.now = now
    }

    /// Apparition de l'écran : premier chargement, puis rechargement silencieux à chaque retour (une fiche
    /// ouverte depuis la liste a pu changer de statut) — `LifecycleResumeEffect` d'Android.
    @discardableResult
    func appear() -> Task<Void, Never>? {
        guard hasAppeared else {
            hasAppeared = true
            return load()
        }
        return refresh()
    }

    /// Rechargement silencieux, ignoré tant que le premier chargement n'est pas fini. La première page relue
    /// remplace le début de la liste : les pages suivantes déjà chargées restent, la position de défilement aussi.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        refresh(pulled: false)
    }

    /// Tirer pour rafraîchir : même rechargement, avec un message en cas d'échec.
    func pullToRefresh() async {
        await refresh(pulled: true)?.value
    }

    @discardableResult
    func setFilter(_ status: ListingStatus?) -> Task<Void, Never>? {
        guard state.filter != status else { return nil }
        state.filter = status
        return load()
    }

    @discardableResult
    func load() -> Task<Void, Never> {
        loadTask?.cancel()
        secondaryTask?.cancel()
        state.isLoading = true
        state.isLoadingMore = false
        state.isRefreshing = false
        state.errorMessage = nil
        state.items = []
        state.page = 1
        let filter = state.filter
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.users.myListings(status: filter, page: 1)
                guard !Task.isCancelled else { return }
                self.hasLoaded = true
                self.state.isLoading = false
                self.state.items = page.items
                self.state.total = page.total
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

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        let current = state
        guard current.canLoadMore else { return nil }
        state.isLoadingMore = true
        let filter = current.filter
        let next = current.page + 1
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.users.myListings(status: filter, page: next)
                guard !Task.isCancelled else { return }
                // Pagination par décalage : une annonce déposée entre deux pages ramène la dernière de la page N
                // en tête de N+1 — deux fois le même identifiant casserait la liste.
                let known = Set(self.state.items.map(\.id))
                self.state.isLoadingMore = false
                self.state.items += page.items.filter { !known.contains($0.id) }
                self.state.page = page.page
                self.state.totalPages = page.totalPages
                self.state.total = page.total
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoadingMore = false
                self.state.notice = ErrorMapper.message(for: error)
            }
        }
        secondaryTask = task
        return task
    }

    // MARK: - Actions (boutons : phase 4)

    func askMarkSold(_ listing: Listing) {
        state.pendingAction = .markSold(listing)
    }

    func askDelete(_ listing: Listing) {
        state.pendingAction = .delete(listing)
    }

    func dismissAction() {
        state.pendingAction = nil
    }

    func noticeShown() {
        state.notice = nil
    }

    @discardableResult
    func confirmAction() -> Task<Void, Never>? {
        guard let action = state.pendingAction else { return nil }
        state.pendingAction = nil
        switch action {
        case .markSold(let listing):
            return markSold(listing)
        case .delete(let listing):
            return delete(listing)
        }
    }

    /// Expirée (ou active à moins de 7 jours de l'échéance), 3 fois au plus : de nouveau en ligne pour 60 jours.
    @discardableResult
    func renew(_ listing: Listing) -> Task<Void, Never>? {
        guard beginAction(on: listing) else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            do {
                let remaining = try await self.annonces.renew(id: listing.id)
                var renewed = listing
                renewed.status = ListingStatus.active.rawValue
                renewed.renewalCount = remaining.map { Listing.maxRenewals - $0 } ?? (listing.renewalCount + 1)
                renewed.expiresAt = self.now().addingTimeInterval(60 * 24 * 3600)
                self.replace(listing.id, with: renewed)
                self.endAction(notice: L10n.myListingRenewed)
            } catch {
                self.endAction(failure: error)
            }
        }
    }

    // MARK: - Interne

    private func refresh(pulled: Bool) -> Task<Void, Never>? {
        let current = state
        guard !current.isLoading, !current.isLoadingMore, !current.isRefreshing, current.busyId == nil, hasLoaded else {
            return nil
        }
        if pulled {
            state.isRefreshing = true
        }
        let filter = current.filter
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.users.myListings(status: filter, page: 1)
                guard !Task.isCancelled else { return }
                let keepTail = self.state.items.count > page.items.count
                self.state.isRefreshing = false
                self.state.items = Paging.mergeFirstPage(current: self.state.items, fresh: page.items, id: { $0.id })
                self.state.total = page.total
                if !keepTail {
                    self.state.page = page.page
                }
                self.state.totalPages = page.totalPages
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isRefreshing = false
                if pulled, let message = ErrorMapper.message(for: error) {
                    self.state.notice = message
                }
            }
        }
        secondaryTask = task
        return task
    }

    /// Vendu : seul le statut est repris — la réponse du PUT ne porte ni catégorie, ni ville, ni modération, la
    /// recopier telle quelle viderait la ligne.
    private func markSold(_ listing: Listing) -> Task<Void, Never>? {
        guard beginAction(on: listing) else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.annonces.markSold(id: listing.id)
                var sold = self.state.items.first { $0.id == listing.id } ?? listing
                sold.status = updated.status
                self.replace(listing.id, with: sold)
                self.endAction(notice: L10n.myListingSoldDone)
            } catch {
                self.endAction(failure: error)
            }
        }
    }

    private func delete(_ listing: Listing) -> Task<Void, Never>? {
        guard beginAction(on: listing) else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.annonces.delete(id: listing.id)
                self.state.items.removeAll { $0.id == listing.id }
                self.state.total = max(self.state.total - 1, 0)
                self.endAction(notice: L10n.myListingDeleted)
            } catch {
                self.endAction(failure: error)
            }
        }
    }

    /// Une action à la fois ; le message précédent s'efface.
    private func beginAction(on listing: Listing) -> Bool {
        guard state.busyId == nil else { return false }
        state.busyId = listing.id
        state.notice = nil
        return true
    }

    private func endAction(notice: String) {
        state.notice = notice
        state.busyId = nil
    }

    /// L'échec devient un message transitoire, la liste reste affichée.
    private func endAction(failure: any Error) {
        if let message = ErrorMapper.message(for: failure) {
            state.notice = message
        }
        state.busyId = nil
    }

    private func replace(_ id: String, with listing: Listing) {
        state.items = state.items.map { $0.id == id ? listing : $0 }
    }
}
