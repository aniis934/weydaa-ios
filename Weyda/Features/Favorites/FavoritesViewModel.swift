import Combine
import Foundation

/// État de « Mes favoris » — portage de `FavoritesUiState` (FavoritesScreen.kt), plus l'e-mail à vérifier (le serveur
/// répond 403 `emailNotVerified` même en lecture) et la bannière du bas.
nonisolated struct FavoritesState: Equatable, Sendable {
    var items: [Listing] = []
    var isLoading: Bool = true
    /// Tirer pour rafraîchir.
    var isRefreshing: Bool = false
    /// Erreur du chargement complet (écran d'erreur avec « Réessayer »).
    var errorMessage: String? = nil
    /// E-mail non vérifié : bandeau « Vérifier » + explication à la place de la liste.
    var needsEmailVerification: Bool = false
    /// Bannière du bas : « Retiré des favoris » + « Annuler », retrait refusé, rafraîchissement impossible ; effacée
    /// par `bannerDismissed()`.
    var banner: WeydaBanner? = nil
}

/// Dernier retrait, que la bannière propose d'annuler : l'annonce et sa place dans la liste.
private nonisolated struct RemovedFavorite: Sendable {
    let listing: Listing
    let index: Int
}

/// « Mes favoris » — portage de `FavoritesViewModel` (Android) : liste complète (`FavoritesRepository.list()`), tirer
/// pour rafraîchir (la liste reste affichée, un échec la laisse telle quelle), retrait optimiste (la ligne revient à SA
/// place si le serveur refuse) avec « Annuler » dans la bannière (le favori est remis, la ligne revient à sa place).
/// Les lignes suivent `favorites.ids` : un cœur retiré ailleurs (fiche ouverte depuis la liste) retire aussi la ligne —
/// sinon elle restait affichée cœur plein, et la toucher RAJOUTAIT le favori.
/// Chaque action renvoie sa tâche (`@discardableResult`) : l'écran l'ignore, les tests l'attendent.
final class FavoritesViewModel: ObservableObject {
    @Published private(set) var state = FavoritesState()

    /// Lecture en vol (chargement, relecture silencieuse) — une seule à la fois ; attendue par les tests.
    private(set) var loadTask: Task<Void, Never>?

    /// Préfixe de l'action « Annuler » d'un retrait : `favorite:<id>`.
    static let undoPrefix = "favorite:"

