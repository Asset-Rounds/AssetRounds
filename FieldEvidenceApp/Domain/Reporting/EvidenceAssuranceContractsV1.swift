import Foundation

enum EvidenceAssuranceFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case duplicateIdentity
    case visibilityDenied
    case stalePreview
    case invalidTransition
    case digestMismatch
    case nonCanonicalData
}

enum EvidenceAssuranceAccessibleDocumentBoundaryV1{
    static func sensitivity(_ value:EvidenceSensitivityV1)->AccessibleDocumentSensitivityV1{
        switch value{case .routine:.customerSafe;case .restricted,.highlyRestricted:.internalOnly}
    }
    static let assuranceDoesNotConferAccessibility=true
}

enum EvidenceAssuranceLimitsV1 {
    static let maximumLinks = 8_192
    static let maximumTextBytes = 512
    static let maximumProjectionVersionBytes = 128
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

private enum EvidenceAssuranceValidationV1 {
    static func id(_ value: UUID) throws {
        guard value != EvidenceAssuranceLimitsV1.zeroUUID else { throw EvidenceAssuranceFailureV1.invalidValue }
    }
    static func text(_ value: String, maximum: Int = EvidenceAssuranceLimitsV1.maximumTextBytes) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value, !value.isEmpty, value.utf8.count <= maximum else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
    }
    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw EvidenceAssuranceFailureV1.invalidValue }
    }
    static func workspace(_ value: WorkspaceID) throws {
        try id(value.rawValue)
    }
    static func revision(_ value: UInt64) throws {
        guard value > 0 else { throw EvidenceAssuranceFailureV1.invalidValue }
    }
}

enum EvidenceAudienceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case internalReview = "INTERNAL_REVIEW"
    case customerReport = "CUSTOMER_REPORT"
    case externalCollaborator = "EXTERNAL_COLLABORATOR"
}

enum EvidenceSensitivityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case routine = "ROUTINE"
    case restricted = "RESTRICTED"
    case highlyRestricted = "HIGHLY_RESTRICTED"
}

enum EvidenceInclusionDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case included = "INCLUDED"
    case excluded = "EXCLUDED"
}

enum EvidenceLimitationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case none = "NONE"
    case audienceNotDeclared = "AUDIENCE_NOT_DECLARED"
    case sensitivityRestricted = "SENSITIVITY_RESTRICTED"
    case evidenceUnavailable = "EVIDENCE_UNAVAILABLE"
    case evidenceInvalid = "EVIDENCE_INVALID"
}

struct EvidenceVisibilityDecisionV1: Codable, Equatable, Hashable, Sendable {
    let audience: EvidenceAudienceV1
    let disposition: EvidenceInclusionDispositionV1
    let limitation: EvidenceLimitationV1

    init(audience: EvidenceAudienceV1, disposition: EvidenceInclusionDispositionV1,
         limitation: EvidenceLimitationV1) throws {
        guard (disposition == .included) == (limitation == .none) else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
        self.audience = audience; self.disposition = disposition; self.limitation = limitation
    }

    func validate() throws {
        guard (disposition == .included) == (limitation == .none) else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
    }
}

