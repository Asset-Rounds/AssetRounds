import Foundation
import OSLog

enum DiagnosticsLogEvent: Equatable, Sendable {
    case countersWriteFailed
    case invalidCountersReset
    case metricValueDiscarded
}

struct DiagnosticsLogger: Sendable {
    typealias Sink = @Sendable (DiagnosticsLogEvent) -> Void

    static let live = DiagnosticsLogger()

    private let sink: Sink

    init() {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "FieldEvidenceApp",
            category: "Diagnostics"
        )
        sink = { event in
            switch event {
            case .countersWriteFailed:
                logger.fault("Diagnostics counters could not be saved.")
            case .invalidCountersReset:
                logger.fault("Invalid diagnostics counters were reset.")
            case .metricValueDiscarded:
                logger.error("A diagnostic metric value was discarded.")
            }
        }
    }

    init(sink: @escaping Sink) {
        self.sink = sink
    }

    func record(_ event: DiagnosticsLogEvent) {
        sink(event)
    }
}
