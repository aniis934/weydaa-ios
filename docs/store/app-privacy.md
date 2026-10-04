# App Privacy — réponses au questionnaire d'App Store Connect

> Brouillon fondé sur le code (app Android v1, API du site, plan iOS) et sur le tableau « Sécurité des
> données » de la fiche Play (dépôt privé, `android/docs/store/README.md`). À revoir quand le code iOS
> existe (phases 1 à 5), puis le jour de la soumission. Le manifeste
> [`PrivacyInfo.xcprivacy`](PrivacyInfo.xcprivacy) (brouillon, même dossier) reprend exactement ces
> réponses : toute modification se fait des deux côtés.

## Les règles d'Apple en quatre phrases

- **Collecter** = envoyer hors de l'iPhone et garder plus longtemps que le temps de répondre à la requête.
  Ce qui reste sur l'appareil n'est pas collecté : historique de recherche local, brouillon d'annonce,
  jetons de session dans le trousseau.
- **Lié à l'identité** = rattaché au compte, ou à un identifiant qui permet de retrouver la personne.
- **Suivi (tracking)** = croiser avec des données d'autres entreprises pour de la publicité ciblée, ou
  les transmettre à un courtier en données. Weydaa : **non** partout, donc pas de fenêtre « Autoriser le
  suivi » (ATT) et `NSPrivacyTracking = false`.
- Ce que collectent les SDK intégrés (Firebase, phase 5) compte comme collecté par l'app.

## Réponses

« Collectez-vous des données depuis cette app ? » → **Oui**. Puis, pour chaque type coché :

| Catégorie → type Apple | Données Weydaa | Lié | Suivi | Finalités |
|---|---|---|---|---|
| Coordonnées → Nom | nom du profil ; nom transmis par Apple ou Google à la première connexion | Oui | Non | Fonctionnalités de l'app |
| Coordonnées → Adresse e-mail | e-mail du compte (y compris l'adresse relais « masquée » d'Apple) ; e-mail du formulaire de contact | Oui | Non | Fonctionnalités de l'app |
| Coordonnées → Numéro de téléphone | facultatif ; révélé seulement à un utilisateur connecté qui le demande | Oui | Non | Fonctionnalités de l'app |
| Localisation → Localisation approximative | wilaya et commune **choisies dans une liste** (annonce, recherche) ; jamais de GPS, aucune permission de localisation | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → E-mails ou SMS | messages et offres de la messagerie | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → Photos ou vidéos | photos d'annonce (photothèque ou appareil photo, uniquement celles choisies) ; photo de profil (dont celle de Google) | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → Service client | formulaire « Nous contacter » | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → Autre contenu | annonces (titre, description, prix, caractéristiques), avis, signalements, présentation du profil | Oui | Non | Fonctionnalités de l'app |
| Historique des recherches | alertes (recherches enregistrées sur le compte) ; requêtes journalisées par le serveur **sans compte** (texte, nombre de résultats, langue : « vouliez-vous dire », statistiques) | Oui | Non | Fonctionnalités de l'app, Personnalisation du produit, Analyse |
| Identifiants → Identifiant utilisateur | identifiant du compte | Oui | Non | Fonctionnalités de l'app |
| Identifiants → Identifiant de l'appareil | jeton de notification (Firebase Cloud Messaging / APNs) enregistré sur le compte, identifiant d'installation Firebase | Oui | Non | Fonctionnalités de l'app |
| Données d'utilisation → Interactions avec le produit | favoris enregistrés sur le compte | Oui | Non | Fonctionnalités de l'app, Personnalisation du produit |
| Diagnostics → Données de plantage | rapports Firebase Crashlytics (builds Release) | Non | Non | Fonctionnalités de l'app |
| Diagnostics → Autres données de diagnostic | contexte technique joint au plantage (modèle, version d'iOS et de l'app) | Non | Non | Fonctionnalités de l'app |

Justifications des finalités :
- **Personnalisation du produit** : la rangée « Pour vous » de l'accueil vient de `GET /api/recommendations`,
  calculée par le serveur d'après les favoris et les alertes du compte.
- **Analyse** : le journal des recherches (`search_logs`, sans identifiant ni IP) sert aussi aux
  statistiques de recherche de l'administration.
