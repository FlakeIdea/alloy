# Compatibility matrix

## Graphics paths

| Backend | DirectX | Needs | Licence | Status in Alloy |
|---|---|---|---|---|
| WineD3D (OpenGL) | 1–11 | Any Wine | LGPL | Offered always. Slowest; OpenGL is deprecated on macOS |
| WineD3D (Vulkan) | 1–11 | Wine + MoltenVK | LGPL / Apache-2.0 | Experimental |
| Wine vkd3d | 12 | Wine + MoltenVK | LGPL | Experimental, low compatibility |
| DXVK-macOS 1.10.x | 10–11 | Wine + MoltenVK + DLLs installed in the prefix | zlib | Experimental. Upstream DXVK 2.x/3.x does not run on MoltenVK |
| vkd3d-proton | 12 | Vulkan features MoltenVK lacks | LGPL | **Not offered**: not viable on macOS |
| D3DMetal | 11–12 | GPTK-based Wine + D3DMetal.framework, supplied by you | Proprietary (Apple) | Offered when detected; never bundled |

## Game test log

A game is listed as working only after an actual test. Every entry records the game version,
runtime, graphics path, preset, resolution, measured FPS (average / 1% low), artefacts and stability.

| Game | Version | Runtime | Graphics | Preset / resolution | Avg / 1% low | Result | Date |
|---|---|---|---|---|---|---|---|
| Wine built-in `cmd.exe` (x64 console) | Wine 11.20 | Wine Devel 11.20 (Gcenx, x86_64 via Rosetta 2) | WineD3D (OpenGL), not exercised (console program) | — | — | **Works**: launched through Alloy, output captured, exit codes 0 and 7 reported correctly | 2026-10-29 |
| Unigine Heaven 4.0 (32-bit, DX11) | Wine 11.20 | Wine Devel 11.20 (Gcenx) | WineD3D (OpenGL), confirmed by Wine log | — | — | **Fails to render DX11**: Heaven reports “feature level 10.0 is not supported”; benchmark never completed (stopped at 420 s). Installer needed innoextract (Inno Setup crashes under WoW64). 32-bit, so cannot use D3DMetal | 2026-10-30 |
| Unigine Superposition 1.1 (64-bit, DX11), fullscreen requested 1080p, actual 1920×1200, High (shaders/textures High, DoF + motion blur on) | Wine 7.7 | Game Porting Toolkit 3.0-3 (Gcenx), bundled D3DMetal 3.0 | D3DMetal, confirmed by log | — | — | **Works**: avg 32.9 FPS (min 28.2, max 40.2); with ROSETTA_ADVERTISE_AVX avg 32.6 (no gain). Superposition reports only min/avg/max, no 1% lows. Base M4, 10-core GPU | 2026-10-31 |
| Unigine Superposition 1.1, 1080p fullscreen, shaders/textures Medium, DoF/motion blur off | Wine 7.7 | GPTK 3.0-3, D3DMetal 3.0 | D3DMetal, confirmed | — | — | **Works**: avg 55.1 FPS (min 44.9, max 70.7) | 2026-10-31 |
| Unigine Superposition 1.1, 1080p | Wine 7.7 | GPTK 3.0-3 base + Apple D3DMetal 4.0 beta 3 redist | D3DMetal requested | — | — | **Fails**: dxgi.dll does not load, game falls back to OpenGL. Alloy now refuses to build this combination | 2026-10-31 |
| Unigine Superposition 1.1, 1080p | Wine 11.20 | Wine Devel (Gcenx) | WineD3D OpenGL, confirmed | — | — | **Fails**: “feature level 11.0 is not supported” | 2026-10-31 |
| Unigine Superposition 1.1, 1080p | Wine 11.20 | Wine Devel (Gcenx) + MoltenVK | WineD3D Vulkan, confirmed | — | — | **Fails**: hangs at startup (MoltenVK: no buffer robustness) | 2026-10-31 |
| Unigine Superposition 1.1, fullscreen, High | Wine 11.0 (CrossOver 26.3 sources, built locally) | Alloy · DXMT 0.80 | DXMT requested; not confirmed by log (DXMT printed no info lines in fullscreen runs) | — | — | **Works**: at 1920×1200 (fullscreen picked the display's 16:10 mode) avg 35.7 FPS (min 9.8, max 43.3) and, warm shader cache, static wallpaper, on battery, avg 34.7 (min 28.7, max 42.1). An earlier 38.3 FPS run is excluded: it ran at 1800×1169. Same resolution as the D3DMetal 3.0 rows, so DXMT is ~7% faster on average here | 2026-10-31 |
| Unigine Superposition 1.1, 1080p | Wine 11.20 (upstream, Gcenx) | DXMT 0.80 | DXMT | — | — | **Fails**: “Failed to create metal view”: upstream winemac.drv does not export macdrv_functions | 2026-10-31 |
| Unigine Superposition 1.1, 1080p | Wine 11.20 (upstream, Gcenx) | D3DMetal 4.0 beta 3 | D3DMetal | — | — | **Fails**: page fault on start-up (needs CrossOver's winemac D3DMetal hooks) | 2026-10-31 |
| Unigine Superposition 1.1, fullscreen 1920×1200, High | Wine 11.0 (CrossOver 26.3 sources, built locally) | Alloy · D3DMetal 4.0 beta 3 | D3DMetal, confirmed by log | — | — | **Works**: avg 32.7 FPS (min 27.6, max 40.3), on battery. Same as D3DMetal 3.0 within noise; DXMT ~7% faster on this DX11 test. A first run at 1800×1169 (avg 35.2) is excluded as not comparable | 2026-10-31 |

### Alloy vs CrossOver 26.3, same benchmark (2026-10-31)

Unigine Superposition 1.1, DX11, fullscreen 1800×1169 (the Mac's desktop size; every layer lists it), High preset
(shaders/textures High, DoF + motion blur on), vsync off. Base M4 MacBook Pro, 10-core GPU, on the charger. Both apps
use Wine built from CrossOver 26.3 sources. CrossOver ran in a separate bottle created for the test. Runs were interleaved
between the apps. The active layer was confirmed by the libraries loaded in the Wine process (`winemetal.so` for DXMT,
`D3DMetal.framework` for D3DMetal). Superposition reports min/avg/max only, no 1% lows.

| App and path | Runs (avg FPS) | Mean avg | Min | Max |
|---|---|---|---|---|
| Alloy, DXMT main 3b25259 (dev build), MSync + AVX | 38.5, 38.1 | **38.3** | 32.7 | 46.3 |
| Alloy, DXMT 0.80, MSync + AVX | 38.0, 38.5 | **38.3** | 32.7 | 47.6 |
| CrossOver 26.3, DXMT (its July 2026 build), MSync | 37.7, 37.4 | 37.6 | 31.7 | 45.1 |
| Alloy, D3DMetal 4.0 beta 3, MSync + AVX | 35.9, 35.4 | 35.7 | 30.4 | 43.8 |
| CrossOver 26.3, D3DMetal 3.0, MSync | 35.9, 35.3 | 35.6 | 29.8 | 44.3 |
| CrossOver 26.3, Auto (its default) | no complete run at 1800×1169 | — | — | — |

- Alloy's DXMT paths beat CrossOver's best path (DXMT) in all four pairings, by about 2% on average.
- CrossOver's Auto mode stopped early in every attempt at 1800×1169. Its one complete run (1920×1200) scored 33.0, the
  same as D3DMetal 3.0 at that resolution (32.9), so Auto most likely uses D3DMetal 3.0 for this benchmark. That is about
  7% below Alloy's DXMT path at equal resolution.
- Many runs in both apps ended with Superposition's own "Benchmark stopped" (it stops on input or focus change); only
  complete runs are listed.

### Expectations, not results

* Both games are Unreal Engine titles that default to DX12, with a `-dx11` fallback.
* With free components only (WineD3D or DXVK-macOS), expect poor performance or rendering problems.
  A D3DMetal-capable runtime is the realistic path to good quality at 60 FPS on an M4.
* 16 GB of unified memory is shared between CPU and GPU. Measure memory pressure before raising
  texture settings to their maximum.

## DLSS → MetalFX (added 2026-10-31)

Games that support NVIDIA DLSS can use Apple MetalFX instead, as CrossOver's game bottles do
(`D3DM_ENABLE_METALFX=1` / `DXMT_ENABLE_NVEXT=1` plus the NGXCore registry path):

| Layer | DLSS upscaling | DLSS Frame Generation |
|---|---|---|
| DXMT (DX10/11) | MetalFX temporal scaler via DXMT's `nvngx.dll` | Not available |
| D3DMetal 4 (DX11/12) | MetalFX via `nvngx-on-metalfx` | MetalFX frame interpolation (in D3DMetal 4's code; not documented by Apple) |

* Verified: the shims are installed, the registry entry is written and read back by Wine's
  `reg.exe`, and the switch variables are set. **Not yet measured in a game.**
* Alloy turns it on automatically for games that ship `nvngx_dlss.dll`. DLSS still has to be
  enabled in the game's own graphics settings.

### Frame generation (added 2026-11-04)

Frame generation is offered only where the game supplies its own depth and motion vectors. Without them,
made-up frames smear moving edges and the HUD and add input delay, so Alloy doesn't generate frames for other games.

* **DLSS Frame Generation** (`nvngx_dlssg.dll`, DirectX 12, 64-bit): new games go to D3DMetal 4 with DLSS on and
  without `-dx11`; existing games get a "Frame generation available" offer with Not now. D3DMetal 4 runs it as MetalFX
  frame interpolation from the game's data. Needs a D3DMetal build with `MTLFXFrameInterpolator` (Alloy checks).
* **AMD FidelityFX** (`amd_fidelityfx_*.dll`, `ffx_fsr3*`, `ffx_frameinterpolation*`): FSR Frame Generation runs in
  the game's own shaders, so the game page points to the game's setting.
* Every game page has a Frame generation line saying which case applies.
* **Not yet tested in a game**: no game with DLSS Frame Generation was available on the test Mac.

## MetalFX upscaling for games without DLSS (added 2026-11-01)

On DXMT, the game page's **MetalFX upscaling** picker (Off, 1.5×, 2×, 3×; CLI `--metalfx <factor>`)
turns on DXMT's MetalFX swapchain (`DXMT_METALFX_SPATIAL_SWAPCHAIN=1`,
`d3d11.metalSpatialUpscaleFactor` in `DXMT_CONFIG`). Every finished frame passes through Apple's
MetalFX spatial scaler and reaches the display at factor × the game's resolution. The game itself
still renders at its own resolution. Off by default.

Measured on this M4 (DXMT 0.80, battery power, a D3D11 test with a GPU-bound pixel shader, a
borderless 1800×1169 window, no frame cap; two interleaved rounds that matched to within 1 FPS):

| Game resolution | MetalFX | Output | FPS |
|---|---|---|---|
| 1800×1169 | Off | 1800×1169 | 91.3 |
| 1800×1169 | 2× | 3600×2338 | 77.7 |
| 1200×778 | 3× | 3600×2334 | 137.1 |
| 1200×778 | 1.5× | 1800×1167 | 172.5 |
| 1200×778 | Off | 1200×778 | 197.9 |

* Evidence that it is in use: Apple's Metal HUD shows a MetalFX section ("Scaling Spatial",
  input 1800×1169, target 3600×2338) and a 3600×2338 drawable.
* It costs about 2 ms of GPU time per frame at full Retina size. FPS rises only when the
  in-game resolution is lowered.
* On the test's hard-edged checkerboard, MetalFX's sharpening leaves light halos at the corners.
  **Not yet compared in a game.**
* Don't combine it with a game's DLSS → MetalFX. That would upscale twice.
* If DXMT reports "MetalFX spatial scaler is not supported on this device", Alloy shows a
  warning finding.

## Environment setup fixes (2026-10-31)

* The self-built runtimes have no Wine Mono or Gecko. `wineboot --init` used to stop at the
  Mono download prompt. Wine sets up 32-bit support after that step, so environments created
  before this fix have an empty `syswow64` and cannot run 32-bit programs (installers, launchers).
  Recreate them, or use **Switch to DXMT** on the game page, which makes a new one.
* Steam installs into its own environment from the Library ("Install Steam"). It needs a network
  that does not block Steam or intercept HTTPS.

## Steam client (fixed 2026-11-01)

Two runtime gaps stopped Steam, both fixed by `scripts/patch-wine-runtime.sh` (see DEPENDENCIES.md):

| Symptom | Cause | Fix |
|---|---|---|
| Sign-in window black (white with GPU on) | Chromium's GPU process draws into the browser's window from another process; the macOS driver cannot show that | kernelbase starts `steamwebhelper.exe` with `--no-sandbox --in-process-gpu --disable-gpu`, as Proton does and as CrossOver's Steam bottle shows in its logs |
| "Crypto API failed certificate check, error flags 0x00000008", QR code greyed out, `LogonFailure No Connection` | Runtimes were built `--without-gnutls`, so bcrypt cannot verify signatures and schannel has no TLS | GnuTLS 3.8.3 (with gmp and nettle) built from the same source release; bcrypt and secur32 rebuilt against it |

* Verified on DXMT 0.80 (Steam client 1792618285): the sign-in window draws, the client connects
  to a Steam server over WebSocket and shows a live sign-in QR code. **Signing in and running a game
  from Steam are not yet tested.**
* All four Alloy runtimes are patched. `alloyctl runtimes` shows "GnuTLS" and "Steam web helper
  fix" for each. Install Steam picks a runtime that has both, and Diagnostics warns when Steam runs on
  one that lacks them.
* GnuTLS also gives every other Windows program working HTTPS through Windows' own APIs (WinHTTP,
  WinINet), which online features and launchers use.

## Game stores and online play (2026-11-01)

**Setup → Game stores** installs each store's official app into its own environment: Steam, Epic Games Launcher,
EA app, Ubisoft Connect, GOG Galaxy and Battle.net. Downloads come only from each store's own hosts over HTTPS;
a redirect elsewhere is refused.

| Store | Installer | Engine support | Tested |
|---|---|---|---|
| Steam | Silent (`/S`) | Steam web helper fix and GnuTLS (Alloy patches) | Sign-in window and QR code (on an unfiltered network); signing in **untested** |
| Epic Games Launcher | `msiexec /i … /qb`; starts with `-SkipBuildPatchPrereq` | CrossOver's own kernelbase fix for `EpicGamesLauncher.exe` is in the engine | **Untested** (not downloaded, as asked) |
| Ubisoft Connect | Silent (`/S`) | CrossOver's fix for `upc.exe` and `UplayWebCore.exe` is in the engine | **Untested** |
| Battle.net | Its own windows | CrossOver's Battle.net registry fix is in advapi32 | **Untested** |
| EA app, GOG Galaxy | Their own windows | GnuTLS only | **Untested**. GOG's web installer can hang under Wine Mono (WineHQ bug 49132); GOG games also come as offline installers |

* Games installed in Steam (`steamapps/appmanifest_*.acf`, fully installed only) and the Epic Games Launcher
  (`ProgramData/Epic/EpicGamesLauncher/Data/Manifests/*.item`) are added to the library on start and whenever the
  store app closes. They start through the store (`steam://rungameid/<id>`,
  `com.epicgames.launcher://apps/<namespace>%3A<item>%3A<app>?action=launch&silent=true`), which signs them in.
* **Sign-in failures on filtered networks.** On 2026-11-01 Steam showed "Download failed: http error 0" and its
  connectivity test got HTTP 403. The network's FortiGuard filter ("Web Filter Violation") answered for
  `steamconnecttest.com` and reset HTTPS to Steam, Epic accounts, EA, Ubisoft, GOG and Battle.net, for macOS
  itself as well. Alloy now checks each store's sign-in server from macOS (Setup, `alloyctl check-stores`,
  and whenever a store app starts) and says when a network blocks it. It does not get around filters.
