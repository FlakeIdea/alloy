import AppKit
import SwiftUI
import AlloyCore

struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var confirmRemove = false
    @State private var showAdvanced = false

    var traits: GameTraits? { model.traits[game.id] }

    var body: some View {
        let state = model.state(of: game.id)
        ScrollView {
            GameHero(game: game, state: state) { controls(state) }
            VStack(alignment: .leading, spacing: 18) {
                if !game.isApp, let traits, let upgrade = model.recommendedUpgrade(for: game, traits: traits) {
                    UpgradeBanner(game: game, choice: upgrade)
                }
                GettingReadyBanner(game: game, state: state)
                if let prefix = model.prefix(game.prefixID), let newest = model.engineUpdate(for: prefix) {
                    EngineUpdateBanner(prefix: prefix, newest: newest)
                } else if let package = model.engineDownloadUpdate {
                    EngineDownloadBanner(package: package)
                } else if let progress = model.engineProgress {
                    ProgressView(value: progress.fraction) { Text(progress.status).font(.callout) }
                        .padding(16).glassCard()
                }
                if let conditions = model.macConditions {
                    HStack(alignment: .top, spacing: 12) {
                        Icon(.alert).font(.title3).foregroundStyle(Theme.warning).frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Mac is running slower").font(.headline)
                            Text(conditions).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(16).glassCard()
                }
                StoreBanner(game: game)
                if model.steamMacVersion(of: game) {
                    HStack(alignment: .top, spacing: 12) {
                        Icon(.mac).font(.title3).foregroundStyle(Theme.accent).frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(game.name) has a Mac version").font(.headline)
                            Text("Steam lists a macOS version of this game. Installed with Steam for Mac, it runs without Wine, which is usually faster and more reliable than the Windows version here.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Get Steam for Mac") { NSWorkspace.shared.open(URL(string: "https://store.steampowered.com/about/")!) }
                            .buttonStyle(GhostCapsule())
                    }
                    .padding(16).glassCard()
                }
                ProblemsCard(game: game)
                AntiCheatNote(names: model.antiCheat[game.id] ?? [])
                if let traits, GraphicsDefaults.needsD3DMetal(traits.usage), !model.hasD3DMetal {
                    DirectX12Note()
                }
                GraphicsCard(game: game)

                Disclosure(title: "Advanced settings", isExpanded: $showAdvanced) {
                    VStack(spacing: 18) {
                        if let prefix = model.prefix(game.prefixID), !prefix.isReadOnly {
                            Panel("Windows components") {
                                VisualCppRow(prefix: prefix, gameNeedsIt: traits.map { WindowsComponent.needed(by: $0).contains(.visualCpp) } ?? false)
                                Divider()
                                DotNetRow(prefix: prefix, gameNeedsIt: traits?.isDotNet ?? false)
                            }
                        }
                        ExtraDLLsPanel(game: game)
                        // Rebuilt when settings change outside the editor (graphics card, faster-graphics switch).
                        GameEditor(game: game, traits: traits)
                            .id("\(game.id)-\(game.prefixID?.uuidString ?? "")-\(game.graphics.hashValue)")
                        Panel("Output") {
                            LogConsole(lines: model.logs[game.id] ?? []).frame(height: 260)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 36).padding(.top, 6).padding(.bottom, 36)
        }
        .task(id: game.executableURL) {
            let g = game, scans = model.scans
            let scanned = await Task.detached { scans.traits(for: g) }.value
            model.traits[g.id] = scanned
            // Store apps' folders hold no game; their games are checked by their logs.
            if GameStore.store(for: g) == nil {
                model.antiCheat[g.id] = await Task.detached { AntiCheat.detect(in: g.folder) }.value
            }
        }
        .confirmationDialog("Remove \(game.name) from Alloy?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { model.remove(game) }
        } message: {
            Text("Only the entry in Alloy is removed. The game's files and its environment (with saves) stay on disk.")
        }
    }

    @ViewBuilder func controls(_ state: LaunchState) -> some View {
        HStack(spacing: 10) {
            if state.isRunning {
                Button { model.stop(game) } label: { Label { Text("Stop") } icon: { GlyphView(glyph: .stop, size: 11) } }
                    .buttonStyle(PrimaryCapsule(tint: Theme.danger))
                Button { model.restart(game) } label: { Label { Text("Restart") } icon: { GlyphView(glyph: .restart, size: 12) } }
                    .buttonStyle(GhostCapsule())
            } else if model.preparing.contains(game.id) {
                Button {} label: { Label { Text("Getting Ready…") } icon: { GlyphView(glyph: .wait, size: 12) } }
                    .buttonStyle(PrimaryCapsule()).disabled(true)
            } else {
                Button { model.requestLaunch(game) } label: {
                    Label { Text(game.isApp ? "Open" : "Play") } icon: { GlyphView(glyph: .play, size: 11) }.padding(.horizontal, 10)
                }
                .buttonStyle(PrimaryCapsule())
                .keyboardShortcut(.defaultAction)
            }
            Button {
                popUpMenu([
                    MenuChoice(title: "Show Game Files in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.executableURL]) },
                    MenuChoice(title: "Diagnostics") { model.selectedGameID = game.id; model.showAdvanced(.diagnostics) },
                    MenuChoice(title: "Add DLL…") { model.chooseDLLs(for: game) },
                    MenuChoice(title: "Environment", enabled: model.prefix(game.prefixID) != nil,
                               children: model.prefix(game.prefixID).map { model.environmentMenu(for: $0) } ?? []),
                    MenuChoice(title: game.isApp ? "Move to Games" : "Move to Apps") {
                        var changed = game
                        changed.isApp.toggle()
                        if changed.isApp { changed.graphics.dlss = false }
                        model.save(changed)
                    },
                    MenuChoice(title: "Remove from Alloy…", destructive: true, separatorBefore: true) { confirmRemove = true },
                ])
            } label: { GlyphView(glyph: .more, size: 15).frame(width: 32, height: 32) }
                .buttonStyle(.flat)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
                .help("More")
        }
    }
}

/// The top of a game's page: its art across the width, the cover, the name and the main actions.
struct GameHero<Controls: View>: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let state: LaunchState
    @ViewBuilder var controls: Controls

    var body: some View {
        let images = model.cover(for: game)
        ZStack(alignment: .bottomLeading) {
            HeroBackdrop(images: images, name: game.name)
            HStack(alignment: .bottom, spacing: 26) {
                CoverArtView(images: images, name: game.name, isStore: GameStore.store(for: game) != nil && !StoreLibraryScanner.startsAGame(game))
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 10) {
                    StatusPill(state: state)
                    Text(game.name).font(.system(size: 36, weight: .heavy)).tracking(-0.9).lineLimit(2)
                    controls.padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36).padding(.bottom, 26)
        }
        .frame(height: 300)
        .overlay(alignment: .topLeading) {
            Button { model.selectedGameID = nil } label: {
                HStack(spacing: 6) { GlyphView(glyph: .back, size: 11, weight: 2); Text("Library") }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.flat)
            .keyboardShortcut("[", modifiers: .command)
            .padding(.leading, 36).padding(.top, 18)
        }
    }
}

/// Shown while the game's environment is being set up or its Windows components install.
/// For a store app, or a game that starts through one: what that means, and a warning when this network blocks the
/// store, which is the usual reason it cannot sign in.
struct StoreBanner: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        if let store = GameStore.store(for: game) {
            let status = model.storeConnectivity[store]
            let blocked = status.flatMap { StoreConnectivity.explanation($0, store: store) }
            HStack(alignment: .top, spacing: 12) {
                Icon(blocked == nil ? "bag.fill" : "wifi.exclamationmark")
                    .font(.title3).foregroundStyle(blocked == nil ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.warning))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(blocked == nil ? title(store) : (status == .offline ? "No internet connection" : "This network blocks \(store.displayName)"))
                        .font(.headline)
                    Text(blocked ?? detail(store)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if blocked != nil {
                    Button("Check Again") { model.checkStoreConnectivity([store]) }.secondaryAction()
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 18)
            .task(id: store) { if model.storeConnectivity[store] == nil { model.checkStoreConnectivity([store]) } }
        }
    }

    func title(_ store: GameStore) -> String {
        StoreLibraryScanner.startsAGame(game) ? "Starts through \(store.displayName)" : store.displayName
    }

    func detail(_ store: GameStore) -> String {
        StoreLibraryScanner.startsAGame(game)
            ? "\(store.displayName) opens first, signs you in and keeps the game up to date. Its settings here apply to the game too."
            : "Sign in here, then install games in \(store.displayName). Games you install appear in your library\(store == .steam || store == .epic ? "" : " once you add them with Add Game")."
    }
}

/// Anti-cheat the game ships, so a refused online mode is not a surprise.
struct AntiCheatNote: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Icon("shield.lefthalf.filled").font(.title3).foregroundStyle(Theme.gradient).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uses \(names.joined(separator: " and "))").font(.headline)
                    Text("Online modes protected by anti-cheat may refuse to run on a Mac; offline and single-player modes usually still work.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)
            .glassCard(cornerRadius: 18)
        }
    }
}

