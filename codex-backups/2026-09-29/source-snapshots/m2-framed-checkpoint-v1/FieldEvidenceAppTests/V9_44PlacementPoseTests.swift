import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_44PlacementPoseTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

final class C45PlacementPoseCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityUsesIntegralMicrometreTemplateGeometry() throws {
        let geometry = try AssetLabelGeometryV1(
            pageWidthMicrometres: 50_000, pageHeightMicrometres: 50_000,
            rows: 1, columns: 1, originXMicrometres: 1_000, originYMicrometres: 1_000,
            cellWidthMicrometres: 40_000, cellHeightMicrometres: 40_000,
            horizontalGapMicrometres: 0, verticalGapMicrometres: 0,
            quietZoneMicrometres: 2_000, textBoundMicrometres: 10_000
        )
        XCTAssertEqual(geometry.capacity, 1)
        XCTAssertEqual(geometry.originXMicrometres, 1_000)
    }
}

final class C30EvidenceContextAnchorV9_44PlacementPose: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}


@MainActor
final class V9_44PlacementPoseTests: XCTestCase {
    func testV23P03C37G01ReferenceFramedPoseHistoryAndQualifiedSnapshotAreDeterministic() throws {
        let workspace = C37PoseTestSupport.workspace()
        let assetID = C37PoseTestSupport.id(40_001)
        let forward = try C37PoseTestSupport.descriptor("forward")
        let face = try C37PoseTestSupport.descriptor(
            "face",
            required: .azimuthOnly,
            observationRequirement: .optional
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [face, forward])
        XCTAssertEqual(registry.descriptors, [forward, face].sorted())
        XCTAssertEqual(try registry.descriptor(for: forward.axisID), forward)

        let supportedAngles: [Int32] = [0, 1, 90_000, 180_000, 359_999]
        XCTAssertEqual(
            try supportedAngles.map {
                try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: $0).milliDegrees
            },
            supportedAngles
        )
        let pose = try C37PoseTestSupport.observedPose(
            descriptor: forward,
            azimuthMilliDegrees: 359_999,
            referenceFrame: .planRelative(C37PoseTestSupport.planFrame())
        )
        try pose.validate(descriptor: forward)
        XCTAssertEqual(pose.elevation?.milliDegrees, 90_000)

