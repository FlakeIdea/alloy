import Foundation
@testable import AlloyCore

/// Temporary directory removed when the value is deinitialised.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("alloy-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ relative: String, _ data: Data, executable: Bool = false) -> URL {
        let file = url.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! data.write(to: file)
        if executable { try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        return file
    }
}

/// Builds a minimal, inert PE header (no code) for parser tests.
enum PEFixture {
    static func make(machine: UInt16 = 0x8664, pe32Plus: Bool = true, dll: Bool = false, subsystem: UInt16 = 2) -> Data {
        var b = [UInt8](repeating: 0, count: 512)
        b[0] = 0x4D; b[1] = 0x5A
        let peOffset = 0x80
        put32(&b, 0x3C, UInt32(peOffset))
        b[peOffset] = 0x50; b[peOffset + 1] = 0x45
        put16(&b, peOffset + 4, machine)
        put16(&b, peOffset + 4 + 18, dll ? 0x2002 : 0x0002)
        let optional = peOffset + 24
        put16(&b, optional, pe32Plus ? 0x20b : 0x10b)
        put16(&b, optional + 68, subsystem)
        return Data(b)
    }

    static func put16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) {
        b[o] = UInt8(v & 0xff); b[o + 1] = UInt8(v >> 8)
    }

    static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xff) }
    }
}

enum MachOFixture {
    static func thin(cpu: UInt32) -> Data {
        var b: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
        for i in 0..<4 { b.append(UInt8((cpu >> (8 * UInt32(i))) & 0xff)) }
        return Data(b + [UInt8](repeating: 0, count: 24))
    }

    static func fat(cpus: [UInt32]) -> Data {
        var b: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        func be(_ v: UInt32) { for i in (0..<4).reversed() { b.append(UInt8((v >> (8 * UInt32(i))) & 0xff)) } }
        be(UInt32(cpus.count))
        for cpu in cpus { be(cpu); be(0); be(0); be(0); be(0) }
        return Data(b)
    }
}

func makeGame(in dir: TempDir, exe: String = "Game.exe", data: Data = PEFixture.make()) -> Game {
    dir.write("Game/\(exe)", data)
    return Game(name: "Test Game", folder: dir.url.appendingPathComponent("Game"), executableRelativePath: exe)
}

/// A fake Wine install: a harmless shell script named `wine` so command building sees an executable file.
func makeFakeRuntime(in dir: TempDir, moltenVK: Bool = false, d3dMetal: Bool = false, kind: RuntimeKind = .wineDevel) -> WineRuntime {
    let root = dir.url.appendingPathComponent("Wine Devel.app/Contents/Resources/wine")
    dir.write("Wine Devel.app/Contents/Resources/wine/bin/wine", Data("#!/bin/sh\necho wine-11.20\n".utf8), executable: true)
    if moltenVK { dir.write("Wine Devel.app/Contents/Resources/wine/lib/libMoltenVK.dylib", Data()) }
    if d3dMetal {
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("lib/external/D3DMetal.framework"),
                                                 withIntermediateDirectories: true)
    }
    return WineBackend(applicationDirectories: [], installRoots: [], versionProbe: { _ in "11.20" })
        .makeRuntime(kind: kind, binary: root.appendingPathComponent("bin/wine"), root: root)
}

func makeInitializedPrefix(in dir: TempDir) -> WinePrefix {
    dir.write("prefix/system.reg", Data("WINE REGISTRY Version 2\n".utf8))
    return WinePrefix(name: "Test Prefix", path: dir.url.appendingPathComponent("prefix"))
}
