import Foundation

/// Cover art for the library, read from files already on the Mac: Steam keeps each game's library images in its
/// `appcache/librarycache` folder. Nothing is downloaded.
public enum CoverArt {
    public struct Images: Equatable, Sendable {
        /// Portrait box art (600×900).
        public var portrait: URL?
        /// The wide banner behind the game's page.
        public var hero: URL?
        /// The game's logo, drawn over the banner.
        public var logo: URL?
        public init(portrait: URL? = nil, hero: URL? = nil, logo: URL? = nil) {
            self.portrait = portrait
            self.hero = hero
            self.logo = logo
        }
        public var isEmpty: Bool { portrait == nil && hero == nil && logo == nil }
    }

    /// The Steam app id of a game Alloy starts through Steam (`steam://rungameid/<id>`).
    public static func steamAppID(of game: Game) -> String? {
        for argument in game.arguments where argument.lowercased().hasPrefix("steam://rungameid/") {
            let id = argument.dropFirst("steam://rungameid/".count).prefix { $0.isNumber }
            if !id.isEmpty { return String(id) }
        }
        return nil
    }

    /// Steam's image cache inside the environment it was installed in.
    public static func steamCache(in prefix: WinePrefix) -> URL? {
        StoreInstaller.executable(of: .steam, in: prefix)?.deletingLastPathComponent()
            .appendingPathComponent("appcache/librarycache")
    }

    /// Steam has stored these as `<id>_library_600x900.jpg` and, more recently, inside a `<id>/` folder (sometimes
    /// one level deeper), so both are searched.
    public static func steamImages(appID: String, cache: URL, fileManager: FileManager = .default) -> Images {
        var images = Images()
        // Recently Steam sometimes keeps only a smaller 300×450 `library_capsule`: used when there is no 600×900.
        var capsule: URL?
        func consider(_ url: URL) {
            let name = url.lastPathComponent.lowercased()
            if images.portrait == nil, name.contains("library_600x900") { images.portrait = url }
            else if capsule == nil, name.hasPrefix("library_capsule") { capsule = url }
            else if images.hero == nil, name.contains("library_hero"), !name.contains("blur") { images.hero = url }
            else if images.logo == nil, name.hasSuffix("logo.png") { images.logo = url }
        }
        let flat = (try? fileManager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
        for url in flat where url.lastPathComponent.hasPrefix(appID + "_") { consider(url) }
        let folder = cache.appendingPathComponent(appID, isDirectory: true)
        if let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil) {
            var seen = 0
            for case let url as URL in walker {
                seen += 1
                if seen > 200 { break }
                consider(url)
            }
        }
        if images.portrait == nil { images.portrait = capsule }
        return images
    }

    /// The game's own artwork when it has some, else Steam's.
    public static func images(for game: Game, prefix: WinePrefix?, fileManager: FileManager = .default) -> Images {
        var images = Images(portrait: game.artwork)
        if let id = steamAppID(of: game), let prefix, let cache = steamCache(in: prefix) {
            let steam = steamImages(appID: id, cache: cache, fileManager: fileManager)
            images.portrait = images.portrait ?? steam.portrait
            images.hero = steam.hero
            images.logo = steam.logo
        }
        return images
    }
}
