<!-- Generated from Sources/AlloyCore/Guides/OpenSourceNotices.swift by `alloyctl write-docs docs`. Edit that file instead. -->

# Third-party notices

Alloy's own app uses only Apple's system frameworks. It runs the game engine as a separate program and links none of its code.

## Alloy

Free software by Flake. You can use, study, change and share it under the GPL; its source code is on GitHub.

| Component | Licence | Use |
|---|---|---|
| [Alloy](https://github.com/FlakeIdea/alloy) | GPL-3.0 | This app and its command-line tool, alloyctl. |

## The game engine

A separate download, installed from Setup. Its licences/ folder holds every licence text, and its source is published with each release.

| Component | Licence | Use |
|---|---|---|
| [Wine](https://www.winehq.org) | LGPL-2.1 or later | Runs Windows programs. Built from the open-source parts of CrossOver 26.3 that CodeWeavers publishes, with Alloy's patches. |
| [vkd3d](https://gitlab.winehq.org/wine/vkd3d) | LGPL-2.1 or later | Part of Wine: Direct3D 12 shader support. |
| [DXMT](https://github.com/3Shain/dxmt) | MIT | Turns Direct3D 10 and 11 into Metal. |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apache-2.0 | Vulkan on Metal. |
| [GStreamer](https://gstreamer.freedesktop.org) | LGPL-2.1 or later | Video playback in games. Video is decoded by macOS itself. |
| [GLib, proxy-libintl](https://gitlab.gnome.org/GNOME/glib) | LGPL-2.1 or later | Used by GStreamer. |
| [libffi](https://sourceware.org/libffi/) | MIT | Used by GLib. |
| [PCRE2](https://github.com/PCRE2Project/pcre2) | BSD-3-Clause | Used by GLib. |
| [GnuTLS](https://gnutls.org) | LGPL-2.1 or later | Secure connections for Windows programs (HTTPS, certificate checks). |
| [Nettle, GMP](https://www.lysator.liu.se/~nisse/nettle/) | LGPL-3.0 or later, or GPL-2.0 or later | Cryptography used by GnuTLS. |
| [FreeType](https://freetype.org) | FreeType Licence | Font rendering. |

## Downloaded when needed

Not part of Alloy. Downloaded from their publishers with your permission, under their own terms.

| Component | Licence | Use |
|---|---|---|
| [Wine Mono](https://gitlab.winehq.org/mono/wine-mono) | MIT, with GPL and LGPL parts | .NET support for games and launchers. From WineHQ. |
| [Microsoft Visual C++ Redistributable](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist) | Microsoft software licence | Needed by many games. From Microsoft. |
| Game store apps | Each store's own terms | Steam, Epic Games Launcher, EA app, Ubisoft Connect, GOG Galaxy, Battle.net. From their publishers. |
| [Rosetta 2](https://support.apple.com/102527) | Apple software licence | Runs the Intel-built engine on Apple silicon. Installed by macOS. |

## Never included

Alloy never ships or downloads these.

| Component | Licence | Use |
|---|---|---|
| [D3DMetal (Apple Game Porting Toolkit)](https://developer.apple.com/games/game-porting-toolkit/) | Apple licence; not redistributable | Optional, for DirectX 12. You download Apple's toolkit yourself and accept Apple's licence; Alloy only uses the copy you add. |
