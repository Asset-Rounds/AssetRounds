import Foundation

enum EvidenceTargetKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case inspectionNode = "INSPECTION_NODE"
    case inspectionResponse = "INSPECTION_RESPONSE"
    case finding = "FINDING"
    case correctiveWork = "CORRECTIVE_WORK"
    case asset = "ASSET"
    case workRecord = "WORK_RECORD"
}

enum C50IncumbentEvidenceAssociationBoundaryV1 {
    static let previewMayDescribeButNeverCreateAssociations = true
    static let acceptedAssociationsUseExistingWorkspaceMutation = true
    static let externalKeysAreNotEvidenceIdentity = true
}

extension EvidenceAssociationV1 {
    func accessibleEvidenceLink(evidenceSHA256:String,mediaType:String = "application/octet-stream")throws->AccessibleEvidenceLinkV1{
        guard action != .removed else{throw AccessibleDocumentFailureV1.missingEvidence}
        return try AccessibleEvidenceLinkV1(evidenceID:evidenceID,evidenceSHA256:evidenceSHA256,mediaType:mediaType)
    }
}

// MARK: - C49 work-resource subject association

enum C49WorkResourceEvidenceAssociationBoundaryV1 {
    static let subjectBindingIsReadOnly = true
    static let evidenceBytesRemainOutsideWorkResourceProjection = true
    static let liveInventoryAssociationIsForbidden = true

    static func report(
        subject: WorkResourceSubjectV1,
        snapshots: [WorkResourceSnapshotV1],
        audience: C49WorkResourceAudienceV1 = .internalOnly,
        includeDirectCostPreview: Bool = false
    ) throws -> C49WorkResourceReportProjectionV1 {
        guard snapshots.allSatisfy({
            $0.entry.workspaceID == subject.workspaceID && $0.entry.subject == subject
        }) else {
            throw C49WorkResourceProjectionFailureV1.invalidWorkspace
        }
        return try C49WorkResourceReportProjectionV1(
            workspaceID: subject.workspaceID,
            snapshots: snapshots,
            audience: audience,
            includeDirectCostPreview: includeDirectCostPreview
        )
    }
}

enum C48PortableReviewEvidenceAssociationBoundaryV1 {
    static let responseAttachmentsAreUnsupported = true
    static let capabilityProofCannotBecomeEvidence = true
    static let rawResponseBytesCannotBecomeEvidence = true
    static let acceptedAssociationsContinueThroughExistingCanonicalWriter = true
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
        let (nextRevision, revisionOverflow) = expectedEvidenceRevision.addingReportingOverflow(1)
        guard [associationEventID, workspaceID, evidenceID, mutationID, actorID].allSatisfy(ContentContractValidationV1.validID),
              expectedEvidenceRevision >= 0, !revisionOverflow, resultingEvidenceRevision == nextRevision,
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
                let (nextRevision, revisionOverflow) = expectedRevision.addingReportingOverflow(1)
                guard !revisionOverflow, event.expectedEvidenceRevision == expectedRevision,
                      event.resultingEvidenceRevision == nextRevision,
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
enum C52ServiceRequestBoundary_EvidenceAssociationContractsV1 {
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

// MARK: - C05 reviewed evidence metadata and immutable sequence history

enum EvidenceMetadataFailureV1: Error, Equatable, Sendable {
    case invalidValue, limitExceeded, wrongWorkspace, duplicateIdentity
    case staleAssociation, invalidSuccessor, invalidDigest, incompatibleVersion
}

enum EvidenceMetadataLimitsV1 {
    static let maximumSequenceItems = 32
    static let maximumCaptionBytes = 1_024
    static let maximumAccessibilityDescriptionBytes = 2_048
}

private enum EvidenceMetadataValidationV1 {
    static func millisecondInstant(_ value: Date) throws {
        let seconds = value.timeIntervalSince1970
        let milliseconds = seconds * 1_000
        let integral = milliseconds.rounded(.toNearestOrAwayFromZero)
        guard seconds.isFinite, milliseconds.isFinite, integral == milliseconds,
              integral >= Double(Int64.min), integral <= Double(Int64.max),
              Date(timeIntervalSince1970: integral / 1_000) == value else {
            throw EvidenceMetadataFailureV1.invalidValue
        }
    }
}

struct EvidenceCurationPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let policyID: UUID
    let workspaceID: WorkspaceID
    let maximumSequenceItems: Int
    let maximumCaptionBytes: Int
    let maximumAccessibilityDescriptionBytes: Int

