import Combine
import Foundation
import os

/// Autorisation de notifier, réduite à ce dont l'app a besoin (provisoire ou éphémère = accordée).
nonisolated enum PushAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

/// Branchement du registre sur le système (Firebase Messaging, UserNotifications, UIApplication) : des closures plutôt
/// qu'un protocole — le registre se teste sans Firebase ni alerte système (`PushRegistrarTests`), et aucun type Firebase
/// ou UserNotifications (non `Sendable`) ne le traverse. Services réels : `FirebasePush.liveServices()`.
nonisolated struct PushServices: Sendable {
    /// Firebase configuré : `GoogleService-Info.plist` dans l'app, ni API simulée ni tests unitaires. Faux = tout est inerte.
    var isAvailable: Bool
    var authorizationStatus: @MainActor @Sendable () async -> PushAuthorizationStatus
    /// Alerte système « Autoriser les notifications ? » ; vrai si l'utilisateur accepte.
    var requestAuthorization: @MainActor @Sendable () async -> Bool
    /// `UIApplication.registerForRemoteNotifications()` : le jeton APNs revient par l'`AppDelegate`.
    var registerForRemoteNotifications: @MainActor @Sendable () -> Void
    /// Jeton APNs déjà remis à Firebase : sans lui, le jeton FCM ne peut rien livrer (et Firebase refuse de le donner).
    var hasAPNsToken: @MainActor @Sendable () -> Bool
    /// Jeton FCM courant (nil : indisponible — réseau, APNs absent).
    var currentToken: @MainActor @Sendable () async -> String?
    /// Destruction du jeton FCM de l'appareil.
    var deleteToken: @MainActor @Sendable () async -> Void
    /// Pastille de l'icône de l'app.
    var setBadge: @MainActor @Sendable (Int) -> Void
    /// Nom de la notification postée par Firebase quand le jeton change (nil : aucune).
    var tokenRefreshNotificationName: String?

    /// Sans Firebase (CI, captures, tests unitaires) : aucun effet, aucune alerte système.
    static let unavailable = PushServices(
        isAvailable: false,
        authorizationStatus: { .denied },
        requestAuthorization: { false },
        registerForRemoteNotifications: {},
        hasAPNsToken: { false },
        currentToken: { nil },
        deleteToken: {},
        setBadge: { _ in },
        tokenRefreshNotificationName: nil
    )
}

/// Notifications push (Firebase Cloud Messaging, relayé vers APNs) — portage de `PushRegistrar`
/// (data/push/PushNotifications.kt) et de `NotificationPermissionEffect` (Android). Exposé par `AppContainer.push`.
///
/// - Jeton FCM de l'appareil rattaché au compte connecté : `POST /api/push/fcm` avec la langue de l'app et
///   `platform: "ios"` (le serveur du lot B ajoute alors l'alerte APNs traduite). Renvoyé à chaque renouvellement tant
///   qu'une session est ouverte ; détruit à la fermeture de session.
/// - Autorisation de notifier demandée au BON moment (première ouverture de Messages par un membre), une seule fois.
/// - Pastille de l'icône = notifications non lues.
/// Sans Firebase (`isAvailable` faux) : tout est sans effet, l'app vit en temps réel + cloche, comme avant.
final class PushRegistrar: ObservableObject {
    /// L'autorisation a déjà été demandée une fois : un refus est respecté (réglable ensuite dans Réglages).
    static let askedKey = "push_permission_asked"
    private static let logger = Logger(subsystem: "com.weydaa.app", category: "push")

    private let api: any WeydaAPI
    private let services: PushServices
    private let defaults: UserDefaults
    private let language: @MainActor () -> String

    /// Une session est ouverte : le jeton courant (et chacun de ses renouvellements) est rattaché au compte.
    private var wantsRegistration = false
    /// Dernier jeton accepté par le serveur pendant cette session : pas de requête en double.
    private var submittedToken: String?
    private var isAskingAuthorization = false
    private var tokenTask: Task<Void, Never>?
    private var deletionTask: Task<Void, Never>?
    /// Travail en cours (chaque tâche se retire à la fin) : `settle()` l'attend dans les tests.
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private var tokenObserver: (any NSObjectProtocol)?

    init(
        api: any WeydaAPI,
        services: PushServices,
        defaults: UserDefaults = .standard,
        language: @escaping @MainActor () -> String = { WeydaLocale.language }
    ) {
        self.api = api
        self.services = services
        self.defaults = defaults
        self.language = language
        observeTokenRefresh()
    }

