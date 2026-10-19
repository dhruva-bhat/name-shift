import AppKit
import SwiftUI

/// Borderless, non-activating panel. Finder stays frontmost and key the whole time; the wheel
/// tracks the pointer and clicks via the event tap. The panel still accepts mouse events so a
/// click on the wheel lands here instead of passing through to Finder as a Shift-click.
final class WheelPanel: NSPanel {
    static let diameter: CGFloat = 300

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the wheel centered on `point`, shifted inward near screen edges so every slice is
    /// reachable. Returns the actual center, which slice math must use.
    func present<Content: View>(_ rootView: Content, at point: NSPoint) -> NSPoint {
        contentView = NSHostingView(rootView: rootView)  // fresh view so the appear animation replays
        let r = Self.diameter / 2
        var center = point
        if let frame = NSScreen.containing(point)?.frame {
            center.x = min(max(center.x, frame.minX + r), frame.maxX - r)
            center.y = min(max(center.y, frame.minY + r), frame.maxY - r)
        }
        setFrame(NSRect(x: center.x - r, y: center.y - r, width: Self.diameter, height: Self.diameter), display: false)
        orderFrontRegardless()
        return center
    }

    func dismiss() {
        orderOut(nil)
        contentView = nil
    }
}

/// Behind-window blur that stays "active" even though our app never is.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Blurred panel background. Offscreen rendering (README images) can't capture a behind-window
/// blur, so it falls back to a solid fill there.
struct PanelBackground: View {
    @Environment(\.snapshotRendering) private var snapshotRendering
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if snapshotRendering {
            Rectangle().fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
        } else {
            VisualEffectBackground()
        }
    }
}

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering README images offscreen.
    var snapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

/// Hosting view that handles the first click even when its (non-activating) window isn't key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
