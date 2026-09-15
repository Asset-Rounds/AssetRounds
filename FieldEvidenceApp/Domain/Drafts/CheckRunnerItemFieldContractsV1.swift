import Foundation

/// Stable navigation values for the eventual parent checkpoint. No focus,
/// keyboard, camera session or transient task state belongs in this value.
enum CheckRunnerItemSemanticAnchorV1: String, Codable, CaseIterable, Sendable {
    case preflight = "PREFLIGHT"
    case wideContext = "WIDE_CONTEXT"
    case closeDetail = "CLOSE_DETAIL"
    case outcome = "OUTCOME"
    case review = "REVIEW"

    func resumeAnchor(assetID: UUID) throws -> DraftResumeAnchorV1 {
        try FieldDraftValidationV1.id(assetID)
        return try .init(sectionID: rawValue.lowercased(),
                         selectedStableID: assetID.uuidString.lowercased())
    }
}

/// A closed prepared result. Construction and inverse validation use the same
/// resolver as the live screen. The raw editable outcome remains a separate value.
enum CheckRunnerOutcomeSnapshotV1: Codable, Equatable, Sendable {
    case noVisibleIssue(outcomeKey: String, outcomeDisplay: String)
    case visibleIssue(outcomeKey: String, outcomeDisplay: String,
                      issueLabelKey: String, issueLabelDisplay: String)
    case couldNotVerify(outcomeKey: String, outcomeDisplay: String,
                        reasonKey: String, reasonDisplay: String,
                        reasonRegistryVersion: String, note: String?)
    case resolved(outcomeKey: String, outcomeDisplay: String, note: String?)
    case issueStillVisible(outcomeKey: String, outcomeDisplay: String, note: String?)
    case originalResolvedDifferentIssue(outcomeKey: String, outcomeDisplay: String,
                                        issueLabelKey: String, issueLabelDisplay: String,
                                        note: String?)

    init(selection: CheckOutcomeSelection, stage: WorkflowStage, signPack: SignPack,
         activeLifecycleProfile: () throws -> WorkspacePackageLifecycleProfileV1) throws {
        try Self.validateStage(selection, stage: stage)
        let resolved = try CheckRunnerOutcomeResolverV1.resolve(
            selection, signPack: signPack, activeLifecycleProfile: activeLifecycleProfile)
        try self.init(resolved: resolved, reasonRegistryVersion: signPack.couldNotVerifyReasons.version)
    }

    static func prepare(editor: CheckRunnerEditableOutcomeV1, stage: WorkflowStage,
                        signPack: SignPack,
                        activeLifecycleProfile: () throws -> WorkspacePackageLifecycleProfileV1) throws
        -> Self {
        guard let storedSelection = editor.selection else { throw FieldDraftFailureV1.invalidValue }
        let selection: CheckOutcomeSelection
        switch storedSelection.liveSelection {
        case let .couldNotVerify(reasonKey, _):
            selection = .couldNotVerify(reasonKey: reasonKey,
                note: try preparedNote(editor.couldNotVerifyNote))
        case .resolved:
            selection = .resolved(note: try preparedNote(editor.recheckNote))
        case .issueStillVisible:
            selection = .issueStillVisible(note: try preparedNote(editor.recheckNote))
        case let .originalResolvedDifferentIssue(labelKey, _):
            selection = .originalResolvedDifferentIssue(labelKey: labelKey,
                note: try preparedNote(editor.recheckNote))
        case .noVisibleIssue, .visibleIssue:
            selection = storedSelection.liveSelection
        }
        return try Self(selection: selection, stage: stage, signPack: signPack,
                        activeLifecycleProfile: activeLifecycleProfile)
    }

    /// Decoded fields are claims until this exact published-profile inverse passes.
    /// A matching result still supplies no workflow, receipt or finalization authority.
    func resolve(stage: WorkflowStage, signPack: SignPack,
                 activeLifecycleProfile: () throws -> WorkspacePackageLifecycleProfileV1) throws
        -> CheckRunnerResolvedOutcomeV1 {
        try Self.validateStage(selection, stage: stage)
        let resolved = try CheckRunnerOutcomeResolverV1.resolve(
            selection, signPack: signPack, activeLifecycleProfile: activeLifecycleProfile)
        let expected = try Self(resolved: resolved,
                                reasonRegistryVersion: signPack.couldNotVerifyReasons.version)
        guard self == expected else { throw FieldDraftFailureV1.digestMismatch }
        return resolved
    }

