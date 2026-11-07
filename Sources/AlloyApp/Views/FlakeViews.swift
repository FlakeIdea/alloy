import AppKit
import SwiftUI

/// Flake, the studio that makes Alloy: its addresses and the version shown to people.
enum Flake {
    static let website = URL(string: "https://flake.co.in")!
    static let alloyPage = URL(string: "https://flake.co.in/alloy/")!
    static let guide = URL(string: "https://flake.co.in/alloy/guide/")!
    static let sourceCode = URL(string: "https://github.com/FlakeIdea/alloy")!
    static let supportEmail = "support@flake.co.in"
    static let helloEmail = "hello@flake.co.in"
    static var hello: URL { URL(string: "mailto:\(helloEmail)")! }

    /// "0.9.1", from the bundle. Builds run from the Swift package have no bundle version.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    /// The version as people see it: "1.0 Beta". Update checks use `version`, the number alone.
    static var displayVersion: String {
        let stage = (Bundle.main.object(forInfoDictionaryKey: "AlloyVersionStage") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        return stage.isEmpty ? version : "\(version) \(stage)"
    }

    /// A new email to support. Bug reports carry the Alloy and macOS versions, nothing else.
    static func email(subject: String, body: String = "") -> URL {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = supportEmail
        parts.queryItems = [URLQueryItem(name: "subject", value: subject)] + (body.isEmpty ? [] : [URLQueryItem(name: "body", value: body)])
        return parts.url ?? URL(string: "mailto:\(supportEmail)")!
    }

    static var bugReport: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return email(subject: "Alloy bug report",
                     body: "What happened:\n\n\nWhat you expected:\n\n\nAlloy \(displayVersion), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\n")
    }
}

