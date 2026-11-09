import Foundation
import Testing
@testable import AlloyCore

@Suite struct BackendDiscoveryTests {
    @Test func discoversAppBundleRuntimes() {
        let dir = TempDir()
        dir.write("Wine Staging.app/Contents/Resources/wine/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("Wine Staging.app/Contents/Resources/wine/lib/libMoltenVK.dylib", Data())
        dir.write("CrossOver.app/Contents/Resources/wine/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("Unrelated.app/Contents/Resources/wine/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        let backend = WineBackend(applicationDirectories: [dir.url], installRoots: [], versionProbe: { _ in "11.20 (Staging)" })
        let runtimes = backend.discoverRuntimes()
        #expect(runtimes.count == 1)
        #expect(runtimes.first?.kind == .wineStaging)
        #expect(runtimes.first?.hasMoltenVK == true)
        #expect(runtimes.first?.displayName == "Wine Staging 11.20 (Staging)")
    }

    @Test func discoversInstallRootsAndSkipsNonExecutables() {
        let dir = TempDir()
        dir.write("brew/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("broken/bin/wine", Data("#!/bin/sh\n".utf8), executable: false)
        let backend = WineBackend(applicationDirectories: [],
                                  installRoots: [dir.url.appendingPathComponent("brew"), dir.url.appendingPathComponent("broken")],
                                  versionProbe: { _ in nil })
        let runtimes = backend.discoverRuntimes()
        #expect(runtimes.count == 1)
        #expect(backend.capabilities(of: runtimes[0]).notes.contains("Version could not be determined."))
    }

    @Test func noRuntimesWhenNothingInstalled() {
        let backend = WineBackend(applicationDirectories: [URL(fileURLWithPath: "/nonexistent")], installRoots: [], versionProbe: { _ in nil })
        #expect(backend.discoverRuntimes().isEmpty)
    }

    @Test func parsesWineVersionOutput() {
        #expect(WineBackend.parseVersion("wine-11.20 (Staging)\n") == "11.20 (Staging)")
        #expect(WineBackend.parseVersion("garbage") == nil)
    }

    @Test func rosettaDetectionFromArchitectures() {
        let r = WineRuntime(kind: .wineDevel, wineBinary: URL(fileURLWithPath: "/x/bin/wine"), root: URL(fileURLWithPath: "/x"),
                            architectures: [.x86_64])
        #expect(r.requiresRosetta)
        #expect(WineBackend().capabilities(of: r).supportsAVXAdvertisement)
    }
}

@Suite struct CapabilityTests {
    @Test func plainWineOffersOnlyOpenGL() {
        let dir = TempDir()
        let caps = WineBackend().capabilities(of: makeFakeRuntime(in: dir))
        #expect(caps.status(of: .wined3dOpenGL) == .available)
        for kind in [GraphicsBackendKind.wined3dVulkan, .vkd3d, .dxvk, .d3dMetal] {
            #expect(!caps.status(of: kind).isUsable)
        }
        #expect(caps.syncModes == [.default])
    }

    @Test func moltenVKUnlocksExperimentalVulkanPaths() {
        let dir = TempDir()
        let caps = WineBackend().capabilities(of: makeFakeRuntime(in: dir, moltenVK: true))
        #expect(caps.status(of: .dxvk).isUsable)
        #expect(caps.status(of: .vkd3d).isUsable)
        #expect(!caps.status(of: .d3dMetal).isUsable)
    }

    @Test func d3dMetalRequiresFramework() {
        let dir = TempDir()
        let caps = WineBackend().capabilities(of: makeFakeRuntime(in: dir, d3dMetal: true, kind: .gamePortingToolkit))
        #expect(caps.status(of: .d3dMetal) == .available)
        #expect(caps.syncModes == [.default, .esync])
    }

    @Test func msyncIsAutomaticWhereTheBuildHasIt() throws {
        let dir = TempDir()
        var runtime = makeFakeRuntime(in: dir)
        runtime.hasMSync = true
        let caps = WineBackend().capabilities(of: runtime)
        #expect(caps.syncModes == [.default, .off, .msync])

        let prefix = makeInitializedPrefix(in: dir)
        var game = makeGame(in: dir)
        game.prefixID = prefix.id
        let auto = try WineBackend().launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(auto.environment["WINEMSYNC"] == "1")
        game.graphics.syncMode = .off
        let off = try WineBackend().launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(off.environment["WINEMSYNC"] == nil)
    }

    @Test func detectsSyncSupportFromNtdll() {
        let dir = TempDir()
        dir.write("rt/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("rt/lib/wine/x86_64-unix/ntdll.so", Data("....WINEMSYNC....WINEESYNC....".utf8))
        let rt = WineBackend(versionProbe: { _ in nil }).makeRuntime(kind: .custom, binary: dir.url.appendingPathComponent("rt/bin/wine"),
                                           root: dir.url.appendingPathComponent("rt"))
        #expect(rt.hasMSync && rt.hasESync)
    }
}

@Suite struct LaunchCommandTests {
    let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })

    @Test func buildsArgumentVectorWithoutShell() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.arguments = ["-name", "a b; rm -rf ~"]
        game.graphics.forceDX11 = true
        game.graphics.metalHUD = true
        let cmd = try backend.launchCommand(for: game, prefix: makeInitializedPrefix(in: dir),
                                            runtime: makeFakeRuntime(in: dir), options: LaunchOptions(logLevel: .errors))
        #expect(cmd.executable.lastPathComponent == "wine")
        #expect(cmd.arguments == [game.executableURL.path, "-name", "a b; rm -rf ~", "-dx11"])
        #expect(cmd.workingDirectory == game.executableURL.deletingLastPathComponent())
        #expect(cmd.environment["WINEDEBUG"] == "-all,err+all")
        #expect(cmd.environment["MTL_HUD_ENABLED"] == "1")
        #expect(cmd.environment["WINE_D3D_CONFIG"] == "renderer=gl")
        #expect(cmd.environment["WINEPREFIX"]?.hasSuffix("/prefix") == true)
    }

    @Test func unsupportedOptionsAreNotApplied() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.graphics.syncMode = .msync          // not supported by Wine Devel
        game.graphics.advertiseAVX = true        // fake runtime is a script, not x86_64
        let cmd = try backend.launchCommand(for: game, prefix: makeInitializedPrefix(in: dir),
                                            runtime: makeFakeRuntime(in: dir), options: LaunchOptions())
        #expect(cmd.environment["WINEMSYNC"] == nil)
        #expect(cmd.environment["ROSETTA_ADVERTISE_AVX"] == nil)
    }

