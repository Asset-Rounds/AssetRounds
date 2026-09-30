import Foundation

enum RecoverabilityVerificationFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion, invalidValue, invalidDigest, nonCanonicalData, limitExceeded
    case wrongWorkspace, wrongArchive, staleProof, unsupportedArchive, quarantined
    case liveWorkspaceMutationDetected, sourceArchiveMutationDetected, reconciliationFailed
    case replayDiverged, cleanupFailed, cancelled, partialEffect, divergentRetry, invalidSuccessor
}

enum RecoverabilityVerificationModeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case structureOnly = "STRUCTURE_ONLY"
    case isolatedDryRestore = "ISOLATED_DRY_RESTORE"
    case fullContentReconciliation = "FULL_CONTENT_RECONCILIATION"
}

enum RecoverabilityVerificationDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case passed = "PASSED"
    case failed = "FAILED"
    case unsupported = "UNSUPPORTED"
    case quarantined = "QUARANTINED"
    case cancelled = "CANCELLED"
}

enum RecoveryPointFreshnessDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case currentAtVerification = "CURRENT_AT_VERIFICATION"
    case historicAtVerification = "HISTORIC_AT_VERIFICATION"
    case historicNoncurrent = "HISTORIC_NONCURRENT"
}

enum RecoverabilityFindingCodeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case corruptArchive = "CORRUPT_ARCHIVE"
    case truncatedArchive = "TRUNCATED_ARCHIVE"
    case corruptRecord = "CORRUPT_RECORD"
    case corruptContent = "CORRUPT_CONTENT"
    case missingContent = "MISSING_CONTENT"
    case corruptCheckpoint = "CORRUPT_CHECKPOINT"
    case unsupportedSchema = "UNSUPPORTED_SCHEMA"
    case unsupportedClientCapability = "UNSUPPORTED_CLIENT_CAPABILITY"
    case wrongArchive = "WRONG_ARCHIVE"
    case staleFrontier = "STALE_FRONTIER"
    case replayDivergence = "REPLAY_DIVERGENCE"
    case cleanupIncomplete = "CLEANUP_INCOMPLETE"
    case liveWorkspaceChanged = "LIVE_WORKSPACE_CHANGED"
    case sourceArchiveChanged = "SOURCE_ARCHIVE_CHANGED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case storageUnavailable = "STORAGE_UNAVAILABLE"
    case cancelled = "CANCELLED"
}

enum RecoverabilityStagingStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case prepared = "PREPARED"
    case structureValidated = "STRUCTURE_VALIDATED"
    case dryRestored = "DRY_RESTORED"
    case contentReconciled = "CONTENT_RECONCILED"
    case replayed = "REPLAYED"
    case cleanupRequired = "CLEANUP_REQUIRED"
}

enum RecoverabilityValidationV1 {
    static let maximumArchiveBytes: Int64 = 1_073_741_824
    static let maximumFindings = 128
    static let maximumTokenBytes = 256

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw RecoverabilityVerificationFailureV1.invalidDigest }
    }

    static func token(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == trimmed, !value.isEmpty, value.utf8.count <= maximumTokenBytes,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
    }

    static let zeroUUID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

struct RecoverabilityClientCapabilityBindingV1: Codable, Equatable, Hashable, Sendable {
    let decisionID: UUID
    let decisionRevision: UInt64
    let decisionSHA256: String

    init(_ decision: ClientCapabilityAdmissionDecisionV1) throws {
        guard decision.decisionID != RecoverabilityValidationV1.zeroUUID, decision.revision > 0 else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try RecoverabilityValidationV1.digest(decision.decisionSHA256)
        decisionID = decision.decisionID
        decisionRevision = decision.revision
        decisionSHA256 = decision.decisionSHA256
    }

    func validate() throws {
        guard decisionID != RecoverabilityValidationV1.zeroUUID, decisionRevision > 0 else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try RecoverabilityValidationV1.digest(decisionSHA256)
    }
}

struct RecoverabilityVerifierBuildV1: Codable, Equatable, Hashable, Sendable {
    let semanticBuildID: String
    let executableSHA256: String
    let contractVersion: Int

    init(semanticBuildID: String, executableSHA256: String, contractVersion: Int = 1) throws {
        try RecoverabilityValidationV1.token(semanticBuildID)
        try RecoverabilityValidationV1.digest(executableSHA256)
        guard contractVersion > 0 else { throw RecoverabilityVerificationFailureV1.invalidValue }
        self.semanticBuildID = semanticBuildID
        self.executableSHA256 = executableSHA256
        self.contractVersion = contractVersion
    }

