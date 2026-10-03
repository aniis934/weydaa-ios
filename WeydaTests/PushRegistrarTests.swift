import Foundation
import XCTest
@testable import Weyda

/// Faux système de notifications (autorisation, APNs, jeton FCM, pastille) : chaque appel est compté. Isolé sur le
/// MainActor comme les closures de `PushServices` qu'il fournit.
@MainActor
final class FakePushSystem {
    var status: PushAuthorizationStatus = .notDetermined
    var grants = true
    var hasAPNs = true
    var token: String? = "fcm-token-1"
    private(set) var statusReads = 0
    private(set) var authorizationRequests = 0
    private(set) var remoteRegistrations = 0
    private(set) var tokenReads = 0
    private(set) var deletions = 0
    private(set) var badges: [Int] = []

    init() {}

    var totalCalls: Int {
        statusReads + authorizationRequests + remoteRegistrations + tokenReads + deletions + badges.count
    }

    func services(available: Bool = true, refreshName: String? = nil) -> PushServices {
        PushServices(
            isAvailable: available,
            authorizationStatus: { [self] in
                self.statusReads += 1
                return self.status
            },
            requestAuthorization: { [self] in
                self.authorizationRequests += 1
                self.status = self.grants ? .authorized : .denied
                return self.grants
            },
            registerForRemoteNotifications: { [self] in
                self.remoteRegistrations += 1
            },
            hasAPNsToken: { [self] in
                self.hasAPNs
            },
            currentToken: { [self] in
                self.tokenReads += 1
                return self.token
            },
            deleteToken: { [self] in
                // Comme Firebase : le jeton détruit est remplacé par un nouveau au prochain besoin.
                self.deletions += 1
                self.token = "fcm-token-\(self.deletions + 1)"
            },
            setBadge: { [self] count in
                self.badges.append(count)
            },
            tokenRefreshNotificationName: refreshName
        )
    }
}

/// `PushRegistrar` — portage de `PushRegistrar` (PushNotifications.kt) et de `NotificationPermissionEffect` (Android) :
/// jeton envoyé avec `platform: "ios"` et la langue, rien sans Firebase, une seule demande d'autorisation, jeton
/// renouvelé renvoyé, désinscription à la fermeture de session.
final class PushRegistrarTests: XCTestCase {

    @MainActor
    private func makeDefaults() throws -> UserDefaults {
        let suite = "push-registrar-tests-\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    /// Jetons reçus par `POST /api/push/fcm` (fausse API).
    @MainActor
    private func recordTokens(on api: FakeWeydaAPI) -> FakeWeydaAPI.Box<[FcmTokenRequestDTO]> {
        let sent = FakeWeydaAPI.Box<[FcmTokenRequestDTO]>([])
        api.onRegisterFcmToken = { body in
            sent.value.append(body)
            return SimpleResponseDTO()
        }
        return sent
    }

    @MainActor
    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    // MARK: - Jeton

    @MainActor
    func testTheTokenIsRegisteredWithTheIOSPlatformAndTheAppLanguage() async throws {
        let api = FakeWeydaAPI()
        let sent = recordTokens(on: api)
        let system = FakePushSystem()
        let registrar = PushRegistrar(api: api, services: system.services(), defaults: try makeDefaults(), language: { "ar" })

        XCTAssertTrue(registrar.isAvailable)
        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(sent.value, [FcmTokenRequestDTO(token: "fcm-token-1", locale: "ar", platform: "ios")])

        // Corps JSON reçu par le serveur (lot B : `platform` "ios" → alerte APNs traduite).
        let data = try JSONEncoder().encode(sent.value[0])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["token": "fcm-token-1", "locale": "ar", "platform": "ios"])

        // Même jeton (retour au premier plan, jeton APNs redonné) : aucune requête en double.
        registrar.registerCurrentToken()
        registrar.apnsTokenDidArrive()
        await registrar.settle()
        XCTAssertEqual(sent.value.count, 1)
        XCTAssertEqual(api.calls, ["registerFcmToken"])
    }

