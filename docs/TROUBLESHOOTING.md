# Troubleshooting

| Symptom (Diagnostics finding) | Cause | Fix |
|---|---|---|
| "No Wine runtime" | No Wine install found | Install a Gcenx build (see README), then **Environments → Rescan** |
| "Rosetta 2 is not installed" / `Bad CPU type` | x86_64 Wine without Rosetta | Run `softwareupdate --install-rosetta --agree-to-license` yourself |
| "Prefix not initialised" | `wineboot` has not run | **Environments → Initialise** |
| "Missing DLL: MSVCP140.dll" etc., "Visual C++ runtime not installed", or the game asks for Visual C++ | Visual C++ runtime missing | **Install Visual C++…** on the game page (or in the environment's menu). Alloy downloads Microsoft's installer and runs it in that environment |
| Menu background blank, videos do not play, "Videos cannot play in this runtime" | Runtime without GStreamer | Use an Alloy runtime, or run `scripts/patch-wine-runtime.sh` on it; environments get the decoder on their next launch |
| Stutter or "frame drops" at a high, steady FPS | Game renders faster than the display | **Frame rate cap → Display maximum** on the game page (the default) |
| Game held to 60 FPS in fullscreen on a 120 Hz display | Exclusive fullscreen switched the display to 60 Hz | Alloy runtimes keep the display at 120 Hz (`scripts/patch-wine-runtime.sh` for older ones) |
| Game Mode stays off | Program not seen as a game by macOS | Alloy runtimes start each program from a games-category bundle; Game Mode needs fullscreen |
| "Missing DLL: d3dx9_43.dll / xinput1_3.dll" | Legacy DirectX runtime missing | Run the game's bundled DirectX June 2010 installer in the environment |
| "DX11 feature level 10.0 is required" / DX12 errors | Graphics path lacks the features | Enable **Force DirectX 11 (-dx11)**; for full DX12 you need D3DMetal |
| "Vulkan is unavailable" | No MoltenVK in the runtime | Use WineD3D (OpenGL) or a runtime that includes MoltenVK |
| "Wine server version mismatch" | Two Wine versions used one prefix | **Stop all programs in this environment**; keep one runtime per environment |
| "Prefix ownership problem" | Wine was run with `sudo` | Never run Wine as root; create a new environment |
| "Anti-cheat detected" | EAC / BattlEye / Vanguard | Online modes usually cannot work under Wine on macOS |
| Graphics "requested, not confirmed" | No renderer evidence in the log | Not necessarily an error. Enable the Metal HUD or Verbose logging to check |
| Stutter on first play that disappears later | Shader compilation | Replay the scene; measure the second run (see Performance) |
| "Steam will not fully work on this runtime" / Steam window black | Runtime lacks the Steam web helper fix | Use an Alloy runtime, or run `scripts/patch-wine-runtime.sh` on this one |
| "No encryption support in this runtime" / Steam cannot sign in, greyed-out QR code | Wine built without GnuTLS | Same: an Alloy runtime, or `scripts/patch-wine-runtime.sh` |
| Picture freezes but the cursor still moves / "A thread was stuck waiting on a lock" | A deadlock between the game's threads (often in video or audio playback) | Alloy saves every thread's backtrace to a `-threads-…txt` file beside the game's log. Keep it with the log; it shows which lock each thread waits for |

## Logs

* Per-run logs: `~/Library/Application Support/Alloy/Logs/` (**Diagnostics → Open Logs Folder**)
* Verbose logging (**Settings**) adds `+loaddll,+seh`. It helps with DLL problems but slows games down.
* **Export Diagnostic Report** writes a redacted Markdown file you can inspect before sharing.
* Thread backtraces: saved automatically when Wine reports a thread stuck on a lock (up to 3 a session, a
  minute apart), or with **Diagnostics → Save Thread Backtraces** while a game runs. Attaching pauses the game
  for a moment. Home-folder paths are shortened to `~`.

## Safety notes

* Alloy never changes macOS security settings, never asks for administrator rights, and never
  touches CrossOver bottles.
* Deleting an environment moves it to the Trash. Your saves inside it can be recovered from there.
