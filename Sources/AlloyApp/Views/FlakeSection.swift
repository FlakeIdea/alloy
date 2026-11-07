import AppKit
import SwiftUI
import AlloyCore

/// The Flake mark drawn as a wireframe, as in "What's next" on flake.co.in: each feather and then the beak trace
/// themselves in, hold, and erase from where they started, on a six-second loop, inside a dashed, hatched frame.
struct FlakeWireframe: View {
    var lineWidth: CGFloat = 1.4
    /// The mark's height as a share of the frame, like the website's 56%.
    var scale: CGFloat = 0.56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cycle = 6.0
    private static let delays = [0, 0.25, 0.5, 0.75]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            Hatch().clipShape(shape)
            shape.strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            GeometryReader { geo in
                let size = min(geo.size.height * scale, geo.size.width * 0.8)
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<4, id: \.self) { part in
                            let (from, to) = reduceMotion ? (0, 1) : Self.trim(time - Self.delays[part])
                            FlakeMark(part: part)
                                .trim(from: from, to: to)
                                .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .frame(width: size, height: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The website's keyframes: drawn from 0 to 40% of the loop, held to 72%, then erased from the start.
    static func trim(_ time: Double) -> (CGFloat, CGFloat) {
        let t = (time.truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle) / cycle
        if t < 0.4 { return (0, ease(t / 0.4)) }
        if t < 0.72 { return (0, 1) }
        return (ease((t - 0.72) / 0.28), 1)
    }

    /// cubic-bezier(.65, 0, .35, 1), the website's --ease.
    static func ease(_ x: Double) -> CGFloat {
        let (x1, y1, x2, y2) = (0.65, 0.0, 0.35, 1.0)
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if bezier(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return CGFloat(bezier(t, y1, y2))
    }

    /// Faint diagonal lines every 15 points, like the website's hatching.
    private struct Hatch: View {
        var body: some View {
            Canvas { context, size in
                var lines = Path()
                var x = -size.height
                while x < size.width {
                    lines.move(to: CGPoint(x: x, y: size.height))
                    lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 15
                }
                context.stroke(lines, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
        }
    }
}

/// The Flake page in the sidebar: who makes Alloy, what's next and how to reach us.
struct FlakeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Flake", subtitle: "The studio that makes Alloy")
                    .padding(.horizontal, -28)

                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("In the works")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(1.2).textCase(.uppercase)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                            .foregroundStyle(.secondary)
                        Text("What's next").font(.system(size: 28, weight: .semibold))
                        Text("Something new is taking shape. When it's ready, you'll see it here first.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Say hello") { NSWorkspace.shared.open(Flake.hello) }
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                    FlakeWireframe(lineWidth: 1.6)
                        .aspectRatio(2, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
                .glassCard(cornerRadius: 22)

                Panel("About Flake") {
                    Text("Flake is an independent software studio. We build software for good: focused apps that solve real problems people overlook, and make the lives we already have better. Alloy is the first.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    belief("01", "Software for good", "Tools that help people, not ones that compete for their attention. No ads, no tracking and no tricks to keep you hooked.")
                    belief("02", "Real problems, easily overlooked", "The everyday obstacles people stopped noticing because they seem too ordinary to fix. We fix them properly.")
                    belief("03", "Better lives, not new ones", "Apps that work with the devices you already have. You shouldn't need to buy something new to benefit.")
                }

                Panel("Get in touch") {
                    HStack(spacing: 10) {
                        Button("flake.co.in") { NSWorkspace.shared.open(Flake.website) }
                        Button("Say Hello") { NSWorkspace.shared.open(Flake.hello) }
                        Button("Get Support") { NSWorkspace.shared.open(Flake.email(subject: "Alloy support")) }
                        Button("Report a Bug") { NSWorkspace.shared.open(Flake.bugReport) }
                        Spacer()
                    }
                    Text("\(Flake.helloEmail) for ideas and feedback, \(Flake.supportEmail) for help with Alloy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
    }

    private func belief(_ number: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(cornerRadius: 16)
    }
}
