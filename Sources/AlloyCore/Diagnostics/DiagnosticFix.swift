import Foundation

/// A one-click fix offered with a problem. A finding lists candidates in the order worth trying; the game page shows
/// the first one that would change something for this game, and the rest under More Fixes.
public enum DiagnosticFix: String, Hashable, CaseIterable, Sendable {
    case installVisualCpp, installDotNet, addD3DMetal, forceDX11, advertiseAVX, turnOffDLSS, turnOffMetalFXUpscaling,
         syncOff, compatibilityMode, stopEnvironment, openSetup, addDLL

    public var title: String {
        switch self {
        case .installVisualCpp: return "Install Visual C++"
        case .installDotNet: return "Install .NET"
        case .addD3DMetal: return "Add D3DMetal…"
        case .forceDX11: return "Use DirectX 11"
        case .advertiseAVX: return "Turn On AVX"
        case .turnOffDLSS: return "Turn Off DLSS → MetalFX"
        case .turnOffMetalFXUpscaling: return "Turn Off MetalFX Upscaling"
        case .syncOff: return "Turn Off MSync"
        case .compatibilityMode: return "Try Compatibility Mode"
        case .stopEnvironment: return "Stop Everything in This Environment"
        case .openSetup: return "Open Setup"
        case .addDLL: return "Add DLL…"
        }
    }

    /// What the fix changed, said after it is applied.
    public var done: String {
        switch self {
        case .forceDX11: return "The game now starts with -dx11."
        case .advertiseAVX: return "Rosetta now tells the game the CPU has AVX."
        case .turnOffDLSS: return "DLSS → MetalFX is off."
        case .turnOffMetalFXUpscaling: return "MetalFX upscaling is off."
        case .syncOff: return "MSync is off; Wine's own synchronisation is used."
        case .compatibilityMode: return "Compatibility mode (WineD3D) is on. It's slower; turn it off on the game page once the game works."
        case .stopEnvironment: return "Every program in this environment was stopped."
        default: return ""
        }
    }

    /// Changes the game's own settings. Fixes the app carries out (installs, stopping, Setup) return false.
    @discardableResult
    public func apply(to game: inout Game) -> Bool {
        switch self {
        case .forceDX11: game.graphics.forceDX11 = true
        case .advertiseAVX: game.graphics.advertiseAVX = true
        case .turnOffDLSS: game.graphics.dlss = false
        case .turnOffMetalFXUpscaling: game.graphics.metalFXSpatialFactor = nil
        case .syncOff: game.graphics.syncMode = .off
        case .compatibilityMode: game.graphics.backend = .wined3dOpenGL; game.graphics.metalFXSpatialFactor = nil
        default: return false
        }
        return true
    }

    /// Whether the fix would change anything for this game as it is set up now.
    public func applies(to game: Game, capabilities: BackendCapabilities?, traits: GameTraits?,
                        visualCppInstalled: Bool, dotNetInstalled: Bool, hasD3DMetal: Bool) -> Bool {
        let g = game.graphics
        switch self {
        case .installVisualCpp: return !visualCppInstalled
        case .installDotNet: return !dotNetInstalled
        case .addD3DMetal: return !hasD3DMetal
        case .forceDX11: return !g.forceDX11 && g.backend == .dxmt && (traits?.isUnreal ?? false)
        case .advertiseAVX: return !g.advertiseAVX && capabilities?.supportsAVXAdvertisement == true
        case .turnOffDLSS: return g.dlss
        case .turnOffMetalFXUpscaling: return g.metalFXSpatialFactor != nil
        case .syncOff: return g.syncMode != .off
        case .compatibilityMode: return !g.backend.isCompatibilityMode
        case .stopEnvironment, .openSetup, .addDLL: return true
        }
    }
}
