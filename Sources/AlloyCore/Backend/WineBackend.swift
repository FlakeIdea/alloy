import Foundation

/// Backend for Wine builds driven through Wine's documented CLI and environment variables.
public struct WineBackend: CompatibilityBackend {
    public let id = "wine"
    public let displayName = "Wine"

    /// Directories searched for `*.app` Wine bundles (Gcenx builds, GPTK repacks).
    public var applicationDirectories: [URL]
    /// Plain install roots that contain `bin/wine` (Homebrew, manual installs, Alloy-managed runtimes).
    public var installRoots: [URL]
    /// Alloy-managed runtimes, one folder each containing `wine/` and a manifest.
    public var managedRuntimesDirectory: URL?
    /// Probes `wine --version`. Injected so tests never execute anything.
    public var versionProbe: @Sendable (URL) -> String?
    /// Reports whether a prefix's wineserver runs, and with MSync. Injected so tests don't depend on running servers.
    public var serverProbe: @Sendable (WinePrefix) -> WineServer.State = WineServer.state(of:)
    private var fileManager: FileManager { .default }

    public init(applicationDirectories: [URL]? = nil,
                installRoots: [URL]? = nil,
                managedRuntimesDirectory: URL? = nil,
                versionProbe: (@Sendable (URL) -> String?)? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
        self.installRoots = installRoots ?? [
            URL(fileURLWithPath: "/opt/homebrew"),
            URL(fileURLWithPath: "/usr/local"),
            URL(fileURLWithPath: "/usr/local/opt/game-porting-toolkit"),
        ]
        self.managedRuntimesDirectory = managedRuntimesDirectory
        self.versionProbe = versionProbe ?? WineBackend.probeVersion
    }

    // MARK: Discovery

    public func discoverRuntimes() -> [WineRuntime] {
        var found: [WineRuntime] = []
        var seen = Set<String>()
        func consider(root: URL, kind: RuntimeKind, name: String? = nil) {
            for binaryName in ["wine", "wine64"] {
                let binary = root.appendingPathComponent("bin/\(binaryName)")
                guard fileManager.isExecutableFile(atPath: binary.path) else { continue }
                let key = binary.resolvingSymlinksInPath().path
                guard !seen.contains(key) else { return }
                seen.insert(key)
                var runtime = makeRuntime(kind: kind, binary: binary, root: root)
                runtime.customName = name
                found.append(runtime)
                return
            }
        }
        for dir in applicationDirectories {
            guard let apps = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for app in apps where app.pathExtension == "app" {
                let name = app.deletingPathExtension().lastPathComponent.lowercased()
                guard name.contains("wine") || name.contains("game porting toolkit") else { continue }
                // CrossOver is deliberately excluded: its Wine is licensed with the CrossOver product.
                consider(root: app.appendingPathComponent("Contents/Resources/wine"), kind: Self.kind(forAppName: name))
            }
        }
        for root in installRoots {
            let kind: RuntimeKind = root.path.contains("game-porting-toolkit") ? .gamePortingToolkit
                : (root.path.hasPrefix("/opt/homebrew") || root.path == "/usr/local" ? .homebrew : .custom)
            consider(root: root, kind: kind)
        }
        if let managed = managedRuntimesDirectory,
           let folders = try? fileManager.contentsOfDirectory(at: managed, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for folder in folders.sorted(by: { $0.path < $1.path }) {
                let manifest = JSONFileStore<ManagedRuntimeManifest?>(
                    fileURL: folder.appendingPathComponent(D3DMetalImporter.manifestName)).load(default: nil)
                let layer = manifest?.translationLayer.flatMap(TranslationLayer.init(rawValue:)) ?? .d3dMetal
                let kind: RuntimeKind = layer == .d3dMetal ? .gamePortingToolkit : .custom
                consider(root: folder.appendingPathComponent("wine"), kind: kind,
                         name: manifest.map { "Alloy · \($0.name)" })
            }
        }
        return found
    }

