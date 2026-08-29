import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C25SurveyDefinitionTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_500)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2500000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func digest(_ byte: Character = "a") -> String {
        String(repeating: byte, count: 64)
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func actor(
        workspaceID: WorkspaceID = workspace(),
        slot: Int = 300,
        responsibility: ResponsibilityKindV1 = .recordedBy
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C25 local survey author"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: responsibility,
            displayNameAtTime: reference.displayName,
            capturedAt: fixedDate
        )
    }

    static func fact(
        _ factID: String = "fact-a",
        required: Bool = true,
        visibility: SurveyVisibilityExpressionV1? = nil,
        defaultValue: ResponseValueV1? = nil,
        payload: SurveyFactPayloadV1 = .shortText(.init(maximumUTF8Bytes: 128))
    ) -> FactDefinitionV1 {
        FactDefinitionV1(
            factID: factID,
            labelLocalizationKey: "survey.\(factID).label",
            accessibilityLabelLocalizationKey: "survey.\(factID).accessibility",
            helpLocalizationKey: "survey.\(factID).help",
            required: required,
            defaultValue: defaultValue,
            visibility: visibility,
            payload: payload
        )
    }

    static func section(
        sectionID: String = "section",
        ordinal: Int = 0,
        facts: [FactDefinitionV1]
    ) -> SurveySectionV1 {
        SurveySectionV1(
            sectionID: sectionID,
            titleLocalizationKey: "survey.section.title",
            accessibilityHeadingLocalizationKey: "survey.section.heading",
            ordinal: ordinal,
            facts: facts.sorted { $0.factID < $1.factID }
        )
    }

    static func release(
        kind: ActivityKindV1 = .survey,
        releaseSlot: Int = 10,
        definitionID: UUID = id(1),
        workspaceID: WorkspaceID = workspace(),
        revision: UInt64 = 1,
        supersedesReleaseID: UUID? = nil,
        facts: [FactDefinitionV1] = [fact()],
        sections: [SurveySectionV1]? = nil,
        completionRules: [CompletionRuleV1]? = nil
    ) throws -> SurveyDefinitionReleaseV1 {
        let sortedFacts = facts.sorted { $0.factID < $1.factID }
        let releaseSections = sections ?? [section(facts: sortedFacts)]
        let releaseRules = completionRules ?? [
            CompletionRuleV1(
                ruleID: "complete",
                expression: .allRequiredVisibleFactsAnswered,
                failureLocalizationKey: "survey.completion.failure"
            )
        ]
        return try SurveyDefinitionReleaseV1(
            releaseID: id(releaseSlot),
            workspaceID: workspaceID,
            definitionID: definitionID,
            activityKind: kind,
            ownerPackageID: "c25.guided.template",
            sections: releaseSections,
            completionRules: releaseRules,
            claimsProfile: ClaimsProfileV1(
                profileID: "claims",
                activityKind: kind,
                allowedClaimKeys: [],
                forbiddenClaimKeys: ["approval", "release"],
                limitationLocalizationKeys: ["survey.claims.limitation"]
            ),
            reportProjection: SurveyReportProjectionV1(
                projectionID: "report",
                projectionVersion: "1",
                headingLocalizationKey: "survey.report.heading",
                emptyValueLocalizationKey: "survey.report.empty",
                sectionIDs: ["section"],
                includedFactIDs: sortedFacts.map(\.factID).sorted()
            ),
            localizationReleaseSHA256: digest("b"),
            supersedesReleaseID: supersedesReleaseID,
            revision: revision,
            mutationID: try mutation(700 + releaseSlot),
            authoredBy: try actor(workspaceID: workspaceID, slot: 300 + releaseSlot),
            authoredAt: fixedDate.addingTimeInterval(Double(revision))
        )
    }

    static func event(
        release: SurveyDefinitionReleaseV1,
        action: SurveyDefinitionLifecycleActionV1,
        priorState: SurveyDefinitionLifecycleStateV1?,
        resultingState: SurveyDefinitionLifecycleStateV1,
        eventSlot: Int,
        predecessor: SurveyDefinitionLifecycleEventV1? = nil,
        sourceDefinitionID: UUID? = nil,
        sourceReleaseID: UUID? = nil,
        sourceReleaseSHA256: String? = nil,
        sourceArchiveSHA256: String? = nil,
        semanticDiffSHA256: String? = nil,
        revision: UInt64
    ) throws -> SurveyDefinitionLifecycleEventV1 {
        try SurveyDefinitionLifecycleEventV1(
            eventID: id(eventSlot),
            workspaceID: release.workspaceID,
            definitionID: release.definitionID,
            action: action,
            priorState: priorState,
            resultingState: resultingState,
            release: try SurveyDefinitionReleaseReferenceV1(release),
            predecessorEventID: predecessor?.eventID,
            predecessorEventSHA256: predecessor?.eventSHA256,
            sourceDefinitionID: sourceDefinitionID,
            sourceReleaseID: sourceReleaseID,
            sourceReleaseSHA256: sourceReleaseSHA256,
            sourceArchiveSHA256: sourceArchiveSHA256,
            semanticDiffSHA256: semanticDiffSHA256,
            actor: try actor(workspaceID: release.workspaceID, slot: 500 + eventSlot),
            recordedAt: fixedDate.addingTimeInterval(100 + Double(revision)),
            revision: revision,
            mutationID: try mutation(1_000 + eventSlot)
        )
    }

    static func extraction(
        for manifest: SurveyTemplateArchiveManifestV1,
        archiveSHA256: String? = nil,
        indexEntries: [StreamingArchiveEntryV1]? = nil
    ) -> StreamingArchiveExtractionV1 {
        let entries = indexEntries ?? manifest.entries.map {
            StreamingArchiveEntryV1(
                path: $0.path,
                mimeType: $0.mediaType,
                compression: .stored,
                storedByteCount: $0.compressedByteCount,
                uncompressedByteCount: $0.byteCount,
                storedSHA256: $0.storedSHA256,
                contentSHA256: $0.sha256
            )
        }
        let index = StreamingArchiveIndexV1(
            archiveSchemaVersion: StreamingArchiveIndexV1.currentSchemaVersion,
            entries: entries,
            storedPayloadByteCount: entries.reduce(Int64(0)) { $0 + $1.storedByteCount },
            uncompressedPayloadByteCount: entries.reduce(Int64(0)) { $0 + $1.uncompressedByteCount }
        )
        return StreamingArchiveExtractionV1(
            archiveURL: URL(fileURLWithPath: "/tmp/c25-survey-template.arsurveytemplate"),
            extractedDirectoryURL: URL(fileURLWithPath: "/tmp/c25-survey-template", isDirectory: true),
            archiveSHA256: archiveSHA256 ?? manifest.archiveSHA256,
            index: index
        )
    }

    static func identity(
        release: SurveyDefinitionReleaseV1,
        state: SurveyDefinitionLifecycleStateV1,
        event: SurveyDefinitionLifecycleEventV1,
        createdBy: ActorSnapshotV1
    ) throws -> SurveyDefinitionIdentityV1 {
        try SurveyDefinitionIdentityV1(
            definitionID: release.definitionID,
            workspaceID: release.workspaceID,
            activityKind: release.activityKind,
            lifecycleState: state,
            currentRelease: try SurveyDefinitionReleaseReferenceV1(release),
            latestLifecycleEventID: event.eventID,
            latestLifecycleEventSHA256: event.eventSHA256,
            createdBy: createdBy,
            createdAt: fixedDate,
            revision: event.revision,
            mutationID: event.mutationID
        )
    }

    static func decodedCorpus() throws -> C25SurveyDefinitionCorpus {
        let bundle = Bundle(for: V9_39SurveyDefinitionTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C25SurveyDefinitionCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/SurveyDefinitions"
            ) ?? bundle.url(
                forResource: "V22P03C25SurveyDefinitionCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            C25SurveyDefinitionCorpus.self,
            from: Data(contentsOf: url)
        )
    }
}

