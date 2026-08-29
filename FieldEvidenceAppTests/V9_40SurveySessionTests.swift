import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private final class C30EvidenceContextAnchorV9_40SurveySession: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

enum C26SurveySessionTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_001_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2600000-0000-4000-8000-%012x", slot))!
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
            displayName: "C26 local survey author"
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

    static func release(
        releaseSlot: Int = 10,
        workspaceID: WorkspaceID = workspace(),
        revision: UInt64 = 1,
        supersedesReleaseID: UUID? = nil,
        facts: [FactDefinitionV1] = [fact()],
        ownerPackageID: String = ShippingIlluminatedSignAdapterV1.packageID
    ) throws -> SurveyDefinitionReleaseV1 {
        let sortedFacts = facts.sorted { $0.factID < $1.factID }
        return try SurveyDefinitionReleaseV1(
            releaseID: id(releaseSlot),
            workspaceID: workspaceID,
            definitionID: id(2),
            activityKind: .survey,
            ownerPackageID: ownerPackageID,
            sections: [
                SurveySectionV1(
                    sectionID: "section",
                    titleLocalizationKey: "survey.section.title",
                    accessibilityHeadingLocalizationKey: "survey.section.heading",
                    ordinal: 0,
                    facts: sortedFacts
                )
            ],
            completionRules: [
                CompletionRuleV1(
                    ruleID: "complete",
                    expression: .allRequiredVisibleFactsAnswered,
                    failureLocalizationKey: "survey.completion.failure"
                )
            ],
            claimsProfile: ClaimsProfileV1(
                profileID: "claims",
                activityKind: .survey,
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
            authoredBy: try actor(workspaceID: workspaceID, slot: 400 + releaseSlot),
            authoredAt: fixedDate.addingTimeInterval(Double(revision))
        )
    }

    static func packageRelease(
        workflowID: String = "c26.workflow.survey.v1",
        startNodeID: String = "c26.start",
        endNodeID: String = "c26.end"
    ) throws -> InspectionPackageReleaseV1 {
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: try workflow(
                workflowID: workflowID,
                startNodeID: startNodeID,
                endNodeID: endNodeID
            )
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        return try InspectionPackageReleasePublisherV1.publish(tested).release
    }

    static func workflow(
        workflowID: String = "c26.workflow.survey.v1",
        startNodeID: String = "c26.start",
        endNodeID: String = "c26.end"
    ) throws -> WorkflowDefinitionV1 {
        try WorkflowDefinitionV1(
            workflowID: workflowID,
            entryNodeID: startNodeID,
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: startNodeID,
                    kind: .section,
                    localizationKey: "c26.start",
                    outgoingNodeIDs: [endNodeID]
                ),
                try WorkflowNodeV1(
                    nodeID: endNodeID,
                    kind: .terminal,
                    localizationKey: "c26.end",
                    outgoingNodeIDs: []
                )
            ]
        )
    }

    static func authority(
        for release: SurveyDefinitionReleaseV1,
        package: InspectionPackageReleaseV1? = nil
    ) throws -> SurveySessionAuthorityV1 {
        try SurveySessionAuthorityV1(
            definition: release,
            packageRelease: package ?? self.packageRelease(),
            pinnedRevisions: []
        )
    }

    static func provisional(
        workspaceID: WorkspaceID = workspace(),
        slot: Int = 40,
        state: ProvisionalSubjectStateV1 = .active,
        revision: UInt64 = 1,
        supersedesSubjectSHA256: String? = nil,
        mutationID: MutationIDV1? = nil
    ) throws -> ProvisionalSubjectV1 {
        try ProvisionalSubjectV1(
            provisionalSubjectID: id(slot),
            workspaceID: workspaceID,
            siteID: id(41),
            localLabel: "Unclassified local subject",
            proposedSubjectKind: .asset,
            state: state,
            createdBy: try actor(workspaceID: workspaceID, slot: 500 + slot),
            createdAt: fixedDate,
            supersedesSubjectSHA256: supersedesSubjectSHA256,
            revision: revision,
            mutationID: mutationID ?? (try self.mutation(1_500 + slot))
        )
    }

    static func session(
        authority: SurveySessionAuthorityV1,
        workspaceID: WorkspaceID = workspace(),
        sessionID: UUID = id(100),
        subject: SurveySessionSubjectV1,
        state: SurveySessionStateV1,
        transition: SurveySessionTransitionV1,
        latestPublication: SurveyPublicationReferenceV1? = nil,
        predecessor: SurveySessionV1? = nil,
        revision: UInt64,
        actorSlot: Int
    ) throws -> SurveySessionV1 {
        try SurveySessionV1(
            sessionID: sessionID,
            workspaceID: workspaceID,
            authority: authority,
            subject: subject,
            state: state,
            transition: transition,
            latestPublication: latestPublication,
            startedBy: try actor(workspaceID: workspaceID, slot: 600),
            lastTransitionBy: try actor(workspaceID: workspaceID, slot: actorSlot),
            startedAt: fixedDate,
            transitionedAt: fixedDate.addingTimeInterval(Double(revision)),
            predecessorSessionSHA256: predecessor?.sessionSHA256,
            revision: revision,
            mutationID: try mutation(2_000 + actorSlot)
        )
    }

    static func capture(
        session: SurveySessionV1,
        release: SurveyDefinitionReleaseV1,
        slot: Int,
        value: ResponseValueV1 = .text("observed"),
        action: FactCaptureActionV1 = .record,
        revision: UInt64 = 1,
        workspaceID: WorkspaceID? = nil
    ) throws -> FactCaptureV1 {
        try FactCaptureV1(
            captureID: id(slot),
            workspaceID: workspaceID ?? session.workspaceID,
            sessionID: session.sessionID,
            definitionRelease: session.authority.definitionRelease,
            factID: "fact-a",
            action: action,
            value: action == .retract ? nil : value,
            predecessors: [],
            capturedBy: try actor(workspaceID: workspaceID ?? session.workspaceID, slot: 700 + slot),
            capturedAt: fixedDate.addingTimeInterval(Double(slot)),
            revision: revision,
            mutationID: try mutation(3_000 + slot)
        )
    }

    static func captureWithPredecessors(
        session: SurveySessionV1,
        slot: Int,
        action: FactCaptureActionV1,
        value: ResponseValueV1,
        predecessors: [FactCaptureV1],
        revision: UInt64
    ) throws -> FactCaptureV1 {
        try FactCaptureV1(
            captureID: id(slot),
            workspaceID: session.workspaceID,
            sessionID: session.sessionID,
            definitionRelease: session.authority.definitionRelease,
            factID: "fact-a",
            action: action,
            value: value,
            predecessors: try predecessors.map(\.reference),
            capturedBy: try actor(workspaceID: session.workspaceID, slot: 700 + slot),
            capturedAt: fixedDate.addingTimeInterval(Double(slot)),
            revision: revision,
            mutationID: try mutation(3_000 + slot)
        )
    }

    static func preview(
        provisional: ProvisionalSubjectV1,
        sessionID: UUID,
        action: SubjectPromotionActionV1 = .promoteToAsset,
        safeToReverse: Bool = true
    ) throws -> SubjectPromotionPreviewV1 {
        try SubjectPromotionPreviewV1(
            workspaceID: provisional.workspaceID,
            provisionalSubject: provisional.reference,
            canonicalSubject: WorkSubjectReferenceV1(
                kind: .asset,
                subjectID: id(80),
                revision: 1,
                ownerAssetID: nil
            ),
            action: action,
            affectedSessionIDs: [sessionID],
            safeToReverse: safeToReverse,
            generatedAt: fixedDate.addingTimeInterval(10)
        )
    }

    static func receipt(
        preview: SubjectPromotionPreviewV1,
        predecessor: SubjectPromotionReceiptV1? = nil,
        slot: Int = 90,
        revision: UInt64 = 1
    ) throws -> SubjectPromotionReceiptV1 {
        try SubjectPromotionReceiptV1(
            receiptID: id(slot),
            preview: preview,
            predecessor: predecessor,
            actor: try actor(workspaceID: preview.workspaceID, slot: 900 + slot),
            recordedAt: fixedDate.addingTimeInterval(20 + Double(revision)),
            revision: revision,
            mutationID: try mutation(4_000 + slot)
        )
    }

    static func persistenceContainer(_ name: String) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV25.models,
            version: PersistentSchemaV25.versionIdentifier
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

    static func promotedPackage(
        _ packageRelease: InspectionPackageReleaseV1,
        workspaceID: WorkspaceID,
        slot: Int
    ) throws -> PromotedPackageReleaseV1 {
        try PromotedPackageReleaseV1(
            releaseRecordID: id(slot),
            workspaceID: workspaceID,
            packageRelease: packageRelease,
            mutationID: try mutation(5_000 + slot),
            promotedAt: fixedDate
        )
    }

    static func seedPersistence(
        context: ModelContext,
        session: SurveySessionV1,
        packageRelease: InspectionPackageReleaseV1,
        packageSlot: Int,
        captures: [FactCaptureV1] = [],
        promotionReceipts: [SubjectPromotionReceiptV1] = []
    ) throws {
        context.insert(try PromotedPackageReleaseRow(
            promotedPackage(
                packageRelease,
                workspaceID: session.workspaceID,
                slot: packageSlot
            )
        ))
        context.insert(try SurveySessionRow(session))
        for capture in captures {
            context.insert(try FactCaptureRow(capture))
        }
        for receipt in promotionReceipts {
            context.insert(try SubjectPromotionReceiptRow(receipt))
        }
        try context.save()
    }
}

