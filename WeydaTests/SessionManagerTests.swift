import os
import XCTest
@testable import Weyda

/// Portage de `SessionManagerTest.kt` : persistance, restauration, UNE seule rotation pour des appels
/// concurrents, déconnexion (ou autre compte) pendant un refresh en vol, raison de la fermeture, profil.
/// Le `SessionManager` vit sur le fil principal : chaque test est `@MainActor`.
final class SessionManagerTests: XCTestCase {
    /// 2026-09-08T10:00:00Z : l'horloge fixe des tests Android.
    private static let clock = Date(timeIntervalSince1970: 1_788_861_600)

    private static func tokenResponse(
        access: String = "access-1",
        refresh: String = "refresh-1",
        userId: String = "user_1",
        email: String = "amina@example.com"
    ) -> TokenResponseDTO {
        TokenResponseDTO(
            accessToken: access,
            refreshToken: refresh,
            expiresIn: 3600,
            refreshExpiresIn: 2_592_000,
            user: AuthUserDTO(id: userId, name: "Amina", email: email, avatar: nil, role: "USER", emailVerified: true)
        )
    }

    @MainActor
    private func makeSession(
        _ storage: InMemorySessionStorage,
        refresh: @escaping @Sendable (String) async throws -> TokenResponseDTO = { _ in throw URLError(.unsupportedURL) }
    ) -> SessionManager {
        SessionManager(storage: storage, refreshCall: refresh, now: { Self.clock })
    }

    @MainActor
    func testSignInPersistsTokensAndUserAndSignOutClearsEverything() {
        let storage = InMemorySessionStorage()
        let session = makeSession(storage)
        XCTAssertFalse(session.isLoggedIn)

        session.signIn(Self.tokenResponse())
        XCTAssertTrue(session.isLoggedIn)
        XCTAssertEqual(session.accessToken, "access-1")
        XCTAssertEqual(session.user?.email, "amina@example.com")
        XCTAssertEqual(storage.tokens?.accessToken, "access-1")
        XCTAssertEqual(storage.tokens?.accessExpiresAt, Self.clock.addingTimeInterval(3600))
        XCTAssertEqual(storage.user?.id, "user_1")

        session.signOut()
        XCTAssertFalse(session.isLoggedIn)
        XCTAssertNil(session.accessToken)
        XCTAssertNil(session.user)
        XCTAssertNil(storage.tokens)
        XCTAssertNil(storage.user)
    }

    @MainActor
    func testRestoreLoadsAValidSessionAndPurgesAnExpiredOrIncompleteOne() {
        let response = Self.tokenResponse()
        let valid = InMemorySessionStorage(tokens: response.toTokens(now: Self.clock), user: response.user.toDomain())
        let session = makeSession(valid)
        session.restore()
        XCTAssertTrue(session.isLoggedIn)
        XCTAssertEqual(session.accessToken, "access-1")

        let expired = InMemorySessionStorage(
            tokens: response.toTokens(now: Self.clock.addingTimeInterval(-31 * 86_400)),
            user: response.user.toDomain()
        )
        let expiredSession = makeSession(expired)
        expiredSession.restore()
        XCTAssertFalse(expiredSession.isLoggedIn)
        XCTAssertNil(expired.tokens)
        XCTAssertNil(expired.user)

        let incomplete = InMemorySessionStorage(tokens: response.toTokens(now: Self.clock), user: nil)
        let incompleteSession = makeSession(incomplete)
        incompleteSession.restore()
        XCTAssertFalse(incompleteSession.isLoggedIn)
        XCTAssertNil(incomplete.tokens)
    }

    @MainActor
    func testConcurrentRefreshesRotateTheTokensOnlyOnce() async {
        let calls = CallLog()
        let gate = Gate()
        let rotated = Self.tokenResponse(access: "access-2", refresh: "refresh-2")
        let session = makeSession(InMemorySessionStorage()) { refreshToken in
            await calls.record(refreshToken)
            await gate.pass()
            return rotated
        }
        session.signIn(Self.tokenResponse())

        let first = Task { await session.refreshIfNeeded(failedAccessToken: "access-1") }
        await gate.waitForArrival() // la rotation est en vol, suspendue sur « le réseau »
        let second = Task { await session.refreshIfNeeded(failedAccessToken: "access-1") }
        await Task.yield()
        gate.open()

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, "access-2")
        XCTAssertEqual(secondResult, "access-2")
        let refreshTokens = await calls.values
        XCTAssertEqual(refreshTokens, ["refresh-1"])
        XCTAssertEqual(session.currentTokens?.refreshToken, "refresh-2")

