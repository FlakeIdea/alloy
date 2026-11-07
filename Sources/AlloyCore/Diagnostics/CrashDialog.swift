import Foundation

/// When a Windows program crashes, Wine starts its debugger, which opens a technical "Program Error" window and keeps
/// the crashed game alive until someone closes it. With `ShowCrashDialog` off the debugger writes the crash and a
/// backtrace to the log instead and the game ends, so Alloy can say in plain words what happened.
public enum CrashDialog {
    static let key = #"HKCU\Software\Wine\WineDbg"#

    /// True once the environment has the window turned off (Wine keeps it in `user.reg`).
    public static func isOff(in prefix: WinePrefix) -> Bool {
        guard let text = try? String(contentsOf: prefix.path.appendingPathComponent("user.reg"), encoding: .utf8) else { return false }
        var inKey = false
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                inKey = line.lowercased().hasPrefix(#"[software\\wine\\winedbg]"#)
            } else if inKey && line.lowercased().hasPrefix(#""showcrashdialog"=dword:00000000"#) {
                return true
            }
        }
        return false
    }

    /// `wine reg add` in the game's environment, with the game's own environment variables.
    public static func turnOffCommand(like launch: LaunchCommand) -> LaunchCommand {
        LaunchCommand(executable: launch.executable,
                      arguments: ["reg", "add", key, "/v", "ShowCrashDialog", "/t", "REG_DWORD", "/d", "0", "/f"],
                      environment: launch.environment)
    }
}