* **Networking inside Wine works**, measured with a test program in the Steam environment: DNS, TCP, UDP (a raw
  DNS query to 1.1.1.1) and WinHTTP HTTPS with certificate checks (Google, Cloudflare: HTTP 200). Steam and Epic
  failed there only with error 12157, the same block.
* Anti-cheat: the game page names Easy Anti-Cheat, BattlEye or Riot Vanguard found in a game's folder before its
  first start, as well as in its log. Online modes behind them may refuse Wine on a Mac.
* The app declares `NSLocalNetworkUsageDescription`, so macOS can ask before games find players on the local network.

## Performance metrics (2026-11-01)

Metrics are Apple's Metal performance HUD. Every game loads it (`MTL_HUD_ENABLED=1`), and Alloy hides it in each
process as it appears: it watches the log for libMTLHud's first line (`exe[pid:tid] [libMTLHud] …`) and posts
`com.apple.metal.hud.notify.ToggleEnabled`, the notification behind the HUD's own ⇧F9 menu item. ⌥⌘M, a Carbon hot key
registered only while a game runs, posts the same notification. It needs no Accessibility permission. Verified on
macOS 27.2 with a Metal test app: the HUD hides and shows on the notification, including when it is posted right as the
HUD loads. **Show metrics when the game starts** (game page) skips the hiding; Settings can turn the shortcut off, and then
the HUD is not loaded at all.

