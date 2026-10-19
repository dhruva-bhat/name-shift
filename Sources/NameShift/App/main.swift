import AppKit

// Menu-bar only: LSUIElement in Info.plist hides the Dock icon; .accessory matches it
// when running the bare binary from `swift run`.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
