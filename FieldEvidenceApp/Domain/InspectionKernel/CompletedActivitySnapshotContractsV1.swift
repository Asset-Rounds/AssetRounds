import Foundation

enum SnapshotProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case duplicateIdentity
    case unorderedValue
    case missingBinding
    case wrongWorkspace
    case staleRevision
    case historyRewrite
    case digestMismatch
    case projectionDisagreement
    case privacyViolation
    case unsupportedAccessibilityClaim
    case hostileText
    case partialEffect
    case incompatibleVersion
}

struct CompletedSurveyDefinitionReferenceV1: Codable, Equatable, Sendable {
    let activityKind: ActivityKindV1
    let release: SurveyDefinitionReleaseReferenceV1
    init(release value: SurveyDefinitionReleaseV1) throws {
        try value.validate(); activityKind = value.activityKind; release = try .init(value)
    }
    func validate() throws { try release.validate() }
}

extension CompletedActivitySnapshotV1 {
    func validateAccessibleDocumentTree(_ tree:AccessibleDocumentSemanticTreeV1)throws{
        try validate();try tree.validate();guard tree.publication.snapshotSHA256==snapshotSHA256 else{throw AccessibleDocumentFailureV1.staleAssessment}
    }
}

enum SnapshotProjectionLimitsV1 {
    static let maximumIDBytes = 128
    static let maximumTextBytes = 4_096
    static let maximumServiceFacts = 256
    static let maximumEvidenceDetails = 256
    static let maximumHistoryFacts = 512
    static let maximumProjectionBytes = 8_388_608
}

enum SnapshotProjectionValidationV1 {
    static func validID(_ value: String) -> Bool {
        WorkflowGrammarValidationV1.validID(value)
    }

    static func validInstant(_ value: String) -> Bool {
        FindingContractValidationV1.validInstant(value)
    }

    static func instantDate(_ value: String) -> Date? {
        guard validInstant(value) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    static func validText(_ value: String, allowEmpty: Bool = false) -> Bool {
        guard (allowEmpty || !value.isEmpty), value.utf8.count <= SnapshotProjectionLimitsV1.maximumTextBytes else {
            return false
        }
        guard value == value.precomposedStringWithCanonicalMapping else { return false }
        for scalar in value.unicodeScalars {
            let number = scalar.value
            if number < 0x20 { return false }
            if number == 0x7F || (0x80...0x9F).contains(number) { return false }
            if [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069].contains(number) { return false }
            if (number & 0xFFFF) == 0xFFFE || (number & 0xFFFF) == 0xFFFF { return false }
        }
        return true
    }

    static func requireSortedUnique<T: Comparable & Hashable>(_ values: [T]) throws {
        guard values == values.sorted(), Set(values).count == values.count else {
            throw SnapshotProjectionFailureV1.unorderedValue
        }
    }
}

struct ClosedContractCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum ClosedContractDecodingV1 {
    static func rejectUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: ClosedContractCodingKeyV1.self)
        guard Set(container.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }

    static func decodeOptional<T: Decodable, Key: CodingKey>(
        _ type: T.Type,
        from values: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> T? {
        guard values.contains(key) else { return nil }
        if try values.decodeNil(forKey: key) {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        return try values.decode(type, forKey: key)
    }
}

struct CompletedServiceFactV1: Codable, Equatable, Hashable, Comparable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case serviceRequest = "SERVICE_REQUEST"
        case serviceStatus = "SERVICE_STATUS"
        case serviceHistory = "SERVICE_HISTORY"
    }

    let factID: String
    let kind: Kind
    let privacyClass: ReportPrivacyClassV1
    let label: String
    let value: String
    let effectiveAt: String?

    static func < (lhs: CompletedServiceFactV1, rhs: CompletedServiceFactV1) -> Bool {
        lhs.factID < rhs.factID
    }

    init(factID: String, kind: Kind, privacyClass: ReportPrivacyClassV1, label: String, value: String, effectiveAt: String?) throws {
        guard SnapshotProjectionValidationV1.validID(factID),
              SnapshotProjectionValidationV1.validText(label),
              SnapshotProjectionValidationV1.validText(value),
              effectiveAt.map(SnapshotProjectionValidationV1.validInstant) ?? true else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        self.factID = factID
        self.kind = kind
        self.privacyClass = privacyClass
        self.label = label
        self.value = value
        self.effectiveAt = effectiveAt
    }

    func validate() throws {
        guard SnapshotProjectionValidationV1.validID(factID),
              SnapshotProjectionValidationV1.validText(label),
              SnapshotProjectionValidationV1.validText(value),
              effectiveAt.map(SnapshotProjectionValidationV1.validInstant) ?? true else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case factID, kind, privacyClass, label, value, effectiveAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(["factID", "kind", "privacyClass", "label", "value", "effectiveAt"])
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            factID: values.decode(String.self, forKey: .factID),
            kind: values.decode(Kind.self, forKey: .kind),
            privacyClass: values.decode(ReportPrivacyClassV1.self, forKey: .privacyClass),
            label: values.decode(String.self, forKey: .label),
            value: values.decode(String.self, forKey: .value),
            effectiveAt: ClosedContractDecodingV1.decodeOptional(
                String.self, from: values, forKey: .effectiveAt
            )
        )
    }
}

struct CompletedActivitySnapshotPayloadV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: String
    let snapshotID: String
    let snapshotRevision: Int
    let sourceActivityID: String
    let sourceRevision: Int
    let reportID: String
    let packageReleaseID: String
    let generatedAt: String
    let completedAt: String
    let supersedesSnapshotID: String?
    let supersededSnapshotSHA256: String?
    let amendmentReason: String?
    let profileBinding: FinalizedReportProfileBindingV1
    let serviceFacts: [CompletedServiceFactV1]
    let evidenceCards: [EvidenceDetailCardV1]
    let limitations: [String]

    init(
        workspaceID: String,
        snapshotID: String,
        snapshotRevision: Int,
        sourceActivityID: String,
        sourceRevision: Int,
        reportID: String,
        packageReleaseID: String,
        generatedAt: String,
        completedAt: String,
        supersedesSnapshotID: String?,
        supersededSnapshotSHA256: String?,
        amendmentReason: String?,
        profileBinding: FinalizedReportProfileBindingV1,
        serviceFacts: [CompletedServiceFactV1],
        evidenceCards: [EvidenceDetailCardV1],
        limitations: [String]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.snapshotID = snapshotID
        self.snapshotRevision = snapshotRevision
        self.sourceActivityID = sourceActivityID
        self.sourceRevision = sourceRevision
        self.reportID = reportID
        self.packageReleaseID = packageReleaseID
        self.generatedAt = generatedAt
        self.completedAt = completedAt
        self.supersedesSnapshotID = supersedesSnapshotID
        self.supersededSnapshotSHA256 = supersededSnapshotSHA256
        self.amendmentReason = amendmentReason
        self.profileBinding = profileBinding
        self.serviceFacts = serviceFacts
        self.evidenceCards = evidenceCards
        self.limitations = limitations
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        guard let generatedDate = SnapshotProjectionValidationV1.instantDate(generatedAt),
              let completedDate = SnapshotProjectionValidationV1.instantDate(completedAt),
              SnapshotProjectionValidationV1.validID(workspaceID),
              SnapshotProjectionValidationV1.validID(snapshotID), snapshotRevision > 0,
              SnapshotProjectionValidationV1.validID(sourceActivityID), sourceRevision > 0,
              SnapshotProjectionValidationV1.validID(reportID),
              SnapshotProjectionValidationV1.validID(packageReleaseID),
              generatedDate >= completedDate,
              serviceFacts.count <= SnapshotProjectionLimitsV1.maximumServiceFacts,
              evidenceCards.count <= SnapshotProjectionLimitsV1.maximumEvidenceDetails,
              !limitations.isEmpty,
              limitations.allSatisfy({ SnapshotProjectionValidationV1.validText($0) }) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        if snapshotRevision == 1 {
            guard supersedesSnapshotID == nil,
                  supersededSnapshotSHA256 == nil,
                  amendmentReason == nil else {
                throw SnapshotProjectionFailureV1.historyRewrite
            }
        } else {
            guard let supersedesSnapshotID,
                  SnapshotProjectionValidationV1.validID(supersedesSnapshotID),
                  supersedesSnapshotID != snapshotID,
                  let supersededSnapshotSHA256,
                  KernelCanonicalHashV1.validSHA256(supersededSnapshotSHA256),
                  let amendmentReason,
                  SnapshotProjectionValidationV1.validText(amendmentReason) else {
                throw SnapshotProjectionFailureV1.historyRewrite
            }
        }
        try profileBinding.validate()
        guard profileBinding.workspaceID == workspaceID,
              profileBinding.snapshotID == snapshotID else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        try SnapshotProjectionValidationV1.requireSortedUnique(serviceFacts.map(\.factID))
        try SnapshotProjectionValidationV1.requireSortedUnique(evidenceCards.map(\.cardID))
        try SnapshotProjectionValidationV1.requireSortedUnique(limitations)
        try serviceFacts.forEach { try $0.validate() }
        try evidenceCards.forEach { try $0.validate() }
        guard evidenceCards.allSatisfy({
            $0.workspaceID == workspaceID
                && $0.outputScopeID == profileBinding.outputScopeID
                && $0.audience == profileBinding.audience
                && $0.privacyTransformID == profileBinding.privacyTransformID
        }) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        if profileBinding.audience == .customerSafe,
           (serviceFacts.contains(where: { $0.privacyClass == .internalOnly })
            || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: serviceFacts.flatMap { [$0.label, $0.value] }
            )) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        let outputReferenceIDs = evidenceCards.flatMap { $0.outputReferences.map(\.outputReferenceID) }
        guard Set(outputReferenceIDs).count == outputReferenceIDs.count else {
            throw SnapshotProjectionFailureV1.duplicateIdentity
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, workspaceID, snapshotID, snapshotRevision, sourceActivityID, sourceRevision
        case reportID, packageReleaseID, generatedAt, completedAt, supersedesSnapshotID
        case supersededSnapshotSHA256, amendmentReason, profileBinding, serviceFacts, evidenceCards, limitations
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set([
                "schemaVersion", "workspaceID", "snapshotID", "snapshotRevision", "sourceActivityID",
                "sourceRevision", "reportID", "packageReleaseID", "generatedAt", "completedAt",
                "supersedesSnapshotID", "supersededSnapshotSHA256", "amendmentReason", "profileBinding",
                "serviceFacts", "evidenceCards", "limitations",
            ])
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            workspaceID: values.decode(String.self, forKey: .workspaceID),
            snapshotID: values.decode(String.self, forKey: .snapshotID),
            snapshotRevision: values.decode(Int.self, forKey: .snapshotRevision),
            sourceActivityID: values.decode(String.self, forKey: .sourceActivityID),
            sourceRevision: values.decode(Int.self, forKey: .sourceRevision),
            reportID: values.decode(String.self, forKey: .reportID),
            packageReleaseID: values.decode(String.self, forKey: .packageReleaseID),
            generatedAt: values.decode(String.self, forKey: .generatedAt),
            completedAt: values.decode(String.self, forKey: .completedAt),
            supersedesSnapshotID: ClosedContractDecodingV1.decodeOptional(
                String.self, from: values, forKey: .supersedesSnapshotID
            ),
            supersededSnapshotSHA256: ClosedContractDecodingV1.decodeOptional(
                String.self, from: values, forKey: .supersededSnapshotSHA256
            ),
            amendmentReason: ClosedContractDecodingV1.decodeOptional(
                String.self, from: values, forKey: .amendmentReason
            ),
            profileBinding: values.decode(FinalizedReportProfileBindingV1.self, forKey: .profileBinding),
            serviceFacts: values.decode([CompletedServiceFactV1].self, forKey: .serviceFacts),
            evidenceCards: values.decode([EvidenceDetailCardV1].self, forKey: .evidenceCards),
            limitations: values.decode([String].self, forKey: .limitations)
        )
    }
}

