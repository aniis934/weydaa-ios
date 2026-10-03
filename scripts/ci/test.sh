#!/bin/bash
# Compile l'app pour le simulateur et lance les tests unitaires (WeydaTests).
# Journal brut : build/logs/xcodebuild.log ; résultats : build/results/unit.xcresult.
set -euo pipefail

device="${SIM_DEVICE:-iPhone 17 Pro}"
mkdir -p build/logs build/results
rm -rf build/results/unit.xcresult

# Signature « ad hoc » du simulateur (CODE_SIGN_IDENTITY=-, sans équipe Apple) : une app non signée
# n'a pas accès au trousseau, et les tests de la session (KeychainSessionStorageTests) seraient sautés.
xcodebuild test \
  -project Weyda.xcodeproj \
  -scheme Weyda \
  -destination "platform=iOS Simulator,name=${device},OS=latest" \
  -only-testing:WeydaTests \
  -resultBundlePath build/results/unit.xcresult \
  -derivedDataPath build/dd \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | tee build/logs/xcodebuild.log | xcbeautify --renderer github-actions

echo "── Décompte des tests ──"
xcrun xcresulttool get test-results summary --path build/results/unit.xcresult --compact || true
