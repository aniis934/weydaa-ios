import Combine
import Foundation

/// État de l'onglet Messages — portage de `ConversationsUiState` (ConversationsViewModel.kt), plus les
/// interlocuteurs que j'ai bloqués (App Store 1.2 : leur contenu est masqué dans la liste).
nonisolated struct ConversationsState: Equatable, Sendable {
    var items: [Conversation] = []
    var isLoading: Bool = true
    var isLoadingMore: Bool = false
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    /// Segment courant : boîte de réception (faux) ou archives (vrai).
    var archived: Bool = false
    var hasMore: Bool = false
    /// Utilisateur connecté : décide de l'interlocuteur affiché et de l'état « non lu ».
    var userId: String = ""
    /// Utilisateurs que j'ai bloqués (`GET /api/users/me/blocked`) ; vide tant que la route n'a pas répondu.
    var blockedIds: Set<String> = []
    /// Erreur du chargement complet (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    /// Message bref (archivage, échec d'une page suivante…), effacé par `noticeShown()`.
    var notice: String? = nil

    /// L'interlocuteur de cette conversation est bloqué : son dernier message n'est pas montré.
    func isBlocked(_ conversation: Conversation) -> Bool {
        blockedIds.contains(conversation.partner(userId).id)
    }

    /// Conversations chargées qui répondent à la recherche locale (nom, annonce, dernier message — sauf celui
    /// d'un interlocuteur bloqué, masqué : le chercher ne doit pas le trahir).
    func visibleItems(matching query: String) -> [Conversation] {
        items.filter { conversation in
            ConversationsText.matches(conversation, query: query, userId: userId, isBlocked: isBlocked(conversation))
        }
    }
}

/// Onglet Messages — portage de `ConversationsViewModel` : liste paginée par curseur (`GET /api/conversations`),
/// segment Conversations / Archives, archivage optimiste (`POST` / `DELETE …/archive`), relecture silencieuse au
/// retour sur l'écran et à chaque `conversations.touched` (canal personnel), relance au retour du réseau. Chaque
/// action renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
final class ConversationsViewModel: ObservableObject {
    /// Taille de la liste des bloqués lue avec la liste (une seule page : au-delà, rien n'est masqué de plus).
    static let blockedLimit = 100

    @Published private(set) var state = ConversationsState()

    /// Requête de liste en vol (chargement, rechargement silencieux ou page suivante) — une seule à la fois :
    /// sans cela, la réponse lente de la boîte de réception arrivait après un passage sur « Archives » et
    /// s'affichait DANS les archives, avec le curseur du mauvais segment (Android : `listJob`).
    private(set) var listTask: Task<Void, Never>?

    private let conversations: ConversationsRepository
    private var nextCursor: String?
    private var hasLoadedOnce = false
    private var hasAppeared = false
    /// La première valeur de session est l'état de départ, pas un changement de compte.
    private var sessionKnown = false
    private var wasOffline = false
    private var subscriptions: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - session: utilisateur de la session (`sessionManager.$user`) : un autre compte jette la liste du précédent.
    ///   - online: connectivité (`connectivity.$isOnline`) ; rien = pas de relance automatique (tests).
    init(
        conversations: ConversationsRepository,
        session: AnyPublisher<User?, Never>,
        online: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher()
    ) {
        self.conversations = conversations
        session
            .map { (user: User?) -> String in user?.id ?? "" }
            .removeDuplicates()
            .sink { [weak self] userId in
                self?.sessionChanged(to: userId)
            }
            .store(in: &subscriptions)
        online
            .removeDuplicates()
            .sink { [weak self] isOnline in
                self?.connectivityChanged(isOnline: isOnline)
            }
            .store(in: &subscriptions)
        // Nouveau message ou conversation touchée (canal personnel) : la liste suit sans attendre un retour sur
        // l'écran — l'ordre et les états « non lu » changent sous les yeux de l'utilisateur.
        conversations.touched
            .sink { [weak self] _ in
                _ = self?.refresh()
            }
            .store(in: &subscriptions)
    }

    // MARK: - Chargement

