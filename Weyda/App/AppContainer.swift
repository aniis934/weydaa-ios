import Combine
import Foundation
import SwiftUI
import UIKit

/// Injection de dépendances manuelle — miroir d'`AppContainer` (Android). Créé une fois par `WeydaApp`, transmis par
/// l'environnement SwiftUI. Réseau, session, images, puis un repository par domaine (noms fixés : les écrans les
/// utilisent tels quels).
final class AppContainer: ObservableObject {
    let config: AppConfig
    /// Session HTTP de l'API : cookies coupés (l'app s'authentifie par jeton Bearer, jamais par
    /// cookie de session web). En API simulée (Debug), les réponses viennent de MockFixtures.
    let apiSession: URLSession
    /// Client SANS jeton : connexion (`api/auth/token`, Google, Apple), rotation (`…/token/refresh`), inscription,
    /// mot de passe oublié (Android : `authApi`).
    let authClient: APIClient
    /// Session unique (jetons + utilisateur), restaurée du trousseau au démarrage.
    let sessionManager: SessionManager
    /// Client authentifié : Bearer de la session, rotation des jetons et rejeu sur 401 (Android : `api`).
    let apiClient: APIClient
    /// En ligne / hors ligne : un seul moniteur pour toute l'app (bandeau, relance des écrans en erreur).
    let connectivity: ConnectivityMonitor
    /// Toutes les routes de l'API (`LiveWeydaAPI` sur les deux clients ci-dessus).
    let api: any WeydaAPI
    /// Chargeur d'images (photos d'annonces, avatars) ; passe par l'API simulée en Debug avec `-WeydaMockAPI YES`.
    let images: ImagePipeline
    /// Temps réel : UNE WebSocket Phoenix pour toute l'app (Android : `realtimeClient`). Inerte sans configuration
    /// Supabase, et en API simulée (captures reproductibles) ; fermée en arrière-plan (`scenePhaseChanged`).
    let realtime: RealtimeClient

    let annonces: AnnonceRepository
    let categories: CategoryRepository
    let attributes: AttributeRepository
    let geo: GeoRepository
    let search: SearchRepository
    let sellers: SellerRepository
    let reviews: ReviewsRepository
    let reports: ReportsRepository
    let auth: AuthRepository
    let users: UserRepository
    let accountData: AccountDataRepository
    let favorites: FavoritesRepository
    let savedSearches: SavedSearchesRepository
    let conversations: ConversationsRepository
    let notifications: NotificationsRepository
    let uploads: UploadRepository

    /// Notifications push (Firebase → APNs) : jeton de l'appareil rattaché au compte connecté, autorisation de notifier,
    /// pastille de l'icône. Inerte sans `GoogleService-Info.plist`, en API simulée et pendant les tests unitaires.
    /// Android : `pushRegistrar`.
    let push: PushRegistrar

    /// Brouillon du NOUVEAU dépôt (`Application Support/PostDrafts/post_draft.json`) : survit à la fermeture de l'app,
    /// effacé à la déconnexion volontaire (gardé si la session tombe d'elle-même). Android : `postDraftStore`.
    let postDrafts: FilePostDraftStore
    /// Photos choisies pour le nouveau dépôt, pas encore publiées (`PostDrafts/new/`).
    let postPhotos: PostPhotoStore
    /// Demande de note App Store : au 2e moment positif, une fois par version (inerte en API simulée et en test).
    let reviewPrompter: ReviewPrompter

    /// Historique de recherche : UNE instance pour toute l'app (accueil + Annonces), vidée à la déconnexion.
    private let searchHistory: SearchHistoryStore
    private var sessionSubscription: AnyCancellable?
    /// Pastille de l'icône de l'app = notifications non lues (comme la cloche).
    private var badgeSubscription: AnyCancellable?
    private var memoryWarningObserver: (any NSObjectProtocol)?
    /// Dernier utilisateur vu : une fermeture de session ne déclenche le ménage que si une session existait.
    private var lastUserId: String?
    /// Travail lancé à l'ouverture d'une session (pastille Messages, langue du compte), annulé à la fermeture.
    private var sessionWork: Task<Void, Never>?
    /// Langue déjà enregistrée sur le compte pendant ce lancement (une requête par langue et par session).
    private var syncedLocale: String?
    /// La scène est passée en arrière-plan depuis le dernier retour au premier plan (pastilles à relire).
    private var wasInBackground = false

