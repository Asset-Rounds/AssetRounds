import Foundation

enum C50IncumbentFileExchangeWholeSignDeletionRuleV1 {
    static let excludesSceneRouteState = C34SceneNavigationCompatibilityBoundaryV1.validate()
    static let canonicalImportedRowsFollowTheirSubjectOwners = true
    static let adapterLayerDeletesCanonicalRows = false
    static let adapterLayerDeletesImmutableMutationHistory = false
    static let ordinaryDeletionIsNotWorkspaceErase = true
}

struct DeletionSitePayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
}

enum C49WorkResourceWholeSignDeletionRuleV1 {
    static func mayPhysicallyDeleteAcceptedRow(isWorkspaceErase: Bool) -> Bool {
        isWorkspaceErase
    }

    static let ordinaryDeletionPreservesSubjectHistory = true
}

struct PackageEvolutionDeletionInventoryV1: Equatable, Sendable {
    let releaseRecordIDs: Set<UUID>
    let sandboxRunIDs: Set<UUID>
    let promotionReceiptIDs: Set<UUID>
    let pointerIDs: Set<UUID>
    static let empty = Self(releaseRecordIDs: [], sandboxRunIDs: [], promotionReceiptIDs: [], pointerIDs: [])
}

struct MeasurementIntegrityDeletionInventoryV1: Equatable, Sendable {
    let instrumentReferences: Int
    let calibrationSnapshots: Int
    let measurementCaptures: Int
    let measurementSeries: Int
    let qualityAssessments: Int
}

struct PrivacyTransformDeletionInventoryV1: Equatable, Sendable {
    let policies: Int; let regions: Int; let manifests: Int; let reviewReceipts: Int
    static let empty = Self(policies: 0, regions: 0, manifests: 0, reviewReceipts: 0)
}
struct ClientCapabilityDeletionInventoryV1:Equatable,Sendable{let profiles:Int;let policies:Int;let dispositions:Int;let decisions:Int;static let empty=Self(profiles:0,policies:0,dispositions:0,decisions:0)}
extension WholeSignDeletionRule{static func validateClientCapabilityLifecycle(before:ClientCapabilityDeletionInventoryV1,after:ClientCapabilityDeletionInventoryV1,workspaceErase:Bool)throws{guard workspaceErase ? after == .empty:before == after else{throw WholeSignDeletionRuleError.invalidGraph}}}
struct FieldReferenceDeletionInventoryV1:Equatable,Sendable{let releaseIDs:Set<UUID>;let bindingIDs:Set<UUID>;let retainedReleaseIDs:Set<UUID>;static let empty=Self(releaseIDs:[],bindingIDs:[],retainedReleaseIDs:[])}
struct AccessibleDocumentDeletionInventoryV1:Equatable,Sendable{let receiptIDs:Set<UUID>;let outputSHA256:Set<String>;static let empty=Self(receiptIDs:[],outputSHA256:[])}
struct SurveyDefinitionDeletionInventoryV1:Equatable,Sendable{let identityIDs:Set<UUID>;let releaseIDs:Set<UUID>;static let empty=Self(identityIDs:[],releaseIDs:[])}
struct SurveySessionDeletionInventoryV1:Equatable,Sendable{let sessionIDs:Set<UUID>;let captureIDs:Set<UUID>;let provisionalSubjectIDs:Set<UUID>;let promotionReceiptIDs:Set<UUID>;let publicationSnapshotIDs:Set<UUID>;static let empty=Self(sessionIDs:[],captureIDs:[],provisionalSubjectIDs:[],promotionReceiptIDs:[],publicationSnapshotIDs:[])}
struct AssetLocatorDeletionInventoryV1: Equatable, Sendable {
    let locatorIDs: Set<UUID>
    let receiptIDs: Set<UUID>
    let assetIDs: Set<UUID>

    static let empty = Self(locatorIDs: [], receiptIDs: [], assetIDs: [])

    init(locators: [AssetLocatorV1], receipts: [LocatorBindingReceiptV1]) throws {
        try AssetLocatorLifecycleClosureV1(
            locators: locators, receipts: receipts
        ).validate()
        locatorIDs = Set(locators.map(\.locatorID))
        receiptIDs = Set(receipts.map(\.receiptID))
        assetIDs = Set(locators.map(\.assetID))
    }
}

/// Schedule rows are not ordinary asset/site cascade targets.  This
/// inventory makes the retention boundary explicit for delete previews and
/// lets workspace Erase prove that both durable families were removed.
struct ScheduleDeletionInventoryV1: Equatable, Sendable {
    let releaseIDs: Set<UUID>
    let occurrenceEventIDs: Set<UUID>
    let exceptionCalendarReleaseIDs: Set<UUID>
    let scheduleOverrideEventIDs: Set<UUID>

    static let empty = Self(
        releaseIDs: [], occurrenceEventIDs: [], exceptionCalendarReleaseIDs: [],
        scheduleOverrideEventIDs: []
    )

    init(
        definitions: [ScheduleDefinitionReleaseV1],
        history: [OccurrenceHistoryEventV1],
        calendars: [ExceptionCalendarReleaseV1],
        overrides: [ScheduleOverrideEventV1]
    ) throws {
        try ScheduleLifecycleClosureV1(
            definitions: definitions, history: history
        ).validate()
        for group in Dictionary(grouping: calendars, by: \.calendarID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1 else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            if ordered.count > 1 {
                for index in 1..<ordered.count {
                    try ordered[index].validateSuccessor(of: ordered[index - 1])
                }
            }
        }
        let definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.releaseID, $0) })
        for value in overrides {
            guard let release = definitionsByID[value.scheduleRelease.releaseID],
                  release.releaseSHA256 == value.scheduleRelease.releaseSHA256 else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
        }
        guard C51ScheduleBackupClosureV1.validatesAdvancedCalendarReferences(
            definitions: definitions, calendars: calendars
        ) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        _ = try ScheduleOverridePrecedenceV1.activeEvents(overrides)
        releaseIDs = Set(definitions.map(\.releaseID))
        occurrenceEventIDs = Set(history.map(\.eventID))
        exceptionCalendarReleaseIDs = Set(calendars.map(\.releaseID))
        scheduleOverrideEventIDs = Set(overrides.map(\.eventID))
    }
}

