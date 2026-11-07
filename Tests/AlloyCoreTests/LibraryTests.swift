import Foundation
import Testing
@testable import AlloyCore

@Suite struct LibraryTests {
    @Test func persistsGamesAcrossInstances() throws {
        let dir = TempDir()
        let file = dir.url.appendingPathComponent("library.json")
        var game = makeGame(in: dir)
        game.arguments = ["-dx11", "--window name"]
        game.environment = ["DXVK_HUD": "fps"]
        game.graphics.targetFPS = 120
        try GameLibrary(fileURL: file).add(game)

        let reloaded = GameLibrary(fileURL: file)
        #expect(reloaded.games.count == 1)
        #expect(reloaded.games.first == game)
        #expect(reloaded.games.first?.graphics.frameBudgetMilliseconds ?? 0 > 8.3)
    }

    @Test func addUpdateRemove() throws {
        let dir = TempDir()
        let library = GameLibrary(fileURL: dir.url.appendingPathComponent("library.json"))
        var game = makeGame(in: dir)
        try library.add(game)
        game.name = "Renamed"
        try library.update(game)
        #expect(library.game(id: game.id)?.name == "Renamed")
        try library.remove(id: game.id)
        #expect(library.games.isEmpty)
    }

    @Test func removingAGameKeepsItsFiles() throws {
        let dir = TempDir()
        let library = GameLibrary(fileURL: dir.url.appendingPathComponent("library.json"))
        let game = makeGame(in: dir)
        try library.add(game)
        try library.remove(id: game.id)
        #expect(FileManager.default.fileExists(atPath: game.executableURL.path))
    }

    @Test func corruptLibraryIsBackedUpNotLost() throws {
        let dir = TempDir()
        let file = dir.write("library.json", Data("{not json".utf8))
        let library = GameLibrary(fileURL: file)
        #expect(library.games.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).filter { $0.contains("corrupt") }
        #expect(backups.count == 1)
        // Reading the same broken file again does not add more copies.
        _ = GameLibrary(fileURL: file)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.path).filter { $0.contains("corrupt") }.count == 1)
    }

    @Test func decodesOlderEntriesWithMissingFields() throws {
        let json = #"{"version":1,"games":[{"id":"6A9C0D3D-EAF8-49D8-A517-67C908FF6D23","name":"Old","folder":"file:///tmp/x/","executableRelativePath":"a.exe"}]}"#
        let dir = TempDir()
        let library = GameLibrary(fileURL: dir.write("library.json", Data(json.utf8)))
        #expect(library.games.first?.graphics.preset == .balanced)
        #expect(library.games.first?.arguments == [])
    }
}

@Suite struct ExecutableTests {
    @Test func validExecutablePasses() throws {
        let dir = TempDir()
        let info = try ExecutableValidator.validate(makeGame(in: dir))
        #expect(info.machine == .x64)
        #expect(info.subsystem == .gui)
    }

