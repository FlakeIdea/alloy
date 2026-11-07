import AppKit
import CoreImage
import SwiftUI
import AlloyCore

// Alloy's own look: an editorial, game-first layout that shares the Flake website's type and hairlines. Tabs along the
// top instead of a sidebar, box art instead of rows, and icons drawn here instead of system symbols.

// MARK: - Glyphs

/// Alloy's icon set, drawn on a 24-point grid with one stroke weight.
enum Glyph: Hashable {
    case library, setup, advanced, add, play, stop, restart, more, back, battery, balanced, sharp, store, check, alert, guide
    case shield, lock, trash, minus, export, bolt, box, wait, offline, doc, pulse, cross, ring, list, frames, mac

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - 12) * s, y: rect.midY + (y - 12) * s) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: rect.midX + (x - 12) * s, y: rect.midY + (y - 12) * s, width: w * s, height: h * s),
                 cornerRadius: c * s)
        }
        var path = Path()
        switch self {
        case .library:
            // Three box covers, the front one tallest.
            path.addPath(r(3, 7, 5, 11, 1.2)); path.addPath(r(9.5, 4, 6, 16, 1.4)); path.addPath(r(17, 7, 4, 11, 1.2))
        case .setup:
            // A tray with a line coming down into it.
            path.move(to: p(12, 3)); path.addLine(to: p(12, 14))
            path.move(to: p(8, 10.5)); path.addLine(to: p(12, 14.5)); path.addLine(to: p(16, 10.5))
            path.move(to: p(4, 15)); path.addLine(to: p(4, 20)); path.addLine(to: p(20, 20)); path.addLine(to: p(20, 15))
        case .advanced:
            // Two rails, each with a square knob.
            path.move(to: p(3, 8)); path.addLine(to: p(21, 8)); path.move(to: p(3, 16)); path.addLine(to: p(21, 16))
            path.addPath(r(13, 5.5, 5, 5, 1)); path.addPath(r(6, 13.5, 5, 5, 1))
        case .add:
            path.move(to: p(12, 5)); path.addLine(to: p(12, 19)); path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
        case .play:
            path.move(to: p(7.5, 4.5)); path.addLine(to: p(19.5, 12)); path.addLine(to: p(7.5, 19.5)); path.closeSubpath()
        case .stop:
            path.addPath(r(6, 6, 12, 12, 2))
        case .restart:
            path.addArc(center: p(12, 12), radius: 7 * s, startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false)
            path.move(to: p(15.5, 2.5)); path.addLine(to: p(15.5, 6.5)); path.addLine(to: p(11.5, 6.5))
        case .more:
            for x in [6.0, 12.0, 18.0] { path.addEllipse(in: CGRect(origin: p(x - 1.2, 10.8), size: CGSize(width: 2.4 * s, height: 2.4 * s))) }
        case .back:
            path.move(to: p(14, 5)); path.addLine(to: p(7, 12)); path.addLine(to: p(14, 19))
        case .battery:
            // A ring, half of it drawn: holding back.
            path.addArc(center: p(12, 12), radius: 7.5 * s, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            path.move(to: p(12, 4.5)); path.addLine(to: p(12, 19.5))
        case .balanced:
            path.addEllipse(in: CGRect(origin: p(4.5, 4.5), size: CGSize(width: 15 * s, height: 15 * s)))
            path.move(to: p(4.5, 12)); path.addLine(to: p(19.5, 12))
        case .sharp:
            path.move(to: p(12, 3.5)); path.addLine(to: p(20.5, 12)); path.addLine(to: p(12, 20.5)); path.addLine(to: p(3.5, 12)); path.closeSubpath()
            path.move(to: p(12, 8.5)); path.addLine(to: p(15.5, 12)); path.addLine(to: p(12, 15.5)); path.addLine(to: p(8.5, 12)); path.closeSubpath()
        case .store:
            path.addPath(r(4, 8, 16, 12, 2))
            path.move(to: p(8.5, 8)); path.addCurve(to: p(15.5, 8), control1: p(8.5, 2.5), control2: p(15.5, 2.5))
        case .check:
            path.move(to: p(5, 12.5)); path.addLine(to: p(10, 17.5)); path.addLine(to: p(19, 7))
        case .alert:
            path.move(to: p(12, 4)); path.addLine(to: p(21, 20)); path.addLine(to: p(3, 20)); path.closeSubpath()
            path.move(to: p(12, 10)); path.addLine(to: p(12, 14.5)); path.move(to: p(12, 17)); path.addLine(to: p(12, 17.2))
        case .guide:
            path.addEllipse(in: CGRect(origin: p(4, 4), size: CGSize(width: 16 * s, height: 16 * s)))
            path.move(to: p(9.5, 9.5)); path.addCurve(to: p(12, 13.5), control1: p(9.5, 6.5), control2: p(15.5, 7.5))
            path.move(to: p(12, 16.5)); path.addLine(to: p(12, 16.7))
        case .shield:
            path.move(to: p(12, 3)); path.addLine(to: p(19.5, 6)); path.addLine(to: p(19.5, 11.5))
            path.addCurve(to: p(12, 21), control1: p(19.5, 16), control2: p(16, 19.5))
            path.addCurve(to: p(4.5, 11.5), control1: p(8, 19.5), control2: p(4.5, 16))
            path.addLine(to: p(4.5, 6)); path.closeSubpath()
        case .lock:
            path.addPath(r(5, 11, 14, 9.5, 2))
            path.move(to: p(8, 11)); path.addLine(to: p(8, 8)); path.addCurve(to: p(16, 8), control1: p(8, 2.5), control2: p(16, 2.5))
            path.addLine(to: p(16, 11))
        case .trash:
            path.move(to: p(4, 6.5)); path.addLine(to: p(20, 6.5))
            path.move(to: p(9.5, 6.5)); path.addLine(to: p(9.5, 3.5)); path.addLine(to: p(14.5, 3.5)); path.addLine(to: p(14.5, 6.5))
            path.move(to: p(6, 6.5)); path.addLine(to: p(7, 20.5)); path.addLine(to: p(17, 20.5)); path.addLine(to: p(18, 6.5))
        case .minus:
            path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
        case .export:
            path.move(to: p(12, 15)); path.addLine(to: p(12, 3.5))
            path.move(to: p(8, 7.5)); path.addLine(to: p(12, 3.5)); path.addLine(to: p(16, 7.5))
            path.move(to: p(4, 13)); path.addLine(to: p(4, 20)); path.addLine(to: p(20, 20)); path.addLine(to: p(20, 13))
        case .bolt:
            path.move(to: p(13.5, 2.5)); path.addLine(to: p(5.5, 13.5)); path.addLine(to: p(11.5, 13.5))
            path.addLine(to: p(10.5, 21.5)); path.addLine(to: p(18.5, 10.5)); path.addLine(to: p(12.5, 10.5)); path.closeSubpath()
        case .box:
            path.move(to: p(12, 3)); path.addLine(to: p(20, 7.5)); path.addLine(to: p(20, 16.5)); path.addLine(to: p(12, 21))
            path.addLine(to: p(4, 16.5)); path.addLine(to: p(4, 7.5)); path.closeSubpath()
            path.move(to: p(4, 7.5)); path.addLine(to: p(12, 12)); path.addLine(to: p(20, 7.5)); path.move(to: p(12, 12)); path.addLine(to: p(12, 21))
        case .wait:
            path.move(to: p(6, 3.5)); path.addLine(to: p(18, 3.5)); path.move(to: p(6, 20.5)); path.addLine(to: p(18, 20.5))
            path.move(to: p(7.5, 3.5)); path.addLine(to: p(16.5, 20.5)); path.move(to: p(16.5, 3.5)); path.addLine(to: p(7.5, 20.5))
        case .offline:
            path.addArc(center: p(12, 19), radius: 13 * s, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            path.addArc(center: p(12, 19), radius: 8 * s, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            path.move(to: p(4, 4)); path.addLine(to: p(20, 20))
        case .doc:
            path.move(to: p(6, 3)); path.addLine(to: p(14, 3)); path.addLine(to: p(18.5, 7.5)); path.addLine(to: p(18.5, 21))
            path.addLine(to: p(6, 21)); path.closeSubpath()
            path.move(to: p(9, 12)); path.addLine(to: p(15.5, 12)); path.move(to: p(9, 16)); path.addLine(to: p(15.5, 16))
        case .pulse:
            path.move(to: p(2.5, 12)); path.addLine(to: p(7, 12)); path.addLine(to: p(9.5, 6)); path.addLine(to: p(14, 19))
            path.addLine(to: p(16.5, 12)); path.addLine(to: p(21.5, 12))
        case .cross:
            path.move(to: p(6, 6)); path.addLine(to: p(18, 18)); path.move(to: p(18, 6)); path.addLine(to: p(6, 18))
        case .ring:
            path.addEllipse(in: CGRect(origin: p(5, 5), size: CGSize(width: 14 * s, height: 14 * s)))
        case .list:
            for y in [6.0, 12.0, 18.0] { path.move(to: p(9, y)); path.addLine(to: p(20, y)); path.move(to: p(4, y)); path.addLine(to: p(5, y)) }
        case .frames:
            path.addPath(r(3, 7, 11, 11, 1.5)); path.move(to: p(17, 7)); path.addLine(to: p(17, 18)); path.move(to: p(20.5, 8.5)); path.addLine(to: p(20.5, 16.5))
        case .mac:
            path.addPath(r(4, 4.5, 16, 11, 1.5)); path.move(to: p(2, 19.5)); path.addLine(to: p(22, 19.5))
        }
        return path
    }

    var filled: Bool { self == .play || self == .stop }
}

struct GlyphView: View {
    let glyph: Glyph
    var size: CGFloat = 16
    var weight: CGFloat = 1.6

    var body: some View {
        GlyphShape(glyph: glyph)
            .stroke(style: StrokeStyle(lineWidth: weight * size / 16, lineCap: .round, lineJoin: .round))
            .background(glyph.filled ? GlyphShape(glyph: glyph).fill() : nil)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

/// An icon that takes its size from the current font, like a system symbol, so it drops into labels and text.
struct Icon: View {
    let glyph: Glyph
    init(_ glyph: Glyph) { self.glyph = glyph }
    /// For names that were system symbols, so callers that pick an icon by name keep working.
    init(_ name: String) { self.glyph = Glyph(symbolName: name) }

    var body: some View {
        Image(systemName: "square").hidden()
            .overlay {
                GeometryReader { geo in
                    GlyphView(glyph: glyph, size: min(geo.size.width, geo.size.height) * 1.05)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

extension Glyph {
    init(symbolName name: String) {
        let n = name.replacingOccurrences(of: ".fill", with: "")
        switch n {
        case _ where n.contains("shield"): self = .shield
        case _ where n.hasPrefix("checkmark"), "hand.thumbsup": self = .check
        case _ where n.hasPrefix("exclamationmark"), "hand.raised": self = .alert
        case _ where n.hasPrefix("questionmark"): self = .guide
        case _ where n.hasPrefix("xmark"): self = .cross
        case "minus.circle", "minus": self = .minus
        case "slider.horizontal.3", "wrench.and.screwdriver": self = .advanced
        case _ where n.hasPrefix("arrow.triangle.2.circlepath"), "arrow.clockwise": self = .restart
        case _ where n.hasPrefix("puzzlepiece"), "shippingbox": self = .box
        case "cpu", "bolt": self = .bolt
        case "bag", "app.badge": self = .store
        case "chevron.left": self = .back
        case "stop", "stop.circle": self = .stop
        case _ where n.hasPrefix("play"): self = .play
        case "hourglass": self = .wait
        case _ where n.hasPrefix("ellipsis"): self = .more
        case _ where n.hasPrefix("wifi"): self = .offline
        case _ where n.hasPrefix("square.stack"): self = .frames
        case "lock": self = .lock
        case "list.bullet.indent", "list.bullet": self = .list
        case "square.and.arrow.up": self = .export
        case "square.and.arrow.down", "arrow.down.circle", "arrow.down.app": self = .setup
        case "stethoscope": self = .pulse
        case _ where n.hasPrefix("gauge"): self = .balanced
        case _ where n.hasPrefix("battery"): self = .battery
        case "eye": self = .sharp
        case "trash": self = .trash
        case _ where n.hasPrefix("doc"): self = .doc
        case "gamecontroller", "square.grid.2x2": self = .library
        case "laptopcomputer": self = .mac
        case "plus", "plus.circle": self = .add
        default: self = .ring
        }
    }
}

private struct GlyphShape: Shape {
    let glyph: Glyph
    func path(in rect: CGRect) -> Path { glyph.path(in: rect) }
}

extension PlayMode {
    var glyph: Glyph {
        switch self {
        case .batterySaver: return .battery
        case .balanced: return .balanced
        case .sharp: return .sharp
        }
    }
}

// MARK: - Type

/// Small uppercase labels in a monospaced face, as on flake.co.in.
struct Kicker: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(1.4).textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// White capsule, dark text: the one main action on a screen.
struct PrimaryCapsule: ButtonStyle {
    var tint: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(tint == Theme.danger ? Color.white : Theme.onFill)
            .padding(.horizontal, 18).frame(height: 36)
            .background(Capsule().fill(tint).opacity(configuration.isPressed ? 0.8 : 1))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

/// Hairline capsule: the actions beside the main one.
struct GhostCapsule: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .opacity(isEnabled ? 1 : 0.45)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
            .contentShape(Capsule())
    }
}

/// A plain button whose whole area is clickable, including the space between its icon and text, not only what's drawn.
struct FlatButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == FlatButtonStyle {
    static var flat: FlatButtonStyle { FlatButtonStyle() }
}

/// A section that opens and closes when its whole header is clicked: the arrow, the title or the space beside them.
/// (The system disclosure control only responds to its arrow.)
struct Disclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var font: Font = .system(size: 15, weight: .bold)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    GlyphView(glyph: .back, size: 10, weight: 2.2)
                        .rotationEffect(.degrees(isExpanded ? -90 : 180))
                        .foregroundStyle(.secondary)
                    Text(title).font(font)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.flat)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded { content }
        }
    }
}

/// Decoded images, so covers aren't read from disk on every redraw.
@MainActor
enum CoverImages {
    private static var cache: [URL: NSImage] = [:]
    static func image(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let image = cache[url] { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[url] = image
        return image
    }

    private static var blurredCache: [URL: NSImage] = [:]
    /// The image softly blurred, made once with Core Image rather than blurred live on every redraw.
    static func blurred(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let image = blurredCache[url] { return image }
        guard let source = CIImage(contentsOf: url) else { return nil }
        let small = source.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        guard let blurred = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: small.clampedToExtent(), kCIInputRadiusKey: 10])?
            .outputImage?.cropped(to: small.extent),
              let cg = CIContext().createCGImage(blurred, from: small.extent) else { return nil }
        let image = NSImage(cgImage: cg, size: small.extent.size)
        blurredCache[url] = image
        return image
    }
}

/// An item in a menu opened by `popUpMenu`.
struct MenuChoice {
    let title: String
    var enabled = true
    var destructive = false
    var separatorBefore = false
    var checked = false
    /// Shown as a submenu instead of running `action`.
    var children: [MenuChoice] = []
    var action: () -> Void = {}
}

private final class MenuTarget: NSObject {
    let actions: [() -> Void]
    init(_ actions: [() -> Void]) { self.actions = actions }
    @objc func run(_ sender: NSMenuItem) { actions[sender.tag]() }
}

/// Opens a standard menu at the pointer. Used behind Alloy's own buttons, since SwiftUI menus on macOS draw
/// themselves as system buttons whatever style they are given.
@MainActor
func popUpMenu(_ choices: [MenuChoice]) {
    var actions: [() -> Void] = []
    func build(_ choices: [MenuChoice]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for choice in choices {
            if choice.separatorBefore { menu.addItem(.separator()) }
            let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            item.isEnabled = choice.enabled
            item.state = choice.checked ? .on : .off
            if choice.destructive {
                item.attributedTitle = NSAttributedString(string: choice.title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            if choice.children.isEmpty {
                item.action = #selector(MenuTarget.run(_:))
                item.tag = actions.count
                actions.append(choice.action)
            } else {
                item.submenu = build(choice.children)
            }
            menu.addItem(item)
        }
        return menu
    }
    let menu = build(choices)
    let target = MenuTarget(actions)
    func assign(_ menu: NSMenu) {
        for item in menu.items {
            if item.action != nil { item.target = target }
            if let submenu = item.submenu { assign(submenu) }
        }
    }
    assign(menu)
    withExtendedLifetime(target) { _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
}

// MARK: - Top bar

/// Centres the window's close, minimise and zoom buttons in Alloy's taller top bar. AppKit puts them back on every
/// layout pass, so this repeats after resizing, focus changes and leaving full screen. (A window toolbar would centre
/// them too, but it takes the clicks meant for the tabs underneath.)
struct WindowChrome: NSViewRepresentable {
    static let barHeight: CGFloat = 52
    /// Room for the window buttons, with the same gap after them as before them.
    static let leadingInset: CGFloat = 92

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { TrafficLights.shared.attach(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { TrafficLights.shared.position(window) } }
    }
}

@MainActor
final class TrafficLights: NSObject {
    static let shared = TrafficLights()
    private var attached = Set<ObjectIdentifier>()

    func attach(_ window: NSWindow) {
        position(window)
        guard attached.insert(ObjectIdentifier(window)).inserted else { return }
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                          NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                          NSWindow.didExitFullScreenNotification, NSWindow.didBecomeMainNotification]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { TrafficLights.shared.position(window) } }
            }
        }
    }

    func position(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview else { return }
        let height = WindowChrome.barHeight
        var frame = container.frame
        if frame.height != height {
            frame.origin.y = window.frame.height - height
            frame.size.height = height
            container.frame = frame
            titlebar.frame = container.bounds
        }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let size = button.frame.size
            let origin = NSPoint(x: 20 + CGFloat(index) * (size.width + 8),
                                 y: titlebar.isFlipped ? (height - size.height) / 2 : (height - size.height) / 2)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Namespace private var tabs

    private let items: [SidebarItem] = [.library, .setup, .advanced]

    var body: some View {
        HStack(spacing: 0) {
            // Leaves room for the window buttons.
            Color.clear.frame(width: WindowChrome.leadingInset, height: 1)

            Spacer(minLength: 24)

            HStack(spacing: 30) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    tab(item, index: index)
                }
            }

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                UpdatePill()
                EnginePill()
                AddGameMenu()
            }
            .padding(.trailing, 18)
        }
        .frame(height: WindowChrome.barHeight)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func tab(_ item: SidebarItem, index: Int) -> some View {
        let selected = (model.selection ?? .library) == item
        return Button { model.selection = item } label: {
            HStack(spacing: 6) {
                Text(item.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                if item == .setup, model.setupStepsLeft > 0 {
                    Text("\(model.setupStepsLeft)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.onFill)
                        .frame(minWidth: 16, minHeight: 16).background(Circle().fill(Theme.warning))
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(height: WindowChrome.barHeight)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule().fill(Theme.accent).frame(height: 2).matchedGeometryEffect(id: "underline", in: tabs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.flat)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .animation(.smooth(duration: 0.25), value: selected)
    }
}

/// Whether games can be played yet, with a link to Setup when not.
private struct EnginePill: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let ready = model.setupStepsLeft == 0
        Button { model.selection = .setup } label: {
            HStack(spacing: 7) {
                Circle().fill(ready ? Theme.success : Theme.warning).frame(width: 7, height: 7)
                Text(ready ? "Ready" : !model.rosettaInstalled ? "Rosetta needed" : "Engine needed")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12).frame(height: 28)
            .overlay(Capsule().strokeBorder(Theme.hairline))
        }
        .buttonStyle(.flat)
        .help(ready ? "The game engine is installed" : "Open Setup to finish installing")
    }
}

private struct UpdatePill: View {
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let release = updater.available {
            Button { openWindow(id: "updates") } label: {
                Text("Update to \(release.version)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.onFill)
                    .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.flat)
        }
    }
}

// MARK: - Covers

/// A game's box art: its own artwork or Steam's, else a typeset cover made from its name.
struct CoverArtView: View {
    let images: CoverArt.Images
    let name: String
    var isStore = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let image = CoverImages.image(images.portrait) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    TypesetCover(name: name, isStore: isStore, width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// A cover for games without artwork: the name set large over a deep tone picked from it, like a designed box.
struct TypesetCover: View {
    let name: String
    var isStore = false
    let width: CGFloat

    var body: some View {
        let tone = Self.tone(for: name)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [tone.opacity(0.95), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
            // A large, cropped first letter as texture.
            Text(String(name.first ?? "A").uppercased())
                .font(.system(size: width * 1.1, weight: .black))
                .foregroundStyle(.white.opacity(0.06))
                .offset(x: width * 0.28, y: -width * 0.25)
            VStack(alignment: .leading, spacing: 6) {
                if isStore { GlyphView(glyph: .store, size: width * 0.16).foregroundStyle(.white.opacity(0.8)) }
                Text(name)
                    .font(.system(size: max(13, width * 0.12), weight: .heavy))
                    .tracking(-0.3).lineLimit(3).minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
            }
            .padding(width * 0.08)
        }
    }

    /// Deep tones, picked from the name so a game keeps its cover.
    static let tones: [Color] = [
        Color(red: 0.23, green: 0.25, blue: 0.30), Color(red: 0.28, green: 0.24, blue: 0.22), Color(red: 0.20, green: 0.27, blue: 0.27),
        Color(red: 0.27, green: 0.22, blue: 0.29), Color(red: 0.24, green: 0.24, blue: 0.24), Color(red: 0.30, green: 0.26, blue: 0.20),
    ]
    static func tone(for name: String) -> Color {
        tones[name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % tones.count]
    }
}

/// One game on the shelf: portrait cover, name and mode underneath.
struct CoverCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var hovering = false

    var body: some View {
        let running = model.state(of: game.id).isRunning
        VStack(alignment: .leading, spacing: 9) {
            CoverArtView(images: model.cover(for: game), name: game.name)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.5 : 0.08), lineWidth: hovering ? 1.5 : 1))
                .overlay(alignment: .bottomTrailing) {
                    if hovering && !running {
                        Button { model.requestLaunch(game) } label: {
                            GlyphView(glyph: .play, size: 13).foregroundStyle(Theme.onFill)
                                .frame(width: 38, height: 38).background(Circle().fill(Theme.accent))
                        }
                        .buttonStyle(.flat).padding(10).transition(.scale.combined(with: .opacity))
                        .help("Play \(game.name)")
                    }
                }
                .overlay(alignment: .topLeading) {
                    if running {
                        HStack(spacing: 5) { Circle().fill(Theme.success).frame(width: 6, height: 6); Text("PLAYING") }
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(.black.opacity(0.7))).padding(8)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.5 : 0.3), radius: hovering ? 16 : 8, y: hovering ? 10 : 4)
                .offset(y: hovering ? -3 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.8)
                    .textCase(.uppercase).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.18), value: hovering)
    }

    var subtitle: String {
        let mode = game.graphics.backend.isCompatibilityMode ? "Compatibility"
            : PlayMode.current(of: game.graphics)?.displayName ?? "Custom"
        return GameStore.store(for: game).map { "\(mode) · \($0.displayName)" } ?? mode
    }
}