extension WholeSignDeletionRule {
    static func validateScheduleLifecycle(
        before: ScheduleDeletionInventoryV1,
        after: ScheduleDeletionInventoryV1,
        workspaceErase: Bool
    ) throws {
        try ScheduleDeletionLedgerPolicyV1.validate()
        guard C51ScheduleBackupClosureV1.embeddedCanonicalComponents.count == 6,
              ScheduleDeletionIntentBoundaryV1
                .ordinaryDeletionPreservesCalendarOverrideBasisAndReceiptClosure else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        if workspaceErase {
            guard after == .empty else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            return
        }
        // A normal asset/site delete does not delete schedule definitions or
        // occurrence history.  Keeping both sets exactly preserves every
        // immutable release and append-only event without dangling refs.
        guard after == before else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
    }
}
extension WholeSignDeletionRule {
    static func validateAssetLocatorLifecycle(
        before: AssetLocatorDeletionInventoryV1,
        after: AssetLocatorDeletionInventoryV1,
        workspaceErase: Bool
    ) throws {
        try AssetLocatorDeletionLedgerPolicyV1.validate()
        if workspaceErase {
            guard after == .empty else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            return
        }
        guard after.locatorIDs.isSubset(of: before.locatorIDs),
              after.receiptIDs.isSubset(of: before.receiptIDs),
              after.assetIDs.isSubset(of: before.assetIDs) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
    }
}
extension WholeSignDeletionRule{static func validateAccessibleDocumentLifecycle(before:AccessibleDocumentDeletionInventoryV1,after:AccessibleDocumentDeletionInventoryV1,workspaceErase:Bool,authorizedPrivacyRemoval:Bool=false)throws{if workspaceErase{guard after == .empty else{throw WholeSignDeletionRuleError.invalidGraph};return};if authorizedPrivacyRemoval{return};guard after==before else{throw WholeSignDeletionRuleError.invalidGraph}}}
extension WholeSignDeletionRule{static func validateFieldReferenceLifecycle(before:FieldReferenceDeletionInventoryV1,after:FieldReferenceDeletionInventoryV1,workspaceErase:Bool)throws{if workspaceErase{guard after == .empty else{throw WholeSignDeletionRuleError.invalidGraph};return};guard after.bindingIDs==before.bindingIDs,after.retainedReleaseIDs==before.retainedReleaseIDs,before.retainedReleaseIDs.isSubset(of:after.releaseIDs)else{throw WholeSignDeletionRuleError.invalidGraph}}}
extension WholeSignDeletionRule{static func validateSurveyDefinitionLifecycle(before:SurveyDefinitionDeletionInventoryV1,after:SurveyDefinitionDeletionInventoryV1,workspaceErase:Bool)throws{if workspaceErase{guard after == .empty else{throw WholeSignDeletionRuleError.invalidGraph};return};guard after==before else{throw WholeSignDeletionRuleError.invalidGraph}}}
extension WholeSignDeletionRule{static func validateSurveySessionLifecycle(before:SurveySessionDeletionInventoryV1,after:SurveySessionDeletionInventoryV1,workspaceErase:Bool)throws{if workspaceErase{guard after == .empty else{throw WholeSignDeletionRuleError.invalidGraph};return};guard SurveySessionEraseBoundaryV1.atomicFamilyCount==5,SurveySessionEraseBoundaryV1.ordinaryDeletionPreservesPublicationAndCaptureHistory,after==before else{throw WholeSignDeletionRuleError.invalidGraph}}}

enum PrivacyTransformDeletionAuthorityV1: Sendable { case ordinaryDelete, workspaceErase }

extension WholeSignDeletionRule {
    static func validatePrivacyTransformLifecycle(authority: PrivacyTransformDeletionAuthorityV1, before: PrivacyTransformDeletionInventoryV1, after: PrivacyTransformDeletionInventoryV1) throws {
        switch authority {
        case .ordinaryDelete: guard before == after else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase: guard after == .empty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }
}

enum MeasurementIntegrityDeletionAuthorityV1: Sendable { case ordinaryAssetOrSiteDelete, workspaceErase }

extension WholeSignDeletionRule {
    static func validateMeasurementIntegrityLifecycle(
        authority: MeasurementIntegrityDeletionAuthorityV1,
        before: MeasurementIntegrityDeletionInventoryV1,
        after: MeasurementIntegrityDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard before == after else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after == .init(instrumentReferences: 0, calibrationSnapshots: 0, measurementCaptures: 0, measurementSeries: 0, qualityAssessments: 0) else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
        }
    }
}

extension WholeSignDeletionRule {
    enum PackageEvolutionDeletionAuthorityV1: Sendable { case ordinaryAssetOrSiteDelete, workspaceErase }
    static func validatePackageEvolutionLifecycle(
        authority: PackageEvolutionDeletionAuthorityV1,
        before: PackageEvolutionDeletionInventoryV1,
        after: PackageEvolutionDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard before == after else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after == .empty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }
}

struct DeletionAssetPayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let siteID: UUID
}

struct DeletionEvidencePayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let recordID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
}

struct WholeSignDeletionRuleInput: Codable, Equatable, Sendable {
    let assetID: UUID
    let deletionID: UUID
    let deletedAt: Date
    let generationID: UUID
    let sites: [DeletionSitePayloadV1]
    let assets: [DeletionAssetPayloadV1]
    let records: [WorkflowRecordPayloadV1]
    let evidence: [DeletionEvidencePayloadV1]
    let issues: [IssuePayloadV1]
    let packets: [PacketPayloadV1]
    let reports: [ReportPayloadV1]
}

