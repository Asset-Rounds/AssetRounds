import Foundation

enum GuidedSurveyRestoreIdentityPolicyV1 {
    static func remintsWorkspace(_ mode: BackupRestoreMode) -> Bool {
        mode == .clone || mode == .fork
    }
    static let publicationSubjectIsFrozenAtPublication = true
}

enum BackupRestoreMode: String, CaseIterable, Codable, Equatable, Sendable {
    case emptyInstall = "empty_install"
    case replaceExisting = "replace_existing"
    case clone
    case fork
}

enum AccessibleDocumentRestoreIdentityDispositionV1:String,Codable,Equatable,Sendable{
    case preserveAcceptedSourceBinding="PRESERVE_ACCEPTED_SOURCE_BINDING"
    case reboundAsIncompleteHistoricSourceEvidence="REBOUND_AS_INCOMPLETE_HISTORIC_SOURCE_EVIDENCE"
    static func resolve(_ mode:BackupRestoreMode)->Self{switch mode{case .emptyInstall,.replaceExisting:return .preserveAcceptedSourceBinding;case .clone,.fork:return .reboundAsIncompleteHistoricSourceEvidence}}
}

/// Locator restore identity is deliberately separate from the generic record
/// disposition.  A replacement in the same workspace can retain a public
/// signed payload, while a clone/fork must make the source signature historic
/// and bind a destination-safe external representation.
enum AssetLocatorRestoreIdentityDispositionV1: String, Codable, Equatable, Sendable {
    case preservePublicSignedPayload = "PRESERVE_PUBLIC_SIGNED_PAYLOAD"
    case reboundAsHistoricSourceEvidence = "REBOUND_AS_HISTORIC_SOURCE_EVIDENCE"

    static func resolve(_ mode: BackupRestoreMode) -> Self {
        switch mode {
        case .emptyInstall, .replaceExisting:
            return .preservePublicSignedPayload
        case .clone, .fork:
            return .reboundAsHistoricSourceEvidence
        }
    }
}

/// Schedule releases and occurrence history are immutable workspace records.
/// A same-workspace replacement keeps their canonical bytes; clone/fork
/// rebinding preserves the history as historic source provenance and never
/// activates source-local notification state.
enum ScheduleRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 27
    static let recordsSchemaVersion = 26
    static let durableFamilyCount = 2
    static let sameWorkspacePreservesImmutableBytes = true
    static let cloneForkSourceScheduleAutomaticallyActive = false
    static let dueAndReminderProjectionsRebuilt = true
    static let notificationStateRestoredAsTruth = false

    static func validate() throws {
        guard persistentSchemaVersion == 27,
              recordsSchemaVersion == 26,
              durableFamilyCount == 2,
              sameWorkspacePreservesImmutableBytes,
              !cloneForkSourceScheduleAutomaticallyActive,
              dueAndReminderProjectionsRebuilt,
              !notificationStateRestoredAsTruth else {
            throw RestoreIdentityDecisionError.invalidMode
        }
    }

    static func preservesImmutableBytes(for mode: BackupRestoreMode) -> Bool {
        switch mode {
        case .emptyInstall, .replaceExisting:
            return sameWorkspacePreservesImmutableBytes
        case .clone, .fork:
            return false
        }
    }
}

enum PlanRestoreIdentityDispositionV1: String, Codable, Equatable, Sendable {
    case preserveSameWorkspaceBytes = "PRESERVE_SAME_WORKSPACE_BYTES"
    case historicRebindForCloneOrFork = "HISTORIC_REBIND_FOR_CLONE_OR_FORK"

    static func resolve(_ mode: BackupRestoreMode) -> Self {
        switch mode {
        case .emptyInstall, .replaceExisting: return .preserveSameWorkspaceBytes
        case .clone, .fork: return .historicRebindForCloneOrFork
        }
    }
}

