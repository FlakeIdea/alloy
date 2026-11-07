import Foundation

/// A game to install through a store's app, from a store link or Steam app ID the person pasted.
///
/// Stores keep the list of games someone owns behind their sign-in (Steam's Web API needs a key, Epic's library API
/// the launcher's token), and Alloy doesn't handle store credentials. So Alloy hands the game to the store app itself:
/// Steam opens its install dialog for the app ID, Epic's launcher opens the game's page with its Install button. The
/// store checks ownership and downloads into its environment; Alloy shows the progress and adds the game when done.
public struct StoreGameLink: Equatable, Sendable {
    public var store: GameStore
    /// Steam app ID, or Epic product slug.
    public var id: String

    /// What the store app is started with.
    public var address: String {
        switch store {
        case .epic: return "com.epicgames.launcher://store/product/\(id)"
        default: return "steam://install/\(id)"
        }
    }

    public var summary: String {
        switch store {
        case .epic: return "Epic Games Store: \(id)"
        default: return "Steam app \(id)"
        }
    }

    /// Accepts a Steam app ID, a Steam store, community or SteamDB link, a `steam://` link, an Epic Games Store
    /// link or a `com.epicgames.launcher://` store link. Anything else, or any character an ID can't have, is refused,
    /// because the result is passed to the store app.
    public static func parse(_ text: String) -> StoreGameLink? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func steamID(_ v: Substring?) -> StoreGameLink? {
            guard let v, (1...10).contains(v.count), v.allSatisfy({ $0.isASCII && $0.isNumber }), v != "0" else { return nil }
            return StoreGameLink(store: .steam, id: String(v))
        }
        func epicSlug(_ v: Substring?) -> StoreGameLink? {
            let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
            guard let v = v?.lowercased(), (1...100).contains(v.count), v.allSatisfy(allowed.contains),
                  v.first != "-" else { return nil }
            return StoreGameLink(store: .epic, id: v)
        }
        if let id = steamID(Substring(s)) { return id }
        let lower = s.lowercased()
        if lower.hasPrefix("steam://") {
            // steam://install/570, steam://run/570, steam://rungameid/570, steam://store/570
            let parts = s.dropFirst("steam://".count).split(separator: "/")
            guard parts.count >= 2, ["install", "run", "rungameid", "store"].contains(parts[0].lowercased()) else { return nil }
            return steamID(parts[1])
        }
        if lower.hasPrefix("com.epicgames.launcher://store/") {
            let parts = s.dropFirst("com.epicgames.launcher://store/".count).split(separator: "/")
            guard parts.count >= 2, ["product", "p"].contains(parts[0].lowercased()) else { return nil }
            return epicSlug(parts[1])
        }
        let withScheme = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? s : "https://" + s
        guard let url = URL(string: withScheme), let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        func after(_ marker: String) -> Substring? {
            guard let i = path.firstIndex(where: { $0.lowercased() == marker }), i + 1 < path.count else { return nil }
            return Substring(path[i + 1])
        }
        switch host {
        case "store.steampowered.com", "steamcommunity.com", "www.steamcommunity.com", "steamdb.info":
            return steamID(after("app"))
        case "store.epicgames.com", "www.epicgames.com", "epicgames.com":
            return epicSlug(after("p") ?? after("product"))
        default:
            return nil
        }
    }
}

/// A game a store app is downloading into its environment, read from the store's own files.
public struct StoreDownload: Equatable, Identifiable, Sendable {
    public var store: GameStore
    public var id: String
    public var name: String
    /// 0…1 when the store records it (Steam does; Epic's manifest doesn't).
    public var fraction: Double?
    public var paused: Bool
}

public enum StoreDownloads {
    public static func current(of store: GameStore, in prefix: WinePrefix, fileManager: FileManager = .default) -> [StoreDownload] {
        switch store {
        case .steam: return steam(in: prefix, fileManager: fileManager)
        case .epic: return epic(in: prefix, fileManager: fileManager)
        default: return []
        }
    }

    /// Steam writes `steamapps/appmanifest_<id>.acf` as soon as a download starts. Until the game is fully installed
    /// (StateFlags bit 4) the manifest carries `BytesDownloaded` and `BytesToDownload`; bit 512 means paused.
    static func steam(in prefix: WinePrefix, fileManager: FileManager) -> [StoreDownload] {
        guard let steam = StoreInstaller.executable(of: .steam, in: prefix) else { return [] }
        let apps = steam.deletingLastPathComponent().appendingPathComponent("steamapps")
        let files = (try? fileManager.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { url -> StoreDownload? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let v = StoreLibraryScanner.vdfValues(text)
                guard let id = v["appid"], !id.isEmpty, id.allSatisfy(\.isNumber), id != "228980",
                      let flags = v["StateFlags"].flatMap(Int.init), flags & 4 == 0 else { return nil }
                let total = v["BytesToDownload"].flatMap(Double.init) ?? 0
                let done = v["BytesDownloaded"].flatMap(Double.init) ?? 0
                return StoreDownload(store: .steam, id: id, name: v["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "Steam app \(id)",
                                     fraction: total > 0 ? min(1, done / total) : nil, paused: flags & 512 != 0)
            }
            .sorted { $0.name < $1.name }
    }

    /// Epic's launcher writes the game's `.item` manifest when an install starts, with `bIsIncompleteInstall` set
    /// until it finishes.
    static func epic(in prefix: WinePrefix, fileManager: FileManager) -> [StoreDownload] {
        let folder = prefix.path.appendingPathComponent("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests")
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "item" }
            .compactMap { url -> StoreDownload? in
                guard let data = try? Data(contentsOf: url),
                      let item = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (item["bIsIncompleteInstall"] as? Bool) == true,
                      let name = item["DisplayName"] as? String, !name.isEmpty else { return nil }
                return StoreDownload(store: .epic, id: (item["AppName"] as? String) ?? name, name: name, fraction: nil, paused: false)
            }
            .sorted { $0.name < $1.name }
    }
}
