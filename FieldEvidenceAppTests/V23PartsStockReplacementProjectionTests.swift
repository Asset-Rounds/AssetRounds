import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23PartsStockReplacementProjectionTests: XCTestCase {
    fileprivate typealias Projector = PartsStockReplacementValueProjectionV1

    func testProjectsAllMutationCasesAndSnapshotFamiliesDeterministically() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(for: fixture.source)
        let bindings = try fixture.bindings(for: requirements, includeExternal: true)
        let original = fixture.source
        let originalSnapshotBytes = try PartsStockCanonicalCodecV1.encode(fixture.source.snapshot)
        let originalMutationBytes = try fixture.source.orderedMutations.map {
            try PartsStockCanonicalCodecV1.encode($0)
        }

        let first = try Projector.project(fixture.source, bindings: bindings)
        let second = try Projector.project(fixture.source, bindings: bindings)

        XCTAssertEqual(first, second)
        XCTAssertEqual(fixture.source, original)
        XCTAssertEqual(try PartsStockCanonicalCodecV1.encode(fixture.source.snapshot), originalSnapshotBytes)
        XCTAssertEqual(
            try fixture.source.orderedMutations.map { try PartsStockCanonicalCodecV1.encode($0) },
            originalMutationBytes
        )
        XCTAssertEqual(first.sourceSnapshotSHA256, fixture.source.snapshot.snapshotSHA256)
        XCTAssertNotEqual(first.targetSnapshot.snapshotSHA256, first.sourceSnapshotSHA256)
        XCTAssertEqual(first.targetSnapshot.workspaceID, fixture.targetWorkspaceID)
        XCTAssertEqual(
            [
                first.targetSnapshot.parts.count,
                first.targetSnapshot.locations.count,
                first.targetSnapshot.movements.count,
                first.targetSnapshot.uses.count,
                first.targetSnapshot.reversals.count,
                first.targetSnapshot.returns.count,
                first.targetSnapshot.abandonments.count
            ],
            [3, 2, 11, 2, 1, 2, 2]
        )

        let caseNames = Set(first.mutations.map { Self.mutationCaseName($0.target) })
        XCTAssertEqual(
            caseNames,
            Set([
                "upsertPart", "upsertLocation", "appendMovement", "transfer", "use",
                "reverseUse", "returnAgainstUse", "retirePart", "abandon"
            ])
        )
        XCTAssertEqual(first.mutations.count, fixture.source.orderedMutations.count)
        let mutationMap = Dictionary(uniqueKeysWithValues: bindings.mutationIDs.map {
            ($0.source.rawValue, $0.target)
        })
        for projection in first.mutations {
            XCTAssertEqual(projection.sourcePostImages, try projection.source.mutationPostImages)
            XCTAssertEqual(projection.targetPostImages, try projection.target.mutationPostImages)
            XCTAssertEqual(projection.target.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.mutationID, mutationMap[projection.source.mutationID.rawValue])
            XCTAssertNotEqual(projection.target.mutationID, projection.source.mutationID)
            XCTAssertNotEqual(projection.targetPostImages, projection.sourcePostImages)
        }

        XCTAssertEqual(first.parts.count, 5)
        for projection in first.parts {
            XCTAssertEqual(projection.target.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.partID, projection.source.partID)
            XCTAssertEqual(projection.target.displayName, projection.source.displayName)
            XCTAssertEqual(projection.target.canonicalUnit, projection.source.canonicalUnit)
            XCTAssertEqual(projection.target.productIdentities, projection.source.productIdentities)
            XCTAssertEqual(projection.target.preferredMinimum, projection.source.preferredMinimum)
            XCTAssertEqual(projection.target.archived, projection.source.archived)
            XCTAssertEqual(projection.target.revision, projection.source.revision)
            XCTAssertEqual(projection.target.mutationID, mutationMap[projection.source.mutationID.rawValue])
            XCTAssertNotEqual(projection.target.partSHA256, projection.source.partSHA256)
        }
        for projection in first.locations {
            XCTAssertEqual(projection.target.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.locationID, projection.source.locationID)
            XCTAssertEqual(projection.target.kind, projection.source.kind)
            XCTAssertEqual(projection.target.label, projection.source.label)
            XCTAssertEqual(projection.target.binLabel, projection.source.binLabel)
            XCTAssertEqual(projection.target.revision, projection.source.revision)
            XCTAssertEqual(projection.target.archived, projection.source.archived)
        }
        for projection in first.actors {
            XCTAssertEqual(projection.target.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.snapshotID, projection.source.snapshotID)
            XCTAssertEqual(projection.target.actor.actorReferenceID, projection.source.actor.actorReferenceID)
            XCTAssertEqual(projection.target.actor.partyID, projection.source.actor.partyID)
            XCTAssertEqual(projection.target.responsibility, projection.source.responsibility)
            XCTAssertEqual(projection.target.displayNameAtTime, projection.source.displayNameAtTime)
            XCTAssertEqual(projection.target.capturedAt, projection.source.capturedAt)
            XCTAssertNotEqual(projection.target.snapshotSHA256, projection.source.snapshotSHA256)
        }

        let targetPartSHABySourceSHA = Dictionary(uniqueKeysWithValues: first.parts.map {
            ($0.source.partSHA256, $0.target.partSHA256)
        })
        let targetWorkBySourceSHA = Dictionary(uniqueKeysWithValues: first.workResources.map {
            ($0.source.entrySHA256, $0.target)
        })
        XCTAssertEqual(first.workResources.count, 5)
        for projection in first.workResources {
            XCTAssertEqual(projection.target.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.entryID, projection.source.entryID)
            XCTAssertEqual(projection.target.expectedRevision, projection.source.expectedRevision)
            XCTAssertEqual(projection.target.revision, projection.source.revision)
            XCTAssertEqual(projection.target.supersedesEntryID, projection.source.supersedesEntryID)
            XCTAssertEqual(projection.target.subject.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.actor.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(projection.target.mutationID, mutationMap[projection.source.mutationID.rawValue])
            XCTAssertNotEqual(projection.target.entrySHA256, projection.source.entrySHA256)
            for (sourceLine, targetLine) in zip(projection.source.materials, projection.target.materials) {
                XCTAssertEqual(targetLine.lineID, sourceLine.lineID)
                XCTAssertEqual(targetLine.description, sourceLine.description)
                XCTAssertEqual(targetLine.quantity, sourceLine.quantity)
                XCTAssertEqual(targetLine.unit, sourceLine.unit)
                if let sourceReference = sourceLine.localPartReference {
                    XCTAssertEqual(
                        targetLine.localPartReference?.partSHA256,
                        targetPartSHABySourceSHA[sourceReference.partSHA256]
                    )
                    XCTAssertNotEqual(targetLine.localPartReference, sourceLine.localPartReference)
                }
            }
        }

        let targetExternalUseWork = try XCTUnwrap(first.workResources.first {
            $0.source.entryID == fixture.externalSuccessorEntryID
        })
        XCTAssertEqual(targetExternalUseWork.target.supersedesEntrySHA256, fixture.targetExternalDigest)
        XCTAssertNotEqual(
            targetExternalUseWork.target.supersedesEntrySHA256,
            targetExternalUseWork.source.supersedesEntrySHA256
        )
        for projection in first.workResources where projection.source.supersedesEntryID != nil
            && projection.source.entryID != fixture.externalSuccessorEntryID {
            let sourcePredecessorSHA = try XCTUnwrap(projection.source.supersedesEntrySHA256)
            XCTAssertEqual(
                projection.target.supersedesEntrySHA256,
                targetWorkBySourceSHA[sourcePredecessorSHA]?.entrySHA256
            )
        }

        let targetMovementByID = Dictionary(uniqueKeysWithValues: first.targetSnapshot.movements.map {
            ($0.movementID, $0)
        })
        for sourceMovement in fixture.source.snapshot.movements {
            let targetMovement = try XCTUnwrap(targetMovementByID[sourceMovement.movementID])
            XCTAssertEqual(targetMovement.workspaceID, fixture.targetWorkspaceID)
            XCTAssertEqual(targetMovement.locationID, sourceMovement.locationID)
            XCTAssertEqual(targetMovement.kind, sourceMovement.kind)
            XCTAssertEqual(targetMovement.quantity, sourceMovement.quantity)
            XCTAssertEqual(targetMovement.unit, sourceMovement.unit)
            XCTAssertEqual(targetMovement.preBalance, sourceMovement.preBalance)
            XCTAssertEqual(targetMovement.postBalance, sourceMovement.postBalance)
            XCTAssertEqual(targetMovement.relatedMovementID, sourceMovement.relatedMovementID)
            XCTAssertEqual(targetMovement.reason, sourceMovement.reason)
            XCTAssertEqual(targetMovement.occurredAt, sourceMovement.occurredAt)
            XCTAssertEqual(targetMovement.recordedAt, sourceMovement.recordedAt)
            XCTAssertEqual(targetMovement.expectedLocationRevision, sourceMovement.expectedLocationRevision)
            XCTAssertEqual(targetMovement.locationRevision, sourceMovement.locationRevision)
            XCTAssertEqual(
                targetMovement.part.partSHA256,
                targetPartSHABySourceSHA[sourceMovement.part.partSHA256]
            )
            XCTAssertNotEqual(targetMovement.eventSHA256, sourceMovement.eventSHA256)
        }

        let targetReturns = first.targetSnapshot.returns.sorted { $0.resultingReturnedMantissa < $1.resultingReturnedMantissa }
        XCTAssertNil(targetReturns[0].predecessorFrontier)
        XCTAssertEqual(targetReturns[1].predecessorFrontier, try targetReturns[0].frontierSnapshot())
        XCTAssertNotEqual(
            targetReturns[1].predecessorFrontier?.frontierSHA256,
            fixture.secondReturn.predecessorFrontier?.frontierSHA256
        )

        let directRebound = try fixture.externalUse.workResourceSuccessor.rebound(
            to: fixture.targetWorkspaceID,
            mappedSubject: try XCTUnwrap(bindings.workSubjects.first?.target),
            mappedActor: try XCTUnwrap(first.actors.first {
                $0.source == fixture.externalUse.workResourceSuccessor.actor
            }?.target),
            mappedSupersedesEntrySHA256: fixture.targetExternalDigest,
            mutationID: try XCTUnwrap(mutationMap[fixture.externalUse.mutationID.rawValue])
        )
        XCTAssertEqual(
            directRebound.materials.first?.localPartReference,
            fixture.externalUse.workResourceSuccessor.materials.first?.localPartReference
        )
        XCTAssertNotEqual(
            targetExternalUseWork.target.materials.first?.localPartReference,
            directRebound.materials.first?.localPartReference
        )
    }

    func testCursorStagesExternalPredecessorAndMatchesOneShotFold() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(for: fixture.source)
        let oneShotBindings = try fixture.bindings(for: requirements, includeExternal: true)
        let stagedBindings = try fixture.bindings(for: requirements, includeExternal: false)
        let expected = try Projector.project(fixture.source, bindings: oneShotBindings)
        let external = try XCTUnwrap(oneShotBindings.externalWorkPredecessors.first)
        var cursor = try Projector.begin(fixture.source, bindings: stagedBindings)

        for mutation in fixture.source.orderedMutations {
            let supplied = mutation.mutationID == fixture.externalUse.mutationID ? [external] : []
            let step = try Projector.projectNext(cursor, externalWorkPredecessors: supplied)
            XCTAssertEqual(step.projection.source, mutation)
            cursor = step.cursor
        }
        XCTAssertEqual(try Projector.finish(cursor), expected)

        let fresh = try Projector.begin(fixture.source, bindings: stagedBindings)
        XCTAssertThrowsError(try Projector.projectNext(fresh, externalWorkPredecessors: [external])) {
            XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding)
        }
    }

    func testBindingBoundaryFailsClosed() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(for: fixture.source)
        let valid = try fixture.bindings(for: requirements, includeExternal: true)

        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: Projector.Bindings(
                    targetWorkspaceID: fixture.targetWorkspaceID,
                    mutationIDs: Array(valid.mutationIDs.dropLast()),
                    workSubjects: valid.workSubjects,
                    externalWorkPredecessors: valid.externalWorkPredecessors
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding) }

        var reusedSourceID = valid.mutationIDs
        reusedSourceID[0] = .init(source: reusedSourceID[0].source, target: reusedSourceID[0].source)
        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: .init(
                    targetWorkspaceID: fixture.targetWorkspaceID,
                    mutationIDs: reusedSourceID,
                    workSubjects: valid.workSubjects,
                    externalWorkPredecessors: valid.externalWorkPredecessors
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding) }

        var duplicateTargets = valid.mutationIDs
        duplicateTargets[1] = .init(source: duplicateTargets[1].source, target: duplicateTargets[0].target)
        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: .init(
                    targetWorkspaceID: fixture.targetWorkspaceID,
                    mutationIDs: duplicateTargets,
                    workSubjects: valid.workSubjects,
                    externalWorkPredecessors: valid.externalWorkPredecessors
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding) }

        let sourceSubject = try XCTUnwrap(requirements.workSubjects.first)
        let wrongWorkspaceSubject = try WorkResourceSubjectV1(
            workspaceID: fixture.sourceWorkspaceID,
            kind: sourceSubject.kind,
            subjectID: sourceSubject.subjectID,
            subjectRevision: sourceSubject.subjectRevision,
            subjectSHA256: Fixture.digest("d")
        )
        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: .init(
                    targetWorkspaceID: fixture.targetWorkspaceID,
                    mutationIDs: valid.mutationIDs,
                    workSubjects: [.init(source: sourceSubject, target: wrongWorkspaceSubject)],
                    externalWorkPredecessors: valid.externalWorkPredecessors
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding) }

        let reusedDigestSubject = try WorkResourceSubjectV1(
            workspaceID: fixture.targetWorkspaceID,
            kind: sourceSubject.kind,
            subjectID: sourceSubject.subjectID,
            subjectRevision: sourceSubject.subjectRevision,
            subjectSHA256: sourceSubject.subjectSHA256
        )
        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: .init(
                    targetWorkspaceID: fixture.targetWorkspaceID,
                    mutationIDs: valid.mutationIDs,
                    workSubjects: [.init(source: sourceSubject, target: reusedDigestSubject)],
                    externalWorkPredecessors: valid.externalWorkPredecessors
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding) }

        let externalRequirement = try XCTUnwrap(requirements.externalWorkPredecessors.first)
        let reusedExternalDigest = Projector.ExternalWorkPredecessorBinding(
            requirement: externalRequirement,
            targetEntrySHA256: externalRequirement.sourceEntrySHA256
        )
        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: .init(
                    targetWorkspaceID: fixture.targetWorkspaceID,
                    mutationIDs: valid.mutationIDs,
                    workSubjects: valid.workSubjects,
                    externalWorkPredecessors: [reusedExternalDigest]
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidBinding) }

        let noExternal = try fixture.bindings(for: requirements, includeExternal: false)
        XCTAssertThrowsError(try Projector.project(fixture.source, bindings: noExternal)) {
            XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .missingDependency)
        }
    }

    func testSameWorkspaceInvalidOrderAndLossyHistoryAreRejected() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(for: fixture.source)
        let targetBindings = try fixture.bindings(for: requirements, includeExternal: true)
        let sameSubject = try WorkResourceSubjectV1(
            workspaceID: fixture.sourceWorkspaceID,
            kind: fixture.sourceSubject.kind,
            subjectID: fixture.sourceSubject.subjectID,
            subjectRevision: fixture.sourceSubject.subjectRevision,
            subjectSHA256: Fixture.digest("f")
        )
        XCTAssertThrowsError(
            try Projector.begin(
                fixture.source,
                bindings: .init(
                    targetWorkspaceID: fixture.sourceWorkspaceID,
                    mutationIDs: targetBindings.mutationIDs,
                    workSubjects: [.init(source: fixture.sourceSubject, target: sameSubject)],
                    externalWorkPredecessors: targetBindings.externalWorkPredecessors
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .sameWorkspace) }

        var reordered = fixture.source.orderedMutations
        let externalUseIndex = try XCTUnwrap(reordered.firstIndex { $0.mutationID == fixture.externalUse.mutationID })
        let firstReturnIndex = try XCTUnwrap(reordered.firstIndex {
            Self.mutationCaseName($0) == "returnAgainstUse"
        })
        reordered.swapAt(externalUseIndex, firstReturnIndex)
        XCTAssertThrowsError(
            try Projector.requirements(for: .init(snapshot: fixture.source.snapshot, orderedMutations: reordered))
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidOrder) }

        let lossyMutations = fixture.source.orderedMutations.filter {
            Self.mutationCaseName($0) != "reverseUse"
        }
        let lossySource = Projector.Source(snapshot: fixture.source.snapshot, orderedMutations: lossyMutations)
        XCTAssertThrowsError(try Projector.requirements(for: lossySource)) {
            XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .incompleteProjection)
        }
    }

    func testExplicitCatalogBaselinesPreserveStrictlyValidatedValuesAndMissingRevisionOne() throws {
        let sourceWorkspaceID = Fixture.workspace(900)
        let targetWorkspaceID = Fixture.workspace(901)
        let part = try Fixture.part(
            slot: 902,
            workspaceID: sourceWorkspaceID,
            mutationID: try Fixture.mutation(903)
        )
        let location = try StockStorageLocationV1(
            locationID: Fixture.id(904), workspaceID: sourceWorkspaceID,
            kind: .shop, label: "External baseline shelf", binLabel: "B-1", revision: 1
        )
        let snapshot = try PartsStockBackupSnapshotV1(
            workspaceID: sourceWorkspaceID,
            parts: [part], locations: [location], movements: [],
            uses: [], reversals: [], returns: [], abandonments: []
        )
        let partRevision = MutationHistoryEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition, id: part.partID
            ),
            revision: part.revision,
            externalProjectionSHA256: part.partSHA256
        )
        let locationRevision = MutationHistoryEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(
                kind: .stockStorageLocation, id: location.locationID
            ),
            revision: location.revision,
            externalProjectionSHA256: try PartsStockCanonicalCodecV1.sha256(location)
        )
        let history = MutationHistorySnapshotV1(
            workspaceRevision: 0, lastLocalSequence: 0, receipts: [], quarantines: [],
            entityRevisions: [partRevision, locationRevision]
        )
        let records = V4BackupRecordsV1(
            workPackets: [], assets: [], evidenceFiles: [], issues: [],
            mutationHistory: history, packets: [], partyAccountability: [],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [], workResources: [],
            partsStockSnapshot: snapshot
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(history))
        XCTAssertNoThrow(
            try C55PartsStockBackupImportBoundaryV1.validate(
                records,
                workspaceID: sourceWorkspaceID
            )
        )

        let baselineSource = Projector.Source(
            snapshot: snapshot,
            orderedMutations: [],
            originalCatalogBaselines: [
                .part(entityRevision: partRevision, value: part),
                .location(entityRevision: locationRevision, value: location),
            ]
        )
        let requirements = try Projector.requirements(for: baselineSource)
        let bindings = Projector.Bindings(
            targetWorkspaceID: targetWorkspaceID,
            mutationIDs: try requirements.mutationIDs.enumerated().map { index, source in
                .init(source: source, target: try Fixture.mutation(920 + index))
            },
            workSubjects: []
        )
        let result = try Projector.project(baselineSource, bindings: bindings)
        XCTAssertTrue(result.mutations.isEmpty)
        XCTAssertEqual(result.parts.map(\.source), [part])
        XCTAssertEqual(result.locations.map(\.source), [location])
        XCTAssertEqual(result.targetSnapshot.parts.map(\.partID), [part.partID])
        XCTAssertEqual(result.targetSnapshot.locations.map(\.locationID), [location.locationID])
        XCTAssertEqual(result.targetSnapshot.workspaceID, targetWorkspaceID)

        let revisionTwo = try Fixture.part(
            slot: 930, workspaceID: sourceWorkspaceID,
            mutationID: try Fixture.mutation(931), revision: 2
        )
        let revisionThree = try Fixture.part(
            slot: 930, workspaceID: sourceWorkspaceID,
            mutationID: try Fixture.mutation(932), revision: 3
        )
        let laterSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: sourceWorkspaceID,
            parts: [revisionThree], locations: [], movements: [],
            uses: [], reversals: [], returns: [], abandonments: []
        )
        let laterRevision = MutationHistoryEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition, id: revisionThree.partID
            ),
            revision: revisionThree.revision,
            externalProjectionSHA256: revisionThree.partSHA256
        )
        let laterSource = Projector.Source(
            snapshot: laterSnapshot,
            orderedMutations: [.upsertPart(revisionTwo), .upsertPart(revisionThree)],
            originalCatalogBaselines: [
                .part(entityRevision: laterRevision, value: revisionThree),
            ]
        )
        let laterRequirements = try Projector.requirements(for: laterSource)
        let laterBindings = Projector.Bindings(
            targetWorkspaceID: targetWorkspaceID,
            mutationIDs: try laterRequirements.mutationIDs.enumerated().map { index, source in
                .init(source: source, target: try Fixture.mutation(940 + index))
            },
            workSubjects: []
        )
        let laterResult = try Projector.project(laterSource, bindings: laterBindings)
        XCTAssertEqual(laterResult.parts.map(\.source.revision).sorted(), [2, 3])
        XCTAssertFalse(laterResult.parts.contains { $0.source.revision == 1 })
        XCTAssertEqual(laterResult.targetSnapshot.parts.count, 1)
        XCTAssertEqual(laterResult.targetSnapshot.parts.first?.revision, 3)

        let locationTwo = try StockStorageLocationV1(
            locationID: location.locationID, workspaceID: sourceWorkspaceID,
            kind: .shop, label: "External baseline shelf v2", binLabel: "B-1", revision: 2
        )
        let locationThree = try StockStorageLocationV1(
            locationID: location.locationID, workspaceID: sourceWorkspaceID,
            kind: .shop, label: "External baseline shelf v3", binLabel: "B-1", revision: 3
        )
        let partTwoMutation = try Fixture.mutation(933)
        let partThreeMutation = try Fixture.mutation(934)
        let locationTwoMutation = try Fixture.mutation(935)
        let locationThreeMutation = try Fixture.mutation(936)
        let admittedPartTwo = try Fixture.part(
            slot: 937, workspaceID: sourceWorkspaceID,
            mutationID: partTwoMutation, revision: 2
        )
        let admittedPartThree = try Fixture.part(
            slot: 937, workspaceID: sourceWorkspaceID,
            mutationID: partThreeMutation, revision: 3
        )
        let admittedMutations: [PartsStockMutationV1] = [
            .upsertPart(admittedPartTwo),
            .upsertLocation(locationTwo, mutationID: locationTwoMutation),
            .upsertPart(admittedPartThree),
            .upsertLocation(locationThree, mutationID: locationThreeMutation),
        ]
        let replica = try WorkspaceReplicaIdentityV1(
            workspaceID: sourceWorkspaceID, replicaID: ReplicaID(rawValue: Fixture.id(938))
        )
        let generationID = Fixture.id(939)
        let admittedReceipts = try admittedMutations.enumerated().map { offset, mutation in
            try Self.c55HistoryRecord(
                mutation: mutation,
                identity: replica,
                generationID: generationID,
                workspaceRevision: UInt64(offset),
                localSequence: UInt64(offset + 1)
            )
        }
        let admittedPartRevision = MutationHistoryEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition, id: admittedPartThree.partID
            ),
            revision: admittedPartThree.revision,
            externalProjectionSHA256: admittedPartThree.partSHA256
        )
        let admittedLocationRevision = MutationHistoryEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(
                kind: .stockStorageLocation, id: locationThree.locationID
            ),
            revision: locationThree.revision,
            externalProjectionSHA256: try PartsStockCanonicalCodecV1.sha256(locationThree)
        )
        let admittedHistory = MutationHistorySnapshotV1(
            workspaceRevision: UInt64(admittedReceipts.count),
            lastLocalSequence: UInt64(admittedReceipts.count),
            receipts: admittedReceipts, quarantines: [],
            entityRevisions: [admittedPartRevision, admittedLocationRevision]
        )
        let admittedSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: sourceWorkspaceID,
            parts: [admittedPartThree], locations: [locationThree], movements: [],
            uses: [], reversals: [], returns: [], abandonments: []
        )
        func admittedRecords(_ history: MutationHistorySnapshotV1) -> V4BackupRecordsV1 {
            V4BackupRecordsV1(
                workPackets: [], assets: [], evidenceFiles: [], issues: [],
                mutationHistory: history, packets: [], partyAccountability: [],
                recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
                reports: [], sites: [], workflowRecords: [], workResources: [],
                partsStockSnapshot: admittedSnapshot
            )
        }
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(admittedHistory))
        XCTAssertNoThrow(try C55PartsStockBackupImportBoundaryV1.validate(
            admittedRecords(admittedHistory), workspaceID: sourceWorkspaceID
        ))

        let admittedSource = Projector.Source(
            snapshot: admittedSnapshot,
            orderedMutations: admittedMutations,
            originalCatalogBaselines: [
                .part(entityRevision: admittedPartRevision, value: admittedPartThree),
                .location(entityRevision: admittedLocationRevision, value: locationThree),
            ]
        )
        let admittedRequirements = try Projector.requirements(for: admittedSource)
        let admittedResult = try Projector.project(
            admittedSource,
            bindings: .init(
                targetWorkspaceID: targetWorkspaceID,
                mutationIDs: try admittedRequirements.mutationIDs.enumerated().map { offset, source in
                    .init(source: source, target: try Fixture.mutation(960 + offset))
                },
                workSubjects: []
            )
        )
        XCTAssertEqual(admittedResult.parts.map(\.source), [admittedPartTwo, admittedPartThree])
        XCTAssertEqual(admittedResult.locations.map(\.source), [locationTwo, locationThree])
        XCTAssertEqual(admittedResult.targetSnapshot.parts.first?.revision, 3)
        XCTAssertEqual(admittedResult.targetSnapshot.locations.first?.revision, 3)

        func assertPublicValidatorRejects(_ revisions: [MutationHistoryEntityRevisionV1]) {
            let hostile = MutationHistorySnapshotV1(
                workspaceRevision: admittedHistory.workspaceRevision,
                lastLocalSequence: admittedHistory.lastLocalSequence,
                receipts: admittedHistory.receipts, quarantines: [], entityRevisions: revisions
            )
            XCTAssertThrowsError(try C55PartsStockBackupImportBoundaryV1.validate(
                admittedRecords(hostile), workspaceID: sourceWorkspaceID
            ))
        }
        assertPublicValidatorRejects([
            .init(identity: admittedPartRevision.identity, revision: admittedPartRevision.revision,
                  externalProjectionSHA256: Fixture.digest("f")),
            admittedLocationRevision,
        ])
        assertPublicValidatorRejects([
            .init(identity: admittedPartRevision.identity, revision: admittedPartRevision.revision - 1,
                  externalProjectionSHA256: admittedPartRevision.externalProjectionSHA256),
            admittedLocationRevision,
        ])
        assertPublicValidatorRejects([
            .init(identity: try WorkspaceEntityIdentityV1(
                      kind: .localPartDefinition, id: Fixture.id(961)
                  ), revision: admittedPartRevision.revision,
                  externalProjectionSHA256: admittedPartRevision.externalProjectionSHA256),
            admittedLocationRevision,
        ])
        assertPublicValidatorRejects([
            .init(identity: try WorkspaceEntityIdentityV1(
                      kind: .stockMovementEvent, id: admittedPartThree.partID
                  ), revision: admittedPartRevision.revision,
                  externalProjectionSHA256: admittedPartRevision.externalProjectionSHA256),
            admittedLocationRevision,
        ])
    }

    func testCatalogBaselineProofRejectsMissingForgedMismatchedAndForbiddenFamily() throws {
        let workspaceID = Fixture.workspace(950)
        let part = try Fixture.part(
            slot: 951, workspaceID: workspaceID,
            mutationID: try Fixture.mutation(952)
        )
        let snapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part], locations: [], movements: [],
            uses: [], reversals: [], returns: [], abandonments: []
        )
        let identity = try WorkspaceEntityIdentityV1(
            kind: .localPartDefinition, id: part.partID
        )
        let validRevision = MutationHistoryEntityRevisionV1(
            identity: identity, revision: part.revision,
            externalProjectionSHA256: part.partSHA256
        )
        func source(_ baseline: Projector.OriginalCatalogBaseline?) -> Projector.Source {
            Projector.Source(
                snapshot: snapshot,
                orderedMutations: [],
                originalCatalogBaselines: baseline.map { [$0] } ?? []
            )
        }
        func assertRejected(
            _ baseline: Projector.OriginalCatalogBaseline?,
            _ expected: PartsStockReplacementValueProjectionFailureV1
        ) {
            XCTAssertThrowsError(try Projector.requirements(for: source(baseline))) {
                XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, expected)
            }
        }

        assertRejected(nil, .incompleteProjection)
        assertRejected(
            .part(
                entityRevision: .init(
                    identity: identity, revision: part.revision,
                    externalProjectionSHA256: Fixture.digest("f")
                ),
                value: part
            ),
            .invalidSource
        )
        assertRejected(
            .part(
                entityRevision: .init(
                    identity: identity, revision: part.revision + 1,
                    externalProjectionSHA256: part.partSHA256
                ),
                value: part
            ),
            .invalidSource
        )
        assertRejected(
            .part(
                entityRevision: .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .stockMovementEvent, id: part.partID
                    ),
                    revision: part.revision,
                    externalProjectionSHA256: part.partSHA256
                ),
                value: part
            ),
            .invalidSource
        )
        let foreignValue = try Fixture.part(
            slot: 953, workspaceID: workspaceID,
            mutationID: try Fixture.mutation(954)
        )
        assertRejected(
            .part(
                entityRevision: .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .localPartDefinition, id: foreignValue.partID
                    ),
                    revision: foreignValue.revision,
                    externalProjectionSHA256: foreignValue.partSHA256
                ),
                value: foreignValue
            ),
            .invalidSource
        )
        XCTAssertThrowsError(
            try Projector.requirements(
                for: Projector.Source(
                    snapshot: snapshot,
                    orderedMutations: [],
                    originalCatalogBaselines: [
                        .part(entityRevision: validRevision, value: part),
                        .part(entityRevision: validRevision, value: part),
                    ]
                )
            )
        ) { XCTAssertEqual($0 as? PartsStockReplacementValueProjectionFailureV1, .invalidSource) }
    }

    private static func mutationCaseName(_ mutation: PartsStockMutationV1) -> String {
        switch mutation {
        case .upsertPart: return "upsertPart"
        case .upsertLocation: return "upsertLocation"
        case .appendMovement: return "appendMovement"
        case .transfer: return "transfer"
        case .use: return "use"
        case .reverseUse: return "reverseUse"
        case .returnAgainstUse: return "returnAgainstUse"
        case .retirePart: return "retirePart"
        case .abandon: return "abandon"
        }
    }

    private static func c55HistoryRecord(
        mutation: PartsStockMutationV1,
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        workspaceRevision: UInt64,
        localSequence: UInt64
    ) throws -> MutationHistoryReceiptRecordV1 {
        let concurrency = try mutation.concurrencyIdentities
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID,
            generationID: generationID,
            writerInstanceID: Fixture.id(962),
            workspaceRevision: workspaceRevision,
            entityRevisions: try concurrency.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            }
        )
        let envelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: mutation.mutationID,
                expectedRevision: expected,
                command: .applyPartsStock(mutation)
            ),
            identity: identity
        )
        let postImages = try mutation.mutationPostImages
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: identity.workspaceID,
            generationID: generationID,
            writerInstanceID: Fixture.id(962),
            workspaceRevision: workspaceRevision + 1,
            entityRevisions: try postImages.map {
                .init(identity: try $0.identity, revision: $0.revision)
            }
        )
        let receipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                localSequence: localSequence
            ),
            envelope: envelope,
            resultingRevision: .init(resulting),
            postImages: postImages,
            committedAt: Fixture.fixedDate.addingTimeInterval(TimeInterval(localSequence))
        )
        return .init(
            envelopeData: try envelope.canonicalData(),
            receiptData: try receipt.canonicalData(),
            reversalBasisData: nil,
            semanticReversalData: nil
        )
    }
}

