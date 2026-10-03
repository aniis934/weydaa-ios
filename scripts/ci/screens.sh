#!/bin/bash
# Tour automatique (WeydaUITests) en API simulée → captures par langue × apparence × appareil,
# plus une vidéo du premier tour si VIDEO=1. Sortie : screens/<appareil>/<langue>-<apparence>/*.png
# Prérequis : produits de `xcodebuild build-for-testing` dans build/dd/Build/Products.
set -uo pipefail

LANGS="${LANGS:-fr ar en}"
APPEARANCES="${APPEARANCES:-light dark}"
VIDEO="${VIDEO:-1}"
# Classes du tour (« TourChatTests TourInboxTests ») ; vide = tout WeydaUITests.
TESTS="${TESTS:-}"
# Taille du texte du simulateur (Dynamic Type), ex. accessibility-extra-extra-extra-large ; vide = défaut.
CONTENT_SIZE="${CONTENT_SIZE:-}"
only=()
if [ -n "$TESTS" ]; then
  for t in $TESTS; do only+=("-only-testing:WeydaUITests/$t"); done
else
  only=("-only-testing:WeydaUITests")
fi
suffix=""
[ -n "$CONTENT_SIZE" ] && suffix="-${CONTENT_SIZE}"
IFS=';' read -r -a DEVICE_LIST <<< "${DEVICES:-iPhone 17 Pro Max;iPhone 17e}"

products=build/dd/Build/Products
xctestrun=$(find "$products" -maxdepth 1 -name '*.xctestrun' | head -1)
if [ -z "$xctestrun" ]; then
  echo "::error::aucun .xctestrun : lancer build-for-testing d'abord"
  exit 1
fi
app=$(find "$products" -maxdepth 2 -name 'Weyda.app' -type d | head -1)
runtime=$(xcrun simctl list runtimes available -j \
  | jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')
echo "Runtime : $runtime"

mkdir -p screens build/results
failures=0

for device in "${DEVICE_LIST[@]}"; do
  slug=$(echo "$device" | tr ' ' '-' | tr -cd '[:alnum:]-')
  udid=$(xcrun simctl create "Weyda $device" "$device" "$runtime")
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  if [ -n "$CONTENT_SIZE" ]; then
    xcrun simctl ui "$udid" content_size "$CONTENT_SIZE" || echo "::warning::taille de texte refusée : $CONTENT_SIZE"
  fi
  # Barre d'état propre (9:41, batterie pleine) : captures dignes de l'App Store.
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

  # Préchauffage : premier lancement de l'app sur un simulateur neuf (≈ 60 s d'attente de l'outil de
  # test au premier tour de la phase 0, absente des tours suivants). On le paie ici, hors du tour filmé.
  if [ -n "$app" ]; then
    xcrun simctl install "$udid" "$app" \
      && xcrun simctl launch "$udid" com.weydaa.app -WeydaMockAPI YES -WeydaSkipLaunch YES > /dev/null \
      && sleep 8 \
      && xcrun simctl terminate "$udid" com.weydaa.app || true
  fi

  first=1
  for lang in $LANGS; do
    for appearance in $APPEARANCES; do
      xcrun simctl ui "$udid" appearance "$appearance"
      run="${slug}-${lang}-${appearance}${suffix}"
      out="screens/${slug}/${lang}-${appearance}${suffix}"
      mkdir -p "$out"

      video_pid=""
      if [ "$first" = 1 ] && [ "$VIDEO" = 1 ]; then
        xcrun simctl io "$udid" recordVideo --codec=h264 --force "screens/${slug}/tour-${lang}-${appearance}.mp4" &
        video_pid=$!
        sleep 2
      fi

      slow=0
      [ -n "$video_pid" ] && slow=1
      TEST_RUNNER_WEYDA_LANG="$lang" TEST_RUNNER_WEYDA_SLOW="$slow" xcodebuild test-without-building \
        -xctestrun "$xctestrun" \
        -destination "id=$udid" \
        "${only[@]}" \
        -resultBundlePath "build/results/${run}.xcresult" \
        2>&1 | xcbeautify --renderer github-actions
      status=${PIPESTATUS[0]}

      if [ -n "$video_pid" ]; then
        kill -INT "$video_pid" 2>/dev/null || true
        wait "$video_pid" 2>/dev/null || true
      fi

      xcrun xcresulttool export attachments --path "build/results/${run}.xcresult" --output-path "$out" \
        && python3 scripts/ci/name-attachments.py "$out"

      if [ "$status" -ne 0 ]; then
        echo "::warning::tour en échec : ${run} (code ${status})"
        failures=$((failures + 1))
      fi
      first=0
    done
  done
  xcrun simctl shutdown "$udid" || true
  xcrun simctl delete "$udid" || true
done

echo "Captures : $(find screens -name '*.png' | wc -l | tr -d ' ') · vidéos : $(find screens -name '*.mp4' | wc -l | tr -d ' ')"
if [ "$failures" -gt 0 ]; then
  echo "::error::${failures} tour(s) en échec"
  exit 1
fi
