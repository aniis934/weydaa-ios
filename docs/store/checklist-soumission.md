# Check-list de soumission — App Store Connect

> Ce que le propriétaire fait, dans l'ordre, avec les renvois aux fichiers de ce dossier. Partie A : une fois
> (dès que le compte Apple Developer est actif) ; partie B : le jour de la soumission. Aucun secret ni donnée
> personnelle dans ce dépôt public : les valeurs se saisissent dans App Store Connect, Firebase, Vercel ou le
> coffre GitHub. Publication côté CI : [`docs/RELEASE.md`](../RELEASE.md). Suivi : `docs/EN-ATTENTE.md`.

## L'ordre en une ligne

Compte Apple → App ID et ses 3 capacités → clés Apple (Sign in with Apple, APNs) → Firebase (app iOS + clé APNs)
→ Google Cloud (client OAuth iOS) → Vercel (variables du lot A) → lots serveur A, B, C fusionnés et déployés →
secrets GitHub → `ios-release` → TestFlight et test final → fiche, confidentialité, âge → soumission.

## A. Préparatifs (une fois)

1. **Compte Apple Developer actif** ; dans App Store Connect → Affaires, accepter les contrats proposés
   (une app gratuite n'a besoin ni de contrat « Apps payantes » ni de coordonnées bancaires). Noter le
   **Team ID** (page Membership).
2. **Identifiant d'app** : Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App →
   « Weydaa », bundle explicite `com.weydaa.app`, cocher les **3 capacités** que demande l'app en Release
   (`Config/Weyda.entitlements`) :
   - **Sign in with Apple** (« Enable as a primary App ID ») ;
   - **Push Notifications** (sans certificat : la clé APNs de l'étape 6 suffit) ;
   - **Associated Domains** (liens universels et mots de passe partagés avec weydaa.com).
   La signature automatique de la CI (clé Admin) sait les activer seule, mais les cocher ici évite un échec
   « Profil de provisionnement » au premier build (`docs/RELEASE.md`, Dépannage).
3. **Appareil** : Devices → **+** → l'iPhone du propriétaire (UDID). Probablement exigé par la signature
   automatique de l'archive (`docs/RELEASE.md`, Dépannage) ; utile aussi pour un build de développement.
4. **App dans App Store Connect** : Apps → **+** → Nouvelle app → iOS, nom `Weydaa – Petites annonces`
   (`fiche-fr.md`), langue principale **Français**, bundle `com.weydaa.app`, SKU au choix (ex.
   `weydaa-ios`), accès complet.
5. **Clé API** : Utilisateurs et accès → Intégrations → App Store Connect API → **Clés d'équipe** →
   générer « GitHub Actions », accès **Admin** → télécharger le `.p8` (une seule fois possible), noter le
   Key ID et l'Issuer ID.
6. **Clés Apple** (Certificates, Identifiers & Profiles → Keys → **+**) : une clé **Sign in with Apple**
   (liée à `com.weydaa.app`) pour le serveur (lot A) et une clé **Apple Push Notifications service (APNs)**
   pour Firebase. Chaque `.p8` ne se télécharge qu'une fois : le ranger hors du dépôt, noter son Key ID.
7. **Firebase** (projet `weydaa-964df`, celui de l'app Android) :
   - Paramètres du projet → **Ajouter une app** → iOS → bundle `com.weydaa.app` → télécharger
     `GoogleService-Info.plist` (ne jamais le mettre dans le dépôt) ;
   - Paramètres du projet → **Cloud Messaging** → app iOS → **Clé d'authentification APNs** → envoyer le `.p8`
     APNs, avec son Key ID et le Team ID (la même clé sert au développement et à la production, donc à
     TestFlight) ;
   - **Crashlytics** : rien à installer, l'app est prête ; le tableau de bord se remplit au premier plantage
     d'un build Release (TestFlight compris). Les symboles (dSYM) partent seuls à chaque `ios-release`.
8. **Google Cloud** : identifiants → client OAuth de type **iOS** pour `com.weydaa.app`. Son identifiant va
   (a) sur Vercel (`AUTH_GOOGLE_IOS_ID`, lot A) et (b) dans le secret GitHub **`GOOGLE_IOS_CLIENT_ID`** du dépôt
   iOS (`ios-release` l'écrit dans `Config/Secrets.xcconfig`, comme Supabase). Sans (b), le bouton « Continuer avec
   Google » est masqué dans le build (le résumé du workflow le dit) : retirer alors Google des fiches et des notes de revue.
9. **Vercel** (variables du lot A) : `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (contenu du `.p8`
   Sign in with Apple), `APPLE_BUNDLE_ID` (= `com.weydaa.app`), `AUTH_GOOGLE_IOS_ID`. Puis, côté Apple :
   « Sign in with Apple for Email Communication » → déclarer weydaa.com et l'adresse d'envoi (SPF, DKIM),
   sinon les e-mails vers les adresses relais d'Apple ne partent pas.
10. **Lots serveur**, relus puis fusionnés et déployés dans cet ordre :
    - **A** (connexion Apple et Google iOS, révocation Apple à la suppression, fichier des liens universels) :
      avant de tester la connexion Apple sur l'iPhone ;
    - **B** (notifications iOS, liste des utilisateurs bloqués, blocage transmis à la modération, §5 des CGU :
      « tolérance zéro » et signalements traités sous 24 heures) : avant de tester le push ;
    - **C** (politique de confidentialité : section 14 « Application iOS », Apple, OpenRouter et Google,
      Firebase Android et iOS ; page de suppression qui cite iOS) : avant la soumission.
    Ensuite, vérifier que `https://weydaa.com/.well-known/apple-app-site-association` et la même adresse sur
    `www.weydaa.com` répondent (JSON qui cite `<Team ID>.com.weydaa.app`, sans redirection).
11. **Secrets GitHub** du dépôt `aniis934/weydaa-ios` (Settings → Secrets and variables → Actions) :
    `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contenu du `.p8` de la clé API), `APPLE_TEAM_ID`,
    `SUPABASE_HOST`, `SUPABASE_ANON_KEY` (temps réel), `GOOGLE_SERVICE_INFO_PLIST` (contenu du fichier
    Firebase : push et Crashlytics). Détail : `docs/RELEASE.md`.
12. **Premier build** : Actions → `ios-release` → Run workflow (branche `main`, notes de version) → e-mail
    d'Apple quand le build est traité (5 à 30 min). Le résumé du run doit dire « Firebase : oui » et
    « Temps réel : oui », sans avertissement « Manifeste de confidentialité absent ».
13. **TestFlight** : onglet TestFlight → Tests internes → **+** groupe « Interne » → s'y ajouter (avec la
    distribution automatique des nouveaux builds) → installer l'app TestFlight sur l'iPhone → installer
    Weydaa → test final guidé (~30 min) : connexion Apple et Google, dépôt avec l'appareil photo, message et
    offre avec un second compte, push (app fermée, au premier plan, appui → le bon fil), lien weydaa.com
    ouvert depuis Notes, blocage puis « Utilisateurs bloqués », suppression d'un compte créé avec Apple.

## B. Le jour de la soumission

14. **Prérequis** : lots A, B et C en ligne ; comptes de démo prêts (`review-notes.md`) ; build testé dans
    TestFlight.
15. **Informations sur l'app** (pour chaque langue : Français, puis **+** Arabe et Anglais) : nom et
    sous-titre (`fiche-fr.md`, `fiche-ar.md`, `fiche-en.md`) ; catégorie principale **Shopping**
    (secondaire facultative : Style de vie) ; droits sur le contenu : **oui, l'app affiche du contenu de
    tiers** (annonces des utilisateurs) et nous avons les droits nécessaires (licence des CGU).
16. **Classification par âge** : questionnaire selon `age-rating.md` (conseil : relever à 18+).
17. **Confidentialité de l'app** : URL de la politique par langue, puis le questionnaire selon
    `app-privacy.md` (15 types) → **Publier**.
18. **Prix et disponibilité** : gratuit ; pays selon la décision en attente (Algérie seule, ou aussi la
    France / l'UE). Si un pays de l'UE est coché : déclarer le statut de **commerçant** (Digital Services
    Act, rubrique dédiée d'App Store Connect) ; adresse et téléphone publics exigés pour un commerçant.
19. **Page de la version 1.0.0** (chaque langue) :
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
20. **Ajouter pour la revue → Soumettre**. Délai habituel : 24 à 48 h. Répondre aux messages du Centre de
    résolution (en anglais), corriger, renvoyer un build si besoin (`ios-release`, build suivant).
21. **Après l'acceptation** : publier ; vérifier la fiche en fr / ar / en sur un iPhone ; garder le compte B
    et son annonce de test le temps des mises à jour ou les retirer ; mettre à jour `docs/PLAN.md` et
    `docs/EN-ATTENTE.md`.

## Pièges connus

- Nom refusé ou déjà pris : `Weydaa` seul, description dans le sous-titre (`fiche-fr.md`).
- Mots-clés : limite exprimée en octets par Apple (les trois listes tiennent dans 100 octets, comptés par script).
- Captures : 1320 × 2868 exactement, sans canal alpha, rien qui évoque une autre plateforme mobile.
- Politique de confidentialité qui ne mentionne pas iOS : rejet fréquent (règle 5.1.1) → lot C d'abord.
- Connexion Google sans connexion Apple, ou suppression de compte introuvable dans l'app : rejets 4.8 et
  5.1.1(v) → tout est décrit dans `review-notes.md`.
- Liste « Utilisateurs bloqués » vide ou push sans alerte sur iPhone : lot B pas encore en ligne.
- E-mail `ITMS-91053` (API non déclarée) : compléter `Weyda/Resources/PrivacyInfo.xcprivacy` et `app-privacy.md`.
- Fonction citée dans la fiche mais absente du build (Google sans identifiant client, temps réel sans
  secrets Supabase) : règle 2.3.1 → retirer la mention ou compléter le build.
