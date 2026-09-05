import Foundation

// MARK: - Shared closed activity vocabulary

enum ActivityContractFailureV2: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case incompatibleVersion
    case unknownKindMutation
    case invalidTransition
    case kindFrozen
    case staleRevision
    case duplicateIdentity
    case wrongWorkspace
    case missingReference
    case unsupportedClaim
    case limitExceeded
}

enum ActivityContractValidationV2 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static let maximumTextBytes = 4_096
    static let maximumReasonBytes = 1_024
    static let maximumFacets = 32
    static let maximumTasks = 512
    static let maximumScopeItems = 512
    static let maximumReferences = 1_024

    static func text(_ value: String, maximumBytes: Int = maximumTextBytes, allowEmpty: Bool = false) -> Bool {
        guard (allowEmpty || !value.isEmpty), value.utf8.count <= maximumBytes,
              value == value.precomposedStringWithCanonicalMapping else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value >= 0x20 && value != 0x7F && !(0x80...0x9F).contains(value)
                && ![0x202A, 0x202B, 0x202C, 0x202D, 0x202E].contains(value)
        }
    }

    static func token(_ value: String, maximumBytes: Int = 128) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || [45, 46, 58, 95].contains($0)
        }
    }

    static func digest(_ value: String) -> Bool { KernelCanonicalHashV1.validSHA256(value) }

    static func sortedUnique<T: Comparable & Hashable>(_ values: [T]) -> Bool {
        values == values.sorted() && Set(values).count == values.count
    }
}

private struct ActivityDynamicCodingKeyV2: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

private enum ActivityClosedCodingV2 {
    static func requireExactKeys(_ decoder: Decoder, _ expected: Set<String>) throws {
        let values = try decoder.container(keyedBy: ActivityDynamicCodingKeyV2.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else {
            throw ActivityContractFailureV2.invalidValue
        }
    }
}

private enum ActivityActorRebindingV2 {
    static func rebound(_ value: ActorSnapshotV1, to workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        try value.validate()
        let actor = try LocalActorReferenceV1(
            actorReferenceID: value.actor.actorReferenceID,
            workspaceID: workspaceID,
            partyID: value.actor.partyID,
            displayName: value.actor.displayName
        )
        return try ActorSnapshotV1(
            snapshotID: value.snapshotID,
            workspaceID: workspaceID,
            actor: actor,
            responsibility: value.responsibility,
            displayNameAtTime: value.displayNameAtTime,
            capturedAt: value.capturedAt
        )
    }
}

enum ActivityKindV2: Hashable, Sendable {
    case inspection
    case survey
    case preventiveMaintenance
    case repair
    case operationalRecheck
    case installation
    case punchReview
    case unknown(String)

    static let knownCases: [ActivityKindV2] = [
        .inspection, .survey, .preventiveMaintenance, .repair,
        .operationalRecheck, .installation, .punchReview
    ]

    var rawValue: String {
        switch self {
        case .inspection: return "INSPECTION"
        case .survey: return "SURVEY"
        case .preventiveMaintenance: return "PREVENTIVE_MAINTENANCE"
        case .repair: return "REPAIR"
        case .operationalRecheck: return "OPERATIONAL_RECHECK"
        case .installation: return "INSTALLATION"
        case .punchReview: return "PUNCH_REVIEW"
        case let .unknown(value): return value
        }
    }

    init(preservingRawValue value: String) throws {
        guard ActivityContractValidationV2.token(value) else { throw ActivityContractFailureV2.invalidValue }
        switch value {
        case "INSPECTION": self = .inspection
        case "SURVEY": self = .survey
        case "PREVENTIVE_MAINTENANCE": self = .preventiveMaintenance
        case "REPAIR": self = .repair
        case "OPERATIONAL_RECHECK": self = .operationalRecheck
        case "INSTALLATION": self = .installation
        case "PUNCH_REVIEW": self = .punchReview
        default: self = .unknown(value)
        }
    }

    var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    func requireKnownForMutation() throws {
        guard isKnown else { throw ActivityContractFailureV2.unknownKindMutation }
    }
}

extension ActivityKindV2: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = try ActivityKindV2(preservingRawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }
}

enum ActivityKindCompatibilityDispositionV2: String, Codable, CaseIterable, Hashable, Sendable {
    case exactV1 = "EXACT_V1"
    case v2Only = "V2_ONLY"
    case unknownReadExportOnly = "UNKNOWN_READ_EXPORT_ONLY"
}

enum ActivityCanonicalStorageAuthorityV2 {
    static func admitsNewC47RowMutation(_ kind: ActivityKindV2) -> Bool {
        kind == .installation || kind == .punchReview
    }

    static func requireNewC47RowMutationAuthority(_ kind: ActivityKindV2) throws {
        try kind.requireKnownForMutation()
        guard admitsNewC47RowMutation(kind) else {
            throw ActivityContractFailureV2.unknownKindMutation
        }
    }
}

enum ActivityKindV1CompatibilityAdapterV2 {
    static func v2(_ value: ActivityKindV1) -> ActivityKindV2 {
        switch value {
        case .inspection: return .inspection
        case .survey: return .survey
        case .preventiveMaintenance: return .preventiveMaintenance
        case .repair: return .repair
        case .operationalRecheck: return .operationalRecheck
        }
    }

    static func v1(_ value: ActivityKindV2) -> ActivityKindV1? {
        switch value {
        case .inspection: return .inspection
        case .survey: return .survey
        case .preventiveMaintenance: return .preventiveMaintenance
        case .repair: return .repair
        case .operationalRecheck: return .operationalRecheck
        case .installation, .punchReview, .unknown: return nil
        }
    }

    static func disposition(_ value: ActivityKindV2) -> ActivityKindCompatibilityDispositionV2 {
        if case .unknown = value { return .unknownReadExportOnly }
        return v1(value) == nil ? .v2Only : .exactV1
    }
}

enum ActivityStateV2: String, Codable, CaseIterable, Hashable, Sendable {
    case draft = "DRAFT"
    case preflightRequired = "PREFLIGHT_REQUIRED"
    case ready = "READY"
    case inProgress = "IN_PROGRESS"
    case paused = "PAUSED"
    case fieldComplete = "FIELD_COMPLETE"
    case readyForReview = "READY_FOR_REVIEW"
    case finalized = "FINALIZED"
    case deferred = "DEFERRED"
    case unableToComplete = "UNABLE_TO_COMPLETE"
    case cancelled = "CANCELLED"
    case changesRequested = "CHANGES_REQUESTED"
    case superseded = "SUPERSEDED"

    var hasStarted: Bool {
        switch self {
        case .inProgress, .paused, .fieldComplete, .readyForReview, .finalized,
             .unableToComplete, .changesRequested, .superseded: return true
        case .draft, .preflightRequired, .ready, .deferred, .cancelled: return false
        }
    }

    func permits(startedAt: Date?) -> Bool {
        switch self {
        case .draft, .preflightRequired, .ready:
            return startedAt == nil
        case .inProgress, .paused, .fieldComplete, .readyForReview, .finalized, .changesRequested:
            return startedAt != nil
        case .deferred, .unableToComplete, .cancelled, .superseded:
            return true
        }
    }

    func permits(finalizedAt: Date?) -> Bool {
        switch self {
        case .finalized: return finalizedAt != nil
        case .superseded: return true
        default: return finalizedAt == nil
        }
    }
}

enum ActivityReviewStateV2: String, Codable, CaseIterable, Hashable, Sendable {
    case notRequested = "NOT_REQUESTED"
    case pending = "PENDING"
    case changesRequested = "CHANGES_REQUESTED"
    case acceptedRecordedFacts = "ACCEPTED_RECORDED_FACTS"
}

enum ActivityStateMachineV2 {
    static func permits(from: ActivityStateV2, to: ActivityStateV2) -> Bool {
        switch (from, to) {
        case (.draft, .preflightRequired), (.draft, .cancelled),
             (.preflightRequired, .ready), (.preflightRequired, .deferred),
             (.preflightRequired, .unableToComplete), (.preflightRequired, .cancelled),
             (.ready, .inProgress), (.ready, .deferred), (.ready, .unableToComplete),
             (.ready, .cancelled), (.inProgress, .paused), (.inProgress, .fieldComplete),
             (.inProgress, .deferred), (.inProgress, .unableToComplete), (.inProgress, .cancelled),
             (.paused, .inProgress), (.paused, .deferred), (.paused, .unableToComplete),
             (.paused, .cancelled), (.fieldComplete, .readyForReview),
             (.fieldComplete, .inProgress), (.fieldComplete, .unableToComplete),
             (.fieldComplete, .cancelled), (.readyForReview, .finalized),
             (.readyForReview, .changesRequested), (.changesRequested, .inProgress),
             (.changesRequested, .fieldComplete), (.changesRequested, .cancelled),
             (.deferred, .preflightRequired), (.deferred, .ready), (.deferred, .cancelled),
             (.deferred, .superseded), (.unableToComplete, .preflightRequired),
             (.unableToComplete, .superseded), (.finalized, .superseded):
            return true
        default:
            return false
        }
    }

    static var exhaustiveTable: [ActivityStateV2: [ActivityStateV2]] {
        Dictionary(uniqueKeysWithValues: ActivityStateV2.allCases.map { from in
            (from, ActivityStateV2.allCases.filter { permits(from: from, to: $0) })
        })
    }
}

enum ActivityReadinessFacetKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case subject = "SUBJECT"
    case access = "ACCESS"
    case site = "SITE"
    case material = "MATERIAL"
    case weather = "WEATHER"
    case equipment = "EQUIPMENT"
    case reference = "REFERENCE"
    case otherRecorded = "OTHER_RECORDED"
}

enum ActivityReadinessDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ready = "READY"
    case blocked = "BLOCKED"
    case deferred = "DEFERRED"
    case notApplicable = "NOT_APPLICABLE"
}

struct ActivityReadinessFacetV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let facetID: String
    let kind: ActivityReadinessFacetKindV1
    let disposition: ActivityReadinessDispositionV1
    let reason: String?

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.facetID < rhs.facetID }

    init(facetID: String, kind: ActivityReadinessFacetKindV1,
         disposition: ActivityReadinessDispositionV1, reason: String? = nil) throws {
        self.facetID = facetID; self.kind = kind; self.disposition = disposition; self.reason = reason
        try validate()
    }

    func validate() throws {
        guard ActivityContractValidationV2.token(facetID),
              reason.map({ ActivityContractValidationV2.text($0, maximumBytes: ActivityContractValidationV2.maximumReasonBytes) }) ?? true,
              (disposition == .ready || disposition == .notApplicable) == (reason == nil) else {
            throw ActivityContractFailureV2.invalidValue
        }
    }

}

enum ActivityCompletionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case completedAsRecorded = "COMPLETED_AS_RECORDED"
    case completedWithOpenItems = "COMPLETED_WITH_OPEN_ITEMS"
    case partiallyCompleted = "PARTIALLY_COMPLETED"
    case unableAttemptRecorded = "UNABLE_ATTEMPT_RECORDED"
    case cancelled = "CANCELLED"
}

struct ActivityAmendmentLinkV1: Codable, Equatable, Hashable, Sendable {
    let predecessorActivityID: UUID
    let predecessorRevision: UInt64
    let predecessorSHA256: String
    let reason: String

    init(predecessorActivityID: UUID, predecessorRevision: UInt64,
         predecessorSHA256: String, reason: String) throws {
        guard predecessorActivityID != ActivityContractValidationV2.zeroUUID,
              predecessorRevision > 0, ActivityContractValidationV2.digest(predecessorSHA256),
              ActivityContractValidationV2.text(reason, maximumBytes: ActivityContractValidationV2.maximumReasonBytes) else {
            throw ActivityContractFailureV2.invalidValue
        }
        self.predecessorActivityID = predecessorActivityID; self.predecessorRevision = predecessorRevision
        self.predecessorSHA256 = predecessorSHA256; self.reason = reason
        try validate()
    }

    func validate() throws {
        guard predecessorActivityID != ActivityContractValidationV2.zeroUUID,
              predecessorRevision > 0, ActivityContractValidationV2.digest(predecessorSHA256),
              ActivityContractValidationV2.text(reason, maximumBytes: ActivityContractValidationV2.maximumReasonBytes) else {
            throw ActivityContractFailureV2.invalidValue
        }
    }

    func rebound(predecessorSHA256: String) throws -> Self {
        try Self(
            predecessorActivityID: predecessorActivityID,
            predecessorRevision: predecessorRevision,
            predecessorSHA256: predecessorSHA256,
            reason: reason
        )
    }
}

enum ActivityVariationKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case basisCorrected = "BASIS_CORRECTED"
    case recordedScopeChanged = "RECORDED_SCOPE_CHANGED"
    case optionalPlanReferenceChanged = "OPTIONAL_PLAN_REFERENCE_CHANGED"
    case physicalPlacementReferenceChanged = "PHYSICAL_PLACEMENT_REFERENCE_CHANGED"
    case otherRecorded = "OTHER_RECORDED"
}

/// Variations are immutable entries embedded in the shared envelope. A later
/// mutation may append entries but may never replace, reorder, or delete a
/// previously accepted variation.
struct ActivityVariationV1: Codable, Equatable, Sendable {
    let variationID: UUID
    let workspaceID: WorkspaceID
    let revision: UInt64
    let kind: ActivityVariationKindV1
    let predecessorBasisSHA256: String
    let successorBasisSHA256: String
    let reason: String
    let actor: ActorSnapshotV1
    let occurredAt: Date
    let mutationID: MutationIDV1
    let variationSHA256: String

    init(variationID: UUID, workspaceID: WorkspaceID, revision: UInt64, kind: ActivityVariationKindV1,
         predecessorBasisSHA256: String, successorBasisSHA256: String,
         reason: String, actor: ActorSnapshotV1, occurredAt: Date,
         mutationID: MutationIDV1) throws {
        let basis = Basis(variationID: variationID, workspaceID: workspaceID, revision: revision, kind: kind,
                          predecessorBasisSHA256: predecessorBasisSHA256,
                          successorBasisSHA256: successorBasisSHA256, reason: reason,
                          actor: actor, occurredAt: occurredAt, mutationID: mutationID)
        self.variationID = variationID; self.workspaceID = workspaceID; self.revision = revision; self.kind = kind
        self.predecessorBasisSHA256 = predecessorBasisSHA256
        self.successorBasisSHA256 = successorBasisSHA256; self.reason = reason
        self.actor = actor; self.occurredAt = occurredAt; self.mutationID = mutationID
        variationSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
        try validate()
    }

    func validate() throws {
        try actor.validate()
        guard variationID != ActivityContractValidationV2.zeroUUID, revision > 0,
              workspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
              actor.workspaceID == workspaceID,
              ActivityContractValidationV2.digest(predecessorBasisSHA256),
              ActivityContractValidationV2.digest(successorBasisSHA256),
              predecessorBasisSHA256 != successorBasisSHA256,
              ActivityContractValidationV2.text(reason, maximumBytes: ActivityContractValidationV2.maximumReasonBytes),
              variationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw ActivityContractFailureV2.invalidValue
        }
    }

    func rebound(
        to workspaceID: WorkspaceID,
        predecessorBasisSHA256: String,
        successorBasisSHA256: String,
        mutationID: MutationIDV1
    ) throws -> Self {
        try Self(variationID: variationID, workspaceID: workspaceID, revision: revision, kind: kind,
                 predecessorBasisSHA256: predecessorBasisSHA256,
                 successorBasisSHA256: successorBasisSHA256, reason: reason,
                 actor: ActivityActorRebindingV2.rebound(actor, to: workspaceID),
                 occurredAt: occurredAt, mutationID: mutationID)
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try rebound(
            to: workspaceID,
            predecessorBasisSHA256: predecessorBasisSHA256,
            successorBasisSHA256: successorBasisSHA256,
            mutationID: mutationID
        )
    }

    private var basis: Basis { .init(variationID: variationID, workspaceID: workspaceID, revision: revision, kind: kind,
        predecessorBasisSHA256: predecessorBasisSHA256, successorBasisSHA256: successorBasisSHA256,
        reason: reason, actor: actor, occurredAt: occurredAt, mutationID: mutationID) }
    private struct Basis: Codable { let variationID:UUID;let workspaceID:WorkspaceID;let revision:UInt64;let kind:ActivityVariationKindV1
        let predecessorBasisSHA256:String;let successorBasisSHA256:String;let reason:String
        let actor:ActorSnapshotV1;let occurredAt:Date;let mutationID:MutationIDV1 }
}

struct ActivityRouteV2: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let kind: ActivityKindV2
    let routeID: String

    init(workspaceID: WorkspaceID, activityID: UUID, kind: ActivityKindV2, routeID: String) throws {
        self.workspaceID = workspaceID; self.activityID = activityID; self.kind = kind; self.routeID = routeID
        try validate()
    }

    func validate() throws {
        try kind.requireKnownForMutation()
        guard workspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
              activityID != ActivityContractValidationV2.zeroUUID,
              ActivityContractValidationV2.token(routeID) else {
            throw ActivityContractFailureV2.invalidValue
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try WorkspaceMutationCanonicalV1.data(self)
    }

    static func decodeCanonical(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else { throw ActivityContractFailureV2.invalidValue }
        return value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, activityID, kind, routeID
    }

    init(from decoder: Decoder) throws {
        try ActivityClosedCodingV2.requireExactKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
                      activityID: values.decode(UUID.self, forKey: .activityID),
                      kind: values.decode(ActivityKindV2.self, forKey: .kind),
                      routeID: values.decode(String.self, forKey: .routeID))
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(activityID, forKey: .activityID)
        try values.encode(kind, forKey: .kind)
        try values.encode(routeID, forKey: .routeID)
    }
}

struct FindingSourceContextV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let activityKind: ActivityKindV2
    let activityRevision: UInt64
    let activitySHA256: String
    let taskOrScopeID: String?

    init(workspaceID: WorkspaceID, activityID: UUID, activityKind: ActivityKindV2,
         activityRevision: UInt64, activitySHA256: String, taskOrScopeID: String? = nil) throws {
        try activityKind.requireKnownForMutation()
        guard activityID != ActivityContractValidationV2.zeroUUID, activityRevision > 0,
              ActivityContractValidationV2.digest(activitySHA256),
              taskOrScopeID.map({ ActivityContractValidationV2.token($0) }) ?? true else {
            throw ActivityContractFailureV2.invalidValue
        }
        self.workspaceID = workspaceID; self.activityID = activityID; self.activityKind = activityKind
        self.activityRevision = activityRevision; self.activitySHA256 = activitySHA256
        self.taskOrScopeID = taskOrScopeID
    }

    func rebound(
        to workspaceID: WorkspaceID,
        activityID: UUID,
        mappedActivitySHA256: String
    ) throws -> Self {
        try Self(
            workspaceID: workspaceID,
            activityID: activityID,
            activityKind: activityKind,
            activityRevision: activityRevision,
            activitySHA256: mappedActivitySHA256,
            taskOrScopeID: taskOrScopeID
        )
    }
}

