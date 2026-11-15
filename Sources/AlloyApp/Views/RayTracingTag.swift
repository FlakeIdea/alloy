import AlloyCore
import SwiftUI

/// Alloy's mark for a game that is given the Mac's ray tracing hardware (`RayTracing.isOffered`): the Flake mark in
/// white on a black pill, with "Alloy Ray Tracing" beside it. Black and white only. On a game's page it arrives in
/// three beats: the pill pops up with the mark alone, its feathers landing one after another and the beak last, then
/// the mark moves aside as the words open out. On a cover it is the mark alone and does not move. When such a game
/// starts, the same arrival plays once over the game (`RayTracingOverlay`).
///
/// It says what Alloy gives the game, not what the game is drawing: the game's own settings turn ray tracing on.
struct RayTracingTag: View {
    /// On a cover, on the game's page, and over a game as it starts.
    enum Size { case compact, full, overlay }
    /// The beats of the arrival; the tag rests in `.named`.
    enum Phase: Int, Comparable {
        case hidden, mark, named
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    var size: Size = .full
    /// A fixed beat, for previews; nil plays the arrival (or rests, with Reduce Motion or on a cover).
    var fixed: Phase? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .hidden
    @State private var landed = 0   // how many pieces of the mark have landed (0–4)

    private var shown: Phase { fixed ?? phase }
    private var pieces: Int { fixed.map { $0 == .hidden ? 0 : 4 } ?? landed }

    var body: some View {
        let compact = size == .compact
        let large = size == .overlay
        let height: CGFloat = compact ? 22 : large ? 40 : 28
        let corner: CGFloat = compact ? 6 : large ? 13 : 9
        HStack(spacing: compact ? 0 : large ? 11 : 8) {
            mark.frame(width: compact ? 9 : large ? 16.5 : 11.5, height: compact ? 12.5 : large ? 23 : 16)
            if !compact && shown == .named {
                Text("Alloy Ray Tracing")
                    .font(.system(size: large ? 15.5 : 11.5, weight: .semibold)).tracking(0.2)
                    .foregroundStyle(.white).lineLimit(1).fixedSize()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -6)), removal: .opacity))
            }
        }
        .padding(.horizontal, compact ? 0 : (shown == .named ? (large ? 16 : 11) : 0))
        .frame(minWidth: compact ? height : height + 6, minHeight: height, maxHeight: height)
        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        .scaleEffect(shown == .hidden ? 0.6 : 1, anchor: .leading)
        .opacity(shown == .hidden ? 0 : 1)
        .fixedSize()
        .help(RayTracing.tagHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alloy Ray Tracing: ray tracing hardware on")
        .task { await arrive() }
    }

    /// The Flake mark, piece by piece: three feathers, then the beak.
    private var mark: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { piece in
                FlakeMark(part: piece).fill(.white)
                    .opacity(pieces > piece ? 1 : 0)
                    .offset(y: pieces > piece ? 0 : (piece == 3 ? 3 : -4))
            }
        }
    }

    private func arrive() async {
        guard fixed == nil, phase == .hidden else { return }
        if reduceMotion || size == .compact { landed = 4; phase = .named; return }
        try? await Task.sleep(for: .seconds(0.25))
        withAnimation(.spring(duration: 0.38, bounce: 0.35)) { phase = .mark }
        for piece in 1...4 {
            try? await Task.sleep(for: .seconds(piece == 4 ? 0.14 : 0.09))
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { landed = piece }
        }
        try? await Task.sleep(for: .seconds(0.55))
        withAnimation(.spring(duration: 0.5, bounce: 0.18)) { phase = .named }
    }
}
