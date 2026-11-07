import AppKit
import Foundation
import UniformTypeIdentifiers
import AlloyCore

/// The simple app has three places: games, the one-click setup, and everything else under Advanced.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case library, setup, advanced, flake
    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: return "Games"
        case .setup: return "Setup"
        case .advanced: return "Advanced"
        case .flake: return "Flake"
        }
    }
    var symbol: String {
        switch self {
        case .library: return "square.grid.2x2.fill"
        case .setup: return "arrow.down.circle.fill"
        case .advanced: return "slider.horizontal.3"
        case .flake: return ""
        }
    }
}

enum AdvancedTab: String, CaseIterable, Identifiable, Hashable {
    case environments, diagnostics, performance, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .environments: return "Environments"
        case .diagnostics: return "Diagnostics"
        case .performance: return "Performance"
        case .settings: return "Settings"
        }
    }
}

/// A launch waiting for the user to confirm the executable.
struct PendingLaunch: Identifiable {
    let id = UUID()
    let game: Game
    let command: LaunchCommand
    let info: PEInfo
    let runtime: WineRuntime
    let prefix: WinePrefix
}

/// The setup wizard's pages, in order.
enum WizardPage: Int, CaseIterable {
    case welcome, terms, install, done

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .terms: "Terms"
        case .install: "Install"
        case .done: "Ready"
        }
    }
}

enum AppSheet: Identifiable, Equatable {
    /// Terms of use, from Settings.
    case terms
    case guide
    /// Open-source licences of the engine and what Alloy downloads.
    case licences
    /// First launch starts at the welcome page; Setup and launches with something missing start at Install.
    /// Shown over the window rather than as a sheet (see `WizardOverlay`).
    case wizard(WizardPage)
    /// Install a game through Steam or Epic from its store link.
    case storeGame

    var isWizard: Bool { if case .wizard = self { true } else { false } }