/// Closed, immutable visibility authority. An audience is denied unless it is
/// explicitly present and compatible with the sensitivity classification.
struct EvidenceVisibilityV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let visibilityID: UUID
    let workspaceID: WorkspaceID
    let sensitivity: EvidenceSensitivityV1
    let allowedAudiences: [EvidenceAudienceV1]
    let effectiveAt: Date
    let supersedesVisibilityID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let visibilitySHA256: String

    init(visibilityID: UUID, workspaceID: WorkspaceID, sensitivity: EvidenceSensitivityV1,
         allowedAudiences: [EvidenceAudienceV1], effectiveAt: Date,
         supersedesVisibilityID: UUID? = nil, revision: UInt64 = 1,
         mutationID: MutationIDV1) throws {
        let audiences = allowedAudiences.sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion; self.visibilityID = visibilityID; self.workspaceID = workspaceID
        self.sensitivity = sensitivity; self.allowedAudiences = audiences; self.effectiveAt = effectiveAt
        self.supersedesVisibilityID = supersedesVisibilityID; self.revision = revision; self.mutationID = mutationID
        visibilitySHA256 = try EvidenceAssuranceCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, visibilityID: visibilityID, workspaceID: workspaceID,
            sensitivity: sensitivity, allowedAudiences: audiences, effectiveAt: effectiveAt,
            supersedesVisibilityID: supersedesVisibilityID, revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try EvidenceAssuranceValidationV1.id(visibilityID); try EvidenceAssuranceValidationV1.workspace(workspaceID)
        try EvidenceAssuranceValidationV1.revision(revision)
        if let supersedesVisibilityID { try EvidenceAssuranceValidationV1.id(supersedesVisibilityID) }
        guard schemaVersion == Self.schemaVersion, effectiveAt.timeIntervalSinceReferenceDate.isFinite,
              allowedAudiences == allowedAudiences.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(allowedAudiences).count == allowedAudiences.count,
              allowedAudiences.contains(.internalReview),
              supersedesVisibilityID != visibilityID,
              (supersedesVisibilityID == nil) == (revision == 1),
              sensitivity != .restricted || !allowedAudiences.contains(.externalCollaborator),
              sensitivity != .highlyRestricted || allowedAudiences == [.internalReview],
              visibilitySHA256 == (try EvidenceAssuranceCanonicalCodecV1.sha256(digestBasis)) else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
    }

    func decision(for audience: EvidenceAudienceV1) throws -> EvidenceVisibilityDecisionV1 {
        try validate()
        if sensitivity == .highlyRestricted && audience != .internalReview {
            return try .init(audience: audience, disposition: .excluded,
                             limitation: .sensitivityRestricted)
        }
        if sensitivity == .restricted && audience == .externalCollaborator {
            return try .init(audience: audience, disposition: .excluded,
                             limitation: .sensitivityRestricted)
        }
        guard allowedAudiences.contains(audience) else {
            return try .init(audience: audience, disposition: .excluded,
                             limitation: .audienceNotDeclared)
        }
        return try .init(audience: audience, disposition: .included, limitation: .none)
    }

    func validateSuccessor(of predecessor: Self) throws {
        try validate(); try predecessor.validate()
        guard workspaceID == predecessor.workspaceID,
              supersedesVisibilityID == predecessor.visibilityID,
              predecessor.revision < UInt64.max, revision == predecessor.revision + 1,
              effectiveAt >= predecessor.effectiveAt, mutationID != predecessor.mutationID else {
            throw EvidenceAssuranceFailureV1.invalidTransition
        }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(visibilityID: visibilityID, workspaceID: workspaceID, sensitivity: sensitivity,
                 allowedAudiences: allowedAudiences, effectiveAt: effectiveAt,
                 supersedesVisibilityID: supersedesVisibilityID, revision: revision, mutationID: mutationID)
    }

    private var digestBasis: DigestBasis { .init(schemaVersion: schemaVersion, visibilityID: visibilityID,
        workspaceID: workspaceID, sensitivity: sensitivity, allowedAudiences: allowedAudiences,
        effectiveAt: effectiveAt, supersedesVisibilityID: supersedesVisibilityID,
        revision: revision, mutationID: mutationID) }
    private struct DigestBasis: Codable { let schemaVersion: Int; let visibilityID: UUID; let workspaceID: WorkspaceID
        let sensitivity: EvidenceSensitivityV1; let allowedAudiences: [EvidenceAudienceV1]; let effectiveAt: Date
        let supersedesVisibilityID: UUID?; let revision: UInt64; let mutationID: MutationIDV1 }
}

