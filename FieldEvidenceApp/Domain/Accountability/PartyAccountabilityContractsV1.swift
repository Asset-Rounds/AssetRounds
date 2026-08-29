import Foundation

enum ScheduleAssigneeBoundaryV1 {
    static func validate(_ actor: ActorSnapshotV1, workspaceID: WorkspaceID) throws {
        try actor.validate()
        guard actor.workspaceID == workspaceID, actor.responsibility == .assignedTo else { throw ScheduleFailureV1.wrongWorkspace }
    }
}

enum PartyAccountabilityFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case unknownKey
    case missingKey
    case staleRevision
    case crossWorkspaceReference
    case invalidInterval
    case digestMismatch
    case unsupportedClaim
    case immutableHistory
    case limitExceeded
}

enum PartyAccountabilityLimitsV1 {
    static let maximumDisplayNameBytes = 256
    static let maximumDescriptorBytes = 1_024
    static let maximumPurposeBytes = 512
    static let maximumLocatorBytes = 1_024
}

enum PartyAccountabilityValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func requireID(_ value: UUID) throws {
        guard value != zero else { throw PartyAccountabilityFailureV1.invalidValue }
    }

    static func requireWorkspace(_ value: WorkspaceID) throws { try requireID(value.rawValue) }

    static func requireText(_ value: String, maximumBytes: Int, allowEmpty: Bool = false) throws {
        guard (allowEmpty || !value.isEmpty), value.utf8.count <= maximumBytes,
              value == value.precomposedStringWithCanonicalMapping else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        for scalar in value.unicodeScalars {
            let n = scalar.value
            guard n >= 0x20, n != 0x7f, !(0x80...0x9f).contains(n),
                  ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069].contains(n),
                  (n & 0xffff) != 0xfffe, (n & 0xffff) != 0xffff else {
                throw PartyAccountabilityFailureV1.invalidValue
            }
        }
    }

    static func requireDigest(_ value: String) throws {
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw PartyAccountabilityFailureV1.digestMismatch
        }
    }
}

private enum PartyAccountabilityClosedCodingV1 {
    static func require<Key: CodingKey & CaseIterable>(_ decoder: Decoder, _ keys: Key.Type) throws
    where Key.AllCases: Collection {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let actual = Set(raw.allKeys.map(\.stringValue))
        let expected = Set(Key.allCases.map(\.stringValue))
        guard actual.isSubset(of: expected) else { throw PartyAccountabilityFailureV1.unknownKey }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }
}

enum ServicePartyKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case person = "PERSON"
    case organization = "ORGANIZATION"
}

enum ServicePartyProvenanceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case locallyRecorded = "LOCALLY_RECORDED"
    case importedExternalEvidence = "IMPORTED_EXTERNAL_EVIDENCE"
    case migratedBaseline = "MIGRATED_BASELINE"
}

enum ServicePartyPrivacyClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case workspaceCustomerData = "WORKSPACE_CUSTOMER_DATA"
}

enum ServicePartyStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case effective = "EFFECTIVE"
    case retired = "RETIRED"
}

