import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FileKind: String, Sendable {
    case image, pdf, video, audio, document, folder, other
}

/// One selected item plus cheap metadata. Probing never decodes pixels or media.
public struct FileDescriptor: Hashable, Sendable {
    public let url: URL
    public let contentType: UTType?
    public let byteSize: Int64?
    public var pixelSize: CGSize?
    public var pageCount: Int?
    /// Media duration; filled in Phase 2 (AVFoundation probing).
    public var duration: TimeInterval?

    public init(url: URL, contentType: UTType?, byteSize: Int64? = nil,
                pixelSize: CGSize? = nil, pageCount: Int? = nil, duration: TimeInterval? = nil) {
        self.url = url
        self.contentType = contentType
        self.byteSize = byteSize
        self.pixelSize = pixelSize
        self.pageCount = pageCount
        self.duration = duration
    }

    public var kind: FileKind { Self.kind(of: contentType) }

    public static func kind(of type: UTType?) -> FileKind {
        guard let type else { return .other }
        if type.conforms(to: .folder) || type.conforms(to: .directory) { return .folder }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .rtf)
            || type.identifier == "org.openxmlformats.wordprocessingml.document"
            || type.identifier == "com.microsoft.word.doc" {
            return .document
        }
        return .other
    }

    /// Type and size only (one stat). Enough for slice applicability; used before the wheel opens.
    public static func basic(_ url: URL) -> FileDescriptor {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return FileDescriptor(url: url, contentType: type, byteSize: values?.fileSize.map(Int64.init))
    }

    /// `basic` plus a header-only probe for images (pixel size) and PDFs (page count).
    public static func probe(_ url: URL) -> FileDescriptor {
        var d = basic(url)
        switch d.kind {
        case .image:
            if let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? Int,
               let h = props[kCGImagePropertyPixelHeight] as? Int {
                d.pixelSize = CGSize(width: w, height: h)
            }
        case .pdf:
            d.pageCount = CGPDFDocument(url as CFURL)?.numberOfPages
        default:
            break
        }
        return d
    }
}

public extension Array where Element == FileDescriptor {
    /// "3 images", "2 PDFs", "5 items".
    var summary: String {
        guard let first = first else { return "Nothing selected" }
        let kinds = Set(map(\.kind))
        if kinds.count == 1 {
            let noun: String
            switch first.kind {
            case .image: noun = "image"
            case .pdf: noun = "PDF"
            case .video: noun = "video"
            case .audio: noun = "audio file"
            case .document: noun = "document"
            case .folder: noun = "folder"
            case .other: noun = "file"
            }
            return count == 1 ? first.url.lastPathComponent : "\(count) \(noun)s"
        }
        return "\(count) items"
    }
}
