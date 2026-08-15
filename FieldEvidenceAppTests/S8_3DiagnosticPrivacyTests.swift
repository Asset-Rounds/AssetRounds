import Foundation
import XCTest
@testable import FieldEvidenceApp

final class S8_3DiagnosticPrivacyTests: XCTestCase {
    func testCanonicalExportContainsOnlyAllowedControlledValues() async throws {
        let counters = DiagnosticsV1(
            firstSignCreated: 2,
            onboardingCompleted: 1,
            paywallPresented: 3,
            purchaseResult: PurchaseResultHistogram(
                cancelled: 4,
                failed: 5,
                pending: 6,
                unverified: 7,
                verified: 8
            ),
            recheckCompleted: 9,
            reportSaved: 10,
            reportShareSheetPresented: 11,
            schemaVersion: 1
        )
        let summary = MetricKitSummaryV1(
            crashCount: 12,
            hangCount: 13,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: 14,
                from2000Up: 15,
                from500Through999: 16,
                under500: 17
            ),
            peakMemoryBytes: 18
        )
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000.123)
        let service = DiagnosticExportService(
            counters: { counters },
            metricKit: { summary },
            app: {
                DiagnosticAppContextV1(build: "42", version: "1.2.3")
            },
            device: {
                DiagnosticDeviceContextV1(
                    model: "iPhone",
                    osVersion: "26.2"
                )
            },
            clock: { generatedAt }
        )

        let prepared = try await service.prepare()
        let encodedAgain = try DiagnosticExportCanonicalEncoderV1.encode(
            prepared.value
        )
        XCTAssertEqual(prepared.canonicalData, encodedAgain)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: prepared.canonicalData)
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set([
                "app", "counters", "device", "diagnosticSchemaVersion",
                "generatedAt", "metricKit",
            ])
        )
        let metric = try XCTUnwrap(object["metricKit"] as? [String: Any])
        XCTAssertEqual(
            Set(metric.keys),
            Set([
                "crashCount", "hangCount", "launchTimeMilliseconds",
                "peakMemoryBytes",
            ])
        )
        let launch = try XCTUnwrap(
            metric["launchTimeMilliseconds"] as? [String: Any]
        )
        XCTAssertEqual(
            Set(launch.keys),
            Set([
                "from1000Through1999", "from2000Up",
                "from500Through999", "under500",
            ])
        )

        let text = try XCTUnwrap(
            String(data: prepared.canonicalData, encoding: .utf8)
        )
        for forbidden in [
            "Customer North Campus",
            "Monument Sign",
            "123 Main Street",
            "technician note",
            "photos/private.jpg",
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "transaction-123",
            "com.palatis3.fieldrecord.sub.solo.monthly.v1",
            "%PDF-report-content",
            "model.sqlite",
            "FieldEvidenceBackup",
            "authorization-token",
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testBoundedMetricsAndFailedCountersRemainNonAuthoritative() async throws {
        let log = DiagnosticsLogProbe()
        let logger = DiagnosticsLogger { event in
            log.append(event)
        }
        let adapter = MetricKitDiagnosticsAdapter(manager: nil, logger: logger)

        XCTAssertTrue(adapter.accept(MetricKitSummaryV1(
            crashCount: .max,
            hangCount: 2,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: 3,
                from2000Up: 4,
                from500Through999: 5,
                under500: 6
            ),
            peakMemoryBytes: 7
        )))
        XCTAssertTrue(adapter.accept(MetricKitSummaryV1(
            crashCount: 1,
            hangCount: 8,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: 9,
                from2000Up: 10,
                from500Through999: 11,
                under500: 12
            ),
            peakMemoryBytes: 13
        )))
        XCTAssertFalse(adapter.accept(MetricKitSummaryV1(
            crashCount: -1,
            hangCount: 0,
            launchTimeMilliseconds: nil,
            peakMemoryBytes: nil
        )))

        XCTAssertEqual(
            adapter.snapshot(),
            MetricKitSummaryV1(
                crashCount: .max,
                hangCount: 10,
                launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                    from1000Through1999: 12,
                    from2000Up: 14,
                    from500Through999: 16,
                    under500: 18
                ),
                peakMemoryBytes: 13
            )
        )
        XCTAssertEqual(log.snapshot(), [.metricValueDiscarded])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Data("occupied".utf8).write(
            to: root.appendingPathComponent("FieldEvidenceDiagnostics")
        )
        let store = DiagnosticsStore(
            applicationSupportURL: root,
            logger: logger
        )
        await store.increment(.reportSaved)
        let durableCounters = await store.snapshot()
        XCTAssertEqual(durableCounters, .zero)
        XCTAssertTrue(log.snapshot().contains(.countersWriteFailed))

        let minimal = try await DiagnosticExportService(
            counters: { durableCounters },
            metricKit: { nil },
            app: { DiagnosticAppContextV1(build: "1", version: "1.0") },
            device: {
                DiagnosticDeviceContextV1(
                    model: "iPhone",
                    osVersion: "26.2"
                )
            },
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        ).prepare()
        XCTAssertNil(minimal.value.metricKit)
        XCTAssertEqual(minimal.value.counters, .zero)
        let minimalText = try XCTUnwrap(
            String(data: minimal.canonicalData, encoding: .utf8)
        )
        XCTAssertTrue(minimalText.contains(#""metricKit":null"#))
        XCTAssertTrue(minimalText.contains(#""report_saved":0"#))
    }
}

private final class DiagnosticsLogProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var events = [DiagnosticsLogEvent]()

    func append(_ event: DiagnosticsLogEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [DiagnosticsLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
