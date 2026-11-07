import AppKit
import SwiftUI
import AlloyCore

@main
struct AlloyApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Lets the SwiftPM-built binary behave as a normal foreground app when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Alloy") {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutMenuItem(); CheckForUpdatesMenuItem() }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Alloy Setup Guide") { NSWorkspace.shared.open(Flake.guide) }
                Button("Graphics Guide") { model.sheet = .guide }
                Divider()
                Button("Contact Support…") { NSWorkspace.shared.open(Flake.email(subject: "Alloy support")) }
                Button("Report a Bug…") { NSWorkspace.shared.open(Flake.bugReport) }
                Button("Visit flake.co.in") { NSWorkspace.shared.open(Flake.website) }
                Divider()
                Button("Terms of Use and Privacy") { model.sheet = .terms }
                Button("Open-Source Licences") { model.sheet = .licences }
                Button("Alloy Source Code") { NSWorkspace.shared.open(Flake.sourceCode) }
            }
            CommandMenu("Game") {
                // The system-wide ⌥⌘M does this while a game runs; a menu key equivalent as well would toggle twice.
                Button("Show or Hide Metrics   \(MetricsHotKey.display)") { MetricsHUD.toggle() }
                Divider()
                Button("Add DLL to This Game or App…") { if let game = model.game(model.selectedGameID) { model.chooseDLLs(for: game) } }
                    .disabled(model.selectedGameID == nil)
            }
        }

        Window("Software Update", id: "updates") { UpdateView().environmentObject(model) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .defaultPosition(.center)

        Window("About Alloy", id: "about") { AboutAlloyView().background(CenteredOnOpen()) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .defaultPosition(.center)
    }
}

/// The About Alloy menu item; a view so it can open the About window.
private struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About Alloy") { openWindow(id: "about") }
    }
}

