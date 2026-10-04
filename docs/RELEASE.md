# Publier Weydaa iOS : TestFlight, puis App Store

> Deux workflows manuels, aucun Mac : `ios-release` (archive signée → TestFlight) et `ios-compat`
> (iOS 16.4 sur un petit iPhone). La fiche, la confidentialité, l'âge, les notes de revue, les captures et
> la check-list du jour J sont dans [`docs/store/`](store/). Dépôt public : jamais de secret ni de donnée
> personnelle ici, seulement des **noms** de secrets.

## Ce qui manque aujourd'hui (dans l'ordre)

| # | Élément | Où | Débloque |
|---|---|---|---|
| 1 | Compte Apple Developer actif (Team ID) | developer.apple.com | tout le reste |
| 2 | App `com.weydaa.app` créée dans App Store Connect (langue fr) | App Store Connect | l'envoi des builds |
| 3 | Clé API **d'équipe**, accès **Admin** → secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` + `APPLE_TEAM_ID` | App Store Connect → Utilisateurs et accès → Intégrations | `ios-release` |
| 4 | iPhone enregistré (UDID) dans Certificates, IDs & Profiles → Devices | portail développeur | probablement la signature automatique de l'archive (voir Dépannage) |
| 5 | Secrets `SUPABASE_HOST`, `SUPABASE_ANON_KEY` (mêmes valeurs que le site) | GitHub → Settings → Secrets | le temps réel dans les builds (sans eux : HTTP seul) |
| 6 | App ID `com.weydaa.app` avec les capacités Sign in with Apple, Push Notifications, Associated Domains | portail développeur → Identifiers | la signature de l'archive (entitlements de Release, voir plus bas) |
| 7 | App iOS dans Firebase + clé APNs déposée → secret `GOOGLE_SERVICE_INFO_PLIST` | Firebase (projet `weydaa-964df`) | push et Crashlytics (code prêt depuis la phase 5, inerte sans ce fichier) |
| 8 | Secret `GOOGLE_IOS_CLIENT_ID` : identifiant du client OAuth « iOS » (`123…-abc.apps.googleusercontent.com`), écrit par `ios-release` dans `Config/Secrets.xcconfig` (`WEYDA_GOOGLE_IOS_CLIENT_ID`) | Google Cloud | le bouton « Continuer avec Google » (masqué sans lui, avertissement dans le résumé) |
| 9 | Lots serveur A, B, C déployés | dépôt du site | connexion Apple, liens universels, push iOS, liste des bloqués, textes légaux |

La branche `prep/release` est fusionnée dans `main` depuis la phase 6 : les deux workflows ont leur bouton
« Run workflow ». Ordre complet, côté Apple, Firebase, Google et Vercel : `store/checklist-soumission.md`.

Facultatif : variable de dépôt `IOS_BUILD_OFFSET` (100 par défaut, voir « Numéro de build »).

## Secrets

GitHub → dépôt `aniis934/weydaa-ios` → **Settings → Secrets and variables → Actions → New repository
secret**. Le plus sûr pour un fichier : la CLI GitHub, qui lit le fichier sans copier-coller et sans rien
laisser dans l'historique du terminal :

```
# Git Bash
gh secret set ASC_KEY_P8 -R aniis934/weydaa-ios < AuthKey_XXXXXXXXXX.p8
# PowerShell
Get-Content AuthKey_XXXXXXXXXX.p8 -Raw | gh secret set ASC_KEY_P8 -R aniis934/weydaa-ios
# Valeur courte : gh la demande, rien ne s'affiche ni ne reste dans l'historique
gh secret set ASC_KEY_ID -R aniis934/weydaa-ios
```

