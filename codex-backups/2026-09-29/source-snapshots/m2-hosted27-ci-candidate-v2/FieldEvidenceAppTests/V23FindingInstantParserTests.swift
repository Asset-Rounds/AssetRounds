import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23FindingInstantParserTests: XCTestCase {
    func testDifferentialSyntaxAndUTF8LimitPreserveOriginalParser() throws {
        // The SDK documents init's GMT default. Do not introduce a local-zone
        // or locale override when retaining the original parser configuration.
        let defaults = ISO8601DateFormatter()
        let zone = try XCTUnwrap(defaults.timeZone)
        for date in [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_780_000_000)] {
            XCTAssertEqual(zone.secondsFromGMT(for: date), 0)
        }
        XCTAssertTrue(Self.originalValidInstant("2026-08-26T20:14:00Z"))
        XCTAssertTrue(Self.originalValidInstant("2026-08-26T20:14:00.125Z"))
        XCTAssertTrue(FindingContractValidationV1.validInstant("2026-08-26T20:14:00Z"))
        XCTAssertTrue(FindingContractValidationV1.validInstant("2026-08-26T20:14:00.125Z"))
        let corpus = Self.syntaxCorpus()
        XCTAssertTrue(corpus.contains { $0.utf8.count == 31 })
        XCTAssertTrue(corpus.contains { $0.utf8.count == 32 })
        XCTAssertTrue(corpus.contains { $0.utf8.count == 33 })
        for value in corpus {
            XCTAssertEqual(FindingContractValidationV1.validInstant(value),
                Self.originalValidInstant(value), String(reflecting: value))
            if value.utf8.count > 32 {
                XCTAssertFalse(FindingContractValidationV1.validInstant(value), String(reflecting: value))
            }
        }
    }

    func testConcurrentMixedParsingPreservesSerialOriginalOutcomes() async {
        let cases = Self.syntaxCorpus().map { (value: $0, expected: Self.originalValidInstant($0)) }
        let completed = expectation(description: "All concurrent instant parser workers return")
        completed.expectedFulfillmentCount = 4
        let failures = InstantMismatchCollector()
        for worker in 0..<4 {
            DispatchQueue.global(qos: .userInitiated).async {
                var mismatches: [String] = []
                // Rotate the same mixed input set so workers alternate between
                // fractional, whole-second and invalid inputs independently.
                for round in 0..<2 {
                    for index in cases.indices {
                        let item = cases[(index + worker * 17 + round * 31) % cases.count]
                        let actual = FindingContractValidationV1.validInstant(item.value)
                        if actual != item.expected {
                            mismatches.append("worker=\(worker) round=\(round) value=\(String(reflecting: item.value))")
                        }
                    }
                }
                failures.append(mismatches)
                completed.fulfill()
            }
        }
        // Completion bound detects a synchronization failure; it is not a
        // performance comparison or a replacement for the native watchdog.
        await fulfillment(of: [completed], timeout: 60)
        XCTAssertEqual(failures.snapshot(), [])
    }

    func testContentReferenceAndDraftCanonicalBytesDigestsAndErrorsStayExact() throws {
        let payload = Data([0x73])
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: Self.hash(payload))
        let digests = try ContentDigestSetV1([digest])
        let workspace = WorkspaceID(rawValue: Self.id(1))
        for instant in Self.edgeCases {
            // These bytes are constructed independently of the production
            // parser/encoder. Borderline syntax keeps the old parser's result.
            let referenceObject: [String: Any] = [
                "schemaVersion": 1, "workspaceID": workspace.rawValue.uuidString.lowercased(),
                "contentID": "content.instant-parser", "byteLength": payload.count,
                "mediaType": "application/octet-stream", "byteRole": "IMMUTABLE_ORIGINAL",
                "digests": ["values": [["algorithm": "SHA256", "hexadecimalValue": digest.hexadecimalValue]]],
                "createdAt": instant,
            ]
            let expectedReference = try Self.canonicalJSON(referenceObject)
            let admittedByOriginal = Self.originalValidInstant(instant)
            if !admittedByOriginal {
                XCTAssertThrowsError(try ContentReferenceV1(
                    workspaceID: workspace.rawValue.uuidString.lowercased(),
                    contentID: "content.instant-parser", byteLength: Int64(payload.count),
                    mediaType: "application/octet-stream", digests: digests,
                    byteRole: .immutableOriginal, createdAt: instant)) {
                    XCTAssertEqual($0 as? ContentContractFailureV1, .invalidValue)
                }
                XCTAssertThrowsError(try JSONDecoder().decode(ContentReferenceV1.self, from: expectedReference)) {
                    XCTAssertEqual($0 as? ContentContractFailureV1, .invalidValue)
                }
                continue
            }
            let reference = try ContentReferenceV1(
                workspaceID: workspace.rawValue.uuidString.lowercased(),
                contentID: "content.instant-parser", byteLength: Int64(payload.count),
                mediaType: "application/octet-stream", digests: digests,
                byteRole: .immutableOriginal, createdAt: instant)
            XCTAssertEqual(reference.createdAt, instant)
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(reference), expectedReference)
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.sha256(reference), Self.hash(expectedReference))
            XCTAssertEqual(try JSONDecoder().decode(ContentReferenceV1.self, from: expectedReference), reference)

            let item = try AttachmentStagingItemV1(
                stageID: Self.id(2), draftID: Self.id(3), workspaceID: workspace,
                attachmentKind: .file, scratchLeaseID: Self.id(4), expectedByteCount: Int64(payload.count),
                actualByteCount: Int64(payload.count), contentDigest: digest, contentReference: reference,
                retryClass: .none, state: .committed, protectionState: .available,
                revision: 1, mutationID: MutationIDV1(rawValue: Self.id(5)))
            var expectedBasis: [String: Any] = [
                "schemaVersion": 1, "stageID": Self.id(2).uuidString, "draftID": Self.id(3).uuidString,
                "workspaceID": ["rawValue": workspace.rawValue.uuidString], "attachmentKind": "FILE",
                "scratchLeaseID": Self.id(4).uuidString, "expectedByteCount": payload.count,
                "actualByteCount": payload.count,
                "contentDigest": ["algorithm": "SHA256", "hexadecimalValue": digest.hexadecimalValue],
                "contentReference": referenceObject, "retryClass": "NONE", "protectionState": "AVAILABLE",
                "state": "COMMITTED", "revision": 1, "mutationID": Self.id(5).uuidString,
            ]
            let expectedDigest = Self.hash(try Self.canonicalJSON(expectedBasis))
            XCTAssertEqual(item.stageSHA256, expectedDigest)
            expectedBasis["stageSHA256"] = expectedDigest
            let expectedBytes = try Self.canonicalJSON(expectedBasis)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(item), expectedBytes)
            let decoded = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: expectedBytes)
            XCTAssertEqual(decoded, item)
            XCTAssertEqual(decoded.contentReference?.createdAt, instant)

            var noncanonical = expectedBytes
            noncanonical.append(0x20)
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: noncanonical)) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .digestMismatch)
            }
            var invalidReference = referenceObject
            invalidReference["createdAt"] = "not-an-instant"
            expectedBasis["contentReference"] = invalidReference
            expectedBasis.removeValue(forKey: "stageSHA256")
            // Rebind the digest honestly, so the nested parser must reject the
            // instant; an unrelated stale-digest failure cannot satisfy this.
            expectedBasis["stageSHA256"] = Self.hash(try Self.canonicalJSON(expectedBasis))
            let invalidBytes = try Self.canonicalJSON(expectedBasis)
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: invalidBytes)) {
                XCTAssertEqual($0 as? ContentContractFailureV1, .invalidValue)
            }
        }
    }
}

