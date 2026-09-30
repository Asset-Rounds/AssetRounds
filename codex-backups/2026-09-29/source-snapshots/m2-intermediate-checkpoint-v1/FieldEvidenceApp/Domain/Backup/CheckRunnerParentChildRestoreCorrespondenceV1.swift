import Foundation

/// References to two supplied checkpoints. Their validated bytes and mapping
/// are bound here; omission-free child history requires the later codec graph.
struct CheckRunnerChildCheckpointCorrespondenceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let sourceWorkspaceID: WorkspaceID
    let sourceDraftID: UUID
    let sourceDraftRevision: UInt64
    let sourceCheckpointSHA256: String
    let sourceMutationID: MutationIDV1
    let destinationWorkspaceID: WorkspaceID
    let destinationDraftID: UUID
    let destinationDraftRevision: UInt64
    let destinationCheckpointSHA256: String
    let destinationMutationID: MutationIDV1

    init(source: FieldDraftCheckpointV1, destination: FieldDraftCheckpointV1,
         map: CheckRunnerRestoreIdentityMapV1) throws {
        try source.validate()
        try destination.validate()
        sourceWorkspaceID = source.workspaceID
        sourceDraftID = source.draftID
        sourceDraftRevision = source.draftRevision
        sourceCheckpointSHA256 = source.checkpointSHA256
        sourceMutationID = source.mutationID
        destinationWorkspaceID = destination.workspaceID
        destinationDraftID = destination.draftID
        destinationDraftRevision = destination.draftRevision
        destinationCheckpointSHA256 = destination.checkpointSHA256
        destinationMutationID = destination.mutationID
        try validate(map: map)
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(sourceWorkspaceID)
        try FieldDraftValidationV1.workspace(destinationWorkspaceID)
        try FieldDraftValidationV1.id(sourceDraftID)
        try FieldDraftValidationV1.id(destinationDraftID)
        _ = try MutationIDV1(rawValue: sourceMutationID.rawValue)
        _ = try MutationIDV1(rawValue: destinationMutationID.rawValue)
        try FieldDraftValidationV1.revision(sourceDraftRevision)
        try FieldDraftValidationV1.revision(destinationDraftRevision)
        try FieldDraftValidationV1.digest(sourceCheckpointSHA256)
        try FieldDraftValidationV1.digest(destinationCheckpointSHA256)
        guard sourceDraftRevision == destinationDraftRevision else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
    }

    func validate(map: CheckRunnerRestoreIdentityMapV1) throws {
        try validate()
        try map.validate()
        guard sourceWorkspaceID.rawValue == map.sourceWorkspaceID,
              destinationWorkspaceID.rawValue == map.destinationWorkspaceID,
              destinationDraftID == (try map.destinationID(for: sourceDraftID, kind: .childDraft)),
              destinationMutationID.rawValue == (try map.destinationID(
                for: sourceMutationID.rawValue, kind: .checkpointMutation)) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
    }

    func validate(source: FieldDraftCheckpointV1, destination: FieldDraftCheckpointV1,
                  map: CheckRunnerRestoreIdentityMapV1) throws {
        guard self == (try Self(source: source, destination: destination, map: map)) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
    }

    fileprivate var sourceKey: String {
        sourceDraftID.uuidString.lowercased() + "/" + String(sourceDraftRevision)
    }
    fileprivate var destinationKey: String {
        destinationDraftID.uuidString.lowercased() + "/" + String(destinationDraftRevision)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceWorkspaceID, sourceDraftID, sourceDraftRevision, sourceCheckpointSHA256, sourceMutationID
        case destinationWorkspaceID, destinationDraftID, destinationDraftRevision
        case destinationCheckpointSHA256, destinationMutationID
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceWorkspaceID = try c.decode(WorkspaceID.self, forKey: .sourceWorkspaceID)
        sourceDraftID = try c.decode(UUID.self, forKey: .sourceDraftID)
        sourceDraftRevision = try c.decode(UInt64.self, forKey: .sourceDraftRevision)
        sourceCheckpointSHA256 = try c.decode(String.self, forKey: .sourceCheckpointSHA256)
        sourceMutationID = try c.decode(MutationIDV1.self, forKey: .sourceMutationID)
        destinationWorkspaceID = try c.decode(WorkspaceID.self, forKey: .destinationWorkspaceID)
        destinationDraftID = try c.decode(UUID.self, forKey: .destinationDraftID)
        destinationDraftRevision = try c.decode(UInt64.self, forKey: .destinationDraftRevision)
        destinationCheckpointSHA256 = try c.decode(String.self, forKey: .destinationCheckpointSHA256)
        destinationMutationID = try c.decode(MutationIDV1.self, forKey: .destinationMutationID)
        try validate()
    }
}

