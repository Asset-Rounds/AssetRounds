import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23BackupManifestMemberTests: XCTestCase {
    func testDraftStagingMemberUsesTypedUUIDsAndHonorsSchemaFloor() throws {
        let draftID = id(10)
        let stageID = id(11)
        let member = entry(
            path: "draft-staging/\(uuid(draftID))/\(uuid(stageID)).bin",
            mimeType: "application/octet-stream"
        )

        XCTAssertNoThrow(try encode(manifest(entries: [member], persistent: 16, records: 15)))
        assertInvalid(manifest(entries: [member], persistent: 15, records: 14))
    }

    func testTemporalOriginalUsesOwnerConstructorAndHonorsSchemaFloor() throws {
        let clip = try C33TemporalEvidenceTestSupport.clip(slot: 410).clip
        let path = try TemporalEvidenceBackupMemberV1.original(for: clip)
        let member = entry(path: path, mimeType: clip.original.mediaType)

        XCTAssertEqual(
            path,
            "content/\(clip.original.workspaceID)/\(clip.original.contentID)/original.bin"
        )
        XCTAssertNoThrow(try encode(manifest(
            entries: [member], persistent: 33, records: 32,
            workspaceID: clip.workspaceID.rawValue
        )))
        assertInvalid(manifest(
            entries: [member], persistent: 32, records: 31,
            workspaceID: clip.workspaceID.rawValue
        ))
    }

    func testC05DerivativeOwnerConstructorsAdmitMarkerAndOriginalAtCurrentSchema() throws {
        let marker = try derivativeMarker()
        let workspace = uuid(marker.workspaceID.rawValue)
        let contentID = marker.result.derivative.contentID
        let directory = "content/\(workspace)/\(contentID)"
        let members = [
            entry(path: "\(directory)/derivative-publication.json", mimeType: "application/json"),
            entry(path: "\(directory)/original.bin", mimeType: marker.result.derivative.mediaType),
        ]

        XCTAssertEqual(marker.metadataMutation.associationEvent.contentID, contentID)
        XCTAssertEqual(marker.result.derivative.workspaceID, workspace)
        XCTAssertNoThrow(try marker.validate())
        XCTAssertNoThrow(try encode(manifest(
            entries: members,
            persistent: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
            records: LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
            workspaceID: marker.workspaceID.rawValue
        )))
        assertInvalid(manifest(
            entries: [members[0]], persistent: 33, records: 32,
            workspaceID: marker.workspaceID.rawValue
        ))
        XCTAssertEqual(C05EvidenceMetadataBackupEnrollmentV1.recordsSchemaVersion, 42)
    }

    func testTypedMemberPathsAndMIMEsRejectMalformedVariantsWithValidControls() throws {
        let workspace = uuid(id(20))
        let draft = uuid(id(21))
        let stage = uuid(id(22))
        let contentID = "manifest-member-content"
        let validDraft = entry(
            path: "draft-staging/\(draft)/\(stage).bin",
            mimeType: "application/octet-stream"
        )
        let validOriginal = entry(
            path: "content/\(workspace)/\(contentID)/original.bin",
            mimeType: "audio/mp4"
        )
        let validMarker = entry(
            path: "content/\(workspace)/\(contentID)/derivative-publication.json",
            mimeType: "application/json"
        )
        XCTAssertNoThrow(try encode(manifest(entries: [validDraft, validOriginal, validMarker])))

        let hostile: [V4BackupEntryV1] = [
            entry(path: "draft-staging/\(draft.uppercased())/\(stage).bin", mimeType: "application/octet-stream"),
            entry(path: "draft-staging/\(draft)/\(stage.uppercased()).bin", mimeType: "application/octet-stream"),
            entry(path: "draft-staging/\(draft)/\(stage).jpg", mimeType: "application/octet-stream"),
            entry(path: "draft-staging/\(draft)/\(stage).bin/extra", mimeType: "application/octet-stream"),
            entry(path: "draft-staging/\(draft)/\(stage).bin", mimeType: "application/json"),
            entry(path: "content/\(workspace.uppercased())/\(contentID)/original.bin", mimeType: "audio/mp4"),
            entry(path: "content/\(workspace)/INVALID/original.bin", mimeType: "audio/mp4"),
            entry(path: "content/\(workspace)//original.bin", mimeType: "audio/mp4"),
            entry(path: "content/\(workspace)/../original.bin", mimeType: "audio/mp4"),
            entry(path: "content/\(workspace)/\(contentID)/original.bin/extra", mimeType: "audio/mp4"),
            entry(path: "content/\(workspace)/\(contentID)/original.jpg", mimeType: "audio/mp4"),
            entry(path: "content/\(workspace)/\(contentID)/original.bin", mimeType: "Audio/MP4"),
            entry(path: "content/\(workspace)/\(contentID)/derivative-publication.json", mimeType: "text/plain"),
            entry(path: "content\\\(workspace)\\\(contentID)\\original.bin", mimeType: "audio/mp4"),
            entry(path: "content/%2e%2e/\(contentID)/original.bin", mimeType: "audio/mp4"),
        ]
        for value in hostile {
            assertInvalid(manifest(entries: [value]), value.path)
        }
    }

    func testTypedMembersRetainManifestHashOrderTotalSourceAndSchemaPredicates() throws {
        let draft = entry(
            path: "draft-staging/\(uuid(id(30)))/\(uuid(id(31))).bin",
            mimeType: "application/octet-stream"
        )
        let valid = manifest(entries: [draft])
        XCTAssertNoThrow(try encode(valid))

        assertInvalid(manifest(entries: [entry(
            path: draft.path, mimeType: draft.mimeType, sha256: String(repeating: "A", count: 64)
        )]))
        assertInvalid(manifest(entries: [entry(
            path: draft.path, mimeType: draft.mimeType, sha256: String(repeating: "a", count: 63)
        )]))
        assertInvalid(manifest(entries: [entry(
            path: draft.path, mimeType: draft.mimeType, sha256: String(repeating: "g", count: 64)
        )]))
        assertInvalid(manifest(entries: [draft, draft]))
        let unsorted = manifest(entries: [draft], sortEntries: false)
        XCTAssertNotEqual(unsorted.entries, valid.entries)
        assertInvalid(unsorted)
        assertInvalid(manifest(entries: [draft], declaredPayloadByteCount: 99))
        assertInvalid(manifest(entries: [draft], persistent: 52, records: 51))
        assertInvalid(manifest(entries: [draft], workspaceID: zeroUUID))
        assertInvalid(manifest(entries: [draft], replicaID: workspaceID))
        assertInvalid(manifest(entries: [draft], sourceGenerationID: nil))
        assertInvalid(manifest(entries: [draft], appBuild: ""))
    }

    func testDecoderRoundTripsTypedMembersAndRejectsUnknownFields() throws {
        let clip = try C33TemporalEvidenceTestSupport.clip(slot: 420).clip
        let temporal = entry(
            path: try TemporalEvidenceBackupMemberV1.original(for: clip),
            mimeType: clip.original.mediaType
        )
        let draft = entry(
            path: "draft-staging/\(uuid(id(40)))/\(uuid(id(41))).bin",
            mimeType: "application/octet-stream"
        )
        let marker = try derivativeMarker()
        let derivativeMarkerEntry = entry(
            path: "content/\(uuid(marker.workspaceID.rawValue))/\(marker.result.derivative.contentID)/derivative-publication.json",
            mimeType: "application/json"
        )
        let value = manifest(
            entries: [draft, temporal, derivativeMarkerEntry],
            workspaceID: clip.workspaceID.rawValue
        )
        let bytes = try encode(value)
        XCTAssertEqual(try BackupCanonicalDecoderV1().decodeManifest(bytes), value)

        let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: originalObject, options: options), bytes)
        var topLevel = originalObject
        topLevel["unknown"] = true
        assertInvalidDecode(try JSONSerialization.data(withJSONObject: topLevel, options: options))

        var unknownEntry = originalObject
        var entries = try XCTUnwrap(unknownEntry["entries"] as? [[String: Any]])
        entries[0]["unknown"] = true
        unknownEntry["entries"] = entries
        assertInvalidDecode(try JSONSerialization.data(withJSONObject: unknownEntry, options: options))
    }
}

