import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

public enum MergeError: Error, CustomStringConvertible {
    case unreadable(URL)
    case locked(URL)
    case unsupported(URL)
    case writeFailed

    public var description: String {
        switch self {
        case .unreadable(let url): return "Can't open “\(url.lastPathComponent)”"
        case .locked(let url): return "“\(url.lastPathComponent)” is password-protected"
        case .unsupported(let url): return "Can't merge “\(url.lastPathComponent)” into a PDF"
        case .writeFailed: return "Writing the merged PDF failed"
        }
    }
}

/// PDFKit merge of PDFs and images (each image becomes one page at its native point size).
/// Outlines are dropped; qpdf in Phase 2 gives a higher-fidelity path.
public enum PDFMerger {
    public static func merge(_ inputs: [URL], into directory: URL, baseName: String,
                             progress: (Double) -> Void = { _ in }) throws -> URL {
        let output = PDFDocument()
        var sources: [PDFDocument] = []  // keep source documents alive until written

        for (i, url) in inputs.enumerated() {
            try Task.checkCancellation()
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
            switch FileDescriptor.kind(of: type) {
            case .pdf:
                guard let doc = PDFDocument(url: url) else { throw MergeError.unreadable(url) }
                if doc.isLocked { throw MergeError.locked(url) }
                sources.append(doc)
                for index in 0..<doc.pageCount {
                    if let page = doc.page(at: index)?.copy() as? PDFPage {
                        output.insert(page, at: output.pageCount)
                    }
                }
            case .image:
                guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
                    throw MergeError.unreadable(url)
                }
                output.insert(page, at: output.pageCount)
            default:
                throw MergeError.unsupported(url)
            }
            progress(Double(i + 1) / Double(inputs.count) * 0.9)
        }

        try Task.checkCancellation()
        let url = try OutputPolicy.write(in: directory, baseName: baseName, ext: "pdf") { temp in
            guard output.write(to: temp) else { throw MergeError.writeFailed }
        }
        withExtendedLifetime(sources) {}
        progress(1)
        return url
    }
}
