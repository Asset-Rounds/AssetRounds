import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private enum C53AssetServiceReliabilityBoundary_V10_02MutationEnvelopeReceiptTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

/// Compiler regressions exercise the production adapter against the complete
/// current schema; the older journal fixtures below retain their own scope.
@MainActor
private final class CompilerWriterAdmissionHarnessV1 {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let context: ModelContext
    let identity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let assetID: UUID
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1

    init(
        workspaceID: WorkspaceID = WorkspaceID(rawValue: UUID()),
        generationID: UUID = UUID(), seedAsset: Bool = false,
        seedReport: Report? = nil,
        failureBoundary: MutationJournalFaultBoundaryV1? = nil,
        generationRootURL: URL? = nil,
        expectedRootIdentity: ReportPDFAnchoredFile.RootIdentity? = nil
    ) throws {
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration(
            "CompilerWriterAdmission", schema: schema, isStoredInMemoryOnly: true,
            allowsSave: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let assetID = UUID()
        var seededModel = false
        if seedAsset {
            let site = Site(label: "Writer admission site", timeZoneID: "UTC")
            context.insert(site)
            context.insert(Asset(id: assetID, siteID: site.id, packID: "com.field-evidence.c39",
                packSchemaVersion: 1, packContentVersion: 1, label: "Writer admission asset"))
            seededModel = true
        }
        if let seedReport {
            context.insert(seedReport)
            seededModel = true
        }
        if seededModel {
            try context.save()
        }
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: UUID()))
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: identity, generationID: generationID,
            failureInjection: failureBoundary.map {
                MutationJournalFailureInjectionV1(failOnceAt: $0)
            }
        )
        let instanceID = UUID()
        self.container = container; self.context = context; self.identity = identity
        self.generationID = generationID; self.assetID = assetID; self.journal = journal
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: instanceID),
            clock: MutationJournalFixedClockV1(), idSource: MutationJournalFixedIDSourceV1(value: instanceID),
            fileAuthority: MutationJournalFileAuthorityV1(), adapter: WorkspaceWriterAdapterV1(
                modelContext: context, generationRootURL: generationRootURL,
                expectedRootIdentity: expectedRootIdentity
            ),
            journalStore: journal)
    }

    func makeWriter(instanceID: UUID) throws -> WorkspaceWriterV1 {
        try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: instanceID),
            clock: MutationJournalFixedClockV1(), idSource: MutationJournalFixedIDSourceV1(value: instanceID),
            fileAuthority: MutationJournalFileAuthorityV1(), adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: journal)
    }

    func expected(_ entities: [WorkspaceEntityRevisionV1], generationID: UUID? = nil,
                  workspaceRevision: UInt64? = nil, writerInstanceID: UUID? = nil) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision()
        return try WorkspaceExpectedRevisionV1(workspaceID: identity.workspaceID,
            generationID: generationID ?? current.generationID, writerInstanceID: writerInstanceID ?? current.writerInstanceID,
            workspaceRevision: workspaceRevision ?? current.revision, entityRevisions: entities)
    }

    func experienceCommand(generationID: UUID? = nil, workspaceRevision: UInt64? = nil) throws -> WorkspaceExperienceMutationCommandV1 {
        let mutationID = try MutationIDV1(rawValue: UUID())
        let template = try StarterWorkspaceTemplateReleaseV1(templateID: UUID(), release: 1,
            titleKey: "workspace.starter.practice.title", packageReleaseIDs: ["shipping.illuminated-sign.v1"],
            practiceWatermark: "PRACTICE — NOT FOR FIELD USE")
        let plan = try StarterWorkspaceInstallPlanV1(planID: UUID(), workspaceID: identity.workspaceID,
            template: template, mutationID: mutationID, requestedAt: Self.date,
            explicitUserRequest: true, destinationWasEmpty: true)
        let revision = try workspaceRevision ?? writer.currentRevision().revision
        let receipt = try StarterWorkspaceInstallReceiptV1(receiptID: UUID(), plan: plan,
            resultingWorkspaceRevision: revision + 1, installedAt: Self.date.addingTimeInterval(1), disposition: .committed)
        let provenance = try PracticeWorkspaceProvenanceV1(provenanceID: UUID(), plan: plan, receipt: receipt, revision: 1)
        let target = try WorkspaceEntityIdentityV1(kind: .practiceWorkspaceProvenance, id: provenance.provenanceID)
        return try WorkspaceExperienceMutationCommandV1(workspaceID: identity.workspaceID,
            expectedRevision: MutationPortableExpectedRevisionV1(expected([.init(identity: target, revision: 0)],
                generationID: generationID, workspaceRevision: revision)),
            mutationID: mutationID, plan: plan, installReceipt: receipt, provenance: provenance)
    }

    func evidenceContext() throws -> EvidenceContextV1 {
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: identity.workspaceID,
            displayName: "Writer context recorder")
        let recordedBy = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: identity.workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: actor.displayName, capturedAt: Self.date)
        let temporal = try TemporalContextV1(occurredAtUTC: Self.date, recordedAtUTC: Self.date,
            localDate: "2027-01-15", localTime: "08:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        return try EvidenceContextV1(contextID: UUID(), workspaceID: identity.workspaceID,
            evidenceID: "writer.context.evidence", evidenceSHA256: String(repeating: "f", count: 64),
            evidenceRevision: 1, assetID: assetID, assetRevision: 1, temporalContext: temporal,
            userObserved: UserObservedEvidenceContextV1(condition: .unknown, observationNoteCode: "WRITER_CONTEXT"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: MutationIDV1(rawValue: UUID()), recordedBy: recordedBy, recordedAt: Self.date.addingTimeInterval(1))
    }

    struct StorageSnapshot: Equatable {
        let history: MutationHistorySnapshotV1
        let mutableCheckpoint: String?
        let provenance: [Data]
        let parts: [Data]
        let contexts: [Data]
        let assetProducts: [Data]
        let pendingChanges: Bool
    }

    func snapshot() throws -> StorageSnapshot {
        let history = try journal.exportSnapshot()
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
        return try StorageSnapshot(history: history, mutableCheckpoint: state.mutableSemanticSHA256,
            provenance: context.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()).map(\.canonicalData).sorted(by: { $0.lexicographicallyPrecedes($1) }),
            parts: context.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).map(\.canonicalData).sorted(by: { $0.lexicographicallyPrecedes($1) }),
            contexts: context.fetch(FetchDescriptor<EvidenceContextRow>()).map(\.canonicalData).sorted(by: { $0.lexicographicallyPrecedes($1) }),
            assetProducts: context.fetch(FetchDescriptor<AssetProductIdentityRow>()).map(\.canonicalData).sorted(by: { $0.lexicographicallyPrecedes($1) }),
            pendingChanges: context.hasChanges)
    }
}

final class V10_02MutationEnvelopeReceiptTests: XCTestCase {
    @MainActor
    func testWorkspaceExperiencePortableAuthorityRebindsAndReplaysOneCanonicalEffect() throws {
        let harness = try CompilerWriterAdmissionHarnessV1()
        let command = try harness.experienceCommand()
        let originalCommand = try WorkspaceMutationCanonicalV1.data(command)
        let oldRuntimeID = try harness.writer.currentRevision().writerInstanceID
        let rebound = try harness.makeWriter(instanceID: UUID())
        XCTAssertNotEqual(try rebound.currentRevision().writerInstanceID, oldRuntimeID)

        let receipt = try rebound.commitWorkspaceExperience(command)
        try receipt.validate(command: command)
        let receiptBytes = try WorkspaceMutationCanonicalV1.data(receipt)
        let durable = try XCTUnwrap(harness.journal.receipt(mutationID: command.mutationID))
        XCTAssertEqual(durable.expectedRevision, command.expectedRevision)
        XCTAssertEqual(durable.resultingRevision.workspaceRevision, 1)
        let persisted = try XCTUnwrap(harness.context.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()).first)
        XCTAssertEqual(try persisted.value(), command.provenance)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        let snapshot = try harness.snapshot()