private struct C25RejectingSurveyDefinitionWriter: SurveyDefinitionWritingV1 {
    func acceptedSurveyDefinitionMutation(
        _ mutationID: MutationIDV1
    ) async throws -> SurveyDefinitionMutationReceiptV1? {
        nil
    }

    func applySurveyDefinition(
        _ mutation: SurveyDefinitionMutationV1
    ) async throws -> SurveyDefinitionMutationReceiptV1 {
        throw SurveyDefinitionFailureV1.invalidTransition
    }
}

private struct C25SurveyDefinitionCorpus: Decodable {
    struct Selector: Decodable {
        let id: String
        let selector: String
        let focus: String
    }

    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let ordinal: Int
    let phase: String
    let previousCardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let currentSyncPersistentModelCount: Int
    let evidenceSelectors: [Selector]
    let evidenceIDs: [String]
    let coverage: [String]
    let activityKinds: [ActivityKindV1]
    let completionSemantics: [ActivityCompletionSemanticV1]
    let lifecycleStates: [SurveyDefinitionLifecycleStateV1]
    let lifecycleActions: [SurveyDefinitionLifecycleActionV1]
    let fieldKinds: [SurveyFieldKindV1]
    let semanticCompatibility: [SurveySemanticCompatibilityV1]
    let adoptionDispositions: [SurveyAdoptionDispositionV1]
    let persistentFamilies: [String]
    let lifecycleEventPersistence: String
    let semanticDiffPersistence: String
    let adoptionPreviewPersistence: String
    let quarantinePersistence: String
    let writer: String
    let importDisposition: String
    let exchangeExtension: String
    let archiveMaximumEntries: Int
    let archiveEntryLimitBytes: Int64
    let archiveAggregateLimitBytes: Int64
    let archivePathLimitBytes: Int
    let archiveMaximumDepth: Int
    let archiveCompressionRatio: Int64
    let archiveCanonicalBytes: Int
    let localPreferenceKeys: [String]
    let localPreferenceExclusions: [String]
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let lifecycleConsumers: [String]
    let forbiddenProductionSymbols: [String]
    let noSecondWriter: Bool
    let noSecondStore: Bool
    let immutableReleasedBytes: Bool
    let noSilentUpgrade: Bool
    let quarantinesImports: Bool
    let oldOrNewOnly: Bool
    let noC26OrC47: Bool
}