/// Plan documents, revisions, normalized frames, placements, and approved
/// rebase receipts are immutable history.  A clone/fork gets explicit
/// destination bindings; a source release is never silently made active.
enum PlanRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 28
    static let recordsSchemaVersion = 27
    static let durableFamilyCount = 4
    static let derivedPreviewRebuilt = true
    static let sourcePlanAutomaticallyActive = false

    static func validate() throws {
        guard persistentSchemaVersion == PlanPersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == PlanPersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount == PlanPersistenceEnrollmentV1.durableModelCount,
              derivedPreviewRebuilt,
              !sourcePlanAutomaticallyActive else {
            throw RestoreIdentityDecisionErrorV1.invalidMode
        }
    }

    static func preservesImmutableBytes(for mode: BackupRestoreMode) -> Bool {
        PlanRestoreIdentityDispositionV1.resolve(mode) == .preserveSameWorkspaceBytes
    }

    static func validate(records: [V28BackupPlanRecordV1]) throws {
        try validate()
        do { _ = try PlanBackupRecordSetV1.decode(records) }
        catch { throw RestoreIdentityDecisionErrorV1.invalidMode }
    }
}

enum PlacementPoseRestoreIdentityDispositionV1: String, Codable, Equatable, Sendable {
    case preserveSameWorkspaceBytes = "PRESERVE_SAME_WORKSPACE_BYTES"
    case historicRebindForCloneOrFork = "HISTORIC_REBIND_FOR_CLONE_OR_FORK"

    static func resolve(_ mode: BackupRestoreMode) -> Self {
        switch mode {
        case .emptyInstall, .replaceExisting:
            return .preserveSameWorkspaceBytes
        case .clone, .fork:
            return .historicRebindForCloneOrFork
        }
    }
}

/// Pose events and anchor observations are the only C37 durable families.
/// Current tips/snapshots are reconstructed; clone/fork rebinding is explicit
/// and source history can never be treated as a destination-live tip.
enum PlacementPoseRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 29
    static let recordsSchemaVersion = 28
    static let durableFamilyCount = 2
    static let derivedProjectionRebuilt = true
    static let cloneForkSourcePoseAutomaticallyActive = false
    static let sensorProposalPersistence = "NONPERSISTENT"

    static func validate() throws {
        guard persistentSchemaVersion == PlacementPosePersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == PlacementPosePersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount == PlacementPosePersistenceEnrollmentV1.durableModelCount,
              derivedProjectionRebuilt,
              !cloneForkSourcePoseAutomaticallyActive,
              sensorProposalPersistence == "NONPERSISTENT" else {
            throw RestoreIdentityDecisionErrorV1.invalidMode
        }
    }

    static func preservesImmutableBytes(for mode: BackupRestoreMode) -> Bool {
        PlacementPoseRestoreIdentityDispositionV1.resolve(mode)
            == .preserveSameWorkspaceBytes
    }

    static func validate(records: [V29BackupPlacementPoseRecordV1]) throws {
        try validate()
        do {
            _ = try PlacementPoseBackupRecordSetV1.decode(records)
        } catch {
            throw RestoreIdentityDecisionErrorV1.invalidMode
        }
    }
}

