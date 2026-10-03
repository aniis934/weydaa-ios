# Phase 2 (Parcourir) — contrats d'interface (complète CONTRACTS.md, qui reste valable en entier)

Dépôt de travail de la phase 2 : `../weydaa-ios-p2` (worktree git, branche
`phase-2`). La couche données (phase 1) y est déjà : `Weyda/Core/**` — lis les fichiers, ne les modifie pas
(demande dans ta note). Écrans Android de référence : `android/app/src/main/java/com/weydaa/app/ui/{home,listings,detail,seller,components,settings/AboutScreen.kt,navigation}`.

## Architecture d'un écran (obligatoire, CLAUDE.md du dépôt)
`XxxView` (point d'entrée, lit `@EnvironmentObject container: AppContainer` et `router: AppRouter`, crée le ViewModel)
→ `XxxScreen` SANS état (reçoit `state` + closures d'action) → composants.
```swift
struct DetailView: View {                                   // init public, paramètres simples
    @EnvironmentObject private var container: AppContainer
    let idOrSlug: String
    var body: some View { DetailHost(model: DetailViewModel(idOrSlug: idOrSlug, annonces: container.annonces /* … */)) }
}
private struct DetailHost: View {
    @StateObject private var model: DetailViewModel
    init(model: @autoclosure @escaping () -> DetailViewModel) { _model = StateObject(wrappedValue: model()) }
    var body: some View { DetailScreen(state: model.state, onRetry: model.load /* … */) }
}
final class DetailViewModel: ObservableObject { @Published private(set) var state = DetailState() … }   // MainActor (défaut)
nonisolated struct DetailState: Equatable, Sendable { … }   // état = données pures → nonisolated
```
Chargement : `.task { await model.loadIfNeeded() }` (une fois) ; tirer pour rafraîchir : `.refreshable`.
Racine de chaque écran : `.accessibilityElement(children: .contain)` + `.accessibilityIdentifier("screen.<nom>")`.
Erreur : `ErrorMapper.message(for:)` (nil = annulation → ne rien afficher). Hors ligne : `container.connectivity`.

## Navigation — propriétaire : agent SHELL (`Weyda/App/Navigation/`)
```swift
nonisolated enum AppRoute: Hashable, Sendable {
    case detail(idOrSlug: String)
    case seller(id: String)
    case webPage(WebPage)                                  // pages légales du site (SFSafariViewController)
    case about
    // phases suivantes (destinations provisoires en phase 2) :
    case chat(conversationId: String, archived: Bool), myListings, favorites, savedSearches, notifications,
         editProfile, changePassword, accountData, contact, editListing(id: String)
}
nonisolated struct ListingsLaunch: Hashable, Sendable {      // ouverture de l'onglet Annonces avec des critères
    var q: String? = nil; var category: String? = nil; var subcategory: String? = nil; var wilaya: Int? = nil; var featured: Bool = false
}
final class AppRouter: ObservableObject {                     // MainActor ; créé par WeydaApp, posé en environmentObject
    @Published var selectedTab: AppTab
    @Published var listingsLaunch: ListingsLaunch?            // consommée (remise à nil) par l'onglet Annonces
    func push(_ route: AppRoute)                              // sur la pile de l'onglet courant
    func openListings(_ launch: ListingsLaunch)               // bascule sur l'onglet Annonces + critères
    func popToRoot(_ tab: AppTab)
    func path(for tab: AppTab) -> Binding<[AppRoute]>
    func open(_ target: DeepLinkTarget)                       // liens profonds (DeepLinks.swift, phase 1)
}
```
Navigation dans un écran : `Button { router.push(.detail(idOrSlug: listing.id)) }` ou `NavigationLink(value: AppRoute.detail(...))`.
`RouteDestinations.swift` (SHELL) fait le `switch` route → vue, avec ces points d'entrée EXACTS :
`HomeView()`, `ListingsView()`, `DetailView(idOrSlug: String)`, `SellerView(id: String)`, `AboutView()`,
`WebPageView(page: WebPage)`. Les routes des phases suivantes ouvrent `ComingSoonView(route:)` (SHELL).

## Composants communs — propriétaire : agent SHELL (`Weyda/DesignSystem/Components/`)
Initialiseurs EXACTS (les agents HOME / LISTINGS / DETAIL les utilisent pendant que SHELL les écrit) :
```swift
ListingCard(listing: Listing, isFavorite: Bool? = nil, onFavorite: (() -> Void)? = nil)       // grille : photo 4:3, prix, titre 2 lignes, lieu, « À la une »
ListingCarouselCard(listing: Listing, isFavorite: Bool? = nil, onFavorite: (() -> Void)? = nil) // largeur WeydaSize.carouselCard
ListingRow(listing: Listing, isFavorite: Bool? = nil, onFavorite: (() -> Void)? = nil)        // vignette WeydaSize.rowThumb*
FavoriteButton(isFavorite: Bool, action: @escaping () -> Void)
FeaturedBadge()
PriceText(price: Double?, priceType: PriceType, style: WeydaTextStyle = .price)
LocationLine(wilaya: LocalizedName?, commune: LocalizedName?)
CategoryCircle(title: String, iconAsset: String, action: @escaping () -> Void)                 // pastille ronde de l'accueil
CategoryTile(title: String, iconAsset: String, count: Int?, action: @escaping () -> Void)
WeydaChip(title: String, isSelected: Bool = false, iconAsset: String? = nil, onRemove: (() -> Void)? = nil, action: @escaping () -> Void)
RatingStars(rating: Double, size: CGFloat = 14)
WeydaSearchField(text: Binding<String>, placeholder: String, onSubmit: @escaping () -> Void)
SearchEntryButton(placeholder: String, action: @escaping () -> Void)                           // faux champ de l'accueil
SectionHeader(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil)
LoadingState() · InlineLoader()
ErrorState(message: String, onRetry: @escaping () -> Void)
EmptyState(systemImage: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil)
OfflineBanner()                                                                                 // lit container.connectivity
SkeletonBlock(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = WeydaRadius.badge)
ListingCardSkeleton() · ListingRowSkeleton() · ListingRowSkeletons(count: Int = 6) · ListingCardSkeletonRow() · CategoryCircleSkeletonRow() · ChipSkeletonRow()
extension View { func weydaShimmer(active: Bool = true) -> some View }                         // immobile si « Réduire les animations »
LoginRequired(title: String, message: String, onLogin: @escaping () -> Void)                     // utilisé en phase 3
```
Photos : `RemoteImage` (pipeline de la phase 1, `Weyda/Core/Images/`), miniature `listing.coverThumbnail` dans les listes.
Icônes de catégorie : `CategoryIcon.assetName(forSlug:)` + `CategoryIconImage`. Interface : SF Symbols.

## Données simulées (captures) — chaque agent ajoute SES fichiers
`Weyda/Mock/MockFixtures/routes-<domaine>.json` (+ réponses sous `MockFixtures/<domaine>/`). Format des routes :
`Weyda/Mock/MockURLProtocol.swift` (jokers `*`, `**`, contraintes `query`, la plus précise gagne). Photos :
`https://photos.mock.weydaa/annonces/<objet>-<n>.webp` (dessinées ; objets : car, phone, laptop, house, sofa, tv,
fridge, bike, watch, dress, pet, tools, job, travel). Données 100 % FICTIVES, plausibles pour l'Algérie (wilayas réelles,
prix en DA réalistes, noms de vendeurs fictifs), en français (les annonces sont rédigées par les vendeurs ; catégories et
wilayas portent fr/ar/en). Domaines : SHELL → aucun ; HOME → `home` (catégories, à la une, récentes, tendances, villes) ;
LISTINGS → `search` (recherche, facettes, suggestions, did-you-mean, attributs) ; DETAIL → `detail` (fiches, vendeurs, avis, similaires).
Ids partagés (pour que les liens se recoupent) : annonces `mock-a1` … `mock-a24`, vendeurs `mock-u1` … `mock-u6` —
HOME écrit la liste de référence `MockFixtures/home/annonces-recentes.json` (24 annonces) EN PREMIER et la décrit dans sa note.

## Tour de captures — propriétaire : agent SHELL (`WeydaUITests/TourTests.swift`, `App/LaunchOptions.swift`)
Option de lancement `-WeydaRoute <route>` (ex. `detail:mock-a3`, `seller:mock-u2`, `listings:q=clio`, `tab:listings`)
qui ouvre directement l'écran (tour rapide et robuste, sans enchaîner les appuis). Captures nommées `NN-<écran>[-<variante>]`.
Chaque agent écran indique dans sa note les captures voulues (route + nom + défilements éventuels).

## Précisions (orchestrateur)
- `AboutView()` et `WebPageView(page:)` (portage de `settings/AboutScreen.kt` + pages web du site dans `SFSafariViewController`) : agent SHELL.
  `DetailView`, `SellerView` : agent DETAIL. `HomeView` (+ feuille des catégories) : agent HOME. `ListingsView` (+ filtres, suggestions) : agent LISTINGS.
- Données du CATALOGUE déjà fournies par la phase 1 (`MockFixtures/routes-catalog.json` : catégories, wilayas, villes populaires,
  communes, attributs) : NE PAS redéfinir ces routes ; les réutiliser. Les annonces, vendeurs, avis viennent des agents phase 2.
- AppContainer : la session s'appelle `container.sessionManager` (pas `session`).
- `router.requestLogin()` : action réservée touchée par un visiteur (favori, contacter, numéro, signaler). Phase 2 : bascule
  sur l'onglet Profil (`LoginRequired`) ; phase 3 : feuille de connexion. Ne PAS inventer d'écran de connexion en phase 2.
- Tour : classe de base `TourTestCase` (`WeydaUITests/TourSupport.swift`, SHELL) avec `captureRoute(_:name:scrolls:)` ;
  chaque agent d'écran crée SA classe dans SON fichier (`TourHomeTests.swift`, `TourListingsTests.swift`, `TourDetailTests.swift`).
- Propriété des routes simulées de `GET /api/annonces` (la plus précise gagne) : HOME → sans contrainte (= récentes, 24
  annonces `mock-a1…a24`), `featured=1`, `/api/annonces/trending`, `/api/recommendations` ; LISTINGS → toute route avec
  `q`, `category`, `subcategory`, `wilaya`, `commune`, `priceType`, `sort` ≠ newest, `page` ≥ 2, `withFacets`, et `/api/search/**` ;
  DETAIL → `/api/annonces/*` (fiche par id ou slug), `POST /api/annonces/*/view`, `/api/users/*`, `/api/users/*/annonces`,
  `/api/reviews`, `/api/reviews/eligibility`, `/api/favorites/*` (visiteur : `{isFavorite:false}`).