struct ClaimEvidenceLinkV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let linkID: UUID
    let workspaceID: WorkspaceID
    let claimID: String
    let criterionID: String?
    let evidenceID: String?
    let evidenceRevision: UInt64?
    let evidenceSHA256: String?
    let visibility: EvidenceVisibilityV1
    let visibilityID: UUID
    let visibilityRevision: UInt64
    let visibilitySHA256: String
    let decision: EvidenceVisibilityDecisionV1
    let limitationNote: String?
    let supersedesLinkID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let linkSHA256: String

    init(linkID: UUID, workspaceID: WorkspaceID, claimID: String, criterionID: String? = nil,
         evidenceID: String? = nil, evidenceRevision: UInt64? = nil, evidenceSHA256: String? = nil,
         visibility: EvidenceVisibilityV1, audience: EvidenceAudienceV1,
         limitation: EvidenceLimitationV1? = nil, limitationNote: String? = nil,
         supersedesLinkID: UUID? = nil, revision: UInt64 = 1, mutationID: MutationIDV1) throws {
        try visibility.validate()
        let base = try visibility.decision(for: audience)
        let resolved: EvidenceVisibilityDecisionV1
        if let limitation, limitation != .none {
            resolved = try .init(audience: audience, disposition: .excluded, limitation: limitation)
        } else { resolved = base }
        schemaVersion = Self.schemaVersion; self.linkID = linkID; self.workspaceID = workspaceID
        self.claimID = claimID; self.criterionID = criterionID; self.evidenceID = evidenceID
        self.evidenceRevision = evidenceRevision; self.evidenceSHA256 = evidenceSHA256
        self.visibility = visibility
        visibilityID = visibility.visibilityID; visibilityRevision = visibility.revision
        visibilitySHA256 = visibility.visibilitySHA256; decision = resolved; self.limitationNote = limitationNote
        self.supersedesLinkID = supersedesLinkID; self.revision = revision; self.mutationID = mutationID
        linkSHA256 = try EvidenceAssuranceCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, linkID: linkID, workspaceID: workspaceID,
            claimID: claimID, criterionID: criterionID, evidenceID: evidenceID,
            evidenceRevision: evidenceRevision, evidenceSHA256: evidenceSHA256,
            visibility: visibility, visibilityID: visibility.visibilityID,
            visibilityRevision: visibility.revision, visibilitySHA256: visibility.visibilitySHA256,
            decision: resolved, limitationNote: limitationNote, supersedesLinkID: supersedesLinkID,
            revision: revision, mutationID: mutationID
        ))
        try validate(visibility: visibility)
    }

    func validate() throws {
        try EvidenceAssuranceValidationV1.id(linkID); try EvidenceAssuranceValidationV1.workspace(workspaceID)
        try EvidenceAssuranceValidationV1.id(visibilityID); try decision.validate()
        try EvidenceAssuranceValidationV1.text(claimID)
        if let evidenceID { try EvidenceAssuranceValidationV1.text(evidenceID) }
        if let criterionID { try EvidenceAssuranceValidationV1.text(criterionID) }
        if let limitationNote { try EvidenceAssuranceValidationV1.text(limitationNote) }
        if let supersedesLinkID { try EvidenceAssuranceValidationV1.id(supersedesLinkID) }
        if let evidenceRevision { try EvidenceAssuranceValidationV1.revision(evidenceRevision) }
        if let evidenceSHA256 { try EvidenceAssuranceValidationV1.digest(evidenceSHA256) }
        try EvidenceAssuranceValidationV1.revision(visibilityRevision)
        try EvidenceAssuranceValidationV1.revision(revision)
        try EvidenceAssuranceValidationV1.digest(visibilitySHA256)
        try visibility.validate()
        let maximumDecision = try visibility.decision(for: decision.audience)
        let hasEvidence = evidenceID != nil && evidenceRevision != nil && evidenceSHA256 != nil
        let hasNoPartialEvidence = (evidenceID == nil) == (evidenceRevision == nil)
            && (evidenceID == nil) == (evidenceSHA256 == nil)
        guard schemaVersion == Self.schemaVersion,
              visibility.workspaceID == workspaceID,
              visibility.visibilityID == visibilityID,
              visibility.revision == visibilityRevision,
              visibility.visibilitySHA256 == visibilitySHA256,
              !(maximumDecision.disposition == .excluded && decision.disposition == .included),
              hasNoPartialEvidence,
              decision.disposition != .included || hasEvidence,
              hasEvidence || decision.limitation == .evidenceUnavailable,
              (decision.disposition == .included) == (decision.limitation == .none),
              decision.disposition == .included ? limitationNote == nil : true,
              supersedesLinkID != linkID, (supersedesLinkID == nil) == (revision == 1),
              linkSHA256 == (try EvidenceAssuranceCanonicalCodecV1.sha256(digestBasis)) else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
    }

    func validate(visibility: EvidenceVisibilityV1) throws {
        try validate(); try visibility.validate()
        let maximumDecision = try visibility.decision(for: decision.audience)
        guard visibility.workspaceID == workspaceID, visibility.visibilityID == visibilityID,
              visibility.revision == visibilityRevision, visibility.visibilitySHA256 == visibilitySHA256,
              !(maximumDecision.disposition == .excluded && decision.disposition == .included) else {
            throw EvidenceAssuranceFailureV1.visibilityDenied
        }
    }

    func validateSuccessor(of predecessor: Self, visibility: EvidenceVisibilityV1) throws {
        try validate(visibility: visibility); try predecessor.validate()
        guard workspaceID == predecessor.workspaceID, claimID == predecessor.claimID,
              evidenceID == predecessor.evidenceID, supersedesLinkID == predecessor.linkID,
              predecessor.revision < UInt64.max, revision == predecessor.revision + 1,
              mutationID != predecessor.mutationID else { throw EvidenceAssuranceFailureV1.invalidTransition }
    }

    func rebound(to workspaceID: WorkspaceID, visibility: EvidenceVisibilityV1) throws -> Self {
        guard visibility.workspaceID == workspaceID else { throw EvidenceAssuranceFailureV1.invalidValue }
        return try Self(linkID: linkID, workspaceID: workspaceID, claimID: claimID, criterionID: criterionID,
                        evidenceID: evidenceID, evidenceRevision: evidenceRevision, evidenceSHA256: evidenceSHA256,
                        visibility: visibility, audience: decision.audience,
                        limitation: decision.limitation == .none ? nil : decision.limitation,
                        limitationNote: limitationNote, supersedesLinkID: supersedesLinkID,
                        revision: revision, mutationID: mutationID)
    }

    private var digestBasis: DigestBasis { .init(schemaVersion: schemaVersion, linkID: linkID, workspaceID: workspaceID,
        claimID: claimID, criterionID: criterionID, evidenceID: evidenceID, evidenceRevision: evidenceRevision,
        evidenceSHA256: evidenceSHA256, visibility: visibility,
        visibilityID: visibilityID, visibilityRevision: visibilityRevision,
        visibilitySHA256: visibilitySHA256, decision: decision, limitationNote: limitationNote,
        supersedesLinkID: supersedesLinkID, revision: revision, mutationID: mutationID) }
    private struct DigestBasis: Codable { let schemaVersion: Int; let linkID: UUID; let workspaceID: WorkspaceID
        let claimID: String; let criterionID: String?; let evidenceID: String?; let evidenceRevision: UInt64?
        let evidenceSHA256: String?; let visibility: EvidenceVisibilityV1
        let visibilityID: UUID; let visibilityRevision: UInt64; let visibilitySHA256: String
        let decision: EvidenceVisibilityDecisionV1; let limitationNote: String?; let supersedesLinkID: UUID?
        let revision: UInt64; let mutationID: MutationIDV1 }
}