## Visual C++ runtime (added 2026-11-01)

Games that need Microsoft's Visual C++ 2015–2022 runtime say so before they start (some Unreal Engine 5 games ask for
"Visual C++ for x64"). Wine's own msvcp140 is not enough for those checks.

* **Install Visual C++…** on the game page (or in the environment's menu) downloads `VC_redist.x64.exe` and
  `VC_redist.x86.exe` from Microsoft (aka.ms → download.visualstudio.microsoft.com, about 40 MB together), keeps them only
  if their SHA-256 matches the one in Microsoft's download address, and runs them with `/install /quiet /norestart`.
  Wine is then told to prefer Microsoft's DLLs (`native,builtin`, the list winetricks' `vcrun2022` uses).
* The installers are 32-bit programs, so the environment needs 32-bit support (every environment made since
  2026-10-31 has it).
* Diagnostics warns when a game ships Microsoft's installer (`_CommonRedist/vcredist`, Unreal's prerequisites) and its
  environment does not have the runtime.
* Verified in a new DXMT environment: both installers finished in about a minute, the registry reports
  v14.44.35211.00 for x64 and x86, and a test program loads Microsoft's msvcp140, vcruntime140 and vcruntime140_1
  (14.44.35211), not Wine's. **Not yet tested with a game that requires it.**