struct WholeSignDeletionPlan: Codable, Equatable, Sendable {
    let assetID: UUID
    let evidenceIDs: [UUID]
    let intent: DeletionIntentV1
    let issueIDs: [UUID]
    let packetIDsToDelete: [UUID]
    let reportIDs: [UUID]
    let siteIDToDelete: UUID?
    let workflowRecordIDs: [UUID]
}

struct ExplicitSiteDeletionInputV1: Equatable, Sendable {
    let siteID: UUID
    let generationID: UUID
    let deletionID: UUID
    let deletedAt: Date
    let siteSchemaVersion: Int
    let label: String
    let address: String?
    let timeZoneID: String?
    let createdAt: Date
    let updatedAt: Date
    let siteAssets: [DeletionAssetPayloadV1]
    let assetPlans: [WholeSignDeletionPlan]
}

struct ExplicitSiteDeletionPreviewV1: Equatable, Sendable {
    let siteID: UUID
    let generationID: UUID
    let deletionID: UUID
    let deletedAt: Date
    let siteSchemaVersion: Int
    let label: String
    let address: String?
    let timeZoneID: String?
    let createdAt: Date
    let updatedAt: Date
    let assetPlans: [WholeSignDeletionPlan]
    let ledgerEntries: [DeletionLedgerEntryV2]
    let schemaVersion: Int
}

enum WholeSignDeletionRuleError: Error, Equatable {
    case invalidGraph
}

enum PartyAccountabilityDeletionAuthorityV1: Equatable, Sendable {
    case ordinaryAssetOrSiteDelete
    case workspaceErase
}

struct PartyAccountabilityDeletionInventoryV1: Equatable, Sendable {
    let servicePartyIDs: Set<UUID>
    let sitePartyRoleEventIDs: Set<UUID>
    let actorSnapshotIDs: Set<UUID>
    let qualificationSnapshotIDs: Set<UUID>
    let signoffSnapshotIDs: Set<UUID>

    var isEmpty: Bool {
        servicePartyIDs.isEmpty && sitePartyRoleEventIDs.isEmpty
            && actorSnapshotIDs.isEmpty && qualificationSnapshotIDs.isEmpty
            && signoffSnapshotIDs.isEmpty
    }
}

struct AssetSemanticDeletionInventoryV1: Equatable, Sendable {
    let kindBindingEventIDs: Set<UUID>
    let workflowCapabilityBindingEventIDs: Set<UUID>
    let productIdentityIDs: Set<UUID>
    let lifecycleEventIDs: Set<UUID>
    let successorLinkIDs: Set<UUID>
    let workSubjectScopeSnapshotIDs: Set<UUID>

    var isEmpty: Bool {
        kindBindingEventIDs.isEmpty && workflowCapabilityBindingEventIDs.isEmpty
            && productIdentityIDs.isEmpty && lifecycleEventIDs.isEmpty
            && successorLinkIDs.isEmpty && workSubjectScopeSnapshotIDs.isEmpty
    }
}

struct AuthorityCriterionDeletionInventoryV1: Equatable, Sendable {
    let recordIDsByKind: [V11BackupAuthorityCriterionRecordV1.Kind: Set<UUID>]
    var isEmpty: Bool { recordIDsByKind.values.allSatisfy(\.isEmpty) }
}

struct FunctionalRelationshipDeletionInventoryV1: Equatable, Sendable {
    let descriptorReleaseIDs: Set<UUID>
    let eventIDs: Set<UUID>
    var isEmpty: Bool { descriptorReleaseIDs.isEmpty && eventIDs.isEmpty }
}

struct EvidenceAssuranceDeletionInventoryV1: Equatable, Sendable {
    let visibilityIDs: Set<UUID>; let linkIDs: Set<UUID>
    let manifestIDs: Set<UUID>; let attestationIDs: Set<UUID>
    var isEmpty: Bool { visibilityIDs.isEmpty && linkIDs.isEmpty && manifestIDs.isEmpty && attestationIDs.isEmpty }
}

struct InspectionReviewDeletionInventoryV1: Equatable, Sendable {
    let transitionIDs: Set<UUID>; let dispositionIDs: Set<UUID>; let requestRevisionIDs: Set<UUID>
    let policyReleaseIDs: Set<UUID>; let actionEventIDs: Set<UUID>
    var isEmpty: Bool { transitionIDs.isEmpty && dispositionIDs.isEmpty && requestRevisionIDs.isEmpty
        && policyReleaseIDs.isEmpty && actionEventIDs.isEmpty }
}

struct WorkPacketDeletionInventoryV1:Equatable,Sendable{let manifestIDs:Set<UUID>;let claimIDs:Set<UUID>;let leaseIDs:Set<UUID>;let releaseIDs:Set<UUID>;let handoffIDs:Set<UUID>}
struct FieldDraftDeletionInventoryV1: Equatable, Sendable {
    let draftIDs: Set<UUID>; let stageIDs: Set<UUID>; let sagaIDs: Set<UUID>
    let reservationIDs: Set<UUID>; let commitReceiptIDs: Set<UUID>; let discardReceiptIDs: Set<UUID>
    var isEmpty: Bool { draftIDs.isEmpty && stageIDs.isEmpty && sagaIDs.isEmpty && reservationIDs.isEmpty && commitReceiptIDs.isEmpty && discardReceiptIDs.isEmpty }
}

struct EvidenceAssuranceOrdinaryDeletionPreviewV1: Equatable, Sendable {
    let blockingManifestIDs: [UUID]
    let blockingAttestationIDs: [UUID]
    let persistentWriteOccurred = false
    var isBlocked: Bool { !blockingManifestIDs.isEmpty || !blockingAttestationIDs.isEmpty }
}

