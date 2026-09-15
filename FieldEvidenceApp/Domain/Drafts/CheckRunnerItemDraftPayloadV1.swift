import Foundation

/// Original Begin values and receipt references. A BOUND tag proves only the
/// links encoded here; the current journal, target and source must still be read.
enum CheckRunnerBeginStateV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    case notBegun
    case prepared(attempt: CheckRunnerFrozenBeginAttemptV1)
    case bound(attempt: CheckRunnerFrozenBeginAttemptV1,
               workflowReceiptReference: CheckRunnerBeginReceiptReferenceV1,
               timeZoneReceiptReference: CheckRunnerBeginReceiptReferenceV1?)

    var attempt: CheckRunnerFrozenBeginAttemptV1? {
        switch self {
        case .notBegun: nil
        case let .prepared(attempt), let .bound(attempt, _, _): attempt
        }
    }

    var workflowReceiptReference: CheckRunnerBeginReceiptReferenceV1? {
        switch self { case let .bound(_, receipt, _): receipt; default: nil }
    }

    func validate() throws {
        try attempt?.validate()
        if let attempt, let timeZone = attempt.timeZone {
            guard timeZone.committedAt <= attempt.recordCommittedAt else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
        guard case let .bound(attempt, workflow, timeZone) = self else { return }
        try Self.validateReference(workflow, workspaceID: attempt.sourceWorkspaceID,
            mutationID: attempt.recordMutationID, command: .createCheckDraft(attempt.recordCommand),
            target: .init(kind: .workflowRecord, id: attempt.recordCommand.recordID),
            resultingTargetRevision: 1, committedAt: attempt.recordCommittedAt)
        guard (attempt.timeZone == nil) == (timeZone == nil) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        if let frozen = attempt.timeZone, let timeZone {
            try Self.validateReference(timeZone, workspaceID: attempt.sourceWorkspaceID,
                mutationID: frozen.mutationID, command: .updateSiteTimeZone(frozen.command),
                target: .init(kind: .site, id: frozen.command.siteID),
                resultingTargetRevision: frozen.expectedSiteRevision + 1,
                committedAt: frozen.committedAt)
            guard workflow.receiptIdentity != timeZone.receiptIdentity,
                  workflow.expectedWorkspaceRevision >= timeZone.resultingWorkspaceRevision else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
    }

    func validate(source: CheckRunnerRoundItemSourceV1) throws {
        try validate()
        try source.validate()
        if let attempt {
            guard attempt.source == source else { throw FieldDraftFailureV1.digestMismatch }
        }
    }

    private static func validateReference(_ reference: CheckRunnerBeginReceiptReferenceV1,
        workspaceID: WorkspaceID, mutationID: MutationIDV1, command: WorkspaceCommandV1,
        target: WorkspaceEntityIdentityV1, resultingTargetRevision: UInt64,
        committedAt: Date) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID, reference.mutationID == mutationID,
              reference.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(command)),
              reference.beginPostimageIdentity == target,
              reference.beginPostimageRevision == resultingTargetRevision,
              reference.committedAt == committedAt else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tag, attempt, workflowReceiptReference, timeZoneReceiptReference
    }
    private enum Tag: String, Codable {
        case notBegun = "NOT_BEGUN", prepared = "PREPARED", bound = "BOUND"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        let allowed: Set<String>
        switch tag {
        case .notBegun: allowed = ["tag"]
        case .prepared: allowed = ["tag", "attempt"]
        case .bound: allowed = ["tag", "attempt", "workflowReceiptReference", "timeZoneReceiptReference"]
        }
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: allowed)
        switch tag {
        case .notBegun: self = .notBegun
        case .prepared:
            self = .prepared(attempt: try c.decode(CheckRunnerFrozenBeginAttemptV1.self, forKey: .attempt))
        case .bound:
            self = .bound(attempt: try c.decode(CheckRunnerFrozenBeginAttemptV1.self, forKey: .attempt),
                workflowReceiptReference: try c.decode(CheckRunnerBeginReceiptReferenceV1.self,
                                                        forKey: .workflowReceiptReference),
                timeZoneReceiptReference: try c.decodeIfPresent(CheckRunnerBeginReceiptReferenceV1.self,
                                                               forKey: .timeZoneReceiptReference))
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notBegun: try c.encode(Tag.notBegun, forKey: .tag)
        case let .prepared(attempt):
            try c.encode(Tag.prepared, forKey: .tag)
            try c.encode(attempt, forKey: .attempt)
        case let .bound(attempt, workflow, timeZone):
            try c.encode(Tag.bound, forKey: .tag)
            try c.encode(attempt, forKey: .attempt)
            try c.encode(workflow, forKey: .workflowReceiptReference)
            try c.encodeIfPresent(timeZone, forKey: .timeZoneReceiptReference)
        }
    }
}

