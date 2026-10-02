# En attente du propriétaire

> Registre du mode autonome (décidé le 2026-10-03) : quand une étape dépend du propriétaire (compte,
> clé, feu vert, décision), on l'écrit ici et on continue sur autre chose. Une ligne par point, la plus
> récente en haut de sa section. Une fois traité : cocher, dater, ne pas effacer.
> Aucun secret ici (dépôt public) : on nomme ce qu'il faut saisir, jamais sa valeur.

## Comptes et clés (à saisir par le propriétaire)
- [ ] **Compte Apple Developer** actif — débloque : connexion Apple, TestFlight, push APNs, liens universels, soumission.
- [ ] **App Store Connect** : app « Weydaa » (`com.weydaa.app`, langue fr), clé API (rôle Admin) → 3 secrets GitHub
      (Key ID, Issuer ID, fichier .p8) — débloque `ios-release`.
- [ ] **Secrets GitHub du dépôt iOS** `SUPABASE_HOST` + `SUPABASE_ANON_KEY` (mêmes valeurs que le site) — débloque
      le temps réel dans les builds de la CI (sans eux : HTTP seul, l'app fonctionne).
- [ ] **Google Cloud** : client OAuth « iOS » pour `com.weydaa.app` ; `AUTH_GOOGLE_IOS_ID` sur Vercel — débloque Google.
- [ ] **Apple** : clé « Sign in with Apple » → variables `APPLE_*` sur Vercel ; relais e-mail Apple (weydaa.com).
- [ ] **Apple** : clé APNs → Firebase ; app iOS dans Firebase → `GoogleService-Info.plist` en secret GitHub.

## Feux verts
- [ ] Déploiement de chaque lot serveur (PR prête → `master` → Vercel) : A (connexion), B (push, modération), C (textes).
- [ ] Écritures réelles en prod avec un compte de test (publier une annonce, envoyer un message, une offre).

## Décisions
- [ ] Pays de diffusion App Store : Algérie seule, ou aussi la France / l'UE (statut de commerçant exigé par Apple).
- [ ] Compte de démo pour l'App Review (e-mail de test dédié).
- [ ] Photos des annonces fictives (captures, API simulée) : dessinées par script par défaut — à revoir si besoin
      pour les captures de la fiche App Store (phase 7).

## Tests sur l'iPhone (TestFlight)
- [ ] Fin de phase 2 : parcourir (fluidité, démarrage : le W fantôme ne doit pas traîner).
- [ ] Fin de phase 5 : messagerie + push.
- [ ] Test final guidé (~30 min) puis soumission.

## Problèmes rencontrés en autonomie
_(rien pour l'instant)_
