import AppKit

extension NSScreen {
    /// The screen under `point` (global AppKit coordinates), falling back to the main screen.
    static func containing(_ point: NSPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }
}

extension NSRect {
    /// This rect moved (not resized) so it lies inside `bounds`, keeping `margin` from the edges.
    func clamped(to bounds: NSRect, margin: CGFloat = 0) -> NSRect {
        var r = self
        r.origin.x = Swift.min(Swift.max(r.origin.x, bounds.minX + margin), bounds.maxX - r.width - margin)
        r.origin.y = Swift.min(Swift.max(r.origin.y, bounds.minY + margin), bounds.maxY - r.height - margin)
        return r
    }
}