struct ActivitySessionEnvelopeV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let activityID: UUID
    let workspaceID: WorkspaceID
    let kind: ActivityKindV2
    let state: ActivityStateV2
    let reviewState: ActivityReviewStateV2
    let subjectID: UUID
    let title: String
    let readiness: [ActivityReadinessFacetV1]
    let readinessPolicy: ActivityReadinessPolicyBindingV2?
    let variations: [ActivityVariationV1]
    let amendment: ActivityAmendmentLinkV1?
    let currentBasisReference: ActivityBasisHeadReferenceV2?
    let installationCloseout: InstallationCloseoutV1?
    let punchReviewCloseout: PunchReviewCloseoutV1?
    let completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1?
    let startedAt: Date?
    let finalizedAt: Date?
    let revision: UInt64
    let mutationID: MutationIDV1
    let predecessorEnvelopeSHA256: String?
    let envelopeSHA256: String

    init(activityID: UUID, workspaceID: WorkspaceID, kind: ActivityKindV2, state: ActivityStateV2,
         reviewState: ActivityReviewStateV2, subjectID: UUID, title: String,
         readiness: [ActivityReadinessFacetV1],
         readinessPolicy: ActivityReadinessPolicyBindingV2? = nil,
         variations: [ActivityVariationV1] = [],
         amendment: ActivityAmendmentLinkV1? = nil,
         currentBasisReference: ActivityBasisHeadReferenceV2? = nil,
         installationCloseout: InstallationCloseoutV1? = nil,
         punchReviewCloseout: PunchReviewCloseoutV1? = nil,
         completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1? = nil,
         startedAt: Date? = nil, finalizedAt: Date? = nil, revision: UInt64,
         mutationID: MutationIDV1, predecessorEnvelopeSHA256: String? = nil) throws {
        let ordered = readiness.sorted()
        let orderedVariations = variations.sorted { $0.revision < $1.revision }
        let basis = Basis(schemaVersion: Self.schemaVersion, activityID: activityID, workspaceID: workspaceID,
                          kind: kind, state: state, reviewState: reviewState, subjectID: subjectID,
                          title: title, readiness: ordered, readinessPolicy: readinessPolicy,
                          variations: orderedVariations,
                          amendment: amendment,currentBasisReference:currentBasisReference,
                          installationCloseout:installationCloseout,punchReviewCloseout:punchReviewCloseout,
                          completedSnapshotReference: completedSnapshotReference,
                          startedAt: startedAt,
                          finalizedAt: finalizedAt, revision: revision, mutationID: mutationID,
                          predecessorEnvelopeSHA256: predecessorEnvelopeSHA256)
        schemaVersion = Self.schemaVersion; self.activityID = activityID; self.workspaceID = workspaceID
        self.kind = kind; self.state = state; self.reviewState = reviewState; self.subjectID = subjectID
        self.title = title; self.readiness = ordered; self.readinessPolicy = readinessPolicy
        self.variations = orderedVariations
        self.amendment = amendment;self.currentBasisReference=currentBasisReference
        self.installationCloseout=installationCloseout;self.punchReviewCloseout=punchReviewCloseout
        self.completedSnapshotReference = completedSnapshotReference
        self.startedAt = startedAt
        self.finalizedAt = finalizedAt; self.revision = revision; self.mutationID = mutationID
        self.predecessorEnvelopeSHA256 = predecessorEnvelopeSHA256
        envelopeSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
        try validateForMutation()
    }

    func validateForRead() throws {
        try readiness.forEach { try $0.validate() }
        try validateReadinessPolicy()
        try variations.forEach { try $0.validate() }
        try amendment?.validate()
        try currentBasisReference?.validate();try installationCloseout?.validate();try punchReviewCloseout?.validate()
        try validateFamilyPayload()
        try completedSnapshotReference?.validate()
        guard schemaVersion == Self.schemaVersion, activityID != ActivityContractValidationV2.zeroUUID,
              subjectID != ActivityContractValidationV2.zeroUUID, revision > 0,
              ActivityContractValidationV2.text(title), readiness.count <= ActivityContractValidationV2.maximumFacets,
              ActivityContractValidationV2.sortedUnique(readiness.map(\.facetID)),
              variations.count <= ActivityContractValidationV2.maximumReferences,
              Set(variations.map(\.variationID)).count == variations.count,
              Set(variations.map(\.variationSHA256)).count == variations.count,
              variations.enumerated().allSatisfy { UInt64($0.offset + 1) == $0.element.revision },
              variations.allSatisfy { $0.workspaceID == workspaceID && $0.actor.workspaceID == workspaceID },
              currentBasisReference.map{$0.workspaceID==workspaceID && $0.activityID==activityID} ?? true,
              completedSnapshotReference.map { $0.workspaceID == workspaceID && $0.activityID == activityID } ?? true,
              Self.completedSnapshotReferenceIsValid(completedSnapshotReference, for: state),
              predecessorEnvelopeSHA256.map(ActivityContractValidationV2.digest) ?? true,
              (revision == 1 && predecessorEnvelopeSHA256 == nil)
                || (revision > 1 && predecessorEnvelopeSHA256 != nil),
              state.permits(startedAt: startedAt), state.permits(finalizedAt: finalizedAt),
              startedAt.map({ finalizedAt.map { $0 >= $1 } ?? true }) ?? true,
              Self.reviewStateIsValid(reviewState, for: state),
              envelopeSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw ActivityContractFailureV2.invalidValue
        }
    }

    func validateForMutation() throws { try validateForRead(); try kind.requireKnownForMutation() }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateForRead(); try validateForMutation()
        let (expectedRevision, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard workspaceID == predecessor.workspaceID, activityID == predecessor.activityID,
              predecessorEnvelopeSHA256 == predecessor.envelopeSHA256,
              (state == predecessor.state || ActivityStateMachineV2.permits(from: predecessor.state, to: state)),
              !overflow, revision == expectedRevision else { throw ActivityContractFailureV2.invalidTransition }
        if predecessor.startedAt != nil || startedAt != nil {
            guard kind == predecessor.kind else { throw ActivityContractFailureV2.kindFrozen }
        }
        if let predecessorStartedAt = predecessor.startedAt {
            guard startedAt == predecessorStartedAt else { throw ActivityContractFailureV2.invalidTransition }
        }
        if predecessor.finalizedAt != nil {
            guard finalizedAt == predecessor.finalizedAt else { throw ActivityContractFailureV2.invalidTransition }
        }
        if predecessor.state == .finalized || predecessor.state == .superseded {
            guard completedSnapshotReference == predecessor.completedSnapshotReference else {
                throw ActivityContractFailureV2.invalidTransition
            }
        } else if state == .superseded {
            guard completedSnapshotReference == nil else {
                throw ActivityContractFailureV2.invalidTransition
            }
        }
        if let predecessorPolicy = predecessor.readinessPolicy {
            guard readinessPolicy == predecessorPolicy else {
                throw ActivityContractFailureV2.invalidTransition
            }
        }
        if let predecessorBasis=predecessor.currentBasisReference,currentBasisReference != predecessorBasis{
            guard let currentBasisReference else{throw ActivityContractFailureV2.invalidTransition}
            let(next,overflow)=predecessorBasis.revision.addingReportingOverflow(1)
            guard !overflow,currentBasisReference.revision==next else{throw ActivityContractFailureV2.staleRevision}
        }else if predecessor.currentBasisReference==nil,currentBasisReference != nil{
            guard currentBasisReference?.revision==1 else{throw ActivityContractFailureV2.staleRevision}
        }
        if let value=predecessor.installationCloseout{guard installationCloseout==value else{throw ActivityContractFailureV2.invalidTransition}}
        if let value=predecessor.punchReviewCloseout{guard punchReviewCloseout==value else{throw ActivityContractFailureV2.invalidTransition}}
        guard variations.starts(with: predecessor.variations),
              variations.dropFirst(predecessor.variations.count).allSatisfy({ $0.mutationID == mutationID }) else {
            throw ActivityContractFailureV2.invalidTransition
        }
    }

    func rebound(to workspaceID: WorkspaceID, activityID: UUID, subjectID: UUID,
                 revision: UInt64, mutationID: MutationIDV1,
                 mappedPredecessorEnvelopeSHA256: String?,
                 mappedVariations: [ActivityVariationV1],
                 mappedAmendment: ActivityAmendmentLinkV1?,
                 mappedCurrentBasisReference:ActivityBasisHeadReferenceV2?,
                 mappedInstallationCloseout:InstallationCloseoutV1?,
                 mappedPunchReviewCloseout:PunchReviewCloseoutV1?) throws -> Self {
        try mappedVariations.forEach { try $0.validate() }
        guard mappedVariations.count == variations.count,
              mappedVariations.map(\.variationID) == variations.map(\.variationID),
              mappedVariations.map(\.revision) == variations.map(\.revision) else {
            throw ActivityContractFailureV2.invalidTransition
        }
        guard (mappedAmendment == nil) == (amendment == nil) else {
            throw ActivityContractFailureV2.missingReference
        }
        if let amendment, let mappedAmendment {
            guard mappedAmendment.predecessorActivityID == amendment.predecessorActivityID,
                  mappedAmendment.predecessorRevision == amendment.predecessorRevision,
                  mappedAmendment.reason == amendment.reason else {
                throw ActivityContractFailureV2.invalidTransition
            }
        }
        let mappedCompletedSnapshotReference = try completedSnapshotReference.map { reference in
            guard let targetCloseoutSHA256 = mappedInstallationCloseout?.closeoutSHA256
                    ?? mappedPunchReviewCloseout?.closeoutSHA256 else {
                throw ActivityContractFailureV2.missingReference
            }
            return try reference.rebound(
                to: workspaceID,
                activityID: activityID,
                targetCloseoutSHA256: targetCloseoutSHA256
            )
        }
        return try Self(activityID: activityID, workspaceID: workspaceID, kind: kind, state: state,
                        reviewState: reviewState, subjectID: subjectID, title: title, readiness: readiness,
                        readinessPolicy: readinessPolicy,
                        variations: mappedVariations, amendment: mappedAmendment,
                        currentBasisReference:mappedCurrentBasisReference,
                        installationCloseout:mappedInstallationCloseout,punchReviewCloseout:mappedPunchReviewCloseout,
                        completedSnapshotReference: mappedCompletedSnapshotReference,
                        startedAt: startedAt,
                        finalizedAt: finalizedAt, revision: revision, mutationID: mutationID,
                        predecessorEnvelopeSHA256: mappedPredecessorEnvelopeSHA256)
    }

    /// Source-compatible root rebind. It is intentionally limited to the
    /// first revision; later revisions must use the mapped-predecessor overload
    /// so a source-workspace digest cannot be silently reused.
    func rebound(to workspaceID: WorkspaceID, activityID: UUID, subjectID: UUID,
                 revision: UInt64, mutationID: MutationIDV1) throws -> Self {
        guard revision == 1 else { throw ActivityContractFailureV2.missingReference }
        return try rebound(to: workspaceID, activityID: activityID, subjectID: subjectID,
                           revision: revision, mutationID: mutationID,
                           mappedPredecessorEnvelopeSHA256: nil,
                           mappedVariations: try variations.map { try $0.rebound(to: workspaceID) },
                           mappedAmendment: amendment,
                           mappedCurrentBasisReference:nil,
                           mappedInstallationCloseout:nil,mappedPunchReviewCloseout:nil)
    }

    func canonicalData() throws -> Data { try validateForRead(); return try WorkspaceMutationCanonicalV1.data(self) }

    private static func reviewStateIsValid(_ review: ActivityReviewStateV2, for state: ActivityStateV2) -> Bool {
        switch state {
        case .readyForReview: return review == .pending
        case .changesRequested: return review == .changesRequested
        case .finalized, .superseded: return review == .acceptedRecordedFacts
        default: return review == .notRequested
        }
    }

    private static func completedSnapshotReferenceIsValid(
        _ reference: CompletedActivitySnapshotV2CompatibilityReferenceV1?,
        for state: ActivityStateV2
    ) -> Bool {
        switch state {
        case .finalized:
            return reference != nil
        case .superseded:
            return true
        default:
            return reference == nil
        }
    }

    private func validateReadinessPolicy() throws {
        let requiresAuthoritativePolicy = state == .ready || state == .inProgress
        switch kind {
        case .installation, .punchReview:
            if requiresAuthoritativePolicy {
                guard let readinessPolicy else { throw ActivityContractFailureV2.missingReference }
                try readinessPolicy.validate(readiness: readiness, kind: kind, state: state)
            } else if let readinessPolicy {
                guard readinessPolicy.activityKind == kind else {
                    throw ActivityContractFailureV2.invalidValue
                }
            }
        case .unknown:
            guard readinessPolicy == nil else { throw ActivityContractFailureV2.invalidValue }
        default:
            guard readinessPolicy == nil else { throw ActivityContractFailureV2.invalidValue }
            if requiresAuthoritativePolicy {
                guard readiness.allSatisfy({ $0.disposition != .blocked && $0.disposition != .deferred }) else {
                    throw ActivityContractFailureV2.invalidTransition
                }
            }
        }
    }

    private func validateFamilyPayload()throws{
        // A superseded activity only carries closeout truth when it is the
        // immutable successor of a finalized activity. Deferred/unable work
        // may be superseded honestly without fabricating completion evidence.
        let requiresCloseout = state == .finalized
            || (state == .superseded && completedSnapshotReference != nil)
        let allowsCloseout = requiresCloseout
            || state == .cancelled
            || state == .unableToComplete
        if !allowsCloseout {
            guard installationCloseout == nil, punchReviewCloseout == nil else {
                throw ActivityContractFailureV2.unsupportedClaim
            }
        }
        switch kind{
        case .installation:
            guard punchReviewCloseout==nil else{throw ActivityContractFailureV2.invalidValue}
            if let currentBasisReference{guard case .installation=currentBasisReference else{throw ActivityContractFailureV2.invalidValue}}
            if requiresCloseout{guard currentBasisReference != nil,installationCloseout != nil else{throw ActivityContractFailureV2.missingReference}}
        case .punchReview:
            guard installationCloseout==nil else{throw ActivityContractFailureV2.invalidValue}
            if let currentBasisReference{guard case .punchReview=currentBasisReference else{throw ActivityContractFailureV2.invalidValue}}
            if let punchReviewCloseout,let currentBasisReference{
                guard punchReviewCloseout.basisSHA256==currentBasisReference.basisSHA256 else{throw ActivityContractFailureV2.missingReference}
            }
            if requiresCloseout{guard currentBasisReference != nil,punchReviewCloseout != nil else{throw ActivityContractFailureV2.missingReference}}
        default:
            guard currentBasisReference==nil,installationCloseout==nil,punchReviewCloseout==nil else{throw ActivityContractFailureV2.invalidValue}
        }
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, activityID: activityID, workspaceID: workspaceID, kind: kind,
              state: state, reviewState: reviewState, subjectID: subjectID, title: title, readiness: readiness,
              readinessPolicy: readinessPolicy,
              variations: variations, amendment: amendment,currentBasisReference:currentBasisReference,
              installationCloseout:installationCloseout,punchReviewCloseout:punchReviewCloseout,
              completedSnapshotReference: completedSnapshotReference,
              startedAt: startedAt, finalizedAt: finalizedAt, revision: revision,
              mutationID: mutationID, predecessorEnvelopeSHA256: predecessorEnvelopeSHA256)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let activityID: UUID; let workspaceID: WorkspaceID; let kind: ActivityKindV2
        let state: ActivityStateV2; let reviewState: ActivityReviewStateV2; let subjectID: UUID; let title: String
        let readiness: [ActivityReadinessFacetV1]; let readinessPolicy: ActivityReadinessPolicyBindingV2?
        let variations: [ActivityVariationV1]
        let amendment: ActivityAmendmentLinkV1?
        let currentBasisReference:ActivityBasisHeadReferenceV2?
        let installationCloseout:InstallationCloseoutV1?;let punchReviewCloseout:PunchReviewCloseoutV1?
        let completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1?
        let startedAt: Date?; let finalizedAt: Date?; let revision: UInt64; let mutationID: MutationIDV1
        let predecessorEnvelopeSHA256: String?
    }
}

struct ActivityStateTransitionV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let transitionID: UUID
    let workspaceID: WorkspaceID
    let activityID: UUID
    let kind: ActivityKindV2
    let fromState: ActivityStateV2
    let toState: ActivityStateV2
    let reason: String?
    let actor: ActorSnapshotV1
    let occurredAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let transitionSHA256: String

    init(transitionID: UUID, workspaceID: WorkspaceID, activityID: UUID, kind: ActivityKindV2,
         fromState: ActivityStateV2, toState: ActivityStateV2, reason: String? = nil,
         actor: ActorSnapshotV1, occurredAt: Date, revision: UInt64, mutationID: MutationIDV1) throws {
        let basis = Basis(schemaVersion: Self.schemaVersion, transitionID: transitionID, workspaceID: workspaceID,
                          activityID: activityID, kind: kind, fromState: fromState, toState: toState,
                          reason: reason, actor: actor, occurredAt: occurredAt, revision: revision, mutationID: mutationID)
        schemaVersion = Self.schemaVersion; self.transitionID = transitionID; self.workspaceID = workspaceID
        self.activityID = activityID; self.kind = kind; self.fromState = fromState; self.toState = toState
        self.reason = reason; self.actor = actor; self.occurredAt = occurredAt; self.revision = revision
        self.mutationID = mutationID; transitionSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
        try validate()
    }

    func validate() throws {
        try kind.requireKnownForMutation()
        try actor.validate()
        let reasonRequired: Bool
        switch toState {
        case .deferred, .unableToComplete, .cancelled, .changesRequested, .superseded:
            reasonRequired = true
        default:
            reasonRequired = false
        }
        guard schemaVersion == Self.schemaVersion, transitionID != ActivityContractValidationV2.zeroUUID,
              activityID != ActivityContractValidationV2.zeroUUID, revision > 0,
              actor.workspaceID == workspaceID,
              ActivityStateMachineV2.permits(from: fromState, to: toState),
              reason.map({ ActivityContractValidationV2.text($0, maximumBytes: ActivityContractValidationV2.maximumReasonBytes) }) ?? true,
              !reasonRequired || reason != nil,
              transitionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw ActivityContractFailureV2.invalidTransition
        }
    }

    func rebound(to workspaceID: WorkspaceID, activityID: UUID, revision: UInt64,
                 mutationID: MutationIDV1) throws -> Self {
        try Self(transitionID: transitionID, workspaceID: workspaceID, activityID: activityID,
                 kind: kind, fromState: fromState, toState: toState, reason: reason,
                 actor: ActivityActorRebindingV2.rebound(actor, to: workspaceID),
                 occurredAt: occurredAt, revision: revision, mutationID: mutationID)
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, transitionID: transitionID, workspaceID: workspaceID,
        activityID: activityID, kind: kind, fromState: fromState, toState: toState, reason: reason,
        actor: actor, occurredAt: occurredAt, revision: revision, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion:Int; let transitionID:UUID; let workspaceID:WorkspaceID
        let activityID:UUID; let kind:ActivityKindV2; let fromState:ActivityStateV2; let toState:ActivityStateV2
        let reason:String?; let actor:ActorSnapshotV1; let occurredAt:Date; let revision:UInt64; let mutationID:MutationIDV1 }
}

// MARK: - Optional provider and no-plan truth

struct ActivityExternalReferenceV1: Codable, Equatable, Hashable, Sendable {
    let referenceID: String
    let revision: UInt64
    let sha256: String
    init(referenceID:String, revision:UInt64, sha256:String)throws{
        guard ActivityContractValidationV2.token(referenceID),revision>0,ActivityContractValidationV2.digest(sha256)
        else{throw ActivityContractFailureV2.invalidValue};self.referenceID=referenceID;self.revision=revision;self.sha256=sha256
    }

    func validate() throws {
        guard ActivityContractValidationV2.token(referenceID), revision > 0,
              ActivityContractValidationV2.digest(sha256) else {
            throw ActivityContractFailureV2.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case referenceID, revision, sha256
    }

    init(from decoder: Decoder) throws {
        try ActivityClosedCodingV2.requireExactKeys(
            decoder, Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            referenceID: values.decode(String.self, forKey: .referenceID),
            revision: values.decode(UInt64.self, forKey: .revision),
            sha256: values.decode(String.self, forKey: .sha256)
        )
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(referenceID, forKey: .referenceID)
        try values.encode(revision, forKey: .revision)
        try values.encode(sha256, forKey: .sha256)
    }
}

struct NoPlanFallbackV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let manualSubjectSelectionRequired: Bool
    let planRequired: Bool
    let scanRequired: Bool
    let limitation: String
    let fallbackSHA256: String

    init(limitation: String) throws {
        let basis = Basis(schemaVersion:Self.schemaVersion,manualSubjectSelectionRequired:true,
                          planRequired:false,scanRequired:false,limitation:limitation)
        schemaVersion=Self.schemaVersion;manualSubjectSelectionRequired=true;planRequired=false;scanRequired=false
        self.limitation=limitation;fallbackSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()
    }
    func validate()throws{guard schemaVersion==Self.schemaVersion,manualSubjectSelectionRequired,!planRequired,!scanRequired,
        ActivityContractValidationV2.text(limitation),fallbackSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))
        else{throw ActivityContractFailureV2.invalidValue}}

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, manualSubjectSelectionRequired, planRequired, scanRequired, limitation, fallbackSHA256
    }

    init(from decoder: Decoder) throws {
        try ActivityClosedCodingV2.requireExactKeys(
            decoder, Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        manualSubjectSelectionRequired = try values.decode(Bool.self, forKey: .manualSubjectSelectionRequired)
        planRequired = try values.decode(Bool.self, forKey: .planRequired)
        scanRequired = try values.decode(Bool.self, forKey: .scanRequired)
        limitation = try values.decode(String.self, forKey: .limitation)
        fallbackSHA256 = try values.decode(String.self, forKey: .fallbackSHA256)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(manualSubjectSelectionRequired, forKey: .manualSubjectSelectionRequired)
        try values.encode(planRequired, forKey: .planRequired)
        try values.encode(scanRequired, forKey: .scanRequired)
        try values.encode(limitation, forKey: .limitation)
        try values.encode(fallbackSHA256, forKey: .fallbackSHA256)
    }

    private var basis:Basis{.init(schemaVersion:schemaVersion,manualSubjectSelectionRequired:manualSubjectSelectionRequired,
        planRequired:planRequired,scanRequired:scanRequired,limitation:limitation)}
    private struct Basis:Codable{let schemaVersion:Int;let manualSubjectSelectionRequired:Bool;let planRequired:Bool
        let scanRequired:Bool;let limitation:String}
}

enum ActivityBasisSourceV1: Codable, Equatable, Hashable, Sendable {
    case noPlan(NoPlanFallbackV1)
    case optionalPlan(ActivityExternalReferenceV1)
    case externalLocal(ActivityExternalReferenceV1)