struct ServicePartyReferenceV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let partyID: UUID
    let workspaceID: WorkspaceID
    let kind: ServicePartyKindV1
    let displayName: String
    /// Optional non-channel context only; never an email, phone, login, or address field.
    let profileDescriptor: String?
    let provenance: ServicePartyProvenanceV1
    let privacyClass: ServicePartyPrivacyClassV1
    let state: ServicePartyStateV1
    let effectiveAt: Date
    let retiredAt: Date?
    let revision: UInt64
    let mutationID: MutationIDV1
    let receiptSHA256: String

    init(partyID: UUID, workspaceID: WorkspaceID, kind: ServicePartyKindV1, displayName: String,
         profileDescriptor: String? = nil, provenance: ServicePartyProvenanceV1,
         privacyClass: ServicePartyPrivacyClassV1 = .workspaceCustomerData, state: ServicePartyStateV1,
         effectiveAt: Date, retiredAt: Date? = nil, revision: UInt64, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.partyID = partyID; self.workspaceID = workspaceID; self.kind = kind
        self.displayName = displayName; self.profileDescriptor = profileDescriptor; self.provenance = provenance
        self.privacyClass = privacyClass; self.state = state; self.effectiveAt = effectiveAt; self.retiredAt = retiredAt
        self.revision = revision; self.mutationID = mutationID
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, partyID: partyID,
            workspaceID: workspaceID, kind: kind, displayName: displayName, profileDescriptor: profileDescriptor,
            provenance: provenance, privacyClass: privacyClass, state: state, effectiveAt: effectiveAt,
            retiredAt: retiredAt, revision: revision, mutationID: mutationID))
        try validate()
    }

    func validate() throws {
        try PartyAccountabilityValidationV1.requireID(partyID); try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try PartyAccountabilityValidationV1.requireText(displayName, maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes)
        if let profileDescriptor { try PartyAccountabilityValidationV1.requireText(profileDescriptor, maximumBytes: PartyAccountabilityLimitsV1.maximumDescriptorBytes) }
        let intervalIsExact = state == .effective ? retiredAt == nil : retiredAt.map { $0 >= effectiveAt } == true
        guard schemaVersion == Self.schemaVersion, revision > 0, intervalIsExact,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, partyID: partyID,
                workspaceID: workspaceID, kind: kind, displayName: displayName, profileDescriptor: profileDescriptor,
                provenance: provenance, privacyClass: privacyClass, state: state, effectiveAt: effectiveAt,
                retiredAt: retiredAt, revision: revision, mutationID: mutationID))) else {
            throw PartyAccountabilityFailureV1.digestMismatch
        }
    }

    private struct Basis: Codable { let schemaVersion: Int; let partyID: UUID; let workspaceID: WorkspaceID; let kind: ServicePartyKindV1; let displayName: String; let profileDescriptor: String?; let provenance: ServicePartyProvenanceV1; let privacyClass: ServicePartyPrivacyClassV1; let state: ServicePartyStateV1; let effectiveAt: Date; let retiredAt: Date?; let revision: UInt64; let mutationID: MutationIDV1 }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, partyID, workspaceID, kind, displayName, profileDescriptor, provenance, privacyClass, state, effectiveAt, retiredAt, revision, mutationID, receiptSHA256 }
    init(from decoder: Decoder) throws {
        try PartyAccountabilityClosedCodingV1.require(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }
        try self.init(partyID: c.decode(UUID.self, forKey: .partyID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), kind: c.decode(ServicePartyKindV1.self, forKey: .kind), displayName: c.decode(String.self, forKey: .displayName), profileDescriptor: c.decodeIfPresent(String.self, forKey: .profileDescriptor), provenance: c.decode(ServicePartyProvenanceV1.self, forKey: .provenance), privacyClass: c.decode(ServicePartyPrivacyClassV1.self, forKey: .privacyClass), state: c.decode(ServicePartyStateV1.self, forKey: .state), effectiveAt: c.decode(Date.self, forKey: .effectiveAt), retiredAt: c.decodeIfPresent(Date.self, forKey: .retiredAt), revision: c.decode(UInt64.self, forKey: .revision), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID))
        guard try c.decode(String.self, forKey: .receiptSHA256) == receiptSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
    }
}

enum SitePartyRoleV1: String, Codable, CaseIterable, Hashable, Sendable {
    case owner = "OWNER"; case `operator` = "OPERATOR"; case client = "CLIENT"
    case serviceProvider = "SERVICE_PROVIDER"; case contact = "CONTACT"
}

enum SitePartyRoleSourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case locallyRecorded = "LOCALLY_RECORDED"
    case importedExternalEvidence = "IMPORTED_EXTERNAL_EVIDENCE"
    case migratedBaseline = "MIGRATED_BASELINE"
}

