import Foundation
import Testing
@testable import AlloyCore

/// These tests run only `/bin/sh` with fixed scripts, as a stand-in for a Windows program.
@Suite struct LauncherTests {
    @Test func capturesOutputErrorsAndExitCode() throws {
        let dir = TempDir()
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "echo out-line; echo err-line >&2; printf partial; exit 3"],
                                    environment: ["ALLOY_TEST": "1"], workingDirectory: dir.url)
        let launcher = GameLauncher(logsDirectory: dir.url.appendingPathComponent("logs"))
        let id = UUID()
        let session = try launcher.launch(gameID: id, gameName: "Sh Test", command: command)
        let state = session.waitUntilExit(timeout: 10)
        #expect(state == .exited(code: 3))
        let texts = session.lines.map(\.text)
        #expect(texts.contains("out-line"))
        #expect(texts.contains("partial"))
        #expect(session.lines.contains { $0.stream == .stderr && $0.text == "err-line" })
        let file = try #require(session.logFile)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("err-line"))
        #expect(saved.contains("Exited with code 3"))
    }

    /// Wine's helper processes inherit the pipes and keep printing after the launcher exits. That used to write
    /// to a closed log handle and abort the app.
    @Test func outputAfterExitIsLoggedWithoutCrashing() throws {
        let dir = TempDir()
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "(sleep 2.5; echo late-line) & echo early-line"],
                                    workingDirectory: dir.url)
        let session = LaunchSession(command: command, logFile: dir.url.appendingPathComponent("late.log"))
        try session.start()
        #expect(session.waitUntilExit(timeout: 10) == .exited(code: 0))
        let deadline = Date().addingTimeInterval(5)
        while !session.lines.contains(where: { $0.text == "late-line" }) && Date() < deadline { usleep(50_000) }
        #expect(session.lines.contains { $0.text == "late-line" })
        let saved = try String(contentsOf: dir.url.appendingPathComponent("late.log"), encoding: .utf8)
        #expect(saved.contains("early-line"))
        #expect(saved.contains("Exited normally"))
        #expect(saved.contains("late-line"))
        // Each line in the file starts with the seconds since the session began.
        #expect(saved.split(separator: "\n").allSatisfy { $0.range(of: #"^\[ *\d+\.\d\ds\] "#, options: .regularExpression) != nil })
    }

    /// Unreal Engine launchers start the real game and exit; the session must keep running until it ends.
    @Test func gameSessionRunsUntilChildProcessesExit() throws {
        let dir = TempDir()
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "(sleep 3; echo game-done) & echo launcher-done"],
                                    workingDirectory: dir.url, waitsForChildProcesses: true)
        let session = LaunchSession(command: command, logFile: nil)
        try session.start()
        Thread.sleep(forTimeInterval: 2.5)
        #expect(session.state.isRunning && session.launcherHasExited)
        #expect(!session.stop())   // the launcher is gone; Alloy ends the rest with wineserver -k
        #expect(session.waitUntilExit(timeout: 10) == .exited(code: 0))
        let texts = session.lines.map(\.text)
        #expect(texts.contains("game-done"))
        #expect(texts.last == "[Alloy] Exited normally (code 0)")
    }

    @Test func preservesWorkingDirectoryAndEnvironment() throws {
        let dir = TempDir()
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "pwd -P; echo \"$ALLOY_TEST\""],
                                    environment: ["ALLOY_TEST": "value with spaces"], workingDirectory: dir.url)
        let session = LaunchSession(command: command, logFile: nil)
        try session.start()
        session.waitUntilExit(timeout: 10)
        let texts = session.lines.map(\.text)
        #expect(texts.contains { $0.hasSuffix("/" + dir.url.lastPathComponent) })
        #expect(texts.contains("value with spaces"))
    }

    @Test func argumentsAreNotInterpretedByAShell() throws {
        let dir = TempDir()
        let marker = dir.url.appendingPathComponent("pwned")
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/echo"),
                                    arguments: ["$(touch \(marker.path))", "; touch \(marker.path)"])
        let session = LaunchSession(command: command, logFile: nil)
        try session.start()
        session.waitUntilExit(timeout: 10)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func stopTerminatesAndRejectsDoubleLaunch() throws {
        let dir = TempDir()
        let launcher = GameLauncher(logsDirectory: dir.url)
        let id = UUID()
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        let session = try launcher.launch(gameID: id, gameName: "sleep", command: command)
        #expect(session.state.isRunning)
        #expect(throws: AlloyError.alreadyRunning) { try launcher.launch(gameID: id, gameName: "sleep", command: command) }
        launcher.stop(gameID: id)
        #expect(session.waitUntilExit(timeout: 10) == .terminatedBySignal(15))
    }

    /// A frozen game prints nothing more, so its last lines must arrive without waiting for more output or exit.
    @Test func linesArriveWhileTheProgramIsStillRunning() throws {
        let command = LaunchCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "echo first-line; echo err-line >&2; sleep 10"])
        let session = LaunchSession(command: command, logFile: nil)
        try session.start()
        defer { session.stop() }
        let deadline = Date().addingTimeInterval(3)
        while session.lines.filter({ $0.text.hasSuffix("-line") }).count < 2 && Date() < deadline { usleep(50_000) }
        #expect(session.state.isRunning)
        #expect(session.lines.contains { $0.stream == .stdout && $0.text == "first-line" })
        #expect(session.lines.contains { $0.stream == .stderr && $0.text == "err-line" })
    }

    @Test func missingExecutableFailsCleanly() {
        let session = LaunchSession(command: LaunchCommand(executable: URL(fileURLWithPath: "/nonexistent/wine"), arguments: []),
                                    logFile: nil)
        #expect(throws: AlloyError.self) { try session.start() }
        if case .failed = session.state {} else { Issue.record("expected failed state, got \(session.state)") }
    }
}

