import Foundation
import Testing
@testable import AlloyCore

@Suite struct CoverArtAndSafetyTests {
    @Test func readsTheSteamAppIDAlloyLaunchesWith() {
        var game = Game(name: "Test", folder: URL(fileURLWithPath: "/tmp"), executableRelativePath: "steam.exe")
        game.arguments = ["steam://rungameid/1091500"]
        #expect(CoverArt.steamAppID(of: game) == "1091500")
        game.arguments = ["-silent"]
        #expect(CoverArt.steamAppID(of: game) == nil)
    }

    @Test func findsSteamImagesInBothLayouts() {
        let dir = TempDir()
        _ = dir.write("cache/570_library_600x900.jpg", Data([1]))
        _ = dir.write("cache/570_library_hero.jpg", Data([1]))
        _ = dir.write("cache/730/a1b2/library_600x900.jpg", Data([1]))
        _ = dir.write("cache/730/library_hero_blur.jpg", Data([1]))
        _ = dir.write("cache/730/logo.png", Data([1]))
        let cache = dir.url.appendingPathComponent("cache")
        let dota = CoverArt.steamImages(appID: "570", cache: cache)
        #expect(dota.portrait?.lastPathComponent == "570_library_600x900.jpg" && dota.hero != nil && dota.logo == nil)
        let cs = CoverArt.steamImages(appID: "730", cache: cache)
        #expect(cs.portrait?.lastPathComponent == "library_600x900.jpg" && cs.hero == nil && cs.logo != nil)
        #expect(CoverArt.steamImages(appID: "999", cache: cache).isEmpty)
        // Only the smaller capsule cached: used, but a 600×900 wins when both exist.
        _ = dir.write("cache/1721470/1d1b/library_capsule.jpg", Data([1]))
        #expect(CoverArt.steamImages(appID: "1721470", cache: cache).portrait?.lastPathComponent == "library_capsule.jpg")
        _ = dir.write("cache/730/c3/library_capsule.jpg", Data([1]))
        #expect(CoverArt.steamImages(appID: "730", cache: cache).portrait?.lastPathComponent == "library_600x900.jpg")
    }

    @Test func dlssTurnsOffOnlyAfterAnEarlyCrash() {
        #expect(DLSSSafety.shouldTurnOff(after: .exited(code: 3), ranFor: 20))
        #expect(DLSSSafety.shouldTurnOff(after: .terminatedBySignal(11), ranFor: 20))
        #expect(!DLSSSafety.shouldTurnOff(after: .exited(code: 0), ranFor: 20))
        #expect(!DLSSSafety.shouldTurnOff(after: .terminatedBySignal(15), ranFor: 20))
        #expect(!DLSSSafety.shouldTurnOff(after: .exited(code: 3), ranFor: 3600))
    }
}