    @MainActor
    func testTheTokenWaitsForTheAPNsTokenAndNeedsASession() async throws {
        let api = FakeWeydaAPI()
        let sent = recordTokens(on: api)
        let system = FakePushSystem()
        system.hasAPNs = false
        let registrar = PushRegistrar(api: api, services: system.services(), defaults: try makeDefaults(), language: { "fr" })

        // Jeton APNs reçu sans session : rien n'est envoyé.
        system.hasAPNs = true
        registrar.apnsTokenDidArrive()
        await registrar.settle()
        XCTAssertEqual(sent.value, [])
        XCTAssertEqual(system.tokenReads, 0)

        // Session ouverte avant le jeton APNs : on attend…
        system.hasAPNs = false
        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(sent.value, [])
        XCTAssertEqual(system.tokenReads, 0, "sans jeton APNs, Firebase n'est pas interrogé")

        // … et le jeton part dès qu'APNs a répondu.
        system.hasAPNs = true
        registrar.apnsTokenDidArrive()
        await registrar.settle()
        XCTAssertEqual(sent.value.map(\.token), ["fcm-token-1"])
        XCTAssertEqual(sent.value.map(\.locale), ["fr"])
    }

    @MainActor
    func testARefusedRegistrationIsRetriedAndAMissingTokenSendsNothing() async throws {
        let api = FakeWeydaAPI()
        let attempts = FakeWeydaAPI.Box(0)
        api.onRegisterFcmToken = { _ in
            attempts.value += 1
            if attempts.value == 1 { throw URLError(.notConnectedToInternet) }
            return SimpleResponseDTO()
        }
        let system = FakePushSystem()
        let registrar = PushRegistrar(api: api, services: system.services(), defaults: try makeDefaults(), language: { "fr" })

        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(attempts.value, 1)
        // Hors ligne au premier essai : renvoyé au retour au premier plan (`AppContainer`), puis plus rien.
        registrar.registerCurrentToken()
        await registrar.settle()
        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(attempts.value, 2)

        // Firebase sans jeton (réseau) : aucune requête.
        let empty = FakePushSystem()
        empty.token = nil
        let other = PushRegistrar(api: api, services: empty.services(), defaults: try makeDefaults(), language: { "fr" })
        other.registerCurrentToken()
        await other.settle()
        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(empty.tokenReads, 1)
    }

    @MainActor
    func testARefreshedTokenIsSentAgainWhileASessionIsOpen() async throws {
        let api = FakeWeydaAPI()
        let sent = recordTokens(on: api)
        let system = FakePushSystem()
        let refresh = "weyda.tests.push.refresh.\(UUID().uuidString)"
        let registrar = PushRegistrar(
            api: api,
            services: system.services(refreshName: refresh),
            defaults: try makeDefaults(),
            language: { "en" }
        )

        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(sent.value.map(\.token), ["fcm-token-1"])

        // Firebase renouvelle le jeton (Android : `onNewToken`).
        system.token = "fcm-token-renewed"
        NotificationCenter.default.post(name: Notification.Name(refresh), object: nil)
        let renewed = await eventually { sent.value.count == 2 }
        XCTAssertTrue(renewed)
        await registrar.settle()
        XCTAssertEqual(sent.value.map(\.token), ["fcm-token-1", "fcm-token-renewed"])
        XCTAssertEqual(sent.value.map(\.locale), ["en", "en"])
    }

    @MainActor
    func testUnregisterDestroysTheTokenAndTheNextSessionRegistersANewOne() async throws {
        let api = FakeWeydaAPI()
        let sent = recordTokens(on: api)
        let system = FakePushSystem()
        let refresh = "weyda.tests.push.refresh.\(UUID().uuidString)"
        let registrar = PushRegistrar(
            api: api,
            services: system.services(refreshName: refresh),
            defaults: try makeDefaults(),
            language: { "fr" }
        )

        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(sent.value.map(\.token), ["fcm-token-1"])

        // Fermeture de session : jeton détruit sur l'appareil, plus aucun envoi (ni renouvellement, ni APNs).
        registrar.unregister()
        await registrar.settle()
        XCTAssertEqual(system.deletions, 1)
        NotificationCenter.default.post(name: Notification.Name(refresh), object: nil)
        registrar.apnsTokenDidArrive()
        try await Task.sleep(nanoseconds: 50_000_000)
        await registrar.settle()
        XCTAssertEqual(sent.value.count, 1)

        // Nouvelle session (autre compte) : le nouveau jeton est rattaché, après la destruction de l'ancien.
        registrar.unregister()
        registrar.registerCurrentToken()
        await registrar.settle()
        XCTAssertEqual(system.deletions, 2)
        XCTAssertEqual(sent.value.map(\.token), ["fcm-token-1", "fcm-token-3"])
    }

    // MARK: - Autorisation

