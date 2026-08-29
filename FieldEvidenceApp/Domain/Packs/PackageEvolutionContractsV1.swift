import Foundation

enum PackageEvolutionFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion, invalidValue, invalidDigest, nonCanonicalData
    case staleSource, ineligibleDraft, incompleteSandbox, incompatiblePromotion
    case stalePointer, divergentMutation, limitExceeded, wrongWorkspace
}

enum C26SurveyEvolutionPinningV1 {
    static func validate(activeSessions:[SurveySessionV1],before:SurveyDefinitionReleaseV1,after:SurveyDefinitionReleaseV1)throws{try before.validate();try after.validate();guard activeSessions.allSatisfy({$0.authority.definitionRelease.releaseID==before.releaseID&&$0.authority.definitionRelease.releaseSHA256==before.releaseSHA256})else{throw SurveySessionFailureV1.staleRevision};try after.validateSuccessor(of:before)}
}

enum SurveyDefinitionEvolutionV1 {
    static func preview(source: SurveyDefinitionReleaseV1, target: SurveyDefinitionReleaseV1, draftIDs: [UUID], activeWorkCount: Int, at: Date) throws -> SurveyDefinitionAdoptionPreviewV1 {
        guard source.definitionID == target.definitionID, source.activityKind == target.activityKind else { throw PackageEvolutionFailureV1.incompatiblePromotion }
        return try .init(workspaceID: source.workspaceID, diff: .init(source: source, target: target), affectedDraftIDs: draftIDs, pinnedActiveWorkCount: activeWorkCount, generatedAt: at)
    }
}

enum PackageSemanticDiffClassificationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noChange = "NO_CHANGE"
    case additiveDraftSafe = "ADDITIVE_DRAFT_SAFE"
    case draftMigrationRequired = "DRAFT_MIGRATION_REQUIRED"
    case activeSessionIncompatible = "ACTIVE_SESSION_INCOMPATIBLE"
    case invalid = "INVALID"
}

enum PackageSemanticChangeKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case capabilityAdded = "CAPABILITY_ADDED", capabilityRemoved = "CAPABILITY_REMOVED"
    case permissionAdded = "PERMISSION_ADDED", permissionRemoved = "PERMISSION_REMOVED"
    case guidanceAdded = "GUIDANCE_ADDED", guidanceRemoved = "GUIDANCE_REMOVED", guidanceChanged = "GUIDANCE_CHANGED"
    case workflowNodeAdded = "WORKFLOW_NODE_ADDED", workflowNodeRemoved = "WORKFLOW_NODE_REMOVED", workflowNodeChanged = "WORKFLOW_NODE_CHANGED"
    case workflowIdentityChanged = "WORKFLOW_IDENTITY_CHANGED", workflowEntryNodeChanged = "WORKFLOW_ENTRY_NODE_CHANGED"
    case fieldAdded = "FIELD_ADDED", fieldRemoved = "FIELD_REMOVED"
    case packageContentVersionChanged = "PACKAGE_CONTENT_VERSION_CHANGED"
    case semanticReleaseChanged = "SEMANTIC_RELEASE_CHANGED"
    case packageIdentityChanged = "PACKAGE_IDENTITY_CHANGED", invalidCandidate = "INVALID_CANDIDATE"
}

struct PackageSemanticReleaseBindingsV1: Codable, Equatable, Sendable {
    let localizationReleaseSHA256: String?
    let assetSemanticCatalogSHA256s: [String]
    let authorityCriterionBindingSHA256s: [String]
    let functionalRelationshipBindingSHA256s: [String]
    init(localizationReleaseSHA256: String? = nil,
         assetSemanticCatalogSHA256s: [String] = [],
         authorityCriterionBindingSHA256s: [String] = [],
         functionalRelationshipBindingSHA256s: [String] = []) throws {
        self.localizationReleaseSHA256 = localizationReleaseSHA256
        self.assetSemanticCatalogSHA256s = assetSemanticCatalogSHA256s.sorted()
        self.authorityCriterionBindingSHA256s = authorityCriterionBindingSHA256s.sorted()
        self.functionalRelationshipBindingSHA256s = functionalRelationshipBindingSHA256s.sorted()
        try validate()
    }
    func validate() throws {
        let groups = [assetSemanticCatalogSHA256s, authorityCriterionBindingSHA256s, functionalRelationshipBindingSHA256s]
        guard localizationReleaseSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              groups.allSatisfy({ $0 == $0.sorted() && Set($0).count == $0.count && $0.allSatisfy(KernelCanonicalHashV1.validSHA256) }) else {
            throw PackageEvolutionFailureV1.invalidDigest
        }
    }
}

struct PackageSemanticChangeV1: Codable, Equatable, Hashable, Sendable {
    let kind: PackageSemanticChangeKindV1
    let stableSubjectID: String
    init(kind: PackageSemanticChangeKindV1, stableSubjectID: String) throws {
        guard InspectionPackageValidationV2.validToken(stableSubjectID, maximumBytes: 256) else { throw PackageEvolutionFailureV1.invalidValue }
        self.kind = kind; self.stableSubjectID = stableSubjectID
    }
    var stableKey: String { "\(kind.rawValue):\(stableSubjectID)" }
}