private extension V23PartsStockReplacementProjectionTests {
    struct Fixture {
        let sourceWorkspaceID: WorkspaceID
        let targetWorkspaceID: WorkspaceID
        let sourceSubject: WorkResourceSubjectV1
        let source: Projector.Source
        let externalUse: StockUseOnWorkReceiptV1
        let secondReturn: StockReturnAgainstUseReceiptV1
        let externalSuccessorEntryID: UUID
        let targetExternalDigest: String

        static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

        static func id(_ slot: Int) -> UUID {
            UUID(uuidString: String(format: "55000000-0000-4000-8000-%012x", slot))!
        }

        static func workspace(_ slot: Int) -> WorkspaceID {
            WorkspaceID(rawValue: id(slot))
        }

        static func mutation(_ slot: Int) throws -> MutationIDV1 {
            try MutationIDV1(rawValue: id(slot))
        }

        static func digest(_ character: Character) -> String {
            String(repeating: String(character), count: 64)
        }

        static func quantity(_ mantissa: Int64) throws -> StockQuantityV1 {
            try StockQuantityV1(mantissa: mantissa, scale: 0, unit: .each)
        }

        static func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
            let reference = try LocalActorReferenceV1(
                actorReferenceID: id(40),
                workspaceID: workspaceID,
                partyID: id(41),
                displayName: "Replacement projector actor"
            )
            return try ActorSnapshotV1(
                snapshotID: id(42),
                workspaceID: workspaceID,
                actor: reference,
                responsibility: .recordedBy,
                displayNameAtTime: reference.displayName,
                capturedAt: fixedDate
            )
        }