    func validate() throws {
        switch self {
        case let .noPlan(value): try value.validate()
        case let .optionalPlan(value), let .externalLocal(value): try value.validate()
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noPlan, optionalPlan, externalLocal
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: ActivityDynamicCodingKeyV2.self)
        let rawKeys = dynamic.allKeys.map(\.stringValue)
        guard rawKeys.count == 1, let rawKey = rawKeys.first,
              let key = CodingKeys(rawValue: rawKey) else {
            throw ActivityContractFailureV2.invalidValue
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch key {
        case .noPlan:
            self = .noPlan(try values.decode(NoPlanFallbackV1.self, forKey: .noPlan))
        case .optionalPlan:
            self = .optionalPlan(try values.decode(ActivityExternalReferenceV1.self, forKey: .optionalPlan))
        case .externalLocal:
            self = .externalLocal(try values.decode(ActivityExternalReferenceV1.self, forKey: .externalLocal))
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .noPlan(value): try values.encode(value, forKey: .noPlan)
        case let .optionalPlan(value): try values.encode(value, forKey: .optionalPlan)
        case let .externalLocal(value): try values.encode(value, forKey: .externalLocal)
        }
    }
}

// MARK: - Installation family

enum InstallationTaskOutcomeV1:String,Codable,CaseIterable,Hashable,Sendable{
    case notStarted="NOT_STARTED",inProgress="IN_PROGRESS",completed="COMPLETED",notApplicable="NOT_APPLICABLE"
    case deferred="DEFERRED",unable="UNABLE"
}
enum InstallationDeferredReasonV1:String,Codable,CaseIterable,Hashable,Sendable{
    case accessUnavailable="ACCESS_UNAVAILABLE",siteNotReady="SITE_NOT_READY",materialUnavailable="MATERIAL_UNAVAILABLE"
    case weather="WEATHER",equipmentUnavailable="EQUIPMENT_UNAVAILABLE",awaitingRecordedDecision="AWAITING_RECORDED_DECISION",otherRecorded="OTHER_RECORDED"
}
enum InstallationUnableReasonV1:String,Codable,CaseIterable,Hashable,Sendable{
    case unsafeRecordedCondition="UNSAFE_RECORDED_CONDITION",subjectMismatch="SUBJECT_MISMATCH"
    case unsupportedInstruction="UNSUPPORTED_INSTRUCTION",irrecoverableAccess="IRRECOVERABLE_ACCESS",otherRecorded="OTHER_RECORDED"
}
enum InstallationCompletionDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{
    case completedAsRecorded="COMPLETED_AS_RECORDED",completedWithOpenItems="COMPLETED_WITH_OPEN_ITEMS"
    case partiallyCompleted="PARTIALLY_COMPLETED",unableAttemptRecorded="UNABLE_ATTEMPT_RECORDED",cancelled="CANCELLED"
}
enum InstallationEvidencePurposeV1:String,Codable,CaseIterable,Hashable,Sendable{
    case preInstallContext="PRE_INSTALL_CONTEXT",subjectIdentity="SUBJECT_IDENTITY",placementContext="PLACEMENT_CONTEXT"
    case taskExecution="TASK_EXECUTION",asBuiltOverview="AS_BUILT_OVERVIEW",asBuiltDetail="AS_BUILT_DETAIL"
    case openException="OPEN_EXCEPTION",completionContext="COMPLETION_CONTEXT",measurementContext="MEASUREMENT_CONTEXT"
}

struct InstallationTaskDefinitionV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let taskID:String;let ordinal:Int;let title:String;let evidencePurposes:[InstallationEvidencePurposeV1]
    static func <(lhs:Self,rhs:Self)->Bool{lhs.ordinal != rhs.ordinal ? lhs.ordinal < rhs.ordinal : lhs.taskID < rhs.taskID}
    init(taskID:String,ordinal:Int,title:String,evidencePurposes:[InstallationEvidencePurposeV1])throws{
        let purposes=evidencePurposes.sorted{$0.rawValue<$1.rawValue};guard ActivityContractValidationV2.token(taskID),ordinal>=0,
            ActivityContractValidationV2.text(title),!purposes.isEmpty,Set(purposes).count==purposes.count else{throw ActivityContractFailureV2.invalidValue}
        self.taskID=taskID;self.ordinal=ordinal;self.title=title;self.evidencePurposes=purposes
    }
}
struct InstallationReadinessPolicyV1:Codable,Equatable,Sendable{
    let requiredFacets:[ActivityReadinessFacetKindV1]
    init(requiredFacets:[ActivityReadinessFacetKindV1])throws{let values=requiredFacets.sorted{$0.rawValue<$1.rawValue}
        self.requiredFacets=values;try validate()}
    func validate()throws{guard !requiredFacets.isEmpty,
        requiredFacets==requiredFacets.sorted(by:{$0.rawValue<$1.rawValue}),Set(requiredFacets).count==requiredFacets.count
        else{throw ActivityContractFailureV2.invalidValue}}
    private enum CodingKeys:String,CodingKey,CaseIterable{case requiredFacets}
    init(from decoder:Decoder)throws{try ActivityClosedCodingV2.requireExactKeys(decoder,Set(CodingKeys.allCases.map(\.rawValue)))
        let values=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(requiredFacets:values.decode([ActivityReadinessFacetKindV1].self,forKey:.requiredFacets))}
    func encode(to encoder:Encoder)throws{try validate();var values=encoder.container(keyedBy:CodingKeys.self)
        try values.encode(requiredFacets,forKey:.requiredFacets)}
}
enum ActivityBundledWorkflowReleaseV1:String,Codable,CaseIterable,Hashable,Sendable{
    case installationV1="BUNDLED_INSTALLATION_V1"
    case punchReviewV1="BUNDLED_PUNCH_REVIEW_V1"
}
enum ActivityWorkflowFamilyAvailabilityDispositionV2:String,Codable,CaseIterable,Hashable,Sendable{
    case availableForStart="AVAILABLE_FOR_START";case historicReadExportOnly="HISTORIC_READ_EXPORT_ONLY"
}
struct ActivityWorkflowFamilyAvailabilityV2:Codable,Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let bundledRelease:ActivityBundledWorkflowReleaseV1
    let workflowReleaseReferenceSHA256:String;let disposition:ActivityWorkflowFamilyAvailabilityDispositionV2
    init(reference:ActivityWorkflowReleaseReferenceV2,
         disposition:ActivityWorkflowFamilyAvailabilityDispositionV2)throws{
        try reference.validate();workspaceID=reference.targetWorkspaceID;bundledRelease=reference.bundledRelease
        workflowReleaseReferenceSHA256=reference.referenceSHA256;self.disposition=disposition
    }
    func validate(reference:ActivityWorkflowReleaseReferenceV2,forStart:Bool)throws{
        try reference.validate();guard workspaceID==reference.targetWorkspaceID,
            bundledRelease==reference.bundledRelease,workflowReleaseReferenceSHA256==reference.referenceSHA256,
            !forStart || disposition == .availableForStart else{throw ActivityContractFailureV2.missingReference}
    }
}

/// Canonical bridge from an activity basis to the sole package registry and
/// one of the two bundled workflow releases. Source release identity remains
/// immutable across clone/fork; target identity is explicitly revalidated
/// against a semantically identical destination release.
struct ActivityWorkflowReleaseReferenceV2:Codable,Equatable,Hashable,Sendable{
    let bundledRelease:ActivityBundledWorkflowReleaseV1
    let sourceWorkspaceID:WorkspaceID;let sourceReleaseID:UUID;let sourceReleaseRevision:UInt64
    let sourceReleaseSHA256:String
    let targetWorkspaceID:WorkspaceID;let targetReleaseID:UUID;let targetReleaseRevision:UInt64
    let targetReleaseSHA256:String
    let packageID:String;let packageContentVersion:Int;let packageSHA256:String
    let releaseCompatibilitySHA256:String;let referenceSHA256:String

    init(installation release:InstallationWorkflowDefinitionReleaseV1,
         package:InspectionPackageV2)throws{
        try release.validate();let packageFacts=try Self.packageFacts(package)
        let compatibility=try Self.installationCompatibility(release)
        try self.init(bundledRelease:.installationV1,
            sourceWorkspaceID:release.workspaceID,sourceReleaseID:release.releaseID,
            sourceReleaseRevision:release.revision,sourceReleaseSHA256:release.releaseSHA256,
            targetWorkspaceID:release.workspaceID,targetReleaseID:release.releaseID,
            targetReleaseRevision:release.revision,targetReleaseSHA256:release.releaseSHA256,
            packageID:packageFacts.id,packageContentVersion:packageFacts.version,
            packageSHA256:packageFacts.sha256,releaseCompatibilitySHA256:compatibility)
        try validateTarget(installation:release,package:package)
    }

    init(punchReview release:PunchReviewWorkflowDefinitionReleaseV1,
         package:InspectionPackageV2)throws{
        try release.validate();let packageFacts=try Self.packageFacts(package)
        let compatibility=try Self.punchCompatibility(release)
        try self.init(bundledRelease:.punchReviewV1,
            sourceWorkspaceID:release.workspaceID,sourceReleaseID:release.releaseID,
            sourceReleaseRevision:release.revision,sourceReleaseSHA256:release.releaseSHA256,
            targetWorkspaceID:release.workspaceID,targetReleaseID:release.releaseID,
            targetReleaseRevision:release.revision,targetReleaseSHA256:release.releaseSHA256,
            packageID:packageFacts.id,packageContentVersion:packageFacts.version,
            packageSHA256:packageFacts.sha256,releaseCompatibilitySHA256:compatibility)
        try validateTarget(punchReview:release,package:package)
    }

    func rebound(to workspaceID:WorkspaceID,
                 installation release:InstallationWorkflowDefinitionReleaseV1,
                 package:InspectionPackageV2)throws->Self{
        try validate();guard bundledRelease == .installationV1,release.workspaceID==workspaceID,
            try Self.installationCompatibility(release)==releaseCompatibilitySHA256
        else{throw ActivityContractFailureV2.missingReference}
        let packageFacts=try Self.packageFacts(package)
        guard packageFacts.id==packageID,packageFacts.version==packageContentVersion,
            packageFacts.sha256==packageSHA256 else{throw ActivityContractFailureV2.missingReference}
        let value=try Self(bundledRelease:bundledRelease,
            sourceWorkspaceID:sourceWorkspaceID,sourceReleaseID:sourceReleaseID,
            sourceReleaseRevision:sourceReleaseRevision,sourceReleaseSHA256:sourceReleaseSHA256,
            targetWorkspaceID:workspaceID,targetReleaseID:release.releaseID,
            targetReleaseRevision:release.revision,targetReleaseSHA256:release.releaseSHA256,
            packageID:packageID,packageContentVersion:packageContentVersion,packageSHA256:packageSHA256,
            releaseCompatibilitySHA256:releaseCompatibilitySHA256)
        try value.validateTarget(installation:release,package:package);return value
    }

    func rebound(to workspaceID:WorkspaceID,
                 punchReview release:PunchReviewWorkflowDefinitionReleaseV1,
                 package:InspectionPackageV2)throws->Self{
        try validate();guard bundledRelease == .punchReviewV1,release.workspaceID==workspaceID,
            try Self.punchCompatibility(release)==releaseCompatibilitySHA256
        else{throw ActivityContractFailureV2.missingReference}
        let packageFacts=try Self.packageFacts(package)
        guard packageFacts.id==packageID,packageFacts.version==packageContentVersion,
            packageFacts.sha256==packageSHA256 else{throw ActivityContractFailureV2.missingReference}
        let value=try Self(bundledRelease:bundledRelease,
            sourceWorkspaceID:sourceWorkspaceID,sourceReleaseID:sourceReleaseID,
            sourceReleaseRevision:sourceReleaseRevision,sourceReleaseSHA256:sourceReleaseSHA256,
            targetWorkspaceID:workspaceID,targetReleaseID:release.releaseID,
            targetReleaseRevision:release.revision,targetReleaseSHA256:release.releaseSHA256,
            packageID:packageID,packageContentVersion:packageContentVersion,packageSHA256:packageSHA256,
            releaseCompatibilitySHA256:releaseCompatibilitySHA256)
        try value.validateTarget(punchReview:release,package:package);return value
    }

    func validate()throws{
        guard sourceWorkspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
            targetWorkspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
            sourceReleaseID != ActivityContractValidationV2.zeroUUID,
            targetReleaseID != ActivityContractValidationV2.zeroUUID,
            sourceReleaseRevision>0,targetReleaseRevision>0,
            ActivityContractValidationV2.token(packageID),packageContentVersion>0,
            [sourceReleaseSHA256,targetReleaseSHA256,packageSHA256,releaseCompatibilitySHA256]
                .allSatisfy(ActivityContractValidationV2.digest),
            referenceSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))
        else{throw ActivityContractFailureV2.missingReference}
    }

    func validateSource(installation release:InstallationWorkflowDefinitionReleaseV1,
                        package:InspectionPackageV2)throws{
        try validate();try release.validate();let facts=try Self.packageFacts(package)
        guard bundledRelease == .installationV1,release.workspaceID==sourceWorkspaceID,
            release.releaseID==sourceReleaseID,release.revision==sourceReleaseRevision,
            release.releaseSHA256==sourceReleaseSHA256,
            try Self.installationCompatibility(release)==releaseCompatibilitySHA256,
            facts.id==packageID,facts.version==packageContentVersion,facts.sha256==packageSHA256
        else{throw ActivityContractFailureV2.missingReference}
    }

    func validateTarget(installation release:InstallationWorkflowDefinitionReleaseV1,
                        package:InspectionPackageV2)throws{
        try validate();try release.validate();let facts=try Self.packageFacts(package)
        guard bundledRelease == .installationV1,release.workspaceID==targetWorkspaceID,
            release.releaseID==targetReleaseID,release.revision==targetReleaseRevision,
            release.releaseSHA256==targetReleaseSHA256,
            try Self.installationCompatibility(release)==releaseCompatibilitySHA256,
            facts.id==packageID,facts.version==packageContentVersion,facts.sha256==packageSHA256
        else{throw ActivityContractFailureV2.missingReference}
    }

    func validateSource(punchReview release:PunchReviewWorkflowDefinitionReleaseV1,
                        package:InspectionPackageV2)throws{
        try validate();try release.validate();let facts=try Self.packageFacts(package)
        guard bundledRelease == .punchReviewV1,release.workspaceID==sourceWorkspaceID,
            release.releaseID==sourceReleaseID,release.revision==sourceReleaseRevision,
            release.releaseSHA256==sourceReleaseSHA256,
            try Self.punchCompatibility(release)==releaseCompatibilitySHA256,
            facts.id==packageID,facts.version==packageContentVersion,facts.sha256==packageSHA256
        else{throw ActivityContractFailureV2.missingReference}
    }

    func validateTarget(punchReview release:PunchReviewWorkflowDefinitionReleaseV1,
                        package:InspectionPackageV2)throws{
        try validate();try release.validate();let facts=try Self.packageFacts(package)
        guard bundledRelease == .punchReviewV1,release.workspaceID==targetWorkspaceID,
            release.releaseID==targetReleaseID,release.revision==targetReleaseRevision,
            release.releaseSHA256==targetReleaseSHA256,
            try Self.punchCompatibility(release)==releaseCompatibilitySHA256,
            facts.id==packageID,facts.version==packageContentVersion,facts.sha256==packageSHA256
        else{throw ActivityContractFailureV2.missingReference}
    }

    private init(bundledRelease:ActivityBundledWorkflowReleaseV1,
                 sourceWorkspaceID:WorkspaceID,sourceReleaseID:UUID,sourceReleaseRevision:UInt64,
                 sourceReleaseSHA256:String,targetWorkspaceID:WorkspaceID,targetReleaseID:UUID,
                 targetReleaseRevision:UInt64,targetReleaseSHA256:String,packageID:String,
                 packageContentVersion:Int,packageSHA256:String,releaseCompatibilitySHA256:String)throws{
        let basis=Basis(bundledRelease:bundledRelease,sourceWorkspaceID:sourceWorkspaceID,
            sourceReleaseID:sourceReleaseID,sourceReleaseRevision:sourceReleaseRevision,
            sourceReleaseSHA256:sourceReleaseSHA256,targetWorkspaceID:targetWorkspaceID,
            targetReleaseID:targetReleaseID,targetReleaseRevision:targetReleaseRevision,
            targetReleaseSHA256:targetReleaseSHA256,packageID:packageID,
            packageContentVersion:packageContentVersion,packageSHA256:packageSHA256,
            releaseCompatibilitySHA256:releaseCompatibilitySHA256)
        self.bundledRelease=bundledRelease;self.sourceWorkspaceID=sourceWorkspaceID
        self.sourceReleaseID=sourceReleaseID;self.sourceReleaseRevision=sourceReleaseRevision
        self.sourceReleaseSHA256=sourceReleaseSHA256;self.targetWorkspaceID=targetWorkspaceID
        self.targetReleaseID=targetReleaseID;self.targetReleaseRevision=targetReleaseRevision
        self.targetReleaseSHA256=targetReleaseSHA256;self.packageID=packageID
        self.packageContentVersion=packageContentVersion;self.packageSHA256=packageSHA256
        self.releaseCompatibilitySHA256=releaseCompatibilitySHA256
        referenceSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()
    }

    private static func packageFacts(_ package:InspectionPackageV2)throws->(id:String,version:Int,sha256:String){
        try InspectionPackageCompatibilityValidatorV2.validate(package)
        let bytes=try InspectionPackageCanonicalCodecV2.encode(package)
        return(package.packageID,package.contentVersion,KernelCanonicalHashV1.sha256(bytes))
    }
    private static func installationCompatibility(_ release:InstallationWorkflowDefinitionReleaseV1)throws->String{
        try release.validate();return try WorkspaceMutationCanonicalV1.sha256(
            InstallationCompatibilityBasis(bundledRelease:release.bundledRelease,tasks:release.tasks,
                                           readinessPolicy:release.readinessPolicy))
    }
    private static func punchCompatibility(_ release:PunchReviewWorkflowDefinitionReleaseV1)throws->String{
        try release.validate();return try WorkspaceMutationCanonicalV1.sha256(
            PunchCompatibilityBasis(bundledRelease:release.bundledRelease,scope:release.scope,
                                    readinessPolicy:release.readinessPolicy))
    }
    private var basis:Basis{.init(bundledRelease:bundledRelease,sourceWorkspaceID:sourceWorkspaceID,
        sourceReleaseID:sourceReleaseID,sourceReleaseRevision:sourceReleaseRevision,
        sourceReleaseSHA256:sourceReleaseSHA256,targetWorkspaceID:targetWorkspaceID,targetReleaseID:targetReleaseID,
        targetReleaseRevision:targetReleaseRevision,targetReleaseSHA256:targetReleaseSHA256,packageID:packageID,
        packageContentVersion:packageContentVersion,packageSHA256:packageSHA256,
        releaseCompatibilitySHA256:releaseCompatibilitySHA256)}
    private struct Basis:Codable{let bundledRelease:ActivityBundledWorkflowReleaseV1;let sourceWorkspaceID:WorkspaceID
        let sourceReleaseID:UUID;let sourceReleaseRevision:UInt64;let sourceReleaseSHA256:String
        let targetWorkspaceID:WorkspaceID;let targetReleaseID:UUID;let targetReleaseRevision:UInt64;let targetReleaseSHA256:String
        let packageID:String;let packageContentVersion:Int;let packageSHA256:String;let releaseCompatibilitySHA256:String}
    private struct InstallationCompatibilityBasis:Codable{let bundledRelease:ActivityBundledWorkflowReleaseV1
        let tasks:[InstallationTaskDefinitionV1];let readinessPolicy:InstallationReadinessPolicyV1}
    private struct PunchCompatibilityBasis:Codable{let bundledRelease:ActivityBundledWorkflowReleaseV1
        let scope:[PunchReviewScopeItemV1];let readinessPolicy:PunchReviewReadinessPolicyV1}
}

/// Runtime-only proof from the sole package/workflow release authority. The
/// canonical reference keeps source provenance, while this context proves
/// that the exact target release is currently available for the requested
/// operation. It is deliberately not another release registry or row.
enum ActivityWorkflowReleaseResolutionContextV2:Sendable{
    case installation(reference:ActivityWorkflowReleaseReferenceV2,
                      release:InstallationWorkflowDefinitionReleaseV1,
                      package:InspectionPackageV2,
                      availability:ActivityWorkflowFamilyAvailabilityV2)
    case punchReview(reference:ActivityWorkflowReleaseReferenceV2,
                    release:PunchReviewWorkflowDefinitionReleaseV1,
                    package:InspectionPackageV2,
                    availability:ActivityWorkflowFamilyAvailabilityV2)

    var reference:ActivityWorkflowReleaseReferenceV2{switch self{
        case let .installation(reference,_,_,_):return reference
        case let .punchReview(reference,_,_,_):return reference}}
    var readinessPolicy:ActivityReadinessPolicyBindingV2{switch self{
        case let .installation(_,release,_,_):return .installation(release.readinessPolicy)
        case let .punchReview(_,release,_,_):return .punchReview(release.readinessPolicy)}}
    var installationTaskIDs:Set<String>?{switch self{
        case let .installation(_,release,_,_):return Set(release.tasks.map(\.taskID))
        case .punchReview:return nil}}

