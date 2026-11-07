import Foundation

/// Moves data saved under one of the app's former names (Metalgate, before that WildRun) to Alloy's folder, once.
/// A same-volume folder rename: nothing is copied or deleted, and game folders elsewhere are not touched.
public enum DataMigration {
    /// Former names, newest first, with the lowercase form used in file names and saved values.
    static let legacyNames: [(folder: String, token: String)] = [("Metalgate", "metalgate"), ("WildRun", "wildrun")]
    static let currentName = "Alloy"
    static let currentToken = "alloy"

    public struct Result: Equatable, Sendable {
        public var moved: Bool
        public var rewrittenFiles: Int
    }

    @discardableResult
    public static func migrateIfNeeded(applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                                         in: .userDomainMask)[0],
                                       fileManager: FileManager = .default) throws -> Result {
        let current = applicationSupport.appendingPathComponent(currentName)
        guard !fileManager.fileExists(atPath: current.path),
              let (legacyFolder, token) = legacyNames.first(where: {
                  fileManager.fileExists(atPath: applicationSupport.appendingPathComponent($0.folder).path)
              })
        else { return Result(moved: false, rewrittenFiles: 0) }
        let legacy = applicationSupport.appendingPathComponent(legacyFolder)
        try fileManager.moveItem(at: legacy, to: current)
        var rewritten = 0
        // Saved paths appear as plain paths and as file URLs, with JSON-escaped slashes or without.
        func forms(_ folder: URL) -> [String] {
            let plain = folder.path + "/"
            let url = folder.absoluteURL.absoluteString.hasSuffix("/") ? folder.absoluteURL.absoluteString : folder.absoluteURL.absoluteString + "/"
            return [plain, url].flatMap { [$0.replacingOccurrences(of: "/", with: "\\/"), $0] }
        }
        var replacements = Array(zip(forms(legacy), forms(current)))
        replacements.append(("\"origin\" : \"\(token)\"", "\"origin\" : \"\(currentToken)\""))
        func rewrite(_ url: URL) throws {
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let original = text
            for (old, new) in replacements { text = text.replacingOccurrences(of: old, with: new) }
            if text != original { try text.write(to: url, atomically: true, encoding: .utf8); rewritten += 1 }
        }
        func rename(_ old: String, _ new: String, in folder: URL) throws -> URL? {
            let from = folder.appendingPathComponent(old), to = folder.appendingPathComponent(new)
            guard fileManager.fileExists(atPath: from.path), !fileManager.fileExists(atPath: to.path) else { return nil }
            try fileManager.moveItem(at: from, to: to)
            return to
        }
        for file in (try? fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "json" { try rewrite(file) }

        let runtimes = current.appendingPathComponent("Runtimes")
        for folder in (try? fileManager.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: nil)) ?? [] {
            if let manifest = try rename("\(token)-runtime.json", D3DMetalImporter.manifestName, in: folder) { try rewrite(manifest) }
            if let marker = try rename("\(token)-package.json", RuntimeInstaller.markerName, in: folder) { try rewrite(marker) }
            _ = try rename("\(token)-backup", "\(currentToken)-backup", in: folder)
        }
        let prefixes = current.appendingPathComponent("Prefixes")
        for prefix in (try? fileManager.contentsOfDirectory(at: prefixes, includingPropertiesForKeys: nil)) ?? [] {
            _ = try rename(".\(token)-dxvk", PrefixManager.dxvkMarker, in: prefix)
            _ = try rename("\(token)-backup", "\(currentToken)-backup", in: prefix)
        }
        return Result(moved: true, rewrittenFiles: rewritten + renameEngines(applicationSupport: applicationSupport, fileManager: fileManager))
    }

    /// Engines installed under a former name keep it in their manifest ("Metalgate Game Engine (DXMT 0.80)"); the
    /// runtime list shows it. Renames the display name only: folders and IDs stay, so environments still find them.
    @discardableResult
    public static func renameEngines(applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                                        in: .userDomainMask)[0],
                                     fileManager: FileManager = .default) -> Int {
        let runtimes = applicationSupport.appendingPathComponent(currentName).appendingPathComponent("Runtimes")
        var renamed = 0
        for folder in (try? fileManager.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: nil)) ?? [] {
            let manifest = folder.appendingPathComponent(D3DMetalImporter.manifestName)
            guard var text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            let original = text
            for (old, _) in legacyNames {
                text = text.replacingOccurrences(of: "\"name\" : \"\(old) Game Engine", with: "\"name\" : \"\(currentName) Game Engine")
                text = text.replacingOccurrences(of: "\"name\": \"\(old) Game Engine", with: "\"name\": \"\(currentName) Game Engine")
            }
            if text != original, (try? text.write(to: manifest, atomically: true, encoding: .utf8)) != nil { renamed += 1 }
        }
        return renamed
    }
}
