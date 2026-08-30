import Foundation

enum AssistanceContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case incompatibleCapability
    case metadataPolicyMismatch
    case proposalNotFound
    case duplicateProposal
    case staleTarget
    case wrongWorkspace
    case expired(AssistanceProposalExpiryReasonV1)
    case invalidReceipt
    case scratchCleanupFailed
    case limitExceeded
    case nonCanonicalData
}

enum AssistanceLimitsV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static let maximumTokenBytes = 256
    static let maximumFieldIDBytes = 512
    static let maximumCanonicalBytes = 1_048_576
    static let maximumLifetime: TimeInterval = 24 * 60 * 60
    static let maximumActiveProposals = 512
    static let maximumTerminalRemovals = 1_024

    static func id(_ value: UUID) throws {
        guard value != zero else { throw AssistanceContractFailureV1.invalidValue }
    }

    static func token(_ value: String, maximumBytes: Int = maximumTokenBytes) throws {
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AssistanceContractFailureV1.invalidValue
        }
    }

    static func digest(_ value: String) throws {
        guard MutationEnvelopeV1.isSHA256(value) else {
            throw AssistanceContractFailureV1.invalidDigest
        }
    }

    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw AssistanceContractFailureV1.invalidValue
        }
    }
}

struct AssistanceCapabilityReferenceV1: Codable, Equatable, Hashable, Sendable {
    let capabilityID: String
    let version: String
    let localeIdentifier: String?

    init(capabilityID: String, version: String, localeIdentifier: String? = nil) throws {
        try AssistanceLimitsV1.token(capabilityID)
        try AssistanceLimitsV1.token(version)
        try localeIdentifier.map { try AssistanceLimitsV1.token($0) }
        self.capabilityID = capabilityID
        self.version = version
        self.localeIdentifier = localeIdentifier
    }

    func validate() throws {
        _ = try Self(
            capabilityID: capabilityID,
            version: version,
            localeIdentifier: localeIdentifier
        )
    }
}

struct AssistanceTargetV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let entity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let fieldID: String

    init(
        workspaceID: WorkspaceID,
        entity: WorkspaceEntityIdentityV1,
        revision: UInt64,
        fieldID: String
    ) throws {
        try AssistanceLimitsV1.token(fieldID, maximumBytes: AssistanceLimitsV1.maximumFieldIDBytes)
        guard revision > 0 else { throw AssistanceContractFailureV1.invalidValue }
        self.workspaceID = workspaceID
        self.entity = entity
        self.revision = revision
        self.fieldID = fieldID
    }

    func validate() throws {
        _ = try WorkspaceEntityIdentityV1(kind: entity.kind, id: entity.id)
        _ = try Self(workspaceID: workspaceID, entity: entity, revision: revision, fieldID: fieldID)
    }
}

enum AssistanceSourceKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case immutableContent = "IMMUTABLE_CONTENT"
    case leasedScratch = "LEASED_SCRATCH"
    case deterministicRule = "DETERMINISTIC_RULE"
    case deviceObservation = "DEVICE_OBSERVATION"
}

struct AssistanceSourceReferenceV1: Codable, Equatable, Hashable, Sendable {
    let kind: AssistanceSourceKindV1
    let sourceID: String
    let revision: UInt64
    let contentSHA256: String

    init(
        kind: AssistanceSourceKindV1,
        sourceID: String,
        revision: UInt64,
        contentSHA256: String
    ) throws {
        try AssistanceLimitsV1.token(sourceID)
        try AssistanceLimitsV1.digest(contentSHA256)
        guard revision > 0 else { throw AssistanceContractFailureV1.invalidValue }
        self.kind = kind
        self.sourceID = sourceID
        self.revision = revision
        self.contentSHA256 = contentSHA256
    }

    func validate() throws {
        _ = try Self(kind: kind, sourceID: sourceID, revision: revision, contentSHA256: contentSHA256)
    }
}

/// Memory-only linkage to a capability-owned scratch lease. It intentionally
/// carries no bytes and is excluded from Codable/persistence enrollment.
struct AssistanceCapabilityScratchV1: Equatable, Sendable {
    let proposalID: UUID
    let source: AssistanceSourceReferenceV1