/// The Flake mark (three feathers and a beak), drawn from the same outlines as the website's logo.
struct FlakeMark: Shape {
    /// One piece (0–2 the feathers, 3 the beak), placed where it sits in the whole mark; nil draws all of it.
    var part: Int? = nil
    private static let size = CGSize(width: 222.26, height: 304.39)
    static let paths = [
        "M46.1,237.9C53.2,236.7 57.7,234.3 62.6,229.4C65.7,226.3 67.4,223.9 69.2,220.1C72.2,214.0 72.8,209.2 72.0,200.4C71.8,198.3 71.5,195.8 71.3,195.0C71.0,194.2 70.9,193.3 70.9,192.9C70.9,192.1 69.5,186.6 68.3,183.0C67.3,179.6 65.4,173.9 64.7,172.3C64.4,171.3 64.0,170.1 63.8,169.5C63.7,169.0 63.5,168.4 63.4,168.3C63.3,168.1 63.1,167.6 62.9,167.1C62.8,166.7 62.4,165.5 62.0,164.6C61.7,163.7 61.1,162.1 60.7,161.2C60.4,160.3 60.0,159.2 59.9,158.7C59.7,158.3 59.4,157.6 59.2,157.2C59.0,156.8 58.9,156.3 58.9,156.1C58.9,155.9 58.6,155.3 58.4,154.8C58.1,154.2 57.9,153.6 57.9,153.4C57.9,153.2 57.6,152.6 57.4,152.0C57.1,151.5 56.9,150.8 56.9,150.6C56.9,150.4 56.6,149.8 56.4,149.3C56.1,148.7 55.9,148.1 55.9,147.9C55.9,147.7 55.7,147.2 55.5,146.8C55.3,146.4 55.0,145.6 54.9,145.2C54.6,143.9 53.7,141.4 53.4,140.8C53.2,140.6 53.0,140.0 52.9,139.5C52.8,138.9 52.3,137.4 51.8,136.0C50.2,131.3 48.7,126.4 47.4,122.0C47.1,121.0 46.7,119.5 46.4,118.5C46.1,117.6 45.9,116.7 45.9,116.5C45.9,116.4 45.7,115.5 45.4,114.6C44.5,111.7 44.1,110.0 43.7,108.6C43.1,106.0 42.7,104.3 42.3,102.8C41.9,101.3 41.5,99.5 40.4,94.8C39.5,90.8 39.3,90.2 39.0,88.4C38.8,87.4 38.6,86.3 38.5,86.1C38.3,85.8 38.0,83.9 37.1,79.4C37.0,78.6 36.6,76.7 36.4,75.0C36.1,73.4 35.6,70.9 35.4,69.5C35.1,68.0 34.9,66.5 34.9,66.0C34.9,65.4 34.7,64.2 34.5,63.1C34.3,62.0 34.1,60.2 34.0,59.1C33.9,58.0 33.7,55.8 33.5,54.4C33.3,52.9 33.0,48.8 32.9,45.3C32.6,36.7 32.2,32.3 31.9,31.7C31.7,31.4 31.4,31.0 31.1,30.9C30.1,30.4 29.1,31.5 27.4,35.1C25.5,38.9 25.1,39.8 24.4,41.6C24.1,42.4 23.6,43.5 23.3,44.0C23.1,44.6 22.9,45.2 22.9,45.3C22.9,45.4 22.7,45.8 22.5,46.2C22.2,47.0 22.0,47.4 21.0,50.1C20.8,50.8 20.4,51.6 20.2,52.1C20.0,52.5 19.9,53.0 19.9,53.2C19.9,53.4 19.6,54.0 19.4,54.5C19.1,55.1 18.9,55.7 18.9,55.9C18.9,56.2 18.7,56.9 18.4,57.4C18.1,58.0 17.5,60.0 16.9,61.9C16.3,63.7 15.6,65.8 15.4,66.5C15.1,67.2 14.8,68.2 14.7,68.8C14.5,69.3 14.2,70.6 13.9,71.5C13.0,74.4 11.7,79.3 10.9,82.6C10.6,83.7 10.3,85.0 10.1,85.6C10.0,86.3 9.6,87.8 9.3,89.1C9.1,90.4 8.6,92.4 8.3,93.5C8.1,94.6 7.9,95.8 7.9,96.0C7.9,96.3 7.7,97.2 7.5,98.0C7.2,99.2 7.0,100.2 6.1,105.6C6.0,106.5 5.6,108.5 5.4,110.0C5.1,111.5 4.9,113.0 4.9,113.4C4.9,113.7 4.7,115.5 4.4,117.3C3.7,121.8 3.0,129.2 2.4,136.8C2.1,141.8 2.0,146.6 2.0,158.4C2.0,174.4 2.2,179.8 3.4,189.5C4.4,197.8 4.9,201.3 6.1,206.1C6.3,206.8 6.6,207.9 6.7,208.6C7.1,210.2 8.0,212.9 8.5,214.1C8.7,214.5 8.9,215.0 8.9,215.1C8.9,215.3 9.0,215.7 9.2,216.1C9.4,216.5 9.9,217.5 10.4,218.4C13.2,224.4 17.5,229.4 22.6,232.7C26.9,235.5 30.0,236.8 35.0,237.8C38.9,238.5 42.3,238.6 46.1,237.9Z",
        "M115.5,195.4C118.2,195.2 119.2,195.0 122.6,193.8C128.2,192.0 133.3,187.5 137.2,181.1C137.6,180.4 138.6,178.0 139.3,176.1C141.7,169.7 142.5,161.2 142.3,147.8C142.1,138.3 141.7,129.7 141.4,126.8C141.2,125.5 141.0,123.0 140.9,121.1C140.6,116.8 140.0,110.7 139.5,107.4C139.3,105.9 139.0,103.9 138.9,102.8C138.8,101.7 138.5,99.6 138.3,98.3C137.8,95.4 137.0,90.5 136.6,88.3C136.5,87.4 136.2,85.7 136.0,84.4C135.8,83.2 135.4,81.5 135.2,80.7C135.0,79.9 134.9,78.9 134.9,78.5C134.9,78.1 134.6,76.9 134.4,75.9C134.1,74.9 133.9,73.8 133.9,73.6C133.9,73.3 133.6,72.0 133.4,70.8C133.1,69.5 132.6,67.4 132.3,66.1C131.7,63.1 131.0,60.0 130.4,57.6C130.1,56.6 129.8,55.2 129.6,54.5C128.7,50.6 128.7,50.3 127.6,46.8C127.5,46.2 127.1,45.0 126.9,44.0C126.1,41.2 124.6,36.0 122.0,27.6C121.3,25.5 119.8,21.0 119.4,19.9C118.8,18.5 118.4,17.3 118.0,15.9C117.8,15.3 117.5,14.5 117.4,14.3C117.2,14.0 117.0,13.3 116.8,12.8C116.6,12.2 116.2,11.1 115.9,10.4C115.6,9.6 115.2,8.6 115.0,8.1C114.2,6.1 113.0,3.8 112.3,3.1C111.2,2.0 110.1,2.1 109.1,3.5C108.6,4.0 107.9,5.2 107.5,6.1C107.1,7.0 106.6,8.2 106.3,8.8C106.1,9.4 105.9,9.9 105.9,10.0C105.9,10.1 105.7,10.7 105.4,11.2C105.2,11.8 104.8,12.7 104.6,13.1C104.5,13.6 104.0,14.7 103.7,15.6C103.4,16.5 103.0,17.6 102.9,18.0C102.8,18.4 102.5,19.2 102.3,19.6C101.8,20.8 101.4,22.0 101.0,23.4C100.8,24.0 100.5,25.1 100.2,25.8C100.0,26.5 99.6,27.6 99.4,28.3C98.6,30.5 97.4,34.7 95.4,41.6C95.1,42.5 94.7,44.1 94.4,45.0C94.1,46.0 93.9,47.0 93.9,47.2C93.9,47.4 93.7,48.2 93.4,49.1C93.1,50.0 92.8,51.3 92.6,52.0C91.7,55.8 91.3,57.4 91.1,58.5C90.9,59.2 90.6,60.5 90.4,61.4C90.1,62.3 89.8,63.7 89.6,64.5C89.5,65.3 89.1,67.0 88.8,68.3C88.4,70.3 87.9,72.8 87.1,76.9C87.0,77.6 86.6,79.2 86.4,80.4C86.1,81.6 85.9,82.9 85.9,83.2C85.9,83.5 85.7,84.9 85.4,86.4C85.1,87.8 84.7,90.4 84.4,92.1C84.1,93.9 83.7,96.6 83.4,98.3C83.1,99.9 82.9,101.6 82.9,102.0C82.9,102.4 82.7,104.2 82.4,105.9C81.8,109.9 81.1,115.6 80.9,119.8C80.7,121.6 80.5,124.5 80.3,126.3C79.6,132.2 79.2,153.5 79.6,160.8C79.9,165.6 80.6,170.6 81.4,173.0C81.7,173.9 81.9,174.7 81.9,174.9C81.9,175.0 82.0,175.5 82.2,176.0C82.4,176.4 82.9,177.5 83.3,178.4C83.7,179.3 84.2,180.3 84.4,180.6C84.7,180.9 84.9,181.3 84.9,181.4C84.9,182.0 87.7,185.5 89.7,187.5C94.4,191.9 101.4,194.9 108.2,195.4C111.7,195.7 112.6,195.7 115.5,195.4Z",
        "M186.1,237.7C187.8,237.4 189.9,236.9 190.7,236.6C192.2,236.1 196.3,234.2 197.4,233.4C200.2,231.6 201.3,230.7 203.8,228.3C206.1,225.9 207.0,224.8 209.4,221.1C209.7,220.6 211.4,217.1 212.3,215.3C212.9,213.8 214.0,210.5 214.7,208.0C214.8,207.5 215.1,206.5 215.3,205.8C215.6,204.7 216.0,202.6 216.6,199.3C216.8,198.4 217.1,196.5 217.4,195.0C217.7,193.5 217.9,191.7 217.9,191.1C217.9,190.4 218.1,188.3 218.4,186.3C218.6,184.4 218.9,181.0 219.0,178.8C219.1,176.6 219.3,172.9 219.5,170.6C220.3,162.1 219.6,139.3 218.4,129.4C218.1,127.3 217.9,125.0 217.9,124.4C217.9,123.8 217.6,121.9 217.4,120.3C217.1,118.6 216.9,116.9 216.9,116.4C216.9,115.9 216.7,114.3 216.4,112.9C216.1,111.4 215.8,109.5 215.7,108.5C215.2,105.3 214.8,103.3 214.4,101.0C213.6,97.0 213.4,96.0 213.1,94.5C212.7,92.5 211.6,87.6 210.1,81.6C208.5,75.2 207.6,72.2 205.0,63.6C204.3,61.3 202.6,56.5 202.2,55.7C202.0,55.3 201.9,54.8 201.9,54.7C201.9,54.5 201.7,53.8 201.4,53.2C201.2,52.5 200.7,51.3 200.4,50.5C200.1,49.7 199.6,48.5 199.4,47.9C199.1,47.3 198.7,46.2 198.4,45.5C195.6,38.5 192.9,32.9 191.9,32.0C190.9,31.2 190.5,31.2 189.9,32.1C189.6,32.7 189.5,33.6 189.3,39.1C189.1,49.0 188.7,53.0 187.5,61.3C187.3,62.6 187.0,64.7 186.9,65.8C186.7,66.9 186.5,68.1 186.4,68.5C186.3,68.9 186.0,70.1 185.9,71.2C185.8,72.2 185.5,73.7 185.3,74.5C185.0,75.3 184.9,76.2 184.9,76.5C184.9,77.0 184.3,79.8 182.4,88.0C182.1,89.1 181.7,91.1 181.4,92.4C180.7,95.4 180.0,98.4 179.6,99.9C179.5,100.5 179.1,101.9 178.9,103.0C178.6,104.0 178.1,105.8 177.9,107.0C177.6,108.1 177.2,109.6 177.0,110.4C176.8,111.1 176.5,112.3 176.3,113.0C176.1,113.6 175.9,114.4 175.9,114.6C175.9,114.8 175.7,115.8 175.4,116.7C175.1,117.6 174.6,119.2 174.4,120.2C173.0,125.2 171.0,131.7 170.4,133.5C170.1,134.2 169.6,135.8 169.2,137.1C168.3,140.0 168.0,140.8 167.4,142.5C167.1,143.2 166.9,144.0 166.8,144.3C166.7,144.5 166.4,145.6 166.0,146.5C165.6,147.5 165.1,148.9 164.9,149.6C164.1,151.9 163.6,153.2 163.4,153.8C163.2,154.2 162.8,155.3 162.0,157.5C161.8,158.1 161.3,159.3 161.0,160.3C160.6,161.2 160.2,162.5 160.0,163.0C159.8,163.6 159.4,164.4 159.2,164.8C159.0,165.2 158.9,165.7 158.9,165.9C158.9,166.1 158.7,166.6 158.5,167.0C158.3,167.4 158.0,168.1 157.9,168.6C157.8,169.1 157.4,170.3 157.0,171.3C156.6,172.2 156.0,174.1 155.6,175.4C155.2,176.7 154.6,178.3 154.4,179.0C153.5,181.4 151.8,187.6 151.1,191.0C151.0,191.7 150.7,193.0 150.5,194.0C149.9,196.6 149.4,200.7 149.2,204.3C149.0,209.8 150.1,215.9 152.2,219.8C152.3,220.0 152.7,220.7 152.9,221.1C154.6,224.2 156.9,227.3 160.0,230.2C163.9,234.0 168.5,236.5 173.8,237.6C174.7,237.8 175.9,238.0 176.4,238.1C178.4,238.6 182.9,238.4 186.1,237.7Z",
        "M122.0,291.7C127.9,285.9 138.4,275.5 145.3,268.6C154.8,259.2 157.9,256.1 157.9,255.6C157.9,255.2 152.3,249.5 134.7,231.8C114.3,211.5 111.4,208.6 110.8,208.6C110.1,208.6 108.8,209.8 100.2,218.6C68.5,250.6 63.9,255.3 63.9,256.0C63.9,256.5 66.9,259.6 78.4,271.0C86.4,279.0 96.8,289.3 101.5,293.9C108.4,300.8 110.1,302.4 110.6,302.4C111.2,302.4 113.3,300.4 122.0,291.7Z",
    ]

