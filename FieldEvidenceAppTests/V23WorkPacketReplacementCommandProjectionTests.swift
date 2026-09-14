import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23WorkPacketReplacementCommandProjectionTests: XCTestCase {
    func testReplacementMutationNamespacesAreDeterministicAndDisjoint() throws {
        let identity = try WorkPacketReplacementFixture.identity()
        let source = try MutationIDV1(rawValue: WorkPacketReplacementFixture.id(30))
        let mapped = try WorkPacketReplacementFixture.mappedIDs(source, identity: identity)
        XCTAssertEqual(mapped, try WorkPacketReplacementFixture.mappedIDs(source, identity: identity))
        XCTAssertEqual(Set(mapped).count, 4)
        XCTAssertFalse(mapped.contains(source))
        XCTAssertFalse(mapped.contains(try identity.destinationPartsStockMutationID(for: source)))
        XCTAssertFalse(mapped.contains(try identity.destinationWorkResourceMutationID(for: source)))
    }

    func testReplacementMutationNamespacesBindSourceOwnerAndTargetGeneration() throws {
        let source = try MutationIDV1(rawValue: WorkPacketReplacementFixture.id(30))
        let baseline = try WorkPacketReplacementFixture.mappedIDs(
            source, identity: WorkPacketReplacementFixture.identity()
        )
        let otherSource = try WorkPacketReplacementFixture.mappedIDs(
            source, identity: WorkPacketReplacementFixture.identity(sourceWorkspace: 11)
        )
        let otherGeneration = try WorkPacketReplacementFixture.mappedIDs(
            source, identity: WorkPacketReplacementFixture.identity(targetGeneration: 12)
        )
        let otherTarget = try WorkPacketReplacementFixture.mappedIDs(
            source, identity: WorkPacketReplacementFixture.identity(targetWorkspace: 13)
        )
        XCTAssertEqual(Set(baseline + otherSource + otherGeneration + otherTarget).count, 16)
        for mode in [BackupRestoreMode.emptyInstall, .clone, .fork] {
            let identity = try WorkPacketReplacementFixture.identity(mode: mode)
            XCTAssertThrowsError(try identity.destinationWorkPacketMutationID(for: source))
            XCTAssertThrowsError(try identity.destinationSurveySessionMutationID(for: source))
            XCTAssertThrowsError(try identity.destinationScheduleMutationID(for: source))
            XCTAssertThrowsError(try identity.destinationFieldDraftMutationID(for: source))
        }
    }

    func testProjectsAllSevenPayloadsFromAuthenticatedHistoryWithoutRewritingContent() throws {
        let corpus = try WorkPacketReplacementFixture.corpus()
        let identity = try WorkPacketReplacementFixture.identity(
            sourceWorkspaceID: corpus.fixture.workspaceID.rawValue
        )
        let projection = try WorkPacketReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        )

        XCTAssertEqual(projection.source, corpus.source)
        XCTAssertEqual(projection.source.history, corpus.history)
        XCTAssertEqual(projection.commands.map(\.source), corpus.source.entries)
        XCTAssertEqual(projection.commands.map(\.source.record), corpus.orderedRecords)
        XCTAssertEqual(projection.commands.map { $0.mutation.postImage.caseName }, [
            "appendManifest", "appendClaim", "supersedeClaim", "appendClaim",
            "appendLease", "supersedeLease", "recordRelease", "recordRelease",
            "recordHandoff", "recordRelease", "recordRelease", "appendManifest",
        ])
        XCTAssertEqual(Set(projection.commands.map { $0.mutation.postImage.caseName }), Set([
            "appendManifest", "appendClaim", "supersedeClaim", "appendLease",
            "supersedeLease", "recordRelease", "recordHandoff",
        ]))

        let targetWorkspaceID = WorkspaceID(rawValue: identity.targetPointer.workspaceID)
        for (sourceMutation, command) in zip(corpus.mutations, projection.commands) {
            XCTAssertEqual(command.source.envelope.command, .applyWorkPacket(sourceMutation))
            XCTAssertEqual(command.mutation.workspaceID, targetWorkspaceID)
            XCTAssertEqual(command.mutation.expectedRevision, sourceMutation.expectedRevision)
            XCTAssertEqual(
                command.mutation.mutationID,
                try identity.destinationWorkPacketMutationID(for: sourceMutation.mutationID)
            )
            XCTAssertEqual(command.postImage, try command.mutation.postImage.mutationPostImage)
            XCTAssertNotEqual(command.mutation.mutationID, sourceMutation.mutationID)
            try assertHistoricalContentRebound(
                sourceMutation.postImage, to: command.mutation.postImage,
                workspaceID: targetWorkspaceID
            )
        }

        let sourceManifests = corpus.mutations.compactMap(\.appendedManifest)
        let targetManifests = projection.commands.compactMap { $0.mutation.appendedManifest }
        XCTAssertEqual(sourceManifests.count, 2)
        XCTAssertEqual(targetManifests.count, 2)
        XCTAssertEqual(targetManifests.map(\.manifestID), sourceManifests.map(\.manifestID))
        XCTAssertEqual(targetManifests.map(\.packetVersion), [1, 2])
        XCTAssertEqual(targetManifests.map(\.items), sourceManifests.map(\.items))
        XCTAssertEqual(targetManifests.map(\.packageReleases), sourceManifests.map(\.packageReleases))
        XCTAssertEqual(targetManifests.map(\.creationBasis), sourceManifests.map(\.creationBasis))
        XCTAssertEqual(targetManifests.map(\.createdAt), sourceManifests.map(\.createdAt))
        XCTAssertEqual(Set(targetManifests.map(\.workspaceID)), [targetWorkspaceID])

        let sourceLinks = corpus.mutations.flatMap(\.resultLinks)
        let targetLinks = projection.commands.flatMap { $0.mutation.resultLinks }
        XCTAssertEqual(targetLinks, sourceLinks)
        XCTAssertEqual(Set(targetLinks), Set([
            corpus.fixture.result, corpus.fixture.alternateResult,
            corpus.fixture.staleResult, corpus.fixture.divergentResult,
        ]))
        XCTAssertTrue(zip(sourceLinks, targetLinks).allSatisfy {
            $0.resultID == $1.resultID
                && $0.resultMutationID == $1.resultMutationID
                && $0.itemExpectedRevision == $1.itemExpectedRevision
                && $0.resultRevision == $1.resultRevision
                && $0.resultSHA256 == $1.resultSHA256
                && $0.evidence == $1.evidence
        })
    }

    func testHistoricalManifestLookupUsesExactOlderReferenceDespiteNewerSnapshotFrontier() throws {
        let corpus = try WorkPacketReplacementFixture.corpus()
        let identity = try WorkPacketReplacementFixture.identity(
            sourceWorkspaceID: corpus.fixture.workspaceID.rawValue
        )
        let projection = try WorkPacketReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        )
        let olderReference = try WorkPacketManifestReferenceV1(corpus.fixture.manifest)
        let newerReference = try WorkPacketManifestReferenceV1(corpus.secondManifest)
        let targetOlder = try projection.targetManifest(for: olderReference)
        let targetNewer = try projection.targetManifest(for: newerReference)

        XCTAssertEqual(targetOlder.manifestID, corpus.fixture.manifest.manifestID)
        XCTAssertEqual(targetOlder.packetVersion, corpus.fixture.manifest.packetVersion)
        XCTAssertEqual(targetOlder.items, corpus.fixture.manifest.items)
        XCTAssertEqual(targetNewer.manifestID, corpus.secondManifest.manifestID)
        XCTAssertEqual(targetNewer.packetVersion, corpus.secondManifest.packetVersion)
        XCTAssertNotEqual(targetOlder.manifestID, targetNewer.manifestID)
        XCTAssertNotEqual(targetOlder.manifestSHA256, targetNewer.manifestSHA256)
        XCTAssertEqual(targetOlder.workspaceID.rawValue, identity.targetPointer.workspaceID)
        let olderIdentity = try corpus.mutations[0].postImage.mutationPostImage.identity
        let snapshotFrontier = try XCTUnwrap(corpus.history.entityRevisions.first {
            $0.identity == olderIdentity
        })
        XCTAssertGreaterThan(snapshotFrontier.revision, corpus.mutations[0].postImage.revision)
        XCTAssertEqual(
            projection.commands[1].mutation.appendedClaim?.manifest.manifestSHA256,
            targetOlder.manifestSHA256
        )
        XCTAssertNotEqual(
            projection.commands[1].mutation.appendedClaim?.manifest.manifestSHA256,
            targetNewer.manifestSHA256
        )
        let unrecordedSameIdentityTip = try WorkPacketManifestReferenceV1(
            corpus.fixture.alternateManifest
        )
        XCTAssertThrowsError(try projection.targetManifest(for: unrecordedSameIdentityTip)) {
            XCTAssertEqual(
                $0 as? WorkPacketReplacementCommandProjectionFailureV1,
                .missingDependency
            )
        }
    }

    func testProjectionMapsOnlyRealDependenciesAndRetainsAuthenticatedReceiptOrder() throws {
        let corpus = try WorkPacketReplacementFixture.corpus(storeRecordsInReverse: true)
        let identity = try WorkPacketReplacementFixture.identity(
            sourceWorkspaceID: corpus.fixture.workspaceID.rawValue
        )
        let projection = try WorkPacketReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        )
        let forwardCorpus = try WorkPacketReplacementFixture.corpus(storeRecordsInReverse: false)
        let forwardProjection = try WorkPacketReplacementCommandProjectionV1.project(
            source: forwardCorpus.source, identity: identity
        )
        let sourceIDs = corpus.mutations.map(\.mutationID)
        XCTAssertEqual(projection.commands.map { $0.source.envelope.mutationID }, sourceIDs)
        XCTAssertEqual(projection.source.history.receipts, Array(corpus.orderedRecords.reversed()))
        XCTAssertEqual(forwardProjection.source.history.receipts, corpus.orderedRecords)
        XCTAssertNotEqual(projection.source.history.receipts,
                          forwardProjection.source.history.receipts)
        XCTAssertEqual(projection.commands, forwardProjection.commands)
        XCTAssertEqual(projection.manifests, forwardProjection.manifests)

        let expected: [[MutationIDV1]] = [
            [], [sourceIDs[0]], [sourceIDs[0], sourceIDs[1]], [sourceIDs[0]],
            [sourceIDs[1]], [sourceIDs[1], sourceIDs[4]],
            [sourceIDs[0], sourceIDs[1], sourceIDs[4]],
            [sourceIDs[0], sourceIDs[1], sourceIDs[4]], [sourceIDs[7]],
            [sourceIDs[0], sourceIDs[1], sourceIDs[4]],
            [sourceIDs[0], sourceIDs[1], sourceIDs[4]], [],
        ].map(WorkPacketReplacementFixture.sorted)
        for (index, command) in projection.commands.enumerated() {
            XCTAssertEqual(command.sourceDependencyMutationIDs, expected[index], "source dependency \(index)")
            XCTAssertEqual(
                command.targetDependencyMutationIDs,
                try expected[index].map { try identity.destinationWorkPacketMutationID(for: $0) }
                    .sorted(by: WorkPacketReplacementFixture.mutationOrder),
                "target dependency \(index)"
            )
            XCTAssertEqual(command.sourceDependencyMutationIDs.count,
                           command.targetDependencyMutationIDs.count)
        }
    }

    func testProjectedCommandsProduceValidTypedTargetReceiptsAndEquivalentConflictEvidence() throws {
        let corpus = try WorkPacketReplacementFixture.corpus()
        let identity = try WorkPacketReplacementFixture.identity(
            sourceWorkspaceID: corpus.fixture.workspaceID.rawValue
        )
        let projection = try WorkPacketReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        )
        for (index, command) in projection.commands.enumerated() {
            let receipt = try WorkPacketReplacementFixture.record(
                mutation: command.mutation,
                generationID: identity.targetPointer.generationID,
                workspaceRevision: UInt64(index),
                localSequence: UInt64(index + 1),
                replicaID: ReplicaID(rawValue: WorkPacketReplacementFixture.id(7_001))
            ).receipt
            XCTAssertNoThrow(try WorkPacketMutationReceiptV1(
                mutation: command.mutation, mutationReceipt: receipt
            ))
        }

        let sourceGraph = try WorkPacketReplacementFixture.graph(
            mutations: corpus.mutations, manifest: corpus.fixture.manifest
        )
        let targetGraph = try WorkPacketReplacementFixture.graph(
            mutations: projection.commands.map(\.mutation),
            manifest: try projection.targetManifest(for: corpus.fixture.manifestReference)
        )
        XCTAssertEqual(
            sourceGraph.items.map { Set($0.preservedResults) },
            targetGraph.items.map { Set($0.preservedResults) }
        )
        XCTAssertEqual(
            sourceGraph.items.map { Set($0.exceptions.map(\.kind)) },
            targetGraph.items.map { Set($0.exceptions.map(\.kind)) }
        )
    }

    func testMissingManifestClaimLeaseAndReleaseDependenciesFailClosed() throws {
        let baseline = try WorkPacketReplacementFixture.mutations().mutations
        let removals = [
            [0],       // claim cannot use a missing historical manifest
            [1],       // claim successor cannot use a missing exact predecessor
            [4],       // lease successor cannot use a missing exact predecessor
            [1, 2, 3], // lease cannot use a missing historical claim
            [4, 5],    // releases cannot use a missing historical lease
            [7],       // handoff cannot use a missing historical release
        ]
        for removed in removals {
            let retained = baseline.enumerated().compactMap {
                removed.contains($0.offset) ? nil : $0.element
            }
            let corpus = try WorkPacketReplacementFixture.corpus(mutations: retained)
            let identity = try WorkPacketReplacementFixture.identity(
                sourceWorkspaceID: corpus.fixture.workspaceID.rawValue
            )
            XCTAssertThrowsError(try WorkPacketReplacementCommandProjectionV1.project(
                source: corpus.source, identity: identity
            )) { error in
                XCTAssertEqual(
                    error as? WorkPacketReplacementCommandProjectionFailureV1,
                    .missingDependency
                )
            }
        }
    }

    func testDuplicateHistoricalIdentityAndMappedMutationCollisionFailClosed() throws {
        let values = try WorkPacketReplacementFixture.mutations()
        let duplicateManifest = try WorkPacketMutationV1(
            workspaceID: values.fixture.workspaceID,
            expectedRevision: 0,
            mutationID: values.fixture.alternateManifest.mutationID,
            postImage: .appendManifest(values.fixture.alternateManifest)
        )
        let duplicateCorpus = try WorkPacketReplacementFixture.corpus(
            mutations: [values.mutations[0], duplicateManifest]
        )
        let identity = try WorkPacketReplacementFixture.identity(
            sourceWorkspaceID: values.fixture.workspaceID.rawValue
        )
        XCTAssertThrowsError(try WorkPacketReplacementCommandProjectionV1.project(
            source: duplicateCorpus.source, identity: identity
        )) { error in
            XCTAssertEqual(error as? WorkPacketReplacementCommandProjectionFailureV1, .collision)
        }

        let mappedID = try identity.destinationWorkPacketMutationID(
            for: values.mutations[0].mutationID
        )
        let collisionCorpus = try WorkPacketReplacementFixture.corpus(
            mutations: values.mutations,
            foreignMutationID: mappedID
        )
        XCTAssertThrowsError(try WorkPacketReplacementCommandProjectionV1.project(
            source: collisionCorpus.source, identity: identity
        )) { error in
            XCTAssertEqual(error as? WorkPacketReplacementCommandProjectionFailureV1, .collision)
        }
    }

    func testProjectionRejectsDifferentSourceOwnerAndNonReplacementIdentity() throws {
        let corpus = try WorkPacketReplacementFixture.corpus()
        let wrongOwner = try WorkPacketReplacementFixture.identity(sourceWorkspace: 91)
        XCTAssertThrowsError(try WorkPacketReplacementCommandProjectionV1.project(
            source: corpus.source, identity: wrongOwner
        )) { error in
            XCTAssertEqual(error as? WorkPacketReplacementCommandProjectionFailureV1, .invalidIdentity)
        }
        for mode in [BackupRestoreMode.emptyInstall, .clone, .fork] {
            let identity = try WorkPacketReplacementFixture.identity(
                sourceWorkspaceID: corpus.fixture.workspaceID.rawValue,
                mode: mode
            )
            XCTAssertThrowsError(try WorkPacketReplacementCommandProjectionV1.project(
                source: corpus.source, identity: identity
            )) { error in
                XCTAssertEqual(error as? WorkPacketReplacementCommandProjectionFailureV1, .invalidIdentity)
            }
        }
    }

    private func assertHistoricalContentRebound(
        _ source: WorkPacketMutationPayloadV1,
        to target: WorkPacketMutationPayloadV1,
        workspaceID: WorkspaceID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        switch (source, target) {
        case let (.appendManifest(original), .appendManifest(rebound)):
            XCTAssertEqual(rebound.workspaceID, workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.manifestID, original.manifestID, file: file, line: line)
            XCTAssertEqual(rebound.packetID, original.packetID, file: file, line: line)
            XCTAssertEqual(rebound.packetVersion, original.packetVersion, file: file, line: line)
            XCTAssertEqual(rebound.items, original.items, file: file, line: line)
            assertActorRebound(original.creator, rebound.creator,
                               workspaceID: workspaceID, file: file, line: line)
        case (.appendClaim(let original), .appendClaim(let rebound)),
             (.supersedeClaim(let original), .supersedeClaim(let rebound)):
            try assertReferencesRebound(original.item, rebound.item,
                                        workspaceID: workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.manifest.workspaceID, workspaceID, file: file, line: line)
            XCTAssertNotEqual(rebound.manifest.manifestSHA256,
                              original.manifest.manifestSHA256, file: file, line: line)
            XCTAssertEqual(rebound.claimID, original.claimID, file: file, line: line)
            XCTAssertEqual(rebound.claimSequence, original.claimSequence, file: file, line: line)
            XCTAssertEqual(rebound.claimedAt, original.claimedAt, file: file, line: line)
            XCTAssertEqual(rebound.supersedesClaimID,
                           original.supersedesClaimID, file: file, line: line)
            XCTAssertEqual(rebound.revision, original.revision, file: file, line: line)
            assertActorRebound(original.holder, rebound.holder,
                               workspaceID: workspaceID, file: file, line: line)
        case (.appendLease(let original), .appendLease(let rebound)),
             (.supersedeLease(let original), .supersedeLease(let rebound)):
            try assertReferencesRebound(original.item, rebound.item,
                                        workspaceID: workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.leaseID, original.leaseID, file: file, line: line)
            XCTAssertEqual(rebound.claimID, original.claimID, file: file, line: line)
            XCTAssertEqual(rebound.leaseSequence, original.leaseSequence, file: file, line: line)
            XCTAssertEqual(rebound.startsAt, original.startsAt, file: file, line: line)
            XCTAssertEqual(rebound.expiresAt, original.expiresAt, file: file, line: line)
            XCTAssertEqual(rebound.supersedesLeaseID,
                           original.supersedesLeaseID, file: file, line: line)
            XCTAssertEqual(rebound.revision, original.revision, file: file, line: line)
            assertActorRebound(original.holder, rebound.holder,
                               workspaceID: workspaceID, file: file, line: line)
        case let (.recordRelease(original), .recordRelease(rebound)):
            try assertReferencesRebound(original.item, rebound.item,
                                        workspaceID: workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.releaseID, original.releaseID, file: file, line: line)
            XCTAssertEqual(rebound.claimID, original.claimID, file: file, line: line)
            XCTAssertEqual(rebound.leaseID, original.leaseID, file: file, line: line)
            XCTAssertEqual(rebound.reason, original.reason, file: file, line: line)
            XCTAssertEqual(rebound.releasedAt, original.releasedAt, file: file, line: line)
            XCTAssertEqual(rebound.revision, original.revision, file: file, line: line)
            assertActorRebound(original.holder, rebound.holder,
                               workspaceID: workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.resultLinks, original.resultLinks, file: file, line: line)
        case let (.recordHandoff(original), .recordHandoff(rebound)):
            try assertReferencesRebound(original.item, rebound.item,
                                        workspaceID: workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.handoffID, original.handoffID, file: file, line: line)
            XCTAssertEqual(rebound.releaseID, original.releaseID, file: file, line: line)
            XCTAssertEqual(rebound.reason, original.reason, file: file, line: line)
            XCTAssertEqual(rebound.handedOffAt, original.handedOffAt, file: file, line: line)
            XCTAssertEqual(rebound.revision, original.revision, file: file, line: line)
            assertActorRebound(original.fromHolder, rebound.fromHolder,
                               workspaceID: workspaceID, file: file, line: line)
            assertActorRebound(original.toHolder, rebound.toHolder,
                               workspaceID: workspaceID, file: file, line: line)
            XCTAssertEqual(rebound.resultLinks, original.resultLinks, file: file, line: line)
        default:
            XCTFail("projector changed the historical payload case", file: file, line: line)
        }
    }

    private func assertReferencesRebound(
        _ source: WorkPacketItemReferenceV1,
        _ target: WorkPacketItemReferenceV1,
        workspaceID: WorkspaceID,
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertEqual(target.workspaceID, workspaceID, file: file, line: line)
        XCTAssertEqual(target.packetID, source.packetID, file: file, line: line)
        XCTAssertEqual(target.packetVersion, source.packetVersion, file: file, line: line)
        XCTAssertNotEqual(target.manifestSHA256, source.manifestSHA256, file: file, line: line)
        XCTAssertEqual(target.itemID, source.itemID, file: file, line: line)
        XCTAssertEqual(target.itemKind, source.itemKind, file: file, line: line)
        XCTAssertEqual(target.expectedRevision, source.expectedRevision, file: file, line: line)
        XCTAssertEqual(target.itemSHA256, source.itemSHA256, file: file, line: line)
        XCTAssertNoThrow(try target.validate(), file: file, line: line)
    }

    private func assertActorRebound(
        _ source: ActorSnapshotV1,
        _ target: ActorSnapshotV1,
        workspaceID: WorkspaceID,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(target.workspaceID, workspaceID, file: file, line: line)
        XCTAssertEqual(target.snapshotID, source.snapshotID, file: file, line: line)
        XCTAssertEqual(target.actor.actorReferenceID,
                       source.actor.actorReferenceID, file: file, line: line)
        XCTAssertEqual(target.actor.workspaceID, workspaceID, file: file, line: line)
        XCTAssertEqual(target.actor.partyID, source.actor.partyID, file: file, line: line)
        XCTAssertEqual(target.actor.displayName,
                       source.actor.displayName, file: file, line: line)
        XCTAssertEqual(target.responsibility,
                       source.responsibility, file: file, line: line)
        XCTAssertEqual(target.displayNameAtTime,
                       source.displayNameAtTime, file: file, line: line)
        XCTAssertEqual(target.capturedAt, source.capturedAt, file: file, line: line)
    }
}

