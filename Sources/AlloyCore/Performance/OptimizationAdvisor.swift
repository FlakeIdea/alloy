import Foundation

/// One measured run of a reproducible scene with a specific configuration.
public struct BenchmarkRun: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var label: String
    public var scene: String
    public var graphics: GraphicsConfiguration
    /// In-game settings recorded by the user, e.g. ["Shadows": "High", "Resolution": "2560x1600"].
    public var inGameSettings: [String: String]
    /// 0–100 visual quality score (100 = everything at maximum, native resolution).
    public var qualityScore: Int
    public var stats: FrameTimeStatistics
    public var crashed: Bool
    public var visualArtifacts: [String]
    public var peakMemoryGB: Double?

    public init(id: UUID = UUID(), date: Date = Date(), label: String, scene: String, graphics: GraphicsConfiguration,
                inGameSettings: [String: String] = [:], qualityScore: Int, stats: FrameTimeStatistics,
                crashed: Bool = false, visualArtifacts: [String] = [], peakMemoryGB: Double? = nil) {
        self.id = id
        self.date = date
        self.label = label
        self.scene = scene
        self.graphics = graphics
        self.inGameSettings = inGameSettings
        self.qualityScore = qualityScore
        self.stats = stats
        self.crashed = crashed
        self.visualArtifacts = visualArtifacts
        self.peakMemoryGB = peakMemoryGB
    }

    /// Runs that crashed or rendered incorrectly never count as successful.
    public var isValid: Bool { !crashed && visualArtifacts.isEmpty }
}

public struct Recommendation: Equatable, Sendable {
    public var run: BenchmarkRun
    public var meetsTarget: Bool
    public var reason: String
}

/// A setting change, ordered from "high cost, small visual impact" to "visually expensive to give up".
public struct SettingAdjustment: Equatable, Sendable {
    public var category: String
    public var advice: String
    /// Unreal Engine scalability console variable, where one applies.
    public var unrealCVar: String?
}

public enum OptimizationAdvisor {
    /// A gain smaller than this (relative 1% lows) is not worth a visible quality loss.
    public static let insignificantGain = 0.05

    /// Quality-first fallback order. Compatibility and stutter causes come before any visual reduction.
    public static let fallbackOrder: [SettingAdjustment] = [
        SettingAdjustment(category: "Compatibility", advice: "Fix errors in Diagnostics first and try another valid graphics backend (e.g. D3DMetal vs DXVK). Translation overhead often matters more than any setting.", unrealCVar: nil),
        SettingAdjustment(category: "Shader stutter", advice: "Replay the benchmark scene once to warm the shader cache before measuring. Hitches that disappear on the second run are compilation, not GPU load.", unrealCVar: nil),
        SettingAdjustment(category: "Volumetrics / effects", advice: "Lower volumetric fog/clouds and heavy particle effects one step.", unrealCVar: "sg.EffectsQuality"),
        SettingAdjustment(category: "Shadows", advice: "Lower shadow quality one step (Epic → High). Usually a large GPU saving for a small visual change.", unrealCVar: "sg.ShadowQuality"),
        SettingAdjustment(category: "Ambient occlusion / post-processing", advice: "Lower post-processing one step; disable motion blur and depth of field if you dislike them.", unrealCVar: "sg.PostProcessQuality"),
        SettingAdjustment(category: "Reflections", advice: "Lower screen-space reflections one step.", unrealCVar: "sg.ReflectionQuality"),
        SettingAdjustment(category: "Foliage / view distance", advice: "Lower foliage and view distance one step.", unrealCVar: "sg.FoliageQuality"),
        SettingAdjustment(category: "Anti-aliasing", advice: "Switch to a cheaper AA mode only if it does not add obvious shimmering.", unrealCVar: "sg.AntiAliasingQuality"),
        SettingAdjustment(category: "Render scale", advice: "Reduce render scale slightly (100% → 90%). Measure before and after; keep native if the gain is small.", unrealCVar: "r.ScreenPercentage"),
        SettingAdjustment(category: "Textures", advice: "Lower textures only if memory pressure is measured (swap use, VRAM warnings). Textures cost little GPU time.", unrealCVar: "sg.TextureQuality"),
    ]

    /// Next adjustment to try after the categories already tried.
    public static func nextAdjustment(after tried: [String]) -> SettingAdjustment? {
        fallbackOrder.first { !tried.contains($0.category) }
    }

    /// Picks the measured run that best fits the preset. Returns nil when no valid run exists.
    public static func recommend(runs: [BenchmarkRun], preset: QualityPreset, targetFPS: Int) -> Recommendation? {
        let valid = runs.filter(\.isValid)
        guard !valid.isEmpty else { return nil }
        let meeting = valid.filter { $0.stats.meetsTarget(fps: targetFPS) }

        func byQualityThenLows(_ a: BenchmarkRun, _ b: BenchmarkRun) -> Bool {
            a.qualityScore != b.qualityScore ? a.qualityScore > b.qualityScore : a.stats.onePercentLowFPS > b.stats.onePercentLowFPS
        }

        switch preset {
        case .highQuality:
            let playable = valid.filter { $0.stats.averageFPS >= Double(targetFPS) * 0.75 }
            let pick = (playable.isEmpty ? valid : playable).sorted(by: byQualityThenLows)[0]
            return Recommendation(run: pick, meetsTarget: pick.stats.meetsTarget(fps: targetFPS),
                                  reason: playable.isEmpty
                                    ? "No run reached 75% of the target; showing the highest-quality valid run."
                                    : "Highest visual quality that stays playable (≥ 75% of target).")
        case .balanced, .custom:
            if let best = meeting.sorted(by: byQualityThenLows).first {
                return Recommendation(run: best, meetsTarget: true,
                                      reason: "Highest quality that sustains \(targetFPS) FPS with stable frame pacing.")
            }
            let pick = preferQuality(valid.sorted { $0.stats.onePercentLowFPS > $1.stats.onePercentLowFPS })
            return Recommendation(run: pick, meetsTarget: false,
                                  reason: "No run met the target. Chose the smoothest run, preferring higher quality where the smoothness difference is under 5%.")
        case .highFPS:
            let pick = preferQuality(valid.sorted { $0.stats.onePercentLowFPS > $1.stats.onePercentLowFPS })
            return Recommendation(run: pick, meetsTarget: pick.stats.meetsTarget(fps: targetFPS),
                                  reason: "Best 1% lows; higher quality kept where the difference is under 5%.")
        }
    }

    /// Given runs sorted by smoothness, prefers a higher-quality run whose 1% lows are within `insignificantGain`.
    static func preferQuality(_ sortedBySmoothness: [BenchmarkRun]) -> BenchmarkRun {
        let fastest = sortedBySmoothness[0]
        let threshold = fastest.stats.onePercentLowFPS * (1 - insignificantGain)
        return sortedBySmoothness
            .filter { $0.stats.onePercentLowFPS >= threshold }
            .max { $0.qualityScore != $1.qualityScore ? $0.qualityScore < $1.qualityScore
                                                      : $0.stats.onePercentLowFPS < $1.stats.onePercentLowFPS } ?? fastest
    }
}
