import Foundation
import Testing
@testable import AlloyCore

@Suite struct GameScanCacheTests {
    func pe(naming dll: String) -> Data { var d = PEFixture.make(); d.append(contentsOf: Array(dll.utf8)); return d }

    @Test func scansOncePerVersionOfTheProgram() throws {
        let dir = TempDir()
        let game = makeGame(in: dir, data: pe(naming: "d3d11.dll"))
        let file = dir.url.appendingPathComponent("scans.json")
        let cache = GameScanCache(url: file)
        #expect(cache.saved(for: game) == nil)
        #expect(cache.traits(for: game).usage == [.d3d11])
        // Saved, and read back by a new cache (the next app start).
        #expect(GameScanCache(url: file).saved(for: game)?.usage == [.d3d11])
        // A changed program is scanned again.
        try pe(naming: "d3d12.dll").write(to: game.executableURL)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: game.executableURL.path)
        #expect(cache.saved(for: game) == nil)
        #expect(cache.traits(for: game).usage == [.d3d12])
        cache.forget(game.id)
        #expect(GameScanCache(url: file).saved(for: game) == nil)
    }

    @Test func findsNamesAcrossReadBoundaries() throws {
        let dir = TempDir()
        // "D3D12.DLL" straddles the 1 MB read boundary, in capitals.
        var bytes = [UInt8](repeating: 0, count: (1 << 20) - 4)
        bytes += Array("D3D12.DLL".utf8) + [UInt8](repeating: 0, count: 100)
        let url = dir.write("big.dll", Data(bytes))
        #expect(DirectXUsage.detect(in: url) == [.d3d12])
        #expect(BinaryScan.find(["d3d12.dll", "mscoree.dll"], in: url) == ["d3d12.dll"])
        #expect(DirectXUsage.detect(in: url, maxBytes: 1 << 20) == [])
    }
}