    var selection: CheckOutcomeSelection {
        switch self {
        case .noVisibleIssue: return .noVisibleIssue
        case let .visibleIssue(_, _, key, _): return .visibleIssue(labelKey: key)
        case let .couldNotVerify(_, _, key, _, _, note):
            return .couldNotVerify(reasonKey: key, note: note)
        case let .resolved(_, _, note): return .resolved(note: note)
        case let .issueStillVisible(_, _, note): return .issueStillVisible(note: note)
        case let .originalResolvedDifferentIssue(_, _, key, _, note):
            return .originalResolvedDifferentIssue(labelKey: key, note: note)
        }
    }

    private init(resolved: CheckRunnerResolvedOutcomeV1, reasonRegistryVersion: String) throws {
        switch resolved.selection {
        case .noVisibleIssue:
            self = .noVisibleIssue(outcomeKey: resolved.key, outcomeDisplay: resolved.display)
        case .visibleIssue:
            guard let label = resolved.issueLabel else { throw FieldDraftFailureV1.invalidValue }
            self = .visibleIssue(outcomeKey: resolved.key, outcomeDisplay: resolved.display,
                                 issueLabelKey: label.key, issueLabelDisplay: label.display)
        case .couldNotVerify:
            guard let reason = resolved.couldNotVerify else { throw FieldDraftFailureV1.invalidValue }
            self = .couldNotVerify(outcomeKey: resolved.key, outcomeDisplay: resolved.display,
                reasonKey: reason.key, reasonDisplay: reason.display,
                reasonRegistryVersion: reasonRegistryVersion, note: resolved.note)
        case .resolved:
            self = .resolved(outcomeKey: resolved.key, outcomeDisplay: resolved.display,
                             note: resolved.note)
        case .issueStillVisible:
            self = .issueStillVisible(outcomeKey: resolved.key, outcomeDisplay: resolved.display,
                                      note: resolved.note)
        case .originalResolvedDifferentIssue:
            guard let label = resolved.issueLabel else { throw FieldDraftFailureV1.invalidValue }
            self = .originalResolvedDifferentIssue(outcomeKey: resolved.key,
                outcomeDisplay: resolved.display, issueLabelKey: label.key,
                issueLabelDisplay: label.display, note: resolved.note)
        }
    }

    private static func preparedNote(_ raw: String) throws -> String? {
        switch CheckRunnerOutcomeResolverV1.projectEditableNote(raw) {
        case .none: return nil
        case let .value(value): return value
        case .invalid: throw CheckRunnerCoordinatorError.invalidLineage
        }
    }

