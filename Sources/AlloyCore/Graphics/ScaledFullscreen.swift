import Foundation

/// Fullscreen at the game's own resolution without changing the Mac's display mode.
///
/// When a game goes fullscreen at a resolution other than the desktop's (BeamNG.drive picks 1512×945 on a display
/// set to 1800×1169), Wine's Mac driver captures the display and switches its mode. On Apple silicon laptops that
/// goes wrong: the picture ends up in a corner or cropped, and the pointer no longer lines up. Wine 10 and later
/// can instead keep the display as it is and scale: the game is told the screen has the size it asked for, its
/// window covers the real screen, the picture is scaled to fit with its shape kept (black bars where the shapes
/// differ), and pointer positions are scaled to match. Wine reads the switch from the `X11 Driver` key on every
/// platform, the Mac included. Older Wine builds (the Game Porting Toolkit's 7.7) ignore it.
///
/// Measured with Alloy's engine (Wine 11.0, DXMT 0.80) on a display set to 1800×1169, with a Direct3D 11 test in
/// exclusive fullscreen at 1512×945: the program was told the screen is 1512×945, its window covered 1800×1169,
/// the whole picture was on screen with bars of 22 points above and below, and a pointer at (639, 666) on the Mac
/// was reported at (537, 541). Not yet tested in a game.
public enum ScaledFullscreen {
    static let key = #"HKCU\Software\Wine\X11 Driver"#
    static let value = "EmulateModeset"

    /// True once the environment has it on (Wine keeps it in `user.reg`).
    public static func isOn(in prefix: WinePrefix) -> Bool {
        guard let text = try? String(contentsOf: prefix.path.appendingPathComponent("user.reg"), encoding: .utf8) else { return false }
        var inKey = false
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                inKey = line.lowercased().hasPrefix(#"[software\\wine\\x11 driver]"#)
            } else if inKey && line.lowercased().hasPrefix(#""emulatemodeset"="y""#) {
                return true
            }
        }
        return false
    }

    /// `wine reg add` in the game's environment, with the game's own environment variables.
    public static func turnOnCommand(like launch: LaunchCommand) -> LaunchCommand {
        LaunchCommand(executable: launch.executable,
                      arguments: ["reg", "add", key, "/v", value, "/t", "REG_SZ", "/d", "Y", "/f"],
                      environment: launch.environment)
    }
}
