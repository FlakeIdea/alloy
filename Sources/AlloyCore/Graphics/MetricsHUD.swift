import Foundation
import notify

/// Apple's Metal performance HUD (FPS, frame time, memory), shown or hidden while a game runs.
///
/// The HUD exists only in processes started with `MTL_HUD_ENABLED=1`. With `MTL_HUD_HIDDEN=1` as well it loads hidden,
/// so a game that starts with metrics hidden has them hidden in every one of its processes (a launcher and the game,
/// say). The HUD hides and shows when the system notification below is posted, the same thing its own menu item does.
/// The notification reaches every process with the HUD loaded, and they all started hidden, so they stay in step: one
/// press shows the metrics everywhere, the next hides them. A game in another app with its HUD on toggles too.
public enum MetricsHUD {
    public static let toggleNotification = "com.apple.metal.hud.notify.ToggleEnabled"

    public static func toggle() { notify_post(toggleNotification) }

    /// Environment for a game's processes: the HUD loaded, and hidden until the shortcut shows it unless `shown`.
    public static func environment(shown: Bool) -> [String: String] {
        shown ? ["MTL_HUD_ENABLED": "1"] : ["MTL_HUD_ENABLED": "1", "MTL_HUD_HIDDEN": "1"]
    }
}
