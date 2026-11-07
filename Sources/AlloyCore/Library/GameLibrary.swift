import Foundation

/// The persisted list of games. Removing an entry never touches the game's files.
public final class GameLibrary {
    struct Document: Codable {
        var version: Int = 1
        var games: [Game] = []
    }

    public private(set) var games: [Game]
    private let store: JSONFileStore<Document>

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL)
        games = store.load(default: Document()).games
    }

    public func add(_ game: Game) throws {
        games.append(game)
        try persist()
    }

    public func update(_ game: Game) throws {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        try persist()
    }

    /// Removes the library entry only.
    public func remove(id: UUID) throws {
        games.removeAll { $0.id == id }
        try persist()
    }

    public func game(id: UUID) -> Game? { games.first { $0.id == id } }

    private func persist() throws {
        try store.save(Document(games: games))
    }
}

/// Finds candidate `.exe` files in a game folder and ranks the likely main executable first.
public enum ExecutableScanner {
    public struct Candidate: Hashable, Sendable {
        public var relativePath: String
        public var score: Int
        public var machine: PEMachine?
    }

    static let ignoredNames = ["unins", "uninstall", "setup", "vc_redist", "vcredist", "dxsetup", "dxwebsetup",
                               "crashreport", "unrealcefsubprocess", "ue4prereqsetup", "ueprereqsetup",
                               "easyanticheat", "dotnet", "redist", "updater", "crashpad", "cefsharp"]

    public static func scan(folder: URL, maxDepth: Int = 6, fileManager: FileManager = .default) -> [Candidate] {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey],
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var results: [Candidate] = []
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        for case let url as URL in enumerator {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let relative = String(resolved.path.dropFirst(basePath.count))
            let depth = relative.split(separator: "/").count - 1
            if depth >= maxDepth { enumerator.skipDescendants() }
            guard url.pathExtension.lowercased() == "exe" else { continue }
            let machine = (try? PEInspector.inspect(url))?.machine
            results.append(Candidate(relativePath: relative, score: score(relative, depth: depth, machine: machine),
                                     machine: machine))
        }
        return results.sorted { $0.score != $1.score ? $0.score > $1.score : $0.relativePath < $1.relativePath }
    }

    static func score(_ relativePath: String, depth: Int, machine: PEMachine?) -> Int {
        let name = (relativePath as NSString).lastPathComponent.lowercased()
        let lowerPath = relativePath.lowercased()
        if ignoredNames.contains(where: { name.contains($0) }) || lowerPath.contains("redist") { return -100 }
        var score = 50 - depth * 5
        if machine == nil { score -= 40 }
        if machine == .x64 { score += 5 }
        // Unreal Engine: the root launcher is preferred; it starts the -Shipping binary with the right arguments.
        if depth == 0 { score += 20 }
        if name.contains("shipping") { score += 10 }
        if lowerPath.contains("engine/binaries") { score -= 30 }
        return score
    }
}

/// Splits a user-typed argument string into an argument vector. Supports quotes and backslash escapes.
/// The result is passed directly to `Process`, never to a shell.
public enum ArgumentParser {
    public static func split(_ input: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inToken = false
        var quote: Character?
        var escaping = false
        for ch in input {
            if escaping {
                current.append(ch); escaping = false; inToken = true; continue
            }
            if ch == "\\" && quote != "'" { escaping = true; inToken = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                continue
            }
            if ch == "\"" || ch == "'" { quote = ch; inToken = true; continue }
            if ch.isWhitespace {
                if inToken { args.append(current); current = ""; inToken = false }
                continue
            }
            current.append(ch); inToken = true
        }
        if inToken { args.append(current) }
        return args
    }

    /// Inverse of `split`, for display in a text field.
    public static func join(_ args: [String]) -> String {
        args.map { arg in
            if arg.isEmpty { return "\"\"" }
            if arg.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }) {
                return "\"" + arg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }
            return arg
        }.joined(separator: " ")
    }
}

/// Validates user-supplied environment variables.
public enum EnvironmentValidator {
    /// Variables that could inject code into host processes or that Alloy manages itself.
    public static let blockedPrefixes = ["DYLD_", "LD_"]
    public static let managedKeys: Set<String> = ["WINEPREFIX", "WINEDEBUG"]

    public static func validate(_ environment: [String: String]) throws {
        for key in environment.keys {
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw AlloyError.invalidEnvironmentKey(key)
            }
            if blockedPrefixes.contains(where: { key.uppercased().hasPrefix($0) }) || managedKeys.contains(key) {
                throw AlloyError.blockedEnvironmentKey(key)
            }
        }
    }
}

/// Finds local artwork in a game folder. No network lookups.
public enum ArtworkFinder {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "ico", "bmp"]
    static let keywords = ["cover", "capsule", "header", "banner", "hero", "library", "logo", "icon"]

    public static func find(in folder: URL, fileManager: FileManager = .default) -> URL? {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var best: (url: URL, rank: Int)?
        for case let url as URL in enumerator {
            if enumerator.level > 2 { enumerator.skipDescendants(); continue }
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            guard let rank = keywords.firstIndex(where: { name.contains($0) }) else { continue }
            if best == nil || rank < best!.rank { best = (url, rank) }
        }
        return best?.url
    }
}
