import Foundation
import Testing
@testable import AlloyCore

@Suite struct GameStoreTests {
    @Test func everyStoreDownloadsOverHTTPSFromItsOwnHosts() {
        for store in GameStore.allCases {
            let host = store.installerURL.host!.lowercased()
            #expect(store.installerURL.scheme == "https")
            #expect(store.downloadHosts.contains { host == $0 || host.hasSuffix("." + $0) }, "\(store) installer host \(host)")
            #expect(store.serviceURL.scheme == "https")
            #expect(!store.executablePaths.isEmpty && !store.installerFileName.isEmpty)
        }
        #expect(Set(GameStore.allCases.map(\.environmentName)).count == GameStore.allCases.count)
    }

    @Test func findsTheStoreAppAndBuildsItsEntry() throws {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        #expect(StoreInstaller.executable(of: .epic, in: prefix) == nil)
        dir.write("prefix/drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe", PEFixture.make())
        let epic = try #require(StoreInstaller.executable(of: .epic, in: prefix))
        #expect(epic.path.hasSuffix("Win32/EpicGamesLauncher.exe"))
        // The 64-bit launcher wins once it is there.
        dir.write("prefix/drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe", PEFixture.make())
        #expect(StoreInstaller.executable(of: .epic, in: prefix)?.path.hasSuffix("Win64/EpicGamesLauncher.exe") == true)

        let entry = StoreInstaller.libraryEntry(.epic, executable: epic, prefix: prefix, graphics: GraphicsConfiguration(backend: .dxmt))
        #expect(entry.name == "Epic Games" && entry.arguments == ["-SkipBuildPatchPrereq"] && entry.prefixID == prefix.id)
        #expect(GameStore.store(for: entry) == .epic && !StoreLibraryScanner.startsAGame(entry))
        #expect(GameStore.store(for: makeGame(in: dir)) == nil)
    }

    /// An `.msi` runs through the environment's msiexec with the package's Z: path; an `.exe` runs directly.
    @Test func runsEachKindOfInstaller() {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        let msi = StoreInstaller.installerGame(.epic, installer: URL(fileURLWithPath: "/Users/me/Library/Downloads/Epic Installer.msi"),
                                               prefix: prefix, graphics: GraphicsConfiguration())
        #expect(msi.executableRelativePath == "msiexec.exe" && msi.folder.path.hasSuffix("drive_c/windows/system32"))
        #expect(msi.arguments == ["/i", #"Z:\Users\me\Library\Downloads\Epic Installer.msi"#, "/qb"])
        let ea = StoreInstaller.installerGame(.ea, installer: URL(fileURLWithPath: "/tmp/dl/EAappInstaller.exe"), prefix: prefix,
                                              graphics: GraphicsConfiguration())
        #expect(ea.executableRelativePath == "EAappInstaller.exe" && ea.arguments.isEmpty)
        #expect(!GameStore.ea.installerExitsWhenDone && GameStore.steam.installerExitsWhenDone && GameStore.epic.installerExitsWhenDone)
    }

    @Test func onlySteamNeedsTheWebHelperFix() {
        let root = URL(fileURLWithPath: "/rt")
        let tls = WineRuntime(kind: .custom, wineBinary: root.appendingPathComponent("bin/wine"), root: root, hasGnuTLS: true)
        #expect(GameStore.epic.missingRequirements(in: tls).isEmpty)
        #expect(GameStore.steam.missingRequirements(in: tls).count == 1)
        let bare = WineRuntime(kind: .custom, wineBinary: root.appendingPathComponent("bin/wine"), root: root)
        #expect(GameStore.ubisoft.missingRequirements(in: bare).count == 1)
    }
}

