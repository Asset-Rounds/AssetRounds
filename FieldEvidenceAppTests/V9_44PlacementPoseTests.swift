import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C37PoseTestSupport {
    static let fixedDate = Date(timeIntervalSinceReferenceDate: 1_900_000_000)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func workspace(_ value: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(10_000 + value))
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(20_000 + value))
    }

    static func stableSlot(for value: UUID) -> Int {
        let hex = value.uuidString.replacingOccurrences(of: "-", with: "").suffix(8)
        return (Int(String(hex), radix: 16) ?? 1) % 20_000 + 1
    }

    static func digest(_ character: Character = "a") -> String {
        String(repeating: String(character), count: 64)
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int,
        responsibility: ResponsibilityKindV1 = .observedBy
    ) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(30_000 + slot),
            workspaceID: workspaceID,
            displayName: "C37 local observer"
        )
        return try ActorSnapshotV1(
            snapshotID: id(31_000 + slot),
            workspaceID: workspaceID,
            actor: local,
            responsibility: responsibility,
            displayNameAtTime: local.displayName,
            capturedAt: fixedDate
        )
    }

    static func episode(_ slot: Int = 1) throws -> PhysicalPlacementEpisodeIDV1 {
        try PhysicalPlacementEpisodeIDV1(rawValue: id(32_000 + slot))
    }

    static func locationPathSnapshot() throws -> LocationPathSnapshotV1 {
        try LocationPathSnapshotV1(
            siteID: id(34_100),
            siteDisplay: "C37 site",
            nodes: []
        )
    }

    struct AdmissionFixture {
        let workspaceID: WorkspaceID
        let assetID: UUID
        let packageRelease: InspectionPackageReleaseV1
        let descriptor: PoseAxisDescriptorV1
        let registryRelease: PoseAxisRegistryReleaseV1
        let planRevision: PlanRevisionV1
        let page: PlanPageReferenceV1
        let frame: SpatialReferenceFrameV1
        let poseFrame: PlanRelativePoseFrameBindingV1
        let placement: AssetPlacementEventV1
        let event: AssetPoseEventV1
        let observation: SpatialAnchorObservationV1
        let closure: PlacementPoseAdmissionClosureV1
    }

    static func packageRelease(workflowID: String = "c37.pose.workflow") throws -> InspectionPackageReleaseV1 {
        let workflow = try WorkflowDefinitionV1(
            workflowID: workflowID,
            entryNodeID: "start",
            declaredFieldIDs: [],
            nodes: [
                try .init(
                    nodeID: "start",
                    kind: .section,
                    localizationKey: "c37.pose.start",
                    outgoingNodeIDs: ["end"]
                ),
                try .init(
                    nodeID: "end",
                    kind: .terminal,
                    localizationKey: "c37.pose.end",
                    outgoingNodeIDs: []
                )
            ]
        )
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: workflow
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        return try InspectionPackageReleasePublisherV1.publish(tested).release
    }

    static func planContentAndRelease(
        workspaceID: WorkspaceID
    ) throws -> (ContentReferenceV1, ContentLocatorV1, FieldReferenceReleaseV1) {
        let contentDigest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: digest("d")
        )
        let entry = try ContentManifestEntryV1(
            contentID: "c37-pose-plan",
            expectedByteLength: 4,
            mediaType: "application/pdf",
            digest: contentDigest,
            expectedLocatorRevision: 1,
            requiredForOpen: true
        )
        let manifest = try ContentManifestV1(
            manifestID: "c37-pose-manifest",
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            manifestRevision: 1,
            entries: [entry]
        )
        let content = try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: entry.contentID,
            byteLength: entry.expectedByteLength,
            mediaType: entry.mediaType,
            digests: try ContentDigestSetV1([contentDigest]),
            byteRole: .immutableOriginal,
            createdAt: "2026-08-29T00:00:00.000Z"
        )
        let locator = try ContentLocatorV1(
            locatorID: "c37-pose-locator",
            workspaceID: content.workspaceID,
            contentID: content.contentID,
            locatorRevision: 1,
            contentDigest: contentDigest,
            expectedByteLength: content.byteLength
        )
        let provenance = try FieldReferenceProvenanceV1(
            kind: .synthetic,
            sourceName: "C37 local fixture",
            sourceReleaseIdentifier: "c37-pose-fixture-1",
            licenseScope: .localUseOnly
        )
        let release = try FieldReferenceReleaseV1(
            releaseID: id(45_120),
            workspaceID: workspaceID,
            referencePackID: "c37-pose-reference-pack",
            kind: .drawing,
            semanticVersion: "1.0.0",
            provenance: provenance,
            manifest: manifest,
            issuedAt: fixedDate,
            revision: 1,
            mutationID: try mutation(45_121)
        )
        return (content, locator, release)
    }

    static func planRevision(
        workspaceID: WorkspaceID
    ) throws -> (PlanRevisionV1, PlanPageReferenceV1, SpatialReferenceFrameV1) {
        let (content, locator, referenceRelease) = try planContentAndRelease(workspaceID: workspaceID)
        let binding = try PlanContentBindingV1(
            content: content,
            locator: locator,
            fieldReferenceRelease: referenceRelease
        )
        let document = try PlanDocumentV1(
            planDocumentID: id(45_130),
            workspaceID: workspaceID,
            stablePlanKey: "c37-pose-plan",
            displayName: "C37 pose plan",
            revision: 1,
            mutationID: try mutation(45_131),
            recordedAt: fixedDate
        )
        let crop = try PlanCropRectV1(
            minX: try NormalizedPlanCoordinateV1(millionths: 0),
            minY: try NormalizedPlanCoordinateV1(millionths: 0),
            maxX: try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale),
            maxY: try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        )
        let page = try PlanPageReferenceV1(
            pageID: id(45_132),
            sourcePageOrdinal: 0,
            presentedPageOrdinal: 0,
            pixelWidth: 2_000,
            pixelHeight: 1_000,
            crop: crop,
            rotation: .degrees0,
            sourcePageSHA256: digest("e")
        )
        let frame = try SpatialReferenceFrameV1(frameID: id(45_133), pageID: page.pageID)
        let revision = try PlanRevisionV1(
            planRevisionID: id(45_134),
            workspaceID: workspaceID,
            planDocument: try document.reference,
            contentBinding: binding,
            pages: [page],
            spatialFrames: [frame],
            state: .released,
            revision: 1,
            mutationID: try mutation(45_135),
            recordedBy: try actor(workspaceID: workspaceID, slot: 45_136, responsibility: .recordedBy),
            recordedAt: fixedDate
        )
        return (revision, page, frame)
    }

    static func placement(
        workspaceID: WorkspaceID,
        assetID: UUID,
        placementID: UUID,
        episode: PhysicalPlacementEpisodeIDV1,
        path: LocationPathSnapshotV1,
        mutationSlot: Int
    ) throws -> AssetPlacementEventV1 {
        try AssetPlacementEventV1(
            id: placementID,
            workspaceID: workspaceID,
            assetID: assetID,
            siteID: path.siteID,
            locationNodeID: nil,
            predecessorEventID: nil,
            source: .manual,
            physicalEpisodeID: episode,
            continuity: .samePhysicalInstallation,
            pathSnapshot: path,
            mutationID: try mutation(mutationSlot),
            occurredAt: fixedDate
        )
    }

    static func admissionFixture() throws -> AdmissionFixture {
        let workspaceID = workspace(3)
        let assetID = id(45_001)
        let packageRelease = try packageRelease()
        let descriptor = try descriptor("admission", required: .azimuthOnly)
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [descriptor])
        let registryRelease = try PoseAxisRegistryReleaseV1(
            packageRelease: packageRelease,
            registry: registry
        )
        let (planRevision, page, frame) = try planRevision(workspaceID: workspaceID)
        let poseFrame = PlanRelativePoseFrameBindingV1(
            planRevision: try planRevision.reference,
            pageID: page.pageID,
            spatialFrameID: frame.frameID,
            acceptedTransformSHA256: digest("f")
        )
        let path = try locationPathSnapshot()
        let episode = try C37PoseTestSupport.episode(3)
        let placement = try placement(
            workspaceID: workspaceID,
            assetID: assetID,
            placementID: id(45_002),
            episode: episode,
            path: path,
            mutationSlot: 45_003
        )
        let event = try poseEvent(
            workspaceID: workspaceID,
            assetID: assetID,
            descriptor: descriptor,
            eventID: id(45_004),
            pose: try observedPose(
                descriptor: descriptor,
                azimuthMilliDegrees: 90_000,
                referenceFrame: .planRelative(poseFrame)
            ),
            placementEventID: placement.id,
            placementEpisodeID: episode
        )
        let observation = try anchor(
            workspaceID: workspaceID,
            assetID: assetID,
            observationID: id(45_005),
            frame: poseFrame,
            placementEpisodeID: episode
        )
        let closure = try PlacementPoseAdmissionClosureV1(
            workspaceID: workspaceID,
            packageRelease: packageRelease,
            axisRegistryRelease: registryRelease,
            planRevisions: [planRevision],
            placementEvents: [placement]
        )
        return AdmissionFixture(
            workspaceID: workspaceID,
            assetID: assetID,
            packageRelease: packageRelease,
            descriptor: descriptor,
            registryRelease: registryRelease,
            planRevision: planRevision,
            page: page,
            frame: frame,
            poseFrame: poseFrame,
            placement: placement,
            event: event,
            observation: observation,
            closure: closure
        )
    }

    static func descriptor(
        _ axis: String,
        required: PoseRequiredComponentsV1 = .azimuthAndElevation,
        observationRequirement: PoseObservationRequirementV1 = .requiredForCompletion,
        applicability: PoseAxisApplicabilityV1 = .applicable
    ) throws -> PoseAxisDescriptorV1 {
        try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.\(axis)"),
            localizedLabelKey: "pose.\(axis)",
            semanticRole: .assetForwardAxis,
            requiredComponents: required,
            observationRequirement: observationRequirement,
            applicability: applicability
        )
    }

    static func planFrame() -> PlanRelativePoseFrameBindingV1 {
        PlanRelativePoseFrameBindingV1(
            planRevision: PlanRevisionReferenceV1(
                planRevisionID: id(33_001),
                planDocumentID: id(33_002),
                revision: 1,
                revisionSHA256: digest("b")
            ),
            pageID: id(33_003),
            spatialFrameID: id(33_004),
            acceptedTransformSHA256: digest("c")
        )
    }

    static func observedPose(
        descriptor: PoseAxisDescriptorV1,
        azimuthMilliDegrees: Int32 = 0,
        referenceFrame: PoseReferenceFrameV1 = .trueBearing
    ) throws -> PlacementPoseV1 {
        let elevation: PoseAngleMilliDegreesV1?
        let verticalUncertainty: PoseUncertaintyV1?
        switch descriptor.requiredComponents {
        case .azimuthOnly:
            elevation = nil
            verticalUncertainty = nil
        case .azimuthAndElevation:
            elevation = try PoseAngleMilliDegreesV1(kind: .elevation, milliDegrees: 90_000)
            verticalUncertainty = .known(try PoseAngleMilliDegreesV1(kind: .verticalUncertainty, milliDegrees: 1))
        }
        return try PlacementPoseV1(
            disposition: .observed,
            referenceFrame: referenceFrame,
            azimuth: try PoseAngleMilliDegreesV1(kind: .azimuth, milliDegrees: azimuthMilliDegrees),
            elevation: elevation,
            horizontalUncertainty: .known(try PoseAngleMilliDegreesV1(kind: .horizontalUncertainty, milliDegrees: 1)),
            verticalUncertainty: verticalUncertainty,
            descriptor: descriptor
        )
    }

    static func notObservedPose(
        descriptor: PoseAxisDescriptorV1,
        reason: PoseNotObservedReasonV1 = .sourceUnavailable
    ) throws -> PlacementPoseV1 {
        try PlacementPoseV1(
            disposition: .notObserved,
            referenceFrame: .unknown,
            notObservedReason: reason,
            descriptor: descriptor
        )
    }

    static func poseEvent(
        workspaceID: WorkspaceID,
        assetID: UUID,
        descriptor: PoseAxisDescriptorV1,
        eventID: UUID,
        pose: PlacementPoseV1,
        predecessor: AssetPoseEventV1? = nil,
        placementEventID: UUID = id(34_001),
        placementEpisodeID: PhysicalPlacementEpisodeIDV1? = nil,
        mutationID: MutationIDV1? = nil
    ) throws -> AssetPoseEventV1 {
        let occurredAt = predecessor?.occurredAt.addingTimeInterval(1) ?? fixedDate
        let source: PoseObservationSourceV1 = predecessor == nil ? .manual : .placementCarryForward
        let responsibility: ResponsibilityKindV1 = predecessor == nil ? .observedBy : .recordedBy
        return try AssetPoseEventV1(
            eventID: eventID,
            workspaceID: workspaceID,
            assetID: assetID,
            axisDescriptor: descriptor,
            placementEpisodeID: placementEpisodeID ?? (try episode()),
            placementEventID: placementEventID,
            locationPathSnapshot: try locationPathSnapshot(),
            pose: pose,
            source: source,
            rootObservationEventID: predecessor?.rootObservationEventID ?? eventID,
            rootObservedAt: predecessor?.rootObservedAt ?? occurredAt,
            predecessor: predecessor,
            revision: predecessor.map { $0.revision + 1 } ?? 1,
            mutationID: try mutationID ?? mutation(stableSlot(for: eventID)),
            recordedBy: try actor(
                workspaceID: workspaceID,
                slot: stableSlot(for: eventID),
                responsibility: responsibility
            ),
            occurredAt: occurredAt,
            recordedAt: occurredAt.addingTimeInterval(1)
        )
    }

    static func anchor(
        workspaceID: WorkspaceID,
        assetID: UUID,
        observationID: UUID,
        frame: PlanRelativePoseFrameBindingV1,
        predecessor: SpatialAnchorObservationV1? = nil,
        disposition: SpatialAnchorObservationDispositionV1 = .observed,
        placementEpisodeID: PhysicalPlacementEpisodeIDV1? = nil
    ) throws -> SpatialAnchorObservationV1 {
        let observedAt = predecessor?.observedAt.addingTimeInterval(1) ?? fixedDate
        let observed = disposition == .observed
        return try SpatialAnchorObservationV1(
            observationID: observationID,
            workspaceID: workspaceID,
            assetID: assetID,
            placementEpisodeID: placementEpisodeID ?? (try episode()),
            planFrame: frame,
            x: observed ? try NormalizedPlanCoordinateV1(millionths: 125_000) : nil,
            y: observed ? try NormalizedPlanCoordinateV1(millionths: 250_000) : nil,
            disposition: disposition,
            reason: observed ? nil : .planFrameLostReobservationRequired,
            predecessor: predecessor,
            revision: predecessor.map { $0.revision + 1 } ?? 1,
            mutationID: try mutation(stableSlot(for: observationID)),
            observedBy: try actor(workspaceID: workspaceID, slot: stableSlot(for: observationID) + 1),
            observedAt: observedAt
        )
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