struct CompletedActivitySnapshotV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV1
    let snapshotSHA256: String

    var id: String { "\(payload.workspaceID)|\(payload.snapshotID)" }

    private init(payload: CompletedActivitySnapshotPayloadV1, snapshotSHA256: String) throws {
        guard KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV1) throws -> CompletedActivitySnapshotV1 {
        guard payload.snapshotRevision == 1, payload.supersedesSnapshotID == nil,
              payload.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        let bytes = try CompletedActivitySnapshotCanonicalCodecV1.encodePayload(payload)
        return try .init(payload: payload, snapshotSHA256: KernelCanonicalHashV1.sha256(bytes))
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV1,
        superseding prior: CompletedActivitySnapshotV1
    ) throws -> CompletedActivitySnapshotV1 {
        let bytes = try CompletedActivitySnapshotCanonicalCodecV1.encodePayload(payload)
        let candidate = try CompletedActivitySnapshotV1(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(bytes)
        )
        try candidate.validateSupersession(of: prior)
        return candidate
    }

    func validateImmutableIdentity(against other: CompletedActivitySnapshotV1) throws {
        try validate()
        try other.validate()
        guard payload.workspaceID == other.payload.workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
        guard payload.snapshotID == other.payload.snapshotID else { throw SnapshotProjectionFailureV1.historyRewrite }
        guard self == other else { throw SnapshotProjectionFailureV1.historyRewrite }
    }

    func validateSupersession(of prior: CompletedActivitySnapshotV1) throws {
        try validate()
        try prior.validate()
        guard payload.workspaceID == prior.payload.workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
        guard let generatedDate = SnapshotProjectionValidationV1.instantDate(payload.generatedAt),
              let priorGeneratedDate = SnapshotProjectionValidationV1.instantDate(prior.payload.generatedAt) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        guard payload.snapshotRevision == prior.payload.snapshotRevision + 1,
              payload.supersedesSnapshotID == prior.payload.snapshotID,
              payload.supersededSnapshotSHA256 == prior.snapshotSHA256,
              payload.sourceActivityID == prior.payload.sourceActivityID,
              payload.reportID == prior.payload.reportID,
              payload.completedAt == prior.payload.completedAt,
              generatedDate >= priorGeneratedDate,
              payload.sourceRevision > prior.payload.sourceRevision else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        guard KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try payload.validate()
        let expected = KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV1.encodePayload(payload)
        )
        guard snapshotSHA256 == expected else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(["schemaVersion", "payload", "snapshotSHA256"])
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV1.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotChainV1 {
    static func validate(_ snapshots: [CompletedActivitySnapshotV1]) throws {
        guard !snapshots.isEmpty else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        try snapshots.forEach { try $0.validate() }
        guard snapshots.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              snapshots.map(\.payload.snapshotRevision) == Array(1...snapshots.count),
              Set(snapshots.map(\.payload.snapshotID)).count == snapshots.count,
              Set(snapshots.map(\.snapshotSHA256)).count == snapshots.count,
              snapshots[0].payload.supersedesSnapshotID == nil,
              snapshots[0].payload.supersededSnapshotSHA256 == nil,
              snapshots[0].payload.amendmentReason == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        for index in snapshots.indices.dropFirst() {
            try snapshots[index].validateSupersession(of: snapshots[index - 1])
        }
    }
}

enum CompletedActivitySnapshotCanonicalCodecV1 {
    private static func makeEncoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV1) throws -> Data {
        try payload.validate()
        let data = try makeEncoder().encode(payload)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV1) throws -> Data {
        try snapshot.validate()
        let data = try makeEncoder().encode(snapshot)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoded = try JSONDecoder().decode(CompletedActivitySnapshotV1.self, from: data)
        try decoded.validate()
        guard try encode(decoded) == data else { throw SnapshotProjectionFailureV1.digestMismatch }
        return decoded
    }
}

/// Additive location/composition release. V1 remains byte-for-byte unchanged.
struct CompletedActivitySnapshotPayloadV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotPayloadV1
    let assetID: UUID
    let locationComposition: CompletedLocationCompositionSnapshotV1

    init(
        activity: CompletedActivitySnapshotPayloadV1,
        assetID: UUID,
        locationComposition: CompletedLocationCompositionSnapshotV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.assetID = assetID
        self.locationComposition = locationComposition
        try validate()
    }

    func validate() throws {
        try activity.validate()
        try locationComposition.validate()
        guard schemaVersion == Self.schemaVersion,
              UUID(uuidString: activity.workspaceID)
                == locationComposition.workspaceID.rawValue,
              assetID == locationComposition.assetID else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, assetID, locationComposition
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotPayloadV1.self, forKey: .activity),
            assetID: values.decode(UUID.self, forKey: .assetID),
            locationComposition: values.decode(
                CompletedLocationCompositionSnapshotV1.self,
                forKey: .locationComposition
            )
        )
    }
}

struct CompletedActivitySnapshotV2: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV2
    let snapshotSHA256: String

    var id: String { "\(payload.activity.workspaceID)|\(payload.activity.snapshotID)" }

    private init(payload: CompletedActivitySnapshotPayloadV2, snapshotSHA256: String) throws {
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV2) throws -> Self {
        guard payload.activity.snapshotRevision == 1,
              payload.activity.supersedesSnapshotID == nil,
              payload.activity.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV2.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV2,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV2.encodePayload(payload)
            )
        )
        try value.validateSupersession(of: prior)
        return value
    }

    func validateSupersession(of prior: Self) throws {
        try validate(); try prior.validate()
        let current = payload.activity
        let previous = prior.payload.activity
        guard current.workspaceID == previous.workspaceID,
              current.snapshotRevision == previous.snapshotRevision + 1,
              current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID,
              current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision,
              payload.locationComposition.frozenAtRevision
                >= prior.payload.locationComposition.frozenAtRevision,
              let currentDate = SnapshotProjectionValidationV1.instantDate(current.generatedAt),
              let previousDate = SnapshotProjectionValidationV1.instantDate(previous.generatedAt),
              currentDate >= previousDate else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        let expected = KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV2.encodePayload(payload)
        )
        guard snapshotSHA256 == expected else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV2.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV2 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV2) throws -> Data {
        try payload.validate()
        let data = try encoder().encode(payload)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV2) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(snapshot)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV2 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(CompletedActivitySnapshotV2.self, from: data)
        try value.validate()
        guard try encode(value) == data else { throw SnapshotProjectionFailureV1.digestMismatch }
        return value
    }
}

/// Frozen, report-facing accountability projection.  The canonical party,
/// role, actor, qualification, and signoff rows remain owned by C38's writer
/// and persistence contracts; this value only captures the exact values used
/// by one completed activity/report.  It contains no contact point, login,
/// authorization, identity-verification, or legal-signature data.
struct CompletedAccountabilitySnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let parties: [ServicePartyReferenceV1]
    let roleEvents: [SitePartyRoleEventV1]
    let actors: [ActorSnapshotV1]
    let qualifications: [QualificationSnapshotV1]
    let signoffs: [SignoffSnapshotV1]
    let snapshotSHA256: String

    /// Compatibility spelling for report/search adapters that refer to the
    /// relationship collection as history.
    var roleHistory: [SitePartyRoleEventV1] { roleEvents }

    init(
        workspaceID: WorkspaceID,
        parties: [ServicePartyReferenceV1] = [],
        roleEvents: [SitePartyRoleEventV1] = [],
        actors: [ActorSnapshotV1] = [],
        qualifications: [QualificationSnapshotV1] = [],
        signoffs: [SignoffSnapshotV1] = []
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.parties = parties.sorted { $0.partyID.uuidString < $1.partyID.uuidString }
        self.roleEvents = roleEvents.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        self.actors = actors.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
        self.qualifications = qualifications.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
        self.signoffs = signoffs.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            parties: self.parties,
            roleEvents: self.roleEvents,
            actors: self.actors,
            qualifications: self.qualifications,
            signoffs: self.signoffs
        ))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              KernelCanonicalHashV1.validSHA256(snapshotSHA256),
              parties.count <= SnapshotProjectionLimitsV1.maximumServiceFacts,
              roleEvents.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              actors.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              qualifications.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              signoffs.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              parties.map({ $0.partyID.uuidString }) == parties.map({ $0.partyID.uuidString }).sorted(),
              roleEvents.map({ $0.eventID.uuidString }) == roleEvents.map({ $0.eventID.uuidString }).sorted(),
              actors.map({ $0.snapshotID.uuidString }) == actors.map({ $0.snapshotID.uuidString }).sorted(),
              qualifications.map({ $0.snapshotID.uuidString }) == qualifications.map({ $0.snapshotID.uuidString }).sorted(),
              signoffs.map({ $0.snapshotID.uuidString }) == signoffs.map({ $0.snapshotID.uuidString }).sorted(),
              Set(parties.map(\.partyID)).count == parties.count,
              Set(roleEvents.map(\.eventID)).count == roleEvents.count,
              Set(actors.map(\.snapshotID)).count == actors.count,
              Set(qualifications.map(\.snapshotID)).count == qualifications.count,
              Set(signoffs.map(\.snapshotID)).count == signoffs.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }

        try parties.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
        }
        let partyIDs = Set(parties.map(\.partyID))
        try roleEvents.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID, partyIDs.contains($0.partyID) else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
        try actors.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
            if let partyID = $0.actor.partyID, !partyIDs.contains(partyID) {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
        try qualifications.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
        }
        let qualificationsByID = Dictionary(
            uniqueKeysWithValues: qualifications.map { ($0.snapshotID, $0) }
        )
        try signoffs.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
            if let qualification = $0.qualification {
                guard qualificationsByID[qualification.snapshotID] == qualification else {
                    throw SnapshotProjectionFailureV1.invalidValue
                }
            }
        }

        let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            parties: parties,
            roleEvents: roleEvents,
            actors: actors,
            qualifications: qualifications,
            signoffs: signoffs
        ))
        guard snapshotSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let parties: [ServicePartyReferenceV1]
        let roleEvents: [SitePartyRoleEventV1]
        let actors: [ActorSnapshotV1]
        let qualifications: [QualificationSnapshotV1]
        let signoffs: [SignoffSnapshotV1]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, parties, roleEvents, actors
        case qualifications, signoffs, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let rebuilt = try Self(
            workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
            parties: values.decode([ServicePartyReferenceV1].self, forKey: .parties),
            roleEvents: values.decode([SitePartyRoleEventV1].self, forKey: .roleEvents),
            actors: values.decode([ActorSnapshotV1].self, forKey: .actors),
            qualifications: values.decode([QualificationSnapshotV1].self, forKey: .qualifications),
            signoffs: values.decode([SignoffSnapshotV1].self, forKey: .signoffs)
        )
        guard try values.decode(String.self, forKey: .snapshotSHA256) == rebuilt.snapshotSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = rebuilt
    }
}

/// Additive completed-activity release for C38.  V1 and V2 payloads remain
/// unchanged; accountability is optional so a site-only migrated activity can
/// be represented explicitly without inventing a party or signoff.
struct CompletedActivitySnapshotPayloadV3: Codable, Equatable, Sendable {
    static let schemaVersion = 3
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotPayloadV2
    let accountability: CompletedAccountabilitySnapshotV1?

    init(
        activity: CompletedActivitySnapshotPayloadV2,
        accountability: CompletedAccountabilitySnapshotV1? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.accountability = accountability
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try activity.validate()
        if let accountability {
            try accountability.validate()
            guard accountability.workspaceID.rawValue.uuidString.lowercased()
                    == activity.activity.workspaceID.lowercased() else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, accountability
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotPayloadV2.self, forKey: .activity),
            accountability: values.decodeIfPresent(
                CompletedAccountabilitySnapshotV1.self,
                forKey: .accountability
            )
        )
    }
}

