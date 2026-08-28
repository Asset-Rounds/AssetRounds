import Foundation

enum EvidenceTargetKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case inspectionNode = "INSPECTION_NODE"
    case inspectionResponse = "INSPECTION_RESPONSE"
    case finding = "FINDING"
    case correctiveWork = "CORRECTIVE_WORK"
    case asset = "ASSET"
    case workRecord = "WORK_RECORD"
}

extension EvidenceAssociationV1 {
    func accessibleEvidenceLink(evidenceSHA256:String,mediaType:String = "application/octet-stream")throws->AccessibleEvidenceLinkV1{
        guard action != .removed else{throw AccessibleDocumentFailureV1.missingEvidence}
        return try AccessibleEvidenceLinkV1(evidenceID:evidenceID,evidenceSHA256:evidenceSHA256,mediaType:mediaType)
    }
}

struct EvidenceAssociationTargetV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: String
    let kind: EvidenceTargetKindV1
    let targetID: String
    let targetRevision: Int

    init(workspaceID: String, kind: EvidenceTargetKindV1, targetID: String, targetRevision: Int) throws {
        guard ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(targetID), targetRevision >= 0 else {
            throw ContentContractFailureV1.invalidValue
        }
        self.workspaceID = workspaceID; self.kind = kind
        self.targetID = targetID; self.targetRevision = targetRevision
    }
}

enum EvidenceAssociationActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case assigned = "ASSIGNED"
    case reassigned = "REASSIGNED"
    case removed = "REMOVED"
}

struct EvidenceAssociationV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let associationEventID: String
    let workspaceID: String
    let evidenceID: String
    let expectedEvidenceRevision: Int
    let resultingEvidenceRevision: Int
    let mutationID: String
    let action: EvidenceAssociationActionV1
    let contentID: String?
    let target: EvidenceAssociationTargetV1?
    let previousContentID: String?
    let previousTarget: EvidenceAssociationTargetV1?
    let supersedesAssociationEventID: String?
    let actorID: String
    let reason: String
    let effectiveAt: String

    var id: String { "\(workspaceID)|\(associationEventID)" }

    init(
        associationEventID: String,
        workspaceID: String,
        evidenceID: String,
        expectedEvidenceRevision: Int,
        resultingEvidenceRevision: Int,
        mutationID: String,
        action: EvidenceAssociationActionV1,
        contentID: String?,
        target: EvidenceAssociationTargetV1?,
        previousContentID: String? = nil,
        previousTarget: EvidenceAssociationTargetV1? = nil,
        supersedesAssociationEventID: String? = nil,
        actorID: String,
        reason: String,
        effectiveAt: String
    ) throws {
        guard target.map({ $0.workspaceID == workspaceID }) ?? true,
              previousTarget.map({ $0.workspaceID == workspaceID }) ?? true else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        guard [associationEventID, workspaceID, evidenceID, mutationID, actorID].allSatisfy(ContentContractValidationV1.validID),
              expectedEvidenceRevision >= 0, resultingEvidenceRevision == expectedEvidenceRevision + 1,
              contentID.map(ContentContractValidationV1.validID) ?? true,
              previousContentID.map(ContentContractValidationV1.validID) ?? true,
              supersedesAssociationEventID.map(ContentContractValidationV1.validID) ?? true,
              FindingContractValidationV1.validText(reason, maximumBytes: ContentContractLimitsV1.maximumTextBytes),
              FindingContractValidationV1.validInstant(effectiveAt) else {
            throw ContentContractFailureV1.invalidValue
        }
        switch action {
        case .assigned:
            guard expectedEvidenceRevision == 0, contentID != nil, target != nil,
                  previousContentID == nil, previousTarget == nil,
                  supersedesAssociationEventID == nil else { throw ContentContractFailureV1.historyRewrite }
        case .reassigned:
            guard expectedEvidenceRevision > 0, contentID != nil, target != nil,
                  previousContentID != nil, previousTarget != nil,
                  supersedesAssociationEventID != nil,
                  contentID != previousContentID || target != previousTarget else {
                throw ContentContractFailureV1.historyRewrite
            }
        case .removed:
            guard expectedEvidenceRevision > 0, contentID == nil, target == nil,
                  previousContentID != nil, previousTarget != nil,
                  supersedesAssociationEventID != nil else { throw ContentContractFailureV1.historyRewrite }
        }
        schemaVersion = Self.schemaVersion
        self.associationEventID = associationEventID; self.workspaceID = workspaceID; self.evidenceID = evidenceID
        self.expectedEvidenceRevision = expectedEvidenceRevision; self.resultingEvidenceRevision = resultingEvidenceRevision
        self.mutationID = mutationID; self.action = action; self.contentID = contentID; self.target = target
        self.previousContentID = previousContentID; self.previousTarget = previousTarget
        self.supersedesAssociationEventID = supersedesAssociationEventID
        self.actorID = actorID; self.reason = reason; self.effectiveAt = effectiveAt
    }
}

