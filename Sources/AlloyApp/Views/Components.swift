import SwiftUI
import AppKit
import AlloyCore

extension View {
    /// A flat surface with a hairline edge. Alloy draws its own surfaces instead of system glass, so it looks like itself.
    func glassCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: min(cornerRadius, 14), style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: min(cornerRadius, 14), style: .continuous).strokeBorder(Theme.hairline))
    }

    /// The main action on a page: a solid capsule.
    func primaryAction(_ tint: Color = Theme.accent) -> some View { buttonStyle(PrimaryCapsule(tint: tint)) }

    /// A secondary action: a hairline capsule.
    func secondaryAction() -> some View { buttonStyle(GhostCapsule()) }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Kicker(text: subtitle)
                Text(title).font(.system(size: 34, weight: .heavy)).tracking(-0.8)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 12)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }) }
}

struct Panel<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Kicker(text: title).padding(.bottom, 2) }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }
}

struct StatusPill: View {
    let state: LaunchState
    var body: some View {
        let color: Color = {
            switch state {
            case .idle: return .gray
            case .running: return Theme.success
            case .exited(let c): return c == 0 ? .gray : Theme.warning
            case .terminatedBySignal: return .gray
            case .failed: return Theme.danger
            }
        }()
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(state.summary).font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(1).textCase(.uppercase)
        }
        .padding(.horizontal, 10).frame(height: 22)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .foregroundStyle(.secondary)
    }
}

struct CapabilityTag: View {
    let status: CapabilityStatus
    var body: some View {
        switch status {
        case .available: tag("Available", Theme.accent)
        case .experimental: tag("Experimental", Theme.warning)
        case .unavailable: tag("Unavailable", .gray)
        }
    }
    func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2))).foregroundStyle(color)
    }
}

struct LogConsole: View {
    let lines: [LogLine]
    @State private var copied = false

    /// The most recent lines, as one text so a selection can span lines (⌘A, ⌘C or drag).
    static let shownLines = 3000

    var body: some View {
        let shown = lines.suffix(Self.shownLines)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if lines.count > shown.count {
                        Text("Showing the last \(shown.count) of \(lines.count) lines. Copy All copies every line.")
                            .font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
                    }
                    Text(attributed(shown))
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(10)
                .padding(.top, 18)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.45)))
            .overlay {
                if lines.isEmpty { Text("No output yet").foregroundStyle(.secondary) }
            }
            .overlay(alignment: .topTrailing) {
                if !lines.isEmpty {
                    Button { copyAll() } label: {
                        Label(copied ? "Copied" : "Copy All", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(8)
                    .help("Copy the whole output to the clipboard")
                }
            }
            .onChange(of: lines.last?.id) { _, newID in
                if newID != nil { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    func attributed(_ shown: ArraySlice<LogLine>) -> AttributedString {
        var out = AttributedString()
        for (i, line) in shown.enumerated() {
            var part = AttributedString(i == shown.count - 1 ? line.text : line.text + "\n")
            part.foregroundColor = color(line)
            out += part
        }
        return out
    }

    func copyAll() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
        copied = true
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
    }

    func color(_ line: LogLine) -> Color {
        if line.stream == .alloy { return Theme.accentAlt }
        if line.text.contains("err:") || line.text.contains("Unhandled") { return Theme.danger }
        if line.stream == .stderr { return Color.white.opacity(0.65) }
        return .white
    }
}

struct FindingRow: View {
    let finding: DiagnosticFinding
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(symbol).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.title).font(.callout.bold())
                Text(finding.detail).font(.callout).foregroundStyle(.secondary)
                if !finding.suggestion.isEmpty {
                    Text(finding.suggestion).font(.callout).foregroundStyle(Theme.accent)
                }
                if let evidence = finding.evidence {
                    Text(evidence).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var symbol: String {
        switch finding.severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch finding.severity {
        case .error: return Theme.danger
        case .warning: return Theme.warning
        case .info: return Theme.accentAlt
        }
    }
}

struct GamePicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Game", selection: $model.selectedGameID) {
            Text("Select a game").tag(UUID?.none)
            ForEach(model.games) { Text($0.name).tag(UUID?.some($0.id)) }
        }
        .frame(maxWidth: 280)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Icon(symbol).font(.system(size: 44)).foregroundStyle(Theme.gradient)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
