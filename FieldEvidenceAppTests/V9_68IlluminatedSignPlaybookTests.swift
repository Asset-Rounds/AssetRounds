import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C03IlluminatedSignPlaybookCorpusV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let ordinal: Int
    let contentMode: String
    let eighthPlaybookForbidden: Bool
    let uiAdoptionEnabled: Bool
    let professionalCertificationClaimed: Bool
    let professionalCertificationRejected: Bool
    let professionalCertificationBoundary: String
    let optionalDecisionGateV1Present: Bool
    let optionalDecisionGateV1Enabled: Bool
    let optionalDecisionGateV1Forbidden: Bool
    let selectors: [Selector]
    let playbookIDs: [String]
    let captureSlots: [CaptureSlot]
    let visibleConditionDisplays: [Display]
    let couldNotVerifyReasons: [String]
    let claims: Claims
    let hashFields: [String]
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let recoveryCases: [String]
    let lifecycle: Lifecycle
    let accessibility: Accessibility
    let forbidden: [String]
    let hashAlgorithm: String

    struct Selector: Decodable {
        let id: String
        let selector: String
        let tier: String
    }

    struct CaptureSlot: Decodable {
        let id: String
        let purposeKey: String
        let required: Bool
    }

    struct Display: Decodable {
        let id: String
        let display: String
    }

    struct Claims: Decodable {
        let visibleConditionsOnly: Bool
        let comparisonIsProof: Bool
        let diagnosisClaimed: Bool
        let electricalCertification: Bool
        let safetyCertification: Bool
    }

    struct Lifecycle: Decodable {
        let persistence: String
        let schema: String
        let store: String
        let writer: String
        let evidence: String
        let backupRestoreDeleteErase: String
        let networkDependency: Bool
        let certificationAuthority: Bool
    }

    struct Accessibility: Decodable {
        let semanticIDCount: Int
        let requiredAndOptionalCaptureAreTextuallyDistinct: Bool
        let poseNeverUsesBareDirectionText: Bool
        let factsAndDisclaimerAreSpoken: Bool
        let uiConformanceClaimed: Bool
        let uiAdoptionClaimed: Bool
    }
}

private enum C03IlluminatedSignPlaybookTestFailure: Error {
    case interrupted
    case malformedFixture
}

private struct C03IlluminatedSignPlaybookFixture {
    let workspace: WorkspaceID
    let releaseDraft: InspectionPackageReleaseV1
    let release: InspectionPackageReleaseV1
    let codec: DraftPayloadCodecReleaseV1
    let registry: IlluminatedSignPlaybookRegistryV1
    let coordinator: IlluminatedSignPlaybookCoordinatorV1
    let associationEvents: [EvidenceAssociationV1]
    let evidenceSequence: EvidenceSequenceV1
    let poseTrace: IlluminatedSignPoseTraceV1
    let payload: IlluminatedSignPlaybookDraftPayloadV1
    let checkpoint: FieldDraftCheckpointV1
    let projection: IlluminatedSignPlaybookCheckpointProjectionV1
    let completion: IlluminatedSignPlaybookCompletionV1
    let reportSection: IlluminatedSignReportSectionV1
}

