import Combine
import Foundation
import XCTest
@testable import Weyda

/// Portage de FavoritesRepositoryTest.kt (Android) : liste, bascule optimiste, retour arrière, suivi de session.
final class FavoritesRepositoryTests: XCTestCase {
    private func user(verified: Bool = true) -> User {
        User(id: "u1", name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: verified)
    }

    @MainActor
    func testListResyncsTheIdsAndTheOptimisticToggleAddsThenRemoves() async throws {
        let api = FakeWeydaAPI()
        let repository = FavoritesRepository(api: api)
        api.onGetFavorites = { [AnnonceDTO(id: "a1", title: "T1"), AnnonceDTO(id: "a2", title: "T2")] }
        let listings = try await repository.list()
        XCTAssertEqual(listings.map { $0.id }, ["a1", "a2"])
        XCTAssertEqual(repository.ids, ["a1", "a2"])

        api.onAddFavorite = { body in
            XCTAssertEqual(body.annonceId, "a3")
            return FavoriteDTO(id: "f", annonceId: body.annonceId)
        }
        let added = try await repository.toggle("a3")
        XCTAssertTrue(added)
        XCTAssertTrue(repository.isFavorite("a3"))

        api.onRemoveFavorite = { id in
            XCTAssertEqual(id, "a1")
            return SimpleResponseDTO()
        }
        let removed = try await repository.toggle("a1")
        XCTAssertFalse(removed)
        XCTAssertEqual(repository.ids, ["a2", "a3"])
    }

    @MainActor
    func testARefusedToggleRollsBackAndIsPublishedWhile409And404MeanAlreadyDone() async throws {
        let api = FakeWeydaAPI()
        let repository = FavoritesRepository(api: api)
        let codes = FakeWeydaAPI.Box<[String]>([])
        let subscription = repository.errors.sink { error in
            codes.value.append((error as? APIError)?.code ?? "?")
        }

        api.onAddFavorite = { _ in throw FakeWeydaAPI.apiError(403, #"{"error":"emailNotVerified"}"#) }
        do {
            _ = try await repository.toggle("a1")
            XCTFail("refus attendu")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "emailNotVerified")
        }
        XCTAssertFalse(repository.isFavorite("a1"))
        XCTAssertEqual(codes.value, ["emailNotVerified"])

        api.onAddFavorite = { _ in throw FakeWeydaAPI.apiError(409, #"{"error":"alreadyFavorited"}"#) }
        let added = try await repository.toggle("a1")
        XCTAssertTrue(added)
        XCTAssertTrue(repository.isFavorite("a1"))

        api.onRemoveFavorite = { _ in throw FakeWeydaAPI.apiError(404, #"{"error":"notFound"}"#) }
        let removed = try await repository.toggle("a1")
        XCTAssertFalse(removed)
        XCTAssertFalse(repository.isFavorite("a1"))
        XCTAssertEqual(codes.value.count, 1)
        subscription.cancel()
    }

    @MainActor
    func testHeartsLoadAtSignInButNotBeforeTheEmailIsVerified() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { [AnnonceDTO(id: "a1", title: "T1")] }
        let session = CurrentValueSubject<User?, Never>(nil)
        let repository = FavoritesRepository(api: api, sessionUser: session.eraseToAnyPublisher())
        await repository.waitForSessionLoad()
        XCTAssertEqual(api.count("getFavorites"), 0)

        session.value = user(verified: false)
        await repository.waitForSessionLoad()
        // 403 emailNotVerified garanti : inutile d'appeler.
        XCTAssertEqual(api.count("getFavorites"), 0)

        session.value = user(verified: true)
        await repository.waitForSessionLoad()
        XCTAssertEqual(api.count("getFavorites"), 1)
        XCTAssertEqual(repository.ids, ["a1"])
    }

    @MainActor
    func testRefreshReadsTheServerStateAndSignOutEmptiesTheIds() async throws {
        let api = FakeWeydaAPI()
        api.onGetFavorites = { [] }
        let session = CurrentValueSubject<User?, Never>(user())
        let repository = FavoritesRepository(api: api, sessionUser: session.eraseToAnyPublisher())
        await repository.waitForSessionLoad()

        api.onIsFavorite = { id in IsFavoriteDTO(isFavorite: id == "a9") }
        let favorite = try await repository.refresh("a9")
        XCTAssertTrue(favorite)
        let other = try await repository.refresh("a1")
        XCTAssertFalse(other)
        XCTAssertEqual(repository.ids, ["a9"])

        session.value = nil
        XCTAssertTrue(repository.ids.isEmpty)
    }
}
