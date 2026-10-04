# Notes pour l'App Review

> À coller dans App Store Connect → version → **Informations pour la revue de l'app** : la version
> anglaise dans « Notes » (4 000 caractères au plus, langue la plus sûre pour les réviseurs), le compte
> de démo dans « Connexion requise ». La version française sert au propriétaire. **Rien n'est inventé** :
> tout ce qui est entre crochets `[À FOURNIR]` / `[À CONFIRMER]` est à compléter le jour J. Les chemins
> d'écran sont ceux prévus (mêmes libellés que l'app Android) : à vérifier sur le build envoyé.

## À préparer avant la soumission (propriétaire)

1. **Compte de démo A** (donné à Apple) : e-mail dédié, mot de passe, e-mail **vérifié**, langue
   française ; 1 ou 2 annonces en ligne ; 1 conversation avec le compte B contenant une offre de prix ;
   1 favori, 1 alerte. Ne jamais y mettre de vraies données personnelles.
2. **Compte vendeur B** (à nous, pas donné à Apple) : une annonce de test en ligne pendant la revue, par
   exemple « Annonce de test — App Review » ; elle reçoit les messages des réviseurs (pas de vrai vendeur
   dérangé). La retirer après la validation.
3. Coordonnées du contact de revue (prénom, nom, téléphone, e-mail) : saisies **dans App Store Connect
   seulement**, jamais dans ce dépôt public.
4. Lots serveur déployés : A (connexion Apple + révocation à la suppression), B (modération, utilisateurs
   bloqués, clause « tolérance zéro » et délai de traitement des signalements dans les CGU), C (textes
   légaux iOS). Sans eux, les réponses aux règles 1.2, 4.8 et 5.1.1(v) ne tiennent pas.

## Version française (référence)

Weydaa est une place de marché gratuite de petites annonces pour l'Algérie (weydaa.com) : publier une
annonce, chercher, contacter un vendeur par messagerie et négocier un prix. Aucun paiement dans l'app,
aucun achat intégré, aucun abonnement, aucune publicité : les ventes se concluent entre particuliers, hors
de l'app. La consultation ne demande pas de compte ; publier, écrire et ajouter aux favoris, si.

- **Compte de démo** : `[À FOURNIR : e-mail]` / `[À FOURNIR : mot de passe]` (e-mail vérifié, annonces,
  conversation avec offre déjà en place).
- **Messagerie** : ouvrir l'annonce « `[À FOURNIR : titre de l'annonce de test du compte B]` » →
  « Contacter le vendeur » → envoyer un message ; dans la conversation, « Faire une offre ». Onglet
  Messages : la conversation existante avec son offre.
- **Connexion avec Apple** : onglet Profil → Se connecter → bouton Apple. Google est aussi proposé ; la
  connexion Apple est l'option équivalente exigée par la règle 4.8.
- **Suppression du compte (5.1.1(v))** : onglet Profil → Mes données → Supprimer mon compte → mot de passe
  (ou confirmation Apple / Google) → Supprimer définitivement. Effacement réel : profil, e-mail,
  téléphone, annonces, favoris, alertes ; les messages déjà envoyés restent chez l'interlocuteur sous
  « Compte supprimé », sans nom ni photo (détail public : https://weydaa.com/fr/suppression-compte). Pour
  un compte Apple, les jetons Apple sont révoqués. Pour tester sans perdre le compte de démo : créer un
  compte avec Apple (immédiat), puis le supprimer.
- **Contenu des utilisateurs (1.2)** : chaque annonce est vérifiée avant sa mise en ligne (analyse
  automatique, puis un modérateur si besoin) ; signaler une annonce (annonce → menu ⋯ → Signaler) ou un
  utilisateur (conversation ou profil vendeur → menu ⋯ → Signaler cet utilisateur) ; bloquer un
  utilisateur (conversation → menu ⋯ → Bloquer cet utilisateur ; liste dans Profil → Utilisateurs bloqués
  `[À CONFIRMER : libellé]`) ; ses messages et contenus sont alors masqués. Signalements traités sous
  `[À CONFIRMER : délai, par ex. 24 h]` ; tolérance zéro pour les contenus abusifs (CGU) ; contact public :
  contact@weydaa.com.
- **Langues** : français, arabe (de droite à gauche) et anglais, selon la langue de l'iPhone ou Réglages →
  Weydaa → Langue. Les annonces sont rédigées par les utilisateurs, surtout en français ou en arabe.
- **Autorisations** : photothèque par le sélecteur système (aucun accès global), appareil photo pour
  photographier un objet à vendre, notifications demandées à la première ouverture de Messages
  `[À CONFIRMER à la phase 5]`. Aucune localisation : la wilaya se choisit dans une liste.
- Nouvelle annonce publiée pendant la revue : elle apparaît « En vérification » dans Profil → Mes annonces
  jusqu'à la modération.

## Version anglaise (à coller dans « Notes »)

```
Weydaa is a free classifieds marketplace for Algeria (weydaa.com): post a listing, search, contact a seller through in-app messaging and negotiate a price. There are no payments in the app, no in-app purchases, no subscriptions and no advertising: sales are completed between individuals outside the app. Browsing needs no account; posting, messaging and favorites do.

DEMO ACCOUNT: [email] / [password] (verified email; it already has listings and a conversation with an offer).

MESSAGING: open the listing "[test listing title]" > "Contact the seller" > send a message; inside the conversation, use "Make an offer". The Messages tab also shows an existing conversation with an offer.

SIGN IN WITH APPLE: Profile tab > Sign in > Apple button. Google sign-in is also offered; Sign in with Apple is the equivalent option (guideline 4.8).

ACCOUNT DELETION (5.1.1(v)): Profile tab > My data > Delete my account > password (or Apple / Google confirmation) > Delete permanently. This is a real erasure: profile, email, phone, listings, favorites and alerts are deleted; messages already sent stay with the other user under "Deleted account", without name or photo (public page: https://weydaa.com/en/suppression-compte). For Apple accounts, the Apple tokens are revoked. To test without losing the demo account, create an account with Sign in with Apple (instant), then delete it.

USER-GENERATED CONTENT (1.2): every listing is checked before it goes live (automated analysis, then a moderator when needed). Users can report a listing (listing > ... menu > Report) or a user (conversation or seller profile > ... menu > Report this user), and block a user (conversation > ... menu > Block this user; list under Profile > Blocked users), which hides their messages and content. Reports are handled within [delay]. Zero tolerance for abusive content (Terms of Use). Public contact: contact@weydaa.com.

LANGUAGES: French, Arabic (right-to-left) and English, following the iPhone language or Settings > Weydaa > Language. Listings are written by users, mostly in French or Arabic.

PERMISSIONS: photos through the system picker (no full library access), camera to photograph an item for sale, notifications requested the first time Messages is opened. No location access: the wilaya (province) is picked from a list.

A listing posted during the review shows as "Under review" in Profile > My listings until moderation.
```
`[email]`, `[password]`, `[test listing title]`, `[delay]` : à remplacer. Environ 2 400 caractères une fois
complété (limite : 4 000). Libellés anglais vérifiés dans le catalogue de l'app (`Contact the seller`,
`Make an offer`, `My data`, `Delete my account`, `Delete permanently`, `Report`, `Report this user`,
`Block this user`) ; « Blocked users » et le libellé du bouton Apple restent à confirmer (phases 3 et 5).
