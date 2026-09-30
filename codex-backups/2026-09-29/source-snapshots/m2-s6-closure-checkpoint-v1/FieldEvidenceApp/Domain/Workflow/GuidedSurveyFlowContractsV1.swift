import Foundation

enum GuidedSurveyFlowFailureV1: Error, Equatable, Sendable {
    case invalidValue, wrongWorkspace, staleSource, missingExactSource
    case unresolvedCondition, incompleteReview, immutablePublicationMismatch, limitExceeded
}

enum GuidedSurveyFlowPersistenceV1 {
    static let mode = "DERIVED_NONPERSISTENT"
    static let persistentSchemaVersion = 53
    static let activeModelCount = 168
    static let addsDurableRows = false
}

enum GuidedSurveyStageV1: String, Codable, CaseIterable, Hashable, Sendable {
    case selectSite = "SELECT_SITE"
    case selectAreaOrPlan = "SELECT_AREA_OR_PLAN"
    case selectSubject = "SELECT_SUBJECT"
    case collectFactsAndEvidence = "COLLECT_FACTS_AND_EVIDENCE"
    case review = "REVIEW"
    case publication = "PUBLICATION"
    case complete = "COMPLETE"
}

enum GuidedSurveyPrimaryActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case selectSite = "SELECT_SITE"
    case selectAreaOrPlan = "SELECT_AREA_OR_PLAN"
    case selectSubject = "SELECT_SUBJECT"
    case answerRequiredFact = "ANSWER_REQUIRED_FACT"
    case resolveConflict = "RESOLVE_CONFLICT"
    case review = "REVIEW"
    case publish = "PUBLISH"
    case viewFrozenReport = "VIEW_FROZEN_REPORT"
    case none = "NONE"
}

enum SurveyDefinitionLibraryActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case open = "OPEN", favorite = "FAVORITE", unfavorite = "UNFAVORITE"
    case duplicateAsDraft = "DUPLICATE_AS_DRAFT", publish = "PUBLISH", retire = "RETIRE"
    case export = "EXPORT", importAsFreshDraft = "IMPORT_AS_FRESH_DRAFT"
    case previewSemanticAdoption = "PREVIEW_SEMANTIC_ADOPTION"
}

struct GuidedSurveySessionTupleV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let sessionRevision: UInt64
    let sessionSHA256: String

    func validate() throws {
        guard sessionID != SurveyDefinitionLimitsV1.zero, sessionRevision > 0,
              KernelCanonicalHashV1.validSHA256(sessionSHA256) else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }

    func validate(matches expected: Self) throws {
        try validate(); try expected.validate()
        guard self == expected else { throw GuidedSurveyFlowFailureV1.staleSource }
    }
}

struct SurveyAuthoringPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let allowedFieldKinds: [SurveyFieldKindV1]
    let allowsGenericEAV: Bool
    let allowsScripting: Bool
    let allowsPassFail: Bool
    let allowsPrivateDirectionField: Bool
    let importDisposition: String
    let policySHA256: String

    init() throws {
        schemaVersion = Self.schemaVersion
        allowedFieldKinds = SurveyFieldKindV1.allCases.sorted { $0.rawValue < $1.rawValue }
        allowsGenericEAV = false; allowsScripting = false; allowsPassFail = false
        allowsPrivateDirectionField = false
        importDisposition = "QUARANTINE_THEN_FRESH_DRAFT_IDENTITY"
        policySHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, allowedFieldKinds: allowedFieldKinds,
            allowsGenericEAV: false, allowsScripting: false, allowsPassFail: false,
            allowsPrivateDirectionField: false,
            importDisposition: "QUARANTINE_THEN_FRESH_DRAFT_IDENTITY"
        ))
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              allowedFieldKinds == SurveyFieldKindV1.allCases.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(allowedFieldKinds).count == allowedFieldKinds.count,
              !allowsGenericEAV, !allowsScripting, !allowsPassFail,
              !allowsPrivateDirectionField,
              importDisposition == "QUARANTINE_THEN_FRESH_DRAFT_IDENTITY",
              policySHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, allowedFieldKinds: allowedFieldKinds, allowsGenericEAV: allowsGenericEAV, allowsScripting: allowsScripting, allowsPassFail: allowsPassFail, allowsPrivateDirectionField: allowsPrivateDirectionField, importDisposition: importDisposition) }
    private struct Basis: Codable { let schemaVersion: Int; let allowedFieldKinds: [SurveyFieldKindV1]; let allowsGenericEAV: Bool; let allowsScripting: Bool; let allowsPassFail: Bool; let allowsPrivateDirectionField: Bool; let importDisposition: String }
}

