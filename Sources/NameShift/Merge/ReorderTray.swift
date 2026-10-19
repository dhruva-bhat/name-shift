import AppKit
import NameShiftCore
import Quartz
import QuickLookThumbnailing
import SwiftUI

/// Order, selection and preview state for the merge tray. Nothing happens until the user
/// confirms (Merge button / Return) or cancels (Cancel / Esc).
@MainActor
final class TrayModel: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        var file: FileDescriptor
        var thumbnail: NSImage?
    }

    @Published var items: [Item]
    @Published var selectedID: UUID?
    @Published private(set) var isPreviewing = false
    var onFinish: (([FileDescriptor]?) -> Void)?

    init(files: [FileDescriptor]) {
        let items = files.map { Item(file: $0) }
        self.items = items
        selectedID = items.first?.id
    }

    var selectedIndex: Int? { items.firstIndex { $0.id == selectedID } }
    var selectedItem: Item? { selectedIndex.map { items[$0] } }

    func confirm() { finish(items.map(\.file)) }
    func cancel() { finish(nil) }

    func togglePreview() {
        isPreviewing.toggle()
    }

    func select(_ id: UUID) {
        selectedID = id
    }

    /// Arrow keys: move the selection (the preview follows it).
    func selectNeighbor(_ offset: Int) {
        guard let i = selectedIndex else { selectedID = items.first?.id; return }
        selectedID = items[min(max(i + offset, 0), items.count - 1)].id
    }

    /// Option-arrow keys: move the selected file within the merge order.
    func moveSelected(by offset: Int) {
        guard let id = selectedID else { return }
        move(id, by: offset)
    }

    func move(_ id: UUID, by steps: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        move(id, to: from + steps)
    }

    /// Moves the item to `index` (clamped). No-op if it's already there.
    func move(_ id: UUID, to index: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(index, 0), items.count - 1)
        guard to != from else { return }
        items = MergeOrdering.move(items, from: from, to: to)
    }

    /// Thumbnails and page counts load off the main thread (the wheel only had file types).
    func loadThumbnails(scale: CGFloat) {
        for item in items {
            let url = item.file.url
            Task { [weak self] in
                let probed = await Task.detached(priority: .userInitiated) { FileDescriptor.probe(url) }.value
                guard let self, let i = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                self.items[i].file = probed
            }
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
        let callback = onFinish
        onFinish = nil
        callback?(result)
    }
}

struct TrayView: View {
    static let itemWidth: CGFloat = 84
    static let spacing: CGFloat = 8

    @ObservedObject var model: TrayModel
    /// The item being dragged and the slot it started in.
    @State private var dragging: (id: UUID, startIndex: Int)?
    /// Pointer travel since the drag began, measured in the strip's (fixed) coordinate space.
    @State private var dragTranslation: CGFloat = 0

