import CryptoKit
import Foundation

/// Microsoft's Visual C++ 2015–2022 Redistributable (MSVCP140.dll, VCRUNTIME140.dll and friends), which most
/// recent games need and many check for before they start. Only Microsoft's own installer is run: downloaded from
/// Microsoft over HTTPS, checked against the SHA-256 in Microsoft's download address, and only after the user asks.
public enum VisualCppRuntime {
    public enum Architecture: String, CaseIterable, Codable, Sendable {
        case x64, x86

        /// Microsoft's permanent link to the latest v14 (2015–2022) installer. It redirects to
        /// download.visualstudio.microsoft.com, whose path contains the file's SHA-256.
        public var downloadURL: URL { URL(string: "https://aka.ms/vs/17/release/vc_redist.\(rawValue).exe")! }
        public var fileName: String { "VC_redist.\(rawValue).exe" }
        /// Approximate download size, for the confirmation text.
        public var approximateMegabytes: Int { self == .x64 ? 26 : 14 }

        /// Key the installer writes and that game launchers check. Wine keeps the 32-bit view under Wow6432Node.
        var registryKey: String {
            self == .x64 ? #"Software\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64"#
                         : #"Software\\Wow6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86"#
        }
    }

    /// The only host an installer is accepted from, after aka.ms redirects.
    public static let trustedHost = "download.visualstudio.microsoft.com"

    /// DLLs switched to Microsoft's copies once the runtime is installed, as winetricks' `vcrun2022` does. Wine's own
    /// versions stay as the fallback (`native,builtin`).
    public static let nativeDLLs = ["concrt140", "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait",
                                    "msvcp140_codecvt_ids", "vcamp140", "vccorlib140", "vcomp140", "vcruntime140",
                                    "vcruntime140_1"]

    // MARK: State of an environment

