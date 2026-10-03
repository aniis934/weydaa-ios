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
- **2026-10-03 (nuit)** — **Phase 3 reprise** sur feu vert du propriétaire, qui demande un NOUVEL ARRÊT à la fin de la
  phase 3 (CI verte, PR fusionnée, galerie publiée → attendre son feu vert pour la phase 4). `main` fusionné dans
  `phase-3` (commit « wip » = le partiel) ; équipe AUTH + ACCOUNT relancée (notes et chaînes de l'équipe dans le
  dossier temporaire de la session : `ios-team/`). `git push` autorisé pour la session, dépôt iOS seulement.
- **2026-10-03 (soir)** — **Phase 2 close** (PR #3) : 356 tests verts, 612 captures relues, galerie
  https://claude.ai/artifact/MtwYSCciJ8Aky6wpfA9GQa. **ARRÊT DEMANDÉ PAR LE PROPRIÉTAIRE** à la fin de la phase 2
  pour vérifier : attendre son feu vert avant la phase 3.
- Phase 1 close (PR #2, galerie https://claude.ai/artifact/WxiTw2n3mHKn5LP1Hcd6x8). Lots serveur A/B/C prêts en PR
  non fusionnées (weyda2026 #5, #6, #7). Préparation App Store sur `prep/release` (worktree `../weydaa-ios-release`,
  `ios-compat` vert sur iOS 16.4) — à fusionner en phase 6.
- **Phase 3 commencée puis mise en pause** (à la demande d'arrêt) : worktree `../weydaa-ios-p3`, branche `phase-3`
  créée depuis la phase 2 AVANT ses écrans, travail partiel NON commité (connexion : `Weyda/Features/Auth`,
  `Weyda/Core/Auth`, composants de formulaire, branchements AppRouter/RootView/AppContainer/LaunchOptions/AppConfig ;
  compte : `Weyda/Features/Account` commencé). Contrat : `docs/equipe/CONTRACTS-P3.md` (interfaces AUTH ↔ ACCOUNT,
  utilisateur fictif `mock-me`, `-WeydaLoggedIn`). Reprise : fusionner `main` dans `phase-3`, relire le partiel, finir AUTH puis ACCOUNT.
- **Méthode : une équipe d'agents en parallèle** (demandée par le propriétaire). L'orchestrateur fixe les contrats
  d'interface AVANT le code (`docs/equipe/CONTRACTS*.md`, `SCREEN-BRIEF.md`), chaque agent écrit SES fichiers et une
  note d'API, l'orchestrateur intègre, commite et lance UNE CI par lot, relit TOUTES les captures en planches
  contact (ffmpeg) avant la galerie.
- **Envoi git** : `weydaa-site/.claude/settings.json` interdit `git push` (protection du site : un envoi sur
  `master` part en production). La session tourne depuis `weydaa-site` → la règle bloque aussi le dépôt iOS. Le
  propriétaire l'a levée pour la phase 2 puis elle a été rétablie : redemander à la prochaine phase (ou ouvrir la
  session depuis `weydaa-ios`).
- À faire en phase 3 : traduire les 4 codes d'erreur Apple du lot A (`invalidAppleToken`, `appleEmailMissing`,
  `appleReauthMismatch`, `appleSignInUnavailable`) ; remplacer les 3 chaînes qui parlent d'Android.

## Rappels
- Pas de Mac : chaque vérification passe par la CI (`gh run watch`, `gh run view --log-failed`).
- Captures : `gh workflow run ios-screens.yml --ref <branche>` puis `gh run download <id> -D <scratchpad>` (un
  artefact `ios-screens-<appareil>-<langue>` par tour ; vidéos ≈ 150 Mo : télécharger en arrière-plan).
- Les fichiers générés (`Localizable.xcstrings`, `L10n.swift`, icônes) se régénèrent sur le poste avec Node
  (`scripts/*.mjs`) : la CI n'a pas accès au dépôt privé.