| Secret | Contenu | Où le trouver | Obligatoire |
|---|---|---|---|
| `ASC_KEY_ID` | identifiant de la clé, 10 caractères | App Store Connect → Intégrations → App Store Connect API → clés d'équipe → colonne Key ID | oui |
| `ASC_ISSUER_ID` | Issuer ID (forme 8-4-4-4-12) | même page, au-dessus de la liste | oui |
| `ASC_KEY_P8` | contenu complet du fichier `AuthKey_XXXXXXXXXX.p8` (lignes BEGIN/END comprises), ou ce contenu en base64 | téléchargé une seule fois à la création de la clé | oui |
| `APPLE_TEAM_ID` | Team ID, 10 caractères | developer.apple.com → Membership | oui |
| `SUPABASE_HOST` | hôte Supabase **sans** `https://` (le script l'enlève au besoin) | `.env` du site (`NEXT_PUBLIC_SUPABASE_URL`) | recommandé |
| `SUPABASE_ANON_KEY` | clé publique Supabase | `.env` du site (`NEXT_PUBLIC_SUPABASE_ANON_KEY`) | recommandé |
| `GOOGLE_SERVICE_INFO_PLIST` | contenu XML de `GoogleService-Info.plist` (ou base64) | console Firebase, app iOS `com.weydaa.app` | pour la soumission (sans lui : ni push ni rapports de plantage) |

La clé doit être une clé **d'équipe** (« Team key », la seule qui a un Issuer ID) avec l'accès **Admin** :
la signature automatique crée certificats et profils, ce qu'un rôle plus faible ne peut pas faire.
Une clé révoquée ou perdue se remplace par une nouvelle (mêmes trois secrets à resaisir).

## Publier un build TestFlight

1. Nouvelle version App Store ? Augmenter `MARKETING_VERSION` dans `project.yml` (PR vers `main`). Pour un
   simple build de test de la même version, rien à changer : le numéro de build monte tout seul.
2. Lancer : GitHub → Actions → **ios-release** → **Run workflow** → branche `main`, notes de version (ce
   que le build change, visible des testeurs), tests unitaires cochés. Ou depuis le PC :
   ```
   gh workflow run ios-release.yml -R aniis934/weydaa-ios --ref main -f notes="Accueil et recherche"
   gh run watch -R aniis934/weydaa-ios
   ```
3. Le job `release` (Mac, 15 à 25 min estimées) :
   1. vérifie les secrets (message clair s'il en manque ou s'ils sont mal formés, sans jamais les
      afficher) et calcule le numéro de build ;
   2. parité du catalogue de chaînes, XcodeGen ;
   3. écrit la clé `.p8` dans `RUNNER_TEMP`, `Config/Secrets.xcconfig` (Supabase) et
      `Weyda/Resources/GoogleService-Info.plist` (si le secret existe ; `BUNDLE_ID` vérifié) — avant XcodeGen ;
   4. tests unitaires (désactivables) ;
   5. `xcodebuild archive` en Release, signature automatique « dans le nuage » : `-allowProvisioningUpdates`
      + `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`, `DEVELOPMENT_TEAM` passé
      en argument (pas dans `project.yml`), `CURRENT_PROJECT_VERSION` = numéro de build ;
   6. `xcodebuild -exportArchive` avec `Config/ExportOptions.plist` (méthode `app-store-connect`,
      destination `upload`, symboles envoyés à Apple) : le build part directement vers App Store Connect ;
   7. dSYM envoyés à Crashlytics (si Firebase est dans le build) et publiés en artefact (30 jours) ; efface la
      clé et les fichiers de secrets, même après un échec.
4. Le job `notes` (Linux, au mieux) attend que le build apparaisse chez Apple (40 min au plus) et écrit
   les notes dans « À tester » (TestFlight, langue fr-FR) par l'API App Store Connect. S'il échoue, le
   build reste bon : saisir les notes à la main.
5. E-mail d'Apple quand le build est traité (5 à 30 min) ; il arrive dans le groupe de test interne
   (distribution automatique) → l'installer depuis l'app TestFlight.

Rien ne se déclenche sur un envoi de code : `ios-release` ne connaît que `workflow_dispatch`, et un
seul lancement à la fois (les suivants attendent).

## Numéro de build

`CFBundleVersion` = numéro d'exécution du workflow + `IOS_BUILD_OFFSET` (100 par défaut) : 101, 102…
Une relance (« Re-run jobs ») garde le numéro d'exécution : le script ajoute la tentative (`101.2`), ce
qui reste croissant (101 < 101.2 < 102) et évite le refus « numéro déjà utilisé ». Si le workflow est un
jour recréé ou renommé (le compteur repart à 1), ou après des envois faits autrement (plan B), augmenter
`IOS_BUILD_OFFSET` (Settings → Secrets and variables → Actions → **Variables**) au-dessus du dernier build.

## De TestFlight à l'App Store

Tout est dans [`store/checklist-soumission.md`](store/checklist-soumission.md) : textes
([`fiche-fr.md`](store/fiche-fr.md), [`fiche-ar.md`](store/fiche-ar.md), [`fiche-en.md`](store/fiche-en.md)),
[`app-privacy.md`](store/app-privacy.md) et le manifeste de l'app
[`Weyda/Resources/PrivacyInfo.xcprivacy`](../Weyda/Resources/PrivacyInfo.xcprivacy), [`age-rating.md`](store/age-rating.md),
[`review-notes.md`](store/review-notes.md), [`screenshots.md`](store/screenshots.md). La version de la
page App Store doit être identique à `MARKETING_VERSION` (1.0.0).

## Sécurité (dépôt et journaux publics)

- Les secrets ne sont passés qu'aux étapes qui en ont besoin ; GitHub masque leurs valeurs dans les
  journaux. Les PR venues de forks n'y ont jamais accès ; seul un collaborateur peut lancer le workflow.
- La clé `.p8` est écrite dans `RUNNER_TEMP` (droits 600) et effacée par une étape `if: always()`, comme
  `Config/Secrets.xcconfig` et `GoogleService-Info.plist` (tous deux ignorés par git).
- Aucun journal brut n'est publié en artefact ; le nom légal éventuel d'un certificat est masqué dans la
  sortie de l'export. Seuls les dSYM sont publiés (aucun secret dedans, le code est public).
- La clé publique Supabase et le `GoogleService-Info.plist` finissent dans l'app : c'est normal (valeurs
  publiques par nature, protégées côté serveur), mais ils ne vont pas dans le dépôt.

## Dépannage

| Symptôme | Cause probable | Que faire |
|---|---|---|
| « Secret manquant » / « Secret mal formé » | secret absent, tronqué ou avec la mauvaise valeur | le resaisir (tableau Secrets) |
| `Your team has no devices from which to generate a provisioning profile` | la signature automatique de l'archive utilise un profil de développement, qui exige un appareil | enregistrer l'iPhone (UDID) dans Devices, relancer ; sinon plan B (aucun appareil requis) |
| `No Accounts`, 401, `NOT_AUTHORIZED` | clé individuelle au lieu d'une clé d'équipe, rôle trop faible, Issuer ID faux, clé révoquée | clé d'équipe Admin, resaisir les trois secrets |
| `No profiles for 'com.weydaa.app' were found` | création automatique refusée (rôle, App ID, capacité) | vérifier le rôle Admin et l'App ID ; capacités (Sign in with Apple, Push, Associated Domains) activées |
| limite de certificats atteinte | chaque exécution peut créer un certificat « Apple Development: Created via API » | révoquer les anciens (Certificates) : sans effet sur les builds publiés |
| `No suitable application records were found` | app absente d'App Store Connect | créer l'app (checklist, étape 4) |
| `The bundle version must be higher…` | numéro de build déjà envoyé | augmenter `IOS_BUILD_OFFSET` |
| e-mail `ITMS-91053: Missing API declaration` | API à raison obligatoire non déclarée | compléter `Weyda/Resources/PrivacyInfo.xcprivacy` et `store/app-privacy.md` (commande de contrôle dans ce dernier) |
| avertissement « Manifeste de confidentialité absent » | `PrivacyInfo.xcprivacy` exclu de la cible ou déplacé | le remettre dans `Weyda/Resources/`, vérifier `excludes` dans `project.yml` |
| `doesn't support the … capability` ou `doesn't include the … entitlement` | capacité absente de l'App ID (Push, Sign in with Apple, Associated Domains) | la cocher sur l'App ID (Identifiers), relancer |
| push reçu sans alerte, ou aucun push sur l'iPhone | clé APNs absente de Firebase, lot B pas en ligne (jeton enregistré comme Android), notifications refusées | clé APNs dans Firebase → Cloud Messaging ; déployer le lot B ; Réglages → Weydaa → Notifications |
| « Crashlytics : upload-symbols introuvable » ou « envoi des dSYM en échec » | chemin du paquet Firebase changé, réseau | le build est bon ; envoyer les dSYM de l'artefact `ios-dsyms-<build>` depuis un Mac (section Firebase) |
| e-mail `ITMS-90683: Missing purpose string` | texte d'autorisation absent (appareil photo…) | ajouter la clé `NS…UsageDescription` (phase 4), dans les trois langues |
| notes TestFlight non écrites | build trop long à traiter, langue fr-FR absente de TestFlight | saisie manuelle, le build est bon |

Le résumé de chaque exécution (onglet du run) récapitule version, build, temps réel, Firebase et le
résultat de chaque étape ; les annotations « error » donnent la piste exacte.

## Plan B : fastlane (préinstallé sur les Mac de GitHub)

Si la signature « dans le nuage » coince (appareil impossible à enregistrer, profils refusés…), on passe
à une signature de **distribution** classique, sans Mac non plus. Non essayé tant que le compte est
inactif ; à câbler sur décision (entrée `methode` à ajouter à `ios-release`).

1. **Certificat de distribution, une fois, depuis le PC** (Git Bash fournit OpenSSL) :
   ```
   openssl genrsa -out weydaa-dist.key 2048
   openssl req -new -key weydaa-dist.key -out weydaa-dist.csr -subj "/CN=Weydaa Distribution/C=DZ"
   ```
   Portail → Certificates → **+** → Apple Distribution → envoyer `weydaa-dist.csr` → télécharger
   `distribution.cer`, puis :
   ```
   openssl x509 -inform DER -in distribution.cer -out weydaa-dist.pem
   openssl pkcs12 -export -legacy -inkey weydaa-dist.key -in weydaa-dist.pem -out weydaa-dist.p12
   ```
   (`-legacy` : sinon le trousseau de macOS refuse un .p12 produit par OpenSSL 3.) Secrets :
   `DIST_CERT_P12` (le .p12 en base64) et `DIST_CERT_PASSWORD`. Garder la clé privée hors du dépôt, en
   lieu sûr ; le certificat se renouvelle chaque année.
2. **Dans la CI** : trousseau temporaire (`security create-keychain`, `security import … -T
   /usr/bin/codesign`, `security set-key-partition-list -S apple-tool:,apple:`), puis profil **App Store**
   (aucun appareil requis) créé ou téléchargé par
   `fastlane run get_provisioning_profile app_identifier:com.weydaa.app api_key_path:<json>` (clé API
   au format JSON de fastlane : `key_id`, `issuer_id`, `key`, écrit dans `RUNNER_TEMP` puis effacé).
3. `xcodebuild archive` en signature **manuelle** (`CODE_SIGN_STYLE=Manual`,
   `CODE_SIGN_IDENTITY="Apple Distribution"`, `PROVISIONING_PROFILE_SPECIFIER=<nom du profil>`), export
   `signingStyle = manual` vers un .ipa, envoi par
   `fastlane run upload_to_testflight api_key_path:<json> ipa:<fichier> skip_waiting_for_build_processing:true`.

Avantages : un seul certificat stable, aucun appareil requis. Variante plus lourde : `fastlane match`
(certificats chiffrés dans un dépôt privé), inutile pour un seul développeur.

## Compatibilité iOS 16 : `ios-compat`

À lancer en phase 6 et avant chaque soumission : `gh workflow run ios-compat.yml -R aniis934/weydaa-ios
--ref <branche>` (le workflow doit être sur `main`), puis `gh run download <id> -n ios-compat-16.4`.
Entrées : version d'iOS (16.4), appareil (vide = iPhone SE 3e génération, sinon iPhone 8), langues (fr),
apparences (light), vidéo (non), cache (non).

Mécanique : l'image du runner `macos-26` n'a que des simulateurs iOS 26 (26.2, 26.4, 26.5). Xcode 26.6
télécharge iOS 16.4 chez Apple avec `xcodebuild -downloadPlatform iOS -buildVersion 16.4 -exportPath …`
(précédé de `xcrun simctl list`, sinon « Unable to connect to simulator ») : cette commande **installe**
le simulateur et en exporte l'image `.dmg`. Ensuite : petit iPhone, compilation, tests unitaires,
préchauffage de l'app, tour de captures en API simulée. Replis : `-architectureVariant universal`, puis
`xcodes runtimes install`. Le cache GitHub de l'image est facultatif (entrée `cache`, désactivée).

### Essais du 2026-10-02 (branche `prep/release`, tags temporaires supprimés depuis)

| | Essai 1 (`compat-try1`) : **vert** |
|---|---|
| Machine | runner `macos-26` (macOS 26.6.2, image du 2026-09-07), Xcode 26.6, 95 Go libres |
| Simulateur iOS 16.4 | **obtenu** : « iOS 16.4 Universal Simulator (20E247) », 6,18 Go, téléchargé + installé + exporté en **1 min 41 s** ; avec `-architectureVariant universal`, Xcode 26.6 répond « not available for download » (code 70) |
| Cache GitHub | sauvegarde de l'image (6,2 Go) en 2 min 12 s, plus lente que le téléchargement, et 60 % du quota de 10 Go du dépôt : cache désactivé par défaut, entrée supprimée |
| Appareil | **iPhone SE (3e génération)**, écran 4,7" ; le simulateur 16.4 propose aussi iPhone 8 / 8 Plus, SE 2, X à 14 |
| Compilation + tests + tour | 6 min 03 s : tests unitaires **17 / 17**, tour **3 / 3** (37 s grâce au préchauffage), **10 captures** (fr, clair) |
| Durée totale | **10 min 39 s** |
| Constats | rendu iOS 16 correct : barre d'onglets classique (sans Liquid Glass), grand titre, lancement animé, démo du design ; barre d'état non surchargée (heure réelle, « Carrier ») ; libellé « electromen… » tronqué dans la démo du design (Debug) sur l'écran de 4,7" |

Essai 2 (`compat-try2`) : échec en 44 s, avant le téléchargement — sous le bash 3.2 de macOS,
`"$IOS_VERSION…"` est lu comme une variable nommée `IOS_VERSION…` (« unbound variable »). Corrigé
(`${IOS_VERSION}`), et le script final reprend la commande exacte validée à l'essai 1. **Version finale
pas relancée** (limite de deux essais) : le premier lancement manuel (≈ 10 min) la validera ; nouveautés
non encore exercées : surcharge de la barre d'état reposée avant chaque tour, filtre `grep` des lignes
de progression.

Règle retenue pour tous les scripts de CI : `${VAR}` (avec accolades) devant tout caractère non ASCII.

## Firebase : push et rapports de plantage

- **Code** : `Weyda/Core/Push/FirebasePush.swift` (seul fichier qui importe Firebase 12.19.2, version exacte de
  `project.yml`). Firebase ne démarre que si `GoogleService-Info.plist` est dans l'app, hors API simulée et hors
  tests unitaires : les builds de la CI et des captures n'en ont pas, tout y est inerte.
- **Fichier de configuration** : jamais dans le dépôt. `release.sh prepare` écrit le contenu du secret
  `GOOGLE_SERVICE_INFO_PLIST` dans `Weyda/Resources/GoogleService-Info.plist` AVANT XcodeGen (il entre ainsi dans
  les ressources), refuse un plist invalide ou d'une autre app (`BUNDLE_ID` différent de `com.weydaa.app`), puis
  l'efface en fin de job. Le résumé du run dit « Firebase (push, plantages) : oui ».
- **Push** : Firebase Cloud Messaging, relayé par APNs ; `FirebaseAppDelegateProxyEnabled = NO` (pas de
  swizzling : le jeton APNs passe à la main), `UIBackgroundModes` = `remote-notification` (Info.plist).
  Autorisation demandée à la première ouverture de Messages par un membre ; jeton envoyé au serveur
  (`POST /api/push/fcm`, plateforme « ios », lot B) et détruit à la déconnexion. Côté Firebase : clé APNs
  (`.p8`, Key ID, Team ID) dans Paramètres du projet → Cloud Messaging → app iOS ; une seule clé sert au
  développement et à la production (TestFlight et App Store utilisent la production).
- **Crashlytics** : collecte activée en Release seulement (`setCrashlyticsCollectionEnabled`, coupée en Debug),
  sans identifiant d'utilisateur (`setUserID` jamais appelé : les plantages restent « non liés », voir
  `store/app-privacy.md`). Les rapports arrivent au relancement qui suit un plantage.
