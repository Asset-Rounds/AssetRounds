import Foundation

enum ReinspectionExceptionFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, corruptDigest, duplicateIdentity
    case staleRevision, wrongWorkspace, missingSource, forgedSource, arithmeticOverflow
    case attestationNotAllowed, receiptMismatch
}

enum ReinspectionExceptionLimitsV1 {
    static let maximumPlanItems = 512
    static let maximumQueueItems = 512
    static let maximumQueryResults = 256
    static let maximumIdentifierBytes = 256
    static let maximumReasons = 7
}

enum ReinspectionExceptionLifecycleV1 {
    static let canonicalWriter = "WorkspaceWriterV1"
    static let writersPerWorkspaceGeneration = 1
    static let createsSecondStore = false
    static let canonicalPersistence = true
    static let queueItemsArePersistent = false
    static let queueIsRebuiltFromRegisteredCanonicalSources = true
    static let acknowledgementMutatesCanonicalSource = false
    static let priorEvidenceCreatesFreshObservation = false
    static let canonicalCommitRequiresResolverValidation = true
}

private enum ReinspectionExceptionValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw ReinspectionExceptionFailureV1.invalidValue } }
    static func revision(_ value: UInt64) throws { guard value > 0 else { throw ReinspectionExceptionFailureV1.staleRevision } }
    static func digest(_ value: String) throws {
        guard value == value.lowercased(), KernelCanonicalHashV1.validSHA256(value) else { throw ReinspectionExceptionFailureV1.corruptDigest }
    }
    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= ReinspectionExceptionLimitsV1.maximumIdentifierBytes,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.:".unicodeScalars.contains(scalar))
              }) else {
            throw ReinspectionExceptionFailureV1.invalidValue
        }
    }
    static func instant(_ value: Date) throws { guard value.timeIntervalSinceReferenceDate.isFinite else { throw ReinspectionExceptionFailureV1.invalidValue } }
    static func hash<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
}

enum ReinspectionSourceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case requirement = "REQUIREMENT"
    case inspectionItem = "INSPECTION_ITEM"
    case finding = "FINDING"
    case correctiveAction = "CORRECTIVE_ACTION"
}

struct ReinspectionSourceIdentityV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let kind: ReinspectionSourceKindV1
    let sourceID: String
    init(workspaceID: WorkspaceID, kind: ReinspectionSourceKindV1, sourceID: String) throws {
        self.workspaceID = workspaceID; self.kind = kind; self.sourceID = sourceID; try validate()
    }
    func validate() throws { try ReinspectionExceptionValidationV1.token(sourceID) }
    var canonicalKey: String { "\(workspaceID.rawValue.uuidString.lowercased())|\(kind.rawValue)|\(sourceID)" }
}

struct ReinspectionSourceSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let identity: ReinspectionSourceIdentityV1
    let revision: UInt64
    let sourceSHA256: String
    let evidenceSHA256: String
    let snapshotSHA256: String
    init(identity: ReinspectionSourceIdentityV1, revision: UInt64, sourceSHA256: String, evidenceSHA256: String) throws {
        schemaVersion = Self.schemaVersion; self.identity = identity; self.revision = revision
        self.sourceSHA256 = sourceSHA256; self.evidenceSHA256 = evidenceSHA256
        snapshotSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, identity: identity,
            revision: revision, sourceSHA256: sourceSHA256, evidenceSHA256: evidenceSHA256)); try validate()
    }
    func validate() throws {
        try identity.validate(); try ReinspectionExceptionValidationV1.revision(revision)
        try ReinspectionExceptionValidationV1.digest(sourceSHA256); try ReinspectionExceptionValidationV1.digest(evidenceSHA256)
        guard schemaVersion == Self.schemaVersion, snapshotSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else {
            throw ReinspectionExceptionFailureV1.forgedSource
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, identity: identity, revision: revision, sourceSHA256: sourceSHA256, evidenceSHA256: evidenceSHA256) }
    private struct Basis: Codable { let schemaVersion: Int; let identity: ReinspectionSourceIdentityV1; let revision: UInt64; let sourceSHA256: String; let evidenceSHA256: String }
}

protocol ReinspectionCanonicalSourceResolvingV1 {
    func resolveReinspectionSource(_ identity: ReinspectionSourceIdentityV1, revision: UInt64) throws -> ReinspectionSourceSnapshotV1
}

extension ReinspectionSourceSnapshotV1 {
    func validateResolved(by resolver: any ReinspectionCanonicalSourceResolvingV1) throws {
        try validate(); let resolved = try resolver.resolveReinspectionSource(identity, revision: revision)
        try resolved.validate()
        guard resolved == self else { throw ReinspectionExceptionFailureV1.staleRevision }
    }
}

enum ReinspectionSelectionReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case changed = "CHANGED", open = "OPEN", expired = "EXPIRED", uncertain = "UNCERTAIN"
    case policy = "POLICY", evidence = "EVIDENCE", fullReview = "FULL_REVIEW"
}

enum ReinspectionCompletionRequirementV1: String, CaseIterable, Codable, Hashable, Sendable {
    case freshEvidence = "FRESH_EVIDENCE"
    case currentObservationOrAttestation = "CURRENT_OBSERVATION_OR_ATTESTATION"
    case fullReview = "FULL_REVIEW"
}