    func validate() throws {
        try RecoverabilityValidationV1.token(semanticBuildID)
        try RecoverabilityValidationV1.digest(executableSHA256)
        guard contractVersion > 0 else { throw RecoverabilityVerificationFailureV1.invalidValue }
    }
}

struct RecoveryPointFrontierV1: Codable, Equatable, Hashable, Sendable {
    let workspaceRevision: UInt64
    let lastLocalSequence: UInt64
    let checkpointID: String
    let checkpointFrontierSHA256: String

    init(workspaceRevision: UInt64, lastLocalSequence: UInt64, checkpointID: String,
         checkpointFrontierSHA256: String) throws {
        guard workspaceRevision > 0, lastLocalSequence <= workspaceRevision else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try RecoverabilityValidationV1.digest(checkpointID)
        try RecoverabilityValidationV1.digest(checkpointFrontierSHA256)
        self.workspaceRevision = workspaceRevision
        self.lastLocalSequence = lastLocalSequence
        self.checkpointID = checkpointID
        self.checkpointFrontierSHA256 = checkpointFrontierSHA256
    }

    func validate() throws {
        guard workspaceRevision > 0, lastLocalSequence <= workspaceRevision else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try RecoverabilityValidationV1.digest(checkpointID)
        try RecoverabilityValidationV1.digest(checkpointFrontierSHA256)
    }

    func freshness(relativeTo observed: Self) -> RecoveryPointFreshnessDispositionV1 {
        self == observed ? .currentAtVerification : .historicAtVerification
    }
}

struct RecoverabilityArchiveIdentityV1: Codable, Equatable, Hashable, Sendable {
    let sourceWorkspaceID: WorkspaceID
    let sourceGenerationID: UUID
    let archiveByteCount: Int64
    let archiveSHA256: String
    let archiveManifestSHA256: String
    let recordsSHA256: String
    let contentManifestSHA256: String
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let frontier: RecoveryPointFrontierV1
    let clientCapability: RecoverabilityClientCapabilityBindingV1

    init(sourceWorkspaceID: WorkspaceID, sourceGenerationID: UUID, archiveByteCount: Int64,
         archiveSHA256: String, archiveManifestSHA256: String, recordsSHA256: String,
         contentManifestSHA256: String, persistentSchemaVersion: Int, recordsSchemaVersion: Int,
         frontier: RecoveryPointFrontierV1,
         clientCapability: RecoverabilityClientCapabilityBindingV1) throws {
        self.sourceWorkspaceID = sourceWorkspaceID; self.sourceGenerationID = sourceGenerationID
        self.archiveByteCount = archiveByteCount; self.archiveSHA256 = archiveSHA256
        self.archiveManifestSHA256 = archiveManifestSHA256; self.recordsSHA256 = recordsSHA256
        self.contentManifestSHA256 = contentManifestSHA256
        self.persistentSchemaVersion = persistentSchemaVersion; self.recordsSchemaVersion = recordsSchemaVersion
        self.frontier = frontier; self.clientCapability = clientCapability
        try validate()
    }

    func validate() throws {
        guard sourceGenerationID != RecoverabilityValidationV1.zeroUUID,
              archiveByteCount > 0, archiveByteCount <= RecoverabilityValidationV1.maximumArchiveBytes,
              persistentSchemaVersion > 0, recordsSchemaVersion > 0 else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try [archiveSHA256, archiveManifestSHA256, recordsSHA256, contentManifestSHA256]
            .forEach(RecoverabilityValidationV1.digest)
        try frontier.validate(); try clientCapability.validate()
    }
}

struct RecoverabilityVerificationPlanV1: Codable, Equatable, Sendable {
    let verificationID: UUID
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let archive: RecoverabilityArchiveIdentityV1
    let mode: RecoverabilityVerificationModeV1
    let observedSourceFrontier: RecoveryPointFrontierV1
    let verifierBuild: RecoverabilityVerifierBuildV1
    let supersedesReceiptID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let plannedAt: Date
    let planSHA256: String