        let root = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: forward,
            eventID: C37PoseTestSupport.id(40_010),
            pose: pose
        )
        let history = try AssetPoseHistoryV1.currentTip(
            workspaceID: workspace,
            assetID: assetID,
            events: [root]
        )
        XCTAssertEqual(history.tips, [root.reference])
        let snapshot = try CompletedPlacementPoseSnapshotV1(
            snapshotID: C37PoseTestSupport.id(40_020),
            workspaceID: workspace,
            assetID: assetID,
            placementEpisodeID: root.placementEpisodeID,
            events: [root],
            capturedAt: root.recordedAt
        )
        XCTAssertEqual(
            try PlacementPoseCanonicalCodecV1.decode(
                CompletedPlacementPoseSnapshotV1.self,
                from: PlacementPoseCanonicalCodecV1.encode(snapshot)
            ),
            snapshot
        )
        let editor = try PlacementPoseEditorContractV1(
            workspaceID: workspace,
            assetID: assetID,
            placementEpisodeID: root.placementEpisodeID,
            descriptors: [forward, face],
            inputMode: .manual
        )
        XCTAssertFalse(editor.allowsNetworkInput)
        let proposal = try DeviceHeadingProposalV1(
            workspaceID: workspace,
            assetID: assetID,
            axisID: forward.axisID,
            proposedAzimuth: try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: 1),
            referenceFrame: .trueBearing,
            accuracyMilliDegrees: 1,
            availability: .available,
            capturedAt: C37PoseTestSupport.fixedDate,
            expiresAt: C37PoseTestSupport.fixedDate.addingTimeInterval(60)
        )
        try proposal.validateFresh(at: C37PoseTestSupport.fixedDate.addingTimeInterval(1))
        XCTAssertTrue(proposal.requiresManualAcceptance)
        let editorState = try PlacementPoseEditorStateV1(
            contract: editor,
            valuesByAxis: [forward.axisID: pose],
            pendingDeviceProposal: proposal,
            isDirty: true
        )
        XCTAssertTrue(editorState.isDirty)
        XCTAssertEqual(
            PlacementPoseEditorCommandV1.acceptDeviceProposal(proposal),
            PlacementPoseEditorCommandV1.acceptDeviceProposal(proposal)
        )
        XCTAssertEqual(
            PlacementPoseEditorCommandV1.discardDeviceProposal,
            PlacementPoseEditorCommandV1.discardDeviceProposal
        )

        let admission = try C37PoseTestSupport.admissionFixture()
        XCTAssertEqual(
            admission.packageRelease.packageReleaseID,
            admission.registryRelease.packageReleaseID
        )
        XCTAssertEqual(admission.registryRelease.registry.descriptors, [admission.descriptor])
        XCTAssertEqual(admission.planRevision.pages.map(\.pageID), [admission.page.pageID])
        XCTAssertEqual(
            admission.planRevision.spatialFrames.map(\.frameID),
            [admission.frame.frameID]
        )
        XCTAssertEqual(admission.placement.pathSnapshot, admission.event.locationPathSnapshot)
        XCTAssertEqual(admission.placement.physicalEpisodeID, admission.event.placementEpisodeID)
        try admission.closure.validate(
            events: [admission.event],
            observations: [admission.observation]
        )
    }

    func testV23P03C37A01ManualNotObservedAndNoPlanFallbackRemainComplete() throws {
        let workspace = C37PoseTestSupport.workspace()
        let assetID = C37PoseTestSupport.id(41_001)
        let descriptor = try C37PoseTestSupport.descriptor("fallback", required: .azimuthOnly)
        let fallback = try C37PoseTestSupport.notObservedPose(
            descriptor: descriptor,
            reason: .sourceUnavailable
        )
        XCTAssertEqual(fallback.disposition, .notObserved)
        XCTAssertEqual(fallback.referenceFrame, .unknown)
        XCTAssertNil(fallback.azimuth)
        XCTAssertNil(fallback.horizontalUncertainty)
        let editor = try PlacementPoseEditorContractV1(
            workspaceID: workspace,
            assetID: assetID,
            placementEpisodeID: try C37PoseTestSupport.episode(41),
            descriptors: [descriptor],
            inputMode: .offlineFallback
        )
        XCTAssertEqual(editor.inputMode, .offlineFallback)
        XCTAssertFalse(editor.allowsSensorInput)
        XCTAssertFalse(editor.allowsNetworkInput)
        let event = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(41_010),
            pose: fallback
        )
        try event.validateIntrinsic()
        XCTAssertEqual(event.source, .manual)
        XCTAssertEqual(event.rootObservationEventID, event.eventID)
    }

    func testV23P03C37AssetPlacementChangeReceiptV1RejectsMismatchedPoseCommandBodySHA256() throws {
        let admission = try C37PoseTestSupport.admissionFixture()
        let newPlacementID = C37PoseTestSupport.id(45_200)
        let newEpisode = try C37PoseTestSupport.episode(45)
        let mutationID = try C37PoseTestSupport.mutation(45_201)
        let proposedPose = try C37PoseTestSupport.notObservedPose(
            descriptor: admission.descriptor,
            reason: .physicalMoveReobservationRequired
        )
        let firstPoseEvent = try C37PoseTestSupport.poseEvent(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            descriptor: admission.descriptor,
            eventID: C37PoseTestSupport.id(45_202),
            pose: proposedPose,
            predecessor: admission.event,
            placementEventID: newPlacementID,
            placementEpisodeID: newEpisode,
            mutationID: mutationID
        )
        let secondPoseEvent = try C37PoseTestSupport.poseEvent(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            descriptor: admission.descriptor,
            eventID: C37PoseTestSupport.id(45_203),
            pose: proposedPose,
            predecessor: admission.event,
            placementEventID: newPlacementID,
            placementEpisodeID: newEpisode,
            mutationID: mutationID
        )
        let newPlacement = try C37PoseTestSupport.placement(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            placementID: newPlacementID,
            episode: newEpisode,
            path: admission.placement.pathSnapshot,
            mutationSlot: 45_201
        )
        let closure = try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [],
            placementEvents: [newPlacement]
        )
        let intent = try PosePlacementDispositionIntentV1(
            predecessor: admission.event.reference,
            proposedPose: proposedPose,
            disposition: .markNotObserved
        )
        let contribution = try PlacementChangeComponentContributionV1(
            componentID: "c37.pose.receipt.binding",
            componentVersion: 1,
            warnings: [],
            requiredContinuityReview: false,
            intentSHA256: intent.intentSHA256,
            poseDispositionIntents: [intent]
        )
        let expectedRevision = WorkspaceExpectedRevisionV1(snapshot: try WorkspaceRevisionV1(
            workspaceID: admission.workspaceID,
            generationID: C37PoseTestSupport.id(45_204),
            revision: 1,
            entityRevisions: []
        ))
        let basis = try AssetPlacementPreviewBasisV1(
            workspaceID: admission.workspaceID,
            expectedRevision: expectedRevision,
            assetID: admission.assetID,
            currentPlacement: admission.placement,
            proposedSiteID: admission.placement.siteID,
            proposedLocationNodeID: admission.placement.locationNodeID,
            proposedPath: admission.placement.pathSnapshot,
            source: .manual,
            reviewedContinuity: .physicalMove
        )
        func plan(_ event: AssetPoseEventV1) throws -> AssetPlacementChangePlanV1 {
            try AssetPlacementChangePlanV1(
                operationID: mutationID.rawValue,
                mutationID: mutationID,
                basis: basis,
                newEventID: newPlacementID,
                resultingPhysicalEpisodeID: newEpisode,
                componentContributions: [contribution],
                poseEvents: [event],
                poseEventPredecessors: [admission.event],
                poseAdmissionClosure: closure
            )
        }
        let firstPlan = try plan(firstPoseEvent)
        let secondPlan = try plan(secondPoseEvent)
        XCTAssertEqual(firstPlan.planSHA256, secondPlan.planSHA256)
        XCTAssertNotEqual(firstPlan.posePostImageSHA256, secondPlan.posePostImageSHA256)
        let firstCommandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAssetPlacementChange(firstPlan)
        )
        let secondCommandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAssetPlacementChange(secondPlan)
        )
        XCTAssertNotEqual(firstCommandBodySHA256, secondCommandBodySHA256)
    }

    func testV23P03C37H01InvalidFramesAnglesTransformsForksAndClaimsFailClosed() throws {
        let workspace = C37PoseTestSupport.workspace()
        let assetID = C37PoseTestSupport.id(42_001)
        let descriptor = try C37PoseTestSupport.descriptor("hostile", required: .azimuthOnly)
        XCTAssertThrowsError(try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: 360_000))
        XCTAssertThrowsError(try PoseAngleMilliDegreesV1(kind: .elevation, milliDegrees: 90_001))
        XCTAssertThrowsError(try PoseAngleMilliDegreesV1(kind: .horizontalUncertainty, milliDegrees: 180_001))
        XCTAssertThrowsError(try PoseAngleMilliDegreesV1(kind: .verticalUncertainty, milliDegrees: 90_001))
        XCTAssertThrowsError(try PoseAngleMilliDegreesV1(kind: .elevation, milliDegrees: Int32.max))
        XCTAssertThrowsError(try PlacementPoseCanonicalCodecV1.decode(
            PoseAngleMilliDegreesV1.self,
            from: Data(#"{"kind":"AZIMUTH","milliDegrees":1.5}"#.utf8)
        ))
        XCTAssertThrowsError(try PlacementPoseCanonicalCodecV1.decode(
            PoseAngleMilliDegreesV1.self,
            from: Data(#"{"kind":"AZIMUTH","milliDegrees":NaN}"#.utf8)
        ))
        XCTAssertThrowsError(try PoseAxisDescriptorRegistryV1(descriptors: [
            descriptor,
            descriptor
        ]))
        let notApplicable = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.not-applicable"),
            localizedLabelKey: "pose.not-applicable",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .notApplicable
        )
        XCTAssertThrowsError(try PlacementPoseV1(
            disposition: .observed,
            referenceFrame: .trueBearing,
            azimuth: try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: 0),
            horizontalUncertainty: .known(try PoseAngleMilliDegreesV1(kind: .horizontalUncertainty, milliDegrees: 1)),
            descriptor: notApplicable
        ))

        XCTAssertThrowsError(try PlanAffineTransformV1(
            m11: -PlanLimitsV1.transformScale,
            m12: 0,
            m21: 0,
            m22: PlanLimitsV1.transformScale,
            tx: 0,
            ty: 0
        ))
        XCTAssertThrowsError(try PlanAffineTransformV1(
            m11: 0,
            m12: 0,
            m21: 0,
            m22: 0,
            tx: 0,
            ty: 0
        ))
        XCTAssertThrowsError(try PoseFrameRebasePolicyV1(minimumSingularValueScaled: 0))

        let root = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(42_010),
            pose: try C37PoseTestSupport.observedPose(descriptor: descriptor, azimuthMilliDegrees: 0)
        )
        let successor = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(42_011),
            pose: try C37PoseTestSupport.notObservedPose(
                descriptor: descriptor,
                reason: .physicalMoveReobservationRequired
            ),
            predecessor: root
        )
        let fork = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(42_012),
            pose: try C37PoseTestSupport.notObservedPose(
                descriptor: descriptor,
                reason: .physicalMoveReobservationRequired
            ),
            predecessor: root
        )
        XCTAssertThrowsError(try AssetPoseHistoryV1.currentTip(
            workspaceID: workspace,
            assetID: assetID,
            events: [root, successor, fork]
        ))
        XCTAssertThrowsError(try AssetPoseHistoryV1.currentTip(
            workspaceID: workspace,
            assetID: assetID,
            events: [root, root]
        ))

        let admission = try C37PoseTestSupport.admissionFixture()
        let missingAuthorities = try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [],
            placementEvents: []
        )
        XCTAssertThrowsError(try missingAuthorities.validate(
            events: [admission.event],
            observations: [admission.observation]
        ))

        let extraPlacement = try C37PoseTestSupport.placement(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            placementID: C37PoseTestSupport.id(45_006),
            episode: admission.placement.physicalEpisodeID,
            path: admission.placement.pathSnapshot,
            mutationSlot: 45_007
        )
        let extraPlacementClosure = try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [admission.planRevision],
            placementEvents: [admission.placement, extraPlacement]
        )
        XCTAssertThrowsError(try extraPlacementClosure.validate(
            events: [admission.event],
            observations: [admission.observation]
        ))

        let extraRevision = try PlanRevisionV1(
            planRevisionID: C37PoseTestSupport.id(45_140),
            workspaceID: admission.workspaceID,
            planDocument: admission.planRevision.planDocument,
            contentBinding: admission.planRevision.contentBinding,
            pages: admission.planRevision.pages,
            spatialFrames: admission.planRevision.spatialFrames,
            state: .released,
            predecessor: admission.planRevision,
            revision: 2,
            mutationID: try C37PoseTestSupport.mutation(45_141),
            recordedBy: try C37PoseTestSupport.actor(
                workspaceID: admission.workspaceID,
                slot: 45_142,
                responsibility: .recordedBy
            ),
            recordedAt: C37PoseTestSupport.fixedDate.addingTimeInterval(2)
        )
        try extraRevision.validateSuccessor(of: admission.planRevision)
        let extraRevisionClosure = try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [admission.planRevision, extraRevision],
            placementEvents: [admission.placement]
        )
        XCTAssertThrowsError(try extraRevisionClosure.validate(
            events: [admission.event],
            observations: [admission.observation]
        ))

        XCTAssertThrowsError(try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [admission.planRevision],
            placementEvents: [admission.placement, admission.placement]
        ))

        let foreignPlacement = try C37PoseTestSupport.placement(
            workspaceID: C37PoseTestSupport.workspace(99),
            assetID: admission.assetID,
            placementID: C37PoseTestSupport.id(45_008),
            episode: admission.placement.physicalEpisodeID,
            path: admission.placement.pathSnapshot,
            mutationSlot: 45_009
        )
        XCTAssertThrowsError(try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [admission.planRevision],
            placementEvents: [foreignPlacement]
        ))

        let (foreignRevision, _, _) = try C37PoseTestSupport.planRevision(
            workspaceID: C37PoseTestSupport.workspace(99)
        )
        XCTAssertThrowsError(try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [foreignRevision],
            placementEvents: [admission.placement]
        ))

        let foreignPackage = try C37PoseTestSupport.packageRelease(
            workflowID: "c37.foreign.workflow"
        )
        XCTAssertThrowsError(try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: foreignPackage,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [admission.planRevision],
            placementEvents: [admission.placement]
        ))

        let planReference = try admission.planRevision.reference
        let wrongRevisionFrame = PlanRelativePoseFrameBindingV1(
            planRevision: PlanRevisionReferenceV1(
                planRevisionID: planReference.planRevisionID,
                planDocumentID: planReference.planDocumentID,
                revision: planReference.revision + 1,
                revisionSHA256: C37PoseTestSupport.digest("a")
            ),
            pageID: admission.page.pageID,
            spatialFrameID: admission.frame.frameID,
            acceptedTransformSHA256: C37PoseTestSupport.digest("f")
        )
        let wrongRevisionEvent = try C37PoseTestSupport.poseEvent(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            descriptor: admission.descriptor,
            eventID: C37PoseTestSupport.id(45_010),
            pose: try C37PoseTestSupport.observedPose(
                descriptor: admission.descriptor,
                azimuthMilliDegrees: 90_000,
                referenceFrame: .planRelative(wrongRevisionFrame)
            ),
            placementEventID: admission.placement.id,
            placementEpisodeID: admission.placement.physicalEpisodeID
        )
        XCTAssertThrowsError(try admission.closure.validate(
            events: [wrongRevisionEvent],
            observations: []
        ))

        let wrongPageFrame = PlanRelativePoseFrameBindingV1(
            planRevision: planReference,
            pageID: C37PoseTestSupport.id(45_011),
            spatialFrameID: admission.frame.frameID,
            acceptedTransformSHA256: C37PoseTestSupport.digest("f")
        )
        let wrongPageEvent = try C37PoseTestSupport.poseEvent(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            descriptor: admission.descriptor,
            eventID: C37PoseTestSupport.id(45_012),
            pose: try C37PoseTestSupport.observedPose(
                descriptor: admission.descriptor,
                referenceFrame: .planRelative(wrongPageFrame)
            ),
            placementEventID: admission.placement.id,
            placementEpisodeID: admission.placement.physicalEpisodeID
        )
        XCTAssertThrowsError(try admission.closure.validate(
            events: [wrongPageEvent],
            observations: []
        ))

        let wrongFrame = PlanRelativePoseFrameBindingV1(
            planRevision: planReference,
            pageID: admission.page.pageID,
            spatialFrameID: C37PoseTestSupport.id(45_013),
            acceptedTransformSHA256: C37PoseTestSupport.digest("f")
        )
        let wrongFrameEvent = try C37PoseTestSupport.poseEvent(
            workspaceID: admission.workspaceID,
            assetID: admission.assetID,
            descriptor: admission.descriptor,
            eventID: C37PoseTestSupport.id(45_014),
            pose: try C37PoseTestSupport.observedPose(
                descriptor: admission.descriptor,
                referenceFrame: .planRelative(wrongFrame)
            ),
            placementEventID: admission.placement.id,
            placementEpisodeID: admission.placement.physicalEpisodeID
        )
        XCTAssertThrowsError(try admission.closure.validate(
            events: [wrongFrameEvent],
            observations: []
        ))

        let forgedDescriptor = try PoseAxisDescriptorV1(
            axisID: admission.descriptor.axisID,
            localizedLabelKey: "pose.forged",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .requiredForCompletion,
            applicability: .applicable
        )
        let forgedRegistry = try PoseAxisDescriptorRegistryV1(descriptors: [forgedDescriptor])
        let forgedRegistryRelease = try PoseAxisRegistryReleaseV1(
            packageRelease: admission.packageRelease,
            registry: forgedRegistry
        )
        let forgedDescriptorClosure = try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: forgedRegistryRelease,
            planRevisions: [admission.planRevision],
            placementEvents: [admission.placement]
        )
        XCTAssertThrowsError(try forgedDescriptorClosure.validate(
            events: [admission.event],
            observations: []
        ))

        let bypassClosure = try PlacementPoseAdmissionClosureV1(
            workspaceID: admission.workspaceID,
            packageRelease: admission.packageRelease,
            axisRegistryRelease: admission.registryRelease,
            planRevisions: [],
            placementEvents: []
        )
        XCTAssertThrowsError(try PlacementPoseMutationV1(
            workspaceID: admission.workspaceID,
            mutationID: admission.event.mutationID,
            events: [admission.event],
            eventPredecessors: [nil],
            admissionClosure: bypassClosure
        ))

        let component = try PoseFrameRebaseComponentV1(
            policy: PoseFrameRebasePolicyV1(),
            currentPoseEvents: { _, _ in [] }
        )
        let shear = try PlanAffineTransformV1(
            m11: PlanLimitsV1.transformScale,
            m12: PlanLimitsV1.transformScale / 10,
            m21: 0,
            m22: PlanLimitsV1.transformScale,
            tx: 0,
            ty: 0
        )
        let nonUniform = try PlanAffineTransformV1(
            m11: PlanLimitsV1.transformScale * 2 / 3,
            m12: 0,
            m21: 0,
            m22: PlanLimitsV1.transformScale * 3 / 2,
            tx: 0,
            ty: 0
        )
        let azimuth = try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: 0)
        XCTAssertNil(try component.transformedAzimuth(azimuth, by: shear))
        XCTAssertNil(try component.transformedAzimuth(azimuth, by: nonUniform))
    }

    func testV23P03C37I01InterruptedMoveRebaseAndPromotionExposeOldOrOneSealedSuccessor() throws {
        let workspace = C37PoseTestSupport.workspace()
        let assetID = C37PoseTestSupport.id(43_001)
        let descriptor = try C37PoseTestSupport.descriptor("move", required: .azimuthOnly)
        let root = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(43_010),
            pose: try C37PoseTestSupport.observedPose(descriptor: descriptor, azimuthMilliDegrees: 90_000)
        )
        let moved = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(43_011),
            pose: try C37PoseTestSupport.notObservedPose(
                descriptor: descriptor,
                reason: .physicalMoveReobservationRequired
            ),
            predecessor: root
        )
        XCTAssertEqual(moved.source, .placementCarryForward)
        XCTAssertEqual(moved.predecessor?.eventID, root.eventID)
        XCTAssertEqual(moved.rootObservationEventID, root.rootObservationEventID)
        let tip = try AssetPoseHistoryV1.currentTip(
            workspaceID: workspace,
            assetID: assetID,
            events: [moved, root]
        )
        XCTAssertEqual(tip.tips, [moved.reference])

        let anchor = try C37PoseTestSupport.anchor(
            workspaceID: workspace,
            assetID: assetID,
            observationID: C37PoseTestSupport.id(43_020),
            frame: C37PoseTestSupport.planFrame()
        )
        let reobserved = try C37PoseTestSupport.anchor(
            workspaceID: workspace,
            assetID: assetID,
            observationID: C37PoseTestSupport.id(43_021),
            frame: C37PoseTestSupport.planFrame(),
            predecessor: anchor,
            disposition: .notObserved
        )
        XCTAssertEqual(reobserved.predecessorObservationID, anchor.observationID)
        XCTAssertEqual(reobserved.predecessorSHA256, anchor.observationSHA256)
        XCTAssertThrowsError(try SpatialAnchorObservationV1(
            observationID: C37PoseTestSupport.id(43_022),
            workspaceID: workspace,
            assetID: assetID,
            placementEpisodeID: try C37PoseTestSupport.episode(),
            planFrame: C37PoseTestSupport.planFrame(),
            x: nil,
            y: nil,
            disposition: .notObserved,
            reason: .planFrameLostReobservationRequired,
            predecessor: anchor,
            revision: reobserved.revision,
            mutationID: anchor.mutationID,
            observedBy: try C37PoseTestSupport.actor(workspaceID: workspace, slot: 43_022),
            observedAt: reobserved.observedAt
        ))
        let transformed = try PoseFrameRebaseComponentV1(
            policy: PoseFrameRebasePolicyV1(),
            currentPoseEvents: { _, _ in [root] }
        )
        let transform = try PlanAffineTransformV1(
            m11: PlanLimitsV1.transformScale,
            m12: 0,
            m21: 0,
            m22: PlanLimitsV1.transformScale,
            tx: 0,
            ty: 0
        )
        XCTAssertEqual(
            try transformed.transformedAzimuth(root.pose.azimuth, by: transform),
            90_000
        )
        XCTAssertEqual(root.eventID, C37PoseTestSupport.id(43_010))
    }

    func testV23P03C37R01RestoreReplayRebuildAndHistoricArtifactsPreserveExactPoseTruth() throws {
        let workspace = C37PoseTestSupport.workspace()
        let cloneWorkspace = C37PoseTestSupport.workspace(2)
        let assetID = C37PoseTestSupport.id(44_001)
        let descriptor = try C37PoseTestSupport.descriptor("restore", required: .azimuthOnly)
        let event = try C37PoseTestSupport.poseEvent(
            workspaceID: workspace,
            assetID: assetID,
            descriptor: descriptor,
            eventID: C37PoseTestSupport.id(44_010),
            pose: try C37PoseTestSupport.observedPose(descriptor: descriptor, azimuthMilliDegrees: 180_000)
        )
        let anchor = try C37PoseTestSupport.anchor(
            workspaceID: workspace,
            assetID: assetID,
            observationID: C37PoseTestSupport.id(44_020),
            frame: C37PoseTestSupport.planFrame()
        )
        let eventRow = try AssetPoseEventRow(event)
        let anchorRow = try SpatialAnchorObservationRow(anchor)
        XCTAssertEqual(try eventRow.value(), event)
        XCTAssertEqual(try anchorRow.value(), anchor)
        XCTAssertEqual(try AssetPoseHistoryV1.currentTip(
            workspaceID: workspace,
            assetID: assetID,
            events: [event]
        ).projectionSHA256, try WorkspaceMutationCanonicalV1.sha256([event.reference]))

        let snapshot = try CompletedPlacementPoseSnapshotV1(
            snapshotID: C37PoseTestSupport.id(44_030),
            workspaceID: workspace,
            assetID: assetID,
            placementEpisodeID: event.placementEpisodeID,
            events: [event],
            capturedAt: event.recordedAt
        )
        let restored = try PlacementPoseCanonicalCodecV1.decode(
            CompletedPlacementPoseSnapshotV1.self,
            from: PlacementPoseCanonicalCodecV1.encode(snapshot)
        )
        XCTAssertEqual(restored.snapshotSHA256, snapshot.snapshotSHA256)
        XCTAssertEqual(restored.eventReferences, [event.reference])

        let reboundActor = try C37PoseTestSupport.actor(
            workspaceID: cloneWorkspace,
            slot: 44_040,
            responsibility: .observedBy
        )
        let clone = try event.rebound(to: cloneWorkspace, recordedBy: reboundActor)
        XCTAssertEqual(clone.revision, 1)
        XCTAssertNil(clone.predecessor)
        XCTAssertNotEqual(clone.workspaceID, event.workspaceID)
        XCTAssertNotEqual(clone.eventSHA256, event.eventSHA256)
        XCTAssertEqual(event.revision, 1)
        XCTAssertEqual(event.pose.azimuth?.milliDegrees, 180_000)
        XCTAssertFalse(try PlacementPoseEditorContractV1(
            workspaceID: workspace,
            assetID: assetID,
            placementEpisodeID: event.placementEpisodeID,
            descriptors: [descriptor],
            inputMode: .offlineFallback
        ).allowsNetworkInput)
    }
}
final class C31LightingAnchorV944PlacementPoseTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class C33TemporalEvidenceAnchorV944PlacementPose: XCTestCase {
    func testC33V944PlacementPoseCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "pose.temporal-anchor-context",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "pose.temporal-anchor-context",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

final class C32AssistanceAnchorV944PlacementPose: XCTestCase {
    func testC32V944PlacementPoseCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .assetPoseEvent,
            fieldID: "pose.no-auto-promotion",
            value: .text("one-shot location proposal only")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .assetPoseEvent,
            fieldID: "pose.no-auto-promotion",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
final class C46V944PoseCompatibilityTests: XCTestCase {
    func testC46PlacementPoseCannotSupplyCurrentDirectionsCoordinate() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "placement-pose",
            kind: .phone,
            handoff: .directions,
            slot: 46044
        )
    }
}
