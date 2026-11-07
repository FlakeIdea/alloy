import Foundation

/// What Steam knows about one game: which systems it is made for and how Steam starts it. Read from Steam's own
/// cache, `appcache/appinfo.vdf`, which the Steam client keeps up to date for every game in the account.
public struct SteamAppInfo: Equatable, Sendable {
    public struct Launch: Equatable, Sendable {
        public var executable: String
        public var arguments: String
        /// Steam's launch type: "default", "option1"…, "vr", "server", "editor", "none" or empty.
        public var type: String
        public var oslist: [String]
        public var workingDirectory: String
        public var betaKey: String
        public var needsDLC: Bool
    }

    public var appID: UInt32
    public var oslist: [String]
    public var installDirectory: String
    public var launches: [Launch]

    /// The game also has a native macOS version on Steam.
    public var hasMacVersion: Bool { oslist.contains("macos") }
}

public enum SteamAppInfoReader {
    public enum Problem: Error { case unknownFormat, truncated }

    private static let cache = Cache()

    /// Every app in Steam's cache, read again only when the file changes.
    public static func apps(steamFolder: URL) -> [UInt32: SteamAppInfo] {
        let file = steamFolder.appendingPathComponent("appcache/appinfo.vdf")
        let stamp = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        guard let stamp else { return [:] }
        if let hit = cache.get(file.path, stamp) { return hit }
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), let apps = try? parse(data) else { return [:] }
        cache.set(file.path, stamp, apps)
        return apps
    }

    /// Reads the binary `appinfo.vdf`: format 27 and 28 write keys inline, 29 (2024 on) uses a string table.
    public static func parse(_ data: Data) throws -> [UInt32: SteamAppInfo] {
        var reader = ByteReader(bytes: [UInt8](data))
        let magic = try reader.u32()
        _ = try reader.u32()  // universe
        var strings: [String]? = nil
        switch magic {
        case 0x07564427, 0x07564428: break
        case 0x07564429:
            let offset = Int(try reader.u64())
            var table = ByteReader(bytes: reader.bytes, position: offset)
            let count = Int(try table.u32())
            guard count < 1_000_000 else { throw Problem.unknownFormat }
            strings = try (0..<count).map { _ in try table.cString() }
        default: throw Problem.unknownFormat
        }
        let headerSize = magic == 0x07564427 ? 40 : 60   // 28 added a second SHA-1
        var apps: [UInt32: SteamAppInfo] = [:]
        while true {
            let appID = try reader.u32()
            if appID == 0 { break }
            let size = Int(try reader.u32())
            let end = reader.position + size
            guard end <= reader.bytes.count, size >= headerSize else { throw Problem.truncated }
            var values = ByteReader(bytes: reader.bytes, position: reader.position + headerSize)
            if let tree = try? values.keyValues(strings: strings), let info = info(appID: appID, tree: tree) {
                apps[appID] = info
            }
            reader.position = end
        }
        return apps
    }

    static func info(appID: UInt32, tree: [String: KeyValue]) -> SteamAppInfo? {
        let root = tree["appinfo"]?.section ?? tree
        let common = root["common"]?.section ?? [:]
        let config = root["config"]?.section ?? [:]
        let launches = (config["launch"]?.section ?? [:])
            .compactMap { key, value -> (Int, SteamAppInfo.Launch)? in
                guard let order = Int(key), let entry = value.section else { return nil }
                let settings = entry["config"]?.section ?? [:]
                return (order, SteamAppInfo.Launch(
                    executable: entry["executable"]?.text ?? "",
                    arguments: entry["arguments"]?.text ?? "",
                    type: (entry["type"]?.text ?? "").lowercased(),
                    oslist: list(settings["oslist"]?.text),
                    workingDirectory: entry["workingdir"]?.text ?? "",
                    betaKey: settings["betakey"]?.text ?? "",
                    needsDLC: settings["ownsdlc"] != nil))
            }
            .sorted { $0.0 < $1.0 }.map(\.1)
        return SteamAppInfo(appID: appID, oslist: list(common["oslist"]?.text),
                            installDirectory: config["installdir"]?.text ?? "", launches: launches)
    }

    private static func list(_ text: String?) -> [String] {
        (text ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public enum KeyValue: Equatable, Sendable {
        case section([String: KeyValue]), string(String), number(Int64)
        var section: [String: KeyValue]? { if case .section(let s) = self { return s }; return nil }
        var text: String? {
            switch self {
            case .string(let s): return s
            case .number(let n): return String(n)
            case .section: return nil
            }
        }
    }

    struct ByteReader {
        var bytes: [UInt8]
        var position = 0

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard position >= 0, count >= 0, position + count <= bytes.count else { throw Problem.truncated }
            defer { position += count }
            return bytes[position..<position + count]
        }
        mutating func u32() throws -> UInt32 { try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        mutating func u64() throws -> UInt64 { try take(8).reversed().reduce(0) { $0 << 8 | UInt64($1) } }
        mutating func cString() throws -> String {
            guard let end = bytes[position...].firstIndex(of: 0) else { throw Problem.truncated }
            let text = String(decoding: bytes[position..<end], as: UTF8.self)
            position = end + 1
            return text
        }

        /// Valve's binary KeyValues: a type byte, a key, then the value; type 8 ends a section.
        mutating func keyValues(strings: [String]?, depth: Int = 0) throws -> [String: KeyValue] {
            guard depth < 32 else { throw Problem.unknownFormat }
            var out: [String: KeyValue] = [:]
            while true {
                let type = try take(1).first!
                if type == 8 { return out }
                let key: String
                if let strings {
                    let index = Int(try u32())
                    guard index < strings.count else { throw Problem.unknownFormat }
                    key = strings[index]
                } else {
                    key = try cString()
                }
                switch type {
                case 0: out[key] = .section(try keyValues(strings: strings, depth: depth + 1))
                case 1: out[key] = .string(try cString())
                case 2, 4, 6: out[key] = .number(Int64(Int32(bitPattern: try u32())))
                case 3: _ = try u32(); out[key] = .number(0)    // float, unused here
                case 7, 10: out[key] = .number(Int64(bitPattern: try u64()))
                default: throw Problem.unknownFormat
                }
            }
        }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: (Date, [UInt32: SteamAppInfo])] = [:]
        func get(_ path: String, _ stamp: Date) -> [UInt32: SteamAppInfo]? {
            lock.withLock { entries[path].flatMap { $0.0 == stamp ? $0.1 : nil } }
        }
        func set(_ path: String, _ stamp: Date, _ apps: [UInt32: SteamAppInfo]) { lock.withLock { entries[path] = (stamp, apps) } }
    }
}

