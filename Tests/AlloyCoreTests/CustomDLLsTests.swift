import Foundation
import Testing
@testable import AlloyCore

struct CustomDLLsTests {
    /// The smallest PE header PEInspector reads: MZ, PE signature, machine and the DLL characteristic.
    func dll(_ machine: UInt16, at url: URL, isDLL: Bool = true) throws {
        var d = Data(count: 0x200)
        d[0] = 0x4D; d[1] = 0x5A
        d[0x3C] = 0x80
        d.replaceSubrange(0x80..<0x84, with: [0x50, 0x45, 0, 0])
        d[0x84] = UInt8(machine & 0xFF); d[0x85] = UInt8(machine >> 8)
        d[0x94] = 0xF0 // size of optional header
        let characteristics: UInt16 = isDLL ? 0x2022 : 0x0022
        d[0x96] = UInt8(characteristics & 0xFF); d[0x97] = UInt8(characteristics >> 8)
        let magic: UInt16 = machine == 0x8664 ? 0x20B : 0x10B
        d[0x98] = UInt8(magic & 0xFF); d[0x99] = UInt8(magic >> 8)
        try d.write(to: url)
    }

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alloy-dll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func refusesDriversWineCoreFilesAndOddNames() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sys = dir.appendingPathComponent("dongle.sys"); try dll(0x8664, at: sys)
        #expect(throws: CustomDLLs.Problem.driver("dongle.sys")) { try CustomDLLs.inspect(sys) }
        let core = dir.appendingPathComponent("ntdll.dll"); try dll(0x8664, at: core)
        #expect(throws: CustomDLLs.Problem.protectedName("ntdll.dll")) { try CustomDLLs.inspect(core) }
        let odd = dir.appendingPathComponent("a b;rm.dll"); try dll(0x8664, at: odd)
        #expect(throws: CustomDLLs.Problem.unsupportedName("a b;rm.dll")) { try CustomDLLs.inspect(odd) }
    }

    @Test func installsByArchitectureAndRestoresWhatItReplaced() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = WinePrefix(name: "Test", path: dir.appendingPathComponent("prefix"))
        let wow = prefix.path.appendingPathComponent("drive_c/windows/syswow64")
        try FileManager.default.createDirectory(at: wow, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: wow.appendingPathComponent("foo.dll"))

        let x86 = dir.appendingPathComponent("Foo.dll"); try dll(0x014c, at: x86)
        let added = try CustomDLLs.install(x86, into: prefix)
        #expect(added == CustomDLL(name: "foo.dll", machine: .x86))
        #expect(try Data(contentsOf: wow.appendingPathComponent("foo.dll")) == Data(contentsOf: x86))

        let x64 = dir.appendingPathComponent("bar.dll"); try dll(0x8664, at: x64)
        let bar = try CustomDLLs.install(x64, into: prefix)
        #expect(FileManager.default.fileExists(atPath: prefix.path.appendingPathComponent("drive_c/windows/system32/bar.dll").path))
        #expect(CustomDLLs.overrides([added, bar]) == "bar,foo=n,b")

        try CustomDLLs.remove(added, from: prefix)
        #expect(try String(contentsOf: wow.appendingPathComponent("foo.dll"), encoding: .utf8) == "original")
    }
}

struct WindowsVersionTests {
    @Test func readsTheVersionFromTheRegistry() {
        let reg = #"""
        [Software\\Microsoft\\Windows NT\\CurrentVersion] 1700000000
        "CSDVersion"=""
        "CurrentBuildNumber"="19045"
        "ProductName"="Windows 10 Pro"

        [Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts] 1700000000
        """#
        #expect(WindowsVersion.from(registryText: reg) == .win10)
        #expect(WindowsVersion.from(registryText: reg.replacingOccurrences(of: "19045", with: "7601")) == .win7)
        #expect(WindowsVersion.from(registryText: "nothing") == nil)
        #expect(WindowsVersion.win7.arguments == ["winecfg", "-v", "win7"])
    }
}
