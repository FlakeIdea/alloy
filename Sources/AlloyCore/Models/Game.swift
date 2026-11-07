import Foundation

public struct Game: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Folder the user selected. Alloy never moves or deletes anything inside it.
    public var folder: URL
    /// Main executable, relative to `folder`.
    public var executableRelativePath: String
    public var prefixID: UUID?
    public var runtimeID: String?
    public var arguments: [String]
    public var environment: [String: String]
    public var graphics: GraphicsConfiguration
    public var artwork: URL?
    public var notes: String
    public var dateAdded: Date
    public var lastPlayed: Date?
    /// Fingerprint of the executable the user last confirmed. A changed file asks again.
    public var confirmedExecutableFingerprint: String?
    /// The person chose "Not now" on the frame-generation offer, so the game page doesn't offer it again.
    public var declinedFrameGeneration = false
    /// A Windows app (an editor, a utility, a launcher for something else) rather than a game: opened, not played, and
    /// without game graphics modes or DLSS.
    public var isApp = false
    /// DLLs the person added to this game's environment; Wine loads them before its own.
    public var customDLLs: [CustomDLL] = []

    public init(id: UUID = UUID(),
                name: String,
                folder: URL,
                executableRelativePath: String,
                prefixID: UUID? = nil,
                runtimeID: String? = nil,
                arguments: [String] = [],
                environment: [String: String] = [:],
                graphics: GraphicsConfiguration = GraphicsConfiguration(),
                artwork: URL? = nil,
                notes: String = "",
                dateAdded: Date = Date()) {
        self.id = id
        self.name = name
        self.folder = folder
        self.executableRelativePath = executableRelativePath
        self.prefixID = prefixID
        self.runtimeID = runtimeID
        self.arguments = arguments
        self.environment = environment
        self.graphics = graphics
        self.artwork = artwork
        self.notes = notes
        self.dateAdded = dateAdded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decode(URL.self, forKey: .folder)
        executableRelativePath = try c.decode(String.self, forKey: .executableRelativePath)
        prefixID = try c.decodeIfPresent(UUID.self, forKey: .prefixID)
        runtimeID = try c.decodeIfPresent(String.self, forKey: .runtimeID)
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        graphics = try c.decodeIfPresent(GraphicsConfiguration.self, forKey: .graphics) ?? GraphicsConfiguration()
        artwork = try c.decodeIfPresent(URL.self, forKey: .artwork)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        confirmedExecutableFingerprint = try c.decodeIfPresent(String.self, forKey: .confirmedExecutableFingerprint)
        declinedFrameGeneration = try c.decodeIfPresent(Bool.self, forKey: .declinedFrameGeneration) ?? false
        isApp = try c.decodeIfPresent(Bool.self, forKey: .isApp) ?? false
        customDLLs = try c.decodeIfPresent([CustomDLL].self, forKey: .customDLLs) ?? []
    }

    public var executableURL: URL {
        folder.appendingPathComponent(executableRelativePath).standardizedFileURL
    }
}

public enum ExecutableValidator {
    /// Checks that the executable exists, stays inside the game folder and is a runnable PE image.
    @discardableResult
    public static func validate(_ game: Game, fileManager: FileManager = .default) throws -> PEInfo {
        let exe = game.executableURL.resolvingSymlinksInPath()
        let folder = game.folder.standardizedFileURL.resolvingSymlinksInPath()
        let folderPath = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        guard exe.path.hasPrefix(folderPath) else {
            throw AlloyError.executableOutsideGameFolder(path: game.executableRelativePath)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: exe.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AlloyError.executableNotFound(path: exe.path)
        }
        let info = try PEInspector.inspect(exe)
        guard !info.isDLL else { throw AlloyError.notAWindowsExecutable(path: exe.lastPathComponent) }
        guard info.machine.isSupportedByWineOnMac else {
            throw AlloyError.unsupportedExecutableArchitecture(info.machine.rawValue)
        }
        return info
    }

    /// Size + modification date + path. Cheap, and changes whenever the file is replaced.
    public static func fingerprint(of url: URL, fileManager: FileManager = .default) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              let date = attrs[.modificationDate] as? Date else { return nil }
        return "\(url.path)|\(size.int64Value)|\(Int(date.timeIntervalSince1970))"
    }
}
