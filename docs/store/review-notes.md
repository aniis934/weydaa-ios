# Notes pour l'App Review

> À coller dans App Store Connect → version → **Informations pour la revue de l'app** : la version
> anglaise dans « Notes » (4 000 caractères au plus, langue la plus sûre pour les réviseurs), le compte
> de démo dans « Connexion requise ». La version française sert au propriétaire. **Rien n'est inventé** :
> les chemins d'écran et les libellés entre guillemets sont ceux du code (phase 7 : `Weyda/Features/**`,
> catalogue `Localizable.xcstrings`) ; ce qui est entre crochets `[À FOURNIR]` est à compléter le jour J.
> À vérifier une dernière fois sur le build envoyé (TestFlight).

## À préparer avant la soumission (propriétaire)

1. **Compte de démo A** (donné à Apple) : e-mail dédié, mot de passe, e-mail **vérifié** (sinon favoris,
   messages et dépôt demandent le code), langue française ; 1 ou 2 annonces en ligne ; 1 conversation avec
   le compte B contenant une offre de prix ; 1 favori, 1 alerte. Ne jamais y mettre de vraies données
   personnelles.
2. **Compte vendeur B** (à nous, pas donné à Apple) : une annonce de test en ligne pendant la revue, par
   exemple « Annonce de test — App Review » ; elle reçoit les messages des réviseurs (pas de vrai vendeur
   dérangé). La retirer après la validation.
3. Coordonnées du contact de revue (prénom, nom, téléphone, e-mail) : saisies **dans App Store Connect
   seulement**, jamais dans ce dépôt public.
4. Lots serveur **déployés** : A (connexion Apple, révocation à la suppression, fichier des liens universels),
   B (liste des utilisateurs bloqués, blocage transmis à la modération, §5 des CGU : « tolérance zéro » et
   signalements traités sous 24 heures, notifications iOS), C (politique de confidentialité avec la section
   14 « Application iOS », page de suppression qui cite iOS). Sans eux, les réponses aux règles 1.2, 4.8 et
   5.1.1(v) ne tiennent pas : la liste des bloqués resterait vide et la connexion Apple échouerait.
5. Build envoyé avec Firebase (secret `GOOGLE_SERVICE_INFO_PLIST`) : sans lui, aucune demande d'autorisation
   des notifications ni aucun push. Avec les secrets Supabase : sans eux, messages sans temps réel. Avec
   l'identifiant client Google iOS : sans lui, le bouton Google est masqué (voir `docs/RELEASE.md`).

## Version française (référence)

Weydaa est une place de marché gratuite de petites annonces pour l'Algérie (weydaa.com) : publier une
annonce, chercher, contacter un vendeur par messagerie et négocier un prix. Aucun paiement dans l'app,
aucun achat intégré, aucun abonnement, aucune publicité : les ventes se concluent entre particuliers, hors
de l'app. La consultation ne demande pas de compte ; publier, écrire, faire une offre, ajouter aux favoris,
créer une alerte, laisser un avis et signaler, si.

- **Compte de démo** : `[À FOURNIR : e-mail]` / `[À FOURNIR : mot de passe]` (e-mail vérifié, annonces,
  conversation avec offre déjà en place).
