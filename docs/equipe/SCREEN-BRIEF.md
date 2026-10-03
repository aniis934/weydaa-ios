# Brief commun des agents d'écran (phase 2 et suivantes)

Dépôt de travail : `../weydaa-ios-p2` (worktree, branche `phase-2`). Aucune commande git.
Pas de Mac ni de compilateur Swift ici : la CI (Mac GitHub) compile ; chaque erreur = 10 min perdues. L'orchestrateur intègre.

## À lire AVANT d'écrire (dans cet ordre)
1. `ios-team/CONTRACTS.md` (règles, pièges Swift 6.2 — dont la section « Pièges constatés en CI » —, conventions), puis
   `ios-team/CONTRACTS-P2.md` (architecture d'écran View → Host → Screen → ViewModel/State, navigation, composants,
   routes simulées, tour), puis les notes `ios-team/notes/shell.md` (API EXACTE des composants et du routeur, règles
   d'usage : cartes enveloppées dans `NavigationLink` + `.buttonStyle(.weydaCard)`, favori en action VoiceOver…),
   `notes/data.md` (modèles, repositories : signatures réelles), `notes/utils.md` (formats, images, suggestions), `notes/network.md`.
2. `weydaa-ios-p2/CLAUDE.md` ; le code réel : `Weyda/App/**` (AppContainer : noms des repositories ; Navigation/),
   `Weyda/DesignSystem/**` (tokens + Components), `Weyda/Core/Repositories/*`, `Weyda/Core/Models/Models.swift`,
   `Weyda/Core/Common/{Format,ErrorMapper,Paging,SuggestionsEngine}.swift`, `Weyda/Core/Images/RemoteImage.swift`,
   `WeydaUITests/TourSupport.swift`, `Weyda/Mock/MockURLProtocol.swift` + `MockFixtures/routes-catalog.json`.
   `Weyda/Core/Localization/L10n.swift` = les 543 chaînes typées (GÉNÉRÉ) : cherche-y les textes d'Android par leur clé.
3. Goûts du propriétaire : `(mémoire du propriétaire : goûts design)`.
4. Référence Android (LECTURE SEULE) : `../weydaa-site/android/app/src/main/java/com/weydaa/app/ui/…`
   (écran, ViewModel, et leurs tests sous `android/app/src/test/java/com/weydaa/app/`).

## Règles de rendu (iOS natif, parité Android)
- Mêmes informations, mêmes règles, mêmes cas (chargement, vide, erreur avec réessayer, hors ligne, rafraîchir) qu'Android ;
  rendu iOS : composants natifs (List/ScrollView, `.searchable` si pertinent, `.sheet` avec `presentationDetents`, menus,
  `ShareLink`, `.refreshable`), Liquid Glass automatique sur iOS 26, aspect classique sur iOS 16.
- Tokens obligatoires, `.weydaText`, Dynamic Type, cibles 44 pt, VoiceOver (étiquettes claires, éléments regroupés),
  RTL par `leading`/`trailing`, animations via `weydaAnimation` (rien ne bouge si « Réduire les animations »).
- Chiffres latins (Format / WeydaLocale), libellés serveur via `LocalizedName.resolve()`.
- iOS 16 : pas d'API 17+ sans `if #available` (pas d'`onChange` à 2 paramètres, pas de `scrollPosition`, pas de
  `ContentUnavailableView`, pas de `@Observable`). Initialiseur explicite pour toute vue avec `@State private` créée ailleurs.
- Petites vues, types explicites sur les closures non triviales, pas de longues expressions ternaires dans les modificateurs.
- Racine de chaque écran : `.accessibilityElement(children: .contain)` + `.accessibilityIdentifier("screen.<nom>")`.
- Aucun texte en dur : `L10n`. Chaîne manquante → `scripts/ios-strings.json` est GÉRÉ par l'orchestrateur : demande-la dans
  ta note (clé, fr, ar, en) et, en attendant, n'utilise pas de clé inexistante (le code doit compiler).
- Données simulées FICTIVES, plausibles pour l'Algérie, dans TES fichiers de routes (`routes-<domaine>.json` + dossier).
- Tests unitaires de tes ViewModels (portage des tests Android correspondants) avec `FakeWeydaAPI` (`WeydaTests/FakeWeydaAPI.swift`,
  à LIRE, ne pas modifier : s'il te manque une route configurable, dis-le dans ta note) ; `@MainActor` sur les tests qui touchent un ViewModel.
- Tour : ta classe `final class TourXxxTests: TourTestCase` dans ton fichier, une ligne `captureRoute(...)` par capture.

## Fin de travail
Relis CHAQUE fichier comme le compilateur Swift 6.2 strict, puis ta note `ios-team/notes/<agent>.md` : fichiers, API, captures,
écarts avec Android, demandes (chaînes fr/ar/en, routes de FakeWeydaAPI…), points douteux pour la compilation.
Rendu final ≤ 40 lignes.
