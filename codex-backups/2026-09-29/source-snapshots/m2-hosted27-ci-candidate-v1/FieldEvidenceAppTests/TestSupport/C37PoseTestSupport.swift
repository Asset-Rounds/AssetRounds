import Foundation
import XCTest
@testable import FieldEvidenceApp

enum C37PoseTestSupport {
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

