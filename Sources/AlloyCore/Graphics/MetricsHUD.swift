import Foundation
import notify

/// Apple's Metal performance HUD (FPS, frame time, memory), shown or hidden while a game runs.
///
/// The HUD exists only in processes started with `MTL_HUD_ENABLED=1`, and always appears as it loads. It hides and
/// shows when the system notification below is posted, the same thing its own ⇧F9 menu item does. The notification
/// reaches every process with the HUD loaded, so a game in another app with its HUD on toggles too.
public enum MetricsHUD {
    public static let toggleNotification = "com.apple.metal.hud.notify.ToggleEnabled"

    public static func toggle() { notify_post(toggleNotification) }

    /// The process the HUD has just loaded into. libMTLHud logs as it loads, through NSLog, so the line carries the
    /// process name and id: `game.exe[1931:26964] [libMTLHud] Metric com.apple.hud-stat.fps already exist`.
    public static func loadingProcess(in line: String) -> Int32? {
        guard let hud = line.range(of: "] [libMTLHud]") else { return nil }
        let head = line[..<hud.lowerBound]
        guard let open = head.lastIndex(of: "[") else { return nil }
        return head[head.index(after: open)...].split(separator: ":").first.flatMap { Int32($0) }
    }

    /// Hides the HUD in each of a game's processes as it appears, for games that start with metrics hidden.
    public final class Hider: @unchecked Sendable {
        private let lock = NSLock()
        private var hidden: Set<Int32> = []
        private let post: @Sendable () -> Void

        public init(post: @escaping @Sendable () -> Void = MetricsHUD.toggle) { self.post = post }

        public func observe(_ line: LogLine) {
            guard let pid = MetricsHUD.loadingProcess(in: line.text) else { return }
            guard lock.withLock({ hidden.insert(pid).inserted }) else { return }
            // Posted right after the HUD's first line it already takes effect; a short pause leaves room to spare.
            let post = self.post
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { post() }
        }
    }
}
