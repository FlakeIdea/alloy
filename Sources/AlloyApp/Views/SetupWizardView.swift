import AppKit
import SwiftUI
import AlloyCore

/// The setup wizard: Welcome, Terms, Install (the Mac check, Rosetta 2, the game engine and the Windows components,
/// with one button) and Ready. First launch starts at Welcome; after the .pkg installer (which showed the terms) and
/// from Setup it starts at Install. Until the terms are accepted it can only be left by agreeing or quitting.
struct SetupWizardPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var page: WizardPage

    init(start: WizardPage) { _page = State(initialValue: start) }

    var body: some View {
        VStack(spacing: 0) {
            WizardSteps(current: page)
                .padding(.top, 20).padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .background(Theme.accent.opacity(0.05))
            Divider()
            Group {
                switch page {
                case .welcome: welcome
                case .terms: terms
                case .install: install
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer.controlSize(.large).padding(20)
        }
        .frame(width: 680, height: 620)
        .onAppear {
            model.refreshSetupStates()
            if model.manifest == nil, model.settings.componentsURL != nil { model.loadManifest() }
        }
    }

    // MARK: Pages

    var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text("Welcome to Alloy").font(.largeTitle.bold())
            MadeByFlake(size: 12)
            Text("Alloy runs Windows games on your Mac. Setup takes a few minutes: read the terms, then one button "
                 + "installs the game engine and the Windows parts games need.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 470).padding(.top, 8)
            Text("Alloy never moves or changes your game files, and nothing runs until you press Play.")
                .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                .frame(maxWidth: 470)
        }
        .padding(32)
        .padding(.top, 12)
    }

    var terms: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Terms.title).font(.title2.bold())
                Text("Version \(Terms.version), last updated \(Terms.updated)").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 8)
            ScrollView { TermsText().padding(.horizontal, 28).padding(.vertical, 12) }
        }
    }

    var install: some View {
        let states = model.setupStates
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(allDone ? "Everything is installed" : "Install what games need").font(.title2.bold())
                Text(allDone ? "Your Mac is ready for Windows games." : "One click installs everything below. Already installed items are skipped.")
                    .foregroundStyle(.secondary)
            }
            ForEach(SetupRunner.Step.allCases) { step in
                SetupStepRow(step: step, state: states[step] ?? .waiting, detail: detail(for: step))
            }
            Spacer(minLength: 0)
            if needsRosetta && !macFailed {
                HStack(spacing: 6) {
                    Text("Rosetta 2 is Apple software. Installing it means you accept Apple's licence for it.")
                    Button("Read Apple's licence") { NSWorkspace.shared.open(Rosetta.licenceURL) }
                        .buttonStyle(.flat).foregroundStyle(Theme.accentAlt)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(28)
    }

    var done: some View {
        VStack(spacing: 16) {
            Icon("checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.onFill)
                .frame(width: 68, height: 68).background(Circle().fill(Theme.fill))
            Text("You're ready to play").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 16) {
                numbered(1, "Add a game", "Games → Add Game, or drag a game's folder, .exe or setup file onto the Games page.")
                numbered(2, "Press Play", "The first start shows exactly which file will run.")
                numbered(3, "Pick a graphics mode", "Balanced suits most games. “Which should I choose?” on the game page explains the rest.")
            }
            .frame(maxWidth: 500)
            .padding(.top, 10)
        }
        .padding(32)
    }

    func numbered(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.headline.monospacedDigit()).foregroundStyle(Theme.onFill)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.fill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder var footer: some View {
        HStack {
            switch page {
            case .welcome:
                if !model.termsAccepted { Button("Quit") { NSApplication.shared.terminate(nil) } }
                Spacer()
                Button("Continue") { page = model.termsAccepted ? .install : .terms }
                    .keyboardShortcut(.defaultAction).primaryAction()
            case .terms:
                Button("Back") { page = .welcome }
                Text("Choosing “Agree” means you accept these terms.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                Button("Agree") { model.acceptTerms(); page = .install }
                    .keyboardShortcut(.defaultAction).primaryAction()
            case .install:
                if model.runningSetup {
                    Text("Setup keeps going if you close this window. Setup in the sidebar shows its progress.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Hide") { model.sheet = nil }
                } else if allDone {
                    Spacer()
                    Button("Continue") { page = .done }.keyboardShortcut(.defaultAction).primaryAction()
                } else {
                    Spacer()
                    Button("Later") { model.sheet = nil }
                    Button(needsRosetta ? "Agree and Install Everything" : "Install Everything") { model.installEverything() }
                        .keyboardShortcut(.defaultAction).primaryAction().disabled(macFailed)
                }
            case .done:
                Spacer()
                Button("Graphics Guide") { model.sheet = .guide }
                Button("Start Playing") { model.sheet = nil; model.selection = .library }
                    .keyboardShortcut(.defaultAction).primaryAction()
            }
        }
    }

    // MARK: State

    var macFailed: Bool { if case .failed = model.setupStates[.mac] { true } else { false } }
    var allDone: Bool { SetupRunner.Step.allCases.allSatisfy { model.setupStates[$0]?.isFinished == true } }
    var needsRosetta: Bool { !(model.setupStates[.rosetta]?.isFinished ?? false) }

    func detail(for step: SetupRunner.Step) -> String {
        switch step {
        case .mac:
            "Apple silicon, macOS 14 or later and \(SystemCheck.gigabytes(SystemCheck.requiredFreeBytes)) free."
        case .rosetta:
            "Apple's free translator. The game engine is built for Intel processors and runs through it."
        case .engine:
            "Wine with DXMT for DirectX 10 and 11 games, video playback and MetalFX upscaling."
                + (model.manifest?.runtimes.first.map { " \(RuntimeInstaller.megabytes($0.downloadBytes)) download." } ?? "")
        case .components:
            "Visual C++ from Microsoft and .NET support from WineHQ, about \(ComponentDownloads.approximateMegabytes) MB. "
                + "Downloaded now and added to each game when it first starts."
        }
    }
}

/// The steps along the top of the wizard, drawn like the timeline on the Flake website: the line grows to the
/// current page and each circle fills in as it is reached.
private struct WizardSteps: View {
    let current: WizardPage

    var body: some View {
        TimelineSteps(stops: WizardPage.allCases.map { .init(id: $0.rawValue, label: $0.title) },
                      current: current.rawValue, ticks: true, dot: 16)
            .frame(width: 520)
    }
}

private struct SetupStepRow: View {
    let step: SetupRunner.Step
    let state: SetupRunner.State
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Icon(symbol).font(.title2).foregroundStyle(Theme.gradient).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    badge
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                status
            }
        }
    }

    var title: String {
        switch step {
        case .mac: "This Mac"
        case .rosetta: "Rosetta 2"
        case .engine: "Game engine"
        case .components: "Windows components"
        }
    }

    var symbol: String {
        switch step {
        case .mac: "laptopcomputer"
        case .rosetta: "arrow.triangle.2.circlepath"
        case .engine: "bolt.fill"
        case .components: "puzzlepiece.extension.fill"
        }
    }

    @ViewBuilder var badge: some View {
        switch state {
        case .waiting: Label { Text("To install") } icon: { Icon("circle") }.foregroundStyle(.secondary)
        case .working: ProgressView().controlSize(.small)
        case .done: Label { Text("Ready") } icon: { Icon("checkmark.circle.fill") }.foregroundStyle(Theme.success)
        case .failed: Label { Text("Problem") } icon: { Icon("exclamationmark.triangle.fill") }.foregroundStyle(Theme.warning)
        case .skipped: Label { Text("Skipped") } icon: { Icon("minus.circle") }.foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var status: some View {
        switch state {
        case .waiting: EmptyView()
        case .working(let text, let fraction):
            if let fraction { ProgressView(value: fraction) { Text(text).font(.caption) } } else { Text(text).font(.caption).foregroundStyle(.secondary) }
        case .done(let text): Text(text).font(.caption).foregroundStyle(Theme.success)
        case .failed(let text): Text(text).font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
        case .skipped(let text): Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