/// "Graphite": white on near-black, like the app icon. Colour is kept for status only (ready, warning, problem),
/// so it always means something.
enum Theme {
    /// Off-white: the main highlight and the fill of primary buttons (which then carry `onFill` text).
    static let accent = Color(white: 0.94)
    /// Light grey, for links and secondary highlights.
    static let accentAlt = Color(white: 0.74)
    /// Mid grey, the tint for switches and other system controls (white would hide their knobs).
    static let steel = Color(white: 0.56)
    static let success = Color(red: 0.36, green: 0.85, blue: 0.60)
    static let warning = Color(red: 1.0, green: 0.82, blue: 0.20)
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.36)
    /// For symbols and thin strokes.
    static let gradient = LinearGradient(colors: [Color(white: 0.98), Color(white: 0.76)], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// For filled surfaces; text on them uses `onFill`.
    static let fill = LinearGradient(colors: [Color(white: 0.96), Color(white: 0.80)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let onFill = Color(white: 0.08)
    /// The window background, behind panels and the About window.
    static let background = Color(white: 0.09)
    /// The main window's flat near-black canvas.
    static let canvas = Color(white: 0.045)
    /// Cards and panels on the canvas.
    static let surface = Color.white.opacity(0.035)
    /// One-pixel edges and dividers.
    static let hairline = Color.white.opacity(0.09)
}

/// Neutral graphite behind the content with a faint light from the top, so glass surfaces have something to refract.
struct Backdrop: View {
    var body: some View {
        Theme.canvas.ignoresSafeArea()
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    /// Pages already opened stay alive, hidden, so switching back to them is instant instead of rebuilt.
    @State private var opened: Set<SidebarItem> = [.library]

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ZStack {
                ForEach(SidebarItem.allCases) { item in
                    if opened.contains(item) || (model.selection ?? .library) == item {
                        let shown = (model.selection ?? .library) == item
                        page(item)
                            .opacity(shown ? 1 : 0)
                            .allowsHitTesting(shown)
                            // Hidden pages' buttons and keyboard shortcuts (Return to play) must not fire.
                            .disabled(!shown)
                            .accessibilityHidden(!shown)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keeps the shortcut for the Flake page, which has no tab.
            .background { Button("") { model.selection = .flake }.keyboardShortcut("4", modifiers: .command).hidden() }
        }
        .ignoresSafeArea(edges: .top)
        .background(Backdrop())
        .background(WindowChrome())
        .disabled(model.sheet?.isWizard == true)
        .overlay { if case .wizard(let page) = model.sheet { WizardOverlay(page: page) } }
        .tint(Theme.steel)
        .onChange(of: model.selection) { _, item in
            if item == .library { model.selectedGameID = nil }
            if let item { opened.insert(item) }
            if ProcessInfo.processInfo.environment["ALLOY_CLICK_LOG"] != nil {
                FileHandle.standardError.write(Data("selected \(item?.rawValue ?? "-") at \(CFAbsoluteTimeGetCurrent())\n".utf8))
            }
        }
        .sheet(item: $model.pendingLaunch) { LaunchConfirmationSheet(pending: $0) }
        .sheet(item: Binding(get: { model.pendingAdd.map(IdentifiedURL.init) }, set: { model.pendingAdd = $0?.url })) {
            AddGameSheet(initial: $0.url, isApp: model.addingApp)
        }
        .sheet(item: Binding(get: { model.pendingSetup.map(IdentifiedURL.init) }, set: { model.pendingSetup = $0?.url })) {
            InstallGameSheet(initial: $0.url)
        }
        .sheet(item: Binding(get: { model.sheet?.isWizard == true ? nil : model.sheet }, set: { model.sheet = $0 })) { sheet in
            switch sheet {
            case .terms: TermsSheet()
            case .guide: GraphicsGuideSheet()
            case .licences: LicencesSheet()
            case .wizard: EmptyView()
            case .storeGame: StoreGameSheet()
            }
        }
        .alert(item: $model.alert) { Alert(title: Text($0.title), message: Text($0.message)) }
        .task { await SnapshotMode.runIfRequested(model: model) }
        .task { await Updater.shared.checkIfDue(model: model) }
    }
}

extension RootView {
    @ViewBuilder func page(_ item: SidebarItem) -> some View {
        switch item {
        case .library: LibraryView()
        case .setup: SetupView()
        case .advanced: AdvancedView()
        case .flake: FlakeView()
        }
    }
}

/// The setup wizard as a panel over the dimmed window rather than a sheet: macOS refuses to quit an app while a sheet
/// is open, and the wizard opens by itself at every launch until the terms are accepted, so as a sheet its Quit
/// button, ⌘Q, logging out and shutting down would all be refused.
private struct WizardOverlay: View {
    let page: WizardPage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            SetupWizardPanel(start: page)
                .background(Color(white: 0.13), in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .id(page)
        }
    }
}

/// Development aid: `ALLOY_SNAPSHOT_DIR=/path` captures each page of Alloy's window to PNG and quits.
/// Uses `screencapture` so system-drawn glass and materials appear as on screen; without Screen Recording
/// permission it falls back to rendering the view hierarchy, which leaves glass surfaces blank.
@MainActor
enum SnapshotMode {
    static func runIfRequested(model: AppModel) async {
        if ProcessInfo.processInfo.environment["ALLOY_TIMING"] != nil { await timeTabs(model: model); return }
        guard let dir = ProcessInfo.processInfo.environment["ALLOY_SNAPSHOT_DIR"] else { return }
        try? await Task.sleep(for: .seconds(2))
        var pages: [(String, () -> Void)] = SidebarItem.allCases.map { item in (item.rawValue, { model.selection = item }) }
        pages += AdvancedTab.allCases.map { tab in ("advanced-\(tab.rawValue)", { model.showAdvanced(tab) }) }
        pages += WizardPage.allCases.map { page in ("wizard-\(page.title.lowercased())", { model.sheet = .wizard(page) }) }
        pages.append(("guide", { model.sheet = .guide }))
        pages.append(("terms", { model.sheet = .terms }))
        pages.append(("licences", { model.sheet = .licences }))
        pages.append(("store-game", { model.sheet = .storeGame }))
        // ALLOY_SNAPSHOT_GAME picks which game's page is captured; otherwise the first in the library.
        let pick = ProcessInfo.processInfo.environment["ALLOY_SNAPSHOT_GAME"]
        if let game = model.games.first(where: { $0.name == pick }) ?? model.games.first {
            // Opening a game must follow the switch to Library, which clears the open game.
            pages.append(("game", { model.selectedGameID = game.id }))
        }
        for (name, show) in pages {
            if name == "game" { model.sheet = nil; model.selection = .library; try? await Task.sleep(for: .seconds(0.5)) }
            if model.sheet != nil, name != "game" { model.sheet = nil; try? await Task.sleep(for: .seconds(0.6)) }
            // A window with a sheet attached can't be captured on its own, so the page behind is captured first.
            let behind = URL(fileURLWithPath: dir).appendingPathComponent("behind-capture.png")
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.sheetParent == nil }),
               window.attachedSheet == nil { _ = capture(window: window, to: behind) }
            show()
            try? await Task.sleep(for: .seconds(1.2))
            // The main window's capture includes an open sheet and the wizard; a sheet window on its own does not capture.
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            if let sheet = window.attachedSheet, compose(behind: behind, window: window, sheet: sheet, to: url) { continue }
            if capture(window: window, to: url) { continue }
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        // The About window, in its own window.
        let about = NSWindow(contentViewController: NSHostingController(rootView: AboutAlloyView()))
        about.styleMask = [.titled, .closable, .fullSizeContentView]
        about.titlebarAppearsTransparent = true
        about.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(2.5))
        _ = capture(window: about, to: URL(fileURLWithPath: dir).appendingPathComponent("about.png"))
        about.close()
        // macOS won't quit while a sheet is open.
        model.sheet = nil
        try? await Task.sleep(for: .seconds(0.6))
        NSApplication.shared.terminate(nil)
    }

    /// Development aid: `ALLOY_TIMING=1` switches between the tabs and prints how long each switch took to draw.
    static func timeTabs(model: AppModel) async {
        try? await Task.sleep(for: .seconds(3))
        model.sheet = nil
        let order: [SidebarItem] = [.setup, .advanced, .flake, .library]
        for round in 0..<4 {
            for item in order {
                let start = CFAbsoluteTimeGetCurrent()
                model.selection = item
                await withCheckedContinuation { done in
                    DispatchQueue.main.async { NSApplication.shared.windows.first?.displayIfNeeded(); DispatchQueue.main.async { done.resume() } }
                }
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                FileHandle.standardError.write(Data("timing round=\(round) tab=\(item.rawValue) ms=\(String(format: "%.1f", ms))\n".utf8))
                try? await Task.sleep(for: .seconds(0.4))
            }
        }
        NSApplication.shared.terminate(nil)
    }

    /// The page captured before the sheet opened, with the sheet's own drawing on top where it sits, its corners
    /// rounded and a shadow under it as macOS draws them.
    private static func compose(behind: URL, window: NSWindow, sheet: NSWindow, to url: URL) -> Bool {
        defer { try? FileManager.default.removeItem(at: behind) }
        guard let base = NSImage(contentsOf: behind)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let view = sheet.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let top = rep.cgImage else { return false }
        let scale = CGFloat(base.width) / window.frame.width
        let frame = CGRect(x: (sheet.frame.minX - window.frame.minX) * scale, y: (sheet.frame.minY - window.frame.minY) * scale,
                           width: sheet.frame.width * scale, height: sheet.frame.height * scale)
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        let shape = CGPath(roundedRect: frame, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 40 * scale, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        context.addPath(shape); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(shape); context.clip()
        context.draw(top, in: frame)
        context.restoreGState()
        context.addPath(shape); context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(1 * scale); context.strokePath()
        guard let image = context.makeImage() else { return false }
        return (try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)) != nil
    }

    private static func capture(window: NSWindow, to url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
    }
}

struct RuntimeStatusBadge: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let ready = model.setupStepsLeft == 0
        HStack(spacing: 8) {
            Circle().fill(ready ? Theme.success : Theme.warning).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(ready ? "Ready to play" : !model.rosettaInstalled ? "Rosetta 2 needed" : "Game engine needed").font(.caption.bold())
                Text(ready ? "Game engine installed" : "Open Setup to install it").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .glassCard(cornerRadius: 14, interactive: true)
        .onTapGesture { model.selection = .setup }
    }
}

