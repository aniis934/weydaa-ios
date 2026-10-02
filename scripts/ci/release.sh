#!/bin/bash
# Publication TestFlight — sous-commandes appelées dans l'ordre par .github/workflows/ios-release.yml
# (lancement MANUEL uniquement). Guide, prérequis, dépannage et plan B : docs/RELEASE.md.
#
#   check     secrets présents et bien formés (jamais affichés), numéro de build, version
#   prepare   clé .p8 dans RUNNER_TEMP (droits 600), Config/Secrets.xcconfig (Supabase),
#             Weyda/Resources/GoogleService-Info.plist (Firebase, si fourni) — AVANT XcodeGen
#   archive   archive Release signée « dans le nuage » : signature automatique + clé API App Store Connect
#   upload    export méthode app-store-connect, destination upload → App Store Connect (TestFlight)
#   symbols   dSYM de l'archive zippés pour l'artefact (envoi à Crashlytics : phase 5)
#   cleanup   efface la clé, les fichiers de secrets et les options d'export (toujours, même après un échec)
#
# Environnement : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contenu du .p8, brut ou en base64), APPLE_TEAM_ID
# — obligatoires ; SUPABASE_HOST + SUPABASE_ANON_KEY (temps réel ; absents = HTTP seul) ;
# GOOGLE_SERVICE_INFO_PLIST (Firebase, phase 5 ; XML brut ou base64) ; IOS_BUILD_OFFSET (100 par défaut) ;
# NOTES (affichées dans le résumé). Écrit pour le bash 3.2 de macOS : ni tableaux associatifs ni ${!x}.
set -euo pipefail

BUNDLE_ID="com.weydaa.app"
RELEASE_DIR="build/release"
ARCHIVE="$RELEASE_DIR/Weyda.xcarchive"
TMP_DIR="${RUNNER_TEMP:-/tmp}"
KEY_DIR="$TMP_DIR/asc-key"
EXPORT_OPTIONS="$TMP_DIR/ExportOptions.plist"
SECRETS_XCCONFIG="Config/Secrets.xcconfig"
FIREBASE_PLIST="Weyda/Resources/GoogleService-Info.plist"

# ── Utilitaires ───────────────────────────────────────────────────────────────────────────────
summary() { [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; }
set_env() { [ -z "${GITHUB_ENV:-}" ] || echo "$1=$2" >> "$GITHUB_ENV"; }
set_output() { [ -z "${GITHUB_OUTPUT:-}" ] || echo "$1=$2" >> "$GITHUB_OUTPUT"; }
die() {
  echo "::error title=$1::$2"
  summary "" "**Échec — $1** : $2"
  exit 1
}
# Identifiants : espaces, retours à la ligne et guillemets parasites (copier-coller) retirés.
clean() { printf '%s' "$1" | tr -d '[:space:]"'; }
# Nom légal éventuel d'un certificat (« Apple Distribution: Prénom Nom (ÉQUIPE) ») masqué : journaux publics.
mask() { sed -l -E 's/((Apple|iPhone) (Development|Distribution)): [^(]+\(/\1: [masqué] (/g'; }

ASC_KEY_ID=$(clean "${ASC_KEY_ID:-}")
ASC_ISSUER_ID=$(clean "${ASC_ISSUER_ID:-}")
APPLE_TEAM_ID=$(clean "${APPLE_TEAM_ID:-}")
ASC_KEY_P8="${ASC_KEY_P8:-}"
SUPABASE_HOST=$(clean "${SUPABASE_HOST:-}")
SUPABASE_ANON_KEY=$(clean "${SUPABASE_ANON_KEY:-}")
GOOGLE_SERVICE_INFO_PLIST="${GOOGLE_SERVICE_INFO_PLIST:-}"

# Contenu PEM de la clé .p8 : le secret peut être collé tel quel ou encodé en base64.
p8_pem() {
  case "$ASC_KEY_P8" in
    *"BEGIN PRIVATE KEY"*) printf '%s\n' "$ASC_KEY_P8" | tr -d '\r' ;;
    *) { printf '%s' "$ASC_KEY_P8" | tr -d '[:space:]' | base64 --decode 2>/dev/null || true; } | tr -d '\r' ;;
  esac
}