/// Shown for games that render only with DirectX 12 while D3DMetal isn't installed: they won't start without it.
struct DirectX12Note: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon("exclamationmark.triangle.fill").font(.title3).foregroundStyle(Theme.warning).frame(width: 26)
            VStack(alignment: .leading, spacing: 8) {
                Text("This game needs DirectX 12").font(.headline)
                Text("To play it, add Apple's D3DMetal. It comes with Apple's Game Porting Toolkit, which Alloy isn't allowed to include: download the toolkit from Apple, open its “Evaluation environment” disk image, accept Apple's licence, then choose the mounted volume.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("Get the Game Porting Toolkit", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
                    Spacer()
                    if model.importingD3DMetal { ProgressView().controlSize(.small) }
                    Button("Add D3DMetal…") { model.importD3DMetal() }.disabled(model.importingD3DMetal).secondaryAction()
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }
}

struct GettingReadyBanner: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let state: LaunchState

    var body: some View {
        if let id = game.prefixID, !state.isRunning {
            let status = model.componentStatus[id]
                ?? (model.state(of: id).isRunning ? "Setting up \(model.prefix(id)?.name ?? "the environment")… Play works once this finishes." : nil)
            if let status {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(status).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
            }
        }
    }
}

/// Problems from the last start, each with a one-click fix where Alloy has one.
struct ProblemsCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        let issues = (model.findings[game.id] ?? []).filter { $0.severity != .info }
        if !issues.isEmpty || model.appliedFix[game.id] != nil {
            Panel(issues.isEmpty ? "Fixed" : "What went wrong") {
                if let note = model.appliedFix[game.id] {
                    Label { Text(note) } icon: { Icon("checkmark.circle.fill") }.foregroundStyle(Theme.accentAlt)
                }
                ForEach(issues.prefix(3)) { finding in
                    HStack(alignment: .top) {
                        FindingRow(finding: finding)
                        Spacer()
                        let fixes = model.fixes(for: finding, game: game)
                        if let first = fixes.first {
                            VStack(alignment: .trailing, spacing: 6) {
                                Button(first.title) { model.apply(first, for: finding, game: game) }.primaryAction(Theme.accent)
                                if fixes.count > 1 {
                                    Menu("More Fixes") {
                                        ForEach(fixes.dropFirst(), id: \.self) { fix in
                                            Button(fix.title) { model.apply(fix, for: finding, game: game) }
                                        }
                                    }
                                    .menuStyle(.borderlessButton).fixedSize()
                                }
                            }
                        }
                    }
                }
                if issues.count > 3 {
                    Button("Show all \(issues.count)") { model.showAdvanced(.diagnostics) }
                }
            }
        }
    }
}

