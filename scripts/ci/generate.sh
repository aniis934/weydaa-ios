#!/bin/bash
# Génère Weyda.xcodeproj depuis project.yml (XcodeGen installé par install-xcodegen.sh).
set -euo pipefail

binary=$(cat "$HOME/.xcodegen-dist/path.txt")
"$binary" generate --spec project.yml
xcodebuild -version
