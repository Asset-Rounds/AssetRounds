import Foundation

struct PhysicalPlacementEpisodeIDV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let rawValue: UUID
    init(rawValue: UUID) throws { try LocationContractValidationV1.requireID(rawValue); self.rawValue = rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue.uuidString.lowercased() < rhs.rawValue.uuidString.lowercased() }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); try self.init(rawValue: c.decode(UUID.self)) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

enum PhysicalContinuityDispositionV1: String, Codable, CaseIterable, Sendable {
    case samePhysicalInstallation = "SAME_PHYSICAL_INSTALLATION"
    case physicalMove = "PHYSICAL_MOVE"
    case unknownReviewRequired = "UNKNOWN_REVIEW_REQUIRED"
}

enum AssetPlacementSourceV1: String, Codable, CaseIterable, Sendable {
    case manual = "MANUAL"
    case imported = "IMPORT"
    case surveyPromotion = "SURVEY_PROMOTION"
    case hierarchyRebase = "HIERARCHY_REBASE"
    case migratedBaseline = "MIGRATED_BASELINE"
    case semanticReversal = "SEMANTIC_REVERSAL"
}

struct AssetPlacementEventV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let id: UUID; let workspaceID: WorkspaceID; let assetID: UUID; let siteID: UUID
    let locationNodeID: UUID?; let predecessorEventID: UUID?; let source: AssetPlacementSourceV1
    let physicalEpisodeID: PhysicalPlacementEpisodeIDV1; let continuity: PhysicalContinuityDispositionV1
    let pathSnapshot: LocationPathSnapshotV1; let mutationID: MutationIDV1; let occurredAt: Date; let eventSHA256: String

    init(id: UUID, workspaceID: WorkspaceID, assetID: UUID, siteID: UUID, locationNodeID: UUID?, predecessorEventID: UUID?, source: AssetPlacementSourceV1, physicalEpisodeID: PhysicalPlacementEpisodeIDV1, continuity: PhysicalContinuityDispositionV1, pathSnapshot: LocationPathSnapshotV1, mutationID: MutationIDV1, occurredAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.id = id; self.workspaceID = workspaceID; self.assetID = assetID; self.siteID = siteID
        self.locationNodeID = locationNodeID; self.predecessorEventID = predecessorEventID; self.source = source
        self.physicalEpisodeID = physicalEpisodeID; self.continuity = continuity; self.pathSnapshot = pathSnapshot; self.mutationID = mutationID; self.occurredAt = occurredAt
        eventSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, id: id, workspaceID: workspaceID, assetID: assetID, siteID: siteID, locationNodeID: locationNodeID, predecessorEventID: predecessorEventID, source: source, physicalEpisodeID: physicalEpisodeID, continuity: continuity, pathSnapshot: pathSnapshot, mutationID: mutationID, occurredAt: occurredAt))
        try validate()
    }
    func validate() throws {
        try LocationContractValidationV1.requireID(id); try LocationContractValidationV1.requireID(assetID); try LocationContractValidationV1.requireID(siteID)
        if let locationNodeID { try LocationContractValidationV1.requireID(locationNodeID) }; if let predecessorEventID { try LocationContractValidationV1.requireID(predecessorEventID) }
        try pathSnapshot.validate()
        guard schemaVersion == Self.schemaVersion, pathSnapshot.siteID == siteID, predecessorEventID != id,
              (locationNodeID == nil && pathSnapshot.nodes.isEmpty) ||
                (locationNodeID != nil && pathSnapshot.nodes.last?.nodeID == locationNodeID),
              continuity != .unknownReviewRequired, occurredAt.timeIntervalSinceReferenceDate.isFinite,
              (source != .migratedBaseline || (locationNodeID == nil && predecessorEventID == nil)),
              eventSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, id: id, workspaceID: workspaceID, assetID: assetID, siteID: siteID, locationNodeID: locationNodeID, predecessorEventID: predecessorEventID, source: source, physicalEpisodeID: physicalEpisodeID, continuity: continuity, pathSnapshot: pathSnapshot, mutationID: mutationID, occurredAt: occurredAt))) else { throw LocationContractFailureV1.invalidValue }
    }
    private struct Basis: Codable { let schemaVersion: Int; let id: UUID; let workspaceID: WorkspaceID; let assetID: UUID; let siteID: UUID; let locationNodeID: UUID?; let predecessorEventID: UUID?; let source: AssetPlacementSourceV1; let physicalEpisodeID: PhysicalPlacementEpisodeIDV1; let continuity: PhysicalContinuityDispositionV1; let pathSnapshot: LocationPathSnapshotV1; let mutationID: MutationIDV1; let occurredAt: Date }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, id, workspaceID, assetID, siteID, locationNodeID, predecessorEventID, source, physicalEpisodeID, continuity, pathSnapshot, mutationID, occurredAt, eventSHA256 }
    init(from decoder: Decoder) throws {
        try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .locationNodeID && $0 != .predecessorEventID }.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(id: c.decode(UUID.self, forKey: .id), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), assetID: c.decode(UUID.self, forKey: .assetID), siteID: c.decode(UUID.self, forKey: .siteID), locationNodeID: LocationClosedCodingV1.optional(UUID.self, from: c, forKey: .locationNodeID), predecessorEventID: LocationClosedCodingV1.optional(UUID.self, from: c, forKey: .predecessorEventID), source: c.decode(AssetPlacementSourceV1.self, forKey: .source), physicalEpisodeID: c.decode(PhysicalPlacementEpisodeIDV1.self, forKey: .physicalEpisodeID), continuity: c.decode(PhysicalContinuityDispositionV1.self, forKey: .continuity), pathSnapshot: c.decode(LocationPathSnapshotV1.self, forKey: .pathSnapshot), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), occurredAt: c.decode(Date.self, forKey: .occurredAt))
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .eventSHA256) == rebuilt.eventSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt
    }
}

