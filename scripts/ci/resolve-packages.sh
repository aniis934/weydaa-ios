#!/bin/bash
# Résout les paquets Swift du projet (Firebase, version exacte de project.yml) dans un dossier COMMUN à toutes les
# compilations de la CI : SPM_DIR (défaut build/spm), passé aussi à `xcodebuild` par test.sh et par le workflow
# ios-screens (-clonedSourcePackagesDirPath). Le dossier est mis en cache par actions/cache (clé = hachage de
# project.yml) : le gros dépôt firebase-ios-sdk n'est pas recloné à chaque envoi. À lancer après generate.sh.
set -euo pipefail

dir="${SPM_DIR:-build/spm}"
mkdir -p "$dir" build/logs

started=$(date +%s)
xcodebuild -resolvePackageDependencies \
  -project Weyda.xcodeproj \
  -scheme Weyda \
  -clonedSourcePackagesDirPath "$dir" \
  2>&1 | tee build/logs/resolve-packages.log
echo "Paquets résolus en $(( $(date +%s) - started )) s : $(du -sh "$dir" | cut -f1) dans $dir"
