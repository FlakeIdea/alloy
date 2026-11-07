import Foundation

/// Windows components a game may need inside its environment, installed for it automatically or with one click.
public enum WindowsComponent: String, CaseIterable, Codable, Identifiable, Sendable {
    case visualCpp
    case dotNet

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .visualCpp: return "Microsoft Visual C++ runtime"
        case .dotNet: return ".NET support (Wine Mono)"
        }
    }

    public var summary: String {
        switch self {
        case .visualCpp: return "Needed by most recent games. Downloaded from Microsoft and checked against Microsoft's checksum."
        case .dotNet: return "For games and launchers written in C# or XNA. Downloaded from WineHQ and checked against the checksum built into Wine."
        }
    }

    public func isInstalled(in prefix: WinePrefix) -> Bool {
        switch self {
        case .visualCpp: return VisualCppRuntime.hasMicrosoftDLLs(.x64, in: prefix)
        case .dotNet: return WineMono.isInstalled(in: prefix)
        }
    }

    /// What this game most likely needs, judged from its files.
    public static func needed(by traits: GameTraits) -> [WindowsComponent] {
        var needs: [WindowsComponent] = []
        if traits.shipsVisualCppInstaller || traits.importsVisualCpp { needs.append(.visualCpp) }
        if traits.isDotNet { needs.append(.dotNet) }
        return needs
    }

    /// Needed components the environment does not have yet.
    public static func missing(for traits: GameTraits, in prefix: WinePrefix) -> [WindowsComponent] {
        needed(by: traits).filter { !$0.isInstalled(in: prefix) }
    }
}

/// Finds ASCII names (import names such as "vcruntime140.dll") in a binary, case-insensitively, without loading it.
enum BinaryScan {
    static func find(_ names: [String], in url: URL, maxBytes: Int = 256 * 1024 * 1024) -> Set<String> {
        let hits = indexes(of: names.map { Array($0.lowercased().utf8) }, in: url, maxBytes: maxBytes)
        return Set(hits.map { names[$0] })
    }

    /// Which of `needles` (lowercase ASCII) appear in the file's first `maxBytes`, ignoring case. Reads 1 MB at a
    /// time into one buffer, lowercases it in place and searches with `memmem`; chunks overlap by the longest needle,
    /// so a name split across two reads is still found. Stops early once everything is found.
    static func indexes(of needles: [[UInt8]], in url: URL, maxBytes: Int) -> Set<Int> {
        guard !needles.isEmpty, needles.allSatisfy({ !$0.isEmpty }) else { return [] }
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        let overlap = needles.map(\.count).max()! - 1
        let chunkSize = 1 << 20
        var buffer = [UInt8](repeating: 0, count: overlap + chunkSize)
        var found = Set<Int>()
        var kept = 0, total = 0
        buffer.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            while total < maxBytes, found.count < needles.count {
                let n = read(fd, base + kept, min(chunkSize, maxBytes - total))
                if n <= 0 { break }
                total += n
                let length = kept + n
                for i in kept..<length where base[i] &- 65 < 26 { base[i] |= 0x20 }
                for (index, needle) in needles.enumerated() where !found.contains(index) {
                    let hit = needle.withUnsafeBufferPointer { memmem(base, length, $0.baseAddress, $0.count) }
                    if hit != nil { found.insert(index) }
                }
                kept = min(overlap, length)
                if kept > 0 { memmove(base, base + (length - kept), kept) }
            }
        }
        return found
    }
}

/// Wine Mono: Wine's own .NET Framework replacement, needed by .NET programs. The runtime's Wine names the exact
/// version it works with and pins its SHA-256 in appwiz.cpl; Alloy downloads that file from WineHQ and accepts it
/// only if it matches one of those checksums.
public enum WineMono {
    public struct Expectation: Equatable, Sendable {
        public var version: String
        public var fileName: String
        public var checksums: Set<String>

        public var downloadURL: URL { URL(string: "https://dl.winehq.org/wine/wine-mono/\(version)/\(fileName)")! }
    }

    /// Approximate download size of the installer, for confirmation text.
    public static let approximateMegabytes = 86

    /// What the runtime's Wine expects, read from its appwiz.cpl, or nil when that cannot be found.
    public static func expectation(for runtime: WineRuntime) -> Expectation? {
        for arch in ["x86_64-windows", "i386-windows"] {
            let url = runtime.root.appendingPathComponent("lib/wine/\(arch)/appwiz.cpl")
            if let data = try? Data(contentsOf: url), let e = expectation(fromAppwiz: data) { return e }
        }
        return nil
    }

    /// The installer in `downloads`, if it is there and matches one of the expected checksums.
    public static func cachedInstaller(_ expected: Expectation, in downloads: URL) -> URL? {
        let msi = downloads.appendingPathComponent(expected.fileName)
        return RuntimeInstaller.sha256(of: msi).map(expected.checksums.contains) == true ? msi : nil
    }

