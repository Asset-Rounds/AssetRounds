import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23ReferenceOwnerReplacementCommandPlanTests: XCTestCase {
    func testMixedPlanHasExactSourceOrderCoverageAndHistoricalTargets() throws {
        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        let plan = try makePlan(corpus)
        let selected = corpus.source.entries.filter { selectedFamilies.contains($0.family) }

        XCTAssertEqual(plan.source, corpus.source)
        XCTAssertEqual(plan.identity, corpus.identity)
        XCTAssertEqual(plan.workPacketProjection, corpus.workProjection)
        XCTAssertEqual(plan.roundProjection, corpus.roundProjection)
        XCTAssertEqual(plan.scheduleProjection, try corpus.project())
        XCTAssertEqual(plan.nodes.map(\.sourceEntry), selected)
        XCTAssertEqual(Set(plan.nodes.map(\.targetMutationID)).count, plan.nodes.count)
        XCTAssertEqual(plan.nodes.count, 14)

        let workSourceID = try XCTUnwrap(corpus.workProjection.commands.first).source.envelope.mutationID
        let roundSourceID = try XCTUnwrap(corpus.roundProjection.commands.first).source.envelope.mutationID
        let workNode = try node(sourceID: workSourceID, in: plan)
        let roundNode = try node(sourceID: roundSourceID, in: plan)
        guard case let .workPacket(work) = workNode.payload,
              case let .roundSession(round) = roundNode.payload else {
            return XCTFail("Expected closed WorkPacket and RoundSession payloads")
        }
        XCTAssertEqual(work, corpus.workProjection.commands[0])
        XCTAssertEqual(round, corpus.roundProjection.commands[0])

        let targetWork = try plan.workPacketProjection.targetManifest(
            for: WorkPacketManifestReferenceV1(try sourceWorkManifest(corpus))
        )
        let targetRound = try plan.roundProjection.targetSession(
            for: corpus.roundProjection.commands[0].sourceRoundReference
        )
        let startedWork = try scheduleNode(sourceID: corpus.events[1].mutationID, in: plan)
        let startedRound = try scheduleNode(sourceID: corpus.events[5].mutationID, in: plan)
        guard case let .startOccurrence(targetWorkEvent, _, _) = startedWork.mutation.payload,
              case let .some(.workPacket(actualWork)) = targetWorkEvent.workInstance,
              case let .startOccurrence(targetRoundEvent, _, _) = startedRound.mutation.payload,
              case let .some(.roundSession(sessionID, revision, sessionSHA256)) = targetRoundEvent.workInstance else {
            return XCTFail("Expected historical WorkPacket and RoundSession references")
        }
        XCTAssertEqual(actualWork, try WorkPacketManifestReferenceV1(targetWork))
        XCTAssertEqual(sessionID, targetRound.sessionID)
        XCTAssertEqual(revision, targetRound.revision)
        XCTAssertEqual(sessionSHA256, targetRound.sessionSHA256)
    }

    func testCoverageIsIndependentOfReceiptStorageOrder() throws {
        let reversedCorpus = try ScheduleReplacementFixture.make(reverseStorage: true, promotions: true)
        let forwardCorpus = try ScheduleReplacementFixture.make(reverseStorage: false, promotions: true)
        let reversed = try makePlan(reversedCorpus)
        let forward = try makePlan(forwardCorpus)

        XCTAssertNotEqual(reversed.source.history.receipts, forward.source.history.receipts)
        XCTAssertEqual(reversed.nodes.map(nodeEvidence), forward.nodes.map(nodeEvidence))
        XCTAssertEqual(reversed.externalProducerObligations.map(obligationEvidence),
                       forward.externalProducerObligations.map(obligationEvidence))
        XCTAssertEqual(reversed.resultingEntityRevisions, forward.resultingEntityRevisions)
        XCTAssertEqual(reversed.nonselectedEntries, forward.nonselectedEntries)
        XCTAssertEqual(reversed.definitionBindings, forward.definitionBindings)
        XCTAssertEqual(reversed.packageBindings, forward.packageBindings)
    }

    func testEmptyAndSingleFamilyPlansRemainExplicit() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let emptyHistory = try ScheduleReplacementFixture.history(commands: [], reverseStorage: true)
        let emptySource = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: emptyHistory
        )
        let empty = try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: emptySource, identity: corpus.identity,
            definitionBindings: [], packageBindings: []
        )
        XCTAssertTrue(empty.nodes.isEmpty)
        XCTAssertTrue(empty.externalProducerObligations.isEmpty)
        XCTAssertTrue(empty.resultingEntityRevisions.isEmpty)
        XCTAssertTrue(empty.nonselectedEntries.isEmpty)

        let workCommand = try XCTUnwrap(orderedCommands(corpus).first {
            if case .applyWorkPacket = $0 { return true }
            return false
        })
        let singleHistory = try ScheduleReplacementFixture.history(
            commands: [workCommand], reverseStorage: true
        )
        let singleSource = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: singleHistory
        )
        let single = try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: singleSource, identity: corpus.identity,
            definitionBindings: [], packageBindings: []
        )
        XCTAssertEqual(single.nodes.map(\.sourceEntry), singleSource.entries)
        XCTAssertEqual(single.nodes.count, 1)
        XCTAssertTrue(single.externalProducerObligations.isEmpty)
        XCTAssertTrue(single.nonselectedEntries.isEmpty)
        XCTAssertEqual(single.resultingEntityRevisions, single.nodes[0].resultingEntityRevisions)
    }

    func testNonselectedAuthenticatedEntryAndFullSourceHistoryRemainExact() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let source = try sourceByAppendingGuidedEntry(to: corpus)
        let plan = try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings,
            packageBindings: corpus.packageBindings
        )

        XCTAssertEqual(plan.source, source)
        XCTAssertEqual(plan.source.history, source.history)
        XCTAssertEqual(plan.nodes.map(\.sourceEntry),
                       source.entries.filter { selectedFamilies.contains($0.family) })
        XCTAssertEqual(plan.nonselectedEntries,
                       source.entries.filter { !selectedFamilies.contains($0.family) })
        XCTAssertEqual(plan.nonselectedEntries.map(\.family), [.guidedSurvey])
        XCTAssertEqual(plan.nonselectedEntries[0].record,
                       try XCTUnwrap(source.entries.last).record)
        XCTAssertFalse(plan.nodes.contains {
            $0.sourceEntry.envelope.mutationID
                == plan.nonselectedEntries[0].envelope.mutationID
        })
    }

    func testExternalProducerObligationsRetainAuthenticatedSourceAndSuppliedTarget() throws {
        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        let plan = try makePlan(corpus)
        let expectedPairs: [(WorkspaceCommandV1, WorkspaceCommandV1)] =
            corpus.definitionBindings.compactMap(\.producer).map {
                (.applySurveyDefinition($0.source), .applySurveyDefinition($0.target))
            } + corpus.packageBindings.flatMap(\.producers).prefix(2).map {
                (.applyPackagePromotion($0.source), .applyPackagePromotion($0.target))
            }

        XCTAssertEqual(plan.externalProducerObligations.count, expectedPairs.count)
        for (sourceCommand, targetCommand) in expectedPairs {
            let sourceID = try ScheduleReplacementFixture.bindings(sourceCommand).mutationID
            let obligation = try XCTUnwrap(plan.externalProducerObligations.first {
                $0.sourceEnvelope.mutationID == sourceID
            })
            XCTAssertEqual(obligation.sourceEnvelope.command, sourceCommand)
            XCTAssertEqual(obligation.targetCommand, targetCommand)
            XCTAssertEqual(obligation.targetMutationID,
                           try ScheduleReplacementFixture.bindings(targetCommand).mutationID)
            XCTAssertEqual(obligation.sourceRecord.envelopeData,
                           try obligation.sourceEnvelope.canonicalData())
            XCTAssertEqual(obligation.sourceRecord.receiptData,
                           try obligation.sourceReceipt.canonicalData())
            XCTAssertTrue(corpus.source.history.receipts.contains(obligation.sourceRecord))
        }
    }

    func testRejectsMissingForeignAndTargetCollisionProducerBindings() throws {
        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: [], packageBindings: corpus.packageBindings
        ))

        let package = corpus.packageBindings[0]
        let authentic = try XCTUnwrap(package.producers.first)
        let foreignSource = try ScheduleReplacementFixture.promotion(
            workspaceID: WorkspaceID(rawValue: ScheduleReplacementFixture.id(9_100)),
            package: package.source, slot: 9_110,
            mutationID: ScheduleReplacementFixture.mutation(9_120)
        )
        let foreignBinding = ScheduleReplacementCommandProjectionV1.PackageBinding(
            source: package.source, target: package.target,
            producers: [.init(source: foreignSource, target: authentic.target)]
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings, packageBindings: [foreignBinding]
        ))

        let selectedTargetID = try corpus.identity.destinationWorkPacketMutationID(
            for: corpus.workProjection.commands[0].source.envelope.mutationID
        )
        let collidingTarget = try ScheduleReplacementFixture.promotion(
            workspaceID: corpus.targetWorkspace, package: package.target, slot: 9_130,
            mutationID: selectedTargetID
        )
        let collidingPairs = [
            ScheduleReplacementCommandProjectionV1.PackageProducerPair(
                source: authentic.source, target: collidingTarget
            )
        ] + Array(package.producers.dropFirst())
        let collidingBinding = ScheduleReplacementCommandProjectionV1.PackageBinding(
            source: package.source, target: package.target, producers: collidingPairs
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings, packageBindings: [collidingBinding]
        ))

        let conflictingTarget = try ScheduleReplacementFixture.promotion(
            workspaceID: corpus.targetWorkspace, package: package.target, slot: 9_140,
            mutationID: authentic.target.mutationID
        )
        XCTAssertNotEqual(conflictingTarget, authentic.target)
        let conflictingBinding = ScheduleReplacementCommandProjectionV1.PackageBinding(
            source: package.source, target: package.target,
            producers: [authentic, .init(source: authentic.source, target: conflictingTarget)]
                + Array(package.producers.dropFirst())
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings, packageBindings: [conflictingBinding]
        ))
    }

    func testAtomicGenerationImagesAndFrontierEvidenceAreExact() throws {
        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        let plan = try makePlan(corpus)
        for node in plan.nodes {
            XCTAssertEqual(node.postImages, try targetPostImages(node.targetCommand))
            XCTAssertEqual(node.expectedEntityRevisions.map(\.identity),
                           node.expectedEntityRevisions.map(\.identity).sorted {
                               $0.stableKey < $1.stableKey
                           })
            XCTAssertEqual(node.resultingEntityRevisions.map(\.identity),
                           node.resultingEntityRevisions.map(\.identity).sorted {
                               $0.stableKey < $1.stableKey
                           })
        }

        let work = try node(
            sourceID: corpus.workProjection.commands[0].source.envelope.mutationID,
            in: plan
        )
        let round = try node(
            sourceID: corpus.roundProjection.commands[0].source.envelope.mutationID,
            in: plan
        )
        let generated1 = try node(sourceID: corpus.events[0].mutationID, in: plan)
        let startedWork = try node(sourceID: corpus.events[1].mutationID, in: plan)
        let workImage = try XCTUnwrap(work.postImages.first)
        let roundImage = try XCTUnwrap(round.postImages.first)
        let generated1Image = try XCTUnwrap(generated1.postImages.first)
        let startedWorkImage = try XCTUnwrap(startedWork.postImages.first)
        let generated1Physical = try generated1Image.identity
        let generated1Concurrency = try generated1Image.concurrencyIdentity
        let startedWorkPhysical = try startedWorkImage.identity
        let startedWorkConcurrency = try startedWorkImage.concurrencyIdentity

        XCTAssertEqual(work.expectedEntityRevisions, [
            .init(identity: try workImage.concurrencyIdentity, revision: 0),
        ])
        XCTAssertEqual(round.expectedEntityRevisions, [
            .init(identity: try roundImage.concurrencyIdentity, revision: 0),
        ])
        XCTAssertEqual(generated1.expectedEntityRevisions, [
            .init(identity: generated1Concurrency, revision: 0),
        ])
        XCTAssertEqual(generated1Physical, generated1Concurrency)
        XCTAssertEqual(revision(generated1Physical, in: generated1.resultingEntityRevisions), 1)
        XCTAssertEqual(generated1Image.revision, 1)
        XCTAssertEqual(startedWork.expectedEntityRevisions, [
            .init(identity: startedWorkConcurrency, revision: 1),
        ])
        XCTAssertEqual(startedWorkConcurrency, generated1Physical)
        XCTAssertNotEqual(startedWorkPhysical, startedWorkConcurrency)
        XCTAssertEqual(revision(startedWorkPhysical, in: startedWork.resultingEntityRevisions), 2)
        XCTAssertEqual(revision(startedWorkConcurrency, in: startedWork.resultingEntityRevisions), 2)

        let generation = try node(sourceID: corpus.scheduleMutations[10].mutationID, in: plan)
        guard case let .schedule(command) = generation.payload,
              case .generateOccurrences = command.mutation.payload else {
            return XCTFail("Expected one atomic generation node")
        }
        XCTAssertEqual(generation.postImages.count, 2)
        XCTAssertEqual(Set(try generation.postImages.map { try $0.identity }).count, 2)
        XCTAssertEqual(generation.expectedEntityRevisions, try generation.postImages.map {
            WorkspaceEntityRevisionV1(identity: try $0.concurrencyIdentity, revision: 0)
        }.sorted { $0.identity.stableKey < $1.identity.stableKey })
        let generatedIdentities = Set(try generation.postImages.flatMap {
            [try $0.identity, try $0.concurrencyIdentity]
        })
        XCTAssertTrue(generatedIdentities.isSubset(
            of: Set(generation.resultingEntityRevisions.map(\.identity))
        ))
        for image in generation.postImages {
            XCTAssertEqual(image.revision, 1)
            XCTAssertEqual(revision(try image.identity, in: generation.resultingEntityRevisions), 1)
            XCTAssertEqual(revision(try image.concurrencyIdentity,
                                    in: generation.resultingEntityRevisions), 1)
        }
        XCTAssertEqual(revision(try workImage.identity,
                                in: generation.resultingEntityRevisions), workImage.revision)
        XCTAssertEqual(revision(try workImage.concurrencyIdentity,
                                in: generation.resultingEntityRevisions), workImage.revision)
        XCTAssertEqual(revision(try roundImage.identity,
                                in: generation.resultingEntityRevisions), roundImage.revision)
        XCTAssertEqual(revision(try roundImage.concurrencyIdentity,
                                in: generation.resultingEntityRevisions), roundImage.revision)
        XCTAssertEqual(revision(generated1Physical,
                                in: generation.resultingEntityRevisions), 2)
        XCTAssertEqual(revision(startedWorkPhysical,
                                in: generation.resultingEntityRevisions), 3)
        XCTAssertEqual(plan.resultingEntityRevisions,
                       try XCTUnwrap(plan.nodes.last).resultingEntityRevisions)
        XCTAssertEqual(plan.resultingEntityRevisions.map(\.identity),
                       plan.resultingEntityRevisions.map(\.identity).sorted {
                           $0.stableKey < $1.stableKey
                       })
    }

    func testDependenciesMapExactProducersAndRejectIncompleteExternalProducerCoverage() throws {
        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        let plan = try makePlan(corpus)
        for node in plan.nodes {
            XCTAssertEqual(Set(node.dependencies.map(\.sourceMutationID)).count,
                           node.dependencies.count)
            XCTAssertFalse(node.dependencies.contains {
                $0.sourceMutationID == node.sourceEntry.envelope.mutationID
            })
            for dependency in node.dependencies {
                XCTAssertEqual(dependency.sourceWorkspaceID, corpus.sourceWorkspace)
                XCTAssertEqual(dependency.targetWorkspaceID, corpus.targetWorkspace)
                XCTAssertEqual(dependency.targetMutationID,
                               try corpus.targetMutationID(for: dependency.sourceMutationID))
                XCTAssertEqual(dependency.reasons, [.semanticReference])
                let producerRevision = try sourceRevision(
                    dependency.sourceMutationID, in: corpus.source
                )
                XCTAssertLessThan(producerRevision,
                                  node.sourceEntry.receipt.resultingRevision.workspaceRevision)
            }
        }

        let lateOnly = ScheduleReplacementCommandProjectionV1.PackageBinding(
            source: corpus.packageBindings[0].source,
            target: corpus.packageBindings[0].target,
            producers: [try XCTUnwrap(corpus.packageBindings[0].producers.last)]
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings, packageBindings: [lateOnly]
        )) { error in
            XCTAssertEqual(error as? ScheduleReplacementCommandProjectionFailureV1,
                           .missingDependency)
        }
    }

    func testGenuineCausationAndReversalMetadataMapToOneSelectedPredecessor() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let history = try semanticPairHistory(corpus: corpus, targetIndex: 0, reversalIndex: 1)
        let source = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: history
        )
        let plan = try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: source, identity: corpus.identity,
            definitionBindings: [], packageBindings: []
        )

        XCTAssertEqual(plan.nodes.count, 2)
        let predecessor = plan.nodes[0]
        let reversal = plan.nodes[1]
        XCTAssertEqual(reversal.dependencies.count, 1)
        XCTAssertEqual(reversal.dependencies[0].sourceMutationID,
                       predecessor.sourceEntry.envelope.mutationID)
        XCTAssertEqual(reversal.dependencies[0].targetMutationID,
                       predecessor.targetMutationID)
        XCTAssertEqual(reversal.dependencies[0].reasons, [.causation, .reversal])
        XCTAssertEqual(reversal.sourceEntry.envelope.causationMutationID,
                       predecessor.sourceEntry.envelope.mutationID)
        XCTAssertEqual(reversal.sourceEntry.receipt.reversesMutationID,
                       predecessor.sourceEntry.envelope.mutationID)
    }

    func testRejectsGenuineForwardCausationAndReversalPair() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let history = try semanticPairHistory(corpus: corpus, targetIndex: 1, reversalIndex: 0)
        let source = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: history
        )
        XCTAssertEqual(source.entries.map(\.family), [.workPacket, .roundSession])
        XCTAssertEqual(source.entries[0].envelope.causationMutationID,
                       source.entries[1].envelope.mutationID)
        XCTAssertEqual(source.entries[0].receipt.reversesMutationID,
                       source.entries[1].envelope.mutationID)
        XCTAssertNotNil(source.entries[1].record.reversalBasisData)
        XCTAssertNotNil(source.entries[0].record.semanticReversalData)
        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: source, identity: corpus.identity,
            definitionBindings: [], packageBindings: []
        )) { error in
            XCTAssertEqual(error as? ReferenceOwnerReplacementCommandPlanFailureV1, .invalidOrder)
        }
    }

    func testRejectsAuthenticatedCausationToNonselectedGuidedOwner() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let source = try guidedCausationSource(corpus: corpus)
        XCTAssertEqual(source.entries.map(\.family), [.guidedSurvey, .workPacket])
        XCTAssertEqual(source.entries[1].envelope.causationMutationID,
                       source.entries[0].envelope.mutationID)
        XCTAssertNil(source.entries[1].receipt.reversesMutationID)

        XCTAssertThrowsError(try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: source, identity: corpus.identity,
            definitionBindings: [], packageBindings: []
        )) { error in
            XCTAssertEqual(error as? ReferenceOwnerReplacementCommandPlanFailureV1,
                           .missingDependency)
        }
    }
}

