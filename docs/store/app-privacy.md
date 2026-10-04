# App Privacy — réponses au questionnaire d'App Store Connect

> Réponses relues en phase 7 d'après le code iOS RÉEL (phases 1 à 6 : compte, dépôt, messagerie et offres, push,
> utilisateurs bloqués, favoris, alertes, avis, Crashlytics), l'API du site et les manifestes de Firebase 12.19.2.
> Le manifeste de l'app [`Weyda/Resources/PrivacyInfo.xcprivacy`](../../Weyda/Resources/PrivacyInfo.xcprivacy)
> reprend exactement ces réponses (contrôlé par `WeydaTests/PrivacyManifestTests.swift`) : toute modification se
> fait des deux côtés. À relire le jour de la soumission si une fonction a changé.

## Les règles d'Apple en quatre phrases

- **Collecter** = envoyer hors de l'iPhone et garder plus longtemps que le temps de répondre à la requête.
  Ce qui reste sur l'appareil n'est pas collecté : historique de recherche local, brouillon d'annonce,
  jetons de session dans le trousseau.
- **Lié à l'identité** = rattaché au compte, ou à un identifiant qui permet de retrouver la personne.
- **Suivi (tracking)** = croiser avec des données d'autres entreprises pour de la publicité ciblée, ou
  les transmettre à un courtier en données. Weydaa : **non** partout, donc pas de fenêtre « Autoriser le
  suivi » (ATT) et `NSPrivacyTracking = false`.
- Ce que collectent les SDK intégrés (Firebase) compte comme collecté par l'app.

## Réponses

« Collectez-vous des données depuis cette app ? » → **Oui**. Puis, pour chaque type coché (15 types) :

| Catégorie → type Apple | Données Weydaa (iOS) | Lié | Suivi | Finalités |
|---|---|---|---|---|
| Coordonnées → Nom | nom du profil (Modifier mon profil) ; nom transmis par Apple (première connexion seulement) ou par Google ; nom du formulaire « Nous contacter » | Oui | Non | Fonctionnalités de l'app |
| Coordonnées → Adresse e-mail | e-mail du compte (y compris l'adresse relais « masquée » d'Apple) ; e-mail du formulaire « Nous contacter » | Oui | Non | Fonctionnalités de l'app |
| Coordonnées → Numéro de téléphone | « Téléphone (optionnel) » du profil ; montré sur l'annonce seulement si le vendeur le choisit, révélé à un utilisateur connecté qui touche « Afficher le numéro » | Oui | Non | Fonctionnalités de l'app |
| Localisation → Localisation approximative | wilaya et commune **choisies dans une liste** (annonce, filtres, alertes) ; jamais de GPS, aucune permission de localisation (déclaré par prudence) | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → E-mails ou SMS | messages de la messagerie, offres de prix, contre-offres et réponses, état de lecture | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → Photos ou vidéos | photos d'annonce (sélecteur de photos du système ou appareil photo, uniquement celles choisies, envoyées en JPEG de 1 600 px) ; photo de profil transmise par Google (l'app iOS n'envoie pas de photo de profil) | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → Service client | formulaire « Nous contacter » (sujet, message) | Oui | Non | Fonctionnalités de l'app |
| Contenu utilisateur → Autre contenu | annonces (titre, description, prix, caractéristiques), bio du profil, avis (note et commentaire), signalements d'annonce ou d'utilisateur, utilisateurs bloqués (chaque blocage est aussi transmis à la modération, lot B) | Oui | Non | Fonctionnalités de l'app |
| Historique des recherches | alertes (5 recherches enregistrées au plus, sur le compte, avec notification des nouvelles annonces) ; requêtes journalisées par le serveur **sans compte** (texte, nombre de résultats, langue ; effacées après 90 jours) | Oui | Non | Fonctionnalités de l'app, Personnalisation du produit, Analyse |
| Identifiants → Identifiant utilisateur | identifiant du compte | Oui | Non | Fonctionnalités de l'app |
| Identifiants → Identifiant de l'appareil | jeton de notification Firebase (FCM, relayé par APNs) enregistré sur le compte (`POST /api/push/fcm`, plateforme « ios »), détruit à la déconnexion ; identifiant d'installation Firebase | Oui | Non | Fonctionnalités de l'app |
| Données d'utilisation → Interactions avec le produit | favoris enregistrés sur le compte | Oui | Non | Fonctionnalités de l'app, Personnalisation du produit |
| Diagnostics → Données de plantage | rapports Firebase Crashlytics (builds Release seulement : collecte coupée en Debug) | Non | Non | Fonctionnalités de l'app |
| Diagnostics → Autres données de diagnostic | contexte technique joint au plantage (modèle, version d'iOS et de l'app) ; télémétrie propre aux SDK Firebase (Installations, GoogleDataTransport, Messaging) | Non | Non | Fonctionnalités de l'app, Analyse |
| Autres données → Autres types de données | déclaré par le manifeste de Firebase Messaging (non lié, Analyse) ; le code de l'app n'envoie aucune donnée de ce type | Non | Non | Analyse |