enum EvidenceAssociationLedgerV1 {
    static func validate(_ events: [EvidenceAssociationV1]) throws {
        guard events.count <= ContentContractLimitsV1.maximumAssociations else {
            throw ContentContractFailureV1.limitExceeded
        }
        var groups: [String: [EvidenceAssociationV1]] = [:]
        var eventIDs = Set<String>(), mutationIDs = Set<String>()
        for event in events {
            guard eventIDs.insert("\(event.workspaceID)|\(event.associationEventID)").inserted,
                  mutationIDs.insert("\(event.workspaceID)|\(event.mutationID)").inserted else {
                throw ContentContractFailureV1.duplicateIdentity
            }
            groups["\(event.workspaceID)|\(event.evidenceID)", default: []].append(event)
        }
        for key in groups.keys.sorted() {
            guard let history = groups[key] else { continue }
            var expectedRevision = 0
            var predecessorID: String?
            var activeContentID: String?
            var activeTarget: EvidenceAssociationTargetV1?
            for event in history {
                guard event.expectedEvidenceRevision == expectedRevision,
                      event.resultingEvidenceRevision == expectedRevision + 1,
                      event.supersedesAssociationEventID == predecessorID else {
                    throw ContentContractFailureV1.historyRewrite
                }
                switch event.action {
                case .assigned:
                    guard expectedRevision == 0 else { throw ContentContractFailureV1.historyRewrite }
                case .reassigned, .removed:
                    guard event.previousContentID == activeContentID,
                          event.previousTarget == activeTarget else {
                        throw ContentContractFailureV1.staleReference
                    }
                }
                activeContentID = event.contentID; activeTarget = event.target
                expectedRevision = event.resultingEvidenceRevision
                predecessorID = event.associationEventID
            }
        }
    }

    static func validateOrphanFree(
        events: [EvidenceAssociationV1],
        references: [ContentReferenceV1]
    ) throws {
        try validate(events)
        guard Set(references.map { "\($0.workspaceID)|\($0.contentID)" }).count == references.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        let keys = Set(references.map { "\($0.workspaceID)|\($0.contentID)" })
        for event in events {
            for contentID in [event.contentID, event.previousContentID].compactMap({ $0 }) {
                guard keys.contains("\(event.workspaceID)|\(contentID)") else {
                    throw ContentContractFailureV1.orphanEvidence
                }
            }
        }
    }
}

enum FutureC36ReservationClassV1: String, CaseIterable, Sendable {
    case prePromotionStagedBytes = "PRE_PROMOTION_STAGED_BYTES"
    case contentPromotedUnbound = "CONTENT_PROMOTED_UNBOUND"
}

struct FutureC36ContentExclusionV1: Equatable, Sendable {
    let reservationClass: FutureC36ReservationClassV1
    let workspaceID: String
    let draftID: String
    let stageID: String
    let commitPlanSHA256: String
    let mutationID: String
    let contentDigest: ContentDigestV1
    let contentID: String?

    init(
        reservationClass: FutureC36ReservationClassV1,
        workspaceID: String,
        draftID: String,
        stageID: String,
        commitPlanSHA256: String,
        mutationID: String,
        contentDigest: ContentDigestV1,
        contentID: String? = nil
    ) throws {
        guard [workspaceID, draftID, stageID, mutationID].allSatisfy(ContentContractValidationV1.validID),
              KernelCanonicalHashV1.validSHA256(commitPlanSHA256),
              contentID.map(ContentContractValidationV1.validID) ?? true,
              (reservationClass == .contentPromotedUnbound) == (contentID != nil) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.reservationClass = reservationClass
        self.workspaceID = workspaceID
        self.draftID = draftID
        self.stageID = stageID
        self.commitPlanSHA256 = commitPlanSHA256
        self.mutationID = mutationID
        self.contentDigest = contentDigest
        self.contentID = contentID
    }
}

