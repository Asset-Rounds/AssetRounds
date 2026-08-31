import Foundation

enum EvidenceQualityFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case staleRevision
    case wrongWorkspace
    case duplicateIdentity
    case corruptDigest
    case arithmeticOverflow
    case unknownRule
    case incompatibleVersion
    case invalidSupersession
    case receiptMismatch
}

enum EvidenceQualityLimitsV1 {
    static let maximumRules = 32
    static let maximumEvidenceBindings = 64
    static let maximumFindings = 32
    static let maximumTextBytes = 512
    static let maximumKeyBytes = 160
    static let maximumVersionBytes = 64
    static let maximumLimitationBytes = 500
    static let maximumMetricValue: Int64 = 9_000_000_000_000_000
}

enum EvidenceQualityLifecycleV1 {
    static let canonicalWriter = "WorkspaceWriterV1"
    static let writersPerWorkspaceGeneration = 1
    static let createsSecondStore = false
    static let assessmentIsAdvisoryOnly = true
    static let changesRequirementOutcome = false
    static let changesComplianceOutcome = false
    static let changesSafetyOutcome = false
    static let changesInspectionOutcome = false
    static let waiverErasesWarnings = false
    static let waiverAutomaticallyPassesEvidence = false
}

private enum EvidenceQualityValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zeroUUID else { throw EvidenceQualityFailureV1.invalidValue }
    }

    static func revision(_ value: UInt64) throws {
        guard value > 0 else { throw EvidenceQualityFailureV1.staleRevision }
    }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value), value == value.lowercased() else {
            throw EvidenceQualityFailureV1.corruptDigest
        }
    }

    static func token(_ value: String, maximumBytes: Int = EvidenceQualityLimitsV1.maximumKeyBytes) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }) else {
            throw EvidenceQualityFailureV1.invalidValue
        }
    }

    static func text(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= EvidenceQualityLimitsV1.maximumTextBytes else {
            throw EvidenceQualityFailureV1.invalidValue
        }
    }

    static func instant(_ value: Date) throws {
        guard value.timeIntervalSince1970.isFinite, value.timeIntervalSince1970 >= 0 else {
            throw EvidenceQualityFailureV1.invalidValue
        }
    }

    static func metric(_ value: Int64) throws {
        guard value >= 0, value <= EvidenceQualityLimitsV1.maximumMetricValue else {
            throw EvidenceQualityFailureV1.arithmeticOverflow
        }
    }

    static func canonicalSHA256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

enum EvidenceQualityRuleKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case darkness = "DARKNESS"
    case blur = "BLUR"
    case resolution = "RESOLUTION"
    case duplicate = "DUPLICATE"
    case framingReferenceSequence = "FRAMING_REFERENCE_SEQUENCE"
    case requiredCount = "REQUIRED_COUNT"
}

enum EvidenceQualityRuleIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case darkness = "evidence.quality.darkness"
    case blur = "evidence.quality.blur"
    case resolution = "evidence.quality.resolution"
    case duplicate = "evidence.quality.duplicate"
    case framingReferenceSequence = "evidence.quality.framing_reference_sequence"
    case requiredCount = "evidence.quality.required_count"

    init(kind: EvidenceQualityRuleKindV1) {
        switch kind {
        case .darkness: self = .darkness
        case .blur: self = .blur
        case .resolution: self = .resolution
        case .duplicate: self = .duplicate
        case .framingReferenceSequence: self = .framingReferenceSequence
        case .requiredCount: self = .requiredCount
        }
    }
}

enum EvidenceQualityMetricUnitV1: String, CaseIterable, Codable, Hashable, Sendable {
    case normalizedLumaMillionths = "NORMALIZED_LUMA_MILLIONTHS"
    case laplacianVarianceMillionths = "LAPLACIAN_VARIANCE_MILLIONTHS"
    case pixelCount = "PIXEL_COUNT"
    case perceptualHashDistanceBits = "PERCEPTUAL_HASH_DISTANCE_BITS"
    case referenceCoverageMillionths = "REFERENCE_COVERAGE_MILLIONTHS"
    case evidenceCount = "EVIDENCE_COUNT"
}

enum EvidenceQualityThresholdComparatorV1: String, CaseIterable, Codable, Hashable, Sendable {
    case atLeast = "AT_LEAST"
    case atMost = "AT_MOST"

    func includes(_ measuredValue: Int64, threshold: Int64) -> Bool {
        switch self {
        case .atLeast: return measuredValue >= threshold
        case .atMost: return measuredValue <= threshold
        }
    }
}

enum EvidenceQualitySeverityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case notice = "NOTICE"
    case caution = "CAUTION"
    case strongCaution = "STRONG_CAUTION"
}

enum EvidenceQualityApplicabilityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case individualCapture = "INDIVIDUAL_CAPTURE"
    case capturePair = "CAPTURE_PAIR"
    case referenceSequence = "REFERENCE_SEQUENCE"
    case evidenceCollection = "EVIDENCE_COLLECTION"
}