    init(reference:ActivityWorkflowReleaseReferenceV2,
         installation release:InstallationWorkflowDefinitionReleaseV1,
         package:InspectionPackageV2,
         availability:ActivityWorkflowFamilyAvailabilityV2)throws{
        try reference.validateTarget(installation:release,package:package)
        try availability.validate(reference:reference,forStart:false)
        self = .installation(reference:reference,release:release,package:package,availability:availability)
    }
    init(reference:ActivityWorkflowReleaseReferenceV2,
         punchReview release:PunchReviewWorkflowDefinitionReleaseV1,
         package:InspectionPackageV2,
         availability:ActivityWorkflowFamilyAvailabilityV2)throws{
        try reference.validateTarget(punchReview:release,package:package)
        try availability.validate(reference:reference,forStart:false)
        self = .punchReview(reference:reference,release:release,package:package,availability:availability)
    }
    func validate(expectedReference:ActivityWorkflowReleaseReferenceV2,
                  forStart:Bool)throws{
        guard reference==expectedReference else{throw ActivityContractFailureV2.missingReference}
        switch self{
        case let .installation(reference,release,package,availability):
            try reference.validateTarget(installation:release,package:package)
            try availability.validate(reference:reference,forStart:forStart)
        case let .punchReview(reference,release,package,availability):
            try reference.validateTarget(punchReview:release,package:package)
            try availability.validate(reference:reference,forStart:forStart)
        }
    }
}
struct InstallationWorkflowDefinitionReleaseV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let tasks:[InstallationTaskDefinitionV1]
    let bundledRelease:ActivityBundledWorkflowReleaseV1;let readinessPolicy:InstallationReadinessPolicyV1
    let revision:UInt64;let mutationID:MutationIDV1;let releaseSHA256:String
    init(releaseID:UUID,workspaceID:WorkspaceID,tasks:[InstallationTaskDefinitionV1],readinessPolicy:InstallationReadinessPolicyV1,
         revision:UInt64,mutationID:MutationIDV1)throws{let ordered=tasks.sorted();let basis=Basis(schemaVersion:Self.schemaVersion,
            releaseID:releaseID,workspaceID:workspaceID,tasks:ordered,bundledRelease:.installationV1,
            readinessPolicy:readinessPolicy,revision:revision,mutationID:mutationID)
        schemaVersion=Self.schemaVersion;self.releaseID=releaseID;self.workspaceID=workspaceID;self.tasks=ordered
        bundledRelease = .installationV1;self.readinessPolicy=readinessPolicy;self.revision=revision;self.mutationID=mutationID
        releaseSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{try readinessPolicy.validate();try tasks.forEach{task in
        guard ActivityContractValidationV2.token(task.taskID),task.ordinal>=0,
              ActivityContractValidationV2.text(task.title),!task.evidencePurposes.isEmpty,
              Set(task.evidencePurposes).count==task.evidencePurposes.count else{throw ActivityContractFailureV2.invalidValue}}
        guard schemaVersion==Self.schemaVersion,releaseID != ActivityContractValidationV2.zeroUUID,revision>0,
        bundledRelease == .installationV1,
        !tasks.isEmpty,tasks.count<=ActivityContractValidationV2.maximumTasks,ActivityContractValidationV2.sortedUnique(tasks.map(\.taskID)),
        releaseSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,releaseID:releaseID,workspaceID:workspaceID,tasks:tasks,
        bundledRelease:bundledRelease,readinessPolicy:readinessPolicy,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let tasks:[InstallationTaskDefinitionV1]
        let bundledRelease:ActivityBundledWorkflowReleaseV1;let readinessPolicy:InstallationReadinessPolicyV1
        let revision:UInt64;let mutationID:MutationIDV1}
}
struct InstallationBasisSnapshotV1:Codable,Equatable,Sendable{
    let basisID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let subjectID:UUID
    let workflowReleaseReference:ActivityWorkflowReleaseReferenceV2
    var workflowReleaseSHA256:String{workflowReleaseReference.targetReleaseSHA256}
    let source:ActivityBasisSourceV1;let capturedAt:Date;let revision:UInt64;let mutationID:MutationIDV1
    let predecessorBasisID:UUID?;let predecessorBasisSHA256:String?;let basisSHA256:String
    init(basisID:UUID,workspaceID:WorkspaceID,activityID:UUID,subjectID:UUID,
         workflowReleaseReference:ActivityWorkflowReleaseReferenceV2,source:ActivityBasisSourceV1,
         capturedAt:Date,revision:UInt64,mutationID:MutationIDV1,
         predecessorBasisID:UUID?=nil,predecessorBasisSHA256:String?=nil)throws{
        let basis=Basis(basisID:basisID,workspaceID:workspaceID,activityID:activityID,subjectID:subjectID,
            workflowReleaseReference:workflowReleaseReference,source:source,capturedAt:capturedAt,revision:revision,
            mutationID:mutationID,predecessorBasisID:predecessorBasisID,predecessorBasisSHA256:predecessorBasisSHA256)
        self.basisID=basisID;self.workspaceID=workspaceID;self.activityID=activityID;self.subjectID=subjectID
        self.workflowReleaseReference=workflowReleaseReference;self.source=source;self.capturedAt=capturedAt
        self.revision=revision;self.mutationID=mutationID;self.predecessorBasisID=predecessorBasisID
        self.predecessorBasisSHA256=predecessorBasisSHA256
        basisSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{try workflowReleaseReference.validate();try source.validate();guard basisID != ActivityContractValidationV2.zeroUUID,
        activityID != ActivityContractValidationV2.zeroUUID,subjectID != ActivityContractValidationV2.zeroUUID,
        workflowReleaseReference.bundledRelease == .installationV1,
        workflowReleaseReference.targetWorkspaceID == workspaceID,revision>0,
        (revision==1 && predecessorBasisID==nil && predecessorBasisSHA256==nil)
            || (revision>1 && predecessorBasisID != nil && predecessorBasisSHA256.map(ActivityContractValidationV2.digest)==true),
        basisSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidValue}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validate();try validate()
        let(next,overflow)=predecessor.revision.addingReportingOverflow(1)
        guard !overflow,workspaceID==predecessor.workspaceID,activityID==predecessor.activityID,
            subjectID==predecessor.subjectID,revision==next,basisID != predecessor.basisID,
            predecessorBasisID==predecessor.basisID,predecessorBasisSHA256==predecessor.basisSHA256
        else{throw ActivityContractFailureV2.staleRevision}}
    func rebound(to workspaceID:WorkspaceID,activityID:UUID,subjectID:UUID,
                 workflowReleaseReference:ActivityWorkflowReleaseReferenceV2,revision:UInt64,
                 mutationID:MutationIDV1,mappedPredecessorBasisID:UUID?,
                 mappedPredecessorBasisSHA256:String?)throws->Self{
        try Self(basisID:basisID,workspaceID:workspaceID,activityID:activityID,subjectID:subjectID,
            workflowReleaseReference:workflowReleaseReference,source:source,capturedAt:capturedAt,revision:revision,
            mutationID:mutationID,predecessorBasisID:mappedPredecessorBasisID,
            predecessorBasisSHA256:mappedPredecessorBasisSHA256)}
    private var basis:Basis{.init(basisID:basisID,workspaceID:workspaceID,activityID:activityID,subjectID:subjectID,
        workflowReleaseReference:workflowReleaseReference,source:source,capturedAt:capturedAt,revision:revision,
        mutationID:mutationID,predecessorBasisID:predecessorBasisID,predecessorBasisSHA256:predecessorBasisSHA256)}
    private struct Basis:Codable{let basisID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let subjectID:UUID
        let workflowReleaseReference:ActivityWorkflowReleaseReferenceV2;let source:ActivityBasisSourceV1;let capturedAt:Date
        let revision:UInt64;let mutationID:MutationIDV1;let predecessorBasisID:UUID?;let predecessorBasisSHA256:String?}
}

struct InstallationBasisReferenceV1:Codable,Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let activityID:UUID;let basisID:UUID;let revision:UInt64;let basisSHA256:String
    init(_ basis:InstallationBasisSnapshotV1)throws{try basis.validate();workspaceID=basis.workspaceID
        activityID=basis.activityID;basisID=basis.basisID;revision=basis.revision;basisSHA256=basis.basisSHA256
        try validate(basis)}
    func validate()throws{guard workspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
        activityID != ActivityContractValidationV2.zeroUUID,basisID != ActivityContractValidationV2.zeroUUID,revision>0,
        ActivityContractValidationV2.digest(basisSHA256)else{throw ActivityContractFailureV2.missingReference}}
    func validate(_ basis:InstallationBasisSnapshotV1)throws{try validate();try basis.validate()
        guard basis.workspaceID==workspaceID,basis.activityID==activityID,basis.basisID==basisID,
            basis.revision==revision,basis.basisSHA256==basisSHA256 else{throw ActivityContractFailureV2.missingReference}}
}

enum InstallationPlacementReferenceV2:Codable,Equatable,Hashable,Sendable{
    case plan(PlanPlacementReferenceV1)
    case pose(AssetPoseEventReferenceV1)
    var stableKey:String{switch self{
        case let .plan(v):return "PLAN|\(v.placementID.uuidString)|\(v.revision)|\(v.placementSHA256)"
        case let .pose(v):return "POSE|\(v.eventID.uuidString)|\(v.revision)|\(v.eventSHA256)"}}
    func validate(workspaceID:WorkspaceID)throws{switch self{
        case let .plan(v):try v.validate()
        case let .pose(v):try v.validate();guard v.workspaceID==workspaceID else{throw ActivityContractFailureV2.wrongWorkspace}}
    }
}

struct InstallationTaskResultV1:Codable,Equatable,Comparable,Sendable{
    let resultID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let taskID:String;let outcome:InstallationTaskOutcomeV1
    let deferredReason:InstallationDeferredReasonV1?;let unableReason:InstallationUnableReasonV1?;let note:String?
    let evidenceReferences:[ContentReferenceV1]
    var evidenceReferenceSHA256s:[String]{evidenceReferences.compactMap{$0.digests.digest(for:.sha256)?.hexadecimalValue}}
    let revision:UInt64;let mutationID:MutationIDV1
    let predecessorResultID:UUID?;let predecessorResultSHA256:String?;let resultSHA256:String
    static func <(lhs:Self,rhs:Self)->Bool{lhs.taskID != rhs.taskID ? lhs.taskID<rhs.taskID : lhs.revision<rhs.revision}
    init(resultID:UUID,workspaceID:WorkspaceID,activityID:UUID,taskID:String,outcome:InstallationTaskOutcomeV1,
         deferredReason:InstallationDeferredReasonV1?=nil,unableReason:InstallationUnableReasonV1?=nil,note:String?=nil,
         evidenceReferences:[ContentReferenceV1]=[],revision:UInt64,mutationID:MutationIDV1,
         predecessorResultID:UUID?=nil,predecessorResultSHA256:String?=nil)throws{
        let refs=evidenceReferences.sorted{$0.contentID<$1.contentID};let basis=Basis(resultID:resultID,workspaceID:workspaceID,activityID:activityID,
            taskID:taskID,outcome:outcome,deferredReason:deferredReason,unableReason:unableReason,note:note,
            evidenceReferences:refs,revision:revision,mutationID:mutationID,
            predecessorResultID:predecessorResultID,predecessorResultSHA256:predecessorResultSHA256)
        self.resultID=resultID;self.workspaceID=workspaceID;self.activityID=activityID;self.taskID=taskID;self.outcome=outcome
        self.deferredReason=deferredReason;self.unableReason=unableReason;self.note=note;self.evidenceReferences=refs
        self.revision=revision;self.mutationID=mutationID;self.predecessorResultID=predecessorResultID
        self.predecessorResultSHA256=predecessorResultSHA256
        resultSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{guard resultID != ActivityContractValidationV2.zeroUUID,activityID != ActivityContractValidationV2.zeroUUID,
        revision>0,ActivityContractValidationV2.token(taskID),
        (revision==1 && predecessorResultID==nil && predecessorResultSHA256==nil)
            || (revision>1 && predecessorResultID != nil && predecessorResultSHA256.map(ActivityContractValidationV2.digest)==true),
        (outcome == .deferred)==(deferredReason != nil),(outcome == .unable)==(unableReason != nil),
        !(deferredReason != nil && unableReason != nil),note.map({ ActivityContractValidationV2.text($0) }) ?? true,
        evidenceReferences.count<=ActivityContractValidationV2.maximumReferences,
        evidenceReferences==evidenceReferences.sorted(by:{$0.contentID<$1.contentID}),
        Set(evidenceReferences.map(\.contentID)).count==evidenceReferences.count,
        evidenceReferences.allSatisfy{$0.workspaceID.lowercased()==workspaceID.rawValue.uuidString.lowercased()
            && $0.digests.digest(for:.sha256) != nil},
        resultSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidValue}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validate();try validate()
        let(next,overflow)=predecessor.revision.addingReportingOverflow(1)
        guard !overflow,workspaceID==predecessor.workspaceID,activityID==predecessor.activityID,taskID==predecessor.taskID,
            revision==next,resultID != predecessor.resultID,predecessorResultID==predecessor.resultID,
            predecessorResultSHA256==predecessor.resultSHA256 else{throw ActivityContractFailureV2.staleRevision}}
    func rebound(to workspaceID:WorkspaceID,activityID:UUID,revision:UInt64,mutationID:MutationIDV1,
                 mappedPredecessorResultID:UUID?,mappedPredecessorResultSHA256:String?)throws->Self{
        let targetWorkspace = workspaceID.rawValue.uuidString.lowercased()
        let reboundEvidence = try evidenceReferences.map {
            try ContentReferenceV1(
                workspaceID: targetWorkspace,
                contentID: $0.contentID,
                byteLength: $0.byteLength,
                mediaType: $0.mediaType,
                digests: $0.digests,
                byteRole: $0.byteRole,
                createdAt: $0.createdAt
            )
        }
        try Self(resultID:resultID,workspaceID:workspaceID,activityID:activityID,taskID:taskID,outcome:outcome,
            deferredReason:deferredReason,unableReason:unableReason,note:note,evidenceReferences:reboundEvidence,
            revision:revision,mutationID:mutationID,predecessorResultID:mappedPredecessorResultID,
            predecessorResultSHA256:mappedPredecessorResultSHA256)}
    func rebound(to workspaceID:WorkspaceID,activityID:UUID,revision:UInt64,mutationID:MutationIDV1)throws->Self{
        guard revision==1 else{throw ActivityContractFailureV2.missingReference}
        return try rebound(to:workspaceID,activityID:activityID,revision:revision,mutationID:mutationID,
            mappedPredecessorResultID:nil,mappedPredecessorResultSHA256:nil)}
    private var basis:Basis{.init(resultID:resultID,workspaceID:workspaceID,activityID:activityID,taskID:taskID,outcome:outcome,
        deferredReason:deferredReason,unableReason:unableReason,note:note,evidenceReferences:evidenceReferences,
        revision:revision,mutationID:mutationID,predecessorResultID:predecessorResultID,
        predecessorResultSHA256:predecessorResultSHA256)}
    private struct Basis:Codable{let resultID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let taskID:String;let outcome:InstallationTaskOutcomeV1
        let deferredReason:InstallationDeferredReasonV1?;let unableReason:InstallationUnableReasonV1?;let note:String?
        let evidenceReferences:[ContentReferenceV1];let revision:UInt64;let mutationID:MutationIDV1
        let predecessorResultID:UUID?;let predecessorResultSHA256:String?}
}

enum InstallationTaskResultLineageV1{
    static func validateAndCurrentHeads(_ values:[InstallationTaskResultV1])throws->[String:InstallationTaskResultV1]{
        guard values.count<=ActivityContractValidationV2.maximumTasks,
              Set(values.map(\.resultID)).count==values.count,
              Set(values.map(\.resultSHA256)).count==values.count else{throw ActivityContractFailureV2.duplicateIdentity}
        var heads:[String:InstallationTaskResultV1]=[:]
        for value in values.sorted(){try value.validate()
            if value.revision==1{guard heads[value.taskID]==nil else{throw ActivityContractFailureV2.duplicateIdentity}}
            else{guard let predecessor=heads[value.taskID] else{throw ActivityContractFailureV2.missingReference}
                try value.validateSuccessor(of:predecessor)}
            heads[value.taskID]=value
        }
        return heads
    }
}

struct InstallationAsBuiltSnapshotV1:Codable,Equatable,Sendable{
    let snapshotID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let basisReference:InstallationBasisReferenceV1
    var basisSHA256:String{basisReference.basisSHA256}
    let taskResultSHA256s:[String];let placementReferences:[InstallationPlacementReferenceV2]
    var placementReferenceSHA256s:[String]{placementReferences.map{switch $0{case let .plan(v):return v.placementSHA256;case let .pose(v):return v.eventSHA256}}}
    let completion:InstallationCompletionDispositionV1
    let limitation:String?;let revision:UInt64;let mutationID:MutationIDV1;let snapshotSHA256:String
    init(snapshotID:UUID,workspaceID:WorkspaceID,activityID:UUID,basisReference:InstallationBasisReferenceV1,taskResultSHA256s:[String],
         placementReferences:[InstallationPlacementReferenceV2]=[],completion:InstallationCompletionDispositionV1,limitation:String?=nil,
         revision:UInt64,mutationID:MutationIDV1)throws{
        let results=taskResultSHA256s.sorted(),placements=placementReferences.sorted{$0.stableKey<$1.stableKey};let basis=Basis(snapshotID:snapshotID,
            workspaceID:workspaceID,activityID:activityID,basisReference:basisReference,taskResultSHA256s:results,
            placementReferences:placements,completion:completion,limitation:limitation,revision:revision,mutationID:mutationID)
        self.snapshotID=snapshotID;self.workspaceID=workspaceID;self.activityID=activityID;self.basisReference=basisReference
        self.taskResultSHA256s=results;self.placementReferences=placements;self.completion=completion;self.limitation=limitation
        self.revision=revision;self.mutationID=mutationID
        snapshotSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{try basisReference.validate();try placementReferences.forEach{try $0.validate(workspaceID:workspaceID)}
        guard snapshotID != ActivityContractValidationV2.zeroUUID,activityID != ActivityContractValidationV2.zeroUUID,
        revision>0,basisReference.workspaceID==workspaceID,basisReference.activityID==activityID,
        !taskResultSHA256s.isEmpty,ActivityContractValidationV2.sortedUnique(taskResultSHA256s),
        placementReferences==placementReferences.sorted(by:{$0.stableKey<$1.stableKey}),
        Set(placementReferences.map(\.stableKey)).count==placementReferences.count,
        taskResultSHA256s.allSatisfy(ActivityContractValidationV2.digest),
        limitation.map({ ActivityContractValidationV2.text($0) }) ?? true,(completion == .completedAsRecorded)==(limitation == nil),
        snapshotSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidValue}}
    func validateBasis(_ basis:InstallationBasisSnapshotV1)throws{try validate();try basisReference.validate(basis)}
    func rebound(to workspaceID:WorkspaceID,activityID:UUID,basis:InstallationBasisSnapshotV1,
                 revision:UInt64,mutationID:MutationIDV1)throws->Self{
        try Self(snapshotID:snapshotID,workspaceID:workspaceID,activityID:activityID,basisReference:InstallationBasisReferenceV1(basis),
            taskResultSHA256s:taskResultSHA256s,placementReferences:placementReferences,
            completion:completion,limitation:limitation,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(snapshotID:snapshotID,workspaceID:workspaceID,activityID:activityID,basisReference:basisReference,
        taskResultSHA256s:taskResultSHA256s,placementReferences:placementReferences,completion:completion,
        limitation:limitation,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let snapshotID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let basisReference:InstallationBasisReferenceV1
        let taskResultSHA256s:[String];let placementReferences:[InstallationPlacementReferenceV2];let completion:InstallationCompletionDispositionV1
        let limitation:String?;let revision:UInt64;let mutationID:MutationIDV1}
}

// MARK: - Standalone punch-review family

enum PunchReviewItemDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{
    case notReviewed="NOT_REVIEWED",reviewedNoItemRecorded="REVIEWED_NO_ITEM_RECORDED"
    case reviewedWithItems="REVIEWED_WITH_ITEMS",notApplicable="NOT_APPLICABLE",deferred="DEFERRED",unable="UNABLE"
}
enum PunchReviewDeferredReasonV1:String,Codable,CaseIterable,Hashable,Sendable{
    case accessUnavailable="ACCESS_UNAVAILABLE",siteNotReady="SITE_NOT_READY",weather="WEATHER"
    case awaitingRecordedDecision="AWAITING_RECORDED_DECISION",otherRecorded="OTHER_RECORDED"
}
enum PunchReviewUnableReasonV1:String,Codable,CaseIterable,Hashable,Sendable{
    case unsafeRecordedCondition="UNSAFE_RECORDED_CONDITION",subjectMismatch="SUBJECT_MISMATCH"
    case irrecoverableAccess="IRRECOVERABLE_ACCESS",otherRecorded="OTHER_RECORDED"
}
enum PunchReviewCompletionDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{
    case completedNoPunchItemsRecordedInScope="COMPLETED_NO_PUNCH_ITEMS_RECORDED_IN_SCOPE"
    case completedWithPunchItemsRecorded="COMPLETED_WITH_PUNCH_ITEMS_RECORDED",partiallyReviewed="PARTIALLY_REVIEWED"
    case unableAttemptRecorded="UNABLE_ATTEMPT_RECORDED",cancelled="CANCELLED"
}
struct PunchReviewScopeItemV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let scopeItemID:String;let ordinal:Int;let title:String
    static func <(lhs:Self,rhs:Self)->Bool{lhs.ordinal != rhs.ordinal ? lhs.ordinal<rhs.ordinal : lhs.scopeItemID<rhs.scopeItemID}
    init(scopeItemID:String,ordinal:Int,title:String)throws{guard ActivityContractValidationV2.token(scopeItemID),ordinal>=0,
        ActivityContractValidationV2.text(title)else{throw ActivityContractFailureV2.invalidValue};self.scopeItemID=scopeItemID;self.ordinal=ordinal;self.title=title}
}
struct PunchReviewReadinessPolicyV1:Codable,Equatable,Sendable{
    let requiredFacets:[ActivityReadinessFacetKindV1]
    init(requiredFacets:[ActivityReadinessFacetKindV1])throws{let values=requiredFacets.sorted{$0.rawValue<$1.rawValue}
        self.requiredFacets=values;try validate()}
    func validate()throws{guard !requiredFacets.isEmpty,
        requiredFacets==requiredFacets.sorted(by:{$0.rawValue<$1.rawValue}),Set(requiredFacets).count==requiredFacets.count
        else{throw ActivityContractFailureV2.invalidValue}}
    private enum CodingKeys:String,CodingKey,CaseIterable{case requiredFacets}
    init(from decoder:Decoder)throws{try ActivityClosedCodingV2.requireExactKeys(decoder,Set(CodingKeys.allCases.map(\.rawValue)))
        let values=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(requiredFacets:values.decode([ActivityReadinessFacetKindV1].self,forKey:.requiredFacets))}
    func encode(to encoder:Encoder)throws{try validate();var values=encoder.container(keyedBy:CodingKeys.self)
        try values.encode(requiredFacets,forKey:.requiredFacets)}
}
struct PunchReviewWorkflowDefinitionReleaseV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let scope:[PunchReviewScopeItemV1]
    let bundledRelease:ActivityBundledWorkflowReleaseV1;let readinessPolicy:PunchReviewReadinessPolicyV1
    let revision:UInt64;let mutationID:MutationIDV1;let releaseSHA256:String
    init(releaseID:UUID,workspaceID:WorkspaceID,scope:[PunchReviewScopeItemV1],readinessPolicy:PunchReviewReadinessPolicyV1,
         revision:UInt64,mutationID:MutationIDV1)throws{let ordered=scope.sorted();let basis=Basis(schemaVersion:Self.schemaVersion,
            releaseID:releaseID,workspaceID:workspaceID,scope:ordered,bundledRelease:.punchReviewV1,
            readinessPolicy:readinessPolicy,revision:revision,mutationID:mutationID)
        schemaVersion=Self.schemaVersion;self.releaseID=releaseID;self.workspaceID=workspaceID;self.scope=ordered
        bundledRelease = .punchReviewV1;self.readinessPolicy=readinessPolicy
        self.revision=revision;self.mutationID=mutationID;releaseSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{try readinessPolicy.validate();guard schemaVersion==Self.schemaVersion,releaseID != ActivityContractValidationV2.zeroUUID,revision>0,!scope.isEmpty,
        bundledRelease == .punchReviewV1,
        scope.count<=ActivityContractValidationV2.maximumScopeItems,ActivityContractValidationV2.sortedUnique(scope.map(\.scopeItemID)),
        releaseSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,releaseID:releaseID,workspaceID:workspaceID,scope:scope,
        bundledRelease:bundledRelease,readinessPolicy:readinessPolicy,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let scope:[PunchReviewScopeItemV1]
        let bundledRelease:ActivityBundledWorkflowReleaseV1;let readinessPolicy:PunchReviewReadinessPolicyV1
        let revision:UInt64;let mutationID:MutationIDV1}
}

enum ActivityReadinessPolicyBindingV2:Codable,Equatable,Sendable{
    case installation(InstallationReadinessPolicyV1)
    case punchReview(PunchReviewReadinessPolicyV1)

