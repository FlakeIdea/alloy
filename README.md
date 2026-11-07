# Alloy

A free, open-source macOS app for playing Windows games on Macs (Apple silicon, and Intel with Compatibility graphics). It is built on Wine, DXMT (DirectX 10/11 on
Apple Metal) and other open-source components, with optional support for Apple's D3DMetal for DirectX 12 games.

Alloy is not affiliated with CodeWeavers, Apple, Microsoft or Valve, and contains no CrossOver or D3DMetal code.

**Download:** [flake.co.in/alloy](https://flake.co.in/alloy/) · **Game engine releases and their source:** [FlakeIdea/alloy-engine](https://github.com/FlakeIdea/alloy-engine/releases) · **Help:** support@flake.co.in

## Using it

1. **Setup wizard**: on first launch Alloy walks through Welcome, Terms, Install and Ready. On the Install page one
   click (**Install Everything**) checks the Mac, installs Rosetta 2 if needed and downloads the game engine (about
   300 MB) and the Windows components. **Setup → Install Everything…** opens it again.
2. **Games → Add Game**: choose the game's folder or its `.exe`, or **Install from Setup File…** for a game that comes as a
   `setup.exe` or `.msi`. You can also drag any of these onto the Games page. Alloy never moves or changes game files.
3. Open the game and press **Play**. The first start shows exactly which file will run; nothing starts without that click.

Before a game's first start, Alloy looks at its files and installs what it needs into that game's own environment:
Microsoft's Visual C++ runtime (downloaded from Microsoft) and .NET support (Wine Mono, from WineHQ), each checked against
a pinned checksum. This can be turned off in Setup.

**Graphics** on each game page:

| Choice | What it does |
|---|---|
| Battery Saver | Caps the game at 60 FPS. Shown on displays faster than 60 Hz |
| Balanced (default) | As smooth as the display allows, up to its refresh rate |
| Sharp | Renders at a lower resolution and upscales with Apple's MetalFX. Smoother in heavy scenes; costs about 2 ms per frame |
| Compatibility mode | Switches to Wine's OpenGL renderer for games that will not start or draw wrongly. Slower |

**Game stores**: Setup installs Steam, the Epic Games Launcher, the EA app, Ubisoft Connect, GOG Galaxy or Battle.net, each
from its publisher. Games installed in Steam or Epic appear in your library. If a network blocks a store (common at schools
and workplaces), Alloy says so.

**Metrics**: press **⌥⌘M** while playing to show or hide FPS, frame time and memory (Apple's Metal HUD).

When a game fails, the game page names the likely cause and offers a one-click fix where there is one.

**Which should I choose?** on the game page opens the Graphics Guide: six short steps from the defaults to lower in-game
resolution with Sharp. The same text is in [docs/GRAPHICS-GUIDE.md](docs/GRAPHICS-GUIDE.md) for your website.

On first launch Alloy shows its [terms of use](docs/TERMS.md) and asks people to accept them. They are also under
**Advanced → Settings → About Alloy**.

Everything else (environments, graphics backends, launch options, logs, diagnostics, frame-time analysis, settings) is under
**Advanced**, and under **Advanced settings** on each game page.

## What runs

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for games actually tested and their results. DirectX 10/11 games use DXMT.
DirectX 12 games need D3DMetal, which you add yourself from Apple's Game Porting Toolkit (**Setup → DirectX 12 games**);
Apple does not allow it to be redistributed. Games with kernel anti-cheat generally do not run.

## Requirements

* macOS 14 or later on Apple silicon; Intel Macs run the engine natively with Compatibility (OpenGL) graphics and experimental DirectX 12 through vkd3d
* About 2 GB free for the game engine, plus your games
* Rosetta 2 (Setup installs it if needed: the engine is an x86_64 build)

## Build from source

Needs a Swift 6 toolchain: Xcode, or only the Command Line Tools (`xcode-select --install`).

```bash
scripts/build-app.sh
```

This makes `build/Alloy.app`, ad-hoc signed for this Mac. Install it with `ditto build/Alloy.app /Applications/Alloy.app`.

Tests:

```bash
scripts/test.sh
```

With only the Command Line Tools, Swift Testing is outside the default search path; the script passes the needed flags.
`ALLOY_WINE_INTEGRATION=1 scripts/test.sh --filter WineIntegrationTests` also runs tests against a real Wine.

A build from source has no game engine download address, so Setup offers **Install from Package File…** instead. To make
your own engine, see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Publishing it

`scripts/release.sh` builds `Alloy-<version>.pkg`, the installer to link from your website. It checks the Mac,
installs Alloy and Rosetta 2, and opens the app, where **Install Everything** downloads the game engine and the
Windows components. It also builds a `.dmg`. [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) covers the whole release:
packaging the engine with its licences, hosting it, signing and notarising, and what the download page must say.

## Command-line tool

`swift build -c release --product alloyctl` builds `alloyctl`, which uses the same storage as the app:

```
alloyctl runtimes
alloyctl prefixes
alloyctl prefix-create <name> <runtime-path>
alloyctl prefix-init <prefix-id>
alloyctl run <prefix-id> <exe> [--graphics dxmt|d3dMetal|dxvk|vkd3d|wined3dVulkan|wined3dOpenGL] [--timeout s] [-- args]
alloyctl install-runtime <components.json URL> [package-id]
alloyctl components <prefix-id> <exe>
alloyctl install-vcruntime <prefix-id>
alloyctl install-dotnet <prefix-id>
alloyctl install-game <prefix-id> <setup.exe|.msi> <name>
alloyctl setup [components.json URL] [--install-rosetta]
alloyctl write-docs docs
```

Run `alloyctl` without arguments for the full list. It only runs the programs you name.

## Project layout

```
Sources/AlloyCore/      UI-independent library (all logic, tested)
  Backend/                  Wine backend, environments, D3DMetal and DXMT runtimes
  Components/               Game engine download, Visual C++ / Wine Mono, Rosetta
  Diagnostics/              Log analysis, graphics verification, redaction, reports
  Graphics/                 Graphics settings, play modes, per-game defaults
  Guides/                   Terms of use and the graphics guide (app and docs/)
  Launch/                   Process launcher with log capture
  Library/                  Library storage, exe scanner, game installer
  Performance/              Frame-time statistics
Sources/AlloyApp/       SwiftUI app
Sources/AlloyCLI/       alloyctl
Tests/AlloyCoreTests/   Swift Testing suites
patches/wine/               Alloy's changes to Wine (LGPL)
scripts/                    build, test, engine patching and packaging, release
docs/                       Compatibility, troubleshooting, licences, distribution
```

Data lives in `~/Library/Application Support/Alloy/` (library, settings, environments, game engines, logs).

## Documentation

* [docs/GRAPHICS-GUIDE.md](docs/GRAPHICS-GUIDE.md): getting the best performance
* [docs/TERMS.md](docs/TERMS.md): terms of use
* [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md): graphics paths and the game test log
* [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
* [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md): publishing a release
* [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md): components and licences
* [docs/FEATURES.md](docs/FEATURES.md): implemented and planned

## Licence

Alloy is free software by Flake, released under the [GNU General Public License, version 3](LICENSE) (GPL-3.0). You can use,
study, change and share it; if you share a changed version, it must stay under the GPL with its source available.

The game engine Alloy downloads is a separate program with its own licences (Wine and most of its parts are LGPL-2.1 or
later; DXMT is MIT; MoltenVK is Apache-2.0). Each engine release on
[FlakeIdea/alloy-engine](https://github.com/FlakeIdea/alloy-engine/releases) includes its licence texts and complete
source. See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md). Apple's D3DMetal is never included.

"Alloy" and "Flake" are names of Flake's project; the GPL covers the code, not the right to present a modified version as
the official Alloy.