@Suite struct FreezeCaptureTests {
    static let stuckLine = #"0170:err:sync:RtlpWaitForCriticalSection section 000000002DAA6068 "?" wait timed out in thread 0170, blocked by 00d8, retrying (60 sec)"#

    @Test func runsWinedbgQuietlyInTheGamesEnvironment() {
        let launch = LaunchCommand(executable: URL(fileURLWithPath: "/rt/bin/wine"), arguments: ["C:\\Game\\Game.exe"],
                                   environment: ["WINEPREFIX": "/p", "WINEDEBUG": "+relay", "WINEMSYNC": "1"],
                                   waitsForChildProcesses: true)
        let command = FreezeCapture.command(like: launch)
        #expect(command.executable == launch.executable)
        #expect(command.arguments == ["winedbg", "--command", "bt all"])
        #expect(command.environment["WINEPREFIX"] == "/p" && command.environment["WINEMSYNC"] == "1")
        #expect(command.environment["WINEDEBUG"] == "-all")
        #expect(!command.waitsForChildProcesses)
    }

    @Test func reportSitsBesideTheLog() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 3, minute: 41, second: 7)))
        let log = URL(fileURLWithPath: "/Logs/game-20261101-033750.log")
        #expect(FreezeCapture.reportURL(besideLog: log, date: date).path == "/Logs/game-20261101-033750-threads-034107.txt")
    }

    /// A long load can stall a thread for 5 seconds; the capture budget must outlast it for a real freeze later.
    @Test func capturesAFewTimesAtMostOncePerMinute() {
        let budget = FreezeCapture.Budget(limit: 2, spacing: 60)
        let start = Date()
        #expect(budget.claim(at: start))
        #expect(!budget.claim(at: start.addingTimeInterval(10)))
        #expect(budget.claim(at: start.addingTimeInterval(61)))
        #expect(!budget.claim(at: start.addingTimeInterval(200)))
    }

    /// A stand-in for Wine: run as `winedbg`, it prints a backtrace; otherwise it reports a stuck thread and waits.
    @Test func savesBacktracesWhenAThreadIsStuck() throws {
        let dir = TempDir()
        let script = """
        #!/bin/sh
        if [ "$1" = winedbg ]; then echo "Backtracing for thread 0170 in process 0020"; exit 0; fi
        echo '\(Self.stuckLine)' >&2
        sleep 10
        """
        let wine = dir.write("bin/wine", Data(script.utf8), executable: true)
        let session = LaunchSession(command: LaunchCommand(executable: wine, arguments: ["Game.exe"]),
                                    logFile: dir.url.appendingPathComponent("game-20261101-033750.log"))
        let saved = Locked<URL?>(nil)
        FreezeCapture.watch(session) { saved.set($0) }
        try session.start()
        defer { session.stop() }
        let deadline = Date().addingTimeInterval(5)
        while saved.get() == nil && Date() < deadline { usleep(50_000) }
        let report = try #require(saved.get())
        #expect(report.lastPathComponent.hasPrefix("game-20261101-033750-threads-"))
        let text = try String(contentsOf: report, encoding: .utf8)
        #expect(text.contains("Backtracing for thread 0170"))
        #expect(session.state.isRunning)
        #expect(session.lines.contains { $0.text.hasPrefix("[Alloy] Saved thread backtraces to") })
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ new: Value) { lock.withLock { value = new } }
}

