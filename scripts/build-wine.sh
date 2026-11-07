#!/bin/bash
# Builds the base Wine for Alloy's game engine from CodeWeavers' open-source CrossOver release, with Alloy's patches.
#
#   scripts/build-wine.sh <crossover-sources-26.3.0.tar.gz> <libMoltenVK.dylib>
#
# The result is <work>/install, a Wine install root for `alloyctl import-wine`. Then add DXMT with
# `alloyctl import-dxmt` and fill the remaining gaps with scripts/patch-wine-runtime.sh. docs/DISTRIBUTION.md has the
# whole sequence.
#
# Build folders end up inside the binaries, so the work folder defaults to /tmp/alloy-build: nothing personal, such as
# a home folder name, ends up in a published engine. Set ALLOY_WINE_WORK to change it.
#
# <libMoltenVK.dylib> is an x86_64 (or universal) MoltenVK build (Apache-2.0), for example the one in Wine Devel
# (Contents/Resources/wine/lib). Needs Xcode's command line tools, plus mingw-w64, bison, autoconf,
# automake and libtool from Homebrew.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { sed -n 's/^#   \(scripts\/build-wine.sh .*\)/usage: \1/p' "$0"; exit 2; }
tarball="$1" moltenvk="$2"
[ -f "$tarball" ] || { echo "No such source archive: $tarball" >&2; exit 1; }
[ -f "$moltenvk" ] || { echo "No such MoltenVK library: $moltenvk" >&2; exit 1; }
lipo -archs "$moltenvk" | grep -qw x86_64 || { echo "$moltenvk has no x86_64 code" >&2; exit 1; }
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "mingw-w64 is needed: brew install mingw-w64" >&2; exit 1; }

work="${ALLOY_WINE_WORK:-/tmp/alloy-build}"
deps="$work/deps-x86_64" build="$work/wine-build" install="$work/install"
jobs="$(sysctl -n hw.ncpu)"
mkdir -p "$work"
case "$work" in "$HOME"/*) echo "Warning: $work is inside your home folder, so its name ends up in the binaries." >&2;; esac

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/libtool/libexec/gnubin:/opt/homebrew/bin:$PATH"
command -v autoconf >/dev/null && command -v libtoolize >/dev/null ||
    { echo "FreeType needs autotools: brew install autoconf automake libtool" >&2; exit 1; }
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64"
export CFLAGS="-O2 -mmacosx-version-min=11.0" OBJCFLAGS="-O2 -mmacosx-version-min=11.0"

echo "Unpacking Wine and FreeType sources…"
rm -rf "$work/sources" "$build" "$install" "$deps"
tar -xzf "$tarball" -C "$work" sources/wine sources/freetype
for p in "$repo"/patches/wine/*.patch; do
    echo "Applying $(basename "$p")"
    patch -d "$work/sources/wine" -p1 --quiet < "$p"
done

echo "Building FreeType…"
(
    cd "$work/sources/freetype"
    # The release leaves out the dlg submodule, which FreeType only compiles for FT_DEBUG_LOGGING. Empty stand-ins
    # satisfy autogen.sh and the makefiles without a git checkout.
    mkdir -p subprojects/dlg/include/dlg subprojects/dlg/src/dlg
    touch subprojects/dlg/include/dlg/dlg.h subprojects/dlg/include/dlg/output.h subprojects/dlg/src/dlg/dlg.c
    [ -f builds/unix/configure ] || ./autogen.sh >"$work/freetype-autogen.log" 2>&1
    ./configure --host=x86_64-apple-darwin --prefix="$deps" --without-harfbuzz --without-png --without-brotli \
        --without-bzip2 --with-zlib=yes >"$work/freetype-configure.log" 2>&1
    make -j"$jobs" >"$work/freetype-make.log" 2>&1
    make install >"$work/freetype-install.log" 2>&1
)

# Wine finds Vulkan by linking against MoltenVK, which must name itself by @rpath so the engine can move.
cp "$moltenvk" "$deps/lib/libMoltenVK.dylib"
chmod u+w "$deps/lib/libMoltenVK.dylib"
install_name_tool -id @rpath/libMoltenVK.dylib "$deps/lib/libMoltenVK.dylib" 2>/dev/null
codesign --force --sign - "$deps/lib/libMoltenVK.dylib" >/dev/null 2>&1

echo "Configuring Wine…"
mkdir -p "$build"
cd "$build"
LDFLAGS="-L$deps/lib -mmacosx-version-min=11.0 -Wl,-rpath,@loader_path/../../ -Wl,-rpath,@loader_path/../../external" \
FREETYPE_CFLAGS="-I$deps/include/freetype2" FREETYPE_LIBS="-L$deps/lib -lfreetype" \
"$work/sources/wine/configure" --prefix="$install" --host=x86_64-apple-darwin \
    --enable-archs=i386,x86_64 --disable-tests --without-x --without-wayland \
    --without-alsa --without-oss --without-pulse --without-capi --without-dbus --without-gphoto --without-gssapi \
    --without-krb5 --without-netapi --without-pcap --without-pcsclite --without-sane --without-udev --without-unwind \
    --without-usb --without-v4l2 --without-gstreamer --without-gnutls --without-sdl --without-cups --without-ffmpeg \
    --without-inotify --without-opencl --with-freetype >"$work/wine-configure.log" 2>&1
grep -q '^#define SONAME_LIBVULKAN' include/config.h || { echo "Wine's configure did not find MoltenVK" >&2; exit 1; }

echo "Building Wine with $jobs jobs (about 15 minutes on an M4)…"
make -j"$jobs" >"$work/wine-make.log" 2>&1 || { tail -20 "$work/wine-make.log" >&2; exit 1; }
make install >"$work/wine-install.log" 2>&1
cp "$deps/lib/libfreetype.6.dylib" "$deps/lib/libMoltenVK.dylib" "$install/lib/"

"$install/bin/wine" --version
echo "Built $install"
