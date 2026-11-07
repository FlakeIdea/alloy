import AppKit
import SwiftUI
import AlloyCore

/// Everything a Mac needs before Windows games run, as one-click steps: the game engine (Wine with DXMT and video
/// playback), the Windows components games ask for, and optional extras.
struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmStore: GameStore?
    @State private var confirmRosetta = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Setup", subtitle: model.hasGameEngine ? "Your Mac is ready for Windows games." : "One download, then add your games.") {
                    if model.setupStepsLeft > 0 {
                        Button("Install Everything…") { model.sheet = .wizard(.install) }.controlSize(.large).primaryAction()
                    } else {
                        Button("Check Everything…") { model.sheet = .wizard(.install) }.secondaryAction()
                    }
                }
                .padding(.horizontal, -28).padding(.top, -28)
                if !model.rosettaInstalled { rosettaCard }
                EngineCard()
                componentsCard
                d3dMetalCard
                storesCard
                SetupCard(symbol: "slider.horizontal.3", title: "Graphics Guide", status: "Guide", ready: true) {
                    Text("Six short steps: which graphics mode to pick, and what to change in the game's own settings.")
                        .foregroundStyle(.secondary)
                    HStack { Spacer(); Button("Open the Graphics Guide") { model.sheet = .guide }.secondaryAction() }
                }
            }
            .padding(28)
        }
        .onAppear { if model.manifest == nil { model.loadManifest() } }
        .alert("Install \(confirmStore?.displayName ?? "")?", isPresented: Binding(get: { confirmStore != nil }, set: { if !$0 { confirmStore = nil } }),
               presenting: confirmStore) { store in
            Button("Install") { model.installStore(store) }
            Button("Cancel", role: .cancel) {}
        } message: { store in
            Text(installMessage(store))
        }
    }

    var rosettaCard: some View {
        SetupCard(symbol: "arrow.triangle.2.circlepath.circle.fill", title: "Rosetta 2", status: "Required", ready: false) {
            Text("The game engine is built for Intel processors and runs through Rosetta 2, Apple's free translator. This Mac doesn't have it yet.")
                .foregroundStyle(.secondary)
            HStack {
                if model.installingRosetta { ProgressView().controlSize(.small); Text("Installing Rosetta 2…").foregroundStyle(.secondary) }
                Spacer()
                Button("Install Rosetta…") { confirmRosetta = true }
                    .disabled(model.installingRosetta).controlSize(.large).primaryAction(Theme.accent)
            }
        }
        .alert("Install Rosetta 2?", isPresented: $confirmRosetta) {
            Button("Agree and Install") { model.installRosetta() }
            Button("Read the Licence") { NSWorkspace.shared.open(Rosetta.licenceURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rosetta 2 is Apple software. Choosing “Agree and Install” means you accept Apple's licence for it, and macOS downloads it from Apple. macOS may ask for your password.")
        }
    }

    var componentsCard: some View {
        SetupCard(symbol: "puzzlepiece.extension.fill", title: "Windows components",
                  status: model.settings.autoInstallComponents ? "Automatic" : "Manual",
                  ready: model.settings.autoInstallComponents) {
            Text("Games often need parts of Windows that Wine doesn't include. Alloy looks at each game's files and installs what it needs into that game's environment before its first start.")
                .foregroundStyle(.secondary)
            ForEach(WindowsComponent.allCases) { component in
                Label { VStack(alignment: .leading, spacing: 2) {
                    Text(component.displayName).bold()
                    Text(component.summary).font(.caption).foregroundStyle(.secondary)
                } } icon: { Icon("checkmark.circle").foregroundStyle(Theme.accentAlt) }
            }
            Toggle("Install what games need automatically", isOn: Binding(
                get: { model.settings.autoInstallComponents },
                set: { model.settings.autoInstallComponents = $0; model.saveSettings() }))
        }
    }

    var d3dMetalCard: some View {
        let has = model.hasD3DMetal
        return SetupCard(symbol: "cpu", title: "DirectX 12 games (optional)", status: has ? "Installed" : "Not installed", ready: has) {
            Text("DirectX 12 games need Apple's D3DMetal, part of Apple's Game Porting Toolkit. Apple doesn't allow it to be redistributed, so you add it yourself: download the toolkit from developer.apple.com, open its “Evaluation environment” disk image, accept Apple's licence, then click Add D3DMetal: Alloy finds it by itself. If you already have Game Porting Toolkit installed, Alloy finds that too. On Macs without it, DirectX 12 games use Wine's vkd3d instead (experimental).")
                .foregroundStyle(.secondary)
            HStack {
                if model.importingD3DMetal { ProgressView().controlSize(.small); Text("Adding D3DMetal…").foregroundStyle(.secondary) }
                Spacer()
                Button("Add D3DMetal…") { model.importD3DMetal() }.disabled(model.importingD3DMetal).secondaryAction()
            }
        }
    }

    func installMessage(_ store: GameStore) -> String {
        let how = store.installerArguments.isEmpty
            ? "runs it there; follow its steps, then sign in."
            : "installs it there. On first start it may download an update, then asks you to sign in."
        let size = store == .steam ? " (about 2 MB)" : store == .ea ? " (about 2 MB)" : ""
        return "Alloy downloads \(store.installerFileName)\(size) from \(store.vendor), makes a “\(store.environmentName)” environment on the game engine and \(how) Games you install there appear in your library."
    }

    /// Steam, Epic and the other stores: install each one's own app, and see whether this network lets it sign in.
    var storesCard: some View {
        let installed = GameStore.allCases.filter { model.storeEntry($0) != nil }
        return SetupCard(symbol: "bag.fill", title: "Game stores (optional)",
                         status: installed.isEmpty ? "None installed" : "\(installed.count) installed", ready: !installed.isEmpty) {
            Text("Buy, download and update games in each store’s own app. Games you install in Steam or the Epic Games Launcher appear in your library.")
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(GameStore.allCases) { store in
                    storeRow(store)
                    if store != GameStore.allCases.last { Divider().opacity(0.4) }
                }
            }
            HStack {
                if model.checkingStores { ProgressView().controlSize(.small); Text("Checking this network…").foregroundStyle(.secondary) }
                Spacer()
                Button("Check Network") { model.checkStoreConnectivity() }.disabled(model.checkingStores).secondaryAction()
            }
        }
        .onAppear { if model.storeConnectivity.isEmpty { model.checkStoreConnectivity() } }
    }

    func storeRow(_ store: GameStore) -> some View {
        let installed = model.storeEntry(store) != nil
        let status = model.storeInstallStatus[store]
        let network = model.storeConnectivity[store]
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayName).font(.headline)
                Text(store.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let network, network != .reachable {
                    Label { Text(network == .offline ? "No internet connection" : "Blocked by this network: sign-in will fail") } icon: { Icon("exclamationmark.triangle.fill") }
                        .font(.caption.bold()).foregroundStyle(Theme.warning)
                        .help(StoreConnectivity.explanation(network, store: store) ?? "")
                }
                if let status {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            if installed {
                Text("In your library").font(.caption.bold()).foregroundStyle(Theme.success).padding(.top, 2)
            } else {
                Button("Install…") { confirmStore = store }
                    .disabled(!model.hasGameEngine || status != nil).secondaryAction()
            }
        }
        .padding(.vertical, 9)
    }
}

