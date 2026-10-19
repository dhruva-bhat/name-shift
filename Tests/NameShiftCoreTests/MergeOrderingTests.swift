import Foundation
import Testing
@testable import NameShiftCore

@Suite struct MergeOrderingTests {
    let files = ["page 10.pdf", "page 2.pdf", "Page 1.pdf", "appendix.pdf"].map { file($0, .pdf) }

    @Test func naturalSortWhenSelectionOrderUnknown() {
        let names = MergeOrdering.defaultOrder(files, selectionOrderIsMeaningful: false).map(\.url.lastPathComponent)
        #expect(names == ["appendix.pdf", "Page 1.pdf", "page 2.pdf", "page 10.pdf"])
    }

    @Test func selectionOrderKeptWhenMeaningful() {
        let names = MergeOrdering.defaultOrder(files, selectionOrderIsMeaningful: true).map(\.url.lastPathComponent)
        #expect(names == ["page 10.pdf", "page 2.pdf", "Page 1.pdf", "appendix.pdf"])
    }

    @Test func moveForwardAndBack() {
        #expect(MergeOrdering.move([1, 2, 3, 4], from: 0, to: 2) == [2, 3, 1, 4])
        #expect(MergeOrdering.move([1, 2, 3, 4], from: 3, to: 0) == [4, 1, 2, 3])
    }

    @Test func moveClampsAndIgnoresBadSource() {
        #expect(MergeOrdering.move([1, 2, 3], from: 0, to: 99) == [2, 3, 1])
        #expect(MergeOrdering.move([1, 2, 3], from: 2, to: -5) == [3, 1, 2])
        #expect(MergeOrdering.move([1, 2, 3], from: 7, to: 0) == [1, 2, 3])
    }
}
