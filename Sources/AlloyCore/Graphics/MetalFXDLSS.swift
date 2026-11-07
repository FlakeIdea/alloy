import Foundation

/// NVIDIA DLSS libraries a game ships. Found by file name; nothing is loaded or run.
public struct DLSSUsage: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `nvngx_dlss.dll`: DLSS Super Resolution (upscaling).
    public static let upscaling = DLSSUsage(rawValue: 1 << 0)
    /// `nvngx_dlssg.dll`: DLSS Frame Generation.
    public static let frameGeneration = DLSSUsage(rawValue: 1 << 1)
    /// AMD FidelityFX (FSR 3 and later) libraries, which can include FSR Frame Generation. Unlike DLSS it runs in the
    /// game's own shaders, so it needs nothing from the Mac's graphics layer.
    public static let amdFidelityFX = DLSSUsage(rawValue: 1 << 2)

    static func kind(of fileName: String) -> DLSSUsage? {
        switch fileName {
        case "nvngx_dlss.dll": return .upscaling
        case "nvngx_dlssg.dll": return .frameGeneration
        default:
            return fileName.hasSuffix(".dll") && ["amd_fidelityfx_", "ffx_fsr3", "ffx_frameinterpolation"].contains(where: fileName.hasPrefix)
                ? .amdFidelityFX : nil
        }
    }

    /// Unreal Engine keeps these under `Engine/Plugins/.../Binaries/ThirdParty/Win64`, so the whole folder is walked.
    public static func detect(in folder: URL, fileManager: FileManager = .default, maxEntries: Int = 100_000) -> DLSSUsage {
        guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: DLSSUsage = []
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > maxEntries { break }
            guard let kind = kind(of: url.lastPathComponent.lowercased()) else { continue }
            found.insert(kind)
            if found == [.upscaling, .frameGeneration, .amdFidelityFX] { break }
        }
        return found
    }
}

/// Lets games that support NVIDIA DLSS use Apple MetalFX instead, the way CrossOver's game bottles do:
/// the graphics layer reports an NVIDIA GPU, the game finds an NGX "core" (`nvngx.dll`) through the registry,
/// and that shim runs MetalFX upscaling (and, in D3DMetal 4, MetalFX frame interpolation for DLSS Frame Generation).
public enum MetalFXDLSS {
    /// Where games look for the NGX core. The value is the folder that holds `nvngx.dll`.
    public static let registryKey = #"HKLM\Software\NVIDIA Corporation\Global\NGXCore"#
    public static let registryPath = #"C:\windows\system32"#

    /// Environment variable that turns the translation on in each layer.
    public static func environmentKey(for backend: GraphicsBackendKind) -> String? {
        switch backend {
        case .d3dMetal: return "D3DM_ENABLE_METALFX"
        case .dxmt: return "DXMT_ENABLE_NVEXT"
        default: return nil
        }
    }

    static func windowsLib(_ runtime: WineRuntime) -> URL { runtime.root.appendingPathComponent("lib/wine/x86_64-windows") }
    static func unixLib(_ runtime: WineRuntime) -> URL { runtime.root.appendingPathComponent("lib/wine/x86_64-unix") }

    /// Apple ships D3DMetal's shim as `nvngx-on-metalfx`; Wine looks it up as `nvngx`. Apple's Read Me says to
    /// rename both halves, so they are copied under the expected name (the originals stay).
    public static func provideD3DMetalShim(wineRoot: URL, fileManager: FileManager = .default) throws {
        let lib = wineRoot.appendingPathComponent("lib/wine")
        for (dir, ext) in [("x86_64-windows", "dll"), ("x86_64-unix", "so")] {
            let source = lib.appendingPathComponent("\(dir)/nvngx-on-metalfx.\(ext)")
            let target = lib.appendingPathComponent("\(dir)/nvngx.\(ext)")
            guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.copyItem(at: source, to: target)
        }
    }