        // Un jeton déjà obsolète ne redéclenche rien.
        let stale = await session.refreshIfNeeded(failedAccessToken: "access-1")
        XCTAssertEqual(stale, "access-2")
        let finalCalls = await calls.values
        XCTAssertEqual(finalCalls.count, 1)
    }

    @MainActor
    func testARejectedRefreshSignsOutButANetworkFailureKeepsTheSession() async {
        let rejected = makeSession(InMemorySessionStorage()) { _ in
            throw APIError(status: 401, code: "invalidRefreshToken")
        }
        rejected.signIn(Self.tokenResponse())
        let rejectedResult = await rejected.refreshIfNeeded(failedAccessToken: "access-1")
        XCTAssertNil(rejectedResult)
        XCTAssertFalse(rejected.isLoggedIn)

        let suspended = makeSession(InMemorySessionStorage()) { _ in
            throw APIError(status: 403, code: "accountSuspended")
        }
        suspended.signIn(Self.tokenResponse())
        let suspendedResult = await suspended.refreshIfNeeded(failedAccessToken: "access-1")
        XCTAssertNil(suspendedResult)
        XCTAssertFalse(suspended.isLoggedIn)

        let offline = makeSession(InMemorySessionStorage()) { _ in
            throw URLError(.notConnectedToInternet)
        }
        offline.signIn(Self.tokenResponse())
        let offlineResult = await offline.refreshIfNeeded(failedAccessToken: "access-1")
        XCTAssertNil(offlineResult)
        XCTAssertTrue(offline.isLoggedIn)
        XCTAssertEqual(offline.accessToken, "access-1")
    }

    @MainActor
    func testTheSignOutIsExpiredOnlyWhenTheServerRejectsTheRefresh() async {
        let session = makeSession(InMemorySessionStorage()) { _ in
            throw APIError(status: 401, code: "invalidRefreshToken")
        }
        session.signIn(Self.tokenResponse())
        _ = await session.refreshIfNeeded(failedAccessToken: "access-1")
        XCTAssertTrue(session.lastSignOutExpired)

        // Reconnexion puis déconnexion demandée : plus « expirée ».
        session.signIn(Self.tokenResponse())
        XCTAssertFalse(session.lastSignOutExpired)
        session.signOut()
        XCTAssertFalse(session.lastSignOutExpired)
    }

    @MainActor
    func testASignOutDuringAnInFlightRefreshIsNotUndoneByItsResult() async {
        let gate = Gate()
        let storage = InMemorySessionStorage()
        let rotated = Self.tokenResponse(access: "access-2", refresh: "refresh-2")
        let session = makeSession(storage) { _ in
            await gate.pass()
            return rotated
        }
        session.signIn(Self.tokenResponse())

        let refresh = Task { await session.refreshIfNeeded(failedAccessToken: "access-1") }
        await gate.waitForArrival()
        session.signOut()
        gate.open()
        let result = await refresh.value

        XCTAssertNil(result)
        XCTAssertFalse(session.isLoggedIn)
        XCTAssertNil(session.accessToken)
        XCTAssertNil(session.user)
        XCTAssertNil(storage.tokens)
        XCTAssertNil(storage.user)
    }

    @MainActor
    func testARefreshFinishingAfterAnotherSignInIsIgnored() async {
        let gate = Gate()
        let rotated = Self.tokenResponse(access: "access-2", refresh: "refresh-2")
        let session = makeSession(InMemorySessionStorage()) { _ in
            await gate.pass()
            return rotated
        }
        session.signIn(Self.tokenResponse())

        let refresh = Task { await session.refreshIfNeeded(failedAccessToken: "access-1") }
        await gate.waitForArrival()
        // Un autre compte se connecte pendant que la rotation de l'ancien est en vol.
        session.signIn(Self.tokenResponse(access: "access-9", refresh: "refresh-9", userId: "user_2", email: "karim@example.com"))
        gate.open()
        let result = await refresh.value

        // Pas de rejeu de l'ancienne requête avec le jeton du nouveau compte, et la nouvelle session reste.
        XCTAssertNil(result)
        XCTAssertEqual(session.accessToken, "access-9")
        XCTAssertEqual(session.user?.id, "user_2")
    }

    @MainActor
    func testUpdateUserAfterSignOutDoesNotRecreateAUser() {
        let storage = InMemorySessionStorage()
        let session = makeSession(storage)
        session.signIn(Self.tokenResponse())
        session.signOut()

        var transformed = false
        session.updateUser { user in
            transformed = true
            var copy = user
            copy.bio = "fantôme"
            return copy
        }
        XCTAssertFalse(transformed)
        XCTAssertNil(session.user)
        XCTAssertNil(storage.user)
    }

    @MainActor
    func testRefreshIfExpiringSoonOnlyRefreshesNearExpiry() async {
        let calls = CallLog()
        let rotated = Self.tokenResponse(access: "access-2", refresh: "refresh-2")
        let session = makeSession(InMemorySessionStorage()) { refreshToken in
            await calls.record(refreshToken)
            return rotated
        }
        session.signIn(Self.tokenResponse())

        let early = await session.refreshIfExpiringSoon(within: 60)
        XCTAssertEqual(early, "access-1")
        let noCall = await calls.values
        XCTAssertTrue(noCall.isEmpty)

        let due = await session.refreshIfExpiringSoon(within: 3600)
        XCTAssertEqual(due, "access-2")
        let oneCall = await calls.values
        XCTAssertEqual(oneCall, ["refresh-1"])
    }

    @MainActor
    func testUpdateUserKeepsProfileFieldsAcrossARotation() async {
        let rotated = Self.tokenResponse(access: "access-2", refresh: "refresh-2")
        let storage = InMemorySessionStorage()
        let session = makeSession(storage) { _ in rotated }
        session.signIn(Self.tokenResponse())
        session.updateUser { user in
            var copy = user
            copy.phone = "0555000000"
            copy.bio = "Vendeur pro"
            return copy
        }
        XCTAssertEqual(storage.user?.bio, "Vendeur pro")

        _ = await session.refreshIfNeeded(failedAccessToken: "access-1")
        XCTAssertEqual(session.accessToken, "access-2")
        XCTAssertEqual(session.user?.phone, "0555000000")
        XCTAssertEqual(session.user?.bio, "Vendeur pro")
    }

    @MainActor
    func testAuthorizationReadsTheSessionAndSharesItsRotation() async {
        let rotated = Self.tokenResponse(access: "access-2", refresh: "refresh-2")
        let session = makeSession(InMemorySessionStorage()) { _ in rotated }
        let authorization = session.authorization

        let visitorToken = await authorization.accessToken()
        XCTAssertNil(visitorToken)

        session.signIn(Self.tokenResponse())
        let currentToken = await authorization.accessToken()
        XCTAssertEqual(currentToken, "access-1")
        let freshToken = await authorization.refreshAfterUnauthorized("access-1")
        XCTAssertEqual(freshToken, "access-2")
        XCTAssertEqual(session.accessToken, "access-2")
    }
}