struct CompletedActivitySnapshotV3: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 3
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV3
    let snapshotSHA256: String

    var id: String { "\(payload.activity.activity.workspaceID)|\(payload.activity.activity.snapshotID)" }

    private init(payload: CompletedActivitySnapshotPayloadV3, snapshotSHA256: String) throws {
        guard KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV3) throws -> Self {
        guard payload.activity.activity.snapshotRevision == 1,
              payload.activity.activity.supersedesSnapshotID == nil,
              payload.activity.activity.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV3.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV3,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV3.encodePayload(payload)
            )
        )
        try value.validateSupersession(of: prior)
        return value
    }

    func validateSupersession(of prior: Self) throws {
        try validate()
        try prior.validate()
        let current = payload.activity.activity
        let previous = prior.payload.activity.activity
        let (expectedSnapshotRevision, revisionOverflowed) =
            previous.snapshotRevision.addingReportingOverflow(1)
        guard current.workspaceID == previous.workspaceID,
              !revisionOverflowed,
              current.snapshotRevision == expectedSnapshotRevision,
              current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID,
              current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision,
              payload.activity.locationComposition.frozenAtRevision
                    >= prior.payload.activity.locationComposition.frozenAtRevision,
              let currentDate = SnapshotProjectionValidationV1.instantDate(current.generatedAt),
              let previousDate = SnapshotProjectionValidationV1.instantDate(previous.generatedAt),
              currentDate >= previousDate else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        let expected = KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV3.encodePayload(payload)
        )
        guard snapshotSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV3.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV3 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV3) throws -> Data {
        try payload.validate()
        let data = try encoder().encode(payload)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV3) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(snapshot)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV3 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(CompletedActivitySnapshotV3.self, from: data)
        try value.validate()
        guard try encode(value) == data else { throw SnapshotProjectionFailureV1.digestMismatch }
        return value
    }
}

/// Additive C39 semantic projection.  The wrapper is intentionally a frozen
/// projection over the canonical asset-semantic records; it carries no
/// operational disposition or inferred product truth.
struct CompletedAssetSemanticsSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let catalogReleases: [AssetSemanticCatalogReleaseReferenceV1]
    let kindBindings: [AssetKindBindingEventV1]
    let workflowCapabilityBindings: [AssetWorkflowCapabilityBindingEventV1]
    let productIdentities: [AssetProductIdentityV1]
    let lifecycleEvents: [AssetLifecycleEventV1]
    let successorLinks: [AssetSuccessorLinkV1]
    let workSubjectScopes: [WorkSubjectScopeSnapshotV1]
    let snapshotSHA256: String

    init(
        workspaceID: WorkspaceID,
        catalogReleases: [AssetSemanticCatalogReleaseReferenceV1],
        kindBindings: [AssetKindBindingEventV1],
        workflowCapabilityBindings: [AssetWorkflowCapabilityBindingEventV1],
        productIdentities: [AssetProductIdentityV1],
        lifecycleEvents: [AssetLifecycleEventV1],
        successorLinks: [AssetSuccessorLinkV1],
        workSubjectScopes: [WorkSubjectScopeSnapshotV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.catalogReleases = catalogReleases.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
        self.kindBindings = kindBindings.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        self.workflowCapabilityBindings = workflowCapabilityBindings.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        self.productIdentities = productIdentities.sorted { $0.identityID.uuidString < $1.identityID.uuidString }
        self.lifecycleEvents = lifecycleEvents.sorted { $0.record.eventID.uuidString < $1.record.eventID.uuidString }
        self.successorLinks = successorLinks.sorted { $0.linkID.uuidString < $1.linkID.uuidString }
        self.workSubjectScopes = workSubjectScopes.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            catalogReleases: self.catalogReleases,
            kindBindings: self.kindBindings,
            workflowCapabilityBindings: self.workflowCapabilityBindings,
            productIdentities: self.productIdentities,
            lifecycleEvents: self.lifecycleEvents,
            successorLinks: self.successorLinks,
            workSubjectScopes: self.workSubjectScopes
        ))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              KernelCanonicalHashV1.validSHA256(snapshotSHA256),
              catalogReleases.count <= 512,
              kindBindings.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              workflowCapabilityBindings.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              productIdentities.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              lifecycleEvents.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              successorLinks.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              workSubjectScopes.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              !catalogReleases.isEmpty || !kindBindings.isEmpty || !workflowCapabilityBindings.isEmpty
                || !productIdentities.isEmpty || !lifecycleEvents.isEmpty || !successorLinks.isEmpty
                || !workSubjectScopes.isEmpty,
              catalogReleases.map({ $0.releaseID.uuidString }) == catalogReleases.map({ $0.releaseID.uuidString }).sorted(),
              kindBindings.map({ $0.eventID.uuidString }) == kindBindings.map({ $0.eventID.uuidString }).sorted(),
              workflowCapabilityBindings.map({ $0.eventID.uuidString }) == workflowCapabilityBindings.map({ $0.eventID.uuidString }).sorted(),
              productIdentities.map({ $0.identityID.uuidString }) == productIdentities.map({ $0.identityID.uuidString }).sorted(),
              lifecycleEvents.map({ $0.record.eventID.uuidString }) == lifecycleEvents.map({ $0.record.eventID.uuidString }).sorted(),
              successorLinks.map({ $0.linkID.uuidString }) == successorLinks.map({ $0.linkID.uuidString }).sorted(),
              workSubjectScopes.map({ $0.snapshotID.uuidString }) == workSubjectScopes.map({ $0.snapshotID.uuidString }).sorted(),
              Set(catalogReleases.map(\.releaseID)).count == catalogReleases.count,
              Set(kindBindings.map(\.eventID)).count == kindBindings.count,
              Set(workflowCapabilityBindings.map(\.eventID)).count == workflowCapabilityBindings.count,
              Set(productIdentities.map(\.identityID)).count == productIdentities.count,
              Set(lifecycleEvents.map({ $0.record.eventID })).count == lifecycleEvents.count,
              Set(successorLinks.map(\.linkID)).count == successorLinks.count,
              Set(workSubjectScopes.map(\.snapshotID)).count == workSubjectScopes.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }

        try catalogReleases.forEach { try $0.validate() }
        let releaseIDs = Set(catalogReleases.map(\.releaseID))
        try kindBindings.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID, releaseIDs.contains($0.catalogRelease.releaseID) else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
        let kindByID = Dictionary(uniqueKeysWithValues: kindBindings.map { ($0.eventID, $0) })
        try workflowCapabilityBindings.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID,
                  let kind = kindByID[$0.kindBindingEventID],
                  kind.assetID == $0.assetID,
                  kind.revision == $0.kindBindingRevision,
                  kind.workspaceID == $0.workspaceID else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        try productIdentities.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
        }
        let successorByID = Dictionary(uniqueKeysWithValues: successorLinks.map { ($0.linkID, $0) })
        try AssetSuccessorLinkV1.validateAcyclic(successorLinks)
        try lifecycleEvents.forEach { event in
            try event.validate()
            guard event.record.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
            if event.kind == .classificationChangedRecorded {
                guard let id = event.record.kindBindingEventID, let kind = kindByID[id] else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
                try event.validateAtomicReference(kindBinding: kind)
            }
            if event.kind == .replacedRecorded {
                guard let id = event.record.successorLinkID, let link = successorByID[id] else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
                try event.validateAtomicReference(successorLink: link)
            }
        }
        try workSubjectScopes.forEach { scope in
            try scope.validate()
            guard scope.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
            for binding in scope.semanticBindings {
                guard let kind = kindByID[binding.kindBindingEventID],
                      kind.assetID == binding.assetID,
                      kind.revision == binding.kindBindingRevision,
                      kind.catalogRelease == binding.catalogRelease else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
            }
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            catalogReleases: catalogReleases,
            kindBindings: kindBindings,
            workflowCapabilityBindings: workflowCapabilityBindings,
            productIdentities: productIdentities,
            lifecycleEvents: lifecycleEvents,
            successorLinks: successorLinks,
            workSubjectScopes: workSubjectScopes
        ))
        guard snapshotSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let catalogReleases: [AssetSemanticCatalogReleaseReferenceV1]
        let kindBindings: [AssetKindBindingEventV1]
        let workflowCapabilityBindings: [AssetWorkflowCapabilityBindingEventV1]
        let productIdentities: [AssetProductIdentityV1]
        let lifecycleEvents: [AssetLifecycleEventV1]
        let successorLinks: [AssetSuccessorLinkV1]
        let workSubjectScopes: [WorkSubjectScopeSnapshotV1]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, catalogReleases, kindBindings
        case workflowCapabilityBindings, productIdentities, lifecycleEvents
        case successorLinks, workSubjectScopes, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let rebuilt = try Self(
            workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
            catalogReleases: values.decode([AssetSemanticCatalogReleaseReferenceV1].self, forKey: .catalogReleases),
            kindBindings: values.decode([AssetKindBindingEventV1].self, forKey: .kindBindings),
            workflowCapabilityBindings: values.decode([AssetWorkflowCapabilityBindingEventV1].self, forKey: .workflowCapabilityBindings),
            productIdentities: values.decode([AssetProductIdentityV1].self, forKey: .productIdentities),
            lifecycleEvents: values.decode([AssetLifecycleEventV1].self, forKey: .lifecycleEvents),
            successorLinks: values.decode([AssetSuccessorLinkV1].self, forKey: .successorLinks),
            workSubjectScopes: values.decode([WorkSubjectScopeSnapshotV1].self, forKey: .workSubjectScopes)
        )
        guard try values.decode(String.self, forKey: .snapshotSHA256) == rebuilt.snapshotSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = rebuilt
    }
}

typealias CompletedAssetSemanticSnapshotV1 = CompletedAssetSemanticsSnapshotV1

struct CompletedActivitySnapshotPayloadV4: Codable, Equatable, Sendable {
    static let schemaVersion = 4
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotPayloadV3
    let assetSemantics: CompletedAssetSemanticsSnapshotV1?

    init(
        activity: CompletedActivitySnapshotPayloadV3,
        assetSemantics: CompletedAssetSemanticsSnapshotV1? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.assetSemantics = assetSemantics
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try activity.validate()
        if let assetSemantics {
            try assetSemantics.validate()
            guard assetSemantics.workspaceID.rawValue.uuidString.lowercased()
                    == activity.activity.activity.workspaceID.lowercased() else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, assetSemantics
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotPayloadV3.self, forKey: .activity),
            assetSemantics: values.decodeIfPresent(
                CompletedAssetSemanticsSnapshotV1.self, forKey: .assetSemantics
            )
        )
    }
}

struct CompletedActivitySnapshotV4: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 4
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV4
    let snapshotSHA256: String

    var id: String { "\(payload.activity.activity.activity.workspaceID)|\(payload.activity.activity.activity.snapshotID)" }

    private init(payload: CompletedActivitySnapshotPayloadV4, snapshotSHA256: String) throws {
        guard KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV4) throws -> Self {
        guard payload.activity.activity.activity.snapshotRevision == 1,
              payload.activity.activity.activity.supersedesSnapshotID == nil,
              payload.activity.activity.activity.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV4.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV4,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV4.encodePayload(payload)
            )
        )
        try value.validateSupersession(of: prior)
        return value
    }

    func validateSupersession(of prior: Self) throws {
        try validate()
        try prior.validate()
        let current = payload.activity.activity.activity
        let previous = prior.payload.activity.activity.activity
        let (expectedRevision, overflowed) = previous.snapshotRevision.addingReportingOverflow(1)
        guard current.workspaceID == previous.workspaceID,
              !overflowed,
              current.snapshotRevision == expectedRevision,
              current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID,
              current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision,
              payload.activity.activity.locationComposition.frozenAtRevision
                    >= prior.payload.activity.activity.locationComposition.frozenAtRevision,
              let currentDate = SnapshotProjectionValidationV1.instantDate(current.generatedAt),
              let previousDate = SnapshotProjectionValidationV1.instantDate(previous.generatedAt),
              currentDate >= previousDate else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        let expected = KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV4.encodePayload(payload)
        )
        guard snapshotSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV4.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV4 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV4) throws -> Data {
        try payload.validate()
        let data = try encoder().encode(payload)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV4) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(snapshot)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV4 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(CompletedActivitySnapshotV4.self, from: data)
        try value.validate()
        guard try encode(value) == data else { throw SnapshotProjectionFailureV1.digestMismatch }
        return value
    }
}