    init(config: AppConfig = .current, mockAPI: Bool = LaunchOptions.mockAPI) {
        self.config = config
        let apiSession = Self.makeAPISession(mockAPI: mockAPI)
        self.apiSession = apiSession

        let authClient = APIClient(baseURL: config.apiBaseURL, session: apiSession)
        self.authClient = authClient

        // Lecture du trousseau de quelques ms au démarrage : la session est connue avant le premier écran.
        let sessionManager = SessionManager(
            storage: Self.makeSessionStorage(mockAPI: mockAPI),
            refreshCall: { refreshToken in
                try await authClient.send(
                    .post("api/auth/token/refresh", json: RefreshRequestDTO(refreshToken: refreshToken)),
                    as: TokenResponseDTO.self
                )
            }
        )
        sessionManager.restore()
        self.sessionManager = sessionManager

        let apiClient = APIClient(
            baseURL: config.apiBaseURL,
            session: apiSession,
            authorization: sessionManager.authorization
        )
        self.apiClient = apiClient
        self.connectivity = ConnectivityMonitor()
        self.images = Self.makeImagePipeline(mockAPI: mockAPI)
        // Active au premier passage de la scène au premier plan (`scenePhaseChanged`).
        self.realtime = RealtimeClient(
            supabaseURL: mockAPI ? nil : config.supabaseURL,
            anonKey: config.supabaseAnonKey,
            startActive: false
        )

        let api = LiveWeydaAPI(client: apiClient, authClient: authClient)
        self.api = api
        let searchHistory = SearchHistoryStore()
        self.searchHistory = searchHistory

        annonces = AnnonceRepository(api: api)
        categories = CategoryRepository(api: api)
        attributes = AttributeRepository(api: api)
        geo = GeoRepository(api: api)
        search = SearchRepository(api: api, history: searchHistory)
        sellers = SellerRepository(api: api)
        reviews = ReviewsRepository(api: api)
        reports = ReportsRepository(api: api)
        auth = AuthRepository(api: api, session: sessionManager)
        users = UserRepository(api: api, session: sessionManager)
        accountData = AccountDataRepository(api: api, session: sessionManager)
        // Les favoris suivent la session d'eux-mêmes : vidés à la déconnexion, rechargés à la connexion (une fois
        // l'e-mail vérifié : `GET /api/favorites` répond 403 avant).
        favorites = FavoritesRepository(api: api, sessionUser: sessionManager.$user.eraseToAnyPublisher())
        savedSearches = SavedSearchesRepository(api: api)
        conversations = ConversationsRepository(api: api)
        notifications = NotificationsRepository(api: api)
        uploads = UploadRepository(api: api)
        // Avant `observeSession` : une session restaurée au démarrage rattache tout de suite le jeton push.
        push = PushRegistrar(api: api, services: Self.makePushServices(mockAPI: mockAPI))

        let postStores = Self.makePostDraftStores(mockAPI: mockAPI)
        postDrafts = postStores.drafts
        postPhotos = postStores.photos
        reviewPrompter = ReviewPrompter(isEnabled: ReviewPrompter.isAllowed && !mockAPI)

        observeSession()
        observeBadge()
        observeMemoryWarnings()
        purgeStaleCaptures()
    }

    /// Aligne la langue du compte (e-mails, notifications) sur celle de l'application : une requête par langue et
    /// par session ; un échec sera retenté à la prochaine ouverture de session.
    func syncAccountLocale() async {
        guard sessionManager.user != nil else { return }
        let locale = WeydaLocale.language
        guard syncedLocale != locale else { return }
        syncedLocale = locale
        let saved = await users.syncLocale(locale)
        if !saved {
            syncedLocale = nil
        }
    }

    // MARK: - Effets de session (portage de `observeUserChannel`, sans le temps réel)

    private func observeSession() {
        sessionSubscription = sessionManager.$user
            .map { $0?.id }
            .removeDuplicates()
            .sink { [weak self] userId in
                self?.sessionChanged(to: userId)
            }
    }

    /// Toute ouverture (connexion, restauration au démarrage) et toute fermeture (déconnexion, jetons révoqués,
    /// compte supprimé) de session passe ici.
    private func sessionChanged(to userId: String?) {
        let previous = lastUserId
        lastUserId = userId
        sessionWork?.cancel()
        sessionWork = nil
        guard let userId else {
            sessionClosed(hadSession: previous != nil)
            return
        }
        sessionOpened(userId: userId)
    }

    /// Pastilles à 0 ; si une session vient vraiment de se fermer (un visiteur garde son historique) : traces
    /// locales de l'utilisateur sortant effacées (export, captures, historique de recherche). Les favoris se
    /// vident d'eux-mêmes (`FavoritesRepository`).
    private func sessionClosed(hadSession: Bool) {
        conversations.publishUnread(0)
        notifications.reset()
        guard hadSession else { return }
        // Plus aucun push de l'ancien compte vers cet appareil : jeton FCM détruit et pastille de l'icône à 0, à TOUTE
        // fermeture de session comme Android (une session expirée ou révoquée ne doit pas continuer d'afficher les
        // messages du compte sur un appareil déconnecté).
        push.unregister()
        push.updateBadge(0)
        accountData.clearLocalFiles()
        search.clearHistory()
        // Brouillon de dépôt et ses photos : effacés à la déconnexion VOLONTAIRE, même si l'assistant n'est plus à
        // l'écran (règle d'`onAccountChanged`, Android) ; gardés quand la session tombe d'elle-même (refresh refusé) :
        // le même compte les retrouve en se reconnectant, un autre compte ne les voit jamais (contrôle du propriétaire).
        if !sessionManager.lastSignOutExpired {
            postDrafts.clear()
            postPhotos.purge(keeping: [])
            PostPhotoStore.standard(namespace: "edit").purge(keeping: [])
        }
    }

