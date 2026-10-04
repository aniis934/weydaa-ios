# WEYDA iOS — application native (Swift 6 / SwiftUI)

Réplique native du site Weyda et de l'app Android, même API HTTP publique `https://weydaa.com/api/*`.
**Aucun Mac** sur le poste de dev (Windows) : on écrit le code ici, les Mac gratuits de GitHub Actions
compilent, testent et photographient. Dépôt **PUBLIC** (macOS gratuit et illimité) → règles de
confidentialité ci-dessous non négociables.

Stack : Swift 6 (isolation MainActor par défaut + « approachable concurrency ») · SwiftUI (UIKit
ponctuel) · iOS 16.0 minimum · iPhone seul, portrait · Xcode 26.6 (runner `macos-26`) · XcodeGen 2.46.0
· une seule dépendance : Firebase 12.19.2 exact (Messaging + Crashlytics, accordé en phase 5 ; inerte sans
`GoogleService-Info.plist`, isolé dans `Weyda/Core/Push/FirebasePush.swift`).

## Références (dépôt PRIVÉ voisin `../weydaa-site/`, jamais copiées telles quelles ici)
- App Android = la référence fonctionnelle : `android/CLAUDE.md`, `android/app/src/main/java/com/weydaa/app/`
  (theme/, brand/, navigation/, data/, ui/…) et ses tests `android/app/src/test/`.
- Contrat d'API : `android/docs/API-CONTRACT.md` (reste dans le dépôt privé).
- Chaînes : `android/app/src/main/res/values{,-ar,-en}/strings.xml` → converties par script (voir plus bas).
- Plan iOS validé et lots serveur : hors dépôt (voir la mémoire du projet) ; suivi ici : `docs/PLAN.md`.

## Mode en cours : AUTONOME jusqu'au bout
Toutes les phases s'enchaînent ; un blocage (compte, clé, feu vert, décision) → `docs/EN-ATTENTE.md`, puis on
continue ailleurs. Règles complètes : `docs/PROMPT-REPRISE.md`.

## Boucle de travail (pas de Mac)
1. Écrire un lot de code relu (conventions anti-erreurs ci-dessous).
2. `git push` → `gh run watch` (ios-ci : 5 à 15 min) → échec : `gh run view <id> --log-failed`.
3. Fin de phase : `gh workflow run ios-screens.yml --ref <branche>` puis `gh run download <id> -D <dossier>`
   (un artefact `ios-screens-<appareil>-<langue>` par tour)
   → relire TOUTES les captures (fr/ar/en, clair/sombre, 2 tailles) et la vidéo.
4. Scripts locaux (Node du poste, sans dépendance) :
   `node scripts/convert-strings.mjs` (catalogue + L10n.swift) · `node scripts/convert-icons.mjs` (icônes Lucide)
   · `node scripts/convert-category-art.mjs` (illustrations 3D des catégories, depuis `../weydaa-site/public/categories` ;
   décodage WebP par le `sharp` du dépôt voisin — aucune dépendance ici)
   · `node scripts/render-icon.mjs` (icône 1024 + W de démarrage) · `node scripts/check-strings.mjs` (parité, aussi en CI).