    init(verificationID: UUID, receiptID: UUID, workspaceID: WorkspaceID,
         archive: RecoverabilityArchiveIdentityV1, mode: RecoverabilityVerificationModeV1,
         observedSourceFrontier: RecoveryPointFrontierV1,
         verifierBuild: RecoverabilityVerifierBuildV1,
         supersedesReceiptID: UUID? = nil, revision: UInt64 = 1,
         mutationID: MutationIDV1, plannedAt: Date) throws {
        self.verificationID = verificationID; self.receiptID = receiptID; self.workspaceID = workspaceID
        self.archive = archive; self.mode = mode; self.observedSourceFrontier = observedSourceFrontier
        self.verifierBuild = verifierBuild; self.supersedesReceiptID = supersedesReceiptID
        self.revision = revision; self.mutationID = mutationID; self.plannedAt = plannedAt
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            verificationID: verificationID, receiptID: receiptID, workspaceID: workspaceID,
            archive: archive, mode: mode, observedSourceFrontier: observedSourceFrontier,
            verifierBuild: verifierBuild, supersedesReceiptID: supersedesReceiptID,
            revision: revision, mutationID: mutationID, plannedAt: plannedAt))
        try validate()
    }

    func validate() throws {
        try archive.validate(); try observedSourceFrontier.validate(); try verifierBuild.validate()
        guard verificationID != RecoverabilityValidationV1.zeroUUID,
              receiptID != RecoverabilityValidationV1.zeroUUID,
              workspaceID == archive.sourceWorkspaceID, revision > 0,
              (supersedesReceiptID == nil) == (revision == 1),
              planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(
                verificationID: verificationID, receiptID: receiptID, workspaceID: workspaceID,
                archive: archive, mode: mode, observedSourceFrontier: observedSourceFrontier,
                verifierBuild: verifierBuild, supersedesReceiptID: supersedesReceiptID,
                revision: revision, mutationID: mutationID, plannedAt: plannedAt))) else {
            throw RecoverabilityVerificationFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable {
        let verificationID: UUID; let receiptID: UUID; let workspaceID: WorkspaceID
        let archive: RecoverabilityArchiveIdentityV1; let mode: RecoverabilityVerificationModeV1
        let observedSourceFrontier: RecoveryPointFrontierV1; let verifierBuild: RecoverabilityVerifierBuildV1
        let supersedesReceiptID: UUID?; let revision: UInt64; let mutationID: MutationIDV1; let plannedAt: Date
    }
}

/// Derived-only staging identity. `stagingLocatorToken` is an opaque local
/// capability, never a path persisted into the verification receipt.
struct RecoverabilityVerificationStagingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let stagingID: UUID
    let verificationID: UUID
    let workspaceID: WorkspaceID
    let archive: RecoverabilityArchiveIdentityV1
    let mode: RecoverabilityVerificationModeV1
    let stagingLocatorToken: String
    let liveWorkspaceStateBeforeSHA256: String
    let sourceArchiveReadbackSHA256: String
    let state: RecoverabilityStagingStateV1
    let createdAt: Date
    let stagingSHA256: String

    init(stagingID: UUID, verificationID: UUID, workspaceID: WorkspaceID,
         archive: RecoverabilityArchiveIdentityV1, mode: RecoverabilityVerificationModeV1,
         stagingLocatorToken: String, liveWorkspaceStateBeforeSHA256: String,
         sourceArchiveReadbackSHA256: String, state: RecoverabilityStagingStateV1,
         createdAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.stagingID = stagingID; self.verificationID = verificationID
        self.workspaceID = workspaceID; self.archive = archive; self.mode = mode
        self.stagingLocatorToken = stagingLocatorToken
        self.liveWorkspaceStateBeforeSHA256 = liveWorkspaceStateBeforeSHA256
        self.sourceArchiveReadbackSHA256 = sourceArchiveReadbackSHA256; self.state = state; self.createdAt = createdAt
        stagingSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, stagingID: stagingID, verificationID: verificationID,
            workspaceID: workspaceID, archive: archive, mode: mode,
            stagingLocatorToken: stagingLocatorToken,
            liveWorkspaceStateBeforeSHA256: liveWorkspaceStateBeforeSHA256,
            sourceArchiveReadbackSHA256: sourceArchiveReadbackSHA256, state: state, createdAt: createdAt))
        try validate()
    }

    func validate() throws {
        try archive.validate(); try RecoverabilityValidationV1.token(stagingLocatorToken)
        try [liveWorkspaceStateBeforeSHA256, sourceArchiveReadbackSHA256, stagingSHA256]
            .forEach(RecoverabilityValidationV1.digest)
        guard schemaVersion == Self.schemaVersion, stagingID != RecoverabilityValidationV1.zeroUUID,
              verificationID != RecoverabilityValidationV1.zeroUUID,
              archive.archiveSHA256 == sourceArchiveReadbackSHA256,
              stagingSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(
                schemaVersion: schemaVersion, stagingID: stagingID, verificationID: verificationID,
                workspaceID: workspaceID, archive: archive, mode: mode,
                stagingLocatorToken: stagingLocatorToken,
                liveWorkspaceStateBeforeSHA256: liveWorkspaceStateBeforeSHA256,
                sourceArchiveReadbackSHA256: sourceArchiveReadbackSHA256, state: state, createdAt: createdAt))) else {
            throw RecoverabilityVerificationFailureV1.invalidDigest
        }
    }

    func advanced(to state: RecoverabilityStagingStateV1) throws -> Self {
        try Self(stagingID: stagingID, verificationID: verificationID, workspaceID: workspaceID,
                 archive: archive, mode: mode, stagingLocatorToken: stagingLocatorToken,
                 liveWorkspaceStateBeforeSHA256: liveWorkspaceStateBeforeSHA256,
                 sourceArchiveReadbackSHA256: sourceArchiveReadbackSHA256,
                 state: state, createdAt: createdAt)
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let stagingID: UUID; let verificationID: UUID; let workspaceID: WorkspaceID
        let archive: RecoverabilityArchiveIdentityV1; let mode: RecoverabilityVerificationModeV1
        let stagingLocatorToken: String; let liveWorkspaceStateBeforeSHA256: String
        let sourceArchiveReadbackSHA256: String; let state: RecoverabilityStagingStateV1; let createdAt: Date
    }
}

