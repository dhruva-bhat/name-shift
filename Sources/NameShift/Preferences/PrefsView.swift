import NameShiftCore
import SwiftUI

struct PrefsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Trigger", selection: $settings.triggerKey) {
                ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            if settings.triggerKey == .fn {
                Text("Set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing, or Fn will also open the emoji/input picker.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            LabeledContent("Hold duration") {
                HStack {
                    Slider(value: $settings.holdMilliseconds,
                           in: TriggerSettings.holdRange.lowerBound * 1000...TriggerSettings.holdRange.upperBound * 1000,
                           step: 10)
                    Text("\(Int(settings.holdMilliseconds)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            }

            Toggle("Trackpad haptic tick", isOn: $settings.hapticsEnabled)
            Toggle("Tick sound", isOn: $settings.soundEnabled)
            Toggle("Paused", isOn: $settings.isPaused)
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
