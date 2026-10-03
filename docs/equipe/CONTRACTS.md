# Équipe iOS Weyda — contrats communs (lu par TOUS les agents)

Dépôt iOS : `../weydaa-ios` (branche courante, NE PAS changer de branche).
Référence Android (dépôt privé, LECTURE SEULE) : `../weydaa-site/android/`
  - code : `app/src/main/java/com/weydaa/app/` · tests : `app/src/test/java/com/weydaa/app/`
  - contrat d'API : `docs/API-CONTRACT.md`
Notes partagées entre agents : `<ce dossier>/notes/<agent>.md` (chacun écrit la SIENNE, lit celles des autres).

## Règles d'équipe
1. **Aucune commande git** (ni commit, ni checkout, ni stash, ni add) : l'orchestrateur s'en charge.
2. **Propriété des fichiers** : n'écris QUE dans les fichiers/dossiers attribués à ton agent. Besoin d'une
   modification ailleurs → écris-la dans ta note (section « Demandes ») ; l'orchestrateur l'applique.
3. **Pas de Mac, pas de compilateur Swift sur le poste** : chaque erreur de compilation coûte 10 min de CI.
   Relis chaque fichier comme un compilateur Swift 6.2 strict (voir « Pièges » ci-dessous) AVANT de rendre.
4. **Dépôt PUBLIC** : aucun secret, aucune donnée personnelle réelle. Fixtures/tests : noms, e-mails,
   téléphones FICTIFS (ex. « Karim B. », `test@example.com`, `0555 00 00 00`). Jamais de vraie réponse de prod.
