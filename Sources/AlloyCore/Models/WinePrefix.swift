import Foundation

public enum PrefixOrigin: String, Codable, Sendable {
    /// Created and owned by Alloy.
    case alloy
    /// Discovered CrossOver bottle. Listed read-only.
    case crossover

    /// Environments saved under the app's former names have origin "metalgate" or "wildrun".
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "metalgate" || raw == "wildrun" { self = .alloy; return }
        guard let value = PrefixOrigin(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown origin \(raw)"))
        }
        self = value
    }
}

public struct WinePrefix: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: URL
    public var runtimeID: String?
    /// "win64" for Alloy prefixes. Wine ≥ 9 on macOS runs 32-bit programs in a win64 prefix (new WoW64).
    public var architecture: String
    public var createdAt: Date
    public var origin: PrefixOrigin

    public init(id: UUID = UUID(), name: String, path: URL, runtimeID: String? = nil,
                architecture: String = "win64", createdAt: Date = Date(), origin: PrefixOrigin = .alloy) {
        self.id = id
        self.name = name
        self.path = path
        self.runtimeID = runtimeID
        self.architecture = architecture
        self.createdAt = createdAt
        self.origin = origin
    }

    public var isReadOnly: Bool { origin == .crossover }

    /// `wineboot` writes system.reg when it finishes initialising a prefix.
    public func isInitialized(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path.appendingPathComponent("system.reg").path)
    }

    public var system32: URL { path.appendingPathComponent("drive_c/windows/system32") }
}

public enum RuntimeKind: String, Codable, Sendable {
    case wineStable, wineDevel, wineStaging, gamePortingToolkit, homebrew, custom

    public var displayName: String {
        switch self {
        case .wineStable: return "Wine Stable"
        case .wineDevel: return "Wine Devel"
        case .wineStaging: return "Wine Staging"
        case .gamePortingToolkit: return "Game Porting Toolkit"
        case .homebrew: return "Wine (Homebrew)"
        case .custom: return "Custom Wine"
        }
    }
}

/// A Wine installation on disk.
public struct WineRuntime: Codable, Identifiable, Hashable, Sendable {
    public var id: String { wineBinary.path }
    public var kind: RuntimeKind
    public var wineBinary: URL
    /// Installation root (the directory containing `bin/`).
    public var root: URL
    public var version: String?
    public var architectures: [HostArchitecture]
    public var hasMoltenVK: Bool
    public var hasD3DMetal: Bool
    /// DXMT's builtin DLLs (`winemetal.dll` + `winemetal.so`) are installed in this runtime's lib/wine.
    public var hasDXMT: Bool
    /// Wine's ntdll reads WINEMSYNC (CrossOver-derived builds: Mach-semaphore synchronisation).
    public var hasMSync: Bool
    /// Wine's ntdll reads WINEESYNC (Wine Staging and Game Porting Toolkit builds).
    public var hasESync: Bool
    /// An NVIDIA NGX shim that turns DLSS into MetalFX: DXMT's `nvngx.dll`, or D3DMetal's `nvngx-on-metalfx.dll`.
    public var hasNVNGX: Bool
    /// D3DMetal maps DLSS Frame Generation onto MetalFX frame interpolation (present in D3DMetal 4).
    public var hasFrameInterpolation: Bool
    /// kernelbase starts Steam's web helper with its compositor in-process, so Steam's windows draw
    /// (patches/wine, or Proton's equivalent). Without it they stay black.
    public var hasSteamWebHelperFix: Bool
    /// bcrypt and schannel are built with GnuTLS, so Windows programs can check certificates and use HTTPS.
    public var hasGnuTLS: Bool
    /// winegstreamer with GStreamer and its plugins in `lib/gstreamer-1.0`, so games can play videos (MP4/H.264).
    public var hasGStreamer: Bool
    /// Name shown for Alloy-managed runtimes (from their manifest).
    public var customName: String?

    public init(kind: RuntimeKind, wineBinary: URL, root: URL, version: String? = nil,
                architectures: [HostArchitecture] = [], hasMoltenVK: Bool = false, hasD3DMetal: Bool = false,
                hasDXMT: Bool = false, hasMSync: Bool = false, hasESync: Bool = false,
                hasNVNGX: Bool = false, hasFrameInterpolation: Bool = false,
                hasSteamWebHelperFix: Bool = false, hasGnuTLS: Bool = false, hasGStreamer: Bool = false) {
        self.kind = kind
        self.wineBinary = wineBinary
        self.root = root
        self.version = version
        self.architectures = architectures
        self.hasMoltenVK = hasMoltenVK
        self.hasD3DMetal = hasD3DMetal
        self.hasDXMT = hasDXMT
        self.hasMSync = hasMSync
        self.hasESync = hasESync
        self.hasNVNGX = hasNVNGX
        self.hasFrameInterpolation = hasFrameInterpolation
        self.hasSteamWebHelperFix = hasSteamWebHelperFix
        self.hasGnuTLS = hasGnuTLS
        self.hasGStreamer = hasGStreamer
    }

    public var displayName: String {
        if let customName { return version.map { "\(customName) · Wine \($0)" } ?? customName }
        return version.map { "\(kind.displayName) \($0)" } ?? kind.displayName
    }

    public var requiresRosetta: Bool {
        // Intel Macs run x86_64 natively.
        SystemCheck.isAppleSilicon && !architectures.contains(.arm64) && architectures.contains(.x86_64)
    }

    public var wineserver: URL { wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver") }
}