struct SitePartyRoleEventV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let eventID: UUID; let workspaceID: WorkspaceID; let siteID: UUID; let partyID: UUID
    let role: SitePartyRoleV1; let effectiveFrom: Date; let effectiveUntil: Date?; let source: SitePartyRoleSourceV1
    let supersedesEventID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date; let receiptSHA256: String

    init(eventID: UUID, workspaceID: WorkspaceID, siteID: UUID, partyID: UUID, role: SitePartyRoleV1,
         effectiveFrom: Date, effectiveUntil: Date? = nil, source: SitePartyRoleSourceV1,
         supersedesEventID: UUID? = nil, revision: UInt64, mutationID: MutationIDV1, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.eventID = eventID; self.workspaceID = workspaceID; self.siteID = siteID
        self.partyID = partyID; self.role = role; self.effectiveFrom = effectiveFrom; self.effectiveUntil = effectiveUntil
        self.source = source; self.supersedesEventID = supersedesEventID; self.revision = revision
        self.mutationID = mutationID; self.recordedAt = recordedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, eventID: eventID,
            workspaceID: workspaceID, siteID: siteID, partyID: partyID, role: role, effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil, source: source, supersedesEventID: supersedesEventID, revision: revision,
            mutationID: mutationID, recordedAt: recordedAt)); try validate()
    }
    func validate() throws {
        try [eventID, siteID, partyID].forEach(PartyAccountabilityValidationV1.requireID); try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        if let supersedesEventID { try PartyAccountabilityValidationV1.requireID(supersedesEventID); guard supersedesEventID != eventID else { throw PartyAccountabilityFailureV1.invalidValue } }
        guard schemaVersion == Self.schemaVersion, revision > 0, recordedAt >= effectiveFrom,
              effectiveUntil.map { $0 >= effectiveFrom } ?? true,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, eventID: eventID,
                workspaceID: workspaceID, siteID: siteID, partyID: partyID, role: role, effectiveFrom: effectiveFrom,
                effectiveUntil: effectiveUntil, source: source, supersedesEventID: supersedesEventID, revision: revision,
                mutationID: mutationID, recordedAt: recordedAt))) else { throw PartyAccountabilityFailureV1.invalidInterval }
    }
    private struct Basis: Codable { let schemaVersion: Int; let eventID: UUID; let workspaceID: WorkspaceID; let siteID: UUID; let partyID: UUID; let role: SitePartyRoleV1; let effectiveFrom: Date; let effectiveUntil: Date?; let source: SitePartyRoleSourceV1; let supersedesEventID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date }
}

struct LocalActorReferenceV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let actorReferenceID: UUID; let workspaceID: WorkspaceID; let partyID: UUID?; let displayName: String
    init(actorReferenceID: UUID, workspaceID: WorkspaceID, partyID: UUID? = nil, displayName: String) throws {
        schemaVersion = Self.schemaVersion; self.actorReferenceID = actorReferenceID; self.workspaceID = workspaceID; self.partyID = partyID; self.displayName = displayName; try validate()
    }
    func validate() throws { try PartyAccountabilityValidationV1.requireID(actorReferenceID); try PartyAccountabilityValidationV1.requireWorkspace(workspaceID); if let partyID { try PartyAccountabilityValidationV1.requireID(partyID) }; try PartyAccountabilityValidationV1.requireText(displayName, maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes); guard schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion } }
}

enum ResponsibilityKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case recordedBy = "RECORDED_BY"; case performedBy = "PERFORMED_BY"; case observedBy = "OBSERVED_BY"
    case reviewedBy = "REVIEWED_BY"; case verifiedBy = "VERIFIED_BY"; case approvedBy = "APPROVED_BY"
    case acknowledgedBy = "ACKNOWLEDGED_BY"; case assignedTo = "ASSIGNED_TO"; case witnessedBy = "WITNESSED_BY"
}

struct ActorSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let actor: LocalActorReferenceV1
    let responsibility: ResponsibilityKindV1; let displayNameAtTime: String; let capturedAt: Date; let snapshotSHA256: String
    init(snapshotID: UUID, workspaceID: WorkspaceID, actor: LocalActorReferenceV1, responsibility: ResponsibilityKindV1, displayNameAtTime: String, capturedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.snapshotID = snapshotID; self.workspaceID = workspaceID; self.actor = actor; self.responsibility = responsibility; self.displayNameAtTime = displayNameAtTime; self.capturedAt = capturedAt
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID, actor: actor, responsibility: responsibility, displayNameAtTime: displayNameAtTime, capturedAt: capturedAt)); try validate()
    }
    func validate() throws { try PartyAccountabilityValidationV1.requireID(snapshotID); try PartyAccountabilityValidationV1.requireWorkspace(workspaceID); try actor.validate(); try PartyAccountabilityValidationV1.requireText(displayNameAtTime, maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes); guard schemaVersion == Self.schemaVersion, actor.workspaceID == workspaceID, actor.displayName == displayNameAtTime, snapshotSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID, actor: actor, responsibility: responsibility, displayNameAtTime: displayNameAtTime, capturedAt: capturedAt))) else { throw PartyAccountabilityFailureV1.digestMismatch } }
    private struct Basis: Codable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let actor: LocalActorReferenceV1; let responsibility: ResponsibilityKindV1; let displayNameAtTime: String; let capturedAt: Date }
}

