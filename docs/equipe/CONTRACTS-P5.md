# Phase 5 (Messagerie et notifications) — contrats d'interface (complète CONTRACTS.md, CONTRACTS-P2/P3/P4.md, SCREEN-BRIEF.md)

Dépôt de travail : `../weydaa-ios-p5` (worktree, branche `phase-5`, partie de `main` après la phase 4). AUCUNE commande git.
Pas de Mac : chaque erreur de compilation = 10 min de CI. Notes de l'équipe : `<scratchpad>/ios-team/notes/` (lire `shell.md`,
`data.md`, `utils.md`, `network.md` pour l'API réelle des composants, repositories, formats).
Référence Android (LECTURE SEULE) : `../weydaa-site/android/app/src/main/java/com/weydaa/app/`
`ui/messages/{ChatScreen,ChatViewModel,ConversationsScreen,ConversationsViewModel,MessagingDialogs}.kt`,
`ui/notifications/{NotificationsScreen,NotificationsViewModel}.kt`, `ui/detail/{DetailScreen,DetailViewModel}.kt` (contact + offre),
`data/push/PushNotifications.kt`, `ui/navigation/NotificationPermission.kt`, `MainActivity.kt`, `WeydaApp.kt` ; tests
`app/src/test/java/com/weydaa/app/{ChatViewModelTest,ConversationsTest,NotificationsTest,DetailViewModelTest}.kt`.
Contrat d'API : `../weydaa-site/android/docs/API-CONTRACT.md` ; lot serveur B (PR weyda2026 #6, branche `ios/lot-b-push-moderation`,
lisible par `git -C ../weydaa-server-ios show origin/ios/lot-b-push-moderation:<chemin>`) : `GET /api/users/me/blocked`, `platform` du jeton,
notifications MESSAGE lues à l'ouverture du fil, bloc APNs.

## Ce qui EXISTE déjà (à utiliser, pas à réécrire)
- Données : `ConversationsRepository` (`unreadCount`, `visibleConversationId`, `touched`, `refreshUnread(userId:)`, `list(cursor:archived:limit:)`,
  `thread(id:cursor:limit:)`, `send`, `deleteMessage`, `setArchived`, `offerAction`, `startConversation`, `makeOffer` (409 `offerAlreadyOpen` → conversation
  existante), `setBlocked`, `revealPhone`, **`blockedUsers(page:limit:) -> BlockedUsersPage`** (ajouté pour la phase 5)) ; `NotificationsRepository`
  (`unreadCount`, `topic`, `incoming`, `page`, `markAllRead`, `markRead`, `delete(id:wasUnread:)`, `onRealtime`, `reset`) ; `ReportsRepository.reportUser(userId:conversationId:reason:details:)`.
- Modèles : `Conversation` (`partner(_:)`, `isSeller`, `isUnreadFor`, `matches(query:userId:)`), `ConversationPage`, `ChatThread` (`isBlockedByMe`), `ChatMessage`
  (`isMine`, `isDeletableBy(_:now:)`, `offer`), `OfferMeta`, `OfferKind`, `OfferAction`, `ConversationAnnonce.acceptsOffers`, `LastMessage`, `AppNotification`
  (`target: NotificationTarget?`), `NotificationKind`, `NotificationPage`, **`BlockedUser` / `BlockedUsersPage`** (nouveaux), `OfferRules` (Core/Models/OfferRules.swift).
- Temps réel : `container.realtime` — `conversationUpdates(topic:conversationId:presenceKey:) -> AsyncStream<ConversationRealtimeUpdate>` (`.event(RealtimeEvent)` :
  `messageNew`, `messageDeleted`, `messagesRead`, `typing` ; `.presence(Set<String>)`), `sendTyping(topic:userId:isTyping:)`, `state` (@Published : passage à
  `.connected` après une coupure = relire la dernière page), `isEnabled` (faux en API simulée et sans secrets). Le canal personnel est DÉJÀ écouté par
  `AppContainer` (cloche + pastille Messages + `conversations.touched`).
