#!/bin/bash
# Compile UpKeepy et l'empaquette dans un bundle .app lançable.
# Nécessaire car une app barre de menu doit tourner depuis un .app
# (avec Info.plist + LSUIElement) pour ne pas apparaître dans le Dock.
#
# Usage :
#   ./build.sh                 build local, signature ad-hoc (dev)
#   SIGN_IDENTITY="Developer ID Application: … (TEAMID)" ./build.sh
#                              build distribuable, hardened runtime + horodatage
#
# Pour produire un DMG notarié prêt à publier, passer par ./release.sh.
set -euo pipefail

APP_NAME="UpKeepy"
BUNDLE="${APP_NAME}.app"
BUNDLE_ID="fr.anisse.upkeepy"
VERSION="${VERSION:-1.0.0}"
# "-" = signature ad-hoc : suffisante en local, refusée par Gatekeeper ailleurs.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$(dirname "$0")"

echo "==> Compilation (release)…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> Empaquetage de ${BUNDLE} (version ${VERSION})…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
cp "$BIN_PATH" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Icône d'app (régénérable via Tools/make-icon.swift + iconutil).
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleIdentifier</key>          <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>                <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundleVersion</key>             <string>${VERSION}</string>
    <key>LSApplicationCategoryType</key>   <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHumanReadableCopyright</key>    <string>Copyright © 2026 anisselbd. Sous licence MIT.</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Signature ad-hoc (usage local uniquement)…"
    codesign --force --sign - "$BUNDLE"
else
    # Hardened runtime + horodatage : les deux sont exigés par la notarisation.
    echo "==> Signature « ${SIGN_IDENTITY} » (hardened runtime)…"
    codesign --force --options runtime --timestamp \
             --entitlements Resources/UpKeepy.entitlements \
             --sign "$SIGN_IDENTITY" "$BUNDLE"
    codesign --verify --strict --verbose=2 "$BUNDLE"
fi

echo "==> Terminé : ${PWD}/${BUNDLE}"
echo "    Lancer avec :  open \"${BUNDLE}\""