// MARK: - Outils (types imbriqués : aucun nom global partagé avec les autres fichiers de tests)

extension SessionManagerTests {
    /// Appels de rotation reçus (jeton de refresh transmis).
    actor CallLog {
        private(set) var values: [String] = []

        func record(_ value: String) {
            values.append(value)
        }
    }

    /// Barrière : la rotation simulée s'y arrête (`pass`) jusqu'à `open()` ; `waitForArrival()` attend
    /// qu'elle y soit — le test agit ainsi PENDANT que le refresh est en vol, sans délai arbitraire.
    /// État sous verrou (pas d'acteur) : les closures des continuations ne touchent aucun état isolé.
    final class Gate: Sendable {
        private struct State: Sendable {
            var arrived = false
            var isOpen = false
            var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
            var openWaiters: [CheckedContinuation<Void, Never>] = []
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        /// Appelé par la rotation simulée : signale son arrivée, puis attend `open()`.
        func pass() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Une seule décision sous verrou : la continuation est soit gardée pour `open()`, soit reprise
                // tout de suite — jamais les deux.
                let (arrivals, passNow): ([CheckedContinuation<Void, Never>], Bool) = state.withLock { state in
                    state.arrived = true
                    let waiting = state.arrivalWaiters
                    state.arrivalWaiters = []
                    if state.isOpen { return (waiting, true) }
                    state.openWaiters.append(continuation)
                    return (waiting, false)
                }
                arrivals.forEach { $0.resume() }
                if passNow { continuation.resume() }
            }
        }

        func waitForArrival() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyThere: Bool = state.withLock { state in
                    if state.arrived { return true }
                    state.arrivalWaiters.append(continuation)
                    return false
                }
                if alreadyThere { continuation.resume() }
            }
        }

        func open() {
            let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
                state.isOpen = true
                let pending = state.openWaiters
                state.openWaiters = []
                return pending
            }
            waiters.forEach { $0.resume() }
        }
    }
}
