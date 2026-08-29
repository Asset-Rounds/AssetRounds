import Foundation

enum LightingContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case staleReference
    case duplicateIdentity
    case incompleteTopology
    case incompleteMeasurementPlan
    case forbiddenClaim
    case safetyStop
    case invalidSuccessor
    case nonCanonicalData
    case limitExceeded
}

enum LightingLimitsV1 {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let maximumTextBytes = 1_024
    static let maximumZones = 512
    static let maximumControlGroups = 512
    static let maximumLuminaires = 4_096
    static let maximumMemberships = 128
    static let maximumMeasurementPoints = 10_000
    static let maximumEvidence = 32
    static let maximumCanonicalBytes = 8_388_608

    static func id(_ value: UUID) throws {
        guard value != zero else { throw LightingContractFailureV1.invalidValue }
    }
    static func revision(_ value: UInt64) throws {
        guard value > 0 else { throw LightingContractFailureV1.invalidValue }
    }
    static func token(_ value: String, maximumBytes: Int = maximumTextBytes) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw LightingContractFailureV1.invalidValue
        }
    }
    static func digest(_ value: String) throws {
        guard MutationEnvelopeV1.isSHA256(value) else { throw LightingContractFailureV1.invalidDigest }
    }
    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw LightingContractFailureV1.invalidValue
        }
    }
    static func next(_ predecessor: UInt64) throws -> UInt64 {
        let result = predecessor.addingReportingOverflow(1)
        guard !result.overflow else { throw LightingContractFailureV1.invalidSuccessor }
        return result.partialValue
    }
}

struct LightingPackageReleaseReferenceV1: Codable, Equatable, Hashable, Sendable {
    let packageReleaseID: String
    let packageID: String
    let contentVersion: Int
    let packageSHA256: String
    let workflowSHA256: String

    init(_ release: InspectionPackageReleaseV1) throws {
        try release.validate()
        guard release.state == .published else { throw LightingContractFailureV1.staleReference }
        packageReleaseID = release.packageReleaseID; packageID = release.packageID
        contentVersion = release.packageContentVersion; packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256
        try validate()
    }
    func validate() throws {
        try LightingLimitsV1.digest(packageReleaseID); try LightingLimitsV1.token(packageID, maximumBytes: 200)
        try LightingLimitsV1.digest(packageSHA256); try LightingLimitsV1.digest(workflowSHA256)
        guard contentVersion > 0 else { throw LightingContractFailureV1.invalidValue }
    }
    func validate(_ release: InspectionPackageReleaseV1) throws {
        try validate(); try release.validate()
        guard release.state == .published, release.packageReleaseID == packageReleaseID,
              release.packageID == packageID, release.packageContentVersion == contentVersion,
              release.packageSHA256 == packageSHA256, release.workflowSHA256 == workflowSHA256 else {
            throw LightingContractFailureV1.staleReference
        }
    }
}

struct LightingZoneV1: Codable, Equatable, Hashable, Sendable {
    let zoneID: UUID
    let displayName: String
    let workSubject: WorkSubjectReferenceV1
    let declaredActivityClass: String?
    let declaredSecurityClass: String?
    func validate() throws {
        try LightingLimitsV1.id(zoneID); try LightingLimitsV1.token(displayName)
        try workSubject.validate()
        try declaredActivityClass.map { try LightingLimitsV1.token($0) }
        try declaredSecurityClass.map { try LightingLimitsV1.token($0) }
    }
}

struct ControlGroupV1: Codable, Equatable, Hashable, Sendable {
    let controlGroupID: UUID
    let semanticID: String
    let expectation: ControlExpectationV1
    func validate() throws {
        try LightingLimitsV1.id(controlGroupID); try LightingLimitsV1.token(semanticID)
        try expectation.validate()
        guard expectation.controlGroupID == controlGroupID.uuidString.lowercased()
                || expectation.controlGroupID == semanticID else {
            throw LightingContractFailureV1.staleReference
        }
    }
}

enum LightingComponentMaintenanceDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case subordinate = "SUBORDINATE"
    case independentlyMaintained = "INDEPENDENTLY_MAINTAINED"
}

struct LuminaireAssetV1: Codable, Equatable, Hashable, Sendable {
    let luminaireID: UUID
    let assetID: UUID
    let assetRevision: UInt64
    let semanticBinding: WorkSubjectSemanticBindingSnapshotV1
    let zoneIDs: [UUID]
    let controlGroupIDs: [UUID]
    let supportAssemblyAssetID: UUID?
    let supportAssemblySemanticBinding: WorkSubjectSemanticBindingSnapshotV1?
    let supportRelationship: FrozenFunctionalRelationshipReferenceV1?
    let supportRelationshipEventID: UUID?
    let maintenanceDisposition: LightingComponentMaintenanceDispositionV1

    init(luminaireID: UUID, assetID: UUID, assetRevision: UInt64,
         semanticBinding: WorkSubjectSemanticBindingSnapshotV1, zoneIDs: [UUID],
         controlGroupIDs: [UUID], supportAssemblyAssetID: UUID? = nil,
         supportRelationship: FrozenFunctionalRelationshipReferenceV1? = nil,
         supportAssemblySemanticBinding: WorkSubjectSemanticBindingSnapshotV1? = nil,
         supportRelationshipEventID: UUID? = nil,
         maintenanceDisposition: LightingComponentMaintenanceDispositionV1) {
        self.luminaireID = luminaireID; self.assetID = assetID; self.assetRevision = assetRevision
        self.semanticBinding = semanticBinding; self.zoneIDs = zoneIDs.sorted { $0.uuidString < $1.uuidString }
        self.controlGroupIDs = controlGroupIDs.sorted { $0.uuidString < $1.uuidString }
        self.supportAssemblyAssetID = supportAssemblyAssetID
        self.supportAssemblySemanticBinding = supportAssemblySemanticBinding
        self.supportRelationship = supportRelationship
        self.supportRelationshipEventID = supportRelationshipEventID
        self.maintenanceDisposition = maintenanceDisposition
    }
    func validate() throws {
        try LightingLimitsV1.id(luminaireID); try LightingLimitsV1.id(assetID)
        try LightingLimitsV1.revision(assetRevision); try semanticBinding.validate()
        try zoneIDs.forEach(LightingLimitsV1.id); try controlGroupIDs.forEach(LightingLimitsV1.id)
        try supportAssemblyAssetID.map(LightingLimitsV1.id)
        try supportAssemblySemanticBinding?.validate()
        try supportRelationship?.validate()
        try supportRelationshipEventID.map(LightingLimitsV1.id)
        guard semanticBinding.assetID == assetID, !zoneIDs.isEmpty, !controlGroupIDs.isEmpty,
              zoneIDs.count <= LightingLimitsV1.maximumMemberships,
              controlGroupIDs.count <= LightingLimitsV1.maximumMemberships,
              Set(zoneIDs).count == zoneIDs.count, Set(controlGroupIDs).count == controlGroupIDs.count,
              (supportAssemblyAssetID == nil) == (supportRelationship == nil),
              (supportAssemblyAssetID == nil) == (supportAssemblySemanticBinding == nil),
              (supportAssemblyAssetID == nil) == (supportRelationshipEventID == nil),
              supportAssemblySemanticBinding?.assetID == supportAssemblyAssetID,
              supportAssemblyAssetID != assetID else { throw LightingContractFailureV1.invalidValue }
    }
}

