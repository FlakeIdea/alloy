import Foundation

/// How a controller macOS sees reaches Windows games through Alloy's engine. Wine reads controllers through macOS's
/// HID system (winebus' IOHID bus; the engine is built without SDL). Xbox controllers are also offered through
/// XInput, the interface most games since 2006 use; other controllers appear through DirectInput, which older games
/// and Steam Input read. Checked on the engine with a test program and no controller connected: the bus starts and
/// skips the keyboard and trackpad. Not yet tested with a real controller.
public enum GameControllers {
    public enum Reach: Equatable, Sendable {
        /// XInput and DirectInput: works in nearly every game with controller support.
        case xinput
        /// DirectInput only: works in games that read DirectInput, and in Steam games with Steam Input on.
        case directInput
    }

    /// From the controller's product category as macOS names it (`GCController.productCategory`).
    public static func reach(productCategory: String) -> Reach {
        productCategory.lowercased().contains("xbox") ? .xinput : .directInput
    }

    public static func summary(_ reach: Reach) -> String {
        switch reach {
        case .xinput: return "Games see it as an Xbox controller (XInput), which nearly every game with controller support reads."
        case .directInput: return "Games see it as a DirectInput controller. Older games read that; most newer ones only read Xbox controllers, so in Steam games turn on Steam Input for it (Steam ▸ Settings ▸ Controller)."
        }
    }

    public static let help = "Connect a controller by USB or Bluetooth (System Settings ▸ Bluetooth), then open the Wine test to see exactly what games in this environment get and to try its buttons and sticks."
}
