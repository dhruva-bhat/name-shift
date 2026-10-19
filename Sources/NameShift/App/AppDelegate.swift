import AppKit

/// Lifecycle: builds the coordinator and menu bar, shows onboarding when permissions are
/// missing, and keeps re-checking permissions so the tap starts as soon as it's allowed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var menuBar: MenuBarController!
    private let windows = WindowPresenter()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator(settings: SettingsStore())
        menuBar = MenuBarController(coordinator: coordinator, actions: .init(
            showOnboarding: { [weak self] in self?.showOnboarding() },
            showPreferences: { [weak self] in self?.showPreferences() },
            showDebugLog: { [weak self] in self?.showDebugLog() }
        ))
        coordinator.start()
        coordinator.permissions.refresh()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        // Give the async Automation check a moment before deciding to show onboarding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.coordinator.permissions.allGranted else { return }
            self.showOnboarding()
        }
    }

    private func recheckPermissions() {
        coordinator.permissions.refresh()
        if CGPreflightListenEventAccess() { coordinator.startMonitorIfPossible() }
        menuBar.updateIcon()
    }

    private func showOnboarding() {
        windows.show(id: "onboarding", title: "Name Shift Permissions") {
            PermissionsView(permissions: coordinator.permissions) { [weak self] in
                self?.windows.close(id: "onboarding")
            }
        }
    }

    private func showPreferences() {
        windows.show(id: "prefs", title: "Name Shift Preferences") {
            PrefsView(settings: coordinator.settings)
        }
    }

    private func showDebugLog() {
        windows.show(id: "debug", title: "Name Shift Debug Log", floating: true, resizable: true) {
            DebugLogView(log: coordinator.log)
        }
    }
}