private struct C26SurveySessionCorpus: Decodable {
    struct Behavior: Decodable {
        let id: String
        let contract: String
        let requirement: String
    }

    struct EvidenceCase: Decodable {
        let id: String
        let kind: String
        let assertion: String
    }

    struct Persistence: Decodable {
        let schemaRelease: String
        let persistentSchemaVersion: Int
        let recordsSchemaVersion: Int
        let persistentKindLifecycleModelCount: Int
        let durableFamilyCount: Int
        let mode: String
        let migrationRequired: Bool
        let backupRestoreRequired: Bool
        let cloneForkRequired: Bool
        let deleteEraseRequired: Bool
        let exportReportRequired: Bool
        let searchRebuildRequired: Bool
        let replayRequired: Bool
        let interruptionRecoveryRequired: Bool
        let canonicalWriter: String
        let canonicalSourceOfTruth: [String]
        let persistedFamilies: [String]
        let nonPersistentFamilies: [String]
        let currentProjectionRowCount: Int
        let providerRows: Int
        let secondStore: Bool
        let secondWriter: Bool
        let downgrade: String
        let forwardFix: String
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let synthetic: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let persistentKindLifecycleModelCount: Int
    let durableFamilyCount: Int
    let durableFamilies: [String]
    let nonPersistentFamilies: [String]
    let requiredContractNames: [String]
    let sessionStates: [String]
    let sessionTransitions: [String]
    let factActions: [String]
    let promotionActions: [String]
    let subjectStates: [String]
    let availabilityStates: [String]
    let failureCases: [String]
    let interruptionPoints: [String]
    let requiredBehaviors: [Behavior]
    let evidenceCases: [EvidenceCase]
    let forbiddenClaims: [String]
    let persistence: Persistence
    let statusFlags: [String: Bool]
}

@MainActor
final class V9_40SurveySessionTests: XCTestCase {
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
    private func corpus() throws -> C26SurveySessionCorpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C26SurveySessionCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/SurveySessions"
            ) ?? bundle.url(
                forResource: "V22P03C26SurveySessionCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            C26SurveySessionCorpus.self,
            from: Data(contentsOf: url)
        )
    }

    func testV23P03C26G01GoldenSurveySessionCreatePauseResumeReviewPublishLifecycle() throws {
        let release = try C26SurveySessionTestSupport.release()
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional()
        let subject = SurveySessionSubjectV1.provisional(provisional.reference)
        let draft = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )
        try draft.validate(definition: release)
        let paused = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .paused,
            transition: .pause,
            predecessor: draft,
            revision: 2,
            actorSlot: 602
        )
        try paused.validateSuccessor(of: draft)
        let resumed = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .draft,
            transition: .resume,
            predecessor: paused,
            revision: 3,
            actorSlot: 603
        )
        try resumed.validateSuccessor(of: paused)
        let review = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .reviewRequired,
            transition: .submitForReview,
            predecessor: resumed,
            revision: 4,
            actorSlot: 604
        )
        try review.validateSuccessor(of: resumed)

        let capture = try C26SurveySessionTestSupport.capture(
            session: review,
            release: release,
            slot: 110
        )
        try capture.validate(session: review, definition: release)
        let provisionalRow = try ProvisionalSubjectRow(provisional)
        let captureRow = try FactCaptureRow(capture)
        XCTAssertEqual(try provisionalRow.value(), provisional)
        XCTAssertEqual(try captureRow.value(), capture)

        let preview = try C26SurveySessionTestSupport.preview(
            provisional: provisional,
            sessionID: review.sessionID
        )
        let receipt = try C26SurveySessionTestSupport.receipt(preview: preview)
        try receipt.validate(preview: preview, predecessor: nil)
        // Publication is a two-pass cycle: project from a complete candidate,
        // then bind the resulting reference to the final complete session.
        let completedCandidate = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .completed,
            transition: .complete,
            predecessor: review,
            revision: 5,
            actorSlot: 605
        )
        let snapshot = try SurveyPublicationSnapshotV1(
            snapshotID: C26SurveySessionTestSupport.id(120),
            session: completedCandidate,
            definition: release,
            currentCaptures: [capture],
            promotionReceipts: [receipt],
            publishedBy: try C26SurveySessionTestSupport.actor(
                workspaceID: completedCandidate.workspaceID,
                slot: 1_200
            ),
            publishedAt: C26SurveySessionTestSupport.fixedDate.addingTimeInterval(30),
            revision: 1,
            mutationID: try C26SurveySessionTestSupport.mutation(4_120)
        )
        XCTAssertEqual(snapshot.facts.map(\.factID), ["fact-a"])
        XCTAssertEqual(snapshot.satisfiedCompletionRuleIDs, ["complete"])

        let completed = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .completed,
            transition: .complete,
            latestPublication: snapshot.reference,
            predecessor: review,
            revision: 5,
            actorSlot: 606
        )
        try completed.validateSuccessor(of: review, publication: snapshot)
        try snapshot.validate(session: completed, definition: release, captures: [capture])
        let amended = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: subject,
            state: .amended,
            transition: .reopenAmendment,
            predecessor: completed,
            revision: 6,
            actorSlot: 607
        )
        try amended.validateSuccessor(of: completed)
        let sessionRow = try SurveySessionRow(completed)
        let snapshotRow = try SurveyPublicationSnapshotRow(snapshot)
        let receiptRow = try SubjectPromotionReceiptRow(receipt)
        XCTAssertEqual(try sessionRow.value(), completed)
        XCTAssertEqual(try snapshotRow.value(), snapshot)
        XCTAssertEqual(try receiptRow.value(), receipt)
        XCTAssertEqual(completed.activityKind, .survey)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertTrue(release.claimsProfile.allowedClaimKeys.isEmpty)

        XCTAssertThrowsError(
            try SurveySessionMutationV1(
                workspaceID: review.workspaceID,
                mutationID: capture.mutationID,
                payload: .captureFact(
                    capture,
                    session: review,
                    definition: release,
                    predecessors: []
                )
            )
        )
    }

    func testV23P03C26A01ConcurrentFactConflictHasNoLastWriteWins() throws {
        let release = try C26SurveySessionTestSupport.release()
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional()
        let draft = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )
        let session = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .reviewRequired,
            transition: .submitForReview,
            predecessor: draft,
            revision: 2,
            actorSlot: 602
        )
        try session.validateSuccessor(of: draft)
        let completedCandidate = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .completed,
            transition: .complete,
            predecessor: session,
            revision: 3,
            actorSlot: 603
        )
        let left = try C26SurveySessionTestSupport.capture(
            session: session,
            release: release,
            slot: 130,
            value: .text("left")
        )
        let right = try C26SurveySessionTestSupport.capture(
            session: session,
            release: release,
            slot: 131,
            value: .text("right")
        )
        try left.validate(session: session, definition: release)
        try right.validate(session: session, definition: release)
        XCTAssertThrowsError(
            try SurveyPublicationSnapshotV1(
                snapshotID: C26SurveySessionTestSupport.id(132),
                session: completedCandidate,
                definition: release,
                currentCaptures: [left, right],
                promotionReceipts: [],
                publishedBy: try C26SurveySessionTestSupport.actor(
                    workspaceID: session.workspaceID,
                    slot: 1_301
                ),
                publishedAt: C26SurveySessionTestSupport.fixedDate,
                revision: 1,
                mutationID: try C26SurveySessionTestSupport.mutation(4_132)
            )
        ) { error in
            XCTAssertEqual(error as? SurveySessionFailureV1, .unresolvedConflict)
        }

        let resolution = try C26SurveySessionTestSupport.captureWithPredecessors(
            session: session,
            slot: 133,
            action: .resolveConflict,
            value: .text("resolved"),
            predecessors: [left, right],
            revision: 2
        )
        try resolution.validateSuccessor(
            of: [left, right],
            session: session,
            definition: release
        )
        let snapshot = try SurveyPublicationSnapshotV1(
            snapshotID: C26SurveySessionTestSupport.id(134),
            session: completedCandidate,
            definition: release,
            currentCaptures: [left, right, resolution],
            promotionReceipts: [],
            publishedBy: try C26SurveySessionTestSupport.actor(
                workspaceID: session.workspaceID,
                slot: 1_302
            ),
            publishedAt: C26SurveySessionTestSupport.fixedDate.addingTimeInterval(1),
            revision: 1,
            mutationID: try C26SurveySessionTestSupport.mutation(4_134)
        )
        let completed = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .completed,
            transition: .complete,
            latestPublication: snapshot.reference,
            predecessor: session,
            revision: 3,
            actorSlot: 604
        )
        try completed.validateSuccessor(of: session, publication: snapshot)
        try snapshot.validate(session: completed, definition: release, captures: [left, right, resolution])
        XCTAssertEqual(snapshot.facts.first?.value, .text("resolved"))
    }

    func testV23P03C26H01HostileSessionDefinitionWorkspaceDigestAndClaimInputsFailClosed() throws {
        let release = try C26SurveySessionTestSupport.release()
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional()
        let session = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )
        let encoded = try SurveySessionCanonicalCodecV1.encode(session)
        XCTAssertThrowsError(
            try SurveySessionCanonicalCodecV1.decode(
                SurveySessionV1.self,
                from: encoded + Data([0x20])
            )
        )

        let foreignDefinition = try C26SurveySessionTestSupport.release(
            releaseSlot: 11,
            ownerPackageID: "c26.foreign.template"
        )
        let publishedPackage = try C26SurveySessionTestSupport.packageRelease()
        XCTAssertThrowsError(
            try SurveySessionAuthorityV1(
                definition: foreignDefinition,
                packageRelease: publishedPackage,
                pinnedRevisions: []
            )
        ) { error in
            XCTAssertEqual(error as? SurveySessionFailureV1, .wrongDefinition)
        }
        let draftPackage = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: try C26SurveySessionTestSupport.workflow()
        )
        XCTAssertThrowsError(try SurveyPackageReleaseReferenceV1(draftPackage))

        let foreignWorkspace = C26SurveySessionTestSupport.workspace(5)
        let foreignSubject = try C26SurveySessionTestSupport.provisional(
            workspaceID: foreignWorkspace,
            slot: 50
        )
        XCTAssertThrowsError(
            try C26SurveySessionTestSupport.capture(
                session: session,
                release: release,
                slot: 151,
                workspaceID: foreignWorkspace
            ).validate(session: session, definition: release)
        ) { error in
            XCTAssertEqual(error as? SurveySessionFailureV1, .wrongWorkspace)
        }
        XCTAssertNotEqual(foreignSubject.workspaceID, session.workspaceID)

        let illegalClaimProfile = ClaimsProfileV1(
            profileID: "claims",
            activityKind: .survey,
            allowedClaimKeys: ["pass"],
            forbiddenClaimKeys: ["approval", "release"],
            limitationLocalizationKeys: ["survey.claims.limitation"]
        )
        XCTAssertThrowsError(
            try SurveyDefinitionReleaseV1(
                releaseID: C26SurveySessionTestSupport.id(152),
                workspaceID: session.workspaceID,
                definitionID: release.definitionID,
                activityKind: .survey,
                ownerPackageID: release.ownerPackageID,
                sections: release.sections,
                completionRules: release.completionRules,
                claimsProfile: illegalClaimProfile,
                reportProjection: release.reportProjection,
                localizationReleaseSHA256: release.localizationReleaseSHA256,
                revision: 1,
                mutationID: try C26SurveySessionTestSupport.mutation(4_152),
                authoredBy: try C26SurveySessionTestSupport.actor(
                    workspaceID: session.workspaceID,
                    slot: 1_552
                ),
                authoredAt: C26SurveySessionTestSupport.fixedDate
            )
        )

        let illegalTransition = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .completed,
            transition: .complete,
            predecessor: session,
            revision: 2,
            actorSlot: 602
        )
        XCTAssertThrowsError(try illegalTransition.validateSuccessor(of: session))
    }

    func testV23P03C26I01PublicationAndPersistenceInterruptionIsOldOrNew() throws {
        let release = try C26SurveySessionTestSupport.release()
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional()
        let before = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )
        let row = try SurveySessionRow(before)
        let paused = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .paused,
            transition: .pause,
            predecessor: before,
            revision: 2,
            actorSlot: 602
        )
        XCTAssertThrowsError(
            try row.replace(with: paused, publication: nil, expectedRevision: 99)
        )
        XCTAssertEqual(try row.value(), before)
        try row.replace(with: paused, publication: nil, expectedRevision: 1)
        XCTAssertEqual(try row.value(), paused)
        XCTAssertThrowsError(
            try row.replace(with: before, publication: nil, expectedRevision: paused.revision)
        )
        XCTAssertEqual(try row.value(), paused)

        let capture = try C26SurveySessionTestSupport.capture(
            session: paused,
            release: release,
            slot: 170
        )
        XCTAssertThrowsError(
            try SurveySessionMutationV1(
                workspaceID: paused.workspaceID,
                mutationID: capture.mutationID,
                payload: .captureFact(
                    capture,
                    session: paused,
                    definition: release,
                    predecessors: []
                )
            )
        )
        XCTAssertEqual(try SurveySessionCanonicalCodecV1.encode(paused), row.canonicalData)
    }

    func testV23P03C26R01RecoveryPreservesImmutableSnapshotAndPromotionAliasHistory() throws {
        let release = try C26SurveySessionTestSupport.release()
        let authority = try C26SurveySessionTestSupport.authority(for: release)
        let provisional = try C26SurveySessionTestSupport.provisional()
        let draft = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )
        let session = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .reviewRequired,
            transition: .submitForReview,
            predecessor: draft,
            revision: 2,
            actorSlot: 602
        )
        try session.validateSuccessor(of: draft)
        let capture = try C26SurveySessionTestSupport.capture(
            session: session,
            release: release,
            slot: 180,
            value: .text("historic")
        )
        let preview = try C26SurveySessionTestSupport.preview(
            provisional: provisional,
            sessionID: session.sessionID
        )
        let promotion = try C26SurveySessionTestSupport.receipt(
            preview: preview,
            slot: 181
        )
        let completedCandidate = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .completed,
            transition: .complete,
            predecessor: session,
            revision: 3,
            actorSlot: 603
        )
        let snapshot = try SurveyPublicationSnapshotV1(
            snapshotID: C26SurveySessionTestSupport.id(182),
            session: completedCandidate,
            definition: release,
            currentCaptures: [capture],
            promotionReceipts: [promotion],
            publishedBy: try C26SurveySessionTestSupport.actor(
                workspaceID: completedCandidate.workspaceID,
                slot: 1_801
            ),
            publishedAt: C26SurveySessionTestSupport.fixedDate.addingTimeInterval(40),
            revision: 1,
            mutationID: try C26SurveySessionTestSupport.mutation(4_182)
        )
        let completed = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .completed,
            transition: .complete,
            latestPublication: snapshot.reference,
            predecessor: session,
            revision: 3,
            actorSlot: 604
        )
        try completed.validateSuccessor(of: session, publication: snapshot)
        try snapshot.validate(session: completed, definition: release, captures: [capture])
        let reversePreview = try C26SurveySessionTestSupport.preview(
            provisional: provisional,
            sessionID: session.sessionID,
            action: .reverse,
            safeToReverse: true
        )
        let reversal = try C26SurveySessionTestSupport.receipt(
            preview: reversePreview,
            predecessor: promotion,
            slot: 183,
            revision: 2
        )
        try reversal.validate(preview: reversePreview, predecessor: promotion)
        XCTAssertEqual(snapshot.facts.first?.value, .text("historic"))
        XCTAssertEqual(snapshot.promotionReceiptsAtPublication, [promotion])
        XCTAssertNotEqual(reversal.receiptSHA256, promotion.receiptSHA256)

        let snapshotRow = try SurveyPublicationSnapshotRow(snapshot)
        let snapshotData = try SurveySessionCanonicalCodecV1.encode(snapshot)
        snapshotRow.canonicalData = snapshotData + Data([0x20])
        XCTAssertThrowsError(try snapshotRow.value())
        snapshotRow.canonicalData = snapshotData
        XCTAssertEqual(try snapshotRow.value(), snapshot)
        XCTAssertEqual(
            V25GuidedSurveyImportBoundaryV1.recordsSchemaVersion,
            24
        )
        XCTAssertEqual(
            V25GuidedSurveyImportBoundaryV1.persistentSchemaVersion,
            25
        )
    }

    func testC26PersistenceRejectsStaleOrDisallowedFactCapture() throws {
        let release = try C26SurveySessionTestSupport.release()
        let package = try C26SurveySessionTestSupport.packageRelease()
        let authority = try C26SurveySessionTestSupport.authority(
            for: release,
            package: package
        )
        let provisional = try C26SurveySessionTestSupport.provisional(slot: 210)
        let draft = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )

        let container = try C26SurveySessionTestSupport.persistenceContainer(
            "C26StaleFactCapture"
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        try C26SurveySessionTestSupport.seedPersistence(
            context: context,
            session: draft,
            packageRelease: package,
            packageSlot: 211
        )

        // The mutation is structurally valid, but its session image is not
        // the persisted image (same identity, different immutable actor/digest).
        let staleSession = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 699
        )
        let staleCapture = try C26SurveySessionTestSupport.capture(
            session: staleSession,
            release: release,
            slot: 212
        )
        let staleMutation = try SurveySessionMutationV1(
            workspaceID: staleSession.workspaceID,
            mutationID: staleCapture.mutationID,
            payload: .captureFact(
                staleCapture,
                session: staleSession,
                definition: release,
                predecessors: []
            )
        )
        let adapter = WorkspaceWriterAdapterV1(modelContext: context)
        XCTAssertThrowsError(
            try adapter.apply(
                .applySurveySession(staleMutation),
                occurredAt: C26SurveySessionTestSupport.fixedDate,
                temporaryRelativePath: "c26/stale-capture"
            )
        ) { error in
            XCTAssertTrue(error is WorkspaceMutationFailureV1)
        }
        let storedSessions = try context.fetch(FetchDescriptor<SurveySessionRow>())
        XCTAssertEqual(storedSessions.count, 1)
        XCTAssertEqual(try storedSessions[0].value(), draft)

        // ReviewRequired is a durable state, but capture is intentionally
        // limited to DRAFT/AMENDED by the closed mutation grammar.
        let review = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .reviewRequired,
            transition: .submitForReview,
            predecessor: draft,
            revision: 2,
            actorSlot: 602
        )
        let reviewCapture = try C26SurveySessionTestSupport.capture(
            session: review,
            release: release,
            slot: 213
        )
        XCTAssertThrowsError(
            try SurveySessionMutationV1(
                workspaceID: review.workspaceID,
                mutationID: reviewCapture.mutationID,
                payload: .captureFact(
                    reviewCapture,
                    session: review,
                    definition: release,
                    predecessors: []
                )
            )
        )
    }

    func testC26PersistenceRejectsMissingOrUnpersistedPublicationInputs() throws {
        let package = try C26SurveySessionTestSupport.packageRelease()
        let release = try C26SurveySessionTestSupport.release(
            facts: [C26SurveySessionTestSupport.fact(required: false)]
        )
        let authority = try C26SurveySessionTestSupport.authority(
            for: release,
            package: package
        )
        let provisional = try C26SurveySessionTestSupport.provisional(slot: 220)

        func publicationFixture(
            name: String,
            snapshotIncludesCapture: Bool,
            persistCapture: Bool,
            snapshotIncludesReceipt: Bool,
            persistReceipt: Bool,
            packageSlot: Int
        ) throws -> (
            container: ModelContainer,
            context: ModelContext,
            predecessor: SurveySessionV1,
            completed: SurveySessionV1,
            snapshot: SurveyPublicationSnapshotV1,
            captures: [FactCaptureV1]
        ) {
            let draft = try C26SurveySessionTestSupport.session(
                authority: authority,
                subject: .provisional(provisional.reference),
                state: .draft,
                transition: .create,
                revision: 1,
                actorSlot: 601
            )
            let predecessor = try C26SurveySessionTestSupport.session(
                authority: authority,
                subject: .provisional(provisional.reference),
                state: .reviewRequired,
                transition: .submitForReview,
                predecessor: draft,
                revision: 2,
                actorSlot: 602
            )
            let capture = try C26SurveySessionTestSupport.capture(
                session: predecessor,
                release: release,
                slot: 221
            )
            let captures = snapshotIncludesCapture ? [capture] : []
            let receipt: SubjectPromotionReceiptV1?
            if snapshotIncludesReceipt {
                receipt = try C26SurveySessionTestSupport.receipt(
                    preview: C26SurveySessionTestSupport.preview(
                        provisional: provisional,
                        sessionID: predecessor.sessionID
                    ),
                    slot: 222
                )
            } else {
                receipt = nil
            }
            let completedCandidate = try C26SurveySessionTestSupport.session(
                authority: authority,
                subject: .provisional(provisional.reference),
                state: .completed,
                transition: .complete,
                predecessor: predecessor,
                revision: 3,
                actorSlot: 603
            )
            let snapshot = try SurveyPublicationSnapshotV1(
                snapshotID: C26SurveySessionTestSupport.id(223),
                session: completedCandidate,
                definition: release,
                currentCaptures: captures,
                promotionReceipts: receipt.map { [$0] } ?? [],
                publishedBy: try C26SurveySessionTestSupport.actor(
                    workspaceID: predecessor.workspaceID,
                    slot: 1_223
                ),
                publishedAt: C26SurveySessionTestSupport.fixedDate.addingTimeInterval(30),
                revision: 1,
                mutationID: try C26SurveySessionTestSupport.mutation(4_223)
            )
            let completed = try C26SurveySessionTestSupport.session(
                authority: authority,
                subject: .provisional(provisional.reference),
                state: .completed,
                transition: .complete,
                latestPublication: snapshot.reference,
                predecessor: predecessor,
                revision: 3,
                actorSlot: 604
            )
            try completed.validateSuccessor(
                of: predecessor,
                publication: snapshot
            )
            try snapshot.validate(
                session: completed,
                definition: release,
                captures: captures
            )

            let container = try C26SurveySessionTestSupport.persistenceContainer(name)
            let context = container.mainContext
            context.autosaveEnabled = false
            try C26SurveySessionTestSupport.seedPersistence(
                context: context,
                session: predecessor,
                packageRelease: package,
                packageSlot: packageSlot,
                captures: persistCapture ? [capture] : [],
                promotionReceipts: persistReceipt
                    ? (receipt.map { [$0] } ?? [])
                    : []
            )
            return (
                container: container,
                context: context,
                predecessor: predecessor,
                completed: completed,
                snapshot: snapshot,
                captures: captures
            )
        }

        // A persisted capture head cannot be silently omitted from the
        // publication input, even when the snapshot itself is structurally
        // valid for an optional fact.
        let omittedHead = try publicationFixture(
            name: "C26OmittedPersistedHead",
            snapshotIncludesCapture: false,
            persistCapture: true,
            snapshotIncludesReceipt: false,
            persistReceipt: false,
            packageSlot: 224
        )
        let omittedHeadMutation = try SurveySessionMutationV1(
            workspaceID: omittedHead.completed.workspaceID,
            mutationID: omittedHead.completed.mutationID,
            payload: .publish(
                omittedHead.completed,
                snapshot: omittedHead.snapshot,
                definition: release,
                captures: omittedHead.captures
            )
        )
        let omittedHeadAdapter = WorkspaceWriterAdapterV1(
            modelContext: omittedHead.context
        )
        XCTAssertThrowsError(
            try omittedHeadAdapter.apply(
                .applySurveySession(omittedHeadMutation),
                occurredAt: C26SurveySessionTestSupport.fixedDate,
                temporaryRelativePath: "c26/omitted-head"
            )
        ) { error in
            XCTAssertTrue(error is WorkspaceMutationFailureV1)
        }
        XCTAssertEqual(
            try omittedHead.context.fetchCount(
                FetchDescriptor<SurveyPublicationSnapshotRow>()
            ),
            0
        )

        // A capture that is present in the supplied snapshot but absent from
        // durable rows is rejected before publication can create a snapshot.
        let unpersistedCapture = try publicationFixture(
            name: "C26UnpersistedCapture",
            snapshotIncludesCapture: true,
            persistCapture: false,
            snapshotIncludesReceipt: false,
            persistReceipt: false,
            packageSlot: 225
        )
        let unpersistedCaptureMutation = try SurveySessionMutationV1(
            workspaceID: unpersistedCapture.completed.workspaceID,
            mutationID: unpersistedCapture.completed.mutationID,
            payload: .publish(
                unpersistedCapture.completed,
                snapshot: unpersistedCapture.snapshot,
                definition: release,
                captures: unpersistedCapture.captures
            )
        )
        let unpersistedCaptureAdapter = WorkspaceWriterAdapterV1(
            modelContext: unpersistedCapture.context
        )
        XCTAssertThrowsError(
            try unpersistedCaptureAdapter.apply(
                .applySurveySession(unpersistedCaptureMutation),
                occurredAt: C26SurveySessionTestSupport.fixedDate,
                temporaryRelativePath: "c26/unpersisted-capture"
            )
        ) { error in
            XCTAssertTrue(error is WorkspaceMutationFailureV1)
        }

        // Promotion receipts are a second persisted frontier. A receipt
        // embedded in the snapshot without its durable row is also rejected.
        let unpersistedReceipt = try publicationFixture(
            name: "C26UnpersistedPromotionReceipt",
            snapshotIncludesCapture: false,
            persistCapture: false,
            snapshotIncludesReceipt: true,
            persistReceipt: false,
            packageSlot: 226
        )
        let unpersistedReceiptMutation = try SurveySessionMutationV1(
            workspaceID: unpersistedReceipt.completed.workspaceID,
            mutationID: unpersistedReceipt.completed.mutationID,
            payload: .publish(
                unpersistedReceipt.completed,
                snapshot: unpersistedReceipt.snapshot,
                definition: release,
                captures: unpersistedReceipt.captures
            )
        )
        let unpersistedReceiptAdapter = WorkspaceWriterAdapterV1(
            modelContext: unpersistedReceipt.context
        )
        XCTAssertThrowsError(
            try unpersistedReceiptAdapter.apply(
                .applySurveySession(unpersistedReceiptMutation),
                occurredAt: C26SurveySessionTestSupport.fixedDate,
                temporaryRelativePath: "c26/unpersisted-receipt"
            )
        ) { error in
            XCTAssertTrue(error is WorkspaceMutationFailureV1)
        }
    }

    func testC26GenericProvisionalMutationRequiresReceiptBackedPromotion() throws {
        let active = try C26SurveySessionTestSupport.provisional(slot: 230)
        for state in [
            ProvisionalSubjectStateV1.promoted,
            .reconciledAlias,
            .promotionReversed
        ] {
            let terminal = try C26SurveySessionTestSupport.provisional(
                slot: 230,
                state: state,
                revision: 2,
                supersedesSubjectSHA256: active.subjectSHA256
            )
            XCTAssertThrowsError(
                try SurveySessionMutationV1(
                    workspaceID: terminal.workspaceID,
                    mutationID: terminal.mutationID,
                    payload: .applyProvisionalSubject(terminal)
                )
            )
        }

        let sessionID = C26SurveySessionTestSupport.id(231)
        let preview = try C26SurveySessionTestSupport.preview(
            provisional: active,
            sessionID: sessionID
        )
        let receipt = try C26SurveySessionTestSupport.receipt(
            preview: preview,
            slot: 232
        )
        let promoted = try C26SurveySessionTestSupport.provisional(
            slot: 230,
            state: .promoted,
            revision: 2,
            supersedesSubjectSHA256: active.subjectSHA256,
            mutationID: receipt.mutationID
        )
        let promotionMutation = try SurveySessionMutationV1(
            workspaceID: promoted.workspaceID,
            mutationID: promoted.mutationID,
            payload: .promoteSubject(
                promoted,
                receipt: receipt,
                preview: preview,
                predecessor: nil
            )
        )
        XCTAssertNoThrow(try promotionMutation.validate())
    }

    func testC26WriterRequiresResolvedAndExactPackageReleaseBinding() throws {
        let package = try C26SurveySessionTestSupport.packageRelease()
        let release = try C26SurveySessionTestSupport.release()
        let authority = try C26SurveySessionTestSupport.authority(
            for: release,
            package: package
        )
        let provisional = try C26SurveySessionTestSupport.provisional(slot: 240)
        let draft = try C26SurveySessionTestSupport.session(
            authority: authority,
            subject: .provisional(provisional.reference),
            state: .draft,
            transition: .create,
            revision: 1,
            actorSlot: 601
        )
        let mutation = try SurveySessionMutationV1(
            workspaceID: draft.workspaceID,
            mutationID: draft.mutationID,
            payload: .applySession(
                draft,
                definition: release,
                publication: nil
            )
        )

        let missingContainer = try C26SurveySessionTestSupport.persistenceContainer(
            "C26MissingPackageRelease"
        )
        let missingAdapter = WorkspaceWriterAdapterV1(
            modelContext: missingContainer.mainContext
        )
        XCTAssertThrowsError(
            try missingAdapter.apply(
                .applySurveySession(mutation),
                occurredAt: C26SurveySessionTestSupport.fixedDate,
                temporaryRelativePath: "c26/missing-package"
            )
        ) { error in
            XCTAssertTrue(error is WorkspaceMutationFailureV1)
        }
        XCTAssertEqual(
            try missingContainer.mainContext.fetchCount(
                FetchDescriptor<SurveySessionRow>()
            ),
            0
        )

        let wrongPackage = try C26SurveySessionTestSupport.packageRelease(
            workflowID: "c26.workflow.foreign.v1",
            startNodeID: "c26.foreign.start",
            endNodeID: "c26.foreign.end"
        )
        let mismatchedContainer = try C26SurveySessionTestSupport.persistenceContainer(
            "C26MismatchedPackageRelease"
        )
        let mismatchedContext = mismatchedContainer.mainContext
        mismatchedContext.autosaveEnabled = false
        mismatchedContext.insert(try PromotedPackageReleaseRow(
            C26SurveySessionTestSupport.promotedPackage(
                wrongPackage,
                workspaceID: draft.workspaceID,
                slot: 241
            )
        ))
        try mismatchedContext.save()
        let mismatchedAdapter = WorkspaceWriterAdapterV1(
            modelContext: mismatchedContext
        )
        XCTAssertThrowsError(
            try mismatchedAdapter.apply(
                .applySurveySession(mutation),
                occurredAt: C26SurveySessionTestSupport.fixedDate,
                temporaryRelativePath: "c26/mismatched-package"
            )
        ) { error in
            XCTAssertTrue(error is WorkspaceMutationFailureV1)
        }
        XCTAssertEqual(
            try mismatchedContext.fetchCount(
                FetchDescriptor<SurveySessionRow>()
            ),
            0
        )
    }

    func testC26CorpusAndClosedLifecycleInventory() throws {
        let value = try corpus()
        XCTAssertEqual(value.schema, "V22P03C26SurveySessionCorpusV1")
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertEqual(value.cardID, "V23-P03-C26")
        XCTAssertTrue(value.synthetic)
        XCTAssertFalse(value.containsCustomerData)
        XCTAssertFalse(value.containsSecrets)
        XCTAssertEqual(value.recordsSchemaVersion, 24)
        XCTAssertEqual(value.persistentSchemaVersion, 25)
        XCTAssertEqual(value.persistentKindLifecycleModelCount, 92)
        XCTAssertEqual(value.durableFamilyCount, 5)
        let durableFamilies = [
            "SurveySessionV1", "FactCaptureV1", "ProvisionalSubjectV1",
            "SubjectPromotionReceiptV1", "SurveyPublicationSnapshotV1"
        ]
        XCTAssertEqual(value.durableFamilies, durableFamilies)
        XCTAssertEqual(value.requiredContractNames, [
            "SurveySessionV1", "FactCaptureV1", "ProvisionalSubjectV1",
            "SubjectPromotionReceiptV1", "SurveyPublicationSnapshotV1"
        ])
        XCTAssertEqual(value.nonPersistentFamilies, [
            "SurveySemanticTreeV1", "SurveyImportPreviewV1", "SurveyDraftScratchV1"
        ])
        XCTAssertEqual(value.sessionStates, SurveySessionStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(value.sessionTransitions, SurveySessionTransitionV1.allCases.map(\.rawValue))
        XCTAssertEqual(value.factActions, FactCaptureActionV1.allCases.map(\.rawValue))
        XCTAssertEqual(value.promotionActions, SubjectPromotionActionV1.allCases.map(\.rawValue))
        XCTAssertEqual(value.subjectStates, ProvisionalSubjectStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(value.availabilityStates, ["AVAILABLE", "MISSING", "STALE", "QUARANTINED", "INCOMPATIBLE"])
        XCTAssertEqual(value.failureCases, [
            "UNKNOWN_ACTIVITY_KIND", "WRONG_WORKSPACE", "WRONG_DEFINITION_RELEASE", "WRONG_PACKAGE_RELEASE",
            "TARGET_REVISION_CHANGED", "DUPLICATE_CAPTURE_ID", "CONCURRENT_FACT_CONFLICT_NO_LWW",
            "DIVERGENT_SAME_ID", "FORGED_SESSION_DIGEST", "FORGED_CAPTURE_DIGEST", "ILLEGAL_SESSION_TRANSITION",
            "INCOMPLETE_REQUIRED_FACT", "PASS_FAIL_CLAIM_FORBIDDEN", "DUPLICATE_PROVISIONAL_SUBJECT",
            "PROMOTION_WITHOUT_PREVIEW", "FORGED_PROMOTION_PREDECESSOR", "ALIAS_FORK", "ALIAS_CYCLE",
            "ARCHIVE_ORPHAN_EVENT", "ARCHIVE_FOREIGN_EVENT", "ARCHIVE_DISCONNECTED_EVENT", "BACKUP_MANIFEST_MISMATCH",
            "REPLAY_DUPLICATE_EFFECT", "REPLAY_EFFECT_BEFORE_CHECKPOINT", "MALFORMED_LOCAL_RECENT_PAYLOAD",
            "REMOTE_PROVIDER_OR_ACCOUNT_FIELD"
        ])
        XCTAssertEqual(value.interruptionPoints, [
            "BEFORE_SESSION_ROW", "AFTER_SESSION_BEFORE_TRANSITION_RECEIPT", "AFTER_FACT_BEFORE_RECEIPT",
            "AFTER_PUBLICATION_BEFORE_RECEIPT", "AFTER_PROMOTION_BEFORE_RECEIPT", "RESTORE_BEFORE_RENAME",
            "SEARCH_AFTER_DROP_BEFORE_REBUILD", "ERASE_AFTER_MARKER_BEFORE_CLEANUP",
            "REPLAY_AFTER_EFFECT_BEFORE_CHECKPOINT"
        ])
        XCTAssertEqual(value.requiredBehaviors.map(\.id), [
            "CLOSED_TYPED_SESSION_BOUNDARY", "TYPED_FACT_CAPTURE_AND_CONFLICT",
            "EXPLICIT_PROVISIONAL_SUBJECT_PROMOTION", "IMMUTABLE_PUBLICATION",
            "EXISTING_WRITER_AND_JOURNAL", "ORDERED_V25_LIFECYCLE"
        ])
        XCTAssertEqual(value.evidenceCases.map(\.id), [
            "C26-S01", "C26-S02", "C26-S03", "C26-S04", "C26-S05", "C26-F01", "C26-B01"
        ])
        XCTAssertEqual(value.persistence.schemaRelease, "SURVEY_SESSION_V1")
        XCTAssertEqual(value.persistence.persistentSchemaVersion, 25)
        XCTAssertEqual(value.persistence.recordsSchemaVersion, 24)
        XCTAssertEqual(value.persistence.persistentKindLifecycleModelCount, 92)
        XCTAssertEqual(value.persistence.durableFamilyCount, 5)
        XCTAssertEqual(value.persistence.mode, "NEW_SCHEMA_VERSION")
        XCTAssertEqual(value.persistence.canonicalWriter, "V23-P02-C01")
        XCTAssertEqual(value.persistence.canonicalSourceOfTruth, durableFamilies)
        XCTAssertEqual(value.persistence.persistedFamilies, durableFamilies)
        XCTAssertEqual(value.persistence.currentProjectionRowCount, 0)
        XCTAssertEqual(value.persistence.providerRows, 0)
        XCTAssertTrue(value.persistence.migrationRequired)
        XCTAssertTrue(value.persistence.backupRestoreRequired)
        XCTAssertTrue(value.persistence.cloneForkRequired)
        XCTAssertTrue(value.persistence.deleteEraseRequired)
        XCTAssertTrue(value.persistence.exportReportRequired)
        XCTAssertTrue(value.persistence.searchRebuildRequired)
        XCTAssertTrue(value.persistence.replayRequired)
        XCTAssertTrue(value.persistence.interruptionRecoveryRequired)
        XCTAssertFalse(value.persistence.secondStore)
        XCTAssertFalse(value.persistence.secondWriter)
        XCTAssertTrue(value.statusFlags.values.allSatisfy { !$0 })
    }
}

extension V9_40SurveySessionTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV940SurveySessionTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C32AssistanceAnchorV940SurveySession: XCTestCase {
    func testC32V940SurveySessionCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .factCapture,
            fieldID: "survey-session.typed-fact",
            value: .triState(.notObserved)
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .factCapture,
            fieldID: "survey-session.typed-fact",
            valueKind: .triState
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