struct PackageSemanticGraphV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let packageReleaseID: String, packageID: String
    let packageContentVersion: Int
    let capabilityIDs: [String], permissionIDs: [String], guidanceSemanticIDs: [String]
    let presentationSemanticIDs: [String]
    let semanticReleaseBindings: PackageSemanticReleaseBindingsV1
    let workflowID: String, entryNodeID: String, declaredFieldIDs: [String], workflowNodeSemanticSHA256ByID: [String: String]
    let semanticGraphSHA256: String

    init(release: InspectionPackageReleaseV1) throws {
        try self.init(release: release, semanticReleaseBindings: .init())
    }
    init(release: InspectionPackageReleaseV1,
         semanticReleaseBindings: PackageSemanticReleaseBindingsV1) throws {
        try release.validate()
        try semanticReleaseBindings.validate()
        let package = try InspectionPackageCanonicalCodecV2.decode(release.canonicalPackageBytes)
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(release.canonicalWorkflowBytes)
        let nodes = try Dictionary(uniqueKeysWithValues: workflow.nodes.map { node in
            (node.nodeID, try WorkspaceMutationCanonicalV1.sha256(node))
        })
        let guidance = package.advisoryGuidance.map { "\($0.guidanceID)|\($0.kind.rawValue)|\($0.localizationKey)" }.sorted()
        let presentation = (
            package.presentation.evidencePurposes.map { "evidencePurpose|\($0.key)" }
            + package.presentation.acknowledgements.map { "acknowledgement|\($0.key)|\($0.version)" }
            + package.presentation.issueLabels.map { "issueLabel|\($0.key)" }
            + package.presentation.couldNotVerifyReasons.map { "couldNotVerify|\($0.key)" }
            + package.presentation.stageDisplays.map { "stage|\($0.key)" }
            + package.presentation.outcomeDisplays.map { "outcome|\($0.key)" }
            + ["couldNotVerifyRegistry|\(package.presentation.couldNotVerifyRegistryVersion)"]
        ).sorted()
        let capabilities = package.capabilities.map(\.rawValue).sorted()
        let permissions = package.permissions.map(\.rawValue).sorted()
        let fields = workflow.declaredFieldIDs.sorted()
        schemaVersion = Self.schemaVersion; packageReleaseID = release.packageReleaseID; packageID = package.packageID
        packageContentVersion = package.contentVersion; capabilityIDs = capabilities
        permissionIDs = permissions; guidanceSemanticIDs = guidance; presentationSemanticIDs = presentation; self.semanticReleaseBindings = semanticReleaseBindings
        workflowID = workflow.workflowID; entryNodeID = workflow.entryNodeID; declaredFieldIDs = fields
        workflowNodeSemanticSHA256ByID = nodes
        semanticGraphSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, packageID: package.packageID, packageContentVersion: package.contentVersion, capabilityIDs: capabilities, permissionIDs: permissions, guidanceSemanticIDs: guidance, presentationSemanticIDs: presentation, semanticReleaseBindings: semanticReleaseBindings, workflowID: workflow.workflowID, entryNodeID: workflow.entryNodeID, declaredFieldIDs: fields, workflowNodeSemanticSHA256ByID: nodes))
        try validate()
    }
    func validate() throws {
        try semanticReleaseBindings.validate()
        guard schemaVersion == Self.schemaVersion, KernelCanonicalHashV1.validSHA256(packageReleaseID),
              InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              WorkflowGrammarValidationV1.validID(workflowID), WorkflowGrammarValidationV1.validID(entryNodeID),
              packageContentVersion > 0,
              capabilityIDs == capabilityIDs.sorted(), permissionIDs == permissionIDs.sorted(), guidanceSemanticIDs == guidanceSemanticIDs.sorted(), presentationSemanticIDs == presentationSemanticIDs.sorted(),
              declaredFieldIDs == declaredFieldIDs.sorted(), Set(capabilityIDs).count == capabilityIDs.count,
              Set(permissionIDs).count == permissionIDs.count, Set(guidanceSemanticIDs).count == guidanceSemanticIDs.count, Set(presentationSemanticIDs).count == presentationSemanticIDs.count,
              workflowNodeSemanticSHA256ByID.values.allSatisfy(KernelCanonicalHashV1.validSHA256),
              semanticGraphSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else { throw PackageEvolutionFailureV1.invalidDigest }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, packageID: packageID, packageContentVersion: packageContentVersion, capabilityIDs: capabilityIDs, permissionIDs: permissionIDs, guidanceSemanticIDs: guidanceSemanticIDs, presentationSemanticIDs: presentationSemanticIDs, semanticReleaseBindings: semanticReleaseBindings, workflowID: workflowID, entryNodeID: entryNodeID, declaredFieldIDs: declaredFieldIDs, workflowNodeSemanticSHA256ByID: workflowNodeSemanticSHA256ByID) }
    private struct Basis: Codable { let schemaVersion: Int; let packageID: String; let packageContentVersion: Int; let capabilityIDs, permissionIDs, guidanceSemanticIDs, presentationSemanticIDs: [String]; let semanticReleaseBindings: PackageSemanticReleaseBindingsV1; let workflowID, entryNodeID: String; let declaredFieldIDs: [String]; let workflowNodeSemanticSHA256ByID: [String: String] }
}

struct PackageSemanticDiffV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int, diffID: String
    let source, target: PackageSemanticGraphV1
    let classification: PackageSemanticDiffClassificationV1
    let changes: [PackageSemanticChangeV1]
    let diffSHA256: String
    init(source: PackageSemanticGraphV1, target: PackageSemanticGraphV1, classification: PackageSemanticDiffClassificationV1, changes: [PackageSemanticChangeV1]) throws {
        let ordered = changes.sorted { $0.stableKey < $1.stableKey }
        schemaVersion = Self.schemaVersion; self.source = source; self.target = target; self.classification = classification; self.changes = ordered
        let basis = Basis(schemaVersion: Self.schemaVersion, source: source, target: target, classification: classification, changes: ordered)
        diffSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis); diffID = diffSHA256; try validate()
    }
    func validate() throws {
        try source.validate(); try target.validate()
        let expectedChanges = try PackageSemanticDifferV1.changes(source: source, target: target)
        guard schemaVersion == Self.schemaVersion,
              changes == expectedChanges,
              changes == changes.sorted(by: { $0.stableKey < $1.stableKey }), Set(changes.map(\.stableKey)).count == changes.count,
              classification == PackageSemanticDifferV1.classification(source: source, target: target, changes: changes),
              diffID == diffSHA256, diffSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else { throw PackageEvolutionFailureV1.invalidDigest }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, source: source, target: target, classification: classification, changes: changes) }
    private struct Basis: Codable { let schemaVersion: Int; let source, target: PackageSemanticGraphV1; let classification: PackageSemanticDiffClassificationV1; let changes: [PackageSemanticChangeV1] }
}

