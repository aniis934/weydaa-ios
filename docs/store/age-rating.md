# Classification par âge — questionnaire d'App Store Connect

> Système d'Apple en vigueur depuis 2025 : **4+, 9+, 13+, 16+, 18+** (iOS 26), avec de nouvelles
> questions (contrôles intégrés, capacités, santé ou bien-être, violence). Les intitulés ci-dessous suivent
> l'écran d'App Store Connect ; s'il a un peu changé le jour J, répondre selon le sens. Les questions de
> contenu se répondent par Aucun / Peu fréquent / Fréquent, les autres par Oui / Non.
> Base : la classification Play (IARC) de l'app Android — interactions entre utilisateurs : oui ; partage
> de position : non ; achats : non ; public cible 18 ans et plus.

## Ce qu'est l'app pour Apple

Une place de marché de petites annonces : contenu **publié par les utilisateurs** (annonces, photos, avis,
bio du profil), **messagerie** privée entre acheteurs et vendeurs avec offres de prix et notifications push,
**modération** (vérification avant mise en ligne, dont une analyse automatique ; signalement d'une annonce ou
d'un utilisateur ; blocage, transmis à la modération, avec la liste Profil → « Utilisateurs bloqués » ;
signalements traités sous 24 heures, §5 des CGU du lot B), aucune publicité, aucun achat, aucun navigateur.
Les CGU réservent l'inscription aux personnes majeures et interdisent armes, drogues, médicaments sans
ordonnance, animaux protégés, contrefaçons, contenus sexuels ou haineux.

Relu en phase 7 d'après l'app réelle (phases 5 et 6) : aucune réponse ne change, les fonctions sociales
ajoutées (offres, avis, blocage, push) relèvent des deux capacités déjà cochées ci-dessous.

## Réponses

| Section | Question | Réponse | Justification |
|---|---|---|---|
| Contrôles intégrés | Contrôle parental | Non | aucun réglage parental dans l'app |
| Contrôles intégrés | Vérification de l'âge (age assurance) | Non | âge déclaré par les CGU, non vérifié techniquement |
| Capacités | Accès non restreint au Web | **Non** | pas de navigateur : seules les pages légales de weydaa.com s'ouvrent, dans une vue Safari intégrée (`SFSafariViewController`), sans barre d'adresse libre ; la connexion Google passe par la feuille d'authentification du système |
| Capacités | Contenu généré par les utilisateurs | **Oui** | annonces, photos, avis, profils publics (bio) |
| Capacités | Messagerie et discussion | **Oui** | messagerie privée acheteur / vendeur, offres de prix, notifications push |
| Capacités | Publicité | Non | aucune publicité ni SDK publicitaire |
| Thèmes pour adultes | Grossièretés ou humour cru | Aucun | interdit par les CGU, annonces vérifiées avant publication, signalement |
| Thèmes pour adultes | Horreur, peur | Aucun | |
| Thèmes pour adultes | Alcool, tabac, drogues (usage ou références) | Aucun | drogues interdites ; si la modération laisse passer des annonces d'articles pour fumeurs (chicha, cigarette électronique) : répondre **Peu fréquent** |
| Médical, bien-être | Informations médicales ou de traitement | Aucun | médicaments interdits par les CGU |
| Médical, bien-être | Santé ou bien-être | Aucun | |
| Sexualité, nudité | Thèmes suggestifs | Aucun | contenus sexuels interdits, modération |
| Sexualité, nudité | Contenu sexuel ou nudité | Aucun | |
| Sexualité, nudité | Contenu sexuel explicite | Aucun | |
| Violence | Violence de dessin animé ou fantastique | Aucun | |
| Violence | Violence réaliste | Aucun | |
| Violence | Violence réaliste prolongée, crue ou sadique | Aucun | |
| Violence | Armes à feu ou autres armes | Aucun | armes interdites par les CGU |
| Jeux de hasard | Jeux de hasard simulés | Aucun | |
| Jeux de hasard | Jeux d'argent réels | Non | |
| Jeux de hasard | Concours | Non | |
| Jeux de hasard | Coffres à butin (loot boxes) | Non | |
| Fin | Conçue pour les enfants (Kids) | Non | |

## Note obtenue et note conseillée

La note calculée s'affiche à la fin du questionnaire : avec ces réponses, elle devrait être basse (4+ ou
9+), les capacités « contenu des utilisateurs » et « messagerie » étant affichées à part sur la fiche ;
le barème exact d'Apple n'est pas public, donc le vérifier à l'écran.

**Conseil : relever la note à 18+** (option « Classification plus élevée » en fin de questionnaire), pour
rester cohérent avec :
- les CGU (inscription réservée aux personnes majeures ; la majorité civile algérienne est même à 19 ans) ;
- la fiche Play (public cible 18 ans et plus) ;
- la nature du service : rencontres en personne entre inconnus pour conclure une vente.

Conséquence : l'app n'est pas proposée aux comptes Apple de mineurs (Temps d'écran, partage familial).
Garder la note calculée reste possible si le propriétaire veut ouvrir la consultation aux mineurs ; il
faudrait alors aligner les CGU et la fiche Play.

## Rappels liés (App Review)

- Règle 1.2 (contenu des utilisateurs) : filtrage, signalement, blocage, coordonnées publiques — tout est
  décrit dans `review-notes.md`.
- Si l'app est un jour distribuée aux États-Unis, certaines lois d'États (Texas, Utah) imposent des
  signaux d'âge (API « Declared Age Range » d'Apple) : sans objet pour l'Algérie et l'UE.
