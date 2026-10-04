import Combine
import Foundation
import XCTest
@testable import Weyda

/// « Mes favoris » — règles de `FavoritesViewModel` (FavoritesScreen.kt, Android) : chargement, erreur et
/// « Réessayer », e-mail à vérifier (403 ou session non vérifiée), retrait optimiste et retour arrière, lignes qui
/// suivent `favorites.ids`, tirer pour rafraîchir, relecture au retour sur l'écran. Données fictives.
final class FavoritesViewModelTests: XCTestCase {
    private static func listing(_ id: String) -> AnnonceDTO {
        AnnonceDTO(id: id, title: "Annonce \(id)")
    }

    private static func member(verified: Bool) -> User {
        User(id: "u1", name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: verified)
    }

    @MainActor
    private func makeModel(
        _ api: FakeWeydaAPI,
        session: CurrentValueSubject<User?, Never>? = nil
    ) -> (model: FavoritesViewModel, repository: FavoritesRepository) {
        let repository = FavoritesRepository(api: api)
        let model = FavoritesViewModel(favorites: repository, session: session?.eraseToAnyPublisher())
        return (model, repository)
    }

    @MainActor
    func testTheListLoadsOnceThenIsRereadSilentlyOnReturn() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { [FavoritesViewModelTests.listing("a1"), FavoritesViewModelTests.listing("a2")] }
        let made = makeModel(api)
        let model = made.model
        XCTAssertTrue(model.state.isLoading)
        await model.appear()?.value
        XCTAssertFalse(model.state.isLoading)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2"])
        XCTAssertEqual(made.repository.ids, ["a1", "a2"])
        XCTAssertEqual(api.count("getFavorites"), 1)

