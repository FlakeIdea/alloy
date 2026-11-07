#!/bin/bash
# Fills gaps in Alloy runtimes built from CrossOver's source release, without rebuilding all of Wine:
#  - kernelbase.dll with the patches in patches/wine (Steam's web helper draws its windows);
#  - GnuTLS for bcrypt and schannel (secur32), so Windows programs can verify certificates and use HTTPS.
#    gmp, nettle and GnuTLS come from the same release and are linked into one libgnutls.30.dylib;
#  - winegstreamer with GStreamer (scripts/build-gstreamer.sh), so games can play MP4/H.264 videos through Media
#    Foundation and DirectShow. Without it, Unreal Engine menus that use a video background stay blank. Its media
#    source waits for each stream's samples separately, so a video with large audio chunks cannot freeze the game.
#    Its H.264 decoder decodes to system memory when the game's Direct3D device has no NV12 textures (DXMT), so
#    Unreal Engine 5's Electra player gets frames;
#  - winemac.so, which keeps ProMotion displays at 120 Hz when a game asks for 60 Hz exclusive fullscreen, and keeps a
#    cursor the game hid from coming back over it;
#  - ntdll.so, which starts each Windows program from a small app bundle in the games category, so macOS turns on
#    Game Mode for it.
#
#   scripts/patch-wine-runtime.sh <crossover-sources-26.3.0.tar.gz> <runtime-dir>...
#
# <runtime-dir> is a folder under ~/Library/Application Support/Alloy/Runtimes (it holds alloy-runtime.json).
# The first original of each replaced file is kept in <runtime-dir>/alloy-backup. Files are replaced by rename,
# so games already running keep the copies they loaded. Needs mingw-w64 and bison (Homebrew), python3 and, once, the
# nettle 3.10 release tarball from ftp.gnu.org (its sources match the release; the tarball adds `configure`) plus
# the build tools and small sources build-gstreamer.sh fetches.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { sed -n 's/^#   \(scripts\/patch-wine-runtime.sh .*\)/usage: \1/p' "$0"; exit 2; }
tarball="$1"; shift
[ -f "$tarball" ] || { echo "No such source archive: $tarball" >&2; exit 1; }
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "mingw-w64 is needed: brew install mingw-w64" >&2; exit 1; }

work="${ALLOY_WINE_WORK:-$HOME/Library/Caches/Alloy/wine-runtime-patch}"
deps="$work/deps-x86_64"
build="$work/build"
jobs="$(sysctl -n hw.ncpu)"
mkdir -p "$work"

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64"
export CFLAGS="-O2 -mmacosx-version-min=11.0" OBJCFLAGS="-O2 -mmacosx-version-min=11.0"

