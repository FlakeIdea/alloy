import Foundation

/// Errors surfaced to the user. Every case carries enough context to explain what to do next.
public enum AlloyError: Error, LocalizedError, Equatable, Sendable {
    case executableNotFound(path: String)
    case executableOutsideGameFolder(path: String)
    case notAWindowsExecutable(path: String)
    case unsupportedExecutableArchitecture(String)
    case runtimeUnavailable(String)
    case prefixNotFound
    case prefixReadOnly(name: String)
    case prefixNotInitialized(name: String)
    case prefixRuntimeMismatch(prefix: String, created: String, requested: String)
    case invalidEnvironmentKey(String)
    case blockedEnvironmentKey(String)
    case graphicsBackendUnavailable(backend: String, reason: String)
    case launchFailed(String)
    /// A download or its check failed; the text is a whole sentence.
    case downloadFailed(String)
    case alreadyRunning
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "The executable could not be found at \(path). It may have been moved, renamed or deleted."
        case .executableOutsideGameFolder(let path):
            return "The executable \(path) is outside the game folder. Choose an executable inside the selected folder."
        case .notAWindowsExecutable(let path):
            return "\(path) is not a Windows executable (no valid PE header)."
        case .unsupportedExecutableArchitecture(let arch):
            return "This executable targets \(arch), which Wine on macOS cannot run."
        case .runtimeUnavailable(let detail):
            return "No usable Wine runtime: \(detail)"
        case .prefixNotFound:
            return "The compatibility environment (prefix) for this game no longer exists."
        case .prefixReadOnly(let name):
            return "\(name) is an external environment (for example a CrossOver bottle). Alloy does not modify it."
        case .prefixNotInitialized(let name):
            return "The environment \(name) has not been initialised yet. Use “Initialise” on the Environments page first."
        case .prefixRuntimeMismatch(let prefix, let created, let requested):
            return "\(prefix) was created with \(created). Running it with \(requested) can corrupt it. Create a separate environment for that runtime."
        case .invalidEnvironmentKey(let key):
            return "“\(key)” is not a valid environment variable name."
        case .blockedEnvironmentKey(let key):
            return "“\(key)” is blocked for security reasons."
        case .graphicsBackendUnavailable(let backend, let reason):
            return "\(backend) cannot be used: \(reason)"
        case .launchFailed(let detail):
            return "Launch failed: \(detail)"
        case .downloadFailed(let detail):
            return detail
        case .alreadyRunning:
            return "This game is already running."
        case .persistenceFailed(let detail):
            return "Could not save data: \(detail)"
        }
    }
}