struct AssuranceProjectionPreviewV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let previewID: UUID; let workspaceID: WorkspaceID
    let audience: EvidenceAudienceV1; let snapshotSHA256: String; let projectionVersion: String
    let sourceLinksSHA256: String; let includedLinks: [ClaimEvidenceLinkV1]; let excludedLinks: [ClaimEvidenceLinkV1]
    let createdAt: Date; let previewSHA256: String

    init(previewID: UUID, workspaceID: WorkspaceID, audience: EvidenceAudienceV1,
         snapshotSHA256: String, projectionVersion: String, links: [ClaimEvidenceLinkV1], createdAt: Date) throws {
        let ordered = links.sorted { $0.linkID.uuidString < $1.linkID.uuidString }
        let sourceDigest = try EvidenceAssuranceCanonicalCodecV1.sha256(ordered)
        let included = ordered.filter { $0.decision.disposition == .included }
        let excluded = ordered.filter { $0.decision.disposition == .excluded }
        schemaVersion = Self.schemaVersion; self.previewID = previewID; self.workspaceID = workspaceID
        self.audience = audience; self.snapshotSHA256 = snapshotSHA256; self.projectionVersion = projectionVersion
        sourceLinksSHA256 = sourceDigest
        includedLinks = included
        excludedLinks = excluded
        self.createdAt = createdAt
        previewSHA256 = try EvidenceAssuranceCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, previewID: previewID, workspaceID: workspaceID,
            audience: audience, snapshotSHA256: snapshotSHA256, projectionVersion: projectionVersion,
            sourceLinksSHA256: sourceDigest, includedLinks: included,
            excludedLinks: excluded, createdAt: createdAt
        ))
        try validate()
    }

    func validate() throws {
        try EvidenceAssuranceValidationV1.id(previewID); try EvidenceAssuranceValidationV1.workspace(workspaceID)
        try EvidenceAssuranceValidationV1.digest(snapshotSHA256); try EvidenceAssuranceValidationV1.digest(sourceLinksSHA256)
        try EvidenceAssuranceValidationV1.text(projectionVersion, maximum: EvidenceAssuranceLimitsV1.maximumProjectionVersionBytes)
        let all = (includedLinks + excludedLinks).sorted { $0.linkID.uuidString < $1.linkID.uuidString }
        try all.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion, all.count <= EvidenceAssuranceLimitsV1.maximumLinks,
              Set(all.map(\.linkID)).count == all.count,
              includedLinks == includedLinks.sorted(by: { $0.linkID.uuidString < $1.linkID.uuidString }),
              excludedLinks == excludedLinks.sorted(by: { $0.linkID.uuidString < $1.linkID.uuidString }),
              all.allSatisfy({ $0.workspaceID == workspaceID && $0.decision.audience == audience }),
              includedLinks.allSatisfy({ $0.decision.disposition == .included }),
              excludedLinks.allSatisfy({ $0.decision.disposition == .excluded }),
              sourceLinksSHA256 == (try EvidenceAssuranceCanonicalCodecV1.sha256(all)),
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              previewSHA256 == (try EvidenceAssuranceCanonicalCodecV1.sha256(digestBasis)) else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
    }

    func rebound(to workspaceID: WorkspaceID, links: [ClaimEvidenceLinkV1]) throws -> Self {
        guard links.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
        return try Self(previewID: previewID, workspaceID: workspaceID, audience: audience,
                        snapshotSHA256: snapshotSHA256, projectionVersion: projectionVersion,
                        links: links, createdAt: createdAt)
    }

    private var digestBasis: DigestBasis { .init(schemaVersion: schemaVersion, previewID: previewID, workspaceID: workspaceID,
        audience: audience, snapshotSHA256: snapshotSHA256, projectionVersion: projectionVersion,
        sourceLinksSHA256: sourceLinksSHA256, includedLinks: includedLinks, excludedLinks: excludedLinks, createdAt: createdAt) }
    private struct DigestBasis: Codable { let schemaVersion: Int; let previewID: UUID; let workspaceID: WorkspaceID
        let audience: EvidenceAudienceV1; let snapshotSHA256: String; let projectionVersion: String
        let sourceLinksSHA256: String; let includedLinks: [ClaimEvidenceLinkV1]; let excludedLinks: [ClaimEvidenceLinkV1]; let createdAt: Date }
}

