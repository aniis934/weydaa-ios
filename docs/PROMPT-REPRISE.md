# Prompt de reprise — Weyda iOS

À coller dans un nouveau chat (dossier `3-DEV/Weyda/weydaa-ios/` ou `weydaa-site/`) :

> Reprends l'app iOS Weyda. Lis `CLAUDE.md`, `docs/PLAN.md`, `docs/EN-ATTENTE.md` et ce fichier (mode
> d'exécution ci-dessous) du dépôt `weydaa-ios`, puis la note `ios-app-plan` de la mémoire du projet.
> Vérifie l'état réel : `git -C <weydaa-ios> status`, `git log --oneline -5`,
> `gh run list -R aniis934/weydaa-ios -L 5`. Puis continue en mode autonome jusqu'au bout.

## Mode d'exécution : AUTONOME jusqu'au bout (décision du propriétaire, 2026-10-03)
Enchaîner TOUTES les phases (1 → 7) dans la même session, sans attendre de validation. S'arrêter seulement
quand plus rien n'avance sans le propriétaire.
- **Blocage** (compte, clé, feu vert, décision, ou problème qui demande ses yeux) → une ligne dans
  `docs/EN-ATTENTE.md` (quoi, pourquoi, ce que ça débloque), puis passer à ce qui peut avancer : autre partie
  de la phase, phase suivante, ou préparation (code écrit et testé en API simulée, en attente d'activation).
- **Garde-fous non négociables** : une phase après l'autre (CI verte + PR fusionnée dans `main` avant la
  suivante) ; galerie privée de captures + vidéo publiée à chaque fin de phase, SANS attendre de réponse ;
  `docs/PLAN.md`, ce fichier et `EN-ATTENTE.md` à jour à chaque frontière de phase (une coupure ne perd rien) ;
  aucune écriture en prod, aucun déploiement serveur, aucun secret, aucune dépendance hors Firebase (accordé).
- **Lots serveur A/B/C** : préparés dans un `git worktree` créé depuis `origin/master` du dépôt privé (le
  dossier `weydaa-site`, sur `release/android-v1` avec des fichiers non commités, n'est JAMAIS touché), tests
  serveur verts, PR ouverte, **non fusionnée** → ligne « feu vert » dans `EN-ATTENTE.md`.
- **Phase 7** : tout préparer (manifeste de confidentialité, étiquettes App Privacy, textes fr/ar/en, captures
  6,9", notes de revue, workflow `ios-release`) ; signature, envoi TestFlight et soumission attendent le compte.
- **Fin du mandat** : toutes les phases au maximum de ce qui est faisable → rapport final = ce qui est fait +
  la liste `EN-ATTENTE.md` dans l'ordre où le propriétaire doit la traiter.

## Où on en est (mis à jour à chaque fin de session)
- **2026-10-03** — **Phase 0 close** (fusionnée dans `main`) : CI verte (17 tests), 132 captures et vidéos relues.
  **Prochaine : phase 1 — données et réseau** (branche `phase-1`). Porter d'Android, avec leurs tests JVM
  (`android/app/src/test/`) : modèles + DTO tolérants (`model/Models.kt`, `data/remote/dto/`), client HTTP et
  erreurs (`SafeCall.kt`, `ui/common/ErrorMapper.kt`), session + trousseau + refresh unique sous verrou
  (`data/session/SessionManager.kt`, `AuthInterceptor.kt`), réseau hors ligne, pipeline d'images, formats
  (`ui/common/Format`, prix DA, dates), validations, pagination (`ui/common/Paging.kt`), suggestions
  (`SuggestionsEngine.kt`), règles d'offre (`model/OfferRules.kt`), protocole Phoenix (`data/realtime/`).
  Contrat d'API : `android/docs/API-CONTRACT.md` (dépôt privé). Fixtures de l'API simulée : FICTIVES.
  À traiter au début de la phase 1 : le tour `ios-screens` reste ≈ 60 s sur l'onglet Accueil avant de taper
  les autres (attente de l'outil de test, à diagnostiquer) — le tour complet fait 26 min.
  Ordre conseillé pour contourner les blocages : 1 → 2 → 3 (e-mail d'abord ; Apple/Google prêts mais inactifs)
  → 4 → 5 (push prêt mais inactif) → 6 (dont `ios-compat` iOS 16.4) → 7 (préparé) ; lots serveur en PR non fusionnées.

## Rappels
- Pas de Mac : chaque vérification passe par la CI (`gh run watch`, `gh run view --log-failed`).
- Captures : `gh workflow run ios-screens.yml --ref <branche>` puis `gh run download <id> -n ios-screens -D <scratchpad>`.
- Les fichiers générés (`Localizable.xcstrings`, `L10n.swift`, icônes) se régénèrent sur le poste avec Node
  (`scripts/*.mjs`) : la CI n'a pas accès au dépôt privé.
