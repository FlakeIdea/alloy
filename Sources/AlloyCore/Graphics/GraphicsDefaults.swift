import Foundation

/// Which Direct3D DLLs an executable names. Found by reading the file's bytes; nothing is loaded or run.
public struct DirectXUsage: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let d3d9 = DirectXUsage(rawValue: 1 << 0)
    public static let d3d10 = DirectXUsage(rawValue: 1 << 1)
    public static let d3d11 = DirectXUsage(rawValue: 1 << 2)
    public static let d3d12 = DirectXUsage(rawValue: 1 << 3)

    static let needles: [(DirectXUsage, [UInt8])] = [
        (.d3d9, Array("d3d9.dll".utf8)), (.d3d10, Array("d3d10".utf8)),
        (.d3d11, Array("d3d11.dll".utf8)), (.d3d12, Array("d3d12.dll".utf8)),
    ]

    /// Case-insensitive scan of the file's bytes (`BinaryScan`), stopping once every kind is found.
    public static func detect(in url: URL, maxBytes: Int = 512 * 1024 * 1024) -> DirectXUsage {
        let hits = BinaryScan.indexes(of: needles.map(\.1), in: url, maxBytes: maxBytes)
        return hits.reduce(into: DirectXUsage()) { $0.insert(needles[$1].0) }
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard let first = needle.first, haystack.count >= needle.count else { return false }
        var i = 0
        while let j = haystack[i...].firstIndex(of: first), j + needle.count <= haystack.count {
            if haystack[j..<(j + needle.count)].elementsEqual(needle) { return true }
            i = j + 1
        }
        return false
    }

    /// DLLs that name Direct3D without being the game's renderer (shader compilers, runtimes, UI toolkits).
    static let ignoredDLLPrefixes = ["d3d", "dxgi", "dxcompiler", "dxil", "msvc", "vcruntime", "ucrtbase", "api-ms-",
                                     "qt5", "qt6", "libegl", "libglesv2", "openal", "steam_api", "nvapi", "nvngx"]

    /// Engines often render from a DLL next to the executable (e.g. Unigine_x64.dll), and Unreal Engine games
    /// ship a launcher stub whose real renderer lives in `*-Shipping.exe` under `Binaries/Win64`.
    public static func detect(game: Game, fileManager: FileManager = .default) -> DirectXUsage {
        var usage = detect(in: game.executableURL)
        let siblings = (try? fileManager.contentsOfDirectory(at: game.executableURL.deletingLastPathComponent(),
                                                             includingPropertiesForKeys: nil)) ?? []
        for dll in siblings.sorted(by: { $0.path < $1.path }).prefix(200) where dll.pathExtension.lowercased() == "dll" {
            let name = dll.lastPathComponent.lowercased()
            guard !ignoredDLLPrefixes.contains(where: name.hasPrefix) else { continue }
            usage.formUnion(detect(in: dll))
        }
        if !usage.isEmpty { return usage }
        guard let walker = fileManager.enumerator(at: game.folder, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var checked = 0
        for case let url as URL in walker where url.lastPathComponent.lowercased().hasSuffix("-shipping.exe") {
            let usage = detect(in: url)
            if !usage.isEmpty { return usage }
            checked += 1
            if checked >= 3 { break }
        }
        return []
    }
}

/// What the defaults need to know about a game. Reading it scans the game's binaries, so do it off the main thread.
public struct GameTraits: Equatable, Codable, Sendable {
    public var usage: DirectXUsage
    public var machine: PEMachine
    public var dlss: DLSSUsage
    /// Unreal Engine games pick DirectX 12 themselves when they have it, unless started with `-dx11`.
    public var isUnreal: Bool
    /// The game comes with Microsoft's Visual C++ installer, so it needs that runtime.
    public var shipsVisualCppInstaller: Bool
    /// The game's program imports Microsoft's Visual C++ DLLs and does not ship its own copies.
    public var importsVisualCpp: Bool
    /// A .NET program (it imports mscoree.dll), which needs Wine Mono.
    public var isDotNet: Bool

    public init(usage: DirectXUsage, machine: PEMachine, dlss: DLSSUsage = [], isUnreal: Bool = false,
                shipsVisualCppInstaller: Bool = false, importsVisualCpp: Bool = false, isDotNet: Bool = false) {
        self.usage = usage
        self.machine = machine
        self.dlss = dlss
        self.isUnreal = isUnreal
        self.shipsVisualCppInstaller = shipsVisualCppInstaller
        self.importsVisualCpp = importsVisualCpp
        self.isDotNet = isDotNet
    }

    public static func inspect(_ game: Game, fileManager: FileManager = .default) -> GameTraits {
        let exeDir = game.executableURL.deletingLastPathComponent()
        let unreal = [game.folder, exeDir].contains { fileManager.fileExists(atPath: $0.appendingPathComponent("Engine/Binaries").path) }
            || game.executableRelativePath.lowercased().contains("binaries/win64")
        // The program that really runs: Unreal Engine's launcher stub starts Binaries/Win64/*-Shipping.exe.
        var programs = [game.executableURL]
        if unreal, let walker = fileManager.enumerator(at: game.folder, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in walker where url.lastPathComponent.lowercased().hasSuffix("-shipping.exe") {
                programs.append(url); break
            }
        }
        let vcNames = ["vcruntime140.dll", "msvcp140.dll"]
        var importsVC = false, dotNet = false
        for program in programs {
            let found = BinaryScan.find(vcNames + ["mscoree.dll"], in: program)
            let local = vcNames.contains { fileManager.fileExists(atPath: program.deletingLastPathComponent().appendingPathComponent($0).path) }
            importsVC = importsVC || (!found.isDisjoint(with: vcNames) && !local)
            if program == game.executableURL { dotNet = found.contains("mscoree.dll") }
        }
        return GameTraits(usage: DirectXUsage.detect(game: game, fileManager: fileManager),
                          machine: (try? PEInspector.inspect(game.executableURL).machine) ?? .x64,
                          dlss: DLSSUsage.detect(in: game.folder, fileManager: fileManager), isUnreal: unreal,
                          shipsVisualCppInstaller: VisualCppRuntime.gameShipsInstaller(game, fileManager: fileManager),
                          importsVisualCpp: importsVC, isDotNet: dotNet)
    }
}