    /// The outlines use only absolute M, C and Z commands.
    /// One outline per piece: the three feathers, then the beak.
    static let parts: [Path] = paths.map { d in
        var path = Path()
        do {
            var numbers: [CGFloat] = []
            var command: Character = "M"
            func flush() {
                switch command {
                case "M":
                    if numbers.count >= 2 { path.move(to: CGPoint(x: numbers[0], y: numbers[1])) }
                case "C":
                    var i = 0
                    while i + 5 < numbers.count {
                        path.addCurve(to: CGPoint(x: numbers[i + 4], y: numbers[i + 5]),
                                      control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                                      control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                        i += 6
                    }
                default: break
                }
                numbers.removeAll()
            }
            var token = ""
            func endNumber() { if let n = Double(token) { numbers.append(CGFloat(n)) }; token = "" }
            for ch in d {
                if ch == "M" || ch == "C" || ch == "Z" {
                    endNumber(); flush()
                    if ch == "Z" { path.closeSubpath() }
                    command = ch
                } else if ch == "," || ch == " " {
                    endNumber()
                } else if ch == "-", !token.isEmpty {
                    endNumber(); token = "-"
                } else {
                    token.append(ch)
                }
            }
            endNumber(); flush()
        }
        return path
    }
    private static let outline: Path = parts.reduce(into: Path()) { $0.addPath($1) }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.size.width, rect.height / Self.size.height)
        let x = rect.midX - Self.size.width * scale / 2
        let y = rect.midY - Self.size.height * scale / 2
        return (part.map { Self.parts[$0] } ?? Self.outline).applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
    }
}

