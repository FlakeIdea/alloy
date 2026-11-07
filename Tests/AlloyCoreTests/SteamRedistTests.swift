import Foundation
import Testing
@testable import AlloyCore

@Suite struct SteamRedistTests {
    // Shapes of Steam's own scripts (Steamworks Shared/_CommonRedist), signatures left out.
    static let dotNet = #"""
    "InstallScript"
    {
    	"Run Process"
    	{
    		"4.8"
    		{
    			"HasRunKey"		"HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\CommonRedist\\.NET\\4.8"
    			"process 1"		"%INSTALLDIR%\\_CommonRedist\\DotNet\\4.8\\Microsoft .NET Framework 4.8.cmd"
    			"NoCleanUp"		"1"
    		}
    	}
    }
    "kvsignatures" { "InstallScript" "93" }
    """#
    static let vcredist = #"""
    "installscript"
    {
    	"Run Process"
    	{
    		"x86 14.51.36247.0"
    		{
    			"hasrunkey"		"HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\CommonRedist\\vcredist\\2022"
    			"process 1"		"%INSTALLDIR%\\_CommonRedist\\vcredist\\2022\\Microsoft Visual C++ 2022 x86.cmd"
    		}
    		"x64 14.51.36247.0"
    		{
    			"hasrunkey"		"HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\CommonRedist\\vcredist\\2022"
    			"process 1"		"%INSTALLDIR%\\_CommonRedist\\vcredist\\2022\\Microsoft Visual C++ 2022 x64.cmd"
    			"Requirement_OS" { "Is64BitWindows" "1" }
    		}
    	}
    }
    """#
    static let directX = #"""
    "installscript"
    {
    	"Run Process"
    	{
    		"dxsetup"
    		{
    			"hasrunkey"		"HKEY_LOCAL_MACHINE\\Software\\Valve\\Steam\\Apps\\CommonRedist\\DirectX\\Jun2010"
    			"process 1"		"%INSTALLDIR%\\_CommonRedist\\DirectX\\Jun2010\\DXSETUP.exe"
    			"command 1"		"/silent"
    		}
    		"Game Setup"
    		{
    			"process 1"		"%INSTALLDIR%\\setup.exe"
    		}
    	}
    }
    """#

    @Test func readsSteamsRedistributablesFromItsInstallScripts() {
        let net = SteamRedist.entries(inScript: Self.dotNet)
        #expect(net == [.init(key: #"Software\Valve\Steam\Apps\CommonRedist\.NET\4.8"#, name: "4.8", minimum: 1, kind: .dotNet)])
        let vc = SteamRedist.entries(inScript: Self.vcredist)
        #expect(vc.map(\.name) == ["x86 14.51.36247.0", "x64 14.51.36247.0"] && vc.allSatisfy { $0.kind == .visualCpp })
        // A game's own setup has no HasRunKey under CommonRedist and stays Steam's business.
        #expect(SteamRedist.entries(inScript: Self.directX).map(\.kind) == [.directX])
    }

    @Test func recordsDotNetAndDirectXAndVisualCppOnlyOnceInstalled() {
        let all = SteamRedist.entries(inScript: Self.dotNet) + SteamRedist.entries(inScript: Self.vcredist)
            + SteamRedist.entries(inScript: Self.directX)
        #expect(SteamRedist.recordable(all, visualCppInstalled: false).map(\.kind) == [.dotNet, .directX])
        #expect(SteamRedist.recordable(all, visualCppInstalled: true).count == 4)
        #expect(SteamRedist.components(for: all) == [.dotNet, .visualCpp])
        let file = SteamRedist.registryFile(SteamRedist.recordable(all, visualCppInstalled: true))
        #expect(file.contains(#"[HKEY_LOCAL_MACHINE\Software\Wow6432Node\Valve\Steam\Apps\CommonRedist\.NET\4.8]"# + "\r\n\"4.8\"=dword:00000001"))
        #expect(file.contains("\"x64 14.51.36247.0\"=dword:00000001"))
    }

    @Test func skipsWhatSteamAlreadyRecordedInTheEnvironment() {
        let dir = TempDir()
        let prefix = makeInitializedPrefix(in: dir)
        dir.write("prefix/drive_c/Program Files (x86)/Steam/steam.exe", Data())
        let shared = "prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Steamworks Shared/_CommonRedist"
        dir.write("\(shared)/DotNet/4.8/installscript.vdf", Data(Self.dotNet.utf8))
        dir.write("\(shared)/vcredist/2022/installscript.vdf", Data(Self.vcredist.utf8))
        #expect(SteamRedist.pending(in: prefix).count == 3)
        // As Wine writes it after Steam (or Alloy) recorded .NET and one Visual C++ entry.
        dir.write("prefix/system.reg", Data(#"""
        WINE REGISTRY Version 2

        [Software\\Wow6432Node\\Valve\\Steam\\Apps\\CommonRedist\\.NET\\4.8] 1794060185
        #time=1dd6ec0b5ca8942
        "4.8"=dword:00000001

        [Software\\Wow6432Node\\Valve\\Steam\\Apps\\CommonRedist\\vcredist\\2022] 1793969771
        "x64 14.51.36247.0"=dword:00000001

        """#.utf8))
        #expect(SteamRedist.pending(in: prefix).map(\.name) == ["x86 14.51.36247.0"])
    }
}
