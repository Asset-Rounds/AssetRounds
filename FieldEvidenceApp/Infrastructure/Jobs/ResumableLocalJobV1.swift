import CryptoKit
import Foundation

enum ScheduleGenerationJobBoundaryV1 { static let outputIsDerivedPlan = true }

struct LocalJobIDV1: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Stable for one kind, workspace and immutable input. A retry therefore
    /// adopts the same durable row instead of duplicating the effect.
    static func deterministic(
        kind: ResumableLocalJobKindV1,
        workspaceID: UUID,
        immutableInputSHA256: String
    ) -> Self {
        let material = [
            "local-job-v1",
            kind.rawValue,
            workspaceID.uuidString.lowercased(),
            immutableInputSHA256
        ].joined(separator: "\u{1f}")
        return Self(rawValue: deterministicUUID(Data(material.utf8)))
    }

    private static func deterministicUUID(_ data: Data) -> UUID {
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct LocalJobChunkIDV1: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func deterministic(jobID: LocalJobIDV1, index: Int) -> Self {
        let material = "local-job-chunk-v1\u{1f}\(jobID.rawValue.uuidString.lowercased())\u{1f}\(index)"
        return Self(rawValue: SHA256.hash(data: Data(material.utf8)).map {
            String(format: "%02x", $0)
        }.joined())
    }
}

enum ResumableLocalJobKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case hash = "HASH"
    case copy = "COPY"
    case sanitize = "SANITIZE"
    case render = "RENDER"
    case archive = "ARCHIVE"
    case importData = "IMPORT"
    case finalize = "FINALIZE"
    case searchRebuild = "SEARCH_REBUILD"
    case starterInstallation = "STARTER_INSTALLATION"
    case mediaProcessing = "MEDIA_PROCESSING"
    case resourceProjection = "RESOURCE_PROJECTION"
    case scheduleGeneration = "SCHEDULE_GENERATION"
    /// Device-local per-attachment processing.  Its output is a staging
    /// checkpoint; publication remains the draft content reservation boundary.
    case draftAttachmentProcessing = "DRAFT_ATTACHMENT_PROCESSING"
}

enum LocalJobStateV1: String, Codable, Equatable, Sendable {
    case queued = "QUEUED"
    case running = "RUNNING"
    case cancellationRequested = "CANCELLATION_REQUESTED"
    case blockedProtectedData = "BLOCKED_PROTECTED_DATA"
    case awaitingPublication = "AWAITING_PUBLICATION"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    var isTerminal: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }
}

enum LocalJobRetryClassificationV1: String, Codable, Equatable, Sendable {
    case retryable = "RETRYABLE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case generationLeaseLost = "GENERATION_LEASE_LOST"
    case permanent = "PERMANENT"
}

enum LocalJobPublicationModeV1: String, Codable, Equatable, Sendable {
    case publishOrAdopt = "PUBLISH_OR_ADOPT"
    case adoptOnly = "ADOPT_ONLY"
}

enum LocalJobPublicationDispositionV1: String, Codable, Equatable, Sendable {
    case published = "PUBLISHED"
    case adopted = "ADOPTED"
}

struct LocalJobPendingPublicationV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let attemptCount: Int
    let result: ResumableLocalJobResultV1
    let persistedAt: Date
    var cancellationRequested: Bool

    init(
        attemptCount: Int,
        result: ResumableLocalJobResultV1,
        persistedAt: Date,
        cancellationRequested: Bool,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.attemptCount = attemptCount
        self.result = result
        self.persistedAt = persistedAt
        self.cancellationRequested = cancellationRequested
    }

    func validate(totalUnitCount: Int) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              attemptCount > 0,
              ResumableLocalJobV1.isSHA256(result.outputSHA256),
              result.completedUnitCount == totalUnitCount,
              persistedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LocalJobValidationFailureV1.invalidContract
        }
    }
}

struct LocalJobPublicationReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let jobID: LocalJobIDV1
    let attemptCount: Int
    let kind: ResumableLocalJobKindV1
    let outputSHA256: String
    let disposition: LocalJobPublicationDispositionV1
    let readBackAt: Date

    init(
        jobID: LocalJobIDV1,
        attemptCount: Int,
        kind: ResumableLocalJobKindV1,
        outputSHA256: String,
        disposition: LocalJobPublicationDispositionV1,
        readBackAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.jobID = jobID
        self.attemptCount = attemptCount
        self.kind = kind
        self.outputSHA256 = outputSHA256
        self.disposition = disposition
        self.readBackAt = readBackAt
    }

    func validate(job: ResumableLocalJobV1) throws {
        guard let pending = job.pendingPublication,
              schemaVersion == Self.currentSchemaVersion,
              jobID == job.id,
              attemptCount == job.attemptCount,
              kind == job.kind,
              outputSHA256 == pending.result.outputSHA256,
              readBackAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LocalJobValidationFailureV1.invalidContract
        }
        if pending.cancellationRequested, disposition != .adopted {
            throw LocalJobValidationFailureV1.invalidContract
        }
    }
}