struct AssuranceManifestV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let manifestID: UUID; let workspaceID: WorkspaceID
    let audience: EvidenceAudienceV1; let snapshotSHA256: String; let projectionVersion: String
    let sourcePreviewID: UUID; let sourcePreviewSHA256: String
    let includedLinks: [ClaimEvidenceLinkV1]; let excludedLinks: [ClaimEvidenceLinkV1]
    let recordedAt: Date; let supersedesManifestID: UUID?; let revision: UInt64; let mutationID: MutationIDV1
    let manifestSHA256: String

    init(manifestID: UUID, preview: AssuranceProjectionPreviewV1, recordedAt: Date,
         supersedesManifestID: UUID? = nil, revision: UInt64 = 1, mutationID: MutationIDV1) throws {
        try preview.validate()
        schemaVersion = Self.schemaVersion; self.manifestID = manifestID; workspaceID = preview.workspaceID
        audience = preview.audience; snapshotSHA256 = preview.snapshotSHA256; projectionVersion = preview.projectionVersion
        sourcePreviewID = preview.previewID; sourcePreviewSHA256 = preview.previewSHA256
        includedLinks = preview.includedLinks; excludedLinks = preview.excludedLinks; self.recordedAt = recordedAt
        self.supersedesManifestID = supersedesManifestID; self.revision = revision; self.mutationID = mutationID
        manifestSHA256 = try EvidenceAssuranceCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, manifestID: manifestID, workspaceID: preview.workspaceID,
            audience: preview.audience, snapshotSHA256: preview.snapshotSHA256,
            projectionVersion: preview.projectionVersion, sourcePreviewID: preview.previewID,
            sourcePreviewSHA256: preview.previewSHA256, includedLinks: preview.includedLinks,
            excludedLinks: preview.excludedLinks, recordedAt: recordedAt,
            supersedesManifestID: supersedesManifestID, revision: revision, mutationID: mutationID
        ))
        try validateFresh(preview: preview)
    }

    func validate() throws {
        try EvidenceAssuranceValidationV1.id(manifestID); try EvidenceAssuranceValidationV1.workspace(workspaceID)
        try EvidenceAssuranceValidationV1.id(sourcePreviewID)
        try EvidenceAssuranceValidationV1.digest(snapshotSHA256); try EvidenceAssuranceValidationV1.digest(sourcePreviewSHA256)
        try EvidenceAssuranceValidationV1.text(projectionVersion, maximum: EvidenceAssuranceLimitsV1.maximumProjectionVersionBytes)
        try EvidenceAssuranceValidationV1.revision(revision)
        if let supersedesManifestID { try EvidenceAssuranceValidationV1.id(supersedesManifestID) }
        let links = includedLinks + excludedLinks; try links.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              links.count <= EvidenceAssuranceLimitsV1.maximumLinks, Set(links.map(\.linkID)).count == links.count,
              includedLinks == includedLinks.sorted(by: { $0.linkID.uuidString < $1.linkID.uuidString }),
              excludedLinks == excludedLinks.sorted(by: { $0.linkID.uuidString < $1.linkID.uuidString }),
              links.allSatisfy({ $0.workspaceID == workspaceID && $0.decision.audience == audience }),
              includedLinks.allSatisfy({ $0.decision.disposition == .included }),
              excludedLinks.allSatisfy({ $0.decision.disposition == .excluded }),
              supersedesManifestID != manifestID, (supersedesManifestID == nil) == (revision == 1),
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              manifestSHA256 == (try EvidenceAssuranceCanonicalCodecV1.sha256(digestBasis)) else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
    }

    func validateFresh(preview: AssuranceProjectionPreviewV1) throws {
        try validate(); try preview.validate()
        guard workspaceID == preview.workspaceID, audience == preview.audience,
              snapshotSHA256 == preview.snapshotSHA256, projectionVersion == preview.projectionVersion,
              sourcePreviewID == preview.previewID, sourcePreviewSHA256 == preview.previewSHA256,
              includedLinks == preview.includedLinks, excludedLinks == preview.excludedLinks,
              recordedAt >= preview.createdAt else {
            throw EvidenceAssuranceFailureV1.stalePreview
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try validate(); try predecessor.validate()
        guard workspaceID == predecessor.workspaceID, audience == predecessor.audience,
              supersedesManifestID == predecessor.manifestID,
              predecessor.revision < UInt64.max, revision == predecessor.revision + 1,
              recordedAt >= predecessor.recordedAt, mutationID != predecessor.mutationID else {
            throw EvidenceAssuranceFailureV1.invalidTransition
        }
    }

    func rebound(to workspaceID: WorkspaceID, preview: AssuranceProjectionPreviewV1) throws -> Self {
        guard preview.workspaceID == workspaceID else { throw EvidenceAssuranceFailureV1.invalidValue }
        return try Self(manifestID: manifestID, preview: preview, recordedAt: recordedAt,
                        supersedesManifestID: supersedesManifestID, revision: revision,
                        mutationID: mutationID)
    }

    private var digestBasis: DigestBasis { .init(schemaVersion: schemaVersion, manifestID: manifestID, workspaceID: workspaceID,
        audience: audience, snapshotSHA256: snapshotSHA256, projectionVersion: projectionVersion,
        sourcePreviewID: sourcePreviewID, sourcePreviewSHA256: sourcePreviewSHA256,
        includedLinks: includedLinks, excludedLinks: excludedLinks, recordedAt: recordedAt,
        supersedesManifestID: supersedesManifestID, revision: revision, mutationID: mutationID) }
    private struct DigestBasis: Codable { let schemaVersion: Int; let manifestID: UUID; let workspaceID: WorkspaceID
        let audience: EvidenceAudienceV1; let snapshotSHA256: String; let projectionVersion: String
        let sourcePreviewID: UUID; let sourcePreviewSHA256: String; let includedLinks: [ClaimEvidenceLinkV1]
        let excludedLinks: [ClaimEvidenceLinkV1]; let recordedAt: Date; let supersedesManifestID: UUID?
        let revision: UInt64; let mutationID: MutationIDV1 }
}

