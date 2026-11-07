import Foundation

/// A fully resolved process invocation. Executed with `Process` directly — never through a shell.
public struct LaunchCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL?
    /// A game: the session lasts until every process that inherited its output has exited, not just the
    /// launcher. Unreal Engine launchers start the real game and exit at once.
    public var waitsForChildProcesses: Bool
    /// Plain-English notes about how this start differs from the game's settings, written to the session log.
    public var notes: [String] = []

    public init(executable: URL, arguments: [String], environment: [String: String] = [:], workingDirectory: URL? = nil,
                waitsForChildProcesses: Bool = false) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.waitsForChildProcesses = waitsForChildProcesses
    }
}

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case errors
    case standard
    case verbose

    /// Value for `WINEDEBUG`. Verbose adds DLL-load tracing, useful for missing-DLL diagnosis but slow.
    public var wineDebug: String {
        switch self {
        case .errors: return "-all,err+all"
        case .standard: return "fixme-all"
        case .verbose: return "fixme-all,+loaddll,+seh"
        }
    }

    public var displayName: String {
        switch self {
        case .errors: return "Errors only"
        case .standard: return "Standard"
        case .verbose: return "Verbose (slower)"
        }
    }
}

public struct LaunchOptions: Sendable {
    public var logLevel: LogLevel
    /// Refresh rate of the main display, for `FrameRateCap.displayMaximum`.
    public var displayRefreshRate: Int
    /// Load the Metal performance HUD in every game, so the metrics shortcut can show it (`MetricsHUD`).
    public var loadMetricsHUD: Bool
    /// Alloy's folder for this game's DXMT shaders (`ShaderCache`), used unless the game sets its own path.
    public var shaderCacheDirectory: URL?
    public init(logLevel: LogLevel = .standard, displayRefreshRate: Int = DisplayInfo.refreshRate(), loadMetricsHUD: Bool = false,
                shaderCacheDirectory: URL? = nil) {
        self.logLevel = logLevel
        self.displayRefreshRate = displayRefreshRate
        self.loadMetricsHUD = loadMetricsHUD
        self.shaderCacheDirectory = shaderCacheDirectory
    }
}

/// Abstraction over a family of compatibility runtimes, so the UI does not depend on one Wine distribution.
public protocol CompatibilityBackend: Sendable {
    var id: String { get }
    var displayName: String { get }
    func discoverRuntimes() -> [WineRuntime]
    func capabilities(of runtime: WineRuntime) -> BackendCapabilities
    func initializePrefixCommand(prefix: WinePrefix, runtime: WineRuntime) throws -> LaunchCommand
    func stopPrefixCommand(prefix: WinePrefix, runtime: WineRuntime) -> LaunchCommand
    func launchCommand(for game: Game, prefix: WinePrefix, runtime: WineRuntime, options: LaunchOptions) throws -> LaunchCommand
}