- Navigation (FAITE par l'orchestrateur, ne pas y toucher) : `RouteDestinations` ouvre `ChatView(conversationId: String, archived: Bool)`, `NotificationsView()`,
  `BlockedUsersView()` ; l'onglet Messages ouvre `ConversationsView()` ; pastille de l'onglet = `conversations.unreadCount` ; cloche de l'accueil
  (`HomeNotificationsButton`) → `.notifications` ; menu du Profil : « Notifications » et « Utilisateurs bloqués » (`L10n.blockedUsersTitle`).
  `AppRoute.chat(conversationId:archived:)`, `.notifications`, `.blockedUsers` ; `-WeydaRoute chat:<id>` (onglet Messages), `notifications`, `blockedUsers`.
  `router.open(DeepLinkTarget)` sait ouvrir un fil, une fiche, un profil, Mes annonces. `DeepLinks.resolve(URL) -> DeepLinkTarget?`, `DeepLinks.siteURL`.
- Composants : `LoginRequired(title:message:onLogin:)`, `AccountMemberGate(title:content:)`, `VerifyEmailBanner`, `ReportSheet` (Detail/DetailShared.swift),
  `floatingNotice`, `RemoteImage`, états (`StateViews.swift`), squelettes, `OfflineBanner`, `RelativeTime`/formats (`Format.swift` : prix « 3 050 000 DA »,
  dates relatives, chiffres latins). Toutes les chaînes `chat_*`, `offer_*`, `notification_*`, `notifications_*`, `push_*` d'Android sont dans `L10n`.
- `FakeWeydaAPI` (tests) : `onGetConversations`, `onGetConversation`, `onSendMessage`, `onDeleteMessage`, `onArchiveConversation`, `onUnarchiveConversation`,
  `onPostOfferAction`, `onInitiateOffer`, `onCreateConversation`, `onBlockUser`, `onUnblockUser`, **`onGetBlockedUsers`**, `onGetNotifications`,
  `onMarkAllNotificationsRead`, `onMarkNotificationRead`, `onDeleteNotification`, `onRegisterFcmToken`, `onReport` (LIRE le fichier, ne pas le modifier ;
  manque → demande dans la note).

## Répartition (3 agents en parallèle)
- **CHAT** (fil de discussion + contact/offre depuis la fiche) :
  `Weyda/Features/Messages/{ChatState,ChatViewModel,ChatView,ChatScreen,ChatComponents}.swift` (+ autres `Chat*.swift` si besoin),
  `Weyda/Features/Messages/MessagingSheets.swift` (API fixée ci-dessous), `Weyda/Features/Detail/{DetailViewModel,DetailView}.swift` (+ `DetailScreen.swift`
  si la barre d'actions doit changer : seulement ce qui touche au contact et à l'offre), `Weyda/App/LaunchOptions.swift` (`chatDemo`, voir captures),
  données simulées `Weyda/Mock/MockFixtures/routes-chat.json` + `MockFixtures/chat/`, tests `WeydaTests/ChatViewModelTests.swift` (portage COMPLET de
  ChatViewModelTest.kt), `WeydaTests/DetailMessagingTests.swift` (cas contact/offre de DetailViewModelTest.kt), tour `WeydaUITests/TourChatTests.swift` (captures 9c).
- **INBOX** (conversations, notifications, bloqués) :
  `Weyda/Features/Messages/{ConversationsViewModel,ConversationsView,ConversationsScreen,ConversationRow}.swift` (+ `Conversations*.swift`),
  `Weyda/Features/Notifications/{NotificationsViewModel,NotificationsView,NotificationsScreen}.swift`, `Weyda/Features/Account/{BlockedUsersViewModel,BlockedUsersView}.swift`,
  `Weyda/Mock/MockURLProtocol.swift` (SEULEMENT si besoin de la variante par langue, voir données simulées), données `routes-inbox.json` + `MockFixtures/inbox/`,
  tests `WeydaTests/{ConversationsViewModelTests,NotificationsViewModelTests,BlockedUsersViewModelTests}.swift` (portage des cas ViewModel de ConversationsTest.kt
  et NotificationsTest.kt ; les cas repository sont déjà dans `MessagingRepositoriesTests.swift`), tour `WeydaUITests/TourInboxTests.swift` (captures 9i).
- **PUSH** (Firebase, notifications système, liens universels) :
  `project.yml` (paquet Firebase + entitlements en Release), `Config/Weyda.entitlements` (nouveau), `Weyda/Resources/Info.plist`, `Weyda/App/WeydaApp.swift`,
  `Weyda/App/AppDelegate.swift` (nouveau), `Weyda/Core/Push/*.swift` (nouveau dossier), `Weyda/App/AppContainer.swift` (propriété `push` + effets de session),
  CI : `.github/workflows/{ios-ci,ios-screens}.yml` + `scripts/ci/*.sh` (cache des paquets SPM), tests `WeydaTests/{PushPayloadTests,PushRegistrarTests,UniversalLinksTests}.swift`.

## API FIXÉE entre agents
```swift
// CHAT — Weyda/Features/Messages/ChatView.swift (écran poussé ; se garde lui-même : visiteur → LoginRequired → router.requestLogin())
struct ChatView: View { init(conversationId: String, archived: Bool) }

// CHAT — Weyda/Features/Messages/MessagingSheets.swift (portage de MessagingDialogs.kt ; utilisées par la fiche ET le fil)
/// Montant d'une offre (nouvelle offre ou contre-offre) : champ numérique (chiffres latins, `Validators.asciiDigits`), prix demandé et offre en
/// cours rappelés, validation 1…`OfferRules`/Android MAX, bouton occupé pendant l'envoi, erreur traduite sous le champ.
struct OfferAmountSheet: View {
    init(title: String, askingPrice: Double?, currentOffer: Double?, amount: Binding<String>, isBusy: Bool, errorMessage: String?,
         onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void)
}
/// Premier message au vendeur : modèles de message d'Android (puces qui remplissent le champ), champ multiligne 2000 car., envoi.
struct ContactSellerSheet: View {
    init(listingTitle: String, message: Binding<String>, isBusy: Bool, errorMessage: String?,
         onSend: @escaping () -> Void, onCancel: @escaping () -> Void)
}

// INBOX — racines
struct ConversationsView: View { init() }      // racine de l'onglet Messages (visiteur → LoginRequired ; membre → liste + archives)
struct NotificationsView: View { init() }      // écran poussé (membre)
struct BlockedUsersView: View { init() }       // écran poussé (membre)

// PUSH — Weyda/Core/Push/PushRegistrar.swift (MainActor), exposé par `AppContainer.push`
final class PushRegistrar: ObservableObject {
    /// Firebase configuré : `GoogleService-Info.plist` présent dans l'app, ni API simulée ni tests unitaires. Faux en CI → tout est sans effet.
    var isAvailable: Bool { get }
    /// Demande l'autorisation de notifier AU BON MOMENT (première ouverture de Messages par un membre), une seule fois (refus respecté),
    /// puis `registerForRemoteNotifications`. Sans Firebase : rien (aucune alerte système dans les tours de captures).
    func requestAuthorizationIfNeeded()
    func registerCurrentToken()   // session ouverte (AppContainer)
    func unregister()             // déconnexion volontaire (AppContainer) : jeton FCM détruit, comme Android
}
```
INBOX appelle `container.push.requestAuthorizationIfNeeded()` dans `ConversationsView` quand un MEMBRE l'affiche (`.task`). CHAT pose
`container.conversations.visibleConversationId = conversationId` à l'apparition du fil et le remet à nil à sa disparition (seulement s'il vaut encore cet id) :
PUSH s'en sert pour ne pas afficher la bannière d'un fil déjà à l'écran.

