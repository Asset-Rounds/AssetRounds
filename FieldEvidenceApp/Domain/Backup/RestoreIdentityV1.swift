import Foundation

enum BackupRestoreMode: String, CaseIterable, Codable, Equatable, Sendable {
    case emptyInstall = "empty_install"
    case replaceExisting = "replace_existing"
    case clone
    case fork
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

    func destinationInspectionReviewRecordID(for sourceID: UUID) -> UUID? {
        destinationRecordID(for: sourceID)
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