    @Test func missingExecutableIsReported() {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.executableRelativePath = "Missing.exe"
        #expect(throws: AlloyError.executableNotFound(path: game.executableURL.resolvingSymlinksInPath().path)) {
            try ExecutableValidator.validate(game)
        }
    }

    @Test func pathTraversalOutsideFolderIsRejected() {
        let dir = TempDir()
        dir.write("Other.exe", PEFixture.make())
        var game = makeGame(in: dir)
        game.executableRelativePath = "../Other.exe"
        #expect(throws: AlloyError.executableOutsideGameFolder(path: "../Other.exe")) {
            try ExecutableValidator.validate(game)
        }
    }

    @Test func nonPEFileIsRejected() {
        let dir = TempDir()
        let game = makeGame(in: dir, exe: "fake.exe", data: Data("#!/bin/sh\necho hi".utf8))
        #expect(throws: AlloyError.notAWindowsExecutable(path: "fake.exe")) { try ExecutableValidator.validate(game) }
    }

    @Test func arm64PEIsUnsupported() {
        let dir = TempDir()
        let game = makeGame(in: dir, data: PEFixture.make(machine: 0xaa64))
        #expect(throws: AlloyError.unsupportedExecutableArchitecture("ARM64")) { try ExecutableValidator.validate(game) }
    }

    @Test func dllIsNotLaunchable() {
        let dir = TempDir()
        let game = makeGame(in: dir, exe: "x.exe", data: PEFixture.make(dll: true))
        #expect(throws: AlloyError.self) { try ExecutableValidator.validate(game) }
    }

    @Test func peInspectorReads32Bit() {
        let info = PEInspector.inspect(data: PEFixture.make(machine: 0x014c, pe32Plus: false, subsystem: 3))
        #expect(info == PEInfo(machine: .x86, is64BitImage: false, isDLL: false, subsystem: .console))
    }

    @Test func machOArchitectures() {
        #expect(MachOInspector.inspect(data: MachOFixture.thin(cpu: 0x0100_0007)) == .machO([.x86_64]))
        #expect(MachOInspector.inspect(data: MachOFixture.fat(cpus: [0x0100_0007, 0x0100_000C])) == .machO([.x86_64, .arm64]))
        #expect(MachOInspector.inspect(data: Data("#!/bin/sh\n".utf8)) == .script)
    }

    @Test func scannerRanksMainExecutableAndIgnoresRedistributables() {
        let dir = TempDir()
        dir.write("G/Space_Game.exe", PEFixture.make())
        dir.write("G/SpaceGame/Binaries/Win64/SpaceGame-Win64-Shipping.exe", PEFixture.make())
        dir.write("G/_CommonRedist/vc_redist.x64.exe", PEFixture.make())
        dir.write("G/Engine/Binaries/Win64/CrashReportClient.exe", PEFixture.make())
        dir.write("G/readme.txt", Data())
        let results = ExecutableScanner.scan(folder: dir.url.appendingPathComponent("G"))
        #expect(results.first?.relativePath == "Space_Game.exe")
        #expect(results.count == 4)
        #expect(results.last.map { $0.score < 0 } == true)
    }

    @Test func fingerprintChangesWhenFileChanges() throws {
        let dir = TempDir()
        let file = dir.write("a.exe", PEFixture.make())
        let before = ExecutableValidator.fingerprint(of: file)
        try Data(count: 10).write(to: file)
        #expect(before != nil)
        #expect(before != ExecutableValidator.fingerprint(of: file))
    }
}

