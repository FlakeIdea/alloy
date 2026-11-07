import Foundation

/// Steam's first-run installers ("Installing Microsoft .NET Framework…", Visual C++, DirectX) for the games in an
/// environment.
///
/// Before a game's first start Steam runs each entry of the game's `installscript.vdf` files ("Run Process") once and
/// then records it under `HKLM\Software\Valve\Steam\Apps\CommonRedist\…` (Steam is 32-bit, so in Wow6432Node), with a
/// value named after the entry. An entry already recorded is skipped. Under Wine Microsoft's .NET Framework installer
/// waits forever, which leaves Steam stuck on "Installing…" for every game after it. Wine Mono stands in for .NET (and
/// XNA), and Wine has its own DirectX, so Alloy records those entries as done; Visual C++ is recorded once Alloy has
/// installed Microsoft's runtime itself. Steam then starts the game straight away.
public enum SteamRedist {
    public enum Kind: String, Sendable { case dotNet, xna, visualCpp, directX }

    public struct Entry: Hashable, Sendable {
        /// Registry key under HKEY_LOCAL_MACHINE, as in the script ("Software\Valve\Steam\Apps\CommonRedist\.NET\4.8").
        public let key: String
        /// Value name: the entry's name in the script ("4.8", "x64 14.51.36247.0").
        public let name: String
        public let minimum: Int
        public let kind: Kind
    }

