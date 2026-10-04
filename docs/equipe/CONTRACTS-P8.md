# Phase 8 (finition « à la Apple », lots 1 et 2) — contrats d'interface (complète CONTRACTS.md, CONTRACTS-P2…P7.md, SCREEN-BRIEF.md)

> ✅ EXÉCUTÉ le 2026-10-05 (PR #11, galerie https://claude.ai/artifact/7LVhnEtgq5WriMZzTUZ5wm) — archive, ne pas exécuter. Ce qui a été
> fait et les écarts : `docs/PLAN.md` § Phase 8.

**Feu vert du propriétaire : 2026-10-04** (« GO lot un et deux »), à exécuter à la session suivante. Préparé le 2026-10-04 à partir
de trois repérages du code (lignes citées = état de `main` à 7816f38 ; les revérifier, elles bougent). Dépôt de travail :
`../weydaa-ios-p8` (worktree, branche `phase-8`, partie de `main`). Les agents : AUCUNE commande git. Pas de Mac : chaque erreur de
compilation = 10 min de CI. Notes de l'équipe : `<scratchpad>/ios-team/notes/p8-<agent>.md`.

## Ce qui ne se fait PAS (décidé à la préparation)
- **Marquer une conversation lue / non lue** (menu, glissement à gauche) : aucune route serveur (`GET /api/conversations/[id]` marque lu
  en effet de bord, rien pour « non lu »). Hors phase ; ligne dans `EN-ATTENTE.md` si le propriétaire le veut un jour.
- **Glissements dans « Mes annonces »** : passer la liste en `List` casserait la mise en page des cartes, les boutons et le tour de
  captures. À la place : **menu d'appui long** sur chaque carte (mêmes actions, mêmes règles). Dit au propriétaire dans le rapport.
- **Photo de l'annonce dans la notification** (extension Notification Service, nouvel App ID) : après le premier TestFlight.
- **« Signaler » depuis une liste** : reste sur la fiche (une feuille par écran serait de trop).
- La pastille de l'icône garde le compteur du serveur (notifications non lues, messages compris, `unreadBadge` du lot B) ; l'onglet
  Messages garde les conversations non lues. Les unifier = changement serveur, pas demandé.

## Prétravail de l'orchestrateur (AVANT les agents, une CI)
Fichiers partagés, écrits et compilés d'abord ; les agents les UTILISENT, ne les réécrivent pas.
1. **Chaînes** : toutes les clés de la section « Chaînes » dans `scripts/ios-strings.json`, puis `convert-strings`, `check-strings`.
2. **`WeydaBanner`** (`Weyda/DesignSystem/Components/Banner.swift`, nouveau) : remplace `floatingNotice` et `ListingsNoticeToast`.
   ```swift
   nonisolated struct WeydaBanner: Hashable, Sendable {
       enum Kind: Hashable, Sendable { case info, success, error }      // pilote l'haptique à l'apparition
       let id: UUID                                                      // même texte deux fois = minuteur relancé
       let message: String
       let symbol: String?                                               // SF Symbol facultatif, en tête
       let kind: Kind
       let action: BannerAction?                                         // « Annuler » ; un identifiant, pas une closure
   }
   nonisolated struct BannerAction: Hashable, Sendable { let id: String; let title: String }   // title = L10n.undo
   extension View {
       func weydaBanner(_ banner: WeydaBanner?, onAction: @escaping (BannerAction) -> Void, onDismiss: @escaping () -> Void) -> some View
   }
   ```
   Placement `safeAreaInset(.bottom)` (comme aujourd'hui : les barres d'actions ajoutées après restent dessous), capsule matériau
   (`.regularMaterial`, verre automatique sur iOS 26), 4 s ou ~7 s avec action, jamais de fermeture automatique d'une bannière à action
   quand VoiceOver tourne ; annonce VoiceOver, `accessibilityAction(named: L10n.undo)` ; glisser vers le bas = fermer ; `ViewThatFits`
   HStack → VStack aux tailles d'accessibilité ; **identifiant `notice` conservé** (TourInbox:162, TourLists:125, TourMyListings:61,83,
   TourReviews:47 le cherchent). `floatingNotice(_:onShown:)` reste, réécrit en enveloppe fine (kind déduit : `.info`) → les écrans
   migrent un par un sans casser.