    /// Pastille Messages relue, langue du compte enregistrée une fois, puis écoute du canal personnel signé
    /// (`user:{id}:{hmac}`, fourni par `GET /api/notifications`) : il tient la cloche et l'onglet Messages à jour
    /// hors de tout écran. Annulé à la fermeture de la session (le canal est alors quitté). Les favoris se
    /// chargent d'eux-mêmes.
    private func sessionOpened(userId: String) {
        syncedLocale = nil
        // Jeton push rattaché au compte (envoyé dès que le jeton APNs est connu ; sans Firebase : rien).
        push.registerCurrentToken()
        sessionWork = Task { [weak self] in
            guard let self else { return }
            _ = try? await self.conversations.refreshUnread(userId: userId)
            await self.syncAccountLocale()
            guard let topic = await self.awaitUserTopic(userId: userId) else { return }
            for await event in self.realtime.userEvents(topic: topic) {
                switch event {
                case .notificationReceived(let notification):
                    self.notifications.onRealtime(notification)
                case .conversationTouched:
                    _ = try? await self.conversations.refreshUnread(userId: userId)
                    self.conversations.notifyTouched()
                default:
                    break
                }
            }
        }
    }

    /// Topic du canal personnel, redemandé tant que la REQUÊTE échoue (2 s → 60 s) : un démarrage hors ligne ne
    /// doit pas priver la cloche de temps réel pour tout le lancement. Une réponse sans topic (temps réel non
    /// configuré côté serveur) clôt l'attente. Miroir d'`awaitUserTopic` (Android).
    private func awaitUserTopic(userId: String) async -> String? {
        var wait: UInt64 = 2_000_000_000
        while !Task.isCancelled {
            if let page = try? await notifications.page(page: 1, limit: 20) {
                return TextCheck.nonBlank(page.topic)
            }
            try? await Task.sleep(nanoseconds: wait)
            wait = min(wait * 2, 60_000_000_000)
            _ = try? await conversations.refreshUnread(userId: userId)
        }
        return nil
    }

    // MARK: - Push

    /// Pastille de l'icône = notifications non lues (`notifications.unreadCount`, tenu par la première page et le canal
    /// personnel) ; remise à 0 avec lui à la fermeture de session. Sans Firebase : sans effet.
    private func observeBadge() {
        let push = self.push
        badgeSubscription = notifications.$unreadCount
            .removeDuplicates()
            .sink { count in
                push.updateBadge(count)
            }
    }

    /// Services réels (Firebase, centre de notifications) seulement hors API simulée et hors tests unitaires : ni
    /// alerte système ni réseau Firebase dans la CI et les tours de captures.
    private static func makePushServices(mockAPI: Bool) -> PushServices {
        guard !mockAPI, !LaunchOptions.isRunningUnitTests else { return .unavailable }
        return FirebasePush.liveServices()
    }

    // MARK: - Premier plan / arrière-plan

