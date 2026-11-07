import Foundation
import Testing
@testable import AlloyCore

@Suite struct CrashExplanationTests {
    func first(_ log: String) -> DiagnosticFinding? { DiagnosticService.analyze(log: log).first }

    @Test func explainsEachKindOfCrash() throws {
        let null = try #require(first("wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140012345 (thread 0124), starting debugger..."))
        #expect(null.kind == .crash && null.detail.contains("null pointer"))
        #expect(null.fixes == [.forceDX11, .turnOffDLSS, .turnOffMetalFXUpscaling, .compatibilityMode])
        let write = try #require(first("wine: Unhandled page fault on write access to 00000001DEADBEEF at address 0000000140012345"))
        #expect(write.detail.contains("write memory it doesn't own"))
        #expect(first("wine: Unhandled exception 0xc0000409 in thread 124")?.subject == "crash-failfast")
        #expect(first("wine: Unhandled exception 0xe06d7363 in thread 124")?.subject == "crash-cpp")
        #expect(first("wine: Unhandled stack overflow at address 0000000140012345")?.subject == "crash-stack")
    }

    @Test func aSpecificCauseReplacesTheGeneralCrash() throws {
        let findings = DiagnosticService.analyze(log: "wine: Unhandled illegal instruction at address 0000000140012345 (thread 0124)")
        #expect(findings.map(\.kind) == [.illegalInstruction])
        #expect(findings.first?.fixes == [.advertiseAVX])
        let lost = DiagnosticService.analyze(log: """
            LogD3D11RHI: Error: Unreal Engine is exiting due to D3D device being lost. (Error: 0x887A0006 - 'HUNG')
            wine: Unhandled exception 0x80000003 in thread 0124
            """)
        #expect(lost.map(\.kind) == [.graphicsDeviceLost])
        #expect(DiagnosticService.analyze(log: "err:virtual:allocate_virtual_memory out of memory for allocation, base (nil) size 40000000").first?.kind == .outOfMemory)
        #expect(DiagnosticService.analyze(log: "err:virtual:allocate_virtual_memory out of memory for allocation", exitState: .exited(code: 0)).isEmpty)
        #expect(DiagnosticService.analyze(log: "[S_API FAIL] SteamAPI_Init() failed; no appID found.").first?.kind == .storeRequired)
    }

    @Test func missingDLLsGetTheMatchingInstall() throws {
        let vc = try #require(first(#"err:module:import_dll Library MSVCP140.dll (which is needed by L"C:\\Game\\game.exe") not found"#))
        #expect(vc.fixes == [.installVisualCpp])
        let net = try #require(first(#"err:module:import_dll Library mscoree.dll (which is needed by L"C:\\Game\\tool.exe") not found"#))
        #expect(net.fixes == [.installDotNet])
        let other = try #require(first(#"err:module:import_dll Library foo.dll (which is needed by L"C:\\Game\\game.exe") not found"#))
        #expect(other.fixes == [.addDLL] && other.suggestion.contains("_CommonRedist"))
    }

    @Test func fixesApplyOnlyWhereTheyChangeSomething() {
        let dir = TempDir()
        var game = makeGame(in: dir)
        game.graphics.backend = .dxmt
        let unreal = GameTraits(usage: [.d3d11, .d3d12], machine: .x64, isUnreal: true)
        func applies(_ fix: DiagnosticFix, traits: GameTraits? = nil, caps: BackendCapabilities? = nil) -> Bool {
            fix.applies(to: game, capabilities: caps, traits: traits, visualCppInstalled: true, dotNetInstalled: false, hasD3DMetal: true)
        }
        #expect(applies(.forceDX11, traits: unreal) && !applies(.forceDX11))
        #expect(!applies(.turnOffDLSS) && !applies(.installVisualCpp) && applies(.installDotNet) && !applies(.addD3DMetal))
        #expect(applies(.compatibilityMode) && applies(.syncOff))
        var changed = game
        #expect(DiagnosticFix.compatibilityMode.apply(to: &changed) && changed.graphics.backend == .wined3dOpenGL)
        #expect(!DiagnosticFix.installVisualCpp.apply(to: &changed))
        game = changed
        #expect(!applies(.compatibilityMode))
        #expect(DiagnosticFix.forceDX11.apply(to: &changed) && changed.graphics.forceDX11)
    }

    @Test func unrecognisedExitsOfferCompatibilityMode() {
        let findings = DiagnosticService.analyze(log: "nothing useful", exitState: .exited(code: 3))
        #expect(findings.first?.kind == .nonZeroExit && findings.first?.fixes == [.compatibilityMode])
    }
}

@Suite struct CrashDialogTests {
    @Test func readsAndTurnsOffWinesCrashWindow() throws {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        let reg = prefix.path.appendingPathComponent("user.reg")
        try Data("WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\WineDbg] 1793817892\n#time=1dd6c8c93f0fa26\n\"ShowCrashDialog\"=dword:00000001\n".utf8).write(to: reg)
        #expect(!CrashDialog.isOff(in: prefix))
        try Data("WINE REGISTRY Version 2\n\n[Software\\\\Other] 1\n\"ShowCrashDialog\"=dword:00000000\n\n[Software\\\\Wine\\\\WineDbg] 1793817892\n#time=1dd6c8c93f0fa26\n\"ShowCrashDialog\"=dword:00000000\n".utf8).write(to: reg)
        #expect(CrashDialog.isOff(in: prefix))
        let cmd = CrashDialog.turnOffCommand(like: LaunchCommand(executable: URL(fileURLWithPath: "/w/bin/wine"), arguments: ["game.exe"],
                                                                 environment: ["WINEPREFIX": prefix.path.path]))
        #expect(cmd.arguments == ["reg", "add", #"HKCU\Software\Wine\WineDbg"#, "/v", "ShowCrashDialog", "/t", "REG_DWORD", "/d", "0", "/f"])
        #expect(cmd.environment["WINEPREFIX"] == prefix.path.path)
    }
}
