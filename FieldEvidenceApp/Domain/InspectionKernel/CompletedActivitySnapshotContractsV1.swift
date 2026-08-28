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
