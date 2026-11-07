import Foundation

public struct LogLine: Identifiable, Equatable, Sendable {
    public enum Stream: String, Sendable { case stdout, stderr, alloy }
    public let id: Int
    public let date: Date
    public let stream: Stream
    public let text: String
}

public enum LaunchState: Equatable, Sendable {
    case idle
    case running(pid: Int32)
    case exited(code: Int32)
    case terminatedBySignal(Int32)
    case failed(String)

    public var isRunning: Bool { if case .running = self { return true }; return false }

    public var summary: String {
        switch self {
        case .idle: return "Not running"
        case .running(let pid): return "Running (pid \(pid))"
        case .exited(let code): return code == 0 ? "Exited normally (code 0)" : "Exited with code \(code)"
        case .terminatedBySignal(let s): return "Stopped (signal \(s))"
        case .failed(let message): return "Failed to start: \(message)"
        }
    }
}

/// One run of one command. Captures stdout/stderr line by line, redacted, into memory and a log file.
public final class LaunchSession: @unchecked Sendable {
    public let command: LaunchCommand
    public let logFile: URL?
    public var onLine: (@Sendable (LogLine) -> Void)?
    public var onStateChange: (@Sendable (LaunchState) -> Void)?

    private let lock = NSLock()
    private var _lines: [LogLine] = []
    private var _state: LaunchState = .idle
    private var nextID = 0
    private var _launcherExited = false
    private var partial: [LogLine.Stream: String] = [:]
    private let process = Process()
    /// Guarded by `logLock`. Wine's helper processes inherit the pipes and can keep writing after the launcher
    /// exits, so the file stays open until both pipes reach EOF, and every write checks it is still open.
    private var logHandle: FileHandle?
    private let logLock = NSLock()
    private let exitGroup = DispatchGroup()
    private let readers = DispatchGroup()
    /// The two readers and the exit handler; the log file closes when all three are done.
    private let logWriters = DispatchGroup()
    private let maxLines = 20_000
    /// When the session started. Log file lines carry the seconds since then, so a slow start shows where the time went.
    private let started = Date()

    public init(command: LaunchCommand, logFile: URL?) {
        self.command = command
        self.logFile = logFile
    }

    public var lines: [LogLine] { lock.withLock { _lines } }
    public var state: LaunchState { lock.withLock { _state } }
    public var fullLog: String { lines.map(\.text).joined(separator: "\n") }

    /// Starts the process directly via `Process` — no shell, so arguments cannot be reinterpreted.
    public func start() throws {
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !EnvironmentValidator.blockedPrefixes.contains { key.hasPrefix($0) }
        }
        env.merge(command.environment) { _, new in new }
        process.environment = env

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        if let logFile {
            try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            logHandle = try? FileHandle(forWritingTo: logFile)
        }
        attach(out.fileHandleForReading, stream: .stdout)
        attach(err.fileHandleForReading, stream: .stderr)

        exitGroup.enter()
        logWriters.enter()
        logWriters.notify(queue: .global()) { [weak self] in self?.closeLog() }
        process.terminationHandler = { [weak self] p in
            guard let self else { return }
            let state: LaunchState = p.terminationReason == .uncaughtSignal
                ? .terminatedBySignal(p.terminationStatus) : .exited(code: p.terminationStatus)
            self.lock.withLock { self._launcherExited = true }
            // Let the readers finish what is buffered. Processes that inherited the pipes keep them open: for a game
            // that is the game itself, so the session runs on until they exit; for anything else, Wine's helpers.
            if self.readers.wait(timeout: .now() + 2) == .timedOut && self.command.waitsForChildProcesses {
                self.append(.alloy, "[Alloy] Launcher exited (\(state.summary.lowercased())); the game is still running")
                self.readers.notify(queue: .global()) { self.finish(state) }
            } else {
                self.finish(state)
            }
        }