- **Messagerie et offres** : ouvrir l'annonce « `[À FOURNIR : titre de l'annonce de test du compte B]` » →
  « Contacter le vendeur » → écrire → « Envoyer » ; ou « Faire une offre » → montant → « Envoyer l'offre ».
  Dans la conversation, le bouton « Faire une offre » est au-dessus du champ de saisie ; sur une offre reçue :
  « Accepter », « Contrer » ou « Refuser ». Onglet **Messages** : la conversation existante avec son offre.
- **Notifications** : l'autorisation est demandée à la première ouverture de l'onglet Messages par un membre
  connecté (jamais au lancement). Liste : onglet Profil → « Notifications », ou la cloche de l'accueil.
- **Connexion avec Apple (4.8)** : onglet Profil → « Se connecter » → « Continuer avec Apple ». Google
  (« Continuer avec Google ») est aussi proposé ; la connexion Apple est l'option équivalente exigée.
- **Suppression du compte (5.1.1(v))** : onglet Profil → « Mes données » → carte « Supprimer mon compte » →
  « Votre mot de passe » → « Supprimer définitivement » → confirmation « Supprimer le compte ? » →
  « Supprimer définitivement ». Compte Apple : « Confirmer avec Apple et supprimer » (confirmation Apple, sans
  mot de passe) ; compte Google : « Confirmer avec Google et supprimer ». Effacement réel : profil, e-mail,
  téléphone, annonces, favoris, alertes ; les messages déjà envoyés restent chez l'interlocuteur sous
  « Compte supprimé », sans nom ni photo (page publique : https://weydaa.com/fr/suppression-compte). Pour un
  compte Apple, l'accès « Se connecter avec Apple » est révoqué auprès d'Apple. Pour tester sans perdre le
  compte de démo : créer un compte avec Apple (immédiat), puis le supprimer. Même écran : « Exporter mes
  données » → « Préparer le fichier » → « Partager ».
- **Contenu des utilisateurs (1.2)** : chaque annonce est vérifiée avant sa mise en ligne (analyse
  automatique, puis un modérateur si besoin).
  - Signaler une annonce : fiche → bouton « Plus d'actions » (⋯, en haut) → « Signaler » → motif →
    « Envoyer le signalement ».
  - Signaler un utilisateur : conversation ou profil du vendeur → « Plus d'actions » (⋯) → « Signaler cet
    utilisateur ».
  - Bloquer : conversation ou profil du vendeur → « Plus d'actions » (⋯) → « Bloquer cet utilisateur » →
    confirmation. La personne ne peut plus écrire, l'aperçu des conversations avec elle est masqué, et chaque
    blocage est transmis à la modération. Liste et déblocage : onglet Profil → « Utilisateurs bloqués » →
    « Débloquer ».
  - Avis : profil du vendeur → « Laisser un avis » (après avoir contacté ce vendeur).
  - Signalements traités sous 24 heures ; tolérance zéro pour les contenus répréhensibles et les
    utilisateurs abusifs (§5 des CGU) ; contact public : contact@weydaa.com.
- **Langues** : français, arabe (de droite à gauche) et anglais, selon la langue de l'iPhone ; onglet Profil
  → « Langue » ouvre la page de Weydaa dans les Réglages pour en changer. Les annonces sont rédigées par les
  utilisateurs, surtout en français ou en arabe.
- **Autorisations** : photos par le sélecteur du système (aucun accès à toute la photothèque), appareil photo
  pour photographier un objet à vendre, notifications (voir plus haut). Aucune localisation : la wilaya se
  choisit dans une liste.
- Nouvelle annonce publiée pendant la revue : elle apparaît « En attente » dans onglet Profil → « Mes
  annonces » (« En cours de validation » sur sa fiche) jusqu'à la modération.

## Version anglaise (à coller dans « Notes »)

```
Weydaa is a free classifieds marketplace for Algeria (weydaa.com): post a listing, search, contact a seller through in-app messaging and negotiate a price. There are no payments in the app, no in-app purchases, no subscriptions and no advertising: sales are completed between individuals outside the app. Browsing needs no account; posting, messaging, offers, favorites, alerts, reviews and reports do.

DEMO ACCOUNT: [email] / [password] (verified email; it already has listings and a conversation with an offer).

MESSAGING AND OFFERS: open the listing "[test listing title]" > "Contact the seller" > type a message > "Send"; or "Make an offer" > amount > "Send offer". Inside a conversation, "Make an offer" sits above the text field; on a received offer: "Accept", "Counter" or "Decline". The Messages tab shows an existing conversation with an offer.

NOTIFICATIONS: permission is requested the first time a signed-in member opens the Messages tab, never at launch. List: Profile tab > "Notifications", or the bell on Home.