    /// Install scripts of the games in the environment's Steam folder.
    public static func scripts(in prefix: WinePrefix, fileManager: FileManager = .default) -> [URL] {
        guard let steam = StoreInstaller.executable(of: .steam, in: prefix)?.deletingLastPathComponent() else { return [] }
        let common = steam.appendingPathComponent("steamapps/common")
        guard let walker = fileManager.enumerator(at: common, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if url.lastPathComponent.lowercased() == "installscript.vdf" { found.append(url); continue }
            // Games keep them at the top or under _CommonRedist/<name>/<version> (level 5); never deep inside game data.
            if walker.level >= 5 { walker.skipDescendants() }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// The .NET, XNA, Visual C++ and DirectX entries in one script. Other entries (a game's own setup, PhysX) are left
    /// to Steam.
    public static func entries(inScript text: String) -> [Entry] {
        guard let root = KeyValuesText.parse(text) else { return [] }
        var out: [Entry] = []
        for (top, value) in root {
            guard top.lowercased() == "installscript", case .object(let script) = value else { continue }
            for (section, body) in script where section.lowercased() == "run process" {
                guard case .object(let processes) = body else { continue }
                for (name, entry) in processes {
                    guard case .object(let fields) = entry else { continue }
                    func field(_ key: String) -> String? {
                        for (k, v) in fields where k.lowercased() == key { if case .string(let s) = v { return s } }
                        return nil
                    }
                    guard let hasRun = field("hasrunkey") else { continue }
                    let process = field("process 1") ?? ""
                    guard let kind = kind(key: hasRun, process: process) else { continue }
                    var key = hasRun
                    for prefix in ["HKEY_LOCAL_MACHINE\\", "HKLM\\"] where key.uppercased().hasPrefix(prefix.uppercased()) {
                        key = String(key.dropFirst(prefix.count))
                    }
                    let minimum = field("minimumhasrunvalue").flatMap { Int($0) } ?? 1
                    let e = Entry(key: key, name: name, minimum: max(1, minimum), kind: kind)
                    if !out.contains(e) { out.append(e) }
                }
            }
        }
        return out
    }

    static func kind(key: String, process: String) -> Kind? {
        let k = key.lowercased(), p = process.lowercased()
        guard k.contains("\\commonredist\\") else { return nil }
        if k.contains("\\vcredist\\") || p.contains("vcredist") || p.contains("visual c++") { return .visualCpp }
        if k.contains("\\.net\\") || k.contains("\\dotnet\\") || p.contains("dotnet") || p.contains(".net framework") { return .dotNet }
        if k.contains("\\xna\\") || p.contains("xna") { return .xna }
        if k.contains("\\directx\\") || p.contains("dxsetup") { return .directX }
        return nil
    }

    /// Entries of every script in the environment that Steam hasn't recorded yet.
    public static func pending(in prefix: WinePrefix) -> [Entry] {
        let recorded = recordedValues(in: prefix)
        var out: [Entry] = []
        for script in scripts(in: prefix) {
            guard let text = (try? String(contentsOf: script, encoding: .utf8))
                    ?? (try? String(contentsOf: script, encoding: .isoLatin1)) else { continue }
            for e in entries(inScript: text) where !out.contains(e) && (recorded[registryID(e)] ?? 0) < e.minimum {
                out.append(e)
            }
        }
        return out
    }

    /// Entries Alloy records as done: DirectX always (Wine's own), .NET and XNA always (Microsoft's installer can't
    /// finish under Wine; Wine Mono stands in, installed by Alloy), Visual C++ once Microsoft's runtime is installed.
    public static func recordable(_ entries: [Entry], visualCppInstalled: Bool) -> [Entry] {
        entries.filter { $0.kind != .visualCpp || visualCppInstalled }
    }

    /// Components Alloy installs for these entries, so the games get what Steam would have installed.
    public static func components(for entries: [Entry]) -> [WindowsComponent] {
        var out: [WindowsComponent] = []
        if entries.contains(where: { $0.kind == .dotNet || $0.kind == .xna }) { out.append(.dotNet) }
        if entries.contains(where: { $0.kind == .visualCpp }) { out.append(.visualCpp) }
        return out
    }

    /// REGEDIT4 file recording the entries as done, in the 32-bit view Steam reads. Imported with `reg import`.
    public static func registryFile(_ entries: [Entry]) -> String {
        var lines = ["REGEDIT4", ""]
        let grouped = Dictionary(grouping: entries, by: { wow64Key($0.key) })
        for key in grouped.keys.sorted() {
            lines.append("[HKEY_LOCAL_MACHINE\\\(key)]")
            for e in grouped[key]! {
                let name = e.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("\"\(name)\"=dword:\(String(format: "%08x", e.minimum))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\r\n")
    }

    /// `Software\Valve\…` as 32-bit Steam sees it from 64-bit Windows.
    static func wow64Key(_ key: String) -> String {
        let lower = key.lowercased()
        if lower.hasPrefix("software\\wow6432node\\") { return key }
        if lower.hasPrefix("software\\") { return "Software\\Wow6432Node\\" + key.dropFirst("software\\".count) }
        return key
    }

    static func registryID(_ e: Entry) -> String { (wow64Key(e.key) + "|" + e.name).lowercased() }

    /// Values Steam has recorded, read from the environment's system.reg (Wine's text registry).
    static func recordedValues(in prefix: WinePrefix) -> [String: Int] {
        guard let text = try? String(contentsOf: prefix.path.appendingPathComponent("system.reg"), encoding: .utf8) else { return [:] }
        var out: [String: Int] = [:]
        var section: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                guard let end = line.lastIndex(of: "]") else { section = nil; continue }
                let name = String(line[line.index(after: line.startIndex)..<end]).replacingOccurrences(of: "\\\\", with: "\\")
                section = name.lowercased().contains("\\valve\\steam\\apps\\commonredist\\") ? name : nil
                continue
            }
            guard let section, line.hasPrefix("\""), let eq = line.range(of: "\"=dword:") else { continue }
            let name = String(line[line.index(after: line.startIndex)..<eq.lowerBound])
                .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            let value = Int(line[eq.upperBound...].prefix(8), radix: 16) ?? 0
            out[(section + "|" + name).lowercased()] = value
        }
        return out
    }
}

/// Valve's text KeyValues ("key" "value" / "key" { … }), enough for install scripts. Keys can repeat, so objects are
/// ordered lists of pairs.
enum KeyValuesText {
    indirect enum Value { case string(String), object([(String, Value)]) }

    static func parse(_ text: String) -> [(String, Value)]? {
        var tokens: [String?] = []   // nil = "{", "" sentinel handled by kind below
        var kinds: [Character] = []  // "s" string, "{" open, "}" close
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "\"" {
                var s = ""; var j = text.index(after: i)
                while j < text.endIndex, text[j] != "\"" {
                    if text[j] == "\\", text.index(after: j) < text.endIndex {
                        let n = text[text.index(after: j)]
                        s.append(n == "n" ? "\n" : n == "t" ? "\t" : n); j = text.index(j, offsetBy: 2); continue
                    }
                    s.append(text[j]); j = text.index(after: j)
                }
                tokens.append(s); kinds.append("s"); i = j < text.endIndex ? text.index(after: j) : j
            } else if c == "{" || c == "}" {
                tokens.append(nil); kinds.append(c); i = text.index(after: i)
            } else if c == "/", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "/" {
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
            } else if c.isWhitespace {
                i = text.index(after: i)
            } else {
                var s = ""
                while i < text.endIndex, !text[i].isWhitespace, text[i] != "{", text[i] != "}", text[i] != "\"" { s.append(text[i]); i = text.index(after: i) }
                tokens.append(s); kinds.append("s")
            }
        }
        var pos = 0
        func object(top: Bool) -> [(String, Value)]? {
            var pairs: [(String, Value)] = []
            while pos < kinds.count {
                if kinds[pos] == "}" { pos += 1; return top ? nil : pairs }
                guard kinds[pos] == "s", let key = tokens[pos] else { return nil }
                pos += 1
                guard pos < kinds.count else { return nil }
                if kinds[pos] == "{" {
                    pos += 1
                    guard let inner = object(top: false) else { return nil }
                    pairs.append((key, .object(inner)))
                } else if kinds[pos] == "s", let v = tokens[pos] {
                    pos += 1; pairs.append((key, .string(v)))
                } else { return nil }
            }
            return top ? pairs : nil
        }
        return object(top: true)
    }
}
