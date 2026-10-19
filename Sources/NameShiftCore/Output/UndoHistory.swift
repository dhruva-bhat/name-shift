import Combine
import Foundation

/// In-memory list of finished jobs' outputs. Undo moves the last job's outputs to the Trash
/// (recoverable — never a hard delete). Persisted history via GRDB arrives in Phase 3.
@MainActor
public final class UndoHistory: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let outputs: [URL]
    }

    @Published public private(set) var entries: [Entry] = []
    public let capacity: Int

    public init(capacity: Int = 20) {
        self.capacity = capacity
    }

    public var last: Entry? { entries.last }

    public func record(id: UUID, title: String, outputs: [URL]) {
        guard !outputs.isEmpty else { return }
        entries.append(Entry(id: id, title: title, outputs: outputs))
        if entries.count > capacity { entries.removeFirst() }
    }

    /// Returns the URLs that were moved to the Trash.
    @discardableResult
    public func undoLast(fileManager: FileManager = .default) throws -> [URL] {
        guard let entry = entries.popLast() else { return [] }
        var trashed: [URL] = []
        for url in entry.outputs where fileManager.fileExists(atPath: url.path) {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            trashed.append(url)
        }
        return trashed
    }
}