struct LightingSystemV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let recordID: UUID
    let systemID: UUID
    let workspaceID: WorkspaceID
    let siteID: UUID
    let packageRelease: LightingPackageReleaseReferenceV1
    let zones: [LightingZoneV1]
    let controlGroups: [ControlGroupV1]
    let luminaires: [LuminaireAssetV1]
    let supersedesRecordID: UUID?
    let predecessorSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let systemSHA256: String

    init(recordID: UUID, systemID: UUID, workspaceID: WorkspaceID, siteID: UUID,
         packageRelease: LightingPackageReleaseReferenceV1, zones: [LightingZoneV1],
         controlGroups: [ControlGroupV1], luminaires: [LuminaireAssetV1],
         predecessor: Self? = nil, revision: UInt64, mutationID: MutationIDV1,
         recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        let orderedZones = zones.sorted { $0.zoneID.uuidString < $1.zoneID.uuidString }
        let orderedGroups = controlGroups.sorted { $0.controlGroupID.uuidString < $1.controlGroupID.uuidString }
        let orderedLuminaires = luminaires.sorted { $0.luminaireID.uuidString < $1.luminaireID.uuidString }
        schemaVersion = Self.schemaVersion; self.recordID = recordID; self.systemID = systemID
        self.workspaceID = workspaceID; self.siteID = siteID; self.packageRelease = packageRelease
        self.zones = orderedZones; self.controlGroups = orderedGroups; self.luminaires = orderedLuminaires
        supersedesRecordID = predecessor?.recordID; predecessorSHA256 = predecessor?.systemSHA256
        self.revision = revision; self.mutationID = mutationID; self.recordedBy = recordedBy
        self.recordedAt = recordedAt
        systemSHA256 = try LightingCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            recordID: recordID, systemID: systemID, workspaceID: workspaceID, siteID: siteID,
            packageRelease: packageRelease, zones: orderedZones, controlGroups: orderedGroups,
            luminaires: orderedLuminaires, supersedesRecordID: predecessor?.recordID,
            predecessorSHA256: predecessor?.systemSHA256, revision: revision, mutationID: mutationID,
            recordedBy: recordedBy, recordedAt: recordedAt))
        try validateIntrinsic(); if let predecessor { try validateSuccessor(of: predecessor) }
    }
    func validateIntrinsic() throws {
        try LightingLimitsV1.id(recordID); try LightingLimitsV1.id(systemID); try LightingLimitsV1.id(siteID)
        try packageRelease.validate(); try recordedBy.validate(); try LightingLimitsV1.instant(recordedAt)
        try predecessorSHA256.map(LightingLimitsV1.digest)
        try zones.forEach { try $0.validate() }; try controlGroups.forEach { try $0.validate() }
        try luminaires.forEach { try $0.validate() }
        let zoneIDs = Set(zones.map(\.zoneID)), controlIDs = Set(controlGroups.map(\.controlGroupID))
        guard schemaVersion == Self.schemaVersion, revision > 0, !zones.isEmpty, !controlGroups.isEmpty,
              !luminaires.isEmpty, zones.count <= LightingLimitsV1.maximumZones,
              controlGroups.count <= LightingLimitsV1.maximumControlGroups,
              luminaires.count <= LightingLimitsV1.maximumLuminaires,
              zoneIDs.count == zones.count, controlIDs.count == controlGroups.count,
              Set(luminaires.map(\.luminaireID)).count == luminaires.count,
              Set(luminaires.map(\.assetID)).count == luminaires.count,
              luminaires.allSatisfy({ Set($0.zoneIDs).isSubset(of: zoneIDs)
                    && Set($0.controlGroupIDs).isSubset(of: controlIDs) }),
              recordedBy.workspaceID == workspaceID, recordedBy.responsibility == .recordedBy,
              (revision == 1) == (supersedesRecordID == nil && predecessorSHA256 == nil),
              systemSHA256 == (try LightingCanonicalCodecV1.sha256(basis)) else {
            throw LightingContractFailureV1.incompleteTopology
        }
    }
    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic(); try validateIntrinsic()
        guard workspaceID == predecessor.workspaceID, siteID == predecessor.siteID,
              systemID == predecessor.systemID, packageRelease == predecessor.packageRelease,
              recordID != predecessor.recordID, supersedesRecordID == predecessor.recordID,
              predecessorSHA256 == predecessor.systemSHA256,
              revision == (try LightingLimitsV1.next(predecessor.revision)),
              mutationID != predecessor.mutationID, recordedAt >= predecessor.recordedAt else {
            throw LightingContractFailureV1.invalidSuccessor
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, recordID: recordID, systemID: systemID,
        workspaceID: workspaceID, siteID: siteID, packageRelease: packageRelease, zones: zones,
        controlGroups: controlGroups, luminaires: luminaires, supersedesRecordID: supersedesRecordID,
        predecessorSHA256: predecessorSHA256, revision: revision, mutationID: mutationID,
        recordedBy: recordedBy, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion:Int;let recordID:UUID;let systemID:UUID;let workspaceID:WorkspaceID;let siteID:UUID;let packageRelease:LightingPackageReleaseReferenceV1;let zones:[LightingZoneV1];let controlGroups:[ControlGroupV1];let luminaires:[LuminaireAssetV1];let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date }
}

struct LightingTopologyAdmissionClosureV1: Codable, Equatable, Sendable {
    let descriptors: [FunctionalRelationshipTypeDescriptorV1]
    let relationshipEvents: [AssetFunctionalRelationshipEventV1]

    func validate(system: LightingSystemV1) throws {
        try system.validateIntrinsic()
        try descriptors.forEach { try $0.validate() }
        try relationshipEvents.forEach { try $0.validate() }
        guard Set(descriptors.map(\.descriptorReleaseID)).count == descriptors.count,
              Set(relationshipEvents.map(\.eventID)).count == relationshipEvents.count,
              descriptors == descriptors.sorted(by: { $0.descriptorReleaseID.uuidString < $1.descriptorReleaseID.uuidString }),
              relationshipEvents == relationshipEvents.sorted(by: {
                  ($0.relationshipID.uuidString, $0.revision) < ($1.relationshipID.uuidString, $1.revision)
              }),
              descriptors.allSatisfy({ $0.workspaceID == system.workspaceID }),
              relationshipEvents.allSatisfy({ $0.workspaceID == system.workspaceID }) else {
            throw LightingContractFailureV1.duplicateIdentity
        }
        let requiredRelationshipIDs = Set(system.luminaires.compactMap { $0.supportRelationship?.relationshipID })
        let requiredDescriptorIDs = Set(system.luminaires.compactMap { $0.supportRelationship?.descriptorReleaseID })
        guard Set(relationshipEvents.map(\.relationshipID)) == requiredRelationshipIDs,
              Set(descriptors.map(\.descriptorReleaseID)) == requiredDescriptorIDs else {
            throw LightingContractFailureV1.incompleteTopology
        }
        for luminaire in system.luminaires {
            guard let frozen = luminaire.supportRelationship,
                  let supportID = luminaire.supportAssemblyAssetID,
                  let supportSemantic = luminaire.supportAssemblySemanticBinding,
                  let eventID = luminaire.supportRelationshipEventID else { continue }
            let matchingDescriptors = descriptors.filter {
                $0.descriptorReleaseID == frozen.descriptorReleaseID
                    && $0.revision == frozen.descriptorReleaseRevision
                    && $0.semanticID == frozen.semanticID
            }
            guard matchingDescriptors.count == 1 else { throw LightingContractFailureV1.staleReference }
            let descriptor = matchingDescriptors[0]
            let sourceIsSupport = descriptor.sourceSemanticIDs.contains(supportSemantic.semanticID)
                && descriptor.targetSemanticIDs.contains(luminaire.semanticBinding.semanticID)
                && descriptor.sourceCatalogRelease == supportSemantic.catalogRelease
                && descriptor.targetCatalogRelease == luminaire.semanticBinding.catalogRelease
            let sourceIsLuminaire = descriptor.sourceSemanticIDs.contains(luminaire.semanticBinding.semanticID)
                && descriptor.targetSemanticIDs.contains(supportSemantic.semanticID)
                && descriptor.sourceCatalogRelease == luminaire.semanticBinding.catalogRelease
                && descriptor.targetCatalogRelease == supportSemantic.catalogRelease
            guard sourceIsSupport != sourceIsLuminaire else { throw LightingContractFailureV1.incompleteTopology }
            let history = relationshipEvents.filter { $0.relationshipID == frozen.relationshipID }
                .sorted { $0.revision < $1.revision }
            guard history.first?.revision == 1, history.first?.action == .added,
                  Set(history.map(\.revision)).count == history.count else {
                throw LightingContractFailureV1.duplicateIdentity
            }
            for index in history.indices.dropFirst() {
                try history[index].validateSuccessor(of: history[history.index(before: index)])
            }
            guard let current = history.max(by: { $0.revision < $1.revision }),
                  current.eventID == eventID,
                  current.revision == frozen.relationshipRevision,
                  current.descriptor.descriptorReleaseID == frozen.descriptorReleaseID,
                  current.descriptor.revision == frozen.descriptorReleaseRevision,
                  (try FrozenFunctionalRelationshipReferenceV1(event: current, descriptor: descriptor)) == frozen,
                  current.action != .ended,
                  current.sourceAssetID == (sourceIsSupport ? supportID : luminaire.assetID),
                  current.targetAssetID == (sourceIsSupport ? luminaire.assetID : supportID),
                  (sourceIsSupport ? current.targetAssetRevision : current.sourceAssetRevision) == luminaire.assetRevision else {
                throw LightingContractFailureV1.staleReference
            }
        }
    }
}