    init(proposalID: UUID, source: AssistanceSourceReferenceV1) throws {
        try AssistanceLimitsV1.id(proposalID)
        try source.validate()
        guard source.kind == .leasedScratch else {
            throw AssistanceContractFailureV1.invalidValue
        }
        self.proposalID = proposalID
        self.source = source
    }
}

struct AssistanceConfidenceV1: Codable, Equatable, Hashable, Sendable {
    let basisPoints: Int

    init(basisPoints: Int) throws {
        guard (0...10_000).contains(basisPoints) else {
            throw AssistanceContractFailureV1.invalidValue
        }
        self.basisPoints = basisPoints
    }
}

struct AssistanceQualityMetadataV1: Codable, Equatable, Hashable, Sendable {
    let metricID: String
    let ratingID: String

    init(metricID: String, ratingID: String) throws {
        try AssistanceLimitsV1.token(metricID)
        try AssistanceLimitsV1.token(ratingID)
        self.metricID = metricID
        self.ratingID = ratingID
    }

    func validate() throws { _ = try Self(metricID: metricID, ratingID: ratingID) }
}

enum AssistancePrivacyClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case workspaceOperational = "WORKSPACE_OPERATIONAL"
    case sensitiveWorkData = "SENSITIVE_WORK_DATA"
    case preciseLocation = "PRECISE_LOCATION"
}

enum AssistanceProposalVerificationStateV1: String, Codable, CaseIterable, Sendable {
    case unverified = "UNVERIFIED"
}

enum AssistanceMetadataRequirementV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notApplicable = "NOT_APPLICABLE"
    case optional = "OPTIONAL"
    case required = "REQUIRED"

    func admits<T>(_ value: T?) -> Bool {
        switch self {
        case .notApplicable: return value == nil
        case .optional: return true
        case .required: return value != nil
        }
    }
}

struct AssistanceCapabilityPolicyV1: Codable, Equatable, Sendable {
    let capability: AssistanceCapabilityReferenceV1
    let enabled: Bool
    let confidenceRequirement: AssistanceMetadataRequirementV1
    let qualityRequirement: AssistanceMetadataRequirementV1
    let manualFallback: ManualFallbackActionV1

    init(
        capability: AssistanceCapabilityReferenceV1,
        enabled: Bool,
        confidenceRequirement: AssistanceMetadataRequirementV1,
        qualityRequirement: AssistanceMetadataRequirementV1,
        manualFallback: ManualFallbackActionV1
    ) throws {
        try capability.validate()
        guard manualFallback != .noFallback else {
            throw AssistanceContractFailureV1.invalidValue
        }
        self.capability = capability
        self.enabled = enabled
        self.confidenceRequirement = confidenceRequirement
        self.qualityRequirement = qualityRequirement
        self.manualFallback = manualFallback
    }

    func validate() throws {
        _ = try Self(
            capability: capability,
            enabled: enabled,
            confidenceRequirement: confidenceRequirement,
            qualityRequirement: qualityRequirement,
            manualFallback: manualFallback
        )
    }

    func validateMetadata(for proposal: AssistanceProposalV1) throws {
        try validate()
        guard proposal.capability == capability,
              confidenceRequirement.admits(proposal.confidence),
              qualityRequirement.admits(proposal.quality) else {
            throw AssistanceContractFailureV1.metadataPolicyMismatch
        }
    }
}