struct RecoverabilityContentReconciliationV1: Codable, Equatable, Hashable, Sendable {
    let expectedContentCount: Int
    let restoredContentCount: Int
    let expectedContentManifestSHA256: String
    let restoredContentManifestSHA256: String
    let missingContentSHA256s: [String]
    let reconciliationSHA256: String

    init(expectedContentCount: Int, restoredContentCount: Int,
         expectedContentManifestSHA256: String, restoredContentManifestSHA256: String,
         missingContentSHA256s: [String]) throws {
        let missing = missingContentSHA256s.sorted()
        self.expectedContentCount = expectedContentCount; self.restoredContentCount = restoredContentCount
        self.expectedContentManifestSHA256 = expectedContentManifestSHA256
        self.restoredContentManifestSHA256 = restoredContentManifestSHA256
        self.missingContentSHA256s = missing
        reconciliationSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            expectedContentCount: expectedContentCount, restoredContentCount: restoredContentCount,
            expectedContentManifestSHA256: expectedContentManifestSHA256,
            restoredContentManifestSHA256: restoredContentManifestSHA256,
            missingContentSHA256s: missing))
        try validate()
    }

    var isComplete: Bool {
        expectedContentCount == restoredContentCount && missingContentSHA256s.isEmpty
            && expectedContentManifestSHA256 == restoredContentManifestSHA256
    }

    func validate() throws {
        guard expectedContentCount >= 0, restoredContentCount >= 0,
              restoredContentCount <= expectedContentCount,
              missingContentSHA256s.count <= RecoverabilityValidationV1.maximumFindings,
              missingContentSHA256s == missingContentSHA256s.sorted(),
              Set(missingContentSHA256s).count == missingContentSHA256s.count else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try ([expectedContentManifestSHA256, restoredContentManifestSHA256, reconciliationSHA256]
            + missingContentSHA256s).forEach(RecoverabilityValidationV1.digest)
        guard reconciliationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(
            expectedContentCount: expectedContentCount, restoredContentCount: restoredContentCount,
            expectedContentManifestSHA256: expectedContentManifestSHA256,
            restoredContentManifestSHA256: restoredContentManifestSHA256,
            missingContentSHA256s: missingContentSHA256s))) else {
            throw RecoverabilityVerificationFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable {
        let expectedContentCount: Int; let restoredContentCount: Int
        let expectedContentManifestSHA256: String; let restoredContentManifestSHA256: String
        let missingContentSHA256s: [String]
    }
}

struct DeterministicRecoveryReplayReceiptV1: Codable, Equatable, Hashable, Sendable {
    let checkpointID: String
    let orderedMutationCount: Int
    let orderedMutationDigestSHA256: String
    let restoredCanonicalStateSHA256: String
    let replayedCanonicalStateSHA256: String
    let replaySHA256: String