/// Lets an optional URL drive `.sheet(item:)`.
struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Shown before an executable runs for the first time, or after it changed on disk.
struct LaunchConfirmationSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let pending: PendingLaunch
    @State private var remember = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label { Text("Run this Windows program?") } icon: { Icon("exclamationmark.shield.fill") }
                .font(.title2.bold()).foregroundStyle(Theme.warning)
            Text("Windows programs run with your user permissions inside the selected environment. Only run software you trust.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Program", pending.game.executableURL.lastPathComponent)
                row("Location", LogRedactor.redact(pending.game.executableURL.deletingLastPathComponent().path))
                row("Architecture", "\(pending.info.machine.rawValue), \(pending.info.subsystem.rawValue)")
                row("Runtime", pending.runtime.displayName + (pending.runtime.requiresRosetta ? " (Rosetta 2)" : ""))
                row("Environment", pending.prefix.name)
                row("Graphics", "\(pending.game.graphics.backend.displayName) (requested)")
                row("Arguments", pending.game.arguments.isEmpty ? "—" : ArgumentParser.join(pending.game.arguments))
                row("Privileges", "Standard user (never administrator)")
            }
            .font(.callout)
            Toggle("Don’t ask again for this exact file (asks again if it changes)", isOn: $remember)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.pendingLaunch = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Run") {
                    let p = pending
                    model.pendingLaunch = nil
                    dismiss()
                    model.startLaunch(p, remember: remember)
                }
                .keyboardShortcut(.defaultAction)
                .primaryAction(Theme.accent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(2)
        }
    }
}

/// Centres its window on screen each time it opens. SwiftUI's `defaultPosition` applies only the first time; after
/// that the window reopens wherever it was last left.
struct CenteredOnOpen: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.setFrameAutosaveName("")
            window.isRestorable = false
            DispatchQueue.main.async { window.center() }
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}
