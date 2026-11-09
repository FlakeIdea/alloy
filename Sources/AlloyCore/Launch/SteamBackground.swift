import Darwin
import Foundation

/// Steam runs in the background while a game plays: its processes in the game's environment get macOS's background
/// priority (lowest CPU priority, efficiency cores on Apple silicon, throttled disk and network), and get their normal
/// priority back when no game is running there. Steam keeps working (downloads, friends, the game's Steam features),
/// only slower to respond.
///
/// Measured on an M4 (4 performance cores) with a CPU-bound Direct3D 9 test standing in for a game and busy processes
/// standing in for a busy Steam: alone 105 fps; with 4 busy processes 43 fps at normal priority, 102 fps when they ran
/// at background priority; with 8, 27 and 86 fps. Steam itself was not measured.
public enum SteamBackground {
    /// Steam's own programs, by executable name.
    public static let programs: Set<String> = ["steam.exe", "steamwebhelper.exe", "steamservice.exe", "steamerrorreporter.exe"]

    /// Steam's processes in this environment.
    public static func processes(in prefix: URL) -> [pid_t] {
        WindowsProcesses.list(in: prefix).filter { programs.contains($0.program) }.map(\.pid)
    }

    /// Background priority on or off for these processes. Only the person's own processes can be changed, and the
    /// change is undone by calling this again with `false` (macOS keeps no other state).
    @discardableResult
    public static func setBackground(_ on: Bool, for pids: [pid_t]) -> Int {
        pids.filter { setpriority(PRIO_DARWIN_PROCESS, id_t($0), on ? PRIO_DARWIN_BG : 0) == 0 }.count
    }
}

/// The Windows programs Wine is running for the person, read from each process's arguments and environment.
public enum WindowsProcesses {
    public struct Process: Equatable, Sendable {
        public var pid: pid_t
        /// Lowercased executable name, such as `steam.exe`.
        public var program: String
        public var prefix: String
    }

    public static func list(in prefix: URL) -> [Process] {
        let wanted = prefix.standardizedFileURL.path
        return allPIDs().compactMap { pid -> Process? in
            guard let raw = arguments(of: pid), let parsed = parse(raw),
                  let winePrefix = parsed.environment["WINEPREFIX"],
                  URL(fileURLWithPath: winePrefix).standardizedFileURL.path == wanted,
                  let first = parsed.arguments.first, let program = programName(first) else { return nil }
            return Process(pid: pid, program: program, prefix: winePrefix)
        }
    }

    /// `C:\Program Files (x86)\Steam\steam.exe` → `steam.exe`; nil for anything that isn't a Windows program.
    public static func programName(_ argument: String) -> String? {
        let name = argument.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init)?.lowercased() ?? ""
        return name.hasSuffix(".exe") ? name : nil
    }

    /// Splits a `KERN_PROCARGS2` buffer: argument count, executable path, padding, arguments, environment.
    public static func parse(_ data: Data) -> (arguments: [String], environment: [String: String])? {
        guard data.count > 4 else { return nil }
        let argc = Int(data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc >= 0, argc < 4096 else { return nil }
        let fields = data.dropFirst(4).split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        // The first field is the executable path; the next argc are the arguments, then the environment.
        guard fields.count >= 1 + argc else { return nil }
        let arguments = Array(fields[1..<(1 + argc)])
        var environment: [String: String] = [:]
        for entry in fields.dropFirst(1 + argc) {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return (arguments, environment)
    }

    private static func allPIDs() -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).map { $0.kp_proc.p_pid }.filter { $0 > 0 }
    }

    private static func arguments(of pid: pid_t) -> Data? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Data(buffer.prefix(size))
    }
}