5. **Commentaires en français**, concis, dans le ton du code existant (expliquer le POURQUOI, citer l'équivalent
   Android quand c'est un portage). Pas de texte visible en dur : `L10n.xxx` (voir `Weyda/Core/Localization/L10n.swift`,
   généré, 542 clés issues d'Android). Chaîne manquante → la demander dans ta note (fr + ar + en), ne pas éditer
   `L10n.swift` ni `Localizable.xcstrings` (générés).
6. **Aucune dépendance externe** (pas de SPM). Frameworks Apple seulement (Foundation, SwiftUI, UIKit, ImageIO,
   Network, Security, CryptoKit, os…).
7. Lis `weydaa-ios/CLAUDE.md` (conventions anti-erreurs) avant d'écrire.
8. À la fin : ta note doit lister (a) les fichiers créés, (b) l'API publique (signatures) que les autres
   utiliseront, (c) les écarts avec Android et pourquoi, (d) les demandes, (e) les points douteux pour la compil.

## Réglages du projet (project.yml)
Swift 6, iOS 16.0 minimum, Xcode 26.6 (SDK iOS 26), `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
`SWIFT_APPROACHABLE_CONCURRENCY = YES` (⇒ `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`…),
`SWIFT_STRICT_CONCURRENCY = complete`. Les fichiers sous `Weyda/` et `WeydaTests/` sont pris automatiquement
(pas besoin de toucher project.yml). La cible de tests N'A PAS l'isolation MainActor par défaut.

## Pièges Swift 6.2 (MainActor par défaut) — à respecter strictement
- Tout type de DONNÉES ou de logique pure : `nonisolated struct/enum/final class`. Ses extensions :
  `nonisolated extension Foo { … }` (une extension NON marquée retombe en MainActor !).
- Fonctions/constantes globales : éviter ; sinon `nonisolated func`. Préférer `static let` dans un
  `nonisolated enum` (une `let` globale serait MainActor).
- Protocoles utilisés hors du fil principal : `nonisolated protocol P: Sendable`.
- Un type MainActor (par défaut) qui se conforme à un protocole → conformité isolée MainActor
  (InferIsolatedConformances) : inutilisable depuis du code nonisolated. D'où : types de données nonisolated,
  et branchements entre couches par **closures `@Sendable`** plutôt que par protocoles quand un côté est MainActor.
- `async` nonisolated = s'exécute chez l'appelant. Travail lourd (réseau + décodage JSON) : `@concurrent func`.
- Pas de `Mutex` (iOS 18) : `OSAllocatedUnfairLock` (iOS 16, `import os`) ou un `actor`.
- `NSCache`, `JSONDecoder`, `NSRegularExpression`… dans un type `Sendable` : créer à la demande, ou envelopper
  dans une classe `final class … : @unchecked Sendable` avec un commentaire qui justifie (thread-safe par nature).
- Pas de `Regex` littérale stockée en `static` (Regex n'est pas Sendable) : fonctions de String ou NSRegularExpression local.
- Closures de callbacks système (NWPathMonitor, URLSession delegate…) : `@Sendable`, retour au fil principal par
  `Task { @MainActor in … }`.
- Pas d'`isolated deinit`, pas de `@Observable` (iOS 17), pas de `ContentUnavailableView`, pas de `Mutex`,
  pas d'API iOS 17+ sans `if #available(iOS 17, *)` + repli.
- Codable : `init(from:)` écrit à la main avec `decodeIfPresent` + valeurs par défaut quand Android a des
  défauts (tolérance = `ignoreUnknownKeys`, `coerceInputValues`). Un `Double` peut arriver en chaîne → lecteur tolérant.
- Pas de `[String: Any]` dans un modèle (pas Sendable) : utiliser `JSONValue` (enum Codable/Sendable/Hashable).
- `Date` : les DTO gardent les dates en `String?` (ISO 8601, millisecondes facultatives) ; les mappers les parsent
  (comme `parseInstant` Android). Formatter ISO créé à la demande (ISO8601DateFormatter n'est pas Sendable).
- Tests XCTest : classes `final class XxxTests: XCTestCase` ; méthode qui touche un type MainActor → `@MainActor func test…`
  (ou classe entière `@MainActor`). `async throws` autorisé. `@testable import Weyda`.
- Pas de `print` dans le code de l'app : `os.Logger(subsystem: "com.weydaa.app", category: "…")` si besoin.

## Conventions de portage Kotlin → Swift (identiques pour tous)
- Noms de types du domaine IDENTIQUES à Android (`Listing`, `Seller`, `Category`, `User`, `AuthTokens`,
  `ChatMessage`, `Conversation`, `AppNotification`…). DTO : suffixe `DTO` (`AnnonceDto` → `AnnonceDTO`,
  `TokenResponseDto` → `TokenResponseDTO`, `AuthUserDto` → `AuthUserDTO`, `MeDto` → `MeDTO`).
- `data class` → `nonisolated struct … : Hashable, Sendable` (+ `Codable` si stocké ou échangé).
- `enum class` → `nonisolated enum … : String, CaseIterable, Sendable` ; cas en lowerCamelCase, `rawValue` = valeur
  « fil » (`case fixed = "FIXED"`), `static func from(_ raw: String?) -> Self` avec le même repli qu'Android.
- `Instant` → `Date` ; `Long` → `Int` ; `Map<String,String>` → `[String: String]` ; `List<T>` → `[T]`.
- `sealed interface` → `enum` à valeurs associées.
- Mappers Android (`fun AnnonceDto.toDomain(): Listing`) → `nonisolated extension AnnonceDTO { func toDomain() -> Listing }`.
- Paramètres `clock: Clock` d'Android → `now: Date = Date()` (testable).
- Erreurs : pas de `Result` Kotlin ; les repositories sont `async throws`. L'annulation (`CancellationError`,
  `URLError.cancelled`) ne doit JAMAIS s'afficher comme une erreur (voir `ErrorMapper`).

## Noms fixés d'avance (pour travailler en parallèle sans se marcher dessus)
Agent DATA (Models/DTO/Mappers) les définit EXACTEMENT ainsi ; les autres agents peuvent les utiliser :
```swift
nonisolated enum PriceType: String, CaseIterable, Codable, Sendable { case fixed = "FIXED", negotiable = "NEGOTIABLE", free = "FREE"; static func from(_ raw: String?) -> PriceType }
nonisolated enum ListingStatus: String, CaseIterable, Codable, Sendable { case pending = "PENDING", active = "ACTIVE", sold = "SOLD", expired = "EXPIRED", rejected = "REJECTED" }
nonisolated enum AttributeType: String, CaseIterable, Codable, Sendable { case select = "SELECT", number = "NUMBER", boolean = "BOOLEAN", text = "TEXT" }
nonisolated enum Requirement: String, CaseIterable, Codable, Sendable { case required = "REQUIRED", recommended = "RECOMMENDED", optional = "OPTIONAL" }
nonisolated struct LocalizedName: Hashable, Codable, Sendable { let fr, ar, en: String; func resolve(_ language: String = WeydaLocale.language) -> String }
nonisolated struct AttributeOption: Hashable, Sendable { let value: String; let label: String }
nonisolated struct AttributeDefinition: Hashable, Sendable { key, label, type: AttributeType, requirement: Requirement, options: [AttributeOption], dependsOn: String?, min/max/step: Double?, unit/unitLabel: String?, rangePresets: [Double], filterable: Bool, filterType: String ; isRequired, isDependent, optionLabel(_:), static displayLabel(_:) }
nonisolated struct User: Hashable, Codable, Sendable { id, name: String?, email, avatarUrl: String?, role, emailVerified: Bool, phone, phoneCountryCode, bio: String?, isRecommended: Bool, memberSince: Date?, hasPassword: Bool ; displayName, isStaff, maxImages }
nonisolated struct AuthTokens: Hashable, Codable, Sendable { accessToken, refreshToken: String; accessExpiresAt, refreshExpiresAt: Date ; func isAccessExpiring(within seconds: TimeInterval, now: Date = Date()) -> Bool ; func isRefreshExpired(now: Date = Date()) -> Bool }
nonisolated struct TokenResponseDTO: Decodable, Sendable { accessToken, refreshToken, tokenType: String; expiresIn, refreshExpiresIn: Int; user: AuthUserDTO; isNewUser: Bool ; func toTokens(now: Date = Date()) -> AuthTokens }
nonisolated struct AuthUserDTO: Decodable, Sendable { … ; func toDomain(previous: User? = nil) -> User }
```
(`User` est `Codable` : c'est le format de stockage local — pas de `StoredUserDto` séparé sur iOS.)

Agent NETWORK définit EXACTEMENT :
```swift
nonisolated struct APIError: Error, Sendable, Equatable { let status: Int; let code: String; let retryAfterSeconds: Int?; let remainingAttempts: Int?; let fieldErrors: [String: String]; let attributeErrors: [String: String]; var isUnauthorized: Bool; var isEmailNotVerified: Bool }
nonisolated struct APIAuthorization: Sendable {   // branchement du client HTTP sur la session
    var accessToken: @Sendable () async -> String?
    var refreshAfterUnauthorized: @Sendable (_ failedAccessToken: String) async -> String?
    static let none: APIAuthorization
}
nonisolated final class APIClient: Sendable { … }   // API détaillée dans notes/network.md
nonisolated enum ErrorMapper { static func message(for error: Error) -> String? }  // nil = annulation (ne rien afficher)
```
Agent UTILS définit EXACTEMENT :
```swift
nonisolated enum ImagePreparationError: Error, Sendable, Equatable { case unreadable, tooLarge }  // ErrorMapper le traduit
```

## Arborescence cible (propriétaires)
```
Weyda/Core/Models/          DATA     Models.swift (+ JSONValue.swift)            UTILS: OfferRules.swift
Weyda/Core/Network/DTO/     DATA     *DTOs.swift (un fichier par fichier dto/*.kt)
Weyda/Core/Mapping/         DATA     Mappers.swift (+ DateParsing.swift)
Weyda/Core/Network/         NETWORK  HTTPMethod/APIRequest/APIClient/APIError/APIAuthorization/Connectivity
Weyda/Core/Session/         NETWORK  SessionManager, SessionStorage, KeychainStore
Weyda/Core/Common/          NETWORK  ErrorMapper.swift
                            UTILS    Format.swift, Validators.swift, Paging.swift
Weyda/Core/Images/          UTILS    pipeline d'images (+ vue RemoteImage)
Weyda/Core/Upload/          UTILS    ImagePreparer.swift
Weyda/Core/Local/           UTILS    SearchHistoryStore.swift
Weyda/App/DeepLinks.swift   UTILS
WeydaTests/                 chacun ses fichiers : DATA → Mappers*Tests ; NETWORK → APIClient/APIError/ErrorMapper/Session*Tests ;
                            UTILS → Validators/Paging/OfferRules/DeepLinks/Format/ImagePreparer/SearchHistory*Tests
(vague 2, plus tard : Core/Network/WeydaAPI.swift + LiveWeydaAPI.swift, Core/Repositories/, Core/Realtime/, Mock/MockFixtures/)
```

## Vague 2 — repositories (signatures FIXÉES, portées d'Android `data/repository/*.kt`)
Classes `final class XxxRepository` (MainActor, isolation par défaut) ; méthodes `async throws` (pas de `Result`).
Celles qui ont un état observé par l'UI sont `ObservableObject` avec `@Published private(set)`.
Construites par `AppContainer` avec `api: any WeydaAPI` (protocole `nonisolated protocol WeydaAPI: Sendable`,
une méthode par endpoint de `WeydaApi.kt`, implémenté par `LiveWeydaAPI` sur `APIClient`, et par `FakeWeydaAPI` dans les tests).
```swift
AnnonceRepository     search(_ query: ListingQuery) -> ListingPage · featured(limit: Int = 8) -> [Listing] · recent(limit: Int = 12) -> [Listing]
                      trending(limit: Int = 12) -> [Listing] · recommendations() -> [Listing] · similar(to listing: Listing, limit: Int = 8) -> [Listing]
                      didYouMean(_ q: String) -> String? · countView(id: String) (silencieux, non-throws) · detail(idOrSlug: String) -> Listing
                      create(_ s: ListingSubmission) -> Listing · update(id: String, _ s: ListingSubmission) -> Listing · markSold(id:) -> Listing
                      delete(id:) · renew(id:) -> Int?
CategoryRepository    roots(forceRefresh: Bool = false) -> [Category]                         (cache mémoire comme Android)
AttributeRepository   attributes(categorySlug: String, subcategory: String?, locale: String = WeydaLocale.language) -> AttributeSet
                      dependentOptions(categorySlug:subcategory:key:context:locale:) -> [AttributeOption]
GeoRepository         wilayas() -> [Wilaya] · communes(wilayaId: Int) -> [Commune] · topWilayas(limit: Int = 10) -> [Wilaya]
SearchRepository      ObservableObject : @Published history: [String], @Published pendingParams: [String: String]?
                      suggestions(_ q: String, locale: String = WeydaLocale.language) -> [Suggestion] · loadHistory() · remember(_ q: String) · clearHistory()
SellerRepository      profile(id:) -> Seller · listings(id:page:limit:) -> ListingPage
ReviewsRepository     forSeller(_ sellerId: String, limit: Int = 3) -> ReviewSummary · eligibility(sellerId:) -> ReviewEligibility · submit(sellerId:rating:comment:)
ReportsRepository     report(annonceId:reason:details:) · reportUser(userId:conversationId:reason:details:)
AuthRepository        user (via session) · isLoggedIn · sessionExpired · login(email:password:) -> User · loginWithGoogle(idToken:locale:) -> User
                      loginWithApple(identityToken:authorizationCode:nonce:givenName:familyName:locale:) -> User (route serveur du lot A, PR #5)
                      register(name:email:password:phone:) -> User · resendVerificationCode() -> Int · confirmEmail(code:) · resetPassword(token:password:)
                      forgotPassword(email:locale:) · logout()
UserRepository        syncLocale(_ locale: String) · me() -> User · updateProfile(name:email:phone:bio:) -> User · changePassword(current:new:confirm:)
                      stats() -> UserStats · myListings(status: ListingStatus?, page: Int = 1, limit: Int = 24) -> ListingPage
AccountDataRepository export() -> URL (fichier temporaire) · clearLocalFiles() · deleteAccount(password:) · deleteGoogleAccount(idToken:) · deleteAppleAccount(identityToken:nonce:authorizationCode:)
FavoritesRepository   ObservableObject : @Published ids: Set<String> ; isFavorite(_ id: String) -> Bool · list() -> [Listing] · refresh(_ id: String) -> Bool
                      toggle(_ id: String) -> Bool (optimiste, rollback) ; suit la session (vide à la déconnexion)
SavedSearchesRepository list() -> [SavedSearch] · create(params: [String: String]) -> SaveSearchOutcome · delete(id:)
ConversationsRepository ObservableObject : @Published unreadCount: Int ; touched: AnyPublisher<Void, Never> (ou AsyncStream)
                      refreshUnread(userId:) -> Int · list(cursor:archived:limit:) -> ConversationPage · thread(id:cursor:limit:) -> ChatThread
                      send(conversationId:content:) -> ChatMessage · deleteMessage(conversationId:messageId:) · setArchived(conversationId:archived:)
                      offerAction(conversationId:action:amount:) -> ChatMessage · startConversation(annonceId:message:) -> ConversationEntry
                      makeOffer(annonceId:amount:) -> ConversationEntry · setBlocked(userId:blocked:) · revealPhone(annonceId:) -> String
NotificationsRepository ObservableObject : @Published unreadCount: Int ; incoming (publisher) ; page(page:limit:) -> NotificationPage
                      markAllRead() -> Int · markRead(id:) · delete(id:wasUnread:) · onRealtime(_:) · reset()
UploadRepository      upload(imageData: Data) -> UploadedImage   (ImagePreparer puis multipart)
```

## Noms des propriétés d'AppContainer (FIXÉS, vague 2 et écrans)
`config`, `apiSession`, `apiClient`, `authClient`, `api: any WeydaAPI`, `sessionManager: SessionManager` (nom déjà en place), `connectivity: ConnectivityMonitor`,
`images: ImagePipeline`, `realtime: RealtimeClient`, et les repositories : `annonces`, `categories`, `attributes`, `geo`, `search`,
`sellers`, `reviews`, `reports`, `auth`, `users`, `accountData`, `favorites`, `savedSearches`, `conversations`, `notifications`, `uploads`.

## Pièges constatés en CI (à ne pas reproduire)
- (vague 2) Une classe `@MainActor` qui se conforme à un `nonisolated protocol` (ex. `FakeWeydaAPI: WeydaAPI`) : ses méthodes
  témoins HÉRITENT de l'isolation du protocole (nonisolated). Dedans, tout membre MainActor s'appelle avec `await`
  (`await record("x")`), sinon « main actor-isolated … cannot be called from outside of the actor ».