/// Starting a Steam game's own program instead of asking Steam to start it.
///
/// When Steam is already open, `steam.exe steam://rungameid/…` only hands the request to that Steam and exits, so
/// the game inherits the environment Steam was opened with: the graphics settings chosen for the game were not
/// used, and Alloy saw the game as closed after a fraction of a second. Starting the program Steam would start,
/// with the app id Steam gives it, keeps the game signed in to that running Steam and uses the game's own settings.
public enum SteamDirectLaunch {
    /// The launch Steam offers for playing on a Windows desktop: no VR, server, editor, beta or DLC-only entry.
    public static func choose(_ launches: [SteamAppInfo.Launch]) -> SteamAppInfo.Launch? {
        let usable = launches.filter { launch in
            (launch.oslist.isEmpty || launch.oslist.contains("windows"))
                && launch.betaKey.isEmpty && !launch.needsDLC
                && !["vr", "server", "editor", "manual"].contains(launch.type)
                && launch.executable.lowercased().hasSuffix(".exe")
        }
        let rank = ["default": 0, "": 0, "option1": 1, "option2": 2, "option3": 3, "none": 4]
        return usable.enumerated().min { a, b in
            (rank[a.element.type] ?? 5, a.offset) < (rank[b.element.type] ?? 5, b.offset)
        }?.element
    }

    /// A copy of a library entry that starts its game through Steam, set to start the game's program directly.
    /// Nil when Steam's cache doesn't say how, or the path it gives would leave the game's folder.
    public static func directGame(for game: Game, steamFolder: URL, apps: [UInt32: SteamAppInfo],
                                  fileManager: FileManager = .default) -> (game: Game, launch: SteamAppInfo.Launch)? {
        guard let appID = CoverArt.steamAppID(of: game).flatMap(UInt32.init), let info = apps[appID],
              let launch = choose(info.launches), launch.workingDirectory.isEmpty else { return nil }
        let manifest = steamFolder.appendingPathComponent("steamapps/appmanifest_\(appID).acf")
        let fromManifest = (try? String(contentsOf: manifest, encoding: .utf8)).flatMap { StoreLibraryScanner.vdfValues($0)["installdir"] }
        guard let installDirectory = fromManifest ?? (info.installDirectory.isEmpty ? nil : info.installDirectory),
              isPlainName(installDirectory) else { return nil }
        let relative = launch.executable.replacingOccurrences(of: "\\", with: "/")
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !relative.hasPrefix("/"), parts.allSatisfy(isPlainName) else { return nil }
        let folder = steamFolder.appendingPathComponent("steamapps/common/\(installDirectory)", isDirectory: true)
        guard fileManager.fileExists(atPath: folder.appendingPathComponent(relative).path) else { return nil }

        var direct = game
        direct.folder = folder
        direct.executableRelativePath = relative
        direct.arguments = splitArguments(launch.arguments)
        // What Steam sets for a game it starts; steam_api then joins the running Steam instead of restarting the game through it.
        direct.environment["SteamAppId"] = String(appID)
        direct.environment["SteamGameId"] = String(appID)
        return (direct, launch)
    }

    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    /// Splits Steam's argument string the way Windows does for simple cases: spaces separate, quotes group.
    public static func splitArguments(_ text: String) -> [String] {
        var out: [String] = [], current = "", quoted = false, started = false
        for character in text {
            if character == "\"" { quoted.toggle(); started = true }
            else if character == " " && !quoted { if started { out.append(current) }; current = ""; started = false }
            else { current.append(character); started = true }
        }
        if started { out.append(current) }
        return out
    }

    /// Whether Steam has signed in since `since`, from its `logs/connection_log.txt`. Each state change is a line such
    /// as `[2026-11-07 19:45:47] [Logged On, 4, 7] [U:1:…] …`, stamped in local time; the latest one counts.
    public static func signedIn(connectionLog: String, since: Date, timeZone: TimeZone = .current) -> Bool {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var state: String?
        for line in connectionLog.split(whereSeparator: \.isNewline) {
            // "[<date>] [<state>, …]": the second bracket holds a state only when a comma follows its first word(s).
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
                  let date = format.date(from: String(line[line.index(after: line.startIndex)..<close])),
                  date >= since.addingTimeInterval(-1) else { continue }
            let rest = line[line.index(after: close)...].drop { $0 == " " }
            guard rest.hasPrefix("["), let comma = rest.firstIndex(of: ","), let end = rest.firstIndex(of: "]"), comma < end
            else { continue }
            state = String(rest[rest.index(after: rest.startIndex)..<comma])
        }
        return state == "Logged On"
    }
}