## Règles d'écran
**CHAT** (portage de ChatScreen/ChatViewModel) : en-tête (interlocuteur, « En ligne » / « écrit… », vignette de l'annonce → fiche, menu : voir l'annonce,
voir le profil → `.seller`, archiver/désarchiver, bloquer/débloquer avec confirmation, signaler → `ReportSheet` puis `reportUser`) ; bulles (les miennes à
`trailing`, couleurs `WeydaColor`, heure, « vu » si `readAt`, supprimé → texte `chat_message_deleted`/équivalent en italique) ; séparateurs de jour si Android
en a ; cartes d'offre (montant, état, boutons accepter / refuser / contre-offre selon `OfferRules` — seulement pour l'offre OUVERTE de l'AUTRE partie ;
« Faire une offre » si `acceptsOffers` et pas d'offre ouverte) ; menu contextuel (appui long) « Supprimer » si `isDeletableBy` → confirmation ; anciens
messages chargés en remontant (`hasMore`/`nextCursor`), position conservée ; défilement en bas à l'ouverture et à chaque message (le mien) ; composeur
(multiligne, 2000 car., bouton désactivé si vide/envoi en cours, `safeAreaInset(edge: .bottom)`), bloqué (`isBlockedByMe`) → composeur remplacé par un
encart + « Débloquer » ; 403 `userBlocked`/`userDeleted`/`emailNotVerified` → message traduit (`ErrorMapper`), e-mail non vérifié → `VerifyEmailBanner`.
Temps réel : `conversationUpdates(topic: conversation.topic, conversationId:, presenceKey: userId)` tant que l'écran est visible ; « écrit… » envoyé au plus
toutes les 2 s, arrêt après 3 s sans frappe (règles Android) ; `state` repassé à `.connected` → relire la dernière page. Après le chargement :
`conversations.refreshUnread(userId:)` et `notifications.page(page: 1)` (le serveur du lot B marque lues les notifications MESSAGE du fil).
Archives (`archived: true`) : même écran, menu « Désarchiver ». Racine : `screen.chat` ; identifiants : `chat.composer`, `chat.send`, `chat.menu`,
`chat.offer.make`, `chat.offer.accept`, `chat.offer.decline`, `chat.offer.counter`.
Fiche (DetailViewModel/DetailView) : « Contacter » → `ContactSellerSheet` → `startConversation` → `router.push(.chat(conversationId:, archived: false))` ;
« Faire une offre » → `OfferAmountSheet` → `makeOffer` (409 avec id → ouvrir la conversation existante, sans erreur) → fil. Visiteur → `router.requestLogin()`
(déjà en place). Supprimer `openWebFallback` du contact/offre (le reste de la fiche ne change pas). Identifiants : `detail.contact.sheet`, `detail.offer.sheet`.