struct GuidedSurveyResumeContextV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let sessionRevision: UInt64
    let sessionSHA256: String
    let sectionID: String
    let subject: SurveySessionSubjectV1
    let factID: String?
    let repeatCoordinates: [SurveyRepeatCoordinateV1]

    var sessionTuple: GuidedSurveySessionTupleV1 {
        .init(workspaceID: workspaceID, sessionID: sessionID,
              sessionRevision: sessionRevision, sessionSHA256: sessionSHA256)
    }

    func validate(sessionTuple expected: GuidedSurveySessionTupleV1) throws {
        try sessionTuple.validate(matches: expected)
    }

    func validate(session: SurveySessionV1, definition: SurveyDefinitionReleaseV1) throws {
        try session.validate(definition: definition); try subject.validate()
        try repeatCoordinates.forEach { try $0.validate() }
        guard workspaceID == session.workspaceID, sessionID == session.sessionID,
              sessionRevision == session.revision, sessionSHA256 == session.sessionSHA256,
              subject == session.subject,
              definition.sections.contains(where: { $0.sectionID == sectionID }),
              factID.map({ id in definition.sections.flatMap(\.facts).contains(where: { $0.factID == id }) }) ?? true,
              repeatCoordinates == repeatCoordinates.sorted(),
              Set(repeatCoordinates).count == repeatCoordinates.count else {
            throw GuidedSurveyFlowFailureV1.staleSource
        }
    }
}

struct GuidedSurveyMissingRequirementV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let sectionID: String
    let factID: String
    let reasonLocalizationKey: String
    var stableKey: String { "\(sectionID)|\(factID)|\(reasonLocalizationKey)" }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableKey < rhs.stableKey }
}

struct GuidedSurveyConditionalReasonV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let factID: String
    let visible: Bool
    let dependencyFactIDs: [String]
    let reasonLocalizationKey: String
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.factID < rhs.factID }
}

struct GuidedSurveyRepeatProgressV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let groupFactID: String
    let completedCount: Int
    let minimum: Int
    let maximum: Int
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.groupFactID < rhs.groupFactID }
}

struct GuidedSurveyPriorFactV1: Codable, Equatable, Sendable {
    let factID: String
    let value: ResponseValueV1
    let sourceCapture: FactCaptureReferenceV1
    let displayPermitted: Bool

    func validate() throws {
        try value.validate()
        try sourceCapture.validate()
        guard SurveyDefinitionLimitsV1.token(factID), displayPermitted else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }
}

struct GuidedSurveyPoseRequirementV1: Codable, Equatable, Sendable {
    let packageReleaseID: String?
    let registryReleaseSHA256: String?
    let applicableAxes: [PoseAxisDescriptorV1]
    let manualEntryAvailable: Bool
    let notObservedAvailable: Bool

    init(release: PoseAxisRegistryReleaseV1?) throws {
        if let release {
            applicableAxes = release.registry.descriptors.filter { $0.applicability == .applicable }.sorted()
            packageReleaseID = release.packageReleaseID
            registryReleaseSHA256 = release.releaseSHA256
            manualEntryAvailable = !applicableAxes.isEmpty
            notObservedAvailable = !applicableAxes.isEmpty
        } else {
            packageReleaseID = nil; registryReleaseSHA256 = nil
            applicableAxes = []; manualEntryAvailable = false; notObservedAvailable = false
        }
        try validate()
    }

    func validate() throws {
        try applicableAxes.forEach { try $0.validate() }
        guard applicableAxes == applicableAxes.sorted(),
              Set(applicableAxes.map(\.axisID)).count == applicableAxes.count,
              (packageReleaseID == nil) == (registryReleaseSHA256 == nil),
              registryReleaseSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              packageReleaseID.map({ !$0.isEmpty }) ?? true,
              (packageReleaseID != nil || applicableAxes.isEmpty),
              (applicableAxes.isEmpty && !manualEntryAvailable && !notObservedAvailable) ||
                (!applicableAxes.isEmpty && packageReleaseID != nil &&
                 manualEntryAvailable && notObservedAvailable) else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }
}

