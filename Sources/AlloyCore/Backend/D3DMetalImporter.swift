import Foundation

/// The `redist/lib` folder from Apple's Game Porting Toolkit disk image, which the user downloads themselves.
public struct D3DMetalRedistributable: Equatable, Sendable {
    /// The `lib` folder containing `external/` and `wine/`.
    public var lib: URL
    public var version: String?

    public var framework: URL { lib.appendingPathComponent("external/D3DMetal.framework") }
}

/// Written next to each Alloy-managed runtime so it can be identified and explained later.
public struct ManagedRuntimeManifest: Codable, Equatable, Sendable {
    public var name: String
    /// The Wine install this runtime was copied from; nil for a runtime installed from a downloaded package,
    /// whose build machine's folders mean nothing here (scripts/package-runtime.sh drops them).
    public var baseRuntimePath: String?
    public var baseRuntimeVersion: String?
    public var d3dMetalVersion: String?
    public var d3dMetalSource: String?
    public var createdAt: Date
    /// `TranslationLayer` raw value; nil in manifests written before DXMT support (those are D3DMetal).
    public var translationLayer: String? = nil
}

public enum TranslationLayer: String, Sendable {
    case d3dMetal
    case dxmt
    /// A plain Wine build (e.g. compiled from CodeWeavers' CrossOver sources) with no extra layer.
    case none
}

/// Copies a self-built Wine install (a folder with `bin/wine`) into Alloy's managed runtimes.
public enum WineBuildImporter {
    @discardableResult
    public static func importBuild(root: URL, name: String, source: String, runtimesDirectory: URL,
                                   fileManager: FileManager = .default) throws -> URL {
        guard fileManager.isExecutableFile(atPath: root.appendingPathComponent("bin/wine").path) else {
            throw AlloyError.runtimeUnavailable("\(root.path) has no executable bin/wine.")
        }
        let folder = runtimesDirectory.appendingPathComponent("\(PrefixManager.slug(name))-\(UUID().uuidString.prefix(8))")
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.copyItem(at: root.resolvingSymlinksInPath(), to: folder.appendingPathComponent("wine"))
            let manifest = ManagedRuntimeManifest(name: name, baseRuntimePath: root.appendingPathComponent("bin/wine").path,
                                                  baseRuntimeVersion: nil, d3dMetalVersion: nil, d3dMetalSource: source,
                                                  createdAt: Date(), translationLayer: TranslationLayer.none.rawValue)
            try JSONFileStore<ManagedRuntimeManifest>(fileURL: folder.appendingPathComponent(D3DMetalImporter.manifestName)).save(manifest)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw AlloyError.persistenceFailed("Could not import the Wine build: \(error.localizedDescription)")
        }
        return folder
    }
}

/// A DXMT release folder (e.g. `v0.80/`) holding `x86_64-unix/winemetal.so` and `x86_64-windows/*.dll`.
public struct DXMTRelease: Equatable, Sendable {
    public var root: URL
    public var version: String?
}

/// Builds DXMT runtimes the same way as D3DMetal: a *copy* of a Wine runtime with DXMT's builtin DLLs merged into `lib/wine`.
public enum DXMTImporter {
    public static let architectures = ["x86_64-unix", "x86_64-windows", "i386-windows"]