extension AssetPlacementEventV1 {
    func frozenAssetWorkSubjectReference() throws -> WorkSubjectReferenceV1 {
        try validate()
        let value = WorkSubjectReferenceV1(
            kind: .asset, subjectID: assetID, revision: 1, ownerAssetID: nil
        )
        try value.validate()
        return value
    }

    func frozenLocationWorkSubjectReference(locationRevision: UInt64) throws
        -> WorkSubjectReferenceV1? {
        try validate()
        guard let locationNodeID else { return nil }
        let value = WorkSubjectReferenceV1(
            kind: .locationNode,
            subjectID: locationNodeID,
            revision: locationRevision,
            ownerAssetID: nil
        )
        try value.validate()
        return value
    }
}

struct AssetPlacementPreviewBasisV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let assetID: UUID
    let currentPlacement: AssetPlacementEventV1?; let proposedSiteID: UUID; let proposedLocationNodeID: UUID?
    let proposedPath: LocationPathSnapshotV1; let source: AssetPlacementSourceV1; let reviewedContinuity: PhysicalContinuityDispositionV1
    init(workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1, assetID: UUID, currentPlacement: AssetPlacementEventV1?, proposedSiteID: UUID, proposedLocationNodeID: UUID?, proposedPath: LocationPathSnapshotV1, source: AssetPlacementSourceV1, reviewedContinuity: PhysicalContinuityDispositionV1) throws {
        try LocationContractValidationV1.requireID(assetID); try LocationContractValidationV1.requireID(proposedSiteID)
        try proposedPath.validate(); try currentPlacement?.validate()
        let bindingChanges = currentPlacement.map {
            $0.siteID != proposedSiteID
                || $0.locationNodeID != proposedLocationNodeID
                || $0.pathSnapshot.nodes.map(\.nodeID) != proposedPath.nodes.map(\.nodeID)
        } ?? true
        guard expectedRevision.workspaceID == workspaceID, proposedPath.siteID == proposedSiteID,
              source != .migratedBaseline,
              currentPlacement.map({ $0.assetID == assetID && $0.workspaceID == workspaceID }) ?? true,
              (proposedLocationNodeID == nil && proposedPath.nodes.isEmpty) ||
                (proposedLocationNodeID != nil && proposedPath.nodes.last?.nodeID == proposedLocationNodeID),
              bindingChanges || reviewedContinuity == .physicalMove,
              source != .hierarchyRebase || (currentPlacement != nil && bindingChanges),
              currentPlacement.map({ $0.siteID == proposedSiteID || reviewedContinuity == .physicalMove }) ?? true,
              reviewedContinuity != .unknownReviewRequired else { throw LocationContractFailureV1.reviewRequired }
        self.workspaceID = workspaceID; self.expectedRevision = expectedRevision; self.assetID = assetID; self.currentPlacement = currentPlacement
        self.proposedSiteID = proposedSiteID; self.proposedLocationNodeID = proposedLocationNodeID; self.proposedPath = proposedPath; self.source = source; self.reviewedContinuity = reviewedContinuity
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, expectedRevision, assetID, currentPlacement, proposedSiteID, proposedLocationNodeID, proposedPath, source, reviewedContinuity }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .currentPlacement && $0 != .proposedLocationNodeID }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), expectedRevision: c.decode(WorkspaceExpectedRevisionV1.self, forKey: .expectedRevision), assetID: c.decode(UUID.self, forKey: .assetID), currentPlacement: LocationClosedCodingV1.optional(AssetPlacementEventV1.self, from: c, forKey: .currentPlacement), proposedSiteID: c.decode(UUID.self, forKey: .proposedSiteID), proposedLocationNodeID: LocationClosedCodingV1.optional(UUID.self, from: c, forKey: .proposedLocationNodeID), proposedPath: c.decode(LocationPathSnapshotV1.self, forKey: .proposedPath), source: c.decode(AssetPlacementSourceV1.self, forKey: .source), reviewedContinuity: c.decode(PhysicalContinuityDispositionV1.self, forKey: .reviewedContinuity)) }
}

