import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23RestoreReviewAuthorityTests: XCTestCase {
    func testWrongContextIdentityAndGenerationHaveNoEffects() throws {
        try assertDenied([.wrongContext, .wrongIdentity, .wrongGeneration], failure: .wrongGeneration)
    }

    func testChangedBindingDeniesAdmissionAndCommitWithoutEffects() throws {
        try assertDenied([.changedBindingBeforeAdmission, .changedBindingBeforeCommit], failure: .wrongGeneration)
    }

    func testChangedCommandAndEnvelopeAreDeniedBeforeEffects() throws {
        try assertDenied([.changedCommandAdmission, .changedEnvelopeAdmission], failure: .invalidCommand,
                         expectedAdmissionAttempts: 1)
    }

    func testChangedCommandOrEnvelopeCannotCommitAfterExactAdmission() throws {
        try assertDenied([.changedCommandCommit, .changedEnvelopeCommit], failure: .invalidCommand, expectedAdmissionAttempts: 1)
    }

    func testGenericWriterCommandReachesAdmissionAndIsDeniedWithoutEffects() throws {
        try assertDenied([.genericWriter], failure: .invalidCommand, expectedAdmissionAttempts: 1)
    }

    func testRecoveryBodyNeverRunsAndHasNoEffects() throws {
        try assertDenied([.recovery], failure: .wrongGeneration, expectedAdmissionAttempts: 0)
    }

    func testSynchronousRevocationDeniesReadAdmissionAndPreviouslyAdmittedCommit() throws {
        try assertDenied([.revokedRead, .revokedAdmission, .revokedCommit], failure: .wrongGeneration)
    }

    private func assertDenied(_ attacks: [StoreRestoreReviewAuthorityProbeV1.Attack],
                              failure: WorkspaceMutationFailureV1,
                              expectedAdmissionAttempts: Int? = nil,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let template = try XCTUnwrap(source.checkpoints.first, file: file, line: line)
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-authority-denials-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: source.workspaceID, replicaID: ReplicaID())
        let factory = StoreGenerationFactory(applicationSupportURL: support, pointerEnrichmentIdentity: identity)
        let session = try factory.openOrBootstrapCurrent()
        let other = try factory.openOrBootstrapCurrent()
        // A genuine incumbent receipt makes accidental history erasure observable.
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let incumbent = try genericCommand(label: "Retained incumbent")
        guard case let .createFirstSign(value) = incumbent else { return XCTFail("Wrong incumbent fixture") }
        let incumbentMutationID = try XCTUnwrap(value.initialPlacementMutationID)
        _ = try coordinator.workspaceWriter.execute(incumbent, mutationID: incumbentMutationID)
        try coordinator.invalidateAndReleaseWriter()
        let checkpoint = try self.checkpoint(template, workspaceID: identity.workspaceID,
                                        mutationID: MutationIDV1(rawValue: UUID()), dateOffset: 0)
        let changed = try self.checkpoint(template, workspaceID: identity.workspaceID,
                                         mutationID: MutationIDV1(rawValue: UUID()), dateOffset: 1)
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext, identity: identity,
            generationID: session.generationID, allowStateBootstrap: false)
        let beforeHistory = try journal.exportSnapshot()
        let beforeCheckpoints = try session.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
            .map { try $0.value() }
        let beforeSites = try session.modelContext.fetchCount(FetchDescriptor<Site>())
        let beforeAssets = try session.modelContext.fetchCount(FetchDescriptor<Asset>())
        XCTAssertFalse(beforeHistory.receipts.isEmpty, file: file, line: line)
        for attack in attacks {
            let result = try StoreRestoreReviewAuthorityProbeV1.run(attack, session: session,
                otherContext: other.modelContext, checkpoint: checkpoint, changedCheckpoint: changed,
                genericCommand: genericCommand(label: "Must never be written"))
            XCTAssertEqual(result.failure, failure, "\(attack)", file: file, line: line)
            XCTAssertFalse(result.recoveryEntered, "\(attack)", file: file, line: line)
            XCTAssertFalse(result.hadChangesBeforeCleanup, "\(attack)", file: file, line: line)
            if let expectedAdmissionAttempts {
                XCTAssertEqual(result.admissionAttempts, expectedAdmissionAttempts, "\(attack)", file: file, line: line)
            }
            XCTAssertFalse(session.modelContext.hasChanges, "\(attack)", file: file, line: line)
            XCTAssertEqual(try journal.exportSnapshot(), beforeHistory, "\(attack)", file: file, line: line)
            XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() },
                           beforeCheckpoints, "\(attack)", file: file, line: line)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Site>()), beforeSites, file: file, line: line)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Asset>()), beforeAssets, file: file, line: line)
        }
        let reopened = try factory.openOrBootstrapCurrent()
        let reopenedJournal = try MutationJournalStoreV1(modelContext: reopened.modelContext,
            identity: reopened.workspaceIdentity, generationID: reopened.generationID, allowStateBootstrap: false)
        XCTAssertEqual(try reopenedJournal.exportSnapshot(), beforeHistory, file: file, line: line)
        XCTAssertEqual(try reopened.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() },
                       beforeCheckpoints, file: file, line: line)
    }

    private func checkpoint(_ template: FieldDraftCheckpointV1, workspaceID: WorkspaceID,
                            mutationID: MutationIDV1, dateOffset: TimeInterval) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(draftID: template.draftID, workspaceID: workspaceID,
            scope: template.scope, purpose: template.purpose, codec: template.codec,
            baseCanonicalRevision: template.baseCanonicalRevision, draftRevision: 1,
            payloadData: template.payloadData, stageIDs: [], resumeAnchor: template.resumeAnchor,
            state: .active, updatedAt: template.updatedAt.addingTimeInterval(dateOffset), mutationID: mutationID)
    }

    private func genericCommand(label: String) throws -> WorkspaceCommandV1 {
        let pack = SignPack.illuminatedSignV1
        let siteID = UUID(), mutationID = try MutationIDV1(rawValue: UUID())
        return try .createFirstSign(.init(siteID: siteID,
            newSite: .init(id: siteID, label: label, address: nil, timeZoneID: "America/New_York"),
            assetID: UUID(), assetLabel: label, packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: RepetitiveCaptureSourcePackageFixture.date,
            initialPlacementMutationID: mutationID, initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())))
    }
}
