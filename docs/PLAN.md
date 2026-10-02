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
| 1 | Données et réseau | modèles, DTO tolérants, client HTTP, erreurs (~65 codes), session + trousseau + refresh, hors ligne, images, formats (DA, dates, chiffres latins), validations, pagination, suggestions, règles d'offre, protocole Phoenix — tests portés d'Android | non | ⏳ |
| 2 | Parcourir | accueil Leboncoin, annonces (recherche, suggestions, historique, filtres + facettes), détail (galerie + zoom, attributs, vendeur, conseils, similaires, partage), profil vendeur, pages légales | non | ⏳ |
| 3 | Compte et connexion + lot serveur A | e-mail, inscription, mot de passe oublié, code e-mail, Apple, Google, profil, mes annonces, mes données (export, suppression), réglages, contact | Apple sign-in | ⏳ |
| 4 | Déposer une annonce | assistant 6 étapes, attributs dynamiques, photos (galerie + appareil → JPEG 1600 px), envoi photo par photo, brouillon, modifier / vendu / renouveler / supprimer | non | ⏳ |
| 5 | Messagerie et notifications + lot serveur B | conversations, fil, offres, archives, « écrit… », blocage + bloqués, signalement, temps réel, cloche et pastilles, push (Firebase), liens universels | push, liens | ⏳ |
| 6 | Favoris, alertes, avis, finition | favoris, alertes (max 5), avis ; VoiceOver, très grand texte, RTL, sombre, Réduire les animations, fluidité, passage iOS 16, touches Liquid Glass | non | ⏳ |
| 7 | App Store + lot serveur C | TestFlight final, manifeste de confidentialité, étiquettes App Privacy, âge, textes fr/ar/en, captures 6,9", compte de démo, test final, soumission | oui | ⏳ |

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

## À vérifier sur un vrai iPhone (premier TestFlight, fin de phase 2)
- Démarrage : sur le simulateur de CI (build Debug lancé par XCUITest), le W fantôme reste ≈ 2 s avant le tracé
  (démarrage à froid du simulateur). Sur appareil, en Release, il doit s'enchaîner sans attente visible.

## Constats de la CI (phase 0)
- Compilé sans erreur ni avertissement du premier coup grâce aux conventions de `CLAUDE.md`.
- `String(format:locale:)` groupe les milliers selon la locale (« 1.234 » en ar_DZ, « 1 234 » en fr) : les
  compteurs du catalogue (`%lld`) s'affichent groupés, en chiffres latins. Voulu, et testé.
- Durées : `ios-ci` 4 à 8 min (13 min avec file d'attente des Mac) ; `ios-screens` ≈ 26 min.

## Décisions techniques (iOS)
- Pluriels : variations du catalogue `.xcstrings` (résolues par le système, six formes de l'arabe).
- Nom affiché localisé via `*.lproj/InfoPlist.strings` (« ويدا » en arabe, comme Android), ce qui déclare
  aussi les trois langues au projet.
- Icône : appiconset « une taille » 1024 + variantes sombre et teintée (iOS 18+) ; Liquid Glass dérive le reste.
- Tuile-logo à la courbe de l'icône iOS (22,37 %, continue), W à 0,56 du côté, comme `WeydaTile` Android.
- Cible tactile 44 pt (HIG Apple) au lieu de 48 dp.
- Tests unitaires en XCTest (compatibles avec le simulateur iOS 16 de `ios-compat`).