struct PlacementChangeComponentContributionV1: Codable, Equatable, Sendable {
    let componentID: String; let componentVersion: Int; let warnings: [String]; let requiredContinuityReview: Bool; let intentSHA256: String
    let poseDispositionIntents: [PosePlacementDispositionIntentV1]
    init(componentID: String, componentVersion: Int, warnings: [String], requiredContinuityReview: Bool, intentSHA256: String,
         poseDispositionIntents: [PosePlacementDispositionIntentV1] = []) throws {
        try LocationContractValidationV1.requireText(componentID, maximumBytes: 128); try LocationContractValidationV1.requireSortedUnique(warnings); try LocationContractValidationV1.requireDigest(intentSHA256)
        guard componentVersion > 0 else { throw LocationContractFailureV1.invalidValue }
        self.componentID = componentID; self.componentVersion = componentVersion; self.warnings = warnings; self.requiredContinuityReview = requiredContinuityReview; self.intentSHA256 = intentSHA256
        self.poseDispositionIntents = poseDispositionIntents.sorted { $0.predecessor.axisID < $1.predecessor.axisID }
        guard Set(self.poseDispositionIntents.map(\.predecessor.axisID)).count == self.poseDispositionIntents.count else { throw LocationContractFailureV1.invalidValue }
    }
    var stableKey: String { "\(componentID)|\(componentVersion)" }
    private enum CodingKeys: String, CodingKey, CaseIterable { case componentID, componentVersion, warnings, requiredContinuityReview, intentSHA256, poseDispositionIntents }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .poseDispositionIntents }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(componentID: c.decode(String.self, forKey: .componentID), componentVersion: c.decode(Int.self, forKey: .componentVersion), warnings: c.decode([String].self, forKey: .warnings), requiredContinuityReview: c.decode(Bool.self, forKey: .requiredContinuityReview), intentSHA256: c.decode(String.self, forKey: .intentSHA256), poseDispositionIntents: (try? c.decode([PosePlacementDispositionIntentV1].self, forKey: .poseDispositionIntents)) ?? []) }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(componentID, forKey: .componentID); try c.encode(componentVersion, forKey: .componentVersion); try c.encode(warnings, forKey: .warnings); try c.encode(requiredContinuityReview, forKey: .requiredContinuityReview); try c.encode(intentSHA256, forKey: .intentSHA256); if !poseDispositionIntents.isEmpty { try c.encode(poseDispositionIntents, forKey: .poseDispositionIntents) } }
}