    var activityKind:ActivityKindV2{switch self{case .installation:return .installation;case .punchReview:return .punchReview}}
    var requiredFacets:[ActivityReadinessFacetKindV1]{switch self{
        case let .installation(value):return value.requiredFacets
        case let .punchReview(value):return value.requiredFacets}}

    func validate(readiness:[ActivityReadinessFacetV1],kind:ActivityKindV2,state:ActivityStateV2)throws{
        guard activityKind == kind else{throw ActivityContractFailureV2.invalidValue}
        switch self{case let .installation(value):try value.validate();case let .punchReview(value):try value.validate()}
        guard state == .ready || state == .inProgress else{return}
        let byKind=Dictionary(grouping:readiness,by:\.kind)
        for required in requiredFacets{
            guard let values=byKind[required],values.count==1,
                  values[0].disposition != .blocked,values[0].disposition != .deferred else{
                throw ActivityContractFailureV2.invalidTransition
            }
        }
        guard readiness.allSatisfy({$0.disposition != .blocked && $0.disposition != .deferred}) else{
            throw ActivityContractFailureV2.invalidTransition
        }
    }

    private enum Tag:String,Codable{case installation="INSTALLATION";case punchReview="PUNCH_REVIEW"}
    private enum CodingKeys:String,CodingKey,CaseIterable{case tag,installation,punchReview}
    init(from decoder:Decoder)throws{
        let container=try decoder.container(keyedBy:CodingKeys.self)
        let tag=try container.decode(Tag.self,forKey:.tag)
        switch tag{
        case .installation:
            try ActivityClosedCodingV2.requireExactKeys(decoder,[CodingKeys.tag.rawValue,CodingKeys.installation.rawValue])
            self = .installation(try container.decode(InstallationReadinessPolicyV1.self,forKey:.installation))
        case .punchReview:
            try ActivityClosedCodingV2.requireExactKeys(decoder,[CodingKeys.tag.rawValue,CodingKeys.punchReview.rawValue])
            self = .punchReview(try container.decode(PunchReviewReadinessPolicyV1.self,forKey:.punchReview))
        }
    }
    func encode(to encoder:Encoder)throws{
        var container=encoder.container(keyedBy:CodingKeys.self)
        switch self{
        case let .installation(value):try container.encode(Tag.installation,forKey:.tag);try container.encode(value,forKey:.installation)
        case let .punchReview(value):try container.encode(Tag.punchReview,forKey:.tag);try container.encode(value,forKey:.punchReview)
        }
    }
}
struct PunchReviewBasisSnapshotV1:Codable,Equatable,Sendable{
    let basisID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let subjectID:UUID
    let workflowReleaseReference:ActivityWorkflowReleaseReferenceV2
    var workflowReleaseSHA256:String{workflowReleaseReference.targetReleaseSHA256}
    let source:ActivityBasisSourceV1;let scopeLimitation:String;let capturedAt:Date;let revision:UInt64;let mutationID:MutationIDV1
    let predecessorBasisID:UUID?;let predecessorBasisSHA256:String?;let basisSHA256:String
    init(basisID:UUID,workspaceID:WorkspaceID,activityID:UUID,subjectID:UUID,
         workflowReleaseReference:ActivityWorkflowReleaseReferenceV2,
         source:ActivityBasisSourceV1,scopeLimitation:String,capturedAt:Date,revision:UInt64,mutationID:MutationIDV1,
         predecessorBasisID:UUID?=nil,predecessorBasisSHA256:String?=nil)throws{
        let basis=Basis(basisID:basisID,workspaceID:workspaceID,
            activityID:activityID,subjectID:subjectID,workflowReleaseReference:workflowReleaseReference,source:source,
            scopeLimitation:scopeLimitation,capturedAt:capturedAt,revision:revision,mutationID:mutationID,
            predecessorBasisID:predecessorBasisID,predecessorBasisSHA256:predecessorBasisSHA256)
        self.basisID=basisID;self.workspaceID=workspaceID;self.activityID=activityID;self.subjectID=subjectID
        self.workflowReleaseReference=workflowReleaseReference;self.source=source
        self.scopeLimitation=scopeLimitation;self.capturedAt=capturedAt
        self.revision=revision;self.mutationID=mutationID;self.predecessorBasisID=predecessorBasisID
        self.predecessorBasisSHA256=predecessorBasisSHA256
        basisSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{try workflowReleaseReference.validate();try source.validate();guard basisID != ActivityContractValidationV2.zeroUUID,
        activityID != ActivityContractValidationV2.zeroUUID,subjectID != ActivityContractValidationV2.zeroUUID,revision>0,
        workflowReleaseReference.bundledRelease == .punchReviewV1,
        workflowReleaseReference.targetWorkspaceID == workspaceID,
        (revision==1 && predecessorBasisID==nil && predecessorBasisSHA256==nil)
            || (revision>1 && predecessorBasisID != nil && predecessorBasisSHA256.map(ActivityContractValidationV2.digest)==true),
        ActivityContractValidationV2.text(scopeLimitation),basisSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))
        else{throw ActivityContractFailureV2.invalidValue}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validate();try validate()
        let(next,overflow)=predecessor.revision.addingReportingOverflow(1)
        guard !overflow,workspaceID==predecessor.workspaceID,activityID==predecessor.activityID,
            subjectID==predecessor.subjectID,revision==next,basisID != predecessor.basisID,
            predecessorBasisID==predecessor.basisID,predecessorBasisSHA256==predecessor.basisSHA256
        else{throw ActivityContractFailureV2.staleRevision}}
    func rebound(to workspaceID:WorkspaceID,activityID:UUID,subjectID:UUID,
                 workflowReleaseReference:ActivityWorkflowReleaseReferenceV2,
                 revision:UInt64,mutationID:MutationIDV1,mappedPredecessorBasisID:UUID?,
                 mappedPredecessorBasisSHA256:String?)throws->Self{
        try Self(basisID:basisID,workspaceID:workspaceID,activityID:activityID,subjectID:subjectID,
            workflowReleaseReference:workflowReleaseReference,source:source,scopeLimitation:scopeLimitation,
            capturedAt:capturedAt,revision:revision,mutationID:mutationID,
            predecessorBasisID:mappedPredecessorBasisID,predecessorBasisSHA256:mappedPredecessorBasisSHA256)}
    private var basis:Basis{.init(basisID:basisID,workspaceID:workspaceID,activityID:activityID,subjectID:subjectID,
        workflowReleaseReference:workflowReleaseReference,source:source,scopeLimitation:scopeLimitation,capturedAt:capturedAt,
        revision:revision,mutationID:mutationID,predecessorBasisID:predecessorBasisID,
        predecessorBasisSHA256:predecessorBasisSHA256)}
    private struct Basis:Codable{let basisID:UUID;let workspaceID:WorkspaceID;let activityID:UUID;let subjectID:UUID
        let workflowReleaseReference:ActivityWorkflowReleaseReferenceV2;let source:ActivityBasisSourceV1
        let scopeLimitation:String;let capturedAt:Date
        let revision:UInt64;let mutationID:MutationIDV1;let predecessorBasisID:UUID?;let predecessorBasisSHA256:String?}
}

struct PunchReviewBasisReferenceV1:Codable,Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let activityID:UUID;let basisID:UUID;let revision:UInt64;let basisSHA256:String
    init(_ basis:PunchReviewBasisSnapshotV1)throws{try basis.validate();workspaceID=basis.workspaceID
        activityID=basis.activityID;basisID=basis.basisID;revision=basis.revision;basisSHA256=basis.basisSHA256
        try validate(basis)}
    func validate()throws{guard workspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
        activityID != ActivityContractValidationV2.zeroUUID,basisID != ActivityContractValidationV2.zeroUUID,revision>0,
        ActivityContractValidationV2.digest(basisSHA256)else{throw ActivityContractFailureV2.missingReference}}
    func validate(_ basis:PunchReviewBasisSnapshotV1)throws{try validate();try basis.validate()
        guard basis.workspaceID==workspaceID,basis.activityID==activityID,basis.basisID==basisID,
            basis.revision==revision,basis.basisSHA256==basisSHA256 else{throw ActivityContractFailureV2.missingReference}}
}

enum ActivityBasisHeadReferenceV2:Codable,Equatable,Hashable,Sendable{
    case installation(InstallationBasisReferenceV1)
    case punchReview(PunchReviewBasisReferenceV1)
    var workspaceID:WorkspaceID{switch self{case let .installation(v):return v.workspaceID;case let .punchReview(v):return v.workspaceID}}
    var activityID:UUID{switch self{case let .installation(v):return v.activityID;case let .punchReview(v):return v.activityID}}
    var revision:UInt64{switch self{case let .installation(v):return v.revision;case let .punchReview(v):return v.revision}}
    var basisSHA256:String{switch self{case let .installation(v):return v.basisSHA256;case let .punchReview(v):return v.basisSHA256}}
    func validate()throws{switch self{case let .installation(v):try v.validate();case let .punchReview(v):try v.validate()}}
}
enum ActivitySupportingRecordKindV2:String,Codable,CaseIterable,Hashable,Sendable{
    case correctiveAction="CORRECTIVE_ACTION";case operationalRecheck="OPERATIONAL_RECHECK"
}
struct ActivitySupportingRecordReferenceV2:Codable,Equatable,Hashable,Sendable{
    let kind:ActivitySupportingRecordKindV2;let recordID:UUID;let revision:UInt64;let recordSHA256:String
    init(kind:ActivitySupportingRecordKindV2,recordID:UUID,revision:UInt64,recordSHA256:String)throws{
        guard recordID != ActivityContractValidationV2.zeroUUID,revision>0,
            ActivityContractValidationV2.digest(recordSHA256)else{throw ActivityContractFailureV2.invalidValue}
        self.kind=kind;self.recordID=recordID;self.revision=revision;self.recordSHA256=recordSHA256}
    func validate()throws{guard recordID != ActivityContractValidationV2.zeroUUID,revision>0,
        ActivityContractValidationV2.digest(recordSHA256)else{throw ActivityContractFailureV2.invalidValue}}
}
struct PunchFindingLinkV1:Codable,Equatable,Hashable,Sendable{
    let findingID:UUID;let findingRevision:Int;let findingSHA256:String;let sourceContext:FindingSourceContextV1
    let supportingRecords:[ActivitySupportingRecordReferenceV2]
    init(findingID:UUID,findingRevision:Int,findingSHA256:String,sourceContext:FindingSourceContextV1,
         supportingRecords:[ActivitySupportingRecordReferenceV2]=[])throws{
        let supports=supportingRecords.sorted{$0.kind.rawValue<$1.kind.rawValue}
        self.findingID=findingID;self.findingRevision=findingRevision;self.findingSHA256=findingSHA256
        self.sourceContext=sourceContext;self.supportingRecords=supports;try validate()}
    func validate()throws{try sourceContext.activityKind.requireKnownForMutation();try supportingRecords.forEach{try $0.validate()}
        guard findingID != ActivityContractValidationV2.zeroUUID,findingRevision>=0,
        ActivityContractValidationV2.digest(findingSHA256),sourceContext.activityKind==.installation || sourceContext.activityKind==.punchReview,
        supportingRecords==supportingRecords.sorted(by:{$0.kind.rawValue<$1.kind.rawValue}),
        Set(supportingRecords.map(\.kind)).count==supportingRecords.count
        else{throw ActivityContractFailureV2.invalidValue}}

    func rebound(
        to workspaceID: WorkspaceID,
        activityID: UUID,
        mappedActivitySHA256: String
    ) throws -> Self {
        try Self(
            findingID: findingID,
            findingRevision: findingRevision,
            findingSHA256: findingSHA256,
            sourceContext: sourceContext.rebound(
                to: workspaceID,
                activityID: activityID,
                mappedActivitySHA256: mappedActivitySHA256
            ),
            supportingRecords: supportingRecords
        )
    }
}
struct PunchItemProjectionV1:Codable,Equatable,Sendable{
    let scopeItemID:String;let disposition:PunchReviewItemDispositionV1;let findingLinks:[PunchFindingLinkV1]
    let deferredReason:PunchReviewDeferredReasonV1?;let unableReason:PunchReviewUnableReasonV1?
    init(scopeItemID:String,disposition:PunchReviewItemDispositionV1,findingLinks:[PunchFindingLinkV1]=[],
         deferredReason:PunchReviewDeferredReasonV1?=nil,unableReason:PunchReviewUnableReasonV1?=nil)throws{
        let links=findingLinks.sorted{$0.findingID.uuidString<$1.findingID.uuidString};guard ActivityContractValidationV2.token(scopeItemID),
            Set(links.map(\.findingID)).count==links.count,(disposition == .reviewedWithItems)==(!links.isEmpty),
            links.allSatisfy{$0.sourceContext.activityKind == .punchReview && $0.sourceContext.taskOrScopeID==scopeItemID},
            (disposition == .deferred)==(deferredReason != nil),(disposition == .unable)==(unableReason != nil),
            !(deferredReason != nil && unableReason != nil)else{throw ActivityContractFailureV2.invalidValue}
        self.scopeItemID=scopeItemID;self.disposition=disposition;self.findingLinks=links
        self.deferredReason=deferredReason;self.unableReason=unableReason
    }
    func validate()throws{
        try findingLinks.forEach{try $0.validate()}
        guard ActivityContractValidationV2.token(scopeItemID),Set(findingLinks.map(\.findingID)).count==findingLinks.count,
            findingLinks.allSatisfy{$0.sourceContext.activityKind == .punchReview && $0.sourceContext.taskOrScopeID==scopeItemID},
            (disposition == .reviewedWithItems)==(!findingLinks.isEmpty),(disposition == .deferred)==(deferredReason != nil),
            (disposition == .unable)==(unableReason != nil),!(deferredReason != nil && unableReason != nil)
        else{throw ActivityContractFailureV2.invalidValue}
    }


    func rebound(
        to workspaceID: WorkspaceID,
        activityID: UUID,
        mappedActivitySHA256: (String) throws -> String
    ) throws -> Self {
        try Self(
            scopeItemID: scopeItemID,
            disposition: disposition,
            findingLinks: findingLinks.map {
                try $0.rebound(
                    to: workspaceID,
                    activityID: activityID,
                    mappedActivitySHA256: mappedActivitySHA256(
                        $0.sourceContext.activitySHA256
                    )
                )
            },
            deferredReason: deferredReason,
            unableReason: unableReason
        )
    }
}

/// Installation closeout is a bounded statement about recorded work only. It
/// never means commissioning, release to service, safety, code compliance,
/// warranty, approval, certification, or authorization.
struct InstallationCloseoutV1: Codable, Equatable, Sendable {
    let completion: InstallationCompletionDispositionV1
    let asBuiltSnapshotSHA256: String
    let openFindings:[PunchFindingLinkV1]
    var openFindingSHA256s:[String]{openFindings.map(\.findingSHA256)}
    let limitation: String?
    let closeoutSHA256: String

    init(completion: InstallationCompletionDispositionV1, asBuiltSnapshotSHA256: String,
         openFindings: [PunchFindingLinkV1] = [], limitation: String? = nil) throws {
        let findings = openFindings.sorted{$0.findingID.uuidString<$1.findingID.uuidString}
        let basis = Basis(completion: completion, asBuiltSnapshotSHA256: asBuiltSnapshotSHA256,
                          openFindings: findings, limitation: limitation)
        self.completion = completion; self.asBuiltSnapshotSHA256 = asBuiltSnapshotSHA256
        self.openFindings = findings; self.limitation = limitation
        closeoutSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
        try validate()
    }

    func validate() throws {
        try openFindings.forEach{try $0.validate()}
        guard ActivityContractValidationV2.digest(asBuiltSnapshotSHA256),
              openFindings==openFindings.sorted(by:{$0.findingID.uuidString<$1.findingID.uuidString}),
              Set(openFindings.map(\.findingID)).count==openFindings.count,
              openFindings.allSatisfy{$0.sourceContext.activityKind == .installation},
              limitation.map({ ActivityContractValidationV2.text($0) }) ?? true,
              closeoutSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw ActivityContractFailureV2.invalidValue
        }
        switch completion {
        case .completedAsRecorded:
            guard openFindings.isEmpty, limitation == nil else { throw ActivityContractFailureV2.unsupportedClaim }
        case .completedWithOpenItems:
            guard !openFindings.isEmpty, limitation != nil else { throw ActivityContractFailureV2.unsupportedClaim }
        case .partiallyCompleted, .unableAttemptRecorded, .cancelled:
            guard limitation != nil else { throw ActivityContractFailureV2.unsupportedClaim }
        }
    }
    private var basis:Basis{.init(completion:completion,asBuiltSnapshotSHA256:asBuiltSnapshotSHA256,
        openFindings:openFindings,limitation:limitation)}
    private struct Basis:Codable{let completion:InstallationCompletionDispositionV1;let asBuiltSnapshotSHA256:String
        let openFindings:[PunchFindingLinkV1];let limitation:String?}

    func rebound(
        to workspaceID: WorkspaceID,
        activityID: UUID,
        asBuiltSnapshotSHA256: String,
        mappedActivitySHA256: (String) throws -> String
    ) throws -> Self {
        try Self(
            completion: completion,
            asBuiltSnapshotSHA256: asBuiltSnapshotSHA256,
            openFindings: openFindings.map {
                try $0.rebound(
                    to: workspaceID,
                    activityID: activityID,
                    mappedActivitySHA256: mappedActivitySHA256(
                        $0.sourceContext.activitySHA256
                    )
                )
            },
            limitation: limitation
        )
    }
}

/// Punch closeout is independently derived from the recorded review scope.
/// Even a no-item result must preserve an explicit scope/time limitation.
struct PunchReviewCloseoutV1: Codable, Equatable, Sendable {
    let completion: PunchReviewCompletionDispositionV1
    let basisSHA256: String
    let scope: [PunchItemProjectionV1]
    let scopeAndTimeLimitation: String
    let closeoutSHA256: String

