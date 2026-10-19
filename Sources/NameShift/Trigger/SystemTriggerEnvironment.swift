import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NameShiftCore

/// Real-OS implementation of the gate's inputs.
struct SystemTriggerEnvironment: TriggerEnvironment {
    let selectionProvider: SelectionProvider

    var frontmostBundleID: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }

    /// Role of the focused element in the frontmost app (e.g. AXTextField while renaming a file).
    func focusedElementRole() -> (role: String?, subrole: String?)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        return (Self.string(element, kAXRoleAttribute), Self.string(element, kAXSubroleAttribute))
    }

    func fetchSelection() throws -> [URL] {
        try selectionProvider.currentSelection()
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