enum AttestationPurposeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case acknowledgeEvidence = "ACKNOWLEDGE_EVIDENCE"
    case acknowledgeReport = "ACKNOWLEDGE_REPORT"
    case confirmLocalReview = "CONFIRM_LOCAL_REVIEW"
}
enum AttestationMethodV1: String, CaseIterable, Codable, Hashable, Sendable {
    case explicitLocalConfirmation = "EXPLICIT_LOCAL_CONFIRMATION"
    case importedExternalEvidence = "IMPORTED_EXTERNAL_EVIDENCE"
}
enum AttestationActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case recorded = "RECORDED"; case superseded = "SUPERSEDED"; case voided = "VOIDED"
}
enum AttestationScopeKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case activitySnapshot = "ACTIVITY_SNAPSHOT"; case reportSnapshot = "REPORT_SNAPSHOT"
    case assuranceManifest = "ASSURANCE_MANIFEST"
}

struct AttestationScopeV1: Codable, Equatable, Hashable, Sendable {
    let kind: AttestationScopeKindV1; let scopeID: UUID; let scopeRevision: UInt64
    init(kind: AttestationScopeKindV1, scopeID: UUID, scopeRevision: UInt64) throws {
        try EvidenceAssuranceValidationV1.id(scopeID); try EvidenceAssuranceValidationV1.revision(scopeRevision)
        self.kind = kind; self.scopeID = scopeID; self.scopeRevision = scopeRevision
    }
    func validate() throws {
        try EvidenceAssuranceValidationV1.id(scopeID)
        try EvidenceAssuranceValidationV1.revision(scopeRevision)
    }
}