final class V9_39SurveyDefinitionTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C25G01FiveActivityKindsHaveStableImmutableLifecycleSemantics() throws {
        let corpus = try C25SurveyDefinitionTestSupport.decodedCorpus()
        XCTAssertEqual(corpus.schema, "V22P03C25SurveyDefinitionCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.corpusID, "v22-p03-c25-survey-definition-v1")
        XCTAssertEqual(corpus.cardID, "V23-P03-C25")
        XCTAssertEqual(corpus.ordinal, 62)
        XCTAssertEqual(corpus.phase, "P03")
        XCTAssertEqual(corpus.previousCardID, "V23-P03-C24")
        XCTAssertEqual(corpus.records, 23)
        XCTAssertEqual(corpus.recordsSchemaVersion, 23)
        XCTAssertEqual(corpus.persistentSchemaVersion, 24)
        XCTAssertEqual(corpus.persistentModelCount, 87)
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), corpus.evidenceIDs)
        XCTAssertEqual(corpus.coverage, ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"])
        XCTAssertEqual(corpus.activityKinds, ActivityKindV1.allCases)
        XCTAssertEqual(corpus.completionSemantics, [
            .criterionAssessment, .typedFactCollection, .maintenanceWorkRecord,
            .remedyWorkRecord, .subsequentOperationalObservation
        ])
        XCTAssertEqual(corpus.lifecycleStates, SurveyDefinitionLifecycleStateV1.allCases)
        XCTAssertEqual(corpus.lifecycleActions, SurveyDefinitionLifecycleActionV1.allCases)
        XCTAssertEqual(corpus.fieldKinds.count, SurveyFieldKindV1.allCases.count)
        XCTAssertEqual(corpus.fieldKinds, SurveyFieldKindV1.allCases)
        XCTAssertEqual(SurveySemanticChangeKindV1.allCases, [
            .sectionAdded, .sectionRemoved, .sectionChanged, .factAdded,
            .factRemoved, .factChanged, .completionRuleChanged,
            .claimsProfileChanged, .reportProjectionChanged, .localizationChanged,
            .activityKindChanged
        ])
        XCTAssertEqual(corpus.semanticCompatibility, [
            .noChange, .additiveDraftSafe, .draftMigrationRequired,
            .activeWorkIncompatible, .invalid
        ])
        XCTAssertEqual(corpus.adoptionDispositions, [
            .noChange, .explicitDraftAdoptionAvailable, .activeWorkPinned, .blocked
        ])

        let semantics = ActivityKindV1.allCases.map { ActivityKindSemanticsV1(kind: $0) }
        XCTAssertEqual(semantics.map(\.completion), corpus.completionSemantics)
        XCTAssertTrue(semantics.first(where: { $0.kind == .inspection })!.mayClaimInspectionResult)
        XCTAssertTrue(semantics.first(where: { $0.kind == .repair })!.mayClaimRepairPerformed)
        XCTAssertTrue(semantics.allSatisfy { !$0.mayClaimReleaseToService })

        for (offset, kind) in ActivityKindV1.allCases.enumerated() {
            let release = try C25SurveyDefinitionTestSupport.release(
                kind: kind,
                releaseSlot: 10 + offset
            )
            let event = try C25SurveyDefinitionTestSupport.event(
                release: release,
                action: .createDraft,
                priorState: nil,
                resultingState: .draft,
                eventSlot: 30 + offset,
                revision: 1
            )
            try release.validate()
            try event.validate(release: release)
            XCTAssertEqual(release.activityKind, kind)
            XCTAssertEqual(event.resultingState, .draft)
        }

        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies, corpus.persistentFamilies)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.lifecycleEventPersistence, corpus.lifecycleEventPersistence)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, corpus.writer)
        XCTAssertEqual(PersistentSchemaV24.models.count, corpus.persistentModelCount)
        XCTAssertEqual(PersistentSchemaV24.models.count, PersistentSchemaV23.models.count + 2)
        XCTAssertEqual(CurrentSyncClassificationCatalogV1.activePersistentModelNames.count, corpus.currentSyncPersistentModelCount)
    }

    func testV23P03C25A01ExplicitDraftAdoptionAndQuarantinedExchangeRemainTyped() async throws {
        let corpus = try C25SurveyDefinitionTestSupport.decodedCorpus()
        let source = try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 50,
            facts: [C25SurveyDefinitionTestSupport.fact("fact-a")]
        )
        let target = try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 51,
            revision: 2,
            supersedesReleaseID: source.releaseID,
            facts: [
                C25SurveyDefinitionTestSupport.fact("fact-a"),
                C25SurveyDefinitionTestSupport.fact("fact-b", required: false)
            ]
        )
        try target.validateSuccessor(of: source)
        let diff = try SurveyDefinitionSemanticDiffV1(source: source, target: target)
        try diff.validate(source: source, target: target)
        XCTAssertEqual(diff.compatibility, .additiveDraftSafe)
        XCTAssertEqual(diff.changes.map(\.kind), [.factAdded])
        XCTAssertEqual(corpus.semanticDiffPersistence, SurveyDefinitionLifecycleV1.semanticDiffPersistence)

        let affectedDraftID = C25SurveyDefinitionTestSupport.id(900)
        let preview = try SurveyDefinitionAdoptionPreviewV1(
            workspaceID: source.workspaceID,
            diff: diff,
            affectedDraftIDs: [affectedDraftID],
            pinnedActiveWorkCount: 0,
            generatedAt: C25SurveyDefinitionTestSupport.fixedDate
        )
        XCTAssertEqual(preview.disposition, .explicitDraftAdoptionAvailable)
        let pinnedPreview = try SurveyDefinitionAdoptionPreviewV1(
            workspaceID: source.workspaceID,
            diff: diff,
            affectedDraftIDs: [affectedDraftID],
            pinnedActiveWorkCount: 1,
            generatedAt: C25SurveyDefinitionTestSupport.fixedDate
        )
        XCTAssertEqual(pinnedPreview.disposition, .activeWorkPinned)
        try preview.validate(
            source: source,
            target: target,
            currentDraftIDs: [affectedDraftID],
            currentActiveWorkCount: 0
        )
        try pinnedPreview.validate(
            source: source,
            target: target,
            currentDraftIDs: [affectedDraftID],
            currentActiveWorkCount: 1
        )

        let draft = try C25SurveyDefinitionTestSupport.event(
            release: source,
            action: .createDraft,
            priorState: nil,
            resultingState: .draft,
            eventSlot: 60,
            revision: 1
        )
        let adoption = try C25SurveyDefinitionTestSupport.event(
            release: target,
            action: .adoptUpgradeAsDraft,
            priorState: .draft,
            resultingState: .draft,
            eventSlot: 61,
            predecessor: draft,
            semanticDiffSHA256: diff.diffSHA256,
            revision: 2
        )
        try adoption.validateSuccessor(of: draft, release: target)
        let createdBy = try C25SurveyDefinitionTestSupport.actor(
            workspaceID: source.workspaceID,
            slot: 1_200
        )
        let previousIdentity = try C25SurveyDefinitionTestSupport.identity(
            release: source,
            state: .draft,
            event: draft,
            createdBy: createdBy
        )
        let adoptedIdentity = try C25SurveyDefinitionTestSupport.identity(
            release: target,
            state: .draft,
            event: adoption,
            createdBy: createdBy
        )
        let coordinator = SurveyDefinitionCoordinatorV1(
            writer: C25RejectingSurveyDefinitionWriter()
        )
        do {
            _ = try await coordinator.applySuccessor(
                previousIdentity: previousIdentity,
                previousRelease: source,
                previousEvent: draft,
                identity: adoptedIdentity,
                release: target,
                event: adoption
            )
            XCTFail("generic successor application must require dedicated adoption validation")
        } catch let error as SurveyDefinitionFailureV1 {
            XCTAssertEqual(error, .stalePreview)
        }

        let previewData = try SurveyDefinitionCanonicalCodecV1.encode(preview)
        let previewText = try XCTUnwrap(String(data: previewData, encoding: .utf8))
        let forgedPreview = try SurveyDefinitionCanonicalCodecV1.decode(
            SurveyDefinitionAdoptionPreviewV1.self,
            from: Data(previewText.replacingOccurrences(
                of: preview.previewSHA256,
                with: C25SurveyDefinitionTestSupport.digest("c")
            ).utf8)
        )
        do {
            _ = try await coordinator.adoptUpgradeAsDraft(
                forgedPreview,
                currentSource: source,
                currentTarget: target,
                previousIdentity: previousIdentity,
                previousEvent: draft,
                currentDraftIDs: [affectedDraftID],
                currentActiveWorkCount: 0,
                identity: adoptedIdentity,
                event: adoption
            )
            XCTFail("forged adoption preview must be rejected")
        } catch let error as SurveyDefinitionFailureV1 {
            XCTAssertEqual(error, .stalePreview)
        }

        do {
            _ = try await coordinator.adoptUpgradeAsDraft(
                pinnedPreview,
                currentSource: source,
                currentTarget: target,
                previousIdentity: previousIdentity,
                previousEvent: draft,
                currentDraftIDs: [affectedDraftID],
                currentActiveWorkCount: 0,
                identity: adoptedIdentity,
                event: adoption
            )
            XCTFail("stale adoption preview must be rejected")
        } catch let error as SurveyDefinitionFailureV1 {
            XCTAssertEqual(error, .stalePreview)
        }

        let mismatchedEvent = try C25SurveyDefinitionTestSupport.event(
            release: target,
            action: .adoptUpgradeAsDraft,
            priorState: .draft,
            resultingState: .draft,
            eventSlot: 64,
            predecessor: draft,
            semanticDiffSHA256: C25SurveyDefinitionTestSupport.digest("f"),
            revision: 2
        )
        let mismatchedIdentity = try C25SurveyDefinitionTestSupport.identity(
            release: target,
            state: .draft,
            event: mismatchedEvent,
            createdBy: createdBy
        )
        do {
            _ = try await coordinator.adoptUpgradeAsDraft(
                pinnedPreview,
                currentSource: source,
                currentTarget: target,
                previousIdentity: previousIdentity,
                previousEvent: draft,
                currentDraftIDs: [affectedDraftID],
                currentActiveWorkCount: 1,
                identity: mismatchedIdentity,
                event: mismatchedEvent
            )
            XCTFail("mismatched event semantic diff must be rejected")
        } catch let error as SurveyDefinitionFailureV1 {
            XCTAssertEqual(error, .stalePreview)
        }

        do {
            _ = try await coordinator.adoptUpgradeAsDraft(
                pinnedPreview,
                currentSource: source,
                currentTarget: target,
                previousIdentity: previousIdentity,
                previousEvent: draft,
                currentDraftIDs: [affectedDraftID],
                currentActiveWorkCount: 1,
                identity: adoptedIdentity,
                event: adoption
            )
            XCTFail("test writer should stop after validated pinned adoption")
        } catch let error as SurveyDefinitionFailureV1 {
            XCTAssertEqual(error, .invalidTransition)
        }

        let publish = try C25SurveyDefinitionTestSupport.event(
            release: target,
            action: .publish,
            priorState: .draft,
            resultingState: .published,
            eventSlot: 62,
            predecessor: adoption,
            revision: 3
        )
        let retire = try C25SurveyDefinitionTestSupport.event(
            release: target,
            action: .retire,
            priorState: .published,
            resultingState: .retired,
            eventSlot: 63,
            predecessor: publish,
            revision: 4
        )
        try publish.validateSuccessor(of: adoption, release: target)
        try retire.validateSuccessor(of: publish, release: target)

        let binding = try CheckRunnerSurveyDefinitionStartBindingV1(
            release: target,
            lifecycleState: .published
        )
        XCTAssertNoThrow(try binding.validate())
        XCTAssertThrowsError(try CheckRunnerSurveyDefinitionStartBindingV1(release: target, lifecycleState: .draft))
        XCTAssertThrowsError(try CheckRunnerSurveyDefinitionStartBindingV1(release: target, lifecycleState: .retired))

        let entry = SurveyTemplateArchiveEntryV1(
            path: "survey.json",
            mediaType: "application-json",
            byteCount: 42,
            sha256: C25SurveyDefinitionTestSupport.digest("c")
        )
        let manifest = try SurveyTemplateArchiveManifestV1(
            archiveID: C25SurveyDefinitionTestSupport.id(70),
            definitionRelease: try SurveyDefinitionReleaseReferenceV1(source),
            entries: [entry],
            archiveByteCount: 42,
            archiveSHA256: C25SurveyDefinitionTestSupport.digest("d")
        )
        try manifest.validate()
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.maximumEntries, corpus.archiveMaximumEntries)
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.maximumArchiveBytes, corpus.archiveAggregateLimitBytes)
        XCTAssertEqual(SurveyTemplateArchiveEntryV1.maximumExpandedBytes, corpus.archiveEntryLimitBytes)
        XCTAssertEqual(SurveyTemplateArchiveEntryV1.maximumPathUTF8Bytes, corpus.archivePathLimitBytes)
        XCTAssertEqual(SurveyTemplateArchiveEntryV1.maximumPathDepth, corpus.archiveMaximumDepth)
        XCTAssertEqual(SurveyTemplateArchiveEntryV1.maximumCompressionRatio, corpus.archiveCompressionRatio)
        let atAggregateLimitEntries = [
            SurveyTemplateArchiveEntryV1(path: "aggregate/limit-a.json", mediaType: "application-json", byteCount: corpus.archiveEntryLimitBytes, sha256: C25SurveyDefinitionTestSupport.digest("a")),
            SurveyTemplateArchiveEntryV1(path: "aggregate/limit-b.json", mediaType: "application-json", byteCount: corpus.archiveEntryLimitBytes, sha256: C25SurveyDefinitionTestSupport.digest("b"))
        ]
        let atAggregateLimitManifest = SurveyTemplateArchiveManifestV1(
            schemaVersion: SurveyTemplateArchiveManifestV1.schemaVersion,
            archiveID: C25SurveyDefinitionTestSupport.id(76),
            definitionRelease: try SurveyDefinitionReleaseReferenceV1(source),
            entries: atAggregateLimitEntries,
            archiveByteCount: corpus.archiveAggregateLimitBytes,
            archiveSHA256: C25SurveyDefinitionTestSupport.digest("c"),
            manifestSHA256: C25SurveyDefinitionTestSupport.digest("d")
        )
        XCTAssertNoThrow(try atAggregateLimitManifest.validate())
        let oversizedEntry = SurveyTemplateArchiveEntryV1(
            path: "oversized.json",
            mediaType: "application-json",
            byteCount: corpus.archiveEntryLimitBytes + 1,
            sha256: C25SurveyDefinitionTestSupport.digest("a")
        )
        XCTAssertThrowsError(try oversizedEntry.validate())
        let tooManyEntries = (0..<corpus.archiveMaximumEntries + 1).map { index in
            SurveyTemplateArchiveEntryV1(
                path: "entries/entry-\(String(format: "%03d", index)).json",
                mediaType: "application-json",
                byteCount: 1,
                sha256: C25SurveyDefinitionTestSupport.digest("a")
            )
        }
        let tooManyManifest = SurveyTemplateArchiveManifestV1(
            schemaVersion: SurveyTemplateArchiveManifestV1.schemaVersion,
            archiveID: C25SurveyDefinitionTestSupport.id(74),
            definitionRelease: try SurveyDefinitionReleaseReferenceV1(source),
            entries: tooManyEntries,
            archiveByteCount: Int64(tooManyEntries.count),
            archiveSHA256: C25SurveyDefinitionTestSupport.digest("b"),
            manifestSHA256: C25SurveyDefinitionTestSupport.digest("c")
        )
        XCTAssertThrowsError(try tooManyManifest.validate())
        let tooLargeAggregateEntries = [
            SurveyTemplateArchiveEntryV1(path: "aggregate/a.json", mediaType: "application-json", byteCount: corpus.archiveEntryLimitBytes, sha256: C25SurveyDefinitionTestSupport.digest("a")),
            SurveyTemplateArchiveEntryV1(path: "aggregate/b.json", mediaType: "application-json", byteCount: corpus.archiveEntryLimitBytes, sha256: C25SurveyDefinitionTestSupport.digest("b")),
            SurveyTemplateArchiveEntryV1(path: "aggregate/c.json", mediaType: "application-json", byteCount: 1, sha256: C25SurveyDefinitionTestSupport.digest("c"))
        ]
        let tooLargeAggregateManifest = SurveyTemplateArchiveManifestV1(
            schemaVersion: SurveyTemplateArchiveManifestV1.schemaVersion,
            archiveID: C25SurveyDefinitionTestSupport.id(75),
            definitionRelease: try SurveyDefinitionReleaseReferenceV1(source),
            entries: tooLargeAggregateEntries,
            archiveByteCount: corpus.archiveAggregateLimitBytes + 1,
            archiveSHA256: C25SurveyDefinitionTestSupport.digest("d"),
            manifestSHA256: C25SurveyDefinitionTestSupport.digest("e")
        )
        XCTAssertThrowsError(try tooLargeAggregateManifest.validate())
        let tooLongPath = SurveyTemplateArchiveEntryV1(
            path: String(repeating: "a", count: corpus.archivePathLimitBytes + 1),
            mediaType: "application-json",
            byteCount: 1,
            sha256: C25SurveyDefinitionTestSupport.digest("f")
        )
        XCTAssertThrowsError(try tooLongPath.validate())
        let tooDeepPath = SurveyTemplateArchiveEntryV1(
            path: (0..<(corpus.archiveMaximumDepth + 1)).map { _ in "segment" }.joined(separator: "/"),
            mediaType: "application-json",
            byteCount: 1,
            sha256: C25SurveyDefinitionTestSupport.digest("a")
        )
        XCTAssertThrowsError(try tooDeepPath.validate())
        let tooWideRatio = SurveyTemplateArchiveEntryV1(
            path: "ratio.json",
            mediaType: "application-json",
            byteCount: corpus.archiveCompressionRatio + 1,
            sha256: C25SurveyDefinitionTestSupport.digest("a"),
            compressedByteCount: 1
        )
        XCTAssertThrowsError(try tooWideRatio.validate())
        let nonIntegralMaximumRatio = SurveyTemplateArchiveEntryV1(
            path: "ratio-remainder.json",
            mediaType: "application-json",
            byteCount: corpus.archiveCompressionRatio * 2 + 1,
            sha256: C25SurveyDefinitionTestSupport.digest("b"),
            compressedByteCount: 2
        )
        XCTAssertThrowsError(try nonIntegralMaximumRatio.validate())
        let assessment = try SurveyTemplateQuarantineAssessmentV1(
            quarantineID: C25SurveyDefinitionTestSupport.id(71),
            archiveSHA256: manifest.archiveSHA256,
            manifestSHA256: manifest.manifestSHA256,
            candidateReleaseSHA256: source.releaseSHA256,
            disposition: .draftCandidate,
            findings: [],
            assessedAt: C25SurveyDefinitionTestSupport.fixedDate
        )
        try assessment.validate()
        let extraction = C25SurveyDefinitionTestSupport.extraction(for: manifest)
        let quarantineCandidate = try SurveyTemplateQuarantineCandidateV1(
            extraction: extraction,
            manifest: manifest,
            assessment: assessment,
            importedRelease: source
        )
        XCTAssertEqual(quarantineCandidate.manifest, manifest)
        XCTAssertEqual(quarantineCandidate.assessment, assessment)
        XCTAssertEqual(quarantineCandidate.importedRelease, source)

        let forgedManifest = SurveyTemplateArchiveManifestV1(
            schemaVersion: manifest.schemaVersion,
            archiveID: manifest.archiveID,
            definitionRelease: manifest.definitionRelease,
            entries: manifest.entries,
            archiveByteCount: manifest.archiveByteCount,
            archiveSHA256: manifest.archiveSHA256,
            manifestSHA256: C25SurveyDefinitionTestSupport.digest("0")
        )
        XCTAssertThrowsError(try SurveyTemplateQuarantineCandidateV1(
            extraction: extraction,
            manifest: forgedManifest,
            assessment: assessment,
            importedRelease: source
        ))

        let forgedAssessment = SurveyTemplateQuarantineAssessmentV1(
            quarantineID: assessment.quarantineID,
            archiveSHA256: assessment.archiveSHA256,
            manifestSHA256: assessment.manifestSHA256,
            candidateReleaseSHA256: assessment.candidateReleaseSHA256,
            disposition: assessment.disposition,
            findings: assessment.findings,
            assessedAt: assessment.assessedAt,
            assessmentSHA256: C25SurveyDefinitionTestSupport.digest("0")
        )
        XCTAssertThrowsError(try SurveyTemplateQuarantineCandidateV1(
            extraction: extraction,
            manifest: manifest,
            assessment: forgedAssessment,
            importedRelease: source
        ))

        let mismatchedArchiveExtraction = C25SurveyDefinitionTestSupport.extraction(
            for: manifest,
            archiveSHA256: C25SurveyDefinitionTestSupport.digest("0")
        )
        XCTAssertThrowsError(try SurveyTemplateQuarantineCandidateV1(
            extraction: mismatchedArchiveExtraction,
            manifest: manifest,
            assessment: assessment,
            importedRelease: source
        ))

        let mismatchedIndexEntry = StreamingArchiveEntryV1(
            path: entry.path,
            mimeType: entry.mediaType,
            compression: .stored,
            storedByteCount: entry.compressedByteCount,
            uncompressedByteCount: entry.byteCount,
            storedSHA256: entry.storedSHA256,
            contentSHA256: C25SurveyDefinitionTestSupport.digest("0")
        )
        let mismatchedIndexExtraction = C25SurveyDefinitionTestSupport.extraction(
            for: manifest,
            indexEntries: [mismatchedIndexEntry]
        )
        XCTAssertThrowsError(try SurveyTemplateQuarantineCandidateV1(
            extraction: mismatchedIndexExtraction,
            manifest: manifest,
            assessment: assessment,
            importedRelease: source
        ))

        let mismatchedReleaseManifest = try SurveyTemplateArchiveManifestV1(
            archiveID: C25SurveyDefinitionTestSupport.id(77),
            definitionRelease: try SurveyDefinitionReleaseReferenceV1(target),
            entries: [entry],
            archiveByteCount: 42,
            archiveSHA256: manifest.archiveSHA256
        )
        let mismatchedReleaseAssessment = try SurveyTemplateQuarantineAssessmentV1(
            quarantineID: C25SurveyDefinitionTestSupport.id(78),
            archiveSHA256: mismatchedReleaseManifest.archiveSHA256,
            manifestSHA256: mismatchedReleaseManifest.manifestSHA256,
            candidateReleaseSHA256: source.releaseSHA256,
            disposition: .draftCandidate,
            findings: [],
            assessedAt: C25SurveyDefinitionTestSupport.fixedDate
        )
        XCTAssertThrowsError(try SurveyTemplateQuarantineCandidateV1(
            extraction: C25SurveyDefinitionTestSupport.extraction(for: mismatchedReleaseManifest),
            manifest: mismatchedReleaseManifest,
            assessment: mismatchedReleaseAssessment,
            importedRelease: source
        ))
        XCTAssertEqual(corpus.quarantinePersistence, SurveyDefinitionLifecycleV1.quarantinePersistence)
        XCTAssertEqual(corpus.importDisposition, SurveyDefinitionLifecycleV1.importDisposition)
        let imported = try C25SurveyDefinitionTestSupport.event(
            release: try C25SurveyDefinitionTestSupport.release(releaseSlot: 72, definitionID: C25SurveyDefinitionTestSupport.id(72)),
            action: .importAsDraft,
            priorState: nil,
            resultingState: .draft,
            eventSlot: 73,
            sourceArchiveSHA256: manifest.archiveSHA256,
            revision: 1
        )
        XCTAssertEqual(imported.action, .importAsDraft)
        XCTAssertEqual(imported.sourceArchiveSHA256, manifest.archiveSHA256)

        let settings = try SettingsRegistryV1.current()
        let recent = try settings.descriptor(for: "device.recentInputMemory")
        XCTAssertEqual(recent.scope, .deviceLocal)
        XCTAssertEqual(recent.backup, .excludedDeviceLocal)
        XCTAssertEqual(recent.privacy, .devicePreferenceNoCustomerData)
        XCTAssertTrue(corpus.localPreferenceKeys.contains(recent.key))
        XCTAssertEqual(V24BackupSurveyDefinitionRecordV1.Kind.allCases.count, 2)
    }

    func testV23P03C25H01ClosedGrammarClaimsStalenessAndForgedReleaseInputsFailClosed() throws {
        let corpus = try C25SurveyDefinitionTestSupport.decodedCorpus()
        XCTAssertThrowsError(try SurveyDefinitionCanonicalCodecV1.decode(ActivityKindV1.self, from: Data("\"UNKNOWN\"".utf8)))
        XCTAssertThrowsError(try SurveyDefinitionCanonicalCodecV1.decode(SurveyFieldKindV1.self, from: Data("\"UNKNOWN\"".utf8)))
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            facts: [
                C25SurveyDefinitionTestSupport.fact("fact-a"),
                C25SurveyDefinitionTestSupport.fact("fact-a")
            ]
        ))

        let missingReference = C25SurveyDefinitionTestSupport.fact(
            "fact-a",
            visibility: .predicate(
                SurveyVisibilityPredicateV1(factID: "missing", expectedValue: .text("yes"))
            )
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(facts: [missingReference]))
        let cycleA = C25SurveyDefinitionTestSupport.fact(
            "fact-a",
            visibility: .predicate(SurveyVisibilityPredicateV1(factID: "fact-b", expectedValue: .text("yes")))
        )
        let cycleB = C25SurveyDefinitionTestSupport.fact(
            "fact-b",
            visibility: .predicate(SurveyVisibilityPredicateV1(factID: "fact-a", expectedValue: .text("yes")))
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(facts: [cycleA, cycleB]))
        let duplicateSectionID = [
            C25SurveyDefinitionTestSupport.section(
                sectionID: "section",
                ordinal: 0,
                facts: [C25SurveyDefinitionTestSupport.fact("fact-a")]
            ),
            C25SurveyDefinitionTestSupport.section(
                sectionID: "section",
                ordinal: 1,
                facts: [C25SurveyDefinitionTestSupport.fact("fact-b")]
            )
        ]
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 84,
            sections: duplicateSectionID
        ))
        let duplicateSectionOrdinal = [
            C25SurveyDefinitionTestSupport.section(
                sectionID: "section",
                ordinal: 0,
                facts: [C25SurveyDefinitionTestSupport.fact("fact-a")]
            ),
            C25SurveyDefinitionTestSupport.section(
                sectionID: "section-b",
                ordinal: 0,
                facts: [C25SurveyDefinitionTestSupport.fact("fact-b")]
            )
        ]
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 85,
            sections: duplicateSectionOrdinal
        ))
        let nonContiguousSectionOrdinal = [
            C25SurveyDefinitionTestSupport.section(
                sectionID: "section",
                ordinal: 0,
                facts: [C25SurveyDefinitionTestSupport.fact("fact-a")]
            ),
            C25SurveyDefinitionTestSupport.section(
                sectionID: "section-b",
                ordinal: 2,
                facts: [C25SurveyDefinitionTestSupport.fact("fact-b")]
            )
        ]
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 86,
            sections: nonContiguousSectionOrdinal
        ))

        let duplicateRules = [
            CompletionRuleV1(
                ruleID: "same-rule",
                expression: .allRequiredVisibleFactsAnswered,
                failureLocalizationKey: "survey.completion.failure"
            ),
            CompletionRuleV1(
                ruleID: "same-rule",
                expression: .factPresent("fact-a"),
                failureLocalizationKey: "survey.completion.failure"
            )
        ]
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 87,
            completionRules: duplicateRules
        ))
        let overflowRules = (0...SurveyDefinitionLimitsV1.maximumRules).map { index in
            CompletionRuleV1(
                ruleID: "rule-\(String(format: "%03d", index))",
                expression: .allRequiredVisibleFactsAnswered,
                failureLocalizationKey: "survey.completion.failure"
            )
        }
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 88,
            completionRules: overflowRules
        ))
        var deepCompletion: SurveyCompletionExpressionV1 = .allRequiredVisibleFactsAnswered
        for _ in 0...SurveyDefinitionLimitsV1.maximumExpressionDepth {
            deepCompletion = .all([deepCompletion])
        }
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 89,
            completionRules: [
                CompletionRuleV1(
                    ruleID: "deep-rule",
                    expression: deepCompletion,
                    failureLocalizationKey: "survey.completion.failure"
                )
            ]
        ))
        let hiddenRequired = C25SurveyDefinitionTestSupport.fact(
            "fact-b",
            required: true,
            visibility: .predicate(
                SurveyVisibilityPredicateV1(factID: "fact-a", expectedValue: .text("never"))
            )
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 90,
            facts: [
                C25SurveyDefinitionTestSupport.fact(
                    "fact-a",
                    payload: .booleanObservation
                ),
                hiddenRequired
            ]
        ))
        let nestedAnyContradiction = C25SurveyDefinitionTestSupport.fact(
            "fact-nested-any-required",
            required: true,
            visibility: .all([
                .any([
                    .predicate(.init(factID: "fact-a", expectedValue: .triState(.trueValue)))
                ]),
                .any([
                    .predicate(.init(factID: "fact-a", expectedValue: .triState(.falseValue)))
                ])
            ])
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 901,
            facts: [
                C25SurveyDefinitionTestSupport.fact("fact-a", payload: .booleanObservation),
                nestedAnyContradiction
            ]
        ))
        let unreachableRule = CompletionRuleV1(
            ruleID: "unreachable",
            expression: .factPresent("missing-fact"),
            failureLocalizationKey: "survey.completion.failure"
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 91,
            completionRules: [unreachableRule]
        ))
        let wrongTypeDefault = C25SurveyDefinitionTestSupport.fact(
            "fact-wrong-default-type",
            defaultValue: .integer(1),
            payload: .shortText(.init(maximumUTF8Bytes: 16))
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 92,
            facts: [wrongTypeDefault]
        ))
        let outOfConstraintDefault = C25SurveyDefinitionTestSupport.fact(
            "fact-default-too-long",
            defaultValue: .text("123456789"),
            payload: .shortText(.init(maximumUTF8Bytes: 8))
        )
        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 93,
            facts: [outOfConstraintDefault]
        ))
        XCTAssertThrowsError(try SurveyTextConstraintsV1(maximumUTF8Bytes: SurveyDefinitionLimitsV1.maximumTextBytes + 1).validate())
        XCTAssertThrowsError(try SurveyRepeatableGroupV1(groupID: "group", childFactIDs: ["fact-a"], minimum: 0, maximum: SurveyDefinitionLimitsV1.maximumRepeatCount + 1).validate())

        let source = try C25SurveyDefinitionTestSupport.release(releaseSlot: 80)
        let encoded = try SurveyDefinitionCanonicalCodecV1.encode(source)
        let sourceText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let forgedText = sourceText.replacingOccurrences(
            of: source.releaseSHA256,
            with: C25SurveyDefinitionTestSupport.digest("f")
        )
        let forgedData = Data(forgedText.utf8)
        XCTAssertThrowsError(try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionReleaseV1.self, from: forgedData))

        XCTAssertThrowsError(try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 80,
            revision: 2,
            supersedesReleaseID: source.releaseID
        ))
        let wrongPredecessor = try C25SurveyDefinitionTestSupport.release(
            releaseSlot: 81,
            revision: 2,
            supersedesReleaseID: C25SurveyDefinitionTestSupport.id(999)
        )
        XCTAssertThrowsError(try wrongPredecessor.validateSuccessor(of: source))

        let differentKind = try C25SurveyDefinitionTestSupport.release(
            kind: .repair,
            releaseSlot: 82,
            revision: 2,
            supersedesReleaseID: source.releaseID
        )
        let invalidDiff = try SurveyDefinitionSemanticDiffV1(source: source, target: differentKind)
        XCTAssertEqual(invalidDiff.compatibility, .invalid)
        let blockedPreview = try SurveyDefinitionAdoptionPreviewV1(
            workspaceID: source.workspaceID,
            diff: invalidDiff,
            affectedDraftIDs: [],
            pinnedActiveWorkCount: 0,
            generatedAt: C25SurveyDefinitionTestSupport.fixedDate
        )
        XCTAssertEqual(blockedPreview.disposition, .blocked)

        let forgedDiff = try SurveyDefinitionSemanticDiffV1(source: source, target: wrongPredecessor)
        let diffData = try SurveyDefinitionCanonicalCodecV1.encode(forgedDiff)
        let diffText = try XCTUnwrap(String(data: diffData, encoding: .utf8))
        let forgedDiffData = Data(diffText.replacingOccurrences(
            of: forgedDiff.diffSHA256,
            with: C25SurveyDefinitionTestSupport.digest("e")
        ).utf8)
        let decodedForgedDiff = try SurveyDefinitionCanonicalCodecV1.decode(
            SurveyDefinitionSemanticDiffV1.self,
            from: forgedDiffData
        )
        XCTAssertThrowsError(try decodedForgedDiff.validate(source: source, target: wrongPredecessor))

        let additiveDiffData = try SurveyDefinitionCanonicalCodecV1.encode(diff)
        let additiveDiffText = try XCTUnwrap(String(data: additiveDiffData, encoding: .utf8))
        let compatibilityForgeryData = Data(additiveDiffText.replacingOccurrences(
            of: "ADDITIVE_DRAFT_SAFE",
            with: "INVALID"
        ).utf8)
        let compatibilityForgery = try SurveyDefinitionCanonicalCodecV1.decode(
            SurveyDefinitionSemanticDiffV1.self,
            from: compatibilityForgeryData
        )
        XCTAssertThrowsError(try compatibilityForgery.validate(source: source, target: target))
        let previewData = try SurveyDefinitionCanonicalCodecV1.encode(preview)
        let previewText = try XCTUnwrap(String(data: previewData, encoding: .utf8))
        let forgedPreviewData = Data(previewText.replacingOccurrences(
            of: preview.previewSHA256,
            with: C25SurveyDefinitionTestSupport.digest("c")
        ).utf8)
        let forgedPreview = try SurveyDefinitionCanonicalCodecV1.decode(
            SurveyDefinitionAdoptionPreviewV1.self,
            from: forgedPreviewData
        )
        XCTAssertThrowsError(try forgedPreview.validate(
            source: source,
            target: target,
            currentDraftIDs: [affectedDraftID],
            currentActiveWorkCount: 0
        ))
        XCTAssertThrowsError(try SurveyDefinitionAdoptionPreviewV1(
            workspaceID: source.workspaceID,
            diff: invalidDiff,
            affectedDraftIDs: [C25SurveyDefinitionTestSupport.id(900), C25SurveyDefinitionTestSupport.id(900)],
            pinnedActiveWorkCount: 0,
            generatedAt: C25SurveyDefinitionTestSupport.fixedDate
        ))
        XCTAssertThrowsError(try SurveyDefinitionAdoptionPreviewV1(
            workspaceID: source.workspaceID,
            diff: invalidDiff,
            affectedDraftIDs: [],
            pinnedActiveWorkCount: -1,
            generatedAt: C25SurveyDefinitionTestSupport.fixedDate
        ))

        for kind in ActivityKindV1.allCases {
            for (offset, claim) in [
                "pass", "certification", "compliance", "training-complete",
                "comprehension", "legal-signature"
            ].enumerated() {
                let invalidClaims = ClaimsProfileV1(
                    profileID: "claims-\(kind.rawValue.lowercased())-\(offset)",
                    activityKind: kind,
                    allowedClaimKeys: [claim],
                    forbiddenClaimKeys: [],
                    limitationLocalizationKeys: ["limitation"]
                )
                XCTAssertThrowsError(try invalidClaims.validate(), "forbidden claim: \(claim) / \(kind.rawValue)")
            }
        }
        let rejected = try SurveyTemplateQuarantineAssessmentV1(
            quarantineID: C25SurveyDefinitionTestSupport.id(83),
            archiveSHA256: C25SurveyDefinitionTestSupport.digest("a"),
            manifestSHA256: nil,
            candidateReleaseSHA256: nil,
            disposition: .rejected,
            findings: ["archive-corrupt"],
            assessedAt: C25SurveyDefinitionTestSupport.fixedDate
        )
        XCTAssertNoThrow(try rejected.validate())
        XCTAssertEqual(corpus.hostileCases.count, 24)
        XCTAssertTrue(corpus.hostileCases.contains("DUPLICATE_SECTION_ID"))
        XCTAssertTrue(corpus.hostileCases.contains("DUPLICATE_SECTION_ORDINAL"))
        XCTAssertTrue(corpus.hostileCases.contains("NONCONTIGUOUS_SECTION_ORDINAL"))
        XCTAssertTrue(corpus.hostileCases.contains("DUPLICATE_COMPLETION_RULE_ID"))
        XCTAssertTrue(corpus.hostileCases.contains("COMPLETION_EXPRESSION_TOO_DEEP"))
        XCTAssertTrue(corpus.hostileCases.contains("HIDDEN_REQUIRED_FIELD"))
        XCTAssertTrue(corpus.hostileCases.contains("FORGED_COMPATIBILITY"))
        XCTAssertTrue(corpus.hostileCases.contains("STALE_ADOPTION_PREVIEW"))
        XCTAssertTrue(corpus.hostileCases.contains("MALFORMED_FAVORITE_RECENT_PAYLOAD"))
        XCTAssertTrue(corpus.hostileCases.contains("SILENT_ACTIVE_WORK_UPGRADE"))
        XCTAssertTrue(corpus.hostileCases.contains("CLAIM_OR_PRIVACY_LEAK"))
        XCTAssertTrue(corpus.noC26OrC47)
    }

    func testV23P03C25I01LifecycleEventAndPersistenceInterruptionBoundariesAreOldOrNew() throws {
        let corpus = try C25SurveyDefinitionTestSupport.decodedCorpus()
        let release = try C25SurveyDefinitionTestSupport.release(releaseSlot: 100)
        let createdBy = try C25SurveyDefinitionTestSupport.actor(slot: 1_100)
        let draftEvent = try C25SurveyDefinitionTestSupport.event(
            release: release,
            action: .createDraft,
            priorState: nil,
            resultingState: .draft,
            eventSlot: 101,
            revision: 1
        )
        let publishEvent = try C25SurveyDefinitionTestSupport.event(
            release: release,
            action: .publish,
            priorState: .draft,
            resultingState: .published,
            eventSlot: 102,
            predecessor: draftEvent,
            revision: 2
        )
        let retireEvent = try C25SurveyDefinitionTestSupport.event(
            release: release,
            action: .retire,
            priorState: .published,
            resultingState: .retired,
            eventSlot: 103,
            predecessor: publishEvent,
            revision: 3
        )
        try publishEvent.validateSuccessor(of: draftEvent, release: release)
        try retireEvent.validateSuccessor(of: publishEvent, release: release)
        XCTAssertEqual(
            Set([draftEvent.eventID, publishEvent.eventID, retireEvent.eventID]).count,
            3
        )
        XCTAssertEqual(
            Set([draftEvent.mutationID, publishEvent.mutationID, retireEvent.mutationID]).count,
            3
        )
        XCTAssertEqual(publishEvent.predecessorEventSHA256, draftEvent.eventSHA256)
        XCTAssertEqual(retireEvent.predecessorEventSHA256, publishEvent.eventSHA256)

        let draftIdentity = try C25SurveyDefinitionTestSupport.identity(
            release: release,
            state: .draft,
            event: draftEvent,
            createdBy: createdBy
        )
        let publishedIdentity = try C25SurveyDefinitionTestSupport.identity(
            release: release,
            state: .published,
            event: publishEvent,
            createdBy: createdBy
        )
        let retiredIdentity = try C25SurveyDefinitionTestSupport.identity(
            release: release,
            state: .retired,
            event: retireEvent,
            createdBy: createdBy
        )
        try draftIdentity.validate(currentRelease: release, event: draftEvent)
        try publishedIdentity.validateSuccessor(of: draftIdentity, event: publishEvent, release: release)
        try retiredIdentity.validateSuccessor(of: publishedIdentity, event: retireEvent, release: release)

        let releaseRow = try SurveyDefinitionReleaseRow(release)
        XCTAssertEqual(try releaseRow.value(), release)
        let identityRow = try SurveyDefinitionIdentityRow(publishedIdentity)
        XCTAssertEqual(
            try identityRow.value(currentRelease: release, event: publishEvent),
            publishedIdentity
        )
        XCTAssertEqual(corpus.persistentFamilies, ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"])
        XCTAssertEqual(corpus.lifecycleEventPersistence, "CANONICAL_MUTATION_JOURNAL_ENVELOPE")
        XCTAssertEqual(corpus.interruptionBoundaries.count, 8)
        XCTAssertTrue(corpus.oldOrNewOnly)
        XCTAssertTrue(corpus.interruptionBoundaries.allSatisfy { !$0.isEmpty })
        // Each boundary has only the two durable snapshots as legal recovery
        // outcomes; a journal interruption cannot expose a partially-mutated
        // third state.
        let legalStates = Set([draftIdentity.identitySHA256, publishedIdentity.identitySHA256])
        XCTAssertTrue(legalStates.contains(draftIdentity.identitySHA256))
        XCTAssertTrue(legalStates.contains(publishedIdentity.identitySHA256))
        XCTAssertFalse(legalStates.contains(retiredIdentity.identitySHA256))
    }

    func testV23P03C25R01RecoveryRetainsReleasedHistoryAndLocalPreferences() throws {
        let corpus = try C25SurveyDefinitionTestSupport.decodedCorpus()
        let release = try C25SurveyDefinitionTestSupport.release(releaseSlot: 120)
        let canonical = try SurveyDefinitionCanonicalCodecV1.encode(release)
        let recovered = try SurveyDefinitionCanonicalCodecV1.decode(
            SurveyDefinitionReleaseV1.self,
            from: canonical
        )
        XCTAssertEqual(recovered, release)
        XCTAssertEqual(recovered.releaseSHA256, release.releaseSHA256)
        try recovered.validate()

        let reboundWorkspace = C25SurveyDefinitionTestSupport.workspace(2)
        let rebound = try recovered.rebound(
            to: reboundWorkspace,
            actor: C25SurveyDefinitionTestSupport.actor(workspaceID: reboundWorkspace, slot: 1_300)
        )
        XCTAssertNotEqual(rebound.workspaceID, release.workspaceID)
        XCTAssertNotEqual(rebound.releaseSHA256, release.releaseSHA256)
        XCTAssertEqual(release.workspaceID, C25SurveyDefinitionTestSupport.workspace())
        XCTAssertEqual(release.releaseSHA256, recovered.releaseSHA256)
        XCTAssertEqual(recovered.sections, release.sections)

        let settings = try SettingsRegistryV1.current()
        for key in ["device.recentInputMemory", "device.lastSelectedSmartViewID"] {
            let descriptor = try settings.descriptor(for: key)
            XCTAssertEqual(descriptor.scope, .deviceLocal)
            XCTAssertEqual(descriptor.backup, .excludedDeviceLocal)
            XCTAssertEqual(descriptor.privacy, .devicePreferenceNoCustomerData)
            XCTAssertFalse(descriptor.changesHistoricOutput)
        }
        let deviceReference = try SurveyDefinitionDeviceReferenceV1(
            workspaceID: release.workspaceID.rawValue,
            definitionID: release.definitionID,
            releaseID: release.releaseID,
            activityKind: release.activityKind,
            releaseRevision: release.revision
        )
        let favoriteIDs = try SurveyDefinitionDeviceMemoryV1.canonicalIDs(
            [deviceReference],
            maximum: SurveyDefinitionDeviceMemoryV1.maximumFavorites
        )
        XCTAssertEqual(favoriteIDs, [deviceReference.stableStorageID])
        XCTAssertNoThrow(try SurveyDefinitionDeviceMemoryV1.validateStoredIDs(
            favoriteIDs,
            maximum: SurveyDefinitionDeviceMemoryV1.maximumFavorites
        ))
        XCTAssertThrowsError(try SurveyDefinitionDeviceMemoryV1.validateStoredIDs(
            ["{arbitrary-not-a-canonical-id}"],
            maximum: SurveyDefinitionDeviceMemoryV1.maximumFavorites
        ))
        XCTAssertThrowsError(try SurveyDefinitionDeviceMemoryV1.validateStoredIDs(
            ["not canonical"],
            maximum: SurveyDefinitionDeviceMemoryV1.maximumRecents
        ))
        XCTAssertThrowsError(try SurveyDefinitionDeviceMemoryV1.validateStoredIDs(
            ["z", "a"],
            maximum: SurveyDefinitionDeviceMemoryV1.maximumRecents
        ))
        XCTAssertThrowsError(try SurveyDefinitionDeviceMemoryV1.validateStoredIDs(
            [favoriteIDs[0], favoriteIDs[0]],
            maximum: SurveyDefinitionDeviceMemoryV1.maximumRecents
        ))
        XCTAssertNoThrow(try SurveyDefinitionDeviceMemoryV1.validatePolicy())
        XCTAssertEqual(SurveyDefinitionDeviceMemoryV1.favoriteKey, "device.surveyDefinition.favoriteIDs")
        XCTAssertEqual(SurveyDefinitionDeviceMemoryV1.recentsKey, "device.surveyDefinition.recentIDs")
        XCTAssertEqual(SurveyDefinitionDeviceMemoryV1.backupDisposition, "EXCLUDED_DEVICE_LOCAL")
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeRelease, .v24)
        XCTAssertEqual(PersistentSchemaMigrationPlanV23.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV23.stages.count, 1)
        XCTAssertNoThrow(try V24SurveyDefinitionImportBoundaryV1.validate(persistent: 24, records: 23))
        XCTAssertEqual(CurrentSyncClassificationCatalogV1.activePersistentModelNames.count, 87)
        let currentSync = try CurrentSyncClassificationCatalogV1.current
        XCTAssertNoThrow(try currentSync.validate())
        XCTAssertEqual(currentSync.persistentModelSubjects.count, 87)
        XCTAssertTrue(currentSync.persistentModelSubjects.map(\.stableName).contains("SurveyDefinitionIdentityRow"))
        XCTAssertTrue(currentSync.persistentModelSubjects.map(\.stableName).contains("SurveyDefinitionReleaseRow"))
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.fileExtension, corpus.exchangeExtension)
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.maximumEntries, corpus.archiveMaximumEntries)
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.maximumArchiveBytes, corpus.archiveAggregateLimitBytes)
        XCTAssertEqual(corpus.archiveEntryLimitBytes, 8_388_608)
        XCTAssertEqual(corpus.archivePathLimitBytes, 240)
        XCTAssertEqual(corpus.archiveMaximumDepth, 8)
        XCTAssertEqual(corpus.archiveCompressionRatio, 20)
        XCTAssertEqual(SurveyDefinitionLimitsV1.maximumCanonicalBytes, corpus.archiveCanonicalBytes)
        XCTAssertTrue(corpus.immutableReleasedBytes)
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
        XCTAssertTrue(corpus.noSilentUpgrade)
        XCTAssertTrue(corpus.quarantinesImports)
        XCTAssertTrue(corpus.lifecycleConsumers.contains("BACKUP"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("RESTORE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("DELETE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("ERASE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("SEARCH"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("JOURNAL_REPLAY"))
        XCTAssertTrue(corpus.localPreferenceExclusions.contains("CUSTOMER_TRUTH"))
        XCTAssertTrue(corpus.localPreferenceExclusions.contains("REMOTE_PROVIDER"))
        XCTAssertTrue(corpus.forbiddenProductionSymbols.contains("C26"))
        XCTAssertTrue(corpus.forbiddenProductionSymbols.contains("C47"))
        XCTAssertTrue(corpus.noC26OrC47)
    }
}
extension V9_39SurveyDefinitionTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_39SurveyDefinitionTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