struct EvidenceQualityRuleV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let ruleID: String
    let kind: EvidenceQualityRuleKindV1
    let ruleVersion: String
    let comparator: EvidenceQualityThresholdComparatorV1
    let threshold: Int64
    let unit: EvidenceQualityMetricUnitV1
    let severity: EvidenceQualitySeverityV1
    let explanationKey: String
    let remedyKey: String
    let applicability: EvidenceQualityApplicabilityV1
    let ruleSHA256: String

    init(ruleID: String, kind: EvidenceQualityRuleKindV1, ruleVersion: String,
         comparator: EvidenceQualityThresholdComparatorV1, threshold: Int64,
         unit: EvidenceQualityMetricUnitV1, severity: EvidenceQualitySeverityV1,
         explanationKey: String, remedyKey: String,
         applicability: EvidenceQualityApplicabilityV1) throws {
        schemaVersion = Self.schemaVersion
        self.ruleID = ruleID; self.kind = kind; self.ruleVersion = ruleVersion
        self.comparator = comparator; self.threshold = threshold; self.unit = unit
        self.severity = severity; self.explanationKey = explanationKey
        self.remedyKey = remedyKey; self.applicability = applicability
        ruleSHA256 = try EvidenceQualityValidationV1.canonicalSHA256(Basis(
            schemaVersion: Self.schemaVersion, ruleID: ruleID, kind: kind,
            ruleVersion: ruleVersion, comparator: comparator, threshold: threshold,
            unit: unit, severity: severity, explanationKey: explanationKey,
            remedyKey: remedyKey, applicability: applicability
        ))
        try validate()
    }

    func validate() throws {
        try EvidenceQualityValidationV1.token(ruleID)
        try EvidenceQualityValidationV1.token(ruleVersion, maximumBytes: EvidenceQualityLimitsV1.maximumVersionBytes)
        try EvidenceQualityValidationV1.metric(threshold)
        try EvidenceQualityValidationV1.token(explanationKey)
        try EvidenceQualityValidationV1.token(remedyKey)
        guard schemaVersion == Self.schemaVersion,
              ruleID == EvidenceQualityRuleIDV1(kind: kind).rawValue,
              Self.expectedUnit[kind] == unit,
              Self.expectedApplicability[kind] == applicability,
              ruleSHA256 == (try EvidenceQualityValidationV1.canonicalSHA256(basis)) else {
            throw EvidenceQualityFailureV1.incompatibleVersion
        }
    }

    private static let expectedUnit: [EvidenceQualityRuleKindV1: EvidenceQualityMetricUnitV1] = [
        .darkness: .normalizedLumaMillionths,
        .blur: .laplacianVarianceMillionths,
        .resolution: .pixelCount,
        .duplicate: .perceptualHashDistanceBits,
        .framingReferenceSequence: .referenceCoverageMillionths,
        .requiredCount: .evidenceCount,
    ]
    private static let expectedApplicability: [EvidenceQualityRuleKindV1: EvidenceQualityApplicabilityV1] = [
        .darkness: .individualCapture,
        .blur: .individualCapture,
        .resolution: .individualCapture,
        .duplicate: .capturePair,
        .framingReferenceSequence: .referenceSequence,
        .requiredCount: .evidenceCollection,
    ]
    private var basis: Basis { .init(schemaVersion: schemaVersion, ruleID: ruleID, kind: kind,
        ruleVersion: ruleVersion, comparator: comparator, threshold: threshold, unit: unit,
        severity: severity, explanationKey: explanationKey, remedyKey: remedyKey,
        applicability: applicability) }
    private struct Basis: Codable { let schemaVersion: Int; let ruleID: String; let kind: EvidenceQualityRuleKindV1; let ruleVersion: String; let comparator: EvidenceQualityThresholdComparatorV1; let threshold: Int64; let unit: EvidenceQualityMetricUnitV1; let severity: EvidenceQualitySeverityV1; let explanationKey: String; let remedyKey: String; let applicability: EvidenceQualityApplicabilityV1 }
}

struct EvidenceQualityRuleSetV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let ruleSetID: UUID
    let workspaceID: WorkspaceID
    let policyVersion: String
    let orderedRules: [EvidenceQualityRuleV1]
    let supersedesRuleSetID: UUID?
    let predecessorSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let ruleSetSHA256: String

    init(ruleSetID: UUID, workspaceID: WorkspaceID, policyVersion: String,
         orderedRules: [EvidenceQualityRuleV1], predecessor: EvidenceQualityRuleSetV1? = nil,
         revision: UInt64, mutationID: MutationIDV1, recordedAt: Date) throws {
        let orderedRules = orderedRules.sorted(by: { $0.ruleID < $1.ruleID })
        schemaVersion = Self.schemaVersion; self.ruleSetID = ruleSetID; self.workspaceID = workspaceID
        self.policyVersion = policyVersion; self.orderedRules = orderedRules
        supersedesRuleSetID = predecessor?.ruleSetID; predecessorSHA256 = predecessor?.ruleSetSHA256
        self.revision = revision; self.mutationID = mutationID; self.recordedAt = recordedAt
        ruleSetSHA256 = try EvidenceQualityValidationV1.canonicalSHA256(Basis(
            schemaVersion: Self.schemaVersion, ruleSetID: ruleSetID, workspaceID: workspaceID,
            policyVersion: policyVersion, orderedRules: orderedRules,
            supersedesRuleSetID: predecessor?.ruleSetID, predecessorSHA256: predecessor?.ruleSetSHA256,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt
        ))
        try validate()
        if let predecessor { try validateSuccessor(of: predecessor) }
    }

    func validate() throws {
        try EvidenceQualityValidationV1.id(ruleSetID); try EvidenceQualityValidationV1.revision(revision)
        try EvidenceQualityValidationV1.token(policyVersion, maximumBytes: EvidenceQualityLimitsV1.maximumVersionBytes)
        try EvidenceQualityValidationV1.instant(recordedAt); try predecessorSHA256.map(EvidenceQualityValidationV1.digest)
        try orderedRules.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              orderedRules.count == EvidenceQualityRuleKindV1.allCases.count,
              orderedRules.count <= EvidenceQualityLimitsV1.maximumRules,
              orderedRules == orderedRules.sorted(by: { $0.ruleID < $1.ruleID }),
              Set(orderedRules.map(\.ruleID)).count == orderedRules.count,
              Set(orderedRules.map(\.kind)) == Set(EvidenceQualityRuleKindV1.allCases),
              (revision == 1) == (supersedesRuleSetID == nil && predecessorSHA256 == nil),
              ruleSetSHA256 == (try EvidenceQualityValidationV1.canonicalSHA256(basis)) else {
            throw EvidenceQualityFailureV1.corruptDigest
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validate(); try validate()
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard !overflow else { throw EvidenceQualityFailureV1.arithmeticOverflow }
        guard workspaceID == predecessor.workspaceID, ruleSetID != predecessor.ruleSetID,
              supersedesRuleSetID == predecessor.ruleSetID,
              predecessorSHA256 == predecessor.ruleSetSHA256, revision == next,
              mutationID != predecessor.mutationID, recordedAt >= predecessor.recordedAt else {
            throw EvidenceQualityFailureV1.invalidSupersession
        }
    }

    func rule(id: String, version: String) throws -> EvidenceQualityRuleV1 {
        guard let rule = orderedRules.first(where: { $0.ruleID == id }) else {
            throw EvidenceQualityFailureV1.unknownRule
        }
        guard rule.ruleVersion == version else { throw EvidenceQualityFailureV1.incompatibleVersion }
        return rule
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, ruleSetID: ruleSetID, workspaceID: workspaceID,
        policyVersion: policyVersion, orderedRules: orderedRules, supersedesRuleSetID: supersedesRuleSetID,
        predecessorSHA256: predecessorSHA256, revision: revision, mutationID: mutationID, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let ruleSetID: UUID; let workspaceID: WorkspaceID; let policyVersion: String; let orderedRules: [EvidenceQualityRuleV1]; let supersedesRuleSetID: UUID?; let predecessorSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date }
}