/// A local purpose-bound assertion only. It is not identity verification,
/// approval, authorship, certification, a legal signature, or nonrepudiation.
struct AttestationV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let attestationID: UUID; let workspaceID: WorkspaceID
    let purpose: AttestationPurposeV1; let scope: AttestationScopeV1
    let manifestID: UUID; let manifestRevision: UInt64; let manifestSHA256: String; let snapshotSHA256: String
    let declaredActor: LocalActorReferenceV1; let method: AttestationMethodV1; let action: AttestationActionV1
    let occurredAt: Date; let recordedAt: Date; let supersedesAttestationID: UUID?
    let revision: UInt64; let mutationID: MutationIDV1; let attestationSHA256: String

    init(attestationID: UUID, workspaceID: WorkspaceID, purpose: AttestationPurposeV1,
         scope: AttestationScopeV1, manifest: AssuranceManifestV1,
         declaredActor: LocalActorReferenceV1, method: AttestationMethodV1,
         action: AttestationActionV1 = .recorded, occurredAt: Date, recordedAt: Date,
         supersedesAttestationID: UUID? = nil, revision: UInt64 = 1,
         mutationID: MutationIDV1) throws {
        try manifest.validate(); try declaredActor.validate()
        schemaVersion = Self.schemaVersion; self.attestationID = attestationID; self.workspaceID = workspaceID
        self.purpose = purpose; self.scope = scope; manifestID = manifest.manifestID; manifestRevision = manifest.revision
        manifestSHA256 = manifest.manifestSHA256; snapshotSHA256 = manifest.snapshotSHA256
        self.declaredActor = declaredActor; self.method = method; self.action = action
        self.occurredAt = occurredAt; self.recordedAt = recordedAt
        self.supersedesAttestationID = supersedesAttestationID; self.revision = revision; self.mutationID = mutationID
        attestationSHA256 = try EvidenceAssuranceCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, attestationID: attestationID, workspaceID: workspaceID,
            purpose: purpose, scope: scope, manifestID: manifest.manifestID,
            manifestRevision: manifest.revision, manifestSHA256: manifest.manifestSHA256,
            snapshotSHA256: manifest.snapshotSHA256, declaredActor: declaredActor,
            method: method, action: action, occurredAt: occurredAt, recordedAt: recordedAt,
            supersedesAttestationID: supersedesAttestationID, revision: revision, mutationID: mutationID
        )); try validate(manifest: manifest)
    }

    func validate() throws {
        try EvidenceAssuranceValidationV1.id(attestationID); try EvidenceAssuranceValidationV1.workspace(workspaceID)
        try EvidenceAssuranceValidationV1.id(manifestID); try EvidenceAssuranceValidationV1.revision(manifestRevision)
        try EvidenceAssuranceValidationV1.digest(manifestSHA256); try EvidenceAssuranceValidationV1.digest(snapshotSHA256)
        try declaredActor.validate(); try scope.validate(); try EvidenceAssuranceValidationV1.revision(revision)
        if let supersedesAttestationID { try EvidenceAssuranceValidationV1.id(supersedesAttestationID) }
        guard schemaVersion == Self.schemaVersion, declaredActor.workspaceID == workspaceID, recordedAt >= occurredAt,
              occurredAt.timeIntervalSinceReferenceDate.isFinite, recordedAt.timeIntervalSinceReferenceDate.isFinite,
              supersedesAttestationID != attestationID,
              (action == .recorded) == (supersedesAttestationID == nil),
              (supersedesAttestationID == nil) == (revision == 1),
              attestationSHA256 == (try EvidenceAssuranceCanonicalCodecV1.sha256(digestBasis)) else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
    }

    func validate(manifest: AssuranceManifestV1) throws {
        try validate(); try manifest.validate()
        guard manifest.workspaceID == workspaceID, manifest.manifestID == manifestID,
              manifest.revision == manifestRevision, manifest.manifestSHA256 == manifestSHA256,
              manifest.snapshotSHA256 == snapshotSHA256,
              recordedAt >= manifest.recordedAt,
              scope.kind != .assuranceManifest
                || (scope.scopeID == manifestID && scope.scopeRevision == manifestRevision) else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try validate(); try predecessor.validate()
        guard predecessor.action != .voided, action != .recorded,
              workspaceID == predecessor.workspaceID, supersedesAttestationID == predecessor.attestationID,
              predecessor.revision < UInt64.max, revision == predecessor.revision + 1,
              purpose == predecessor.purpose, scope == predecessor.scope,
              action != .voided || (
                manifestID == predecessor.manifestID
                    && manifestRevision == predecessor.manifestRevision
                    && manifestSHA256 == predecessor.manifestSHA256
                    && snapshotSHA256 == predecessor.snapshotSHA256
              ),
              occurredAt >= predecessor.occurredAt, recordedAt >= predecessor.recordedAt,
              mutationID != predecessor.mutationID else { throw EvidenceAssuranceFailureV1.invalidTransition }
    }

    func rebound(to workspaceID: WorkspaceID, manifest: AssuranceManifestV1) throws -> Self {
        let actor = try LocalActorReferenceV1(actorReferenceID: declaredActor.actorReferenceID,
            workspaceID: workspaceID, partyID: declaredActor.partyID, displayName: declaredActor.displayName)
        return try Self(attestationID: attestationID, workspaceID: workspaceID, purpose: purpose,
                        scope: scope, manifest: manifest, declaredActor: actor, method: method,
                        action: action, occurredAt: occurredAt, recordedAt: recordedAt,
                        supersedesAttestationID: supersedesAttestationID, revision: revision, mutationID: mutationID)
    }

    private var digestBasis: DigestBasis { .init(schemaVersion: schemaVersion, attestationID: attestationID,
        workspaceID: workspaceID, purpose: purpose, scope: scope, manifestID: manifestID,
        manifestRevision: manifestRevision, manifestSHA256: manifestSHA256, snapshotSHA256: snapshotSHA256,
        declaredActor: declaredActor, method: method, action: action, occurredAt: occurredAt,
        recordedAt: recordedAt, supersedesAttestationID: supersedesAttestationID,
        revision: revision, mutationID: mutationID) }
    private struct DigestBasis: Codable { let schemaVersion: Int; let attestationID: UUID; let workspaceID: WorkspaceID
        let purpose: AttestationPurposeV1; let scope: AttestationScopeV1; let manifestID: UUID; let manifestRevision: UInt64
        let manifestSHA256: String; let snapshotSHA256: String; let declaredActor: LocalActorReferenceV1
        let method: AttestationMethodV1; let action: AttestationActionV1; let occurredAt: Date; let recordedAt: Date
        let supersedesAttestationID: UUID?; let revision: UInt64; let mutationID: MutationIDV1 }
}

