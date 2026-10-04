import Combine
import Foundation

/// État de « Mes favoris » — portage de `FavoritesUiState` (FavoritesScreen.kt), plus l'e-mail à vérifier (le serveur
/// répond 403 `emailNotVerified` même en lecture) et un message bref.
nonisolated struct FavoritesState: Equatable, Sendable {
    var items: [Listing] = []
    var isLoading: Bool = true
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    /// Erreur du chargement complet (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    /// E-mail non vérifié : bandeau « Vérifier » + explication à la place de la liste.
    var needsEmailVerification: Bool = false
    /// Message bref (retrait refusé, rafraîchissement impossible), effacé par `noticeShown()`.
    var notice: String? = nil
}

/// « Mes favoris » — portage de `FavoritesViewModel` (Android) : liste complète (`FavoritesRepository.list()`), tirer
/// pour rafraîchir (la liste reste affichée, un échec la laisse telle quelle), retrait optimiste (la ligne revient à SA
/// place si le serveur refuse). Les lignes suivent `favorites.ids` : un cœur retiré ailleurs (fiche ouverte depuis la
/// liste) retire aussi la ligne — sinon elle restait affichée cœur plein, et la toucher RAJOUTAIT le favori.
/// Chaque action renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
final class FavoritesViewModel: ObservableObject {
    @Published private(set) var state = FavoritesState()

    /// Lecture en vol (chargement, relecture silencieuse) — une seule à la fois ; attendue par les tests.
    private(set) var loadTask: Task<Void, Never>?

    private let favorites: FavoritesRepository
    private var hasAppeared = false
    /// E-mail vérifié selon la session (nil = pas de session suivie : tests, ou visiteur).
    private var emailVerified: Bool?
    /// Retraits envoyés au serveur et pas encore confirmés : une relecture ne doit pas les rendre.
    private var pendingRemovals: Set<String> = []
    private var subscriptions: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - favorites: source de vérité des cœurs (`ids`) et de la liste.
    ///   - session: utilisateur de la session (`sessionManager.$user`) : e-mail non vérifié → pas de requête (403
    ///     garanti, même règle que `FavoritesRepository`) ; e-mail tout juste vérifié → la liste se charge seule.
    init(favorites: FavoritesRepository, session: AnyPublisher<User?, Never>? = nil) {
        self.favorites = favorites
        favorites.$ids
            .sink { [weak self] ids in
                self?.idsChanged(ids)
            }
            .store(in: &subscriptions)
        if let session {
            session
                .map { (user: User?) -> Bool? in user.map { $0.emailVerified } }
                .removeDuplicates()
                .sink { [weak self] verified in
                    self?.emailVerificationChanged(verified)
                }
                .store(in: &subscriptions)
        }
    }

    // MARK: - Chargement

    /// Premier affichage : chargement complet ; chaque retour sur l'écran (depuis une fiche) : relecture silencieuse —
    /// un favori remis depuis la fiche y reparaît.
    @discardableResult
    func appear() -> Task<Void, Never>? {
        guard hasAppeared else {
            hasAppeared = true
            return load()
        }
        return refreshSilently()
    }

    /// Chargement complet (premier affichage, « Réessayer »).
    @discardableResult
    func load() -> Task<Void, Never> {
        start(askServer: false)
    }

    /// Tirer pour rafraîchir : la liste reçue remplace l'ancienne ; un échec la laisse et donne un message. Depuis
    /// l'écran d'erreur ou celui de l'e-mail à vérifier, le serveur est interrogé quoi que dise la session (l'adresse a
    /// pu être vérifiée sur le site).
    func pullToRefresh() async {
        let current = state
        guard !current.isLoading, !current.isRefreshing else { return }
        if current.errorMessage != nil || current.needsEmailVerification {
            await start(askServer: true).value
            return
        }
        state.isRefreshing = true
        do {
            let list = try await favorites.list()
            state.items = shown(list)
        } catch let error as APIError where error.isEmailNotVerified {
            state.items = []
            state.needsEmailVerification = true
        } catch {
            if let message = ErrorMapper.message(for: error) {
                state.notice = message
            }
        }
        state.isRefreshing = false
    }