// MARK: - C20 reviewed-derivative reviewer boundary

extension ActorSnapshotV1 {
    /// C20 review requires an explicit reviewed-by actor snapshot in the same
    /// workspace. The snapshot remains a bounded recorded responsibility and
    /// is never promoted to a verified-person or privacy/compliance claim.
    func c20ValidatePrivacyReviewer(in workspaceID: WorkspaceID) throws {
        try validate()
        guard self.workspaceID == workspaceID else {
            throw PrivacyTransformFailureV1.wrongWorkspace
        }
        guard responsibility == .reviewedBy else {
            throw PrivacyTransformFailureV1.reviewRequired
        }
    }
}

enum QualificationProvenanceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case selfDeclared = "SELF_DECLARED"
    case importedExternalEvidence = "IMPORTED_EXTERNAL_EVIDENCE"
}

struct QualificationSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let declaredScope: String
    let issuerDisplay: String?; let credentialLocator: String?; let effectiveAt: Date?; let expiresAt: Date?
    let provenance: QualificationProvenanceV1; let capturedAt: Date; let snapshotSHA256: String
    init(snapshotID: UUID, workspaceID: WorkspaceID, declaredScope: String, issuerDisplay: String? = nil,
         credentialLocator: String? = nil, effectiveAt: Date? = nil, expiresAt: Date? = nil,
         provenance: QualificationProvenanceV1, capturedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.snapshotID = snapshotID; self.workspaceID = workspaceID; self.declaredScope = declaredScope
        self.issuerDisplay = issuerDisplay; self.credentialLocator = credentialLocator; self.effectiveAt = effectiveAt
        self.expiresAt = expiresAt; self.provenance = provenance; self.capturedAt = capturedAt
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, snapshotID: snapshotID,
            workspaceID: workspaceID, declaredScope: declaredScope, issuerDisplay: issuerDisplay, credentialLocator: credentialLocator,
            effectiveAt: effectiveAt, expiresAt: expiresAt, provenance: provenance, capturedAt: capturedAt)); try validate()
    }
    func validate() throws {
        try PartyAccountabilityValidationV1.requireID(snapshotID); try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try PartyAccountabilityValidationV1.requireText(declaredScope, maximumBytes: PartyAccountabilityLimitsV1.maximumDescriptorBytes)
        if let issuerDisplay { try PartyAccountabilityValidationV1.requireText(issuerDisplay, maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes) }
        if let credentialLocator { try PartyAccountabilityValidationV1.requireText(credentialLocator, maximumBytes: PartyAccountabilityLimitsV1.maximumLocatorBytes) }
        guard schemaVersion == Self.schemaVersion,
              expiresAt.map { expiry in effectiveAt.map { $0 <= expiry } ?? true } ?? true,
              snapshotSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, snapshotID: snapshotID,
                workspaceID: workspaceID, declaredScope: declaredScope, issuerDisplay: issuerDisplay, credentialLocator: credentialLocator,
                effectiveAt: effectiveAt, expiresAt: expiresAt, provenance: provenance, capturedAt: capturedAt))) else { throw PartyAccountabilityFailureV1.digestMismatch }
    }
    private struct Basis: Codable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let declaredScope: String; let issuerDisplay: String?; let credentialLocator: String?; let effectiveAt: Date?; let expiresAt: Date?; let provenance: QualificationProvenanceV1; let capturedAt: Date }
}

enum SignoffDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case recordedLocalAssertion = "RECORDED_LOCAL_ASSERTION"
    case externalEvidenceAttached = "EXTERNAL_EVIDENCE_ATTACHED"
    case notRecorded = "NOT_RECORDED"
    case notApplicable = "NOT_APPLICABLE"
}