/// Exact declared commit-to-target linkage from supplied validated values.
/// Full journal authentication and the child codec's target-command proof are
/// separate requirements; a matching row or digest alone cannot replace them.
struct CheckRunnerChildTargetReceiptCorrespondenceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let sourceWorkspaceID: WorkspaceID
    let destinationWorkspaceID: WorkspaceID
    let sourceDraftID: UUID
    let destinationDraftID: UUID
    let sourceCommitReceiptID: UUID
    let destinationCommitReceiptID: UUID
    let sourceCommitReceiptSHA256: String
    let destinationCommitReceiptSHA256: String
    let sourceTargetMutationID: MutationIDV1
    let destinationTargetMutationID: MutationIDV1
    let sourceTargetResultSHA256: String
    let destinationTargetResultSHA256: String
    let sourceTargetCommittedAt: Date
    let destinationTargetCommittedAt: Date

    init(sourceCommitReceipt: DraftCommitReceiptV1, sourceTargetReceipt: MutationReceiptV1,
         destinationCommitReceipt: DraftCommitReceiptV1, destinationTargetReceipt: MutationReceiptV1,
         map: CheckRunnerRestoreIdentityMapV1) throws {
        try Self.validateLink(commit: sourceCommitReceipt, target: sourceTargetReceipt)
        try Self.validateLink(commit: destinationCommitReceipt, target: destinationTargetReceipt)
        sourceWorkspaceID = sourceCommitReceipt.workspaceID
        destinationWorkspaceID = destinationCommitReceipt.workspaceID
        sourceDraftID = sourceCommitReceipt.draftID
        destinationDraftID = destinationCommitReceipt.draftID
        sourceCommitReceiptID = sourceCommitReceipt.receiptID
        destinationCommitReceiptID = destinationCommitReceipt.receiptID
        sourceCommitReceiptSHA256 = sourceCommitReceipt.receiptSHA256
        destinationCommitReceiptSHA256 = destinationCommitReceipt.receiptSHA256
        sourceTargetMutationID = sourceTargetReceipt.mutationID
        destinationTargetMutationID = destinationTargetReceipt.mutationID
        sourceTargetResultSHA256 = sourceTargetReceipt.resultSHA256
        destinationTargetResultSHA256 = destinationTargetReceipt.resultSHA256
        sourceTargetCommittedAt = sourceTargetReceipt.committedAt
        destinationTargetCommittedAt = destinationTargetReceipt.committedAt
        try validate(map: map)
    }

    private static func validateLink(commit: DraftCommitReceiptV1, target: MutationReceiptV1) throws {
        try commit.validate()
        try target.validate()
        guard commit.workspaceID == target.identity.workspaceID,
              commit.targetMutationID == target.mutationID,
              commit.targetReceiptSHA256 == target.resultSHA256,
              commit.committedAt == target.committedAt else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(sourceWorkspaceID)
        try FieldDraftValidationV1.workspace(destinationWorkspaceID)
        try [sourceDraftID, destinationDraftID, sourceCommitReceiptID, destinationCommitReceiptID]
            .forEach(FieldDraftValidationV1.id)
        _ = try MutationIDV1(rawValue: sourceTargetMutationID.rawValue)
        _ = try MutationIDV1(rawValue: destinationTargetMutationID.rawValue)
        try [sourceCommitReceiptSHA256, destinationCommitReceiptSHA256,
             sourceTargetResultSHA256, destinationTargetResultSHA256].forEach(FieldDraftValidationV1.digest)
        try FieldDraftValidationV1.instant(sourceTargetCommittedAt)
        try FieldDraftValidationV1.instant(destinationTargetCommittedAt)
    }

    func validate(map: CheckRunnerRestoreIdentityMapV1) throws {
        try validate()
        try map.validate()
        guard sourceWorkspaceID.rawValue == map.sourceWorkspaceID,
              destinationWorkspaceID.rawValue == map.destinationWorkspaceID,
              destinationDraftID == (try map.destinationID(for: sourceDraftID, kind: .childDraft)),
              destinationCommitReceiptID == (try map.destinationID(
                for: sourceCommitReceiptID, kind: .commitReceipt)),
              destinationTargetMutationID.rawValue == (try map.destinationID(
                for: sourceTargetMutationID.rawValue, kind: .commitTargetMutation)) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
    }

    func validate(sourceCommitReceipt: DraftCommitReceiptV1, sourceTargetReceipt: MutationReceiptV1,
                  destinationCommitReceipt: DraftCommitReceiptV1, destinationTargetReceipt: MutationReceiptV1,
                  map: CheckRunnerRestoreIdentityMapV1) throws {
        guard self == (try Self(sourceCommitReceipt: sourceCommitReceipt, sourceTargetReceipt: sourceTargetReceipt,
                               destinationCommitReceipt: destinationCommitReceipt,
                               destinationTargetReceipt: destinationTargetReceipt, map: map)) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
    }

    fileprivate var sourceKey: String {
        [sourceDraftID, sourceCommitReceiptID, sourceTargetMutationID.rawValue]
            .map { $0.uuidString.lowercased() }.joined(separator: "/")
    }
    fileprivate var destinationKey: String {
        [destinationDraftID, destinationCommitReceiptID, destinationTargetMutationID.rawValue]
            .map { $0.uuidString.lowercased() }.joined(separator: "/")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceWorkspaceID, destinationWorkspaceID, sourceDraftID, destinationDraftID
        case sourceCommitReceiptID, destinationCommitReceiptID, sourceCommitReceiptSHA256, destinationCommitReceiptSHA256
        case sourceTargetMutationID, destinationTargetMutationID, sourceTargetResultSHA256, destinationTargetResultSHA256
        case sourceTargetCommittedAt, destinationTargetCommittedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceWorkspaceID = try c.decode(WorkspaceID.self, forKey: .sourceWorkspaceID)
        destinationWorkspaceID = try c.decode(WorkspaceID.self, forKey: .destinationWorkspaceID)
        sourceDraftID = try c.decode(UUID.self, forKey: .sourceDraftID)
        destinationDraftID = try c.decode(UUID.self, forKey: .destinationDraftID)
        sourceCommitReceiptID = try c.decode(UUID.self, forKey: .sourceCommitReceiptID)
        destinationCommitReceiptID = try c.decode(UUID.self, forKey: .destinationCommitReceiptID)
        sourceCommitReceiptSHA256 = try c.decode(String.self, forKey: .sourceCommitReceiptSHA256)
        destinationCommitReceiptSHA256 = try c.decode(String.self, forKey: .destinationCommitReceiptSHA256)
        sourceTargetMutationID = try c.decode(MutationIDV1.self, forKey: .sourceTargetMutationID)
        destinationTargetMutationID = try c.decode(MutationIDV1.self, forKey: .destinationTargetMutationID)
        sourceTargetResultSHA256 = try c.decode(String.self, forKey: .sourceTargetResultSHA256)
        destinationTargetResultSHA256 = try c.decode(String.self, forKey: .destinationTargetResultSHA256)
        sourceTargetCommittedAt = try c.decode(Date.self, forKey: .sourceTargetCommittedAt)
        destinationTargetCommittedAt = try c.decode(Date.self, forKey: .destinationTargetCommittedAt)
        try validate()
    }
}