        append(.alloy, "[Alloy] Starting \(command.executable.lastPathComponent) \(ArgumentParser.join(command.arguments))")
        for text in command.notes { append(.alloy, "[Alloy] \(text)") }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            // Lets the reader threads see EOF instead of blocking forever; the log closes once they have.
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            exitGroup.leave()
            let state = LaunchState.failed(error.localizedDescription)
            append(.alloy, "[Alloy] \(state.summary)")
            setState(state)
            logWriters.leave()
            throw AlloyError.launchFailed(error.localizedDescription)
        }
        setState(.running(pid: process.processIdentifier))
    }

    /// Adds an Alloy line to the session's log.
    public func note(_ text: String) { append(.alloy, "[Alloy] \(text)") }

    /// The launcher process has exited; Windows processes it started may still be running.
    public var launcherHasExited: Bool { lock.withLock { _launcherExited } }

    /// Sends SIGTERM, then SIGKILL after `grace` seconds if the process is still alive. Returns false when the
    /// launcher had already exited: what still runs is in the Wine environment (end it with `wineserver -k`).
    @discardableResult
    public func stop(grace: TimeInterval = 3) -> Bool {
        guard process.isRunning else { return false }
        append(.alloy, "[Alloy] Stop requested")
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
            if self?.process.isRunning == true { kill(pid, SIGKILL) }
        }
        return true
    }

    @discardableResult
    public func waitUntilExit(timeout: TimeInterval? = nil) -> LaunchState {
        if let timeout { _ = exitGroup.wait(timeout: .now() + timeout) } else { exitGroup.wait() }
        return state
    }

    public func waitForExit() async -> LaunchState {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async { cont.resume(returning: self.waitUntilExit()) }
        }
    }

    // MARK: Internals

    /// One reader thread per pipe, using read(2): it returns whatever has arrived. `read(upToCount:)` waits for the
    /// full count or EOF, which held a quiet program's lines (a frozen game's last ones) until it exited, and
    /// `availableData` raises an Objective-C exception (and aborts the process) if the handle is closed underneath it.
    private func attach(_ handle: FileHandle, stream: LogLine.Stream) {
        readers.enter()
        logWriters.enter()
        let group = logWriters
        Thread.detachNewThread { [weak self] in
            defer { self?.readers.leave(); group.leave() }
            let fd = handle.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    self?.ingest(Data(buffer[..<count]), stream: stream)
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            withExtendedLifetime(handle) {}
        }
    }

    private func finish(_ state: LaunchState) {
        flushPartial(.stdout)
        flushPartial(.stderr)
        append(.alloy, "[Alloy] \(state.summary)")
        setState(state)
        exitGroup.leave()
        logWriters.leave()
    }

    private func flushPartial(_ stream: LogLine.Stream) {
        let leftover: String? = lock.withLock { partial.removeValue(forKey: stream) }
        if let leftover, !leftover.isEmpty { append(stream, leftover) }
    }

    private func ingest(_ data: Data, stream: LogLine.Stream) {
        let text = String(decoding: data, as: UTF8.self)
        let complete: [String] = lock.withLock {
            let combined = (partial[stream] ?? "") + text
            var parts = combined.components(separatedBy: "\n")
            partial[stream] = parts.removeLast()
            return parts
        }
        for line in complete { append(stream, line) }
    }

    private func append(_ stream: LogLine.Stream, _ raw: String) {
        let text = LogRedactor.redact(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        let line: LogLine = lock.withLock {
            let line = LogLine(id: nextID, date: Date(), stream: stream, text: text)
            nextID += 1
            _lines.append(line)
            if _lines.count > maxLines { _lines.removeFirst(_lines.count - maxLines) }
            return line
        }
        writeLog(String(format: "[%7.2fs] ", line.date.timeIntervalSince(started)) + text + "\n")
        onLine?(line)
    }

    /// The throwing `write(contentsOf:)`: the older `write(_:)` raises an Objective-C exception (and aborts the app)
    /// on a closed handle or a full disk.
    private func writeLog(_ text: String) {
        logLock.withLock { try? logHandle?.write(contentsOf: Data(text.utf8)) }
    }

    private func closeLog() {
        logLock.withLock {
            try? logHandle?.close()
            logHandle = nil
        }
    }

    private func setState(_ state: LaunchState) {
        lock.withLock { _state = state }
        onStateChange?(state)
    }
}

/// Builds sessions with a per-run log file and tracks one running session per game.
public final class GameLauncher: @unchecked Sendable {
    public let logsDirectory: URL
    private let lock = NSLock()
    private var sessions: [UUID: LaunchSession] = [:]

    public init(logsDirectory: URL) {
        self.logsDirectory = logsDirectory
    }

    public func session(for gameID: UUID) -> LaunchSession? { lock.withLock { sessions[gameID] } }

    /// `onLine` is set before the process starts, so it sees every line.
    public func launch(gameID: UUID, gameName: String, command: LaunchCommand,
                       onLine: (@Sendable (LogLine) -> Void)? = nil) throws -> LaunchSession {
        if let existing = session(for: gameID), existing.state.isRunning { throw AlloyError.alreadyRunning }
        let session = LaunchSession(command: command, logFile: logFileURL(name: gameName))
        session.onLine = onLine
        lock.withLock { sessions[gameID] = session }
        // Links Wine left behind for a runtime folder that has since moved would stop it from starting.
        let dead = WineTemporaryFiles.removeDeadLinks()
        if dead > 0 { session.note("Removed \(dead) out-of-date Wine link\(dead == 1 ? "" : "s") from the temporary folder") }
        try session.start()
        return session
    }

    /// False when the game's launcher had already exited (see `LaunchSession.stop`).
    @discardableResult
    public func stop(gameID: UUID) -> Bool { session(for: gameID)?.stop() ?? false }

    public func logFileURL(name: String, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return logsDirectory.appendingPathComponent("\(PrefixManager.slug(name))-\(formatter.string(from: date)).log")
    }
}