    private static func validateStage(_ selection: CheckOutcomeSelection, stage: WorkflowStage) throws {
        switch (stage, selection) {
        case (.check, .noVisibleIssue), (.check, .visibleIssue), (.check, .couldNotVerify),
             (.recheck, .resolved), (.recheck, .issueStillVisible),
             (.recheck, .originalResolvedDifferentIssue), (.recheck, .couldNotVerify): return
        default: throw FieldDraftFailureV1.invalidValue
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = try? FieldDraftCanonicalCodecV1.encode(lhs),
              let right = try? FieldDraftCanonicalCodecV1.encode(rhs) else { return false }
        return left == right
    }

    private enum CodingKeys: String, CodingKey {
        case tag, outcomeKey, outcomeDisplay, issueLabelKey, issueLabelDisplay
        case reasonKey, reasonDisplay, reasonRegistryVersion, note
    }
    private enum Tag: String, Codable {
        case noVisibleIssue = "NO_VISIBLE_ISSUE", visibleIssue = "VISIBLE_ISSUE"
        case couldNotVerify = "COULD_NOT_VERIFY", resolved = "RESOLVED"
        case issueStillVisible = "ISSUE_STILL_VISIBLE"
        case originalResolvedDifferentIssue = "ORIGINAL_RESOLVED_DIFFERENT_ISSUE"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        var allowed: Set<String> = ["tag", "outcomeKey", "outcomeDisplay"]
        switch tag {
        case .noVisibleIssue: break
        case .visibleIssue: allowed.formUnion(["issueLabelKey", "issueLabelDisplay"])
        case .couldNotVerify: allowed.formUnion(["reasonKey", "reasonDisplay", "reasonRegistryVersion", "note"])
        case .resolved, .issueStillVisible: allowed.insert("note")
        case .originalResolvedDifferentIssue: allowed.formUnion(["issueLabelKey", "issueLabelDisplay", "note"])
        }
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: allowed)
        let key = try c.decode(String.self, forKey: .outcomeKey)
        let display = try c.decode(String.self, forKey: .outcomeDisplay)
        switch tag {
        case .noVisibleIssue:
            self = .noVisibleIssue(outcomeKey: key, outcomeDisplay: display)
        case .visibleIssue:
            self = .visibleIssue(outcomeKey: key, outcomeDisplay: display,
                issueLabelKey: try c.decode(String.self, forKey: .issueLabelKey),
                issueLabelDisplay: try c.decode(String.self, forKey: .issueLabelDisplay))
        case .couldNotVerify:
            self = .couldNotVerify(outcomeKey: key, outcomeDisplay: display,
                reasonKey: try c.decode(String.self, forKey: .reasonKey),
                reasonDisplay: try c.decode(String.self, forKey: .reasonDisplay),
                reasonRegistryVersion: try c.decode(String.self, forKey: .reasonRegistryVersion),
                note: try c.decodeIfPresent(String.self, forKey: .note))
        case .resolved:
            self = .resolved(outcomeKey: key, outcomeDisplay: display,
                note: try c.decodeIfPresent(String.self, forKey: .note))
        case .issueStillVisible:
            self = .issueStillVisible(outcomeKey: key, outcomeDisplay: display,
                note: try c.decodeIfPresent(String.self, forKey: .note))
        case .originalResolvedDifferentIssue:
            self = .originalResolvedDifferentIssue(outcomeKey: key, outcomeDisplay: display,
                issueLabelKey: try c.decode(String.self, forKey: .issueLabelKey),
                issueLabelDisplay: try c.decode(String.self, forKey: .issueLabelDisplay),
                note: try c.decodeIfPresent(String.self, forKey: .note))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let tag: Tag
        let key: String
        let display: String
        switch self {
        case let .noVisibleIssue(outcomeKey, outcomeDisplay):
            tag = .noVisibleIssue; key = outcomeKey; display = outcomeDisplay
        case let .visibleIssue(outcomeKey, outcomeDisplay, labelKey, labelDisplay):
            tag = .visibleIssue; key = outcomeKey; display = outcomeDisplay
            try c.encode(labelKey, forKey: .issueLabelKey)
            try c.encode(labelDisplay, forKey: .issueLabelDisplay)
        case let .couldNotVerify(outcomeKey, outcomeDisplay, reasonKey, reasonDisplay, version, note):
            tag = .couldNotVerify; key = outcomeKey; display = outcomeDisplay
            try c.encode(reasonKey, forKey: .reasonKey)
            try c.encode(reasonDisplay, forKey: .reasonDisplay)
            try c.encode(version, forKey: .reasonRegistryVersion)
            try c.encodeIfPresent(note, forKey: .note)
        case let .resolved(outcomeKey, outcomeDisplay, note):
            tag = .resolved; key = outcomeKey; display = outcomeDisplay
            try c.encodeIfPresent(note, forKey: .note)
        case let .issueStillVisible(outcomeKey, outcomeDisplay, note):
            tag = .issueStillVisible; key = outcomeKey; display = outcomeDisplay
            try c.encodeIfPresent(note, forKey: .note)
        case let .originalResolvedDifferentIssue(outcomeKey, outcomeDisplay, labelKey, labelDisplay, note):
            tag = .originalResolvedDifferentIssue; key = outcomeKey; display = outcomeDisplay
            try c.encode(labelKey, forKey: .issueLabelKey)
            try c.encode(labelDisplay, forKey: .issueLabelDisplay)
            try c.encodeIfPresent(note, forKey: .note)
        }
        try c.encode(tag, forKey: .tag)
        try c.encode(key, forKey: .outcomeKey)
        try c.encode(display, forKey: .outcomeDisplay)
    }
}

/// Closed references only. A COMMITTED tag is a claim whose child checkpoint,
/// commit receipt and target receipt still require the owning journal's proof.
enum CheckRunnerPhotoSlotV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    case pending(childDraftID: UUID, captureStep: WorkflowDraftStep, purposeKey: String)
    case committed(childDraftID: UUID, captureStep: WorkflowDraftStep, purposeKey: String,
                   committedChildDraftRevision: UInt64, committedChildCheckpointSHA256: String,
                   childCommitReceiptID: UUID, childCommitReceiptSHA256: String,
                   evidenceID: UUID, targetMutationID: MutationIDV1, targetReceiptSHA256: String)

    var childDraftID: UUID {
        switch self { case let .pending(id, _, _), let .committed(id, _, _, _, _, _, _, _, _, _): return id }
    }
    var captureStep: WorkflowDraftStep {
        switch self { case let .pending(_, step, _), let .committed(_, step, _, _, _, _, _, _, _, _): return step }
    }
    var purposeKey: String {
        switch self { case let .pending(_, _, purpose), let .committed(_, _, purpose, _, _, _, _, _, _, _): return purpose }
    }
    var evidenceID: UUID? {
        switch self { case .pending: return nil; case let .committed(_, _, _, _, _, _, _, id, _, _): return id }
    }