extension RestoreIdentityV1 {
    func destinationWorkResourceMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        let id = Self.deterministicUUID(
            namespace: "work-resource-restore:\(targetPointer.generationID.uuidString.lowercased())",
            sourceID: sourceID.rawValue,
            workspaceID: targetPointer.workspaceID
        )
        return try MutationIDV1(rawValue: id)
    }

    func destinationActivityContractMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        let digest = CanonicalJSONV1.sha256(Data(
            "activity-contract-restore\u{0}\(sourceID.rawValue.uuidString.lowercased())\u{0}\(targetPointer.workspaceID.uuidString.lowercased())\u{0}\(targetPointer.generationID.uuidString.lowercased())".utf8
        ))
        var bytes = stride(from: 0, to: 32, by: 2).map {
            UInt8(digest.dropFirst($0).prefix(2), radix: 16) ?? 0
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return try MutationIDV1(rawValue: UUID(uuid: (
            bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
            bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]
        )))
    }

    func destinationOperationalContactMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        let digest = CanonicalJSONV1.sha256(Data(
            "operational-contact-restore\u{0}\(sourceID.rawValue.uuidString.lowercased())\u{0}\(targetPointer.workspaceID.uuidString.lowercased())\u{0}\(targetPointer.generationID.uuidString.lowercased())".utf8
        ))
        var bytes = stride(from: 0, to: 32, by: 2).map {
            UInt8(digest.dropFirst($0).prefix(2), radix: 16) ?? 0
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return try MutationIDV1(rawValue: UUID(uuid: (
            bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
            bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]
        )))
    }

    func destinationAcceptedLabelMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        let digest = CanonicalJSONV1.sha256(Data(
            "accepted-label-restore\u{0}\(sourceID.rawValue.uuidString.lowercased())\u{0}\(targetPointer.workspaceID.uuidString.lowercased())\u{0}\(targetPointer.generationID.uuidString.lowercased())".utf8
        ))
        var bytes = stride(from: 0, to: 32, by: 2).map {
            UInt8(digest.dropFirst($0).prefix(2), radix: 16) ?? 0
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return try MutationIDV1(rawValue: UUID(uuid: (
            bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
            bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]
        )))
    }

    func destinationPackageEvolutionWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }

    func destinationMeasurementIntegrityWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }

    func destinationPrivacyTransformWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }
    func destinationClientCapabilityWorkspaceID() -> WorkspaceID { WorkspaceID(rawValue: targetPointer.workspaceID) }
    func destinationRecoverabilityWorkspaceID() -> WorkspaceID { WorkspaceID(rawValue: targetPointer.workspaceID) }
    func destinationFieldReferenceWorkspaceID()->WorkspaceID{WorkspaceID(rawValue:targetPointer.workspaceID)}
    func destinationPlanWorkspaceID() -> WorkspaceID { WorkspaceID(rawValue: targetPointer.workspaceID) }
    func destinationPlacementPoseWorkspaceID() -> WorkspaceID { WorkspaceID(rawValue: targetPointer.workspaceID) }
    func placementPoseDisposition() -> PlacementPoseRestoreIdentityDispositionV1 {
        PlacementPoseRestoreIdentityDispositionV1.resolve(mode)
    }
    func preservesPlacementPoseImmutableBytes() -> Bool {
        PlacementPoseRestoreIdentityPolicyV1.preservesImmutableBytes(for: mode)
    }
    func assetLocatorDisposition() -> AssetLocatorRestoreIdentityDispositionV1 {
        AssetLocatorRestoreIdentityDispositionV1.resolve(mode)
    }
    func preservesAssetLocatorPublicSignedPayload() -> Bool {
        assetLocatorDisposition() == .preservePublicSignedPayload
    }
    func planDisposition() -> PlanRestoreIdentityDispositionV1 {
        PlanRestoreIdentityDispositionV1.resolve(mode)
    }
    func preservesPlanImmutableBytes() -> Bool {
        PlanRestoreIdentityPolicyV1.preservesImmutableBytes(for: mode)
    }
    static let packageEvolutionIdentityRule = "PRESERVE_RELEASE_RUN_RECEIPT_POINTER_IDS_REBIND_WORKSPACE_AND_DIGESTS"
}

enum RestoreRecordIdentityDispositionV1: String, Codable, Equatable, Sendable {
    case preserve
}

/// Identity copied from the immutable backup manifest. It is provenance only:
/// `replicaID` must never be selected as the destination's active writer.
struct RestoreSourceIdentityV1: Codable, Equatable, Sendable {
    let workspaceID: UUID?
    let replicaID: UUID?
}

/// Complete identity of one published generation pointer. Binding the manifest
/// digest as well as IDs prevents recovery from accepting a same-name but
/// different generation.
struct RestorePointerIdentityV1: Codable, Equatable, Sendable {
    let generationID: UUID
    let generationManifestSHA256: String
    let knownReplicaIDs: [UUID]
    let workspaceID: UUID
    let replicaID: UUID

    init(
        generationID: UUID,
        generationManifestSHA256: String,
        knownReplicaIDs: Set<UUID> = [],
        workspaceID: UUID,
        replicaID: UUID
    ) {
        var history = knownReplicaIDs
        history.insert(replicaID)
        self.generationID = generationID
        self.generationManifestSHA256 = generationManifestSHA256
        self.knownReplicaIDs = history.sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }
        self.workspaceID = workspaceID
        self.replicaID = replicaID
    }
}

struct RestoreIdentityDecisionInputV1: Equatable, Sendable {
    let mode: BackupRestoreMode
    let source: RestoreSourceIdentityV1
    let oldPointer: RestorePointerIdentityV1
    let targetGenerationID: UUID
    let targetGenerationManifestSHA256: String
    let allocatedWorkspaceID: UUID?
    let allocatedReplicaID: UUID?
    let unavailableWorkspaceIDs: Set<UUID>
    let unavailableReplicaIDs: Set<UUID>

