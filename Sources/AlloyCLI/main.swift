import Foundation
import AlloyCore

/// Command-line front end over AlloyCore for scripted setup and reproducible benchmark runs.
/// Uses the same storage as the app. Runs only what it is explicitly told to run.
let usage = """
usage:
  alloyctl runtimes
  alloyctl prefixes
  alloyctl import-d3dmetal <toolkit-volume> <base-runtime-path>
  alloyctl import-dxmt <dxmt-release-folder> <base-runtime-path> [source-note]
  alloyctl import-wine <wine-install-root> <name> [source-note]
  alloyctl prefix-create <name> <runtime-path>
  alloyctl prefix-init <prefix-id>
  alloyctl prefix-trash <prefix-id>
  alloyctl runtime-trash <runtime-path>
  alloyctl superposition-result <log-file>
  alloyctl write-docs <folder>
  alloyctl update <path to Alloy.app> [--check]
  alloyctl installer-pages <folder>
  alloyctl setup [components.json URL] [--install-rosetta]
  alloyctl install-steam <prefix-id>
  alloyctl install-store <\(GameStore.allCases.map(\.rawValue).joined(separator: "|"))> <prefix-id>
  alloyctl check-stores
  alloyctl store-games <prefix-id>
  alloyctl install-vcruntime <prefix-id>
  alloyctl install-dotnet <prefix-id>
  alloyctl components <prefix-id> <exe-path>
  alloyctl install-runtime <components.json URL> [package-id]
  alloyctl install-game <prefix-id> <setup.exe|setup.msi> <name>
  alloyctl run <prefix-id> <exe-path> [--graphics <backend>] [--hud | --metrics-hidden] [--no-avx] [--sync default|off|esync|msync] [--dlss] [--metalfx <factor>] [--dx11] [--queued-frames-default] [--scroll-speed <percent>] [--no-large-address] [--runtime <wine-binary>] [--fps-cap display|off|<n>] [--shader-cache <game-id>] [--timeout <s>] [--env K=V]... [-- <args>...]
graphics backends: \(GraphicsBackendKind.allCases.map(\.rawValue).joined(separator: ", "))
"""

try? DataMigration.migrateIfNeeded()
DataMigration.renameEngines()
let support = AppSettings.supportDirectory
let backend = WineBackend(managedRuntimesDirectory: support.appendingPathComponent("Runtimes"))
let prefixes = PrefixManager(storageRoot: AppSettings().prefixStorageLocation)
let launcher = GameLauncher(logsDirectory: support.appendingPathComponent("Logs"))

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func runtime(for prefix: WinePrefix) -> WineRuntime {
    let all = backend.discoverRuntimes()
    guard let r = all.first(where: { $0.id == prefix.runtimeID }) ?? (prefix.runtimeID == nil ? all.first : nil) else {
        fail("Runtime \(prefix.runtimeID ?? "-") for \(prefix.name) is not installed.")
    }
    return r
}

func stream(_ session: LaunchSession, timeout: TimeInterval, prefix: WinePrefix) -> LaunchState {
    let earlier = session.onLine
    session.onLine = { line in earlier?(line); print(line.text) }
    FreezeCapture.watch(session)
    let state = session.waitUntilExit(timeout: timeout)
    if state.isRunning {
        print("[alloy] timeout after \(Int(timeout))s, stopping")
        session.stop()
        // Stopping wine alone can leave the prefix's services (winedevice, rpcss…) running.
        let kill = LaunchSession(command: backend.stopPrefixCommand(prefix: prefix, runtime: runtime(for: prefix)), logFile: nil)
        try? kill.start()
        _ = kill.waitUntilExit(timeout: 15)
        return session.waitUntilExit(timeout: 15)
    }
    return state
}

/// Prints setup progress: every status change, but a download's progress only every 10 %.
actor SetupPrinter {
    var failed = false
    var lastLine = ""
    var lastTenth: [SetupRunner.Step: Int] = [:]

    func show(_ step: SetupRunner.Step, _ state: SetupRunner.State) {
        var line: String
        switch state {
        case .waiting: return
        case .working(let status, let fraction):
            if let fraction {
                let tenth = Int(fraction * 10)
                guard tenth != lastTenth[step] else { return }
                lastTenth[step] = tenth
            }
            line = status
        case .done(let text): line = "done. " + text
        case .skipped(let text): line = "skipped. " + text
        case .failed(let text): failed = true; line = "FAILED. " + text
        }
        line = "[alloy] \(step.rawValue): " + line
        if line != lastLine { print(line); lastLine = line }
    }
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }
args.removeFirst()

