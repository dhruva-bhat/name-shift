import Foundation
import Testing
@testable import NameShiftCore

@Suite struct OutputPolicyTests {
    let dir = URL(fileURLWithPath: "/tmp/x", isDirectory: true)

    @Test func candidateNames() {
        #expect(OutputPolicy.candidateName(baseName: "photo", ext: "png", attempt: 1) == "photo.png")
        #expect(OutputPolicy.candidateName(baseName: "photo", ext: "png", attempt: 2) == "photo 2.png")
        #expect(OutputPolicy.candidateName(baseName: "photo 2", ext: "png", attempt: 2) == "photo 2 2.png")
        #expect(OutputPolicy.candidateName(baseName: "README", ext: "", attempt: 3) == "README 3")
    }

    @Test func uniqueURLSkipsExisting() {
        let taken: Set<String> = ["/tmp/x/a.png", "/tmp/x/a 2.png"]
        let url = OutputPolicy.uniqueURL(in: dir, baseName: "a", ext: "png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "a 3.png")
    }

    @Test func uniqueURLFreeName() {
        let url = OutputPolicy.uniqueURL(in: dir, baseName: "a", ext: "png") { _ in false }
        #expect(url.lastPathComponent == "a.png")
    }

    @Test func writeNeverOverwrites() throws {
        let tmp = try TempDir()
        let existing = tmp.url.appendingPathComponent("a.png")
        try Data("original".utf8).write(to: existing)

        let out1 = try OutputPolicy.write(in: tmp.url, baseName: "a", ext: "png") { try Data("new1".utf8).write(to: $0) }
        let out2 = try OutputPolicy.write(in: tmp.url, baseName: "a", ext: "png") { try Data("new2".utf8).write(to: $0) }

        #expect(out1.lastPathComponent == "a 2.png")
        #expect(out2.lastPathComponent == "a 3.png")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "original")
        #expect(try String(contentsOf: out1, encoding: .utf8) == "new1")
    }

    @Test func fallsBackWhenExclusiveRenameUnsupported() throws {
        let tmp = try TempDir()
        let existing = tmp.url.appendingPathComponent("a.png")
        try Data("original".utf8).write(to: existing)
        // Simulate an exFAT/SMB volume where renamex_np(RENAME_EXCL) returns ENOTSUP.
        let out = try OutputPolicy.write(in: tmp.url, baseName: "a", ext: "png",
                                         exclusiveRename: { _, _ in ENOTSUP }) { try Data("new".utf8).write(to: $0) }
        #expect(out.lastPathComponent == "a 2.png")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "original")
        #expect(try String(contentsOf: out, encoding: .utf8) == "new")
    }

    @Test func failedWriteLeavesNoFilesBehind() throws {
        let tmp = try TempDir()
        #expect(throws: OutputError.self) {
            try OutputPolicy.write(in: tmp.url, baseName: "a", ext: "png",
                                   exclusiveRename: { _, _ in EACCES }) { try Data("x".utf8).write(to: $0) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).isEmpty)
    }

    @Test func writeFailsWhenBodyProducesNothing() throws {
        let tmp = try TempDir()
        #expect(throws: OutputError.self) {
            try OutputPolicy.write(in: tmp.url, baseName: "a", ext: "png") { _ in }
        }
    }
}

struct TempDir {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("NameShiftTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
