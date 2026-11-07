import Foundation

/// Video playback for games (Media Foundation and DirectShow, which Unreal Engine uses for menu backgrounds and
/// cutscenes) through Wine's winegstreamer. Runtimes built by `scripts/patch-wine-runtime.sh` carry GStreamer with
/// CrossOver's plugin set; H.264 and AAC are decoded by macOS (VideoToolbox, AudioToolbox).
public enum VideoPlayback {
    public static func pluginFolder(root: URL) -> URL { root.appendingPathComponent("lib/gstreamer-1.0") }

    /// Where GStreamer keeps its plugin list for a runtime; rebuilt automatically when the plugins change.
    public static func registryFile(for runtime: WineRuntime, cacheDirectory: URL = defaultCacheDirectory) -> URL {
        let name = runtime.root.deletingLastPathComponent().lastPathComponent
            .map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return cacheDirectory.appendingPathComponent("registry-\(name.isEmpty ? "runtime" : name).x86_64.bin")
    }

    public static var defaultCacheDirectory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("Alloy/gstreamer")
    }

    /// Wine does not tell GStreamer where its plugins are. Only this runtime's plugins are used (not, say, Homebrew's),
    /// and they are scanned in the game's process instead of a helper GStreamer would otherwise try to start.
    public static func environment(for runtime: WineRuntime, cacheDirectory: URL = defaultCacheDirectory) -> [String: String] {
        ["GST_PLUGIN_SYSTEM_PATH_1_0": pluginFolder(root: runtime.root).path,
         "GST_PLUGIN_PATH_1_0": "",
         "GST_REGISTRY_1_0": registryFile(for: runtime, cacheDirectory: cacheDirectory).path,
         "GST_REGISTRY_FORK": "no"]
    }

    /// Environments made before their runtime had winegstreamer lack it: Wine loads a component only from the
    /// environment's own Windows folder, and its classes (the MP4 byte-stream handler, H.264 and AAC decoders) are
    /// registered when the environment is set up.
    public static func needsSetup(prefix: WinePrefix, runtime: WineRuntime, fileManager: FileManager = .default) -> Bool {
        guard runtime.hasGStreamer, !prefix.isReadOnly, prefix.isInitialized(fileManager: fileManager) else { return false }
        if !fileManager.fileExists(atPath: prefix.system32.appendingPathComponent("winegstreamer.dll").path) { return true }
        let registry = (try? String(contentsOf: prefix.path.appendingPathComponent("system.reg"), encoding: .utf8)) ?? ""
        return !registry.localizedCaseInsensitiveContains("winegstreamer.dll")
    }

    /// Copies winegstreamer into system32 (and syswow64, for 32-bit programs), as `wineboot` does for new environments.
    public static func installDLLs(from runtime: WineRuntime, into prefix: WinePrefix, fileManager: FileManager = .default) throws {
        let lib = runtime.root.appendingPathComponent("lib/wine")
        var pairs = [(lib.appendingPathComponent("x86_64-windows/winegstreamer.dll"), prefix.system32)]
        let wow = prefix.path.appendingPathComponent("drive_c/windows/syswow64")
        if fileManager.fileExists(atPath: wow.appendingPathComponent("kernel32.dll").path) {
            pairs.append((lib.appendingPathComponent("i386-windows/winegstreamer.dll"), wow))
        }
        do {
            for (source, folder) in pairs where fileManager.fileExists(atPath: source.path) {
                let target = folder.appendingPathComponent("winegstreamer.dll")
                if fileManager.contentsEqual(atPath: source.path, andPath: target.path) { continue }
                let temporary = folder.appendingPathComponent("winegstreamer.dll.alloy-new")
                try? fileManager.removeItem(at: temporary)
                try fileManager.copyItem(at: source, to: temporary)
                _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
            }
        } catch {
            throw AlloyError.persistenceFailed("Could not add video playback to \(prefix.name): \(error.localizedDescription)")
        }
    }

    /// Wine's own regsvr32 (64-bit, then 32-bit when the environment has it), with the game's environment so it shares
    /// the game's wineserver. No program from the game is run.
    public static func registrationCommands(prefix: WinePrefix, like launch: LaunchCommand,
                                            fileManager: FileManager = .default) -> [LaunchCommand] {
        var commands = [LaunchCommand(executable: launch.executable, arguments: ["regsvr32", "/s", "winegstreamer.dll"],
                                      environment: launch.environment)]
        let wow = prefix.path.appendingPathComponent("drive_c/windows/syswow64")
        if fileManager.fileExists(atPath: wow.appendingPathComponent("regsvr32.exe").path),
           fileManager.fileExists(atPath: wow.appendingPathComponent("winegstreamer.dll").path) {
            commands.append(LaunchCommand(executable: launch.executable,
                                          arguments: [#"C:\windows\syswow64\regsvr32.exe"#, "/s", "winegstreamer.dll"],
                                          environment: launch.environment))
        }
        return commands
    }

    /// Adds and registers winegstreamer when the environment lacks it. Blocking; run it off the main thread.
    public static func prepare(prefix: WinePrefix, runtime: WineRuntime, like launch: LaunchCommand) throws {
        guard needsSetup(prefix: prefix, runtime: runtime) else { return }
        try installDLLs(from: runtime, into: prefix)
        for command in registrationCommands(prefix: prefix, like: launch) {
            let session = LaunchSession(command: command, logFile: nil)
            try session.start()
            guard session.waitUntilExit(timeout: 120) == .exited(code: 0) else {
                throw AlloyError.launchFailed("Wine could not register its video decoders in \(prefix.name).")
            }
        }
    }
}