/// An unverified, in-memory review candidate. This type deliberately has no
/// SwiftData annotation and no persistence-row counterpart.
struct AssistanceProposalV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let proposalID: UUID
    let capability: AssistanceCapabilityReferenceV1
    let target: AssistanceTargetV1
    let value: ResponseValueV1
    let source: AssistanceSourceReferenceV1
    let confidence: AssistanceConfidenceV1?
    let quality: AssistanceQualityMetadataV1?
    let packageReleaseSHA256: String?
    let definitionReleaseSHA256: String?
    let createdAt: Date
    let expiresAt: Date
    let privacyClass: AssistancePrivacyClassV1

    init(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        value: ResponseValueV1,
        source: AssistanceSourceReferenceV1,
        confidence: AssistanceConfidenceV1? = nil,
        quality: AssistanceQualityMetadataV1? = nil,
        packageReleaseSHA256: String? = nil,
        definitionReleaseSHA256: String? = nil,
        createdAt: Date,
        expiresAt: Date,
        privacyClass: AssistancePrivacyClassV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.proposalID = proposalID
        self.capability = capability
        self.target = target
        self.value = value
        self.source = source
        self.confidence = confidence
        self.quality = quality
        self.packageReleaseSHA256 = packageReleaseSHA256
        self.definitionReleaseSHA256 = definitionReleaseSHA256
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.privacyClass = privacyClass
        try validate()
    }

    func validate() throws {
        try AssistanceLimitsV1.id(proposalID)
        try capability.validate()
        try target.validate()
        try value.validate()
        try source.validate()
        try quality?.validate()
        try packageReleaseSHA256.map(AssistanceLimitsV1.digest)
        try definitionReleaseSHA256.map(AssistanceLimitsV1.digest)
        try AssistanceLimitsV1.instant(createdAt)
        try AssistanceLimitsV1.instant(expiresAt)
        guard schemaVersion == Self.schemaVersion,
              value != .noValue,
              expiresAt > createdAt,
              expiresAt.timeIntervalSince(createdAt) <= AssistanceLimitsV1.maximumLifetime else {
            throw AssistanceContractFailureV1.invalidValue
        }
    }

    var proposalSHA256: String { get throws { try AssistanceCanonicalCodecV1.sha256(self) } }
    var valueSHA256: String { get throws { try AssistanceCanonicalCodecV1.sha256(value) } }
    var verificationState: AssistanceProposalVerificationStateV1 { .unverified }

    func expiryReason(
        in context: AssistanceProposalEvaluationContextV1
    ) throws -> AssistanceProposalExpiryReasonV1? {
        try validate()
        try context.validate()
        if target.workspaceID != context.workspaceID { return .workspaceChanged }
        if target.revision != context.targetRevision { return .targetRevisionChanged }
        if !context.policy.enabled { return .capabilityRevoked }
        if capability.capabilityID != context.policy.capability.capabilityID {
            return .capabilityRevoked
        }
        if capability.version != context.policy.capability.version {
            return .capabilityVersionChanged
        }
        if capability.localeIdentifier != context.policy.capability.localeIdentifier {
            return .capabilityLocaleChanged
        }
        if (try? context.policy.validateMetadata(for: self)) == nil {
            return .capabilityPolicyChanged
        }
        if packageReleaseSHA256 != context.packageReleaseSHA256 { return .packageChanged }
        if definitionReleaseSHA256 != context.definitionReleaseSHA256 { return .definitionChanged }
        guard let currentSource = context.currentSource else { return .sourceDeleted }
        if source != currentSource { return .sourceChanged }
        if context.evaluatedAt >= expiresAt { return .timedOut }
        return nil
    }
}

struct AssistanceProposalEvaluationContextV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let targetRevision: UInt64
    let policy: AssistanceCapabilityPolicyV1
    let packageReleaseSHA256: String?
    let definitionReleaseSHA256: String?
    let currentSource: AssistanceSourceReferenceV1?
    let evaluatedAt: Date

    init(
        workspaceID: WorkspaceID,
        targetRevision: UInt64,
        policy: AssistanceCapabilityPolicyV1,
        packageReleaseSHA256: String? = nil,
        definitionReleaseSHA256: String? = nil,
        currentSource: AssistanceSourceReferenceV1?,
        evaluatedAt: Date
    ) {
        self.workspaceID = workspaceID
        self.targetRevision = targetRevision
        self.policy = policy
        self.packageReleaseSHA256 = packageReleaseSHA256
        self.definitionReleaseSHA256 = definitionReleaseSHA256
        self.currentSource = currentSource
        self.evaluatedAt = evaluatedAt
    }

    func validate() throws {
        guard targetRevision > 0 else { throw AssistanceContractFailureV1.invalidValue }
        try policy.validate()
        try packageReleaseSHA256.map(AssistanceLimitsV1.digest)
        try definitionReleaseSHA256.map(AssistanceLimitsV1.digest)
        try currentSource?.validate()
        try AssistanceLimitsV1.instant(evaluatedAt)
    }
}