private enum C03IlluminatedSignPlaybookTestSupport {
    // 2026-08-31T00:00:00Z is 2026-08-30 20:00:00 in America/New_York.
    static let fixedDate = Date(timeIntervalSince1970: 1_788_134_400)
    static let fixedDigest = String(repeating: "a", count: 64)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func workspace(_ value: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(300_000 + value))
    }

    static func subject(_ workspace: WorkspaceID) throws -> EvidenceAssociationTargetV1 {
        try EvidenceAssociationTargetV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            kind: .asset,
            targetID: id(540_002).uuidString.lowercased(),
            targetRevision: 1
        )
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(400_000 + value))
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int,
        responsibility: ResponsibilityKindV1
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(500_000 + slot),
            workspaceID: workspaceID,
            displayName: "C03 local reviewer"
        )
        return try ActorSnapshotV1(
            snapshotID: id(510_000 + slot),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: responsibility,
            displayNameAtTime: reference.displayName,
            capturedAt: fixedDate
        )
    }

    static func releasePair() throws -> (InspectionPackageReleaseV1, InspectionPackageReleaseV1) {
        let workflow = try WorkflowDefinitionV1(
            workflowID: "c03.illuminated.sign.workflow",
            entryNodeID: "start",
            declaredFieldIDs: [],
            nodes: [
                try .init(
                    nodeID: "start",
                    kind: .section,
                    localizationKey: "c03.illuminated.start",
                    outgoingNodeIDs: ["end"]
                ),
                try .init(
                    nodeID: "end",
                    kind: .terminal,
                    localizationKey: "c03.illuminated.end",
                    outgoingNodeIDs: []
                ),
            ]
        )
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: workflow
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        let published = try InspectionPackageReleasePublisherV1.publish(tested)
        return (draft, published.release)
    }

    static func association(
        workspace: WorkspaceID,
        index: Int,
        target: EvidenceAssociationTargetV1
    ) throws -> EvidenceAssociationV1 {
        let workspaceString = workspace.rawValue.uuidString.lowercased()
        return try EvidenceAssociationV1(
            associationEventID: "c03-association-\(index)",
            workspaceID: workspaceString,
            evidenceID: "c03-evidence-\(index)",
            expectedEvidenceRevision: 0,
            resultingEvidenceRevision: 1,
            mutationID: id(520_000 + index).uuidString.lowercased(),
            action: .assigned,
            contentID: "c03-content-\(index)",
            target: target,
            actorID: "c03-actor-\(index)",
            reason: "Attach visible sign evidence.",
            effectiveAt: String(format: "2026-08-30T00:%02d:00.000Z", index)
        )
    }

    static func evidenceBundle(
        workspace: WorkspaceID,
        indexBase: Int = 1
    ) throws -> ([EvidenceAssociationV1], EvidenceSequenceV1) {
        let target = try subject(workspace)
        let events = try [
            association(workspace: workspace, index: indexBase, target: target),
            association(workspace: workspace, index: indexBase + 1, target: target),
        ]
        let policy = try EvidenceCurationPolicyV1(
            policyID: id(530_000 + indexBase),
            workspaceID: workspace
        )
        let reviewer = try actor(
            workspaceID: workspace,
            slot: 531_000 + indexBase,
            responsibility: .reviewedBy
        )
        let items = try events.enumerated().map { offset, event in
            guard let contentID = event.contentID, let eventTarget = event.target else {
                throw C03IlluminatedSignPlaybookTestFailure.malformedFixture
            }
            return try EvidenceSequenceItemV1(
                evidenceID: event.evidenceID,
                contentID: contentID,
                role: offset == 0 ? .context : .detail,
                caption: try EvidenceReviewedCaptionV1(
                    text: "C03 reviewed source \(offset + 1)",
                    provenance: .userAuthored,
                    reviewer: reviewer,
                    reviewedAt: fixedDate.addingTimeInterval(Double(offset))
                ),
                accessibilityDescription: try EvidenceAccessibilityDescriptionV1(
                    text: "Reviewed sign source \(offset + 1).",
                    provenance: .userAuthored,
                    reviewer: reviewer,
                    reviewedAt: fixedDate.addingTimeInterval(Double(offset))
                ),
                ordinal: offset,
                target: eventTarget,
                association: event
            )
        }
        let sequence = try EvidenceSequenceV1(
            sequenceID: id(532_000 + indexBase),
            workspaceID: workspace,
            target: target,
            policy: policy,
            orderedItems: items,
            revision: 1,
            mutationID: try mutation(533_000 + indexBase)
        )
        return (events, sequence)
    }

    static func poseTrace(workspace: WorkspaceID) throws -> IlluminatedSignPoseTraceV1 {
        let descriptor = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c03.sign-face"),
            localizedLabelKey: "pose.c03.sign-face",
            semanticRole: .signFaceNormal,
            requiredComponents: .azimuthOnly,
            observationRequirement: .requiredForCompletion,
            applicability: .applicable
        )
        let eventID = id(540_001)
        let pose = try PlacementPoseV1(
            disposition: .observed,
            referenceFrame: .trueBearing,
            azimuth: try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: 90_000),
            horizontalUncertainty: .known(
                try PoseAngleMilliDegreesV1(kind: .horizontalUncertainty, milliDegrees: 1)
            ),
            descriptor: descriptor
        )
        let event = try AssetPoseEventV1(
            eventID: eventID,
            workspaceID: workspace,
            assetID: id(540_002),
            axisDescriptor: descriptor,
            placementEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: id(540_003)),
            placementEventID: id(540_004),
            locationPathSnapshot: try LocationPathSnapshotV1(
                siteID: id(540_005),
                siteDisplay: "C03 sign site",
                nodes: []
            ),
            pose: pose,
            source: .manual,
            rootObservationEventID: eventID,
            rootObservedAt: fixedDate,
            predecessor: nil,
            revision: 1,
            mutationID: try mutation(540_006),
            recordedBy: try actor(workspaceID: workspace, slot: 540_007, responsibility: .observedBy),
            occurredAt: fixedDate,
            recordedAt: fixedDate.addingTimeInterval(1)
        )
        return try IlluminatedSignPoseTraceV1(descriptor: descriptor, event: event)
    }

    static func checkpoint(
        workspace: WorkspaceID,
        payloadData: Data,
        codec: DraftPayloadCodecReleaseV1,
        scope: DraftScopeKeyV1? = nil,
        revision: UInt64 = 1,
        state: FieldDraftStateV1 = .active,
        mutationSeed: Int = 550_001,
        updatedAt: Date = fixedDate
    ) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(
            draftID: id(550_000),
            workspaceID: workspace,
            scope: try scope ?? IlluminatedSignPlaybookDraftScopeV1.make(
                subject: subject(workspace), playbookID: .darkSection
            ),
            purpose: .evidenceCuration,
            codec: codec,
            baseCanonicalRevision: 0,
            draftRevision: revision,
            payloadData: payloadData,
            stageIDs: [],
            resumeAnchor: try DraftResumeAnchorV1(
                sectionID: "illuminated-sign",
                fieldID: "dark_section",
                selectedStableID: "dark_section",
                boundedPosition: 1
            ),
            state: state,
            updatedAt: updatedAt,
            mutationID: try mutation(mutationSeed)
        )
    }

    static func makeFixture() throws -> C03IlluminatedSignPlaybookFixture {
        let workspace = workspace()
        let (releaseDraft, release) = try releasePair()
        let codec = try DraftPayloadCodecReleaseV1(
            codecID: "c03.illuminated-sign",
            codecVersion: 1,
            releaseSHA256: fixedDigest
        )
        let registry = try ShippingIlluminatedSignAdapterV1.playbookRegistry(
            release: release,
            draftCodec: codec
        )
        let coordinator = try IlluminatedSignPlaybookCoordinatorV1(registry: registry)
        let (associationEvents, evidenceSequence) = try evidenceBundle(workspace: workspace)
        let captures = try evidenceSequence.orderedItems.enumerated().map { offset, item in
            try IlluminatedSignCaptureTraceV1(
                slotID: offset == 0 ? .wideContext : .closeDetail,
                purposeKey: offset == 0 ? "wide_context" : "close_detail",
                item: item
            )
        }
        let pose = try poseTrace(workspace: workspace)
        let checkedTime = try IlluminatedSignCheckedTimeV1(
            context: TimeContextSnapshotV1(
                localDate: "2026-08-30",
                localTime: "20:00:00",
                observedAtUTC: fixedDate,
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -240
            )
        )
        let display = try XCTUnwrapForC03(
            registry.visibleConditionDisplays[IlluminatedSignPlaybookIDV1.darkSection.rawValue]
        )
        let payload = try coordinator.payload(
            workspaceID: workspace,
            playbookID: .darkSection,
            subject: evidenceSequence.target,
            stage: .check,
            checkedTime: checkedTime,
            selectedVisibleCondition: try IlluminatedSignSelectedVisibleConditionV1(
                playbookID: .darkSection,
                frozenDisplay: display
            ),
            captures: captures,
            outcome: .visibleIssue,
            poseTrace: pose
        )
        let payloadData = try coordinator.canonicalPayloadData(payload)
        let checkpoint = try checkpoint(
            workspace: workspace,
            payloadData: payloadData,
            codec: codec
        )
        let projection = try coordinator.project(
            checkpoint: checkpoint,
            associationEvents: associationEvents,
            evidenceSequence: evidenceSequence,
            evidenceSequenceHistory: [evidenceSequence],
            poseEventHistory: [pose.event]
        )
        let completion = try coordinator.complete(
            checkpoint: checkpoint,
            associationEvents: associationEvents,
            evidenceSequence: evidenceSequence,
            evidenceSequenceHistory: [evidenceSequence],
            poseEventHistory: [pose.event]
        )
        let reportSection = try coordinator.reportSection(
            for: completion,
            checkpoint: checkpoint,
            associationEvents: associationEvents,
            evidenceSequence: evidenceSequence,
            evidenceSequenceHistory: [evidenceSequence],
            poseEventHistory: [pose.event]
        )
        return C03IlluminatedSignPlaybookFixture(
            workspace: workspace,
            releaseDraft: releaseDraft,
            release: release,
            codec: codec,
            registry: registry,
            coordinator: coordinator,
            associationEvents: associationEvents,
            evidenceSequence: evidenceSequence,
            poseTrace: pose,
            payload: payload,
            checkpoint: checkpoint,
            projection: projection,
            completion: completion,
            reportSection: reportSection
        )
    }
}

