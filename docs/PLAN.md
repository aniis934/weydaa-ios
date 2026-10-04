# Plan — application iOS native Weyda

> Plan validé le 2026-10-02 (version complète, avec les lots serveur et les actions du propriétaire :
> hors dépôt, voir la mémoire du projet). Ce fichier suit l'**avancement** côté iOS.

## Cible
Parité avec l'app Android v1 : 24 routes, 61 endpoints, 537 chaînes + 5 pluriels × 3 langues, 206 tests.
Fluide, rendu iOS 26/27 (Liquid Glass via les composants natifs) et compatible iOS 16 (iPhone 8 / X et plus).

## Mode d'exécution (2026-10-03)
**Autonome jusqu'au bout** : toutes les phases s'enchaînent dans la même session ; ce qui dépend du
propriétaire va dans `docs/EN-ATTENTE.md` et on continue. Règles et garde-fous : `docs/PROMPT-REPRISE.md`.

## Phases (une à la fois : fermée, testée, commitée ; galerie à la fin de chacune)
| # | Phase | Contenu | Compte Apple ? | État |
|---|---|---|---|---|
| 0 | Fondations | dépôt public, projet XcodeGen, CI `ios-ci` + `ios-screens`, tokens de design, W et icône 1024, icônes Lucide, chaînes converties (+ parité), coquille 5 onglets, lancement animé, socle d'API simulée | non | ✅ close le 2026-10-03 |
| 1 | Données et réseau | modèles, DTO tolérants, client HTTP, erreurs (~65 codes), session + trousseau + refresh, hors ligne, images, formats (DA, dates, chiffres latins), validations, pagination, suggestions, règles d’offre, protocole Phoenix — tests portés d’Android | non | ✅ close le 2026-10-03 |
| 2 | Parcourir | accueil Leboncoin, annonces (recherche, suggestions, historique, filtres + facettes), détail (galerie + zoom, attributs, vendeur, conseils, similaires, partage), profil vendeur, pages légales | non | ✅ close le 2026-10-03 |
| 3 | Compte et connexion + lot serveur A | e-mail, inscription, mot de passe oublié, code e-mail, Apple, Google, profil, mes annonces, mes données (export, suppression), réglages, contact | Apple sign-in | ✅ close le 2026-10-03 (Apple / Google : test sur iPhone en attente) |
| 4 | Déposer une annonce | assistant 6 étapes, attributs dynamiques, photos (galerie + appareil → JPEG 1600 px), envoi photo par photo, brouillon, modifier / vendu / renouveler / supprimer | non | ✅ close le 2026-10-04 |
| 5 | Messagerie et notifications + lot serveur B | conversations, fil, offres, archives, « écrit… », blocage + bloqués, signalement, temps réel, cloche et pastilles, push (Firebase), liens universels | push, liens | ✅ close le 2026-10-04 (push et liens : test sur iPhone en attente) |
| 6 | Favoris, alertes, avis, finition | favoris, alertes (max 5), avis ; VoiceOver, très grand texte, RTL, sombre, Réduire les animations, fluidité, passage iOS 16, touches Liquid Glass | non | ✅ close le 2026-10-04 |
| 7 | App Store + lot serveur C | TestFlight final, manifeste de confidentialité, étiquettes App Privacy, âge, textes fr/ar/en, captures 6,9", compte de démo, test final, soumission | oui | ✅ préparée le 2026-10-04 (TestFlight, test final et soumission : compte Apple) |
| 8 | Finition « à la Apple » (lots 1 et 2) | fiche (barre au défilement, actions sur une rangée), transition zoom, onglet touché deux fois, grands titres, bannières + Annuler, feuilles d'actions, haptique, feuilles protégées, appuis longs, raccourcis de l'icône, notifications à actions, note App Store, partage avec photo | non | ⏳ préparée le 2026-10-04 (feu vert donné ; à exécuter) |

Jalons TestFlight sur l'iPhone du propriétaire : fin de phase 2, fin de phase 5, test final.