/// Frozen C40 authority/criterion facts captured at completion. This aggregate
/// preserves exact historic records; presentation layers omit licensed content
/// references and raw locators.
struct CompletedAuthorityCriterionSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let aggregate: AuthorityCriterionAggregateV1
    let snapshotSHA256: String

    init(workspaceID: WorkspaceID, aggregate: AuthorityCriterionAggregateV1) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.aggregate = Self.canonicalized(aggregate)
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, workspaceID: workspaceID,
            aggregate: self.aggregate
        ))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try AuthorityCriterionRegistryV1.validate(aggregate, workspaceID: workspaceID)
        for value in aggregate.severityMappingReleases {
            guard value.workspaceID == workspaceID else { throw SnapshotProjectionFailureV1.wrongWorkspace }
        }
        let sources = Dictionary(uniqueKeysWithValues: aggregate.sourceReleases.map { ($0.releaseID, $0) })
        let bases = Dictionary(uniqueKeysWithValues: aggregate.basisBindings.map { ($0.bindingID, $0) })
        let applicability = Dictionary(uniqueKeysWithValues: aggregate.applicabilityContexts.map { ($0.snapshotID, $0) })
        let scopes = Dictionary(uniqueKeysWithValues: aggregate.assessmentScopes.map { ($0.snapshotID, $0) })
        let scales = Dictionary(uniqueKeysWithValues: aggregate.severityScaleReleases.map { ($0.releaseID, $0) })
        let protocols = Dictionary(uniqueKeysWithValues: aggregate.measurementProtocolReleases.map { ($0.releaseID, $0) })
        let evaluators = Dictionary(uniqueKeysWithValues: aggregate.evaluatorDescriptors.map { ($0.descriptorID, $0) })
        guard aggregate.basisBindings.allSatisfy({ sources[$0.authorityReleaseID] != nil }),
              aggregate.applicabilityContexts.allSatisfy({ context in
                  context.basisBindings.allSatisfy {
                      sources[$0.authorityReleaseID] != nil && bases[$0.bindingID] == $0
                  }
              }),
              aggregate.assessmentScopes.allSatisfy({ scope in
                  guard let context = applicability[scope.applicabilityContextID] else { return false }
                  return context.workSubjectScope == scope.workSubjectScope
              }),
              aggregate.classificationBindings.allSatisfy({ value in
                  guard let scope = scopes[value.assessmentScopeID],
                        applicability[value.applicabilityContextID] != nil,
                        scope.applicabilityContextID == value.applicabilityContextID,
                        scope.includedCriterionIDs.contains(value.criterionID) else { return false }
                  guard let releaseID = value.severityScaleReleaseID,
                        let levelID = value.severityLevelID else { return true }
                  return scales[releaseID]?.levels.contains(where: { $0.levelID == levelID }) == true
              }),
              aggregate.measurementProtocolReleases.allSatisfy({ evaluators[$0.evaluatorDescriptorID] != nil }),
              aggregate.derivedFacts.allSatisfy({ value in
                  protocols[value.protocolReleaseID]?.evaluatorDescriptorID == value.evaluatorDescriptorID
                      && evaluators[value.evaluatorDescriptorID] != nil
              }) else { throw SnapshotProjectionFailureV1.missingBinding }
        let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion, workspaceID: workspaceID, aggregate: aggregate
        ))
        guard snapshotSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private static func canonicalized(_ value: AuthorityCriterionAggregateV1) -> AuthorityCriterionAggregateV1 {
        AuthorityCriterionAggregateV1(
            sourceReleases: value.sourceReleases.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString },
            basisBindings: value.basisBindings.sorted { $0.bindingID.uuidString < $1.bindingID.uuidString },
            applicabilityContexts: value.applicabilityContexts.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString },
            assessmentScopes: value.assessmentScopes.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString },
            severityScaleReleases: value.severityScaleReleases.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString },
            severityMappingReleases: value.severityMappingReleases.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString },
            classificationBindings: value.classificationBindings.sorted { $0.bindingID.uuidString < $1.bindingID.uuidString },
            measurementProtocolReleases: value.measurementProtocolReleases.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString },
            evaluatorDescriptors: value.evaluatorDescriptors.sorted { $0.descriptorID.uuidString < $1.descriptorID.uuidString },
            derivedFacts: value.derivedFacts.sorted { $0.provenanceID.uuidString < $1.provenanceID.uuidString }
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let aggregate: AuthorityCriterionAggregateV1
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, aggregate, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let rebuilt = try Self(
            workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
            aggregate: values.decode(AuthorityCriterionAggregateV1.self, forKey: .aggregate)
        )
        guard try values.decode(String.self, forKey: .snapshotSHA256) == rebuilt.snapshotSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = rebuilt
    }
}

struct CompletedActivitySnapshotPayloadV5: Codable, Equatable, Sendable {
    static let schemaVersion = 5
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotPayloadV4
    let authorityCriterion: CompletedAuthorityCriterionSnapshotV1

    init(activity: CompletedActivitySnapshotPayloadV4,
         authorityCriterion: CompletedAuthorityCriterionSnapshotV1) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.authorityCriterion = authorityCriterion
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try activity.validate()
        try authorityCriterion.validate()
        guard authorityCriterion.workspaceID.rawValue.uuidString.lowercased()
                == activity.activity.activity.workspaceID.lowercased() else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, authorityCriterion
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotPayloadV4.self, forKey: .activity),
            authorityCriterion: values.decode(
                CompletedAuthorityCriterionSnapshotV1.self, forKey: .authorityCriterion
            )
        )
    }
}

struct CompletedActivitySnapshotV5: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 5
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV5
    let snapshotSHA256: String
    var id: String { "\(payload.activity.activity.activity.activity.workspaceID)|\(payload.activity.activity.activity.activity.snapshotID)" }

    private init(payload: CompletedActivitySnapshotPayloadV5, snapshotSHA256: String) throws {
        schemaVersion = Self.schemaVersion; self.payload = payload; self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV5) throws -> Self {
        let activity = payload.activity.activity.activity.activity
        guard activity.snapshotRevision == 1, activity.supersedesSnapshotID == nil,
              activity.supersededSnapshotSHA256 == nil else { throw SnapshotProjectionFailureV1.historyRewrite }
        return try Self(payload: payload, snapshotSHA256: KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV5.encodePayload(payload)
        ))
    }

    static func freezeAmendment(_ payload: CompletedActivitySnapshotPayloadV5,
                                superseding prior: Self) throws -> Self {
        let value = try Self(payload: payload, snapshotSHA256: KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV5.encodePayload(payload)
        ))
        let current = payload.activity.activity.activity.activity
        let previous = prior.payload.activity.activity.activity.activity
        let (next, overflow) = previous.snapshotRevision.addingReportingOverflow(1)
        guard !overflow, current.workspaceID == previous.workspaceID,
              current.snapshotRevision == next, current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID, current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision else { throw SnapshotProjectionFailureV1.historyRewrite }
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        guard snapshotSHA256 == KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV5.encodePayload(payload)
        ) else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV5.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV5 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder(); value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return value
    }
    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV5) throws -> Data {
        try payload.validate(); let data = try encoder().encode(payload)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }
    static func encode(_ snapshot: CompletedActivitySnapshotV5) throws -> Data {
        try snapshot.validate(); let data = try encoder().encode(snapshot)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }
    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV5 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(CompletedActivitySnapshotV5.self, from: data)
        try value.validate(); guard try encode(value) == data else { throw SnapshotProjectionFailureV1.digestMismatch }
        return value
    }
}

/// Additive C41 snapshot boundary.  The prior V1--V5 payloads remain byte
/// stable; this layer binds one exact functional-relationship history snapshot
/// to the already-frozen activity snapshot.  The relationship projection is a
/// read-only companion and later relationship events never rewrite this value.
struct CompletedActivitySnapshotPayloadV6: Codable, Equatable, Sendable {
    static let schemaVersion = 6
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotPayloadV5
    let functionalRelationships: CompletedFunctionalRelationshipSnapshotV1

    init(
        activity: CompletedActivitySnapshotPayloadV5,
        functionalRelationships: CompletedFunctionalRelationshipSnapshotV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.functionalRelationships = functionalRelationships
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try activity.validate()
        try functionalRelationships.validate()
        let workspace = activity.activity.activity.activity.activity.workspaceID
        guard functionalRelationships.workspaceID.rawValue.uuidString.lowercased() == workspace.lowercased() else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, functionalRelationships
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotPayloadV5.self, forKey: .activity),
            functionalRelationships: values.decode(
                CompletedFunctionalRelationshipSnapshotV1.self,
                forKey: .functionalRelationships
            )
        )
    }
}

struct CompletedActivitySnapshotV6: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 6
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV6
    let snapshotSHA256: String

    var id: String {
        "\(payload.activity.activity.activity.activity.activity.workspaceID)|\(payload.activity.activity.activity.activity.activity.snapshotID)"
    }

    private init(payload: CompletedActivitySnapshotPayloadV6, snapshotSHA256: String) throws {
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV6) throws -> Self {
        let activity = payload.activity.activity.activity.activity.activity
        guard activity.snapshotRevision == 1,
              activity.supersedesSnapshotID == nil,
              activity.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV6.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV6,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV6.encodePayload(payload)
            )
        )
        let current = payload.activity.activity.activity.activity.activity
        let previous = prior.payload.activity.activity.activity.activity.activity
        let (next, overflow) = previous.snapshotRevision.addingReportingOverflow(1)
        guard !overflow,
              current.workspaceID == previous.workspaceID,
              current.snapshotRevision == next,
              current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID,
              current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision,
              payload.functionalRelationships.capturedAt >= prior.payload.functionalRelationships.capturedAt else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        guard snapshotSHA256 == KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV6.encodePayload(payload)
        ) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV6.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV6 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV6) throws -> Data {
        try payload.validate()
        let data = try encoder().encode(payload)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV6) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(snapshot)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV6 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(CompletedActivitySnapshotV6.self, from: data)
        try value.validate()
        guard try encode(value) == data else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return value
    }
}

/// Additive C13 boundary. The V6 activity snapshot remains the immutable
/// source snapshot; this wrapper records the preview-first assurance facts
/// that were derived from that exact V6 digest. Existing V1--V6 bytes are not
/// rewritten when assurance policy is introduced.
struct CompletedActivitySnapshotPayloadV7: Codable, Equatable, Sendable {
    static let schemaVersion = 7
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotV6
    let assurance: ReportEvidenceAssuranceProjectionV1

    init(
        activity: CompletedActivitySnapshotV6,
        assurance: ReportEvidenceAssuranceProjectionV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.assurance = assurance
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try activity.validate()
        let base = activity.payload.activity.activity.activity.activity.activity
        guard let workspaceUUID = UUID(uuidString: base.workspaceID) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        try assurance.validate(
            expectedSnapshotSHA256: activity.snapshotSHA256,
            expectedAudience: ReportEvidenceAssuranceProjectionPolicyV1
                .evidenceAudience(for: base.profileBinding.audience)
        )
        guard assurance.preview.workspaceID == WorkspaceID(rawValue: workspaceUUID),
              assurance.preview.projectionVersion == base.profileBinding.projectionVersion else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, assurance
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotV6.self, forKey: .activity),
            assurance: values.decode(ReportEvidenceAssuranceProjectionV1.self, forKey: .assurance)
        )
    }
}

struct CompletedActivitySnapshotV7: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 7
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV7
    let snapshotSHA256: String

    var id: String {
        payload.activity.id
    }

    private init(payload: CompletedActivitySnapshotPayloadV7, snapshotSHA256: String) throws {
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV7) throws -> Self {
        let base = payload.activity.payload.activity.activity.activity.activity.activity
        guard base.snapshotRevision == 1,
              base.supersedesSnapshotID == nil,
              base.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV7.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV7,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV7.encodePayload(payload)
            )
        )
        let current = payload.activity.payload.activity.activity.activity.activity.activity
        let previous = prior.payload.activity.payload.activity.activity.activity.activity.activity
        let (next, overflow) = previous.snapshotRevision.addingReportingOverflow(1)
        guard !overflow,
              current.workspaceID == previous.workspaceID,
              current.snapshotRevision == next,
              current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.payload.activity.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID,
              current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision,
              payload.assurance.preview.createdAt >= prior.payload.assurance.preview.createdAt else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        guard snapshotSHA256 == KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV7.encodePayload(payload)
        ) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV7.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV7 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV7) throws -> Data {
        try payload.validate()
        let data = try encoder().encode(payload)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV7) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(snapshot)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV7 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(CompletedActivitySnapshotV7.self, from: data)
        try value.validate()
        guard try encode(value) == data else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return value
    }
}