struct ReinspectionPlanItemV1: Codable, Equatable, Sendable {
    let itemID: UUID
    let prior: ReinspectionSourceSnapshotV1
    let current: ReinspectionSourceSnapshotV1
    let reasons: [ReinspectionSelectionReasonV1]
    let completionRequirement: ReinspectionCompletionRequirementV1
    init(itemID: UUID, prior: ReinspectionSourceSnapshotV1, current: ReinspectionSourceSnapshotV1,
         reasons: [ReinspectionSelectionReasonV1], completionRequirement: ReinspectionCompletionRequirementV1) throws {
        self.itemID = itemID; self.prior = prior; self.current = current; self.reasons = reasons
        self.completionRequirement = completionRequirement; try validate()
    }
    func validate() throws {
        try ReinspectionExceptionValidationV1.id(itemID); try prior.validate(); try current.validate()
        let ordered = reasons.sorted { $0.rawValue < $1.rawValue }
        guard prior.identity == current.identity, prior.identity.workspaceID == current.identity.workspaceID,
              prior.revision <= current.revision, !reasons.isEmpty,
              reasons.count <= ReinspectionExceptionLimitsV1.maximumReasons,
              reasons == ordered, Set(reasons).count == reasons.count else { throw ReinspectionExceptionFailureV1.invalidValue }
        if reasons.contains(.fullReview) { guard completionRequirement == .fullReview else { throw ReinspectionExceptionFailureV1.invalidValue } }
        if reasons.contains(.evidence) || reasons.contains(.expired) || reasons.contains(.open) {
            guard completionRequirement != .currentObservationOrAttestation else { throw ReinspectionExceptionFailureV1.attestationNotAllowed }
        }
        guard prior.revision != current.revision || prior.sourceSHA256 != current.sourceSHA256 || prior.evidenceSHA256 != current.evidenceSHA256 || reasons == [.policy] || reasons == [.fullReview] else {
            throw ReinspectionExceptionFailureV1.staleRevision
        }
    }
}

struct ReinspectionPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let planEventID: UUID; let planID: UUID; let workspaceID: WorkspaceID
    let revision: UInt64; let supersedesPlanEventID: UUID?; let predecessorSHA256: String?
    let policyVersion: UInt64; let policySHA256: String; let items: [ReinspectionPlanItemV1]
    let plannedBy: ActorSnapshotV1; let plannedAt: Date; let mutationID: MutationIDV1; let planSHA256: String
    init(planEventID: UUID, planID: UUID, workspaceID: WorkspaceID, revision: UInt64,
         predecessor: ReinspectionPlanV1? = nil, policyVersion: UInt64, policySHA256: String,
         items: [ReinspectionPlanItemV1], plannedBy: ActorSnapshotV1, plannedAt: Date, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.planEventID = planEventID; self.planID = planID; self.workspaceID = workspaceID
        self.revision = revision; supersedesPlanEventID = predecessor?.planEventID; predecessorSHA256 = predecessor?.planSHA256
        self.policyVersion = policyVersion; self.policySHA256 = policySHA256; self.items = items
        self.plannedBy = plannedBy; self.plannedAt = plannedAt; self.mutationID = mutationID
        planSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, planEventID: planEventID,
            planID: planID, workspaceID: workspaceID, revision: revision, supersedesPlanEventID: predecessor?.planEventID,
            predecessorSHA256: predecessor?.planSHA256, policyVersion: policyVersion, policySHA256: policySHA256,
            items: items, plannedBy: plannedBy, plannedAt: plannedAt, mutationID: mutationID)); try validate(predecessor: predecessor)
    }
    func validate() throws { try validate(predecessor: nil, requirePredecessorValue: false) }
    func validate(predecessor: ReinspectionPlanV1?) throws { try validate(predecessor: predecessor, requirePredecessorValue: true) }
    func validateResolved(predecessor: ReinspectionPlanV1? = nil,
                          by resolver: any ReinspectionCanonicalSourceResolvingV1) throws {
        if let predecessor { try validate(predecessor: predecessor) } else { try validate() }
        for item in items { try item.prior.validateResolved(by: resolver); try item.current.validateResolved(by: resolver) }
        if let predecessor { for item in predecessor.items { try item.prior.validateResolved(by: resolver); try item.current.validateResolved(by: resolver) } }
    }
    private func validate(predecessor: ReinspectionPlanV1?, requirePredecessorValue: Bool) throws {
        try ReinspectionExceptionValidationV1.id(planEventID); try ReinspectionExceptionValidationV1.id(planID)
        try ReinspectionExceptionValidationV1.revision(revision); try ReinspectionExceptionValidationV1.revision(policyVersion)
        try ReinspectionExceptionValidationV1.digest(policySHA256); try plannedBy.validate(); try ReinspectionExceptionValidationV1.instant(plannedAt)
        guard schemaVersion == Self.schemaVersion, plannedBy.workspaceID == workspaceID, !items.isEmpty,
              items.count <= ReinspectionExceptionLimitsV1.maximumPlanItems,
              items == items.sorted(by: { ($0.current.identity.canonicalKey, $0.itemID.uuidString) < ($1.current.identity.canonicalKey, $1.itemID.uuidString) }),
              Set(items.map(\.itemID)).count == items.count, Set(items.map { $0.current.identity.canonicalKey }).count == items.count,
              items.allSatisfy({ $0.current.identity.workspaceID == workspaceID }),
              planSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else { throw ReinspectionExceptionFailureV1.invalidValue }
        try items.forEach { try $0.validate() }
        if revision == 1 { guard supersedesPlanEventID == nil, predecessorSHA256 == nil, predecessor == nil else { throw ReinspectionExceptionFailureV1.staleRevision } }
        else {
            guard supersedesPlanEventID != nil, predecessorSHA256 != nil else { throw ReinspectionExceptionFailureV1.staleRevision }
            if requirePredecessorValue {
                guard let predecessor else { throw ReinspectionExceptionFailureV1.staleRevision }
                let (nextRevision, overflow) = predecessor.revision.addingReportingOverflow(1)
                guard !overflow, predecessor.workspaceID == workspaceID, predecessor.planID == planID,
                      nextRevision == revision, predecessor.planEventID == supersedesPlanEventID,
                      predecessor.planSHA256 == predecessorSHA256 else { throw ReinspectionExceptionFailureV1.staleRevision }
            }
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, planEventID: planEventID, planID: planID, workspaceID: workspaceID,
        revision: revision, supersedesPlanEventID: supersedesPlanEventID, predecessorSHA256: predecessorSHA256,
        policyVersion: policyVersion, policySHA256: policySHA256, items: items, plannedBy: plannedBy,
        plannedAt: plannedAt, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion: Int; let planEventID: UUID; let planID: UUID; let workspaceID: WorkspaceID; let revision: UInt64; let supersedesPlanEventID: UUID?; let predecessorSHA256: String?; let policyVersion: UInt64; let policySHA256: String; let items: [ReinspectionPlanItemV1]; let plannedBy: ActorSnapshotV1; let plannedAt: Date; let mutationID: MutationIDV1 }
}