protocol EvidenceAssuranceValidatableV1 { func validate() throws }
extension EvidenceVisibilityV1: EvidenceAssuranceValidatableV1 {}
extension EvidenceVisibilityDecisionV1: EvidenceAssuranceValidatableV1 {}
extension ClaimEvidenceLinkV1: EvidenceAssuranceValidatableV1 {}
extension AssuranceProjectionPreviewV1: EvidenceAssuranceValidatableV1 {}
extension AssuranceManifestV1: EvidenceAssuranceValidatableV1 {}
extension AttestationV1: EvidenceAssuranceValidatableV1 {}
extension AttestationScopeV1: EvidenceAssuranceValidatableV1 {}

enum EvidenceAssuranceCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func sha256<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= 8_388_608 else { throw EvidenceAssuranceFailureV1.nonCanonicalData }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        if let validatable = value as? any EvidenceAssuranceValidatableV1 { try validatable.validate() }
        guard try encode(value) == data else { throw EvidenceAssuranceFailureV1.nonCanonicalData }
        return value
    }
}

extension ClaimEvidenceLinkV1 {
    /// Exact immutable evidence reference for C14. Visibility remains C13
    /// truth and this conversion never implies review acceptance.
    func inspectionReviewEvidenceReference() throws -> ReviewEvidenceReferenceV1 {
        try validate()
        guard evidenceID != nil, evidenceRevision != nil, evidenceSHA256 != nil,
              decision.limitation != .evidenceUnavailable,
              decision.limitation != .evidenceInvalid else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
        return try .init(kind: .claimEvidenceLink,
                         referenceID: linkID.uuidString.lowercased(),
                         revision: revision, sha256: linkSHA256)
    }
}

extension AssuranceManifestV1 {
    func validateInspectionReviewBinding(id: UUID, revision: UInt64, sha256: String,
                                         workspaceID: WorkspaceID) throws {
        try validate()
        guard manifestID == id, self.revision == revision, manifestSHA256 == sha256,
              self.workspaceID == workspaceID else { throw EvidenceAssuranceFailureV1.invalidValue }
    }
}