struct EvidenceQualityEvidenceBindingV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let evidenceID: String
    let evidenceRevision: UInt64
    let contentID: String
    let contentSHA256: String

    init(workspaceID: WorkspaceID, evidenceID: String, evidenceRevision: UInt64,
         contentID: String, contentSHA256: String) throws {
        try EvidenceQualityValidationV1.token(evidenceID); try EvidenceQualityValidationV1.revision(evidenceRevision)
        try EvidenceQualityValidationV1.token(contentID); try EvidenceQualityValidationV1.digest(contentSHA256)
        self.workspaceID = workspaceID; self.evidenceID = evidenceID; self.evidenceRevision = evidenceRevision
        self.contentID = contentID; self.contentSHA256 = contentSHA256
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, evidenceID: evidenceID, evidenceRevision: evidenceRevision, contentID: contentID, contentSHA256: contentSHA256) }
    var stableKey: String { "\(workspaceID.rawValue.uuidString.lowercased())|\(evidenceID)|\(String(format: "%020llu", evidenceRevision))|\(contentID)|\(contentSHA256)" }
}

struct EvidenceQualityRuleInputV1: Codable, Equatable, Hashable, Sendable {
    let ruleID: String
    let ruleVersion: String
    let measuredValue: Int64
    let unit: EvidenceQualityMetricUnitV1
    let subject: EvidenceQualityEvidenceBindingV1
    let comparison: EvidenceQualityEvidenceBindingV1?
    let referenceSequenceSHA256: String?

    init(rule: EvidenceQualityRuleV1, measuredValue: Int64,
         subject: EvidenceQualityEvidenceBindingV1,
         comparison: EvidenceQualityEvidenceBindingV1? = nil,
         referenceSequenceSHA256: String? = nil) throws {
        try rule.validate(); try EvidenceQualityValidationV1.metric(measuredValue); try subject.validate()
        try comparison?.validate(); try referenceSequenceSHA256.map(EvidenceQualityValidationV1.digest)
        guard (rule.applicability == .capturePair) == (comparison != nil),
              (rule.applicability == .referenceSequence) == (referenceSequenceSHA256 != nil),
              comparison.map({ $0.workspaceID == subject.workspaceID }) ?? true,
              comparison.map({ $0.stableKey != subject.stableKey }) ?? true else {
            throw EvidenceQualityFailureV1.invalidValue
        }
        ruleID = rule.ruleID; ruleVersion = rule.ruleVersion; self.measuredValue = measuredValue
        unit = rule.unit; self.subject = subject; self.comparison = comparison
        self.referenceSequenceSHA256 = referenceSequenceSHA256
    }

    func validate(against rule: EvidenceQualityRuleV1) throws {
        try rule.validate(); try EvidenceQualityValidationV1.metric(measuredValue); try subject.validate()
        try comparison?.validate(); try referenceSequenceSHA256.map(EvidenceQualityValidationV1.digest)
        guard ruleID == rule.ruleID, ruleVersion == rule.ruleVersion, unit == rule.unit,
              (rule.applicability == .capturePair) == (comparison != nil),
              (rule.applicability == .referenceSequence) == (referenceSequenceSHA256 != nil),
              comparison.map({ $0.workspaceID == subject.workspaceID }) ?? true,
              comparison.map({ $0.stableKey != subject.stableKey }) ?? true else {
            throw EvidenceQualityFailureV1.incompatibleVersion
        }
    }
}

enum EvidenceQualityFindingDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case withinConfiguredBoundary = "WITHIN_CONFIGURED_BOUNDARY"
    case attentionRecommended = "ATTENTION_RECOMMENDED"
    case unavailableInput = "UNAVAILABLE_INPUT"
}

struct EvidenceQualityRuleFindingV1: Codable, Equatable, Hashable, Sendable {
    let ruleID: String
    let ruleVersion: String
    let input: EvidenceQualityRuleInputV1
    let disposition: EvidenceQualityFindingDispositionV1
    let severity: EvidenceQualitySeverityV1
    let explanationKey: String
    let remedyKey: String

    init(rule: EvidenceQualityRuleV1, input: EvidenceQualityRuleInputV1,
         disposition: EvidenceQualityFindingDispositionV1) throws {
        try input.validate(against: rule)
        let expected: EvidenceQualityFindingDispositionV1 = rule.comparator.includes(input.measuredValue, threshold: rule.threshold)
            ? .withinConfiguredBoundary : .attentionRecommended
        guard disposition == expected else { throw EvidenceQualityFailureV1.invalidValue }
        ruleID = rule.ruleID; ruleVersion = rule.ruleVersion; self.input = input
        self.disposition = disposition; severity = rule.severity
        explanationKey = rule.explanationKey; remedyKey = rule.remedyKey
    }

