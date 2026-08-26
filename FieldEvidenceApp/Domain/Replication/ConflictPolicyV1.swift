import Foundation

enum ConflictRuleV1: String, Codable, CaseIterable, Sendable {
    case immutableVersion = "IMMUTABLE_VERSION"
    case stableIDAppendUnion = "STABLE_ID_APPEND_UNION"
    case exactRevisionManual = "EXACT_REVISION_MANUAL"
    case deleteWins = "DELETE_WINS"
    case derivedRebuild = "DERIVED_REBUILD"
    case localOnly = "LOCAL_ONLY"
}

struct ConflictPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let policyID: String
    let policyVersion: Int
    let rule: ConflictRuleV1

    init(policyID: String, policyVersion: Int = 1, rule: ConflictRuleV1) throws {
        self.schemaVersion = Self.schemaVersion
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.rule = rule
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              ReplicationContractValidationV1.validToken(policyID),
              policyVersion > 0 else {
            throw ConflictPolicyFailureV1.invalidPolicy
        }
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw ConflictPolicyFailureV1.invalidPolicy
        }
        return value
    }
}

struct ConflictCompetitorV1: Codable, Equatable, Hashable, Sendable {
    static let maximumCount = 64

    let mutationID: MutationIDV1
    let canonicalInputSHA256: String

    init(mutationID: MutationIDV1, canonicalInputSHA256: String) throws {
        guard ReplicationContractValidationV1.isSHA256(canonicalInputSHA256) else {
            throw ConflictPolicyFailureV1.invalidDigest
        }
        self.mutationID = mutationID
        self.canonicalInputSHA256 = canonicalInputSHA256
    }

    fileprivate var canonicalKey: String {
        mutationID.rawValue.uuidString.lowercased() + ":" + canonicalInputSHA256
    }
}

enum ConflictSubjectIdentityV1: Equatable, Hashable, Sendable {
    case workspace(WorkspaceID)
    case entity(workspaceID: WorkspaceID, entity: WorkspaceEntityIdentityV1)

    fileprivate var workspaceID: WorkspaceID {
        switch self {
        case .workspace(let workspaceID), .entity(let workspaceID, _): return workspaceID
        }
    }

    fileprivate func validate() throws {
        switch self {
        case .workspace(let workspaceID):
            guard workspaceID.rawValue != ConflictUUIDV1.zero else { throw ConflictPolicyFailureV1.invalidSubject }
        case .entity(let workspaceID, let entity):
            guard workspaceID.rawValue != ConflictUUIDV1.zero, entity.id != ConflictUUIDV1.zero else {
                throw ConflictPolicyFailureV1.invalidSubject
            }
        }
    }
}

extension ConflictSubjectIdentityV1: Codable {
    private enum CodingKeys: String, CodingKey { case kind, workspaceID, entity }
    private enum Kind: String, Codable { case workspace = "WORKSPACE"; case entity = "ENTITY" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .workspace:
            self = .workspace(try container.decode(WorkspaceID.self, forKey: .workspaceID))
        case .entity:
            self = .entity(
                workspaceID: try container.decode(WorkspaceID.self, forKey: .workspaceID),
                entity: try container.decode(WorkspaceEntityIdentityV1.self, forKey: .entity)
            )
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .workspace(let workspaceID):
            try container.encode(Kind.workspace, forKey: .kind)
            try container.encode(workspaceID, forKey: .workspaceID)
        case .entity(let workspaceID, let entity):
            try container.encode(Kind.entity, forKey: .kind)
            try container.encode(workspaceID, forKey: .workspaceID)
            try container.encode(entity, forKey: .entity)
        }
    }
}