# Fresh sources every time, so the patches always apply to the release as shipped.
rm -rf "$work/sources"
tar -xzf "$tarball" -C "$work" sources/wine sources/gnutls sources/gstreamer sources/glib
src="$work/sources/wine"
for p in "$repo"/patches/wine/*.patch; do
    echo "Applying $(basename "$p")"
    patch -d "$src" -p1 --quiet < "$p"
done
version="$(awk '{print $3}' "$src/VERSION")"

nettle_tgz="$work/nettle-3.10.tar.gz"
nettle_sha=b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
if [ ! -f "$nettle_tgz" ] || [ "$(shasum -a 256 "$nettle_tgz" | cut -d' ' -f1)" != "$nettle_sha" ]; then
    echo "Downloading nettle 3.10 from ftp.gnu.org"
    curl -fsSL --max-time 300 -o "$nettle_tgz.part" https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz
    [ "$(shasum -a 256 "$nettle_tgz.part" | cut -d' ' -f1)" = "$nettle_sha" ] || { echo "nettle checksum mismatch" >&2; exit 1; }
    mv "$nettle_tgz.part" "$nettle_tgz"
fi
tar -xzf "$nettle_tgz" -C "$work/sources"

# Static gmp and nettle, then a shared GnuTLS that contains them.
dep() { # <name> <source-dir> <configure args...>
    local name=$1 dir=$2; shift 2
    [ -f "$deps/.built-$name" ] && return
    echo "Building $name (log: $work/dep-build/$name)"
    rm -rf "$work/dep-build/$name"; mkdir -p "$work/dep-build/$name"
    (cd "$work/dep-build/$name" &&
        "$dir/configure" --host=x86_64-apple-darwin --prefix="$deps" "$@" > configure.log 2>&1 &&
        make -j"$jobs" > make.log 2>&1 && make install > install.log 2>&1)
    touch "$deps/.built-$name"
}
dep gmp "$work/sources/gnutls/gmp" --disable-shared --enable-static --disable-assembly --disable-cxx
dep nettle "$work/sources/nettle-3.10" --disable-shared --enable-static --disable-documentation --disable-openssl \
    --with-include-path="$deps/include" --with-lib-path="$deps/lib"
NETTLE_CFLAGS="-I$deps/include" NETTLE_LIBS="$deps/lib/libnettle.a" \
HOGWEED_CFLAGS="-I$deps/include" HOGWEED_LIBS="$deps/lib/libhogweed.a" \
GMP_CFLAGS="-I$deps/include" GMP_LIBS="$deps/lib/libgmp.a" LDFLAGS="-mmacosx-version-min=11.0" \
dep gnutls "$work/sources/gnutls/gnutls" --enable-shared --disable-static --with-included-libtasn1 \
    --with-included-unistring --without-p11-kit --without-idn --without-zlib --without-brotli --without-zstd \
    --without-tpm --without-tpm2 --without-libintl-prefix --disable-nls --disable-tools --disable-cxx --disable-doc \
    --disable-tests --disable-guile --disable-libdane
gnutls_lib="$deps/lib/libgnutls.30.dylib"
# Wine dlopens it by file name, which dyld looks up in bcrypt.so's and secur32.so's rpaths (the runtime's lib folder,
# next to libfreetype). No build-machine path stays in the library.
install_name_tool -id @rpath/libgnutls.30.dylib "$gnutls_lib"

gst="$work/gstreamer/install"
if [ ! -f "$work/gstreamer/.built" ]; then
    "$repo/scripts/build-gstreamer.sh" "$work/sources" "$work/gstreamer"
    touch "$work/gstreamer/.built"
fi

# winemac and win32u need Vulkan, as in the full runtime build: configure finds MoltenVK by linking against it, so
# point it at the copy a runtime ships (only linked against here, never installed). The link lives in the work
# folder because LDFLAGS cannot hold a path with spaces, such as "Application Support".
mvk="$work/moltenvk"
rm -rf "$mvk"; mkdir -p "$mvk"
for rt in "$@"; do [ -f "${rt%/}/wine/lib/libMoltenVK.dylib" ] && { ln -s "${rt%/}/wine/lib/libMoltenVK.dylib" "$mvk/"; break; }; done
[ -e "$mvk/libMoltenVK.dylib" ] || { echo "None of the runtimes has lib/libMoltenVK.dylib, which winemac is built against" >&2; exit 1; }
case "$mvk" in *" "*) echo "The work folder $work must not contain spaces (set ALLOY_WINE_WORK)" >&2; exit 1;; esac

echo "Configuring Wine $version (log: $build/configure.log)"
mkdir -p "$build"
(cd "$build" && GNUTLS_CFLAGS="-I$deps/include" GNUTLS_LIBS="-L$deps/lib -lgnutls" \
    GSTREAMER_CFLAGS="-I$gst/include/gstreamer-1.0 -I$gst/include/glib-2.0 -I$gst/lib/glib-2.0/include" \
    GSTREAMER_LIBS="-L$gst/lib -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0" \
    LDFLAGS="-mmacosx-version-min=11.0 -L$mvk -Wl,-rpath,@loader_path/../../ -Wl,-rpath,@loader_path/../../external" \
    "$src/configure" --host=x86_64-apple-darwin --enable-archs=i386,x86_64 --disable-tests \
    --without-x --without-wayland --without-alsa --without-oss --without-pulse --without-capi --without-dbus \
    --without-gphoto --without-gssapi --without-krb5 --without-netapi --without-pcap --without-pcsclite \
    --without-sane --without-udev --without-unwind --without-usb --without-v4l2 --with-gstreamer \
    --without-sdl --without-cups --without-ffmpeg --without-inotify --without-opencl --without-freetype \
    --with-gnutls > configure.log 2>&1)
grep -q '^#define SONAME_LIBGNUTLS "libgnutls.30.dylib"' "$build/include/config.h" ||
    { echo "Wine's configure did not pick up GnuTLS; see $build/configure.log" >&2; exit 1; }
grep -q 'checking for gst_pad_new in -lgstreamer-1.0... yes' "$build/configure.log" ||
    { echo "Wine's configure did not pick up GStreamer; see $build/configure.log" >&2; exit 1; }
grep -q '^#define SONAME_LIBVULKAN "libMoltenVK.dylib"' "$build/include/config.h" ||
    { echo "Wine's configure did not pick up MoltenVK; see $build/configure.log" >&2; exit 1; }

echo "Building kernelbase, bcrypt, secur32, winegstreamer, winemac and ntdll (log: $build/make.log)"
products=(dlls/kernelbase/x86_64-windows/kernelbase.dll dlls/kernelbase/i386-windows/kernelbase.dll
          dlls/bcrypt/bcrypt.so dlls/secur32/secur32.so
          dlls/winegstreamer/x86_64-windows/winegstreamer.dll dlls/winegstreamer/i386-windows/winegstreamer.dll
          dlls/winegstreamer/winegstreamer.so dlls/winemac.drv/winemac.so dlls/ntdll/ntdll.so)
make -C "$build" -j"$jobs" "${products[@]}" > "$build/make.log" 2>&1 ||
    { grep -m10 -E " error:|\*\*\*" "$build/make.log" >&2; echo "Build failed; see $build/make.log" >&2; exit 1; }

# install <runtime-dir> <built file> <path inside the runtime>
install_file() {
    local rt=$1 new=$2 target="$1/wine/$3" backup="$1/alloy-backup/$3"
    if [ -f "$target" ] && cmp -s "$new" "$target"; then echo "  $3: already current"; return; fi
    if [ -f "$target" ] && [ ! -f "$backup" ]; then mkdir -p "$(dirname "$backup")"; cp -p "$target" "$backup"; fi
    cp "$new" "$target.alloy-new"
    mv -f "$target.alloy-new" "$target"
    echo "  $3: installed"
}

for rt in "$@"; do
    rt="${rt%/}"
    lib="$rt/wine/lib/wine"
    if [ ! -f "$rt/alloy-runtime.json" ] || [ ! -f "$lib/x86_64-windows/kernelbase.dll" ]; then
        echo "Skipping $rt: not an Alloy-managed runtime" >&2; continue
    fi
    # Files from another Wine tree would not match this runtime's ntdll, so only CrossOver-source builds of the same
    # version are changed. Their kernelbase carries CodeWeavers' Epic launcher message.
    if ! "$rt/wine/bin/wine" --version 2>/dev/null | grep -qx "wine-$version" ||
       ! LC_ALL=C grep -q -a "HACK: moving EpicGamesLauncher.exe" "$lib/x86_64-windows/kernelbase.dll"; then
        echo "Skipping $rt: not built from CrossOver's Wine $version sources" >&2; continue
    fi
    echo "$(basename "$rt"):"
    install_file "$rt" "$build/dlls/kernelbase/x86_64-windows/kernelbase.dll" lib/wine/x86_64-windows/kernelbase.dll
    install_file "$rt" "$build/dlls/kernelbase/i386-windows/kernelbase.dll" lib/wine/i386-windows/kernelbase.dll
    install_file "$rt" "$build/dlls/bcrypt/bcrypt.so" lib/wine/x86_64-unix/bcrypt.so
    install_file "$rt" "$build/dlls/secur32/secur32.so" lib/wine/x86_64-unix/secur32.so
    install_file "$rt" "$gnutls_lib" lib/libgnutls.30.dylib
    install_file "$rt" "$build/dlls/winegstreamer/x86_64-windows/winegstreamer.dll" lib/wine/x86_64-windows/winegstreamer.dll
    install_file "$rt" "$build/dlls/winegstreamer/i386-windows/winegstreamer.dll" lib/wine/i386-windows/winegstreamer.dll
    install_file "$rt" "$build/dlls/winegstreamer/winegstreamer.so" lib/wine/x86_64-unix/winegstreamer.so
    install_file "$rt" "$build/dlls/winemac.drv/winemac.so" lib/wine/x86_64-unix/winemac.so
    install_file "$rt" "$build/dlls/ntdll/ntdll.so" lib/wine/x86_64-unix/ntdll.so
    # GLib and GStreamer next to libgnutls (winegstreamer.so's rpath), plugins in lib/gstreamer-1.0, which Alloy
    # passes to GStreamer as its plugin path. Only real files are copied; the libraries refer to each other by name.
    mkdir -p "$rt/wine/lib/gstreamer-1.0"
    for f in "$gst"/lib/*.dylib; do [ -L "$f" ] || install_file "$rt" "$f" "lib/$(basename "$f")" >/dev/null; done
    for f in "$gst"/lib/gstreamer-1.0/*.dylib; do install_file "$rt" "$f" "lib/gstreamer-1.0/$(basename "$f")" >/dev/null; done
    echo "  GStreamer: $(ls "$rt/wine/lib/gstreamer-1.0" | grep -c '\.dylib$') plugins"
done