    init(policyID: UUID, workspaceID: WorkspaceID,
         maximumSequenceItems: Int = EvidenceMetadataLimitsV1.maximumSequenceItems,
         maximumCaptionBytes: Int = EvidenceMetadataLimitsV1.maximumCaptionBytes,
         maximumAccessibilityDescriptionBytes: Int = EvidenceMetadataLimitsV1.maximumAccessibilityDescriptionBytes) throws {
        guard (1...EvidenceMetadataLimitsV1.maximumSequenceItems).contains(maximumSequenceItems),
              (1...EvidenceMetadataLimitsV1.maximumCaptionBytes).contains(maximumCaptionBytes),
              (1...EvidenceMetadataLimitsV1.maximumAccessibilityDescriptionBytes).contains(maximumAccessibilityDescriptionBytes) else {
            throw EvidenceMetadataFailureV1.limitExceeded
        }
        schemaVersion = Self.schemaVersion; self.policyID = policyID; self.workspaceID = workspaceID
        self.maximumSequenceItems = maximumSequenceItems; self.maximumCaptionBytes = maximumCaptionBytes
        self.maximumAccessibilityDescriptionBytes = maximumAccessibilityDescriptionBytes
    }

    func validate() throws {
        guard self == (try Self(policyID: policyID, workspaceID: workspaceID,
            maximumSequenceItems: maximumSequenceItems, maximumCaptionBytes: maximumCaptionBytes,
            maximumAccessibilityDescriptionBytes: maximumAccessibilityDescriptionBytes)) else {
            throw EvidenceMetadataFailureV1.invalidValue
        }
    }
}

enum EvidenceRoleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case context = "CONTEXT", detail = "DETAIL", before = "BEFORE", after = "AFTER", other = "OTHER"
}

enum EvidenceReviewedTextProvenanceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case userAuthored = "USER_AUTHORED"
    case importedThenReviewed = "IMPORTED_THEN_REVIEWED"
}

struct EvidenceReviewedCaptionV1: Codable, Equatable, Sendable {
    let text: String
    let provenance: EvidenceReviewedTextProvenanceV1
    let reviewer: ActorSnapshotV1
    let reviewedAt: Date

    init(text: String, provenance: EvidenceReviewedTextProvenanceV1,
         reviewer: ActorSnapshotV1, reviewedAt: Date) throws {
        try reviewer.validate()
        guard !text.isEmpty, text.utf8.count <= EvidenceMetadataLimitsV1.maximumCaptionBytes,
              reviewedAt.timeIntervalSince1970.isFinite else { throw EvidenceMetadataFailureV1.invalidValue }
        try EvidenceMetadataValidationV1.millisecondInstant(reviewedAt)
        try EvidenceMetadataValidationV1.millisecondInstant(reviewer.capturedAt)
        self.text = text; self.provenance = provenance; self.reviewer = reviewer; self.reviewedAt = reviewedAt
    }
}

struct EvidenceAccessibilityDescriptionV1: Codable, Equatable, Sendable {
    let text: String
    let provenance: EvidenceReviewedTextProvenanceV1
    let reviewer: ActorSnapshotV1
    let reviewedAt: Date

    init(text: String, provenance: EvidenceReviewedTextProvenanceV1,
         reviewer: ActorSnapshotV1, reviewedAt: Date) throws {
        try reviewer.validate()
        guard !text.isEmpty, text.utf8.count <= EvidenceMetadataLimitsV1.maximumAccessibilityDescriptionBytes,
              reviewedAt.timeIntervalSince1970.isFinite else { throw EvidenceMetadataFailureV1.invalidValue }
        try EvidenceMetadataValidationV1.millisecondInstant(reviewedAt)
        try EvidenceMetadataValidationV1.millisecondInstant(reviewer.capturedAt)
        self.text = text; self.provenance = provenance; self.reviewer = reviewer; self.reviewedAt = reviewedAt
    }
}

struct EvidenceAssociationBindingV1: Codable, Equatable, Hashable, Sendable {
    let associationEventID: String
    let resultingEvidenceRevision: Int
    let associationSHA256: String