enum PackageSemanticDifferV1 {
    static func diff(source: InspectionPackageReleaseV1, target: InspectionPackageReleaseV1) throws -> PackageSemanticDiffV1 {
        try diff(source: source, target: target, sourceBindings: .init(), targetBindings: .init())
    }
    static func diff(source: InspectionPackageReleaseV1, target: InspectionPackageReleaseV1,
                     sourceBindings: PackageSemanticReleaseBindingsV1,
                     targetBindings: PackageSemanticReleaseBindingsV1) throws -> PackageSemanticDiffV1 {
        let a = try PackageSemanticGraphV1(release: source, semanticReleaseBindings: sourceBindings), b = try PackageSemanticGraphV1(release: target, semanticReleaseBindings: targetBindings)
        let changes = try changes(source: a, target: b)
        let c = classification(source: a, target: b, changes: changes)
        return try PackageSemanticDiffV1(source: a, target: b, classification: c, changes: changes)
    }

    /// Rebuilds the complete semantic change set from the two immutable graphs.
    /// Persisted or imported diffs are rejected unless their declared array is
    /// byte-for-byte equivalent to this deterministic derivation.
    static func changes(source a: PackageSemanticGraphV1,
                        target b: PackageSemanticGraphV1) throws -> [PackageSemanticChangeV1] {
        try a.validate(); try b.validate()
        var changes: [PackageSemanticChangeV1] = []
        func setChanges(_ old: [String], _ new: [String], added: PackageSemanticChangeKindV1, removed: PackageSemanticChangeKindV1) throws {
            for value in Set(new).subtracting(old).sorted() { changes.append(try .init(kind: added, stableSubjectID: value)) }
            for value in Set(old).subtracting(new).sorted() { changes.append(try .init(kind: removed, stableSubjectID: value)) }
        }
        if a.packageID != b.packageID { changes.append(try .init(kind: .packageIdentityChanged, stableSubjectID: b.packageID)) }
        if a.packageContentVersion != b.packageContentVersion {
            changes.append(try .init(kind: .packageContentVersionChanged,
                                     stableSubjectID: "\(a.packageContentVersion)__TO__\(b.packageContentVersion)"))
        }
        if a.workflowID != b.workflowID {
            changes.append(try .init(kind: .workflowIdentityChanged,
                                     stableSubjectID: "\(a.workflowID)__TO__\(b.workflowID)"))
        }
        if a.entryNodeID != b.entryNodeID {
            changes.append(try .init(kind: .workflowEntryNodeChanged,
                                     stableSubjectID: "\(a.entryNodeID)__TO__\(b.entryNodeID)"))
        }
        try setChanges(a.capabilityIDs, b.capabilityIDs, added: .capabilityAdded, removed: .capabilityRemoved)
        try setChanges(a.permissionIDs, b.permissionIDs, added: .permissionAdded, removed: .permissionRemoved)
        try setChanges(a.guidanceSemanticIDs, b.guidanceSemanticIDs, added: .guidanceAdded, removed: .guidanceRemoved)
        try setChanges(a.presentationSemanticIDs, b.presentationSemanticIDs, added: .guidanceAdded, removed: .guidanceRemoved)
        if a.semanticReleaseBindings != b.semanticReleaseBindings { changes.append(try .init(kind: .semanticReleaseChanged, stableSubjectID: "package.semantic.releases")) }
        try setChanges(a.declaredFieldIDs, b.declaredFieldIDs, added: .fieldAdded, removed: .fieldRemoved)
        let oldNodes = Set(a.workflowNodeSemanticSHA256ByID.keys), newNodes = Set(b.workflowNodeSemanticSHA256ByID.keys)
        for id in newNodes.subtracting(oldNodes).sorted() { changes.append(try .init(kind: .workflowNodeAdded, stableSubjectID: id)) }
        for id in oldNodes.subtracting(newNodes).sorted() { changes.append(try .init(kind: .workflowNodeRemoved, stableSubjectID: id)) }
        for id in oldNodes.intersection(newNodes).sorted() where a.workflowNodeSemanticSHA256ByID[id] != b.workflowNodeSemanticSHA256ByID[id] { changes.append(try .init(kind: .workflowNodeChanged, stableSubjectID: id)) }
        return changes.sorted { $0.stableKey < $1.stableKey }
    }
    static func classification(source: PackageSemanticGraphV1, target: PackageSemanticGraphV1, changes: [PackageSemanticChangeV1]) -> PackageSemanticDiffClassificationV1 {
        if target.packageContentVersion < source.packageContentVersion { return .invalid }
        if changes.contains(where: { $0.kind == .invalidCandidate || $0.kind == .packageIdentityChanged }) || target.packageContentVersion == source.packageContentVersion && source.semanticGraphSHA256 != target.semanticGraphSHA256 { return .invalid }
        if source.semanticGraphSHA256 == target.semanticGraphSHA256 { return .noChange }
        if changes.contains(where: { [.workflowIdentityChanged, .workflowEntryNodeChanged, .workflowNodeRemoved, .workflowNodeChanged, .capabilityRemoved, .permissionRemoved, .semanticReleaseChanged].contains($0.kind) }) { return .activeSessionIncompatible }
        if changes.contains(where: { [.fieldRemoved, .guidanceRemoved, .guidanceChanged].contains($0.kind) }) { return .draftMigrationRequired }
        return .additiveDraftSafe
    }
}