* Fixed the same day: Wine writes "installed" Visual C++ 14.42 registry keys into every new environment, so Alloy
  reported the runtime as installed when only Wine's stand-in DLLs were there (and hid the Install button). Detection
  now requires Microsoft's msvcp140/vcruntime140 DLLs in system32 and syswow64 (Wine's carry a "Wine builtin DLL"
  marker). Also verified in an existing environment: the test program there loads Microsoft's 14.44 DLLs.

## Videos, frame pacing and Game Mode (added 2026-11-01)

Measured with Alloy's own test programs (`test.mp4`: H.264 High 1280×720, 90 frames, AAC audio; a D3D11 pacing
test), not with the games.

* **Videos (MP4/H.264/AAC).** Unreal Engine menus that play a video background stayed blank, and one game's log showed
  Media Foundation's MP4 reader `{317df618-…}` as "not registered": the runtimes had no GStreamer. They now include
  GStreamer 1.24 with Apple's VideoToolbox/AudioToolbox decoders (no software H.264 decoder is bundled). Existing
  environments get the decoder registered on their next launch. Result: all 90 frames and the audio decode, in 64-bit
  and 32-bit programs, in a new environment and in two existing ones.
* **Frame-rate cap.** Rendering faster than the display presents unevenly: uncapped, the pacing test ran at 240 FPS
  with half its frames over 1.5× the average frame time. **Frame rate cap** on the game page now defaults to the
  display maximum (120 on ProMotion), through DXMT's `d3d11.preferredMaxFrameRate`, DXVK's `DXVK_FRAME_RATE` or, for
  fixed values, D3DMetal's `D3DM_MAX_FPS` (its limiter paces 120 unevenly, so at the display maximum vsync limits
  it). Capped: 120.1 FPS, 2 of 840 frames over 1.5×.
