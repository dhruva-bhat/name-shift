import Foundation

/// One thing the wheel can do to a selection. Actions are pure engine types: no UI.
public protocol FileAction: Sendable {
    var id: String { get }
    var title: String { get }
    var symbolName: String { get }
    /// True if the app must confirm input order (merge tray) before `run`.
    var requiresOrdering: Bool { get }

    /// nil if the action applies to `files`; otherwise a short reason shown on the slice.
    func unavailableReason(for files: [FileDescriptor]) -> String?

    func run(on files: [FileDescriptor], progress: @escaping @Sendable (Double) -> Void) async throws -> ActionResult
}

public extension FileAction {
    var requiresOrdering: Bool { false }

    func isApplicable(to files: [FileDescriptor]) -> Bool {
        unavailableReason(for: files) == nil
    }
}
