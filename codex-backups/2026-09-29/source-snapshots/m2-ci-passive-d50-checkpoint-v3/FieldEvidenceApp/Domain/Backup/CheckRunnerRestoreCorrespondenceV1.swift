import Foundation

enum CheckRunnerRestoreCorrespondenceFailureV1: Error, Equatable {
    case invalidIdentity
    case invalidMode
    case unsupportedSchema
    case duplicateIdentity
    case identityMismatch
    case noncanonicalPairs
    case digestMismatch
    case declaredCoverageMismatch
    case missingIdentity
}

/// Canonical records and Round identities remain distinct from the operational
/// draft identities that the existing restore authority remaps for a fork.
enum CheckRunnerRestoreIdentityKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case roundSession, roundItem, roundLaunchPlan
    case site, asset, issue, parentRecord, workflowRecord, evidenceFile
    case parentDraft, childDraft, stage, draftCommitPlan, saga, reservation
    case commitReceipt, discardReceipt, scratchLease, processingJob
    case planMutation, checkpointMutation, stageMutation, sagaMutation
    case reservationMutation, commitTargetMutation, commitReceiptMutation
    case discardReceiptMutation, beginRecordMutation, beginTimeZoneMutation

    var operationalNamespace: String? {
        switch self {
        case .roundSession, .roundItem, .roundLaunchPlan,
             .site, .asset, .issue, .parentRecord, .workflowRecord, .evidenceFile:
            return nil
        case .parentDraft, .childDraft: return "draft"
        case .stage: return "stage"
        case .draftCommitPlan: return "plan"
        case .saga: return "saga"
        case .reservation: return "reservation"
        case .commitReceipt, .discardReceipt: return "receipt"
        case .scratchLease: return "scratchLease"
        case .processingJob: return "processingJob"
        case .planMutation: return "mutation.plan"
        case .checkpointMutation: return "mutation.checkpoint"
        case .stageMutation: return "mutation.stage"
        case .sagaMutation: return "mutation.saga"
        case .reservationMutation: return "mutation.reservation"
        case .commitTargetMutation: return "mutation.target"
        case .commitReceiptMutation: return "mutation.commitReceipt"
        case .discardReceiptMutation: return "mutation.discardReceipt"
        case .beginRecordMutation: return "mutation.beginRecord"
        case .beginTimeZoneMutation: return "mutation.beginTimeZone"
        }
    }
}

struct CheckRunnerRestoreIdentitySourceV1: Codable, Hashable, Sendable {
    let kind: CheckRunnerRestoreIdentityKindV1
    let sourceID: UUID

    init(kind: CheckRunnerRestoreIdentityKindV1, sourceID: UUID) throws {
        self.kind = kind
        self.sourceID = sourceID
        try validate()
    }

    func validate() throws {
        try CheckRunnerRestoreIdentityRulesV1.validateID(sourceID)
    }

    private enum CodingKeys: String, CodingKey { case kind, sourceID }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: ["kind", "sourceID"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: c.decode(CheckRunnerRestoreIdentityKindV1.self, forKey: .kind),
            sourceID: c.decode(UUID.self, forKey: .sourceID)
        )
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(sourceID, forKey: .sourceID)
    }
}

struct CheckRunnerRestoreIdentityPairV1: Codable, Hashable, Sendable {
    let kind: CheckRunnerRestoreIdentityKindV1
    let sourceID: UUID
    let destinationID: UUID

    init(kind: CheckRunnerRestoreIdentityKindV1, sourceID: UUID, destinationID: UUID) throws {
        self.kind = kind
        self.sourceID = sourceID
        self.destinationID = destinationID
        try validate()
    }

    func validate() throws {
        try CheckRunnerRestoreIdentityRulesV1.validateID(sourceID)
        try CheckRunnerRestoreIdentityRulesV1.validateID(destinationID)
    }

    private enum CodingKeys: String, CodingKey { case kind, sourceID, destinationID }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: ["kind", "sourceID", "destinationID"]
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: c.decode(CheckRunnerRestoreIdentityKindV1.self, forKey: .kind),
            sourceID: c.decode(UUID.self, forKey: .sourceID),
            destinationID: c.decode(UUID.self, forKey: .destinationID)
        )
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(sourceID, forKey: .sourceID)
        try c.encode(destinationID, forKey: .destinationID)
    }
}

enum CheckRunnerRestoreModeV1: String, Codable, Equatable, Sendable {
    case sameWorkspace, crossWorkspaceReplace, fork