enum UnchangedAttestationReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case noRelevantChangeObserved = "NO_RELEVANT_CHANGE_OBSERVED"
    case conditionObservedUnchanged = "CONDITION_OBSERVED_UNCHANGED"
}

struct UnchangedAttestationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let attestationID: UUID; let workspaceID: WorkspaceID
    let planID: UUID; let planRevision: UInt64; let planSHA256: String; let planItemID: UUID
    let prior: ReinspectionSourceSnapshotV1; let current: ReinspectionSourceSnapshotV1
    let policyVersion: UInt64; let policySHA256: String; let reason: UnchangedAttestationReasonV1
    let currentObservationBasis: ObservationBasisV1; let attestedBy: ActorSnapshotV1; let attestedAt: Date
    let mutationID: MutationIDV1; let createsFreshObservation: Bool; let attestationSHA256: String
    init(attestationID: UUID, plan: ReinspectionPlanV1, planItemID: UUID, reason: UnchangedAttestationReasonV1,
         currentObservationBasis: ObservationBasisV1, attestedBy: ActorSnapshotV1, attestedAt: Date,
         mutationID: MutationIDV1) throws {
        guard let item = plan.items.first(where: { $0.itemID == planItemID }) else { throw ReinspectionExceptionFailureV1.missingSource }
        schemaVersion = Self.schemaVersion; self.attestationID = attestationID; workspaceID = plan.workspaceID
        planID = plan.planID; planRevision = plan.revision; planSHA256 = plan.planSHA256; self.planItemID = planItemID
        prior = item.prior; current = item.current; policyVersion = plan.policyVersion; policySHA256 = plan.policySHA256
        self.reason = reason; self.currentObservationBasis = currentObservationBasis; self.attestedBy = attestedBy
        self.attestedAt = attestedAt; self.mutationID = mutationID; createsFreshObservation = false
        attestationSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, attestationID: attestationID,
            workspaceID: plan.workspaceID, planID: plan.planID, planRevision: plan.revision, planSHA256: plan.planSHA256,
            planItemID: planItemID, prior: item.prior, current: item.current, policyVersion: plan.policyVersion,
            policySHA256: plan.policySHA256, reason: reason, currentObservationBasis: currentObservationBasis,
            attestedBy: attestedBy, attestedAt: attestedAt, mutationID: mutationID, createsFreshObservation: false)); try validate(plan: plan)
    }
    func validate() throws { try validate(plan: nil) }
    func validate(plan: ReinspectionPlanV1?) throws {
        try ReinspectionExceptionValidationV1.id(attestationID); try ReinspectionExceptionValidationV1.id(planID)
        try ReinspectionExceptionValidationV1.id(planItemID); try ReinspectionExceptionValidationV1.revision(planRevision)
        try ReinspectionExceptionValidationV1.revision(policyVersion); try ReinspectionExceptionValidationV1.digest(planSHA256)
        try ReinspectionExceptionValidationV1.digest(policySHA256); try prior.validate(); try current.validate()
        try currentObservationBasis.validate(); try attestedBy.validate(); try ReinspectionExceptionValidationV1.instant(attestedAt)
        guard schemaVersion == Self.schemaVersion, prior.identity == current.identity, current.identity.workspaceID == workspaceID,
              attestedBy.workspaceID == workspaceID, currentObservationBasis.kind == .directlyObserved,
              !createsFreshObservation, attestationSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else {
            throw ReinspectionExceptionFailureV1.attestationNotAllowed
        }
        if let plan {
            try plan.validate(); guard plan.workspaceID == workspaceID, plan.planID == planID, plan.revision == planRevision,
                plan.planSHA256 == planSHA256, plan.policyVersion == policyVersion, plan.policySHA256 == policySHA256,
                let item = plan.items.first(where: { $0.itemID == planItemID }), item.prior == prior, item.current == current,
                item.completionRequirement == .currentObservationOrAttestation else { throw ReinspectionExceptionFailureV1.attestationNotAllowed }
        }
    }
    func validateResolved(plan: ReinspectionPlanV1, by resolver: any ReinspectionCanonicalSourceResolvingV1) throws {
        try validate(plan: plan); try prior.validateResolved(by: resolver); try current.validateResolved(by: resolver)
        try plan.validateResolved(by: resolver)
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, attestationID: attestationID, workspaceID: workspaceID,
        planID: planID, planRevision: planRevision, planSHA256: planSHA256, planItemID: planItemID, prior: prior,
        current: current, policyVersion: policyVersion, policySHA256: policySHA256, reason: reason,
        currentObservationBasis: currentObservationBasis, attestedBy: attestedBy, attestedAt: attestedAt,
        mutationID: mutationID, createsFreshObservation: createsFreshObservation) }
    private struct Basis: Codable { let schemaVersion: Int; let attestationID: UUID; let workspaceID: WorkspaceID; let planID: UUID; let planRevision: UInt64; let planSHA256: String; let planItemID: UUID; let prior: ReinspectionSourceSnapshotV1; let current: ReinspectionSourceSnapshotV1; let policyVersion: UInt64; let policySHA256: String; let reason: UnchangedAttestationReasonV1; let currentObservationBasis: ObservationBasisV1; let attestedBy: ActorSnapshotV1; let attestedAt: Date; let mutationID: MutationIDV1; let createsFreshObservation: Bool }
}