    /// Apparition de l'écran : premier chargement, puis relecture silencieuse à chaque retour (un fil ouvert depuis
    /// la liste a changé l'ordre et les accusés de lecture) — `LifecycleResumeEffect` d'Android.
    @discardableResult
    func appear() -> Task<Void, Never>? {
        guard hasAppeared else {
            hasAppeared = true
            return load()
        }
        return refresh()
    }

    /// Chargement complet du segment courant (premier affichage, « Réessayer », changement de segment).
    @discardableResult
    func load() -> Task<Void, Never> {
        listTask?.cancel()
        state.isLoading = true
        state.isLoadingMore = false
        state.isRefreshing = false
        state.errorMessage = nil
        let archived = state.archived
        let task = Task { [weak self] in
            guard let self else { return }
            let blocked = self.fetchBlockedIds()
            do {
                let page = try await self.conversations.list(archived: archived)
                // Les bloqués arrivent AVANT la liste à l'écran : aucun aperçu masqué ne s'affiche un instant.
                let blockedIds = await blocked.value
                guard !Task.isCancelled else { return }
                if let blockedIds {
                    self.state.blockedIds = blockedIds
                }
                self.nextCursor = page.nextCursor
                self.hasLoadedOnce = true
                self.state.isLoading = false
                self.state.items = page.items
                self.state.hasMore = page.nextCursor != nil
                self.publishUnread(archived: archived, items: page.items)
            } catch {
                blocked.cancel()
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.errorMessage = ErrorMapper.message(for: error) ?? L10n.errorGeneric
            }
        }
        listTask = task
        return task
    }

