import Foundation

enum MyDayPlanningPayloadPhaseV1: String, Codable, CaseIterable, Sendable {
    case editing = "EDITING"
    case preparedCommit = "PREPARED_COMMIT"
}

struct MyDayPlanningConfirmedContextV1: Codable, Equatable, Sendable {
    let key: MyDayKeyV1
    let recordedBy: ActorSnapshotV1
    let keyWasExplicitlyConfirmed: Bool
    let recordedByWasExplicitlySelectedOrCaptured: Bool

    init(
        key: MyDayKeyV1,
        recordedBy: ActorSnapshotV1,
        keyWasExplicitlyConfirmed: Bool,
        recordedByWasExplicitlySelectedOrCaptured: Bool
    ) throws {
        self.key = key
        self.recordedBy = recordedBy
        self.keyWasExplicitlyConfirmed = keyWasExplicitlyConfirmed
        self.recordedByWasExplicitlySelectedOrCaptured = recordedByWasExplicitlySelectedOrCaptured
        try validate()
    }

    func validate() throws {
        try key.validate()
        try recordedBy.validate()
        try MyDayLimitsV1.millisecondInstant(recordedBy.capturedAt)
        guard recordedBy.workspaceID == key.workspaceID,
              recordedBy.responsibility == .recordedBy,
              keyWasExplicitlyConfirmed,
              recordedByWasExplicitlySelectedOrCaptured else {
            throw FieldDraftFailureV1.invalidValue
        }
    }
}

enum MyDayPlanningEditingIntentKindV1: String, Codable, CaseIterable, Sendable {
    case plan = "PLAN"
    case carryover = "CARRYOVER"
}

enum MyDayPlanningEditingIntentV1: Equatable, Sendable {
    case plan(draft: MyDayPlanDraftV1, predecessor: MyDayPlanV1?)
    case carryover(
        sourcePlan: MyDayPlanReferenceV1,
        selectedMembershipIDs: [UUID],
        targetKey: MyDayKeyV1,
        targetPredecessor: MyDayPlanReferenceV1?
    )

    var targetKey: MyDayKeyV1 {
        switch self {
        case .plan(let draft, _): return draft.key
        case .carryover(_, _, let targetKey, _): return targetKey
        }
    }

    var targetBaseRevision: UInt64 {
        switch self {
        case .plan(_, let predecessor): return predecessor?.revision ?? 0
        case .carryover(_, _, _, let targetPredecessor): return targetPredecessor?.revision ?? 0
        }
    }