        static func part(
            slot: Int,
            workspaceID: WorkspaceID,
            mutationID: MutationIDV1,
            archived: Bool = false,
            revision: UInt64 = 1
        ) throws -> LocalPartDefinitionV1 {
            try LocalPartDefinitionV1(
                partID: id(slot),
                workspaceID: workspaceID,
                displayName: "Part \(slot)",
                canonicalUnit: .each,
                productIdentities: [try StockProductIdentityV1(kind: .sku, value: "SKU-\(slot)")],
                preferredMinimum: try quantity(2),
                archived: archived,
                revision: revision,
                mutationID: mutationID
            )
        }

        static func archivedPart(
            from source: LocalPartDefinitionV1,
            mutationID: MutationIDV1
        ) throws -> LocalPartDefinitionV1 {
            try LocalPartDefinitionV1(
                partID: source.partID,
                workspaceID: source.workspaceID,
                displayName: source.displayName,
                canonicalUnit: source.canonicalUnit,
                productIdentities: source.productIdentities,
                preferredMinimum: source.preferredMinimum,
                archived: true,
                revision: source.revision + 1,
                mutationID: mutationID
            )
        }

        static func movement(
            slot: Int,
            workspaceID: WorkspaceID,
            part: LocalPartReferenceSnapshotV1,
            locationID: UUID,
            kind: StockMovementKindV1,
            amount: Int64,
            pre: StockBalanceV1,
            post: Int64,
            relatedMovementID: UUID? = nil,
            reason: String? = nil,
            actor: ActorSnapshotV1,
            expectedRevision: UInt64,
            mutationID: MutationIDV1,
            time: TimeInterval
        ) throws -> StockMovementEventV1 {
            try StockMovementEventV1(
                movementID: id(slot),
                workspaceID: workspaceID,
                part: part,
                locationID: locationID,
                kind: kind,
                quantity: try quantity(amount),
                unit: .each,
                preBalance: pre,
                postBalance: try quantity(post),
                relatedMovementID: relatedMovementID,
                reason: reason,
                actor: actor,
                occurredAt: fixedDate.addingTimeInterval(time),
                recordedAt: fixedDate.addingTimeInterval(time + 1),
                expectedLocationRevision: expectedRevision,
                mutationID: mutationID
            )
        }

