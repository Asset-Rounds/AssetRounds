import Foundation

enum PlacementPoseFailureV1: Error, Equatable {
    case invalidIdentity
    case invalidValue
    case invalidDigest
    case incompatibleVersion
    case duplicateIdentity
    case unorderedValue
    case wrongWorkspace
    case referenceMismatch
    case predecessorMismatch
    case arithmeticOverflow
    case reviewRequired
}

enum PlacementPoseLimitsV1 {
    static let maximumAxesPerRelease = 8
    static let maximumEventsPerClosure = 100_000
    static let maximumTokenBytes = 128

    static func id(_ value: UUID) throws {
        guard value.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw PlacementPoseFailureV1.invalidIdentity
        }
    }
    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTokenBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw PlacementPoseFailureV1.invalidValue
        }
    }
    static func digest(_ value: String) throws {
        guard value.count == 64, value == value.lowercased(),
              value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }) else {
            throw PlacementPoseFailureV1.invalidDigest
        }
    }
}

struct PoseAxisID: Codable, Equatable, Hashable, Comparable, Sendable {
    let rawValue: String
    init(rawValue: String) throws { try PlacementPoseLimitsV1.token(rawValue); self.rawValue = rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum PoseAxisSemanticRoleV1: String, Codable, CaseIterable, Hashable, Sendable {
    case assetForwardAxis = "ASSET_FORWARD_AXIS"
    case signFaceNormal = "SIGN_FACE_NORMAL"
    case lightBeamCenterline = "LIGHT_BEAM_CENTERLINE"
    case otherDeclaredAxis = "OTHER_DECLARED_AXIS"
}

enum PoseRequiredComponentsV1: String, Codable, CaseIterable, Hashable, Sendable {
    case azimuthOnly = "AZIMUTH_ONLY"
    case azimuthAndElevation = "AZIMUTH_AND_ELEVATION"
}

enum PoseObservationRequirementV1: String, Codable, CaseIterable, Hashable, Sendable {
    case requiredForCompletion = "REQUIRED_FOR_COMPLETION"
    case optional = "OPTIONAL"
}

enum PoseAxisApplicabilityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case applicable = "APPLICABLE"
    case notApplicable = "NOT_APPLICABLE"
}

struct PoseAxisDescriptorV1: Codable, Equatable, Hashable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let axisID: PoseAxisID
    let localizedLabelKey: String
    let semanticRole: PoseAxisSemanticRoleV1
    let requiredComponents: PoseRequiredComponentsV1
    let observationRequirement: PoseObservationRequirementV1
    let applicability: PoseAxisApplicabilityV1
    let descriptorVersion: UInt64
    let descriptorSHA256: String

    init(axisID: PoseAxisID, localizedLabelKey: String,
         semanticRole: PoseAxisSemanticRoleV1,
         requiredComponents: PoseRequiredComponentsV1,
         observationRequirement: PoseObservationRequirementV1,
         applicability: PoseAxisApplicabilityV1,
         descriptorVersion: UInt64 = 1) throws {
        schemaVersion = Self.schemaVersion; self.axisID = axisID
        self.localizedLabelKey = localizedLabelKey; self.semanticRole = semanticRole
        self.requiredComponents = requiredComponents; self.observationRequirement = observationRequirement
        self.applicability = applicability; self.descriptorVersion = descriptorVersion
        descriptorSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            axisID: axisID, localizedLabelKey: localizedLabelKey, semanticRole: semanticRole,
            requiredComponents: requiredComponents, observationRequirement: observationRequirement,
            applicability: applicability, descriptorVersion: descriptorVersion))
        try validate()
    }
    func validate() throws {
        try PlacementPoseLimitsV1.token(localizedLabelKey); guard schemaVersion == Self.schemaVersion,
              descriptorVersion > 0, descriptorSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw PlacementPoseFailureV1.invalidDigest
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.axisID < rhs.axisID }
    private var basis: Basis { .init(schemaVersion: schemaVersion, axisID: axisID,
        localizedLabelKey: localizedLabelKey, semanticRole: semanticRole,
        requiredComponents: requiredComponents, observationRequirement: observationRequirement,
        applicability: applicability, descriptorVersion: descriptorVersion) }
    private struct Basis: Codable { let schemaVersion: Int; let axisID: PoseAxisID; let localizedLabelKey: String; let semanticRole: PoseAxisSemanticRoleV1; let requiredComponents: PoseRequiredComponentsV1; let observationRequirement: PoseObservationRequirementV1; let applicability: PoseAxisApplicabilityV1; let descriptorVersion: UInt64 }
}

struct PoseAxisDescriptorRegistryV1: Codable, Equatable, Sendable {
    let registryVersion: Int
    let descriptors: [PoseAxisDescriptorV1]
    let registrySHA256: String
    init(registryVersion: Int = 1, descriptors: [PoseAxisDescriptorV1]) throws {
        let ordered = descriptors.sorted(); self.registryVersion = registryVersion; self.descriptors = ordered
        registrySHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(registryVersion: registryVersion, descriptors: ordered))
        try validate()
    }
    func validate() throws {
        try descriptors.forEach { try $0.validate() }
        guard registryVersion > 0, !descriptors.isEmpty,
              descriptors.count <= PlacementPoseLimitsV1.maximumAxesPerRelease,
              descriptors == descriptors.sorted(), Set(descriptors.map(\.axisID)).count == descriptors.count,
              registrySHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(registryVersion: registryVersion, descriptors: descriptors))) else {
            throw PlacementPoseFailureV1.unorderedValue
        }
    }
    func descriptor(for axisID: PoseAxisID) throws -> PoseAxisDescriptorV1 {
        let matches = descriptors.filter { $0.axisID == axisID }
        guard matches.count == 1 else { throw PlacementPoseFailureV1.referenceMismatch }
        return matches[0]
    }
    private struct Basis: Codable { let registryVersion: Int; let descriptors: [PoseAxisDescriptorV1] }
}

struct PoseAxisRegistryPolicyV1: Codable, Equatable, Hashable, Sendable {
    let policyVersion: Int; let maximumAxesPerPackageRelease: Int
    let permitsUnknownAxes: Bool; let permitsRetiredAxes: Bool
    init(policyVersion: Int = 1,
         maximumAxesPerPackageRelease: Int = PlacementPoseLimitsV1.maximumAxesPerRelease) throws {
        guard policyVersion > 0,
              maximumAxesPerPackageRelease == PlacementPoseLimitsV1.maximumAxesPerRelease else {
            throw PlacementPoseFailureV1.invalidValue
        }
        self.policyVersion = policyVersion
        self.maximumAxesPerPackageRelease = maximumAxesPerPackageRelease
        permitsUnknownAxes = false; permitsRetiredAxes = false
    }
    func validate(_ registry: PoseAxisDescriptorRegistryV1) throws {
        try registry.validate()
        guard registry.descriptors.count <= maximumAxesPerPackageRelease,
              !permitsUnknownAxes, !permitsRetiredAxes else { throw PlacementPoseFailureV1.invalidValue }
    }
}