    public func makeRuntime(kind: RuntimeKind, binary: URL, root: URL) -> WineRuntime {
        let archs: [HostArchitecture]
        if case .machO(let a) = MachOInspector.inspect(binary) { archs = a } else { archs = [] }
        let libs = ["lib", "lib64", "lib/external", "lib/wine"].map { root.appendingPathComponent($0) }
        let hasMVK = libs.contains { fileManager.fileExists(atPath: $0.appendingPathComponent("libMoltenVK.dylib").path) }
        let hasD3DM = libs.contains { fileManager.fileExists(atPath: $0.appendingPathComponent("D3DMetal.framework").path) }
        let wineLib = root.appendingPathComponent("lib/wine")
        let hasDXMT = fileManager.fileExists(atPath: wineLib.appendingPathComponent("x86_64-windows/winemetal.dll").path)
            && fileManager.fileExists(atPath: wineLib.appendingPathComponent("x86_64-unix/winemetal.so").path)
        // Which fast-sync switches this build understands, read from its ntdll rather than guessed from its name.
        let ntdll = (try? Data(contentsOf: wineLib.appendingPathComponent("x86_64-unix/ntdll.so"), options: .alwaysMapped)) ?? Data()
        let win = wineLib.appendingPathComponent("x86_64-windows")
        let hasNVNGX = ["nvngx.dll", "nvngx-on-metalfx.dll"].contains { fileManager.fileExists(atPath: win.appendingPathComponent($0).path) }
            && fileManager.fileExists(atPath: win.appendingPathComponent("nvapi64.dll").path)
        // Frame interpolation is read from D3DMetal's own code (about 8 MB), not assumed from its version.
        let d3dm = libs.map { $0.appendingPathComponent("D3DMetal.framework/D3DMetal") }.first { fileManager.fileExists(atPath: $0.path) }
        let hasInterpolation = d3dm.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }?
            .range(of: Data("MTLFXFrameInterpolatorDescriptor".utf8)) != nil
        // The web helper fix matches Steam's executable by name, so kernelbase holds it as a wide string.
        let kernelbase = (try? Data(contentsOf: win.appendingPathComponent("kernelbase.dll"), options: .alwaysMapped)) ?? Data()
        let hasWebHelperFix = kernelbase.range(of: Data("steamwebhelper.exe".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })) != nil
        // The frame-latency option is read from DXMT's own d3d11 (about 4 MB), not assumed from the engine's version.
        let hasLatency = hasDXMT && ((try? Data(contentsOf: win.appendingPathComponent("d3d11.dll"), options: .alwaysMapped))?
            .range(of: Data(FrameQueue.configKey.utf8)) != nil)
        // The scroll speed is read from the Mac driver's own code, not assumed from the engine's version.
        let winemac = (try? Data(contentsOf: wineLib.appendingPathComponent("x86_64-unix/winemac.so"), options: .alwaysMapped)) ?? Data()
        // bcrypt names libgnutls only when Wine was configured with it.
        let bcrypt = (try? Data(contentsOf: wineLib.appendingPathComponent("x86_64-unix/bcrypt.so"), options: .alwaysMapped)) ?? Data()
        return WineRuntime(kind: kind, wineBinary: binary, root: root, version: versionProbe(binary),
                           architectures: archs, hasMoltenVK: hasMVK, hasD3DMetal: hasD3DM, hasDXMT: hasDXMT,
                           hasMSync: ntdll.range(of: Data("WINEMSYNC".utf8)) != nil,
                           hasESync: ntdll.range(of: Data("WINEESYNC".utf8)) != nil,
                           hasNVNGX: hasNVNGX, hasFrameInterpolation: hasInterpolation,
                           hasSteamWebHelperFix: hasWebHelperFix,
                           hasGnuTLS: bcrypt.range(of: Data("libgnutls".utf8)) != nil,
                           hasGStreamer: fileManager.fileExists(atPath: wineLib.appendingPathComponent("x86_64-unix/winegstreamer.so").path)
                               && fileManager.fileExists(atPath: VideoPlayback.pluginFolder(root: root).path),
                           // The bundle's Info.plist is written by ntdll, so the games category is in its strings.
                           hasGameModeBundles: ntdll.range(of: Data("public.app-category.games".utf8)) != nil,
                           hasFrameLatencyOption: hasLatency,
                           hasScrollSpeedOption: winemac.range(of: Data(ScrollSpeed.variable.utf8)) != nil,
                           hasLargeAddressOption: ntdll.range(of: Data(LargeAddressSpace.variable.utf8)) != nil)
    }

    static func kind(forAppName name: String) -> RuntimeKind {
        if name.contains("game porting toolkit") { return .gamePortingToolkit }
        if name.contains("staging") { return .wineStaging }
        if name.contains("devel") { return .wineDevel }
        if name.contains("stable") { return .wineStable }
        return .custom
    }

    /// Runs `wine --version` with a timeout. This executes only the macOS Wine loader, never a Windows program.
    @Sendable public static func probeVersion(_ binary: URL) -> String? {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parseVersion(output)
    }

    /// "wine-11.20 (Staging)" → "11.20 (Staging)".
    public static func parseVersion(_ output: String) -> String? {
        let line = output.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard line.hasPrefix("wine-") else { return nil }
        return String(line.dropFirst(5))
    }

    /// Moves an Alloy-managed runtime to the Trash (recoverable). Refuses runtimes Alloy didn't create
    /// and runtimes an environment still uses.
    public func trashManagedRuntime(_ runtime: WineRuntime, usedBy prefixes: [WinePrefix]) throws {
        guard let managed = managedRuntimesDirectory?.standardizedFileURL,
              runtime.root.standardizedFileURL.path.hasPrefix(managed.path + "/") else {
            throw AlloyError.runtimeUnavailable("\(runtime.displayName) isn't an Alloy-managed runtime; remove it yourself.")
        }
        if let user = prefixes.first(where: { $0.runtimeID == runtime.id }) {
            throw AlloyError.runtimeUnavailable("\(runtime.displayName) is still used by the environment \(user.name).")
        }
        // Managed runtimes live at Runtimes/<folder>/wine; trash the whole <folder>.
        var folder = runtime.root.standardizedFileURL
        while folder.deletingLastPathComponent().path != managed.path { folder.deleteLastPathComponent() }
        try fileManager.trashItem(at: folder, resultingItemURL: nil)
    }

    // MARK: Capabilities

    public func capabilities(of runtime: WineRuntime) -> BackendCapabilities {
        let noMVK = "No MoltenVK (libMoltenVK.dylib) found in this runtime."
        var graphics: [GraphicsBackendKind: CapabilityStatus] = [.wined3dOpenGL: .available]
        graphics[.wined3dVulkan] = runtime.hasMoltenVK
            ? .experimental("Vulkan renderer over MoltenVK. Not always faster than OpenGL.") : .unavailable(noMVK)
        graphics[.vkd3d] = runtime.hasMoltenVK
            ? .experimental("Wine's built-in D3D12 over MoltenVK. Low game compatibility.") : .unavailable(noMVK)
        graphics[.dxvk] = runtime.hasMoltenVK
            ? .experimental("Needs DXVK-macOS DLLs installed into the prefix. Upstream DXVK 2.x/3.x does not run on MoltenVK.")
            : .unavailable(noMVK)
        graphics[.d3dMetal] = !SystemCheck.isAppleSilicon
            ? .unavailable("D3DMetal needs a Mac with Apple silicon.")
            : runtime.hasD3DMetal
            ? .available
            : .unavailable("Needs a Game Porting Toolkit-based Wine containing D3DMetal.framework. Proprietary; you supply it.")
        graphics[.dxmt] = !SystemCheck.isAppleSilicon
            ? .unavailable("DXMT needs a Mac with Apple silicon. On Intel Macs, games use OpenGL or Vulkan.")
            : runtime.hasDXMT
            ? .experimental("Open-source D3D10/11 → Metal. Replaces Wine's d3d11/dxgi in this runtime copy.")
            : .unavailable("Needs the Alloy game engine with DXMT. Install it from Setup.")

        var sync: [SyncMode] = [.default]
        if runtime.hasMSync { sync.append(.off) }
        if runtime.hasESync || runtime.kind == .wineStaging || runtime.kind == .gamePortingToolkit { sync.append(.esync) }
        if runtime.hasMSync { sync.append(.msync) }

        var notes: [String] = []
        if runtime.requiresRosetta { notes.append("x86_64 build: runs under Rosetta 2.") }
        if !SystemCheck.isAppleSilicon { notes.append("Intel Mac: the engine runs natively, without Rosetta.") }
        if runtime.version == nil { notes.append("Version could not be determined.") }
        var upscaling: Set<GraphicsBackendKind> = []
        if SystemCheck.isAppleSilicon, runtime.hasNVNGX && runtime.hasD3DMetal { upscaling.insert(.d3dMetal) }
        if SystemCheck.isAppleSilicon, runtime.hasNVNGX && runtime.hasDXMT { upscaling.insert(.dxmt) }
        let frameGeneration: Set<GraphicsBackendKind> = upscaling.contains(.d3dMetal) && runtime.hasFrameInterpolation ? [.d3dMetal] : []
        var caps = BackendCapabilities(graphics: graphics, syncModes: sync, supportsMetalHUD: true,
                                   supportsAVXAdvertisement: runtime.requiresRosetta, notes: notes,
                                   metalFXUpscaling: upscaling, metalFXFrameGeneration: frameGeneration,
                                   metalFXSpatialUpscaling: runtime.hasDXMT ? [.dxmt] : [],
                                   frameQueue: runtime.hasDXMT && runtime.hasFrameLatencyOption ? [.dxmt] : [],
                                   scrollSpeed: runtime.hasScrollSpeedOption,
                                   largeAddressSpace: runtime.hasLargeAddressOption)
        if runtime.hasD3DMetal && RayTracing.thisMacHasHardwareRayTracing { caps.rayTracing = [.d3dMetal] }
        return caps
    }

    // MARK: Commands

    /// For every Wine process Alloy starts in the prefix, games and Wine's own tools alike.
    ///
    /// The first process of a Wine session fills in what Windows reports about the processor
    /// (`IsProcessorFeaturePresent`, the enabled extended state) for every program started after it. Under Rosetta 2
    /// the processor only shows AVX when asked to, so a session begun by `wineboot` or an installer without
    /// `ROSETTA_ADVERTISE_AVX` told the games that followed "no AVX" through Windows while the processor itself
    /// reported it. Asking in every process keeps the two the same.
    func baseEnvironment(prefix: WinePrefix, runtime: WineRuntime, logLevel: LogLevel) -> [String: String] {
        var env = ["WINEPREFIX": prefix.path.path, "WINEDEBUG": logLevel.wineDebug]
        if runtime.requiresRosetta { env[Self.advertiseAVXVariable] = "1" }
        return env
    }

    static let advertiseAVXVariable = "ROSETTA_ADVERTISE_AVX"

    public func initializePrefixCommand(prefix: WinePrefix, runtime: WineRuntime) throws -> LaunchCommand {
        try wineboot("--init", prefix: prefix, runtime: runtime)
    }

    /// `wineboot --update` with the same overrides as `--init`, after the prefix moved to another engine.
    public func updatePrefixCommand(prefix: WinePrefix, runtime: WineRuntime) throws -> LaunchCommand {
        try wineboot("--update", prefix: prefix, runtime: runtime)
    }

    private func wineboot(_ mode: String, prefix: WinePrefix, runtime: WineRuntime) throws -> LaunchCommand {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        // These runtimes ship without Wine Mono and Gecko. Without the overrides wineboot stops at a download
        // prompt and never finishes (offline it cannot). Install them later only if a program needs .NET or MSHTML.
        var env = baseEnvironment(prefix: prefix, runtime: runtime, logLevel: .standard)
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        // Games default to MSync and share this wineserver if they start within seconds; a wineserver started
        // without MSync makes them fail (msync_init: bootstrap_look_up).
        var notes: [String] = []
        applySync(runtime.hasMSync ? .msync : .off, runtime: runtime, prefix: prefix, to: &env, notes: &notes)
        var command = LaunchCommand(executable: runtime.wineBinary, arguments: ["wineboot", mode], environment: env)
        command.notes = notes
        return command
    }

    /// One of Wine's own tools (msiexec, reg) in the prefix, with the sync mode games there use, so it shares their
    /// wineserver. Waits for every process it starts, as installers hand work to child processes.
    public func wineToolCommand(_ arguments: [String], prefix: WinePrefix, runtime: WineRuntime) throws -> LaunchCommand {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        guard prefix.isInitialized() else { throw AlloyError.prefixNotInitialized(name: prefix.name) }
        if let created = prefix.runtimeID, created != runtime.id {
            throw AlloyError.prefixRuntimeMismatch(prefix: prefix.name, created: created, requested: runtime.displayName)
        }
        var env = baseEnvironment(prefix: prefix, runtime: runtime, logLevel: .standard)
        var notes: [String] = []
        applySync(runtime.hasMSync ? .msync : .off, runtime: runtime, prefix: prefix, to: &env, notes: &notes)
        var command = LaunchCommand(executable: runtime.wineBinary, arguments: arguments, environment: env, waitsForChildProcesses: true)
        command.notes = notes
        return command
    }

    /// `wineserver -k` ends every Windows process in that prefix.
    public func stopPrefixCommand(prefix: WinePrefix, runtime: WineRuntime) -> LaunchCommand {
        LaunchCommand(executable: runtime.wineserver, arguments: ["-k"],
                      environment: ["WINEPREFIX": prefix.path.path])
    }

    public func launchCommand(for game: Game, prefix: WinePrefix, runtime: WineRuntime,
                              options: LaunchOptions) throws -> LaunchCommand {
        guard FileManager.default.isExecutableFile(atPath: runtime.wineBinary.path) else {
            throw AlloyError.runtimeUnavailable("\(runtime.wineBinary.path) is missing or not executable.")
        }
        guard prefix.isInitialized() else { throw AlloyError.prefixNotInitialized(name: prefix.name) }
        if let created = prefix.runtimeID, created != runtime.id {
            throw AlloyError.prefixRuntimeMismatch(prefix: prefix.name, created: created, requested: runtime.displayName)
        }
        let info = try ExecutableValidator.validate(game)
        if info.machine == .x86 && runtime.kind == .gamePortingToolkit {
            throw AlloyError.unsupportedExecutableArchitecture("32-bit x86, and this Game Porting Toolkit runtime runs 64-bit programs only")
        }
        if info.machine == .x86 && game.graphics.backend == .d3dMetal {
            throw AlloyError.graphicsBackendUnavailable(backend: GraphicsBackendKind.d3dMetal.displayName,
                                                          reason: "D3DMetal supports 64-bit programs only; this one is 32-bit.")
        }
        try EnvironmentValidator.validate(game.environment)

        let caps = capabilities(of: runtime)
        let g = game.graphics
        if case .unavailable(let reason) = caps.status(of: g.backend) {
            throw AlloyError.graphicsBackendUnavailable(backend: g.backend.displayName, reason: reason)
        }
        if g.backend == .dxvk && !PrefixManager.hasDXVKInstalled(prefix) {
            throw AlloyError.graphicsBackendUnavailable(backend: g.backend.displayName,
                reason: "DXVK DLLs are not installed in \(prefix.name). Install them from the Environments page.")
        }

        var env = baseEnvironment(prefix: prefix, runtime: runtime, logLevel: options.logLevel)
        var overrides: [String] = []
        // DXMT reads its options from one variable, separated by semicolons.
        var dxmtConfig: [String] = []
        switch g.backend {
        case .wined3dOpenGL: env["WINE_D3D_CONFIG"] = "renderer=gl"
        case .wined3dVulkan: env["WINE_D3D_CONFIG"] = "renderer=vulkan"
        case .vkd3d, .d3dMetal: break
        case .dxmt:
            // Info level prints DXMT's device line, which GraphicsVerifier uses as evidence.
            env["DXMT_LOG_LEVEL"] = "info"
            if let cache = g.shaderCachePath, !cache.isEmpty { env["DXMT_SHADER_CACHE_PATH"] = cache }
            // DXMT reads at most MAX_PATH (260) characters of it.
            else if let cache = options.shaderCacheDirectory, cache.path.hasPrefix("/"), cache.path.utf16.count < 250 {
                env["DXMT_SHADER_CACHE_PATH"] = cache.path
            }
        case .dxvk:
            overrides.append("d3d11,d3d10core,dxgi=n,b")
            env["DXVK_LOG_LEVEL"] = "info"
            if let cache = g.shaderCachePath, !cache.isEmpty { env["DXVK_STATE_CACHE_PATH"] = cache }
        }
        if let fps = g.frameRateCap.limit(displayRefreshRate: options.displayRefreshRate) {
            switch g.backend {
            case .dxmt: dxmtConfig.append("d3d11.preferredMaxFrameRate=\(fps)")
            case .dxvk: env["DXVK_FRAME_RATE"] = String(fps)
            // D3DMetal's limiter paces 120 FPS unevenly, so at the display maximum vsync alone limits it.
            case .d3dMetal where g.frameRateCap != .displayMaximum: env["D3DM_MAX_FPS"] = String(fps)
            default: break
            }
        }
        // DXMT presents through a MetalFX spatial scaler: the frame reaches the display at factor × the game's size.
        if let factor = g.metalFXSpatialFactor, MetalFXSpatialUpscaling.validFactors.contains(factor),
           caps.metalFXSpatialUpscaling.contains(g.backend) {
            env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"
            dxmtConfig.append("d3d11.metalSpatialUpscaleFactor=\(MetalFXSpatialUpscaling.configValue(factor))")
        }
        if let frames = g.frameQueue.frames, caps.frameQueue.contains(g.backend) {
            dxmtConfig.append("\(FrameQueue.configKey)=\(frames)")
        }
        if !dxmtConfig.isEmpty { env["DXMT_CONFIG"] = dxmtConfig.joined(separator: ";") }
        if caps.scrollSpeed && game.scrollSpeedPercent != ScrollSpeed.standard && ScrollSpeed.range.contains(game.scrollSpeedPercent) {
            env[ScrollSpeed.variable] = String(game.scrollSpeedPercent)
        }
        if info.machine == .x86 && game.largeAddressSpace && caps.largeAddressSpace { env[LargeAddressSpace.variable] = "1" }
        // Said either way, so the game's ray tracing options follow the switch and not D3DMetal's default for the chip.
        if caps.rayTracing.contains(g.backend) { env[RayTracing.variable] = game.rayTracing ? "1" : "0" }
        if runtime.hasGStreamer { env.merge(VideoPlayback.environment(for: runtime)) { _, new in new } }
        // Shown from the start when the game asks for it; otherwise loaded for the shortcut and hidden as it appears.
        // Loaded for the metrics shortcut, the HUD starts hidden; it starts shown when the game is set to show it.
        if (g.metalHUD || options.loadMetricsHUD) && caps.supportsMetalHUD { env.merge(MetricsHUD.environment(shown: g.metalHUD)) { $1 } }
        // The game then sees an NVIDIA GPU and offers DLSS; the NGX shim runs MetalFX (MetalFXDLSS sets it up).
        if g.dlss && caps.metalFXUpscaling.contains(g.backend), let key = MetalFXDLSS.environmentKey(for: g.backend) { env[key] = "1" }
        // On for every Wine process under Rosetta (baseEnvironment); a game with it turned off doesn't see AVX.
        if !(g.advertiseAVX && caps.supportsAVXAdvertisement) { env[Self.advertiseAVXVariable] = nil }
        // XNA games (Terraria, Stardew Valley…) run on Wine Mono's FNA. Its default SDL_GPU driver uses Vulkan, which
        // on MoltenVK can crash at the first buffer (vkCreateBuffer: external memory); Direct3D 11 goes through the
        // game's Metal graphics instead and starts faster. Other games ignore the variable; a game's own value wins.
        env[FNA.driverKey] = FNA.driver
        // Automatic means MSync where the build has it, as CrossOver enables for new bottles.
        let sync: SyncMode = g.syncMode == .default && caps.syncModes.contains(.msync) ? .msync : g.syncMode
        var notes: [String] = []
        applySync(caps.syncModes.contains(sync) ? sync : .off, runtime: runtime, prefix: prefix, to: &env, notes: &notes)
        if let added = CustomDLLs.overrides(game.customDLLs) { overrides.append(added) }
        for (key, value) in game.environment {
            if key == "WINEDLLOVERRIDES" { overrides.append(value) } else { env[key] = value }
        }
        if !overrides.isEmpty { env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";") }

        var args = [game.executableURL.path] + game.arguments
        if g.forceDX11 && !game.arguments.contains(where: { $0.lowercased() == "-dx11" }) { args.append("-dx11") }
        var command = LaunchCommand(executable: runtime.wineBinary, arguments: args, environment: env,
                                    workingDirectory: game.executableURL.deletingLastPathComponent(), waitsForChildProcesses: true)
        command.notes = notes
        return command
    }

    /// Sets the sync variables for `wanted`, unless the prefix's wineserver already runs with a different MSync
    /// setting: Wine would refuse to start the program then, so it follows the server and says so.
    func applySync(_ wanted: SyncMode, runtime: WineRuntime, prefix: WinePrefix,
                   to env: inout [String: String], notes: inout [String]) {
        var sync = wanted
        if runtime.hasMSync, case .running(let serverMSync) = serverProbe(prefix), serverMSync != (wanted == .msync) {
            sync = serverMSync ? .msync : .off
            notes.append(serverMSync
                ? "MSync stays on for this start: another program in this environment is running with it on, and Wine can't mix the two. Quit it (or stop the environment) for this game's setting to apply."
                : "MSync is off for this start: another program in this environment is running without it, and Wine can't mix the two.")
        }
        if sync == .esync { env["WINEESYNC"] = "1" }
        if sync == .msync { env["WINEMSYNC"] = "1" }
    }
}

