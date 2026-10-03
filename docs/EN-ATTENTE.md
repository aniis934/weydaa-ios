# En attente du propriétaire

> Registre du mode autonome (décidé le 2026-10-03) : quand une étape dépend du propriétaire (compte,
> clé, feu vert, décision), on l'écrit ici et on continue sur autre chose. Une ligne par point, la plus
> récente en haut de sa section. Une fois traité : cocher, dater, ne pas effacer.
> Aucun secret ici (dépôt public) : on nomme ce qu'il faut saisir, jamais sa valeur.

## Comptes et clés (à saisir par le propriétaire)
- [ ] **Clé API d'ÉQUIPE App Store Connect (accès Admin, « Team key », pas une clé individuelle)** → secrets GitHub
      `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contenu du .p8) + `APPLE_TEAM_ID` — débloque `ios-release`
      (mode d'emploi : `docs/RELEASE.md`, branche `prep/release`).
- [ ] **iPhone enregistré (UDID)** dans Certificates, IDs & Profiles — probablement exigé par la signature
      automatique de l'archive (sinon plan B fastlane, documenté).
- [ ] **Compte Apple Developer** actif — débloque : connexion Apple, TestFlight, push APNs, liens universels, soumission.
- [ ] **App Store Connect** : app « Weydaa » (`com.weydaa.app`, langue fr), clé API (rôle Admin) → 3 secrets GitHub
      (Key ID, Issuer ID, fichier .p8) — débloque `ios-release`.
- [ ] **Secrets GitHub du dépôt iOS** `SUPABASE_HOST` + `SUPABASE_ANON_KEY` (mêmes valeurs que le site) — débloque
      le temps réel dans les builds de la CI (sans eux : HTTP seul, l'app fonctionne).
- [ ] **Google Cloud** : client OAuth « iOS » pour `com.weydaa.app` ; `AUTH_GOOGLE_IOS_ID` sur Vercel — débloque Google.
- [ ] **Apple** : clé « Sign in with Apple » → variables `APPLE_*` sur Vercel ; relais e-mail Apple (weydaa.com).
- [ ] **Apple** : clé APNs → Firebase ; app iOS dans Firebase → `GoogleService-Info.plist` en secret GitHub.
- [ ] **Ordre conseillé côté serveur (2026-10-03, lots prêts)** : 1) Apple Developer : noter le Team ID, créer l'App ID
      `com.weydaa.app` (Sign in with Apple, Associated Domains, Push) ; 2) clés « Sign in with Apple » et APNs (.p8) ;
      3) Google Cloud : client OAuth iOS ; 4) Vercel : `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (contenu du .p8),
      `APPLE_BUNDLE_ID` (= com.weydaa.app), `AUTH_GOOGLE_IOS_ID` ; 5) Firebase : app iOS + clé APNs ; 6) « Sign in with
      Apple for Email Communication » : weydaa.com + l'adresse d'envoi (SPF, DKIM) — sans ça, les e-mails vers les
      adresses relais Apple ne partent pas ; 7) feux verts ci-dessous, puis vérifier l'AASA sur les deux domaines.

## Feux verts
- [ ] **Lot C (textes)** — https://github.com/aniis934/weyda2026/pull/7 : confidentialité (section iOS, Apple parmi
      les destinataires) et page de suppression, fr/ar/en. Prêt (tsc, vitest, lint, CI verts) — à fusionner avant la soumission.
- [ ] **Lot B (push, modération)** — https://github.com/aniis934/weyda2026/pull/6 : bloc APNs pour les jetons iOS
      (titre traduit selon la langue de l'appareil ; Android inchangé), `platform` sur `/api/push/fcm`, notifications
      MESSAGE lues à l'ouverture du fil, `GET /api/users/me/blocked`, signalement à la modération à chaque blocage,
      clause « tolérance zéro » (24 h) dans les CGU ×3. Prêt — à fusionner avant la phase 5 (push iOS).
- [ ] **Lot A (connexion)** — https://github.com/aniis934/weyda2026/pull/5 : `POST /api/auth/apple`, révocation Apple
      à la suppression de compte (avant l'effacement ; un échec n'empêche pas la suppression, note TN3194), audiences
      Google (`AUTH_GOOGLE_IOS_ID`), `providers` sur `/api/users/me`, AASA dynamique (404 tant que `APPLE_TEAM_ID` est
      vide). Prêt — à fusionner avant le test de la connexion Apple/Google sur iPhone (phase 3).
      Contrôle du 2026-10-03 : `/.well-known/apple-app-site-association` répond 404 sans redirection sur weydaa.com et
      www.weydaa.com (normal avant le lot A) ; les push de ces branches ont créé des **prévisualisations** Vercel
      automatiques (intégration existante), rien en production.
- [ ] Déploiement de chaque lot serveur (PR prête → `master` → Vercel) : A (connexion), B (push, modération), C (textes).
- [ ] Branche `prep/release` (workflows `ios-release` / `ios-compat`, textes App Store, App Privacy, notes de revue) :
      fusionnée dans `main` par l'orchestrateur en phase 6 (`ios-compat` y sera relancé, ≈ 10 min, iOS 16.4 sur
      iPhone SE) — rien à faire de ton côté avant.
- [ ] Écritures réelles en prod avec un compte de test (publier une annonce, envoyer un message, une offre).

## Décisions
- [ ] Âge App Store : 18+ conseillé (cohérent avec les CGU et la fiche Play) ; nom « Weydaa – Petites annonces »
      (repli « Weydaa ») ; ligne de copyright — détails : `docs/store/age-rating.md`, fiches `docs/store/fiche-*.md`.
- [ ] Textes du site à compléter (relevé du 2026-10-03, hors iOS) : le formulaire Play « Sécurité des données » oublie
      l'historique des recherches (journal serveur), la personnalisation « Pour vous » et l'identifiant utilisateur ;
      la politique de confidentialité ne cite pas OpenRouter (modération IA des annonces).
- [ ] Pays de diffusion App Store : Algérie seule, ou aussi la France / l'UE (statut de commerçant exigé par Apple).
- [ ] Comptes de démo pour l'App Review : A (donné à Apple) et B (vendeur avec une annonce de test, pour tester la
      messagerie) — `docs/store/review-notes.md` ; le contact de la revue se saisit dans App Store Connect seulement.
- [ ] Photos des annonces fictives (captures, API simulée) : dessinées par script par défaut — à revoir si besoin
      pour les captures de la fiche App Store (phase 7).

## Tests sur l'iPhone (TestFlight)
- [ ] Fin de phase 2 : parcourir (fluidité, démarrage : le W fantôme ne doit pas traîner).
- [ ] Fin de phase 5 : messagerie + push.
- [ ] Test final guidé (~30 min) puis soumission.

## Problèmes rencontrés en autonomie
- [ ] **Feu vert pour la phase 3** (2026-10-03) : arrêt demandé à la fin de la phase 2 pour vérification — galerie
      https://claude.ai/artifact/MtwYSCciJ8Aky6wpfA9GQa. La phase 3 (connexion, compte) est commencée et en pause.
- [ ] **Envoi git (`git push`)** interdit par `weydaa-site/.claude/settings.json` (protection du site) : levé pour la
      phase 2 à ta demande, puis rétabli. À chaque phase : autoriser de nouveau, ou ouvrir la session depuis `weydaa-ios`.
- [ ] Site (hors iOS, relevé le 2026-10-03) : `messages/ar.json` et `en.json` ont des clés en double dans la section
      admin (`dashboard`, `users`, `reports` : un texte puis un objet) — la seconde écrase la première.