struct LocalJobCheckpointV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let nextChunkIndex: Int
    let completedUnitCount: Int
    let totalUnitCount: Int
    let lastChunkID: LocalJobChunkIDV1?
    let rollingOutputSHA256: String?

    init(
        nextChunkIndex: Int,
        completedUnitCount: Int,
        totalUnitCount: Int,
        lastChunkID: LocalJobChunkIDV1? = nil,
        rollingOutputSHA256: String? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.nextChunkIndex = nextChunkIndex
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.lastChunkID = lastChunkID
        self.rollingOutputSHA256 = rollingOutputSHA256
    }

    func validate(for jobID: LocalJobIDV1) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              nextChunkIndex >= 0,
              completedUnitCount >= 0,
              totalUnitCount >= 0,
              completedUnitCount <= totalUnitCount,
              rollingOutputSHA256.map(Self.isSHA256) ?? true else {
            throw LocalJobValidationFailureV1.invalidCheckpoint
        }
        if nextChunkIndex == 0 {
            guard lastChunkID == nil else {
                throw LocalJobValidationFailureV1.invalidCheckpoint
            }
        } else {
            guard let lastChunkID,
                  lastChunkID == .deterministic(
                      jobID: jobID,
                      index: nextChunkIndex - 1
                  ) else {
                throw LocalJobValidationFailureV1.invalidCheckpoint
            }
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

enum LocalJobValidationFailureV1: Error, Equatable, Sendable {
    case invalidContract
    case invalidDigest
    case invalidCheckpoint
    case invalidTransition
}

struct ResumableLocalJobV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: LocalJobIDV1
    let workspaceID: UUID
    let kind: ResumableLocalJobKindV1
    let immutableInputSHA256: String
    let stagingRelativePath: String
    let generationEpoch: GenerationEpochV1?
    let createdAt: Date
    var updatedAt: Date
    var state: LocalJobStateV1
    var checkpoint: LocalJobCheckpointV1
    var attemptCount: Int
    var retryClassification: LocalJobRetryClassificationV1?
    var outputSHA256: String?
    var failureCode: String?
    var pendingPublication: LocalJobPendingPublicationV1?
    var publicationReceipt: LocalJobPublicationReceiptV1?

    init(
        id: LocalJobIDV1? = nil,
        workspaceID: UUID,
        kind: ResumableLocalJobKindV1,
        immutableInputSHA256: String,
        stagingRelativePath: String,
        generationEpoch: GenerationEpochV1? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        state: LocalJobStateV1 = .queued,
        checkpoint: LocalJobCheckpointV1,
        attemptCount: Int = 0,
        retryClassification: LocalJobRetryClassificationV1? = nil,
        outputSHA256: String? = nil,
        failureCode: String? = nil,
        pendingPublication: LocalJobPendingPublicationV1? = nil,
        publicationReceipt: LocalJobPublicationReceiptV1? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.id = id ?? .deterministic(
            kind: kind,
            workspaceID: workspaceID,
            immutableInputSHA256: immutableInputSHA256
        )
        self.workspaceID = workspaceID
        self.kind = kind
        self.immutableInputSHA256 = immutableInputSHA256
        self.stagingRelativePath = stagingRelativePath
        self.generationEpoch = generationEpoch
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.state = state
        self.checkpoint = checkpoint
        self.attemptCount = attemptCount
        self.retryClassification = retryClassification
        self.outputSHA256 = outputSHA256
        self.failureCode = failureCode
        self.pendingPublication = pendingPublication
        self.publicationReceipt = publicationReceipt
        try validate()
    }

    func validate() throws {
        try generationEpoch?.validate()
        try checkpoint.validate(for: id)
        guard schemaVersion == Self.currentSchemaVersion,
              id == .deterministic(
                  kind: kind,
                  workspaceID: workspaceID,
                  immutableInputSHA256: immutableInputSHA256
              ),
              workspaceID != GenerationEpochV1.zeroUUID,
              Self.isSHA256(immutableInputSHA256),
              Self.isSafeRelativePath(stagingRelativePath),
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              attemptCount >= 0,
              outputSHA256.map(Self.isSHA256) ?? true,
              failureCode.map(Self.isSafeCode) ?? true else {
            throw LocalJobValidationFailureV1.invalidContract
        }
        // Wall-clock records may move backward or forward. Job causality is
        // carried by attempt/checkpoint/state transitions, not Date ordering.
        try pendingPublication?.validate(
            totalUnitCount: checkpoint.totalUnitCount
        )
        if let pendingPublication,
           pendingPublication.attemptCount != attemptCount {
                throw LocalJobValidationFailureV1.invalidContract
        }
        try publicationReceipt?.validate(job: self)
        switch state {
        case .succeeded:
            guard outputSHA256 != nil,
                  failureCode == nil,
                  retryClassification == nil,
                  checkpoint.completedUnitCount == checkpoint.totalUnitCount,
                  pendingPublication != nil,
                  publicationReceipt != nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        case .awaitingPublication:
            guard outputSHA256 == nil,
                  failureCode == nil,
                  retryClassification == nil,
                  pendingPublication != nil,
                  publicationReceipt == nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        case .failed:
            guard outputSHA256 == nil,
                  failureCode != nil,
                  retryClassification != nil,
                  retryClassification != .protectedDataUnavailable,
                  pendingPublication == nil,
                  publicationReceipt == nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        case .cancelled:
            guard outputSHA256 == nil,
                  failureCode == nil,
                  retryClassification == nil,
                  pendingPublication == nil,
                  publicationReceipt == nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        case .blockedProtectedData:
            guard outputSHA256 == nil,
                  failureCode == nil,
                  retryClassification == .protectedDataUnavailable,
                  pendingPublication == nil,
                  publicationReceipt == nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        case .queued:
            guard outputSHA256 == nil,
                  failureCode == nil,
                  retryClassification != .permanent,
                  pendingPublication == nil,
                  publicationReceipt == nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        case .running, .cancellationRequested:
            guard outputSHA256 == nil,
                  failureCode == nil,
                  retryClassification == nil,
                  pendingPublication == nil,
                  publicationReceipt == nil else {
                throw LocalJobValidationFailureV1.invalidContract
            }
        }
    }

    func permitsTransition(to next: LocalJobStateV1) -> Bool {
        if state == next { return true }
        switch (state, next) {
        case (.queued, .running), (.queued, .cancellationRequested),
             (.running, .queued), (.running, .cancellationRequested),
             (.running, .blockedProtectedData), (.running, .succeeded),
             (.running, .awaitingPublication),
             (.running, .failed), (.cancellationRequested, .cancelled),
             (.cancellationRequested, .awaitingPublication),
             (.awaitingPublication, .succeeded),
             (.awaitingPublication, .cancelled),
             (.blockedProtectedData, .queued),
             (.blockedProtectedData, .cancellationRequested),
             (.failed, .queued):
            return true
        default:
            return false
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("\\") else {
            return false
        }
        let components = value.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private static func isSafeCode(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0)
        }
    }
}

