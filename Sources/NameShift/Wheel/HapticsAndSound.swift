import AppKit

/// Tick when the hovered slice changes. Haptics only register while a finger is on a
/// Force Touch trackpad; the optional sound covers mice.
@MainActor
enum Feedback {
    private static let tickSound: NSSound? = {
        let sound = NSSound(named: "Tink")
        sound?.volume = 0.2
        return sound
    }()

    static func tick(haptics: Bool, sound: Bool) {
        if haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if sound, let tickSound {
            tickSound.stop()
            tickSound.play()
        }
    }
}