    init(checkpointID: String, orderedMutationCount: Int, orderedMutationDigestSHA256: String,
         restoredCanonicalStateSHA256: String, replayedCanonicalStateSHA256: String) throws {
        self.checkpointID = checkpointID; self.orderedMutationCount = orderedMutationCount
        self.orderedMutationDigestSHA256 = orderedMutationDigestSHA256
        self.restoredCanonicalStateSHA256 = restoredCanonicalStateSHA256
        self.replayedCanonicalStateSHA256 = replayedCanonicalStateSHA256
        replaySHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            checkpointID: checkpointID, orderedMutationCount: orderedMutationCount,
            orderedMutationDigestSHA256: orderedMutationDigestSHA256,
            restoredCanonicalStateSHA256: restoredCanonicalStateSHA256,
            replayedCanonicalStateSHA256: replayedCanonicalStateSHA256))
        try validate()
    }

    var reconciles: Bool { restoredCanonicalStateSHA256 == replayedCanonicalStateSHA256 }

    func validate() throws {
        guard orderedMutationCount >= 0 else { throw RecoverabilityVerificationFailureV1.invalidValue }
        try [checkpointID, orderedMutationDigestSHA256, restoredCanonicalStateSHA256,
             replayedCanonicalStateSHA256, replaySHA256].forEach(RecoverabilityValidationV1.digest)
        guard replaySHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(
            checkpointID: checkpointID, orderedMutationCount: orderedMutationCount,
            orderedMutationDigestSHA256: orderedMutationDigestSHA256,
            restoredCanonicalStateSHA256: restoredCanonicalStateSHA256,
            replayedCanonicalStateSHA256: replayedCanonicalStateSHA256))) else {
            throw RecoverabilityVerificationFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable {
        let checkpointID: String; let orderedMutationCount: Int; let orderedMutationDigestSHA256: String
        let restoredCanonicalStateSHA256: String; let replayedCanonicalStateSHA256: String
    }
}

struct RecoverabilityCleanupProofV1: Codable, Equatable, Hashable, Sendable {
    let stagingID: UUID
    let verificationID: UUID
    let stagingRemoved: Bool
    let liveWorkspaceStateBeforeSHA256: String
    let liveWorkspaceStateAfterSHA256: String
    let sourceArchiveSHA256Before: String
    let sourceArchiveSHA256After: String
    let canonicalWorkspaceMutationCount: UInt64
    let cleanupSHA256: String

    init(stagingID: UUID, verificationID: UUID, stagingRemoved: Bool, liveWorkspaceStateBeforeSHA256: String,
         liveWorkspaceStateAfterSHA256: String, sourceArchiveSHA256Before: String,
         sourceArchiveSHA256After: String, canonicalWorkspaceMutationCount: UInt64) throws {
        self.stagingID = stagingID; self.verificationID = verificationID; self.stagingRemoved = stagingRemoved
        self.liveWorkspaceStateBeforeSHA256 = liveWorkspaceStateBeforeSHA256
        self.liveWorkspaceStateAfterSHA256 = liveWorkspaceStateAfterSHA256
        self.sourceArchiveSHA256Before = sourceArchiveSHA256Before
        self.sourceArchiveSHA256After = sourceArchiveSHA256After
        self.canonicalWorkspaceMutationCount = canonicalWorkspaceMutationCount
        cleanupSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            stagingID: stagingID, verificationID: verificationID, stagingRemoved: stagingRemoved,
            liveWorkspaceStateBeforeSHA256: liveWorkspaceStateBeforeSHA256,
            liveWorkspaceStateAfterSHA256: liveWorkspaceStateAfterSHA256,
            sourceArchiveSHA256Before: sourceArchiveSHA256Before,
            sourceArchiveSHA256After: sourceArchiveSHA256After,
            canonicalWorkspaceMutationCount: canonicalWorkspaceMutationCount))
        try validate()
    }

    var provesIsolation: Bool {
        stagingRemoved && liveWorkspaceStateBeforeSHA256 == liveWorkspaceStateAfterSHA256
            && sourceArchiveSHA256Before == sourceArchiveSHA256After
            && canonicalWorkspaceMutationCount == 0
    }

    func validate() throws {
        guard stagingID != RecoverabilityValidationV1.zeroUUID,
              verificationID != RecoverabilityValidationV1.zeroUUID else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        try [liveWorkspaceStateBeforeSHA256, liveWorkspaceStateAfterSHA256,
             sourceArchiveSHA256Before, sourceArchiveSHA256After, cleanupSHA256]
            .forEach(RecoverabilityValidationV1.digest)
        guard cleanupSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(
            stagingID: stagingID, verificationID: verificationID, stagingRemoved: stagingRemoved,
            liveWorkspaceStateBeforeSHA256: liveWorkspaceStateBeforeSHA256,
            liveWorkspaceStateAfterSHA256: liveWorkspaceStateAfterSHA256,
            sourceArchiveSHA256Before: sourceArchiveSHA256Before,
            sourceArchiveSHA256After: sourceArchiveSHA256After,
            canonicalWorkspaceMutationCount: canonicalWorkspaceMutationCount))) else {
            throw RecoverabilityVerificationFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable {
        let stagingID: UUID; let verificationID: UUID; let stagingRemoved: Bool
        let liveWorkspaceStateBeforeSHA256: String
        let liveWorkspaceStateAfterSHA256: String; let sourceArchiveSHA256Before: String
        let sourceArchiveSHA256After: String; let canonicalWorkspaceMutationCount: UInt64
    }
}

