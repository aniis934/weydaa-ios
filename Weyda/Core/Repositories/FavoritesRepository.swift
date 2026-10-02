import Combine
import Foundation

/// Clé de session suivie par les favoris : utilisateur et e-mail vérifié (`GET /api/favorites` répond 403 tant
/// que l'e-mail ne l'est pas).
private nonisolated struct FavoritesSessionKey: Equatable, Sendable {
    let userId: String?
    let verified: Bool
}

/// Favoris (`/api/favorites*`, session requise, 403 `emailNotVerified` même en lecture) — portage de
/// `FavoritesRepository`. `ids` = source de vérité des cœurs dans toute l'app : chargé à la connexion (et au
/// démarrage sur une session restaurée), mis à jour de façon optimiste par `toggle` (retour arrière + `errors` si
/// le serveur refuse), vidé à la déconnexion.
final class FavoritesRepository: ObservableObject {
    @Published private(set) var ids: Set<String> = []

    /// Échecs de `toggle` (déjà annulés localement) : à afficher en bandeau par la racine de l'app.
    var errors: AnyPublisher<any Error, Never> { errorSubject.eraseToAnyPublisher() }

    private let api: any WeydaAPI
    private let errorSubject = PassthroughSubject<any Error, Never>()
    private var sessionSubscription: AnyCancellable?
    private var sessionLoad: Task<Void, Never>?
    /// Change à chaque changement de session : une liste reçue après une déconnexion n'est jamais appliquée.
    private var sessionGeneration = 0
    /// Dernière bascule réseau lancée : la suivante l'attend (un double appui ne croise jamais POST et DELETE).
    private var lastToggle: Task<Void, Never>?

    /// `sessionUser` : l'utilisateur de session (`sessionManager.$user`) ; `nil` = pas de suivi (tests).
    init(api: any WeydaAPI, sessionUser: AnyPublisher<User?, Never>? = nil) {
        self.api = api
        if let sessionUser {
            follow(sessionUser)
        }
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// Liste complète (annonces ACTIVE / SOLD / EXPIRED, la plus récente en tête) ; resynchronise `ids`.
    func list() async throws -> [Listing] {
        let generation = sessionGeneration
        let listings = try await api.getFavorites().map { $0.toDomain() }
        if generation == sessionGeneration {
            ids = Set(listings.map { $0.id })
        }
        return listings
    }

    /// État serveur d'une annonce (200 `{ isFavorite: false }` sans session) ; met `ids` à jour.
    func refresh(_ id: String) async throws -> Bool {
        let favorite = try await api.isFavorite(annonceId: id).isFavorite
        if favorite {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        return favorite
    }

    /// Bascule optimiste ; renvoie le nouvel état. 409 `alreadyFavorited` à l'ajout / 404 au retrait = état déjà
    /// atteint (succès). Toute autre erreur : retour arrière, publiée dans `errors`, puis relancée.
    /// La requête part dans une tâche propre : quitter la fiche juste après l'appui ne l'annule pas.
    @discardableResult
    func toggle(_ id: String) async throws -> Bool {
        let wasFavorite = ids.contains(id)
        if wasFavorite {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        let api = self.api
        let previous = lastToggle
        let call = Task<Bool, any Error> {
            _ = await previous?.value
            if wasFavorite {
                _ = try await api.removeFavorite(annonceId: id)
                return false
            }
            _ = try await api.addFavorite(FavoriteRequestDTO(annonceId: id))
            return true
        }
        lastToggle = Task {
            _ = await call.result
        }
        do {
            return try await call.value
        } catch let error as APIError where !wasFavorite && error.code == "alreadyFavorited" {
            return true
        } catch let error as APIError where wasFavorite && error.code == "notFound" {
            return false
        } catch {
            if wasFavorite {
                ids.insert(id)
            } else {
                ids.remove(id)
            }
            errorSubject.send(error)
            throw error
        }
    }

    /// Bascule détachée de l'écran (appui sur un cœur) : l'échec passe par `errors`.
    func toggleDetached(_ id: String) {
        Task {
            _ = try? await toggle(id)
        }
    }

    /// Attend la fin du chargement lancé par le dernier changement de session (tests, écran « Mes favoris »).
    func waitForSessionLoad() async {
        _ = await sessionLoad?.value
    }

    // MARK: - Session

    private func follow(_ sessionUser: AnyPublisher<User?, Never>) {
        sessionSubscription = sessionUser
            .map { user in FavoritesSessionKey(userId: user?.id, verified: user?.emailVerified == true) }
            .removeDuplicates()
            .sink { [weak self] key in
                self?.sessionChanged(key)
            }
    }

    /// Déconnexion → cœurs vidés ; connexion (ou e-mail tout juste vérifié) → favoris chargés. Échec silencieux :
    /// les cœurs se rempliront au prochain `list` / `refresh`.
    private func sessionChanged(_ key: FavoritesSessionKey) {
        sessionGeneration += 1
        sessionLoad?.cancel()
        sessionLoad = nil
        guard key.userId != nil else {
            ids = []
            return
        }
        guard key.verified else { return }
        sessionLoad = Task { [weak self] in
            _ = try? await self?.list()
        }
    }
}