@MainActor
protocol PlacementChangeComponentV1: AnyObject {
    var componentID: String { get }
    var componentVersion: Int { get }
    func preview(_ basis: AssetPlacementPreviewBasisV1) throws -> PlacementChangeComponentContributionV1
}

@MainActor
struct PlacementChangeComponentRegistryV1 {
    static let schemaVersion = 1
    private let components: [any PlacementChangeComponentV1]
    init(components: [any PlacementChangeComponentV1], allowedOrderedComponentIDs: [String]) throws {
        let ids = components.map(\.componentID)
        guard ids == allowedOrderedComponentIDs, Set(ids).count == ids.count,
              components.allSatisfy({ $0.componentVersion > 0 }) else { throw LocationContractFailureV1.unorderedValue }
        self.components = components
    }
    func contributions(for basis: AssetPlacementPreviewBasisV1) throws -> [PlacementChangeComponentContributionV1] {
        let values = try components.map { component in
            let value = try component.preview(basis)
            guard value.componentID == component.componentID, value.componentVersion == component.componentVersion else { throw LocationContractFailureV1.invalidValue }
            return value
        }
        guard values.map(\.stableKey) == values.map(\.stableKey).sorted(), Set(values.map(\.stableKey)).count == values.count else { throw LocationContractFailureV1.unorderedValue }
        return values
    }
}