enum AssistanceProposalExpiryReasonV1: String, Codable, CaseIterable, Equatable, Sendable {
    case targetRevisionChanged = "TARGET_REVISION_CHANGED"
    case capabilityRevoked = "CAPABILITY_REVOKED"
    case capabilityVersionChanged = "CAPABILITY_VERSION_CHANGED"
    case capabilityLocaleChanged = "CAPABILITY_LOCALE_CHANGED"
    case capabilityPolicyChanged = "CAPABILITY_POLICY_CHANGED"
    case packageChanged = "PACKAGE_CHANGED"
    case definitionChanged = "DEFINITION_CHANGED"
    case timedOut = "TIMED_OUT"
    case workspaceChanged = "WORKSPACE_CHANGED"
    case sourceDeleted = "SOURCE_DELETED"
    case sourceChanged = "SOURCE_CHANGED"
}

enum AssistanceRemovalKindV1: String, Codable, CaseIterable, Equatable, Sendable {
    case rejected = "REJECTED"
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"
    case accepted = "ACCEPTED"
}

struct AssistanceRemovalDispositionV1: Equatable, Sendable {
    let proposalID: UUID
    let kind: AssistanceRemovalKindV1
    let expiryReason: AssistanceProposalExpiryReasonV1?
    let scratchDeleted: Bool
    let manualTextPreserved: Bool
    let durableRejectedCorpusCreated: Bool

    init(
        proposalID: UUID,
        kind: AssistanceRemovalKindV1,
        expiryReason: AssistanceProposalExpiryReasonV1? = nil
    ) throws {
        try AssistanceLimitsV1.id(proposalID)
        guard (kind == .expired) == (expiryReason != nil) else {
            throw AssistanceContractFailureV1.invalidValue
        }
        self.proposalID = proposalID
        self.kind = kind
        self.expiryReason = expiryReason
        scratchDeleted = true
        manualTextPreserved = true
        durableRejectedCorpusCreated = false
    }
}

struct AssistanceExpiryDispositionV1: Equatable, Sendable {
    let proposalID: UUID
    let reason: AssistanceProposalExpiryReasonV1
    let removal: AssistanceRemovalDispositionV1
}

enum AssistanceReviewDecisionV1: Equatable, Sendable {
    case ready(AssistanceProposalV1)
    case expired(AssistanceExpiryDispositionV1)
}

/// Closed, typed canonical mutations that an accepted proposal may authorize.
/// C32 starts with its direct C26 prerequisite. Later OCR/location cards extend
/// this enum deliberately; they never pass an opaque closure or raw database
/// operation through the assistance boundary.
enum AssistanceCanonicalTargetMutationV1: Codable, Equatable, Sendable {
    case surveySession(SurveySessionMutationV1)

    var workspaceID: WorkspaceID {
        switch self { case .surveySession(let value): value.workspaceID }
    }

    var mutationID: MutationIDV1 {
        switch self { case .surveySession(let value): value.mutationID }
    }

    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            switch self { case .surveySession(let value): return try value.affectedIdentities }
        }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            switch self { case .surveySession(let value): return try value.concurrencyIdentities }
        }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        switch self { case .surveySession(let value): return try value.expectedRevision(for: identity) }
    }

    func validate(
        proposal: AssistanceProposalV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        acceptedBy: ActorSnapshotV1,
        acceptedAt: Date
    ) throws {
        try proposal.validate()
        let concurrency = try concurrencyIdentities
        let expected = expectedRevision.entityRevisions
        guard workspaceID == proposal.target.workspaceID,
              workspaceID == expectedRevision.workspaceID,
              self.mutationID == mutationID,
              Set(concurrency) == Set(expected.map(\.identity)),
              concurrency.allSatisfy({ identity in
                  expected.first(where: { $0.identity == identity })?.revision
                    == (try? self.expectedRevision(for: identity))
              }) else { throw AssistanceContractFailureV1.staleTarget }

        switch self {
        case .surveySession(let value):
            try value.validate()
            guard case let .captureFact(capture, session, definition, _) = value.payload,
                  proposal.target.entity.kind == .surveySession,
                  proposal.target.entity.id == session.sessionID,
                  proposal.target.revision == session.revision,
                  proposal.target.fieldID == capture.factID,
                  capture.value == proposal.value,
                  capture.action != .retract,
                  capture.capturedBy == acceptedBy,
                  capture.capturedAt == acceptedAt,
                  proposal.packageReleaseSHA256
                    == session.authority.packageRelease.packageSHA256,
                  proposal.definitionReleaseSHA256 == definition.releaseSHA256 else {
                throw AssistanceContractFailureV1.invalidValue
            }
        }
    }

    var mutationSHA256: String { get throws { try AssistanceCanonicalCodecV1.sha256(self) } }
}