    @Test func unavailableGraphicsBackendIsRefused() {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.graphics.backend = .d3dMetal
        #expect(throws: AlloyError.self) {
            try backend.launchCommand(for: game, prefix: makeInitializedPrefix(in: dir),
                                      runtime: makeFakeRuntime(in: dir), options: LaunchOptions())
        }
    }

    @Test func dxvkRequiresInstalledDLLs() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.graphics.backend = .dxvk
        game.graphics.frameRateCap = .fixed(60)
        game.environment = ["WINEDLLOVERRIDES": "xinput1_3=n,b"]
        let prefix = makeInitializedPrefix(in: dir)
        let runtime = makeFakeRuntime(in: dir, moltenVK: true)
        #expect(throws: AlloyError.self) {
            try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        }
        dir.write("dxvk/x64/d3d11.dll", Data("new".utf8))
        dir.write("dxvk/x64/dxgi.dll", Data("new".utf8))
        dir.write("prefix/drive_c/windows/system32/d3d11.dll", Data("original".utf8))
        let manager = PrefixManager(storageRoot: dir.url.appendingPathComponent("store"), crossOverBottlesRoot: nil)
        try manager.installDXVK(from: dir.url.appendingPathComponent("dxvk"), into: prefix)
        let cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["WINEDLLOVERRIDES"] == "d3d11,d3d10core,dxgi=n,b;xinput1_3=n,b")
        #expect(cmd.environment["DXVK_FRAME_RATE"] == "60")

        try manager.uninstallDXVK(from: prefix)
        let restored = try String(contentsOf: prefix.system32.appendingPathComponent("d3d11.dll"), encoding: .utf8)
        #expect(restored == "original")
        #expect(!PrefixManager.hasDXVKInstalled(prefix))
    }

    /// The default cap is the display's refresh rate, through each graphics path's own limiter; D3DMetal is left to
    /// vsync at the display maximum because its limiter paces 120 FPS unevenly.
    @Test func frameRateCapUsesEachLimiter() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        let prefix = makeInitializedPrefix(in: dir)
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-windows/winemetal.dll", Data())
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-unix/winemetal.so", Data())
        let runtime = makeFakeRuntime(in: dir, moltenVK: true, d3dMetal: true)
        let at120 = LaunchOptions(displayRefreshRate: 120)
        #expect(game.graphics.frameRateCap == .displayMaximum)
        game.graphics.backend = .dxmt
        let dxmt = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120)
        #expect(dxmt.environment["DXMT_CONFIG"] == "d3d11.preferredMaxFrameRate=120")
        game.graphics.backend = .d3dMetal
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["D3DM_MAX_FPS"] == nil)
        game.graphics.frameRateCap = .fixed(60)
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["D3DM_MAX_FPS"] == "60")
        game.graphics.frameRateCap = .off
        game.graphics.backend = .dxmt
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["DXMT_CONFIG"] == nil)
        game.graphics.frameRateCap = .displayMaximum
        game.graphics.backend = .wined3dOpenGL
        let gl = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120)
        #expect(gl.environment["DXMT_CONFIG"] == nil && gl.environment["DXVK_FRAME_RATE"] == nil)
        #expect(FrameRateCap.displayMaximum.limit(displayRefreshRate: 120) == 120)
        #expect(FrameRateCap.off.limit(displayRefreshRate: 120) == nil)
        #expect(FrameRateCap.fixed(60).limit(displayRefreshRate: 120) == 60)
    }

    /// MetalFX upscaling turns on DXMT's MetalFX swapchain and shares DXMT_CONFIG with the frame cap.
    @Test func metalFXSpatialUpscalingOnlyOnDXMT() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        let prefix = makeInitializedPrefix(in: dir)
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-windows/winemetal.dll", Data())
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-unix/winemetal.so", Data())
        let runtime = makeFakeRuntime(in: dir, moltenVK: true, d3dMetal: true)
        let at120 = LaunchOptions(displayRefreshRate: 120)
        #expect(backend.capabilities(of: runtime).metalFXSpatialUpscaling == [.dxmt])
        #expect(backend.capabilities(of: makeFakeRuntime(in: TempDir())).metalFXSpatialUpscaling.isEmpty)
        game.graphics.backend = .dxmt
        var env = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment
        #expect(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == nil)
        game.graphics.metalFXSpatialFactor = 1.5
        env = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment
        #expect(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == "1")
        #expect(env["DXMT_CONFIG"] == "d3d11.preferredMaxFrameRate=120;d3d11.metalSpatialUpscaleFactor=1.5")
        game.graphics.frameRateCap = .off
        game.graphics.metalFXSpatialFactor = 2
        env = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment
        #expect(env["DXMT_CONFIG"] == "d3d11.metalSpatialUpscaleFactor=2")
        // Out-of-range factors and other graphics paths get nothing.
        game.graphics.metalFXSpatialFactor = 8
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["DXMT_CONFIG"] == nil)
        game.graphics.metalFXSpatialFactor = 2
        game.graphics.backend = .d3dMetal
        env = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment
        #expect(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == nil && env["DXMT_CONFIG"] == nil)

        let decode = { (json: String) in try JSONDecoder().decode(GraphicsConfiguration.self, from: Data(json.utf8)) }
        #expect(try decode("{}").metalFXSpatialFactor == nil)
        var g = GraphicsConfiguration(); g.metalFXSpatialFactor = 3
        #expect(try JSONDecoder().decode(GraphicsConfiguration.self, from: JSONEncoder().encode(g)).metalFXSpatialFactor == 3)
        #expect(MetalFXSpatialUpscaling.displayName(1.5) == "1.5×" && MetalFXSpatialUpscaling.displayName(2) == "2×")

        let warning = DiagnosticService.analyze(log: "warn:  MetalFX spatial scaler is not supported on this device")
        #expect(warning.contains { $0.title == "MetalFX upscaling is not active" })
    }

    /// The scroll speed reaches the engine only when its Mac driver reads it, and only when it isn't the standard 1×.
    @Test func scrollSpeedNeedsTheEngineOption() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        let prefix = makeInitializedPrefix(in: dir)
        let unix = "Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-unix/"
        #expect(game.scrollSpeedPercent == 100)

        dir.write(unix + "winemac.so", Data("....use_precise_scrolling....".utf8))
        var runtime = makeFakeRuntime(in: dir, moltenVK: true, d3dMetal: true)
        #expect(!runtime.hasScrollSpeedOption && !backend.capabilities(of: runtime).scrollSpeed)
        game.scrollSpeedPercent = 200
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions()).environment["ALLOY_SCROLL_SPEED_PERCENT"] == nil)

        dir.write(unix + "winemac.so", Data("....ALLOY_SCROLL_SPEED_PERCENT....".utf8))
        runtime = makeFakeRuntime(in: dir, moltenVK: true, d3dMetal: true)
        #expect(runtime.hasScrollSpeedOption && backend.capabilities(of: runtime).scrollSpeed)
        let speed = { try self.backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions()).environment["ALLOY_SCROLL_SPEED_PERCENT"] }
        #expect(try speed() == "200")
        game.scrollSpeedPercent = 100
        #expect(try speed() == nil)
        game.scrollSpeedPercent = 5000
        #expect(try speed() == nil)
        // A game's own variable wins, as for every other variable.
        game.scrollSpeedPercent = 150
        game.environment = ["ALLOY_SCROLL_SPEED_PERCENT": "300"]
        #expect(try speed() == "300")

        // Saved games from before the setting load at 1×; the setting survives a save.
        var saved = makeGame(in: dir); saved.scrollSpeedPercent = 75
        let json = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(Game.self, from: json).scrollSpeedPercent == 75)
        var old = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        old.removeValue(forKey: "scrollSpeedPercent")
        #expect(try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: old)).scrollSpeedPercent == 100)
        #expect(ScrollSpeed.label(150) == "1.5×" && ScrollSpeed.label(200) == "2×" && ScrollSpeed.label(75) == "0.75×")
    }

    /// 32-bit games get 4 GB when the engine's ntdll reads WINE_LARGE_ADDRESS_AWARE; 64-bit games never need it.
    @Test func largeAddressSpaceFor32BitGames() throws {
        let dir = TempDir()
        var game32 = makeGame(in: dir, exe: "Old.exe", data: PEFixture.make(machine: 0x14c, pe32Plus: false))
        let game64 = makeGame(in: dir)
        let prefix = makeInitializedPrefix(in: dir)
        let unix = "Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-unix/"
        #expect(game32.largeAddressSpace)
        let laa = { (game: Game, runtime: WineRuntime) in
            try self.backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions()).environment["WINE_LARGE_ADDRESS_AWARE"]
        }

        dir.write(unix + "ntdll.so", Data("....WINEMSYNC....".utf8))
        var runtime = makeFakeRuntime(in: dir, moltenVK: true)
        #expect(!runtime.hasLargeAddressOption && !backend.capabilities(of: runtime).largeAddressSpace)
        #expect(try laa(game32, runtime) == nil)

        dir.write(unix + "ntdll.so", Data("....WINEMSYNC....WINE_LARGE_ADDRESS_AWARE....".utf8))
        runtime = makeFakeRuntime(in: dir, moltenVK: true)
        #expect(runtime.hasLargeAddressOption && backend.capabilities(of: runtime).largeAddressSpace)
        #expect(try laa(game32, runtime) == "1")
        #expect(try laa(game64, runtime) == nil)
        game32.largeAddressSpace = false
        #expect(try laa(game32, runtime) == nil)

        // Saved games from before the setting load with it on; turning it off survives a save.
        let json = try JSONEncoder().encode(game32)
        #expect(try JSONDecoder().decode(Game.self, from: json).largeAddressSpace == false)
        var old = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        old.removeValue(forKey: "largeAddressSpace")
        #expect(try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: old)).largeAddressSpace)
    }

    /// Low input delay is on by default, but only on a DXMT whose d3d11 reads dxgi.maxFrameLatency.
    @Test func lowInputDelayNeedsTheEngineOption() throws {
        let dir = TempDir()
        var game = makeGame(in: dir)
        let prefix = makeInitializedPrefix(in: dir)
        let lib = "Wine Devel.app/Contents/Resources/wine/lib/wine/"
        dir.write(lib + "x86_64-windows/winemetal.dll", Data())
        dir.write(lib + "x86_64-unix/winemetal.so", Data())
        let at120 = LaunchOptions(displayRefreshRate: 120)
        game.graphics.backend = .dxmt
        #expect(game.graphics.lowInputDelay)

        // An engine without the option (DXMT 0.80 as released) gets nothing.
        dir.write(lib + "x86_64-windows/d3d11.dll", Data("MZ....d3d11.metalSpatialUpscaleFactor....".utf8))
        var runtime = makeFakeRuntime(in: dir, moltenVK: true, d3dMetal: true)
        #expect(!runtime.hasFrameLatencyOption && backend.capabilities(of: runtime).lowInputDelay.isEmpty)
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["DXMT_CONFIG"]
                == "d3d11.preferredMaxFrameRate=120")

        dir.write(lib + "x86_64-windows/d3d11.dll", Data("MZ....dxgi.maxFrameLatency....".utf8))
        runtime = makeFakeRuntime(in: dir, moltenVK: true, d3dMetal: true)
        #expect(runtime.hasFrameLatencyOption && backend.capabilities(of: runtime).lowInputDelay == [.dxmt])
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["DXMT_CONFIG"]
                == "d3d11.preferredMaxFrameRate=120;dxgi.maxFrameLatency=1")
        game.graphics.lowInputDelay = false
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["DXMT_CONFIG"]
                == "d3d11.preferredMaxFrameRate=120")
        // Other graphics paths never get it.
        game.graphics.lowInputDelay = true
        game.graphics.backend = .d3dMetal
        #expect(try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: at120).environment["DXMT_CONFIG"] == nil)

        // Games saved before the setting existed get it; turning it off is kept.
        let decode = { (json: String) in try JSONDecoder().decode(GraphicsConfiguration.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"backend":"dxmt"}"#).lowInputDelay)
        var g = GraphicsConfiguration(); g.lowInputDelay = false
        #expect(try !JSONDecoder().decode(GraphicsConfiguration.self, from: JSONEncoder().encode(g)).lowInputDelay)
    }

    /// Settings saved before the cap existed keep their DXVK limit; the rest get the display maximum.
    @Test func olderFrameLimitSettingsCarryOver() throws {
        let decode = { (json: String) in try JSONDecoder().decode(GraphicsConfiguration.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"backend":"dxvk","dxvkFrameRateLimit":90}"#).frameRateCap == .fixed(90))
        #expect(try decode(#"{"backend":"dxvk","dxvkFrameRateLimit":0}"#).frameRateCap == .displayMaximum)
        #expect(try decode(#"{"backend":"dxmt"}"#).frameRateCap == .displayMaximum)
        var g = GraphicsConfiguration(); g.frameRateCap = .off
        #expect(try JSONDecoder().decode(GraphicsConfiguration.self, from: JSONEncoder().encode(g)).frameRateCap == .off)
    }

    @Test func missingRuntimeBinaryIsReported() {
        let dir = TempDir()
        let runtime = WineRuntime(kind: .custom, wineBinary: dir.url.appendingPathComponent("nope/bin/wine"), root: dir.url)
        #expect(throws: AlloyError.self) {
            try backend.launchCommand(for: makeGame(in: dir), prefix: makeInitializedPrefix(in: dir), runtime: runtime, options: LaunchOptions())
        }
    }

    @Test func uninitialisedPrefixIsReported() {
        let dir = TempDir()
        let prefix = WinePrefix(name: "Empty", path: dir.url.appendingPathComponent("empty"))
        #expect(throws: AlloyError.prefixNotInitialized(name: "Empty")) {
            try backend.launchCommand(for: makeGame(in: dir), prefix: prefix, runtime: makeFakeRuntime(in: dir), options: LaunchOptions())
        }
    }
}