private extension V23BackupManifestMemberTests {
    static let workspaceID = UUID(uuidString: "ab000000-0000-4000-8000-000000000001")!
    static let replicaID = UUID(uuidString: "ab000000-0000-4000-8000-000000000002")!
    static let generationID = UUID(uuidString: "ab000000-0000-4000-8000-000000000003")!
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static let instant = "2027-09-04T00:00:00Z"
    static let date = Date(timeIntervalSince1970: 1_820_001_600)

    var workspaceID: UUID { Self.workspaceID }
    var zeroUUID: UUID { Self.zeroUUID }

    func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "ab000000-0000-4000-8000-%012x", slot))!
    }

    func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    func entry(
        path: String,
        mimeType: String,
        byteCount: Int = 1,
        sha256: String = String(repeating: "a", count: 64)
    ) -> V4BackupEntryV1 {
        V4BackupEntryV1(byteCount: byteCount, mimeType: mimeType, path: path, sha256: sha256)
    }

    func manifest(
        entries additions: [V4BackupEntryV1],
        persistent: Int = LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
        records: Int = LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
        sortEntries: Bool = true,
        declaredPayloadByteCount: Int? = nil,
        workspaceID: UUID? = Self.workspaceID,
        replicaID: UUID? = Self.replicaID,
        sourceGenerationID: UUID? = Self.generationID,
        appBuild: String = "manifest-member-tests"
    ) -> V4BackupManifestV1 {
        var entries = [entry(path: "records.json", mimeType: "application/json")] + additions
        if sortEntries {
            entries.sort { $0.path < $1.path }
        }
        return V4BackupManifestV1(
            backupSchemaVersion: 4,
            consumedEvaluationRootIDs: [],
            declaredPayloadByteCount: declaredPayloadByteCount
                ?? entries.reduce(0) { $0 + $1.byteCount },
            entries: entries,
            exportedAt: Self.date,
            packs: [],
            source: V4BackupSourceV1(
                appBuild: appBuild,
                appVersion: "1",
                persistentSchemaVersion: persistent,
                replicaID: replicaID,
                recordsSchemaVersion: records,
                sourceGenerationID: sourceGenerationID,
                workspaceID: workspaceID
            )
        )
    }

    func encode(_ value: V4BackupManifestV1) throws -> Data {
        try BackupCanonicalEncoderV1().encodeManifest(value).data
    }

    func assertInvalid(
        _ value: V4BackupManifestV1,
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try encode(value), context, file: file, line: line) {
            XCTAssertEqual(
                $0 as? BackupCanonicalEncodingErrorV1,
                .invalidManifest,
                context,
                file: file,
                line: line
            )
        }
    }

    func assertInvalidDecode(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try BackupCanonicalDecoderV1().decodeManifest(data),
            file: file,
            line: line
        ) {
            XCTAssertEqual(
                $0 as? BackupCanonicalDecodingErrorV1,
                .invalidManifest,
                file: file,
                line: line
            )
        }
    }

    func contentReference(
        workspaceID: WorkspaceID,
        contentID: String,
        bytes: Data,
        role: ContentByteRoleV1
    ) throws -> ContentReferenceV1 {
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: KernelCanonicalHashV1.sha256(bytes)
        )
        return try ContentReferenceV1(
            workspaceID: uuid(workspaceID.rawValue),
            contentID: contentID,
            byteLength: Int64(bytes.count),
            mediaType: "image/png",
            digests: ContentDigestSetV1([digest]),
            byteRole: role,
            createdAt: Self.instant
        )
    }

    func derivativeMarker() throws -> EvidenceDerivativePublicationMarkerV1 {
        let workspace = WorkspaceID(rawValue: id(50))
        let source = try contentReference(
            workspaceID: workspace,
            contentID: "manifest-member-source",
            bytes: Data([0x01, 0x02]),
            role: .immutableOriginal
        )
        let derivativeBytes = Data([0x03, 0x04, 0x05])
        let derivative = try contentReference(
            workspaceID: workspace,
            contentID: "manifest-member-derivative",
            bytes: derivativeBytes,
            role: .derivative
        )
        let sourceDigest = try XCTUnwrap(source.digests.digest(for: .sha256))
        let derivativeDigest = try XCTUnwrap(derivative.digests.digest(for: .sha256))
        let requestSHA256 = String(repeating: "b", count: 64)
        let provenance = try ContentDerivativeProvenanceV1(
            provenanceID: "manifest-member-provenance",
            workspaceID: source.workspaceID,
            sources: [try ContentSourceBindingV1(contentID: source.contentID, digest: sourceDigest)],
            derivativeContentID: derivative.contentID,
            derivativeDigest: derivativeDigest,
            transform: .sequence(try SequenceDerivativeV1(
                assemblerID: "manifest-member-assembler",
                assemblerVersion: "1",
                orderedSourceCount: 1
            )),
            metadataSanitizerID: "manifest-member-sanitizer",
            metadataSanitizerVersion: "1",
            createdAt: Self.instant
        )
        let result = try EvidenceCurationDerivativeResultV1(
            requestSHA256: requestSHA256,
            derivative: derivative,
            provenance: provenance,
            orderedSources: [source]
        )
        let target = try EvidenceAssociationTargetV1(
            workspaceID: source.workspaceID,
            kind: .inspectionNode,
            targetID: "manifest-member-target",
            targetRevision: 1
        )
        let mutationID = try MutationIDV1(rawValue: id(51))
        let association = try EvidenceAssociationV1(
            associationEventID: "manifest-member-association",
            workspaceID: source.workspaceID,
            evidenceID: "manifest-member-evidence",
            expectedEvidenceRevision: 0,
            resultingEvidenceRevision: 1,
            mutationID: uuid(mutationID.rawValue),
            action: .assigned,
            contentID: derivative.contentID,
            target: target,
            actorID: "manifest-member-actor",
            reason: "Publish the owned derivative member.",
            effectiveAt: Self.instant
        )
        let reviewer = try C26SurveySessionTestSupport.actor(workspaceID: workspace, slot: 520)
        let caption = try EvidenceReviewedCaptionV1(
            text: "Owned derivative",
            provenance: .userAuthored,
            reviewer: reviewer,
            reviewedAt: reviewer.capturedAt
        )
        let item = try EvidenceSequenceItemV1(
            evidenceID: association.evidenceID,
            contentID: derivative.contentID,
            role: .detail,
            caption: caption,
            ordinal: 0,
            target: target,
            association: association
        )
        let sequence = try EvidenceSequenceV1(
            sequenceID: id(52),
            workspaceID: workspace,
            target: target,
            policy: try EvidenceCurationPolicyV1(policyID: id(53), workspaceID: workspace),
            orderedItems: [item],
            revision: 1,
            mutationID: mutationID
        )
        let metadataMutation = try EvidenceMetadataMutationV1(
            workspaceID: workspace,
            mutationID: mutationID,
            expectedSequenceRevision: 0,
            associationEvent: association,
            sequenceSuccessor: sequence
        )
        return try EvidenceDerivativePublicationMarkerV1(package: EvidenceDerivativeStorePackageV1(
            operationID: "manifest-member-operation",
            workspaceID: workspace,
            requestSHA256: requestSHA256,
            orderedSources: [source],
            derivativeBytes: derivativeBytes,
            result: result,
            metadataMutation: metadataMutation
        ))
    }
}