struct DraftUpgradePlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int, planID: String
    let workspaceID: WorkspaceID; let draftID: UUID; let sourceDraftRevision, sourceBaseCanonicalRevision: UInt64
    let sourceCheckpointSHA256, sourcePayloadSHA256, sourcePackageReleaseID, targetPackageReleaseID, semanticDiffSHA256: String
    let targetPayloadData: Data; let targetPayloadSHA256: String; let declaredActor: ActorSnapshotV1; let consentRecordedAt: Date; let planSHA256: String
    init(workspaceID: WorkspaceID, draftID: UUID, sourceDraftRevision: UInt64, sourceBaseCanonicalRevision: UInt64, sourceCheckpointSHA256: String, sourcePayloadSHA256: String, sourcePackageReleaseID: String, targetPackageReleaseID: String, semanticDiffSHA256: String, targetPayloadData: Data, declaredActor: ActorSnapshotV1, consentRecordedAt: Date) throws {
        let targetSHA = KernelCanonicalHashV1.sha256(targetPayloadData)
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.draftID = draftID; self.sourceDraftRevision = sourceDraftRevision; self.sourceBaseCanonicalRevision = sourceBaseCanonicalRevision; self.sourceCheckpointSHA256 = sourceCheckpointSHA256; self.sourcePayloadSHA256 = sourcePayloadSHA256; self.sourcePackageReleaseID = sourcePackageReleaseID; self.targetPackageReleaseID = targetPackageReleaseID; self.semanticDiffSHA256 = semanticDiffSHA256; self.targetPayloadData = targetPayloadData; targetPayloadSHA256 = targetSHA; self.declaredActor = declaredActor; self.consentRecordedAt = consentRecordedAt
        let sha = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, draftID: draftID, sourceDraftRevision: sourceDraftRevision, sourceBaseCanonicalRevision: sourceBaseCanonicalRevision, sourceCheckpointSHA256: sourceCheckpointSHA256, sourcePayloadSHA256: sourcePayloadSHA256, sourcePackageReleaseID: sourcePackageReleaseID, targetPackageReleaseID: targetPackageReleaseID, semanticDiffSHA256: semanticDiffSHA256, targetPayloadSHA256: targetSHA, declaredActor: declaredActor, consentRecordedAt: consentRecordedAt)); planID = sha; planSHA256 = sha; try validate()
    }
    func validate(source: FieldDraftCheckpointV1? = nil, diff: PackageSemanticDiffV1? = nil) throws {
        try declaredActor.validate(); if let source { try source.validate(); guard source.state == .active, source.workspaceID == workspaceID, source.draftID == draftID, source.draftRevision == sourceDraftRevision, source.baseCanonicalRevision == sourceBaseCanonicalRevision, source.checkpointSHA256 == sourceCheckpointSHA256, source.payloadSHA256 == sourcePayloadSHA256 else { throw PackageEvolutionFailureV1.staleSource } }; if let diff { try diff.validate(); guard diff.diffSHA256 == semanticDiffSHA256, diff.source.packageReleaseID == sourcePackageReleaseID, diff.target.packageReleaseID == targetPackageReleaseID, [.additiveDraftSafe, .draftMigrationRequired].contains(diff.classification) else { throw PackageEvolutionFailureV1.incompatiblePromotion } }
        guard schemaVersion == Self.schemaVersion, sourceDraftRevision > 0,
              [sourceCheckpointSHA256,sourcePayloadSHA256,sourcePackageReleaseID,targetPackageReleaseID,semanticDiffSHA256,targetPayloadSHA256,planSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              sourcePackageReleaseID != targetPackageReleaseID,
              declaredActor.workspaceID == workspaceID, declaredActor.responsibility == .recordedBy,
              consentRecordedAt.timeIntervalSinceReferenceDate.isFinite,
              targetPayloadData.count <= FieldDraftLimitsV1.maximumPayloadBytes,
              KernelCanonicalHashV1.sha256(targetPayloadData) == targetPayloadSHA256,
              planID == planSHA256, planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else { throw PackageEvolutionFailureV1.invalidDigest }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID, draftID: draftID, sourceDraftRevision: sourceDraftRevision, sourceBaseCanonicalRevision: sourceBaseCanonicalRevision, sourceCheckpointSHA256: sourceCheckpointSHA256, sourcePayloadSHA256: sourcePayloadSHA256, sourcePackageReleaseID: sourcePackageReleaseID, targetPackageReleaseID: targetPackageReleaseID, semanticDiffSHA256: semanticDiffSHA256, targetPayloadSHA256: targetPayloadSHA256, declaredActor: declaredActor, consentRecordedAt: consentRecordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let draftID: UUID; let sourceDraftRevision, sourceBaseCanonicalRevision: UInt64; let sourceCheckpointSHA256, sourcePayloadSHA256, sourcePackageReleaseID, targetPackageReleaseID, semanticDiffSHA256, targetPayloadSHA256: String; let declaredActor: ActorSnapshotV1; let consentRecordedAt: Date }
}

enum PackageSandboxCheckKindV1: String, Codable, CaseIterable, Hashable, Sendable { case schema="SCHEMA", graph="GRAPH", localizedDisplay="LOCALIZED_DISPLAY", reportPDF="REPORT_PDF", openJSON="OPEN_JSON", backupRestore="BACKUP_RESTORE", deleteErase="DELETE_ERASE", export="EXPORT", searchRebuild="SEARCH_REBUILD", replay="REPLAY", classification="CLASSIFICATION", brandStateFixtures="BRAND_STATE_FIXTURES" }
enum PackageSandboxFixtureShapeV1: String, Codable, CaseIterable, Hashable, Sendable { case minimal="MINIMAL", representative="REPRESENTATIVE" }
enum PackageSandboxCheckDispositionV1: String, Codable, Hashable, Sendable { case passed="PASSED", failed="FAILED" }
enum PackageSandboxActivationEvidenceV1: String, Codable, Hashable, Sendable {
    case notAttempted="NOT_ATTEMPTED", attempted="ATTEMPTED", unavailable="UNAVAILABLE"
}
struct PackageSandboxCheckResultV1: Codable, Equatable, Sendable {
    let kind: PackageSandboxCheckKindV1
    let shape: PackageSandboxFixtureShapeV1
    let fixtureID, fixtureSHA256, resultSHA256: String
    let disposition: PackageSandboxCheckDispositionV1
    let activationEvidence: PackageSandboxActivationEvidenceV1
    var stableKey: String { "\(kind.rawValue)|\(shape.rawValue)" }
}
enum PackageSandboxDispositionV1: String, Codable, Hashable, Sendable { case completePass="COMPLETE_PASS", completeFail="COMPLETE_FAIL" }

