import Combine
import Foundation
import NameShiftCore

/// UserDefaults-backed preferences. Moves to GRDB with presets/history in Phase 3.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var triggerKey: TriggerKey { didSet { defaults.set(triggerKey.rawValue, forKey: "triggerKey") } }
    /// Milliseconds, 200–800.
    @Published var holdMilliseconds: Double { didSet { defaults.set(holdMilliseconds, forKey: "holdMs") } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "haptics") } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "sound") } }
    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "paused") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        triggerKey = defaults.string(forKey: "triggerKey").flatMap(TriggerKey.init(rawValue:)) ?? .shift
        let ms = defaults.double(forKey: "holdMs")
        holdMilliseconds = ms == 0 ? TriggerSettings.defaultHold * 1000 : ms
        hapticsEnabled = defaults.object(forKey: "haptics") as? Bool ?? true
        soundEnabled = defaults.bool(forKey: "sound")
        isPaused = defaults.bool(forKey: "paused")
    }

    var triggerSettings: TriggerSettings {
        TriggerSettings(key: triggerKey, holdDuration: holdMilliseconds / 1000)
    }
}
