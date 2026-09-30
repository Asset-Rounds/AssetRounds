import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23BackupSchemaAdmissionTests: XCTestCase {
    // Independent expectations: concrete PersistentSchemaV5...V53 plus the
    // corresponding frozen/enrolled records envelopes, not the admission helper.
    private let v4Pairs: [(Int, Int)] = [
        (5, 4), (6, 5), (7, 6), (8, 7), (9, 8), (10, 9), (11, 10), (12, 11),
        (13, 12), (14, 13), (15, 14), (16, 15), (17, 16), (18, 17), (19, 18),
        (20, 19), (21, 20), (22, 21), (23, 22), (24, 23), (25, 24), (26, 25),
        (27, 26), (28, 27), (29, 28), (30, 29), (31, 30), (32, 31), (33, 32),
        (34, 33), (35, 34), (36, 35), (37, 36), (38, 37), (39, 38), (40, 39),
        (41, 40), (42, 41), (43, 42), (44, 43), (45, 44), (46, 45), (47, 46),
        (48, 47), (49, 48), (50, 49), (51, 50), (52, 51), (53, 52),
    ]
    private let workspaceID = UUID(uuidString: "aa000000-0000-4000-8000-000000000001")!
    private let replicaID = UUID(uuidString: "aa000000-0000-4000-8000-000000000002")!
    private let generationID = UUID(uuidString: "aa000000-0000-4000-8000-000000000003")!

    func testEveryEnrolledV4TupleRoundTripsAndValidatesActualPackage() throws {
        for (persistent, version) in v4Pairs {
            try XCTContext.runActivity(named: "V4 persistent \(persistent), records \(version)") { _ in
                let records = try makeRecords(version)
                let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
                XCTAssertEqual(try BackupCanonicalDecoderV1().decodeRecords(bytes), records)
                try withPackage(records: bytes, persistent: persistent, version: version) { url, manifestBytes in
                    let checked = try BackupPackageValidatorV1().validate(stagedPackageURL: url)
                    XCTAssertEqual(checked.records, records)
                    XCTAssertEqual(checked.manifest.source.persistentSchemaVersion, persistent)
                    XCTAssertEqual(checked.manifest.source.recordsSchemaVersion, version)
                    XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("records.json")), bytes)
                    XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), manifestBytes)
                }
            }
        }
    }

    func testLegacyC08RetainsPopulatedMappingProfileAndRejectsForeignWorkspace() throws {
        let budget = try ImportStreamingBudgetV1(maximumSourceBytes: 1_024, maximumRows: 1,
            maximumColumns: 2, maximumCellBytes: 128, maximumScalarsPerCell: 128)
        let release = try ImportSchemaReleaseV1(releaseID: "schema_admission_legacy", release: 1,
            entityKind: .asset, externalKeyColumn: "asset_key", columns: [
                try .init(key: "asset_key", scalar: .identifier, required: true,
                    editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128)
            ], budget: budget)
        let profile = try ImportMappingProfileV1(profileID: generationID,
            workspaceID: WorkspaceID(rawValue: workspaceID), profileName: "Legacy import mapping",
            schemaRelease: release, mappings: [try .init(sourceColumn: "external_key", targetColumn: "asset_key")])
        for (persistent, version) in [(46, 45), (47, 46)] {
            let records = try makeRecords(version, profiles: [profile])
            let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(bytes)
            XCTAssertEqual(decoded.importMappingProfiles, [profile])
            XCTAssertEqual(decoded, records)
            try withPackage(records: bytes, persistent: persistent, version: version) { url, manifestBytes in
                XCTAssertEqual(try BackupPackageValidatorV1().validate(stagedPackageURL: url).records, records)
                let hostile = try mutate(manifestBytes) { object in
                    var source = try XCTUnwrap(object["source"] as? [String: Any])
                    source["workspaceID"] = "aa000000-0000-4000-8000-000000000099"
                    object["source"] = source
                }
                // The stock snapshot also binds workspace; this test proves no
                // legacy package bypass. The direct C08 call isolates its guard.
                try hostile.write(to: url.appendingPathComponent("manifest.json"), options: .atomic)
                XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: url))
                let foreignManifest = try BackupCanonicalDecoderV1().decodeManifest(hostile)
                XCTAssertThrowsError(try C08ImportBulkBackupPackageValidationV1.validate(records, manifest: foreignManifest))
            }
        }
        XCTAssertThrowsError(try C08ImportBulkBackupEnrollmentV1.validate(makeRecords(44, profiles: [profile])))
    }

    func testPackageRejectsEveryMismatchedPairAndUnknownFutureEnvelope() throws {
        for (persistent, version) in v4Pairs {
            let bytes = try BackupCanonicalEncoderV1().encodeRecords(makeRecords(version)).data
            try withPackage(records: bytes, persistent: persistent, version: version) { url, manifestBytes in
                for (foreignPersistent, foreignRecords) in [(persistent + 1, version), (54, 53), (53, 52)] {
                    if foreignPersistent == persistent && foreignRecords == version { continue }
                    let hostile = try mutate(manifestBytes) { object in
                        var source = try XCTUnwrap(object["source"] as? [String: Any])
                        source["persistentSchemaVersion"] = foreignPersistent
                        source["recordsSchemaVersion"] = foreignRecords
                        object["source"] = source
                    }
                    try hostile.write(to: url.appendingPathComponent("manifest.json"), options: .atomic)
                    XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: url))
                    XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("records.json")), bytes)
                }
            }
        }
        for version in [0, -1, 53, Int.max] {
            XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(makeRecords(version)))
        }
    }

    func testNewlyAdmittedEnvelopesRetainLedgerHistoryAndCompanionRejections() throws {
        for version in [42, 45, 46, 47, 48, 49, 50, 51, 52] {
            let original = try makeRecords(version)
            let bytes = try BackupCanonicalEncoderV1().encodeRecords(original).data
            var missing = ["deletionLedger", "mutationHistory", "partsStockSnapshot"]
            if version >= 48 { missing.append("reinspectionExceptionQueue") }
            if version >= 49 { missing.append("entityIdentityResolution") }
            for key in missing {
                let hostile = try mutate(bytes) { $0.removeValue(forKey: key) }
                XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(hostile), "records\(version) missing \(key)")
                // Recompute manifest hash/size to exercise structural validation,
                // rather than failing only at the outer digest.
                try withPackage(records: hostile, persistent: version + 1, version: version) { url, _ in
                    XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: url))
                }
            }
            for key in ["deletionLedger", "mutationHistory"] {
                let hostile = try mutate(bytes) { object in
                    var family = try XCTUnwrap(object[key] as? [String: Any])
                    family["schemaVersion"] = 999
                    object[key] = family
                }
                XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(hostile))
                try withPackage(records: hostile, persistent: version + 1, version: version) { url, _ in
                    XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: url))
                }
            }
            let unknownKey = try mutate(bytes) { $0["futureTruth"] = [] }
            XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(unknownKey))
        }
    }

    func testPopulatedServiceRequestFieldsSurviveEverySuccessorAndRejectBeforeIntroduction() throws {
        let scope = try ServiceRequestScopeSnapshotV1(siteID: generationID,
            siteExpectedRevision: 1, siteSemanticSHA256: String(repeating: "a", count: 64))
        let body = try ServiceRequestSubmissionBodyV1(requestText: "Door needs adjustment",
            statedDate: nil, urgency: .urgentSelfAsserted,
            requester: .init(displayName: "Caller", organization: "Example organization"),
            contact: .init(value: "+1 555 0100", wording: "SELF_ASSERTED_UNVERIFIED"), category: "hardware")
        let request = try ServiceRequestRecordV1(recordID: generationID,
            workspaceID: WorkspaceID(rawValue: workspaceID), source: .phone, scope: scope,
            body: body, mediaManifest: .init(entries: []),
            acceptedSourceBytes: .init(Data("Manual service request".utf8)),
            capabilityAssessment: .init(proofValidity: .unavailable, importEligibility: .unavailable),
            revision: 1, mutationID: .init(rawValue: replicaID),
            recordedAt: Date(timeIntervalSince1970: 1_788_134_400))
        let row = try V38BackupServiceRequestRecordV1(request)
        for version in [38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52] {
            let records = try makeRecords(version, requests: [row])
            let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(bytes)
            XCTAssertEqual(decoded, records, "records\(version)")
            XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeLegacyEmptyServiceRequestRecords(records))
            if version >= 48 {
                let partial = try baselineC52OmissionBytes(bytes,
                    omitting: ["serviceRequestDispositionEvents", "serviceRequestWorkLinkEvents"])
                XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(partial))
            }
            XCTAssertEqual(try decoded.serviceRequests.first?.value().acceptedSourceBytes,
                request.acceptedSourceBytes)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            for key in ["serviceRequests", "serviceRequestDispositionEvents", "serviceRequestWorkLinkEvents"] {
                XCTAssertNotNil(object[key], "records\(version) lost \(key)")
            }
            try withPackage(records: bytes, persistent: version + 1, version: version) { url, _ in
                XCTAssertEqual(try BackupPackageValidatorV1().validate(stagedPackageURL: url).records, records)
            }
        }
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(makeRecords(37, requests: [row])))
    }

    func testHistoricalEmptyC52ShapePreservesPhysicalBytesAndRejectsOtherShapes() throws {
        let keys = ["serviceRequests", "serviceRequestDispositionEvents", "serviceRequestWorkLinkEvents"]
        for version in [48, 49, 50, 51, 52] {
            let records = try makeRecords(version)
            let canonical = try BackupCanonicalEncoderV1().encodeRecords(records).data
            // Independent old-byte oracle: baseline encoder0b9ded1e emits C52
            // keys only for >=38 && <48. All other field encoding is unchanged.
            let legacy = try baselineC52OmissionBytes(canonical, omitting: keys)
            XCTAssertNotEqual(legacy, canonical)
            let decoded = try BackupCanonicalDecoderV1().decodeRecordsWithFacts(legacy)
            XCTAssertEqual(decoded.records, records)
            let descriptor = try XCTUnwrap(decoded.facts.descriptor(matching: records))
            XCTAssertEqual(descriptor.sha256, KernelCanonicalHashV1.sha256(legacy))
            XCTAssertEqual(descriptor.byteCount, legacy.count)
            XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(decoded.records).data, canonical)
            try withPackage(records: legacy, persistent: version + 1, version: version) { url, manifestBytes in
                let checked = try ValidatedRepetitiveCaptureSourcePackageV2.validate(
                    stagedPackageURL: url, using: BackupPackageValidatorV1())
                XCTAssertEqual(checked.records, records)
                XCTAssertEqual(checked.recordsJSONSHA256, KernelCanonicalHashV1.sha256(legacy))
                XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("records.json")), legacy)
                XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), manifestBytes)
            }
            for partial in [[keys[0]], [keys[0], keys[1]]] {
                let hostile = try baselineC52OmissionBytes(canonical, omitting: partial)
                XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(hostile))
            }
            let extra = try mutate(legacy) { $0["futureTruth"] = [] }
            let missingCompanion = try mutate(legacy) { $0.removeValue(forKey: "partsStockSnapshot") }
            let nullFamily = try mutate(legacy) { $0[keys[0]] = NSNull() }
            let duplicateKey = Data(("{\"recordsSchemaVersion\":\(version)," + String(decoding: legacy.dropFirst(), as: UTF8.self)).utf8)
            let noncanonical = legacy + Data([0x20])
            for hostile in [extra, missingCompanion, nullFamily, duplicateKey, noncanonical] {
                XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(hostile))
                try withPackage(records: hostile, persistent: version + 1, version: version) { url, _ in
                    XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: url))
                }
            }
        }
        let before = try BackupCanonicalEncoderV1().encodeRecords(makeRecords(47)).data
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(
            baselineC52OmissionBytes(before, omitting: keys)))
        let current = try BackupCanonicalEncoderV1().encodeRecords(makeRecords(52)).data
        let future = try mutate(baselineC52OmissionBytes(current, omitting: keys)) { $0["recordsSchemaVersion"] = 53 }
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(future))
    }

    private func baselineC52OmissionBytes(_ canonical: Data, omitting keys: [String]) throws -> Data {
        var text = try XCTUnwrap(String(data: canonical, encoding: .utf8))
        for key in keys {
            // Each omitted array is an empty top-level field, followed by a
            // comma in the baseline's lexical order. Preserve every other byte.
            let token = "\"\(key)\":[],"
            XCTAssertEqual(text.components(separatedBy: token).count, 2)
            let range = try XCTUnwrap(text.range(of: token))
            text.removeSubrange(range)
        }
        return Data(text.utf8)
    }

    func testHistoricalManifestTuplesRemainExplicitAndForeignBackupVersionsFail() throws {
        let bytes = Data("{}".utf8)
        for (backup, persistent, records) in [(1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3)] {
            let manifest = makeManifest(bytes, backup: backup, persistent: persistent, version: records)
            let encoded = try BackupCanonicalEncoderV1().encodeManifest(manifest).data
            XCTAssertEqual(try BackupCanonicalDecoderV1().decodeManifest(encoded), manifest)
        }
        for (backup, persistent, records) in [(1, 3, 2), (2, 4, 3), (3, 5, 4), (5, 53, 52), (4, 54, 53)] {
            XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeManifest(
                makeManifest(bytes, backup: backup, persistent: persistent, version: records)))
        }
    }

    private func makeRecords(_ version: Int, profiles: [ImportMappingProfileV1] = [],
        requests: [V38BackupServiceRequestRecordV1] = []) throws -> V4BackupRecordsV1 {
        let stock: PartsStockBackupSnapshotV1? = version >= 40
            ? try .init(workspaceID: WorkspaceID(rawValue: workspaceID), parts: [], locations: [],
                movements: [], uses: [], reversals: [], returns: [], abandonments: []) : nil
        let queue: ReinspectionExceptionQueueBackupSnapshotV1? = version >= 48
            ? try .init(plans: [], attestations: [], acknowledgements: [], receipts: [], effectProvenance: []) : nil
        let identity: EntityIdentityResolutionBackupSnapshotV1? = version >= 49
            ? try .init(workspaceID: WorkspaceID(rawValue: workspaceID), generationID: generationID,
                aliasLinks: [], consolidationReceipts: [], mutationReceipts: []) : nil
        return V4BackupRecordsV1(assets: [], deletionLedger: .empty, evidenceFiles: [], issues: [],
            mutationHistory: .init(workspaceRevision: 0, lastLocalSequence: 0,
                receipts: [], quarantines: [], entityRevisions: []),
            packets: [], recordsSchemaVersion: version, reports: [], sites: [], workflowRecords: [],
            serviceRequests: requests, partsStockSnapshot: stock, importMappingProfiles: profiles,
            reinspectionExceptionQueue: queue, entityIdentityResolution: identity)
    }

    private func makeManifest(_ bytes: Data, backup: Int = 4, persistent: Int, version: Int) -> V4BackupManifestV1 {
        V4BackupManifestV1(backupSchemaVersion: backup, consumedEvaluationRootIDs: [],
            declaredPayloadByteCount: bytes.count,
            entries: [.init(byteCount: bytes.count, mimeType: "application/json", path: "records.json",
                sha256: KernelCanonicalHashV1.sha256(bytes))],
            exportedAt: Date(timeIntervalSince1970: 1_788_134_400), packs: [],
            source: .init(appBuild: "schema-admission-tests", appVersion: "23",
                persistentSchemaVersion: persistent, replicaID: backup == 1 ? nil : replicaID,
                recordsSchemaVersion: version, sourceGenerationID: version >= 5 ? generationID : nil,
                workspaceID: backup == 1 ? nil : workspaceID))
    }

    private func withPackage(records: Data, persistent: Int, version: Int,
        body: (URL, Data) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "schema-admission-\(UUID().uuidString).fieldrecordbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try BackupCanonicalEncoderV1().encodeManifest(
            makeManifest(records, persistent: persistent, version: version)).data
        try records.write(to: root.appendingPathComponent("records.json"), options: .atomic)
        try manifest.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        try body(root, manifest)
    }

    private func mutate(_ data: Data, change: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