## Structure
```
project.yml              XcodeGen : cibles Weyda, WeydaTests, WeydaUITests (le .xcodeproj n'est JAMAIS commité)
Config/*.xcconfig        hôte API, Supabase (vide = temps réel coupé) ; Secrets.xcconfig écrit par la CI, ignoré par git
Weyda/App/               WeydaApp, AppContainer (DI manuelle : clients, session, 16 repositories, temps réel, images),
                         RootView (onglets + lancement), AppTab, LaunchOptions (arguments des tests), DeepLinks,
                         Navigation/ (AppRoute, AppRouter : une pile par onglet, RouteDestinations, LaunchRoute)
Weyda/Core/              Config, Localization (L10n.swift GÉNÉRÉ, WeydaLocale : langue + chiffres latins),
                         Models, Network (APIClient, WeydaAPI/LiveWeydaAPI, DTO/), Mapping, Session (trousseau),
                         Repositories, Realtime (Phoenix), Images (pipeline + RemoteImage), Upload, Local (historique,
                         brouillon du dépôt, photos locales), Common
                         (Format, ErrorMapper, Validators, Paging, SuggestionsEngine), Auth (Sign in with Apple +
                         nonce, Google par ASWebAuthenticationSession + PKCE, sans SDK)
Weyda/DesignSystem/      Tokens (WeydaColor/Palette/Ramp, WeydaSpace/Size/Radius, WeydaDuration/WeydaCurve,
                         WeydaTextStyle), Brand (WeydaMarkPath = tracé unique du W, WeydaMark/Extruded/Tile/
                         Loader/Wordmark, LaunchView), Components, Showcase (Debug)
Weyda/Features/          un dossier par domaine : Home, Listings, Detail, Seller, About (phase 2) ; Auth (feuille
                         de connexion `AuthFlowView`), Account (profil et écrans du compte) (phase 3) ; Post (assistant de
                         dépôt, modification, sélecteurs de photos) (phase 4) ; Shell (provisoires)
Weyda/Mock/              API simulée (Debug) : MockURLProtocol (jokers, `*` de requête), MockPhotos (photos dessinées),
                         MockFixtures/routes-<domaine>.json + dossiers (exclu des builds Release)
Weyda/Resources/         Assets.xcassets (AppIcon, SplashMark, LaunchBackground, AccentColor, Categories/ Lucide,
                         CategoryArt/ illustrations 3D du site @2x/@3x, GoogleLogo),
                         Localizable.xcstrings (GÉNÉRÉ), Info.plist (clés non générables), *.lproj/InfoPlist.strings
WeydaTests/              tests unitaires (logique portée d'Android avec ses cas de test)
WeydaUITests/            tour de captures : TourSupport (classe de base TourTestCase, `captureRoute`), un fichier
                         Tour<Écran>Tests par domaine (langue via TEST_RUNNER_WEYDA_LANG)
scripts/                 conversions (.mjs), scripts/ci/ (install-xcodegen, generate, test, screens)
.github/workflows/       ios-ci (chaque push ; `live` manuel = lecture seule contre la vraie API) · ios-screens (à la
                         demande : une compilation puis un tour par appareil × langue en parallèle) · ios-compat,
                         ios-release (branche prep/release, fusion en phase 6)
docs/equipe/             contrats d'interface de l'équipe d'agents (CONTRACTS*.md, SCREEN-BRIEF.md) : à lire avant d'écrire
```

