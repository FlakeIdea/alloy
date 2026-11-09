import Foundation

/// Copies of an environment's game saves, made before Alloy changes or removes the environment (moving it to a newer
/// game engine, moving it to the Trash). Kept in `Save Backups/<environment id>/<date>/` next to the environments, the
/// last `keep` per environment, each with a `backup.json` describing it. On APFS a copy is a clone, so it takes no
/// space until the game changes the file.
///
/// Saved: each Windows user's AppData (Roaming, Local, LocalLow), Documents and Saved Games, the shared Documents, and
/// Steam's `userdata` (local copies of cloud saves and per-game settings), without caches, logs, temporary files or
/// Steam screenshots. Links are never followed, so a folder Wine links to the Mac (such as Documents) is not copied:
/// it lives outside the environment, and changing the environment doesn't touch it. Restoring copies the backup's
/// files back over the environment's; files the backup doesn't have stay as they are.
public enum SaveBackups {
    public static let folderName = "Save Backups"
    public static let manifestName = "backup.json"
    /// Backups kept per environment; older ones are removed when a new one is made.
    public static let keep = 3
    /// A single file larger than this is not a save (a video, a disk image) and is skipped.
    public static let largestFile: Int64 = 1 << 30

    public static let settingHelp = "Before Alloy moves an environment to a newer game engine or moves it to the Trash, it copies the games' saves and settings from it (AppData, Documents, Saved Games, Steam's local saves), keeping the last \(keep) copies per environment. On a Mac's own disk the copies take almost no space until games change their saves. Restore them from the environment's menu on the Environments page."

    public struct Manifest: Codable, Equatable, Sendable {
        public var prefixID: UUID
        public var prefixName: String
        public var date: Date
        /// Why it was made, e.g. "Before moving to a newer game engine".
        public var reason: String
        public var files: Int
        public var bytes: Int64
        /// Paths (relative to the environment) skipped because they were too large.
        public var skipped: [String]
    }

    public struct Backup: Identifiable, Equatable, Sendable {
        public var folder: URL
        public var manifest: Manifest
        public var id: URL { folder }
    }

    public static func root(storage: URL) -> URL { storage.appendingPathComponent(folderName, isDirectory: true) }

    /// The folders, relative to the environment, that hold saves. Only folders that exist and are real folders.
    public static func saveFolders(in prefix: URL, fileManager fm: FileManager = .default) -> [String] {
        var result: [String] = []
        let users = prefix.appendingPathComponent("drive_c/users")
        let names = ((try? fm.contentsOfDirectory(atPath: users.path)) ?? []).sorted()
        for user in names where !user.hasPrefix(".") {
            let base = "drive_c/users/\(user)"
            let candidates = user == "Public"
                ? ["Documents"]
                : ["AppData/Roaming", "AppData/Local", "AppData/LocalLow", "Documents", "Saved Games"]
            result += candidates.map { "\(base)/\($0)" }
        }
        result.append("drive_c/Program Files (x86)/Steam/userdata")
        return result.filter { isRealFolder(prefix.appendingPathComponent($0), fm) }
    }

    /// Folder names (any case) that hold caches or logs rather than saves.
    static let skippedFolders: Set<String> = [
        "temp", "tmp", "cache", "caches", "gpucache", "shadercache", "shadercaches", "d3dscache", "code cache",
        "htmlcache", "webcache", "crashdumps", "crashes", "crashreportclient", "logs", "microsoft", "nvidia", "packages",
    ]

    /// Copies the saves. Returns nil when the environment has none.
    @discardableResult
    public static func backUp(prefix: WinePrefix, reason: String, storage: URL, date: Date = Date(),
                              fileManager fm: FileManager = .default) throws -> Backup? {
        let folders = saveFolders(in: prefix.path, fileManager: fm)
        guard !folders.isEmpty else { return nil }
        let dir = root(storage: storage).appendingPathComponent(prefix.id.uuidString, isDirectory: true)
        let folder = dir.appendingPathComponent(folderStamp(date), isDirectory: true)
        let partial = dir.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        var files = 0, bytes: Int64 = 0, skipped: [String] = []
        do {
            for relative in folders {
                try copyTree(from: prefix.path.appendingPathComponent(relative), to: partial.appendingPathComponent(relative),
                             relative: relative, files: &files, bytes: &bytes, skipped: &skipped, fm: fm)
            }
            guard files > 0 else { try? fm.removeItem(at: partial); return nil }
            let manifest = Manifest(prefixID: prefix.id, prefixName: prefix.name, date: date, reason: reason,
                                    files: files, bytes: bytes, skipped: skipped)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: partial.appendingPathComponent(manifestName))
            // Only a finished copy gets its final name, so a half-made backup is never offered for restoring.
            try fm.moveItem(at: partial, to: folder)
            prune(prefixID: prefix.id, storage: storage, fileManager: fm)
            return Backup(folder: folder, manifest: manifest)
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
    }

