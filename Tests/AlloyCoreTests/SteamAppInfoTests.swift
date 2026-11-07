import Foundation
import Testing
@testable import AlloyCore

struct SteamAppInfoTests {
    typealias Launch = SteamAppInfo.Launch

    /// Writes a format-29 appinfo.vdf: keys are indexes into a string table at the end of the file.
    final class Writer {
        var strings: [String] = []
        var body = Data()
        func index(_ s: String) -> UInt32 {
            if let i = strings.firstIndex(of: s) { return UInt32(i) }
            strings.append(s); return UInt32(strings.count - 1)
        }
        func u32(_ v: UInt32, into d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func section(_ key: String, _ fill: (inout Data) -> Void, into d: inout Data) {
            d.append(0); u32(index(key), into: &d); fill(&d); d.append(8)
        }
        func string(_ key: String, _ value: String, into d: inout Data) {
            d.append(1); u32(index(key), into: &d); d.append(contentsOf: Array(value.utf8)); d.append(0)
        }
        func app(_ id: UInt32, _ fill: (inout Data) -> Void) {
            var kv = Data()
            section("appinfo", fill, into: &kv)
            kv.append(8)
            u32(id, into: &body); u32(UInt32(60 + kv.count), into: &body)
            body.append(Data(count: 60)); body.append(kv)
        }
        func file() -> Data {
            var d = Data()
            u32(0x07564429, into: &d); u32(1, into: &d)
            let tableOffset = UInt64(16 + body.count + 4)
            withUnsafeBytes(of: tableOffset.littleEndian) { d.append(contentsOf: $0) }
            d.append(body); u32(0, into: &d)
            u32(UInt32(strings.count), into: &d)
            for s in strings { d.append(contentsOf: Array(s.utf8)); d.append(0) }
            return d
        }
    }

    func mcosuLike() -> Data {
        let w = Writer()
        w.app(607260) { d in
            w.section("common", { w.string("oslist", "windows,macos,linux", into: &$0) }, into: &d)
            w.section("config", { c in
                w.string("installdir", "McOsu", into: &c)
                w.section("launch", { l in
                    w.section("0", { e in
                        w.string("executable", "McEngine.exe", into: &e); w.string("type", "vr", into: &e)
                        w.section("config", { w.string("oslist", "windows", into: &$0) }, into: &e)
                    }, into: &l)
                    w.section("1", { e in
                        w.string("executable", "McEngine_dx11.exe", into: &e); w.string("arguments", "-novr", into: &e)
                        w.string("type", "option2", into: &e)
                        w.section("config", { w.string("oslist", "windows", into: &$0) }, into: &e)
                    }, into: &l)
                    w.section("3", { e in
                        w.string("executable", "McEngine", into: &e)
                        w.section("config", { w.string("oslist", "macos", into: &$0) }, into: &e)
                    }, into: &l)
                }, into: &c)
            }, into: &d)
        }
        return w.file()
    }

    @Test func readsFormat29() throws {
        let apps = try SteamAppInfoReader.parse(mcosuLike())
        let info = try #require(apps[607260])
        #expect(info.hasMacVersion)
        #expect(info.installDirectory == "McOsu")
        #expect(info.launches.map(\.executable) == ["McEngine.exe", "McEngine_dx11.exe", "McEngine"])
        #expect(info.launches[1].arguments == "-novr")
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: (any Error).self) { try SteamAppInfoReader.parse(Data("not a vdf file".utf8)) }
        #expect(throws: (any Error).self) { try SteamAppInfoReader.parse(Data(mcosuLike().prefix(40))) }
    }