enum LightingTopologyAdmissionV1 {
    static func validate(_ system: LightingSystemV1,
                         admission: LightingTopologyAdmissionClosureV1) throws {
        try admission.validate(system: system)
    }
}

enum LightingIssueKindV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case appearedUnlit = "APPEARED_UNLIT"; case partialOutput = "PARTIAL_OUTPUT"
    case observedIntermittent = "OBSERVED_INTERMITTENT"; case cameraBandingOnly = "CAMERA_BANDING_ONLY"
    case daylightEnergized = "DAYLIGHT_ENERGIZED"; case controlUnknown = "CONTROL_UNKNOWN"
    case lensConcern = "LENS_CONCERN"; case shieldConcern = "SHIELD_CONCERN"
    case alignmentConcern = "ALIGNMENT_CONCERN"; case obstructionConcern = "OBSTRUCTION_CONCERN"
    case spillConcern = "SPILL_CONCERN"; case glareConcern = "GLARE_CONCERN"
    case colorConcern = "COLOR_CONCERN"; case supportDamage = "SUPPORT_DAMAGE"
    case visiblePotentialElectricalIndicator = "VISIBLE_POTENTIAL_ELECTRICAL_INDICATOR"
    case visiblePotentialEmergencyIndicator = "VISIBLE_POTENTIAL_EMERGENCY_INDICATOR"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct LightingObservationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion:Int;let recordID:UUID;let observationID:UUID;let workspaceID:WorkspaceID
    let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let luminaireID:UUID
    let assetID:UUID;let assetRevision:UInt64;let zoneID:UUID;let controlGroupID:UUID
    let evidenceContext:EvidenceContextV1;let observationBasis:ObservationBasisV1
    let issueKinds:[LightingIssueKindV1];let supersedesRecordID:UUID?;let predecessorSHA256:String?
    let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date
    let observationSHA256:String
    init(recordID:UUID,observationID:UUID,workspaceID:WorkspaceID,system:LightingSystemV1,
         luminaireID:UUID,zoneID:UUID,controlGroupID:UUID,evidenceContext:EvidenceContextV1,
         observationBasis:ObservationBasisV1,issueKinds:[LightingIssueKindV1],predecessor:Self?=nil,
         revision:UInt64,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws{
        try system.validateIntrinsic();guard let luminaire=system.luminaires.first(where:{$0.luminaireID==luminaireID})else{throw LightingContractFailureV1.staleReference}
        let orderedKinds=issueKinds.sorted()
        schemaVersion=Self.schemaVersion;self.recordID=recordID;self.observationID=observationID;self.workspaceID=workspaceID
        systemID=system.systemID;systemRevision=system.revision;systemSHA256=system.systemSHA256;self.luminaireID=luminaireID
        assetID=luminaire.assetID;assetRevision=luminaire.assetRevision;self.zoneID=zoneID;self.controlGroupID=controlGroupID
        self.evidenceContext=evidenceContext;self.observationBasis=observationBasis;self.issueKinds=orderedKinds
        supersedesRecordID=predecessor?.recordID;predecessorSHA256=predecessor?.observationSHA256;self.revision=revision
        self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt
        observationSHA256=try LightingCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,recordID:recordID,observationID:observationID,workspaceID:workspaceID,systemID:system.systemID,systemRevision:system.revision,systemSHA256:system.systemSHA256,luminaireID:luminaireID,assetID:luminaire.assetID,assetRevision:luminaire.assetRevision,zoneID:zoneID,controlGroupID:controlGroupID,evidenceContext:evidenceContext,observationBasis:observationBasis,issueKinds:orderedKinds,supersedesRecordID:predecessor?.recordID,predecessorSHA256:predecessor?.observationSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt));try validate(system:system)
        if let predecessor{try validateSuccessor(of:predecessor,system:system)}
    }
    func validateIntrinsic()throws{try LightingLimitsV1.id(recordID);try LightingLimitsV1.id(observationID);try LightingLimitsV1.id(systemID);try LightingLimitsV1.id(luminaireID);try LightingLimitsV1.id(assetID);try LightingLimitsV1.id(zoneID);try LightingLimitsV1.id(controlGroupID);try LightingLimitsV1.revision(systemRevision);try LightingLimitsV1.revision(assetRevision);try LightingLimitsV1.revision(revision);try LightingLimitsV1.digest(systemSHA256);try predecessorSHA256.map(LightingLimitsV1.digest);try evidenceContext.validateIntrinsic();try observationBasis.validate();try recordedBy.validate();try LightingLimitsV1.instant(recordedAt);guard schemaVersion==Self.schemaVersion,issueKinds.count<=LightingIssueKindV1.allCases.count,issueKinds==issueKinds.sorted(),Set(issueKinds).count==issueKinds.count,evidenceContext.workspaceID==workspaceID,evidenceContext.assetID==assetID,evidenceContext.assetRevision==assetRevision,recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,(revision==1)==(supersedesRecordID==nil&&predecessorSHA256==nil),observationSHA256==(try LightingCanonicalCodecV1.sha256(basis))else{throw LightingContractFailureV1.invalidValue}}
    func validate(system:LightingSystemV1)throws{try validateIntrinsic();try system.validateIntrinsic();guard workspaceID==system.workspaceID,systemID==system.systemID,systemRevision==system.revision,systemSHA256==system.systemSHA256,let luminaire=system.luminaires.first(where:{$0.luminaireID==luminaireID}),luminaire.assetID==assetID,luminaire.assetRevision==assetRevision,luminaire.zoneIDs.contains(zoneID),luminaire.controlGroupIDs.contains(controlGroupID)else{throw LightingContractFailureV1.staleReference}}
    func validateSuccessor(of predecessor:Self,system:LightingSystemV1)throws{try predecessor.validateIntrinsic();try validate(system:system);guard observationID==predecessor.observationID,recordID != predecessor.recordID,supersedesRecordID==predecessor.recordID,predecessorSHA256==predecessor.observationSHA256,revision==(try LightingLimitsV1.next(predecessor.revision)),mutationID != predecessor.mutationID,recordedAt>=predecessor.recordedAt else{throw LightingContractFailureV1.invalidSuccessor}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,recordID:recordID,observationID:observationID,workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,luminaireID:luminaireID,assetID:assetID,assetRevision:assetRevision,zoneID:zoneID,controlGroupID:controlGroupID,evidenceContext:evidenceContext,observationBasis:observationBasis,issueKinds:issueKinds,supersedesRecordID:supersedesRecordID,predecessorSHA256:predecessorSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let recordID:UUID;let observationID:UUID;let workspaceID:WorkspaceID;let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let luminaireID:UUID;let assetID:UUID;let assetRevision:UInt64;let zoneID:UUID;let controlGroupID:UUID;let evidenceContext:EvidenceContextV1;let observationBasis:ObservationBasisV1;let issueKinds:[LightingIssueKindV1];let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

enum LightingIssueDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case open="OPEN";case resolved="RESOLVED";case superseded="SUPERSEDED"}
struct LightingObservationReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let observationID: UUID
    let luminaireID: UUID
    let assetID: UUID
    let assetRevision: UInt64
    let revision: UInt64
    let observationSHA256: String

    init(_ value: LightingObservationV1) throws {
        try value.validateIntrinsic()
        workspaceID = value.workspaceID; observationID = value.observationID
        luminaireID = value.luminaireID; assetID = value.assetID
        assetRevision = value.assetRevision; revision = value.revision
        observationSHA256 = value.observationSHA256
    }
    func validate() throws {
        try LightingLimitsV1.id(observationID); try LightingLimitsV1.id(luminaireID)
        try LightingLimitsV1.id(assetID); try LightingLimitsV1.revision(assetRevision)
        try LightingLimitsV1.revision(revision); try LightingLimitsV1.digest(observationSHA256)
    }
}

