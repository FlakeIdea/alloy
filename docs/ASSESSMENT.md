# Alloy — Technical Assessment (2026-10-29)

## 1. Environment (inspected locally)

| Item | Finding |
|---|---|
| macOS | 27.2 (build 26B118) |
| CPU / RAM | Apple M4, arm64, 16 GB unified memory |
| Free disk | ~125 GB of 460 GB |
| Developer tools | **Command Line Tools only** (no Xcode.app). Swift 6.2.3, Swift Testing framework present, XCTest/xcodebuild unavailable |
| Homebrew | 7.0.9 |
| Rosetta 2 | Installed and running |
| Wine | **Not installed** (no `wine`, no Wine*.app) |
| Vulkan / MoltenVK | Not installed system-wide |
| CrossOver | `~/Applications/CrossOver.app` present; three bottles (CrossOver 26.3, win64). **Treated as read-only; never modified.** |

Consequences:
* The app is built with **Swift Package Manager** (works with Command Line Tools). Opening `Package.swift` in Xcode works if Xcode is installed later; no `.xcodeproj` is generated because `xcodebuild` is unavailable.
* Tests use **Swift Testing** (`import Testing`), not XCTest.
* Nothing Windows-related can execute until a Wine runtime is installed (requires your approval — ~225 MB download).

## 2. Open-source landscape (verified via GitHub API on 2026-10-29)

| Project | Status | Licence | Role / constraints |
|---|---|---|---|
| Wine (upstream) | Active | LGPL-2.1+ | Core compatibility layer. Wine ≥ 9 on macOS uses "new WoW64": one 64-bit prefix runs both 32- and 64-bit Windows programs, no 32-bit host libraries. |
| Gcenx/macOS_Wine_builds | Active — 11.20 released 2026-10-29 | LGPL (Wine) | Best free prebuilt Wine for macOS. **x86_64 only (`osx64`) — runs under Rosetta 2**, not ARM-native. Bundles wine-mono, wine-gecko, GStreamer. Devel and Staging variants. |
| Homebrew `wine-stable` cask | **Disabled 2026-09-01** (fails Gatekeeper) | — | Do not depend on it. |
| Whisky (Whisky-App) | **Archived 2025-05-11** | GPL-3.0 | Reference only. Alloy does not copy its code. |
| frankea/Whisky fork | Active — app-v3.7.0 (2026-08-30) | GPL-3.0 | Alternative frontend; shows the ecosystem still works. |
| Sikarugir (Kegworks successor) | Active | — | Wrapper creator; not used. |
| Apple Game Porting Toolkit / D3DMetal | GPTK 3.0 (Gcenx repack 2026-03-03) | **Proprietary Apple licence** — evaluation terms, redistribution unclear | DirectX 11/12 → Metal, best performance for most modern DX games on Apple Silicon. **Alloy never bundles or downloads it**; users point Alloy to their own copy. |
| DXVK (upstream) | Active — v3.1.1 | zlib | D3D8/9/10/11 → Vulkan. **Requires Vulkan features MoltenVK does not expose**; not usable on macOS as-is. |
| Gcenx/DXVK-macOS | Stale — v1.10.3 (2023 build, repack 2024) | zlib | Old DXVK branch patched for MoltenVK. D3D10/11 only. Experimental. |
| vkd3d-proton | Active — v3.1 | LGPL-2.1 | D3D12 → Vulkan. **Not viable on MoltenVK** (needs descriptor-buffer / heap features MoltenVK lacks). Not offered. |
| vkd3d (Wine's own) | Active, built into Wine | LGPL | Wine's builtin D3D12 over Vulkan; works partially over MoltenVK. Experimental. |
| MoltenVK | Active — v1.4.2 (2026-07-24) | Apache-2.0 | Vulkan → Metal. Needed by Wine's Vulkan renderer, vkd3d and DXVK-macOS. |
| KosmicKrisp (LunarG/Mesa) | Emerging | MIT | Vulkan-on-Metal driver from Mesa; may eventually make upstream DXVK viable. Not integrated; to evaluate. |

## 3. Technically valid graphics combinations

| Backend in Alloy | DirectX | Requires | Status |
|---|---|---|---|
| WineD3D (OpenGL) | 1–11 | Any Wine | Works everywhere. Slowest. OpenGL is deprecated on macOS. |
| WineD3D (Vulkan renderer) | 1–11 | Wine + MoltenVK | Experimental. |
| Wine vkd3d (D3D12) | 12 | Wine + MoltenVK | Experimental, low compatibility. |
| DXVK-macOS | 10/11 | Wine + MoltenVK + user-supplied DXVK-macOS DLLs installed into an Alloy prefix | Experimental. |
| D3DMetal | 11/12 (DX9 via Wine) | A GPTK-based Wine build that contains `D3DMetal.framework` (user-supplied) | Best performance when available; proprietary. |

Alloy only enables a combination when its requirements are detected, and it reports
the graphics backend as **requested**, not **active**, until it finds evidence in the logs.

## 4. Target games — honest expectations (not yet tested)

* The first target games are Unreal Engine 4/5 titles that default to DX12 with a DX11 fallback (`-dx11`). Community reports suggest they run under D3DMetal-based stacks. They will most likely **not** run acceptably under WineD3D/OpenGL.
* So with free components only, realistic performance needs the user-supplied GPTK/D3DMetal runtime. Without it, expect poor or no rendering.
* None of them ships kernel anti-cheat (to the best of current knowledge), which removes the biggest blocker.
* Steam DRM: games need the Windows Steam client running inside the same prefix.

## 5. Security model

* No shell is ever used to launch anything: `Process` with an argument vector.
* Executables run only after an explicit click and a confirmation showing the path, PE architecture and runtime. The confirmation is required again if the file changes.
* `DYLD_*` environment variables are blocked. Logs are redacted (home path, `password=`/`token=`-style secrets).
* Removing a game removes only the library entry. Deleting a prefix moves it to the Trash (reversible).
* CrossOver bottles are listed read-only and never written to.

## 6. Plan

1. **Milestone 1 (this session):** core library (models, PE/Mach-O inspection, library persistence, backend protocol, Wine runtime discovery, prefix manager, launcher with log capture, diagnostics, graphics capability matrix, frame-time statistics, quality-first advisor), SwiftUI app, tests, `.app` bundle.
2. **Milestone 2 (needs approval):** install a Gcenx Wine build, then test with Wine's built-in harmless programs (`cmd /c echo`, `winver`, `notepad`).
3. **Milestone 3:** GPTK/D3DMetal runtime support with user-supplied files; Steam-in-prefix workflow.
4. **Milestone 4:** game testing with your legally obtained copies; record results in `COMPATIBILITY.md`.
5. **Milestone 5:** automated frame-time capture, UE4 `GameUserSettings.ini` preset editing with backups.