**INBOX** : Conversations (portage de ConversationsScreen/ViewModel) : sélecteur « Conversations / Archives » (segmenté natif), recherche locale
(`.searchable`, `matches(query:userId:)`), rangées (avatar ou initiale, nom de l'interlocuteur, titre + vignette de l'annonce, aperçu du dernier message —
« message supprimé » si `isDeleted` —, date relative, non lue = pastille + gras), glisser pour archiver / désarchiver, tirer pour rafraîchir, page suivante par
curseur, états vide / erreur / hors ligne ; relecture de la première page sur `conversations.touched` et au retour sur l'écran ; visiteur → `LoginRequired`.
Utilisateurs bloqués (Guideline 1.2 — « masquer leur contenu ») : la liste charge aussi `blockedUsers(page: 1, limit: 100)` (échec, ex. 404 avant le
déploiement du lot B → ignoré) ; une conversation dont l'interlocuteur est bloqué affiche « Utilisateur bloqué » à la place de l'aperçu.
Notifications (portage de NotificationsScreen/ViewModel) : rangées (icône SF Symbol par `NotificationKind`, libellé du type `notification_type_*`, corps,
date relative, non lue = pastille), appui → `markRead` puis ouverture de `target` (`.listing` → `.detail`, `.conversation` → `.chat`, `.seller` → `.seller`,
`.myListings` → `.myListings`), glisser pour supprimer, « Tout marquer comme lu » (barre), pagination, `incoming` → insertion en tête, tirer pour rafraîchir.
Bloqués : rangées (avatar/initiale, nom ou « Compte supprimé », « bloqué le … »), « Débloquer » + confirmation → `setBlocked(userId:blocked:false)` →
rangée retirée + message ; vide (texte qui explique comment bloquer) ; erreur + réessayer ; pagination.
Racines : `screen.conversations`, `screen.notifications`, `screen.blockedUsers` ; identifiants : `conversations.archives`, `conversation.row.<id>`,
`notifications.markAll`, `notification.row.<id>`, `blocked.unblock.<id>`.