enum ExceptionQueueSourceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case integrityFinding = "INTEGRITY_FINDING", qualityWarning = "QUALITY_WARNING", qualityWaiver = "QUALITY_WAIVER"
    case reviewChangeRequest = "REVIEW_CHANGE_REQUEST", correctiveAction = "CORRECTIVE_ACTION"
    case workPacketCollision = "WORK_PACKET_COLLISION", replayQuarantine = "REPLAY_QUARANTINE"
    case captureInboxItem = "CAPTURE_INBOX_ITEM", relatedWorkSuggestion = "RELATED_WORK_SUGGESTION"
}
enum ExceptionQueueSeverityV1: Int, CaseIterable, Codable, Hashable, Sendable { case informational = 0, warning = 1, actionRequired = 2, blocking = 3 }
enum ExceptionQueueReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case integrity = "INTEGRITY", quality = "QUALITY", review = "REVIEW", overdue = "OVERDUE", reopened = "REOPENED"
    case collision = "COLLISION", quarantine = "QUARANTINE", unresolvedCapture = "UNRESOLVED_CAPTURE", relatedWork = "RELATED_WORK"
}
enum ExceptionQueueDeepLinkV1: String, CaseIterable, Codable, Hashable, Sendable {
    case sourceRecord = "SOURCE_RECORD", evidenceReview = "EVIDENCE_REVIEW", correctiveWork = "CORRECTIVE_WORK"
    case packetReview = "PACKET_REVIEW", replayReview = "REPLAY_REVIEW", captureInbox = "CAPTURE_INBOX", relatedWorkDecision = "RELATED_WORK_DECISION"
}

struct ExceptionQueueSourceSnapshotV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let kind: ExceptionQueueSourceKindV1; let sourceID: String
    let sourceRevision: UInt64; let sourceSHA256: String; let evidenceSHA256: String; let logicalExceptionKey: String
    let severity: ExceptionQueueSeverityV1; let reasons: [ExceptionQueueReasonV1]; let deepLink: ExceptionQueueDeepLinkV1
    init(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1, sourceID: String, sourceRevision: UInt64,
         sourceSHA256: String, evidenceSHA256: String, severity: ExceptionQueueSeverityV1,
         reasons: [ExceptionQueueReasonV1], deepLink: ExceptionQueueDeepLinkV1) throws {
        self.workspaceID = workspaceID; self.kind = kind; self.sourceID = sourceID; self.sourceRevision = sourceRevision
        self.sourceSHA256 = sourceSHA256; self.evidenceSHA256 = evidenceSHA256; self.severity = severity
        self.reasons = reasons; self.deepLink = deepLink
        logicalExceptionKey = try ReinspectionExceptionValidationV1.hash(IdentityBasis(workspaceID: workspaceID,
            kind: kind, sourceID: sourceID, sourceRevision: sourceRevision, sourceSHA256: sourceSHA256,
            evidenceSHA256: evidenceSHA256, reasons: reasons)); try validate()
    }
    func validate() throws {
        try ReinspectionExceptionValidationV1.token(sourceID); try ReinspectionExceptionValidationV1.token(logicalExceptionKey)
        try ReinspectionExceptionValidationV1.revision(sourceRevision); try ReinspectionExceptionValidationV1.digest(sourceSHA256)
        try ReinspectionExceptionValidationV1.digest(evidenceSHA256); try ReinspectionExceptionValidationV1.digest(logicalExceptionKey)
        guard !reasons.isEmpty, reasons == reasons.sorted(by: { $0.rawValue < $1.rawValue }), Set(reasons).count == reasons.count else { throw ReinspectionExceptionFailureV1.invalidValue }
        guard logicalExceptionKey == (try ReinspectionExceptionValidationV1.hash(IdentityBasis(workspaceID: workspaceID,
            kind: kind, sourceID: sourceID, sourceRevision: sourceRevision, sourceSHA256: sourceSHA256,
            evidenceSHA256: evidenceSHA256, reasons: reasons))) else { throw ReinspectionExceptionFailureV1.forgedSource }
    }
    private struct IdentityBasis: Codable { let workspaceID: WorkspaceID; let kind: ExceptionQueueSourceKindV1; let sourceID: String; let sourceRevision: UInt64; let sourceSHA256: String; let evidenceSHA256: String; let reasons: [ExceptionQueueReasonV1] }
}

protocol ExceptionQueueCanonicalSourceProvidingV1 {
    var registeredSourceKind: ExceptionQueueSourceKindV1 { get }
    func unresolvedExceptionSources(workspaceID: WorkspaceID) throws -> [ExceptionQueueSourceSnapshotV1]
}

protocol ExceptionQueueCanonicalSourceResolvingV1 {
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1,
                                     sourceID: String, revision: UInt64) throws -> ExceptionQueueSourceSnapshotV1
}

extension ExceptionQueueSourceSnapshotV1 {
    func validateResolved(by resolver: any ExceptionQueueCanonicalSourceResolvingV1) throws {
        try validate()
        let resolved = try resolver.resolveExceptionQueueSource(workspaceID: workspaceID, kind: kind,
            sourceID: sourceID, revision: sourceRevision)
        try resolved.validate(); guard resolved == self else { throw ReinspectionExceptionFailureV1.staleRevision }
    }
}

struct ExceptionQueueSourceRegistryV1: Codable, Equatable, Sendable {
    let registeredKinds: [ExceptionQueueSourceKindV1]
    init(registeredKinds: [ExceptionQueueSourceKindV1]) throws {
        self.registeredKinds = registeredKinds; try validate()
    }
    func validate() throws {
        let complete = ExceptionQueueSourceKindV1.allCases.sorted { $0.rawValue < $1.rawValue }
        guard registeredKinds == complete else { throw ReinspectionExceptionFailureV1.missingSource }
    }
}

enum ExceptionQueueAcknowledgementDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case acknowledged = "ACKNOWLEDGED", locallyResolvedProjection = "LOCALLY_RESOLVED_PROJECTION", reopened = "REOPENED"
}

