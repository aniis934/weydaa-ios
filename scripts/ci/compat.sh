#!/bin/bash
# Compatibilité iOS 16 (workflow ios-compat) : simulateur iOS ancien téléchargé chez Apple (absent de
# l'image du runner), petit iPhone, compilation, tests unitaires et tour de captures en API simulée
# (même mécanique que screens.sh). Sous-commandes, dans l'ordre du workflow :
#   download  télécharge le simulateur iOS IOS_VERSION chez Apple : xcodebuild l'installe ET en exporte
#             l'image (.dmg) dans RUNTIME_DIR, que le cache facultatif du workflow peut sauvegarder ; rien
#             à faire s'il est déjà installé ou restauré du cache — sorties : downloaded=true|false,
#             source=preinstalled|cache|apple|none
#   install   installe l'image restaurée du cache (puis la supprime) ; à défaut, installation directe
#             (xcodebuild, puis xcodes) ; échec lisible si iOS IOS_VERSION reste introuvable
#   run       simulateur, build-for-testing, tests unitaires, tour → screens/<appareil>/<langue>-<apparence>/
# Entrées : IOS_VERSION (16.4), DEVICE (vide = iPhone SE (3rd generation), sinon iPhone 8, sinon
# iPhone SE (2nd generation)), LANGS (fr), APPEARANCES (light), VIDEO (0|1), RUNTIME_DIR (~/.weyda-runtimes).
# Xcode 26.6, essais du 2026-10-02 : `xcodebuild -downloadPlatform iOS -buildVersion 16.4 -exportPath …`
# SANS -architectureVariant télécharge « iOS 16.4 Universal Simulator (20E247) » (6,18 Go), l'installe et
# en exporte l'image ; AVEC `-architectureVariant universal`, réponse « iOS 16.4 (universal) is not
# available for download » (code 70) : l'option ne sert que de repli. `xcrun simctl list` avant, sinon
# « Unable to connect to simulator ». Bash 3.2 (macOS) : toujours ${VAR} devant un caractère non ASCII
# (« $X… » y est lu comme une variable nommée « X… » : échec de l'essai 2).
set -uo pipefail

IOS_VERSION="${IOS_VERSION:-16.4}"
RUNTIME_DIR="${RUNTIME_DIR:-$HOME/.weyda-runtimes}"
LANGS="${LANGS:-fr}"
APPEARANCES="${APPEARANCES:-light}"
VIDEO="${VIDEO:-0}"
DEVICE="${DEVICE:-}"

