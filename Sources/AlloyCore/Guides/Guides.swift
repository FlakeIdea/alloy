import Foundation

/// A titled block of text shown in the app and published on the website. Paragraphs may use inline Markdown.
public struct GuideSection: Sendable, Hashable, Identifiable {
    public let symbol: String
    public let title: String
    public let paragraphs: [String]
    public var id: String { title }

    init(_ symbol: String, _ title: String, _ paragraphs: [String]) {
        self.symbol = symbol
        self.title = title
        self.paragraphs = paragraphs
    }
}

/// The terms people accept on first launch. docs/TERMS.md is generated from this (`alloyctl write-docs docs`),
/// so the website and the app say the same thing. Raise `version` when the meaning changes: people are asked again.
public enum Terms {
    public static let version = 4
    public static let updated = "7 November 2026"
    public static let title = "Alloy Terms of Use"
    public static let intro = "Alloy is free, open-source software made by Flake. These terms explain what it does, what it doesn't, and what you agree to by using it. They are written to be read."

    public static let sections: [GuideSection] = [
        GuideSection("app.badge", "What Alloy is", [
            "Alloy lets Windows games and programs run on Macs using Wine, DXMT and other open-source components. It does not contain, sell or provide any games.",
            "Alloy is an independent project. It is not made by, endorsed by or affiliated with CodeWeavers, Apple, Microsoft, Valve, Epic Games, Electronic Arts, Ubisoft, GOG, Blizzard, NVIDIA or any game publisher. Their names and trademarks belong to them and are used only to describe compatibility.",
        ]),
        GuideSection("doc.text", "Licences", [
            "Alloy's source code is published at github.com/FlakeIdea/alloy under the GNU General Public License, version 3 (GPL-3.0). The game engine and the components Alloy downloads come under their own open-source licences, which are included with them and listed under Open-Source Licences in the Help menu. The game engine's complete source code is published with each engine release at github.com/FlakeIdea/alloy-engine.",
            "Nothing in these terms limits the rights those open-source licences give you.",
        ]),
        GuideSection("gamecontroller", "Your games", [
            "Use Alloy only with games and software you have the right to use. Alloy does not remove copy protection or DRM and must not be used to run pirated software.",
            "Each game's own licence and terms still apply when it runs in Alloy.",
        ]),
        GuideSection("bag", "Game stores and accounts", [
            "Store apps such as Steam and the Epic Games Launcher run in Alloy like any Windows program. You sign in inside the store's own window: Alloy never sees, stores or sends your store password.",
            "Each store's own terms apply to your account and the games you get there.",
        ]),
        GuideSection("hand.thumbsup", "Acceptable use", [
            "Don't use Alloy to infringe copyright, get around copy protection, cheat in online games, or get around a network's rules or filters.",
        ]),
        GuideSection("network", "Online games and anti-cheat", [
            "Some online games use anti-cheat software that does not work in Wine or may react to it. Playing online games through Alloy is at your own risk. The Alloy authors are not responsible for account suspensions or bans.",
            "Networks at schools and workplaces often block game stores and online games. Alloy tells you when it finds this and never tries to get around a network's filter.",
        ]),
        GuideSection("arrow.down.circle", "Downloads from other publishers", [
            "With your permission, Alloy downloads software from its publishers: the game engine from the Alloy release site, the Visual C++ runtime from Microsoft, Wine Mono from WineHQ, Rosetta 2 from Apple, and game store apps from their publishers (Steam from Valve, the Epic Games Launcher from Epic Games, the EA app from EA, Ubisoft Connect from Ubisoft, GOG Galaxy from GOG and Battle.net from Blizzard). Each comes under its publisher's own terms, which you accept when you install it.",
            "The game engine, the Visual C++ runtime and Wine Mono are checked against a published checksum before they are installed. Store apps change too often for that, so they are downloaded over HTTPS straight from their publishers' own servers, and a download that ends up anywhere else is refused. Each publisher is responsible for its own software.",
        ]),
        GuideSection("hand.raised", "Privacy", [
            "Alloy does not collect analytics, usage data or personal information, and has no account.",
            "Logs and diagnostic reports stay on your Mac. Reports remove your home folder path and anything that looks like a password or token, and are shared only if you choose to send one yourself.",
            "Alloy connects to the internet only for the downloads above, to check the list of available game engines, to check whether game stores can be reached (it asks each store's sign-in server and Apple's connectivity page for an answer), and once a day, unless you turn it off in Settings, to check flake.co.in for a newer Alloy. These requests send nothing about you. Those servers see your IP address, as any website does.",
            "Games you run may connect to the internet and your local network themselves, as they do on Windows. macOS asks you before a game first looks for devices on your local network.",
        ]),
        GuideSection("lock.shield", "Running Windows programs", [
            "Windows programs run with your normal user permissions inside their own environment. Alloy asks before running a program for the first time and never runs one with administrator rights. Only run software you trust.",
        ]),
        GuideSection("exclamationmark.triangle", "No warranty", [
            "Alloy is provided “as is”, without warranty of any kind. Not every game works, performance varies between games and Macs, and games can crash or lose unsaved progress. Keep backups of save games you care about.",
        ]),
        GuideSection("scalemass", "Limitation of liability", [
            "To the extent the law allows, the authors and contributors of Alloy are not liable for any damage or loss from using it, including lost data, lost game progress or actions taken against game accounts.",
            "Nothing in these terms removes rights you have under consumer protection law where you live.",
        ]),
        GuideSection("envelope", "Contact", [
            "Questions about these terms, licences, the source code or a trademark concern: email support@flake.co.in, or open an issue at github.com/FlakeIdea/alloy.",
        ]),
        GuideSection("arrow.triangle.2.circlepath", "Changes", [
            "These terms may change in a later version of Alloy. If they change in a way that matters, Alloy shows them again and asks you to accept them before you continue.",
        ]),
    ]

