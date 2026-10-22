import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23BackupRawDataWireV1Tests: XCTestCase {
    func testCompleteSmallGraphAndBothReversalKindsRoundTripWithoutChangingLegacyBytes() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(semanticRequiredPair: true)
        defer { fixture.removePackages() }
        let legacy = try fixture.validatedPackage()
        let original = legacy.records
        let oldBytes = try BackupCanonicalEncoderV1().encodeRecords(original).data
        let history = try XCTUnwrap(original.mutationHistory)
        XCTAssertTrue(history.receipts.contains { $0.reversalBasisData != nil })
        XCTAssertTrue(history.receipts.contains { $0.semanticReversalData != nil })
        XCTAssertFalse(original.fieldDrafts.isEmpty)

        let plan = try BackupCanonicalEncoderV1().encodeRawDataRecords(original)
        let raw = try rawData(plan)
        let decoded = try BackupCanonicalDecoderV1().decodeRawDataRecordsWithFacts(
            plan.metadata.data, rawData: raw)
        XCTAssertEqual(decoded.records, original)
        XCTAssertEqual(decoded.records.fieldDrafts.map(\.canonicalData), original.fieldDrafts.map(\.canonicalData))
        XCTAssertEqual(decoded.records.mutationHistory, history)
        XCTAssertEqual(decoded.facts.wireFormat, .rawDataV1)
        XCTAssertEqual(decoded.facts.rawDescriptor(matching: original)?.sha256, plan.slots.sha256)
        XCTAssertEqual(decoded.facts.descriptor(matching: original)?.sha256, plan.metadata.sha256)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(decoded.records).data, oldBytes)
        XCTAssertEqual(try BackupCanonicalDecoderV1().decodeRecords(oldBytes), original)
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(plan.metadata.data))
        XCTAssertLessThan(plan.metadata.data.count + raw.count, oldBytes.count)

        try withPackage(records: original, source: legacy.source) { root in
            let admitted = try ValidatedRepetitiveCaptureSourcePackageV2.validate(
                stagedPackageURL: root, using: BackupPackageValidatorV1())
            XCTAssertEqual(admitted.records, original)
            XCTAssertEqual(admitted.recordsJSONSHA256, plan.metadata.sha256)
            XCTAssertEqual(admitted.validatedPackage.manifest.backupSchemaVersion, 5)
            let rawEntry = try XCTUnwrap(admitted.validatedPackage.manifest.entries.first {
                $0.path == BackupRawDataWireV1.rawPath
            })
            XCTAssertEqual(rawEntry.sha256, plan.slots.sha256)
            XCTAssertEqual(rawEntry.byteCount, raw.count)
        }
    }

    func testCallbacksMayDecodeHistoryBeforeDraftsAndReverseHistoryFieldOrder() throws {
        // Schema order is draft, envelope, receipt, basis, semantic. The test
        // decoder intentionally asks Foundation for the exact opposite order.
        let metadata = Data(#"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,2]}}],"mutationHistory":{"receipts":[{"envelopeData":{"$bytes":[2,2]},"receiptData":{"$bytes":[4,2]},"reversalBasisData":{"$bytes":[6,0]},"semanticReversalData":{"$bytes":[6,2]}}]}}"#.utf8)
        let raw = Data([0, 255, 1, 254, 2, 253, 3, 252])
        let resolver = try BackupRawDataWireV1.Resolver(metadata: metadata, raw: raw, maximumByteCount: 4_096)
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .custom { try resolver.decode($0) }
        let value = try decoder.decode(ReverseOrder.self, from: metadata)
        try resolver.validateComplete()
        XCTAssertEqual(value.fieldDrafts[0].canonicalData, Data([0, 255]))
        let receipt = try XCTUnwrap(value.mutationHistory.receipts.first)
        XCTAssertEqual(receipt.envelopeData, Data([1, 254]))
        XCTAssertEqual(receipt.receiptData, Data([2, 253]))
        XCTAssertEqual(receipt.reversalBasisData, Data())
        XCTAssertEqual(receipt.semanticReversalData, Data([3, 252]))
        // Empty optional bytes are a wire distinction, not a valid positive
        // imported canonical reversal receipt. Domain validation still applies.
    }

    func testReferencesCannotEscapeClosedCodingPathsOrDuplicateConsumption() throws {
        struct Unrelated: Decodable { let otherData: Data }
        let unrelated = Data(#"{"otherData":{"$bytes":[0,0]}}"#.utf8)
        let resolver = try BackupRawDataWireV1.Resolver(metadata: unrelated, raw: Data(), maximumByteCount: 1_024)
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .custom { try resolver.decode($0) }
        XCTAssertThrowsError(try decoder.decode(Unrelated.self, from: unrelated))
        let ordinary = try decoder.decode(Unrelated.self, from: Data(#"{"otherData":"AAH/"}"#.utf8))
        XCTAssertEqual(ordinary.otherData, Data([0, 1, 255]))
        try resolver.validateComplete()

        struct RepeatDraft: Decodable {
            enum CodingKeys: String, CodingKey { case canonicalData }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                _ = try c.decode(Data.self, forKey: .canonicalData)
                _ = try c.decode(Data.self, forKey: .canonicalData)
            }
        }
        struct RepeatRoot: Decodable { let fieldDrafts: [RepeatDraft] }
        let metadata = Data(#"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,1]}}]}"#.utf8)
        let once = try BackupRawDataWireV1.Resolver(metadata: metadata, raw: Data([7]), maximumByteCount: 1_024)
        let repeatedDecoder = JSONDecoder()
        repeatedDecoder.dataDecodingStrategy = .custom { try once.decode($0) }
        XCTAssertThrowsError(try repeatedDecoder.decode(RepeatRoot.self, from: metadata))
    }

    func testUnconsumedRawRangesCannotProduceCompleteFacts() throws {
        struct IgnoresData: Decodable { }
        let metadata = Data(#"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,1]}}]}"#.utf8)
        let resolver = try BackupRawDataWireV1.Resolver(metadata: metadata, raw: Data([7]), maximumByteCount: 1_024)
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .custom { try resolver.decode($0) }
        _ = try decoder.decode(IgnoresData.self, from: metadata)
        XCTAssertThrowsError(try resolver.validateComplete())
    }

    func testRangePreflightRejectsAliasOverlapGapTailOverflowAndLegacyTokenBeforeCopies() throws {
        let invalid = [
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,3]}},{"canonicalData":{"$bytes":[0,2]}}]}"#,
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,3]}},{"canonicalData":{"$bytes":[2,3]}}]}"#,
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,3]}},{"canonicalData":{"$bytes":[4,1]}}]}"#,
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,3]}}]}"#,
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[-1,5]}}]}"#,
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,-5]}}]}"#,
            "{\"fieldDrafts\":[{\"canonicalData\":{\"$bytes\":[0,\(Int.max)]}}]}",
            #"{"fieldDrafts":[{"canonicalData":{"$bytes":[0,5,0]}}]}"#,
            #"{"fieldDrafts":[{"canonicalData":"YWJjZGU="}]}"#,
        ]
        for text in invalid {
            XCTAssertThrowsError(try BackupRawDataWireV1.references(
                metadata: Data(text.utf8), rawByteCount: 5, maximumByteCount: 4_096), text)
        }
        let overflow = "{\"fieldDrafts\":[{\"canonicalData\":{\"$bytes\":[0,5]}},{\"canonicalData\":{\"$bytes\":[5,\(Int.max)]}}]}"
        XCTAssertThrowsError(try BackupRawDataWireV1.references(
            metadata: Data(overflow.utf8), rawByteCount: 5, maximumByteCount: 4_096))
    }

    func testCombinedDecodedBudgetCannotBeDoubledByTwoMembers() throws {
        let cap: Int64 = 512 * 1_048_576
        XCTAssertNoThrow(try BackupRawDataWireV1.validateCombinedByteCount(metadata: 16, raw: cap - 16, maximum: cap))
        XCTAssertThrowsError(try BackupRawDataWireV1.validateCombinedByteCount(metadata: 16, raw: cap - 15, maximum: cap))
        XCTAssertThrowsError(try BackupRawDataWireV1.validateCombinedByteCount(metadata: cap, raw: cap, maximum: cap))
        // A caller cannot raise the closed records budget by supplying a larger limit.
        XCTAssertThrowsError(try BackupRawDataWireV1.validateCombinedByteCount(metadata: cap, raw: 1, maximum: Int64.max))
        XCTAssertThrowsError(try BackupRawDataWireV1.validateCombinedByteCount(metadata: Int64.max, raw: 1, maximum: Int64.max))
        XCTAssertThrowsError(try BackupRawDataWireV1.validateCombinedByteCount(metadata: -1, raw: 0, maximum: cap))
    }

    func testCanonicalMetadataRejectsUnknownDuplicateFractionalAndNullReferences() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(semanticRequiredPair: true)
        defer { fixture.removePackages() }
        let records = try fixture.validatedPackage().records
        let plan = try BackupCanonicalEncoderV1().encodeRawDataRecords(records)
        let raw = try rawData(plan)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: plan.metadata.data) as? [String: Any])
        var unknown = object
        unknown["futureWireVersion"] = 99
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRawDataRecordsWithFacts(json(unknown), rawData: raw))
        var drafts = try XCTUnwrap(object["fieldDrafts"] as? [[String: Any]])
        let original = try XCTUnwrap(drafts.first)
        for token in [NSNull(), ["$bytes": [0, 1.5]], ["$bytes": [0, 1], "unknown": 1], "base64"] as [Any] {
            drafts[0]["canonicalData"] = token
            object["fieldDrafts"] = drafts
            XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRawDataRecordsWithFacts(json(object), rawData: raw))
        }
        var extraReferenceKey = try XCTUnwrap(original["canonicalData"] as? [String: Any])
        extraReferenceKey["unknown"] = 1
        drafts[0] = original
        drafts[0]["canonicalData"] = extraReferenceKey
        object["fieldDrafts"] = drafts
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRawDataRecordsWithFacts(json(object), rawData: raw))
        drafts[0] = original
        object["fieldDrafts"] = drafts
        let text = try XCTUnwrap(String(data: json(object), encoding: .utf8))
        let duplicate = "{\"recordsSchemaVersion\":44," + String(text.dropFirst())
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRawDataRecordsWithFacts(Data(duplicate.utf8), rawData: raw))
    }

    func testRawMemberIntegrityMissingExtraAndVersionMismatchesFailPackageAdmission() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(semanticRequiredPair: true)
        defer { fixture.removePackages() }
        let legacy = try fixture.validatedPackage()
        try withPackage(records: legacy.records, source: legacy.source) { root in
            let rawURL = root.appendingPathComponent(BackupRawDataWireV1.rawPath)
            let before = try Data(contentsOf: rawURL)
            var corrupted = before
            corrupted[corrupted.startIndex] ^= 1
            try corrupted.write(to: rawURL)
            XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: root))
            try before.write(to: rawURL)
            try FileManager.default.moveItem(at: rawURL, to: root.appendingPathComponent("unowned.bin"))
            XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: root))
            try FileManager.default.moveItem(at: root.appendingPathComponent("unowned.bin"), to: rawURL)
            let manifestURL = root.appendingPathComponent("manifest.json")
            let original = try Data(contentsOf: manifestURL)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            for version in [4, 6] {
                object["backupSchemaVersion"] = version
                try json(object).write(to: manifestURL)
                XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: root))
            }
            try original.write(to: manifestURL)
            XCTAssertNoThrow(try BackupPackageValidatorV1().validate(stagedPackageURL: root))
            let metadataURL = root.appendingPathComponent("records.json")
            let originalMetadata = try Data(contentsOf: metadataURL)
            let originalManifest = try BackupCanonicalDecoderV1().decodeManifest(original)
            for alias in [false, true] {
                var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: originalMetadata) as? [String: Any])
                if alias {
                    var drafts = try XCTUnwrap(metadata["fieldDrafts"] as? [[String: Any]])
                    XCTAssertGreaterThan(drafts.count, 1)
                    drafts[1]["canonicalData"] = drafts[0]["canonicalData"]
                    metadata["fieldDrafts"] = drafts
                } else {
                    metadata["futureWireVersion"] = 99
                }
                let changed = try json(metadata)
                try changed.write(to: metadataURL)
                let entries = originalManifest.entries.map { entry in
                    entry.path == "records.json"
                        ? V4BackupEntryV1(byteCount: changed.count, mimeType: entry.mimeType,
                            path: entry.path, sha256: KernelCanonicalHashV1.sha256(changed))
                        : entry
                }
                let authenticatedHostile = V4BackupManifestV1(backupSchemaVersion: 5,
                    consumedEvaluationRootIDs: originalManifest.consumedEvaluationRootIDs,
                    declaredPayloadByteCount: entries.reduce(0) { $0 + $1.byteCount }, entries: entries,
                    exportedAt: originalManifest.exportedAt, packs: originalManifest.packs,
                    source: originalManifest.source)
                try BackupCanonicalEncoderV1().encodeManifest(authenticatedHostile).data.write(to: manifestURL)
                // Both outer descriptors are truthful; raw-wire validation must
                // reject the actual alias/noncanonical metadata before facts.
                XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: root))
            }
            try originalMetadata.write(to: metadataURL)
            try original.write(to: manifestURL)
            XCTAssertNoThrow(try BackupPackageValidatorV1().validate(stagedPackageURL: root))
        }
    }

    func testLegacyArchivePathProfileRejectsRawMemberAndNewProfileKeepsTypedPath() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("raw-path-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data([0x5a])
        try payload.write(to: root.appendingPathComponent("payload"))
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let identity = StreamingArchiveRootIdentityV1(
            device: try XCTUnwrap(attributes[.systemNumber] as? NSNumber).uint64Value,
            inode: try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value)
        func entry(_ path: String, mimeType: String) -> StreamingArchiveWriteEntryV1 {
            StreamingArchiveWriteEntryV1(path: path, mimeType: mimeType,
                sourceRootURL: root, sourceRelativePath: "payload",
                expectedSourceRootIdentity: identity,
                expectedUncompressedByteCount: Int64(payload.count),
                expectedContentSHA256: KernelCanonicalHashV1.sha256(payload), compression: .stored)
        }
        // Exercise the writer's existing entry point, which validates the same
        // path/MIME pair before observing the owned source file.
        XCTAssertThrowsError(try StreamingArchiveService().sourceObservation(entry(
            BackupRawDataWireV1.rawPath, mimeType: BackupRawDataWireV1.rawMIMEType))) {
            XCTAssertEqual($0 as? StreamingArchiveFailureV1, .hostilePath)
        }
        let reader = StreamingArchiveService(pathProfile: .backupV5)
        XCTAssertNoThrow(try reader.sourceObservation(entry(BackupRawDataWireV1.rawPath,
            mimeType: BackupRawDataWireV1.rawMIMEType)))
        for path in ["records-data.BIN", "records-data.bin/extra", "../records-data.bin"] {
            XCTAssertThrowsError(try reader.sourceObservation(entry(path,
                mimeType: BackupRawDataWireV1.rawMIMEType))) {
                XCTAssertEqual($0 as? StreamingArchiveFailureV1, .hostilePath)
            }
        }
        XCTAssertThrowsError(try reader.sourceObservation(entry(BackupRawDataWireV1.rawPath,
            mimeType: "application/json"))) {
            XCTAssertEqual($0 as? StreamingArchiveFailureV1, .hostilePath)
        }
    }

    private func rawData(_ plan: BackupRawDataWireV1.Plan) throws -> Data {
        var raw = Data()
        try plan.slots.forEachChunk { raw.append($0) }
        XCTAssertEqual(raw.count, plan.slots.byteCount)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(raw), plan.slots.sha256)
        return raw
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func withPackage(records: V4BackupRecordsV1, source: V4BackupSourceV1,
                             body: (URL) throws -> Void) throws {
        let plan = try BackupCanonicalEncoderV1().encodeRawDataRecords(records)
        let raw = try rawData(plan)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "raw-data-wire-\(UUID().uuidString).fieldrecordbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = [
            V4BackupEntryV1(byteCount: raw.count, mimeType: BackupRawDataWireV1.rawMIMEType,
                path: BackupRawDataWireV1.rawPath, sha256: plan.slots.sha256),
            V4BackupEntryV1(byteCount: plan.metadata.data.count, mimeType: "application/json",
                path: "records.json", sha256: plan.metadata.sha256),
        ].sorted { $0.path < $1.path }
        let manifest = V4BackupManifestV1(backupSchemaVersion: 5, consumedEvaluationRootIDs: [],
            declaredPayloadByteCount: entries.reduce(0) { $0 + $1.byteCount }, entries: entries,
            exportedAt: RepetitiveCaptureSourcePackageFixture.date, packs: [], source: source)
        try plan.metadata.data.write(to: root.appendingPathComponent("records.json"))
        try raw.write(to: root.appendingPathComponent(BackupRawDataWireV1.rawPath))
        try BackupCanonicalEncoderV1().encodeManifest(manifest).data.write(
            to: root.appendingPathComponent("manifest.json"))
        try body(root)
    }

    private struct ReverseOrder: Decodable {
        struct Draft: Decodable { let canonicalData: Data }
        struct History: Decodable {
            struct Receipt: Decodable {
                let envelopeData: Data
                let receiptData: Data
                let reversalBasisData: Data?
                let semanticReversalData: Data?
                enum CodingKeys: String, CodingKey {
                    case envelopeData, receiptData, reversalBasisData, semanticReversalData
                }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    semanticReversalData = try c.decodeIfPresent(Data.self, forKey: .semanticReversalData)
                    reversalBasisData = try c.decodeIfPresent(Data.self, forKey: .reversalBasisData)
                    receiptData = try c.decode(Data.self, forKey: .receiptData)
                    envelopeData = try c.decode(Data.self, forKey: .envelopeData)
                }
            }
            let receipts: [Receipt]
        }
        let fieldDrafts: [Draft]
        let mutationHistory: History
        enum CodingKeys: String, CodingKey { case fieldDrafts, mutationHistory }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mutationHistory = try c.decode(History.self, forKey: .mutationHistory)
            fieldDrafts = try c.decode([Draft].self, forKey: .fieldDrafts)
        }
    }
}

