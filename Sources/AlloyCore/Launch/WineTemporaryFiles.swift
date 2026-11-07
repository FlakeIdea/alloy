import Foundation

/// Wine keeps links to its loader and `ntdll.so` in `$TMPDIR/winetemp-<id>/` and reuses them on later starts without
/// checking them; the folder's name comes from the loader file, so it stays the same when the runtime's folder moves.
/// After a move (the data migration, or a runtime moved by hand) the links point at nothing and Wine stops with
/// "could not load ntdll.so". Removing the dead links lets Wine make fresh ones.
public enum WineTemporaryFiles {
    /// Removes links whose target no longer exists, in each winetemp folder and in the per-program app bundles
    /// (`<name>.exe.app/Contents/MacOS`) inside it. Files and working links are left alone. Returns how many went.
    @discardableResult
    public static func removeDeadLinks(temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
                                       fileManager: FileManager = .default) -> Int {
        var removed = 0
        func sweep(_ folder: URL) {
            for item in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
                let path = folder.appendingPathComponent(item).path
                guard (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil,
                      !fileManager.fileExists(atPath: path)   // follows the link: false when its target is gone
                else { continue }
                if (try? fileManager.removeItem(atPath: path)) != nil { removed += 1 }
            }
        }
        for name in (try? fileManager.contentsOfDirectory(atPath: temporaryDirectory.path)) ?? [] where name.hasPrefix("winetemp-") {
            let folder = temporaryDirectory.appendingPathComponent(name)
            sweep(folder)
            for bundle in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where bundle.hasSuffix(".app") {
                sweep(folder.appendingPathComponent(bundle).appendingPathComponent("Contents/MacOS"))
            }
        }
        return removed
    }
}