SIGN IN WITH APPLE (4.8): Profile tab > "Sign in" > "Continue with Apple". Google sign-in is also offered; Sign in with Apple is the equivalent option.

ACCOUNT DELETION (5.1.1(v)): Profile tab > "My data" > "Delete my account" card > "Your password" > "Delete permanently" > confirm "Delete account?" > "Delete permanently". Apple accounts: "Confirm with Apple and delete" (Apple confirmation, no password); Google accounts: "Confirm with Google and delete". This is a real erasure: profile, email, phone, listings, favorites and alerts are deleted; messages already sent stay with the other user under "Deleted account", without name or photo (public page: https://weydaa.com/en/suppression-compte). For Apple accounts, Sign in with Apple access is revoked with Apple. To test without losing the demo account, create an account with Sign in with Apple (instant), then delete it. Same screen: "Export my data" > "Prepare the file".

USER-GENERATED CONTENT (1.2): every listing is checked before it goes live (automated analysis, then a moderator when needed).
- Report a listing: listing > "More actions" (...) > "Report" > reason > "Submit report".
- Report a user: conversation or seller profile > "More actions" (...) > "Report this user".
- Block a user: conversation or seller profile > "More actions" (...) > "Block this user" > confirm. They can no longer message you, conversation previews with them are hidden, and every block is passed on to our moderation team. List and unblock: Profile tab > "Blocked users" > "Unblock".
- Reviews: seller profile > "Leave a review" (after contacting that seller).
Reports are handled within 24 hours; zero tolerance for objectionable content and abusive users (Terms of Use, section 5). Public contact: contact@weydaa.com.

LANGUAGES: French, Arabic (right-to-left) and English, following the iPhone language; Profile tab > "Language" opens Weydaa's page in iOS Settings to change it. Listings are written by users, mostly in French or Arabic.

PERMISSIONS: photos through the system picker (no full library access), camera to photograph an item for sale, notifications (see above). No location access: the wilaya (province) is picked from a list.

A listing posted during the review shows as "Pending" in Profile tab > "My listings" ("Under review" on the listing itself) until moderation.
```
`[email]`, `[password]`, `[test listing title]` : à remplacer (`[À FOURNIR]`). Compté par script : 3 368
caractères tels quels, environ 3 420 une fois complété (limite : 4 000). Si le build n'a pas d'identifiant client
Google iOS (bouton Google masqué, voir `docs/RELEASE.md`), retirer la phrase « Google sign-in is also offered… ».

Libellés vérifiés dans le code et le catalogue (fr / en) : « Profil » / « Profile », « Se connecter » / « Sign in »,
« Contacter le vendeur » / « Contact the seller », « Envoyer » / « Send », « Faire une offre » / « Make an
offer », « Envoyer l'offre » / « Send offer », « Accepter » / « Accept », « Contrer » / « Counter », « Refuser » /
« Decline », « Notifications », « Mes données » / « My data », « Supprimer mon compte » / « Delete my account »,
« Votre mot de passe » / « Your password », « Supprimer définitivement » / « Delete permanently », « Supprimer le
compte ? » / « Delete account? », « Confirmer avec Apple et supprimer » / « Confirm with Apple and delete »,
« Exporter mes données » / « Export my data », « Préparer le fichier » / « Prepare the file », « Plus d'actions » /
« More actions », « Signaler » / « Report », « Envoyer le signalement » / « Submit report », « Signaler cet
utilisateur » / « Report this user », « Bloquer cet utilisateur » / « Block this user », « Utilisateurs bloqués » /
« Blocked users », « Débloquer » / « Unblock », « Laisser un avis » / « Leave a review », « Langue » /
« Language », « Mes annonces » / « My listings », « En attente » / « Pending », « En cours de validation » /
« Under review ». « Continuer avec Apple » / « Continue with Apple » est le libellé du bouton système d'Apple
(`SignInWithAppleButton(.continue)`), traduit par iOS. Délai de 24 heures et « tolérance zéro » : §5 des CGU du
lot B (fr et en).
