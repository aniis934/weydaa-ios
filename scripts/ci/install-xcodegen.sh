#!/bin/bash
# Installe XcodeGen (version épinglée XCODEGEN_VERSION) dans ~/.xcodegen-dist, depuis la release
# officielle GitHub. Outil de génération du projet seulement : rien n'est embarqué dans l'app.
set -euo pipefail

version="${XCODEGEN_VERSION:?XCODEGEN_VERSION manquant}"
dest="$HOME/.xcodegen-dist"
archive="${RUNNER_TEMP:-/tmp}/xcodegen.zip"

rm -rf "$dest"
mkdir -p "$dest"
curl -fsSL "https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip" -o "$archive"
unzip -q "$archive" -d "$dest"

binary=$(find "$dest" -type f -name xcodegen -perm -u+x | head -1)
if [ -z "$binary" ]; then
  echo "::error::binaire xcodegen introuvable dans l'archive"
  find "$dest" -maxdepth 3
  exit 1
fi
echo "$binary" > "$dest/path.txt"
"$binary" --version
