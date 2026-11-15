import AlloyCore
import SwiftUI

/// Alloy's mark for a game that is given the Mac's ray tracing hardware (`RayTracing.isOffered`): a light plate with
/// a ray bouncing off a surface, and the words on a dark plate beside it. Black, white and greys only, like the rest
/// of Alloy. It says what Alloy gives the game, not what the game is drawing: the game's own settings turn ray
/// tracing on.
struct RayTracingTag: View {
    enum Size { case compact, full }
    var size: Size = .full

    var body: some View {
        let height: CGFloat = size == .compact ? 18 : 22
        HStack(spacing: 0) {
            RayGlyph()
                .stroke(Theme.onFill, style: StrokeStyle(lineWidth: size == .compact ? 1.3 : 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: size == .compact ? 11 : 13, height: size == .compact ? 8 : 10)
                .frame(width: height + 2, height: height)
                .background(Theme.gradient)
            Text(size == .compact ? "RT" : "RAY TRACING")
                .font(.system(size: size == .compact ? 9.5 : 10.5, weight: .bold, design: .monospaced))
                .tracking(size == .compact ? 1.2 : 1.6)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, size == .compact ? 6 : 9)
                .frame(height: height)
                .background(Color(white: 0.05).opacity(0.94))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        // Keeps its edge on a light cover.
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .fixedSize()
        .help(RayTracing.tagHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ray tracing hardware on")
    }
}

/// A ray coming down to a surface and leaving it again.
struct RayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let hit = CGPoint(x: rect.midX, y: rect.maxY)
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY))
        path.addLine(to: hit)
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
