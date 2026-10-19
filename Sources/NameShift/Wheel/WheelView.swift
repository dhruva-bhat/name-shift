import NameShiftCore
import SwiftUI

/// Pure rendering of WheelViewModel: a ring of sectors, slice 0 at 12 o'clock, clockwise.
struct WheelView: View {
    static let outerRadius: CGFloat = 132
    static let innerRadius: CGFloat = 42  // also the cancel dead zone

    @ObservedObject var model: WheelViewModel
    @State private var appeared: Bool

    /// `animateIn: false` shows the wheel fully open immediately (used for README images).
    init(model: WheelViewModel, animateIn: Bool = true) {
        self.model = model
        _appeared = State(initialValue: !animateIn)
    }

    var body: some View {
        ZStack {
            PanelBackground()
                .frame(width: Self.outerRadius * 2, height: Self.outerRadius * 2)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

            ForEach(Array(model.slices.enumerated()), id: \.element.id) { index, slice in
                let hovered = index == model.hoveredIndex
                SectorShape(start: model.geometry.startAngle(of: index) + 0.015,
                            end: model.geometry.endAngle(of: index) - 0.015,
                            inner: Self.innerRadius + 3, outer: Self.outerRadius - 4)
                    .fill(hovered ? (slice.isEnabled ? Color.accentColor : Color.gray.opacity(0.45)) : Color.primary.opacity(0.04))
                SliceLabel(slice: slice, hovered: hovered)
                    .position(Self.point(angle: model.geometry.centerAngle(of: index),
                                         radius: (Self.innerRadius + Self.outerRadius) / 2 + 4))
            }

            centerHub
        }
        .frame(width: WheelPanel.diameter, height: WheelPanel.diameter)
        .scaleEffect(appeared ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.16, dampingFraction: 0.82)) { appeared = true } }
        .animation(.easeOut(duration: 0.08), value: model.hoveredIndex)
    }

    private var centerHub: some View {
        let hovered = model.hoveredSlice
        return ZStack {
            Circle().fill(Color.primary.opacity(0.08))
            VStack(spacing: 2) {
                Text(hovered?.title ?? model.summary)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(hovered.map { $0.isEnabled ? "release or click to run" : ($0.detail ?? "unavailable") } ?? "release to cancel")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(6)
        }
        .frame(width: Self.innerRadius * 2, height: Self.innerRadius * 2)
    }

    /// Screen point (SwiftUI, y-down) for an angle measured clockwise from 12 o'clock.
    static func point(angle: Double, radius: CGFloat) -> CGPoint {
        let c = WheelPanel.diameter / 2
        return CGPoint(x: c + radius * CGFloat(sin(angle)), y: c - radius * CGFloat(cos(angle)))
    }
}

private struct SliceLabel: View {
    let slice: WheelSlice
    let hovered: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: slice.symbolName)
                .font(.system(size: 17, weight: .medium))
            Text(slice.title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(hovered && slice.isEnabled ? Color.white : Color.primary)
        .opacity(slice.isEnabled ? 1 : 0.35)
        .scaleEffect(hovered ? 1.08 : 1)
    }
}

/// Annular sector built from sampled points (no arc-direction ambiguity in flipped coordinates).
struct SectorShape: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ a: Double, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a))) }
        let steps = 32
        var path = Path()
        path.move(to: point(start, outer))
        for s in 1...steps { path.addLine(to: point(start + (end - start) * Double(s) / Double(steps), outer)) }
        for s in (0...steps).reversed() { path.addLine(to: point(start + (end - start) * Double(s) / Double(steps), inner)) }
        path.closeSubpath()
        return path
    }
}
