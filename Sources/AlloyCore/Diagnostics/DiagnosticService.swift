import Foundation

/// Removes the user's home path and credential-looking values before anything is shown, stored or exported.
public enum LogRedactor {
    public static let homePath = FileManager.default.homeDirectoryForCurrentUser.path
    static let steamIDPattern = try! NSRegularExpression(pattern: #"\b7656119\d{10}\b"#)
    static let secretPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(password|passwd|pwd|token|secret|api[_-]?key|auth[_-]?code|session[_-]?id)(\s*[=:]\s*)("[^"]*"|\S+)"#)

    public static func redact(_ text: String, homePath: String = LogRedactor.homePath) -> String {
        var result = text
        if !homePath.isEmpty, homePath != "/" { result = result.replacingOccurrences(of: homePath, with: "~") }
        let range = NSRange(result.startIndex..., in: result)
        result = secretPattern.stringByReplacingMatches(in: result, range: range, withTemplate: "$1$2<redacted>")
        // SteamID64 values identify an account.
        let idRange = NSRange(result.startIndex..., in: result)
        return steamIDPattern.stringByReplacingMatches(in: result, range: idRange, withTemplate: "<steamid>")
    }
}

public struct DiagnosticFinding: Identifiable, Hashable, Sendable {
    public enum Severity: String, Comparable, Sendable {
        case info, warning, error
        public static func < (a: Self, b: Self) -> Bool {
            let order: [Self] = [.info, .warning, .error]
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
    }
    public enum Kind: String, Sendable {
        case missingDLL, rosettaMissing, runtimeBroken, runtimeMissing, badPath, vulkanUnavailable,
             directX12Unsupported, crash, antiCheat, wineserverMismatch, prefixPermissions,
             nonZeroExit, graphicsBackendConfirmed, graphicsBackendNotConfirmed, unsupportedArchitecture,
             runtimeLimitation, missingRuntimeComponent, freeze, illegalInstruction, outOfMemory, graphicsDeviceLost,
             storeRequired
    }

    public var id: String { "\(kind.rawValue):\(subject)" }
    public var kind: Kind
    public var severity: Severity
    public var title: String
    public var detail: String
    public var suggestion: String
    public var subject: String
    public var evidence: String?
    /// One-click fixes worth trying, best first (`DiagnosticFix.applies` says which fit this game).
    public var fixes: [DiagnosticFix] = []
}

/// Pattern-based analysis of Wine logs. Each rule maps a known failure signature to a fix.
public enum DiagnosticService {
    struct Rule {
        let kind: DiagnosticFinding.Kind
        let severity: DiagnosticFinding.Severity
        var fixes: [DiagnosticFix] = []
        let pattern: NSRegularExpression
        let make: (_ groups: [String], _ line: String) -> (title: String, detail: String, suggestion: String, subject: String)
    }

    static func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }

    static let rules: [Rule] = [
        // Wine says so when a thread has waited 5 seconds for a critical section, and every minute after.
        Rule(kind: .freeze, severity: .warning,
             pattern: regex(#"wait timed out in thread ([0-9a-f]+), blocked by ([0-9a-f]+)"#)) { g, _ in
            ("A thread was stuck waiting on a lock",
             "Windows thread \(g[0]) waited more than 5 seconds for a lock held by thread \(g[1]). If the picture stopped changing (the cursor may still move), the game froze here.",
             "Alloy saved a backtrace of every thread to a “-threads” file in the Logs folder; it shows where each thread was waiting. Keep it with the log for a bug report. Nothing is sent anywhere.",
             "lock")
        },
        // Media Foundation asks for GStreamer's MP4 byte-stream handler; without winegstreamer videos never start.
        Rule(kind: .runtimeLimitation, severity: .warning,
             pattern: regex(#"class \{317df618-5e5a-468a-9f15-d827a9a08162\} not registered"#)) { _, _ in
            ("Videos cannot play in this runtime",
             "The game tried to open an MP4 video through Media Foundation, but Wine's video decoders (winegstreamer) are not available. Menus with video backgrounds stay blank and cutscenes are skipped or black.",
             "Use an Alloy runtime with video support (alloyctl runtimes shows “Video (GStreamer): yes”), or run scripts/patch-wine-runtime.sh on this one. Alloy adds the decoders to existing environments on the next launch.",
             "gstreamer")
        },
        Rule(kind: .missingDLL, severity: .error,
             pattern: regex(#"Library (\S+\.dll) \(which is needed by L?"([^"]+)"\) not found"#)) { g, _ in
            ("Missing DLL: \(g[0])",
             "\((g[1] as NSString).lastPathComponent) needs a Windows file called \(g[0]) that isn't in this game's environment, so Windows stopped it before it could start.",
             DiagnosticService.dllSuggestion(g[0]), g[0].lowercased())
        },
        Rule(kind: .rosettaMissing, severity: .error, pattern: regex(#"Bad CPU type in executable"#)) { _, _ in
            ("Rosetta 2 is not installed",
             "The Wine runtime is an x86_64 build and macOS cannot run it without Rosetta 2.",
             "Open Setup and click Install Rosetta, or run `softwareupdate --install-rosetta` in Terminal, then try again.", "rosetta")
        },
        Rule(kind: .runtimeBroken, severity: .error,
             pattern: regex(#"(could not load ntdll|could not load kernel32\.dll|wine: failed to initialize)"#)) { g, _ in
            ("Wine runtime is broken or incomplete",
             "Wine could not load its core libraries (\(g[0])).",
             "Quit and reopen Alloy (it clears Wine's old links on each start), then try again. If it keeps happening, reinstall the game engine from Setup.", "core")
        },
        Rule(kind: .badPath, severity: .error, pattern: regex(#"wine: could not open working directory"#)) { _, _ in
            ("Game folder path is too long for Windows",
             "Windows programs cannot use folder paths longer than 260 characters, and this game's folder path is longer.",
             "Move the game folder somewhere with a shorter path, for example a Games folder in your home folder, then add it again.",
             "pathlength")
        },
        Rule(kind: .badPath, severity: .error,
             pattern: regex(#"wine: (cannot find|could not open|failed to open) (?!working directory)['"L]*([^'"]+)['"]*"#)) { g, _ in
            ("Executable path not found by Wine",
             "Wine could not open \(g[1]).",
             "Check that the game folder still exists and the selected executable is correct.", g[1])
        },
        Rule(kind: .vulkanUnavailable, severity: .warning,
             pattern: regex(#"(vkCreateInstance failed|Failed to load (libvulkan|libMoltenVK)|err:vulkan|No Vulkan|VK_ERROR_INCOMPATIBLE_DRIVER)"#)) { _, _ in
            ("Vulkan is unavailable",
             "A Vulkan-based graphics path was requested but no working Vulkan driver (MoltenVK) was found.",
             "Switch to WineD3D (OpenGL), or use a runtime that bundles MoltenVK.", "vulkan")
        },
        Rule(kind: .directX12Unsupported, severity: .warning,
             fixes: [.forceDX11, .addD3DMetal],
             pattern: regex(#"(D3D12CreateDevice failed|DX12 is not supported|D3D12 is not supported|DX11 feature level 10\.0 is required|feature level [0-9.]+ is not supported)"#)) { _, _ in
            ("The game asked for DirectX features this graphics path doesn't have",
             "The game wanted DirectX 12 (or a newer DirectX 11 feature level) and the graphics path it's set to doesn't provide it, so it stopped.",
             "Unreal Engine games can usually run with DirectX 11 instead. Games that only have DirectX 12 need Apple's D3DMetal, which you add from the Game Porting Toolkit.", "dx12")
        },
        // The CPU met an instruction Rosetta 2 doesn't run, nearly always AVX, which Rosetta only offers when asked.
        Rule(kind: .illegalInstruction, severity: .error, fixes: [.advertiseAVX],
             pattern: regex(#"(Unhandled illegal instruction|Unhandled exception: illegal instruction|exception 0xc000001d)"#)) { _, _ in
            ("The game needs a CPU feature it wasn't offered",
             "The game used a processor instruction (usually AVX) that this Mac only provides through Rosetta 2 when the game is told it's there. Without it Windows stops the game straight away.",
             "Turn on AVX for this game and start it again. If AVX is already on, the game needs an instruction set (such as AVX-512) that Rosetta 2 doesn't have.",
             "illegal-instruction")
        },
        Rule(kind: .outOfMemory, severity: .error, fixes: [.turnOffMetalFXUpscaling],
             pattern: regex(#"(out of memory|Out of video memory|E_OUTOFMEMORY|0xc0000017|not enough memory)"#)) { _, _ in
            ("The game ran out of memory",
             "The game asked for more memory than was free, and stopped. Games share memory with the graphics on a Mac, so high texture settings and other open apps both count.",
             "Close other apps (browsers especially), lower the game's texture quality or resolution, then try again.",
             "memory")
        },
        Rule(kind: .graphicsDeviceLost, severity: .error, fixes: [.turnOffMetalFXUpscaling, .turnOffDLSS, .compatibilityMode],
             pattern: regex(#"(DXGI_ERROR_DEVICE_REMOVED|DXGI_ERROR_DEVICE_HUNG|DXGI_ERROR_DEVICE_RESET|D3D device being lost|device removed reason|GPU crashed or D3D Device Removed)"#)) { _, _ in
            ("The graphics stopped responding",
             "The game's graphics work stopped responding (Windows calls this “device removed”), so the game gave up. This usually comes from one heavy setting or effect, not from the Mac.",
             "Lower the game's graphics settings (ray tracing and the highest presets first) or turn off upscaling, then try again.",
             "device-lost")
        },
        Rule(kind: .storeRequired, severity: .warning,
             pattern: regex(#"(SteamAPI_Init\(\) failed|\[S_API FAIL\] SteamAPI_Init|Steam must be running|EOS_Auth|EpicGamesLauncher.*not running)"#)) { _, _ in
            ("The game wants its store app running",
             "This game checks with its store (Steam or Epic) when it starts, and couldn't reach it, so it closed.",
             "Install the store in Alloy from Setup, sign in there, and start the game from the store's entry in your library.",
             "store")
        },
        Rule(kind: .crash, severity: .error, fixes: [.forceDX11, .turnOffDLSS, .turnOffMetalFXUpscaling, .compatibilityMode],
             pattern: regex(#"(?:wine: )?Unhandled (page fault(?: on (read|write|execute) access to (?:0x)?([0-9a-f]+))?|exception (?:0x)?([0-9a-f]{8})|stack overflow|privileged instruction|divide by zero)|EXCEPTION_ACCESS_VIOLATION"#)) { g, line in
            DiagnosticService.crashExplanation(g, line: line)
        },
        Rule(kind: .antiCheat, severity: .error,
             pattern: regex(#"(EasyAntiCheat|BattlEye|BEService|vgk\.sys|EAC launcher)"#)) { g, _ in
            ("Anti-cheat detected: \(g[0])",
             "Kernel-level or Windows-only anti-cheat usually blocks Wine on macOS.",
             "Online modes protected by this anti-cheat are unlikely to work. Offline modes sometimes do.", g[0].lowercased())
        },
        Rule(kind: .wineserverMismatch, severity: .error, fixes: [.stopEnvironment],
             pattern: regex(#"(Server is running with WINEMSYNC but this process is not|msync_init.*bootstrap_look_up|msync: error: client requested|version mismatch|wineserver.*incompatible)"#)) { g, _ in
            g[0].lowercased().contains("msync")
            ? ("Another program in this environment uses a different setting",
               "Every Windows program in an environment shares one Wine background process. One already running there (often Steam) uses a different MSync setting from this game, and Wine can't mix the two.",
               "Quit the other program, or stop the environment, then start the game again.", "msync")
            : ("A different Wine version is running in this environment",
               "Another program in this environment was started by a different Wine version, and the two can't share it.",
               "Stop the environment, then start the game again. Use one game engine per environment.", "wineserver")
        },
        Rule(kind: .prefixPermissions, severity: .error,
             pattern: regex(#"is not owned by you"#)) { _, _ in
            ("Prefix ownership problem",
             "The prefix folder is owned by another user (often after running Wine with sudo).",
             "Never run Wine as administrator. Create a new prefix in Alloy.", "ownership")
        },
        Rule(kind: .runtimeLimitation, severity: .warning,
             pattern: regex(#"failed to load libgnutls"#)) { _, _ in
            ("No encryption support in this runtime",
             "Wine could not load GnuTLS, so Windows programs cannot check certificates or open HTTPS connections. Sign-ins and online features fail.",
             "Use a runtime built with GnuTLS. For runtimes built from CrossOver's sources, run scripts/patch-wine-runtime.sh.", "gnutls")
        },
        Rule(kind: .runtimeLimitation, severity: .warning,
             pattern: regex(#"MetalFX spatial scaler is not supported on this device"#)) { _, _ in
            ("MetalFX upscaling is not active",
             "DXMT reported that this Mac cannot run the MetalFX spatial scaler, so frames are shown at the game's own size.",
             "Turn off MetalFX upscaling for this game.", "metalfx-spatial")
        },
    ]

    /// Plain-English explanation of a Windows crash Wine reported, by kind of exception.
    static func crashExplanation(_ g: [String], line: String) -> (title: String, detail: String, suggestion: String, subject: String) {
        let lower = line.lowercased()
        let tryThis = "Alloy's fixes below are in the order most likely to help. If none does, export a diagnostic report from Advanced → Diagnostics; nothing is sent anywhere."
        if lower.contains("stack overflow") || lower.contains("c00000fd") {
            return ("The game crashed: it ran out of stack space",
                    "A part of the game called itself too deeply and used up its stack, so Windows stopped it. This is usually a bug the game hits under Wine.", tryThis, "crash-stack")
        }
        if lower.contains("c0000409") {
            return ("The game stopped itself after an internal error",
                    "The game noticed something wrong in its own memory and shut itself down on purpose (Windows calls this a fail-fast).", tryThis, "crash-failfast")
        }
        if lower.contains("e06d7363") {
            return ("The game crashed on an error it didn't handle",
                    "The game's own code raised an error and nothing in the game caught it. Missing files or settings it can't read are common reasons.",
                    "Check the game's files (Steam: Verify integrity) and that it has write access to its folder. " + tryThis, "crash-cpp")
        }
        if g.count > 2, !g[1].isEmpty, !g[2].isEmpty {
            let address = g[2].drop { $0 == "0" }
            let null = address.isEmpty || address.count <= 4
            return ("The game crashed",
                    null ? "The game tried to use something that was never created (a null pointer). Under Wine this usually means a feature it expected, often in graphics, failed earlier without saying so."
                         : "The game tried to \(g[1]) memory it doesn't own, so Windows stopped it.",
                    tryThis, "crash")
        }
        return ("The game crashed", "Windows stopped the game after an error it didn't handle.", tryThis, "crash")
    }

    public static func analyze(log: String, exitState: LaunchState? = nil,
                               requestedGraphics: GraphicsBackendKind? = nil) -> [DiagnosticFinding] {
        var findings: [String: DiagnosticFinding] = [:]
        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            for rule in rules {
                guard let m = rule.pattern.firstMatch(in: line, range: range) else { continue }
                let groups = (1..<max(m.numberOfRanges, 1)).map { i -> String in
                    guard let r = Range(m.range(at: i), in: line) else { return "" }
                    return String(line[r])
                }
                let made = rule.make(groups, line)
                var finding = DiagnosticFinding(kind: rule.kind, severity: rule.severity, title: made.title,
                                                detail: made.detail, suggestion: made.suggestion,
                                                subject: made.subject, evidence: line)
                finding.fixes = rule.kind == .missingDLL ? dllFixes(made.subject) : rule.fixes
                if findings[finding.id] == nil { findings[finding.id] = finding }
            }
        }
        // Wine also logs failed large allocations that a game recovers from; after a clean exit they meant nothing.
        if exitState == .exited(code: 0) { findings = findings.filter { $0.value.kind != .outOfMemory } }
        // A specific explanation replaces the general "crashed" one for the same crash.
        if findings.values.contains(where: { [.illegalInstruction, .outOfMemory, .graphicsDeviceLost].contains($0.kind) }) {
            findings = findings.filter { $0.value.kind != .crash }
        }
        if let backend = requestedGraphics, let f = GraphicsVerifier.verify(backend: backend, log: log) {
            findings[f.id] = f
        }
        if case .exited(let code) = exitState, code != 0 {
            var f = DiagnosticFinding(kind: .nonZeroExit, severity: findings.isEmpty ? .warning : .info,
                                      title: "The game closed with an error (code \(code))",
                                      detail: "The game ended by itself and reported a problem, but its log has no error Alloy recognises.",
                                      suggestion: findings.isEmpty
                                        ? "Try Compatibility mode. If that doesn't help, turn on Verbose logging in Advanced → Settings and start the game again, so the log says more."
                                        : "See the other problems for the likely cause.",
                                      subject: "\(code)", evidence: nil)
            if findings.isEmpty { f.fixes = [.compatibilityMode] }
            findings[f.id] = f
        }
        return findings.values.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : $0.title < $1.title
        }
    }

    /// Context checks that do not need a log.
    public static func preflight(game: Game, runtime: WineRuntime?, prefix: WinePrefix?) -> [DiagnosticFinding] {
        var result: [DiagnosticFinding] = []
        if runtime == nil {
            result.append(DiagnosticFinding(kind: .runtimeMissing, severity: .error, title: "No Wine runtime selected",
                detail: "Alloy could not find a usable Wine installation.",
                suggestion: RuntimeInstallGuide.summary, subject: "runtime", evidence: nil))
        }
        do { try ExecutableValidator.validate(game) } catch let error as AlloyError {
            let kind: DiagnosticFinding.Kind
            if case .unsupportedExecutableArchitecture = error { kind = .unsupportedArchitecture } else { kind = .badPath }
            result.append(DiagnosticFinding(kind: kind, severity: .error, title: "Executable problem",
                detail: error.errorDescription ?? "\(error)",
                suggestion: "Edit the game and choose its main .exe again.", subject: "exe", evidence: nil))
        } catch {}
        // Windows programs commonly fail beyond MAX_PATH (260); Z:\ plus the Unix path is what they see.
        if game.executableURL.path.count + 3 > 240 {
            result.append(DiagnosticFinding(kind: .badPath, severity: .warning, title: "Path may be too long for Windows",
                detail: "The executable path is \(game.executableURL.path.count + 3) characters as Windows sees it; many programs fail above 260.",
                suggestion: "Move the game to a shorter folder, for example inside the environment's C: drive.", subject: "pathlength", evidence: nil))
        }
        if let prefix, !prefix.isInitialized() {
            result.append(DiagnosticFinding(kind: .badPath, severity: .warning, title: "Prefix not initialised",
                detail: "\(prefix.name) has not been set up yet.",
                suggestion: "Open Environments and click Initialise.", subject: "prefix", evidence: nil))
        }
        if let prefix, prefix.isInitialized(), !prefix.isReadOnly, VisualCppRuntime.installedVersion(.x64, in: prefix) == nil,
           VisualCppRuntime.gameShipsInstaller(game) {
            result.append(DiagnosticFinding(kind: .missingRuntimeComponent, severity: .warning,
                title: "Visual C++ runtime not installed",
                detail: "This game comes with Microsoft's Visual C++ installer, so it most likely needs the runtime (games then ask for “Visual C++” or report a missing MSVCP140.dll). \(prefix.name) does not have it yet.",
                suggestion: VisualCppRuntime.canInstall(in: prefix)
                    ? "Click Install Visual C++ on the game page. Alloy downloads it from Microsoft and installs it in this environment."
                    : "\(prefix.name) cannot run 32-bit programs, which Microsoft's installer needs. Use a new environment for this game, then install Visual C++ there.",
                subject: "vcruntime", evidence: nil))
        }
        if let runtime, let store = GameStore.store(for: game) {
            for (i, problem) in store.missingRequirements(in: runtime).enumerated() {
                result.append(DiagnosticFinding(kind: .runtimeLimitation, severity: .warning, title: "\(store.displayName) will not fully work on this runtime",
                    detail: problem,
                    suggestion: store == .steam
                        ? "Pick a runtime that has the Steam web helper fix and GnuTLS (Alloy's patched runtimes), or run scripts/patch-wine-runtime.sh on this one."
                        : "Pick a runtime built with GnuTLS, such as Alloy's game engine.",
                    subject: "\(store.rawValue)\(i)", evidence: nil))
            }
        }
        // Store apps' folders hold no game; games started through a store are checked by their log instead.
        let antiCheat = GameStore.store(for: game) == nil ? AntiCheat.detect(in: game.folder) : []
        if !antiCheat.isEmpty {
            result.append(DiagnosticFinding(kind: .antiCheat, severity: .info,
                title: "Online play may be refused: \(antiCheat.joined(separator: " and "))",
                detail: "This game uses \(antiCheat.joined(separator: " and ")). Anti-cheat software decides by itself whether to allow Wine on a Mac, and many games' online modes refuse it, while their offline modes still work. Alloy does not get around anti-cheat.",
                suggestion: "Try the game's offline or single-player mode. If online play is refused, only the developer can allow it.",
                subject: "anticheat", evidence: nil))
        }
        return result
    }

    static func dllFixes(_ dll: String) -> [DiagnosticFix] {
        let name = dll.lowercased()
        if ["msvcp", "vcruntime", "msvcr", "vcomp", "concrt"].contains(where: name.hasPrefix) { return [.installVisualCpp] }
        if name == "mscoree.dll" { return [.installDotNet] }
        if name.hasPrefix("d3d12") { return [.forceDX11, .addD3DMetal] }
        return CustomDLLs.protected.contains(name) ? [] : [.addDLL]
    }

    static func dllSuggestion(_ dll: String) -> String {
        let name = dll.lowercased()
        if name.hasPrefix("msvcp") || name.hasPrefix("vcruntime") || name.hasPrefix("msvcr") || name.hasPrefix("concrt") {
            return "It comes with Microsoft's Visual C++ runtime. Click Install Visual C++: Alloy downloads it from Microsoft and installs it in this environment."
        }
        if name.hasPrefix("d3dx9") || name.hasPrefix("d3dx10") || name.hasPrefix("d3dx11") || name.hasPrefix("xinput1_") || name.hasPrefix("xaudio2_") || name.hasPrefix("d3dcompiler") {
            return "It's part of Microsoft's older DirectX runtime (June 2010). Many games ship its installer in a folder such as _CommonRedist or DirectX: run DXSETUP.exe from there with Install from Setup File, in this game's environment."
        }
        if name == "mscoree.dll" {
            return "The game is a .NET program. Click Install .NET: Alloy installs Wine Mono, Wine's own .NET, from WineHQ."
        }
        if name.hasPrefix("d3d12") {
            return "The game needs DirectX 12 here. Unreal Engine games can usually use DirectX 11 instead; otherwise add Apple's D3DMetal."
        }
        return "Look in the game's folder for a redistributables folder (often _CommonRedist or Redist) with the installer that provides \(dll), and run it with Install from Setup File in this game's environment. If you have the file itself from the program's maker, click Add DLL. Avoid DLL download websites: they often spread malware."
    }
}

/// Decides whether the requested graphics backend is actually in use, using evidence in the log.
public enum GraphicsVerifier {
    static let markers: [GraphicsBackendKind: [String]] = [
        .dxvk: ["info:  DXVK: v", "DXVK: v"],
        .d3dMetal: ["D3DMetal", "D3DM"],
        // DXVK prints "D3D11InternalCreateDevice: Maximum supported…", so this exact form is DXMT's.
        .dxmt: ["info:  Maximum supported feature level: "],
        .wined3dVulkan: ["Using the Vulkan renderer", "wined3d_adapter_vk"],
        .vkd3d: ["vkd3d:", "vkd3d-"],
        .wined3dOpenGL: ["Using the OpenGL renderer", "wined3d_adapter_gl"],
    ]

    public static func verify(backend: GraphicsBackendKind, log: String) -> DiagnosticFinding? {
        let markers = markers[backend] ?? []
        // Only lines produced by the program count — not Alloy's own "Starting ..." line with the environment.
        let programLog = log.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("[Alloy]") }.joined(separator: "\n")
        if let hit = markers.first(where: { programLog.contains($0) }) {
            return DiagnosticFinding(kind: .graphicsBackendConfirmed, severity: .info,
                                     title: "\(backend.displayName) confirmed active",
                                     detail: "The log contains “\(hit)”.", suggestion: "", subject: backend.rawValue, evidence: hit)
        }
        return DiagnosticFinding(kind: .graphicsBackendNotConfirmed, severity: .info,
                                 title: "\(backend.displayName) requested, not confirmed",
                                 detail: "No log evidence shows this graphics path was used. Many games log nothing about their renderer, so this is not necessarily a problem.",
                                 suggestion: "Enable the Metal HUD to see the active Metal device, or use Verbose logging.",
                                 subject: backend.rawValue, evidence: nil)
    }
}

public enum RuntimeInstallGuide {
    public static let summary = "Install a free Wine build: download wine-devel or wine-staging (osx64) from github.com/Gcenx/macOS_Wine_builds/releases, extract it and move “Wine Devel.app” or “Wine Staging.app” to /Applications. These builds run under Rosetta 2. The Homebrew wine-stable cask was disabled on 2026-09-01."
}

/// Builds a local, redacted diagnostic report. Nothing is uploaded.
public struct DiagnosticReport: Sendable {
    public var generatedAt = Date()
    public var system: [String: String]
    public var game: Game?
    public var runtime: WineRuntime?
    public var prefix: WinePrefix?
    public var state: LaunchState?
    public var findings: [DiagnosticFinding]
    public var logTail: [String]

    public init(game: Game?, runtime: WineRuntime?, prefix: WinePrefix?, state: LaunchState?,
                findings: [DiagnosticFinding], log: String, tailLines: Int = 400) {
        self.game = game
        self.runtime = runtime
        self.prefix = prefix
        self.state = state
        self.findings = findings
        self.logTail = Array(log.split(whereSeparator: \.isNewline).suffix(tailLines).map { LogRedactor.redact(String($0)) })
        self.system = DiagnosticReport.systemInfo()
    }

    public static func systemInfo() -> [String: String] {
        let info = ProcessInfo.processInfo
        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif
        return [
            "macOS": info.operatingSystemVersionString,
            "Architecture": arch,
            "Physical memory": "\(info.physicalMemory / 1_073_741_824) GB",
            "Rosetta 2": FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime") ? "installed" : "not found",
        ]
    }

    public func markdown() -> String {
        var out = "# Alloy diagnostic report\n\nGenerated: \(ISO8601DateFormatter().string(from: generatedAt))\n\n## System\n"
        for key in system.keys.sorted() { out += "- \(key): \(system[key]!)\n" }
        if let game {
            out += "\n## Game\n- Name: \(game.name)\n- Executable: \(LogRedactor.redact(game.executableURL.path))\n"
            out += "- Arguments: \(ArgumentParser.join(game.arguments))\n"
            out += "- Graphics (requested): \(game.graphics.backend.displayName), preset \(game.graphics.preset.displayName), target \(game.graphics.targetFPS) FPS\n"
            out += "- Custom environment keys: \(game.environment.keys.sorted().joined(separator: ", "))\n"
        }
        if let runtime {
            out += "\n## Runtime\n- \(runtime.displayName)\n- Binary: \(LogRedactor.redact(runtime.wineBinary.path))\n"
            out += "- Architectures: \(runtime.architectures.map(\.rawValue).joined(separator: ", "))\n"
            out += "- MoltenVK: \(runtime.hasMoltenVK ? "yes" : "no"), D3DMetal: \(runtime.hasD3DMetal ? "yes" : "no")\n"
        }
        if let prefix {
            out += "\n## Prefix\n- \(prefix.name) (\(prefix.origin.rawValue), \(prefix.architecture))\n- Path: \(LogRedactor.redact(prefix.path.path))\n"
        }
        if let state { out += "\n## Result\n- \(state.summary)\n" }
        out += "\n## Findings\n"
        if findings.isEmpty { out += "- None\n" }
        for f in findings {
            out += "- **[\(f.severity.rawValue)] \(f.title)** — \(f.detail)"
            if !f.suggestion.isEmpty { out += " Suggestion: \(f.suggestion)" }
            out += "\n"
        }
        out += "\n## Log (last \(logTail.count) lines, redacted)\n```\n\(logTail.joined(separator: "\n"))\n```\n"
        return out
    }

    public func write(to url: URL) throws {
        do { try markdown().write(to: url, atomically: true, encoding: .utf8) }
        catch { throw AlloyError.persistenceFailed(error.localizedDescription) }
    }
}
