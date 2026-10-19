import AppKit
import NameShiftCore
import SwiftUI

/// Live trigger log: why the gate fired or didn't. Opened as a floating window so it stays
/// visible while you test in Finder.
struct DebugLogView: View {
    @ObservedObject var log: TriggerLog

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(log.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.time.string(from: entry.date)).foregroundStyle(.secondary)
                        Image(systemName: symbol(entry.kind)).foregroundStyle(color(entry.kind))
                        Text(entry.message).textSelection(.enabled)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .id(entry.id)
                }
                .onChange(of: log.entries.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Text("\(log.entries.count) entries").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.plainText, forType: .string)
                }
                Button("Clear") { log.clear() }
            }
            .padding(8)
        }
        .frame(minWidth: 560, minHeight: 280)
    }

    private func symbol(_ kind: TriggerLog.Entry.Kind) -> String {
        switch kind {
        case .info: return "circle.fill"
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        }
    }

    private func color(_ kind: TriggerLog.Entry.Kind) -> Color {
        switch kind {
        case .info: return .secondary.opacity(0.5)
        case .pass: return .green
        case .fail: return .red
        }
    }
}