- La modération automatique des annonces (texte et photos envoyés à un modèle d'IA via OpenRouter) et la
  lutte contre la fraude relèvent de « Fonctionnalités de l'app » au sens d'Apple (sécurité, prévention
  des fraudes) : aucune finalité supplémentaire.
- Les deux diagnostics ne sont **pas liés** à l'identité tant que l'app n'appelle pas
  `Crashlytics.setUserID` (Android ne le fait pas) : **ne pas l'ajouter**, sinon passer ces lignes à « Oui ».

### Non collecté (ne rien cocher)

Localisation précise · adresse postale · autres coordonnées · santé, forme · données financières ·
données sensibles · contacts · audio · contenu de jeu · historique de navigation · achats · données
publicitaires · autres données d'utilisation · performances · scan de l'environnement · mains, tête ·
autres données. Aucune publicité, aucun SDK publicitaire, aucun outil d'analyse dans l'app (PostHog ne
tourne que sur le site, après consentement).

## Divergences avec la fiche Play (à signaler au propriétaire)

| # | Point | iOS | Play aujourd'hui | À faire |
|---|---|---|---|---|
| 1 | Journal serveur des recherches (sans compte) | déclaré (Historique des recherches, Analyse) | absent (seul l'historique local est cité) | ajouter « Historique des recherches dans l'app » au formulaire Play |
| 2 | Personnalisation « Pour vous » (favoris, alertes) | finalité déclarée | finalité absente | ajouter « Personnalisation » côté Play |
| 3 | Identifiant utilisateur | déclaré | absent | ajouter « Identifiants utilisateur » côté Play |
| 4 | Formulaire de contact | Service client | non cité | facultatif côté Play |
| 5 | Connexion Apple (nom, e-mail éventuellement relais) | couvert par Nom / E-mail | sans objet | — |
| 6 | Historique de recherche local, brouillons, jetons | non collectés (restent sur l'iPhone) | cité dans « Activité » | rien à changer |
| 7 | Prestataires dans la politique de confidentialité | — | Firebase cité pour Android seulement ; OpenRouter (modération IA) et Apple (connexion) absents | lot serveur C : section iOS + OpenRouter + Apple |

Le lot C doit aussi faire mentionner iOS dans la page de suppression de compte (révocation Apple).

## Saisie dans App Store Connect

1. App → **Confidentialité de l'app** → URL de la politique de confidentialité (une par langue, voir les
   fiches), puis **Commencer**.
2. « Collectez-vous des données ? » → **Oui** → cocher exactement les 14 types du tableau → Enregistrer.
3. Pour chaque type : finalités cochées comme dans le tableau → « Lié à l'identité ? » → « Utilisé pour
   le suivi ? » **Non**.
4. Vérifier l'aperçu (« Données liées à vous », « Données non liées à vous », aucune « Données utilisées
   pour vous suivre »), puis **Publier**. La section doit être publiée avant la soumission.

## API à raison obligatoire (manifeste)

Apple exige une raison déclarée pour certaines API. Brouillon : UserDefaults (**CA92.1**, données lues
et écrites par l'app elle-même) et horodatage de fichiers (**C617.1**, fichiers du conteneur de l'app).

Vérifications à faire quand le code sera là (phase 1 pour le cache d'images, phase 7 avant de déplacer
le manifeste) :

| Catégorie | Raison prévue | Recherche dans le code | Si aucun résultat |
|---|---|---|---|
| UserDefaults | CA92.1 | `UserDefaults`, `@AppStorage` (déjà : `LaunchOptions`) | garder (toujours utilisé) |
| Horodatage de fichiers | C617.1 | `contentModificationDate`, `creationDate`, `contentAccessDate`, `attributesOfItem`, `modificationDate`, `stat(`, `getattrlist` | retirer l'entrée |
| Heure de démarrage du système | 35F9.1 (durées) | `systemUptime`, `mach_absolute_time` | ne rien ajouter |
| Espace disque | E174.1 (vérifier avant d'écrire) | `volumeAvailableCapacity`, `systemFreeSize`, `statfs` | ne rien ajouter |
| Claviers actifs | — | `activeInputModes` | ne rien ajouter |

Commande (Git Bash, à la racine du dépôt) :
`grep -rnE "contentModificationDate|creationDate|contentAccessDate|attributesOfItem|modificationDate|getattrlist|systemUptime|mach_absolute_time|volumeAvailableCapacity|systemFreeSize|statfs|activeInputModes" Weyda/`

Contrôle sans Mac : à chaque envoi TestFlight, Apple vérifie le binaire et signale par e-mail une API non
déclarée (`ITMS-91053: Missing API declaration`, avec la catégorie) — c'est bloquant à l'envoi.
`ios-release` avertit aussi si `PrivacyInfo.xcprivacy` manque dans l'app archivée. Firebase (phase 5)
apporte ses propres manifestes : vérifier que la version intégrée les contient (Firebase 10.22 ou plus).

Phase 7 : déplacer le fichier tel quel dans `Weyda/Resources/PrivacyInfo.xcprivacy` (XcodeGen l'ajoute aux
ressources : il doit se retrouver à la racine de `Weyda.app`).