struct PackageSandboxRunV1: Codable, Equatable, Sendable {
    static let schemaVersion=1; let schemaVersion:Int; let runID:UUID; let workspaceID:WorkspaceID; let packageReleaseID,packageSHA256,workflowSHA256,semanticDiffSHA256,exactHead:String;let activePointerStateBeforeSHA256,activePointerStateAfterSHA256:String;let checks:[PackageSandboxCheckResultV1];let disposition:PackageSandboxDispositionV1;let revision:UInt64;let mutationID:MutationIDV1;let runSHA256:String
    init(runID:UUID,workspaceID:WorkspaceID,packageReleaseID:String,packageSHA256:String,workflowSHA256:String,semanticDiffSHA256:String,exactHead:String,activePointerStateBeforeSHA256:String,activePointerStateAfterSHA256:String,checks:[PackageSandboxCheckResultV1],revision:UInt64=1,mutationID:MutationIDV1)throws{let ordered=checks.sorted{$0.stableKey<$1.stableKey};let expectedCount=PackageSandboxCheckKindV1.allCases.count*PackageSandboxFixtureShapeV1.allCases.count;let result:PackageSandboxDispositionV1=ordered.count==expectedCount&&ordered.allSatisfy{$0.disposition == .passed&&$0.activationEvidence == .notAttempted}&&activePointerStateBeforeSHA256==activePointerStateAfterSHA256 ? .completePass:.completeFail;schemaVersion=Self.schemaVersion;self.runID=runID;self.workspaceID=workspaceID;self.packageReleaseID=packageReleaseID;self.packageSHA256=packageSHA256;self.workflowSHA256=workflowSHA256;self.semanticDiffSHA256=semanticDiffSHA256;self.exactHead=exactHead;self.activePointerStateBeforeSHA256=activePointerStateBeforeSHA256;self.activePointerStateAfterSHA256=activePointerStateAfterSHA256;self.checks=ordered;disposition=result;self.revision=revision;self.mutationID=mutationID;runSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,runID:runID,workspaceID:workspaceID,packageReleaseID:packageReleaseID,packageSHA256:packageSHA256,workflowSHA256:workflowSHA256,semanticDiffSHA256:semanticDiffSHA256,exactHead:exactHead,activePointerStateBeforeSHA256:activePointerStateBeforeSHA256,activePointerStateAfterSHA256:activePointerStateAfterSHA256,checks:ordered,disposition:result,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{let expectedPairs=Set(PackageSandboxCheckKindV1.allCases.flatMap{kind in PackageSandboxFixtureShapeV1.allCases.map{"\(kind.rawValue)|\($0.rawValue)"}});guard schemaVersion==Self.schemaVersion,runID != UUID.zero,revision>0,[packageReleaseID,packageSHA256,workflowSHA256,semanticDiffSHA256,activePointerStateBeforeSHA256,activePointerStateAfterSHA256,runSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),activePointerStateBeforeSHA256==activePointerStateAfterSHA256,exactHead.count==40&&exactHead.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),checks.map(\.stableKey)==checks.map(\.stableKey).sorted(),Set(checks.map(\.stableKey))==expectedPairs,checks.allSatisfy({InspectionPackageValidationV2.validToken($0.fixtureID,maximumBytes:160)&&KernelCanonicalHashV1.validSHA256($0.fixtureSHA256)&&KernelCanonicalHashV1.validSHA256($0.resultSHA256)&&$0.activationEvidence == .notAttempted}),PackageSandboxCheckKindV1.allCases.allSatisfy({kind in let fixtures=checks.filter{$0.kind==kind};return fixtures.count==2&&Set(fixtures.map(\.fixtureID)).count==2&&Set(fixtures.map(\.fixtureSHA256)).count==2}),disposition == (checks.allSatisfy{$0.disposition == .passed} ? .completePass:.completeFail),runSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw PackageEvolutionFailureV1.incompleteSandbox}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(runID:runID,workspaceID:workspaceID,packageReleaseID:packageReleaseID,packageSHA256:packageSHA256,workflowSHA256:workflowSHA256,semanticDiffSHA256:semanticDiffSHA256,exactHead:exactHead,activePointerStateBeforeSHA256:activePointerStateBeforeSHA256,activePointerStateAfterSHA256:activePointerStateAfterSHA256,checks:checks,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,runID:runID,workspaceID:workspaceID,packageReleaseID:packageReleaseID,packageSHA256:packageSHA256,workflowSHA256:workflowSHA256,semanticDiffSHA256:semanticDiffSHA256,exactHead:exactHead,activePointerStateBeforeSHA256:activePointerStateBeforeSHA256,activePointerStateAfterSHA256:activePointerStateAfterSHA256,checks:checks,disposition:disposition,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let runID:UUID;let workspaceID:WorkspaceID;let packageReleaseID,packageSHA256,workflowSHA256,semanticDiffSHA256,exactHead:String;let activePointerStateBeforeSHA256,activePointerStateAfterSHA256:String;let checks:[PackageSandboxCheckResultV1];let disposition:PackageSandboxDispositionV1;let revision:UInt64;let mutationID:MutationIDV1}
}

struct PromotedPackageReleaseV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let releaseRecordID:UUID;let workspaceID:WorkspaceID;let packageRelease:InspectionPackageReleaseV1;let revision:UInt64;let mutationID:MutationIDV1;let promotedAt:Date;let releaseRecordSHA256:String
    init(releaseRecordID:UUID,workspaceID:WorkspaceID,packageRelease:InspectionPackageReleaseV1,revision:UInt64=1,mutationID:MutationIDV1,promotedAt:Date)throws{schemaVersion=Self.schemaVersion;self.releaseRecordID=releaseRecordID;self.workspaceID=workspaceID;self.packageRelease=packageRelease;self.revision=revision;self.mutationID=mutationID;self.promotedAt=promotedAt;releaseRecordSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,releaseRecordID:releaseRecordID,workspaceID:workspaceID,packageRelease:packageRelease,revision:revision,mutationID:mutationID,promotedAt:promotedAt));try validate()}
    func validate()throws{try packageRelease.validate();guard schemaVersion==Self.schemaVersion,releaseRecordID != UUID.zero,revision==1,packageRelease.state == .published,releaseRecordSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw PackageEvolutionFailureV1.invalidDigest}};private var basis:Basis{.init(schemaVersion:schemaVersion,releaseRecordID:releaseRecordID,workspaceID:workspaceID,packageRelease:packageRelease,revision:revision,mutationID:mutationID,promotedAt:promotedAt)};private struct Basis:Codable{let schemaVersion:Int;let releaseRecordID:UUID;let workspaceID:WorkspaceID;let packageRelease:InspectionPackageReleaseV1;let revision:UInt64;let mutationID:MutationIDV1;let promotedAt:Date}}
