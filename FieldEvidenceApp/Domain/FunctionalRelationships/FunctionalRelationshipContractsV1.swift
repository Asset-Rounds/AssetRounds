import Foundation

enum FunctionalRelationshipFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, digestMismatch, duplicateIdentity
    case unknownDescriptor, incompatibleEndpoint, crossWorkspace, crossSite
    case selfEdgeDenied, cardinalityExceeded, cycleDetected, traversalBoundExceeded
    case invalidTransition, staleRevision, incomplete, nonCanonicalData
}

extension CompletedFunctionalRelationshipSnapshotV1 {
    func inspectionReviewEvidenceReference() throws -> ReviewEvidenceReferenceV1 {
        try validate()
        return try .init(kind: .functionalRelationshipSnapshot,
                         referenceID: snapshotID.uuidString.lowercased(),
                         revision: UInt64(Self.schemaVersion), sha256: snapshotSHA256)
    }
}

enum FunctionalRelationshipLimitsV1 {
    static let maximumDescriptors = 256
    static let maximumEvents = 20_000
    static let maximumCurrentRelationships = 10_000
    static let maximumEndpointKinds = 64
    static let maximumCapabilities = 64
    static let maximumCardinality = 10_000
    static let maximumTraversalDepth = 64
    static let maximumHardEdges = 10_000
    static let maximumLocalizationKeyBytes = 240
    static let maximumProvenanceBytes = 1_024
    static let zeroUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

enum FunctionalRelationshipDirectionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case directed = "DIRECTED"
    case undirected = "UNDIRECTED"
}

enum FunctionalRelationshipSymmetryV1: String, Codable, CaseIterable, Hashable, Sendable {
    case asymmetric = "ASYMMETRIC"
    case symmetric = "SYMMETRIC"
}

enum FunctionalRelationshipSelfEdgePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case forbidden = "FORBIDDEN"
    case allowed = "ALLOWED"
}

enum FunctionalRelationshipCyclePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case forbidden = "FORBIDDEN"
    case bounded = "BOUNDED"
}

enum FunctionalRelationshipSitePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case sameSiteRequired = "SAME_SITE_REQUIRED"
    case crossSiteLocalAllowed = "CROSS_SITE_LOCAL_ALLOWED"
}

enum FunctionalRelationshipWorkspacePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case sameWorkspaceRequired = "SAME_WORKSPACE_REQUIRED"
}

enum FunctionalRelationshipReadinessBoundaryV1: String, Codable, CaseIterable, Hashable, Sendable {
    case atomicCreationBundle = "ATOMIC_CREATION_BUNDLE"
    case readiness = "READINESS"
    case finalization = "FINALIZATION"
}

struct FunctionalRelationshipCardinalityV1: Codable, Equatable, Hashable, Sendable {
    let minimum: Int
    let maximum: Int

    init(minimum: Int, maximum: Int) throws {
        guard minimum >= 0, maximum >= minimum,
              maximum <= FunctionalRelationshipLimitsV1.maximumCardinality else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
        self.minimum = minimum
        self.maximum = maximum
    }
}