@Suite struct StoreLibraryTests {
    @Test func readsInstalledSteamGames() throws {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        let steam = "prefix/drive_c/Program Files (x86)/Steam"
        dir.write("\(steam)/steam.exe", PEFixture.make())
        func manifest(_ id: String, _ name: String, flags: Int) -> Data {
            Data("\"AppState\"\n{\n\t\"appid\"\t\t\"\(id)\"\n\t\"Universe\"\t\t\"1\"\n\t\"name\"\t\t\"\(name)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"UserConfig\"\n\t{\n\t\t\"name\"\t\t\"Other\"\n\t}\n}\n".utf8)
        }
        dir.write("\(steam)/steamapps/appmanifest_1091500.acf", manifest("1091500", "Cyberpunk 2077", flags: 4))
        dir.write("\(steam)/steamapps/appmanifest_570.acf", manifest("570", "Dota 2", flags: 1026))  // still downloading
        dir.write("\(steam)/steamapps/appmanifest_228980.acf", manifest("228980", "Steamworks Common Redistributables", flags: 4))
        let found = StoreLibraryScanner.installedGames(of: .steam, in: prefix)
        #expect(found.map(\.name) == ["Cyberpunk 2077"])
        #expect(found.first?.launchArgument == "steam://rungameid/1091500")

        let store = Game(name: "Steam", folder: dir.url.appendingPathComponent(steam), executableRelativePath: "steam.exe",
                         prefixID: prefix.id, arguments: ["-cef-disable-gpu"])
        let added = StoreLibraryScanner.newEntries(for: found, storeEntry: store, existing: [store])
        #expect(added.count == 1 && added[0].arguments == ["-cef-disable-gpu", "steam://rungameid/1091500"])
        #expect(StoreLibraryScanner.startsAGame(added[0]) && GameStore.store(for: added[0]) == .steam)
        // Found again later, it is not added twice.
        #expect(StoreLibraryScanner.newEntries(for: found, storeEntry: store, existing: [store] + added).isEmpty)
    }

    @Test func readsInstalledEpicGamesAndRejectsOddManifests() throws {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        let manifests = "prefix/drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"
        func item(_ name: String, app: String, incomplete: Bool = false) -> Data {
            try! JSONSerialization.data(withJSONObject: ["DisplayName": name, "AppName": app, "CatalogNamespace": "ns1",
                                                         "CatalogItemId": "abc123", "bIsIncompleteInstall": incomplete])
        }
        dir.write("\(manifests)/A.item", item("Fortnite", app: "Fortnite"))
        dir.write("\(manifests)/B.item", item("Half Done", app: "Half", incomplete: true))
        dir.write("\(manifests)/C.item", item("Sneaky", app: "x?action=uninstall&y"))
        dir.write("\(manifests)/notes.txt", Data("ignore".utf8))
        let found = StoreLibraryScanner.installedGames(of: .epic, in: prefix)
        #expect(found.map(\.name) == ["Fortnite"])
        #expect(found.first?.launchArgument == "com.epicgames.launcher://apps/ns1%3Aabc123%3AFortnite?action=launch&silent=true")
        #expect(StoreLibraryScanner.installedGames(of: .ea, in: prefix).isEmpty)
    }
}

@Suite struct StoreConnectivityTests {
    @Test func recognisesFilterPages() {
        let forti = Data("<html><head><title>Web Filter Violation</title></head><body>FortiGuard Intrusion Prevention - Access Blocked</body></html>".utf8)
        #expect(StoreConnectivity.looksLikeBlockPage(status: 403, body: forti))
        #expect(StoreConnectivity.looksLikeBlockPage(status: 200, body: Data("This site is blocked by your administrator".utf8)))
        #expect(!StoreConnectivity.looksLikeBlockPage(status: 200, body: Data(#"{"response":{"servertime":1793549537}}"#.utf8)))
        // A real server's own refusal still means the network let us through.
        #expect(!StoreConnectivity.looksLikeBlockPage(status: 401, body: Data(#"{"errorCode":"errors.com.epicgames.common.authentication"}"#.utf8)))
        #expect(!StoreConnectivity.looksLikeBlockPage(status: 404, body: forti))
    }

    @Test func explainsWhatToDo() {
        #expect(StoreConnectivity.explanation(.reachable, store: .steam) == nil)
        #expect(StoreConnectivity.explanation(.blockedByNetwork, store: .steam)?.contains("another network") == true)
        #expect(StoreConnectivity.explanation(.offline, store: .epic)?.contains("not connected") == true)
    }
}

@Suite struct MetricsTests {
    @Test func findsTheProcessTheHUDLoadedInto() {
        #expect(MetricsHUD.loadingProcess(in: "2026-11-01 21:44:10.686 SpaceGame-Win64-Shipping.exe[1931:26964] [libMTLHud] Metric com.apple.hud-stat.fps already exist") == 1931)
        #expect(MetricsHUD.loadingProcess(in: "[   3.42s] 2026-11-01 21:43:45.242 GameLauncher-Win64-Shipping.exe[1862:25555] [libMTLHud] Metric x") == 1862)
        #expect(MetricsHUD.loadingProcess(in: "0128:err:ole:com_get_class_object class not registered") == nil)
        #expect(MetricsHUD.loadingProcess(in: "[libMTLHud] no process") == nil)
    }

