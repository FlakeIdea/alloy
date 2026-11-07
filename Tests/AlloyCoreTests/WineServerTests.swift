import Foundation
import Testing
@testable import AlloyCore

@Suite struct WineServerTests {
    func setup(server: WineServer.State) -> (WineBackend, WineRuntime, WinePrefix, Game, TempDir) {
        let dir = TempDir()
        var runtime = MetalFXDLSSTests().runtime(in: dir, d3dMetal: false)
        runtime.hasMSync = true
        var backend = WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in nil })
        backend.serverProbe = { _ in server }
        var game = makeGame(in: dir)
        game.graphics.backend = .dxmt
        return (backend, runtime, makeInitializedPrefix(in: dir), game, dir)
    }

    @Test func followsTheGameWhenNothingRuns() throws {
        var (backend, runtime, prefix, game, dir) = setup(server: .stopped); defer { withExtendedLifetime(dir) {} }
        var cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["WINEMSYNC"] == "1" && cmd.notes.isEmpty)
        game.graphics.syncMode = .off
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["WINEMSYNC"] == nil && cmd.notes.isEmpty)
        backend.serverProbe = { _ in .running(msync: false) }
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["WINEMSYNC"] == nil && cmd.notes.isEmpty)
    }

    @Test func followsARunningServerWithADifferentSetting() throws {
        var (backend, runtime, prefix, game, dir) = setup(server: .running(msync: true)); defer { withExtendedLifetime(dir) {} }
        game.graphics.syncMode = .off
        var cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["WINEMSYNC"] == "1")
        #expect(cmd.notes.first?.contains("MSync stays on") == true)

        backend.serverProbe = { _ in .running(msync: false) }
        game.graphics.syncMode = .default
        cmd = try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
        #expect(cmd.environment["WINEMSYNC"] == nil)
        #expect(cmd.notes.count == 1)
        let tool = try backend.wineToolCommand(["reg", "add"], prefix: prefix, runtime: runtime)
        #expect(tool.environment["WINEMSYNC"] == nil)
    }

    @Test func stoppedForAMissingPrefix() {
        let dir = TempDir()
        #expect(WineServer.state(of: makeInitializedPrefix(in: dir)) == .stopped)
        #expect(WineServer.identity(of: dir.url)?.folder.hasPrefix("/tmp/.wine-\(getuid())/server-") == true)
    }

    @Test func explainsTheMismatchInPlainEnglish() {
        let log = "00ec:err:sync:msync_init Server is running with WINEMSYNC but this process is not, please enable WINEMSYNC or restart wineserver."
        let f = DiagnosticService.analyze(log: log, exitState: .exited(code: 1)).first { $0.kind == .wineserverMismatch }
        #expect(f?.title == "Another program in this environment uses a different setting")
        #expect(f?.fixes == [.stopEnvironment])
    }
}