    func validate(against rule: EvidenceQualityRuleV1) throws {
        try input.validate(against: rule)
        let expected: EvidenceQualityFindingDispositionV1 = rule.comparator.includes(input.measuredValue, threshold: rule.threshold)
            ? .withinConfiguredBoundary : .attentionRecommended
        guard ruleID == rule.ruleID, ruleVersion == rule.ruleVersion, disposition == expected,
              severity == rule.severity, explanationKey == rule.explanationKey,
              remedyKey == rule.remedyKey else { throw EvidenceQualityFailureV1.corruptDigest }
    }
    var warningRemainsVisible: Bool { disposition != .withinConfiguredBoundary }
}

struct EvidenceQualityAssessmentV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let assessmentID: UUID
    let workspaceID: WorkspaceID
    let evidence: EvidenceQualityEvidenceBindingV1
    let ruleSetID: UUID
    let ruleSetRevision: UInt64
    let ruleSetSHA256: String
    let orderedFindings: [EvidenceQualityRuleFindingV1]
    let revision: UInt64
    let mutationID: MutationIDV1
    let assessedAt: Date
    let assessmentSHA256: String
    let advisoryOnly: Bool
    let altersRequirementComplianceSafetyOrInspectionOutcome: Bool

    init(assessmentID: UUID, workspaceID: WorkspaceID,
         evidence: EvidenceQualityEvidenceBindingV1, ruleSet: EvidenceQualityRuleSetV1,
         orderedFindings: [EvidenceQualityRuleFindingV1], revision: UInt64,
         mutationID: MutationIDV1, assessedAt: Date) throws {
        let orderedFindings = orderedFindings.sorted(by: { $0.ruleID < $1.ruleID })
        schemaVersion = Self.schemaVersion; self.assessmentID = assessmentID; self.workspaceID = workspaceID
        self.evidence = evidence; ruleSetID = ruleSet.ruleSetID; ruleSetRevision = ruleSet.revision
        ruleSetSHA256 = ruleSet.ruleSetSHA256; self.orderedFindings = orderedFindings
        self.revision = revision; self.mutationID = mutationID; self.assessedAt = assessedAt
        advisoryOnly = true; altersRequirementComplianceSafetyOrInspectionOutcome = false
        assessmentSHA256 = try EvidenceQualityValidationV1.canonicalSHA256(Basis(
            schemaVersion: Self.schemaVersion, assessmentID: assessmentID, workspaceID: workspaceID,
            evidence: evidence, ruleSetID: ruleSet.ruleSetID, ruleSetRevision: ruleSet.revision,
            ruleSetSHA256: ruleSet.ruleSetSHA256, orderedFindings: orderedFindings,
            revision: revision, mutationID: mutationID, assessedAt: assessedAt,
            advisoryOnly: true, altersRequirementComplianceSafetyOrInspectionOutcome: false
        ))
        try validate(ruleSet: ruleSet)
    }

    func validate(ruleSet: EvidenceQualityRuleSetV1) throws {
        try EvidenceQualityValidationV1.id(assessmentID); try EvidenceQualityValidationV1.revision(revision)
        try EvidenceQualityValidationV1.instant(assessedAt); try evidence.validate(); try ruleSet.validate()
        guard schemaVersion == Self.schemaVersion, evidence.workspaceID == workspaceID,
              ruleSet.workspaceID == workspaceID,
              ruleSetID == ruleSet.ruleSetID, ruleSetRevision == ruleSet.revision,
              ruleSetSHA256 == ruleSet.ruleSetSHA256,
              orderedFindings.count <= EvidenceQualityLimitsV1.maximumFindings,
              orderedFindings == orderedFindings.sorted(by: { $0.ruleID < $1.ruleID }),
              orderedFindings.map(\.ruleID) == ruleSet.orderedRules.map(\.ruleID),
              orderedFindings.allSatisfy({ $0.input.subject == evidence }), advisoryOnly,
              !altersRequirementComplianceSafetyOrInspectionOutcome else {
            throw EvidenceQualityFailureV1.unknownRule
        }
        for finding in orderedFindings { try finding.validate(against: ruleSet.rule(id: finding.ruleID, version: finding.ruleVersion)) }
        guard assessmentSHA256 == (try EvidenceQualityValidationV1.canonicalSHA256(basis)) else {
            throw EvidenceQualityFailureV1.corruptDigest
        }
    }

    var warningFindings: [EvidenceQualityRuleFindingV1] { orderedFindings.filter(\.warningRemainsVisible) }
    func validateCurrentEvidence(_ current: EvidenceQualityEvidenceBindingV1) throws {
        try current.validate()
        guard current.evidenceID == evidence.evidenceID else { throw EvidenceQualityFailureV1.invalidValue }
        guard current.evidenceRevision == evidence.evidenceRevision else { throw EvidenceQualityFailureV1.staleRevision }
        guard current.contentID == evidence.contentID,
              current.contentSHA256 == evidence.contentSHA256 else { throw EvidenceQualityFailureV1.corruptDigest }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, assessmentID: assessmentID, workspaceID: workspaceID,
        evidence: evidence, ruleSetID: ruleSetID, ruleSetRevision: ruleSetRevision,
        ruleSetSHA256: ruleSetSHA256, orderedFindings: orderedFindings, revision: revision,
        mutationID: mutationID, assessedAt: assessedAt, advisoryOnly: advisoryOnly,
        altersRequirementComplianceSafetyOrInspectionOutcome: altersRequirementComplianceSafetyOrInspectionOutcome) }
    private struct Basis: Codable { let schemaVersion: Int; let assessmentID: UUID; let workspaceID: WorkspaceID; let evidence: EvidenceQualityEvidenceBindingV1; let ruleSetID: UUID; let ruleSetRevision: UInt64; let ruleSetSHA256: String; let orderedFindings: [EvidenceQualityRuleFindingV1]; let revision: UInt64; let mutationID: MutationIDV1; let assessedAt: Date; let advisoryOnly: Bool; let altersRequirementComplianceSafetyOrInspectionOutcome: Bool }
}

enum EvidenceQualityWaiverReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case evidenceUnavailable = "EVIDENCE_UNAVAILABLE"
    case conditionsChanged = "CONDITIONS_CHANGED"
    case retakeNotPossible = "RETAKE_NOT_POSSIBLE"

    var requiresLimitation: Bool {
        self == .retakeNotPossible
    }
}

enum EvidenceQualityWaiverActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case recorded = "RECORDED"
    case withdrawn = "WITHDRAWN"
}

struct EvidenceQualityWaiverV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let waiverEventID: UUID
    let waiverID: UUID
    let workspaceID: WorkspaceID
    let assessmentID: UUID
    let assessmentRevision: UInt64
    let assessmentSHA256: String
    let evidence: EvidenceQualityEvidenceBindingV1
    let selectedRuleIDs: [String]
    let reason: EvidenceQualityWaiverReasonV1
    let limitation: String?
    let action: EvidenceQualityWaiverActionV1
    let actor: ActorSnapshotV1
    let recordedAt: Date
    let supersedesWaiverEventID: UUID?
    let predecessorSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let waiverSHA256: String
    let erasesWarnings: Bool
    let automaticallyPassesEvidence: Bool

    init(waiverEventID: UUID, waiverID: UUID, assessment: EvidenceQualityAssessmentV1,
         selectedRuleIDs: [String], reason: EvidenceQualityWaiverReasonV1,
         limitation: String? = nil, action: EvidenceQualityWaiverActionV1? = nil,
         actor: ActorSnapshotV1, recordedAt: Date, predecessor: EvidenceQualityWaiverV1? = nil,
         revision: UInt64, mutationID: MutationIDV1) throws {
        let resolvedAction = action ?? (predecessor == nil ? .recorded : .withdrawn)
        schemaVersion = Self.schemaVersion; self.waiverEventID = waiverEventID; self.waiverID = waiverID
        workspaceID = assessment.workspaceID; assessmentID = assessment.assessmentID
        assessmentRevision = assessment.revision; assessmentSHA256 = assessment.assessmentSHA256
        evidence = assessment.evidence; self.selectedRuleIDs = selectedRuleIDs.sorted()
        self.reason = reason; self.limitation = limitation; self.action = resolvedAction; self.actor = actor
        self.recordedAt = recordedAt; supersedesWaiverEventID = predecessor?.waiverEventID
        predecessorSHA256 = predecessor?.waiverSHA256; self.revision = revision; self.mutationID = mutationID
        erasesWarnings = false; automaticallyPassesEvidence = false
        waiverSHA256 = try EvidenceQualityValidationV1.canonicalSHA256(Basis(
            schemaVersion: Self.schemaVersion, waiverEventID: waiverEventID, waiverID: waiverID,
            workspaceID: assessment.workspaceID, assessmentID: assessment.assessmentID,
            assessmentRevision: assessment.revision, assessmentSHA256: assessment.assessmentSHA256,
            evidence: assessment.evidence, selectedRuleIDs: selectedRuleIDs.sorted(), reason: reason,
            limitation: limitation, action: resolvedAction, actor: actor, recordedAt: recordedAt,
            supersedesWaiverEventID: predecessor?.waiverEventID, predecessorSHA256: predecessor?.waiverSHA256,
            revision: revision, mutationID: mutationID, erasesWarnings: false, automaticallyPassesEvidence: false
        ))
        try validate(assessment: assessment)
        if let predecessor {
            try predecessor.validate(assessment: assessment)
            try validateSuccessor(of: predecessor)
        }
    }

    func validate(assessment: EvidenceQualityAssessmentV1) throws {
        try validateHistoryShape()
        try EvidenceQualityValidationV1.id(waiverEventID); try EvidenceQualityValidationV1.id(waiverID)
        try EvidenceQualityValidationV1.revision(revision); try EvidenceQualityValidationV1.instant(recordedAt)
        try actor.validate(); try predecessorSHA256.map(EvidenceQualityValidationV1.digest)
        if let limitation {
            guard limitation.utf8.count <= EvidenceQualityLimitsV1.maximumLimitationBytes else {
                throw EvidenceQualityFailureV1.invalidValue
            }
            try EvidenceQualityValidationV1.text(limitation)
        }
        guard schemaVersion == Self.schemaVersion, workspaceID == assessment.workspaceID,
              assessmentID == assessment.assessmentID, assessmentRevision == assessment.revision,
              assessmentSHA256 == assessment.assessmentSHA256, evidence == assessment.evidence,
              !selectedRuleIDs.isEmpty, selectedRuleIDs.count <= EvidenceQualityLimitsV1.maximumRules,
              selectedRuleIDs == selectedRuleIDs.sorted(), Set(selectedRuleIDs).count == selectedRuleIDs.count,
              Set(selectedRuleIDs).isSubset(of: Set(assessment.warningFindings.map(\.ruleID))),
              reason.requiresLimitation == (limitation != nil), actor.workspaceID == workspaceID,
              actor.responsibility == .recordedBy, recordedAt >= actor.capturedAt else {
            throw EvidenceQualityFailureV1.invalidValue
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateHistoryShape()
        try validateHistoryShape()
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard !overflow else { throw EvidenceQualityFailureV1.arithmeticOverflow }
        guard workspaceID == predecessor.workspaceID, waiverID == predecessor.waiverID,
              waiverEventID != predecessor.waiverEventID,
              assessmentID == predecessor.assessmentID, assessmentRevision == predecessor.assessmentRevision,
              assessmentSHA256 == predecessor.assessmentSHA256, evidence == predecessor.evidence,
              selectedRuleIDs == predecessor.selectedRuleIDs, reason == predecessor.reason,
              limitation == predecessor.limitation,
              supersedesWaiverEventID == predecessor.waiverEventID,
              predecessorSHA256 == predecessor.waiverSHA256, revision == next,
              mutationID != predecessor.mutationID, recordedAt >= predecessor.recordedAt,
              predecessor.revision == 1, predecessor.action == .recorded,
              action == .withdrawn else {
            throw EvidenceQualityFailureV1.invalidSupersession
        }
    }
    func validateCurrentEvidence(_ current: EvidenceQualityEvidenceBindingV1) throws {
        try current.validate()
        guard current.evidenceID == evidence.evidenceID else { throw EvidenceQualityFailureV1.invalidValue }
        guard current.evidenceRevision == evidence.evidenceRevision else { throw EvidenceQualityFailureV1.staleRevision }
        guard current.contentID == evidence.contentID,
              current.contentSHA256 == evidence.contentSHA256 else { throw EvidenceQualityFailureV1.corruptDigest }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, waiverEventID: waiverEventID, waiverID: waiverID,
        workspaceID: workspaceID, assessmentID: assessmentID, assessmentRevision: assessmentRevision,
        assessmentSHA256: assessmentSHA256, evidence: evidence, selectedRuleIDs: selectedRuleIDs,
        reason: reason, limitation: limitation, action: action, actor: actor, recordedAt: recordedAt,
        supersedesWaiverEventID: supersedesWaiverEventID, predecessorSHA256: predecessorSHA256,
        revision: revision, mutationID: mutationID, erasesWarnings: erasesWarnings,
        automaticallyPassesEvidence: automaticallyPassesEvidence) }
    private func validateHistoryShape() throws {
        let isInitial = revision == 1 && action == .recorded
            && supersedesWaiverEventID == nil && predecessorSHA256 == nil
        let isWithdrawal = revision == 2 && action == .withdrawn
            && supersedesWaiverEventID != nil && predecessorSHA256 != nil
        guard schemaVersion == Self.schemaVersion, isInitial || isWithdrawal,
              !erasesWarnings, !automaticallyPassesEvidence,
              waiverSHA256 == (try EvidenceQualityValidationV1.canonicalSHA256(basis)) else {
            throw EvidenceQualityFailureV1.invalidSupersession
        }
    }
    private struct Basis: Codable { let schemaVersion: Int; let waiverEventID: UUID; let waiverID: UUID; let workspaceID: WorkspaceID; let assessmentID: UUID; let assessmentRevision: UInt64; let assessmentSHA256: String; let evidence: EvidenceQualityEvidenceBindingV1; let selectedRuleIDs: [String]; let reason: EvidenceQualityWaiverReasonV1; let limitation: String?; let action: EvidenceQualityWaiverActionV1; let actor: ActorSnapshotV1; let recordedAt: Date; let supersedesWaiverEventID: UUID?; let predecessorSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let erasesWarnings: Bool; let automaticallyPassesEvidence: Bool }
}

