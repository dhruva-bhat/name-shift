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

    public typealias Trash = @Sendable (URL) throws -> Void
    public nonisolated static let systemTrash: Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// Undo the most recent job. Returns the URLs that were moved to the Trash.
    @discardableResult
    public func undoLast(fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
                         trash: Trash = UndoHistory.systemTrash) throws -> [URL] {
        guard let last = entries.last else { return [] }
        return try undo(id: last.id, fileExists: fileExists, trash: trash)
    }

    /// Undo a specific job (e.g. the one the HUD is showing). If some files can't be trashed,
    /// the entry stays with just those files so Undo can be retried, and the first error is thrown.
    @discardableResult
    public func undo(id: UUID, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
                     trash: Trash = UndoHistory.systemTrash) throws -> [URL] {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return [] }
        let entry = entries[index]
        var trashed: [URL] = []
        var remaining: [URL] = []
        var firstError: Error?
        for url in entry.outputs where fileExists(url) {
            do {
                try trash(url)
                trashed.append(url)
            } catch {
                remaining.append(url)
                firstError = firstError ?? error
            }
        }
        if remaining.isEmpty {
            entries.remove(at: index)
        } else {
            entries[index] = Entry(id: entry.id, title: entry.title, outputs: remaining)
        }
        if let firstError { throw firstError }
        return trashed
    }
}
