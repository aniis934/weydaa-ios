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

## Où on en est (mis à jour à chaque fin de phase)
- **2026-10-03 (matin)** — **Phase 1 close** (PR #2) : 271 tests verts, passage en lecture seule contre la vraie API
  vert, galerie https://claude.ai/artifact/WxiTw2n3mHKn5LP1Hcd6x8. Lots serveur A/B/C prêts en PR non fusionnées
  (weyda2026 #5, #6, #7). Préparation App Store faite sur la branche `prep/release` (worktree `../weydaa-ios-release`,
  `ios-compat` vert sur iOS 16.4) — à fusionner en phase 6.
- **Phase 2 en cours** — branche `phase-2`, worktree `../weydaa-ios-p2` (créé par `git worktree add`). Socle fait et
  vert (navigation à une pile par onglet, composants communs, À propos, tour `TourTestCase`, 291 tests) ; écrans
  Accueil, Annonces, Détail + Vendeur en cours d'écriture (agents HOME, LISTINGS, DETAIL).
- **Méthode : une équipe d'agents en parallèle** (demandée par le propriétaire). L'orchestrateur fixe les contrats
  d'interface AVANT le code (`docs/equipe/CONTRACTS*.md`, `SCREEN-BRIEF.md` : règles, pièges Swift 6.2 constatés,
  noms et signatures imposés, propriété des fichiers), chaque agent écrit SES fichiers et une note d'API, l'orchestrateur
  intègre, commite et lance UNE CI par lot. Une phase suivante peut être PRÉPARÉE dans son worktree pendant que la
  précédente passe sa CI ; elle n'est fusionnée qu'après elle.
- Ordre conseillé pour contourner les blocages : 2 → 3 (e-mail d'abord ; Apple/Google prêts mais inactifs) → 4 → 5
  (push prêt mais inactif) → 6 (dont `ios-compat` iOS 16.4 + fusion de `prep/release`) → 7 (préparé).
- À faire en phase 3 : traduire les 4 codes d'erreur Apple du lot A (`invalidAppleToken`, `appleEmailMissing`,
  `appleReauthMismatch`, `appleSignInUnavailable` → `scripts/ios-strings.json` + `ErrorMapper`) ; remplacer les
  3 chaînes qui parlent d'Android (signalées par `convert-strings.mjs`).

## Rappels
- Pas de Mac : chaque vérification passe par la CI (`gh run watch`, `gh run view --log-failed`).
- Captures : `gh workflow run ios-screens.yml --ref <branche>` puis `gh run download <id> -n ios-screens -D <scratchpad>`.
- Les fichiers générés (`Localizable.xcstrings`, `L10n.swift`, icônes) se régénèrent sur le poste avec Node
  (`scripts/*.mjs`) : la CI n'a pas accès au dépôt privé.