/// The simple graphics choice: a play mode, and compatibility mode for games the Metal paths cannot run.
struct GraphicsCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var confirmSharp = false

    /// The modes for this game and display, plus the game's current mode if this display would not offer it (Battery
    /// Saver chosen on a faster display), so the page still shows what is set.
    func playModes(caps: BackendCapabilities, current: PlayMode?) -> [PlayMode] {
        var modes = PlayMode.available(for: game.graphics.backend, capabilities: caps, displayRefreshRate: DisplayInfo.refreshRate())
        if let current, !modes.contains(current) { modes.insert(current, at: 0) }
        return modes
    }

    var body: some View {
        Panel("Graphics") {
            if let caps = model.capabilities(for: game) {
                let current = PlayMode.current(of: game.graphics)
                let modes = playModes(caps: caps, current: current)
                // Apps don't need game graphics modes, only the Compatibility switch.
                if !game.isApp {
                HStack(spacing: 12) {
                    ForEach(modes) { mode in
                        ModeTile(mode: mode, selected: current == mode) {
                            // Sharp upscales every frame, which can make a game at a high resolution lag: asked first.
                            if mode == .sharp && current != .sharp { confirmSharp = true } else { model.setPlayMode(mode, for: game) }
                        }
                    }
                }
                .alert("Use Sharp for \(game.name)?", isPresented: $confirmSharp) {
                    Button("Use Sharp") { model.setPlayMode(.sharp, for: game) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(sharpWarning(caps))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(current?.summary(displayRefreshRate: DisplayInfo.refreshRate())
                         ?? "Custom settings, changed under Advanced settings. Choosing a mode replaces them.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.sheet = .guide } label: { Label { Text("Which should I choose?") } icon: { Icon("questionmark.circle") } }
                        .buttonStyle(.flat).foregroundStyle(Theme.accentAlt).font(.callout)
                }
                Divider()
                // The store app itself (Steam's own window) has no game to upscale.
                if caps.metalFXUpscaling.contains(game.graphics.backend),
                   GameStore.store(for: game) == nil || StoreLibraryScanner.startsAGame(game) {
                    let sharp = current == .sharp
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MetalFX scaling")
                            Text(metalFXScalingNote(sharp: sharp)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("MetalFX scaling", isOn: Binding(get: { game.graphics.dlss && !sharp },
                                                                set: { model.setMetalFXScaling($0, for: game) }))
                            .toggleStyle(.switch).labelsHidden().disabled(sharp)
                    }
                    Divider()
                }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compatibility mode")
                        Text(game.isApp ? "Turn on if the app's window is blank or draws incorrectly."
                             : "Turn on if the game won't start or draws incorrectly. Slower than the default Metal graphics.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Compatibility mode", isOn: Binding(get: { game.graphics.backend.isCompatibilityMode },
                                                              set: { model.setCompatibilityMode($0, for: game) }))
                        .toggleStyle(.switch).labelsHidden()
                }
                // Store entries' files are the store app's, not the game's, so they say nothing about frame generation.
                if !game.isApp, let traits = model.traits[game.id], GameStore.store(for: game) == nil {
                    let status = FrameGeneration.status(traits: traits, graphics: game.graphics, capabilities: caps,
                                                        d3dMetal4Installed: model.hasD3DMetalFrameGeneration)
                    Divider()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Frame generation")
                            Text(status.summary).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if status == .switchAvailable, let choice = model.frameGenerationChoice(for: game, traits: traits) {
                            Button("Switch to D3DMetal") { model.applyUpgrade(choice, to: game) }
                        } else if status == .needsD3DMetal4 {
                            Button("Add D3DMetal…") { model.importD3DMetal() }
                        } else {
                            Icon(status == .available ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(status == .available ? Theme.accentAlt : Color.secondary)
                        }
                    }
                }
                Text("Graphics: \(game.graphics.backend.displayName), for \(game.graphics.backend.directXVersions)")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("Install the game engine from Setup to choose graphics settings.").foregroundStyle(Theme.warning)
            }
        }
    }
}

/// A newer game engine is installed than the one this game's environment runs on.
struct EngineUpdateBanner: View {
    @EnvironmentObject var model: AppModel
    let prefix: WinePrefix
    let newest: WineRuntime

    var body: some View {
        let others = model.games.filter { $0.prefixID == prefix.id }.count - 1
        HStack(alignment: .top, spacing: 12) {
            Icon("arrow.down.circle").font(.title3).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text("A newer game engine is installed").font(.headline)
                Text("The \(prefix.name) environment still runs on an older one. Updating it brings the engine's latest fixes\(others > 0 ? " to the \(others) other game\(others == 1 ? "" : "s") in it too" : ""). Games, saves and settings stay as they are.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Update Environment") { model.moveToNewestEngine(prefix) }
                .buttonStyle(GhostCapsule())
        }
        .padding(16).glassCard()
    }
}

/// A newer game engine can be downloaded.
struct EngineDownloadBanner: View {
    @EnvironmentObject var model: AppModel
    let package: RuntimePackage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon("arrow.down.circle").font(.title3).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text("Game engine update available").font(.headline)
                Text("\(package.name), with the latest fixes. \(RuntimeInstaller.megabytes(package.downloadBytes)) download. After it installs, Alloy offers to move this game's environment onto it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Install Update") { model.installEngine(package) }
                .buttonStyle(GhostCapsule())
        }
        .padding(16).glassCard()
    }
}