    public static func locate(in root: URL, maxDepth: Int = 3, fileManager: FileManager = .default) -> DXMTRelease? {
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            if fileManager.fileExists(atPath: dir.appendingPathComponent("x86_64-unix/winemetal.so").path),
               fileManager.fileExists(atPath: dir.appendingPathComponent("x86_64-windows/d3d11.dll").path) {
                let name = dir.lastPathComponent
                return DXMTRelease(root: dir, version: name.hasPrefix("v") ? String(name.dropFirst()) : nil)
            }
            guard depth < maxDepth, let children = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for child in children.sorted(by: { $0.path < $1.path })
            where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    @discardableResult
    public static func makeManagedRuntime(name: String, base: WineRuntime, release: DXMTRelease, source: String,
                                          runtimesDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        if let major = base.version.flatMap({ Int($0.prefix { $0.isNumber }) }), major < 8 {
            throw AlloyError.runtimeUnavailable("DXMT needs a modern Wine (8 or newer); \(base.displayName) is too old.")
        }
        let folder = runtimesDirectory.appendingPathComponent("\(PrefixManager.slug(name))-\(UUID().uuidString.prefix(8))")
        let wineLib = folder.appendingPathComponent("wine/lib/wine")
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.copyItem(at: base.root.resolvingSymlinksInPath(), to: folder.appendingPathComponent("wine"))
            for arch in architectures where fileManager.fileExists(atPath: release.root.appendingPathComponent(arch).path) {
                try D3DMetalImporter.merge(from: release.root.appendingPathComponent(arch),
                                           into: wineLib.appendingPathComponent(arch), fileManager: fileManager)
            }
            let manifest = ManagedRuntimeManifest(name: name, baseRuntimePath: base.wineBinary.path,
                                                  baseRuntimeVersion: base.version, d3dMetalVersion: nil,
                                                  d3dMetalSource: source, createdAt: Date(),
                                                  translationLayer: TranslationLayer.dxmt.rawValue)
            try JSONFileStore<ManagedRuntimeManifest>(fileURL: folder.appendingPathComponent(D3DMetalImporter.manifestName)).save(manifest)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw AlloyError.persistenceFailed("Could not build the DXMT runtime: \(error.localizedDescription)")
        }
        return folder
    }
}

/// Builds D3DMetal-capable runtimes by merging Apple's redistributable into a *copy* of a Wine runtime.
/// The source Wine install and the Toolkit image are only read. Removing the managed folder undoes everything.
public enum D3DMetalImporter {
    public static let manifestName = "alloy-runtime.json"