    /// Copies the runtime's `nvngx.dll` and `nvapi64.dll` into the environment's system32, keeping whatever was
    /// there in `alloy-backup/nvngx`. Only Alloy-managed environments and runtimes are changed.
    public static func installShims(from runtime: WineRuntime, into prefix: WinePrefix, runtimeIsManaged: Bool,
                                    fileManager: FileManager = .default) throws {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        guard prefix.isInitialized() else { throw AlloyError.prefixNotInitialized(name: prefix.name) }
        let win = windowsLib(runtime)
        if !fileManager.fileExists(atPath: win.appendingPathComponent("nvngx.dll").path) {
            guard runtimeIsManaged else {
                throw AlloyError.graphicsBackendUnavailable(backend: "DLSS → MetalFX",
                    reason: "\(runtime.displayName) has no nvngx.dll, and Alloy only changes runtimes it manages.")
            }
            try provideD3DMetalShim(wineRoot: runtime.root, fileManager: fileManager)
        }
        let backup = prefix.path.appendingPathComponent("alloy-backup/nvngx")
        do {
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            for name in ["nvngx.dll", "nvapi64.dll"] {
                let source = win.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path) else {
                    throw AlloyError.graphicsBackendUnavailable(backend: "DLSS → MetalFX", reason: "\(runtime.displayName) has no \(name).")
                }
                let target = prefix.system32.appendingPathComponent(name)
                if fileManager.contentsEqual(atPath: source.path, andPath: target.path) { continue }
                if fileManager.fileExists(atPath: target.path) {
                    let saved = backup.appendingPathComponent(name)
                    if !fileManager.fileExists(atPath: saved.path) { try fileManager.copyItem(at: target, to: saved) }
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: source, to: target)
            }
        } catch let error as AlloyError {
            throw error
        } catch {
            throw AlloyError.persistenceFailed("Could not install the DLSS → MetalFX files: \(error.localizedDescription)")
        }
    }

    /// True when the environment's registry already tells games where the NGX core is.
    public static func hasRegistryPath(_ prefix: WinePrefix) -> Bool {
        guard let text = try? String(contentsOf: prefix.path.appendingPathComponent("system.reg"), encoding: .utf8) else { return false }
        var inKey = false
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                inKey = line.lowercased().hasPrefix(#"[software\\nvidia corporation\\global\\ngxcore]"#)
            } else if inKey && line.lowercased().hasPrefix(#""fullpath"="#) {
                return true
            }
        }
        return false
    }

    /// Wine's own `reg.exe`, run with the game's environment (same prefix and sync mode) so it shares the
    /// game's wineserver. No program from the game is run.
    public static func registryCommand(like launch: LaunchCommand) -> LaunchCommand {
        LaunchCommand(executable: launch.executable,
                      arguments: ["reg", "add", registryKey, "/v", "FullPath", "/t", "REG_SZ", "/d", registryPath, "/f"],
                      environment: launch.environment)
    }
}

/// Whether a game can show generated frames between the ones it renders, and why not. Frame generation needs the
/// game's own depth and motion vectors; without them in-between frames smear moving edges and the HUD, so Alloy
/// offers it only where the game provides that data.
public enum FrameGeneration: Equatable, Sendable {
    /// DLSS Frame Generation runs as MetalFX frame generation on this game's current path.
    case available
    /// The game ships DLSS Frame Generation; an installed D3DMetal 4 runtime can run it (the game page offers the switch).
    case switchAvailable
    /// The game ships DLSS Frame Generation, but no installed runtime has D3DMetal 4.
    case needsD3DMetal4
    /// The game ships AMD FidelityFX, which may include FSR Frame Generation, run by the game itself.
    case gameRuns
    /// The game provides no motion data for it.
    case unsupported

    public static func status(traits: GameTraits, graphics: GraphicsConfiguration, capabilities: BackendCapabilities?,
                              d3dMetal4Installed: Bool) -> FrameGeneration {
        if traits.dlss.contains(.frameGeneration) {
            if capabilities?.metalFXFrameGeneration.contains(graphics.backend) == true && !graphics.forceDX11 && graphics.dlss {
                return .available
            }
            return d3dMetal4Installed ? .switchAvailable : .needsD3DMetal4
        }
        return traits.dlss.contains(.amdFidelityFX) ? .gameRuns : .unsupported
    }

    public var summary: String {
        switch self {
        case .available:
            return "On: turn on DLSS Frame Generation in the game's graphics settings. Apple MetalFX makes the extra frames from the game's own motion data. Best when the game already runs at 40 FPS or more; it adds a little input delay."
        case .switchAvailable:
            return "This game ships DLSS Frame Generation, which runs on its DirectX 12 path with D3DMetal 4. Switching makes a new environment; the current one stays on disk with its saves."
        case .needsD3DMetal4:
            return "This game ships DLSS Frame Generation. To use it, add D3DMetal 4 from Apple's Game Porting Toolkit in Setup."
        case .gameRuns:
            return "This game includes AMD FidelityFX. If its settings offer FSR Frame Generation, you can turn it on there: the game makes the extra frames itself. Not yet tested in Alloy."
        case .unsupported:
            return "Not available: this game doesn't provide the motion data frame generation needs. Alloy doesn't guess frames without it, because that smears moving edges and the HUD and adds input delay."
        }
    }
}
