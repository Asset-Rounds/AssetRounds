import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Pure classifier witnesses with actual canonical-writer history and persisted
/// family snapshots. These are not Router/source-set or physical effect proofs.
@MainActor
final class TemporalCaptureOwnerClassifierTests: XCTestCase {
    typealias Classifier = TemporalNormalizationUncommittedOriginalClassificationV1

    func testWriterProducedQualityOwnsSubjectComparisonAndWaiverAcrossAllHistory() async throws {
        let fixture = try C10ProductionFixture(useActiveSchema: true)
        let primary = fixture.capture(id: "primary")
        let comparison = fixture.capture(id: "comparison", bytes: [71, 72, 73, 74])
        let request = try fixture.request(revision: 1, primary: primary, comparison: comparison,
            collection: [primary, comparison])
        guard case let .assessed(assessment, _) = try fixture.coordinator.assess(request) else {
            return XCTFail("genuine writer did not persist assessment")
        }
        let waiver = try fixture.waiver(for: assessment)
        let history = try fixture.journal.exportSnapshot()
        let first = try XCTUnwrap(history.receipts.first)
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: first.envelopeData)
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: envelope.workspaceID, replicaID: envelope.replicaID)
        let generation = try fixture.writer.currentRevision().generationID
        let records = V4BackupRecordsV1(assets: [], deletionLedger: .empty, evidenceFiles: [], issues: [],
            mutationHistory: history, packets: [],
            recordsSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [],
            partsStockSnapshot: try PartsStockLifecycleAdapterV1(modelContext: fixture.context)
                .snapshotForBackup(workspaceID: fixture.workspaceID),
            evidenceQuality: try fixture.physicalBackupSnapshot())
        let observation = try source(records: records, identity: identity, generation: generation)
        for binding in [primary.evidence, comparison.evidence] {
            let reservation = try reservation(workspace: binding.workspaceID, contentID: binding.contentID,
                digest: binding.contentSHA256)
            let result = try await classify(reservation, sources: [observation])
            let owners = result.blockers.compactMap { blocker -> TemporalNormalizationEvidenceSemanticReferencesV1.Reference? in
                guard case let .retainedOwner(.captureQuality(_, reference)) = blocker else { return nil }
                return reference
            }
            XCTAssertFalse(owners.isEmpty)
            if binding == primary.evidence {
                let waiverOwners = owners.filter { reference in
                    if case let .waiver(value) = reference.owner.value { return value == waiver }
                    return false
                }
                // A lawful waiver must bind the same assessment evidence; a
                // waiver-only physical owner cannot be fabricated by dropping
                // the mandatory assessment. Assert its own origins explicitly.
                XCTAssertTrue(waiverOwners.contains { if case .canonical = $0.owner.origin { return true }; return false })
                XCTAssertTrue(waiverOwners.contains { if case .immutableHistory = $0.owner.origin { return true }; return false })
            }

            XCTAssertTrue(owners.contains { if case .canonical = $0.owner.origin { return true }; return false })
            XCTAssertTrue(owners.contains { if case .immutableHistory = $0.owner.origin { return true }; return false })
        }
        // The unrelated prepared original is not owned merely because the
        // assessment retained an opaque framing-sequence commitment.
        let unrelated = try await classify(reservation(workspace: fixture.workspaceID,
            contentID: "uncommitted-other", digest: KernelCanonicalHashV1.sha256(Data([9]))), sources: [observation])
        guard case .noReferencedContentInSuppliedObservations = unrelated.decision else {
            return XCTFail("unrelated original was blocked by semantic metadata")
        }
        XCTAssertEqual(try fixture.journal.exportSnapshot(), history)
    }

    func testWriterProducedInboxRetainsOriginalAndThumbnailDescriptors() async throws {
        let fixture = try C11Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.generationRoot) }
        let item = try await fixture.item(label: "retained capture")
        _ = try fixture.commit(.putInboxItem(item), mutationID: item.mutationID)
        let history = try fixture.journal.exportSnapshot()
        let records = try inboxRecords(fixture, history: history)
        let observation = try source(records: records, identity: fixture.identity, generation: fixture.generationID)
        let digest = try XCTUnwrap(item.content.digests.digest(for: .sha256)).hexadecimalValue
        let owned = try await classify(reservation(workspace: fixture.workspaceID, contentID: item.content.contentID,
            digest: digest), sources: [observation])
        XCTAssertTrue(owned.blockers.contains { if case .retainedOwner(.survey) = $0 { return true }; return false })
        XCTAssertTrue(owned.blockers.contains { if case .retainedOwner(.workflowFile) = $0 { return true }; return false })
        let wrongDigest = try await classify(reservation(workspace: fixture.workspaceID,
            contentID: item.content.contentID, digest: KernelCanonicalHashV1.sha256(Data([255]))), sources: [observation])
        XCTAssertTrue(wrongDigest.blockers.contains { if case .retainedOwner(.workflowFile) = $0 { return true }; return false })
        XCTAssertTrue(wrongDigest.blockers.contains { if case .retainedOwner(.survey) = $0 { return true }; return false })
        let unrelated = try await classify(reservation(workspace: fixture.workspaceID, contentID: "other-original",
            digest: KernelCanonicalHashV1.sha256(Data([9]))), sources: [observation])
        guard case .noReferencedContentInSuppliedObservations = unrelated.decision else {
            return XCTFail("genuine populated capture family did not close")
        }
        let foreign = try reservation(workspace: WorkspaceID(rawValue: UUID()), contentID: item.content.contentID, digest: digest)
        let foreignResult = try await classify(foreign, sources: [observation])
        XCTAssertFalse(foreignResult.blockers.contains { if case .retainedOwner = $0 { return true }; return false })
        XCTAssertEqual(try fixture.journal.exportSnapshot(), history)
        XCTAssertEqual(try Data(contentsOf: fixture.contentURL(item)), Data([1, 2, 3, 4]))
    }

    func testActualWriterThumbnailOnlyDescriptorOwnsPreparedOriginal() async throws {
        let fixture = try C11Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.generationRoot) }
        let original = try await fixture.item(label: "unrelated original")
        let before = try fixture.journal.exportSnapshot()
        let accepted = try XCTUnwrap(before.receipts.compactMap { row -> CheckEvidenceMutationV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            if case let .acceptCheckEvidence(value) = envelope.command { return value }
            return nil
        }.first)
        let bytes = Data([41, 42, 43, 44]), contentID = UUID().uuidString.lowercased()
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: KernelCanonicalHashV1.sha256(bytes))
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: fixture.workspaceID,
            contentID: contentID, digest: digest, byteLength: Int64(bytes.count), mediaType: "image/jpeg",
            mutationID: MutationIDV1(rawValue: UUID()), createdAt: original.content.createdAt)
        let write = try await fixture.evidenceStore.persistImmutableOriginal(bytes: bytes, request: request)
        try write.validate(request: request, bytes: bytes)
        let evidenceID = UUID()
        _ = try fixture.writer.execute(.acceptCheckEvidence(.init(evidenceID: evidenceID,
            draftID: accepted.draftID, purposeKey: "detail", relativePath: accepted.relativePath,
            mimeType: accepted.mimeType, byteCount: accepted.byteCount, sha256: accepted.sha256,
            thumbnailRelativePath: write.relativePath, thumbnailByteCount: bytes.count,
            thumbnailSHA256: digest.hexadecimalValue, nextDraftStepKey: WorkflowDraftStep.close.rawValue,
            createdAt: accepted.createdAt)), mutationID: MutationIDV1(rawValue: UUID()))
        let history = try fixture.journal.exportSnapshot()
        let observed = try source(records: inboxRecords(fixture, history: history),
            identity: fixture.identity, generation: fixture.generationID)
        let result = try await classify(reservation(workspace: fixture.workspaceID, contentID: contentID,
            digest: digest.hexadecimalValue), sources: [observed])
        let owners = result.blockers.compactMap { blocker -> TemporalNormalizationWorkflowFileReferencesV1.Reference? in
            if case let .retainedOwner(.workflowFile(_, reference)) = blocker { return reference }
            return nil
        }
        XCTAssertEqual(owners.count, 2, "exact current and immutable-history thumbnail owners")
        for reference in owners {
            switch reference.binding {
            case let .evidence(value):
                XCTAssertEqual(value.id, evidenceID)
                XCTAssertNotEqual(value.relativePath, write.relativePath)
                XCTAssertEqual(value.thumbnailRelativePath, write.relativePath)
            case let .acceptedEvidence(value):
                XCTAssertEqual(value.evidenceID, evidenceID)
                XCTAssertNotEqual(value.relativePath, write.relativePath)
                XCTAssertEqual(value.thumbnailRelativePath, write.relativePath)
            default: XCTFail("unexpected descriptor owner")
            }
        }
        XCTAssertEqual(try fixture.journal.exportSnapshot(), history)
        XCTAssertEqual(try Data(contentsOf: fixture.generationRoot.appendingPathComponent(write.relativePath)), bytes)
    }

    private func inboxRecords(_ fixture: C11Fixture, history: MutationHistorySnapshotV1) throws -> V4BackupRecordsV1 {
        let context = fixture.context
        let companions = try ObservationAndTimeRowStoreV1.validatedIndex(in: context)
        let workflows = try context.fetch(FetchDescriptor<WorkflowRecord>()).map { row in
            workflowDTO(row, observationAndTime: try XCTUnwrap(companions[row.id]))
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        return V4BackupRecordsV1(
            assetPlacementEvents: try context.fetch(FetchDescriptor<AssetPlacementEventRow>()).map {
                V5BackupLocationRecordV1(id: $0.id, canonicalData: $0.canonicalData)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: try context.fetch(FetchDescriptor<Asset>()).map {
                .init(id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion, packContentVersion: $0.packContentVersion,
                    label: $0.label, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            deletionLedger: try DeletionLedgerStore(context: context).snapshot(),
            evidenceFiles: try context.fetch(FetchDescriptor<EvidenceFile>()).map {
                .init(id: $0.id, schemaVersion: $0.schemaVersion, recordID: $0.recordID, purposeKey: $0.purposeKey,
                    relativePath: $0.relativePath, mimeType: $0.mimeType, byteCount: $0.byteCount,
                    sha256: $0.sha256, createdAt: $0.createdAt, thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount, thumbnailSHA256: $0.thumbnailSHA256)
            }.sorted { $0.id.uuidString < $1.id.uuidString }, issues: [], mutationHistory: history, packets: [],
            recordsSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion, reports: [],
            sites: try context.fetch(FetchDescriptor<Site>()).map {
                .init(id: $0.id, schemaVersion: $0.schemaVersion, label: $0.label, address: $0.address,
                    timeZoneID: $0.timeZoneID, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString }, workflowRecords: workflows,
            partsStockSnapshot: try PartsStockLifecycleAdapterV1(modelContext: context).snapshotForBackup(workspaceID: fixture.workspaceID),
            fastSurveyInbox: try fixture.physicalBackupSnapshot())
    }
    // Exact incumbent DTO field mapping over actual fixture rows, not a
    // historical row reconstruction or a retained-source authority.
    private func workflowDTO(
        _ value: WorkflowRecord,
        observationAndTime: ObservationAndTimeRow
    ) -> V4BackupWorkflowRecordDTO {
        .init(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID, issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage, state: value.state,
            draftStepKey: value.draftStepKey, startedAt: value.startedAt,
            completedAt: value.completedAt, observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID, utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey, couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID,
            observationBasisV1Data: observationAndTime.observationBasisV1Data,
            temporalContextV1Data: observationAndTime.temporalContextV1Data
        )
    }
    private func source(records: V4BackupRecordsV1, identity: WorkspaceReplicaIdentityV1,
                        generation: UUID) throws -> TemporalNormalizationReferencePreflightV1 {
        let history = try XCTUnwrap(records.mutationHistory), encoder = BackupCanonicalEncoderV1()
        let snapshot = try TemporalNormalizationCanonicalSnapshotV1(source: .init(appBuild: "test", appVersion: "test",
            persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
            replicaID: identity.replicaID.rawValue, recordsSchemaVersion: records.recordsSchemaVersion,
            sourceGenerationID: generation, workspaceID: identity.workspaceID.rawValue), records: records,
            recordsData: encoder.encodeRecords(records).data, semanticRecordsData: encoder.encodeSemanticRecords(records).data,
            history: history, workspaceIdentity: identity, generationID: generation,
            revision: .init(workspaceID: identity.workspaceID, generationID: generation, history: history))
        return try .observe(snapshot: snapshot, history: .init(history: history))
    }
    private func reservation(workspace: WorkspaceID, contentID: String, digest: String) throws -> TemporalEvidencePromotionReservationV1 {
        let now = Date(timeIntervalSince1970: 1_820_000_000), id = UUID(), mutation = try MutationIDV1(rawValue: UUID())
        let request = try CapabilityScratchLeaseRequestV1(leaseID: id, operationID: mutation.rawValue,
            purpose: .capture, requestedByteCount: 1024, createdAt: now, expiresAt: now.addingTimeInterval(60))
        let lease = CapabilityScratchLeaseV1(leaseID: id, purpose: .capture, relativeDirectory: "capture-" + id.uuidString.lowercased())
        let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: lease, mutationID: mutation,
            contentID: contentID, contentSHA256: digest)
        return try .init(workspaceID: workspace, mutationID: mutation, contentID: contentID,
            contentSHA256: digest, binding: binding, state: .prepared)
    }
    private func classify(_ reservation: TemporalEvidencePromotionReservationV1,
                          sources: [TemporalNormalizationReferencePreflightV1]) async throws -> Classifier {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = try TemporalEvidencePromotionRecoveryFileAdapterV1(generationRootURL: root,
            workspaceID: reservation.workspaceID,
            verify: { _, _, _ in throw TemporalEvidenceContractFailureV1.staleSource },
            remove: { _, _, _ in throw TemporalEvidenceContractFailureV1.staleSource })
        try await adapter.prepare(reservation)
        return try .init(reservation: reservation, operational: .prepare(generationRootURL: root), sources: sources)
    }
}