@Suite struct PrefixTests {
    @Test func createPersistAndTrash() throws {
        let dir = TempDir()
        let root = dir.url.appendingPathComponent("store")
        let manager = PrefixManager(storageRoot: root, crossOverBottlesRoot: nil)
        let prefix = try manager.createPrefix(name: "Space Game!", runtimeID: "/x/bin/wine")
        #expect(prefix.path.lastPathComponent.hasPrefix("space-game-"))
        #expect(prefix.architecture == "win64")
        #expect(!prefix.isInitialized())

        let reloaded = PrefixManager(storageRoot: root, crossOverBottlesRoot: nil)
        #expect(reloaded.ownPrefixes == [prefix])
        try reloaded.trashPrefix(id: prefix.id)
        #expect(reloaded.ownPrefixes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: prefix.path.path))
    }

    @Test func crossOverBottlesAreReadOnly() throws {
        let dir = TempDir()
        dir.write("Bottles/Steam/cxbottle.conf", Data("[Bottle]\n\"BottleID\" = \"6A9C0D3D-EAF8-49D8-A517-67C908FF6D23\"\n\"WineArch\" = \"win64\"\n".utf8))
        dir.write("Bottles/Steam/system.reg", Data())
        dir.write("Bottles/NotABottle/readme", Data())
        let manager = PrefixManager(storageRoot: dir.url.appendingPathComponent("store"),
                                    crossOverBottlesRoot: dir.url.appendingPathComponent("Bottles"))
        let bottles = manager.crossOverBottles()
        #expect(bottles.count == 1)
        let steam = try #require(bottles.first)
        #expect(steam.isReadOnly)
        #expect(steam.id.uuidString == "6A9C0D3D-EAF8-49D8-A517-67C908FF6D23")
        #expect(throws: AlloyError.prefixReadOnly(name: "Steam")) { try manager.trashPrefix(id: steam.id) }
        #expect(throws: AlloyError.prefixReadOnly(name: "Steam")) {
            try WineBackend().initializePrefixCommand(prefix: steam, runtime: makeFakeRuntime(in: dir))
        }
        #expect(throws: AlloyError.prefixReadOnly(name: "Steam")) {
            try manager.installDXVK(from: dir.url, into: steam)
        }
        #expect(FileManager.default.fileExists(atPath: steam.path.appendingPathComponent("cxbottle.conf").path))
    }

    @Test func initializeCommandUsesWineboot() throws {
        let dir = TempDir()
        let prefix = WinePrefix(name: "P", path: dir.url.appendingPathComponent("p"))
        let cmd = try WineBackend().initializePrefixCommand(prefix: prefix, runtime: makeFakeRuntime(in: dir))
        #expect(cmd.arguments == ["wineboot", "--init"])
        #expect(cmd.environment["WINEPREFIX"] == prefix.path.path)
        // Otherwise wineboot waits forever on the Wine Mono download prompt.
        #expect(cmd.environment["WINEDLLOVERRIDES"] == "mscoree,mshtml=")
        #expect(cmd.environment["WINEMSYNC"] == nil)
        var msync = makeFakeRuntime(in: dir); msync.hasMSync = true
        #expect(try WineBackend().initializePrefixCommand(prefix: prefix, runtime: msync).environment["WINEMSYNC"] == "1")
    }
}