        let restarted = try harness.makeWriter(instanceID: UUID())
        let replayed = try restarted.commitWorkspaceExperience(command)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(replayed), receiptBytes)
        XCTAssertEqual(try harness.snapshot(), snapshot)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(command), originalCommand)
        let wire = try XCTUnwrap(String(data: originalCommand, encoding: .utf8))
        XCTAssertFalse(wire.contains("writerInstanceID"))
        XCTAssertFalse(wire.lowercased().contains(oldRuntimeID.uuidString.lowercased()))
        XCTAssertFalse(try XCTUnwrap(String(data: receiptBytes, encoding: .utf8)).contains("writerInstanceID"))
        try harness.journal.validateAll()
    }

    @MainActor
    func testWorkspaceExperienceStaleForeignAndWrongRuntimeAuthorityHaveZeroEffects() throws {
        let harness = try CompilerWriterAdmissionHarnessV1()
        let before = try harness.snapshot()
        let foreign = try harness.experienceCommand(generationID: UUID())
        XCTAssertThrowsError(try harness.writer.commitWorkspaceExperience(foreign)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongGeneration)
        }
        XCTAssertEqual(try harness.snapshot(), before)
        let stale = try harness.experienceCommand(workspaceRevision: 1)
        XCTAssertThrowsError(try harness.writer.commitWorkspaceExperience(stale)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        XCTAssertEqual(try harness.snapshot(), before)

        let command = try harness.experienceCommand()
        let wrongRuntime = try harness.expected(command.expectedRevision.entityRevisions, writerInstanceID: UUID())
        XCTAssertThrowsError(try harness.writer.execute(.init(mutationID: command.mutationID,
            expectedRevision: wrongRuntime, command: .applyWorkspaceExperience(command)))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWriterInstance)
        }
        XCTAssertEqual(try harness.snapshot(), before)
        let differentPortable = try harness.expected(command.expectedRevision.entityRevisions, workspaceRevision: 1)
        XCTAssertThrowsError(try harness.writer.execute(.init(mutationID: command.mutationID,
            expectedRevision: differentPortable, command: .applyWorkspaceExperience(command)))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try harness.snapshot(), before)
        try harness.journal.validateAll()
    }

    @MainActor
    func testArchivedPartUpsertCannotBypassArchiveProofOrRejectAssetSemantics() throws {
        let harness = try CompilerWriterAdmissionHarnessV1(seedAsset: true)
        let archived = try LocalPartDefinitionV1(partID: UUID(), workspaceID: harness.identity.workspaceID,
            displayName: "Archived without retirement proof", canonicalUnit: .each, archived: true,
            revision: 1, mutationID: MutationIDV1(rawValue: UUID()))
        let before = try harness.snapshot()
        XCTAssertThrowsError(try harness.writer.commitPartsStock(.upsertPart(archived))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try harness.snapshot(), before)
        let ordinary = try LocalPartDefinitionV1(partID: UUID(), workspaceID: harness.identity.workspaceID,
            displayName: "Ordinary part", canonicalUnit: .each, archived: false,
            revision: 1, mutationID: MutationIDV1(rawValue: UUID()))
        _ = try harness.writer.commitPartsStock(.upsertPart(ordinary))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).map { try $0.value() }, [ordinary])

        let semanticMutationID = try MutationIDV1(rawValue: UUID())
        let identifier = AssetProductIdentifierV1(kind: .serial, value: "SN-WRITER-1",
            normalizedComparisonValue: "sn-writer-1", issuer: "local-record", provenance: .humanRecorded,
            reviewState: .reviewedAsRecorded, effectiveFrom: CompilerWriterAdmissionHarnessV1.date, effectiveUntil: nil)
        let product = try AssetProductIdentityV1(identityID: UUID(), workspaceID: harness.identity.workspaceID,
            assetID: harness.assetID, identifiers: [identifier], predecessorIdentityID: nil,
            revision: 1, mutationID: semanticMutationID, recordedAt: CompilerWriterAdmissionHarnessV1.date)
        let semantic = try AssetSemanticsMutationV1(workspaceID: harness.identity.workspaceID,
            assetID: harness.assetID, expectedAssetRevision: 0, mutationID: semanticMutationID,
            operation: .appendProductIdentity, productIdentity: product)
        let expected = try harness.expected([.init(identity: semantic.affectedIdentity, revision: 0)])
        _ = try harness.writer.execute(.init(mutationID: semanticMutationID,
            expectedRevision: expected, command: .applyAssetSemantics(semantic)))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<AssetProductIdentityRow>()).map { try $0.value() }, [product])
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<LocalPartDefinitionRowV1>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try harness.writer.currentRevision().revision, 2)
        XCTAssertFalse(harness.context.hasChanges)
        try harness.journal.validateAll()
    }

    @MainActor
    func testThrowingMultiAndSingleIdentityWriterGuardsPersistOnlyMatchingCommands() throws {
        let fixture = try C05WriterMutationFixtureV1.make()
        let harness = try CompilerWriterAdmissionHarnessV1(workspaceID: fixture.workspaceID)
        let targets = try fixture.mutation.concurrencyIdentities
        XCTAssertEqual(targets.count, 2)
        let before = try harness.snapshot()
        let mismatch = try harness.expected(targets.map { .init(identity: $0, revision: 1) })
        XCTAssertThrowsError(try harness.writer.execute(.init(mutationID: fixture.mutation.mutationID,
            expectedRevision: mismatch, command: .applyEvidenceMetadata(fixture.mutation)))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try harness.snapshot(), before)
        let multipleReceipt = try harness.writer.commitEvidenceMetadata(fixture.mutation)
        XCTAssertEqual(multipleReceipt.mutationReceipt.postImages.count, 2)
        XCTAssertEqual(try harness.writer.evidenceAssociationHistory(workspaceID: fixture.workspaceID,
            evidenceID: fixture.association.evidenceID), [fixture.association])
        XCTAssertEqual(try harness.writer.evidenceSequenceHistory(workspaceID: fixture.workspaceID,
            sequenceID: fixture.sequence.sequenceID), [fixture.sequence])

        let contextValue = try harness.evidenceContext()
        let operation = EvidenceContextWriteOperationV1.appendContext(value: contextValue, predecessor: nil)
        let target = try operation.concurrencyIdentity
        let afterMultiple = try harness.snapshot()
        let wrongSingle = try harness.expected([.init(identity: target, revision: 1)])
        XCTAssertThrowsError(try harness.writer.execute(.init(mutationID: operation.mutationID,
            expectedRevision: wrongSingle, command: .applyEvidenceContext(operation)))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try harness.snapshot(), afterMultiple)
        let expected = try harness.expected([.init(identity: target, revision: 0)])
        _ = try harness.writer.execute(.init(mutationID: operation.mutationID,
            expectedRevision: expected, command: .applyEvidenceContext(operation)))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<EvidenceContextRow>()).map { try $0.value() }, [contextValue])
        let singleReceipt = try XCTUnwrap(harness.journal.receipt(mutationID: operation.mutationID))
        XCTAssertEqual(singleReceipt.postImages.count, 1)
        XCTAssertEqual(try singleReceipt.postImages.first?.identity, try operation.affectedIdentity)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try harness.writer.currentRevision().revision, 2)
        XCTAssertFalse(harness.context.hasChanges)
        try harness.journal.validateAll()
    }

    func testV23P03C39ReleaseReferenceCanonicalReceiptIsStable() throws {
        let reference = AssetSemanticCatalogReleaseReferenceV1(
            releaseID: UUID(uuidString: "00000000-0000-0000-0000-000000002101")!,
            packageRelease: try PackageReleaseIdentityV1(
                packageID: "com.field-evidence.c39",
                schemaVersion: 1,
                contentVersion: 1
            ),
            catalogSHA256: String(repeating: "a", count: 64)
        )
        try reference.validate()
        let first = try AssetSemanticCanonicalCodecV1.encode(reference)
        XCTAssertEqual(first, try AssetSemanticCanonicalCodecV1.encode(reference))
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode(
                AssetSemanticCatalogReleaseReferenceV1.self,
                from: first
            ),
            reference
        )
    }

    @MainActor
    func testV10_02G01CanonicalEnvelopeReceiptBytesAndAtomicCommit() throws {
        let corpus = try Self.loadCorpus()
        let harness = try MutationJournalHarnessV1()
        let request = try harness.request(mutation: 10, label: "North sign")
        let envelope = try harness.envelope(request)
        let envelopeBytes = try envelope.canonicalData()

        XCTAssertEqual(try MutationEnvelopeV1.decodeCanonical(from: envelopeBytes), envelope)
        XCTAssertEqual(try envelope.canonicalSHA256(), MutationJournalHarnessV1.sha256(envelopeBytes))
        XCTAssertEqual(envelope.contentDependencyIDs, ["content-a", "content-b"])
        XCTAssertEqual(envelope.workspaceID.rawValue.uuidString.lowercased(), corpus.canonicalVector.workspaceID.lowercased())
        XCTAssertEqual(envelope.mutationID.rawValue.uuidString.lowercased(), corpus.canonicalVector.mutationID.lowercased())
        XCTAssertEqual(envelope.commandKind.rawValue, corpus.canonicalVector.commandKind)

        let receipt = try harness.commit(envelope, entities: [harness.asset, harness.site])
        let receiptBytes = try receipt.canonicalData()
        let receiptText = try XCTUnwrap(String(data: receiptBytes, encoding: .utf8))
        XCTAssertEqual(try MutationReceiptV1.decodeCanonical(from: receiptBytes), receipt)
        XCTAssertEqual(try receipt.canonicalSHA256(), MutationJournalHarnessV1.sha256(receiptBytes))
        XCTAssertFalse(receiptText.contains("writerInstanceID"))
        var tamperedPortableAuthority = receiptText
        let generationRange = try XCTUnwrap(
            tamperedPortableAuthority.range(
                of: receipt.expectedRevision.generationID.uuidString,
                options: .caseInsensitive
            )
        )
        tamperedPortableAuthority.replaceSubrange(
            generationRange,
            with: MutationJournalHarnessV1.id(99).uuidString.lowercased()
        )
        XCTAssertThrowsError(try MutationReceiptV1.decodeCanonical(
            from: Data(tamperedPortableAuthority.utf8)
        ))
        XCTAssertEqual(receipt.identity.localSequence, 1)
        XCTAssertEqual(receipt.expectedRevision.workspaceRevision, 0)
        XCTAssertEqual(receipt.resultingRevision.workspaceRevision, 1)
        XCTAssertEqual(receipt.postImages.count, 2)
        XCTAssertEqual(receipt.contentDependencyIDs, envelope.contentDependencyIDs)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkspaceMutationStateRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()), 2)
        try harness.store.validateAll()

        let persistedSite = try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<Site>()).first
        )
        persistedSite.label = "Tampered after receipt"
        try harness.context.save()
        XCTAssertThrowsError(
            try MutationReceiptRecoveryServiceV1(store: harness.store)
                .recoverBeforeWriterActivation()
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
    }

    func testV10_02G01TemporalReceiptRetainsPortableGenerationAndRevisionAuthority() throws {
        let fixture = try C33TemporalEvidenceTestSupport.clip(slot: 902)
        let expected = try C33TemporalEvidenceTestSupport.expectedRevision(
            for: fixture.clip,
            generationID: C33TemporalEvidenceTestSupport.id(903),
            writerInstanceID: C33TemporalEvidenceTestSupport.id(904)
        )
        let mutation = try TemporalEvidenceMutationV1(
            workspaceID: fixture.clip.workspaceID,
            expectedRevision: expected,
            mutationID: fixture.clip.mutationID,
            payload: .acceptClip(
                fixture.clip,
                review: C33TemporalEvidenceTestSupport.review(for: fixture.clip),
                predecessor: nil
            )
        )
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.clip.workspaceID,
            replicaID: ReplicaID(rawValue: C33TemporalEvidenceTestSupport.id(905))
        )

        func receipt(for receiptExpected: WorkspaceExpectedRevisionV1) throws -> MutationReceiptV1 {
            let request = WorkspaceMutationRequestV1(
                mutationID: mutation.mutationID,
                expectedRevision: receiptExpected,
                command: .applyTemporalEvidence(mutation)
            )
            let envelope = try MutationEnvelopeV1(request: request, identity: identity)
            let resulting = try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: receiptExpected.generationID,
                writerInstanceID: receiptExpected.writerInstanceID,
                workspaceRevision: receiptExpected.workspaceRevision + 1,
                entityRevision: fixture.clip.revision
            )
            return try MutationReceiptV1(
                identity: MutationReceiptIdentityV1(
                    workspaceID: fixture.clip.workspaceID,
                    replicaID: identity.replicaID,
                    localSequence: 1
                ),
                envelope: envelope,
                resultingRevision: MutationPortableExpectedRevisionV1(resulting),
                postImages: mutation.mutationPostImages,
                committedAt: fixture.clip.acceptedAt
            )
        }

        let matchingReceipt = try receipt(for: expected)
        let portable = try TemporalEvidenceMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: matchingReceipt
        )
        try portable.validate(mutation: mutation)
        let wireText = try XCTUnwrap(String(
            data: WorkspaceMutationCanonicalV1.data(portable),
            encoding: .utf8
        ))
        XCTAssertFalse(wireText.contains("writerInstanceID"))

        let foreignExpectations = [
            try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: C33TemporalEvidenceTestSupport.id(906),
                writerInstanceID: C33TemporalEvidenceTestSupport.id(907)
            ),
            try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: expected.generationID,
                writerInstanceID: C33TemporalEvidenceTestSupport.id(908),
                workspaceRevision: expected.workspaceRevision + 1
            ),
        ]
        for foreignExpected in foreignExpectations {
            let foreignReceipt = try receipt(for: foreignExpected)
            XCTAssertNoThrow(try foreignReceipt.validate())
            XCTAssertThrowsError(try TemporalEvidenceMutationReceiptV1(
                mutation: mutation,
                mutationReceipt: foreignReceipt
            )) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReceipt)
            }
        }
    }

    @MainActor
    func testV10_02A01RestartReplayChangedHashQuarantineAndSequence() throws {
        let harness = try MutationJournalHarnessV1()
        let originalExpected = try harness.currentExpected()
        let request = try harness.request(mutation: 20, label: "Original", expected: originalExpected)
        let envelope = try harness.envelope(request)
        let receipt = try harness.commit(envelope, entities: [harness.asset])

        let relaunchedContext = ModelContext(harness.container)
        relaunchedContext.autosaveEnabled = false
        let relaunched = try MutationJournalStoreV1(
            modelContext: relaunchedContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        try MutationReceiptRecoveryServiceV1(store: relaunched).recoverBeforeWriterActivation()
        XCTAssertEqual(
            try relaunched.resolveReplay(envelope: envelope, detectedAt: harness.date(21)),
            receipt
        )

        let changed = try harness.envelope(harness.request(
            mutation: 20,
            label: "Changed",
            expected: originalExpected
        ))
        XCTAssertThrowsError(try relaunched.resolveReplay(envelope: changed, detectedAt: harness.date(22))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try relaunched.resolveReplay(envelope: envelope, detectedAt: harness.date(23))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
        XCTAssertEqual(try relaunched.currentRevision(writerInstanceID: harness.writerInstanceID).revision, 1)
        let normalQuarantine = try XCTUnwrap(
            try relaunched.exportSnapshot().quarantines.first
        )
        XCTAssertEqual(normalQuarantine.identityDomain, .mutationEnvelope)
        XCTAssertEqual(normalQuarantine.acceptedIdentitySHA256, try envelope.canonicalSHA256())
        XCTAssertEqual(normalQuarantine.conflictingIdentitySHA256, try changed.canonicalSHA256())

        let normalSnapshot = try relaunched.exportSnapshot()
        let normalRestoreContainer = try MutationJournalHarnessV1.makeContainer(
            name: "V10_02NormalQuarantineRestore"
        )
        let normalRestoreStore = try MutationJournalStoreV1(
            modelContext: normalRestoreContainer.mainContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        try normalRestoreStore.replaceHistory(
            with: normalSnapshot,
            identityDisposition: .preserve
        )
        XCTAssertEqual(
            try normalRestoreStore.exportSnapshot().quarantines,
            normalSnapshot.quarantines
        )
        let malformedDomainRow = try XCTUnwrap(
            try normalRestoreContainer.mainContext.fetch(
                FetchDescriptor<MutationQuarantineRow>()
            ).first
        )
        malformedDomainRow.identityDomain = "UNKNOWN_IDENTITY_DOMAIN"
        try normalRestoreContainer.mainContext.save()
        XCTAssertThrowsError(try normalRestoreStore.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        let mixedDomainSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: normalSnapshot.workspaceRevision,
            lastLocalSequence: normalSnapshot.lastLocalSequence,
            receipts: normalSnapshot.receipts,
            quarantines: [.init(
                workspaceID: normalQuarantine.workspaceID,
                mutationID: normalQuarantine.mutationID,
                identityDomain: .semanticReversalReplayIdentity,
                acceptedIdentitySHA256: normalQuarantine.acceptedIdentitySHA256,
                conflictingIdentitySHA256: normalQuarantine.conflictingIdentitySHA256,
                detectedAt: normalQuarantine.detectedAt
            )],
            entityRevisions: normalSnapshot.entityRevisions
        )
        XCTAssertThrowsError(
            try MutationJournalStoreV1.validateImportedSnapshot(mixedDomainSnapshot)
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }

        let nextRequest = try harness.request(mutation: 21, label: "Next")
        let next = try harness.commit(harness.envelope(nextRequest), entities: [harness.site])
        XCTAssertEqual(next.identity.localSequence, 2)
        XCTAssertNotEqual(receipt.identity.stableKey, next.identity.stableKey)
        XCTAssertTrue(receipt.identity.stableKey.hasPrefix(
            "\(harness.workspaceID.rawValue.uuidString.lowercased()):\(harness.replicaID.rawValue.uuidString.lowercased()):"
        ))

        let secondIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: MutationJournalHarnessV1.id(70)),
            replicaID: ReplicaID(rawValue: MutationJournalHarnessV1.id(71))
        )
        let secondGeneration = MutationJournalHarnessV1.id(72)
        let secondSiteID = MutationJournalHarnessV1.id(73)
        let secondAssetID = MutationJournalHarnessV1.id(74)
        relaunchedContext.insert(Site(id: secondSiteID, label: "Second workspace"))
        relaunchedContext.insert(Asset(
            id: secondAssetID,
            siteID: secondSiteID,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Second asset"
        ))
        try relaunchedContext.save()
        let secondStore = try MutationJournalStoreV1(
            modelContext: relaunchedContext,
            identity: secondIdentity,
            generationID: secondGeneration
        )
        let secondSite = try WorkspaceEntityIdentityV1(kind: .site, id: secondSiteID)
        let secondAsset = try WorkspaceEntityIdentityV1(kind: .asset, id: secondAssetID)
        let secondCurrent = try secondStore.currentRevision(
            writerInstanceID: MutationJournalHarnessV1.id(75)
        )
        let secondExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: secondIdentity.workspaceID,
            generationID: secondGeneration,
            writerInstanceID: secondCurrent.writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: [
                .init(identity: secondSite, revision: 0),
                .init(identity: secondAsset, revision: 0),
            ]
        )
        let sharedMutationID = request.mutationID
        let secondEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: sharedMutationID,
                expectedRevision: secondExpected,
                command: .createFirstSign(.init(
                    siteID: secondSiteID,
                    newSite: .init(
                        id: secondSiteID,
                        label: "Second workspace",
                        address: nil,
                        timeZoneID: "UTC"
                    ),
                    assetID: secondAssetID,
                    assetLabel: "Second asset",
                    packID: "test.pack",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    createdAt: harness.date(24)
                ))
            ),
            identity: secondIdentity
        )
        let secondReceipt = try secondStore.commit(
            envelope: secondEnvelope,
            writerInstanceID: secondCurrent.writerInstanceID,
            affectedEntities: [secondSite, secondAsset],
            committedAt: harness.date(25)
        )
        XCTAssertEqual(secondReceipt.mutationID, receipt.mutationID)
        XCTAssertNotEqual(secondReceipt.identity.workspaceID, receipt.identity.workspaceID)
        XCTAssertEqual(try secondStore.receipt(mutationID: sharedMutationID), secondReceipt)
        XCTAssertEqual(try harness.store.receipt(mutationID: sharedMutationID), receipt)
    }

    @MainActor
    func testV10_02H01StaleForeignUnknownTamperedSequenceAndReversalRejection() throws {
        let harness = try MutationJournalHarnessV1()
        let initial = try harness.currentExpected()
        let envelope = try harness.envelope(harness.request(mutation: 30, label: "Accepted", expected: initial))
        let receipt = try harness.commit(envelope, entities: [harness.site])

        let revisionMismatchSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: receipt.resultingRevision.workspaceRevision,
            lastLocalSequence: receipt.identity.localSequence,
            receipts: [.init(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil,
                semanticReversalData: nil
            )],
            quarantines: [],
            entityRevisions: [.init(identity: harness.site, revision: 0)]
        )
        XCTAssertThrowsError(
            try MutationJournalStoreV1.validateImportedSnapshot(revisionMismatchSnapshot)
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        let mismatchContainer = try MutationJournalHarnessV1.makeContainer(
            name: "V10_02RevisionMismatchImport"
        )
        let mismatchContext = mismatchContainer.mainContext
        mismatchContext.autosaveEnabled = false
        let mismatchStore = try MutationJournalStoreV1(
            modelContext: mismatchContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        XCTAssertThrowsError(try mismatchStore.replaceHistory(
            with: revisionMismatchSnapshot,
            identityDisposition: .preserve
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(
            try mismatchContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )
        XCTAssertEqual(
            try mismatchContext.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()),
            0
        )

        let stale = try harness.envelope(harness.request(mutation: 31, label: "Stale", expected: initial))
        XCTAssertThrowsError(try harness.commit(stale, entities: [harness.asset])) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        let current = try harness.store.currentRevision(writerInstanceID: harness.writerInstanceID)
        let staleEntityExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: harness.workspaceID,
            generationID: harness.generationID,
            writerInstanceID: harness.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [.init(identity: harness.site, revision: 0)]
        )
        let staleEntity = try harness.envelope(harness.request(
            mutation: 34,
            label: "Stale entity",
            expected: staleEntityExpected
        ))
        XCTAssertThrowsError(try harness.commit(staleEntity, entities: [harness.site])) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleEntityRevision(harness.site))
        }
        let missingExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: harness.workspaceID,
            generationID: harness.generationID,
            writerInstanceID: harness.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: []
        )
        let missingTargetEnvelope = try harness.envelope(harness.request(
            mutation: 38,
            label: "Missing target token",
            expected: missingExpected
        ))
        XCTAssertThrowsError(try harness.commit(
            missingTargetEnvelope,
            entities: [harness.site, harness.asset]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }

        let foreignWorkspace = WorkspaceID(rawValue: MutationJournalHarnessV1.id(90))
        let foreignRevision = try WorkspaceRevisionV1(
            workspaceID: foreignWorkspace,
            generationID: harness.generationID,
            revision: 0,
            entityRevisions: []
        )
        let foreignRequest = try harness.request(
            mutation: 32,
            label: "Foreign",
            expected: WorkspaceExpectedRevisionV1(snapshot: foreignRevision)
        )
        XCTAssertThrowsError(try MutationEnvelopeV1(request: foreignRequest, identity: harness.identity))

        var unknownVersion = try envelope.canonicalData()
        unknownVersion = try XCTUnwrap(String(data: unknownVersion, encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
            .data(using: .utf8)!
        XCTAssertThrowsError(try MutationEnvelopeV1.decodeCanonical(from: unknownVersion))
        let unknownCommand = try XCTUnwrap(String(data: try envelope.canonicalData(), encoding: .utf8))
            .replacingOccurrences(of: "create_first_sign", with: "future_command")
            .data(using: .utf8)!
        XCTAssertThrowsError(try MutationEnvelopeV1.decodeCanonical(from: unknownCommand))

        let rows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
        let row = try XCTUnwrap(rows.first)
        row.receiptSHA256 = String(repeating: "0", count: 64)
        try harness.context.save()
        XCTAssertThrowsError(try harness.store.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        row.receiptSHA256 = try receipt.canonicalSHA256()
        try harness.context.save()
        try harness.store.validateAll()
        XCTAssertEqual(receipt.identity.localSequence, 1)

        let originalReceiptData = row.receiptData
        let dependencyTamper = try XCTUnwrap(
            String(data: originalReceiptData, encoding: .utf8)
        )
            .replacingOccurrences(of: "content-b", with: "content-c")
            .data(using: .utf8)!
        row.receiptData = dependencyTamper
        row.receiptSHA256 = MutationJournalHarnessV1.sha256(dependencyTamper)
        try harness.context.save()
        XCTAssertThrowsError(try harness.store.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        row.receiptData = originalReceiptData
        row.receiptSHA256 = try receipt.canonicalSHA256()
        try harness.context.save()
        try harness.store.validateAll()

        let targetPlan = try harness.reversalPlan(mutation: 30)
        let basis = try ReversalBasisV1(
            targetMutationID: envelope.mutationID,
            targetReceiptIdentity: receipt.identity,
            plan: targetPlan
        )
        let encodedBasis = try WorkspaceMutationCanonicalV1.data(basis)
        let decodedBasis = try ReversalBasisV1.decodeCanonical(from: encodedBasis)
        XCTAssertEqual(decodedBasis.planDigest, targetPlan.planDigest)
        let tamperedBasis = try XCTUnwrap(String(data: encodedBasis, encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
            .data(using: .utf8)!
        XCTAssertThrowsError(try ReversalBasisV1.decodeCanonical(from: tamperedBasis))
        XCTAssertThrowsError(try ReversalBasisV1(
            targetMutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(33)),
            targetReceiptIdentity: receipt.identity,
            plan: targetPlan
        ))

        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(35)),
            expectedRevision: try harness.currentExpected(),
            command: .updateSiteTimeZone(.init(
                siteID: harness.site.id,
                timeZoneID: "UTC",
                confirmedAt: harness.date(35)
            ))
        )
        let reversalExecution = try SemanticReversalExecutionV1(
            targetMutationID: envelope.mutationID,
            targetReceiptIdentity: receipt.identity,
            reversalBasisSHA256: basis.canonicalSHA256(),
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        )
        let reversalReplayIdentitySHA256 = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: harness.identity,
            targetMutationID: envelope.mutationID,
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        ).canonicalSHA256()
        let reversalEnvelope = try MutationEnvelopeV1(
            request: reversalRequest,
            identity: harness.identity,
            sourceKind: .semanticReversal,
            causationMutationID: envelope.mutationID,
            correlationID: MutationJournalHarnessV1.id(36),
            semanticReversalReplayIdentitySHA256: reversalReplayIdentitySHA256,
            semanticReversalExecution: reversalExecution
        )
        let foreignTargetExecution = try SemanticReversalExecutionV1(
            targetMutationID: envelope.mutationID,
            targetReceiptIdentity: MutationReceiptIdentityV1(
                workspaceID: foreignWorkspace,
                replicaID: receipt.identity.replicaID,
                localSequence: receipt.identity.localSequence
            ),
            reversalBasisSHA256: basis.canonicalSHA256(),
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        )
        XCTAssertThrowsError(try MutationEnvelopeV1(
            request: reversalRequest,
            identity: harness.identity,
            sourceKind: .semanticReversal,
            causationMutationID: envelope.mutationID,
            correlationID: MutationJournalHarnessV1.id(36),
            semanticReversalReplayIdentitySHA256: reversalReplayIdentitySHA256,
            semanticReversalExecution: foreignTargetExecution
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        let reversalResult = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: harness.workspaceID,
                generationID: harness.generationID,
                writerInstanceID: harness.writerInstanceID,
                workspaceRevision: 2,
                entityRevisions: [.init(identity: harness.site, revision: 2)]
            )
        )
        let reversalIdentity = MutationReceiptIdentityV1(
            workspaceID: harness.workspaceID,
            replicaID: harness.replicaID,
            localSequence: 2
        )
        let reversalReceipt = try MutationReceiptV1(
            identity: reversalIdentity,
            envelope: reversalEnvelope,
            resultingRevision: reversalResult,
            postImages: [.site(
                id: harness.site.id,
                revision: 2,
                semanticSHA256: String(repeating: "c", count: 64)
            )],
            reversesMutationID: envelope.mutationID,
            committedAt: harness.date(36)
        )
        let tamperedLink = try SemanticReversalReceiptV1(
            reversalReceiptIdentity: reversalIdentity,
            reversesMutationID: envelope.mutationID,
            targetReceiptIdentity: receipt.identity,
            reversalBasisSHA256: try basis.canonicalSHA256(),
            planDigest: String(repeating: "b", count: 64),
            compensatingMutationIDs: [try MutationIDV1(rawValue: MutationJournalHarnessV1.id(37))],
            resultingRevision: reversalResult
        )
        let hostileSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: 2,
            lastLocalSequence: 2,
            receipts: [
                .init(
                    envelopeData: try envelope.canonicalData(),
                    receiptData: try receipt.canonicalData(),
                    reversalBasisData: try basis.canonicalData(),
                    semanticReversalData: nil
                ),
                .init(
                    envelopeData: try reversalEnvelope.canonicalData(),
                    receiptData: try reversalReceipt.canonicalData(),
                    reversalBasisData: nil,
                    semanticReversalData: try tamperedLink.canonicalData()
                ),
            ],
            quarantines: [],
            entityRevisions: [.init(identity: harness.site, revision: 2)]
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(hostileSnapshot)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        let hostileContainer = try MutationJournalHarnessV1.makeContainer(name: "V10_02HostileImport")
        let hostileContext = hostileContainer.mainContext
        hostileContext.autosaveEnabled = false
        let hostileStore = try MutationJournalStoreV1(
            modelContext: hostileContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        XCTAssertThrowsError(try hostileStore.replaceHistory(
            with: hostileSnapshot,
            identityDisposition: .preserve
        ))
        XCTAssertEqual(try hostileContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)

        let tombstoneHarness = try MutationJournalHarnessV1()
        let persistedAsset = try XCTUnwrap(
            try tombstoneHarness.context.fetch(FetchDescriptor<Asset>()).first
        )
        tombstoneHarness.context.delete(persistedAsset)
        let deleteEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(39)),
                expectedRevision: try tombstoneHarness.currentExpected(),
                command: .deleteAsset(.init(
                    deletionID: MutationJournalHarnessV1.id(40),
                    assetID: tombstoneHarness.asset.id,
                    planDigest: String(repeating: "d", count: 64)
                ))
            ),
            identity: tombstoneHarness.identity
        )
        let deletionReceipt = try tombstoneHarness.commit(
            deleteEnvelope,
            entities: [tombstoneHarness.asset]
        )
        guard case .tombstone = try XCTUnwrap(deletionReceipt.postImages.first) else {
            return XCTFail("Deleted entity must produce a typed tombstone")
        }
        try tombstoneHarness.store.validateAll()
        tombstoneHarness.context.insert(Asset(
            id: tombstoneHarness.asset.id,
            siteID: tombstoneHarness.site.id,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Illicit resurrection"
        ))
        try tombstoneHarness.context.save()
        XCTAssertThrowsError(
            try MutationReceiptRecoveryServiceV1(store: tombstoneHarness.store)
                .recoverBeforeWriterActivation()
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }

        let reversalHarness = try MutationJournalHarnessV1()
        let targetRequest = try reversalHarness.request(mutation: 60, label: "Target")
        let compensatingCommand = try reversalHarness.request(
            mutation: 61,
            label: "Compensation",
            expected: targetRequest.expectedRevision
        ).command
        let targetPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand]
        )
        _ = try reversalHarness.writer.execute(targetRequest, reversalPlan: targetPlan)
        let reversalMutationID = try MutationIDV1(rawValue: MutationJournalHarnessV1.id(61))
        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: reversalMutationID,
            expectedRevision: try reversalHarness.currentExpected(),
            command: compensatingCommand
        )
        let targetRow = try XCTUnwrap(
            try reversalHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == targetRequest.mutationID.rawValue }
        )
        let originalBasisData = try XCTUnwrap(targetRow.reversalBasisData)
        let originalBasisSHA256 = try XCTUnwrap(targetRow.reversalBasisSHA256)
        let mismatchedBasisData = try XCTUnwrap(
            String(data: originalBasisData, encoding: .utf8)?
                .replacingOccurrences(
                    of: WorkspaceCommandKindV1.createFirstSign.rawValue,
                    with: WorkspaceCommandKindV1.updateSiteTimeZone.rawValue
                )
                .data(using: .utf8)
        )
        let mismatchedBasis = try ReversalBasisV1.decodeCanonical(from: mismatchedBasisData)
        XCTAssertNotEqual(
            mismatchedBasis.compensatingCommandKinds,
            targetPlan.compensatingCommands.map(\.kind)
        )
        targetRow.reversalBasisData = mismatchedBasisData
        targetRow.reversalBasisSHA256 = try mismatchedBasis.canonicalSHA256()
        try reversalHarness.context.save()
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: targetPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
        }
        targetRow.reversalBasisData = originalBasisData
        targetRow.reversalBasisSHA256 = originalBasisSHA256
        try reversalHarness.context.save()
        let preflightMultiCommandPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand, compensatingCommand]
        )
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: preflightMultiCommandPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
        }
        let acceptedReversal = try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: targetPlan,
            compensatingMutationIDs: [reversalMutationID]
        )
        XCTAssertEqual(
            try reversalHarness.writer.executeSemanticReversal(
                reversalRequest,
                targetMutationID: targetRequest.mutationID,
                plan: targetPlan,
                compensatingMutationIDs: [reversalMutationID]
            ),
            acceptedReversal
        )
        let acceptedSemanticSnapshot = try reversalHarness.store.exportSnapshot()
        let acceptedSemanticReplaySHA256 = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: reversalHarness.identity,
            targetMutationID: targetRequest.mutationID,
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalMutationID]
        ).canonicalSHA256()

        let changedPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "changed")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand]
        )
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: changedPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        let changedPlanReplaySHA256 = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: reversalHarness.identity,
            targetMutationID: targetRequest.mutationID,
            planDigest: changedPlan.planDigest,
            compensatingMutationIDs: [reversalMutationID]
        ).canonicalSHA256()
        let semanticQuarantine = try XCTUnwrap(
            try reversalHarness.store.exportSnapshot().quarantines.first
        )
        XCTAssertEqual(
            semanticQuarantine.identityDomain,
            .semanticReversalReplayIdentity
        )
        XCTAssertEqual(
            semanticQuarantine.acceptedIdentitySHA256,
            acceptedSemanticReplaySHA256
        )
        XCTAssertEqual(
            semanticQuarantine.conflictingIdentitySHA256,
            changedPlanReplaySHA256
        )
        let acceptedSemanticEnvelope = try XCTUnwrap(
            try acceptedSemanticSnapshot.receipts
                .map { try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData) }
                .first { $0.mutationID == reversalMutationID }
        )
        XCTAssertNotEqual(
            semanticQuarantine.acceptedIdentitySHA256,
            try acceptedSemanticEnvelope.canonicalSHA256()
        )

        let changedTargetID = try MutationIDV1(rawValue: MutationJournalHarnessV1.id(62))
        let changedTargetPlan = try SemanticReversalPlanV1(
            mutationID: changedTargetID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand]
        )
        let changedCompensatingMutationID = try MutationIDV1(
            rawValue: MutationJournalHarnessV1.id(63)
        )
        let replayVariants: [(String, MutationIDV1, String, [MutationIDV1])] = [
            ("missing-target", changedTargetID, changedTargetPlan.planDigest, [reversalMutationID]),
            ("compensating-id", targetRequest.mutationID, targetPlan.planDigest, [changedCompensatingMutationID]),
        ]
        for (label, variantTarget, variantPlanDigest, variantCompensatingIDs) in replayVariants {
            let variantContainer = try MutationJournalHarnessV1.makeContainer(
                name: "V10_02SemanticReplay-\(label)"
            )
            let variantStore = try MutationJournalStoreV1(
                modelContext: variantContainer.mainContext,
                identity: reversalHarness.identity,
                generationID: reversalHarness.generationID
            )
            try variantStore.replaceHistory(
                with: acceptedSemanticSnapshot,
                identityDisposition: .preserve
            )
            let conflictingReplaySHA256 = try SemanticReversalReplayIdentityV1(
                request: reversalRequest,
                identity: reversalHarness.identity,
                targetMutationID: variantTarget,
                planDigest: variantPlanDigest,
                compensatingMutationIDs: variantCompensatingIDs
            ).canonicalSHA256()
            XCTAssertThrowsError(try variantStore.resolveSemanticReversalReplay(
                request: reversalRequest,
                replayIdentitySHA256: conflictingReplaySHA256,
                detectedAt: reversalHarness.date(64)
            )) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined, label)
            }
            let quarantinedVariant = try variantStore.exportSnapshot()
            let quarantine = try XCTUnwrap(quarantinedVariant.quarantines.first, label)
            XCTAssertEqual(quarantine.identityDomain, .semanticReversalReplayIdentity, label)
            XCTAssertEqual(quarantine.acceptedIdentitySHA256, acceptedSemanticReplaySHA256, label)
            XCTAssertEqual(quarantine.conflictingIdentitySHA256, conflictingReplaySHA256, label)

            let restoredContainer = try MutationJournalHarnessV1.makeContainer(
                name: "V10_02SemanticReplayRestore-\(label)"
            )
            let restoredStore = try MutationJournalStoreV1(
                modelContext: restoredContainer.mainContext,
                identity: reversalHarness.identity,
                generationID: reversalHarness.generationID
            )
            try restoredStore.replaceHistory(
                with: quarantinedVariant,
                identityDisposition: .preserve
            )
            XCTAssertEqual(
                try restoredStore.exportSnapshot().quarantines,
                quarantinedVariant.quarantines,
                label
            )
        }
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: changedTargetID,
            plan: changedTargetPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: targetPlan,
            compensatingMutationIDs: [changedCompensatingMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }

        let multiCommandPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand, compensatingCommand]
        )
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: multiCommandPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(
            try reversalHarness.writer.durableReceipt(mutationID: reversalMutationID),
            try reversalHarness.writer.durableReceipt(mutationID: acceptedReversal.mutationID)
        )
        XCTAssertEqual(
            try reversalHarness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            1
        )
        XCTAssertEqual(reversalHarness.adapter.applyCount, 2)
        let replayRelaunchContext = ModelContext(reversalHarness.container)
        replayRelaunchContext.autosaveEnabled = false
        XCTAssertEqual(
            try replayRelaunchContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            1
        )
        XCTAssertEqual(
            try replayRelaunchContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            2
        )
        let reversalRow = try XCTUnwrap(
            try reversalHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == reversalMutationID.rawValue }
        )
        let originalSemanticData = try XCTUnwrap(reversalRow.semanticReversalData)
        let semanticReceipt = try SemanticReversalReceiptV1.decodeCanonical(
            from: originalSemanticData
        )
        let mismatchedResultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: semanticReceipt.resultingRevision.workspaceID,
                generationID: semanticReceipt.resultingRevision.generationID,
                writerInstanceID: MutationJournalHarnessV1.id(66),
                workspaceRevision: semanticReceipt.resultingRevision.workspaceRevision + 1,
                entityRevisions: semanticReceipt.resultingRevision.entityRevisions
            )
        )
        let mismatchedSemanticReceipt = try SemanticReversalReceiptV1(
            reversalReceiptIdentity: semanticReceipt.reversalReceiptIdentity,
            reversesMutationID: semanticReceipt.reversesMutationID,
            targetReceiptIdentity: semanticReceipt.targetReceiptIdentity,
            reversalBasisSHA256: semanticReceipt.reversalBasisSHA256,
            planDigest: semanticReceipt.planDigest,
            compensatingMutationIDs: semanticReceipt.compensatingMutationIDs,
            resultingRevision: mismatchedResultingRevision
        )
        reversalRow.semanticReversalData = try mismatchedSemanticReceipt.canonicalData()
        try reversalHarness.context.save()
        XCTAssertThrowsError(try reversalHarness.store.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        reversalRow.semanticReversalData = originalSemanticData
        try reversalHarness.context.save()
        XCTAssertNoThrow(try reversalHarness.store.validateAll())

        let planReplayHarness = try MutationJournalHarnessV1()
        let plannedRequest = try planReplayHarness.request(mutation: 64, label: "Planned")
        let plannedCompensation = try planReplayHarness.request(
            mutation: 65,
            label: "Planned compensation",
            expected: plannedRequest.expectedRevision
        ).command
        let acceptedPlan = try SemanticReversalPlanV1(
            mutationID: plannedRequest.mutationID,
            commandKind: plannedRequest.command.kind,
            expectedRevision: plannedRequest.expectedRevision,
            prospectiveTargets: [planReplayHarness.site, planReplayHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "accepted")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [plannedCompensation]
        )
        _ = try planReplayHarness.writer.execute(plannedRequest, reversalPlan: acceptedPlan)
        let divergentPlan = try SemanticReversalPlanV1(
            mutationID: plannedRequest.mutationID,
            commandKind: plannedRequest.command.kind,
            expectedRevision: plannedRequest.expectedRevision,
            prospectiveTargets: [planReplayHarness.site, planReplayHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "divergent")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [plannedCompensation]
        )
        XCTAssertThrowsError(try planReplayHarness.writer.execute(
            plannedRequest,
            reversalPlan: divergentPlan
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try planReplayHarness.writer.execute(
            plannedRequest,
            reversalPlan: acceptedPlan
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(planReplayHarness.adapter.applyCount, 1)

        let missingTargetHarness = try MutationJournalHarnessV1()
        let missingTargetReplay = try missingTargetHarness.acceptedSemanticReplay(
            targetMutation: 67,
            reversalMutation: 68
        )
        let missingTargetRow = try XCTUnwrap(
            try missingTargetHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == missingTargetReplay.targetMutationID.rawValue }
        )
        missingTargetHarness.context.delete(missingTargetRow)
        try missingTargetHarness.context.save()
        XCTAssertThrowsError(try missingTargetHarness.writer.executeSemanticReversal(
            missingTargetReplay.request,
            targetMutationID: missingTargetReplay.targetMutationID,
            plan: missingTargetReplay.plan,
            compensatingMutationIDs: missingTargetReplay.compensatingMutationIDs
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(missingTargetHarness.adapter.applyCount, 2)

        let corruptBasisHarness = try MutationJournalHarnessV1()
        let corruptBasisReplay = try corruptBasisHarness.acceptedSemanticReplay(
            targetMutation: 69,
            reversalMutation: 70
        )
        let corruptBasisRow = try XCTUnwrap(
            try corruptBasisHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == corruptBasisReplay.targetMutationID.rawValue }
        )
        let corruptBasisData = try XCTUnwrap(corruptBasisRow.reversalBasisData)
        let alteredBasisData = try XCTUnwrap(
            String(data: corruptBasisData, encoding: .utf8)?
                .replacingOccurrences(
                    of: WorkspaceCommandKindV1.createFirstSign.rawValue,
                    with: WorkspaceCommandKindV1.updateSiteTimeZone.rawValue
                )
                .data(using: .utf8)
        )
        let alteredBasis = try ReversalBasisV1.decodeCanonical(from: alteredBasisData)
        corruptBasisRow.reversalBasisData = alteredBasisData
        corruptBasisRow.reversalBasisSHA256 = try alteredBasis.canonicalSHA256()
        try corruptBasisHarness.context.save()
        XCTAssertThrowsError(try corruptBasisHarness.writer.executeSemanticReversal(
            corruptBasisReplay.request,
            targetMutationID: corruptBasisReplay.targetMutationID,
            plan: corruptBasisReplay.plan,
            compensatingMutationIDs: corruptBasisReplay.compensatingMutationIDs
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(corruptBasisHarness.adapter.applyCount, 2)
    }

    @MainActor
    func testReportPDFSaveReturnFaultPreservesHeldCommittedValueAndReplaysReceipt() throws {
        let generationID = UUID()
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V10_02-held-pdf-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let generationRoot = temporaryRoot.appendingPathComponent(
            generationID.uuidString.lowercased(), isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: generationRoot, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let reportID = UUID()
        let report = Report(
            id: reportID, packetID: UUID(), sourceRecordID: UUID(),
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(reportID.uuidString.lowercased()).json",
            snapshotSHA256: String(repeating: "a", count: 64),
            pdfState: .pending, pdfRelativePath: nil, pdfSHA256: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_090),
            replacesReportID: nil
        )
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRoot)
        let harness = try CompilerWriterAdmissionHarnessV1(
            generationID: generationID, seedReport: report,
            failureBoundary: .afterSaveBeforeReturn,
            generationRootURL: generationRoot, expectedRootIdentity: rootIdentity
        )
        let failed = try ReportRenderService.transitionMutation(
            report: report, writer: harness.writer, transition: .pendingToFailed
        )
        XCTAssertEqual(failed.expectedReportRevision, 0)

        XCTAssertThrowsError(try harness.writer.commitReportPDFTransition(failed)) {
            XCTAssertEqual(
                $0 as? MutationJournalFailureV1,
                .injected(.afterSaveBeforeReturn)
            )
        }

        // The journal save is durable despite its lost acknowledgement. The
        // production adapter must not restore the already-committed held row.
        XCTAssertEqual(report.pdfState, ReportPDFState.failed.rawValue)
        XCTAssertNil(report.pdfRelativePath)
        XCTAssertNil(report.pdfSHA256)
        XCTAssertFalse(harness.context.hasChanges)
        let durable = try XCTUnwrap(harness.journal.receipt(mutationID: failed.mutationID))
        XCTAssertEqual(try harness.writer.reportPDFTransitionReceipt(for: failed), durable)
        XCTAssertEqual(try harness.writer.commitReportPDFTransition(failed), durable)
        try harness.journal.validateAll()

        let freshContext = ModelContext(harness.container)
        freshContext.autosaveEnabled = false
        let durableReport = try XCTUnwrap(
            freshContext.fetch(FetchDescriptor<Report>()).first { $0.id == reportID }
        )
        XCTAssertEqual(durableReport.pdfState, ReportPDFState.failed.rawValue)

        let pending = try ReportRenderService.transitionMutation(
            report: report, writer: harness.writer, transition: .failedToPending
        )
        XCTAssertEqual(pending.expectedReportRevision, 1)
        _ = try harness.writer.commitReportPDFTransition(pending)
        XCTAssertEqual(report.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertEqual(try harness.journal.exportSnapshot().receipts.count, 2)
        try harness.journal.validateAll()
    }

    @MainActor
    func testV10_02I01EveryAtomicCrashBoundaryRecoversExactlyOnce() throws {
        let logicalBoundaries = try Self.loadCorpus().interruptionBoundaries
        XCTAssertEqual(logicalBoundaries.count, 7)
        XCTAssertEqual(Set(logicalBoundaries).count, logicalBoundaries.count)
        XCTAssertEqual(MutationJournalFaultBoundaryV1.allCases.count, 3)

        for (offset, boundary) in MutationJournalFaultBoundaryV1.allCases.enumerated() {
            let harness = try MutationJournalHarnessV1(failureBoundary: boundary)
            let request = try harness.request(
                mutation: UInt8(40 + offset),
                label: boundary.rawValue
            )
            let envelope = try MutationEnvelopeV1(request: request, identity: harness.identity)
            XCTAssertThrowsError(try harness.writer.execute(request)) {
                XCTAssertEqual($0 as? MutationJournalFailureV1, .injected(boundary))
            }
            XCTAssertEqual(harness.adapter.rollbackCount, 1)

            let relaunchedContext = ModelContext(harness.container)
            relaunchedContext.autosaveEnabled = false
            let relaunched = try MutationJournalStoreV1(
                modelContext: relaunchedContext,
                identity: harness.identity,
                generationID: harness.generationID
            )
            try MutationReceiptRecoveryServiceV1(store: relaunched).recoverBeforeWriterActivation()
            if boundary == .afterSaveBeforeReturn {
                let durable = try XCTUnwrap(relaunched.receipt(mutationID: envelope.mutationID))
                XCTAssertEqual(
                    try relaunched.resolveReplay(envelope: envelope, detectedAt: harness.date(60)),
                    durable
                )
                XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
                XCTAssertEqual(try relaunched.currentRevision(writerInstanceID: harness.writerInstanceID).revision, 1)
            } else {
                XCTAssertNil(try relaunched.receipt(mutationID: envelope.mutationID))
                XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
                XCTAssertEqual(try relaunched.currentRevision(writerInstanceID: harness.writerInstanceID).revision, 0)
            }
        }
    }

    @MainActor
    func testV10_02R01MigrationLifecycleAndReplicaIdentityMatrix() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeRelease, .v11)
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.releases,
            [.v1, .v2, .v3, .v4, .v5, .v6, .v7, .v8, .v9, .v10, .v11]
        )
        XCTAssertEqual(PersistentSchemaV4.models.count, PersistentSchemaV3.models.count + 4)
        XCTAssertEqual(PersistentSchemaV5.models.count, PersistentSchemaV4.models.count + 1)
        XCTAssertEqual(PersistentSchemaV6.models.count, PersistentSchemaV5.models.count + 6)
        XCTAssertEqual(PersistentSchemaV7.models.count, PersistentSchemaV6.models.count + 1)
        XCTAssertEqual(PersistentSchemaV8.models.count, PersistentSchemaV7.models.count + 1)
        XCTAssertEqual(PersistentSchemaV9.models.count, PersistentSchemaV8.models.count + 5)
        XCTAssertEqual(PersistentSchemaV10.models.count, PersistentSchemaV9.models.count + 6)
        XCTAssertEqual(PersistentSchemaV11.models.count, PersistentSchemaV10.models.count + 9)
        XCTAssertEqual(PersistentSchemaMigrationPlanV3.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV4.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV5.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV6.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaReleaseV1.v5.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v6.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v7.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v8.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v9.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v10.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v11.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaMigrationPlanV8.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV8.stages.count, 1)
        XCTAssertEqual(PersistentSchemaMigrationPlanV9.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV9.stages.count, 1)
        XCTAssertEqual(PersistentSchemaMigrationPlanV10.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV10.stages.count, 1)

        XCTAssertEqual(corpus.restoreMatrix.map(\.mode), ["empty", "replace", "clone", "fork"])
        XCTAssertTrue(corpus.restoreMatrix.allSatisfy(\.preservesReceiptHistory))
        XCTAssertTrue(corpus.restoreMatrix.filter(\.mintsDestinationReplicaID).allSatisfy {
            !$0.preservesDestinationWorkspaceID
        })
        XCTAssertEqual(corpus.lifecycle.persistentSchemaVersion, 4)
        XCTAssertFalse(corpus.lifecycle.migrationV3ToV4FabricatesHistoricReceipts)

        let harness = try MutationJournalHarnessV1()
        let original = try harness.commit(
            harness.envelope(harness.request(mutation: 50, label: "History")),
            entities: [harness.asset]
        )
        let beforeDelete = try harness.currentExpected()
        let deleteEnvelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(51)),
                expectedRevision: beforeDelete,
                command: .deleteAsset(.init(
                    deletionID: MutationJournalHarnessV1.id(52),
                    assetID: harness.asset.id,
                    planDigest: String(repeating: "a", count: 64)
                ))
            ),
            identity: harness.identity,
            correlationID: MutationJournalHarnessV1.id(53)
        )
        let deletionReceipt = try harness.commit(deleteEnvelope, entities: [harness.asset])
        let snapshot = try harness.store.exportSnapshot()
        XCTAssertEqual(snapshot.receipts.count, 2)
        XCTAssertEqual(try harness.store.receipt(mutationID: deletionReceipt.mutationID), deletionReceipt)
        let incomingSequenceAhead: UInt64 = 7
        let aheadSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: snapshot.workspaceRevision,
            lastLocalSequence: incomingSequenceAhead,
            receipts: snapshot.receipts,
            quarantines: snapshot.quarantines,
            entityRevisions: snapshot.entityRevisions
        )

        for (offset, mode) in corpus.restoreMatrix.enumerated() {
            let destinationWorkspace = mode.mintsDestinationReplicaID
                ? MutationJournalHarnessV1.id(UInt8(80 + offset))
                : harness.workspaceID.rawValue
            let destinationReplica = mode.mintsDestinationReplicaID
                ? MutationJournalHarnessV1.id(UInt8(90 + offset))
                : harness.replicaID.rawValue
            let destinationGeneration = mode.mintsDestinationReplicaID
                ? MutationJournalHarnessV1.id(UInt8(100 + offset))
                : harness.generationID
            let destinationIdentity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: destinationWorkspace),
                replicaID: ReplicaID(rawValue: destinationReplica)
            )
            let destinationContainer = try MutationJournalHarnessV1.makeContainer(
                name: "V10_02Restore-\(mode.mode)"
            )
            let destinationContext = destinationContainer.mainContext
            destinationContext.autosaveEnabled = false
            let destinationStore = try MutationJournalStoreV1(
                modelContext: destinationContext,
                identity: destinationIdentity,
                generationID: destinationGeneration
            )
            try destinationStore.replaceHistory(
                with: aheadSnapshot,
                identityDisposition: mode.mintsDestinationReplicaID
                    ? .destination(destinationIdentity, generationID: destinationGeneration)
                    : .preserve
            )
            let imported = try destinationStore.exportSnapshot()
            XCTAssertEqual(imported.receipts, snapshot.receipts, mode.mode)
            XCTAssertEqual(imported.workspaceRevision, snapshot.workspaceRevision, mode.mode)
            XCTAssertEqual(
                imported.lastLocalSequence,
                mode.mintsDestinationReplicaID ? 0 : incomingSequenceAhead,
                mode.mode
            )
            if mode.mintsDestinationReplicaID {
                XCTAssertNotEqual(destinationIdentity.replicaID, harness.replicaID, mode.mode)
            } else {
                XCTAssertEqual(destinationIdentity, harness.identity, mode.mode)
            }
            var expectedReceiptCount = 2
            if !mode.mintsDestinationReplicaID {
                destinationContext.insert(Site(
                    id: harness.site.id,
                    label: "Journal site",
                    address: nil,
                    timeZoneID: "UTC",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
                ))
                destinationContext.insert(Asset(
                    id: harness.asset.id,
                    siteID: harness.site.id,
                    packID: "test.pack",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    label: "Journal asset",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_001)
                ))
                try destinationContext.save()
                let writerInstanceID = MutationJournalHarnessV1.id(110)
                let importedRevision = try destinationStore.currentRevision(
                    writerInstanceID: writerInstanceID
                )
                let importedByIdentity = Dictionary(uniqueKeysWithValues:
                    importedRevision.entityRevisions.map { ($0.identity, $0.revision) }
                )
                let expected = try WorkspaceExpectedRevisionV1(
                    workspaceID: destinationIdentity.workspaceID,
                    generationID: destinationGeneration,
                    writerInstanceID: writerInstanceID,
                    workspaceRevision: importedRevision.revision,
                    entityRevisions: [.init(
                        identity: harness.asset,
                        revision: importedByIdentity[harness.asset, default: 0]
                    )]
                )
                let localWriter = try WorkspaceWriterV1(
                    identity: destinationIdentity,
                    generationID: destinationGeneration,
                    initialRevision: importedRevision,
                    clock: MutationJournalFixedClockV1(),
                    idSource: MutationJournalFixedIDSourceV1(value: writerInstanceID),
                    fileAuthority: MutationJournalFileAuthorityV1(),
                    adapter: MutationJournalFaultAdapterV1(),
                    journalStore: destinationStore
                )
                let localMutationID = try MutationIDV1(
                    rawValue: MutationJournalHarnessV1.id(111)
                )
                _ = try localWriter.execute(.init(
                    mutationID: localMutationID,
                    expectedRevision: expected,
                    command: .createFirstSign(.init(
                        siteID: harness.site.id,
                        newSite: nil,
                        assetID: harness.asset.id,
                        assetLabel: "Local destination write",
                        packID: "test.pack",
                        packSchemaVersion: 1,
                        packContentVersion: 1,
                        createdAt: Date(timeIntervalSince1970: 1_800_000_111)
                    ))
                ))
                XCTAssertEqual(
                    try XCTUnwrap(
                        localWriter.durableReceipt(mutationID: localMutationID)
                    ).identity.localSequence,
                    incomingSequenceAhead + 1
                )
                let localProjection = try XCTUnwrap(destinationStore.exportSnapshot()
                    .entityRevisions.first { $0.identity == harness.asset })
                XCTAssertNil(localProjection.externalProjectionSHA256)
                let relaunchedContext = ModelContext(destinationContainer)
                relaunchedContext.autosaveEnabled = false
                let relaunchedStore = try MutationJournalStoreV1(
                    modelContext: relaunchedContext,
                    identity: destinationIdentity,
                    generationID: destinationGeneration,
                    allowStateBootstrap: false
                )
                XCTAssertNoThrow(
                    try MutationReceiptRecoveryServiceV1(store: relaunchedStore)
                        .recoverBeforeWriterActivation()
                )
                expectedReceiptCount = 3
            }
            XCTAssertThrowsError(try destinationStore.clearForErase(
                expectedWorkspaceID: WorkspaceID(rawValue: MutationJournalHarnessV1.id(120)),
                expectedGenerationID: MutationJournalHarnessV1.id(121)
            ))
            XCTAssertEqual(
                try destinationStore.exportSnapshot().receipts.count,
                expectedReceiptCount,
                mode.mode
            )
            try destinationStore.clearForErase(
                expectedWorkspaceID: destinationIdentity.workspaceID,
                expectedGenerationID: destinationGeneration
            )
            let erased = try destinationStore.exportSnapshot()
            XCTAssertTrue(erased.receipts.isEmpty, mode.mode)
            XCTAssertTrue(erased.quarantines.isEmpty, mode.mode)
            XCTAssertTrue(erased.entityRevisions.isEmpty, mode.mode)
            XCTAssertEqual(erased.workspaceRevision, 0, mode.mode)
            XCTAssertEqual(erased.lastLocalSequence, 0, mode.mode)
        }
        XCTAssertNotEqual(original.identity.workspaceID.rawValue, harness.replicaID.rawValue)
        XCTAssertEqual(try harness.store.receipt(mutationID: original.mutationID), original)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
    }

    private static func loadCorpus() throws -> MutationEnvelopeReceiptCorpusFixtureV1 {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P02C02MutationEnvelopeReceiptCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Mutation"
        ) ?? bundle.url(
            forResource: "V21P02C02MutationEnvelopeReceiptCorpusV1",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(
            MutationEnvelopeReceiptCorpusFixtureV1.self,
            from: Data(contentsOf: url)
        )
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C15ReceiptEnvelopeBindsReleaseMutationAndRevision() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_202)
        let mutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.completedRelease.mutationID,
            postImage: .recordRelease(fixture.completedRelease)
        )
        XCTAssertEqual(mutation.workspaceID, fixture.workspaceID)
        XCTAssertEqual(mutation.revision, fixture.completedRelease.revision)
        XCTAssertEqual(try mutation.affectedIdentity.id, fixture.completedRelease.releaseID)
        XCTAssertEqual(try mutation.canonicalSHA256().count, 64)
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C57ReceiptReplayIsExactAndDivergenceFailsClosed() throws {
        let fixture = try C57MyDayExistingSuiteFixtureV1.make()
        let receipt = try MyDayMutationReceiptV1(
            command: fixture.saveCommand,
            resultingPlan: fixture.sourcePlan,
            disposition: .committed,
            committedAt: fixture.sourcePlan.authoredAt.addingTimeInterval(3)
        )
        try receipt.validate(command: fixture.saveCommand)
        XCTAssertEqual(receipt.resultingPlan, try MyDayPlanReferenceV1(fixture.sourcePlan))
        XCTAssertNil(receipt.carryoverReceiptSHA256)

        let replay = try MyDayCommandReplayResolutionV1.resolve(
            command: fixture.saveCommand,
            priorReceipt: receipt
        )
        XCTAssertEqual(replay.disposition, .idempotentReplay)
        XCTAssertEqual(replay.receipt, receipt)

        let divergent = try fixture.divergentSaveCommand()
        XCTAssertEqual(divergent.mutationID, fixture.saveCommand.mutationID)
        XCTAssertNotEqual(
            try divergent.canonicalSHA256(),
            try fixture.saveCommand.canonicalSHA256()
        )
        XCTAssertThrowsError(try MyDayCommandReplayResolutionV1.resolve(
            command: divergent,
            priorReceipt: receipt
        )) {
            XCTAssertEqual($0 as? MyDayFailureV1, .divergentMutation)
        }

        let carryoverReceipt = try MyDayMutationReceiptV1(
            command: fixture.carryoverCommand,
            resultingPlan: fixture.targetPlan,
            carryoverReceipt: fixture.carryoverReceipt,
            disposition: .committed,
            committedAt: fixture.carryoverReceipt.committedAt
        )
        try carryoverReceipt.validate(command: fixture.carryoverCommand)
        XCTAssertEqual(
            carryoverReceipt.carryoverReceiptSHA256,
            fixture.carryoverReceipt.receiptSHA256
        )
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C34RestorationReceiptBindsStableIdentityWithoutMutation() throws {
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000003402")!
        )
        let stableEntityID = UUID(uuidString: "00000000-0000-4000-8000-000000003403")!
        let target = try NavigationTargetV1(
            workspaceID: workspaceID,
            destination: .draftReview,
            stableEntityID: stableEntityID,
            requestedMode: .resume
        )
        let result = try RouteRegistryV1().resolve(
            target,
            context: .init(currentWorkspaceID: workspaceID, currentRevision: 0)
        )
        let receipt = try RouteRestorationReceiptV1(
            receiptID: UUID(uuidString: "00000000-0000-4000-8000-000000003404")!,
            evidenceKind: .golden,
            source: .explicitIngress,
            result: result,
            snapshotID: nil
        )
        try receipt.validate()
        XCTAssertEqual(receipt.result.target.stableEntityID, stableEntityID)
        XCTAssertEqual(receipt.canonicalMutationCount, 0)
        XCTAssertFalse(receipt.startsAutomaticWork)
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C36ReceiptBindsMutationDigestSagaChainAndCanonicalReadBack() throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        let mutation = try FieldDraftMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            mutationID: fixture.activeCheckpoint.mutationID,
            postImage: .createCheckpoint(fixture.activeCheckpoint)
        )
        let mutationDigest = try mutation.canonicalSHA256()
        let receiptData = try FieldDraftCanonicalCodecV1.encode(fixture.commitReceipt)
        let replayed = try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: receiptData)
        XCTAssertEqual(replayed, fixture.commitReceipt)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(replayed), receiptData)
        XCTAssertEqual(mutationDigest.count, 64)
        XCTAssertEqual(replayed.sagaEventSHA256Chain, [
            fixture.preparedSaga.sagaSHA256, fixture.promotedSaga.sagaSHA256,
            fixture.targetCommittedSaga.sagaSHA256, fixture.retirePendingSaga.sagaSHA256,
            fixture.retiredSaga.sagaSHA256
        ])
        XCTAssertEqual(replayed.sagaID, fixture.retiredSaga.sagaID)
        XCTAssertEqual(replayed.commitPlanSHA256, fixture.plan.planSHA256)
        XCTAssertEqual(replayed.mutationID, fixture.rowMutationIDs.terminalBundleMutationID)
        XCTAssertNotEqual(replayed.mutationID, fixture.plan.mutationID)
    }
}

