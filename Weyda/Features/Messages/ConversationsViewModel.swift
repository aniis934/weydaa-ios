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
    /// Bannière du bas : « Conversation archivée » + « Annuler », échec d'une action, d'une page suivante ou d'un
    /// rafraîchissement ; effacée par `bannerDismissed()`.
    var banner: WeydaBanner? = nil

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

/// Dernier archivage (ou désarchivage) que la bannière propose d'annuler : la conversation, sa place, le segment qu'elle
/// a quitté et son état « non lu » (pastille de l'onglet).
private nonisolated struct MovedConversation: Sendable {
    let conversation: Conversation
    let index: Int
    /// Segment quitté : archives (vrai) ou boîte de réception (faux).
    let fromArchived: Bool
    let wasUnread: Bool
}

/// Onglet Messages — portage de `ConversationsViewModel` : liste paginée par curseur (`GET /api/conversations`),
/// segment Conversations / Archives, archivage optimiste (`POST` / `DELETE …/archive`) avec « Annuler » dans la bannière
/// (requête inverse, rangée remise à sa place, pastille rétablie), relecture silencieuse au retour sur l'écran et à
/// chaque `conversations.touched` (canal personnel), relance au retour du réseau. Chaque action renvoie sa tâche
/// (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
final class ConversationsViewModel: ObservableObject {
    /// Taille de la liste des bloqués lue avec la liste (une seule page : au-delà, rien n'est masqué de plus).
    static let blockedLimit = 100
    /// Préfixe de l'action « Annuler » d'un archivage : `archive:<id>`.
    static let undoPrefix = "archive:"

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
    /// Archivages envoyés et pas encore confirmés : une relecture ne doit pas rendre leur rangée.
    private var pendingMoves: Set<String> = []
    /// Jeton de l'archivage en cours de chaque conversation : l'issue d'un archivage annulé (« Annuler ») est ignorée.
    private var moveTokens: [String: Int] = [:]
    private var moveCounter = 0
    /// Requête de l'archivage en cours de chaque conversation (nil = réussi, sinon l'erreur) : « Annuler » attend son
    /// issue avant de défaire.
    private var moveRequests: [String: Task<(any Error)?, Never>] = [:]
    /// Conversations en cours de remise (« Annuler ») : les relectures attendent (la réponse du serveur ne les
    /// contiendrait peut-être pas encore).
    private var restoring: Set<String> = []
    /// Archivage que la bannière propose d'annuler (le dernier).
    private var lastMove: MovedConversation?

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
                self.state.items = self.shown(page.items)
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
                self.state.items += self.shown(page.items).filter { !known.contains($0.id) }
                self.state.hasMore = page.nextCursor != nil
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoadingMore = false
                self.showError(error)
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

    /// Archiver / désarchiver (glissement, appui long) : la ligne quitte la liste courante tout de suite, la bannière
    /// « Conversation archivée » propose « Annuler » ; si le serveur refuse, la ligne revient à SA place (message
    /// d'erreur). Seule CETTE ligne revient : restaurer un instantané ferait réapparaître une autre conversation
    /// archivée entre-temps, elle avec succès.
    @discardableResult
    func toggleArchive(_ conversation: Conversation) -> Task<Void, Never>? {
        let id = conversation.id
        // Remise en cours (« Annuler » touché à l'instant) : la ligne reste, le geste pourra être refait ensuite.
        guard !restoring.contains(id) else { return nil }
        guard let position = state.items.firstIndex(where: { $0.id == id }) else { return nil }
        let current = state.items[position]
        let fromArchived = state.archived
        let move = MovedConversation(
            conversation: current,
            index: position,
            fromArchived: fromArchived,
            wasUnread: current.isUnreadFor(state.userId)
        )
        state.items.remove(at: position)
        moveCounter += 1
        let token = moveCounter
        moveTokens[id] = token
        pendingMoves.insert(id)
        lastMove = move
        // Pas de vibration ici : le glissement plein en donne déjà une (UIKit).
        state.banner = InboxBanner.archived(!fromArchived, undoId: Self.undoPrefix + id)
        let repository = conversations
        let target = !fromArchived
        let request: Task<(any Error)?, Never> = Task { () async -> (any Error)? in
            do {
                try await repository.setArchived(conversationId: id, archived: target)
                return nil
            } catch {
                return error
            }
        }
        moveRequests[id] = request
        return Task { [weak self] in
            let failure: (any Error)? = await request.value
            self?.moveFinished(move, token: token, error: failure)
        }
    }

    /// Action de la bannière. « Annuler » un archivage : la ligne revient tout de suite à SA place, puis la requête
    /// inverse part une fois l'archivage abouti (rien à défaire si le serveur l'a refusé) ; la pastille de l'onglet
    /// retrouve sa valeur. Échec de la remise : la ligne repart, avec le message d'erreur.
    @discardableResult
    func bannerAction(_ action: BannerAction) -> Task<Void, Never>? {
        state.banner = nil
        guard let move = lastMove, action.id == Self.undoPrefix + move.conversation.id else { return nil }
        lastMove = nil
        let id = move.conversation.id
        // L'issue de l'archivage encore en vol ne compte plus (`moveFinished` l'ignore) ; la remise l'attend.
        moveTokens[id] = nil
        pendingMoves.remove(id)
        let inFlight: Task<(any Error)?, Never>? = moveRequests.removeValue(forKey: id)
        // Archivage déjà confirmé : la pastille l'a suivi, la remise la rétablira.
        let badgeFollowed: Bool = inFlight == nil
        restoring.insert(id)
        putBack(move)
        let repository = conversations
        let target = move.fromArchived
        return Task { [weak self] in
            var moveFailed = false
            if let inFlight {
                let failure: (any Error)? = await inFlight.value
                moveFailed = failure != nil
            }
            // Le serveur avait refusé l'archivage : la conversation n'a pas changé de segment, rien à défaire.
            if moveFailed {
                self?.restoreFinished(id)
                return
            }
            do {
                try await repository.setArchived(conversationId: id, archived: target)
                self?.restoreSucceeded(move, badgeFollowed: badgeFollowed)
            } catch {
                self?.restoreFailed(move, badgeFollowed: badgeFollowed, error: error)
            }
        }
    }

