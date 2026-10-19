import AppKit
import NameShiftCore

/// Status-bar icon and menu: status line, missing permissions, pause, undo, windows, quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Actions {
        var showOnboarding: () -> Void
        var showPreferences: () -> Void
        var showDebugLog: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: AppCoordinator
    private let actions: Actions

    init(coordinator: AppCoordinator, actions: Actions) {
        self.coordinator = coordinator
        self.actions = actions
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    func updateIcon() {
        let name: String
        if !coordinator.permissions.allGranted { name = "exclamationmark.circle" }
        else if coordinator.settings.isPaused { name = "pause.circle" }
        else { name = "circle.circle" }
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Name Shift")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        coordinator.permissions.refresh()
        menu.removeAllItems()

        let settings = coordinator.settings
        let missing = coordinator.permissions.missing
        let status: String
        if !missing.isEmpty { status = "Name Shift — needs permissions" }
        else if settings.isPaused { status = "Name Shift — paused" }
        else { status = "Name Shift — hold \(settings.triggerKey.displayName) in Finder" }
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))

        for permission in missing {
            menu.addItem(item("⚠︎ Grant \(permission.title)…") { [actions] in actions.showOnboarding() })
        }
        menu.addItem(.separator())

        let pause = item(settings.isPaused ? "Resume" : "Pause") { [weak self] in
            self?.coordinator.settings.isPaused.toggle()
            self?.updateIcon()
        }
        menu.addItem(pause)

        let undo = item(coordinator.undo.last.map { "Undo “\($0.title)”" } ?? "Undo Last Job") { [weak self] in
            self?.coordinator.undoLast()
        }
        undo.isEnabled = coordinator.undo.last != nil
        menu.addItem(undo)
        menu.addItem(.separator())

        menu.addItem(item("Preferences…", key: ",") { [actions] in actions.showPreferences() })
        menu.addItem(item("Debug Log…") { [actions] in actions.showDebugLog() })
        menu.addItem(item("Permissions…") { [actions] in actions.showOnboarding() })
        menu.addItem(.separator())
        menu.addItem(item("Quit Name Shift", key: "q") { NSApp.terminate(nil) })

        updateIcon()
    }

    private func item(_ title: String, key: String = "", handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