struct AssetPlacementChangePlanV1: Codable, Equatable, Sendable {
    let operationID: UUID; let mutationID: MutationIDV1; let basis: AssetPlacementPreviewBasisV1
    let newEventID: UUID; let resultingPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1
    let componentContributions: [PlacementChangeComponentContributionV1]
    let poseEvents: [AssetPoseEventV1]; let poseEventPredecessors: [AssetPoseEventV1]
    let poseAdmissionClosure: PlacementPoseAdmissionClosureV1?
    let posePostImageSHA256: String?; let planSHA256: String
    init(operationID: UUID, mutationID: MutationIDV1, basis: AssetPlacementPreviewBasisV1, newEventID: UUID, resultingPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1, componentContributions: [PlacementChangeComponentContributionV1], poseEvents: [AssetPoseEventV1] = [], poseEventPredecessors: [AssetPoseEventV1] = [], poseAdmissionClosure: PlacementPoseAdmissionClosureV1? = nil) throws {
        try LocationContractValidationV1.requireID(operationID); try LocationContractValidationV1.requireID(newEventID)
        guard componentContributions.map(\.stableKey) == componentContributions.map(\.stableKey).sorted(), Set(componentContributions.map(\.stableKey)).count == componentContributions.count,
              !componentContributions.contains(where: { $0.requiredContinuityReview }) || basis.reviewedContinuity != .unknownReviewRequired,
              basis.currentPlacement.map({
                  (basis.reviewedContinuity == .physicalMove)
                    == ($0.physicalEpisodeID != resultingPhysicalEpisodeID)
              }) ?? true else { throw LocationContractFailureV1.reviewRequired }
        self.operationID = operationID; self.mutationID = mutationID; self.basis = basis; self.newEventID = newEventID; self.resultingPhysicalEpisodeID = resultingPhysicalEpisodeID; self.componentContributions = componentContributions
        self.poseEvents = poseEvents.sorted { $0.axisDescriptor.axisID < $1.axisDescriptor.axisID }
        self.poseEventPredecessors = poseEventPredecessors.sorted { $0.axisDescriptor.axisID < $1.axisDescriptor.axisID }
        self.poseAdmissionClosure = poseAdmissionClosure
        posePostImageSHA256 = poseEvents.isEmpty ? nil : try WorkspaceMutationCanonicalV1.sha256(PoseBasis(events: self.poseEvents, predecessors: self.poseEventPredecessors, admissionClosure: poseAdmissionClosure))
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, mutationID: mutationID, basis: basis, newEventID: newEventID, resultingPhysicalEpisodeID: resultingPhysicalEpisodeID, componentContributions: componentContributions))
        try validate()
    }
    func validate() throws {
        try LocationContractValidationV1.requireID(operationID)
        try LocationContractValidationV1.requireID(newEventID)
        try basis.proposedPath.validate()
        let episodeTransitionIsValid = basis.currentPlacement.map {
            (basis.reviewedContinuity == .physicalMove)
                == ($0.physicalEpisodeID != resultingPhysicalEpisodeID)
        } ?? true
        let intents = componentContributions.flatMap(\.poseDispositionIntents).sorted { $0.predecessor.axisID < $1.predecessor.axisID }
        guard basis.currentPlacement?.id != newEventID,
              componentContributions.map(\.stableKey) == componentContributions.map(\.stableKey).sorted(),
              Set(componentContributions.map(\.stableKey)).count == componentContributions.count,
              !componentContributions.contains(where: { $0.requiredContinuityReview })
                || basis.reviewedContinuity != .unknownReviewRequired,
              episodeTransitionIsValid,
              poseEvents.count == poseEventPredecessors.count,
              poseEvents.count == intents.count,
              Set(poseEvents.map { $0.axisDescriptor.axisID }).count == poseEvents.count,
              zip(poseEvents, poseEventPredecessors).allSatisfy({ value, predecessor in
                  guard let intent = intents.first(where: { $0.predecessor == predecessor.reference }) else { return false }
                  do { try value.validateSuccessor(of: predecessor) } catch { return false }
                  return value.workspaceID == basis.workspaceID && value.assetID == basis.assetID
                    && value.placementEventID == newEventID
                    && value.placementEpisodeID == resultingPhysicalEpisodeID
                    && value.locationPathSnapshot == basis.proposedPath
                    && value.mutationID == mutationID && value.pose == intent.proposedPose
                    && value.source == .placementCarryForward
              }),
              (poseEvents.isEmpty && poseAdmissionClosure == nil)
                || (!poseEvents.isEmpty && poseAdmissionClosure != nil),
              (poseEvents.isEmpty ? posePostImageSHA256 == nil : posePostImageSHA256 == (try WorkspaceMutationCanonicalV1.sha256(PoseBasis(events: poseEvents, predecessors: poseEventPredecessors, admissionClosure: poseAdmissionClosure)))),
              planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, mutationID: mutationID, basis: basis, newEventID: newEventID, resultingPhysicalEpisodeID: resultingPhysicalEpisodeID, componentContributions: componentContributions))) else { throw LocationContractFailureV1.digestMismatch }
        try poseAdmissionClosure?.validate(events: poseEvents, observations: [])
    }
    private struct Basis: Codable { let operationID: UUID; let mutationID: MutationIDV1; let basis: AssetPlacementPreviewBasisV1; let newEventID: UUID; let resultingPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1; let componentContributions: [PlacementChangeComponentContributionV1] }
    private struct PoseBasis: Codable { let events: [AssetPoseEventV1]; let predecessors: [AssetPoseEventV1]; let admissionClosure: PlacementPoseAdmissionClosureV1? }
    private enum CodingKeys: String, CodingKey, CaseIterable { case operationID, mutationID, basis, newEventID, resultingPhysicalEpisodeID, componentContributions, poseEvents, poseEventPredecessors, poseAdmissionClosure, posePostImageSHA256, planSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { ![.poseEvents, .poseEventPredecessors, .poseAdmissionClosure, .posePostImageSHA256].contains($0) }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(operationID: c.decode(UUID.self, forKey: .operationID), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), basis: c.decode(AssetPlacementPreviewBasisV1.self, forKey: .basis), newEventID: c.decode(UUID.self, forKey: .newEventID), resultingPhysicalEpisodeID: c.decode(PhysicalPlacementEpisodeIDV1.self, forKey: .resultingPhysicalEpisodeID), componentContributions: c.decode([PlacementChangeComponentContributionV1].self, forKey: .componentContributions), poseEvents: (try? c.decode([AssetPoseEventV1].self, forKey: .poseEvents)) ?? [], poseEventPredecessors: (try? c.decode([AssetPoseEventV1].self, forKey: .poseEventPredecessors)) ?? [], poseAdmissionClosure: try c.decodeIfPresent(PlacementPoseAdmissionClosureV1.self, forKey: .poseAdmissionClosure)); guard try c.decode(String.self, forKey: .planSHA256) == rebuilt.planSHA256, (try? c.decode(String.self, forKey: .posePostImageSHA256)) == rebuilt.posePostImageSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(operationID, forKey: .operationID); try c.encode(mutationID, forKey: .mutationID); try c.encode(basis, forKey: .basis); try c.encode(newEventID, forKey: .newEventID); try c.encode(resultingPhysicalEpisodeID, forKey: .resultingPhysicalEpisodeID); try c.encode(componentContributions, forKey: .componentContributions); if !poseEvents.isEmpty { try c.encode(poseEvents, forKey: .poseEvents); try c.encode(poseEventPredecessors, forKey: .poseEventPredecessors); try c.encode(poseAdmissionClosure, forKey: .poseAdmissionClosure); try c.encode(posePostImageSHA256, forKey: .posePostImageSHA256) }; try c.encode(planSHA256, forKey: .planSHA256) }
}