/// The entire editable field snapshot. Invalid raw text remains editable; only
/// the explicit prepared-outcome validator invokes the submission semantics.
struct CheckRunnerItemFieldStateV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let preflight: CheckRunnerEditablePreflightV1
    let begin: CheckRunnerBeginStateV1
    let outcome: CheckRunnerEditableOutcomeV1
    let wideContext: CheckRunnerPhotoSlotV1?
    let closeDetail: CheckRunnerPhotoSlotV1?
    let semanticAnchor: CheckRunnerItemSemanticAnchorV1

    init(preflight: CheckRunnerEditablePreflightV1, begin: CheckRunnerBeginStateV1,
         outcome: CheckRunnerEditableOutcomeV1, wideContext: CheckRunnerPhotoSlotV1?,
         closeDetail: CheckRunnerPhotoSlotV1?, semanticAnchor: CheckRunnerItemSemanticAnchorV1) throws {
        self.preflight = preflight; self.begin = begin; self.outcome = outcome
        self.wideContext = wideContext; self.closeDetail = closeDetail; self.semanticAnchor = semanticAnchor
        try validate()
    }

    func validate() throws {
        try begin.validate()
        try CheckRunnerPhotoSlotV1.validateSlots(wideContext: wideContext, closeDetail: closeDetail)
        // A photo child targets the exact workflow created by Begin. Before its
        // original receipt is bound there is no parent-owned child to reference.
        if begin.workflowReceiptReference == nil {
            guard wideContext == nil, closeDetail == nil else { throw FieldDraftFailureV1.missingReceipt }
        }
    }

    func validate(source: CheckRunnerRoundItemSourceV1) throws {
        try validate()
        try begin.validate(source: source)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case preflight, begin, outcome, wideContext, closeDetail, semanticAnchor
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(preflight: c.decode(CheckRunnerEditablePreflightV1.self, forKey: .preflight),
            begin: c.decode(CheckRunnerBeginStateV1.self, forKey: .begin),
            outcome: c.decode(CheckRunnerEditableOutcomeV1.self, forKey: .outcome),
            wideContext: c.decodeIfPresent(CheckRunnerPhotoSlotV1.self, forKey: .wideContext),
            closeDetail: c.decodeIfPresent(CheckRunnerPhotoSlotV1.self, forKey: .closeDetail),
            semanticAnchor: c.decode(CheckRunnerItemSemanticAnchorV1.self, forKey: .semanticAnchor))
    }
}

/// Exact portable equivalents of the incumbent finalizer's identifiers.
/// The existing issue in a recheck is deliberately distinct from newly minted IDs.
struct CheckRunnerFinalizationIdentifiersV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let mutationID: UUID
    let packetID: UUID
    let stableRootID: UUID
    let reportID: UUID
    let issueID: UUID?
    let newIssueID: UUID?

    init(_ value: FinalizationIdentifiers) throws {
        mutationID = value.mutationID; packetID = value.packetID; stableRootID = value.stableRootID
        reportID = value.reportID; issueID = value.issueID; newIssueID = value.newIssueID
        try validate()
    }

    var finalizationIdentifiers: FinalizationIdentifiers {
        .init(mutationID: mutationID, packetID: packetID, stableRootID: stableRootID,
              reportID: reportID, issueID: issueID, newIssueID: newIssueID)
    }

    func validate() throws {
        let ids = [mutationID, packetID, stableRootID, reportID] + [issueID, newIssueID].compactMap { $0 }
        try ids.forEach(FieldDraftValidationV1.id)
        guard Set(ids).count == ids.count else { throw FieldDraftFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mutationID, packetID, stableRootID, reportID, issueID, newIssueID
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(.init(mutationID: c.decode(UUID.self, forKey: .mutationID),
            packetID: c.decode(UUID.self, forKey: .packetID),
            stableRootID: c.decode(UUID.self, forKey: .stableRootID),
            reportID: c.decode(UUID.self, forKey: .reportID),
            issueID: c.decodeIfPresent(UUID.self, forKey: .issueID),
            newIssueID: c.decodeIfPresent(UUID.self, forKey: .newIssueID)))
    }
}