/// Wine Mono's FNA (XNA for .NET games): which FNA3D graphics driver it uses.
public enum FNA {
    public static let driverKey = "FNA3D_FORCE_DRIVER"
    public static let driver = "D3D11"
}

/// Scrolling while a game holds the mouse (hidden or confined, as in mouse-look). The engine's Mac driver then scrolls
/// like a Windows mouse (patches/wine/0008): one wheel step per wheel click and per 20 points of trackpad or Magic Mouse
/// swipe, no inertia, no cursor move. The speed scales that (patches/wine/0009): at 200% a click is two steps.
public enum ScrollSpeed {
    public static let variable = "ALLOY_SCROLL_SPEED_PERCENT"
    /// One step per wheel click, like Windows. Right for games where a step is an action, such as switching items.
    public static let standard = 100
    public static let range = 25...800
    /// The speeds the game page offers.
    public static let choices = [50, 75, 100, 150, 200, 300, 400]
    public static func label(_ percent: Int) -> String {
        let value = Double(percent) / 100
        let number = value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
        return number + "×"
    }
    public static let help = "How far a wheel click or a trackpad or Magic Mouse swipe scrolls while the game holds the mouse. At 1× each wheel click is one step, like on Windows, which games use for things like switching items. Raise it if scrolling lists or zooming feels slow."
}