struct ExceptionQueueAcknowledgementV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let acknowledgementID: UUID; let workspaceID: WorkspaceID; let logicalExceptionKey: String
    let sourceKind: ExceptionQueueSourceKindV1; let sourceID: String; let sourceRevision: UInt64; let sourceSHA256: String
    let evidenceSHA256: String
    let disposition: ExceptionQueueAcknowledgementDispositionV1; let revision: UInt64
    let supersedesAcknowledgementID: UUID?; let predecessorSHA256: String?
    let actor: ActorSnapshotV1; let recordedAt: Date; let mutationID: MutationIDV1; let acknowledgementSHA256: String
    init(acknowledgementID: UUID, source: ExceptionQueueSourceSnapshotV1,
         disposition: ExceptionQueueAcknowledgementDispositionV1, revision: UInt64,
         predecessor: ExceptionQueueAcknowledgementV1? = nil, actor: ActorSnapshotV1,
         recordedAt: Date, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.acknowledgementID = acknowledgementID; workspaceID = source.workspaceID
        logicalExceptionKey = source.logicalExceptionKey; sourceKind = source.kind; sourceID = source.sourceID
        sourceRevision = source.sourceRevision; sourceSHA256 = source.sourceSHA256; evidenceSHA256 = source.evidenceSHA256
        self.disposition = disposition; self.revision = revision
        supersedesAcknowledgementID = predecessor?.acknowledgementID; predecessorSHA256 = predecessor?.acknowledgementSHA256
        self.actor = actor; self.recordedAt = recordedAt; self.mutationID = mutationID
        acknowledgementSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion,
            acknowledgementID: acknowledgementID, workspaceID: source.workspaceID, logicalExceptionKey: source.logicalExceptionKey,
            sourceKind: source.kind, sourceID: source.sourceID, sourceRevision: source.sourceRevision,
            sourceSHA256: source.sourceSHA256, evidenceSHA256: source.evidenceSHA256, disposition: disposition, revision: revision,
            supersedesAcknowledgementID: predecessor?.acknowledgementID, predecessorSHA256: predecessor?.acknowledgementSHA256,
            actor: actor, recordedAt: recordedAt, mutationID: mutationID)); try validate(source: source, predecessor: predecessor)
    }
    func validate() throws { try validate(source: nil, predecessor: nil, requireRelated: false) }
    func validate(source: ExceptionQueueSourceSnapshotV1, predecessor: ExceptionQueueAcknowledgementV1? = nil) throws { try validate(source: source, predecessor: predecessor, requireRelated: true) }
    func validateCurrentSource(_ source: ExceptionQueueSourceSnapshotV1) throws {
        try validate(); try source.validate()
        guard source.workspaceID == workspaceID, source.logicalExceptionKey == logicalExceptionKey,
              source.kind == sourceKind, source.sourceID == sourceID, source.sourceRevision == sourceRevision,
              source.sourceSHA256 == sourceSHA256, source.evidenceSHA256 == evidenceSHA256 else { throw ReinspectionExceptionFailureV1.forgedSource }
    }
    private func validate(source: ExceptionQueueSourceSnapshotV1?, predecessor: ExceptionQueueAcknowledgementV1?, requireRelated: Bool) throws {
        try ReinspectionExceptionValidationV1.id(acknowledgementID); try ReinspectionExceptionValidationV1.token(logicalExceptionKey)
        try ReinspectionExceptionValidationV1.token(sourceID); try ReinspectionExceptionValidationV1.revision(sourceRevision)
        try ReinspectionExceptionValidationV1.digest(sourceSHA256); try ReinspectionExceptionValidationV1.digest(evidenceSHA256)
        try ReinspectionExceptionValidationV1.revision(revision)
        try actor.validate(); try ReinspectionExceptionValidationV1.instant(recordedAt)
        guard schemaVersion == Self.schemaVersion, actor.workspaceID == workspaceID,
              acknowledgementSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else { throw ReinspectionExceptionFailureV1.invalidValue }
        if revision == 1 { guard supersedesAcknowledgementID == nil, predecessorSHA256 == nil, predecessor == nil else { throw ReinspectionExceptionFailureV1.staleRevision } }
        else { guard supersedesAcknowledgementID != nil, predecessorSHA256 != nil else { throw ReinspectionExceptionFailureV1.staleRevision } }
        if requireRelated {
            guard let source, source.workspaceID == workspaceID, source.logicalExceptionKey == logicalExceptionKey,
                  source.kind == sourceKind, source.sourceID == sourceID, source.sourceRevision == sourceRevision,
                  source.sourceSHA256 == sourceSHA256, source.evidenceSHA256 == evidenceSHA256 else { throw ReinspectionExceptionFailureV1.forgedSource }
            if revision > 1 {
                guard let predecessor else { throw ReinspectionExceptionFailureV1.staleRevision }
                let (nextRevision, overflow) = predecessor.revision.addingReportingOverflow(1)
                guard !overflow, predecessor.workspaceID == workspaceID,
                predecessor.logicalExceptionKey == logicalExceptionKey, nextRevision == revision,
                predecessor.acknowledgementID == supersedesAcknowledgementID,
                predecessor.acknowledgementSHA256 == predecessorSHA256 else { throw ReinspectionExceptionFailureV1.staleRevision }
            }
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, acknowledgementID: acknowledgementID, workspaceID: workspaceID,
        logicalExceptionKey: logicalExceptionKey, sourceKind: sourceKind, sourceID: sourceID, sourceRevision: sourceRevision,
        sourceSHA256: sourceSHA256, evidenceSHA256: evidenceSHA256, disposition: disposition, revision: revision,
        supersedesAcknowledgementID: supersedesAcknowledgementID, predecessorSHA256: predecessorSHA256,
        actor: actor, recordedAt: recordedAt, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion: Int; let acknowledgementID: UUID; let workspaceID: WorkspaceID; let logicalExceptionKey: String; let sourceKind: ExceptionQueueSourceKindV1; let sourceID: String; let sourceRevision: UInt64; let sourceSHA256: String; let evidenceSHA256: String; let disposition: ExceptionQueueAcknowledgementDispositionV1; let revision: UInt64; let supersedesAcknowledgementID: UUID?; let predecessorSHA256: String?; let actor: ActorSnapshotV1; let recordedAt: Date; let mutationID: MutationIDV1 }
}

