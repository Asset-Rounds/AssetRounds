import Foundation

protocol DraftAutosaveClockV1: Sendable {
    func nowNanoseconds() async -> UInt64
    func sleep(untilNanoseconds deadline: UInt64) async throws
}

struct ContinuousDraftAutosaveClockV1: DraftAutosaveClockV1 {
    private let origin = ContinuousClock().now

    func nowNanoseconds() async -> UInt64 {
        let duration = origin.duration(to: ContinuousClock().now)
        let components = duration.components
        let seconds = components.seconds > 0 ? UInt64(components.seconds) : 0
        let attoseconds = components.attoseconds > 0 ? UInt64(components.attoseconds) : 0
        let whole = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !whole.overflow else { return .max }
        let total = whole.partialValue.addingReportingOverflow(attoseconds / 1_000_000_000)
        return total.overflow ? .max : total.partialValue
    }

    func sleep(untilNanoseconds deadline: UInt64) async throws {
        let now = await nowNanoseconds()
        guard deadline > now else { return }
        try await Task.sleep(nanoseconds: deadline - now)
    }
}

struct DraftAutosaveFailureStateV1: Equatable, Sendable {
    let draftID: UUID
    let attempt: Int
    let firstDirtyNanoseconds: UInt64
    let failedAtNanoseconds: UInt64
    let nextRetryNanoseconds: UInt64?
}

actor DraftAutosaveSchedulerV1 {
    typealias Flush = @Sendable (UUID) async throws -> Void
    typealias Failure = @Sendable (DraftAutosaveFailureStateV1) async -> Void

    private static let maximumAutomaticRetryCount = 3

    private struct Dirty {
        let first: UInt64
        var last: UInt64
        var generation: UInt64
        var retryCount: Int
        var failureState: DraftAutosaveFailureStateV1?
        var task: Task<Void, Never>?
    }

    private let policy: DraftAutosavePolicyV1
    private let clock: any DraftAutosaveClockV1
    private let flush: Flush
    private let failure: Failure
    private var dirty: [UUID: Dirty] = [:]

    init(
        policy: DraftAutosavePolicyV1,
        clock: any DraftAutosaveClockV1,
        flush: @escaping Flush,
        failure: @escaping Failure = { _ in }
    ) {
        self.policy = policy
        self.clock = clock
        self.flush = flush
        self.failure = failure
    }

    func meaningfulEdit(draftID: UUID) async {
        let now = await clock.nowNanoseconds()
        var value = dirty[draftID] ?? Dirty(
            first: now,
            last: now,
            generation: 0,
            retryCount: 0,
            failureState: nil,
            task: nil
        )
        value.last = now
        value.retryCount = 0
        value.task?.cancel()
        value.generation = nextGeneration(after: value.generation)
        let deadline = automaticDeadline(first: value.first, last: now)
        value.task = scheduledTask(draftID: draftID, generation: value.generation, deadline: deadline)
        dirty[draftID] = value
    }

    func forceFlush(draftID: UUID) async throws {
        dirty[draftID]?.task?.cancel()
        guard let generation = dirty[draftID]?.generation else { return }
        do {
            try await flush(draftID)
            guard dirty[draftID]?.generation == generation else { return }
            dirty[draftID] = nil
        } catch {
            await recordFailureAndScheduleRetry(draftID: draftID, expectedGeneration: generation)
            throw error
        }
    }

    func forceFlushAll() async throws {
        for draftID in dirty.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            try await forceFlush(draftID: draftID)
        }
    }

    func failureState(draftID: UUID) -> DraftAutosaveFailureStateV1? {
        dirty[draftID]?.failureState
    }

    func cancel(draftID: UUID) {
        dirty[draftID]?.task?.cancel()
        dirty[draftID] = nil
    }

    private func scheduledTask(draftID: UUID, generation: UInt64, deadline: UInt64) -> Task<Void, Never> {
        Task { [clock, flush] in
            do {
                try await clock.sleep(untilNanoseconds: deadline)
                try Task.checkCancellation()
                try await flush(draftID)
                await self.didFlush(draftID: draftID, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                await self.recordFailureAndScheduleRetry(draftID: draftID, expectedGeneration: generation)
            }
        }
    }

    private func didFlush(draftID: UUID, generation: UInt64) {
        guard dirty[draftID]?.generation == generation else { return }
        dirty[draftID] = nil
    }

    private func recordFailureAndScheduleRetry(draftID: UUID, expectedGeneration: UInt64?) async {
        guard dirty[draftID]?.generation == expectedGeneration else { return }
        let failedAt = await clock.nowNanoseconds()
        guard var value = dirty[draftID], expectedGeneration == value.generation else { return }
        let willRetry = value.retryCount < Self.maximumAutomaticRetryCount
        let nextRetry = willRetry ? automaticDeadline(first: value.first, last: failedAt) : nil
        let state = DraftAutosaveFailureStateV1(
            draftID: draftID,
            attempt: value.retryCount + 1,
            firstDirtyNanoseconds: value.first,
            failedAtNanoseconds: failedAt,
            nextRetryNanoseconds: nextRetry
        )
        value.failureState = state
        value.task = nil
        dirty[draftID] = value
        await failure(state)

        guard var current = dirty[draftID], current.generation == value.generation else { return }
        guard let nextRetry else { return }
        current.retryCount += 1
        current.generation = nextGeneration(after: current.generation)
        current.task = scheduledTask(draftID: draftID, generation: current.generation, deadline: nextRetry)
        dirty[draftID] = current
    }

    private func automaticDeadline(first: UInt64, last: UInt64) -> UInt64 {
        min(saturatingAdd(last, policy.trailingNanoseconds), saturatingAdd(first, policy.maximumDirtyNanoseconds))
    }

    private func nextGeneration(after current: UInt64) -> UInt64 {
        let next = current.addingReportingOverflow(1)
        return next.overflow ? 1 : next.partialValue
    }

    private func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Drafts_DraftAutosaveSchedulerV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Drafts_DraftAutosaveSchedulerV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Drafts/DraftAutosaveSchedulerV1.swift", role: .draft)
}

enum C31LightingDraftAutosaveBoundaryV1 {
    static let autosaveIsDisposableStaging = true
    static let autosaveDoesNotChangeHistoricDisplay = true
    static let lightingProjectionRequiresExplicitCommit = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Drafts_DraftAutosaveSchedulerV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Drafts_DraftAutosaveSchedulerV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row165 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Drafts_DraftAutosaveSchedulerV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

enum C34SceneRestorationDraftAutosaveBoundaryV1 {
    static let schedulesAutosave = false
    static let startsAutomaticWork = false
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !schedulesAutosave && !startsAutomaticWork && C34DraftResumeNavigationBoundaryV1.validate(anchor: anchor) }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Drafts_DraftAutosaveSchedulerV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}
