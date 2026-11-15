import AppKit
import SwiftUI

/// Alloy's ray tracing tag over a game as it starts: a clear, click-through panel in the top left corner of the main
/// screen, above the game's window, where the tag arrives (`RayTracingTag`), rests a few seconds and fades out.
/// The panel never becomes key or main and ignores the mouse, so the game keeps every click and key.
///
/// It is timed from the launch, not from the game's first frame, which Alloy can't see: a game that takes longer to
/// open its window shows the tag over its loading screen or misses it.
@MainActor
final class RayTracingOverlay {
    static let shared = RayTracingOverlay()
    private var panel: NSPanel?
    private var showing: Task<Void, Never>?

    /// Shows the tag `delay` seconds from now for `duration` seconds. A second call while one is pending replaces it.
    func show(after delay: Double = 5, for duration: Double = 5.5) {
        showing?.cancel()
        showing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.present()
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self.dismiss()
        }
    }

    private func present() {
        panel?.close()
        guard let screen = NSScreen.main else { return }
        let size = CGSize(width: 320, height: 96)
        // Below the menu bar or the notch, whichever the screen has.
        let top = screen.frame.maxY - max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        let frame = CGRect(x: screen.frame.minX, y: top - size.height, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSHostingView(rootView:
            RayTracingTag(size: .overlay)
                .padding(.leading, 28).padding(.top, 24)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .environment(\.colorScheme, .dark))
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func dismiss() async {
        guard let panel else { return }
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            panel.animator().alphaValue = 0
        }
        panel.close()
        if self.panel === panel { self.panel = nil }
    }
}