    @Test func choosesTheDesktopWindowsLaunch() throws {
        let launches = try #require(SteamAppInfoReader.parse(mcosuLike())[607260]).launches
        #expect(SteamDirectLaunch.choose(launches)?.executable == "McEngine_dx11.exe")

        func launch(_ exe: String, type: String = "", os: [String] = ["windows"], beta: String = "") -> Launch {
            Launch(executable: exe, arguments: "", type: type, oslist: os, workingDirectory: "", betaKey: beta, needsDLC: false)
        }
        #expect(SteamDirectLaunch.choose([launch("Editor.exe", type: "editor"), launch("Game.exe", type: "option1"),
                                          launch("Main.exe", type: "default")])?.executable == "Main.exe")
        #expect(SteamDirectLaunch.choose([launch("Beta.exe", beta: "beta"), launch("Game.app", os: ["macos"])]) == nil)
        #expect(SteamDirectLaunch.choose([launch("bin\\win64\\Game.exe", os: [])])?.executable == "bin\\win64\\Game.exe")
    }

    @Test func splitsArguments() {
        #expect(SteamDirectLaunch.splitArguments("-novr") == ["-novr"])
        #expect(SteamDirectLaunch.splitArguments(" -a  \"two words\" -b ") == ["-a", "two words", "-b"])
        #expect(SteamDirectLaunch.splitArguments("") == [])
    }

    /// Lines as Steam writes them; only a sign-in after Alloy opened Steam counts, and the latest state wins.
    @Test func readsSteamSignInFromItsConnectionLog() {
        let utc = TimeZone(identifier: "UTC")!
        let log = """
        [2026-11-07 19:40:00] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete
        [2026-11-07 19:45:46] [Connected, 4, 7] [U:1:1] Logging on [U:1:1]
        [2026-11-07 19:45:47] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'
        [2026-11-07 19:45:47] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete
        [2026-11-07 19:45:47] CClientJobGetClientUpdateHosts: cached version not expired
        """
        func at(_ time: String) -> Date {
            let f = DateFormatter(); f.timeZone = utc; f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.date(from: time)!
        }
        #expect(SteamDirectLaunch.signedIn(connectionLog: log, since: at("2026-11-07 19:45:40"), timeZone: utc))
        // The earlier sign-in, before Steam was opened this time, doesn't count.
        let starting = log.components(separatedBy: "\n").prefix(2).joined(separator: "\n")
        #expect(!SteamDirectLaunch.signedIn(connectionLog: starting, since: at("2026-11-07 19:45:40"), timeZone: utc))
        #expect(!SteamDirectLaunch.signedIn(connectionLog: log, since: at("2026-11-07 19:50:00"), timeZone: utc))
        #expect(!SteamDirectLaunch.signedIn(connectionLog: log + "\n[2026-11-07 19:46:00] [Logged Off, 4, 7] [U:1:1] Log off",
                                            since: at("2026-11-07 19:45:40"), timeZone: utc))
    }

    @Test func startsTheGameProgramInsideItsFolder() throws {
        let steam = FileManager.default.temporaryDirectory.appendingPathComponent("steam-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: steam) }
        let game = steam.appendingPathComponent("steamapps/common/McOsu")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data().write(to: game.appendingPathComponent("McEngine_dx11.exe"))
        try "\"AppState\"\n{\n\t\"appid\"\t\t\"607260\"\n\t\"installdir\"\t\t\"McOsu\"\n}\n"
            .write(to: steam.appendingPathComponent("steamapps/appmanifest_607260.acf"), atomically: true, encoding: .utf8)
        let entry = Game(name: "McOsu", folder: steam, executableRelativePath: "steam.exe", prefixID: UUID(),
                         arguments: ["-cef-disable-gpu", "steam://rungameid/607260"])
        let apps = try SteamAppInfoReader.parse(mcosuLike())

        let direct = try #require(SteamDirectLaunch.directGame(for: entry, steamFolder: steam, apps: apps))
        #expect(direct.game.executableURL.standardizedFileURL == game.appendingPathComponent("McEngine_dx11.exe").standardizedFileURL)
        #expect(direct.game.arguments == ["-novr"])
        #expect(direct.game.environment["SteamAppId"] == "607260")
        #expect(direct.game.id == entry.id)

        // A launch path that climbs out of the game's folder is not used.
        var escaping = apps
        escaping[607260]?.launches[1].executable = "..\\..\\..\\steam.exe"
        #expect(SteamDirectLaunch.directGame(for: entry, steamFolder: steam, apps: escaping) == nil)
        // Nor one that isn't installed.
        try FileManager.default.removeItem(at: game.appendingPathComponent("McEngine_dx11.exe"))
        #expect(SteamDirectLaunch.directGame(for: entry, steamFolder: steam, apps: apps) == nil)
    }
}