@Suite struct ArgumentTests {
    @Test(arguments: [
        ("-dx11 -windowed", ["-dx11", "-windowed"]),
        (#"--name "My Save" -x"#, ["--name", "My Save", "-x"]),
        (#"'single quoted' a\ b"#, ["single quoted", "a b"]),
        (#"--empty "" end"#, ["--empty", "", "end"]),
        ("   ", []),
        ("; rm -rf ~", [";", "rm", "-rf", "~"]),
    ])
    func splitting(input: String, expected: [String]) {
        #expect(ArgumentParser.split(input) == expected)
    }

    @Test func joinRoundTrips() {
        let args = ["-dx11", "with space", #"quote"inside"#, "", #"back\slash"#]
        #expect(ArgumentParser.split(ArgumentParser.join(args)) == args)
    }

    @Test func environmentValidation() throws {
        try EnvironmentValidator.validate(["DXVK_HUD": "fps", "MY_VAR2": "x"])
        #expect(throws: AlloyError.blockedEnvironmentKey("DYLD_INSERT_LIBRARIES")) {
            try EnvironmentValidator.validate(["DYLD_INSERT_LIBRARIES": "/tmp/x.dylib"])
        }
        #expect(throws: AlloyError.invalidEnvironmentKey("BAD-KEY")) { try EnvironmentValidator.validate(["BAD-KEY": "1"]) }
        #expect(throws: AlloyError.blockedEnvironmentKey("WINEPREFIX")) { try EnvironmentValidator.validate(["WINEPREFIX": "/"]) }
    }
}

@Suite struct ArtworkTests {
    @Test func prefersCoverOverIcon() {
        let dir = TempDir()
        dir.write("G/icon.png", Data())
        dir.write("G/Art/cover_art.jpg", Data())
        dir.write("G/notes.txt", Data())
        #expect(ArtworkFinder.find(in: dir.url.appendingPathComponent("G"))?.lastPathComponent == "cover_art.jpg")
    }

    @Test func noArtworkReturnsNil() {
        let dir = TempDir()
        dir.write("G/game.exe", PEFixture.make())
        #expect(ArtworkFinder.find(in: dir.url.appendingPathComponent("G")) == nil)
    }
}

@Suite struct DataMigrationTests {
    @Test func movesLegacyFolderAndRewritesSavedPaths() throws {
        let dir = TempDir()
        let support = dir.url
        let base = support.path.replacingOccurrences(of: "/", with: "\\/")
        let urlBase = "file:\\/\\/" + base.replacingOccurrences(of: " ", with: "%20")
        dir.write("WildRun/prefixes.json", Data("""
        [{"architecture":"win64","createdAt":0,"id":"EFBC6EEB-8616-4C78-A958-3F41EF5452B3","name":"P","origin" : "wildrun",
          "path":"\(urlBase)\\/WildRun\\/Prefixes\\/p","runtimeID":"\(base)\\/WildRun\\/Runtimes\\/r\\/wine\\/bin\\/wine"}]
        """.utf8))
        dir.write("WildRun/Runtimes/r/wildrun-runtime.json", Data("{}".utf8))
        dir.write("WildRun/Prefixes/p/.wildrun-dxvk", Data())
        dir.write("Unrelated/keep.txt", Data("x".utf8))

        let result = try DataMigration.migrateIfNeeded(applicationSupport: support)
        #expect(result.moved && result.rewrittenFiles == 1)
        let current = support.appendingPathComponent("Alloy")
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("WildRun").path))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("Runtimes/r/alloy-runtime.json").path))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("Prefixes/p/.alloy-dxvk").path))
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Unrelated/keep.txt").path))

        let saved = try String(contentsOf: current.appendingPathComponent("prefixes.json"), encoding: .utf8)
        #expect(!saved.contains("WildRun") && !saved.contains("wildrun"))
        let prefixes = try JSONDecoder().decode([WinePrefix].self, from: Data(saved.utf8))
        #expect(prefixes.first?.origin == .alloy)
        #expect(prefixes.first?.runtimeID?.contains("/Alloy/Runtimes/r/") == true)

        // Runs once: a second call changes nothing.
        #expect(try DataMigration.migrateIfNeeded(applicationSupport: support) == .init(moved: false, rewrittenFiles: 0))
    }

    /// Data from the Metalgate name moves too, with its runtime files, backups and markers.
    @Test func movesMetalgateFolder() throws {
        let dir = TempDir()
        let support = dir.url
        let base = support.path.replacingOccurrences(of: "/", with: "\\/")
        dir.write("Metalgate/library.json", Data("""
        [{"folder":"\(base)\\/Metalgate\\/Prefixes\\/p\\/drive_c\\/Game","name":"G"}]
        """.utf8))
        dir.write("Metalgate/prefixes.json", Data(#"[{"origin" : "metalgate"}]"#.utf8))
        dir.write("Metalgate/Runtimes/r/metalgate-runtime.json", Data("{}".utf8))
        dir.write("Metalgate/Runtimes/r/metalgate-package.json", Data("{}".utf8))
        dir.write("Metalgate/Runtimes/r/metalgate-backup/lib/x.dll", Data())
        dir.write("Metalgate/Prefixes/p/.metalgate-dxvk", Data())
        dir.write("Metalgate/Prefixes/p/metalgate-backup/dxvk/d3d11.dll", Data())
        dir.write("WildRun/settings.json", Data("{}".utf8))  // older still: left alone once Metalgate's data has moved

        let result = try DataMigration.migrateIfNeeded(applicationSupport: support)
        #expect(result.moved && result.rewrittenFiles == 2)
        let current = support.appendingPathComponent("Alloy")
        for path in ["Runtimes/r/alloy-runtime.json", "Runtimes/r/alloy-package.json", "Runtimes/r/alloy-backup/lib/x.dll",
                     "Prefixes/p/.alloy-dxvk", "Prefixes/p/alloy-backup/dxvk/d3d11.dll"] {
            #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent(path).path), "\(path)")
        }
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Metalgate").path))
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("WildRun/settings.json").path))
        let library = try String(contentsOf: current.appendingPathComponent("library.json"), encoding: .utf8)
        #expect(library.contains("\\/Alloy\\/Prefixes") && !library.contains("Metalgate"))
        #expect(try String(contentsOf: current.appendingPathComponent("prefixes.json"), encoding: .utf8).contains(#""alloy""#))
    }

    @Test func decodesLegacyOrigin() throws {
        #expect(try JSONDecoder().decode(PrefixOrigin.self, from: Data("\"wildrun\"".utf8)) == .alloy)
        #expect(try JSONDecoder().decode(PrefixOrigin.self, from: Data("\"metalgate\"".utf8)) == .alloy)
    }
}