extension PromotedPackageReleaseV1{func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(releaseRecordID:releaseRecordID,workspaceID:workspaceID,packageRelease:packageRelease,revision:revision,mutationID:mutationID,promotedAt:promotedAt)}}

enum PackagePromotionAuthorityV1:String,Codable,Hashable,Sendable{case explicitLocalOperator="EXPLICIT_LOCAL_OPERATOR"}
enum PackageRollbackCompatibilityV1:String,Codable,Hashable,Sendable{case preActivationDiscardable="PRE_ACTIVATION_DISCARDABLE",activatedForwardFixRequired="ACTIVATED_FORWARD_FIX_REQUIRED"}
enum PackagePromotionOperationV1:String,Codable,Hashable,Sendable{case initialActivation="INITIAL_ACTIVATION",postActivationForwardFix="POST_ACTIVATION_FORWARD_FIX"}
enum PackagePostActivationPolicyV1:String,Codable,Hashable,Sendable{case forwardFixOnly="FORWARD_FIX_ONLY"}

struct ActivePackageRegistryPointerV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let pointerID:UUID;let workspaceID:WorkspaceID;let packageID:String;let activeReleaseRecordID:UUID;let promotionReceiptID:UUID;let activePackageReleaseID,activeReleaseRecordSHA256:String;let supersedesPointerID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let pointerSHA256:String
    init(pointerID:UUID,workspaceID:WorkspaceID,packageID:String,activeReleaseRecordID:UUID,promotionReceiptID:UUID,activePackageReleaseID:String,activeReleaseRecordSHA256:String,supersedesPointerID:UUID?=nil,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.pointerID=pointerID;self.workspaceID=workspaceID;self.packageID=packageID;self.activeReleaseRecordID=activeReleaseRecordID;self.promotionReceiptID=promotionReceiptID;self.activePackageReleaseID=activePackageReleaseID;self.activeReleaseRecordSHA256=activeReleaseRecordSHA256;self.supersedesPointerID=supersedesPointerID;self.revision=revision;self.mutationID=mutationID;pointerSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,pointerID:pointerID,workspaceID:workspaceID,packageID:packageID,activeReleaseRecordID:activeReleaseRecordID,promotionReceiptID:promotionReceiptID,activePackageReleaseID:activePackageReleaseID,activeReleaseRecordSHA256:activeReleaseRecordSHA256,supersedesPointerID:supersedesPointerID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{guard schemaVersion==Self.schemaVersion,pointerID != UUID.zero,promotionReceiptID != UUID.zero,revision>0,InspectionPackageValidationV2.validIdentifier(packageID,maximumBytes:200),KernelCanonicalHashV1.validSHA256(activePackageReleaseID),KernelCanonicalHashV1.validSHA256(activeReleaseRecordSHA256),(supersedesPointerID==nil)==(revision==1),supersedesPointerID != pointerID,pointerSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw PackageEvolutionFailureV1.invalidDigest}}
    func validateSuccessor(of predecessor:Self,expectedRevision:UInt64)throws{try predecessor.validate();try validate();let next=predecessor.revision.addingReportingOverflow(1);guard !next.overflow,expectedRevision==predecessor.revision,revision==next.partialValue,supersedesPointerID==predecessor.pointerID,workspaceID==predecessor.workspaceID,packageID==predecessor.packageID,mutationID != predecessor.mutationID else{throw PackageEvolutionFailureV1.stalePointer}}
    func rebound(to workspaceID:WorkspaceID,activeReleaseRecord:PromotedPackageReleaseV1)throws->Self{try activeReleaseRecord.validate();guard activeReleaseRecord.releaseRecordID==activeReleaseRecordID,activeReleaseRecord.packageRelease.packageReleaseID==activePackageReleaseID,activeReleaseRecord.packageRelease.packageID==packageID else{throw PackageEvolutionFailureV1.incompatiblePromotion};return try .init(pointerID:pointerID,workspaceID:workspaceID,packageID:packageID,activeReleaseRecordID:activeReleaseRecordID,promotionReceiptID:promotionReceiptID,activePackageReleaseID:activePackageReleaseID,activeReleaseRecordSHA256:activeReleaseRecord.releaseRecordSHA256,supersedesPointerID:supersedesPointerID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,pointerID:pointerID,workspaceID:workspaceID,packageID:packageID,activeReleaseRecordID:activeReleaseRecordID,promotionReceiptID:promotionReceiptID,activePackageReleaseID:activePackageReleaseID,activeReleaseRecordSHA256:activeReleaseRecordSHA256,supersedesPointerID:supersedesPointerID,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let pointerID:UUID;let workspaceID:WorkspaceID;let packageID:String;let activeReleaseRecordID:UUID;let promotionReceiptID:UUID;let activePackageReleaseID,activeReleaseRecordSHA256:String;let supersedesPointerID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}}