private func XCTUnwrapForC03<T>(_ value: T?) throws -> T {
    guard let value else { throw C03IlluminatedSignPlaybookTestFailure.malformedFixture }
    return value
}

final class V9_68IlluminatedSignPlaybookTests: XCTestCase {
    func testV23P04C03G01ExactSevenPlaybookManifestAndCaptureMatrix() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "G01", tier: "GOLDEN")
        let fixture = try C03IlluminatedSignPlaybookTestSupport.makeFixture()
        let pack = SignPack.illuminatedSignV1
        let parity = try ShippingIlluminatedSignAdapterV1.parityReceipt()

        XCTAssertEqual(fixture.registry.schemaVersion, 1)
        XCTAssertEqual(fixture.registry.manifests.map { $0.playbookID.rawValue }, corpus.playbookIDs)
        XCTAssertEqual(
            fixture.registry.manifests.map(\.playbookID),
            IlluminatedSignPlaybookIDV1.canonicalOrder
        )
        XCTAssertEqual(Set(fixture.registry.manifests.map(\.playbookID)).count, 7)
        XCTAssertEqual(fixture.registry.sourcePackSHA256, parity.sourceCanonicalSHA256)
        XCTAssertTrue(parity.exactParity)
        XCTAssertEqual(fixture.registry.evidencePurposeKeys, ["close_detail", "wide_context", "work_context"])
        XCTAssertEqual(
            fixture.registry.evidencePurposeKeys,
            corpus.captureSlots.map(\.purposeKey).sorted()
        )
        XCTAssertEqual(pack.evidencePurposes.map(\.key), ["wide_context", "close_detail", "work_context"])
        XCTAssertEqual(
            fixture.registry.visibleConditionDisplays,
            Dictionary(uniqueKeysWithValues: corpus.visibleConditionDisplays.map { ($0.id, $0.display) })
        )
        XCTAssertEqual(
            Set(fixture.registry.couldNotVerifyReasons.keys),
            Set(corpus.couldNotVerifyReasons)
        )
        XCTAssertEqual(fixture.registry.couldNotVerifyRegistryVersion, pack.couldNotVerifyReasons.version)
        try fixture.registry.validate()

        for manifest in fixture.registry.manifests {
            XCTAssertEqual(manifest.captureRequirements.map(\.slotID), IlluminatedSignCaptureSlotIDV1.canonicalOrder)
            XCTAssertEqual(manifest.captureRequirements.map(\.purposeKey), corpus.captureSlots.map(\.purposeKey))
            XCTAssertEqual(manifest.captureRequirements.map(\.required), [true, true, false])
            XCTAssertEqual(manifest.visibleConditionClaim, .visibleConditionsOnly)
            XCTAssertFalse(manifest.comparisonIsProof)
            XCTAssertFalse(manifest.electricalCertification)
            XCTAssertFalse(manifest.safetyCertification)
            XCTAssertEqual(manifest.reportSectionID, "illuminated_sign.playbook.\(manifest.playbookID.rawValue)")
            XCTAssertTrue(KernelCanonicalHashV1.validSHA256(manifest.manifestSHA256))
        }
        XCTAssertEqual(corpus.hashAlgorithm, "SHA-256")
        try IlluminatedSignPlaybookAccessibilityPolicyV1.validate()
        try IlluminatedSignPlaybookLocalizationPolicyV1.validate()

        let missing = Array(fixture.registry.manifests.dropLast())
        XCTAssertThrowsError(try IlluminatedSignPlaybookRegistryV1(
            release: fixture.release,
            sourcePackSHA256: fixture.registry.sourcePackSHA256,
            draftCodec: fixture.codec,
            manifests: missing,
            evidencePurposeKeys: pack.evidencePurposes.map(\.key),
            visibleConditionDisplays: fixture.registry.visibleConditionDisplays,
            disclaimer: fixture.registry.disclaimer,
            couldNotVerifyRegistryVersion: fixture.registry.couldNotVerifyRegistryVersion,
            couldNotVerifyReasons: fixture.registry.couldNotVerifyReasons
        ))
        let duplicate = fixture.registry.manifests + [fixture.registry.manifests[0]]
        XCTAssertThrowsError(try IlluminatedSignPlaybookRegistryV1(
            release: fixture.release,
            sourcePackSHA256: fixture.registry.sourcePackSHA256,
            draftCodec: fixture.codec,
            manifests: duplicate,
            evidencePurposeKeys: pack.evidencePurposes.map(\.key),
            visibleConditionDisplays: fixture.registry.visibleConditionDisplays,
            disclaimer: fixture.registry.disclaimer,
            couldNotVerifyRegistryVersion: fixture.registry.couldNotVerifyRegistryVersion,
            couldNotVerifyReasons: fixture.registry.couldNotVerifyReasons
        ))
        XCTAssertNil(IlluminatedSignPlaybookIDV1(rawValue: "eighth_playbook"))
    }

    func testV23P04C03A01StructuredReportFactTraceabilityAndPoseBinding() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "A01", tier: "ALTERNATE")
        let fixture = try C03IlluminatedSignPlaybookTestSupport.makeFixture()

        XCTAssertEqual(fixture.projection.completeness.state, .complete)
        XCTAssertEqual(fixture.projection.completeness.missingRequiredSlots, [])
        XCTAssertTrue(fixture.projection.completeness.hasReviewedPose)
        XCTAssertEqual(fixture.payload.captures.map(\.slotID), [.wideContext, .closeDetail])
        XCTAssertEqual(fixture.payload.captures.map(\.item), fixture.evidenceSequence.orderedItems)
        XCTAssertEqual(fixture.payload.stage, .check)
        XCTAssertEqual(fixture.payload.selectedVisibleCondition?.playbookID, .darkSection)
        XCTAssertEqual(fixture.payload.outcome, .visibleIssue)
        XCTAssertEqual(fixture.payload.subject, fixture.evidenceSequence.target)
        XCTAssertEqual(fixture.payload.subject.workspaceID, fixture.workspace.rawValue.uuidString.lowercased())
        XCTAssertEqual(fixture.payload.subject.kind, .asset)
        XCTAssertEqual(fixture.payload.subject.targetID, fixture.poseTrace.event.assetID.uuidString.lowercased())
        XCTAssertEqual(fixture.payload.checkedTime.context.localDate, "2026-08-30")
        XCTAssertEqual(fixture.payload.checkedTime.context.localTime, "20:00:00")
        XCTAssertEqual(fixture.payload.checkedTime.context.timeZoneID, "America/New_York")
        XCTAssertEqual(fixture.payload.checkedTime.context.utcOffsetMinutes, -240)
        XCTAssertEqual(fixture.poseTrace.descriptor.semanticRole, .signFaceNormal)
        XCTAssertEqual(fixture.poseTrace.event.pose.referenceFrame, .trueBearing)
        XCTAssertEqual(fixture.completion.fact.visibleConditionClaim, .visibleConditionsOnly)
        XCTAssertFalse(fixture.completion.fact.comparisonIsProof)
        XCTAssertFalse(fixture.completion.fact.diagnosisClaimed)
        XCTAssertFalse(fixture.completion.fact.electricalCertification)
        XCTAssertFalse(fixture.completion.fact.safetyCertification)
        XCTAssertEqual(fixture.completion.fact.captures, fixture.payload.captures)
        XCTAssertEqual(fixture.completion.evidenceSequenceFrontier, try fixture.evidenceSequence.frontier)
        XCTAssertEqual(fixture.completion.poseEventFrontier, fixture.poseTrace.eventReference)
        XCTAssertEqual(fixture.completion.checkpointDraftID, fixture.checkpoint.draftID)
        XCTAssertEqual(fixture.completion.checkpointDraftRevision, fixture.checkpoint.draftRevision)
        XCTAssertEqual(fixture.completion.checkpointSHA256, fixture.checkpoint.checkpointSHA256)
        XCTAssertEqual(
            Set(fixture.payload.captures.map { $0.item.associationBinding.associationEventID }),
            Set(fixture.associationEvents.map(\.associationEventID))
        )
        XCTAssertTrue(fixture.reportSection.visibleConditionsOnly)
        XCTAssertTrue(fixture.reportSection.nonCertificationStatementRequired)
        XCTAssertEqual(fixture.reportSection.fact.factSHA256, fixture.completion.fact.factSHA256)

        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.decodeRegistry(
                from: try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.registry)
            ),
            fixture.registry
        )
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.decodeDraftPayload(
                from: try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.payload),
                registry: fixture.registry
            ),
            fixture.payload
        )
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.decode(
                FieldDraftCheckpointV1.self,
                from: try FieldDraftCanonicalCodecV1.encode(fixture.checkpoint)
            ),
            fixture.checkpoint
        )
        XCTAssertEqual(
            try EvidenceMetadataCanonicalCodecV1.decode(
                EvidenceSequenceV1.self,
                from: try EvidenceMetadataCanonicalCodecV1.data(fixture.evidenceSequence)
            ),
            fixture.evidenceSequence
        )
        XCTAssertEqual(
            try PlacementPoseCanonicalCodecV1.decode(
                AssetPoseEventV1.self,
                from: try PlacementPoseCanonicalCodecV1.encode(fixture.poseTrace.event)
            ),
            fixture.poseTrace.event
        )
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.decodeCompletion(
                from: try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.completion),
                checkpoint: fixture.checkpoint,
                payload: fixture.payload,
                completeness: fixture.projection.completeness,
                evidenceSequence: fixture.evidenceSequence,
                registry: fixture.registry
            ),
            fixture.completion
        )
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.decodeReportSection(
                from: try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.reportSection),
                completion: fixture.completion,
                registry: fixture.registry
            ),
            fixture.reportSection
        )

        let committing = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(fixture.payload),
            codec: fixture.codec,
            revision: 2,
            state: .committing,
            mutationSeed: 550_002,
            updatedAt: C03IlluminatedSignPlaybookTestSupport.fixedDate.addingTimeInterval(1)
        )
        try committing.validateSuccessor(
            of: fixture.checkpoint,
            expectedDraftRevision: fixture.checkpoint.draftRevision,
            expectedBaseRevision: fixture.checkpoint.baseCanonicalRevision
        )
        let successorProjection = try fixture.coordinator.project(
            checkpoint: committing,
            predecessor: fixture.checkpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        )
        XCTAssertEqual(successorProjection.payload, fixture.payload)
        XCTAssertEqual(successorProjection.completeness.state, .complete)

        let noVisibleIssue = try fixture.coordinator.payload(
            workspaceID: fixture.workspace,
            playbookID: .darkSection,
            subject: fixture.evidenceSequence.target,
            stage: .recheck,
            checkedTime: fixture.payload.checkedTime,
            captures: fixture.payload.captures,
            outcome: .noVisibleIssue,
            poseTrace: fixture.poseTrace
        )
        let noVisibleCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(noVisibleIssue),
            codec: fixture.codec,
            revision: 3,
            mutationSeed: 550_003,
            updatedAt: C03IlluminatedSignPlaybookTestSupport.fixedDate.addingTimeInterval(2)
        )
        let noVisibleCompletion = try fixture.coordinator.complete(
            checkpoint: noVisibleCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        )
        XCTAssertEqual(noVisibleCompletion.fact.outcome, .noVisibleIssue)
        XCTAssertNil(noVisibleCompletion.fact.selectedVisibleCondition)
        XCTAssertNil(noVisibleCompletion.fact.couldNotVerify)

        let couldNotVerify = try IlluminatedSignCouldNotVerifyV1(
            reasonKey: "access_lost",
            frozenDisplay: try XCTUnwrapForC03(fixture.registry.couldNotVerifyReasons["access_lost"]),
            registryVersion: fixture.registry.couldNotVerifyRegistryVersion
        )
        let zeroCaptureCouldNotVerify = try fixture.coordinator.payload(
            workspaceID: fixture.workspace,
            playbookID: .darkSection,
            subject: fixture.evidenceSequence.target,
            stage: .recheck,
            checkedTime: fixture.payload.checkedTime,
            outcome: .couldNotVerify,
            couldNotVerify: couldNotVerify
        )
        let couldNotVerifyCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(zeroCaptureCouldNotVerify),
            codec: fixture.codec,
            revision: 4,
            mutationSeed: 550_004,
            updatedAt: C03IlluminatedSignPlaybookTestSupport.fixedDate.addingTimeInterval(3)
        )
        let couldNotVerifyCompletion = try fixture.coordinator.complete(
            checkpoint: couldNotVerifyCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: []
        )
        XCTAssertEqual(couldNotVerifyCompletion.fact.outcome, .couldNotVerify)
        XCTAssertEqual(couldNotVerifyCompletion.fact.couldNotVerify, couldNotVerify)
        XCTAssertTrue(couldNotVerifyCompletion.fact.captures.isEmpty)
        XCTAssertNil(couldNotVerifyCompletion.fact.poseTrace)
    }

    func testV23P04C03H01ClaimsSafeAdmissionRejectsUnsafeAndUndeclaredContent() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "H01", tier: "HOSTILE")
        let fixture = try C03IlluminatedSignPlaybookTestSupport.makeFixture()
        XCTAssertEqual(corpus.hostileCases.count, 17)
        XCTAssertTrue(corpus.hostileCases.contains("unsafe-claim"))
        XCTAssertTrue(corpus.hostileCases.contains("missing-capture-trace"))
        XCTAssertTrue(corpus.hostileCases.contains("cross-workspace-sequence"))
        XCTAssertTrue(corpus.hostileCases.contains("canonical-byte-overflow"))

        XCTAssertThrowsError(try IlluminatedSignCaptureRequirementV1(
            slotID: .wideContext, purposeKey: "close_detail", required: true
        ))
        XCTAssertThrowsError(try IlluminatedSignCaptureRequirementV1(
            slotID: .workContext, purposeKey: "work_context", required: true
        ))
        XCTAssertThrowsError(try IlluminatedSignCouldNotVerifyV1(
            reasonKey: "capture_unavailable",
            frozenDisplay: String(repeating: "x", count: 513),
            registryVersion: fixture.registry.couldNotVerifyRegistryVersion
        ))
        XCTAssertThrowsError(try IlluminatedSignSelectedVisibleConditionV1(
            playbookID: .darkSection,
            frozenDisplay: String(repeating: "x", count: 513)
        ))
        XCTAssertThrowsError(try IlluminatedSignPlaybookManifestV1(
            playbookID: .darkSection,
            manifestVersion: 0,
            release: fixture.release,
            sourcePackSHA256: fixture.registry.sourcePackSHA256,
            captureRequirements: fixture.registry.manifests[0].captureRequirements
        ))
        XCTAssertThrowsError(try IlluminatedSignPlaybookManifestV1(
            playbookID: .darkSection,
            release: fixture.release,
            sourcePackSHA256: fixture.registry.sourcePackSHA256,
            captureRequirements: fixture.registry.manifests[0].captureRequirements,
            reportSectionVersion: 0
        ))

        let badDisplay = try IlluminatedSignCouldNotVerifyV1(
            reasonKey: "capture_unavailable",
            frozenDisplay: "Forged display",
            registryVersion: fixture.registry.couldNotVerifyRegistryVersion
        )
        XCTAssertThrowsError(try fixture.coordinator.payload(
            workspaceID: fixture.workspace,
            playbookID: .darkSection,
            subject: fixture.evidenceSequence.target,
            stage: .check,
            checkedTime: fixture.payload.checkedTime,
            outcome: .couldNotVerify,
            couldNotVerify: badDisplay
        ))

        let incompletePayload = try fixture.coordinator.payload(
            workspaceID: fixture.workspace,
            playbookID: .darkSection,
            subject: fixture.evidenceSequence.target,
            stage: .check,
            checkedTime: fixture.payload.checkedTime,
            selectedVisibleCondition: fixture.payload.selectedVisibleCondition,
            outcome: .visibleIssue
        )
        let incompleteCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(incompletePayload),
            codec: fixture.codec,
            mutationSeed: 551_001
        )
        XCTAssertThrowsError(try fixture.coordinator.complete(
            checkpoint: incompleteCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        ))

        XCTAssertThrowsError(try fixture.coordinator.payload(
            workspaceID: fixture.workspace,
            playbookID: .darkSection,
            subject: fixture.evidenceSequence.target,
            stage: .check,
            checkedTime: fixture.payload.checkedTime,
            selectedVisibleCondition: fixture.payload.selectedVisibleCondition,
            captures: fixture.payload.captures + [fixture.payload.captures[0]],
            outcome: .visibleIssue,
            poseTrace: fixture.poseTrace
        ))
        XCTAssertThrowsError(try IlluminatedSignPlaybookDraftPayloadV1(
            workspaceID: fixture.workspace,
            playbookID: .darkSection,
            registry: fixture.registry,
            stage: .check,
            checkedTime: fixture.payload.checkedTime,
            selectedVisibleCondition: fixture.payload.selectedVisibleCondition,
            captures: fixture.payload.captures + [fixture.payload.captures[0]],
            outcome: .visibleIssue,
            poseTrace: fixture.poseTrace
        ))

        let foreignWorkspace = C03IlluminatedSignPlaybookTestSupport.workspace(2)
        let (_, foreignSequence) = try C03IlluminatedSignPlaybookTestSupport.evidenceBundle(
            workspace: foreignWorkspace,
            indexBase: 10
        )
        XCTAssertThrowsError(try fixture.coordinator.project(
            checkpoint: fixture.checkpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: foreignSequence,
            evidenceSequenceHistory: [foreignSequence],
            poseEventHistory: [fixture.poseTrace.event]
        ))

        let wrongScopeKind = try DraftScopeKeyV1(
            scopeKind: "illuminated-sign-playbook-foreign",
            stableComponentIDs: ["c03-sign", "dark_section"]
        )
        let wrongScopeCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(fixture.payload),
            codec: fixture.codec,
            scope: wrongScopeKind,
            mutationSeed: 551_010
        )
        XCTAssertThrowsError(try fixture.coordinator.project(
            checkpoint: wrongScopeCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        ))
        let expectedScope = try IlluminatedSignPlaybookDraftScopeV1.make(
            subject: fixture.payload.subject,
            playbookID: fixture.payload.playbookID
        )
        let extraScopeComponent = try DraftScopeKeyV1(
            scopeKind: expectedScope.scopeKind,
            stableComponentIDs: expectedScope.stableComponentIDs + ["forbidden-extra-component"]
        )
        let extraScopeCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(fixture.payload),
            codec: fixture.codec,
            scope: extraScopeComponent,
            mutationSeed: 551_011
        )
        XCTAssertThrowsError(try fixture.coordinator.project(
            checkpoint: extraScopeCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        ))

        let wrongDescriptor = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c03.wrong"),
            localizedLabelKey: "pose.c03.wrong",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .requiredForCompletion,
            applicability: .applicable
        )
        XCTAssertThrowsError(try IlluminatedSignPoseTraceV1(
            descriptor: wrongDescriptor,
            event: fixture.poseTrace.event
        ))

        var corruptPayloadData = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.payload)
        corruptPayloadData[corruptPayloadData.startIndex] ^= 0x01
        XCTAssertThrowsError(try IlluminatedSignPlaybookCanonicalCodecV1.decodeDraftPayload(
            from: corruptPayloadData, registry: fixture.registry
        ))
        XCTAssertThrowsError(try IlluminatedSignPlaybookCanonicalCodecV1.decodeDraftPayload(
            from: Data(repeating: 0, count: IlluminatedSignPlaybookLimitsV1.maximumCanonicalBytes + 1),
            registry: fixture.registry
        ))

        var forgedPayloadObject = try XCTUnwrapForC03(
            JSONSerialization.jsonObject(
                with: try fixture.coordinator.canonicalPayloadData(fixture.payload)
            ) as? [String: Any]
        )
        forgedPayloadObject["payloadSHA256"] = String(repeating: "0", count: 64)
        let forgedDigestData = try JSONSerialization.data(
            withJSONObject: forgedPayloadObject, options: [.sortedKeys]
        )
        XCTAssertThrowsError(try IlluminatedSignPlaybookCanonicalCodecV1.decodeDraftPayload(
            from: forgedDigestData, registry: fixture.registry
        ))
        forgedPayloadObject["unknownShippingKey"] = "must-not-expand-contract"
        let unknownKeyData = try JSONSerialization.data(
            withJSONObject: forgedPayloadObject, options: [.sortedKeys]
        )
        XCTAssertThrowsError(try IlluminatedSignPlaybookCanonicalCodecV1.decodeDraftPayload(
            from: unknownKeyData, registry: fixture.registry
        ))

        let unsafeFactData = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.completion.fact)
        var unsafeObject = try XCTUnwrapForC03(
            JSONSerialization.jsonObject(with: unsafeFactData) as? [String: Any]
        )
        unsafeObject["comparisonIsProof"] = true
        unsafeObject["diagnosisClaimed"] = true
        unsafeObject["electricalCertification"] = true
        unsafeObject["safetyCertification"] = true
        let unsafeData = try JSONSerialization.data(withJSONObject: unsafeObject, options: [.sortedKeys])
        let unsafeFact = try JSONDecoder().decode(IlluminatedSignStructuredFactV1.self, from: unsafeData)
        XCTAssertThrowsError(try unsafeFact.validate(
            manifest: try fixture.registry.manifest(for: .darkSection),
            registry: fixture.registry
        ))
        XCTAssertFalse(fixture.completion.fact.diagnosisClaimed)
        XCTAssertFalse(fixture.completion.fact.electricalCertification)
        XCTAssertFalse(fixture.completion.fact.safetyCertification)
    }

    func testV23P04C03I01InterruptedCaptureCheckpointAndReplayAreZeroOrComplete() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "I01", tier: "INTERRUPTION")
        let fixture = try C03IlluminatedSignPlaybookTestSupport.makeFixture()
        XCTAssertEqual(
            corpus.interruptionBoundaries,
            [
                "before-validation",
                "after-validation-before-publication",
                "after-publication-before-receipt",
                "before-checkpoint-projection",
                "after-checkpoint-projection",
                "relaunch-recovery-required",
            ]
        )

        for boundary in InspectionPackageReleasePublisherV1.Boundary.allCases {
            XCTAssertThrowsError(try InspectionPackageReleasePublisherV1.test(
                fixture.releaseDraft,
                interruption: { observed in
                    if observed == boundary { throw C03IlluminatedSignPlaybookTestFailure.interrupted }
                }
            ))
        }

        let committing = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(fixture.payload),
            codec: fixture.codec,
            revision: 2,
            state: .committing,
            mutationSeed: 552_002,
            updatedAt: C03IlluminatedSignPlaybookTestSupport.fixedDate.addingTimeInterval(1)
        )
        let recovering = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: try fixture.coordinator.canonicalPayloadData(fixture.payload),
            codec: fixture.codec,
            revision: 3,
            state: .recoveryRequired,
            mutationSeed: 552_003,
            updatedAt: C03IlluminatedSignPlaybookTestSupport.fixedDate.addingTimeInterval(2)
        )
        try recovering.validateSuccessor(
            of: committing,
            expectedDraftRevision: committing.draftRevision,
            expectedBaseRevision: committing.baseCanonicalRevision
        )
        let recovery = try fixture.coordinator.recover(
            checkpoint: recovering,
            predecessor: committing,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        )
        XCTAssertEqual(recovery.projection.completeness.state, .complete)
        XCTAssertEqual(recovery.projection.payload, fixture.payload)
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(recovery.projection.payload),
            try fixture.coordinator.canonicalPayloadData(fixture.payload)
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(recovery.recoverySHA256))
        XCTAssertEqual(
            try fixture.coordinator.recover(
                checkpoint: recovering,
                predecessor: committing,
                associationEvents: fixture.associationEvents,
                evidenceSequence: fixture.evidenceSequence,
                evidenceSequenceHistory: [fixture.evidenceSequence],
                poseEventHistory: [fixture.poseTrace.event]
            ),
            recovery
        )

        var malformedBytes = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.payload)
        malformedBytes[malformedBytes.count - 1] ^= 0x01
        let malformedCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: malformedBytes,
            codec: fixture.codec,
            mutationSeed: 552_004
        )
        XCTAssertThrowsError(try fixture.coordinator.project(
            checkpoint: malformedCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        ))

        let first = try fixture.coordinator.complete(
            checkpoint: fixture.checkpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        )
        let retry = try fixture.coordinator.complete(
            checkpoint: fixture.checkpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        )
        XCTAssertEqual(first, retry)
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(first),
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(retry)
        )
        XCTAssertEqual(fixture.checkpoint.state, .active)
        XCTAssertEqual(fixture.checkpoint.lastReceiptSHA256, nil)
    }

    func testV23P04C03R01PlaybookRemovalPreservesKernelAndHistoricTruth() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "R01", tier: "RECOVERY")
        let fixture = try C03IlluminatedSignPlaybookTestSupport.makeFixture()
        XCTAssertEqual(corpus.recoveryCases.count, 8)
        XCTAssertEqual(
            corpus.lifecycle.persistence,
            IlluminatedSignPlaybookLifecycleV1.persistence
        )
        XCTAssertEqual(corpus.lifecycle.schema, IlluminatedSignPlaybookLifecycleV1.schema)
        XCTAssertEqual(corpus.lifecycle.store, IlluminatedSignPlaybookLifecycleV1.store)
        XCTAssertEqual(corpus.lifecycle.writer, IlluminatedSignPlaybookLifecycleV1.writer)
        XCTAssertEqual(corpus.lifecycle.evidence, IlluminatedSignPlaybookLifecycleV1.evidence)
        XCTAssertEqual(
            corpus.lifecycle.backupRestoreDeleteErase,
            IlluminatedSignPlaybookLifecycleV1.backupRestoreDeleteErase
        )
        XCTAssertFalse(corpus.lifecycle.networkDependency)
        XCTAssertFalse(corpus.lifecycle.certificationAuthority)
        XCTAssertEqual(corpus.forbidden.count, 11)
        XCTAssertTrue(corpus.forbidden.contains("NEW_PLAYBOOK_STORE"))
        XCTAssertTrue(corpus.forbidden.contains("BARE_DIRECTION_STORAGE"))
        XCTAssertTrue(corpus.forbidden.contains("PROFESSIONAL_CERTIFICATION"))
        XCTAssertTrue(corpus.forbidden.contains("TELEMETRY"))
        XCTAssertEqual(corpus.hashFields.count, 7)

        let originalRegistryBytes = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.registry)
        let originalPayloadBytes = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.payload)
        let originalCompletionBytes = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.completion)
        let originalSectionBytes = try IlluminatedSignPlaybookCanonicalCodecV1.encode(fixture.reportSection)
        let originalCheckpointBytes = try FieldDraftCanonicalCodecV1.encode(fixture.checkpoint)
        let originalSequenceBytes = try EvidenceMetadataCanonicalCodecV1.data(fixture.evidenceSequence)
        let originalPoseBytes = try PlacementPoseCanonicalCodecV1.encode(fixture.poseTrace.event)

        try EvidenceMetadataGraphV1.validate(
            sequences: [fixture.evidenceSequence],
            associationEvents: fixture.associationEvents
        )
        _ = try AssetPoseHistoryV1.currentTip(
            workspaceID: fixture.workspace,
            assetID: fixture.poseTrace.event.assetID,
            events: [fixture.poseTrace.event]
        )

        let recoveredCheckpoint = try C03IlluminatedSignPlaybookTestSupport.checkpoint(
            workspace: fixture.workspace,
            payloadData: originalPayloadBytes,
            codec: fixture.codec,
            revision: 2,
            state: .recoveryRequired,
            mutationSeed: 553_002,
            updatedAt: C03IlluminatedSignPlaybookTestSupport.fixedDate.addingTimeInterval(1)
        )
        let recovered = try fixture.coordinator.recover(
            checkpoint: recoveredCheckpoint,
            associationEvents: fixture.associationEvents,
            evidenceSequence: fixture.evidenceSequence,
            evidenceSequenceHistory: [fixture.evidenceSequence],
            poseEventHistory: [fixture.poseTrace.event]
        )
        XCTAssertEqual(recovered.projection.payload, fixture.payload)
        XCTAssertEqual(recovered.projection.completeness.state, .complete)
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(recovered.projection.payload),
            originalPayloadBytes
        )

        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(
                try IlluminatedSignPlaybookCanonicalCodecV1.decodeRegistry(from: originalRegistryBytes)
            ),
            originalRegistryBytes
        )
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(
                try IlluminatedSignPlaybookCanonicalCodecV1.decodeCompletion(
                    from: originalCompletionBytes,
                    checkpoint: fixture.checkpoint,
                    payload: fixture.payload,
                    completeness: fixture.projection.completeness,
                    evidenceSequence: fixture.evidenceSequence,
                    registry: fixture.registry
                )
            ),
            originalCompletionBytes
        )
        XCTAssertEqual(
            try IlluminatedSignPlaybookCanonicalCodecV1.encode(
                try IlluminatedSignPlaybookCanonicalCodecV1.decodeReportSection(
                    from: originalSectionBytes,
                    completion: fixture.completion,
                    registry: fixture.registry
                )
            ),
            originalSectionBytes
        )
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.encode(
                try FieldDraftCanonicalCodecV1.decode(
                    FieldDraftCheckpointV1.self, from: originalCheckpointBytes
                )
            ),
            originalCheckpointBytes
        )
        XCTAssertEqual(
            try EvidenceMetadataCanonicalCodecV1.data(
                try EvidenceMetadataCanonicalCodecV1.decode(
                    EvidenceSequenceV1.self, from: originalSequenceBytes
                )
            ),
            originalSequenceBytes
        )
        XCTAssertEqual(
            try PlacementPoseCanonicalCodecV1.encode(
                try PlacementPoseCanonicalCodecV1.decode(
                    AssetPoseEventV1.self, from: originalPoseBytes
                )
            ),
            originalPoseBytes
        )
        XCTAssertEqual(fixture.registry.manifests.count, 7)
        XCTAssertEqual(
            fixture.registry.manifests.map(\.playbookID),
            IlluminatedSignPlaybookIDV1.canonicalOrder
        )
        XCTAssertEqual(
            IlluminatedSignPlaybookAccessibilityPolicyV1.semanticIDs.count,
            corpus.accessibility.semanticIDCount
        )
        XCTAssertTrue(corpus.accessibility.requiredAndOptionalCaptureAreTextuallyDistinct)
        XCTAssertTrue(corpus.accessibility.poseNeverUsesBareDirectionText)
        XCTAssertTrue(corpus.accessibility.factsAndDisclaimerAreSpoken)
        XCTAssertFalse(corpus.accessibility.uiConformanceClaimed)
        XCTAssertFalse(corpus.accessibility.uiAdoptionClaimed)
    }

    private func loadCorpus() throws -> C03IlluminatedSignPlaybookCorpusV1 {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V22/IlluminatedSignPlaybook/V22P04C03IlluminatedSignPlaybookCorpusV1.json"
        )
        return try JSONDecoder().decode(
            C03IlluminatedSignPlaybookCorpusV1.self,
            from: Data(contentsOf: url)
        )
    }

    private func assertCorpus(
        _ corpus: C03IlluminatedSignPlaybookCorpusV1,
        selector: String,
        tier: String
    ) {
        XCTAssertEqual(corpus.schema, "V22P04C03IlluminatedSignPlaybookCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P04-C03")
        XCTAssertEqual(corpus.ordinal, 91)
        XCTAssertEqual(corpus.contentMode, "CONTENT_ONLY")
        XCTAssertTrue(corpus.eighthPlaybookForbidden)
        XCTAssertFalse(corpus.uiAdoptionEnabled)
        XCTAssertFalse(corpus.professionalCertificationClaimed)
        XCTAssertTrue(corpus.professionalCertificationRejected)
        XCTAssertTrue(corpus.professionalCertificationBoundary.contains("professional certification"))
        XCTAssertFalse(corpus.optionalDecisionGateV1Present)
        XCTAssertFalse(corpus.optionalDecisionGateV1Enabled)
        XCTAssertTrue(corpus.optionalDecisionGateV1Forbidden)
        XCTAssertEqual(corpus.selectors.map(\.id), ["G01", "A01", "H01", "I01", "R01"])
        let row = corpus.selectors.first { $0.id == selector }
        XCTAssertEqual(row?.selector, "V23-P04-C03-\(selector)")
        XCTAssertEqual(row?.tier, tier)
    }
}