enum SignoffMethodV1: String, Codable, CaseIterable, Hashable, Sendable {
    case typedLocalAssertion = "TYPED_LOCAL_ASSERTION"
    case explicitLocalAcknowledgement = "EXPLICIT_LOCAL_ACKNOWLEDGEMENT"
    case externalEvidenceReference = "EXTERNAL_EVIDENCE_REFERENCE"
    case noAssertion = "NO_ASSERTION"
}

struct SignoffIntentDisclosureReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let releaseID: String; let disclosureText: String
    let statesLocalAssertionOnly: Bool; let disclaimsIdentityVerification: Bool; let disclaimsLegalSignature: Bool
    init(releaseID: String, disclosureText: String, statesLocalAssertionOnly: Bool = true,
         disclaimsIdentityVerification: Bool = true, disclaimsLegalSignature: Bool = true) throws {
        schemaVersion = Self.schemaVersion; self.releaseID = releaseID; self.disclosureText = disclosureText
        self.statesLocalAssertionOnly = statesLocalAssertionOnly; self.disclaimsIdentityVerification = disclaimsIdentityVerification
        self.disclaimsLegalSignature = disclaimsLegalSignature; try validate()
    }
    func validate() throws { try PartyAccountabilityValidationV1.requireText(releaseID, maximumBytes: 128); try PartyAccountabilityValidationV1.requireText(disclosureText, maximumBytes: PartyAccountabilityLimitsV1.maximumDescriptorBytes); guard schemaVersion == Self.schemaVersion, statesLocalAssertionOnly, disclaimsIdentityVerification, disclaimsLegalSignature else { throw PartyAccountabilityFailureV1.unsupportedClaim } }
}

struct SignoffRoleAssertionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let claimedRole: String; let claimedRelationship: SitePartyRoleV1?; let actor: ActorSnapshotV1; let disclosureRelease: SignoffIntentDisclosureReleaseV1
    init(claimedRole: String, claimedRelationship: SitePartyRoleV1? = nil, actor: ActorSnapshotV1, disclosureRelease: SignoffIntentDisclosureReleaseV1) throws {
        schemaVersion = Self.schemaVersion; self.claimedRole = claimedRole; self.claimedRelationship = claimedRelationship; self.actor = actor; self.disclosureRelease = disclosureRelease; try validate()
    }
    func validate() throws { try PartyAccountabilityValidationV1.requireText(claimedRole, maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes); try actor.validate(); try disclosureRelease.validate(); guard schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion } }
}

