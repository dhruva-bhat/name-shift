import AppKit
import QuickLookThumbnailing
import NameShiftCore
import SwiftUI

/// Countdown + order state for the merge tray. Auto-confirms after `duration` unless the user
/// starts dragging, which pauses it until Return / the Merge button.
@MainActor
final class TrayModel: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let file: FileDescriptor
        var thumbnail: NSImage?
    }

    @Published var items: [Item]
    @Published private(set) var remaining: Double
    @Published private(set) var isPaused = false
    let duration: Double
    var onFinish: (([FileDescriptor]?) -> Void)?
    private var timer: Timer?

    init(files: [FileDescriptor], duration: Double = 2.0) {
        items = files.map { Item(file: $0) }
        self.duration = duration
        remaining = duration
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !isPaused else { return }
        remaining -= 1.0 / 30
        if remaining <= 0 { confirm() }
    }

    func pause() { isPaused = true }
    func confirm() { finish(items.map(\.file)) }
    func cancel() { finish(nil) }

    /// Returns how many positions the item actually moved (clamped at the ends).
    @discardableResult
    func move(_ id: UUID, by steps: Int) -> Int {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return 0 }
        let to = min(max(from + steps, 0), items.count - 1)
        guard to != from else { return 0 }
        items = MergeOrdering.move(items, from: from, to: to)
        return to - from
    }

    func loadThumbnails(scale: CGFloat) {
        for item in items {
            let request = QLThumbnailGenerator.Request(fileAt: item.file.url, size: CGSize(width: 72, height: 72),
                                                       scale: scale, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
                guard let image = rep?.nsImage else { return }
                Task { @MainActor in
                    guard let self, let i = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                    self.items[i].thumbnail = image
                }
            }
        }
    }

    private func finish(_ result: [FileDescriptor]?) {
        timer?.invalidate()
        timer = nil
        let callback = onFinish
        onFinish = nil
        callback?(result)
    }
}

struct TrayView: View {
    static let itemWidth: CGFloat = 84
    static let spacing: CGFloat = 8

    @ObservedObject var model: TrayModel
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var consumed: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Merge \(model.items.count) files → PDF").font(.headline)
                Spacer()
                Text(model.isPaused ? "Return to merge · Esc to cancel"
                                    : "Merging in \(String(format: "%.1f", max(model.remaining, 0)))s · drag to reorder")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        let dragging = draggingID == item.id
                        TrayItemView(item: item, position: index + 1)
                            .offset(x: dragging ? dragOffset : 0)
                            .scaleEffect(dragging ? 1.06 : 1)
                            .zIndex(dragging ? 1 : 0)
                            .gesture(drag(item))
                    }
                }
                .padding(.vertical, 4)
                .animation(.spring(response: 0.22, dampingFraction: 0.85), value: model.items.map(\.id))
            }

            ProgressView(value: model.isPaused ? 0 : max(model.remaining, 0) / model.duration)
                .progressViewStyle(.linear)
                .opacity(model.isPaused ? 0 : 1)

            HStack {
                Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Merge") { model.confirm() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: Self.width(for: model.items.count))
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    static func width(for count: Int) -> CGFloat {
        min(max(CGFloat(count) * (itemWidth + spacing) + 28, 360), 760)
    }

    private func drag(_ item: TrayModel.Item) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                model.pause()
                if draggingID == nil { draggingID = item.id; consumed = 0 }
                dragOffset = value.translation.width - consumed
                let stride = Self.itemWidth + Self.spacing
                let steps = Int((dragOffset / stride).rounded())
                if steps != 0 {
                    let moved = model.move(item.id, by: steps)
                    consumed += CGFloat(moved) * stride
                    dragOffset = value.translation.width - consumed
                }
            }
            .onEnded { _ in
                draggingID = nil
                dragOffset = 0
                consumed = 0
            }
    }
}

private struct TrayItemView: View {
    let item: TrayModel.Item
    let position: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumb = item.thumbnail {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.file.url.path)).resizable()
                    }
                }
                .frame(width: 72, height: 72)
                Text("\(position)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
            }
            Text(item.file.url.lastPathComponent)
                .font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: TrayView.itemWidth)
        .contentShape(Rectangle())
    }
}

/// Key-capable but non-activating: Return/Esc go to the tray instead of Finder (where Return
/// would start renaming the selected file), while Finder stays the active app.
final class TrayPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class ReorderTrayController {
    private let panel = TrayPanel()

    /// Calls `completion` with the confirmed order, or nil if cancelled.
    func present(files: [FileDescriptor], near point: NSPoint, completion: @escaping ([FileDescriptor]?) -> Void) {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let model = TrayModel(files: files)
        model.onFinish = { [weak self] result in
            self?.panel.orderOut(nil)
            self?.panel.contentView = nil
            previousApp?.activate()  // hand key focus straight back to Finder
            completion(result)
        }
        panel.onCancel = { [weak model] in model?.cancel() }

        let host = FirstMouseHostingView(rootView: TrayView(model: model))
        let size = host.fittingSize
        panel.contentView = host
        let screen = (NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main)
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 24)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        model.loadThumbnails(scale: screen?.backingScaleFactor ?? 2)
        model.start()
    }
}
