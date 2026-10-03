import Combine
import Foundation

/// État de l'onglet Profil d'un membre — portage de `ProfileUiState` (ProfileViewModels.kt).
nonisolated struct ProfileState: Equatable, Sendable {
    var user: User? = nil
    var stats: UserStats? = nil
    var isRefreshing: Bool = false
    /// Profil complet ou statistiques illisibles (le reste de l'écran reste affiché) ; nil = rien à signaler.
    var errorMessage: String? = nil
    var isLoggingOut: Bool = false
}

/// Profil complet + statistiques, déconnexion — portage de `ProfileViewModel`. Suit l'utilisateur de session :
/// à chaque changement de compte, les statistiques du précédent sont jetées et le profil complet (téléphone,
/// bio, « recommandé ») est relu.
final class ProfileViewModel: ObservableObject {
    @Published private(set) var state: ProfileState

    private let users: UserRepository
    private let auth: AuthRepository
    private var userSubscription: AnyCancellable?
    private var currentUserId: String?
    /// Relecture en cours (profil + statistiques) — attendue par le tirer-pour-rafraîchir et les tests.
    private(set) var refreshTask: Task<Void, Never>?

    /// `userUpdates` : l'utilisateur de session (`sessionManager.$user`), valeur courante comprise.
    init(users: UserRepository, auth: AuthRepository, userUpdates: AnyPublisher<User?, Never>) {
        self.users = users
        self.auth = auth
        self.state = ProfileState(user: auth.user)
        userSubscription = userUpdates.sink { [weak self] user in
            self?.userDidChange(user)
        }
    }

    /// Profil complet + statistiques, relus en tâche de fond ; une relecture en cours est remplacée.
    func refresh() {
        guard currentUserId != nil else { return }
        refreshTask?.cancel()
        state.isRefreshing = true
        state.errorMessage = nil
        refreshTask = Task { [weak self] in
            await self?.reload()
        }
    }

    /// Tirer pour rafraîchir : l'indicateur du système reste affiché jusqu'à la fin de la relecture.
    func pullToRefresh() async {
        refresh()
        await refreshTask?.value
    }

    func logout() {
        state.isLoggingOut = true
        auth.logout()
    }

    // MARK: - Interne

    private func userDidChange(_ user: User?) {
        state.user = user
        let id = user?.id
        guard id != currentUserId else { return }
        currentUserId = id
        refreshTask?.cancel()
        refreshTask = nil
        state.stats = nil
        state.errorMessage = nil
        state.isLoggingOut = false
        state.isRefreshing = false
        refresh()
    }

    /// Les deux requêtes partent ensemble ; une erreur n'efface pas l'autre résultat (dégradation gracieuse :
    /// les statistiques déjà affichées restent si leur relecture échoue).
    private func reload() async {
        let users = self.users
        async let meCall: User = users.me()
        async let statsCall: UserStats = users.stats()
        var failure: (any Error)? = nil
        do {
            _ = try await meCall
        } catch {
            failure = error
        }
        var fresh: UserStats? = nil
        do {
            fresh = try await statsCall
        } catch {
            if failure == nil { failure = error }
        }
        guard !Task.isCancelled else { return }
        state.isRefreshing = false
        if let fresh {
            state.stats = fresh
        }
        state.errorMessage = failure.flatMap { ErrorMapper.message(for: $0) }
    }
}