struct SignoffSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let purpose: String
    let subjectID: UUID; let subjectRevision: UInt64; let disposition: SignoffDispositionV1; let method: SignoffMethodV1
    let roleAssertion: SignoffRoleAssertionV1?; let qualification: QualificationSnapshotV1?; let externalEvidenceID: UUID?
    let occurredAt: Date?; let recordedAt: Date; let supersedesSnapshotID: UUID?; let mutationID: MutationIDV1; let snapshotSHA256: String
    init(snapshotID: UUID, workspaceID: WorkspaceID, purpose: String, subjectID: UUID, subjectRevision: UInt64,
         disposition: SignoffDispositionV1, method: SignoffMethodV1, roleAssertion: SignoffRoleAssertionV1? = nil,
         qualification: QualificationSnapshotV1? = nil, externalEvidenceID: UUID? = nil, occurredAt: Date? = nil,
         recordedAt: Date, supersedesSnapshotID: UUID? = nil, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.snapshotID = snapshotID; self.workspaceID = workspaceID; self.purpose = purpose
        self.subjectID = subjectID; self.subjectRevision = subjectRevision; self.disposition = disposition; self.method = method
        self.roleAssertion = roleAssertion; self.qualification = qualification; self.externalEvidenceID = externalEvidenceID
        self.occurredAt = occurredAt; self.recordedAt = recordedAt; self.supersedesSnapshotID = supersedesSnapshotID; self.mutationID = mutationID
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, snapshotID: snapshotID,
            workspaceID: workspaceID, purpose: purpose, subjectID: subjectID, subjectRevision: subjectRevision,
            disposition: disposition, method: method, roleAssertion: roleAssertion, qualification: qualification,
            externalEvidenceID: externalEvidenceID, occurredAt: occurredAt, recordedAt: recordedAt,
            supersedesSnapshotID: supersedesSnapshotID, mutationID: mutationID)); try validate()
    }
    func validate() throws {
        try [snapshotID, subjectID].forEach(PartyAccountabilityValidationV1.requireID); try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try PartyAccountabilityValidationV1.requireText(purpose, maximumBytes: PartyAccountabilityLimitsV1.maximumPurposeBytes)
        if let roleAssertion { try roleAssertion.validate(); guard roleAssertion.actor.workspaceID == workspaceID else { throw PartyAccountabilityFailureV1.crossWorkspaceReference } }
        if let qualification { try qualification.validate(); guard qualification.workspaceID == workspaceID else { throw PartyAccountabilityFailureV1.crossWorkspaceReference } }
        if let externalEvidenceID { try PartyAccountabilityValidationV1.requireID(externalEvidenceID) }
        if let supersedesSnapshotID { try PartyAccountabilityValidationV1.requireID(supersedesSnapshotID); guard supersedesSnapshotID != snapshotID else { throw PartyAccountabilityFailureV1.invalidValue } }
        let semanticShape: Bool
        switch disposition {
        case .recordedLocalAssertion: semanticShape = roleAssertion != nil && externalEvidenceID == nil && occurredAt != nil && (method == .typedLocalAssertion || method == .explicitLocalAcknowledgement)
        case .externalEvidenceAttached: semanticShape = roleAssertion != nil && externalEvidenceID != nil && occurredAt != nil && method == .externalEvidenceReference
        case .notRecorded, .notApplicable: semanticShape = roleAssertion == nil && qualification == nil && externalEvidenceID == nil && occurredAt == nil && method == .noAssertion
        }
        guard schemaVersion == Self.schemaVersion, subjectRevision > 0, semanticShape,
              occurredAt.map { $0 <= recordedAt } ?? true,
              snapshotSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, snapshotID: snapshotID,
                workspaceID: workspaceID, purpose: purpose, subjectID: subjectID, subjectRevision: subjectRevision,
                disposition: disposition, method: method, roleAssertion: roleAssertion, qualification: qualification,
                externalEvidenceID: externalEvidenceID, occurredAt: occurredAt, recordedAt: recordedAt,
                supersedesSnapshotID: supersedesSnapshotID, mutationID: mutationID))) else { throw PartyAccountabilityFailureV1.unsupportedClaim }
    }
    private struct Basis: Codable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let purpose: String; let subjectID: UUID; let subjectRevision: UInt64; let disposition: SignoffDispositionV1; let method: SignoffMethodV1; let roleAssertion: SignoffRoleAssertionV1?; let qualification: QualificationSnapshotV1?; let externalEvidenceID: UUID?; let occurredAt: Date?; let recordedAt: Date; let supersedesSnapshotID: UUID?; let mutationID: MutationIDV1 }
}

extension SitePartyRoleEventV1 {
    func validateSupersession(of predecessor: SitePartyRoleEventV1) throws {
        try predecessor.validate(); try validate()
        let nextRevision = predecessor.revision.addingReportingOverflow(1)
        guard supersedesEventID == predecessor.eventID, workspaceID == predecessor.workspaceID,
              siteID == predecessor.siteID, partyID == predecessor.partyID, role == predecessor.role,
              !nextRevision.overflow, revision == nextRevision.partialValue,
              recordedAt >= predecessor.recordedAt,
              effectiveFrom >= predecessor.effectiveFrom else { throw PartyAccountabilityFailureV1.immutableHistory }
    }

    func validatePartyReference(_ party: ServicePartyReferenceV1) throws {
        try party.validate(); try validate()
        guard workspaceID == party.workspaceID, partyID == party.partyID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
    }
}

// MARK: - C19 measurement accountability bridge

extension ActorSnapshotV1 {
    /// A measurement operator is a captured local responsibility, never an
    /// identity or qualification claim. C19 accepts only the two roles that
    /// can author a local capture.
    func c19ValidateMeasurementOperator(in workspaceID: WorkspaceID) throws {
        try validate()
        guard self.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        guard responsibility == .performedBy || responsibility == .recordedBy else {
            throw PartyAccountabilityFailureV1.unsupportedClaim
        }
    }