/// "by Flake" with the mark, for the sidebar and the About window.
struct MadeByFlake: View {
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size * 0.4) {
            FlakeMark().frame(width: size * 0.8, height: size * 1.1)
            Text("by FLAKE").font(.system(size: size * 0.82, weight: .semibold)).tracking(size * 0.22)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("by Flake")
    }
}

/// A row of stops joined by a line, as on the Flake website: the line grows towards the current stop and each
/// circle fills in once the line reaches it. The current stop gets a soft halo.
struct TimelineSteps: View {
    struct Stop: Identifiable {
        let id: Int
        let label: String
        var title: String? = nil
        var detail: String? = nil
    }

    let stops: [Stop]
    let current: Int
    /// Ticks in the circles behind the current stop, for steps that are finished.
    var ticks = false
    var dot: CGFloat = 18

    /// How far along the line is drawn, in stops (0 is the first circle).
    @State private var drawn: CGFloat = 0
    @State private var halo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let column = geo.size.width / CGFloat(max(stops.count, 1))
            let start = column / 2
            let span = column * CGFloat(max(stops.count - 1, 0))
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.12))
                    .frame(width: span, height: 1.5)
                    .offset(x: start, y: dot / 2 - 0.75)
                Capsule().fill(Theme.accent)
                    .frame(width: column * drawn, height: 1.5)
                    .offset(x: start, y: dot / 2 - 0.75)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(stops) { stop in
                        VStack(spacing: 8) {
                            circle(for: stop.id)
                            VStack(spacing: 3) {
                                Text(stop.label)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .tracking(1.2).textCase(.uppercase)
                                    .foregroundStyle(stop.id == current ? .primary : .secondary)
                                if let title = stop.title { Text(title).font(.headline) }
                                if let detail = stop.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(width: column)
                    }
                }
            }
        }
        .frame(height: height)
        .onAppear { move(to: current, animated: !reduceMotion) }
        .onChange(of: current) { _, value in move(to: value, animated: !reduceMotion) }
    }

    private var height: CGFloat {
        let hasTitle = stops.contains { $0.title != nil }
        let hasDetail = stops.contains { $0.detail != nil }
        return dot + 8 + 14 + (hasTitle ? 22 : 0) + (hasDetail ? 34 : 0)
    }

    private func move(to index: Int, animated: Bool) {
        let target = CGFloat(index)
        guard animated else { drawn = target; return }
        // The line travels at a steady speed, so a longer stretch takes longer, like scrolling on the website.
        let duration = 0.45 + 0.35 * Double(abs(target - drawn))
        withAnimation(.easeInOut(duration: duration)) { drawn = target }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { halo = true }
    }

    @ViewBuilder private func circle(for index: Int) -> some View {
        let reached = drawn + 0.02 >= CGFloat(index)
        ZStack {
            Circle().fill(Theme.background)
            Circle().fill(Theme.accent).opacity(reached ? 1 : 0)
            Circle().strokeBorder(reached ? Theme.accent : Color.white.opacity(0.45), lineWidth: 1.2)
            if ticks, reached, index < current {
                Icon("checkmark").font(.system(size: dot * 0.45, weight: .bold)).foregroundStyle(Theme.onFill)
            }
        }
        .frame(width: dot, height: dot)
        // The halo sits behind the circle without changing its size or position.
        .background {
            if index == current {
                Circle().fill(Color.white.opacity(halo ? 0.14 : 0.05)).frame(width: dot * 1.9, height: dot * 1.9)
            }
        }
        .frame(width: dot * 2, height: dot)
        .animation(.easeOut(duration: 0.3), value: reached)
    }
}

/// Alloy's About window: the version, who makes it, what comes next and where to get help.
struct AboutAlloyView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 88, height: 88)
                Text("Alloy").font(.system(size: 26, weight: .semibold))
                Text("Version \(Flake.displayVersion)").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                MadeByFlake(size: 13).padding(.top, 2)
            }
            .padding(.top, 30)

            VStack(alignment: .leading, spacing: 14) {
                Text("What's next")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    FlakeWireframe().frame(width: 150, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Something new is taking shape").font(.headline)
                        Text("Flake is working on its next app. When it's ready, you'll see it here first.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 26)

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                Button("Check for Updates") { openWindow(id: "updates"); Task { await Updater.shared.check() } }
                Button("Get Support") { NSWorkspace.shared.open(Flake.email(subject: "Alloy support")) }
                Button("Report a Bug") { NSWorkspace.shared.open(Flake.bugReport) }
            }
            .controlSize(.large)

            Text("© \(String(Calendar.current.component(.year, from: Date()))) Flake. Alloy is free, open-source software (GPL-3.0), built on Wine and other open-source projects.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 22)
        }
        .frame(width: 460, height: 500)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