@Suite struct SteamInstallerTests {
    @Test func findsSteamAndBuildsEntries() throws {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        #expect(SteamInstaller.steamExecutable(in: prefix) == nil)
        dir.write("prefix/drive_c/Program Files (x86)/Steam/steam.exe", PEFixture.make())
        let steam = try #require(SteamInstaller.steamExecutable(in: prefix))
        let entry = SteamInstaller.libraryEntry(steam: steam, prefix: prefix, graphics: GraphicsConfiguration(backend: .dxmt))
        #expect(entry.executableURL == steam && entry.prefixID == prefix.id && entry.graphics.backend == .dxmt)
        #expect(entry.arguments.isEmpty)
        #expect(SteamInstaller.isSteamClient(entry))

        let root = dir.url.appendingPathComponent("rt")
        let bare = WineRuntime(kind: .custom, wineBinary: root.appendingPathComponent("bin/wine"), root: root)
        #expect(SteamInstaller.missingRequirements(in: bare).count == 2)
        let fixed = WineRuntime(kind: .custom, wineBinary: root.appendingPathComponent("bin/wine"), root: root,
                                hasSteamWebHelperFix: true, hasGnuTLS: true)
        #expect(SteamInstaller.missingRequirements(in: fixed).isEmpty)
        let steamGame = Game(name: "Steam", folder: steam.deletingLastPathComponent(), executableRelativePath: "steam.exe",
                             prefixID: prefix.id)
        let warnings = DiagnosticService.preflight(game: steamGame, runtime: bare, prefix: prefix).filter { $0.kind == .runtimeLimitation }
        #expect(warnings.count == 2)
        #expect(DiagnosticService.preflight(game: steamGame, runtime: fixed, prefix: prefix).allSatisfy { $0.kind != .runtimeLimitation })

        let setup = SteamInstaller.installerGame(installer: dir.url.appendingPathComponent("dl/SteamSetup.exe"), prefix: prefix,
                                                 graphics: GraphicsConfiguration())
        #expect(setup.arguments == ["/S"] && setup.executableRelativePath == "SteamSetup.exe")
        #expect(SteamInstaller.installerURL.host == "cdn.fastly.steamstatic.com" && SteamInstaller.installerURL.scheme == "https")
    }

    /// The web helper fix is found as the wide string kernelbase matches on; GnuTLS by bcrypt naming the library.
    @Test func detectsWhatSteamNeedsInARuntime() {
        func runtime(patched: Bool) -> WineRuntime {
            let dir = TempDir(), base = "rt/wine"
            dir.write("\(base)/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
            let name = patched ? Data("x\0s\0t\0e\0a\0m\0w\0e\0b\0h\0e\0l\0p\0e\0r\0.\0e\0x\0e\0".utf8) : Data("steamwebhelper.exe".utf8)
            dir.write("\(base)/lib/wine/x86_64-windows/kernelbase.dll", name)
            dir.write("\(base)/lib/wine/x86_64-unix/bcrypt.so", Data((patched ? "libgnutls.30.dylib" : "no tls").utf8))
            let root = dir.url.appendingPathComponent(base)
            return WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in "11.0" })
                .makeRuntime(kind: .custom, binary: root.appendingPathComponent("bin/wine"), root: root)
        }
        let fixed = runtime(patched: true), plain = runtime(patched: false)
        #expect(fixed.hasSteamWebHelperFix && fixed.hasGnuTLS)
        #expect(!plain.hasSteamWebHelperFix && !plain.hasGnuTLS)
    }
}

