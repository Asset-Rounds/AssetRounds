import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerBeginHistoryTests: XCTestCase {
    func testShippingBeginReturnsExactTimeZoneAndDraftHistoryWithoutCollapsingRevisionSnapshot() throws {
        try withHarness("shipping-begin") { h in
            let count = try h.records().count
            let draft = try h.beginCheck()
            XCTAssertEqual(try h.records().count, count + 2)
            let zone = try h.onlyPair(.updateSiteTimeZone)
            let create = try h.onlyPair(.createCheckDraft)
            let before = try h.snapshot()

            for pair in [zone, create] {
                let direct = try XCTUnwrap(h.journal.checkRunnerBeginEvidence(
                    workspaceID: pair.envelope.workspaceID, mutationID: pair.envelope.mutationID
                ))
                let wrapped = try XCTUnwrap(h.writer.checkRunnerBeginEvidence(
                    workspaceID: pair.envelope.workspaceID, mutationID: pair.envelope.mutationID
                ))
                XCTAssertEqual(direct, wrapped)
                XCTAssertEqual(direct.envelope, pair.envelope)
                XCTAssertEqual(direct.receipt, pair.receipt)
                XCTAssertEqual(try direct.envelope.canonicalData(), pair.record.envelopeData)
                XCTAssertEqual(try direct.receipt.canonicalData(), pair.record.receiptData)
                XCTAssertEqual(direct.envelopeSHA256, try pair.envelope.canonicalSHA256())
                XCTAssertGreaterThan(direct.receipt.resultingRevision.entityRevisions.count, 1)
            }
            guard case let .updateSiteTimeZone(originalZone) = zone.envelope.command,
                  case let .updateSiteTimeZone(returnedZone) = try XCTUnwrap(
                    h.journal.checkRunnerBeginEvidence(
                        workspaceID: h.workspaceID, mutationID: zone.envelope.mutationID
                    )
                  ).command,
                  case let .createCheckDraft(originalCreate) = create.envelope.command,
                  case let .createCheckDraft(returnedCreate) = try XCTUnwrap(
                    h.journal.checkRunnerBeginEvidence(
                        workspaceID: h.workspaceID, mutationID: create.envelope.mutationID
                    )
                  ).command else {
                return XCTFail("Expected exact retained Begin commands")
            }
            XCTAssertEqual(returnedZone, originalZone)
            XCTAssertEqual(returnedZone.confirmedAt, h.observedAt)
            XCTAssertEqual(returnedCreate, originalCreate)
            XCTAssertEqual(returnedCreate.recordID, draft.id)
            XCTAssertEqual(returnedCreate.startedAt, h.observedAt)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testExplicitWorkspaceNamespaceDistinguishesSameMutationIDAndReturnsAbsence() throws {
        let mutationID = try MutationIDV1(rawValue: UUID())
        var foreignRecords: [MutationHistoryReceiptRecordV1] = []
        var foreignPair: BeginHistoryHarness.Pair?
        var foreignOnlyPair: BeginHistoryHarness.Pair?
        var foreignWorkspaceID: WorkspaceID?
        var foreignSiteID: UUID?
        try withHarness("foreign") { source in
            try source.commitTimeZone(mutationID, "America/Chicago")
            _ = try source.beginCheck()
            foreignRecords = try source.records()
            foreignPair = try source.pair(source.workspaceID, mutationID)
            foreignOnlyPair = try source.onlyPair(.createCheckDraft)
            foreignWorkspaceID = source.workspaceID
            foreignSiteID = source.siteID
        }

        try withHarness("local") { target in
            try target.commitTimeZone(mutationID, "America/New_York")
            let local = try target.pair(target.workspaceID, mutationID)
            let foreign = try XCTUnwrap(foreignPair)
            let foreignOnly = try XCTUnwrap(foreignOnlyPair)
            for record in foreignRecords {
                target.context.insert(try MutationReceiptRow(
                    envelope: MutationEnvelopeV1.decodeCanonical(from: record.envelopeData),
                    receipt: MutationReceiptV1.decodeCanonical(from: record.receiptData),
                    reversalBasis: try record.reversalBasisData.map { try ReversalBasisV1.decodeCanonical(from: $0) },
                    semanticReversal: try record.semanticReversalData.map { try SemanticReversalReceiptV1.decodeCanonical(from: $0) }
                ))
            }
            try target.context.save()
            let foreignWorkspace = try XCTUnwrap(foreignWorkspaceID)
            let transported = try target.context.fetch(FetchDescriptor<MutationReceiptRow>()).filter {
                $0.workspaceID == foreignWorkspace.rawValue
            }
            XCTAssertEqual(transported.count, foreignRecords.count)
            for record in foreignRecords {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
                let key = MutationWorkspaceKeyV1.value(
                    workspaceID: envelope.workspaceID,
                    mutationID: envelope.mutationID
                )
                let row = try XCTUnwrap(transported.first { $0.workspaceMutationKey == key })
                XCTAssertEqual(row.mutationID, envelope.mutationID.rawValue)
                XCTAssertEqual(row.receiptIdentity, receipt.identity.stableKey)
                XCTAssertEqual(row.workspaceID, receipt.identity.workspaceID.rawValue)
                XCTAssertEqual(row.replicaID, receipt.identity.replicaID.rawValue)
                XCTAssertEqual(row.localSequence, Int64(receipt.identity.localSequence))
                XCTAssertEqual(row.commandKind, envelope.commandKind.rawValue)
                XCTAssertEqual(row.envelopeData, record.envelopeData)
                XCTAssertEqual(row.envelopeSHA256, try envelope.canonicalSHA256())
                XCTAssertEqual(row.receiptData, record.receiptData)
                XCTAssertEqual(row.receiptSHA256, try receipt.canonicalSHA256())
                XCTAssertEqual(row.reversalBasisData, record.reversalBasisData)
                XCTAssertEqual(
                    row.reversalBasisSHA256,
                    try record.reversalBasisData.map {
                        try ReversalBasisV1.decodeCanonical(from: $0).canonicalSHA256()
                    }
                )
                XCTAssertEqual(row.semanticReversalData, record.semanticReversalData)
            }
            let before = try target.snapshot()
            let localEvidence = try XCTUnwrap(target.journal.checkRunnerBeginEvidence(
                workspaceID: target.workspaceID, mutationID: mutationID
            ))
            let foreignEvidence = try XCTUnwrap(target.journal.checkRunnerBeginEvidence(
                workspaceID: foreignWorkspace, mutationID: mutationID
            ))
            XCTAssertEqual(localEvidence.envelope, local.envelope)
            XCTAssertEqual(foreignEvidence.envelope, foreign.envelope)
            XCTAssertEqual(foreignEvidence.receipt, foreign.receipt)
            XCTAssertEqual(try foreignEvidence.envelope.canonicalData(), foreign.record.envelopeData)
            XCTAssertEqual(try foreignEvidence.receipt.canonicalData(), foreign.record.receiptData)
            XCTAssertEqual(foreignEvidence.envelope.generationID, foreign.envelope.generationID)
            XCTAssertEqual(foreignEvidence.receipt.identity, foreign.receipt.identity)
            XCTAssertEqual(foreignEvidence.receipt.committedAt, foreign.receipt.committedAt)
            XCTAssertNotEqual(localEvidence.envelopeSHA256, foreignEvidence.envelopeSHA256)
            let foreignSite = try XCTUnwrap(foreignSiteID)
            XCTAssertFalse(try target.context.fetch(FetchDescriptor<Site>()).contains { $0.id == foreignSite })
            XCTAssertNil(try target.journal.checkRunnerBeginEvidence(
                workspaceID: target.workspaceID,
                mutationID: foreignOnly.envelope.mutationID
            ))
            XCTAssertEqual(
                try target.journal.checkRunnerBeginEvidence(
                    workspaceID: foreignOnly.envelope.workspaceID,
                    mutationID: foreignOnly.envelope.mutationID
                )?.receipt,
                foreignOnly.receipt
            )
            XCTAssertNil(try target.journal.checkRunnerBeginEvidence(
                workspaceID: target.workspaceID, mutationID: MutationIDV1(rawValue: UUID())
            ))
            XCTAssertEqual(try target.snapshot(), before)
        }
    }

    func testDirtyContextDeniesHistoricalPresenceWithoutChangingRows() throws {
        try withHarness("dirty") { h in
            try h.commitTimeZone(h.selectedMutationID, "America/New_York")
            let clean = try h.snapshot()
            let site = try XCTUnwrap(h.context.fetch(FetchDescriptor<Site>()).first)
            site.label = "Unsaved label"
            let dirty = try h.snapshot()
            XCTAssertNotEqual(dirty, clean)
            XCTAssertTrue(dirty.hasChanges)
            assertFailure(.persistenceFailed) {
                _ = try h.journal.checkRunnerBeginEvidence(
                    workspaceID: h.workspaceID, mutationID: h.selectedMutationID
                )
            }
            XCTAssertEqual(try h.snapshot(), dirty)
            h.context.rollback()
        }
    }

    func testInvalidatedWriterDeniesHistoricalRead() throws {
        try withHarness("retired-lease") { h in
            try h.commitTimeZone(h.selectedMutationID, "America/New_York")
            let before = try h.snapshot()
            try h.retireJournalLease()
            assertFailure(.wrongGeneration) {
                _ = try h.journal.checkRunnerBeginEvidence(
                    workspaceID: h.workspaceID, mutationID: h.selectedMutationID
                )
            }
            XCTAssertEqual(try h.snapshot(), before)
            h.writer.invalidate()
            assertFailure(.writerInvalidated) {
                _ = try h.writer.checkRunnerBeginEvidence(
                    workspaceID: h.workspaceID, mutationID: h.selectedMutationID
                )
            }
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testSelectedQuarantineDeniesHistoricalPresenceWithoutChangingHistory() throws {
        try withHarness("quarantine") { h in
            try h.commitTimeZone(h.selectedMutationID, "America/New_York")
            let pair = try h.pair(h.workspaceID, h.selectedMutationID)
            h.context.insert(MutationQuarantineRow(
                workspaceID: h.workspaceID,
                mutationID: h.selectedMutationID,
                identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: pair.receipt.envelopeSHA256,
                conflictingIdentitySHA256: String(repeating: "b", count: 64),
                detectedAt: h.observedAt
            ))
            try h.context.save()
            let before = try h.snapshot()
            assertFailure(.mutationIDQuarantined) {
                _ = try h.journal.checkRunnerBeginEvidence(
                    workspaceID: h.workspaceID, mutationID: h.selectedMutationID
                )
            }
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testWholeJournalCorruptionDeniesSelectedPresenceAndAbsenceWithoutWriting() throws {
        let corruptions: [(String, (MutationReceiptRow) -> Void)] = [
            ("mutation-id", { $0.mutationID = UUID() }),
            ("workspace-key", { $0.workspaceMutationKey += "-corrupt" }),
            ("receipt-identity", { $0.receiptIdentity += "-corrupt" }),
            ("workspace-id", { $0.workspaceID = UUID() }),
            ("replica-id", { $0.replicaID = UUID() }),
            ("local-sequence", { $0.localSequence += 1 }),
            ("command-kind", { $0.commandKind = "CORRUPT_COMMAND_KIND" }),
            ("envelope-bytes", { $0.envelopeData.append(0) }),
            ("envelope-digest", { $0.envelopeSHA256 = String(repeating: "d", count: 64) }),
            ("receipt-bytes", { $0.receiptData.append(0) }),
            ("receipt-digest", { $0.receiptSHA256 = String(repeating: "e", count: 64) }),
            ("reversal-basis", {
                $0.reversalBasisData = Data("{}".utf8)
                $0.reversalBasisSHA256 = String(repeating: "f", count: 64)
            }),
            ("semantic-reversal", { $0.semanticReversalData = Data("{}".utf8) }),
        ]
        for (label, corrupt) in corruptions {
            try withHarness("whole-journal-\(label)") { h in
                try h.commitTimeZone(h.selectedMutationID, "America/New_York")
                let unrelated = try XCTUnwrap(
                    h.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                        $0.mutationID != h.selectedMutationID.rawValue
                    }
                )
                corrupt(unrelated)
                try h.context.save()
                let before = try h.snapshot()
                for id in [h.selectedMutationID, try MutationIDV1(rawValue: UUID())] {
                    assertFailure(.receiptHistoryCorrupt) {
                        _ = try h.journal.checkRunnerBeginEvidence(workspaceID: h.workspaceID, mutationID: id)
                    }
                }
                XCTAssertEqual(try h.snapshot(), before, label)
            }
        }
        for label in ["state-revision", "entity-revision"] {
            try withHarness("whole-journal-\(label)") { h in
                try h.commitTimeZone(h.selectedMutationID, "America/New_York")
                if label == "state-revision" {
                    let state = try XCTUnwrap(
                        h.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first
                    )
                    state.workspaceRevision += 1
                } else {
                    let revision = try XCTUnwrap(
                        h.context.fetch(FetchDescriptor<EntityMutationRevisionRow>()).first
                    )
                    revision.revision += 1
                }
                try h.context.save()
                let before = try h.snapshot()
                for id in [h.selectedMutationID, try MutationIDV1(rawValue: UUID())] {
                    assertFailure(.receiptHistoryCorrupt) {
                        _ = try h.journal.checkRunnerBeginEvidence(
                            workspaceID: h.workspaceID,
                            mutationID: id
                        )
                    }
                }
                XCTAssertEqual(try h.snapshot(), before, label)
            }
        }
    }

    func testTypedEvidenceRejectsUnsupportedMismatchedAndGenericValidWrongEffects() throws {
        try withHarness("typed") { h in
            _ = try h.beginCheck()
            let zone = try h.onlyPair(.updateSiteTimeZone)
            let draft = try h.onlyPair(.createCheckDraft)
            let unsupported = try h.onlyPair(.createFirstSign)
            assertHistoryCorrupt {
                _ = try CheckRunnerBeginCommittedEvidenceV1(
                    envelope: zone.envelope, receipt: draft.receipt
                )
            }
            let oneImageUnsupported = try MutationReceiptV1(
                identity: unsupported.receipt.identity,
                envelope: unsupported.envelope,
                resultingRevision: unsupported.receipt.resultingRevision,
                postImages: [try XCTUnwrap(unsupported.receipt.postImages.first)],
                committedAt: unsupported.receipt.committedAt
            )
            try oneImageUnsupported.validate()
            assertHistoryCorrupt {
                _ = try CheckRunnerBeginCommittedEvidenceV1(
                    envelope: unsupported.envelope, receipt: oneImageUnsupported
                )
            }
            guard case let .updateSiteTimeZone(command) = zone.envelope.command else {
                return XCTFail("Expected retained time-zone command")
            }
            let wrong = try h.syntheticPair(command: command, effects: [
                .site(id: UUID(), revision: 1, semanticSHA256: String(repeating: "c", count: 64))
            ])
            try wrong.envelope.validate(); try wrong.receipt.validate()
            assertHistoryCorrupt {
                _ = try CheckRunnerBeginCommittedEvidenceV1(
                    envelope: wrong.envelope, receipt: wrong.receipt
                )
            }
            let extra = try h.syntheticPair(command: command, effects: [
                .site(id: command.siteID, revision: 1, semanticSHA256: String(repeating: "a", count: 64)),
                .workflowRecord(id: UUID(), revision: 1, semanticSHA256: String(repeating: "b", count: 64)),
            ])
            try extra.envelope.validate(); try extra.receipt.validate()
            assertHistoryCorrupt {
                _ = try CheckRunnerBeginCommittedEvidenceV1(
                    envelope: extra.envelope, receipt: extra.receipt
                )
            }
            let provenanceID = try MutationIDV1(rawValue: UUID())
            let provenanceWriterID = UUID()
            let provenanceEffect: [MutationPostImageV1] = [
                .site(
                    id: command.siteID,
                    revision: 1,
                    semanticSHA256: String(repeating: "d", count: 64)
                )
            ]
            let localProvenance = try h.syntheticPair(
                command: command,
                effects: provenanceEffect,
                mutationID: provenanceID,
                writerID: provenanceWriterID,
                sourceKind: .localUser
            )
            let importedProvenance = try h.syntheticPair(
                command: command,
                effects: provenanceEffect,
                mutationID: provenanceID,
                writerID: provenanceWriterID,
                sourceKind: .importedHistory
            )
            assertHistoryCorrupt {
                _ = try CheckRunnerBeginCommittedEvidenceV1(
                    envelope: importedProvenance.envelope,
                    receipt: localProvenance.receipt
                )
            }
            let laterRevision = try h.syntheticPair(
                command: command,
                effects: provenanceEffect,
                mutationID: provenanceID,
                writerID: provenanceWriterID,
                workspaceRevision: 50
            )
            assertHistoryCorrupt {
                _ = try CheckRunnerBeginCommittedEvidenceV1(
                    envelope: localProvenance.envelope,
                    receipt: laterRevision.receipt
                )
            }
            XCTAssertEqual(
                try h.journal.checkRunnerBeginEvidence(
                    workspaceID: zone.envelope.workspaceID, mutationID: zone.envelope.mutationID
                )?.receipt,
                zone.receipt
            )
        }
    }

    private func assertHistoryCorrupt(
        file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void
    ) { assertFailure(.receiptHistoryCorrupt, file: file, line: line, body) }

    private func assertFailure(
        _ expected: WorkspaceMutationFailureV1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected, file: file, line: line)
        }
    }
}

@MainActor
private func withHarness<Value>(
    _ label: String, _ body: (BeginHistoryHarness) throws -> Value
) throws -> Value {
    var root: URL?
    do {
        let value = try autoreleasepool { () throws -> Value in
            let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
                "V23-begin-history-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
            root = fixtureRoot
            let harness = try BeginHistoryHarness(root: fixtureRoot)
            do {
                let value = try body(harness)
                try harness.closeLeases()
                return value
            } catch {
                try? harness.closeLeases()
                throw error
            }
        }
        if let root { try FileManager.default.removeItem(at: root) }
        return value
    } catch {
        if let root { try? FileManager.default.removeItem(at: root) }
        throw error
    }
}

@MainActor
private final class BeginHistoryHarness {
    struct Pair {
        let record: MutationHistoryReceiptRecordV1
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1
    }
    struct SyntheticPair { let envelope: MutationEnvelopeV1; let receipt: MutationReceiptV1 }
    struct ReceiptAnchor: Equatable {
        let mutationID: UUID; let workspaceMutationKey: String; let receiptIdentity: String
        let workspaceID: UUID; let replicaID: UUID; let localSequence: Int64; let commandKind: String
        let envelopeData: Data; let envelopeSHA256: String; let receiptData: Data; let receiptSHA256: String
        let reversalBasisData: Data?; let reversalBasisSHA256: String?; let semanticReversalData: Data?
    }
    struct QuarantineAnchor: Equatable {
        let workspaceID: UUID; let mutationID: UUID; let workspaceMutationKey: String; let identityDomain: String
        let acceptedIdentitySHA256: String; let conflictingIdentitySHA256: String; let detectedAt: Date
    }
    struct StateAnchor: Equatable {
        let workspaceID: UUID; let generationID: UUID; let activeReplicaID: UUID
        let workspaceRevision: Int64; let lastLocalSequence: Int64; let mutableSemanticSHA256: String?
    }
    struct RevisionAnchor: Equatable {
        let stableIdentity: String; let kind: String; let entityID: UUID
        let revision: Int64; let externalProjectionSHA256: String?
    }
    struct SiteAnchor: Equatable {
        let id: UUID; let schemaVersion: Int; let label: String; let address: String?
        let timeZoneID: String?; let createdAt: Date; let updatedAt: Date
    }
    struct AssetAnchor: Equatable {
        let id: UUID; let schemaVersion: Int; let siteID: UUID; let packID: String
        let packSchemaVersion: Int; let packContentVersion: Int; let label: String
        let createdAt: Date; let updatedAt: Date
    }
    struct WorkflowAnchor: Equatable {
        let id: UUID; let schemaVersion: Int; let assetID: UUID; let recordRevisionRootID: UUID
        let revisionKind: String; let stage: String; let state: String; let draftStepKey: String?
        let startedAt: Date; let observedAtUTC: Date?; let timeZoneID: String?
        let afterDarkAccepted: Bool?; let safePositionAccepted: Bool?
        let packID: String; let packSchemaVersion: Int; let packContentVersion: Int
        let issueID: UUID?
        let parentRecordID: UUID?
        let utcOffsetMinutes: Int?
        let localDate: String?
        let localTime: String?
        let afterDarkAcknowledgementKey: String?
        let afterDarkAcknowledgementCopy: String?
        let afterDarkAcknowledgementVersion: String?
        let safePositionAcknowledgementKey: String?
        let safePositionAcknowledgementCopy: String?
        let safePositionAcknowledgementVersion: String?
        let pdfTemplateID: String
        let pdfTemplateVersion: Int
        let finalizationMutationID: UUID?
    }
    struct Snapshot: Equatable {
        let receipts: [ReceiptAnchor]; let quarantines: [QuarantineAnchor]
        let states: [StateAnchor]; let revisions: [RevisionAnchor]
        let sites: [SiteAnchor]; let assets: [AssetAnchor]; let workflows: [WorkflowAnchor]
        let hasChanges: Bool
    }

    let root: URL
    let factory: StoreGenerationFactory
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let profile: WorkspacePackageLifecycleProfileV1
    let siteID = UUID(), assetID = UUID()
    let observedAt = Date(timeIntervalSince1970: 1_789_000_000)
    let selectedMutationID: MutationIDV1
    let journal: MutationJournalStoreV1
    private let journalLease: GenerationLeaseHandleV1
    private var journalLeaseClosed = false, coordinatorLeaseClosed = false
    var context: ModelContext { session.modelContext }
    var writer: WorkspaceWriterV1 { coordinator.workspaceWriter }
    var workspaceID: WorkspaceID { session.workspaceID }

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: UUID()), replicaID: ReplicaID(rawValue: UUID())
        )
        let localFactory = StoreGenerationFactory(
            applicationSupportURL: root,
            pointerEnrichmentIdentity: identity
        )
        factory = localFactory
        let localSession = try localFactory.openOrBootstrapCurrent()
        session = localSession
        let registry = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let localCoordinator = try StoreSessionCoordinator(
            validatingSession: localSession,
            lifecycleProfileRegistry: registry
        )
        coordinator = localCoordinator
        let localProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: .illuminatedSignV1
        )
        profile = localProfile
        selectedMutationID = try MutationIDV1(rawValue: UUID())
        guard let epoch = localSession.generationEpoch else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        let leases = try localFactory.makeGenerationLeaseRegistry()
        let localJournalLease = try leases.acquireHandle(epoch: epoch, role: .writer)
        journalLease = localJournalLease
        journal = try MutationJournalStoreV1(
            modelContext: localSession.modelContext,
            identity: localSession.workspaceIdentity,
            generationID: localSession.generationID,
            allowStateBootstrap: false,
            staleWriterFence: localFactory.makeWriterFence(
                expectedGenerationEpoch: epoch,
                writerLeaseToken: localJournalLease.token,
                registry: leases
            )
        )
        let first = try MutationIDV1(rawValue: UUID())
        _ = try localCoordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID,
            newSite: .init(id: siteID, label: "North Campus", address: "10 Main", timeZoneID: nil),
            assetID: assetID,
            assetLabel: "Monument Sign",
            packID: localProfile.package.packID,
            packSchemaVersion: localProfile.package.schemaVersion,
            packContentVersion: localProfile.package.contentVersion,
            createdAt: observedAt.addingTimeInterval(-10),
            initialPlacementMutationID: first,
            initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        )), mutationID: first)
    }

    func beginCheck() throws -> WorkflowRecord {
        try CheckRunnerCoordinator(
            modelContext: context,
            packageLifecycleDependencies: coordinator.packageLifecycleDependencies(
                profileRegistry: coordinator.lifecycleProfileRegistry
            ),
            packageLifecycleProfile: profile
        ).beginCheck(
            assetID: assetID, timeZoneID: "America/New_York", isTimeZoneConfirmed: true,
            afterDarkAccepted: true, safePositionAccepted: true, observedAt: observedAt
        )
    }
    func commitTimeZone(_ id: MutationIDV1, _ zone: String) throws {
        _ = try writer.execute(.updateSiteTimeZone(.init(
            siteID: siteID, timeZoneID: zone, confirmedAt: observedAt
        )), mutationID: id)
    }
    func records() throws -> [MutationHistoryReceiptRecordV1] {
        try writer.sourceMutationHistorySnapshot().receipts
    }
    func pairs() throws -> [Pair] {
        try records().map { Pair(
            record: $0,
            envelope: try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData),
            receipt: try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        ) }
    }
    func onlyPair(_ kind: WorkspaceCommandKindV1) throws -> Pair {
        let matches = try pairs().filter { $0.envelope.commandKind == kind }
        guard matches.count == 1, let value = matches.first else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return value
    }
    func pair(_ workspaceID: WorkspaceID, _ mutationID: MutationIDV1) throws -> Pair {
        let matches = try pairs().filter {
            $0.envelope.workspaceID == workspaceID && $0.envelope.mutationID == mutationID
        }
        guard matches.count == 1, let value = matches.first else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return value
    }
    func syntheticPair(
        command: SiteTimeZoneMutationV1,
        effects: [MutationPostImageV1],
        mutationID: MutationIDV1? = nil,
        writerID: UUID = UUID(),
        workspaceRevision: UInt64 = 40,
        sourceKind: MutationSourceKindV1 = .localUser
    ) throws -> SyntheticPair {
        let identities = try effects.map { try $0.identity }
        let resolvedMutationID: MutationIDV1
        if let mutationID {
            resolvedMutationID = mutationID
        } else {
            resolvedMutationID = try MutationIDV1(rawValue: UUID())
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: session.generationID, writerInstanceID: writerID,
            workspaceRevision: workspaceRevision,
            entityRevisions: identities.map { .init(identity: $0, revision: 0) }
        )
        let envelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: resolvedMutationID, expectedRevision: expected,
                command: .updateSiteTimeZone(command)
            ),
            identity: session.workspaceIdentity,
            sourceKind: sourceKind
        )
        let resulting = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: session.generationID, writerInstanceID: writerID,
            workspaceRevision: workspaceRevision + 1,
            entityRevisions: identities.map { .init(identity: $0, revision: 1) }
        ))
        return SyntheticPair(envelope: envelope, receipt: try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: workspaceID, replicaID: session.replicaID, localSequence: 99
            ), envelope: envelope, resultingRevision: resulting,
            postImages: effects, committedAt: observedAt
        ))
    }

    func snapshot() throws -> Snapshot {
        Snapshot(
            receipts: try context.fetch(FetchDescriptor<MutationReceiptRow>()).map { .init(
                mutationID: $0.mutationID, workspaceMutationKey: $0.workspaceMutationKey,
                receiptIdentity: $0.receiptIdentity, workspaceID: $0.workspaceID, replicaID: $0.replicaID,
                localSequence: $0.localSequence, commandKind: $0.commandKind,
                envelopeData: $0.envelopeData, envelopeSHA256: $0.envelopeSHA256,
                receiptData: $0.receiptData, receiptSHA256: $0.receiptSHA256,
                reversalBasisData: $0.reversalBasisData, reversalBasisSHA256: $0.reversalBasisSHA256,
                semanticReversalData: $0.semanticReversalData
            ) }.sorted { $0.workspaceMutationKey < $1.workspaceMutationKey },
            quarantines: try context.fetch(FetchDescriptor<MutationQuarantineRow>()).map { .init(
                workspaceID: $0.workspaceID, mutationID: $0.mutationID,
                workspaceMutationKey: $0.workspaceMutationKey, identityDomain: $0.identityDomain,
                acceptedIdentitySHA256: $0.acceptedIdentitySHA256,
                conflictingIdentitySHA256: $0.conflictingIdentitySHA256, detectedAt: $0.detectedAt
            ) }.sorted { $0.workspaceMutationKey < $1.workspaceMutationKey },
            states: try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map { .init(
                workspaceID: $0.workspaceID, generationID: $0.generationID, activeReplicaID: $0.activeReplicaID,
                workspaceRevision: $0.workspaceRevision, lastLocalSequence: $0.lastLocalSequence,
                mutableSemanticSHA256: $0.mutableSemanticSHA256
            ) }.sorted { $0.workspaceID.uuidString < $1.workspaceID.uuidString },
            revisions: try context.fetch(FetchDescriptor<EntityMutationRevisionRow>()).map { .init(
                stableIdentity: $0.stableIdentity, kind: $0.kind, entityID: $0.entityID,
                revision: $0.revision, externalProjectionSHA256: $0.externalProjectionSHA256
            ) }.sorted { $0.stableIdentity < $1.stableIdentity },
            sites: try context.fetch(FetchDescriptor<Site>()).map { .init(
                id: $0.id, schemaVersion: $0.schemaVersion, label: $0.label, address: $0.address,
                timeZoneID: $0.timeZoneID, createdAt: $0.createdAt, updatedAt: $0.updatedAt
            ) }.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: try context.fetch(FetchDescriptor<Asset>()).map { .init(
                id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID, packID: $0.packID,
                packSchemaVersion: $0.packSchemaVersion, packContentVersion: $0.packContentVersion,
                label: $0.label, createdAt: $0.createdAt, updatedAt: $0.updatedAt
            ) }.sorted { $0.id.uuidString < $1.id.uuidString },
            workflows: try context.fetch(FetchDescriptor<WorkflowRecord>()).map { .init(
                id: $0.id, schemaVersion: $0.schemaVersion, assetID: $0.assetID,
                recordRevisionRootID: $0.recordRevisionRootID, revisionKind: $0.revisionKind,
                stage: $0.stage, state: $0.state, draftStepKey: $0.draftStepKey,
                startedAt: $0.startedAt, observedAtUTC: $0.observedAtUTC, timeZoneID: $0.timeZoneID,
                afterDarkAccepted: $0.afterDarkAcknowledgementAccepted,
                safePositionAccepted: $0.safePositionAcknowledgementAccepted,
                packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                packContentVersion: $0.packContentVersion,
                issueID: $0.issueID,
                parentRecordID: $0.parentRecordID,
                utcOffsetMinutes: $0.utcOffsetMinutes,
                localDate: $0.localDate,
                localTime: $0.localTime,
                afterDarkAcknowledgementKey: $0.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: $0.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: $0.afterDarkAcknowledgementVersion,
                safePositionAcknowledgementKey: $0.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy: $0.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion: $0.safePositionAcknowledgementVersion,
                pdfTemplateID: $0.pdfTemplateID,
                pdfTemplateVersion: $0.pdfTemplateVersion,
                finalizationMutationID: $0.finalizationMutationID
            ) }.sorted { $0.id.uuidString < $1.id.uuidString },
            hasChanges: context.hasChanges
        )
    }
    func retireJournalLease() throws {
        guard !journalLeaseClosed else { return }
        try journalLease.close(); journalLeaseClosed = true
    }
    func closeLeases() throws {
        if !coordinatorLeaseClosed {
            do { try coordinator.invalidateAndReleaseWriter(); coordinatorLeaseClosed = true }
            catch { if !journalLeaseClosed { try? journalLease.close() }; throw error }
        }
        if !journalLeaseClosed { try journalLease.close(); journalLeaseClosed = true }
    }
}
