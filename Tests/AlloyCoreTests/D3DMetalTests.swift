import Foundation
import Testing
@testable import AlloyCore

/// Uses a fake Toolkit layout (empty placeholder files); no Apple binaries are involved.
@Suite struct D3DMetalImporterTests {
    func makeRedist(in dir: TempDir, version: String = "3.0") {
        let fw = "Volume/Evaluation environment/redist/lib/external/D3DMetal.framework"
        dir.write("\(fw)/Versions/A/D3DMetal", Data("new-d3dmetal".utf8))
        let plist = try! PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
        dir.write("\(fw)/Versions/A/Resources/Info.plist", plist)
        dir.write("Volume/Evaluation environment/redist/lib/external/libd3dshared.dylib", Data("shared".utf8))
        dir.write("Volume/Evaluation environment/redist/lib/wine/x86_64-windows/d3d11.dll", Data("apple-d3d11".utf8))
    }

    @Test func locatesRedistributableInMountedVolume() throws {
        let dir = TempDir()
        makeRedist(in: dir)
        dir.write("Volume/README.pdf", Data())
        let redist = try #require(D3DMetalImporter.locate(in: dir.url.appendingPathComponent("Volume")))
        #expect(redist.lib.path.hasSuffix("redist/lib"))
        #expect(redist.version == "3.0")
    }

    @Test func missingSharedLibraryIsRejected() {
        let dir = TempDir()
        dir.write("V/redist/lib/external/D3DMetal.framework/D3DMetal", Data())
        #expect(D3DMetalImporter.locate(in: dir.url.appendingPathComponent("V")) == nil)
    }

    @Test func buildsManagedRuntimeWithoutTouchingSources() throws {
        let dir = TempDir()
        makeRedist(in: dir)
        let base = makeFakeRuntime(in: dir, kind: .gamePortingToolkit)
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal", Data("old".utf8))
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-windows/d3d11.dll", Data("wine-d3d11".utf8))
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-windows/kernel32.dll", Data("k32".utf8))
        let redist = try #require(D3DMetalImporter.locate(in: dir.url.appendingPathComponent("Volume")))
        let runtimes = dir.url.appendingPathComponent("Runtimes")

        let folder = try D3DMetalImporter.makeManagedRuntime(name: "GPTK 3.0", base: base, redist: redist, runtimesDirectory: runtimes)
        let lib = folder.appendingPathComponent("wine/lib")
        func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
        #expect(try read(lib.appendingPathComponent("external/D3DMetal.framework/Versions/A/D3DMetal")) == "new-d3dmetal")
        #expect(try read(lib.appendingPathComponent("wine/x86_64-windows/d3d11.dll")) == "apple-d3d11")
        #expect(try read(lib.appendingPathComponent("wine/x86_64-windows/kernel32.dll")) == "k32")
        // Original runtime is untouched.
        #expect(try read(base.root.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")) == "wine-d3d11")

        let backend = WineBackend(applicationDirectories: [], installRoots: [], managedRuntimesDirectory: runtimes,
                                  versionProbe: { _ in "7.7" })
        let found = try #require(backend.discoverRuntimes().first)
        #expect(found.hasD3DMetal)
        #expect(found.displayName == "Alloy · GPTK 3.0 · Wine 7.7")
        #expect(backend.capabilities(of: found).status(of: .d3dMetal) == .available)
        #expect(D3DMetalImporter.manifest(for: found)?.d3dMetalVersion == "3.0")
    }