struct FunctionalRelationshipTypeDescriptorV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let descriptorReleaseID: UUID
    let workspaceID: WorkspaceID
    let packageRelease: PackageReleaseIdentityV1
    let semanticID: String
    let sourceCatalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let targetCatalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let sourceSemanticIDs: [String]
    let targetSemanticIDs: [String]
    let requiredSourceCapabilityIDs: [AssetSemanticCapabilityIDV1]
    let requiredTargetCapabilityIDs: [AssetSemanticCapabilityIDV1]
    let direction: FunctionalRelationshipDirectionV1
    let symmetry: FunctionalRelationshipSymmetryV1
    let sourceCardinality: FunctionalRelationshipCardinalityV1
    let targetCardinality: FunctionalRelationshipCardinalityV1
    let selfEdgePolicy: FunctionalRelationshipSelfEdgePolicyV1
    let cyclePolicy: FunctionalRelationshipCyclePolicyV1
    let maximumTraversalDepth: Int
    let maximumHardEdges: Int
    let sitePolicy: FunctionalRelationshipSitePolicyV1
    let workspacePolicy: FunctionalRelationshipWorkspacePolicyV1
    let minimumCardinalityBoundaries: [FunctionalRelationshipReadinessBoundaryV1]
    let displayNameLocalizationKey: String
    let descriptionLocalizationKey: String?
    let sourceRoleLocalizationKey: String
    let targetRoleLocalizationKey: String
    let releasedAt: Date
    let supersedesDescriptorReleaseID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let descriptorSHA256: String

    init(
        descriptorReleaseID: UUID, workspaceID: WorkspaceID,
        packageRelease: PackageReleaseIdentityV1, semanticID: String,
        sourceCatalogRelease: AssetSemanticCatalogReleaseReferenceV1,
        targetCatalogRelease: AssetSemanticCatalogReleaseReferenceV1,
        sourceSemanticIDs: [String], targetSemanticIDs: [String],
        requiredSourceCapabilityIDs: [AssetSemanticCapabilityIDV1] = [],
        requiredTargetCapabilityIDs: [AssetSemanticCapabilityIDV1] = [],
        direction: FunctionalRelationshipDirectionV1,
        symmetry: FunctionalRelationshipSymmetryV1,
        sourceCardinality: FunctionalRelationshipCardinalityV1,
        targetCardinality: FunctionalRelationshipCardinalityV1,
        selfEdgePolicy: FunctionalRelationshipSelfEdgePolicyV1,
        cyclePolicy: FunctionalRelationshipCyclePolicyV1,
        maximumTraversalDepth: Int, maximumHardEdges: Int,
        sitePolicy: FunctionalRelationshipSitePolicyV1,
        workspacePolicy: FunctionalRelationshipWorkspacePolicyV1 = .sameWorkspaceRequired,
        minimumCardinalityBoundaries: [FunctionalRelationshipReadinessBoundaryV1],
        displayNameLocalizationKey: String, descriptionLocalizationKey: String? = nil,
        sourceRoleLocalizationKey: String, targetRoleLocalizationKey: String,
        releasedAt: Date, supersedesDescriptorReleaseID: UUID? = nil,
        revision: UInt64 = 1,
        mutationID: MutationIDV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.descriptorReleaseID = descriptorReleaseID; self.workspaceID = workspaceID
        self.packageRelease = packageRelease; self.semanticID = semanticID
        self.sourceCatalogRelease = sourceCatalogRelease; self.targetCatalogRelease = targetCatalogRelease
        self.sourceSemanticIDs = sourceSemanticIDs.sorted(); self.targetSemanticIDs = targetSemanticIDs.sorted()
        self.requiredSourceCapabilityIDs = requiredSourceCapabilityIDs.sorted()
        self.requiredTargetCapabilityIDs = requiredTargetCapabilityIDs.sorted()
        self.direction = direction; self.symmetry = symmetry
        self.sourceCardinality = sourceCardinality; self.targetCardinality = targetCardinality
        self.selfEdgePolicy = selfEdgePolicy; self.cyclePolicy = cyclePolicy
        self.maximumTraversalDepth = maximumTraversalDepth; self.maximumHardEdges = maximumHardEdges
        self.sitePolicy = sitePolicy; self.workspacePolicy = workspacePolicy
        self.minimumCardinalityBoundaries = minimumCardinalityBoundaries.sorted { $0.rawValue < $1.rawValue }
        self.displayNameLocalizationKey = displayNameLocalizationKey
        self.descriptionLocalizationKey = descriptionLocalizationKey
        self.sourceRoleLocalizationKey = sourceRoleLocalizationKey
        self.targetRoleLocalizationKey = targetRoleLocalizationKey
        self.releasedAt = releasedAt; self.supersedesDescriptorReleaseID = supersedesDescriptorReleaseID
        self.revision = revision; self.mutationID = mutationID
        descriptorSHA256 = try FunctionalRelationshipCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, descriptorReleaseID: descriptorReleaseID,
            workspaceID: workspaceID, packageRelease: packageRelease, semanticID: semanticID,
            sourceCatalogRelease: sourceCatalogRelease, targetCatalogRelease: targetCatalogRelease,
            sourceSemanticIDs: self.sourceSemanticIDs, targetSemanticIDs: self.targetSemanticIDs,
            requiredSourceCapabilityIDs: self.requiredSourceCapabilityIDs,
            requiredTargetCapabilityIDs: self.requiredTargetCapabilityIDs,
            direction: direction, symmetry: symmetry, sourceCardinality: sourceCardinality,
            targetCardinality: targetCardinality, selfEdgePolicy: selfEdgePolicy,
            cyclePolicy: cyclePolicy, maximumTraversalDepth: maximumTraversalDepth,
            maximumHardEdges: maximumHardEdges, sitePolicy: sitePolicy, workspacePolicy: workspacePolicy,
            minimumCardinalityBoundaries: self.minimumCardinalityBoundaries,
            displayNameLocalizationKey: displayNameLocalizationKey,
            descriptionLocalizationKey: descriptionLocalizationKey,
            sourceRoleLocalizationKey: sourceRoleLocalizationKey,
            targetRoleLocalizationKey: targetRoleLocalizationKey, releasedAt: releasedAt,
            supersedesDescriptorReleaseID: supersedesDescriptorReleaseID,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, descriptorReleaseID != FunctionalRelationshipLimitsV1.zeroUUID,
              revision > 0, supersedesDescriptorReleaseID != descriptorReleaseID,
              (supersedesDescriptorReleaseID == nil) == (revision == 1),
              AssetSemanticValidationV1.validPackageRelease(packageRelease),
              AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160),
              !sourceSemanticIDs.isEmpty, !targetSemanticIDs.isEmpty,
              sourceSemanticIDs.count <= FunctionalRelationshipLimitsV1.maximumEndpointKinds,
              targetSemanticIDs.count <= FunctionalRelationshipLimitsV1.maximumEndpointKinds,
              sourceSemanticIDs == sourceSemanticIDs.sorted(), targetSemanticIDs == targetSemanticIDs.sorted(),
              Set(sourceSemanticIDs).count == sourceSemanticIDs.count,
              Set(targetSemanticIDs).count == targetSemanticIDs.count,
              sourceSemanticIDs.allSatisfy({ AssetSemanticValidationV1.validIdentifier($0, maximumBytes: 160) }),
              targetSemanticIDs.allSatisfy({ AssetSemanticValidationV1.validIdentifier($0, maximumBytes: 160) }),
              requiredSourceCapabilityIDs.count <= FunctionalRelationshipLimitsV1.maximumCapabilities,
              requiredTargetCapabilityIDs.count <= FunctionalRelationshipLimitsV1.maximumCapabilities,
              Set(requiredSourceCapabilityIDs).count == requiredSourceCapabilityIDs.count,
              Set(requiredTargetCapabilityIDs).count == requiredTargetCapabilityIDs.count,
              requiredSourceCapabilityIDs == requiredSourceCapabilityIDs.sorted(),
              requiredTargetCapabilityIDs == requiredTargetCapabilityIDs.sorted(),
              (direction == .undirected) == (symmetry == .symmetric),
              maximumTraversalDepth > 0, maximumTraversalDepth <= FunctionalRelationshipLimitsV1.maximumTraversalDepth,
              maximumHardEdges > 0, maximumHardEdges <= FunctionalRelationshipLimitsV1.maximumHardEdges,
              workspacePolicy == .sameWorkspaceRequired,
              minimumCardinalityBoundaries == minimumCardinalityBoundaries.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(minimumCardinalityBoundaries).count == minimumCardinalityBoundaries.count,
              symmetry != .symmetric || (
                sourceCatalogRelease == targetCatalogRelease
                    && sourceSemanticIDs == targetSemanticIDs
                    && requiredSourceCapabilityIDs == requiredTargetCapabilityIDs
                    && sourceCardinality == targetCardinality
              ),
              validLocalizationKey(displayNameLocalizationKey), validLocalizationKey(sourceRoleLocalizationKey),
              validLocalizationKey(targetRoleLocalizationKey),
              descriptionLocalizationKey.map(validLocalizationKey) ?? true else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
        try sourceCatalogRelease.validate(); try targetCatalogRelease.validate()
        guard descriptorSHA256 == (try FunctionalRelationshipCanonicalCodecV1.sha256(digestBasis)) else {
            throw FunctionalRelationshipFailureV1.digestMismatch
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try validate();try predecessor.validate()
        guard supersedesDescriptorReleaseID==predecessor.descriptorReleaseID,
              descriptorReleaseID != predecessor.descriptorReleaseID,
              workspaceID==predecessor.workspaceID,semanticID==predecessor.semanticID,
              predecessor.revision<UInt64.max,revision==predecessor.revision+1,
              releasedAt>=predecessor.releasedAt,mutationID != predecessor.mutationID else {
            throw FunctionalRelationshipFailureV1.invalidTransition
        }
    }

    func validate(sourceCatalog: AssetSemanticCatalogReleaseV1, targetCatalog: AssetSemanticCatalogReleaseV1) throws {
        try validate(); try sourceCatalog.validate(); try targetCatalog.validate()
        guard sourceCatalog.reference == sourceCatalogRelease,
              targetCatalog.reference == targetCatalogRelease else {
            throw FunctionalRelationshipFailureV1.unknownDescriptor
        }
        for semanticID in sourceSemanticIDs { _ = try sourceCatalog.definition(semanticID: semanticID) }
        for semanticID in targetSemanticIDs { _ = try targetCatalog.definition(semanticID: semanticID) }
        for semanticID in sourceSemanticIDs {
            let capabilities = Set(try sourceCatalog.definition(semanticID: semanticID).capabilityIDs)
            guard Set(requiredSourceCapabilityIDs).isSubset(of: capabilities) else {
                throw FunctionalRelationshipFailureV1.incompatibleEndpoint
            }
        }
        for semanticID in targetSemanticIDs {
            let capabilities = Set(try targetCatalog.definition(semanticID: semanticID).capabilityIDs)
            guard Set(requiredTargetCapabilityIDs).isSubset(of: capabilities) else {
                throw FunctionalRelationshipFailureV1.incompatibleEndpoint
            }
        }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(descriptorReleaseID: descriptorReleaseID, workspaceID: workspaceID,
            packageRelease: packageRelease, semanticID: semanticID,
            sourceCatalogRelease: sourceCatalogRelease, targetCatalogRelease: targetCatalogRelease,
            sourceSemanticIDs: sourceSemanticIDs, targetSemanticIDs: targetSemanticIDs,
            requiredSourceCapabilityIDs: requiredSourceCapabilityIDs,
            requiredTargetCapabilityIDs: requiredTargetCapabilityIDs, direction: direction, symmetry: symmetry,
            sourceCardinality: sourceCardinality, targetCardinality: targetCardinality,
            selfEdgePolicy: selfEdgePolicy, cyclePolicy: cyclePolicy,
            maximumTraversalDepth: maximumTraversalDepth, maximumHardEdges: maximumHardEdges,
            sitePolicy: sitePolicy, workspacePolicy: workspacePolicy,
            minimumCardinalityBoundaries: minimumCardinalityBoundaries,
            displayNameLocalizationKey: displayNameLocalizationKey,
            descriptionLocalizationKey: descriptionLocalizationKey,
            sourceRoleLocalizationKey: sourceRoleLocalizationKey,
            targetRoleLocalizationKey: targetRoleLocalizationKey, releasedAt: releasedAt,
            supersedesDescriptorReleaseID: supersedesDescriptorReleaseID,
            revision: revision, mutationID: mutationID)
    }

    private var digestBasis: DigestBasis { DigestBasis(schemaVersion: schemaVersion,
        descriptorReleaseID: descriptorReleaseID, workspaceID: workspaceID, packageRelease: packageRelease,
        semanticID: semanticID, sourceCatalogRelease: sourceCatalogRelease, targetCatalogRelease: targetCatalogRelease,
        sourceSemanticIDs: sourceSemanticIDs, targetSemanticIDs: targetSemanticIDs,
        requiredSourceCapabilityIDs: requiredSourceCapabilityIDs,
        requiredTargetCapabilityIDs: requiredTargetCapabilityIDs, direction: direction, symmetry: symmetry,
        sourceCardinality: sourceCardinality, targetCardinality: targetCardinality,
        selfEdgePolicy: selfEdgePolicy, cyclePolicy: cyclePolicy,
        maximumTraversalDepth: maximumTraversalDepth, maximumHardEdges: maximumHardEdges,
        sitePolicy: sitePolicy, workspacePolicy: workspacePolicy,
        minimumCardinalityBoundaries: minimumCardinalityBoundaries,
        displayNameLocalizationKey: displayNameLocalizationKey,
        descriptionLocalizationKey: descriptionLocalizationKey,
        sourceRoleLocalizationKey: sourceRoleLocalizationKey, targetRoleLocalizationKey: targetRoleLocalizationKey,
        releasedAt: releasedAt, supersedesDescriptorReleaseID: supersedesDescriptorReleaseID,
        revision: revision, mutationID: mutationID) }
    private struct DigestBasis: Codable { let schemaVersion:Int; let descriptorReleaseID:UUID; let workspaceID:WorkspaceID; let packageRelease:PackageReleaseIdentityV1; let semanticID:String; let sourceCatalogRelease:AssetSemanticCatalogReleaseReferenceV1; let targetCatalogRelease:AssetSemanticCatalogReleaseReferenceV1; let sourceSemanticIDs:[String]; let targetSemanticIDs:[String]; let requiredSourceCapabilityIDs:[AssetSemanticCapabilityIDV1]; let requiredTargetCapabilityIDs:[AssetSemanticCapabilityIDV1]; let direction:FunctionalRelationshipDirectionV1; let symmetry:FunctionalRelationshipSymmetryV1; let sourceCardinality:FunctionalRelationshipCardinalityV1; let targetCardinality:FunctionalRelationshipCardinalityV1; let selfEdgePolicy:FunctionalRelationshipSelfEdgePolicyV1; let cyclePolicy:FunctionalRelationshipCyclePolicyV1; let maximumTraversalDepth:Int; let maximumHardEdges:Int; let sitePolicy:FunctionalRelationshipSitePolicyV1; let workspacePolicy:FunctionalRelationshipWorkspacePolicyV1; let minimumCardinalityBoundaries:[FunctionalRelationshipReadinessBoundaryV1]; let displayNameLocalizationKey:String; let descriptionLocalizationKey:String?; let sourceRoleLocalizationKey:String; let targetRoleLocalizationKey:String; let releasedAt:Date; let supersedesDescriptorReleaseID:UUID?; let revision:UInt64; let mutationID:MutationIDV1 }
}

enum AssetFunctionalRelationshipEventActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case added = "ADDED"; case ended = "ENDED"; case superseded = "SUPERSEDED"
}

struct FunctionalRelationshipDescriptorReferenceV1: Codable, Equatable, Hashable, Sendable {
    let descriptorReleaseID: UUID; let revision: UInt64; let descriptorSHA256: String
    let packageRelease: PackageReleaseIdentityV1; let semanticID: String
    init(_ descriptor: FunctionalRelationshipTypeDescriptorV1) {
        descriptorReleaseID=descriptor.descriptorReleaseID; revision=descriptor.revision
        descriptorSHA256=descriptor.descriptorSHA256; packageRelease=descriptor.packageRelease
        semanticID=descriptor.semanticID
    }
    func validate() throws { guard descriptorReleaseID != FunctionalRelationshipLimitsV1.zeroUUID,
        revision > 0, AssetSemanticValidationV1.validSHA256(descriptorSHA256),
        AssetSemanticValidationV1.validPackageRelease(packageRelease),
        AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160) else {
        throw FunctionalRelationshipFailureV1.invalidValue } }
}

struct FunctionalRelationshipEndpointSnapshotV1: Codable, Equatable, Hashable, Sendable {
    let assetID: UUID
    let workspaceID: WorkspaceID
    let siteID: UUID
    let assetRevision: UInt64
    let kindBindingEventID: UUID
    let kindBindingRevision: UInt64
    let catalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let semanticID: String
    let capabilityIDs: [AssetSemanticCapabilityIDV1]

    init(assetID: UUID, workspaceID: WorkspaceID, siteID: UUID, assetRevision: UInt64,
         kindBindingEventID: UUID, kindBindingRevision: UInt64,
         catalogRelease: AssetSemanticCatalogReleaseReferenceV1, semanticID: String,
         capabilityIDs: [AssetSemanticCapabilityIDV1]) throws {
        self.assetID=assetID;self.workspaceID=workspaceID;self.siteID=siteID
        self.assetRevision=assetRevision;self.kindBindingEventID=kindBindingEventID
        self.kindBindingRevision=kindBindingRevision;self.catalogRelease=catalogRelease
        self.semanticID=semanticID;self.capabilityIDs=capabilityIDs.sorted();try validate()
    }
    func validate() throws {
        try catalogRelease.validate()
        guard assetID != FunctionalRelationshipLimitsV1.zeroUUID,
              siteID != FunctionalRelationshipLimitsV1.zeroUUID,
              assetRevision>0,kindBindingEventID != FunctionalRelationshipLimitsV1.zeroUUID,
              kindBindingRevision>0,AssetSemanticValidationV1.validIdentifier(semanticID,maximumBytes:160),
              capabilityIDs.count<=FunctionalRelationshipLimitsV1.maximumCapabilities,
              capabilityIDs==capabilityIDs.sorted(),Set(capabilityIDs).count==capabilityIDs.count else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
    }
}