    /// Firebase configuré : `GoogleService-Info.plist` présent dans l'app, ni API simulée ni tests unitaires. Faux en CI
    /// → tout est sans effet.
    var isAvailable: Bool { services.isAvailable }

    /// Demande l'autorisation de notifier — à appeler quand un MEMBRE ouvre Messages (`ConversationsView`), jamais au
    /// lancement : c'est là que la raison est évidente. Une seule fois (un refus est respecté) ; accordée → inscription
    /// auprès d'APNs. Sans Firebase : rien (aucune alerte système dans les tours de captures).
    func requestAuthorizationIfNeeded() {
        guard services.isAvailable, !isAskingAuthorization else { return }
        isAskingAuthorization = true
        run { [weak self] in
            await self?.askAuthorization()
            self?.isAskingAuthorization = false
        }
    }

    /// Session ouverte (connexion ou démarrage avec une session, `AppContainer`) : le jeton courant est rattaché au compte.
    func registerCurrentToken() {
        guard services.isAvailable else { return }
        wantsRegistration = true
        submitToken()
    }

    /// Fermeture de session (`AppContainer`) : le jeton FCM est détruit sur l'appareil, comme Android — le serveur ne peut
    /// plus rien y envoyer (il le purge au premier envoi refusé) ; un nouveau jeton suivra le prochain compte connecté.
    func unregister() {
        wantsRegistration = false
        submittedToken = nil
        tokenTask?.cancel()
        tokenTask = nil
        guard services.isAvailable else { return }
        let deleteToken = services.deleteToken
        deletionTask = run { await deleteToken() }
    }

    /// Jeton APNs reçu (`AppDelegate`) : le jeton FCM peut enfin livrer — envoyé au serveur si une session est ouverte.
    func apnsTokenDidArrive() {
        submitToken()
    }

    /// Pastille de l'icône (notifications non lues ; 0 à la déconnexion).
    func updateBadge(_ count: Int) {
        guard services.isAvailable else { return }
        services.setBadge(max(count, 0))
    }

    /// Tests : attend la fin du travail lancé (autorisation, envoi ou destruction du jeton).
    func settle() async {
        while let task = inFlight.values.first {
            await task.value
        }
    }

    // MARK: - Interne

    private func askAuthorization() async {
        switch await services.authorizationStatus() {
        case .authorized:
            // Déjà accordée (ici ou dans Réglages) : inscription APNs, le jeton peut avoir changé.
            services.registerForRemoteNotifications()
        case .denied:
            break
        case .notDetermined:
            guard !defaults.bool(forKey: Self.askedKey) else { return }
            defaults.set(true, forKey: Self.askedKey)
            if await services.requestAuthorization() {
                services.registerForRemoteNotifications()
            }
        }
    }

    /// Envoie le jeton courant s'il le faut : session ouverte, jeton APNs connu (sinon on attend `apnsTokenDidArrive`),
    /// jeton différent du dernier accepté. La destruction en cours (déconnexion juste avant) passe d'abord.
    private func submitToken() {
        guard services.isAvailable, wantsRegistration, services.hasAPNsToken() else { return }
        tokenTask?.cancel()
        let deletion = deletionTask
        tokenTask = run { [weak self] in
            if let deletion {
                await deletion.value
            }
            await self?.sendCurrentToken()
        }
    }

    private func sendCurrentToken() async {
        guard wantsRegistration, !Task.isCancelled else { return }
        let fetched = await services.currentToken()
        guard let token = TextCheck.nonBlank(fetched) else { return }
        guard wantsRegistration, !Task.isCancelled, token != submittedToken else { return }
        do {
            _ = try await api.registerFcmToken(FcmTokenRequestDTO(token: token, locale: language()))
            if wantsRegistration {
                submittedToken = token
            }
        } catch {
            // Hors ligne, serveur indisponible… : nouvel essai au prochain retour au premier plan ou renouvellement.
            Self.logger.notice("Jeton push non enregistré : \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Jeton renouvelé par Firebase : renvoyé au serveur si une session est ouverte (Android : `onNewToken`).
    private func observeTokenRefresh() {
        guard services.isAvailable, let name = services.tokenRefreshNotificationName else { return }
        tokenObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(name),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.submitToken()
            }
        }
    }

    @discardableResult
    private func run(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.inFlight[id] = nil
        }
        inFlight[id] = task
        return task
    }
}
