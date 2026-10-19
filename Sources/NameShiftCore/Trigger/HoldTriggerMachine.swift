import Foundation

/// Raw input the event tap feeds into the machine. Mouse movement is not an input:
/// small hand jitter must never cancel a pending trigger.
public enum TriggerInput: Equatable, Sendable {
    case modifiersChanged(ModifierSet)
    case keyDown(keyCode: UInt16)
    /// `onWheel`: a primary click inside the open wheel's circle (fires the slice under it).
    case mouseDown(onWheel: Bool)
    /// Pointer moved with a button held (marquee selection, file drag).
    case mouseDragged
    case scroll
    case holdTimerFired(generation: Int)
}

public enum TriggerOutput: Equatable, Sendable {
    case scheduleHoldTimer(after: TimeInterval, generation: Int)
    case cancelHoldTimer
    /// Hold elapsed cleanly. The app must now run the TriggerGate, then either show the
    /// wheel or call `dismissWheel()`.
    case holdElapsed
    /// Trigger released, or wheel clicked, while open: fire the hovered slice.
    case commit
    /// Wheel was open and got cancelled (Esc, other key, click, extra modifier).
    case cancel(reason: String)
    /// Diagnostic line for the debug log; no behavior attached.
    case note(String)
}

/// Pure state machine for "hold the trigger modifier alone for N ms".
///
/// Rules:
/// - Arms only when the trigger modifiers are held with no other modifier, and the user
///   reached that state by pressing only trigger keys (so Cmd+Shift → release Cmd never arms).
/// - Any key press, click, or scroll during the hold poisons the gesture until every
///   modifier is released (Shift-click multi-select and typing capitals never open the wheel).
/// - While open: releasing a trigger key or clicking on the wheel commits; any other
///   input (Esc, typing, clicking outside the wheel) cancels.
public struct HoldTriggerMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case pending(generation: Int)
        case open
        /// Something disqualified this press; wait until all modifiers are released.
        case poisoned
    }

    public static let escapeKeyCode: UInt16 = 53

    public private(set) var state: State = .idle
    public var settings: TriggerSettings
    private var generation = 0

    public init(settings: TriggerSettings) {
        self.settings = settings
    }

    public mutating func handle(_ input: TriggerInput) -> [TriggerOutput] {
        let required = settings.key.required
        switch (state, input) {

        // MARK: idle
        case (.idle, .modifiersChanged(let mods)):
            if mods == required {
                generation += 1
                state = .pending(generation: generation)
                return [.scheduleHoldTimer(after: settings.holdDuration, generation: generation),
                        .note("\(mods) down — waiting \(Int(settings.holdDuration * 1000)) ms")]
            }
            if mods.isSubset(of: required) { return [] }  // building up a combo, or all released
            state = .poisoned
            return []

        // MARK: pending
        case (.pending, .modifiersChanged(let mods)):
            if mods == required { return [] }
            if mods.isSubset(of: required) {
                state = .idle
                return [.cancelHoldTimer, .note("released before hold elapsed")]
            }
            state = .poisoned
            return [.cancelHoldTimer, .note("cancelled: another modifier pressed (\(mods))")]

        case (.pending, .keyDown(let code)):
            state = .poisoned
            return [.cancelHoldTimer, .note("cancelled: key \(code) pressed during hold")]

        case (.pending, .mouseDown):  // Shift-click multi-select
            state = .poisoned
            return [.cancelHoldTimer, .note("cancelled: mouse click during hold (Shift-click?)")]

        case (.pending, .mouseDragged):
            state = .poisoned
            return [.cancelHoldTimer, .note("cancelled: mouse drag during hold")]

        case (.pending, .scroll):
            state = .poisoned
            return [.cancelHoldTimer, .note("cancelled: scroll during hold")]

        case (.pending(let gen), .holdTimerFired(let fired)):
            guard gen == fired else { return [] }
            state = .open
            return [.holdElapsed]

        // MARK: open
        case (.open, .modifiersChanged(let mods)):
            if mods == required { return [] }
            if mods.isSubset(of: required) {
                state = .idle
                return [.commit]
            }
            state = .poisoned
            return [.cancel(reason: "another modifier pressed (\(mods))")]

        case (.open, .keyDown(let code)):
            state = .poisoned
            return [.cancel(reason: code == Self.escapeKeyCode ? "Esc" : "key \(code) pressed")]

        case (.open, .mouseDown(let onWheel)):
            // Poisoned either way, so the later Shift release doesn't fire a second time.
            state = .poisoned
            return onWheel ? [.commit] : [.cancel(reason: "click outside the wheel")]

        case (.open, .mouseDragged):
            state = .poisoned
            return [.cancel(reason: "mouse drag")]

        case (.open, .scroll):
            return []  // scroll rotates the ring; handled by the wheel view model

        // MARK: poisoned
        case (.poisoned, .modifiersChanged(let mods)):
            if mods.isEmpty { state = .idle }
            return []

        default:
            return []  // stale timers, keys while idle, etc.
        }
    }

    /// Called when the gate rejects after `.holdElapsed`, so the press can't re-arm.
    public mutating func dismissWheel() {
        if state == .open { state = .poisoned }
    }

    /// Called on pause or when the tap is re-enabled after the system disabled it.
    public mutating func reset(currentModifiers: ModifierSet) -> [TriggerOutput] {
        let hadTimer: Bool
        if case .pending = state { hadTimer = true } else { hadTimer = false }
        state = currentModifiers.isEmpty ? .idle : .poisoned
        return hadTimer ? [.cancelHoldTimer] : []
    }
}
