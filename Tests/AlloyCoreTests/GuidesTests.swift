import Foundation
import Testing
@testable import AlloyCore

@Suite struct GuidesTests {
    static let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("docs")

    /// The website copies must say what the app says. Regenerate with `alloyctl write-docs docs`.
    @Test func publishedDocsMatchTheApp() throws {
        #expect(try String(contentsOf: Self.docs.appendingPathComponent("TERMS.md"), encoding: .utf8) == Terms.markdown)
        #expect(try String(contentsOf: Self.docs.appendingPathComponent("GRAPHICS-GUIDE.md"), encoding: .utf8) == GraphicsGuide.markdown)
        #expect(try String(contentsOf: Self.docs.appendingPathComponent("THIRD-PARTY-NOTICES.md"), encoding: .utf8) == OpenSourceNotices.markdown)
    }

    @Test func sectionsAreNumberedAndUnique() {
        #expect(Set(Terms.sections.map(\.id)).count == Terms.sections.count)
        let steps = GraphicsGuide.steps(displayRefreshRate: nil)
        #expect(Set(steps.map(\.id)).count == steps.count)
        #expect(Terms.markdown.contains("## \(Terms.sections.count). Changes"))
        #expect(GraphicsGuide.markdown.contains("## Step 6: If the game won't start or looks wrong"))
    }

    /// A 60 Hz display is not told about 120 Hz, ProMotion or Battery Saver.
    @Test func guideFollowsTheDisplay() {
        func text(_ rate: Int?) -> String { GraphicsGuide.steps(displayRefreshRate: rate).flatMap(\.paragraphs).joined(separator: " ") }
        for rate in [60, 120, nil] { #expect(!text(rate).contains("ProMotion")) }
        for high in ["120 FPS", "120 Hz", "137 to 172 FPS", "Battery Saver"] { #expect(!text(60).contains(high)) }
        #expect(text(60).contains("up to 60 FPS") && text(60).contains("steady 60 FPS"))
        #expect(text(120).contains("up to 120 FPS") && text(120).contains("Battery Saver"))
        #expect(GraphicsGuide.steps(displayRefreshRate: 60).count == 5 && GraphicsGuide.steps(displayRefreshRate: nil).count == 6)
    }

    @Test func oldSettingsFilesHaveNoAcceptedTerms() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.acceptedTermsVersion == nil)
    }
}

@Suite struct InstallerAndSetupTests {
    @Test func installerLicencePageCallsOutRosettaAndHasEveryTermsSection() {
        let page = InstallerPages.license
        #expect(page.contains("<meta charset=\"utf-8\">"))
        #expect(page.contains(Rosetta.licenceURL.absoluteString))
        for section in Terms.sections { #expect(page.contains(InstallerPages.escape(section.title))) }
        #expect(InstallerPages.inline("a **b** & <c>") == "a <b>b</b> &amp; &lt;c&gt;")
        #expect(InstallerPages.welcome.contains("Rosetta 2") && InstallerPages.conclusion.contains("Install Everything"))
    }

    @Test func readsTheTermsVersionTheInstallerRecorded() {
        let dir = TempDir()
        let record = dir.write("AcceptedTerms", Data("1\n".utf8))
        #expect(Terms.acceptedByInstaller(record: record) == 1)
        #expect(Terms.acceptedByInstaller(record: dir.url.appendingPathComponent("missing")) == nil)
        #expect(Terms.acceptedByInstaller(record: dir.write("Bad", Data("yes".utf8))) == nil)
    }

    @Test func componentDownloadsAreMissingUntilVerifiedCopiesExist() throws {
        let dir = TempDir()
        let runtime = makeFakeRuntime(in: dir)
        let downloads = dir.url.appendingPathComponent("Downloads")
        // The fake runtime has no appwiz.cpl, so it names no Wine Mono version and only Visual C++ is counted.
        #expect(ComponentDownloads.missing(for: runtime, in: downloads) == [.visualCpp])
        let vc = ComponentDownloads.folder(for: .visualCpp, in: downloads)
        for arch in VisualCppRuntime.Architecture.allCases {
            let file = dir.write("Downloads/vcredist/\(arch.fileName)", PEFixture.make())
            try #require(RuntimeInstaller.sha256(of: file)).write(to: file.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        }
        #expect(vc.lastPathComponent == "vcredist")
        #expect(ComponentDownloads.missing(for: runtime, in: downloads).isEmpty)
        // A changed file no longer counts.
        dir.write("Downloads/vcredist/VC_redist.x86.exe", Data("tampered".utf8))
        #expect(ComponentDownloads.missing(for: runtime, in: downloads) == [.visualCpp])
    }

    @Test func setupWithoutADownloadAddressOrEngineSaysWhatToDo() async {
        let dir = TempDir()
        let runtimes = dir.url.appendingPathComponent("Runtimes")
        let runner = SetupRunner(backend: WineBackend(applicationDirectories: [], installRoots: [], managedRuntimesDirectory: runtimes),
                                 runtimesDirectory: runtimes, downloads: dir.url.appendingPathComponent("Downloads"),
                                 componentsURL: nil, installRosetta: false)
        let log = StateLog()
        await runner.run { await log.add($0, $1) }
        let final = await log.final
        if SystemCheck.isAppleSilicon {
            guard case .done(let mac) = final[.mac] else { Issue.record("mac: \(String(describing: final[.mac]))"); return }
            #expect(mac.contains("Apple silicon"))
            guard case .failed(let engine) = final[.engine] else { Issue.record("engine: \(String(describing: final[.engine]))"); return }
            #expect(engine.contains("Install from Package File"))
            #expect(final[.components] == .skipped("Needs the game engine."))
            // Without consent Rosetta is never installed, only reported.
            if !Rosetta.isInstalled() { #expect(final[.rosetta] == .failed("Not installed. The game engine needs it.")) }
        } else {
            #expect(final[.engine] == .skipped("Needs a supported Mac."))
        }
        #expect(runner.currentStates()[.engine] == .waiting)
    }
}

actor StateLog {
    var final: [SetupRunner.Step: SetupRunner.State] = [:]
    func add(_ step: SetupRunner.Step, _ state: SetupRunner.State) { final[step] = state }
}