enum EvidenceQualityMutationPayloadV1: Codable, Equatable, Sendable {
    case putRuleSet(EvidenceQualityRuleSetV1)
    case recordAssessment(EvidenceQualityAssessmentV1)
    case recordWaiver(EvidenceQualityWaiverV1)

    var workspaceID: WorkspaceID {
        switch self { case let .putRuleSet(v): return v.workspaceID; case let .recordAssessment(v): return v.workspaceID; case let .recordWaiver(v): return v.workspaceID }
    }
    var mutationID: MutationIDV1 {
        switch self { case let .putRuleSet(v): return v.mutationID; case let .recordAssessment(v): return v.mutationID; case let .recordWaiver(v): return v.mutationID }
    }
    var semanticSHA256: String {
        switch self { case let .putRuleSet(v): return v.ruleSetSHA256; case let .recordAssessment(v): return v.assessmentSHA256; case let .recordWaiver(v): return v.waiverSHA256 }
    }
}

struct EvidenceQualityMutationCommandV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let commandID: UUID
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let payload: EvidenceQualityMutationPayloadV1
    let submittedAt: Date
    let commandSHA256: String

    init(commandID: UUID, workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1,
         mutationID: MutationIDV1, payload: EvidenceQualityMutationPayloadV1, submittedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.commandID = commandID; self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision; self.mutationID = mutationID
        self.payload = payload; self.submittedAt = submittedAt
        commandSHA256 = try EvidenceQualityValidationV1.canonicalSHA256(Basis(schemaVersion: Self.schemaVersion,
            commandID: commandID, workspaceID: workspaceID, expectedRevision: expectedRevision,
            mutationID: mutationID, payload: payload, submittedAt: submittedAt))
        try validate()
    }
    func validate() throws {
        try EvidenceQualityValidationV1.id(commandID); try EvidenceQualityValidationV1.instant(submittedAt)
        guard schemaVersion == Self.schemaVersion, expectedRevision.workspaceID == workspaceID,
              expectedRevision.generationID != EvidenceQualityValidationV1.zeroUUID,
              expectedRevision.writerInstanceID != EvidenceQualityValidationV1.zeroUUID,
              payload.workspaceID == workspaceID, payload.mutationID == mutationID,
              commandSHA256 == (try EvidenceQualityValidationV1.canonicalSHA256(basis)) else {
            throw EvidenceQualityFailureV1.wrongWorkspace
        }
    }
    func validate(currentRevision: WorkspaceRevisionV1) throws {
        try validate()
        let current = WorkspaceExpectedRevisionV1(snapshot: currentRevision)
        guard current.workspaceID == workspaceID else { throw EvidenceQualityFailureV1.wrongWorkspace }
        guard current == expectedRevision else { throw EvidenceQualityFailureV1.staleRevision }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, commandID: commandID, workspaceID: workspaceID,
        expectedRevision: expectedRevision, mutationID: mutationID, payload: payload, submittedAt: submittedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let mutationID: MutationIDV1; let payload: EvidenceQualityMutationPayloadV1; let submittedAt: Date }
}

enum EvidenceQualityQueryScopeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case exactAssessment = "EXACT_ASSESSMENT"
    case evidenceHistory = "EVIDENCE_HISTORY"
    case currentRuleSet = "CURRENT_RULE_SET"
}

enum EvidenceQualityQueryTargetV1: Codable, Equatable, Sendable {
    case exactAssessment(evidenceID: String, evidenceRevision: UInt64, assessmentID: UUID)
    case evidenceHistory(evidenceID: String)
    case currentRuleSet

    var scope: EvidenceQualityQueryScopeV1 {
        switch self {
        case .exactAssessment: return .exactAssessment
        case .evidenceHistory: return .evidenceHistory
        case .currentRuleSet: return .currentRuleSet
        }
    }
}

struct EvidenceQualityQueryV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let target: EvidenceQualityQueryTargetV1

    var scope: EvidenceQualityQueryScopeV1 { target.scope }
    var evidenceID: String? {
        switch target {
        case let .exactAssessment(evidenceID, _, _), let .evidenceHistory(evidenceID): return evidenceID
        case .currentRuleSet: return nil
        }
    }
    var evidenceRevision: UInt64? {
        guard case let .exactAssessment(_, revision, _) = target else { return nil }
        return revision
    }
    var assessmentID: UUID? {
        guard case let .exactAssessment(_, _, assessmentID) = target else { return nil }
        return assessmentID
    }

    init(workspaceID: WorkspaceID, target: EvidenceQualityQueryTargetV1) throws {
        self.workspaceID = workspaceID; self.target = target
        try validate()
    }

    init(workspaceID: WorkspaceID, scope: EvidenceQualityQueryScopeV1,
         evidenceID: String? = nil, evidenceRevision: UInt64? = nil, assessmentID: UUID? = nil) throws {
        let target: EvidenceQualityQueryTargetV1
        switch scope {
        case .exactAssessment:
            guard let assessmentID, let evidenceID, let evidenceRevision else {
                throw EvidenceQualityFailureV1.invalidValue
            }
            target = .exactAssessment(evidenceID: evidenceID, evidenceRevision: evidenceRevision,
                                      assessmentID: assessmentID)
        case .evidenceHistory:
            guard assessmentID == nil, let evidenceID, evidenceRevision == nil else {
                throw EvidenceQualityFailureV1.invalidValue
            }
            target = .evidenceHistory(evidenceID: evidenceID)
        case .currentRuleSet:
            guard assessmentID == nil, evidenceID == nil, evidenceRevision == nil else { throw EvidenceQualityFailureV1.invalidValue }
            target = .currentRuleSet
        }
        try self.init(workspaceID: workspaceID, target: target)
    }

    func validate() throws {
        try EvidenceQualityValidationV1.id(workspaceID.rawValue)
        switch target {
        case let .exactAssessment(evidenceID, evidenceRevision, assessmentID):
            try EvidenceQualityValidationV1.token(evidenceID)
            try EvidenceQualityValidationV1.revision(evidenceRevision)
            try EvidenceQualityValidationV1.id(assessmentID)
        case let .evidenceHistory(evidenceID):
            try EvidenceQualityValidationV1.token(evidenceID)
        case .currentRuleSet:
            break
        }
    }

    private enum CodingKeys: String, CodingKey { case workspaceID, target }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
                      target: values.decode(EvidenceQualityQueryTargetV1.self, forKey: .target))
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(target, forKey: .target)
    }
}

struct EvidenceQualityProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let assessment: EvidenceQualityAssessmentV1
    let waiverHistory: [EvidenceQualityWaiverV1]
    let visibleWarnings: [EvidenceQualityRuleFindingV1]
    let advisoryOnly: Bool

    init(workspaceID: WorkspaceID, assessment: EvidenceQualityAssessmentV1,
         waiverHistory: [EvidenceQualityWaiverV1]) throws {
        let waiverHistory = waiverHistory.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            if $0.waiverID != $1.waiverID { return $0.waiverID.uuidString < $1.waiverID.uuidString }
            return $0.revision < $1.revision
        }
        guard assessment.workspaceID == workspaceID,
              waiverHistory.allSatisfy({ $0.workspaceID == workspaceID && $0.assessmentID == assessment.assessmentID }),
              Set(waiverHistory.map(\.waiverEventID)).count == waiverHistory.count else {
            throw EvidenceQualityFailureV1.wrongWorkspace
        }
        try waiverHistory.forEach { try $0.validate(assessment: assessment) }
        let histories = Dictionary(grouping: waiverHistory, by: \.waiverID)
        for history in histories.values {
            let ordered = history.sorted(by: { $0.revision < $1.revision })
            guard ordered.first?.revision == 1, ordered.count <= 2,
                  Set(ordered.map(\.revision)).count == ordered.count else {
                throw EvidenceQualityFailureV1.invalidSupersession
            }
            if ordered.count == 2 { try ordered[1].validateSuccessor(of: ordered[0]) }
        }
        self.workspaceID = workspaceID; self.assessment = assessment; self.waiverHistory = waiverHistory
        visibleWarnings = assessment.warningFindings; advisoryOnly = true
    }

    func validate() throws {
        let rebuilt = try Self(workspaceID: workspaceID, assessment: assessment,
                               waiverHistory: waiverHistory)
        guard rebuilt == self else { throw EvidenceQualityFailureV1.corruptDigest }
    }
}

struct EvidenceQualityAssessmentProjectionResultV1: Codable, Equatable, Sendable {
    let ruleSet: EvidenceQualityRuleSetV1
    let projection: EvidenceQualityProjectionV1

