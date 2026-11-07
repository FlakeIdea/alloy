# Implemented vs planned

"Implemented" means the code exists and is covered by automated tests or was checked in the running app.
Anything that needs a real Wine runtime is marked **unverified** until it has been run against one.

## Implemented

### Simple mode and setup
- Three places: **Games**, **Setup**, **Advanced** (environments, diagnostics, performance and settings behind one tab)
- One-click game engine install from a `components.json` the release points to: download with progress, SHA-256 check,
  unpack only a package with one runtime folder and no links leaving it, record the installed package, offer updates
  (tested end to end from a local server; `scripts/package-runtime.sh` builds packages with their licence texts)
- Rosetta 2 card in Setup when it is missing; installs with Apple's `softwareupdate` after the person agrees to Apple's
  licence (**unverified**: this Mac already has Rosetta)
- Windows components found from each game's files and installed into its environment before the first start: Visual C++
  (Microsoft, checksum-pinned) and Wine Mono for .NET programs (WineHQ, checked against the checksum the runtime's
  `appwiz.cpl` pins). Detection tested on real games; Wine Mono download, install and a .NET test program verified
- Install a game from its `setup.exe` or `.msi` into its own environment; the game is found among the new programs
  (logic tested; **unverified** with a real installer)
- Drag a folder, `.exe` or setup file onto the Games page
- Terms of use on first launch (accept or quit; asked again when `Terms.version` rises) and a six-step Graphics Guide,
  opened from the game page, Setup and Settings; `alloyctl write-docs` writes both as Markdown for the website, and a
  test keeps `docs/` in step with the app
- Download retries on dropped connections and TLS errors; plain error messages in the app and `alloyctl`
- Game page: Play, Battery Saver (displays above 60 Hz) / Balanced / Sharp, Compatibility mode, problems with one-click fixes; the full editor,
  components and log under **Advanced settings**
- `scripts/release.sh`: `.pkg` installer and `.dmg`, Developer ID signing and notarisation when credentials are given
  (**unverified** without a Developer ID). The `.pkg` refuses Intel Macs and macOS before 14, shows the terms, installs the
  app, Rosetta 2 and the terms record, then opens Alloy (built and inspected; its postinstall dry-run tested; a real
  install is **unverified**: it needs an administrator password)
- Setup wizard (Welcome, Terms, Install, Ready). **Install Everything** checks the Mac and free space, installs
  Rosetta 2 and the game engine, and downloads the Visual C++ and Wine Mono installers ahead. It opens on first launch,
  at Install when something is missing (or after the `.pkg`, which showed the terms), and from Setup. Its `SetupRunner` was tested
  end to end with `alloyctl setup` in an empty home folder (engine from a local server)

- Game stores in Setup: Steam, Epic Games Launcher, EA app, Ubisoft Connect, GOG Galaxy, Battle.net, each installed from
  its publisher's own hosts into its own environment (Steam verified to its sign-in window; the others **unverified**).
  A network check names a network that blocks a store (verified against a FortiGuard filter)
- ⌥⌘M shows or hides a running game's metrics (Metal HUD), hidden at start (verified with a Metal test app)

### Library
- Add a game from a folder; ranked `.exe` detection (PE header, architecture, Unreal Engine layout, redistributables ignored)
- Edit name, executable, environment, runtime, arguments (quoted parsing, never passed to a shell), environment variables, artwork
- Remove entry only (game files never touched); persistence with corrupt-file backup
- Local artwork detection (cover/header/icon images in the game folder) or a user-chosen image
- Games installed in Steam or the Epic Games Launcher join the library and start through the store (manifest parsing tested;
  **unverified** with a signed-in store)

### Environments
- Wine runtime discovery: Gcenx `Wine *.app` bundles in /Applications and ~/Applications, Homebrew, GPTK, custom folders
- Detection of runtime architecture (Mach-O), Rosetta requirement, MoltenVK and D3DMetal presence
- Create, initialise (`wineboot --init`, verified with Wine 11.20: 22 s), and Trash (recoverable) Alloy prefixes
- CrossOver bottles listed **read-only**; every write path refuses them
- DXVK-macOS DLL install into a prefix, with backup and restore (file logic tested; rendering **unverified**)
- "Stop all programs" via `wineserver -k` (verified in the integration test)

### Launcher
- `Process`-based launch with argument vector, working directory set to the exe folder, merged environment, `DYLD_*` stripped
- Live stdout/stderr capture, per-run log file, exit codes, stop (SIGTERM → SIGKILL), restart
- Confirmation before first run and after the file changes; never runs with administrator privileges

### Graphics
- Capability matrix per runtime; the UI only offers usable backends
- Applies only options the runtime supports: `WINE_D3D_CONFIG` renderer, DXVK overrides, frame limit and state cache, Metal HUD, `ROSETTA_ADVERTISE_AVX`, esync/msync, `-dx11`
- Graphics backend reported as **requested** until log evidence confirms it

### Diagnostics
- Signatures: missing DLL (with VC++/DirectX/.NET advice), Rosetta missing, broken runtime, bad path, Vulkan unavailable, DX12/feature-level failure, crash, anti-cheat, wineserver mismatch, prefix ownership, non-zero exit
- Pre-flight checks (runtime, executable, prefix)
- Redacted Markdown report export (home path, password/token-style values); nothing is uploaded

### Performance
- Frame-time statistics: average FPS, 1% lows, p99, median, standard deviation, over-budget ratio, hitch count
- CSV import (PresentMon `MsBetweenPresents`, MangoHud `frametime`, single column)
- Benchmark history per game, with quality score, in-game settings, crashes and visual artefacts
- Preset-aware recommendation (High Quality / Quality + Performance / High FPS) that never picks crashed or broken runs and keeps higher quality when the gain is under 5%
- Quality-first tuning order (compatibility → shader stutter → effects → shadows → … → render scale → textures)

## Planned

1. Automatic frame-time capture (Metal HUD log parsing) instead of CSV import
2. Unreal Engine `GameUserSettings.ini` editor that applies presets, with backup and restore
3. Extracting icons from `.exe` resources for artwork
4. DirectX 9 redistributable (d3dx9) installer for older games, from Microsoft's package
5. Evaluate KosmicKrisp (Mesa Vulkan-on-Metal) as a path to upstream DXVK
6. Automatic update check for the app itself
