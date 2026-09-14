import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23ScheduleReplacementCommandProjectionTests: XCTestCase {
    func testProjectsAllSixPayloadsWithExactGraphAndAtomicGeneration() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let projection = try corpus.project()

        XCTAssertEqual(projection.source, corpus.source)
        XCTAssertEqual(projection.identity, corpus.identity)
        XCTAssertEqual(projection.commands.count, corpus.scheduleMutations.count)
        XCTAssertEqual(projection.commands.map(\.sourceEntry.record), corpus.scheduleEntries.map(\.record))
        XCTAssertEqual(projection.commands.flatMap(\.postImages),
                       try projection.commands.flatMap { try $0.mutation.mutationPostImages })

        var cases = Set<String>()
        for command in projection.commands {
            switch command.mutation.payload {
            case .appendRelease: cases.insert("release")
            case .appendExceptionCalendarRelease: cases.insert("calendar")
            case .appendOverrideEvent: cases.insert("override")
            case .appendOccurrenceEvent: cases.insert("occurrence")
            case .startOccurrence: cases.insert("start")
            case let .generateOccurrences(_, plan, events):
                cases.insert("generation")
                XCTAssertEqual(events.count, 2)
                XCTAssertEqual(Set(events.map(\.mutationID)), Set([command.mutation.mutationID]))
                XCTAssertEqual(Set(events.map(\.occurrenceID)), Set(plan.candidates.map(\.occurrenceID)))
                XCTAssertEqual(command.postImages.count, 2)
                for event in events {
                    let candidate = try XCTUnwrap(plan.candidates.first { $0.occurrenceID == event.occurrenceID })
                    XCTAssertEqual(candidate.nominalBasis, event.nominalBasis)
                    XCTAssertEqual(candidate.effectiveBasis, event.effectiveBasis)
                    XCTAssertEqual(candidate.predecessorOccurrenceID, event.identityPredecessorOccurrenceID)
                    XCTAssertEqual(candidate.completionEventSHA256, event.identityCompletionEventSHA256)
                }
            }
            XCTAssertEqual(command.mutation.workspaceID, corpus.targetWorkspace)
            XCTAssertEqual(command.sourceDependencyMutationIDs.sorted(by: ScheduleReplacementFixture.less),
                           command.sourceDependencyMutationIDs)
            XCTAssertEqual(command.sourceDependencyMutationIDs,
                           try corpus.expectedDependencies(for: command.sourceEntry.envelope.mutationID))
            XCTAssertEqual(command.targetDependencyMutationIDs,
                           try command.sourceDependencyMutationIDs.map {
                               try corpus.targetMutationID(for: $0)
                           })
        }
        XCTAssertEqual(cases, ["release", "calendar", "override", "occurrence", "start", "generation"])
    }

    func testPreservesLiteralFieldsAndRebindsWorkPacketAndRoundReferences() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let projection = try corpus.project()
        let targetEvents = projection.commands.flatMap { command -> [OccurrenceHistoryEventV1] in
            switch command.mutation.payload {
            case let .appendOccurrenceEvent(event, _, _), let .startOccurrence(event, _, _): return [event]
            case let .generateOccurrences(_, _, events): return events
            default: return []
            }
        }
        let started = targetEvents.filter { $0.action == .start }
        XCTAssertEqual(started.count, 2)
        XCTAssertTrue(started.contains { if case .workPacket = $0.workInstance { return true }; return false })
        XCTAssertTrue(started.contains { if case .roundSession = $0.workInstance { return true }; return false })

        for sourceEvent in corpus.events {
            let target = try projection.targetEvent(for: sourceEvent)
            XCTAssertEqual(target.eventID, sourceEvent.eventID)
            if let predecessorID = sourceEvent.identityPredecessorOccurrenceID,
               let completionSHA = sourceEvent.identityCompletionEventSHA256 {
                let sourceAnchor = try XCTUnwrap(corpus.events.first {
                    $0.occurrenceID == predecessorID && $0.eventSHA256 == completionSHA
                })
                let targetAnchor = try projection.targetEvent(for: sourceAnchor)
                let expectedID = try OccurrenceIDV1(
                    scheduleDefinitionID: target.scheduleRelease.scheduleDefinitionID,
                    identityNamespaceID: target.scheduleRelease.occurrenceIdentityNamespaceID,
                    nominalKey: sourceEvent.nominalBasis.nominalKey,
                    predecessorOccurrenceID: targetAnchor.occurrenceID,
                    completionEventSHA256: targetAnchor.eventSHA256
                )
                XCTAssertEqual(target.occurrenceID, expectedID)
                XCTAssertEqual(target.identityPredecessorOccurrenceID, targetAnchor.occurrenceID)
                XCTAssertEqual(target.identityCompletionEventSHA256, targetAnchor.eventSHA256)
            } else {
                XCTAssertEqual(target.occurrenceID, sourceEvent.occurrenceID)
                XCTAssertNil(target.identityPredecessorOccurrenceID)
                XCTAssertNil(target.identityCompletionEventSHA256)
            }
            XCTAssertEqual(target.nominalBasis.timeBasisSHA256, target.scheduleRelease.timeBasisSHA256)
            XCTAssertEqual(target.effectiveBasis.timeBasisSHA256, target.scheduleRelease.timeBasisSHA256)
            XCTAssertNotEqual(target.nominalBasis.timeBasisSHA256, sourceEvent.nominalBasis.timeBasisSHA256)
            ScheduleReplacementFixture.assertBasisLiterals(sourceEvent.nominalBasis, target.nominalBasis)
            ScheduleReplacementFixture.assertBasisLiterals(sourceEvent.effectiveBasis, target.effectiveBasis)
            let calendar = try projection.targetCalendar(for: corpus.calendars[0].reference)
            XCTAssertEqual(target.nominalBasis.adjustmentProvenanceSHA256, calendar.releaseSHA256)
            XCTAssertEqual(target.effectiveBasis.adjustmentProvenanceSHA256, calendar.releaseSHA256)
            XCTAssertNotEqual(target.nominalBasis.adjustmentProvenanceSHA256,
                              sourceEvent.nominalBasis.adjustmentProvenanceSHA256)
            XCTAssertEqual(target.completedAt, sourceEvent.completedAt)
            XCTAssertEqual(target.recordedAt, sourceEvent.recordedAt)
            XCTAssertEqual(target.recordedBy.snapshotID, sourceEvent.recordedBy.snapshotID)
            XCTAssertEqual(target.recordedBy.displayNameAtTime, sourceEvent.recordedBy.displayNameAtTime)
            XCTAssertEqual(target.recordedBy.responsibility, sourceEvent.recordedBy.responsibility)
            XCTAssertEqual(target.recordedBy.capturedAt, sourceEvent.recordedBy.capturedAt)
            XCTAssertEqual(target.recordedBy.actor.actorReferenceID,
                           sourceEvent.recordedBy.actor.actorReferenceID)
            XCTAssertEqual(target.recordedBy.actor.partyID, sourceEvent.recordedBy.actor.partyID)
            XCTAssertEqual(target.recordedBy.actor.displayName, sourceEvent.recordedBy.actor.displayName)
            switch sourceEvent.workInstance {
            case let .workPacket(reference):
                let manifest = try corpus.workProjection.targetManifest(for: reference)
                XCTAssertEqual(target.workInstance, .workPacket(try WorkPacketManifestReferenceV1(manifest)))
            case let .roundSession(id, revision, digest):
                let session = try corpus.roundProjection.targetSession(for: .init(
                    workspaceID: corpus.sourceWorkspace, sessionID: id,
                    revision: revision, sessionSHA256: digest))
                XCTAssertEqual(target.workInstance, .roundSession(sessionID: session.sessionID,
                    revision: session.revision, sessionSHA256: session.sessionSHA256))
            case nil: XCTAssertNil(target.workInstance)
            }
            XCTAssertEqual(target.recordedBy.workspaceID, corpus.targetWorkspace)
        }

        let targetForward = try projection.targetOverride(for: corpus.forwardOverride.reference)
        XCTAssertEqual(targetForward.target, corpus.forwardOverride.target)
        XCTAssertEqual(targetForward.reasonCode, corpus.forwardOverride.reasonCode)
        XCTAssertEqual(targetForward.recordedAt, corpus.forwardOverride.recordedAt)
    }

    func testExactHistoricalLookupsIncludeOldReleaseCalendarOverrideAndOccurrenceAnchor() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let projection = try corpus.project()

        let firstRelease = try projection.targetRelease(for: try .init(corpus.releases[0]))
        let secondRelease = try projection.targetRelease(for: try .init(corpus.releases[1]))
        XCTAssertEqual(firstRelease.revision, 1)
        XCTAssertEqual(secondRelease.revision, 2)
        XCTAssertEqual(firstRelease.occurrenceIdentityNamespaceID,
                       secondRelease.occurrenceIdentityNamespaceID)

        XCTAssertEqual(try projection.targetCalendar(for: corpus.calendars[0].reference).revision, 1)
        XCTAssertEqual(try projection.targetCalendar(for: corpus.calendars[1].reference).revision, 2)
        XCTAssertEqual(try projection.targetOverride(for: corpus.overrides[0].reference).revision, 1)
        XCTAssertEqual(try projection.targetOverride(for: corpus.overrides[1].reference).revision, 2)

        for source in corpus.releases {
            let target = try projection.targetRelease(for: .init(source))
            XCTAssertEqual(target.scheduleDefinitionID, source.scheduleDefinitionID)
            XCTAssertEqual(target.releaseID, source.releaseID)
            XCTAssertEqual(target.occurrenceIdentityNamespaceID, source.occurrenceIdentityNamespaceID)
            XCTAssertEqual(target.action, source.action)
            XCTAssertEqual(target.lifecycleState, source.lifecycleState)
            XCTAssertEqual(target.startsAtUTC, source.startsAtUTC)
            XCTAssertEqual(target.endsAtUTC, source.endsAtUTC)
            XCTAssertEqual(target.generationHorizonDays, source.generationHorizonDays)
            XCTAssertEqual(target.maximumGeneratedOccurrences, source.maximumGeneratedOccurrences)
            XCTAssertEqual(target.readyLeadSeconds, source.readyLeadSeconds)
            XCTAssertEqual(target.overdueGraceSeconds, source.overdueGraceSeconds)
            XCTAssertEqual(target.subject, source.subject)
            XCTAssertEqual(target.authoredAt, source.authoredAt)
            if case let .advanced(sourceConfiguration) = source.recurrence,
               case let .advanced(targetConfiguration) = target.recurrence {
                let calendar = try projection.targetCalendar(for: sourceConfiguration.calendarRelease)
                XCTAssertEqual(targetConfiguration.calendarRelease, calendar.reference)
                XCTAssertEqual(targetConfiguration.recurrence, sourceConfiguration.recurrence)
                XCTAssertEqual(target.timeBasis.calendarBasisSHA256, calendar.releaseSHA256)
                XCTAssertEqual(target.timeBasis.ianaTimeZoneIdentifier, source.timeBasis.ianaTimeZoneIdentifier)
                XCTAssertEqual(target.timeBasis.timeZoneRuleSetVersion, source.timeBasis.timeZoneRuleSetVersion)
                XCTAssertEqual(target.timeBasis.timeZoneRuleSetSHA256, source.timeBasis.timeZoneRuleSetSHA256)
                XCTAssertNotEqual(target.timeBasis, source.timeBasis)
            } else { XCTFail("Expected advanced calendars") }
            XCTAssertEqual(target.authoredBy.snapshotID, source.authoredBy.snapshotID)
            XCTAssertEqual(target.authoredBy.displayNameAtTime, source.authoredBy.displayNameAtTime)
            XCTAssertEqual(target.workspaceID, corpus.targetWorkspace)
        }
        for source in corpus.calendars {
            let target = try projection.targetCalendar(for: source.reference)
            XCTAssertEqual(target.calendarID, source.calendarID)
            XCTAssertEqual(target.releaseID, source.releaseID)
            XCTAssertEqual(target.name, source.name)
            XCTAssertEqual(target.effectiveRange, source.effectiveRange)
            XCTAssertEqual(target.baseIncludedWeekdays, source.baseIncludedWeekdays)
            XCTAssertEqual(target.excludedDates, source.excludedDates)
            XCTAssertEqual(target.excludedRanges, source.excludedRanges)
            XCTAssertEqual(target.includedOverrideDates, source.includedOverrideDates)
            XCTAssertEqual(target.authoredAt, source.authoredAt)
            XCTAssertEqual(target.authoredBy.snapshotID, source.authoredBy.snapshotID)
        }
        for source in corpus.overrides {
            let target = try projection.targetOverride(for: source.reference)
            XCTAssertEqual(target.scope, source.scope)
            XCTAssertEqual(target.kind, source.kind)
            XCTAssertEqual(target.effectiveRange, source.effectiveRange)
            XCTAssertEqual(target.replacementDate, source.replacementDate)
            XCTAssertEqual(target.replacementWindow, source.replacementWindow)
            XCTAssertEqual(target.reasonCode, source.reasonCode)
            XCTAssertEqual(target.recordedAt, source.recordedAt)
            XCTAssertEqual(target.recordedBy.snapshotID, source.recordedBy.snapshotID)
        }

        let completedRoot = corpus.events.first { $0.action == .complete }!
        let anchor = try C34OccurrenceNavigationAnchorV1(event: completedRoot)
        let eligible = try projection.targetOccurrence(for: anchor, eventSHA256: completedRoot.eventSHA256)
        guard case let .scheduleOccurrence(targetAnchor, sourceEventSHA256) = eligible else {
            return XCTFail("Expected a schedule occurrence")
        }
        XCTAssertEqual(targetAnchor.occurrenceID, completedRoot.occurrenceID)
        XCTAssertEqual(targetAnchor.expectedOccurrenceRevision, completedRoot.revision)
        XCTAssertNotEqual(sourceEventSHA256, completedRoot.eventSHA256)

        let child = corpus.events.first { $0.identityPredecessorOccurrenceID != nil }!
        let targetChild = try projection.targetEvent(for: child)
        let targetRoot = try projection.targetEvent(for: completedRoot)
        XCTAssertEqual(targetChild.identityPredecessorOccurrenceID, targetRoot.occurrenceID)
        XCTAssertEqual(targetChild.identityCompletionEventSHA256, targetRoot.eventSHA256)
    }

    func testEveryProjectedCommandBuildsCanonicalTypedTargetReceipt() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let projection = try corpus.project()
        for (offset, command) in projection.commands.enumerated() {
            let record = try ScheduleReplacementFixture.record(
                command: .applySchedule(command.mutation),
                workspaceRevision: UInt64(offset), localSequence: UInt64(offset + 1)
            )
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.record.receiptData)
            XCTAssertNoThrow(try ScheduleMutationReceiptV1(
                mutation: command.mutation, mutationReceipt: receipt
            ))
            XCTAssertEqual(receipt.postImages, command.postImages)
        }
    }

    func testProjectionIsIndependentOfStoredReceiptOrder() throws {
        let forward = try ScheduleReplacementFixture.make(reverseStorage: false)
        let reverse = try ScheduleReplacementFixture.make(reverseStorage: true)
        XCTAssertNotEqual(forward.history.receipts, reverse.history.receipts)
        XCTAssertEqual(try forward.project().commands, try reverse.project().commands)
    }

    func testRejectsMissingExternalBindingsAndWrongIdentity() throws {
        let corpus = try ScheduleReplacementFixture.make()
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: [], packageBindings: corpus.packageBindings,
            workPacketProjection: corpus.workProjection, roundProjection: corpus.roundProjection
        ))
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings, packageBindings: [],
            workPacketProjection: corpus.workProjection, roundProjection: corpus.roundProjection
        ))
        let wrong = try ScheduleReplacementFixture.identity(sourceWorkspace: ScheduleReplacementFixture.id(999))
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: wrong,
            definitionBindings: corpus.definitionBindings, packageBindings: corpus.packageBindings,
            workPacketProjection: corpus.workProjection, roundProjection: corpus.roundProjection
        ))
    }

    func testBaselineBindingsAndPluralPromotionDependenciesUseExactReceiptPrefix() throws {
        let baseline = try ScheduleReplacementFixture.make(definitionProducer: false)
        XCTAssertNil(baseline.definitionBindings[0].producer)
        XCTAssertTrue(baseline.packageBindings[0].producers.isEmpty)
        XCTAssertNoThrow(try baseline.project())

        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        let projection = try corpus.project()
        let pairs = corpus.packageBindings[0].producers
        XCTAssertEqual(pairs.count, 3)
        for command in projection.commands {
            XCTAssertEqual(command.sourceDependencyMutationIDs,
                           try corpus.expectedDependencies(for: command.sourceEntry.envelope.mutationID))
            guard case .appendRelease = command.mutation.payload else { continue }
            let dependencies = Dictionary(uniqueKeysWithValues: zip(
                command.sourceDependencyMutationIDs, command.targetDependencyMutationIDs))
            for pair in pairs.prefix(2) {
                XCTAssertEqual(dependencies[pair.source.mutationID], pair.target.mutationID)
            }
            XCTAssertNil(dependencies[pairs[2].source.mutationID])
            let definitionPair = try XCTUnwrap(corpus.definitionBindings[0].producer)
            XCTAssertEqual(dependencies[definitionPair.source.mutationID], definitionPair.target.mutationID)
            XCTAssertEqual(command.targetDependencyMutationIDs,
                           try command.sourceDependencyMutationIDs.map { try corpus.targetMutationID(for: $0) })
        }
        for pair in pairs {
            let record = try ScheduleReplacementFixture.record(command: .applyPackagePromotion(pair.target),
                                                               workspaceRevision: 0, localSequence: 1)
            XCTAssertNoThrow(try PackagePromotionMutationReceiptV1(
                mutation: pair.target,
                mutationReceipt: MutationReceiptV1.decodeCanonical(from: record.record.receiptData)))
        }
        let definition = try XCTUnwrap(corpus.definitionBindings[0].producer).target
        let record = try ScheduleReplacementFixture.record(command: .applySurveyDefinition(definition),
                                                           workspaceRevision: 0, localSequence: 1)
        XCTAssertNoThrow(try SurveyDefinitionMutationReceiptV1(
            mutation: definition,
            mutationReceipt: MutationReceiptV1.decodeCanonical(from: record.record.receiptData)))
    }

    func testRejectsMissingDuplicateForeignAndCollidingExternalProducerPairs() throws {
        let corpus = try ScheduleReplacementFixture.make(promotions: true)
        let binding = corpus.packageBindings[0]
        let pairs = binding.producers
        let foreign = try ScheduleReplacementFixture.promotion(
            workspaceID: corpus.sourceWorkspace, package: binding.source, slot: 800,
            mutationID: ScheduleReplacementFixture.mutation(9_000))
        let collision = try ScheduleReplacementFixture.promotion(
            workspaceID: corpus.targetWorkspace, package: binding.source, slot: 800,
            mutationID: corpus.scheduleMutations[0].mutationID)
        let invalidPairs: [[ScheduleReplacementCommandProjectionV1.PackageProducerPair]] = [
            Array(pairs.dropLast()), [pairs[0], pairs[0], pairs[2]],
            [.init(source: pairs[0].source, target: foreign), pairs[1], pairs[2]],
            [.init(source: pairs[0].source, target: collision), pairs[1], pairs[2]]
        ]
        for invalid in invalidPairs {
            XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
                source: corpus.source, identity: corpus.identity,
                definitionBindings: corpus.definitionBindings,
                packageBindings: [.init(source: binding.source, target: binding.target, producers: invalid)],
                workPacketProjection: corpus.workProjection, roundProjection: corpus.roundProjection))
        }
        let definition = corpus.definitionBindings[0]
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: [.init(source: definition.source, target: definition.target, producer: nil)],
            packageBindings: corpus.packageBindings, workPacketProjection: corpus.workProjection,
            roundProjection: corpus.roundProjection))
    }

    func testAddedOccurrenceReferencesAndOverrideFrontiersRecomputeFromExactOwners() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let projection = try corpus.project()
        let targets = try corpus.overrides.map { try projection.targetOverride(for: $0.reference) }
        let expectedAdded = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
            scheduleDefinitionID: targets[1].scheduleRelease.scheduleDefinitionID,
            identityNamespaceID: targets[1].scheduleRelease.occurrenceIdentityNamespaceID,
            overrideEvent: targets[1])
        XCTAssertEqual(targets[2].target, .occurrence(expectedAdded, nominalDate: targets[1].target.nominalDate))
        XCTAssertNotEqual(targets[2].target, corpus.overrides[2].target)
        for (offset, target) in targets.enumerated() {
            XCTAssertEqual(target.expectedOverrideFrontierSHA256,
                           try ScheduleOverridePrecedenceV1.closureSHA256(Array(targets.prefix(offset))))
        }
        let command = try XCTUnwrap(projection.commands.first { $0.mutation.mutationID == targets[2].mutationID })
        XCTAssertTrue(command.sourceDependencyMutationIDs.contains(corpus.overrides[1].mutationID))
    }

    func testUnknownProvenanceFailsClosedAfterAuthenticatedSourceConstruction() throws {
        let corpus = try ScheduleReplacementFixture.make(unknownProvenance: true)
        XCTAssertFalse(corpus.source.entries.isEmpty)
        XCTAssertThrowsError(try corpus.project())
    }

    func testAllDaysTimeBasisRemainsLiteralWithTypedTargetReceipts() throws {
        let corpus = try ScheduleReplacementFixture.make(allDays: true)
        let projection = try corpus.project()
        for source in corpus.releases {
            let target = try projection.targetRelease(for: .init(source))
            XCTAssertEqual(source.timeBasis.calendarBasisID, ScheduleLimitsV1.allDaysCalendarBasisID)
            XCTAssertEqual(target.timeBasis, source.timeBasis)
            XCTAssertEqual(target.recurrence, source.recurrence)
        }
        for source in corpus.events {
            let target = try projection.targetEvent(for: source)
            XCTAssertEqual(target.nominalBasis, source.nominalBasis)
            XCTAssertEqual(target.effectiveBasis, source.effectiveBasis)
        }
        for command in projection.commands {
            let record = try ScheduleReplacementFixture.record(command: .applySchedule(command.mutation),
                                                               workspaceRevision: 0, localSequence: 1)
            XCTAssertNoThrow(try ScheduleMutationReceiptV1(mutation: command.mutation,
                mutationReceipt: MutationReceiptV1.decodeCanonical(from: record.record.receiptData)))
        }
    }

    func testRetiredExceptionMapsAddedReplacementAcrossIdentityNamespaces() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let release = try ScheduleReplacementFixture.release(
            workspaceID: corpus.sourceWorkspace, definition: corpus.definitionBindings[0].source,
            package: corpus.packageBindings[0].source, calendar: corpus.calendars[0],
            revision: 3, predecessor: corpus.releases[1], interval: 2,
            namespace: ScheduleReplacementFixture.id(7_000))
        let added = try ScheduleReplacementFixture.override(
            slot: 970, release: release, revision: 4, predecessor: corpus.overrides[2],
            target: .nominalDate(ScheduleReplacementFixture.date(2027, 6, 26)), kind: .addOne,
            frontier: ScheduleOverridePrecedenceV1.closureSHA256([]))
        let replacement = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
            scheduleDefinitionID: release.scheduleDefinitionID,
            identityNamespaceID: release.occurrenceIdentityNamespaceID, overrideEvent: added)
        let predecessor = corpus.events[4]
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: corpus.sourceWorkspace, slot: 980)
        let exception = try ScheduleExceptionV1(
            exceptionID: ScheduleReplacementFixture.id(981), kind: .retiredForRuleChange,
            priorEffectiveBasisSHA256: ScheduleCanonicalCodecV1.sha256(predecessor.effectiveBasis),
            replacementOccurrenceID: replacement, reasonCode: "rule-rotation", recordedBy: actor,
            recordedAt: ScheduleReplacementFixture.now)
        let event = try OccurrenceHistoryEventV1(
            eventID: ScheduleReplacementFixture.id(982), workspaceID: corpus.sourceWorkspace,
            occurrenceID: predecessor.occurrenceID, scheduleRelease: predecessor.scheduleRelease,
            action: .applyException, nominalBasis: predecessor.nominalBasis, effectiveBasis: predecessor.effectiveBasis,
            exception: exception, predecessor: predecessor, revision: predecessor.revision + 1,
            mutationID: ScheduleReplacementFixture.mutation(982), recordedBy: actor,
            recordedAt: ScheduleReplacementFixture.now)
        let additions = try [
            ScheduleMutationV1(workspaceID: corpus.sourceWorkspace, mutationID: release.mutationID,
                payload: .appendRelease(release, predecessor: corpus.releases[1])),
            ScheduleMutationV1(workspaceID: corpus.sourceWorkspace, mutationID: added.mutationID,
                payload: .appendOverrideEvent(added, predecessor: corpus.overrides[2], release: release)),
            ScheduleMutationV1(workspaceID: corpus.sourceWorkspace, mutationID: event.mutationID,
                payload: .appendOccurrenceEvent(event, predecessor: predecessor, release: corpus.releases[1]))
        ]
        var commands = try corpus.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }.sorted { $0.expectedRevision.workspaceRevision < $1.expectedRevision.workspaceRevision }.map(\.command)
        commands += additions.map(WorkspaceCommandV1.applySchedule)
        let history = try ScheduleReplacementFixture.history(commands: commands, reverseStorage: true)
        let projection = try corpus.project(history: history)
        let target = try projection.targetEvent(for: event)
        let targetAdded = try projection.targetOverride(for: added.reference)
        let targetException = try XCTUnwrap(target.exception)
        let expectedReplacement = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
            scheduleDefinitionID: targetAdded.scheduleRelease.scheduleDefinitionID,
            identityNamespaceID: targetAdded.scheduleRelease.occurrenceIdentityNamespaceID,
            overrideEvent: targetAdded)
        XCTAssertNotEqual(target.scheduleRelease.occurrenceIdentityNamespaceID,
                          targetAdded.scheduleRelease.occurrenceIdentityNamespaceID)
        XCTAssertEqual(targetException.replacementOccurrenceID, expectedReplacement)
        XCTAssertNotEqual(targetException.replacementOccurrenceID, replacement)
        XCTAssertEqual(targetException.kind, exception.kind)
        XCTAssertEqual(targetException.reasonCode, exception.reasonCode)
        XCTAssertEqual(targetException.recordedAt, exception.recordedAt)
        XCTAssertEqual(targetException.recordedBy.snapshotID, exception.recordedBy.snapshotID)
        XCTAssertEqual(targetException.recordedBy.workspaceID, corpus.targetWorkspace)
        ScheduleReplacementFixture.assertActorLiterals(exception.recordedBy, targetException.recordedBy)
        XCTAssertNil(targetException.replacementBasis)
        XCTAssertEqual(targetException.priorEffectiveBasisSHA256,
                       try ScheduleCanonicalCodecV1.sha256(projection.targetEvent(for: predecessor).effectiveBasis))
        let command = try XCTUnwrap(projection.commands.last)
        XCTAssertTrue(command.sourceDependencyMutationIDs.contains(added.mutationID))
        for command in projection.commands.suffix(3) {
            let record = try ScheduleReplacementFixture.record(command: .applySchedule(command.mutation),
                                                               workspaceRevision: 0, localSequence: 1)
            XCTAssertNoThrow(try ScheduleMutationReceiptV1(mutation: command.mutation,
                mutationReceipt: MutationReceiptV1.decodeCanonical(from: record.record.receiptData)))
        }
    }

    func testExceptionRecomputesPriorEffectiveDigestAndOverrideProvenance() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let predecessor = corpus.events[4]
        let replacement = try ScheduleReplacementFixture.basis("2027-06-04", release: corpus.releases[1],
                                                               provenance: corpus.overrides[1].eventSHA256)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: corpus.sourceWorkspace, slot: 960)
        let exception = try ScheduleExceptionV1(
            exceptionID: ScheduleReplacementFixture.id(961), kind: .basisAdjusted,
            priorEffectiveBasisSHA256: ScheduleCanonicalCodecV1.sha256(predecessor.effectiveBasis),
            replacementBasis: replacement, reasonCode: "calendar-adjustment", recordedBy: actor,
            recordedAt: ScheduleReplacementFixture.now)
        let event = try OccurrenceHistoryEventV1(
            eventID: ScheduleReplacementFixture.id(962), workspaceID: corpus.sourceWorkspace,
            occurrenceID: predecessor.occurrenceID, scheduleRelease: predecessor.scheduleRelease,
            action: .applyException, nominalBasis: predecessor.nominalBasis, effectiveBasis: replacement,
            exception: exception, predecessor: predecessor, revision: predecessor.revision + 1,
            mutationID: ScheduleReplacementFixture.mutation(962), recordedBy: actor,
            recordedAt: ScheduleReplacementFixture.now)
        let mutation = try ScheduleMutationV1(workspaceID: corpus.sourceWorkspace, mutationID: event.mutationID,
            payload: .appendOccurrenceEvent(event, predecessor: predecessor, release: corpus.releases[1]))
        var commands = try corpus.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }.sorted { $0.expectedRevision.workspaceRevision < $1.expectedRevision.workspaceRevision }.map(\.command)
        commands.append(.applySchedule(mutation))
        let history = try ScheduleReplacementFixture.history(commands: commands, reverseStorage: true)
        let projection = try corpus.project(history: history)
        let target = try projection.targetEvent(for: event)
        let targetPrior = try projection.targetEvent(for: predecessor)
        let targetException = try XCTUnwrap(target.exception)
        XCTAssertEqual(targetException.priorEffectiveBasisSHA256,
                       try ScheduleCanonicalCodecV1.sha256(targetPrior.effectiveBasis))
        XCTAssertNotEqual(targetException.priorEffectiveBasisSHA256, exception.priorEffectiveBasisSHA256)
        XCTAssertEqual(targetException.replacementBasis, target.effectiveBasis)
        XCTAssertEqual(target.effectiveBasis.adjustmentProvenanceSHA256,
                       try projection.targetOverride(for: corpus.overrides[1].reference).eventSHA256)
        XCTAssertEqual(targetException.exceptionID, exception.exceptionID)
        XCTAssertEqual(targetException.reasonCode, exception.reasonCode)
        XCTAssertEqual(targetException.recordedAt, exception.recordedAt)
        XCTAssertEqual(targetException.recordedBy.workspaceID, corpus.targetWorkspace)
        ScheduleReplacementFixture.assertActorLiterals(exception.recordedBy, targetException.recordedBy)
        let command = try XCTUnwrap(projection.commands.last)
        XCTAssertTrue(command.sourceDependencyMutationIDs.contains(corpus.overrides[1].mutationID))
        let record = try ScheduleReplacementFixture.record(command: .applySchedule(command.mutation),
                                                           workspaceRevision: 0, localSequence: 1)
        XCTAssertNoThrow(try ScheduleMutationReceiptV1(mutation: command.mutation,
            mutationReceipt: MutationReceiptV1.decodeCanonical(from: record.record.receiptData)))
    }

    func testUnknownCompletionAndDifferentSourceProjectionsFailClosed() throws {
        let unknown = try ScheduleReplacementFixture.make(unknownCompletion: true)
        XCTAssertFalse(unknown.source.entries.isEmpty)
        XCTAssertThrowsError(try unknown.project())
        let corpus = try ScheduleReplacementFixture.make()
        let other = try ScheduleReplacementFixture.make(definitionProducer: false)
        XCTAssertNotEqual(corpus.source, other.source)
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: corpus.identity, definitionBindings: corpus.definitionBindings,
            packageBindings: corpus.packageBindings, workPacketProjection: other.workProjection,
            roundProjection: corpus.roundProjection))
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: corpus.identity, definitionBindings: corpus.definitionBindings,
            packageBindings: corpus.packageBindings, workPacketProjection: corpus.workProjection,
            roundProjection: other.roundProjection))
    }

    func testRejectsConstructorValidMismatchedEmbeddedHistoricalRelease() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let different = try ScheduleReplacementFixture.release(
            workspaceID: corpus.sourceWorkspace, definition: corpus.definitionBindings[0].source,
            package: corpus.packageBindings[0].source, calendar: corpus.calendars[0],
            revision: 1, readyLeadDelta: 1)
        XCTAssertEqual(different.releaseID, corpus.releases[0].releaseID)
        XCTAssertNotEqual(different.releaseSHA256, corpus.releases[0].releaseSHA256)
        let basis = try ScheduleReplacementFixture.basis("2027-06-25", release: different)
        let id = try OccurrenceIDV1(scheduleDefinitionID: different.scheduleDefinitionID,
            identityNamespaceID: different.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey)
        let event = try ScheduleReplacementFixture.event(slot: 950, release: different,
            occurrenceID: id, basis: basis, action: .generated, predecessor: nil)
        let command = try ScheduleMutationV1(workspaceID: corpus.sourceWorkspace, mutationID: event.mutationID,
            payload: .appendOccurrenceEvent(event, predecessor: nil, release: different))
        var commands = try corpus.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }.sorted { $0.expectedRevision.workspaceRevision < $1.expectedRevision.workspaceRevision }.map(\.command)
        commands.append(.applySchedule(command))
        let history = try ScheduleReplacementFixture.history(commands: commands, reverseStorage: true)
        XCTAssertThrowsError(try corpus.project(history: history))
    }

    func testHistoricalLookupRejectsUnknownDigestAndForeignAnchor() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let projection = try corpus.project()
        let source = corpus.events[0]
        let anchor = try C34OccurrenceNavigationAnchorV1(event: source)
        XCTAssertThrowsError(try projection.targetOccurrence(for: anchor,
            eventSHA256: ScheduleReplacementFixture.digest("f")))
        let target = try projection.targetEvent(for: source)
        XCTAssertThrowsError(try projection.targetEvent(for: target))
        XCTAssertThrowsError(try projection.targetRelease(for: .init(
            projection.targetRelease(for: .init(corpus.releases[0])))))
        XCTAssertThrowsError(try projection.targetOccurrence(for: C34OccurrenceNavigationAnchorV1(event: target),
                                                              eventSHA256: source.eventSHA256))
    }

    func testRejectsRelevantQuarantineAndDuplicateAuthenticatedMutation() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let entry = try XCTUnwrap(corpus.scheduleEntries.first)
        let quarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: corpus.sourceWorkspace,
            mutationID: entry.envelope.mutationID.rawValue,
            identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: try entry.envelope.canonicalSHA256(),
            conflictingIdentitySHA256: ScheduleReplacementFixture.digest("f"),
            detectedAt: ScheduleReplacementFixture.now
        )
        let quarantined = ScheduleReplacementFixture.replacing(corpus.history, quarantines: [quarantine])
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(quarantined))
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: quarantined
        ))

        let duplicated = ScheduleReplacementFixture.replacing(
            corpus.history, receipts: corpus.history.receipts + [entry.record]
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: duplicated
        ))
    }

    func testRejectsConstructorValidForkedReleaseHistory() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let fork = try ScheduleReplacementFixture.release(
            workspaceID: corpus.sourceWorkspace, definition: corpus.definitionBindings[0].source,
            package: corpus.packageBindings[0].source, calendar: corpus.calendars[0],
            revision: 2, predecessor: corpus.releases[0], slotOffset: 5_000)
        XCTAssertNoThrow(try fork.validateSuccessor(of: corpus.releases[0]))
        let extra = try ScheduleMutationV1(workspaceID: corpus.sourceWorkspace, mutationID: fork.mutationID,
                                          payload: .appendRelease(fork, predecessor: corpus.releases[0]))
        var commands = try corpus.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }.sorted { $0.expectedRevision.workspaceRevision < $1.expectedRevision.workspaceRevision }.map(\.command)
        commands.append(.applySchedule(extra))
        let history = try ScheduleReplacementFixture.history(commands: commands, reverseStorage: true)
        XCTAssertThrowsError(try corpus.project(history: history))
    }

    func testRejectsMissingCalendarProducerAndDuplicateDefinitionBindings() throws {
        let corpus = try ScheduleReplacementFixture.make()
        let commands = try corpus.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }.sorted { $0.expectedRevision.workspaceRevision < $1.expectedRevision.workspaceRevision }
            .filter { $0.mutationID != corpus.scheduleMutations[0].mutationID }.map(\.command)
        let missing = try ScheduleReplacementFixture.history(commands: commands, reverseStorage: true)
        let source = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.sourceWorkspace, history: missing)
        let work = try WorkPacketReplacementCommandProjectionV1.project(source: source, identity: corpus.identity)
        let round = try RoundSessionReplacementCommandProjectionV1.project(source: source, identity: corpus.identity)
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: source, identity: corpus.identity,
            definitionBindings: corpus.definitionBindings, packageBindings: corpus.packageBindings,
            workPacketProjection: work, roundProjection: round))

        var forkedBindings = corpus.definitionBindings
        forkedBindings.append(corpus.definitionBindings[0])
        XCTAssertThrowsError(try ScheduleReplacementCommandProjectionV1.project(
            source: corpus.source, identity: corpus.identity,
            definitionBindings: forkedBindings, packageBindings: corpus.packageBindings,
            workPacketProjection: corpus.workProjection, roundProjection: corpus.roundProjection
        ))
    }
}