/// A game store's app (Steam, Epic…) in the Stores row: smaller, square.
struct StoreTile: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            GlyphView(glyph: game.isApp ? .doc : .store, size: 18).frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(model.state(of: game.id).isRunning ? "Open" : game.isApp ? "Windows app" : "Game store")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(hovering ? 0.07 : 0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .onHover { hovering = $0 }
    }
}

// MARK: - Spotlight and game hero

/// A wide banner: the game's Steam hero art, or its cover enlarged and blurred, darkened towards the text.
struct HeroBackdrop: View {
    let images: CoverArt.Images
    let name: String

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = CoverImages.image(images.hero) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else if let image = CoverImages.blurred(images.portrait) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).opacity(0.75)
                } else {
                    LinearGradient(colors: [TypesetCover.tone(for: name), Theme.canvas], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
                LinearGradient(colors: [Theme.canvas.opacity(0.95), Theme.canvas.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, Theme.canvas], startPoint: .center, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// Alloy's name and icon, at the top of the library under the bar. Opens the Flake page.
struct Wordmark: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.selection = .flake } label: {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 24, height: 24)
                Text("ALLOY").font(.system(size: 13, weight: .heavy)).tracking(3.5)
                Text("by Flake").font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.flat)
        .help("About Flake")
    }
}