    /// Quality review requires an explicitly reviewed-by actor snapshot. It
    /// is kept separate from operator validation so a capture cannot be
    /// silently treated as its own review.
    func c19ValidateMeasurementReviewer(in workspaceID: WorkspaceID) throws {
        try validate()
        guard self.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        guard responsibility == .reviewedBy else {
            throw PartyAccountabilityFailureV1.unsupportedClaim
        }
    }
}

extension ServicePartyReferenceV1 {
    func validateSuccessor(of predecessor: ServicePartyReferenceV1) throws {
        try predecessor.validate(); try validate()
        let nextRevision = predecessor.revision.addingReportingOverflow(1)
        guard partyID == predecessor.partyID, workspaceID == predecessor.workspaceID,
              kind == predecessor.kind, effectiveAt == predecessor.effectiveAt,
              !nextRevision.overflow, revision == nextRevision.partialValue else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
        if predecessor.state == .retired, state != .retired { throw PartyAccountabilityFailureV1.immutableHistory }
    }
}

extension LocalActorReferenceV1 {
    func validatePartyReference(_ party: ServicePartyReferenceV1) throws {
        try validate(); try party.validate()
        guard workspaceID == party.workspaceID, partyID == party.partyID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
    }
}

extension SignoffSnapshotV1 {
    func validateSupersession(of predecessor: SignoffSnapshotV1) throws {
        try predecessor.validate(); try validate()
        guard predecessor.subjectRevision < UInt64.max,
              supersedesSnapshotID == predecessor.snapshotID, workspaceID == predecessor.workspaceID,
              subjectID == predecessor.subjectID, subjectRevision >= predecessor.subjectRevision,
              purpose == predecessor.purpose, recordedAt >= predecessor.recordedAt else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
    }
}

// Synthesized Encodable output is retained, while every Decodable entry point
// is routed back through the same validating initializer used by writers.
extension SitePartyRoleEventV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let eventID: UUID; let workspaceID: WorkspaceID; let siteID: UUID; let partyID: UUID; let role: SitePartyRoleV1; let effectiveFrom: Date; let effectiveUntil: Date?; let source: SitePartyRoleSourceV1; let supersedesEventID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date; let receiptSHA256: String }
    init(from decoder: Decoder) throws {
        let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }
        try self.init(eventID: v.eventID, workspaceID: v.workspaceID, siteID: v.siteID, partyID: v.partyID, role: v.role, effectiveFrom: v.effectiveFrom, effectiveUntil: v.effectiveUntil, source: v.source, supersedesEventID: v.supersedesEventID, revision: v.revision, mutationID: v.mutationID, recordedAt: v.recordedAt)
        guard receiptSHA256 == v.receiptSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
    }
}

extension LocalActorReferenceV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let actorReferenceID: UUID; let workspaceID: WorkspaceID; let partyID: UUID?; let displayName: String }
    init(from decoder: Decoder) throws { let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }; try self.init(actorReferenceID: v.actorReferenceID, workspaceID: v.workspaceID, partyID: v.partyID, displayName: v.displayName) }
}

extension ActorSnapshotV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let actor: LocalActorReferenceV1; let responsibility: ResponsibilityKindV1; let displayNameAtTime: String; let capturedAt: Date; let snapshotSHA256: String }
    init(from decoder: Decoder) throws { let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }; try self.init(snapshotID: v.snapshotID, workspaceID: v.workspaceID, actor: v.actor, responsibility: v.responsibility, displayNameAtTime: v.displayNameAtTime, capturedAt: v.capturedAt); guard snapshotSHA256 == v.snapshotSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch } }
}

extension ActorSnapshotV1 {
    func validateInspectionReviewResponsibility(
        _ expected: ResponsibilityKindV1,
        workspaceID: WorkspaceID
    ) throws {
        try validate()
        guard self.workspaceID == workspaceID, responsibility == expected else {
            throw PartyAccountabilityFailureV1.unsupportedClaim
        }
    }
}

extension LocalActorReferenceV1 {
    func validateInspectionReviewAssignee(workspaceID: WorkspaceID) throws {
        try validate()
        guard self.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
    }
}

