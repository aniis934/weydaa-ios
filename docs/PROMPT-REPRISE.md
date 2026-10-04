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
- **2026-10-04 (soir)** — Après la phase 7 : icônes de catégorie = illustrations 3D du site (PR #9, 613 tests, 24 captures App Store
  refaites, galerie https://claude.ai/artifact/QWV68gKW4YJLK9B5M7mA2i). Audit « app parfaite à la Apple » → **phase 8 (lots 1 et 2)
  PRÉPARÉE, feu vert du propriétaire donné, à exécuter à la prochaine session** : tout est dans `docs/equipe/CONTRACTS-P8.md`
  (prétravail de l'orchestrateur, puis 2 vagues d'agents, règles par point, chaînes, captures). Une seule phase : s'arrêter à sa fin
  avec la galerie. Message de lancement à coller :
  > /go weyda — phase 8 de l'app iOS (lots 1 et 2 de finition « à la Apple », feu vert du 04/10). Lis docs/equipe/CONTRACTS-P8.md. Autorisations pour la session : git push vers weydaa-ios (branche phase-8, PR, fusion dans main) ; mise à jour de la PR serveur B (weyda2026 #6) pour ajouter `aps.category`, SANS la fusionner. Arrête-toi à la fin de la phase 8 avec la galerie.
  Si le propriétaire lance la session sans ces autorisations : les lui demander d'abord (push iOS + mise à jour de la PR B).
- **2026-10-04 (fin de journée)** — **Phase 7 préparée** (PR #8) : captures de la fiche (24, fr/ar/en), manifeste de confidentialité,
  App Privacy, fiches, notes de revue, check-list, `ios-release` complet. **Toutes les phases de code sont faites (0 à 7, 612 tests).**
  ARRÊT demandé par le propriétaire à la fin de la phase 7 : la suite est à lui, dans l'ordre de `docs/EN-ATTENTE.md` (section « Ordre de
  traitement ») — compte Apple, secrets, lots serveur A/B/C, TestFlight, test final guidé, soumission. Galeries : phase 5 https://claude.ai/artifact/CKkeRRCK9gWiXELJUhj2wp,
  phase 6 https://claude.ai/artifact/V4Z54sFRSCpsBZYqLBrQMo, phase 7 https://claude.ai/artifact/B9meNggA7FGCi6JyV1ee5G. Prochaine session iOS = accompagner ces étapes (test final guidé sur iPhone, corrections, soumission).
- **2026-10-04** — **Phase 6 close** (PR #7) : favoris, alertes, avis ; finition (très grand texte, hors ligne sur iOS 26, VoiceOver,
  haptique, Liquid Glass du composeur) ; `prep/release` fusionnée ; iOS 16.4 vert. 608 tests verts, galerie https://claude.ai/artifact/V4Z54sFRSCpsBZYqLBrQMo. Suite : phase 7
  (préparation App Store) enchaînée sans arrêt.
- **2026-10-04** — **Phase 5 close** (PR #6) : messagerie (fil, offres, contact et offre depuis la fiche), conversations et archives,
  notifications, utilisateurs bloqués, push Firebase (inerte sans `GoogleService-Info.plist`), liens universels. 577 tests verts, galerie
  https://claude.ai/artifact/CKkeRRCK9gWiXELJUhj2wp. Feu vert reçu le 2026-10-04 pour enchaîner les phases 5, 6 et 7 SANS arrêt ; arrêt demandé à la fin de la phase 7 (3 liens de galerie
  + liste EN-ATTENTE dans l'ordre de traitement). PR serveur A/B/C rebasées sur `master` le 2026-10-04 (non fusionnées).
- **2026-10-04** — **Phase 4 close** (PR #5) : déposer une annonce (assistant 6 étapes, attributs dynamiques, photos galerie
  et appareil, envoi photo par photo, brouillon), modifier une annonce, boutons de « Mes annonces » (vendu, renouveler,
  supprimer). 475 tests verts, tours de captures verts, galerie https://claude.ai/artifact/TcxYfo9YzeUPup9hiYkeAt. **ARRÊT DEMANDÉ PAR LE PROPRIÉTAIRE** à la fin de
  chaque phase : attendre son feu vert avant la phase 5 (messagerie et notifications + lot serveur B).
- **2026-10-03 (nuit)** — **Phase 3 close** (PR #4) : connexion (e-mail, inscription, mot de passe oublié, nouveau
  mot de passe, code e-mail, Apple, Google sans SDK) et compte (profil, modifier, mot de passe, mes annonces, mes
  données, contact, langue → Réglages). 434 tests verts, tours de captures verts, galerie
  https://claude.ai/artifact/RatHcgEgHZHGEzGQhp7VgL. **ARRÊT DEMANDÉ PAR LE PROPRIÉTAIRE** à la fin de la phase 3 :
  attendre son feu vert avant la phase 4 (déposer une annonce). Connexion Apple / Google : à tester sur iPhone quand
  le compte Apple, l'identifiant Google iOS et le lot A seront là (`EN-ATTENTE.md`).
- **2026-10-03 (soir)** — **Phase 2 close** (PR #3) : 356 tests verts, 612 captures relues, galerie
  https://claude.ai/artifact/MtwYSCciJ8Aky6wpfA9GQa. **ARRÊT DEMANDÉ PAR LE PROPRIÉTAIRE** à la fin de la phase 2
  pour vérifier : attendre son feu vert avant la phase 3.
- Phase 1 close (PR #2, galerie https://claude.ai/artifact/WxiTw2n3mHKn5LP1Hcd6x8). Lots serveur A/B/C prêts en PR
  non fusionnées (weyda2026 #5, #6, #7). Préparation App Store sur `prep/release` (worktree `../weydaa-ios-release`,
  `ios-compat` vert sur iOS 16.4) — à fusionner en phase 6.
- **Méthode : une équipe d'agents en parallèle** (demandée par le propriétaire). L'orchestrateur fixe les contrats
  d'interface AVANT le code (`docs/equipe/CONTRACTS*.md`, `SCREEN-BRIEF.md`), chaque agent écrit SES fichiers et une
  note d'API, l'orchestrateur intègre, commite et lance UNE CI par lot, relit TOUTES les captures en planches
  contact (ffmpeg) avant la galerie.
- **Envoi git** : `weydaa-site/.claude/settings.json` interdit `git push` (protection du site : un envoi sur
  `master` part en production). La session tourne depuis `weydaa-site` → la règle bloque aussi le dépôt iOS. Le
  propriétaire l'a levée pour la phase 2 puis elle a été rétablie ; en phase 3, il a autorisé « pour la session, dépôt
  iOS seulement » → envois ciblés `git -C <worktree iOS> push` (de nouveau accordé en phase 4, le 2026-10-04). Redemander
  à chaque nouvelle session (ou ouvrir la session depuis `weydaa-ios`).
- (Fait) Phase 5 : worktree `../weydaa-ios-p5` depuis `main` ; contrats `docs/equipe/CONTRACTS-P5.md`
  à écrire d'abord (conversations, fil, offres, archives, « écrit… », blocage, signalement, temps réel, cloche et pastilles,
  push Firebase — dépendance accordée —, liens universels ; lot serveur B = PR weyda2026 #6). Chaînes des agents : un fichier JSON
  par agent fusionné par `node scripts/merge-agent-strings.mjs . <fichiers>` (même format que `scripts/ios-strings.json`),
  clés utilisables tout de suite dans le code ; puis `node scripts/convert-strings.mjs`.

## Rappels
- Pas de Mac : chaque vérification passe par la CI (`gh run watch`, `gh run view --log-failed`).
- Captures : `gh workflow run ios-screens.yml --ref <branche>` puis `gh run download <id> -D <scratchpad>` (un
  artefact `ios-screens-<appareil>-<langue>` par tour ; vidéos ≈ 150 Mo : télécharger en arrière-plan).
- Les fichiers générés (`Localizable.xcstrings`, `L10n.swift`, icônes) se régénèrent sur le poste avec Node
  (`scripts/*.mjs`) : la CI n'a pas accès au dépôt privé.
