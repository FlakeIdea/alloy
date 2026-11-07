import Foundation

/// Windows game stores whose own apps Alloy can install in an environment, so games are bought, downloaded and
/// updated the normal way. Only each store's official installer is run, and only after the user asks for it.
public enum GameStore: String, CaseIterable, Codable, Sendable, Identifiable {
    case steam, epic, ea, ubisoft, gog, battlenet

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .steam: return "Steam"
        case .epic: return "Epic Games Launcher"
        case .ea: return "EA app"
        case .ubisoft: return "Ubisoft Connect"
        case .gog: return "GOG Galaxy"
        case .battlenet: return "Battle.net"
        }
    }

    /// Name of the environment the store gets, and of its library entry.
    public var environmentName: String {
        switch self {
        case .steam: return "Steam"
        case .epic: return "Epic Games"
        case .ea: return "EA app"
        case .ubisoft: return "Ubisoft Connect"
        case .gog: return "GOG Galaxy"
        case .battlenet: return "Battle.net"
        }
    }

    public var vendor: String {
        switch self {
        case .steam: return "Valve"
        case .epic: return "Epic Games"
        case .ea: return "EA"
        case .ubisoft: return "Ubisoft"
        case .gog: return "GOG"
        case .battlenet: return "Blizzard"
        }
    }

    /// The store's official installer address.
    public var installerURL: URL {
        switch self {
        case .steam: return URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!
        case .epic: return URL(string: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!
        case .ea: return URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")!
        case .ubisoft: return URL(string: "https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe")!
        case .gog: return URL(string: "https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe")!
        case .battlenet: return URL(string: "https://www.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live")!
        }
    }

    public var installerFileName: String {
        switch self {
        case .steam: return "SteamSetup.exe"
        case .epic: return "EpicGamesLauncherInstaller.msi"
        case .ea: return "EAappInstaller.exe"
        case .ubisoft: return "UbisoftConnectInstaller.exe"
        case .gog: return "GOG_Galaxy_2.0.exe"
        case .battlenet: return "Battle.net-Setup.exe"
        }
    }

    /// Hosts the download may end on after redirects. Anything else is refused, so a redirect cannot hand over
    /// another site's file.
    public var downloadHosts: [String] {
        switch self {
        case .steam: return ["steamstatic.com", "steampowered.com"]
        case .epic: return ["epicgames.com", "epicgames-download1.akamaized.net"]
        case .ea: return ["origin-a.akamaihd.net", "ea.com"]
        case .ubisoft: return ["ubi.com", "ubistatic3-a.akamaihd.net"]
        case .gog: return ["gog-statics.com", "gog.com"]
        case .battlenet: return ["battle.net", "blizzard.com"]
        }
    }

    /// Where the installer puts the store's app, relative to `drive_c`, preferred first.
    public var executablePaths: [String] {
        switch self {
        case .steam: return ["Program Files (x86)/Steam/steam.exe", "Program Files/Steam/steam.exe"]
        case .epic: return ["Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                            "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe"]
        case .ea: return ["Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe"]
        case .ubisoft: return ["Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe"]
        case .gog: return ["Program Files (x86)/GOG Galaxy/GalaxyClient.exe"]
        case .battlenet: return ["Program Files (x86)/Battle.net/Battle.net Launcher.exe", "Program Files (x86)/Battle.net/Battle.net.exe"]
        }
    }

    /// The store app's file name, which identifies it in the library.
    public var executableNames: Set<String> {
        Set(executablePaths.map { ($0 as NSString).lastPathComponent.lowercased() })
    }

    /// Arguments the store app starts with. Epic's launcher otherwise first runs its own prerequisites installer,
    /// which fails under Wine.
    public var launchArguments: [String] {
        self == .epic ? ["-SkipBuildPatchPrereq"] : []
    }

    /// How the installer runs: silently where the store supports it, else with its own windows.
    public var installerArguments: [String] {
        switch self {
        case .steam, .ubisoft: return ["/S"]
        case .epic: return ["/qb"]  // msiexec: progress only, no questions
        case .ea, .gog, .battlenet: return []
        }
    }

    /// True when the installer finishes by itself. The others end by starting the store app, so Alloy adds the
    /// library entry as soon as the app is on disk instead of waiting.
    public var installerExitsWhenDone: Bool { installerArguments.isEmpty == false }

    /// An address the store's app must reach to sign in. Used to tell a blocked network from a broken install.
    public var serviceURL: URL {
        switch self {
        case .steam: return URL(string: "https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/")!
        case .epic: return URL(string: "https://account-public-service-prod.ol.epicgames.com/account/api/oauth/verify")!
        case .ea: return URL(string: "https://accounts.ea.com/")!
        case .ubisoft: return URL(string: "https://public-ubiservices.ubi.com/")!
        case .gog: return URL(string: "https://auth.gog.com/")!
        case .battlenet: return URL(string: "https://account.battle.net/")!
        }
    }

    /// Steam and Epic are what Alloy's engine carries fixes for (Steam's web helper, and CrossOver's own fix for
    /// the Epic Games Launcher). The others run but have not been tested with Alloy.
    public var isExperimental: Bool { self != .steam && self != .epic }

    public var note: String {
        switch self {
        case .steam: return "Play games you own on Steam."
        case .epic: return "Play games from the Epic Games Store, including free weekly games."
        case .ea: return "EA games such as EA Sports FC and The Sims. Experimental."
        case .ubisoft: return "Ubisoft games such as Assassin’s Creed. Experimental."
        case .gog: return "Experimental. GOG games also come as offline installers on gog.com: add one with Install from Setup File."
        case .battlenet: return "Blizzard games such as Diablo and Overwatch. Experimental."
        }
    }

    /// The store whose app this library entry starts, if any.
    public static func store(for game: Game) -> GameStore? {
        let name = game.executableURL.lastPathComponent.lowercased()
        return allCases.first { $0.executableNames.contains(name) }
    }

    /// What a runtime lacks for this store. Every store signs in over HTTPS, which Wine checks with GnuTLS; Steam's
    /// windows also need the web helper fix.
    public func missingRequirements(in runtime: WineRuntime) -> [String] {
        var missing: [String] = []
        if self == .steam && !runtime.hasSteamWebHelperFix {
            missing.append("Steam's windows stay black: the runtime lacks the Steam web helper fix.")
        }
        if !runtime.hasGnuTLS {
            missing.append("\(displayName) cannot sign in: the runtime has no GnuTLS, so certificates cannot be checked.")
        }
        return missing
    }
}

/// Downloads a store's official installer and runs it in an environment.
public enum StoreInstaller {
    public static func executable(of store: GameStore, in prefix: WinePrefix, fileManager: FileManager = .default) -> URL? {
        store.executablePaths
            .map { prefix.path.appendingPathComponent("drive_c").appendingPathComponent($0) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    /// The installer as a game, so it gets the environment's runtime and settings. An `.msi` runs through the
    /// environment's own msiexec with the package's Windows path.
    public static func installerGame(_ store: GameStore, installer: URL, prefix: WinePrefix, graphics: GraphicsConfiguration) -> Game {
        if installer.pathExtension.lowercased() == "msi" {
            let system32 = prefix.path.appendingPathComponent("drive_c/windows/system32")
            return Game(name: "\(store.displayName) Setup", folder: system32, executableRelativePath: "msiexec.exe", prefixID: prefix.id,
                        arguments: ["/i", windowsPath(installer)] + store.installerArguments, graphics: graphics)
        }
        return Game(name: "\(store.displayName) Setup", folder: installer.deletingLastPathComponent(),
                    executableRelativePath: installer.lastPathComponent, prefixID: prefix.id,
                    arguments: store.installerArguments, graphics: graphics)
    }

    /// A macOS path as Wine's Z: drive sees it.
    public static func windowsPath(_ url: URL) -> String {
        "Z:" + url.standardizedFileURL.path.replacingOccurrences(of: "/", with: "\\")
    }

    /// Library entry for the installed store app. Games installed through it run in the same environment.
    public static func libraryEntry(_ store: GameStore, executable: URL, prefix: WinePrefix, graphics: GraphicsConfiguration) -> Game {
        Game(name: store.environmentName, folder: executable.deletingLastPathComponent(),
             executableRelativePath: executable.lastPathComponent, prefixID: prefix.id,
             arguments: store.launchArguments, graphics: graphics,
             notes: "Installed by Alloy. Games you install in \(store.displayName) run in the “\(prefix.name)” environment.")
    }

    /// Sets up the environment, downloads the installer, runs it and returns the library entry.
    public static func install(_ store: GameStore, into prefix: WinePrefix, runtime: WineRuntime, backend: WineBackend,
                               graphics: GraphicsConfiguration, installer: URL,
                               progress: @Sendable (String) -> Void) async throws -> Game {
        progress("Setting up the \(prefix.name) environment…")
        if !prefix.isInitialized() {
            let boot = LaunchSession(command: try backend.initializePrefixCommand(prefix: prefix, runtime: runtime), logFile: nil)
            try boot.start()
            guard boot.waitUntilExit(timeout: 300) == .exited(code: 0) else {
                throw AlloyError.launchFailed("Wine could not set up the \(prefix.name) environment.")
            }
        }
        progress("Downloading \(store.displayName) from \(store.vendor)…")
        do { try await download(store, to: installer) } catch let error as AlloyError {
            throw error
        } catch {
            throw AlloyError.downloadFailed("Could not download \(store.displayName): \(error.localizedDescription) If this network blocks game stores or inspects HTTPS, try another network.")
        }
        progress(store.installerArguments.isEmpty ? "Follow the \(store.displayName) installer’s steps…" : "Installing \(store.displayName)…")
        let setup = installerGame(store, installer: installer, prefix: prefix, graphics: graphics)
        let run = LaunchSession(command: try backend.launchCommand(for: setup, prefix: prefix, runtime: runtime, options: LaunchOptions()),
                                logFile: nil)
        try run.start()
        let found: URL?
        if store.installerExitsWhenDone {
            _ = await Task.detached { run.waitUntilExit(timeout: 1800) }.value
            found = executable(of: store, in: prefix)
        } else {
            found = await waitForExecutable(store, in: prefix, while: run, timeout: 3600)
        }
        guard let app = found else {
            throw AlloyError.launchFailed("The \(store.displayName) installer finished but its app was not found in \(prefix.name).")
        }
        return libraryEntry(store, executable: app, prefix: prefix, graphics: graphics)
    }

    /// Waits until the store's app is on disk and has stopped growing, or the installer ends without it.
    static func waitForExecutable(_ store: GameStore, in prefix: WinePrefix, while run: LaunchSession, timeout: TimeInterval) async -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSize: Int64 = -1
        while Date() < deadline {
            if let app = executable(of: store, in: prefix) {
                let size = (try? FileManager.default.attributesOfItem(atPath: app.path)[.size] as? NSNumber)?.int64Value ?? 0
                if size > 0 && size == lastSize { return app }
                lastSize = size
            } else if !run.state.isRunning {
                return nil
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return executable(of: store, in: prefix)
    }

    /// Downloads over HTTPS with the system's certificate checks, and only from the store's own hosts.
    public static func download(_ store: GameStore, to destination: URL) async throws {
        let (temporary, response) = try await AlloyHTTP.session.download(from: store.installerURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AlloyError.downloadFailed("\(store.vendor)'s server answered with HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        guard let host = http.url?.host?.lowercased(), http.url?.scheme == "https",
              store.downloadHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            try? FileManager.default.removeItem(at: temporary)
            throw AlloyError.downloadFailed("The \(store.displayName) download was redirected to \(http.url?.host ?? "another site"), which is not \(store.vendor)'s, so it was not used. A network filter may be answering in its place; try another network.")
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
    }
}

/// Games installed through a store's app, so they appear in the library and start through the store, which
/// signs them in and keeps them updated.
public enum StoreLibraryScanner {
    public struct Found: Hashable, Sendable {
        public var store: GameStore
        public var name: String
        /// What the store app is started with to run this game.
        public var launchArgument: String
    }

    public static func installedGames(of store: GameStore, in prefix: WinePrefix, fileManager: FileManager = .default) -> [Found] {
        switch store {
        case .steam: return steamGames(in: prefix, fileManager: fileManager)
        case .epic: return epicGames(in: prefix, fileManager: fileManager)
        default: return []
        }
    }

    /// True for a library entry that starts one game through its store, rather than the store app itself.
    public static func startsAGame(_ game: Game) -> Bool {
        GameStore.store(for: game) != nil && game.arguments.last?.contains("://") == true
    }

    /// Library entries for found games that the library does not have yet. They start the store app with its own
    /// arguments plus the game's address.
    public static func newEntries(for found: [Found], storeEntry: Game, existing: [Game]) -> [Game] {
        let known = Set(existing.filter { $0.prefixID == storeEntry.prefixID }.compactMap(\.arguments.last))
        return found.filter { !known.contains($0.launchArgument) }.map {
            Game(name: $0.name, folder: storeEntry.folder, executableRelativePath: storeEntry.executableRelativePath,
                 prefixID: storeEntry.prefixID, arguments: storeEntry.arguments + [$0.launchArgument],
                 graphics: storeEntry.graphics, notes: "Installed in \($0.store.displayName). Starts through \($0.store.displayName).")
        }
    }

    /// Steam writes `steamapps/appmanifest_<id>.acf` per game; StateFlags bit 4 means fully installed.
    static func steamGames(in prefix: WinePrefix, fileManager: FileManager) -> [Found] {
        guard let steam = StoreInstaller.executable(of: .steam, in: prefix) else { return [] }
        let apps = steam.deletingLastPathComponent().appendingPathComponent("steamapps")
        let files = (try? fileManager.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { url -> Found? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let values = vdfValues(text)
                guard let id = values["appid"], !id.isEmpty, id.allSatisfy(\.isNumber), id != "228980",  // Steamworks redistributables
                      let name = values["name"], !name.isEmpty,
                      let flags = values["StateFlags"].flatMap(Int.init), flags & 4 != 0 else { return nil }
                return Found(store: .steam, name: name, launchArgument: "steam://rungameid/\(id)")
            }
            .sorted { $0.name < $1.name }
    }

    /// Top-level `"key" "value"` pairs of a Valve KeyValues file.
    static func vdfValues(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        let pattern = try! NSRegularExpression(pattern: #"^\s*"([^"]+)"\s+"([^"]*)""#, options: .anchorsMatchLines)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let k = Range(match.range(at: 1), in: text), let v = Range(match.range(at: 2), in: text) else { continue }
            let key = String(text[k])
            if values[key] == nil { values[key] = String(text[v]) }
        }
        return values
    }

    /// The Epic Games Launcher writes one JSON `.item` manifest per installed game.
    static func epicGames(in prefix: WinePrefix, fileManager: FileManager) -> [Found] {
        let folder = prefix.path.appendingPathComponent("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests")
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        // Manifest values go into the launch address, so only the characters Epic's identifiers use are accepted.
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        func clean(_ s: Any?) -> String? {
            guard let s = s as? String, !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) else { return nil }
            return s
        }
        return files.filter { $0.pathExtension.lowercased() == "item" }
            .compactMap { url -> Found? in
                guard let data = try? Data(contentsOf: url),
                      let item = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (item["bIsIncompleteInstall"] as? Bool) != true,
                      let name = item["DisplayName"] as? String, !name.isEmpty,
                      let ns = clean(item["CatalogNamespace"]), let catalog = clean(item["CatalogItemId"]),
                      let app = clean(item["AppName"]) else { return nil }
                return Found(store: .epic, name: name,
                             launchArgument: "com.epicgames.launcher://apps/\(ns)%3A\(catalog)%3A\(app)?action=launch&silent=true")
            }
            .sorted { $0.name < $1.name }
    }
}

/// Whether this Mac's network lets a store's app sign in. Schools and workplaces often filter game stores; Wine
/// then fails with only a vague error, so Alloy checks from macOS and says what is wrong.
public enum StoreConnectivity {
    public enum Status: Equatable, Sendable {
        case reachable
        /// Other websites work but the store's servers do not answer, or a filter answers in their place.
        case blockedByNetwork
        case offline
    }

    /// Apple's own connectivity check page.
    public static let controlURL = URL(string: "https://www.apple.com/library/test/success.html")!

    public static func check(_ store: GameStore, session: URLSession = AlloyHTTP.session) async -> Status {
        if await reachable(store.serviceURL, session: session) { return .reachable }
        return await reachable(controlURL, session: session) ? .blockedByNetwork : .offline
    }

    /// Any answer from the real server counts, even an error status: only no answer, or a filter's page, does not.
    static func reachable(_ url: URL, session: URLSession) async -> Bool {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return !looksLikeBlockPage(status: http.statusCode, body: data)
    }

    static let blockPageMarkers = ["web filter violation", "fortiguard", "web page blocked", "access blocked", "site blocked",
                                   "this site is blocked", "blocked by your", "internet usage policy", "zscaler", "cisco umbrella",
                                   "sophos web", "barracuda", "websense", "lightspeed systems", "securly", "content filter"]

    /// A filter that inspects HTTPS answers with its own page; its words give it away.
    public static func looksLikeBlockPage(status: Int, body: Data) -> Bool {
        guard status == 403 || status == 200 || status == 302 || status == 451 || status == 511 else { return false }
        let text = String(decoding: body.prefix(65_536), as: UTF8.self).lowercased()
        return blockPageMarkers.contains { text.contains($0) }
    }

    public static func explanation(_ status: Status, store: GameStore) -> String? {
        switch status {
        case .reachable: return nil
        case .blockedByNetwork:
            return "\(store.displayName)'s sign-in servers can't be reached, although other websites work. Networks at schools and workplaces often filter game stores. Connect to another network, such as your home Wi-Fi or your phone’s hotspot, then try again."
        case .offline:
            return "This Mac is not connected to the internet, so \(store.displayName) cannot sign in."
        }
    }
}
