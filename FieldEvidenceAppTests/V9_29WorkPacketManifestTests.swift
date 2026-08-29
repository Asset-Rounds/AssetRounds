import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V9_29WorkPacketManifestTests: XCTestCase {
    func testV23P03C15GoldenClaimLeaseReleaseAndHandoffProjection() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture()

        try fixture.manifest.validate()
        try fixture.manifestReference.validate()
        try fixture.itemReference.validate()
        try fixture.claim.validate()
        try fixture.successorClaim.validateSuccessor(of: fixture.claim)
        try fixture.lease.validate()
        try fixture.successorLease.validateSuccessor(of: fixture.lease)
        try fixture.completedRelease.validate(
            claim: fixture.claim, lease: fixture.lease, manifest: fixture.manifest
        )
        try fixture.handoffRelease.validate(claim: fixture.claim, lease: fixture.lease)
        try fixture.handoff.validate(release: fixture.handoffRelease)

        let completed = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, manifest: fixture.manifest,
            claims: [fixture.claim], leases: [fixture.lease],
            releases: [fixture.completedRelease], handoffs: [],
            at: fixture.completedRelease.releasedAt
        )
        let completedItem = try XCTUnwrap(
            completed.items.first(where: { $0.item.itemID == fixture.item.itemID })
        )
        XCTAssertEqual(completed.items.count, fixture.manifest.items.count)
        XCTAssertNil(completedItem.currentClaim)
        XCTAssertNil(completedItem.currentLease)
        XCTAssertEqual(completedItem.latestRelease, fixture.completedRelease)
        XCTAssertEqual(completedItem.preservedResults, [fixture.result])

        let handedOff = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, manifest: fixture.manifest,
            claims: [fixture.claim], leases: [fixture.lease],
            releases: [fixture.handoffRelease], handoffs: [fixture.handoff],
            at: fixture.handoff.handedOffAt
        )
        let handoffItem = try XCTUnwrap(
            handedOff.items.first(where: { $0.item.itemID == fixture.item.itemID })
        )
        XCTAssertNil(handoffItem.currentClaim)
        XCTAssertEqual(handoffItem.latestRelease, fixture.handoffRelease)
        XCTAssertEqual(handoffItem.latestHandoff, fixture.handoff)
        XCTAssertEqual(handoffItem.preservedResults, [fixture.alternateResult, fixture.alternateResult])
    }

    func testV23P03C15MutationTransitionTableAndConcurrencyIdentity() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_029)
        let manifestMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.manifest.mutationID,
            postImage: .appendManifest(fixture.manifest)
        )
        let claimMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.claim.mutationID,
            postImage: .appendClaim(fixture.claim)
        )
        let successorClaimMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: fixture.claim.revision,
            mutationID: fixture.successorClaim.mutationID,
            postImage: .supersedeClaim(fixture.successorClaim)
        )
        let leaseMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.lease.mutationID,
            postImage: .appendLease(fixture.lease)
        )
        let successorLeaseMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: fixture.lease.revision,
            mutationID: fixture.successorLease.mutationID,
            postImage: .supersedeLease(fixture.successorLease)
        )
        let releaseMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.completedRelease.mutationID,
            postImage: .recordRelease(fixture.completedRelease)
        )
        let handoffMutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.handoff.mutationID,
            postImage: .recordHandoff(fixture.handoff)
        )
        let mutations = [
            manifestMutation, claimMutation, successorClaimMutation,
            leaseMutation, successorLeaseMutation, releaseMutation, handoffMutation
        ]

        XCTAssertTrue(WorkspaceCommandKindV1.allCases.contains(.applyWorkPacket))
        XCTAssertEqual(try manifestMutation.affectedIdentity.kind, .workPacketManifest)
        XCTAssertEqual(try successorClaimMutation.affectedIdentity.kind, .workItemClaim)
        XCTAssertEqual(try successorClaimMutation.predecessorIdentity?.id, fixture.claim.claimID)
        XCTAssertEqual(try successorLeaseMutation.predecessorIdentity?.id, fixture.lease.leaseID)
        XCTAssertEqual(try manifestMutation.concurrencyIdentity.id, fixture.manifest.manifestID)
        XCTAssertEqual(try successorClaimMutation.concurrencyIdentity.id, fixture.claim.claimID)
        XCTAssertEqual(try successorLeaseMutation.concurrencyIdentity.id, fixture.lease.leaseID)
        XCTAssertEqual(
            Set(mutations.compactMap { try? $0.affectedIdentity.kind.rawValue }).count, 5
        )
        XCTAssertTrue(try mutations.allSatisfy { try $0.canonicalSHA256().count == 64 })
    }

    func testV23P03C15CanonicalReplayAndWorkspaceRebinding() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_030)
        let manifestBytes = try WorkPacketCanonicalCodecV1.encode(fixture.manifest)
        let decodedManifest = try WorkPacketCanonicalCodecV1.decode(
            WorkPacketManifestV1.self, from: manifestBytes
        )
        XCTAssertEqual(decodedManifest, fixture.manifest)
        XCTAssertEqual(try WorkPacketCanonicalCodecV1.encode(decodedManifest), manifestBytes)

        let claimBytes = try WorkPacketCanonicalCodecV1.encode(fixture.claim)
        let decodedClaim = try WorkPacketCanonicalCodecV1.decode(
            WorkItemClaimV1.self, from: claimBytes
        )
        XCTAssertEqual(decodedClaim, fixture.claim)

        XCTAssertEqual(
            try WorkPacketReplayValidatorV1.disposition(
                existing: fixture.manifest, incoming: fixture.manifest, identityMatches: true
            ), .idempotentReplay
        )
        XCTAssertEqual(
            try WorkPacketReplayValidatorV1.disposition(
                existing: fixture.manifest, incoming: fixture.alternateManifest, identityMatches: true
            ), .quarantineDivergentBytes
        )
        XCTAssertEqual(
            try WorkPacketReplayValidatorV1.disposition(
                existing: fixture.manifest, incoming: fixture.alternateManifest, identityMatches: false
            ), .apply
        )

        let rebound = try fixture.manifest.rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.workspaceID, fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.manifestID, fixture.manifest.manifestID)
        XCTAssertNotEqual(rebound.manifestSHA256, fixture.manifest.manifestSHA256)
        XCTAssertEqual(rebound.items, fixture.manifest.items)
    }

    func testV23P03C15HostileInputsFailClosedAndPreserveBoundaries() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_031)
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

        XCTAssertThrowsError(
            try WorkPacketManifestV1(
                manifestID: zero, packetID: fixture.manifest.packetID,
                packetVersion: 1, workspaceID: fixture.workspaceID,
                items: [fixture.item], packageReleases: [fixture.packageRelease],
                creationBasis: .explicitLocalSelection, creator: fixture.creator,
                createdAt: fixture.manifest.createdAt, mutationID: fixture.manifest.mutationID
            )
        ) { error in
            XCTAssertEqual(error as? WorkPacketFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(
            try WorkItemClaimV1(
                claimID: fixture.claim.claimID, workspaceID: fixture.otherWorkspaceID,
                manifest: fixture.manifestReference, item: fixture.itemReference,
                holder: fixture.holder, claimSequence: 1,
                claimedAt: fixture.claim.claimedAt, mutationID: fixture.claim.mutationID
            )
        ) { error in
            XCTAssertEqual(error as? WorkPacketFailureV1, .holderMismatch)
        }
        XCTAssertThrowsError(
            try WorkLeaseV1(
                leaseID: fixture.lease.leaseID, workspaceID: fixture.workspaceID,
                claimID: fixture.claim.claimID, item: fixture.itemReference,
                holder: fixture.holder, leaseSequence: 1,
                startsAt: fixture.lease.startsAt,
                expiresAt: fixture.lease.startsAt.addingTimeInterval(
                    WorkPacketLimitsV1.maximumLeaseSeconds + 1
                ), mutationID: fixture.lease.mutationID
            )
        )
        XCTAssertThrowsError(
            try WorkReleaseV1(
                releaseID: fixture.completedRelease.releaseID,
                workspaceID: fixture.workspaceID, claimID: fixture.claim.claimID,
                leaseID: fixture.lease.leaseID, item: fixture.itemReference,
                holder: fixture.holder, reason: .completed, resultLinks: [],
                releasedAt: fixture.completedRelease.releasedAt,
                mutationID: fixture.completedRelease.mutationID
            )
        )
        XCTAssertThrowsError(
            try WorkHandoffV1(
                handoffID: fixture.handoff.handoffID, workspaceID: fixture.workspaceID,
                releaseID: fixture.handoffRelease.releaseID, item: fixture.itemReference,
                fromHolder: fixture.holder, toHolder: fixture.holder,
                resultLinks: [fixture.alternateResult], reason: "same actor",
                handedOffAt: fixture.handoff.handedOffAt, mutationID: fixture.handoff.mutationID
            )
        )
        XCTAssertThrowsError(
            try WorkPacketResultLinkV1(
                resultID: fixture.result.resultID, resultMutationID: fixture.result.resultMutationID,
                itemExpectedRevision: 1, resultRevision: 1, resultSHA256: "not-a-sha",
                evidence: []
            )
        )
        let wrongKindEvidence = try ReviewEvidenceReferenceV1(
            kind: .externalEvidenceReference, referenceID: "c15-wrong-kind",
            revision: 1, sha256: C15WorkPacketManifestTestSupportV1.digest
        )
        let wrongKindResult = try WorkPacketResultLinkV1(
            resultID: C15WorkPacketManifestTestSupportV1.id(150_094),
            resultMutationID: C15WorkPacketManifestTestSupportV1.mutation(150_095),
            itemExpectedRevision: fixture.item.expectedRevision, resultRevision: 1,
            resultSHA256: C15WorkPacketManifestTestSupportV1.digest,
            evidence: [wrongKindEvidence]
        )
        let underEvidenceRelease = try WorkReleaseV1(
            releaseID: C15WorkPacketManifestTestSupportV1.id(150_096),
            workspaceID: fixture.workspaceID, claimID: fixture.claim.claimID,
            leaseID: fixture.lease.leaseID, item: fixture.itemReference,
            holder: fixture.holder, reason: .completed, resultLinks: [wrongKindResult],
            releasedAt: fixture.completedRelease.releasedAt,
            mutationID: C15WorkPacketManifestTestSupportV1.mutation(150_097)
        )
        XCTAssertThrowsError(
            try underEvidenceRelease.validate(
                claim: fixture.claim, lease: fixture.lease, manifest: fixture.manifest
            )
        ) { error in
            XCTAssertEqual(error as? WorkPacketFailureV1, .missingResult)
        }
        let staleSuccessor = try WorkItemClaimV1(
            claimID: fixture.successorClaim.claimID, workspaceID: fixture.workspaceID,
            manifest: fixture.manifestReference, item: fixture.itemReference,
            holder: fixture.successorHolder, claimSequence: 3,
            claimedAt: fixture.successorClaim.claimedAt,
            supersedesClaimID: fixture.claim.claimID, revision: 3,
            mutationID: fixture.successorClaim.mutationID
        )
        XCTAssertThrowsError(try staleSuccessor.validateSuccessor(of: fixture.claim)) { error in
            XCTAssertEqual(error as? WorkPacketFailureV1, .staleRevision)
        }
        XCTAssertThrowsError(
            try WorkPacketProjectionBuilderV1.rebuild(
                workspaceID: fixture.otherWorkspaceID, manifest: fixture.manifest,
                claims: [], leases: [], releases: [], handoffs: [], at: fixture.manifest.createdAt
            )
        ) { error in
            XCTAssertEqual(error as? WorkPacketFailureV1, .wrongWorkspace)
        }
    }

    func testV23P03C15ConflictExpiryAndReclaimExceptionsAreTyped() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_032)

        XCTAssertTrue(try fixture.lease.isActive(at: fixture.lease.startsAt))
        XCTAssertFalse(try fixture.lease.isActive(at: fixture.lease.expiresAt))
        XCTAssertEqual(WorkReleaseReasonV1.allCases.count, 5)
        let prematureReclaim = try WorkReleaseV1(
            releaseID: C15WorkPacketManifestTestSupportV1.id(150_090),
            workspaceID: fixture.workspaceID, claimID: fixture.claim.claimID,
            leaseID: fixture.lease.leaseID, item: fixture.itemReference,
            holder: fixture.holder, reason: .reclaimed, releasedAt: fixture.lease.startsAt
                .addingTimeInterval(200), mutationID: C15WorkPacketManifestTestSupportV1.mutation(150_091)
        )
        XCTAssertThrowsError(
            try prematureReclaim.validate(claim: fixture.claim, lease: fixture.lease)
        )
        let reclaimed = try WorkReleaseV1(
            releaseID: C15WorkPacketManifestTestSupportV1.id(150_092),
            workspaceID: fixture.workspaceID, claimID: fixture.claim.claimID,
            leaseID: fixture.lease.leaseID, item: fixture.itemReference,
            holder: fixture.holder, reason: .reclaimed, releasedAt: fixture.lease.expiresAt,
            mutationID: C15WorkPacketManifestTestSupportV1.mutation(150_093)
        )
        try reclaimed.validate(claim: fixture.claim, lease: fixture.lease)
        XCTAssertEqual(reclaimed.reason, .reclaimed)

        let simultaneous = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, manifest: fixture.manifest,
            claims: [fixture.claim, fixture.competingClaim], leases: [], releases: [],
            handoffs: [], at: fixture.claim.claimedAt
        )
        let simultaneousItem = try XCTUnwrap(
            simultaneous.items.first(where: { $0.item.itemID == fixture.item.itemID })
        )
        XCTAssertTrue(simultaneousItem.exceptions.contains { $0.kind == .simultaneousClaim })
        XCTAssertNil(simultaneousItem.currentClaim)

        let expired = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, manifest: fixture.manifest,
            claims: [fixture.claim], leases: [fixture.lease],
            releases: [fixture.expiredRelease], handoffs: [],
            at: fixture.expiredRelease.releasedAt
        )
        let expiredItem = try XCTUnwrap(
            expired.items.first(where: { $0.item.itemID == fixture.item.itemID })
        )
        XCTAssertTrue(expiredItem.exceptions.contains { $0.kind == .staleResultRevision })
        XCTAssertTrue(expiredItem.exceptions.contains { $0.kind == .expiredLeaseResult })
        XCTAssertEqual(expiredItem.preservedResults, [fixture.staleResult])

        let divergent = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, manifest: fixture.manifest,
            claims: [fixture.claim], leases: [fixture.lease],
            releases: [fixture.completedRelease, fixture.divergentRelease], handoffs: [],
            at: fixture.divergentRelease.releasedAt
        )
        let divergentItem = try XCTUnwrap(
            divergent.items.first(where: { $0.item.itemID == fixture.item.itemID })
        )
        XCTAssertTrue(divergentItem.exceptions.contains { $0.kind == .divergentSameIdentity })
        XCTAssertEqual(divergentItem.preservedResults.count, 2)
        XCTAssertEqual(divergentItem.exceptions.first(where: { $0.kind == .divergentSameIdentity })?.conflictingDigests.count, 2)
    }

    func testV23P03C15PersistenceRowsAndSchemaMigrationRoundTrip() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_033)

        let manifestRow = try WorkPacketManifestRow(fixture.manifest)
        let claimRow = try WorkItemClaimRow(fixture.claim)
        let leaseRow = try WorkLeaseRow(fixture.lease)
        let releaseRow = try WorkReleaseRow(fixture.completedRelease)
        let handoffRow = try WorkHandoffRow(fixture.handoff)
        XCTAssertEqual(try manifestRow.value(), fixture.manifest)
        XCTAssertEqual(try claimRow.value(), fixture.claim)
        XCTAssertEqual(try leaseRow.value(), fixture.lease)
        XCTAssertEqual(try releaseRow.value(), fixture.completedRelease)
        XCTAssertEqual(try handoffRow.value(), fixture.handoff)
        XCTAssertEqual(PersistentSchemaV15.versionIdentifier, Schema.Version(15, 0, 0))
        XCTAssertEqual(PersistentSchemaV15.models.count, 58)
        XCTAssertEqual(PersistentSchemaMigrationPlanV14.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV14.stages.count, 1)
        XCTAssertEqual(PersistentSchemaMigrationPlanV14.schemas[1].versionIdentifier, PersistentSchemaV15.versionIdentifier)
    }

    func testV23P03C15CorpusCoversGAAHIRAAndIntegrationSurfaces() throws {
        struct Flags: Codable {
            let native: Bool
            let hosted: Bool
            let adoption: Bool
            let acceptance: Bool
            let release: Bool
        }
        struct Corpus: Codable {
            let cardID: String
            let ordinal: Int
            let phase: String
            let itemKinds: [String]
            let creationBases: [String]
            let releaseReasons: [String]
            let conflictKinds: [String]
            let coverage: [String]
            let evidenceIDs: [String]
            let boundaryRefs: [String]
            let integrationSurfaces: [String]
            let persistentModelCount: Int
            let recordsSchemaVersion: Int
            let provisionalFlags: Flags
        }

        let data = try Data(contentsOf: C15WorkPacketManifestTestSupportV1.corpusURL())
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        XCTAssertEqual(corpus.cardID, "V23-P03-C15")
        XCTAssertEqual(corpus.ordinal, 52)
        XCTAssertEqual(corpus.phase, "P03")
        XCTAssertEqual(corpus.itemKinds.count, WorkPacketItemKindV1.allCases.count)
        XCTAssertEqual(corpus.creationBases.count, WorkPacketCreationBasisV1.allCases.count)
        XCTAssertEqual(corpus.releaseReasons.count, WorkReleaseReasonV1.allCases.count)
        XCTAssertEqual(corpus.conflictKinds.count, 4)
        XCTAssertEqual(Set(corpus.coverage), Set(["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"]))
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertTrue(corpus.boundaryRefs.contains("V23-P03-C14"))
        XCTAssertTrue(corpus.boundaryRefs.contains("V23-P03-C38"))
        XCTAssertEqual(
            Set(corpus.integrationSurfaces),
            Set(["backup", "restore", "import", "delete", "erase", "migration", "search", "report", "replay", "clone", "fork"])
        )
        XCTAssertEqual(corpus.persistentModelCount, PersistentSchemaV15.models.count)
        XCTAssertEqual(corpus.recordsSchemaVersion, 14)
        XCTAssertFalse(corpus.provisionalFlags.native)
        XCTAssertFalse(corpus.provisionalFlags.hosted)
        XCTAssertFalse(corpus.provisionalFlags.adoption)
        XCTAssertFalse(corpus.provisionalFlags.acceptance)
        XCTAssertFalse(corpus.provisionalFlags.release)
    }
}

extension V9_29WorkPacketManifestTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(PersistentSchemaV22.versionIdentifier, Schema.Version(22, 0, 0))
        XCTAssertEqual(PersistentSchemaV22.models.count, PersistentSchemaV21.models.count + 2)
        XCTAssertNoThrow(try V22FieldReferenceImportBoundaryV1.validate(persistent: 22, records: 21))
    }
}

extension V9_29WorkPacketManifestTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
