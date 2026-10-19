import Foundation

/// Everything the gate needs from the OS, injectable so the gate is unit-testable.
public protocol TriggerEnvironment {
    var frontmostBundleID: String? { get }
    var isAccessibilityTrusted: Bool { get }
    /// True when some app (e.g. a password field) has enabled Secure Event Input.
    var isSecureInputEnabled: Bool { get }
    /// True while any mouse button is down (e.g. mid-drag in Finder).
    var isMouseButtonDown: Bool { get }
    /// AX role/subrole of the focused element inside the frontmost app, or nil if unknown.
    func focusedElementRole() -> (role: String?, subrole: String?)?
    /// Expensive (Apple Event round trip). Only called if every cheaper check passed.
    func fetchSelection() throws -> [URL]
}

public enum GateFailure: Equatable, Sendable, CustomStringConvertible {
    case paused
    case frontmostNotFinder(String?)
    case secureInput
    case mouseButtonHeld
    case accessibilityMissing
    case textEditing(role: String)
    case selectionUnavailable(String)
    case emptySelection

    public var description: String {
        switch self {
        case .paused: return "paused"
        case .frontmostNotFinder(let id): return "frontmost app is \(id ?? "unknown"), not Finder"
        case .secureInput: return "secure input is active"
        case .mouseButtonHeld: return "a mouse button is held (dragging)"
        case .accessibilityMissing: return "Accessibility permission missing (can't check text focus)"
        case .textEditing(let role): return "text editing in Finder (\(role))"
        case .selectionUnavailable(let why): return "couldn't read Finder selection: \(why)"
        case .emptySelection: return "no files selected"
        }
    }
}

public enum GateDecision: Equatable, Sendable {
    case open(selection: [URL])
    case rejected(GateFailure)
}

public struct TriggerGate: Sendable {
    public static let finderBundleID = "com.apple.finder"

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    private static let textSubroles: Set<String> = ["AXSearchField", "AXSecureTextField"]

    public init() {}

    /// Checks run cheapest-first; the Finder Apple Event happens last.
    public func evaluate(_ env: TriggerEnvironment, paused: Bool) -> GateDecision {
        if paused { return .rejected(.paused) }

        let front = env.frontmostBundleID
        guard front == Self.finderBundleID else { return .rejected(.frontmostNotFinder(front)) }

        if env.isSecureInputEnabled { return .rejected(.secureInput) }
        if env.isMouseButtonDown { return .rejected(.mouseButtonHeld) }
        guard env.isAccessibilityTrusted else { return .rejected(.accessibilityMissing) }

        if let focus = env.focusedElementRole(),
           Self.isTextEditing(role: focus.role, subrole: focus.subrole) {
            return .rejected(.textEditing(role: [focus.role, focus.subrole].compactMap { $0 }.joined(separator: "/")))
        }

        let selection: [URL]
        do {
            selection = try env.fetchSelection()
        } catch {
            return .rejected(.selectionUnavailable(String(describing: error)))
        }
        guard !selection.isEmpty else { return .rejected(.emptySelection) }
        return .open(selection: selection)
    }

    public static func isTextEditing(role: String?, subrole: String?) -> Bool {
        if let role, textRoles.contains(role) { return true }
        if let subrole, textSubroles.contains(subrole) { return true }
        return false
    }
}