    // MARK: - Retrait

    /// Retrait optimiste : la ligne disparaît tout de suite et revient à sa place si le serveur refuse (message bref).
    @discardableResult
    func remove(_ listing: Listing) -> Task<Void, Never>? {
        guard let index = state.items.firstIndex(where: { $0.id == listing.id }) else { return nil }
        state.items.remove(at: index)
        // Déjà retiré ailleurs : `toggle` est une bascule, il recréerait le favori côté serveur.
        guard favorites.isFavorite(listing.id) else { return nil }
        // Une relecture silencieuse en vol rendrait la ligne (le serveur ne l'a peut-être pas encore retirée).
        if !state.isLoading {
            loadTask?.cancel()
        }
        let id = listing.id
        pendingRemovals.insert(id)
        let repository = self.favorites
        return Task { [weak self] in
            do {
                _ = try await repository.toggle(id)
                self?.removalFinished(listing, at: index, error: nil)
            } catch {
                self?.removalFinished(listing, at: index, error: error)
            }
        }
    }

    func noticeShown() {
        state.notice = nil
    }

    // MARK: - Interne

    private func start(askServer: Bool) -> Task<Void, Never> {
        loadTask?.cancel()
        state.isRefreshing = false
        state.errorMessage = nil
        if !askServer && emailVerified == false {
            state.isLoading = false
            state.items = []
            state.needsEmailVerification = true
            let skipped: Task<Void, Never> = Task {}
            loadTask = skipped
            return skipped
        }
        state.isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await self.favorites.list()
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.needsEmailVerification = false
                self.state.items = self.shown(list)
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.applyLoadFailure(error)
            }
        }
        loadTask = task
        return task
    }

    /// Relecture sans indicateur (retour sur l'écran) ; un échec est ignoré.
    private func refreshSilently() -> Task<Void, Never>? {
        let current = state
        guard !current.isLoading, !current.isRefreshing, current.errorMessage == nil, !current.needsEmailVerification,
              pendingRemovals.isEmpty else { return nil }
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            guard let list = try? await self.favorites.list(), !Task.isCancelled else { return }
            self.state.items = self.shown(list)
        }
        loadTask = task
        return task
    }

    /// 403 `emailNotVerified` → bandeau et explication ; toute autre erreur → écran d'erreur.
    private func applyLoadFailure(_ error: any Error) {
        if let apiError = error as? APIError, apiError.isEmailNotVerified {
            state.items = []
            state.needsEmailVerification = true
        } else {
            state.needsEmailVerification = false
            state.errorMessage = ErrorMapper.message(for: error) ?? L10n.errorGeneric
        }
    }

    private func removalFinished(_ listing: Listing, at index: Int, error: (any Error)?) {
        pendingRemovals.remove(listing.id)
        guard let error else { return }
        // Un rechargement a pu la remettre entre-temps : deux fois le même identifiant ferait planter la liste.
        if !state.items.contains(where: { $0.id == listing.id }) {
            state.items.insert(listing, at: min(index, state.items.count))
        }
        if let message = ErrorMapper.message(for: error) {
            state.notice = message
        }
    }

    /// Un cœur retiré ailleurs retire la ligne (Android : `favorites.ids.collect`). `@Published` publie AVANT d'écrire :
    /// la valeur reçue fait foi, pas `favorites.ids`.
    private func idsChanged(_ ids: Set<String>) {
        let items = state.items
        let kept: [Listing] = items.filter { ids.contains($0.id) }
        if kept.count != items.count {
            state.items = kept
        }
    }

    /// E-mail tout juste vérifié (feuille « Vérifier » refermée) : la liste se charge sans autre geste.
    private func emailVerificationChanged(_ verified: Bool?) {
        emailVerified = verified
        guard verified == true, hasAppeared, state.needsEmailVerification else { return }
        load()
    }

    private func shown(_ list: [Listing]) -> [Listing] {
        let pending = pendingRemovals
        guard !pending.isEmpty else { return list }
        return list.filter { !pending.contains($0.id) }
    }
}