    @MainActor
    func testAuthorizationIsRequestedOnceAndARefusalIsRespected() async throws {
        let defaults = try makeDefaults()
        let system = FakePushSystem()
        system.grants = false
        let registrar = PushRegistrar(api: FakeWeydaAPI(), services: system.services(), defaults: defaults, language: { "fr" })

        // Deux écrans Messages ouverts coup sur coup : une seule alerte.
        registrar.requestAuthorizationIfNeeded()
        registrar.requestAuthorizationIfNeeded()
        await registrar.settle()
        XCTAssertEqual(system.authorizationRequests, 1)
        XCTAssertEqual(system.remoteRegistrations, 0, "refus : pas d'inscription APNs")
        XCTAssertTrue(defaults.bool(forKey: PushRegistrar.askedKey))

        // Plus tard (même lancement ou suivant) : jamais redemandé, même si iOS répondait « non déterminé ».
        system.status = .notDetermined
        registrar.requestAuthorizationIfNeeded()
        await registrar.settle()
        let relaunched = PushRegistrar(api: FakeWeydaAPI(), services: system.services(), defaults: defaults, language: { "fr" })
        relaunched.requestAuthorizationIfNeeded()
        await relaunched.settle()
        XCTAssertEqual(system.authorizationRequests, 1)
        XCTAssertEqual(system.remoteRegistrations, 0)
    }

    @MainActor
    func testAGrantedOrExistingAuthorizationRegistersWithAPNs() async throws {
        let system = FakePushSystem()
        let registrar = PushRegistrar(api: FakeWeydaAPI(), services: system.services(), defaults: try makeDefaults(), language: { "fr" })
        registrar.requestAuthorizationIfNeeded()
        await registrar.settle()
        XCTAssertEqual(system.authorizationRequests, 1)
        XCTAssertEqual(system.remoteRegistrations, 1)

        // Déjà accordée (ici ou dans Réglages) : pas d'alerte, inscription APNs.
        let granted = FakePushSystem()
        granted.status = .authorized
        let other = PushRegistrar(api: FakeWeydaAPI(), services: granted.services(), defaults: try makeDefaults(), language: { "fr" })
        other.requestAuthorizationIfNeeded()
        await other.settle()
        XCTAssertEqual(granted.authorizationRequests, 0)
        XCTAssertEqual(granted.remoteRegistrations, 1)

        // Refusée dans Réglages : rien.
        let denied = FakePushSystem()
        denied.status = .denied
        let third = PushRegistrar(api: FakeWeydaAPI(), services: denied.services(), defaults: try makeDefaults(), language: { "fr" })
        third.requestAuthorizationIfNeeded()
        await third.settle()
        XCTAssertEqual(denied.authorizationRequests, 0)
        XCTAssertEqual(denied.remoteRegistrations, 0)
    }

    // MARK: - Pastille et absence de Firebase

    @MainActor
    func testTheBadgeFollowsTheUnreadCount() throws {
        let system = FakePushSystem()
        let registrar = PushRegistrar(api: FakeWeydaAPI(), services: system.services(), defaults: try makeDefaults(), language: { "fr" })
        registrar.updateBadge(3)
        registrar.updateBadge(-2)
        registrar.updateBadge(0)
        XCTAssertEqual(system.badges, [3, 0, 0])
    }

    @MainActor
    func testNothingHappensWithoutFirebase() async throws {
        let api = FakeWeydaAPI()
        let sent = recordTokens(on: api)
        let defaults = try makeDefaults()
        let system = FakePushSystem()
        let refresh = "weyda.tests.push.refresh.\(UUID().uuidString)"
        let registrar = PushRegistrar(
            api: api,
            services: system.services(available: false, refreshName: refresh),
            defaults: defaults,
            language: { "fr" }
        )

        XCTAssertFalse(registrar.isAvailable)
        registrar.requestAuthorizationIfNeeded()
        registrar.registerCurrentToken()
        registrar.apnsTokenDidArrive()
        NotificationCenter.default.post(name: Notification.Name(refresh), object: nil)
        registrar.updateBadge(4)
        registrar.unregister()
        try await Task.sleep(nanoseconds: 50_000_000)
        await registrar.settle()

        XCTAssertEqual(api.calls, [])
        XCTAssertEqual(sent.value, [])
        XCTAssertEqual(system.totalCalls, 0, "aucune alerte système, aucun appel à Firebase")
        XCTAssertFalse(defaults.bool(forKey: PushRegistrar.askedKey))
    }

    @MainActor
    func testFirebaseStaysOffDuringUnitTests() {
        // Hôte des tests : ni GoogleService-Info.plist en CI, ni démarrage de Firebase pendant les tests unitaires.
        XCTAssertFalse(FirebasePush.isEnabled)
        XCTAssertFalse(FirebasePush.liveServices().isAvailable)
        XCTAssertFalse(PushServices.unavailable.isAvailable)
    }
}
