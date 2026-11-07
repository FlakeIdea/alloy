import Foundation
import Testing
@testable import AlloyCore

@Suite struct ShaderCacheTests {
    @Test func copiesTheLargestEarlierCacheOnce() throws {
        let dir = TempDir()
        let game = makeGame(in: dir, exe: "Playtime.exe")
        dir.write("Game/Playtime/Binaries/Win64/Playtime-Win64-Shipping.exe", Data())
        #expect(ShaderCache.programNames(for: game) == ["Playtime.exe", "Playtime-Win64-Shipping.exe"])
        let system = dir.url.appendingPathComponent("C")
        // A launcher stub's small cache and the Unreal Engine game's real one.
        dir.write("C/dxmt/Playtime.exe/shaders_320.db", Data("small".utf8))
        dir.write("C/dxmt/Playtime-Win64-Shipping.exe/shaders_320.db", Data(repeating: 1, count: 4096))
        dir.write("C/dxmt/Playtime-Win64-Shipping.exe/shaders_320.db-wal", Data(repeating: 2, count: 512))
        dir.write("C/dxmt/Playtime-Win64-Shipping.exe/shaders_320.db-shm", Data(repeating: 3, count: 64))
        dir.write("C/dxmt/Playtime-Win64-Shipping.exe/shaders_320.db-lock", Data())
        dir.write("C/dxmt/Other.exe/shaders_320.db", Data(repeating: 9, count: 9000))
        let support = dir.url.appendingPathComponent("Support")
        let folder = try #require(ShaderCache.prepare(for: game, supportDirectory: support, systemCacheDirectory: system))
        #expect(folder.path == support.appendingPathComponent("ShaderCache/\(game.id.uuidString)").path)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["metal", "shaders_320.db", "shaders_320.db-wal"])
        #expect(try Data(contentsOf: folder.appendingPathComponent("shaders_320.db")).count == 4096)
        // The originals stay.
        #expect(FileManager.default.fileExists(atPath: system.appendingPathComponent("dxmt/Playtime-Win64-Shipping.exe/shaders_320.db").path))
        // Once the game has its own cache, nothing is copied over it.
        try Data("grown".utf8).write(to: folder.appendingPathComponent("shaders_320.db"))
        _ = ShaderCache.prepare(for: game, supportDirectory: support, systemCacheDirectory: system)
        #expect(try Data(contentsOf: folder.appendingPathComponent("shaders_320.db")) == Data("grown".utf8))
        #expect(ShaderCache.size(for: game.id, supportDirectory: support) > 0)
    }

    @Test func keepsMetalsCacheInTheGamesFolder() throws {
        let fm = FileManager.default
        let dir = TempDir()
        let game = makeGame(in: dir, exe: "Game.exe")
        let system = dir.url.appendingPathComponent("C")
        dir.write("C/dxmt/Game.exe/com.apple.metal/32024/pipelines.bin", Data("pso".utf8))
        let support = dir.url.appendingPathComponent("Support")
        let folder = try #require(ShaderCache.prepare(for: game, supportDirectory: support, systemCacheDirectory: system))
        let link = system.appendingPathComponent("dxmt/Game.exe/com.apple.metal")
        let target = folder.appendingPathComponent("metal/Game.exe")
        // The existing cache moved into the game's folder, and Metal finds it through the link.
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try Data(contentsOf: link.appendingPathComponent("32024/pipelines.bin")) == Data("pso".utf8))
        // macOS clears its cache folder: the next start links the kept cache again.
        try fm.removeItem(at: system)
        _ = ShaderCache.prepare(for: game, supportDirectory: support, systemCacheDirectory: system)
        #expect(try Data(contentsOf: link.appendingPathComponent("32024/pipelines.bin")) == Data("pso".utf8))
        // Another game with the same program name gets the link; the first game's cache stays in its own folder.
        let other = Game(name: "Other", folder: game.folder, executableRelativePath: "Game.exe")
        let otherFolder = try #require(ShaderCache.prepare(for: other, supportDirectory: support, systemCacheDirectory: system))
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == otherFolder.appendingPathComponent("metal/Game.exe").path)
        #expect(fm.fileExists(atPath: target.appendingPathComponent("32024/pipelines.bin").path))
    }

    @Test func makesAnEmptyFolderWithoutEarlierCache() throws {
        let dir = TempDir()
        let game = makeGame(in: dir)
        let folder = try #require(ShaderCache.prepare(for: game, supportDirectory: dir.url.appendingPathComponent("S"),
                                                      systemCacheDirectory: dir.url.appendingPathComponent("none")))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["metal"])
        #expect(ShaderCache.systemCacheDirectory()?.path.hasPrefix("/") == true)
    }

    @Test func dxmtUsesTheFolderUnlessTheGameSetsItsOwn() throws {
        let dir = TempDir()
        let backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        let runtime = MetalFXDLSSTests().runtime(in: dir, d3dMetal: false)
        let prefix = makeInitializedPrefix(in: dir)
        var game = makeGame(in: dir)
        game.graphics.backend = .dxmt
        let cache = dir.url.appendingPathComponent("Cache")
        var cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions(shaderCacheDirectory: cache))
        #expect(cmd.environment["DXMT_SHADER_CACHE_PATH"] == cache.path)
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["DXMT_SHADER_CACHE_PATH"] == nil)
        game.graphics.shaderCachePath = "/Volumes/Fast/cache"
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions(shaderCacheDirectory: cache))
        #expect(cmd.environment["DXMT_SHADER_CACHE_PATH"] == "/Volumes/Fast/cache")
    }
}
