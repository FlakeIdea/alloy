import Foundation

/// Installs a game from its Windows setup program (setup.exe or .msi) into the game's own environment, then finds
/// the game among the programs the setup added. The setup runs only after the user chose it and confirmed.
public enum GameInstaller {
    /// Folders under drive_c that setups install into; Windows' own folder is never searched.
    static let skippedTopFolders: Set<String> = ["windows"]

    /// Programs under drive_c, as paths relative to drive_c.
    public static func executables(in prefix: WinePrefix, limit: Int = 50_000, fileManager: FileManager = .default) -> Set<String> {
        let root = prefix.path.appendingPathComponent("drive_c").standardizedFileURL.resolvingSymlinksInPath()
        let base = root.path + "/"
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: Set<String> = []
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > limit { break }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count))
            let parts = relative.split(separator: "/")
            if parts.count == 1, skippedTopFolders.contains(parts[0].lowercased()) { walker.skipDescendants(); continue }
            // Wine links "My Documents" and friends to the Mac's home folders; never walk into those.
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { walker.skipDescendants(); continue }
            if url.pathExtension.lowercased() == "exe" { found.insert(relative) }
        }
        return found
    }

    /// The folder holding most of the new programs, two levels below drive_c (for example
    /// "Program Files/Some Game" or "GOG Games/Some Game"), or one level for setups that install to C:\SomeGame.
    public static func installFolder(newExecutables: Set<String>) -> String? {
        let installers = ExecutableScanner.ignoredNames
        let useful = newExecutables.filter { path in
            let name = (path as NSString).lastPathComponent.lowercased()
            return !installers.contains { name.contains($0) }
        }
        var counts: [String: Int] = [:]
        for path in useful.isEmpty ? newExecutables : useful {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let containers = ["program files", "program files (x86)", "gog games", "games", "users", "programdata"]
            let depth = containers.contains(parts[0].lowercased()) && parts.count >= 3 ? 2 : 1
            counts[parts.prefix(depth).joined(separator: "/"), default: 0] += 1
        }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// A library entry for what the setup installed, or nil when it added no program Alloy can start.
    public static func installedGame(name: String, newExecutables: Set<String>, prefix: WinePrefix) -> Game? {
        guard let relativeFolder = installFolder(newExecutables: newExecutables) else { return nil }
        let folder = prefix.path.appendingPathComponent("drive_c").appendingPathComponent(relativeFolder)
        guard let best = ExecutableScanner.scan(folder: folder).first(where: { $0.score >= 0 && $0.machine?.isSupportedByWineOnMac == true }) else {
            return nil
        }
        return Game(name: name, folder: folder, executableRelativePath: best.relativePath, prefixID: prefix.id,
                    artwork: ArtworkFinder.find(in: folder))
    }

    /// Windows path for a Mac file, through the Z: drive Wine maps to "/".
    public static func windowsPath(for url: URL) -> String {
        "Z:" + url.standardizedFileURL.path.replacingOccurrences(of: "/", with: "\\")
    }

    /// The command that runs the setup: the program itself, or Wine's msiexec for an .msi package.
    public static func setupCommand(installer: URL, prefix: WinePrefix, runtime: WineRuntime, backend: WineBackend) throws -> LaunchCommand {
        if installer.pathExtension.lowercased() == "msi" {
            return try backend.wineToolCommand(["msiexec", "/i", windowsPath(for: installer)], prefix: prefix, runtime: runtime)
        }
        let game = Game(name: "Setup", folder: installer.deletingLastPathComponent(),
                        executableRelativePath: installer.lastPathComponent, prefixID: prefix.id)
        return try backend.launchCommand(for: game, prefix: prefix, runtime: runtime, options: LaunchOptions())
    }

    /// A display name from the setup's file name: "setup_some_game_1.2.exe" → "Some Game".
    public static func suggestedName(for installer: URL) -> String {
        var stem = installer.deletingPathExtension().lastPathComponent
        for noise in ["setup_", "setup-", "install_", "_setup", "-setup", "setup", "installer"] {
            stem = stem.replacingOccurrences(of: noise, with: " ", options: .caseInsensitive)
        }
        let words = stem.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").filter { !$0.allSatisfy { $0.isNumber || $0 == "." || $0 == "(" || $0 == ")" } }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name.isEmpty ? "New Game" : name
    }
}