## Chaîne CI (Mac gratuits de GitHub, dépôt public)
| Workflow | Quand | Ce qu'il fait |
|---|---|---|
| `ios-ci` | chaque push | parité du catalogue, génération XcodeGen, compilation simulateur, tests unitaires |
| `ios-screens` | fin de phase, à la demande | tour en API simulée → captures fr/ar/en × clair/sombre × iPhone 17 Pro Max (6,9") + iPhone 17e, vidéo |
| `ios-compat` | à la demande (phase 6) | Xcode 26 + simulateur iOS 16.4 téléchargé → tour rapide sur petit iPhone |
| `ios-release` | manuel, compte Apple actif (phase 3+) | archive signée « cloud » (clé API) → TestFlight → symboles |

Runner `macos-26` (image du 2026-09-07) : Xcode 26.6 par défaut, simulateurs iOS 26.2 / 26.4 / 26.5 ;
iPhone 17 Pro Max partout, iPhone 16e seulement en 26.2 → la petite taille est l'**iPhone 17e** (6,1").
XcodeGen n'est pas préinstallé : version épinglée téléchargée depuis sa release officielle, mise en cache.

## Phase 0 — détail
- [x] Dépôt public `aniis934/weydaa-ios`, e-mail git masqué, LICENSE « tous droits réservés », notices Lucide,
      analyse des secrets + protection au push activées
- [x] `.gitignore` (secrets Apple/Google, .xcodeproj généré, DerivedData), `CLAUDE.md`, `docs/`
- [x] `project.yml` (XcodeGen) : app + tests unitaires + tests d'interface, Swift 6, iOS 16, MainActor par défaut
- [x] Tokens de design portés d'Android (couleurs clair/sombre, palette, espacements, tailles, rayons, durées,
      courbes, échelle typographique Dynamic Type)
