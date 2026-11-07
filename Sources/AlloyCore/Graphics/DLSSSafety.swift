import Foundation

/// When DLSS → MetalFX should be switched off by itself. The translation makes the graphics layer report an NVIDIA
/// GPU, and a game can take NVIDIA-only paths it then can't finish, so a crash in the first minutes is treated as a
/// sign the translation doesn't suit this game.
public enum DLSSSafety {
    /// How soon after starting a crash counts against the translation.
    public static let window: TimeInterval = 180

    public static func shouldTurnOff(after state: LaunchState, ranFor seconds: TimeInterval) -> Bool {
        guard seconds < window else { return false }
        switch state {
        case .exited(let code): return code != 0
        // Crashes (illegal instruction, abort, bus error, segmentation fault), not a person or Alloy ending the game.
        case .terminatedBySignal(let signal): return [4, 6, 10, 11].contains(signal)
        case .failed: return true
        default: return false
        }
    }
}