private struct MutationEnvelopeReceiptCorpusFixtureV1: Decodable {
    struct CanonicalVector: Decodable {
        let workspaceID: String
        let mutationID: String
        let commandKind: String
    }

    struct RestoreMode: Decodable {
        let mode: String
        let preservesDestinationWorkspaceID: Bool
        let mintsDestinationReplicaID: Bool
        let preservesReceiptHistory: Bool
    }

    struct Lifecycle: Decodable {
        let persistentSchemaVersion: Int
        let migrationV3ToV4FabricatesHistoricReceipts: Bool
    }

    let canonicalVector: CanonicalVector
    let interruptionBoundaries: [String]
    let restoreMatrix: [RestoreMode]
    let lifecycle: Lifecycle
}

private struct AcceptedSemanticReplayScenarioV1 {
    let request: WorkspaceMutationRequestV1
    let targetMutationID: MutationIDV1
    let plan: SemanticReversalPlanV1
    let compensatingMutationIDs: [MutationIDV1]
}

@MainActor
private final class MutationJournalHarnessV1 {
    let workspaceID = WorkspaceID(rawValue: MutationJournalHarnessV1.id(1))
    let replicaID = ReplicaID(rawValue: MutationJournalHarnessV1.id(2))
    let generationID = MutationJournalHarnessV1.id(3)
    let writerInstanceID = MutationJournalHarnessV1.id(4)
    let site = try! WorkspaceEntityIdentityV1(kind: .site, id: MutationJournalHarnessV1.id(5))
    let asset = try! WorkspaceEntityIdentityV1(kind: .asset, id: MutationJournalHarnessV1.id(6))
    let container: ModelContainer
    let context: ModelContext
    let identity: WorkspaceReplicaIdentityV1
    let store: MutationJournalStoreV1
    let adapter: MutationJournalFaultAdapterV1
    let writer: WorkspaceWriterV1

