import Foundation

/// A release of the Alloy app, as published at flake.co.in/alloy/latest.json by the website's build.
public struct AppRelease: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int?
    public let url: URL
    public let sha256: String
    public let size: Int?
    public let notes: [String]?
    public let minimumSystemVersion: String?

    public init(version: String, build: Int? = nil, url: URL, sha256: String, size: Int? = nil, notes: [String]? = nil,
                minimumSystemVersion: String? = nil) {
        self.version = version
        self.build = build
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.notes = notes
        self.minimumSystemVersion = minimumSystemVersion
    }
}

/// Checking for, downloading and installing a newer Alloy.
///
/// The check is one HTTPS request for a small JSON file and sends nothing about the Mac. An update is installed only
/// after the person clicks Install: the zip must come from flake.co.in, match the published SHA-256, and contain an
/// Alloy app with a newer version. The old copy goes to the Trash, not deleted, so it can be put back.
public enum AppUpdate {
    public static let feed = URL(string: "https://flake.co.in/alloy/latest.json")!
    /// The bundle identifiers Alloy has shipped under. An update must carry one of them.
    public static let bundleIdentifiers: Set<String> = ["in.co.flake.Alloy", "local.alloy.Alloy"]
    static let trustedHosts: Set<String> = ["flake.co.in", "www.flake.co.in"]
    /// How often the automatic check runs.
    public static let interval: TimeInterval = 24 * 60 * 60

    public enum Result: Equatable, Sendable {
        case upToDate(latest: String)
        case available(AppRelease)
        /// A newer version exists but needs a newer macOS than this Mac has.
        case needsNewerMacOS(AppRelease)
    }

    // MARK: Versions

    /// Compares dotted version numbers ("0.10.0" is newer than "0.9.1"); a missing part counts as 0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    // MARK: Addresses

    /// Update files come only from flake.co.in over HTTPS, or from this Mac (for testing a release before uploading).
    public static func isTrusted(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if url.scheme == "https", trustedHosts.contains(host) { return true }
        return (url.scheme == "http" || url.scheme == "https") && ["127.0.0.1", "localhost", "::1"].contains(host)
    }

    /// The feed address; ALLOY_UPDATE_FEED may point at a local test server, never at another website.
    public static func feedURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let value = environment["ALLOY_UPDATE_FEED"], let url = URL(string: value), isTrusted(url) { return url }
        return feed
    }

    // MARK: Check

    public static func decode(_ data: Data) throws -> AppRelease {
        do { return try JSONDecoder().decode(AppRelease.self, from: data) } catch {
            throw AlloyError.downloadFailed("The update information from flake.co.in couldn't be read.")
        }
    }

    public static func result(for release: AppRelease, currentVersion: String,
                              systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Result {
        guard isNewer(release.version, than: currentVersion) else { return .upToDate(latest: release.version) }
        if let minimum = release.minimumSystemVersion {
            let system = "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
            if isNewer(minimum, than: system) { return .needsNewerMacOS(release) }
        }
        return .available(release)
    }

    public static func check(currentVersion: String, feed: URL = feedURL()) async throws -> Result {
        guard isTrusted(feed) else { throw AlloyError.downloadFailed("Updates can only come from flake.co.in.") }
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await AlloyHTTP.session.data(for: request) } catch {
            throw AlloyError.downloadFailed("Alloy couldn't reach flake.co.in. Check your internet connection and try again.")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AlloyError.downloadFailed("flake.co.in didn't return update information. Try again later.")
        }
        return result(for: try decode(data), currentVersion: currentVersion)
    }

    // MARK: Download

    /// Downloads the release's zip and returns the verified Alloy.app inside it, in a temporary folder.
    public static func download(_ release: AppRelease, currentVersion: String,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard isTrusted(release.url) else { throw AlloyError.downloadFailed("Updates can only come from flake.co.in.") }
        let total = Double(max(release.size ?? 0, 1))
        let zip = try await Downloader.download(release.url) { bytes in progress(min(Double(bytes) / total, 1)) }
        defer { try? FileManager.default.removeItem(at: zip) }
        return try prepare(zip: zip, release: release, currentVersion: currentVersion)
    }

    /// Checks the zip against the release, unpacks it and checks the app inside.
    public static func prepare(zip: URL, release: AppRelease, currentVersion: String) throws -> URL {
        guard let actual = RuntimeInstaller.sha256(of: zip), actual.lowercased() == release.sha256.lowercased() else {
            throw AlloyError.downloadFailed("The downloaded update didn't match the published checksum, so it wasn't installed.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alloy-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw AlloyError.downloadFailed("The update couldn't be unpacked.") }
        let app = folder.appendingPathComponent("Alloy.app")
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let id = info["CFBundleIdentifier"] as? String, bundleIdentifiers.contains(id),
              let version = info["CFBundleShortVersionString"] as? String else {
            throw AlloyError.downloadFailed("The download doesn't contain the Alloy app, so it wasn't installed.")
        }
        guard version == release.version, isNewer(version, than: currentVersion) else {
            throw AlloyError.downloadFailed("The download isn't a newer version of Alloy, so it wasn't installed.")
        }
        return app
    }

    // MARK: Install

    /// Alloy can replace itself only when its own folder is writable, such as Applications on an admin account.
    public static func canReplace(_ current: URL) -> Bool {
        current.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: current.path)
    }

    /// Moves the current app to the Trash and puts the new one in its place. Returns where the old copy went.
    @discardableResult
    public static func install(_ newApp: URL, replacing current: URL) throws -> URL? {
        let fm = FileManager.default
        var trashed: NSURL?
        try fm.trashItem(at: current, resultingItemURL: &trashed)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            // Put the old copy back so Alloy is never left missing.
            if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: current) }
            throw AlloyError.downloadFailed("The update couldn't be put in place: \(error.localizedDescription)")
        }
        return trashed as URL?
    }

    /// Opens `app` once this process has quit. The path is passed as an argument, never inside the script.
    public static func relaunch(_ app: URL, after pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                           "alloy-relaunch", String(pid), app.path]
        try shell.run()
    }
}
