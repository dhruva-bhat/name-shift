import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, avif, webp, tiff

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .avif: return UTType("public.avif") ?? .image
        case .webp: return .webP
        case .tiff: return .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }

    public var displayName: String {
        switch self {
        case .jpeg: return "JPG"
        default: return rawValue.uppercased()
        }
    }

    var isLossy: Bool { [.jpeg, .heic, .avif, .webp].contains(self) }
    var supportsAlpha: Bool { self != .jpeg }

    /// UTIs ImageIO can encode on this machine. WebP is decode-only in ImageIO; AVIF
    /// encoding depends on the OS version.
    public static var systemWritableTypes: Set<String> {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }
}

public enum ConversionError: Error, CustomStringConvertible {
    case unreadable(URL)
    case unsupportedOutput(ImageFormat)
    case encodeFailed(URL)

    public var description: String {
        switch self {
        case .unreadable(let url): return "Can't read “\(url.lastPathComponent)” as an image"
        case .unsupportedOutput(let f): return "This Mac can't encode \(f.displayName) natively"
        case .encodeFailed(let url): return "Encoding “\(url.lastPathComponent)” failed"
        }
    }
}

/// Native ImageIO conversion. Copies metadata and orientation; first frame only (Phase 1).
public enum ImageConverter {
    public static func convert(_ source: URL, to format: ImageFormat, quality: Double = 0.9,
                               writableTypes: Set<String> = ImageFormat.systemWritableTypes) throws -> URL {
        guard writableTypes.contains(format.utType.identifier) else { throw ConversionError.unsupportedOutput(format) }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw ConversionError.unreadable(source)
        }
        let sourceProps = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let hasAlpha = (sourceProps[kCGImagePropertyHasAlpha] as? Bool) ?? false

        return try OutputPolicy.write(in: source.deletingLastPathComponent(),
                                      baseName: source.deletingPathExtension().lastPathComponent,
                                      ext: format.fileExtension) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, format.utType.identifier as CFString, 1, nil) else {
                throw ConversionError.unsupportedOutput(format)
            }
            var options: [CFString: Any] = [:]
            if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }

            if hasAlpha && !format.supportsAlpha {
                // JPEG has no alpha; ImageIO would composite onto black. Flatten onto white instead.
                guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                      let flat = flattenOnWhite(image) else { throw ConversionError.unreadable(source) }
                var props = sourceProps
                props.merge(options) { _, new in new }
                CGImageDestinationAddImage(dest, flat, props as CFDictionary)
            } else {
                CGImageDestinationAddImageFromSource(dest, src, 0, options as CFDictionary)
            }
            guard CGImageDestinationFinalize(dest) else { throw ConversionError.encodeFailed(source) }
        }
    }

    static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