enum ScheduleReplacementFixture {
    struct Corpus {
        let sourceWorkspace: WorkspaceID
        let targetWorkspace: WorkspaceID
        let history: MutationHistorySnapshotV1
        let source: ReferenceOwnerReplacementSourceV1.Source
        let identity: RestoreIdentityV1
        let scheduleEntries: [ReferenceOwnerReplacementSourceV1.Entry]
        let scheduleMutations: [ScheduleMutationV1]
        let releases: [ScheduleDefinitionReleaseV1]
        let calendars: [ExceptionCalendarReleaseV1]
        let overrides: [ScheduleOverrideEventV1]
        let forwardOverride: ScheduleOverrideEventV1
        let events: [OccurrenceHistoryEventV1]
        let definitionBindings: [ScheduleReplacementCommandProjectionV1.DefinitionBinding]
        let packageBindings: [ScheduleReplacementCommandProjectionV1.PackageBinding]
        let workProjection: WorkPacketReplacementCommandProjectionV1.Projection
        let roundProjection: RoundSessionReplacementCommandProjectionV1.Projection

        func project() throws -> ScheduleReplacementCommandProjectionV1.Projection {
            try ScheduleReplacementCommandProjectionV1.project(
                source: source, identity: identity,
                definitionBindings: definitionBindings, packageBindings: packageBindings,
                workPacketProjection: workProjection, roundProjection: roundProjection
            )
        }

