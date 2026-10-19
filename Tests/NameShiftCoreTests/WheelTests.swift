import CoreGraphics
import Testing
@testable import NameShiftCore

@Suite struct WheelGeometryTests {
    let g = WheelGeometry(sliceCount: 6, deadZoneRadius: 30)

    @Test func deadZoneMeansCancel() {
        #expect(g.sliceIndex(for: CGVector(dx: 0, dy: 0)) == nil)
        #expect(g.sliceIndex(for: CGVector(dx: 20, dy: 20)) == nil)
    }

    @Test func compassDirections() {
        #expect(g.sliceIndex(for: CGVector(dx: 0, dy: 100)) == 0)    // up
        #expect(g.sliceIndex(for: CGVector(dx: 0, dy: -100)) == 3)   // down
        #expect(g.sliceIndex(for: CGVector(dx: 100, dy: 60)) == 1)   // up-right
        #expect(g.sliceIndex(for: CGVector(dx: -100, dy: 60)) == 5)  // up-left
    }

    @Test func boundaryJustLeftOfTopWrapsToSliceZero() {
        // 29° counter-clockwise from top is still inside slice 0 (±30°).
        let a = -29.0 * .pi / 180
        #expect(g.sliceIndex(for: CGVector(dx: CGFloat(100 * sin(a)), dy: CGFloat(100 * cos(a)))) == 0)
        let b = -31.0 * .pi / 180
        #expect(g.sliceIndex(for: CGVector(dx: CGFloat(100 * sin(b)), dy: CGFloat(100 * cos(b)))) == 5)
    }
}

@MainActor
@Suite struct WheelViewModelTests {
    func model() -> WheelViewModel {
        let vm = WheelViewModel()
        let slices = (0..<6).map { WheelSlice(id: "s\($0)", title: "\($0)", symbolName: "circle", isEnabled: $0 != 2) }
        vm.reset(slices: slices, summary: "", deadZoneRadius: 30)
        return vm
    }

    @Test func pointerChangesReportedOnce() {
        let vm = model()
        #expect(vm.pointerMoved(offset: CGVector(dx: 0, dy: 80)))
        #expect(!vm.pointerMoved(offset: CGVector(dx: 1, dy: 90)))
        #expect(vm.hoveredIndex == 0)
    }

    @Test func releaseInDeadZoneCancels() {
        let vm = model()
        vm.pointerMoved(offset: CGVector(dx: 0, dy: 80))
        vm.pointerMoved(offset: CGVector(dx: 2, dy: 2))
        #expect(vm.commitTarget() == nil)
    }

    @Test func disabledSliceDoesNotCommit() {
        let vm = model()
        vm.pointerMoved(offset: CGVector(dx: 60, dy: -60))  // slice 2
        #expect(vm.hoveredIndex == 2)
        #expect(vm.commitTarget() == nil)
    }

    @Test func mouseWheelStepsAndWraps() {
        let vm = model()
        vm.scrolled(delta: 1, precise: false)
        #expect(vm.hoveredIndex == 0)
        vm.scrolled(delta: -1, precise: false)
        #expect(vm.hoveredIndex == 5)  // wraps backwards past 0
    }

    @Test func trackpadScrollAccumulates() {
        let vm = model()
        #expect(!vm.scrolled(delta: 10, precise: true))
        #expect(vm.scrolled(delta: 20, precise: true))
        #expect(vm.hoveredIndex == 0)
    }
}
