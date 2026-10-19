import AppKit
import ApplicationServices
import Combine

enum Permission: String, CaseIterable, Identifiable {
    case inputMonitoring, accessibility, automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        case .automation: return "Automation → Finder"
        }
    }

    var explanation: String {
        switch self {
        case .inputMonitoring:
            return "Lets Name Shift notice how long you hold Shift. It only observes timing; it never blocks or changes keystrokes."
        case .accessibility:
            return "Lets Name Shift tell when you're typing in Finder (renaming, search) so the wheel stays out of the way."
        case .automation:
            return "Lets Name Shift ask Finder which files are selected."
        }
    }

    var symbol: String {
        switch self {
        case .inputMonitoring: return "keyboard"
        case .accessibility: return "accessibility"
        case .automation: return "folder.badge.gearshape"
        }
    }

    var settingsURL: URL {
        let anchor: String
        switch self {
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .automation: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

enum PermissionStatus: Equatable {
    case granted, denied, notDetermined, unknown
}

/// Detects, requests, and re-checks the three TCC permissions.
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var status: [Permission: PermissionStatus] = [:]

    var missing: [Permission] { Permission.allCases.filter { status[$0] != .granted } }
    var allGranted: Bool { missing.isEmpty }

    func refresh() {
        status[.inputMonitoring] = CGPreflightListenEventAccess() ? .granted : .denied
        status[.accessibility] = AXIsProcessTrusted() ? .granted : .denied
        DispatchQueue.global(qos: .userInitiated).async {
            let automation = Self.automationStatus(askUser: false)
            DispatchQueue.main.async { self.status[.automation] = automation }
        }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .inputMonitoring:
            // Shows the system prompt the first time only; afterwards, send the user to Settings.
            if !CGRequestListenEventAccess() { openSettings(permission) }
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { openSettings(permission) }
        case .automation:
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.automationStatus(askUser: true)  // blocks while the prompt is up
                DispatchQueue.main.async {
                    self.status[.automation] = result
                    if result == .denied { self.openSettings(.automation) }
                }
            }
        }
        refresh()
    }

    func openSettings(_ permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    nonisolated static func automationStatus(askUser: Bool) -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askUser)
        switch result {
        case noErr: return .granted
        case -1743: return .denied          // errAEEventNotPermitted
        case -1744: return .notDetermined   // errAEEventWouldRequireUserConsent
        default: return .unknown            // e.g. -600: Finder not running
        }
    }
}
