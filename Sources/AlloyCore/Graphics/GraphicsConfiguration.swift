import Foundation

/// DirectX translation paths Alloy knows how to configure. They are not interchangeable:
/// each has its own requirements, which `GraphicsCapabilityMatrix` checks.
public enum GraphicsBackendKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case wined3dOpenGL
    case wined3dVulkan
    case vkd3d
    case dxvk
    case d3dMetal
    case dxmt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wined3dOpenGL: return "WineD3D (OpenGL)"
        case .wined3dVulkan: return "WineD3D (Vulkan via MoltenVK)"
        case .vkd3d: return "Wine vkd3d (D3D12 via MoltenVK)"
        case .dxvk: return "DXVK-macOS (D3D10/11 via MoltenVK)"
        case .d3dMetal: return "D3DMetal (Apple GPTK)"
        case .dxmt: return "DXMT (D3D10/11 → Metal)"
        }
    }

    public var directXVersions: String {
        switch self {
        case .wined3dOpenGL, .wined3dVulkan: return "DirectX 1–11"
        case .vkd3d: return "DirectX 12"
        case .dxvk, .dxmt: return "DirectX 10–11"
        case .d3dMetal: return "DirectX 11–12"
        }
    }

    public var licence: String {
        switch self {
        case .wined3dOpenGL, .wined3dVulkan, .vkd3d: return "LGPL-2.1+ (Wine)"
        case .dxvk: return "zlib (DXVK) + Apache-2.0 (MoltenVK)"
        case .d3dMetal: return "Proprietary Apple licence — user-supplied, never bundled"
        case .dxmt: return "zlib (DXMT, 3Shain/dxmt)"
        }
    }
}

/// Sync primitives some Wine builds support. Upstream Wine has none of these as opt-in flags.
public enum SyncMode: String, Codable, CaseIterable, Sendable {
    /// MSync when the runtime has it, otherwise Wine's own synchronisation.
    case `default`
    /// Wine's own synchronisation, even where a faster mode exists.
    case off
    case esync
    case msync

    public var displayName: String {
        switch self {
        case .default: return "Automatic (MSync when available)"
        case .off: return "Off (Wine default)"
        case .esync: return "ESync"
        case .msync: return "MSync"
        }
    }
}

public enum QualityPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case highQuality
    case balanced
    case highFPS
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .highQuality: return "High Quality"
        case .balanced: return "Quality + Performance"
        case .highFPS: return "High FPS"
        case .custom: return "Custom"
        }
    }

    public var summary: String {
        switch self {
        case .highQuality: return "Prioritise visual fidelity. Accept lower frame rates as long as gameplay stays playable."
        case .balanced: return "Keep high graphics and hit the frame-rate target with consistent frame pacing. Default."
        case .highFPS: return "Prioritise responsiveness and 1% lows. Lowers expensive effects first, textures last."
        case .custom: return "Configure individual settings yourself."
        }
    }
}

/// Highest frame rate a game may render at. Games that render faster than the display can show present their frames
/// unevenly, which looks like stutter on ProMotion displays even at well over 120 FPS.
public enum FrameRateCap: Codable, Hashable, Sendable {
    /// The display's refresh rate (120 on ProMotion MacBook Pros), read when the game starts.
    case displayMaximum
    case off
    case fixed(Int)

    /// Frames per second to limit to, or nil for no limit.
    public func limit(displayRefreshRate: Int) -> Int? {
        switch self {
        case .displayMaximum: return displayRefreshRate > 0 ? displayRefreshRate : nil
        case .off: return nil
        case .fixed(let fps): return fps > 0 ? fps : nil
        }
    }

    /// Graphics paths with a frame limiter: DXMT, DXVK and D3DMetal.
    public static func isSupported(by backend: GraphicsBackendKind) -> Bool {
        [.dxmt, .dxvk, .d3dMetal].contains(backend)
    }
}

/// MetalFX spatial upscaling for games without DLSS: DXMT upscales each finished frame by a factor before the display
/// shows it. The game still renders at its own resolution, so the frame rate only rises when the in-game resolution is
/// lowered; at the same resolution the picture is sharper on a Retina display.
public enum MetalFXSpatialUpscaling {
    /// Factors offered in the app. A game that renders at the window's size reaches the Retina pixel size at 2×.
    public static let factors: [Double] = [1.5, 2, 3]
    /// DXMT treats factors below 1 as 1. MetalFX on Apple silicon creates spatial scalers up to 4×.
    public static let validFactors: ClosedRange<Double> = 1...4

    /// The factor as DXMT's config parser reads it: digits with an optional decimal point.
    public static func configValue(_ factor: Double) -> String { String(format: "%g", factor) }

    public static func displayName(_ factor: Double) -> String { configValue(factor) + "×" }
}

