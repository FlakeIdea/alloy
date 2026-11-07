#!/bin/zsh
# Builds the x86_64 GLib + GStreamer that Wine's winegstreamer needs to play videos (Media Foundation, DirectShow),
# from the GStreamer 1.24 and GLib 2.78 sources in CrossOver's source release. Only the plugins CrossOver ships are
# built; H.264/HEVC and AAC decoding use Apple's VideoToolbox and AudioToolbox (the applemedia plugin), so no
# patent-encumbered software decoder is included.
#
#   scripts/build-gstreamer.sh <extracted-sources-dir> <work-dir>
#
# <extracted-sources-dir> holds sources/gstreamer and sources/glib. The result is <work-dir>/install, with every
# library referring to the others through @rpath. Needs python3 and Rosetta. Downloads, once: meson, ninja and
# setuptools from PyPI, and the small sources meson pins for GLib (pcre2, libffi, proxy-libintl, gvdb).
set -euo pipefail

[ $# -eq 2 ] || { sed -n '7,7p' "$0"; exit 2; }
src="$1" work="$2"
[ -d "$src/gstreamer" ] && [ -d "$src/glib" ] || { echo "No gstreamer and glib folders in $src" >&2; exit 1; }
mkdir -p "$work"
venv="$work/meson-venv" tree="$work/gst-src" build="$work/gst-build" install="$work/install"

if [ ! -x "$venv/bin/meson" ]; then
    echo "Setting up meson and ninja (from PyPI)"
    python3 -m venv "$venv"
    # setuptools provides distutils, which GLib 2.78's gdbus-codegen still imports on Python 3.12 and later.
    "$venv/bin/python3" -I -m pip install -q meson==1.12.1 ninja==1.13.2 setuptools
fi
export PATH="$venv/bin:/usr/bin:/bin:/usr/sbin:/sbin" MACOSX_DEPLOYMENT_TARGET=11.0
# Python.org builds do not use the macOS keychain; meson's downloads still verify certificates, against this bundle.
[ -f /etc/ssl/cert.pem ] && export SSL_CERT_FILE=/etc/ssl/cert.pem

rm -rf "$tree" "$build" "$install"
cp -R "$src/gstreamer" "$tree"
rm -rf "$tree/subprojects/glib"; cp -R "$src/glib" "$tree/subprojects/glib"
# Use the release's GLib as it is (the monorepo's wrap would download 2.78.3), and GLib's proxy-libintl wrap: the
# monorepo's copy lacks the [provide] line GLib's fallback looks for.
cat > "$tree/subprojects/glib.wrap" <<'EOF'
[wrap-file]
directory = glib

[provide]
dependency_names = gthread-2.0, gobject-2.0, gmodule-no-export-2.0, gmodule-export-2.0, gmodule-2.0, glib-2.0, gio-2.0, gio-unix-2.0
program_names = glib-genmarshal, glib-mkenums, glib-compile-schemas, glib-compile-resources, gio-querymodules, gdbus-codegen
EOF
cp "$src/glib/subprojects/proxy-libintl.wrap" "$tree/subprojects/proxy-libintl.wrap"
# The release has gvdb as an empty submodule folder; without it meson fetches the pinned revision.
rmdir "$tree/subprojects/glib/subprojects/gvdb" 2>/dev/null || true

echo "Configuring GStreamer (log: $work/setup.log)"
cd "$tree"
arch -x86_64 meson setup "$build" --prefix="$install" --libdir=lib --buildtype=release \
  -Ddefault_library=shared -Dauto_features=disabled \
  "-Dc_link_args=['-Wl,-rpath,@loader_path','-Wl,-rpath,@loader_path/..']" \
  "-Dobjc_link_args=['-Wl,-rpath,@loader_path','-Wl,-rpath,@loader_path/..']" \
  -Dbase=enabled -Dgood=enabled -Dbad=enabled -Dugly=disabled -Dlibav=disabled -Ddevtools=disabled -Dges=disabled \
  -Drtsp_server=disabled -Drs=disabled -Dgst-examples=disabled -Dpython=disabled -Dtls=disabled -Dlibnice=disabled \
  -Dgpl=disabled -Dtests=disabled -Dtools=disabled -Dexamples=disabled -Dintrospection=disabled -Dnls=disabled \
  -Dorc=disabled -Ddoc=disabled -Dgtk_doc=disabled -Dqt5=disabled -Dqt6=disabled -Dwebrtc=disabled \
  -Dglib:tests=false -Dglib:installed_tests=false -Dglib:xattr=false -Dglib:dtrace=false -Dglib:systemtap=false \
  -Dglib:man=false -Dglib:libelf=disabled -Dglib:sysprof=disabled -Dglib:selinux=disabled -Dglib:libmount=disabled \
  -Dgstreamer:ptp-helper=disabled -Dgstreamer:check=disabled -Dgstreamer:libunwind=disabled -Dgstreamer:libdw=disabled \
  -Dgstreamer:bash-completion=disabled -Dgstreamer:coretracers=disabled -Dgstreamer:registry=true \
  -Dgst-plugins-base:app=enabled -Dgst-plugins-base:audioconvert=enabled -Dgst-plugins-base:audioresample=enabled \
  -Dgst-plugins-base:playback=enabled -Dgst-plugins-base:typefind=enabled -Dgst-plugins-base:videoconvertscale=enabled \
  -Dgst-plugins-base:pbtypes=enabled -Dgst-plugins-base:volume=enabled \
  -Dgst-plugins-base:gl=enabled "-Dgst-plugins-base:gl_api=['opengl']" "-Dgst-plugins-base:gl_platform=['cgl']" \
  "-Dgst-plugins-base:gl_winsys=['cocoa']" \
  -Dgst-plugins-good:isomp4=enabled -Dgst-plugins-good:audioparsers=enabled -Dgst-plugins-good:wavparse=enabled \
  -Dgst-plugins-good:id3demux=enabled -Dgst-plugins-good:avi=enabled -Dgst-plugins-good:deinterlace=enabled \
  -Dgst-plugins-good:videofilter=enabled \
  -Dgst-plugins-bad:applemedia=enabled -Dgst-plugins-bad:gl=enabled -Dgst-plugins-bad:videoparsers=enabled \
  > "$work/setup.log" 2>&1 || { tail -30 "$work/setup.log"; exit 1; }

echo "Building GStreamer (log: $work/build.log)"
arch -x86_64 ninja -C "$build" > "$work/build.log" 2>&1 || { grep -m10 -E 'error:|FAILED|Undefined' "$work/build.log"; exit 1; }
arch -x86_64 ninja -C "$build" install > "$work/install.log" 2>&1 || { tail -20 "$work/install.log"; exit 1; }

# meson records absolute install names; make every library find the others next to it (or one folder up, for plugins).
for f in "$install"/lib/*.dylib(.N) "$install"/lib/gstreamer-1.0/*.dylib(.N); do
    args=(-id "@rpath/${f:t}")
    for dep in ${(f)"$(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep "^$install/lib/" || true)"}; do
        [ -n "$dep" ] && args+=(-change "$dep" "@rpath/${dep:t}")
    done
    install_name_tool "${args[@]}" "$f" 2>/dev/null
    codesign -f -s - "$f" 2>/dev/null
done
if otool -L "$install"/lib/*.dylib(.N) "$install"/lib/gstreamer-1.0/*.dylib(.N) | grep -v ':$' | grep -q "$install"; then
    echo "Some libraries still refer to $install" >&2; exit 1
fi
echo "GStreamer: $(ls "$install/lib/gstreamer-1.0" | grep -c '\.dylib$') plugins in $install"