- **Symboles (dSYM)** : l'étape `symbols` de `release.sh` zippe les dSYM de l'archive (artefact
  `ios-dsyms-<build>`, 30 jours) puis, si Firebase est dans le build, les envoie avec l'outil livré dans le
  paquet, même version que l'app :
  `build/release/dd/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols -gsp Weyda/Resources/GoogleService-Info.plist -p ios build/release/Weyda.xcarchive/dSYMs`.
  Un échec n'est qu'un avertissement (le build TestFlight est déjà parti) : sur un Mac, refaire la même
  commande avec le dossier `dSYMs` de l'artefact dézippé et le `GoogleService-Info.plist` téléchargé de Firebase.
  Apple reçoit aussi les symboles (`uploadSymbols` dans `Config/ExportOptions.plist`).

## Entitlements de Release et capacités de l'App ID

`Config/Weyda.entitlements` n'est appliqué qu'à la configuration **Release** (`project.yml` :
`configs: Release: CODE_SIGN_ENTITLEMENTS`) : les builds Debug de la CI (simulateur, sans équipe Apple) n'en
ont pas, l'archive signée de `ios-release` les a tous.

| Entitlement | Valeur dans le fichier | Capacité à cocher sur l'App ID | Sert à |
|---|---|---|---|
| `aps-environment` | `development` | Push Notifications | push (APNs) |
| `com.apple.developer.applesignin` | `Default` | Sign in with Apple (« primary App ID ») | « Continuer avec Apple » (lot A côté serveur) |
| `com.apple.developer.associated-domains` | `applinks:weydaa.com`, `applinks:www.weydaa.com`, `webcredentials:weydaa.com` | Associated Domains | liens universels et mots de passe du Trousseau partagés avec le site |

- **`aps-environment` = `development`, c'est voulu** : c'est la valeur qu'écrit Xcode en ajoutant la capacité
  Push, et l'archive est signée automatiquement avec un profil de **développement** (« production » y serait
  refusé). L'export App Store Connect (`ios-release`, étape `upload`) re-signe avec le profil de distribution,
  qui passe la valeur à `production` : les builds TestFlight et App Store parlent à l'APNs de production.
- **Capacités** : cocher les trois sur l'App ID `com.weydaa.app` (Certificates, Identifiers & Profiles →
  Identifiers) avant le premier `ios-release`. La signature automatique avec une clé Admin sait les activer,
  mais un App ID déjà prêt évite l'erreur « doesn't support the … capability » (Dépannage).
- **Liens universels** : le fichier `/.well-known/apple-app-site-association` est servi par le site (lot A), à
  partir de la variable `APPLE_TEAM_ID` de Vercel (404 tant qu'elle est vide), sur `weydaa.com` et
  `www.weydaa.com`. Apple le récupère par son propre réseau à l'installation de l'app : après une correction du
  fichier, réinstaller l'app pour la tester.
