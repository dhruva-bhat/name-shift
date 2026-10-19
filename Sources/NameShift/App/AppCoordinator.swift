import AppKit
import Combine
import QuartzCore
import NameShiftCore

/// Wires the runtime flow: event tap → state machine → gate → wheel → action → job → HUD.
/// Decisions live in NameShiftCore; this type only connects them to AppKit.
@MainActor
final class AppCoordinator {
    let settings: SettingsStore
    let log = TriggerLog()
    let permissions = PermissionCenter()
    let undo = UndoHistory()
    let jobs = JobQueue(maxConcurrent: 2)
    let registry = ActionRegistry.phase1()

    private let monitor = ModifierMonitor()
    private var machine: HoldTriggerMachine
    private let gate = TriggerGate()
    private let environment = SystemTriggerEnvironment(selectionProvider: FinderSelectionProvider())

    private let wheelModel = WheelViewModel()
    private let wheelPanel = WheelPanel()
    private var wheelCenter: NSPoint = .zero
    private var wheelFiles: [FileDescriptor] = []
    private var holdTimer: DispatchWorkItem?

    private let tray = ReorderTrayController()
    private lazy var hud = ProgressHUDController(onUndo: { [weak self] in self?.undoLast() },
                                                 onCancel: { [weak self] job in self?.jobs.cancel(job) })
    private var subscriptions: Set<AnyCancellable> = []

    var isMonitoring: Bool { monitor.isInstalled }

    init(settings: SettingsStore) {
        self.settings = settings
        machine = HoldTriggerMachine(settings: settings.triggerSettings)

        settings.$triggerKey.combineLatest(settings.$holdMilliseconds)
            .sink { [weak self] key, ms in
                self?.machine.settings = TriggerSettings(key: key, holdDuration: ms / 1000)
            }
            .store(in: &subscriptions)
        settings.$isPaused.dropFirst()
            .sink { [weak self] paused in
                guard let self else { return }
                if paused { self.closeWheel() }
                self.apply(self.machine.reset(currentModifiers: []))
                self.log.info(paused ? "paused" : "resumed")
            }
            .store(in: &subscriptions)
    }

    func start() {
        monitor.handler = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        jobs.onFinished = { [weak self] job in self?.jobFinished(job) }
        startMonitorIfPossible()
    }

    func startMonitorIfPossible() {
        guard !monitor.isInstalled else { return }
        if monitor.start() {
            log.info("event tap installed (listen-only); trigger = \(settings.triggerKey.displayName), hold = \(Int(settings.holdMilliseconds)) ms")
        } else if CGPreflightListenEventAccess() {
            log.fail("event tap creation failed even though Input Monitoring looks granted — try relaunching")
        }
    }

    // MARK: - Event flow

    private var isWheelOpen: Bool { wheelPanel.isVisible }

    private func handle(_ event: ModifierMonitor.Event) {
        switch event {
        case .trigger(let input):
            feed(input)
        case .mouseDown(let primary):
            var onWheel = false
            if isWheelOpen {
                updateHover()  // target the slice under the click, not the last mouse-move sample
                let p = NSEvent.mouseLocation
                onWheel = primary && hypot(p.x - wheelCenter.x, p.y - wheelCenter.y) <= WheelView.outerRadius
            }
            feed(.mouseDown(onWheel: onWheel))
        case .mouseMoved:
            if isWheelOpen { updateHover() }
        case .scroll(let delta, let precise):
            feed(.scroll)
            if isWheelOpen, wheelModel.scrolled(delta: delta, precise: precise) { tick() }
        case .tapReenabled(let mods):
            log.fail("event tap was disabled by the system; re-enabled and resynced (\(mods))")
            closeWheel()
            apply(machine.reset(currentModifiers: mods))
        }
    }

    private func feed(_ input: TriggerInput) {
        guard !settings.isPaused else { return }
        apply(machine.handle(input))
    }