Justifications des finalités :
- **Personnalisation du produit** : la rangée « Pour vous » de l'accueil vient de `GET /api/recommendations`,
  calculée par le serveur d'après les favoris et les alertes du compte (vérifié dans le code du site).
- **Analyse** : le journal des recherches (`search_logs`, sans identifiant ni IP) sert aux statistiques de
  recherche de l'administration. Les SDK Firebase déclarent aussi « Analyse » pour leur propre télémétrie
  (manifestes de FirebaseInstallations, GoogleDataTransport et FirebaseMessaging 12.19.2). L'app n'embarque
  **aucun** outil d'analyse (ni Firebase Analytics, ni PostHog).
- La modération automatique des annonces (titre, description, prix, lieu et caractéristiques envoyés à un
  modèle de Google via OpenRouter ; ni les photos, dont seul le nombre compte, ni le nom, l'e-mail ou le
  téléphone) et la lutte contre la fraude relèvent de « Fonctionnalités de l'app » au sens d'Apple (sécurité,
  prévention des fraudes) : aucune finalité supplémentaire.
- **Diagnostics non liés** : l'app n'appelle pas `Crashlytics.setUserID` (`Weyda/Core/Push/FirebasePush.swift`).
  **Ne pas l'ajouter**, sinon passer les deux lignes de diagnostic à « Oui ».
- **Identifiant de l'appareil lié** : Firebase le déclare « non lié » de son côté, mais le serveur de Weydaa
  rattache le jeton au compte : la réponse la plus stricte l'emporte.

### Non collecté (ne rien cocher)

Localisation précise · adresse postale · autres coordonnées · santé, forme · données financières ·
données sensibles · contacts · audio · contenu de jeu · historique de navigation · achats · données
publicitaires · autres données d'utilisation · performances · scan de l'environnement · mains, tête.
Aucune publicité, aucun SDK publicitaire, aucun identifiant publicitaire, aucune demande de suivi.

### Vu dans le code, mais pas à déclarer

- Reste sur l'iPhone : historique de recherche local (`SearchHistoryStore`, UserDefaults), brouillon d'annonce
  (`Application Support/PostDrafts`), photos prises en attente d'envoi (`tmp`, purgées après 24 h), export de
  « Mes données » (`tmp`, effacé à la déconnexion), jetons de session (trousseau), cache des images.
- Compteur de vues (`POST /api/annonces/{id}/view`) : simple compteur anonyme de l'annonce ; l'adresse IP ne
  sert qu'à l'anti-abus (une vue par IP et par annonce toutes les 30 min).
- Présence « En ligne » et « écrit… » : diffusées en temps réel entre les deux interlocuteurs, sans
  enregistrement.
- Langue de l'app envoyée au compte (`PUT /api/users/me`, pour la langue des e-mails et des notifications) :
  réglage du compte, sans type Apple correspondant.
- Adresse IP et journaux techniques du serveur (sécurité, limitation des abus) : pas un type Apple à part ; elle
  ne sert pas à localiser (la localisation approximative est déjà cochée pour la wilaya).

## Divergences avec la fiche Play (à signaler au propriétaire)