struct SurveyReviewStateV1: Codable, Equatable, Sendable {
    static let persistenceMode = GuidedSurveyFlowPersistenceV1.mode
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let sessionRevision: UInt64
    let sessionSHA256: String
    let missingRequirements: [GuidedSurveyMissingRequirementV1]
    let conflictFactIDs: [String]
    let mayPublish: Bool
    let frozenPublication: SurveyPublicationReferenceV1?
    let reviewSHA256: String

    var sessionTuple: GuidedSurveySessionTupleV1 {
        .init(workspaceID: workspaceID, sessionID: sessionID,
              sessionRevision: sessionRevision, sessionSHA256: sessionSHA256)
    }

    init(session: SurveySessionV1, missingRequirements: [GuidedSurveyMissingRequirementV1],
         conflictFactIDs: [String], publication: SurveyPublicationSnapshotV1?) throws {
        try session.validateIntrinsic(); try publication?.validateIntrinsic()
        workspaceID = session.workspaceID; sessionID = session.sessionID
        sessionRevision = session.revision; sessionSHA256 = session.sessionSHA256
        self.missingRequirements = missingRequirements.sorted()
        self.conflictFactIDs = conflictFactIDs.sorted()
        frozenPublication = publication?.reference
        mayPublish = self.missingRequirements.isEmpty && self.conflictFactIDs.isEmpty &&
            publication == nil && session.state == .reviewRequired
        reviewSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            workspaceID: workspaceID, sessionID: sessionID, sessionRevision: sessionRevision,
            sessionSHA256: sessionSHA256, missingRequirements: self.missingRequirements,
            conflictFactIDs: self.conflictFactIDs, mayPublish: mayPublish,
            frozenPublication: frozenPublication
        ))
        try validate()
    }

    func validate() throws {
        try sessionTuple.validate()
        try frozenPublication?.validate()
        guard missingRequirements == missingRequirements.sorted(),
              Set(missingRequirements).count == missingRequirements.count,
              conflictFactIDs == conflictFactIDs.sorted(),
              Set(conflictFactIDs).count == conflictFactIDs.count,
              !mayPublish || (missingRequirements.isEmpty && conflictFactIDs.isEmpty && frozenPublication == nil),
              reviewSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }

    func validate(sessionTuple expected: GuidedSurveySessionTupleV1) throws {
        try validate(); try sessionTuple.validate(matches: expected)
    }

    private var basis: Basis { .init(workspaceID: workspaceID, sessionID: sessionID, sessionRevision: sessionRevision, sessionSHA256: sessionSHA256, missingRequirements: missingRequirements, conflictFactIDs: conflictFactIDs, mayPublish: mayPublish, frozenPublication: frozenPublication) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let sessionID: UUID; let sessionRevision: UInt64; let sessionSHA256: String; let missingRequirements: [GuidedSurveyMissingRequirementV1]; let conflictFactIDs: [String]; let mayPublish: Bool; let frozenPublication: SurveyPublicationReferenceV1? }
}

struct GuidedSurveyFlowV1: Codable, Equatable, Sendable {
    static let persistenceMode = GuidedSurveyFlowPersistenceV1.mode
    let workspaceID: WorkspaceID
    let definition: SurveyDefinitionReleaseReferenceV1
    let definitionState: SurveyDefinitionLifecycleStateV1
    let sessionID: UUID
    let sessionRevision: UInt64
    let sessionSHA256: String
    let stage: GuidedSurveyStageV1
    let sectionProgressMillionths: Int64
    let missingRequirements: [GuidedSurveyMissingRequirementV1]
    let conditionalReasons: [GuidedSurveyConditionalReasonV1]
    let repeatProgress: [GuidedSurveyRepeatProgressV1]
    let priorFacts: [GuidedSurveyPriorFactV1]
    let poseRequirement: GuidedSurveyPoseRequirementV1
    let review: SurveyReviewStateV1
    let resumeContext: GuidedSurveyResumeContextV1
    let primaryAction: GuidedSurveyPrimaryActionV1
    let favorite: Bool
    let recentOrdinal: Int?
    let flowSHA256: String

    var sessionTuple: GuidedSurveySessionTupleV1 {
        .init(workspaceID: workspaceID, sessionID: sessionID,
              sessionRevision: sessionRevision, sessionSHA256: sessionSHA256)
    }

