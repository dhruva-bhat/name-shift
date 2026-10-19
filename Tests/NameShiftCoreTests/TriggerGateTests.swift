import Foundation
import Testing
@testable import NameShiftCore

final class FakeEnvironment: TriggerEnvironment {
    var frontmostBundleID: String? = TriggerGate.finderBundleID
    var isAccessibilityTrusted = true
    var isSecureInputEnabled = false
    var focus: (role: String?, subrole: String?)? = ("AXOutline", nil)
    var selection: Result<[URL], Error> = .success([URL(fileURLWithPath: "/tmp/a.png")])
    private(set) var selectionFetches = 0

    func focusedElementRole() -> (role: String?, subrole: String?)? { focus }
    func fetchSelection() throws -> [URL] {
        selectionFetches += 1
        return try selection.get()
    }
}

@Suite struct TriggerGateTests {
    let gate = TriggerGate()

    @Test func passesWithFinderAndSelection() {
        let env = FakeEnvironment()
        #expect(gate.evaluate(env, paused: false) == .open(selection: [URL(fileURLWithPath: "/tmp/a.png")]))
    }

    @Test func pausedRejectsFirst() {
        let env = FakeEnvironment()
        #expect(gate.evaluate(env, paused: true) == .rejected(.paused))
        #expect(env.selectionFetches == 0)
    }

    @Test func otherAppRejectsWithoutAppleEvent() {
        let env = FakeEnvironment()
        env.frontmostBundleID = "com.apple.Safari"
        #expect(gate.evaluate(env, paused: false) == .rejected(.frontmostNotFinder("com.apple.Safari")))
        #expect(env.selectionFetches == 0)
    }

    @Test func secureInputRejects() {
        let env = FakeEnvironment()
        env.isSecureInputEnabled = true
        #expect(gate.evaluate(env, paused: false) == .rejected(.secureInput))
    }

    @Test func missingAccessibilityRejects() {
        let env = FakeEnvironment()
        env.isAccessibilityTrusted = false
        #expect(gate.evaluate(env, paused: false) == .rejected(.accessibilityMissing))
    }

    @Test func renamingAFileRejects() {
        let env = FakeEnvironment()
        env.focus = ("AXTextField", nil)
        #expect(gate.evaluate(env, paused: false) == .rejected(.textEditing(role: "AXTextField")))
        #expect(env.selectionFetches == 0)
    }

    @Test func searchFieldRejects() {
        let env = FakeEnvironment()
        env.focus = ("AXTextField", "AXSearchField")
        #expect(gate.evaluate(env, paused: false) == .rejected(.textEditing(role: "AXTextField/AXSearchField")))
    }

    @Test func unknownFocusIsAllowed() {
        let env = FakeEnvironment()
        env.focus = nil
        #expect(gate.evaluate(env, paused: false) == .open(selection: [URL(fileURLWithPath: "/tmp/a.png")]))
    }

    @Test func emptySelectionRejects() {
        let env = FakeEnvironment()
        env.selection = .success([])
        #expect(gate.evaluate(env, paused: false) == .rejected(.emptySelection))
    }

    @Test func selectionErrorRejects() {
        let env = FakeEnvironment()
        env.selection = .failure(SelectionError.notAuthorized)
        #expect(gate.evaluate(env, paused: false) == .rejected(.selectionUnavailable("Automation → Finder not granted")))
    }

    @Test func textRoleClassification() {
        #expect(TriggerGate.isTextEditing(role: "AXTextArea", subrole: nil))
        #expect(TriggerGate.isTextEditing(role: "AXComboBox", subrole: nil))
        #expect(!TriggerGate.isTextEditing(role: "AXList", subrole: nil))
        #expect(!TriggerGate.isTextEditing(role: nil, subrole: nil))
    }
}
