import Combine
import CoreGraphics
import Foundation

/// Hover state for the open wheel. Free of AppKit so it is testable; the app feeds it
/// pointer offsets and scroll deltas and reacts to `hoveredIndex` changes (haptics).
@MainActor
public final class WheelViewModel: ObservableObject {
    @Published public private(set) var slices: [WheelSlice] = []
    @Published public private(set) var hoveredIndex: Int?
    @Published public private(set) var summary: String = ""
    public private(set) var geometry = WheelGeometry(sliceCount: 1)

    /// Points of precise (trackpad) scrolling per one-slice step.
    public var preciseScrollStep: Double = 28
    private var scrollAccumulator: Double = 0

    public init() {}

    public func reset(slices: [WheelSlice], summary: String, deadZoneRadius: CGFloat) {
        self.slices = slices
        self.summary = summary
        geometry = WheelGeometry(sliceCount: max(slices.count, 1), deadZoneRadius: deadZoneRadius)
        hoveredIndex = nil
        scrollAccumulator = 0
    }

    public var hoveredSlice: WheelSlice? { hoveredIndex.map { slices[$0] } }

    /// Returns true if the hovered slice changed.
    @discardableResult
    public func pointerMoved(offset: CGVector) -> Bool {
        guard !slices.isEmpty else { return false }
        return setHovered(geometry.sliceIndex(for: offset))
    }

    /// Secondary input: rotate the selection. `precise` = trackpad pixel deltas,
    /// otherwise each mouse-wheel notch steps one slice.
    @discardableResult
    public func scrolled(delta: Double, precise: Bool) -> Bool {
        guard !slices.isEmpty, delta != 0 else { return false }
        var steps = 0
        if precise {
            scrollAccumulator += delta
            steps = Int(scrollAccumulator / preciseScrollStep)
            scrollAccumulator -= Double(steps) * preciseScrollStep
        } else {
            steps = delta > 0 ? 1 : -1
        }
        guard steps != 0 else { return false }
        let n = slices.count
        let base = hoveredIndex ?? (steps > 0 ? -1 : 0)
        return setHovered(((base + steps) % n + n) % n)
    }

    /// The slice to run on release, or nil to cancel (dead zone or disabled slice).
    public func commitTarget() -> WheelSlice? {
        guard let slice = hoveredSlice, slice.isEnabled else { return nil }
        return slice
    }

    private func setHovered(_ index: Int?) -> Bool {
        guard index != hoveredIndex else { return false }
        hoveredIndex = index
        return true
    }
}