private extension WorkPacketMutationPayloadV1 {
    var caseName: String {
        switch self {
        case .appendManifest: "appendManifest"
        case .appendClaim: "appendClaim"
        case .supersedeClaim: "supersedeClaim"
        case .appendLease: "appendLease"
        case .supersedeLease: "supersedeLease"
        case .recordRelease: "recordRelease"
        case .recordHandoff: "recordHandoff"
        }
    }
}

private extension WorkPacketMutationV1 {
    var appendedManifest: WorkPacketManifestV1? {
        guard case let .appendManifest(value) = postImage else { return nil }
        return value
    }

    var appendedClaim: WorkItemClaimV1? {
        switch postImage {
        case let .appendClaim(value), let .supersedeClaim(value): value
        default: nil
        }
    }

    var resultLinks: [WorkPacketResultLinkV1] {
        switch postImage {
        case let .recordRelease(value): value.resultLinks
        case let .recordHandoff(value): value.resultLinks
        default: []
        }
    }
}

private enum WorkPacketReplacementFixture {
    struct Values {
        let fixture: C15WorkPacketManifestTestSupportV1.Fixture
        let secondManifest: WorkPacketManifestV1
        let mutations: [WorkPacketMutationV1]
    }

    struct Corpus {
        let fixture: C15WorkPacketManifestTestSupportV1.Fixture
        let secondManifest: WorkPacketManifestV1
        let mutations: [WorkPacketMutationV1]
        let orderedRecords: [MutationHistoryReceiptRecordV1]
        let history: MutationHistorySnapshotV1
        let source: ReferenceOwnerReplacementSourceV1.Source
    }

