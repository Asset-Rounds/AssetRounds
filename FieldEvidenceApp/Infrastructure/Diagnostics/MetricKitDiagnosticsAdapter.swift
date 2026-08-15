import Foundation
import MetricKit

final class MetricKitDiagnosticsAdapter: NSObject, MXMetricManagerSubscriber {
    private let lock = NSLock()
    private let manager: MXMetricManager?
    private let logger: DiagnosticsLogger
    private var retainedSummary: MetricKitSummaryV1?
    private var isStarted = false

    init(
        manager: MXMetricManager? = .shared,
        logger: DiagnosticsLogger = .live
    ) {
        self.manager = manager
        self.logger = logger
        super.init()
    }

    deinit {
        if isStarted {
            manager?.remove(self)
        }
    }

    func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()
        manager?.add(self)
    }

    func stop() {
        lock.lock()
        guard isStarted else {
            lock.unlock()
            return
        }
        isStarted = false
        lock.unlock()
        manager?.remove(self)
    }

    func snapshot() -> MetricKitSummaryV1? {
        lock.lock()
        defer { lock.unlock() }
        return retainedSummary
    }

    @discardableResult
    func accept(_ summary: MetricKitSummaryV1) -> Bool {
        guard summary.isValid else {
            logger.record(.metricValueDiscarded)
            return false
        }
        merge(summary)
        return true
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            var launchTime: LaunchTimeMillisecondsV1?
            if let metrics = payload.applicationLaunchMetrics {
                launchTime = reducedLaunchTime(
                    metrics.histogrammedTimeToFirstDraw
                )
            }

            var peakMemoryBytes: Int64?
            if let metric = payload.memoryMetrics {
                peakMemoryBytes = boundedBytes(metric.peakMemoryUsage)
            }

            guard launchTime != nil || peakMemoryBytes != nil else {
                continue
            }
            merge(
                MetricKitSummaryV1(
                    crashCount: 0,
                    hangCount: 0,
                    launchTimeMilliseconds: launchTime,
                    peakMemoryBytes: peakMemoryBytes
                )
            )
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashCount = Int64(payload.crashDiagnostics?.count ?? 0)
            let hangCount = Int64(payload.hangDiagnostics?.count ?? 0)
            guard crashCount > 0 || hangCount > 0 else {
                continue
            }
            merge(
                MetricKitSummaryV1(
                    crashCount: crashCount,
                    hangCount: hangCount,
                    launchTimeMilliseconds: nil,
                    peakMemoryBytes: nil
                )
            )
        }
    }

    private func merge(_ incoming: MetricKitSummaryV1) {
        lock.lock()
        defer { lock.unlock() }

        guard let current = retainedSummary else {
            retainedSummary = incoming
            return
        }
        retainedSummary = MetricKitSummaryV1(
            crashCount: saturatedAdd(current.crashCount, incoming.crashCount),
            hangCount: saturatedAdd(current.hangCount, incoming.hangCount),
            launchTimeMilliseconds: merged(
                current.launchTimeMilliseconds,
                incoming.launchTimeMilliseconds
            ),
            peakMemoryBytes: maximum(
                current.peakMemoryBytes,
                incoming.peakMemoryBytes
            )
        )
    }

    private func reducedLaunchTime(
        _ histogram: MXHistogram<UnitDuration>
    ) -> LaunchTimeMillisecondsV1? {
        var result = LaunchTimeMillisecondsV1.zero
        var acceptedCount: Int64 = 0
        let enumerator = histogram.bucketEnumerator

        while let object = enumerator.nextObject() {
            guard let bucket = object as? MXHistogramBucket<UnitDuration> else {
                logger.record(.metricValueDiscarded)
                continue
            }
            let count = Int64(bucket.bucketCount)
            let start = bucket.bucketStart.converted(to: .milliseconds).value
            let end = bucket.bucketEnd.converted(to: .milliseconds).value
            guard count >= 0,
                  start.isFinite,
                  end.isFinite,
                  start >= 0,
                  end >= start else {
                logger.record(.metricValueDiscarded)
                continue
            }
            guard count > 0 else { continue }

            if end <= 500 {
                result.under500 = saturatedAdd(result.under500, count)
            } else if start >= 500, end <= 1_000 {
                result.from500Through999 = saturatedAdd(
                    result.from500Through999,
                    count
                )
            } else if start >= 1_000, end <= 2_000 {
                result.from1000Through1999 = saturatedAdd(
                    result.from1000Through1999,
                    count
                )
            } else if start >= 2_000 {
                result.from2000Up = saturatedAdd(result.from2000Up, count)
            } else {
                // A source bucket that crosses an export boundary cannot be
                // split truthfully, so this best-effort summary undercounts it.
                logger.record(.metricValueDiscarded)
                continue
            }
            acceptedCount = saturatedAdd(acceptedCount, count)
        }
        return acceptedCount == 0 ? nil : result
    }

    private func boundedBytes(
        _ measurement: Measurement<UnitInformationStorage>
    ) -> Int64? {
        let value = measurement.converted(to: .bytes).value
        guard value.isFinite, value >= 0 else {
            logger.record(.metricValueDiscarded)
            return nil
        }
        if value >= Double(Int64.max) {
            return .max
        }
        return Int64(value.rounded(.down))
    }

    private func merged(
        _ lhs: LaunchTimeMillisecondsV1?,
        _ rhs: LaunchTimeMillisecondsV1?
    ) -> LaunchTimeMillisecondsV1? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return LaunchTimeMillisecondsV1(
                from1000Through1999: saturatedAdd(
                    lhs.from1000Through1999,
                    rhs.from1000Through1999
                ),
                from2000Up: saturatedAdd(lhs.from2000Up, rhs.from2000Up),
                from500Through999: saturatedAdd(
                    lhs.from500Through999,
                    rhs.from500Through999
                ),
                under500: saturatedAdd(lhs.under500, rhs.under500)
            )
        case let (.some(value), .none), let (.none, .some(value)):
            return value
        case (.none, .none):
            return nil
        }
    }

    private func maximum(_ lhs: Int64?, _ rhs: Int64?) -> Int64? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return max(lhs, rhs)
        case let (.some(value), .none), let (.none, .some(value)):
            return value
        case (.none, .none):
            return nil
        }
    }

    private func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if rhs > Int64.max - lhs {
            return .max
        }
        return lhs + rhs
    }
}