    /// Relecture silencieuse (retour sur l'écran, `touched`) : pas d'indicateur, pas de message en cas d'échec.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        refresh(force: false)
    }

    /// Tirer pour rafraîchir : même relecture, avec l'indicateur et un message en cas d'échec.
    func pullToRefresh() async {
        let current = state
        if current.isLoading || current.isRefreshing || current.isLoadingMore { return }
        guard hasLoadedOnce else {
            await load().value
            return
        }
        state.isRefreshing = true
        guard let task = refresh(force: true) else {
            state.isRefreshing = false
            return
        }
        await task.value
    }

    /// Page suivante (curseur) ; les conversations déjà présentes ne sont pas reprises.
    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        guard let cursor = nextCursor else { return nil }
        let current = state
        guard !current.isLoading, !current.isLoadingMore, !current.isRefreshing else { return nil }
        // Une relecture silencieuse en vol rendrait ce curseur caduc.
        listTask?.cancel()
        state.isLoadingMore = true
        let archived = current.archived
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.conversations.list(cursor: cursor, archived: archived)
                guard !Task.isCancelled else { return }
                self.nextCursor = page.nextCursor
                let known: Set<String> = Set(self.state.items.map { $0.id })
                self.state.isLoadingMore = false
                self.state.items += page.items.filter { !known.contains($0.id) }
                self.state.hasMore = page.nextCursor != nil
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoadingMore = false
                self.state.notice = ErrorMapper.message(for: error)
            }
        }
        listTask = task
        return task
    }

    /// Segment Conversations / Archives : la liste repart de zéro (et du haut).
    @discardableResult
    func setArchived(_ archived: Bool) -> Task<Void, Never>? {
        guard archived != state.archived else { return nil }
        state.archived = archived
        state.items = []
        state.hasMore = false
        nextCursor = nil
        return load()
    }

    // MARK: - Actions

    /// Archiver / désarchiver : la ligne quitte la liste courante tout de suite et y revient, à sa place, si le
    /// serveur refuse (la conversation change simplement de segment). Seule CETTE ligne revient : restaurer un
    /// instantané ferait réapparaître une autre conversation archivée entre-temps, elle avec succès.
    @discardableResult
    func toggleArchive(_ conversation: Conversation) -> Task<Void, Never>? {
        let wasArchived = state.archived
        guard let position = state.items.firstIndex(where: { $0.id == conversation.id }) else { return nil }
        let wasUnread = conversation.isUnreadFor(state.userId)
        state.items.remove(at: position)
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.conversations.setArchived(conversationId: conversation.id, archived: !wasArchived)
                self.state.notice = wasArchived ? L10n.chatUnarchived : L10n.chatArchived
                // La pastille de l'onglet ne compte que la boîte de réception : une conversation non lue qui la
                // quitte (ou y revient) la fait baisser (ou monter) tout de suite.
                if wasUnread {
                    let delta = wasArchived ? 1 : -1
                    self.conversations.publishUnread(self.conversations.unreadCount + delta)
                }
            } catch {
                let current = self.state
                if current.archived == wasArchived && !current.items.contains(where: { $0.id == conversation.id }) {
                    self.state.items.insert(conversation, at: min(position, current.items.count))
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

    private func refresh(force: Bool) -> Task<Void, Never>? {
        let current = state
        guard hasLoadedOnce, !current.isLoading, !current.isLoadingMore, force || !current.isRefreshing else {
            return nil
        }
        listTask?.cancel()
        let archived = current.archived
        let task = Task { [weak self] in
            guard let self else { return }
            let blocked = self.fetchBlockedIds()
            do {
                let page = try await self.conversations.list(archived: archived)
                let blockedIds = await blocked.value
                guard !Task.isCancelled else {
                    if force { self.state.isRefreshing = false }
                    return
                }
                if let blockedIds {
                    self.state.blockedIds = blockedIds
                }
                // Pages suivantes déjà chargées : gardées, avec leur curseur (`Paging.mergeFirstPage`).
                let keepTail = self.state.items.count > page.items.count
                if !keepTail {
                    self.nextCursor = page.nextCursor
                    self.state.hasMore = page.nextCursor != nil
                }
                self.state.items = Paging.mergeFirstPage(current: self.state.items, fresh: page.items, id: { $0.id })
                self.state.errorMessage = nil
                self.state.isRefreshing = false
                self.publishUnread(archived: archived, items: page.items)
            } catch {
                blocked.cancel()
                guard !Task.isCancelled else {
                    if force { self.state.isRefreshing = false }
                    return
                }
                self.state.isRefreshing = false
                if force, let message = ErrorMapper.message(for: error) {
                    self.state.notice = message
                }
            }
        }
        listTask = task
        return task
    }

    /// Identifiants des utilisateurs bloqués, lus en même temps que la liste ; nil si la route échoue (404 avant
    /// le déploiement du lot serveur B, hors ligne…) : l'échec est ignoré, rien n'est alors masqué de plus.
    private func fetchBlockedIds() -> Task<Set<String>?, Never> {
        let repository = conversations
        let limit = Self.blockedLimit
        return Task { () async -> Set<String>? in
            do {
                let page = try await repository.blockedUsers(page: 1, limit: limit)
                return Set(page.items.map { $0.id })
            } catch {
                return nil
            }
        }
    }

    /// La pastille de l'onglet ne compte que la boîte de réception, jamais les archives.
    private func publishUnread(archived: Bool, items: [Conversation]) {
        guard !archived else { return }
        let userId = state.userId
        conversations.publishUnread(items.filter { $0.isUnreadFor(userId) }.count)
    }

    /// Autre compte (le ViewModel survit à la session) : la liste et l'identité du précédent sont jetées.
    private func sessionChanged(to userId: String) {
        guard sessionKnown else {
            sessionKnown = true
            state.userId = userId
            return
        }
        listTask?.cancel()
        listTask = nil
        nextCursor = nil
        hasLoadedOnce = false
        var fresh = ConversationsState()
        fresh.userId = userId
        fresh.isLoading = !userId.isEmpty
        state = fresh
        if !userId.isEmpty {
            load()
        }
    }

    /// Retour du réseau : un écran resté en erreur (rien d'affiché) se recharge de lui-même.
    private func connectivityChanged(isOnline: Bool) {
        let reconnected = isOnline && wasOffline
        wasOffline = !isOnline
        guard reconnected, state.errorMessage != nil, state.items.isEmpty else { return }
        load()
    }
}