    var id: String {
        switch self {
        case .terms: "terms"
        case .guide: "guide"
        case .licences: "licences"
        case .wizard(let page): "wizard-\(page.rawValue)"
        case .storeGame: "store-game"
        }
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published private(set) var games: [Game] = []
    @Published private(set) var runtimes: [WineRuntime] = []
    @Published private(set) var prefixes: [WinePrefix] = []
    @Published var selection: SidebarItem? = .library
    @Published var advancedTab: AdvancedTab = .environments
    @Published var selectedGameID: UUID?
    @Published private(set) var states: [UUID: LaunchState] = [:]
    @Published private(set) var logs: [UUID: [LogLine]] = [:]
    @Published private(set) var findings: [UUID: [DiagnosticFinding]] = [:]
    @Published private(set) var benchmarks: [UUID: [BenchmarkRun]] = [:]
    @Published var pendingLaunch: PendingLaunch?
    @Published var alert: AlertItem?

    private let settingsStore: JSONFileStore<AppSettings>
    private var library: GameLibrary
    private(set) var prefixManager: PrefixManager
    private let benchmarkStore: BenchmarkStore
    let launcher: GameLauncher
    private var sessions: [UUID: LaunchSession] = [:]
    private var refreshTimer: Timer?

    var logsDirectory: URL { AppSettings.supportDirectory.appendingPathComponent("Logs") }
    var runtimesDirectory: URL { AppSettings.supportDirectory.appendingPathComponent("Runtimes") }
    @Published var importingD3DMetal = false
    /// Progress text per game store while its app is being installed.
    @Published var storeInstallStatus: [GameStore: String] = [:]
    /// Games Steam or Epic is downloading, read from the stores' files every few seconds while a store app runs.
    @Published private(set) var storeDownloads: [StoreDownload] = []
    private var storePollTick = 0
    /// Whether this network lets each store's app sign in; nil until checked.
    @Published private(set) var storeConnectivity: [GameStore: StoreConnectivity.Status] = [:]
    @Published private(set) var checkingStores = false
    /// ⌥⌘M while a game runs, registered only then so it never takes the keys from other apps for long.
    private let metricsHotKey = MetricsHotKey()
    @Published var rosettaInstalled = Rosetta.isInstalled()
    /// The sheet over the main window: terms, graphics guide or setup wizard.
    @Published var sheet: AppSheet?
    /// What the setup wizard shows per step.
    @Published var setupStates: [SetupRunner.Step: SetupRunner.State] = [:]
    @Published private(set) var runningSetup = false
    /// Set at launch: once runtimes are found, offer the setup wizard if Rosetta or the engine is missing.
    private var offerSetupAfterDiscovery = false
    @Published var installingRosetta = false
    /// Progress text per environment while Windows components (Visual C++, .NET) are being installed.
    @Published var componentStatus: [UUID: String] = [:]
    /// Games being prepared for their start (components installing); Play waits for them.
    @Published private(set) var preparing: Set<UUID> = []
    /// Low Power Mode or heat slowing the Mac, explained; checked every few seconds.
    @Published private(set) var macConditions: String? = MacConditions.current
    /// Box art found for each game, looked up once per game and artwork setting.
    private var covers: [UUID: (key: String, images: CoverArt.Images)] = [:]

    func cover(for game: Game) -> CoverArt.Images {
        let key = "\(game.artwork?.path ?? "")|\(game.arguments.joined(separator: " "))|\(game.prefixID?.uuidString ?? "")"
        if let cached = covers[game.id], cached.key == key { return cached.images }
        let images = CoverArt.images(for: game, prefix: prefix(game.prefixID))
        covers[game.id] = (key, images)
        return images
    }
    /// What each opened game needs, from its files (scanned off the main thread).
    @Published var traits: [UUID: GameTraits] = [:]
    /// Each game's scan, kept until its program changes, so games aren't rescanned on every visit or start.
    let scans = GameScanCache(url: AppSettings.supportDirectory.appendingPathComponent("game-scans.json"))
    /// Anti-cheat found in each game's folder, read with its traits.
    @Published var antiCheat: [UUID: [String]] = [:]

    /// A runtime with D3DMetal, the only DirectX 12 path on this Mac, is installed.
    var hasD3DMetal: Bool { runtimes.contains { backend.capabilities(of: $0).status(of: .d3dMetal).isUsable } }
    /// Downloadable game engines, once components.json has been read.
    @Published private(set) var manifest: ComponentManifest?
    @Published private(set) var manifestError: String?
    /// Download and unpack progress of the game engine, 0…1, with a status line.
    @Published private(set) var engineProgress: (fraction: Double, status: String)?
    /// Progress text while a game's setup program is running; nil when idle.
    @Published var setupInstallStatus: String?
    /// A dropped or chosen file waiting for the add-game or install-game sheet.
    @Published var pendingAdd: URL?
    /// The add sheet is for a Windows app rather than a game.
    @Published var addingApp = false
    @Published var pendingSetup: URL?
    /// Versions confirmed by an install in this session; Wine writes its registry file up to 30 s later.
    @Published private(set) var visualCppInstalled: [UUID: String] = [:]

    init() {
        // Data saved under the app's former names (Metalgate, WildRun) moves to Alloy's folder, once.
        if ProcessInfo.processInfo.environment["ALLOY_DATA_DIR"] == nil { try? DataMigration.migrateIfNeeded() }
        DataMigration.renameEngines()
        let support = AppSettings.supportDirectory
        settingsStore = JSONFileStore(fileURL: support.appendingPathComponent("settings.json"))
        let settings = settingsStore.load(default: AppSettings())
        self.settings = settings
        library = GameLibrary(fileURL: settings.libraryLocation)
        prefixManager = PrefixManager(storageRoot: settings.prefixStorageLocation)
        benchmarkStore = BenchmarkStore(fileURL: support.appendingPathComponent("benchmarks.json"))
        launcher = GameLauncher(logsDirectory: support.appendingPathComponent("Logs"))
        games = library.games
        for game in games { if let saved = scans.saved(for: game) { traits[game.id] = saved } }
        benchmarks = benchmarkStore.runs
        prefixes = prefixManager.allPrefixes
        refreshRuntimes()
        importStoreGames()
        if ProcessInfo.processInfo.environment["ALLOY_SNAPSHOT_DIR"] == nil {
            offerSetupAfterDiscovery = true
            if (settings.acceptedTermsVersion ?? 0) < Terms.version {
                // People who installed with the .pkg agreed on its licence page.
                if (Terms.acceptedByInstaller() ?? 0) >= Terms.version {
                    self.settings.acceptedTermsVersion = Terms.version
                    saveSettings()
                } else {
                    sheet = .wizard(.welcome)
                }
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pullSessionOutput() }
        }
    }

    var termsAccepted: Bool { (settings.acceptedTermsVersion ?? 0) >= Terms.version }

    func acceptTerms() {
        settings.acceptedTermsVersion = Terms.version
        saveSettings()
    }

    // MARK: Setup wizard

    func setupRunner(installRosetta: Bool) -> SetupRunner {
        SetupRunner(backend: backend, runtimesDirectory: runtimesDirectory, downloads: componentDownloads,
                    componentsURL: settings.componentsURL, installRosetta: installRosetta)
    }

    func refreshSetupStates() {
        let runner = setupRunner(installRosetta: false)
        Task.detached {
            let states = runner.currentStates()
            await MainActor.run { if !self.runningSetup { self.setupStates = states } }
        }
    }

    /// Installs everything that is missing. The wizard's button says that this accepts Apple's licence for Rosetta 2.
    func installEverything() {
        guard !runningSetup else { return }
        runningSetup = true
        let runner = setupRunner(installRosetta: true)
        Task.detached {
            await runner.run { step, state in
                await MainActor.run {
                    self.setupStates[step] = state
                    switch (step, state) {
                    case (.engine, .working(let status, let fraction)): self.engineProgress = (fraction ?? 0, status)
                    case (.engine, _): self.engineProgress = nil
                    case (.rosetta, .working): self.installingRosetta = true
                    case (.rosetta, _): self.installingRosetta = false
                    default: break
                    }
                }
            }
            await MainActor.run {
                self.runningSetup = false
                self.engineProgress = nil
                self.installingRosetta = false
                self.rosettaInstalled = Rosetta.isInstalled()
                self.refreshRuntimes()
            }
        }
    }

    private func offerSetupIfNeeded() {
        guard offerSetupAfterDiscovery else { return }
        offerSetupAfterDiscovery = false
        if sheet == nil, setupStepsLeft > 0 { sheet = .wizard(.install) }
    }

    func showAdvanced(_ tab: AdvancedTab) {
        advancedTab = tab
        selection = .advanced
    }

    // MARK: Lookups

    var backend: WineBackend {
        WineBackend(installRoots: WineBackend().installRoots + settings.customRuntimeRoots,
                    managedRuntimesDirectory: runtimesDirectory)
    }

    func game(_ id: UUID?) -> Game? { id.flatMap { id in games.first { $0.id == id } } }
    func prefix(_ id: UUID?) -> WinePrefix? { id.flatMap { id in prefixes.first { $0.id == id } } }
    var ownPrefixes: [WinePrefix] { prefixes.filter { !$0.isReadOnly } }
    var crossOverBottles: [WinePrefix] { prefixes.filter(\.isReadOnly) }

    func runtime(for game: Game) -> WineRuntime? {
        let wanted = game.runtimeID ?? prefix(game.prefixID)?.runtimeID ?? settings.defaultRuntimeID
        return runtimes.first { $0.id == wanted } ?? runtimes.first
    }

    /// Runtime and graphics path for a new game. With an existing environment only its runtime is considered.
    func graphicsDefault(for game: Game, existingPrefixID: UUID?, traits: GameTraits? = nil) -> GraphicsDefaults.Choice {
        var candidates = runtimes
        if let id = existingPrefixID, let prefix = prefix(id) {
            candidates = runtimes.filter { $0.id == prefix.runtimeID }
        }
        let preferred = runtimes.first { $0.id == settings.defaultRuntimeID }
        return GraphicsDefaults.choose(traits: traits ?? scans.traits(for: game), runtimes: candidates,
                                       preferredRuntime: existingPrefixID == nil ? preferred : candidates.first, backend: backend)
    }

    /// A faster setup than the game has now: offered when it is not on DXMT or D3DMetal (or its runtime cannot
    /// run the one it is set to) and an installed runtime can.
    func recommendedUpgrade(for game: Game, traits: GameTraits) -> GraphicsDefaults.Choice? {
        let choice = graphicsDefault(for: game, existingPrefixID: nil, traits: traits)
        guard [.dxmt, .d3dMetal].contains(choice.backend), choice.runtime != nil else { return nil }
        let current = game.graphics.backend
        // A game that ships DLSS Frame Generation, on a path without it: offered even when that path is fast.
        if choice.frameGeneration, !game.declinedFrameGeneration,
           !(capabilities(for: game)?.metalFXFrameGeneration.contains(current) == true && !game.graphics.forceDX11) {
            return choice
        }
        // Without the frame-generation offer, a game already on a fast path is left alone.
        if choice.frameGeneration, [.dxmt, .d3dMetal].contains(current) { return nil }
        if [.dxmt, .d3dMetal].contains(current), capabilities(for: game)?.status(of: current).isUsable == true { return nil }
        return choice
    }

    /// Moves a game onto the recommended runtime and graphics path. An environment made with another runtime is
    /// left as it is (with its saves); the game gets a new one on the recommended runtime.
    func applyUpgrade(_ choice: GraphicsDefaults.Choice, to game: Game) {
        guard let runtime = choice.runtime else { return }
        var g = game
        if prefix(g.prefixID)?.runtimeID != runtime.id {
            let short = choice.backend == .dxmt ? "DXMT" : "D3DMetal"
            guard let p = createPrefix(name: "\(game.name) (\(short))", runtime: runtime) else { return }
            g.prefixID = p.id
            initializePrefix(p)
        }
        g.runtimeID = nil
        g.graphics.backend = choice.backend
        // Frame generation needs the game's DirectX 12 path.
        g.graphics.forceDX11 = choice.frameGeneration ? false : choice.forceDX11 || g.graphics.forceDX11
        g.graphics.dlss = choice.dlss || g.graphics.dlss
        g.graphics.advertiseAVX = true
        g.graphics.syncMode = .default
        save(g)
    }

    /// The D3DMetal 4 path for a game that ships DLSS Frame Generation, when a runtime for it is installed.
    func frameGenerationChoice(for game: Game, traits: GameTraits) -> GraphicsDefaults.Choice? {
        let choice = graphicsDefault(for: game, existingPrefixID: nil, traits: traits)
        return choice.frameGeneration && choice.runtime != nil ? choice : nil
    }

    func declineFrameGeneration(for game: Game) {
        var g = game
        g.declinedFrameGeneration = true
        save(g)
    }

    /// Whether any installed runtime runs DLSS Frame Generation (D3DMetal 4 with frame interpolation).
    var hasD3DMetalFrameGeneration: Bool {
        runtimes.contains { backend.capabilities(of: $0).metalFXFrameGeneration.contains(.d3dMetal) }
    }

    func capabilities(for game: Game) -> BackendCapabilities? {
        runtime(for: game).map { backend.capabilities(of: $0) }
    }

    func state(of id: UUID) -> LaunchState { states[id] ?? .idle }

    // MARK: Runtimes & prefixes

    func refreshRuntimes() {
        let backend = self.backend
        Task.detached {
            let found = backend.discoverRuntimes()
            await MainActor.run { self.runtimes = found; self.offerSetupIfNeeded() }
        }
    }

    func refreshPrefixes() { prefixes = prefixManager.allPrefixes }

    // MARK: Engine updates

    /// The newer game engine this environment can move to, if one is installed.
    func engineUpdate(for prefix: WinePrefix) -> WineRuntime? {
        guard !prefix.isReadOnly, let current = runtimes.first(where: { $0.id == prefix.runtimeID }) else { return nil }
        return EngineUpdate.newer(than: current, among: runtimes, managedDirectory: runtimesDirectory)
    }

    /// Something is running in this environment (a game, Steam, an installer).
    func isRunning(in prefix: WinePrefix) -> Bool {
        sessions.values.contains { session in
            session.state.isRunning && session.command.environment["WINEPREFIX"].map {
                URL(fileURLWithPath: $0).standardizedFileURL == prefix.path.standardizedFileURL
            } == true
        }
    }

    /// Moves the environment, and every game in it, onto the newest game engine. Only which engine runs it changes:
    /// its files, saves and installed games stay as they are.
    func moveToNewestEngine(_ prefix: WinePrefix) {
        guard let newest = engineUpdate(for: prefix) else { return }
        guard !isRunning(in: prefix) else {
            alert = AlertItem(title: "Close what's running in \(prefix.name) first",
                              message: "Quit the games and store apps running in this environment, then update its game engine.")
            return
        }
        let old = prefix.runtimeID
        var p = prefix
        p.runtimeID = newest.id
        do { try prefixManager.update(p) } catch { report(error, title: "Could not update \(prefix.name)"); return }
        refreshPrefixes()
        for game in games where game.prefixID == prefix.id && game.runtimeID != nil && game.runtimeID == old {
            var g = game
            g.runtimeID = nil
            save(g)
        }
    }

    func createPrefix(name: String, runtime: WineRuntime?) -> WinePrefix? {
        do {
            let p = try prefixManager.createPrefix(name: name, runtimeID: runtime?.id)
            refreshPrefixes()
            return p
        } catch { report(error, title: "Could not create environment"); return nil }
    }

    /// Runs `wineboot --init`. Only the macOS Wine loader runs; no user-supplied Windows program.
    func initializePrefix(_ prefix: WinePrefix) {
        guard let runtime = runtimes.first(where: { $0.id == prefix.runtimeID }) ?? runtimes.first else {
            alert = AlertItem(title: "No Wine runtime", message: RuntimeInstallGuide.summary); return
        }
        do {
            let command = try backend.initializePrefixCommand(prefix: prefix, runtime: runtime)
            let session = try launcher.launch(gameID: prefix.id, gameName: "prefix-\(prefix.name)", command: command)
            track(session, id: prefix.id) { [weak self] _ in self?.refreshPrefixes() }
        } catch { report(error, title: "Could not initialise \(prefix.name)") }
    }

    /// Builds an Alloy-managed D3DMetal runtime from Apple's Game Porting Toolkit redistributable that the
    /// user downloaded and whose licence they accepted. The selected Wine build and the image are only read.
    func importD3DMetal() {
        importingD3DMetal = true
        Task.detached {
            let found = D3DMetalImporter.findOnThisMac()
            await MainActor.run {
                self.importingD3DMetal = false
                self.importD3DMetal(found: found)
            }
        }
    }

    /// Uses D3DMetal already on this Mac after the person confirms, else asks them to choose the toolkit.
    private func importD3DMetal(found: D3DMetalRedistributable?) {
        var redist = found
        if let found {
            let confirm = NSAlert()
            confirm.messageText = "Use D3DMetal \(found.version ?? "") from Apple's Game Porting Toolkit?"
            confirm.informativeText = "Alloy found it at \(LogRedactor.redact(found.lib.path)). It's used under Apple's licence for the toolkit, which you accepted when you downloaded it. Alloy copies it into its own engine folder and leaves the original as it is."
            confirm.addButton(withTitle: "Use It")
            confirm.addButton(withTitle: "Choose Another…")
            confirm.addButton(withTitle: "Cancel")
            switch confirm.runModal() {
            case .alertFirstButtonReturn: break
            case .alertSecondButtonReturn: redist = nil
            default: return
            }
        }
        if redist == nil {
            guard let source = AppModel.chooseFolder(prompt: "Use This Toolkit") else { return }
            redist = D3DMetalImporter.locate(in: source)
        }
        guard let redist else {
            alert = AlertItem(title: "D3DMetal not found",
                              message: "Download Apple's Game Porting Toolkit from developer.apple.com, open its “Evaluation environment for Windows games” disk image and click Add D3DMetal again. Alloy finds it by itself once it's mounted.")
            return
        }
        guard let base = runtimes.first(where: D3DMetalImporter.isPlainManagedBuild)
                ?? runtimes.first(where: { $0.kind == .gamePortingToolkit && D3DMetalImporter.isLayerableBase($0) }) else {
            alert = AlertItem(title: "No Game Porting Toolkit Wine build",
                              message: "D3DMetal needs a Wine build made from Apple's Game Porting Toolkit sources. Install one (for example Gcenx's game-porting-toolkit build), then try again.")
            return
        }
        importingD3DMetal = true
        let runtimesDirectory = self.runtimesDirectory
        Task.detached {
            do {
                try D3DMetalImporter.makeManagedRuntime(name: "D3DMetal \(redist.version ?? "")".trimmingCharacters(in: .whitespaces),
                                                        base: base, redist: redist, runtimesDirectory: runtimesDirectory)
                await MainActor.run { self.importingD3DMetal = false; self.refreshRuntimes() }
            } catch {
                await MainActor.run { self.importingD3DMetal = false; self.report(error, title: "D3DMetal import failed") }
            }
        }
    }

    func trashPrefix(_ prefix: WinePrefix) {
        do {
            try prefixManager.trashPrefix(id: prefix.id)
            for var g in games where g.prefixID == prefix.id { g.prefixID = nil; save(g) }
            refreshPrefixes()
        } catch { report(error, title: "Could not remove environment") }
    }

    func stopAll(in prefix: WinePrefix) {
        guard let runtime = runtimes.first(where: { $0.id == prefix.runtimeID }) ?? runtimes.first else { return }
        let command = backend.stopPrefixCommand(prefix: prefix, runtime: runtime)
        try? LaunchSession(command: command, logFile: nil).start()
    }

    func installDXVK(into prefix: WinePrefix) {
        guard let source = settings.dxvkLocation else {
            alert = AlertItem(title: "DXVK location not set",
                              message: "Download a DXVK-macOS build yourself and select its folder (containing x64/ and x32/) in Settings.")
            return
        }
        do { try prefixManager.installDXVK(from: source, into: prefix); refreshPrefixes() }
        catch { report(error, title: "DXVK install failed") }
    }

    func uninstallDXVK(from prefix: WinePrefix) {
        do { try prefixManager.uninstallDXVK(from: prefix); refreshPrefixes() }
        catch { report(error, title: "Could not restore original DLLs") }
    }

    // MARK: Game engine

    /// True when an installed runtime runs DirectX 10/11 games through Metal (DXMT).
    var hasGameEngine: Bool { runtimes.contains { backend.capabilities(of: $0).status(of: .dxmt).isUsable } }

    /// Steps Setup still needs before games run: Rosetta 2 and the game engine.
    var setupStepsLeft: Int { (rosettaInstalled ? 0 : 1) + (hasGameEngine ? 0 : 1) }

    /// Runs Apple's Rosetta installer; SetupView asks the person to agree to Apple's licence first.
    func installRosetta() {
        guard !installingRosetta else { return }
        installingRosetta = true
        Task.detached {
            let failure: String?
            do { try Rosetta.install(); failure = nil } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await MainActor.run {
                self.installingRosetta = false
                self.rosettaInstalled = Rosetta.isInstalled()
                if let failure { self.alert = AlertItem(title: "Rosetta 2 was not installed", message: failure) }
            }
        }
    }

    var installedPackages: [String: RuntimeInstaller.Marker] { RuntimeInstaller.installedMarkers(in: runtimesDirectory) }

    /// A newer game engine to download, when one is already installed (Setup offers the first one in the list).
    var engineDownloadUpdate: RuntimePackage? {
        guard engineProgress == nil, hasGameEngine, let package = manifest?.runtimes.first,
              installedPackages[package.id] == nil else { return nil }
        return package
    }

    /// Reads the list of downloadable game engines from the address this release was built with.
    func loadManifest() {
        guard let url = settings.componentsURL else {
            manifestError = "This copy of Alloy was built without a download address for the game engine. Install it from a package file instead."
            return
        }
        manifestError = nil
        Task {
            do { manifest = try await RuntimeInstaller.fetchManifest(from: url) }
            catch { manifestError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }

    func installEngine(_ package: RuntimePackage) {
        guard engineProgress == nil else { return }
        engineProgress = (0, "Starting the download…")
        let runtimesDirectory = self.runtimesDirectory
        let downloads = AppSettings.supportDirectory.appendingPathComponent("Downloads/runtimes")
        Task.detached {
            do {
                _ = try await RuntimeInstaller.install(package, into: runtimesDirectory, downloads: downloads) { fraction, status in
                    Task { @MainActor in self.engineProgress = (fraction, status) }
                }
                await MainActor.run { self.engineProgress = nil; self.refreshRuntimes() }
            } catch {
                await MainActor.run { self.engineProgress = nil; self.report(error, title: "The game engine was not installed") }
            }
        }
    }

    /// Installs a game engine package the user downloaded themselves (a .tar.xz from an Alloy release).
    func installEngine(fromArchive archive: URL) {
        guard engineProgress == nil else { return }
        engineProgress = (0.5, "Unpacking \(archive.lastPathComponent)…")
        let runtimesDirectory = self.runtimesDirectory
        Task.detached {
            do {
                _ = try RuntimeInstaller.unpack(archive: archive, into: runtimesDirectory)
                await MainActor.run { self.engineProgress = nil; self.refreshRuntimes() }
            } catch {
                await MainActor.run { self.engineProgress = nil; self.report(error, title: "The game engine was not installed") }
            }
        }
    }

    // MARK: Windows components

    var componentDownloads: URL { AppSettings.supportDirectory.appendingPathComponent("Downloads") }

    /// Installs the components into the environment one after another, showing progress on the environment.
    func install(_ components: [WindowsComponent], into prefix: WinePrefix) {
        guard let runtime = runtimes.first(where: { $0.id == prefix.runtimeID }) ?? runtimes.first else {
            alert = AlertItem(title: "No game engine", message: "Install the game engine from Setup first."); return
        }
        guard componentStatus[prefix.id] == nil, !components.isEmpty else { return }
        componentStatus[prefix.id] = "Preparing…"
        let backend = self.backend, downloads = componentDownloads
        Task.detached {
            do {
                try await AppModel.installComponents(components, into: prefix, runtime: runtime, backend: backend, downloads: downloads) { status in
                    Task { @MainActor in self.componentStatus[prefix.id] = status }
                }
                await MainActor.run { self.finishedComponents(in: prefix) }
            } catch {
                await MainActor.run {
                    self.componentStatus[prefix.id] = nil
                    self.report(error, title: "Windows components were not installed")
                }
            }
        }
    }

    nonisolated static func installComponents(_ components: [WindowsComponent], into prefix: WinePrefix, runtime: WineRuntime,
                                              backend: WineBackend, downloads: URL,
                                              progress: @escaping @Sendable (String) -> Void) async throws {
        for component in components where !component.isInstalled(in: prefix) {
            switch component {
            case .visualCpp:
                _ = try await VisualCppRuntime.install(into: prefix, runtime: runtime, backend: backend,
                                                       downloads: ComponentDownloads.folder(for: .visualCpp, in: downloads), progress: progress)
            case .dotNet:
                try await WineMono.install(into: prefix, runtime: runtime, backend: backend,
                                           downloads: ComponentDownloads.folder(for: .dotNet, in: downloads), progress: progress)
            }
        }
    }

    private func finishedComponents(in prefix: WinePrefix) {
        componentStatus[prefix.id] = nil
        if let version = VisualCppRuntime.installedVersion(.x64, in: prefix) { visualCppInstalled[prefix.id] = version }
        for game in games where game.prefixID == prefix.id {
            findings[game.id]?.removeAll { $0.kind == .missingRuntimeComponent }
        }
        objectWillChange.send()
    }

    // MARK: Simple graphics

    func setPlayMode(_ mode: PlayMode, for game: Game) {
        var g = game
        mode.apply(to: &g.graphics)
        save(g)
    }

    /// MetalFX scaling: games that support DLSS get Apple MetalFX upscaling instead (DLSS → MetalFX).
    func setMetalFXScaling(_ on: Bool, for game: Game) {
        var g = game
        g.graphics.dlss = on
        save(g)
    }

    /// Compatibility mode is Wine's own Direct3D (OpenGL) in the same environment. Turning it off returns to the
    /// Metal path Alloy picks for the game, which may need a new environment on the game engine.
    func setCompatibilityMode(_ on: Bool, for game: Game) {
        if on {
            var g = game
            g.graphics.backend = .wined3dOpenGL
            g.graphics.metalFXSpatialFactor = nil
            save(g)
            return
        }
        let choice = graphicsDefault(for: game, existingPrefixID: nil, traits: traits[game.id])
        guard [.dxmt, .d3dMetal].contains(choice.backend), choice.runtime != nil else {
            alert = AlertItem(title: "No faster graphics for this game",
                              message: "The installed game engine has no Metal path for this game's DirectX version. \(choice.reason)")
            return
        }
        applyUpgrade(choice, to: game)
    }

    // MARK: Installing games from a setup program

    /// Makes an environment for the game on the game engine, runs the setup the user chose there and adds the game it
    /// installed. The user confirmed the setup in the app first.
    func installGame(from setup: URL, name: String) {
        let choice = GraphicsDefaults.choose(usage: [.d3d11], machine: .x64, runtimes: runtimes,
                                             preferredRuntime: runtimes.first { $0.id == settings.defaultRuntimeID }, backend: backend)
        guard let runtime = choice.runtime else {
            alert = AlertItem(title: "No game engine", message: "Install the game engine from Setup first."); return
        }
        guard setupInstallStatus == nil, let prefix = createPrefix(name: name, runtime: runtime) else { return }
        setupInstallStatus = "Preparing an environment for \(name)…"
        let backend = self.backend, launcher = self.launcher
        Task.detached {
            do {
                let initialize = try launcher.launch(gameID: prefix.id, gameName: "prefix-\(prefix.name)",
                                                     command: try backend.initializePrefixCommand(prefix: prefix, runtime: runtime))
                guard initialize.waitUntilExit(timeout: 600) == .exited(code: 0) else {
                    throw AlloyError.launchFailed("The environment for \(name) could not be set up.")
                }
                let before = GameInstaller.executables(in: prefix)
                await MainActor.run { self.refreshPrefixes(); self.setupInstallStatus = "Running \(setup.lastPathComponent). Follow its steps; keep the suggested install folder." }
                let session = try launcher.launch(gameID: UUID(), gameName: "setup-\(name)",
                                                  command: try GameInstaller.setupCommand(installer: setup, prefix: prefix, runtime: runtime, backend: backend))
                let state = await session.waitForExit()
                let added = GameInstaller.executables(in: prefix).subtracting(before)
                guard let installed = GameInstaller.installedGame(name: name, newExecutables: added, prefix: prefix) else {
                    throw AlloyError.launchFailed("The setup ended (\(state.summary.lowercased())) without installing a program Alloy can start. If it installed somewhere unusual, add the game with Add Game Folder and choose that folder inside the environment.")
                }
                let traits = self.scans.traits(for: installed)
                await MainActor.run {
                    var game = installed
                    let choice = self.graphicsDefault(for: game, existingPrefixID: prefix.id, traits: traits)
                    game.graphics.backend = choice.backend
                    game.graphics.forceDX11 = choice.forceDX11
                    game.graphics.dlss = choice.dlss
                    game.notes = "Installed from \(setup.lastPathComponent). Graphics default: \(choice.reason)"
                    self.setupInstallStatus = nil
                    self.traits[game.id] = traits
                    self.add(game)
                    self.selection = .library
                }
            } catch {
                await MainActor.run { self.setupInstallStatus = nil; self.report(error, title: "\(name) was not installed") }
            }
        }
    }

    /// A folder or file dropped on the library: a setup program opens the install sheet, anything else the add sheet.
    func handleDrop(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if ext == "msi" || (ext == "exe" && ["setup", "install"].contains(where: name.contains)) {
            pendingSetup = url
        } else {
            addingApp = false
            pendingAdd = url
        }
    }

    // MARK: Game stores

    /// The store app's library entry, if it is installed.
    func storeEntry(_ store: GameStore) -> Game? {
        games.first { GameStore.store(for: $0) == store && !StoreLibraryScanner.startsAGame($0) }
    }

    /// What the last one-click fix on a game's page changed, shown until the game is started again.
    @Published var appliedFix: [UUID: String] = [:]

    /// The finding's fixes that would change something for this game, best first.
    func fixes(for finding: DiagnosticFinding, game: Game) -> [DiagnosticFix] {
        let prefix = prefix(game.prefixID)
        return finding.fixes.filter {
            if [.installVisualCpp, .installDotNet, .stopEnvironment].contains($0), prefix == nil || prefix?.isReadOnly == true { return false }
            if $0 == .installVisualCpp, let prefix, !VisualCppRuntime.canInstall(in: prefix) { return false }
            return $0.applies(to: game, capabilities: capabilities(for: game), traits: traits[game.id],
                              visualCppInstalled: prefix.map { WindowsComponent.visualCpp.isInstalled(in: $0) } ?? true,
                              dotNetInstalled: prefix.map { WindowsComponent.dotNet.isInstalled(in: $0) } ?? true,
                              hasD3DMetal: hasD3DMetal)
        }
    }

    func apply(_ fix: DiagnosticFix, for finding: DiagnosticFinding, game: Game) {
        switch fix {
        case .installVisualCpp: if let p = prefix(game.prefixID) { install([.visualCpp], into: p) }
        case .installDotNet: if let p = prefix(game.prefixID) { install([.dotNet], into: p) }
        case .addD3DMetal: importD3DMetal(); return
        case .openSetup: selection = .setup; return
        case .addDLL: chooseDLLs(for: game); return
        case .stopEnvironment: if let p = prefix(game.prefixID) { stopAll(in: p) }
        default:
            var g = game
            guard fix.apply(to: &g) else { return }
            save(g)
        }
        findings[game.id]?.removeAll { $0.id == finding.id }
        appliedFix[game.id] = fix.done.isEmpty ? "\(fix.title): started. Press Play when it's done." : "\(fix.done) Press Play to try again."
    }

    /// Stores set up in Alloy that can install games from a link.
    var gameInstallStores: [GameStore] { [GameStore.steam, .epic].filter { storeEntry($0) != nil } }

    /// Opens the store app at the game: Steam's install dialog, or the game's page in Epic's launcher. The store
    /// checks ownership and downloads; the game joins the library when its install finishes.
    func installThroughStore(_ link: StoreGameLink) {
        guard let entry = storeEntry(link.store) else {
            alert = AlertItem(title: "\(link.store.displayName) isn't installed", message: "Install it from Setup first. Alloy sets it up in its own environment.")
            return
        }
        if sessions[entry.id]?.state.isRunning == true, let prefix = prefix(entry.prefixID), let runtime = runtime(for: entry) {
            // The running store app takes the address from a second start of its program, which then ends.
            var g = entry
            g.arguments += [link.address]
            do {
                let session = LaunchSession(command: try backend.launchCommand(for: g, prefix: prefix, runtime: runtime,
                                                                               options: LaunchOptions(logLevel: settings.logLevel)),
                                            logFile: nil)
                try session.start()
                Task.detached { _ = session.waitUntilExit(timeout: 120) }
                sessions[entry.id]?.note("Asked \(link.store.displayName) to install \(link.summary)")
            } catch { report(error, title: "Could not open \(link.store.displayName)") }
        } else {
            requestLaunch(entry, extraArguments: [link.address])
        }
        storePollTick = 0
    }

    /// Reads what the stores are downloading, and adds games whose download finished to the library.
    func refreshStoreDownloads() {
        var now: [StoreDownload] = []
        for store in gameInstallStores {
            guard let entry = storeEntry(store), let prefix = prefix(entry.prefixID) else { continue }
            now += StoreDownloads.current(of: store, in: prefix)
        }
        if now != storeDownloads {
            let finished = !Set(storeDownloads.map(\.id)).isSubset(of: Set(now.map(\.id)))
            storeDownloads = now
            if finished { importStoreGames() }
        }
    }

    /// Makes an environment for the store on the runtime Alloy picks for DirectX 11 games, downloads the store's
    /// official installer, runs it there and adds the store app to the library. The user confirmed this in the app first.
    func installStore(_ store: GameStore) {
        // Prefer runtimes the store fully works on (Steam's windows draw, and every store can sign in).
        let ready = runtimes.filter { store.missingRequirements(in: $0).isEmpty }
        let candidates = ready.isEmpty ? runtimes : ready
        let choice = GraphicsDefaults.choose(usage: [.d3d11], machine: .x64, runtimes: candidates,
                                             preferredRuntime: candidates.first { $0.id == settings.defaultRuntimeID }, backend: backend)
        guard let runtime = choice.runtime else {
            alert = AlertItem(title: "No Wine runtime", message: RuntimeInstallGuide.summary); return
        }
        // An earlier, unfinished attempt's environment is reused rather than duplicated.
        guard let prefix = ownPrefixes.first(where: { $0.name == store.environmentName && $0.runtimeID == runtime.id })
                ?? createPrefix(name: store.environmentName, runtime: runtime) else { return }
        var graphics = GraphicsConfiguration(backend: choice.backend)
        // DLSS → MetalFX is set per game when its files show it ships DLSS, never for a whole store environment:
        // it makes the graphics layer report an NVIDIA GPU, which a game without DLSS has no use for.
        graphics.dlss = false
        let backend = self.backend
        let installer = AppSettings.supportDirectory.appendingPathComponent("Downloads/\(store.installerFileName)")
        storeInstallStatus[store] = "Setting up the \(store.environmentName) environment…"
        Task.detached {
            do {
                let entry = try await StoreInstaller.install(store, into: prefix, runtime: runtime, backend: backend, graphics: graphics,
                                                             installer: installer) { status in
                    Task { @MainActor in self.storeInstallStatus[store] = status }
                }
                await MainActor.run {
                    self.storeInstallStatus[store] = nil
                    self.refreshPrefixes()
                    self.add(entry)
                }
            } catch {
                await MainActor.run {
                    self.storeInstallStatus[store] = nil
                    self.report(error, title: "\(store.displayName) was not installed")
                    self.checkStoreConnectivity([store])
                }
            }
        }
    }

    /// Checks from macOS whether each store's sign-in servers answer, so a filtered network is named as the cause.
    func checkStoreConnectivity(_ stores: [GameStore] = GameStore.allCases) {
        guard !stores.isEmpty else { return }
        checkingStores = true
        Task {
            await withTaskGroup(of: (GameStore, StoreConnectivity.Status).self) { group in
                for store in stores { group.addTask { (store, await StoreConnectivity.check(store)) } }
                for await (store, status) in group { storeConnectivity[store] = status }
            }
            checkingStores = false
        }
    }

    /// Adds games installed through Steam or the Epic Games Launcher to the library; they start through the store.
    func importStoreGames() {
        for store in [GameStore.steam, .epic] {
            guard let entry = storeEntry(store), let prefix = prefix(entry.prefixID) else { continue }
            let found = StoreLibraryScanner.installedGames(of: store, in: prefix)
            for game in StoreLibraryScanner.newEntries(for: found, storeEntry: entry, existing: games) {
                do { try library.add(game) } catch { report(error, title: "Could not add \(game.name)"); return }
            }
        }
        games = library.games
    }

    /// When a store app starts, a blocked network is the usual reason it cannot sign in, so say so at once.
    private func warnIfStoreBlocked(_ game: Game) {
        guard let store = GameStore.store(for: game) else { return }
        Task {
            let status = await StoreConnectivity.check(store)
            storeConnectivity[store] = status
            if let message = StoreConnectivity.explanation(status, store: store) {
                alert = AlertItem(title: status == .offline ? "No internet connection" : "This network blocks \(store.displayName)", message: message)
            }
        }
    }

    // MARK: Visual C++

    /// Installed version of the 64-bit runtime in this environment, or nil.
    func visualCppVersion(in prefix: WinePrefix) -> String? {
        visualCppInstalled[prefix.id] ?? VisualCppRuntime.installedVersion(.x64, in: prefix)
    }

    var visualCppDownloads: URL { AppSettings.supportDirectory.appendingPathComponent("Downloads/vcredist") }

    /// Downloads Microsoft's Visual C++ 2015–2022 installers (if not already downloaded and verified) and runs them in
    /// the environment. The user confirmed this in the app first.
    func installVisualCpp(into prefix: WinePrefix) { install([.visualCpp], into: prefix) }

    // MARK: Library

    func add(_ game: Game) {
        do { try library.add(game); games = library.games; selectedGameID = game.id }
        catch { report(error, title: "Could not add game") }
    }

    /// Asks for DLL files and adds them to the game's environment. Only files the person picks; nothing is downloaded.
    func chooseDLLs(for game: Game) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["dll", "sys"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose DLL files for \(game.name). Use files from the program's own installer or its maker, not DLL download websites."
        guard panel.runModal() == .OK else { return }
        addDLLs(panel.urls, to: game)
    }

    func addDLLs(_ urls: [URL], to game: Game) {
        guard let prefix = prefix(game.prefixID) else {
            alert = AlertItem(title: "No environment", message: "Start \(game.name) once so Alloy creates its environment, then add DLLs.")
            return
        }
        var updated = self.game(game.id) ?? game
        var problems: [String] = []
        for url in urls {
            do {
                let dll = try CustomDLLs.install(url, into: prefix)
                updated.customDLLs.removeAll { $0 == dll }
                updated.customDLLs.append(dll)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        save(updated)
        if !problems.isEmpty { alert = AlertItem(title: "Some files weren't added", message: problems.joined(separator: "\n\n")) }
    }

    func removeDLL(_ dll: CustomDLL, from game: Game) {
        guard let prefix = prefix(game.prefixID) else { return }
        do {
            // Another game in the same environment may still use it; then only this game stops preferring it.
            let shared = games.contains { $0.id != game.id && $0.prefixID == game.prefixID && $0.customDLLs.contains(dll) }
            if !shared { try CustomDLLs.remove(dll, from: prefix) }
            var updated = self.game(game.id) ?? game
            updated.customDLLs.removeAll { $0 == dll }
            save(updated)
        } catch {
            report(error, title: "\(dll.name) wasn't removed")
        }
    }

    // MARK: Environment tools

    private func runtime(forPrefix prefix: WinePrefix) -> WineRuntime? {
        runtimes.first { $0.id == prefix.runtimeID } ?? runtimes.first
    }

    /// Opens one of Wine's own programs in an environment.
    func open(_ tool: WineTool, in prefix: WinePrefix) {
        runWineTool(tool.arguments, in: prefix, title: "\(tool.title) didn't open")
    }

    func setWindowsVersion(_ version: WindowsVersion, in prefix: WinePrefix) {
        runWineTool(version.arguments, in: prefix, title: "The Windows version wasn't changed")
    }

    private func runWineTool(_ arguments: [String], in prefix: WinePrefix, title: String) {
        guard let runtime = runtime(forPrefix: prefix) else { alert = AlertItem(title: title, message: RuntimeInstallGuide.summary); return }
        do {
            let command = try backend.wineToolCommand(arguments, prefix: prefix, runtime: runtime)
            try LaunchSession(command: command, logFile: nil).start()
        } catch {
            report(error, title: title)
        }
    }

    /// Runs a Windows program the person picks, once, in an environment, after showing what it is.
    func runProgram(in prefix: WinePrefix) {
        guard let url = AppModel.chooseFile(types: ["exe", "msi", "bat"], prompt: "Run") else { return }
        let info = try? PEInspector.inspect(url)
        if url.pathExtension.lowercased() == "exe", info?.machine.isSupportedByWineOnMac != true {
            alert = AlertItem(title: "\(url.lastPathComponent) can't run", message: "It isn't a Windows program Wine can run (\(info?.machine.rawValue ?? "not a valid program")).")
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Run \(url.lastPathComponent) in \(prefix.name)?"
        confirm.informativeText = "It runs with your user permissions, never as administrator, in this environment only. Only run software you trust.\n\n\(LogRedactor.redact(url.deletingLastPathComponent().path))"
        confirm.addButton(withTitle: "Run")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let args: [String] = switch url.pathExtension.lowercased() {
        case "msi": ["msiexec", "/i", url.path]
        case "bat": ["start", "/unix", url.path]
        default: [url.path]
        }
        runWineTool(args, in: prefix, title: "\(url.lastPathComponent) didn't start")
    }

    /// Tools, Windows version and Run Program for an environment, as menu items.
    func environmentMenu(for prefix: WinePrefix) -> [MenuChoice] {
        let ready = !prefix.isReadOnly && prefix.isInitialized()
        let current = WindowsVersion.current(in: prefix)
        return [
            MenuChoice(title: "Run a Program in This Environment…", enabled: ready) { self.runProgram(in: prefix) },
            MenuChoice(title: "Windows Tools", enabled: ready, children: WineTool.allCases.map { tool in
                MenuChoice(title: tool.title) { self.open(tool, in: prefix) }
            }),
            MenuChoice(title: "Windows Version", enabled: ready, children: WindowsVersion.allCases.map { version in
                MenuChoice(title: version.title, checked: version == current) { self.setWindowsVersion(version, in: prefix) }
            }),
        ]
    }

    func save(_ game: Game) {
        do { try library.update(game); games = library.games }
        catch { report(error, title: "Could not save game") }
    }

    /// Removes only the library entry; the game's files are untouched.
    func remove(_ game: Game) {
        launcher.stop(gameID: game.id)
        do { try library.remove(id: game.id); games = library.games }
        catch { report(error, title: "Could not remove game"); return }
        scans.forget(game.id)
        // Its saved shaders are Alloy's own data, made again if the game is added back. Moved to the Trash.
        let shaders = ShaderCache.directory(for: game.id, supportDirectory: AppSettings.supportDirectory)
        if FileManager.default.fileExists(atPath: shaders.path) { try? FileManager.default.trashItem(at: shaders, resultingItemURL: nil) }
        if selectedGameID == game.id { selectedGameID = nil }
    }

    // MARK: Launching

    /// Validates everything and asks for confirmation unless this exact executable was confirmed before.
    /// `extraArguments` are added for this start only (a store address), not saved with the game.
    func requestLaunch(_ game: Game, extraArguments: [String] = []) {
        guard let runtime = runtime(for: game) else {
            findings[game.id] = DiagnosticService.preflight(game: game, runtime: nil, prefix: prefix(game.prefixID))
            alert = AlertItem(title: "No Wine runtime installed", message: RuntimeInstallGuide.summary)
            return
        }
        guard let prefix = prefix(game.prefixID) else {
            alert = AlertItem(title: "No environment selected",
                              message: "Edit the game and choose an Alloy environment (prefix) to run it in.")
            return
        }
        guard !prefix.isReadOnly else {
            alert = AlertItem(title: "CrossOver bottle selected",
                              message: AlloyError.prefixReadOnly(name: prefix.name).errorDescription ?? "")
            return
        }
        // A Steam game always starts from Alloy, never from Steam: started by Steam, it got the settings Steam was opened
        // with, Alloy lost track of it, and macOS could leave it in the background without Game Mode. When Steam isn't
        // open yet, Alloy opens it quietly first and starts the game once Steam has signed in.
        if extraArguments.isEmpty, !preparing.contains(game.id), !steamFallback.contains(game.id), !steamIsOpen(in: prefix),
           directSteamGame(game, prefix: prefix) != nil, let steam = steamEntry(in: prefix) {
            openSteamThenStart(game, steam: steam, prefix: prefix)
            return
        }
        do {
            // With Steam already open, steam.exe would only pass the request on: the game would get Steam's settings
            // instead of its own, and Alloy would lose track of it. The game's own program is started instead.
            let direct = steamIsOpen(in: prefix) ? directSteamGame(game, prefix: prefix) : nil
            let info = try ExecutableValidator.validate(direct?.game ?? game)
            // DXMT keeps converted shaders in Alloy's folder, so later starts don't convert them again.
            let shaders = game.graphics.backend == .dxmt && (game.graphics.shaderCachePath ?? "").isEmpty
                ? ShaderCache.prepare(for: game, supportDirectory: AppSettings.supportDirectory) : nil
            var launched = direct?.game ?? game
            if direct == nil { launched.arguments += extraArguments }
            var command = try backend.launchCommand(for: launched, prefix: prefix, runtime: runtime,
                                                    options: LaunchOptions(logLevel: settings.logLevel,
                                                                           loadMetricsHUD: settings.metricsShortcut,
                                                                           shaderCacheDirectory: shaders))
            if let direct {
                let arguments = direct.launch.arguments.isEmpty ? "" : " \(direct.launch.arguments)"
                command.notes.append("Steam is already open, so Alloy starts \(direct.launch.executable)\(arguments) itself, the way Steam would, with \(game.name)'s own settings. Steam still signs it in.")
            } else if StoreLibraryScanner.startsAGame(game), GameStore.store(for: game) == .steam {
                command.notes.append("Steam starts \(game.name). If Steam was already open elsewhere, the game runs with the settings Steam was opened with, and Alloy can't tell when it closes.")
            }
            let pending = PendingLaunch(game: game, command: command, info: info, runtime: runtime, prefix: prefix)
            let fingerprint = ExecutableValidator.fingerprint(of: game.executableURL)
            if fingerprint != nil && fingerprint == game.confirmedExecutableFingerprint {
                startLaunch(pending, remember: false)
            } else {
                pendingLaunch = pending
            }
        } catch {
            findings[game.id] = DiagnosticService.preflight(game: game, runtime: runtime, prefix: prefix)
            report(error, title: "Cannot launch \(game.name)")
        }
    }

    /// The library entry for the Steam app itself in this environment.
    func steamEntry(in prefix: WinePrefix) -> Game? {
        games.first { $0.prefixID == prefix.id && GameStore.store(for: $0) == .steam && !StoreLibraryScanner.startsAGame($0) }
    }

    /// Opens Steam in the background, waits up to 90 seconds for it to sign in, then starts the game itself. If Steam
    /// doesn't open or sign in, the game is started the old way, through steam.exe.
    private func openSteamThenStart(_ game: Game, steam: Game, prefix: WinePrefix) {
        let since = Date()
        let log = StoreInstaller.executable(of: .steam, in: prefix)?.deletingLastPathComponent()
            .appendingPathComponent("logs/connection_log.txt")
        preparing.insert(game.id)
        requestLaunch(steam, extraArguments: ["-silent"])
        Task { @MainActor [weak self] in
            for second in 1...90 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                let open = self.steamIsOpen(in: prefix)
                // Steam didn't start (and isn't waiting for the user to confirm it).
                if !open && self.pendingLaunch == nil && second >= 10 { break }
                if open, let log, let text = try? String(contentsOf: log, encoding: .utf8),
                   SteamDirectLaunch.signedIn(connectionLog: text, since: since) {
                    // Signed in; a moment more for Steam to answer games asking for it.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    break
                }
            }
            guard let self else { return }
            self.preparing.remove(game.id)
            // Steam open: the game starts directly. Not open: through steam.exe, without trying to open Steam again.
            self.steamFallback.insert(game.id)
            self.requestLaunch(game)
            self.steamFallback.remove(game.id)
        }
    }

    /// Games being started through steam.exe after Steam didn't open or sign in for Alloy.
    private var steamFallback: Set<UUID> = []

    /// Steam is running in this environment, started by Alloy (for the store entry or a game it started).
    func steamIsOpen(in prefix: WinePrefix) -> Bool {
        sessions.values.contains { session in
            guard session.state.isRunning, let path = session.command.environment["WINEPREFIX"],
                  URL(fileURLWithPath: path).standardizedFileURL == prefix.path.standardizedFileURL,
                  let program = session.command.arguments.first else { return false }
            return URL(fileURLWithPath: program).lastPathComponent.lowercased() == "steam.exe"
        }
    }

    /// The game's own program, from Steam's launch settings, for a library entry that starts a game through Steam.
    func directSteamGame(_ game: Game, prefix: WinePrefix) -> (game: Game, launch: SteamAppInfo.Launch)? {
        guard GameStore.store(for: game) == .steam, StoreLibraryScanner.startsAGame(game),
              let steam = StoreInstaller.executable(of: .steam, in: prefix)?.deletingLastPathComponent() else { return nil }
        return SteamDirectLaunch.directGame(for: game, steamFolder: steam, apps: SteamAppInfoReader.apps(steamFolder: steam))
    }

    /// The game has a native macOS version on Steam, which runs better than the Windows one through Wine.
    func steamMacVersion(of game: Game) -> Bool {
        guard let id = CoverArt.steamAppID(of: game).flatMap(UInt32.init), let prefix = prefix(game.prefixID),
              let steam = StoreInstaller.executable(of: .steam, in: prefix)?.deletingLastPathComponent() else { return false }
        return SteamAppInfoReader.apps(steamFolder: steam)[id]?.hasMacVersion == true
    }

    func startLaunch(_ pending: PendingLaunch, remember: Bool) {
        var game = pending.game
        if remember { game.confirmedExecutableFingerprint = ExecutableValidator.fingerprint(of: game.executableURL) }
        game.lastPlayed = Date()
        save(game)
        let command = pending.command
        let runtime = pending.runtime, prefix = pending.prefix
        let needsDLSS = game.graphics.dlss && backend.capabilities(of: runtime).metalFXUpscaling.contains(game.graphics.backend)
        let needsVideo = VideoPlayback.needsSetup(prefix: prefix, runtime: runtime)
        // Once per environment: a crash then ends the game with a log Alloy explains, instead of Wine's debugger window.
        let needsQuietCrashes = !prefix.isReadOnly && !CrashDialog.isOff(in: prefix)
        let autoInstall = settings.autoInstallComponents
        let knownTraits = traits[game.id]
        let backend = self.backend, downloads = componentDownloads, scans = self.scans
        guard needsDLSS || needsVideo || needsQuietCrashes || autoInstall else { beginSession(game, command: command); return }
        // Set up once per environment: Windows components the game needs, video decoders for environments made before
        // their runtime had them, and for DLSS → MetalFX the NGX shim and its registry entry.
        let managed = runtime.root.standardizedFileURL.path.hasPrefix(runtimesDirectory.standardizedFileURL.path + "/")
        preparing.insert(game.id)
        Task.detached {
            if autoInstall {
                let traits = knownTraits ?? scans.traits(for: game)
                if knownTraits == nil { await MainActor.run { self.traits[game.id] = traits } }
                let missing = WindowsComponent.missing(for: traits, in: prefix)
                    .filter { $0 != .visualCpp || VisualCppRuntime.canInstall(in: prefix) }
                if !missing.isEmpty {
                    await MainActor.run { self.componentStatus[prefix.id] = "Getting \(game.name) ready…" }
                    do {
                        try await AppModel.installComponents(missing, into: prefix, runtime: runtime, backend: backend, downloads: downloads) { status in
                            Task { @MainActor in self.componentStatus[prefix.id] = status }
                        }
                        await MainActor.run { self.finishedComponents(in: prefix) }
                    } catch {
                        // The game still starts: Wine's own stand-ins are enough for many games.
                        await MainActor.run {
                            self.componentStatus[prefix.id] = nil
                            self.report(error, title: "Some Windows components were not installed")
                        }
                    }
                }
            }
            do {
                if needsVideo { try VideoPlayback.prepare(prefix: prefix, runtime: runtime, like: command) }
                if needsQuietCrashes {
                    // Not worth stopping the game for: without it a crash shows Wine's window, as before.
                    let session = LaunchSession(command: CrashDialog.turnOffCommand(like: command), logFile: nil)
                    if (try? session.start()) != nil { _ = session.waitUntilExit(timeout: 30) }
                }
                if needsDLSS { try MetalFXDLSS.installShims(from: runtime, into: prefix, runtimeIsManaged: managed) }
                if needsDLSS && !MetalFXDLSS.hasRegistryPath(prefix) {
                    let session = LaunchSession(command: MetalFXDLSS.registryCommand(like: command), logFile: nil)
                    try session.start()
                    guard session.waitUntilExit(timeout: 60) == .exited(code: 0) else {
                        throw AlloyError.launchFailed("Wine could not record where the DLSS → MetalFX shim is in \(prefix.name).")
                    }
                }
                await MainActor.run { self.preparing.remove(game.id); self.beginSession(game, command: command) }
            } catch {
                await MainActor.run { self.preparing.remove(game.id); self.report(error, title: "Could not prepare \(prefix.name) for \(game.name)") }
            }
        }
    }

    private func beginSession(_ game: Game, command: LaunchCommand) {
        appliedFix[game.id] = nil
        do {
            let session = try launcher.launch(gameID: game.id, gameName: game.name, command: command)
            FreezeCapture.watch(session)
            let backendKind = game.graphics.backend
            let store = GameStore.store(for: game)
            let started = Date()
            let usedDLSS = game.graphics.dlss && store == nil
            track(session, id: game.id) { [weak self] session in
                if usedDLSS, DLSSSafety.shouldTurnOff(after: session.state, ranFor: Date().timeIntervalSince(started)) {
                    self?.turnOffDLSSAfterCrash(game.id)
                }
                self?.findings[game.id] = DiagnosticService.analyze(log: session.fullLog, exitState: session.state,
                                                                    requestedGraphics: backendKind)
                // Games downloaded while the store app was open join the library.
                if store != nil { self?.importStoreGames() }
            }
            warnIfStoreBlocked(game)
        } catch { report(error, title: "Launch failed") }
    }

    /// A game that ended badly soon after starting with DLSS → MetalFX goes back to the game's own rendering
    /// next time, and the person is told so they can turn it on again.
    private func turnOffDLSSAfterCrash(_ id: UUID) {
        guard var game = game(id), game.graphics.dlss else { return }
        game.graphics.dlss = false
        save(game)
        alert = AlertItem(title: "DLSS → MetalFX turned off for \(game.name)",
                          message: "The game closed unexpectedly soon after starting, so next time it runs without MetalFX standing in for DLSS. If it crashes again, the cause is something else: you can turn MetalFX back on under Advanced settings on the game's page.")
    }

    /// Ends the game. When its launcher has already exited (Unreal Engine launchers do), the game is still
    /// running in its environment, so every process there is ended.
    func stop(_ game: Game) {
        if !launcher.stop(gameID: game.id), launcher.session(for: game.id)?.state.isRunning == true,
           let prefix = prefix(game.prefixID) {
            stopAll(in: prefix)
        }
    }

    /// Saves a backtrace of every thread in the running game's environment beside its log, then shows it in Finder.
    func saveThreadBacktraces(_ game: Game) {
        guard let session = sessions[game.id], session.state.isRunning, let log = session.logFile else { return }
        let report = FreezeCapture.reportURL(besideLog: log)
        session.note("Saving every thread’s backtrace to \(report.lastPathComponent)")
        Task.detached {
            do {
                try FreezeCapture.capture(like: session.command, to: report)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([report]) }
            } catch {
                await MainActor.run { self.report(error, title: "Could not save thread backtraces") }
            }
        }
    }

    func restart(_ game: Game) {
        guard let session = sessions[game.id] else { requestLaunch(game); return }
        stop(game)
        Task {
            _ = await session.waitForExit()
            requestLaunch(self.game(game.id) ?? game)
        }
    }

    private func track(_ session: LaunchSession, id: UUID, onExit: @escaping @MainActor (LaunchSession) -> Void) {
        sessions[id] = session
        states[id] = session.state
        logs[id] = session.lines
        findings[id] = nil
        Task {
            _ = await session.waitForExit()
            pullSessionOutput()
            onExit(session)
        }
    }

    private func pullSessionOutput() {
        var anyRunning = false
        let quiet = !NSApplication.shared.isActive && sessions.values.contains { $0.state.isRunning }
        for (id, session) in sessions {
            let state = session.state
            anyRunning = anyRunning || state.isRunning
            if states[id] != state { states[id] = state }
            // While a game is in front, Alloy redraws its output every 3 s instead of every 0.3 s, leaving the CPU to the game.
            if quiet && storePollTick % 10 != 0 { continue }
            if logs[id]?.last?.id != session.lines.last?.id { logs[id] = session.lines }
        }
        if storePollTick % 10 == 0 {
            let conditions = MacConditions.current
            if macConditions != conditions { macConditions = conditions }
        }
        metricsHotKey.isEnabled = anyRunning && settings.metricsShortcut
        // About every 3 s while a store app runs or a download is shown.
        storePollTick += 1
        if storePollTick % 10 == 1, !storeDownloads.isEmpty || gameInstallStores.contains(where: { store in
            storeEntry(store).map { sessions[$0.id]?.state.isRunning == true } ?? false }) {
            refreshStoreDownloads()
        }
    }

    func fullLog(for id: UUID) -> String { (logs[id] ?? []).map(\.text).joined(separator: "\n") }

    // MARK: Diagnostics & benchmarks

    func exportReport(for game: Game, to url: URL) {
        let runtime = runtime(for: game)
        let report = DiagnosticReport(game: game, runtime: runtime, prefix: prefix(game.prefixID), state: states[game.id],
                                      findings: findings[game.id] ?? DiagnosticService.preflight(game: game, runtime: runtime, prefix: prefix(game.prefixID)),
                                      log: fullLog(for: game.id))
        do { try report.write(to: url) } catch { self.report(error, title: "Export failed") }
    }

    func addBenchmark(_ run: BenchmarkRun, to game: Game) {
        do { try benchmarkStore.add(run, gameID: game.id); benchmarks = benchmarkStore.runs }
        catch { report(error, title: "Could not save benchmark") }
    }

    func removeBenchmark(_ run: BenchmarkRun, from game: Game) {
        try? benchmarkStore.remove(runID: run.id, gameID: game.id)
        benchmarks = benchmarkStore.runs
    }

    // MARK: Settings

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            // The components address may have changed; Setup reads it again.
            manifest = nil
            manifestError = nil
            library = GameLibrary(fileURL: settings.libraryLocation)
            games = library.games
            prefixManager = PrefixManager(storageRoot: settings.prefixStorageLocation)
            refreshPrefixes()
            refreshRuntimes()
        } catch { report(error, title: "Could not save settings") }
    }

    func report(_ error: Error, title: String) {
        alert = AlertItem(title: title, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    // MARK: Panels

    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFile(types: [String], prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = types.compactMap { .init(filenameExtension: $0) }
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseSaveLocation(name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url : nil
    }
}