    init(workspaceID: WorkspaceID, definition: SurveyDefinitionReleaseV1,
         identity: SurveyDefinitionIdentityV1, lifecycleEvent: SurveyDefinitionLifecycleEventV1,
         session: SurveySessionV1,
         captures: [FactCaptureV1], publication: SurveyPublicationSnapshotV1?,
         resumeContext: GuidedSurveyResumeContextV1,
         poseRequirement: GuidedSurveyPoseRequirementV1,
         priorFacts: [GuidedSurveyPriorFactV1], favorite: Bool, recentOrdinal: Int?) throws {
        try definition.validate(); try identity.validate(currentRelease: definition,
                                                          event: lifecycleEvent)
        try session.validate(definition: definition); try resumeContext.validate(session: session, definition: definition)
        try poseRequirement.validate(); try publication?.validateIntrinsic()
        try priorFacts.forEach { try $0.validate() }
        guard workspaceID == definition.workspaceID, workspaceID == session.workspaceID,
              identity.currentRelease == (try SurveyDefinitionReleaseReferenceV1(definition)),
              recentOrdinal.map({ $0 >= 0 }) ?? true else { throw GuidedSurveyFlowFailureV1.wrongWorkspace }
        let projection = try GuidedSurveyFlowDerivationV1.derive(definition: definition, session: session, captures: captures)
        let review = try SurveyReviewStateV1(session: session,
            missingRequirements: projection.missing, conflictFactIDs: projection.conflicts,
            publication: publication)
        self.workspaceID = workspaceID; self.definition = try .init(definition)
        definitionState = identity.lifecycleState; sessionID = session.sessionID
        sessionRevision = session.revision; sessionSHA256 = session.sessionSHA256
        stage = Self.stage(session: session, review: review)
        sectionProgressMillionths = projection.progress
        missingRequirements = projection.missing; conditionalReasons = projection.conditions
        repeatProgress = projection.repeats; self.priorFacts = priorFacts.sorted { $0.factID < $1.factID }
        self.poseRequirement = poseRequirement; self.review = review; self.resumeContext = resumeContext
        primaryAction = Self.action(stage: stage, review: review)
        self.favorite = favorite; self.recentOrdinal = recentOrdinal
        flowSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            workspaceID: workspaceID, definition: self.definition, definitionState: definitionState,
            sessionID: sessionID, sessionRevision: sessionRevision, sessionSHA256: sessionSHA256,
            stage: stage, sectionProgressMillionths: sectionProgressMillionths,
            missingRequirements: missingRequirements, conditionalReasons: conditionalReasons,
            repeatProgress: repeatProgress, priorFacts: self.priorFacts,
            poseRequirement: poseRequirement, review: review, resumeContext: resumeContext,
            primaryAction: primaryAction, favorite: favorite, recentOrdinal: recentOrdinal
        ))
        try validate()
    }

    func validate() throws {
        try definition.validate(); try poseRequirement.validate(); try sessionTuple.validate()
        try review.validate(sessionTuple: sessionTuple)
        try resumeContext.validate(sessionTuple: sessionTuple)
        try priorFacts.forEach { try $0.validate() }
        guard (0...1_000_000).contains(sectionProgressMillionths),
              missingRequirements == missingRequirements.sorted(),
              conditionalReasons == conditionalReasons.sorted(), repeatProgress == repeatProgress.sorted(),
              priorFacts.map(\.factID) == priorFacts.map(\.factID).sorted(),
              Set(priorFacts.map(\.factID)).count == priorFacts.count,
              flowSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw GuidedSurveyFlowFailureV1.invalidValue
        }
    }

    private static func stage(session: SurveySessionV1, review: SurveyReviewStateV1) -> GuidedSurveyStageV1 {
        if review.frozenPublication != nil { return .complete }
        switch session.state { case .reviewRequired: return .review; case .completed: return .publication; default: return .collectFactsAndEvidence }
    }
    private static func action(stage: GuidedSurveyStageV1, review: SurveyReviewStateV1) -> GuidedSurveyPrimaryActionV1 {
        if review.frozenPublication != nil { return .viewFrozenReport }
        if !review.conflictFactIDs.isEmpty { return .resolveConflict }
        if !review.missingRequirements.isEmpty { return .answerRequiredFact }
        if review.mayPublish { return .publish }
        return stage == .collectFactsAndEvidence ? .review : .none
    }
    private var basis: Basis { .init(workspaceID: workspaceID, definition: definition, definitionState: definitionState, sessionID: sessionID, sessionRevision: sessionRevision, sessionSHA256: sessionSHA256, stage: stage, sectionProgressMillionths: sectionProgressMillionths, missingRequirements: missingRequirements, conditionalReasons: conditionalReasons, repeatProgress: repeatProgress, priorFacts: priorFacts, poseRequirement: poseRequirement, review: review, resumeContext: resumeContext, primaryAction: primaryAction, favorite: favorite, recentOrdinal: recentOrdinal) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let definition: SurveyDefinitionReleaseReferenceV1; let definitionState: SurveyDefinitionLifecycleStateV1; let sessionID: UUID; let sessionRevision: UInt64; let sessionSHA256: String; let stage: GuidedSurveyStageV1; let sectionProgressMillionths: Int64; let missingRequirements: [GuidedSurveyMissingRequirementV1]; let conditionalReasons: [GuidedSurveyConditionalReasonV1]; let repeatProgress: [GuidedSurveyRepeatProgressV1]; let priorFacts: [GuidedSurveyPriorFactV1]; let poseRequirement: GuidedSurveyPoseRequirementV1; let review: SurveyReviewStateV1; let resumeContext: GuidedSurveyResumeContextV1; let primaryAction: GuidedSurveyPrimaryActionV1; let favorite: Bool; let recentOrdinal: Int? }
}