struct RecoverabilityVerificationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let verificationID: UUID
    let archive: RecoverabilityArchiveIdentityV1
    let mode: RecoverabilityVerificationModeV1
    let observedSourceFrontier: RecoveryPointFrontierV1
    let freshness: RecoveryPointFreshnessDispositionV1
    let verifierBuild: RecoverabilityVerifierBuildV1
    let restoredRecordsSHA256: String?
    let contentReconciliation: RecoverabilityContentReconciliationV1?
    let replayReceipt: DeterministicRecoveryReplayReceiptV1?
    let cleanupProof: RecoverabilityCleanupProofV1
    let disposition: RecoverabilityVerificationDispositionV1
    let findings: [RecoverabilityFindingCodeV1]
    let receiptIncludedInVerifiedArchive: Bool
    let verifiedAt: Date
    let supersedesReceiptID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let receiptSHA256: String

    init(receiptID: UUID, workspaceID: WorkspaceID, verificationID: UUID,
         archive: RecoverabilityArchiveIdentityV1, mode: RecoverabilityVerificationModeV1,
         observedSourceFrontier: RecoveryPointFrontierV1,
         freshness: RecoveryPointFreshnessDispositionV1,
         verifierBuild: RecoverabilityVerifierBuildV1, restoredRecordsSHA256: String?,
         contentReconciliation: RecoverabilityContentReconciliationV1?,
         replayReceipt: DeterministicRecoveryReplayReceiptV1?, cleanupProof: RecoverabilityCleanupProofV1,
         disposition: RecoverabilityVerificationDispositionV1,
         findings: [RecoverabilityFindingCodeV1], verifiedAt: Date,
         supersedesReceiptID: UUID? = nil, revision: UInt64 = 1, mutationID: MutationIDV1) throws {
        let findings = findings.sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion; self.receiptID = receiptID; self.workspaceID = workspaceID
        self.verificationID = verificationID; self.archive = archive; self.mode = mode
        self.observedSourceFrontier = observedSourceFrontier; self.freshness = freshness
        self.verifierBuild = verifierBuild; self.restoredRecordsSHA256 = restoredRecordsSHA256
        self.contentReconciliation = contentReconciliation; self.replayReceipt = replayReceipt
        self.cleanupProof = cleanupProof; self.disposition = disposition; self.findings = findings
        receiptIncludedInVerifiedArchive = false; self.verifiedAt = verifiedAt
        self.supersedesReceiptID = supersedesReceiptID; self.revision = revision; self.mutationID = mutationID
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Self.basis(
            schemaVersion: Self.schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
            verificationID: verificationID, archive: archive, mode: mode,
            observedSourceFrontier: observedSourceFrontier, freshness: freshness,
            verifierBuild: verifierBuild, restoredRecordsSHA256: restoredRecordsSHA256,
            contentReconciliation: contentReconciliation, replayReceipt: replayReceipt,
            cleanupProof: cleanupProof, disposition: disposition, findings: findings,
            receiptIncludedInVerifiedArchive: false, verifiedAt: verifiedAt,
            supersedesReceiptID: supersedesReceiptID, revision: revision, mutationID: mutationID))
        try validate()
    }

    var isPassingProof: Bool { disposition == .passed && findings.isEmpty }

    func validate() throws {
        try archive.validate(); try observedSourceFrontier.validate(); try verifierBuild.validate()
        try contentReconciliation?.validate(); try replayReceipt?.validate(); try cleanupProof.validate()
        try restoredRecordsSHA256.map(RecoverabilityValidationV1.digest)
        let expectedFreshness: RecoveryPointFreshnessDispositionV1 = workspaceID == archive.sourceWorkspaceID
            ? archive.frontier.freshness(relativeTo: observedSourceFrontier)
            : .historicNoncurrent
        guard schemaVersion == Self.schemaVersion, receiptID != RecoverabilityValidationV1.zeroUUID,
              verificationID != RecoverabilityValidationV1.zeroUUID, revision > 0,
              (supersedesReceiptID == nil) == (revision == 1), !receiptIncludedInVerifiedArchive,
              cleanupProof.verificationID == verificationID,
              cleanupProof.sourceArchiveSHA256Before == archive.archiveSHA256,
              cleanupProof.sourceArchiveSHA256After == archive.archiveSHA256,
              cleanupProof.provesIsolation,
              findings.count <= RecoverabilityValidationV1.maximumFindings,
              findings == findings.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(findings).count == findings.count,
              freshness == expectedFreshness,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Self.basis(
                schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
                verificationID: verificationID, archive: archive, mode: mode,
                observedSourceFrontier: observedSourceFrontier, freshness: freshness,
                verifierBuild: verifierBuild, restoredRecordsSHA256: restoredRecordsSHA256,
                contentReconciliation: contentReconciliation, replayReceipt: replayReceipt,
                cleanupProof: cleanupProof, disposition: disposition, findings: findings,
                receiptIncludedInVerifiedArchive: receiptIncludedInVerifiedArchive, verifiedAt: verifiedAt,
                supersedesReceiptID: supersedesReceiptID, revision: revision, mutationID: mutationID))) else {
            throw RecoverabilityVerificationFailureV1.invalidDigest
        }
        switch mode {
        case .structureOnly:
            guard restoredRecordsSHA256 == nil, contentReconciliation == nil, replayReceipt == nil else {
                throw RecoverabilityVerificationFailureV1.invalidValue
            }
        case .isolatedDryRestore:
            guard restoredRecordsSHA256 != nil, contentReconciliation == nil, replayReceipt != nil else {
                throw RecoverabilityVerificationFailureV1.invalidValue
            }
        case .fullContentReconciliation:
            guard restoredRecordsSHA256 != nil, contentReconciliation != nil, replayReceipt != nil else {
                throw RecoverabilityVerificationFailureV1.invalidValue
            }
        }
        if disposition == .passed {
            guard findings.isEmpty else {
                throw RecoverabilityVerificationFailureV1.cleanupFailed
            }
            switch mode {
            case .structureOnly:
                break
            case .isolatedDryRestore:
                guard let restoredRecordsSHA256,
                      restoredRecordsSHA256 == archive.recordsSHA256,
                      let replayReceipt, replayReceipt.reconciles,
                      replayReceipt.restoredCanonicalStateSHA256 == restoredRecordsSHA256,
                      replayReceipt.checkpointID == archive.frontier.checkpointID else {
                    throw RecoverabilityVerificationFailureV1.replayDiverged
                }
            case .fullContentReconciliation:
                guard let restoredRecordsSHA256,
                      restoredRecordsSHA256 == archive.recordsSHA256,
                      let contentReconciliation, contentReconciliation.isComplete,
                      contentReconciliation.expectedContentManifestSHA256 == archive.contentManifestSHA256,
                      let replayReceipt, replayReceipt.reconciles,
                      replayReceipt.restoredCanonicalStateSHA256 == restoredRecordsSHA256,
                      replayReceipt.checkpointID == archive.frontier.checkpointID else {
                    throw RecoverabilityVerificationFailureV1.reconciliationFailed
                }
            }
        } else if findings.isEmpty {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try validate(); try predecessor.validate()
        guard receiptID != predecessor.receiptID,
              supersedesReceiptID == predecessor.receiptID,
              workspaceID == predecessor.workspaceID,
              archive == predecessor.archive,
              mutationID != predecessor.mutationID,
              predecessor.revision < UInt64.max, revision == predecessor.revision + 1 else {
            throw RecoverabilityVerificationFailureV1.invalidSuccessor
        }
    }

    /// Clone/fork keeps the original archive/source binding as immutable,
    /// explicitly noncurrent historic evidence in the destination workspace.
    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        guard workspaceID != self.workspaceID else { throw RecoverabilityVerificationFailureV1.invalidValue }
        return try Self(receiptID: receiptID, workspaceID: workspaceID, verificationID: verificationID,
                 archive: archive, mode: mode, observedSourceFrontier: observedSourceFrontier,
                 freshness: .historicNoncurrent, verifierBuild: verifierBuild,
                 restoredRecordsSHA256: restoredRecordsSHA256,
                 contentReconciliation: contentReconciliation, replayReceipt: replayReceipt,
                 cleanupProof: cleanupProof, disposition: disposition, findings: findings,
                 verifiedAt: verifiedAt, supersedesReceiptID: supersedesReceiptID,
                 revision: revision, mutationID: mutationID)
    }

    private static func basis(schemaVersion: Int, receiptID: UUID, workspaceID: WorkspaceID,
                       verificationID: UUID, archive: RecoverabilityArchiveIdentityV1,
                       mode: RecoverabilityVerificationModeV1,
                       observedSourceFrontier: RecoveryPointFrontierV1,
                       freshness: RecoveryPointFreshnessDispositionV1,
                       verifierBuild: RecoverabilityVerifierBuildV1, restoredRecordsSHA256: String?,
                       contentReconciliation: RecoverabilityContentReconciliationV1?,
                       replayReceipt: DeterministicRecoveryReplayReceiptV1?,
                       cleanupProof: RecoverabilityCleanupProofV1,
                       disposition: RecoverabilityVerificationDispositionV1,
                       findings: [RecoverabilityFindingCodeV1], receiptIncludedInVerifiedArchive: Bool,
                       verifiedAt: Date, supersedesReceiptID: UUID?, revision: UInt64,
                       mutationID: MutationIDV1) -> Basis {
        Basis(schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
              verificationID: verificationID, archive: archive, mode: mode,
              observedSourceFrontier: observedSourceFrontier, freshness: freshness,
              verifierBuild: verifierBuild, restoredRecordsSHA256: restoredRecordsSHA256,
              contentReconciliation: contentReconciliation, replayReceipt: replayReceipt,
              cleanupProof: cleanupProof, disposition: disposition, findings: findings,
              receiptIncludedInVerifiedArchive: receiptIncludedInVerifiedArchive, verifiedAt: verifiedAt,
              supersedesReceiptID: supersedesReceiptID, revision: revision, mutationID: mutationID)
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let verificationID: UUID
        let archive: RecoverabilityArchiveIdentityV1; let mode: RecoverabilityVerificationModeV1
        let observedSourceFrontier: RecoveryPointFrontierV1
        let freshness: RecoveryPointFreshnessDispositionV1; let verifierBuild: RecoverabilityVerifierBuildV1
        let restoredRecordsSHA256: String?; let contentReconciliation: RecoverabilityContentReconciliationV1?
        let replayReceipt: DeterministicRecoveryReplayReceiptV1?; let cleanupProof: RecoverabilityCleanupProofV1
        let disposition: RecoverabilityVerificationDispositionV1; let findings: [RecoverabilityFindingCodeV1]
        let receiptIncludedInVerifiedArchive: Bool; let verifiedAt: Date; let supersedesReceiptID: UUID?
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

struct RecoverabilityFreshnessProjectionV1: Equatable, Sendable {
    let receiptID: UUID
    let disposition: RecoveryPointFreshnessDispositionV1
    let remainsExactArchiveProof: Bool

    static func derive(receipt: RecoverabilityVerificationReceiptV1,
                       currentArchiveSHA256: String,
                       currentSourceFrontier: RecoveryPointFrontierV1) throws -> Self {
        try receipt.validate(); try RecoverabilityValidationV1.digest(currentArchiveSHA256)
        let exact = receipt.archive.archiveSHA256 == currentArchiveSHA256
        let sameWorkspace = receipt.workspaceID == receipt.archive.sourceWorkspaceID
        let freshness: RecoveryPointFreshnessDispositionV1 = exact && sameWorkspace
            ? receipt.archive.frontier.freshness(relativeTo: currentSourceFrontier)
            : .historicNoncurrent
        return Self(receiptID: receipt.receiptID, disposition: freshness,
                    remainsExactArchiveProof: exact && sameWorkspace && receipt.isPassingProof)
    }
}

enum RecoverabilityVerificationCanonicalCodecV1 {
    static let maximumBytes = 4_194_304
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw RecoverabilityVerificationFailureV1.limitExceeded }
        return data
    }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumBytes else { throw RecoverabilityVerificationFailureV1.limitExceeded }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw RecoverabilityVerificationFailureV1.nonCanonicalData }
        return value
    }
}

enum RecoverabilityVerificationLifecycleV1 {
    static let stagingPersistence = "DERIVED_ONLY_DROP_AND_REBUILD"
    static let receiptPersistence = "RECOVERABILITY_VERIFICATION_RECEIPT_V1_IMMUTABLE_EVIDENCE"
    static let backupEligibility = "SUBSEQUENT_BACKUPS_ONLY"
    static let receiptInsideVerifiedArchive = false
    static let externalCopyAvailabilityClaimed = false
    static let liveRestorePermitted = false
    static let writer = "SOLE_CANONICAL_WORKSPACE_WRITER"
}