// MARK: - C14 inspection review history

/// The C14 history binding is the single provenance tuple for review,
/// change-request, and corrective-action facts.  It intentionally carries
/// only immutable digests across the preceding C13/C38/C40/C41 boundaries;
/// the corresponding source values remain owned by those contracts.
struct CompletedInspectionReviewBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let completedSnapshotSHA256: String
    let c13AssuranceSHA256: String
    let c38AccountabilitySHA256: String
    let c40AuthorityCriterionSHA256: String
    let c41FunctionalRelationshipsSHA256: String
    let bindingSHA256: String

    var evidenceAssuranceSHA256: String { c13AssuranceSHA256 }
    var accountabilitySHA256: String { c38AccountabilitySHA256 }
    var authorityCriterionSHA256: String { c40AuthorityCriterionSHA256 }
    var functionalRelationshipsSHA256: String { c41FunctionalRelationshipsSHA256 }

    init(
        workspaceID: WorkspaceID,
        completedSnapshotSHA256: String,
        c13AssuranceSHA256: String,
        c38AccountabilitySHA256: String,
        c40AuthorityCriterionSHA256: String,
        c41FunctionalRelationshipsSHA256: String
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.completedSnapshotSHA256 = completedSnapshotSHA256
        self.c13AssuranceSHA256 = c13AssuranceSHA256
        self.c38AccountabilitySHA256 = c38AccountabilitySHA256
        self.c40AuthorityCriterionSHA256 = c40AuthorityCriterionSHA256
        self.c41FunctionalRelationshipsSHA256 = c41FunctionalRelationshipsSHA256
        bindingSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            completedSnapshotSHA256: completedSnapshotSHA256,
            c13AssuranceSHA256: c13AssuranceSHA256,
            c38AccountabilitySHA256: c38AccountabilitySHA256,
            c40AuthorityCriterionSHA256: c40AuthorityCriterionSHA256,
            c41FunctionalRelationshipsSHA256: c41FunctionalRelationshipsSHA256
        ))
        try validate()
    }

    func validate() throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != zero,
              [completedSnapshotSHA256, c13AssuranceSHA256,
               c38AccountabilitySHA256, c40AuthorityCriterionSHA256,
               c41FunctionalRelationshipsSHA256, bindingSHA256]
                .allSatisfy(KernelCanonicalHashV1.validSHA256),
              bindingSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(
                  schemaVersion: schemaVersion,
                  workspaceID: workspaceID,
                  completedSnapshotSHA256: completedSnapshotSHA256,
                  c13AssuranceSHA256: c13AssuranceSHA256,
                  c38AccountabilitySHA256: c38AccountabilitySHA256,
                  c40AuthorityCriterionSHA256: c40AuthorityCriterionSHA256,
                  c41FunctionalRelationshipsSHA256: c41FunctionalRelationshipsSHA256
              ))) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let completedSnapshotSHA256: String
        let c13AssuranceSHA256: String
        let c38AccountabilitySHA256: String
        let c40AuthorityCriterionSHA256: String
        let c41FunctionalRelationshipsSHA256: String
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, completedSnapshotSHA256
        case c13AssuranceSHA256, c38AccountabilitySHA256
        case c40AuthorityCriterionSHA256, c41FunctionalRelationshipsSHA256
        case bindingSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let value = try Self(
            workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
            completedSnapshotSHA256: values.decode(String.self, forKey: .completedSnapshotSHA256),
            c13AssuranceSHA256: values.decode(String.self, forKey: .c13AssuranceSHA256),
            c38AccountabilitySHA256: values.decode(String.self, forKey: .c38AccountabilitySHA256),
            c40AuthorityCriterionSHA256: values.decode(String.self, forKey: .c40AuthorityCriterionSHA256),
            c41FunctionalRelationshipsSHA256: values.decode(String.self, forKey: .c41FunctionalRelationshipsSHA256)
        )
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try values.decode(String.self, forKey: .bindingSHA256) == value.bindingSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = value
    }
}

/// A frozen C14 review/change/action history.  Review transitions and
/// dispositions, change-request revisions, and corrective-action revisions
/// are retained as their exact canonical facts.  No later projection is
/// allowed to mutate this value; amendments are represented by a new V8
/// snapshot whose predecessor remains readable.
struct CompletedInspectionReviewHistorySnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let sourceSnapshotSHA256: String
    let binding: CompletedInspectionReviewBindingV1
    let reviewTransitions: [InspectionReviewTransitionV1]
    let reviewDispositions: [ReviewDispositionV1]
    let changeRequests: [ChangeRequestV1]
    let correctiveActions: [CorrectiveActionEventV1]
    let snapshotSHA256: String

    var reviewHistory: [InspectionReviewTransitionV1] { reviewTransitions }
    var changeHistory: [ChangeRequestV1] { changeRequests }
    var actionHistory: [CorrectiveActionEventV1] { correctiveActions }

    init(
        workspaceID: WorkspaceID,
        sourceSnapshotSHA256: String,
        binding: CompletedInspectionReviewBindingV1,
        reviewHistory: [InspectionReviewTransitionV1],
        reviewDispositions: [ReviewDispositionV1] = [],
        changeHistory: [ChangeRequestV1],
        actionHistory: [CorrectiveActionEventV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        self.binding = binding
        reviewTransitions = reviewHistory.sorted(by: Self.transitionOrder)
        self.reviewDispositions = reviewDispositions.sorted(by: Self.dispositionOrder)
        changeRequests = changeHistory.sorted(by: Self.changeOrder)
        correctiveActions = actionHistory.sorted(by: Self.actionOrder)
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            binding: binding,
            reviewTransitions: reviewTransitions,
            reviewDispositions: self.reviewDispositions,
            changeRequests: changeRequests,
            correctiveActions: correctiveActions
        ))
        try validate()
    }

    init(
        workspaceID: WorkspaceID,
        sourceSnapshotSHA256: String,
        binding: CompletedInspectionReviewBindingV1,
        reviewTransitions: [InspectionReviewTransitionV1],
        dispositions: [ReviewDispositionV1] = [],
        changeRequests: [ChangeRequestV1],
        correctiveActions: [CorrectiveActionEventV1]
    ) throws {
        try self.init(
            workspaceID: workspaceID,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            binding: binding,
            reviewHistory: reviewTransitions,
            reviewDispositions: dispositions,
            changeHistory: changeRequests,
            actionHistory: correctiveActions
        )
    }

    func validate() throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != zero,
              KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              binding.workspaceID == workspaceID,
              binding.completedSnapshotSHA256 == sourceSnapshotSHA256,
              reviewTransitions.count <= InspectionReviewLimitsV1.maximumHistory,
              reviewDispositions.count <= InspectionReviewLimitsV1.maximumHistory,
              changeRequests.count <= InspectionReviewLimitsV1.maximumHistory,
              correctiveActions.count <= InspectionReviewLimitsV1.maximumHistory,
              reviewTransitions == reviewTransitions.sorted(by: Self.transitionOrder),
              reviewDispositions == reviewDispositions.sorted(by: Self.dispositionOrder),
              changeRequests == changeRequests.sorted(by: Self.changeOrder),
              correctiveActions == correctiveActions.sorted(by: Self.actionOrder),
              uniqueTransitions,
              uniqueDispositions,
              uniqueChanges,
              uniqueActions else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try binding.validate()
        try reviewTransitions.forEach { transition in
            try transition.validate()
            guard transition.workspaceID == workspaceID,
                  transition.subject.workspaceID == workspaceID,
                  transition.actor.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
            if transition.subject.kind == .completedActivitySnapshot {
                guard transition.subject.subjectSHA256 == sourceSnapshotSHA256 else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
            }
        }
        try reviewDispositions.forEach { disposition in
            try disposition.validate()
            guard disposition.workspaceID == workspaceID,
                  disposition.subject.workspaceID == workspaceID,
                  disposition.reviewer.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
        try changeRequests.forEach { request in
            try request.validate()
            guard request.workspaceID == workspaceID,
                  request.requester.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
            try validateBoundItem(request.item)
            if let resolution = request.resolution {
                guard resolution.resolver.workspaceID == workspaceID else {
                    throw SnapshotProjectionFailureV1.wrongWorkspace
                }
            }
        }
        try correctiveActions.forEach { action in
            try action.validate()
            guard action.workspaceID == workspaceID,
                  action.recorder.workspaceID == workspaceID,
                  (action.verifier?.workspaceID ?? workspaceID) == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
            try validateBoundItem(action.source)
        }

        try validateTransitionChains()
        try validateDispositionChains()
        try validateChangeChains()
        try validateActionChains()

        let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            binding: binding,
            reviewTransitions: reviewTransitions,
            reviewDispositions: reviewDispositions,
            changeRequests: changeRequests,
            correctiveActions: correctiveActions
        ))
        guard snapshotSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    /// Builds a history boundary only when all preceding C13/C38/C40/C41
    /// projections are present and their exact digests can be carried forward.
    static func freeze(
        activity: CompletedActivitySnapshotV7,
        reviewHistory: [InspectionReviewTransitionV1],
        reviewDispositions: [ReviewDispositionV1] = [],
        changeHistory: [ChangeRequestV1],
        actionHistory: [CorrectiveActionEventV1]
    ) throws -> Self {
        try activity.validate()
        let v6 = activity.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard let accountability = v3.accountability,
              let workspaceUUID = UUID(uuidString: base.workspaceID) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let assuranceData = try ReportEvidenceAssuranceCanonicalCodecV1.encode(activity.payload.assurance)
        let assuranceSHA256 = KernelCanonicalHashV1.sha256(assuranceData)
        let binding = try CompletedInspectionReviewBindingV1(
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            completedSnapshotSHA256: activity.snapshotSHA256,
            c13AssuranceSHA256: assuranceSHA256,
            c38AccountabilitySHA256: accountability.snapshotSHA256,
            c40AuthorityCriterionSHA256: v5.authorityCriterion.snapshotSHA256,
            c41FunctionalRelationshipsSHA256: v6.functionalRelationships.snapshotSHA256
        )
        return try Self(
            workspaceID: binding.workspaceID,
            sourceSnapshotSHA256: activity.snapshotSHA256,
            binding: binding,
            reviewHistory: reviewHistory,
            reviewDispositions: reviewDispositions,
            changeHistory: changeHistory,
            actionHistory: actionHistory
        )
    }

    func validateImmutableHistory(of prior: Self) throws {
        try validate()
        try prior.validate()
        guard workspaceID == prior.workspaceID,
              reviewTransitions == prior.reviewTransitions,
              reviewDispositions == prior.reviewDispositions,
              changeRequests == prior.changeRequests,
              correctiveActions == prior.correctiveActions else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }

    private var uniqueTransitions: Bool {
        let values = reviewTransitions.map { "\($0.reviewID.uuidString):\($0.revision)" }
        return Set(values).count == values.count
    }
    private var uniqueDispositions: Bool {
        let values = reviewDispositions.map { "\($0.dispositionID.uuidString):\($0.revision)" }
        return Set(values).count == values.count
    }
    private var uniqueChanges: Bool {
        let values = changeRequests.map { "\($0.requestID.uuidString):\($0.revision)" }
        return Set(values).count == values.count
    }
    private var uniqueActions: Bool {
        let values = correctiveActions.map { "\($0.actionID.uuidString):\($0.revision)" }
        return Set(values).count == values.count
    }

    private func validateBoundItem(_ item: ChangeRequestItemReferenceV1) throws {
        try item.validate()
        let bindingDigests: Set<String> = [
            sourceSnapshotSHA256,
            binding.c13AssuranceSHA256,
            binding.c38AccountabilitySHA256,
            binding.c40AuthorityCriterionSHA256,
            binding.c41FunctionalRelationshipsSHA256,
        ]
        switch item.kind {
        case .review, .finding:
            guard item.itemSHA256 == sourceSnapshotSHA256 || bindingDigests.contains(item.itemSHA256) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        case .evidence:
            guard item.itemSHA256 == binding.c13AssuranceSHA256 else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        case .criterion:
            guard item.itemSHA256 == binding.c40AuthorityCriterionSHA256 else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        case .functionalRelationship:
            guard item.itemSHA256 == binding.c41FunctionalRelationshipsSHA256 else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
    }

    private func validateTransitionChains() throws {
        for values in Dictionary(grouping: reviewTransitions, by: \.reviewID).values {
            let ordered = values.sorted(by: Self.transitionOrder)
            for (index, value) in ordered.enumerated() {
                if index == 0 {
                    guard value.revision == 1, value.predecessorTransitionID == nil else {
                        throw SnapshotProjectionFailureV1.historyRewrite
                    }
                } else {
                    try value.validateSuccessor(of: ordered[index - 1])
                }
            }
        }
    }

    private func validateDispositionChains() throws {
        for values in Dictionary(grouping: reviewDispositions, by: \.reviewID).values {
            let ordered = values.sorted(by: Self.dispositionOrder)
            for (index, value) in ordered.enumerated() {
                if index == 0 {
                    guard value.revision == 1, value.supersedesDispositionID == nil else {
                        throw SnapshotProjectionFailureV1.historyRewrite
                    }
                } else {
                    try value.validateSuccessor(of: ordered[index - 1])
                }
            }
        }
    }

    private func validateChangeChains() throws {
        for values in Dictionary(grouping: changeRequests, by: \.requestID).values {
            let ordered = values.sorted(by: Self.changeOrder)
            for (index, value) in ordered.enumerated() {
                if index == 0 {
                    guard value.revision == 1, value.supersedesRequestRevisionID == nil else {
                        throw SnapshotProjectionFailureV1.historyRewrite
                    }
                } else {
                    try value.validateSuccessor(of: ordered[index - 1])
                }
            }
        }
    }

    private func validateActionChains() throws {
        for values in Dictionary(grouping: correctiveActions, by: \.actionID).values {
            let ordered = values.sorted(by: Self.actionOrder)
            for (index, value) in ordered.enumerated() {
                if index == 0 {
                    guard value.revision == 1, value.predecessorEventID == nil else {
                        throw SnapshotProjectionFailureV1.historyRewrite
                    }
                } else {
                    let prior = ordered[index - 1]
                    let (next, overflow) = prior.revision.addingReportingOverflow(1)
                    guard !overflow,
                          value.revision == next,
                          value.predecessorEventID == prior.eventID,
                          value.workspaceID == prior.workspaceID,
                          value.source == prior.source,
                          value.recordedAt >= prior.recordedAt,
                          value.mutationID != prior.mutationID,
                          CorrectiveActionTransitionTableV1.permits(
                              from: prior.state, to: value.state
                          ) else {
                        throw SnapshotProjectionFailureV1.historyRewrite
                    }
                }
            }
        }
    }

    private static func transitionOrder(
        _ lhs: InspectionReviewTransitionV1,
        _ rhs: InspectionReviewTransitionV1
    ) -> Bool {
        (lhs.reviewID.uuidString, lhs.revision, lhs.transitionID.uuidString)
            < (rhs.reviewID.uuidString, rhs.revision, rhs.transitionID.uuidString)
    }
    private static func dispositionOrder(
        _ lhs: ReviewDispositionV1,
        _ rhs: ReviewDispositionV1
    ) -> Bool {
        (lhs.reviewID.uuidString, lhs.revision, lhs.dispositionID.uuidString)
            < (rhs.reviewID.uuidString, rhs.revision, rhs.dispositionID.uuidString)
    }
    private static func changeOrder(
        _ lhs: ChangeRequestV1,
        _ rhs: ChangeRequestV1
    ) -> Bool {
        (lhs.requestID.uuidString, lhs.revision, lhs.requestRevisionID.uuidString)
            < (rhs.requestID.uuidString, rhs.revision, rhs.requestRevisionID.uuidString)
    }
    private static func actionOrder(
        _ lhs: CorrectiveActionEventV1,
        _ rhs: CorrectiveActionEventV1
    ) -> Bool {
        (lhs.actionID.uuidString, lhs.revision, lhs.eventID.uuidString)
            < (rhs.actionID.uuidString, rhs.revision, rhs.eventID.uuidString)
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let sourceSnapshotSHA256: String
        let binding: CompletedInspectionReviewBindingV1
        let reviewTransitions: [InspectionReviewTransitionV1]
        let reviewDispositions: [ReviewDispositionV1]
        let changeRequests: [ChangeRequestV1]
        let correctiveActions: [CorrectiveActionEventV1]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, sourceSnapshotSHA256, binding
        case reviewTransitions, reviewDispositions, changeRequests
        case correctiveActions, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let value = try Self(
            workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
            sourceSnapshotSHA256: values.decode(String.self, forKey: .sourceSnapshotSHA256),
            binding: values.decode(CompletedInspectionReviewBindingV1.self, forKey: .binding),
            reviewTransitions: values.decode([InspectionReviewTransitionV1].self, forKey: .reviewTransitions),
            dispositions: values.decode([ReviewDispositionV1].self, forKey: .reviewDispositions),
            changeRequests: values.decode([ChangeRequestV1].self, forKey: .changeRequests),
            correctiveActions: values.decode([CorrectiveActionEventV1].self, forKey: .correctiveActions)
        )
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try values.decode(String.self, forKey: .snapshotSHA256) == value.snapshotSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = value
    }
}

