import Foundation

/// Merge PDFs and/or images into one PDF, in the order the user confirmed in the tray.
/// (The "common target" rule for audio/video lands with the Phase 2 registry.)
public struct MergePDFAction: FileAction {
    public init() {}

    public var id: String { "merge.pdf" }
    public var title: String { "Merge → PDF" }
    public var symbolName: String { "doc.on.doc" }
    public var requiresOrdering: Bool { true }

    static let mergeableKinds: Set<FileKind> = [.pdf, .image]

    public func unavailableReason(for files: [FileDescriptor]) -> String? {
        guard files.count >= 2 else { return "Select 2+ PDFs or images" }
        guard files.allSatisfy({ Self.mergeableKinds.contains($0.kind) }) else { return "Only PDFs and images" }
        return nil
    }

    public func run(on files: [FileDescriptor], progress: @escaping @Sendable (Double) -> Void) async throws -> ActionResult {
        guard let first = files.first else { return ActionResult(outputs: []) }
        let base = first.url.deletingPathExtension().lastPathComponent + " merged"
        let url = try PDFMerger.merge(files.map(\.url), into: first.url.deletingLastPathComponent(),
                                      baseName: base, progress: progress)
        return ActionResult(outputs: [url])
    }
}
