import AppKit

// Menu-bar only: LSUIElement in Info.plist hides the Dock icon; .accessory matches it
// when running the bare binary from `swift run`.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    #if DEBUG
    // Dev-only hook for scripts/render-readme-images.sh; not compiled into release builds.
    if ReadmeImages.renderIfRequested() { exit(0) }
    #endif
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
