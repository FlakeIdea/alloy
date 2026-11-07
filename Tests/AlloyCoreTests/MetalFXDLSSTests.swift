import Foundation
import Testing
@testable import AlloyCore

@Suite struct MetalFXDLSSTests {
    /// A fake runtime laid out like D3DMetal 4 (Apple's `nvngx-on-metalfx` names) or DXMT (`nvngx.dll`).
    func runtime(in dir: TempDir, d3dMetal: Bool, interpolation: Bool = false) -> WineRuntime {
        let base = "Runtimes/r/wine"
        dir.write("\(base)/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("\(base)/lib/wine/x86_64-windows/nvapi64.dll", Data("nvapi".utf8))
        if d3dMetal {
            dir.write("\(base)/lib/wine/x86_64-windows/nvngx-on-metalfx.dll", Data("ngx-pe".utf8))
            dir.write("\(base)/lib/wine/x86_64-unix/nvngx-on-metalfx.so", Data("ngx-unix".utf8))
            dir.write("\(base)/lib/external/D3DMetal.framework/D3DMetal",
                      Data((interpolation ? "x MTLFXFrameInterpolatorDescriptor x" : "no").utf8))
        } else {
            dir.write("\(base)/lib/wine/x86_64-windows/nvngx.dll", Data("dxmt-ngx".utf8))
            dir.write("\(base)/lib/wine/x86_64-windows/winemetal.dll", Data())
            dir.write("\(base)/lib/wine/x86_64-unix/winemetal.so", Data())
        }
        let root = dir.url.appendingPathComponent(base)
        return WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in "11.0" })
            .makeRuntime(kind: .custom, binary: root.appendingPathComponent("bin/wine"), root: root)
    }

    @Test func detectsShimsAndFrameInterpolation() {
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let d3dm = runtime(in: TempDir(), d3dMetal: true, interpolation: true)
        #expect(d3dm.hasNVNGX && d3dm.hasFrameInterpolation)
        #expect(backend.capabilities(of: d3dm).metalFXUpscaling == [.d3dMetal])
        #expect(backend.capabilities(of: d3dm).metalFXFrameGeneration == [.d3dMetal])
        let older = runtime(in: TempDir(), d3dMetal: true, interpolation: false)
        #expect(backend.capabilities(of: older).metalFXFrameGeneration.isEmpty)
        let dxmt = runtime(in: TempDir(), d3dMetal: false)
        #expect(backend.capabilities(of: dxmt).metalFXUpscaling == [.dxmt])
        #expect(backend.capabilities(of: dxmt).metalFXFrameGeneration.isEmpty)
        #expect(backend.capabilities(of: makeFakeRuntime(in: TempDir())).metalFXUpscaling.isEmpty)
    }

    @Test func launchSetsTheLayersSwitchOnlyWhenOn() throws {
        let dir = TempDir()
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let dxmt = runtime(in: dir, d3dMetal: false)
        let prefix = makeInitializedPrefix(in: dir)
        var game = makeGame(in: dir)
        game.graphics.backend = .dxmt
        var cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: dxmt, options: LaunchOptions())
        #expect(cmd.environment["DXMT_ENABLE_NVEXT"] == nil)
        #expect(cmd.waitsForChildProcesses)
        game.graphics.dlss = true
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: dxmt, options: LaunchOptions())
        #expect(cmd.environment["DXMT_ENABLE_NVEXT"] == "1")
        #expect(cmd.environment["D3DM_ENABLE_METALFX"] == nil)
        // A runtime without an NGX shim never gets the switch.
        game.graphics.backend = .wined3dOpenGL
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: makeFakeRuntime(in: dir), options: LaunchOptions())
        #expect(cmd.environment["DXMT_ENABLE_NVEXT"] == nil && cmd.environment["D3DM_ENABLE_METALFX"] == nil)
    }

    @Test func installsShimsKeepingTheOriginals() throws {
        let dir = TempDir()
        let d3dm = runtime(in: dir, d3dMetal: true)
        let prefix = makeInitializedPrefix(in: dir)
        dir.write("prefix/drive_c/windows/system32/nvapi64.dll", Data("wine-stub".utf8))

        try MetalFXDLSS.installShims(from: d3dm, into: prefix, runtimeIsManaged: true)
        let lib = d3dm.root.appendingPathComponent("lib/wine")
        // Apple's Read Me: the shim is used under the name nvngx (both halves); the originals stay.
        #expect(try Data(contentsOf: lib.appendingPathComponent("x86_64-unix/nvngx.so")) == Data("ngx-unix".utf8))
        #expect(FileManager.default.fileExists(atPath: lib.appendingPathComponent("x86_64-windows/nvngx-on-metalfx.dll").path))
        #expect(try Data(contentsOf: prefix.system32.appendingPathComponent("nvngx.dll")) == Data("ngx-pe".utf8))
        #expect(try Data(contentsOf: prefix.system32.appendingPathComponent("nvapi64.dll")) == Data("nvapi".utf8))
        let saved = prefix.path.appendingPathComponent("alloy-backup/nvngx/nvapi64.dll")
        #expect(try Data(contentsOf: saved) == Data("wine-stub".utf8))
        // Running it again changes nothing and keeps the first backup.
        try MetalFXDLSS.installShims(from: d3dm, into: prefix, runtimeIsManaged: true)
        #expect(try Data(contentsOf: saved) == Data("wine-stub".utf8))
    }

    @Test func leavesUnmanagedRuntimesAlone() {
        let dir = TempDir()
        let d3dm = runtime(in: dir, d3dMetal: true)
        let prefix = makeInitializedPrefix(in: dir)
        #expect(throws: AlloyError.self) { try MetalFXDLSS.installShims(from: d3dm, into: prefix, runtimeIsManaged: false) }
        #expect(!FileManager.default.fileExists(atPath: d3dm.root.appendingPathComponent("lib/wine/x86_64-unix/nvngx.so").path))
    }

    @Test func readsTheNGXRegistryEntry() {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        #expect(!MetalFXDLSS.hasRegistryPath(prefix))
        dir.write("prefix/system.reg", Data(#"""
        WINE REGISTRY Version 2

        [Software\\Nvidia Corporation\\Global\\NGXCore] 1793458504
        #time=1dd6947cfd2f230

        [Software\\Other] 1
        "FullPath"="C:\\elsewhere"
        """#.utf8))
        #expect(!MetalFXDLSS.hasRegistryPath(prefix))
        dir.write("prefix/system.reg", Data(#"""
        WINE REGISTRY Version 2

        [Software\\NVIDIA Corporation\\Global\\NGXCore] 1793296962
        #time=1dd67cfb1cd4750
        "FullPath"="C:\\windows\\system32"
        """#.utf8))
        #expect(MetalFXDLSS.hasRegistryPath(prefix))
        let reg = MetalFXDLSS.registryCommand(like: LaunchCommand(executable: URL(fileURLWithPath: "/w/bin/wine"), arguments: [],
                                                                 environment: ["WINEPREFIX": "/p", "WINEMSYNC": "1"]))
        #expect(reg.arguments == ["reg", "add", #"HKLM\Software\NVIDIA Corporation\Global\NGXCore"#, "/v", "FullPath",
                                  "/t", "REG_SZ", "/d", #"C:\windows\system32"#, "/f"])
        #expect(reg.environment["WINEMSYNC"] == "1" && !reg.waitsForChildProcesses)
    }

    @Test func findsDLSSFilesInUnrealLayouts() {
        let dir = TempDir()
        dir.write("G/Engine/Plugins/Runtime/Nvidia/DLSS/Binaries/ThirdParty/Win64/nvngx_dlss.dll", Data())
        #expect(DLSSUsage.detect(in: dir.url.appendingPathComponent("G")) == [.upscaling])
        dir.write("G/Engine/Plugins/Runtime/Nvidia/Streamline/Binaries/ThirdParty/Win64/NVNGX_DLSSG.DLL", Data())
        #expect(DLSSUsage.detect(in: dir.url.appendingPathComponent("G")) == [.upscaling, .frameGeneration])
        #expect(DLSSUsage.detect(in: dir.url.appendingPathComponent("missing")).isEmpty)
    }

    @Test func defaultsForceDX11AndDLSSForUnrealOnDXMT() {
        let dir = TempDir()
        let dxmt = runtime(in: dir, d3dMetal: false)
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let unreal = GameTraits(usage: [.d3d11, .d3d12], machine: .x64, dlss: [.upscaling], isUnreal: true)
        let choice = GraphicsDefaults.choose(traits: unreal, runtimes: [dxmt], preferredRuntime: nil, backend: backend)
        #expect(choice.backend == .dxmt && choice.forceDX11 && choice.dlss)
        let plain = GraphicsDefaults.choose(traits: GameTraits(usage: [.d3d11], machine: .x64), runtimes: [dxmt],
                                            preferredRuntime: nil, backend: backend)
        #expect(plain.backend == .dxmt && !plain.forceDX11 && !plain.dlss)
    }

    @Test func findsFidelityFXAsGameRunFrameGeneration() {
        let dir = TempDir()
        dir.write("G/bin/amd_fidelityfx_dx12.dll", Data())
        #expect(DLSSUsage.detect(in: dir.url.appendingPathComponent("G")) == [.amdFidelityFX])
        dir.write("H/ffx_fsr3upscaler_x64.dll", Data())
        #expect(DLSSUsage.detect(in: dir.url.appendingPathComponent("H")) == [.amdFidelityFX])
        dir.write("I/ffx_fsr2_api_x64.dll", Data())   // FSR 2 is upscaling only
        #expect(DLSSUsage.detect(in: dir.url.appendingPathComponent("I")).isEmpty)
    }

    @Test func picksD3DMetal4ForDLSSFrameGeneration() {
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let dxmt = runtime(in: TempDir(), d3dMetal: false)
        let d3dm4 = runtime(in: TempDir(), d3dMetal: true, interpolation: true)
        let d3dm3 = runtime(in: TempDir(), d3dMetal: true, interpolation: false)
        let fg = GameTraits(usage: [.d3d11, .d3d12], machine: .x64, dlss: [.upscaling, .frameGeneration], isUnreal: true)
        let choice = GraphicsDefaults.choose(traits: fg, runtimes: [dxmt, d3dm4], preferredRuntime: nil, backend: backend)
        #expect(choice.backend == .d3dMetal && choice.runtime?.id == d3dm4.id)
        #expect(choice.frameGeneration && choice.dlss && !choice.forceDX11)
        // Without frame interpolation in D3DMetal, the measured DX11 default stays.
        let older = GraphicsDefaults.choose(traits: fg, runtimes: [dxmt, d3dm3], preferredRuntime: nil, backend: backend)
        #expect(older.backend == .dxmt && !older.frameGeneration)
        // A DX11-only game, or a 32-bit one, can't use it.
        let dx11 = GameTraits(usage: [.d3d11], machine: .x64, dlss: [.frameGeneration])
        #expect(!GraphicsDefaults.choose(traits: dx11, runtimes: [dxmt, d3dm4], preferredRuntime: nil, backend: backend).frameGeneration)
        let x86 = GameTraits(usage: [.d3d12], machine: .x86, dlss: [.frameGeneration])
        #expect(!GraphicsDefaults.choose(traits: x86, runtimes: [dxmt, d3dm4], preferredRuntime: nil, backend: backend).frameGeneration)
    }

    @Test func frameGenerationStatusFollowsTheGamesOwnData() {
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let caps = backend.capabilities(of: runtime(in: TempDir(), d3dMetal: true, interpolation: true))
        var graphics = GraphicsConfiguration()
        graphics.backend = .d3dMetal
        graphics.dlss = true
        let fg = GameTraits(usage: [.d3d12], machine: .x64, dlss: [.upscaling, .frameGeneration])
        #expect(FrameGeneration.status(traits: fg, graphics: graphics, capabilities: caps, d3dMetal4Installed: true) == .available)
        graphics.forceDX11 = true
        #expect(FrameGeneration.status(traits: fg, graphics: graphics, capabilities: caps, d3dMetal4Installed: true) == .switchAvailable)
        graphics.forceDX11 = false
        graphics.backend = .dxmt
        #expect(FrameGeneration.status(traits: fg, graphics: graphics, capabilities: caps, d3dMetal4Installed: false) == .needsD3DMetal4)
        let fsr = GameTraits(usage: [.d3d12], machine: .x64, dlss: [.amdFidelityFX])
        #expect(FrameGeneration.status(traits: fsr, graphics: graphics, capabilities: caps, d3dMetal4Installed: true) == .gameRuns)
        let none = GameTraits(usage: [.d3d11], machine: .x64)
        #expect(FrameGeneration.status(traits: none, graphics: graphics, capabilities: caps, d3dMetal4Installed: true) == .unsupported)
    }
}
