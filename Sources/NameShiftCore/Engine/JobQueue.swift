import Combine
import Foundation

public struct ActionResult: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let input: URL
        public let message: String
        public init(input: URL, message: String) { self.input = input; self.message = message }
    }

    public var outputs: [URL]
    public var failures: [Failure]

    public init(outputs: [URL], failures: [Failure] = []) {
        self.outputs = outputs
        self.failures = failures
    }
}

@MainActor
public final class Job: ObservableObject, Identifiable {
    public enum State: Equatable {
        case queued, running, succeeded(ActionResult), failed(String), cancelled
        public var isFinished: Bool {
            switch self { case .queued, .running: return false; default: return true }
        }
    }

    public typealias Work = @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> ActionResult

    public let id = UUID()
    public let title: String
    public let inputs: [URL]
    @Published public internal(set) var state: State = .queued
    @Published public internal(set) var progress: Double = 0

    let work: Work
    var task: Task<Void, Never>?

    init(title: String, inputs: [URL], work: @escaping Work) {
        self.title = title
        self.inputs = inputs
        self.work = work
    }
}

/// FIFO queue with a concurrency limit. Work runs off the main actor; state is published
/// on the main actor for the HUD.
@MainActor
public final class JobQueue: ObservableObject {
    @Published public private(set) var jobs: [Job] = []
    public let maxConcurrent: Int
    public var onFinished: ((Job) -> Void)?

    public init(maxConcurrent: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    @discardableResult
    public func enqueue(title: String, inputs: [URL], work: @escaping Job.Work) -> Job {
        let job = Job(title: title, inputs: inputs, work: work)
        jobs.append(job)
        pump()
        return job
    }

    public func cancel(_ job: Job) {
        switch job.state {
        case .queued:
            job.state = .cancelled
            onFinished?(job)
        case .running:
            job.task?.cancel()
        default:
            break
        }
    }

    private var runningCount: Int { jobs.filter { $0.state == .running }.count }

    private func pump() {
        while runningCount < maxConcurrent, let next = jobs.first(where: { $0.state == .queued }) {
            start(next)
        }
        if jobs.count > 50 { jobs.removeAll { $0.state.isFinished } }
    }

    private func start(_ job: Job) {
        job.state = .running
        let work = job.work
        job.task = Task.detached(priority: .userInitiated) { [weak self] in
            let progress: @Sendable (Double) -> Void = { value in
                Task { @MainActor in if job.state == .running { job.progress = value } }
            }
            let state: Job.State
            do {
                let result = try await work(progress)
                state = Task.isCancelled ? .cancelled : .succeeded(result)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = .failed(String(describing: error))
            }
            await MainActor.run {
                job.state = state
                if case .succeeded = state { job.progress = 1 }
                self?.onFinished?(job)
                self?.pump()
            }
        }
    }
}
