import Foundation

/// What a Mac needs before Alloy can run games, checked by the installer and the setup wizard.
public enum SystemCheck {
    /// The game engine takes about 1.5 GB once unpacked and its download needs room too; a few game environments
    /// add more.
    public static let requiredFreeBytes: Int64 = 3_000_000_000

    public static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }()

    public static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// Free space for `url`'s volume (or its nearest existing parent folder), counting space macOS can free on demand.
    public static func freeBytes(at url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder.deleteLastPathComponent()
        }
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public static func gigabytes(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }
}

/// The Windows components games most often need, downloaded ahead of time so each game's environment can be set up
/// from disk. Nothing is installed here: a game still gets them in its own environment before its first start.
public enum ComponentDownloads {
    public static func folder(for component: WindowsComponent, in downloads: URL) -> URL {
        downloads.appendingPathComponent(component == .visualCpp ? "vcredist" : "wine-mono")
    }

    public static var approximateMegabytes: Int {
        VisualCppRuntime.Architecture.allCases.map(\.approximateMegabytes).reduce(0, +) + WineMono.approximateMegabytes
    }

    /// Components whose installers are not yet downloaded and verified. Wine Mono counts only when the runtime
    /// names the version it needs.
    public static func missing(for runtime: WineRuntime, in downloads: URL) -> [WindowsComponent] {
        var missing: [WindowsComponent] = []
        let vc = folder(for: .visualCpp, in: downloads)
        if VisualCppRuntime.Architecture.allCases.contains(where: { VisualCppRuntime.verifiedInstaller($0, in: vc) == nil }) {
            missing.append(.visualCpp)
        }
        if let expected = WineMono.expectation(for: runtime),
           WineMono.cachedInstaller(expected, in: folder(for: .dotNet, in: downloads)) == nil {
            missing.append(.dotNet)
        }
        return missing
    }

    /// Downloads every missing installer from its publisher and checks it the same way a game's install does.
    public static func fetch(for runtime: WineRuntime, into downloads: URL,
                             progress: @Sendable (String) -> Void) async throws {
        let vc = folder(for: .visualCpp, in: downloads)
        for arch in VisualCppRuntime.Architecture.allCases where VisualCppRuntime.verifiedInstaller(arch, in: vc) == nil {
            progress("Downloading Visual C++ (\(arch.rawValue)) from Microsoft…")
            do { _ = try await VisualCppRuntime.download(arch, to: vc) } catch let error as AlloyError { throw error } catch {
                throw AlloyError.downloadFailed("Could not download Visual C++ (\(arch.rawValue)): \(error.localizedDescription)")
            }
        }
        let mono = folder(for: .dotNet, in: downloads)
        if let expected = WineMono.expectation(for: runtime), WineMono.cachedInstaller(expected, in: mono) == nil {
            progress("Downloading Wine Mono \(expected.version) from WineHQ…")
            _ = try await WineMono.download(expected, to: mono)
        }
    }
}

/// "Install Everything": checks the Mac, then installs Rosetta 2, the game engine and the Windows components'
/// installers in order. The setup wizard and `alloyctl setup` both run this.
public struct SetupRunner: Sendable {
    public enum Step: String, CaseIterable, Identifiable, Sendable {
        case mac, rosetta, engine, components
        public var id: String { rawValue }
    }

    public enum State: Equatable, Sendable {
        case waiting
        case working(String, fraction: Double?)
        case done(String)
        case failed(String)
        case skipped(String)

        public var isFinished: Bool {
            switch self { case .done, .skipped: true; default: false }
        }
    }

    public var backend: WineBackend
    public var runtimesDirectory: URL
    /// Alloy's Downloads folder: runtimes/, vcredist/ and wine-mono/ inside it.
    public var downloads: URL
    public var componentsURL: URL?
    /// True only after the person agreed to Apple's licence for Rosetta 2.
    public var installRosetta: Bool

    public init(backend: WineBackend, runtimesDirectory: URL, downloads: URL, componentsURL: URL?, installRosetta: Bool) {
        self.backend = backend
        self.runtimesDirectory = runtimesDirectory
        self.downloads = downloads
        self.componentsURL = componentsURL
        self.installRosetta = installRosetta
    }

    /// A runtime that plays DirectX 10/11 games through Metal, if one is installed.
    public func gameEngine() -> WineRuntime? {
        backend.discoverRuntimes().first { backend.capabilities(of: $0).status(of: .dxmt).isUsable }
    }

