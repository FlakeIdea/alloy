import Foundation

/// Apple's Rosetta 2, which the game engine needs: free Wine builds for macOS, and the engine built from them,
/// are x86_64. New Macs do not have it until something asks for it.
public enum Rosetta {
    /// A file Apple's installer adds (the diagnostics report checks the same one).
    public static let runtimePath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
    public static let licenceURL = URL(string: "https://www.apple.com/legal/sla/")!

    /// True when the engine can run: Rosetta is installed, or this is an Intel Mac, which doesn't need it.
    public static func isInstalled(fileManager: FileManager = .default) -> Bool {
        !SystemCheck.isAppleSilicon || fileManager.fileExists(atPath: runtimePath)
    }

    /// The command Alloy runs, and the one people can type in Terminal themselves.
    public static let installArguments = ["--install-rosetta", "--agree-to-license"]

    /// Runs Apple's installer and waits for it. Call only after the person agreed to Apple's licence in the app:
    /// `--agree-to-license` passes that agreement on. Blocks, so run it off the main thread.
    public static func install() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = installArguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { throw AlloyError.launchFailed("softwareupdate: \(error.localizedDescription)") }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, isInstalled() else {
            let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AlloyError.runtimeUnavailable(
                "Rosetta 2 could not be installed\(text.isEmpty ? "" : ": " + String(text.suffix(300))). "
                + "You can install it in Terminal with: softwareupdate " + installArguments.joined(separator: " "))
        }
    }
}