struct PoseAxisRegistryReleaseV1: Codable, Equatable, Sendable {
    let packageReleaseID: String; let packageID: String; let packageContentVersion: Int
    let packageSHA256: String; let workflowSHA256: String
    let registry: PoseAxisDescriptorRegistryV1; let releaseSHA256: String
    init(packageRelease: InspectionPackageReleaseV1,
         registry: PoseAxisDescriptorRegistryV1) throws {
        try packageRelease.validate(); try registry.validate()
        packageReleaseID = packageRelease.packageReleaseID; packageID = packageRelease.packageID
        packageContentVersion = packageRelease.packageContentVersion
        packageSHA256 = packageRelease.packageSHA256; workflowSHA256 = packageRelease.workflowSHA256
        self.registry = registry
        releaseSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(packageReleaseID: packageReleaseID,
            packageID: packageID, packageContentVersion: packageContentVersion,
            packageSHA256: packageSHA256, workflowSHA256: workflowSHA256, registry: registry))
    }
    func validate(packageRelease: InspectionPackageReleaseV1) throws {
        try packageRelease.validate(); try registry.validate()
        guard packageReleaseID == packageRelease.packageReleaseID, packageID == packageRelease.packageID,
              packageContentVersion == packageRelease.packageContentVersion,
              packageSHA256 == packageRelease.packageSHA256,
              workflowSHA256 == packageRelease.workflowSHA256,
              releaseSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(packageReleaseID: packageReleaseID,
                packageID: packageID, packageContentVersion: packageContentVersion,
                packageSHA256: packageSHA256, workflowSHA256: workflowSHA256, registry: registry))) else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
    }
    private struct Basis: Codable { let packageReleaseID: String; let packageID: String; let packageContentVersion: Int; let packageSHA256: String; let workflowSHA256: String; let registry: PoseAxisDescriptorRegistryV1 }
}

/// Exact, caller-supplied authorities required to admit pose post-images. The
/// closure is immutable and is validated against the complete mutation bundle;
/// it is not a current-state projection and cannot infer missing authorities.
struct PlacementPoseAdmissionClosureV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let packageRelease: InspectionPackageReleaseV1
    let axisRegistryRelease: PoseAxisRegistryReleaseV1
    let planRevisions: [PlanRevisionV1]
    let placementEvents: [AssetPlacementEventV1]

    init(workspaceID: WorkspaceID, packageRelease: InspectionPackageReleaseV1,
         axisRegistryRelease: PoseAxisRegistryReleaseV1,
         planRevisions: [PlanRevisionV1], placementEvents: [AssetPlacementEventV1]) throws {
        self.workspaceID = workspaceID
        self.packageRelease = packageRelease
        self.axisRegistryRelease = axisRegistryRelease
        self.planRevisions = planRevisions.sorted { $0.planRevisionID.uuidString < $1.planRevisionID.uuidString }
        self.placementEvents = placementEvents.sorted { $0.id.uuidString < $1.id.uuidString }
        try validateAuthorities()
    }

    static func merging(_ closures: [Self]) throws -> Self {
        guard let first = closures.first,
              closures.allSatisfy({
                  $0.workspaceID == first.workspaceID
                    && $0.packageRelease == first.packageRelease
                    && $0.axisRegistryRelease == first.axisRegistryRelease
              }) else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        var revisions: [UUID: PlanRevisionV1] = [:]
        var placements: [UUID: AssetPlacementEventV1] = [:]
        for closure in closures {
            try closure.validateAuthorities()
            for revision in closure.planRevisions {
                if let existing = revisions[revision.planRevisionID], existing != revision {
                    throw PlacementPoseFailureV1.duplicateIdentity
                }
                revisions[revision.planRevisionID] = revision
            }
            for placement in closure.placementEvents {
                if let existing = placements[placement.id], existing != placement {
                    throw PlacementPoseFailureV1.duplicateIdentity
                }
                placements[placement.id] = placement
            }
        }
        return try .init(workspaceID: first.workspaceID, packageRelease: first.packageRelease,
                         axisRegistryRelease: first.axisRegistryRelease,
                         planRevisions: Array(revisions.values),
                         placementEvents: Array(placements.values))
    }

    func validate(events: [AssetPoseEventV1],
                  observations: [SpatialAnchorObservationV1]) throws {
        try validateAuthorities()
        guard events.count + observations.count <= PlacementPoseLimitsV1.maximumEventsPerClosure else {
            throw PlacementPoseFailureV1.invalidValue
        }

        var placementByID: [UUID: AssetPlacementEventV1] = [:]
        for placement in placementEvents {
            guard placementByID.updateValue(placement, forKey: placement.id) == nil else {
                throw PlacementPoseFailureV1.duplicateIdentity
            }
        }
        var revisionByReference: [PlanRevisionReferenceV1: PlanRevisionV1] = [:]
        for revision in planRevisions {
            let reference = try revision.reference
            guard revisionByReference.updateValue(revision, forKey: reference) == nil else {
                throw PlacementPoseFailureV1.duplicateIdentity
            }
        }

        var usedPlacementIDs = Set<UUID>()
        var usedPlanReferences = Set<PlanRevisionReferenceV1>()
        for event in events {
            try event.validateIntrinsic()
            guard event.workspaceID == workspaceID,
                  axisRegistryRelease.registry.descriptors.filter({ $0.axisID == event.axisDescriptor.axisID }) == [event.axisDescriptor],
                  let placement = placementByID[event.placementEventID],
                  placement.workspaceID == workspaceID,
                  placement.assetID == event.assetID,
                  placement.physicalEpisodeID == event.placementEpisodeID,
                  placement.pathSnapshot == event.locationPathSnapshot else {
                throw PlacementPoseFailureV1.referenceMismatch
            }
            usedPlacementIDs.insert(placement.id)
            if case .planRelative(let frame) = event.pose.referenceFrame {
                try validate(frame: frame, revisions: revisionByReference)
                usedPlanReferences.insert(frame.planRevision)
            }
        }
        for observation in observations {
            try observation.validateIntrinsic()
            guard observation.workspaceID == workspaceID else {
                throw PlacementPoseFailureV1.wrongWorkspace
            }
            let placements = placementEvents.filter {
                $0.workspaceID == workspaceID && $0.assetID == observation.assetID
                    && $0.physicalEpisodeID == observation.placementEpisodeID
            }
            guard placements.count == 1 else { throw PlacementPoseFailureV1.referenceMismatch }
            usedPlacementIDs.insert(placements[0].id)
            try validate(frame: observation.planFrame, revisions: revisionByReference)
            usedPlanReferences.insert(observation.planFrame.planRevision)
        }
        var suppliedPlanReferences = Set<PlanRevisionReferenceV1>()
        for revision in planRevisions { suppliedPlanReferences.insert(try revision.reference) }
        guard usedPlacementIDs == Set(placementEvents.map(\.id)),
              usedPlanReferences == suppliedPlanReferences else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
    }

    private func validateAuthorities() throws {
        try packageRelease.validate()
        try axisRegistryRelease.validate(packageRelease: packageRelease)
        try planRevisions.forEach {
            try $0.validateIntrinsic()
            guard $0.workspaceID == workspaceID else { throw PlacementPoseFailureV1.wrongWorkspace }
        }
        try placementEvents.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else { throw PlacementPoseFailureV1.wrongWorkspace }
        }
        guard Set(planRevisions.map(\.planRevisionID)).count == planRevisions.count,
              Set(placementEvents.map(\.id)).count == placementEvents.count else {
            throw PlacementPoseFailureV1.duplicateIdentity
        }
    }

    private func validate(frame: PlanRelativePoseFrameBindingV1,
                          revisions: [PlanRevisionReferenceV1: PlanRevisionV1]) throws {
        try frame.validate()
        guard let revision = revisions[frame.planRevision], revision.workspaceID == workspaceID,
              revision.pages.filter({ $0.pageID == frame.pageID }).count == 1,
              revision.spatialFrames.filter({
                  $0.frameID == frame.spatialFrameID && $0.pageID == frame.pageID
              }).count == 1 else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
    }
}