typealias CompletedReviewChangeActionHistorySnapshotV1 = CompletedInspectionReviewHistorySnapshotV1

/// V8 is an additive completed-snapshot wrapper.  V7 remains the immutable
/// source of the C13 evidence assurance projection; the C14 history is a
/// sibling fact bound to V7's exact digest.
struct CompletedActivitySnapshotPayloadV8: Codable, Equatable, Sendable {
    static let schemaVersion = 8
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotV7
    let inspectionReviewHistory: CompletedInspectionReviewHistorySnapshotV1

    var reviewHistory: CompletedInspectionReviewHistorySnapshotV1 { inspectionReviewHistory }

    init(
        activity: CompletedActivitySnapshotV7,
        inspectionReviewHistory: CompletedInspectionReviewHistorySnapshotV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.inspectionReviewHistory = inspectionReviewHistory
        try validate()
    }

    init(
        activity: CompletedActivitySnapshotV7,
        reviewHistory: CompletedInspectionReviewHistorySnapshotV1
    ) throws {
        try self.init(activity: activity, inspectionReviewHistory: reviewHistory)
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try activity.validate()
        let v6 = activity.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        try inspectionReviewHistory.validate()
        guard inspectionReviewHistory.workspaceID.rawValue.uuidString.lowercased()
                == base.workspaceID.lowercased(),
              inspectionReviewHistory.sourceSnapshotSHA256 == activity.snapshotSHA256,
              inspectionReviewHistory.binding.c13AssuranceSHA256
                == KernelCanonicalHashV1.sha256(
                    try ReportEvidenceAssuranceCanonicalCodecV1.encode(activity.payload.assurance)
                ) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        guard inspectionReviewHistory.binding.c38AccountabilitySHA256
                == v3.accountability?.snapshotSHA256,
              inspectionReviewHistory.binding.c40AuthorityCriterionSHA256
                == v5.authorityCriterion.snapshotSHA256,
              inspectionReviewHistory.binding.c41FunctionalRelationshipsSHA256
                == v6.functionalRelationships.snapshotSHA256 else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, inspectionReviewHistory
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotV7.self, forKey: .activity),
            inspectionReviewHistory: values.decode(
                CompletedInspectionReviewHistorySnapshotV1.self,
                forKey: .inspectionReviewHistory
            )
        )
    }
}

struct CompletedActivitySnapshotV8: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 8
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV8
    let snapshotSHA256: String

    var id: String { payload.activity.id }

    private init(payload: CompletedActivitySnapshotPayloadV8, snapshotSHA256: String) throws {
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV8) throws -> Self {
        let v6 = payload.activity.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard base.snapshotRevision == 1,
              base.supersedesSnapshotID == nil,
              base.supersededSnapshotSHA256 == nil else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV8.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV8,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV8.encodePayload(payload)
            )
        )
        let currentV6 = payload.activity.payload.activity
        let currentV5 = currentV6.payload.activity
        let currentV4 = currentV5.activity
        let currentV3 = currentV4.activity
        let current = currentV3.activity.activity
        let previousV6 = prior.payload.activity.payload.activity
        let previousV5 = previousV6.payload.activity
        let previousV4 = previousV5.activity
        let previousV3 = previousV4.activity
        let previous = previousV3.activity.activity
        let (next, overflow) = previous.snapshotRevision.addingReportingOverflow(1)
        guard !overflow,
              current.workspaceID == previous.workspaceID,
              current.snapshotRevision == next,
              current.supersedesSnapshotID == previous.snapshotID,
              current.supersededSnapshotSHA256 == prior.payload.activity.snapshotSHA256,
              current.sourceActivityID == previous.sourceActivityID,
              current.reportID == previous.reportID,
              current.completedAt == previous.completedAt,
              current.sourceRevision > previous.sourceRevision else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        try payload.inspectionReviewHistory.validateImmutableHistory(
            of: prior.payload.inspectionReviewHistory
        )
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        guard snapshotSHA256 == KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV8.encodePayload(payload)
        ) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV8.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV8 {
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        value.dateEncodingStrategy = .millisecondsSince1970
        return value
    }

    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV8) throws -> Data {
        try payload.validate()
        let data = try encoder().encode(payload)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV8) throws -> Data {
        try snapshot.validate()
        let data = try encoder().encode(snapshot)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV8 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(CompletedActivitySnapshotV8.self, from: data)
        try value.validate()
        guard try encode(value) == data else { throw SnapshotProjectionFailureV1.digestMismatch }
        return value
    }
}

typealias CompletedReviewHistorySnapshotV1 = CompletedInspectionReviewHistorySnapshotV1

// MARK: - C15 replayable work-packet snapshot

/// The completed C15 snapshot keeps the complete packet event history in the
/// immutable snapshot boundary.  Reports consume the deliberately smaller
/// `ReportWorkPacketProjectionV1`; actor snapshots, result links, and evidence
/// references never cross that boundary into customer-facing output.
enum CompletedWorkPacketItemStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unclaimed = "UNCLAIMED"
    case claimed = "CLAIMED"
    case leased = "LEASED"
    case released = "RELEASED"
    case handedOff = "HANDED_OFF"
    case conflicted = "CONFLICTED"
    case expired = "EXPIRED"
}

struct CompletedWorkPacketItemSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let itemID: String
    let itemKind: WorkPacketItemKindV1
    let expectedRevision: UInt64
    let itemSHA256: String
    let state: CompletedWorkPacketItemStateV1
    let currentClaimID: UUID?
    let currentLeaseID: UUID?
    let latestReleaseID: UUID?
    let latestHandoffID: UUID?
    let preservedResultCount: Int
    let conflictKinds: [WorkPacketConflictKindV1]
    let itemSnapshotSHA256: String

    init(
        item: WorkPacketItemReferenceV1,
        projection: WorkPacketItemProjectionV1
    ) throws {
        guard item == projection.item else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let conflictKinds = projection.exceptions.map(\.kind).sorted {
            $0.rawValue < $1.rawValue
        }
        let state: CompletedWorkPacketItemStateV1
        if !conflictKinds.isEmpty {
            state = .conflicted
        } else if projection.latestHandoff != nil {
            state = .handedOff
        } else if let release = projection.latestRelease {
            state = release.reason == .leaseExpired ? .expired : .released
        } else if projection.currentLease != nil {
            state = .leased
        } else if projection.currentClaim != nil {
            state = .claimed
        } else {
            state = .unclaimed
        }
        let basis = Basis(
            schemaVersion: Self.schemaVersion,
            itemID: item.itemID,
            itemKind: item.itemKind,
            expectedRevision: item.expectedRevision,
            itemSHA256: item.itemSHA256,
            state: state,
            currentClaimID: projection.currentClaim?.claimID,
            currentLeaseID: projection.currentLease?.leaseID,
            latestReleaseID: projection.latestRelease?.releaseID,
            latestHandoffID: projection.latestHandoff?.handoffID,
            preservedResultCount: projection.preservedResults.count,
            conflictKinds: conflictKinds
        )
        schemaVersion = Self.schemaVersion
        itemID = item.itemID
        itemKind = item.itemKind
        expectedRevision = item.expectedRevision
        itemSHA256 = item.itemSHA256
        self.state = state
        currentClaimID = projection.currentClaim?.claimID
        currentLeaseID = projection.currentLease?.leaseID
        latestReleaseID = projection.latestRelease?.releaseID
        latestHandoffID = projection.latestHandoff?.handoffID
        preservedResultCount = projection.preservedResults.count
        self.conflictKinds = conflictKinds
        itemSnapshotSHA256 = KernelCanonicalHashV1.sha256(
            try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(basis)
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SnapshotProjectionValidationV1.validText(itemID),
              expectedRevision > 0,
              KernelCanonicalHashV1.validSHA256(itemSHA256),
              preservedResultCount >= 0,
              conflictKinds == conflictKinds.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(conflictKinds).count == conflictKinds.count,
              KernelCanonicalHashV1.validSHA256(itemSnapshotSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let expected = KernelCanonicalHashV1.sha256(
            try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(Basis(
                schemaVersion: schemaVersion,
                itemID: itemID,
                itemKind: itemKind,
                expectedRevision: expectedRevision,
                itemSHA256: itemSHA256,
                state: state,
                currentClaimID: currentClaimID,
                currentLeaseID: currentLeaseID,
                latestReleaseID: latestReleaseID,
                latestHandoffID: latestHandoffID,
                preservedResultCount: preservedResultCount,
                conflictKinds: conflictKinds
            ))
        )
        guard expected == itemSnapshotSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let itemID: String
        let itemKind: WorkPacketItemKindV1
        let expectedRevision: UInt64
        let itemSHA256: String
        let state: CompletedWorkPacketItemStateV1
        let currentClaimID: UUID?
        let currentLeaseID: UUID?
        let latestReleaseID: UUID?
        let latestHandoffID: UUID?
        let preservedResultCount: Int
        let conflictKinds: [WorkPacketConflictKindV1]
    }
}

enum CompletedWorkPacketSnapshotCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

struct CompletedWorkPacketSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let manifest: WorkPacketManifestV1
    let claims: [WorkItemClaimV1]
    let leases: [WorkLeaseV1]
    let releases: [WorkReleaseV1]
    let handoffs: [WorkHandoffV1]
    let items: [CompletedWorkPacketItemSnapshotV1]
    let sourceRevision: UInt64
    let createdAt: Date
    let snapshotSHA256: String

    init(
        manifest: WorkPacketManifestV1,
        claims: [WorkItemClaimV1],
        leases: [WorkLeaseV1],
        releases: [WorkReleaseV1],
        handoffs: [WorkHandoffV1],
        sourceRevision: UInt64 = 1,
        createdAt: Date
    ) throws {
        let orderedClaims = claims.sorted {
            ($0.claimSequence, $0.claimID.uuidString.lowercased())
                < ($1.claimSequence, $1.claimID.uuidString.lowercased())
        }
        let orderedLeases = leases.sorted {
            ($0.leaseSequence, $0.leaseID.uuidString.lowercased())
                < ($1.leaseSequence, $1.leaseID.uuidString.lowercased())
        }
        let orderedReleases = releases.sorted {
            ($0.releasedAt, $0.releaseID.uuidString.lowercased())
                < ($1.releasedAt, $1.releaseID.uuidString.lowercased())
        }
        let orderedHandoffs = handoffs.sorted {
            ($0.handedOffAt, $0.handoffID.uuidString.lowercased())
                < ($1.handedOffAt, $1.handoffID.uuidString.lowercased())
        }
        let projection = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: manifest.workspaceID,
            manifest: manifest,
            claims: orderedClaims,
            leases: orderedLeases,
            releases: orderedReleases,
            handoffs: orderedHandoffs,
            at: createdAt
        )
        guard sourceRevision > 0,
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let itemValues = try projection.items.map {
            try CompletedWorkPacketItemSnapshotV1(item: $0.item, projection: $0)
        }
        schemaVersion = Self.schemaVersion
        workspaceID = manifest.workspaceID
        self.manifest = manifest
        claims = orderedClaims
        leases = orderedLeases
        releases = orderedReleases
        handoffs = orderedHandoffs
        items = itemValues
        self.sourceRevision = sourceRevision
        self.createdAt = createdAt
        snapshotSHA256 = KernelCanonicalHashV1.sha256(
            try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(Basis(
                schemaVersion: Self.schemaVersion,
                workspaceID: manifest.workspaceID,
                manifest: manifest,
                claims: orderedClaims,
                leases: orderedLeases,
                releases: orderedReleases,
                handoffs: orderedHandoffs,
                items: itemValues,
                sourceRevision: sourceRevision,
                createdAt: createdAt
            ))
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID == manifest.workspaceID,
              sourceRevision > 0,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256),
              claims.count <= WorkPacketLimitsV1.maximumHistory,
              leases.count <= WorkPacketLimitsV1.maximumHistory,
              releases.count <= WorkPacketLimitsV1.maximumHistory,
              handoffs.count <= WorkPacketLimitsV1.maximumHistory,
              items.count == manifest.items.count,
              items == items.sorted(by: { $0.itemID < $1.itemID }),
              Set(items.map(\.itemID)).count == items.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try manifest.validate()
        let manifestReference = try WorkPacketManifestReferenceV1(manifest)
        let itemReferences = try manifest.items.map {
            try WorkPacketItemReferenceV1(manifest: manifest, item: $0)
        }
        let itemBelongs: (WorkPacketItemReferenceV1) -> Bool = { item in
            itemReferences.contains(item)
        }
        try claims.forEach { claim in
            try claim.validate()
            guard claim.workspaceID == workspaceID,
                  claim.manifest == manifestReference,
                  itemBelongs(claim.item) else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
        try leases.forEach { lease in
            try lease.validate()
            guard lease.workspaceID == workspaceID,
                  itemBelongs(lease.item),
                  claims.contains(where: {
                      $0.claimID == lease.claimID
                          && $0.item == lease.item
                          && $0.workspaceID == workspaceID
                  }) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        try releases.forEach { release in
            try release.validate()
            guard release.workspaceID == workspaceID,
                  itemBelongs(release.item),
                  claims.contains(where: {
                      $0.claimID == release.claimID
                          && $0.item == release.item
                          && $0.workspaceID == workspaceID
                  }),
                  leases.contains(where: {
                      $0.leaseID == release.leaseID
                          && $0.claimID == release.claimID
                          && $0.item == release.item
                          && $0.workspaceID == workspaceID
                  }) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        try handoffs.forEach { handoff in
            try handoff.validate()
            guard handoff.workspaceID == workspaceID,
                  itemBelongs(handoff.item),
                  releases.contains(where: {
                      $0.releaseID == handoff.releaseID
                          && $0.item == handoff.item
                          && $0.workspaceID == workspaceID
                  }) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        guard claims == claims.sorted(by: Self.claimOrder),
              leases == leases.sorted(by: Self.leaseOrder),
              releases == releases.sorted(by: Self.releaseOrder),
              handoffs == handoffs.sorted(by: Self.handoffOrder) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let projection = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            manifest: manifest,
            claims: claims,
            leases: leases,
            releases: releases,
            handoffs: handoffs,
            at: createdAt
        )
        let expectedItems = try projection.items.map {
            try CompletedWorkPacketItemSnapshotV1(item: $0.item, projection: $0)
        }
        guard expectedItems == items else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let expected = KernelCanonicalHashV1.sha256(
            try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(Basis(
                schemaVersion: schemaVersion,
                workspaceID: workspaceID,
                manifest: manifest,
                claims: claims,
                leases: leases,
                releases: releases,
                handoffs: handoffs,
                items: items,
                sourceRevision: sourceRevision,
                createdAt: createdAt
            ))
        )
        guard snapshotSHA256 == expected else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private static func claimOrder(
        _ lhs: WorkItemClaimV1,
        _ rhs: WorkItemClaimV1
    ) -> Bool {
        (lhs.claimSequence, lhs.claimID.uuidString.lowercased())
            < (rhs.claimSequence, rhs.claimID.uuidString.lowercased())
    }

    private static func leaseOrder(
        _ lhs: WorkLeaseV1,
        _ rhs: WorkLeaseV1
    ) -> Bool {
        (lhs.leaseSequence, lhs.leaseID.uuidString.lowercased())
            < (rhs.leaseSequence, rhs.leaseID.uuidString.lowercased())
    }

    private static func releaseOrder(
        _ lhs: WorkReleaseV1,
        _ rhs: WorkReleaseV1
    ) -> Bool {
        (lhs.releasedAt, lhs.releaseID.uuidString.lowercased())
            < (rhs.releasedAt, rhs.releaseID.uuidString.lowercased())
    }

    private static func handoffOrder(
        _ lhs: WorkHandoffV1,
        _ rhs: WorkHandoffV1
    ) -> Bool {
        (lhs.handedOffAt, lhs.handoffID.uuidString.lowercased())
            < (rhs.handedOffAt, rhs.handoffID.uuidString.lowercased())
    }

    /// Amendments may add immutable events but cannot rewrite an existing
    /// manifest/event/result link. This is the packet analogue of the V8
    /// completed-history supersession check.
    func validateImmutableHistory(of prior: Self) throws {
        try validate()
        try prior.validate()
        guard workspaceID == prior.workspaceID,
              manifest.manifestID == prior.manifest.manifestID,
              manifest.packetID == prior.manifest.packetID,
              manifest.manifestSHA256 == prior.manifest.manifestSHA256,
              sourceRevision > prior.sourceRevision,
              createdAt >= prior.createdAt else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
        guard Self.containsExact(prior.claims, in: claims, id: { $0.claimID }),
              Self.containsExact(prior.leases, in: leases, id: { $0.leaseID }),
              Self.containsExact(prior.releases, in: releases, id: { $0.releaseID }),
              Self.containsExact(prior.handoffs, in: handoffs, id: { $0.handoffID }) else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }

    private static func containsExact<Value: Equatable>(
        _ prior: [Value],
        in current: [Value],
        id: (Value) -> UUID
    ) -> Bool {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { (id($0), $0) })
        return prior.allSatisfy { currentByID[id($0)] == $0 }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let manifest: WorkPacketManifestV1
        let claims: [WorkItemClaimV1]
        let leases: [WorkLeaseV1]
        let releases: [WorkReleaseV1]
        let handoffs: [WorkHandoffV1]
        let items: [CompletedWorkPacketItemSnapshotV1]
        let sourceRevision: UInt64
        let createdAt: Date
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, manifest, claims, leases, releases
        case handoffs, items, sourceRevision, createdAt, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let manifest = try values.decode(WorkPacketManifestV1.self, forKey: .manifest)
        let decodedClaims = try values.decode([WorkItemClaimV1].self, forKey: .claims)
        let decodedLeases = try values.decode([WorkLeaseV1].self, forKey: .leases)
        let decodedReleases = try values.decode([WorkReleaseV1].self, forKey: .releases)
        let decodedHandoffs = try values.decode([WorkHandoffV1].self, forKey: .handoffs)
        let rebuilt = try Self(
            manifest: manifest,
            claims: decodedClaims,
            leases: decodedLeases,
            releases: decodedReleases,
            handoffs: decodedHandoffs,
            sourceRevision: values.decode(UInt64.self, forKey: .sourceRevision),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try values.decode(WorkspaceID.self, forKey: .workspaceID) == rebuilt.workspaceID,
              decodedClaims == rebuilt.claims,
              decodedLeases == rebuilt.leases,
              decodedReleases == rebuilt.releases,
              decodedHandoffs == rebuilt.handoffs,
              try values.decode([CompletedWorkPacketItemSnapshotV1].self, forKey: .items)
                    == rebuilt.items,
              try values.decode(String.self, forKey: .snapshotSHA256) == rebuilt.snapshotSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = rebuilt
    }
}

/// V9 is an additive wrapper. V8 and its C14 history remain byte-for-byte
/// immutable while the packet snapshot is bound to the same completed
/// workspace/packet identity.
struct CompletedActivitySnapshotPayloadV9: Codable, Equatable, Sendable {
    static let schemaVersion = 9
    let schemaVersion: Int
    let activity: CompletedActivitySnapshotV8
    let workPacket: CompletedWorkPacketSnapshotV1

    init(activity: CompletedActivitySnapshotV8, workPacket: CompletedWorkPacketSnapshotV1) throws {
        schemaVersion = Self.schemaVersion
        self.activity = activity
        self.workPacket = workPacket
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try activity.validate()
        try workPacket.validate()
        let v7 = activity.payload.activity
        let v6 = v7.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard workPacket.workspaceID.rawValue.uuidString.lowercased() == base.workspaceID.lowercased(),
              workPacket.manifest.packetID == base.packetID else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, activity, workPacket
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            activity: values.decode(CompletedActivitySnapshotV8.self, forKey: .activity),
            workPacket: values.decode(CompletedWorkPacketSnapshotV1.self, forKey: .workPacket)
        )
    }
}

struct CompletedActivitySnapshotV9: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 9
    let schemaVersion: Int
    let payload: CompletedActivitySnapshotPayloadV9
    let snapshotSHA256: String

    var id: String { payload.activity.id }

    private init(payload: CompletedActivitySnapshotPayloadV9, snapshotSHA256: String) throws {
        schemaVersion = Self.schemaVersion
        self.payload = payload
        self.snapshotSHA256 = snapshotSHA256
        try validate()
    }

    static func freezeOriginal(_ payload: CompletedActivitySnapshotPayloadV9) throws -> Self {
        try payload.activity.validate()
        return try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV9.encodePayload(payload)
            )
        )
    }

    static func freezeAmendment(
        _ payload: CompletedActivitySnapshotPayloadV9,
        superseding prior: Self
    ) throws -> Self {
        let value = try Self(
            payload: payload,
            snapshotSHA256: KernelCanonicalHashV1.sha256(
                try CompletedActivitySnapshotCanonicalCodecV9.encodePayload(payload)
            )
        )
        try payload.activity.validateSupersession(of: prior.payload.activity)
        try payload.workPacket.validateImmutableHistory(of: prior.payload.workPacket)
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try payload.validate()
        guard snapshotSHA256 == KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV9.encodePayload(payload)
        ) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, payload, snapshotSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            payload: values.decode(CompletedActivitySnapshotPayloadV9.self, forKey: .payload),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256)
        )
    }
}