    /// Each process is hidden once, however many lines the HUD prints there.
    @Test func hidesEachProcessOnce() async throws {
        final class Counter: @unchecked Sendable { let lock = NSLock(); var n = 0 }
        let counter = Counter()
        let hider = MetricsHUD.Hider { counter.lock.withLock { counter.n += 1 } }
        func line(_ text: String) -> LogLine { LogLine(id: 0, date: Date(), stream: .stderr, text: text) }
        for pid in [100, 100, 100, 200] { hider.observe(line("game.exe[\(pid):1] [libMTLHud] Metric a already exist")) }
        hider.observe(line("game.exe[300:1] something else"))
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(counter.lock.withLock { counter.n } == 2)
    }

    @Test func loadsTheHUDForTheShortcutOrWhenShownAtStart() throws {
        let dir = TempDir()
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let game = makeGame(in: dir)
        let prefix = makeInitializedPrefix(in: dir), runtime = makeFakeRuntime(in: dir)
        let plain = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(plain.environment["MTL_HUD_ENABLED"] == nil)
        let shortcut = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions(loadMetricsHUD: true))
        #expect(shortcut.environment["MTL_HUD_ENABLED"] == "1")
    }

    @Test func shortcutIsOnUnlessTurnedOff() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.metricsShortcut)
        var off = AppSettings(); off.metricsShortcut = false
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off)).metricsShortcut == false)
    }
}

@Suite struct AntiCheatTests {
    @Test func findsAntiCheatAGameShips() {
        let dir = TempDir()
        dir.write("game/Game.exe", PEFixture.make())
        #expect(AntiCheat.detect(in: dir.url.appendingPathComponent("game")).isEmpty)
        dir.write("game/EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe", PEFixture.make())
        dir.write("game/Binaries/Win64/BattlEye/BEService_x64.exe", PEFixture.make())
        #expect(AntiCheat.detect(in: dir.url.appendingPathComponent("game")) == ["Easy Anti-Cheat", "BattlEye"])
    }
}

@Suite struct DirectX12Tests {
    /// Only games that render with DirectX 12 alone need D3DMetal; games that also have DirectX 11 run on DXMT.
    @Test func flagsGamesThatOnlyHaveDirectX12() {
        #expect(GraphicsDefaults.needsD3DMetal([.d3d12]))
        #expect(GraphicsDefaults.needsD3DMetal([.d3d12, .d3d9]))
        #expect(!GraphicsDefaults.needsD3DMetal([.d3d12, .d3d11]))
        #expect(!GraphicsDefaults.needsD3DMetal([.d3d11]))
        #expect(!GraphicsDefaults.needsD3DMetal([]))
    }
}

@Suite struct WineTemporaryFilesTests {
    /// Links to a moved runtime are removed so Wine makes new ones; files and working links stay.
    @Test func removesOnlyDeadLinks() throws {
        let dir = TempDir()
        let fm = FileManager.default
        let temp = dir.url.appendingPathComponent("T")
        let wt = temp.appendingPathComponent("winetemp-1-2-3")
        let macos = wt.appendingPathComponent("Game.exe.app/Contents/MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        dir.write("runtime/ntdll.so", Data("x".utf8))
        try fm.createSymbolicLink(atPath: wt.appendingPathComponent("ntdll.so").path, withDestinationPath: dir.url.appendingPathComponent("old/ntdll.so").path)
        try fm.createSymbolicLink(atPath: wt.appendingPathComponent("wine").path, withDestinationPath: dir.url.appendingPathComponent("runtime/ntdll.so").path)
        try fm.createSymbolicLink(atPath: macos.appendingPathComponent("ntdll.so").path, withDestinationPath: dir.url.appendingPathComponent("old/ntdll.so").path)
        dir.write("T/winetemp-1-2-3/explorer.exe", Data("x".utf8))
        try fm.createDirectory(at: temp.appendingPathComponent("other"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: temp.appendingPathComponent("other/dead").path, withDestinationPath: "/nonexistent")

        #expect(WineTemporaryFiles.removeDeadLinks(temporaryDirectory: temp) == 2)
        let names = try fm.contentsOfDirectory(atPath: wt.path)
        #expect(Set(names) == ["wine", "explorer.exe", "Game.exe.app"])
        #expect(try fm.contentsOfDirectory(atPath: macos.path).isEmpty)
        #expect((try? fm.destinationOfSymbolicLink(atPath: temp.appendingPathComponent("other/dead").path)) != nil)
    }
}