/// A 32-bit Windows program gets 2 GB of address space unless its executable is marked large-address-aware, which many
/// older games aren't although they run out of memory with mods, high-resolution textures or long sessions. Wine then
/// gives every 32-bit program 4 GB, as Proton does by default. Measured on Alloy's engine with a 32-bit program that
/// reserves memory until it can't: 1,920 MB without, 3,968 MB with. 64-bit programs are not affected.
public enum LargeAddressSpace {
    public static let variable = "WINE_LARGE_ADDRESS_AWARE"
    public static let help = "Lets a 32-bit game use up to 4 GB of memory instead of 2 GB, which helps older games that crash or run out of memory with mods or high-resolution textures. 64-bit games already have plenty and aren't affected. Turn it off only if a 32-bit game misbehaves with it."
}

/// Hardware ray tracing for DirectX 12 games. Windows games ask for it through DirectX Raytracing (DXR), which only
/// Apple's D3DMetal translates to Metal's ray tracing; DXMT (DirectX 10 and 11, with DirectX 12 unfinished and without
/// DXR in its unreleased code) and MoltenVK have none. Apple's graphics chips trace rays in hardware from the M3 on.
///
/// Measured on an M4 with D3DMetal 3.0 and a DirectX 12 test program: `D3DM_SUPPORT_DXR=1` (and unset) reports
/// raytracing tier 1.1, feature level 12_2 and shader model 6.6, and bottom- and top-level acceleration structures
/// for 80,000 triangles were built on the GPU in 34 to 58 ms; with `D3DM_SUPPORT_DXR=0` the tier is "not supported".
/// Rays were then traced and every result checked, with shaders built by Microsoft's shader compiler: inline ray queries
/// (DXR 1.1) and a `DispatchRays` pipeline with ray generation, closest hit and miss shaders (DXR 1.0) each gave
/// 40,000 hits and 25,536 misses for 65,536 rays over and around the scene, as it must, and about 600 million rays a
/// second for 4 million simple rays. No game is tested yet.
public enum RayTracing {
    public static let variable = "D3DM_SUPPORT_DXR"
    public static let help = "Lets DirectX 12 games use this Mac's ray tracing hardware through D3DMetal, so the game offers its ray tracing options. Checked with a test program that traced rays both ways games do and got every result right; no game has been tested yet. Ray tracing costs a lot of frame rate: turn it on in the game's own settings, start with the lowest level, and use MetalFX upscaling. Turn this off if a DirectX 12 game crashes or draws wrongly."
    public static let needsD3DMetal = "Ray tracing: this Mac's graphics chip can trace rays, but games ask for it through DirectX 12, which this game's graphics path (DXMT, DirectX 10 and 11) doesn't have. It needs a DirectX 12 game on Apple's D3DMetal, which you add yourself from the Game Porting Toolkit."