    init(completion: PunchReviewCompletionDispositionV1, basisSHA256: String,
         scope: [PunchItemProjectionV1], scopeAndTimeLimitation: String) throws {
        let ordered = scope.sorted { $0.scopeItemID < $1.scopeItemID }
        let basis = Basis(completion:completion,basisSHA256:basisSHA256,scope:ordered,
                          scopeAndTimeLimitation:scopeAndTimeLimitation)
        self.completion=completion;self.basisSHA256=basisSHA256;self.scope=ordered
        self.scopeAndTimeLimitation=scopeAndTimeLimitation
        closeoutSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()
    }
    func validate()throws{
        try scope.forEach{try $0.validate()}
        guard ActivityContractValidationV2.digest(basisSHA256),!scope.isEmpty,
              scope.count<=ActivityContractValidationV2.maximumScopeItems,
              ActivityContractValidationV2.sortedUnique(scope.map(\.scopeItemID)),
              ActivityContractValidationV2.text(scopeAndTimeLimitation),
              closeoutSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))
        else{throw ActivityContractFailureV2.invalidValue}
        let hasItems=scope.contains{!$0.findingLinks.isEmpty}
        switch completion {
        case .completedNoPunchItemsRecordedInScope:
            guard !hasItems,scope.allSatisfy({$0.disposition == .reviewedNoItemRecorded || $0.disposition == .notApplicable})
            else{throw ActivityContractFailureV2.unsupportedClaim}
        case .completedWithPunchItemsRecorded:
            guard hasItems,
                scope.allSatisfy({ $0.disposition == .reviewedWithItems
                    || $0.disposition == .reviewedNoItemRecorded
                    || $0.disposition == .notApplicable })
            else{throw ActivityContractFailureV2.unsupportedClaim}
        case .partiallyReviewed:
            guard scope.contains(where:{ $0.disposition == .notReviewed || $0.disposition == .deferred }),
                !scope.contains(where:{ $0.disposition == .unable })
            else{throw ActivityContractFailureV2.unsupportedClaim}
        case .unableAttemptRecorded:
            guard scope.contains(where:{ $0.disposition == .unable })
            else{throw ActivityContractFailureV2.unsupportedClaim}
        case .cancelled:
            guard !scope.allSatisfy({ $0.disposition == .reviewedNoItemRecorded
                || $0.disposition == .reviewedWithItems
                || $0.disposition == .notApplicable })
            else{throw ActivityContractFailureV2.unsupportedClaim}
        }
    }
    private var basis:Basis{.init(completion:completion,basisSHA256:basisSHA256,scope:scope,
        scopeAndTimeLimitation:scopeAndTimeLimitation)}
    private struct Basis:Codable{let completion:PunchReviewCompletionDispositionV1;let basisSHA256:String
        let scope:[PunchItemProjectionV1];let scopeAndTimeLimitation:String}

    func rebound(
        to workspaceID: WorkspaceID,
        activityID: UUID,
        basisSHA256: String,
        mappedActivitySHA256: (String) throws -> String
    ) throws -> Self {
        try Self(
            completion: completion,
            basisSHA256: basisSHA256,
            scope: scope.map {
                try $0.rebound(
                    to: workspaceID,
                    activityID: activityID,
                    mappedActivitySHA256: mappedActivitySHA256
                )
            },
            scopeAndTimeLimitation: scopeAndTimeLimitation
        )
    }
}

/// Runtime-only proof assembled from the existing Finding/corrective/recheck
/// owners. It adds no finding status or persistence authority.
struct ActivityCloseoutResolutionContextV2:Sendable{
    struct FindingFact:Sendable{let revision:Int;let sha256:String}
    let findingFactsByID:[UUID:FindingFact]
    let supportingRecords:Set<ActivitySupportingRecordReferenceV2>
    let sourceEnvelopesBySHA256:[String:ActivitySessionEnvelopeV2]
    let installationAsBuiltSnapshot:InstallationAsBuiltSnapshotV1?
    init(findings:[FindingV1],supportingRecords:[ActivitySupportingRecordReferenceV2],
         sourceEnvelopes:[ActivitySessionEnvelopeV2],
         installationAsBuiltSnapshot:InstallationAsBuiltSnapshotV1?=nil)throws{
        var values:[UUID:FindingFact]=[:]
        for finding in findings{
            guard let id=UUID(uuidString:finding.findingID),values[id]==nil else{throw ActivityContractFailureV2.duplicateIdentity}
            let sha=try WorkspaceMutationCanonicalV1.sha256(finding)
            values[id]=FindingFact(revision:finding.revision,sha256:sha)
        }
        try sourceEnvelopes.forEach{try $0.validateForRead()}
        guard Set(sourceEnvelopes.map(\.envelopeSHA256)).count==sourceEnvelopes.count else{throw ActivityContractFailureV2.duplicateIdentity}
        findingFactsByID=values;self.supportingRecords=Set(supportingRecords)
        sourceEnvelopesBySHA256=Dictionary(uniqueKeysWithValues:sourceEnvelopes.map{($0.envelopeSHA256,$0)})
        self.installationAsBuiltSnapshot=installationAsBuiltSnapshot
    }
    func validate(_ envelope:ActivitySessionEnvelopeV2)throws{
        let links:[PunchFindingLinkV1]
        if let closeout=envelope.installationCloseout{
            guard let installationAsBuiltSnapshot,installationAsBuiltSnapshot.workspaceID==envelope.workspaceID,
                installationAsBuiltSnapshot.activityID==envelope.activityID,
                installationAsBuiltSnapshot.snapshotSHA256==closeout.asBuiltSnapshotSHA256
            else{throw ActivityContractFailureV2.missingReference}
            links=closeout.openFindings
        }
        else if let closeout=envelope.punchReviewCloseout{links=closeout.scope.flatMap(\.findingLinks)}
        else{guard findingFactsByID.isEmpty,supportingRecords.isEmpty,sourceEnvelopesBySHA256.isEmpty
            else{throw ActivityContractFailureV2.invalidValue};return}
        guard Set(links.map(\.findingID)).count==links.count else{throw ActivityContractFailureV2.duplicateIdentity}
        for link in links{
            guard let actual=findingFactsByID[link.findingID],actual.revision==link.findingRevision,
                actual.sha256==link.findingSHA256,link.sourceContext.workspaceID==envelope.workspaceID,
                link.sourceContext.activityID==envelope.activityID,link.sourceContext.activityKind==envelope.kind,
                link.sourceContext.activityRevision<=envelope.revision,
                Set(link.supportingRecords).isSubset(of:supportingRecords)
            else{throw ActivityContractFailureV2.missingReference}
            guard let sourceEnvelope=sourceEnvelopesBySHA256[link.sourceContext.activitySHA256],
                sourceEnvelope.workspaceID==link.sourceContext.workspaceID,
                sourceEnvelope.activityID==link.sourceContext.activityID,
                sourceEnvelope.kind==link.sourceContext.activityKind,
                sourceEnvelope.revision==link.sourceContext.activityRevision
            else{throw ActivityContractFailureV2.missingReference}
        }
    }
}

/// Additive C47 binding to the already-released CompletedActivitySnapshotV2
/// codec. The historic snapshot bytes remain owned by
/// CompletedActivitySnapshotCanonicalCodecV2 and are never rewritten into an
/// activity-envelope-shaped record.
struct CompletedActivitySnapshotV2CompatibilityReferenceV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let sourceWorkspaceID: WorkspaceID
    let sourceActivityID: UUID
    let sourceActivityRevision: Int
    let sourceSubjectID: UUID
    let sourceCloseoutSHA256:String
    let targetCloseoutSHA256:String
    let snapshotID: String
    let snapshotRevision: Int
    let snapshotSHA256: String

    init(_ snapshot: CompletedActivitySnapshotV2, activityCloseoutSHA256:String) throws {
        try snapshot.validate()
        let activity = snapshot.payload.activity
        guard let workspaceUUID = UUID(uuidString: activity.workspaceID),
              let activityUUID = UUID(uuidString: activity.sourceActivityID) else {
            throw ActivityContractFailureV2.missingReference
        }
        workspaceID = WorkspaceID(rawValue: workspaceUUID)
        activityID = activityUUID
        sourceWorkspaceID = WorkspaceID(rawValue: workspaceUUID)
        sourceActivityID = activityUUID
        sourceActivityRevision = activity.sourceRevision
        sourceSubjectID = snapshot.payload.assetID
        sourceCloseoutSHA256=activityCloseoutSHA256
        targetCloseoutSHA256=activityCloseoutSHA256
        snapshotID = activity.snapshotID
        snapshotRevision = activity.snapshotRevision
        snapshotSHA256 = snapshot.snapshotSHA256
        try validate(snapshot: snapshot)
    }

    func rebound(
        to workspaceID: WorkspaceID,
        activityID: UUID,
        targetCloseoutSHA256: String
    ) throws -> Self {
        try Self(workspaceID: workspaceID, activityID: activityID,
                 sourceWorkspaceID: sourceWorkspaceID, sourceActivityID: sourceActivityID,
                 sourceActivityRevision: sourceActivityRevision, sourceSubjectID: sourceSubjectID,
                 sourceCloseoutSHA256:sourceCloseoutSHA256,
                 targetCloseoutSHA256:targetCloseoutSHA256,
                 snapshotID: snapshotID, snapshotRevision: snapshotRevision,
                 snapshotSHA256: snapshotSHA256)
    }

    private init(workspaceID: WorkspaceID, activityID: UUID,
                 sourceWorkspaceID: WorkspaceID, sourceActivityID: UUID,
                 sourceActivityRevision: Int, sourceSubjectID: UUID,
                 sourceCloseoutSHA256:String,targetCloseoutSHA256:String,snapshotID: String,
                 snapshotRevision: Int, snapshotSHA256: String) throws {
        self.workspaceID = workspaceID; self.activityID = activityID
        self.sourceWorkspaceID = sourceWorkspaceID; self.sourceActivityID = sourceActivityID
        self.sourceActivityRevision = sourceActivityRevision; self.sourceSubjectID = sourceSubjectID
        self.sourceCloseoutSHA256=sourceCloseoutSHA256
        self.targetCloseoutSHA256=targetCloseoutSHA256
        self.snapshotID = snapshotID; self.snapshotRevision = snapshotRevision
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    func validate() throws {
        guard workspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
              activityID != ActivityContractValidationV2.zeroUUID,
              sourceWorkspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
              sourceActivityID != ActivityContractValidationV2.zeroUUID,
              sourceActivityRevision > 0, sourceSubjectID != ActivityContractValidationV2.zeroUUID,
              ActivityContractValidationV2.digest(sourceCloseoutSHA256),
              ActivityContractValidationV2.digest(targetCloseoutSHA256),
              ActivityContractValidationV2.token(snapshotID), snapshotRevision > 0,
              ActivityContractValidationV2.digest(snapshotSHA256) else {
            throw ActivityContractFailureV2.missingReference
        }
    }

    func validate(snapshot: CompletedActivitySnapshotV2) throws {
        try validate()
        try snapshot.validate()
        let activity = snapshot.payload.activity
        guard activity.workspaceID.lowercased() == sourceWorkspaceID.rawValue.uuidString.lowercased(),
              activity.sourceActivityID.lowercased() == sourceActivityID.uuidString.lowercased(),
              activity.sourceRevision == sourceActivityRevision,
              snapshot.payload.assetID == sourceSubjectID,
              activity.snapshotID == snapshotID, activity.snapshotRevision == snapshotRevision,
              snapshot.snapshotSHA256 == snapshotSHA256 else {
            throw ActivityContractFailureV2.missingReference
        }
    }
}

/// Runtime-only proof supplied by the authority that owns the released,
/// file-backed CompletedActivitySnapshotV2 bytes. It is intentionally not a
/// second persistent record or a replacement snapshot codec.
struct CompletedActivitySnapshotResolutionContextV2: Sendable {
    let reference: CompletedActivitySnapshotV2CompatibilityReferenceV1
    let snapshot: CompletedActivitySnapshotV2

    init(reference: CompletedActivitySnapshotV2CompatibilityReferenceV1,
         snapshot: CompletedActivitySnapshotV2) throws {
        try reference.validate(snapshot: snapshot)
        self.reference = reference; self.snapshot = snapshot
    }
}

/// Runtime-only current-head proof. Persistence constructs this from the sole
/// InstallationTaskResult row family before applying a mutation.
struct InstallationTaskCurrentHeadContextV1: Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let headsByTaskID: [String: InstallationTaskResultV1]

    init(workspaceID: WorkspaceID, activityID: UUID,
         currentHeads: [InstallationTaskResultV1]) throws {
        try currentHeads.forEach { try $0.validate() }
        guard workspaceID.rawValue != ActivityContractValidationV2.zeroUUID,
              activityID != ActivityContractValidationV2.zeroUUID,
              currentHeads.count <= ActivityContractValidationV2.maximumTasks,
              currentHeads.allSatisfy { $0.workspaceID == workspaceID && $0.activityID == activityID },
              Set(currentHeads.map(\.taskID)).count == currentHeads.count else {
            throw ActivityContractFailureV2.duplicateIdentity
        }
        self.workspaceID = workspaceID; self.activityID = activityID
        headsByTaskID = Dictionary(uniqueKeysWithValues: currentHeads.map { ($0.taskID, $0) })
    }

    func validate(successors: [InstallationTaskResultV1]) throws {
        guard Set(successors.map(\.taskID)).count == successors.count else {
            throw ActivityContractFailureV2.duplicateIdentity
        }
        for successor in successors {
            if let predecessor = headsByTaskID[successor.taskID] {
                try successor.validateSuccessor(of: predecessor)
            } else {
                guard successor.revision == 1, successor.predecessorResultID == nil,
                      successor.predecessorResultSHA256 == nil else {
                    throw ActivityContractFailureV2.staleRevision
                }
            }
        }
    }
}

/// Runtime-only resolution of C47 references through their existing content,
/// plan, and placement-pose owners. It adds no storage or status authority.
struct ActivityInstallationReferenceResolutionContextV2: Sendable {
    let contentReferences: Set<ContentReferenceV1>
    let planPlacementsByReference: [PlanPlacementReferenceV1: PlanPlacementV1]
    let poseEventsByReference: [AssetPoseEventReferenceV1: AssetPoseEventV1]

    init(
        contentReferences: [ContentReferenceV1],
        planPlacements: [PlanPlacementV1],
        poseEvents: [AssetPoseEventV1]
    ) throws {
        let planPairs = try planPlacements.map { value -> (PlanPlacementReferenceV1, PlanPlacementV1) in
            try value.validateIntrinsic()
            return (PlanPlacementReferenceV1(
                placementID: value.placementID,
                revision: value.revision,
                placementSHA256: value.placementSHA256
            ), value)
        }
        let posePairs = try poseEvents.map { value -> (AssetPoseEventReferenceV1, AssetPoseEventV1) in
            try value.validateIntrinsic()
            return (value.reference, value)
        }
        guard Set(planPairs.map(\.0)).count == planPairs.count,
              Set(posePairs.map(\.0)).count == posePairs.count else {
            throw ActivityContractFailureV2.duplicateIdentity
        }
        self.contentReferences = Set(contentReferences)
        planPlacementsByReference = Dictionary(uniqueKeysWithValues: planPairs)
        poseEventsByReference = Dictionary(uniqueKeysWithValues: posePairs)
    }

    func validate(_ mutation: ActivityContractMutationV2) throws {
        for result in mutation.installationTaskResults {
            guard Set(result.evidenceReferences).isSubset(of: contentReferences) else {
                throw ActivityContractFailureV2.missingReference
            }
        }
        if let snapshot = mutation.installationAsBuiltSnapshot {
            for reference in snapshot.placementReferences {
                switch reference {
                case let .plan(value):
                    guard let placement = planPlacementsByReference[value],
                          placement.workspaceID == mutation.workspaceID,
                          placement.subjectID == mutation.successorEnvelope.subjectID else {
                        throw ActivityContractFailureV2.missingReference
                    }
                case let .pose(value):
                    guard let event = poseEventsByReference[value],
                          event.workspaceID == mutation.workspaceID,
                          event.assetID == mutation.successorEnvelope.subjectID else {
                        throw ActivityContractFailureV2.missingReference
                    }
                }
            }
        }
    }
}

// MARK: - One canonical writer mutation envelope