    init(
        mode: BackupRestoreMode,
        source: RestoreSourceIdentityV1,
        oldPointer: RestorePointerIdentityV1,
        targetGenerationID: UUID,
        targetGenerationManifestSHA256: String,
        allocatedWorkspaceID: UUID? = nil,
        allocatedReplicaID: UUID? = nil,
        unavailableWorkspaceIDs: Set<UUID> = [],
        unavailableReplicaIDs: Set<UUID> = []
    ) {
        self.mode = mode
        self.source = source
        self.oldPointer = oldPointer
        self.targetGenerationID = targetGenerationID
        self.targetGenerationManifestSHA256 = targetGenerationManifestSHA256
        self.allocatedWorkspaceID = allocatedWorkspaceID
        self.allocatedReplicaID = allocatedReplicaID
        self.unavailableWorkspaceIDs = unavailableWorkspaceIDs
        self.unavailableReplicaIDs = unavailableReplicaIDs
    }
}

struct RestoreIdentityV1: Equatable, Sendable {
    let mode: BackupRestoreMode
    let source: RestoreSourceIdentityV1
    let oldPointer: RestorePointerIdentityV1
    let targetPointer: RestorePointerIdentityV1
    let recordIdentityDisposition: RestoreRecordIdentityDispositionV1

    func destinationRecordID(for sourceRecordID: UUID) -> UUID? {
        sourceRecordID
    }

    func destinationFunctionalRelationshipWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }

    func destinationFunctionalRelationshipRecordID(for sourceID: UUID) -> UUID? {
        destinationRecordID(for: sourceID)
    }

    func destinationEvidenceAssuranceWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }

    func destinationInspectionReviewWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }

    func destinationWorkPacketWorkspaceID()->WorkspaceID{WorkspaceID(rawValue:targetPointer.workspaceID)}

    func destinationFieldDraftWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: targetPointer.workspaceID)
    }

    /// Draft operational identities are preserved by exact replacement but
    /// must be deterministically remapped by clone/fork to prevent a restored
    /// scratch lease or reservation from aliasing the source workspace.
    func destinationFieldDraftID(for sourceID: UUID, namespace: String) -> UUID? {
        switch mode {
        case .emptyInstall, .replaceExisting: return sourceID
        case .clone, .fork:
            return Self.deterministicUUID(
                namespace: namespace,
                sourceID: sourceID,
                workspaceID: targetPointer.workspaceID
            )
        }
    }

    func destinationInspectionReviewRecordID(for sourceID: UUID) -> UUID? {
        destinationRecordID(for: sourceID)
    }
}