    func validate() throws {
        switch self {
        case .plan(let draft, let predecessor):
            let reconstructed = try MyDayPlanDraftV1(
                key: draft.key,
                items: draft.items,
                eligibleReferences: draft.eligibleReferences
            )
            try predecessor?.validate()
            guard reconstructed == draft,
                  predecessor.map({ $0.key == draft.key }) ?? true else {
                throw FieldDraftFailureV1.invalidValue
            }
        case .carryover(
            let sourcePlan,
            let selectedMembershipIDs,
            let targetKey,
            let targetPredecessor
        ):
            try sourcePlan.validate()
            try targetKey.validate()
            try targetPredecessor?.validate()
            try selectedMembershipIDs.forEach(MyDayLimitsV1.id)
            guard sourcePlan.key.workspaceID == targetKey.workspaceID,
                  sourcePlan.key != targetKey,
                  !selectedMembershipIDs.isEmpty,
                  selectedMembershipIDs.count <= MyDayLimitsV1.maximumItems,
                  Set(selectedMembershipIDs).count == selectedMembershipIDs.count,
                  targetPredecessor.map({ $0.key == targetKey }) ?? true else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
    }
}

extension MyDayPlanningEditingIntentV1: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, draft, predecessor, sourcePlan, selectedMembershipIDs, targetKey, targetPredecessor
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let actualKeys = Set(values.allKeys.map(\.rawValue))
        switch try values.decode(MyDayPlanningEditingIntentKindV1.self, forKey: .kind) {
        case .plan:
            guard actualKeys == Set([
                CodingKeys.kind.rawValue,
                CodingKeys.draft.rawValue,
                CodingKeys.predecessor.rawValue
            ]) else { throw FieldDraftFailureV1.invalidValue }
            self = .plan(
                draft: try values.decode(MyDayPlanDraftV1.self, forKey: .draft),
                predecessor: try values.decodeIfPresent(MyDayPlanV1.self, forKey: .predecessor)
            )
        case .carryover:
            guard actualKeys == Set([
                CodingKeys.kind.rawValue,
                CodingKeys.sourcePlan.rawValue,
                CodingKeys.selectedMembershipIDs.rawValue,
                CodingKeys.targetKey.rawValue,
                CodingKeys.targetPredecessor.rawValue
            ]) else { throw FieldDraftFailureV1.invalidValue }
            self = .carryover(
                sourcePlan: try values.decode(MyDayPlanReferenceV1.self, forKey: .sourcePlan),
                selectedMembershipIDs: try values.decode([UUID].self, forKey: .selectedMembershipIDs),
                targetKey: try values.decode(MyDayKeyV1.self, forKey: .targetKey),
                targetPredecessor: try values.decodeIfPresent(
                    MyDayPlanReferenceV1.self,
                    forKey: .targetPredecessor
                )
            )
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plan(let draft, let predecessor):
            try values.encode(MyDayPlanningEditingIntentKindV1.plan, forKey: .kind)
            try values.encode(draft, forKey: .draft)
            try values.encode(predecessor, forKey: .predecessor)
        case .carryover(
            let sourcePlan,
            let selectedMembershipIDs,
            let targetKey,
            let targetPredecessor
        ):
            try values.encode(MyDayPlanningEditingIntentKindV1.carryover, forKey: .kind)
            try values.encode(sourcePlan, forKey: .sourcePlan)
            try values.encode(selectedMembershipIDs, forKey: .selectedMembershipIDs)
            try values.encode(targetKey, forKey: .targetKey)
            try values.encode(targetPredecessor, forKey: .targetPredecessor)
        }
    }
}

struct MyDayPlanningCommitAttemptInputsV1: Codable, Equatable, Sendable {
    let command: MyDayCommandV1
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

    init(
        command: MyDayCommandV1,
        fieldDraftPlanID: UUID,
        preparedSagaID: UUID,
        contentPromotedSagaID: UUID,
        targetCommittedSagaID: UUID,
        draftRetirePendingSagaID: UUID,
        draftRetiredSagaID: UUID,
        preparedSagaMutationID: MutationIDV1,
        contentPromotedSagaMutationID: MutationIDV1,
        targetCommittedSagaMutationID: MutationIDV1,
        draftRetirePendingSagaMutationID: MutationIDV1,
        terminalBundleMutationID: MutationIDV1,
        commitReceiptID: UUID,
        preparedSagaUpdatedAt: Date,
        contentPromotedSagaUpdatedAt: Date,
        targetCommittedSagaUpdatedAt: Date,
        draftRetirePendingSagaUpdatedAt: Date,
        draftRetiredSagaUpdatedAt: Date,
        terminalCheckpointUpdatedAt: Date
    ) throws {
        self.command = command
        self.fieldDraftPlanID = fieldDraftPlanID
        self.preparedSagaID = preparedSagaID
        self.contentPromotedSagaID = contentPromotedSagaID
        self.targetCommittedSagaID = targetCommittedSagaID
        self.draftRetirePendingSagaID = draftRetirePendingSagaID
        self.draftRetiredSagaID = draftRetiredSagaID
        self.preparedSagaMutationID = preparedSagaMutationID
        self.contentPromotedSagaMutationID = contentPromotedSagaMutationID
        self.targetCommittedSagaMutationID = targetCommittedSagaMutationID
        self.draftRetirePendingSagaMutationID = draftRetirePendingSagaMutationID
        self.terminalBundleMutationID = terminalBundleMutationID
        self.commitReceiptID = commitReceiptID
        self.preparedSagaUpdatedAt = preparedSagaUpdatedAt
        self.contentPromotedSagaUpdatedAt = contentPromotedSagaUpdatedAt
        self.targetCommittedSagaUpdatedAt = targetCommittedSagaUpdatedAt
        self.draftRetirePendingSagaUpdatedAt = draftRetirePendingSagaUpdatedAt
        self.draftRetiredSagaUpdatedAt = draftRetiredSagaUpdatedAt
        self.terminalCheckpointUpdatedAt = terminalCheckpointUpdatedAt
        try validate()
    }

