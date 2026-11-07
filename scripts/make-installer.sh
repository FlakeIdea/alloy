#!/bin/zsh
# Wraps a built Alloy.app in Alloy-<version>.pkg, the installer for a website download. It checks the Mac
# (Apple silicon, macOS 14+), shows the terms (agreeing also covers Apple's Rosetta 2 licence), installs the
# app in /Applications, installs Rosetta 2 if missing, records the accepted terms and opens Alloy, whose setup
# wizard downloads the game engine and the Windows components with one click.
#
#   scripts/make-installer.sh build/Alloy.app build/Alloy-1.0.0.pkg
#
#   ALLOY_VERSION              version shown in the installer (default: the app's CFBundleShortVersionString)
#   ALLOY_INSTALLER_IDENTITY   "Developer ID Installer: Your Name (TEAMID)" to sign the package (needed on other Macs)
# release.sh calls this; it signs the app first and notarises the package afterwards.
set -eu
cd "$(dirname "$0")/.."
APP=${1:?usage: make-installer.sh <Alloy.app> <output.pkg>}
OUT=${2:?usage: make-installer.sh <Alloy.app> <output.pkg>}
[ -x "$APP/Contents/MacOS/Alloy" ] || { echo "$APP is not a built Alloy.app" >&2; exit 2; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
VERSION=${ALLOY_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")}
PKG_ID="$BUNDLE_ID.pkg"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/Applications" "$WORK/scripts" "$WORK/resources"
# Without quarantine and other extended attributes (macOS keeps its own provenance attribute, which Installer restores).
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$WORK/root/Applications/Alloy.app"
codesign --verify --strict "$WORK/root/Applications/Alloy.app"

# Installer pages and the terms version come from the same text the app shows.
swift build -c release --product alloyctl >/dev/null
"$(swift build -c release --show-bin-path)/alloyctl" installer-pages "$WORK/resources" >/dev/null
mv "$WORK/resources/terms-version" "$WORK/scripts/terms-version"
cp -X scripts/installer/postinstall "$WORK/scripts/postinstall"
chmod 755 "$WORK/scripts/postinstall"
xattr -cr "$WORK/scripts" "$WORK/resources" 2>/dev/null || true
sips -z 160 160 Resources/AppIcon.png --out "$WORK/resources/background.png" >/dev/null

# Always install to /Applications, even if another copy of the app exists elsewhere on the disk.
export COPYFILE_DISABLE=1
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" --scripts "$WORK/scripts" \
  --identifier "$PKG_ID" --version "$VERSION" --install-location / "$WORK/Alloy-app.pkg" >/dev/null

sed -e "s/@VERSION@/$VERSION/g" -e "s/@PKG_ID@/$PKG_ID/g" scripts/installer/Distribution.xml > "$WORK/Distribution.xml"
SIGN=()
if [ -n "${ALLOY_INSTALLER_IDENTITY:-}" ]; then
  SIGN=(--sign "$ALLOY_INSTALLER_IDENTITY" --timestamp)
else
  echo "Note: ALLOY_INSTALLER_IDENTITY is not set; the package is unsigned and macOS on other Macs will refuse it."
fi
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
productbuild --distribution "$WORK/Distribution.xml" --resources "$WORK/resources" --package-path "$WORK" "${SIGN[@]}" "$OUT" >/dev/null
echo "Built $OUT ($VERSION, $PKG_ID)"
