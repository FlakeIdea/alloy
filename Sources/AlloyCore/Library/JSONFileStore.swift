import Foundation

/// Reads and atomically writes a Codable value as pretty-printed JSON.
/// A corrupt file is preserved as `<name>.corrupt-<timestamp>` instead of being overwritten, once per content.
public struct JSONFileStore<Value: Codable> {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load(default defaultValue: @autoclosure () -> Value) -> Value {
        guard let data = try? Data(contentsOf: fileURL) else { return defaultValue() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        if let value = try? decoder.decode(Value.self, from: data) { return value }
        // Files that are read often (runtime manifests are read on every scan) would otherwise pile up copies.
        let folder = fileURL.deletingLastPathComponent()
        let prefix = fileURL.lastPathComponent + ".corrupt-"
        let existing = (try? fileManager.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasPrefix(prefix) } ?? []
        if !existing.contains(where: { (try? Data(contentsOf: folder.appendingPathComponent($0))) == data }) {
            let backup = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? fileManager.copyItem(at: fileURL, to: backup)
        }
        return defaultValue()
    }

    public func save(_ value: Value) throws {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .deferredToDate  // exact round-trip
            try encoder.encode(value).write(to: fileURL, options: .atomic)
        } catch {
            throw AlloyError.persistenceFailed(error.localizedDescription)
        }
    }
}