struct AssetPlacementChangeReceiptV1: Codable, Equatable, Sendable {
    let planSHA256: String; let placementEvent: AssetPlacementEventV1; let mutationReceiptIdentity: MutationReceiptIdentityV1
    let posePostImageSHA256: String?; let commandBodySHA256: String
    let mutationReceiptSHA256: String; let committedAt: Date; let receiptSHA256: String
    init(plan: AssetPlacementChangePlanV1, placementEvent: AssetPlacementEventV1, mutationReceipt: MutationReceiptV1) throws {
        try plan.validate(); try placementEvent.validate(); try mutationReceipt.validate()
        let commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAssetPlacementChange(plan))
        guard placementEvent.id == plan.newEventID, placementEvent.mutationID == plan.mutationID,
              mutationReceipt.mutationID == plan.mutationID,
              mutationReceipt.identity.workspaceID == plan.basis.workspaceID,
              mutationReceipt.commandBodySHA256 == commandBodySHA256 else {
            throw LocationContractFailureV1.invalidValue
        }
        planSHA256 = plan.planSHA256; self.placementEvent = placementEvent; mutationReceiptIdentity = mutationReceipt.identity
        posePostImageSHA256 = plan.posePostImageSHA256; self.commandBodySHA256 = commandBodySHA256
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256(); committedAt = mutationReceipt.committedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(planSHA256: plan.planSHA256, placementEvent: placementEvent, posePostImageSHA256: plan.posePostImageSHA256, commandBodySHA256: commandBodySHA256, mutationReceiptIdentity: mutationReceipt.identity, mutationReceiptSHA256: mutationReceiptSHA256, committedAt: committedAt))
    }
    func validate(plan: AssetPlacementChangePlanV1, mutationReceipt: MutationReceiptV1) throws {
        let rebuilt = try Self(plan: plan, placementEvent: placementEvent, mutationReceipt: mutationReceipt)
        guard rebuilt == self else { throw LocationContractFailureV1.digestMismatch }
    }
    private struct Basis: Codable { let planSHA256: String; let placementEvent: AssetPlacementEventV1; let posePostImageSHA256: String?; let commandBodySHA256: String; let mutationReceiptIdentity: MutationReceiptIdentityV1; let mutationReceiptSHA256: String; let committedAt: Date }
    private enum CodingKeys: String, CodingKey, CaseIterable { case planSHA256, placementEvent, posePostImageSHA256, commandBodySHA256, mutationReceiptIdentity, mutationReceiptSHA256, committedAt, receiptSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .posePostImageSHA256 }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); planSHA256 = try c.decode(String.self, forKey: .planSHA256); placementEvent = try c.decode(AssetPlacementEventV1.self, forKey: .placementEvent); posePostImageSHA256 = try c.decodeIfPresent(String.self, forKey: .posePostImageSHA256); commandBodySHA256 = try c.decode(String.self, forKey: .commandBodySHA256); mutationReceiptIdentity = try c.decode(MutationReceiptIdentityV1.self, forKey: .mutationReceiptIdentity); mutationReceiptSHA256 = try c.decode(String.self, forKey: .mutationReceiptSHA256); committedAt = try c.decode(Date.self, forKey: .committedAt); receiptSHA256 = try c.decode(String.self, forKey: .receiptSHA256); try placementEvent.validate(); try mutationReceiptIdentity.validate(); try LocationContractValidationV1.requireDigest(commandBodySHA256); try posePostImageSHA256.map(LocationContractValidationV1.requireDigest); let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(planSHA256: planSHA256, placementEvent: placementEvent, posePostImageSHA256: posePostImageSHA256, commandBodySHA256: commandBodySHA256, mutationReceiptIdentity: mutationReceiptIdentity, mutationReceiptSHA256: mutationReceiptSHA256, committedAt: committedAt)); guard receiptSHA256 == expected else { throw LocationContractFailureV1.digestMismatch } }
}

