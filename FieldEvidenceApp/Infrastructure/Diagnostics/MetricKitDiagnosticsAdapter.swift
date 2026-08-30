import Foundation
import MetricKit

protocol MetricReportingSourceV1: AnyObject, Sendable {
    func add(_ subscriber: any MXMetricManagerSubscriber)
    func remove(_ subscriber: any MXMetricManagerSubscriber)
}

final class MetricKitReportingSourceV1: MetricReportingSourceV1,
    @unchecked Sendable {
    static let shared = MetricKitReportingSourceV1(manager: .shared)

    private let manager: MXMetricManager

    init(manager: MXMetricManager) {
        self.manager = manager
    }

    func add(_ subscriber: any MXMetricManagerSubscriber) {
        manager.add(subscriber)
    }

    func remove(_ subscriber: any MXMetricManagerSubscriber) {
        manager.remove(subscriber)
    }
}

enum MetricReportingSourceContractV1 {
    static let sourceCount = 1
    static let retainedSource = "IOS18_METRICKIT_FALLBACK"
    static let permitsBetaOnlyAPI = false
    static let permitsSecondReportingSource = false
}

/// MetricKit is reduced to the existing numeric health summary.  C54
/// envelope bytes, secret material, content/customer digests, raw metadata,
/// identifiers, filenames, and scratch locators are never accepted or
/// retained by this adapter.
enum C54EncryptedPortableEnvelopeMetricKitBoundaryV1 {
    static let diagnosticsAreMetadataOnly = true
    static let staticStageAndCategoryOnly = true
    static let acceptsOnlyNumericHealthSummary = true
    static let envelopeBytesRetained = false
    static let envelopeBytesExported = false
    static let passphrasesRetained = false
    static let passphrasesExported = false
    static let derivedKeysRetained = false
    static let derivedKeysExported = false
    static let saltsAndNonceMaterialRetained = false
    static let saltsAndNonceMaterialExported = false
    static let plaintextOrCustomerDigestsRetained = false
    static let plaintextOrCustomerDigestsExported = false
    static let rawMetadataRetained = false
    static let rawMetadataExported = false
    static let linkableIDsOrFilenamesRetained = false
    static let linkableIDsOrFilenamesExported = false
    static let scratchPathsRetained = false
    static let scratchPathsExported = false
    static let rawMetricKitPayloadRetained = false

    static func validate(_ summary: MetricKitSummaryV1?) -> Bool {
        (summary?.isValid ?? true)
            && diagnosticsAreMetadataOnly
            && staticStageAndCategoryOnly
            && acceptsOnlyNumericHealthSummary
            && !envelopeBytesRetained
            && !envelopeBytesExported
            && !passphrasesRetained
            && !passphrasesExported
            && !derivedKeysRetained
            && !derivedKeysExported
            && !saltsAndNonceMaterialRetained
            && !saltsAndNonceMaterialExported
            && !plaintextOrCustomerDigestsRetained
            && !plaintextOrCustomerDigestsExported
            && !rawMetadataRetained
            && !rawMetadataExported
            && !linkableIDsOrFilenamesRetained
            && !linkableIDsOrFilenamesExported
            && !scratchPathsRetained
            && !scratchPathsExported
            && !rawMetricKitPayloadRetained
    }
}

typealias C54MetricKitDiagnosticsBoundaryV1 =
    C54EncryptedPortableEnvelopeMetricKitBoundaryV1

final class MetricKitDiagnosticsAdapter: NSObject, MXMetricManagerSubscriber,
    @unchecked Sendable {
    private let registrationLock = NSLock()
    private let summaryLock = NSLock()
    private let reportingSource: (any MetricReportingSourceV1)?
    private let logger: DiagnosticsLogger
    private var retainedSummary: MetricKitSummaryV1?
    private var desiredRegistration = false
    private var appliedRegistration = false
    private var isDrivingRegistration = false

    init(logger: DiagnosticsLogger = .live) {
        reportingSource = MetricKitReportingSourceV1.shared
        self.logger = logger
        super.init()
    }

    /// Compatibility/testing seam. Passing nil intentionally disables source
    /// registration; production's no-argument initializer retains the sole
    /// shared MetricKit source above.
    init(manager: MXMetricManager?, logger: DiagnosticsLogger = .live) {
        reportingSource = manager.map(MetricKitReportingSourceV1.init(manager:))
        self.logger = logger
        super.init()
    }

    init(
        reportingSource: (any MetricReportingSourceV1)?,
        logger: DiagnosticsLogger = .live
    ) {
        self.reportingSource = reportingSource
        self.logger = logger
        super.init()
    }

    deinit {
        registrationLock.lock()
        let mustRemove = appliedRegistration
        desiredRegistration = false
        appliedRegistration = false
        registrationLock.unlock()
        if mustRemove { reportingSource?.remove(self) }
    }

    func start() {
        requestRegistration(true)
    }

    func stop() {
        requestRegistration(false)
    }

    /// One caller drives the external source while every caller may update the
    /// desired state. External add/remove is never invoked under our lock, so a
    /// synchronous callback can safely request another transition. The driver
    /// repeats until applied state matches the latest desired state.
    private func requestRegistration(_ desired: Bool) {
        registrationLock.lock()
        desiredRegistration = desired
        guard !isDrivingRegistration else {
            registrationLock.unlock()
            return
        }
        isDrivingRegistration = true
        registrationLock.unlock()

        while true {
            registrationLock.lock()
            guard appliedRegistration != desiredRegistration else {
                isDrivingRegistration = false
                registrationLock.unlock()
                return
            }
            let nextAppliedState = desiredRegistration
            registrationLock.unlock()

            if nextAppliedState {
                reportingSource?.add(self)
            } else {
                reportingSource?.remove(self)
            }

            registrationLock.lock()
            appliedRegistration = nextAppliedState
            registrationLock.unlock()
        }
    }

    func snapshot() -> MetricKitSummaryV1? {
        summaryLock.lock()
        defer { summaryLock.unlock() }
        return retainedSummary
    }

    @discardableResult
    func accept(_ summary: MetricKitSummaryV1) -> Bool {
        guard C54EncryptedPortableEnvelopeMetricKitBoundaryV1.validate(summary) else {
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
        summaryLock.lock()
        defer { summaryLock.unlock() }

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
