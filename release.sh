#!/bin/bash
# Produit un DMG signé, notarié et agrafé, prêt à être publié en GitHub Release
# puis référencé par un cask Homebrew.
#
# Prérequis (une seule fois, voir docs/RELEASING.md) :
#   1. un certificat « Developer ID Application » dans le trousseau ;
#   2. un profil notarytool enregistré :
#        xcrun notarytool store-credentials "upkeepy" \
#          --apple-id "<ton Apple ID>" --team-id "<TEAM_ID>" --password "<mdp app dédié>"
#
# Usage :
#   ./release.sh                  version par défaut
#   VERSION=1.1.0 ./release.sh    version explicite
#   SKIP_NOTARIZE=1 ./release.sh  répétition à blanc, sans passer par Apple
set -euo pipefail

APP_NAME="UpKeepy"
BUNDLE="${APP_NAME}.app"
VERSION="${VERSION:-1.0.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-upkeepy}"
DIST_DIR="dist"
DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

cd "$(dirname "$0")"

# --- 1. Identité de signature -------------------------------------------------
# On la déduit du trousseau pour ne pas coder en dur un Team ID dans le dépôt.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    # Le « || true » est indispensable : sans lui, un grep sans résultat ferait
    # mourir le script (set -e + pipefail) avant l'explication ci-dessous.
    SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" \
        | head -1 | sed -E 's/.*"(.+)".*/\1/' || true)"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
    cat >&2 <<'HELP'
✗ Aucun certificat « Developer ID Application » trouvé dans le trousseau.

  Un certificat « Apple Development » ne suffit pas : il ne permet que le test
  en local, et Gatekeeper bloquera l'app chez tout le monde.

  Pour en créer un (compte Apple Developer payant requis) :
    Xcode → Settings → Accounts → ton compte → Manage Certificates…
    → bouton + → « Developer ID Application »

  Puis relancer ce script.
HELP
    exit 1
fi

echo "==> Identité : ${SIGN_IDENTITY}"

# --- 2. Build signé -----------------------------------------------------------
VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" ./build.sh

# --- 3. Notarisation de l'app elle-même ---------------------------------------
# On agrafe le ticket à l'app AVANT de l'enfermer dans le DMG. Sans cela, l'app
# copiée dans /Applications ne porte aucun ticket : Gatekeeper doit alors
# interroger Apple en ligne, et un utilisateur hors ligne ou derrière un réseau
# filtrant voit « UpKeepy est endommagé ». Le DMG est notarié séparément plus
# bas, car c'est lui que l'utilisateur télécharge.
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    echo "==> Notarisation de l'app (1/2)…"
    mkdir -p "$DIST_DIR"
    APP_ZIP="${DIST_DIR}/${APP_NAME}-app.zip"
    # ditto plutôt que zip : préserve les métadonnées du bundle.
    ditto -c -k --keepParent "$BUNDLE" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$BUNDLE"
    rm -f "$APP_ZIP"
fi

# --- 4. Fabrication du DMG ----------------------------------------------------
# Un dossier intermédiaire contenant l'app + un alias vers /Applications, pour
# que l'utilisateur n'ait qu'à glisser l'icône d'un côté à l'autre.
echo "==> Fabrication du DMG…"
mkdir -p "$DIST_DIR"
rm -f "$DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov "$DMG" >/dev/null

# Le DMG est signé lui aussi : c'est le fichier que l'utilisateur télécharge,
# donc celui que Gatekeeper inspecte en premier.
echo "==> Signature du DMG…"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

# --- 5. Notarisation du DMG ---------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "==> Notarisation ignorée (SKIP_NOTARIZE=1). DMG non distribuable."
else
    echo "==> Notarisation du DMG (2/2)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    # L'agrafage colle le ticket au DMG : l'app s'ouvre alors même hors ligne.
    echo "==> Agrafage du ticket…"
    xcrun stapler staple "$DMG"

    echo "==> Vérification Gatekeeper…"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

# --- 6. Cask Homebrew ---------------------------------------------------------
# Généré ici plutôt que recopié à la main : la version et le sha256 doivent
# correspondre exactement au DMG publié, sinon l'installation échoue chez tout
# le monde. Voir docs/HOMEBREW.md.
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
SIZE="$(du -h "$DMG" | awk '{print $1}')"
CASK="${DIST_DIR}/upkeepy.rb"

cat > "$CASK" <<CASKFILE
cask "upkeepy" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/anisselbd/upkeepy/releases/download/v#{version}/UpKeepy-#{version}.dmg",
      verified: "github.com/anisselbd/upkeepy/"
  name "UpKeepy"
  desc "Menu bar app that keeps Homebrew, npm, RubyGems and macOS up to date"
  homepage "https://upkeepy.fr/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "UpKeepy.app"

  zap trash: [
    "~/Library/Preferences/fr.anisse.upkeepy.plist",
  ]
end
CASKFILE

# --- 7. Récapitulatif ---------------------------------------------------------
echo
echo "✓ ${DMG}  (${SIZE})"
echo "  sha256 : ${SHA}"
echo "✓ ${CASK}"
echo
echo "Suite :"
echo "  1. gh release create v${VERSION} \"${DMG}\" --title \"UpKeepy ${VERSION}\" --notes-file docs/release-notes.md"
echo "  2. cp ${CASK} ../homebrew-tap/Casks/  puis pousser  (voir docs/HOMEBREW.md)"