enum CheckRunnerRestoreBeginPhaseV1: String, Codable, Equatable, Sendable {
    case prepared = "PREPARED"
    case bound = "BOUND"
}

/// Canonical correspondence for the explicitly supplied identity and child
/// pairs. A released parent/child codec must later prove complete graph coverage,
/// phase ordering and command meaning before any staging publication or resume.
struct CheckRunnerParentChildRestoreCorrespondenceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let schemaVersion: Int
    let mode: CheckRunnerRestoreModeV1
    let sourceWorkspaceID: WorkspaceID
    let destinationWorkspaceID: WorkspaceID
    let sourceAttemptSHA256: String
    let destinationBinding: CheckRunnerDestinationBeginBindingV1
    let destinationBindingSHA256: String
    let identityPairs: [CheckRunnerRestoreIdentityPairV1]
    let dependencies: [CheckRunnerDestinationDependencyV1]
    let recordBegin: CheckRunnerBeginMutationCorrespondenceV1
    let timeZoneBegin: CheckRunnerBeginMutationCorrespondenceV1?
    let childCheckpointPairs: [CheckRunnerChildCheckpointCorrespondenceV1]
    let childTargetReceiptPairs: [CheckRunnerChildTargetReceiptCorrespondenceV1]
    let mappingSHA256: String

    static func make(
        identity: RestoreIdentityV1, source: CheckRunnerFrozenBeginAttemptV1,
        declaredSources: [CheckRunnerRestoreIdentitySourceV1],
        binding: CheckRunnerDestinationBeginBindingV1? = nil,
        recordBegin: CheckRunnerBeginMutationCorrespondenceV1? = nil,
        timeZoneBegin: CheckRunnerBeginMutationCorrespondenceV1? = nil,
        childCheckpointPairs: [CheckRunnerChildCheckpointCorrespondenceV1] = [],
        childTargetReceiptPairs: [CheckRunnerChildTargetReceiptCorrespondenceV1] = []
    ) throws -> Self? {
        try source.validate()
        guard source.sourceWorkspaceID.rawValue == identity.source.workspaceID else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        // The existing identity authority returns nil only for configuration
        // clone. No operational correspondence is published for that mode.
        guard let map = try CheckRunnerRestoreIdentityMapV1.make(identity: identity, sources: declaredSources) else {
            return nil
        }
        guard let binding, let recordBegin else { throw CheckRunnerRestoreBeginFailureV1.invalidBinding }
        return try Self(source: source, binding: binding, map: map, recordBegin: recordBegin,
                        timeZoneBegin: timeZoneBegin, childCheckpointPairs: childCheckpointPairs,
                        childTargetReceiptPairs: childTargetReceiptPairs)
    }

    init(source: CheckRunnerFrozenBeginAttemptV1, binding: CheckRunnerDestinationBeginBindingV1,
         map: CheckRunnerRestoreIdentityMapV1, recordBegin: CheckRunnerBeginMutationCorrespondenceV1,
         timeZoneBegin: CheckRunnerBeginMutationCorrespondenceV1?,
         childCheckpointPairs: [CheckRunnerChildCheckpointCorrespondenceV1],
         childTargetReceiptPairs: [CheckRunnerChildTargetReceiptCorrespondenceV1]) throws {
        try source.validate()
        try binding.validate(source: source, map: map)
        schemaVersion = 1
        mode = map.mode
        sourceWorkspaceID = source.sourceWorkspaceID
        destinationWorkspaceID = binding.destinationWorkspaceID
        sourceAttemptSHA256 = try FieldDraftCanonicalCodecV1.sha256(source)
        destinationBinding = binding
        destinationBindingSHA256 = try binding.canonicalSHA256()
        identityPairs = map.pairs
        dependencies = try Self.dependencyUnion(binding)
        self.recordBegin = recordBegin
        self.timeZoneBegin = timeZoneBegin
        self.childCheckpointPairs = childCheckpointPairs.sorted { $0.sourceKey < $1.sourceKey }
        self.childTargetReceiptPairs = childTargetReceiptPairs.sorted { $0.sourceKey < $1.sourceKey }
        mappingSHA256 = try FieldDraftCanonicalCodecV1.sha256(Body(
            schemaVersion: schemaVersion, mode: mode, sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID, sourceAttemptSHA256: sourceAttemptSHA256,
            destinationBinding: destinationBinding, destinationBindingSHA256: destinationBindingSHA256,
            identityPairs: identityPairs, dependencies: dependencies, recordBegin: recordBegin,
            timeZoneBegin: timeZoneBegin, childCheckpointPairs: self.childCheckpointPairs,
            childTargetReceiptPairs: self.childTargetReceiptPairs))
        try validate(source: source)
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw CheckRunnerRestoreCorrespondenceFailureV1.unsupportedSchema }
        try FieldDraftValidationV1.workspace(sourceWorkspaceID)
        try FieldDraftValidationV1.workspace(destinationWorkspaceID)
        try FieldDraftValidationV1.digest(sourceAttemptSHA256)
        try destinationBinding.validate()
        let map = try identityMap()
        guard identityPairs == map.pairs,
              destinationWorkspaceID == destinationBinding.destinationWorkspaceID,
              destinationBindingSHA256 == (try destinationBinding.canonicalSHA256()),
              dependencies == (try Self.dependencyUnion(destinationBinding)),
              mappingSHA256 == (try FieldDraftCanonicalCodecV1.sha256(body)) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.digestMismatch
        }
        for dependency in dependencies {
            let kind: CheckRunnerRestoreIdentityKindV1
            switch dependency.sourceIdentity.kind {
            case .site: kind = .site
            case .asset: kind = .asset
            case .issue: kind = .issue
            case .workflowRecord:
                kind = dependency.sourceIdentity.id == destinationBinding.recordCommand.recordID
                    ? .workflowRecord : .parentRecord
            default: throw CheckRunnerRestoreBeginFailureV1.invalidDependency
            }
            try dependency.validate(map: map, kind: kind)
        }
        try validateBegin(recordBegin, role: .record, map: map,
                          mutationID: destinationBinding.recordMutationID,
                          command: .createCheckDraft(destinationBinding.recordCommand),
                          committedAt: destinationBinding.recordCommittedAt)
        switch (timeZoneBegin, destinationBinding.timeZoneMutationID,
                destinationBinding.timeZoneCommand, destinationBinding.timeZoneCommittedAt) {
        case (nil, nil, nil, nil): break
        case let (.some(pair), .some(mutationID), .some(command), .some(committedAt)):
            try validateBegin(pair, role: .timeZone, map: map, mutationID: mutationID,
                              command: .updateSiteTimeZone(command), committedAt: committedAt)
        default: throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        try childCheckpointPairs.forEach { try $0.validate(map: map) }
        try childTargetReceiptPairs.forEach { try $0.validate(map: map) }
        guard childCheckpointPairs == childCheckpointPairs.sorted(by: { $0.sourceKey < $1.sourceKey }),
              childTargetReceiptPairs == childTargetReceiptPairs.sorted(by: { $0.sourceKey < $1.sourceKey }),
              Set(childCheckpointPairs.map(\.sourceKey)).count == childCheckpointPairs.count,
              Set(childCheckpointPairs.map(\.destinationKey)).count == childCheckpointPairs.count,
              Set(childCheckpointPairs.map(\.sourceMutationID)).count == childCheckpointPairs.count,
              Set(childCheckpointPairs.map(\.destinationMutationID)).count == childCheckpointPairs.count,
              Set(childTargetReceiptPairs.map(\.sourceKey)).count == childTargetReceiptPairs.count,
              Set(childTargetReceiptPairs.map(\.destinationKey)).count == childTargetReceiptPairs.count,
              Set(childTargetReceiptPairs.map(\.sourceCommitReceiptID)).count == childTargetReceiptPairs.count,
              Set(childTargetReceiptPairs.map(\.destinationCommitReceiptID)).count == childTargetReceiptPairs.count,
              Set(childTargetReceiptPairs.map(\.sourceTargetMutationID)).count == childTargetReceiptPairs.count,
              Set(childTargetReceiptPairs.map(\.destinationTargetMutationID)).count == childTargetReceiptPairs.count else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.noncanonicalPairs
        }
    }

    func validate(source: CheckRunnerFrozenBeginAttemptV1) throws {
        try validate()
        try source.validate()
        let map = try identityMap()
        guard sourceWorkspaceID == source.sourceWorkspaceID,
              sourceAttemptSHA256 == (try FieldDraftCanonicalCodecV1.sha256(source)) else {
            throw CheckRunnerRestoreCorrespondenceFailureV1.digestMismatch
        }
        try destinationBinding.validate(source: source, map: map)
        try recordBegin.validate(source: source, binding: destinationBinding, map: map)
        try timeZoneBegin?.validate(source: source, binding: destinationBinding, map: map)
    }

    /// Explicit phase shape only. BOUND still requires authenticated destination
    /// evidence and current target/successor checks in the later live service.
    func validate(phase: CheckRunnerRestoreBeginPhaseV1) throws {
        try validate()
        let records = [recordBegin] + (timeZoneBegin.map { [$0] } ?? [])
        switch phase {
        case .prepared:
            guard records.allSatisfy({ $0.destinationReceipt == nil }) else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
        case .bound:
            guard records.allSatisfy({ $0.destinationReceipt != nil }) else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
        }
    }

    private func validateBegin(_ pair: CheckRunnerBeginMutationCorrespondenceV1,
                               role: CheckRunnerBeginMutationRoleV1,
                               map: CheckRunnerRestoreIdentityMapV1, mutationID: MutationIDV1,
                               command: WorkspaceCommandV1, committedAt: Date) throws {
        try pair.validate()
        let identityKind: CheckRunnerRestoreIdentityKindV1 = role == .record ? .beginRecordMutation : .beginTimeZoneMutation
        guard pair.role == role, pair.sourceWorkspaceID == sourceWorkspaceID,
              pair.destinationWorkspaceID == destinationWorkspaceID,
              pair.destinationMutationID == mutationID,
              pair.destinationMutationID.rawValue == (try map.destinationID(
                for: pair.sourceMutationID.rawValue, kind: identityKind)),
              pair.destinationCommandCanonicalSHA256 == (try WorkspaceMutationCanonicalV1.sha256(command)),
              pair.frozenCommittedAt == committedAt else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
    }

    private func identityMap() throws -> CheckRunnerRestoreIdentityMapV1 {
        try .init(mode: mode, sourceWorkspaceID: sourceWorkspaceID.rawValue,
                  destinationWorkspaceID: destinationWorkspaceID.rawValue, pairs: identityPairs)
    }

    private static func dependencyUnion(
        _ binding: CheckRunnerDestinationBeginBindingV1
    ) throws -> [CheckRunnerDestinationDependencyV1] {
        var result: [WorkspaceEntityIdentityV1: CheckRunnerDestinationDependencyV1] = [:]
        for dependency in binding.recordMappedDependencyBasis + (binding.timeZoneMappedDependencyBasis ?? []) {
            try dependency.validate()
            if let existing = result[dependency.sourceIdentity], existing != dependency {
                throw CheckRunnerRestoreBeginFailureV1.invalidDependency
            }
            result[dependency.sourceIdentity] = dependency
        }
        return result.values.sorted { $0.sourceIdentity.stableKey < $1.sourceIdentity.stableKey }
    }

    private struct Body: Encodable {
        let schemaVersion: Int
        let mode: CheckRunnerRestoreModeV1
        let sourceWorkspaceID: WorkspaceID
        let destinationWorkspaceID: WorkspaceID
        let sourceAttemptSHA256: String
        let destinationBinding: CheckRunnerDestinationBeginBindingV1
        let destinationBindingSHA256: String
        let identityPairs: [CheckRunnerRestoreIdentityPairV1]
        let dependencies: [CheckRunnerDestinationDependencyV1]
        let recordBegin: CheckRunnerBeginMutationCorrespondenceV1
        let timeZoneBegin: CheckRunnerBeginMutationCorrespondenceV1?
        let childCheckpointPairs: [CheckRunnerChildCheckpointCorrespondenceV1]
        let childTargetReceiptPairs: [CheckRunnerChildTargetReceiptCorrespondenceV1]
    }

    private var body: Body {
        Body(schemaVersion: schemaVersion, mode: mode, sourceWorkspaceID: sourceWorkspaceID,
             destinationWorkspaceID: destinationWorkspaceID, sourceAttemptSHA256: sourceAttemptSHA256,
             destinationBinding: destinationBinding, destinationBindingSHA256: destinationBindingSHA256,
             identityPairs: identityPairs, dependencies: dependencies, recordBegin: recordBegin,
             timeZoneBegin: timeZoneBegin, childCheckpointPairs: childCheckpointPairs,
             childTargetReceiptPairs: childTargetReceiptPairs)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, mode, sourceWorkspaceID, destinationWorkspaceID, sourceAttemptSHA256
        case destinationBinding, destinationBindingSHA256, identityPairs, dependencies, recordBegin, timeZoneBegin
        case childCheckpointPairs, childTargetReceiptPairs, mappingSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        mode = try c.decode(CheckRunnerRestoreModeV1.self, forKey: .mode)
        sourceWorkspaceID = try c.decode(WorkspaceID.self, forKey: .sourceWorkspaceID)
        destinationWorkspaceID = try c.decode(WorkspaceID.self, forKey: .destinationWorkspaceID)
        sourceAttemptSHA256 = try c.decode(String.self, forKey: .sourceAttemptSHA256)
        destinationBinding = try c.decode(CheckRunnerDestinationBeginBindingV1.self, forKey: .destinationBinding)
        destinationBindingSHA256 = try c.decode(String.self, forKey: .destinationBindingSHA256)
        identityPairs = try c.decode([CheckRunnerRestoreIdentityPairV1].self, forKey: .identityPairs)
        dependencies = try c.decode([CheckRunnerDestinationDependencyV1].self, forKey: .dependencies)
        recordBegin = try c.decode(CheckRunnerBeginMutationCorrespondenceV1.self, forKey: .recordBegin)
        timeZoneBegin = try c.decodeIfPresent(CheckRunnerBeginMutationCorrespondenceV1.self, forKey: .timeZoneBegin)
        childCheckpointPairs = try c.decode([CheckRunnerChildCheckpointCorrespondenceV1].self, forKey: .childCheckpointPairs)
        childTargetReceiptPairs = try c.decode([CheckRunnerChildTargetReceiptCorrespondenceV1].self, forKey: .childTargetReceiptPairs)
        mappingSHA256 = try c.decode(String.self, forKey: .mappingSHA256)
        try validate()
    }
}
