import Foundation
import NameShiftCore

/// Reads Finder's selection (windows or Desktop) with one Apple Event (`selection as alias list`).
/// NSAppleScript is main-thread only; the script is compiled once and reused. The timeout keeps a
/// busy or hung Finder from blocking the main thread (and the event tap) for the default ~2 minutes.
final class FinderSelectionProvider: SelectionProvider {
    /// Finder doesn't expose the order items were clicked, so merges default to natural sort.
    static let selectionOrderIsMeaningful = false

    private static let source = """
    with timeout of 2 seconds
        tell application id "com.apple.finder" to set theSelection to (get selection as alias list)
    end timeout
    set thePaths to {}
    repeat with anItem in theSelection
        set end of thePaths to POSIX path of anItem
    end repeat
    return thePaths
    """

    private lazy var script: NSAppleScript? = {
        let script = NSAppleScript(source: Self.source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return error == nil ? script : nil
    }()

    func currentSelection() throws -> [URL] {
        guard let script else { throw SelectionError.scriptFailed(code: -1, message: "script failed to compile") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? -1
            if code == -1743 { throw SelectionError.notAuthorized }
            throw SelectionError.scriptFailed(code: code, message: error[NSAppleScript.errorMessage] as? String ?? "")
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { index in
            result.atIndex(index)?.stringValue.map { URL(fileURLWithPath: $0) }
        }
    }
}