summary() { [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; }
output() { [ -z "${GITHUB_OUTPUT:-}" ] || echo "$1=$2" >> "$GITHUB_OUTPUT"; }
duration() { printf '%d min %02d s' $(($1 / 60)) $(($1 % 60)); }
disk() { df -h / | tail -1 | awk '{print "Disque : " $4 " libres sur " $2}'; }

# Identifiant du simulateur iOS IOS_VERSION installé et utilisable (vide sinon).
runtime_id() {
  xcrun simctl list runtimes -j 2>/dev/null | jq -r --arg v "$IOS_VERSION" '
    [.runtimes[]
      | select(.platform == "iOS" and .isAvailable == true
               and (.version == $v or (.version | startswith($v + "."))))]
    | first | .identifier // empty' 2>/dev/null
}

# Lignes de progression retirées : xcodebuild en écrit des dizaines de milliers (« 12.3% (… of 6.18 GB) »).
no_progress() { grep --line-buffered -v -E '[0-9]%' || true; }

# Télécharge et installe le simulateur iOS IOS_VERSION ; avec un dossier en argument, xcodebuild y
# exporte aussi l'image (.dmg). Sans -architectureVariant d'abord, « universal » en repli.
download_platform() {
  local export_dir="$1" variant status
  for variant in default universal; do
    set -- -downloadPlatform iOS -buildVersion "$IOS_VERSION"
    [ "$variant" = default ] || set -- "$@" -architectureVariant "$variant"
    if [ -n "$export_dir" ]; then
      rm -rf "$export_dir"
      mkdir -p "$export_dir"
      set -- "$@" -exportPath "$export_dir"
    fi
    echo "xcodebuild $*"
    xcodebuild "$@" 2>&1 | no_progress
    status=${PIPESTATUS[0]}
    [ "$status" -ne 0 ] || return 0
    echo "::warning::xcodebuild -downloadPlatform (variante $variant) : code $status"
  done
  return 1
}

# Barre d'état propre (9:41, batterie pleine, sans « Carrier »). Sur le simulateur iOS 16.4, une
# surcharge posée juste après le démarrage ne tient pas (essai 1 : heure réelle et « Carrier ») :
# elle est reposée avant chaque tour.
clean_status_bar() {
  xcrun simctl status_bar "$1" override --time "9:41" --operatorName "" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 \
    || echo "::warning::barre d'état non surchargée"
}

wait_runtime() {
  local limit=$1 waited=0
  while [ -z "$(runtime_id)" ]; do
    [ "$waited" -lt "$limit" ] || return 1
    sleep 10
    waited=$((waited + 10))
  done
  return 0
}

# Type d'appareil « identifiant|nom » : DEVICE s'il est proposé, sinon le plus petit iPhone d'iOS 16.
pick_device() {
  local runtime=$1 types candidate id
  types=$(xcrun simctl list runtimes -j | jq -c --arg r "$runtime" '[.runtimes[] | select(.identifier == $r) | .supportedDeviceTypes[]?]')
  echo "iPhone proposés par ce simulateur : $(echo "$types" | jq -r '[.[] | select(.productFamily == "iPhone") | .name] | join(", ")')" >&2
  for candidate in "$DEVICE" "iPhone SE (3rd generation)" "iPhone 8" "iPhone SE (2nd generation)"; do
    [ -n "$candidate" ] || continue
    id=$(echo "$types" | jq -r --arg n "$candidate" '[.[] | select(.name == $n)] | first | .identifier // empty')
    if [ -n "$id" ]; then
      echo "$id|$candidate"
      return 0
    fi
    if [ "$candidate" = "$DEVICE" ]; then
      echo "::warning::appareil « $DEVICE » non proposé par $runtime : choix automatique" >&2
    fi
  done
  echo "$types" | jq -r '[.[] | select(.productFamily == "iPhone")] | first | if . == null then "" else "\(.identifier)|\(.name)" end'
}

# ── download ──────────────────────────────────────────────────────────────────────────────────
cmd_download() {
  xcrun simctl list > /dev/null 2>&1 || true
  echo "── Machine ──"
  sw_vers || true
  xcodebuild -version || true
  disk
  echo "── Options de téléchargement de cet xcodebuild ──"
  xcodebuild -help 2>&1 | grep -i -E "downloadPlatform|buildVersion|architectureVariant|exportPath|importPlatform" | head -12 || true
  echo "── Simulateurs iOS installés ──"
  xcrun simctl list runtimes 2>/dev/null | grep -i "ios" || true

  if [ -n "$(runtime_id)" ]; then
    echo "iOS $IOS_VERSION déjà installé sur le runner."
    output downloaded false
    output source preinstalled
    summary "- Simulateur iOS $IOS_VERSION : déjà présent sur le runner"
    return 0
  fi
  mkdir -p "$RUNTIME_DIR"
  if [ -n "$(ls -A "$RUNTIME_DIR" 2>/dev/null)" ]; then
    local cached
    cached=$(du -sh "$RUNTIME_DIR" | cut -f1)
    echo "Simulateur restauré du cache : $(ls "$RUNTIME_DIR") ($cached)"
    output downloaded false
    output source cache
    summary "- Simulateur iOS $IOS_VERSION : restauré du cache ($cached)"
    return 0
  fi

  # Même commande que l'essai 1 (avec -exportPath : installe ET exporte l'image). Le workflow ne
  # sauvegarde l'image que si le cache est demandé.
  local start=$SECONDS status
  echo "Téléchargement chez Apple : simulateur iOS ${IOS_VERSION}"
  download_platform "$RUNTIME_DIR"
  status=$?
  local secs=$((SECONDS - start))
  if [ "$status" -eq 0 ] && [ -n "$(ls -A "$RUNTIME_DIR" 2>/dev/null)" ]; then
    local size
    size=$(du -sh "$RUNTIME_DIR" | cut -f1)
    echo "Téléchargé et installé en $(duration $secs) ; image exportée : $(ls "$RUNTIME_DIR") ($size)"
    output downloaded true
    output source apple
    summary "- Simulateur iOS ${IOS_VERSION} : téléchargé chez Apple et installé en $(duration $secs) (image de ${size})"
  elif [ "$status" -eq 0 ]; then
    echo "Téléchargé et installé en $(duration $secs) (aucune image exportée)"
    output downloaded false
    output source apple
    summary "- Simulateur iOS ${IOS_VERSION} : téléchargé chez Apple et installé en $(duration $secs)"
  else
    rm -rf "$RUNTIME_DIR"
    echo "::warning::téléchargement en échec après $(duration $secs) : autres méthodes à l'étape suivante"
    output downloaded false
    output source none
    summary "- Simulateur iOS ${IOS_VERSION} : téléchargement en échec ($(duration $secs)), autres méthodes tentées"
  fi
  disk
}

# ── install ───────────────────────────────────────────────────────────────────────────────────
cmd_install() {
  xcrun simctl list > /dev/null 2>&1 || true
  local start=$SECONDS image runtime
  if [ -z "$(runtime_id)" ]; then
    image=$(find "$RUNTIME_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)
    if [ -n "$image" ]; then
      echo "Installation de l'image $(basename "$image")…"
      if ! xcrun simctl runtime add "$image"; then
        echo "::warning::simctl runtime add a échoué : essai avec xcodebuild -importPlatform"
        xcodebuild -importPlatform "$image" || true
      fi
      if wait_runtime 300; then
        # CoreSimulator garde sa propre copie de l'image : on libère la place (sauf si elle y est montée).
        if ! xcrun simctl runtime list 2>/dev/null | grep -F "$RUNTIME_DIR" > /dev/null; then
          rm -rf "$RUNTIME_DIR"
        fi
      fi
    fi
  fi
  if [ -z "$(runtime_id)" ]; then
    echo "Installation directe (sans image locale)…"
    xcrun simctl list > /dev/null 2>&1 || true
    download_platform "" \
      || { command -v xcodes > /dev/null && xcodes runtimes install "iOS $IOS_VERSION" < /dev/null; } \
      || true
    wait_runtime 300 || true
  fi

  runtime=$(runtime_id)
  if [ -z "$runtime" ]; then
    xcrun simctl list runtimes || true
    echo "::error title=Simulateur iOS $IOS_VERSION introuvable::ni xcodebuild -downloadPlatform ni xcodes n'ont fourni un simulateur iOS $IOS_VERSION utilisable avec $(xcodebuild -version | head -1). Voir le journal ; essayer une autre version (entrée ios_version)."
    summary "- **Échec** : simulateur iOS $IOS_VERSION introuvable après installation"
    exit 1
  fi
  local secs=$((SECONDS - start))
  echo "Simulateur prêt en $(duration $secs) : $runtime"
  summary "- Simulateur installé en $(duration $secs) : \`$runtime\`"
  disk
}

# ── run ───────────────────────────────────────────────────────────────────────────────────────
cmd_run() {
  mkdir -p build/logs build/results screens
  local runtime
  runtime=$(runtime_id)
  if [ -z "$runtime" ]; then
    echo "::error::simulateur iOS $IOS_VERSION absent : l'étape install n'a pas abouti"
    exit 1
  fi

  local pick type_id type_name
  pick=$(pick_device "$runtime")
  type_id="${pick%%|*}"
  type_name="${pick#*|}"
  if [ -z "$type_id" ]; then
    echo "::error::aucun iPhone proposé par $runtime"
    exit 1
  fi
  echo "Appareil : $type_name · $runtime"

  local udid start boot_secs
  udid=$(xcrun simctl create "Weyda compat" "$type_id" "$runtime") || {
    echo "::error::création du simulateur impossible ($type_name, $runtime)"
    exit 1
  }
  start=$SECONDS
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  boot_secs=$((SECONDS - start))
  clean_status_bar "$udid"
  touch build/logs/.compat-start

  # 1. Compilation pour ce simulateur (Debug, cible iOS 16.0).
  start=$SECONDS
  xcodebuild build-for-testing \
    -project Weyda.xcodeproj \
    -scheme Weyda \
    -destination "id=$udid" \
    -derivedDataPath build/dd \
    -clonedSourcePackagesDirPath "${SPM_DIR:-build/spm}" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee build/logs/build-for-testing.log | xcbeautify --renderer github-actions
  local build_status=${PIPESTATUS[0]} build_secs=$((SECONDS - start))
  summary "### ios-compat — iOS $IOS_VERSION · $type_name" "" \
    "| Étape | Résultat | Durée |" "|---|---|---|" \
    "| Démarrage du simulateur | ok | $(duration $boot_secs) |"
  if [ "$build_status" -ne 0 ]; then
    summary "| Compilation | **échec** (code $build_status) | $(duration $build_secs) |"
    echo "::error::compilation pour iOS $IOS_VERSION en échec"
    exit 1
  fi
  summary "| Compilation (build-for-testing) | ok | $(duration $build_secs) |"

  local xctestrun app
  xctestrun=$(find build/dd/Build/Products -maxdepth 1 -name '*.xctestrun' | head -1)
  app=$(find build/dd/Build/Products -maxdepth 2 -name 'Weyda.app' -type d | head -1)

  # 2. Tests unitaires sur iOS 16 (LiveAPITests sautés : jamais d'appel à la prod ici).
  start=$SECONDS
  TEST_RUNNER_WEYDA_LIVE_API=0 xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "id=$udid" \
    -only-testing:WeydaTests \
    -resultBundlePath build/results/compat-unit.xcresult \
    2>&1 | xcbeautify --renderer github-actions
  local unit_status=${PIPESTATUS[0]} unit_secs=$((SECONDS - start)) unit_json unit_counts
  unit_json=$(xcrun xcresulttool get test-results summary --path build/results/compat-unit.xcresult --compact 2>/dev/null || true)
  unit_counts=$(echo "$unit_json" | jq -r '"\(.passedTests // "?") réussis sur \(.totalTestCount // "?") (\(.failedTests // 0) en échec, \(.skippedTests // 0) sautés)"' 2>/dev/null || true)
  [ -n "$unit_counts" ] || unit_counts="décompte indisponible"
  if [ "$unit_status" -eq 0 ]; then
    summary "| Tests unitaires | $unit_counts | $(duration $unit_secs) |"
  else
    summary "| Tests unitaires | **échec** : $unit_counts | $(duration $unit_secs) |"
  fi

  # 3. Préchauffage : premier lancement sur un simulateur neuf, hors du tour (comme screens.sh).
  if [ -n "$app" ]; then
    xcrun simctl install "$udid" "$app" \
      && xcrun simctl launch "$udid" com.weydaa.app -WeydaMockAPI YES -WeydaSkipLaunch YES > /dev/null \
      && sleep 8 \
      && xcrun simctl terminate "$udid" com.weydaa.app \
      || echo "::warning::préchauffage de l'app incomplet"
  fi

  # 4. Tour de captures en API simulée, par langue × apparence.
  local slug lang appearance run_name out video_pid slow status first=1 tour_failures=0
  slug=$(printf '%s-iOS-%s' "$type_name" "$IOS_VERSION" | tr ' ' '-' | tr -cd '[:alnum:].-')
  start=$SECONDS
  for lang in $LANGS; do
    for appearance in $APPEARANCES; do
      xcrun simctl ui "$udid" appearance "$appearance" || true
      clean_status_bar "$udid"
      run_name="compat-${lang}-${appearance}"
      out="screens/${slug}/${lang}-${appearance}"
      mkdir -p "$out"
      video_pid=""
      slow=0
      if [ "$first" = 1 ] && [ "$VIDEO" = 1 ]; then
        xcrun simctl io "$udid" recordVideo --codec=h264 --force "screens/${slug}/tour-${lang}-${appearance}.mp4" &
        video_pid=$!
        slow=1
        sleep 2
      fi
      TEST_RUNNER_WEYDA_LANG="$lang" TEST_RUNNER_WEYDA_SLOW="$slow" TEST_RUNNER_WEYDA_LIVE_API=0 \
        xcodebuild test-without-building \
        -xctestrun "$xctestrun" \
        -destination "id=$udid" \
        -only-testing:WeydaUITests \
        -resultBundlePath "build/results/${run_name}.xcresult" \
        2>&1 | xcbeautify --renderer github-actions
      status=${PIPESTATUS[0]}
      if [ -n "$video_pid" ]; then
        kill -INT "$video_pid" 2>/dev/null || true
        wait "$video_pid" 2>/dev/null || true
      fi
      xcrun xcresulttool export attachments --path "build/results/${run_name}.xcresult" --output-path "$out" \
        && python3 scripts/ci/name-attachments.py "$out"
      if [ "$status" -ne 0 ]; then
        echo "::warning::tour en échec : ${run_name} (code ${status})"
        tour_failures=$((tour_failures + 1))
      fi
      first=0
    done
  done
  local tour_secs=$((SECONDS - start)) shots
  shots=$(find screens -name '*.png' | wc -l | tr -d ' ')
  if [ "$tour_failures" -eq 0 ]; then
    summary "| Tour ($LANGS · $APPEARANCES) | $shots captures | $(duration $tour_secs) |"
  else
    summary "| Tour ($LANGS · $APPEARANCES) | **$tour_failures tour(s) en échec**, $shots captures | $(duration $tour_secs) |"
  fi

  # Échecs : détail des tests et rapports de plantage de l'app (artefact de résultats).
  if [ "$unit_status" -ne 0 ] || [ "$tour_failures" -gt 0 ]; then
    local failures
    failures=$(echo "$unit_json" | jq -r '.testFailures[]? | "- \(.testName // "?") : \(.failureText // "" | gsub("\n"; " "))"' 2>/dev/null | head -20 || true)
    [ -z "$failures" ] || summary "" "**Tests unitaires en échec :**" "" "$failures"
    find "$HOME/Library/Logs/DiagnosticReports" -name 'Weyda*' -newer build/logs/.compat-start \
      -exec cp {} build/logs/ \; 2>/dev/null || true
  fi

  xcrun simctl shutdown "$udid" || true
  xcrun simctl delete "$udid" || true
  echo "Captures : $shots · tests unitaires : $unit_counts"
  if [ "$unit_status" -ne 0 ] || [ "$tour_failures" -gt 0 ]; then
    echo "::error::iOS $IOS_VERSION : tests unitaires ou tour en échec (voir le résumé)"
    exit 1
  fi
}

case "${1:-}" in
  download | install | run) "cmd_$1" ;;
  *)
    echo "usage : $0 download|install|run" >&2
    exit 2
    ;;
esac
