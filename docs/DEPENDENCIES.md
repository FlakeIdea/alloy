# Dependencies and licences

Alloy's source uses only Apple system frameworks (Foundation, SwiftUI, AppKit, Swift Testing).
The app links no third-party code and bundles no compatibility components. The game engine is a separate download
(see "The game engine package" below); everything else is **found on your system**, **supplied by you**, or
**downloaded on request** from its publisher, and runs as a separate process or DLL.

| Component | How Alloy uses it | Licence | Bundled? |
|---|---|---|---|
| Wine (e.g. Gcenx macOS builds) | Executes `wine`, `wineserver` as separate processes | LGPL-2.1+ | No |
| wine-mono, wine-gecko | Shipped inside Gcenx builds | GPL/LGPL/MPL mix | No |
| MoltenVK | Detected inside the Wine runtime | Apache-2.0 | No |
| DXVK-macOS | DLLs you download, copied into a prefix on request (reversible) | zlib | No |
| D3DMetal / Game Porting Toolkit | Detected in a Wine folder you add yourself | Proprietary Apple licence (evaluation terms; redistribution unclear) | **Never** |
| CrossOver | Bottles listed read-only; its Wine is never used | Proprietary (CodeWeavers) | No |
| Microsoft Visual C++ 2015–2022 Redistributable | Downloaded from Microsoft when a game needs it (or on request), checked against Microsoft's checksum, then run in that environment | Proprietary (Microsoft; free to redistribute with programs) | **Never**: downloaded on request |
| Wine Mono | Downloaded from WineHQ when a .NET game needs it, checked against the checksum the runtime's `appwiz.cpl` pins, installed with Wine's `msiexec` | GPL/LGPL/MIT mix | **Never**: downloaded on request |
| Rosetta 2 | Installed with Apple's `softwareupdate` after you agree to Apple's licence in Setup | Proprietary (Apple) | **Never** |

Because Alloy only starts Wine as a separate program and never links to it, Alloy's own
licence can be chosen freely. **Choose one before publishing** (MIT, Apache-2.0 or GPL-3.0 are
common). No `LICENSE` file has been added yet, because that is your decision.

Whisky (GPL-3.0, archived) was studied only as a reference for which environment variables
exist. No Whisky code was copied.

## The game engine package

A public release offers one downloadable game engine (`scripts/package-runtime.sh`): an Alloy runtime built from
CrossOver's source release as described below, with DXMT 0.80 (MIT, from its GitHub release). Publishing it means
distributing LGPL software, so the package carries a `licenses/` folder with the texts of every component, and the
matching source must be offered. [DISTRIBUTION.md](DISTRIBUTION.md) lists the steps. D3DMetal is never part of it.

| Component in the package | Licence |
|---|---|
| Wine 11.0 (CrossOver tree) with `patches/wine`, including its bundled vkd3d | LGPL-2.1+ |
| DXMT 0.80 (d3d10core, d3d11, dxgi, winemetal, nvapi64, nvngx) | MIT |
| GStreamer 1.24, GLib 2.78, proxy-libintl | LGPL-2.1+ |
| libffi | MIT |
| pcre2 (inside GLib) | BSD-3-Clause |
| GnuTLS 3.8.3, with nettle 3.10 and GMP linked in | LGPL-2.1+; nettle and GMP LGPL-3+ or GPL-2+ |
| FreeType | FreeType licence (BSD-style) |
| MoltenVK | Apache-2.0 |

## Runtimes built from CrossOver's source release

CodeWeavers publishes the open-source parts of CrossOver (`crossover-sources-26.3.0.tar.gz`). The
Alloy runtimes are built locally from it. Nothing from CrossOver.app itself is copied.

| Component | Use | Licence |
|---|---|---|
| Wine 11.0 (CrossOver tree) | The runtime itself | LGPL-2.1+ |
| `patches/wine/*.patch` | Alloy's changes to Wine: Steam web helper switches, keeping ProMotion at 120 Hz in exclusive fullscreen, Game Mode bundles, per-stream sample waits in the media source, H.264 decoding to system memory when the Direct3D device has no NV12 textures | LGPL-2.1+, like Wine |
| GStreamer 1.24, GLib 2.78 (from the same source release) | `lib/` and `lib/gstreamer-1.0` in each runtime, for winegstreamer (video in Media Foundation and DirectShow). H.264/AAC decoding uses Apple's VideoToolbox/AudioToolbox; no patent-encumbered software decoder is built | LGPL-2.1+ |
| GnuTLS 3.8.3, with its built-in libtasn1 and libunistring | `lib/libgnutls.30.dylib` in each runtime, for bcrypt and schannel | LGPL-2.1+ |
| nettle 3.10, GMP | Linked statically into that library | LGPL-3+ or GPL-2+ (dual) |

`scripts/patch-wine-runtime.sh <source tarball> <runtime folder>...` rebuilds only what changed
(kernelbase, bcrypt, secur32, winegstreamer, winemac, ntdll, GnuTLS and GStreamer, about 10 minutes the first time). It installs into
Alloy-managed runtimes built from the same Wine version, and keeps each original under
`<runtime>/alloy-backup`. It downloads one file, the nettle 3.10 release from ftp.gnu.org
(SHA-256 `b4c518ad…e47c`). Its sources match CrossOver's copy file for file; the tarball only adds
the generated `configure`. Rebuilding needs mingw-w64 and bison from Homebrew.
