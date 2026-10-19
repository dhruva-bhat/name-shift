import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import NameShiftCore

/// Real file round trips through ImageIO and PDFKit in a temp directory.
@Suite struct EngineIntegrationTests {
    func makePNG(in dir: URL, name: String, alpha: Bool) throws -> URL {
        let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: alpha ? 0.5 : 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    func makePDF(in dir: URL, name: String, pages: Int) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for _ in 0..<pages { ctx.beginPDFPage(nil); ctx.endPDFPage() }
        ctx.closePDF()
        return url
    }

    @Test func pngToJPEGWithAlphaKeepsOriginal() throws {
        let tmp = try TempDir()
        let png = try makePNG(in: tmp.url, name: "shot.png", alpha: true)
        let before = try Data(contentsOf: png)
        let out = try ImageConverter.convert(png, to: .jpeg)
        #expect(out.lastPathComponent == "shot.jpg")
        #expect(try Data(contentsOf: png) == before)
        let d = FileDescriptor.probe(out)
        #expect(d.contentType?.conforms(to: .jpeg) == true)
        #expect(d.pixelSize == CGSize(width: 8, height: 4))
    }

    @Test func convertingTwiceDoesNotOverwrite() throws {
        let tmp = try TempDir()
        let png = try makePNG(in: tmp.url, name: "a.png", alpha: false)
        let first = try ImageConverter.convert(png, to: .heic)
        let second = try ImageConverter.convert(png, to: .heic)
        #expect(first.lastPathComponent == "a.heic")
        #expect(second.lastPathComponent == "a 2.heic")
    }

    @Test func unsupportedFormatThrows() throws {
        let tmp = try TempDir()
        let png = try makePNG(in: tmp.url, name: "a.png", alpha: false)
        #expect(throws: ConversionError.self) {
            try ImageConverter.convert(png, to: .webp, writableTypes: ["public.png"])
        }
    }

    @Test func mergePDFsAndImageInOrder() async throws {
        let tmp = try TempDir()
        let a = try makePDF(in: tmp.url, name: "a.pdf", pages: 2)
        let img = try makePNG(in: tmp.url, name: "b.png", alpha: false)
        let c = try makePDF(in: tmp.url, name: "c.pdf", pages: 1)
        let files = [a, img, c].map(FileDescriptor.probe)
        let result = try await MergePDFAction().run(on: files) { _ in }
        let out = try #require(result.outputs.first)
        #expect(out.lastPathComponent == "a merged.pdf")
        let doc = try #require(PDFDocument(url: out))
        #expect(doc.pageCount == 4)
        #expect(doc.page(at: 2)?.bounds(for: .mediaBox).size == CGSize(width: 8, height: 4))  // the image page
    }

    @Test func probeReadsPDFPageCount() throws {
        let tmp = try TempDir()
        let pdf = try makePDF(in: tmp.url, name: "x.pdf", pages: 3)
        #expect(FileDescriptor.probe(pdf).pageCount == 3)
    }
}