@Suite struct DiagnosticsTests {
    @Test func reportsAThreadStuckOnALock() throws {
        let findings = DiagnosticService.analyze(log: FreezeCaptureTests.stuckLine, exitState: .terminatedBySignal(15))
        let f = try #require(findings.first { $0.kind == .freeze })
        #expect(f.detail.contains("thread 0170") && f.detail.contains("thread 00d8"))
        #expect(f.suggestion.contains("-threads"))
    }

    @Test func detectsMissingDLLWithSuggestion() {
        let log = #"0024:err:module:import_dll Library MSVCP140.dll (which is needed by L"C:\\Game\\Game.exe") not found"#
        let findings = DiagnosticService.analyze(log: log)
        let f = try! #require(findings.first { $0.kind == .missingDLL })
        #expect(f.title == "Missing DLL: MSVCP140.dll")
        #expect(f.suggestion.contains("Visual C++"))
    }

    @Test func detectsCommonFailureSignatures() {
        let log = """
        arch: posix_spawnp: /Applications/Wine.app/wine: Bad CPU type in executable
        wine: Unhandled page fault on read access to 0000000000000000
        LowLevelFatalError: DX11 feature level 10.0 is required to run the engine.
        wine client error:0: version mismatch 812/790.
        Starting EasyAntiCheat service
        """
        let kinds = Set(DiagnosticService.analyze(log: log, exitState: .exited(code: 1)).map(\.kind))
        #expect(kinds.isSuperset(of: [.rosettaMissing, .crash, .directX12Unsupported, .wineserverMismatch, .antiCheat, .nonZeroExit]))
    }

    @Test func errorsSortBeforeInfo() {
        let log = "wine: Unhandled exception 0xc0000005"
        let findings = DiagnosticService.analyze(log: log, exitState: .exited(code: 5), requestedGraphics: .dxvk)
        #expect(findings.first?.severity == .error)
        #expect(findings.last?.severity == .info)
    }

    @Test func graphicsBackendIsOnlyConfirmedWithEvidence() {
        let unconfirmed = GraphicsVerifier.verify(backend: .dxvk, log: "[Alloy] Starting wine DXVK: v1.10")
        #expect(unconfirmed?.kind == .graphicsBackendNotConfirmed)
        let confirmed = GraphicsVerifier.verify(backend: .dxvk, log: "info:  DXVK: v1.10.3")
        #expect(confirmed?.kind == .graphicsBackendConfirmed)
    }

    @Test func preflightReportsMissingRuntimeAndExecutable() {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.executableRelativePath = "gone.exe"
        let kinds = DiagnosticService.preflight(game: game, runtime: nil, prefix: nil).map(\.kind)
        #expect(kinds.contains(.runtimeMissing))
        #expect(kinds.contains(.badPath))
    }

