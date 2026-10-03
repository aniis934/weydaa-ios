# Phase 4 (Déposer une annonce) — contrats d'interface (complète CONTRACTS.md, CONTRACTS-P2.md, CONTRACTS-P3.md, SCREEN-BRIEF.md)

Dépôt de travail : `../weydaa-ios-p4` (worktree, branche `phase-4`, partie de `main` après la phase 3 : navigation, composants,
repositories, connexion, compte). AUCUNE commande git. Pas de Mac : chaque erreur de compilation = 10 min de CI.
Référence Android (LECTURE SEULE) : `../weydaa-site/android/app/src/main/java/com/weydaa/app/`
`ui/post/{PostListingViewModel,PostListingScreen,PostSteps,PostReviewScreens,PhotoPickers}.kt`, `ui/profile/MyListingsScreen.kt`,
`data/remote/dto/DraftDtos.kt`, `data/repository/UploadRepository.kt` ; tests `app/src/test/java/com/weydaa/app/{PostListingViewModelTest,UploadRepositoryTest}.kt`.
Ce qui EXISTE déjà côté iOS (à utiliser, pas à réécrire) : `AnnonceRepository.create/update/markSold/delete/renew`, `UploadRepository.upload(imageData:)`
(ImagePreparer → JPEG 1600 px, `prepare` injectable), `AttributeRepository.attributes/dependentOptions`, `GeoRepository.wilayas/communes`,
`CategoryRepository.roots`, `UserRepository.me`, `Validators.title/description/price/attribute(s)/asciiDigits` (renvoient `ValidationMessage?`, `.text`
= phrase traduite), `ErrorMapper` (`message(for:)`, `validationMessage(_:)` pour les codes d'attribut), modèles `ListingSubmission`, `UploadedImage`,
`AttributeSet`, `AttributeValue`, `Wilaya`, `Commune`, `Category`, `User.maxImages`, `Listing.imageRefs/parentCategorySlug/isRenewable(now:)`,
`MyListingsViewModel` (logique vendu / renouveler / supprimer + confirmation, SANS boutons), `DetailView` (bouton « Modifier » du propriétaire →
`router.push(.editListing(id:))` déjà branché), `AppRoute.editListing(id:)`, lien profond `/annonce/<id>/modifier`, `LaunchRoute` `editListing:<id>` et
`tab:post`, `LoginRequired`, `VerifyEmailBanner`, `AccountMemberGate`, `RemoteImage`, `floatingNotice` (DetailShared.swift), composants de formulaire
de la connexion (`Weyda/Features/Auth/AuthComponents.swift`). Toutes les chaînes `post_*` et `my_listing_*` d'Android sont DÉJÀ dans `L10n`
(`L10n.postStepOf(current, total)`, `L10n.postPhotosHint(max)`, `L10n.postCharCount(n, max)`… : vérifier la signature exacte dans L10n.swift).

## Répartition (3 agents en parallèle)
- **WIZARD** (logique + tests) :
  `Weyda/Features/Post/PostListingState.swift` (types ci-dessous), `Weyda/Features/Post/PostListingViewModel.swift`,
  `Weyda/Core/Local/PostDraftStore.swift` (brouillon), `Weyda/Core/Local/PostPhotoStore.swift` (photos locales),
  `Weyda/App/AppContainer.swift` (2 propriétés + amorçage du brouillon simulé, voir plus bas), `Weyda/App/LaunchOptions.swift` (`postDraft`),
  données simulées des brouillons `Weyda/Mock/MockFixtures/post/drafts/*.json`.
  Tests : `WeydaTests/PostListingViewModelTests.swift` (portage COMPLET de PostListingViewModelTest.kt, cas par cas), `WeydaTests/PostDraftStoreTests.swift`,
  `WeydaTests/PostPhotoStoreTests.swift`, `WeydaTests/UploadRepositoryTests.swift` (portage d'UploadRepositoryTest.kt).
- **SCREENS** (écrans de l'assistant + tour) :
  `Weyda/Features/Post/PostListingView.swift` (garde visiteur + hôte du ViewModel), `PostListingScreen.swift` (progression, barre Retour/Suivant,
  bandeau d'erreur, confirmation d'abandon en édition), `PostCategoryStep.swift`, `PostAttributesStep.swift`, `PostDetailsStep.swift`, `PostPhotosStep.swift`,
  `PostLocationStep.swift`, `PostReviewStep.swift`, `PostResultScreen.swift` (+ `PostComponents.swift` si besoin) — tous sous `Weyda/Features/Post/` ;
  dans le code existant : `Weyda/App/RootView.swift` (`TabRoot` : `.post` → `PostListingView()`), `Weyda/App/Navigation/RouteDestinations.swift`
  (`.editListing(let id)` → `PostListingView(editingId: id)`). Données simulées `Weyda/Mock/MockFixtures/routes-post.json` + `MockFixtures/post/`
  (hors `drafts/`). Tour `WeydaUITests/TourPostTests.swift` (captures 7x).
- **MEDIA** (sélecteurs de photos + actions de « Mes annonces ») :
  `Weyda/Features/Post/PostPhotoPickers.swift` (galerie, appareil photo, miniature locale — API ci-dessous), `Weyda/Resources/Info.plist`
  (`NSCameraUsageDescription`) + `Weyda/Resources/{fr,ar,en}.lproj/InfoPlist.strings` (texte localisé de la permission ; vérifier les noms de
  dossiers .lproj réels) ; `Weyda/Features/Account/MyListingsView.swift` (boutons d'action par annonce, confirmation, message) ;
  données simulées `Weyda/Mock/MockFixtures/routes-mylistings.json` + `MockFixtures/mylistings/` ; tests complémentaires de `MyListingsViewModel` s'il en
  manque (regarder d'abord `WeydaTests/ProfileViewModelsTests.swift`) dans `WeydaTests/MyListingsActionsTests.swift` ; tour `WeydaUITests/TourMyListingsTests.swift` (captures 8x).

## Types FIXÉS — WIZARD les écrit EXACTEMENT ainsi, SCREENS et MEDIA s'en servent
```swift
// Weyda/Features/Post/PostListingState.swift
nonisolated enum PostStep: String, CaseIterable, Codable, Sendable {      // ordre du site ; .attributes seulement si la catégorie en a
    case category = "CATEGORY", attributes = "ATTRIBUTES", details = "DETAILS", photos = "PHOTOS", location = "LOCATION", review = "REVIEW"
}
nonisolated enum PhotoStatus: String, Codable, Sendable { case uploading = "UPLOADING", done = "DONE", failed = "FAILED" }
nonisolated struct PhotoItem: Hashable, Sendable, Identifiable {
    /// Nom du fichier local (PostPhotoStore) ; pour une photo déjà en ligne (édition) : son URL distante.
    var localRef: String
    var upload: UploadedImage? = nil
    var status: PhotoStatus = .uploading
    var errorMessage: String? = nil
    var id: String { localRef }
    /// Aperçu distant (miniature si fournie, sinon l'image) une fois envoyée ; nil → aperçu local.
    var remoteURL: URL? { … }
}
nonisolated struct PostListingState: Equatable, Sendable {               // portage de PostListingUiState, @StringRes → String? déjà traduit
    var categories: [Category] = []; var categoriesLoading = true; var categoriesError = false
    var parentCategoryId: String? = nil; var subcategoryId: String? = nil; var categoryError: String? = nil
    var attributeSet: AttributeSet? = nil; var attributesLoading = false; var attributesError = false
    var attributeValues: [String: String] = [:]; var attributeErrors: [String: String] = [:]
    var dependentOptions: [String: [AttributeOption]] = [:]
    var title = ""; var description = ""; var priceType: PriceType = .fixed; var price = ""
    var titleError: String? = nil; var descriptionError: String? = nil; var priceError: String? = nil
    var photos: [PhotoItem] = []; var maxPhotos = 5; var photosNotice: String? = nil
    var wilayas: [Wilaya] = []; var wilayaId: Int? = nil; var communes: [Commune] = []; var communesLoading = false; var communeId: Int? = nil
    var userPhone: String? = nil; var listingPhone: String? = nil; var showPhone = false
    var step: PostStep = .category; var isSubmitting = false; var errorMessage: String? = nil
    var result: Listing? = nil
    var editingId: String? = nil; var editLoading = false; var editError: String? = nil
    var isDirty = false; var emailVerified = true
    // Calculées (mêmes règles qu'Android) : isEditing, parentCategory, subcategories, needsSubcategory, subcategory, categoryId,
    // isCategoryComplete, hasAttributes, steps: [PostStep], stepIndex, isFirstStep, isLastStep, isUploading, remainingPhotoSlots,
    // uploadedImages, contactPhone, canGoNext, selectedWilaya, selectedCommune ;
    // func optionsFor(_ d: AttributeDefinition) -> [AttributeOption] ; func isAttributeEnabled(_ d: AttributeDefinition) -> Bool ;
    // func toSubmission() -> ListingSubmission
}
```
```swift
// Weyda/Features/Post/PostListingViewModel.swift — MainActor (défaut)
final class PostListingViewModel: ObservableObject {
    @Published private(set) var state: PostListingState
    /// Fichiers des photos choisies (aperçu local : `photoStore.fileURL(for: item.localRef)`).
    let photoStore: PostPhotoStore
    init(editingId: String?, drafts: any PostDraftStore, photoStore: PostPhotoStore, annonces: AnnonceRepository,
         categories: CategoryRepository, attributes: AttributeRepository, geo: GeoRepository, auth: AuthRepository,
         users: UserRepository, uploads: UploadRepository, userUpdates: AnyPublisher<User?, Never>,
         locale: @escaping () -> String = { WeydaLocale.language })
    /// Nouveau dépôt : `container.postDrafts` + `container.postPhotos` (disque, survit à la fermeture) ;
    /// édition : brouillon en mémoire + `PostPhotoStore.standard(namespace: "edit")`.
    static func make(container: AppContainer, editingId: String?) -> PostListingViewModel
    // Chaque méthode qui lance du travail renvoie sa tâche (@discardableResult) : l'écran l'ignore, les tests l'attendent.
    @discardableResult func loadCategories() -> Task<Void, Never>?
    @discardableResult func loadEditing() -> Task<Void, Never>?
    @discardableResult func onSelectParent(_ id: String) -> Task<Void, Never>?
    @discardableResult func onSelectSubcategory(_ id: String) -> Task<Void, Never>?
    @discardableResult func onAttributeChange(_ key: String, _ value: String) -> Task<Void, Never>?
    func onTitleChange(_ value: String); func onDescriptionChange(_ value: String)
    func onPriceTypeChange(_ type: PriceType); func onPriceChange(_ value: String)
    /// Octets des photos choisies (galerie ou appareil) : écrites dans `photoStore` (SHA-256 = nom : une même photo choisie deux fois
    /// n'est ajoutée qu'une fois), places restantes respectées (excédent → `photosNotice` = L10n.postPhotosLimit(max)), file d'envoi lancée.
    @discardableResult func onPhotosPicked(_ images: [Data]) -> Task<Void, Never>?
    func onCameraUnavailable()
    func onRemovePhoto(at index: Int); func onMakeMainPhoto(at index: Int)
    @discardableResult func onRetryPhoto(at index: Int) -> Task<Void, Never>?
    @discardableResult func onWilayaChange(_ id: Int?) -> Task<Void, Never>?
    func onCommuneChange(_ id: Int?); func onShowPhoneChange(_ show: Bool)
    @discardableResult func next() -> Task<Void, Never>?        // valide l'étape ; à la dernière : submit()
    func back(); func goTo(_ step: PostStep)
    @discardableResult func submit() -> Task<Void, Never>?
    func clearDraft()                                            // « Déposer une autre annonce »
    func photosNoticeShown()                                     // efface photosNotice (message transitoire)
}
```
Écarts iOS assumés (à noter dans les commentaires) : pas d'`onLocaleChanged` (changer la langue de l'app dans Réglages relance l'app) ;
le brouillon d'édition vit en mémoire (iOS ne tue pas l'app pendant l'appareil photo comme Android peut le faire).
Session : `userUpdates` = `container.sessionManager.$user.eraseToAnyPublisher()` (même mécanisme que `ProfileViewModel`) — changement de compte → règles
d'Android (`onAccountChanged`), `emailVerified` suivi en direct.

```swift
// Weyda/Core/Local/PostDraftStore.swift — brouillon JSON (portage de PostDraftDto + DraftStore)
nonisolated struct PostDraft: Codable, Hashable, Sendable { … }   // mêmes champs que PostDraftDto ; photos: [PostDraft.Photo] (localRef, url, thumbnailUrl, publicId)
nonisolated protocol PostDraftStore: Sendable { func read() -> String?; func write(_ value: String); func clear() }
nonisolated final class FilePostDraftStore: PostDraftStore { init(fileURL: URL); static func standard() -> FilePostDraftStore }  // Application Support/PostDrafts/post_draft.json, exclu des sauvegardes
nonisolated final class InMemoryPostDraftStore: PostDraftStore { init(_ value: String? = nil) }  // verrou `OSAllocatedUnfairLock` (Sendable)
// Weyda/Core/Local/PostPhotoStore.swift
nonisolated struct PostPhotoStore: Sendable {
    init(directory: URL)                                   // créé à la demande, exclu des sauvegardes iCloud
    static func standard(namespace: String) -> PostPhotoStore   // Application Support/PostDrafts/<namespace>/ ("new" ou "edit")
    func fileURL(for ref: String) -> URL
    @concurrent func save(_ data: Data) async throws -> String  // ref = SHA-256 hex (CryptoKit) ; fichier déjà là → même ref, pas de réécriture
    @concurrent func load(_ ref: String) async throws -> Data
    func remove(_ ref: String)
    func purge(keeping refs: Set<String>)                  // au démarrage : fichiers que le brouillon ne cite plus
}
// AppContainer (WIZARD) : `let postDrafts: FilePostDraftStore` et `let postPhotos: PostPhotoStore` (namespace "new").
```

## API FIXÉE — MEDIA l'écrit, SCREENS s'en sert (`Weyda/Features/Post/PostPhotoPickers.swift`)
```swift
extension View {
    /// Galerie : `.photosPicker` d'iOS 16 (multi-sélection ≤ limit, images seulement, sans permission photo) ; charge les octets
    /// (`loadTransferable(type: Data.self)`, hors fil principal) puis rappelle `onPicked` sur le fil principal, dans l'ordre choisi.
    func postGalleryPicker(isPresented: Binding<Bool>, limit: Int, onPicked: @escaping ([Data]) -> Void) -> some View
    /// Appareil photo : `UIImagePickerController` (.camera) en plein écran ; photo → JPEG 0,9 → `onCaptured`. Annulation : rien.
    func postCameraPicker(isPresented: Binding<Bool>, onCaptured: @escaping (Data) -> Void) -> some View
}
nonisolated enum PostCamera { static var isAvailable: Bool { get } }   // UIImagePickerController.isSourceTypeAvailable(.camera) ; faux au simulateur
/// Miniature d'un fichier local, décodée HORS du fil principal à la taille affichée (ImageIO, `kCGImageSourceCreateThumbnailFromImageAlways`,
/// orientation EXIF appliquée) ; fond neutre pendant le décodage, icône si illisible. Remplit son cadre (`.scaledToFill` + clip par l'appelant).
struct LocalPhotoThumbnail: View { init(fileURL: URL) }
```
Pas d'appareil photo (simulateur) : SCREENS masque le bouton « Appareil photo » (`PostCamera.isAvailable`) ; `onCameraUnavailable` reste pour parité.

## Navigation et règles d'écran (SCREENS)
- Onglet Déposer : visiteur → `LoginRequired` (titre/texte d'Android pour le dépôt s'ils existent, sinon `loginRequiredTitle/Body`) → `router.requestLogin()` ;
  membre → l'assistant (ViewModel recréé pour un autre compte : `.id(user.id)`), `VerifyEmailBanner` si e-mail non vérifié (`router.requestEmailVerification()`).
- Édition (`PostListingView(editingId:)`, poussée sur la pile) : `AccountMemberGate`, ouverture sur le récapitulatif, bouton retour système remplacé par
  « retour au récapitulatif » puis confirmation d'abandon si modifié (`post_discard_*`) — règles du `BackHandler` Android. Glisser pour revenir : désactivé
  quand il ferait perdre des modifications (`.interactiveDismissDisabled` n'existe pas pour une pile : `navigationBarBackButtonHidden` + bouton maison).
- Résultat : « Voir l'annonce » → `router.push(.detail(idOrSlug:))` ; « Mes annonces » → `router.push(.myListings)` ; « Déposer une autre annonce » →
  `clearDraft()`. En édition : boutons du résultat d'Android (`post_updated_*`).
- Chaque étape repart du haut ; clavier : la barre Retour/Suivant reste au-dessus (`safeAreaInset(edge: .bottom)`), champ suivant au retour ;
  prix et nombres : clavier numérique, chiffres latins (`Validators.asciiDigits` est appliqué par le ViewModel).
- Attributs : SELECT → `Picker`/menu (ou liste dans une feuille si > 8 options, avec recherche), dépendant désactivé tant que le parent est vide
  (`postSelectParentFirst`), NUMBER → champ numérique + unité, BOOLEAN → `Toggle`, TEXT → champ ; requis marqués ; erreurs sous le champ.
- Photos : grille (2 ou 3 colonnes), photo principale marquée (`postPhotoMain`), menu par photo (principale, retirer, réessayer si échec), état
  d'envoi (indicateur) et d'échec (icône + message), compteur `postPhotoCount`, conseils `postPhotosHint(max)`.
- Localisation : wilaya puis commune (listes avec recherche fr/ar/en sans accents — `LocalizedName.resolve()`), « afficher mon numéro » si `contactPhone`.
- Récapitulatif : sections avec « Modifier » (`goTo`), avertissement `postEditPendingWarning` en édition, `postExpirationNotice`.
- Racines : `.accessibilityIdentifier("screen.post")` (assistant), `"screen.postResult"`, `"screen.postEdit"` (édition) ; identifiants utiles au
  tour : `post.next`, `post.back`, `post.step.<rawValue en minuscules>`.

## Données simulées
- WIZARD : brouillons `MockFixtures/post/drafts/<nom>.json` au format `PostDraft` (catégorie `vehicules` › `voitures`, attributs Renault Clio,
  titre « Renault Clio 4 GT Line 2019 », description de 2-3 phrases, prix 2 350 000 négociable, 3 photos DÉJÀ envoyées
  `https://photos.mock.weydaa/annonces/clio-<n>.webp`, wilaya 16 Alger, une commune de `communes-16.json`) : `step-category`, `step-attributes`,
  `step-details`, `step-photos`, `step-location`, `step-review` (chacun s'ouvre sur son étape, étapes précédentes remplies), `photos-failed`
  (2 photos envoyées + 1 photo sans fichier local → échec à l'envoi), `details-invalid` (titre « Clio », description trop courte, sur DETAILS).
  Lancement `-WeydaPostDraft <nom>` (API simulée seulement, `LaunchOptions.postDraft`) : AppContainer écrit le contenu brut du fichier dans
  `postDrafts` AVANT la création du ViewModel (et rien d'autre). Vérifier que MockPhotos dessine bien ces URL (lire `Weyda/Mock/MockPhotos.swift`).
- SCREENS : `routes-post.json` : `POST /api/annonces` → 201, annonce PENDING (id `mock-new-1`, reprend la Clio) ; `PUT /api/annonces/*` → annonce
  modifiée (générique) ; `POST /api/upload` → `{url, thumbnailUrl, publicId}` d'une photo `https://photos.mock.weydaa/annonces/upload-1.webp` ;
  `GET /api/annonces/mock-new-1` si « Voir l'annonce » doit s'ouvrir dans le tour. Vérifier comment les `routes-*.json` sont chargés
  (`MockURLProtocol.swift`) ; s'il faut toucher le chargeur, le DEMANDER dans la note.
- MEDIA : `routes-mylistings.json` : `PUT /api/annonces/<id ACTIVE précis>` → statut SOLD (chemin précis : il l'emporte sur le `*` de SCREENS),
  `PATCH /api/annonces/*` → `{ renewalsRemaining: 2 }`, `DELETE /api/annonces/*` → `{ success: true }` ; ids des annonces `mock-m1…m6` (lire
  `routes-account.json` et `MockFixtures/account/` pour leurs statuts).

## Chaînes
Chaque agent tient `<scratchpad>/ios-team/strings/<wizard|screens|media>.json` (format de `scripts/ios-strings.json` : `add` / `override`, fr + ar + en),
préfixes `post_` (WIZARD : `post_wiz_`, SCREENS : `post_ui_`) et `media_` / `my_listing_`. Accès `L10n.cleEnCamelCase` utilisable TOUT DE SUITE dans le code
(`%1$s` → String, `%1$d` → Int). Vérifier d'abord que la clé n'existe pas (`Weyda/Core/Localization/L10n.swift`). Arabe soigné, registre neutre.
Texte de permission de l'appareil photo : `InfoPlist.strings` (pas le catalogue).

## Captures (tour)
SCREENS (7x) : `captureLaunch(["-WeydaRoute", "tab:post", "-WeydaLoggedIn", "YES", "-WeydaPostDraft", "step-…"], name: "7x-…", screen: "post")` pour
chaque étape remplie, + assistant vide (pas de brouillon), visiteur (sans `-WeydaLoggedIn`), e-mail non vérifié, erreurs (`details-invalid` + appui
`post.next`), photos en échec, récapitulatif, publication → résultat (appui `post.next` sur le récapitulatif), édition (`editListing:<id>`).
MEDIA (8x) : « Mes annonces » avec boutons, confirmation « vendu », confirmation « supprimer », message après action.
Lire `WeydaUITests/TourSupport.swift` et un tour existant (`TourAccountTests.swift`) AVANT d'écrire.

## Rendu (≤ 40 lignes) + note `<scratchpad>/ios-team/notes/<agent>.md`
Fichiers créés/modifiés, API publique, écarts avec Android, demandes (chaînes, chargeur de routes, FakeWeydaAPI), points douteux pour la compilation.