# Pistes lisibles pour les échecs connus de signature / d'envoi (journal brut en argument).
hints() {
  local log="$1"
  echo "── Lignes d'erreur du journal brut ──"
  grep -E "error:|ITMS-|\*\* (ARCHIVE|EXPORT) FAILED" "$log" | mask | sort -u | head -40 || true
  if grep -E "has no devices" "$log" > /dev/null; then
    echo "::error title=Aucun appareil enregistré::la signature automatique de l'archive exige au moins un appareil dans le compte : enregistrer l'iPhone (UDID) dans Certificates, IDs & Profiles > Devices, puis relancer."
  fi
  if grep -E -i "No Accounts|authentication (failed|credentials)|NOT_AUTHORIZED|invalid (api )?key|status code 401|status code 403" "$log" > /dev/null; then
    echo "::error title=Clé API refusée::vérifier ASC_KEY_ID, ASC_ISSUER_ID et ASC_KEY_P8 : clé d'ÉQUIPE (Team key) avec l'accès Admin, non révoquée."
  fi
  if grep -E "No profiles for|requires a provisioning profile|Automatic signing is disabled|doesn't include signing certificate" "$log" > /dev/null; then
    echo "::error title=Profil de provisionnement::création automatique refusée : clé API sans rôle Admin, App ID com.weydaa.app absent, ou capacité non activée (docs/RELEASE.md, Dépannage)."
  fi
  if grep -E -i "maximum number of|already have a current|certificate limit" "$log" > /dev/null; then
    echo "::error title=Limite de certificats::révoquer les anciens certificats « Created via API » (Certificates, IDs & Profiles), puis relancer."
  fi
  if grep -E -i "No suitable application records|app record|Could not find (the )?app" "$log" > /dev/null; then
    echo "::error title=App absente d'App Store Connect::créer l'app (bundle $BUNDLE_ID) dans App Store Connect avant le premier envoi."
  fi
  if grep -E -i "bundle version must be higher|has already been used|redundant binary" "$log" > /dev/null; then
    echo "::error title=Numéro de build déjà utilisé::augmenter la variable de dépôt IOS_BUILD_OFFSET (Settings > Secrets and variables > Actions > Variables), puis relancer."
  fi
}