// MARK: - C36 attachment processing jobs

struct DraftAttachmentJobRequestV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let draftID: UUID
    let stageID: UUID
    let stageSHA256: String
    let stagingRelativePath: String
    let totalUnitCount: Int
    let createdAt: Date

    init(
        workspaceID: WorkspaceID,
        draftID: UUID,
        stageID: UUID,
        stageSHA256: String,
        stagingRelativePath: String,
        totalUnitCount: Int = 1,
        createdAt: Date
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard workspaceID.rawValue != zero, draftID != zero, stageID != zero,
              ResumableLocalJobV1.isSHA256(stageSHA256),
              totalUnitCount > 0,
              !stagingRelativePath.isEmpty,
              !stagingRelativePath.hasPrefix("/"),
              !stagingRelativePath.hasPrefix("\\"),
              !stagingRelativePath.replacingOccurrences(of: "\\", with: "/")
                  .split(separator: "/", omittingEmptySubsequences: false)
                  .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LocalJobValidationFailureV1.invalidContract
        }
        self.workspaceID = workspaceID
        self.draftID = draftID
        self.stageID = stageID
        self.stageSHA256 = stageSHA256
        self.stagingRelativePath = stagingRelativePath
        self.totalUnitCount = totalUnitCount
        self.createdAt = createdAt
    }
}

extension ResumableLocalJobV1 {
    /// Creates the stable queue row for one staging item.  The input digest is
    /// the item digest, not a mutable file timestamp, so retries adopt the
    /// same job and resume from its durable checkpoint.
    static func draftAttachmentProcessing(
        _ request: DraftAttachmentJobRequestV1
    ) throws -> Self {
        let checkpoint = LocalJobCheckpointV1(
            nextChunkIndex: 0,
            completedUnitCount: 0,
            totalUnitCount: request.totalUnitCount
        )
        return try Self(
            workspaceID: request.workspaceID.rawValue,
            kind: .draftAttachmentProcessing,
            immutableInputSHA256: request.stageSHA256,
            stagingRelativePath: request.stagingRelativePath,
            createdAt: request.createdAt,
            checkpoint: checkpoint
        )
    }

    var isDraftAttachmentProcessing: Bool {
        kind == .draftAttachmentProcessing
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Jobs_ResumableLocalJobV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Jobs_ResumableLocalJobV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Jobs_ResumableLocalJobV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift", role: .job)
}

enum C31LightingLocalJobBoundaryV1 {
    static let jobStateIsDisposableProjectionState = true
    static let retryDoesNotRewriteFrozenHistory = true
    static let jobDoesNotCollectSensorData = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Jobs_ResumableLocalJobV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}
