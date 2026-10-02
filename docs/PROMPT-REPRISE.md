# Prompt de reprise — Weyda iOS

À coller dans un nouveau chat (dossier `3-DEV/Weyda/weydaa-ios/` ou `weydaa-site/`) :

> Reprends l'app iOS Weyda. Lis `CLAUDE.md` et `docs/PLAN.md` du dépôt `weydaa-ios`, puis la note
> `ios-app-plan` de la mémoire du projet. Vérifie l'état réel : `git -C <weydaa-ios> status`,
> `git log --oneline -5`, `gh run list -R aniis934/weydaa-ios -L 5`. Puis continue la phase en cours
> (case non cochée de `docs/PLAN.md`), une phase à la fois, CI verte et captures relues avant de clore.

## Où on en est (mis à jour à chaque fin de session)
- **2026-10-03** — Phase 0 écrite en entier sur la branche `phase-0` (code, scripts, tests, workflows).
  Reste : pousser les workflows (le jeton gh doit avoir le scope `workflow` : `gh auth refresh -s workflow`),
  obtenir `ios-ci` vert (corriger les erreurs de compilation éventuelles), lancer `ios-screens`, relire
  captures + vidéo, puis PR `phase-0` → `main` et checkpoint.

## Rappels
- Pas de Mac : chaque vérification passe par la CI (`gh run watch`, `gh run view --log-failed`).
- Captures : `gh workflow run ios-screens.yml --ref phase-0` puis `gh run download <id> -n ios-screens -D <scratchpad>`.
- Les fichiers générés (`Localizable.xcstrings`, `L10n.swift`, icônes) se régénèrent sur le poste avec Node
  (`scripts/*.mjs`) : la CI n'a pas accès au dépôt privé.