struct LightingIssueV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let recordID:UUID;let issueID:UUID;let workspaceID:WorkspaceID;let kind:LightingIssueKindV1
    let subjectAssetID:UUID;let observation:LightingObservationReferenceV1;let findingID:String;let findingRevision:Int
    let disposition:LightingIssueDispositionV1;let resolutionEvidence:[ContentReferenceV1];let supersedesRecordID:UUID?
    let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1
    let recordedAt:Date;let issueSHA256:String
    init(recordID:UUID,issueID:UUID,workspaceID:WorkspaceID,kind:LightingIssueKindV1,subjectAssetID:UUID,
         observation:LightingObservationReferenceV1,finding:FindingV1,disposition:LightingIssueDispositionV1,
         resolutionEvidence:[ContentReferenceV1]=[],predecessor:Self?=nil,revision:UInt64,
         mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws{
        let orderedEvidence=resolutionEvidence.sorted{$0.contentID<$1.contentID}
        schemaVersion=Self.schemaVersion;self.recordID=recordID;self.issueID=issueID;self.workspaceID=workspaceID;self.kind=kind
        self.subjectAssetID=subjectAssetID;self.observation=observation;findingID=finding.findingID;findingRevision=finding.revision
        self.disposition=disposition;self.resolutionEvidence=orderedEvidence
        supersedesRecordID=predecessor?.recordID;predecessorSHA256=predecessor?.issueSHA256;self.revision=revision
        self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt
        issueSHA256=try LightingCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,recordID:recordID,issueID:issueID,workspaceID:workspaceID,kind:kind,subjectAssetID:subjectAssetID,observation:observation,findingID:finding.findingID,findingRevision:finding.revision,disposition:disposition,resolutionEvidence:orderedEvidence,supersedesRecordID:predecessor?.recordID,predecessorSHA256:predecessor?.issueSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt));try validateIntrinsic();if let predecessor{try validateSuccessor(of:predecessor)}
    }
    func validateIntrinsic()throws{try LightingLimitsV1.id(recordID);try LightingLimitsV1.id(issueID);try LightingLimitsV1.id(subjectAssetID);try observation.validate();try LightingLimitsV1.token(findingID);try LightingLimitsV1.revision(revision);try predecessorSHA256.map(LightingLimitsV1.digest);try recordedBy.validate();try LightingLimitsV1.instant(recordedAt);try resolutionEvidence.forEach{reference in guard reference.workspaceID==workspaceID.rawValue.uuidString.lowercased(),reference.digests.digest(for:.sha256) != nil else{throw LightingContractFailureV1.wrongWorkspace}};guard schemaVersion==Self.schemaVersion,findingRevision>=0,resolutionEvidence.count<=LightingLimitsV1.maximumEvidence,resolutionEvidence==resolutionEvidence.sorted(by:{$0.contentID<$1.contentID}),Set(resolutionEvidence.map(\.contentID)).count==resolutionEvidence.count,observation.workspaceID==workspaceID,observation.assetID==subjectAssetID,(disposition == .resolved) == !resolutionEvidence.isEmpty,recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,(revision==1)==(supersedesRecordID==nil&&predecessorSHA256==nil),issueSHA256==(try LightingCanonicalCodecV1.sha256(basis))else{throw LightingContractFailureV1.invalidValue}}
    func validate(observation source:LightingObservationV1)throws{try validateIntrinsic();try source.validateIntrinsic();guard observation==(try LightingObservationReferenceV1(source)),workspaceID==source.workspaceID,subjectAssetID==source.assetID,source.issueKinds.contains(kind) else{throw LightingContractFailureV1.staleReference}}
    func validateSuccessor(of predecessor:Self,observation source:LightingObservationV1)throws{try predecessor.validateIntrinsic();try validate(observation:source);guard predecessor.disposition == .open,workspaceID==predecessor.workspaceID,issueID==predecessor.issueID,kind==predecessor.kind,subjectAssetID==predecessor.subjectAssetID,observation==predecessor.observation,findingID==predecessor.findingID,recordID != predecessor.recordID,supersedesRecordID==predecessor.recordID,predecessorSHA256==predecessor.issueSHA256,revision==(try LightingLimitsV1.next(predecessor.revision)),mutationID != predecessor.mutationID,recordedAt>=predecessor.recordedAt else{throw LightingContractFailureV1.invalidSuccessor}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validateIntrinsic();try validateIntrinsic();guard predecessor.disposition == .open,workspaceID==predecessor.workspaceID,issueID==predecessor.issueID,kind==predecessor.kind,subjectAssetID==predecessor.subjectAssetID,observation==predecessor.observation,findingID==predecessor.findingID,recordID != predecessor.recordID,supersedesRecordID==predecessor.recordID,predecessorSHA256==predecessor.issueSHA256,revision==(try LightingLimitsV1.next(predecessor.revision)),mutationID != predecessor.mutationID,recordedAt>=predecessor.recordedAt else{throw LightingContractFailureV1.invalidSuccessor}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,recordID:recordID,issueID:issueID,workspaceID:workspaceID,kind:kind,subjectAssetID:subjectAssetID,observation:observation,findingID:findingID,findingRevision:findingRevision,disposition:disposition,resolutionEvidence:resolutionEvidence,supersedesRecordID:supersedesRecordID,predecessorSHA256:predecessorSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let recordID:UUID;let issueID:UUID;let workspaceID:WorkspaceID;let kind:LightingIssueKindV1;let subjectAssetID:UUID;let observation:LightingObservationReferenceV1;let findingID:String;let findingRevision:Int;let disposition:LightingIssueDispositionV1;let resolutionEvidence:[ContentReferenceV1];let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

struct LightingIssueAdmissionClosureV1: Codable, Equatable, Sendable {
    let observation: LightingObservationV1

    func validate(issue: LightingIssueV1, predecessor: LightingIssueV1?) throws {
        try issue.validate(observation: observation)
        if let predecessor { try issue.validateSuccessor(of: predecessor, observation: observation) }
        else if issue.revision != 1 || issue.disposition != .open {
            throw LightingContractFailureV1.invalidSuccessor
        }
    }
}

enum LightingMeasurementPlaneV1:String,Codable,CaseIterable,Hashable,Sendable{case horizontal="HORIZONTAL";case vertical="VERTICAL";case otherDeclared="OTHER_DECLARED"}
struct LightingMeasurementPointV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let pointID:UUID;let ordinal:Int;let zoneID:UUID;let pageID:UUID;let spatialFrameID:UUID
    let plane:LightingMeasurementPlaneV1;let heightMillimetres:Int64;let orientationMilliDegrees:Int32
    static func <(lhs:Self,rhs:Self)->Bool{(lhs.ordinal,lhs.pointID.uuidString)<(rhs.ordinal,rhs.pointID.uuidString)}
    func validate()throws{try LightingLimitsV1.id(pointID);try LightingLimitsV1.id(zoneID);try LightingLimitsV1.id(pageID);try LightingLimitsV1.id(spatialFrameID);guard ordinal>0,ordinal<=LightingLimitsV1.maximumMeasurementPoints,heightMillimetres>=0,heightMillimetres<=100_000,(-360_000...360_000).contains(orientationMilliDegrees)else{throw LightingContractFailureV1.invalidValue}}
}

struct LightingMeasurementCaptureBindingV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let pointID:UUID;let sampleOrdinal:Int;let captureID:UUID;let captureRevision:UInt64;let captureSHA256:String
    static func <(lhs:Self,rhs:Self)->Bool{(lhs.sampleOrdinal,lhs.pointID.uuidString)<(rhs.sampleOrdinal,rhs.pointID.uuidString)}
    func validate()throws{try LightingLimitsV1.id(pointID);try LightingLimitsV1.id(captureID);try LightingLimitsV1.revision(captureRevision);try LightingLimitsV1.digest(captureSHA256);guard sampleOrdinal>0,sampleOrdinal<=LightingLimitsV1.maximumMeasurementPoints else{throw LightingContractFailureV1.invalidValue}}
}