struct PackagePromotionReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let promotedReleaseRecordID: UUID
    let sandboxRunID: UUID
    let semanticDiff: PackageSemanticDiffV1
    let predecessorPointerSHA256: String
    let resultingPointerSHA256: String
    let declaredActor: ActorSnapshotV1
    let exactHead: String
    let authority: PackagePromotionAuthorityV1
    let operation: PackagePromotionOperationV1
    let postActivationPolicy: PackagePostActivationPolicyV1
    let rollbackCompatibility: PackageRollbackCompatibilityV1
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let receiptSHA256: String

    var semanticDiffSHA256: String { semanticDiff.diffSHA256 }
    var actorSnapshotSHA256: String { declaredActor.snapshotSHA256 }

    init(receiptID: UUID, workspaceID: WorkspaceID,
         promotedRelease: PromotedPackageReleaseV1, sandboxRun: PackageSandboxRunV1,
         diff: PackageSemanticDiffV1, predecessorPointer: ActivePackageRegistryPointerV1?,
         resultingPointer: ActivePackageRegistryPointerV1, actor: ActorSnapshotV1,
         exactHead: String, authority: PackagePromotionAuthorityV1 = .explicitLocalOperator,
         operation: PackagePromotionOperationV1,
         postActivationPolicy: PackagePostActivationPolicyV1 = .forwardFixOnly,
         rollbackCompatibility: PackageRollbackCompatibilityV1, revision: UInt64 = 1,
         mutationID: MutationIDV1, recordedAt: Date) throws {
        let predecessorSHA = predecessorPointer?.pointerSHA256 ?? String(repeating: "0", count: 64)
        schemaVersion = Self.schemaVersion; self.receiptID = receiptID; self.workspaceID = workspaceID
        promotedReleaseRecordID = promotedRelease.releaseRecordID; sandboxRunID = sandboxRun.runID
        semanticDiff = diff; predecessorPointerSHA256 = predecessorSHA
        resultingPointerSHA256 = resultingPointer.pointerSHA256; declaredActor = actor
        self.exactHead = exactHead; self.authority = authority; self.operation = operation
        self.postActivationPolicy = postActivationPolicy; self.rollbackCompatibility = rollbackCompatibility
        self.revision = revision; self.mutationID = mutationID; self.recordedAt = recordedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
            promotedReleaseRecordID: promotedRelease.releaseRecordID, sandboxRunID: sandboxRun.runID,
            semanticDiff: diff, predecessorPointerSHA256: predecessorSHA,
            resultingPointerSHA256: resultingPointer.pointerSHA256, declaredActor: actor,
            exactHead: exactHead, authority: authority, operation: operation,
            postActivationPolicy: postActivationPolicy, rollbackCompatibility: rollbackCompatibility,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt
        ))
        try validate(promotedRelease: promotedRelease, sandboxRun: sandboxRun,
                     predecessorPointer: predecessorPointer, resultingPointer: resultingPointer)
    }

    func validate() throws {
        try semanticDiff.validate(); try declaredActor.validate()
        guard schemaVersion == Self.schemaVersion, receiptID != UUID.zero, revision == 1,
              declaredActor.workspaceID == workspaceID, declaredActor.responsibility == .recordedBy,
              declaredActor.capturedAt <= recordedAt,
              operation == (predecessorPointerSHA256 == String(repeating: "0", count: 64) ? .initialActivation : .postActivationForwardFix),
              postActivationPolicy == .forwardFixOnly,
              rollbackCompatibility == .activatedForwardFixRequired,
              [predecessorPointerSHA256, resultingPointerSHA256, receiptSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              exactHead.count == 40 && exactHead.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw PackageEvolutionFailureV1.invalidDigest
        }
    }

    func validate(promotedRelease: PromotedPackageReleaseV1,
                  sandboxRun: PackageSandboxRunV1,
                  predecessorPointer: ActivePackageRegistryPointerV1?,
                  resultingPointer: ActivePackageRegistryPointerV1) throws {
        try validate(); try promotedRelease.validate(); try sandboxRun.validate()
        try predecessorPointer?.validate(); try resultingPointer.validate()
        guard workspaceID == promotedRelease.workspaceID, workspaceID == sandboxRun.workspaceID,
              workspaceID == resultingPointer.workspaceID,
              promotedReleaseRecordID == promotedRelease.releaseRecordID, sandboxRunID == sandboxRun.runID,
              sandboxRun.disposition == .completePass, sandboxRun.semanticDiffSHA256 == semanticDiff.diffSHA256,
              sandboxRun.mutationID == mutationID,
              promotedRelease.packageRelease.packageReleaseID == semanticDiff.target.packageReleaseID,
              sandboxRun.packageReleaseID == promotedRelease.packageRelease.packageReleaseID,
              sandboxRun.packageSHA256 == promotedRelease.packageRelease.packageSHA256,
              sandboxRun.workflowSHA256 == promotedRelease.packageRelease.workflowSHA256,
              promotedRelease.promotedAt <= recordedAt,
              resultingPointer.activeReleaseRecordID == promotedRelease.releaseRecordID,
              resultingPointer.promotionReceiptID == receiptID,
              resultingPointer.packageID == promotedRelease.packageRelease.packageID,
              resultingPointer.activePackageReleaseID == promotedRelease.packageRelease.packageReleaseID,
              resultingPointer.activeReleaseRecordSHA256 == promotedRelease.releaseRecordSHA256,
              resultingPointer.mutationID == mutationID, promotedRelease.mutationID == mutationID,
              exactHead == sandboxRun.exactHead else { throw PackageEvolutionFailureV1.incompatiblePromotion }
        if let predecessorPointer {
            try resultingPointer.validateSuccessor(of: predecessorPointer, expectedRevision: predecessorPointer.revision)
            guard predecessorPointerSHA256 == predecessorPointer.pointerSHA256 else { throw PackageEvolutionFailureV1.stalePointer }
        } else {
            guard predecessorPointerSHA256 == String(repeating: "0", count: 64),
                  resultingPointer.revision == 1 else { throw PackageEvolutionFailureV1.stalePointer }
        }
    }

    func rebound(to workspaceID: WorkspaceID,
                 promotedRelease: PromotedPackageReleaseV1,
                 sandboxRun: PackageSandboxRunV1,
                 predecessorPointer: ActivePackageRegistryPointerV1?,
                 resultingPointer: ActivePackageRegistryPointerV1,
                 actor: ActorSnapshotV1) throws -> Self {
        try Self(receiptID: receiptID, workspaceID: workspaceID,
                 promotedRelease: promotedRelease, sandboxRun: sandboxRun,
                 diff: semanticDiff, predecessorPointer: predecessorPointer,
                 resultingPointer: resultingPointer, actor: actor, exactHead: exactHead,
                 authority: authority, operation: operation,
                 postActivationPolicy: postActivationPolicy,
                 rollbackCompatibility: rollbackCompatibility,
                 revision: revision, mutationID: mutationID, recordedAt: recordedAt)
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID,
        workspaceID: workspaceID, promotedReleaseRecordID: promotedReleaseRecordID,
        sandboxRunID: sandboxRunID, semanticDiff: semanticDiff,
        predecessorPointerSHA256: predecessorPointerSHA256,
        resultingPointerSHA256: resultingPointerSHA256, declaredActor: declaredActor,
        exactHead: exactHead, authority: authority, operation: operation,
        postActivationPolicy: postActivationPolicy, rollbackCompatibility: rollbackCompatibility,
        revision: revision, mutationID: mutationID, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let promotedReleaseRecordID, sandboxRunID: UUID; let semanticDiff: PackageSemanticDiffV1; let predecessorPointerSHA256, resultingPointerSHA256: String; let declaredActor: ActorSnapshotV1; let exactHead: String; let authority: PackagePromotionAuthorityV1; let operation: PackagePromotionOperationV1; let postActivationPolicy: PackagePostActivationPolicyV1; let rollbackCompatibility: PackageRollbackCompatibilityV1; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date }
}