enum PoseAngleKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case azimuth = "AZIMUTH"; case elevation = "ELEVATION"
    case horizontalUncertainty = "HORIZONTAL_UNCERTAINTY"; case verticalUncertainty = "VERTICAL_UNCERTAINTY"
}

struct PoseAngleMilliDegreesV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let kind: PoseAngleKindV1
    let milliDegrees: Int32
    init(kind: PoseAngleKindV1, milliDegrees: Int32) throws {
        let valid: Bool
        switch kind {
        case .azimuth: valid = (0..<360_000).contains(milliDegrees)
        case .elevation: valid = (-90_000...90_000).contains(milliDegrees)
        case .horizontalUncertainty: valid = (0...180_000).contains(milliDegrees)
        case .verticalUncertainty: valid = (0...90_000).contains(milliDegrees)
        }
        guard valid else { throw PlacementPoseFailureV1.invalidValue }
        self.kind = kind; self.milliDegrees = milliDegrees
    }
    static func azimuth(_ value: Int32) throws -> Self { try .init(kind: .azimuth, milliDegrees: value) }
    static func elevation(_ value: Int32) throws -> Self { try .init(kind: .elevation, milliDegrees: value) }
    static func horizontalUncertainty(_ value: Int32) throws -> Self { try .init(kind: .horizontalUncertainty, milliDegrees: value) }
    static func verticalUncertainty(_ value: Int32) throws -> Self { try .init(kind: .verticalUncertainty, milliDegrees: value) }
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.kind.rawValue, lhs.milliDegrees) < (rhs.kind.rawValue, rhs.milliDegrees) }
    private enum CodingKeys: String, CodingKey { case kind, milliDegrees }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(kind: container.decode(PoseAngleKindV1.self, forKey: .kind),
                      milliDegrees: container.decode(Int32.self, forKey: .milliDegrees))
    }
}

enum PoseUncertaintyV1: Codable, Equatable, Hashable, Sendable {
    case known(PoseAngleMilliDegreesV1)
    case unknown
    func validate(expected kind: PoseAngleKindV1) throws {
        if case .known(let value) = self, value.kind != kind { throw PlacementPoseFailureV1.invalidValue }
    }
}

enum PoseObservationDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case observed = "OBSERVED"; case notObserved = "NOT_OBSERVED"
}

enum PoseNotObservedReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notYetObserved = "NOT_YET_OBSERVED"
    case physicalMoveReobservationRequired = "PHYSICAL_MOVE_REOBSERVATION_REQUIRED"
    case planFrameLostReobservationRequired = "PLAN_FRAME_LOST_REOBSERVATION_REQUIRED"
    case obscuredOrUnsafe = "OBSCURED_OR_UNSAFE"
    case sourceUnavailable = "SOURCE_UNAVAILABLE"
    case userDeclined = "USER_DECLINED"
}

struct PlanRelativePoseFrameBindingV1: Codable, Equatable, Hashable, Sendable {
    let planRevision: PlanRevisionReferenceV1
    let pageID: UUID
    let spatialFrameID: UUID
    let acceptedTransformSHA256: String
    func validate() throws { try planRevision.validate(); try PlacementPoseLimitsV1.id(pageID); try PlacementPoseLimitsV1.id(spatialFrameID); try PlacementPoseLimitsV1.digest(acceptedTransformSHA256) }
}

enum PoseReferenceFrameV1: Codable, Equatable, Hashable, Sendable {
    case unknown
    case planRelative(PlanRelativePoseFrameBindingV1)
    case trueBearing
    case magneticBearing
    func validate() throws { if case .planRelative(let value) = self { try value.validate() } }
}

enum PoseCaptureSourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case manual = "MANUAL"
    case deviceHeadingProposalAccepted = "DEVICE_HEADING_PROPOSAL_ACCEPTED"
    case planGesture = "PLAN_GESTURE"
    case imported = "IMPORT"
    case surveyPromotion = "SURVEY_PROMOTION"
    case planRebase = "PLAN_REBASE"
    case placementCarryForward = "PLACEMENT_CARRY_FORWARD"
    case semanticReversal = "SEMANTIC_REVERSAL"
}
typealias PoseObservationSourceV1 = PoseCaptureSourceV1

struct DeviceHeadingProposalV1: Codable, Equatable, Sendable {
    enum AvailabilityV1: String, Codable, CaseIterable, Sendable {
        case available = "AVAILABLE"; case denied = "DENIED"; case unavailable = "UNAVAILABLE"
    }
    let workspaceID: WorkspaceID; let assetID: UUID; let axisID: PoseAxisID
    let proposedAzimuth: PoseAngleMilliDegreesV1; let referenceFrame: PoseReferenceFrameV1
    let accuracyMilliDegrees: Int32; let availability: AvailabilityV1
    let capturedAt: Date; let expiresAt: Date; let requiresManualAcceptance: Bool
    init(workspaceID: WorkspaceID, assetID: UUID, axisID: PoseAxisID,
         proposedAzimuth: PoseAngleMilliDegreesV1, referenceFrame: PoseReferenceFrameV1,
         accuracyMilliDegrees: Int32, availability: AvailabilityV1,
         capturedAt: Date, expiresAt: Date) throws {
        try PlacementPoseLimitsV1.id(assetID); try referenceFrame.validate()
        guard proposedAzimuth.kind == .azimuth, referenceFrame != .unknown,
              accuracyMilliDegrees >= 0, accuracyMilliDegrees <= 180_000,
              availability == .available, capturedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite, capturedAt < expiresAt else {
            throw PlacementPoseFailureV1.invalidValue
        }
        self.workspaceID = workspaceID; self.assetID = assetID; self.axisID = axisID
        self.proposedAzimuth = proposedAzimuth; self.referenceFrame = referenceFrame
        self.accuracyMilliDegrees = accuracyMilliDegrees; self.availability = availability
        self.capturedAt = capturedAt; self.expiresAt = expiresAt; requiresManualAcceptance = true
    }
    func validateFresh(at now: Date) throws {
        guard availability == .available, now >= capturedAt, now < expiresAt else {
            throw PlacementPoseFailureV1.reviewRequired
        }
    }
}

