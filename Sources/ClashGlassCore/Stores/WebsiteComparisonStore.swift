import Foundation
import Observation

@Observable
@MainActor
public final class WebsiteComparisonStore {
    public var input = "" {
        didSet {
            if input != oldValue {
                if isRunning { cancel() }
                isInputInvalid = false
                if result != nil { isStale = true }
            }
        }
    }
    public private(set) var result: WebsiteComparison?
    public private(set) var isRunning = false
    public private(set) var isInputInvalid = false
    public private(set) var isStale = false
    public private(set) var wasCancelled = false
    private let service: WebsiteComparisonService
    private var generation = 0
    @ObservationIgnored private var request: Task<WebsiteComparison, Never>?

    public init(service: WebsiteComparisonService = WebsiteComparisonService()) { self.service = service }

    public func run(context: WebsiteComparisonContext) async {
        guard !isRunning else { return }
        guard let url = try? WebsiteURLInput.normalized(input) else {
            isInputInvalid = true
            return
        }
        generation += 1
        let revision = generation
        isInputInvalid = false
        isRunning = true
        wasCancelled = false
        isStale = false
        result = nil
        let service = service
        let task = Task { await service.compare(url: url, context: context) }
        request = task
        let completed = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard revision == generation else { return }
        request = nil
        isRunning = false
        guard !Task.isCancelled else { wasCancelled = true; return }
        result = completed
    }

    public func cancel() {
        generation += 1
        request?.cancel()
        request = nil
        if isRunning { wasCancelled = true }
        isRunning = false
    }

    public func invalidate() {
        cancel()
        if result != nil { isStale = true }
    }
}