# ── check ─────────────────────────────────────────────────────────────────────────────────────
cmd_check() {
  local name value missing="" bad="" item
  for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_TEAM_ID; do
    eval "value=\${$name:-}"
    [ -n "$value" ] || missing="$missing $name"
  done
  if [ -n "$missing" ]; then
    summary "### Publication impossible : secret(s) manquant(s)" ""
    for name in $missing; do
      echo "::error title=Secret manquant : $name::à créer dans Settings > Secrets and variables > Actions du dépôt (docs/RELEASE.md, section Secrets)."
      summary "- \`$name\`"
    done
    summary "" "À saisir dans **Settings → Secrets and variables → Actions**, puis relancer. Détail : \`docs/RELEASE.md\`."
    exit 1
  fi

  printf '%s' "$APPLE_TEAM_ID" | grep -E '^[A-Z0-9]{10}$' > /dev/null \
    || bad="$bad|APPLE_TEAM_ID : 10 caractères, majuscules et chiffres (page Membership du compte développeur)"
  printf '%s' "$ASC_KEY_ID" | grep -E '^[A-Z0-9]{10}$' > /dev/null \
    || bad="$bad|ASC_KEY_ID : 10 caractères, majuscules et chiffres (colonne Key ID de la clé API)"
  printf '%s' "$ASC_ISSUER_ID" | grep -E -i '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' > /dev/null \
    || bad="$bad|ASC_ISSUER_ID : identifiant 8-4-4-4-12 (Issuer ID, au-dessus de la liste des clés d'équipe)"
  p8_pem | grep -- "-----BEGIN PRIVATE KEY-----" > /dev/null \
    || bad="$bad|ASC_KEY_P8 : contenu complet du fichier AuthKey_XXXXXXXXXX.p8 (lignes BEGIN et END comprises), ou ce contenu en base64"
  if [ -n "$bad" ]; then
    summary "### Publication impossible : secret(s) mal formé(s)" ""
    local IFS='|'
    for item in $bad; do
      [ -n "$item" ] || continue
      echo "::error title=Secret mal formé::$item"
      summary "- $item"
    done
    exit 1
  fi

  # Numéro de build : numéro d'exécution du workflow + décalage (toujours croissant). Une relance
  # (« Re-run ») garde le même numéro d'exécution : on ajoute alors « .tentative » (101 < 101.2 < 102).
  local offset="${IOS_BUILD_OFFSET:-}"
  [ -n "$offset" ] || offset=100
  case "$offset" in
    *[!0-9]*) die "Numéro de build" "la variable de dépôt IOS_BUILD_OFFSET doit être un entier positif" ;;
  esac
  local run="${GITHUB_RUN_NUMBER:-0}" attempt="${GITHUB_RUN_ATTEMPT:-1}" build
  offset=$((10#$offset))
  build=$((10#$run + offset))
  [ "$attempt" -le 1 ] || build="$build.$attempt"

  local version
  version=$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*$/\1/p' project.yml | head -1)
  [ -n "$version" ] || die "Version" "MARKETING_VERSION introuvable dans project.yml"

  local realtime="oui" firebase="oui" branch="${GITHUB_REF_NAME:-local}" sha="${GITHUB_SHA:-local}"
  if [ -z "$SUPABASE_HOST" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    realtime="non : secrets SUPABASE_HOST / SUPABASE_ANON_KEY absents (HTTP seul)"
    echo "::warning title=Temps réel désactivé::secrets SUPABASE_HOST / SUPABASE_ANON_KEY absents : ce build fonctionnera en HTTP seul."
  fi
  [ -n "$GOOGLE_SERVICE_INFO_PLIST" ] || firebase="non (attendu à partir de la phase 5)"
  if [ "$branch" != "main" ]; then
    echo "::warning title=Branche::publication lancée depuis « $branch » et non depuis main."
  fi

  set_env BUILD_NUMBER "$build"
  set_output build "$build"
  set_output version "$version"
  echo "Weydaa $version (build $build) — branche $branch, commit ${sha:0:7}"
  summary "### Weydaa $version — build $build" "" \
    "| | |" "|---|---|" \
    "| Branche | \`$branch\` (\`${sha:0:7}\`) |" \
    "| Numéro de build | $build (exécution ${run} + décalage ${offset}) |" \
    "| Temps réel (Supabase) | $realtime |" \
    "| Firebase (push, plantages) | $firebase |" ""
  if [ -n "${NOTES:-}" ]; then
    summary "**Notes de version :**" ""
    printf '%s\n' "$NOTES" | sed 's/^/> /' >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
    summary ""
  fi
}

# ── prepare ───────────────────────────────────────────────────────────────────────────────────
cmd_prepare() {
  rm -rf "$KEY_DIR"
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
  local key="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
  ( umask 077; p8_pem > "$key" )
  grep -- "-----BEGIN PRIVATE KEY-----" "$key" > /dev/null || die "Clé API" "ASC_KEY_P8 ne contient pas de clé privée lisible"
  set_env ASC_KEY_PATH "$key"
  echo "Clé API écrite dans RUNNER_TEMP (droits 600) ; effacée en fin de job."

  if [ -n "$SUPABASE_HOST" ] && [ -n "$SUPABASE_ANON_KEY" ]; then
    # Hôte seul : « // » (de https://) ouvrirait un commentaire dans un .xcconfig.
    local host="$SUPABASE_HOST"
    host="${host#https://}"
    host="${host#http://}"
    host="${host%%/*}"
    {
      echo "// Écrit par scripts/ci/release.sh depuis le coffre GitHub — ignoré par git, effacé en fin de job."
      echo "WEYDA_SUPABASE_HOST = $host"
      echo "WEYDA_SUPABASE_ANON_KEY = $SUPABASE_ANON_KEY"
    } > "$SECRETS_XCCONFIG"
    echo "Temps réel : $SECRETS_XCCONFIG écrit."
  else
    rm -f "$SECRETS_XCCONFIG"
    echo "Temps réel : désactivé (secrets Supabase absents)."
  fi

  if [ -n "$GOOGLE_SERVICE_INFO_PLIST" ]; then
    case "$GOOGLE_SERVICE_INFO_PLIST" in
      *"<plist"*) printf '%s\n' "$GOOGLE_SERVICE_INFO_PLIST" > "$FIREBASE_PLIST" ;;
      *) { printf '%s' "$GOOGLE_SERVICE_INFO_PLIST" | tr -d '[:space:]' | base64 --decode 2>/dev/null || true; } > "$FIREBASE_PLIST" ;;
    esac
    if ! plutil -lint "$FIREBASE_PLIST" > /dev/null 2>&1; then
      rm -f "$FIREBASE_PLIST"
      die "Firebase" "GOOGLE_SERVICE_INFO_PLIST n'est pas un plist valide (contenu XML du fichier, ou ce contenu en base64)"
    fi
    local bundle
    bundle=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$FIREBASE_PLIST" 2>/dev/null || true)
    if [ "$bundle" != "$BUNDLE_ID" ]; then
      rm -f "$FIREBASE_PLIST"
      die "Firebase" "GoogleService-Info.plist appartient à une autre app (BUNDLE_ID différent de $BUNDLE_ID)"
    fi
    echo "Firebase : $FIREBASE_PLIST écrit (avant XcodeGen, pour être embarqué dans l'app)."
  fi
}

# ── archive ───────────────────────────────────────────────────────────────────────────────────
cmd_archive() {
  : "${BUILD_NUMBER:?BUILD_NUMBER absent : l'étape check n'a pas tourné}"
  : "${ASC_KEY_PATH:?ASC_KEY_PATH absent : l'étape prepare n'a pas tourné}"
  mkdir -p build/logs "$RELEASE_DIR"
  rm -rf "$ARCHIVE"

  # DEVELOPMENT_TEAM vient du secret (project.yml ne le contient pas : dépôt public, équipe inconnue).
  local status
  set +e
  xcodebuild archive \
    -project Weyda.xcodeproj \
    -scheme Weyda \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$RELEASE_DIR/dd" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee build/logs/archive.log | xcbeautify --renderer github-actions
  status=${PIPESTATUS[0]}
  set -e
  if [ "$status" -ne 0 ]; then
    hints build/logs/archive.log
    die "Archive" "xcodebuild archive a échoué (code $status) : pistes ci-dessus, dépannage dans docs/RELEASE.md"
  fi

  local plist="$ARCHIVE/Info.plist" version build
  version=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$plist")
  build=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$plist")
  [ "$build" = "$BUILD_NUMBER" ] || die "Archive" "numéro de build inattendu dans l'archive ($build au lieu de $BUILD_NUMBER)"
  if [ ! -f "$ARCHIVE/Products/Applications/Weyda.app/PrivacyInfo.xcprivacy" ]; then
    echo "::warning title=Manifeste de confidentialité absent::PrivacyInfo.xcprivacy n'est pas dans l'app (brouillon : docs/store/, à placer dans Weyda/Resources à la phase 7)."
  fi
  set_output version "$version"
  echo "Archive signée : Weydaa $version ($build)"
  summary "- Archive Release signée : Weydaa $version ($build)"
}

# ── upload ────────────────────────────────────────────────────────────────────────────────────
cmd_upload() {
  : "${ASC_KEY_PATH:?ASC_KEY_PATH absent : l'étape prepare n'a pas tourné}"
  [ -d "$ARCHIVE" ] || die "Envoi" "archive absente : l'étape archive n'a pas abouti"
  mkdir -p build/logs
  cp Config/ExportOptions.plist "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Delete :teamID" "$EXPORT_OPTIONS" > /dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :teamID string $APPLE_TEAM_ID" "$EXPORT_OPTIONS"
  plutil -lint "$EXPORT_OPTIONS" > /dev/null
  rm -rf "$RELEASE_DIR/export"

  local status
  set +e
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$RELEASE_DIR/export" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    2>&1 | tee build/logs/export.log | mask
  status=${PIPESTATUS[0]}
  set -e
  if [ "$status" -ne 0 ]; then
    hints build/logs/export.log
    die "Envoi" "xcodebuild -exportArchive a échoué (code $status) : pistes ci-dessus, dépannage dans docs/RELEASE.md"
  fi
  echo "Build envoyé à App Store Connect : traitement par Apple (5 à 30 min), puis disponible dans TestFlight."
  summary "- Envoyé à App Store Connect : traitement par Apple (5 à 30 min), puis TestFlight (e-mail d'Apple)."
}

# ── symbols ───────────────────────────────────────────────────────────────────────────────────
cmd_symbols() {
  if [ -d "$ARCHIVE/dSYMs" ] && [ -n "$(ls -A "$ARCHIVE/dSYMs" 2>/dev/null)" ]; then
    rm -f "$RELEASE_DIR/dSYMs.zip"
    ditto -c -k --keepParent "$ARCHIVE/dSYMs" "$RELEASE_DIR/dSYMs.zip"
    echo "dSYM : $RELEASE_DIR/dSYMs.zip ($(du -h "$RELEASE_DIR/dSYMs.zip" | cut -f1))"
  else
    echo "::warning::aucun dSYM dans l'archive"
  fi
}

# ── cleanup ───────────────────────────────────────────────────────────────────────────────────
cmd_cleanup() {
  rm -rf "$KEY_DIR"
  rm -f "$EXPORT_OPTIONS" "$SECRETS_XCCONFIG" "$FIREBASE_PLIST"
  echo "Clé API, fichiers de secrets et options d'export effacés."
}

case "${1:-}" in
  check | prepare | archive | upload | symbols | cleanup) "cmd_$1" ;;
  *)
    echo "usage : $0 check|prepare|archive|upload|symbols|cleanup" >&2
    exit 2
    ;;
esac