    init(failureBoundary: MutationJournalFaultBoundaryV1? = nil) throws {
        let installedContainer = try Self.makeContainer(name: "V10_02MutationJournal")
        let installedContext = installedContainer.mainContext
        installedContext.autosaveEnabled = false
        installedContext.insert(Site(
            id: Self.id(5),
            label: "Journal site",
            address: nil,
            timeZoneID: "UTC",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        installedContext.insert(Asset(
            id: Self.id(6),
            siteID: Self.id(5),
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Journal asset",
            createdAt: Date(timeIntervalSince1970: 1_800_000_001)
        ))
        try installedContext.save()
        let installedIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: Self.id(1)),
            replicaID: ReplicaID(rawValue: Self.id(2))
        )
        let journalStore = try MutationJournalStoreV1(
            modelContext: installedContext,
            identity: installedIdentity,
            generationID: Self.id(3),
            failureInjection: failureBoundary.map {
                MutationJournalFailureInjectionV1(failOnceAt: $0)
            }
        )
        let faultAdapter = MutationJournalFaultAdapterV1()
        container = installedContainer
        context = installedContext
        identity = installedIdentity
        store = journalStore
        adapter = faultAdapter
        writer = try WorkspaceWriterV1(
            identity: installedIdentity,
            generationID: Self.id(3),
            initialRevision: journalStore.currentRevision(writerInstanceID: Self.id(4)),
            clock: MutationJournalFixedClockV1(),
            idSource: MutationJournalFixedIDSourceV1(value: Self.id(4)),
            fileAuthority: MutationJournalFileAuthorityV1(),
            adapter: faultAdapter,
            journalStore: journalStore
        )
    }