struct AssetFunctionalRelationshipEventV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int; let eventID:UUID; let relationshipID:UUID; let workspaceID:WorkspaceID
    let action:AssetFunctionalRelationshipEventActionV1; let sourceAssetID:UUID; let targetAssetID:UUID
    let sourceAssetRevision:UInt64; let targetAssetRevision:UInt64
    let descriptor:FunctionalRelationshipDescriptorReferenceV1
    let effectiveAt:Date; let recordedAt:Date; let actor:LocalActorReferenceV1; let provenance:String
    let predecessorEventID:UUID?; let expectedRelationshipRevision:UInt64
    let revision:UInt64; let mutationID:MutationIDV1; let eventSHA256:String
    init(eventID:UUID, relationshipID:UUID, workspaceID:WorkspaceID,
         action:AssetFunctionalRelationshipEventActionV1, sourceAssetID:UUID, targetAssetID:UUID,
         sourceAssetRevision:UInt64, targetAssetRevision:UInt64,
         descriptor:FunctionalRelationshipDescriptorReferenceV1,
         effectiveAt:Date, recordedAt:Date, actor:LocalActorReferenceV1, provenance:String,
         predecessorEventID:UUID?=nil, expectedRelationshipRevision:UInt64,
         revision:UInt64, mutationID:MutationIDV1) throws {
        schemaVersion=Self.schemaVersion; self.eventID=eventID; self.relationshipID=relationshipID; self.workspaceID=workspaceID
        self.action=action; self.sourceAssetID=sourceAssetID; self.targetAssetID=targetAssetID
        self.sourceAssetRevision=sourceAssetRevision; self.targetAssetRevision=targetAssetRevision; self.descriptor=descriptor
        self.effectiveAt=effectiveAt; self.recordedAt=recordedAt; self.actor=actor; self.provenance=provenance
        self.predecessorEventID=predecessorEventID; self.expectedRelationshipRevision=expectedRelationshipRevision
        self.revision=revision; self.mutationID=mutationID
        eventSHA256=try FunctionalRelationshipCanonicalCodecV1.sha256(DigestBasis(schemaVersion:Self.schemaVersion,eventID:eventID,relationshipID:relationshipID,workspaceID:workspaceID,action:action,sourceAssetID:sourceAssetID,targetAssetID:targetAssetID,sourceAssetRevision:sourceAssetRevision,targetAssetRevision:targetAssetRevision,descriptor:descriptor,effectiveAt:effectiveAt,recordedAt:recordedAt,actor:actor,provenance:provenance,predecessorEventID:predecessorEventID,expectedRelationshipRevision:expectedRelationshipRevision,revision:revision,mutationID:mutationID)); try validate()
    }
    func validate() throws {
        try descriptor.validate(); try actor.validate()
        let isAdd=action == .added
        guard schemaVersion==Self.schemaVersion, eventID != FunctionalRelationshipLimitsV1.zeroUUID,
              relationshipID != FunctionalRelationshipLimitsV1.zeroUUID,
              sourceAssetID != FunctionalRelationshipLimitsV1.zeroUUID,
              targetAssetID != FunctionalRelationshipLimitsV1.zeroUUID,
              sourceAssetRevision>0,targetAssetRevision>0,actor.workspaceID==workspaceID,
              !provenance.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              provenance.utf8.count<=FunctionalRelationshipLimitsV1.maximumProvenanceBytes,
              recordedAt>=effectiveAt,
              isAdd == (predecessorEventID == nil),
              (isAdd ? expectedRelationshipRevision==0 : expectedRelationshipRevision>0),
              expectedRelationshipRevision < UInt64.max, revision==expectedRelationshipRevision+1,
              eventSHA256==(try FunctionalRelationshipCanonicalCodecV1.sha256(digestBasis)) else { throw FunctionalRelationshipFailureV1.invalidValue }
    }
    func validateSuccessor(of predecessor: Self) throws {
        try validate();try predecessor.validate()
        guard predecessor.action != .ended,action != .added,
              workspaceID==predecessor.workspaceID,relationshipID==predecessor.relationshipID,
              predecessorEventID==predecessor.eventID,
              expectedRelationshipRevision==predecessor.revision,
              predecessor.revision < UInt64.max,revision==predecessor.revision+1,
              effectiveAt>=predecessor.effectiveAt,recordedAt>=predecessor.recordedAt,
              mutationID != predecessor.mutationID else {
            throw FunctionalRelationshipFailureV1.invalidTransition
        }
    }
    func rebound(to workspaceID:WorkspaceID) throws -> Self { let reboundActor=try LocalActorReferenceV1(actorReferenceID:actor.actorReferenceID,workspaceID:workspaceID,partyID:actor.partyID,displayName:actor.displayName); return try Self(eventID:eventID,relationshipID:relationshipID,workspaceID:workspaceID,action:action,sourceAssetID:sourceAssetID,targetAssetID:targetAssetID,sourceAssetRevision:sourceAssetRevision,targetAssetRevision:targetAssetRevision,descriptor:descriptor,effectiveAt:effectiveAt,recordedAt:recordedAt,actor:reboundActor,provenance:provenance,predecessorEventID:predecessorEventID,expectedRelationshipRevision:expectedRelationshipRevision,revision:revision,mutationID:mutationID) }
    private var digestBasis:DigestBasis { DigestBasis(schemaVersion:schemaVersion,eventID:eventID,relationshipID:relationshipID,workspaceID:workspaceID,action:action,sourceAssetID:sourceAssetID,targetAssetID:targetAssetID,sourceAssetRevision:sourceAssetRevision,targetAssetRevision:targetAssetRevision,descriptor:descriptor,effectiveAt:effectiveAt,recordedAt:recordedAt,actor:actor,provenance:provenance,predecessorEventID:predecessorEventID,expectedRelationshipRevision:expectedRelationshipRevision,revision:revision,mutationID:mutationID) }
    private struct DigestBasis:Codable { let schemaVersion:Int;let eventID:UUID;let relationshipID:UUID;let workspaceID:WorkspaceID;let action:AssetFunctionalRelationshipEventActionV1;let sourceAssetID:UUID;let targetAssetID:UUID;let sourceAssetRevision:UInt64;let targetAssetRevision:UInt64;let descriptor:FunctionalRelationshipDescriptorReferenceV1;let effectiveAt:Date;let recordedAt:Date;let actor:LocalActorReferenceV1;let provenance:String;let predecessorEventID:UUID?;let expectedRelationshipRevision:UInt64;let revision:UInt64;let mutationID:MutationIDV1 }
}