    init(ruleSet: EvidenceQualityRuleSetV1, projection: EvidenceQualityProjectionV1) throws {
        try ruleSet.validate()
        try projection.validate()
        try projection.assessment.validate(ruleSet: ruleSet)
        guard ruleSet.workspaceID == projection.workspaceID,
              ruleSet.ruleSetID == projection.assessment.ruleSetID,
              ruleSet.revision == projection.assessment.ruleSetRevision,
              ruleSet.ruleSetSHA256 == projection.assessment.ruleSetSHA256 else {
            throw EvidenceQualityFailureV1.corruptDigest
        }
        self.ruleSet = ruleSet; self.projection = projection
    }

    func validate() throws {
        let rebuilt = try Self(ruleSet: ruleSet, projection: projection)
        guard rebuilt == self else { throw EvidenceQualityFailureV1.corruptDigest }
    }
}

enum EvidenceQualityQueryResultV1: Codable, Equatable, Sendable {
    case currentRuleSet(EvidenceQualityRuleSetV1)
    case assessmentProjection(EvidenceQualityAssessmentProjectionResultV1)
    case notFound(EvidenceQualityQueryV1)

    func validate(for query: EvidenceQualityQueryV1) throws {
        try query.validate()
        switch (query.target, self) {
        case let (.currentRuleSet, .currentRuleSet(ruleSet)):
            try ruleSet.validate()
            guard ruleSet.workspaceID == query.workspaceID else { throw EvidenceQualityFailureV1.wrongWorkspace }
        case let (.exactAssessment(evidenceID, evidenceRevision, assessmentID), .assessmentProjection(result)):
            try result.validate()
            let assessment = result.projection.assessment
            guard result.projection.workspaceID == query.workspaceID,
                  assessment.assessmentID == assessmentID,
                  assessment.evidence.evidenceID == evidenceID,
                  assessment.evidence.evidenceRevision == evidenceRevision else {
                throw EvidenceQualityFailureV1.staleRevision
            }
        case let (.evidenceHistory(evidenceID), .assessmentProjection(result)):
            try result.validate()
            guard result.projection.workspaceID == query.workspaceID,
                  result.projection.assessment.evidence.evidenceID == evidenceID else {
                throw EvidenceQualityFailureV1.wrongWorkspace
            }
        case let (_, .notFound(boundQuery)):
            try boundQuery.validate()
            guard boundQuery == query else { throw EvidenceQualityFailureV1.receiptMismatch }
        default:
            throw EvidenceQualityFailureV1.invalidValue
        }
    }
}

enum EvidenceQualityReceiptRecoveryStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case effectCommittedAwaitingReceipt = "EFFECT_COMMITTED_AWAITING_RECEIPT"
    case receiptCommitted = "RECEIPT_COMMITTED"
}

struct EvidenceQualityMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let generationID: UUID
    let mutationID: MutationIDV1
    let commandSHA256: String
    let semanticSHA256: String
    let priorWorkspaceRevision: UInt64
    let resultingWorkspaceRevision: UInt64
    let recoveryState: EvidenceQualityReceiptRecoveryStateV1
    let committedAt: Date
    let receiptSHA256: String

    init(receiptID: UUID, command: EvidenceQualityMutationCommandV1,
         resultingWorkspaceRevision: UInt64, recoveryState: EvidenceQualityReceiptRecoveryStateV1,
         committedAt: Date) throws {
        try command.validate(); schemaVersion = Self.schemaVersion; self.receiptID = receiptID
        workspaceID = command.workspaceID; generationID = command.expectedRevision.generationID
        mutationID = command.mutationID; commandSHA256 = command.commandSHA256
        semanticSHA256 = command.payload.semanticSHA256
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision
        self.recoveryState = recoveryState; self.committedAt = committedAt
        receiptSHA256 = try EvidenceQualityValidationV1.canonicalSHA256(Basis(schemaVersion: Self.schemaVersion,
            receiptID: receiptID, workspaceID: command.workspaceID, generationID: command.expectedRevision.generationID,
            mutationID: command.mutationID, commandSHA256: command.commandSHA256,
            semanticSHA256: command.payload.semanticSHA256,
            priorWorkspaceRevision: command.expectedRevision.workspaceRevision,
            resultingWorkspaceRevision: resultingWorkspaceRevision, recoveryState: recoveryState, committedAt: committedAt))
        try validate(command: command)
    }
    func validate(command: EvidenceQualityMutationCommandV1) throws {
        try validate()
        guard workspaceID == command.workspaceID,
              generationID == command.expectedRevision.generationID, mutationID == command.mutationID,
              commandSHA256 == command.commandSHA256, semanticSHA256 == command.payload.semanticSHA256,
              priorWorkspaceRevision == command.expectedRevision.workspaceRevision else {
            throw EvidenceQualityFailureV1.receiptMismatch
        }
    }
    func validate() throws {
        try EvidenceQualityValidationV1.id(receiptID); try EvidenceQualityValidationV1.id(generationID)
        try EvidenceQualityValidationV1.instant(committedAt)
        let (next, overflow) = priorWorkspaceRevision.addingReportingOverflow(1)
        guard !overflow else { throw EvidenceQualityFailureV1.arithmeticOverflow }
        try EvidenceQualityValidationV1.digest(commandSHA256)
        try EvidenceQualityValidationV1.digest(semanticSHA256)
        guard schemaVersion == Self.schemaVersion, resultingWorkspaceRevision == next,
              receiptSHA256 == (try EvidenceQualityValidationV1.canonicalSHA256(basis)) else {
            throw EvidenceQualityFailureV1.receiptMismatch
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
        generationID: generationID, mutationID: mutationID, commandSHA256: commandSHA256,
        semanticSHA256: semanticSHA256, priorWorkspaceRevision: priorWorkspaceRevision,
        resultingWorkspaceRevision: resultingWorkspaceRevision, recoveryState: recoveryState, committedAt: committedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let generationID: UUID; let mutationID: MutationIDV1; let commandSHA256: String; let semanticSHA256: String; let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64; let recoveryState: EvidenceQualityReceiptRecoveryStateV1; let committedAt: Date }
}