    public static var markdown: String {
        render(title: title, subtitle: "Version \(version), last updated \(updated)", intro: intro,
               sections: sections, heading: { i, s in "\(i + 1). \(s.title)" })
    }

    /// Written by the installer's postinstall script after the person agreed on its licence page, so the app does not
    /// ask again. Holds the accepted version number.
    public static let installerRecord = URL(fileURLWithPath: "/Library/Application Support/Alloy/AcceptedTerms")

    /// The terms version the installer recorded, if any.
    public static func acceptedByInstaller(record: URL = installerRecord) -> Int? {
        (try? String(contentsOf: record, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

/// The pages of the downloadable installer (`scripts/make-installer.sh`), written by `alloyctl installer-pages`.
public enum InstallerPages {
    public static var welcome: String {
        html(title: "Welcome to Alloy", body: """
        <h1>Welcome to Alloy</h1>
        <p>Alloy plays Windows games on your Mac.</p>
        <p>This installer:</p>
        <ol>
        <li>checks that your Mac has macOS 14 or later (Apple silicon, or Intel with Compatibility graphics);</li>
        <li>puts Alloy in your Applications folder;</li>
        <li>installs Rosetta 2 from Apple if your Mac doesn't have it yet. The game engine needs it.</li>
        </ol>
        <p>Then Alloy opens. One click there downloads the game engine and the Windows components games need
        (Visual C++ from Microsoft, .NET support from WineHQ). Keep about \(SystemCheck.gigabytes(SystemCheck.requiredFreeBytes)) free for them.</p>
        <p>Alloy is free and open source. It is not affiliated with CodeWeavers, Apple, Microsoft, Valve, Epic Games or any other game store or publisher.</p>
        """)
    }

    /// The terms, with Apple's Rosetta licence called out first because agreeing here also installs Rosetta.
    public static var license: String {
        var body = "<h1>\(escape(Terms.title))</h1>\n<p><i>Version \(Terms.version), last updated \(Terms.updated)</i></p>\n"
        body += "<p class=\"note\"><b>Rosetta 2:</b> if your Mac doesn't have Rosetta 2, this installer installs it from Apple. "
            + "Rosetta 2 is Apple software. By agreeing, you also accept Apple's licence for it: "
            + "<a href=\"\(Rosetta.licenceURL.absoluteString)\">\(Rosetta.licenceURL.absoluteString)</a>.</p>\n"
        body += "<p>\(inline(Terms.intro))</p>\n"
        for (i, section) in Terms.sections.enumerated() {
            body += "<h2>\(i + 1). \(escape(section.title))</h2>\n" + section.paragraphs.map { "<p>\(inline($0))</p>\n" }.joined()
        }
        return html(title: Terms.title, body: body)
    }

    public static var conclusion: String {
        html(title: "Alloy is installed", body: """
        <h1>Alloy is installed</h1>
        <p>Alloy opens now. Click <b>Install Everything</b> to download the game engine and the Windows
        components, then add your first game.</p>
        <p>If something could not be installed, for example Rosetta 2 without an internet connection, Alloy's
        <b>Setup</b> page offers it again.</p>
        <p>For the best performance, open <b>Which should I choose?</b> on any game's page.</p>
        """)
    }

    static func html(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        body { font: 13px -apple-system, sans-serif; line-height: 1.45; color: #1d1d1f; }
        h1 { font-size: 18px; } h2 { font-size: 14px; margin-top: 1.2em; }
        .note { background: rgba(128, 128, 128, 0.14); border-left: 3px solid #8e8e93; padding: 6px 10px; }
        @media (prefers-color-scheme: dark) { body { color: #f5f5f7; } a { color: #e5e5ea; } }
        </style></head>
        <body>
        \(body)
        </body></html>

        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escapes the text and turns Markdown `**bold**` into <b>.
    static func inline(_ text: String) -> String {
        escape(text).components(separatedBy: "**").enumerated().map { i, part in i % 2 == 1 ? "<b>\(part)</b>" : part }.joined()
    }
}

/// The graphics tutorial: what to choose in Alloy and in the game itself. In the app it follows the Mac's display,
/// so a 60 Hz display is never told about 120 Hz or Battery Saver; docs/GRAPHICS-GUIDE.md is generated for any display.
/// Numbers come from Alloy's own measurements (docs/COMPATIBILITY.md); the rest is general advice.
public enum GraphicsGuide {
    public static let title = "Graphics Guide"
    public static let intro = "Most games run well with Alloy's defaults. If a game feels slow or looks wrong, go through these steps in order and stop when it plays the way you like."

    /// The steps for a display with this refresh rate, or for any display when nil (the published copy).
    public static func steps(displayRefreshRate rate: Int?) -> [GuideSection] {
        let upTo = rate.map { "up to \($0) FPS on your display" } ?? "up to its refresh rate"
        // Frame rates a 60 Hz display cannot show are no help there, so it hears what the gain buys it instead.
        let sixtyHertz = rate.map { $0 <= 60 } ?? false
        let speed = sixtyHertz
            ? "In Alloy's GPU test, a lower resolution scaled up with MetalFX ran about 50% faster than full resolution: room for a heavy game to hold a steady 60 FPS."
            : "In Alloy's GPU test, rendering at 1200 × 778 and scaling up with MetalFX ran at 137 to 172 FPS, against 91 FPS at full resolution."
        var steps = [
            GuideSection("gauge.with.dots.needle.50percent", "Start with Balanced", [
                "Every game starts in **Balanced**: it runs as smoothly as your display allows, \(upTo), and Alloy paces the frames evenly. Play for a few minutes first. Most games need nothing else.",
                "The first minutes of a new game can stutter while it prepares its shaders. That gets better as you play and is faster on the next start.",
            ]),
            GuideSection("powerplug", "Plug in and play in fullscreen", [
                "Plug your Mac in and turn off Low Power Mode: on battery, macOS can slow the graphics down.",
                "Play in fullscreen. macOS then turns on Game Mode, which gives the game priority over other apps.",
            ]),
            GuideSection("slider.horizontal.3", "Lower the heavy settings in the game", [
                "Open the game's own graphics settings. Shadows, volumetric fog and clouds, ambient occlusion, motion blur and ray tracing cost the most. Lower these first; textures can usually stay high on Macs with 16 GB of memory or more.",
                "If the game has its own frame-rate limit, set it to Unlimited or to your display's rate. Alloy already limits the game to what your display can show.",
            ]),
            GuideSection("eye", "Still slow? Lower the resolution and choose Sharp", [
                "The biggest gain comes from a lower resolution. In the game, choose about half your screen's resolution (for example 1512 × 982 on a 14-inch MacBook Pro), then choose **Sharp** in Alloy. Apple's MetalFX scales the picture back up to your full Retina resolution, so it stays crisp instead of blurry.",
                speed + " Sharp on its own, at full resolution, costs about 2 milliseconds per frame, so use it together with a lower resolution.",
                "If the game offers DLSS, you can try that instead: Alloy passes it to Apple's MetalFX. Don't use DLSS and Sharp together.",
            ]),
            GuideSection("wrench.and.screwdriver", "If the game won't start or looks wrong", [
                "First check the game page: Alloy lists problems it found, often with a one-click fix such as installing a missing Windows component.",
                "For a black screen, missing textures or a crash at start, turn on **Compatibility mode**. It switches to a slower, older renderer that some games need. Turn it off again if it doesn't help.",
            ]),
        ]
        // Battery Saver's 60 FPS limit only saves power on a display faster than 60 Hz.
        if !sixtyHertz {
            var text = ["**Battery Saver** limits the game to 60 FPS. The Mac stays cooler and quieter and the battery lasts longer. Most single-player games still feel smooth at 60."]
            if rate == nil { text.append("It appears on Macs whose display runs faster than 60 Hz. On a 60 Hz display, Balanced already runs at 60.") }
            steps.insert(GuideSection("battery.75percent", "On battery, choose Battery Saver", text), at: steps.count - 1)
        }
        return steps
    }

    public static var markdown: String {
        render(title: title, subtitle: nil, intro: intro, sections: steps(displayRefreshRate: nil),
               heading: { i, s in "Step \(i + 1): \(s.title)" })
    }
}

private func render(title: String, subtitle: String?, intro: String, sections: [GuideSection],
                    heading: (Int, GuideSection) -> String) -> String {
    var out = "<!-- Generated from Sources/AlloyCore/Guides/Guides.swift by `alloyctl write-docs docs`. Edit that file instead. -->\n\n"
    out += "# \(title)\n\n"
    if let subtitle { out += "_\(subtitle)_\n\n" }
    out += intro + "\n"
    for (i, section) in sections.enumerated() {
        out += "\n## \(heading(i, section))\n\n" + section.paragraphs.joined(separator: "\n\n") + "\n"
    }
    return out
}