enum FunctionalRelationshipReadinessStateV1:String,Codable,CaseIterable,Hashable,Sendable { case ready="READY";case incomplete="INCOMPLETE" }
struct FunctionalRelationshipReadinessRequirementV1:Codable,Equatable,Hashable,Sendable { let assetID:UUID;let descriptorReleaseID:UUID;let role:String;let minimum:Int;let actual:Int }

struct CurrentFunctionalRelationshipProjectionV1:Codable,Equatable,Hashable,Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let workspaceID:WorkspaceID;let throughRecordedAt:Date
    let currentRelationships:[AssetFunctionalRelationshipEventV1]
    let readiness:FunctionalRelationshipReadinessStateV1
    let readinessRequirements:[FunctionalRelationshipReadinessRequirementV1]
    let sourceEventsSHA256:String;let projectionSHA256:String
    init(workspaceID:WorkspaceID,throughRecordedAt:Date,currentRelationships:[AssetFunctionalRelationshipEventV1],readinessRequirements:[FunctionalRelationshipReadinessRequirementV1],sourceEventsSHA256:String) throws { schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.throughRecordedAt=throughRecordedAt;self.currentRelationships=currentRelationships.sorted{ $0.relationshipID.uuidString<$1.relationshipID.uuidString };self.readinessRequirements=readinessRequirements.sorted{ ($0.assetID.uuidString,$0.role)<($1.assetID.uuidString,$1.role) };readiness=self.readinessRequirements.isEmpty ? .ready:.incomplete;self.sourceEventsSHA256=sourceEventsSHA256;projectionSHA256=try FunctionalRelationshipCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,workspaceID:workspaceID,throughRecordedAt:throughRecordedAt,currentRelationships:self.currentRelationships,readiness:readiness,readinessRequirements:self.readinessRequirements,sourceEventsSHA256:sourceEventsSHA256));try validate() }
    func validate()throws{try currentRelationships.forEach{try $0.validate()};guard schemaVersion==Self.schemaVersion,currentRelationships.count<=FunctionalRelationshipLimitsV1.maximumCurrentRelationships,currentRelationships==currentRelationships.sorted(by:{$0.relationshipID.uuidString<$1.relationshipID.uuidString}),Set(currentRelationships.map(\.relationshipID)).count==currentRelationships.count,currentRelationships.allSatisfy{$0.workspaceID==workspaceID && $0.action != .ended},readiness==(readinessRequirements.isEmpty ? .ready:.incomplete),readinessRequirements.allSatisfy{$0.assetID != FunctionalRelationshipLimitsV1.zeroUUID && $0.descriptorReleaseID != FunctionalRelationshipLimitsV1.zeroUUID && ["SOURCE","TARGET","SYMMETRIC"].contains($0.role) && $0.minimum>0 && $0.actual>=0 && $0.actual<$0.minimum},AssetSemanticValidationV1.validSHA256(sourceEventsSHA256),projectionSHA256==(try FunctionalRelationshipCanonicalCodecV1.sha256(Basis(schemaVersion:schemaVersion,workspaceID:workspaceID,throughRecordedAt:throughRecordedAt,currentRelationships:currentRelationships,readiness:readiness,readinessRequirements:readinessRequirements,sourceEventsSHA256:sourceEventsSHA256)))else{throw FunctionalRelationshipFailureV1.digestMismatch}}
    func validate(descriptorReleases:[FunctionalRelationshipTypeDescriptorV1])throws{
        try validate();try descriptorReleases.forEach{try $0.validate()}
        guard Set(descriptorReleases.map(\.descriptorReleaseID)).count==descriptorReleases.count,
              descriptorReleases.allSatisfy({$0.workspaceID==workspaceID}) else {
            throw FunctionalRelationshipFailureV1.duplicateIdentity
        }
        let descriptors=Dictionary(uniqueKeysWithValues:descriptorReleases.map{($0.descriptorReleaseID,$0)})
        try FunctionalRelationshipProjectionBuilderV1.validateTopology(currentRelationships,descriptors:descriptors)
    }
    private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let throughRecordedAt:Date;let currentRelationships:[AssetFunctionalRelationshipEventV1];let readiness:FunctionalRelationshipReadinessStateV1;let readinessRequirements:[FunctionalRelationshipReadinessRequirementV1];let sourceEventsSHA256:String}
}