extension QualificationSnapshotV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let declaredScope: String; let issuerDisplay: String?; let credentialLocator: String?; let effectiveAt: Date?; let expiresAt: Date?; let provenance: QualificationProvenanceV1; let capturedAt: Date; let snapshotSHA256: String }
    init(from decoder: Decoder) throws { let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }; try self.init(snapshotID: v.snapshotID, workspaceID: v.workspaceID, declaredScope: v.declaredScope, issuerDisplay: v.issuerDisplay, credentialLocator: v.credentialLocator, effectiveAt: v.effectiveAt, expiresAt: v.expiresAt, provenance: v.provenance, capturedAt: v.capturedAt); guard snapshotSHA256 == v.snapshotSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch } }
}

extension QualificationSnapshotV1 {
    /// Validates only the recorded claim's temporal applicability. It does not
    /// authenticate an actor or verify a credential or professional status.
    func validateDeclaredApplicability(at effectiveAt: Date, workspaceID: WorkspaceID) throws {
        try validate()
        guard self.workspaceID == workspaceID,
              self.effectiveAt.map({ $0 <= effectiveAt }) ?? true,
              expiresAt.map({ effectiveAt <= $0 }) ?? true else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
    }
}

extension ActorSnapshotV1 {
    func validateAuthoritySelection(workspaceID: WorkspaceID) throws {
        try validate()
        guard self.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.wrongWorkspace
        }
    }
}

extension SignoffIntentDisclosureReleaseV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let releaseID: String; let disclosureText: String; let statesLocalAssertionOnly: Bool; let disclaimsIdentityVerification: Bool; let disclaimsLegalSignature: Bool }
    init(from decoder: Decoder) throws { let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }; try self.init(releaseID: v.releaseID, disclosureText: v.disclosureText, statesLocalAssertionOnly: v.statesLocalAssertionOnly, disclaimsIdentityVerification: v.disclaimsIdentityVerification, disclaimsLegalSignature: v.disclaimsLegalSignature) }
}

extension SignoffRoleAssertionV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let claimedRole: String; let claimedRelationship: SitePartyRoleV1?; let actor: ActorSnapshotV1; let disclosureRelease: SignoffIntentDisclosureReleaseV1 }
    init(from decoder: Decoder) throws { let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }; try self.init(claimedRole: v.claimedRole, claimedRelationship: v.claimedRelationship, actor: v.actor, disclosureRelease: v.disclosureRelease) }
}

extension SignoffSnapshotV1 {
    private struct Decoded: Decodable { let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID; let purpose: String; let subjectID: UUID; let subjectRevision: UInt64; let disposition: SignoffDispositionV1; let method: SignoffMethodV1; let roleAssertion: SignoffRoleAssertionV1?; let qualification: QualificationSnapshotV1?; let externalEvidenceID: UUID?; let occurredAt: Date?; let recordedAt: Date; let supersedesSnapshotID: UUID?; let mutationID: MutationIDV1; let snapshotSHA256: String }
    init(from decoder: Decoder) throws { let v = try Decoded(from: decoder); guard v.schemaVersion == Self.schemaVersion else { throw PartyAccountabilityFailureV1.incompatibleVersion }; try self.init(snapshotID: v.snapshotID, workspaceID: v.workspaceID, purpose: v.purpose, subjectID: v.subjectID, subjectRevision: v.subjectRevision, disposition: v.disposition, method: v.method, roleAssertion: v.roleAssertion, qualification: v.qualification, externalEvidenceID: v.externalEvidenceID, occurredAt: v.occurredAt, recordedAt: v.recordedAt, supersedesSnapshotID: v.supersedesSnapshotID, mutationID: v.mutationID); guard snapshotSHA256 == v.snapshotSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch } }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Accountability_PartyAccountabilityContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Accountability_PartyAccountabilityContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Accountability_PartyAccountabilityContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift", role: .evidence)
}

enum C31LightingAccountabilityBoundaryV1 {
    static let partyIdentityIsNotCopiedIntoLightingProjection = true
    static let responsibleActorClaimsAreNotInferred = true
    static let reportUsesOnlyExistingWorkspaceReferences = true
}
// MARK: - C32 assistance party accountability boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Accountability_PartyAccountabilityContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedByMustBeReviewedActor = true

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

enum C33TemporalEvidenceBoundary_Domain_Accountability_PartyAccountabilityContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}