enum WholeSignDeletionRule {
    static func validatePartyAccountabilityLifecycle(
        authority: PartyAccountabilityDeletionAuthorityV1,
        before: PartyAccountabilityDeletionInventoryV1,
        after: PartyAccountabilityDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard after == before else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
        case .workspaceErase:
            guard after.isEmpty else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
        }
    }

    static func validateAssetSemanticLifecycle(
        authority: PartyAccountabilityDeletionAuthorityV1,
        before: AssetSemanticDeletionInventoryV1,
        after: AssetSemanticDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard after == before else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after.isEmpty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }

    static func validateAuthorityCriterionLifecycle(
        authority: PartyAccountabilityDeletionAuthorityV1,
        before: AuthorityCriterionDeletionInventoryV1,
        after: AuthorityCriterionDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard after == before else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after.isEmpty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }

    static func validateFunctionalRelationshipLifecycle(
        authority: PartyAccountabilityDeletionAuthorityV1,
        before: FunctionalRelationshipDeletionInventoryV1,
        after: FunctionalRelationshipDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard after == before else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after.isEmpty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }

    static func validateEvidenceAssuranceLifecycle(
        authority: PartyAccountabilityDeletionAuthorityV1,
        before: EvidenceAssuranceDeletionInventoryV1,
        after: EvidenceAssuranceDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard after == before else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after.isEmpty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }

    static func validateInspectionReviewLifecycle(
        authority: PartyAccountabilityDeletionAuthorityV1,
        before: InspectionReviewDeletionInventoryV1,
        after: InspectionReviewDeletionInventoryV1
    ) throws {
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard after == before else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after.isEmpty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }

    static func validateWorkPacketLifecycle(authority:PartyAccountabilityDeletionAuthorityV1,before:WorkPacketDeletionInventoryV1,after:WorkPacketDeletionInventoryV1)throws{try WorkPacketDeletionLedgerPolicyV1.validate();switch authority{case .ordinaryAssetOrSiteDelete:guard before==after else{throw WholeSignDeletionRuleError.invalidGraph};case .workspaceErase:guard after.manifestIDs.isEmpty,after.claimIDs.isEmpty,after.leaseIDs.isEmpty,after.releaseIDs.isEmpty,after.handoffIDs.isEmpty else{throw WholeSignDeletionRuleError.invalidGraph}}}

    static func validateFieldDraftLifecycle(authority: PartyAccountabilityDeletionAuthorityV1, before: FieldDraftDeletionInventoryV1, after: FieldDraftDeletionInventoryV1) throws {
        try FieldDraftDeletionLedgerPolicyV1.validate()
        switch authority {
        case .ordinaryAssetOrSiteDelete:
            guard before == after else { throw WholeSignDeletionRuleError.invalidGraph }
        case .workspaceErase:
            guard after.isEmpty else { throw WholeSignDeletionRuleError.invalidGraph }
        }
    }

    static func evidenceAssuranceOrdinaryDeletionPreview(
        manifests: [AssuranceManifestV1], attestations: [AttestationV1]
    ) -> EvidenceAssuranceOrdinaryDeletionPreviewV1 {
        .init(blockingManifestIDs: manifests.map(\.manifestID).sorted { $0.uuidString < $1.uuidString },
              blockingAttestationIDs: attestations.map(\.attestationID).sorted { $0.uuidString < $1.uuidString })
    }

    static func functionalRelationshipEndpointDeletionPreviews(
        assetID: UUID,
        assetSiteID: UUID,
        projection: CurrentFunctionalRelationshipProjectionV1,
        descriptors: [FunctionalRelationshipTypeDescriptorV1]
    ) throws -> [FunctionalRelationshipDispositionPreviewV1] {
        let descriptorByID = Dictionary(
            uniqueKeysWithValues: descriptors.map { ($0.descriptorReleaseID, $0) }
        )
        return try projection.currentRelationships.compactMap { relationship in
            guard relationship.sourceAssetID == assetID || relationship.targetAssetID == assetID,
                  let descriptor = descriptorByID[
                    relationship.descriptor.descriptorReleaseID
                  ] else { return nil }
            return try FunctionalRelationshipDispositionPreviewEngineV1.preview(
                change: .deleted, relationship: relationship,
                descriptor: descriptor, currentSiteID: assetSiteID
            )
        }
    }

    /// Ordinary asset/site deletion is deliberately not an Erase operation.
    /// Placement and composition event rows are append-only evidence and are
    /// therefore never returned as cascade targets. Active composition must be
    /// retired through the sole workspace writer before either endpoint can be
    /// deleted. A site with location/history rows requires a separate explicit
    /// hierarchy disposition rather than silently orphaning or deleting them.
    static func validateLocationDeletionNoCascade(
        deletingAssetID: UUID?,
        deletingSiteID: UUID?,
        liveAssetSiteByID: [UUID: UUID],
        locationNodes: [LocationNodeV1],
        placementEvents: [AssetPlacementEventV1],
        compositionEdges: [AssetCompositionEdgeV1]
    ) throws {
        guard (deletingAssetID == nil) != (deletingSiteID == nil),
              Set(locationNodes.map(\.id)).count == locationNodes.count,
              Set(placementEvents.map(\.id)).count == placementEvents.count,
              Set(compositionEdges.map(\.id)).count == compositionEdges.count else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        var placementTips: [UUID: AssetPlacementEventV1] = [:]
        do {
            try LocationHierarchyPolicyV1.validate(locationNodes)
            let histories = Dictionary(grouping: placementEvents, by: \.assetID)
            let liveAssetIDs = Set(liveAssetSiteByID.keys)
            guard liveAssetIDs.isSubset(of: Set(histories.keys)),
                  compositionEdges.filter(\.isActive).allSatisfy({
                      liveAssetIDs.contains($0.parentAssetID) && liveAssetIDs.contains($0.childAssetID)
                  }) else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            for (assetID, events) in histories {
                try AssetPlacementHistoryV1.validate(events)
                let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
                let referenced = Set(events.compactMap(\.predecessorEventID))
                guard let tip = events.first(where: { !referenced.contains($0.id) }) else {
                    throw WholeSignDeletionRuleError.invalidGraph
                }
                var visited = Set<UUID>()
                var cursor: AssetPlacementEventV1? = tip
                while let event = cursor {
                    guard visited.insert(event.id).inserted else {
                        throw WholeSignDeletionRuleError.invalidGraph
                    }
                    cursor = event.predecessorEventID.flatMap { byID[$0] }
                }
                guard visited.count == events.count else {
                    throw WholeSignDeletionRuleError.invalidGraph
                }
                placementTips[assetID] = tip
            }
            guard liveAssetSiteByID.allSatisfy({ assetID, siteID in
                placementTips[assetID]?.siteID == siteID
            }) else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            let nodesByID = Dictionary(uniqueKeysWithValues: locationNodes.map { ($0.id, $0) })
            guard placementEvents.allSatisfy({ event in
                guard let nodeID = event.locationNodeID,
                      let node = nodesByID[nodeID] else {
                    return event.locationNodeID == nil
                }
                return node.workspaceID == event.workspaceID && node.siteID == event.siteID
            }) else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            try AssetCompositionPolicyV1.validate(
                edges: compositionEdges,
                placementByAssetID: placementTips
            )
        } catch {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        if let deletingAssetID {
            guard !compositionEdges.contains(where: {
                $0.isActive && ($0.parentAssetID == deletingAssetID || $0.childAssetID == deletingAssetID)
            }) else {
                throw WholeSignDeletionRuleError.invalidGraph
            }
            // Placement history intentionally remains as an immutable reference
            // to the asset tombstone; it is not a deletion-ledger cascade target.
            return
        }
        guard let deletingSiteID else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        let siteAssetIDs = Set(liveAssetSiteByID.compactMap { assetID, siteID in
            siteID == deletingSiteID ? assetID : nil
        })
        guard
              siteAssetIDs.isEmpty,
              !locationNodes.contains(where: {
                  $0.siteID == deletingSiteID && $0.state == .active
              }),
              !compositionEdges.contains(where: {
                  $0.isActive && (siteAssetIDs.contains($0.parentAssetID)
                    || siteAssetIDs.contains($0.childAssetID))
              }) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        // Archived nodes and all placement history remain addressable through
        // the site tombstone. Erase, not ordinary delete, clears the generation.
    }

    static func makeExplicitSiteDeletionPreview(
        _ input: ExplicitSiteDeletionInputV1
    ) throws -> ExplicitSiteDeletionPreviewV1 {
        guard input.siteSchemaVersion == 1,
              input.updatedAt >= input.createdAt,
              input.deletedAt >= input.createdAt,
              !input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              unique(input.siteAssets.map(\.id)),
              input.siteAssets.allSatisfy({
                  $0.schemaVersion == 1 && $0.siteID == input.siteID
              }),
              Set(input.siteAssets.map(\.id)) == Set(input.assetPlans.map(\.assetID)),
              unique(input.assetPlans.map(\.assetID)),
              input.assetPlans.allSatisfy({ plan in
                  plan.intent.schemaVersion == 2
                    && plan.intent.generationID == input.generationID
                    && plan.intent.deletionID == input.deletionID
                    && plan.intent.ledgerEntries.allSatisfy({ $0.deletedAt == input.deletedAt })
                    && plan.siteIDToDelete == nil
              }) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        let relativePaths = input.assetPlans.flatMap { $0.intent.relativePaths }
        guard unique(relativePaths) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        let siteEntry = try DeletionLedgerEntryV2(
            identity: DeletionIdentityV2(kind: .site, id: input.siteID),
            deletedAt: input.deletedAt
        )
        let entries = (input.assetPlans.flatMap { $0.intent.ledgerEntries } + [siteEntry])
            .sorted { $0.identity < $1.identity }
        _ = try DeletionLedgerV2(entries: entries)
        return ExplicitSiteDeletionPreviewV1(
            siteID: input.siteID,
            generationID: input.generationID,
            deletionID: input.deletionID,
            deletedAt: input.deletedAt,
            siteSchemaVersion: input.siteSchemaVersion,
            label: input.label,
            address: input.address,
            timeZoneID: input.timeZoneID,
            createdAt: input.createdAt,
            updatedAt: input.updatedAt,
            assetPlans: input.assetPlans.sorted {
                canonicalID($0.assetID) < canonicalID($1.assetID)
            },
            ledgerEntries: entries,
            schemaVersion: 1
        )
    }

    static func makePlan(
        _ input: WholeSignDeletionRuleInput
    ) throws -> WholeSignDeletionPlan {
        guard validGlobalGraph(input),
              let asset = only(input.assets, where: { $0.id == input.assetID }),
              only(input.sites, where: { $0.id == asset.siteID }) != nil else {
            throw WholeSignDeletionRuleError.invalidGraph
        }

        let selectedRecords = input.records.filter { $0.assetID == asset.id }
        let recordIDs = Set(selectedRecords.map(\.id))
        let selectedEvidence = input.evidence.filter { recordIDs.contains($0.recordID) }
        let selectedIssues = input.issues.filter { $0.assetID == asset.id }
        let selectedPacketIDs = Set(input.packets.compactMap { packet in
            packetOwner(packet, records: input.records, reports: input.reports) == asset.id
                ? packet.id
                : nil
        })
        let selectedPackets = input.packets.filter { selectedPacketIDs.contains($0.id) }
        let selectedReports = input.reports.filter { selectedPacketIDs.contains($0.packetID) }

        guard selectedEvidence.count == input.evidence.filter({
                  recordIDs.contains($0.recordID)
              }).count,
              selectedIssues.allSatisfy({ recordIDs.contains($0.openedByRecordID) }),
              selectedIssues.allSatisfy({ issue in
                  issue.resolvedByRecordID.map(recordIDs.contains) ?? true
              }),
              selectedReports.allSatisfy({ recordIDs.contains($0.sourceRecordID) }),
              selectedRecords.allSatisfy({ record in
                  record.packetID.map(selectedPacketIDs.contains) ?? true
              }) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }

        let tombstones = selectedPackets
            .filter(\.evaluationCounted)
            .map { packet in
                PacketPayloadV1(
                    id: packet.id,
                    schemaVersion: packet.schemaVersion,
                    stableRootID: packet.stableRootID,
                    currentRecordID: nil,
                    evaluationCounted: true,
                    contentDeletedAt: input.deletedAt,
                    createdAt: packet.createdAt
                )
            }
            .sorted { canonicalID($0.id) < canonicalID($1.id) }
        let paths = (selectedEvidence.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath]
        } + selectedReports.flatMap { report in
            [report.snapshotRelativePath, report.pdfRelativePath].compactMap { $0 }
        }).sorted()
        guard Set(paths).count == paths.count,
              paths.allSatisfy(DeletionIntentEncoderV1.validRelativePath),
              tombstones.allSatisfy({ $0.contentDeletedAt == input.deletedAt }) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }

        let intent = DeletionIntentV1(
            assetID: asset.id,
            countedPacketTombstones: tombstones,
            deletionID: input.deletionID,
            generationID: input.generationID,
            ledgerEntries: try ledgerEntries(
                asset: asset,
                evidence: selectedEvidence,
                issues: selectedIssues,
                packets: selectedPackets,
                reports: selectedReports,
                records: selectedRecords,
                deletedAt: input.deletedAt
            ),
            phase: .prepared,
            relativePaths: paths,
            schemaVersion: 2
        )
        guard DeletionIntentEncoderV1.valid(intent) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        return WholeSignDeletionPlan(
            assetID: asset.id,
            evidenceIDs: sortedIDs(selectedEvidence.map(\.id)),
            intent: intent,
            issueIDs: sortedIDs(selectedIssues.map(\.id)),
            packetIDsToDelete: sortedIDs(
                selectedPackets.filter { !$0.evaluationCounted }.map(\.id)
            ),
            reportIDs: sortedIDs(selectedReports.map(\.id)),
            siteIDToDelete: nil,
            workflowRecordIDs: sortedIDs(selectedRecords.map(\.id))
        )
    }

    private static func validGlobalGraph(_ input: WholeSignDeletionRuleInput) -> Bool {
        guard !input.sites.isEmpty,
              !input.assets.isEmpty,
              unique(input.sites.map(\.id)),
              unique(input.assets.map(\.id)),
              unique(input.records.map(\.id)),
              unique(input.records.compactMap(\.revisesRecordID)),
              unique(input.evidence.map(\.id)),
              unique(input.issues.map(\.id)),
              unique(input.issues.map(\.openedByRecordID)),
              unique(input.packets.map(\.id)),
              unique(input.packets.map(\.stableRootID)),
              unique(input.packets.compactMap(\.currentRecordID)),
              unique(input.reports.map(\.id)),
              unique(input.reports.map(\.sourceRecordID)),
              unique(input.reports.compactMap(\.replacesReportID)),
              unique(input.records.compactMap(\.finalizationMutationID)),
              uniqueAcrossAuthorities(input),
              input.sites.allSatisfy({ $0.schemaVersion == 1 }),
              input.assets.allSatisfy({ asset in
                  asset.schemaVersion == 1
                    && exactlyOne(input.sites, where: { $0.id == asset.siteID })
              }),
              validRecords(input),
              validEvidence(input),
              validIssues(input),
              validPacketsAndReports(input) else {
            return false
        }
        return true
    }

    private static func ledgerEntries(
        asset: DeletionAssetPayloadV1,
        evidence: [DeletionEvidencePayloadV1],
        issues: [IssuePayloadV1],
        packets: [PacketPayloadV1],
        reports: [ReportPayloadV1],
        records: [WorkflowRecordPayloadV1],
        deletedAt: Date
    ) throws -> [DeletionLedgerEntryV2] {
        var identities = [try DeletionIdentityV2(kind: .asset, id: asset.id)]
        identities += try evidence.map {
            try DeletionIdentityV2(kind: .evidenceFile, id: $0.id)
        }
        identities += try issues.map {
            try DeletionIdentityV2(kind: .issue, id: $0.id)
        }
        identities += try packets.map {
            try DeletionIdentityV2(kind: .packet, id: $0.id)
        }
        identities += try reports.map {
            try DeletionIdentityV2(kind: .report, id: $0.id)
        }
        identities += try records.map {
            try DeletionIdentityV2(kind: .workflowRecord, id: $0.id)
        }
        return try identities.sorted().map {
            try DeletionLedgerEntryV2(identity: $0, deletedAt: deletedAt)
        }
    }

    private static func validRecords(_ input: WholeSignDeletionRuleInput) -> Bool {
        let assetsByID = Dictionary(uniqueKeysWithValues: input.assets.map { ($0.id, $0) })
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        let issuesByID = Dictionary(uniqueKeysWithValues: input.issues.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: input.packets.map { ($0.id, $0) })
        guard input.records.allSatisfy({ record in
            guard record.schemaVersion == 1,
                  assetsByID[record.assetID] != nil,
                  let revisionKind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  WorkflowStage(rawValue: record.stage) != nil,
                  let state = WorkflowState(rawValue: record.state),
                  let revisionRoot = recordsByID[record.recordRevisionRootID],
                  revisionRoot.assetID == record.assetID,
                  revisionRoot.revisionKind == WorkflowRevisionKind.original.rawValue,
                  revisionRoot.recordRevisionRootID == revisionRoot.id,
                  record.parentRecordID.map({
                      recordsByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.issueID.map({
                      issuesByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.packetID.map({ packetsByID[$0] != nil }) ?? true else {
                return false
            }
            guard validObservationAndTime(record) else { return false }
            switch state {
            case .draft:
                guard record.completedAt == nil else { return false }
            case .completed:
                guard record.completedAt.map({ $0 >= record.startedAt }) == true else {
                    return false
                }
            }
            switch revisionKind {
            case .original:
                return record.recordRevisionRootID == record.id
                    && record.revisesRecordID == nil
                    && record.evidenceSourceRecordID == nil
            case .clericalCorrection:
                guard let revisedID = record.revisesRecordID,
                      let sourceID = record.evidenceSourceRecordID,
                      let revised = recordsByID[revisedID],
                      let source = recordsByID[sourceID] else {
                    return false
                }
                return revised.assetID == record.assetID
                    && revised.recordRevisionRootID == record.recordRevisionRootID
                    && source.assetID == record.assetID
            }
        }) else {
            return false
        }
        let parentEdges = Dictionary(uniqueKeysWithValues: input.records.map {
            ($0.id, $0.parentRecordID)
        })
        let revisionEdges = Dictionary(uniqueKeysWithValues: input.records.map {
            ($0.id, $0.revisesRecordID)
        })
        let evidenceSourceEdges = Dictionary(uniqueKeysWithValues: input.records.map {
            ($0.id, $0.evidenceSourceRecordID)
        })
        return acyclic(parentEdges)
            && acyclic(revisionEdges)
            && acyclic(evidenceSourceEdges)
    }

    private static func validEvidence(_ input: WholeSignDeletionRuleInput) -> Bool {
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        return input.evidence.allSatisfy { value in
            let id = canonicalID(value.id)
            return value.schemaVersion == 1
                && recordsByID[value.recordID] != nil
                && !value.purposeKey.isEmpty
                && value.mimeType == MediaContractV1.durableMIMEType
                && value.relativePath == "evidence/\(id)/original.jpg"
                && value.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg"
                && value.byteCount > 0
                && value.thumbnailByteCount > 0
                && isLowercaseSHA256(value.sha256)
                && isLowercaseSHA256(value.thumbnailSHA256)
        }
    }

    private static func validIssues(_ input: WholeSignDeletionRuleInput) -> Bool {
        let assetsByID = Dictionary(uniqueKeysWithValues: input.assets.map { ($0.id, $0) })
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        return input.issues.allSatisfy { issue in
            issue.schemaVersion == 1
                && assetsByID[issue.assetID] != nil
                && recordsByID[issue.openedByRecordID]?.assetID == issue.assetID
                && (issue.resolvedByRecordID.map {
                    recordsByID[$0]?.assetID == issue.assetID
                } ?? true)
                && !issue.labelKey.isEmpty
                && !issue.labelDisplaySnapshot.isEmpty
                && IssueStatus(rawValue: issue.status) != nil
                && issue.updatedAt >= issue.createdAt
        }
    }

    private static func validPacketsAndReports(
        _ input: WholeSignDeletionRuleInput
    ) -> Bool {
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: input.packets.map { ($0.id, $0) })
        let reportsByID = Dictionary(uniqueKeysWithValues: input.reports.map { ($0.id, $0) })
        guard input.packets.allSatisfy({ packet in
            guard packet.schemaVersion == 1,
                  packet.createdAt <= (packet.contentDeletedAt ?? .distantFuture) else {
                return false
            }
            if let currentRecordID = packet.currentRecordID {
                return packet.contentDeletedAt == nil
                    && recordsByID[currentRecordID]?.packetID == packet.id
                    && packetOwner(packet, records: input.records, reports: input.reports) != nil
            }
            return packet.evaluationCounted
                && packet.contentDeletedAt != nil
                && input.records.allSatisfy { $0.packetID != packet.id }
                && input.reports.allSatisfy { $0.packetID != packet.id }
        }), input.reports.allSatisfy({ report in
            guard report.schemaVersion == 1,
                  let packet = packetsByID[report.packetID],
                  let source = recordsByID[report.sourceRecordID],
                  packet.currentRecordID != nil,
                  packetOwner(packet, records: input.records, reports: input.reports)
                    == source.assetID,
                  report.snapshotSchemaVersion == 1 || report.snapshotSchemaVersion == 2,
                  report.snapshotRelativePath
                    == "snapshots/\(canonicalID(report.id)).json",
                  isLowercaseSHA256(report.snapshotSHA256),
                  let state = ReportPDFState(rawValue: report.pdfState) else {
                return false
            }
            switch state {
            case .ready:
                return report.pdfRelativePath == "pdfs/\(canonicalID(report.id)).pdf"
                    && report.pdfSHA256.map(isLowercaseSHA256) == true
            case .pending, .failed:
                return report.pdfRelativePath == nil && report.pdfSHA256 == nil
            }
        }) else {
            return false
        }
        let replacementEdges = Dictionary(uniqueKeysWithValues: input.reports.map {
            ($0.id, $0.replacesReportID)
        })
        return acyclic(replacementEdges) && input.reports.allSatisfy { report in
            report.replacesReportID.map { replacedID in
                guard let replaced = reportsByID[replacedID] else { return false }
                return replaced.packetID == report.packetID
                    && replaced.createdAt <= report.createdAt
            } ?? true
        }
    }

    private static func packetOwner(
        _ packet: PacketPayloadV1,
        records: [WorkflowRecordPayloadV1],
        reports: [ReportPayloadV1]
    ) -> UUID? {
        var owners = Set<UUID>()
        if let currentRecordID = packet.currentRecordID,
           let record = records.first(where: { $0.id == currentRecordID }) {
            owners.insert(record.assetID)
        }
        for record in records where record.packetID == packet.id {
            owners.insert(record.assetID)
        }
        for report in reports where report.packetID == packet.id {
            if let record = records.first(where: { $0.id == report.sourceRecordID }) {
                owners.insert(record.assetID)
            }
        }
        return owners.count == 1 ? owners.first : nil
    }

    private static func validObservationAndTime(
        _ record: WorkflowRecordPayloadV1
    ) -> Bool {
        guard (record.observationBasisV1Data == nil)
                == (record.temporalContextV1Data == nil) else { return false }
        guard let basisData = record.observationBasisV1Data,
              let temporalData = record.temporalContextV1Data else { return true }
        do {
            let basis = try ObservationAndTimeCodecV1.decodeObservationBasis(basisData)
            let temporal = try ObservationAndTimeCodecV1.decodeTemporalContext(temporalData)
            return try ObservationAndTimeCodecV1.encode(basis) == basisData
                && ObservationAndTimeCodecV1.encode(temporal) == temporalData
        } catch {
            return false
        }
    }

    private static func uniqueAcrossAuthorities(
        _ input: WholeSignDeletionRuleInput
    ) -> Bool {
        let values = input.sites.map(\.id)
            + input.assets.map(\.id)
            + input.records.map(\.id)
            + input.evidence.map(\.id)
            + input.issues.map(\.id)
            + input.packets.map(\.id)
            + input.packets.map(\.stableRootID)
            + input.reports.map(\.id)
            + input.records.compactMap(\.finalizationMutationID)
            + [input.deletionID, input.generationID]
        return unique(values)
    }

    private static func acyclic(_ edges: [UUID: UUID?]) -> Bool {
        for start in edges.keys {
            var seen = Set<UUID>()
            var current: UUID? = start
            while let value = current {
                guard seen.insert(value).inserted else { return false }
                current = edges[value] ?? nil
            }
        }
        return true
    }

    private static func exactlyOne<T>(
        _ values: [T],
        where predicate: (T) -> Bool
    ) -> Bool {
        values.filter(predicate).count == 1
    }

    private static func only<T>(
        _ values: [T],
        where predicate: (T) -> Bool
    ) -> T? {
        let matches = values.filter(predicate)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private static func sortedIDs(_ values: [UUID]) -> [UUID] {
        values.sorted { canonicalID($0) < canonicalID($1) }
    }

    private static func canonicalID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_WholeSignDeletionRule {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_WholeSignDeletionRule_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}

enum C30EvidenceContextWholeSignDeletionRuleV1 {
    static let contextRowsAreWorkspaceScoped = true
    static let pairRowsAreWorkspaceScoped = true
    static let immutableHistoryRetainedForOrdinaryDeletion = true

    static func validate(workspaceID: WorkspaceID,
                         contexts: [EvidenceContextV1],
                         links: [PairedObservationLinkV1]) throws {
        guard contextRowsAreWorkspaceScoped, pairRowsAreWorkspaceScoped,
              immutableHistoryRetainedForOrdinaryDeletion,
              contexts.allSatisfy({ $0.workspaceID == workspaceID }),
              links.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw EvidenceContextFailureV1.wrongWorkspace
        }
        try contexts.forEach { try $0.validateIntrinsic() }
        try links.forEach { try $0.validateIntrinsic() }
    }
}

enum C31LightingWholeSignDeletionBoundaryV1 {
    static let topologyIsDeletedAsOneClosure = true
    static let ordinaryDeletionRetainsImmutableHistory = true
    static let orphanLightingRootsAreRejected = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        let roots = try LightingBackupRecordSetV1.decode(records)
        let workspaces = roots.systems.map(\.workspaceID)
            + roots.observations.map(\.workspaceID)
            + roots.issues.map(\.workspaceID)
            + roots.plans.map(\.workspaceID)
            + roots.claims.map(\.workspaceID)
        guard workspaces.allSatisfy({ $0 == workspaceID }),
              topologyIsDeletedAsOneClosure,
              ordinaryDeletionRetainsImmutableHistory,
              orphanLightingRootsAreRejected else {
            throw LightingContractFailureV1.wrongWorkspace
        }
    }
}
// MARK: - C32 assistance whole-sign deletion boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_WholeSignDeletionRule_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotBypassDeletionRules = true

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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Domain_Workflow_WholeSignDeletionRule_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

enum C45AcceptedLabelWholeSignBoundaryV1 { static let activeLocatorTruthMayBlockDeletion=true;static let generatedOutputPossessionIsNotClaimed=true }

enum C46OperationalContactBoundary_40{static let assetOrSiteCascadeDeletesPartyContacts=false;static let workspaceEraseOwnsRows=true}
enum C47ActivityContractWholeSignDeletionBoundaryV2 { static let unfinalizedMatchingSubjectGraphCanBeRemoved=true;static let finalizedAndSupersededHistoryCannotCascade=true;static let cancelledAndUnableHistoryCannotCascade=true;static let immutableActivityEvidenceCannotCascade=true;static let unrelatedActivitiesRemain=true }

enum C48PortableExchangeWholeSignDeletionRuleV2 {
    static func mayInvalidate(
        _ session: PortableExchangeSessionRecordV2,
        workspaceID: WorkspaceID,
        subjectID: String
    ) -> Bool {
        C48PortableExchangeDeletionIntentBoundaryV2.invalidatesSession(
            session,
            workspaceID: workspaceID,
            canonicalSubjectIdentity: subjectID
        )
    }
}
enum C52ServiceRequestBoundary_WholeSignDeletionRule {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}
