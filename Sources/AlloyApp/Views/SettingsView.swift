import SwiftUI
import AlloyCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = AppSettings()
    @State private var loaded = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Settings", subtitle: "Defaults for all games")
                    .padding(.horizontal, -28)
                Panel("About Alloy") {
                    HStack {
                        Text("Version \(Flake.displayVersion)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Graphics Guide") { model.sheet = .guide }
                        Button("Terms & Privacy") { model.sheet = .terms }
                        Button("Licences") { model.sheet = .licences }
                    }
                    Text("Alloy is independent and not affiliated with CodeWeavers, Apple, Microsoft, Valve, Epic Games or any game store or publisher. Their names are used only to describe compatibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel("Compatibility backend") {
                    Form {
                        Picker("Default Wine runtime", selection: $draft.defaultRuntimeID) {
                            Text("First available").tag(String?.none)
                            ForEach(model.runtimes) { Text($0.displayName).tag(String?.some($0.id)) }
                        }
                        Picker("Logging level", selection: $draft.logLevel) {
                            ForEach(LogLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        Text("Sets WINEDEBUG=\(draft.logLevel.wineDebug). Verbose logging can reduce game performance.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Panel("Playing") {
                    Toggle("Show or hide game metrics with \(MetricsHotKey.display)", isOn: $draft.metricsShortcut)
                    Text("Metrics (FPS, frame time, memory, and the rendering and scaled resolution) start hidden. While a game runs, \(MetricsHotKey.display) works even when the game is in front. With this off, games start without the metrics overlay loaded.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Keep Steam in the background while you play", isOn: $draft.steamInBackground)
                    Text("While a game runs, Steam in the same environment gets the lowest priority and the Mac's efficiency cores, so it can't take processor time from the game. Steam keeps working, only slower to respond. It gets its normal priority back when you quit the game.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel("Game saves") {
                    Toggle("Back up game saves before big changes", isOn: Binding(
                        get: { draft.backsUpSaves }, set: { draft.backupSaves = $0 }))
                    Text(SaveBackups.settingHelp).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Show Backups in Finder") { model.revealSaveBackups() }
                        Spacer()
                    }
                }
                Panel("Updates") {
                    HStack {
                        Toggle("Check for new versions of Alloy every day", isOn: $draft.checkForUpdates)
                        Spacer()
                        Button("Check Now") { openWindow(id: "updates"); Task { await Updater.shared.check() } }
                    }
                    Text("The check asks flake.co.in for the latest version number and sends nothing about you or your Mac. Nothing is installed until you click Install.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel("Downloads") {
                    Toggle("Install the Windows components games need automatically", isOn: $draft.autoInstallComponents)
                    TextField("Components address (components.json)", text: Binding(
                        get: { draft.componentsURLOverride?.absoluteString ?? "" },
                        set: { draft.componentsURLOverride = $0.isEmpty ? nil : URL(string: $0) }),
                              prompt: Text(Bundle.main.object(forInfoDictionaryKey: "AlloyComponentsURL") as? String ?? "Not set in this build"))
                    Text("Leave the address empty to use the one this release was built with. Set it to test a release folder before uploading it, for example http://127.0.0.1:8765/components.json.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel("Locations") {
                    locationRow("Library file", draft.libraryLocation.path) {
                        if let dir = AppModel.chooseFolder(prompt: "Store Library Here") {
                            draft.libraryLocation = dir.appendingPathComponent("library.json")
                        }
                    }
                    locationRow("Environment storage", draft.prefixStorageLocation.path) {
                        if let dir = AppModel.chooseFolder(prompt: "Store Environments Here") { draft.prefixStorageLocation = dir }
                    }
                    locationRow("DXVK-macOS build (optional)", draft.dxvkLocation?.path ?? "Not set") {
                        if let dir = AppModel.chooseFolder(prompt: "Use This DXVK Folder") { draft.dxvkLocation = dir }
                    }
                    Text("Changing a location does not move existing data. DXVK must be a build you downloaded yourself (zlib licence); it is used only after you install it into an environment.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel("Custom Wine installs") {
                    ForEach(draft.customRuntimeRoots, id: \.self) { root in
                        HStack {
                            Text(LogRedactor.redact(root.path)).font(.callout.monospaced())
                            Spacer()
                            Button { draft.customRuntimeRoots.removeAll { $0 == root } } label: { Icon("minus.circle") }
                                .buttonStyle(.flat)
                        }
                    }
                    Button("Add Folder Containing bin/wine…") {
                        if let dir = AppModel.chooseFolder(prompt: "Add Wine Install") { draft.customRuntimeRoots.append(dir) }
                    }
                    Text("Use this for a Game Porting Toolkit build you obtained from Apple yourself, or any other Wine install.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel("Shader cache") {
                    Text("The shader cache location is configurable per game only for DXVK (DXVK_STATE_CACHE_PATH). For D3DMetal and WineD3D, macOS manages Metal shader caches itself, and there is no supported setting.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Revert") { draft = model.settings }.disabled(draft == model.settings)
                    Button("Save Settings") {
                        model.settings = draft
                        model.saveSettings()
                    }
                    .primaryAction(Theme.accent).disabled(draft == model.settings)
                }
            }
            .padding(28)
        }
        .onAppear {
            if !loaded { draft = model.settings; loaded = true }
        }
    }

    func locationRow(_ title: String, _ path: String, choose: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(LogRedactor.redact(path)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Change…", action: choose)
        }
    }
}