private enum GuidedSurveyFlowDerivationV1 {
    static func derive(definition: SurveyDefinitionReleaseV1, session: SurveySessionV1,
                       captures: [FactCaptureV1]) throws -> (missing: [GuidedSurveyMissingRequirementV1], conditions: [GuidedSurveyConditionalReasonV1], repeats: [GuidedSurveyRepeatProgressV1], conflicts: [String], progress: Int64) {
        try captures.forEach { try $0.validate(session: session, definition: definition) }
        let predecessorIDs = Set(captures.flatMap { $0.predecessors.map(\.captureID) })
        let heads = captures.filter { !predecessorIDs.contains($0.captureID) }
        let groups = Dictionary(grouping: heads) { "\($0.factID)|\($0.repeatCoordinates.map(\.stableKey).joined(separator: "/"))" }
        let conflicts = Array(Set(groups.filter { $0.value.count != 1 }.values.flatMap { $0.map(\.factID) })).sorted()
        let selected = groups.values.filter { $0.count == 1 }.compactMap(\.first).filter { $0.action != .retract }
        let values = Dictionary(uniqueKeysWithValues: selected.filter { $0.repeatCoordinates.isEmpty && $0.value != nil }.map { ($0.factID, $0.value!) })
        var missing: [GuidedSurveyMissingRequirementV1] = [], conditions: [GuidedSurveyConditionalReasonV1] = []
        var visibleCount = 0, answeredCount = 0
        for section in definition.sections.sorted(by: { $0.ordinal < $1.ordinal }) {
            for fact in section.facts {
                let visible = visibility(fact.visibility, values)
                if let expression = fact.visibility {
                    conditions.append(.init(factID: fact.factID, visible: visible,
                        dependencyFactIDs: Array(Set(expression.referencedFactIDs)).sorted(),
                        reasonLocalizationKey: visible ? "survey.condition.visible" : "survey.condition.hidden"))
                }
                guard visible, fact.kind != .instruction else { continue }
                visibleCount += 1
                if selected.contains(where: { $0.factID == fact.factID && $0.value != nil }) { answeredCount += 1 }
                else if fact.required { missing.append(.init(sectionID: section.sectionID,
                    factID: fact.factID, reasonLocalizationKey: "survey.required.missing")) }
            }
        }
        let repeats = definition.sections.flatMap(\.facts).compactMap { fact -> GuidedSurveyRepeatProgressV1? in
            guard case .repeatableGroup(let group) = fact.payload else { return nil }
            let count = Set(selected.filter { $0.factID == fact.factID }.flatMap { $0.repeatCoordinates.map(\.occurrenceID) }).count
            return .init(groupFactID: fact.factID, completedCount: count, minimum: group.minimum, maximum: group.maximum)
        }.sorted()
        let progress = visibleCount == 0 ? 1_000_000 : Int64(answeredCount) * 1_000_000 / Int64(visibleCount)
        return (missing.sorted(), conditions.sorted(), repeats, conflicts, progress)
    }
    private static func visibility(_ value: SurveyVisibilityExpressionV1?, _ facts: [String: ResponseValueV1]) -> Bool {
        guard let value else { return true }
        switch value { case .predicate(let p): return facts[p.factID] == p.expectedValue; case .all(let a): return a.allSatisfy { visibility($0, facts) }; case .any(let a): return a.contains { visibility($0, facts) }; case .not(let x): return !visibility(x, facts) }
    }
}