enum FunctionalRelationshipProjectionBuilderV1 {
    static func validateCandidate(
        _ candidate: AssetFunctionalRelationshipEventV1,
        source: FunctionalRelationshipEndpointSnapshotV1,
        target: FunctionalRelationshipEndpointSnapshotV1,
        descriptor: FunctionalRelationshipTypeDescriptorV1,
        existingCurrent: [AssetFunctionalRelationshipEventV1]
    ) throws {
        try candidate.validate();try source.validate();try target.validate();try descriptor.validate()
        guard candidate.workspaceID==descriptor.workspaceID,
              source.workspaceID==candidate.workspaceID,target.workspaceID==candidate.workspaceID else {
            throw FunctionalRelationshipFailureV1.crossWorkspace
        }
        guard candidate.sourceAssetID==source.assetID,candidate.targetAssetID==target.assetID,
              candidate.sourceAssetRevision==source.assetRevision,candidate.targetAssetRevision==target.assetRevision,
              candidate.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor),
              source.catalogRelease==descriptor.sourceCatalogRelease,
              target.catalogRelease==descriptor.targetCatalogRelease,
              descriptor.sourceSemanticIDs.contains(source.semanticID),
              descriptor.targetSemanticIDs.contains(target.semanticID),
              Set(descriptor.requiredSourceCapabilityIDs).isSubset(of:Set(source.capabilityIDs)),
              Set(descriptor.requiredTargetCapabilityIDs).isSubset(of:Set(target.capabilityIDs)) else {
            throw FunctionalRelationshipFailureV1.incompatibleEndpoint
        }
        if descriptor.sitePolicy == .sameSiteRequired,source.siteID != target.siteID {
            throw FunctionalRelationshipFailureV1.crossSite
        }
        if descriptor.selfEdgePolicy == .forbidden,source.assetID==target.assetID {
            throw FunctionalRelationshipFailureV1.selfEdgeDenied
        }
        if candidate.action == .added {
            let duplicate=existingCurrent.contains { edge in
                guard edge.descriptor.descriptorReleaseID==descriptor.descriptorReleaseID else{return false}
                if edge.sourceAssetID==source.assetID && edge.targetAssetID==target.assetID{return true}
                return descriptor.symmetry == .symmetric
                    && edge.sourceAssetID==target.assetID && edge.targetAssetID==source.assetID
            }
            guard !duplicate else{throw FunctionalRelationshipFailureV1.duplicateIdentity}
        }
        // Topology constraints are descriptor-scoped. Existing relationships
        // owned by another descriptor must never be interpreted using the
        // candidate descriptor's direction/cardinality/cycle policy.
        let descriptorCurrent = existingCurrent.filter {
            $0.descriptor.descriptorReleaseID == descriptor.descriptorReleaseID
                && $0.relationshipID != candidate.relationshipID
        }
        let replacement = descriptorCurrent + [candidate]
        try validateTopology(
            replacement.filter { $0.action != .ended },
            descriptors: [descriptor.descriptorReleaseID: descriptor]
        )
    }

    static func rebuild(workspaceID:WorkspaceID,events:[AssetFunctionalRelationshipEventV1],descriptors:[FunctionalRelationshipTypeDescriptorV1],boundary:FunctionalRelationshipReadinessBoundaryV1?=nil)throws->CurrentFunctionalRelationshipProjectionV1{
        guard events.count<=FunctionalRelationshipLimitsV1.maximumEvents,descriptors.count<=FunctionalRelationshipLimitsV1.maximumDescriptors else{throw FunctionalRelationshipFailureV1.invalidValue}
        try events.forEach{try $0.validate()};try descriptors.forEach{try $0.validate()}
        guard Set(descriptors.map(\.descriptorReleaseID)).count==descriptors.count,
              descriptors.allSatisfy({$0.workspaceID==workspaceID}),
              events.allSatisfy({$0.workspaceID==workspaceID}) else{throw FunctionalRelationshipFailureV1.duplicateIdentity}
        let descriptorByID=Dictionary(uniqueKeysWithValues:descriptors.map{($0.descriptorReleaseID,$0)})
        guard events.allSatisfy({ event in
            guard let descriptor = descriptorByID[event.descriptor.descriptorReleaseID] else {
                return false
            }
            return event.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor)
                && descriptor.workspaceID == event.workspaceID
        }) else {
            throw FunctionalRelationshipFailureV1.unknownDescriptor
        }
        let groups=Dictionary(grouping:events,by:\.relationshipID);var current:[AssetFunctionalRelationshipEventV1]=[]
        for (_,history) in groups { let ordered=history.sorted{$0.revision<$1.revision};let expectedRevisions=ordered.indices.map{UInt64($0+1)};guard ordered.first?.action == .added,ordered.map(\.revision)==expectedRevisions else{throw FunctionalRelationshipFailureV1.invalidTransition};for pair in zip(ordered,ordered.dropFirst()){try pair.1.validateSuccessor(of:pair.0)};if let last=ordered.last,last.action != .ended{current.append(last)} }
        try validateTopology(current,descriptors:descriptorByID)
        var requirements:[FunctionalRelationshipReadinessRequirementV1]=[]
        if let boundary { for descriptor in descriptors where descriptor.minimumCardinalityBoundaries.contains(boundary){let edges=current.filter{$0.descriptor.descriptorReleaseID==descriptor.descriptorReleaseID};if descriptor.symmetry == .symmetric{for assetID in Set(edges.flatMap{[$0.sourceAssetID,$0.targetAssetID]}){let count=edges.filter{$0.sourceAssetID==assetID || $0.targetAssetID==assetID}.count;if count<descriptor.sourceCardinality.minimum{requirements.append(.init(assetID:assetID,descriptorReleaseID:descriptor.descriptorReleaseID,role:"SYMMETRIC",minimum:descriptor.sourceCardinality.minimum,actual:count))}}}else{for assetID in Set(edges.map(\.sourceAssetID)){let count=edges.filter{$0.sourceAssetID==assetID}.count;if count<descriptor.sourceCardinality.minimum{requirements.append(.init(assetID:assetID,descriptorReleaseID:descriptor.descriptorReleaseID,role:"SOURCE",minimum:descriptor.sourceCardinality.minimum,actual:count))}};for assetID in Set(edges.map(\.targetAssetID)){let count=edges.filter{$0.targetAssetID==assetID}.count;if count<descriptor.targetCardinality.minimum{requirements.append(.init(assetID:assetID,descriptorReleaseID:descriptor.descriptorReleaseID,role:"TARGET",minimum:descriptor.targetCardinality.minimum,actual:count))}}}}}
        let digest=try FunctionalRelationshipCanonicalCodecV1.sha256(events.sorted{($0.relationshipID.uuidString,$0.revision)<($1.relationshipID.uuidString,$1.revision)})
        let projection=try CurrentFunctionalRelationshipProjectionV1(workspaceID:workspaceID,throughRecordedAt:events.map(\.recordedAt).max() ?? Date(timeIntervalSince1970:0),currentRelationships:current,readinessRequirements:requirements,sourceEventsSHA256:digest)
        try projection.validate(descriptorReleases:descriptors)
        return projection
    }
    static func validateAtomicCreationBundle(workspaceID:WorkspaceID,existing:[AssetFunctionalRelationshipEventV1],additions:[AssetFunctionalRelationshipEventV1],descriptors:[FunctionalRelationshipTypeDescriptorV1])throws{guard !additions.isEmpty,additions.allSatisfy{$0.action == .added} else{throw FunctionalRelationshipFailureV1.invalidValue};let projection=try rebuild(workspaceID:workspaceID,events:existing+additions,descriptors:descriptors,boundary:.atomicCreationBundle);guard projection.readiness == .ready else{throw FunctionalRelationshipFailureV1.incomplete}}
    fileprivate static func validateTopology(_ current:[AssetFunctionalRelationshipEventV1],descriptors:[UUID:FunctionalRelationshipTypeDescriptorV1])throws{for descriptor in descriptors.values{let edges=current.filter{$0.descriptor.descriptorReleaseID==descriptor.descriptorReleaseID};guard edges.count<=descriptor.maximumHardEdges else{throw FunctionalRelationshipFailureV1.traversalBoundExceeded};let keys=edges.map{edge->String in if descriptor.symmetry == .symmetric{let ordered=[edge.sourceAssetID.uuidString,edge.targetAssetID.uuidString].sorted();return "\(ordered[0]):\(ordered[1])"};return "\(edge.sourceAssetID.uuidString):\(edge.targetAssetID.uuidString)"};guard Set(keys).count==keys.count else{throw FunctionalRelationshipFailureV1.duplicateIdentity};for edge in edges{guard edge.descriptor == .init(descriptor) else{throw FunctionalRelationshipFailureV1.unknownDescriptor};if edge.sourceAssetID==edge.targetAssetID,descriptor.selfEdgePolicy == .forbidden{throw FunctionalRelationshipFailureV1.selfEdgeDenied};let sourceCount=descriptor.symmetry == .symmetric ? edges.filter{$0.sourceAssetID==edge.sourceAssetID || $0.targetAssetID==edge.sourceAssetID}.count:edges.filter{$0.sourceAssetID==edge.sourceAssetID}.count;let targetCount=descriptor.symmetry == .symmetric ? edges.filter{$0.sourceAssetID==edge.targetAssetID || $0.targetAssetID==edge.targetAssetID}.count:edges.filter{$0.targetAssetID==edge.targetAssetID}.count;guard sourceCount<=descriptor.sourceCardinality.maximum,targetCount<=descriptor.targetCardinality.maximum else{throw FunctionalRelationshipFailureV1.cardinalityExceeded}};if descriptor.cyclePolicy == .forbidden{try validateAcyclic(edges,descriptor:descriptor)}else{try validateTraversalBound(edges,descriptor:descriptor)}};guard current.allSatisfy{descriptors[$0.descriptor.descriptorReleaseID] != nil}else{throw FunctionalRelationshipFailureV1.unknownDescriptor}}
    private static func validateAcyclic(_ edges:[AssetFunctionalRelationshipEventV1],descriptor:FunctionalRelationshipTypeDescriptorV1)throws{var graph:[UUID:[UUID]]=[:];for edge in edges{graph[edge.sourceAssetID,default:[]].append(edge.targetAssetID);if descriptor.symmetry == .symmetric{graph[edge.targetAssetID,default:[]].append(edge.sourceAssetID)}};func walk(_ node:UUID,parent:UUID?,depth:Int,path:inout Set<UUID>)throws{guard depth<=descriptor.maximumTraversalDepth else{throw FunctionalRelationshipFailureV1.traversalBoundExceeded};guard path.insert(node).inserted else{throw FunctionalRelationshipFailureV1.cycleDetected};defer{path.remove(node)};for next in graph[node,default:[]] where next != parent{try walk(next,parent:descriptor.symmetry == .symmetric ? node:nil,depth:depth+1,path:&path)}};for origin in graph.keys{var path=Set<UUID>();try walk(origin,parent:nil,depth:0,path:&path)}}
    private static func validateTraversalBound(_ edges:[AssetFunctionalRelationshipEventV1],descriptor:FunctionalRelationshipTypeDescriptorV1)throws{var graph:[UUID:[UUID]]=[:];for edge in edges{graph[edge.sourceAssetID,default:[]].append(edge.targetAssetID);if descriptor.symmetry == .symmetric{graph[edge.targetAssetID,default:[]].append(edge.sourceAssetID)}};for origin in graph.keys{var visited:Set<UUID>=[origin];var frontier:[(UUID,Int)]=[(origin,0)];while !frontier.isEmpty{let(node,depth)=frontier.removeFirst();guard depth<=descriptor.maximumTraversalDepth else{throw FunctionalRelationshipFailureV1.traversalBoundExceeded};for next in graph[node,default:[]] where visited.insert(next).inserted{frontier.append((next,depth+1))}}}}
}

