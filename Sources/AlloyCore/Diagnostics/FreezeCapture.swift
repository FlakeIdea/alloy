import Foundation

/// Saves a backtrace of every Windows thread in a game's environment (winedbg's "bt all"), so a freeze can be traced
/// to the locks its threads wait on. Wine prints "wait timed out in thread …" once a thread has waited 5 seconds for a
/// lock, and every minute after that; `watch` captures on that line. The report is a plain file beside the game's log
/// and stays on this Mac.
public enum FreezeCapture {
    public static let trigger = "wait timed out in thread"

    public static func command(like launch: LaunchCommand) -> LaunchCommand {
        var environment = launch.environment
        // winedbg's own trace output would bury the backtraces.
        environment["WINEDEBUG"] = "-all"
        return LaunchCommand(executable: launch.executable, arguments: ["winedbg", "--command", "bt all"],
                             environment: environment)
    }

    /// `<log name>-threads-<time>.txt` beside the game's log, so several captures of one session do not overwrite.
    public static func reportURL(besideLog log: URL, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let name = log.deletingPathExtension().lastPathComponent
        return log.deletingLastPathComponent().appendingPathComponent("\(name)-threads-\(formatter.string(from: date)).txt")
    }

    /// Blocking; run it off the main thread. Attaching pauses the game's threads for a moment and then lets them
    /// continue. False when winedbg did not finish within `timeout` (the report then holds what it printed so far).
    @discardableResult
    public static func capture(like launch: LaunchCommand, to report: URL, timeout: TimeInterval = 120) throws -> Bool {
        let session = LaunchSession(command: command(like: launch), logFile: report)
        try session.start()
        let state = session.waitUntilExit(timeout: timeout)
        if state.isRunning { session.stop(); return false }
        return true
    }

    /// Captures on `trigger` lines of `session`, keeping any `onLine` handler already set, and calls `saved` with
    /// each report once it is written. A wait that clears (a long load) would otherwise use up the capture before a
    /// real freeze, so it captures up to `limit` times, at least `spacing` seconds apart.
    public static func watch(_ session: LaunchSession, limit: Int = 3, spacing: TimeInterval = 60,
                             saved: @escaping @Sendable (URL) -> Void = { _ in }) {
        guard let log = session.logFile else { return }
        let budget = Budget(limit: limit, spacing: spacing)
        let previous = session.onLine
        session.onLine = { [weak session] line in
            previous?(line)
            guard let session, line.stream != .alloy, line.text.contains(trigger), budget.claim(at: line.date) else { return }
            let report = reportURL(besideLog: log)
            session.note("A thread is stuck waiting on a lock; saving every thread’s backtrace to \(report.lastPathComponent)")
            DispatchQueue.global().async {
                do {
                    let finished = try capture(like: session.command, to: report)
                    session.note(finished ? "Saved thread backtraces to \(report.path)"
                                          : "winedbg did not finish; saved what it printed to \(report.path)")
                    saved(report)
                } catch {
                    session.note("Could not save thread backtraces: \(error.localizedDescription)")
                }
            }
        }
    }

    final class Budget: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private let spacing: TimeInterval
        private var used = 0
        private var last: Date?

        init(limit: Int, spacing: TimeInterval) { self.limit = limit; self.spacing = spacing }

        func claim(at date: Date) -> Bool {
            lock.withLock {
                guard used < limit, last.map({ date.timeIntervalSince($0) >= spacing }) ?? true else { return false }
                used += 1
                last = date
                return true
            }
        }
    }
}