private extension RestoreIdentityV1 {
    static func deterministicUUID(namespace: String, sourceID: UUID, workspaceID: UUID) -> UUID {
        let digest = CanonicalJSONV1.sha256(Data("field-draft\u{0}\(namespace)\u{0}\(sourceID.uuidString.lowercased())\u{0}\(workspaceID.uuidString.lowercased())".utf8))
        var bytes = stride(from: 0, to: 32, by: 2).map { offset -> UInt8 in
            UInt8(digest.dropFirst(offset).prefix(2), radix: 16) ?? 0
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

enum RestoreIdentityDecisionErrorV1: Error, Equatable {
    case missingSourceIdentity
    case invalidPointerIdentity
    case invalidMode
    case workspaceCollision
    case replicaCollision
    case sourceReplicaReuse
}

/// Pure identity transformation authority. UUID allocation happens before this
/// function; the decision only validates and freezes the proposed identities.
enum RestoreIdentityDecisionV1 {
    static func decide(
        _ input: RestoreIdentityDecisionInputV1
    ) throws -> RestoreIdentityV1 {
        guard validPointer(input.oldPointer),
              validSHA256(input.targetGenerationManifestSHA256),
              input.targetGenerationID != input.oldPointer.generationID else {
            throw RestoreIdentityDecisionErrorV1.invalidPointerIdentity
        }
        guard let sourceWorkspaceID = input.source.workspaceID,
              let sourceReplicaID = input.source.replicaID,
              sourceWorkspaceID != sourceReplicaID else {
            throw RestoreIdentityDecisionErrorV1.missingSourceIdentity
        }

        let workspaceID: UUID
        let replicaID: UUID
        let recordDisposition: RestoreRecordIdentityDispositionV1

        switch input.mode {
        case .emptyInstall:
            workspaceID = sourceWorkspaceID
            replicaID = try destinationReplica(
                proposed: input.allocatedReplicaID,
                source: sourceReplicaID,
                retaining: nil,
                unavailable: input.unavailableReplicaIDs
            )
            recordDisposition = .preserve

        case .replaceExisting:
            workspaceID = input.oldPointer.workspaceID
            replicaID = try destinationReplica(
                proposed: input.allocatedReplicaID,
                source: sourceReplicaID,
                retaining: input.oldPointer.replicaID,
                unavailable: input.unavailableReplicaIDs
            )
            recordDisposition = .preserve

        case .clone:
            workspaceID = try distinctWorkspace(
                input.allocatedWorkspaceID,
                source: sourceWorkspaceID,
                old: input.oldPointer.workspaceID,
                unavailable: input.unavailableWorkspaceIDs
            )
            replicaID = try destinationReplica(
                proposed: input.allocatedReplicaID,
                source: sourceReplicaID,
                retaining: nil,
                unavailable: input.unavailableReplicaIDs
            )
            recordDisposition = .preserve

        case .fork:
            workspaceID = try distinctWorkspace(
                input.allocatedWorkspaceID,
                source: sourceWorkspaceID,
                old: input.oldPointer.workspaceID,
                unavailable: input.unavailableWorkspaceIDs
            )
            replicaID = try destinationReplica(
                proposed: input.allocatedReplicaID,
                source: sourceReplicaID,
                retaining: nil,
                unavailable: input.unavailableReplicaIDs
            )
            recordDisposition = .preserve
        }

        var targetReplicaHistory = Set(input.oldPointer.knownReplicaIDs)
        targetReplicaHistory.insert(sourceReplicaID)
        targetReplicaHistory.insert(replicaID)
        let targetPointer = RestorePointerIdentityV1(
            generationID: input.targetGenerationID,
            generationManifestSHA256: input.targetGenerationManifestSHA256,
            knownReplicaIDs: targetReplicaHistory,
            workspaceID: workspaceID,
            replicaID: replicaID
        )
        guard validPointer(targetPointer),
              targetPointer.replicaID != sourceReplicaID else {
            throw RestoreIdentityDecisionErrorV1.sourceReplicaReuse
        }
        return RestoreIdentityV1(
            mode: input.mode,
            source: input.source,
            oldPointer: input.oldPointer,
            targetPointer: targetPointer,
            recordIdentityDisposition: recordDisposition
        )
    }
}

private extension RestoreIdentityDecisionV1 {
    static func destinationReplica(
        proposed: UUID?,
        source: UUID,
        retaining existing: UUID?,
        unavailable: Set<UUID>
    ) throws -> UUID {
        if let existing,
           existing != source,
           !unavailable.contains(existing) {
            return existing
        }
        guard let proposed else {
            if existing == source {
                throw RestoreIdentityDecisionErrorV1.sourceReplicaReuse
            }
            throw RestoreIdentityDecisionErrorV1.replicaCollision
        }
        guard proposed != source else {
            throw RestoreIdentityDecisionErrorV1.sourceReplicaReuse
        }
        guard !unavailable.contains(proposed) else {
            throw RestoreIdentityDecisionErrorV1.replicaCollision
        }
        return proposed
    }

    static func distinctWorkspace(
        _ proposed: UUID?,
        source: UUID,
        old: UUID,
        unavailable: Set<UUID>
    ) throws -> UUID {
        guard let proposed,
              proposed != source,
              proposed != old,
              !unavailable.contains(proposed) else {
            throw RestoreIdentityDecisionErrorV1.workspaceCollision
        }
        return proposed
    }

    static func validPointer(_ value: RestorePointerIdentityV1) -> Bool {
        validSHA256(value.generationManifestSHA256)
            && value.generationID != value.workspaceID
            && value.generationID != value.replicaID
            && value.workspaceID != value.replicaID
            && !value.knownReplicaIDs.isEmpty
            && value.knownReplicaIDs.count <= 64
            && value.knownReplicaIDs == value.knownReplicaIDs.sorted {
                $0.uuidString.lowercased() < $1.uuidString.lowercased()
            }
            && Set(value.knownReplicaIDs).count == value.knownReplicaIDs.count
            && value.knownReplicaIDs.contains(value.replicaID)
    }

    static func validSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                (48...57).contains(Int($0.value))
                    || (97...102).contains(Int($0.value))
            }
    }
}

/// C25 keeps survey lifecycle authority in mutation history. Replacement may
/// preserve the exact two durable values; clone/fork must project them into
/// the destination workspace while retaining immutable definition/release IDs.
enum SurveyDefinitionRestoreIdentityPolicyV1 {
    static func validate(
        record: V24BackupSurveyDefinitionRecordV1,
        decision: RestoreIdentityV1?
    ) throws {
        guard let decision else { return }
        switch decision.mode {
        case .emptyInstall, .replaceExisting:
            guard record.workspaceID == decision.source.workspaceID else {
                throw RestoreIdentityDecisionErrorV1.workspaceCollision
            }
        case .clone, .fork:
            guard decision.targetPointer.workspaceID != decision.source.workspaceID,
                  record.workspaceID == decision.targetPointer.workspaceID else {
                throw RestoreIdentityDecisionErrorV1.workspaceCollision
            }
        }
    }
}

/// Restore keeps context bytes immutable in the same workspace and makes a
/// clone/fork explicitly historic until a user records a new successor.
enum C30EvidenceContextRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 30
    static let recordsSchemaVersion = 29
    static let durableFamilyCount = 2
    static let cloneForkSourceContextAutomaticallyActive = false
    static let preservesImmutableBytes = true

