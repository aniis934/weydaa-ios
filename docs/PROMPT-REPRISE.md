# Prompt de reprise — Weyda iOS

À coller dans un nouveau chat (dossier `3-DEV/Weyda/weydaa-ios/` ou `weydaa-site/`) :

> Reprends l'app iOS Weyda. Lis `CLAUDE.md` et `docs/PLAN.md` du dépôt `weydaa-ios`, puis la note
> `ios-app-plan` de la mémoire du projet. Vérifie l'état réel : `git -C <weydaa-ios> status`,
> `git log --oneline -5`, `gh run list -R aniis934/weydaa-ios -L 5`. Puis continue la phase en cours
> (case non cochée de `docs/PLAN.md`), une phase à la fois, CI verte et captures relues avant de clore.

## Où on en est (mis à jour à chaque fin de session)
- **2026-10-03** — **Phase 0 close** (fusionnée dans `main`) : CI verte (17 tests), 132 captures et vidéos relues.
  **Prochaine : phase 1 — données et réseau** (branche `phase-1`). Porter d'Android, avec leurs tests JVM
  (`android/app/src/test/`) : modèles + DTO tolérants (`model/Models.kt`, `data/remote/dto/`), client HTTP et
  erreurs (`SafeCall.kt`, `ui/common/ErrorMapper.kt`), session + trousseau + refresh unique sous verrou
  (`data/session/SessionManager.kt`, `AuthInterceptor.kt`), réseau hors ligne, pipeline d'images, formats
  (`ui/common/Format`, prix DA, dates), validations, pagination (`ui/common/Paging.kt`), suggestions
  (`SuggestionsEngine.kt`), règles d'offre (`model/OfferRules.kt`), protocole Phoenix (`data/realtime/`).
  Contrat d'API : `android/docs/API-CONTRACT.md` (dépôt privé). Fixtures de l'API simulée : FICTIVES.

## Rappels
- Pas de Mac : chaque vérification passe par la CI (`gh run watch`, `gh run view --log-failed`).
- Captures : `gh workflow run ios-screens.yml --ref <branche>` puis `gh run download <id> -n ios-screens -D <scratchpad>`.
- Les fichiers générés (`Localizable.xcstrings`, `L10n.swift`, icônes) se régénèrent sur le poste avec Node
  (`scripts/*.mjs`) : la CI n'a pas accès au dépôt privé.
