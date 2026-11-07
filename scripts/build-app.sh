#!/bin/sh
# Builds build/Alloy.app from the Swift package using only the Command Line Tools.
# The bundle is ad-hoc signed for local use; scripts/release.sh signs and notarises it for downloads.
#   ALLOY_COMPONENTS_URL  where the app finds components.json (the game engine download), see package-runtime.sh
#   ALLOY_VERSION         version number, such as 1.0 (dotted numbers only: update checks compare it), default 0.1.0
#   ALLOY_STAGE           a word shown after the version, such as Beta; empty for none
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
# Source paths are written relative to the repository, so the app carries no user name or folder of the Mac it was built on.
# One universal app: Apple silicon and Intel Macs. ALLOY_ARCHS=arm64 builds for this Mac only, faster while working.
ARCHS="${ALLOY_ARCHS:-arm64 x86_64}"
SLICES=""
for ARCH in $ARCHS; do
  swift build -c "$CONFIG" --product Alloy --triple "$ARCH-apple-macosx14.0" -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
  BIN="$(swift build -c "$CONFIG" --triple "$ARCH-apple-macosx14.0" --show-bin-path)"
  # Relative to the repository, so a folder name with spaces can't split the list.
  SLICES="$SLICES ${BIN#"$PWD"/}/Alloy"
done
APP=build/Alloy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP/Contents/MacOS/Alloy"
# Debug symbols point at the build folder's object files; strip them.
strip -S -x "$APP/Contents/MacOS/Alloy"
if LC_ALL=C grep -q -e "$HOME" -e "$PWD" "$APP/Contents/MacOS/Alloy"; then
  echo "The app still contains a path from this Mac ($HOME)." >&2; exit 1
fi
# App icon: Resources/AppIcon.png is drawn by scripts/make-icon.swift.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
# The build number is the commit count: a plain number, never a Git label people would see.
VERSION="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SHORT_VERSION="${ALLOY_VERSION:-0.1.0}"
case "$SHORT_VERSION" in *[!0-9.]*) echo "ALLOY_VERSION must be dotted numbers, such as 1.0; put words like Beta in ALLOY_STAGE" >&2; exit 2;; esac
STAGE="${ALLOY_STAGE-}"
case "$STAGE" in *[!A-Za-z0-9\ ]*) echo "ALLOY_STAGE may hold only letters, digits and spaces" >&2; exit 2;; esac
# Where the app finds the game engine. flake.co.in publishes components.json, which points at the engine wherever it is
# hosted, so the engine can move without a new app. Set ALLOY_COMPONENTS_URL= (empty) for a build without one.
COMPONENTS_URL="${ALLOY_COMPONENTS_URL-https://flake.co.in/alloy/components.json}"
case "$COMPONENTS_URL" in ""|https://*|http://127.0.0.1*|http://localhost*) ;; *) echo "ALLOY_COMPONENTS_URL must be https://" >&2; exit 2;; esac
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Alloy</string>
  <key>CFBundleDisplayName</key><string>Alloy</string>
  <key>CFBundleIdentifier</key><string>${ALLOY_BUNDLE_ID:-in.co.flake.Alloy}</string>
  <key>CFBundleExecutable</key><string>Alloy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>AlloyVersionStage</key><string>$STAGE</string>
  <key>AlloyComponentsURL</key><string>$COMPONENTS_URL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Flake</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>Games you start in Alloy find and join other players on your local network, for LAN and local co-op play.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
