import Foundation

public enum MergeOrdering {
    /// Selection order when the provider can vouch for it; otherwise Finder-style natural
    /// filename sort ("page 2" before "page 10"). Finder's AppleScript `selection` does not
    /// reliably report click order, so the Finder provider passes `false`.
    public static func defaultOrder(_ files: [FileDescriptor], selectionOrderIsMeaningful: Bool) -> [FileDescriptor] {
        guard !selectionOrderIsMeaningful else { return files }
        return files.sorted { a, b in
            let result = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent)
            if result != .orderedSame { return result == .orderedAscending }
            return a.url.path < b.url.path
        }
    }

    /// Move one element, clamping the destination. Used by the reorder tray.
    public static func move<T>(_ items: [T], from source: Int, to destination: Int) -> [T] {
        guard items.indices.contains(source) else { return items }
        var copy = items
        let item = copy.remove(at: source)
        copy.insert(item, at: min(max(destination, 0), copy.count))
        return copy
    }
}
