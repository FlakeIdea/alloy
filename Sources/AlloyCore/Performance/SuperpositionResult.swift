import Foundation

/// FPS summary decoded from the base64 block Unigine Superposition prints after "Benchmark results:".
/// Layout (little-endian): min, max, avg FPS (Float32), scene count (UInt32), then per-scene average FPS.
/// Superposition reports only these aggregates, so 1% lows are not available from it.
public struct SuperpositionResult: Equatable, Sendable {
    public var minFPS: Double
    public var maxFPS: Double
    public var averageFPS: Double
    public var sceneAverages: [Double]

    public static func parse(log: String) -> SuperpositionResult? {
        let lines = log.components(separatedBy: .newlines)
        guard let marker = lines.lastIndex(where: { $0.contains("Benchmark results:") }) else { return nil }
        for line in lines[(marker + 1)...].prefix(4) {
            if let result = decode(line.trimmingCharacters(in: .whitespaces)) { return result }
        }
        return nil
    }

    static func decode(_ blob: String) -> SuperpositionResult? {
        guard blob.count >= 24, let data = Data(base64Encoded: blob + String(repeating: "=", count: (4 - blob.count % 4) % 4)),
              data.count >= 16 else { return nil }
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        func f32(_ offset: Int) -> Double { Double(Float(bitPattern: u32(offset))) }
        let count = Int(u32(12))
        guard count > 0, count < 256, data.count >= 16 + count * 4 else { return nil }
        let result = SuperpositionResult(minFPS: f32(0), maxFPS: f32(4), averageFPS: f32(8),
                                         sceneAverages: (0..<count).map { f32(16 + $0 * 4) })
        let plausible = (0.0...10_000.0)
        guard plausible.contains(result.minFPS), plausible.contains(result.maxFPS), plausible.contains(result.averageFPS),
              result.minFPS <= result.averageFPS, result.averageFPS <= result.maxFPS else { return nil }
        return result
    }
}