    private let favorites: FavoritesRepository
    private var hasAppeared = false
    /// E-mail vérifié selon la session (nil = pas de session suivie : tests, ou visiteur).
    private var emailVerified: Bool?
    /// Retraits envoyés au serveur et pas encore confirmés : une relecture ne doit pas les rendre.
    private var pendingRemovals: Set<String> = []
    /// Jeton du retrait en cours de chaque annonce : l'issue d'un retrait annulé (« Annuler ») ou remplacé est ignorée.
    private var removalTokens: [String: Int] = [:]
    private var removalCounter = 0
    /// Tâche du retrait en cours de chaque annonce : « Annuler » attend son issue avant de remettre le favori.
    private var removalTasks: [String: Task<Void, Never>] = [:]
    /// Favoris en cours de remise (« Annuler ») : leur ligne reste affichée même si `ids` ne les contient pas encore.
    private var restoring: Set<String> = []
    /// Retrait que la bannière propose d'annuler (le dernier).
    private var lastRemoval: RemovedFavorite?
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
            showError(error)
        }
        state.isRefreshing = false
    }

    // MARK: - Retrait

    /// Retrait optimiste (glissement, cœur, menu d'appui long) : la ligne disparaît tout de suite, la bannière
    /// « Retiré des favoris » propose « Annuler » ; si le serveur refuse, la ligne revient à sa place (message d'erreur).
    @discardableResult
    func remove(_ listing: Listing) -> Task<Void, Never>? {
        // Remise en cours (« Annuler » touché à l'instant) : la ligne reste, le geste pourra être refait ensuite.
        guard !restoring.contains(listing.id) else { return nil }
        guard let index = state.items.firstIndex(where: { $0.id == listing.id }) else { return nil }
        state.items.remove(at: index)
        // Déjà retiré ailleurs : `toggle` est une bascule, il recréerait le favori côté serveur.
        guard favorites.isFavorite(listing.id) else { return nil }
        // Une relecture silencieuse en vol rendrait la ligne (le serveur ne l'a peut-être pas encore retirée).
        if !state.isLoading {
            loadTask?.cancel()
        }
        let id = listing.id
        removalCounter += 1
        let token = removalCounter
        removalTokens[id] = token
        pendingRemovals.insert(id)
        lastRemoval = RemovedFavorite(listing: listing, index: index)
        // Pas de vibration ici : le glissement plein en donne déjà une (UIKit).
        state.banner = WeydaBanner(
            L10n.favoriteRemoved,
            symbol: "heart.slash",
            kind: .info,
            action: .undo(Self.undoPrefix + id)
        )
        let repository = self.favorites
        let task = Task { [weak self] in
            do {
                _ = try await repository.toggle(id)
                self?.removalFinished(listing, at: index, token: token, error: nil)
            } catch {
                self?.removalFinished(listing, at: index, token: token, error: error)
            }
        }
        removalTasks[id] = task
        return task
    }

    /// Action de la bannière. « Annuler » un retrait : la ligne revient tout de suite à SA place, puis le favori est
    /// remis une fois le retrait aboutit (`toggle` l'ajoute ; 409 `alreadyFavorited` = succès) ; rien à remettre si le
    /// serveur a refusé le retrait. Échec de la remise : la ligne repart, avec le message d'erreur.
    @discardableResult
    func bannerAction(_ action: BannerAction) -> Task<Void, Never>? {
        state.banner = nil
        guard let removal = lastRemoval, action.id == Self.undoPrefix + removal.listing.id else { return nil }
        lastRemoval = nil
        let listing = removal.listing
        let id = listing.id
        // L'issue du retrait encore en vol ne compte plus (`removalFinished` l'ignore) ; la remise l'attend.
        removalTokens[id] = nil
        pendingRemovals.remove(id)
        let removalInFlight: Task<Void, Never>? = removalTasks.removeValue(forKey: id)
        restoring.insert(id)
        if !state.items.contains(where: { $0.id == id }) {
            state.items.insert(listing, at: min(removal.index, state.items.count))
        }
        let repository = self.favorites
        return Task { [weak self] in
            _ = await removalInFlight?.value
            // Retrait refusé (le repository a remis le cœur) : déjà favori, rien à faire.
            if !repository.isFavorite(id) {
                do {
                    _ = try await repository.toggle(id)
                } catch {
                    self?.restoreFailed(id, error: error)
                    return
                }
            }
            self?.restoreFinished(id)
        }
    }

    /// La bannière s'est fermée (délai écoulé, glissée) : « Annuler » n'est plus proposé.
    func bannerDismissed() {
        state.banner = nil
        lastRemoval = nil
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
              pendingRemovals.isEmpty, restoring.isEmpty else { return nil }
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

    /// Issue d'un retrait. Ignorée s'il a été annulé (« Annuler ») ou remplacé par un retrait plus récent de la même
    /// annonce ; refus du serveur → la ligne revient à sa place, la bannière d'erreur remplace « Annuler ».
    private func removalFinished(_ listing: Listing, at index: Int, token: Int, error: (any Error)?) {
        let id = listing.id
        guard removalTokens[id] == token else { return }
        removalTokens[id] = nil
        removalTasks[id] = nil
        pendingRemovals.remove(id)
        guard let error else { return }
        if lastRemoval?.listing.id == id {
            lastRemoval = nil
        }
        // Un rechargement a pu la remettre entre-temps : deux fois le même identifiant ferait planter la liste.
        if !state.items.contains(where: { $0.id == id }) {
            state.items.insert(listing, at: min(index, state.items.count))
        }
        if ErrorMapper.message(for: error) != nil {
            showError(error)
        } else if state.banner?.action?.id == Self.undoPrefix + id {
            // Annulation (aucun message) : « Annuler » n'a plus d'objet, la ligne est revenue.
            state.banner = nil
        }
    }

    /// Bannière d'erreur (rien pour une annulation).
    private func showError(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else { return }
        state.banner = WeydaBanner(message, symbol: "exclamationmark.circle", kind: .error)
    }

    /// Favori remis (« Annuler ») : la ligne suit de nouveau `ids`.
    private func restoreFinished(_ id: String) {
        restoring.remove(id)
    }

    /// Remise refusée : l'annonce n'est plus en favori, sa ligne repart ; le message dit pourquoi.
    private func restoreFailed(_ id: String, error: any Error) {
        restoring.remove(id)
        state.items.removeAll { $0.id == id }
        showError(error)
    }

    /// Un cœur retiré ailleurs retire la ligne (Android : `favorites.ids.collect`), sauf un favori en cours de remise.
    /// `@Published` publie AVANT d'écrire : la valeur reçue fait foi, pas `favorites.ids`.
    private func idsChanged(_ ids: Set<String>) {
        let items = state.items
        let kept: [Listing] = items.filter { ids.contains($0.id) || restoring.contains($0.id) }
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