    static func disposition(for mode: BackupRestoreMode) -> String {
        switch mode {
        case .clone, .fork: return "REBOUND_HISTORIC_SOURCE_EVIDENCE"
        case .emptyInstall, .replaceExisting: return "PRESERVE_ACCEPTED_SOURCE_BINDING"
        }
    }

    static func validate(_ rows: [V30BackupEvidenceContextRecordV1]) throws {
        guard persistentSchemaVersion == 30, recordsSchemaVersion == 29,
              durableFamilyCount == 2, !cloneForkSourceContextAutomaticallyActive,
              preservesImmutableBytes else { throw EvidenceContextFailureV1.invalidValue }
        _ = try EvidenceContextBackupRecordSetV1.decode(rows)
    }
}

/// Lighting records remain immutable source evidence. Same-workspace restore
/// preserves their canonical bytes; clone/fork callers must explicitly bind
/// a new workspace before treating any restored root as current.
enum C31LightingRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 31
    static let recordsSchemaVersion = 30
    static let durableFamilyCount = 5
    static let sameWorkspacePreservesImmutableBytes = true
    static let cloneForkRequiresExplicitHistoricRebind = true
    static let sourceClaimNeverBecomesActive = true

    static func disposition(for mode: BackupRestoreMode) -> String {
        switch mode {
        case .emptyInstall, .replaceExisting:
            return "PRESERVE_SAME_WORKSPACE_LIGHTING_BYTES"
        case .clone, .fork:
            return "EXPLICIT_HISTORIC_LIGHTING_REBIND_REQUIRED"
        }
    }

    static func validate(_ rows: [V31BackupLightingRecordV1],
                         mode: BackupRestoreMode) throws {
        guard persistentSchemaVersion == 31,
              recordsSchemaVersion == 30,
              durableFamilyCount == V31BackupLightingRecordV1.Kind.allCases.count,
              sameWorkspacePreservesImmutableBytes,
              cloneForkRequiresExplicitHistoricRebind,
              sourceClaimNeverBecomesActive else {
            throw LightingContractFailureV1.invalidValue
        }
        _ = disposition(for: mode)
        _ = try LightingBackupRecordSetV1.decode(rows)
    }
}

/// C32 receipts are immutable canonical-mutation provenance. Same-workspace
/// restore preserves them as active history. Clone/fork preserves the exact
/// source receipt and its outer journal receipt as historic source provenance;
/// neither row is rebound or made authoritative for the destination workspace.
enum C32AssistanceRestoreProvenanceDispositionV1: String, Equatable, Sendable {
    case activeWorkspace = "ACTIVE_WORKSPACE_ACCEPTANCE_PROVENANCE"
    case historicSource = "TRANSITIVE_HISTORIC_SOURCE_ACCEPTANCE_PROVENANCE"
}

