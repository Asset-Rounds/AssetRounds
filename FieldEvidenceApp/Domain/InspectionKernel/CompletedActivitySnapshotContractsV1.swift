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
