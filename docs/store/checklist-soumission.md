# Check-list de soumission — App Store Connect

> Ce que le propriétaire fait, dans l'ordre, avec les renvois aux fichiers de ce dossier. Les étapes 1 à 8
> se font une fois (dès que le compte Apple Developer est actif) ; les étapes 9 à 16 le jour de la
> soumission. Aucun secret ni donnée personnelle dans ce dépôt public : les valeurs se saisissent dans
> App Store Connect ou dans le coffre GitHub. Publication côté CI : [`docs/RELEASE.md`](../RELEASE.md).

## A. Préparatifs (une fois)

1. **Compte Apple Developer actif** ; dans App Store Connect → Affaires, accepter les contrats proposés
   (une app gratuite n'a besoin ni de contrat « Apps payantes » ni de coordonnées bancaires). Noter le
   **Team ID** (page Membership).
2. **Identifiant d'app** : Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App →
   « Weydaa », bundle explicite `com.weydaa.app`, capacités **Sign in with Apple**, **Push
   Notifications**, **Associated Domains** (cochables plus tard, aux phases 3 et 5).
3. **Appareil** : Devices → **+** → l'iPhone du propriétaire (UDID). Probablement exigé par la signature
   automatique de l'archive (`docs/RELEASE.md`, Dépannage) ; utile aussi pour un build de développement.
4. **App dans App Store Connect** : Apps → **+** → Nouvelle app → iOS, nom `Weydaa – Petites annonces`
   (`fiche-fr.md`), langue principale **Français**, bundle `com.weydaa.app`, SKU au choix (ex.
   `weydaa-ios`), accès complet.
5. **Clé API** : Utilisateurs et accès → Intégrations → App Store Connect API → **Clés d'équipe** →
   générer « GitHub Actions », accès **Admin** → télécharger le `.p8` (une seule fois possible), noter le
   Key ID et l'Issuer ID.
6. **Secrets GitHub** du dépôt `aniis934/weydaa-ios` (Settings → Secrets and variables → Actions) :
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contenu du `.p8`), `APPLE_TEAM_ID`, `SUPABASE_HOST`,
   `SUPABASE_ANON_KEY`, puis `GOOGLE_SERVICE_INFO_PLIST` à la phase 5. Détail : `docs/RELEASE.md`.
7. **Premier build** : Actions → `ios-release` → Run workflow (branche `main`, notes de version) → e-mail
   d'Apple quand le build est traité (5 à 30 min).
8. **TestFlight** : onglet TestFlight → Tests internes → **+** groupe « Interne » → s'y ajouter (avec la
   distribution automatique des nouveaux builds) → installer l'app TestFlight sur l'iPhone → installer
   Weydaa → test final guidé (plan, ~30 min).

## B. Le jour de la soumission

9. **Prérequis serveur** : lots A (connexion Apple, révocation), B (modération, utilisateurs bloqués,
   CGU « tolérance zéro » et délai de traitement) et C (politique de confidentialité et page de
   suppression qui citent iOS, Apple et OpenRouter) déployés. Comptes de démo prêts (`review-notes.md`).
10. **Informations sur l'app** (pour chaque langue : Français, puis **+** Arabe et Anglais) : nom et
    sous-titre (`fiche-fr.md`, `fiche-ar.md`, `fiche-en.md`) ; catégorie principale **Shopping**
    (secondaire facultative : Style de vie) ; droits sur le contenu : **oui, l'app affiche du contenu de
    tiers** (annonces des utilisateurs) et nous avons les droits nécessaires (licence des CGU).
11. **Classification par âge** : questionnaire selon `age-rating.md` (conseil : relever à 18+).
12. **Confidentialité de l'app** : URL de la politique par langue, puis le questionnaire selon
    `app-privacy.md` → **Publier**.
13. **Prix et disponibilité** : gratuit ; pays selon la décision en attente (Algérie seule, ou aussi la
    France / l'UE). Si un pays de l'UE est coché : déclarer le statut de **commerçant** (Digital Services
    Act, rubrique dédiée d'App Store Connect) ; adresse et téléphone publics exigés pour un commerçant.
14. **Page de la version 1.0.0** (chaque langue) :
    - captures 6,9" dans l'ordre de `screenshots.md` ;
    - texte promotionnel, description, mots-clés, URL d'assistance et URL marketing (fiches) ;
    - « Nouveautés » : absent pour la première version (texte prêt dans les fiches) ;
    - le numéro de version de la page doit être **1.0.0**, identique à `MARKETING_VERSION` de `project.yml`
      (sinon le build n'est pas sélectionnable) ;
    - **Build** : choisir le build testé dans TestFlight (conformité du chiffrement déjà réglée :
      `ITSAppUsesNonExemptEncryption = NO` dans l'Info.plist, HTTPS seulement) ;
    - **Copyright** : `2026 Weydaa` (ou le nom légal du titulaire) ;
    - **Informations pour la revue** : « Connexion requise » cochée + compte de démo, coordonnées du
      contact (saisies ici seulement), notes en anglais (`review-notes.md`) ;
    - **Publication de la version** : « Publier manuellement » pour la première.
15. **Ajouter pour la revue → Soumettre**. Délai habituel : 24 à 48 h. Répondre aux messages du Centre de
    résolution (en anglais), corriger, renvoyer un build si besoin (`ios-release`, build suivant).
16. **Après l'acceptation** : publier ; vérifier la fiche en fr / ar / en sur un iPhone ; garder le compte B
    et son annonce de test le temps des mises à jour ou les retirer ; mettre à jour `docs/PLAN.md` et
    `docs/EN-ATTENTE.md`.

## Pièges connus

- Nom refusé ou déjà pris : `Weydaa` seul, description dans le sous-titre (`fiche-fr.md`).
- Mots-clés : limite exprimée en octets par Apple (les listes tiennent dans 100 octets).
- Captures : 1320 × 2868 exactement, sans canal alpha, rien qui évoque une autre plateforme mobile.
- Politique de confidentialité qui ne mentionne pas iOS : rejet fréquent (règle 5.1.1) → lot C d'abord.
- Connexion Google sans connexion Apple, ou suppression de compte introuvable dans l'app : rejets 4.8 et
  5.1.1(v) → tout est décrit dans `review-notes.md`.