| # | Point | iOS | Play aujourd'hui | À faire |
|---|---|---|---|---|
| 1 | Journal serveur des recherches (sans compte) | déclaré (Historique des recherches, Analyse) | absent (seul l'historique local est cité) | ajouter « Historique des recherches dans l'app » au formulaire Play |
| 2 | Personnalisation « Pour vous » (favoris, alertes) | finalité déclarée | finalité absente | ajouter « Personnalisation » côté Play |
| 3 | Identifiant utilisateur | déclaré | absent | ajouter « Identifiants utilisateur » côté Play |
| 4 | Formulaire de contact | Service client | non cité | facultatif côté Play |
| 5 | Connexion Apple (nom, e-mail éventuellement relais) | couvert par Nom / E-mail | sans objet | — |
| 6 | Historique de recherche local, brouillons, jetons | non collectés (restent sur l'iPhone) | cité dans « Activité » | rien à changer |
| 7 | Télémétrie des SDK Firebase (diagnostics « Analyse », « autres types de données ») | déclarée (manifestes Firebase) | absente (Crashlytics seul, « Stabilité ») | vérifier la fiche « Sécurité des données » publiée par Google pour les SDK Firebase Android ; compléter si besoin |
| 8 | Utilisateurs bloqués (transmis à la modération, lot B) | Autre contenu | non cité | ajouter aux « Contenus générés par l'utilisateur » côté Play une fois le lot B en ligne |
| 9 | Prestataires dans la politique de confidentialité | — | Firebase cité pour Android seulement ; OpenRouter et Apple absents | **réglé par le lot C** (section 14 « Application iOS », Apple, OpenRouter et Google, Firebase Android et iOS) : à fusionner avant la soumission |

Le lot C fait aussi mentionner iOS dans la page de suppression de compte (révocation Apple).

## Saisie dans App Store Connect

1. App → **Confidentialité de l'app** → URL de la politique de confidentialité (une par langue, voir les
   fiches), puis **Commencer**.
2. « Collectez-vous des données ? » → **Oui** → cocher exactement les 15 types du tableau → Enregistrer.
3. Pour chaque type : finalités cochées comme dans le tableau → « Lié à l'identité ? » → « Utilisé pour
   le suivi ? » **Non**.
4. Vérifier l'aperçu : « Données liées à vous » (12 types), « Données non liées à vous » (3 types : données de
   plantage, autres données de diagnostic, autres types de données), aucune « Données utilisées pour vous
   suivre ». Puis **Publier**. La section doit être publiée avant la soumission.

Contrôle facultatif sur un Mac : Xcode → Organizer → archive → clic droit → **Generate Privacy Report** (PDF qui
réunit le manifeste de l'app et ceux de Firebase) ; chaque type du rapport doit figurer dans le tableau.

## API à raison obligatoire (manifeste)

Apple exige une raison déclarée pour certaines API. Relevé du code de l'APP (`Weyda/`, phase 7) ; Firebase et
GoogleUtilities déclarent les leurs dans leurs propres manifestes (rien à recopier) :

| Catégorie | Raison | Utilisée par | Déclarée |
|---|---|---|---|
| UserDefaults | **CA92.1** (données lues et écrites par l'app seule) | `LaunchOptions` (arguments des tests), `SearchHistoryStore`, `PushRegistrar` (autorisation déjà demandée), `KeychainSessionStorage` (première installation), `HomeView` / `DetailView` (feuilles des tests, Debug) | oui |
| Horodatage de fichiers | **C617.1** (fichiers du conteneur de l'app) | `ImageDiskCache` (Caches/WeydaImages : date de modification lue et réécrite pour éliminer les moins récemment lus), `AccountDataRepository.purgeStaleCaptures` (photos de plus de 24 h dans `tmp`) | oui |
| Heure de démarrage du système | — | aucune (`systemUptime`, `mach_absolute_time` absents) | non |
| Espace disque | — | aucune (`volumeAvailableCapacity`, `systemFreeSize`, `statfs` absents) | non |
| Claviers actifs | — | aucune (`activeInputModes` absent) | non |

Commande de contrôle (Git Bash, à la racine du dépôt), à relancer quand le code change :
`grep -rnE "UserDefaults|@AppStorage|contentModificationDate|creationDate|contentAccessDate|attributesOfItem|modificationDate|getattrlist|systemUptime|mach_absolute_time|volumeAvailableCapacity|systemFreeSize|statfs|activeInputModes" Weyda/`

Contrôles sans Mac :
- `WeydaTests/PrivacyManifestTests.swift` (à chaque CI) : le manifeste est dans l'app, se lit, ne déclare
  aucun suivi, chaque catégorie a une raison bien formée, UserDefaults et horodatage de fichiers sont présents.
- `ios-release` avertit si `PrivacyInfo.xcprivacy` manque à la racine de l'app archivée.
- À chaque envoi TestFlight, Apple vérifie le binaire et signale par e-mail une API non déclarée
  (`ITMS-91053: Missing API declaration`, avec la catégorie) — bloquant à l'envoi.