private extension V23ReferenceOwnerReplacementCommandPlanTests {
    var selectedFamilies: Set<ReferenceOwnerReplacementSourceV1.Family> {
        [.workPacket, .roundSession, .schedule]
    }

    func makePlan(_ corpus: ScheduleReplacementFixture.Corpus) throws
        -> ReferenceOwnerReplacementCommandPlanV1.Plan {
        try ReferenceOwnerReplacementCommandPlanV1.plan(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings,
            packageBindings: corpus.packageBindings
        )
    }

    func orderedCommands(_ corpus: ScheduleReplacementFixture.Corpus) throws
        -> [WorkspaceCommandV1] {
        try corpus.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }.sorted {
            $0.expectedRevision.workspaceRevision < $1.expectedRevision.workspaceRevision
        }.map(\.command)
    }

    func node(sourceID: MutationIDV1,
              in plan: ReferenceOwnerReplacementCommandPlanV1.Plan) throws
        -> ReferenceOwnerReplacementCommandPlanV1.Node {
        try XCTUnwrap(plan.nodes.first { $0.sourceEntry.envelope.mutationID == sourceID })
    }

    func scheduleNode(sourceID: MutationIDV1,
                      in plan: ReferenceOwnerReplacementCommandPlanV1.Plan) throws
        -> ScheduleReplacementCommandProjectionV1.Command {
        let value = try node(sourceID: sourceID, in: plan)
        guard case let .schedule(command) = value.payload else {
            throw ScheduleReplacementCommandProjectionFailureV1.invalidSource
        }
        return command
    }

    func sourceWorkManifest(_ corpus: ScheduleReplacementFixture.Corpus) throws
        -> WorkPacketManifestV1 {
        guard case let .appendManifest(value) = try corpus.workProjection.commands[0]
            .sourceWorkMutation.postImage else {
            throw WorkPacketReplacementCommandProjectionFailureV1.invalidSource
        }
        return value
    }

    func nodeEvidence(_ node: ReferenceOwnerReplacementCommandPlanV1.Node)
        -> String {
        let dependencies = node.dependencies.map {
            "\($0.sourceWorkspaceID.rawValue.uuidString):\($0.sourceMutationID.rawValue.uuidString):" +
            "\($0.targetWorkspaceID.rawValue.uuidString):\($0.targetMutationID.rawValue.uuidString):" +
            $0.reasons.map(\.rawValue).joined(separator: ",")
        }.joined(separator: "|")
        return "\(node.sourceEntry.envelope.mutationID.rawValue.uuidString):" +
            "\(node.targetMutationID.rawValue.uuidString):\(dependencies):" +
            "\(node.expectedEntityRevisions):\(node.resultingEntityRevisions)"
    }

    func obligationEvidence(
        _ value: ReferenceOwnerReplacementCommandPlanV1.ExternalProducerObligation
    ) -> String {
        "\(value.sourceEnvelope.mutationID.rawValue.uuidString):" +
        "\(value.targetMutationID.rawValue.uuidString):" +
        "\(value.sourceRecord.envelopeData.base64EncodedString()):" +
        "\(value.sourceRecord.receiptData.base64EncodedString())"
    }

    func targetPostImages(_ command: WorkspaceCommandV1) throws -> [MutationPostImageV1] {
        try ScheduleReplacementFixture.bindings(command).images
    }

    func sourceRevision(_ mutationID: MutationIDV1,
                        in source: ReferenceOwnerReplacementSourceV1.Source) throws -> UInt64 {
        if let entry = source.entries.first(where: { $0.envelope.mutationID == mutationID }) {
            return entry.receipt.resultingRevision.workspaceRevision
        }
        for record in source.history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard envelope.mutationID == mutationID,
                  envelope.workspaceID == source.workspaceID else { continue }
            return try MutationReceiptV1.decodeCanonical(from: record.receiptData)
                .resultingRevision.workspaceRevision
        }
        throw ScheduleReplacementCommandProjectionFailureV1.missingDependency
    }

    func revision(_ identity: WorkspaceEntityIdentityV1,
                  in rows: [WorkspaceEntityRevisionV1]) -> UInt64? {
        let matches = rows.filter { $0.identity == identity }
        guard matches.count == 1 else { return nil }
        return matches[0].revision
    }

    func semanticPairHistory(corpus: ScheduleReplacementFixture.Corpus,
                             targetIndex: Int, reversalIndex: Int) throws
        -> MutationHistorySnapshotV1 {
        let selectedCommands = try orderedCommands(corpus).filter {
            switch $0 {
            case .applyWorkPacket, .applyRoundSession: return true
            default: return false
            }
        }
        XCTAssertEqual(selectedCommands.count, 2)
        XCTAssertNotEqual(targetIndex, reversalIndex)
        let bindings = try selectedCommands.map(ScheduleReplacementFixture.bindings)
        let expected = try bindings.enumerated().map { offset, binding in
            try WorkspaceExpectedRevisionV1(
                workspaceID: binding.workspaceID,
                generationID: ScheduleReplacementFixture.generationID,
                writerInstanceID: ScheduleReplacementFixture.writerID,
                workspaceRevision: UInt64(offset), entityRevisions: binding.expected
            )
        }
        let requests = try zip(selectedCommands, expected).map { command, expected in
            WorkspaceMutationRequestV1(
                mutationID: try ScheduleReplacementFixture.bindings(command).mutationID,
                expectedRevision: expected, command: command
            )
        }
        let replica = try WorkspaceReplicaIdentityV1(
            workspaceID: corpus.sourceWorkspace,
            replicaID: ScheduleReplacementFixture.replicaID
        )
        let receiptIdentities = selectedCommands.indices.map {
            MutationReceiptIdentityV1(
                workspaceID: corpus.sourceWorkspace,
                replicaID: ScheduleReplacementFixture.replicaID,
                localSequence: UInt64($0 + 1)
            )
        }
        let targetBinding = bindings[targetIndex]
        let plan = try SemanticReversalPlanV1(
            mutationID: targetBinding.mutationID,
            commandKind: selectedCommands[targetIndex].kind,
            expectedRevision: expected[targetIndex],
            prospectiveTargets: try targetBinding.images.map { try $0.identity },
            requiredSemanticValues: [.init(key: "reference", value: "before")],
            contentReferences: [], dependencyGraph: [], conflicts: [],
            compensatingCommands: [selectedCommands[reversalIndex]]
        )
        let basis = try ReversalBasisV1(
            targetMutationID: targetBinding.mutationID,
            targetReceiptIdentity: receiptIdentities[targetIndex], plan: plan
        )
        let execution = try SemanticReversalExecutionV1(
            targetMutationID: targetBinding.mutationID,
            targetReceiptIdentity: receiptIdentities[targetIndex],
            reversalBasisSHA256: basis.canonicalSHA256(), planDigest: basis.planDigest,
            compensatingMutationIDs: [bindings[reversalIndex].mutationID]
        )
        let replay = try SemanticReversalReplayIdentityV1(
            request: requests[reversalIndex], identity: replica,
            targetMutationID: targetBinding.mutationID, planDigest: basis.planDigest,
            compensatingMutationIDs: [bindings[reversalIndex].mutationID]
        ).canonicalSHA256()

        var records: [MutationHistoryReceiptRecordV1] = []
        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for index in selectedCommands.indices {
            let isTarget = index == targetIndex
            let isReversal = index == reversalIndex
            let envelope = try MutationEnvelopeV1(
                request: requests[index], identity: replica,
                sourceKind: isReversal ? .semanticReversal : .localUser,
                causationMutationID: isReversal ? targetBinding.mutationID : nil,
                reversalPlanDigest: isTarget ? basis.planDigest : nil,
                semanticReversalReplayIdentitySHA256: isReversal ? replay : nil,
                semanticReversalExecution: isReversal ? execution : nil
            )
            for image in bindings[index].images {
                terminal[try image.identity] = image.revision
                terminal[try image.concurrencyIdentity] = image.revision
            }
            let resulting = try MutationPortableExpectedRevisionV1(
                WorkspaceExpectedRevisionV1(
                    workspaceID: corpus.sourceWorkspace,
                    generationID: ScheduleReplacementFixture.generationID,
                    writerInstanceID: ScheduleReplacementFixture.writerID,
                    workspaceRevision: UInt64(index + 1),
                    entityRevisions: try bindings[index].images.map {
                        WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
                    }
                )
            )
            let receipt = try MutationReceiptV1(
                identity: receiptIdentities[index], envelope: envelope,
                resultingRevision: resulting, postImages: bindings[index].images,
                reversesMutationID: isReversal ? targetBinding.mutationID : nil,
                committedAt: ScheduleReplacementFixture.now.addingTimeInterval(Double(index + 1))
            )
            let semantic: SemanticReversalReceiptV1?
            if isReversal {
                semantic = try SemanticReversalReceiptV1(
                    reversalReceiptIdentity: receipt.identity,
                    reversesMutationID: targetBinding.mutationID,
                    targetReceiptIdentity: receiptIdentities[targetIndex],
                    reversalBasisSHA256: basis.canonicalSHA256(), planDigest: basis.planDigest,
                    compensatingMutationIDs: [bindings[reversalIndex].mutationID],
                    resultingRevision: receipt.resultingRevision
                )
            } else {
                semantic = nil
            }
            records.append(.init(
                envelopeData: try envelope.canonicalData(), receiptData: try receipt.canonicalData(),
                reversalBasisData: isTarget ? try basis.canonicalData() : nil,
                semanticReversalData: try semantic?.canonicalData()
            ))
        }
        let history = MutationHistorySnapshotV1(
            workspaceRevision: UInt64(records.count), lastLocalSequence: UInt64(records.count),
            receipts: Array(records.reversed()), quarantines: [],
            entityRevisions: terminal.map { .init(identity: $0.key, revision: $0.value) }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        return history
    }

    func sourceByAppendingGuidedEntry(to corpus: ScheduleReplacementFixture.Corpus) throws
        -> ReferenceOwnerReplacementSourceV1.Source {
        let mutationID = try ScheduleReplacementFixture.mutation(9_700)
        let provisional = try C26SurveySessionTestSupport.provisional(
            workspaceID: corpus.sourceWorkspace, slot: 9_710, mutationID: mutationID
        )
        let mutation = try SurveySessionMutationV1(
            workspaceID: corpus.sourceWorkspace, mutationID: mutationID,
            payload: .applyProvisionalSubject(provisional)
        )
        let command = WorkspaceCommandV1.applySurveySession(mutation)
        let identities = try mutation.concurrencyIdentities
        let images = try mutation.mutationPostImages
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: corpus.sourceWorkspace,
            generationID: ScheduleReplacementFixture.generationID,
            writerInstanceID: ScheduleReplacementFixture.writerID,
            workspaceRevision: corpus.history.workspaceRevision,
            entityRevisions: try identities.map {
                WorkspaceEntityRevisionV1(
                    identity: $0, revision: try mutation.expectedRevision(for: $0)
                )
            }
        )
        let envelope = try MutationEnvelopeV1(
            request: .init(mutationID: mutationID, expectedRevision: expected, command: command),
            identity: .init(
                workspaceID: corpus.sourceWorkspace,
                replicaID: ScheduleReplacementFixture.replicaID
            )
        )
        let resulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: corpus.sourceWorkspace,
                generationID: ScheduleReplacementFixture.generationID,
                writerInstanceID: ScheduleReplacementFixture.writerID,
                workspaceRevision: corpus.history.workspaceRevision + 1,
                entityRevisions: try images.map {
                    WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
                }
            )
        )
        let receipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: corpus.sourceWorkspace,
                replicaID: ScheduleReplacementFixture.replicaID,
                localSequence: corpus.history.lastLocalSequence + 1
            ),
            envelope: envelope, resultingRevision: resulting, postImages: images,
            committedAt: ScheduleReplacementFixture.now.addingTimeInterval(
                Double(corpus.history.lastLocalSequence + 1)
            )
        )
        let record = MutationHistoryReceiptRecordV1(
            envelopeData: try envelope.canonicalData(),
            receiptData: try receipt.canonicalData(),
            reversalBasisData: nil, semanticReversalData: nil
        )
        var terminal = Dictionary(uniqueKeysWithValues: corpus.history.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        for image in images {
            terminal[try image.identity] = image.revision
            terminal[try image.concurrencyIdentity] = image.revision
        }
        let history = MutationHistorySnapshotV1(
            workspaceRevision: corpus.history.workspaceRevision + 1,
            lastLocalSequence: corpus.history.lastLocalSequence + 1,
            receipts: corpus.history.receipts + [record], quarantines: corpus.history.quarantines,
            entityRevisions: terminal.map { .init(identity: $0.key, revision: $0.value) }
                .sorted { $0.identity.stableKey < $1.identity.stableKey }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        return try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: history
        )
    }

    func guidedCausationSource(corpus: ScheduleReplacementFixture.Corpus) throws
        -> ReferenceOwnerReplacementSourceV1.Source {
        let guidedID = try ScheduleReplacementFixture.mutation(9_800)
        let provisional = try C26SurveySessionTestSupport.provisional(
            workspaceID: corpus.sourceWorkspace, slot: 9_810, mutationID: guidedID
        )
        let guidedMutation = try SurveySessionMutationV1(
            workspaceID: corpus.sourceWorkspace, mutationID: guidedID,
            payload: .applyProvisionalSubject(provisional)
        )
        let guidedCommand = WorkspaceCommandV1.applySurveySession(guidedMutation)
        let workCommand = try XCTUnwrap(orderedCommands(corpus).first {
            if case .applyWorkPacket = $0 { return true }
            return false
        })
        let workBinding = try ScheduleReplacementFixture.bindings(workCommand)
        let guidedIdentities = try guidedMutation.concurrencyIdentities
        let guidedImages = try guidedMutation.mutationPostImages
        let allCommands = [guidedCommand, workCommand]
        let mutationIDs = [guidedID, workBinding.mutationID]
        let expectedRows = [
            try guidedIdentities.map {
                WorkspaceEntityRevisionV1(
                    identity: $0, revision: try guidedMutation.expectedRevision(for: $0)
                )
            },
            workBinding.expected,
        ]
        let images = [guidedImages, workBinding.images]
        let expected = try allCommands.indices.map { index in
            try WorkspaceExpectedRevisionV1(
                workspaceID: corpus.sourceWorkspace,
                generationID: ScheduleReplacementFixture.generationID,
                writerInstanceID: ScheduleReplacementFixture.writerID,
                workspaceRevision: UInt64(index), entityRevisions: expectedRows[index]
            )
        }
        let requests = allCommands.indices.map { index in
            WorkspaceMutationRequestV1(
                mutationID: mutationIDs[index], expectedRevision: expected[index],
                command: allCommands[index]
            )
        }
        let replica = try WorkspaceReplicaIdentityV1(
            workspaceID: corpus.sourceWorkspace,
            replicaID: ScheduleReplacementFixture.replicaID
        )
        let identities = allCommands.indices.map {
            MutationReceiptIdentityV1(
                workspaceID: corpus.sourceWorkspace,
                replicaID: ScheduleReplacementFixture.replicaID,
                localSequence: UInt64($0 + 1)
            )
        }
        let plan = try SemanticReversalPlanV1(
            mutationID: guidedID, commandKind: guidedCommand.kind,
            expectedRevision: expected[0],
            prospectiveTargets: try guidedImages.map { try $0.identity },
            requiredSemanticValues: [.init(key: "guided", value: "before")],
            contentReferences: [], dependencyGraph: [], conflicts: [],
            compensatingCommands: [workCommand]
        )
        let basis = try ReversalBasisV1(
            targetMutationID: guidedID, targetReceiptIdentity: identities[0], plan: plan
        )
        let execution = try SemanticReversalExecutionV1(
            targetMutationID: guidedID, targetReceiptIdentity: identities[0],
            reversalBasisSHA256: basis.canonicalSHA256(), planDigest: basis.planDigest,
            compensatingMutationIDs: [workBinding.mutationID]
        )
        let replay = try SemanticReversalReplayIdentityV1(
            request: requests[1], identity: replica, targetMutationID: guidedID,
            planDigest: basis.planDigest,
            compensatingMutationIDs: [workBinding.mutationID]
        ).canonicalSHA256()
        let envelopes = try [
            MutationEnvelopeV1(
                request: requests[0], identity: replica,
                reversalPlanDigest: basis.planDigest
            ),
            MutationEnvelopeV1(
                request: requests[1], identity: replica,
                sourceKind: .semanticReversal, causationMutationID: guidedID,
                semanticReversalReplayIdentitySHA256: replay,
                semanticReversalExecution: execution
            ),
        ]
        var records: [MutationHistoryReceiptRecordV1] = []
        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for index in allCommands.indices {
            for image in images[index] {
                terminal[try image.identity] = image.revision
                terminal[try image.concurrencyIdentity] = image.revision
            }
            let resulting = try MutationPortableExpectedRevisionV1(
                WorkspaceExpectedRevisionV1(
                    workspaceID: corpus.sourceWorkspace,
                    generationID: ScheduleReplacementFixture.generationID,
                    writerInstanceID: ScheduleReplacementFixture.writerID,
                    workspaceRevision: UInt64(index + 1),
                    entityRevisions: try images[index].map {
                        WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
                    }
                )
            )
            let receipt = try MutationReceiptV1(
                identity: identities[index], envelope: envelopes[index],
                resultingRevision: resulting, postImages: images[index],
                committedAt: ScheduleReplacementFixture.now.addingTimeInterval(Double(index + 1))
            )
            records.append(.init(
                envelopeData: try envelopes[index].canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: index == 0 ? try basis.canonicalData() : nil,
                semanticReversalData: nil
            ))
        }
        let history = MutationHistorySnapshotV1(
            workspaceRevision: UInt64(records.count),
            lastLocalSequence: UInt64(records.count), receipts: Array(records.reversed()),
            quarantines: [],
            entityRevisions: terminal.map { .init(identity: $0.key, revision: $0.value) }
                .sorted { $0.identity.stableKey < $1.identity.stableKey }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        return try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: history
        )
    }
}

private extension WorkPacketReplacementCommandProjectionV1.Command {
    var sourceWorkMutation: WorkPacketMutationV1 {
        get throws {
            guard case let .applyWorkPacket(value) = source.envelope.command else {
                throw WorkPacketReplacementCommandProjectionFailureV1.invalidSource
            }
            return value
        }
    }
}

private extension RoundSessionReplacementCommandProjectionV1.Command {
    var sourceRoundReference: RoundSessionReferenceV1 {
        get throws {
            guard case let .applyRoundSession(value) = source.envelope.command else {
                throw RoundSessionReplacementCommandProjectionFailureV1.invalidSource
            }
            return try value.session.reference
        }
    }
}