struct ExceptionQueueItemV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let queueItemID: String; let source: ExceptionQueueSourceSnapshotV1
    let acknowledgement: ExceptionQueueAcknowledgementV1?; let isSourceResolved: Bool
    let queueItemSHA256: String
    init(source: ExceptionQueueSourceSnapshotV1, acknowledgement: ExceptionQueueAcknowledgementV1? = nil,
         isSourceResolved: Bool = false) throws {
        schemaVersion = Self.schemaVersion; queueItemID = source.logicalExceptionKey; self.source = source
        self.acknowledgement = acknowledgement; self.isSourceResolved = isSourceResolved
        queueItemSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion,
            queueItemID: source.logicalExceptionKey, source: source, acknowledgement: acknowledgement,
            isSourceResolved: isSourceResolved)); try validate()
    }
    func validate() throws {
        try source.validate(); if let acknowledgement { try acknowledgement.validateCurrentSource(source) }
        guard schemaVersion == Self.schemaVersion, queueItemID == source.logicalExceptionKey,
              !isSourceResolved, queueItemSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else {
            throw ReinspectionExceptionFailureV1.forgedSource
        }
    }
    func validateResolved(by resolver: any ExceptionQueueCanonicalSourceResolvingV1) throws {
        try validate(); try source.validateResolved(by: resolver)
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, queueItemID: queueItemID, source: source, acknowledgement: acknowledgement, isSourceResolved: isSourceResolved) }
    private struct Basis: Codable { let schemaVersion: Int; let queueItemID: String; let source: ExceptionQueueSourceSnapshotV1; let acknowledgement: ExceptionQueueAcknowledgementV1?; let isSourceResolved: Bool }
}

struct ExceptionQueueFilterV1: Codable, Equatable, Sendable {
    let sourceKinds: [ExceptionQueueSourceKindV1]; let severities: [ExceptionQueueSeverityV1]; let reasons: [ExceptionQueueReasonV1]
    init(sourceKinds: [ExceptionQueueSourceKindV1] = [], severities: [ExceptionQueueSeverityV1] = [], reasons: [ExceptionQueueReasonV1] = []) throws {
        self.sourceKinds = sourceKinds; self.severities = severities; self.reasons = reasons; try validate()
    }
    func validate() throws {
        guard sourceKinds == sourceKinds.sorted(by: { $0.rawValue < $1.rawValue }), Set(sourceKinds).count == sourceKinds.count,
              severities == severities.sorted(by: { $0.rawValue < $1.rawValue }), Set(severities).count == severities.count,
              reasons == reasons.sorted(by: { $0.rawValue < $1.rawValue }), Set(reasons).count == reasons.count else { throw ReinspectionExceptionFailureV1.duplicateIdentity }
    }
    func includes(_ item: ExceptionQueueItemV1) -> Bool {
        (sourceKinds.isEmpty || sourceKinds.contains(item.source.kind)) &&
        (severities.isEmpty || severities.contains(item.source.severity)) &&
        (reasons.isEmpty || !Set(reasons).isDisjoint(with: item.source.reasons))
    }
}

struct ExceptionQueueProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let registry: ExceptionQueueSourceRegistryV1
    let items: [ExceptionQueueItemV1]
    let unresolvedCount: Int

    init(workspaceID: WorkspaceID, registry: ExceptionQueueSourceRegistryV1,
         sources: [ExceptionQueueSourceSnapshotV1],
         acknowledgements: [ExceptionQueueAcknowledgementV1] = [],
         resolver: any ExceptionQueueCanonicalSourceResolvingV1) throws {
        try registry.validate()
        guard sources.count <= ReinspectionExceptionLimitsV1.maximumQueueItems else {
            throw ReinspectionExceptionFailureV1.arithmeticOverflow
        }
        try sources.forEach { try $0.validateResolved(by: resolver) }
        try acknowledgements.forEach { try $0.validate() }
        guard sources.allSatisfy({ $0.workspaceID == workspaceID }),
              acknowledgements.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw ReinspectionExceptionFailureV1.wrongWorkspace
        }
        let sortedSources = sources.sorted {
            if $0.logicalExceptionKey != $1.logicalExceptionKey { return $0.logicalExceptionKey < $1.logicalExceptionKey }
            if $0.severity != $1.severity { return $0.severity.rawValue > $1.severity.rawValue }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return ($0.sourceID, $0.sourceRevision, $0.sourceSHA256) < ($1.sourceID, $1.sourceRevision, $1.sourceSHA256)
        }
        var selected: [ExceptionQueueSourceSnapshotV1] = []
        for source in sortedSources where selected.last?.logicalExceptionKey != source.logicalExceptionKey { selected.append(source) }
        let acknowledgementByKey = Dictionary(grouping: acknowledgements, by: \.logicalExceptionKey)
        let built = try selected.map { source -> ExceptionQueueItemV1 in
            let matching = (acknowledgementByKey[source.logicalExceptionKey] ?? [])
                .filter { acknowledgement in
                    acknowledgement.sourceKind == source.kind && acknowledgement.sourceID == source.sourceID &&
                    acknowledgement.sourceRevision == source.sourceRevision && acknowledgement.sourceSHA256 == source.sourceSHA256
                }
                .sorted { ($0.revision, $0.acknowledgementID.uuidString) < ($1.revision, $1.acknowledgementID.uuidString) }
            guard Set(matching.map(\.revision)).count == matching.count else { throw ReinspectionExceptionFailureV1.duplicateIdentity }
            return try ExceptionQueueItemV1(source: source, acknowledgement: matching.last)
        }.sorted {
            $0.source.severity == $1.source.severity
                ? $0.queueItemID < $1.queueItemID
                : $0.source.severity.rawValue > $1.source.severity.rawValue
        }
        self.workspaceID = workspaceID; self.registry = registry; items = built; unresolvedCount = built.count
        try validate()
    }

    func validate() throws {
        try registry.validate(); try items.forEach { try $0.validate() }
        guard items.count <= ReinspectionExceptionLimitsV1.maximumQueueItems, unresolvedCount == items.count,
              items.allSatisfy({ $0.source.workspaceID == workspaceID }),
              Set(items.map(\.queueItemID)).count == items.count,
              items == items.sorted(by: {
                  $0.source.severity == $1.source.severity
                      ? $0.queueItemID < $1.queueItemID
                      : $0.source.severity.rawValue > $1.source.severity.rawValue
              }) else { throw ReinspectionExceptionFailureV1.duplicateIdentity }
    }
}