enum FunctionalRelationshipEndpointChangeV1:String,Codable,CaseIterable,Hashable,Sendable {case moved="MOVED";case reparented="REPARENTED";case replaced="REPLACED";case retired="RETIRED";case deleted="DELETED";case restored="RESTORED";case identityReconciled="IDENTITY_RECONCILED";case imported="IMPORTED";case packageRetired="PACKAGE_RETIRED";case crossSiteChanged="CROSS_SITE_CHANGED"}
enum FunctionalRelationshipDispositionV1:String,Codable,CaseIterable,Hashable,Sendable {case retain="RETAIN";case end="END";case supersede="SUPERSEDE";case reviewRequired="REVIEW_REQUIRED";case denied="DENIED"}
struct FunctionalRelationshipDispositionPreviewV1:Codable,Equatable,Hashable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let relationshipID:UUID;let relationshipRevision:UInt64;let change:FunctionalRelationshipEndpointChangeV1;let disposition:FunctionalRelationshipDispositionV1;let reasonCode:String;let persistentWriteOccurred:Bool;let previewSHA256:String;init(workspaceID:WorkspaceID,relationshipID:UUID,relationshipRevision:UInt64,change:FunctionalRelationshipEndpointChangeV1,disposition:FunctionalRelationshipDispositionV1,reasonCode:String)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.relationshipID=relationshipID;self.relationshipRevision=relationshipRevision;self.change=change;self.disposition=disposition;self.reasonCode=reasonCode;persistentWriteOccurred=false;previewSHA256=try FunctionalRelationshipCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,workspaceID:workspaceID,relationshipID:relationshipID,relationshipRevision:relationshipRevision,change:change,disposition:disposition,reasonCode:reasonCode,persistentWriteOccurred:false));try validate()};func validate()throws{guard schemaVersion==Self.schemaVersion,relationshipID != FunctionalRelationshipLimitsV1.zeroUUID,relationshipRevision>0,!reasonCode.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,reasonCode.utf8.count<=256,!persistentWriteOccurred,previewSHA256==(try FunctionalRelationshipCanonicalCodecV1.sha256(Basis(schemaVersion:schemaVersion,workspaceID:workspaceID,relationshipID:relationshipID,relationshipRevision:relationshipRevision,change:change,disposition:disposition,reasonCode:reasonCode,persistentWriteOccurred:persistentWriteOccurred)))else{throw FunctionalRelationshipFailureV1.invalidValue}};private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let relationshipID:UUID;let relationshipRevision:UInt64;let change:FunctionalRelationshipEndpointChangeV1;let disposition:FunctionalRelationshipDispositionV1;let reasonCode:String;let persistentWriteOccurred:Bool}}

enum FunctionalRelationshipDispositionPreviewEngineV1 {
    static func preview(
        change: FunctionalRelationshipEndpointChangeV1,
        relationship: AssetFunctionalRelationshipEventV1,
        descriptor: FunctionalRelationshipTypeDescriptorV1,
        currentSiteID: UUID,
        proposedSiteID: UUID? = nil
    ) throws -> FunctionalRelationshipDispositionPreviewV1 {
        try relationship.validate();try descriptor.validate()
        guard relationship.workspaceID==descriptor.workspaceID,
              relationship.descriptor==FunctionalRelationshipDescriptorReferenceV1(descriptor),
              currentSiteID != FunctionalRelationshipLimitsV1.zeroUUID,
              proposedSiteID.map({$0 != FunctionalRelationshipLimitsV1.zeroUUID}) ?? true else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
        let disposition:FunctionalRelationshipDispositionV1
        let reason:String
        switch change {
        case .deleted,.retired,.packageRetired:
            disposition = .end;reason="endpoint_or_package_no_longer_current_review_end"
        case .replaced,.identityReconciled:
            disposition = .supersede;reason="endpoint_identity_change_review_successor"
        case .restored,.imported:
            disposition = .reviewRequired;reason="restored_or_imported_relationship_review_required"
        case .moved,.reparented,.crossSiteChanged:
            guard let proposedSiteID else {
                disposition = .reviewRequired;reason="destination_site_required_for_review"
                return try .init(workspaceID:relationship.workspaceID,relationshipID:relationship.relationshipID,relationshipRevision:relationship.revision,change:change,disposition:disposition,reasonCode:reason)
            }
            if proposedSiteID==currentSiteID { disposition = .retain;reason="same_site_functional_relationship_retained" }
            else if descriptor.sitePolicy == .crossSiteLocalAllowed { disposition = .reviewRequired;reason="cross_site_local_relationship_review_required" }
            else { disposition = .denied;reason="descriptor_requires_same_site" }
        }
        return try .init(workspaceID:relationship.workspaceID,relationshipID:relationship.relationshipID,relationshipRevision:relationship.revision,change:change,disposition:disposition,reasonCode:reason)
    }
}

struct CompletedFunctionalRelationshipSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let snapshotID: UUID
    let workspaceID: WorkspaceID
    let capturedAt: Date
    /// Complete immutable event history through `capturedAt`, ordered by
    /// relationship identity and revision. Current state is always rebuilt.
    let descriptorReleases: [FunctionalRelationshipTypeDescriptorV1]
    let relationships: [AssetFunctionalRelationshipEventV1]
    let frozenReferences: [FrozenFunctionalRelationshipReferenceV1]
    let snapshotSHA256: String

    init(
        snapshotID: UUID,
        workspaceID: WorkspaceID,
        capturedAt: Date,
        descriptorReleases: [FunctionalRelationshipTypeDescriptorV1],
        relationships: [AssetFunctionalRelationshipEventV1]
    ) throws {
        let orderedDescriptors = descriptorReleases.sorted {
            $0.descriptorReleaseID.uuidString < $1.descriptorReleaseID.uuidString
        }
        let orderedEvents = relationships.sorted(by: Self.eventOrder)
        guard Self.hasCompleteHistoryRoots(orderedEvents) else {
            throw FunctionalRelationshipFailureV1.digestMismatch
        }
        let projection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            events: orderedEvents,
            descriptors: orderedDescriptors
        )
        let descriptorsByID = Dictionary(uniqueKeysWithValues: orderedDescriptors.map {
            ($0.descriptorReleaseID, $0)
        })
        let references = try projection.currentRelationships.map { event in
            guard let descriptor = descriptorsByID[event.descriptor.descriptorReleaseID] else {
                throw FunctionalRelationshipFailureV1.unknownDescriptor
            }
            return try FrozenFunctionalRelationshipReferenceV1(
                event: event,
                descriptor: descriptor
            )
        }

        schemaVersion = Self.schemaVersion
        self.snapshotID = snapshotID
        self.workspaceID = workspaceID
        self.capturedAt = capturedAt
        self.descriptorReleases = orderedDescriptors
        self.relationships = orderedEvents
        frozenReferences = references
        snapshotSHA256 = try FunctionalRelationshipCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            snapshotID: snapshotID,
            workspaceID: workspaceID,
            capturedAt: capturedAt,
            descriptorReleases: orderedDescriptors,
            relationships: orderedEvents,
            frozenReferences: references
        ))
        try validate()
    }

    func validate() throws {
        try descriptorReleases.forEach { try $0.validate() }
        try relationships.forEach { try $0.validate() }
        try frozenReferences.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              snapshotID != FunctionalRelationshipLimitsV1.zeroUUID,
              descriptorReleases == descriptorReleases.sorted(by: {
                  $0.descriptorReleaseID.uuidString < $1.descriptorReleaseID.uuidString
              }),
              relationships == relationships.sorted(by: Self.eventOrder),
              Set(descriptorReleases.map(\.descriptorReleaseID)).count == descriptorReleases.count,
              Set(relationships.map(\.eventID)).count == relationships.count,
              Self.hasCompleteHistoryRoots(relationships),
              descriptorReleases.allSatisfy({ $0.workspaceID == workspaceID }),
              relationships.allSatisfy({ $0.workspaceID == workspaceID && $0.recordedAt <= capturedAt }) else {
            throw FunctionalRelationshipFailureV1.digestMismatch
        }

        let projection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            events: relationships,
            descriptors: descriptorReleases
        )
        let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptorReleases.map {
            ($0.descriptorReleaseID, $0)
        })
        let expectedReferences = try projection.currentRelationships.map { event in
            guard let descriptor = descriptorsByID[event.descriptor.descriptorReleaseID] else {
                throw FunctionalRelationshipFailureV1.unknownDescriptor
            }
            return try FrozenFunctionalRelationshipReferenceV1(
                event: event,
                descriptor: descriptor
            )
        }
        guard frozenReferences == expectedReferences,
              snapshotSHA256 == (try FunctionalRelationshipCanonicalCodecV1.sha256(Basis(
                  schemaVersion: schemaVersion,
                  snapshotID: snapshotID,
                  workspaceID: workspaceID,
                  capturedAt: capturedAt,
                  descriptorReleases: descriptorReleases,
                  relationships: relationships,
                  frozenReferences: frozenReferences
              ))) else {
            throw FunctionalRelationshipFailureV1.digestMismatch
        }
    }

    private static func eventOrder(
        _ lhs: AssetFunctionalRelationshipEventV1,
        _ rhs: AssetFunctionalRelationshipEventV1
    ) -> Bool {
        if lhs.relationshipID != rhs.relationshipID {
            return lhs.relationshipID.uuidString < rhs.relationshipID.uuidString
        }
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        return lhs.eventID.uuidString < rhs.eventID.uuidString
    }

    private static func hasCompleteHistoryRoots(
        _ events: [AssetFunctionalRelationshipEventV1]
    ) -> Bool {
        Dictionary(grouping: events, by: \.relationshipID).values.allSatisfy { history in
            history.min(by: { $0.revision < $1.revision })?.action == .added
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let snapshotID: UUID
        let workspaceID: WorkspaceID
        let capturedAt: Date
        let descriptorReleases: [FunctionalRelationshipTypeDescriptorV1]
        let relationships: [AssetFunctionalRelationshipEventV1]
        let frozenReferences: [FrozenFunctionalRelationshipReferenceV1]
    }
}

extension CompletedFunctionalRelationshipSnapshotV1 {
    func rebound(to workspaceID:WorkspaceID)throws->Self {
        try Self(snapshotID:snapshotID,workspaceID:workspaceID,capturedAt:capturedAt,
            descriptorReleases:try descriptorReleases.map{try $0.rebound(to:workspaceID)},
            relationships:try relationships.map{try $0.rebound(to:workspaceID)})
    }
}

protocol FunctionalRelationshipValidatableV1 { func validate() throws }
extension FunctionalRelationshipTypeDescriptorV1:FunctionalRelationshipValidatableV1 {}
extension AssetFunctionalRelationshipEventV1:FunctionalRelationshipValidatableV1 {}
extension CurrentFunctionalRelationshipProjectionV1:FunctionalRelationshipValidatableV1 {}
extension FunctionalRelationshipDispositionPreviewV1:FunctionalRelationshipValidatableV1 {}
extension CompletedFunctionalRelationshipSnapshotV1:FunctionalRelationshipValidatableV1 {}

enum FunctionalRelationshipCanonicalCodecV1 { static func encode<T:Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)};static func decode<T:Decodable & Encodable>(_ type:T.Type,from data:Data)throws->T{let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);if let validatable=value as? any FunctionalRelationshipValidatableV1{try validatable.validate()};guard try encode(value)==data else{throw FunctionalRelationshipFailureV1.nonCanonicalData};return value};static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)} }

private func validLocalizationKey(_ value:String)->Bool{AssetSemanticValidationV1.validLocalizationKey(value)}
