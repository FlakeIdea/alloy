import Foundation

public enum HostArchitecture: String, Codable, Sendable, CaseIterable {
    case arm64
    case x86_64
}

/// Reads Mach-O headers to tell whether a host binary (e.g. `wine`) needs Rosetta 2.
public enum MachOInspector {
    public enum Result: Equatable, Sendable {
        case machO([HostArchitecture])
        case script
        case unknown
    }

    public static func inspect(_ url: URL) -> Result {
        let resolved = url.resolvingSymlinksInPath()
        guard let handle = try? FileHandle(forReadingFrom: resolved) else { return .unknown }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        return inspect(data: data)
    }

    public static func inspect(data: Data) -> Result {
        let b = [UInt8](data)
        guard b.count >= 8 else { return .unknown }
        if b[0] == 0x23, b[1] == 0x21 { return .script } // "#!"
        let magicBE = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        switch magicBE {
        case 0xCFFA_EDFE, 0xCEFA_EDFE: // thin, little-endian 64/32-bit
            let cpu = UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24
            return .machO(architecture(cpu).map { [$0] } ?? [])
        case 0xCAFE_BABE, 0xCAFE_BABF: // fat (big-endian)
            let count = Int(readBE32(b, 4))
            let entrySize = magicBE == 0xCAFE_BABF ? 32 : 20
            var archs: [HostArchitecture] = []
            for i in 0..<min(count, 16) {
                let offset = 8 + i * entrySize
                guard offset + 4 <= b.count else { break }
                if let a = architecture(readBE32(b, offset)) { archs.append(a) }
            }
            return .machO(archs)
        default:
            return .unknown
        }
    }

    static func architecture(_ cpu: UInt32) -> HostArchitecture? {
        switch cpu {
        case 0x0100_000C: return .arm64
        case 0x0100_0007: return .x86_64
        default: return nil
        }
    }

    static func readBE32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
    }
}