        // Retour depuis une fiche où un favori a été ajouté : relecture sans squelettes.
        api.onGetFavorites = {
            [FavoritesViewModelTests.listing("a3"), FavoritesViewModelTests.listing("a1"), FavoritesViewModelTests.listing("a2")]
        }
        let again = model.appear()
        XCTAssertFalse(model.state.isLoading)
        await again?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["a3", "a1", "a2"])
        XCTAssertEqual(api.count("getFavorites"), 2)
    }

    @MainActor
    func testAFailedLoadShowsTheErrorAndRetryReloads() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { throw FakeWeydaAPI.apiError(500) }
        let model = makeModel(api).model
        await model.appear()?.value
        XCTAssertFalse(model.state.isLoading)
        XCTAssertNotNil(model.state.errorMessage)
        XCTAssertFalse(model.state.needsEmailVerification)
        XCTAssertTrue(model.state.items.isEmpty)

        api.onGetFavorites = { [FavoritesViewModelTests.listing("a1")] }
        await model.load().value
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1"])
    }

    @MainActor
    func testA403EmailNotVerifiedShowsTheVerificationStateUntilTheEmailIsVerified() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { throw FakeWeydaAPI.apiError(403, #"{"error":"emailNotVerified"}"#) }
        let session = CurrentValueSubject<User?, Never>(FavoritesViewModelTests.member(verified: true))
        let model = makeModel(api, session: session).model
        // Session « vérifiée » mais serveur d'un autre avis : le 403 fait foi (bandeau, pas d'écran d'erreur).
        await model.appear()?.value
        XCTAssertTrue(model.state.needsEmailVerification)
        XCTAssertNil(model.state.errorMessage)
        XCTAssertTrue(model.state.items.isEmpty)

        // Session relue non vérifiée : rien ne part ; puis e-mail vérifié (feuille « Vérifier ») : la liste se charge seule.
        api.onGetFavorites = { [FavoritesViewModelTests.listing("a1")] }
        session.value = FavoritesViewModelTests.member(verified: false)
        XCTAssertEqual(api.count("getFavorites"), 1)
        session.value = FavoritesViewModelTests.member(verified: true)
        await model.loadTask?.value
        XCTAssertEqual(api.count("getFavorites"), 2)
        XCTAssertFalse(model.state.needsEmailVerification)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1"])
    }

    @MainActor
    func testAnUnverifiedSessionSkipsTheRequestUntilPullToRefreshAsksTheServer() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { [FavoritesViewModelTests.listing("a1")] }
        let session = CurrentValueSubject<User?, Never>(FavoritesViewModelTests.member(verified: false))
        let model = makeModel(api, session: session).model
        // 403 garanti (même règle que FavoritesRepository) : inutile d'appeler.
        await model.appear()?.value
        XCTAssertTrue(model.state.needsEmailVerification)
        XCTAssertFalse(model.state.isLoading)
        XCTAssertEqual(api.count("getFavorites"), 0)

        // Adresse vérifiée sur le site, session pas encore relue : tirer pour rafraîchir interroge le serveur.
        await model.pullToRefresh()
        XCTAssertEqual(api.count("getFavorites"), 1)
        XCTAssertFalse(model.state.needsEmailVerification)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1"])
    }

    @MainActor
    func testRemovalIsOptimisticAndARefusalPutsTheRowBackInItsPlace() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { ["a1", "a2", "a3"].map { FavoritesViewModelTests.listing($0) } }
        let removed = FakeWeydaAPI.Box<[String]>([])
        api.onRemoveFavorite = { id in
            removed.value.append(id)
            return SimpleResponseDTO()
        }
        let made = makeModel(api)
        let model = made.model
        await model.appear()?.value
        let second = try XCTUnwrap(model.state.items.first(where: { $0.id == "a2" }))

        let task = model.remove(second)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a3"])
        // « Retiré des favoris » + « Annuler », tout de suite (sans attendre le serveur).
        XCTAssertEqual(model.state.banner?.message, L10n.favoriteRemoved)
        XCTAssertEqual(model.state.banner?.action, BannerAction.undo(FavoritesViewModel.undoPrefix + "a2"))
        await task?.value
        XCTAssertEqual(removed.value, ["a2"])
        XCTAssertFalse(made.repository.isFavorite("a2"))
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a3"])
        model.bannerDismissed()
        XCTAssertNil(model.state.banner)

        // Refus du serveur : la ligne revient à SA place (pas en fin de liste), la bannière d'erreur remplace « Annuler ».
        api.onRemoveFavorite = { _ in throw FakeWeydaAPI.apiError(500) }
        let first = try XCTUnwrap(model.state.items.first)
        let refused = model.remove(first)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a3"])
        await refused?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a3"])
        XCTAssertTrue(made.repository.isFavorite("a1"))
        XCTAssertEqual(model.state.banner?.kind, WeydaBanner.Kind.error)
        XCTAssertNil(model.state.banner?.action)
        model.bannerDismissed()
        XCTAssertNil(model.state.banner)
    }

    /// « Annuler » (bannière) : le favori est remis et la ligne revient à SA place — retrait déjà fait, ou encore en vol
    /// (la remise attend son issue ; 409 `alreadyFavorited` = succès). Bannière fermée : « Annuler » n'a plus d'effet.
    @MainActor
    func testUndoPutsTheFavoriteBackInItsPlace() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { ["a1", "a2", "a3"].map { FavoritesViewModelTests.listing($0) } }
        api.onRemoveFavorite = { _ in SimpleResponseDTO() }
        let added = FakeWeydaAPI.Box<[String]>([])
        api.onAddFavorite = { body in
            added.value.append(body.annonceId)
            return FavoriteDTO(id: "fav-\(body.annonceId)", annonceId: body.annonceId)
        }
        let made = makeModel(api)
        let model = made.model
        await model.appear()?.value
        let second = try XCTUnwrap(model.state.items.first(where: { $0.id == "a2" }))

        // Retrait confirmé par le serveur, puis « Annuler ».
        await model.remove(second)?.value
        let action = try XCTUnwrap(model.state.banner?.action)
        XCTAssertEqual(action.id, FavoritesViewModel.undoPrefix + "a2")
        let undo = model.bannerAction(action)
        XCTAssertNil(model.state.banner)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2", "a3"])
        await undo?.value
        XCTAssertEqual(added.value, ["a2"])
        XCTAssertTrue(made.repository.isFavorite("a2"))
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2", "a3"])

        // « Annuler » pendant que le retrait est en vol : la ligne ne repart pas, le favori est remis (409 = succès).
        api.onAddFavorite = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"alreadyFavorited"}"#) }
        let first = try XCTUnwrap(model.state.items.first)
        let removal = model.remove(first)
        let inFlight = try XCTUnwrap(model.state.banner?.action)
        let undoInFlight = model.bannerAction(inFlight)
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2", "a3"])
        await removal?.value
        await undoInFlight?.value
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2", "a3"])
        XCTAssertTrue(made.repository.isFavorite("a1"))
        XCTAssertNil(model.state.banner)
        XCTAssertEqual(api.count("removeFavorite"), 2)

        // Bannière fermée (délai écoulé) : « Annuler » n'a plus d'effet.
        let third = try XCTUnwrap(model.state.items.last)
        await model.remove(third)?.value
        let late = try XCTUnwrap(model.state.banner?.action)
        model.bannerDismissed()
        XCTAssertNil(model.bannerAction(late))
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1", "a2"])
        XCTAssertFalse(made.repository.isFavorite("a3"))
    }

    @MainActor
    func testAHeartRemovedElsewhereRemovesTheRowWithoutASecondRequest() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { [FavoritesViewModelTests.listing("a1"), FavoritesViewModelTests.listing("a2")] }
        api.onRemoveFavorite = { _ in SimpleResponseDTO() }
        let made = makeModel(api)
        let model = made.model
        await model.appear()?.value
        let stale = try XCTUnwrap(model.state.items.last)

        // Cœur retiré depuis la fiche (autre écran, même repository) : la ligne part aussi d'ici.
        _ = try await made.repository.toggle("a2")
        XCTAssertEqual(model.state.items.map { $0.id }, ["a1"])
        XCTAssertEqual(api.count("removeFavorite"), 1)

        // Ligne déjà partie : aucun appel (une bascule RAJOUTERAIT le favori).
        XCTAssertNil(model.remove(stale))
        XCTAssertEqual(api.count("removeFavorite"), 1)
    }

    @MainActor
    func testPullToRefreshReplacesTheListAndAFailureKeepsIt() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { [FavoritesViewModelTests.listing("a1")] }
        let model = makeModel(api).model
        await model.appear()?.value

        api.onGetFavorites = { [FavoritesViewModelTests.listing("a2"), FavoritesViewModelTests.listing("a1")] }
        await model.pullToRefresh()
        XCTAssertEqual(model.state.items.map { $0.id }, ["a2", "a1"])
        XCTAssertFalse(model.state.isRefreshing)

        api.onGetFavorites = { throw FakeWeydaAPI.apiError(500) }
        await model.pullToRefresh()
        XCTAssertEqual(model.state.items.map { $0.id }, ["a2", "a1"])
        XCTAssertNil(model.state.errorMessage)
        XCTAssertEqual(model.state.banner?.kind, WeydaBanner.Kind.error)
        XCTAssertFalse(model.state.isRefreshing)
    }
}