        func project(history: MutationHistorySnapshotV1) throws -> ScheduleReplacementCommandProjectionV1.Projection {
            let source = try ReferenceOwnerReplacementSourceV1.source(workspaceID: sourceWorkspace, history: history)
            return try ScheduleReplacementCommandProjectionV1.project(
                source: source, identity: identity, definitionBindings: definitionBindings,
                packageBindings: packageBindings,
                workPacketProjection: WorkPacketReplacementCommandProjectionV1.project(source: source, identity: identity),
                roundProjection: RoundSessionReplacementCommandProjectionV1.project(source: source, identity: identity))
        }

        func expectedDependencies(for sourceID: MutationIDV1) throws -> [MutationIDV1] {
            let calendar = calendars[0].mutationID
            let first = releases[0].mutationID, second = releases[1].mutationID
            let sourceWork = try XCTUnwrap(workProjection.commands.first).source.envelope.mutationID
            let sourceRound = try XCTUnwrap(roundProjection.commands.first).source.envelope.mutationID
            let expected: [[MutationIDV1]] = [
                [], [calendar], [first, calendar],
                [first, calendar, events[0].mutationID, sourceWork],
                [first, calendar, events[1].mutationID, sourceWork],
                [calendar], [first, calendar], [second],
                [second, overrides[0].mutationID],
                [second, overrides[0].mutationID, overrides[1].mutationID],
                [second, calendar, events[2].mutationID],
                [second, calendar, events[3].mutationID, events[2].mutationID, sourceRound]
            ]
            let offset = try XCTUnwrap(scheduleMutations.firstIndex { $0.mutationID == sourceID })
            var dependencies = expected[offset]
            if offset != 0 && offset != 5 {
                if let producer = definitionBindings[0].producer { dependencies.append(producer.source.mutationID) }
                dependencies += packageBindings[0].producers.prefix(2).map { $0.source.mutationID }
            }
            return Array(Set(dependencies)).sorted(by: ScheduleReplacementFixture.less)
        }

