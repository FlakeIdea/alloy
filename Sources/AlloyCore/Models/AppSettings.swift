import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var defaultRuntimeID: String?
    public var libraryLocation: URL
    public var prefixStorageLocation: URL
    public var logLevel: LogLevel
    /// Extra Wine install roots (folders containing bin/wine) added by the user.
    public var customRuntimeRoots: [URL]
    /// Root of a user-supplied DXVK-macOS build (folder containing x64/ and x32/).
    public var dxvkLocation: URL?
    /// Install the Windows components a game needs (Visual C++, .NET) before its first start.
    public var autoInstallComponents: Bool
    /// Where to read components.json from instead of the address built into this release (for testing a release).
    public var componentsURLOverride: URL?
    /// The `Terms.version` the person accepted; nil until they do.
    public var acceptedTermsVersion: Int?
    /// ⌥⌘M shows or hides a running game's performance metrics (the Metal HUD, which every game then loads).
    public var metricsShortcut: Bool
    /// Look for a newer Alloy once a day (one request to flake.co.in that sends nothing about this Mac).
    public var checkForUpdates: Bool

    /// The components manifest: the override, else the address the release was built with (Info.plist).
    public var componentsURL: URL? {
        componentsURLOverride ?? (Bundle.main.object(forInfoDictionaryKey: "AlloyComponentsURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// `ALLOY_DATA_DIR` points Alloy at another folder, for screenshots and testing with a demo library.
    public static let supportDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["ALLOY_DATA_DIR"], custom.hasPrefix("/") {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alloy")
    }()

    public init(supportDirectory: URL = AppSettings.supportDirectory) {
        defaultRuntimeID = nil
        libraryLocation = supportDirectory.appendingPathComponent("library.json")
        prefixStorageLocation = supportDirectory
        logLevel = .standard
        customRuntimeRoots = []
        dxvkLocation = nil
        autoInstallComponents = true
        componentsURLOverride = nil
        acceptedTermsVersion = nil
        metricsShortcut = true
        checkForUpdates = true
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        defaultRuntimeID = try c.decodeIfPresent(String.self, forKey: .defaultRuntimeID)
        libraryLocation = try c.decodeIfPresent(URL.self, forKey: .libraryLocation) ?? d.libraryLocation
        prefixStorageLocation = try c.decodeIfPresent(URL.self, forKey: .prefixStorageLocation) ?? d.prefixStorageLocation
        logLevel = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .standard
        customRuntimeRoots = try c.decodeIfPresent([URL].self, forKey: .customRuntimeRoots) ?? []
        dxvkLocation = try c.decodeIfPresent(URL.self, forKey: .dxvkLocation)
        autoInstallComponents = try c.decodeIfPresent(Bool.self, forKey: .autoInstallComponents) ?? true
        componentsURLOverride = try c.decodeIfPresent(URL.self, forKey: .componentsURLOverride)
        acceptedTermsVersion = try c.decodeIfPresent(Int.self, forKey: .acceptedTermsVersion)
        metricsShortcut = try c.decodeIfPresent(Bool.self, forKey: .metricsShortcut) ?? true
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
    }
}

/// Benchmark history per game, stored next to the library.
public final class BenchmarkStore {
    private let store: JSONFileStore<[UUID: [BenchmarkRun]]>
    public private(set) var runs: [UUID: [BenchmarkRun]]

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL)
        runs = store.load(default: [:])
    }

    public func add(_ run: BenchmarkRun, gameID: UUID) throws {
        runs[gameID, default: []].append(run)
        try store.save(runs)
    }

    public func remove(runID: UUID, gameID: UUID) throws {
        runs[gameID]?.removeAll { $0.id == runID }
        try store.save(runs)
    }
}
