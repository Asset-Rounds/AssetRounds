import Foundation

enum CheckRunnerBeginMutationRoleV1: String, Codable, Equatable, Sendable {
    case record = "RECORD"
    case timeZone = "TIME_ZONE"

    fileprivate var targetKind: WorkspaceEntityKindV1 {
        switch self {
        case .record: return .workflowRecord
        case .timeZone: return .site
        }
    }

    fileprivate func accepts(_ command: CheckRunnerBeginCommittedEvidenceV1.Command) -> Bool {
        switch (self, command) {
        case (.record, .createCheckDraft), (.timeZone, .updateSiteTimeZone): return true
        default: return false
        }
    }
}

/// A comparison result only. A present candidate still needs the selected
/// destination route, exact effect and current target/successor checks.
enum CheckRunnerBeginSourceReadComparisonV1: Equatable, Sendable {
    case expectationMatched
    case sameKeyPresentCandidate
}

/// Immutable declared correspondence. Neither decoding nor a matching receipt
/// reference supplies a live lease, fresh CAS, or permission to adopt an effect.
struct CheckRunnerBeginMutationCorrespondenceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let schemaVersion: Int
    let role: CheckRunnerBeginMutationRoleV1
    let sourceWorkspaceID: WorkspaceID
    let sourceMutationID: MutationIDV1
    let sourceCommandCanonicalSHA256: String
    let expectedSourceEvidence: CheckRunnerExpectedSourceBeginEvidenceV1
    let destinationWorkspaceID: WorkspaceID
    let destinationMutationID: MutationIDV1
    let destinationCommandCanonicalSHA256: String
    let frozenCommittedAt: Date
    let destinationReceipt: CheckRunnerBeginReceiptReferenceV1?

    static func record(
        source: CheckRunnerFrozenBeginAttemptV1,
        binding: CheckRunnerDestinationBeginBindingV1,
        map: CheckRunnerRestoreIdentityMapV1,
        expectedSourceEvidence: CheckRunnerExpectedSourceBeginEvidenceV1,
        destinationReceipt: CheckRunnerBeginReceiptReferenceV1?
    ) throws -> Self {
        try Self(role: .record, source: source, binding: binding, map: map,
                 expectedSourceEvidence: expectedSourceEvidence, destinationReceipt: destinationReceipt)
    }

    static func timeZone(
        source: CheckRunnerFrozenBeginAttemptV1,
        binding: CheckRunnerDestinationBeginBindingV1,
        map: CheckRunnerRestoreIdentityMapV1,
        expectedSourceEvidence: CheckRunnerExpectedSourceBeginEvidenceV1,
        destinationReceipt: CheckRunnerBeginReceiptReferenceV1?
    ) throws -> Self? {
        try binding.validate(source: source, map: map)
        guard source.timeZone != nil else {
            guard case .absent = expectedSourceEvidence, destinationReceipt == nil else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
            return nil
        }
        return try Self(role: .timeZone, source: source, binding: binding, map: map,
                        expectedSourceEvidence: expectedSourceEvidence, destinationReceipt: destinationReceipt)
    }

    private init(
        role: CheckRunnerBeginMutationRoleV1,
        source: CheckRunnerFrozenBeginAttemptV1,
        binding: CheckRunnerDestinationBeginBindingV1,
        map: CheckRunnerRestoreIdentityMapV1,
        expectedSourceEvidence: CheckRunnerExpectedSourceBeginEvidenceV1,
        destinationReceipt: CheckRunnerBeginReceiptReferenceV1?
    ) throws {
        try binding.validate(source: source, map: map)
        schemaVersion = 1
        self.role = role
        sourceWorkspaceID = source.sourceWorkspaceID
        destinationWorkspaceID = binding.destinationWorkspaceID
        self.expectedSourceEvidence = expectedSourceEvidence
        self.destinationReceipt = destinationReceipt
        switch role {
        case .record:
            sourceMutationID = source.recordMutationID
            destinationMutationID = binding.recordMutationID
            sourceCommandCanonicalSHA256 = try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.createCheckDraft(source.recordCommand))
            destinationCommandCanonicalSHA256 = try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.createCheckDraft(binding.recordCommand))
            frozenCommittedAt = source.recordCommittedAt
        case .timeZone:
            guard let original = source.timeZone,
                  let mutationID = binding.timeZoneMutationID,
                  let command = binding.timeZoneCommand else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
            sourceMutationID = original.mutationID
            destinationMutationID = mutationID
            sourceCommandCanonicalSHA256 = try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.updateSiteTimeZone(original.command))
            destinationCommandCanonicalSHA256 = try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.updateSiteTimeZone(command))
            frozenCommittedAt = original.committedAt
        }
        try validate(source: source, binding: binding, map: map)
    }

    var hasIdenticalKeys: Bool {
        sourceWorkspaceID == destinationWorkspaceID && sourceMutationID == destinationMutationID
    }

    /// Closed shape and cross-field consistency. Contextual validation against
    /// the original source and identity map remains mandatory after decoding.
    func validate() throws {
        try FieldDraftValidationV1.workspace(sourceWorkspaceID)
        try FieldDraftValidationV1.workspace(destinationWorkspaceID)
        _ = try MutationIDV1(rawValue: sourceMutationID.rawValue)
        _ = try MutationIDV1(rawValue: destinationMutationID.rawValue)
        try expectedSourceEvidence.validate(sourceWorkspaceID: sourceWorkspaceID,
                                            sourceMutationID: sourceMutationID)
        guard schemaVersion == 1,
              KernelCanonicalHashV1.validSHA256(sourceCommandCanonicalSHA256),
              KernelCanonicalHashV1.validSHA256(destinationCommandCanonicalSHA256),
              sourceCommandCanonicalSHA256 == destinationCommandCanonicalSHA256,
              frozenCommittedAt.timeIntervalSince1970.isFinite,
              frozenCommittedAt.timeIntervalSince1970 >= 0 else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        if case let .exact(evidence) = expectedSourceEvidence {
            guard role.accepts(evidence.command),
                  evidence.envelope.commandBodySHA256 == sourceCommandCanonicalSHA256,
                  evidence.receipt.committedAt == frozenCommittedAt else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
        }
        if let reference = destinationReceipt {
            try reference.validate()
            guard reference.workspaceID == destinationWorkspaceID,
                  reference.mutationID == destinationMutationID,
                  reference.beginPostimageIdentity.kind == role.targetKind,
                  reference.commandBodySHA256 == destinationCommandCanonicalSHA256,
                  reference.committedAt == frozenCommittedAt else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
            if hasIdenticalKeys, case let .exact(original) = expectedSourceEvidence {
                guard reference == (try CheckRunnerBeginReceiptReferenceV1(evidence: original)) else {
                    throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
                }
            }
        }
    }

    func validate(source: CheckRunnerFrozenBeginAttemptV1,
                  binding: CheckRunnerDestinationBeginBindingV1,
                  map: CheckRunnerRestoreIdentityMapV1) throws {
        try validate()
        try binding.validate(source: source, map: map)
        guard sourceWorkspaceID == source.sourceWorkspaceID,
              destinationWorkspaceID == binding.destinationWorkspaceID else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        let originalCommand: WorkspaceCommandV1
        let destinationCommand: WorkspaceCommandV1
        let expectedEntities: [WorkspaceEntityRevisionV1]
        switch role {
        case .record:
            guard sourceMutationID == source.recordMutationID,
                  destinationMutationID == binding.recordMutationID,
                  frozenCommittedAt == source.recordCommittedAt,
                  frozenCommittedAt == binding.recordCommittedAt else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
            originalCommand = .createCheckDraft(source.recordCommand)
            destinationCommand = .createCheckDraft(binding.recordCommand)
            expectedEntities = source.recordExpectedEntityRevisions
        case .timeZone:
            guard let original = source.timeZone,
                  sourceMutationID == original.mutationID,
                  destinationMutationID == binding.timeZoneMutationID,
                  let command = binding.timeZoneCommand,
                  frozenCommittedAt == original.committedAt,
                  frozenCommittedAt == binding.timeZoneCommittedAt else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
            originalCommand = .updateSiteTimeZone(original.command)
            destinationCommand = .updateSiteTimeZone(command)
            expectedEntities = [try .init(identity: .init(kind: .site, id: original.command.siteID),
                                          revision: original.expectedSiteRevision)]
        }
        guard sourceCommandCanonicalSHA256 == (try WorkspaceMutationCanonicalV1.sha256(originalCommand)),
              destinationCommandCanonicalSHA256 == (try WorkspaceMutationCanonicalV1.sha256(destinationCommand)) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        if case let .exact(evidence) = expectedSourceEvidence {
            // A fresh full workspace CAS may include unrelated entries. Every
            // dependency frozen for this original effect must still match.
            for required in expectedEntities {
                let entries = evidence.receipt.expectedRevision.entityRevisions.filter {
                    $0.identity == required.identity
                }
                guard entries.count == 1, entries[0].revision == required.revision else {
                    throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
                }
            }
        }
    }

    /// Compare the caller's one authenticated full-journal source-key read.
    /// This method performs no lookup and never turns a candidate into adoption.
    func validateFreshSourceRead(
        _ actual: CheckRunnerBeginCommittedEvidenceV1?
    ) throws -> CheckRunnerBeginSourceReadComparisonV1 {
        try validate()
        if let actual {
            _ = try CheckRunnerBeginCommittedEvidenceV1(envelope: actual.envelope, receipt: actual.receipt)
            guard actual.envelope.workspaceID == sourceWorkspaceID,
                  actual.envelope.mutationID == sourceMutationID else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
        }
        switch (expectedSourceEvidence, actual) {
        case (.absent, nil): return .expectationMatched
        case (.absent, .some) where hasIdenticalKeys: return .sameKeyPresentCandidate
        case let (.exact(expected), .some(observed)):
            guard try expected.envelope.canonicalData() == observed.envelope.canonicalData(),
                  try expected.receipt.canonicalData() == observed.receipt.canonicalData() else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
            return .expectationMatched
        default: throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
    }

    /// Authenticate the stored historical reference. Destination provenance,
    /// live target/successor state and effect permission remain later gates.
    func validateDestinationEvidence(_ evidence: CheckRunnerBeginCommittedEvidenceV1) throws {
        try validate()
        guard let reference = destinationReceipt, role.accepts(evidence.command) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
        try reference.validate(evidence: evidence)
        if hasIdenticalKeys, case let .exact(original) = expectedSourceEvidence {
            guard try original.envelope.canonicalData() == evidence.envelope.canonicalData(),
                  try original.receipt.canonicalData() == evidence.receipt.canonicalData() else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, role, sourceWorkspaceID, sourceMutationID, sourceCommandCanonicalSHA256
        case expectedSourceEvidence, destinationWorkspaceID, destinationMutationID
        case destinationCommandCanonicalSHA256, frozenCommittedAt, destinationReceipt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        role = try c.decode(CheckRunnerBeginMutationRoleV1.self, forKey: .role)
        sourceWorkspaceID = try c.decode(WorkspaceID.self, forKey: .sourceWorkspaceID)
        sourceMutationID = try c.decode(MutationIDV1.self, forKey: .sourceMutationID)
        sourceCommandCanonicalSHA256 = try c.decode(String.self, forKey: .sourceCommandCanonicalSHA256)
        expectedSourceEvidence = try c.decode(CheckRunnerExpectedSourceBeginEvidenceV1.self, forKey: .expectedSourceEvidence)
        destinationWorkspaceID = try c.decode(WorkspaceID.self, forKey: .destinationWorkspaceID)
        destinationMutationID = try c.decode(MutationIDV1.self, forKey: .destinationMutationID)
        destinationCommandCanonicalSHA256 = try c.decode(String.self, forKey: .destinationCommandCanonicalSHA256)
        frozenCommittedAt = try c.decode(Date.self, forKey: .frozenCommittedAt)
        destinationReceipt = try c.decodeIfPresent(CheckRunnerBeginReceiptReferenceV1.self, forKey: .destinationReceipt)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(role, forKey: .role)
        try c.encode(sourceWorkspaceID, forKey: .sourceWorkspaceID)
        try c.encode(sourceMutationID, forKey: .sourceMutationID)
        try c.encode(sourceCommandCanonicalSHA256, forKey: .sourceCommandCanonicalSHA256)
        try c.encode(expectedSourceEvidence, forKey: .expectedSourceEvidence)
        try c.encode(destinationWorkspaceID, forKey: .destinationWorkspaceID)
        try c.encode(destinationMutationID, forKey: .destinationMutationID)
        try c.encode(destinationCommandCanonicalSHA256, forKey: .destinationCommandCanonicalSHA256)
        try c.encode(frozenCommittedAt, forKey: .frozenCommittedAt)
        try c.encodeIfPresent(destinationReceipt, forKey: .destinationReceipt)
    }
}