extension GraphicsCard {
    func sharpWarning(_ caps: BackendCapabilities) -> String {
        var parts = ["Sharp uses Apple MetalFX to upscale every frame to your display's full Retina resolution."]
        if game.graphics.dlss && caps.metalFXUpscaling.contains(game.graphics.backend) {
            parts.append("It turns off MetalFX scaling, so the picture isn't upscaled twice.")
        }
        parts.append("If you set a high resolution in the game, upscaling it as well can make the game lag.")
        parts.append("Use Sharp only when the game doesn't run well at a high resolution and you want it to look sharper: choose a lower resolution in the game, and Sharp scales it up.")
        return parts.joined(separator: " ")
    }

    func metalFXScalingNote(sharp: Bool) -> String {
        if sharp { return "Off while Sharp is on: Sharp already upscales every frame with MetalFX." }
        var note = "Games that support NVIDIA DLSS use Apple MetalFX upscaling instead: turn on DLSS in the game's graphics settings. Turn this off if the game looks scaled or blurry."
        if let traits = model.traits[game.id], GameStore.store(for: game) == nil, !traits.dlss.contains(.upscaling) {
            note += " No DLSS files were found in this game's folder, so it may make no difference here."
        }
        return note
    }
}

struct ModeTile: View {
    let mode: PlayMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlyphView(glyph: mode.glyph, size: 20, weight: 1.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName).font(.system(size: 14, weight: .bold))
                    Text(selected ? "On" : "Off").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
                        .textCase(.uppercase).opacity(0.6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.flat)
        .foregroundStyle(selected ? Theme.onFill : Color.primary)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.03))))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(selected ? 0.0 : 0.1)))
        .animation(.smooth(duration: 0.2), value: selected)
    }
}