    /// Seen with a 275-character folder path: Wine falls back to C:\windows and then cannot find the program.
    @Test func explainsFolderPathsTooLongForWindows() {
        let log = #"""
        wine: could not open working directory L"Z:\\private\\tmp\\very\\long\\dotnet"..., starting in the Windows directory.
        """#
        let findings = DiagnosticService.analyze(log: log)
        #expect(findings.map(\.title) == ["Game folder path is too long for Windows"])
        let missing = DiagnosticService.analyze(log: "wine: cannot find L\"C:\\Games\\x.exe\"")
        #expect(missing.first?.title == "Executable path not found by Wine")
    }

    @Test func redactsHomeAndSecrets() {
        let text = "open /Users/alice/Games/x.exe password=hunter2 token: \"abc def\" api_key=XYZ"
        let out = LogRedactor.redact(text, homePath: "/Users/alice")
        #expect(out == "open ~/Games/x.exe password=<redacted> token: <redacted> api_key=<redacted>")
    }

    @Test func detectsUnsupportedFeatureLevelAndConfirmsRenderer() {
        let log = """
        00f8:err:winediag:wined3d_dll_init Using the OpenGL renderer.
        12:12:45 D3D11Render::D3D11Render(): feature level 10.0 is not supported
        """
        let findings = DiagnosticService.analyze(log: log, requestedGraphics: .wined3dOpenGL)
        #expect(findings.contains { $0.kind == .directX12Unsupported })
        #expect(findings.contains { $0.kind == .graphicsBackendConfirmed })
    }

    @Test func warnsAboutLongPaths() {
        let dir = TempDir()
        let deep = String(repeating: "very-long-folder-name/", count: 12)
        dir.write("G/\(deep)Game.exe", PEFixture.make())
        let game = Game(name: "x", folder: dir.url.appendingPathComponent("G"), executableRelativePath: "\(deep)Game.exe")
        #expect(DiagnosticService.preflight(game: game, runtime: nil, prefix: nil).contains { $0.subject == "pathlength" })
    }

    @Test func parsesSuperpositionResults() throws {
        let log = "Benchmark running\nBenchmark results:\n816\nAAAgQgAAjEIAAFxCAwAAAAAASEIAAHBCAABcQg==\nUnigine~# quit\n"
        let r = try #require(SuperpositionResult.parse(log: log))
        #expect(r.minFPS == 40 && r.maxFPS == 70 && r.averageFPS == 55)
        #expect(r.sceneAverages == [50, 60, 55])
        #expect(SuperpositionResult.parse(log: "Benchmark failed (incorrect settings)") == nil)
    }

    @Test func redactsSteamIDs() {
        #expect(LogRedactor.redact("Caching Steam ID:  76561198000000001 [API loaded no]", homePath: "/x")
                == "Caching Steam ID:  <steamid> [API loaded no]")
    }

    @Test func exportsRedactedReport() throws {
        let dir = TempDir()
        let game = makeGame(in: dir)
        let log = "line token=SECRET123\nwine: Unhandled page fault"
        let report = DiagnosticReport(game: game, runtime: makeFakeRuntime(in: dir), prefix: makeInitializedPrefix(in: dir),
                                      state: .exited(code: 1), findings: DiagnosticService.analyze(log: log), log: log)
        let url = dir.url.appendingPathComponent("report.md")
        try report.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("# Alloy diagnostic report"))
        #expect(text.contains("The game crashed"))
        #expect(!text.contains("SECRET123"))
        #expect(text.contains("Exited with code 1"))
    }
}

@Suite struct PerformanceTests {
    func stats(_ times: [Double], budget: Double = 1000.0 / 60) -> FrameTimeStatistics { FrameTimeStatistics(frameTimesMs: times, budgetMs: budget)! }

    @Test func steadySixtyFPS() {
        let s = stats(Array(repeating: 16.0, count: 600))
        #expect(abs(s.averageFPS - 62.5) < 0.01)
        #expect(abs(s.onePercentLowFPS - 62.5) < 0.01)
        #expect(s.stutterCount == 0)
        #expect(s.meetsTarget(fps: 60))
    }

    @Test func stutterDragsDownOnePercentLows() {
        var times = Array(repeating: 10.0, count: 990)
        times += Array(repeating: 50.0, count: 10)
        let s = stats(times)
        #expect(s.averageFPS > 90)
        #expect(abs(s.onePercentLowFPS - 20) < 0.01)
        #expect(s.stutterCount == 10)
        #expect(s.p99FrameTimeMs == 50)
        #expect(!s.meetsTarget(fps: 60))
    }

    @Test func tooFewSamplesGivesNil() {
        #expect(FrameTimeStatistics(frameTimesMs: [16, 16, 16], budgetMs: 16.67) == nil)
    }

    @Test func parsesPresentMonAndMangoHudCSV() {
        let presentMon = "Application,ProcessID,MsBetweenPresents\ngame.exe,1,16.5\ngame.exe,1,17.0\n"
        #expect(FrameTimeCSV.parse(presentMon) == [16.5, 17.0])
        let mango = "os,cpu,gpu\nmacOS,M4,M4\nfps,frametime,cpu_load\n60,16.6,20\n59,16.9,21\n"
        #expect(FrameTimeCSV.parse(mango) == [16.6, 16.9])
        #expect(FrameTimeCSV.parse("8.3\n8.4\n") == [8.3, 8.4])
    }

    func run(_ label: String, quality: Int, fps: Double, lowFPS: Double, crashed: Bool = false, artifacts: [String] = []) -> BenchmarkRun {
        var times = Array(repeating: 1000 / fps, count: 990)
        times += Array(repeating: 1000 / lowFPS, count: 10)
        return BenchmarkRun(label: label, scene: "Ch1 intro", graphics: GraphicsConfiguration(), qualityScore: quality,
                            stats: stats(times), crashed: crashed, visualArtifacts: artifacts)
    }

    @Test func balancedPicksHighestQualityThatMeetsTarget() throws {
        let runs = [run("Ultra", quality: 100, fps: 52, lowFPS: 40),
                    run("High shadows", quality: 90, fps: 64, lowFPS: 52),
                    run("Medium", quality: 60, fps: 90, lowFPS: 75),
                    run("Broken", quality: 100, fps: 120, lowFPS: 100, artifacts: ["black water"])]
        let rec = try #require(OptimizationAdvisor.recommend(runs: runs, preset: .balanced, targetFPS: 60))
        #expect(rec.run.label == "High shadows")
        #expect(rec.meetsTarget)
    }

    @Test func highQualityAcceptsLowerFPS() throws {
        let runs = [run("Ultra", quality: 100, fps: 50, lowFPS: 40), run("Medium", quality: 60, fps: 90, lowFPS: 75)]
        #expect(OptimizationAdvisor.recommend(runs: runs, preset: .highQuality, targetFPS: 60)?.run.label == "Ultra")
    }

    @Test func highFPSKeepsQualityWhenGainIsInsignificant() throws {
        let runs = [run("High", quality: 90, fps: 118, lowFPS: 98), run("Low", quality: 40, fps: 122, lowFPS: 100)]
        #expect(OptimizationAdvisor.recommend(runs: runs, preset: .highFPS, targetFPS: 120)?.run.label == "High")
    }

    @Test func crashedRunsAreNeverRecommended() {
        #expect(OptimizationAdvisor.recommend(runs: [run("x", quality: 100, fps: 60, lowFPS: 60, crashed: true)],
                                              preset: .balanced, targetFPS: 60) == nil)
    }

    @Test func fallbackOrderIsQualityFirst() {
        let order = OptimizationAdvisor.fallbackOrder.map(\.category)
        #expect(order.first == "Compatibility")
        #expect(order.last == "Textures")
        #expect(order.firstIndex(of: "Shadows")! < order.firstIndex(of: "Render scale")!)
        #expect(OptimizationAdvisor.nextAdjustment(after: ["Compatibility", "Shader stutter"])?.category == "Volumetrics / effects")
    }

    @Test func benchmarkStorePersists() throws {
        let dir = TempDir()
        let file = dir.url.appendingPathComponent("bench.json")
        let gameID = UUID()
        let r = run("A", quality: 80, fps: 60, lowFPS: 50)
        try BenchmarkStore(fileURL: file).add(r, gameID: gameID)
        #expect(BenchmarkStore(fileURL: file).runs[gameID] == [r])
    }
}
