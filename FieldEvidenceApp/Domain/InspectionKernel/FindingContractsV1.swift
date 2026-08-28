import Foundation

enum FindingContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case duplicateIdentity
    case missingTarget
    case invalidTransition
    case staleRevision
    case historyRewrite
    case recheckRequired
    case releaseNotEligible
    case selfRelationship
    case reverseRelationship
    case relationshipCycle
    case publicationInterrupted
    case hashMismatch
    case incompatibleVersion
    case canonicalEvidenceIncomplete
}

extension FindingV1 {
    func inspectionReviewItemReference() throws -> ChangeRequestItemReferenceV1 {
        guard revision >= 0 else { throw FindingContractFailureV1.invalidValue }
        return try .init(kind: .finding, itemID: findingID,
                         itemRevision: UInt64(revision),
                         itemSHA256: WorkspaceMutationCanonicalV1.sha256(self))
    }
}

enum FindingContractLimitsV1 {
    static let maximumIDBytes = 128
    static let maximumTextBytes = 2_048
    static let maximumReasonBytes = 1_024
    static let maximumEvidenceReferences = 32
    static let maximumTransitions = 512
    static let maximumLinks = 256
    static let maximumRegistryEntries = 1_024
    static let maximumCanonicalBytes = 1_048_576
}

enum FindingContractValidationV1 {
    static func validID(_ value: String) -> Bool {
        WorkflowGrammarValidationV1.validID(value)
    }

    static func validText(_ value: String, maximumBytes: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= maximumBytes
    }

    static func validInstant(_ value: String) -> Bool {
        guard value.utf8.count <= 32 else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    static func validateIDs(_ values: [String], maximum: Int) throws {
        guard values.count <= maximum,
              values == values.sorted(),
              Set(values).count == values.count,
              values.allSatisfy(validID) else {
            throw FindingContractFailureV1.invalidValue
        }
    }
}

struct FindingSeverityBindingV1: Codable, Equatable, Hashable, Sendable {
    let severityID: String
    let severityScaleReleaseID: String
    let severityScaleSHA256: String

    init(
        severityID: String,
        severityScaleReleaseID: String,
        severityScaleSHA256: String
    ) throws {
        guard FindingContractValidationV1.validID(severityID),
              FindingContractValidationV1.validID(severityScaleReleaseID),
              KernelCanonicalHashV1.validSHA256(severityScaleSHA256) else {
            throw FindingContractFailureV1.invalidValue
        }
        self.severityID = severityID
        self.severityScaleReleaseID = severityScaleReleaseID
        self.severityScaleSHA256 = severityScaleSHA256
    }
}

extension FindingSeverityBindingV1 {
    func validate(against scale: SeverityScaleReleaseV1) throws {
        try scale.validate()
        guard severityScaleReleaseID.lowercased() == scale.releaseID.uuidString.lowercased(),
              scale.levels.contains(where: { $0.levelID == severityID }),
              severityScaleSHA256 == scale.releaseSHA256 else {
            throw FindingContractFailureV1.invalidValue
        }
    }
}

struct FindingSubjectV1: Codable, Equatable, Hashable, Sendable {
    let subjectKindID: String
    let subjectID: String
    let subjectRevision: Int

    init(subjectKindID: String, subjectID: String, subjectRevision: Int) throws {
        guard FindingContractValidationV1.validID(subjectKindID),
              FindingContractValidationV1.validID(subjectID), subjectRevision >= 0 else {
            throw FindingContractFailureV1.invalidValue
        }
        self.subjectKindID = subjectKindID
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
    }
}

enum FindingSourceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case inspectionResponse = "INSPECTION_RESPONSE"
    case inspectionObservation = "INSPECTION_OBSERVATION"
    case humanObservation = "HUMAN_OBSERVATION"
    case importedRecord = "IMPORTED_RECORD"
}

struct FindingSourceV1: Codable, Equatable, Hashable, Sendable {
    let kind: FindingSourceKindV1
    let sourceID: String
    let sourceRevision: Int
    let evidenceRevisionIDs: [String]

    init(
        kind: FindingSourceKindV1,
        sourceID: String,
        sourceRevision: Int,
        evidenceRevisionIDs: [String] = []
    ) throws {
        guard FindingContractValidationV1.validID(sourceID), sourceRevision >= 0 else {
            throw FindingContractFailureV1.invalidValue
        }
        try FindingContractValidationV1.validateIDs(
            evidenceRevisionIDs,
            maximum: FindingContractLimitsV1.maximumEvidenceReferences
        )
        self.kind = kind
        self.sourceID = sourceID
        self.sourceRevision = sourceRevision
        self.evidenceRevisionIDs = evidenceRevisionIDs
    }
}

