# Phase 7 (préparation App Store) — contrats d'interface (complète CONTRACTS.md … CONTRACTS-P6.md)

Dépôt de travail : `../weydaa-ios-p7` (worktree, branche `phase-7`, partie de `main` après la phase 6 : app complète, workflows
`ios-release` / `ios-compat` et dossier `docs/store/` fusionnés). AUCUNE commande git. Pas de Mac : chaque erreur = 10 min de CI.
Ce qui attend le propriétaire (compte Apple, clés, TestFlight, soumission) ne se fait PAS ici : on prépare tout pour qu'il n'ait plus qu'à
saisir et cliquer. Dépôt PUBLIC : aucun secret, aucune donnée personnelle, aucun contact réel (champs `[À FOURNIR]`).

## Répartition (2 agents en parallèle)
- **STORE** (captures de la fiche App Store) : `WeydaUITests/StoreShotsTests.swift` (nouveau), mode vitrine Debug
  `Weyda/DesignSystem/Showcase/StoreFrame.swift` (nouveau) + branchement minimal dans `Weyda/App/RootView.swift` et `Weyda/App/LaunchOptions.swift`
  (`-WeydaStoreCaption <1…8>`), légendes dans `<scratchpad>/ios-team/strings/store.json` (clés `store_caption_1` … `_8`, fr/ar/en =
  tableau de `docs/store/screenshots.md`), données simulées si nécessaire (voir « marques »), `docs/store/screenshots.md` (mise à jour : ce
  qui a été fait, comment relancer).
- **DOCS** (conformité et textes) : `Weyda/Resources/PrivacyInfo.xcprivacy` (nouveau, depuis le brouillon `docs/store/PrivacyInfo.xcprivacy`),
  test `WeydaTests/PrivacyManifestTests.swift` (le manifeste est dans le paquet de l'app, se lit, et déclare chaque API « à raison requise »
  réellement utilisée par le code de l'app), `docs/store/{app-privacy,review-notes,checklist-soumission,fiche-fr,fiche-ar,fiche-en,age-rating}.md`,
  `docs/RELEASE.md` (Firebase, Crashlytics, entitlements, capacités de l'App ID).

## STORE — règles
- Mode vitrine (Debug + API simulée SEULEMENT, jamais en Release) : `-WeydaStoreCaption <n>` → la racine affiche, au-dessus de l'app, un
  bandeau de marque (fond `WeydaBrandColor`/`WeydaColor.primary`, W de la marque, légende n en grand, `.weydaText`, centrée, 2 lignes au plus,
  RTL en arabe) et, dessous, l'app RÉDUITE dans un cadre aux coins continus (`WeydaRadius`, ombre douce) — rendu propre à 1320 × 2868
  (iPhone 17 Pro Max). Sans l'argument : rien ne change. Le tour n'interagit pas à travers le cadre réduit : chaque capture s'ouvre
  directement sur l'état voulu par les arguments existants (`-WeydaRoute`, `-WeydaLoggedIn`, `-WeydaPostDraft`, `-WeydaChatDemo`…).
- Les 8 écrans (ordre et légendes de `docs/store/screenshots.md`) : 1 accueil ; 2 annonces avec filtres actifs (`listings:category=…&wilaya=…`
  + prix si possible) ; 3 fiche `mock-a2` (galerie, prix, caractéristiques) ; 4 fil `mock-c1` (carte de contre-offre) ; 5 dépôt (brouillon
  `step-attributes` ou `step-photos`) ; 6 profil vendeur `mock-u1` (note, avis) ; 7 favoris ou alertes ; 8 accueil en sombre.
  `StoreShotsTests` : une méthode par écran, captures nommées `store-01-accueil` … `store-08-sombre` ; l'écran 8 seulement si l'apparence
  du tour est `dark` (variable d'environnement du tour / `UITraitCollection`), les 7 autres seulement en `light`.
- Marques : AUCUNE autre plateforme mobile visible (règle 2.3.10 : pas de « Samsung Galaxy », « Xiaomi », « Android »…) sur les 8 écrans.
  Les rails de l'accueil simulé contiennent « Samsung Galaxy S23 Ultra » et « Xiaomi Redmi Note 13 Pro » : choisir des cadrages qui ne les
  montrent pas, sinon remplacer ces deux annonces simulées par des objets neutres (et mettre à jour les tests qui citent leurs titres —
  `grep` dans `WeydaTests/` et `WeydaUITests/`). Pas d'iPhone d'un concurrent non plus (Apple tolère l'iPhone).
- Relecture : l'orchestrateur lance `ios-screens` (`-f tests="StoreShotsTests" -f devices="iPhone 17 Pro Max"`, apparences light puis dark),
  vérifie 1320 × 2868 et convertit en JPEG sans alpha.

## DOCS — règles
- `PrivacyInfo.xcprivacy` : `NSPrivacyTracking` false, aucun domaine de suivi, `NSPrivacyCollectedDataTypes` = EXACTEMENT les réponses de
  `app-privacy.md` (à revoir d'après le code des phases 1 à 6 : messagerie, offres, avis, favoris, alertes, signalements, utilisateurs bloqués,
  jeton FCM/APNs, Crashlytics en Release), `NSPrivacyAccessedAPITypes` d'après un `grep` du code de l'APP (pas des SDK : Firebase livre ses
  propres manifestes) : UserDefaults (`CA92.1`), dates de fichiers (`attributesOfItem`, `.contentModificationDateKey`, `creationDate`… →
  `C617.1`), espace disque, heure de démarrage (`systemUptime`, `mach_absolute_time`)… chaque raison justifiée en commentaire. Fichier sous
  `Weyda/Resources/` (pris dans le paquet par XcodeGen ; le vérifier dans `project.yml`), plist XML valide (tester avec `plistlib`).
- `app-privacy.md` / fiches / notes de revue / check-list / RELEASE.md : mettre à jour d'après l'app RÉELLE (phases 5 et 6 : messagerie et
  offres, notifications push, utilisateurs bloqués dans Profil → Utilisateurs bloqués, favoris, alertes, avis ; Crashlytics ; liens
  universels), en lisant le code (`Weyda/Features/**`) et `L10n.swift` pour les libellés EXACTS des chemins d'écran (fr et en). Remplacer les
  `[À CONFIRMER à la phase 5]` qui peuvent l'être ; garder `[À FOURNIR]` pour ce qui dépend du propriétaire (comptes de démo, contact,
  délai de traitement des signalements si les CGU ne le fixent pas — lire le lot B : `git -C ../weydaa-server-ios show
  origin/ios/lot-b-push-moderation:messages/fr.json` section CGU).
- `RELEASE.md` : secret `GOOGLE_SERVICE_INFO_PLIST`, envoi des dSYM à Crashlytics (étape `symbols`), entitlements de Release
  (`Config/Weyda.entitlements` : push, liens universels, Sign in with Apple) et capacités à cocher sur l'App ID, `aps-environment`
  (`development` dans le fichier, l'export App Store le passe en production).

## Rendu (≤ 40 lignes) + note `<scratchpad>/ios-team/notes/<store|docs>.md`
