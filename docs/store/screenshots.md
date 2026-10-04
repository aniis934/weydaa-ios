# Captures App Store — plan (iPhone 6,9 pouces)

> Une seule taille est exigée pour un iPhone seul : **6,9 pouces**, portrait, **1320 × 2868** (iPhone 17
> Pro Max ; Apple accepte aussi des tailles voisines comme 1290 × 2796 et réduit lui-même pour les autres
> écrans).
> 1 à 10 captures par langue ; on en prévoit 8, dans l'ordre ci-dessous, en fr, ar et en. Pas d'iPad
> (app iPhone seule). Vidéo d'aperçu facultative (plus tard).

## Les 8 écrans, dans l'ordre

Les deux ou trois premières captures sont celles qu'on voit dans les résultats de recherche : elles
portent l'essentiel (chercher, voir une annonce, discuter).

| # | Écran (données fictives) | Légende fr | Légende ar | Légende en |
|---|---|---|---|---|
| 1 | Accueil : recherche, catégories, « À la une » | Achetez et vendez près de chez vous | بيع وشراء بالقرب منك | Buy and sell near you |
| 2 | Annonces : résultats avec filtres actifs (catégorie, wilaya, prix) | Trouvez vite grâce aux filtres | اعثر بسرعة بفضل الفلاتر | Find it fast with filters |
| 3 | Détail d'une annonce : galerie, prix, caractéristiques, vendeur | Photos en grand, tous les détails | صور كبيرة وكل التفاصيل | Big photos, every detail |
| 4 | Messagerie : fil avec une carte d'offre de prix | Discutez et négociez en direct | تحدّث وتفاوض مباشرة | Chat and negotiate live |
| 5 | Déposer : étape des caractéristiques (voiture) ou des photos | Votre annonce en quelques minutes | إعلانك في دقائق | Post an ad in minutes |
| 6 | Profil d'un vendeur : note, avis, vitrine | Des vendeurs notés par les acheteurs | بائعون يقيّمهم المشترون | Sellers rated by buyers |
| 7 | Favoris et alertes (ou feuille de filtres complète) | Favoris et alertes : rien ne vous échappe | المفضلة والتنبيهات: لا يفوتك شيء | Favorites and alerts |
| 8 | Accueil en mode sombre | Clair ou sombre, en 3 langues | فاتح أو داكن، بثلاث لغات | Light or dark, in 3 languages |

Chaque langue a ses propres captures : l'interface arabe (de droite à gauche) pour la fiche arabe, etc.

## Production : le tour automatique, sans Mac

1. **Données fictives** dans l'API simulée (`Weyda/Mock/MockFixtures`, jamais la prod) : une dizaine
   d'annonces crédibles (voiture, F3 à Oran, électroménager, meubles…), vendeurs aux prénoms inventés,
   une conversation avec offre, un profil avec avis. Prix en dinars, wilayas réelles. Photos : dessinées
   par script par défaut ; pour la fiche, photos libres de droits ou prises par le propriétaire (décision
   en attente, `docs/EN-ATTENTE.md`) — jamais de photo d'un vrai utilisateur. Éviter toute annonce
   montrant une autre plateforme mobile (règle 2.3.10 : pas de « Samsung Galaxy » en vitrine).
2. **Tour dédié** (phase 7) : un test d'interface `StoreShotsTests` (à côté de `TourTests`) ouvre les 8
   écrans dans l'état voulu (filtres posés, galerie ouverte, offre visible) et nomme les captures
   `store-01-accueil` … `store-08-sombre` ; l'écran 8 se prend lors d'un second passage en apparence sombre.
3. **Lancement** : le workflow `ios-screens` existant, réglé sur `devices = iPhone 17 Pro Max`,
   `languages = fr ar en`, `appearances = light` (puis `dark` pour l'écran 8). Barre d'état 9:41, batterie
   pleine, Wi-Fi (déjà forcée par `screens.sh`).
4. **Format** : la capture du simulateur iPhone 17 Pro Max fait exactement 1320 × 2868. Vérifier l'absence
   de canal alpha (`sips -g hasAlpha`) ; si besoin, convertir en JPEG qualité 95 avec `sips` sur le Mac de
   la CI. Nommage final : `fr/01-accueil.jpg`, `ar/01-accueil.jpg`, `en/01-accueil.jpg`…
5. **Légendes** : deux options.
   - **Sans légende** (le plus simple, accepté par Apple) : les captures brutes.
   - **Avec légende** : un mode « vitrine » réservé au Debug (`-WeydaStoreCaption <n>`) affiche la
     légende du tableau en haut, sur fond de marque, et l'écran réduit en dessous ; les légendes vont dans
     `scripts/ios-strings.json` (fr, ar, en) comme toute chaîne. Aucune dépendance, même tour.
6. **Relecture** : les 24 captures (8 × 3 langues) relues comme à chaque phase (RTL, débordements, texte
   tronqué), puis déposées à la main dans App Store Connect, langue par langue (glisser-déposer, dans
   l'ordre).

## Vérifications avant l'envoi

- L'app en usage, pas seulement un écran de connexion ou un logo (règle 2.3.3) ; aucun prix ni
  promotion inventés.
- Aucun nom, téléphone, e-mail ou photo d'une vraie personne.
- Les fonctions montrées existent dans le build soumis.