    public static let tagHelp = "Ray tracing hardware is on for this game: it is a DirectX 12 game on D3DMetal, which passes ray tracing to this Mac's graphics chip. Turn ray tracing on in the game's own settings. A game without ray tracing options looks the same."

    /// Whether the game is given the Mac's ray tracing hardware, which is when Alloy shows its ray tracing tag: a
    /// DirectX 12 game, on a graphics path that has ray tracing on this Mac, with the game's switch on.
    public static func isOffered(to game: Game, capabilities: BackendCapabilities?, traits: GameTraits?) -> Bool {
        guard game.rayTracing, !game.isApp, let capabilities, let traits else { return false }
        return capabilities.rayTracing.contains(game.graphics.backend) && traits.usage.contains(.d3d12)
    }

    /// "Apple M4 Pro" → true, "Apple M2" → false: hardware ray tracing came with the M3.
    public static func chipHasHardwareRayTracing(brand: String) -> Bool {
        guard let range = brand.range(of: "Apple M") else { return false }
        let digits = brand[range.upperBound...].prefix { $0.isNumber }
        return (Int(digits) ?? 0) >= 3
    }

    public static let thisMacHasHardwareRayTracing: Bool = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return false }
        return chipHasHardwareRayTracing(brand: String(cString: buffer))
    }()
}