    /// Downloads the installer from WineHQ into `downloads` and keeps it only if it matches the expected checksums.
    public static func download(_ expected: Expectation, to downloads: URL) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        let msi = downloads.appendingPathComponent(expected.fileName)
        try? fileManager.removeItem(at: msi)
        let temporary = try await Downloader.download(expected.downloadURL) { _ in }
        guard let actual = RuntimeInstaller.sha256(of: temporary), expected.checksums.contains(actual) else {
            try? fileManager.removeItem(at: temporary)
            throw AlloyError.downloadFailed("The downloaded Wine Mono \(expected.version) does not match the checksum the game engine pins, so it was not used.")
        }
        try fileManager.moveItem(at: temporary, to: msi)
        return msi
    }

    /// Parses the UTF-16 file name "wine-mono-<version>-x86.msi" and the 64-digit hex checksums in appwiz.cpl.
    static func expectation(fromAppwiz data: Data) -> Expectation? {
        let bytes = [UInt8](data)
        let prefix: [UInt8] = Array("wine-mono-".utf8).flatMap { [$0, UInt8(0)] }
        guard let start = firstIndex(of: prefix, in: bytes) else { return nil }
        var name = ""
        var i = start
        while i + 1 < bytes.count, bytes[i + 1] == 0, bytes[i] >= 0x20, bytes[i] < 0x7f, name.count < 64 {
            name.append(Character(UnicodeScalar(bytes[i])))
            i += 2
        }
        guard name.hasSuffix(".msi") else { return nil }
        var version = String(name.dropFirst("wine-mono-".count).dropLast(".msi".count))
        if let dash = version.lastIndex(of: "-") { version = String(version[..<dash]) }
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        var checksums: Set<String> = []
        var run: [UInt8] = []
        for b in bytes + [0] {
            let hex = (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66)
            if hex { run.append(b); continue }
            if run.count == 64 && b == 0 { checksums.insert(String(decoding: run, as: UTF8.self)) }
            run.removeAll(keepingCapacity: true)
        }
        return checksums.isEmpty ? nil : Expectation(version: version, fileName: name, checksums: checksums)
    }

    static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard let first = needle.first, haystack.count >= needle.count else { return nil }
        var i = 0
        while let j = haystack[i...].firstIndex(of: first), j + needle.count <= haystack.count {
            if haystack[j..<(j + needle.count)].elementsEqual(needle) { return j }
            i = j + 1
        }
        return nil
    }

    /// Wine Mono's installer puts its runtime under C:\windows\mono.
    public static func isInstalled(in prefix: WinePrefix) -> Bool {
        FileManager.default.fileExists(atPath: prefix.path.appendingPathComponent("drive_c/windows/mono/mono-2.0").path)
    }

    /// Downloads Wine Mono (unless a verified copy is already in `downloads`) and installs it with Wine's own
    /// msiexec. Throws when the download does not match or the install leaves no Mono behind.
    public static func install(into prefix: WinePrefix, runtime: WineRuntime, backend: WineBackend, downloads: URL,
                               progress: @escaping @Sendable (String) -> Void) async throws {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        guard prefix.isInitialized() else { throw AlloyError.prefixNotInitialized(name: prefix.name) }
        guard let expected = expectation(for: runtime) else {
            throw AlloyError.downloadFailed("\(runtime.displayName) does not say which Wine Mono version it needs, so .NET support cannot be installed automatically.")
        }
        let fileManager = FileManager.default
        var msi = cachedInstaller(expected, in: downloads)
        if msi == nil {
            progress("Downloading Wine Mono \(expected.version) from WineHQ…")
            msi = try await download(expected, to: downloads)
        }
        guard let msi else { return }
        progress("Installing .NET support (Wine Mono \(expected.version)) in \(prefix.name)…")
        let temp = prefix.path.appendingPathComponent("drive_c/windows/temp")
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        let copy = temp.appendingPathComponent(expected.fileName)
        try? fileManager.removeItem(at: copy)
        try fileManager.copyItem(at: msi, to: copy)
        defer { try? fileManager.removeItem(at: copy) }
        let command = try backend.wineToolCommand(["msiexec", "/i", #"C:\windows\temp\"# + expected.fileName, "/qn"],
                                                  prefix: prefix, runtime: runtime)
        let session = LaunchSession(command: command, logFile: nil)
        try session.start()
        let state = session.waitUntilExit(timeout: 900)
        guard isInstalled(in: prefix) else {
            throw AlloyError.downloadFailed("Wine Mono's installer ended (\(state.summary.lowercased())), but .NET support is not in \(prefix.name).")
        }
    }
}