    static func makeContainer(name: String) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV5.models,
            version: PersistentSchemaV5.versionIdentifier
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                name,
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
    }

    func date(_ offset: UInt8) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(offset))
    }

    func currentExpected() throws -> WorkspaceExpectedRevisionV1 {
        let current = try store.currentRevision(writerInstanceID: writerInstanceID)
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
        )
        return try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [site, asset].map {
                WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
            }
        )
    }

    func request(
        mutation: UInt8,
        label: String,
        expected: WorkspaceExpectedRevisionV1? = nil
    ) throws -> WorkspaceMutationRequestV1 {
        WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutation)),
            expectedRevision: expected ?? (try currentExpected()),
            command: .createFirstSign(.init(
                siteID: site.id,
                newSite: .init(id: site.id, label: "Site", address: nil, timeZoneID: "UTC"),
                assetID: asset.id,
                assetLabel: label,
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: date(1)
            ))
        )
    }

    func envelope(_ request: WorkspaceMutationRequestV1) throws -> MutationEnvelopeV1 {
        try MutationEnvelopeV1(
            request: request,
            identity: identity,
            contentDependencyIDs: ["content-b", "content-a"],
            correlationID: Self.id(7)
        )
    }

    func acceptedSemanticReplay(
        targetMutation: UInt8,
        reversalMutation: UInt8
    ) throws -> AcceptedSemanticReplayScenarioV1 {
        let targetRequest = try request(mutation: targetMutation, label: "Replay target")
        let compensation = try request(
            mutation: reversalMutation,
            label: "Replay compensation",
            expected: targetRequest.expectedRevision
        ).command
        let plan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [site, asset],
            requiredSemanticValues: [.init(key: "before", value: "replay")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensation]
        )
        _ = try writer.execute(targetRequest, reversalPlan: plan)
        let reversalID = try MutationIDV1(rawValue: Self.id(reversalMutation))
        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: reversalID,
            expectedRevision: try currentExpected(),
            command: compensation
        )
        _ = try writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: plan,
            compensatingMutationIDs: [reversalID]
        )
        return AcceptedSemanticReplayScenarioV1(
            request: reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: plan,
            compensatingMutationIDs: [reversalID]
        )
    }

    func commit(
        _ envelope: MutationEnvelopeV1,
        entities: [WorkspaceEntityIdentityV1]
    ) throws -> MutationReceiptV1 {
        try store.commit(
            envelope: envelope,
            writerInstanceID: writerInstanceID,
            affectedEntities: entities,
            committedAt: date(70)
        )
    }

    func reversalPlan(mutation: UInt8) throws -> SemanticReversalPlanV1 {
        try SemanticReversalPlanV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutation)),
            commandKind: .updateSiteTimeZone,
            expectedRevision: currentExpected(),
            prospectiveTargets: [site],
            requiredSemanticValues: [.init(key: "before", value: "UTC")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [.updateSiteTimeZone(.init(
                siteID: site.id,
                timeZoneID: "UTC",
                confirmedAt: date(60)
            ))]
        )
    }

    static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class MutationJournalFaultAdapterV1: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0
    private(set) var rollbackCount = 0

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        applyCount += 1
        guard case let .createFirstSign(value) = command else {
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite {
            identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
    }

    func rollback() {
        rollbackCount += 1
    }
}

