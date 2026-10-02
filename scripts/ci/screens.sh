#!/bin/bash
# Tour automatique (WeydaUITests) en API simulée → captures par langue × apparence × appareil,
# plus une vidéo du parcours par appareil. Sortie : screens/<appareil>/<langue>-<apparence>/*.png
# Prérequis : `xcodebuild build-for-testing` déjà fait dans build/dd.
set -uo pipefail

LANGS="${LANGS:-fr ar en}"
APPEARANCES="${APPEARANCES:-light dark}"
IFS=';' read -r -a DEVICE_LIST <<< "${DEVICES:-iPhone 17 Pro Max;iPhone 17e}"

xctestrun=$(find build/dd/Build/Products -name '*.xctestrun' | head -1)
if [ -z "$xctestrun" ]; then
  echo "::error::aucun .xctestrun : lancer build-for-testing d'abord"
  exit 1
fi
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
  # Barre d'état propre (9:41, batterie pleine) : captures dignes de l'App Store.
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

  first=1
  for lang in $LANGS; do
    for appearance in $APPEARANCES; do
      xcrun simctl ui "$udid" appearance "$appearance"
      run="${slug}-${lang}-${appearance}"
      out="screens/${slug}/${lang}-${appearance}"
      mkdir -p "$out"

      video_pid=""
      if [ "$first" = 1 ]; then
        xcrun simctl io "$udid" recordVideo --codec=h264 --force "screens/${slug}/tour-${lang}-${appearance}.mp4" &
        video_pid=$!
        sleep 2
      fi

      TEST_RUNNER_WEYDA_LANG="$lang" TEST_RUNNER_WEYDA_SLOW="$first" xcodebuild test-without-building \
        -xctestrun "$xctestrun" \
        -destination "id=$udid" \
        -only-testing:WeydaUITests \
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
