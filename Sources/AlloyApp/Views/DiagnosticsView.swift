import AppKit
import SwiftUI
import AlloyCore

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Diagnostics", subtitle: "Logs and troubleshooting. Reports are saved locally; nothing is uploaded.") {
                HStack {
                    GamePicker()
                    Button("Open Logs Folder") {
                        try? FileManager.default.createDirectory(at: model.logsDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(model.logsDirectory)
                    }
                }
            }
            if let game = model.game(model.selectedGameID) {
                let runtime = model.runtime(for: game)
                let prefix = model.prefix(game.prefixID)
                let findings = model.findings[game.id] ?? DiagnosticService.preflight(game: game, runtime: runtime, prefix: prefix)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Panel("Summary") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow { Text("Result").foregroundStyle(.secondary); StatusPill(state: model.state(of: game.id)) }
                                GridRow { Text("Runtime").foregroundStyle(.secondary); Text(runtime?.displayName ?? "None") }
                                GridRow { Text("Environment").foregroundStyle(.secondary); Text(prefix?.name ?? "None") }
                                GridRow { Text("Graphics").foregroundStyle(.secondary); Text("\(game.graphics.backend.displayName) (requested)") }
                            }
                        }
                        Panel("Findings") {
                            if findings.isEmpty {
                                Label { Text("No problems detected") } icon: { Icon("checkmark.seal.fill") }.foregroundStyle(Theme.accent)
                            }
                            ForEach(findings) { FindingRow(finding: $0); Divider() }
                        }
                        Panel("Last session log") {
                            LogConsole(lines: model.logs[game.id] ?? []).frame(height: 320)
                        }
                        HStack {
                            if model.state(of: game.id).isRunning {
                                Button { model.saveThreadBacktraces(game) } label: {
                                    Label { Text("Save Thread Backtraces") } icon: { Icon("list.bullet.indent") }
                                }
                                .help("For a game that has stopped responding: saves where each of its threads is waiting to the Logs folder.")
                            }
                            Spacer()
                            Button {
                                if let url = AppModel.chooseSaveLocation(name: "Alloy-\(game.name)-report.md") {
                                    model.exportReport(for: game, to: url)
                                }
                            } label: { Label { Text("Export Diagnostic Report…") } icon: { Icon("square.and.arrow.up") } }
                            .primaryAction(Theme.accent)
                        }
                        Text("Reports redact your home folder path and credential-looking values. Review before sharing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(28)
                }
            } else {
                EmptyStateView(symbol: "stethoscope", title: "Select a game",
                               message: "Pick a game to see its last launch result, detected problems and log.")
            }
        }
    }
}
