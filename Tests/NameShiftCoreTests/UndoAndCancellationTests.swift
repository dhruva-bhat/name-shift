import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NameShiftCore

struct TrashFailure: Error {}

@MainActor
@Suite struct UndoHistoryTests {
    let a = URL(fileURLWithPath: "/tmp/a.png")
    let b = URL(fileURLWithPath: "/tmp/b.png")
    let c = URL(fileURLWithPath: "/tmp/c.png")

    @Test func undoSpecificJobLeavesOthers() throws {
        let history = UndoHistory()
        let first = UUID(), second = UUID()
        history.record(id: first, title: "one", outputs: [a])
        history.record(id: second, title: "two", outputs: [b])
        var trashed: [URL] = []
        try history.undo(id: first, fileExists: { _ in true }, trash: { _ in })
        #expect(history.entries.map(\.id) == [second])
        trashed = try history.undoLast(fileExists: { _ in true }, trash: { _ in })
        #expect(trashed == [b])
        #expect(history.entries.isEmpty)
    }

    @Test func partialTrashFailureKeepsRemainingFiles() {
        let history = UndoHistory()
        let id = UUID()
        history.record(id: id, title: "job", outputs: [a, b, c])
        let failing = b
        #expect(throws: TrashFailure.self) {
            try history.undoLast(fileExists: { _ in true }, trash: { if $0 == failing { throw TrashFailure() } })
        }
        #expect(history.entries.count == 1)
        #expect(history.entries.first?.outputs == [b])  // retryable
    }

    @Test func missingFilesAreSkipped() throws {
        let history = UndoHistory()
        history.record(id: UUID(), title: "job", outputs: [a, b])
        let trashed = try history.undoLast(fileExists: { $0 == a }, trash: { _ in })
        #expect(trashed == [a])
        #expect(history.entries.isEmpty)
    }
}

@Suite struct CancellationTests {
    @Test func convertCancelledBeforeAnyOutputThrowsCancellation() async {
        let action = ConvertImageAction(format: .jpeg, writableTypes: ["public.jpeg"])
        let files = [FileDescriptor(url: URL(fileURLWithPath: "/tmp/nope.png"), contentType: .png)]
        let task = Task { try await action.run(on: files) { _ in } }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func basicDescriptorSkipsProbe() throws {
        let tmp = try TempDir()
        let url = tmp.url.appendingPathComponent("x.pdf")
        var box = CGRect(x: 0, y: 0, width: 10, height: 10)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
        let basic = FileDescriptor.basic(url)
        #expect(basic.kind == .pdf)
        #expect(basic.pageCount == nil)
        #expect(FileDescriptor.probe(url).pageCount == 1)
    }
}
