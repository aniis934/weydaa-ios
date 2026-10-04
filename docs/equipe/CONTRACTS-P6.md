# Phase 6 (Favoris, alertes, avis, finition) — contrats d'interface (complète CONTRACTS.md, CONTRACTS-P2…P5.md, SCREEN-BRIEF.md)

Dépôt de travail : `../weydaa-ios-p6` (worktree, branche `phase-6`, partie de `main` après la phase 5 : messagerie, notifications,
push). AUCUNE commande git. Pas de Mac : chaque erreur de compilation = 10 min de CI. Notes de l'équipe : `<scratchpad>/ios-team/notes/`
(`shell.md`, `data.md`, `utils.md`, `chat.md`, `inbox.md` : API réelle des composants, repositories, formats, rangées de la phase 5).
Référence Android (LECTURE SEULE) : `../weydaa-site/android/app/src/main/java/com/weydaa/app/`
`ui/favorites/FavoritesScreen.kt` (ViewModel dans le même fichier), `ui/alerts/SavedSearchesScreen.kt` (idem), `ui/seller/{SellerViewModel,
SellerScreen,ReviewDialog}.kt` ; tests `app/src/test/java/com/weydaa/app/{FavoritesRepositoryTest,SavedSearchesRepositoryTest,SellerProfileTest,
ReviewsRepositoryTest}.kt`.

## Ce qui EXISTE déjà (à utiliser, pas à réécrire)
- `FavoritesRepository` (`ids` @Published, `isFavorite`, `list() -> [Listing]`, `toggle`, `toggleDetached`, suit la session ; 403 `emailNotVerified`
  même en lecture), `SavedSearchesRepository` (`list() -> [SavedSearch]`, `create(params:) -> SaveSearchOutcome`, `delete(id:)` ; 5 au maximum),
  `SearchRepository.pendingParams` (déposer les paramètres d'une alerte : l'onglet Annonces les applique de lui-même), `ReviewsRepository`
  (`forSeller`, `eligibility(sellerId:) -> ReviewEligibility`, `submit(sellerId:rating:comment:)`), modèles `SavedSearch` (`name`, `params`, `createdAt`),
  `ReviewEligibility` (`canReview`, `existing: MyReview?`), `MyReview.commentMax` (1000), `Review`, `ReviewSummary`.
- `SellerViewModel` / `SellerView` / `SellerScreen` (phase 2 : vitrine, avis, signaler, bloquer — « Laisser un avis » annoncé pour la phase 6).
- Composants : cartes et rangées d'annonce (`ListingCards.swift`), `RatingStars`, états, squelettes, `LoginRequired`, `AccountMemberGate`, `VerifyEmailBanner`,
  `floatingNotice`, feuilles « Annuler | Titre » (`ReportSheet`, `OfferAmountSheet` : même gabarit), formats (prix, dates relatives, chiffres latins).