struct AssistanceAcceptanceRequestV1: Codable, Equatable, Sendable {
    let proposal: AssistanceProposalV1
    let targetMutation: AssistanceCanonicalTargetMutationV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let acceptedBy: ActorSnapshotV1
    let acceptedAt: Date

    init(
        proposal: AssistanceProposalV1,
        targetMutation: AssistanceCanonicalTargetMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        acceptedBy: ActorSnapshotV1,
        acceptedAt: Date
    ) throws {
        self.proposal = proposal
        self.targetMutation = targetMutation
        self.expectedRevision = expectedRevision
        self.mutationID = mutationID
        self.acceptedBy = acceptedBy
        self.acceptedAt = acceptedAt
        try validate()
    }

    func validate() throws {
        try proposal.validate()
        try acceptedBy.validate()
        try AssistanceLimitsV1.instant(acceptedAt)
        guard expectedRevision.workspaceID == proposal.target.workspaceID,
              acceptedBy.workspaceID == proposal.target.workspaceID,
              acceptedBy.responsibility == .reviewedBy,
              acceptedAt >= proposal.createdAt,
              acceptedAt < proposal.expiresAt else {
            throw AssistanceContractFailureV1.staleTarget
        }
        try targetMutation.validate(
            proposal: proposal,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            acceptedBy: acceptedBy,
            acceptedAt: acceptedAt
        )
    }

    var requestSHA256: String { get throws { try AssistanceCanonicalCodecV1.sha256(self) } }

    /// The only bridge into the generic journal/writer transaction. The outer
    /// command retains proposal/review provenance for effect-before-receipt
    /// recovery while WorkspaceWriterAdapter applies the closed target payload.
    func canonicalWorkspaceMutationRequest() -> WorkspaceMutationRequestV1 {
        WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            command: .applyAssistanceAcceptance(self)
        )
    }

    func validateManualPathEquivalence(
        to manualTargetMutation: AssistanceCanonicalTargetMutationV1
    ) throws {
        try validate()
        guard targetMutation == manualTargetMutation else {
            throw AssistanceContractFailureV1.invalidValue
        }
    }
}