    init(_ association: EvidenceAssociationV1) throws {
        guard association.action != .removed, association.contentID != nil, association.target != nil else {
            throw EvidenceMetadataFailureV1.staleAssociation
        }
        associationEventID = association.associationEventID
        resultingEvidenceRevision = association.resultingEvidenceRevision
        associationSHA256 = try EvidenceMetadataCanonicalCodecV1.sha256(association)
    }
}

struct EvidenceSequenceItemV1: Codable, Equatable, Sendable {
    let evidenceID: String
    let contentID: String
    let role: EvidenceRoleV1
    let caption: EvidenceReviewedCaptionV1
    let accessibilityDescription: EvidenceAccessibilityDescriptionV1?
    let ordinal: Int
    let target: EvidenceAssociationTargetV1
    let associationBinding: EvidenceAssociationBindingV1

    init(evidenceID: String, contentID: String, role: EvidenceRoleV1,
         caption: EvidenceReviewedCaptionV1,
         accessibilityDescription: EvidenceAccessibilityDescriptionV1? = nil,
         ordinal: Int, target: EvidenceAssociationTargetV1,
         association: EvidenceAssociationV1) throws {
        guard ContentContractValidationV1.validID(evidenceID), ContentContractValidationV1.validID(contentID),
              ordinal >= 0, association.evidenceID == evidenceID, association.contentID == contentID,
              association.target == target, association.workspaceID == target.workspaceID,
              caption.reviewer.workspaceID.rawValue.uuidString.lowercased() == target.workspaceID,
              accessibilityDescription.map({ $0.reviewer.workspaceID == caption.reviewer.workspaceID }) ?? true else {
            throw EvidenceMetadataFailureV1.staleAssociation
        }
        self.evidenceID = evidenceID; self.contentID = contentID; self.role = role; self.caption = caption
        self.accessibilityDescription = accessibilityDescription; self.ordinal = ordinal; self.target = target
        associationBinding = try EvidenceAssociationBindingV1(association)
    }
}

struct EvidenceSequenceReferenceV1: Codable, Equatable, Hashable, Sendable {
    let sequenceID: UUID
    let revision: UInt64
    let sequenceSHA256: String
    init(sequenceID: UUID, revision: UInt64, sequenceSHA256: String) throws {
        guard revision > 0, KernelCanonicalHashV1.validSHA256(sequenceSHA256) else { throw EvidenceMetadataFailureV1.invalidValue }
        self.sequenceID = sequenceID; self.revision = revision; self.sequenceSHA256 = sequenceSHA256
    }
}

