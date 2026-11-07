import Foundation
import Testing
@testable import AlloyCore

@Suite struct RuntimeInstallerTests {
    /// Packs `folder` (relative to `dir`) the way scripts/package-runtime.sh does.
    func pack(_ folders: [String], in dir: TempDir, name: String = "pkg.tar.xz") throws -> URL {
        let archive = dir.url.appendingPathComponent(name)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-C", dir.url.appendingPathComponent("src").path, "-cJf", archive.path] + folders
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)
        return archive
    }

    func fakeRuntime(_ name: String, in dir: TempDir) {
        dir.write("src/\(name)/wine/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("src/\(name)/alloy-runtime.json", Data(#"{"name":"Test","translationLayer":"dxmt"}"#.utf8))
    }

    @Test func installsAVerifiedPackageAndRecordsIt() async throws {
        let dir = TempDir()
        fakeRuntime("alloy-test-1", in: dir)
        let archive = try pack(["alloy-test-1"], in: dir)
        let sha = try #require(RuntimeInstaller.sha256(of: archive))
        let runtimes = dir.url.appendingPathComponent("Runtimes")
        let package = RuntimePackage(id: "test-1", name: "Test Engine", version: "1", url: archive, sha256: sha,
                                     downloadBytes: 1, installedBytes: 1)
        let folder = try await RuntimeInstaller.install(package, into: runtimes, downloads: dir.url.appendingPathComponent("dl")) { _, _ in }
        #expect(folder.lastPathComponent == "alloy-test-1")
        #expect(FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent("wine/bin/wine").path))
        #expect(RuntimeInstaller.installedMarkers(in: runtimes)["test-1"]?.sha256 == sha)
        // No staging folders are left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: runtimes.path).filter { $0.hasPrefix(".staging") }.isEmpty)
    }

    @Test func rejectsAWrongChecksum() async throws {
        let dir = TempDir()
        fakeRuntime("alloy-test-1", in: dir)
        let archive = try pack(["alloy-test-1"], in: dir)
        let package = RuntimePackage(id: "test-1", name: "Test Engine", version: "1", url: archive,
                                     sha256: String(repeating: "0", count: 64), downloadBytes: 1, installedBytes: 1)
        let runtimes = dir.url.appendingPathComponent("Runtimes")
        await #expect(throws: AlloyError.self) {
            try await RuntimeInstaller.install(package, into: runtimes, downloads: dir.url.appendingPathComponent("dl")) { _, _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: runtimes.appendingPathComponent("alloy-test-1").path))
    }

    @Test func rejectsPackagesThatAreNotOneRuntime() throws {
        let dir = TempDir()
        fakeRuntime("a", in: dir)
        fakeRuntime("b", in: dir)
        let two = try pack(["a", "b"], in: dir, name: "two.tar.xz")
        #expect(throws: AlloyError.self) { try RuntimeInstaller.unpack(archive: two, into: dir.url.appendingPathComponent("R")) }
        dir.write("src/empty/readme.txt", Data("hi".utf8))
        let empty = try pack(["empty"], in: dir, name: "empty.tar.xz")
        #expect(throws: AlloyError.self) { try RuntimeInstaller.unpack(archive: empty, into: dir.url.appendingPathComponent("R")) }
    }

    @Test func rejectsLinksPointingOutside() throws {
        let dir = TempDir()
        fakeRuntime("evil", in: dir)
        try FileManager.default.createSymbolicLink(atPath: dir.url.appendingPathComponent("src/evil/wine/escape").path,
                                                   withDestinationPath: "../../../../outside")
        try FileManager.default.createSymbolicLink(atPath: dir.url.appendingPathComponent("src/evil/wine/ok").path,
                                                   withDestinationPath: "bin/wine")
        let archive = try pack(["evil"], in: dir)
        let runtimes = dir.url.appendingPathComponent("R")
        #expect(throws: AlloyError.self) { try RuntimeInstaller.unpack(archive: archive, into: runtimes) }
        #expect(!FileManager.default.fileExists(atPath: runtimes.appendingPathComponent("evil").path))
    }

    /// The manifest scripts/package-runtime.sh writes has no build-machine paths; it must still read as a DXMT runtime,
    /// or the engine is taken for a D3DMetal build (which refuses 32-bit games).
    @Test func packagedRuntimeIsDiscoveredAsDXMT() throws {
        let dir = TempDir()
        dir.write("Runtimes/alloy-x/wine/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("Runtimes/alloy-x/alloy-runtime.json", Data(#"""
            {"baseRuntimeVersion":"11.0","createdAt":815228728.17,"d3dMetalSource":"https://github.com/3Shain/dxmt/releases/tag/v0.80",
             "name":"Alloy Game Engine","translationLayer":"dxmt"}
            """#.utf8))
        let backend = WineBackend(managedRuntimesDirectory: dir.url.appendingPathComponent("Runtimes"), versionProbe: { _ in nil })
        let runtime = try #require(backend.discoverRuntimes().first { $0.root.path.contains("alloy-x") })
        #expect(runtime.kind == .custom)
        #expect(runtime.displayName.contains("Alloy Game Engine"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.appendingPathComponent("Runtimes/alloy-x").path)
            .filter { $0.contains("corrupt") }.isEmpty)
    }

    @Test func manifestAndSources() throws {
        let json = #"{"formatVersion":1,"runtimes":[{"id":"x","name":"X","version":"1","url":"alloy-x.tar.xz","sha256":"ab","downloadBytes":5,"installedBytes":9}]}"#
        let manifest = try JSONDecoder().decode(ComponentManifest.self, from: Data(json.utf8))
            .resolved(against: URL(string: "https://example.com/releases/v1/components.json")!)
        #expect(manifest.runtimes.first?.url.absoluteString == "https://example.com/releases/v1/alloy-x.tar.xz")
        #expect(RuntimeInstaller.isAllowedSource(URL(string: "https://example.com/a")!))
        #expect(RuntimeInstaller.isAllowedSource(URL(string: "http://127.0.0.1:8765/components.json")!))
        #expect(!RuntimeInstaller.isAllowedSource(URL(string: "http://example.com/a")!))
        #expect(!RuntimeInstaller.isAllowedSource(URL(string: "ftp://example.com/a")!))
        #expect(RuntimeInstaller.megabytes(292_000_000) == "292 MB" && RuntimeInstaller.megabytes(1_545_000_000) == "1.5 GB")
    }
}

@Suite struct WindowsComponentTests {
    /// appwiz.cpl keeps the Mono file name as UTF-16 and the checksums as C strings.
    @Test func readsWineMonoExpectationFromAppwiz() {
        var bytes: [UInt8] = Array(repeating: 0x41, count: 40)
        bytes += Array("wine-mono-10.4.1-x86.msi".utf8).flatMap { [$0, UInt8(0)] } + [0, 0]
        let mono = "071f4b2887e1c97a11d791ff3d65be9429eed6dec4c2708888bfd546ba358e23"
        bytes += Array(mono.utf8) + [0] + Array("not-a-checksum".utf8) + [0]
        bytes += Array(String(repeating: "a", count: 65).utf8) + [0]  // too long: not a SHA-256
        let e = WineMono.expectation(fromAppwiz: Data(bytes))
        #expect(e?.version == "10.4.1")
        #expect(e?.fileName == "wine-mono-10.4.1-x86.msi")
        #expect(e?.checksums == [mono])
        #expect(e?.downloadURL.absoluteString == "https://dl.winehq.org/wine/wine-mono/10.4.1/wine-mono-10.4.1-x86.msi")
        #expect(WineMono.expectation(fromAppwiz: Data("nothing here".utf8)) == nil)
    }

    @Test func detectsVisualCppAndDotNetFromImports() {
        let dir = TempDir()
        var exe = PEFixture.make()
        exe.append(Data("....KERNEL32.dll..VCRUNTIME140.dll..MSCOREE.DLL..".utf8))
        let game = makeGame(in: dir, data: exe)
        let traits = GameTraits.inspect(game)
        #expect(traits.importsVisualCpp && traits.isDotNet)
        #expect(WindowsComponent.needed(by: traits) == [.visualCpp, .dotNet])
        // A game that ships its own vcruntime140.dll next to the program does not need the installer.
        dir.write("Game/vcruntime140.dll", Data())
        #expect(!GameTraits.inspect(game).importsVisualCpp)
        let plain = makeGame(in: TempDir())
        #expect(WindowsComponent.needed(by: GameTraits.inspect(plain)).isEmpty)
    }
}

@Suite struct PlayModeTests {
    @Test func modesMapToSettingsAndBack() {
        var g = GraphicsConfiguration(backend: .dxmt)
        #expect(PlayMode.current(of: g) == .balanced)
        for mode in PlayMode.allCases {
            mode.apply(to: &g)
            #expect(PlayMode.current(of: g) == mode)
        }
        // Sharp turns MetalFX scaling off so frames aren't upscaled twice; the other modes turn it back on.
        PlayMode.sharp.apply(to: &g)
        #expect(g.metalFXSpatialFactor == 2 && g.frameRateCap == .displayMaximum && !g.dlss)
        PlayMode.batterySaver.apply(to: &g)
        #expect(g.frameRateCap == .fixed(60) && g.metalFXSpatialFactor == nil && g.dlss)
        PlayMode.balanced.apply(to: &g)
        #expect(g.dlss)
        g.frameRateCap = .fixed(90)
        #expect(PlayMode.current(of: g) == nil)
    }

    @Test func onlyModesThePathSupports() {
        let dxmt = BackendCapabilities(graphics: [:], syncModes: [.default], supportsMetalHUD: true, supportsAVXAdvertisement: false,
                                       notes: [], metalFXSpatialUpscaling: [.dxmt])
        #expect(PlayMode.available(for: .dxmt, capabilities: dxmt, displayRefreshRate: 120) == [.batterySaver, .balanced, .sharp])
        #expect(PlayMode.available(for: .d3dMetal, capabilities: dxmt, displayRefreshRate: 120) == [.batterySaver, .balanced])
        #expect(PlayMode.available(for: .wined3dOpenGL, capabilities: dxmt, displayRefreshRate: 120) == [.balanced])
        // On a 60 Hz display Battery Saver's 60 FPS limit is the same as Balanced.
        #expect(PlayMode.available(for: .dxmt, capabilities: dxmt, displayRefreshRate: 60) == [.balanced, .sharp])
        #expect(GraphicsBackendKind.wined3dOpenGL.isCompatibilityMode && !GraphicsBackendKind.dxmt.isCompatibilityMode)
    }

    @Test func newSettingsDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.autoInstallComponents && s.componentsURLOverride == nil)
    }
}

@Suite struct GameInstallerTests {
    @Test func findsTheInstallFolder() {
        let added: Set<String> = ["Program Files/Cool Game/CoolGame.exe", "Program Files/Cool Game/unins000.exe",
                                  "Program Files/Cool Game/bin/helper.exe", "Program Files (x86)/Common/redist/vc_redist.x64.exe"]
        #expect(GameInstaller.installFolder(newExecutables: added) == "Program Files/Cool Game")
        #expect(GameInstaller.installFolder(newExecutables: ["Games/Thing/thing.exe"]) == "Games/Thing")
        #expect(GameInstaller.installFolder(newExecutables: ["MyGame/run.exe"]) == "MyGame")
        #expect(GameInstaller.installFolder(newExecutables: []) == nil)
    }

    @Test func installedGameAndHelpers() {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        let drive = "prefix/drive_c"
        dir.write("\(drive)/Program Files/Cool Game/CoolGame.exe", PEFixture.make())
        dir.write("\(drive)/Program Files/Cool Game/unins000.exe", PEFixture.make(machine: 0x14c, pe32Plus: false))
        let found = GameInstaller.executables(in: prefix)
        #expect(found.contains("Program Files/Cool Game/CoolGame.exe"))
        let game = GameInstaller.installedGame(name: "Cool Game", newExecutables: found, prefix: prefix)
        #expect(game?.executableRelativePath == "CoolGame.exe" && game?.prefixID == prefix.id)
        #expect(GameInstaller.suggestedName(for: URL(fileURLWithPath: "/x/setup_cool_game_1.2.3.exe")) == "Cool Game")
        #expect(GameInstaller.windowsPath(for: URL(fileURLWithPath: "/Users/a/Setup.msi")) == #"Z:\Users\a\Setup.msi"#)
    }
}
