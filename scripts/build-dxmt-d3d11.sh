#!/bin/zsh
# Builds DXMT's d3d11.dll (64- and 32-bit) with Alloy's patches (patches/dxmt). See patches/dxmt/README.md.
#
#   scripts/build-dxmt-d3d11.sh <dxmt-v0.80-checkout> <wine-build-dir> <official-v0.80-d3d11.dll> <out-dir>
#
# Needs mingw-w64 (x86_64 and i686), meson >= 1.3 and ninja on PATH. The checkout needs its submodules
# (git submodule update --init --recursive). The patches are applied to it if they aren't already.
# Without Xcode's Metal toolchain, dxmt_command.metallib is taken from the official d3d11.dll instead of compiled.
# Writes <out-dir>/x86_64-windows/d3d11.dll and <out-dir>/i386-windows/d3d11.dll, stripped and marked as Wine builtins.
set -eu
[ $# -eq 4 ] || { sed -n 2,9p "$0"; exit 2; }
src=${1:A} wine=${2:A} official=${3:A} out=$4
here=${0:A:h}
[ -f "$src/meson.build" ] || { echo "No DXMT checkout in $src" >&2; exit 2; }
[ -x "$wine/tools/winebuild/winebuild" ] || { echo "No tools/winebuild/winebuild in $wine" >&2; exit 2; }
[ -f "$official" ] || { echo "No such file: $official" >&2; exit 2; }
for p in "$here/../patches/dxmt/"*.patch; do
  if git -C "$src" apply --check "$p" 2>/dev/null; then git -C "$src" apply "$p"; echo "Applied ${p:t}"
  elif git -C "$src" apply --check --reverse "$p" 2>/dev/null; then echo "Already applied: ${p:t}"
  else echo "${p:t} does not apply to $src" >&2; exit 1; fi
done
mkdir -p "$out"; out=${out:A}
work=$(mktemp -d "${TMPDIR:-/tmp}/dxmt-build.XXXXXX")
trap 'rm -rf "$work"' EXIT

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  # A metallib starts with "MTLB" and holds its own size at offset 16.
  python3 -I - "$official" "$work/dxmt_command.metallib" <<'PY'
import struct, sys
data = open(sys.argv[1], 'rb').read()
i = data.find(b'MTLB\x01\x80')
if i < 0: sys.exit("No Metal library in " + sys.argv[1])
size = struct.unpack_from('<Q', data, i + 16)[0]
if not 0 < size <= len(data) - i: sys.exit("Unexpected Metal library size")
open(sys.argv[2], 'wb').write(data[i:i + size])
print("Using the official dxmt_command.metallib (%d bytes)" % size)
PY
  mkdir -p "$work/bin"
  cat > "$work/bin/xcrun" <<EOF
#!/bin/sh
# Build-only stand-in for "xcrun metal" and "xcrun metallib": the library comes from the official v0.80 d3d11.dll.
out=""; mode=""; prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  case "\$a" in metallib) mode=lib;; metal) [ -z "\$mode" ] && mode=ir;; esac
  prev="\$a"
done
[ -n "\$out" ] || exec /usr/bin/xcrun "\$@"
if [ "\$mode" = lib ]; then cp "$work/dxmt_command.metallib" "\$out"; else : > "\$out"; fi
EOF
  chmod +x "$work/bin/xcrun"
  export PATH="$work/bin:$PATH"
fi

# Only the Windows side is built, so LLVM (for the Mac side's shader converter) is never used; meson wants the folder.
mkdir -p "$work/nollvm/include" "$work/nollvm/lib"
for bits arch strip in 64 x86_64 x86_64-w64-mingw32-strip 32 i386 i686-w64-mingw32-strip; do
  meson setup --cross-file "$src/build-win$bits.txt" -Dwine_build_path="$wine" -Dnative_llvm_path="$work/nollvm" \
    "$work/build$bits" "$src" --buildtype release >/dev/null
  ninja -C "$work/build$bits" src/d3d11/d3d11.dll >/dev/null
  mkdir -p "$out/$arch-windows"
  cp "$work/build$bits/src/d3d11/d3d11.dll" "$out/$arch-windows/d3d11.dll"
  $strip "$out/$arch-windows/d3d11.dll"
  "$wine/tools/winebuild/winebuild" --builtin "$out/$arch-windows/d3d11.dll"
  echo "Built $out/$arch-windows/d3d11.dll"
done