struct FindingV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let findingID: String
    let revision: Int
    let severity: FindingSeverityBindingV1
    let categoryID: String
    let subject: FindingSubjectV1
    let source: FindingSourceV1
    let summary: String

    var id: String { findingID }

    init(
        findingID: String,
        revision: Int = 0,
        severity: FindingSeverityBindingV1,
        categoryID: String,
        subject: FindingSubjectV1,
        source: FindingSourceV1,
        summary: String
    ) throws {
        guard FindingContractValidationV1.validID(findingID), revision >= 0,
              FindingContractValidationV1.validID(categoryID),
              FindingContractValidationV1.validText(
                summary,
                maximumBytes: FindingContractLimitsV1.maximumTextBytes
              ) else {
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.findingID = findingID
        self.revision = revision
        self.severity = severity
        self.categoryID = categoryID
        self.subject = subject
        self.source = source
        self.summary = summary
    }
}

extension FindingV1 {
    func validateClassification(
        _ classification: FindingClassificationBindingV1,
        scale: SeverityScaleReleaseV1?
    ) throws {
        try classification.validate()
        guard UUID(uuidString: findingID) == classification.findingID else {
            throw FindingContractFailureV1.invalidValue
        }
        if let scale {
            try severity.validate(against: scale)
            guard classification.severityScaleReleaseID == scale.releaseID,
                  classification.severityLevelID == severity.severityID else {
                throw FindingContractFailureV1.invalidValue
            }
        } else if classification.severityScaleReleaseID != nil
                    || classification.severityLevelID != nil {
            throw FindingContractFailureV1.invalidValue
        }
    }
}

extension FindingV1 {
    /// Stable immutable claim identity for a specific C03 finding revision.
    var assuranceClaimID: String { "finding:\(findingID):\(revision)" }

    func bindsAssuranceEvidenceID(_ evidenceID: String) -> Bool {
        source.evidenceRevisionIDs.contains(evidenceID)
    }
}

enum FindingClosedCodingV1 {
    static func requireExact(_ decoder: any Decoder, keys: [String]) throws {
        try KernelClosedCodingV1.require(decoder, keys: keys)
    }

    static func requireClosed(
        _ decoder: any Decoder,
        allowed: [String],
        required: [String]
    ) throws {
        try KernelClosedCodingV1.require(decoder, keys: allowed, required: required)
    }
}

extension FindingSubjectV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case subjectKindID, subjectID, subjectRevision
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            subjectKindID: c.decode(String.self, forKey: .subjectKindID),
            subjectID: c.decode(String.self, forKey: .subjectID),
            subjectRevision: c.decode(Int.self, forKey: .subjectRevision)
        )
    }
}

extension FindingSeverityBindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case severityID, severityScaleReleaseID, severityScaleSHA256
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            severityID: c.decode(String.self, forKey: .severityID),
            severityScaleReleaseID: c.decode(String.self, forKey: .severityScaleReleaseID),
            severityScaleSHA256: c.decode(String.self, forKey: .severityScaleSHA256)
        )
    }
}

extension FindingSourceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, sourceID, sourceRevision, evidenceRevisionIDs
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: c.decode(FindingSourceKindV1.self, forKey: .kind),
            sourceID: c.decode(String.self, forKey: .sourceID),
            sourceRevision: c.decode(Int.self, forKey: .sourceRevision),
            evidenceRevisionIDs: c.decode([String].self, forKey: .evidenceRevisionIDs)
        )
    }
}

extension FindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, findingID, revision, severity, categoryID, subject, source, summary
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw FindingContractFailureV1.incompatibleVersion
        }
        try self.init(
            findingID: c.decode(String.self, forKey: .findingID),
            revision: c.decode(Int.self, forKey: .revision),
            severity: c.decode(FindingSeverityBindingV1.self, forKey: .severity),
            categoryID: c.decode(String.self, forKey: .categoryID),
            subject: c.decode(FindingSubjectV1.self, forKey: .subject),
            source: c.decode(FindingSourceV1.self, forKey: .source),
            summary: c.decode(String.self, forKey: .summary)
        )
    }
}
