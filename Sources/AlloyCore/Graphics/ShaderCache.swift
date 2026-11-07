import Foundation

/// Where a game's converted shaders are kept between plays.
///
/// DXMT converts each Direct3D shader to Metal the first time the game uses it and Metal then builds a GPU pipeline
/// from it; that work is what makes the first minutes of a new game hitch. Both results are saved: DXMT's in an SQLite
/// file (`shaders_<metal version>.db`), Metal's in a `com.apple.metal` folder. By default both sit in macOS's per-user
/// cache folder (`getconf DARWIN_USER_CACHE_DIR`) under `dxmt/<program name>/`, where macOS may delete them to free
/// space and where two games with the same program name share them.
///
/// Alloy keeps them in a folder per game in its own support folder instead: DXMT's file through
/// `DXMT_SHADER_CACHE_PATH`, and Metal's by linking `dxmt/<program>/com.apple.metal` to the game's folder (DXMT has no
/// setting for it). On the first start it moves what was already saved there, so no work is lost.
/// D3DMetal keeps its own cache, which Alloy leaves alone.
public enum ShaderCache {
    public static let folderName = "ShaderCache"

    public static func directory(for gameID: UUID, supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent(folderName).appendingPathComponent(gameID.uuidString)
    }

    /// macOS's per-user cache folder, where DXMT saves when not told otherwise.
    public static func systemCacheDirectory() -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    /// The program names DXMT saves this game's shaders under: the executable, and for Unreal Engine games the
    /// `*-Shipping.exe` the launcher starts (in `<Project>/Binaries/Win64`).
    static func programNames(for game: Game, fileManager: FileManager = .default) -> [String] {
        var names = [game.executableURL.lastPathComponent]
        let roots = [game.folder] + ((try? fileManager.contentsOfDirectory(at: game.folder, includingPropertiesForKeys: nil)) ?? [])
        for root in roots.prefix(64) {
            let binaries = root.appendingPathComponent("Binaries/Win64")
            for name in (try? fileManager.contentsOfDirectory(atPath: binaries.path)) ?? []
            where name.lowercased().hasSuffix("-shipping.exe") && !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Metal's pipeline cache for one program, kept in the game's folder.
    static func metalDirectory(in folder: URL, program: String) -> URL {
        folder.appendingPathComponent("metal").appendingPathComponent(program)
    }

    static func hasCache(in folder: URL, fileManager: FileManager) -> Bool {
        ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).contains { isDatabase($0) }
    }

    static func isDatabase(_ name: String) -> Bool { name.hasPrefix("shaders_") && name.hasSuffix(".db") }

    /// Makes the game's folder, moves shaders saved earlier in macOS's cache folder into it, and links Metal's cache
    /// there. Call before the game starts, while nothing writes the caches. Returns the folder for
    /// `DXMT_SHADER_CACHE_PATH`, or nil if it couldn't be made.
    @discardableResult
    public static func prepare(for game: Game, supportDirectory: URL,
                               systemCacheDirectory: URL? = ShaderCache.systemCacheDirectory(),
                               fileManager: FileManager = .default) -> URL? {
        let folder = directory(for: game.id, supportDirectory: supportDirectory)
        do { try fileManager.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }
        guard let system = systemCacheDirectory else { return folder }
        let dxmt = system.appendingPathComponent("dxmt")
        let programs = programNames(for: game, fileManager: fileManager)
        if !hasCache(in: folder, fileManager: fileManager) {
            // The largest earlier file is the one the game itself filled (a launcher stub saves little or nothing).
            func size(_ dir: URL) -> Int {
                ((try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
                    .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            }
            if let source = programs.map({ dxmt.appendingPathComponent($0) }).filter({ hasCache(in: $0, fileManager: fileManager) })
                .max(by: { size($0) < size($1) }) {
                for name in (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []
                where isDatabase(name) || (name.hasSuffix(".db-wal") && isDatabase(String(name.dropLast(4)))) {
                    // Copied, not moved: on the same APFS volume a copy is an instant clone that takes no extra space.
                    try? fileManager.copyItem(at: source.appendingPathComponent(name), to: folder.appendingPathComponent(name))
                }
            }
        }
        for program in programs { linkMetalCache(program: program, folder: folder, dxmt: dxmt, fileManager: fileManager) }
        return folder
    }

    /// Points `dxmt/<program>/com.apple.metal` at the game's own folder. An existing cache there moves into the game's
    /// folder if that has none yet; otherwise it is left as it is.
    static func linkMetalCache(program: String, folder: URL, dxmt: URL, fileManager: FileManager) {
        let target = metalDirectory(in: folder, program: program)
        let link = dxmt.appendingPathComponent(program).appendingPathComponent("com.apple.metal")
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
            if destination == target.path { return }
            try? fileManager.removeItem(at: link)   // a link to another game's folder: only the link goes
        } else if fileManager.fileExists(atPath: link.path) {
            guard !fileManager.fileExists(atPath: target.path) else { return }
            do {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: link, to: target)
            } catch { return }
        }
        do {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        } catch {}
    }

    /// Bytes saved for a game, for the game page.
    public static func size(for gameID: UUID, supportDirectory: URL, fileManager: FileManager = .default) -> Int {
        let folder = directory(for: gameID, supportDirectory: supportDirectory)
        guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in walker { total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }
}
