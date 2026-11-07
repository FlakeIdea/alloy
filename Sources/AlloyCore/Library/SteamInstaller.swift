import Foundation

/// Installs Valve's Steam client into an Alloy environment, so games are installed and updated the normal way.
/// Only Valve's own installer is run, and only after the user asks for it. `StoreInstaller` does the work.
public enum SteamInstaller {
    /// Valve's official installer, about 2 MB. Steam downloads its own client update on first start.
    public static var installerURL: URL { GameStore.steam.installerURL }

    /// Where the installer puts Steam: `Program Files (x86)` by default, `Program Files` on some versions.
    public static func steamExecutable(in prefix: WinePrefix, fileManager: FileManager = .default) -> URL? {
        StoreInstaller.executable(of: .steam, in: prefix, fileManager: fileManager)
    }

    /// The installer, run silently (NSIS `/S`) like any game so it gets the environment's runtime and settings.
    public static func installerGame(installer: URL, prefix: WinePrefix, graphics: GraphicsConfiguration) -> Game {
        StoreInstaller.installerGame(.steam, installer: installer, prefix: prefix, graphics: graphics)
    }

    /// What a runtime lacks for Steam. Its windows are Chromium web views, which draw only with the web helper fix
    /// in kernelbase, and it signs in only when Wine can check its servers' certificates (GnuTLS).
    /// `scripts/patch-wine-runtime.sh` adds both to runtimes built from CrossOver's sources.
    public static func missingRequirements(in runtime: WineRuntime) -> [String] {
        GameStore.steam.missingRequirements(in: runtime)
    }

    public static func isSteamClient(_ game: Game) -> Bool { GameStore.store(for: game) == .steam }

    /// Library entry for the installed client. Games installed through it run in the same environment.
    public static func libraryEntry(steam: URL, prefix: WinePrefix, graphics: GraphicsConfiguration) -> Game {
        StoreInstaller.libraryEntry(.steam, executable: steam, prefix: prefix, graphics: graphics)
    }

    /// Sets up the environment, downloads the installer, runs it silently and returns the library entry.
    public static func install(into prefix: WinePrefix, runtime: WineRuntime, backend: WineBackend,
                               graphics: GraphicsConfiguration, installer: URL,
                               progress: @Sendable (String) -> Void) async throws -> Game {
        try await StoreInstaller.install(.steam, into: prefix, runtime: runtime, backend: backend, graphics: graphics,
                                         installer: installer, progress: progress)
    }
}
