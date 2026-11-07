import Foundation
import Testing
@testable import AlloyCore

/// End-to-end tests against a real Wine install. Opt-in: `ALLOY_WINE_INTEGRATION=1 scripts/test.sh`.
/// Only Wine's own built-in programs run; the prefix lives in a temporary folder and is deleted afterwards.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ALLOY_WINE_INTEGRATION"] == "1"))
struct WineIntegrationTests {
    let backend = WineBackend()

    func runtime() throws -> WineRuntime {
        try #require(backend.discoverRuntimes().first, "No Wine runtime installed")
    }

    func run(_ command: LaunchCommand, timeout: TimeInterval) -> LaunchSession {
        let session = LaunchSession(command: command, logFile: nil)
        try? session.start()
        session.waitUntilExit(timeout: timeout)
        return session
    }

    @Test func discoversInstalledRuntime() throws {
        let r = try runtime()
        #expect(r.version != nil)
        #expect(r.requiresRosetta)
        let caps = backend.capabilities(of: r)
        #expect(caps.status(of: .wined3dOpenGL) == .available)
        print("Runtime: \(r.displayName) archs=\(r.architectures) MoltenVK=\(r.hasMoltenVK) D3DMetal=\(r.hasD3DMetal)")
    }

    @Test func initialisesPrefixAndRunsBuiltInProgram() throws {
        let r = try runtime()
        let dir = TempDir()
        let manager = PrefixManager(storageRoot: dir.url, crossOverBottlesRoot: nil)
        let prefix = try manager.createPrefix(name: "Integration", runtimeID: r.id)
        defer { _ = run(backend.stopPrefixCommand(prefix: prefix, runtime: r), timeout: 30) }

        let start = Date()
        let boot = run(try backend.initializePrefixCommand(prefix: prefix, runtime: r), timeout: 300)
        print("wineboot: \(boot.state.summary) in \(Int(Date().timeIntervalSince(start)))s")
        #expect(boot.state == .exited(code: 0))
        #expect(prefix.isInitialized())

        // Treat Wine's built-in cmd.exe as the "game": a real PE file inside a folder, launched through Alloy.
        let cmd = prefix.system32.appendingPathComponent("cmd.exe")
        let info = try PEInspector.inspect(cmd)
        print("cmd.exe: \(info)")
        var game = Game(name: "cmd", folder: prefix.system32, executableRelativePath: "cmd.exe",
                        arguments: ["/c", "echo", "ALLOY_OK", "&", "ver"])
        game.graphics.metalHUD = true
        let command = try backend.launchCommand(for: game, prefix: prefix, runtime: r, options: LaunchOptions())
        let session = run(command, timeout: 120)
        print(session.fullLog)
        #expect(session.state == .exited(code: 0))
        #expect(session.lines.contains { $0.text.contains("ALLOY_OK") })
        let findings = DiagnosticService.analyze(log: session.fullLog, exitState: session.state)
        #expect(!findings.contains { $0.severity == .error })

        // A failing program must surface a non-zero exit code and a diagnostic.
        game.arguments = ["/c", "exit", "7"]
        let failing = run(try backend.launchCommand(for: game, prefix: prefix, runtime: r, options: LaunchOptions()), timeout: 120)
        #expect(failing.state == .exited(code: 7))
        #expect(DiagnosticService.analyze(log: failing.fullLog, exitState: failing.state).contains { $0.kind == .nonZeroExit })
    }
}