/// Wine Mono in one environment: installed, or a one-click install (confirmed first: it downloads from WineHQ).
struct DotNetRow: View {
    @EnvironmentObject var model: AppModel
    let prefix: WinePrefix
    var gameNeedsIt = false
    @State private var confirm = false

    var body: some View {
        let installed = WindowsComponent.dotNet.isInstalled(in: prefix)
        let status = model.componentStatus[prefix.id]
        HStack(alignment: .top, spacing: 12) {
            Icon(installed ? "checkmark.seal.fill" : "shippingbox")
                .foregroundStyle(installed ? Theme.success : (gameNeedsIt ? Theme.warning : Color.secondary))
            VStack(alignment: .leading, spacing: 3) {
                Text(WindowsComponent.dotNet.displayName).bold()
                Text(installed ? "Installed in \(prefix.name)."
                     : gameNeedsIt ? "This game is a .NET program, so it needs this." : "Only for games and launchers written in C# or XNA.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status == nil && !installed {
                Button("Install .NET Support…") { confirm = true }.disabled(!prefix.isInitialized())
            }
        }
        .confirmationDialog("Install .NET support in “\(prefix.name)”?", isPresented: $confirm) {
            Button("Download from WineHQ and Install") { model.install([.dotNet], into: prefix) }
        } message: {
            Text("Alloy downloads Wine Mono (about 80 MB) from dl.winehq.org, checks it against the checksum built into this Wine, and installs it in this environment with Wine's msiexec.")
        }
    }
}

/// Microsoft's Visual C++ runtime in one environment: its version, or an Install button (confirmed first, because it
/// downloads and runs Microsoft's installer).
struct VisualCppRow: View {
    @EnvironmentObject var model: AppModel
    let prefix: WinePrefix
    var gameNeedsIt = false
    @State private var confirm = false

    var body: some View {
        let version = model.visualCppVersion(in: prefix)
        let status = model.componentStatus[prefix.id]
        HStack(alignment: .top, spacing: 12) {
            Icon(version == nil ? "shippingbox" : "checkmark.seal.fill")
                .foregroundStyle(version == nil ? (gameNeedsIt ? Theme.warning : Color.secondary) : Theme.success)
            VStack(alignment: .leading, spacing: 3) {
                Text("Microsoft Visual C++ 2015–2022 runtime").bold()
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                } else if let version {
                    Text("Installed in \(prefix.name) (\(version)).").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(gameNeedsIt ? "This game comes with Microsoft's installer, so it most likely needs it. Games without it ask for “Visual C++” or report a missing MSVCP140.dll."
                                     : "Needed by most recent games. Games without it ask for “Visual C++” or report a missing MSVCP140.dll.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if status != nil {
                ProgressView().controlSize(.small)
            } else if version == nil {
                Button("Install Visual C++…") { confirm = true }
                    .disabled(!prefix.isInitialized())
                    .primaryAction(gameNeedsIt ? Theme.accent : Theme.accentAlt)
            }
        }
        .confirmationDialog("Install Visual C++ in “\(prefix.name)”?", isPresented: $confirm) {
            Button("Download from Microsoft and Install") { model.installVisualCpp(into: prefix) }
        } message: {
            Text(VisualCppRuntime.canInstall(in: prefix) ? confirmText
                 : "\(prefix.name) cannot run 32-bit programs, which Microsoft's installer needs. Use a new environment for this game, then install Visual C++ there.")
        }
    }

    var confirmText: String {
        let missing = VisualCppRuntime.Architecture.allCases.filter { VisualCppRuntime.verifiedInstaller($0, in: model.visualCppDownloads) == nil }
        let download = missing.isEmpty ? "Microsoft's installers are already downloaded and verified."
            : "Alloy downloads Microsoft's Visual C++ 2015–2022 Redistributable (\(missing.map { "\($0.rawValue) about \($0.approximateMegabytes) MB" }.joined(separator: ", "))) from microsoft.com and checks it against the checksum Microsoft publishes in its download address."
        return download + " It then runs Microsoft's installer silently in this environment (64-bit and 32-bit) and tells Wine to use Microsoft's DLLs. Other games in this environment can use it too."
    }
}

/// Offers to move a game off a slow graphics path onto the one Alloy measured fastest.
struct UpgradeBanner: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let choice: GraphicsDefaults.Choice