struct AssistanceAcceptanceReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let proposalID: UUID
    let capability: AssistanceCapabilityReferenceV1
    let target: AssistanceTargetV1
    let acceptedValue: ResponseValueV1
    let source: AssistanceSourceReferenceV1
    let privacyClass: AssistancePrivacyClassV1
    let proposalSHA256: String
    let valueSHA256: String
    let requestSHA256: String
    let targetMutationSHA256: String
    let canonicalCommandBodySHA256: String
    let canonicalEffectIdentities: [WorkspaceEntityIdentityV1]
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let acceptedBy: ActorSnapshotV1
    let acceptedAt: Date
    let canonicalMutationReceiptIdentity: MutationReceiptIdentityV1
    let canonicalMutationReceiptSHA256: String
    let receiptSHA256: String

    init(
        request: AssistanceAcceptanceRequestV1,
        canonicalMutationReceipt: MutationReceiptV1
    ) throws {
        try request.validate()
        try canonicalMutationReceipt.validate()
        schemaVersion = Self.schemaVersion
        receiptID = request.mutationID.rawValue
        workspaceID = request.proposal.target.workspaceID
        proposalID = request.proposal.proposalID
        capability = request.proposal.capability
        target = request.proposal.target
        acceptedValue = request.proposal.value
        source = request.proposal.source
        privacyClass = request.proposal.privacyClass
        proposalSHA256 = try request.proposal.proposalSHA256
        valueSHA256 = try request.proposal.valueSHA256
        requestSHA256 = try request.requestSHA256
        targetMutationSHA256 = try request.targetMutation.mutationSHA256
        canonicalCommandBodySHA256 = try AssistanceCanonicalCodecV1.sha256(
            WorkspaceCommandV1.applyAssistanceAcceptance(request)
        )
        canonicalEffectIdentities = try request.targetMutation.affectedIdentities
            .sorted { $0.stableKey < $1.stableKey }
        expectedRevision = request.expectedRevision
        mutationID = request.mutationID
        acceptedBy = request.acceptedBy
        acceptedAt = request.acceptedAt
        canonicalMutationReceiptIdentity = canonicalMutationReceipt.identity
        canonicalMutationReceiptSHA256 = try canonicalMutationReceipt.canonicalSHA256()
        receiptSHA256 = try AssistanceCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            receiptID: receiptID,
            workspaceID: workspaceID,
            proposalID: proposalID,
            capability: capability,
            target: target,
            acceptedValue: acceptedValue,
            source: source,
            privacyClass: privacyClass,
            proposalSHA256: proposalSHA256,
            valueSHA256: valueSHA256,
            requestSHA256: requestSHA256,
            targetMutationSHA256: targetMutationSHA256,
            canonicalCommandBodySHA256: canonicalCommandBodySHA256,
            canonicalEffectIdentities: canonicalEffectIdentities,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            acceptedBy: acceptedBy,
            acceptedAt: acceptedAt,
            canonicalMutationReceiptIdentity: canonicalMutationReceiptIdentity,
            canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
        ))
        try validate(canonicalMutationReceipt: canonicalMutationReceipt)
    }

    func validate() throws {
        let validatedExpectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: expectedRevision.workspaceID,
            generationID: expectedRevision.generationID,
            writerInstanceID: expectedRevision.writerInstanceID,
            workspaceRevision: expectedRevision.workspaceRevision,
            entityRevisions: expectedRevision.entityRevisions
        )
        try AssistanceLimitsV1.id(receiptID)
        try AssistanceLimitsV1.id(proposalID)
        try capability.validate()
        try target.validate()
        try acceptedValue.validate()
        try source.validate()
        try acceptedBy.validate()
        try canonicalMutationReceiptIdentity.validate()
        try [proposalSHA256, valueSHA256, requestSHA256, targetMutationSHA256,
             canonicalCommandBodySHA256,
             canonicalMutationReceiptSHA256, receiptSHA256].forEach(AssistanceLimitsV1.digest)
        try AssistanceLimitsV1.instant(acceptedAt)
        guard schemaVersion == Self.schemaVersion,
              receiptID == mutationID.rawValue,
              workspaceID == target.workspaceID,
              acceptedValue != .noValue,
              acceptedBy.workspaceID == workspaceID,
              acceptedBy.responsibility == .reviewedBy,
              canonicalMutationReceiptIdentity.workspaceID == workspaceID,
              expectedRevision == validatedExpectedRevision,
              expectedRevision.workspaceID == workspaceID,
              !canonicalEffectIdentities.isEmpty,
              canonicalEffectIdentities == canonicalEffectIdentities.sorted(by: {
                  $0.stableKey < $1.stableKey
              }),
              Set(canonicalEffectIdentities).count == canonicalEffectIdentities.count,
              valueSHA256 == (try AssistanceCanonicalCodecV1.sha256(acceptedValue)),
              receiptSHA256 == (try AssistanceCanonicalCodecV1.sha256(basis)) else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
    }

    func validate(canonicalMutationReceipt: MutationReceiptV1) throws {
        try validate()
        try canonicalMutationReceipt.validate()
        let imageIdentities = try canonicalMutationReceipt.postImages.map(\.identity)
        let portableExpectedRevision = try MutationPortableExpectedRevisionV1(expectedRevision)
        guard canonicalMutationReceipt.identity == canonicalMutationReceiptIdentity,
              canonicalMutationReceipt.mutationID == mutationID,
              canonicalMutationReceipt.identity.workspaceID == workspaceID,
              canonicalMutationReceipt.expectedRevision == portableExpectedRevision,
              canonicalMutationReceipt.commandBodySHA256 == canonicalCommandBodySHA256,
              try canonicalMutationReceipt.canonicalSHA256() == canonicalMutationReceiptSHA256,
              imageIdentities == canonicalEffectIdentities,
              canonicalMutationReceipt.committedAt >= acceptedAt else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
    }

    func validate(request: AssistanceAcceptanceRequestV1) throws {
        try request.validate()
        try validate()
        guard proposalID == request.proposal.proposalID,
              workspaceID == request.proposal.target.workspaceID,
              capability == request.proposal.capability,
              target == request.proposal.target,
              acceptedValue == request.proposal.value,
              source == request.proposal.source,
              privacyClass == request.proposal.privacyClass,
              proposalSHA256 == (try request.proposal.proposalSHA256),
              requestSHA256 == (try request.requestSHA256),
              targetMutationSHA256 == (try request.targetMutation.mutationSHA256),
              canonicalCommandBodySHA256 == (try AssistanceCanonicalCodecV1.sha256(
                  WorkspaceCommandV1.applyAssistanceAcceptance(request)
              )),
              canonicalEffectIdentities == (try request.targetMutation.affectedIdentities.sorted {
                  $0.stableKey < $1.stableKey
              }),
              expectedRevision == request.expectedRevision,
              mutationID == request.mutationID,
              acceptedBy == request.acceptedBy,
              acceptedAt == request.acceptedAt else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
    }

    private var basis: Basis {
        .init(
            schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
            proposalID: proposalID, capability: capability, target: target,
            acceptedValue: acceptedValue, source: source, privacyClass: privacyClass,
            proposalSHA256: proposalSHA256, valueSHA256: valueSHA256,
            requestSHA256: requestSHA256, targetMutationSHA256: targetMutationSHA256,
            canonicalCommandBodySHA256: canonicalCommandBodySHA256,
            canonicalEffectIdentities: canonicalEffectIdentities,
            expectedRevision: expectedRevision,
            mutationID: mutationID, acceptedBy: acceptedBy, acceptedAt: acceptedAt,
            canonicalMutationReceiptIdentity: canonicalMutationReceiptIdentity,
            canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let receiptID: UUID
        let workspaceID: WorkspaceID
        let proposalID: UUID
        let capability: AssistanceCapabilityReferenceV1
        let target: AssistanceTargetV1
        let acceptedValue: ResponseValueV1
        let source: AssistanceSourceReferenceV1
        let privacyClass: AssistancePrivacyClassV1
        let proposalSHA256: String
        let valueSHA256: String
        let requestSHA256: String
        let targetMutationSHA256: String
        let canonicalCommandBodySHA256: String
        let canonicalEffectIdentities: [WorkspaceEntityIdentityV1]
        let expectedRevision: WorkspaceExpectedRevisionV1
        let mutationID: MutationIDV1
        let acceptedBy: ActorSnapshotV1
        let acceptedAt: Date
        let canonicalMutationReceiptIdentity: MutationReceiptIdentityV1
        let canonicalMutationReceiptSHA256: String
    }
}

enum AssistanceCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try WorkspaceMutationCanonicalV1.data(value)
        guard !data.isEmpty, data.count <= AssistanceLimitsV1.maximumCanonicalBytes else {
            throw AssistanceContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= AssistanceLimitsV1.maximumCanonicalBytes else {
            throw AssistanceContractFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw AssistanceContractFailureV1.nonCanonicalData }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

enum C33TemporalEvidenceBoundary_Domain_Assistance_AssistanceContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row178 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Assistance_AssistanceContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}
enum C52ServiceRequestBoundary_AssistanceContractsV1 {
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