private struct MutationJournalFixedClockV1: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_080) }
}

private struct MutationJournalFixedIDSourceV1: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct MutationJournalFileAuthorityV1: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C41MutationEnvelopeHasCanonicalReplayBytes() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_020)
        let bytes = try FunctionalRelationshipCanonicalCodecV1.encode(fixture.added)
        let replayed = try FunctionalRelationshipCanonicalCodecV1.decode(
            AssetFunctionalRelationshipEventV1.self, from: bytes
        )

        XCTAssertEqual(replayed, fixture.added)
        XCTAssertEqual(try FunctionalRelationshipCanonicalCodecV1.encode(replayed), bytes)
        XCTAssertEqual(replayed.mutationID, fixture.added.mutationID)
        XCTAssertEqual(replayed.revision, fixture.added.revision)
        XCTAssertEqual(replayed.eventSHA256, fixture.added.eventSHA256)
        try replayed.validate()
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C13MutationEnvelopeHasCanonicalManifestAndAttestationBytes() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_020)
        let mutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.customerManifest.mutationID,
            postImage: .appendManifest(manifest: fixture.customerManifest, preview: fixture.customerPreview)
        )
        let manifestBytes = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest)
        let attestationBytes = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation)

        try mutation.validate()
        XCTAssertEqual(try mutation.canonicalData(), try mutation.canonicalData())
        XCTAssertEqual(
            try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: manifestBytes),
            fixture.customerManifest
        )
        XCTAssertEqual(
            try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: attestationBytes),
            fixture.customerAttestation
        )
        XCTAssertEqual(fixture.customerAttestation.manifestSHA256, fixture.customerManifest.manifestSHA256)
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C14MutationReceiptUsesCanonicalTransitionDigest() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_102)
        let transition = fixture.transitions[0]
        let bundle = try InspectionReviewAtomicBundleV1(transition: transition)
        let mutation = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: transition.mutationID, postImage: .applyReviewBundle(bundle)
        )
        let digest = try mutation.canonicalSHA256()
        XCTAssertEqual(digest.count, 64)
        XCTAssertTrue(digest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(mutation.mutationID, transition.mutationID)
        XCTAssertEqual(try mutation.affectedIdentities.count, 1)
        XCTAssertEqual(try mutation.concurrencyIdentities.count, 1)
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testV23P03C18ReceiptAndSandboxRowsUseCanonicalRoundTrips() throws {
        let value = try PackageSemanticChangeV1(
            kind: .capabilityAdded,
            stableSubjectID: "c18.capability"
        )
        let encoded = try PackageEvolutionCanonicalCodecV1.encode(value)
        XCTAssertEqual(
            try PackageEvolutionCanonicalCodecV1.decode(
                PackageSemanticChangeV1.self,
                from: encoded
            ),
            value
        )
        XCTAssertEqual(value.stableKey, "CAPABILITY_ADDED:c18.capability")
        XCTAssertTrue(PackageEvolutionLifecycleV1.persistent)
        XCTAssertTrue(PackageEvolutionLifecycleV1.migrationRequired)
        XCTAssertGreaterThan(MemoryLayout<PackagePromotionReceiptV1>.size, 0)
        XCTAssertGreaterThan(MemoryLayout<PackageSandboxRunV1>.size, 0)
    }

    func testV23P03C19ReceiptBindsBundleAndJournalDigest() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let receipt = try MeasurementIntegrityWriteReceiptV1(
            workspaceID: fixture.workspace, mutationID: fixture.mutationID,
            bundleSHA256: fixture.bundle.bundleSHA256,
            journalReceiptSHA256: C19MeasurementIntegrityTestSupport.digest("j")
        )
        try MeasurementIntegrityCoordinatorV1.validate(receipt, for: fixture.bundle)
        XCTAssertEqual(receipt.bundleSHA256, fixture.bundle.bundleSHA256)
        XCTAssertThrowsError(try MeasurementIntegrityWriteReceiptV1(
            workspaceID: fixture.workspace, mutationID: fixture.mutationID,
            bundleSHA256: "not-a-digest",
            journalReceiptSHA256: C19MeasurementIntegrityTestSupport.digest("j")
        ))
    }

    func testC20PrivacyTransformReceiptBindsManifestAndDerivativeDigest() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let receipt = try PrivacyTransformPublicationReceiptV1(
            bundle: fixture.bundle,
            canonicalMutationReceiptSHA256: C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        try receipt.validate(
            bundle: fixture.bundle,
            expectedCanonicalMutationReceiptSHA256:
                C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        XCTAssertEqual(receipt.mutationID, fixture.mutationID)
        XCTAssertEqual(receipt.derivativeSHA256, fixture.manifest.derivativeSHA256)
        XCTAssertEqual(
            receipt.canonicalMutationReceiptSHA256,
            C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    @MainActor
    func testV23P03C05WorkspaceWriterCommitsExactTwoPostImagesAndCAS() throws {
        let fixture = try C05WriterMutationFixtureV1.make()
        let schema = Schema(
            PersistentSchemaV43.models,
            version: PersistentSchemaV43.versionIdentifier
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V23-P03-C05-Writer",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.workspaceID,
            replicaID: ReplicaID(rawValue: fixture.replicaID)
        )
        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: fixture.generationID
        )
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: fixture.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: fixture.writerInstanceID),
            clock: MutationJournalFixedClockV1(),
            idSource: MutationJournalFixedIDSourceV1(value: fixture.writerInstanceID),
            fileAuthority: MutationJournalFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: journal
        )

        let receipt = try writer.commitEvidenceMetadata(fixture.mutation)
        try receipt.validate()
        let journalReceipt = receipt.mutationReceipt
        let postImages = journalReceipt.postImages
        XCTAssertEqual(postImages.count, 2)
        XCTAssertEqual(
            Set(try postImages.map { try $0.identity.kind }),
            Set([.evidenceAssociationEvent, .evidenceSequenceRevision])
        )
        XCTAssertEqual(journalReceipt.expectedRevision.workspaceRevision, 0)
        XCTAssertEqual(journalReceipt.resultingRevision.workspaceRevision, 1)
        XCTAssertEqual(
            journalReceipt.expectedRevision.entityRevisions.map(\.revision),
            [0, 0]
        )
        XCTAssertEqual(
            journalReceipt.resultingRevision.entityRevisions.map(\.revision),
            [1, 1]
        )
        let associationIdentity = try EvidenceMetadataMutationV1.associationEntityIdentity(
            workspaceID: fixture.association.workspaceID,
            evidenceID: fixture.association.evidenceID
        )
        let sequenceIdentity = try WorkspaceEntityIdentityV1(
            kind: .evidenceSequenceRevision,
            id: fixture.sequence.sequenceID
        )
        let imageIdentities = try postImages.map { try $0.identity }
        XCTAssertEqual(Set(imageIdentities), Set([associationIdentity, sequenceIdentity]))
        XCTAssertEqual(
            try postImages.first(where: { try $0.identity == associationIdentity })?.revision,
            1
        )
        XCTAssertEqual(
            try postImages.first(where: { try $0.identity == sequenceIdentity })?.revision,
            1
        )
        XCTAssertEqual(
            try postImages.map { try $0.concurrencyIdentity },
            imageIdentities
        )
        XCTAssertEqual(
            try MutationReceiptV1.decodeCanonical(from: journalReceipt.canonicalData()),
            journalReceipt
        )
        XCTAssertEqual(
            try XCTUnwrap(writer.evidenceMetadataReceipt(for: fixture.mutation)),
            receipt
        )
        XCTAssertEqual(
            try writer.evidenceAssociationHistory(
                workspaceID: fixture.workspaceID,
                evidenceID: fixture.association.evidenceID
            ),
            [fixture.association]
        )
        XCTAssertEqual(
            try writer.evidenceSequenceHistory(
                workspaceID: fixture.workspaceID,
                sequenceID: fixture.sequence.sequenceID
            ),
            [fixture.sequence]
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).count, 1)

        let replay = try writer.commitEvidenceMetadata(fixture.mutation)
        XCTAssertEqual(replay, receipt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).count, 1)

        let divergent = try fixture.divergentMutation()
        XCTAssertThrowsError(try writer.commitEvidenceMetadata(divergent)) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).count, 1)

        let stale = try fixture.staleMutation()
        XCTAssertThrowsError(try writer.commitEvidenceMetadata(stale)) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).count, 1)
    }
}

private struct C05WriterMutationFixtureV1 {
    let workspaceID: WorkspaceID
    let replicaID: UUID
    let generationID: UUID
    let writerInstanceID: UUID
    let target: EvidenceAssociationTargetV1
    let policy: EvidenceCurationPolicyV1
    let reviewer: ActorSnapshotV1
    let association: EvidenceAssociationV1
    let item: EvidenceSequenceItemV1
    let sequence: EvidenceSequenceV1
    let mutation: EvidenceMetadataMutationV1