enum AssetPlacementHistoryV1 {
    static func validate(_ events: [AssetPlacementEventV1]) throws {
        guard !events.isEmpty, events.count <= LocationContractLimitsV1.maximumCollectionCount,
              Set(events.map(\.id)).count == events.count else { throw LocationContractFailureV1.duplicateIdentity }
        try events.forEach { try $0.validate() }
        guard Set(events.map(\.workspaceID)).count == 1, Set(events.map(\.assetID)).count == 1 else { throw LocationContractFailureV1.invalidValue }
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        let referenced = Set(events.compactMap(\.predecessorEventID))
        let tips = events.filter { !referenced.contains($0.id) }
        let roots = events.filter { $0.predecessorEventID == nil }
        guard tips.count == 1, roots.count == 1 else { throw LocationContractFailureV1.hierarchyViolation }
        for event in events where event.predecessorEventID != nil {
            guard let predecessor = event.predecessorEventID.flatMap({ byID[$0] }), predecessor.occurredAt <= event.occurredAt,
                  event.siteID != predecessor.siteID || event.locationNodeID != predecessor.locationNodeID ||
                    event.pathSnapshot != predecessor.pathSnapshot || event.continuity == .physicalMove,
                  (event.continuity == .physicalMove) == (event.physicalEpisodeID != predecessor.physicalEpisodeID),
                  event.siteID == predecessor.siteID || event.continuity == .physicalMove else { throw LocationContractFailureV1.hierarchyViolation }
        }
        var reachable = Set<UUID>()
        var cursor: AssetPlacementEventV1? = tips[0]
        while let event = cursor {
            guard reachable.insert(event.id).inserted else { throw LocationContractFailureV1.hierarchyViolation }
            cursor = try event.predecessorEventID.map { predecessorID in
                guard let predecessor = byID[predecessorID] else { throw LocationContractFailureV1.hierarchyViolation }
                return predecessor
            }
        }
        guard reachable.count == events.count, reachable.contains(roots[0].id) else {
            throw LocationContractFailureV1.hierarchyViolation
        }
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Location_AssetPlacementContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Location_AssetPlacementContractsV1_swift {
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
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Location_AssetPlacementContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift", role: .location)
}

enum C31LightingAssetPlacementBoundaryV1 {
    static let luminairesBindExistingAssetPlacement = true
    static let placementDoesNotProveInstalledOrOperatingState = true
    static let poseAndlightingFactsRemainSeparate = true
}
// MARK: - C32 assistance asset placement boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Location_AssetPlacementContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedLocationUsesExpectedRevision = true

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

enum C33TemporalEvidenceBoundary_Domain_Location_AssetPlacementContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row150 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
