import Foundation

/// Conditions on the Mac that slow every game down, explained in plain words.
public enum MacConditions {
    /// What's slowing the Mac, or nil when nothing is.
    public static func notice(thermal: ProcessInfo.ThermalState, lowPowerMode: Bool) -> String? {
        switch (thermal, lowPowerMode) {
        case (.critical, _):
            return "Your Mac is very hot and is slowing itself down a lot to cool. Let it rest, or use Battery Saver mode, which halves the work at 120 Hz."
        case (.serious, _):
            return "Your Mac is hot and is slowing itself down to cool, so games run slower. Battery Saver mode keeps it cooler."
        case (_, true):
            return "Low Power Mode is on, so macOS slows the Mac to save battery and games run slower. Turn it off in System Settings › Battery for full speed."
        default:
            return nil
        }
    }

    public static var current: String? {
        notice(thermal: ProcessInfo.processInfo.thermalState, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
