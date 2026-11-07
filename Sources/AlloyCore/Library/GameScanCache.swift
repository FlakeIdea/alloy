import Foundation

/// Remembers what scanning each game's files found (`GameTraits`), so a game is scanned once per version of its
/// program instead of each time its page opens or it starts. A scan reads every DLL beside the program and can take
/// a second or more on a large game. An entry is used only while the program's size, date and path are unchanged.
public final class GameScanCache: @unchecked Sendable {
    /// Raised whenever scanning finds something new (a new kind in `DLSSUsage`, say), so older results are redone.
    static let version = 2

    struct Entry: Codable { var fingerprint: String; var traits: GameTraits }
    struct File: Codable { var version: Int; var entries: [UUID: Entry] }

    public let url: URL
    private let lock = NSLock()
    private var entries: [UUID: Entry]

    public init(url: URL) {
        self.url = url
        let file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) }
        entries = file?.version == GameScanCache.version ? file?.entries ?? [:] : [:]
    }

    /// The saved result, if the game's program is unchanged since it was scanned.
    public func saved(for game: Game) -> GameTraits? {
        guard let fingerprint = ExecutableValidator.fingerprint(of: game.executableURL) else { return nil }
        return lock.withLock { entries[game.id].flatMap { $0.fingerprint == fingerprint ? $0.traits : nil } }
    }

    /// The saved result, or a fresh scan (saved for next time). Reads files, so call it off the main thread.
    public func traits(for game: Game, fileManager: FileManager = .default) -> GameTraits {
        if let saved = saved(for: game) { return saved }
        let traits = GameTraits.inspect(game, fileManager: fileManager)
        if let fingerprint = ExecutableValidator.fingerprint(of: game.executableURL) {
            lock.withLock { entries[game.id] = Entry(fingerprint: fingerprint, traits: traits) }
            save()
        }
        return traits
    }

    public func forget(_ gameID: UUID) {
        guard lock.withLock({ entries.removeValue(forKey: gameID) }) != nil else { return }
        save()
    }

    private func save() {
        let file = lock.withLock { File(version: GameScanCache.version, entries: entries) }
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