    /// Both installers are 32-bit programs (the x64 one too), so they need an environment that runs 32-bit code.
    /// Environments made before Alloy set up 32-bit support have an empty syswow64.
    public static func canInstall(in prefix: WinePrefix, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: prefix.path.appendingPathComponent("drive_c/windows/syswow64/kernel32.dll").path)
    }

    /// Installed version (for example "v14.44.35211.00"), or nil when Microsoft's DLLs are not in the environment.
    /// The registry alone proves nothing: Wine's own setup writes "installed" keys for Visual C++ 14.42 into every
    /// new environment, while its DLLs are Wine's builtin stand-ins.
    public static func installedVersion(_ arch: Architecture, in prefix: WinePrefix) -> String? {
        guard hasMicrosoftDLLs(arch, in: prefix) else { return nil }
        guard let text = try? String(contentsOf: prefix.path.appendingPathComponent("system.reg"), encoding: .utf8) else { return "installed" }
        return installedVersion(arch, registryText: text) ?? "installed"
    }

    /// DLLs games import most, per architecture (vcruntime140_1 exists only for x64).
    static func coreDLLs(_ arch: Architecture) -> [String] {
        arch == .x64 ? ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"] : ["msvcp140.dll", "vcruntime140.dll"]
    }

    /// True when the core DLLs exist in system32 (x64) or syswow64 (x86) and none is a Wine builtin.
    public static func hasMicrosoftDLLs(_ arch: Architecture, in prefix: WinePrefix) -> Bool {
        let folder = prefix.path.appendingPathComponent(arch == .x64 ? "drive_c/windows/system32" : "drive_c/windows/syswow64")
        return coreDLLs(arch).allSatisfy { name in
            let url = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) && !isWineBuiltin(url)
        }
    }

    /// Wine marks its builtin PE files with "Wine builtin DLL" right after the DOS header.
    static func isWineBuiltin(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: 0x40)) != nil, let bytes = try? handle.read(upToCount: 16) else { return false }
        return bytes == Data("Wine builtin DLL".utf8)
    }

    static func installedVersion(_ arch: Architecture, registryText text: String) -> String? {
        let header = "[\(arch.registryKey.lowercased())]"
        var inKey = false, installed = false
        var version: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                if inKey { break }
                inKey = line.lowercased().hasPrefix(header)
            } else if inKey {
                let lower = line.lowercased()
                if lower.hasPrefix(#""installed"=dword:"#) { installed = lower.hasSuffix("00000001") }
                if lower.hasPrefix(#""version"=""#) { version = String(line.dropFirst(#""Version"=""#.count).dropLast()) }
            }
        }
        return installed ? (version ?? "installed") : nil
    }

    /// Version from `reg query` output, or nil when the key or value is missing.
    public static func parseQuery(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 3, fields[0].lowercased() == "version", fields[1] == "REG_SZ" { return String(fields[2]) }
        }
        return nil
    }

    /// True when both the 64-bit and the 32-bit runtime are installed (games use one, their launchers often the other).
    public static func isInstalled(in prefix: WinePrefix) -> Bool {
        Architecture.allCases.allSatisfy { installedVersion($0, in: prefix) != nil }
    }

    /// Games that ship Microsoft's installer (Steam's `_CommonRedist`, Unreal's prerequisites) need the runtime.
    /// Looks in the game folder and two folders above it, for multi-game packages; only names are checked.
    public static func gameShipsInstaller(_ game: Game, fileManager: FileManager = .default) -> Bool {
        var folder = game.folder.standardizedFileURL
        for _ in 0..<3 {
            for marker in ["_CommonRedist/vcredist", "Engine/Extras/Redist/en-us/UEPrereqSetup_x64.exe"]
            where fileManager.fileExists(atPath: folder.appendingPathComponent(marker).path) { return true }
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { break }
            folder = parent
        }
        return false
    }

    // MARK: Download

    /// The installer in `folder`, if it is there and still has the SHA-256 recorded when it was downloaded.
    public static func verifiedInstaller(_ arch: Architecture, in folder: URL) -> URL? {
        let file = folder.appendingPathComponent(arch.fileName)
        guard let recorded = try? String(contentsOf: hashFile(file), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let actual = sha256(of: file), actual == recorded else { return nil }
        return file
    }

    /// SHA-256 that Microsoft puts in the download path, for example `/download/pr/<id>/<SHA-256>/VC_redist.x64.exe`.
    public static func expectedHash(from url: URL) -> String? {
        guard url.scheme == "https", url.host?.lowercased() == trustedHost else { return nil }
        return url.pathComponents.first { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }?.lowercased()
    }

    /// Downloads one installer into `folder` over HTTPS with the system's certificate checks. The file is kept only if
    /// it came from Microsoft's download host, matches the SHA-256 in that address and is a Windows program.
    public static func download(_ arch: Architecture, to folder: URL) async throws -> URL {
        let (temporary, response) = try await AlloyHTTP.session.download(from: arch.downloadURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AlloyError.downloadFailed("Microsoft's server answered with HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        guard let final = http.url, let expected = expectedHash(from: final) else {
            throw AlloyError.downloadFailed("The download did not come from \(trustedHost) (it came from \(http.url?.host ?? "an unknown host")), so it was not used.")
        }
        guard let actual = sha256(of: temporary), actual == expected else {
            throw AlloyError.downloadFailed("The downloaded \(arch.fileName) does not match the checksum in Microsoft's download address, so it was not used.")
        }
        guard (try? PEInspector.inspect(temporary)) != nil else {
            throw AlloyError.downloadFailed("The downloaded \(arch.fileName) is not a Windows program, so it was not used.")
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(arch.fileName)
        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: temporary, to: target)
        try actual.write(to: hashFile(target), atomically: true, encoding: .utf8)
        return target
    }

    static func hashFile(_ installer: URL) -> URL { installer.appendingPathExtension("sha256") }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Install

    /// The installer as a launch, so it runs with the environment's runtime and sync mode like any program.
    public static func installerGame(installer: URL, prefix: WinePrefix) -> Game {
        Game(name: "Visual C++ Runtime Setup", folder: installer.deletingLastPathComponent(),
             executableRelativePath: installer.lastPathComponent, prefixID: prefix.id,
             arguments: ["/install", "/quiet", "/norestart"], graphics: GraphicsConfiguration())
    }

    /// Wine's own `reg.exe` reading the installed version, sharing the environment's wineserver.
    public static func queryCommand(_ arch: Architecture, like launch: LaunchCommand) -> LaunchCommand {
        let key = "HKLM\\" + arch.registryKey.replacingOccurrences(of: #"\\"#, with: #"\"#)
        return LaunchCommand(executable: launch.executable, arguments: ["reg", "query", key, "/v", "Version"],
                             environment: launch.environment)
    }

    /// REGEDIT4 file that makes Wine prefer Microsoft's DLLs; imported with `reg import`.
    public static func overridesRegistryFile() -> String {
        (["REGEDIT4", "", #"[HKEY_CURRENT_USER\Software\Wine\DllOverrides]"#]
            + nativeDLLs.map { #""\#($0)"="native,builtin""# } + [""]).joined(separator: "\r\n")
    }

    public static func importCommand(file windowsPath: String, like launch: LaunchCommand) -> LaunchCommand {
        LaunchCommand(executable: launch.executable, arguments: ["reg", "import", windowsPath], environment: launch.environment)
    }

    /// Downloads what is missing, runs each installer silently, switches the DLLs to Microsoft's copies and returns the
    /// installed version per architecture. Throws when an installer fails or the runtime is not found afterwards.
    public static func install(into prefix: WinePrefix, runtime: WineRuntime, backend: WineBackend, downloads: URL,
                               progress: @Sendable (String) -> Void) async throws -> [Architecture: String] {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        guard prefix.isInitialized() else { throw AlloyError.prefixNotInitialized(name: prefix.name) }
        guard canInstall(in: prefix) else {
            throw AlloyError.launchFailed("\(prefix.name) cannot run 32-bit programs, and Microsoft's installer is one. Create a new environment for this game (or use Switch to DXMT on the game page), then install Visual C++ there.")
        }
        var versions: [Architecture: String] = [:]
        var lastCommand: LaunchCommand?
        for arch in Architecture.allCases {
            var installer = verifiedInstaller(arch, in: downloads)
            if installer == nil {
                progress("Downloading Visual C++ (\(arch.rawValue)) from Microsoft…")
                do { installer = try await download(arch, to: downloads) } catch let error as AlloyError {
                    throw error
                } catch {
                    throw AlloyError.downloadFailed("Could not download Visual C++ (\(arch.rawValue)): \(error.localizedDescription)")
                }
            }
            guard let installer else { continue }
            progress("Installing Visual C++ (\(arch.rawValue)) in \(prefix.name)…")
            let command = try backend.launchCommand(for: installerGame(installer: installer, prefix: prefix),
                                                    prefix: prefix, runtime: runtime, options: LaunchOptions())
            lastCommand = command
            let run = LaunchSession(command: command, logFile: nil)
            try run.start()
            // The exit status is not checked: Unix keeps only its low 8 bits, so 3010 ("restart needed") and 1638
            // ("a newer version is installed") would look like failures. The registry says whether it worked.
            let state = run.waitUntilExit(timeout: 900)
            let query = LaunchSession(command: queryCommand(arch, like: command), logFile: nil)
            try query.start()
            _ = query.waitUntilExit(timeout: 120)
            // Wine's setup already registers a fake 14.42, so only Microsoft's DLLs on disk prove the install worked.
            guard hasMicrosoftDLLs(arch, in: prefix) else {
                throw AlloyError.launchFailed("Microsoft's Visual C++ (\(arch.rawValue)) installer ended (\(state.summary.lowercased())), but its DLLs are not in \(prefix.name).")
            }
            versions[arch] = parseQuery(query.fullLog) ?? "installed"
        }
        if let lastCommand {
            progress("Switching to Microsoft's Visual C++ DLLs…")
            let file = prefix.path.appendingPathComponent("drive_c/windows/temp/alloy-vcruntime.reg")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try overridesRegistryFile().write(to: file, atomically: true, encoding: .ascii)
            let imp = LaunchSession(command: importCommand(file: #"C:\windows\temp\alloy-vcruntime.reg"#, like: lastCommand), logFile: nil)
            try imp.start()
            guard imp.waitUntilExit(timeout: 120) == .exited(code: 0) else {
                throw AlloyError.launchFailed("Visual C++ is installed, but Wine's DLL settings could not be changed.")
            }
        }
        return versions
    }
}