struct MeasurementPlanV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let recordID:UUID;let planID:UUID;let workspaceID:WorkspaceID;let systemID:UUID
    let systemRevision:UInt64;let systemSHA256:String;let packageRelease:LightingPackageReleaseReferenceV1;let planRevision:PlanRevisionReferenceV1
    let protocolReference:MeasurementProtocolReferenceV1;let points:[LightingMeasurementPointV1]
    let expectedSampleCount:Int;let environmentBasisSHA256:String;let controlContextSHA256:String
    let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1
    let recordedBy:ActorSnapshotV1;let recordedAt:Date;let planSHA256:String
    init(recordID:UUID,planID:UUID,workspaceID:WorkspaceID,system:LightingSystemV1,
         planRevision:PlanRevisionReferenceV1,protocolReference:MeasurementProtocolReferenceV1,
         points:[LightingMeasurementPointV1],expectedSampleCount:Int,environmentBasisSHA256:String,
         controlContextSHA256:String,predecessor:Self?=nil,revision:UInt64,mutationID:MutationIDV1,
         recordedBy:ActorSnapshotV1,recordedAt:Date)throws{
        let orderedPoints=points.sorted()
        schemaVersion=Self.schemaVersion;self.recordID=recordID;self.planID=planID;self.workspaceID=workspaceID
        systemID=system.systemID;systemRevision=system.revision;systemSHA256=system.systemSHA256;packageRelease=system.packageRelease;self.planRevision=planRevision
        self.protocolReference=protocolReference;self.points=orderedPoints;self.expectedSampleCount=expectedSampleCount
        self.environmentBasisSHA256=environmentBasisSHA256;self.controlContextSHA256=controlContextSHA256
        supersedesRecordID=predecessor?.recordID;predecessorSHA256=predecessor?.planSHA256;self.revision=revision
        self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt
        planSHA256=try LightingCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,recordID:recordID,planID:planID,workspaceID:workspaceID,systemID:system.systemID,systemRevision:system.revision,systemSHA256:system.systemSHA256,packageRelease:system.packageRelease,planRevision:planRevision,protocolReference:protocolReference,points:orderedPoints,expectedSampleCount:expectedSampleCount,environmentBasisSHA256:environmentBasisSHA256,controlContextSHA256:controlContextSHA256,supersedesRecordID:predecessor?.recordID,predecessorSHA256:predecessor?.planSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt));try validate(system:system);if let predecessor{try validateSuccessor(of:predecessor,system:system)}
    }
    func validateIntrinsic()throws{try LightingLimitsV1.id(recordID);try LightingLimitsV1.id(planID);try LightingLimitsV1.id(systemID);try LightingLimitsV1.revision(systemRevision);try LightingLimitsV1.digest(systemSHA256);try packageRelease.validate();try planRevision.validate();try protocolReference.validate();try points.forEach{try $0.validate()};try LightingLimitsV1.digest(environmentBasisSHA256);try LightingLimitsV1.digest(controlContextSHA256);try predecessorSHA256.map(LightingLimitsV1.digest);try recordedBy.validate();guard schemaVersion==Self.schemaVersion,!points.isEmpty,points.count<=LightingLimitsV1.maximumMeasurementPoints,expectedSampleCount==points.count,Set(points.map(\.pointID)).count==points.count,Set(points.map(\.ordinal)).count==points.count,points.map(\.ordinal)==Array(1...points.count),recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,(revision==1)==(supersedesRecordID==nil&&predecessorSHA256==nil),planSHA256==(try LightingCanonicalCodecV1.sha256(basis))else{throw LightingContractFailureV1.incompleteMeasurementPlan}}
    func validate(system:LightingSystemV1)throws{try validateIntrinsic();try system.validateIntrinsic();let zones=Set(system.zones.map(\.zoneID));guard workspaceID==system.workspaceID,systemID==system.systemID,systemRevision==system.revision,systemSHA256==system.systemSHA256,packageRelease==system.packageRelease,Set(points.map(\.zoneID)).isSubset(of:zones)else{throw LightingContractFailureV1.staleReference}}
    func validateSuccessor(of predecessor:Self,system:LightingSystemV1)throws{try predecessor.validateIntrinsic();try validate(system:system);guard planID==predecessor.planID,recordID != predecessor.recordID,supersedesRecordID==predecessor.recordID,predecessorSHA256==predecessor.planSHA256,revision==(try LightingLimitsV1.next(predecessor.revision)),mutationID != predecessor.mutationID else{throw LightingContractFailureV1.invalidSuccessor}}
    func validateCompleteCaptures(_ captures:[MeasurementCaptureV1],bindings:[LightingMeasurementCaptureBindingV1],protocolRelease:MeasurementProtocolReleaseV1,instrument:InstrumentReferenceV1,calibration:CalibrationStatusSnapshotV1,quality:[MeasurementQualityAssessmentV1])throws{
        try validateIntrinsic();try protocolRelease.validate();try instrument.validate();try calibration.validate()
        try captures.forEach{try $0.validate()};try bindings.forEach{try $0.validate()};try quality.forEach{try $0.validate()}
        let instrumentReference=try InstrumentRevisionReferenceV1(instrument),calibrationReference=try CalibrationSnapshotReferenceV1(calibration)
        let capturesByID=Dictionary(grouping:captures,by:\.captureID),qualityBySubject=Dictionary(grouping:quality,by:\.subjectID)
        let protocolShape = protocolRelease.samplingPolicy == .single ? expectedSampleCount == 1 : true
        for capture in captures {
            guard let assessment=qualityBySubject[capture.captureID]?.only else {
                throw LightingContractFailureV1.incompleteMeasurementPlan
            }
            let expectedReasons=try MeasurementQualityEvaluatorV1.reasons(
                capture:capture,calibration:calibration,requiresUncertainty:protocolRelease.requiresUncertainty
            )
            guard assessment.reasonCodes==expectedReasons,
                  assessment.result==MeasurementQualityEvaluatorV1.result(for:expectedReasons) else {
                throw LightingContractFailureV1.incompleteMeasurementPlan
            }
        }
        guard protocolRelease.workspaceID==workspaceID,protocolReference==(try MeasurementProtocolReferenceV1(protocolRelease)),
              protocolRelease.dimension == .illuminance,protocolRelease.minimumSampleCount<=expectedSampleCount,
              expectedSampleCount<=protocolRelease.maximumSampleCount,protocolShape,
              captures.count==points.count,bindings.count==points.count,bindings==bindings.sorted(),quality.count==captures.count,
              captures.map(\.captureID)==bindings.map(\.captureID),quality.map(\.subjectID)==bindings.map(\.captureID),
              Set(bindings.map(\.pointID))==Set(points.map(\.pointID)),Set(bindings.map(\.captureID))==Set(captures.map(\.captureID)),
              bindings.map(\.sampleOrdinal)==points.map(\.ordinal),
              bindings.allSatisfy({binding in guard let capture=capturesByID[binding.captureID]?.only,
                    let assessment=qualityBySubject[binding.captureID]?.only else{return false};return capture.revision==binding.captureRevision&&capture.captureSHA256==binding.captureSHA256&&assessment.subjectRevision==capture.revision&&assessment.subjectSHA256==capture.captureSHA256&&assessment.assessedAt>=capture.capturedAt}),
              captures.allSatisfy({capture in capture.workspaceID==workspaceID&&capture.packageReleaseID==packageRelease.packageReleaseID&&capture.workflowSHA256==packageRelease.workflowSHA256&&capture.measurement.dimension == .illuminance&&capture.measurement.canonicalUnitID==protocolRelease.normativeUnitID&&capture.sourceMode == .localObservation&&capture.instrument==instrumentReference&&capture.calibration==calibrationReference&&protocolRelease.recordedAt<=capture.capturedAt&&instrument.recordedAt<=capture.capturedAt&&calibration.capturedAt<=capture.capturedAt&&(!protocolRelease.requiresUncertainty || capture.measurement.uncertaintyCanonical != nil)&&calibration.effectiveAt.map{$0<=capture.capturedAt}==true&&calibration.expiresAt.map{capture.capturedAt<=$0}==true}),
              instrument.workspaceID==workspaceID,instrument.kind == .illuminanceMeter,instrument.lifecycleState == .active,
              instrument.supportedUnitIDs.contains(protocolRelease.normativeUnitID),calibration.workspaceID==workspaceID,
              calibration.instrument==instrumentReference,calibration.status == .current,
              quality.allSatisfy({$0.workspaceID==workspaceID&&$0.subjectKind == .capture&&$0.result == .clear}) else {
            throw LightingContractFailureV1.incompleteMeasurementPlan
        }
    }
    private var basis:Basis{.init(schemaVersion:schemaVersion,recordID:recordID,planID:planID,workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,packageRelease:packageRelease,planRevision:planRevision,protocolReference:protocolReference,points:points,expectedSampleCount:expectedSampleCount,environmentBasisSHA256:environmentBasisSHA256,controlContextSHA256:controlContextSHA256,supersedesRecordID:supersedesRecordID,predecessorSHA256:predecessorSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let recordID:UUID;let planID:UUID;let workspaceID:WorkspaceID;let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let packageRelease:LightingPackageReleaseReferenceV1;let planRevision:PlanRevisionReferenceV1;let protocolReference:MeasurementProtocolReferenceV1;let points:[LightingMeasurementPointV1];let expectedSampleCount:Int;let environmentBasisSHA256:String;let controlContextSHA256:String;let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

struct CriterionReferenceV1:Codable,Equatable,Sendable{
    let workspaceID:WorkspaceID;let criterionID:String;let authorityReleaseID:UUID;let authorityRevision:UInt64;let authoritySHA256:String
    let basisBindingID:UUID;let basisBindingRevision:UInt64;let basisBindingSHA256:String
    let applicabilitySnapshotID:UUID;let applicabilityRevision:UInt64;let applicabilitySHA256:String
    let assessmentScopeID:UUID;let assessmentScopeRevision:UInt64;let assessmentScopeSHA256:String
    let protocolReference:MeasurementProtocolReferenceV1;let jurisdictionOrContractBasis:String
    let maintainedOrInitialBasis:String;let gridPlaneFormula:String;let effectiveFrom:Date?;let effectiveUntil:Date?
    let reviewedBy:ActorSnapshotV1
    func validate()throws{try LightingLimitsV1.token(criterionID);try LightingLimitsV1.id(authorityReleaseID);try LightingLimitsV1.revision(authorityRevision);try LightingLimitsV1.digest(authoritySHA256);try LightingLimitsV1.id(basisBindingID);try LightingLimitsV1.revision(basisBindingRevision);try LightingLimitsV1.digest(basisBindingSHA256);try LightingLimitsV1.id(applicabilitySnapshotID);try LightingLimitsV1.revision(applicabilityRevision);try LightingLimitsV1.digest(applicabilitySHA256);try LightingLimitsV1.id(assessmentScopeID);try LightingLimitsV1.revision(assessmentScopeRevision);try LightingLimitsV1.digest(assessmentScopeSHA256);try protocolReference.validate();try LightingLimitsV1.token(jurisdictionOrContractBasis);try LightingLimitsV1.token(maintainedOrInitialBasis);try LightingLimitsV1.token(gridPlaneFormula);try reviewedBy.validate();guard effectiveUntil.map{until in effectiveFrom.map{$0<=until} ?? true} ?? true,reviewedBy.responsibility == .reviewedBy else{throw LightingContractFailureV1.invalidValue}}
    func validate(authority:AuthoritySourceReleaseV1,basis:RequirementBasisBindingV1,applicability:ApplicabilityContextSnapshotV1,scope:AssessmentScopeSnapshotV1)throws{try validate();try authority.validate();try basis.validate();try applicability.validate();try scope.validate();guard authority.workspaceID==workspaceID,basis.workspaceID==workspaceID,applicability.workspaceID==workspaceID,scope.workspaceID==workspaceID,reviewedBy.workspaceID==workspaceID,authority.releaseID==authorityReleaseID,authority.revision==authorityRevision,authority.releaseSHA256==authoritySHA256,basis.bindingID==basisBindingID,basis.revision==basisBindingRevision,basis.bindingSHA256==basisBindingSHA256,basis.authorityReleaseID==authorityReleaseID,basis.criterionID==criterionID,applicability.snapshotID==applicabilitySnapshotID,applicability.revision==applicabilityRevision,applicability.snapshotSHA256==applicabilitySHA256,scope.snapshotID==assessmentScopeID,scope.revision==assessmentScopeRevision,scope.snapshotSHA256==assessmentScopeSHA256,scope.applicabilityContextID==applicabilitySnapshotID,scope.includedCriterionIDs.contains(criterionID)else{throw LightingContractFailureV1.staleReference}}
}

enum LightingClaimTierV1:String,Codable,CaseIterable,Hashable,Sendable{case observed="OBSERVED";case measured="MEASURED";case derived="DERIVED";case screened="SCREENED";case externallyAttested="EXTERNALLY_ATTESTED"}
enum LightingScreeningDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case withinRecordedCriterion="WITHIN_RECORDED_CRITERION";case potentialVariance="POTENTIAL_VARIANCE";case inconclusive="INCONCLUSIVE"}
extension LightingScreeningDispositionV1{
    init(_ result:ScreeningCriterionResultV1)throws{switch result{case .meetsScreeningCriterion:self = .withinRecordedCriterion;case .doesNotMeet:self = .potentialVariance;case .inconclusive:self = .inconclusive;case .notEvaluated:throw LightingContractFailureV1.forbiddenClaim}}
}
struct LightingMeasurementClaimReferenceV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let planID:UUID;let planRevision:UInt64;let planSHA256:String;let captures:[LightingMeasurementCaptureBindingV1];let seriesID:UUID?;let seriesRevision:UInt64?;let seriesSHA256:String?;func validate()throws{try LightingLimitsV1.id(planID);try LightingLimitsV1.revision(planRevision);try LightingLimitsV1.digest(planSHA256);try captures.forEach{try $0.validate()};guard !captures.isEmpty,captures==captures.sorted(),Set(captures.map(\.pointID)).count==captures.count,Set(captures.map(\.captureID)).count==captures.count,(seriesID==nil)==(seriesRevision==nil&&seriesSHA256==nil)else{throw LightingContractFailureV1.invalidValue};try seriesID.map(LightingLimitsV1.id);if let seriesRevision{try LightingLimitsV1.revision(seriesRevision)};try seriesSHA256.map(LightingLimitsV1.digest)}}
struct LightingAttestationReferenceV1:Codable,Equatable,Hashable,Sendable{let workspaceID:WorkspaceID;let attestationID:UUID;let revision:UInt64;let attestationSHA256:String;let method:AttestationMethodV1;init(_ value:AttestationV1)throws{try value.validate();workspaceID=value.workspaceID;attestationID=value.attestationID;revision=value.revision;attestationSHA256=value.attestationSHA256;method=value.method;try validate()}func validate()throws{try LightingLimitsV1.id(attestationID);try LightingLimitsV1.revision(revision);try LightingLimitsV1.digest(attestationSHA256);guard method == .importedExternalEvidence else{throw LightingContractFailureV1.forbiddenClaim}}}

