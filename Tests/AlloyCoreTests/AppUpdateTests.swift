import Foundation
import Testing
@testable import AlloyCore

@Suite struct AppUpdateTests {
    @Test func comparesVersionsByNumber() {
        #expect(AppUpdate.isNewer("0.9.2", than: "0.9.1"))
        #expect(AppUpdate.isNewer("0.10.0", than: "0.9.9"))
        #expect(AppUpdate.isNewer("1.0", than: "0.9.9"))
        #expect(!AppUpdate.isNewer("0.9.1", than: "0.9.1"))
        #expect(!AppUpdate.isNewer("0.9", than: "0.9.0"))
        #expect(AppUpdate.isNewer("0.9.0", than: "development"))
    }

    @Test func trustsOnlyFlakeOverHTTPSAndThisMac() {
        #expect(AppUpdate.isTrusted(URL(string: "https://flake.co.in/downloads/Alloy-1.zip")!))
        #expect(AppUpdate.isTrusted(URL(string: "http://127.0.0.1:4173/alloy/latest.json")!))
        #expect(!AppUpdate.isTrusted(URL(string: "http://flake.co.in/alloy/latest.json")!))
        #expect(!AppUpdate.isTrusted(URL(string: "https://flake.co.in.example.com/a.zip")!))
        #expect(!AppUpdate.isTrusted(URL(string: "file:///tmp/Alloy.zip")!))
        #expect(AppUpdate.feedURL(environment: ["ALLOY_UPDATE_FEED": "https://evil.example/latest.json"]) == AppUpdate.feed)
        #expect(AppUpdate.feedURL(environment: ["ALLOY_UPDATE_FEED": "http://localhost:4173/alloy/latest.json"]).host == "localhost")
    }

    @Test func readsTheFeedTheWebsitePublishes() throws {
        let json = #"{"version":"0.9.2","build":60,"url":"https://flake.co.in/downloads/Alloy-0.9.2.zip","sha256":"ab","size":1400000,"notes":["Check for Updates"],"minimumSystemVersion":"14.0"}"#
        let release = try AppUpdate.decode(Data(json.utf8))
        #expect(release.version == "0.9.2" && release.notes == ["Check for Updates"])
        let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)
        #expect(AppUpdate.result(for: release, currentVersion: "0.9.1", systemVersion: sonoma) == .available(release))
        #expect(AppUpdate.result(for: release, currentVersion: "0.9.2", systemVersion: sonoma) == .upToDate(latest: "0.9.2"))
        let ventura = OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)
        #expect(AppUpdate.result(for: release, currentVersion: "0.9.1", systemVersion: ventura) == .needsNewerMacOS(release))
        #expect(throws: AlloyError.self) { try AppUpdate.decode(Data("<html>".utf8)) }
    }

    /// A zip laid out like the website's download: Alloy.app at the top.
    func zip(id: String, version: String, in dir: TempDir) throws -> URL {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(id)</string>
        <key>CFBundleShortVersionString</key><string>\(version)</string></dict></plist>
        """
        _ = dir.write("src-\(version)-\(id)/Alloy.app/Contents/Info.plist", Data(plist.utf8))
        _ = dir.write("src-\(version)-\(id)/Alloy.app/Contents/MacOS/Alloy", Data("#!/bin/sh\n".utf8), executable: true)
        let zip = dir.url.appendingPathComponent("Alloy-\(version)-\(id).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent",
                           dir.url.appendingPathComponent("src-\(version)-\(id)/Alloy.app").path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        return zip
    }

    func release(_ zip: URL, version: String, sha: String? = nil) -> AppRelease {
        AppRelease(version: version, url: URL(string: "https://flake.co.in/downloads/x.zip")!,
                   sha256: sha ?? RuntimeInstaller.sha256(of: zip)!)
    }

    @Test func acceptsAVerifiedNewerAlloy() throws {
        let dir = TempDir()
        let file = try zip(id: "in.co.flake.Alloy", version: "0.9.2", in: dir)
        let app = try AppUpdate.prepare(zip: file, release: release(file, version: "0.9.2"), currentVersion: "0.9.1")
        #expect(app.lastPathComponent == "Alloy.app")
        #expect(FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Alloy").path))
    }

    @Test func refusesAnythingElse() throws {
        let dir = TempDir()
        let good = try zip(id: "in.co.flake.Alloy", version: "0.9.2", in: dir)
        #expect(throws: AlloyError.self) {
            try AppUpdate.prepare(zip: good, release: release(good, version: "0.9.2", sha: String(repeating: "0", count: 64)), currentVersion: "0.9.1")
        }
        #expect(throws: AlloyError.self) {
            try AppUpdate.prepare(zip: good, release: release(good, version: "0.9.2"), currentVersion: "0.9.2")
        }
        #expect(throws: AlloyError.self) {
            try AppUpdate.prepare(zip: good, release: release(good, version: "0.9.3"), currentVersion: "0.9.1")
        }
        let other = try zip(id: "com.example.Other", version: "0.9.2", in: dir)
        #expect(throws: AlloyError.self) {
            try AppUpdate.prepare(zip: other, release: release(other, version: "0.9.2"), currentVersion: "0.9.1")
        }
    }
}

struct AlloyHTTPTests {
    /// Requests say only that they come from Alloy: no macOS, CFNetwork or language details.
    @Test func requestsCarryOnlyGenericHeaders() {
        let headers = AlloyHTTP.session.configuration.httpAdditionalHeaders as? [String: String]
        #expect(headers?["User-Agent"] == "Alloy")
        #expect(headers?["Accept-Language"] == "en")
        #expect(AlloyHTTP.configuration().httpShouldSetCookies == false)
    }
}