private extension V23FindingInstantParserTests {
    // Exact pre-change production implementation retained as the syntax oracle.
    static func originalValidInstant(_ value: String) -> Bool {
        guard value.utf8.count <= 32 else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    static let edgeCases = [
        "2026-08-26T20:14:00Z", "2026-08-26T20:14:00.1Z", "2026-08-26T20:14:00.125Z",
        "2026-08-26T20:14:00.123456Z", "2026-08-26T20:14:00.123456789Z",
        "2026-08-26T20:14:00+00:00", "2026-08-26T20:14:00-07:00", "2026-08-26T20:14:00+05:45",
        "2026-08-26T20:14:00+0000", "2026-08-26T20:14:00.125-07:00", "2026-08-26T20:14:00+14:00",
        "2026-08-26T20:14:00+24:00", "2026-08-26T20:14:00.1234567890Z",
        "2024-02-29T00:00:00Z", "2023-02-29T00:00:00Z", "2000-02-29T00:00:00Z", "1900-02-29T00:00:00Z",
        "0000-01-01T00:00:00Z", "9999-12-31T23:59:59Z", "2026-00-01T00:00:00Z", "2026-13-01T00:00:00Z",
        "2026-01-00T00:00:00Z", "2026-04-31T00:00:00Z", "2026-08-26T24:00:00Z", "2026-08-26T25:00:00Z",
        "2026-08-26T20:60:00Z", "2016-12-31T23:59:60Z", "2026-08-26T20:14:61Z",
        "2026-08-26T20:14:00", "2026-08-26", "20260826T201400Z", "2026-W35-3T20:14:00Z",
        "2026-238T20:14:00Z", "2026-08-26t20:14:00z", "2026-08-26 20:14:00Z", "2026-08-26T20:14:00.Z",
        "2026-08-26T20:14:00,125Z", " 2026-08-26T20:14:00Z", "2026-08-26T20:14:00Z ",
        "2026-08-26T20:14:00Zjunk", "2026-08-26T20:14:00Z\n", "2026-08-26T20:14:00Z\0",
        "", "not-an-instant", "２０２６-08-26T20:14:00Z", "2026-08-26T20:14:00é",
    ]

    static func syntaxCorpus() -> [String] {
        var values = edgeCases
        let seeds = ["2026-08-26T20:14:00Z", "2026-08-26T20:14:00.125Z"]
        for seed in seeds {
            let bytes = Array(seed.utf8)
            for index in bytes.indices {
                for replacement in [UInt8(0x30), 0x39, 0x54, 0x20, 0x00] {
                    var changed = bytes
                    changed[index] = replacement
                    values.append(String(decoding: changed, as: UTF8.self))
                }
            }
        }
        for count in [31, 32, 33] {
            values.append(String(repeating: "x", count: count))
            values.append("2026-08-26T20:14:00Z" + String(repeating: " ", count: count - 20))
        }
        // Character count must not substitute for the existing UTF-8 limit.
        values.append(String(repeating: "é", count: 16))
        values.append(String(repeating: "é", count: 16) + "x")
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static func id(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "91000000-0000-0000-0000-%012d", suffix))!
    }

    static func canonicalJSON(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func hash(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

private final class InstantMismatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String] = []
    func append(_ values: [String]) {
        lock.lock()
        defer { lock.unlock() }
        failures.append(contentsOf: values)
    }
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }
}