// Errors end the command with their message instead of a crash report.
do {
    switch command {
    case "superposition-result":
        // Reads a Superposition score from any captured log, such as one from another Wine launcher.
        guard args.count == 1, let text = try? String(contentsOfFile: args[0], encoding: .utf8) else { fail(usage) }
        guard let sp = SuperpositionResult.parse(log: text) else { fail("No Superposition result in \(args[0])") }
        print(String(format: "min %.1f  avg %.1f  max %.1f  (%d scenes)", sp.minFPS, sp.averageFPS, sp.maxFPS, sp.sceneAverages.count))

    case "write-docs":
        // The terms and graphics guide as Markdown for the website, from the same text the app shows.
        guard args.count == 1 else { fail(usage) }
        let folder = URL(fileURLWithPath: args[0], isDirectory: true)
        for (name, text) in [("TERMS.md", Terms.markdown), ("GRAPHICS-GUIDE.md", GraphicsGuide.markdown),
                             ("THIRD-PARTY-NOTICES.md", OpenSourceNotices.markdown)] {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            print("[alloy] Wrote \(folder.appendingPathComponent(name).path)")
        }

    case "update":
        // The same check and install as Alloy ▸ Check for Updates, for an Alloy.app that isn't running.
        guard args.count >= 1, args[0].hasSuffix(".app") else { fail(usage) }
        let app = URL(fileURLWithPath: args[0])
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let current = info["CFBundleShortVersionString"] as? String else { fail("\(app.path) isn't an Alloy app") }
        let feed = AppUpdate.feedURL()
        print("[alloy] Installed: \(current). Checking \(feed.absoluteString)")
        switch try await AppUpdate.check(currentVersion: current, feed: feed) {
        case .upToDate(let latest): print("[alloy] Up to date (latest is \(latest))")
        case .needsNewerMacOS(let r): print("[alloy] \(r.version) needs macOS \(r.minimumSystemVersion ?? "?") or later")
        case .available(let release):
            print("[alloy] \(release.version) is available")
            guard !args.contains("--check") else { break }
            guard AppUpdate.canReplace(app) else { fail("Can't write to \(app.deletingLastPathComponent().path)") }
            let new = try await AppUpdate.download(release, currentVersion: current) { _ in }
            let old = try AppUpdate.install(new, replacing: app)
            print("[alloy] Installed \(release.version) at \(app.path); the old copy is in the Trash\(old.map { " (\($0.lastPathComponent))" } ?? "")")
        }

    case "installer-pages":
        // welcome.html, license.html and conclusion.html for scripts/make-installer.sh, and the terms version it records.
        guard args.count == 1 else { fail(usage) }
        let folder = URL(fileURLWithPath: args[0], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in [("welcome.html", InstallerPages.welcome), ("license.html", InstallerPages.license),
                             ("conclusion.html", InstallerPages.conclusion), ("terms-version", "\(Terms.version)\n")] {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        print("[alloy] Wrote installer pages to \(folder.path)")

    case "setup":
        // What the app's "Install Everything" does: check the Mac, Rosetta 2 (only with --install-rosetta, which
        // accepts Apple's licence), the game engine from the components list, and the Windows components' installers.
        let rosetta = args.contains("--install-rosetta")
        let url = args.first { !$0.hasPrefix("--") }.flatMap { URL(string: $0) } ?? AppSettings().componentsURL
        let runner = SetupRunner(backend: backend, runtimesDirectory: support.appendingPathComponent("Runtimes"),
                                 downloads: support.appendingPathComponent("Downloads"), componentsURL: url, installRosetta: rosetta)
        let printer = SetupPrinter()
        await runner.run { await printer.show($0, $1) }
        exit(await printer.failed ? 1 : 0)

    case "runtimes":
        for r in backend.discoverRuntimes() {
            let caps = backend.capabilities(of: r)
            let usable = GraphicsBackendKind.allCases.filter { caps.status(of: $0).isUsable }.map(\.rawValue)
            let steam = SteamInstaller.missingRequirements(in: r).isEmpty ? "ready" : "incomplete"
            print("\(r.displayName)\n  path: \(r.wineBinary.path)\n  archs: \(r.architectures.map(\.rawValue)) graphics: \(usable)")
            print("  GnuTLS: \(r.hasGnuTLS ? "yes" : "no")  Steam web helper fix: \(r.hasSteamWebHelperFix ? "yes" : "no")  Steam: \(steam)  Video (GStreamer): \(r.hasGStreamer ? "yes" : "no")  Low input delay: \(r.hasFrameLatencyOption ? "yes" : "no")  Scroll speed: \(r.hasScrollSpeedOption ? "yes" : "no")  32-bit 4 GB: \(r.hasLargeAddressOption ? "yes" : "no")")
        }

    case "prefixes":
        for p in prefixes.allPrefixes {
            print("\(p.id.uuidString)  \(p.name)  [\(p.origin.rawValue)\(p.isInitialized() ? ", initialised" : "")]  runtime: \(p.runtimeID ?? "-")")
        }

    case "import-d3dmetal":
        guard args.count == 2 else { fail(usage) }
        guard let redist = D3DMetalImporter.locate(in: URL(fileURLWithPath: args[0])) else { fail("No D3DMetal redistributable found in \(args[0])") }
        guard let base = backend.discoverRuntimes().first(where: { $0.id == args[1] && D3DMetalImporter.isLayerableBase($0) }) else {
            fail("Unknown base runtime path: \(args[1])")
        }
        let built = try D3DMetalImporter.makeManagedRuntime(name: "D3DMetal \(redist.version ?? "")".trimmingCharacters(in: .whitespaces),
                                                            base: base, redist: redist, runtimesDirectory: support.appendingPathComponent("Runtimes"))
        print(built.path)

    case "import-wine":
        guard args.count >= 2 else { fail(usage) }
        let built = try WineBuildImporter.importBuild(root: URL(fileURLWithPath: args[0]), name: args[1],
                                                      source: args.count > 2 ? args[2] : args[0],
                                                      runtimesDirectory: support.appendingPathComponent("Runtimes"))
        print(built.path)

    case "import-dxmt":
        guard args.count >= 2 else { fail(usage) }
        guard let release = DXMTImporter.locate(in: URL(fileURLWithPath: args[0])) else { fail("No DXMT release found in \(args[0])") }
        guard let base = backend.discoverRuntimes().first(where: { $0.id == args[1] }) else { fail("Unknown base runtime path: \(args[1])") }
        let built = try DXMTImporter.makeManagedRuntime(name: "DXMT \(release.version ?? "")".trimmingCharacters(in: .whitespaces),
                                                        base: base, release: release, source: args.count > 2 ? args[2] : release.root.path,
                                                        runtimesDirectory: support.appendingPathComponent("Runtimes"))
        print(built.path)

    case "prefix-trash":
        guard args.count == 1, let id = UUID(uuidString: args[0]) else { fail(usage) }
        try prefixes.trashPrefix(id: id)
        print("Moved environment to the Trash")

    case "runtime-trash":
        guard args.count == 1, let r = backend.discoverRuntimes().first(where: { $0.id == args[0] }) else { fail("Unknown runtime path") }
        try backend.trashManagedRuntime(r, usedBy: prefixes.ownPrefixes)
        print("Moved \(r.displayName) to the Trash")

    case "prefix-create":
        guard args.count == 2 else { fail(usage) }
        guard backend.discoverRuntimes().contains(where: { $0.id == args[1] }) else { fail("Unknown runtime path: \(args[1])") }
        let p = try prefixes.createPrefix(name: args[0], runtimeID: args[1])
        print(p.id.uuidString)

    case "prefix-init":
        guard let id = args.first.flatMap(UUID.init(uuidString:)), let p = prefixes.prefix(id: id) else { fail(usage) }
        let session = try launcher.launch(gameID: p.id, gameName: "prefix-\(p.name)",
                                          command: try backend.initializePrefixCommand(prefix: p, runtime: runtime(for: p)))
        let state = stream(session, timeout: 600, prefix: p)
        print("[alloy] \(state.summary)")
        exit(state == .exited(code: 0) ? 0 : 1)

    case "install-runtime":
        // Downloads a game engine package listed in a components manifest, checks it and unpacks it into Runtimes.
        guard let manifestURL = args.first.flatMap({ URL(string: $0) }) else { fail(usage) }
        let manifest = try await RuntimeInstaller.fetchManifest(from: manifestURL)
        guard let package = args.count > 1 ? manifest.runtimes.first(where: { $0.id == args[1] }) : manifest.runtimes.first else {
            fail("No such package in \(manifestURL.absoluteString).")
        }
        let folder = try await RuntimeInstaller.install(package, into: support.appendingPathComponent("Runtimes"),
                                                        downloads: support.appendingPathComponent("Downloads/runtimes")) { fraction, status in
            print("[alloy] \(Int(fraction * 100))% \(status)")
        }
        print("[alloy] Installed \(package.name) in \(LogRedactor.redact(folder.path))")

    case "components":
        // What a game needs, from its files only (nothing is run), and what the environment already has.
        guard args.count >= 2, let id = UUID(uuidString: args[0]), let p = prefixes.prefix(id: id) else { fail(usage) }
        let exe = URL(fileURLWithPath: args[1])
        let traits = GameTraits.inspect(Game(name: exe.lastPathComponent, folder: exe.deletingLastPathComponent(),
                                             executableRelativePath: exe.lastPathComponent))
        print("[alloy] DirectX: \(traits.usage)  machine: \(traits.machine.rawValue)  unreal: \(traits.isUnreal)  dlss: \(traits.dlss)")
        print("[alloy] Visual C++: ships installer \(traits.shipsVisualCppInstaller), imports \(traits.importsVisualCpp)  .NET: \(traits.isDotNet)")
        for c in WindowsComponent.allCases {
            print("[alloy] \(c.displayName): needed \(WindowsComponent.needed(by: traits).contains(c)), installed in \(p.name) \(c.isInstalled(in: p))")
        }
        if let mono = WineMono.expectation(for: runtime(for: p)) {
            print("[alloy] Wine Mono for this runtime: \(mono.fileName) (\(mono.checksums.count) pinned checksum(s)) from \(mono.downloadURL.absoluteString)")
        }

    case "install-dotnet":
        guard let id = args.first.flatMap(UUID.init(uuidString:)), let p = prefixes.prefix(id: id), !p.isReadOnly else { fail(usage) }
        try await WineMono.install(into: p, runtime: runtime(for: p), backend: backend,
                                   downloads: support.appendingPathComponent("Downloads/wine-mono")) { print("[alloy] \($0)") }
        print("[alloy] .NET support (Wine Mono) installed in \(p.name)")

    case "install-game":
        // Runs a setup program the user named in the given environment, then reports the game it installed.
        guard args.count >= 3, let id = UUID(uuidString: args[0]), let p = prefixes.prefix(id: id), !p.isReadOnly else { fail(usage) }
        let setup = URL(fileURLWithPath: args[1])
        let r = runtime(for: p)
        let before = GameInstaller.executables(in: p)
        let session = try launcher.launch(gameID: p.id, gameName: "setup-\(args[2])",
                                          command: try GameInstaller.setupCommand(installer: setup, prefix: p, runtime: r, backend: backend))
        let state = stream(session, timeout: 3600, prefix: p)
        let added = GameInstaller.executables(in: p).subtracting(before)
        print("[alloy] Setup \(state.summary.lowercased()); \(added.count) new program(s)")
        guard let game = GameInstaller.installedGame(name: args[2], newExecutables: added, prefix: p) else {
            fail("The setup added no program Alloy can start.")
        }
        print("[alloy] Game: \(LogRedactor.redact(game.executableURL.path))")

    case "install-steam", "install-store":
        // Downloads the store's official installer and runs it in the given environment; the user asked for this.
        let storeArgs = command == "install-steam" ? ["steam"] + args : args
        guard storeArgs.count == 2, let store = GameStore(rawValue: storeArgs[0]),
              let id = UUID(uuidString: storeArgs[1]), let p = prefixes.prefix(id: id), !p.isReadOnly else { fail(usage) }
        let r = runtime(for: p)
        var graphics = GraphicsConfiguration(backend: r.hasDXMT ? .dxmt : r.hasD3DMetal ? .d3dMetal : .wined3dOpenGL)
        graphics.dlss = backend.capabilities(of: r).metalFXUpscaling.contains(graphics.backend)
        let entry = try await StoreInstaller.install(store, into: p, runtime: r, backend: backend, graphics: graphics,
                                                     installer: support.appendingPathComponent("Downloads/\(store.installerFileName)")) { print("[alloy] \($0)") }
        // Same library the app uses; restart the app afterwards so it reads the new entry.
        let settings = JSONFileStore(fileURL: support.appendingPathComponent("settings.json")).load(default: AppSettings())
        let library = GameLibrary(fileURL: settings.libraryLocation)
        try library.add(entry)
        print("[alloy] \(store.displayName) installed: \(entry.executableURL.path); added to the library")

    case "check-stores":
        // Asks each store's sign-in server for an answer from macOS; nothing is downloaded or run.
        for store in GameStore.allCases {
            let status = await StoreConnectivity.check(store)
            print("\(store.displayName): \(status)")
            if let why = StoreConnectivity.explanation(status, store: store) { print("  \(why)") }
        }

    case "store-games":
        guard let id = args.first.flatMap(UUID.init(uuidString:)), let p = prefixes.prefix(id: id) else { fail(usage) }
        for store in GameStore.allCases {
            for found in StoreLibraryScanner.installedGames(of: store, in: p) { print("\(store.displayName)\t\(found.name)\t\(found.launchArgument)") }
        }

    case "install-vcruntime":
        // Microsoft's Visual C++ 2015–2022 runtime (x64 and x86), downloaded from Microsoft; the user asked for this.
        guard let id = args.first.flatMap(UUID.init(uuidString:)), let p = prefixes.prefix(id: id), !p.isReadOnly else { fail(usage) }
        let versions = try await VisualCppRuntime.install(into: p, runtime: runtime(for: p), backend: backend,
                                                          downloads: support.appendingPathComponent("Downloads/vcredist")) { print("[alloy] \($0)") }
        for (arch, version) in versions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("[alloy] Visual C++ \(arch.rawValue): \(version)")
        }

    case "run":
        guard args.count >= 2, let id = UUID(uuidString: args[0]), let p = prefixes.prefix(id: id) else { fail(usage) }
        let exe = URL(fileURLWithPath: args[1]).standardizedFileURL
        var graphics = GraphicsConfiguration()
        var env: [String: String] = [:]
        var timeout: TimeInterval = 900
        var metricsHidden = false
        var shaderCacheID: UUID?
        var runtimeOverride: URL?
        var scrollSpeed = ScrollSpeed.standard
        var largeAddressSpace = true
        var programArgs: [String] = []
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--graphics":
                i += 1
                guard i < args.count, let kind = GraphicsBackendKind(rawValue: args[i]) else { fail(usage) }
                graphics.backend = kind
            case "--hud": graphics.metalHUD = true
            case "--metrics-hidden": metricsHidden = true
            case "--dlss": graphics.dlss = true
            case "--metalfx":
                i += 1
                guard i < args.count, let factor = Double(args[i]), MetalFXSpatialUpscaling.validFactors.contains(factor) else { fail(usage) }
                graphics.metalFXSpatialFactor = factor
            case "--dx11": graphics.forceDX11 = true
            case "--runtime":
                // Testing: run the environment on another engine (its wine binary) without changing the environment.
                i += 1
                guard i < args.count, FileManager.default.isExecutableFile(atPath: args[i]) else { fail(usage) }
                runtimeOverride = URL(fileURLWithPath: args[i])
            case "--queued-frames-default": graphics.lowInputDelay = false
            case "--scroll-speed":
                i += 1
                guard i < args.count, let percent = Int(args[i]), ScrollSpeed.range.contains(percent) else { fail(usage) }
                scrollSpeed = percent
            case "--no-avx": graphics.advertiseAVX = false
            case "--no-large-address": largeAddressSpace = false
            case "--sync":
                i += 1
                guard i < args.count, let mode = SyncMode(rawValue: args[i]) else { fail(usage) }
                graphics.syncMode = mode
            case "--fps-cap":
                i += 1
                guard i < args.count else { fail(usage) }
                switch args[i] {
                case "display": graphics.frameRateCap = .displayMaximum
                case "off": graphics.frameRateCap = .off
                default:
                    guard let fps = Int(args[i]), fps > 0 else { fail(usage) }
                    graphics.frameRateCap = .fixed(fps)
                }
            case "--timeout":
                i += 1
                guard i < args.count, let t = TimeInterval(args[i]) else { fail(usage) }
                timeout = t
            case "--shader-cache":
                i += 1
                guard i < args.count, let id = UUID(uuidString: args[i]) else { fail(usage) }
                shaderCacheID = id
            case "--env":
                i += 1
                guard i < args.count, let eq = args[i].firstIndex(of: "=") else { fail(usage) }
                env[String(args[i][..<eq])] = String(args[i][args[i].index(after: eq)...])
            case "--":
                programArgs = Array(args[(i + 1)...]); i = args.count
            default: fail("Unknown option \(args[i])\n\(usage)")
            }
            i += 1
        }
        var game = Game(id: shaderCacheID ?? UUID(), name: exe.deletingPathExtension().lastPathComponent, folder: exe.deletingLastPathComponent(),
                        executableRelativePath: exe.lastPathComponent, prefixID: p.id, arguments: programArgs,
                        environment: env, graphics: graphics)
        game.scrollSpeedPercent = scrollSpeed
        game.largeAddressSpace = largeAddressSpace
        let r = runtimeOverride.map { backend.makeRuntime(kind: .custom, binary: $0, root: $0.deletingLastPathComponent().deletingLastPathComponent()) }
            ?? runtime(for: p)
        if graphics.metalFXSpatialFactor != nil && !backend.capabilities(of: r).metalFXSpatialUpscaling.contains(graphics.backend) {
            fail("MetalFX upscaling is not available for \(graphics.backend.displayName) in \(r.displayName).")
        }
        // With --shader-cache <id>, shaders are kept as the app keeps them for the game with that ID.
        let shaders = shaderCacheID != nil && graphics.backend == .dxmt ? ShaderCache.prepare(for: game, supportDirectory: support) : nil
        let cmd = try backend.launchCommand(for: game, prefix: p, runtime: r,
                                            options: LaunchOptions(loadMetricsHUD: metricsHidden, shaderCacheDirectory: shaders))
        if graphics.dlss {
            guard backend.capabilities(of: r).metalFXUpscaling.contains(graphics.backend) else {
                fail("DLSS → MetalFX is not available for \(graphics.backend.displayName) in \(r.displayName).")
            }
            let managed = r.root.standardizedFileURL.path.hasPrefix(support.appendingPathComponent("Runtimes").standardizedFileURL.path + "/")
            try MetalFXDLSS.installShims(from: r, into: p, runtimeIsManaged: managed)
            if !MetalFXDLSS.hasRegistryPath(p) {
                let reg = LaunchSession(command: MetalFXDLSS.registryCommand(like: cmd), logFile: nil)
                try reg.start()
                print("[alloy] DLSS → MetalFX registry entry: \(reg.waitUntilExit(timeout: 60).summary)")
            }
        }
        if VideoPlayback.needsSetup(prefix: p, runtime: r) {
            try VideoPlayback.prepare(prefix: p, runtime: r, like: cmd)
            print("[alloy] Video playback (winegstreamer) added to \(p.name)")
        }
        if !p.isReadOnly && !CrashDialog.isOff(in: p) {
            let reg = LaunchSession(command: CrashDialog.turnOffCommand(like: cmd), logFile: nil)
            try reg.start()
            print("[alloy] Crash window turned off in \(p.name) (crashes go to the log): \(reg.waitUntilExit(timeout: 30).summary)")
        }
        let start = Date()
        let session = try launcher.launch(gameID: game.id, gameName: game.name, command: cmd)
        let state = stream(session, timeout: timeout, prefix: p)
        print("[alloy] \(state.summary) after \(Int(Date().timeIntervalSince(start)))s; log: \(session.logFile?.path ?? "-")")
        if let sp = SuperpositionResult.parse(log: session.fullLog) {
            print(String(format: "[alloy] Superposition FPS: min %.1f  avg %.1f  max %.1f  (%d scenes)",
                         sp.minFPS, sp.averageFPS, sp.maxFPS, sp.sceneAverages.count))
        }
        for f in DiagnosticService.analyze(log: session.fullLog, exitState: state, requestedGraphics: graphics.backend) {
            print("[alloy] [\(f.severity.rawValue)] \(f.title)")
        }

    default:
        fail(usage)
    }
} catch {
    fail("error: " + error.localizedDescription)
}
