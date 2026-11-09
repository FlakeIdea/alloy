import Foundation
import Testing
@testable import AlloyCore

struct SaveBackupsTests {
    func makePrefix(_ dir: TempDir) -> WinePrefix {
        let user = "drive_c/users/player"
        dir.write("pfx/\(user)/AppData/Roaming/Game/save1.dat", Data("slot1".utf8))
        dir.write("pfx/\(user)/AppData/Local/Game/Saved/SaveGames/a.sav", Data("unreal".utf8))
        dir.write("pfx/\(user)/AppData/Local/Game/Saved/Logs/game.log", Data("log".utf8))
        dir.write("pfx/\(user)/AppData/Local/Temp/junk.tmp", Data("tmp".utf8))
        dir.write("pfx/\(user)/AppData/LocalLow/Studio/Game/prefs.json", Data("{}".utf8))
        dir.write("pfx/\(user)/Saved Games/Other/s.bin", Data("x".utf8))
        dir.write("pfx/drive_c/Program Files (x86)/Steam/userdata/123/440/remote/cloud.sav", Data("cloud".utf8))
        dir.write("pfx/drive_c/Program Files (x86)/Steam/userdata/123/760/remote/440/screenshots/1.jpg", Data("jpg".utf8))
        // Wine links Documents to the Mac; the link must not be followed.
        dir.write("mac-docs/private.txt", Data("mine".utf8))
        try? FileManager.default.createSymbolicLink(at: dir.url.appendingPathComponent("pfx/\(user)/Documents"),
                                                    withDestinationURL: dir.url.appendingPathComponent("mac-docs"))
        return WinePrefix(name: "Test", path: dir.url.appendingPathComponent("pfx"))
    }

    @Test func backsUpSavesWithoutCachesOrLinks() throws {
        let dir = TempDir()
        let prefix = makePrefix(dir)
        let storage = dir.url.appendingPathComponent("storage")
        let backup = try #require(try SaveBackups.backUp(prefix: prefix, reason: "Test", storage: storage))
        let has = { (path: String) in FileManager.default.fileExists(atPath: backup.folder.appendingPathComponent(path).path) }
        let user = "drive_c/users/player"
        #expect(has("\(user)/AppData/Roaming/Game/save1.dat"))
        #expect(has("\(user)/AppData/Local/Game/Saved/SaveGames/a.sav"))
        #expect(has("\(user)/AppData/LocalLow/Studio/Game/prefs.json"))
        #expect(has("\(user)/Saved Games/Other/s.bin"))
        #expect(has("drive_c/Program Files (x86)/Steam/userdata/123/440/remote/cloud.sav"))
        #expect(!has("\(user)/AppData/Local/Game/Saved/Logs/game.log"))
        #expect(!has("\(user)/AppData/Local/Temp/junk.tmp"))
        #expect(!has("drive_c/Program Files (x86)/Steam/userdata/123/760"))
        #expect(!has("\(user)/Documents/private.txt"))
        #expect(backup.manifest.files == 5)
        #expect(SaveBackups.list(prefixID: prefix.id, storage: storage).map(\.folder) == [backup.folder])
    }

    @Test func restoresOverChangedSavesAndKeepsNewOnes() throws {
        let dir = TempDir()
        let prefix = makePrefix(dir)
        let storage = dir.url.appendingPathComponent("storage")
        let backup = try #require(try SaveBackups.backUp(prefix: prefix, reason: "Test", storage: storage))
        let save = prefix.path.appendingPathComponent("drive_c/users/player/AppData/Roaming/Game/save1.dat")
        try Data("corrupted".utf8).write(to: save)
        let newer = prefix.path.appendingPathComponent("drive_c/users/player/AppData/Roaming/Game/save2.dat")
        try Data("new".utf8).write(to: newer)
        try FileManager.default.removeItem(at: prefix.path.appendingPathComponent("drive_c/users/player/AppData/LocalLow"))
        let count = try SaveBackups.restore(backup, into: prefix)
        #expect(count == 5)
        #expect(try String(contentsOf: save, encoding: .utf8) == "slot1")
        #expect(FileManager.default.fileExists(atPath: newer.path))
        #expect(FileManager.default.fileExists(atPath: prefix.path.appendingPathComponent("drive_c/users/player/AppData/LocalLow/Studio/Game/prefs.json").path))
        // The Mac folder behind the link is untouched.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.appendingPathComponent("mac-docs").path) == ["private.txt"])
        // A backup only goes back into its own environment.
        let other = WinePrefix(name: "Other", path: prefix.path)
        #expect(throws: (any Error).self) { try SaveBackups.restore(backup, into: other) }
    }

    @Test func keepsTheLastThree() throws {
        let dir = TempDir()
        let prefix = makePrefix(dir)
        let storage = dir.url.appendingPathComponent("storage")
        for i in 0..<5 {
            try SaveBackups.backUp(prefix: prefix, reason: "n\(i)", storage: storage, date: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60))
        }
        let kept = SaveBackups.list(prefixID: prefix.id, storage: storage)
        #expect(kept.map(\.manifest.reason) == ["n4", "n3", "n2"])
    }

    @Test func noSavesNoBackup() throws {
        let dir = TempDir()
        dir.write("empty/drive_c/windows/system32/x.dll", Data())
        let prefix = WinePrefix(name: "Empty", path: dir.url.appendingPathComponent("empty"))
        #expect(try SaveBackups.backUp(prefix: prefix, reason: "x", storage: dir.url.appendingPathComponent("s")) == nil)
    }
}
