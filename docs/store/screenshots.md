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

## Production : le tour automatique, sans Mac (en place depuis la phase 7)

Captures **avec légende**, produites par la CI sur un simulateur iPhone 17 Pro Max, en API simulée (jamais la
prod), sans compte Apple ni Mac. C'est aussi la seule façon d'avoir des légendes arabes composées par le
système (de droite à gauche, SF Arabic).

1. **Mode vitrine** (Debug + API simulée seulement, jamais en Release) : l'argument `-WeydaStoreCaption <n>`
   (1 à 8) enveloppe la racine de l'app dans `StoreFrame` (`Weyda/DesignSystem/Showcase/StoreFrame.swift`,
   branché par une ligne `.storeFrame()` dans `RootView`). Rendu : fond vert de la marque (Emerald 700, celui
   de l'écran de lancement), en haut le W de la marque et la légende n en blanc, grand et gras, centrée, deux
   lignes au plus ; dessous, l'app réduite à 80 % dans un cadre aux coins continus, ombre douce. L'app est mise
   en page à la taille de la zone utile du téléphone (même cadrage que le tour de captures) puis réduite au
   rendu seulement. Barre d'état masquée en vitrine (l'heure noire du mode clair jurait sur le vert). Les
   légendes sont les clés `store_caption_1` … `store_caption_8` du catalogue (`scripts/ios-strings.json`,
   textes du tableau ci-dessus).
2. **Tour dédié** `WeydaUITests/StoreShotsTests.swift` : une méthode par écran ; chacune ouvre l'app
   DIRECTEMENT sur l'état voulu par les arguments de lancement (aucun appui à travers le cadre réduit), attend
   le contenu et les photos simulées, puis capture :

   | # | Capture | Arguments de lancement (en plus de `-WeydaStoreCaption n`) |
   |---|---|---|
   | 1 | `store-01-accueil` | `-WeydaRoute tab:home` (visiteur) |
   | 2 | `store-02-annonces` | `-WeydaRoute listings:category=vehicules&subcategory=voitures` (6 voitures, puces et « Filtres » actifs) |
   | 3 | `store-03-fiche` | `-WeydaRoute detail:mock-a2` (Clio « à la une », galerie 1 / 8, visiteur) |
   | 4 | `store-04-messagerie` | `-WeydaRoute chat:mock-c1 -WeydaLoggedIn YES` (contre-offre : Accepter / Contrer / Refuser) |
   | 5 | `store-05-depot` | `-WeydaRoute tab:post -WeydaPostDraft step-attributes -WeydaLoggedIn YES` |
   | 6 | `store-06-vendeur` | `-WeydaRoute seller:mock-u1` (Karim B., 4,8, avis) |
   | 7 | `store-07-favoris` | `-WeydaRoute favorites -WeydaLoggedIn YES` (5 favoris) |
   | 8 | `store-08-sombre` | `-WeydaRoute tab:home`, passage sombre |

   Écrans 1 à 7 au passage clair seulement, écran 8 au passage sombre seulement (les autres méthodes sont
   « ignorées ») : `screens.sh` transmet l'apparence au test (`TEST_RUNNER_WEYDA_APPEARANCE`). Écran 2 : avec
   la wilaya en plus, l'API simulée n'a que 2 voitures (écran à moitié vide) et le prix n'est pas porté par
   `-WeydaRoute` ; catégorie + sous-catégorie donnent une liste pleine.
3. **Marques** (règle 2.3.10) : cadrages relus sur les captures de la phase 6, aucune autre plateforme mobile
   visible. Les annonces simulées « Samsung Galaxy S23 Ultra » (mock-a6) et « Xiaomi Redmi Note 13 Pro »
   (mock-a21) existent mais restent hors champ (3e carte « À la une », 6e carte « Tendances », bas des
   « Récentes ») ; un iPhone serait toléré. Tout changement de cadrage → revérifier.
4. **Lancement** (les deux passages dans la même exécution) :

   ```
   gh workflow run ios-screens.yml --ref <branche> -f tests="StoreShotsTests" \
     -f devices="iPhone 17 Pro Max" -f languages="fr ar en" -f appearances="light dark"
   gh run download <id> -D <dossier>
   ```

   Un artefact par langue, `ios-screens-iPhone-17-Pro-Max-<langue>` : `<langue>-light/store-01…07.png` et
   `<langue>-dark/store-08-sombre.png` (PNG du simulateur, 1320 × 2868).
5. **Format final** : l'orchestrateur vérifie 1320 × 2868, convertit en **JPEG qualité 95 sans canal alpha**
   et range les fichiers sous `docs/store/captures/<langue>/0N-<nom>.jpg` (`fr`, `ar`, `en`) :
   `01-accueil`, `02-annonces`, `03-fiche`, `04-messagerie`, `05-depot`, `06-vendeur`, `07-favoris`,
   `08-sombre`.
6. **Relecture** : les 24 captures (8 × 3 langues) relues comme à chaque phase (RTL, débordements, texte
   tronqué, légende sur deux lignes au plus), puis déposées à la main dans App Store Connect, langue par
   langue (glisser-déposer, dans l'ordre). Photos des annonces : dessinées par script ; des photos libres de
   droits ou du propriétaire restent possibles (décision en attente, `docs/EN-ATTENTE.md`) — jamais la photo
   d'un vrai utilisateur.

## Vérifications avant l'envoi

- L'app en usage, pas seulement un écran de connexion ou un logo (règle 2.3.3) ; aucun prix ni
  promotion inventés.
- Aucun nom, téléphone, e-mail ou photo d'une vraie personne.
- Les fonctions montrées existent dans le build soumis.
