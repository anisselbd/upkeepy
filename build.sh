#!/bin/bash
# Compile UpKeepy et l'empaquette dans un bundle .app lançable.
# Nécessaire car une app barre de menu doit tourner depuis un .app
# (avec Info.plist + LSUIElement) pour ne pas apparaître dans le Dock.
set -euo pipefail

APP_NAME="UpKeepy"
BUNDLE="${APP_NAME}.app"
BUNDLE_ID="fr.anisse.upkeepy"
VERSION="1.0"

cd "$(dirname "$0")"

echo "==> Compilation (release)…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> Empaquetage de ${BUNDLE}…"
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
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHumanReadableCopyright</key>    <string>UpKeepy — maintenance Mac</string>
</dict>
</plist>
PLIST

# Signature ad-hoc : suffisante pour un usage local.
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "==> Terminé : ${PWD}/${BUNDLE}"
echo "    Lancer avec :  open \"${BUNDLE}\""