@Suite struct GraphicsDefaultsTests {
    @Test func detectsDirect3DImportsCaseInsensitively() {
        let dir = TempDir()
        var data = PEFixture.make()
        data.append(Data("....KERNEL32.dll..D3D11.DLL..dxgi.dll".utf8))
        dir.write("G/Game.exe", data)
        var dx12 = PEFixture.make()
        dx12.append(Data("d3d12.dll".utf8))
        dir.write("G/Twelve.exe", dx12)
        #expect(DirectXUsage.detect(in: dir.url.appendingPathComponent("G/Game.exe")) == [.d3d11])
        #expect(DirectXUsage.detect(in: dir.url.appendingPathComponent("G/Twelve.exe")) == [.d3d12])
    }

    @Test func readsEngineDLLButIgnoresShaderCompiler() {
        let dir = TempDir()
        dir.write("G/bin/game.exe", PEFixture.make())
        dir.write("G/bin/Engine_x64.dll", Data("..d3d11.dll..".utf8))
        dir.write("G/bin/d3dcompiler_47.dll", Data("d3d12.dll d3d9.dll".utf8))
        let game = Game(name: "G", folder: dir.url.appendingPathComponent("G"), executableRelativePath: "bin/game.exe")
        #expect(DirectXUsage.detect(game: game) == [.d3d11])
    }