struct PlacementPoseV1: Codable, Equatable, Hashable, Sendable {
    let disposition: PoseObservationDispositionV1
    let referenceFrame: PoseReferenceFrameV1
    let azimuth: PoseAngleMilliDegreesV1?
    let elevation: PoseAngleMilliDegreesV1?
    let horizontalUncertainty: PoseUncertaintyV1?
    let verticalUncertainty: PoseUncertaintyV1?
    let notObservedReason: PoseNotObservedReasonV1?

    init(disposition: PoseObservationDispositionV1, referenceFrame: PoseReferenceFrameV1,
         azimuth: PoseAngleMilliDegreesV1? = nil, elevation: PoseAngleMilliDegreesV1? = nil,
         horizontalUncertainty: PoseUncertaintyV1? = nil, verticalUncertainty: PoseUncertaintyV1? = nil,
         notObservedReason: PoseNotObservedReasonV1? = nil,
         descriptor: PoseAxisDescriptorV1) throws {
        self.disposition = disposition; self.referenceFrame = referenceFrame; self.azimuth = azimuth
        self.elevation = elevation; self.horizontalUncertainty = horizontalUncertainty
        self.verticalUncertainty = verticalUncertainty; self.notObservedReason = notObservedReason
        try validate(descriptor: descriptor)
    }
    func validate(descriptor: PoseAxisDescriptorV1) throws {
        try descriptor.validate(); try referenceFrame.validate()
        guard descriptor.applicability == .applicable else { throw PlacementPoseFailureV1.invalidValue }
        switch disposition {
        case .notObserved:
            guard referenceFrame == .unknown, azimuth == nil, elevation == nil,
                  horizontalUncertainty == nil, verticalUncertainty == nil, notObservedReason != nil else {
                throw PlacementPoseFailureV1.invalidValue
            }
        case .observed:
            guard referenceFrame != .unknown, notObservedReason == nil,
                  azimuth?.kind == .azimuth, horizontalUncertainty != nil else { throw PlacementPoseFailureV1.invalidValue }
            try horizontalUncertainty?.validate(expected: .horizontalUncertainty)
            switch descriptor.requiredComponents {
            case .azimuthOnly:
                guard elevation == nil, verticalUncertainty == nil else { throw PlacementPoseFailureV1.invalidValue }
            case .azimuthAndElevation:
                guard elevation?.kind == .elevation, verticalUncertainty != nil else { throw PlacementPoseFailureV1.invalidValue }
                try verticalUncertainty?.validate(expected: .verticalUncertainty)
            }
        }
    }
}

struct AssetPoseEventReferenceV1: Codable, Equatable, Hashable, Sendable {
    let eventID: UUID; let workspaceID: WorkspaceID; let assetID: UUID; let axisID: PoseAxisID
    let revision: UInt64; let eventSHA256: String
    func validate() throws { try PlacementPoseLimitsV1.id(eventID); try PlacementPoseLimitsV1.id(assetID); guard revision > 0 else { throw PlacementPoseFailureV1.invalidValue }; try PlacementPoseLimitsV1.digest(eventSHA256) }
}