    /// Backups of this environment, newest first.
    public static func list(prefixID: UUID, storage: URL, fileManager fm: FileManager = .default) -> [Backup] {
        let dir = root(storage: storage).appendingPathComponent(prefixID.uuidString, isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { name -> Backup? in
            let folder = dir.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
                  let manifest = try? decoder.decode(Manifest.self, from: data), manifest.prefixID == prefixID else { return nil }
            return Backup(folder: folder, manifest: manifest)
        }.sorted { $0.manifest.date > $1.manifest.date }
    }

    /// Copies the backup's files into the environment, replacing files with the same path. Returns the files copied.
    @discardableResult
    public static func restore(_ backup: Backup, into prefix: WinePrefix, fileManager fm: FileManager = .default) throws -> Int {
        guard backup.manifest.prefixID == prefix.id else { throw CocoaError(.fileReadNoPermission) }
        var restored = 0
        for relative in saveFolderNames(in: backup.folder, fm) {
            let target = prefix.path.appendingPathComponent(relative)
            // Never write through a link that leads out of the environment.
            if let parent = existingAncestor(of: target, fm), !isInside(parent, prefix.path) { continue }
            restored += try restoreTree(from: backup.folder.appendingPathComponent(relative), to: target, prefix: prefix.path, fm: fm)
        }
        return restored
    }

    public static func describe(_ backup: Backup) -> String {
        let date = DateFormatter.localizedString(from: backup.manifest.date, dateStyle: .medium, timeStyle: .short)
        let size = ByteCountFormatter.string(fromByteCount: backup.manifest.bytes, countStyle: .file)
        return "\(date) · \(backup.manifest.files) files, \(size) · \(backup.manifest.reason)"
    }

    // MARK: Internals

    static func folderStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f.string(from: date)
    }

    static func prune(prefixID: UUID, storage: URL, fileManager fm: FileManager) {
        for old in list(prefixID: prefixID, storage: storage, fileManager: fm).dropFirst(keep) {
            try? fm.removeItem(at: old.folder)
        }
    }

    private static func isRealFolder(_ url: URL, _ fm: FileManager) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func copyTree(from source: URL, to target: URL, relative: String, files: inout Int, bytes: inout Int64,
                                 skipped: inout [String], fm: FileManager) throws {
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        let items = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: keys, options: [])) ?? []
        for item in items {
            guard let v = try? item.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
            let name = item.lastPathComponent
            let childRelative = relative + "/" + name
            if v.isDirectory == true {
                if skippedFolders.contains(name.lowercased()) { continue }
                // Steam keeps each account's screenshots in userdata/<account>/760.
                if name == "760", relative.hasPrefix("drive_c/Program Files (x86)/Steam/userdata/") { continue }
                try copyTree(from: item, to: target.appendingPathComponent(name), relative: childRelative,
                             files: &files, bytes: &bytes, skipped: &skipped, fm: fm)
            } else if v.isRegularFile == true {
                let size = Int64(v.fileSize ?? 0)
                if size > largestFile { skipped.append(childRelative); continue }
                // copyItem clones on APFS, so the copy costs no space until the original changes.
                try fm.copyItem(at: item, to: target.appendingPathComponent(name))
                files += 1
                bytes += size
            }
        }
    }

    /// The save folders a backup holds, relative to the environment (the same list `saveFolders` makes).
    private static func saveFolderNames(in backup: URL, _ fm: FileManager) -> [String] {
        saveFolders(in: backup, fileManager: fm)
    }

    private static func restoreTree(from source: URL, to target: URL, prefix: URL, fm: FileManager) throws -> Int {
        var count = 0
        if let v = try? target.resourceValues(forKeys: [.isSymbolicLinkKey]), v.isSymbolicLink == true { return 0 }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        for item in (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: keys, options: [])) ?? [] {
            guard let v = try? item.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
            let destination = target.appendingPathComponent(item.lastPathComponent)
            if v.isDirectory == true {
                count += try restoreTree(from: item, to: destination, prefix: prefix, fm: fm)
            } else if v.isRegularFile == true {
                if let d = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                    if d.isSymbolicLink == true || d.isDirectory == true { continue }
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: item, to: destination)
                count += 1
            }
        }
        return count
    }

    private static func existingAncestor(of url: URL, _ fm: FileManager) -> URL? {
        var current = url
        while !fm.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
        return current.resolvingSymlinksInPath()
    }

    private static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}
