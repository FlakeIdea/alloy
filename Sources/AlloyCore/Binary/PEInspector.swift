import Foundation

/// Architecture of a Windows PE image, from the COFF `Machine` field.
public enum PEMachine: String, Codable, Sendable {
    case x86 = "x86 (32-bit)"
    case x64 = "x86-64"
    case arm64 = "ARM64"
    case arm64ec = "ARM64EC"
    case unknown = "Unknown"

    init(rawMachine: UInt16) {
        switch rawMachine {
        case 0x014c: self = .x86
        case 0x8664: self = .x64
        case 0xaa64: self = .arm64
        case 0xa641: self = .arm64ec
        default: self = .unknown
        }
    }

    /// Whether the Rosetta-hosted Wine builds available on macOS can run this machine type.
    public var isSupportedByWineOnMac: Bool { self == .x86 || self == .x64 }
}

public enum PESubsystem: String, Codable, Sendable {
    case gui = "Windows GUI"
    case console = "Console"
    case other = "Other"
}

public struct PEInfo: Equatable, Sendable {
    public var machine: PEMachine
    public var is64BitImage: Bool
    public var isDLL: Bool
    public var subsystem: PESubsystem
}

/// Reads PE headers without executing or loading the file.
public enum PEInspector {
    public static func inspect(_ url: URL) throws -> PEInfo {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw AlloyError.executableNotFound(path: url.path)
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        guard let info = inspect(data: data) else {
            throw AlloyError.notAWindowsExecutable(path: url.lastPathComponent)
        }
        return info
    }

    /// Parses the DOS stub and COFF/optional headers. Returns nil for anything that is not a PE image.
    public static func inspect(data: Data) -> PEInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A else { return nil } // "MZ"
        let peOffset = Int(readUInt32(bytes, 0x3C))
        guard peOffset > 0, peOffset + 24 + 70 <= bytes.count else { return nil }
        guard bytes[peOffset] == 0x50, bytes[peOffset + 1] == 0x45,
              bytes[peOffset + 2] == 0, bytes[peOffset + 3] == 0 else { return nil } // "PE\0\0"
        let coff = peOffset + 4
        let machine = PEMachine(rawMachine: readUInt16(bytes, coff))
        let characteristics = readUInt16(bytes, coff + 18)
        let optional = coff + 20
        let magic = readUInt16(bytes, optional)
        guard magic == 0x10b || magic == 0x20b else { return nil }
        let subsystemRaw = readUInt16(bytes, optional + 68)
        let subsystem: PESubsystem = subsystemRaw == 2 ? .gui : (subsystemRaw == 3 ? .console : .other)
        return PEInfo(machine: machine,
                      is64BitImage: magic == 0x20b,
                      isDLL: characteristics & 0x2000 != 0,
                      subsystem: subsystem)
    }

    static func readUInt16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    static func readUInt32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
