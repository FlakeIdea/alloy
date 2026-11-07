import SwiftUI
import AlloyCore

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    @State private var importing: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Performance", subtitle: "Record how a game runs with different settings and keep the best one") {
                GamePicker()
            }
            if let game = model.game(model.selectedGameID) {
                let runs = model.benchmarks[game.id] ?? []
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Panel("Recommendation — \(game.graphics.preset.displayName), \(game.graphics.targetFPS) FPS target") {
                            if let rec = OptimizationAdvisor.recommend(runs: runs, preset: game.graphics.preset, targetFPS: game.graphics.targetFPS) {
                                HStack {
                                    Icon(rec.meetsTarget ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(rec.meetsTarget ? Theme.accent : Theme.warning)
                                    Text(rec.run.label).font(.headline)
                                }
                                Text(rec.reason).foregroundStyle(.secondary)
                                if !rec.run.inGameSettings.isEmpty {
                                    Text(rec.run.inGameSettings.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
                                        .font(.callout)
                                }
                            } else {
                                Text("No valid measurements yet. Recommendations are based only on runs you have measured.")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Panel("Measured runs") {
                            if runs.isEmpty { Text("None").foregroundStyle(.secondary) }
                            ForEach(runs) { run in RunRow(run: run, target: game.graphics.targetFPS) { model.removeBenchmark(run, from: game) } }
                            Button {
                                if let url = AppModel.chooseFile(types: ["csv", "txt"], prompt: "Import"),
                                   let text = try? String(contentsOf: url, encoding: .utf8) {
                                    let times = FrameTimeCSV.parse(text)
                                    if times.count >= 10 { importing = times }
                                    else { model.alert = AlertItem(title: "No frame times found", message: "Expected a CSV with a MsBetweenPresents, frametime or frame_time column, or one value per line.") }
                                }
                            } label: { Label { Text("Import Frame-Time Capture…") } icon: { Icon("square.and.arrow.down") } }
                            Text("Alloy does not yet capture frame times automatically. Import a CSV (PresentMon, MangoHud-style, or one millisecond value per line) recorded from the same reproducible scene for every configuration.")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Panel("Quality-first tuning order") {
                            Text("When a configuration misses the target, change one thing at a time in this order and measure again. Keep a change only if it measurably helps (≥ 5% better 1% lows).")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(OptimizationAdvisor.fallbackOrder.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top) {
                                    Text("\(index + 1).").bold().frame(width: 22, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.category).bold()
                                        Text(step.advice).font(.callout).foregroundStyle(.secondary)
                                        if let cvar = step.unrealCVar {
                                            Text("Unreal: \(cvar)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(28)
                }
                .sheet(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } })) {
                    if let times = importing { RecordRunSheet(game: game, frameTimes: times) }
                }
            } else {
                EmptyStateView(symbol: "gauge.with.dots.needle.67percent", title: "Select a game",
                               message: "Pick a game to record and compare benchmark runs.")
            }
        }
    }
}

struct RunRow: View {
    let run: BenchmarkRun
    let target: Int
    let onDelete: () -> Void

    var body: some View {
        let s = run.stats
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.label).bold()
                Text("\(run.scene) · \(run.graphics.backend.displayName) · quality \(run.qualityScore)")
                    .font(.caption).foregroundStyle(.secondary)
                if run.crashed { Text("Crashed").font(.caption).foregroundStyle(Theme.danger) }
                if !run.visualArtifacts.isEmpty {
                    Text("Artefacts: \(run.visualArtifacts.joined(separator: ", "))").font(.caption).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            metric("Avg", String(format: "%.1f", s.averageFPS))
            metric("1% low", String(format: "%.1f", s.onePercentLowFPS))
            metric("p99", String(format: "%.1f ms", s.p99FrameTimeMs))
            metric("Over budget", String(format: "%.1f%%", s.overBudgetRatio * 100))
            metric("Hitches", "\(s.stutterCount)")
            Icon(s.meetsTarget(fps: target) ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(s.meetsTarget(fps: target) ? Theme.accent : .secondary)
            Button(action: onDelete) { Icon("trash") }.buttonStyle(.flat)
        }
        .padding(.vertical, 4)
    }

    func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.callout.monospacedDigit().bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 60, alignment: .trailing)
    }
}

struct RecordRunSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let game: Game
    let frameTimes: [Double]
    @State private var label = ""
    @State private var scene = ""
    @State private var quality = 80.0
    @State private var settingsText = ""
    @State private var crashed = false
    @State private var artifacts = ""

    var body: some View {
        let stats = FrameTimeStatistics(frameTimesMs: frameTimes, budgetMs: game.graphics.frameBudgetMilliseconds)
        VStack(alignment: .leading, spacing: 12) {
            Text("Record benchmark run").font(.title2.bold())
            if let stats {
                Text(String(format: "%d frames · %.1f FPS avg · %.1f FPS 1%% low", stats.frameCount, stats.averageFPS, stats.onePercentLowFPS))
                    .foregroundStyle(.secondary)
            }
            Form {
                TextField("Label", text: $label, prompt: Text("e.g. High, shadows Medium"))
                TextField("Scene", text: $scene, prompt: Text("e.g. first level, 60 s walk"))
                VStack(alignment: .leading) {
                    Slider(value: $quality, in: 0...100, step: 5) { Text("Visual quality \(Int(quality))") }
                    Text("100 = every setting at maximum at native resolution.").font(.caption).foregroundStyle(.secondary)
                }
                TextField("In-game settings", text: $settingsText, prompt: Text("Shadows=High; Textures=Epic; Resolution=2560x1600"))
                TextField("Visual artefacts (comma separated)", text: $artifacts)
                Toggle("Crashed or became unstable", isOn: $crashed)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    guard let stats else { return }
                    let settings = Dictionary(settingsText.split(separator: ";").compactMap { pair -> (String, String)? in
                        let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        return kv.count == 2 ? (kv[0], kv[1]) : nil
                    }, uniquingKeysWith: { $1 })
                    let run = BenchmarkRun(label: label.ifEmpty("Run"), scene: scene, graphics: game.graphics,
                                           inGameSettings: settings, qualityScore: Int(quality), stats: stats, crashed: crashed,
                                           visualArtifacts: artifacts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                    model.addBenchmark(run, to: game)
                    dismiss()
                }
                .primaryAction(Theme.accent).disabled(stats == nil)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