enum ContentEvidenceGraphV1 {
    static func validate(
        references: [ContentReferenceV1],
        originalProvenance: [ContentOriginalProvenanceV1],
        derivativeProvenance: [ContentDerivativeProvenanceV1],
        associationEvents: [EvidenceAssociationV1],
        validTargets: [EvidenceAssociationTargetV1],
        futureC36Exclusions: [FutureC36ContentExclusionV1] = []
    ) throws {
        guard validTargets.count <= ContentContractLimitsV1.maximumAssociations,
              futureC36Exclusions.count <= ContentContractLimitsV1.maximumManifestEntries else {
            throw ContentContractFailureV1.limitExceeded
        }
        try ContentProvenanceGraphV1.validate(
            references: references,
            originals: originalProvenance,
            derivatives: derivativeProvenance
        )
        try EvidenceAssociationLedgerV1.validateOrphanFree(events: associationEvents, references: references)

        let targetKeys = validTargets.map {
            "\($0.workspaceID)|\($0.kind.rawValue)|\($0.targetID)|\($0.targetRevision)"
        }
        guard Set(targetKeys).count == targetKeys.count else { throw ContentContractFailureV1.duplicateIdentity }
        let targetSet = Set(targetKeys)
        for event in associationEvents {
            for target in [event.target, event.previousTarget].compactMap({ $0 }) {
                guard target.workspaceID == event.workspaceID else {
                    throw ContentContractFailureV1.wrongWorkspace
                }
                let key = "\(target.workspaceID)|\(target.kind.rawValue)|\(target.targetID)|\(target.targetRevision)"
                guard targetSet.contains(key) else { throw ContentContractFailureV1.orphanEvidence }
            }
        }

        let draftKeys = futureC36Exclusions.map { "\($0.workspaceID)|\($0.draftID)" }
        let stageKeys = futureC36Exclusions.map { "\($0.workspaceID)|\($0.stageID)" }
        let reservationMutationKeys = futureC36Exclusions.map { "\($0.workspaceID)|\($0.mutationID)" }
        guard Set(draftKeys).count == draftKeys.count,
              Set(stageKeys).count == stageKeys.count,
              Set(reservationMutationKeys).count == reservationMutationKeys.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        let exclusionKeys = futureC36Exclusions.compactMap { exclusion -> String? in
            guard exclusion.reservationClass == .contentPromotedUnbound,
                  let contentID = exclusion.contentID else { return nil }
            return "\(exclusion.workspaceID)|\(contentID)"
        }
        guard Set(exclusionKeys).count == exclusionKeys.count else { throw ContentContractFailureV1.duplicateIdentity }
        let excluded = Set(exclusionKeys)
        var terminalEventByEvidence: [String: EvidenceAssociationV1] = [:]
        for event in associationEvents {
            terminalEventByEvidence["\(event.workspaceID)|\(event.evidenceID)"] = event
        }
        let associated = Set(terminalEventByEvidence.values.compactMap { event in
            event.contentID.map { "\(event.workspaceID)|\($0)" }
        })
        guard associated.isDisjoint(with: excluded) else {
            throw ContentContractFailureV1.orphanEvidence
        }
        for reference in references where reference.byteRole == .immutableOriginal {
            let key = "\(reference.workspaceID)|\(reference.contentID)"
            guard associated.contains(key) || excluded.contains(key) else {
                throw ContentContractFailureV1.orphanEvidence
            }
        }
        guard excluded.allSatisfy({ key in
            references.contains { reference in
                "\(reference.workspaceID)|\(reference.contentID)" == key
                    && reference.byteRole == .immutableOriginal
                    && futureC36Exclusions.contains { exclusion in
                        exclusion.reservationClass == .contentPromotedUnbound
                            && "\(exclusion.workspaceID)|\(exclusion.contentID ?? "")" == key
                            && reference.digests.digest(for: exclusion.contentDigest.algorithm) == exclusion.contentDigest
                    }
            }
        }) else { throw ContentContractFailureV1.orphanEvidence }
    }
}

extension EvidenceAssociationTargetV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, kind, targetID, targetRevision }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(String.self, forKey: .workspaceID), kind: c.decode(EvidenceTargetKindV1.self, forKey: .kind), targetID: c.decode(String.self, forKey: .targetID), targetRevision: c.decode(Int.self, forKey: .targetRevision))
    }
}

extension EvidenceAssociationV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, associationEventID, workspaceID, evidenceID, expectedEvidenceRevision
        case resultingEvidenceRevision, mutationID, action, contentID, target, previousContentID
        case previousTarget, supersedesAssociationEventID, actorID, reason, effectiveAt
    }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireClosed(
            decoder, allowed: CodingKeys.allCases.map(\.rawValue),
            required: CodingKeys.allCases.filter {
                ![.contentID, .target, .previousContentID, .previousTarget, .supersedesAssociationEventID].contains($0)
            }.map(\.rawValue)
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.contentID, .target, .previousContentID, .previousTarget, .supersedesAssociationEventID]
        where c.contains(key) && (try c.decodeNil(forKey: key)) {
            throw ContentContractFailureV1.invalidValue
        }
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(
            associationEventID: c.decode(String.self, forKey: .associationEventID), workspaceID: c.decode(String.self, forKey: .workspaceID),
            evidenceID: c.decode(String.self, forKey: .evidenceID), expectedEvidenceRevision: c.decode(Int.self, forKey: .expectedEvidenceRevision),
            resultingEvidenceRevision: c.decode(Int.self, forKey: .resultingEvidenceRevision), mutationID: c.decode(String.self, forKey: .mutationID),
            action: c.decode(EvidenceAssociationActionV1.self, forKey: .action), contentID: c.decodeIfPresent(String.self, forKey: .contentID),
            target: c.decodeIfPresent(EvidenceAssociationTargetV1.self, forKey: .target), previousContentID: c.decodeIfPresent(String.self, forKey: .previousContentID),
            previousTarget: c.decodeIfPresent(EvidenceAssociationTargetV1.self, forKey: .previousTarget), supersedesAssociationEventID: c.decodeIfPresent(String.self, forKey: .supersedesAssociationEventID),
            actorID: c.decode(String.self, forKey: .actorID), reason: c.decode(String.self, forKey: .reason), effectiveAt: c.decode(String.self, forKey: .effectiveAt)
        )
    }
}