    func validate() throws {
        try FieldDraftValidationV1.id(childDraftID)
        let purpose: String
        switch captureStep {
        case .wide: purpose = "wide_context"
        case .close: purpose = "close_detail"
        default: throw FieldDraftFailureV1.invalidValue
        }
        guard purposeKey == purpose else { throw FieldDraftFailureV1.invalidValue }
        if case let .committed(_, _, _, revision, checkpointSHA, receiptID, receiptSHA,
                               evidenceID, targetMutationID, targetReceiptSHA) = self {
            try FieldDraftValidationV1.revision(revision)
            try FieldDraftValidationV1.id(receiptID)
            try FieldDraftValidationV1.id(evidenceID)
            try FieldDraftValidationV1.digest(checkpointSHA)
            try FieldDraftValidationV1.digest(receiptSHA)
            try FieldDraftValidationV1.digest(targetReceiptSHA)
            guard evidenceID != childDraftID, targetMutationID.rawValue == evidenceID else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
    }

    /// Relationship only; this must run after the actual child/target proof.
    func validateReplacement(of pending: Self) throws {
        try validate(); try pending.validate()
        guard case .committed = self, case .pending = pending,
              childDraftID == pending.childDraftID, captureStep == pending.captureStep,
              purposeKey == pending.purposeKey else { throw FieldDraftFailureV1.invalidValue }
    }

    static func validateSlots(wideContext: Self?, closeDetail: Self?) throws {
        var ids: [UUID] = []
        for (slot, step) in [(wideContext, WorkflowDraftStep.wide), (closeDetail, .close)] {
            guard let slot else { continue }
            try slot.validate()
            guard slot.captureStep == step else { throw FieldDraftFailureV1.invalidValue }
            ids.append(slot.childDraftID)
            if let evidenceID = slot.evidenceID { ids.append(evidenceID) }
        }
        guard Set(ids).count == ids.count else { throw FieldDraftFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case tag, childDraftID, captureStep, purposeKey, committedChildDraftRevision
        case committedChildCheckpointSHA256, childCommitReceiptID, childCommitReceiptSHA256
        case evidenceID, targetMutationID, targetReceiptSHA256
    }
    private enum Tag: String, Codable { case pending = "PENDING", committed = "COMMITTED" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: tag == .pending
            ? ["tag", "childDraftID", "captureStep", "purposeKey"]
            : Set(CodingKeys.allCases.map(\.rawValue)))
        let id = try c.decode(UUID.self, forKey: .childDraftID)
        let step = try c.decode(WorkflowDraftStep.self, forKey: .captureStep)
        let purpose = try c.decode(String.self, forKey: .purposeKey)
        switch tag {
        case .pending: self = .pending(childDraftID: id, captureStep: step, purposeKey: purpose)
        case .committed:
            self = .committed(childDraftID: id, captureStep: step, purposeKey: purpose,
                committedChildDraftRevision: try c.decode(UInt64.self, forKey: .committedChildDraftRevision),
                committedChildCheckpointSHA256: try c.decode(String.self, forKey: .committedChildCheckpointSHA256),
                childCommitReceiptID: try c.decode(UUID.self, forKey: .childCommitReceiptID),
                childCommitReceiptSHA256: try c.decode(String.self, forKey: .childCommitReceiptSHA256),
                evidenceID: try c.decode(UUID.self, forKey: .evidenceID),
                targetMutationID: try c.decode(MutationIDV1.self, forKey: .targetMutationID),
                targetReceiptSHA256: try c.decode(String.self, forKey: .targetReceiptSHA256))
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(childDraftID, forKey: .childDraftID)
        try c.encode(captureStep, forKey: .captureStep)
        try c.encode(purposeKey, forKey: .purposeKey)
        switch self {
        case .pending: try c.encode(Tag.pending, forKey: .tag)
        case let .committed(_, _, _, revision, checkpointSHA, receiptID, receiptSHA,
                             evidenceID, targetMutationID, targetReceiptSHA):
            try c.encode(Tag.committed, forKey: .tag)
            try c.encode(revision, forKey: .committedChildDraftRevision)
            try c.encode(checkpointSHA, forKey: .committedChildCheckpointSHA256)
            try c.encode(receiptID, forKey: .childCommitReceiptID)
            try c.encode(receiptSHA, forKey: .childCommitReceiptSHA256)
            try c.encode(evidenceID, forKey: .evidenceID)
            try c.encode(targetMutationID, forKey: .targetMutationID)
            try c.encode(targetReceiptSHA, forKey: .targetReceiptSHA256)
        }
    }
}
