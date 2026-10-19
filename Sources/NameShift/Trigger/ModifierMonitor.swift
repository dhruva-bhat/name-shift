import AppKit
import NameShiftCore

/// Listen-only CGEventTap. It never modifies or swallows events; it only translates them
/// into TriggerInput for the state machine plus pointer/scroll updates for the open wheel.
final class ModifierMonitor {
    enum Event {
        case trigger(TriggerInput)
        /// Any mouse button down; `primary` = left button.
        case mouseDown(primary: Bool)
        case mouseMoved
        case scroll(delta: Double, precise: Bool)
        /// The system disabled the tap (timeout/user input) and we re-enabled it; we may have
        /// missed flag changes, so the machine must resync from the live modifier state.
        case tapReenabled(ModifierSet)
    }

    var handler: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { tap != nil }

    /// Fails (returns false) when Input Monitoring hasn't been granted.
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: modifierTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            handler?(.tapReenabled(ModifierSet(cgFlags: CGEventSource.flagsState(.combinedSessionState))))
        case .flagsChanged:
            handler?(.trigger(.modifiersChanged(ModifierSet(cgFlags: event.flags))))
        case .keyDown:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            handler?(.trigger(.keyDown(keyCode: code)))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handler?(.mouseDown(primary: type == .leftMouseDown))
        case .scrollWheel:
            let precise = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let field1: CGEventField = precise ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1
            let field2: CGEventField = precise ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2
            // Holding Shift turns a mouse wheel's vertical scroll into horizontal, so use either axis.
            let dy = event.getDoubleValueField(field1)
            let dx = event.getDoubleValueField(field2)
            let delta = abs(dy) >= abs(dx) ? -dy : dx
            handler?(.scroll(delta: delta, precise: precise))
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            handler?(.mouseMoved)
        default:
            break
        }
    }
}

private func modifierTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<ModifierMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)  // ignored for listen-only taps
}