struct AssetPoseEventV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let eventID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let axisDescriptor: PoseAxisDescriptorV1; let placementEpisodeID: PhysicalPlacementEpisodeIDV1
    let placementEventID: UUID; let locationPathSnapshot: LocationPathSnapshotV1
    let pose: PlacementPoseV1; let source: PoseObservationSourceV1
    let rootObservationEventID: UUID; let rootObservedAt: Date; let predecessor: AssetPoseEventReferenceV1?
    let revision: UInt64; let mutationID: MutationIDV1; let recordedBy: ActorSnapshotV1
    let occurredAt: Date; let recordedAt: Date; let eventSHA256: String

    init(eventID: UUID, workspaceID: WorkspaceID, assetID: UUID,
         axisDescriptor: PoseAxisDescriptorV1, placementEpisodeID: PhysicalPlacementEpisodeIDV1,
         placementEventID: UUID, locationPathSnapshot: LocationPathSnapshotV1,
         pose: PlacementPoseV1, source: PoseObservationSourceV1,
         rootObservationEventID: UUID, rootObservedAt: Date, predecessor: AssetPoseEventV1?,
         revision: UInt64, mutationID: MutationIDV1, recordedBy: ActorSnapshotV1,
         occurredAt: Date, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.eventID = eventID; self.workspaceID = workspaceID; self.assetID = assetID
        self.axisDescriptor = axisDescriptor; self.placementEpisodeID = placementEpisodeID
        self.placementEventID = placementEventID; self.locationPathSnapshot = locationPathSnapshot
        self.pose = pose; self.source = source; self.rootObservationEventID = rootObservationEventID
        self.rootObservedAt = rootObservedAt; self.predecessor = predecessor?.reference
        self.revision = revision; self.mutationID = mutationID; self.recordedBy = recordedBy
        self.occurredAt = occurredAt; self.recordedAt = recordedAt
        eventSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            axisDescriptor: axisDescriptor, placementEpisodeID: placementEpisodeID,
            placementEventID: placementEventID, locationPathSnapshot: locationPathSnapshot,
            pose: pose, source: source,
            rootObservationEventID: rootObservationEventID, rootObservedAt: rootObservedAt,
            predecessor: predecessor?.reference, revision: revision, mutationID: mutationID,
            recordedBy: recordedBy, occurredAt: occurredAt, recordedAt: recordedAt))
        try validateIntrinsic(); if let predecessor { try validateSuccessor(of: predecessor) }
    }
    var reference: AssetPoseEventReferenceV1 { .init(eventID: eventID, workspaceID: workspaceID, assetID: assetID, axisID: axisDescriptor.axisID, revision: revision, eventSHA256: eventSHA256) }
    func validateIntrinsic() throws {
        try PlacementPoseLimitsV1.id(eventID); try PlacementPoseLimitsV1.id(assetID); try PlacementPoseLimitsV1.id(placementEventID)
        try PlacementPoseLimitsV1.id(rootObservationEventID); try axisDescriptor.validate()
        try locationPathSnapshot.validate(); try pose.validate(descriptor: axisDescriptor)
        try recordedBy.validate(); try predecessor?.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0, recordedBy.workspaceID == workspaceID,
              occurredAt.timeIntervalSinceReferenceDate.isFinite, recordedAt.timeIntervalSinceReferenceDate.isFinite,
              rootObservedAt.timeIntervalSinceReferenceDate.isFinite, occurredAt <= recordedAt,
              (predecessor == nil) == (revision == 1),
              eventSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basisWithoutDigest)) else { throw PlacementPoseFailureV1.invalidDigest }
        if source == .planRebase || source == .placementCarryForward || source == .semanticReversal {
            guard predecessor != nil, recordedBy.responsibility == .recordedBy else {
                throw PlacementPoseFailureV1.predecessorMismatch
            }
        } else {
            guard recordedBy.responsibility == .observedBy,
                  rootObservationEventID == eventID, rootObservedAt == occurredAt else {
                throw PlacementPoseFailureV1.referenceMismatch
            }
        }
    }
    func validateSuccessor(of prior: AssetPoseEventV1) throws {
        try validateIntrinsic(); try prior.validateIntrinsic()
        guard prior.revision < UInt64.max, workspaceID == prior.workspaceID, assetID == prior.assetID,
              axisDescriptor.axisID == prior.axisDescriptor.axisID, predecessor == prior.reference,
              revision == prior.revision + 1, eventID != prior.eventID, mutationID != prior.mutationID else {
            throw PlacementPoseFailureV1.predecessorMismatch
        }
        if source == .planRebase || source == .placementCarryForward || source == .semanticReversal {
            guard rootObservationEventID == prior.rootObservationEventID,
                  rootObservedAt == prior.rootObservedAt else { throw PlacementPoseFailureV1.referenceMismatch }
        }
    }
    func rebound(to workspaceID: WorkspaceID, predecessor: AssetPoseEventV1?,
                 recordedBy: ActorSnapshotV1) throws -> Self {
        guard recordedBy.workspaceID == workspaceID else { throw PlacementPoseFailureV1.wrongWorkspace }
        if let predecessor, predecessor.revision == UInt64.max { throw PlacementPoseFailureV1.arithmeticOverflow }
        return try .init(eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            axisDescriptor: axisDescriptor, placementEpisodeID: placementEpisodeID,
            placementEventID: placementEventID, locationPathSnapshot: locationPathSnapshot,
            pose: pose, source: source,
            rootObservationEventID: rootObservationEventID, rootObservedAt: rootObservedAt,
            predecessor: predecessor, revision: predecessor.map { $0.revision + 1 } ?? 1,
            mutationID: mutationID, recordedBy: recordedBy,
            occurredAt: occurredAt, recordedAt: recordedAt)
    }
    func rebound(to workspaceID: WorkspaceID, recordedBy: ActorSnapshotV1) throws -> Self {
        guard predecessor == nil else { throw PlacementPoseFailureV1.predecessorMismatch }
        return try rebound(to: workspaceID, predecessor: nil, recordedBy: recordedBy)
    }
    func reissued(mutationID: MutationIDV1, predecessor: AssetPoseEventV1) throws -> Self {
        try .init(eventID: eventID, workspaceID: workspaceID, assetID: assetID,
            axisDescriptor: axisDescriptor, placementEpisodeID: placementEpisodeID,
            placementEventID: placementEventID, locationPathSnapshot: locationPathSnapshot,
            pose: pose, source: source, rootObservationEventID: rootObservationEventID,
            rootObservedAt: rootObservedAt, predecessor: predecessor, revision: revision,
            mutationID: mutationID, recordedBy: recordedBy, occurredAt: occurredAt,
            recordedAt: recordedAt)
    }
    private var basisWithoutDigest: Basis { .init(schemaVersion: schemaVersion, eventID: eventID, workspaceID: workspaceID, assetID: assetID, axisDescriptor: axisDescriptor, placementEpisodeID: placementEpisodeID, placementEventID: placementEventID, locationPathSnapshot: locationPathSnapshot, pose: pose, source: source, rootObservationEventID: rootObservationEventID, rootObservedAt: rootObservedAt, predecessor: predecessor, revision: revision, mutationID: mutationID, recordedBy: recordedBy, occurredAt: occurredAt, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let eventID: UUID; let workspaceID: WorkspaceID; let assetID: UUID; let axisDescriptor: PoseAxisDescriptorV1; let placementEpisodeID: PhysicalPlacementEpisodeIDV1; let placementEventID: UUID; let locationPathSnapshot: LocationPathSnapshotV1; let pose: PlacementPoseV1; let source: PoseObservationSourceV1; let rootObservationEventID: UUID; let rootObservedAt: Date; let predecessor: AssetPoseEventReferenceV1?; let revision: UInt64; let mutationID: MutationIDV1; let recordedBy: ActorSnapshotV1; let occurredAt: Date; let recordedAt: Date }
}

enum SpatialAnchorObservationDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case observed = "OBSERVED"; case notObserved = "NOT_OBSERVED"
}

struct SpatialAnchorObservationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let observationID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let placementEpisodeID: PhysicalPlacementEpisodeIDV1; let planFrame: PlanRelativePoseFrameBindingV1
    let x: NormalizedPlanCoordinateV1?; let y: NormalizedPlanCoordinateV1?
    let disposition: SpatialAnchorObservationDispositionV1; let reason: PoseNotObservedReasonV1?
    let predecessorObservationID: UUID?; let predecessorSHA256: String?; let revision: UInt64
    let mutationID: MutationIDV1; let observedBy: ActorSnapshotV1; let observedAt: Date; let observationSHA256: String
    init(observationID: UUID, workspaceID: WorkspaceID, assetID: UUID,
         placementEpisodeID: PhysicalPlacementEpisodeIDV1, planFrame: PlanRelativePoseFrameBindingV1,
         x: NormalizedPlanCoordinateV1?, y: NormalizedPlanCoordinateV1?,
         disposition: SpatialAnchorObservationDispositionV1, reason: PoseNotObservedReasonV1?,
         predecessor: SpatialAnchorObservationV1?, revision: UInt64, mutationID: MutationIDV1,
         observedBy: ActorSnapshotV1, observedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.observationID = observationID; self.workspaceID = workspaceID; self.assetID = assetID
        self.placementEpisodeID = placementEpisodeID; self.planFrame = planFrame; self.x = x; self.y = y
        self.disposition = disposition; self.reason = reason; predecessorObservationID = predecessor?.observationID
        predecessorSHA256 = predecessor?.observationSHA256; self.revision = revision; self.mutationID = mutationID
        self.observedBy = observedBy; self.observedAt = observedAt
        observationSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            observationID: observationID, workspaceID: workspaceID, assetID: assetID,
            placementEpisodeID: placementEpisodeID, planFrame: planFrame, x: x, y: y,
            disposition: disposition, reason: reason,
            predecessorObservationID: predecessor?.observationID,
            predecessorSHA256: predecessor?.observationSHA256, revision: revision,
            mutationID: mutationID, observedBy: observedBy, observedAt: observedAt))
        try validateIntrinsic(); if let predecessor { try validateSuccessor(of: predecessor) }
    }
    func validateIntrinsic() throws {
        try PlacementPoseLimitsV1.id(observationID); try PlacementPoseLimitsV1.id(assetID); try planFrame.validate(); try observedBy.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0, observedBy.workspaceID == workspaceID,
              observedAt.timeIntervalSinceReferenceDate.isFinite,
              (predecessorObservationID == nil) == (predecessorSHA256 == nil),
              (predecessorObservationID == nil) == (revision == 1),
              ((disposition == .observed && x != nil && y != nil && reason == nil) ||
               (disposition == .notObserved && x == nil && y == nil && reason != nil)),
              observationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else { throw PlacementPoseFailureV1.invalidDigest }
        try predecessorSHA256.map(PlacementPoseLimitsV1.digest)
    }
    func validateSuccessor(of prior: Self) throws {
        try validateIntrinsic(); try prior.validateIntrinsic()
        guard prior.revision < UInt64.max, workspaceID == prior.workspaceID, assetID == prior.assetID,
              predecessorObservationID == prior.observationID, predecessorSHA256 == prior.observationSHA256,
              revision == prior.revision + 1, mutationID != prior.mutationID else { throw PlacementPoseFailureV1.predecessorMismatch }
    }
    func rebound(to workspaceID: WorkspaceID, predecessor: Self?,
                 observedBy: ActorSnapshotV1) throws -> Self {
        guard observedBy.workspaceID == workspaceID else { throw PlacementPoseFailureV1.wrongWorkspace }
        if let predecessor, predecessor.revision == UInt64.max { throw PlacementPoseFailureV1.arithmeticOverflow }
        return try .init(observationID: observationID, workspaceID: workspaceID, assetID: assetID,
            placementEpisodeID: placementEpisodeID, planFrame: planFrame, x: x, y: y,
            disposition: disposition, reason: reason, predecessor: predecessor,
            revision: predecessor.map { $0.revision + 1 } ?? 1, mutationID: mutationID,
            observedBy: observedBy, observedAt: observedAt)
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, observationID: observationID, workspaceID: workspaceID, assetID: assetID, placementEpisodeID: placementEpisodeID, planFrame: planFrame, x: x, y: y, disposition: disposition, reason: reason, predecessorObservationID: predecessorObservationID, predecessorSHA256: predecessorSHA256, revision: revision, mutationID: mutationID, observedBy: observedBy, observedAt: observedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let observationID: UUID; let workspaceID: WorkspaceID; let assetID: UUID; let placementEpisodeID: PhysicalPlacementEpisodeIDV1; let planFrame: PlanRelativePoseFrameBindingV1; let x: NormalizedPlanCoordinateV1?; let y: NormalizedPlanCoordinateV1?; let disposition: SpatialAnchorObservationDispositionV1; let reason: PoseNotObservedReasonV1?; let predecessorObservationID: UUID?; let predecessorSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let observedBy: ActorSnapshotV1; let observedAt: Date }
}