    private func apply(_ outputs: [TriggerOutput]) {
        for output in outputs {
            switch output {
            case .scheduleHoldTimer(let delay, let generation):
                holdTimer?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.feed(.holdTimerFired(generation: generation)) }
                }
                holdTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            case .cancelHoldTimer:
                holdTimer?.cancel()
                holdTimer = nil
            case .holdElapsed:
                openWheelIfGatePasses()
            case .commit:
                commitWheel()
            case .cancel(let reason):
                closeWheel()
                log.info("wheel cancelled: \(reason)")
            case .note(let message):
                log.info(message)
            }
        }
    }

    // MARK: - Wheel

    private func openWheelIfGatePasses() {
        let started = CACurrentMediaTime()
        let decision = gate.evaluate(environment, paused: settings.isPaused)
        let ms = Int((CACurrentMediaTime() - started) * 1000)
        switch decision {
        case .rejected(let failure):
            machine.dismissWheel()
            log.fail("gate rejected: \(failure) [\(ms) ms]")
        case .open(let urls):
            let files = urls.map(FileDescriptor.probe)
            wheelFiles = files
            wheelModel.reset(slices: registry.slices(for: files), summary: files.summary,
                             deadZoneRadius: WheelView.innerRadius)
            wheelCenter = wheelPanel.present(WheelView(model: wheelModel), at: NSEvent.mouseLocation)
            updateHover()
            let enabled = registry.slices(for: files).filter(\.isEnabled).map(\.title)
            log.pass("gate passed: Finder, \(files.count) selected (\(files.summary)) [\(ms) ms] → wheel open; enabled: \(enabled.joined(separator: ", "))")
        }
    }

    private func updateHover() {
        let p = NSEvent.mouseLocation
        if wheelModel.pointerMoved(offset: CGVector(dx: p.x - wheelCenter.x, dy: p.y - wheelCenter.y)) { tick() }
    }

    private func tick() {
        Feedback.tick(haptics: settings.hapticsEnabled, sound: settings.soundEnabled)
    }

    private func closeWheel() {
        if wheelPanel.isVisible { wheelPanel.dismiss() }
    }

    private func commitWheel() {
        closeWheel()
        guard let slice = wheelModel.commitTarget() else {
            if let hovered = wheelModel.hoveredSlice {
                log.info("released on disabled “\(hovered.title)”: \(hovered.detail ?? "")")
                hud.showInfo(hovered.detail ?? "Not available for this selection", title: hovered.title)
            } else {
                log.info("released/clicked in center → cancelled")
            }
            return
        }
        guard let action = registry.action(id: slice.id) else { return }
        log.pass("fire: \(action.title) on \(wheelFiles.summary)")
        perform(action, on: wheelFiles)
    }

    private func perform(_ action: any FileAction, on files: [FileDescriptor]) {
        guard action.requiresOrdering else { return run(action, on: files) }
        let ordered = MergeOrdering.defaultOrder(files, selectionOrderIsMeaningful: FinderSelectionProvider.selectionOrderIsMeaningful)
        tray.present(files: ordered, near: NSEvent.mouseLocation) { [weak self] result in
            guard let self else { return }
            guard let result else { return self.log.info("merge tray cancelled") }
            self.log.info("merge order: \(result.map(\.url.lastPathComponent).joined(separator: ", "))")
            self.run(action, on: result)
        }
    }

    private func run(_ action: any FileAction, on files: [FileDescriptor]) {
        let job = jobs.enqueue(title: "\(action.title) · \(files.summary)", inputs: files.map(\.url)) { progress in
            try await action.run(on: files, progress: progress)
        }
        hud.track(job)
    }

    // MARK: - Jobs & undo

    private func jobFinished(_ job: Job) {
        switch job.state {
        case .succeeded(let result):
            undo.record(id: job.id, title: job.title, outputs: result.outputs)
            log.pass("job done: \(job.title) → \(result.outputs.map(\.lastPathComponent).joined(separator: ", "))"
                     + (result.failures.isEmpty ? "" : "; \(result.failures.count) failed"))
        case .failed(let message):
            log.fail("job failed: \(job.title): \(message)")
        case .cancelled:
            log.info("job cancelled: \(job.title)")
        default:
            break
        }
    }

    func undoLast() {
        guard let entry = undo.last else { return }
        do {
            let trashed = try undo.undoLast()
            log.info("undo: moved \(trashed.count) file(s) from “\(entry.title)” to Trash")
            hud.showInfo("Moved \(trashed.count) file\(trashed.count == 1 ? "" : "s") to the Trash", title: "Undo")
        } catch {
            hud.showInfo("Undo failed: \(error.localizedDescription)", title: "Undo")
        }
    }
}