struct ConflictIdentityV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let digestSHA256: String

    private init(schemaVersion: Int, digestSHA256: String) {
        self.schemaVersion = schemaVersion
        self.digestSHA256 = digestSHA256
    }

    static func derive(
        subject: ConflictSubjectIdentityV1,
        policy: ConflictPolicyV1,
        competitors: [ConflictCompetitorV1]
    ) throws -> Self {
        try subject.validate()
        try policy.validate()
        let normalized = try ConflictNormalizationV1.competitors(competitors)
        let payload = ConflictIdentityPayloadV1(
            schemaVersion: schemaVersion,
            subject: subject,
            policyID: policy.policyID,
            policyVersion: policy.policyVersion,
            policySHA256: try policy.canonicalSHA256(),
            competitors: normalized
        )
        return Self(
            schemaVersion: schemaVersion,
            digestSHA256: try WorkspaceMutationCanonicalV1.sha256(payload)
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              ReplicationContractValidationV1.isSHA256(digestSHA256) else {
            throw ConflictPolicyFailureV1.invalidIdentity
        }
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw ConflictPolicyFailureV1.invalidIdentity
        }
        return value
    }
}

private struct ConflictIdentityPayloadV1: Codable {
    let schemaVersion: Int
    let subject: ConflictSubjectIdentityV1
    let policyID: String
    let policyVersion: Int
    let policySHA256: String
    let competitors: [ConflictCompetitorV1]
}

enum ConflictDispositionV1: String, Codable, CaseIterable, Sendable {
    case immutableUnion = "IMMUTABLE_UNION"
    case stableIDAppendUnion = "STABLE_ID_APPEND_UNION"
    case manualResolutionRequired = "MANUAL_RESOLUTION_REQUIRED"
    case deleteWins = "DELETE_WINS"
    case rebuildDerived = "REBUILD_DERIVED"
    case retainLocalOnly = "RETAIN_LOCAL_ONLY"
}

struct ConflictCausalFrontierV1: Codable, Equatable, Sendable {
    static let maximumObservedInputCount = 64

    let baseRevision: UInt64
    let baseSemanticSHA256: String?
    let observedInputs: [ConflictCompetitorV1]

    init(
        baseRevision: UInt64,
        baseSemanticSHA256: String?,
        observedInputs: [ConflictCompetitorV1]
    ) throws {
        if let baseSemanticSHA256,
           !ReplicationContractValidationV1.isSHA256(baseSemanticSHA256) {
            throw ConflictPolicyFailureV1.invalidDigest
        }
        self.baseRevision = baseRevision
        self.baseSemanticSHA256 = baseSemanticSHA256
        self.observedInputs = try ConflictNormalizationV1.competitors(
            observedInputs,
            allowEmpty: true
        )
    }

    func validate() throws {
        if let baseSemanticSHA256,
           !ReplicationContractValidationV1.isSHA256(baseSemanticSHA256) {
            throw ConflictPolicyFailureV1.invalidDigest
        }
        guard observedInputs == (try ConflictNormalizationV1.competitors(
            observedInputs,
            allowEmpty: true
        )) else {
            throw ConflictPolicyFailureV1.noncanonicalCompetitors
        }
    }
}

enum ConflictResolutionReadinessV1: Equatable, Sendable {
    case ready
    case deferred(missingInputs: [ConflictCompetitorV1])
    case successorRequired(
        identity: ConflictIdentityV1,
        unexpectedInputs: [ConflictCompetitorV1]
    )
}

