#!/bin/sh
# Runs the test suite. With only the Command Line Tools installed (no Xcode), Swift Testing lives
# outside the default search path and its Foundation cross-import overlay is incomplete, so point
# the compiler at it explicitly. With full Xcode installed, plain `swift test` works.
set -e
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if xcode-select -p | grep -q CommandLineTools; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
else
  exec swift test "$@"
fi