        static func material(
            lineID: UUID,
            quantity: Int64,
            part: LocalPartReferenceSnapshotV1
        ) throws -> ManualMaterialLineV1 {
            try ManualMaterialLineV1(
                lineID: lineID,
                description: part.displayName,
                quantity: try ExactDecimalQuantityV1(mantissa: quantity, scale: 0),
                unit: StockUnitV1.each.rawValue,
                localPartReference: part
            )
        }

        static func workEntry(
            slot: Int,
            workspaceID: WorkspaceID,
            subject: WorkResourceSubjectV1,
            actor: ActorSnapshotV1,
            materials: [ManualMaterialLineV1],
            mutationID: MutationIDV1,
            expectedRevision: UInt64,
            predecessor: WorkResourceEntryV1? = nil,
            externalPredecessor: (id: UUID, digest: String)? = nil,
            disposition: WorkResourceDispositionV1 = .active
        ) throws -> WorkResourceEntryV1 {
            let predecessorID = predecessor?.entryID ?? externalPredecessor?.id
            let predecessorDigest = predecessor?.entrySHA256 ?? externalPredecessor?.digest
            return try WorkResourceEntryV1(
                entryID: id(slot),
                workspaceID: workspaceID,
                subject: subject,
                actor: actor,
                duration: materials.isEmpty ? try ManualDurationV1(minutes: 1) : nil,
                materials: materials,
                visibility: .internalOnly,
                disposition: disposition,
                recordedAt: fixedDate.addingTimeInterval(TimeInterval(100 + slot)),
                expectedRevision: expectedRevision,
                revision: expectedRevision + 1,
                supersedesEntryID: predecessorID,
                supersedesEntrySHA256: predecessorDigest,
                mutationID: mutationID
            )
        }