    /// What can be told without downloading anything, for the wizard's first look.
    public func currentStates() -> [Step: State] {
        var states: [Step: State] = [.mac: checkMac(),
                                     .rosetta: !SystemCheck.isAppleSilicon ? .done("Not needed on Intel Macs")
                                         : Rosetta.isInstalled() ? .done("Installed") : .waiting]
        if let engine = gameEngine() {
            states[.engine] = .done("Installed: \(engine.displayName)")
            states[.components] = ComponentDownloads.missing(for: engine, in: downloads).isEmpty ? .done("Downloaded and checked") : .waiting
        } else {
            states[.engine] = .waiting
            states[.components] = .waiting
        }
        return states
    }

    func checkMac() -> State {
        let free = SystemCheck.freeBytes(at: runtimesDirectory)
        if let free, free < SystemCheck.requiredFreeBytes {
            return .failed("Only \(SystemCheck.gigabytes(free)) free. Alloy needs about \(SystemCheck.gigabytes(SystemCheck.requiredFreeBytes)): free up some space, then try again.")
        }
        return .done("\(SystemCheck.isAppleSilicon ? "Apple silicon" : "Intel"), \(SystemCheck.macOSVersion)" + (free.map { ", \(SystemCheck.gigabytes($0)) free" } ?? ""))
    }

    /// Runs every step. A failed step does not stop the later ones unless they depend on it; the Mac check does.
    public func run(update send: @escaping @Sendable (Step, State) async -> Void) async {
        let reporter = Reporter(send: send)
        let update: @Sendable (Step, State) async -> Void = { await reporter.report($0, $1) }
        let mac = checkMac()
        await update(.mac, mac)
        guard case .done = mac else {
            for step in Step.allCases where step != .mac { await update(step, .skipped("Needs a supported Mac.")) }
            return
        }

        if !SystemCheck.isAppleSilicon {
            await update(.rosetta, .done("Not needed on Intel Macs"))
        } else if Rosetta.isInstalled() {
            await update(.rosetta, .done("Installed"))
        } else if installRosetta {
            await update(.rosetta, .working("Installing Rosetta 2 from Apple…", fraction: nil))
            do { try Rosetta.install(); await update(.rosetta, .done("Installed")) }
            catch { await update(.rosetta, .failed(Self.message(error))) }
        } else {
            await update(.rosetta, .failed("Not installed. The game engine needs it."))
        }

        await update(.engine, await installEngine(update: update))

        guard let engine = gameEngine() else {
            await update(.components, .skipped("Needs the game engine."))
            return
        }
        await update(.components, .working("Checking…", fraction: nil))
        do {
            try await ComponentDownloads.fetch(for: engine, into: downloads) { status in
                Task { await update(.components, .working(status, fraction: nil)) }
            }
            await update(.components, .done("Visual C++ and .NET support are ready for your games"))
        } catch {
            await update(.components, .failed(Self.message(error)))
        }
    }

    func installEngine(update: @escaping @Sendable (Step, State) async -> Void) async -> State {
        let installed = gameEngine()
        guard let componentsURL else {
            return installed.map { .done("Installed: \($0.displayName)") }
                ?? .failed("This copy of Alloy has no download address for the game engine. Use Install from Package File… in Setup.")
        }
        await update(.engine, .working("Checking for the latest game engine…", fraction: nil))
        let package: RuntimePackage
        do {
            guard let first = try await RuntimeInstaller.fetchManifest(from: componentsURL).runtimes.first else {
                return installed.map { .done("Installed: \($0.displayName)") } ?? .failed("The download list has no game engine in it.")
            }
            package = first
        } catch {
            return installed.map { .done("Installed: \($0.displayName). Could not check for updates.") } ?? .failed(Self.message(error))
        }
        if RuntimeInstaller.installedMarkers(in: runtimesDirectory)[package.id] != nil {
            return .done("Installed: \(package.name)")
        }
        do {
            _ = try await RuntimeInstaller.install(package, into: runtimesDirectory, downloads: downloads.appendingPathComponent("runtimes")) { fraction, status in
                Task { await update(.engine, .working(status, fraction: fraction)) }
            }
            return .done("Installed: \(package.name)")
        } catch {
            return .failed(Self.message(error))
        }
    }

    static func message(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }

    /// Progress arrives from download callbacks on other tasks; once a step has finished, late progress for it is dropped.
    private actor Reporter {
        let send: @Sendable (Step, State) async -> Void
        var finished: Set<Step> = []

        init(send: @escaping @Sendable (Step, State) async -> Void) { self.send = send }

        func report(_ step: Step, _ state: State) async {
            switch state {
            case .working, .waiting: if finished.contains(step) { return }
            case .done, .failed, .skipped: finished.insert(step)
            }
            await send(step, state)
        }
    }
}