    /// La bannière s'est fermée (délai écoulé, glissée) : « Annuler » n'est plus proposé.
    func bannerDismissed() {
        state.banner = nil
        lastMove = nil
    }

    // MARK: - Interne

    private func refresh(force: Bool) -> Task<Void, Never>? {
        let current = state
        guard hasLoadedOnce, !current.isLoading, !current.isLoadingMore, force || !current.isRefreshing,
              restoring.isEmpty else {
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
                let fresh: [Conversation] = self.shown(page.items)
                let keepTail = self.state.items.count > fresh.count
                if !keepTail {
                    self.nextCursor = page.nextCursor
                    self.state.hasMore = page.nextCursor != nil
                }
                self.state.items = Paging.mergeFirstPage(current: self.state.items, fresh: fresh, id: { $0.id })
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
                if force {
                    self.showError(error)
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

    /// Issue d'un archivage. Ignorée s'il a été annulé (« Annuler ») : la remise s'occupe de la suite. Succès : la
    /// pastille suit. Refus : la ligne revient à sa place, la bannière d'erreur remplace « Annuler ».
    private func moveFinished(_ move: MovedConversation, token: Int, error: (any Error)?) {
        let id = move.conversation.id
        guard moveTokens[id] == token else { return }
        moveTokens[id] = nil
        moveRequests[id] = nil
        pendingMoves.remove(id)
        guard let error else {
            applyUnreadDelta(of: move, reversed: false)
            return
        }
        if lastMove?.conversation.id == id {
            lastMove = nil
        }
        putBack(move)
        if ErrorMapper.message(for: error) != nil {
            showError(error)
        } else if state.banner?.action?.id == Self.undoPrefix + id {
            // Annulation (aucun message) : « Annuler » n'a plus d'objet, la ligne est revenue.
            state.banner = nil
        }
    }

    /// Remise aboutie (« Annuler ») : la pastille retrouve sa valeur si elle avait suivi l'archivage.
    private func restoreSucceeded(_ move: MovedConversation, badgeFollowed: Bool) {
        guard restoring.remove(move.conversation.id) != nil else { return }
        if badgeFollowed {
            applyUnreadDelta(of: move, reversed: true)
        }
    }

    /// Remise refusée : la conversation reste dans l'autre segment, sa ligne repart ; la pastille suit l'archivage si
    /// elle ne l'avait pas encore fait. Le message dit pourquoi.
    private func restoreFailed(_ move: MovedConversation, badgeFollowed: Bool, error: any Error) {
        let id = move.conversation.id
        guard restoring.remove(id) != nil else { return }
        if state.archived == move.fromArchived {
            state.items.removeAll { $0.id == id }
        }
        if !badgeFollowed {
            applyUnreadDelta(of: move, reversed: false)
        }
        showError(error)
    }

    /// Rien à défaire (archivage refusé) : la ligne, déjà revenue, suit de nouveau les relectures.
    private func restoreFinished(_ id: String) {
        restoring.remove(id)
    }

    /// La ligne revient à SA place, si l'écran montre encore le segment qu'elle a quitté. Un rechargement a pu la
    /// remettre entre-temps : deux fois le même identifiant ferait planter la liste.
    private func putBack(_ move: MovedConversation) {
        let current = state
        let id = move.conversation.id
        guard current.archived == move.fromArchived, !current.items.contains(where: { $0.id == id }) else { return }
        state.items.insert(move.conversation, at: min(move.index, current.items.count))
    }

    /// La pastille de l'onglet ne compte que la boîte de réception : une conversation non lue qui la quitte la fait
    /// baisser, une qui y revient la fait monter. `reversed` = l'archivage est défait (« Annuler »).
    private func applyUnreadDelta(of move: MovedConversation, reversed: Bool) {
        guard move.wasUnread else { return }
        let joinsInbox: Bool = move.fromArchived != reversed
        let delta: Int = joinsInbox ? 1 : -1
        conversations.publishUnread(conversations.unreadCount + delta)
    }

    /// Bannière d'erreur (rien pour une annulation).
    private func showError(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else { return }
        state.banner = InboxBanner.error(message)
    }

    /// Les conversations dont l'archivage est en vol ne reviennent pas avec une relecture.
    private func shown(_ items: [Conversation]) -> [Conversation] {
        let hidden = pendingMoves
        guard !hidden.isEmpty else { return items }
        return items.filter { !hidden.contains($0.id) }
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
        // Archivages du compte précédent : leurs issues sont ignorées (jetons et remises oubliés).
        pendingMoves = []
        moveTokens = [:]
        moveRequests = [:]
        restoring = []
        lastMove = nil
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