        static func zeroBalance(
            workspaceID: WorkspaceID,
            partID: UUID,
            locationID: UUID,
            movement: StockMovementEventV1
        ) throws -> StockBalanceProjectionV1 {
            let value = StockBalanceProjectionV1(
                workspaceID: workspaceID,
                partID: partID,
                locationID: locationID,
                unit: .each,
                balance: .known(try quantity(0)),
                locationRevision: movement.locationRevision,
                lastMovementID: movement.movementID
            )
            try value.validate()
            return value
        }

        static func make() throws -> Fixture {
            let sourceWorkspaceID = workspace(1)
            let targetWorkspaceID = workspace(2)
            let actor = try actor(workspaceID: sourceWorkspaceID)
            let subject = try WorkResourceSubjectV1(
                workspaceID: sourceWorkspaceID,
                kind: .workPacket,
                subjectID: id(43).uuidString,
                subjectRevision: 3,
                subjectSHA256: digest("a")
            )
            let partA = try part(
                slot: 100,
                workspaceID: sourceWorkspaceID,
                mutationID: try mutation(1)
            )
            let partReference = try partA.frozenReference()
            let location1 = try StockStorageLocationV1(
                locationID: id(110), workspaceID: sourceWorkspaceID, kind: .shop,
                label: "Main shelf", binLabel: "A-1", revision: 1
            )
            let location2 = try StockStorageLocationV1(
                locationID: id(111), workspaceID: sourceWorkspaceID, kind: .vehicle,
                label: "Service van", binLabel: "V-2", revision: 1
            )
            let opening1 = try movement(
                slot: 120, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .openingCount, amount: 10,
                pre: .unknown, post: 10, actor: actor, expectedRevision: 0,
                mutationID: try mutation(4), time: 0
            )
            let opening2 = try movement(
                slot: 121, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location2.locationID, kind: .openingCount, amount: 5,
                pre: .unknown, post: 5, actor: actor, expectedRevision: 0,
                mutationID: try mutation(5), time: 2
            )
            let transferMutationID = try mutation(6)
            let outboundID = id(122)
            let inboundID = id(123)
            let outbound = try StockMovementEventV1(
                movementID: outboundID, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .transferOut, quantity: try quantity(2),
                unit: .each, preBalance: .known(try quantity(10)), postBalance: try quantity(8),
                relatedMovementID: inboundID, actor: actor,
                occurredAt: fixedDate.addingTimeInterval(4),
                recordedAt: fixedDate.addingTimeInterval(5), expectedLocationRevision: 1,
                mutationID: transferMutationID
            )
            let inbound = try StockMovementEventV1(
                movementID: inboundID, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location2.locationID, kind: .transferIn, quantity: try quantity(2),
                unit: .each, preBalance: .known(try quantity(5)), postBalance: try quantity(7),
                relatedMovementID: outboundID, actor: actor,
                occurredAt: fixedDate.addingTimeInterval(4),
                recordedAt: fixedDate.addingTimeInterval(5), expectedLocationRevision: 1,
                mutationID: transferMutationID
            )
            let transfer = StockTransferReceiptV1(
                workspaceID: sourceWorkspaceID,
                outbound: outbound,
                inbound: inbound,
                mutationID: transferMutationID
            )
            try transfer.validate()

            let use1MutationID = try mutation(7)
            let use1Movement = try movement(
                slot: 124, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .useOnWork, amount: 2,
                pre: .known(try quantity(8)), post: 6, actor: actor, expectedRevision: 2,
                mutationID: use1MutationID, time: 6
            )
            let use1LineID = id(200)
            let use1Work = try workEntry(
                slot: 201, workspaceID: sourceWorkspaceID, subject: subject, actor: actor,
                materials: [try material(lineID: use1LineID, quantity: 2, part: partReference)],
                mutationID: use1MutationID, expectedRevision: 0
            )
            let use1 = try StockUseOnWorkReceiptV1(
                receiptID: id(202), movement: use1Movement, workResourceSuccessor: use1Work,
                frozenMaterialLineID: use1LineID, mutationID: use1MutationID
            )

            let reverseMutationID = try mutation(8)
            let reverseMovement = try movement(
                slot: 125, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .reverseUse, amount: 2,
                pre: .known(try quantity(6)), post: 8,
                relatedMovementID: use1Movement.movementID, reason: "Mistaken issue",
                actor: actor, expectedRevision: 3, mutationID: reverseMutationID, time: 8
            )
            let reverseWork = try workEntry(
                slot: 203, workspaceID: sourceWorkspaceID, subject: subject, actor: actor,
                materials: use1Work.materials, mutationID: reverseMutationID,
                expectedRevision: use1Work.revision, predecessor: use1Work, disposition: .reversed
            )
            let reversal = try StockUseReversalReceiptV1(
                receiptID: id(204), sourceUse: use1, reversalMovement: reverseMovement,
                workResourceSuccessor: reverseWork, reason: "Mistaken issue",
                mutationID: reverseMutationID
            )

            let externalSourceDigest = digest("e")
            let externalEntryID = id(205)
            let use2MutationID = try mutation(9)
            let use2Movement = try movement(
                slot: 126, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .useOnWork, amount: 2,
                pre: .known(try quantity(8)), post: 6, actor: actor, expectedRevision: 4,
                mutationID: use2MutationID, time: 10
            )
            let use2LineID = id(206)
            let use2Work = try workEntry(
                slot: 207, workspaceID: sourceWorkspaceID, subject: subject, actor: actor,
                materials: [try material(lineID: use2LineID, quantity: 2, part: partReference)],
                mutationID: use2MutationID, expectedRevision: 1,
                externalPredecessor: (id: externalEntryID, digest: externalSourceDigest)
            )
            let use2 = try StockUseOnWorkReceiptV1(
                receiptID: id(208), movement: use2Movement, workResourceSuccessor: use2Work,
                frozenMaterialLineID: use2LineID, mutationID: use2MutationID
            )

            let return1MutationID = try mutation(10)
            let return1Movement = try movement(
                slot: 127, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .returnAgainstUse, amount: 1,
                pre: .known(try quantity(6)), post: 7,
                relatedMovementID: use2Movement.movementID, actor: actor, expectedRevision: 5,
                mutationID: return1MutationID, time: 12
            )
            let return1Work = try workEntry(
                slot: 209, workspaceID: sourceWorkspaceID, subject: subject, actor: actor,
                materials: [try material(lineID: use2LineID, quantity: 1, part: partReference)],
                mutationID: return1MutationID, expectedRevision: use2Work.revision,
                predecessor: use2Work
            )
            let return1 = try StockReturnAgainstUseReceiptV1(
                receiptID: id(210), sourceUse: use2, predecessorFrontier: nil,
                returnMovement: return1Movement, workResourcePredecessor: use2Work,
                workResourceSuccessor: return1Work, mutationID: return1MutationID
            )

            let return2MutationID = try mutation(11)
            let return2Movement = try movement(
                slot: 128, workspaceID: sourceWorkspaceID, part: partReference,
                locationID: location1.locationID, kind: .returnAgainstUse, amount: 1,
                pre: .known(try quantity(7)), post: 8,
                relatedMovementID: use2Movement.movementID, actor: actor, expectedRevision: 6,
                mutationID: return2MutationID, time: 14
            )
            let return2Work = try workEntry(
                slot: 211, workspaceID: sourceWorkspaceID, subject: subject, actor: actor,
                materials: [], mutationID: return2MutationID,
                expectedRevision: return1Work.revision, predecessor: return1Work
            )
            let return2 = try StockReturnAgainstUseReceiptV1(
                receiptID: id(212), sourceUse: use2,
                predecessorFrontier: try return1.frontierSnapshot(),
                returnMovement: return2Movement, workResourcePredecessor: return1Work,
                workResourceSuccessor: return2Work, mutationID: return2MutationID
            )

            let retirementPart = try part(
                slot: 101, workspaceID: sourceWorkspaceID, mutationID: try mutation(20)
            )
            let retiredPart = try archivedPart(from: retirementPart, mutationID: try mutation(21))
            let retirementCount1 = try movement(
                slot: 129, workspaceID: sourceWorkspaceID,
                part: try retirementPart.frozenReference(), locationID: location1.locationID,
                kind: .physicalCount, amount: 0, pre: .unknown, post: 0,
                actor: actor, expectedRevision: 0, mutationID: try mutation(22), time: 16
            )
            let retirementCount2 = try movement(
                slot: 130, workspaceID: sourceWorkspaceID,
                part: try retirementPart.frozenReference(), locationID: location2.locationID,
                kind: .physicalCount, amount: 0, pre: .unknown, post: 0,
                actor: actor, expectedRevision: 0, mutationID: try mutation(23), time: 18
            )
            let retirement = try StockPartRetirementReceiptV1(
                archivedPartSuccessor: retiredPart,
                predecessor: retirementPart,
                verifiedBalances: [
                    try zeroBalance(
                        workspaceID: sourceWorkspaceID,
                        partID: retirementPart.partID,
                        locationID: location1.locationID,
                        movement: retirementCount1
                    ),
                    try zeroBalance(
                        workspaceID: sourceWorkspaceID,
                        partID: retirementPart.partID,
                        locationID: location2.locationID,
                        movement: retirementCount2
                    )
                ]
            )

            let abandonmentPart = try part(
                slot: 102, workspaceID: sourceWorkspaceID, mutationID: try mutation(30)
            )
            let abandonedPart = try archivedPart(from: abandonmentPart, mutationID: try mutation(31))
            let abandonments = try [location1, location2].enumerated().map { index, location in
                try AbandonUnverifiedStockDispositionV1(
                    dispositionID: id(220 + index), workspaceID: sourceWorkspaceID,
                    partID: abandonmentPart.partID, locationID: location.locationID,
                    actor: actor, reason: "Unable to verify location \(index + 1)",
                    lastMovementID: nil, lastLocationRevision: 0,
                    recordedAt: fixedDate.addingTimeInterval(TimeInterval(20 + index)),
                    mutationID: abandonedPart.mutationID, currentBalance: .unknown
                )
            }
            let abandonment = try StockAbandonmentReceiptV1(
                dispositions: abandonments,
                archivedPartSuccessor: abandonedPart,
                predecessor: abandonmentPart
            )

            let snapshot = try PartsStockBackupSnapshotV1(
                workspaceID: sourceWorkspaceID,
                parts: [partA, retiredPart, abandonedPart],
                locations: [location1, location2],
                movements: [
                    opening1, opening2, outbound, inbound, use1Movement, reverseMovement,
                    use2Movement, return1Movement, return2Movement,
                    retirementCount1, retirementCount2
                ],
                uses: [use1, use2],
                reversals: [reversal],
                returns: [return1, return2],
                abandonments: abandonments
            )
            let mutations: [PartsStockMutationV1] = [
                .upsertPart(partA),
                .upsertLocation(location1, mutationID: try mutation(2)),
                .upsertLocation(location2, mutationID: try mutation(3)),
                .appendMovement(opening1),
                .appendMovement(opening2),
                .transfer(transfer),
                .use(use1),
                .reverseUse(reversal),
                .use(use2),
                .returnAgainstUse(return1),
                .returnAgainstUse(return2),
                .upsertPart(retirementPart),
                .appendMovement(retirementCount1),
                .appendMovement(retirementCount2),
                .retirePart(retirement),
                .upsertPart(abandonmentPart),
                .abandon(abandonment)
            ]
            return Fixture(
                sourceWorkspaceID: sourceWorkspaceID,
                targetWorkspaceID: targetWorkspaceID,
                sourceSubject: subject,
                source: Projector.Source(snapshot: snapshot, orderedMutations: mutations),
                externalUse: use2,
                secondReturn: return2,
                externalSuccessorEntryID: use2Work.entryID,
                targetExternalDigest: digest("c")
            )
        }

        func bindings(
            for requirements: Projector.Requirements,
            includeExternal: Bool
        ) throws -> Projector.Bindings {
            let mutations = try requirements.mutationIDs.enumerated().map { index, source in
                Projector.MutationIDBinding(source: source, target: try Self.mutation(800 + index))
            }
            let subjects = try requirements.workSubjects.map { source in
                Projector.WorkSubjectBinding(
                    source: source,
                    target: try WorkResourceSubjectV1(
                        workspaceID: targetWorkspaceID,
                        kind: source.kind,
                        subjectID: source.subjectID,
                        subjectRevision: source.subjectRevision,
                        subjectSHA256: Self.digest("b")
                    )
                )
            }
            let external = includeExternal ? requirements.externalWorkPredecessors.map {
                Projector.ExternalWorkPredecessorBinding(
                    requirement: $0,
                    targetEntrySHA256: targetExternalDigest
                )
            } : []
            return Projector.Bindings(
                targetWorkspaceID: targetWorkspaceID,
                mutationIDs: mutations,
                workSubjects: subjects,
                externalWorkPredecessors: external
            )
        }
    }
}
