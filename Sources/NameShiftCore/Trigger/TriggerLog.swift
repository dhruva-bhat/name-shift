import Combine
import Foundation
import os

/// Ring buffer of trigger decisions, shown in the Debug Log window and mirrored to
/// the unified log (`log stream --predicate 'subsystem == "NameShift"'`).
@MainActor
public final class TriggerLog: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public enum Kind: Sendable { case info, pass, fail }
        public let id = UUID()
        public let date: Date
        public let kind: Kind
        public let message: String
    }

    @Published public private(set) var entries: [Entry] = []
    public let capacity: Int
    private let logger = Logger(subsystem: "NameShift", category: "trigger")

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    public func info(_ message: String) { append(.info, message) }
    public func pass(_ message: String) { append(.pass, message) }
    public func fail(_ message: String) { append(.fail, message) }

    public func clear() { entries.removeAll() }

    public var plainText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { e in
            let tag = switch e.kind { case .info: "   "; case .pass: "OK "; case .fail: "NO " }
            return "\(f.string(from: e.date)) \(tag) \(e.message)"
        }.joined(separator: "\n")
    }

    private func append(_ kind: Entry.Kind, _ message: String) {
        entries.append(Entry(date: Date(), kind: kind, message: message))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        switch kind {
        case .fail: logger.notice("\(message, privacy: .public)")
        default: logger.info("\(message, privacy: .public)")
        }
    }
}