    /// Appelé par la scène (`WeydaApp`). `.inactive` (centre de contrôle, sélecteur d'apps) ne change rien.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            realtime.setActive(true)
            // Retour au premier plan (pas le premier lancement) : ce qui est arrivé pendant l'absence n'est pas
            // passé par la socket, fermée en arrière-plan — les pastilles sont relues (Android : refreshOnForeground).
            if wasInBackground, let userId = sessionManager.user?.id {
                // Jeton push : renvoyé seulement s'il a changé ou si le dernier envoi a échoué (hors ligne).
                push.registerCurrentToken()
                Task { [weak self] in
                    guard let self else { return }
                    _ = try? await self.conversations.refreshUnread(userId: userId)
                    _ = try? await self.notifications.page(page: 1, limit: 20)
                }
            }
            wasInBackground = false
        case .background:
            realtime.setActive(false)
            wasInBackground = true
        default:
            break
        }
    }

    // MARK: - Mémoire et fichiers

    /// Alerte mémoire : images décodées libérées (le cache disque reste).
    private func observeMemoryWarnings() {
        let images = self.images
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            images.removeAllFromMemory()
        }
    }

    /// Captures de dépôt abandonnées depuis plus de 24 h : effacées au démarrage, hors du fil principal.
    private func purgeStaleCaptures() {
        let directory = accountData.cameraDirectory
        Task.detached(priority: .utility) {
            AccountDataRepository.purgeStaleCaptures(in: directory)
        }
    }

    // MARK: - Fabriques

    private static func makeAPISession(mockAPI: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        #if DEBUG
        if mockAPI {
            configuration.protocolClasses = [MockURLProtocol.self]
        }
        #endif
        return URLSession(configuration: configuration)
    }

    /// `ImagePipeline.shared` (qui suit `-WeydaMockAPI`) ; un conteneur créé avec un autre choix (tests) a le sien.
    private static func makeImagePipeline(mockAPI: Bool) -> ImagePipeline {
        #if DEBUG
        if mockAPI != LaunchOptions.mockAPI {
            let protocols: [AnyClass] = mockAPI ? [MockURLProtocol.self] : []
            return ImagePipeline(session: ImagePipeline.makeSession(protocolClasses: protocols), disk: nil)
        }
        #endif
        return ImagePipeline.shared
    }

    /// Brouillon de dépôt et photos : `Application Support/PostDrafts/`. En API simulée (Debug) : un dossier temporaire
    /// VIDÉ à chaque lancement — comme la session en mémoire, chaque capture du tour part du même état et le brouillon
    /// réel de l'appareil n'est jamais touché ; avec `-WeydaPostDraft <nom>`, le brouillon
    /// `MockFixtures/post/drafts/<nom>.json` y est écrit tel quel avant la création de l'assistant.
    private static func makePostDraftStores(mockAPI: Bool) -> (drafts: FilePostDraftStore, photos: PostPhotoStore) {
        #if DEBUG
        if mockAPI {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeydaMockPostDrafts", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            let drafts = FilePostDraftStore(fileURL: root.appendingPathComponent("post_draft.json", isDirectory: false))
            if let name = LaunchOptions.postDraft, let raw = mockPostDraft(named: name) {
                drafts.write(raw)
            }
            return (drafts: drafts, photos: PostPhotoStore(directory: root.appendingPathComponent("new", isDirectory: true)))
        }
        #endif
        return (drafts: FilePostDraftStore.standard(), photos: PostPhotoStore.standard(namespace: "new"))
    }

    #if DEBUG
    /// Contenu brut d'un brouillon simulé (même dossier de ressources que `MockRoutes`) ; nom inconnu → nil.
    private static func mockPostDraft(named name: String) -> String? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent(MockRoutes.directory, isDirectory: true)
            .appendingPathComponent("post", isDirectory: true)
            .appendingPathComponent("drafts", isDirectory: true)
            .appendingPathComponent("\(name).json", isDirectory: false),
            let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    #endif

    /// Trousseau, purgé au premier lancement d'une nouvelle installation. En API simulée (Debug) : session
    /// en mémoire, jamais dans le trousseau — chaque lancement du tour de captures part du même état ; avec
    /// `-WeydaLoggedIn`, elle est déjà ouverte au nom de l'utilisateur fictif de référence.
    private static func makeSessionStorage(mockAPI: Bool) -> any SessionStorage {
        #if DEBUG
        if mockAPI {
            guard let mockSession = LaunchOptions.mockSession else { return InMemorySessionStorage() }
            return InMemorySessionStorage(
                tokens: MockSessionFixture.tokens(),
                user: MockSessionFixture.user(emailVerified: mockSession == .verified)
            )
        }
        #endif
        let keychain = KeychainSessionStorage()
        keychain.purgeIfFreshInstall(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        return keychain
    }
}

#if DEBUG
/// Session simulée des captures (`-WeydaLoggedIn`, API simulée) : l'utilisateur FICTIF de référence — les réponses
/// simulées de `GET /api/users/me` le reprennent à l'identique — et des jetons factices valables un an.
nonisolated enum MockSessionFixture {
    static let userId = "mock-me"

    static func user(emailVerified: Bool) -> User {
        User(
            id: userId,
            name: "Yacine Benali",
            email: "yacine.benali@example.com",
            avatarUrl: nil,
            role: "USER",
            emailVerified: emailVerified,
            phone: "0555000000",
            phoneCountryCode: "+213",
            bio: "Particulier à Alger, je vends ce dont je ne me sers plus.",
            isRecommended: false,
            memberSince: DateParsing.parseInstant("2025-03-14T10:00:00.000Z"),
            hasPassword: true
        )
    }

    static func tokens(now: Date = Date()) -> AuthTokens {
        let expiry = now.addingTimeInterval(365 * 86_400)
        return AuthTokens(
            accessToken: "mock-access-token",
            refreshToken: "mock-refresh-token",
            accessExpiresAt: expiry,
            refreshExpiresAt: expiry
        )
    }
}
#endif
