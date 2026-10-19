import CoreGraphics
import Foundation

/// The modifier keys the trigger cares about. Caps Lock is deliberately excluded.
public struct ModifierSet: OptionSet, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = ModifierSet(rawValue: 1 << 0)
    public static let control = ModifierSet(rawValue: 1 << 1)
    public static let option = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
    public static let fn = ModifierSet(rawValue: 1 << 4)

    public init(cgFlags: CGEventFlags) {
        var set: ModifierSet = []
        if cgFlags.contains(.maskShift) { set.insert(.shift) }
        if cgFlags.contains(.maskControl) { set.insert(.control) }
        if cgFlags.contains(.maskAlternate) { set.insert(.option) }
        if cgFlags.contains(.maskCommand) { set.insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { set.insert(.fn) }
        self = set
    }

    public var description: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        if contains(.fn) { parts.append("fn") }
        return parts.isEmpty ? "none" : parts.joined()
    }
}

public enum TriggerKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case shift
    case optionShift
    case fn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shift: return "Shift"
        case .optionShift: return "Option + Shift"
        case .fn: return "Fn / Globe"
        }
    }

    /// The exact modifier set that must be held (and nothing else).
    public var required: ModifierSet {
        switch self {
        case .shift: return [.shift]
        case .optionShift: return [.shift, .option]
        case .fn: return [.fn]
        }
    }
}

public struct TriggerSettings: Equatable, Sendable {
    public static let holdRange: ClosedRange<TimeInterval> = 0.2...0.8
    public static let defaultHold: TimeInterval = 0.3

    public var key: TriggerKey
    public var holdDuration: TimeInterval {
        didSet { holdDuration = min(max(holdDuration, Self.holdRange.lowerBound), Self.holdRange.upperBound) }
    }

    public init(key: TriggerKey = .shift, holdDuration: TimeInterval = TriggerSettings.defaultHold) {
        self.key = key
        self.holdDuration = min(max(holdDuration, Self.holdRange.lowerBound), Self.holdRange.upperBound)
    }
}