    fileprivate var identityMode: BackupRestoreMode {
        switch self {
        case .sameWorkspace, .crossWorkspaceReplace: return .replaceExisting
        case .fork: return .fork
        }
    }
}

/// A pure, explicitly declared identity map. This proves the supplied pairs and
/// their digest, not completeness against a decoded parent/child draft graph.
/// Clone deliberately has no map; active generation and writer IDs never enter it.
struct CheckRunnerRestoreIdentityMapV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let schemaVersion: Int
    let mode: CheckRunnerRestoreModeV1
    let sourceWorkspaceID: UUID
    let destinationWorkspaceID: UUID
    let pairs: [CheckRunnerRestoreIdentityPairV1]
    let mapSHA256: String

    static func make(
        identity: RestoreIdentityV1, sources: [CheckRunnerRestoreIdentitySourceV1]
    ) throws -> Self? {
        try CheckRunnerRestoreIdentityRulesV1.validateSources(sources)
        guard let sourceWorkspaceID = identity.source.workspaceID else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.invalidIdentity
        }
        let destinationWorkspaceID = identity.targetPointer.workspaceID
        try CheckRunnerRestoreIdentityRulesV1.validateID(sourceWorkspaceID)
        try CheckRunnerRestoreIdentityRulesV1.validateID(destinationWorkspaceID)
        let mode: CheckRunnerRestoreModeV1
        switch identity.mode {
        case .clone:
            guard sourceWorkspaceID != destinationWorkspaceID else {
                throw CheckRunnerRestoreCorrespondenceFailureV1.invalidMode
            }
            return nil
        case .emptyInstall:
            guard sourceWorkspaceID == destinationWorkspaceID else {
                throw CheckRunnerRestoreCorrespondenceFailureV1.invalidMode
            }
            mode = .sameWorkspace
        case .replaceExisting:
            mode = sourceWorkspaceID == destinationWorkspaceID ? .sameWorkspace : .crossWorkspaceReplace
        case .fork:
            mode = .fork
        }
        let pairs = try sources.map { source -> CheckRunnerRestoreIdentityPairV1 in
            let destinationID: UUID?
            if let namespace = source.kind.operationalNamespace {
                destinationID = identity.destinationFieldDraftID(for: source.sourceID, namespace: namespace)
            } else {
                destinationID = identity.destinationRecordID(for: source.sourceID)
            }
            guard let destinationID else {
                throw CheckRunnerRestoreCorrespondenceFailureV1.identityMismatch
            }
            return try .init(kind: source.kind, sourceID: source.sourceID, destinationID: destinationID)
        }
        return try Self(
            mode: mode, sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID, pairs: pairs
        )
    }

    init(
        mode: CheckRunnerRestoreModeV1, sourceWorkspaceID: UUID,
        destinationWorkspaceID: UUID, pairs: [CheckRunnerRestoreIdentityPairV1]
    ) throws {
        schemaVersion = 1
        self.mode = mode
        self.sourceWorkspaceID = sourceWorkspaceID
        self.destinationWorkspaceID = destinationWorkspaceID
        self.pairs = pairs.sorted(by: Self.precedes)
        try Self.validateShape(
            mode: mode, sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID, pairs: self.pairs
        )
        mapSHA256 = try FieldDraftCanonicalCodecV1.sha256(Body(
            schemaVersion: schemaVersion, mode: mode, sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID, pairs: self.pairs
        ))
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw CheckRunnerRestoreCorrespondenceFailureV1.unsupportedSchema }
        try Self.validateShape(
            mode: mode, sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID, pairs: pairs
        )
        guard mapSHA256 == (try FieldDraftCanonicalCodecV1.sha256(body)) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.digestMismatch
        }
    }

    /// The caller must obtain this exact set from its authenticated source.
    /// This finite comparison cannot infer omitted nodes in a future codec graph.
    func validate(requiredSources: [CheckRunnerRestoreIdentitySourceV1]) throws {
        try validate()
        try CheckRunnerRestoreIdentityRulesV1.validateSources(requiredSources)
        let actual = try Set(pairs.map {
            try CheckRunnerRestoreIdentitySourceV1(kind: $0.kind, sourceID: $0.sourceID)
        })
        guard actual == Set(requiredSources) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.declaredCoverageMismatch
        }
    }

    func destinationID(for sourceID: UUID, kind: CheckRunnerRestoreIdentityKindV1) throws -> UUID {
        try CheckRunnerRestoreIdentityRulesV1.validateID(sourceID)
        guard let pair = pairs.first(where: { $0.kind == kind && $0.sourceID == sourceID }) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.missingIdentity
        }
        return pair.destinationID
    }

    func sourceID(for destinationID: UUID, kind: CheckRunnerRestoreIdentityKindV1) throws -> UUID {
        try CheckRunnerRestoreIdentityRulesV1.validateID(destinationID)
        guard let pair = pairs.first(where: { $0.kind == kind && $0.destinationID == destinationID }) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.missingIdentity
        }
        return pair.sourceID
    }

    private struct Body: Encodable {
        let schemaVersion: Int
        let mode: CheckRunnerRestoreModeV1
        let sourceWorkspaceID: UUID
        let destinationWorkspaceID: UUID
        let pairs: [CheckRunnerRestoreIdentityPairV1]
    }

    private var body: Body {
        Body(schemaVersion: schemaVersion, mode: mode, sourceWorkspaceID: sourceWorkspaceID,
             destinationWorkspaceID: destinationWorkspaceID, pairs: pairs)
    }

    private static func precedes(
        _ lhs: CheckRunnerRestoreIdentityPairV1, _ rhs: CheckRunnerRestoreIdentityPairV1
    ) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID.uuidString.lowercased() < rhs.sourceID.uuidString.lowercased()
        }
        return lhs.destinationID.uuidString.lowercased() < rhs.destinationID.uuidString.lowercased()
    }

    private static func validateShape(
        mode: CheckRunnerRestoreModeV1, sourceWorkspaceID: UUID,
        destinationWorkspaceID: UUID, pairs: [CheckRunnerRestoreIdentityPairV1]
    ) throws {
        try CheckRunnerRestoreIdentityRulesV1.validateID(sourceWorkspaceID)
        try CheckRunnerRestoreIdentityRulesV1.validateID(destinationWorkspaceID)
        guard (mode == .sameWorkspace) == (sourceWorkspaceID == destinationWorkspaceID) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.invalidMode
        }
        guard pairs == pairs.sorted(by: precedes) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.noncanonicalPairs
        }
        var sourceKeys = Set<CheckRunnerRestoreIdentitySourceV1>()
        var destinationKeys = Set<CheckRunnerRestoreIdentitySourceV1>()
        for pair in pairs {
            try pair.validate()
            guard sourceKeys.insert(try .init(kind: pair.kind, sourceID: pair.sourceID)).inserted,
                  destinationKeys.insert(try .init(kind: pair.kind, sourceID: pair.destinationID)).inserted else {
                throw CheckRunnerRestoreCorrespondenceFailureV1.duplicateIdentity
            }
            let expected: UUID?
            if let namespace = pair.kind.operationalNamespace {
                expected = RestoreIdentityV1.destinationFieldDraftID(
                    for: pair.sourceID, namespace: namespace, mode: mode.identityMode,
                    destinationWorkspaceID: destinationWorkspaceID
                )
            } else {
                expected = RestoreIdentityV1.destinationRecordID(for: pair.sourceID)
            }
            guard expected == pair.destinationID else {
                throw CheckRunnerRestoreCorrespondenceFailureV1.identityMismatch
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, mode, sourceWorkspaceID, destinationWorkspaceID, pairs, mapSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: ["schemaVersion", "mode", "sourceWorkspaceID", "destinationWorkspaceID", "pairs", "mapSHA256"]
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        mode = try c.decode(CheckRunnerRestoreModeV1.self, forKey: .mode)
        sourceWorkspaceID = try c.decode(UUID.self, forKey: .sourceWorkspaceID)
        destinationWorkspaceID = try c.decode(UUID.self, forKey: .destinationWorkspaceID)
        pairs = try c.decode([CheckRunnerRestoreIdentityPairV1].self, forKey: .pairs)
        mapSHA256 = try c.decode(String.self, forKey: .mapSHA256)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(mode, forKey: .mode)
        try c.encode(sourceWorkspaceID, forKey: .sourceWorkspaceID)
        try c.encode(destinationWorkspaceID, forKey: .destinationWorkspaceID)
        try c.encode(pairs, forKey: .pairs)
        try c.encode(mapSHA256, forKey: .mapSHA256)
    }
}

private enum CheckRunnerRestoreIdentityRulesV1 {
    static func validateID(_ id: UUID) throws {
        guard id.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.invalidIdentity
        }
    }

    static func validateSources(_ sources: [CheckRunnerRestoreIdentitySourceV1]) throws {
        try sources.forEach { try $0.validate() }
        guard Set(sources).count == sources.count else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.duplicateIdentity
        }
    }
}
