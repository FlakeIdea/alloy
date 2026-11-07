import Foundation

/// Statistics over a sequence of frame times (milliseconds).
public struct FrameTimeStatistics: Codable, Hashable, Sendable {
    public var frameCount: Int
    public var averageFPS: Double
    /// FPS equivalent of the mean of the slowest 1% of frames.
    public var onePercentLowFPS: Double
    public var p99FrameTimeMs: Double
    public var medianFrameTimeMs: Double
    public var standardDeviationMs: Double
    /// Share of frames slower than the target's frame budget (0–1).
    public var overBudgetRatio: Double
    /// Frames longer than twice the median — visible hitches.
    public var stutterCount: Int

    public init?(frameTimesMs raw: [Double], budgetMs: Double) {
        let times = raw.filter { $0.isFinite && $0 > 0 }
        guard times.count >= 10 else { return nil }
        let sorted = times.sorted()
        let total = times.reduce(0, +)
        let mean = total / Double(times.count)
        frameCount = times.count
        averageFPS = 1000.0 * Double(times.count) / total
        let worstCount = max(1, times.count / 100)
        let worst = sorted.suffix(worstCount)
        onePercentLowFPS = 1000.0 / (worst.reduce(0, +) / Double(worst.count))
        p99FrameTimeMs = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.99).rounded(.down)))]
        medianFrameTimeMs = sorted.count % 2 == 0
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        standardDeviationMs = (times.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(times.count)).squareRoot()
        overBudgetRatio = Double(times.filter { $0 > budgetMs * 1.05 }.count) / Double(times.count)
        let median = medianFrameTimeMs
        stutterCount = times.filter { $0 > median * 2 }.count
    }

    /// Whether this run sustains the target: average at target, 1% lows not far below it, few over-budget frames.
    public func meetsTarget(fps: Int) -> Bool {
        averageFPS >= Double(fps) * 0.97 && onePercentLowFPS >= Double(fps) * 0.75 && overBudgetRatio <= 0.05
    }
}

/// Reads frame times from CSV exports (PresentMon `MsBetweenPresents`, MangoHud `frametime`, or a single column).
public enum FrameTimeCSV {
    public static func parse(_ text: String) -> [Double] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let names = ["msbetweenpresents", "frametime", "frame_time", "frametime_ms", "ms"]
        for (index, line) in lines.enumerated() {
            let headers = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if let column = headers.firstIndex(where: { names.contains($0) }) {
                return lines[(index + 1)...].compactMap { row in
                    let cells = row.split(separator: ",", omittingEmptySubsequences: false)
                    return column < cells.count ? Double(cells[column].trimmingCharacters(in: .whitespaces)) : nil
                }
            }
        }
        // Headerless single column.
        return lines.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}