enum ReinspectionExceptionMutationPayloadV1: Codable, Equatable, Sendable {
    case putPlan(ReinspectionPlanV1, ReinspectionPlanV1?)
    case recordAttestation(UnchangedAttestationV1, ReinspectionPlanV1)
    case recordAcknowledgement(ExceptionQueueAcknowledgementV1, ExceptionQueueSourceSnapshotV1, ExceptionQueueAcknowledgementV1?)
    var workspaceID: WorkspaceID { switch self { case let .putPlan(v, _): return v.workspaceID; case let .recordAttestation(v, _): return v.workspaceID; case let .recordAcknowledgement(v, _, _): return v.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case let .putPlan(v, _): return v.mutationID; case let .recordAttestation(v, _): return v.mutationID; case let .recordAcknowledgement(v, _, _): return v.mutationID } }
    var semanticSHA256s: [String] { switch self { case let .putPlan(v, _): return [v.planSHA256]; case let .recordAttestation(v, _): return [v.attestationSHA256]; case let .recordAcknowledgement(v, _, _): return [v.acknowledgementSHA256] } }
    func validate() throws { switch self { case let .putPlan(v, predecessor): try v.validate(predecessor: predecessor); case let .recordAttestation(v, p): try v.validate(plan: p); case let .recordAcknowledgement(v, s, predecessor): try v.validate(source: s, predecessor: predecessor) } }
    func validateResolved(reinspectionResolver: any ReinspectionCanonicalSourceResolvingV1,
                          exceptionResolver: any ExceptionQueueCanonicalSourceResolvingV1) throws {
        try validate()
        switch self {
        case let .putPlan(plan, predecessor):
            for item in plan.items { try item.prior.validateResolved(by: reinspectionResolver); try item.current.validateResolved(by: reinspectionResolver) }
            if let predecessor { for item in predecessor.items { try item.prior.validateResolved(by: reinspectionResolver); try item.current.validateResolved(by: reinspectionResolver) } }
        case let .recordAttestation(attestation, plan):
            try attestation.prior.validateResolved(by: reinspectionResolver); try attestation.current.validateResolved(by: reinspectionResolver)
            for item in plan.items { try item.prior.validateResolved(by: reinspectionResolver); try item.current.validateResolved(by: reinspectionResolver) }
        case let .recordAcknowledgement(_, source, _):
            try source.validateResolved(by: exceptionResolver)
        }
    }
}

struct ReinspectionExceptionMutationCommandV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1; let mutationID: MutationIDV1
    let payload: ReinspectionExceptionMutationPayloadV1; let submittedAt: Date; let commandSHA256: String
    init(commandID: UUID, workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1,
         mutationID: MutationIDV1, payload: ReinspectionExceptionMutationPayloadV1, submittedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.commandID = commandID; self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision; self.mutationID = mutationID; self.payload = payload; self.submittedAt = submittedAt
        commandSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, commandID: commandID,
            workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, payload: payload, submittedAt: submittedAt)); try validate()
    }
    func validate() throws {
        try ReinspectionExceptionValidationV1.id(commandID); try payload.validate(); try ReinspectionExceptionValidationV1.instant(submittedAt)
        guard schemaVersion == Self.schemaVersion, expectedRevision.workspaceID == workspaceID,
              expectedRevision.generationID != ReinspectionExceptionValidationV1.zero,
              expectedRevision.writerInstanceID != ReinspectionExceptionValidationV1.zero,
              payload.workspaceID == workspaceID, payload.mutationID == mutationID,
              commandSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
    }
    func validate(currentRevision: WorkspaceRevisionV1) throws { try validate(); guard WorkspaceExpectedRevisionV1(snapshot: currentRevision) == expectedRevision else { throw ReinspectionExceptionFailureV1.staleRevision } }
    func validate(currentRevision: WorkspaceRevisionV1,
                  reinspectionResolver: any ReinspectionCanonicalSourceResolvingV1,
                  exceptionResolver: any ExceptionQueueCanonicalSourceResolvingV1) throws {
        try validate(currentRevision: currentRevision)
        try payload.validateResolved(reinspectionResolver: reinspectionResolver, exceptionResolver: exceptionResolver)
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, commandID: commandID, workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, payload: payload, submittedAt: submittedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let mutationID: MutationIDV1; let payload: ReinspectionExceptionMutationPayloadV1; let submittedAt: Date }
}

