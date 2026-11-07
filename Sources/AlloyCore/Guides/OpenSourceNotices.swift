import Foundation

/// What Alloy is built from and what it installs, with each licence. The app shows it under Help → Open-Source
/// Licences; docs/THIRD-PARTY-NOTICES.md is generated from it (`alloyctl write-docs docs`). The engine package
/// carries the full licence texts in its `licenses/` folder.
public enum OpenSourceNotices {
    public struct Component: Identifiable, Hashable, Sendable {
        public var id: String { name }
        public let name: String
        public let licence: String
        public let use: String
        public let url: String
    }

    public struct Group: Identifiable, Hashable, Sendable {
        public var id: String { title }
        public let title: String
        public let note: String
        public let components: [Component]
    }

    public static let groups: [Group] = [
        Group(title: "Alloy", note: "Free software by Flake. You can use, study, change and share it under the GPL; its source code is on GitHub.", components: [
            Component(name: "Alloy", licence: "GPL-3.0", use: "This app and its command-line tool, alloyctl.", url: "https://github.com/FlakeIdea/alloy"),
        ]),
        Group(title: "The game engine", note: "A separate download, installed from Setup. Its licences/ folder holds every licence text, and its source is published with each release.", components: [
            Component(name: "Wine", licence: "LGPL-2.1 or later", use: "Runs Windows programs. Built from the open-source parts of CrossOver 26.3 that CodeWeavers publishes, with Alloy's patches.", url: "https://www.winehq.org"),
            Component(name: "vkd3d", licence: "LGPL-2.1 or later", use: "Part of Wine: Direct3D 12 shader support.", url: "https://gitlab.winehq.org/wine/vkd3d"),
            Component(name: "DXMT", licence: "MIT", use: "Turns Direct3D 10 and 11 into Metal.", url: "https://github.com/3Shain/dxmt"),
            Component(name: "MoltenVK", licence: "Apache-2.0", use: "Vulkan on Metal.", url: "https://github.com/KhronosGroup/MoltenVK"),
            Component(name: "GStreamer", licence: "LGPL-2.1 or later", use: "Video playback in games. Video is decoded by macOS itself.", url: "https://gstreamer.freedesktop.org"),
            Component(name: "GLib, proxy-libintl", licence: "LGPL-2.1 or later", use: "Used by GStreamer.", url: "https://gitlab.gnome.org/GNOME/glib"),
            Component(name: "libffi", licence: "MIT", use: "Used by GLib.", url: "https://sourceware.org/libffi/"),
            Component(name: "PCRE2", licence: "BSD-3-Clause", use: "Used by GLib.", url: "https://github.com/PCRE2Project/pcre2"),
            Component(name: "GnuTLS", licence: "LGPL-2.1 or later", use: "Secure connections for Windows programs (HTTPS, certificate checks).", url: "https://gnutls.org"),
            Component(name: "Nettle, GMP", licence: "LGPL-3.0 or later, or GPL-2.0 or later", use: "Cryptography used by GnuTLS.", url: "https://www.lysator.liu.se/~nisse/nettle/"),
            Component(name: "FreeType", licence: "FreeType Licence", use: "Font rendering.", url: "https://freetype.org"),
        ]),
        Group(title: "Downloaded when needed", note: "Not part of Alloy. Downloaded from their publishers with your permission, under their own terms.", components: [
            Component(name: "Wine Mono", licence: "MIT, with GPL and LGPL parts", use: ".NET support for games and launchers. From WineHQ.", url: "https://gitlab.winehq.org/mono/wine-mono"),
            Component(name: "Microsoft Visual C++ Redistributable", licence: "Microsoft software licence", use: "Needed by many games. From Microsoft.", url: "https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist"),
            Component(name: "Game store apps", licence: "Each store's own terms", use: "Steam, Epic Games Launcher, EA app, Ubisoft Connect, GOG Galaxy, Battle.net. From their publishers.", url: ""),
            Component(name: "Rosetta 2", licence: "Apple software licence", use: "Runs the Intel-built engine on Apple silicon. Installed by macOS.", url: "https://support.apple.com/102527"),
        ]),
        Group(title: "Never included", note: "Alloy never ships or downloads these.", components: [
            Component(name: "D3DMetal (Apple Game Porting Toolkit)", licence: "Apple licence; not redistributable", use: "Optional, for DirectX 12. You download Apple's toolkit yourself and accept Apple's licence; Alloy only uses the copy you add.", url: "https://developer.apple.com/games/game-porting-toolkit/"),
        ]),
    ]

    public static let intro = "Alloy's own app uses only Apple's system frameworks. It runs the game engine as a separate program and links none of its code."

    public static var markdown: String {
        var out = "<!-- Generated from Sources/AlloyCore/Guides/OpenSourceNotices.swift by `alloyctl write-docs docs`. Edit that file instead. -->\n\n"
        out += "# Third-party notices\n\n\(intro)\n"
        for group in groups {
            out += "\n## \(group.title)\n\n\(group.note)\n\n| Component | Licence | Use |\n|---|---|---|\n"
            for c in group.components {
                let name = c.url.isEmpty ? c.name : "[\(c.name)](\(c.url))"
                out += "| \(name) | \(c.licence) | \(c.use) |\n"
            }
        }
        return out
    }
}