/// How many frames a game may prepare ahead of the GPU (DXMT's `dxgi.maxFrameLatency`, patches/dxmt/0001; DXMT 0.80
/// itself lets games queue three). Fewer frames: what the player does reaches the screen sooner. Measured with Alloy's
/// D3D11 test on an M4 MacBook Pro, GPU-heavy frames at about 38.5 fps, from the start of a frame's CPU work to the end
/// of its GPU work: 52.5 ms with one frame, 77.6 ms with two, 104.5 ms with the game's three. One frame costs frame
/// rate when a game keeps both the CPU and the GPU busy: 48.5 fps against 49.4 with two (and with Highball), because the
/// GPU runs the same frames about 1.3% slower with only one waiting. Two frames give the full frame rate.
public enum FrameQueue: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One frame: the lowest input delay, up to about 2% fewer frames.
    case lowInputDelay
    /// Two frames, the default: the full frame rate, a frame less delay than the game's own three.
    case standard
    /// Whatever the game asks for: three frames unless it calls SetMaximumFrameLatency.
    case game

    public var id: String { rawValue }
    public static let configKey = "dxgi.maxFrameLatency"

    /// The value for `configKey`, or nil to leave it to the game.
    public var frames: Int? {
        switch self {
        case .lowInputDelay: return 1
        case .standard: return 2
        case .game: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .lowInputDelay: return "Low input delay (1 frame)"
        case .standard: return "Standard (2 frames)"
        case .game: return "Game's own (usually 3 frames)"
        }
    }

    public static let help = "How many frames the game can prepare before they reach the screen. Standard gives the full frame rate. Low input delay gets your clicks and keys on screen about a frame sooner, for competitive games, but can cost up to 2% of frame rate in games that work both the processor and the graphics chip hard. Game's own adds about a frame of delay."
}