struct AssetPoseCurrentTipV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let assetID: UUID; let tips: [AssetPoseEventReferenceV1]; let projectionSHA256: String
}
typealias CurrentPoseProjectionV1 = AssetPoseCurrentTipV1

enum AssetPoseHistoryV1 {
    static func currentTip(workspaceID: WorkspaceID, assetID: UUID,
                           events: [AssetPoseEventV1]) throws -> AssetPoseCurrentTipV1 {
        guard !events.isEmpty, events.count <= PlacementPoseLimitsV1.maximumEventsPerClosure else { throw PlacementPoseFailureV1.invalidValue }
        var byID: [UUID: AssetPoseEventV1] = [:]
        for event in events { try event.validateIntrinsic(); guard byID.updateValue(event, forKey: event.eventID) == nil else { throw PlacementPoseFailureV1.duplicateIdentity } }
        guard events.allSatisfy({ $0.workspaceID == workspaceID && $0.assetID == assetID }) else { throw PlacementPoseFailureV1.wrongWorkspace }
        for event in events { if let predecessor = event.predecessor { guard let prior = byID[predecessor.eventID] else { throw PlacementPoseFailureV1.predecessorMismatch }; try event.validateSuccessor(of: prior) } }
        let referenced = Set(events.compactMap { $0.predecessor?.eventID })
        let tips = events.filter { !referenced.contains($0.eventID) }.map(\.reference).sorted { $0.axisID < $1.axisID }
        guard Set(tips.map(\.axisID)).count == tips.count else { throw PlacementPoseFailureV1.duplicateIdentity }
        return .init(workspaceID: workspaceID, assetID: assetID, tips: tips,
                     projectionSHA256: try WorkspaceMutationCanonicalV1.sha256(tips))
    }
}

struct PosePlacementDispositionIntentV1: Codable, Equatable, Sendable {
    let predecessor: AssetPoseEventReferenceV1; let proposedPose: PlacementPoseV1
    let disposition: PosePlacementDispositionV1; let intentSHA256: String
    init(predecessor: AssetPoseEventReferenceV1, proposedPose: PlacementPoseV1,
         disposition: PosePlacementDispositionV1) throws {
        try predecessor.validate(); self.predecessor = predecessor; self.proposedPose = proposedPose
        self.disposition = disposition
        intentSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(predecessor: predecessor,
            proposedPose: proposedPose, disposition: disposition))
    }
    func validate(descriptor: PoseAxisDescriptorV1) throws {
        try predecessor.validate(); try proposedPose.validate(descriptor: descriptor)
        guard predecessor.axisID == descriptor.axisID,
              intentSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(predecessor: predecessor,
                proposedPose: proposedPose, disposition: disposition))) else { throw PlacementPoseFailureV1.invalidDigest }
    }
    private struct Basis: Codable { let predecessor: AssetPoseEventReferenceV1; let proposedPose: PlacementPoseV1; let disposition: PosePlacementDispositionV1 }
}

enum PosePlacementDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case reobserve = "REOBSERVE"
    case carryForwardSamePhysicalInstallation = "CARRY_FORWARD_SAME_PHYSICAL_INSTALLATION"
    case markNotObserved = "MARK_NOT_OBSERVED"
}

@MainActor
final class PosePlacementDispositionComponentV1: PlacementChangeComponentV1 {
    let componentID = "C37_POSE_PLACEMENT_DISPOSITION"; let componentVersion = 1
    private let currentPoseEvents: @MainActor (UUID) throws -> [AssetPoseEventV1]
    init(currentPoseEvents: @escaping @MainActor (UUID) throws -> [AssetPoseEventV1]) { self.currentPoseEvents = currentPoseEvents }
    func preview(_ basis: AssetPlacementPreviewBasisV1) throws -> PlacementChangeComponentContributionV1 {
        let events = try currentPoseEvents(basis.assetID)
        let moved = basis.reviewedContinuity == .physicalMove
        let disposition: PosePlacementDispositionV1 = moved ? .markNotObserved : .carryForwardSamePhysicalInstallation
        let intents = try events.map { event -> PosePlacementDispositionIntentV1 in
            let pose = moved ? try PlacementPoseV1(disposition: .notObserved, referenceFrame: .unknown,
                notObservedReason: .physicalMoveReobservationRequired, descriptor: event.axisDescriptor) : event.pose
            return try .init(predecessor: event.reference, proposedPose: pose, disposition: disposition)
        }.sorted { $0.predecessor.axisID < $1.predecessor.axisID }
        return try .init(componentID: componentID, componentVersion: componentVersion,
            warnings: moved && !events.isEmpty ? ["POSE_REOBSERVATION_REQUIRED"] : [],
            requiredContinuityReview: moved && !events.isEmpty,
            intentSHA256: WorkspaceMutationCanonicalV1.sha256(intents),
            poseDispositionIntents: intents)
    }
}

