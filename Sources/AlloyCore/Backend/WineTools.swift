import Foundation

/// Wine's own programs, opened in one environment, as CrossOver offers for a bottle. None of them is a program the
/// person added: they come with the Wine engine.
public enum WineTool: String, CaseIterable, Sendable {
    case settings, registry, commandPrompt, taskManager, controlPanel, gameControllers, uninstaller, explorer

    public var title: String {
        switch self {
        case .settings: return "Wine Settings"
        case .registry: return "Registry Editor"
        case .commandPrompt: return "Command Prompt"
        case .taskManager: return "Task Manager"
        case .controlPanel: return "Control Panel"
        case .gameControllers: return "Game Controllers"
        case .uninstaller: return "Add or Remove Programs"
        case .explorer: return "Windows File Browser"
        }
    }

    public var arguments: [String] {
        switch self {
        case .settings: return ["winecfg"]
        case .registry: return ["regedit"]
        case .commandPrompt: return ["start", "cmd.exe"]
        case .taskManager: return ["taskmgr"]
        case .controlPanel: return ["control"]
        // Wine's own controller panel: what games see through DirectInput and XInput, with a live button test.
        case .gameControllers: return ["control", "joy.cpl"]
        case .uninstaller: return ["uninstaller"]
        case .explorer: return ["explorer"]
        }
    }
}

/// The version of Windows an environment tells programs it is. Some apps refuse older or newer ones.
public enum WindowsVersion: String, CaseIterable, Sendable {
    case win11, win10, win81, win7, winxp

    public var title: String {
        switch self {
        case .win11: return "Windows 11"
        case .win10: return "Windows 10"
        case .win81: return "Windows 8.1"
        case .win7: return "Windows 7"
        case .winxp: return "Windows XP"
        }
    }

    /// `winecfg -v` sets it for the whole environment.
    public var arguments: [String] { ["winecfg", "-v", rawValue] }

    /// Read from the environment's registry (system.reg) without starting Wine.
    public static func current(in prefix: WinePrefix, fileManager: FileManager = .default) -> WindowsVersion? {
        guard let text = try? String(contentsOf: prefix.path.appendingPathComponent("system.reg"), encoding: .utf8) else { return nil }
        return from(registryText: text)
    }

    static func from(registryText text: String) -> WindowsVersion? {
        guard let range = text.range(of: #"\[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\][^\[]*"#, options: .regularExpression),
              let build = text[range].range(of: #""CurrentBuildNumber"="(\d+)""#, options: .regularExpression)
        else { return nil }
        let number = Int(text[build].filter(\.isNumber)) ?? 0
        switch number {
        case 22000...: return .win11
        case 10240..<22000: return .win10
        case 9600..<10240: return .win81
        case 7600..<9200: return .win7
        case 2600..<3800: return .winxp
        default: return nil
        }
    }
}
