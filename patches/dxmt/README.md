# DXMT patches

Alloy's game engine uses DXMT v0.80 (https://github.com/3Shain/dxmt, MIT licence) with these changes to its
`d3d11.dll`. Everything else in DXMT (dxgi, d3d10core, winemetal) is the v0.80 release as published.

- `0001-dxgi-max-frame-latency-option.patch`: a `dxgi.maxFrameLatency` option (named after DXVK's), read from
  `DXMT_CONFIG`. When set to 1 to 16 it replaces the number of frames a game may queue ahead of the GPU (DXMT's
  default is 3, or what the game asks for with `SetMaximumFrameLatency`). Alloy sets it to 1 when a game's
  "Low input delay" setting is on. 0 or unset leaves DXMT's behaviour unchanged.
- `0002-include-iomanip-for-gcc-16.patch`: a missing standard header that GCC 16 (mingw-w64) needs. No change in
  behaviour.
- `0003-fullscreen-size-with-wine-mode-emulation.patch`: when Wine's mode emulation is on (`EmulateModeset` under
  `HKCU\Software\Wine\X11 Driver`, which Alloy turns on in every game environment), fullscreen asks Wine for the
  swap chain's size even if the game didn't set `DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH`. DXMT otherwise keeps the
  desktop mode for such games, so a game going fullscreen at 1024×665 on an 1800×1169 desktop drew into a 1024×665
  window in the top-left corner, and after a minimize and restore Wine stretched that window to 1800×1169 while the
  game still drew at 1024×665 (BeamNG.drive: wrong UI and camera scaling). With emulation the real display never
  changes mode: Wine reports the requested size to the game and scales the picture to fill the screen, which is what
  Windows does for these games. With emulation off, nothing changes.

## Building d3d11.dll

`scripts/build-dxmt-d3d11.sh` builds the 64- and 32-bit `d3d11.dll` with mingw-w64, meson and ninja, from a DXMT v0.80
checkout (with submodules) and a Wine build folder (for winebuild, which marks the DLL as a Wine builtin).

DXMT embeds one Metal library in d3d11 (`dxmt_command.metallib`, compiled from `src/dxmt/dxmt_command.metal`).
Compiling it needs Xcode's Metal toolchain. Without it, the script takes that library from the official v0.80
`d3d11.dll` (it is byte-identical in the 64- and 32-bit builds) instead of compiling it, so the shader code is
exactly the released one. None of the patches touch the Metal source.

## Measured

`d3d11.dll` with patch 0001, in Alloy's engine on an M-series Mac at 120 Hz, with a D3D11 test that renders with
`Present(0, 0)` and times when each frame's GPU work finishes after the game submitted it:

| load | queued frames | frame rate | submit → finished (average) |
| --- | --- | --- | --- |
| light | 3 (default) | 120 fps | 33.0 ms |
| light | 1 | 120 fps | 16.6 ms |
| GPU-heavy | 3 (default) | 38.6 fps | 103.7 ms |
| GPU-heavy | 1 | 38.6 fps | 51.8 ms |

The game asked for 3 frames with `SetMaximumFrameLatency(3)` and still got 1, as with DXVK's option.
