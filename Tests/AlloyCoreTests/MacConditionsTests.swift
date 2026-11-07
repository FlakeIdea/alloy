import Foundation
import Testing
@testable import AlloyCore

struct MacConditionsTests {
    @Test func quietWhenNothingSlowsTheMac() {
        #expect(MacConditions.notice(thermal: .nominal, lowPowerMode: false) == nil)
        #expect(MacConditions.notice(thermal: .fair, lowPowerMode: false) == nil)
    }

    @Test func explainsHeatBeforeLowPowerMode() {
        #expect(MacConditions.notice(thermal: .serious, lowPowerMode: true)?.contains("hot") == true)
        #expect(MacConditions.notice(thermal: .critical, lowPowerMode: false)?.contains("very hot") == true)
        #expect(MacConditions.notice(thermal: .nominal, lowPowerMode: true)?.contains("Low Power Mode") == true)
    }
}

struct WindowsAppEntryTests {
    @Test func olderLibrariesLoadAsGamesAndAppsRoundTrip() throws {
        var game = Game(name: "Notepad++", folder: URL(fileURLWithPath: "/tmp/npp"), executableRelativePath: "notepad++.exe")
        let old = try JSONEncoder().encode(game)
        // A library saved before apps existed has no isApp key.
        var dict = try JSONSerialization.jsonObject(with: old) as! [String: Any]
        dict.removeValue(forKey: "isApp")
        let legacy = try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: dict))
        #expect(legacy.isApp == false)
        game.isApp = true
        let back = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(back.isApp)
    }
}