struct ConflictResolutionBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let conflictIdentity: ConflictIdentityV1
    let subject: ConflictSubjectIdentityV1
    let policy: ConflictPolicyV1
    let competitors: [ConflictCompetitorV1]
    let causalFrontier: ConflictCausalFrontierV1
    let disposition: ConflictDispositionV1

    init(
        subject: ConflictSubjectIdentityV1,
        policy: ConflictPolicyV1,
        competitors: [ConflictCompetitorV1],
        causalFrontier: ConflictCausalFrontierV1,
        disposition: ConflictDispositionV1
    ) throws {
        let normalized = try ConflictNormalizationV1.competitors(competitors)
        self.schemaVersion = Self.schemaVersion
        self.conflictIdentity = try ConflictIdentityV1.derive(
            subject: subject,
            policy: policy,
            competitors: normalized
        )
        self.subject = subject
        self.policy = policy
        self.competitors = normalized
        self.causalFrontier = causalFrontier
        self.disposition = disposition
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ConflictPolicyFailureV1.invalidBasis
        }
        try subject.validate()
        try policy.validate()
        try conflictIdentity.validate()
        try causalFrontier.validate()
        guard competitors == (try ConflictNormalizationV1.competitors(competitors)),
              conflictIdentity == (try ConflictIdentityV1.derive(
                subject: subject,
                policy: policy,
                competitors: competitors
              )),
              Set(causalFrontier.observedInputs).isSubset(of: Set(competitors)) else {
            throw ConflictPolicyFailureV1.invalidBasis
        }
        let expectedDisposition: ConflictDispositionV1
        switch policy.rule {
        case .immutableVersion: expectedDisposition = .immutableUnion
        case .stableIDAppendUnion: expectedDisposition = .stableIDAppendUnion
        case .exactRevisionManual: expectedDisposition = .manualResolutionRequired
        case .deleteWins: expectedDisposition = .deleteWins
        case .derivedRebuild: expectedDisposition = .rebuildDerived
        case .localOnly: expectedDisposition = .retainLocalOnly
        }
        guard disposition == expectedDisposition else {
            throw ConflictPolicyFailureV1.invalidDisposition
        }
    }

    func readiness(availableInputs: [ConflictCompetitorV1]) throws -> ConflictResolutionReadinessV1 {
        try validate()
        let normalizedAvailable = try ConflictNormalizationV1.competitors(
            availableInputs,
            allowEmpty: true
        )
        let frozen = Set(competitors)
        let unexpected = normalizedAvailable.filter { !frozen.contains($0) }
        if !unexpected.isEmpty {
            return .successorRequired(
                identity: try ConflictIdentityV1.derive(
                    subject: subject,
                    policy: policy,
                    competitors: competitors + unexpected
                ),
                unexpectedInputs: unexpected
            )
        }
        let available = Set(normalizedAvailable)
        let missing = competitors.filter { !available.contains($0) }
        return missing.isEmpty ? .ready : .deferred(missingInputs: missing)
    }

    func successor(adding competitor: ConflictCompetitorV1) throws -> ConflictIdentityV1 {
        try validate()
        guard !competitors.contains(competitor) else { return conflictIdentity }
        return try ConflictIdentityV1.derive(
            subject: subject,
            policy: policy,
            competitors: competitors + [competitor]
        )
    }

    func canonicalData() throws -> Data {
        try validate()
        return try WorkspaceMutationCanonicalV1.data(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else {
            throw ConflictPolicyFailureV1.invalidBasis
        }
        return value
    }
}

enum ConflictPolicyFailureV1: Error, Equatable {
    case invalidPolicy
    case invalidDigest
    case invalidSubject
    case invalidIdentity
    case invalidBasis
    case invalidDisposition
    case emptyCompetitors
    case tooManyCompetitors
    case duplicateMutationID
    case noncanonicalCompetitors
}

private enum ConflictNormalizationV1 {
    static func competitors(
        _ values: [ConflictCompetitorV1],
        allowEmpty: Bool = false
    ) throws -> [ConflictCompetitorV1] {
        guard allowEmpty || !values.isEmpty else {
            throw ConflictPolicyFailureV1.emptyCompetitors
        }
        guard values.count <= ConflictCompetitorV1.maximumCount else {
            throw ConflictPolicyFailureV1.tooManyCompetitors
        }
        guard values.allSatisfy({ ReplicationContractValidationV1.isSHA256($0.canonicalInputSHA256) }) else {
            throw ConflictPolicyFailureV1.invalidDigest
        }
        let sorted = values.sorted { $0.canonicalKey < $1.canonicalKey }
        guard Set(sorted.map(\.mutationID)).count == sorted.count else {
            throw ConflictPolicyFailureV1.duplicateMutationID
        }
        return sorted
    }
}

private enum ConflictUUIDV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
