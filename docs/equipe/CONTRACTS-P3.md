# Phase 3 (Compte et connexion) — contrats d'interface (complète CONTRACTS.md, CONTRACTS-P2.md et SCREEN-BRIEF.md)

Dépôt de travail de la phase 3 : `../weydaa-ios-p3` (worktree, branche `phase-3`,
partie du socle de la phase 2 : navigation, composants, repositories). Les écrans Accueil / Annonces / Détail de la phase 2
sont écrits EN MÊME TEMPS dans un autre worktree : n'y touche pas, ne compte pas dessus.
Référence Android : `ui/auth/*`, `ui/profile/*`, `ui/settings/{AccountData*,Contact,Language}*.kt`, `ui/components/{VerifyEmailBanner,LoginRequired}.kt`,
tests `AuthViewModelsTest.kt`, `ProfileViewModelsTest.kt`, `AuthRepositoryTest.kt`.

## Répartition
- **AUTH** : `Weyda/Features/Auth/*` (connexion, inscription, mot de passe oublié, nouveau mot de passe, code e-mail, feuille
  `AuthFlowView`, composants de formulaire), `Weyda/Core/Auth/*` (Apple, Google, nonce, PKCE), `Weyda/DesignSystem/Components/VerifyEmailBanner.swift`,
  et dans le code existant : `Weyda/App/Navigation/AppRouter.swift` + `Weyda/App/RootView.swift` (présentation de la feuille de connexion,
  racine de l'onglet Profil = `ProfileView()`), `Weyda/App/LaunchOptions.swift`, `Weyda/App/AppContainer.swift` (session simulée),
  `Weyda/Core/Config/AppConfig.swift` + `Config/Shared.xcconfig` + `Weyda/Resources/Info.plist` (identifiant client Google iOS),
  `Weyda/Core/Common/ErrorMapper.swift` (codes Apple). Données simulées `routes-auth.json` + `MockFixtures/auth/`.
  Tests `AuthViewModelsTests.swift`, `AppleSignInTests.swift`, `GoogleSignInTests.swift`. Tour `TourAuthTests.swift`.
- **ACCOUNT** : `Weyda/Features/Account/*` (`ProfileView` visiteur/connecté, modifier le profil, mot de passe, mes annonces,
  mes données, nous contacter, langue), `Weyda/App/Navigation/RouteDestinations.swift` (destinations `.myListings`,
  `.editProfile`, `.changePassword`, `.accountData`, `.contact` à la place de `ComingSoonView`). Données simulées
  `routes-account.json` + `MockFixtures/account/`. Tests `ProfileViewModelsTests.swift`, `AccountDataViewModelTests.swift`,
  `ContactViewModelTests.swift`. Tour `TourAccountTests.swift`.
  `GuestProfileView` (SHELL) reste utilisable par `ProfileView` pour l'état visiteur, ou est remplacé : ACCOUNT décide.

## Interfaces FIXÉES entre AUTH et ACCOUNT
```swift
// AUTH — Weyda/Core/Auth/AppleSignIn.swift
nonisolated struct AppleCredential: Sendable, Hashable { let identityToken: String; let authorizationCode: String?; let rawNonce: String;
                                                          let givenName: String?; let familyName: String?; let email: String? }
final class AppleSignInCoordinator { func signIn() async throws -> AppleCredential }        // MainActor ; annulation → CancellationError
// AUTH — Weyda/Core/Auth/GoogleSignIn.swift (ASWebAuthenticationSession + PKCE, SANS SDK ; inactif si l'identifiant client est vide)
final class GoogleSignInCoordinator { var isConfigured: Bool { get }; func signIn() async throws -> String /* id_token */ }
// AUTH — Weyda/App/Navigation/AppRouter.swift
nonisolated enum AuthEntry: Hashable, Identifiable, Sendable { case login, register, forgotPassword, verifyEmail, resetPassword(token: String) }
@Published var authFlow: AuthEntry?            // feuille de connexion présentée par RootView
func requestLogin()                            // phase 3 : authFlow = .login (la signature ne change pas)
func requestEmailVerification()                // authFlow = .verifyEmail
// ACCOUNT — Weyda/Features/Account/ProfileView.swift : `struct ProfileView: View { init() }` (racine de l'onglet Profil)
```
Connexion réussie → la feuille se ferme d'elle-même ; e-mail non vérifié après inscription → étape « code e-mail » dans la même feuille.
Lien profond `/{locale}/auth/reinitialiser-mdp?token=…` → `router.open(.resetPassword(token))` → `authFlow = .resetPassword(token:)`.

## Session simulée (captures) — AUTH l'implémente, ACCOUNT s'en sert
`-WeydaLoggedIn YES` (e-mail vérifié) ou `-WeydaLoggedIn unverified` : en API simulée seulement, la session en mémoire est pré-remplie
(jetons factices valides 1 an) avec l'utilisateur FICTIF de référence, que les fixtures de `GET /api/users/me` (ACCOUNT) reprennent à l'identique :
`id "mock-me"`, `name "Yacine Benali"`, `email "yacine.benali@example.com"`, `phone "0555000000"`, `phoneCountryCode "+213"`,
`bio "Particulier à Alger, je vends ce dont je ne me sers plus."`, `role "USER"`, `isRecommended false`,
`memberSince "2025-03-14T10:00:00.000Z"`, `hasPassword true`, `providers ["credentials"]`.
Ses annonces (`GET /api/users/me/annonces`, ACCOUNT) : 6 annonces `mock-m1…m6` de statuts variés (ACTIVE, PENDING, SOLD, EXPIRED, REJECTED
avec `aiModeration`), photos `https://photos.mock.weydaa/annonces/<objet>-<n>.webp`.

## Spécificités iOS
- Apple : `SignInWithAppleButton` (AuthenticationServices, libellé et style fournis par le système, noir/blanc selon l'apparence),
  nonce aléatoire (SecRandomCopyBytes) dont le SHA-256 (CryptoKit) part dans la requête ; `AuthRepository.loginWithApple(identityToken:
  authorizationCode:nonce:givenName:familyName:locale:)`. L'entitlement « Sign in with Apple » viendra avec le compte Apple : ne PAS toucher
  `project.yml` ; sans lui, le bouton échoue proprement (message `ErrorMapper`) — en API simulée, le bouton simule une connexion réussie.
- Google : `ASWebAuthenticationSession` (présentation via `ASWebAuthenticationPresentationContextProviding` sur la fenêtre clé),
  OAuth 2.0 + PKCE vers `accounts.google.com`, échange du code à `oauth2.googleapis.com/token` (client iOS : pas de secret), `id_token` →
  `AuthRepository.loginWithGoogle`. Identifiant client : `AppConfig.googleIOSClientID` ← clé Info.plist `WeydaGoogleIOSClientID` ←
  `WEYDA_GOOGLE_IOS_CLIENT_ID` (xcconfig, VIDE aujourd'hui → bouton Google masqué). Schéma de retour = identifiant client inversé.
- Langue : pas de sélecteur maison ; la ligne « Langue » ouvre les Réglages de l'app (`UIApplication.openSettingsURLString`) avec une phrase
  d'explication (les 3 chaînes Android qui parlent d'Android seront remplacées par l'orchestrateur : demande les textes iOS dans ta note).
- Mes annonces (phase 3) : liste par statut + badges + note de modération + ouverture de la fiche ; les ACTIONS (modifier, vendu, renouveler,
  supprimer) sont la phase 4 : n'en mets pas les boutons.
- Mes données : export (fichier JSON partagé par `ShareLink`/feuille de partage), suppression du compte : mot de passe, OU Google (id_token frais),
  OU Apple (`AppleSignInCoordinator.signIn()` puis `accountData.deleteAppleAccount(identityToken:nonce:authorizationCode:)`) selon
  `providers`/`hasPassword` ; confirmation explicite ; succès → session fermée.

## Routes simulées
AUTH : `POST /api/auth/token` (succès), `/api/auth/register`, `/api/auth/forgot-password`, `/api/auth/reset-password`,
`/api/email-verify` (+ `/confirm`), `/api/auth/apple`, `/api/auth/google` — réponses = utilisateur de référence.
ACCOUNT : `GET/PUT /api/users/me`, `/api/users/me/stats`, `/api/users/me/annonces` (+ `status=…`), `PUT /api/users/me/password`,
`/api/users/me/export`, `DELETE /api/users/me/account`, `POST /api/contact`.
---------------------------------------------------------------------------------------------------------------
## REPRISE DE LA PHASE 3 (2026-10-03, nuit) — prime sur ce qui précède en cas de contradiction
- Dépôt de travail : `../weydaa-ios-p3` (branche `phase-3`). La phase 2 y est
  désormais FUSIONNÉE : Accueil, Annonces, Fiche (`DetailView`, route `.detail(idOrSlug:)`), Vendeur, À propos existent ; tu
  peux t'en servir (ouvrir une fiche depuis « Mes annonces » = `router.push(.detail(idOrSlug: id))` ou `NavigationLink(value:)`).
- Le travail partiel de la session précédente est commité (commit « wip: phase 3 ») : RELIS-LE d'abord, d'un œil de
  compilateur Swift 6.2 strict ET de relecteur (parité Android, règles du brief), corrige-le, puis termine.
- Notes : `<scratchpad>/ios-team/notes/auth.md` et `notes/account.md` (chacun la sienne ; lis celle de l'autre).
- **Chaînes (NOUVEAU mécanisme)** : chaque agent tient SON fichier `<scratchpad>/ios-team/strings/<agent>.json`, même format
  que `scripts/ios-strings.json` : `{ "add": { "cle_snake": { "fr": "…", "ar": "…", "en": "…" } }, "override": { "cle_android_existante": { "fr", "ar", "en" } } }`.
  Tu PEUX utiliser tout de suite dans le code l'accès généré : `L10n.cleSnake` (sans argument) ou `L10n.cleSnake(p1)` avec
  `%1$s` → `String`, `%1$d` → `Int` (arguments en ordre). L'orchestrateur fusionne et régénère `L10n.swift` avant la CI.
  Vérifie qu'une clé n'existe pas déjà dans `Weyda/Core/Localization/L10n.swift` (sinon réutilise-la) ; préfixe `auth_` /
  `account_` pour éviter les collisions entre agents. Arabe soigné (registre neutre, comme les chaînes existantes).
- Chaînes Android qui parlent d'Android (`error_google_no_account`, `language_hint`, `language_legacy_hint`) : ACCOUNT propose
  les `override` iOS des deux `language_*` ; AUTH celui d'`error_google_no_account`.
- Codes d'erreur Apple du lot A (`invalidAppleToken`, `appleEmailMissing`, `appleReauthMismatch`, `appleSignInUnavailable`) :
  AUTH ajoute 4 vraies clés (`error_invalid_apple_token`, `error_apple_email_missing`, `error_apple_reauth_mismatch`,
  `error_apple_unavailable`), branche `ErrorMapper` (+ `appleMessage`) et ajoute les cas à `WeydaTests/ErrorMapperTests.swift`.
- Captures : numéros 5x = connexion (AUTH), 6x = compte (ACCOUNT). Écrans de membre : `captureLaunch(["-WeydaRoute", "<route>",
  "-WeydaLoggedIn", "YES"], name: "6x-…", screen: "…")` ; l'onglet Profil connecté : route `tab:account` + `-WeydaLoggedIn YES`.
- Données simulées : chaque agent crée `Weyda/Mock/MockFixtures/routes-<auth|account>.json` + dossier `MockFixtures/<auth|account>/`
  (lis `Weyda/Mock/MockURLProtocol.swift` et `routes-catalog.json` pour le format : méthode, chemin à jokers, contraintes de
  requête, statut, fichier). Vérifie comment les fichiers `routes-*.json` sont chargés (tous ? liste explicite ?) et, s'il
  faut toucher le chargeur, demande-le dans ta note au lieu de l'éditer.
- Tests unitaires : `FakeWeydaAPI` (à LIRE, ne pas modifier) couvre déjà toutes les routes de connexion et de compte.
- Rendu final (≤ 40 lignes) : fichiers créés/modifiés, chaînes ajoutées (nombre), captures prévues, points douteux de compilation.
