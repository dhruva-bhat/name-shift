import AppKit
import NameShiftCore
import SwiftUI
import UniformTypeIdentifiers

/// `NameShift --render-readme-images <dir>` renders the real wheel, merge tray, HUD and onboarding
/// views (light + dark) into PNGs for the README, then exits. No screen capture or permissions
/// involved; the Finder window behind the wheel is a drawn mock-up.
@MainActor
enum ReadmeImages {
    static func renderIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-readme-images"), flag + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            write(wheelScene(files: ["IMG_2041.heic", "IMG_2042.heic", "IMG_2043.heic"], others: ["Notes.txt", "Budget.numbers", "IMG_2044.heic", "Scan.pdf", "Logo.png"],
                             title: "Photos", hover: CGVector(dx: 107, dy: 62)),
                  scheme, dir.appendingPathComponent("wheel-convert-\(suffix).png"))
            write(wheelScene(files: ["Invoice.pdf", "Receipt.pdf"], others: ["Contract.pdf", "Photo.jpg", "Notes.txt", "Slides.key", "Draft.pdf", "Logo.png"],
                             title: "Taxes 2026", hover: CGVector(dx: 30, dy: -120)),
                  scheme, dir.appendingPathComponent("wheel-merge-\(suffix).png"))
            write(trayScene(), scheme, dir.appendingPathComponent("merge-tray-\(suffix).png"))
            write(hudScene(), scheme, dir.appendingPathComponent("hud-\(suffix).png"))
            write(onboardingScene(), scheme, dir.appendingPathComponent("onboarding-\(suffix).png"))
        }
        print("Rendered README images to \(dir.path)")
        return true
    }

    // MARK: - Scenes

    private static func descriptors(_ names: [String]) -> [FileDescriptor] {
        names.map { name in
            let url = URL(fileURLWithPath: "/Users/you/Documents/\(name)")
            return FileDescriptor(url: url, contentType: UTType(filenameExtension: url.pathExtension))
        }
    }

    private static func wheelScene(files: [String], others: [String], title: String, hover: CGVector) -> some View {
        let selected = descriptors(files)
        let model = WheelViewModel()
        model.reset(slices: ActionRegistry.phase1().slices(for: selected), summary: selected.summary,
                    deadZoneRadius: WheelView.innerRadius)
        model.pointerMoved(offset: hover)
        let tiles = (files.map { ($0, true) } + others.map { ($0, false) })
        return SceneBackdrop {
            ZStack {
                MockFinderWindow(title: title, tiles: tiles)
                // Wheel to the right of the file grid so the selected files stay visible.
                Group {
                    WheelView(model: model, animateIn: false)
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 26))
                        .foregroundStyle(.black)
                        .shadow(color: .white, radius: 0.5).shadow(color: .white, radius: 0.5)
                        .offset(x: hover.dx + 7, y: -hover.dy + 11)  // arrow tip at the pointer
                }
                .offset(x: 250, y: 24)
            }
            .frame(width: 860, height: 440)
        }
    }

    private static func trayScene() -> some View {
        let model = TrayModel(files: descriptors(["01 Cover.pdf", "02 Invoice.pdf", "03 Receipt.jpg", "04 Notes.pdf", "05 Appendix.pdf"]))
        let pages: [(String, Color)] = [("Cover", .indigo), ("Invoice", .blue), ("Receipt", .orange), ("Notes", .teal), ("Appendix", .gray)]
        for (i, page) in pages.enumerated() { model.items[i].thumbnail = pageThumbnail(page.0, tint: NSColor(page.1)) }
        model.selectedID = model.items[2].id
        return SceneBackdrop { TrayView(model: model) }
    }

    private static func hudScene() -> some View {
        let model = HUDModel()
        model.title = "To JPG · 3 images"
        model.phase = .done(outputs: ["IMG_2041.jpg", "IMG_2042.jpg", "IMG_2043.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }, note: nil)
        return SceneBackdrop { HUDView(model: model) }
    }

    private static func onboardingScene() -> some View {
        let permissions = PermissionCenter(fixedStatus: [.inputMonitoring: .granted, .accessibility: .granted,
                                                         .automation: .notDetermined])
        return PermissionsView(permissions: permissions, onDone: {})
            .background(Color(nsColor: .windowBackgroundColor))
    }

    /// A page-like thumbnail: white sheet, colored header, a title and text lines.
    private static func pageThumbnail(_ title: String, tint: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 72, height: 72), flipped: true) { _ in
            let page = NSRect(x: 14, y: 2, width: 44, height: 68)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: page, xRadius: 2, yRadius: 2).fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            NSBezierPath(roundedRect: page, xRadius: 2, yRadius: 2).stroke()
            tint.setFill()
            NSRect(x: page.minX, y: page.minY, width: page.width, height: 12).fill()
            (title as NSString).draw(at: NSPoint(x: page.minX + 4, y: page.minY + 15),
                                     withAttributes: [.font: NSFont.boldSystemFont(ofSize: 6), .foregroundColor: NSColor.black])
            NSColor.black.withAlphaComponent(0.18).setFill()
            for row in 0..<7 {
                NSRect(x: page.minX + 4, y: page.minY + 27 + CGFloat(row) * 5, width: row % 3 == 2 ? 22 : 36, height: 1.6).fill()
            }
            return true
        }
    }

    // MARK: - Capture

    /// Hosts the view in an offscreen window and captures it, so AppKit-backed controls
    /// (buttons, scroll views) render too, which ImageRenderer can't do.
    private static func write<V: View>(_ view: V, _ scheme: ColorScheme, _ url: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .environment(\.snapshotRendering, true)
            .environment(\.colorScheme, scheme))
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()  // offscreen; lets SwiftUI and AppKit finish layout/drawing
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Soft desktop-like gradient with padding around a scene.
private struct SceneBackdrop<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(28)
            .background(
                LinearGradient(colors: colorScheme == .dark
                               ? [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.20, green: 0.12, blue: 0.28)]
                               : [Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.80, green: 0.72, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
    }
}

/// Drawn stand-in for a Finder icon-view window with some files selected.
private struct MockFinderWindow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let tiles: [(name: String, selected: Bool)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 12, height: 12) }
                Spacer()
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.93))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(118)), count: 4), alignment: .leading, spacing: 22) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (tile.name as NSString).pathExtension) ?? .data))
                            .resizable().frame(width: 64, height: 64)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(tile.selected ? Color.primary.opacity(0.12) : .clear))
                        Text(tile.name)
                            .font(.system(size: 11))
                            .foregroundStyle(tile.selected ? Color.white : Color.primary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(tile.selected ? Color.accentColor : .clear))
                    }
                }
            }
            .padding(.top, 28)
            .padding(.leading, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.15)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
}