- [x] Le W (tracé unique), W extrudé, tuile, indicateur d'attente, mot « Weydaa »
- [x] Icône 1024 (claire, sombre, teintée) + W de l'écran de démarrage, rendus par script sans dépendance
- [x] 16 icônes Lucide (15 catégories + épingle) en SVG vectoriels teintables
- [x] 542 clés (537 chaînes + 5 pluriels) × fr/ar/en → `Localizable.xcstrings` + `L10n.swift`, garde-fou en CI
- [x] Coquille 5 onglets (barre native), écrans provisoires, lancement animé (même chorégraphie qu'Android)
- [x] Socle d'API simulée (Debug) + écran de démonstration du design (Debug)
- [x] Tests : parité des chaînes, pluriels arabes (6 formes), chiffres latins, W, courbes, icônes, config, API simulée
- [x] Workflows `ios-ci` et `ios-screens` écrits
- [x] Workflows poussés, `ios-ci` vert : 17 tests sur 17, 0 avertissement de compilation, ≈ 4 min (2026-10-02)
- [x] `ios-screens` vert (26 min) : 132 captures (fr/ar/en × clair/sombre × 17 Pro Max + 17e) et 2 vidéos relues —
      RTL inversé correctement, pluriel arabe « إعلانان », « 12 500 دج », barre Liquid Glass, rien ne déborde
- [x] Clôture : PR `phase-0` → `main`, checkpoint

## Phase 1 — détail (close le 2026-10-03, PR #2)
Travail en équipe d'agents parallèles (contrats d'interface fixés d'avance, notes partagées), intégré et commité par
l'orchestrateur ; une CI par lot, pas par fichier.
- [x] API simulée v2 : routes à jokers (`*`, `**`), contraintes de requête, la plus précise gagne, fichiers
      `routes-*.json` par domaine ; photos fictives dessinées en Core Graphics (pleine taille + `_thumb`)
- [x] `ios-screens` parallèle : une compilation, puis un tour par appareil × langue ; préchauffage du simulateur
      (l'attente ne touche que le tour FILMÉ de chaque appareil : due à l'enregistrement vidéo, pas au simulateur
      neuf — le préchauffage n'y change rien ; sans gravité, un seul tour par appareil est filmé)
- [x] `ios-ci` : lancement manuel `live` (passage en lecture seule contre la vraie API)
- [x] Vague 1 — modèles, DTO tolérants, mappers ; client HTTP, APIError, ErrorMapper (73 codes) ; session +
      trousseau + refresh unique ; connectivité ; formats, validations, pagination, offres, liens profonds ;
      préparation des photos ; historique ; pipeline d'images + `RemoteImage` — **CI verte du premier coup :
      170 tests, 0 avertissement** ; tests unitaires désormais signés ad hoc (`CODE_SIGN_IDENTITY=-`) : les 4 tests du
      trousseau, sautés sans signature, tournent (170/170)
- [x] Vague 2 — `WeydaAPI` (66 routes) + `LiveWeydaAPI`, 16 repositories, AppContainer (effets de session, canal
      temps réel personnel, scène premier plan / arrière-plan), données simulées du catalogue, tests des repositories
      (fausse API qui enregistre les appels), `LiveAPITests`, démo Debug des données (`-WeydaScreen data`)
- [x] Vague 2 — temps réel (parseur Phoenix pur + client WebSocket à transport injectable), moteur de suggestions
- [x] CI : 271 tests, 0 échec, 0 avertissement (une seule correction : isolation de la fausse API des tests)
- [x] Passage contre la VRAIE API en lecture seule (`ios-ci` manuel, live = true) : catégories, wilayas, annonces,
      fiche par id et par slug, attributs, suggestions, tendances, vendeur, avis — tout se décode, 0 échec
- [x] Tour de captures (144 captures, 6 tours en parallèle) et galerie privée :
      https://claude.ai/artifact/WxiTw2n3mHKn5LP1Hcd6x8 — clôture : PR #2 `phase-1` → `main`

## Phase 2 — détail (close le 2026-10-03, PR #3)
Équipe : SHELL (navigation, composants), puis HOME, LISTINGS, DETAIL en parallèle sur des contrats fixés
(`docs/equipe/CONTRACTS-P2.md`) ; données simulées partagées (30 annonces `mock-a1…a30`, 6 vendeurs) réconciliées
par simulation du routeur (52/52 requêtes justes).
- [x] Navigation : une pile par onglet (`AppRouter`), liens profonds, `-WeydaRoute` pour ouvrir un écran au lancement
- [x] Composants communs (cartes, ligne, puces, états, squelettes, étoiles, champ de recherche, hors ligne)
- [x] Accueil (sections en parallèle, feuille des catégories avec recherche fr/ar/en sans accents)
- [x] Annonces : recherche, suggestions + historique, « vouliez-vous dire », filtres + facettes, pagination, alerte
- [x] Fiche : galerie et zoom plein écran, caractéristiques traduites, vendeur, avis, similaires, partage,
      signalement ; profil vendeur (vitrine, avis, signaler, bloquer) ; À propos et pages légales
- [x] Données simulées : attributs du catalogue en arabe et en anglais (générés par le code du site), joker de
      requête `*` dans l'API simulée
- [x] CI : 356 tests, 0 échec, 0 avertissement — compilé du premier coup (une seule correction : un test qui
      attendait 24 annonces au lieu de 30)
- [x] 612 captures relues (fr/ar/en × clair/sombre × 17 Pro Max + 17e) ; corrigé à la relecture : milliers
      visibles en français (« 3 150 000 DA »), barre d'onglets masquée sur la fiche, libellés de contact entiers sur 17e
- [x] Galerie privée : https://claude.ai/artifact/MtwYSCciJ8Aky6wpfA9GQa

## Phase 3 — détail (close le 2026-10-03, PR #4)
Équipe : AUTH et ACCOUNT en parallèle sur des interfaces fixées (`docs/equipe/CONTRACTS-P3.md` : `AuthEntry`,
`requestLogin`, `requestEmailVerification`, `ProfileView`, session simulée `-WeydaLoggedIn`, utilisateur fictif `mock-me`).
- [x] Feuille de connexion (`AuthFlowView`, pile propre) : se ferme d'elle-même une fois connecté ; e-mail non vérifié →
      étape du code dans la même feuille ; l'écran d'origine reste dessous (l'action se refait d'un appui)
- [x] Connexion, inscription, mot de passe oublié, nouveau mot de passe (lien `/auth/reinitialiser-mdp?token=…`), code
      e-mail (compte à rebours de renvoi, essais restants) ; bandeau « e-mail à vérifier » (`VerifyEmailBanner`)
- [x] Sign in with Apple (nonce aléatoire, SHA-256) — échoue proprement tant que la capacité n'est pas posée (compte
      Apple) ; Google sans SDK (`ASWebAuthenticationSession` + PKCE), bouton masqué sans identifiant client iOS
- [x] Codes d'erreur Apple du lot A traduits (4 clés) ; les 3 phrases qui parlaient d'Android remplacées
- [x] Profil visiteur / membre (statistiques, badges, menu), modifier le profil, mot de passe, mes annonces (statuts,
      motifs de modération, ouverture de la fiche ; actions = phase 4), mes données (export JSON partagé, suppression
      par mot de passe, Google ou Apple selon `providers`), nous contacter, langue → Réglages de l'app
- [x] Données simulées `routes-auth.json` + `routes-account.json` (dont les fiches `mock-m1…m6` de « Mes annonces »)
- [x] CI : 434 tests, 0 échec, 0 avertissement — compilé du premier coup
- [x] Tours de captures verts (5x connexion, 6x compte : 22 écrans × fr/ar/en × clair/sombre × 17 Pro Max + 17e) ;
      ≈ 220 captures de la phase 3 relues en planches, plus une vérification des écrans de la phase 2 (aucune régression)
- [x] Corrigé à la relecture : puces de « Mes annonces » invisibles sur iOS 26 (voir constats) ; tour en français
      (dernière puce hors écran → glissement de la rangée avant l'appui)
- [x] Galerie privée : https://claude.ai/artifact/RatHcgEgHZHGEzGQhp7VgL — clôture : PR #4 `phase-3` → `main`
- [ ] Test sur iPhone de la connexion Apple / Google : attend le compte Apple, les clés et le lot serveur A (EN-ATTENTE)

## Phase 4 — détail (close le 2026-10-04, PR #5)
Équipe : WIZARD (logique + tests), SCREENS (écrans + tour 7x), MEDIA (photos + « Mes annonces », tour 8x) en parallèle sur des
interfaces fixées (`docs/equipe/CONTRACTS-P4.md` : `PostListingState`, `PostListingViewModel`, `PostDraftStore`, `PostPhotoStore`,
`postGalleryPicker` / `postCameraPicker` / `LocalPhotoThumbnail`, brouillons simulés `-WeydaPostDraft`).
- [x] Assistant 6 étapes (catégorie, caractéristiques si la catégorie en a, infos et prix, photos, localisation, vérification) :
      portage de `PostListingViewModel` (validation par étape, selects dépendants, retour sur l'étape fautive selon l'erreur serveur)
- [x] Brouillon sur disque (`Application Support/PostDrafts`, exclu des sauvegardes, propriétaire, effacé à la déconnexion
      volontaire) ; édition : brouillon en mémoire ; photos locales nommées par SHA-256 (une photo choisie deux fois = une)
- [x] Photos : galerie (`PhotosPicker`, sans permission), appareil photo (`UIImagePickerController`, `NSCameraUsageDescription`
      fr/ar/en ; bouton masqué sans caméra), envoi séquentiel (JPEG 1600 px), échec + réessayer, photo principale
- [x] Modifier une annonce (route `editListing`, depuis la fiche ou « Mes annonces ») : ouverture sur le récapitulatif, retour
      au récapitulatif puis confirmation d'abandon ; boutons de « Mes annonces » (modifier, vendu, renouveler, supprimer)
- [x] Données simulées : `routes-post.json`, `routes-mylistings.json`, 8 brouillons ; attributs de « Voitures » filtrés comme le
      serveur (`showFor` / `hideFor`)
- [x] CI : 475 tests (472 + 3 sautés en dehors du mode `live`), 0 échec, 0 avertissement — compilé du premier coup
- [x] ≈ 340 captures de la phase 4 relues (fr/ar/en × clair/sombre × 17 Pro Max + 17e) + vidéo ; aucune régression des phases 2-3
- [x] Corrigé à la relecture : l'année groupée comme un prix dans le récapitulatif (« 2 019 ») — milliers à partir de 10 000
- [x] Galerie privée : https://claude.ai/artifact/TcxYfo9YzeUPup9hiYkeAt — clôture : PR #5 `phase-4` → `main`
- [ ] Sur iPhone : appareil photo et sélecteur de photos réels ; première vraie publication avec un compte de test (EN-ATTENTE)

## Phase 5 — détail (close le 2026-10-04, PR #6)
Équipe : CHAT (fil, offres, contact depuis la fiche), INBOX (conversations, notifications, bloqués), PUSH (Firebase, notifications système,
liens universels, CI) en parallèle sur des interfaces fixées (`docs/equipe/CONTRACTS-P5.md` : `ChatView`, `OfferAmountSheet`,
`ContactSellerSheet`, `ConversationsView`, `NotificationsView`, `BlockedUsersView`, `PushRegistrar`) ; pré-travail de l'orchestrateur (route et
écran des bloqués, `GET /api/users/me/blocked` du lot B, plateforme « ios » du jeton, pastille de l'onglet Messages).
- [x] Fil de discussion : bulles, séparateurs de jour (jamais « Demain » : une date future vaut aujourd'hui), cartes d'offre (accepter / contre-offre
      / refuser sur l'offre OUVERTE seulement ; « en attente » seulement sur elle — défaut corrigé, présent aussi sur Android), suppression dans
      les 5 min (appui long, VoiceOver), anciens messages en remontant, temps réel + « écrit… » + présence, archiver, bloquer / débloquer, signaler
- [x] Contact et offre depuis la fiche (feuilles natives, 409 → conversation existante) : fin du repli « s'ouvre dans le navigateur »
- [x] Conversations / Archives (recherche, glisser pour archiver, pagination par curseur), aperçu masqué des utilisateurs bloqués (App Store 1.2),
      notifications (cible ouverte, tout lu, glisser pour supprimer, temps réel), écran « Utilisateurs bloqués » (Profil), pastille de l'onglet
- [x] Push : Firebase 12.19.2 exact (Messaging + Crashlytics), inerte sans `GoogleService-Info.plist` (CI, captures) ; autorisation demandée à la
      première ouverture de Messages ; bannière masquée pour le fil à l'écran ; appui → écran visé (rejoué si l'interface n'est pas prête) ;
      pastille de l'icône = notifications non lues ; jeton FCM détruit à la fermeture de session
- [x] Liens universels (`onContinueUserActivity`) : tous les chemins de l'AASA du lot A testés (apex, www, 3 langues) ; entitlements en Release
- [x] CI : paquets SPM en cache ; `ios-screens` : limite à 100 min, entrées `tests` (classes du tour) et `content_size` (Dynamic Type)
- [x] CI : 577 tests, 0 échec ; 9 avertissements attendus (6 `@_implementationOnly` des imports Firebase, 3 dépréciations Firebase dont le
      remplaçant — l'identifiant d'installation — ne convient pas au serveur, qui stocke des jetons FCM) ; compilé vert du premier coup
- [x] ≈ 250 captures de la phase relues (fr/ar/en × clair/sombre × 17 Pro Max + 17e) + vidéo ; pas de régression des phases 2-4
- [x] Corrigé à la relecture : offres « en attente » dépassées, séparateur « Demain » (horloge de la CI), boutons d'offre tronqués en arabe, titre
      « Notific… » (bouton icône), en-tête du fil illisible sur iOS 26 quand une bulle verte passe sous la barre (fond opaque)
- [x] Galerie privée : https://claude.ai/artifact/CKkeRRCK9gWiXELJUhj2wp — clôture : PR #6 `phase-5` → `main`
- [ ] Sur iPhone : push (app fermée, au premier plan, appui), lien weydaa.com ouvert depuis Notes ; attend compte Apple, clé APNs, Firebase iOS,
      lots A et B déployés (EN-ATTENTE)

## Phase 6 — détail (close le 2026-10-04, PR #7)
Branche `prep/release` fusionnée (workflows `ios-release` / `ios-compat`, `docs/store/`) et adaptée à Firebase (paquets SPM, envoi des dSYM
à Crashlytics par `upload-symbols`). Deux lots, quatre agents (`docs/equipe/CONTRACTS-P6.md`).
- [x] Lot 1 — LISTS : « Mes favoris » (retrait optimiste, suivi des cœurs retirés ailleurs, e-mail à vérifier) et « Mes alertes » (critères
      lisibles en puces, compteur n / 5, ouverture dans l'onglet Annonces filtré, suppression confirmée) ; REVIEWS : « Laisser un avis » /
      « Modifier mon avis » sur le profil vendeur (éligibilité, 5 étoiles réglables sous VoiceOver, commentaire avec compteur)
- [x] `ios-compat` : compilation, tests et tour complet VERTS sur iOS 16.4 (iPhone SE 3e génération, Xcode 26.6, Firebase compris)
- [x] Tour en très grand texte (taille d'accessibilité AX3, 17e, ar + fr) relu → lot 2
- [x] Lot 2 — LAYOUT : aux tailles d'accessibilité, plus aucun prix ni libellé utile tronqué (rangées d'annonce empilées, prix jamais
      coupés, actions empilées, statistiques sur 2 colonnes, grille du dépôt sans mot arabe coupé, en-têtes empilés) ; rendu inchangé aux
      tailles normales ; A11Y : bandeau hors ligne au-dessus du contenu (il passait sous la barre d'iOS 26), `-WeydaForceOffline`, badge
      « À la une » lu par VoiceOver, retours haptiques (message, offre, favori), composeur du fil en capsule Liquid Glass (iOS 26)
- [x] « Réduire les animations » : déjà respecté partout (audit) ; VoiceOver : un seul défaut trouvé et corrigé
- [x] CI : 608 tests, 0 échec, verts du premier coup (lots 1 et 2)
- [x] Captures relues : tour complet fr + ar × clair/sombre × 17 Pro Max + 17e, très grand texte fr + ar, iOS 16.4 ; galerie https://claude.ai/artifact/V4Z54sFRSCpsBZYqLBrQMo
- [ ] Sur iPhone : fluidité, haptique, Liquid Glass réel (TestFlight)

## Phase 7 — détail (préparée le 2026-10-04, PR #8)
Deux agents (`docs/equipe/CONTRACTS-P7.md`) ; tout ce qui demande le compte Apple attend le propriétaire (`docs/EN-ATTENTE.md`, section
« Ordre de traitement »).
- [x] Captures de la fiche : mode vitrine Debug (`-WeydaStoreCaption 1…8` : légende de marque composée par l'app, l'app réduite dans un
      cadre), tour `StoreShotsTests` → 24 captures 1320 × 2868 (8 écrans × fr/ar/en, l'écran 8 en sombre), relues, en JPEG sans alpha dans
      `docs/store/captures/<langue>/` ; aucune autre plateforme mobile visible (règle 2.3.10)
- [x] Manifeste `Weyda/Resources/PrivacyInfo.xcprivacy` embarqué (aucun suivi ; UserDefaults `CA92.1`, dates de fichiers `C617.1` ;
      15 types de données) + `PrivacyManifestTests` ; brouillon de `docs/store/` retiré
- [x] App Privacy, fiches fr/ar/en (limites d'Apple comptées par script), notes de revue fr/en (chemins exacts, délai de 24 h des CGU du
      lot B), âge, check-list de soumission, `RELEASE.md` (Firebase, dSYM, entitlements, capacités de l'App ID)
- [x] `ios-release` : identifiant client Google iOS transmis au build (secret `GOOGLE_IOS_CLIENT_ID` ; sans lui, le bouton Google était
      masqué dans TestFlight) ; dSYM envoyés à Crashlytics
- [x] CI : 612 tests, 0 échec, vert du premier coup ; galerie https://claude.ai/artifact/B9meNggA7FGCi6JyV1ee5G
- [ ] TestFlight, test final guidé (~30 min) sur iPhone, soumission : compte Apple Developer et secrets (EN-ATTENTE, étapes B à D)

## Galeries des phases 5 à 7 (2026-10-04)
Phase 5 (messagerie, notifications) https://claude.ai/artifact/CKkeRRCK9gWiXELJUhj2wp · phase 6 (favoris, alertes, avis, finition) https://claude.ai/artifact/V4Z54sFRSCpsBZYqLBrQMo · phase 7 (fiche App Store) https://claude.ai/artifact/B9meNggA7FGCi6JyV1ee5G.

## Phase 8 — finition « à la Apple » (préparée le 2026-10-04, à exécuter)
Feu vert du propriétaire le 2026-10-04 pour les lots 1 et 2 de l'audit « app parfaite à la Apple » ; exécution à la session suivante.
Contrat complet (prétravail, 2 vagues d'agents, règles par point, chaînes fr/ar/en, captures) : `docs/equipe/CONTRACTS-P8.md`.
- [ ] Prétravail de l'orchestrateur (une CI) : chaînes, `WeydaBanner`, haptique `error`/`warning`, signal « haut de page », zoom
      (`AppRoute.detail(…, zoomSource:)`, espaces de noms), `listingContextMenu`, `Listing.sellerId`, `SellerLinks`, `ReviewPrompter`,
      `ShortcutAction` + `-WeydaShortcut`
- [ ] Vague 1 (DETAIL, BROWSE, ACCOUNT) puis vague 2 (INBOX, SYSTEM), une CI par vague
- [ ] Lot 1 : fiche (barre au défilement + titre, actions sur une rangée), zoom carte → fiche (iOS 18), onglet touché deux fois = haut
      de page, grands titres (Messages, Favoris, Alertes, Mes annonces), bannières iOS + « Annuler », feuilles d'actions, haptique,
      Filtres et connexion protégés contre la fermeture par glissement
- [ ] Lot 2 : appuis longs (annonces, conversations, Mes annonces), raccourcis de l'icône, notifications à actions (répondre,
      accepter / refuser ; `aps.category` à ajouter à la PR B avec l'accord du propriétaire), note App Store, partage avec photo,
      partage du profil vendeur
- [ ] Captures relues (fr/ar/en, clair/sombre, 2 iPhone, très grand texte), galerie, PR fusionnée
- Écarts décidés à la préparation : pas de « lu / non lu » (aucune route serveur), menu d'appui long au lieu des glissements dans
  « Mes annonces », photo dans la notification après le premier TestFlight, pastille de l'icône inchangée (compteur du serveur).

## Après la phase 7 — illustrations des catégories (2026-10-04, PR #9)
Demande du propriétaire : les icônes de catégorie de l'app = les illustrations 3D en couleur du site.
- [x] `Assets.xcassets/CategoryArt` : les 14 illustrations de `public/categories` (site) en PNG sans perte @2x/@3x d'une
      tuile de 64 pt (562 Ko) ; `scripts/convert-category-art.mjs` (efface au passage la jointure d'aplat des images du
      site : carré visible, sujets coupés net) ; test : chaque slug a son illustration, à 64 pt
- [x] `CategoryArtwork` (tuile arrondie ou disque, liseré d'un demi-point, tuile « Toutes ») : accueil (64 pt), feuille
      des catégories (40 pt), dépôt (56 pt, choisie = anneau + coche), puces des annonces (disque 24 → 40 pt avec le
      texte), pastille de la fiche ; pictogrammes Lucide gardés pour les petits repères (critères d'alerte)
- [x] 24 captures de la fiche App Store refaites (`docs/store/captures/`) ; CI 613 tests, 0 échec ; captures relues
      (fr/ar/en, clair/sombre, 2 iPhone, très grand texte) ; galerie https://claude.ai/artifact/QWV68gKW4YJLK9B5M7mA2i

## Constats de la CI (phase 6)
- Firebase + 4 agents : tous les lots compilés verts du premier coup ; `ios-compat` (iOS 16.4) vert sans correction.
- Très grand texte : les dispositions en ligne (prix à côté d'une vignette, 3-4 boutons côte à côte, titre + « Voir tout ») cassent aux
  tailles d'accessibilité ; règle retenue : `dynamicTypeSize.isAccessibilitySize` → disposition empilée, un prix ne se tronque jamais.
- `workflow_dispatch` d'`ios-compat` accepté depuis une branche avant même la fusion dans `main` (le workflow existait déjà sur une branche).

## Constats de la CI (phase 5)
- Équipe de 3 agents : ≈ 11 700 lignes, compilées et testées vertes du premier coup, Firebase compris (≈ 10 min de CI avec le cache).
- iOS 26 : la barre de navigation Liquid Glass s'ADAPTE au contenu qui défile dessous (bulle verte → barre d'état et titre en blanc) ;
  un en-tête qui doit rester lisible (fil de discussion) prend un fond opaque. À vérifier sur les autres écrans en phase 6.
- Tour complet > 45 min par langue depuis la messagerie : relectures ciblées par classes (`-f tests="TourChatTests TourInboxTests"`).
- Les captures prises par le simulateur de la CI suivent son horloge (UTC, la veille au soir) : données simulées datées du jour → « futur ».

## Constats de la CI (phase 4)
- Équipe de 3 agents : ≈ 6 200 lignes, compilées et testées vertes du premier coup (contrats fixés d'avance + relecture
  « compilateur » par chaque agent ; les risques signalés par les agents ont été relus par l'orchestrateur avant l'envoi).
- Le tour ne peut pas piloter le sélecteur de photos (hors processus) ni l'appareil photo (absent du simulateur) : les étapes
  remplies viennent de brouillons simulés (`-WeydaPostDraft <nom>`, écrits dans un dossier temporaire vidé à chaque lancement).
- `ios-screens` : un tour peut attendre un Mac libre plus de 25 min quand les 5 Mac gratuits sont pris (CI + autres tours).

## Constats de la CI (phase 3)
- Équipe AUTH + ACCOUNT : ≈ 8 700 lignes, compilées et testées vertes du premier coup (434 tests, 0 avertissement).
- iOS 26 : ce qu'on pose dans `.safeAreaInset(edge: .top)` d'une vue défilante passe SOUS l'effet de bord de la barre de
  navigation (fondu vers le fond) — les puces de « Mes annonces » étaient invisibles. Barres fixes du haut : pile
  verticale au-dessus de la vue défilante (ou `safeAreaBar`, iOS 26). **Phase 6** : vérifier `OfflineBanner` (même
  encart sur la fiche et les écrans du compte) en mode avion sur iOS 26.
- Tour (XCUITest) : demander `isHittable` sur un élément hors écran ÉCHOUE (« Activation point invalid ») au lieu de
  répondre faux ; `app.scrollViews.containing(…)` renvoie d'abord un conteneur parent, qu'un glissement ne fait pas
  défiler. Pour atteindre un élément d'une rangée horizontale : glisser par coordonnées à la hauteur de la rangée.
- Faux défaut évité : dans une phrase arabe, le point qui suit une adresse e-mail s'affiche À GAUCHE de l'adresse
  (« .yacine… ») — c'est la lecture correcte de droite à gauche ; l'isolement de l'adresse (U+2066/U+2069) reste une précaution.
- `ios-screens` : un Mac sans le simulateur demandé fait échouer la compilation (« Unable to find a device ») — relancer.

## Constats de la CI (phase 2)
- Le tour filmé saute des passages entiers (l'enregistreur du simulateur perd des images quand le Mac est chargé) :
  les captures font foi, la vidéo sert d'aperçu.
- Un délai « Timed out while requesting screenshot » peut faire échouer un tour sans défaut de l'app : relancer
  le seul tour en échec (`gh run rerun <id> --failed`).
- Contact et offre d'un membre connecté : alerte « s'ouvre dans le navigateur » vers la fiche du site en attendant
  la messagerie (phase 5) — invisible tant que la connexion (phase 3) n'existe pas.

## À vérifier sur un vrai iPhone (premier TestFlight, fin de phase 2)
- Démarrage : sur le simulateur de CI (build Debug lancé par XCUITest), le W fantôme reste ≈ 2 s avant le tracé
  (démarrage à froid du simulateur). Sur appareil, en Release, il doit s'enchaîner sans attente visible.

## Constats de la CI (phase 0)
- Compilé sans erreur ni avertissement du premier coup grâce aux conventions de `CLAUDE.md`.
- `String(format:locale:)` groupe les milliers selon la locale (« 1.234 » en ar_DZ, « 1 234 » en fr) : les
  compteurs du catalogue (`%lld`) s'affichent groupés, en chiffres latins. Voulu, et testé.
- Durées : `ios-ci` 4 à 8 min (13 min avec file d'attente des Mac) ; `ios-screens` ≈ 26 min.

## Constats de la CI (phase 1)
- Code écrit par 3 agents en parallèle sur des contrats fixés d'avance : vague 1 verte du premier coup, vague 2 à une
  correction près (piège : une classe MainActor conforme à un protocole `nonisolated` → ses méthodes témoins sont
  nonisolated ; consigné dans les contrats d'équipe).
- `ios-screens` parallèle : ≈ 8 min par tour (dont ≈ 5 min de démarrage simulateur + xcodebuild), ≈ 25 min de bout en
  bout quand les 5 Mac gratuits sont partagés avec d'autres lancements.
- Tests unitaires signés ad hoc : sinon le trousseau du simulateur refuse l'accès (tests sautés).

## Décisions techniques (iOS)
- Pluriels : variations du catalogue `.xcstrings` (résolues par le système, six formes de l'arabe).
- Nom affiché localisé via `*.lproj/InfoPlist.strings` (« ويدا » en arabe, comme Android), ce qui déclare
  aussi les trois langues au projet.
- Icône : appiconset « une taille » 1024 + variantes sombre et teintée (iOS 18+) ; Liquid Glass dérive le reste.
- Tuile-logo à la courbe de l'icône iOS (22,37 %, continue), W à 0,56 du côté, comme `WeydaTile` Android.
- Cible tactile 44 pt (HIG Apple) au lieu de 48 dp.
- Tests unitaires en XCTest (compatibles avec le simulateur iOS 16 de `ios-compat`).