/// The game engine: installed version, or a one-click download with progress.
struct EngineCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ready = model.hasGameEngine
        SetupCard(symbol: "bolt.fill", title: "Game engine", status: ready ? "Installed" : "Required", ready: ready) {
            Text("Wine with DXMT, which turns DirectX 10 and 11 into Apple Metal, plus video playback and MetalFX upscaling. Everything in it is open source.")
                .foregroundStyle(.secondary)
            if let progress = model.engineProgress {
                ProgressView(value: progress.fraction) { Text(progress.status).font(.callout) }
            } else if let package = model.manifest?.runtimes.first {
                let installed = model.installedPackages[package.id] != nil
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name).bold()
                        Text(installed ? "Installed. Version \(package.version)."
                             : "\(RuntimeInstaller.megabytes(package.downloadBytes)) download, \(RuntimeInstaller.megabytes(package.installedBytes)) on disk.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !installed {
                        Button(ready ? "Install Update" : "Install") { model.installEngine(package) }
                            .controlSize(.large).primaryAction(Theme.accent)
                    }
                }
            } else if let error = model.manifestError, !(ready && model.settings.componentsURL == nil) {
                // A build without a download address has nothing to retry; with an engine installed it has nothing to say.
                Text(error).font(.callout).foregroundStyle(ready ? Color.secondary : Theme.warning)
                HStack {
                    if model.settings.componentsURL != nil { Button("Try Again") { model.loadManifest() } }
                    Spacer()
                    Button("Install from Package File…") {
                        if let file = AppModel.chooseFile(types: ["xz"], prompt: "Install") { model.installEngine(fromArchive: file) }
                    }
                }
            } else if !ready {
                HStack { ProgressView().controlSize(.small); Text("Checking for the latest game engine…").foregroundStyle(.secondary) }
            }
            if ready, let runtime = model.runtimes.first(where: { model.backend.capabilities(of: $0).status(of: .dxmt).isUsable }) {
                Label { Text(runtime.displayName) } icon: { Icon("checkmark.seal.fill") }.font(.callout).foregroundStyle(Theme.success)
            }
        }
    }
}

struct SetupCard<Content: View>: View {
    let symbol: String
    let title: String
    let status: String
    let ready: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Icon(symbol).font(.title).foregroundStyle(Theme.gradient).frame(width: 40)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.title3.bold())
                    Spacer()
                    Text(status).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill((ready ? Theme.success : Theme.warning).opacity(0.16)))
                        .foregroundStyle(ready ? Theme.success : Theme.warning)
                }
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }
}

/// Environments, diagnostics, performance and settings: everything a first-time user does not need.
struct AdvancedView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.advancedTab) {
                ForEach(AdvancedTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            .padding(.top, 24)
            Group {
                switch model.advancedTab {
                case .environments: EnvironmentsView()
                case .diagnostics: DiagnosticsView()
                case .performance: PerformanceView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