**PUSH** :
- Firebase 12.19.2 (dépendance ACCORDÉE, version EXACTE) par Swift Package Manager dans `project.yml` (`packages:` + produits `FirebaseMessaging`,
  `FirebaseCrashlytics` — vérifier les noms de produits dans `Package.swift` de la version : `gh api repos/firebase/firebase-ios-sdk/contents/Package.swift?ref=12.19.2`).
- `FirebaseApp.configure()` SEULEMENT si `GoogleService-Info.plist` est dans le paquet de l'app (écrit par `ios-release` depuis le coffre GitHub, jamais commité),
  hors API simulée et hors tests unitaires ; sinon tout le push est inerte (CI, captures). Crashlytics : même règle (vérifier la politique d'Android : `WeydaApp.kt`).
- `FirebaseAppDelegateProxyEnabled = NO` (Info.plist) : jeton APNs passé à la main (`Messaging.messaging().apnsToken`) ; jeton FCM obtenu par l'API async
  (`Messaging.messaging().token()`) et suivi par la notification `MessagingRegistrationTokenRefreshed` (pas de `MessagingDelegate` à conformer).
  `POST /api/push/fcm` avec `FcmTokenRequestDTO(token:locale: WeydaLocale.language)` (`platform` vaut déjà "ios").
- `UNUserNotificationCenterDelegate` : méthodes `nonisolated`, données utiles extraites TOUT DE SUITE en valeur `Sendable` (`PushPayload` : `url`, `type`,
  `conversationId`, `notificationId`), gestionnaire de complétion appelé dans la méthode même ; premier plan : bannière + son SAUF si
  `conversationId == visibleConversationId` (copie du fil visible gardée dans une boîte verrouillée `OSAllocatedUnfairLock` lisible hors du fil principal) ;
  appui → `Task { @MainActor in … }` → lien du site (`DeepLinks.siteURL` + `url`, préfixe de langue toléré) → `router.open` ; appui reçu avant que l'interface
  soit prête → mis de côté puis rejoué.
- Pastille de l'icône = `notifications.unreadCount` (iOS 17 : `UNUserNotificationCenter.setBadgeCount`, iOS 16 : `applicationIconBadgeNumber`), remise à 0
  à la déconnexion.
- Liens universels : `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` en plus de `.onOpenURL` ; entitlements (Release seulement :
  `CODE_SIGN_ENTITLEMENTS` dans `configs: Release:`) : `com.apple.developer.associated-domains` = `applinks:weydaa.com`, `applinks:www.weydaa.com` ;
  `aps-environment` = `production` ; `com.apple.developer.applesignin` = `[Default]`. Les builds Debug de la CI (simulateur, signature ad hoc) n'ont PAS
  d'entitlements. Comparer les chemins de l'AASA du lot A (`git -C ../weydaa-server-ios show origin/ios/lot-a-connexion:src/lib/apple-app-site-association.ts`)
  avec `DeepLinks` et tester chaque chemin (`UniversalLinksTests`).
- `Info.plist` : `UIBackgroundModes` = `remote-notification`. AUCUN secret dans le dépôt.
- CI : cache des paquets (`-clonedSourcePackagesDirPath` + `actions/cache` sur le hachage de `project.yml`) dans `ios-ci` et `ios-screens` ; Firebase en
  Swift 6 : rien de Firebase dans un type `nonisolated` sans précaution (types ObjC non `Sendable`).
- Pièges Swift 6 : `UIApplicationDelegate` est MainActor (OK) ; `@UIApplicationDelegateAdaptor` dans `WeydaApp` ; l'AppDelegate est créé AVANT les
  `@StateObject` de `WeydaApp` → il garde l'appui en attente jusqu'à `attach(container:router:)` (appelé par `WeydaApp` au premier affichage).

## Données simulées (FICTIVES, cohérentes entre CHAT et INBOX)
Moi = `mock-me` (Yacine Benali). Interlocuteurs existants : `mock-u1` Karim B., `mock-u2` Amina K., `mock-u3` Yacine M., `mock-u5` Sofiane T., `mock-u6` Lyes A.
Contenu d'un message OFFER = `"<emoji> <montant formaté>"` (serveur : 💰 NEW, ↩️ COUNTER, ✅ ACCEPTED, ❌ DECLINED, ex. `"↩️ 3 050 000 DA"`), `type: "OFFER"`,
`metadata: { kind, amount }`. Dates : 2026-09-28 → 2026-10-04 (fuseau Z).
| id | annonce | moi | interlocuteur | état | dernier message (aperçu de la liste = dernier du fil) |
|---|---|---|---|---|---|
| mock-c1 | mock-a2 Renault Clio 4 GT Line 2019 (NEGOTIABLE 3 150 000, `car-1.webp`) | acheteur | mock-u2 Amina K. | NON LU ; offre NEW 2 900 000 (moi) puis COUNTER 3 050 000 (elle) OUVERTE ; un de mes messages supprimé | Amina, 2026-10-04T09:12:00Z : « Je peux descendre à 3 050 000 DA, pas moins. Elle a fait sa vidange le mois dernier. » |
| mock-c2 | mock-m1 Lenovo ThinkPad T14 (NEGOTIABLE 85 000, `laptop-61.webp`) | vendeur | mock-u5 Sofiane T. | lu | moi, 2026-10-03T18:40:00Z : « Oui, toujours disponible. Vous pouvez passer ce soir après 18 h. » |
| mock-c3 | mock-a1 iPhone 15 Pro Max (NEGOTIABLE 215 000, `phone-1.webp`) | acheteur | mock-u1 Karim B. | lu ; offres NEW 200 000 → COUNTER 210 000 → COUNTER 205 000 (moi) → ACCEPTED 205 000 (lui) | Karim, 2026-10-02T20:05:00Z : « Parfait, on se retrouve demain à Didouche Mourad. » |
| mock-c4 | mock-a24 À donner : canapé 3 places (FREE, `sofa-2.webp`) | acheteur | mock-u3 Yacine M. | lu par lui (`readAt`) ; pas d'offre (gratuit) | moi, 2026-10-01T11:30:00Z : « Merci beaucoup, je passe le récupérer samedi matin. » |
| mock-c5 | mock-m2 Canapé d'angle 5 places (FIXED 65 000, `sofa-61.webp`) | vendeur | mock-u6 Lyes A. | **bloqué par moi** (`isBlockedByMe: true`) | Lyes, 2026-09-30T22:47:00Z : « Répondez ou je laisse un mauvais avis. » |
| mock-c6 (archives seulement) | mock-a17 MacBook Air M1 (FIXED 135 000, `laptop-1.webp`, statut **SOLD** dans le fil) | acheteur | mock-u1 Karim B. | lu | Karim, 2026-09-28T15:20:00Z : « Désolé, il vient d'être vendu. » |
Liste (INBOX) : `GET /api/conversations` → c1…c5 (dans cet ordre), `nextCursor: null` ; `GET /api/conversations?archived=true` → c6 ; topics `"conv:mock-cN:mock"`.
Fil (CHAT) : `GET /api/conversations/mock-cN` (6 fichiers, 6 à 14 messages chacun, l'annonce avec `status`/`price`/`priceType`, `isBlockedByMe`,
`hasMore: false`) ; `POST /api/conversations/*/messages` → message renvoyé (générique) ; `DELETE /api/conversations/*/messages/*`, `POST /api/conversations/*/offers`
→ message OFFER générique ; `POST /api/conversations` → `{ conversationId: "mock-c1", … }` (contact depuis la fiche) ; `POST /api/annonces/*/offers` → 201
`mock-c1` ; `POST /api/users/*/block` → `{ success: true }` ; `POST /api/reports` s'il n'existe pas déjà (vérifier `routes-detail.json`).
INBOX : `POST|DELETE /api/conversations/*/archive`, `DELETE /api/users/*/block` → `{ success: true }` ; `GET /api/users/me/blocked` → Lyes A. (`mock-u6`,
bloqué le 2026-09-30T22:50:00Z) + un compte supprimé (`mock-u9`, `name: null`, 2026-09-12) ; `GET /api/notifications` → 8 notifications, `unreadCount: 3`,
`topic: ""` : MESSAGE (non lue, url `/dashboard/messages/mock-c1`), OFFER_COUNTER (non lue, même fil), ANNONCE_APPROVED (non lue, `/dashboard/annonces`),
OFFER_ACCEPTED (`/dashboard/messages/mock-c3`), REVIEW (`/profil/mock-me`), FAVORITE_PRICE_DROP (`/annonce/mock-a10`), SEARCH_ALERT (`/annonce/mock-a25`),
ANNONCE_EXPIRED (`/dashboard/annonces`) ; `PATCH /api/notifications`, `PATCH|DELETE /api/notifications/*`. Titres/corps de notification : écrits par le
SERVEUR dans la langue du compte — si le chargeur le permet simplement, une variante par langue (`notifications.ar.json`, `.en.json` choisie selon la langue
de l'app) ; sinon français partout, et le DIRE dans la note.
⚠️ Au lancement avec `-WeydaLoggedIn`, `AppContainer` lit déjà `GET /api/conversations` (pastille Messages = 1) et `GET /api/notifications` (cloche = 3) :
ces deux réponses apparaissent donc aussi dans les tours des phases 2 à 4 (voulu).

## Chaînes
Chaque agent tient `<scratchpad>/ios-team/strings/<chat|inbox|push>.json` (format `scripts/ios-strings.json` : `add` / `override`, fr + ar + en), préfixes
`chat_ui_` (CHAT), `inbox_` (INBOX), `push_` (PUSH). Accès `L10n.cleEnCamelCase` utilisable TOUT DE SUITE (`%1$s` → String, `%1$d` → Int). Vérifier
d'abord que la clé n'existe pas (`Weyda/Core/Localization/L10n.swift`). Arabe soigné, registre neutre ; aucune phrase qui parle d'Android.

## Captures (tour)
Lire `WeydaUITests/TourSupport.swift` et un tour existant (`TourPostTests.swift`, `TourMyListingsTests.swift`) AVANT d'écrire. Session : `-WeydaLoggedIn YES`.
- CHAT (9c) : fil c1 (offre ouverte à moi de répondre), c1 avec la feuille de contre-offre, c3 (offre acceptée), c4 (gratuit), c5 (bloqué), c6 archivé,
  menu du fil, confirmation de blocage, feuille de signalement, `-WeydaChatDemo typing` (CHAT l'ajoute à `LaunchOptions`, Debug + API simulée : l'interlocuteur
  « en ligne » et « écrit… » sans temps réel), fiche → feuille « Contacter » puis fil ouvert, fiche → feuille d'offre ; visiteur sur `chat:mock-c1`.
- INBOX (9i) : Conversations (non lue en tête, bloqué), recherche, Archives, glisser (action visible), visiteur ; Notifications (non lues, après « tout lu »),
  glisser pour supprimer ; Bloqués (liste, confirmation de déblocage, vide si possible), Profil membre (ligne « Utilisateurs bloqués »).
- PUSH : pas de tour (rien de visible sans compte Apple) ; tests unitaires seulement.

## Rendu (≤ 40 lignes) + note `<scratchpad>/ios-team/notes/<chat|inbox|push>.md`
Fichiers créés/modifiés, API publique, écarts avec Android et pourquoi, demandes (chaînes, FakeWeydaAPI, chargeur de routes), points douteux pour la compilation.