    struct Record {
        let value: MutationHistoryReceiptRecordV1
        let receipt: MutationReceiptV1
        let image: MutationPostImageV1
    }

    static let date = Date(timeIntervalSince1970: 1_811_000_000)
    static let generationID = id(7_002)
    static let writerID = id(7_003)
    static let replicaID = ReplicaID(rawValue: id(7_004))

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c5710000-0000-4000-8000-%012x", value))!
    }

    static func identity(
        sourceWorkspace: Int = 1,
        targetWorkspace: Int = 3,
        targetGeneration: Int = 6,
        mode: BackupRestoreMode = .replaceExisting
    ) throws -> RestoreIdentityV1 {
        try identity(
            sourceWorkspaceID: id(sourceWorkspace), targetWorkspace: targetWorkspace,
            targetGeneration: targetGeneration, mode: mode
        )
    }

    static func identity(
        sourceWorkspaceID: UUID,
        targetWorkspace: Int = 3,
        targetGeneration: Int = 6,
        mode: BackupRestoreMode = .replaceExisting
    ) throws -> RestoreIdentityV1 {
        try RestoreIdentityDecisionV1.decide(.init(
            mode: mode,
            source: .init(workspaceID: sourceWorkspaceID, replicaID: id(2)),
            oldPointer: .init(generationID: id(5),
                              generationManifestSHA256: String(repeating: "a", count: 64),
                              workspaceID: id(targetWorkspace), replicaID: id(4)),
            targetGenerationID: id(targetGeneration),
            targetGenerationManifestSHA256: String(repeating: "b", count: 64),
            allocatedWorkspaceID: id(20), allocatedReplicaID: id(21)
        ))
    }

    static func mappedIDs(_ source: MutationIDV1, identity: RestoreIdentityV1) throws -> [MutationIDV1] {
        try [identity.destinationWorkPacketMutationID(for: source),
             identity.destinationSurveySessionMutationID(for: source),
             identity.destinationScheduleMutationID(for: source),
             identity.destinationFieldDraftMutationID(for: source)]
    }

    static func mutations() throws -> Values {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 157_000)
        let secondManifest = try WorkPacketManifestV1(
            manifestID: id(7_100), packetID: fixture.alternateManifest.packetID,
            packetVersion: fixture.alternateManifest.packetVersion,
            workspaceID: fixture.workspaceID, items: fixture.alternateManifest.items,
            packageReleases: fixture.alternateManifest.packageReleases,
            creationBasis: fixture.alternateManifest.creationBasis,
            creator: fixture.alternateManifest.creator,
            createdAt: fixture.alternateManifest.createdAt,
            mutationID: fixture.alternateManifest.mutationID
        )
        return Values(fixture: fixture, secondManifest: secondManifest, mutations: [
            try mutation(.appendManifest(fixture.manifest), expectedRevision: 0),
            try mutation(.appendClaim(fixture.claim), expectedRevision: 0),
            try mutation(.supersedeClaim(fixture.successorClaim),
                         expectedRevision: fixture.claim.revision),
            try mutation(.appendClaim(fixture.competingClaim), expectedRevision: 0),
            try mutation(.appendLease(fixture.lease), expectedRevision: 0),
            try mutation(.supersedeLease(fixture.successorLease),
                         expectedRevision: fixture.lease.revision),
            try mutation(.recordRelease(fixture.completedRelease), expectedRevision: 0),
            try mutation(.recordRelease(fixture.handoffRelease), expectedRevision: 0),
            try mutation(.recordHandoff(fixture.handoff), expectedRevision: 0),
            try mutation(.recordRelease(fixture.expiredRelease), expectedRevision: 0),
            try mutation(.recordRelease(fixture.divergentRelease), expectedRevision: 0),
            try mutation(.appendManifest(secondManifest), expectedRevision: 0),
        ])
    }

    static func mutation(
        _ payload: WorkPacketMutationPayloadV1,
        expectedRevision: UInt64
    ) throws -> WorkPacketMutationV1 {
        try WorkPacketMutationV1(
            workspaceID: payload.workspaceID, expectedRevision: expectedRevision,
            mutationID: payload.mutationID, postImage: payload
        )
    }

    static func corpus(
        mutations explicitMutations: [WorkPacketMutationV1]? = nil,
        storeRecordsInReverse: Bool = true,
        foreignMutationID: MutationIDV1? = nil
    ) throws -> Corpus {
        let values = try mutations()
        let mutations = explicitMutations ?? values.mutations
        var records: [Record] = []
        for (index, mutation) in mutations.enumerated() {
            records.append(try record(
                mutation: mutation, generationID: generationID,
                workspaceRevision: UInt64(index), localSequence: UInt64(index + 1),
                replicaID: replicaID
            ))
        }

        var stored: [MutationHistoryReceiptRecordV1] = storeRecordsInReverse
            ? Array(records.map(\.value).reversed()) : records.map(\.value)
        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for record in records {
            terminal[try record.image.identity] = record.image.revision
        }
        if let first = records.first {
            terminal[try first.image.identity] = first.image.revision + 9
        }
        if let foreignMutationID {
            let foreignWorkspace = WorkspaceID(rawValue: id(7_900))
            let actor = try rebound(values.fixture.creator, to: foreignWorkspace)
            let item = try WorkPacketItemV1(
                itemID: "c57-foreign", kind: .inspection, expectedRevision: 1,
                itemSHA256: String(repeating: "f", count: 64)
            )
            let manifest = try WorkPacketManifestV1(
                manifestID: id(7_901), packetID: id(7_902), packetVersion: 1,
                workspaceID: foreignWorkspace, items: [item], packageReleases: [],
                creationBasis: .explicitLocalSelection, creator: actor,
                createdAt: date, mutationID: foreignMutationID
            )
            let foreign = try record(
                mutation: try mutation(.appendManifest(manifest), expectedRevision: 0),
                generationID: id(7_903), workspaceRevision: 0, localSequence: 1,
                replicaID: ReplicaID(rawValue: id(7_904))
            )
            stored.append(foreign.value)
            terminal[try foreign.image.identity] = foreign.image.revision
        }
        let history = MutationHistorySnapshotV1(
            workspaceRevision: UInt64(records.count),
            lastLocalSequence: UInt64(records.count),
            receipts: stored, quarantines: [],
            entityRevisions: terminal.map {
                MutationHistoryEntityRevisionV1(identity: $0.key, revision: $0.value)
            }.sorted { $0.identity.stableKey < $1.identity.stableKey }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        let source = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: values.fixture.workspaceID, history: history
        )
        return Corpus(
            fixture: values.fixture, secondManifest: values.secondManifest,
            mutations: mutations, orderedRecords: records.map(\.value),
            history: history, source: source
        )
    }

    static func record(
        mutation: WorkPacketMutationV1,
        generationID: UUID,
        workspaceRevision: UInt64,
        localSequence: UInt64,
        replicaID: ReplicaID
    ) throws -> Record {
        let command = WorkspaceCommandV1.applyWorkPacket(mutation)
        let concurrencyIdentity = try mutation.concurrencyIdentity
        let affectedIdentity = try mutation.affectedIdentity
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID, generationID: generationID,
            writerInstanceID: writerID, workspaceRevision: workspaceRevision,
            entityRevisions: [WorkspaceEntityRevisionV1(
                identity: concurrencyIdentity, revision: mutation.expectedRevision
            )]
        )
        let envelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: mutation.mutationID, expectedRevision: expected, command: command
            ),
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: mutation.workspaceID, replicaID: replicaID
            )
        )
        let image = try mutation.postImage.mutationPostImage
        let resulting = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID, generationID: generationID,
            writerInstanceID: writerID, workspaceRevision: workspaceRevision + 1,
            entityRevisions: [WorkspaceEntityRevisionV1(
                identity: affectedIdentity, revision: mutation.postImage.revision
            )]
        ))
        let receipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: mutation.workspaceID, replicaID: replicaID,
                localSequence: localSequence
            ),
            envelope: envelope, resultingRevision: resulting,
            postImages: [image], committedAt: date.addingTimeInterval(Double(localSequence))
        )
        _ = try WorkPacketMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        return Record(
            value: MutationHistoryReceiptRecordV1(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil, semanticReversalData: nil
            ),
            receipt: receipt, image: image
        )
    }

    static func graph(
        mutations: [WorkPacketMutationV1],
        manifest: WorkPacketManifestV1
    ) throws -> WorkPacketProjectionV1 {
        let claims = mutations.compactMap { mutation -> WorkItemClaimV1? in
            switch mutation.postImage {
            case let .appendClaim(value), let .supersedeClaim(value): value
            default: nil
            }
        }
        let leases = mutations.compactMap { mutation -> WorkLeaseV1? in
            switch mutation.postImage {
            case let .appendLease(value), let .supersedeLease(value): value
            default: nil
            }
        }
        let releases = mutations.compactMap { mutation -> WorkReleaseV1? in
            guard case let .recordRelease(value) = mutation.postImage else { return nil }
            return value
        }
        let handoffs = mutations.compactMap { mutation -> WorkHandoffV1? in
            guard case let .recordHandoff(value) = mutation.postImage else { return nil }
            return value
        }
        return try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: manifest.workspaceID, manifest: manifest,
            claims: claims, leases: leases, releases: releases, handoffs: handoffs,
            at: date.addingTimeInterval(10_000)
        )
    }

    static func rebound(_ actor: ActorSnapshotV1, to workspaceID: WorkspaceID) throws
        -> ActorSnapshotV1 {
        try ActorSnapshotV1(
            snapshotID: actor.snapshotID, workspaceID: workspaceID,
            actor: LocalActorReferenceV1(
                actorReferenceID: actor.actor.actorReferenceID,
                workspaceID: workspaceID, partyID: actor.actor.partyID,
                displayName: actor.actor.displayName
            ),
            responsibility: actor.responsibility,
            displayNameAtTime: actor.displayNameAtTime,
            capturedAt: actor.capturedAt
        )
    }

    static func sorted(_ values: [MutationIDV1]) -> [MutationIDV1] {
        values.sorted(by: mutationOrder)
    }

    static func mutationOrder(_ left: MutationIDV1, _ right: MutationIDV1) -> Bool {
        left.rawValue.uuidString < right.rawValue.uuidString
    }
}