3. **Haptique** (`Haptics.swift`) : ajouter `error()` et `warning()` (`UINotificationFeedbackGenerator`). Règle de la maison inchangée :
   à l'aboutissement, jamais à l'appui (sauf le favori optimiste) ; pas d'haptique sur un glissement plein (UIKit en donne déjà une).
4. **Navigation** :
   - `AppRoute.detail(idOrSlug: String, zoomSource: String? = nil)` (seul `RouteDestinations.swift:14` lie la valeur ; les 29 usages
     des tests compilent tels quels).
   - `AppRouter` : `@Published private(set) var scrollToTopRequests: [AppTab: Int]` ; dans `select(_:)` : onglet déjà actif ET pile
     vide → compteur + 1 ; pile non vide → `popToRoot` seul (inchangé). Test dans `AppRouterTests` (garder
     `testTappingTheActiveTabPopsItToItsRoot`).
   - Environnement (`@Entry`, rétro-déployé, pas d'`EnvironmentKey` manuel) : `scrollToTopSignal: Int = 0`,
     `listingZoomNamespace: Namespace.ID? = nil`, injectés par `TabStack` (`RootView.swift` ~115-120 ; un `@Namespace` par onglet,
     posé sur le `NavigationStack`).
   - Modificateurs : `.scrollsToTop(on: signal, proxy:, anchor:)` (animation qui respecte « Réduire les animations ») ;
     `.listingZoomSource(id:)` / `.listingZoomDestination(id:)` : `if #available(iOS 18, *)` et espace de noms présent →
     `matchedTransitionSource` (découpe `WeydaRadius.card`) / `navigationTransition(.zoom(sourceID:in:))` ; sinon rien. Rien non plus
     sous « Réduire les animations » ni `LaunchOptions.freezeMotion`. `RouteDestinations` pose la destination quand `zoomSource != nil`.
5. **Menu d'appui long d'une annonce** (`Weyda/DesignSystem/Components/ListingContextMenu.swift`, nouveau) :
   ```swift
   nonisolated struct ListingCardMenu: Sendable { let shareURL: URL?; let canFavorite: Bool; let sellerId: String? }
   extension View {   // posé sur le NavigationLink à l'appel (pas dans la carte : `.weydaCard` et l'accessibilité restent intacts)
       func listingContextMenu(_ listing: Listing, menu: ListingCardMenu, isFavorite: Bool,
                               onFavorite: @escaping () -> Void, onSeller: ((String) -> Void)?) -> some View
   }
   ```
   `contextMenu(menuItems:preview:)` (iOS 16) ; aperçu = `ListingCard` à largeur fixe (`WeydaSize.carouselCard`) ; entrées : Ajouter /
   Retirer des favoris (`favoriteAdd`/`favoriteRemove`), Partager (`ShareLink`, `share`), Voir le vendeur (`menuSeeSeller`, seulement
   avec `sellerId` et pas sa propre annonce).
6. **`Listing.sellerId`** : rempli depuis `AnnonceDTO.userId` (décodé mais jamais recopié : `Mappers.swift` ~104) + test de mapping.
7. **Liens** : `SellerLinks.webURL(sellerId:language:)` → `https://weydaa.com/<lang>/profil/<id>` (page du site existante, `noindex` ;
   déjà routée par `DeepLinks.swift:122`), modelé sur `DetailLinks.webURL` (`DetailViewModel.swift` ~549-553) + test.
8. **Note App Store** : `ReviewPrompter` (`Weyda/Core/Local/ReviewPrompter.swift`, `nonisolated final class … @unchecked Sendable`,
   modèle `SearchHistoryStore`, clés `weyda.review.*`) tenu par `AppContainer` : `record(_ moment: PositiveMoment) -> Bool` (vrai =
   demander maintenant) ; règle : au 2e moment positif au moins, une fois par version (`CFBundleShortVersionString`), jamais sous
   `LaunchOptions.mockAPI` ni en test. Moments : annonce publiée (pas une modification), offre acceptée (vendeur), avis envoyé, annonce
   vendue. Côté vue : `.requestsReview(when: Bool)` (`@Environment(\.requestReview)`, iOS 16, `import StoreKit` = framework système, pas
   une dépendance). Tests unitaires de la règle. Commentaire de `PrivacyInfo.xcprivacy` (UserDefaults CA92.1 déjà déclaré) à compléter.
9. **Raccourcis** : `nonisolated enum ShortcutAction: String { case post, search, messages }` + `func target() -> DeepLinkTarget`
   (`post` → `.post`, `messages` → `.messages`, `search` → `.listings(params: [:])` avec focalisation de la recherche : ajouter
   `focusSearch: Bool = false` à `ListingsLaunch`, `AppRoute.swift` ~75-81) ; argument de lancement `-WeydaShortcut <action>`
   (`LaunchOptions.swift`, modèle de `route`) ; tests de la correspondance.

## Répartition — vague 1 (3 agents en parallèle, après le prétravail)
- **DETAIL** : `Weyda/Features/Detail/*` (DetailScreen, DetailView, DetailViewModel, DetailGallery, DetailSections, DetailShared hors
  `floatingNotice`), `Weyda/Features/Seller/*` ; tour `WeydaUITests/TourP8DetailTests.swift` (captures `11d-…`).
- **BROWSE** : `Weyda/Features/Home/*`, `Weyda/Features/Listings/*` (FiltersSheet compris), `Weyda/Features/Favorites/*`,
  `Weyda/Features/Alerts/*` ; tests existants `TourListsTests.swift` (adaptations) ; tour `TourP8BrowseTests.swift` (`11b-…`).
- **ACCOUNT** : `Weyda/Features/Account/*` (Profile, MyListings, BlockedUsers, AccountComponents…), `Weyda/Features/Post/*`,
  `Weyda/Features/Auth/*` ; tests `TourMyListingsTests.swift` (adaptations) ; tour `TourP8AccountTests.swift` (`11a-…`).

## Répartition — vague 2 (2 agents en parallèle, après la CI verte de la vague 1)
- **INBOX** : `Weyda/Features/Messages/*` (Conversations, ConversationRow, Chat*), `Weyda/Features/Notifications/*` ; tests
  `TourChatTests.swift`, `TourInboxTests.swift` (adaptations) ; tour `TourP8InboxTests.swift` (`11i-…`).
- **SYSTEM** : `Weyda/App/{AppDelegate,WeydaApp,AppContainer}.swift`, `Weyda/App/SceneDelegate.swift` (nouveau), `Weyda/Core/Push/*` ;
  tests unitaires `WeydaTests/{ShortcutTests,NotificationActionsTests}.swift`.

## Règles par point (numéros = liste donnée au propriétaire)
**1. Fiche — barre du haut (DETAIL)**. Garder la barre SYSTÈME (retour par glissement, verre natif d'iOS 26, identifiants intacts) :
au-dessus de la photo `.toolbarBackground(.hidden, for: .navigationBar)`, galerie sous la barre d'état (`ignoresSafeArea(.top)` sur le
ScrollView), voile dégradé sombre en haut de la photo (`DetailGalleryColor.scrim`) ; sous iOS 26 seulement, pastilles blanches derrière
partager / menu (comme `FavoriteButton(onPhoto: true)`) ; photo dépassée → `.toolbarBackground(.visible)` + matériau + titre de
l'annonce en `.principal` (`.titleSmall`, une ligne ; ajouté seulement replié : VoiceOver ne le lit pas deux fois), transition
`weydaAnimation(value: isCollapsed)`. Lecture du défilement : iOS 18 `onScrollGeometryChange` ; iOS 16-17 `GeometryReader` à hauteur
nulle + PreferenceKey **`nonisolated` avec `static let defaultValue`** (un `static var` ne compile pas en Swift 6) ; seuil = hauteur de
la galerie (largeur × 3/4) − marge haute − ~44 pt ; n'écrire l'état que quand le booléen change. Pièges : le badge « À la une »
(`topLeading`) passerait sous le bouton retour → marge haute ; l'indicateur de `.refreshable` sous la barre d'état (vérifier en
capture) ; hors ligne, la bannière s'empile au-dessus (acceptable) ; le squelette doit déborder pareil (pas de saut au chargement).
**2. Fiche — barre d'actions sur une rangée (DETAIL)**, `DetailSections.swift` ~265-399 seulement : `[téléphone 44 pt rond .bordered]
[Faire une offre .bordered] [Contacter .borderedProminent]` ; propriétaire : `[Modifier]` seul ; tailles d'accessibilité : pile
verticale (branche existante). Téléphone : 1er appui = bouton (indicateur dans le rond) ; révélé → `Menu` dont l'en-tête est le numéro
(`Format.ltrIsolate`), entrées Appeler / Copier (→ bannière « Numéro copié ») ; les deux formes gardent `detail.phone`. Tous les états
du tableau de repérage restent couverts (vendu / expiré : pas de barre ; gratuit : pas d'offre ; visiteur : chaque action →
`router.requestLogin()`). **`detail.contact` doit rester un Button** (`app.buttons`, TourChat:197) ; `detail.offer`, `detail.edit`,
feuilles `detail.contact.sheet` / `detail.offer.sheet` inchangés. Nouveau libellé court `detailContactShort`.
**3. Transition zoom (BROWSE pose les sources, DETAIL rien, prétravail la destination)** : sources sur le libellé des NavigationLink des
cartes : HomeScreen ~252 (carrousels « À la une », « Tendances », « Pour vous » : clé `home.<rail>.<id>`) et ~324 (récentes), ListingsScreen
~342, SellerScreen ~181 (DETAIL), DetailSections ~250 (annonces similaires, DETAIL) ; `AppRoute.detail(idOrSlug:zoomSource:)` reçoit la
même clé. Une même annonce dans deux rangées = deux clés différentes.
**4. Onglet touché deux fois = haut de page (chaque agent sur ses racines)** : Accueil (`home.top` sur `SearchEntryButton`, BROWSE),
Annonces (id sur le compteur de résultats + retirer le focus de la recherche, BROWSE), Déposer (`post.scroll.top` existe, ACCOUNT),
Messages (`ScrollViewReader` autour de la `List`, cible = 1re conversation, INBOX), Profil (`profile.top` sur l'en-tête, ACCOUNT).
Vérifier en capture qu'iOS 26 ne défile pas déjà de lui-même (double défilement).
**5. Grands titres** : `.large` sur Messages + sa version visiteur (INBOX), Favoris, Alertes (BROWSE), Mes annonces, Profil visiteur, la
porte `LoginRequired` (`AccountComponents.swift` ~43-44) (ACCOUNT). Mes annonces : la rangée de puces horizontale AVANT la liste peut
capter le grand titre (il ne se replie plus) → la mettre dans le contenu défilant, ou vérifier en capture. Accueil (logo), Annonces
(barre masquée), fiche, chat : inchangés.
**6. Bannières iOS + « Annuler »** (chaque agent migre SES écrans de `floatingNotice` vers `weydaBanner`, `kind` juste : erreurs
`.error`, confirmations `.success`) :
- Favoris (BROWSE) : retrait (glisser ou cœur) → bannière « Retiré des favoris » + Annuler → `FavoritesRepository.toggle(id)` (ajoute
  si absent ; 409 `alreadyFavorited` = succès) et réinsertion de la rangée par le ViewModel (`idsChanged` ne fait que retirer).
- Alertes (BROWSE) : l'alerte de confirmation disparaît → suppression différée + Annuler (`pendingDeletions`) ; adapter
  `TourListsTests:110` et l'aide `deleteAlert` (~222) qui attendent `app.alerts`.
- Notifications (INBOX) : suppression différée (pas d'inverse côté API) : rangée masquée + pastille baissée, `delete` appelé à
  l'expiration, à la suppression suivante ou à `onDisappear` ; identifiants en attente filtrés du rafraîchissement et du temps réel
  (modèle `pendingRemovals` + `shown()` de FavoritesViewModel).
- Archiver une conversation (INBOX) : Annuler → `setArchived(conversationId:archived:)` inverse, rangée remise à sa place, delta de
  non-lus inversé.
- Feuilles d'actions iOS (`confirmationDialog`) au lieu des alertes : déconnexion (ProfileView ~101), vendu / supprimer (MyListings
  ~138), abandon des modifications (PostListingScreen ~85) [ACCOUNT] ; bloquer (SellerScreen ~87) [DETAIL] ; bloquer / supprimer un
  message (ChatView ~84) [INBOX]. On GARDE l'alerte pour la suppression du compte et pour débloquer. ⚠️ sur iPhone une feuille d'actions
  est `app.sheets`, pas `app.alerts` : adapter TourMyListings:28,40,52, TourChat:101 dans la même vague.
- Cœurs des cartes (Accueil, Annonces, vendeur) : les échecs sont muets aujourd'hui (personne n'écoute `favorites.errors`) → bannière
  d'erreur à la racine (BROWSE pour Accueil/Annonces, DETAIL pour vendeur/fiche).
**7. Haptique** : publication réussie (`PostListingViewModel.runSubmit` ~847, ACCOUNT, `success`) ; offre / premier message envoyés
depuis la fiche (callbacks `onOfferSent`/`onMessageSent` sur le modèle de ChatViewModel, DETAIL) ; signalement envoyé (Detail ~340,
Seller ~406 [DETAIL], Chat ~523 [INBOX]) et avis envoyé (Seller ~332) → `success` ; erreurs → via `WeydaBanner.kind`. Pas sur le
tirer-pour-rafraîchir ni sur les glissements pleins.
**8. Feuilles qui ne se ferment plus en perdant la saisie** : Filtres (BROWSE) : `draft != state.filters` (`ListingFilters` est
Hashable ; attention aux changements non voulus : `onChange(wilayaId)` qui vide la commune, « Réinitialiser ») →
`.interactiveDismissDisabled(dirty)` + « Fermer » modifié → feuille d'actions « Abandonner les modifications ? ». Connexion (ACCOUNT) :
`.interactiveDismissDisabled(isBusy || champs remplis)` dans chaque `*Host` (Login, Register, VerifyEmail…) ; « Fermer »
(`auth.close`) reste inconditionnel.
**9. Appui long** : annonces (BROWSE : Accueil, Annonces, Favoris ; DETAIL : vendeur, similaires) avec `listingContextMenu` ;
conversation (INBOX) : Archiver / Désarchiver (`chatArchive`/`chatUnarchive`) + Voir l'annonce (si connue) ; « Mes annonces »
(ACCOUNT) : menu sur la zone NavigationLink (~412-425) qui réutilise `available(for:)`, `title(for:)`, `symbol`, `isDestructive`,
désactivé pendant `isLocked`, avec aperçu ; identifiants `myListing.<action>.<id>` inchangés.
**10. Glissements** : rien de nouveau (voir « Ce qui ne se fait pas ») ; les glissements existants restent.
**11. Raccourcis sur l'icône (SYSTEM)** : déclarer une scène (`AppDelegate.application(_:configurationForConnecting:options:)` →
`UISceneConfiguration(delegateClass: SceneDelegate.self)`, SwiftUI garde la fenêtre) ; démarrage à froid
`connectionOptions.shortcutItem`, à chaud `windowScene(_:performActionFor:completionHandler:)` (dans une app à scènes,
`application(_:performActionFor:)` n'est jamais appelé) → `AppDelegate.navigation.open(ShortcutAction.target())` (tampon `pending` déjà
prévu pour le démarrage à froid). ⚠️ avec l'adaptateur, `UIApplication.shared.delegate as? AppDelegate` échoue (c'est le proxy de
SwiftUI) → référence statique. Articles DYNAMIQUES posés à chaque lancement (`UIApplication.shared.shortcutItems`, titres L10n, icônes
SF `plus.circle`, `magnifyingglass`, `envelope`) ; recherche → onglet Annonces, champ focalisé (`focusSearch`, consommé dans
`ListingsView` ~48 par `searchFocused`, BROWSE).
**12. Notifications à actions (SYSTEM)** : catégories enregistrées dans `didFinishLaunching` AVANT le délégué : `MESSAGE` =
`UNTextInputNotificationAction` « Répondre » (bouton `chatSend`, champ `chatMessagePlaceholder`) ; `OFFER` = « Accepter »
(`.authenticationRequired`) et « Refuser » (`.destructive`). `PushNotificationDelegate` (~178-189 ignore aujourd'hui toute action
autre que l'appui) → `didReceive` asynchrone : extraire d'abord la charge utile et `userText` (`UNNotificationResponse` n'est pas
Sendable), puis `ConversationsRepository.send(conversationId:content:)` ou `offerAction(conversationId:action:)` (`.accept` /
`.decline`), puis `markNotificationRead(id:)` et rafraîchir la pastille ; échec (403 `emailNotVerified`, hors ligne, 409 offre
dépassée) → notification locale `pushActionFailed`. **Lancement en arrière-plan** : SwiftUI peut ne connecter aucune scène → `attach`
jamais appelé → l'`AppContainer` doit appartenir à l'`AppDelegate` (créé dans `didFinishLaunching`, `WeydaApp` l'utilise au lieu de son
propre `@StateObject`) ; JAMAIS un second `SessionManager` (deux rotations du jeton de rafraîchissement = déconnexion). Trousseau :
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` → lisible écran verrouillé après le 1er déverrouillage : OK. Risque connu : accepter
depuis une vieille notification accepte la DERNIÈRE offre (le serveur dérive l'état du dernier message d'offre) → accepté pour v1 ;
garde serveur « offre attendue » possible plus tard. **Côté serveur (PR B, weyda2026 #6, `src/lib/fcm.ts` `buildFcmMessage`)** : ajouter
`category` à `aps` selon `message.type` (`MESSAGE` → `"MESSAGE"` ; `OFFER_RECEIVED`, `OFFER_COUNTER` → `"OFFER"`) — **accord du
propriétaire requis** (ligne EN-ATTENTE) ; sans lui l'app compile et fonctionne, les boutons n'apparaissent simplement pas.
**13. Note App Store et partage avec photo** : `.requestsReview(when:)` aux 4 moments (ACCOUNT : publication, vendu ; DETAIL : avis
envoyé, après la fermeture de la feuille ; INBOX : offre acceptée par le vendeur, `ChatView` ~157-161). Partage de la fiche avec aperçu
(DETAIL) : après chargement, le ViewModel demande la couverture au cache disque (`container.images.image(for: coverImage, targetSize:
~120 × 120, scale: 2)`, pas de réseau en général), `UIImage?` dans un `@Published` À PART (pas dans l'état Hashable) →
`ShareLink(item:subject:message:preview: SharePreview(titre, image:))`, aperçu texte seul sinon. Profil vendeur (DETAIL) : bouton
Partager (`SellerLinks.webURL`) dans la barre (aujourd'hui seul le menu de modération, si `canModerate`).

## Chaînes (prétravail ; fr / ar / en ; vérifier `L10n.swift` avant d'ajouter — existent déjà : `share`, `favoriteAdd`,
`favoriteRemove`, `chatArchive`, `chatUnarchive`, `chatArchived`, `chatUnarchived`, `offerAccept`, `offerDecline`, `chatSend`,
`chatMessagePlaceholder`, `navPost`, `navMessages`, `navListings`, `postDiscard*`, `detailContact`, `detailShowPhone`, `cancel`, `close`,
`listsAlertDeleted`, `myListingDeleted`, `profileLogout*`, `notificationDelete`). L'arabe est à faire relire avec la fiche App Store.
| clé | fr | ar | en |
|---|---|---|---|
| `undo` | Annuler | تراجع | Undo |
| `detail_contact_short` | Contacter | تواصل | Contact |
| `detail_call` | Appeler | اتصال | Call |
| `detail_copy_number` | Copier le numéro | نسخ الرقم | Copy number |
| `detail_number_copied` | Numéro copié | تم نسخ الرقم | Number copied |
| `menu_see_seller` | Voir le vendeur | عرض البائع | View seller |
| `menu_open_listing` | Voir l'annonce | عرض الإعلان | View listing |
| `favorite_removed` | Retiré des favoris | أُزيل من المفضلة | Removed from favorites |
| `notification_deleted` | Notification supprimée | تم حذف الإشعار | Notification deleted |
| `filters_discard_title` | Abandonner les modifications ? | تجاهل التعديلات؟ | Discard your changes? |
| `discard` | Abandonner | تجاهل | Discard |
| `keep_editing` | Continuer | متابعة التعديل | Keep editing |
| `shortcut_search` | Rechercher | بحث | Search |
| `push_action_reply` | Répondre | رد | Reply |
| `push_action_failed` | Action impossible depuis la notification. Ouvrez Weydaa pour réessayer. | تعذّر تنفيذ الإجراء من الإشعار. افتح Weydaa وأعد المحاولة. | Couldn't do that from the notification. Open Weydaa to try again. |
| `seller_share` | Partager le profil | مشاركة الملف الشخصي | Share profile |
(Raccourcis « Déposer » et « Messages » : `navPost`, `navMessages`.)

## Captures (chaque agent, tour à son nom ; API simulée)
DETAIL (`11d`) : fiche en haut, fiche défilée (barre + titre), barre d'actions (acheteur, gratuit, propriétaire, numéro révélé + menu),
appui long sur une annonce similaire, profil vendeur avec Partager, feuille d'actions « Bloquer ». BROWSE (`11b`) : appui long sur une
carte (aperçu + menu), favori retiré + bannière Annuler, alerte supprimée + Annuler, filtres modifiés + « Fermer » → feuille d'actions,
grands titres Favoris / Alertes, raccourci `-WeydaShortcut search` (champ focalisé). ACCOUNT (`11a`) : Mes annonces (grand titre, appui
long), feuilles d'actions déconnexion / vendu / supprimer / abandon, connexion remplie (glisser ne ferme pas). INBOX (`11i`) : Messages
grand titre, appui long sur une conversation, archivée + Annuler, notification supprimée + Annuler, feuille d'actions « Bloquer » du chat.
Toutes en fr/ar/en × clair/sombre × 2 iPhone, plus un passage très grand texte (fr/ar, iPhone 17e) sur fiche, filtres, bannières.
Notifications à actions et raccourcis : interface système, non photographiable → tests unitaires (correspondances, traitement d'une
réponse avec un faux dépôt) + test réel sur iPhone au premier TestFlight (étape C).

## Rendu de chaque agent (≤ 40 lignes) + note `<scratchpad>/ios-team/notes/p8-<agent>.md`
Fichiers touchés, API ajoutées, identifiants, chaînes utilisées, écarts avec ce contrat, points douteux pour la compilation.