        func targetMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
            if let pair = definitionBindings.compactMap(\.producer).first(where: { $0.source.mutationID == sourceID }) {
                return pair.target.mutationID
            }
            if let pair = packageBindings.flatMap(\.producers).first(where: { $0.source.mutationID == sourceID }) {
                return pair.target.mutationID
            }
            guard let entry = source.entries.first(where: { $0.envelope.mutationID == sourceID }) else {
                throw ScheduleReplacementCommandProjectionFailureV1.missingDependency
            }
            switch entry.family {
            case .workPacket: return try identity.destinationWorkPacketMutationID(for: sourceID)
            case .roundSession: return try identity.destinationRoundSessionMutationID(for: sourceID)
            case .schedule: return try identity.destinationScheduleMutationID(for: sourceID)
            case .guidedSurvey: return try identity.destinationSurveySessionMutationID(for: sourceID)
            case .fieldDraft: return try identity.destinationFieldDraftMutationID(for: sourceID)
            }
        }
    }

    struct Record { let record: MutationHistoryReceiptRecordV1; let images: [MutationPostImageV1] }
    struct Bindings {
        let workspaceID: WorkspaceID; let mutationID: MutationIDV1
        let expected: [WorkspaceEntityRevisionV1]; let images: [MutationPostImageV1]
    }

    static let now = Date(timeIntervalSince1970: 1_812_345_600)
    static let generationID = id(2)
    static let writerID = id(3)
    static let replicaID = ReplicaID(rawValue: id(4))

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c5730000-0000-4000-8000-%012x", value))!
    }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(10_000 + value)) }
    static func digest(_ character: Character) -> String { String(repeating: String(character), count: 64) }
    static func less(_ lhs: MutationIDV1, _ rhs: MutationIDV1) -> Bool {
        lhs.rawValue.uuidString.lowercased() < rhs.rawValue.uuidString.lowercased()
    }

    static func assertActorLiterals(_ source: ActorSnapshotV1, _ target: ActorSnapshotV1,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(target.snapshotID, source.snapshotID, file: file, line: line)
        XCTAssertEqual(target.actor.actorReferenceID, source.actor.actorReferenceID, file: file, line: line)
        XCTAssertEqual(target.actor.partyID, source.actor.partyID, file: file, line: line)
        XCTAssertEqual(target.actor.displayName, source.actor.displayName, file: file, line: line)
        XCTAssertEqual(target.responsibility, source.responsibility, file: file, line: line)
        XCTAssertEqual(target.displayNameAtTime, source.displayNameAtTime, file: file, line: line)
        XCTAssertEqual(target.capturedAt, source.capturedAt, file: file, line: line)
        XCTAssertEqual(target.actor.workspaceID, target.workspaceID, file: file, line: line)
    }

    static func assertBasisLiterals(_ source: ResolvedOccurrenceBasisV1,
                                    _ target: ResolvedOccurrenceBasisV1,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(target.nominalLocalDate, source.nominalLocalDate, file: file, line: line)
        XCTAssertEqual(target.nominalLocalTime, source.nominalLocalTime, file: file, line: line)
        XCTAssertEqual(target.resolvedAtUTC, source.resolvedAtUTC, file: file, line: line)
        XCTAssertEqual(target.utcOffsetSeconds, source.utcOffsetSeconds, file: file, line: line)
        XCTAssertEqual(target.disposition, source.disposition, file: file, line: line)
    }

    static func identity(sourceWorkspace: UUID = id(1)) throws -> RestoreIdentityV1 {
        try RestoreIdentityDecisionV1.decide(.init(
            mode: .replaceExisting,
            source: .init(workspaceID: sourceWorkspace, replicaID: id(5)),
            oldPointer: .init(generationID: id(6), generationManifestSHA256: digest("a"),
                              workspaceID: id(7), replicaID: id(8)),
            targetGenerationID: id(9), targetGenerationManifestSHA256: digest("b"),
            allocatedWorkspaceID: id(20), allocatedReplicaID: id(21)
        ))
    }

    private struct FixtureConstructionFailure: Error, CustomStringConvertible {
        let stage: String
        let errorType: String
        let detail: String
        var description: String {
            "ScheduleReplacementFixture.make stage=\(stage) type=\(errorType) error=\(detail)"
        }
    }

    static func make(reverseStorage: Bool = true, definitionProducer: Bool = true, promotions: Bool = false, unknownProvenance: Bool = false, unknownCompletion: Bool = false, allDays: Bool = false) throws -> Corpus {
        var fixtureStage = "entry"
        do {
            fixtureStage = "sourceWorkspace"
            let sourceWorkspace = WorkspaceID(rawValue: id(1))
            fixtureStage = "identity"
            let identity = try identity()
            fixtureStage = "targetWorkspace"
            let targetWorkspace = WorkspaceID(rawValue: identity.targetPointer.workspaceID)
            fixtureStage = "sourceDefinition"
            let sourceDefinition = try C26SurveySessionTestSupport.release(
                releaseSlot: 600, workspaceID: sourceWorkspace
            )
            fixtureStage = "sourceDefinitionMutation"
            let sourceDefinitionMutation = try definitionMutation(release: sourceDefinition)
            fixtureStage = "targetDefinitionMutation"
            let targetDefinitionMutation = try reboundDefinitionMutation(
                sourceDefinitionMutation, workspaceID: targetWorkspace,
                mutationID: definitionProducer ? mutation(900) : sourceDefinitionMutation.mutationID
            )
            fixtureStage = "targetDefinition"
            let targetDefinition = targetDefinitionMutation.release
            fixtureStage = "package"
            let package = try C26SurveySessionTestSupport.packageRelease()
            fixtureStage = "promotionPairs"
            let promotionPairs = try (promotions ? [800, 820, 840] : []).map { slot in
                ScheduleReplacementCommandProjectionV1.PackageProducerPair(
                    source: try promotion(workspaceID: sourceWorkspace, package: package, slot: slot, mutationID: mutation(slot)),
                    target: try promotion(workspaceID: targetWorkspace, package: package, slot: slot, mutationID: mutation(2_000 - slot))
                )
            }

            fixtureStage = "manifestMutation"
            let manifestMutation = try workPacket(workspaceID: sourceWorkspace)
            fixtureStage = "manifest"
            let manifest: WorkPacketManifestV1
            guard case let .appendManifest(value) = manifestMutation.postImage else { fatalError() }
            manifest = value
            fixtureStage = "roundMutation"
            let roundMutation = try round(workspaceID: sourceWorkspace, package: package)
            fixtureStage = "round"
            let round = roundMutation.session
            fixtureStage = "calendar1"
            let calendar1 = try calendar(workspaceID: sourceWorkspace, revision: 1)
            fixtureStage = "calendar2"
            let calendar2 = try calendar(workspaceID: sourceWorkspace, revision: 2, predecessor: calendar1)
            fixtureStage = "release1"
            let release1 = try release(
                workspaceID: sourceWorkspace, definition: sourceDefinition, package: package,
                calendar: calendar1, revision: 1, advanced: !allDays
            )
            fixtureStage = "release2"
            let release2 = try release(
                workspaceID: sourceWorkspace, definition: sourceDefinition, package: package,
                calendar: calendar1, revision: 2, predecessor: release1, advanced: !allDays
            )
            fixtureStage = "basis1"
            let basis1 = try basis("2027-06-01", release: release1, provenance: unknownProvenance ? digest("f") : nil)
            fixtureStage = "occurrence1"
            let occurrence1 = try OccurrenceIDV1(
                scheduleDefinitionID: release1.scheduleDefinitionID,
                identityNamespaceID: release1.occurrenceIdentityNamespaceID,
                nominalKey: basis1.nominalKey
            )
            fixtureStage = "generated1"
            let generated1 = try event(
                slot: 100, release: release1, occurrenceID: occurrence1,
                basis: basis1, action: .generated, predecessor: nil
            )
            fixtureStage = "startedWork"
            let startedWork = try event(
                slot: 101, release: release1, occurrenceID: occurrence1,
                basis: basis1, action: .start, predecessor: generated1,
                work: .workPacket(try WorkPacketManifestReferenceV1(manifest))
            )
            fixtureStage = "completed"
            let completed = try event(
                slot: 102, release: release1, occurrenceID: occurrence1,
                basis: basis1, action: .complete, predecessor: startedWork,
                work: .workPacket(try WorkPacketManifestReferenceV1(manifest)), completedAt: now.addingTimeInterval(500)
            )
            fixtureStage = "completionSHA"
            let completionSHA = unknownCompletion ? digest("f") : completed.eventSHA256
            fixtureStage = "basis2"
            let basis2 = try basis("2027-06-02", release: release2)
            fixtureStage = "childID"
            let childID = try OccurrenceIDV1(
                scheduleDefinitionID: release2.scheduleDefinitionID,
                identityNamespaceID: release2.occurrenceIdentityNamespaceID,
                nominalKey: basis2.nominalKey, predecessorOccurrenceID: occurrence1,
                completionEventSHA256: completionSHA
            )
            fixtureStage = "basis3"
            let basis3 = try basis("2027-06-03", release: release2)
            fixtureStage = "siblingID"
            let siblingID = try OccurrenceIDV1(
                scheduleDefinitionID: release2.scheduleDefinitionID,
                identityNamespaceID: release2.occurrenceIdentityNamespaceID,
                nominalKey: basis3.nominalKey
            )
            fixtureStage = "generationMutationID"
            let generationMutationID = try mutation(106)
            fixtureStage = "child"
            let child = try event(
                slot: 106, release: release2, occurrenceID: childID, basis: basis2,
                action: .generated, predecessor: nil, mutationID: generationMutationID,
                identityPredecessor: occurrence1, identityCompletion: completionSHA
            )
            fixtureStage = "sibling"
            let sibling = try event(
                slot: 107, release: release2, occurrenceID: siblingID, basis: basis3,
                action: .generated, predecessor: nil, mutationID: generationMutationID
            )
            fixtureStage = "startedRound"
            let startedRound = try event(
                slot: 108, release: release2, occurrenceID: childID, basis: basis2,
                action: .start, predecessor: child,
                work: .roundSession(sessionID: round.sessionID, revision: round.revision,
                                    sessionSHA256: round.sessionSHA256)
            )
            fixtureStage = "plan"
            let plan = try OccurrenceGenerationPlanV1(
                definition: release2,
                window: .init(startsAtUTC: release2.startsAtUTC,
                              endsAtUTC: release2.startsAtUTC.addingTimeInterval(10 * 86_400),
                              maximumOccurrences: 4),
                candidates: [
                    .init(occurrenceID: childID, nominalBasis: basis2, effectiveBasis: basis2,
                          predecessorOccurrenceID: occurrence1,
                          completionEventSHA256: completionSHA),
                    .init(occurrenceID: siblingID, nominalBasis: basis3, effectiveBasis: basis3)
                ], existingOccurrenceIDs: [occurrence1]
            )
            fixtureStage = "emptyFrontier"
            let emptyFrontier = try ScheduleOverridePrecedenceV1.closureSHA256([])
            fixtureStage = "forwardOccurrence"
            let forwardOccurrence = OccurrenceIDV1(rawValue: digest("e"))
            fixtureStage = "override1"
            let override1 = try override(
                slot: 120, release: release2, revision: 1, predecessor: nil,
                target: .occurrence(forwardOccurrence, nominalDate: try date(2027, 6, 20)),
                kind: .move, frontier: emptyFrontier
            )
            fixtureStage = "override2"
            let override2 = try override(
                slot: 121, release: release2, revision: 2, predecessor: override1,
                target: .nominalDate(try date(2027, 6, 21)), kind: .addOne,
                frontier: try ScheduleOverridePrecedenceV1.closureSHA256([override1])
            )

            fixtureStage = "addedID"
            let addedID = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
                scheduleDefinitionID: release2.scheduleDefinitionID,
                identityNamespaceID: release2.occurrenceIdentityNamespaceID, overrideEvent: override2)
            fixtureStage = "override3"
            let override3 = try override(
                slot: 122, release: release2, revision: 3, predecessor: override2,
                target: .occurrence(addedID, nominalDate: override2.target.nominalDate), kind: .skip,
                frontier: try ScheduleOverridePrecedenceV1.closureSHA256([override1, override2]))

            fixtureStage = "scheduleMutations"
            let scheduleMutations = try [
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: calendar1.mutationID,
                                   payload: .appendExceptionCalendarRelease(calendar1, predecessor: nil)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: release1.mutationID,
                                   payload: .appendRelease(release1, predecessor: nil)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: generated1.mutationID,
                                   payload: .appendOccurrenceEvent(generated1, predecessor: nil, release: release1)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: startedWork.mutationID,
                                   payload: .startOccurrence(startedWork, predecessor: generated1, release: release1)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: completed.mutationID,
                                   payload: .appendOccurrenceEvent(completed, predecessor: startedWork, release: release1)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: calendar2.mutationID,
                                   payload: .appendExceptionCalendarRelease(calendar2, predecessor: calendar1)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: release2.mutationID,
                                   payload: .appendRelease(release2, predecessor: release1)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: override1.mutationID,
                                   payload: .appendOverrideEvent(override1, predecessor: nil, release: release2)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: override2.mutationID,
                                   payload: .appendOverrideEvent(override2, predecessor: override1, release: release2)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: override3.mutationID,
                                   payload: .appendOverrideEvent(override3, predecessor: override2, release: release2)),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: generationMutationID,
                                   payload: .generateOccurrences(release: release2, plan: plan, events: [child, sibling])),
                ScheduleMutationV1(workspaceID: sourceWorkspace, mutationID: startedRound.mutationID,
                                   payload: .startOccurrence(startedRound, predecessor: child, release: release2))
            ]
            fixtureStage = "commands"
            let commands: [WorkspaceCommandV1] =
                (definitionProducer ? [.applySurveyDefinition(sourceDefinitionMutation)] : [])
                + promotionPairs.prefix(2).map { .applyPackagePromotion($0.source) }
                + [.applyWorkPacket(manifestMutation), .applyRoundSession(roundMutation)]
                + scheduleMutations.map(WorkspaceCommandV1.applySchedule)
                + promotionPairs.dropFirst(2).map { .applyPackagePromotion($0.source) }
            fixtureStage = "built"
            let built = try history(commands: commands, reverseStorage: reverseStorage)
            fixtureStage = "source"
            let source = try ReferenceOwnerReplacementSourceV1.source(
                workspaceID: sourceWorkspace, history: built
            )
            fixtureStage = "workProjection"
            let workProjection = try WorkPacketReplacementCommandProjectionV1.project(
                source: source, identity: identity
            )
            fixtureStage = "roundProjection"
            let roundProjection = try RoundSessionReplacementCommandProjectionV1.project(
                source: source, identity: identity
            )
            fixtureStage = "definitionBindings"
            let definitionBindings = [ScheduleReplacementCommandProjectionV1.DefinitionBinding(
                source: sourceDefinition, target: targetDefinition,
                producer: definitionProducer ? .init(source: sourceDefinitionMutation, target: targetDefinitionMutation) : nil
            )]
            fixtureStage = "packageBindings"
            let packageBindings = [ScheduleReplacementCommandProjectionV1.PackageBinding(
                source: package, target: package, producers: promotionPairs
            )]
            fixtureStage = "corpus"
            return Corpus(
                sourceWorkspace: sourceWorkspace, targetWorkspace: targetWorkspace,
                history: built, source: source, identity: identity,
                scheduleEntries: source.entries.filter { $0.family == .schedule },
                scheduleMutations: scheduleMutations, releases: [release1, release2],
                calendars: [calendar1, calendar2], overrides: [override1, override2, override3],
                forwardOverride: override1,
                events: [generated1, startedWork, completed, child, sibling, startedRound],
                definitionBindings: definitionBindings, packageBindings: packageBindings,
                workProjection: workProjection, roundProjection: roundProjection
            )
        } catch {
            throw FixtureConstructionFailure(stage: fixtureStage,
                errorType: String(reflecting: type(of: error)), detail: String(reflecting: error))
        }
    }

    static func definitionMutation(release: SurveyDefinitionReleaseV1) throws
        -> SurveyDefinitionMutationV1 {
        let event = try SurveyDefinitionLifecycleEventV1(
            eventID: id(590), workspaceID: release.workspaceID,
            definitionID: release.definitionID, action: .createDraft,
            priorState: nil, resultingState: .draft,
            release: .init(release), actor: release.authoredBy,
            recordedAt: release.authoredAt, revision: 1, mutationID: release.mutationID
        )
        let identity = try SurveyDefinitionIdentityV1(
            definitionID: release.definitionID, workspaceID: release.workspaceID,
            activityKind: release.activityKind, lifecycleState: .draft,
            currentRelease: .init(release), latestLifecycleEventID: event.eventID,
            latestLifecycleEventSHA256: event.eventSHA256,
            createdBy: release.authoredBy, createdAt: release.authoredAt,
            revision: 1, mutationID: release.mutationID
        )
        return try .init(identity: identity, release: release, event: event)
    }

    static func reboundDefinitionMutation(_ source: SurveyDefinitionMutationV1,
                                          workspaceID: WorkspaceID,
                                          mutationID: MutationIDV1) throws
        -> SurveyDefinitionMutationV1 {
        let actor = try ActorSnapshotV1(
            snapshotID: source.release.authoredBy.snapshotID, workspaceID: workspaceID,
            actor: .init(actorReferenceID: source.release.authoredBy.actor.actorReferenceID,
                         workspaceID: workspaceID,
                         partyID: source.release.authoredBy.actor.partyID,
                         displayName: source.release.authoredBy.actor.displayName),
            responsibility: source.release.authoredBy.responsibility,
            displayNameAtTime: source.release.authoredBy.displayNameAtTime,
            capturedAt: source.release.authoredBy.capturedAt
        )
        let release = try SurveyDefinitionReleaseV1(
            releaseID: source.release.releaseID, workspaceID: workspaceID,
            definitionID: source.release.definitionID,
            activityKind: source.release.activityKind,
            ownerPackageID: source.release.ownerPackageID,
            sections: source.release.sections, completionRules: source.release.completionRules,
            claimsProfile: source.release.claimsProfile,
            reportProjection: source.release.reportProjection,
            localizationReleaseSHA256: source.release.localizationReleaseSHA256,
            supersedesReleaseID: source.release.supersedesReleaseID,
            revision: source.release.revision, mutationID: mutationID,
            authoredBy: actor, authoredAt: source.release.authoredAt
        )
        let event = try SurveyDefinitionLifecycleEventV1(
            eventID: source.event.eventID, workspaceID: workspaceID,
            definitionID: release.definitionID, action: source.event.action,
            priorState: source.event.priorState, resultingState: source.event.resultingState,
            release: .init(release), actor: actor, recordedAt: source.event.recordedAt,
            revision: source.event.revision, mutationID: mutationID
        )
        let value = try SurveyDefinitionIdentityV1(
            definitionID: release.definitionID, workspaceID: workspaceID,
            activityKind: release.activityKind, lifecycleState: source.identity.lifecycleState,
            currentRelease: .init(release), latestLifecycleEventID: event.eventID,
            latestLifecycleEventSHA256: event.eventSHA256,
            createdBy: actor, createdAt: source.identity.createdAt,
            revision: source.identity.revision, mutationID: mutationID
        )
        return try .init(identity: value, release: release, event: event)
    }

    static func promotion(workspaceID: WorkspaceID, package: InspectionPackageReleaseV1,
                          slot: Int, mutationID: MutationIDV1) throws -> PackagePromotionMutationV1 {
        let diff = try PackageSemanticDifferV1.diff(source: package, target: package)
        let checks = PackageSandboxCheckKindV1.allCases.flatMap { kind in
            PackageSandboxFixtureShapeV1.allCases.map { shape in
                let name = "schedule.\(kind.rawValue.lowercased()).\(shape.rawValue.lowercased())"
                return PackageSandboxCheckResultV1(
                    kind: kind, shape: shape, fixtureID: name,
                    fixtureSHA256: KernelCanonicalHashV1.sha256(Data(name.utf8)),
                    resultSHA256: KernelCanonicalHashV1.sha256(Data("result.\(name)".utf8)),
                    disposition: .passed, activationEvidence: .notAttempted)
            }
        }
        let sandbox = try PackageSandboxRunV1(
            runID: id(slot + 1), workspaceID: workspaceID,
            packageReleaseID: package.packageReleaseID, packageSHA256: package.packageSHA256,
            workflowSHA256: package.workflowSHA256, semanticDiffSHA256: diff.diffSHA256,
            exactHead: String(repeating: "c", count: 40),
            activePointerStateBeforeSHA256: digest("a"), activePointerStateAfterSHA256: digest("a"),
            checks: checks, mutationID: mutationID)
        let promoted = try PromotedPackageReleaseV1(
            releaseRecordID: id(slot + 2), workspaceID: workspaceID, packageRelease: package,
            mutationID: mutationID, promotedAt: now)
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: id(slot + 3), workspaceID: workspaceID, packageID: package.packageID,
            activeReleaseRecordID: promoted.releaseRecordID, promotionReceiptID: id(slot + 4),
            activePackageReleaseID: package.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256, revision: 1, mutationID: mutationID)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: workspaceID, slot: slot + 5)
        let receipt = try PackagePromotionReceiptV1(
            receiptID: id(slot + 4), workspaceID: workspaceID, promotedRelease: promoted,
            sandboxRun: sandbox, diff: diff, predecessorPointer: nil, resultingPointer: pointer,
            actor: actor, exactHead: sandbox.exactHead, operation: .initialActivation,
            rollbackCompatibility: .activatedForwardFixRequired, mutationID: mutationID, recordedAt: now)
        return try .init(workspaceID: workspaceID, expectedPointerRevision: 0, mutationID: mutationID,
                         bundle: .init(promotedRelease: promoted, sandboxRun: sandbox, semanticDiff: diff,
                                       predecessorPointer: nil, resultingPointer: pointer, actor: actor, receipt: receipt))
    }

    static func workPacket(workspaceID: WorkspaceID) throws -> WorkPacketMutationV1 {
        let mutationID = try mutation(30)
        let item = try WorkPacketItemV1(
            itemID: "c57-schedule-work", kind: .inspection,
            expectedRevision: 1, itemSHA256: digest("c")
        )
        let manifest = try WorkPacketManifestV1(
            manifestID: id(31), packetID: id(32), packetVersion: 1,
            workspaceID: workspaceID, items: [item], packageReleases: [],
            creationBasis: .explicitLocalSelection,
            creator: C26SurveySessionTestSupport.actor(workspaceID: workspaceID, slot: 33),
            createdAt: now, mutationID: mutationID
        )
        return try .init(workspaceID: workspaceID, expectedRevision: 0,
                         mutationID: mutationID, postImage: .appendManifest(manifest))
    }

    static func round(workspaceID: WorkspaceID,
                      package: InspectionPackageReleaseV1) throws -> RoundSessionMutationV1 {
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: .init(package), requiredContent: []
        )
        let item = try RoundItemV1(
            itemID: id(42), order: 0,
            selection: .init(assetID: id(43), siteID: id(44), labelAtSelection: "Schedule round"),
            requirement: requirement
        )
        let session = try RoundSessionV1(
            workspaceID: workspaceID, sessionID: id(45), revision: 1,
            mutationID: mutation(46), state: .draft, transition: .create,
            items: [item],
            recordedBy: C26SurveySessionTestSupport.actor(workspaceID: workspaceID, slot: 47),
            recordedAt: now
        )
        return try .init(workspaceID: workspaceID, expectedRevision: 0,
                         mutationID: session.mutationID, session: session)
    }

    static func calendar(workspaceID: WorkspaceID, revision: UInt64,
                         predecessor: ExceptionCalendarReleaseV1? = nil) throws
        -> ExceptionCalendarReleaseV1 {
        try .init(
            workspaceID: workspaceID, calendarID: id(50), releaseID: id(50 + Int(revision)),
            name: "Schedule calendar r\(revision)", ianaTimeZoneIdentifier: "America/New_York",
            effectiveRange: .init(startsOn: try date(2027, 1, 1), endsOn: try date(2027, 12, 31)),
            baseIncludedWeekdays: ScheduleWeekdayV1.allCases,
            excludedDates: revision == 1 ? [try date(2027, 7, 4)] : [try date(2027, 7, 5)],
            supersedesReleaseID: predecessor?.releaseID,
            predecessorReleaseSHA256: predecessor?.releaseSHA256,
            revision: revision, mutationID: mutation(50 + Int(revision)),
            authoredBy: C26SurveySessionTestSupport.actor(
                workspaceID: workspaceID, slot: 50 + Int(revision)
            ), authoredAt: now.addingTimeInterval(Double(revision))
        )
    }

    static func release(workspaceID: WorkspaceID, definition: SurveyDefinitionReleaseV1,
                        package: InspectionPackageReleaseV1, calendar: ExceptionCalendarReleaseV1,
                        revision: UInt64, predecessor: ScheduleDefinitionReleaseV1? = nil, slotOffset: Int = 0, readyLeadDelta: Int64 = 0, advanced: Bool = true, interval: Int = 1, namespace: UUID? = nil) throws
        -> ScheduleDefinitionReleaseV1 {
        let configuration = AdvancedScheduleConfigurationV1(
            recurrence: .daily(interval: interval), calendarRelease: calendar.reference,
            businessDayAdjustmentPolicy: .nextIncludedDay
        )
        let timeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: "America/New_York", timeZoneRuleSetVersion: "2026a",
            timeZoneRuleSetSHA256: digest("d"), ambiguousTimePolicy: .earlierOffset,
            nonexistentTimePolicy: .shiftForwardByGap,
            calendarBasisID: advanced ? calendar.calendarID.uuidString.lowercased() : ScheduleLimitsV1.allDaysCalendarBasisID,
            calendarBasisRevision: advanced ? calendar.revision : 1,
            calendarBasisSHA256: advanced ? calendar.releaseSHA256 : digest("a")
        )
        return try .init(
            scheduleDefinitionID: id(60), releaseID: id(60 + Int(revision) + slotOffset),
            workspaceID: workspaceID,
            occurrenceIdentityNamespaceID: namespace ?? predecessor?.occurrenceIdentityNamespaceID ?? id(63),
            action: revision == 1 ? .create : .edit, lifecycleState: .active,
            recurrence: advanced ? .advanced(configuration) : .fixedCalendar(.init(
                cadence: .daily, interval: interval,
                anchor: .init(year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
                              hour: 9, minute: 0, second: 0))), timeBasis: timeBasis,
            startsAtUTC: now, generationHorizonDays: 60, maximumGeneratedOccurrences: 8,
            readyLeadSeconds: Int64(3_600 + revision) + readyLeadDelta, overdueGraceSeconds: 7_200,
            subject: .init(kind: .asset, subjectID: id(64), revision: 7, ownerAssetID: nil),
            workDefinition: try .init(kind: .roundSession, definition: definition,
                                      packageRelease: package),
            assignee: nil, supersedesReleaseID: predecessor?.releaseID,
            predecessorReleaseSHA256: predecessor?.releaseSHA256,
            revision: revision, mutationID: mutation(60 + Int(revision) + slotOffset),
            authoredBy: C26SurveySessionTestSupport.actor(
                workspaceID: workspaceID, slot: 60 + Int(revision)
            ), authoredAt: now.addingTimeInterval(Double(revision))
        )
    }

    static func basis(_ localDate: String, release: ScheduleDefinitionReleaseV1, provenance: String? = nil) throws
        -> ResolvedOccurrenceBasisV1 {
        let result = ResolvedOccurrenceBasisV1(
            nominalLocalDate: localDate, nominalLocalTime: "09:00:00",
            resolvedAtUTC: now.addingTimeInterval(86_400), utcOffsetSeconds: -14_400,
            disposition: .unambiguous,
            timeBasisSHA256: try release.timeBasis.canonicalSHA256(),
            adjustmentProvenanceSHA256: provenance ?? (release.timeBasis.calendarBasisID == ScheduleLimitsV1.allDaysCalendarBasisID ? nil : release.timeBasis.calendarBasisSHA256)
        )
        try result.validate(); return result
    }

    static func event(slot: Int, release: ScheduleDefinitionReleaseV1,
                      occurrenceID: OccurrenceIDV1, basis: ResolvedOccurrenceBasisV1,
                      action: OccurrenceHistoryActionV1, predecessor: OccurrenceHistoryEventV1?,
                      work: ScheduledWorkInstanceReferenceV1? = nil, completedAt: Date? = nil,
                      mutationID explicitMutationID: MutationIDV1? = nil,
                      identityPredecessor: OccurrenceIDV1? = nil,
                      identityCompletion: String? = nil) throws -> OccurrenceHistoryEventV1 {
        try .init(
            eventID: id(200 + slot), workspaceID: release.workspaceID,
            occurrenceID: occurrenceID,
            identityPredecessorOccurrenceID: identityPredecessor ?? predecessor?.identityPredecessorOccurrenceID,
            identityCompletionEventSHA256: identityCompletion ?? predecessor?.identityCompletionEventSHA256,
            scheduleRelease: .init(release), action: action,
            nominalBasis: basis, effectiveBasis: basis, workInstance: work,
            completedAt: completedAt, predecessor: predecessor,
            revision: (predecessor?.revision ?? 0) + 1,
            mutationID: try explicitMutationID ?? mutation(200 + slot),
            recordedBy: C26SurveySessionTestSupport.actor(
                workspaceID: release.workspaceID, slot: 200 + slot
            ), recordedAt: now.addingTimeInterval(Double(slot))
        )
    }

    static func override(slot: Int, release: ScheduleDefinitionReleaseV1, revision: UInt64,
                         predecessor: ScheduleOverrideEventV1?, target: ScheduleOverrideTargetV1,
                         kind: ScheduleOccurrenceOverrideKindV1, frontier: String) throws
        -> ScheduleOverrideEventV1 {
        let nominal = target.nominalDate
        return try .init(
            eventID: id(400 + slot), workspaceID: release.workspaceID,
            scheduleRelease: .init(release), target: target, scope: .thisOccurrence,
            kind: kind, effectiveRange: .init(startsOn: nominal, endsOn: nominal),
            replacementDate: kind == .skip ? nil : nominal,
            replacementWindow: kind == .skip ? nil : .init(
                year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
                hour: 11, minute: 30, second: 0
            ), reasonCode: "schedule-test", expectedScheduleRevision: release.revision,
            expectedOverrideFrontierSHA256: frontier,
            supersedesEventID: predecessor?.eventID,
            predecessorEventSHA256: predecessor?.eventSHA256,
            revision: revision, mutationID: mutation(400 + slot),
            recordedBy: C26SurveySessionTestSupport.actor(
                workspaceID: release.workspaceID, slot: 400 + slot
            ), recordedAt: now.addingTimeInterval(Double(slot))
        )
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) throws -> ScheduleLocalDateV1 {
        try .init(year: year, month: month, day: day)
    }

    static func history(commands: [WorkspaceCommandV1], reverseStorage: Bool) throws
        -> MutationHistorySnapshotV1 {
        var records: [MutationHistoryReceiptRecordV1] = []
        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for (offset, command) in commands.enumerated() {
            let value = try record(command: command, workspaceRevision: UInt64(offset),
                                   localSequence: UInt64(offset + 1))
            records.append(value.record)
            for image in value.images { terminal[try image.identity] = image.revision }
        }
        let snapshot = MutationHistorySnapshotV1(
            workspaceRevision: UInt64(commands.count), lastLocalSequence: UInt64(commands.count),
            receipts: reverseStorage ? Array(records.reversed()) : records,
            quarantines: [], entityRevisions: terminal.map {
                .init(identity: $0.key, revision: $0.value)
            }.sorted { $0.identity.stableKey < $1.identity.stableKey }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(snapshot)
        return snapshot
    }

    static func record(command: WorkspaceCommandV1, workspaceRevision: UInt64,
                       localSequence: UInt64) throws -> Record {
        let binding = try bindings(command)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: binding.workspaceID, generationID: generationID,
            writerInstanceID: writerID, workspaceRevision: workspaceRevision,
            entityRevisions: binding.expected
        )
        let envelope = try MutationEnvelopeV1(
            request: .init(mutationID: binding.mutationID, expectedRevision: expected,
                           command: command),
            identity: .init(workspaceID: binding.workspaceID, replicaID: replicaID)
        )
        let resulting = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
            workspaceID: binding.workspaceID, generationID: generationID,
            writerInstanceID: writerID, workspaceRevision: workspaceRevision + 1,
            entityRevisions: try binding.images.map {
                .init(identity: try $0.identity, revision: $0.revision)
            }
        ))
        let receipt = try MutationReceiptV1(
            identity: .init(workspaceID: binding.workspaceID, replicaID: replicaID,
                            localSequence: localSequence),
            envelope: envelope, resultingRevision: resulting,
            postImages: binding.images,
            committedAt: now.addingTimeInterval(Double(localSequence))
        )
        return Record(record: .init(
            envelopeData: try envelope.canonicalData(), receiptData: try receipt.canonicalData(),
            reversalBasisData: nil, semanticReversalData: nil
        ), images: binding.images)
    }

    static func bindings(_ command: WorkspaceCommandV1) throws -> Bindings {
        let workspaceID: WorkspaceID; let mutationID: MutationIDV1
        let identities: [WorkspaceEntityIdentityV1]; let revisions: [UInt64]
        let images: [MutationPostImageV1]
        switch command {
        case let .applyPackagePromotion(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = try value.concurrencyIdentities
            revisions = try identities.map { try value.expectedRevision(for: $0) }
            images = try value.mutationPostImages
        case let .applySurveyDefinition(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = try value.concurrencyIdentities
            revisions = try identities.map { try value.expectedRevision(for: $0) }
            images = try value.mutationPostImages
        case let .applyWorkPacket(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = [try value.concurrencyIdentity]; revisions = [value.expectedRevision]
            images = [try value.postImage.mutationPostImage]
        case let .applyRoundSession(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = [try value.concurrencyIdentity]; revisions = [value.expectedRevision]
            images = [try value.mutationPostImage]
        case let .applySchedule(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = try value.concurrencyIdentities
            revisions = try identities.map { try value.expectedRevision(for: $0) }
            images = try value.mutationPostImages
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
        return .init(workspaceID: workspaceID, mutationID: mutationID,
                     expected: zip(identities, revisions).map {
                         .init(identity: $0.0, revision: $0.1)
                     }, images: images)
    }

    static func replacing(_ history: MutationHistorySnapshotV1,
                          receipts: [MutationHistoryReceiptRecordV1]? = nil,
                          quarantines: [MutationHistoryQuarantineRecordV1]? = nil)
        -> MutationHistorySnapshotV1 {
        .init(workspaceRevision: history.workspaceRevision,
              lastLocalSequence: history.lastLocalSequence,
              receipts: receipts ?? history.receipts,
              quarantines: quarantines ?? history.quarantines,
              entityRevisions: history.entityRevisions)
    }

    static func removing(_ history: MutationHistorySnapshotV1, mutationID: MutationIDV1)
        -> MutationHistorySnapshotV1 {
        let kept = history.receipts.filter {
            (try? MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).mutationID) != mutationID
        }
        return replacing(history, receipts: kept)
    }
}