struct LightingClaimStateV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let recordID:UUID;let claimID:UUID;let workspaceID:WorkspaceID;let subjectAssetID:UUID
    let tier:LightingClaimTierV1;let observation:LightingObservationReferenceV1?;let measurement:LightingMeasurementClaimReferenceV1?
    let derivedFact:DerivedFactProvenanceV1?;let criterion:CriterionReferenceV1?;let screeningDisposition:LightingScreeningDispositionV1?
    let externalAttestation:LightingAttestationReferenceV1?;let supersedesRecordID:UUID?;let predecessorSHA256:String?
    let revision:UInt64;let mutationID:MutationIDV1;let reviewedBy:ActorSnapshotV1;let recordedAt:Date;let claimSHA256:String
    init(recordID:UUID,claimID:UUID,workspaceID:WorkspaceID,subjectAssetID:UUID,tier:LightingClaimTierV1,
         observation:LightingObservationReferenceV1?=nil,measurement:LightingMeasurementClaimReferenceV1?=nil,
         derivedFact:DerivedFactProvenanceV1?=nil,criterion:CriterionReferenceV1?=nil,
         screeningDisposition:LightingScreeningDispositionV1?=nil,
         externalAttestation:LightingAttestationReferenceV1?=nil,predecessor:Self?=nil,revision:UInt64,
         mutationID:MutationIDV1,reviewedBy:ActorSnapshotV1,recordedAt:Date)throws{
        schemaVersion=Self.schemaVersion;self.recordID=recordID;self.claimID=claimID;self.workspaceID=workspaceID
        self.subjectAssetID=subjectAssetID;self.tier=tier;self.observation=observation;self.measurement=measurement
        self.derivedFact=derivedFact;self.criterion=criterion;self.screeningDisposition=screeningDisposition
        self.externalAttestation=externalAttestation;supersedesRecordID=predecessor?.recordID;predecessorSHA256=predecessor?.claimSHA256
        self.revision=revision;self.mutationID=mutationID;self.reviewedBy=reviewedBy;self.recordedAt=recordedAt
        claimSHA256=try LightingCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,recordID:recordID,claimID:claimID,workspaceID:workspaceID,subjectAssetID:subjectAssetID,tier:tier,observation:observation,measurement:measurement,derivedFact:derivedFact,criterion:criterion,screeningDisposition:screeningDisposition,externalAttestation:externalAttestation,supersedesRecordID:predecessor?.recordID,predecessorSHA256:predecessor?.claimSHA256,revision:revision,mutationID:mutationID,reviewedBy:reviewedBy,recordedAt:recordedAt));try validateIntrinsic();if let predecessor{try validateSuccessor(of:predecessor)}
    }
    func validateIntrinsic()throws{try LightingLimitsV1.id(recordID);try LightingLimitsV1.id(claimID);try LightingLimitsV1.id(subjectAssetID);try observation?.validate();try measurement?.validate();try derivedFact?.validate();try criterion?.validate();try externalAttestation?.validate();try predecessorSHA256.map(LightingLimitsV1.digest);try reviewedBy.validate();try LightingLimitsV1.instant(recordedAt);let shape:Bool;switch tier{case .observed:shape=observation != nil&&measurement==nil&&derivedFact==nil&&criterion==nil&&screeningDisposition==nil&&externalAttestation==nil;case .measured:shape=observation != nil&&measurement != nil&&derivedFact==nil&&criterion==nil&&screeningDisposition==nil&&externalAttestation==nil;case .derived:shape=observation != nil&&measurement != nil&&derivedFact != nil&&criterion==nil&&screeningDisposition==nil&&externalAttestation==nil;case .screened:shape=observation != nil&&measurement != nil&&criterion != nil&&screeningDisposition != nil&&externalAttestation==nil;case .externallyAttested:shape=externalAttestation != nil&&observation != nil&&measurement==nil&&derivedFact==nil&&criterion==nil&&screeningDisposition==nil};guard schemaVersion==Self.schemaVersion,shape,observation?.workspaceID==workspaceID,observation?.assetID==subjectAssetID,measurement.map{$0.workspaceID==workspaceID} ?? true,derivedFact.map{$0.workspaceID==workspaceID} ?? true,criterion.map{$0.workspaceID==workspaceID} ?? true,externalAttestation.map{$0.workspaceID==workspaceID} ?? true,reviewedBy.workspaceID==workspaceID,reviewedBy.responsibility == .reviewedBy,(revision==1)==(supersedesRecordID==nil&&predecessorSHA256==nil),claimSHA256==(try LightingCanonicalCodecV1.sha256(basis))else{throw LightingContractFailureV1.forbiddenClaim}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validateIntrinsic();try validateIntrinsic();guard workspaceID==predecessor.workspaceID,claimID==predecessor.claimID,subjectAssetID==predecessor.subjectAssetID,recordID != predecessor.recordID,supersedesRecordID==predecessor.recordID,predecessorSHA256==predecessor.claimSHA256,revision==(try LightingLimitsV1.next(predecessor.revision)),mutationID != predecessor.mutationID,recordedAt>=predecessor.recordedAt else{throw LightingContractFailureV1.invalidSuccessor}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,recordID:recordID,claimID:claimID,workspaceID:workspaceID,subjectAssetID:subjectAssetID,tier:tier,observation:observation,measurement:measurement,derivedFact:derivedFact,criterion:criterion,screeningDisposition:screeningDisposition,externalAttestation:externalAttestation,supersedesRecordID:supersedesRecordID,predecessorSHA256:predecessorSHA256,revision:revision,mutationID:mutationID,reviewedBy:reviewedBy,recordedAt:recordedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let recordID:UUID;let claimID:UUID;let workspaceID:WorkspaceID;let subjectAssetID:UUID;let tier:LightingClaimTierV1;let observation:LightingObservationReferenceV1?;let measurement:LightingMeasurementClaimReferenceV1?;let derivedFact:DerivedFactProvenanceV1?;let criterion:CriterionReferenceV1?;let screeningDisposition:LightingScreeningDispositionV1?;let externalAttestation:LightingAttestationReferenceV1?;let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let reviewedBy:ActorSnapshotV1;let recordedAt:Date}
}

