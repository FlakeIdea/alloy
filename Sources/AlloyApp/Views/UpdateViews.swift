import AppKit
import SwiftUI
import AlloyCore

/// Checks flake.co.in for a newer Alloy and, when asked, installs it and restarts.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(AppRelease)
        case needsNewerMacOS(AppRelease)
        case downloading(AppRelease, Double)
        case installing(AppRelease)
        case failed(String, AppRelease?)
    }

    @Published private(set) var state: State = .idle

    /// The newer version found by the last check, for the sidebar notice.
    var available: AppRelease? {
        switch state {
        case .available(let r), .downloading(let r, _), .installing(let r): return r
        case .failed(_, let r): return r
        default: return nil
        }
    }

    var busy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    func check() async {
        guard !busy else { return }
        state = .checking
        do {
            switch try await AppUpdate.check(currentVersion: Flake.version) {
            case .upToDate(let latest): state = .upToDate(latest)
            case .available(let release): state = .available(release)
            case .needsNewerMacOS(let release): state = .needsNewerMacOS(release)
            }
        } catch {
            state = .failed(error.localizedDescription, nil)
        }
    }

    /// The once-a-day check at launch. Quiet: it changes nothing on screen unless it finds a newer version.
    func checkIfDue(model: AppModel) async {
        guard model.settings.checkForUpdates, ProcessInfo.processInfo.environment["ALLOY_SNAPSHOT_DIR"] == nil else { return }
        let key = "lastUpdateCheck"
        let last = UserDefaults.standard.double(forKey: key)
        if last > 0, Date().timeIntervalSince1970 - last < AppUpdate.interval { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        guard case .idle = state, let result = try? await AppUpdate.check(currentVersion: Flake.version) else { return }
        if case .available(let release) = result { state = .available(release) }
    }

    var canInstallInPlace: Bool { AppUpdate.canReplace(Bundle.main.bundleURL) }

    func install(_ release: AppRelease, gamesRunning: Bool) async {
        guard !gamesRunning else {
            state = .failed("Quit your games first. Alloy restarts to finish the update.", release)
            return
        }
        state = .downloading(release, 0)
        do {
            let app = try await AppUpdate.download(release, currentVersion: Flake.version) { fraction in
                Task { @MainActor in
                    if case .downloading(let r, _) = Updater.shared.state { Updater.shared.state = .downloading(r, fraction) }
                }
            }
            state = .installing(release)
            let current = Bundle.main.bundleURL
            try AppUpdate.install(app, replacing: current)
            try AppUpdate.relaunch(current)
            NSApplication.shared.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription, release)
        }
    }
}

extension AppModel {
    var anyGameRunning: Bool { states.values.contains { $0.isRunning } }
}

/// Alloy ▸ Check for Updates…
struct CheckForUpdatesMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Check for Updates…") {
            openWindow(id: "updates")
            Task { await Updater.shared.check() }
        }
    }
}

/// The Software Update window.
struct UpdateView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            Spacer(minLength: 0)
            Divider().opacity(0.4)
            HStack {
                Text(model.settings.checkForUpdates ? "Alloy also checks once a day." : "Daily checks are off in Settings.")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                buttons
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 500, height: 300)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Theme.steel)
        .task { if case .idle = updater.state { await updater.check() } }
    }

    @ViewBuilder private var content: some View {
        switch updater.state {
        case .idle, .checking:
            Text("Checking for updates…").font(.title3.weight(.semibold))
            ProgressView().controlSize(.small).padding(.top, 4)
        case .upToDate(let latest):
            Text("Alloy is up to date").font(.title3.weight(.semibold))
            Text("Version \(Flake.displayVersion) is the latest\(latest == Flake.version ? "" : " (newest published: \(latest))").")
                .foregroundStyle(.secondary)
        case .available(let release):
            Text("Alloy \(release.version) is available").font(.title3.weight(.semibold))
            Text("You have version \(Flake.displayVersion).").foregroundStyle(.secondary)
            notes(release)
            Text(updater.canInstallInPlace
                 ? "Alloy restarts to finish. Your games, settings and game engine stay as they are."
                 : "Alloy can't replace itself from where it is. Download the new version and drag it into Applications.")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
        case .needsNewerMacOS(let release):
            Text("Alloy \(release.version) needs a newer macOS").font(.title3.weight(.semibold))
            Text("It needs macOS \(release.minimumSystemVersion ?? "") or later. This version of Alloy keeps working.")
                .foregroundStyle(.secondary)
        case .downloading(let release, let fraction):
            Text("Downloading Alloy \(release.version)…").font(.title3.weight(.semibold))
            ProgressView(value: fraction).frame(width: 300).padding(.top, 4)
        case .installing(let release):
            Text("Installing Alloy \(release.version)…").font(.title3.weight(.semibold))
            Text("Alloy will restart in a moment.").foregroundStyle(.secondary)
        case .failed(let message, _):
            Text("The update didn't finish").font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func notes(_ release: AppRelease) -> some View {
        if let notes = release.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(notes.prefix(5), id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(note).font(.callout)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch updater.state {
        case .available(let release):
            Button("Later") { dismissWindow(id: "updates") }
            if updater.canInstallInPlace {
                Button("Install and Restart") { Task { await updater.install(release, gamesRunning: model.anyGameRunning) } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Download") { NSWorkspace.shared.open(release.url) }.keyboardShortcut(.defaultAction)
            }
        case .failed(_, let release):
            Button("Open flake.co.in") { NSWorkspace.shared.open(Flake.alloyPage) }
            if let release, updater.canInstallInPlace {
                Button("Try Again") { Task { await updater.install(release, gamesRunning: model.anyGameRunning) } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Try Again") { Task { await updater.check() } }.keyboardShortcut(.defaultAction)
            }
        case .downloading, .installing, .checking, .idle:
            Button("Close") { dismissWindow(id: "updates") }.disabled(true)
        default:
            Button("Done") { dismissWindow(id: "updates") }.keyboardShortcut(.defaultAction)
        }
    }
}

/// Shown above the status card in the sidebar once a check finds a newer version.
struct UpdateNotice: View {
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let release = updater.available {
            Button { openWindow(id: "updates") } label: {
                HStack(spacing: 8) {
                    Icon("arrow.down.circle.fill").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Alloy \(release.version) is available").font(.caption.bold())
                        Text("Click to update").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.flat)
            .glassCard(cornerRadius: 14, interactive: true)
        }
    }
}
