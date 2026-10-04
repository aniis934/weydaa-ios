# Fiche App Store — français (langue principale)

> Textes à coller dans App Store Connect, localisation **Français**, version **1.0.0**. Adaptés de la
> fiche Play (dépôt privé, `android/docs/store/fiche-fr.md`) : aucune mention d'Android ni de Google Play
> (règle 2.3.10 d'Apple), ajout de l'iPhone, de la connexion avec Apple et de la photothèque.
> Comptes faits par script (caractères Unicode ; octets UTF-8 en plus pour les mots-clés, voir la note).
> **À relire avant la soumission** : chaque fonction citée doit être présente dans le build envoyé.

| Champ | Limite | Écran d'App Store Connect | Compte |
|---|---|---|---|
| Nom | 30 | Informations sur l'app | 25 |
| Sous-titre | 30 | Informations sur l'app | 28 |
| Texte promotionnel | 170 | Page de la version (modifiable sans nouvelle version) | 161 |
| Description | 4 000 | Page de la version | 2 655 |
| Mots-clés | 100 | Page de la version | 95 caractères / 97 octets |
| Nouveautés | 4 000 | Page de la version (absent pour la toute première version) | 183 |

## Nom (30 caractères max)

```
Weydaa – Petites annonces
```
25 caractères. Le nom doit être unique sur l'App Store. Si Apple le refuse (règle 2.3.7 : pas de
description dans le nom) ou s'il est pris : `Weydaa` seul, la description passant dans le sous-titre.

## Sous-titre (30 caractères max)

```
Achetez et vendez en Algérie
```
28 caractères.

## Texte promotionnel (170 caractères max)

```
Voitures, immobilier, téléphones : publiez une annonce en quelques minutes et discutez en direct avec les acheteurs, partout en Algérie. Gratuit, sans publicité.
```
161 caractères. Modifiable à tout moment, sans nouvelle version ni nouvelle revue.

## Description (4 000 caractères max)

```
Weydaa est la marketplace algérienne pour acheter et vendre près de chez vous. Voitures, immobilier, téléphones, meubles, mode : déposez votre annonce en quelques minutes depuis votre iPhone et discutez directement avec les acheteurs.

DÉPOSER UNE ANNONCE EN QUELQUES MINUTES
• Choisissez la catégorie, l'application propose les bons champs : marque et modèle pour une voiture, surface et nombre de pièces pour un logement, état et capacité pour un téléphone.
• Ajoutez jusqu'à 5 photos depuis la photothèque ou l'appareil photo (8 pour les vendeurs recommandés).
• Indiquez votre wilaya et votre commune parmi les 58 wilayas d'Algérie.
• Publiez : votre annonce est vérifiée puis mise en ligne.

TROUVER EXACTEMENT CE QUE VOUS CHERCHEZ
• Recherche instantanée avec suggestions et historique.
• Filtres par sous-catégorie, wilaya, commune, prix, type de prix et caractéristiques (marque, carburant, année…).
• Tri par date, par prix ou par pertinence.
• Favoris : gardez vos annonces sous la main.
• Alertes : enregistrez une recherche et retrouvez-la en un geste.

DISCUTER ET NÉGOCIER
• Messagerie intégrée avec le vendeur, messages en temps réel.
• Faites une offre de prix : le vendeur accepte, refuse ou propose un contre-prix, tout reste dans la conversation.
• Accusés de lecture et archivage des conversations.
• Notifications pour les nouveaux messages, les offres et l'état de vos annonces.
• Après avoir contacté un vendeur, laissez-lui un avis : toute la communauté s'y fie.
• Signalez une annonce ou un utilisateur, bloquez qui vous importune : notre équipe de modération examine chaque signalement.

GÉRER SES ANNONCES
• Toutes vos annonces au même endroit : en ligne, en vérification, vendues, expirées.
• Modifier, marquer vendu, renouveler ou supprimer en deux touches.
• Statistiques : vues, favoris reçus, messages reçus.

PENSÉE POUR L'ALGÉRIE ET POUR L'IPHONE
• Trois langues : français, العربية, English, avec une interface entièrement adaptée à l'écriture de droite à gauche.
• Les 58 wilayas et leurs communes, des prix en dinars.
• Connexion par e-mail, avec Apple ou avec Google.
• Thème clair ou sombre, comme votre iPhone ; textes agrandis et VoiceOver pris en charge.

VOS DONNÉES VOUS APPARTIENNENT
• Exportez à tout moment un fichier contenant votre profil, vos annonces, vos messages, vos favoris et vos avis.
• Supprimez votre compte depuis l'application : effacement réel, pas une simple désactivation.
• Aucune publicité, aucun traceur publicitaire, aucune localisation GPS.

Weydaa, c'est aussi weydaa.com : vos annonces y sont visibles, et votre compte e-mail ou Google fonctionne sur le site comme dans l'application.
```
2 655 caractères.

Différences avec la fiche Play : « photothèque » (terme iOS) ; connexion avec Apple ; avis sur les
vendeurs ; thème qui suit l'iPhone, VoiceOver et textes agrandis (phase 6) ; la dernière phrase ne promet
plus « le même compte partout » (un compte créé avec Apple et une adresse masquée ne se connecte pas
encore sur le site, voir le plan) ; plus de « notifications même application fermée » (vrai sur iOS aussi,
mais seulement une fois Firebase et la clé APNs en place, phase 5).

## Mots-clés (100 max, virgules sans espace)

```
voiture,occasion,immobilier,location,appartement,téléphone,meuble,emploi,vente,achat,alger,oran
```
95 caractères, 97 octets. Aucun mot du nom ni du sous-titre (Apple les indexe déjà), aucun nom de
concurrent (règle 2.3.7). Note : l'aide d'Apple exprime cette limite en **octets** (une lettre accentuée
ou arabe en compte 2) ; les trois listes tiennent dans 100 octets.

## Nouveautés de la version 1.0.0

```
Première version de Weydaa sur iPhone : parcourez les annonces de toute l'Algérie, publiez les vôtres avec photos, discutez et négociez en direct, en français, en arabe ou en anglais.
```
183 caractères. App Store Connect n'affiche pas ce champ pour la toute première version : ce texte sert
de notes TestFlight (entrée « notes » de `ios-release`) et de base pour la 1.0.1.

## Adresses (URL)

| Champ | URL | Note |
|---|---|---|
| URL d'assistance (obligatoire) | `https://weydaa.com/fr/contact` | formulaire + adresse publique `contact@weydaa.com` |
| URL marketing (facultative) | `https://weydaa.com/fr` | |
| Politique de confidentialité (obligatoire) | `https://weydaa.com/fr/confidentialite` | doit mentionner l'app iOS : lot serveur C |
| Suppression de compte (pour la revue, pas un champ) | `https://weydaa.com/fr/suppression-compte` | page publique, sans connexion |

## Autres champs

- Catégorie principale : **Shopping** (comme Play) ; secondaire facultative : Style de vie.
- Prix : gratuit. Aucun achat intégré, aucun abonnement.
- Copyright : `2026 Weydaa` (ou le nom légal du titulaire du compte, au choix du propriétaire).