struct EvidenceSequenceV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sequenceID: UUID
    let workspaceID: WorkspaceID
    let target: EvidenceAssociationTargetV1
    let policy: EvidenceCurationPolicyV1
    let orderedItems: [EvidenceSequenceItemV1]
    let predecessor: EvidenceSequenceReferenceV1?
    let revision: UInt64
    let mutationID: MutationIDV1
    let sequenceSHA256: String

    var reference: EvidenceSequenceReferenceV1 {
        get throws { try .init(sequenceID: sequenceID, revision: revision, sequenceSHA256: sequenceSHA256) }
    }
    var frontier: EvidenceSequenceReferenceV1 { get throws { try reference } }

    init(sequenceID: UUID, workspaceID: WorkspaceID, target: EvidenceAssociationTargetV1,
         policy: EvidenceCurationPolicyV1, orderedItems: [EvidenceSequenceItemV1],
         predecessor: EvidenceSequenceReferenceV1? = nil, revision: UInt64,
         mutationID: MutationIDV1) throws {
        guard policy.workspaceID == workspaceID,
              target.workspaceID == workspaceID.rawValue.uuidString.lowercased(),
              orderedItems.count <= policy.maximumSequenceItems,
              orderedItems.map(\.ordinal) == Array(0..<orderedItems.count),
              Set(orderedItems.map(\.evidenceID)).count == orderedItems.count,
              Set(orderedItems.map(\.contentID)).count == orderedItems.count,
              orderedItems.allSatisfy({ $0.target == target && $0.caption.text.utf8.count <= policy.maximumCaptionBytes && ($0.accessibilityDescription?.text.utf8.count ?? 0) <= policy.maximumAccessibilityDescriptionBytes }),
              revision > 0,
              (predecessor == nil && revision == 1) || (predecessor?.sequenceID == sequenceID && predecessor.map({ $0.revision < UInt64.max && $0.revision + 1 == revision }) == true) else {
            throw EvidenceMetadataFailureV1.invalidSuccessor
        }
        schemaVersion = Self.schemaVersion; self.sequenceID = sequenceID; self.workspaceID = workspaceID
        self.target = target; self.policy = policy; self.orderedItems = orderedItems; self.predecessor = predecessor
        self.revision = revision; self.mutationID = mutationID
        sequenceSHA256 = try EvidenceMetadataCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            sequenceID: sequenceID, workspaceID: workspaceID, target: target, policy: policy,
            orderedItems: orderedItems, predecessor: predecessor, revision: revision, mutationID: mutationID))
    }

    func validateSuccessor(of prior: Self) throws {
        let (nextRevision, overflow) = prior.revision.addingReportingOverflow(1)
        guard predecessor == (try prior.reference), sequenceID == prior.sequenceID,
              !overflow, workspaceID == prior.workspaceID, target == prior.target, revision == nextRevision else {
            throw EvidenceMetadataFailureV1.invalidSuccessor
        }
    }
    func validate() throws {
        let rebuilt = try Self(sequenceID: sequenceID, workspaceID: workspaceID, target: target,
            policy: policy, orderedItems: orderedItems, predecessor: predecessor,
            revision: revision, mutationID: mutationID)
        guard rebuilt == self else { throw EvidenceMetadataFailureV1.invalidDigest }
    }
    private struct Basis: Codable { let schemaVersion: Int; let sequenceID: UUID; let workspaceID: WorkspaceID; let target: EvidenceAssociationTargetV1; let policy: EvidenceCurationPolicyV1; let orderedItems: [EvidenceSequenceItemV1]; let predecessor: EvidenceSequenceReferenceV1?; let revision: UInt64; let mutationID: MutationIDV1 }
}

struct EvidenceMetadataMutationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let expectedSequenceRevision: UInt64
    let associationEvent: EvidenceAssociationV1
    let sequenceSuccessor: EvidenceSequenceV1

    init(workspaceID: WorkspaceID, mutationID: MutationIDV1, expectedSequenceRevision: UInt64,
         associationEvent: EvidenceAssociationV1, sequenceSuccessor: EvidenceSequenceV1) throws {
        let (nextRevision, overflow) = expectedSequenceRevision.addingReportingOverflow(1)
        let matchingItemCount: Int
        if associationEvent.action == .removed {
            matchingItemCount = 0
        } else {
            let binding = try EvidenceAssociationBindingV1(associationEvent)
            matchingItemCount = sequenceSuccessor.orderedItems.filter {
                $0.evidenceID == associationEvent.evidenceID && $0.associationBinding == binding
            }.count
        }
        guard sequenceSuccessor.workspaceID == workspaceID, sequenceSuccessor.mutationID == mutationID,
              !overflow, sequenceSuccessor.revision == nextRevision,
              associationEvent.workspaceID == workspaceID.rawValue.uuidString.lowercased(),
              associationEvent.mutationID == mutationID.rawValue.uuidString.lowercased(),
              (associationEvent.action == .removed
                ? sequenceSuccessor.orderedItems.allSatisfy({ $0.evidenceID != associationEvent.evidenceID })
                : matchingItemCount == 1) else {
            throw EvidenceMetadataFailureV1.invalidSuccessor
        }
        self.workspaceID = workspaceID; self.mutationID = mutationID; self.expectedSequenceRevision = expectedSequenceRevision
        self.associationEvent = associationEvent; self.sequenceSuccessor = sequenceSuccessor
    }

    func validate() throws {
        guard self == (try Self(workspaceID: workspaceID, mutationID: mutationID,
            expectedSequenceRevision: expectedSequenceRevision, associationEvent: associationEvent,
            sequenceSuccessor: sequenceSuccessor)) else { throw EvidenceMetadataFailureV1.invalidValue }
    }
}

extension EvidenceAssociationV1 {
    var associationSHA256: String { get throws { try EvidenceMetadataCanonicalCodecV1.sha256(self) } }