    @Test func findsUnrealShippingBinaryBehindLauncherStub() {
        let dir = TempDir()
        dir.write("G/Game.exe", PEFixture.make())
        var shipping = PEFixture.make()
        shipping.append(Data("d3d11.dll d3d12.dll".utf8))
        dir.write("G/Game/Binaries/Win64/Game-Win64-Shipping.exe", shipping)
        let game = Game(name: "G", folder: dir.url.appendingPathComponent("G"), executableRelativePath: "Game.exe")
        #expect(DirectXUsage.detect(game: game) == [.d3d11, .d3d12])
    }

    @Test func choosesDXMTForDX11AndD3DMetalForDX12() {
        let dir = TempDir()
        let plain = makeFakeRuntime(in: dir)
        var dxmt = plain; dxmt.hasDXMT = true
        dxmt.wineBinary = URL(fileURLWithPath: "/dxmt/bin/wine")
        var d3dm = plain; d3dm.hasD3DMetal = true
        d3dm.wineBinary = URL(fileURLWithPath: "/d3dm/bin/wine")
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let all = [plain, dxmt, d3dm]

        #expect(GraphicsDefaults.choose(usage: [.d3d11], machine: .x64, runtimes: all, preferredRuntime: nil, backend: backend).backend == .dxmt)
        let dx12 = GraphicsDefaults.choose(usage: [.d3d12], machine: .x64, runtimes: all, preferredRuntime: nil, backend: backend)
        #expect(dx12.backend == .d3dMetal && dx12.runtime == d3dm)
        // D3DMetal is 64-bit only.
        #expect(GraphicsDefaults.choose(usage: [.d3d12], machine: .x86, runtimes: all, preferredRuntime: plain, backend: backend).backend == .wined3dOpenGL)
        #expect(GraphicsDefaults.choose(usage: [.d3d9], machine: .x64, runtimes: all, preferredRuntime: plain, backend: backend).runtime == plain)
        // No D3DMetal, but MoltenVK: DirectX 12 runs through vkd3d rather than OpenGL.
        var mvk = plain; mvk.hasMoltenVK = true
        #expect(GraphicsDefaults.choose(usage: [.d3d12], machine: .x64, runtimes: [mvk], preferredRuntime: mvk, backend: backend).backend == .vkd3d)
        #expect(GraphicsDefaults.choose(usage: [.d3d9], machine: .x64, runtimes: [mvk], preferredRuntime: mvk, backend: backend).backend == .wined3dOpenGL)
        // No DXMT runtime: DX11 falls back to D3DMetal.
        #expect(GraphicsDefaults.choose(usage: [.d3d11], machine: .x64, runtimes: [plain, d3dm], preferredRuntime: nil, backend: backend).backend == .d3dMetal)
    }
}

@Suite struct RuntimeTrashTests {
    @Test func refusesUnmanagedAndInUseRuntimes() throws {
        let dir = TempDir()
        let backend = WineBackend(managedRuntimesDirectory: dir.url.appendingPathComponent("Runtimes"), versionProbe: { _ in nil })
        let outside = makeFakeRuntime(in: dir)
        #expect(throws: AlloyError.self) { try backend.trashManagedRuntime(outside, usedBy: []) }

        dir.write("Runtimes/r-1/wine/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        let managed = backend.makeRuntime(kind: .custom, binary: dir.url.appendingPathComponent("Runtimes/r-1/wine/bin/wine"),
                                          root: dir.url.appendingPathComponent("Runtimes/r-1/wine"))
        let user = WinePrefix(name: "Uses it", path: dir.url.appendingPathComponent("p"), runtimeID: managed.id)
        #expect(throws: AlloyError.self) { try backend.trashManagedRuntime(managed, usedBy: [user]) }
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("Runtimes/r-1").path))
    }
}