    static func make() throws -> Self {
        let workspaceID = WorkspaceID(rawValue: id(1))
        let workspaceString = workspaceID.rawValue.uuidString.lowercased()
        let target = try EvidenceAssociationTargetV1(
            workspaceID: workspaceString,
            kind: .finding,
            targetID: "finding.c05.writer",
            targetRevision: 1
        )
        let policy = try EvidenceCurationPolicyV1(
            policyID: id(2),
            workspaceID: workspaceID
        )
        let actor = try LocalActorReferenceV1(
            actorReferenceID: id(3),
            workspaceID: workspaceID,
            displayName: "C05 writer"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: id(4),
            workspaceID: workspaceID,
            actor: actor,
            responsibility: .reviewedBy,
            displayNameAtTime: "C05 writer",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        let mutationID = try MutationIDV1(rawValue: id(5))
        let association = try EvidenceAssociationV1(
            associationEventID: "association.c05.writer.1",
            workspaceID: workspaceString,
            evidenceID: "evidence.c05.writer",
            expectedEvidenceRevision: 0,
            resultingEvidenceRevision: 1,
            mutationID: mutationID.rawValue.uuidString.lowercased(),
            action: .assigned,
            contentID: "content.c05.writer",
            target: target,
            actorID: "actor.c05.writer",
            reason: "Attach the reviewed source evidence.",
            effectiveAt: "2026-08-27T00:00:00Z"
        )
        let caption = try EvidenceReviewedCaptionV1(
            text: "Writer fixture",
            provenance: .userAuthored,
            reviewer: reviewer,
            reviewedAt: Date(timeIntervalSince1970: 1_800_000_002)
        )
        let item = try EvidenceSequenceItemV1(
            evidenceID: association.evidenceID,
            contentID: try XCTUnwrap(association.contentID),
            role: .context,
            caption: caption,
            ordinal: 0,
            target: target,
            association: association
        )
        let sequence = try EvidenceSequenceV1(
            sequenceID: id(6),
            workspaceID: workspaceID,
            target: target,
            policy: policy,
            orderedItems: [item],
            revision: 1,
            mutationID: mutationID
        )
        let mutation = try EvidenceMetadataMutationV1(
            workspaceID: workspaceID,
            mutationID: mutationID,
            expectedSequenceRevision: 0,
            associationEvent: association,
            sequenceSuccessor: sequence
        )
        return Self(
            workspaceID: workspaceID,
            replicaID: id(7),
            generationID: id(8),
            writerInstanceID: id(9),
            target: target,
            policy: policy,
            reviewer: reviewer,
            association: association,
            item: item,
            sequence: sequence,
            mutation: mutation
        )
    }

    func divergentMutation() throws -> EvidenceMetadataMutationV1 {
        try makeMutation(
            mutationID: mutation.mutationID,
            associationEventID: "association.c05.writer.divergent",
            contentID: "content.c05.writer.divergent",
            sequenceRevision: 1,
            predecessor: nil,
            expectedSequenceRevision: 0,
            expectedAssociationRevision: 0
        )
    }

    func staleMutation() throws -> EvidenceMetadataMutationV1 {
        try makeMutation(
            mutationID: try MutationIDV1(rawValue: Self.id(10)),
            associationEventID: "association.c05.writer.stale",
            contentID: "content.c05.writer.stale",
            sequenceRevision: 2,
            predecessor: try sequence.reference,
            expectedSequenceRevision: 1,
            expectedAssociationRevision: 0
        )
    }

    private func makeMutation(
        mutationID: MutationIDV1,
        associationEventID: String,
        contentID: String,
        sequenceRevision: UInt64,
        predecessor: EvidenceSequenceReferenceV1?,
        expectedSequenceRevision: UInt64,
        expectedAssociationRevision: Int
    ) throws -> EvidenceMetadataMutationV1 {
        let association = try EvidenceAssociationV1(
            associationEventID: associationEventID,
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            evidenceID: self.association.evidenceID,
            expectedEvidenceRevision: expectedAssociationRevision,
            resultingEvidenceRevision: expectedAssociationRevision + 1,
            mutationID: mutationID.rawValue.uuidString.lowercased(),
            action: .assigned,
            contentID: contentID,
            target: target,
            actorID: "actor.c05.writer",
            reason: "Hostile replay candidate.",
            effectiveAt: "2026-08-27T00:00:00Z"
        )
        let caption = try EvidenceReviewedCaptionV1(
            text: "Hostile candidate",
            provenance: .userAuthored,
            reviewer: reviewer,
            reviewedAt: Date(timeIntervalSince1970: 1_800_000_003)
        )
        let item = try EvidenceSequenceItemV1(
            evidenceID: association.evidenceID,
            contentID: contentID,
            role: .context,
            caption: caption,
            ordinal: 0,
            target: target,
            association: association
        )
        let sequence = try EvidenceSequenceV1(
            sequenceID: self.sequence.sequenceID,
            workspaceID: workspaceID,
            target: target,
            policy: policy,
            orderedItems: [item],
            predecessor: predecessor,
            revision: sequenceRevision,
            mutationID: mutationID
        )
        return try EvidenceMetadataMutationV1(
            workspaceID: workspaceID,
            mutationID: mutationID,
            expectedSequenceRevision: expectedSequenceRevision,
            associationEvent: association,
            sequenceSuccessor: sequence
        )
    }

    private static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }
}

extension V10_02MutationEnvelopeReceiptTests {
    func testFinalizationLegacyEnvelopeAndSchemaOneIntentRoundTripWithoutWriterBinding() throws {
        let fixture = try FinalizationCodecAdmissionFixtureV1.make()
        let envelope = try fixture.legacyFinalizationEnvelope()
        let envelopeData = try envelope.canonicalData()
        let intent = fixture.intent(schemaVersion: 1, writerCommitBinding: nil)
        let intentData = try FinalizationContractEncoderV1().encodeIntent(intent).data

        XCTAssertEqual(try MutationEnvelopeV1.decodeCanonical(from: envelopeData), envelope)
        XCTAssertEqual(try envelope.canonicalData(), envelopeData)
        XCTAssertFalse(try XCTUnwrap(String(data: envelopeData, encoding: .utf8)).contains("writerAuthority"))
        XCTAssertEqual(try FinalizationContractDecoderV1().decodeIntent(intentData), intent)
        XCTAssertEqual(try FinalizationContractEncoderV1().encodeIntent(intent).data, intentData)
        XCTAssertFalse(try XCTUnwrap(String(data: intentData, encoding: .utf8)).contains("writerCommitBinding"))

        var explicitNullText = try XCTUnwrap(String(data: intentData, encoding: .utf8))
        explicitNullText.insert(contentsOf: "\"writerCommitBinding\":null,", at: explicitNullText.index(after: explicitNullText.startIndex))
        let explicitNull = Data(explicitNullText.utf8)
        XCTAssertThrowsError(try FinalizationContractDecoderV1().decodeIntent(explicitNull))

        let history = try fixture.history(
            envelope: envelope, postImages: fixture.finalizationPostImages
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(
            history, sourcePersistentSchemaVersion: PersistentSchemaV4.versionIdentifier.major
        ))
    }

    func testFinalizationSchemaTwoAdmitsMigratedBaselineAndRejectsHostileBindings() throws {
        let fixture = try FinalizationCodecAdmissionFixtureV1.make()
        let envelope = try fixture.boundFinalizationEnvelope()
        let binding = FinalizationWriterCommitBindingV1(
            envelopeData: try envelope.canonicalData(), occurredAt: fixture.occurredAt
        )
        let intent = fixture.intent(schemaVersion: 2, writerCommitBinding: binding)
        let encoded = try FinalizationContractEncoderV1().encodeIntent(intent).data

        XCTAssertEqual(try FinalizationContractDecoderV1().decodeIntent(encoded), intent)
        XCTAssertEqual(try XCTUnwrap(intent.writerCommitBinding).envelope(), envelope)
        XCTAssertThrowsError(try FinalizationContractEncoderV1().encodeIntent(
            fixture.intent(schemaVersion: 2, writerCommitBinding: nil)
        ))
        XCTAssertThrowsError(try FinalizationContractEncoderV1().encodeIntent(
            fixture.intent(schemaVersion: 1, writerCommitBinding: binding)
        ))
        XCTAssertThrowsError(try FinalizationContractEncoderV1().encodeIntent(
            fixture.intent(
                schemaVersion: 2, writerCommitBinding: binding,
                generationID: fixture.id(93)
            )
        ))
        XCTAssertThrowsError(try FinalizationContractEncoderV1().encodeIntent(
            fixture.intent(
                schemaVersion: 2, writerCommitBinding: binding,
                snapshotSHA256: fixture.digest("8")
            )
        ))
        XCTAssertThrowsError(try FinalizationContractEncoderV1().encodeIntent(
            fixture.intent(
                schemaVersion: 2, writerCommitBinding: binding,
                finalizationMutationID: fixture.id(94)
            )
        ))

        for hostile in try [
            fixture.hostileFinalizationEnvelope(recordID: fixture.id(90)),
            fixture.hostileFinalizationEnvelope(contentDigests: [fixture.digest("9")]),
            fixture.hostileFinalizationEnvelope(workspaceID: WorkspaceID(rawValue: fixture.id(91))),
        ] {
            let hostileBinding = FinalizationWriterCommitBindingV1(
                envelopeData: try hostile.canonicalData(), occurredAt: fixture.occurredAt
            )
            XCTAssertThrowsError(try FinalizationContractEncoderV1().encodeIntent(
                fixture.intent(schemaVersion: 2, writerCommitBinding: hostileBinding)
            ))
            XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
                fixture.history(envelope: hostile, postImages: fixture.finalizationPostImages),
                sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
            ))
        }

        var mismatchedImages = try fixture.finalizationPostImages
        let recordIndex = try XCTUnwrap(mismatchedImages.firstIndex {
            (try? $0.identity.kind) == .workflowRecord
        })
        mismatchedImages[recordIndex] = .workflowRecord(
            id: fixture.recordID, revision: 2, semanticSHA256: fixture.digest("7")
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(envelope: envelope, postImages: mismatchedImages),
            sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
        let missingAssetLock = try fixture.hostileFinalizationEnvelope(includeAssetLock: false)
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: missingAssetLock, postImages: fixture.finalizationPostImages
            ), sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
        let migratedDraftBaseline = try fixture.hostileFinalizationEnvelope(recordRevision: 0)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: migratedDraftBaseline,
                postImages: try fixture.finalizationPostImages(recordRevision: 1)
            ), sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
        let advancedAssetRevision = WorkspaceEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(kind: .asset, id: fixture.assetID),
            revision: 8
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: envelope, postImages: fixture.finalizationPostImages,
                overriddenResultingRevisions: [advancedAssetRevision]
            ), sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
        let wrongNewReportRevision = try fixture.hostileFinalizationEnvelope(reportRevision: 1)
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: wrongNewReportRevision,
                postImages: try fixture.finalizationPostImages(reportRevision: 2)
            ), sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
    }

    func testOriginalSourceV53AdmitsBoundFinalizationAndPDFButV52RejectsBoth() throws {
        let fixture = try FinalizationCodecAdmissionFixtureV1.make()
        let finalizationEnvelope = try fixture.boundFinalizationEnvelope()
        let pdfEnvelope = try fixture.pdfTransitionEnvelope()
        let cases = [
            try fixture.history(
                envelope: finalizationEnvelope, postImages: fixture.finalizationPostImages
            ),
            try fixture.history(
                envelope: pdfEnvelope, postImages: [try fixture.pdfPostImage(revision: 2)],
                additionalResultingRevisions: [
                    .init(
                        identity: WorkspaceEntityIdentityV1(kind: .asset, id: fixture.assetID),
                        revision: 7
                    ),
                ]
            ),
        ]

        for history in cases {
            XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(
                history, sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
            ))
            XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
                history, sourcePersistentSchemaVersion: PersistentSchemaV52.versionIdentifier.major
            )) { error in
                XCTAssertEqual(error as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
        }

        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: pdfEnvelope,
                postImages: [.report(
                    id: fixture.reportID, revision: 2, semanticSHA256: fixture.digest("f")
                )]
            ), sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
        let wrongOuterRevision = try fixture.pdfTransitionEnvelope(outerEntityRevision: 2)
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: wrongOuterRevision,
                postImages: [try fixture.pdfPostImage(revision: 3)]
            ), sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
        let wrongOuterWorkspace = try fixture.pdfTransitionEnvelope(
            outerWorkspaceID: WorkspaceID(rawValue: fixture.id(92))
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(
            fixture.history(
                envelope: wrongOuterWorkspace,
                postImages: [try fixture.pdfPostImage(revision: 2)]
            ),
            sourcePersistentSchemaVersion: PersistentSchemaV53.versionIdentifier.major
        ))
    }
}

private struct FinalizationCodecAdmissionFixtureV1 {
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let generationID: UUID
    let finalizationMutationID: MutationIDV1
    let recordID: UUID
    let packetID: UUID
    let stableRootID: UUID
    let reportID: UUID
    let assetID: UUID
    let completedAt: Date
    let snapshotCreatedAt: Date
    let occurredAt: Date
    let snapshotSHA256: String
    let contentDigests: [String]
    let payload: FinalizationPayloadV1
    let payloadSHA256: String
    let authority: FinalizationWriterAuthorityV1
    let sourceBinding: FinalizationWriterSourceBindingV1
    let report: ReportPayloadV1

    static func make() throws -> Self {
        let workspaceID = WorkspaceID(rawValue: Self.id(1))
        let generationID = Self.id(3)
        let mutationID = try MutationIDV1(rawValue: Self.id(4))
        let recordID = Self.id(5)
        let packetID = Self.id(6)
        let stableRootID = Self.id(7)
        let reportID = Self.id(8)
        let assetID = Self.id(10)
        let completedAt = Date(timeIntervalSince1970: 1_800_100_001)
        let snapshotCreatedAt = Date(timeIntervalSince1970: 1_800_100_002)
        let snapshotSHA256 = Self.digest("a")
        let migratedObservation = try ObservationAndTimeMigrationV1.migrate(
            existingObservationBasisData: nil, existingTemporalContextData: nil,
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil, observedAtUTC: completedAt,
            recordedAtUTC: completedAt, timeZoneID: "UTC", utcOffsetMinutes: 0,
            localDate: "2027-01-16", localTime: "08:00:01"
        )
        let record = WorkflowRecordPayloadV1(
            id: recordID, schemaVersion: 1, assetID: assetID, packetID: packetID,
            issueID: nil, parentRecordID: nil, recordRevisionRootID: recordID,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue,
            state: WorkflowState.completed.rawValue,
            draftStepKey: nil, startedAt: completedAt.addingTimeInterval(-60),
            completedAt: completedAt, observedAtUTC: completedAt, timeZoneID: "UTC",
            utcOffsetMinutes: 0, localDate: "2027-01-16", localTime: "08:00:01",
            afterDarkAcknowledgementKey: "after_dark",
            afterDarkAcknowledgementCopy: "Work after dark requires care.",
            afterDarkAcknowledgementVersion: "1", afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: "safe_authorized_position",
            safePositionAcknowledgementCopy: "Work from a safe position.",
            safePositionAcknowledgementVersion: "1", safePositionAcknowledgementAccepted: true,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: "no_visible_issue", couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: mutationID.rawValue
        )
        let packet = PacketPayloadV1(
            id: packetID, schemaVersion: 1, stableRootID: stableRootID,
            currentRecordID: recordID, evaluationCounted: true,
            contentDeletedAt: nil, createdAt: completedAt
        )
        let report = ReportPayloadV1(
            id: reportID, schemaVersion: 1, packetID: packetID,
            sourceRecordID: recordID, snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(reportID.uuidString.lowercased()).json",
            snapshotSHA256: snapshotSHA256, pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil, pdfSHA256: nil, createdAt: snapshotCreatedAt,
            replacesReportID: nil
        )
        let payload = FinalizationPayloadV1(
            issueInsert: nil, issueTransition: nil, packetAfter: packet,
            packetBefore: nil, reportInsert: report, workflowRecordAfter: record
        )
        let payloadSHA256 = try FinalizationContractEncoderV1().encodePayload(payload).sha256
        let contentDigests = [Self.digest("b"), Self.digest("c")]
        let sourceBinding = FinalizationWriterSourceBindingV1(
            sourceRecordID: recordID,
            observationBasisV1Data: try XCTUnwrap(migratedObservation.observationBasisData),
            temporalContextV1Data: try XCTUnwrap(migratedObservation.temporalContextData),
            requirementAssurance: nil
        )
        let authority = FinalizationWriterAuthorityV1(
            workspaceID: workspaceID, generationID: generationID, payload: payload,
            payloadSHA256: payloadSHA256,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: snapshotSHA256, contentDigests: contentDigests,
            sourceBinding: sourceBinding
        )
        try authority.validate()
        return Self(
            workspaceID: workspaceID, replicaID: ReplicaID(rawValue: Self.id(2)),
            generationID: generationID, finalizationMutationID: mutationID,
            recordID: recordID, packetID: packetID, stableRootID: stableRootID,
            reportID: reportID, assetID: assetID,
            completedAt: completedAt, snapshotCreatedAt: snapshotCreatedAt,
            occurredAt: Date(timeIntervalSince1970: 1_800_100_003),
            snapshotSHA256: snapshotSHA256, contentDigests: contentDigests,
            payload: payload, payloadSHA256: payloadSHA256, authority: authority,
            sourceBinding: sourceBinding, report: report
        )
    }