    func validateSuccessor(of prior: Self) throws {
        let (nextRevision, overflow) = prior.resultingEvidenceRevision.addingReportingOverflow(1)
        guard !overflow, workspaceID == prior.workspaceID, evidenceID == prior.evidenceID,
              expectedEvidenceRevision == prior.resultingEvidenceRevision,
              resultingEvidenceRevision == nextRevision,
              supersedesAssociationEventID == prior.associationEventID,
              previousContentID == prior.contentID, previousTarget == prior.target,
              associationEventID != prior.associationEventID, mutationID != prior.mutationID,
              action != .assigned else { throw EvidenceMetadataFailureV1.invalidSuccessor }
    }
}

enum EvidenceMetadataGraphV1 {
    static func validate(sequences: [EvidenceSequenceV1], associationEvents: [EvidenceAssociationV1]) throws {
        guard sequences.count <= ContentContractLimitsV1.maximumManifestEntries,
              associationEvents.count <= ContentContractLimitsV1.maximumAssociations else {
            throw EvidenceMetadataFailureV1.limitExceeded
        }
        try EvidenceAssociationLedgerV1.validate(associationEvents)
        let eventKeys = associationEvents.map { "\($0.workspaceID)|\($0.associationEventID)" }
        guard Set(eventKeys).count == eventKeys.count else { throw EvidenceMetadataFailureV1.duplicateIdentity }
        let eventByKey = Dictionary(uniqueKeysWithValues: zip(eventKeys, associationEvents))
        let sequenceKeys = sequences.map { "\($0.sequenceID.uuidString.lowercased())|\(String(format: "%020llu", $0.revision))" }
        guard Set(sequenceKeys).count == sequenceKeys.count else { throw EvidenceMetadataFailureV1.duplicateIdentity }
        var groups: [UUID: [EvidenceSequenceV1]] = [:]
        for sequence in sequences { groups[sequence.sequenceID, default: []].append(sequence) }
        for sequenceID in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let history = groups[sequenceID], history.first?.revision == 1 else { throw EvidenceMetadataFailureV1.invalidSuccessor }
            var previous: EvidenceSequenceV1?
            for sequence in history {
                if let previous { try sequence.validateSuccessor(of: previous) }
                for item in sequence.orderedItems {
                    let key = "\(sequence.target.workspaceID)|\(item.associationBinding.associationEventID)"
                    guard let event = eventByKey[key], event.evidenceID == item.evidenceID,
                          event.contentID == item.contentID, event.target == item.target,
                          event.resultingEvidenceRevision == item.associationBinding.resultingEvidenceRevision,
                          (try event.associationSHA256) == item.associationBinding.associationSHA256 else {
                        throw EvidenceMetadataFailureV1.staleAssociation
                    }
                }
                previous = sequence
            }
        }
    }
}

enum EvidenceMetadataCanonicalCodecV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let data = try WorkspaceMutationCanonicalV1.data(value)
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else { throw EvidenceMetadataFailureV1.limitExceeded }
        return data
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else { throw EvidenceMetadataFailureV1.limitExceeded }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try Self.data(value) == data else { throw EvidenceMetadataFailureV1.invalidDigest }
        return value
    }
}

extension EvidenceCurationPolicyV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, policyID, workspaceID, maximumSequenceItems, maximumCaptionBytes, maximumAccessibilityDescriptionBytes }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceMetadataFailureV1.incompatibleVersion }
        try self.init(policyID: c.decode(UUID.self, forKey: .policyID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), maximumSequenceItems: c.decode(Int.self, forKey: .maximumSequenceItems), maximumCaptionBytes: c.decode(Int.self, forKey: .maximumCaptionBytes), maximumAccessibilityDescriptionBytes: c.decode(Int.self, forKey: .maximumAccessibilityDescriptionBytes))
    }
}

extension EvidenceReviewedCaptionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case text, provenance, reviewer, reviewedAt }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(text: c.decode(String.self, forKey: .text), provenance: c.decode(EvidenceReviewedTextProvenanceV1.self, forKey: .provenance), reviewer: c.decode(ActorSnapshotV1.self, forKey: .reviewer), reviewedAt: c.decode(Date.self, forKey: .reviewedAt))
    }
}

extension EvidenceAccessibilityDescriptionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case text, provenance, reviewer, reviewedAt }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(text: c.decode(String.self, forKey: .text), provenance: c.decode(EvidenceReviewedTextProvenanceV1.self, forKey: .provenance), reviewer: c.decode(ActorSnapshotV1.self, forKey: .reviewer), reviewedAt: c.decode(Date.self, forKey: .reviewedAt))
    }
}

extension EvidenceAssociationBindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case associationEventID, resultingEvidenceRevision, associationSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        let eventID = try c.decode(String.self, forKey: .associationEventID), revision = try c.decode(Int.self, forKey: .resultingEvidenceRevision), digest = try c.decode(String.self, forKey: .associationSHA256)
        guard ContentContractValidationV1.validID(eventID), revision > 0, KernelCanonicalHashV1.validSHA256(digest) else { throw EvidenceMetadataFailureV1.invalidValue }
        associationEventID = eventID; resultingEvidenceRevision = revision; associationSHA256 = digest
    }
}

extension EvidenceSequenceItemV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case evidenceID, contentID, role, caption, accessibilityDescription, ordinal, target, associationBinding }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: CodingKeys.allCases.filter({ $0 != .accessibilityDescription }).map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        let evidenceID = try c.decode(String.self, forKey: .evidenceID), contentID = try c.decode(String.self, forKey: .contentID), caption = try c.decode(EvidenceReviewedCaptionV1.self, forKey: .caption), description = try c.decodeIfPresent(EvidenceAccessibilityDescriptionV1.self, forKey: .accessibilityDescription), ordinal = try c.decode(Int.self, forKey: .ordinal), target = try c.decode(EvidenceAssociationTargetV1.self, forKey: .target), binding = try c.decode(EvidenceAssociationBindingV1.self, forKey: .associationBinding)
        guard ContentContractValidationV1.validID(evidenceID), ContentContractValidationV1.validID(contentID), ordinal >= 0,
              caption.reviewer.workspaceID.rawValue.uuidString.lowercased() == target.workspaceID,
              description.map({ $0.reviewer.workspaceID == caption.reviewer.workspaceID }) ?? true else { throw EvidenceMetadataFailureV1.invalidValue }
        self.evidenceID = evidenceID; self.contentID = contentID; role = try c.decode(EvidenceRoleV1.self, forKey: .role); self.caption = caption; accessibilityDescription = description; self.ordinal = ordinal; self.target = target; associationBinding = binding
    }
}

extension EvidenceSequenceReferenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case sequenceID, revision, sequenceSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sequenceID: c.decode(UUID.self, forKey: .sequenceID), revision: c.decode(UInt64.self, forKey: .revision), sequenceSHA256: c.decode(String.self, forKey: .sequenceSHA256))
    }
}

extension EvidenceSequenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, sequenceID, workspaceID, target, policy, orderedItems, predecessor, revision, mutationID, sequenceSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: CodingKeys.allCases.filter({ $0 != .predecessor }).map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceMetadataFailureV1.incompatibleVersion }
        let rebuilt = try Self(sequenceID: c.decode(UUID.self, forKey: .sequenceID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), target: c.decode(EvidenceAssociationTargetV1.self, forKey: .target), policy: c.decode(EvidenceCurationPolicyV1.self, forKey: .policy), orderedItems: c.decode([EvidenceSequenceItemV1].self, forKey: .orderedItems), predecessor: c.decodeIfPresent(EvidenceSequenceReferenceV1.self, forKey: .predecessor), revision: c.decode(UInt64.self, forKey: .revision), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID))
        guard rebuilt.sequenceSHA256 == (try c.decode(String.self, forKey: .sequenceSHA256)) else { throw EvidenceMetadataFailureV1.invalidDigest }; self = rebuilt
    }
}

extension EvidenceMetadataMutationV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, mutationID, expectedSequenceRevision, associationEvent, sequenceSuccessor }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), expectedSequenceRevision: c.decode(UInt64.self, forKey: .expectedSequenceRevision), associationEvent: c.decode(EvidenceAssociationV1.self, forKey: .associationEvent), sequenceSuccessor: c.decode(EvidenceSequenceV1.self, forKey: .sequenceSuccessor))
    }
}