* **ProMotion and exclusive fullscreen.** A game asking for 60 Hz exclusive fullscreen made Wine switch the display to
  60 Hz, which held one game to 60 FPS even with its limit on Unlimited. `patches/wine/0002` keeps the display at its
  fastest mode for the requested size. Result: the display stays at 120 Hz; with vsync off the test runs at 120.
* **Game Mode.** macOS turns Game Mode on only for apps in the games category, read from an app bundle's Info.plist;
  Wine's loader has none (macOS ignores the plist embedded in it). `patches/wine/0003` starts each Windows program from
  a small `<name>.exe.app` bundle in the games category, in the temporary folder CrossOver already uses for its
  per-program loader links. Result: macOS grants the program Game Mode in fullscreen ("game mode session" in
  `gamepolicyd`'s log). Wine's own programs in system32 are not marked as games.
* **A game froze after its intro.** With videos working, an Unreal Engine 4 game played its intro and then froze with the cursor
  still moving. Alloy's thread backtraces showed the game's main thread waiting on Media Foundation and Wine's
  media source waiting for an audio buffer that never came. Its main menu background video is
  unlike its MP4s: 3440×1440 H.264 at 57 Mbit/s with 16-bit PCM audio stored in half-second chunks, so about
  3.5 MB of video sits between two audio chunks. Wine keeps one buffer per stream and the demuxer's queue holds
  2 MB, and the media source waited for every stream's samples on one queue, so the audio wait held up the video
  requests that would have emptied the queue. `patches/wine/0004` waits for each stream on its own queue. Result,
  with a test clip of the same format and layout: before, Wine's Media Session froze after 1 video frame and 3
  audio buffers; after, all 600 frames and 10 s of audio play in real time, in 64-bit and 32-bit, and also when
  restarted from the start three times (as a looping menu does) and when closed mid-playback. The Source Reader
  decodes the clip fully. Seeking to a new position while playing still stops playback, as it did before the
  change. In the game (reported by the tester): it now reaches its main menu.
* **Unreal Engine 5 videos.** Unreal Engine 5 games play MP4s with Unreal Engine 5's Electra player, which
  hands Wine's H.264 decoder a Direct3D 11 device and asks for NV12 frames in textures. DXMT 0.80 cannot create NV12
  textures (nor does DXMT main), so the decoder failed on the first frame: a test program set up the same way decoded
  0 of 48 frames. CrossOver's Wine also hides NV12 from the decoder's list on macOS. `patches/wine/0005` declines a
  device without NV12 textures, so the caller decodes to system memory, and lists NV12 last instead of not at all.
  Result: 48 of 48 frames, correct pixels, with and without the device; the earlier Media Session and Source Reader
  tests (64- and 32-bit, the clip format above) still pass. Menu backgrounds in Bink 2 (`.bk2`) use a different
  player that this does not touch and that cannot be tested without RAD's tools. DXMT 0.80 also lacks
  `EnumAdapterByLuid` (DXMT main has it), which some Unreal Engine 5 games call at start-up. **Not yet checked in the game.**
* **Distant fog cut off in an Unreal Engine 4 game** (reported; open). The cause is not found yet. The game writes no
  log, and DXMT's log for it shows no errors. DXMT 0.80 passes a D3D11 test of the features Unreal Engine 4 draws fog
  with, compared against CPU results:
  * a 160×90×128 half-float volume filled and integrated by compute shaders, then sampled past its last slice;
  * layered rendering into every slice of a 3D texture through a geometry shader;
  * reversed-Z depth read through D32_FLOAT_S8X24 and D24_UNORM_S8 views, turned into exponential height fog from
    10 to 10¹³ units, with start and cutoff distances.

  DXMT does not support the depth-bounds test, so Unreal Engine does not use it.

## Shader stutter, start time and CPU scheduling (measured 2026-11-04)

Test Mac: M4 MacBook Pro, DXMT 0.80 engine. Programs written for these tests; no game was run.

**Shader caches.** DXMT saves converted shaders in an SQLite file and Metal saves the pipelines it builds from them,
both in macOS's cache folder (`getconf DARWIN_USER_CACHE_DIR`) under `dxmt/<program name>/`, which macOS may clear.
Alloy now keeps both in `ShaderCache/<game-id>/` in its support folder (`DXMT_SHADER_CACHE_PATH`, and a link for
Metal's `com.apple.metal`), carrying over what was already saved. A D3D11 program drawing with 200 different pixel
shaders, 20 frames:

| Caches | Worst frame | All 20 frames |
|---|---|---|
| None (first play) | 47–69 ms | 286–293 ms |
| Both kept | 11–21 ms | 124–175 ms |
| Only DXMT's file missing | 24–28 ms | 172–186 ms |
| Only Metal's cache missing | 31–37 ms | 249–257 ms |
| macOS cache folder cleared, Alloy's kept (3 runs) | 11–15 ms | 152–157 ms |

The first play of a game still converts every shader once; the saved work removes that from later plays.
DXMT reads at most 260 characters of the path, so very long support-folder paths fall back to DXMT's default.

**Start time.** Wine reaches a program's `main()` in 0.72 s, with or without its server already running and with or
without `winemenubuilder`. Keeping wineserver alive was not added. Alloy's own scan of a game's files (DirectX, DLSS,
Visual C++) took about 0.5 s for Steam's folder in a release build and ran on every visit to the game page; it is
now saved per program version in `game-scans.json`.

**CPU scheduling.** Running the game at a higher quality-of-service class did not reach the game (Wine re-executes
its loader, and an injected library never ran in the game process). With 10 busy background loops, frame times of a
4-thread test differed by less than 0.5 ms and the slowest frames were within noise. Not shipped; Game Mode already
gives the game priority.

**Crashes.** Wine's debugger window is turned off per environment (`ShowCrashDialog=0`), so a crashed game ends within
seconds with a backtrace in its log and Alloy's explanation, instead of waiting on Wine's dialog. Checked with test
programs that crash on a null pointer and on an illegal instruction.


## MSync (measured 2026-11-05)

All three engines (Alloy Game Engine, DXMT 0.80, D3DMetal 4.0b3) are built from CrossOver 26.3's Wine source, which
includes MSync (Mach-semaphore synchronisation). Alloy turns it on for every game unless the game's Sync setting says
otherwise. A test program (`synctest.exe`: two threads passing an event back and forth 20,000 times, then four threads
contending for one mutex for 1 s), two rounds each on the Alloy Game Engine:

| | Event round trip | Mutex locks per second |
|---|---|---|
| MSync on | 3.7–6.9 µs | 3.1 million |
| MSync off | 20.2 µs | 0.15 million |

Every program in an environment shares one wineserver, and Wine refuses to start a program whose MSync setting
differs from the server's (`msync_init Server is running with WINEMSYNC but this process is not`, exit code 1). This
happened when a game with MSync off started while Steam or another program ran with it on. Alloy now checks the
server before each start (its lock file, and the `wine-<inode>-msync` Mach service MSync registers) and follows the
running server, saying so in the game's log; the diagnostics explain the error in plain English if it still occurs.

## Cursor showing over games (2026-11-05)

Reported: the macOS arrow sometimes appeared over a running Unreal Engine game. Wine's Mac driver hides the cursor
once and remembers that it did; if macOS shows it again by itself, Wine never hides it again until the game changes
its cursor. `patches/wine/0006` hides it again at most every 0.25 s while the mouse moves and the game wants it
hidden, and keeps the game's window as the mouse target when the cursor is confined to it or a fullscreen game's
window has another window (menu bar, notification) over it.

Tested with `cursortest.exe` (a full-screen window that hides the cursor; GDI or Direct3D 11 through DXMT with the
hidden Metal HUD; with and without ClipCursor; with Unreal-style SetCursorPos to the centre every frame; as a child of
a launcher process that keeps running), with screenshots with and without the cursor around the pointer: before and
after the patch the cursor stayed hidden at all four edges, under the menu bar, after a notification and after
switching to another app and back; it showed only while another app was in front, as it should. With the patch it
was hidden in 60 of 60 screenshots taken while the pointer moved (no flicker). None of these reproduced the reported
case; after the patch the user reported the arrow no longer appears in the Unreal Engine game where they saw it.

## Looking around stuck left or right (2026-11-07)

Reported: in a game, turning the view left or right sometimes stopped while up and down still worked, as if the mouse
were stuck at the edge of the screen. Wine's Mac driver confines the cursor for ClipCursor with a window's mouse
confinement rect, which macOS limits to the window, so the cursor is held to the part of the game's rect inside the
window. To decide whether the cursor is pinned (and send the mouse's own motion instead of a position), Wine tested the
rect the game asked for. Games often clip to their whole monitor or to a rect a little larger than their window, so at
the window's edge the next position was still "inside", and Wine sent absolute moves to the same spot: no movement
that way. `patches/wine/0007` tests the region the cursor is really held in, read back from the window, and counts a
cursor within a point of its edge as pinned. Shipped in engine package `dxmt-0.80-cx26.3-3` (package -2 with only
`winemac.so` rebuilt).

Not yet tested in a game: the cause was found by reading the driver's code, and the fix builds and loads. Check it in
the game where it happened: windowed or borderless, turn left or right until the view would have stopped.

## Metrics shortcut showing nothing (2026-11-07)

Metal's HUD appears as it loads, so Alloy used to hide it in each process by posting the HUD's toggle notification.
That notification reaches every process with the HUD, so a second process (a launcher, then the game) flipped the
first one back, and the shortcut could then show metrics in one window while hiding them in another. libMTLHud reads
`MTL_HUD_HIDDEN=1` to load hidden (tested with a Metal test window: hidden at start, shown after one toggle), so every
process now starts hidden and the shortcut toggles them all together.

## Steam games and their settings (2026-11-07)

Started by an already-open Steam, a game inherited the environment Steam was opened with: a game set to Balanced ran
with Sharp's MetalFX 2× because Steam had been opened for another game that used Sharp (seen in the logs: the second
game's processes logged into the first game's session). Alloy 1.0 Beta starts Steam games itself when Steam is open,
and when it isn't, opens Steam quietly (`-silent`), waits for "Logged On" in Steam's `logs/connection_log.txt` and then
starts the game itself. Game Mode needs the game frontmost and fullscreen; a game started by Alloy is started from the
app the player just clicked. Not yet confirmed in `gamepolicyd`'s log for a Steam game.


## Steam's first-run installers (.NET, Visual C++, DirectX)

Before a game's first start Steam runs the installers in the game's `installscript.vdf` files and records each one under
`HKLM\Software\Wow6432Node\Valve\Steam\Apps\CommonRedist`. Microsoft's .NET Framework installer never finishes under
Wine, which left Steam stuck on "Installing…" (reported by a tester, with .NET and Visual C++). Before Steam or a game in
its environment starts, and while Steam is open whenever it finishes downloading a game, Alloy records the .NET, XNA and
DirectX entries as done (Wine Mono and Wine's own DirectX stand in), installs Wine Mono and Visual C++ itself when
automatic components are on, and records Visual C++ once Microsoft's runtime is installed. Checked: the record lands in
the 32-bit view Steam reads, in the same form Steam writes. Not yet confirmed by the tester in Steam.

## XNA games (Terraria): FNA graphics driver

Wine Mono 10.4.1 runs XNA games on FNA 25.11, whose default driver is SDL_GPU on Vulkan (MoltenVK). A tester's Terraria
crashed right after `vkCreateBuffer(): Only external memory handle type … MTLBUFFER … supported` (Apple M5). Alloy sets
`FNA3D_FORCE_DRIVER=D3D11`, so FNA draws through the game's Direct3D 11 path (DXMT). Tested with a small XNA program
built with Wine Mono's compiler: SDL_GPU/Vulkan, D3D11 and OpenGL all drew 240 frames on an M4; D3D11 started in 2.4 s
against 10.8 s for the default. Terraria itself has not been tested.

## Input delay (Brawlhalla, reported)

Not reproduced; Brawlhalla hasn't been tested. DXMT 0.80 lets a game queue up to three frames (`max_latency_ = 3`)
with no setting to lower it, which at 60 FPS can add up to about 50 ms. A lower limit needs a DXMT change in a new
engine build.