@Suite struct VisualCppRuntimeTests {
    @Test func wineBuiltinDLLsAreNotMicrosofts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let builtin = dir.appendingPathComponent("builtin.dll"), native = dir.appendingPathComponent("native.dll")
        try (Data("MZ".utf8) + Data(count: 0x3e) + Data("Wine builtin DLL".utf8) + Data(count: 16)).write(to: builtin)
        try (Data("MZ".utf8) + Data(count: 0x60)).write(to: native)
        #expect(VisualCppRuntime.isWineBuiltin(builtin))
        #expect(!VisualCppRuntime.isWineBuiltin(native))
    }

    static let registry = #"""
    [Software\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64] 1793475999
    #time=1dd69708be0e946
    "Bld"=dword:0000898b
    "Installed"=dword:00000001
    "Version"="v14.44.35211.00"

    [Software\\Wow6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86] 1793475999
    "Installed"=dword:00000000
    "Version"="v14.44.35211.00"
    """#

    @Test func readsInstalledVersionsFromTheRegistry() {
        #expect(VisualCppRuntime.installedVersion(.x64, registryText: Self.registry) == "v14.44.35211.00")
        // Installed=0 (an interrupted install) does not count.
        #expect(VisualCppRuntime.installedVersion(.x86, registryText: Self.registry) == nil)
        #expect(VisualCppRuntime.installedVersion(.x64, registryText: "[Software\\\\Wine] 1\n") == nil)
        let query = "\r\nHKEY_LOCAL_MACHINE\\Software\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64\r\n    Version    REG_SZ    v14.44.35211.00\r\n"
        #expect(VisualCppRuntime.parseQuery(query) == "v14.44.35211.00")
        #expect(VisualCppRuntime.parseQuery("reg: Unable to find the specified registry key\n") == nil)
    }

    /// Only Microsoft's download host is accepted, and its path must carry the file's SHA-256.
    @Test func acceptsOnlyMicrosoftsDownloadHost() {
        let hash = "cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b"
        let good = URL(string: "https://download.visualstudio.microsoft.com/download/pr/990c720a/\(hash.uppercased())/VC_redist.x64.exe")!
        #expect(VisualCppRuntime.expectedHash(from: good) == hash)
        #expect(VisualCppRuntime.expectedHash(from: URL(string: "http://download.visualstudio.microsoft.com/download/pr/1/\(hash)/VC_redist.x64.exe")!) == nil)
        #expect(VisualCppRuntime.expectedHash(from: URL(string: "https://example.com/\(hash)/VC_redist.x64.exe")!) == nil)
        #expect(VisualCppRuntime.expectedHash(from: URL(string: "https://download.visualstudio.microsoft.com/download/VC_redist.x64.exe")!) == nil)
        for arch in VisualCppRuntime.Architecture.allCases {
            #expect(arch.downloadURL.scheme == "https" && arch.downloadURL.host == "aka.ms")
        }
    }

    @Test func runsAnInstallerOnlyWhileItMatchesItsRecordedHash() throws {
        let dir = TempDir()
        let folder = dir.url.appendingPathComponent("vcredist")
        #expect(VisualCppRuntime.verifiedInstaller(.x64, in: folder) == nil)
        dir.write("vcredist/VC_redist.x64.exe", PEFixture.make())
        #expect(VisualCppRuntime.verifiedInstaller(.x64, in: folder) == nil) // no recorded hash
        let file = folder.appendingPathComponent("VC_redist.x64.exe")
        try #require(VisualCppRuntime.sha256(of: file)).write(to: VisualCppRuntime.hashFile(file), atomically: true, encoding: .utf8)
        #expect(VisualCppRuntime.verifiedInstaller(.x64, in: folder) == file)
        dir.write("vcredist/VC_redist.x64.exe", PEFixture.make() + Data([0]))
        #expect(VisualCppRuntime.verifiedInstaller(.x64, in: folder) == nil)
    }

    @Test func switchesWineToMicrosoftsDLLs() {
        let reg = VisualCppRuntime.overridesRegistryFile()
        #expect(reg.hasPrefix("REGEDIT4\r\n\r\n[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\r\n"))
        for dll in ["msvcp140", "vcruntime140", "vcruntime140_1"] { #expect(reg.contains("\"\(dll)\"=\"native,builtin\"\r\n")) }
        let launch = LaunchCommand(executable: URL(fileURLWithPath: "/rt/bin/wine"), arguments: [], environment: ["WINEPREFIX": "/p"])
        let query = VisualCppRuntime.queryCommand(.x86, like: launch)
        #expect(query.arguments == ["reg", "query", #"HKLM\Software\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X86"#, "/v", "Version"])
        #expect(query.environment == launch.environment)
        let setup = VisualCppRuntime.installerGame(installer: URL(fileURLWithPath: "/dl/VC_redist.x86.exe"), prefix: WinePrefix(name: "p", path: URL(fileURLWithPath: "/p")))
        #expect(setup.arguments == ["/install", "/quiet", "/norestart"] && setup.executableRelativePath == "VC_redist.x86.exe")
    }

    /// A game that ships Microsoft's installer (here two folders up, as in multi-game packages) gets a warning until
    /// its environment has the runtime; environments without 32-bit support are told they cannot install it.
    @Test func warnsWhenAGameShipsTheInstaller() throws {
        let dir = TempDir()
        dir.write("pack/Game/Binaries/Win64/game.exe", PEFixture.make())
        let game = Game(name: "Game", folder: dir.url.appendingPathComponent("pack/Game/Binaries/Win64"), executableRelativePath: "game.exe")
        #expect(!VisualCppRuntime.gameShipsInstaller(game))
        dir.write("pack/_CommonRedist/vcredist/2022/VC_redist.x64.exe", PEFixture.make())
        #expect(!VisualCppRuntime.gameShipsInstaller(game)) // three levels up is too far
        let near = Game(name: "Game", folder: dir.url.appendingPathComponent("pack/Game"), executableRelativePath: "Binaries/Win64/game.exe")
        #expect(VisualCppRuntime.gameShipsInstaller(near))

        let prefix = makeInitializedPrefix(in: dir)
        var g = near; g.prefixID = prefix.id
        let finding = try #require(DiagnosticService.preflight(game: g, runtime: nil, prefix: prefix).first { $0.kind == .missingRuntimeComponent })
        #expect(!VisualCppRuntime.canInstall(in: prefix) && finding.suggestion.contains("cannot run 32-bit programs"))
        dir.write("prefix/drive_c/windows/syswow64/kernel32.dll", PEFixture.make())
        #expect(VisualCppRuntime.canInstall(in: prefix))
        // Registry keys alone are what Wine's own setup writes, so the warning stays until Microsoft's DLLs are there.
        dir.write("prefix/system.reg", Data(Self.registry.utf8))
        #expect(DiagnosticService.preflight(game: g, runtime: nil, prefix: prefix).contains { $0.kind == .missingRuntimeComponent })
        for name in ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"] { dir.write("prefix/drive_c/windows/system32/\(name)", PEFixture.make()) }
        #expect(VisualCppRuntime.installedVersion(.x64, in: prefix) == "v14.44.35211.00")
        #expect(DiagnosticService.preflight(game: g, runtime: nil, prefix: prefix).allSatisfy { $0.kind != .missingRuntimeComponent })
    }
}

@Suite struct VideoPlaybackTests {
    func runtime(in dir: TempDir, withGStreamer: Bool) -> WineRuntime {
        let base = "rt/wine"
        dir.write("\(base)/bin/wine", Data("#!/bin/sh\n".utf8), executable: true)
        dir.write("\(base)/lib/wine/x86_64-windows/winegstreamer.dll", Data("pe64".utf8))
        dir.write("\(base)/lib/wine/i386-windows/winegstreamer.dll", Data("pe32".utf8))
        if withGStreamer {
            dir.write("\(base)/lib/wine/x86_64-unix/winegstreamer.so", Data("so".utf8))
            dir.write("\(base)/lib/gstreamer-1.0/libgstisomp4.dylib", Data("plugin".utf8))
        }
        let root = dir.url.appendingPathComponent(base)
        return WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in "11.0" })
            .makeRuntime(kind: .custom, binary: root.appendingPathComponent("bin/wine"), root: root)
    }

    @Test func detectsGStreamerAndPointsGStreamerAtTheRuntime() {
        let plain = runtime(in: TempDir(), withGStreamer: false)
        #expect(!plain.hasGStreamer)
        let dir = TempDir(), rt = runtime(in: dir, withGStreamer: true)
        #expect(rt.hasGStreamer)
        let env = VideoPlayback.environment(for: rt, cacheDirectory: dir.url.appendingPathComponent("cache"))
        #expect(env["GST_PLUGIN_SYSTEM_PATH_1_0"] == rt.root.appendingPathComponent("lib/gstreamer-1.0").path)
        #expect(env["GST_REGISTRY_1_0"] == dir.url.appendingPathComponent("cache/registry-rt.x86_64.bin").path)
        #expect(env["GST_REGISTRY_FORK"] == "no")
    }

    /// Environments made before the runtime had winegstreamer get it copied in (64- and 32-bit) and registered.
    @Test func addsDecodersToOlderEnvironments() throws {
        let dir = TempDir(), rt = runtime(in: dir, withGStreamer: true)
        let prefix = makeInitializedPrefix(in: dir)
        dir.write("prefix/drive_c/windows/system32/kernel32.dll", PEFixture.make())
        #expect(VideoPlayback.needsSetup(prefix: prefix, runtime: rt))
        #expect(!VideoPlayback.needsSetup(prefix: prefix, runtime: runtime(in: TempDir(), withGStreamer: false)))

        try VideoPlayback.installDLLs(from: rt, into: prefix)
        #expect(FileManager.default.contents(atPath: prefix.system32.appendingPathComponent("winegstreamer.dll").path) == Data("pe64".utf8))
        let launch = LaunchCommand(executable: rt.wineBinary, arguments: [], environment: ["WINEPREFIX": prefix.path.path])
        #expect(VideoPlayback.registrationCommands(prefix: prefix, like: launch).map(\.arguments) == [["regsvr32", "/s", "winegstreamer.dll"]])
        // Still needed until the registry names it.
        #expect(VideoPlayback.needsSetup(prefix: prefix, runtime: rt))

        dir.write("prefix/drive_c/windows/syswow64/kernel32.dll", PEFixture.make())
        dir.write("prefix/drive_c/windows/syswow64/regsvr32.exe", PEFixture.make())
        try VideoPlayback.installDLLs(from: rt, into: prefix)
        let wow = prefix.path.appendingPathComponent("drive_c/windows/syswow64/winegstreamer.dll")
        #expect(FileManager.default.contents(atPath: wow.path) == Data("pe32".utf8))
        let commands = VideoPlayback.registrationCommands(prefix: prefix, like: launch)
        #expect(commands.count == 2 && commands[1].arguments.first == #"C:\windows\syswow64\regsvr32.exe"#)
        #expect(commands.allSatisfy { $0.environment == launch.environment })

        dir.write("prefix/system.reg", Data(#"[Software\\Classes\\CLSID\\{317DF618-5E5A-468A-9F15-D827A9A08162}\\InprocServer32] 1"#.utf8
                                            + Data("\n@=\"C:\\\\windows\\\\system32\\\\winegstreamer.dll\"\n".utf8)))
        #expect(!VideoPlayback.needsSetup(prefix: prefix, runtime: rt))
    }

    @Test func reportsMissingVideoDecoders() {
        let log = "0260:err:ole:com_get_class_object class {317df618-5e5a-468a-9f15-d827a9a08162} not registered"
        let finding = DiagnosticService.analyze(log: log).first { $0.subject == "gstreamer" }
        #expect(finding?.kind == .runtimeLimitation)
    }
}

@Suite struct EngineNameTests {
    @Test func renamesEnginesInstalledUnderAFormerName() throws {
        let dir = TempDir()
        dir.write("Alloy/Runtimes/metalgate-dxmt-1/alloy-runtime.json", Data("{\n  \"name\" : \"Metalgate Game Engine (DXMT 0.80)\",\n  \"origin\" : \"alloy\"\n}".utf8))
        dir.write("Alloy/Runtimes/d3dmetal-4/alloy-runtime.json", Data("{\n  \"name\" : \"D3DMetal 4.0\"\n}".utf8))
        #expect(DataMigration.renameEngines(applicationSupport: dir.url) == 1)
        let text = try String(contentsOf: dir.url.appendingPathComponent("Alloy/Runtimes/metalgate-dxmt-1/alloy-runtime.json"), encoding: .utf8)
        #expect(text.contains("\"Alloy Game Engine (DXMT 0.80)\""))
        #expect(DataMigration.renameEngines(applicationSupport: dir.url) == 0)
    }
}
