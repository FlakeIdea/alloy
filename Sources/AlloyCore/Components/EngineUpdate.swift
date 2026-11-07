import Foundation

/// Moving environments onto a newer game engine.
///
/// An environment remembers the engine it was made with, and a newly installed engine package goes into a folder of
/// its own, so engine fixes (in Wine's Mac driver, say) never reached existing environments. An environment on an
/// older DXMT engine built from the same Wine version can move to the newest one: the Wine underneath is the same, so
/// its files, saves and installed games need no change.
public enum EngineUpdate {
    /// The package an engine in Alloy's Runtimes folder came from; nil for engines made on this Mac or found elsewhere.
    public static func marker(of runtime: WineRuntime, fileManager: FileManager = .default) -> RuntimeInstaller.Marker? {
        let file = runtime.root.deletingLastPathComponent().appendingPathComponent(RuntimeInstaller.markerName)
        guard let data = fileManager.contents(atPath: file.path) else { return nil }
        return try? RuntimeInstaller.decoder.decode(RuntimeInstaller.Marker.self, from: data)
    }

    /// The engine an environment on `current` should move to, or nil when it's already on the newest one or can't move.
    public static func newer(than current: WineRuntime, among runtimes: [WineRuntime], managedDirectory: URL,
                             marker: (WineRuntime) -> RuntimeInstaller.Marker? = { EngineUpdate.marker(of: $0) }) -> WineRuntime? {
        func isDXMTEngine(_ r: WineRuntime) -> Bool {
            r.hasDXMT && !r.hasD3DMetal && r.root.standardizedFileURL.path.hasPrefix(managedDirectory.standardizedFileURL.path + "/")
        }
        func wineMajor(_ r: WineRuntime) -> Int? { r.version.flatMap { Int($0.prefix { $0.isNumber }) } }
        let packaged = runtimes.compactMap { r in isDXMTEngine(r) ? marker(r).map { (r, $0) } : nil }
        guard let (newest, newestMarker) = packaged.max(by: { $0.1.installedAt < $1.1.installedAt }),
              newest.id != current.id, isDXMTEngine(current),
              let major = wineMajor(current), major == wineMajor(newest) else { return nil }
        if let own = marker(current), own.installedAt >= newestMarker.installedAt { return nil }
        return newest
    }
}
