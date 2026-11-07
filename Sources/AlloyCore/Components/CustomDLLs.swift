import Foundation

/// A Windows DLL the person added to a game's environment themselves, such as one a program reports missing.
public struct CustomDLL: Codable, Hashable, Sendable, Identifiable {
    /// File name, lowercased, such as "foo.dll".
    public var name: String
    public var machine: PEMachine
    public var id: String { "\(name)-\(machine.rawValue)" }
    public init(name: String, machine: PEMachine) { self.name = name; self.machine = machine }

    /// Where it goes: 64-bit DLLs in system32, 32-bit ones in syswow64.
    public var folder: String { machine == .x64 ? "drive_c/windows/system32" : "drive_c/windows/syswow64" }
    public var architectureName: String { machine == .x64 ? "64-bit" : "32-bit" }
}

/// Adds DLLs the person chose to an environment and tells Wine to use them before its own.
///
/// Only files the person picks are used: Alloy never downloads DLLs, since DLL download sites are a common source of
/// malware and most Microsoft DLLs may not be redistributed. Windows drivers (.sys) can't be added: Wine cannot load
/// kernel drivers at all.
public enum CustomDLLs {
    /// Wine's core libraries. Replacing these with Windows copies stops every program in the environment.
    public static let protected: Set<String> = [
        "ntdll.dll", "kernel32.dll", "kernelbase.dll", "user32.dll", "gdi32.dll", "win32u.dll", "advapi32.dll",
        "wow64.dll", "wow64cpu.dll", "wow64win.dll", "winex11.drv", "winemac.drv", "wineboot.exe", "rpcrt4.dll",
        "ole32.dll", "combase.dll", "sechost.dll", "ucrtbase.dll", "msvcrt.dll", "shell32.dll", "ws2_32.dll",
        "winevulkan.dll", "opengl32.dll", "dxgi.dll", "d3d11.dll", "d3d10core.dll", "d3d12.dll", "nvngx.dll", "nvapi64.dll",
    ]

    public enum Problem: Error, Equatable, LocalizedError {
        case notADLL(String), driver(String), unsupportedName(String), protectedName(String), architecture(String, String)

        public var errorDescription: String? {
            switch self {
            case .notADLL(let n): return "\(n) isn't a Windows DLL."
            case .driver(let n): return "\(n) is a Windows driver. Wine can't load Windows drivers, so programs that need one (anti-cheat, hardware dongles, VPNs) can't work in Alloy."
            case .unsupportedName(let n): return "\(n) has a name Alloy can't use. Keep the DLL's original file name."
            case .protectedName(let n): return "\(n) is part of Wine itself. Replacing it with a Windows copy would stop every program in this environment, so Alloy doesn't allow it."
            case .architecture(let n, let m): return "\(n) is built for \(m). Only 32-bit and 64-bit Intel (x86) DLLs work."
            }
        }
    }

    /// Checks the file without loading it.
    public static func inspect(_ url: URL) throws -> CustomDLL {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".sys") { throw Problem.driver(url.lastPathComponent) }
        guard name.range(of: #"^[a-z0-9_.+-]{1,64}\.dll$"#, options: .regularExpression) != nil else {
            throw name.hasSuffix(".dll") ? Problem.unsupportedName(url.lastPathComponent) : Problem.notADLL(url.lastPathComponent)
        }
        guard !protected.contains(name) else { throw Problem.protectedName(url.lastPathComponent) }
        guard let info = try? PEInspector.inspect(url), info.isDLL else { throw Problem.notADLL(url.lastPathComponent) }
        guard info.machine == .x64 || info.machine == .x86 else { throw Problem.architecture(url.lastPathComponent, info.machine.rawValue) }
        return CustomDLL(name: name, machine: info.machine)
    }

    private static func backup(_ target: URL) -> URL { target.appendingPathExtension("alloy-original") }

    /// Copies the DLL into the environment, keeping any file it replaces so removing it puts that back.
    @discardableResult
    public static func install(_ url: URL, into prefix: WinePrefix, fileManager: FileManager = .default) throws -> CustomDLL {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        let dll = try inspect(url)
        let folder = prefix.path.appendingPathComponent(dll.folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(dll.name)
        if fileManager.fileExists(atPath: target.path) {
            if !fileManager.fileExists(atPath: backup(target).path) {
                try fileManager.moveItem(at: target, to: backup(target))
            } else {
                try fileManager.removeItem(at: target)
            }
        }
        try fileManager.copyItem(at: url, to: target)
        return dll
    }

    /// Removes an added DLL and restores what it replaced.
    public static func remove(_ dll: CustomDLL, from prefix: WinePrefix, fileManager: FileManager = .default) throws {
        guard !prefix.isReadOnly else { throw AlloyError.prefixReadOnly(name: prefix.name) }
        let target = prefix.path.appendingPathComponent(dll.folder).appendingPathComponent(dll.name)
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        if fileManager.fileExists(atPath: backup(target).path) { try fileManager.moveItem(at: backup(target), to: target) }
    }

    /// WINEDLLOVERRIDES entry that makes Wine load these copies before its own.
    public static func overrides(_ dlls: [CustomDLL]) -> String? {
        let names = Set(dlls.map { ($0.name as NSString).deletingPathExtension }).sorted()
        return names.isEmpty ? nil : names.joined(separator: ",") + "=n,b"
    }
}
