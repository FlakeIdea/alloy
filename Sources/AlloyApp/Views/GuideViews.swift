import AppKit
import SwiftUI
import AlloyCore

/// The terms of use, opened again from Settings. First launch shows them inside the setup wizard.
struct TermsSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            GuideHeader(symbol: "checkmark.shield.fill", title: Terms.title,
                        subtitle: "Version \(Terms.version), last updated \(Terms.updated)")
            ScrollView { TermsText().padding(28) }
            Divider()
            HStack {
                Spacer()
                Button("Done") { model.sheet = nil }.keyboardShortcut(.defaultAction).primaryAction()
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 640, height: 620)
    }
}

struct TermsText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Terms.intro).foregroundStyle(.secondary)
            ForEach(Terms.sections) { section in
                HStack(alignment: .top, spacing: 14) {
                    Icon(section.symbol).font(.title3).foregroundStyle(Theme.gradient).frame(width: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title).font(.headline)
                        ForEach(section.paragraphs, id: \.self) { Text(LocalizedStringKey($0)).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
        }
    }
}

/// The engine's components and what Alloy downloads, each with its licence and project page.
struct LicencesSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            GuideHeader(symbol: "doc.text.fill", title: "Open-Source Licences", subtitle: "What Alloy is built from and installs")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(OpenSourceNotices.intro).foregroundStyle(.secondary)
                    ForEach(OpenSourceNotices.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title).font(.headline)
                            Text(group.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            VStack(spacing: 0) {
                                ForEach(group.components) { component in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let url = URL(string: component.url), !component.url.isEmpty {
                                                Link(component.name, destination: url).font(.body.weight(.semibold))
                                            } else {
                                                Text(component.name).font(.body.weight(.semibold))
                                            }
                                            Text(component.use).font(.caption).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 12)
                                        Text(component.licence).font(.caption.monospaced()).foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing).frame(maxWidth: 190, alignment: .trailing)
                                    }
                                    .padding(.vertical, 8)
                                    if component != group.components.last { Divider().opacity(0.4) }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
                        }
                    }
                }
                .padding(28)
            }
            Divider()
            HStack {
                Text("Full licence texts are in the engine's licences folder.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.sheet = nil }.keyboardShortcut(.defaultAction).primaryAction()
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 640, height: 640)
    }
}

/// The graphics tutorial as numbered steps.
struct GraphicsGuideSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            GuideHeader(symbol: "slider.horizontal.3", title: GraphicsGuide.title, subtitle: "What to try when a game is slow or looks wrong")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(GraphicsGuide.intro).foregroundStyle(.secondary)
                    ForEach(Array(GraphicsGuide.steps(displayRefreshRate: DisplayInfo.refreshRate()).enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(Theme.onFill)
                                .frame(width: 30, height: 30).background(Circle().fill(Theme.fill))
                            VStack(alignment: .leading, spacing: 6) {
                                Label { Text(step.title) } icon: { Icon(step.symbol) }.font(.headline)
                                ForEach(step.paragraphs, id: \.self) { Text(LocalizedStringKey($0)).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                }
                .padding(28)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { model.sheet = nil }.keyboardShortcut(.defaultAction).primaryAction()
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 640, height: 640)
    }
}

private struct GuideHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Icon(symbol).font(.largeTitle).foregroundStyle(Theme.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
        .background(Theme.accent.opacity(0.08))
    }
}
