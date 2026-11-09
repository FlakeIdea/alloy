import Foundation
import Testing
@testable import AlloyCore

struct SteamBackgroundTests {
    func procArgs(_ exec: String, _ args: [String], _ env: [String]) -> Data {
        var d = Data()
        withUnsafeBytes(of: Int32(args.count)) { d.append(contentsOf: $0) }
        d.append(Data(exec.utf8)); d.append(contentsOf: [0, 0, 0, 0])
        for field in args + env { d.append(Data(field.utf8)); d.append(0) }
        return d
    }

    @Test func readsWineProcessArguments() throws {
        let data = procArgs("/Applications/Alloy.app/wine/bin/wine-preloader",
                            [#"C:\Program Files (x86)\Steam\bin\cef\cef.win7x64\steamwebhelper.exe"#, "-lang=en"],
                            ["HOME=/Users/x", "WINEPREFIX=/Users/x/Alloy/Prefixes/steam", "A=b=c"])
        let parsed = try #require(WindowsProcesses.parse(data))
        #expect(parsed.arguments.count == 2)
        #expect(parsed.environment["WINEPREFIX"] == "/Users/x/Alloy/Prefixes/steam")
        #expect(parsed.environment["A"] == "b=c")
        #expect(WindowsProcesses.programName(parsed.arguments[0]) == "steamwebhelper.exe")
        #expect(SteamBackground.programs.contains("steamwebhelper.exe"))
    }

    @Test func onlyWindowsProgramsHaveNames() {
        #expect(WindowsProcesses.programName(#"C:\Program Files (x86)\Steam\Steam.exe"#) == "steam.exe")
        #expect(WindowsProcesses.programName("/usr/bin/yes") == nil)
        #expect(WindowsProcesses.parse(Data([1, 0])) == nil)
    }

    @Test func settingsDefaultToSteamInBackgroundAndAskAboutBackups() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.steamInBackground && old.backupSaves == nil && old.backsUpSaves)
    }
}