/// Per-game graphics/launch configuration. Only options the selected runtime supports are applied.
public struct GraphicsConfiguration: Codable, Hashable, Sendable {
    public var backend: GraphicsBackendKind
    public var preset: QualityPreset
    public var targetFPS: Int
    /// Show the Metal performance HUD from the start. Without it the HUD starts hidden (see `MetricsHUD`).
    public var metalHUD: Bool
    public var syncMode: SyncMode
    public var advertiseAVX: Bool
    /// Frame limit for DXMT, DXVK and D3DMetal.
    public var frameRateCap: FrameRateCap
    /// DXVK only: where the DXVK state cache is written.
    public var shaderCachePath: String?
    /// Prefer the Unreal Engine `-dx11` path for games whose DX12 path fails.
    public var forceDX11: Bool
    /// DLSS → MetalFX: games that support DLSS (and DLSS Frame Generation) use Apple MetalFX instead.
    public var dlss: Bool
    /// MetalFX spatial upscaling factor (DXMT), or nil for off.
    public var metalFXSpatialFactor: Double?
    /// Queue one frame ahead of the GPU instead of three (DXMT, see `LowInputDelay`). On unless turned off.
    public var lowInputDelay: Bool

    public init(backend: GraphicsBackendKind = .wined3dOpenGL,
                preset: QualityPreset = .balanced,
                targetFPS: Int = 60,
                metalHUD: Bool = false,
                syncMode: SyncMode = .default,
                advertiseAVX: Bool = true,
                frameRateCap: FrameRateCap = .displayMaximum,
                shaderCachePath: String? = nil,
                forceDX11: Bool = false,
                dlss: Bool = false,
                metalFXSpatialFactor: Double? = nil,
                lowInputDelay: Bool = true) {
        self.backend = backend
        self.preset = preset
        self.targetFPS = targetFPS
        self.metalHUD = metalHUD
        self.syncMode = syncMode
        self.advertiseAVX = advertiseAVX
        self.frameRateCap = frameRateCap
        self.shaderCachePath = shaderCachePath
        self.forceDX11 = forceDX11
        self.dlss = dlss
        self.metalFXSpatialFactor = metalFXSpatialFactor
        self.lowInputDelay = lowInputDelay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GraphicsConfiguration()
        backend = try c.decodeIfPresent(GraphicsBackendKind.self, forKey: .backend) ?? d.backend
        preset = try c.decodeIfPresent(QualityPreset.self, forKey: .preset) ?? d.preset
        targetFPS = try c.decodeIfPresent(Int.self, forKey: .targetFPS) ?? d.targetFPS
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? d.metalHUD
        syncMode = try c.decodeIfPresent(SyncMode.self, forKey: .syncMode) ?? d.syncMode
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? d.advertiseAVX
        // Older settings had only a DXVK limit, 0 meaning off; games without one get the display maximum.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if let cap = try c.decodeIfPresent(FrameRateCap.self, forKey: .frameRateCap) {
            frameRateCap = cap
        } else if let dxvk = try legacy.decodeIfPresent(Int.self, forKey: .dxvkFrameRateLimit), dxvk > 0 {
            frameRateCap = .fixed(dxvk)
        } else {
            frameRateCap = d.frameRateCap
        }
        shaderCachePath = try c.decodeIfPresent(String.self, forKey: .shaderCachePath)
        forceDX11 = try c.decodeIfPresent(Bool.self, forKey: .forceDX11) ?? false
        dlss = try c.decodeIfPresent(Bool.self, forKey: .dlss) ?? false
        metalFXSpatialFactor = try c.decodeIfPresent(Double.self, forKey: .metalFXSpatialFactor)
        lowInputDelay = try c.decodeIfPresent(Bool.self, forKey: .lowInputDelay) ?? d.lowInputDelay
    }

    private enum LegacyKeys: String, CodingKey { case dxvkFrameRateLimit }

    /// Frame-time budget for the target, e.g. 16.67 ms at 60 FPS.
    public var frameBudgetMilliseconds: Double { 1000.0 / Double(max(targetFPS, 1)) }
}

public enum CapabilityStatus: Equatable, Sendable {
    case available
    case experimental(String)
    case unavailable(String)

    public var isUsable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

/// What a given runtime can actually do. The UI only shows options whose status is usable.
public struct BackendCapabilities: Equatable, Sendable {
    public var graphics: [GraphicsBackendKind: CapabilityStatus]
    public var syncModes: [SyncMode]
    public var supportsMetalHUD: Bool
    public var supportsAVXAdvertisement: Bool
    public var notes: [String]
    /// Graphics paths on which DLSS is translated to MetalFX upscaling.
    public var metalFXUpscaling: Set<GraphicsBackendKind> = []
    /// Graphics paths on which DLSS Frame Generation is translated to MetalFX frame interpolation.
    public var metalFXFrameGeneration: Set<GraphicsBackendKind> = []
    /// Graphics paths that can upscale any game's frames with MetalFX (DXMT's MetalFX swapchain).
    public var metalFXSpatialUpscaling: Set<GraphicsBackendKind> = []
    /// Graphics paths that can limit the game to one queued frame (`LowInputDelay`).
    public var lowInputDelay: Set<GraphicsBackendKind> = []
    /// The engine takes a per-game scroll speed (`ScrollSpeed`).
    public var scrollSpeed = false
    /// 32-bit games can be given 4 GB of address space (`LargeAddressSpace`).
    public var largeAddressSpace = false

    public func status(of backend: GraphicsBackendKind) -> CapabilityStatus {
        graphics[backend] ?? .unavailable("Not supported by this runtime.")
    }
}