/// Shipping wire assertions and logical checkpoint assertions bind different
/// bytes in envelope5. Keep both proofs when a test inspects the logical JSON.
enum BackupRawDataWireTestSupport {
    static func logicalRecordsData(afterChecking package: ValidatedV4BackupPackageV1,
        file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let encoder = BackupCanonicalEncoderV1()
        let legacy = try encoder.encodeRecords(package.records).data
        let metadata = try XCTUnwrap(package.members["records.json"], file: file, line: line)
        if package.manifest.backupSchemaVersion == 5 {
            let plan = try encoder.encodeRawDataRecords(package.records)
            let raw = try XCTUnwrap(package.members[BackupRawDataWireV1.rawPath], file: file, line: line)
            XCTAssertEqual(metadata, plan.metadata.data, file: file, line: line)
            XCTAssertEqual(raw.count, plan.slots.byteCount, file: file, line: line)
            XCTAssertEqual(KernelCanonicalHashV1.sha256(raw), plan.slots.sha256, file: file, line: line)
            let decoded = try BackupCanonicalDecoderV1().decodeRawDataRecordsWithFacts(metadata, rawData: raw)
            XCTAssertEqual(decoded.records, package.records, file: file, line: line)
            XCTAssertEqual(try encoder.encodeRecords(decoded.records).data, legacy, file: file, line: line)
        } else {
            XCTAssertEqual(metadata, legacy, file: file, line: line)
            XCTAssertEqual(try BackupCanonicalDecoderV1().decodeRecords(metadata), package.records, file: file, line: line)
        }
        return legacy
    }
}