struct ActivityContractMutationV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let predecessorEnvelope: ActivitySessionEnvelopeV2?
    let successorEnvelope: ActivitySessionEnvelopeV2
    let transition: ActivityStateTransitionV2?
    let completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1?
    let installationBasisSnapshot: InstallationBasisSnapshotV1?
    let installationTaskResults: [InstallationTaskResultV1]
    let installationAsBuiltSnapshot: InstallationAsBuiltSnapshotV1?
    let punchReviewBasisSnapshot: PunchReviewBasisSnapshotV1?
    let mutationSHA256: String

    init(workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1, mutationID: MutationIDV1,
         predecessorEnvelope: ActivitySessionEnvelopeV2? = nil, successorEnvelope: ActivitySessionEnvelopeV2,
         transition: ActivityStateTransitionV2? = nil,
         completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1? = nil,
         installationBasisSnapshot: InstallationBasisSnapshotV1? = nil,
         installationTaskResults: [InstallationTaskResultV1] = [],
         installationAsBuiltSnapshot: InstallationAsBuiltSnapshotV1? = nil,
         punchReviewBasisSnapshot: PunchReviewBasisSnapshotV1? = nil) throws {
        let results = installationTaskResults.sorted {
            $0.resultID.uuidString < $1.resultID.uuidString
        }
        let basis = Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID,
                          expectedRevision: expectedRevision, mutationID: mutationID,
                          predecessorEnvelope: predecessorEnvelope, successorEnvelope: successorEnvelope,
                          transition: transition, completedSnapshotReference: completedSnapshotReference,
                          installationBasisSnapshot: installationBasisSnapshot,
                          installationTaskResults: results,
                          installationAsBuiltSnapshot: installationAsBuiltSnapshot,
                          punchReviewBasisSnapshot: punchReviewBasisSnapshot)
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision; self.mutationID = mutationID
        self.predecessorEnvelope = predecessorEnvelope; self.successorEnvelope = successorEnvelope
        self.transition = transition; self.completedSnapshotReference = completedSnapshotReference
        self.installationBasisSnapshot = installationBasisSnapshot
        self.installationTaskResults = results; self.installationAsBuiltSnapshot = installationAsBuiltSnapshot
        self.punchReviewBasisSnapshot = punchReviewBasisSnapshot
        mutationSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
        try validate()
    }

    func validate() throws {
        try successorEnvelope.validateForMutation()
        try ActivityCanonicalStorageAuthorityV2.requireNewC47RowMutationAuthority(successorEnvelope.kind)
        try predecessorEnvelope?.validateForRead(); try transition?.validate()
        try completedSnapshotReference?.validate()
        try installationBasisSnapshot?.validate()
        try installationTaskResults.forEach { try $0.validate() }
        try installationAsBuiltSnapshot?.validate(); try punchReviewBasisSnapshot?.validate()
        let activityID = successorEnvelope.activityID
        guard schemaVersion == Self.schemaVersion, expectedRevision.workspaceID == workspaceID,
              successorEnvelope.workspaceID == workspaceID, successorEnvelope.mutationID == mutationID,
              predecessorEnvelope.map { $0.workspaceID == workspaceID && $0.activityID == activityID } ?? true,
              transition.map { $0.workspaceID == workspaceID && $0.activityID == activityID
                && $0.kind == successorEnvelope.kind && $0.mutationID == mutationID
                && $0.revision == successorEnvelope.revision } ?? true,
              completedSnapshotReference.map { $0.workspaceID == workspaceID && $0.activityID == activityID } ?? true,
              completedSnapshotReference == successorEnvelope.completedSnapshotReference,
              installationBasisSnapshot.map { $0.workspaceID == workspaceID && $0.activityID == activityID } ?? true,
              installationTaskResults.allSatisfy { $0.workspaceID == workspaceID && $0.activityID == activityID && $0.mutationID == mutationID },
              installationAsBuiltSnapshot.map { $0.workspaceID == workspaceID && $0.activityID == activityID && $0.mutationID == mutationID } ?? true,
              punchReviewBasisSnapshot.map { $0.workspaceID == workspaceID && $0.activityID == activityID && $0.mutationID == mutationID } ?? true,
              Set(installationTaskResults.map(\.resultID)).count == installationTaskResults.count,
              Set(installationTaskResults.map(\.taskID)).count == installationTaskResults.count,
              mutationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw ActivityContractFailureV2.invalidValue
        }
        if let predecessorEnvelope {
            try successorEnvelope.validateSuccessor(of: predecessorEnvelope)
            if predecessorEnvelope.state == successorEnvelope.state {
                guard transition == nil else { throw ActivityContractFailureV2.invalidTransition }
            } else {
                guard let transition, transition.fromState == predecessorEnvelope.state,
                      transition.toState == successorEnvelope.state else {
                    throw ActivityContractFailureV2.invalidTransition
                }
            }
        } else {
            guard successorEnvelope.revision == 1, successorEnvelope.state == .draft,
                  successorEnvelope.predecessorEnvelopeSHA256 == nil, transition == nil else {
                throw ActivityContractFailureV2.invalidTransition
            }
        }
        switch successorEnvelope.kind {
        case .installation:
            guard punchReviewBasisSnapshot == nil else { throw ActivityContractFailureV2.invalidValue }
            if successorEnvelope.state == .ready || successorEnvelope.state == .inProgress {
                guard let readinessPolicy = successorEnvelope.readinessPolicy else { throw ActivityContractFailureV2.missingReference }
                try readinessPolicy.validate(readiness: successorEnvelope.readiness,
                                             kind: successorEnvelope.kind,
                                             state: successorEnvelope.state)
            } else if let readinessPolicy = successorEnvelope.readinessPolicy {
                guard readinessPolicy.activityKind == .installation else {
                    throw ActivityContractFailureV2.invalidValue
                }
            }
            if let installationAsBuiltSnapshot {
                if let installationBasisSnapshot {
                    try installationAsBuiltSnapshot.validateBasis(installationBasisSnapshot)
                } else {
                    guard case let .installation(reference)? = successorEnvelope.currentBasisReference,
                          reference == installationAsBuiltSnapshot.basisReference else {
                        throw ActivityContractFailureV2.missingReference
                    }
                }
                if let closeout = successorEnvelope.installationCloseout {
                    guard closeout.asBuiltSnapshotSHA256 == installationAsBuiltSnapshot.snapshotSHA256,
                          closeout.completion == installationAsBuiltSnapshot.completion else {
                        throw ActivityContractFailureV2.missingReference
                    }
                }
            }
            try validateInstallationBasisLineage()
        case .punchReview:
            guard installationBasisSnapshot == nil, installationTaskResults.isEmpty,
                  installationAsBuiltSnapshot == nil else {
                throw ActivityContractFailureV2.invalidValue
            }
            if successorEnvelope.state == .ready || successorEnvelope.state == .inProgress {
                guard let readinessPolicy = successorEnvelope.readinessPolicy else { throw ActivityContractFailureV2.missingReference }
                try readinessPolicy.validate(readiness: successorEnvelope.readiness,
                                             kind: successorEnvelope.kind,
                                             state: successorEnvelope.state)
            } else if let readinessPolicy = successorEnvelope.readinessPolicy {
                guard readinessPolicy.activityKind == .punchReview else {
                    throw ActivityContractFailureV2.invalidValue
                }
            }
            try validatePunchBasisLineage()
        default:
            // The seven-kind vocabulary is used for read/route/report
            // compatibility. New C47 row admission belongs only to the two
            // additive contract families; legacy kinds remain with their
            // released V1 writers and rows.
            throw ActivityContractFailureV2.unknownKindMutation
        }
    }

    private func validateInstallationBasisLineage()throws{
        let predecessorReference:InstallationBasisReferenceV1?={if case let .installation(v)?=predecessorEnvelope?.currentBasisReference{return v};return nil}()
        let successorReference:InstallationBasisReferenceV1?={if case let .installation(v)?=successorEnvelope.currentBasisReference{return v};return nil}()
        if let installationBasisSnapshot{
            let reference=try InstallationBasisReferenceV1(installationBasisSnapshot)
            guard successorReference==reference,installationBasisSnapshot.mutationID==mutationID else{throw ActivityContractFailureV2.missingReference}
            if let predecessorReference{
                guard installationBasisSnapshot.predecessorBasisID==predecessorReference.basisID,
                    installationBasisSnapshot.predecessorBasisSHA256==predecessorReference.basisSHA256
                else{throw ActivityContractFailureV2.staleRevision}
                guard successorEnvelope.variations.contains(where: {
                    $0.mutationID == mutationID
                        && $0.predecessorBasisSHA256 == predecessorReference.basisSHA256
                        && $0.successorBasisSHA256 == installationBasisSnapshot.basisSHA256
                        && ($0.kind == .basisCorrected
                            || $0.kind == .optionalPlanReferenceChanged
                            || $0.kind == .physicalPlacementReferenceChanged)
                }) else { throw ActivityContractFailureV2.missingReference }
            }else{guard installationBasisSnapshot.revision==1 else{throw ActivityContractFailureV2.staleRevision}}
        }else{guard successorReference==predecessorReference else{throw ActivityContractFailureV2.missingReference}}
    }

    private func validatePunchBasisLineage()throws{
        let predecessorReference:PunchReviewBasisReferenceV1?={if case let .punchReview(v)?=predecessorEnvelope?.currentBasisReference{return v};return nil}()
        let successorReference:PunchReviewBasisReferenceV1?={if case let .punchReview(v)?=successorEnvelope.currentBasisReference{return v};return nil}()
        if let punchReviewBasisSnapshot{
            let reference=try PunchReviewBasisReferenceV1(punchReviewBasisSnapshot)
            guard successorReference==reference,punchReviewBasisSnapshot.mutationID==mutationID else{throw ActivityContractFailureV2.missingReference}
            if let predecessorReference{
                guard punchReviewBasisSnapshot.predecessorBasisID==predecessorReference.basisID,
                    punchReviewBasisSnapshot.predecessorBasisSHA256==predecessorReference.basisSHA256
                else{throw ActivityContractFailureV2.staleRevision}
                guard successorEnvelope.variations.contains(where: {
                    $0.mutationID == mutationID
                        && $0.predecessorBasisSHA256 == predecessorReference.basisSHA256
                        && $0.successorBasisSHA256 == punchReviewBasisSnapshot.basisSHA256
                        && ($0.kind == .basisCorrected
                            || $0.kind == .optionalPlanReferenceChanged
                            || $0.kind == .recordedScopeChanged)
                }) else { throw ActivityContractFailureV2.missingReference }
            }else{guard punchReviewBasisSnapshot.revision==1 else{throw ActivityContractFailureV2.staleRevision}}
        }else{guard successorReference==predecessorReference else{throw ActivityContractFailureV2.missingReference}}
    }

    /// Strong writer-side validation after persistence has resolved the
    /// released snapshot bytes and current task heads. Finalized mutations
    /// cannot be committed through the C47 adapter without this proof.
    func validateResolved(
        completedSnapshot context: CompletedActivitySnapshotResolutionContextV2?,
        installationTaskHeads: InstallationTaskCurrentHeadContextV1,
        currentInstallationBasis: InstallationBasisSnapshotV1? = nil,
        currentPunchBasis: PunchReviewBasisSnapshotV1? = nil,
        workflowReleaseContext: ActivityWorkflowReleaseResolutionContextV2? = nil,
        installationReferenceContext: ActivityInstallationReferenceResolutionContextV2? = nil,
        closeoutContext:ActivityCloseoutResolutionContextV2?=nil
    ) throws {
        try validate()
        guard installationTaskHeads.workspaceID == workspaceID,
              installationTaskHeads.activityID == successorEnvelope.activityID else {
            throw ActivityContractFailureV2.wrongWorkspace
        }
        if let completedSnapshotReference {
            guard let context, context.reference == completedSnapshotReference else {
                throw ActivityContractFailureV2.missingReference
            }
            try context.reference.validate(snapshot: context.snapshot)
            let expectedSourceRevision:UInt64
            if successorEnvelope.state == .finalized{expectedSourceRevision=successorEnvelope.revision}
            else if successorEnvelope.state == .superseded,let predecessorEnvelope,
                    predecessorEnvelope.completedSnapshotReference==completedSnapshotReference{
                expectedSourceRevision=predecessorEnvelope.revision
            }else{throw ActivityContractFailureV2.missingReference}
            guard Int(exactly: expectedSourceRevision)==completedSnapshotReference.sourceActivityRevision,
                  completedSnapshotReference.sourceWorkspaceID != workspaceID
                    || completedSnapshotReference.sourceSubjectID == successorEnvelope.subjectID else {
                throw ActivityContractFailureV2.missingReference
            }
            let expectedCloseoutSHA:String?
            if successorEnvelope.state == .finalized{
                expectedCloseoutSHA=successorEnvelope.installationCloseout?.closeoutSHA256
                    ?? successorEnvelope.punchReviewCloseout?.closeoutSHA256
            }else{
                expectedCloseoutSHA=predecessorEnvelope?.installationCloseout?.closeoutSHA256
                    ?? predecessorEnvelope?.punchReviewCloseout?.closeoutSHA256
            }
            guard completedSnapshotReference.targetCloseoutSHA256==expectedCloseoutSHA
            else{throw ActivityContractFailureV2.missingReference}
            if completedSnapshotReference.sourceWorkspaceID == workspaceID {
                guard completedSnapshotReference.sourceActivityID == successorEnvelope.activityID,
                      completedSnapshotReference.sourceSubjectID == successorEnvelope.subjectID,
                      completedSnapshotReference.sourceCloseoutSHA256
                        == completedSnapshotReference.targetCloseoutSHA256 else {
                    throw ActivityContractFailureV2.missingReference
                }
            } else {
                // A cross-workspace source is introduced only by the validated
                // clone/fork restore path. Live target mutations may preserve
                // that immutable provenance, but cannot manufacture a new one.
                guard predecessorEnvelope?.completedSnapshotReference
                        == completedSnapshotReference else {
                    throw ActivityContractFailureV2.missingReference
                }
            }
        } else {
            guard context == nil else { throw ActivityContractFailureV2.invalidValue }
        }
        if successorEnvelope.kind == .installation {
            guard currentPunchBasis == nil else { throw ActivityContractFailureV2.invalidValue }
            let resolvedBasis = installationBasisSnapshot ?? currentInstallationBasis
            if let installationBasisSnapshot, let currentInstallationBasis {
                try installationBasisSnapshot.validateSuccessor(of: currentInstallationBasis)
            }
            if let resolvedBasis {
                guard case let .installation(reference)? = successorEnvelope.currentBasisReference else {
                    throw ActivityContractFailureV2.missingReference
                }
                try reference.validate(resolvedBasis)
                guard let workflowReleaseContext else { throw ActivityContractFailureV2.missingReference }
                let isStarting = predecessorEnvelope?.startedAt == nil && successorEnvelope.startedAt != nil
                try workflowReleaseContext.validate(
                    expectedReference: resolvedBasis.workflowReleaseReference,
                    forStart: isStarting
                )
                if successorEnvelope.state == .ready || successorEnvelope.state == .inProgress {
                    guard successorEnvelope.readinessPolicy == workflowReleaseContext.readinessPolicy else {
                        throw ActivityContractFailureV2.missingReference
                    }
                }
            } else {
                guard successorEnvelope.currentBasisReference == nil,
                      case nil = workflowReleaseContext,
                      installationTaskResults.isEmpty,
                      installationAsBuiltSnapshot == nil,
                      successorEnvelope.installationCloseout == nil,
                      successorEnvelope.state == .draft || successorEnvelope.state == .preflightRequired else {
                    throw ActivityContractFailureV2.missingReference
                }
            }
            try installationTaskHeads.validate(successors: installationTaskResults)
            let requiredTaskIDs = workflowReleaseContext?.installationTaskIDs
            var resolvedTaskHeads = installationTaskHeads.headsByTaskID
            installationTaskResults.forEach { resolvedTaskHeads[$0.taskID] = $0 }
            if let requiredTaskIDs {
                guard resolvedTaskHeads.values.allSatisfy({ requiredTaskIDs.contains($0.taskID) }) else {
                    throw ActivityContractFailureV2.missingReference
                }
                guard (successorEnvelope.state != .finalized
                       && successorEnvelope.installationCloseout == nil)
                    || Set(resolvedTaskHeads.keys) == requiredTaskIDs else {
                    throw ActivityContractFailureV2.unsupportedClaim
                }
            } else {
                guard resolvedTaskHeads.isEmpty,
                      successorEnvelope.state != .finalized,
                      successorEnvelope.installationCloseout == nil else {
                    throw ActivityContractFailureV2.missingReference
                }
            }
            let resolvedAsBuiltSnapshot = installationAsBuiltSnapshot
                ?? closeoutContext?.installationAsBuiltSnapshot
            if let installationAsBuiltSnapshot = resolvedAsBuiltSnapshot {
                try installationAsBuiltSnapshot.validate()
                guard installationAsBuiltSnapshot.workspaceID == workspaceID,
                      installationAsBuiltSnapshot.activityID == successorEnvelope.activityID,
                      Set(installationAsBuiltSnapshot.taskResultSHA256s)
                    == Set(resolvedTaskHeads.values.map(\.resultSHA256)) else {
                    throw ActivityContractFailureV2.staleRevision
                }
            }
            if let closeout = successorEnvelope.installationCloseout {
                let asBuilt = resolvedAsBuiltSnapshot
                guard let asBuilt, asBuilt.completion == closeout.completion else {
                    throw ActivityContractFailureV2.unsupportedClaim
                }
                let outcomes = resolvedTaskHeads.values.map(\.outcome)
                switch closeout.completion {
                case .completedAsRecorded:
                    guard !outcomes.isEmpty,
                          outcomes.allSatisfy({ $0 == .completed || $0 == .notApplicable }),
                          closeout.openFindings.isEmpty else {
                        throw ActivityContractFailureV2.unsupportedClaim
                    }
                case .completedWithOpenItems:
                    guard !outcomes.isEmpty,
                          outcomes.allSatisfy({ $0 == .completed || $0 == .notApplicable }),
                          !closeout.openFindings.isEmpty else {
                        throw ActivityContractFailureV2.unsupportedClaim
                    }
                case .partiallyCompleted:
                    guard outcomes.contains(where: {
                        $0 == .notStarted || $0 == .inProgress || $0 == .deferred || $0 == .unable
                    }) else { throw ActivityContractFailureV2.unsupportedClaim }
                case .unableAttemptRecorded:
                    guard outcomes.contains(.unable) else {
                        throw ActivityContractFailureV2.unsupportedClaim
                    }
                case .cancelled:
                    guard successorEnvelope.state == .cancelled
                        || successorEnvelope.state == .superseded else {
                        throw ActivityContractFailureV2.unsupportedClaim
                    }
                }
            }
            guard let installationReferenceContext else {
                if !installationTaskResults.flatMap(\.evidenceReferences).isEmpty
                    || !(installationAsBuiltSnapshot?.placementReferences.isEmpty ?? true) {
                    throw ActivityContractFailureV2.missingReference
                }
                return try validateCloseoutResolution(closeoutContext)
            }
            try installationReferenceContext.validate(self)
        } else {
            guard installationTaskHeads.headsByTaskID.isEmpty,
                  currentInstallationBasis == nil else {
                throw ActivityContractFailureV2.invalidValue
            }
            let resolvedBasis = punchReviewBasisSnapshot ?? currentPunchBasis
            if let resolvedBasis {
                guard case let .punchReview(reference)? = successorEnvelope.currentBasisReference else {
                    throw ActivityContractFailureV2.missingReference
                }
                if let punchReviewBasisSnapshot, let currentPunchBasis {
                    try punchReviewBasisSnapshot.validateSuccessor(of: currentPunchBasis)
                }
                try reference.validate(resolvedBasis)
                guard let workflowReleaseContext else { throw ActivityContractFailureV2.missingReference }
                let isStarting = predecessorEnvelope?.startedAt == nil && successorEnvelope.startedAt != nil
                try workflowReleaseContext.validate(
                    expectedReference: resolvedBasis.workflowReleaseReference,
                    forStart: isStarting
                )
                if successorEnvelope.state == .ready || successorEnvelope.state == .inProgress {
                    guard successorEnvelope.readinessPolicy == workflowReleaseContext.readinessPolicy else {
                        throw ActivityContractFailureV2.missingReference
                    }
                }
            } else {
                guard successorEnvelope.currentBasisReference == nil,
                      case nil = workflowReleaseContext,
                      successorEnvelope.punchReviewCloseout == nil,
                      successorEnvelope.state == .draft || successorEnvelope.state == .preflightRequired else {
                    throw ActivityContractFailureV2.missingReference
                }
            }
            guard installationReferenceContext == nil else {
                throw ActivityContractFailureV2.invalidValue
            }
        }
        try validateCloseoutResolution(closeoutContext)
    }

    private func validateCloseoutResolution(
        _ closeoutContext: ActivityCloseoutResolutionContextV2?
    ) throws {
        if successorEnvelope.installationCloseout != nil || successorEnvelope.punchReviewCloseout != nil{
            guard let closeoutContext else{throw ActivityContractFailureV2.missingReference}
            try closeoutContext.validate(successorEnvelope)
        }else{guard closeoutContext==nil else{throw ActivityContractFailureV2.invalidValue}}
    }

    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, workspaceID: workspaceID, expectedRevision: expectedRevision,
              mutationID: mutationID, predecessorEnvelope: predecessorEnvelope,
              successorEnvelope: successorEnvelope, transition: transition,
              completedSnapshotReference: completedSnapshotReference,
              installationBasisSnapshot: installationBasisSnapshot,
              installationTaskResults: installationTaskResults,
              installationAsBuiltSnapshot: installationAsBuiltSnapshot,
              punchReviewBasisSnapshot: punchReviewBasisSnapshot)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1
        let mutationID: MutationIDV1; let predecessorEnvelope: ActivitySessionEnvelopeV2?
        let successorEnvelope: ActivitySessionEnvelopeV2; let transition: ActivityStateTransitionV2?
        let completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1?
        let installationBasisSnapshot: InstallationBasisSnapshotV1?
        let installationTaskResults: [InstallationTaskResultV1]
        let installationAsBuiltSnapshot: InstallationAsBuiltSnapshotV1?
        let punchReviewBasisSnapshot: PunchReviewBasisSnapshotV1?
    }
}

// MARK: - Independent contract invalidation and NONPERSISTENT receipts

enum ActivityContractInvalidationAxisV1:String,Codable,CaseIterable,Hashable,Sendable{
    case shared="SHARED",installation="INSTALLATION",punch="PUNCH"
}
struct ActivityContractInvalidationTokenV1:Codable,Equatable,Hashable,Sendable{
    let axis:ActivityContractInvalidationAxisV1;let contractSHA256:String
    init(axis:ActivityContractInvalidationAxisV1,contractSHA256:String)throws{guard ActivityContractValidationV2.digest(contractSHA256)
        else{throw ActivityContractFailureV2.invalidDigest};self.axis=axis;self.contractSHA256=contractSHA256}
}
enum ActivityContractConformancePersistenceV1:String,Codable,Hashable,Sendable{case nonpersistent="NONPERSISTENT"}

struct SharedActivityEnvelopeReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let persistence:ActivityContractConformancePersistenceV1
    let sharedContractSHA256:String;let receiptSHA256:String
    init(sharedContractSHA256:String)throws{let basis=Basis(schemaVersion:Self.schemaVersion,persistence:.nonpersistent,
        sharedContractSHA256:sharedContractSHA256);schemaVersion=Self.schemaVersion;persistence = .nonpersistent
        self.sharedContractSHA256=sharedContractSHA256;receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{guard schemaVersion==Self.schemaVersion,persistence == .nonpersistent,
        ActivityContractValidationV2.digest(sharedContractSHA256),receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))
        else{throw ActivityContractFailureV2.invalidDigest}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,persistence:persistence,sharedContractSHA256:sharedContractSHA256)}
    private struct Basis:Codable{let schemaVersion:Int;let persistence:ActivityContractConformancePersistenceV1;let sharedContractSHA256:String}
}
struct InstallationActivityContractReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let persistence:ActivityContractConformancePersistenceV1
    let sharedContractSHA256:String;let installationContractSHA256:String;let noPlanFallbackSHA256:String;let receiptSHA256:String
    init(sharedContractSHA256:String,installationContractSHA256:String,noPlanFallbackSHA256:String)throws{
        let basis=Basis(schemaVersion:Self.schemaVersion,persistence:.nonpersistent,sharedContractSHA256:sharedContractSHA256,
            installationContractSHA256:installationContractSHA256,noPlanFallbackSHA256:noPlanFallbackSHA256)
        schemaVersion=Self.schemaVersion;persistence = .nonpersistent;self.sharedContractSHA256=sharedContractSHA256
        self.installationContractSHA256=installationContractSHA256;self.noPlanFallbackSHA256=noPlanFallbackSHA256
        receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{guard schemaVersion==Self.schemaVersion,persistence == .nonpersistent,
        [sharedContractSHA256,installationContractSHA256,noPlanFallbackSHA256].allSatisfy(ActivityContractValidationV2.digest),
        receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidDigest}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,persistence:persistence,sharedContractSHA256:sharedContractSHA256,
        installationContractSHA256:installationContractSHA256,noPlanFallbackSHA256:noPlanFallbackSHA256)}
    private struct Basis:Codable{let schemaVersion:Int;let persistence:ActivityContractConformancePersistenceV1
        let sharedContractSHA256:String;let installationContractSHA256:String;let noPlanFallbackSHA256:String}
}
struct PunchActivityContractReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let persistence:ActivityContractConformancePersistenceV1
    let sharedContractSHA256:String;let punchContractSHA256:String;let noPlanFallbackSHA256:String;let receiptSHA256:String
    init(sharedContractSHA256:String,punchContractSHA256:String,noPlanFallbackSHA256:String)throws{
        let basis=Basis(schemaVersion:Self.schemaVersion,persistence:.nonpersistent,sharedContractSHA256:sharedContractSHA256,
            punchContractSHA256:punchContractSHA256,noPlanFallbackSHA256:noPlanFallbackSHA256)
        schemaVersion=Self.schemaVersion;persistence = .nonpersistent;self.sharedContractSHA256=sharedContractSHA256
        self.punchContractSHA256=punchContractSHA256;self.noPlanFallbackSHA256=noPlanFallbackSHA256
        receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(basis);try validate()}
    func validate()throws{guard schemaVersion==Self.schemaVersion,persistence == .nonpersistent,
        [sharedContractSHA256,punchContractSHA256,noPlanFallbackSHA256].allSatisfy(ActivityContractValidationV2.digest),
        receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw ActivityContractFailureV2.invalidDigest}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,persistence:persistence,sharedContractSHA256:sharedContractSHA256,
        punchContractSHA256:punchContractSHA256,noPlanFallbackSHA256:noPlanFallbackSHA256)}
    private struct Basis:Codable{let schemaVersion:Int;let persistence:ActivityContractConformancePersistenceV1
        let sharedContractSHA256:String;let punchContractSHA256:String;let noPlanFallbackSHA256:String}
}