    private static let stride = itemWidth + spacing
    private static let reorderAnimation = Animation.spring(response: 0.25, dampingFraction: 0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Merge \(model.items.count) files → PDF").font(.headline)
                Spacer()
                Text("Check the order, then Merge").font(.caption).foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.spacing) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            let isDragged = dragging?.id == item.id
                            TrayItemView(item: item, position: index + 1, selected: item.id == model.selectedID)
                                .id(item.id)
                                .offset(x: isDragged ? dragOffset(currentIndex: index) : 0)
                                .scaleEffect(isDragged ? 1.06 : 1)
                                .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 6, y: 2)
                                .zIndex(isDragged ? 1 : 0)
                                // The dragged item tracks the pointer exactly; only its neighbours animate.
                                .transaction { if isDragged { $0.animation = nil } }
                                .onTapGesture(count: 2) { model.select(item.id); if !model.isPreviewing { model.togglePreview() } }
                                .onTapGesture { model.select(item.id) }
                                .gesture(drag(item, index: index))
                        }
                    }
                    .padding(.vertical, 4)
                    .coordinateSpace(name: "strip")
                }
                .onChange(of: model.selectedID) { _, id in
                    // Keyboard selection scrolls into view; a drag must not scroll the strip under the pointer.
                    if let id, dragging == nil { withAnimation { proxy.scrollTo(id) } }
                }
            }

            if model.isPreviewing, let item = model.selectedItem, let index = model.selectedIndex {
                VStack(spacing: 6) {
                    QuickLookPreview(url: item.file.url)
                        .frame(height: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("\(index + 1) of \(model.items.count) · \(item.file.url.lastPathComponent)"
                         + (item.file.pageCount.map { " · \($0) page\($0 == 1 ? "" : "s")" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }

            HStack {
                Text("Space preview · ←→ select · ⌥←→ move · drag to reorder")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel  esc") { model.cancel() }
                Button("Merge  ↩") { model.confirm() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: Self.width(for: model.items.count, previewing: model.isPreviewing))
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    static func width(for count: Int, previewing: Bool) -> CGFloat {
        min(max(CGFloat(count) * (itemWidth + spacing) + 28, previewing ? 600 : 460), 760)
    }

    /// Visual offset that keeps the dragged item under the pointer even after its slot changes.
    private func dragOffset(currentIndex: Int) -> CGFloat {
        guard let dragging else { return 0 }
        return dragTranslation - CGFloat(currentIndex - dragging.startIndex) * Self.stride
    }

    private func drag(_ item: TrayModel.Item, index: Int) -> some Gesture {
        // Measured in the strip's space: in the item's own space the translation would jump by a
        // whole slot every time the item is reordered, which made the drag oscillate.
        DragGesture(minimumDistance: 3, coordinateSpace: .named("strip"))
            .onChanged { value in
                if dragging == nil {
                    dragging = (item.id, index)
                    model.selectedID = item.id
                }
                guard let dragging else { return }
                dragTranslation = value.translation.width
                // Target slot from the total distance, not accumulated steps, so it can't drift.
                let target = dragging.startIndex + Int((dragTranslation / Self.stride).rounded())
                withAnimation(Self.reorderAnimation) { model.move(item.id, to: target) }
            }
            .onEnded { _ in
                // Settle the dropped item into its slot.
                withAnimation(Self.reorderAnimation) {
                    dragging = nil
                    dragTranslation = 0
                }
            }
    }
}

private struct TrayItemView: View {
    let item: TrayModel.Item
    let position: Int
    let selected: Bool

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
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.18) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            Text(item.file.url.lastPathComponent)
                .font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: TrayView.itemWidth)
        .contentShape(Rectangle())
    }
}

/// Inline Quick Look (scrollable for multi-page PDFs). Embedded in the tray rather than using the
/// shared QLPreviewPanel, so keyboard focus stays in the tray and never falls back to Finder.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

/// Key-capable but non-activating: keys go to the tray instead of Finder (where Return would
/// rename and Space would open Finder's own Quick Look), while Finder stays the active app.
final class TrayPanel: NSPanel {
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
}

@MainActor
final class ReorderTrayController {
    private let panel = TrayPanel()
    private var keyMonitor: Any?
    private var previewSubscription: AnyObject?
    private var activeModel: TrayModel?

    /// Calls `completion` with the confirmed order, or nil if cancelled. If a tray is already
    /// open, it is cancelled first (its completion gets nil) so nothing is dropped or leaked.
    func present(files: [FileDescriptor], near point: NSPoint, completion: @escaping ([FileDescriptor]?) -> Void) {
        activeModel?.cancel()
        let previousApp = NSWorkspace.shared.frontmostApplication
        let model = TrayModel(files: files)
        activeModel = model
        model.onFinish = { [weak self] result in
            guard let self else { return }
            self.activeModel = nil
            if let keyMonitor = self.keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            self.keyMonitor = nil
            self.previewSubscription = nil
            self.panel.orderOut(nil)
            self.panel.contentViewController = nil
            previousApp?.activate()  // hand key focus straight back to Finder
            completion(result)
        }

        // The window follows the SwiftUI size, so it grows when the preview opens.
        let host = NSHostingController(rootView: TrayView(model: model))
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        let size = host.view.fittingSize
        let screen = NSScreen.containing(point)
        panel.setFrame(NSRect(origin: NSPoint(x: point.x - size.width / 2, y: point.y + 24), size: size), display: true)
        keepOnScreen(screen)
        panel.makeKeyAndOrderFront(nil)

        previewSubscription = model.$isPreviewing.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.keepOnScreen(screen) }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            guard let self, let model, event.window === self.panel else { return event }
            let keyCode = event.keyCode
            let option = event.modifierFlags.contains(.option)
            MainActor.assumeIsolated { Self.handleKey(keyCode, option: option, model: model) }
            return nil  // every key is handled here, so none falls through to Finder
        }

        model.loadThumbnails(scale: screen?.backingScaleFactor ?? 2)
    }

    private static func handleKey(_ keyCode: UInt16, option: Bool, model: TrayModel) {
        switch keyCode {
        case 49: model.togglePreview()                                        // Space
        case 123: option ? model.moveSelected(by: -1) : model.selectNeighbor(-1)  // ←
        case 124: option ? model.moveSelected(by: 1) : model.selectNeighbor(1)    // →
        case 36, 76: model.confirm()                                          // Return / Enter
        case 53: model.isPreviewing ? model.togglePreview() : model.cancel()  // Esc closes preview first
        default: break  // swallow other keys so they never reach Finder
        }
    }

    private func keepOnScreen(_ screen: NSScreen?) {
        guard let vf = screen?.visibleFrame else { return }
        panel.setFrame(panel.frame.clamped(to: vf, margin: 8), display: true)
    }
}
