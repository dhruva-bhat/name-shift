import Testing
@testable import NameShiftCore

@Suite struct HoldTriggerMachineTests {
    func machine(_ key: TriggerKey = .shift) -> HoldTriggerMachine {
        HoldTriggerMachine(settings: TriggerSettings(key: key, holdDuration: 0.45))
    }

    /// Drives the machine to `.open` and returns it.
    func opened(_ key: TriggerKey = .shift) -> HoldTriggerMachine {
        var m = machine(key)
        _ = m.handle(.modifiersChanged(key.required))
        _ = m.handle(.holdTimerFired(generation: 1))
        return m
    }

    @Test func shiftDownSchedulesTimer() {
        var m = machine()
        let out = m.handle(.modifiersChanged(.shift))
        #expect(out.contains(.scheduleHoldTimer(after: 0.45, generation: 1)))
        #expect(m.state == .pending(generation: 1))
    }

    @Test func cleanHoldOpensThenReleaseCommits() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        #expect(m.handle(.holdTimerFired(generation: 1)) == [.holdElapsed])
        #expect(m.handle(.modifiersChanged([])) == [.commit])
        #expect(m.state == .idle)
    }

    @Test func releaseBeforeHoldDoesNotOpen() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        let out = m.handle(.modifiersChanged([]))
        #expect(out.contains(.cancelHoldTimer))
        #expect(m.handle(.holdTimerFired(generation: 1)).isEmpty)  // stale timer ignored
        #expect(m.state == .idle)
    }

    @Test func typingCapitalPoisonsUntilRelease() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        #expect(m.handle(.keyDown(keyCode: 0)).contains(.cancelHoldTimer))
        #expect(m.handle(.holdTimerFired(generation: 1)).isEmpty)
        #expect(m.state == .poisoned)
        _ = m.handle(.modifiersChanged([]))
        #expect(m.state == .idle)
    }

    @Test func shiftClickPoisons() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        _ = m.handle(.mouseDown(onWheel: false))
        #expect(m.state == .poisoned)
        #expect(m.handle(.holdTimerFired(generation: 1)).isEmpty)
    }

    @Test func scrollDuringHoldPoisons() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        _ = m.handle(.scroll)
        #expect(m.state == .poisoned)
    }

    @Test func chordThenReleaseOtherModifierNeverArms() {
        var m = machine()
        _ = m.handle(.modifiersChanged([.command, .shift]))
        #expect(m.state == .poisoned)
        #expect(m.handle(.modifiersChanged(.shift)).isEmpty)  // released ⌘, still poisoned
        #expect(m.state == .poisoned)
    }

    @Test func addingModifierDuringHoldCancels() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        #expect(m.handle(.modifiersChanged([.shift, .command])).contains(.cancelHoldTimer))
        #expect(m.state == .poisoned)
    }

    @Test func escWhileOpenCancels() {
        var m = opened()
        #expect(m.handle(.keyDown(keyCode: HoldTriggerMachine.escapeKeyCode)) == [.cancel(reason: "Esc")])
        #expect(m.handle(.modifiersChanged([])).isEmpty)  // release after Esc must not commit
    }

    @Test func clickOutsideWheelCancels() {
        var m = opened()
        #expect(m.handle(.mouseDown(onWheel: false)) == [.cancel(reason: "click outside the wheel")])
    }

    @Test func clickOnWheelCommitsOnce() {
        var m = opened()
        #expect(m.handle(.mouseDown(onWheel: true)) == [.commit])
        #expect(m.state == .poisoned)
        #expect(m.handle(.modifiersChanged([])).isEmpty)  // releasing Shift afterwards doesn't re-fire
        #expect(m.state == .idle)
    }

    @Test func clickOnWheelPositionDuringHoldStillPoisons() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        _ = m.handle(.mouseDown(onWheel: true))
        #expect(m.state == .poisoned)
    }

    @Test func defaultHoldIs300ms() {
        #expect(TriggerSettings().holdDuration == 0.3)
    }

    @Test func scrollWhileOpenIsIgnoredByMachine() {
        var m = opened()
        #expect(m.handle(.scroll).isEmpty)
        #expect(m.state == .open)
    }

    @Test func gateRejectionPreventsReopenUntilRelease() {
        var m = opened()
        m.dismissWheel()
        #expect(m.state == .poisoned)
        #expect(m.handle(.modifiersChanged([])).isEmpty)
        #expect(m.state == .idle)
    }

    @Test func optionShiftBuildsUpThenCommitsOnPartialRelease() {
        var m = machine(.optionShift)
        #expect(m.handle(.modifiersChanged(.shift)).isEmpty)  // building up
        #expect(m.state == .idle)
        _ = m.handle(.modifiersChanged([.shift, .option]))
        #expect(m.state == .pending(generation: 1))
        _ = m.handle(.holdTimerFired(generation: 1))
        #expect(m.handle(.modifiersChanged(.shift)) == [.commit])
    }

    @Test func plainShiftDoesNotArmOptionShiftTrigger() {
        var m = machine(.optionShift)
        _ = m.handle(.modifiersChanged(.shift))
        #expect(m.handle(.holdTimerFired(generation: 1)).isEmpty)
    }

    @Test func fnTrigger() {
        var m = machine(.fn)
        _ = m.handle(.modifiersChanged(.fn))
        #expect(m.handle(.holdTimerFired(generation: 1)) == [.holdElapsed])
    }

    @Test func generationsIncrease() {
        var m = machine()
        _ = m.handle(.modifiersChanged(.shift))
        _ = m.handle(.modifiersChanged([]))
        let out = m.handle(.modifiersChanged(.shift))
        #expect(out.contains(.scheduleHoldTimer(after: 0.45, generation: 2)))
        #expect(m.handle(.holdTimerFired(generation: 1)).isEmpty)
        #expect(m.handle(.holdTimerFired(generation: 2)) == [.holdElapsed])
    }

    @Test func holdDurationIsClamped() {
        #expect(TriggerSettings(holdDuration: 0.05).holdDuration == 0.2)
        #expect(TriggerSettings(holdDuration: 5).holdDuration == 0.8)
    }
}