/// The game to pick up again, large, at the top of the library.
struct Spotlight: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        let images = model.cover(for: game)
        let running = model.state(of: game.id).isRunning
        ZStack(alignment: .bottomLeading) {
            HeroBackdrop(images: images, name: game.name)
            HStack(alignment: .bottom, spacing: 28) {
                CoverArtView(images: images, name: game.name)
                    .frame(width: 132, height: 198)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(text: game.isApp ? (running ? "Open now" : "Windows app") : running ? "Playing now" : game.lastPlayed == nil ? "Ready to play" : "Continue playing")
                    Text(game.name).font(.system(size: 40, weight: .heavy)).tracking(-1).lineLimit(2)
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if running {
                            Button { model.stop(game) } label: { Label { Text("Stop") } icon: { GlyphView(glyph: .stop, size: 11) } }
                                .buttonStyle(PrimaryCapsule(tint: Theme.danger))
                        } else {
                            Button { model.requestLaunch(game) } label: { Label { Text(game.isApp ? "Open" : "Play") } icon: { GlyphView(glyph: .play, size: 11) } }
                                .buttonStyle(PrimaryCapsule())
                                .disabled(model.preparing.contains(game.id))
                        }
                        Button(game.isApp ? "App Page" : "Game Page") { model.selectedGameID = game.id }.buttonStyle(GhostCapsule())
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36).padding(.bottom, 30)
        }
        .frame(height: 320)
        .overlay(alignment: .topLeading) { Wordmark().padding(.leading, 36).padding(.top, 22) }
    }

    var detail: String {
        let mode = game.graphics.backend.isCompatibilityMode ? "Compatibility mode"
            : PlayMode.current(of: game.graphics).map { "\($0.displayName) graphics" } ?? "Custom graphics"
        guard let played = game.lastPlayed else { return mode }
        return "\(mode) · Last played \(played.formatted(.relative(presentation: .named)))"
    }
}