- Navigation (FAITE par l'orchestrateur) : `RouteDestinations` ouvre `FavoritesView()` (`.favorites`) et `SavedSearchesView()` (`.savedSearches`) ;
  liens profonds et `-WeydaRoute favorites` / `savedSearches` existent ; le menu du Profil y mène déjà. Onglet Annonces : `router.openListings(_:)`,
  `router.select(.listings)`.

## Répartition (2 agents en parallèle, lot 1)
- **LISTS** : `Weyda/Features/Favorites/{FavoritesViewModel,FavoritesView,FavoritesScreen}.swift`, `Weyda/Features/Alerts/{SavedSearchesViewModel,
  SavedSearchesView,SavedSearchesScreen}.swift`, données simulées `Weyda/Mock/MockFixtures/routes-lists.json` + `MockFixtures/lists/`, tests
  `WeydaTests/{FavoritesViewModelTests,SavedSearchesViewModelTests}.swift`, tour `WeydaUITests/TourListsTests.swift` (captures `10l-…`).
- **REVIEWS** : `Weyda/Features/Seller/{SellerViewModel,SellerView,SellerScreen}.swift` (ajouts : éligibilité, bouton, feuille, envoi) +
  `Weyda/Features/Seller/ReviewSheet.swift` (nouveau), données simulées `routes-reviews.json` + `MockFixtures/reviews/`, tests
  `WeydaTests/SellerReviewTests.swift` (portage des cas d'avis de SellerProfileTest.kt / ReviewsRepositoryTest.kt), tour `WeydaUITests/TourReviewsTests.swift`
  (captures `10r-…`) ; `Weyda/App/LaunchOptions.swift` (`reviewDemo`, Debug + API simulée, si une capture de feuille remplie en a besoin).

## API FIXÉE
```swift
struct FavoritesView: View { init() }        // membre (AccountMemberGate) ; e-mail non vérifié → bandeau + état explicatif (403)
struct SavedSearchesView: View { init() }    // membre
/// Feuille « Laisser un avis » / « Modifier mon avis » (gabarit des feuilles « Annuler | Titre » de l'app) : 5 étoiles (cibles 44 pt, VoiceOver
/// réglable par `accessibilityAdjustableAction`), commentaire facultatif ≤ MyReview.commentMax avec compteur, envoi occupé, erreur traduite.
struct ReviewSheet: View {
    init(sellerName: String, isEditing: Bool, rating: Binding<Int>, comment: Binding<String>, isBusy: Bool, errorMessage: String?,
         onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void)
}
```

## Règles d'écran
**Favoris** (portage de FavoritesScreen) : liste d'annonces (rangée existante, cœur plein pour retirer — retrait optimiste, la rangée disparaît aussi
quand le cœur est retiré ailleurs : suivre `favorites.ids`), tirer pour rafraîchir, ouverture de la fiche, vide (texte + « Parcourir les annonces » →
onglet Annonces), erreur + réessayer, e-mail non vérifié (403) → `VerifyEmailBanner` + message. Racine `screen.favorites`, rangées `favorite.row.<id>`.
**Alertes** (portage de SavedSearchesScreen) : rangées (nom de l'alerte, critères lisibles en puces : recherche, catégorie, wilaya, prix… libellés
localisés via le catalogue déjà chargé / `LocalizedName.resolve()`, date de création), appui → `container.search.pendingParams = alerte.params` puis
onglet Annonces revenu à sa racine (`router.popToRoot(.listings)` + `router.select(.listings)` ou l'équivalent existant), glisser pour supprimer avec
confirmation, compteur « n / 5 », note « créez une alerte depuis une recherche » (bouton → onglet Annonces), vide, erreur. Racine
`screen.savedSearches`, rangées `alert.row.<id>`.
**Avis** (portage de SellerViewModel + ReviewDialog) : membre connecté, pas soi-même → éligibilité chargée avec le profil (échec silencieux) ;
`canReview` → bouton « Laisser un avis » (ou « Modifier mon avis » si `existing`, feuille pré-remplie) dans la section des avis ; visiteur → bouton
qui mène à la connexion (`router.requestLogin()`) seulement si Android le fait, sinon rien ; envoi → message `review_sent`, avis relus ; erreurs
403 `notEligible` / `emailNotVerified` / `userBlocked`, 400 `ownReviewError` → `ErrorMapper` (feuille fermée sur refus serveur, gardée sur erreur
réseau, comme Android). Identifiants : `seller.review.open`, `review.star.<n>`, `review.submit`.

## Données simulées (FICTIVES)
- LISTS : `GET /api/favorites` → 5 annonces existantes (`mock-a3`, `mock-a10`, `mock-a14`, `mock-a17`, `mock-a25` : reprendre les fiches de
  `MockFixtures/detail/`) ; `DELETE /api/favorites*` → `{ success: true }` ; `GET /api/saved-searches` → 4 alertes (« Clio à Alger » q=clio
  category=vehicules wilaya=16 ; « Appartements F3 à Oran » category=immobilier wilaya=31 priceMax=… ; « iPhone moins de 150 000 DA » ;
  « Vélos » subcategory=…) — `params` = clés d'URL du site ; `DELETE /api/saved-searches/*` → `{ success: true }`.
  ⚠️ `FavoritesRepository` charge `GET /api/favorites` à l'ouverture de session (`-WeydaLoggedIn`) : les cœurs pleins apparaîtront donc aussi dans
  les tours des phases 2 à 5 (voulu, vérifier que rien ne casse).
- REVIEWS : `GET /api/reviews/eligibility` (lire la route réelle dans `LiveWeydaAPI.swift`) → `canReview: true` sans avis pour `mock-u1`,
  avec avis existant (4 étoiles + commentaire) pour `mock-u2`, `canReview: false` pour les autres ; `POST /api/reviews` → avis créé.

## Chaînes
`<scratchpad>/ios-team/strings/<lists|reviews>.json` (format `scripts/ios-strings.json`), préfixes `lists_` / `reviews_` ; vérifier d'abord
`L10n.swift` (toutes les chaînes `favorites_*`, `alerts_*`, `review_*` d'Android y sont).

## Captures
LISTS (10l) : favoris (liste, vide, e-mail non vérifié, glisser), alertes (liste, confirmation de suppression, vide, ouverture → onglet Annonces filtré).
REVIEWS (10r) : profil `mock-u1` avec bouton, feuille vide, feuille remplie (étoiles + commentaire — sans clavier : préremplir par lancement Debug si
besoin, `-WeydaReviewDemo`), envoi → message, profil `mock-u2` « Modifier mon avis » + feuille pré-remplie.

## Rendu (≤ 40 lignes) + note `<scratchpad>/ios-team/notes/<lists|reviews>.md`
Fichiers, API, écarts avec Android, demandes, points douteux pour la compilation.
