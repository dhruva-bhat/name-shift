import Foundation

/// Source of "what the user has selected". Finder now; Mail/browser downloads in Phase 4.
public protocol SelectionProvider {
    func currentSelection() throws -> [URL]
}

public enum SelectionError: Error, CustomStringConvertible {
    case notAuthorized
    case scriptFailed(code: Int, message: String)

    public var description: String {
        switch self {
        case .notAuthorized: return "Automation → Finder not granted"
        case .scriptFailed(let code, let message): return "AppleScript error \(code): \(message)"
        }
    }
}