enum LightingClaimAdmissionV1{
    static func validateObserved(_ claim:LightingClaimStateV1,observation:LightingObservationV1)throws{
        try claim.validateIntrinsic();try observation.validateIntrinsic()
        guard claim.tier == .observed,claim.workspaceID==observation.workspaceID,
              claim.subjectAssetID==observation.assetID,
              claim.observation==(try LightingObservationReferenceV1(observation)) else{
            throw LightingContractFailureV1.forbiddenClaim
        }
    }
    static func validateMeasured(_ claim:LightingClaimStateV1,observation:LightingObservationV1,
                                 plan:MeasurementPlanV1,captures:[MeasurementCaptureV1],
                                 bindings:[LightingMeasurementCaptureBindingV1],protocolRelease:MeasurementProtocolReleaseV1,
                                 instrument:InstrumentReferenceV1,
                                 calibration:CalibrationStatusSnapshotV1,
                                 quality:[MeasurementQualityAssessmentV1])throws{
        try validateMeasurementBasis(claim,observation:observation,plan:plan,captures:captures,
                                     bindings:bindings,protocolRelease:protocolRelease,instrument:instrument,
                                     calibration:calibration,quality:quality)
        guard claim.tier == .measured else{throw LightingContractFailureV1.forbiddenClaim}
    }
    static func validateDerived(_ claim:LightingClaimStateV1,observation:LightingObservationV1,
                                plan:MeasurementPlanV1,captures:[MeasurementCaptureV1],
                                bindings:[LightingMeasurementCaptureBindingV1],protocolRelease:MeasurementProtocolReleaseV1,
                                evaluator:DerivedFactEvaluatorDescriptorV1,instrument:InstrumentReferenceV1,
                                calibration:CalibrationStatusSnapshotV1,
                                quality:[MeasurementQualityAssessmentV1])throws{
        try validateMeasurementBasis(claim,observation:observation,plan:plan,captures:captures,
                                     bindings:bindings,protocolRelease:protocolRelease,instrument:instrument,
                                     calibration:calibration,quality:quality)
        try evaluator.validate()
        guard claim.tier == .derived,let provenance=claim.derivedFact,
              evaluator.workspaceID==claim.workspaceID,
              provenance.protocolReleaseID==protocolRelease.releaseID,
              provenance.evaluatorDescriptorID==evaluator.descriptorID,
              provenance.disposition == .evaluated,
              provenance.inputs.count==captures.count else{throw LightingContractFailureV1.forbiddenClaim}
        let capturesByID=Dictionary(grouping:captures,by:\.captureID)
        for input in provenance.inputs {
            guard let capture=capturesByID[input.sampleID]?.only,input.state == .present,
                  let binding=bindings.first(where:{$0.captureID==capture.captureID}),
                  input.sampleOrdinal==binding.sampleOrdinal,
                  input.measurement==capture.measurement else{throw LightingContractFailureV1.staleReference}
        }
    }
    private static func validateMeasurementBasis(_ claim:LightingClaimStateV1,observation:LightingObservationV1,
                                 plan:MeasurementPlanV1,captures:[MeasurementCaptureV1],
                                 bindings:[LightingMeasurementCaptureBindingV1],protocolRelease:MeasurementProtocolReleaseV1,
                                 instrument:InstrumentReferenceV1,calibration:CalibrationStatusSnapshotV1,
                                 quality:[MeasurementQualityAssessmentV1])throws{
        try claim.validateIntrinsic();try observation.validateIntrinsic()
        try plan.validateCompleteCaptures(captures,bindings:bindings,protocolRelease:protocolRelease,
                                          instrument:instrument,calibration:calibration,quality:quality)
        guard claim.workspaceID==plan.workspaceID,
              claim.subjectAssetID==observation.assetID,
              claim.observation==(try LightingObservationReferenceV1(observation)),
              let measured=claim.measurement,measured.workspaceID==plan.workspaceID,
              measured.planID==plan.planID,measured.planRevision==plan.revision,
              measured.planSHA256==plan.planSHA256,measured.captures==bindings else{
            throw LightingContractFailureV1.forbiddenClaim
        }
    }
    static func validateScreened(_ claim:LightingClaimStateV1,
                                 observation:LightingObservationV1,plan:MeasurementPlanV1,
                                 captures:[MeasurementCaptureV1],bindings:[LightingMeasurementCaptureBindingV1],
                                 protocolRelease:MeasurementProtocolReleaseV1,instrument:InstrumentReferenceV1,
                                 calibration:CalibrationStatusSnapshotV1,quality:[MeasurementQualityAssessmentV1],
                                 classification:FindingClassificationBindingV1,
                                 criterion:CriterionReferenceV1,authority:AuthoritySourceReleaseV1,
                                 basis:RequirementBasisBindingV1,
                                 applicability:ApplicabilityContextSnapshotV1,
                                 scope:AssessmentScopeSnapshotV1)throws{
        try validateMeasurementBasis(claim,observation:observation,plan:plan,captures:captures,
                                     bindings:bindings,protocolRelease:protocolRelease,instrument:instrument,
                                     calibration:calibration,quality:quality)
        try classification.validate()
        try criterion.validate(authority:authority,basis:basis,applicability:applicability,scope:scope)
        guard claim.tier == .screened,claim.workspaceID==classification.workspaceID,
              claim.criterion==criterion,classification.criterionID==criterion.criterionID,
              criterion.protocolReference==(try MeasurementProtocolReferenceV1(protocolRelease)),
              classification.applicabilityContextID==criterion.applicabilitySnapshotID,
              classification.assessmentScopeID==criterion.assessmentScopeID,
              claim.screeningDisposition==(try LightingScreeningDispositionV1(classification.result)) else{
            throw LightingContractFailureV1.forbiddenClaim
        }
    }
    static func validateExternallyAttested(_ claim:LightingClaimStateV1,
                                           attestation:AttestationV1)throws{
        try claim.validateIntrinsic();try attestation.validate()
        guard claim.tier == .externallyAttested,
              claim.externalAttestation==(try LightingAttestationReferenceV1(attestation)) else{
            throw LightingContractFailureV1.forbiddenClaim
        }
    }
    static func validateObservedReference(_ claim:LightingClaimStateV1,
                                          observation:LightingObservationV1)throws{
        try observation.validateIntrinsic()
        guard claim.workspaceID==observation.workspaceID,
              claim.subjectAssetID==observation.assetID,
              claim.observation==(try LightingObservationReferenceV1(observation)) else{
            throw LightingContractFailureV1.staleReference
        }
    }
}