/// Picks the runtime and graphics path for a newly added game, based on measured results
/// (docs/COMPATIBILITY.md, 2026-10-31): DXMT was fastest for DX11; D3DMetal 4.0 is the only path here with DX12.
public enum GraphicsDefaults {
    public struct Choice: Equatable, Sendable {
        public var runtime: WineRuntime?
        public var backend: GraphicsBackendKind
        public var reason: String
        /// An Unreal Engine game that also has DirectX 12 must be told to use DX11 on DXMT.
        public var forceDX11 = false
        /// MetalFX scaling (DLSS → MetalFX): on wherever the chosen path has it, as in the Balanced and Battery Saver modes.
        public var dlss = false
        /// The game ships DLSS Frame Generation and the chosen path runs it as MetalFX frame generation.
        public var frameGeneration = false
    }

    /// A game that renders only with Direct3D 12. On this Mac only D3DMetal runs it, which people add themselves.
    public static func needsD3DMetal(_ usage: DirectXUsage) -> Bool {
        usage.contains(.d3d12) && usage.isDisjoint(with: [.d3d10, .d3d11])
    }

    public static func choose(traits: GameTraits, runtimes: [WineRuntime], preferredRuntime: WineRuntime?,
                              backend: WineBackend) -> Choice {
        // DLSS Frame Generation only works on the game's DirectX 12 path, which D3DMetal 4 runs with MetalFX frame
        // generation fed by the game's own depth and motion vectors.
        if traits.dlss.contains(.frameGeneration), traits.usage.contains(.d3d12), traits.machine != .x86,
           let r = runtimes.filter({ backend.capabilities(of: $0).metalFXFrameGeneration.contains(.d3dMetal) })
               .max(by: { ($0.version ?? "") < ($1.version ?? "") }) {
            return Choice(runtime: r, backend: .d3dMetal,
                          reason: "Ships DLSS Frame Generation: D3DMetal 4 runs it as MetalFX frame generation, using the game's own motion data.",
                          forceDX11: false, dlss: true, frameGeneration: true)
        }
        var choice = choose(usage: traits.usage, machine: traits.machine, runtimes: runtimes,
                            preferredRuntime: preferredRuntime, backend: backend)
        choice.forceDX11 = choice.backend == .dxmt && traits.isUnreal && traits.usage.contains(.d3d12)
        if let runtime = choice.runtime, backend.capabilities(of: runtime).metalFXUpscaling.contains(choice.backend) {
            choice.dlss = true
            if traits.dlss.contains(.upscaling) { choice.reason += " MetalFX scaling on: the game ships DLSS." }
        }
        return choice
    }

    public static func choose(usage: DirectXUsage, machine: PEMachine, runtimes: [WineRuntime],
                              preferredRuntime: WineRuntime?, backend: WineBackend) -> Choice {
        func usable(_ kind: GraphicsBackendKind) -> [WineRuntime] {
            runtimes.filter { backend.capabilities(of: $0).status(of: kind).isUsable }
        }
        func major(_ r: WineRuntime) -> Int { r.version.flatMap { Int($0.prefix { $0.isNumber }) } ?? 0 }
        let fallback = preferredRuntime ?? runtimes.first
        let is64 = machine != .x86

        let dx11 = !usage.isDisjoint(with: [.d3d10, .d3d11])
        if dx11, let r = usable(.dxmt).max(by: { major($0) < major($1) }) {
            return Choice(runtime: r, backend: .dxmt,
                          reason: "Uses Direct3D 10/11: DXMT measured fastest for DX11 on this Mac.")
        }
        // D3DMetal is 64-bit only; prefer the newest Wine underneath (D3DMetal 4 needs CrossOver-based Wine 11).
        if is64, dx11 || usage.contains(.d3d12), let r = usable(.d3dMetal).max(by: { major($0) < major($1) }) {
            return Choice(runtime: r, backend: .d3dMetal,
                          reason: usage.contains(.d3d12) && !dx11
                              ? "Uses Direct3D 12: D3DMetal is the only DX12 path here."
                              : "Uses Direct3D 10/11: no DXMT runtime installed, so D3DMetal.")
        }
        // No D3DMetal (an Intel Mac, or it wasn't added): Wine's vkd3d runs DirectX 12 on Metal through MoltenVK.
        // Less complete than D3DMetal, but OpenGL can't run DirectX 12 at all.
        if usage.contains(.d3d12), !dx11, let r = usable(.vkd3d).first(where: { $0 == fallback }) ?? usable(.vkd3d).first {
            return Choice(runtime: r, backend: .vkd3d,
                          reason: "Uses Direct3D 12 and no D3DMetal is available here: Wine's vkd3d on Metal (through MoltenVK). Experimental.")
        }
        return Choice(runtime: fallback, backend: .wined3dOpenGL,
                      reason: usage.isEmpty ? "No Direct3D 10–12 usage detected: WineD3D (OpenGL)."
                                            : "No DXMT or D3DMetal runtime suits this program: WineD3D (OpenGL).")
    }
}
