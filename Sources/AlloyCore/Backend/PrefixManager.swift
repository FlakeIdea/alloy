import Foundation

/// Manages Alloy-owned prefixes and lists CrossOver bottles read-only.
public final class PrefixManager {
    public let storageRoot: URL
    public let crossOverBottlesRoot: URL?
    private let store: JSONFileStore<[WinePrefix]>
    private let fileManager = FileManager.default
    public private(set) var ownPrefixes: [WinePrefix]

    static let dxvkMarker = ".alloy-dxvk"

    public init(storageRoot: URL, crossOverBottlesRoot: URL? = PrefixManager.defaultCrossOverBottles) {
        self.storageRoot = storageRoot
        self.crossOverBottlesRoot = crossOverBottlesRoot
        store = JSONFileStore(fileURL: storageRoot.appendingPathComponent("prefixes.json"))
        ownPrefixes = store.load(default: [])
    }

    public static var defaultCrossOverBottles: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles")
    }

    public var allPrefixes: [WinePrefix] { ownPrefixes + crossOverBottles() }

    public func prefix(id: UUID) -> WinePrefix? { allPrefixes.first { $0.id == id } }

    /// Creates the folder and metadata. Run `initializePrefixCommand` afterwards to populate it.
    public func createPrefix(name: String, runtimeID: String?) throws -> WinePrefix {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID()
        let slug = Self.slug(trimmed.isEmpty ? "prefix" : trimmed)
        let path = storageRoot.appendingPathComponent("Prefixes/\(slug)-\(id.uuidString.prefix(8))")
        do {
            try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        } catch {
            throw AlloyError.persistenceFailed(error.localizedDescription)
        }
        let prefix = WinePrefix(id: id, name: trimmed.isEmpty ? "Prefix" : trimmed, path: path, runtimeID: runtimeID)
        ownPrefixes.append(prefix)
        try store.save(ownPrefixes)
        return prefix
    }

    public func update(_ prefix: WinePrefix) throws {
        guard !prefix.isReadOnly, let i = ownPrefixes.firstIndex(where: { $0.id == prefix.id }) else { return }
        ownPrefixes[i] = prefix
        try store.save(ownPrefixes)
    }

    /// Moves the prefix folder to the Trash (recoverable) and forgets it. Refuses external bottles.
    public func trashPrefix(id: UUID) throws {
        guard let prefix = ownPrefixes.first(where: { $0.id == id }) else {
            if let external = crossOverBottles().first(where: { $0.id == id }) {
                throw AlloyError.prefixReadOnly(name: external.name)
            }
            throw AlloyError.prefixNotFound
        }
        if fileManager.fileExists(atPath: prefix.path.path) {
            try fileManager.trashItem(at: prefix.path, resultingItemURL: nil)
        }
        ownPrefixes.removeAll { $0.id == id }
        try store.save(ownPrefixes)
    }

    static func slug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return String(collapsed.prefix(40)).lowercased()
    }

    // MARK: CrossOver (read-only)

    public func crossOverBottles() -> [WinePrefix] {
        guard let root = crossOverBottlesRoot,
              let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { dir -> WinePrefix? in
            let conf = dir.appendingPathComponent("cxbottle.conf")
            guard let text = try? String(contentsOf: conf, encoding: .utf8) else { return nil }
            let values = Self.parseCXBottleConf(text)
            let id = values["BottleID"].flatMap(UUID.init(uuidString:)) ?? Self.stableUUID(for: dir.path)
            return WinePrefix(id: id, name: dir.lastPathComponent, path: dir,
                              architecture: values["WineArch"] ?? "unknown",
                              createdAt: (try? fileManager.attributesOfItem(atPath: dir.path)[.creationDate] as? Date) ?? Date(),
                              origin: .crossover)
        }.sorted { $0.name < $1.name }
    }

    /// Parses `"Key" = "Value"` lines.
    static func parseCXBottleConf(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            if parts.count == 2, !parts[0].isEmpty, result[parts[0]] == nil { result[parts[0]] = parts[1] }
        }
        return result
    }

    static func stableUUID(for string: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in string.utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: DXVK (reversible)

    public static func hasDXVKInstalled(_ prefix: WinePrefix) -> Bool {
        FileManager.default.fileExists(atPath: prefix.path.appendingPathComponent(dxvkMarker).path)
    }

    /// Copies DXVK DLLs (`x64/` → system32, `x32/` → syswow64), backing up the originals so it can be undone.
    public func installDXVK(from dxvkRoot: URL, into prefix: WinePrefix) throws {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        guard prefix.isInitialized() else { throw AlloyError.prefixNotInitialized(name: prefix.name) }
        let backup = prefix.path.appendingPathComponent("alloy-backup/dxvk")
        let pairs = [("x64", "system32"), ("x32", "syswow64")]
        var installed = 0
        do {
            for (source, target) in pairs {
                let src = dxvkRoot.appendingPathComponent(source)
                let dst = prefix.path.appendingPathComponent("drive_c/windows/\(target)")
                guard let dlls = try? fileManager.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { continue }
                let backupDir = backup.appendingPathComponent(target)
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                for dll in dlls where dll.pathExtension.lowercased() == "dll" {
                    let existing = dst.appendingPathComponent(dll.lastPathComponent)
                    let saved = backupDir.appendingPathComponent(dll.lastPathComponent)
                    if fileManager.fileExists(atPath: existing.path) {
                        if !fileManager.fileExists(atPath: saved.path) { try fileManager.copyItem(at: existing, to: saved) }
                        try fileManager.removeItem(at: existing)
                    }
                    try fileManager.copyItem(at: dll, to: existing)
                    installed += 1
                }
            }
        } catch {
            throw AlloyError.persistenceFailed("DXVK install failed: \(error.localizedDescription)")
        }
        guard installed > 0 else {
            throw AlloyError.graphicsBackendUnavailable(backend: "DXVK", reason: "No DLLs found in x64/ or x32/ of \(dxvkRoot.path).")
        }
        fileManager.createFile(atPath: prefix.path.appendingPathComponent(Self.dxvkMarker).path, contents: Data(dxvkRoot.path.utf8))
    }

    /// Restores the DLLs saved by `installDXVK`.
    public func uninstallDXVK(from prefix: WinePrefix) throws {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        let backup = prefix.path.appendingPathComponent("alloy-backup/dxvk")
        for target in ["system32", "syswow64"] {
            let dir = backup.appendingPathComponent(target)
            guard let saved = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let dst = prefix.path.appendingPathComponent("drive_c/windows/\(target)")
            for file in saved {
                let target = dst.appendingPathComponent(file.lastPathComponent)
                try? fileManager.removeItem(at: target)
                try fileManager.copyItem(at: file, to: target)
            }
        }
        try? fileManager.removeItem(at: backup)
        try? fileManager.removeItem(at: prefix.path.appendingPathComponent(Self.dxvkMarker))
    }
}