/// Inputs frozen before COMMITTING. No plan, saga, payload or output digest is
/// stored here: those depend on the enclosing durable checkpoint and real effect.
struct CheckRunnerFinalizationAttemptInputsV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let normalizedOutcome: CheckRunnerOutcomeSnapshotV1
    let identifiers: CheckRunnerFinalizationIdentifiersV1
    let completedAt: Date
    let snapshotCreatedAt: Date
    let sourceApp: SourceAppSnapshotV1
    let expectedWorkflowRecordRevision: UInt64
    let fieldDraftPlanID: UUID
    let preparedSagaID: UUID
    let contentPromotedSagaID: UUID
    let targetCommittedSagaID: UUID
    let draftRetirePendingSagaID: UUID
    let draftRetiredSagaID: UUID
    let preparedSagaMutationID: MutationIDV1
    let contentPromotedSagaMutationID: MutationIDV1
    let targetCommittedSagaMutationID: MutationIDV1
    let draftRetirePendingSagaMutationID: MutationIDV1
    let terminalBundleMutationID: MutationIDV1
    let commitReceiptID: UUID
    let preparedSagaUpdatedAt: Date
    let contentPromotedSagaUpdatedAt: Date
    let targetCommittedSagaUpdatedAt: Date
    let draftRetirePendingSagaUpdatedAt: Date
    let draftRetiredSagaUpdatedAt: Date
    let terminalCheckpointUpdatedAt: Date

    init(normalizedOutcome: CheckRunnerOutcomeSnapshotV1,
         identifiers: CheckRunnerFinalizationIdentifiersV1, completedAt: Date, snapshotCreatedAt: Date,
         sourceApp: SourceAppSnapshotV1, expectedWorkflowRecordRevision: UInt64,
         fieldDraftPlanID: UUID, preparedSagaID: UUID, contentPromotedSagaID: UUID,
         targetCommittedSagaID: UUID, draftRetirePendingSagaID: UUID, draftRetiredSagaID: UUID,
         preparedSagaMutationID: MutationIDV1, contentPromotedSagaMutationID: MutationIDV1,
         targetCommittedSagaMutationID: MutationIDV1, draftRetirePendingSagaMutationID: MutationIDV1,
         terminalBundleMutationID: MutationIDV1, commitReceiptID: UUID,
         preparedSagaUpdatedAt: Date, contentPromotedSagaUpdatedAt: Date,
         targetCommittedSagaUpdatedAt: Date, draftRetirePendingSagaUpdatedAt: Date,
         draftRetiredSagaUpdatedAt: Date, terminalCheckpointUpdatedAt: Date) throws {
        self.normalizedOutcome = normalizedOutcome; self.identifiers = identifiers
        self.completedAt = completedAt; self.snapshotCreatedAt = snapshotCreatedAt; self.sourceApp = sourceApp
        self.expectedWorkflowRecordRevision = expectedWorkflowRecordRevision
        self.fieldDraftPlanID = fieldDraftPlanID; self.preparedSagaID = preparedSagaID
        self.contentPromotedSagaID = contentPromotedSagaID; self.targetCommittedSagaID = targetCommittedSagaID
        self.draftRetirePendingSagaID = draftRetirePendingSagaID; self.draftRetiredSagaID = draftRetiredSagaID
        self.preparedSagaMutationID = preparedSagaMutationID
        self.contentPromotedSagaMutationID = contentPromotedSagaMutationID
        self.targetCommittedSagaMutationID = targetCommittedSagaMutationID
        self.draftRetirePendingSagaMutationID = draftRetirePendingSagaMutationID
        self.terminalBundleMutationID = terminalBundleMutationID; self.commitReceiptID = commitReceiptID
        self.preparedSagaUpdatedAt = preparedSagaUpdatedAt
        self.contentPromotedSagaUpdatedAt = contentPromotedSagaUpdatedAt
        self.targetCommittedSagaUpdatedAt = targetCommittedSagaUpdatedAt
        self.draftRetirePendingSagaUpdatedAt = draftRetirePendingSagaUpdatedAt
        self.draftRetiredSagaUpdatedAt = draftRetiredSagaUpdatedAt
        self.terminalCheckpointUpdatedAt = terminalCheckpointUpdatedAt
        try validate()
    }

    private var operationalIDs: [UUID] {
        [fieldDraftPlanID, preparedSagaID, contentPromotedSagaID, targetCommittedSagaID,
         draftRetirePendingSagaID, draftRetiredSagaID, preparedSagaMutationID.rawValue,
         contentPromotedSagaMutationID.rawValue, targetCommittedSagaMutationID.rawValue,
         draftRetirePendingSagaMutationID.rawValue, terminalBundleMutationID.rawValue, commitReceiptID]
    }

    func validate() throws {
        try identifiers.validate()
        let ids = operationalIDs + [identifiers.mutationID, identifiers.packetID,
            identifiers.stableRootID, identifiers.reportID] + [identifiers.newIssueID].compactMap { $0 }
        try ids.forEach(FieldDraftValidationV1.id)
        let times = [completedAt, snapshotCreatedAt, preparedSagaUpdatedAt, contentPromotedSagaUpdatedAt,
            targetCommittedSagaUpdatedAt, draftRetirePendingSagaUpdatedAt,
            draftRetiredSagaUpdatedAt, terminalCheckpointUpdatedAt]
        try times.forEach(FieldDraftValidationV1.instant)
        guard Set(ids).count == ids.count,
              expectedWorkflowRecordRevision > 0, expectedWorkflowRecordRevision < UInt64.max,
              zip(times, times.dropFirst()).allSatisfy({ pair in pair.0 <= pair.1 }) else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    /// Stage, identifier, media and time linkage only. Child receipt/evidence
    /// times and the live finalizer's affected identities require their real owners.
    func validate(source: CheckRunnerRoundItemSourceV1, field: CheckRunnerItemFieldStateV1) throws {
        try validate(); try field.validate(source: source)
        guard case let .bound(begin, workflow, _) = field.begin,
              completedAt >= begin.recordCommand.startedAt,
              expectedWorkflowRecordRevision >= workflow.beginPostimageRevision else {
            throw FieldDraftFailureV1.missingReceipt
        }
        let newlyAllocatedIssueID: UUID?
        switch (source.requestedEntry, normalizedOutcome.selection) {
        case (.check, .noVisibleIssue), (.check, .couldNotVerify):
            guard identifiers.issueID == nil, identifiers.newIssueID == nil else {
                throw FieldDraftFailureV1.invalidValue
            }
            newlyAllocatedIssueID = nil
        case (.check, .visibleIssue):
            guard let issueID = identifiers.issueID, identifiers.newIssueID == nil else {
                throw FieldDraftFailureV1.invalidValue
            }
            newlyAllocatedIssueID = issueID
        case let (.recheck(issueID), .resolved), let (.recheck(issueID), .issueStillVisible),
             let (.recheck(issueID), .couldNotVerify):
            guard identifiers.issueID == issueID, identifiers.newIssueID == nil else {
                throw FieldDraftFailureV1.invalidValue
            }
            newlyAllocatedIssueID = nil
        case let (.recheck(issueID), .originalResolvedDifferentIssue):
            guard identifiers.issueID == issueID, let newIssueID = identifiers.newIssueID else {
                throw FieldDraftFailureV1.invalidValue
            }
            newlyAllocatedIssueID = newIssueID
        default: throw FieldDraftFailureV1.invalidValue
        }
        let ids = operationalIDs + [begin.recordCommand.recordID, identifiers.mutationID,
            identifiers.packetID, identifiers.stableRootID, identifiers.reportID]
            + [newlyAllocatedIssueID, begin.timeZone?.mutationID.rawValue].compactMap { $0 }
        guard Set(ids).count == ids.count else { throw FieldDraftFailureV1.invalidValue }
        // An inherited recheck issue is excluded from allocation, but it cannot
        // impersonate an operational row or one of this attempt's new outputs.
        if let inheritedIssueID = source.requestedEntry.issueID {
            guard !ids.contains(inheritedIssueID) else { throw FieldDraftFailureV1.invalidValue }
        }
        let slots = [field.wideContext, field.closeDetail].compactMap { $0 }
        guard slots.allSatisfy({ if case .committed = $0 { return true }; return false }) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        if case .couldNotVerify = normalizedOutcome.selection { return }
        guard field.wideContext != nil, field.closeDetail != nil else {
            throw FieldDraftFailureV1.missingContent
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let a = try? FieldDraftCanonicalCodecV1.encode(lhs),
              let b = try? FieldDraftCanonicalCodecV1.encode(rhs) else { return false }
        return a == b
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case normalizedOutcome, identifiers, completedAt, snapshotCreatedAt, sourceApp
        case expectedWorkflowRecordRevision, fieldDraftPlanID, preparedSagaID, contentPromotedSagaID
        case targetCommittedSagaID, draftRetirePendingSagaID, draftRetiredSagaID
        case preparedSagaMutationID, contentPromotedSagaMutationID, targetCommittedSagaMutationID
        case draftRetirePendingSagaMutationID, terminalBundleMutationID, commitReceiptID
        case preparedSagaUpdatedAt, contentPromotedSagaUpdatedAt, targetCommittedSagaUpdatedAt
        case draftRetirePendingSagaUpdatedAt, draftRetiredSagaUpdatedAt, terminalCheckpointUpdatedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let app = try c.superDecoder(forKey: .sourceApp)
        try ClosedContractDecodingV1.rejectUnknownKeys(app, allowed: ["build", "version"])
        try self.init(normalizedOutcome: c.decode(CheckRunnerOutcomeSnapshotV1.self, forKey: .normalizedOutcome),
            identifiers: c.decode(CheckRunnerFinalizationIdentifiersV1.self, forKey: .identifiers),
            completedAt: c.decode(Date.self, forKey: .completedAt),
            snapshotCreatedAt: c.decode(Date.self, forKey: .snapshotCreatedAt),
            sourceApp: SourceAppSnapshotV1(from: app),
            expectedWorkflowRecordRevision: c.decode(UInt64.self, forKey: .expectedWorkflowRecordRevision),
            fieldDraftPlanID: c.decode(UUID.self, forKey: .fieldDraftPlanID),
            preparedSagaID: c.decode(UUID.self, forKey: .preparedSagaID),
            contentPromotedSagaID: c.decode(UUID.self, forKey: .contentPromotedSagaID),
            targetCommittedSagaID: c.decode(UUID.self, forKey: .targetCommittedSagaID),
            draftRetirePendingSagaID: c.decode(UUID.self, forKey: .draftRetirePendingSagaID),
            draftRetiredSagaID: c.decode(UUID.self, forKey: .draftRetiredSagaID),
            preparedSagaMutationID: c.decode(MutationIDV1.self, forKey: .preparedSagaMutationID),
            contentPromotedSagaMutationID: c.decode(MutationIDV1.self, forKey: .contentPromotedSagaMutationID),
            targetCommittedSagaMutationID: c.decode(MutationIDV1.self, forKey: .targetCommittedSagaMutationID),
            draftRetirePendingSagaMutationID: c.decode(MutationIDV1.self, forKey: .draftRetirePendingSagaMutationID),
            terminalBundleMutationID: c.decode(MutationIDV1.self, forKey: .terminalBundleMutationID),
            commitReceiptID: c.decode(UUID.self, forKey: .commitReceiptID),
            preparedSagaUpdatedAt: c.decode(Date.self, forKey: .preparedSagaUpdatedAt),
            contentPromotedSagaUpdatedAt: c.decode(Date.self, forKey: .contentPromotedSagaUpdatedAt),
            targetCommittedSagaUpdatedAt: c.decode(Date.self, forKey: .targetCommittedSagaUpdatedAt),
            draftRetirePendingSagaUpdatedAt: c.decode(Date.self, forKey: .draftRetirePendingSagaUpdatedAt),
            draftRetiredSagaUpdatedAt: c.decode(Date.self, forKey: .draftRetiredSagaUpdatedAt),
            terminalCheckpointUpdatedAt: c.decode(Date.self, forKey: .terminalCheckpointUpdatedAt))
    }
}

/// Complete pure parent payload grammar. It has no allocated codec release,
/// registration, checkpoint constructor, writer or target execution authority.
struct CheckRunnerItemDraftPayloadV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    static let schemaVersion = 1
    static let maximumPayloadBytes = 2 * 1_024 * 1_024
    enum Phase: String, Codable { case editing = "EDITING", preparedFinalization = "PREPARED_FINALIZATION" }

    let phase: Phase
    let source: CheckRunnerRoundItemSourceV1
    let field: CheckRunnerItemFieldStateV1
    let finalizationAttempt: CheckRunnerFinalizationAttemptInputsV1?

    init(editing source: CheckRunnerRoundItemSourceV1, field: CheckRunnerItemFieldStateV1) throws {
        phase = .editing; self.source = source; self.field = field; finalizationAttempt = nil
        try validate()
    }

    init(prepared source: CheckRunnerRoundItemSourceV1, field: CheckRunnerItemFieldStateV1,
         attempt: CheckRunnerFinalizationAttemptInputsV1) throws {
        phase = .preparedFinalization; self.source = source; self.field = field; finalizationAttempt = attempt
        try validate()
    }

    func validate() throws {
        try source.validate(); try field.validate(source: source)
        switch phase {
        case .editing:
            guard finalizationAttempt == nil else { throw FieldDraftFailureV1.invalidValue }
        case .preparedFinalization:
            guard let finalizationAttempt else { throw FieldDraftFailureV1.invalidValue }
            try finalizationAttempt.validate(source: source, field: field)
        }
        // Encoding is a direct projection of immutable fields and does not call
        // this validator recursively. No nested generic 512-byte text cap applies.
        guard try FieldDraftCanonicalCodecV1.encode(self).count <= Self.maximumPayloadBytes else {
            throw FieldDraftFailureV1.limitExceeded
        }
    }

    /// Proves the prepared result against the actual package resolver and raw
    /// editor. Even this proof does not replace source/target/child receipt reads.
    func validatePreparedOutcome(signPack: SignPack,
        activeLifecycleProfile: () throws -> WorkspacePackageLifecycleProfileV1) throws {
        try validate()
        guard let finalizationAttempt, phase == .preparedFinalization,
              source.legacyPackageIdentity.matches(signPack) else {
            throw FieldDraftFailureV1.invalidValue
        }
        let profile = try activeLifecycleProfile()
        guard profile.release == source.legacyPackageIdentity, profile.package == signPack else {
            throw FieldDraftFailureV1.digestMismatch
        }
        let release = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: signPack, stage: source.requestedEntry.stage)
        let reference = try RoundPackageReleaseReferenceV1(packageReleaseID: release.packageReleaseID,
            packageID: release.packageID, packageContentVersion: release.packageContentVersion,
            packageSHA256: release.packageSHA256, workflowSHA256: release.workflowSHA256)
        guard source.packageRelease == reference else {
            throw FieldDraftFailureV1.digestMismatch
        }
        let expected = try CheckRunnerOutcomeSnapshotV1.prepare(editor: field.outcome,
            stage: source.requestedEntry.stage, signPack: signPack, activeLifecycleProfile: { profile })
        guard expected == finalizationAttempt.normalizedOutcome else {
            throw FieldDraftFailureV1.digestMismatch
        }
        _ = try finalizationAttempt.normalizedOutcome.resolve(stage: source.requestedEntry.stage,
            signPack: signPack, activeLifecycleProfile: { profile })
    }

    static func encode(_ value: Self) throws -> Data {
        try value.validate()
        let data = try FieldDraftCanonicalCodecV1.encode(value)
        _ = try FieldDraftCanonicalCodecV1.decode(Self.self, from: data)
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }
        return try FieldDraftCanonicalCodecV1.decode(Self.self, from: data)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let a = try? FieldDraftCanonicalCodecV1.encode(lhs),
              let b = try? FieldDraftCanonicalCodecV1.encode(rhs) else { return false }
        return a == b
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, phase, source, field, finalizationAttempt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw FieldDraftFailureV1.incompatibleVersion
        }
        let phase = try c.decode(Phase.self, forKey: .phase)
        var allowed: Set<String> = ["schemaVersion", "phase", "source", "field"]
        if phase == .preparedFinalization { allowed.insert("finalizationAttempt") }
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: allowed)
        let source = try c.decode(CheckRunnerRoundItemSourceV1.self, forKey: .source)
        let field = try c.decode(CheckRunnerItemFieldStateV1.self, forKey: .field)
        switch phase {
        case .editing: try self.init(editing: source, field: field)
        case .preparedFinalization:
            try self.init(prepared: source, field: field,
                attempt: c.decode(CheckRunnerFinalizationAttemptInputsV1.self, forKey: .finalizationAttempt))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersion, forKey: .schemaVersion)
        try c.encode(phase, forKey: .phase)
        try c.encode(source, forKey: .source)
        try c.encode(field, forKey: .field)
        try c.encodeIfPresent(finalizationAttempt, forKey: .finalizationAttempt)
    }
}
