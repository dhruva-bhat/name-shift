import AppKit
import SwiftUI

/// Shows (and reuses) the app's few regular windows: onboarding, preferences, debug log.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, floating: Bool = false, resizable: Bool = false,
                             content: () -> Content) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let host = NSHostingController(rootView: content())
        // Size the window from the SwiftUI content; a zero-sized window shows nothing.
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.view.fittingSize),
                              styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = host
        window.isReleasedWhenClosed = false
        if floating {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close(id: String) {
        windows[id]?.close()
    }
}