enum LightingClaimAdmissionClosureV1: Codable, Equatable, Sendable {
    case observed(observation: LightingObservationV1)
    case measured(observation: LightingObservationV1, plan: MeasurementPlanV1,
                  protocolRelease: MeasurementProtocolReleaseV1, captures: [MeasurementCaptureV1],
                  bindings: [LightingMeasurementCaptureBindingV1], instrument: InstrumentReferenceV1,
                  calibration: CalibrationStatusSnapshotV1, quality: [MeasurementQualityAssessmentV1])
    case derived(observation: LightingObservationV1, plan: MeasurementPlanV1,
                 protocolRelease: MeasurementProtocolReleaseV1, evaluator: DerivedFactEvaluatorDescriptorV1,
                 captures: [MeasurementCaptureV1], bindings: [LightingMeasurementCaptureBindingV1],
                 instrument: InstrumentReferenceV1, calibration: CalibrationStatusSnapshotV1,
                 quality: [MeasurementQualityAssessmentV1])
    case screened(observation: LightingObservationV1, plan: MeasurementPlanV1,
                  protocolRelease: MeasurementProtocolReleaseV1, captures: [MeasurementCaptureV1],
                  bindings: [LightingMeasurementCaptureBindingV1], instrument: InstrumentReferenceV1,
                  calibration: CalibrationStatusSnapshotV1, quality: [MeasurementQualityAssessmentV1],
                  classification: FindingClassificationBindingV1, criterion: CriterionReferenceV1,
                  authority: AuthoritySourceReleaseV1, basis: RequirementBasisBindingV1,
                  applicability: ApplicabilityContextSnapshotV1, scope: AssessmentScopeSnapshotV1)
    case externallyAttested(observation: LightingObservationV1, attestation: AttestationV1)

    func validate(claim: LightingClaimStateV1) throws {
        switch self {
        case .observed(let observation):
            try LightingClaimAdmissionV1.validateObserved(claim, observation: observation)
        case .measured(let observation,let plan,let protocolRelease,let captures,let bindings,let instrument,let calibration,let quality):
            try LightingClaimAdmissionV1.validateMeasured(claim,observation:observation,plan:plan,captures:captures,bindings:bindings,protocolRelease:protocolRelease,instrument:instrument,calibration:calibration,quality:quality)
        case .derived(let observation,let plan,let protocolRelease,let evaluator,let captures,let bindings,let instrument,let calibration,let quality):
            try LightingClaimAdmissionV1.validateDerived(claim,observation:observation,plan:plan,captures:captures,bindings:bindings,protocolRelease:protocolRelease,evaluator:evaluator,instrument:instrument,calibration:calibration,quality:quality)
        case .screened(let observation,let plan,let protocolRelease,let captures,let bindings,let instrument,let calibration,let quality,let classification,let criterion,let authority,let basis,let applicability,let scope):
            try LightingClaimAdmissionV1.validateScreened(claim,observation:observation,plan:plan,captures:captures,bindings:bindings,protocolRelease:protocolRelease,instrument:instrument,calibration:calibration,quality:quality,classification:classification,criterion:criterion,authority:authority,basis:basis,applicability:applicability,scope:scope)
        case .externallyAttested(let observation,let attestation):
            try LightingClaimAdmissionV1.validateObservedReference(claim, observation: observation)
            try LightingClaimAdmissionV1.validateExternallyAttested(claim,attestation:attestation)
        }
    }
}

enum LightingSafetyIntentV1:String,Codable,CaseIterable,Hashable,Sendable{case observeFromAuthorizedPosition="OBSERVE_FROM_AUTHORIZED_POSITION";case touchEnergizedEquipment="TOUCH_ENERGIZED_EQUIPMENT";case openEquipment="OPEN_EQUIPMENT";case climb="CLIMB";case probe="PROBE";case repair="REPAIR";case enterActiveTraffic="ENTER_ACTIVE_TRAFFIC"}
enum LightingSafetyStopReasonV1:String,Codable,CaseIterable,Hashable,Sendable{case siteAuthorityRequired="SITE_AUTHORITY_REQUIRED";case controlPlanRequired="CONTROL_PLAN_REQUIRED";case energizedWorkNotAuthorized="ENERGIZED_WORK_NOT_AUTHORIZED";case trafficControlNotAuthorized="TRAFFIC_CONTROL_NOT_AUTHORIZED"}
struct LightingSafetyAuthorityV1:Codable,Equatable,Hashable,Sendable{let siteAuthoritySHA256:String?;let applicableControlPlanSHA256:String?;let energizedWorkAuthorized:Bool;let trafficControlAuthorized:Bool}
enum LightingSafetyGateV1{static func requireAllowed(_ intent:LightingSafetyIntentV1,authority:LightingSafetyAuthorityV1)throws{if intent == .observeFromAuthorizedPosition{return};guard authority.siteAuthoritySHA256.map(MutationEnvelopeV1.isSHA256)==true,authority.applicableControlPlanSHA256.map(MutationEnvelopeV1.isSHA256)==true else{throw LightingContractFailureV1.safetyStop};switch intent{case .touchEnergizedEquipment,.openEquipment,.climb,.probe,.repair:guard authority.energizedWorkAuthorized else{throw LightingContractFailureV1.safetyStop};case .enterActiveTraffic:guard authority.trafficControlAuthorized else{throw LightingContractFailureV1.safetyStop};case .observeFromAuthorizedPosition:break}}}

private extension Array { var only: Element? { count == 1 ? self[0] : nil } }

private protocol LightingValidatableV1{func validateLighting()throws}
extension LightingSystemV1:LightingValidatableV1{fileprivate func validateLighting()throws{try validateIntrinsic()}}
extension LightingObservationV1:LightingValidatableV1{fileprivate func validateLighting()throws{try validateIntrinsic()}}
extension LightingIssueV1:LightingValidatableV1{fileprivate func validateLighting()throws{try validateIntrinsic()}}
extension MeasurementPlanV1:LightingValidatableV1{fileprivate func validateLighting()throws{try validateIntrinsic()}}
extension LightingClaimStateV1:LightingValidatableV1{fileprivate func validateLighting()throws{try validateIntrinsic()}}
enum LightingCanonicalCodecV1{
    static func encode<T:Encodable>(_ value:T)throws->Data{let data=try WorkspaceMutationCanonicalV1.data(value);guard data.count<=LightingLimitsV1.maximumCanonicalBytes else{throw LightingContractFailureV1.limitExceeded};return data}
    static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=LightingLimitsV1.maximumCanonicalBytes else{throw LightingContractFailureV1.limitExceeded};let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);if let validatable=value as? any LightingValidatableV1{try validatable.validateLighting()};guard try encode(value)==data else{throw LightingContractFailureV1.nonCanonicalData};return value}
    static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}
}
// MARK: - C32 assistance lighting boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Lighting_LightingContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotClaimLightingOperation = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Domain_Lighting_LightingContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}