    var sagaMutationIDs: [MutationIDV1] {
        [
            preparedSagaMutationID,
            contentPromotedSagaMutationID,
            targetCommittedSagaMutationID,
            draftRetirePendingSagaMutationID
        ]
    }

    var allOperationalMutationIDs: [MutationIDV1] {
        [command.mutationID] + sagaMutationIDs + [terminalBundleMutationID]
    }

    var sagaUpdatedAts: [Date] {
        [
            preparedSagaUpdatedAt,
            contentPromotedSagaUpdatedAt,
            targetCommittedSagaUpdatedAt,
            draftRetirePendingSagaUpdatedAt,
            draftRetiredSagaUpdatedAt
        ]
    }

    func validate() throws {
        try command.validate()
        let durableIDs = [
            fieldDraftPlanID,
            preparedSagaID,
            contentPromotedSagaID,
            targetCommittedSagaID,
            draftRetirePendingSagaID,
            draftRetiredSagaID,
            commitReceiptID
        ]
        try durableIDs.forEach(MyDayLimitsV1.id)
        let allOperationalIDs = durableIDs + allOperationalMutationIDs.map(\.rawValue)
        guard Set(allOperationalIDs).count == allOperationalIDs.count else {
            throw FieldDraftFailureV1.invalidValue
        }
        let dates = sagaUpdatedAts + [terminalCheckpointUpdatedAt]
        try dates.forEach(MyDayLimitsV1.millisecondInstant)
        guard zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw FieldDraftFailureV1.invalidValue
        }
    }
}

struct MyDayPlanningDraftPayloadV1: Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let phase: MyDayPlanningPayloadPhaseV1
    let confirmedContext: MyDayPlanningConfirmedContextV1?
    let editingIntent: MyDayPlanningEditingIntentV1?
    let commitAttempt: MyDayPlanningCommitAttemptInputsV1?

    init(
        editing context: MyDayPlanningConfirmedContextV1,
        intent: MyDayPlanningEditingIntentV1
    ) throws {
        schemaVersion = Self.schemaVersion
        phase = .editing
        confirmedContext = context
        editingIntent = intent
        commitAttempt = nil
        try validate()
    }

    init(prepared attempt: MyDayPlanningCommitAttemptInputsV1) throws {
        schemaVersion = Self.schemaVersion
        phase = .preparedCommit
        confirmedContext = nil
        editingIntent = nil
        commitAttempt = attempt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw FieldDraftFailureV1.incompatibleVersion
        }
        switch phase {
        case .editing:
            guard let confirmedContext, let editingIntent, commitAttempt == nil else {
                throw FieldDraftFailureV1.invalidValue
            }
            try confirmedContext.validate()
            try editingIntent.validate()
            guard editingIntent.targetKey == confirmedContext.key else {
                throw FieldDraftFailureV1.wrongWorkspace
            }
        case .preparedCommit:
            guard confirmedContext == nil, editingIntent == nil, let commitAttempt else {
                throw FieldDraftFailureV1.invalidValue
            }
            try commitAttempt.validate()
        }
    }
}

