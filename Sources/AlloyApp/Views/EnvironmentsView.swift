import AppKit
import SwiftUI
import AlloyCore

struct EnvironmentsView: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""
    @State private var prefixToTrash: WinePrefix?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Environments", subtitle: "Wine runtimes and isolated prefixes") {
                    Button { model.refreshRuntimes(); model.refreshPrefixes() } label: { Label { Text("Rescan") } icon: { Icon("arrow.clockwise") } }
                }
                .padding(.horizontal, -28)

                Panel("Wine runtimes") {
                    if model.runtimes.isEmpty {
                        Label { Text("No Wine runtime found") } icon: { Icon("exclamationmark.triangle.fill") }.foregroundStyle(Theme.warning)
                        Text(RuntimeInstallGuide.summary).font(.callout).foregroundStyle(.secondary)
                        Button("Install the Game Engine…") { model.selection = .setup }
                        Text("You can also add your own Wine install folder in Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.runtimes) { RuntimeRow(runtime: $0) }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("D3DMetal (Apple Game Porting Toolkit)").bold()
                            Text("Best DirectX 11/12 performance. Download the Toolkit from developer.apple.com, open its “Evaluation environment” image and accept Apple's licence, then select the mounted volume. Alloy builds a separate runtime copy; nothing else is modified.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.importingD3DMetal { ProgressView().controlSize(.small) }
                        Button("Add D3DMetal Runtime…") { model.importD3DMetal() }.disabled(model.importingD3DMetal)
                    }
                }

                Panel("Alloy environments") {
                    HStack {
                        TextField("New environment name", text: $newName)
                        Button("Create") {
                            _ = model.createPrefix(name: newName, runtime: model.runtimes.first)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if model.ownPrefixes.isEmpty {
                        Text("No environments yet. Adding a game creates one automatically.").foregroundStyle(.secondary)
                    }
                    ForEach(model.ownPrefixes) { prefix in
                        PrefixRow(prefix: prefix, onTrash: { prefixToTrash = prefix })
                        Divider()
                    }
                }

                Panel("CrossOver bottles (read-only)") {
                    Text("Listed for reference only. Alloy never modifies, launches into or deletes CrossOver bottles: running a different Wine version in a bottle can upgrade and break it.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.crossOverBottles.isEmpty { Text("None found.").foregroundStyle(.secondary) }
                    ForEach(model.crossOverBottles) { bottle in
                        HStack {
                            Icon("lock.fill").foregroundStyle(.secondary)
                            Text(bottle.name).bold()
                            Text(bottle.architecture).foregroundStyle(.secondary)
                            Spacer()
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([bottle.path]) }
                        }
                    }
                }
            }
            .padding(28)
        }
        .confirmationDialog("Move \(prefixToTrash?.name ?? "") to the Trash?",
                            isPresented: Binding(get: { prefixToTrash != nil }, set: { if !$0 { prefixToTrash = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let p = prefixToTrash { model.trashPrefix(p) }
                prefixToTrash = nil
            }
        } message: {
            Text("Programs and saves installed inside this environment go with it. You can restore it from the Trash. Game folders you added are not affected.")
        }
    }
}

struct RuntimeRow: View {
    @EnvironmentObject var model: AppModel
    let runtime: WineRuntime

    var body: some View {
        let caps = model.backend.capabilities(of: runtime)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(runtime.displayName).font(.headline)
                if model.settings.defaultRuntimeID == runtime.id || (model.settings.defaultRuntimeID == nil && model.runtimes.first == runtime) {
                    Text("Default").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.2))).foregroundStyle(Theme.accent)
                }
                Spacer()
                Text(runtime.architectures.map(\.rawValue).joined(separator: " + ").ifEmpty("unknown arch"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(LogRedactor.redact(runtime.wineBinary.path)).font(.caption.monospaced()).foregroundStyle(.tertiary)
            ForEach(caps.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(GraphicsBackendKind.allCases) { kind in
                    GridRow {
                        Text(kind.displayName).font(.callout)
                        Text(kind.directXVersions).font(.caption).foregroundStyle(.secondary)
                        CapabilityTag(status: caps.status(of: kind))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PrefixRow: View {
    @EnvironmentObject var model: AppModel
    let prefix: WinePrefix
    let onTrash: () -> Void
    @State private var confirmVisualCpp = false

    var body: some View {
        let state = model.state(of: prefix.id)
        let initialized = prefix.isInitialized()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(prefix.name).font(.headline)
                Text(prefix.architecture).font(.caption).foregroundStyle(.secondary)
                if PrefixManager.hasDXVKInstalled(prefix) { CapabilityTag(status: .experimental("DXVK")).overlay(Text("")) }
                Spacer()
                if state.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.caption)
                } else if !initialized {
                    Button("Initialise") { model.initializePrefix(prefix) }.primaryAction(Theme.accent)
                }
                Button {
                    let hasDXVK = PrefixManager.hasDXVKInstalled(prefix)
                    popUpMenu([
                        MenuChoice(title: "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([prefix.path]) },
                        MenuChoice(title: "Stop all programs in this environment") { model.stopAll(in: prefix) },
                    ] + model.environmentMenu(for: prefix).enumerated().map { index, choice in
                        var choice = choice; choice.separatorBefore = index == 0; return choice
                    } + [
                        hasDXVK
                            ? MenuChoice(title: "Remove DXVK (restore original DLLs)", separatorBefore: true) { model.uninstallDXVK(from: prefix) }
                            : MenuChoice(title: "Install DXVK-macOS DLLs…", enabled: initialized, separatorBefore: true) { model.installDXVK(into: prefix) },
                        MenuChoice(title: "Install Visual C++ Runtime…",
                                   enabled: initialized && model.visualCppVersion(in: prefix) == nil && model.componentStatus[prefix.id] == nil) { confirmVisualCpp = true },
                        MenuChoice(title: "Move to Trash…", destructive: true, separatorBefore: true, action: onTrash),
                    ])
                } label: { GlyphView(glyph: .more, size: 15).frame(width: 30, height: 30) }
                .buttonStyle(.flat)
                .help("More")
            }
            Text(initialized ? "Initialised" : "Not initialised — click Initialise to run wineboot")
                .font(.caption).foregroundStyle(initialized ? Color.secondary : Theme.warning)
            if let status = model.componentStatus[prefix.id] {
                Text(status).font(.caption).foregroundStyle(.secondary)
            } else if let version = model.visualCppVersion(in: prefix) {
                Text("Visual C++ runtime \(version)").font(.caption).foregroundStyle(.secondary)
            }
            let users = model.games.filter { $0.prefixID == prefix.id }.map(\.name)
            if !users.isEmpty { Text("Used by: \(users.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
            if case .exited(let code) = state, code != 0 {
                Text("Last operation exited with code \(code). See Diagnostics.").font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .sheet(isPresented: $confirmVisualCpp) {
            VStack(alignment: .leading, spacing: 14) {
                VisualCppRow(prefix: prefix)
                HStack { Spacer(); Button("Done") { confirmVisualCpp = false }.keyboardShortcut(.defaultAction).primaryAction() }
            }
            .padding(24).frame(width: 520)
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