    @Test func buildsDXMTRuntimeWithoutTouchingBase() throws {
        let dir = TempDir()
        let base = makeFakeRuntime(in: dir)
        dir.write("Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-windows/d3d11.dll", Data("wine-d3d11".utf8))
        dir.write("dl/v0.80/x86_64-unix/winemetal.so", Data("so".utf8))
        dir.write("dl/v0.80/x86_64-windows/d3d11.dll", Data("dxmt-d3d11".utf8))
        dir.write("dl/v0.80/x86_64-windows/winemetal.dll", Data("wm".utf8))
        let release = try #require(DXMTImporter.locate(in: dir.url.appendingPathComponent("dl")))
        #expect(release.version == "0.80")
        let runtimes = dir.url.appendingPathComponent("Runtimes")
        let folder = try DXMTImporter.makeManagedRuntime(name: "DXMT 0.80", base: base, release: release, source: "test",
                                                         runtimesDirectory: runtimes)
        let d3d11 = folder.appendingPathComponent("wine/lib/wine/x86_64-windows/d3d11.dll")
        #expect(try String(contentsOf: d3d11, encoding: .utf8) == "dxmt-d3d11")
        #expect(try String(contentsOf: base.root.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), encoding: .utf8) == "wine-d3d11")

        let backend = WineBackend(applicationDirectories: [], installRoots: [], managedRuntimesDirectory: runtimes,
                                  versionProbe: { _ in "11.20" })
        let found = try #require(backend.discoverRuntimes().first)
        #expect(found.hasDXMT && !found.hasD3DMetal && found.kind == .custom)
        #expect(backend.capabilities(of: found).status(of: .dxmt).isUsable)
        #expect(!WineBackend().capabilities(of: base).status(of: .dxmt).isUsable)

        dir.write("prefix/system.reg", Data("WINE REGISTRY Version 2\n".utf8))
        var game = makeGame(in: dir)
        game.graphics.backend = .dxmt
        game.graphics.shaderCachePath = "/tmp/cache"
        let cmd = try backend.launchCommand(for: game, prefix: WinePrefix(name: "P", path: dir.url.appendingPathComponent("prefix")),
                                            runtime: found, options: LaunchOptions())
        #expect(cmd.environment["DXMT_LOG_LEVEL"] == "info")
        #expect(cmd.environment["DXMT_SHADER_CACHE_PATH"] == "/tmp/cache")
        #expect(GraphicsVerifier.verify(backend: .dxmt, log: "info:  Maximum supported feature level: D3D_FEATURE_LEVEL_11_1")?.kind == .graphicsBackendConfirmed)
        #expect(GraphicsVerifier.verify(backend: .dxmt, log: "info:  D3D11InternalCreateDevice: Maximum supported feature level: X")?.kind == .graphicsBackendNotConfirmed)
    }

    @Test func importsPlainWineBuildAsCustomRuntime() throws {
        let dir = TempDir()
        dir.write("build/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        let runtimes = dir.url.appendingPathComponent("Runtimes")
        try WineBuildImporter.importBuild(root: dir.url.appendingPathComponent("build"), name: "CrossOver 26.3 source build",
                                          source: "test", runtimesDirectory: runtimes)
        let backend = WineBackend(applicationDirectories: [], installRoots: [], managedRuntimesDirectory: runtimes,
                                  versionProbe: { _ in "11.0" })
        let found = try #require(backend.discoverRuntimes().first)
        #expect(found.kind == .custom)
        #expect(found.displayName == "Alloy · CrossOver 26.3 source build · Wine 11.0")
        #expect(D3DMetalImporter.isLayerableBase(found) && D3DMetalImporter.isPlainManagedBuild(found))
        #expect(throws: AlloyError.self) {
            try WineBuildImporter.importBuild(root: dir.url.appendingPathComponent("nope"), name: "x", source: "t", runtimesDirectory: runtimes)
        }
    }

    @Test func knownBadD3DMetalWineCombinationIsRefused() {
        let base = WineRuntime(kind: .gamePortingToolkit, wineBinary: URL(fileURLWithPath: "/x/bin/wine64"),
                               root: URL(fileURLWithPath: "/x"), version: "7.7 (Game Porting Toolkit 1.1)")
        let redist = D3DMetalRedistributable(lib: URL(fileURLWithPath: "/v/redist/lib"), version: "4.0b3")
        #expect(D3DMetalImporter.incompatibility(base: base, redist: redist) != nil)
        #expect(D3DMetalImporter.incompatibility(base: base, redist: D3DMetalRedistributable(lib: redist.lib, version: "3.0")) == nil)
        #expect(throws: AlloyError.self) {
            try D3DMetalImporter.makeManagedRuntime(name: "x", base: base, redist: redist,
                                                    runtimesDirectory: TempDir().url.appendingPathComponent("R"))
        }
    }

    @Test func thirtyTwoBitProgramsAreRefusedOnD3DMetalAndGPTK() {
        let dir = TempDir()
        var game = makeGame(in: dir, data: PEFixture.make(machine: 0x014c, pe32Plus: false))
        game.graphics.backend = .d3dMetal
        let gptk = makeFakeRuntime(in: dir, d3dMetal: true, kind: .gamePortingToolkit)
        #expect(throws: AlloyError.self) {
            try WineBackend().launchCommand(for: game, prefix: makeInitializedPrefix(in: dir), runtime: gptk, options: LaunchOptions())
        }
    }

    @Test func prefixCannotSwitchRuntime() throws {
        let dir = TempDir()
        var prefix = makeInitializedPrefix(in: dir)
        prefix.runtimeID = "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine"
        let runtime = makeFakeRuntime(in: dir)
        #expect(throws: AlloyError.self) {
            try WineBackend().launchCommand(for: makeGame(in: dir), prefix: prefix, runtime: runtime, options: LaunchOptions())
        }
    }
}
