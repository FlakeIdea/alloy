import CryptoKit
import Foundation

/// A ready-to-run game engine: a Wine runtime with its graphics layers (DXMT) and video decoders, packed by
/// `scripts/package-runtime.sh`. Listed in the components manifest an Alloy release points to.
public struct RuntimePackage: Codable, Equatable, Identifiable, Sendable {
    /// Stable name of this build, for example "dxmt-0.80-cx26.3-1". A runtime folder records it once installed.
    public var id: String
    public var name: String
    public var version: String
    public var url: URL
    public var sha256: String
    public var downloadBytes: Int64
    public var installedBytes: Int64
    public var summary: String?

    public init(id: String, name: String, version: String, url: URL, sha256: String,
                downloadBytes: Int64, installedBytes: Int64, summary: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.downloadBytes = downloadBytes
        self.installedBytes = installedBytes
        self.summary = summary
    }
}

/// `components.json`: what can be downloaded. The first runtime is the recommended one.
public struct ComponentManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var runtimes: [RuntimePackage]

    public init(formatVersion: Int = 1, runtimes: [RuntimePackage]) {
        self.formatVersion = formatVersion
        self.runtimes = runtimes
    }

    /// Package URLs may be relative to the manifest, so a release folder can be uploaded as it is.
    public func resolved(against manifestURL: URL) -> ComponentManifest {
        var copy = self
        copy.runtimes = runtimes.map { p in
            var p = p
            if p.url.scheme == nil, let absolute = URL(string: p.url.relativeString, relativeTo: manifestURL)?.absoluteURL { p.url = absolute }
            return p
        }
        return copy
    }
}

/// Downloads, checks and unpacks game engine packages into Alloy's Runtimes folder. Nothing outside that
/// folder (and the downloads folder) is written; a package is used only if its SHA-256 matches the manifest.
public enum RuntimeInstaller {
    /// Written into an installed runtime's folder; records which package it came from.
    public static let markerName = "alloy-package.json"

    public struct Marker: Codable, Equatable, Sendable {
        public var id: String
        public var version: String
        public var sha256: String
        public var installedAt: Date
    }

