import Foundation

/// Anti-cheat a game ships, found by the folders and files it installs. Shown before the first start, so people know
/// why an online mode may refuse to run. Alloy never alters or gets around anti-cheat.
public enum AntiCheat {
    static let markers: [(name: String, entries: Set<String>)] = [
        ("Easy Anti-Cheat", ["easyanticheat", "easyanticheat_eos", "easyanticheat_eos_setup.exe", "easyanticheat_setup.exe",
                             "start_protected_game.exe"]),
        ("BattlEye", ["battleye", "beservice.exe", "beservice_x64.exe"]),
        ("Riot Vanguard", ["vgc.exe", "vgk.sys"]),
    ]

    /// Names of the anti-cheat systems found within three levels of the game folder. Stops after a few thousand
    /// entries so a huge folder stays quick.
    public static func detect(in folder: URL, fileManager: FileManager = .default) -> [String] {
        guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [String] = []
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > 4000 { break }
            if walker.level >= 3 { walker.skipDescendants() }
            let name = url.lastPathComponent.lowercased()
            for marker in markers where !found.contains(marker.name) && marker.entries.contains(name) {
                found.append(marker.name)
            }
            if found.count == markers.count { break }
        }
        return markers.map(\.name).filter(found.contains)
    }
}