    var finalizationPostImages: [MutationPostImageV1] {
        get throws { try finalizationPostImages(recordRevision: 2) }
    }

    func finalizationPostImages(
        recordRevision: UInt64 = 2, packetRevision: UInt64 = 1,
        reportRevision: UInt64 = 1
    ) throws -> [MutationPostImageV1] {
            let record = payload.workflowRecordAfter
            let recordDTO = V4BackupWorkflowRecordDTO(
                id: record.id, schemaVersion: record.schemaVersion, assetID: record.assetID,
                packetID: record.packetID, issueID: record.issueID,
                parentRecordID: record.parentRecordID,
                recordRevisionRootID: record.recordRevisionRootID,
                revisesRecordID: record.revisesRecordID,
                evidenceSourceRecordID: record.evidenceSourceRecordID,
                revisionKind: record.revisionKind, stage: record.stage, state: record.state,
                draftStepKey: record.draftStepKey, startedAt: record.startedAt,
                completedAt: record.completedAt, observedAtUTC: record.observedAtUTC,
                timeZoneID: record.timeZoneID, utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate, localTime: record.localTime,
                afterDarkAcknowledgementKey: record.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: record.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: record.afterDarkAcknowledgementVersion,
                afterDarkAcknowledgementAccepted: record.afterDarkAcknowledgementAccepted,
                safePositionAcknowledgementKey: record.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy: record.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion: record.safePositionAcknowledgementVersion,
                safePositionAcknowledgementAccepted: record.safePositionAcknowledgementAccepted,
                packID: record.packID, packSchemaVersion: record.packSchemaVersion,
                packContentVersion: record.packContentVersion,
                pdfTemplateID: record.pdfTemplateID, pdfTemplateVersion: record.pdfTemplateVersion,
                outcomeKey: record.outcomeKey, couldNotVerifyKey: record.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
                workPerformedLocalDate: record.workPerformedLocalDate,
                workDescription: record.workDescription, note: record.note,
                finalizationMutationID: record.finalizationMutationID,
                observationBasisV1Data: sourceBinding.observationBasisV1Data,
                temporalContextV1Data: sourceBinding.temporalContextV1Data
            )
            let recordValue = FinalizationCodecWorkflowRecordPostImageV8(
                record: recordDTO, requirementAssurance: nil
            )
            let packet = payload.packetAfter
            let packetValue = V4BackupPacketDTO(
                id: packet.id, schemaVersion: packet.schemaVersion,
                stableRootID: packet.stableRootID, currentRecordID: packet.currentRecordID,
                evaluationCounted: packet.evaluationCounted,
                contentDeletedAt: packet.contentDeletedAt, createdAt: packet.createdAt
            )
            let reportValue = V4BackupReportDTO(
                id: report.id, schemaVersion: report.schemaVersion, packetID: report.packetID,
                sourceRecordID: report.sourceRecordID,
                snapshotSchemaVersion: report.snapshotSchemaVersion,
                snapshotRelativePath: report.snapshotRelativePath,
                snapshotSHA256: report.snapshotSHA256, pdfState: report.pdfState,
                pdfRelativePath: report.pdfRelativePath, pdfSHA256: report.pdfSHA256,
                createdAt: report.createdAt, replacesReportID: report.replacesReportID
            )
            return try [
                postImage(
                    .workflowRecord, id: record.id, revision: recordRevision,
                    value: recordValue
                ),
                postImage(.packet, id: packet.id, revision: packetRevision, value: packetValue),
                postImage(.report, id: report.id, revision: reportRevision, value: reportValue),
            ].sorted { try $0.identity.stableKey < $1.identity.stableKey }
    }

    func pdfPostImage(revision: UInt64) throws -> MutationPostImageV1 {
        let ready = V4BackupReportDTO(
            id: report.id, schemaVersion: report.schemaVersion, packetID: report.packetID,
            sourceRecordID: report.sourceRecordID,
            snapshotSchemaVersion: report.snapshotSchemaVersion,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: report.snapshotSHA256, pdfState: ReportPDFState.ready.rawValue,
            pdfRelativePath: "pdfs/\(reportID.uuidString.lowercased()).pdf",
            pdfSHA256: digest("e"), createdAt: report.createdAt,
            replacesReportID: report.replacesReportID
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .report, id: reportID)
        let semanticSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            FinalizationCodecPostImageDigestBasisV1(
                identity: identity, revision: revision, value: ready
            )
        )
        return .report(id: reportID, revision: revision, semanticSHA256: semanticSHA256)
    }

    func legacyFinalizationEnvelope() throws -> MutationEnvelopeV1 {
        try finalizationEnvelope(writerAuthority: nil)
    }

    func boundFinalizationEnvelope() throws -> MutationEnvelopeV1 {
        try finalizationEnvelope(writerAuthority: authority)
    }

    func hostileFinalizationEnvelope(
        recordID: UUID? = nil, contentDigests: [String]? = nil,
        workspaceID: WorkspaceID? = nil, recordRevision: UInt64 = 1,
        reportRevision: UInt64 = 0, includeAssetLock: Bool = true
    ) throws -> MutationEnvelopeV1 {
        try finalizationEnvelope(
            writerAuthority: authority, recordID: recordID ?? self.recordID,
            contentDigests: contentDigests ?? self.contentDigests,
            workspaceID: workspaceID ?? self.workspaceID,
            recordRevision: recordRevision, reportRevision: reportRevision,
            includeAssetLock: includeAssetLock
        )
    }

    func intent(
        schemaVersion: Int, writerCommitBinding: FinalizationWriterCommitBindingV1?,
        generationID: UUID? = nil, snapshotSHA256: String? = nil,
        finalizationMutationID: UUID? = nil
    ) -> FinalizationIntentV1 {
        FinalizationIntentV1(
            completedAt: completedAt,
            finalizationMutationID: finalizationMutationID ?? self.finalizationMutationID.rawValue,
            finalizationPayload: payload, finalizationPayloadSHA256: payloadSHA256,
            generationID: generationID ?? self.generationID,
            packetID: packetID, phase: .prepared,
            recordID: recordID, reportID: reportID, schemaVersion: schemaVersion,
            snapshotCreatedAt: snapshotCreatedAt,
            snapshotFinalRelativePath: report.snapshotRelativePath,
            snapshotSHA256: snapshotSHA256 ?? self.snapshotSHA256,
            snapshotStagingRelativePath: ".staging/\(reportID.uuidString.lowercased()).json",
            stableRootID: stableRootID, writerCommitBinding: writerCommitBinding
        )
    }

    func pdfTransitionEnvelope(
        outerWorkspaceID: WorkspaceID? = nil, outerEntityRevision: UInt64 = 1
    ) throws -> MutationEnvelopeV1 {
        let command = try ReportPDFTransitionMutationV1.make(
            workspaceID: workspaceID, generationID: generationID,
            expectedReportRevision: 1, reportBefore: report,
            transition: .pendingToReady(
                relativePath: "pdfs/\(reportID.uuidString.lowercased()).pdf",
                sha256: digest("e"), byteCount: 128
            )
        )
        return try envelope(
            mutationID: command.mutationID, command: .transitionReportPDF(command),
            identity: try WorkspaceEntityIdentityV1(kind: .report, id: reportID),
            entityRevision: outerEntityRevision,
            workspaceID: outerWorkspaceID ?? workspaceID
        )
    }

    func history(
        envelope: MutationEnvelopeV1, postImages: [MutationPostImageV1],
        additionalResultingRevisions: [WorkspaceEntityRevisionV1] = [],
        overriddenResultingRevisions: [WorkspaceEntityRevisionV1] = []
    ) throws -> MutationHistorySnapshotV1 {
        let imageRevisions = try postImages.map {
            WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
        }
        let imageIdentities = Set(imageRevisions.map(\.identity))
        let overriddenIdentities = Set(overriddenResultingRevisions.map(\.identity))
        let unchangedLocks = envelope.expectedRevision.entityRevisions.filter {
            !imageIdentities.contains($0.identity) && !overriddenIdentities.contains($0.identity)
        }
        let resultingRevisions = (
            imageRevisions + unchangedLocks + additionalResultingRevisions
                + overriddenResultingRevisions
        ).sorted {
            $0.identity.stableKey < $1.identity.stableKey
        }
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: envelope.workspaceID, generationID: envelope.generationID,
            writerInstanceID: id(70), workspaceRevision: 1,
            entityRevisions: resultingRevisions
        )
        let receipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: envelope.workspaceID, replicaID: envelope.replicaID, localSequence: 1
            ), envelope: envelope,
            resultingRevision: MutationPortableExpectedRevisionV1(resulting),
            postImages: postImages, committedAt: occurredAt
        )
        return MutationHistorySnapshotV1(
            workspaceRevision: 1, lastLocalSequence: 1,
            receipts: [.init(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil, semanticReversalData: nil
            )], quarantines: [],
            entityRevisions: resultingRevisions
        )
    }

    func digest(_ character: Character) -> String {
        Self.digest(character)
    }

    func id(_ byte: UInt8) -> UUID { Self.id(byte) }

    private func finalizationEnvelope(
        writerAuthority: FinalizationWriterAuthorityV1?,
        recordID: UUID? = nil, contentDigests: [String]? = nil,
        workspaceID: WorkspaceID? = nil, recordRevision: UInt64 = 1,
        reportRevision: UInt64 = 0, includeAssetLock: Bool = true
    ) throws -> MutationEnvelopeV1 {
        let command = FinalizeCheckMutationV1(
            finalizationMutationID: finalizationMutationID.rawValue,
            assetID: assetID, recordID: recordID ?? self.recordID,
            packetID: packetID, reportID: reportID, issueID: nil,
            semanticDigest: payloadSHA256,
            contentDigests: contentDigests ?? self.contentDigests,
            writerAuthority: writerAuthority
        )
        var revisions = try [
            WorkspaceEntityRevisionV1(
                identity: WorkspaceEntityIdentityV1(kind: .workflowRecord, id: self.recordID),
                revision: recordRevision
            ),
            WorkspaceEntityRevisionV1(
                identity: WorkspaceEntityIdentityV1(kind: .packet, id: packetID), revision: 0
            ),
            WorkspaceEntityRevisionV1(
                identity: WorkspaceEntityIdentityV1(kind: .report, id: reportID),
                revision: reportRevision
            ),
        ]
        if includeAssetLock {
            revisions.append(WorkspaceEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
                revision: 7
            ))
        }
        return try envelope(
            mutationID: finalizationMutationID, command: .finalizeCheck(command),
            entityRevisions: revisions, workspaceID: workspaceID ?? self.workspaceID,
            contentDependencyIDs: writerAuthority == nil ? [] : (contentDigests ?? self.contentDigests)
        )
    }

    private func envelope(
        mutationID: MutationIDV1, command: WorkspaceCommandV1,
        identity: WorkspaceEntityIdentityV1? = nil, entityRevision: UInt64 = 0,
        entityRevisions: [WorkspaceEntityRevisionV1]? = nil,
        workspaceID: WorkspaceID? = nil, contentDependencyIDs: [String] = []
    ) throws -> MutationEnvelopeV1 {
        let envelopeWorkspaceID = workspaceID ?? self.workspaceID
        let expectedEntityRevisions: [WorkspaceEntityRevisionV1]
        if let entityRevisions {
            expectedEntityRevisions = entityRevisions
        } else {
            expectedEntityRevisions = [WorkspaceEntityRevisionV1(
                identity: try XCTUnwrap(identity), revision: entityRevision
            )]
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: envelopeWorkspaceID, generationID: generationID,
            writerInstanceID: id(71), workspaceRevision: 0,
            entityRevisions: expectedEntityRevisions
        )
        return try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: mutationID, expectedRevision: expected, command: command
            ), identity: WorkspaceReplicaIdentityV1(
                workspaceID: envelopeWorkspaceID, replicaID: replicaID
            ), contentDependencyIDs: contentDependencyIDs
        )
    }

    private static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }

    private func postImage<Value: Codable>(
        _ kind: WorkspaceEntityKindV1, id: UUID, revision: UInt64, value: Value
    ) throws -> MutationPostImageV1 {
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
        let semanticSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            FinalizationCodecPostImageDigestBasisV1(
                identity: identity, revision: revision, value: value
            )
        )
        switch kind {
        case .workflowRecord:
            return .workflowRecord(id: id, revision: revision, semanticSHA256: semanticSHA256)
        case .packet:
            return .packet(id: id, revision: revision, semanticSHA256: semanticSHA256)
        case .report:
            return .report(id: id, revision: revision, semanticSHA256: semanticSHA256)
        default:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }
}

private struct FinalizationCodecPostImageDigestBasisV1<Value: Codable>: Codable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let value: Value
}

private struct FinalizationCodecWorkflowRecordPostImageV8: Codable {
    let record: V4BackupWorkflowRecordDTO
    let requirementAssurance: RequirementAssuranceSnapshotV1?
}
