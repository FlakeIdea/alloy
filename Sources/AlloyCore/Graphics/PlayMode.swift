import Foundation

/// The one graphics choice the simple game page offers. Each mode is a fixed set of the detailed settings, so the
/// detailed (advanced) editor still shows exactly what a mode did; any other combination reads as "Custom".
public enum PlayMode: String, CaseIterable, Identifiable, Sendable {
    /// 60 FPS: half the GPU work of a 120 Hz display, for longer play on battery and a cooler Mac. Offered only on
    /// displays faster than 60 Hz; on a 60 Hz display it would be the same as Balanced.
    case batterySaver
    /// As smooth as the display allows. The default.
    case balanced
    /// MetalFX upscales every frame to the Retina pixel size (DXMT only); a little slower. It turns off MetalFX scaling
    /// (DLSS → MetalFX), so a game's frames are never upscaled twice.
    case sharp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .batterySaver: return "Battery Saver"
        case .balanced: return "Balanced"
        case .sharp: return "Sharp"
        }
    }

    public var symbol: String {
        switch self {
        case .batterySaver: return "battery.75percent"
        case .balanced: return "gauge.with.dots.needle.50percent"
        case .sharp: return "eye"
        }
    }

    public func summary(displayRefreshRate: Int) -> String {
        switch self {
        case .batterySaver: return "Limits the game to 60 FPS. Longer battery life and a cooler Mac."
        case .balanced: return "As smooth as your display allows (\(displayRefreshRate) FPS). Recommended."
        case .sharp: return "Apple MetalFX sharpens the picture to your Retina display's full resolution. Costs a few FPS."
        }
    }

    /// The mode these settings match, or nil when they were changed by hand.
    public static func current(of g: GraphicsConfiguration) -> PlayMode? {
        switch (g.frameRateCap, g.metalFXSpatialFactor) {
        case (.fixed(60), nil): return .batterySaver
        case (.displayMaximum, nil): return .balanced
        case (.displayMaximum, 2): return .sharp
        default: return nil
        }
    }

    /// Battery Saver and Balanced turn MetalFX scaling (DLSS → MetalFX) on; it can then be turned off on its own.
    public func apply(to g: inout GraphicsConfiguration) {
        switch self {
        case .batterySaver: g.frameRateCap = .fixed(60); g.metalFXSpatialFactor = nil; g.dlss = true
        case .balanced: g.frameRateCap = .displayMaximum; g.metalFXSpatialFactor = nil; g.dlss = true
        case .sharp: g.frameRateCap = .displayMaximum; g.metalFXSpatialFactor = 2; g.dlss = false
        }
    }

    /// Modes that do something on this graphics path and display: a frame limit needs DXMT, DXVK or D3DMetal and a
    /// display faster than 60 Hz, and MetalFX upscaling needs DXMT.
    public static func available(for backend: GraphicsBackendKind, capabilities: BackendCapabilities,
                                 displayRefreshRate: Int) -> [PlayMode] {
        var modes: [PlayMode] = []
        if FrameRateCap.isSupported(by: backend), displayRefreshRate > 60 { modes.append(.batterySaver) }
        modes.append(.balanced)
        if capabilities.metalFXSpatialUpscaling.contains(backend) { modes.append(.sharp) }
        return modes
    }
}

extension GraphicsBackendKind {
    /// Compatibility mode: Wine's own Direct3D over OpenGL. Slower, but it runs games the Metal paths cannot draw.
    public var isCompatibilityMode: Bool { self == .wined3dOpenGL }
}
