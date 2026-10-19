import Foundation

/// Phase 1: a fixed 6-slice layout. Slices that don't apply to the selection are shown
/// disabled (with the reason) rather than hidden, so the layout stays stable while tuning
/// the interaction. Phase 2 swaps this for context-aware `applicable(for:)` layouts.
public struct ActionRegistry: Sendable {
    public let actions: [any FileAction]

    public init(actions: [any FileAction]) {
        self.actions = actions
    }

    public static func phase1(writableTypes: Set<String> = ImageFormat.systemWritableTypes) -> ActionRegistry {
        ActionRegistry(actions: [
            ConvertImageAction(format: .png, writableTypes: writableTypes),
            ConvertImageAction(format: .jpeg, writableTypes: writableTypes),
            ConvertImageAction(format: .heic, writableTypes: writableTypes),
            MergePDFAction(),
            ConvertImageAction(format: .webp, writableTypes: writableTypes),
            ConvertImageAction(format: .avif, writableTypes: writableTypes),
        ])
    }

    public func action(id: String) -> (any FileAction)? {
        actions.first { $0.id == id }
    }

    public func applicable(for files: [FileDescriptor]) -> [any FileAction] {
        actions.filter { $0.isApplicable(to: files) }
    }

    public func slices(for files: [FileDescriptor]) -> [WheelSlice] {
        actions.map { action in
            let reason = action.unavailableReason(for: files)
            return WheelSlice(id: action.id, title: action.title, symbolName: action.symbolName,
                              isEnabled: reason == nil, detail: reason)
        }
    }
}
