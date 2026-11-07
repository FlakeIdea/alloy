#!/bin/zsh
# Builds the website downloads: Alloy-<version>.pkg (the installer: checks the Mac, installs the app and Rosetta 2,
# then Alloy downloads the game engine and components with one click) and Alloy-<version>.dmg (drag to
# Applications). See docs/DISTRIBUTION.md first.
#
#   ALLOY_VERSION=1.0.0 ALLOY_COMPONENTS_URL=https://…/components.json scripts/release.sh
#
# Without a Developer ID both are only for this Mac: macOS blocks them on other Macs ("Apple could not verify…").
# For a public download also set:
#   ALLOY_SIGN_IDENTITY       "Developer ID Application: Your Name (TEAMID)" (signs the app and the disk image)
#   ALLOY_INSTALLER_IDENTITY  "Developer ID Installer: Your Name (TEAMID)" (signs the .pkg)
#   ALLOY_NOTARY_PROFILE      a notarytool keychain profile: xcrun notarytool store-credentials <name> …
#   ALLOY_BUNDLE_ID           your reverse-DNS app id, for example com.example.alloy
set -eu
cd "$(dirname "$0")/.."
: "${ALLOY_VERSION:?Set ALLOY_VERSION, for example 1.0.0}"
[ -n "${ALLOY_COMPONENTS_URL:-}" ] || echo "Note: ALLOY_COMPONENTS_URL is not set; users must install the game engine from a package file."
scripts/build-app.sh release
APP=build/Alloy.app

if [ -n "${ALLOY_SIGN_IDENTITY:-}" ]; then
  echo "Signing with $ALLOY_SIGN_IDENTITY (hardened runtime)…"
  codesign --force --options runtime --timestamp --sign "$ALLOY_SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

DMG="build/Alloy-$ALLOY_VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$STAGE/Alloy.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Alloy $ALLOY_VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [ -n "${ALLOY_SIGN_IDENTITY:-}" ]; then codesign --force --timestamp --sign "$ALLOY_SIGN_IDENTITY" "$DMG"; fi

PKG="build/Alloy-$ALLOY_VERSION.pkg"
scripts/make-installer.sh "$APP" "$PKG"

if [ -n "${ALLOY_SIGN_IDENTITY:-}" ] && [ -n "${ALLOY_INSTALLER_IDENTITY:-}" ] && [ -n "${ALLOY_NOTARY_PROFILE:-}" ]; then
  for FILE in "$PKG" "$DMG"; do
    echo "Notarising $FILE (Apple checks the app; this takes a few minutes)…"
    xcrun notarytool submit "$FILE" --keychain-profile "$ALLOY_NOTARY_PROFILE" --wait
    xcrun stapler staple "$FILE"
  done
  spctl --assess --type install --verbose=2 "$PKG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  echo "Not notarised: macOS on other Macs will refuse these files. Set ALLOY_SIGN_IDENTITY, ALLOY_INSTALLER_IDENTITY"
  echo "and ALLOY_NOTARY_PROFILE; see docs/DISTRIBUTION.md."
fi
shasum -a 256 "$PKG" "$DMG"
echo "Built $PKG and $DMG (offer the .pkg as the main download)"
