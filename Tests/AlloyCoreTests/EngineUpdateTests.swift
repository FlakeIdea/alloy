import Foundation
import Testing
@testable import AlloyCore

@Suite struct EngineUpdateTests {
    func engine(_ dir: TempDir, _ folder: String, version: String = "11.0", d3dMetal: Bool = false) -> WineRuntime {
        let root = dir.url.appendingPathComponent("Runtimes/\(folder)/wine")
        return WineRuntime(kind: .custom, wineBinary: root.appendingPathComponent("bin/wine"), root: root,
                           version: version, hasD3DMetal: d3dMetal, hasDXMT: true)
    }

    func marker(_ id: String, _ seconds: TimeInterval) -> RuntimeInstaller.Marker {
        RuntimeInstaller.Marker(id: id, version: id, sha256: "", installedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func movesOlderDXMTEnginesOfTheSameWineToTheNewestPackage() {
        let dir = TempDir()
        let managed = dir.url.appendingPathComponent("Runtimes")
        let built = engine(dir, "dxmt-0-80-local")           // made on this Mac, no package marker
        let old = engine(dir, "alloy-dxmt-2"), new = engine(dir, "alloy-dxmt-3")
        let d3dm = engine(dir, "d3dmetal-4", d3dMetal: true)
        let wine10 = engine(dir, "dxmt-wine10", version: "10.0")
        let elsewhere = WineRuntime(kind: .wineDevel, wineBinary: URL(fileURLWithPath: "/Applications/Wine Devel.app/wine/bin/wine"),
                                    root: URL(fileURLWithPath: "/Applications/Wine Devel.app/wine"), version: "11.0", hasDXMT: true)
        let markers = [old.id: marker("dxmt-0.80-cx26.3-2", 100), new.id: marker("dxmt-0.80-cx26.3-3", 200)]
        let all = [built, old, new, d3dm, wine10, elsewhere]
        func update(_ r: WineRuntime) -> WineRuntime? {
            EngineUpdate.newer(than: r, among: all, managedDirectory: managed) { markers[$0.id] }
        }
        #expect(update(built) == new)
        #expect(update(old) == new)
        #expect(update(new) == nil)
        #expect(update(d3dm) == nil)          // D3DMetal environments stay on D3DMetal
        #expect(update(wine10) == nil)        // another Wine version could need its files updated
        #expect(update(elsewhere) == nil)     // only engines in Alloy's own folder
    }

    @Test func readsThePackageMarkerBesideTheEngine() throws {
        let dir = TempDir()
        let r = engine(dir, "alloy-dxmt-3")
        let m = marker("dxmt-0.80-cx26.3-3", 200)
        dir.write("Runtimes/alloy-dxmt-3/\(RuntimeInstaller.markerName)", try RuntimeInstaller.encoder.encode(m))
        #expect(EngineUpdate.marker(of: r) == m)
        #expect(EngineUpdate.marker(of: engine(dir, "none")) == nil)
    }
}