struct PoseFrameRebasePolicyV1: Codable, Equatable, Hashable, Sendable {
    let policyVersion: Int; let minimumSingularValueScaled: Int64; let maximumSingularValueRatioScaled: Int64
    let maximumSimilarityResidualScaled: Int64; let policySHA256: String
    init(policyVersion: Int = 1, minimumSingularValueScaled: Int64 = 1,
         maximumSingularValueRatioScaled: Int64 = 1_000_001_000,
         maximumSimilarityResidualScaled: Int64 = 1) throws {
        self.policyVersion = policyVersion; self.minimumSingularValueScaled = minimumSingularValueScaled
        self.maximumSingularValueRatioScaled = maximumSingularValueRatioScaled
        self.maximumSimilarityResidualScaled = maximumSimilarityResidualScaled
        policySHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(policyVersion: policyVersion, minimumSingularValueScaled: minimumSingularValueScaled, maximumSingularValueRatioScaled: maximumSingularValueRatioScaled, maximumSimilarityResidualScaled: maximumSimilarityResidualScaled))
        guard policyVersion > 0, minimumSingularValueScaled > 0, maximumSingularValueRatioScaled >= 1_000_000_000,
              maximumSimilarityResidualScaled >= 0 else { throw PlacementPoseFailureV1.invalidValue }
    }
    func validate() throws {
        guard policyVersion > 0, minimumSingularValueScaled > 0,
              maximumSingularValueRatioScaled >= 1_000_000_000,
              maximumSimilarityResidualScaled >= 0,
              policySHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(policyVersion: policyVersion,
                minimumSingularValueScaled: minimumSingularValueScaled,
                maximumSingularValueRatioScaled: maximumSingularValueRatioScaled,
                maximumSimilarityResidualScaled: maximumSimilarityResidualScaled))) else {
            throw PlacementPoseFailureV1.invalidDigest
        }
    }
    private struct Basis: Codable { let policyVersion: Int; let minimumSingularValueScaled: Int64; let maximumSingularValueRatioScaled: Int64; let maximumSimilarityResidualScaled: Int64 }
}

struct PoseFrameRebaseComponentV1: PlanRebaseComponentV1 {
    let componentID = "C37_POSE_FRAME_REBASE"; let componentVersion = 1; let stableSortOrdinal = 3700
    let policy: PoseFrameRebasePolicyV1
    let currentPoseEvents: @Sendable (WorkspaceID, UUID) throws -> [AssetPoseEventV1]
    let currentAnchorObservations: @Sendable (WorkspaceID, UUID) throws -> [SpatialAnchorObservationV1]
    init(policy: PoseFrameRebasePolicyV1,
         currentPoseEvents: @escaping @Sendable (WorkspaceID, UUID) throws -> [AssetPoseEventV1],
         currentAnchorObservations: @escaping @Sendable (WorkspaceID, UUID) throws -> [SpatialAnchorObservationV1] = { _, _ in [] }) {
        self.policy = policy; self.currentPoseEvents = currentPoseEvents
        self.currentAnchorObservations = currentAnchorObservations
    }
    func reviewedContribution(poseEffects: PlacementPoseMutationV1) throws
        -> PlanRebaseComponentContributionV1 {
        try poseEffects.validate()
        guard poseEffects.observations.isEmpty,
              poseEffects.events.allSatisfy({ $0.source == .planRebase }) else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        return try .init(componentID: componentID, componentVersion: componentVersion,
            rows: [], warnings: [], requiresReview: false,
            mutationIntentSHA256: WorkspaceMutationCanonicalV1.sha256(poseEffects))
    }
    func evaluate(_ context: PlanRebaseComponentContextV1) throws -> PlanRebaseComponentContributionV1 {
        try policy.validate(); try context.transform.validate()
        var intentDigests: [String] = []; var warnings: [PlanRebaseWarningV1] = []
        for placement in context.placements where placement.subjectKind == .asset {
            for event in try currentPoseEvents(context.workspaceID, placement.subjectID) {
                guard case .planRelative(let frame) = event.pose.referenceFrame,
                      frame.planRevision.planRevisionID == context.oldRevision.planRevisionID else { continue }
                let disposition = try transformedAzimuth(event.pose.azimuth, by: context.transform)
                if disposition == nil { warnings.append(.init(code: .componentReviewRequired, placementID: placement.placementID, componentID: componentID)) }
                intentDigests.append(try WorkspaceMutationCanonicalV1.sha256([event.eventSHA256,
                    disposition.map { String($0) } ?? "REVIEW_REQUIRED", context.transform.transformSHA256]))
            }
            for anchor in try currentAnchorObservations(context.workspaceID, placement.subjectID) {
                try anchor.validateIntrinsic()
                guard anchor.planFrame.planRevision.planRevisionID == context.oldRevision.planRevisionID else { continue }
                guard let x = anchor.x, let y = anchor.y else {
                    intentDigests.append(try WorkspaceMutationCanonicalV1.sha256([anchor.observationSHA256,
                        "REOBSERVATION_REQUIRED", context.transform.transformSHA256])); continue
                }
                let transformed = try context.transform.applyingNormalized(x: x, y: y)
                if transformed.disposition != .accepted {
                    warnings.append(.init(code: .outOfBounds, placementID: placement.placementID, componentID: componentID))
                }
                intentDigests.append(try WorkspaceMutationCanonicalV1.sha256([anchor.observationSHA256,
                    transformed.x.map { String($0.millionths) } ?? "OUT_OF_BOUNDS",
                    transformed.y.map { String($0.millionths) } ?? "OUT_OF_BOUNDS",
                    context.transform.transformSHA256]))
            }
        }
        return try .init(componentID: componentID, componentVersion: componentVersion, rows: [], warnings: warnings,
            requiresReview: !warnings.isEmpty, mutationIntentSHA256: WorkspaceMutationCanonicalV1.sha256(intentDigests.sorted()))
    }
    func transformedAzimuth(_ angle: PoseAngleMilliDegreesV1?, by transform: PlanAffineTransformV1) throws -> Int32? {
        try policy.validate()
        guard let angle, angle.kind == .azimuth else { return nil }
        let scale = 1_000_000_000.0; let radians = Double(angle.milliDegrees) * .pi / 180_000.0
        let a = Double(transform.m11) / scale, b = Double(transform.m12) / scale
        let c = Double(transform.m21) / scale, d = Double(transform.m22) / scale
        let trace = a * a + b * b + c * c + d * d
        let determinant = a * d - b * c
        let discriminant = max(0, trace * trace - 4 * determinant * determinant)
        let largest = sqrt(max(0, (trace + sqrt(discriminant)) / 2))
        let smallest = sqrt(max(0, (trace - sqrt(discriminant)) / 2))
        let residual = max(abs(a * b + c * d), abs((a * a + c * c) - (b * b + d * d)))
            / max(1, largest * largest)
        let minimum = Double(policy.minimumSingularValueScaled) / scale
        let maximumRatio = Double(policy.maximumSingularValueRatioScaled) / scale
        let maximumResidual = Double(policy.maximumSimilarityResidualScaled) / scale
        guard [a, b, c, d, trace, determinant, largest, smallest, residual].allSatisfy(\.isFinite),
              determinant > 0, smallest >= minimum, largest / smallest <= maximumRatio,
              residual <= maximumResidual else { return nil }
        let x = sin(radians), y = -cos(radians)
        let tx = a * x + b * y
        let ty = c * x + d * y
        guard tx.isFinite, ty.isFinite, hypot(tx, ty) >= 1.0e-9 else { return nil }
        // The inherited C37 transform contract deliberately uses IEEE-754
        // atan2 at this boundary. Only the final milli-degree value is stored,
        // using explicit nearest-ties-to-even rounding for deterministic edges.
        let degrees = atan2(tx, -ty) * 180_000.0 / .pi
        guard degrees.isFinite, degrees >= Double(Int32.min), degrees <= Double(Int32.max) else { throw PlacementPoseFailureV1.arithmeticOverflow }
        let rounded = Int64(degrees.rounded(.toNearestOrEven)); let normalized = ((rounded % 360_000) + 360_000) % 360_000
        return Int32(normalized)
    }
}

enum PlacementPoseEditorInputModeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case manual = "MANUAL"; case offlineFallback = "OFFLINE_FALLBACK"
}

enum PlacementPoseEditorCommandV1: Codable, Equatable, Sendable {
    case setObserved(axisID: PoseAxisID, pose: PlacementPoseV1)
    case setNotObserved(axisID: PoseAxisID, reason: PoseNotObservedReasonV1)
    case acceptDeviceProposal(DeviceHeadingProposalV1)
    case discardDeviceProposal
}

struct PlacementPoseEditorStateV1: Codable, Equatable, Sendable {
    let contract: PlacementPoseEditorContractV1
    let valuesByAxis: [PoseAxisID: PlacementPoseV1]
    let pendingDeviceProposal: DeviceHeadingProposalV1?
    let isDirty: Bool
    init(contract: PlacementPoseEditorContractV1,
         valuesByAxis: [PoseAxisID: PlacementPoseV1] = [:],
         pendingDeviceProposal: DeviceHeadingProposalV1? = nil,
         isDirty: Bool = false) throws {
        let descriptorIDs = Set(contract.descriptors.map(\.axisID))
        guard Set(valuesByAxis.keys).isSubset(of: descriptorIDs),
              pendingDeviceProposal.map({ $0.workspaceID == contract.workspaceID &&
                  $0.assetID == contract.assetID && descriptorIDs.contains($0.axisID) }) ?? true else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        for (axisID, pose) in valuesByAxis {
            guard let descriptor = contract.descriptors.first(where: { $0.axisID == axisID }) else {
                throw PlacementPoseFailureV1.referenceMismatch
            }
            try pose.validate(descriptor: descriptor)
        }
        self.contract = contract; self.valuesByAxis = valuesByAxis
        self.pendingDeviceProposal = pendingDeviceProposal; self.isDirty = isDirty
    }
}

struct PlacementPoseEditorContractV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let assetID: UUID; let placementEpisodeID: PhysicalPlacementEpisodeIDV1
    let descriptors: [PoseAxisDescriptorV1]; let inputMode: PlacementPoseEditorInputModeV1
    let allowsSensorInput: Bool; let allowsNetworkInput: Bool
    init(workspaceID: WorkspaceID, assetID: UUID, placementEpisodeID: PhysicalPlacementEpisodeIDV1,
         descriptors: [PoseAxisDescriptorV1], inputMode: PlacementPoseEditorInputModeV1) throws {
        try PlacementPoseLimitsV1.id(assetID); _ = try PoseAxisDescriptorRegistryV1(descriptors: descriptors)
        self.workspaceID = workspaceID; self.assetID = assetID; self.placementEpisodeID = placementEpisodeID
        self.descriptors = descriptors.sorted(); self.inputMode = inputMode
        allowsSensorInput = false; allowsNetworkInput = false
    }
}

struct CompletedPlacementPoseSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let assetID: UUID
    let placementEpisodeID: PhysicalPlacementEpisodeIDV1; let events: [AssetPoseEventV1]
    let eventReferences: [AssetPoseEventReferenceV1]
    let capturedAt: Date; let snapshotSHA256: String
    init(snapshotID: UUID, workspaceID: WorkspaceID, assetID: UUID,
         placementEpisodeID: PhysicalPlacementEpisodeIDV1, events: [AssetPoseEventV1], capturedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.snapshotID = snapshotID; self.workspaceID = workspaceID; self.assetID = assetID
        self.placementEpisodeID = placementEpisodeID
        self.events = events.sorted { $0.axisDescriptor.axisID < $1.axisDescriptor.axisID }
        eventReferences = self.events.map(\.reference); self.capturedAt = capturedAt
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID, assetID: assetID, placementEpisodeID: placementEpisodeID, events: self.events, eventReferences: eventReferences, capturedAt: capturedAt))
        try validate(events: events)
    }
    func validate(events: [AssetPoseEventV1]) throws {
        try PlacementPoseLimitsV1.id(snapshotID); try PlacementPoseLimitsV1.id(assetID)
        try events.forEach { try $0.validateIntrinsic() }
        guard schemaVersion == Self.schemaVersion, events.allSatisfy({ $0.workspaceID == workspaceID && $0.assetID == assetID && $0.placementEpisodeID == placementEpisodeID }),
              events.allSatisfy({ $0.axisDescriptor.observationRequirement == .optional || $0.pose.disposition == .observed }),
              eventReferences == events.map(\.reference).sorted(by: { $0.axisID < $1.axisID }),
              self.events == events.sorted(by: { $0.axisDescriptor.axisID < $1.axisDescriptor.axisID }),
              Set(eventReferences.map(\.axisID)).count == eventReferences.count,
              snapshotSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID, assetID: assetID, placementEpisodeID: placementEpisodeID, events: self.events, eventReferences: eventReferences, capturedAt: capturedAt))) else { throw PlacementPoseFailureV1.referenceMismatch }
    }
    private struct Basis: Codable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let assetID: UUID; let placementEpisodeID: PhysicalPlacementEpisodeIDV1; let events: [AssetPoseEventV1]; let eventReferences: [AssetPoseEventReferenceV1]; let capturedAt: Date }
}

enum PlacementPoseCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        switch value {
        case let event as AssetPoseEventV1: try event.validateIntrinsic()
        case let observation as SpatialAnchorObservationV1: try observation.validateIntrinsic()
        case let descriptor as PoseAxisDescriptorV1: try descriptor.validate()
        case let registry as PoseAxisDescriptorRegistryV1: try registry.validate()
        case let policy as PoseFrameRebasePolicyV1: try policy.validate()
        case let snapshot as CompletedPlacementPoseSnapshotV1: try snapshot.validate(events: snapshot.events)
        default: break
        }
        return value
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Pose_PlacementPoseContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift", role: .pose)
}

enum C31LightingPoseBoundaryV1 {
    static let poseIsAPlacementReferenceNotLightingProof = true
    static let uncertaintyRemainsRecorded = true
    static let poseDoesNotInferOrientationOrControlState = true
}