enum CompletedActivitySnapshotCanonicalCodecV9 {
    static func encodePayload(_ payload: CompletedActivitySnapshotPayloadV9) throws -> Data {
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func encode(_ snapshot: CompletedActivitySnapshotV9) throws -> Data {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> CompletedActivitySnapshotV9 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        let value = try decoder.decode(CompletedActivitySnapshotV9.self, from: data)
        try value.validate()
        guard try encode(value) == data else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return value
    }
}

// MARK: - C19 measurement projection binding

extension CompletedActivitySnapshotV9 {
    /// Validates the read-only C19 projection against the completed activity's
    /// existing workspace/package identity. The snapshot schema and canonical
    /// bytes remain untouched; no measurement value is imported or rewritten.
    func c19ValidateMeasurementProjection(
        instruments: [InstrumentReferenceV1] = [],
        calibrations: [CalibrationStatusSnapshotV1] = [],
        captures: [MeasurementCaptureV1] = [],
        series: [MeasurementSeriesV1] = [],
        assessments: [MeasurementQualityAssessmentV1] = [],
        protocols: [MeasurementProtocolReleaseV1] = []
    ) throws {
        try validate()

        let v7 = payload.activity.payload.activity
        let v6 = v7.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard let workspaceUUID = UUID(uuidString: base.workspaceID) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        let workspaceID = WorkspaceID(rawValue: workspaceUUID)

        guard instruments.count <= MeasurementIntegrityLimitsV1.maximumUnitCount,
              calibrations.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              captures.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              series.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              assessments.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              protocols.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              Set(instruments.map(\.referenceID)).count == instruments.count,
              Set(calibrations.map(\.snapshotID)).count == calibrations.count,
              Set(captures.map(\.captureID)).count == captures.count,
              Set(series.map(\.snapshotID)).count == series.count,
              Set(assessments.map(\.assessmentID)).count == assessments.count,
              Set(protocols.map(\.releaseID)).count == protocols.count else {
            throw SnapshotProjectionFailureV1.duplicateIdentity
        }

        try instruments.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }
        for calibration in calibrations {
            try calibration.validate()
            guard calibration.workspaceID == workspaceID,
                  instruments.contains(where: { instrument in
                      instrument.referenceID == calibration.instrument.referenceID
                          && instrument.revision == calibration.instrument.revision
                          && instrument.referenceSHA256 == calibration.instrument.referenceSHA256
                  }) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        try protocols.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }

        for capture in captures {
            try capture.validate()
            guard capture.workspaceID == workspaceID,
                  capture.packageReleaseID == base.packageReleaseID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
            let instrument = capture.instrument.flatMap { reference in
                instruments.first {
                    $0.referenceID == reference.referenceID
                        && $0.revision == reference.revision
                        && $0.referenceSHA256 == reference.referenceSHA256
                }
            }
            let calibration = capture.calibration.flatMap { reference in
                calibrations.first {
                    $0.snapshotID == reference.snapshotID
                        && $0.revision == reference.revision
                        && $0.snapshotSHA256 == reference.snapshotSHA256
                }
            }
            try capture.validateClosure(instrument: instrument, calibration: calibration)
        }

        for value in series {
            guard let protocolRelease = protocols.first(where: {
                $0.releaseID == value.protocolReference.releaseID
            }) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
            try protocolRelease.c19ValidateSeries(value, captures: captures)
            guard value.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
        }

        for assessment in assessments {
            try assessment.validate()
            guard assessment.workspaceID == workspaceID else {
                throw SnapshotProjectionFailureV1.wrongWorkspace
            }
            switch assessment.subjectKind {
            case .capture:
                guard let capture = captures.first(where: { $0.captureID == assessment.subjectID }),
                      capture.revision == assessment.subjectRevision,
                      capture.captureSHA256 == assessment.subjectSHA256 else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
            case .series:
                let matches = series.filter {
                    ($0.snapshotID == assessment.subjectID || $0.seriesID == assessment.subjectID)
                        && $0.state == .finalized
                        && $0.revision == assessment.subjectRevision
                        && $0.seriesSHA256 == assessment.subjectSHA256
                }
                guard matches.count == 1 else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
            }
        }
    }
}

// MARK: - C20 audience-safe privacy-transform binding

enum CompletedPrivacyTransformProjectionPolicyV1 {
    static let projectionVersion = PrivacyTransformReportProjectionV1.projectionVersion
    static let derivativeOnly = true
    static let requiresApprovedReview = true
    static let requiresCurrentSource = true
    static let requiresExplicitRedactionDeclaration = true
    static let historicArtifactsImmutable = true
    static let correctionsAreAmendOnly = true
    static let excludesOriginalReferences = true
    static let excludesOriginalBytes = true
    static let excludesDerivativeBytes = true
}

extension CompletedActivitySnapshotV9 {
    /// Binds a C20 metadata projection to the immutable completed-snapshot
    /// workspace without importing content bytes or changing the snapshot.
    func c20ValidatePrivacyTransformProjection(
        _ projection: PrivacyTransformReportProjectionV1,
        expectedWorkspaceID: WorkspaceID? = nil
    ) throws -> PrivacyTransformReportProjectionV1 {
        try validate()
        try projection.validate()

        let v7 = payload.activity.payload.activity
        let v6 = v7.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard let rawWorkspaceID = UUID(uuidString: base.workspaceID) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        let snapshotWorkspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        guard projection.workspaceID == snapshotWorkspaceID,
              expectedWorkspaceID.map({ $0 == projection.workspaceID }) ?? true,
              projection.isAudienceSafe,
              projection.originalReferenceExcluded,
              projection.derivativeOnly else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        return projection
    }

    static func c20ValidatePrivacyTransformProjection(
        _ projection: PrivacyTransformReportProjectionV1,
        expectedWorkspaceID: WorkspaceID? = nil
    ) throws -> PrivacyTransformReportProjectionV1 {
        try projection.validate()
        guard expectedWorkspaceID.map({ $0 == projection.workspaceID }) ?? true else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        return projection
    }
}

// MARK: - C21 client capability and package lifecycle binding

extension CompletedActivitySnapshotV9 {
    /// Binds the metadata-only C21 projection to the completed snapshot's
    /// workspace and package release. The projection does not alter the
    /// completed bytes; withdrawal may block new work while finalized history
    /// remains viewable/exportable through its recorded decision.
    func c21ValidateClientCapabilityProjection(
        _ projection: ClientCapabilityReportProjectionV1,
        expectedWorkspaceID: WorkspaceID? = nil
    ) throws -> ClientCapabilityReportProjectionV1 {
        try validate()
        try projection.validate()

        let v7 = payload.activity.payload.activity
        let v6 = v7.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard let rawWorkspaceID = UUID(uuidString: base.workspaceID) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        let snapshotWorkspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        guard projection.workspaceID == snapshotWorkspaceID,
              expectedWorkspaceID.map({ $0 == projection.workspaceID }) ?? true,
              projection.packageReleaseID == base.packageReleaseID else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        return projection
    }

    static func c21ValidateClientCapabilityProjection(
        _ projection: ClientCapabilityReportProjectionV1,
        expectedWorkspaceID: WorkspaceID? = nil
    ) throws -> ClientCapabilityReportProjectionV1 {
        try projection.validate()
        guard expectedWorkspaceID.map({ $0 == projection.workspaceID }) ?? true else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        return projection
    }
}

// MARK: - C23 immutable work-session reference binding

extension CompletedWorkPacketSnapshotV1 {
    /// Rebuilds a completed packet's reference projection from the exact
    /// immutable packet snapshot. A finalized subject can be read/exported,
    /// but no later release may silently replace its binding.
    func c23FieldReferenceProjection(
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1]
    ) throws -> WorkPacketFieldReferenceProjectionV1 {
        try validate()
        let projection = try WorkPacketReferenceProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            manifest: manifest,
            claims: claims,
            leases: leases,
            releases: releases,
            handoffs: handoffs,
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness,
            subjectState: .finalized,
            at: createdAt
        )
        try projection.validate()
        return projection
    }

    func c23ValidateFieldReferenceProjection(
        _ projection: WorkPacketFieldReferenceProjectionV1,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1]
    ) throws -> WorkPacketFieldReferenceProjectionV1 {
        let expected = try c23FieldReferenceProjection(
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness
        )
        guard expected == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return projection
    }
}

extension CompletedActivitySnapshotV9 {
    /// Completed-activity reports may carry the metadata-only C23 projection
    /// only after its workspace is re-derived from the immutable snapshot.
    /// No subject identity or reference bytes are copied into the snapshot.
    func c23ValidateFieldReferenceProjection(
        _ projection: WorkSessionFieldReferenceProjectionV1,
        expectedWorkspaceID: WorkspaceID? = nil
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        try validate()
        let v7 = payload.activity.payload.activity
        let v6 = v7.payload.activity
        let v5 = v6.payload.activity
        let v4 = v5.activity
        let v3 = v4.activity
        let base = v3.activity.activity
        guard let rawWorkspaceID = UUID(uuidString: base.workspaceID) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        let snapshotWorkspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        guard projection.workspaceID == snapshotWorkspaceID,
              projection.subjectState == .finalized,
              expectedWorkspaceID.map({ $0 == projection.workspaceID }) ?? true else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }
        try projection.validate(expectedWorkspaceID: snapshotWorkspaceID)
        return projection
    }

    static func c23ValidateFieldReferenceProjection(
        _ projection: WorkSessionFieldReferenceProjectionV1,
        expectedWorkspaceID: WorkspaceID? = nil
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        try projection.validate(expectedWorkspaceID: expectedWorkspaceID)
        guard projection.subjectState == .finalized else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        return projection
    }
}
