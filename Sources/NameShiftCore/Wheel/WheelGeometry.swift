import CoreGraphics
import Foundation

/// Angle → slice math. Angles are radians clockwise from 12 o'clock; slice 0 is centered at
/// the top. Offsets use AppKit screen orientation (dx right, dy up).
public struct WheelGeometry: Equatable, Sendable {
    public var sliceCount: Int
    public var deadZoneRadius: CGFloat

    public init(sliceCount: Int, deadZoneRadius: CGFloat = 36) {
        precondition(sliceCount > 0)
        self.sliceCount = sliceCount
        self.deadZoneRadius = deadZoneRadius
    }

    public var sliceWidth: Double { 2 * .pi / Double(sliceCount) }

    /// Clockwise angle from straight up, in [0, 2π).
    public static func angle(of offset: CGVector) -> Double {
        let a = atan2(Double(offset.dx), Double(offset.dy))
        return a < 0 ? a + 2 * .pi : a
    }

    /// nil inside the dead zone (which means "cancel").
    public func sliceIndex(for offset: CGVector) -> Int? {
        let distance = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot()
        guard distance >= deadZoneRadius else { return nil }
        let shifted = Self.angle(of: offset) + sliceWidth / 2
        return Int(floor(shifted / sliceWidth)) % sliceCount
    }

    public func centerAngle(of index: Int) -> Double { Double(index) * sliceWidth }
    public func startAngle(of index: Int) -> Double { centerAngle(of: index) - sliceWidth / 2 }
    public func endAngle(of index: Int) -> Double { centerAngle(of: index) + sliceWidth / 2 }
}
