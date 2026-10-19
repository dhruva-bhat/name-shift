import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NameShiftCore

func file(_ name: String, _ type: UTType) -> FileDescriptor {
    FileDescriptor(url: URL(fileURLWithPath: "/tmp/\(name)"), contentType: type)
}

@Suite struct ActionRegistryTests {
    // Simulate ImageIO without WebP encoding (true on macOS 14–26).
    let writable: Set<String> = ["public.png", "public.jpeg", "public.heic", "public.avif", "public.tiff"]
    var registry: ActionRegistry { .phase1(writableTypes: writable) }

    func enabled(_ files: [FileDescriptor]) -> Set<String> {
        Set(registry.slices(for: files).filter(\.isEnabled).map(\.id))
    }

    @Test func layoutIsStaticSixSlices() {
        #expect(registry.slices(for: []).count == 6)
        #expect(registry.slices(for: [file("a.pdf", .pdf)]).map(\.id) == registry.slices(for: []).map(\.id))
    }

    @Test func singleHEICCanBecomeOtherFormatsButNotHEIC() {
        let ids = enabled([file("a.heic", .heic)])
        #expect(ids == ["convert.png", "convert.jpeg", "convert.avif"])
    }

    @Test func webpIsDisabledWithReasonWhenNotEncodable() {
        let slice = registry.slices(for: [file("a.png", .png)]).first { $0.id == "convert.webp" }
        #expect(slice?.isEnabled == false)
        #expect(slice?.detail?.contains("libvips") == true)
    }

    @Test func singlePDFHasNothingEnabled() {
        #expect(enabled([file("a.pdf", .pdf)]).isEmpty)
    }

    @Test func twoPDFsCanMerge() {
        #expect(enabled([file("a.pdf", .pdf), file("b.pdf", .pdf)]) == ["merge.pdf"])
    }

    @Test func mixedPDFAndImagesCanMergeAndConvert() {
        let ids = enabled([file("a.pdf", .pdf), file("b.png", .png)])
        #expect(ids.contains("merge.pdf"))
        #expect(ids.contains("convert.jpeg"))
        #expect(!ids.contains("convert.png"))  // the only image is already PNG
    }

    @Test func videoBlocksMerge() {
        let reason = MergePDFAction().unavailableReason(for: [file("a.pdf", .pdf), file("b.mov", .quickTimeMovie)])
        #expect(reason == "Only PDFs and images")
    }

    @Test func registryApplicableFilters() {
        let ids = registry.applicable(for: [file("a.png", .png), file("b.png", .png)]).map(\.id)
        #expect(ids == ["convert.jpeg", "convert.heic", "merge.pdf", "convert.avif"])
    }

    @Test func kindClassification() {
        #expect(file("a.pdf", .pdf).kind == .pdf)
        #expect(file("a.jpg", .jpeg).kind == .image)
        #expect(file("a.mp4", .mpeg4Movie).kind == .video)
        #expect(file("a.m4a", .mpeg4Audio).kind == .audio)
        #expect(file("a.txt", .plainText).kind == .document)
    }
}
