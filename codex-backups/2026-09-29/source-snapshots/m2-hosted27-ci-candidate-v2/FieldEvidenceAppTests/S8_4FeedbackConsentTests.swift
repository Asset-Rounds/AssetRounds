import Foundation
import XCTest
@testable import FieldEvidenceApp

final class S8_4FeedbackConsentTests: XCTestCase {
    func testAttachAndDontAttachUseExactReviewedBytesAndSafeEditableContext() async throws {
        let prepared = try await makeDiagnostic()
        let configuration = FeedbackConfigurationV1.uiTestFixture

        let attached = try FeedbackMailDraftBuilderV1.make(
            configuration: configuration,
            diagnostic: prepared,
            attachmentChoice: .attach
        )
        let detached = try FeedbackMailDraftBuilderV1.make(
            configuration: configuration,
            diagnostic: prepared,
            attachmentChoice: .doNotAttach
        )

        XCTAssertEqual(attached.recipients, ["support@example.invalid"])
        XCTAssertEqual(attached.subject, "App feedback")
        XCTAssertEqual(attached.body, detached.body)
        XCTAssertEqual(
            attached.body,
            """
            App version: 1.2.3 (42)
            Device: iPhone
            OS: iOS 26.2

            Feedback:

            """
        )
        XCTAssertEqual(attached.attachments.count, 1)
        XCTAssertEqual(
            attached.attachments.first,
            FeedbackMailAttachmentV1(
                data: prepared.canonicalData,
                filename: "field-record-diagnostics.json",
                mimeType: "application/json"
            )
        )
        XCTAssertTrue(detached.attachments.isEmpty)
        XCTAssertEqual(detached.recipients, attached.recipients)
        XCTAssertEqual(detached.subject, attached.subject)

        for forbidden in [
            "Customer North Campus",
            "123 Main Street",
            "technician note",
            "photos/private.jpg",
            "transaction-123",
            "report-content",
        ] {
            XCTAssertFalse(attached.body.contains(forbidden), forbidden)
        }

        var altered = prepared.canonicalData
        altered.append(0x20)
        let tampered = PreparedDiagnosticExportV1(
            value: prepared.value,
            canonicalData: altered
        )
        XCTAssertThrowsError(try FeedbackMailDraftBuilderV1.make(
            configuration: configuration,
            diagnostic: tampered,
            attachmentChoice: .attach
        )) { error in
            XCTAssertEqual(
                error as? FeedbackMailDraftError,
                .invalidAuthority
            )
        }
    }

    func testConfigurationAndUnavailableFallbackFailClosedWithoutTransport() async throws {
        let prepared = try await makeDiagnostic()
        let valid = FeedbackConfigurationV1.uiTestFixture
        XCTAssertEqual(valid.validatedSupportAddress, "support@example.invalid")
        XCTAssertEqual(valid.route(mailComposerAvailable: true), .composer)
        XCTAssertEqual(
            valid.route(mailComposerAvailable: false),
            .unavailableFallback
        )

        let invalidAddresses: [String?] = [
            nil,
            "",
            " support@example.invalid",
            "support@example.invalid ",
            "support@@example.invalid",
            "support@example",
            "support@-example.invalid",
            "support@example..invalid",
            "support\n@example.invalid",
        ]
        for address in invalidAddresses {
            let configuration = FeedbackConfigurationV1(
                supportAddress: address
            )
            XCTAssertNil(configuration.validatedSupportAddress)
            XCTAssertEqual(
                configuration.route(mailComposerAvailable: true),
                .blocked
            )
            XCTAssertEqual(
                configuration.route(mailComposerAvailable: false),
                .blocked
            )
            XCTAssertThrowsError(try FeedbackMailDraftBuilderV1.make(
                configuration: configuration,
                diagnostic: prepared,
                attachmentChoice: .doNotAttach
            )) { error in
                XCTAssertEqual(
                    error as? FeedbackMailDraftError,
                    .invalidAuthority
                )
            }
        }
    }

    private func makeDiagnostic() async throws -> PreparedDiagnosticExportV1 {
        try await DiagnosticExportService(
            counters: { .zero },
            metricKit: { nil },
            app: {
                DiagnosticAppContextV1(build: "42", version: "1.2.3")
            },
            device: {
                DiagnosticDeviceContextV1(
                    model: "iPhone",
                    osVersion: "26.2"
                )
            },
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        ).prepare()
    }
}