extension MyDayPlanningDraftPayloadV1: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, phase, confirmedContext, editingIntent
        case command, fieldDraftPlanID
        case preparedSagaID, contentPromotedSagaID, targetCommittedSagaID
        case draftRetirePendingSagaID, draftRetiredSagaID
        case preparedSagaMutationID, contentPromotedSagaMutationID, targetCommittedSagaMutationID
        case draftRetirePendingSagaMutationID, terminalBundleMutationID, commitReceiptID
        case preparedSagaUpdatedAt, contentPromotedSagaUpdatedAt, targetCommittedSagaUpdatedAt
        case draftRetirePendingSagaUpdatedAt, draftRetiredSagaUpdatedAt, terminalCheckpointUpdatedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else { throw FieldDraftFailureV1.incompatibleVersion }
        let decodedPhase = try values.decode(MyDayPlanningPayloadPhaseV1.self, forKey: .phase)
        let actualKeys = Set(values.allKeys.map(\.rawValue))
        switch decodedPhase {
        case .editing:
            let required = Set([
                CodingKeys.schemaVersion.rawValue,
                CodingKeys.phase.rawValue,
                CodingKeys.confirmedContext.rawValue,
                CodingKeys.editingIntent.rawValue
            ])
            guard actualKeys == required else { throw FieldDraftFailureV1.invalidValue }
            self = try .init(
                editing: values.decode(MyDayPlanningConfirmedContextV1.self, forKey: .confirmedContext),
                intent: values.decode(MyDayPlanningEditingIntentV1.self, forKey: .editingIntent)
            )
        case .preparedCommit:
            let required = Set(CodingKeys.allCases.map(\.rawValue)).subtracting([
                CodingKeys.confirmedContext.rawValue,
                CodingKeys.editingIntent.rawValue
            ])
            guard actualKeys == required else { throw FieldDraftFailureV1.invalidValue }
            self = try .init(prepared: .init(
                command: values.decode(MyDayCommandV1.self, forKey: .command),
                fieldDraftPlanID: values.decode(UUID.self, forKey: .fieldDraftPlanID),
                preparedSagaID: values.decode(UUID.self, forKey: .preparedSagaID),
                contentPromotedSagaID: values.decode(UUID.self, forKey: .contentPromotedSagaID),
                targetCommittedSagaID: values.decode(UUID.self, forKey: .targetCommittedSagaID),
                draftRetirePendingSagaID: values.decode(UUID.self, forKey: .draftRetirePendingSagaID),
                draftRetiredSagaID: values.decode(UUID.self, forKey: .draftRetiredSagaID),
                preparedSagaMutationID: values.decode(MutationIDV1.self, forKey: .preparedSagaMutationID),
                contentPromotedSagaMutationID: values.decode(MutationIDV1.self, forKey: .contentPromotedSagaMutationID),
                targetCommittedSagaMutationID: values.decode(MutationIDV1.self, forKey: .targetCommittedSagaMutationID),
                draftRetirePendingSagaMutationID: values.decode(MutationIDV1.self, forKey: .draftRetirePendingSagaMutationID),
                terminalBundleMutationID: values.decode(MutationIDV1.self, forKey: .terminalBundleMutationID),
                commitReceiptID: values.decode(UUID.self, forKey: .commitReceiptID),
                preparedSagaUpdatedAt: values.decode(Date.self, forKey: .preparedSagaUpdatedAt),
                contentPromotedSagaUpdatedAt: values.decode(Date.self, forKey: .contentPromotedSagaUpdatedAt),
                targetCommittedSagaUpdatedAt: values.decode(Date.self, forKey: .targetCommittedSagaUpdatedAt),
                draftRetirePendingSagaUpdatedAt: values.decode(Date.self, forKey: .draftRetirePendingSagaUpdatedAt),
                draftRetiredSagaUpdatedAt: values.decode(Date.self, forKey: .draftRetiredSagaUpdatedAt),
                terminalCheckpointUpdatedAt: values.decode(Date.self, forKey: .terminalCheckpointUpdatedAt)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(phase, forKey: .phase)
        switch phase {
        case .editing:
            guard let confirmedContext, let editingIntent else {
                throw FieldDraftFailureV1.invalidValue
            }
            try values.encode(confirmedContext, forKey: .confirmedContext)
            try values.encode(editingIntent, forKey: .editingIntent)
        case .preparedCommit:
            guard let attempt = commitAttempt else {
                throw FieldDraftFailureV1.invalidValue
            }
            try values.encode(attempt.command, forKey: .command)
            try values.encode(attempt.fieldDraftPlanID, forKey: .fieldDraftPlanID)
            try values.encode(attempt.preparedSagaID, forKey: .preparedSagaID)
            try values.encode(attempt.contentPromotedSagaID, forKey: .contentPromotedSagaID)
            try values.encode(attempt.targetCommittedSagaID, forKey: .targetCommittedSagaID)
            try values.encode(attempt.draftRetirePendingSagaID, forKey: .draftRetirePendingSagaID)
            try values.encode(attempt.draftRetiredSagaID, forKey: .draftRetiredSagaID)
            try values.encode(attempt.preparedSagaMutationID, forKey: .preparedSagaMutationID)
            try values.encode(attempt.contentPromotedSagaMutationID, forKey: .contentPromotedSagaMutationID)
            try values.encode(attempt.targetCommittedSagaMutationID, forKey: .targetCommittedSagaMutationID)
            try values.encode(attempt.draftRetirePendingSagaMutationID, forKey: .draftRetirePendingSagaMutationID)
            try values.encode(attempt.terminalBundleMutationID, forKey: .terminalBundleMutationID)
            try values.encode(attempt.commitReceiptID, forKey: .commitReceiptID)
            try values.encode(attempt.preparedSagaUpdatedAt, forKey: .preparedSagaUpdatedAt)
            try values.encode(attempt.contentPromotedSagaUpdatedAt, forKey: .contentPromotedSagaUpdatedAt)
            try values.encode(attempt.targetCommittedSagaUpdatedAt, forKey: .targetCommittedSagaUpdatedAt)
            try values.encode(attempt.draftRetirePendingSagaUpdatedAt, forKey: .draftRetirePendingSagaUpdatedAt)
            try values.encode(attempt.draftRetiredSagaUpdatedAt, forKey: .draftRetiredSagaUpdatedAt)
            try values.encode(attempt.terminalCheckpointUpdatedAt, forKey: .terminalCheckpointUpdatedAt)
        }
    }
}

enum MyDayPlanningDraftCodecV1 {
    static let maximumPayloadBytes = 1_048_576
    static let codecID = "assetrounds.my-day-planning.v1"
    static let codecVersion: UInt64 = 1
    static let releaseSHA256 = "a1c5569f3e4cc1781022a7a3ce950b1234af2439b4aeed3d4f57bf6b9e08dadd"

    static let grammarDescriptor = [
        "codecID=assetrounds.my-day-planning.v1",
        "codecVersion=1",
        "payload.schemaVersion=1",
        "payload.phase=EDITING|PREPARED_COMMIT",
        "payload.keys.EDITING=schemaVersion,phase,confirmedContext,editingIntent",
        "payload.keys.PREPARED_COMMIT=schemaVersion,phase,command,fieldDraftPlanID,preparedSagaID,contentPromotedSagaID,targetCommittedSagaID,draftRetirePendingSagaID,draftRetiredSagaID,preparedSagaMutationID,contentPromotedSagaMutationID,targetCommittedSagaMutationID,draftRetirePendingSagaMutationID,terminalBundleMutationID,commitReceiptID,preparedSagaUpdatedAt,contentPromotedSagaUpdatedAt,targetCommittedSagaUpdatedAt,draftRetirePendingSagaUpdatedAt,draftRetiredSagaUpdatedAt,terminalCheckpointUpdatedAt",
        "confirmedContext.keys=key,recordedBy,keyWasExplicitlyConfirmed,recordedByWasExplicitlySelectedOrCaptured",
        "editingIntent.kind=PLAN|CARRYOVER",
        "editingIntent.keys.PLAN=kind,draft,predecessor",
        "editingIntent.keys.CARRYOVER=kind,sourcePlan,selectedMembershipIDs,targetKey,targetPredecessor",
        "nested=MyDayKeyV1,ActorSnapshotV1,MyDayPlanDraftV1,MyDayPlanV1,MyDayPlanReferenceV1,MyDayCommandV1,MutationIDV1",
        "limits.maximumPayloadBytes=1048576",
        "limits.maximumStageItems=0",
        "limits.maximumMyDayItems=50",
        "dates=millisecondsSince1970",
        "canonical=WorkspaceMutationCanonicalV1.sortedKeys.byteExactReencode",
        "authority=purpose:MY_DAY_PLANNING,target:apply_my_day_v1,retention:RETIRE_AFTER_COMMIT,privacy:WORKSPACE_PRIVATE,attachments:none",
        "invariant.editing=explicitConfirmedKeyAndRecordedBy;exactIntent;noPreparedAttempt",
        "invariant.prepared=exactCommandPlusNonderivedIDsAndTimes;noGenericDraftCommitPlanOrSagaOrDerivedGenericDigestOrExpectedRevision",
        "invariant.identity=allOperationalIDsNonzeroAndPairwiseUniqueAcrossPlanSagaReceiptAndMutationKinds",
        "invariant.time=fiveSagaTimesAndTerminalCheckpointTimeMillisecondQuantizedAndNondecreasing",
        "invariant.checkpoint=workspaceKeyScopeBaseRevisionStateStageAndCodecExact",
        "checkpoint.phaseStates.EDITING=ACTIVE|RECOVERY_REQUIRED|DISCARD_PENDING|DISCARDED",
        "checkpoint.phaseStates.PREPARED_COMMIT=COMMITTING|CONFLICTED|RECOVERY_REQUIRED|COMMITTED",
        "checkpoint.reconstruction=PREPARED_COMMIT+COMMITTING only",
        "invariant.reconstruction=payloadBytes->payloadSHA256->DraftCommitPlanV1->fiveDraftCommitSagaV1"
    ].joined(separator: "\n")

    static func release() throws -> DraftPayloadCodecReleaseV1 {
        guard FieldDraftCanonicalCodecV1.sha256(Data(grammarDescriptor.utf8)) == releaseSHA256 else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return try .init(codecID: codecID, codecVersion: codecVersion, releaseSHA256: releaseSHA256)
    }

    static func definition() throws -> DraftPurposeDefinitionV1 {
        try .init(
            purpose: .myDayPlanning,
            codec: release(),
            maximumPayloadBytes: maximumPayloadBytes,
            maximumStageItems: 0,
            targetCommandKind: .applyMyDay,
            retention: .retireAfterCommit,
            attachmentKinds: [],
            privacyClass: .workspacePrivate
        )
    }

    static func scope(for key: MyDayKeyV1) throws -> DraftScopeKeyV1 {
        try key.validate()
        return try .init(
            scopeKind: DraftPurposeV1.myDayPlanning.rawValue,
            stableComponentIDs: [key.stableKey]
        )
    }

    static func encode(_ value: MyDayPlanningDraftPayloadV1) throws -> Data {
        _ = try release()
        try value.validate()
        let data = try FieldDraftCanonicalCodecV1.encode(value)
        guard !data.isEmpty, data.count <= maximumPayloadBytes else {
            throw FieldDraftFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> MyDayPlanningDraftPayloadV1 {
        _ = try release()
        guard !data.isEmpty, data.count <= maximumPayloadBytes else {
            throw FieldDraftFailureV1.limitExceeded
        }
        let value = try FieldDraftCanonicalCodecV1.decode(
            MyDayPlanningDraftPayloadV1.self,
            from: data
        )
        try value.validate()
        guard try encode(value) == data else { throw FieldDraftFailureV1.digestMismatch }
        return value
    }

    @discardableResult
    static func validateCheckpointPayload(
        _ checkpoint: FieldDraftCheckpointV1
    ) throws -> MyDayPlanningDraftPayloadV1 {
        let authority = try MyDayPlanningDraftPurposeAuthorityV1()
        try checkpoint.validate(authority: authority)
        try MyDayLimitsV1.millisecondInstant(checkpoint.updatedAt)
        guard checkpoint.purpose == .myDayPlanning,
              checkpoint.codec == (try release()),
              checkpoint.stageIDs.isEmpty else {
            throw FieldDraftFailureV1.invalidValue
        }
        let payload = try decode(checkpoint.payloadData)
        switch payload.phase {
        case .editing:
            guard let context = payload.confirmedContext,
                  let intent = payload.editingIntent,
                  [.active, .conflicted, .recoveryRequired, .discardPending, .discarded].contains(checkpoint.state),
                  checkpoint.workspaceID == context.key.workspaceID,
                  checkpoint.scope == (try scope(for: context.key)),
                  checkpoint.baseCanonicalRevision == intent.targetBaseRevision else {
                throw FieldDraftFailureV1.invalidValue
            }
        case .preparedCommit:
            guard let attempt = payload.commitAttempt,
                  [.committing, .conflicted, .recoveryRequired, .committed].contains(checkpoint.state),
                  checkpoint.workspaceID == attempt.command.workspaceID,
                  checkpoint.scope == (try scope(for: attempt.command.myDayPlanningTargetKey)),
                  checkpoint.baseCanonicalRevision == attempt.command.myDayPlanningExpectedTargetRevision else {
                throw FieldDraftFailureV1.invalidValue
            }
            if checkpoint.state == .committing {
                guard attempt.terminalCheckpointUpdatedAt >= checkpoint.updatedAt else {
                    throw FieldDraftFailureV1.invalidValue
                }
            } else if checkpoint.state == .committed {
                guard attempt.terminalCheckpointUpdatedAt == checkpoint.updatedAt else {
                    throw FieldDraftFailureV1.invalidValue
                }
            }
            let checkpointMutationIsValid: Bool
            if checkpoint.state == .committed {
                checkpointMutationIsValid =
                    checkpoint.mutationID == attempt.terminalBundleMutationID
                    && checkpoint.lastDurableMutationID == attempt.terminalBundleMutationID
            } else {
                checkpointMutationIsValid = !attempt.allOperationalMutationIDs.contains(checkpoint.mutationID)
            }
            guard checkpointMutationIsValid else { throw FieldDraftFailureV1.invalidValue }
        }
        return payload
    }

    static func reconstructCommit(
        from checkpoint: FieldDraftCheckpointV1
    ) throws -> MyDayPlanningCommitReconstructionV1 {
        let payload = try validateCheckpointPayload(checkpoint)
        guard checkpoint.state == .committing,
              let attempt = payload.commitAttempt else {
            throw FieldDraftFailureV1.invalidTransition
        }
        let plan = try DraftCommitPlanV1(
            planID: attempt.fieldDraftPlanID,
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            draftRevision: checkpoint.draftRevision,
            baseCanonicalRevision: checkpoint.baseCanonicalRevision,
            payloadSHA256: checkpoint.payloadSHA256,
            stageDigests: [],
            targetCommandKind: .applyMyDay,
            expectedTargetRevision: attempt.command.myDayPlanningExpectedTargetRevision,
            mutationID: attempt.command.mutationID,
            outputKeys: try attempt.command.myDayPlanningOutputKeys
        )
        let prepared = try DraftCommitSagaV1(
            sagaID: attempt.preparedSagaID,
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            plan: plan,
            state: .prepared,
            revision: 1,
            mutationID: attempt.preparedSagaMutationID,
            updatedAt: attempt.preparedSagaUpdatedAt
        )
        let contentPromoted = try DraftCommitSagaV1(
            sagaID: attempt.contentPromotedSagaID,
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            plan: plan,
            state: .contentPromotedUnbound,
            predecessorSagaID: prepared.sagaID,
            revision: 2,
            mutationID: attempt.contentPromotedSagaMutationID,
            updatedAt: attempt.contentPromotedSagaUpdatedAt
        )
        let targetCommitted = try DraftCommitSagaV1(
            sagaID: attempt.targetCommittedSagaID,
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            plan: plan,
            state: .targetCommitted,
            predecessorSagaID: contentPromoted.sagaID,
            revision: 3,
            mutationID: attempt.targetCommittedSagaMutationID,
            updatedAt: attempt.targetCommittedSagaUpdatedAt
        )
        let retirePending = try DraftCommitSagaV1(
            sagaID: attempt.draftRetirePendingSagaID,
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            plan: plan,
            state: .draftRetirePending,
            predecessorSagaID: targetCommitted.sagaID,
            revision: 4,
            mutationID: attempt.draftRetirePendingSagaMutationID,
            updatedAt: attempt.draftRetirePendingSagaUpdatedAt
        )
        let retired = try DraftCommitSagaV1(
            sagaID: attempt.draftRetiredSagaID,
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            plan: plan,
            state: .draftRetired,
            predecessorSagaID: retirePending.sagaID,
            revision: 5,
            mutationID: attempt.terminalBundleMutationID,
            updatedAt: attempt.draftRetiredSagaUpdatedAt
        )
        let rowMutationIDs = try DraftCommitRowMutationIDsV1(
            reservationByStageID: [:],
            terminalBundleMutationID: attempt.terminalBundleMutationID
        )
        try rowMutationIDs.validate(
            stageIDs: [],
            targetMutationID: plan.mutationID,
            sagaMutationIDs: attempt.sagaMutationIDs
        )
        return .init(
            command: attempt.command,
            plan: plan,
            prepared: prepared,
            contentPromoted: contentPromoted,
            targetCommitted: targetCommitted,
            retirePending: retirePending,
            retired: retired,
            rowMutationIDs: rowMutationIDs,
            commitReceiptID: attempt.commitReceiptID,
            terminalCheckpointUpdatedAt: attempt.terminalCheckpointUpdatedAt
        )
    }
}

struct MyDayPlanningDraftPurposeAuthorityV1: DraftPurposeDefinitionResolvingV1, Sendable {
    private let definition: DraftPurposeDefinitionV1

    init() throws {
        definition = try MyDayPlanningDraftCodecV1.definition()
    }

    func require(
        _ purpose: DraftPurposeV1,
        codec: DraftPayloadCodecReleaseV1
    ) throws -> DraftPurposeDefinitionV1 {
        guard purpose == .myDayPlanning else { throw FieldDraftFailureV1.unknownPurpose }
        guard codec == definition.codec else { throw FieldDraftFailureV1.unknownCodec }
        return definition
    }
}

struct MyDayPlanningCommitReconstructionV1: Equatable, Sendable {
    let command: MyDayCommandV1
    let plan: DraftCommitPlanV1
    let prepared: DraftCommitSagaV1
    let contentPromoted: DraftCommitSagaV1
    let targetCommitted: DraftCommitSagaV1
    let retirePending: DraftCommitSagaV1
    let retired: DraftCommitSagaV1
    let rowMutationIDs: DraftCommitRowMutationIDsV1
    let commitReceiptID: UUID
    let terminalCheckpointUpdatedAt: Date

    var sagas: [DraftCommitSagaV1] {
        [prepared, contentPromoted, targetCommitted, retirePending, retired]
    }
}

private extension MyDayCommandV1 {
    var myDayPlanningTargetKey: MyDayKeyV1 {
        switch self {
        case .save(let successor, _): return successor.key
        case .carryover(_, _, let target, _): return target.key
        }
    }

    var myDayPlanningExpectedTargetRevision: UInt64 {
        switch self {
        case .save(_, let predecessor): return predecessor?.revision ?? 0
        case .carryover(let plan, _, _, _): return plan.expectedTargetPlan?.revision ?? 0
        }
    }

    var myDayPlanningOutputKeys: [String] {
        get throws {
            let values: [WorkspaceEntityIdentityV1]
            switch self {
            case .save(let successor, _):
                values = [try .init(kind: .myDayPlan, id: successor.planID)]
            case .carryover(_, _, let target, _):
                values = [
                    try .init(kind: .myDayPlan, id: target.planID),
                    try .init(kind: .myDayCarryoverReceipt, id: mutationID.rawValue)
                ]
            }
            return values.map(\.stableKey).sorted()
        }
    }
}