enum ReinspectionExceptionQueryTargetV1: Codable, Equatable, Sendable {
    case plan(UUID), attestation(UUID), acknowledgement(String), queue(ExceptionQueueFilterV1)
}
struct ReinspectionExceptionQueryV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let target: ReinspectionExceptionQueryTargetV1; let maximumResults: Int
    init(workspaceID: WorkspaceID, target: ReinspectionExceptionQueryTargetV1, maximumResults: Int = 100) throws {
        guard (1...ReinspectionExceptionLimitsV1.maximumQueryResults).contains(maximumResults) else { throw ReinspectionExceptionFailureV1.invalidValue }
        switch target { case let .plan(id), let .attestation(id): try ReinspectionExceptionValidationV1.id(id); case let .acknowledgement(key): try ReinspectionExceptionValidationV1.token(key); case let .queue(filter): try filter.validate() }
        self.workspaceID = workspaceID; self.target = target; self.maximumResults = maximumResults
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, target: target, maximumResults: maximumResults) }
}
enum ReinspectionExceptionQueryResultV1: Codable, Equatable, Sendable {
    case plan(ReinspectionPlanV1), attestation(UnchangedAttestationV1)
    case acknowledgement(ExceptionQueueAcknowledgementV1), queue([ExceptionQueueItemV1])
    case notFound(ReinspectionExceptionQueryV1)
    func validate(for query: ReinspectionExceptionQueryV1) throws {
        try query.validate()
        switch (query.target, self) {
        case let (.plan(id), .plan(v)): try v.validate(); guard v.workspaceID == query.workspaceID, v.planID == id else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
        case let (.attestation(id), .attestation(v)): try v.validate(); guard v.workspaceID == query.workspaceID, v.attestationID == id else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
        case let (.acknowledgement(key), .acknowledgement(v)): try v.validate(); guard v.workspaceID == query.workspaceID, v.logicalExceptionKey == key else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
        case let (.queue(filter), .queue(values)):
            try filter.validate(); try values.forEach { try $0.validate() }
            guard values.count <= query.maximumResults,
                  values == values.sorted(by: {
                      $0.source.severity == $1.source.severity
                          ? $0.queueItemID < $1.queueItemID
                          : $0.source.severity.rawValue > $1.source.severity.rawValue
                  }),
                  Set(values.map(\.queueItemID)).count == values.count,
                  values.allSatisfy({ $0.source.workspaceID == query.workspaceID && filter.includes($0) }) else { throw ReinspectionExceptionFailureV1.duplicateIdentity }
        case let (_, .notFound(bound)): guard bound == query else { throw ReinspectionExceptionFailureV1.receiptMismatch }
        default: throw ReinspectionExceptionFailureV1.invalidValue
        }
    }
    func validateResolved(for query: ReinspectionExceptionQueryV1,
                          reinspectionResolver: any ReinspectionCanonicalSourceResolvingV1,
                          exceptionResolver: any ExceptionQueueCanonicalSourceResolvingV1) throws {
        try validate(for: query)
        switch self {
        case let .plan(plan): try plan.validateResolved(by: reinspectionResolver)
        case let .attestation(attestation):
            try attestation.prior.validateResolved(by: reinspectionResolver); try attestation.current.validateResolved(by: reinspectionResolver)
        case let .acknowledgement(acknowledgement):
            let source = try exceptionResolver.resolveExceptionQueueSource(workspaceID: acknowledgement.workspaceID,
                kind: acknowledgement.sourceKind, sourceID: acknowledgement.sourceID, revision: acknowledgement.sourceRevision)
            try acknowledgement.validateCurrentSource(source)
        case let .queue(items): try items.forEach { try $0.validateResolved(by: exceptionResolver) }
        case .notFound: break
        }
    }
}

enum ReinspectionExceptionRecoveryStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case effectCommittedAwaitingReceipt = "EFFECT_COMMITTED_AWAITING_RECEIPT", receiptCommitted = "RECEIPT_COMMITTED"
}
struct ReinspectionExceptionMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let generationID: UUID
    let mutationID: MutationIDV1; let commandSHA256: String; let semanticSHA256s: [String]
    let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64
    let recoveryState: ReinspectionExceptionRecoveryStateV1; let committedAt: Date; let receiptSHA256: String
    init(receiptID: UUID, command: ReinspectionExceptionMutationCommandV1, resultingWorkspaceRevision: UInt64,
         recoveryState: ReinspectionExceptionRecoveryStateV1, committedAt: Date) throws {
        try command.validate(); schemaVersion = Self.schemaVersion; self.receiptID = receiptID; workspaceID = command.workspaceID
        generationID = command.expectedRevision.generationID; mutationID = command.mutationID; commandSHA256 = command.commandSHA256
        semanticSHA256s = command.payload.semanticSHA256s.sorted(); priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision; self.recoveryState = recoveryState; self.committedAt = committedAt
        receiptSHA256 = try ReinspectionExceptionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, receiptID: receiptID,
            workspaceID: command.workspaceID, generationID: command.expectedRevision.generationID, mutationID: command.mutationID,
            commandSHA256: command.commandSHA256, semanticSHA256s: command.payload.semanticSHA256s.sorted(),
            priorWorkspaceRevision: command.expectedRevision.workspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision,
            recoveryState: recoveryState, committedAt: committedAt)); try validate(command: command)
    }
    func validate() throws {
        try ReinspectionExceptionValidationV1.id(receiptID); try ReinspectionExceptionValidationV1.id(generationID)
        try ReinspectionExceptionValidationV1.digest(commandSHA256); try semanticSHA256s.forEach(ReinspectionExceptionValidationV1.digest)
        try ReinspectionExceptionValidationV1.instant(committedAt); let (next, overflow) = priorWorkspaceRevision.addingReportingOverflow(1)
        guard !overflow, schemaVersion == Self.schemaVersion, resultingWorkspaceRevision == next,
              !semanticSHA256s.isEmpty, semanticSHA256s == semanticSHA256s.sorted(), Set(semanticSHA256s).count == semanticSHA256s.count,
              receiptSHA256 == (try ReinspectionExceptionValidationV1.hash(basis)) else { throw ReinspectionExceptionFailureV1.receiptMismatch }
    }
    func validate(command: ReinspectionExceptionMutationCommandV1) throws {
        try validate(); try command.validate(); guard workspaceID == command.workspaceID, generationID == command.expectedRevision.generationID,
            mutationID == command.mutationID, commandSHA256 == command.commandSHA256,
            semanticSHA256s == command.payload.semanticSHA256s.sorted(), priorWorkspaceRevision == command.expectedRevision.workspaceRevision else { throw ReinspectionExceptionFailureV1.receiptMismatch }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID, generationID: generationID,
        mutationID: mutationID, commandSHA256: commandSHA256, semanticSHA256s: semanticSHA256s,
        priorWorkspaceRevision: priorWorkspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision,
        recoveryState: recoveryState, committedAt: committedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let generationID: UUID; let mutationID: MutationIDV1; let commandSHA256: String; let semanticSHA256s: [String]; let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64; let recoveryState: ReinspectionExceptionRecoveryStateV1; let committedAt: Date }
}
