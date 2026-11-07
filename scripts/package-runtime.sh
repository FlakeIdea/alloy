#!/bin/zsh
# Packs an Alloy runtime folder into a downloadable game engine package and lists it in components.json.
#
#   scripts/package-runtime.sh <runtime-dir> <out-dir> <package-id> "<display name>" [version]
#
# <runtime-dir> is a folder under ~/Library/Application Support/Alloy/Runtimes (it holds wine/bin/wine).
# Upload everything in <out-dir> to one place (for example a GitHub release), then build the app with
#   ALLOY_COMPONENTS_URL=<that place>/components.json scripts/build-app.sh
# The newest package goes first in components.json; Alloy offers the first one.
#
# Licence texts must travel with the binaries (LGPL and Apache-2.0 require it). They are collected into licenses/ from:
#   ALLOY_SOURCES_TARBALL  CrossOver's crossover-sources-<version>.tar.gz the runtime was built from
#   ALLOY_WINE_WORK        the work folder patch-wine-runtime.sh used (GLib's libffi, pcre2 and proxy-libintl)
#   ALLOY_EXTRA_LICENSES   a folder copied as is, for the rest; DXMT's LICENSE (from its source archive) goes here
set -eu
[ $# -ge 4 ] || { sed -n 2,14p "$0"; exit 2; }
src=${1:A} out=$2 id=$3 name=$4 version=${5:-$3}
[ -x "$src/wine/bin/wine" ] || { echo "No wine/bin/wine in $src" >&2; exit 2; }
case $id in *[!A-Za-z0-9._-]*) echo "Package ids use letters, digits, '.', '_' and '-' only." >&2; exit 2;; esac
mkdir -p "$out"
out=${out:A}
folder="alloy-$id"
stage=$(mktemp -d "${TMPDIR:-/tmp}/alloy-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT

echo "Copying $src (without headers, static libraries and backups)…"
rsync -a --exclude 'wine/include' --exclude 'alloy-backup' --exclude 'alloy-package.json' \
  --exclude '*.a' --exclude '*.la' "$src/" "$stage/$folder/"

# The runtime manifest records folders on the build machine; keep only what Alloy reads.
python3 -I - "$stage/$folder/alloy-runtime.json" "$name" <<'PY'
import json, sys, time
path, name = sys.argv[1], sys.argv[2]
try:
    old = json.load(open(path))
except FileNotFoundError:
    old = {}
keep = {k: old[k] for k in ("translationLayer", "baseRuntimeVersion", "d3dMetalSource") if k in old}
keep["name"] = name
keep["createdAt"] = time.time() - 978307200  # Foundation's reference date (2001-01-01)
json.dump(keep, open(path, "w"), indent=2, sort_keys=True)
PY

# MoltenVK's own install name points into the folder it was built in.
for lib in "$stage/$folder"/wine/lib/libMoltenVK.dylib(N); do
  install_name_tool -id @rpath/libMoltenVK.dylib "$lib" 2>/dev/null
  codesign --force --sign - "$lib" >/dev/null 2>&1
done

# Licence texts, one folder per component.
lic="$stage/$folder/licenses"
mkdir -p "$lic"
missing=()
if [ -n "${ALLOY_SOURCES_TARBALL:-}" ]; then
  [ -f "$ALLOY_SOURCES_TARBALL" ] || { echo "No such file: $ALLOY_SOURCES_TARBALL" >&2; exit 2; }
  tar -xzf "$ALLOY_SOURCES_TARBALL" -C "$stage" \
    --include 'sources/*/COPYING*' --include 'sources/*/LICENSE*' --include 'sources/gnutls/*/COPYING*' --include 'sources/gnutls/*/LICENSE*'
  for c in wine gstreamer glib gnutls/gnutls gnutls/gmp gnutls/nettle moltenvk freetype vkd3d; do
    files=("$stage/sources/$c"/(COPYING*|LICENSE*|LICENCE*)(N-.))  # GLib's COPYING is a link into LICENSES/
    if [ ${#files} -gt 0 ]; then mkdir -p "$lic/${c:t}"; cp -L "${files[@]}" "$lic/${c:t}/"; else missing+=("$c"); fi
  done
  rm -rf "$stage/sources"
else
  missing+=("Wine, GStreamer, GLib, GnuTLS, GMP, nettle, MoltenVK, FreeType, vkd3d (set ALLOY_SOURCES_TARBALL)")
fi
subprojects="${ALLOY_WINE_WORK:-$HOME/Library/Caches/Alloy/wine-runtime-patch}/gstreamer/gst-src/subprojects"
for sp in libffi proxy-libintl pcre2; do
  files=("$subprojects/$sp"*/(COPYING*|LICENSE*|LICENCE*)(N-.))
  if [ ${#files} -gt 0 ]; then mkdir -p "$lic/$sp"; cp -L "${files[@]}" "$lic/$sp/"; else missing+=("$sp (set ALLOY_WINE_WORK)"); fi
done
if [ -n "${ALLOY_EXTRA_LICENSES:-}" ]; then
  cp -R "$ALLOY_EXTRA_LICENSES/" "$lic/"
else
  missing+=("DXMT (put its LICENSE in a folder named dxmt under ALLOY_EXTRA_LICENSES)")
fi
if [ ${#missing} -gt 0 ]; then
  echo "WARNING: no licence text for: ${(j:; :)missing}"
  echo "         Publish a package only with every licence included. See docs/DISTRIBUTION.md."
fi

# Build folders often end up inside binaries (debug info, __FILE__). They name your user account.
user=$(id -un)
leaks=$(LC_ALL=C grep -rl -a -- "/$user" "$stage/$folder" 2>/dev/null | wc -l | tr -d ' ')
if [ "$leaks" -gt 0 ]; then
  echo "WARNING: $leaks file(s) contain paths with your user name ($user), from the folders the runtime was built in."
  echo "         For a public release, rebuild it in a neutral folder, for example:"
  echo "         ALLOY_WINE_WORK=/tmp/alloy-build scripts/patch-wine-runtime.sh <crossover-sources.tar.gz> <runtime-dir>"
fi

archive="$out/$folder.tar.xz"
echo "Compressing to $archive…"
installed=$(( $(du -sk "$stage/$folder" | awk '{print $1}') * 1024 ))
tar -C "$stage" --options xz:compression-level=6,xz:threads=0 -cJf "$archive" "$folder"
sha=$(shasum -a 256 "$archive" | awk '{print $1}')
bytes=$(stat -f %z "$archive")

python3 -I - "$out/components.json" "$id" "$name" "$version" "${archive:t}" "$sha" "$bytes" "$installed" <<'PY'
import json, sys
path, pid, name, version, file, sha, size, installed = sys.argv[1:9]
try:
    manifest = json.load(open(path))
except FileNotFoundError:
    manifest = {"formatVersion": 1, "runtimes": []}
entry = {"id": pid, "name": name, "version": version, "url": file, "sha256": sha,
         "downloadBytes": int(size), "installedBytes": int(installed),
         "summary": "Wine with DXMT (DirectX 10/11 to Metal), video playback and MetalFX upscaling."}
manifest["runtimes"] = [entry] + [r for r in manifest["runtimes"] if r["id"] != pid]
json.dump(manifest, open(path, "w"), indent=2)
PY
echo "Packed $folder: $(( bytes / 1000000 )) MB download, $(( installed / 1000000 )) MB installed, sha256 $sha"
echo "Listed in $out/components.json"
