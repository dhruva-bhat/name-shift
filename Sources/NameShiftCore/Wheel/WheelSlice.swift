import Foundation

/// What the wheel draws for one slice. `id` maps back to a FileAction in the registry.
/// `children` is the Phase 2 child ring (e.g. Convert → PNG/JPG/...); unused in Phase 1.
public struct WheelSlice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String
    public let isEnabled: Bool
    /// Why the slice is disabled, shown in the center when hovered.
    public let detail: String?
    public var children: [WheelSlice]

    public init(id: String, title: String, symbolName: String, isEnabled: Bool = true,
                detail: String? = nil, children: [WheelSlice] = []) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.isEnabled = isEnabled
        self.detail = detail
        self.children = children
    }
}