    /// HTTPS anywhere; plain HTTP only from this Mac (for testing a release folder before uploading it).
    public static func isAllowedSource(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return url.host != nil
        case "http": return ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
        case "file": return true
        default: return false
        }
    }

    public static func fetchManifest(from url: URL) async throws -> ComponentManifest {
        guard isAllowedSource(url) else { throw AlloyError.downloadFailed("Components are only downloaded over HTTPS (\(url.absoluteString) is not).") }
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (body, response): (Data, URLResponse)
            do { (body, response) = try await AlloyHTTP.session.data(from: url) } catch let error as URLError {
                throw AlloyError.downloadFailed("Could not reach the game engine download server: \(error.localizedDescription)")
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    throw AlloyError.downloadFailed("The game engine isn't available to download yet. Check flake.co.in/alloy for news.")
                }
                throw AlloyError.downloadFailed("The components server answered with HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
            }
            data = body
        }
        let manifest = try JSONDecoder().decode(ComponentManifest.self, from: data)
        guard manifest.formatVersion == 1 else {
            throw AlloyError.downloadFailed("This version of Alloy is too old for the available components. Download the latest Alloy.")
        }
        return manifest.resolved(against: url)
    }

    /// Packages installed in the Runtimes folder, by package id.
    public static func installedMarkers(in runtimesDirectory: URL, fileManager: FileManager = .default) -> [String: Marker] {
        let folders = (try? fileManager.contentsOfDirectory(at: runtimesDirectory, includingPropertiesForKeys: nil)) ?? []
        var result: [String: Marker] = [:]
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(markerName)),
                  let marker = try? decoder.decode(Marker.self, from: data) else { continue }
            result[marker.id] = marker
        }
        return result
    }

    /// Downloads (or reuses a verified download of) the package, checks its SHA-256 and unpacks it.
    /// Returns the new runtime folder.
    public static func install(_ package: RuntimePackage, into runtimesDirectory: URL, downloads: URL,
                               progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        guard isAllowedSource(package.url) else {
            throw AlloyError.downloadFailed("\(package.name) is not offered over HTTPS, so it was not downloaded.")
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        let archive = downloads.appendingPathComponent(safeFileName(package.id) + ".tar.xz")
        if sha256(of: archive) != package.sha256.lowercased() {
            try? fileManager.removeItem(at: archive)
            if package.url.isFileURL {
                try fileManager.copyItem(at: package.url, to: archive)
            } else {
                let total = Double(max(package.downloadBytes, 1))
                let temporary = try await Downloader.download(package.url) { written in
                    progress(min(Double(written) / total, 1) * 0.8, "Downloading \(package.name)… \(megabytes(written)) of \(megabytes(package.downloadBytes))")
                }
                try fileManager.moveItem(at: temporary, to: archive)
            }
            progress(0.8, "Checking the download…")
            guard sha256(of: archive) == package.sha256.lowercased() else {
                try? fileManager.removeItem(at: archive)
                throw AlloyError.downloadFailed("The downloaded \(package.name) does not match its published checksum, so it was not installed. Try again; if it keeps failing, the download server has a different file than this Alloy release expects.")
            }
        }
        progress(0.85, "Unpacking \(package.name)…")
        let folder = try unpack(archive: archive, into: runtimesDirectory)
        let marker = Marker(id: package.id, version: package.version, sha256: package.sha256.lowercased(), installedAt: Date())
        try encoder.encode(marker).write(to: folder.appendingPathComponent(markerName))
        // The archive is kept only until the install worked; the runtime is the copy that matters.
        try? fileManager.removeItem(at: archive)
        progress(1, "Installed \(package.name).")
        return folder
    }

    /// Unpacks a package archive into a staging folder inside the Runtimes folder, checks it holds exactly one
    /// runtime folder (with `wine/bin/wine`) and no links that point outside it, then moves it into place.
    public static func unpack(archive: URL, into runtimesDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: runtimesDirectory, withIntermediateDirectories: true)
        let staging = runtimesDirectory.appendingPathComponent(".staging-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        // bsdtar refuses absolute paths and ".." entries unless told otherwise (-P).
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", staging.path]
        let errors = Pipe()
        tar.standardError = errors
        tar.standardOutput = FileHandle.nullDevice
        try tar.run()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw AlloyError.downloadFailed("The package could not be unpacked: \(String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let top = (try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)).filter { !$0.lastPathComponent.hasPrefix(".") }
        guard top.count == 1, let folder = top.first,
              fileManager.isExecutableFile(atPath: folder.appendingPathComponent("wine/bin/wine").path) else {
            throw AlloyError.downloadFailed("The package does not contain an Alloy runtime (one folder with wine/bin/wine).")
        }
        if let escaping = linkEscaping(folder, fileManager: fileManager) {
            throw AlloyError.downloadFailed("The package was not installed: it contains a link that points outside it (\(escaping)).")
        }
        let target = runtimesDirectory.appendingPathComponent(folder.lastPathComponent)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw AlloyError.downloadFailed("\(folder.lastPathComponent) is already installed.")
        }
        try fileManager.moveItem(at: folder, to: target)
        return target
    }

    /// The first symbolic link under `root` whose destination resolves outside `root`, or nil.
    static func linkEscaping(_ root: URL, fileManager: FileManager) -> String? {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true,
                  let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { continue }
            let resolved = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL.path
            if !(resolved + "/").hasPrefix(base) { return url.lastPathComponent + " → " + destination }
        }
        return nil
    }

    static func safeFileName(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "-" })
    }

    public static func megabytes(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1e9) : "\(bytes / 1_000_000) MB"
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// A file download with progress, through URLSession's system certificate checks.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(onProgress: @escaping @Sendable (Int64) -> Void) { self.onProgress = onProgress }

    /// Network errors worth another try: a dropped Wi-Fi connection or a TLS handshake cut short.
    static let transientErrors: Set<URLError.Code> = [.secureConnectionFailed, .networkConnectionLost, .timedOut,
                                                      .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost]

    /// Downloads to a temporary file that the caller moves or deletes, trying up to three times on transient errors.
    static func download(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        var attempt = 1
        while true {
            do { return try await downloadOnce(url, progress: progress) } catch let error as URLError {
                guard attempt < 3, transientErrors.contains(error.code) else {
                    throw AlloyError.downloadFailed("The download failed: \(error.localizedDescription)")
                }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                attempt += 1
            }
        }
    }

    private static func downloadOnce(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let downloader = Downloader(onProgress: progress)
        let session = URLSession(configuration: AlloyHTTP.configuration(), delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            continuation?.resume(throwing: AlloyError.downloadFailed("The download server answered with HTTP \(code)."))
            continuation = nil
            return
        }
        // The system deletes `location` when this method returns, so keep a copy.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("alloy-\(UUID().uuidString).download")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: (error as? URLError) ?? AlloyError.downloadFailed("The download failed: \(error.localizedDescription)"))
        continuation = nil
    }
}