## Règles OBLIGATOIRES
- **Dépôt public** : aucun secret (clés, .p8, GoogleService-Info.plist, jetons → coffre GitHub uniquement),
  aucune donnée personnelle (fixtures FICTIVES : ni vrais noms, téléphones, e-mails, ni photos d'utilisateurs),
  e-mail git masqué (`58832080+aniis934@users.noreply.github.com`, configuré dans ce clone).
- **i18n** : toute chaîne visible → catalogue. Jamais de texte en dur. Chaîne venue d'Android : la modifier
  dans `strings.xml` (dépôt privé) puis `node scripts/convert-strings.mjs`. Chaîne propre à iOS (ou phrase
  qui parle d'Android) : `scripts/ios-strings.json` (`add` / `override`, fr + ar + en). Accès typé :
  `L10n.navHome`, `L10n.priceDzd(x)`, `L10n.resultsCount(n)` (pluriels gérés). Seule exception : l'écran
  Showcase (Debug) affiche des noms de tokens en `Text(verbatim:)`. Libellés serveur via `nameFr/nameAr/nameEn`.
- **Langue** : réglage « langue de l'app » d'iOS (pas de sélecteur maison) ; `WeydaLocale.language`.
  Chiffres latins partout (`WeydaLocale.formatting`, posée sur l'environnement par RootView).
  `L10n.tr` groupe les milliers selon la locale (« 1 234 annonces ») : voulu ; un identifiant ou une année
  passe en `%@` (chaîne déjà formatée), jamais en `%lld`.
- **RTL** : `leading`/`trailing`, jamais gauche/droite. Le logo, l'extrusion et le mot « Weydaa » sont forcés
  en LTR. L'arabe est relu dans chaque tour de captures.
- **Architecture** : `XxxView` (possède le ViewModel `final class XxxViewModel: ObservableObject`, `@Published`)
  → `XxxScreen` sans état (état + actions en paramètres) → composants. Réseau UNIQUEMENT via le client et les
  repositories ; erreur `{ error: "code" }` → message traduit (ErrorMapper, phase 1).
- **Tokens obligatoires** : couleurs `WeydaColor`/`WeydaPalette`/`WeydaBrandColor`, espacements `WeydaSpace`,
  tailles `WeydaSize`, rayons `WeydaRadius` (`style: .continuous`), durées/courbes `WeydaDuration`/`WeydaCurve`,
  texte `.weydaText(.style)` (Dynamic Type). Composants iOS natifs (Liquid Glass automatique sur iOS 26+).
- **Animations** : `weydaAnimation(_:value:)` ou lecture de `accessibilityReduceMotion` — rien ne bouge
  quand « Réduire les animations » est actif.
- **iOS 16** : NavigationStack, PhotosPicker, ShareLink, feuilles à hauteur réglable, `Layout` sont OK ;
  toute API iOS 17+ (`@Observable`, `scrollPosition`, `containerRelativeFrame`, `ContentUnavailableView`,
  `sensoryFeedback`, `glassEffect`…) passe par `if #available` avec repli.
- **Le W** : `WeydaMarkPath.data` = la source iOS ; identique à `WEYDA_W_PATH_DATA` (Android) et à
  `scripts/render-icon.mjs` — toute retouche des trois côtés, puis `node scripts/render-icon.mjs`.
- **Visuels de catégorie** : toute vignette (accueil, feuille, dépôt, puces, fiche) = `CategoryArtwork(.category(slug:))`,
  l'illustration 3D du site ; le pictogramme `CategoryIcon.assetName(forSlug:)` seulement pour un petit repère
  (≤ 16 pt, critères d'alerte) ; jamais l'emoji `category.icon`.
- **Accessibilité / tests** : chaque écran racine porte `.accessibilityElement(children: .contain)` +
  `.accessibilityIdentifier("screen.<nom>")` (le tour de captures s'en sert).
- JAMAIS de dépendance sans accord · JAMAIS changer bundle ID (`com.weydaa.app`) / iOS minimum sans demande ·
  JAMAIS de paiement · écriture réelle en prod (publication, message) = feu vert explicite du propriétaire.

## Conventions anti-erreurs (chaque erreur de compilation = un aller-retour CI de 10 min)
- Types de données, logique pure, utilitaires : `nonisolated` (enum/struct/class). Sinon ils héritent de
  MainActor et leurs conformances (Codable, Hashable…) deviennent inutilisables hors du fil principal.
  Vues, ViewModels, AppContainer : MainActor (défaut).
- Une vue qui a un `@State private var` et qu'on crée depuis un autre fichier : **initialiseur explicite**
  (sinon l'initialiseur synthétisé devient privé).
- Petites vues, types explicites sur les closures non triviales, pas de longues expressions ternaires dans
  les modificateurs (le vérificateur de types de SwiftUI abandonne).
- `async` non isolé = s'exécute chez l'appelant (approachable concurrency) : décodage lourd → `@concurrent`.
- Pas de `Shape` maison (piège d'isolation) : `WeydaMarkPath.path(in:)` renvoie un `Path` (déjà une Shape).
- Fond d'une vue : `.background(couleur)` ou `.background(couleur, in: forme)` (pas l'ancienne forme dépréciée).
- Tests unitaires : cible SANS isolation MainActor par défaut ; marquer `@MainActor` un test qui touche une
  vue ou un ViewModel.

## Commits
Petits, en français, `type: description` (feat, fix, refactor, ui, docs, chore, ci, test) ; message via
fichier (`git commit -F fichier`). Une phase = une branche `phase-N`, PR vers `main` à la clôture.