struct PackagePromotionAtomicBundleV1:Sendable{let promotedRelease:PromotedPackageReleaseV1;let sandboxRun:PackageSandboxRunV1;let semanticDiff:PackageSemanticDiffV1;let predecessorPointer:ActivePackageRegistryPointerV1?;let resultingPointer:ActivePackageRegistryPointerV1;let actor:ActorSnapshotV1;let receipt:PackagePromotionReceiptV1;func validate()throws{guard receipt.semanticDiff==semanticDiff,receipt.declaredActor==actor else{throw PackageEvolutionFailureV1.incompatiblePromotion};try receipt.validate(promotedRelease:promotedRelease,sandboxRun:sandboxRun,predecessorPointer:predecessorPointer,resultingPointer:resultingPointer)}}

/// Complete durable PACKAGE_EVOLUTION_V1 closure used by restore, replay,
/// diagnostics and lifecycle consumers. DraftUpgradePlanV1 is intentionally
/// absent because it is a zero-write C36 preview.
struct PackageEvolutionLifecycleClosureV1: Codable, Equatable, Sendable {
    let promotedReleases: [PromotedPackageReleaseV1]
    let sandboxRuns: [PackageSandboxRunV1]
    let promotionReceipts: [PackagePromotionReceiptV1]
    let activePointers: [ActivePackageRegistryPointerV1]

    init(promotedReleases: [PromotedPackageReleaseV1],
         sandboxRuns: [PackageSandboxRunV1],
         promotionReceipts: [PackagePromotionReceiptV1],
         activePointers: [ActivePackageRegistryPointerV1]) throws {
        self.promotedReleases = promotedReleases.sorted { $0.releaseRecordID.uuidString < $1.releaseRecordID.uuidString }
        self.sandboxRuns = sandboxRuns.sorted { $0.runID.uuidString < $1.runID.uuidString }
        self.promotionReceipts = promotionReceipts.sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }
        self.activePointers = activePointers.sorted { $0.pointerID.uuidString < $1.pointerID.uuidString }
        try validate()
    }

    func validate() throws {
        try promotedReleases.forEach { try $0.validate() }; try sandboxRuns.forEach { try $0.validate() }
        try promotionReceipts.forEach { try $0.validate() }; try activePointers.forEach { try $0.validate() }
        guard Set(promotedReleases.map(\.releaseRecordID)).count == promotedReleases.count,
              Set(sandboxRuns.map(\.runID)).count == sandboxRuns.count,
              Set(promotionReceipts.map(\.receiptID)).count == promotionReceipts.count,
              Set(activePointers.map(\.pointerID)).count == activePointers.count else {
            throw PackageEvolutionFailureV1.invalidValue
        }
        let releases = Dictionary(uniqueKeysWithValues: promotedReleases.map { ($0.releaseRecordID, $0) })
        let runs = Dictionary(uniqueKeysWithValues: sandboxRuns.map { ($0.runID, $0) })
        let pointers = Dictionary(uniqueKeysWithValues: activePointers.map { ($0.pointerSHA256, $0) })
        for receipt in promotionReceipts {
            guard let release = releases[receipt.promotedReleaseRecordID],
                  let run = runs[receipt.sandboxRunID],
                  let pointer = pointers[receipt.resultingPointerSHA256] else {
                throw PackageEvolutionFailureV1.incompatiblePromotion
            }
            let predecessor = receipt.predecessorPointerSHA256 == String(repeating: "0", count: 64)
                ? nil : pointers[receipt.predecessorPointerSHA256]
            guard predecessor != nil || receipt.predecessorPointerSHA256 == String(repeating: "0", count: 64) else {
                throw PackageEvolutionFailureV1.stalePointer
            }
            try receipt.validate(promotedRelease: release, sandboxRun: run,
                                 predecessorPointer: predecessor, resultingPointer: pointer)
        }
    }
}

enum PackageEvolutionCanonicalCodecV1{static func encode<T:Codable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy = .millisecondsSince1970;return try e.encode(value)};static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=4_194_304 else{throw PackageEvolutionFailureV1.limitExceeded};let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);guard try encode(value)==data else{throw PackageEvolutionFailureV1.nonCanonicalData};return value}}

enum PackageEvolutionLifecycleV1{static let schema="PACKAGE_EVOLUTION_V1";static let persistent=true;static let migrationRequired=true;static let backupRestoreRequired=true;static let deleteEraseRequired=true;static let exportReportRequired=true;static let searchRebuildReplayRequired=true;static let postActivationPolicy=PackagePostActivationPolicyV1.forwardFixOnly;static let rollbackOperationAvailable=false;static let downgradePolicy="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION";static let interruption="OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID";static let writer="SOLE_CANONICAL_WORKSPACE_WRITER"}

private extension UUID { static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) }

extension PackagePromotionAtomicBundleV1 {
    func validateClientCapabilityAdmission(_ closure: ClientCapabilityLifecycleClosureV1) throws {
        try validate(); try closure.validate()
        guard closure.profile.workspaceID == promotedRelease.workspaceID,
              closure.release.packageReleaseID == promotedRelease.packageRelease.packageReleaseID,
              closure.release.packageSHA256 == promotedRelease.packageRelease.packageSHA256,
              closure.release.workflowSHA256 == promotedRelease.packageRelease.workflowSHA256,
              closure.decision.operation == .upgradeDraft,
              closure.decision.admission == .readWrite else {
            throw PackageEvolutionFailureV1.incompatiblePromotion
        }
    }
}