    var body: some View {
        let target = choice.backend == .dxmt ? "DXMT" : "D3DMetal"
        let needsNewEnvironment = model.prefix(game.prefixID)?.runtimeID != choice.runtime?.id
        HStack(alignment: .top, spacing: 14) {
            Icon(choice.frameGeneration ? "square.stack.3d.forward.dottedline.fill" : "bolt.fill")
                .font(.title2).foregroundStyle(Theme.accentAlt)
            VStack(alignment: .leading, spacing: 6) {
                if choice.frameGeneration {
                    Text("Frame generation available").font(.headline)
                    Text("\(game.name) ships NVIDIA DLSS Frame Generation. On D3DMetal 4 it runs as Apple MetalFX frame generation, made from the game's own motion data, for up to twice the frames on screen. After switching, turn on DLSS Frame Generation in the game's graphics settings. It works best when the game already runs at 40 FPS or more, and adds a little input delay. Not yet tested in a game in Alloy.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Faster graphics available").font(.headline)
                    Text([.dxmt, .d3dMetal].contains(game.graphics.backend)
                         ? "\(game.name) is set to \(game.graphics.backend.displayName), but the engine in its environment doesn't include it, so it runs with slower graphics. \(choice.reason)"
                         : "\(game.name) is set to \(game.graphics.backend.displayName), which is far slower than Metal. \(choice.reason)")
                        .foregroundStyle(.secondary)
                }
                if needsNewEnvironment, let runtime = choice.runtime {
                    Text("Switching makes a new environment on \(runtime.displayName). The current environment stays on disk with its saves.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button("Switch to \(target)") { model.applyUpgrade(choice, to: game) }
                    .controlSize(.large).primaryAction(Theme.accent)
                if choice.frameGeneration {
                    Button("Not now") { model.declineFrameGeneration(for: game) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }
}

/// Edits a game's configuration. Only options the selected runtime supports are shown.
struct GameEditor: View {
    @EnvironmentObject var model: AppModel
    let traits: GameTraits?
    @State private var draft: Game
    @State private var argumentText: String
    @State private var newEnvKey = ""
    @State private var newEnvValue = ""
    @State private var candidates: [ExecutableScanner.Candidate] = []

    init(game: Game, traits: GameTraits? = nil) {
        self.traits = traits
        _draft = State(initialValue: game)
        _argumentText = State(initialValue: ArgumentParser.join(game.arguments))
    }

    var body: some View {
        let caps = model.capabilities(for: draft)
        VStack(spacing: 18) {
            Panel("Game") {
                Form {
                    TextField("Name", text: $draft.name)
                    Picker("Executable", selection: $draft.executableRelativePath) {
                        Text(draft.executableRelativePath).tag(draft.executableRelativePath)
                        ForEach(candidates.filter { $0.relativePath != draft.executableRelativePath }, id: \.relativePath) {
                            Text($0.relativePath).tag($0.relativePath)
                        }
                    }
                    Picker("Environment", selection: $draft.prefixID) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.ownPrefixes) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Wine runtime", selection: $draft.runtimeID) {
                        Text("Default").tag(String?.none)
                        ForEach(model.runtimes) { Text($0.displayName).tag(String?.some($0.id)) }
                    }
                    TextField("Launch arguments", text: $argumentText, prompt: Text("e.g. -dx11 -windowed"))
                    HStack {
                        Text("Artwork")
                        Spacer()
                        Button("Choose Image…") {
                            if let url = AppModel.chooseFile(types: ["png", "jpg", "jpeg", "webp", "ico", "bmp"], prompt: "Use Image") {
                                draft.artwork = url
                            }
                        }
                        if draft.artwork != nil { Button("Clear") { draft.artwork = nil } }
                    }
                }
            }

            Panel("Graphics & performance") {
                if let caps {
                    Form {
                        Picker("Graphics backend", selection: $draft.graphics.backend) {
                            ForEach(GraphicsBackendKind.allCases.filter { caps.status(of: $0).isUsable }) { kind in
                                Text("\(kind.displayName) — \(kind.directXVersions)").tag(kind)
                            }
                        }
                        if case .experimental(let note) = caps.status(of: draft.graphics.backend) {
                            Label { Text(note) } icon: { Icon("exclamationmark.triangle") }.font(.caption).foregroundStyle(Theme.warning)
                        }
                        Picker("Preset", selection: $draft.graphics.preset) {
                            ForEach(QualityPreset.allCases) { Text($0.displayName).tag($0) }
                        }
                        Text(draft.graphics.preset.summary).font(.caption).foregroundStyle(.secondary)
                        Picker("Target frame rate", selection: $draft.graphics.targetFPS) {
                            ForEach(targetChoices(current: draft.graphics.targetFPS), id: \.self) { fps in
                                Text("\(fps) FPS (\(String(format: "%.2f", 1000.0 / Double(fps))) ms)").tag(fps)
                            }
                        }
                        if FrameRateCap.isSupported(by: draft.graphics.backend) {
                            Picker("Frame rate cap", selection: $draft.graphics.frameRateCap) {
                                Text("Display maximum (\(DisplayInfo.refreshRate()) FPS)").tag(FrameRateCap.displayMaximum)
                                ForEach(frameCapChoices(current: draft.graphics.frameRateCap), id: \.self) { fps in
                                    Text("\(fps) FPS").tag(FrameRateCap.fixed(fps))
                                }
                                Text("Off").tag(FrameRateCap.off)
                            }
                            Text("A game that renders faster than the display shows its frames unevenly, which looks like stutter. The display maximum is the smoothest; the in-game limit can stay on Unlimited.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Force DirectX 11 (-dx11, Unreal Engine)", isOn: $draft.graphics.forceDX11)
                        if caps.metalFXUpscaling.contains(draft.graphics.backend) {
                            Toggle("DLSS → MetalFX", isOn: $draft.graphics.dlss)
                            Text(dlssNote(caps)).font(.caption).foregroundStyle(.secondary)
                        }
                        if caps.metalFXSpatialUpscaling.contains(draft.graphics.backend) {
                            Picker("MetalFX upscaling", selection: $draft.graphics.metalFXSpatialFactor) {
                                Text("Off").tag(Double?.none)
                                ForEach(spatialFactorChoices(current: draft.graphics.metalFXSpatialFactor), id: \.self) { factor in
                                    Text(MetalFXSpatialUpscaling.displayName(factor)).tag(Double?.some(factor))
                                }
                            }
                            Text(spatialNote).font(.caption).foregroundStyle(.secondary)
                        }
                        if caps.supportsMetalHUD {
                            Toggle("Show metrics when the game starts", isOn: $draft.graphics.metalHUD)
                            Text(model.settings.metricsShortcut
                                 ? "Metrics show FPS, frame time, memory and resolution. Press \(MetricsHotKey.display) while playing to show or hide them. \(MetricsHUD.resolutionHelp)"
                                 : "Metrics show FPS, frame time, memory and resolution. Turn on the metrics shortcut in Settings to show them while playing. \(MetricsHUD.resolutionHelp)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if caps.supportsAVXAdvertisement {
                            Toggle("Advertise AVX to the game (Rosetta 2)", isOn: $draft.graphics.advertiseAVX)
                        }
                        if caps.syncModes.count > 1 {
                            Picker("Synchronisation", selection: $draft.graphics.syncMode) {
                                ForEach(caps.syncModes, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                        if draft.graphics.backend == .dxvk {
                            TextField("DXVK shader cache folder", text: Binding(
                                get: { draft.graphics.shaderCachePath ?? "" },
                                set: { draft.graphics.shaderCachePath = $0.isEmpty ? nil : $0 }))
                        }
                    }
                    Text("These are launch-level settings. In-game settings (shadows, textures, resolution) are set inside the game; the Performance page records and compares them.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Install a Wine runtime to see the graphics options it supports.").foregroundStyle(Theme.warning)
                }
            }

            Panel("Environment variables (advanced)") {
                Label { Text("Advanced: wrong values can stop a game from starting. DYLD_* and Alloy-managed variables are blocked.") } icon: { Icon("exclamationmark.triangle") }.font(.caption).foregroundStyle(Theme.warning)
                ForEach(draft.environment.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).font(.system(.body, design: .monospaced))
                        Text("=")
                        Text(draft.environment[key] ?? "").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Button { draft.environment[key] = nil } label: { Icon("minus.circle") }.buttonStyle(.flat)
                    }
                }
                HStack {
                    TextField("NAME", text: $newEnvKey).frame(width: 200)
                    TextField("value", text: $newEnvValue)
                    Button("Add") {
                        let key = newEnvKey.trimmingCharacters(in: .whitespaces)
                        do {
                            try EnvironmentValidator.validate([key: newEnvValue])
                            draft.environment[key] = newEnvValue
                            newEnvKey = ""; newEnvValue = ""
                        } catch { model.report(error, title: "Invalid variable") }
                    }
                    .disabled(newEnvKey.isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Revert") { revert() }.disabled(!hasChanges)
                Button("Save Changes") { save() }
                    .primaryAction(Theme.accent).disabled(!hasChanges)
            }
        }
        .task(id: draft.id) {
            let folder = draft.folder
            candidates = await Task.detached { ExecutableScanner.scan(folder: folder) }.value
        }
    }

    var original: Game? { model.game(draft.id) }

    /// Targets this display can show, plus a saved one that is not in the list.
    func targetChoices(current: Int) -> [Int] {
        let rate = DisplayInfo.refreshRate()
        var choices = [30, 40, 60, 90, 120, 144, 165, 240].filter { $0 <= rate }
        if !choices.contains(current) { choices.append(current); choices.sort() }
        return choices
    }

    /// Fixed caps below the display's rate (the display maximum covers its own rate, and a cap above it does nothing),
    /// plus a saved value that is not in the list.
    func frameCapChoices(current: FrameRateCap) -> [Int] {
        let rate = DisplayInfo.refreshRate()
        var choices = [30, 40, 60, 90, 120, 144, 165, 240].filter { $0 < rate }
        if case .fixed(let fps) = current, !choices.contains(fps) { choices.append(fps); choices.sort() }
        return choices
    }

    /// Factors offered in the picker, plus a saved one that is not in the list.
    func spatialFactorChoices(current: Double?) -> [Double] {
        var choices = MetalFXSpatialUpscaling.factors
        if let current, !choices.contains(current) { choices.append(current); choices.sort() }
        return choices
    }

    var spatialNote: String {
        // Measured on an M4 with a DXMT test at 1800×1169: 91 FPS without, 78 with 2×; 137 FPS at 1200×778 with 3×.
        var parts = ["For games without DLSS. MetalFX upscales every frame to this many times the game's resolution before the display shows it. That costs about 2 ms of GPU time per frame at full Retina size."]
        if let d = DisplayInfo.pointSizeAndScale(), d.scale > 1 {
            let w = d.width * 2 / 3 / 2 * 2, h = d.height * 2 / 3 / 2 * 2
            parts.append("At the game's usual \(d.width)×\(d.height), \(d.scale)× fills this Retina display pixel for pixel: sharper, a little slower.")
            parts.append("For more FPS, lower the in-game resolution to about \(w)×\(h) and choose 3×: under half the pixels to render, about 50% more FPS in a GPU-bound test.")
        } else {
            parts.append("The frame rate rises only when you lower the in-game resolution.")
        }
        if draft.graphics.dlss { parts.append("If the game's DLSS is on, use that instead: both together upscale twice.") }
        return parts.joined(separator: " ")
    }

    func dlssNote(_ caps: BackendCapabilities) -> String {
        var parts = ["Games that support NVIDIA DLSS use Apple MetalFX upscaling instead, as CrossOver's game bottles do. Turn DLSS on in the game's graphics settings."]
        if caps.metalFXFrameGeneration.contains(draft.graphics.backend) {
            parts.append("DLSS Frame Generation runs as MetalFX frame interpolation (DirectX 12 games).")
        } else if traits?.dlss.contains(.frameGeneration) == true {
            parts.append("This game also has DLSS Frame Generation; on this Mac that needs D3DMetal 4 with DirectX 12 (turn off Force DirectX 11).")
        }
        if let traits {
            parts.append(traits.dlss.isDisjoint(with: [.upscaling, .frameGeneration]) ? "No DLSS files were found in this game's folder."
                         : "This game ships \(traits.dlss.contains(.frameGeneration) ? "DLSS and DLSS Frame Generation" : "DLSS").")
        }
        return parts.joined(separator: " ")
    }

    /// Applies only user-editable fields onto the latest stored game, so launch bookkeeping
    /// (last played, confirmed fingerprint) made while editing is not overwritten.
    var merged: Game? {
        guard var g = original else { return nil }
        g.name = draft.name
        g.executableRelativePath = draft.executableRelativePath
        g.prefixID = draft.prefixID
        g.runtimeID = draft.runtimeID
        g.arguments = ArgumentParser.split(argumentText)
        g.environment = draft.environment
        g.graphics = draft.graphics
        g.artwork = draft.artwork
        g.notes = draft.notes
        return g
    }

    var hasChanges: Bool { merged.map { $0 != original } ?? false }

    func save() {
        if let merged { model.save(merged) }
    }

    func revert() {
        guard let original else { return }
        draft = original
        argumentText = ArgumentParser.join(original.arguments)
    }
}

/// DLLs the person added to this game's environment, and the button to add more.
struct ExtraDLLsPanel: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        Panel("Extra DLLs") {
            Text("When a program says a DLL is missing, add the file here and Alloy puts it in this environment and tells Wine to use it. Use the file from the program's own installer or its maker: DLL download websites often spread malware. Windows drivers (.sys) can't be used, because Wine can't load drivers.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if game.customDLLs.isEmpty {
                Text("None added.").font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(game.customDLLs) { dll in
                    HStack(spacing: 10) {
                        Icon(.box).foregroundStyle(.secondary)
                        Text(dll.name).font(.system(.callout, design: .monospaced))
                        Text(dll.architectureName).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { model.removeDLL(dll, from: game) }.secondaryAction()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Add DLL…") { model.chooseDLLs(for: game) }.secondaryAction()
                    .disabled(model.prefix(game.prefixID)?.isReadOnly ?? true)
            }
        }
    }
}
