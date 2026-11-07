import Foundation
import Testing
@testable import AlloyCore

@Suite struct StoreGameInstallTests {
    @Test func readsSteamLinksAndIDs() {
        for text in ["620", " 620\n", "https://store.steampowered.com/app/620/Portal_2/", "store.steampowered.com/app/620",
                     "https://steamcommunity.com/app/620", "https://steamdb.info/app/620/", "steam://install/620",
                     "steam://rungameid/620", "steam://store/620"] {
            #expect(StoreGameLink.parse(text) == StoreGameLink(store: .steam, id: "620"), "\(text)")
        }
        #expect(StoreGameLink.parse("steam://install/620")?.address == "steam://install/620")
    }

    @Test func readsEpicLinks() {
        for text in ["https://store.epicgames.com/en-US/p/fortnite", "store.epicgames.com/p/fortnite",
                     "https://www.epicgames.com/store/en-US/p/fortnite", "com.epicgames.launcher://store/product/fortnite",
                     "https://store.epicgames.com/p/Fortnite?lang=de"] {
            #expect(StoreGameLink.parse(text) == StoreGameLink(store: .epic, id: "fortnite"), "\(text)")
        }
        #expect(StoreGameLink.parse("https://store.epicgames.com/p/fortnite")?.address == "com.epicgames.launcher://store/product/fortnite")
    }

    @Test func refusesAnythingElse() {
        for text in ["", "0", "12345678901", "-1", "620; rm", "steam://uninstall/620", "steam://install/620&x",
                     "https://evil.example/app/620", "https://store.steampowered.com/app/abc", "https://store.epicgames.com/p/fort%20nite",
                     "https://store.epicgames.com/p/-x", "com.epicgames.launcher://apps/x?action=uninstall", "file:///etc/passwd",
                     "https://store.steampowered.com.evil.example/app/620"] {
            #expect(StoreGameLink.parse(text) == nil, "\(text)")
        }
    }

    @Test func showsSteamAndEpicDownloads() {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        let steam = "prefix/drive_c/Program Files (x86)/Steam"
        dir.write("\(steam)/steam.exe", PEFixture.make())
        func manifest(_ id: String, _ name: String, flags: Int, done: Int = 0, total: Int = 0) -> Data {
            Data("\"AppState\"\n{\n\t\"appid\"\t\t\"\(id)\"\n\t\"name\"\t\t\"\(name)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"BytesToDownload\"\t\t\"\(total)\"\n\t\"BytesDownloaded\"\t\t\"\(done)\"\n}\n".utf8)
        }
        dir.write("\(steam)/steamapps/appmanifest_620.acf", manifest("620", "Portal 2", flags: 1026, done: 2_500, total: 10_000))
        dir.write("\(steam)/steamapps/appmanifest_570.acf", manifest("570", "Dota 2", flags: 1538, done: 1, total: 4))  // paused
        dir.write("\(steam)/steamapps/appmanifest_400.acf", manifest("400", "Portal", flags: 4))  // installed
        let steamDownloads = StoreDownloads.current(of: .steam, in: prefix)
        #expect(steamDownloads.map(\.name) == ["Dota 2", "Portal 2"])
        #expect(steamDownloads.last?.fraction == 0.25 && steamDownloads.last?.paused == false)
        #expect(steamDownloads.first?.paused == true)

        let manifests = "prefix/drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"
        dir.write("\(manifests)/A.item", try! JSONSerialization.data(withJSONObject: ["DisplayName": "Done", "AppName": "D", "bIsIncompleteInstall": false]))
        dir.write("\(manifests)/B.item", try! JSONSerialization.data(withJSONObject: ["DisplayName": "Coming", "AppName": "C", "bIsIncompleteInstall": true]))
        #expect(StoreDownloads.current(of: .epic, in: prefix).map(\.name) == ["Coming"])
    }
}
