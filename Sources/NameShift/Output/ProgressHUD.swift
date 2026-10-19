import AppKit
import Combine
import NameShiftCore
import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    enum Phase: Equatable {
        case running
        case done(outputs: [URL], note: String?)
        case failed(String)
        case info(String)
    }

    @Published var title = ""
    @Published var progress = 0.0
    @Published var phase: Phase = .running
    var onReveal: (([URL]) -> Void)?
    var onUndo: (() -> Void)?
    var onCancel: (() -> Void)?
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            icon.font(.system(size: 20)).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                detail
            }
            Spacer(minLength: 4)
            buttons
        }
        .padding(.horizontal, 14)
        .frame(width: 400, height: 62)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    @ViewBuilder private var icon: some View {
        switch model.phase {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .running:
            ProgressView(value: model.progress).progressViewStyle(.linear)
        case .done(let outputs, let note):
            Text(note ?? (outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files created"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        case .failed(let message), .info(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.phase {
        case .running:
            Button { model.onCancel?() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel")
        case .done(let outputs, _):
            Button("Undo") { model.onUndo?() }.controlSize(.small)
            Button("Reveal in Finder") { model.onReveal?(outputs) }.controlSize(.small)
        default:
            EmptyView()
        }
    }
}

/// One toast bound to the most recent job: progress → "Done · Reveal in Finder".
@MainActor
final class ProgressHUDController {
    private let panel: NSPanel
    private let model = HUDModel()
    private var subscriptions: Set<AnyCancellable> = []
    private var hideWork: DispatchWorkItem?

    private let onCancelJob: (Job) -> Void

    private var trackedJobID: UUID?

    init(onUndo: @escaping (UUID) -> Void, onCancel: @escaping (Job) -> Void) {
        onCancelJob = onCancel
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 62),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FirstMouseHostingView(rootView: HUDView(model: model))
        model.onReveal = { [weak self] urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            self?.hide()
        }
        model.onUndo = { [weak self] in
            guard let self, let id = self.trackedJobID else { return }
            onUndo(id)  // undo this HUD's job, not whichever job finished last
            self.scheduleHide(after: 2.5)
        }
    }

    func track(_ job: Job) {
        subscriptions.removeAll()
        hideWork?.cancel()
        trackedJobID = job.id
        model.title = job.title
        model.progress = job.progress
        model.phase = .running
        model.onCancel = { [weak self, weak job] in if let job { self?.onCancelJob(job) } }
        job.$progress.sink { [weak self] in self?.model.progress = $0 }.store(in: &subscriptions)
        job.$state.sink { [weak self] state in self?.apply(state) }.store(in: &subscriptions)
        show()
    }

    func showInfo(_ message: String, title: String = "Name Shift") {
        subscriptions.removeAll()
        model.title = title
        model.phase = .info(message)
        show()
        scheduleHide(after: 2.5)
    }

    private func apply(_ state: Job.State) {
        switch state {
        case .queued, .running:
            model.phase = .running
        case .succeeded(let result):
            let note: String?
            if result.wasCancelled {
                note = "Cancelled · kept \(result.outputs.count) finished file\(result.outputs.count == 1 ? "" : "s")"
            } else if let failure = result.failures.first {
                note = "\(result.outputs.count) done, \(result.failures.count) failed: \(failure.message)"
            } else {
                note = nil
            }
            model.phase = .done(outputs: result.outputs, note: note)
            scheduleHide(after: 5)
        case .failed(let message):
            model.phase = .failed(message)
            scheduleHide(after: 6)
        case .cancelled:
            model.phase = .info("Cancelled")
            scheduleHide(after: 1.5)
        }
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        if let vf = NSScreen.containing(mouse)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY + 48))
        }
        panel.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }
}