enum C32AssistanceRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 32
    static let recordsSchemaVersion = 31
    static let durableFamilyCount = 1
    static let proposalPersistence = "NONPERSISTENT"
    static let historicSourceProvenanceIsTransitivelyPortable = true

    static func disposition(for mode: BackupRestoreMode) -> String {
        switch mode {
        case .emptyInstall, .replaceExisting: return "PRESERVE_CANONICAL_ACCEPTANCE_PROVENANCE"
        case .clone, .fork: return "PRESERVE_TRANSITIVE_HISTORIC_SOURCE_ACCEPTANCE_PROVENANCE"
        }
    }

    /// The immutable receipt/journal pair carries its original workspace
    /// identity through every descendant. Equality with the destination is
    /// the only condition that can make the provenance active there.
    static func provenanceDisposition(
        receiptWorkspaceID: UUID,
        targetWorkspaceID: UUID,
        mode: BackupRestoreMode
    ) throws -> C32AssistanceRestoreProvenanceDispositionV1 {
        if receiptWorkspaceID == targetWorkspaceID {
            guard mode != .clone && mode != .fork else {
                throw AssistanceContractFailureV1.invalidReceipt
            }
            return .activeWorkspace
        }
        return .historicSource
    }

    static func validate(_ records: [V32BackupAssistanceAcceptanceRecordV1],
                         mode: BackupRestoreMode) throws {
        guard persistentSchemaVersion == AssistancePersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == AssistancePersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount == AssistancePersistenceEnrollmentV1.durableModelCount,
              proposalPersistence == "NONPERSISTENT",
              historicSourceProvenanceIsTransitivelyPortable else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        for record in records { _ = try record.value() }
    }
}

/// C33 metadata is rebound for clone/fork, while the immutable original bytes
/// and their content digest are preserved exactly. Supporting derivative and
/// retention lineage remains inside the rebound clip and canonical journal.
enum C33TemporalEvidenceRestoreIdentityPolicyV1 {
    static let persistentSchemaVersion = 33
    static let recordsSchemaVersion = 32
    static let durableFamilyCount = 2
    static let directOriginalBytesRemainDigestIdentical = true
    static let cloneForkRebindsWorkspaceAndTargetAuthority = true

    static func validate(
        _ records: [V33BackupTemporalEvidenceRecordV1],
        mode: BackupRestoreMode
    ) throws {
        guard persistentSchemaVersion == TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount == TemporalEvidencePersistenceEnrollmentV1.durableModelCount,
              directOriginalBytesRemainDigestIdentical,
              cloneForkRebindsWorkspaceAndTargetAuthority else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        for record in records {
            switch record.kind {
            case .clip: _ = try record.clipValue()
            case .anchor: _ = try record.anchorValue()
            }
        }
        _ = mode
    }
}

enum C45AcceptedLabelRestoreIdentityBoundaryV1 { static let replacePreservesCanonicalSnapshot=true;static let cloneForkRebindsHistoricSnapshot=true;static let cloneForkActivatesReprint=false }

enum C48PortableExchangeRestoreIdentityDispositionV2: String, Codable, Sendable {
    case preserveAcceptedSessionAndCapability = "PRESERVE_ACCEPTED_SESSION_AND_CAPABILITY"
    case rebindHistoryAndInvalidateCapability = "REBIND_HISTORY_AND_INVALIDATE_CAPABILITY"

    static func resolve(_ mode: BackupRestoreMode) -> Self {
        switch mode {
        case .emptyInstall, .replaceExisting:
            return .preserveAcceptedSessionAndCapability
        case .clone, .fork:
            return .rebindHistoryAndInvalidateCapability
        }
    }
}

enum C49WorkResourceRestoreIdentityPolicyV1 {
    static func preservesCanonicalBytes(_ identity: RestoreIdentityV1) -> Bool {
        identity.source.workspaceID == identity.targetPointer.workspaceID
    }

    static func requiresHistoricRebinding(_ identity: RestoreIdentityV1) -> Bool {
        identity.source.workspaceID != identity.targetPointer.workspaceID
    }
}