    /// Finds `redist/lib` (or a bare `lib`) containing D3DMetal under a mounted volume or folder.
    public static func locate(in root: URL, maxDepth: Int = 4, fileManager: FileManager = .default) -> D3DMetalRedistributable? {
        func check(_ lib: URL) -> D3DMetalRedistributable? {
            let external = lib.appendingPathComponent("external")
            guard fileManager.fileExists(atPath: external.appendingPathComponent("D3DMetal.framework").path),
                  fileManager.fileExists(atPath: external.appendingPathComponent("libd3dshared.dylib").path) else { return nil }
            return D3DMetalRedistributable(lib: lib, version: frameworkVersion(external.appendingPathComponent("D3DMetal.framework")))
        }
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            if dir.lastPathComponent == "lib", let found = check(dir) { return found }
            guard depth < maxDepth,
                  let children = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: [.skipsHiddenFiles]) else { continue }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && child.pathExtension != "framework" && child.pathExtension != "app" {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    /// Places Apple's toolkit is usually found once the person has downloaded it and accepted Apple's licence: its
    /// mounted disk image, and Game Porting Toolkit installs. Only read; Alloy never downloads or ships D3DMetal.
    public static func candidateFolders(fileManager: FileManager = .default) -> [URL] {
        var folders: [URL] = []
        let volumes = URL(fileURLWithPath: "/Volumes")
        for volume in (try? fileManager.contentsOfDirectory(at: volumes, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
            // The startup disk appears here as a link to "/"; scanning it would take minutes.
            if volume.resolvingSymlinksInPath().path == "/" { continue }
            folders.append(volume)
        }
        for path in ["/Applications/Game Porting Toolkit.app/Contents/Resources",
                     "/opt/homebrew/opt/game-porting-toolkit", "/usr/local/opt/game-porting-toolkit"] {
            if fileManager.fileExists(atPath: path) { folders.append(URL(fileURLWithPath: path)) }
        }
        return folders
    }

    /// The newest D3DMetal already on this Mac, if any.
    public static func findOnThisMac(fileManager: FileManager = .default) -> D3DMetalRedistributable? {
        candidateFolders(fileManager: fileManager)
            .compactMap { locate(in: $0, maxDepth: 5, fileManager: fileManager) }
            .max { ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedAscending }
    }

    static func frameworkVersion(_ framework: URL) -> String? {
        for plist in ["Resources/Info.plist", "Versions/A/Resources/Info.plist", "Info.plist"] {
            if let dict = NSDictionary(contentsOf: framework.appendingPathComponent(plist)) as? [String: Any] {
                return dict["CFBundleShortVersionString"] as? String ?? dict["CFBundleVersion"] as? String
            }
        }
        return nil
    }

    /// Combinations measured not to work. D3DMetal 4.0's Unix-side libraries do not load in Wine 7.7
    /// (tested 2026-10-31: dxgi.dll fails, the game falls back to OpenGL).
    static func incompatibility(base: WineRuntime, redist: D3DMetalRedistributable) -> String? {
        func major(_ s: String?) -> Int? { s.flatMap { Int($0.prefix { $0.isNumber }) } }
        guard let d3d = major(redist.version), let wine = major(base.version) else { return nil }
        if d3d >= 4 && wine < 8 {
            return "D3DMetal \(redist.version ?? "") needs a newer Wine than \(base.version ?? "") (it fails to load in Wine 7.7). Use the D3DMetal bundled with this Toolkit build instead."
        }
        return nil
    }

    /// Clones `base` into `runtimesDirectory/<slug>/wine` and merges the redistributable into its `lib` folder.
    @discardableResult
    public static func makeManagedRuntime(name: String, base: WineRuntime, redist: D3DMetalRedistributable,
                                          runtimesDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        if let reason = incompatibility(base: base, redist: redist) { throw AlloyError.runtimeUnavailable(reason) }
        let folder = runtimesDirectory.appendingPathComponent("\(PrefixManager.slug(name))-\(UUID().uuidString.prefix(8))")
        let wineRoot = folder.appendingPathComponent("wine")
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            // FileManager uses APFS clonefile for copies on the same volume: fast and space-efficient.
            try fileManager.copyItem(at: base.root.resolvingSymlinksInPath(), to: wineRoot)
            try merge(from: redist.lib, into: wineRoot.appendingPathComponent("lib"), fileManager: fileManager)
            try MetalFXDLSS.provideD3DMetalShim(wineRoot: wineRoot, fileManager: fileManager)
            let manifest = ManagedRuntimeManifest(name: name, baseRuntimePath: base.wineBinary.path,
                                                  baseRuntimeVersion: base.version, d3dMetalVersion: redist.version,
                                                  d3dMetalSource: redist.lib.path, createdAt: Date())
            try JSONFileStore<ManagedRuntimeManifest>(fileURL: folder.appendingPathComponent(manifestName)).save(manifest)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw AlloyError.persistenceFailed("Could not build the D3DMetal runtime: \(error.localizedDescription)")
        }
        return folder
    }

    /// Recursively copies `source` over `destination`, replacing files. Bundles (`.framework`) are replaced whole.
    static func merge(from source: URL, into destination: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true && values.isSymbolicLink != true && item.pathExtension != "framework" {
                try merge(from: item, into: target, fileManager: fileManager)
            } else {
                if fileManager.fileExists(atPath: target.path) || (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }

    /// A runtime D3DMetal can be layered onto: an unmanaged install, or an Alloy-imported plain Wine build.
    /// Never another managed runtime that already carries a translation layer.
    public static func isLayerableBase(_ runtime: WineRuntime) -> Bool {
        guard let manifest = manifest(for: runtime) else { return true }
        return manifest.translationLayer == TranslationLayer.none.rawValue
    }

    /// True for an Alloy-imported plain build of CodeWeavers' sources, which has the winemac hooks D3DMetal 4 needs.
    public static func isPlainManagedBuild(_ runtime: WineRuntime) -> Bool {
        manifest(for: runtime)?.translationLayer == TranslationLayer.none.rawValue
    }

    public static func manifest(for runtime: WineRuntime) -> ManagedRuntimeManifest? {
        let folder = runtime.root.deletingLastPathComponent()
        let url = folder.appendingPathComponent(manifestName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return JSONFileStore<ManagedRuntimeManifest?>(fileURL: url).load(default: nil)
    }
}