enum ActivityContractPersistenceEnrollmentV2 {
    static let persistentFamilies = ["ActivitySessionEnvelopeV2", "ActivityStateTransitionV2", "CompletedActivitySnapshotV2",
                                     "InstallationTaskResultV1", "InstallationAsBuiltSnapshotV1", "PunchReviewBasisSnapshotV1"]
    static let nonpersistentFamilies = ["SharedActivityEnvelopeReceiptV1", "InstallationActivityContractReceiptV1",
                                        "PunchActivityContractReceiptV1", "NoPlanFallbackV1"]
    static let usesSoleWorkspaceWriter = true
    static let inspectionNamedCanonicalStorageForbidden = true
    static let planOrScanProviderRequired = false
    static let completionClaimsCommissioningComplianceApprovalOrCertification = false
}

// MARK: - Installation workflow projections (nonpersistent)

enum InstallationWorkflowFailureV1: Error, Equatable, Sendable {
    case invalidContext
    case blockedReadiness
    case invalidCommand
    case unknownTask
    case incompleteRequiredTask
    case divergentAsBuilt
    case unavailableCapability
}

enum InstallationOptionalCapabilityDispositionV1: String, Codable, CaseIterable, Sendable {
    case available = "AVAILABLE"
    case manualFallback = "MANUAL_FALLBACK"
    case unavailable = "UNAVAILABLE"
}

/// Typed optional C19 input. Absence never implies a plan exists.
struct InstallationPlanCapabilityV1: Equatable, Sendable {
    static let providerID = "V23_P03_C19_INSTALLATION_PLAN_REFERENCE"
    static let consumerID = "V23_P04_C33"
    static let capabilityID: CapabilityIDV1 = .filesAndShare
    let disposition: InstallationOptionalCapabilityDispositionV1
    let planReference: InstallationPlanReferenceV1?
    let noPlanFallback: NoPlanFallbackV1?
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1?

    init(disposition: InstallationOptionalCapabilityDispositionV1,
         planReference: InstallationPlanReferenceV1? = nil,
         noPlanFallback: NoPlanFallbackV1? = nil,
         availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1? = nil) throws {
        self.disposition = disposition; self.planReference = planReference
        self.noPlanFallback = noPlanFallback; self.availabilityReceipt = availabilityReceipt
        try validate()
    }

    func validate() throws {
        try planReference?.validate(); try noPlanFallback?.validate(); try availabilityReceipt?.validate()
        if let availabilityReceipt {
            guard availabilityReceipt.providerID == Self.providerID,
                  availabilityReceipt.consumerID == Self.consumerID,
                  availabilityReceipt.capabilityID == Self.capabilityID,
                  (disposition == .available) == (availabilityReceipt.availabilityReason == .available) else {
                throw InstallationWorkflowFailureV1.unavailableCapability
            }
        }
        switch disposition {
        case .available:
            guard planReference != nil, noPlanFallback == nil else { throw InstallationWorkflowFailureV1.invalidContext }
        case .manualFallback:
            guard planReference == nil, noPlanFallback != nil else { throw InstallationWorkflowFailureV1.invalidContext }
        case .unavailable:
            guard planReference == nil, noPlanFallback != nil, availabilityReceipt != nil else {
                throw InstallationWorkflowFailureV1.invalidContext
            }
        }
    }
}

/// Typed optional C21 input. Absence never fabricates a successful scan.
struct InstallationScanCapabilityV1: Equatable, Sendable {
    static let providerID = "V23_P04_C21_INSTALLATION_SCAN_ENTRY"
    static let consumerID = "V23_P04_C33"
    static let capabilityID: CapabilityIDV1 = .camera
    let disposition: InstallationOptionalCapabilityDispositionV1
    let scanReceipt: InstallationScanEntryReceiptV1?
    let manualFallback: ManualLookupFallbackV1?
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1?

    init(disposition: InstallationOptionalCapabilityDispositionV1,
         scanReceipt: InstallationScanEntryReceiptV1? = nil,
         manualFallback: ManualLookupFallbackV1? = nil,
         availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1? = nil) throws {
        self.disposition = disposition; self.scanReceipt = scanReceipt
        self.manualFallback = manualFallback; self.availabilityReceipt = availabilityReceipt
        try validate()
    }

    func validate() throws {
        try manualFallback?.validateIntrinsic(); try availabilityReceipt?.validate()
        if let availabilityReceipt {
            guard availabilityReceipt.providerID == Self.providerID,
                  availabilityReceipt.consumerID == Self.consumerID,
                  availabilityReceipt.capabilityID == Self.capabilityID,
                  (disposition == .available) == (availabilityReceipt.availabilityReason == .available) else {
                throw InstallationWorkflowFailureV1.unavailableCapability
            }
        }
        switch disposition {
        case .available:
            guard scanReceipt != nil, manualFallback == nil else { throw InstallationWorkflowFailureV1.invalidContext }
        case .manualFallback:
            guard scanReceipt == nil, manualFallback != nil else { throw InstallationWorkflowFailureV1.invalidContext }
        case .unavailable:
            guard scanReceipt == nil, manualFallback != nil, availabilityReceipt != nil else {
                throw InstallationWorkflowFailureV1.invalidContext
            }
        }
    }
}

struct InstallationReadinessBlockerV1: Codable, Equatable, Comparable, Sendable {
    let facetID: String
    let kind: ActivityReadinessFacetKindV1
    let disposition: ActivityReadinessDispositionV1
    let reason: String

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.facetID < rhs.facetID }
}

struct InstallationTaskProjectionV1: Equatable, Sendable {
    let definition: InstallationTaskDefinitionV1
    let currentResult: InstallationTaskResultV1?
    var isTerminal: Bool {
        guard let currentResult else { return false }
        return ![.notStarted, .inProgress].contains(currentResult.outcome)
    }
}

enum InstallationCloseoutActionV1: String, Codable, CaseIterable, Sendable {
    case recordFieldComplete = "RECORD_FIELD_COMPLETE"
    case submitForReview = "SUBMIT_FOR_REVIEW"
    case finalizeRecordedCloseout = "FINALIZE_RECORDED_CLOSEOUT"
}

/// Renderer-neutral, deterministic report input. The sole report renderer may
/// consume this value; this card does not create a renderer or report store.
struct InstallationReportProjectionV1: Codable, Equatable, Sendable {
    let activityID: UUID
    let envelopeSHA256: String
    let state: ActivityStateV2
    let taskResultSHA256s: [String]
    let variationSHA256s: [String]
    let asBuiltSnapshotSHA256: String?
    let closeoutSHA256: String?
    let claimsSafe: Bool
    let claimsCompliant: Bool
    let claimsPermitted: Bool
    let claimsCommissioned: Bool
    let claimsApproved: Bool
    let claimsInService: Bool
    let projectionSHA256: String

    init(envelope: ActivitySessionEnvelopeV2, taskResults: [InstallationTaskResultV1],
         asBuiltSnapshot: InstallationAsBuiltSnapshotV1?) throws {
        try envelope.validateForRead(); try taskResults.forEach { try $0.validate() }
        try asBuiltSnapshot?.validate()
        guard envelope.kind == .installation,
              taskResults.allSatisfy({ $0.workspaceID == envelope.workspaceID && $0.activityID == envelope.activityID }),
              Set(taskResults.map(\.taskID)).count == taskResults.count,
              asBuiltSnapshot.map({ $0.workspaceID == envelope.workspaceID && $0.activityID == envelope.activityID }) ?? true,
              envelope.installationCloseout.map({ closeout in
                  asBuiltSnapshot.map({ $0.snapshotSHA256 == closeout.asBuiltSnapshotSHA256 }) ?? false
              }) ?? true else {
            throw InstallationWorkflowFailureV1.invalidContext
        }
        let resultSHA256s = taskResults.sorted().map(\.resultSHA256)
        let variationSHA256s = envelope.variations.map(\.variationSHA256)
        let basis = Basis(activityID: envelope.activityID, envelopeSHA256: envelope.envelopeSHA256,
                          state: envelope.state, taskResultSHA256s: resultSHA256s,
                          variationSHA256s: variationSHA256s,
                          asBuiltSnapshotSHA256: asBuiltSnapshot?.snapshotSHA256,
                          closeoutSHA256: envelope.installationCloseout?.closeoutSHA256,
                          claimsSafe: false, claimsCompliant: false, claimsPermitted: false,
                          claimsCommissioned: false, claimsApproved: false, claimsInService: false)
        activityID = envelope.activityID; envelopeSHA256 = envelope.envelopeSHA256; state = envelope.state
        taskResultSHA256s = resultSHA256s; self.variationSHA256s = variationSHA256s
        asBuiltSnapshotSHA256 = asBuiltSnapshot?.snapshotSHA256
        closeoutSHA256 = envelope.installationCloseout?.closeoutSHA256
        claimsSafe = false; claimsCompliant = false; claimsPermitted = false
        claimsCommissioned = false; claimsApproved = false; claimsInService = false
        projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
    }

    private struct Basis: Codable {
        let activityID: UUID; let envelopeSHA256: String; let state: ActivityStateV2
        let taskResultSHA256s: [String]; let variationSHA256s: [String]
        let asBuiltSnapshotSHA256: String?; let closeoutSHA256: String?
        let claimsSafe: Bool; let claimsCompliant: Bool; let claimsPermitted: Bool
        let claimsCommissioned: Bool; let claimsApproved: Bool; let claimsInService: Bool
    }
}

enum InstallationReportReadinessV1: String, Codable, CaseIterable, Sendable {
    case fieldWorkIncomplete = "FIELD_WORK_INCOMPLETE"
    case reviewRequired = "REVIEW_REQUIRED"
    case readyForExistingRenderer = "READY_FOR_EXISTING_RENDERER"
}

struct InstallationWorkflowProjectionV1: Equatable, Sendable {
    let envelope: ActivitySessionEnvelopeV2
    let blockers: [InstallationReadinessBlockerV1]
    let tasks: [InstallationTaskProjectionV1]
    let nextTaskID: String?
    let planDisposition: InstallationOptionalCapabilityDispositionV1
    let scanDisposition: InstallationOptionalCapabilityDispositionV1
    let canStart: Bool
    let canCloseout: Bool
    let nextCloseoutAction: InstallationCloseoutActionV1?
    let reportReadiness: InstallationReportReadinessV1
    let reportReady: Bool
    let closeoutRecorded: Bool
    let report: InstallationReportProjectionV1
}

enum InstallationWorkflowProjectionBoundaryV1 {
    static let persistentFamilyAdded = false
    static let schemaOrStoreAdded = false
    static let writerOrBackendAdded = false
    static let reportRendererAdded = false
    static let parallelKernelAdded = false
    static let optionalPlanOrScanTruthFabricated = false
    static let completionClaimsSafetyCompliancePermitCommissioningApprovalOrService = false
    static let adoptsPhase10 = false
}

// MARK: - Standalone punch-review workflow projections

enum PunchReviewWorkflowFailureV1: Error, Equatable, Sendable {
    case invalidContext
    case invalidCommand
    case blockedReadiness
    case unknownScopeItem
    case duplicateDecision
    case staleOrWrongAsset
    case conflictingRecheck
    case unresolvedCloseoutCount
    case unavailableCapability
}

enum PunchReviewPlanDispositionV1: String, Codable, CaseIterable, Sendable {
    case available = "AVAILABLE"
    case manualFallback = "MANUAL_FALLBACK"
    case externalLocal = "EXTERNAL_LOCAL"
    case unavailable = "UNAVAILABLE"
}

/// Typed optional P03-C19 input. A missing provider is explicit and never
/// prevents a standalone review from using its recorded no-plan fallback.
struct PunchReviewPlanCapabilityV1: Equatable, Sendable {
    static let providerID = "V23_P03_C19_PUNCH_PLAN_REFERENCE"
    static let consumerID = "V23_P04_C34"
    static let capabilityID: CapabilityIDV1 = .filesAndShare
    let disposition: PunchReviewPlanDispositionV1
    let planReference: PunchPlanReferenceV1?
    let noPlanFallback: NoPlanFallbackV1?
    let externalReference: ActivityExternalReferenceV1?
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1?

    init(disposition: PunchReviewPlanDispositionV1,
         planReference: PunchPlanReferenceV1? = nil,
         noPlanFallback: NoPlanFallbackV1? = nil,
         externalReference: ActivityExternalReferenceV1? = nil,
         availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1? = nil) throws {
        self.disposition = disposition; self.planReference = planReference
        self.noPlanFallback = noPlanFallback; self.externalReference = externalReference
        self.availabilityReceipt = availabilityReceipt
        try validate()
    }

    func validate() throws {
        try planReference?.validate(); try noPlanFallback?.validate()
        try externalReference?.validate(); try availabilityReceipt?.validate()
        if let availabilityReceipt {
            guard availabilityReceipt.providerID == Self.providerID,
                  availabilityReceipt.consumerID == Self.consumerID,
                  availabilityReceipt.capabilityID == Self.capabilityID,
                  (disposition == .available)
                    == (availabilityReceipt.availabilityReason == .available) else {
                throw PunchReviewWorkflowFailureV1.unavailableCapability
            }
        }
        switch disposition {
        case .available:
            guard planReference != nil, noPlanFallback == nil, externalReference == nil else {
                throw PunchReviewWorkflowFailureV1.invalidContext
            }
        case .manualFallback:
            guard planReference == nil, noPlanFallback != nil, externalReference == nil else {
                throw PunchReviewWorkflowFailureV1.invalidContext
            }
        case .externalLocal:
            guard planReference == nil, noPlanFallback == nil, externalReference != nil else {
                throw PunchReviewWorkflowFailureV1.invalidContext
            }
        case .unavailable:
            guard planReference == nil, noPlanFallback != nil, externalReference == nil,
                  availabilityReceipt != nil else {
                throw PunchReviewWorkflowFailureV1.invalidContext
            }
        }
    }
}

/// Optional installation truth is read-only and fully resolved. Its absence is
/// a first-class standalone state and never blocks punch-review start.
struct PunchReviewInstallationSnapshotContextV1: Equatable, Sendable {
    let envelope: ActivitySessionEnvelopeV2
    let asBuiltSnapshot: InstallationAsBuiltSnapshotV1
    let completedSnapshot: CompletedActivitySnapshotV2

    init(envelope: ActivitySessionEnvelopeV2,
         asBuiltSnapshot: InstallationAsBuiltSnapshotV1,
         completedSnapshot: CompletedActivitySnapshotV2) throws {
        self.envelope = envelope; self.asBuiltSnapshot = asBuiltSnapshot
        self.completedSnapshot = completedSnapshot
        try validate()
    }

    func validate() throws {
        try envelope.validateForRead(); try asBuiltSnapshot.validate(); try completedSnapshot.validate()
        guard envelope.kind == .installation, envelope.state == .finalized,
              asBuiltSnapshot.workspaceID == envelope.workspaceID,
              asBuiltSnapshot.activityID == envelope.activityID,
              let closeout = envelope.installationCloseout,
              closeout.asBuiltSnapshotSHA256 == asBuiltSnapshot.snapshotSHA256,
              let reference = envelope.completedSnapshotReference,
              reference.workspaceID == envelope.workspaceID,
              reference.activityID == envelope.activityID,
              reference.sourceWorkspaceID == envelope.workspaceID,
              reference.sourceActivityID == envelope.activityID,
              reference.sourceSubjectID == envelope.subjectID,
              reference.sourceCloseoutSHA256 == closeout.closeoutSHA256,
              reference.targetCloseoutSHA256 == closeout.closeoutSHA256 else {
            throw PunchReviewWorkflowFailureV1.invalidContext
        }
        try reference.validate(snapshot: completedSnapshot)
    }
}

struct PunchReviewReadinessBlockerV1: Codable, Equatable, Comparable, Sendable {
    let facetID: String
    let kind: ActivityReadinessFacetKindV1
    let disposition: ActivityReadinessDispositionV1
    let reason: String
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.facetID < rhs.facetID }
}

struct PunchReviewScopeProjectionV1: Equatable, Sendable {
    let definition: PunchReviewScopeItemV1
    let decision: PunchItemProjectionV1?
    let unresolvedFindingCount: Int
    let resolvedFindingCount: Int
    var hasRecordedDecision: Bool { decision != nil }
}

enum PunchReviewCloseoutActionV1: String, Codable, CaseIterable, Sendable {
    case recordFieldComplete = "RECORD_FIELD_COMPLETE"
    case submitForReview = "SUBMIT_FOR_REVIEW"
    case finalizeRecordedCloseout = "FINALIZE_RECORDED_CLOSEOUT"
}

enum PunchReviewReportReadinessV1: String, Codable, CaseIterable, Sendable {
    case reviewIncomplete = "REVIEW_INCOMPLETE"
    case reviewRequired = "REVIEW_REQUIRED"
    case readyForExistingRenderer = "READY_FOR_EXISTING_RENDERER"
}

/// Renderer-neutral input only. Every approval, compliance, safety, delivery,
/// and identity claim stays false regardless of closeout disposition.
struct PunchReviewReportProjectionV1: Codable, Equatable, Sendable {
    let activityID: UUID
    let envelopeSHA256: String
    let state: ActivityStateV2
    let basisSHA256: String
    let scopeItemIDs: [String]
    let findingSHA256s: [String]
    let correctiveActionSHA256s: [String]
    let verifiedRecheckSHA256s: [String]
    let unresolvedScopeCount: Int
    let unresolvedFindingCount: Int
    let resolvedFindingCount: Int
    let closeoutSHA256: String?
    let installationSnapshotSHA256: String?
    let claimsSafe: Bool
    let claimsCompliant: Bool
    let claimsApproved: Bool
    let claimsAccepted: Bool
    let claimsDelivered: Bool
    let claimsIdentityVerified: Bool
    let projectionSHA256: String

    init(activityID: UUID, envelopeSHA256: String, state: ActivityStateV2,
         basisSHA256: String, scopeItemIDs: [String], findingSHA256s: [String],
         correctiveActionSHA256s: [String], verifiedRecheckSHA256s: [String],
         unresolvedScopeCount: Int, unresolvedFindingCount: Int,
         resolvedFindingCount: Int, closeoutSHA256: String?,
         installationSnapshotSHA256: String?) throws {
        let basis = Basis(activityID:activityID,envelopeSHA256:envelopeSHA256,state:state,
            basisSHA256:basisSHA256,scopeItemIDs:scopeItemIDs,findingSHA256s:findingSHA256s,
            correctiveActionSHA256s:correctiveActionSHA256s,
            verifiedRecheckSHA256s:verifiedRecheckSHA256s,
            unresolvedScopeCount:unresolvedScopeCount,unresolvedFindingCount:unresolvedFindingCount,
            resolvedFindingCount:resolvedFindingCount,closeoutSHA256:closeoutSHA256,
            installationSnapshotSHA256:installationSnapshotSHA256,
            claimsSafe:false,claimsCompliant:false,claimsApproved:false,claimsAccepted:false,
            claimsDelivered:false,claimsIdentityVerified:false)
        self.activityID=activityID;self.envelopeSHA256=envelopeSHA256;self.state=state
        self.basisSHA256=basisSHA256;self.scopeItemIDs=scopeItemIDs
        self.findingSHA256s=findingSHA256s;self.correctiveActionSHA256s=correctiveActionSHA256s
        self.verifiedRecheckSHA256s=verifiedRecheckSHA256s
        self.unresolvedScopeCount=unresolvedScopeCount;self.unresolvedFindingCount=unresolvedFindingCount
        self.resolvedFindingCount=resolvedFindingCount;self.closeoutSHA256=closeoutSHA256
        self.installationSnapshotSHA256=installationSnapshotSHA256
        claimsSafe=false;claimsCompliant=false;claimsApproved=false;claimsAccepted=false
        claimsDelivered=false;claimsIdentityVerified=false
        projectionSHA256=try WorkspaceMutationCanonicalV1.sha256(basis)
    }
    private struct Basis:Codable{let activityID:UUID;let envelopeSHA256:String;let state:ActivityStateV2
        let basisSHA256:String;let scopeItemIDs:[String];let findingSHA256s:[String]
        let correctiveActionSHA256s:[String];let verifiedRecheckSHA256s:[String]
        let unresolvedScopeCount:Int;let unresolvedFindingCount:Int;let resolvedFindingCount:Int
        let closeoutSHA256:String?;let installationSnapshotSHA256:String?
        let claimsSafe:Bool;let claimsCompliant:Bool;let claimsApproved:Bool;let claimsAccepted:Bool
        let claimsDelivered:Bool;let claimsIdentityVerified:Bool}
}

struct PunchReviewWorkflowProjectionV1: Equatable, Sendable {
    let envelope: ActivitySessionEnvelopeV2
    let blockers: [PunchReviewReadinessBlockerV1]
    let scope: [PunchReviewScopeProjectionV1]
    let nextScopeItemID: String?
    let planDisposition: PunchReviewPlanDispositionV1
    let installationSnapshotAvailable: Bool
    let canStart: Bool
    let canCloseout: Bool
    let nextCloseoutAction: PunchReviewCloseoutActionV1?
    let reportReadiness: PunchReviewReportReadinessV1
    let reportReady: Bool
    let report: PunchReviewReportProjectionV1
}

enum PunchReviewWorkflowProjectionBoundaryV1 {
    static let persistentFamilyAdded = false
    static let schemaStoreWriterOrBackendAdded = false
    static let reportRendererAdded = false
    static let installationRequiredForStart = false
    static let installationTruthInferred = false
    static let claimsComplianceApprovalSafetyDeliveryOrIdentity = false
}
