import Foundation
import Testing
@testable import AlloyCore

@Suite struct WineUpdateTests {
    @Test func refreshesAnEnvironmentMovedToAnotherEngine() throws {
        let dir = TempDir()
        let runtime = makeFakeRuntime(in: dir)
        let prefix = makeInitializedPrefix(in: dir)
        let inf = runtime.wineBinary.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/wine/wine.inf")
        try FileManager.default.createDirectory(at: inf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: inf)
        let modified = Date(timeIntervalSince1970: 1_794_052_477)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: inf.path)
        let stamp = prefix.path.appendingPathComponent(".update-timestamp")

        #expect(prefix.needsWineUpdate(for: runtime))                     // no stamp yet
        try "1793440927\n".write(to: stamp, atomically: true, encoding: .utf8)
        #expect(prefix.needsWineUpdate(for: runtime))                     // stamp from the old engine
        try "1794052477\n".write(to: stamp, atomically: true, encoding: .utf8)
        #expect(!prefix.needsWineUpdate(for: runtime))                    // up to date
        try "disable\n".write(to: stamp, atomically: true, encoding: .utf8)
        #expect(!prefix.needsWineUpdate(for: runtime))
    }

    @Test func refreshRunsWinebootUpdateWithoutTheMonoPrompt() throws {
        let dir = TempDir()
        let cmd = try WineBackend().updatePrefixCommand(prefix: makeInitializedPrefix(in: dir), runtime: makeFakeRuntime(in: dir))
        #expect(cmd.arguments == ["wineboot", "--update"])
        #expect(cmd.environment["WINEDLLOVERRIDES"] == "mscoree,mshtml=")
    }
}
