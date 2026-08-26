import CryptoKit
import Darwin
import Foundation
import SwiftData

private enum DeletionDescriptorRead {
    static func read(
        descriptor: Int32,
        declaredSize: off_t,
        maximumByteCount: Int
    ) -> Data? {
        guard declaredSize >= 0,
              maximumByteCount >= 0,
              UInt64(declaredSize) <= UInt64(maximumByteCount),
              UInt64(declaredSize) <= UInt64(Int.max) else {
            return nil
        }
        let expected = Int(declaredSize)
        var data = Data(count: expected)
        let filled = data.withUnsafeMutableBytes {
            (raw: UnsafeMutableRawBufferPointer) -> Bool in
            var offset = 0
            while offset < expected {
                let count = Darwin.read(
                    descriptor,
                    raw.baseAddress!.advanced(by: offset),
                    expected - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard filled else { return nil }
        var trailing: UInt8 = 0
        while true {
            let count = Darwin.read(descriptor, &trailing, 1)
            if count < 0, errno == EINTR { continue }
            guard count == 0 else { return nil }
            break
        }
        return data
    }
}

struct WholeSignDeletionOutcome: Equatable, Sendable {
    let assetID: UUID
    let deletionID: UUID
    let countedTombstoneCount: Int
}

struct WholeSignDeletionRecoverySummary: Equatable, Sendable {
    let cancelledPreparedCount: Int
    let completedCommittedCount: Int
}

struct ExplicitSiteDeletionOutcomeV1: Equatable, Sendable {
    let siteID: UUID
    let deletionID: UUID
}

enum WholeSignDeletionServiceError: Error, Equatable {
    case invalidGeneration
    case contextHasChanges
    case graphInvalid
    case journalInvalid
    case recoveryRequired
    case fileInvalid
    case saveFailed
    case cleanupFailed
    case injectedFailure
}

enum WholeSignDeletionFailurePoint: Equatable, Sendable {
    case preparedJournal
    case databaseSave
    case committedPhase
    case fileCleanup
    case journalRemoval
}

final class WholeSignDeletionFailureInjection: @unchecked Sendable {
    private let lock = NSLock()
    private var point: WholeSignDeletionFailurePoint?

    init(failOnceAt point: WholeSignDeletionFailurePoint) {
        self.point = point
    }

    func removeFailure() {
        lock.lock()
        point = nil
        lock.unlock()
    }

    fileprivate func consume(_ candidate: WholeSignDeletionFailurePoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard point == candidate else { return false }
        point = nil
        return true
    }
}

@MainActor
final class WholeSignDeletionService {
    private static let maximumSnapshotByteCount = 32 * 1_024 * 1_024
    private static let maximumPDFByteCount = 128 * 1_024 * 1_024
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let generationID: UUID
    private let journal: DeletionJournalStore
    private let files: DeletionGenerationFiles
    private let ledgerStore: DeletionLedgerStore
    private let writerLeaseHandle: GenerationLeaseHandleV1?
    private let staleWriterFence: StaleWriterFenceV1?
    private let allowsLegacyXCTestFallback: Bool
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private let failureInjection: WholeSignDeletionFailureInjection?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: WholeSignDeletionFailureInjection? = nil
    ) {
        self.modelContext = modelContext
        ledgerStore = DeletionLedgerStore(context: modelContext)
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.now = now
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection

        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        let applicationSupport = dataRoot.deletingLastPathComponent()
#if DEBUG
        let canonicalCurrentPointer = applicationSupport
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("current.json")
        let migrationAuthorityDirectory = applicationSupport
            .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
            .appendingPathComponent("schema-migration", isDirectory: true)
        allowsLegacyXCTestFallback = Self.isRunningUnderXCTest
            && !fileManager.fileExists(atPath: canonicalCurrentPointer.path)
            && !fileManager.fileExists(
                atPath: migrationAuthorityDirectory.path
            )
#else
        allowsLegacyXCTestFallback = false
#endif
        var derivedWriterLeaseHandle: GenerationLeaseHandleV1?
        var derivedStaleWriterFence: StaleWriterFenceV1?
        if generations.lastPathComponent == "generations",
           dataRoot.lastPathComponent == "FieldEvidenceData",
           let parsed = UUID(uuidString: root.lastPathComponent),
           parsed.uuidString.lowercased() == root.lastPathComponent,
           let fileAuthority = try? DeletionGenerationFiles(rootURL: root),
           let journalAuthority = try? DeletionJournalStore(
               applicationSupportURL: applicationSupport
           ) {
            generationID = parsed
            files = fileAuthority
            journal = journalAuthority
            do {
                let generationFactory = StoreGenerationFactory(
                    applicationSupportURL: applicationSupport
                )
                let registry = try generationFactory
                    .makeGenerationLeaseRegistry()
                let epoch = try generationFactory.currentGenerationEpoch()
                guard epoch.generationID == parsed else {
                    throw GenerationLeaseRegistryFailureV1.staleGeneration
                }
                let leaseHandle = try registry.acquireHandle(
                    epoch: epoch,
                    role: .writer
                )
                do {
                    derivedStaleWriterFence = try generationFactory
                        .makeWriterFence(
                            expectedGenerationEpoch: epoch,
                            writerLeaseToken: leaseHandle.token,
                            registry: registry
                        )
                    derivedWriterLeaseHandle = leaseHandle
                } catch {
                    // Retain a lease whose fence could not be constructed.
                    // Releasing it here could fail ambiguously; keeping it is
                    // fail-closed and prevents this service from authorizing
                    // deletion or making the generation prune-eligible.
                    derivedWriterLeaseHandle = leaseHandle
                    derivedStaleWriterFence = nil
                }
            } catch {
                derivedWriterLeaseHandle = nil
                derivedStaleWriterFence = nil
            }
        } else {
            generationID = UUID()
            files = DeletionGenerationFiles.invalid
            journal = DeletionJournalStore.invalid
        }
        writerLeaseHandle = derivedWriterLeaseHandle
        staleWriterFence = derivedStaleWriterFence
    }

    func delete(assetID: UUID) async throws -> WholeSignDeletionOutcome {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        guard try journal.loadAll().isEmpty else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let frozenMutationHistory = try mutationHistorySnapshot()

        let rows = try fetchRows()
        let deletionID = makeUUID()
        let deletedAt = now()
        let input = makeRuleInput(
            rows: rows,
            assetID: assetID,
            deletionID: deletionID,
            deletedAt: deletedAt
        )
        let rulePlan: WholeSignDeletionPlan
        do {
            rulePlan = try WholeSignDeletionRule.makePlan(input)
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        let canonicalIntent: DeletionIntentV1
        do {
            canonicalIntent = try DeletionIntentDecoderV1().decode(
                DeletionIntentEncoderV1().encode(rulePlan.intent).data
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        let plan = WholeSignDeletionPlan(
            assetID: rulePlan.assetID,
            evidenceIDs: rulePlan.evidenceIDs,
            intent: canonicalIntent,
            issueIDs: rulePlan.issueIDs,
            packetIDsToDelete: rulePlan.packetIDsToDelete,
            reportIDs: rulePlan.reportIDs,
            siteIDToDelete: rulePlan.siteIDToDelete,
            workflowRecordIDs: rulePlan.workflowRecordIDs
        )
        try requireLedgerEntriesUnseen(plan.intent)
        try validateOwnedFiles(plan: plan, rows: rows)
        try journal.create(plan.intent)
        try inject(.preparedJournal)

        let packetStates = Dictionary(uniqueKeysWithValues: rows.packets.map {
            ($0.id, ($0.currentRecordID, $0.evaluationCounted, $0.contentDeletedAt))
        })
        do {
            try ledgerStore.stageUnion(plan.intent.ledgerEntries)
            try apply(plan: plan, rows: rows)
            try saveStagedMutationWithAuthority()
        } catch {
            for packet in rows.packets {
                if let state = packetStates[packet.id] {
                    packet.currentRecordID = state.0
                    packet.evaluationCounted = state.1
                    packet.contentDeletedAt = state.2
                }
            }
            modelContext.rollback()
            do {
                try journal.remove(plan.intent)
            } catch {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            if error is WholeSignDeletionServiceError { throw error }
            throw WholeSignDeletionServiceError.saveFailed
        }

        do {
            try inject(.committedPhase)
            try journal.replace(plan.intent.withPhase(.databaseCommitted))
            try cleanup(plan.intent)
            try inject(.journalRemoval)
            try journal.remove(plan.intent.withPhase(.databaseCommitted))
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
        }
        guard mutationHistoryAuthorityMatches(
            frozenMutationHistory,
            try mutationHistorySnapshot()
        ) else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        return WholeSignDeletionOutcome(
            assetID: assetID,
            deletionID: deletionID,
            countedTombstoneCount: plan.intent.countedPacketTombstones.count
        )
    }

    func previewSiteDeletion(
        siteID: UUID
    ) throws -> ExplicitSiteDeletionPreviewV1 {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        guard try journal.loadAll().isEmpty else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let rows = try fetchRows()
        guard let site = rows.sites.first(where: { $0.id == siteID }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        do {
            return try WholeSignDeletionRule.makeExplicitSiteDeletionPreview(
                try explicitSiteInput(
                    site: site,
                    rows: rows,
                    deletionID: makeUUID(),
                    deletedAt: now()
                )
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func deleteSite(
        preview: ExplicitSiteDeletionPreviewV1
    ) async throws -> ExplicitSiteDeletionOutcomeV1 {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        guard try journal.loadAll().isEmpty,
              preview.generationID == generationID,
              preview.schemaVersion == 1 else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let frozenMutationHistory = try mutationHistorySnapshot()
        let rows = try fetchRows()
        guard let site = rows.sites.first(where: { $0.id == preview.siteID }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        let current: ExplicitSiteDeletionPreviewV1
        do {
            current = try WholeSignDeletionRule.makeExplicitSiteDeletionPreview(
                try explicitSiteInput(
                    site: site,
                    rows: rows,
                    deletionID: preview.deletionID,
                    deletedAt: preview.deletedAt
                )
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        guard current == preview else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        for plan in preview.assetPlans {
            try validateOwnedFiles(plan: plan, rows: rows)
        }
        try requireLedgerIdentitiesUnseen(preview.ledgerEntries.map(\.identity))
        let packetStates = Dictionary(uniqueKeysWithValues: rows.packets.map {
            ($0.id, ($0.currentRecordID, $0.evaluationCounted, $0.contentDeletedAt))
        })
        do {
            try ledgerStore.stageUnion(preview.ledgerEntries)
            for plan in preview.assetPlans {
                try apply(plan: plan, rows: rows)
            }
            modelContext.delete(site)
            try saveStagedMutationWithAuthority()
        } catch {
            for packet in rows.packets {
                if let state = packetStates[packet.id] {
                    packet.currentRecordID = state.0
                    packet.evaluationCounted = state.1
                    packet.contentDeletedAt = state.2
                }
            }
            modelContext.rollback()
            if error is WholeSignDeletionServiceError { throw error }
            throw WholeSignDeletionServiceError.saveFailed
        }
        do {
            try inject(.fileCleanup)
            for plan in preview.assetPlans {
                try cleanup(plan.intent)
            }
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
        }
        guard mutationHistoryAuthorityMatches(
            frozenMutationHistory,
            try mutationHistorySnapshot()
        ) else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        return ExplicitSiteDeletionOutcomeV1(
            siteID: preview.siteID,
            deletionID: preview.deletionID
        )
    }

    func reconcile() async throws -> WholeSignDeletionRecoverySummary {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        let frozenMutationHistory = try mutationHistorySnapshot()
        let intents = try journal.loadAll()
        let intentPaths = intents.flatMap(\.relativePaths)
        let intentPacketIDs = intents.flatMap {
            $0.countedPacketTombstones.map(\.id)
        }
        let intentLedgerIdentities = intents.flatMap {
            $0.ledgerEntries.map(\.identity)
        }
        guard Set(intents.map(\.assetID)).count == intents.count,
              Set(intentPaths).count == intentPaths.count,
              Set(intentPacketIDs).count == intentPacketIDs.count,
              Set(intentLedgerIdentities).count == intentLedgerIdentities.count else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        var cancelled = 0
        var completed = 0
        for intent in intents {
            guard intent.generationID == generationID else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            let rows = try fetchRows()
            if rows.assets.contains(where: { $0.id == intent.assetID }) {
                if intent.schemaVersion == 1 {
                    guard intent.phase == .prepared,
                          try legacyPreparedIntentMatches(intent, rows: rows) else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                    try journal.remove(intent)
                    cancelled += 1
                    continue
                }
                guard intent.phase == .prepared,
                      let plan = try preparedPlan(intent, rows: rows) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                try requireLedgerEntriesUnseen(intent)
                let packetStates = Dictionary(uniqueKeysWithValues: rows.packets.map {
                    ($0.id, ($0.currentRecordID, $0.evaluationCounted, $0.contentDeletedAt))
                })
                do {
                    try ledgerStore.stageUnion(intent.ledgerEntries)
                    try apply(plan: plan, rows: rows)
                    try saveStagedMutationWithAuthority()
                } catch {
                    for packet in rows.packets {
                        if let state = packetStates[packet.id] {
                            packet.currentRecordID = state.0
                            packet.evaluationCounted = state.1
                            packet.contentDeletedAt = state.2
                        }
                    }
                    modelContext.rollback()
                    if error is WholeSignDeletionServiceError { throw error }
                    throw WholeSignDeletionServiceError.saveFailed
                }
                try inject(.committedPhase)
                try journal.replace(intent.withPhase(.databaseCommitted))
                try cleanup(intent)
                try inject(.journalRemoval)
                try journal.remove(intent.withPhase(.databaseCommitted))
                completed += 1
                continue
            }
            guard try committedStateMatches(intent, rows: rows) else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            if intent.phase == .prepared {
                try journal.replace(intent.withPhase(.databaseCommitted))
            }
            try cleanup(intent)
            try journal.remove(intent.withPhase(.databaseCommitted))
            completed += 1
        }
        guard mutationHistoryAuthorityMatches(
            frozenMutationHistory,
            try mutationHistorySnapshot()
        ) else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        return WholeSignDeletionRecoverySummary(
            cancelledPreparedCount: cancelled,
            completedCommittedCount: completed
        )
    }

    private func requireAuthority() throws {
        guard files.isValid, journal.isValid,
              files.generationID == generationID else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        if let writerLeaseHandle, let staleWriterFence {
            guard writerLeaseHandle.token
                    == staleWriterFence.writerLeaseToken,
                  writerLeaseHandle.token.epoch.generationID
                    == generationID else {
                throw WholeSignDeletionServiceError.invalidGeneration
            }
            do {
                try staleWriterFence.validateCurrent()
                return
            } catch {
                throw WholeSignDeletionServiceError.invalidGeneration
            }
        }
        guard writerLeaseHandle == nil, staleWriterFence == nil else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
#if DEBUG
        guard allowsLegacyXCTestFallback else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
#else
        throw WholeSignDeletionServiceError.invalidGeneration
#endif
    }

    /// The mutation lock covers only the synchronous semantic checkpoint and
    /// SwiftData commit. Journal phase publication and file cleanup remain
    /// outside it, and no suspension is possible while it is held.
    private func saveStagedMutationWithAuthority() throws {
        if let staleWriterFence {
            do {
                try staleWriterFence.withAuthorizedCommit { [self] in
                    try stageMutationSemanticState()
                    try inject(.databaseSave)
                    try modelContext.save()
                }
            } catch let failure as GenerationLeaseRegistryFailureV1 {
                switch failure {
                case .staleGeneration, .leaseNotActive, .wrongLeaseRole:
                    throw WholeSignDeletionServiceError.invalidGeneration
                case .invalidContract, .invalidPath, .invalidIdentity,
                        .corruptRegistry, .registryLimitExceeded,
                        .duplicateLease, .uncertainOwner,
                        .protectedDataUnavailable:
                    throw WholeSignDeletionServiceError.saveFailed
                }
            }
            return
        }
#if DEBUG
        guard writerLeaseHandle == nil, allowsLegacyXCTestFallback else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        // Synthetic pre-generation test stores have no current pointer or
        // manifest from which production authority can be derived. Preserve
        // their historical fault-injection and rollback behavior only in the
        // XCTest process; this branch is not compiled into RELEASE.
        try stageMutationSemanticState()
        try inject(.databaseSave)
        try modelContext.save()
#else
        throw WholeSignDeletionServiceError.invalidGeneration
#endif
    }

#if DEBUG
    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
            != nil
    }
#endif

    private func inject(_ point: WholeSignDeletionFailurePoint) throws {
        if failureInjection?.consume(point) == true {
            throw WholeSignDeletionServiceError.injectedFailure
        }
    }

    private func cleanup(_ intent: DeletionIntentV1) throws {
        for path in intent.relativePaths {
            try inject(.fileCleanup)
            do {
                try files.removeIfPresent(relativePath: path)
            } catch {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
        }
        let evidenceIDs = Set(intent.relativePaths.compactMap { path -> UUID? in
            let components = path.split(separator: "/").map(String.init)
            guard components.count == 3, components[0] == "evidence" else { return nil }
            return UUID(uuidString: components[1])
        })
        for id in evidenceIDs {
            do { try files.removeEvidenceBundleIfEmpty(id: id) }
            catch { throw WholeSignDeletionServiceError.cleanupFailed }
        }
    }
}

private extension WholeSignDeletionService {
    func mutationHistoryAuthorityMatches(
        _ before: MutationHistorySnapshotV1?,
        _ after: MutationHistorySnapshotV1?
    ) -> Bool {
        guard let before, let after else { return before == nil && after == nil }
        return before.schemaVersion == after.schemaVersion
            && before.workspaceRevision == after.workspaceRevision
            && before.lastLocalSequence == after.lastLocalSequence
            && before.receipts == after.receipts
            && before.quarantines == after.quarantines
            && before.entityRevisions.map {
                "\($0.identity.stableKey):\($0.revision)"
            } == after.entityRevisions.map {
                "\($0.identity.stableKey):\($0.revision)"
            }
    }

    func stageMutationSemanticState() throws {
        var descriptor = FetchDescriptor<WorkspaceMutationStateRow>()
        descriptor.fetchLimit = 2
        let states = try modelContext.fetch(descriptor)
        guard states.count == 1,
              let state = states.first,
              state.generationID == generationID else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        do {
            let identity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: state.workspaceID),
                replicaID: ReplicaID(rawValue: state.activeReplicaID)
            )
            try mutationJournalStore(identity: identity)
                .stageMutableSemanticStateAfterAuthorizedExternalMutation()
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    func mutationHistorySnapshot() throws -> MutationHistorySnapshotV1? {
        var descriptor = FetchDescriptor<WorkspaceMutationStateRow>()
        descriptor.fetchLimit = 2
        let states = try modelContext.fetch(descriptor)
        guard states.count <= 1 else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        guard let state = states.first else {
            guard try modelContext.fetchCount(
                    FetchDescriptor<MutationReceiptRow>()
                  ) == 0,
                  try modelContext.fetchCount(
                    FetchDescriptor<MutationQuarantineRow>()
                  ) == 0,
                  try modelContext.fetchCount(
                    FetchDescriptor<EntityMutationRevisionRow>()
                  ) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            return nil
        }
        guard state.generationID == generationID else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        do {
            let identity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: state.workspaceID),
                replicaID: ReplicaID(rawValue: state.activeReplicaID)
            )
            return try mutationJournalStore(identity: identity)
                .exportSnapshot()
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    func mutationJournalStore(
        identity: WorkspaceReplicaIdentityV1
    ) throws -> MutationJournalStoreV1 {
        if let staleWriterFence {
            return try MutationJournalStoreV1(
                modelContext: modelContext,
                identity: identity,
                generationID: generationID,
                allowStateBootstrap: false,
                staleWriterFence: staleWriterFence
            )
        }
#if DEBUG
        guard writerLeaseHandle == nil, allowsLegacyXCTestFallback else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        return try MutationJournalStoreV1(
            modelContext: modelContext,
            identity: identity,
            generationID: generationID
        )
#else
        throw WholeSignDeletionServiceError.invalidGeneration
#endif
    }

    struct Rows {
        let sites: [Site]
        let assets: [Asset]
        let records: [WorkflowRecord]
        let evidence: [EvidenceFile]
        let issues: [Issue]
        let packets: [Packet]
        let reports: [Report]
    }

    func fetchRows() throws -> Rows {
        do {
            return Rows(
                sites: try boundedFetch(Site.self),
                assets: try boundedFetch(Asset.self),
                records: try boundedFetch(WorkflowRecord.self),
                evidence: try boundedFetch(EvidenceFile.self),
                issues: try boundedFetch(Issue.self),
                packets: try boundedFetch(Packet.self),
                reports: try boundedFetch(Report.self)
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func boundedFetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = Self.maximumGraphRowsPerKind + 1
        let rows = try modelContext.fetch(descriptor)
        guard rows.count <= Self.maximumGraphRowsPerKind else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        return rows
    }

    func makeRuleInput(
        rows: Rows,
        assetID: UUID,
        deletionID: UUID,
        deletedAt: Date
    ) -> WholeSignDeletionRuleInput {
        WholeSignDeletionRuleInput(
            assetID: assetID,
            deletionID: deletionID,
            deletedAt: deletedAt,
            generationID: generationID,
            sites: rows.sites.map { .init(id: $0.id, schemaVersion: $0.schemaVersion) },
            assets: rows.assets.map {
                .init(id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID)
            },
            records: rows.records.map(payload),
            evidence: rows.evidence.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    recordID: $0.recordID, purposeKey: $0.purposeKey,
                    relativePath: $0.relativePath, mimeType: $0.mimeType,
                    byteCount: $0.byteCount, sha256: $0.sha256,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount,
                    thumbnailSHA256: $0.thumbnailSHA256
                )
            },
            issues: rows.issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    assetID: $0.assetID, openedByRecordID: $0.openedByRecordID,
                    labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot,
                    status: $0.status, resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            packets: rows.packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt, createdAt: $0.createdAt
                )
            },
            reports: rows.reports.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    packetID: $0.packetID, sourceRecordID: $0.sourceRecordID,
                    snapshotSchemaVersion: $0.snapshotSchemaVersion,
                    snapshotRelativePath: $0.snapshotRelativePath,
                    snapshotSHA256: $0.snapshotSHA256, pdfState: $0.pdfState,
                    pdfRelativePath: $0.pdfRelativePath, pdfSHA256: $0.pdfSHA256,
                    createdAt: $0.createdAt, replacesReportID: $0.replacesReportID
                )
            }
        )
    }

    func explicitSiteInput(
        site: Site,
        rows: Rows,
        deletionID: UUID,
        deletedAt: Date
    ) throws -> ExplicitSiteDeletionInputV1 {
        let assetPlans = try rows.assets
            .filter { $0.siteID == site.id }
            .map { asset in
                try WholeSignDeletionRule.makePlan(makeRuleInput(
                    rows: rows,
                    assetID: asset.id,
                    deletionID: deletionID,
                    deletedAt: deletedAt
                ))
            }
        return ExplicitSiteDeletionInputV1(
            siteID: site.id,
            generationID: generationID,
            deletionID: deletionID,
            deletedAt: deletedAt,
            siteSchemaVersion: site.schemaVersion,
            label: site.label,
            address: site.address,
            timeZoneID: site.timeZoneID,
            createdAt: site.createdAt,
            updatedAt: site.updatedAt,
            siteAssets: rows.assets.filter { $0.siteID == site.id }.map {
                DeletionAssetPayloadV1(
                    id: $0.id,
                    schemaVersion: $0.schemaVersion,
                    siteID: $0.siteID
                )
            },
            assetPlans: assetPlans
        )
    }

    func payload(_ row: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: row.id, schemaVersion: row.schemaVersion, assetID: row.assetID,
            packetID: row.packetID, issueID: row.issueID,
            parentRecordID: row.parentRecordID,
            recordRevisionRootID: row.recordRevisionRootID,
            revisesRecordID: row.revisesRecordID,
            evidenceSourceRecordID: row.evidenceSourceRecordID,
            revisionKind: row.revisionKind, stage: row.stage, state: row.state,
            draftStepKey: row.draftStepKey, startedAt: row.startedAt,
            completedAt: row.completedAt, observedAtUTC: row.observedAtUTC,
            timeZoneID: row.timeZoneID, utcOffsetMinutes: row.utcOffsetMinutes,
            localDate: row.localDate, localTime: row.localTime,
            afterDarkAcknowledgementKey: row.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: row.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: row.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: row.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: row.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: row.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: row.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: row.safePositionAcknowledgementAccepted,
            packID: row.packID, packSchemaVersion: row.packSchemaVersion,
            packContentVersion: row.packContentVersion,
            pdfTemplateID: row.pdfTemplateID,
            pdfTemplateVersion: row.pdfTemplateVersion,
            outcomeKey: row.outcomeKey, couldNotVerifyKey: row.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: row.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: row.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: row.workPerformedLocalDate,
            workDescription: row.workDescription, note: row.note,
            finalizationMutationID: row.finalizationMutationID
        )
    }

    func validateOwnedFiles(plan: WholeSignDeletionPlan, rows: Rows) throws {
        if !plan.reportIDs.isEmpty {
            let coordinator: ReportDeliveryCoordinator
            do {
                coordinator = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    signPack: .illuminatedSignV1
                )
                for reportID in plan.reportIDs {
                    try coordinator.validateRecoveryAuthority(id: reportID)
                }
            } catch {
                throw WholeSignDeletionServiceError.fileInvalid
            }
        }
        let evidenceByPath = Dictionary(uniqueKeysWithValues: rows.evidence.flatMap {
            [($0.relativePath, ($0.byteCount, $0.sha256, true)),
             ($0.thumbnailRelativePath, ($0.thumbnailByteCount, $0.thumbnailSHA256, true))]
        })
        let reportsByPath = Dictionary(uniqueKeysWithValues: rows.reports.flatMap { report in
            var values = [(report.snapshotRelativePath, (Int?.none, report.snapshotSHA256, false))]
            if let path = report.pdfRelativePath, let hash = report.pdfSHA256 {
                values.append((path, (Int?.none, hash, false)))
            }
            return values
        })
        let snapshotReports = Dictionary(uniqueKeysWithValues: rows.reports.map {
            ($0.snapshotRelativePath, $0)
        })
        for path in plan.intent.relativePaths {
            let data: Data
            let maximumByteCount: Int
            if evidenceByPath[path] != nil {
                maximumByteCount = path.hasSuffix("thumbnail.jpg")
                    ? MediaContractV1.thumbnailByteCountMaximum
                    : MediaContractV1.originalByteCountMaximum
            } else if path.hasPrefix("snapshots/") {
                maximumByteCount = Self.maximumSnapshotByteCount
            } else {
                maximumByteCount = Self.maximumPDFByteCount
            }
            do {
                data = try files.read(
                    relativePath: path,
                    maximumByteCount: maximumByteCount
                )
            }
            catch { throw WholeSignDeletionServiceError.fileInvalid }
            if let authority = evidenceByPath[path] {
                guard data.count == authority.0,
                      sha256(data) == authority.1 else {
                    throw WholeSignDeletionServiceError.fileInvalid
                }
                do {
                    _ = try MediaNormalizerV1().validateCanonicalJPEG(
                        data,
                        kind: path.hasSuffix("thumbnail.jpg") ? .thumbnail : .original
                    )
                } catch { throw WholeSignDeletionServiceError.fileInvalid }
            } else if let authority = reportsByPath[path] {
                guard sha256(data) == authority.1 else {
                    throw WholeSignDeletionServiceError.fileInvalid
                }
                if let report = snapshotReports[path] {
                    do {
                        let snapshot = try ReportSnapshotEncoderV1().decode(data)
                        guard try ReportSnapshotEncoderV1().encode(snapshot).data == data,
                              snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion,
                              snapshot.reportID == report.id,
                              snapshot.packetID == report.packetID,
                              snapshot.sourceRecordID == report.sourceRecordID else {
                            throw WholeSignDeletionServiceError.fileInvalid
                        }
                    } catch {
                        throw WholeSignDeletionServiceError.fileInvalid
                    }
                } else if path.hasPrefix("pdfs/") {
                    guard data.starts(with: Data("%PDF-".utf8)),
                          data.count >= 6 else {
                        throw WholeSignDeletionServiceError.fileInvalid
                    }
                }
            } else {
                throw WholeSignDeletionServiceError.fileInvalid
            }
        }
        for id in plan.evidenceIDs {
            do {
                try files.validateEvidenceBundle(id: id)
                try files.requireAbsent(
                    components: [".staging", "evidence", id.uuidString.lowercased()]
                )
            }
            catch { throw WholeSignDeletionServiceError.fileInvalid }
        }
        for reportID in plan.reportIDs {
            do {
                try files.requireAbsent(
                    components: [".staging", "pdfs", "\(reportID.uuidString.lowercased()).pdf"]
                )
            } catch { throw WholeSignDeletionServiceError.fileInvalid }
        }
        let selectedRecordIDs = Set(plan.workflowRecordIDs)
        let selectedRecords = rows.records.filter { selectedRecordIDs.contains($0.id) }
        for mutationID in selectedRecords.compactMap(\.finalizationMutationID) {
            do {
                try files.requireAbsent(
                    components: [
                        ".staging", "snapshots",
                        "\(mutationID.uuidString.lowercased()).json",
                    ]
                )
            } catch { throw WholeSignDeletionServiceError.fileInvalid }
        }
    }

    func preparedPlan(
        _ intent: DeletionIntentV1,
        rows: Rows
    ) throws -> WholeSignDeletionPlan? {
        guard intent.schemaVersion == 2 else { return nil }
        let dates = Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt))
        let ledgerDates = Set(intent.ledgerEntries.map(\.deletedAt))
        guard dates.count <= 1,
              ledgerDates.count == 1,
              let ledgerDate = ledgerDates.first else { return nil }
        let input = makeRuleInput(
            rows: rows, assetID: intent.assetID,
            deletionID: intent.deletionID,
            deletedAt: dates.first ?? ledgerDate
        )
        guard let plan = try? WholeSignDeletionRule.makePlan(input),
              plan.intent == intent else { return nil }
        try validateOwnedFiles(plan: plan, rows: rows)
        return plan
    }

    func legacyPreparedIntentMatches(
        _ intent: DeletionIntentV1,
        rows: Rows
    ) throws -> Bool {
        guard intent.schemaVersion == 1, intent.ledgerEntries.isEmpty else { return false }
        let dates = Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt))
        guard dates.count <= 1 else { return false }
        let input = makeRuleInput(
            rows: rows,
            assetID: intent.assetID,
            deletionID: intent.deletionID,
            deletedAt: dates.first ?? .distantPast
        )
        guard let plan = try? WholeSignDeletionRule.makePlan(input) else { return false }
        let legacy = DeletionIntentV1(
            assetID: plan.intent.assetID,
            countedPacketTombstones: plan.intent.countedPacketTombstones,
            deletionID: plan.intent.deletionID,
            generationID: plan.intent.generationID,
            ledgerEntries: [],
            phase: plan.intent.phase,
            relativePaths: plan.intent.relativePaths,
            schemaVersion: 1
        )
        guard legacy == intent else { return false }
        try validateOwnedFiles(plan: plan, rows: rows)
        return true
    }

    func committedStateMatches(_ intent: DeletionIntentV1, rows: Rows) throws -> Bool {
        let tombstones = Dictionary(uniqueKeysWithValues:
            intent.countedPacketTombstones.map { ($0.id, $0) }
        )
        guard unique(rows.sites.map(\.id)),
              unique(rows.assets.map(\.id)),
              unique(rows.records.map(\.id)),
              unique(rows.evidence.map(\.id)),
              unique(rows.issues.map(\.id)),
              unique(rows.packets.map(\.id)),
              unique(rows.packets.map(\.stableRootID)),
              unique(rows.reports.map(\.id)),
              rows.sites.allSatisfy({ $0.schemaVersion == 1 }),
              rows.assets.allSatisfy({ asset in
                  asset.schemaVersion == 1
                    && rows.sites.contains(where: { $0.id == asset.siteID })
              }),
              rows.records.allSatisfy({ record in
                  record.assetID != intent.assetID
                    && rows.assets.contains(where: { $0.id == record.assetID })
                    && record.parentRecordID.map({ parent in
                        rows.records.contains(where: {
                            $0.id == parent && $0.assetID == record.assetID
                        })
                    }) ?? true
              }),
              rows.issues.allSatisfy({ $0.assetID != intent.assetID }),
              tombstones.allSatisfy({ id, expected in
                  rows.packets.filter({ $0.id == id }).count == 1
                    && rows.packets.first(where: { $0.id == id }).map {
                        $0.schemaVersion == expected.schemaVersion
                            && $0.stableRootID == expected.stableRootID
                            && $0.currentRecordID == nil
                            && $0.evaluationCounted
                            && $0.contentDeletedAt == expected.contentDeletedAt
                            && $0.createdAt == expected.createdAt
                    } == true
              }),
              rows.evidence.allSatisfy({ evidence in
                  rows.records.contains(where: { $0.id == evidence.recordID })
              }),
              rows.reports.allSatisfy({ report in
                  rows.records.contains(where: { $0.id == report.sourceRecordID })
                    && rows.packets.contains(where: { $0.id == report.packetID })
              }),
              rows.packets.allSatisfy({ packet in
                  if let recordID = packet.currentRecordID {
                      return packet.contentDeletedAt == nil
                        && rows.records.contains(where: {
                            $0.id == recordID && $0.packetID == packet.id
                        })
                  }
                  return packet.evaluationCounted && packet.contentDeletedAt != nil
                    && rows.records.allSatisfy({ $0.packetID != packet.id })
                    && rows.reports.allSatisfy({ $0.packetID != packet.id })
              }),
              intent.ledgerEntries.allSatisfy({ entry in
                  if entry.identity.kind == .packet,
                     tombstones[entry.identity.id] != nil {
                      return true
                  }
                  return !contains(entry.identity, rows: rows)
              }) else { return false }
        if intent.schemaVersion == 2 {
            do {
                try ledgerStore.requireContains(Set(intent.ledgerEntries.map(\.identity)))
            } catch {
                return false
            }
        }
        return true
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    func contains(_ identity: DeletionIdentityV2, rows: Rows) -> Bool {
        switch identity.kind {
        case .site:
            return rows.sites.contains { $0.id == identity.id }
        case .asset:
            return rows.assets.contains { $0.id == identity.id }
        case .workflowRecord:
            return rows.records.contains { $0.id == identity.id }
        case .evidenceFile:
            return rows.evidence.contains { $0.id == identity.id }
        case .issue:
            return rows.issues.contains { $0.id == identity.id }
        case .packet:
            return rows.packets.contains { $0.id == identity.id }
        case .report:
            return rows.reports.contains { $0.id == identity.id }
        }
    }

    func apply(plan: WholeSignDeletionPlan, rows: Rows) throws {
        let evidenceIDs = Set(plan.evidenceIDs)
        let issueIDs = Set(plan.issueIDs)
        let reportIDs = Set(plan.reportIDs)
        let recordIDs = Set(plan.workflowRecordIDs)
        let packetDeleteIDs = Set(plan.packetIDsToDelete)
        let tombstones = Dictionary(uniqueKeysWithValues:
            plan.intent.countedPacketTombstones.map { ($0.id, $0) }
        )
        rows.evidence.filter { evidenceIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        rows.issues.filter { issueIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        rows.reports.filter { reportIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        rows.records.filter { recordIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        rows.packets.filter { packetDeleteIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        for packet in rows.packets {
            if let tombstone = tombstones[packet.id] {
                packet.currentRecordID = nil
                packet.evaluationCounted = true
                packet.contentDeletedAt = tombstone.contentDeletedAt
            }
        }
        guard let asset = rows.assets.first(where: { $0.id == plan.assetID }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        modelContext.delete(asset)
        guard plan.siteIDToDelete == nil else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func requireLedgerEntriesUnseen(_ intent: DeletionIntentV1) throws {
        try requireLedgerIdentitiesUnseen(intent.ledgerEntries.map(\.identity))
    }

    func requireLedgerIdentitiesUnseen(_ identities: [DeletionIdentityV2]) throws {
        let expected = Set(identities)
        do {
            let existing = Set(try ledgerStore.snapshot().entries.map(\.identity))
            guard expected.isDisjoint(with: existing) else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    static let maximumGraphRowsPerKind = DeletionLedgerV2.maximumEntryCount
}

private final class DeletionGenerationFiles {
    private let rootURL: URL?
    private let identity: Identity?
    let generationID: UUID

    var isValid: Bool { rootURL != nil && identity != nil }
    static let invalid = DeletionGenerationFiles()

    private init() {
        rootURL = nil
        identity = nil
        generationID = UUID()
    }

    init(rootURL: URL) throws {
        let root = rootURL.standardizedFileURL
        guard let parsed = UUID(uuidString: root.lastPathComponent),
              parsed.uuidString.lowercased() == root.lastPathComponent else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        let descriptor = try Self.openRoot(root)
        defer { Darwin.close(descriptor) }
        identity = try Self.identity(descriptor, directory: true)
        self.rootURL = root
        generationID = parsed
    }

    func read(relativePath: String, maximumByteCount: Int) throws -> Data {
        try withParent(relativePath) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw WholeSignDeletionServiceError.fileInvalid }
            defer { Darwin.close(descriptor) }
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_nlink == 1,
                  let data = DeletionDescriptorRead.read(
                    descriptor: descriptor,
                    declaredSize: info.st_size,
                    maximumByteCount: maximumByteCount
                  ) else {
                throw WholeSignDeletionServiceError.fileInvalid
            }
            var after = stat()
            guard Darwin.fstat(descriptor, &after) == 0,
                  info.st_dev == after.st_dev,
                  info.st_ino == after.st_ino,
                  info.st_size == after.st_size,
                  data.count == Int(after.st_size) else {
                throw WholeSignDeletionServiceError.fileInvalid
            }
            return data
        }
    }

    func removeIfPresent(relativePath: String) throws {
        try withParent(relativePath) { parent, leaf in
            var before = stat()
            if Darwin.fstatat(parent, leaf, &before, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else {
                    throw WholeSignDeletionServiceError.cleanupFailed
                }
                return
            }
            guard (before.st_mode & S_IFMT) == S_IFREG, before.st_nlink == 1 else {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
            defer { Darwin.close(descriptor) }
            let opened = try Self.identity(descriptor, directory: false)
            guard opened == Identity(device: before.st_dev, inode: before.st_ino),
                  Darwin.unlinkat(parent, leaf, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
        }
    }

    func validateEvidenceBundle(id: UUID) throws {
        try withEvidenceParent { evidence in
            let name = id.uuidString.lowercased()
            let bundle = Darwin.openat(
                evidence, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard bundle >= 0 else { throw WholeSignDeletionServiceError.fileInvalid }
            defer { Darwin.close(bundle) }
            guard try Self.names(in: bundle) == ["original.jpg", "thumbnail.jpg"] else {
                throw WholeSignDeletionServiceError.fileInvalid
            }
        }
    }

    func removeEvidenceBundleIfEmpty(id: UUID) throws {
        try withEvidenceParent { evidence in
            let name = id.uuidString.lowercased()
            if Darwin.unlinkat(evidence, name, AT_REMOVEDIR) != 0 {
                guard errno == ENOENT else {
                    throw WholeSignDeletionServiceError.cleanupFailed
                }
            } else if Darwin.fsync(evidence) != 0 {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
        }
    }

    func requireAbsent(components: [String]) throws {
        guard !components.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty && component != "." && component != ".."
                    && !component.contains("/") && !component.contains("\\")
              }),
              let rootURL, let identity else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
        var descriptor = try Self.openRoot(rootURL)
        defer { Darwin.close(descriptor) }
        guard try Self.identity(descriptor, directory: true) == identity else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        for component in components.dropLast() {
            let next = Darwin.openat(
                descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if next < 0 {
                guard errno == ENOENT else {
                    throw WholeSignDeletionServiceError.fileInvalid
                }
                return
            }
            Darwin.close(descriptor)
            descriptor = next
        }
        guard let leaf = components.last else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
        var info = stat()
        guard Darwin.fstatat(
            descriptor, leaf, &info, AT_SYMLINK_NOFOLLOW
        ) != 0, errno == ENOENT else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
    }

    private func withEvidenceParent<T>(_ body: (Int32) throws -> T) throws -> T {
        guard let rootURL, let identity else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        let root = try Self.openRoot(rootURL)
        defer { Darwin.close(root) }
        guard try Self.identity(root, directory: true) == identity else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        let evidence = Darwin.openat(
            root, "evidence", O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard evidence >= 0 else { throw WholeSignDeletionServiceError.fileInvalid }
        defer { Darwin.close(evidence) }
        return try body(evidence)
    }

    private func withParent<T>(
        _ relativePath: String,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        guard DeletionIntentEncoderV1.validRelativePath(relativePath),
              let rootURL, let identity else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
        let components = relativePath.split(separator: "/").map(String.init)
        guard let leaf = components.last else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
        var descriptor = try Self.openRoot(rootURL)
        defer { Darwin.close(descriptor) }
        guard try Self.identity(descriptor, directory: true) == identity else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
        for component in components.dropLast() {
            let next = Darwin.openat(
                descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard next >= 0 else { throw WholeSignDeletionServiceError.fileInvalid }
            Darwin.close(descriptor)
            descriptor = next
        }
        return try body(descriptor, leaf)
    }

    private static func openRoot(_ root: URL) throws -> Int32 {
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        guard generations.lastPathComponent == "generations",
              dataRoot.lastPathComponent == "FieldEvidenceData" else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        let data = Darwin.open(dataRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard data >= 0 else { throw WholeSignDeletionServiceError.invalidGeneration }
        defer { Darwin.close(data) }
        let generationsFD = Darwin.openat(
            data, "generations", O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard generationsFD >= 0 else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        defer { Darwin.close(generationsFD) }
        let result = Darwin.openat(
            generationsFD, root.lastPathComponent,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard result >= 0 else { throw WholeSignDeletionServiceError.invalidGeneration }
        return result
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func identity(_ descriptor: Int32, directory: Bool) throws -> Identity {
        var info = stat()
        let expected = directory ? S_IFDIR : S_IFREG
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == expected else {
            throw WholeSignDeletionServiceError.fileInvalid
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func names(in descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw WholeSignDeletionServiceError.fileInvalid
        }
        defer { Darwin.closedir(directory) }
        var result = [String]()
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." {
                guard result.count < 16 else {
                    throw WholeSignDeletionServiceError.fileInvalid
                }
                result.append(name)
            }
            errno = 0
        }
        guard errno == 0 else { throw WholeSignDeletionServiceError.fileInvalid }
        return result.sorted()
    }
}

private final class DeletionJournalStore {
    private static let maximumJournalEntryCount = 1_024
    private static let maximumJournalFileByteCount = 64 * 1_024 * 1_024
    private static let maximumJournalEnumerationByteCount: Int64 = 64 * 1_024 * 1_024
    private let applicationSupportURL: URL?
    private let identity: Identity?
    private let operationsIdentity: Identity?
    private let deletionIdentity: Identity?
    var isValid: Bool {
        applicationSupportURL != nil && identity != nil
            && operationsIdentity != nil && deletionIdentity != nil
    }
    static let invalid = DeletionJournalStore()

    private init() {
        applicationSupportURL = nil
        identity = nil
        operationsIdentity = nil
        deletionIdentity = nil
    }

    init(applicationSupportURL: URL) throws {
        let root = applicationSupportURL.standardizedFileURL
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        defer { Darwin.close(descriptor) }
        let capturedIdentity = try Self.identity(descriptor)
        let operations = try Self.openOrCreateDirectory(
            parent: descriptor,
            name: "FieldEvidenceOperations"
        )
        defer { Darwin.close(operations) }
        let capturedOperationsIdentity = try Self.identity(operations)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: "FieldEvidenceOperations",
                within: root
            ) {
                guard try Self.identity(descriptor) == capturedIdentity,
                      try Self.identity(operations) == capturedOperationsIdentity else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
            }
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        let deletion = try Self.openOrCreateDirectory(
            parent: operations,
            name: "deletion"
        )
        defer { Darwin.close(deletion) }
        let capturedDeletionIdentity = try Self.identity(deletion)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: "FieldEvidenceOperations/deletion",
                within: root
            ) {
                guard try Self.identity(descriptor) == capturedIdentity,
                      try Self.identity(operations) == capturedOperationsIdentity,
                      try Self.identity(deletion) == capturedDeletionIdentity else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
            }
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        self.applicationSupportURL = root
        identity = capturedIdentity
        operationsIdentity = capturedOperationsIdentity
        deletionIdentity = capturedDeletionIdentity
    }

    func create(_ intent: DeletionIntentV1) throws {
        try write(intent, exclusive: true)
    }

    func replace(_ intent: DeletionIntentV1) throws {
        guard intent.phase == .databaseCommitted else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        let expected = intent.withPhase(.prepared)
        try verifyExistingPolicy(.journal, name: Self.name(intent.deletionID))
        try withDeletionDirectory { descriptor in
            let existing = try Self.decode(
                Self.read(descriptor: descriptor, name: Self.name(intent.deletionID))
            )
            guard existing == expected else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
        }
        try write(intent, exclusive: false)
    }

    func remove(_ expected: DeletionIntentV1) throws {
        try verifyExistingPolicy(.journal, name: Self.name(expected.deletionID))
        try withDeletionDirectory { descriptor in
            let name = Self.name(expected.deletionID)
            let existing = try Self.decode(Self.read(descriptor: descriptor, name: name))
            guard existing == expected else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            guard Darwin.unlinkat(descriptor, name, 0) == 0,
                  Darwin.fsync(descriptor) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
        }
    }

    func loadAll() throws -> [DeletionIntentV1] {
        try withDeletionDirectory { descriptor in
            let duplicate = Darwin.dup(descriptor)
            guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
                if duplicate >= 0 { Darwin.close(duplicate) }
                throw WholeSignDeletionServiceError.journalInvalid
            }
            defer { Darwin.closedir(directory) }
            var names = [String]()
            errno = 0
            while let entry = Darwin.readdir(directory) {
                var tuple = entry.pointee.d_name
                let capacity = MemoryLayout.size(ofValue: tuple)
                let name = withUnsafePointer(to: &tuple) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                        String(cString: $0)
                    }
                }
                if name != "." && name != ".." {
                    guard names.count < Self.maximumJournalEntryCount else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                    names.append(name)
                }
                errno = 0
            }
            guard errno == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            let temporaryNames = names.filter { Self.temporaryIdentifier($0) != nil }
            let journalNames = names.filter { Self.journalIdentifier($0) != nil }
            guard temporaryNames.count + journalNames.count == names.count else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            var enumeratedBytes: Int64 = 0
            for name in names {
                var info = stat()
                guard Darwin.fstatat(
                    descriptor,
                    name,
                    &info,
                    AT_SYMLINK_NOFOLLOW
                ) == 0,
                      (info.st_mode & S_IFMT) == S_IFREG,
                      info.st_nlink == 1,
                      info.st_size >= 0,
                      Int64(info.st_size) <= Int64(Self.maximumJournalFileByteCount),
                      enumeratedBytes
                        <= Self.maximumJournalEnumerationByteCount - Int64(info.st_size) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                enumeratedBytes += Int64(info.st_size)
            }
            let journalIDs = Set(journalNames.compactMap(Self.journalIdentifier))
            for temporary in temporaryNames {
                try verifyExistingPolicy(.journalTemporary, name: temporary)
                guard let temporaryID = Self.temporaryIdentifier(temporary) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let file = Darwin.openat(descriptor, temporary, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                var info = stat()
                guard Darwin.fstat(file, &info) == 0,
                      (info.st_mode & S_IFMT) == S_IFREG,
                      info.st_nlink == 1 else {
                    Darwin.close(file)
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let expectedTemporary = Identity(
                    device: info.st_dev,
                    inode: info.st_ino
                )
                Darwin.close(file)
                if journalIDs.contains(temporaryID) {
                    let existing = try Self.decode(
                        Self.read(descriptor: descriptor, name: Self.name(temporaryID))
                    )
                    let replacement = try Self.decode(
                        Self.read(descriptor: descriptor, name: temporary)
                    )
                    guard existing.deletionID == temporaryID,
                          existing.phase == .prepared,
                          replacement == existing.withPhase(.databaseCommitted) else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                }
                try Self.removeIfExact(
                    descriptor: descriptor,
                    name: temporary,
                    expected: expectedTemporary
                )
            }
            if !temporaryNames.isEmpty, Darwin.fsync(descriptor) != 0 {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            return try journalNames.sorted().map { name in
                try verifyExistingPolicy(.journal, name: name)
                guard let identifier = Self.journalIdentifier(name) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let data = try Self.read(descriptor: descriptor, name: name)
                let intent = try Self.decode(data)
                guard intent.deletionID == identifier else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                return intent
            }
        }
    }

    private func write(_ intent: DeletionIntentV1, exclusive: Bool) throws {
        let data: Data
        do { data = try DeletionIntentEncoderV1().encode(intent).data }
        catch { throw WholeSignDeletionServiceError.journalInvalid }
        try withDeletionDirectory { descriptor in
            let name = Self.name(intent.deletionID)
            let temporary = ".\(intent.deletionID.uuidString.lowercased()).tmp"
            var temporaryInfo = stat()
            guard Darwin.fstatat(
                descriptor,
                temporary,
                &temporaryInfo,
                AT_SYMLINK_NOFOLLOW
            ) != 0, errno == ENOENT else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            let file = Darwin.openat(
                descriptor, temporary,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR)
            )
            guard file >= 0 else { throw WholeSignDeletionServiceError.journalInvalid }
            defer { Darwin.close(file) }
            let expectedTemporary = try Self.fileIdentity(file)
            var succeeded = false
            var published = false
            var swapped = false
            defer {
                if !succeeded && !published {
                    try? Self.removeIfExact(
                        descriptor: descriptor,
                        name: temporary,
                        expected: expectedTemporary
                    )
                }
            }
            try applyPolicy(
                .journalTemporary,
                name: temporary,
                descriptor: file,
                expected: expectedTemporary
            )
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var written = 0
                while written < raw.count {
                    let count = Darwin.write(file, base.advanced(by: written), raw.count - written)
                    guard count > 0 else { throw WholeSignDeletionServiceError.journalInvalid }
                    written += count
                }
            }
            guard Darwin.fsync(file) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            guard let temporaryValue = try Self.readValueIfPresent(
                descriptor: descriptor,
                name: temporary
            ), temporaryValue.identity == expectedTemporary,
                  temporaryValue.data == data else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            let priorValue: ReadValue?
            if exclusive {
                priorValue = nil
            } else {
                let expectedData: Data
                do {
                    expectedData = try DeletionIntentEncoderV1()
                        .encode(intent.withPhase(.prepared)).data
                } catch {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                guard let existing = try Self.readValueIfPresent(
                    descriptor: descriptor,
                    name: name
                ), existing.data == expectedData else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                priorValue = existing
            }
            let flags = exclusive ? UInt32(RENAME_EXCL) : UInt32(RENAME_SWAP)
            guard Darwin.renameatx_np(
                descriptor,
                temporary,
                descriptor,
                name,
                flags
            ) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            published = true
            swapped = priorValue != nil
            do {
                guard Darwin.fsync(descriptor) == 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                try verifyPublishedPolicy(
                    .journal,
                    name: name,
                    expectedIdentity: temporaryValue.identity
                )
                guard let publishedValue = try Self.readValueIfPresent(
                    descriptor: descriptor,
                    name: name
                ), publishedValue.identity == temporaryValue.identity,
                      publishedValue.data == data else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                if let priorValue {
                    try verifyPublishedPolicy(
                        .journalTemporary,
                        name: temporary,
                        expectedIdentity: priorValue.identity
                    )
                    guard let displaced = try Self.readValueIfPresent(
                        descriptor: descriptor,
                        name: temporary
                    ), displaced.identity == priorValue.identity,
                          displaced.data == priorValue.data else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                    try Self.removeExact(
                        descriptor: descriptor,
                        name: temporary,
                        expected: displaced
                    )
                    swapped = false
                }
                succeeded = true
            } catch {
                if let priorValue, swapped {
                    do {
                        if let publishedValue = try Self.readValueIfPresent(
                            descriptor: descriptor,
                            name: name
                        ), let displaced = try Self.readValueIfPresent(
                            descriptor: descriptor,
                            name: temporary
                        ), publishedValue.identity == temporaryValue.identity,
                              publishedValue.data == data,
                              displaced.identity == priorValue.identity,
                              displaced.data == priorValue.data,
                              Darwin.renameatx_np(
                                descriptor,
                                temporary,
                                descriptor,
                                name,
                                UInt32(RENAME_SWAP)
                              ) == 0,
                              Darwin.fsync(descriptor) == 0 {
                            try Self.removeExact(
                                descriptor: descriptor,
                                name: temporary,
                                expected: temporaryValue
                            )
                            published = false
                            swapped = false
                        }
                    } catch {
                        // Preserve the exact failure and leave uncertain state for recovery.
                    }
                } else if priorValue == nil, published {
                    do {
                        try Self.removeExact(
                            descriptor: descriptor,
                            name: name,
                            expected: temporaryValue
                        )
                        published = false
                    } catch {
                        // Preserve the exact failure and leave uncertain state for recovery.
                    }
                }
                throw error
            }
        }
    }

    private func policyRelativePath(_ name: String) -> String {
        "FieldEvidenceOperations/deletion/\(name)"
    }

    private func verifyExistingPolicy(
        _ kind: OwnedFileKindV1,
        name: String
    ) throws {
        guard let root = applicationSupportURL else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        do {
            try withDeletionDirectory { descriptor in
                let leaf = Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_NOFOLLOW
                )
                if leaf < 0, errno == ENOENT { return }
                guard leaf >= 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                defer { Darwin.close(leaf) }
                let expected = try Self.fileIdentity(leaf)
                try ProtectedFilePolicyV1.applyAndVerify(
                    kind,
                    relativePath: policyRelativePath(name),
                    within: root
                ) {
                    try self.withDeletionDirectory { _ in }
                    try self.verifyLeaf(
                        name,
                        descriptor: leaf,
                        expected: expected
                    )
                }
            }
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private func applyPolicy(
        _ kind: OwnedFileKindV1,
        name: String,
        descriptor: Int32,
        expected: Identity
    ) throws {
        guard let root = applicationSupportURL else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: policyRelativePath(name),
                within: root
            ) {
                try self.withDeletionDirectory { _ in }
                try self.verifyLeaf(
                    name,
                    descriptor: descriptor,
                    expected: expected
                )
            }
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private func verifyLeaf(
        _ name: String,
        descriptor: Int32,
        expected: Identity
    ) throws {
        guard try Self.fileIdentity(descriptor) == expected else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        var info = stat()
        guard try withDeletionDirectory { parent in
            Darwin.fstatat(
                parent,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0
        },
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Identity(device: info.st_dev, inode: info.st_ino) == expected else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private func verifyPublishedPolicy(
        _ kind: OwnedFileKindV1,
        name: String,
        expectedIdentity: Identity
    ) throws {
        guard let root = applicationSupportURL else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        do {
            try withDeletionDirectory { descriptor in
                let leaf = Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_NOFOLLOW
                )
                guard leaf >= 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                defer { Darwin.close(leaf) }
                guard try Self.fileIdentity(leaf) == expectedIdentity else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                try self.verifyLeaf(
                    name,
                    descriptor: leaf,
                    expected: expectedIdentity
                )
                try ProtectedFilePolicyV1.verify(
                    kind,
                    at: root
                        .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
                        .appendingPathComponent("deletion", isDirectory: true)
                        .appendingPathComponent(name)
                )
                try self.verifyLeaf(
                    name,
                    descriptor: leaf,
                    expected: expectedIdentity
                )
            }
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private func withDeletionDirectory<T>(_ body: (Int32) throws -> T) throws -> T {
        guard let root = applicationSupportURL,
              let identity,
              let operationsIdentity,
              let deletionIdentity else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        let rootFD = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0, try Self.identity(rootFD) == identity else {
            if rootFD >= 0 { Darwin.close(rootFD) }
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        defer { Darwin.close(rootFD) }
        let operations = Darwin.openat(
            rootFD,
            "FieldEvidenceOperations",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard operations >= 0, try Self.identity(operations) == operationsIdentity else {
            if operations >= 0 { Darwin.close(operations) }
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        defer { Darwin.close(operations) }
        let deletion = Darwin.openat(
            operations,
            "deletion",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard deletion >= 0, try Self.identity(deletion) == deletionIdentity else {
            if deletion >= 0 { Darwin.close(deletion) }
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        defer { Darwin.close(deletion) }
        return try body(deletion)
    }

    private static func openOrCreateDirectory(parent: Int32, name: String) throws -> Int32 {
        var result = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if result < 0 && errno == ENOENT {
            guard Darwin.mkdirat(parent, name, mode_t(S_IRWXU)) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            result = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard result >= 0 else { throw WholeSignDeletionServiceError.journalInvalid }
        return result
    }

    private static func read(descriptor: Int32, name: String) throws -> Data {
        try readValue(descriptor: descriptor, name: name).data
    }

    private static func readValueIfPresent(
        descriptor: Int32,
        name: String
    ) throws -> ReadValue? {
        var info = stat()
        guard Darwin.fstatat(
            descriptor,
            name,
            &info,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            if errno == ENOENT { return nil }
            throw WholeSignDeletionServiceError.journalInvalid
        }
        return try readValue(descriptor: descriptor, name: name)
    }

    private static func readValue(
        descriptor: Int32,
        name: String
    ) throws -> ReadValue {
        let file = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { throw WholeSignDeletionServiceError.journalInvalid }
        defer { Darwin.close(file) }
        var before = stat()
        guard Darwin.fstat(file, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size >= 0 else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        guard let data = DeletionDescriptorRead.read(
            descriptor: file,
            declaredSize: before.st_size,
            maximumByteCount: Self.maximumJournalFileByteCount
        ) else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        var after = stat()
        guard Darwin.fstat(file, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        return ReadValue(
            data: data,
            identity: Identity(device: after.st_dev, inode: after.st_ino)
        )
    }

    private static func removeIfExact(
        descriptor: Int32,
        name: String,
        expected: Identity
    ) throws {
        guard let current = try readValueIfPresent(
            descriptor: descriptor,
            name: name
        ), current.identity == expected,
              Darwin.unlinkat(descriptor, name, 0) == 0,
              Darwin.fsync(descriptor) == 0,
              try readValueIfPresent(descriptor: descriptor, name: name) == nil else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private static func removeExact(
        descriptor: Int32,
        name: String,
        expected: ReadValue
    ) throws {
        guard let current = try readValueIfPresent(
            descriptor: descriptor,
            name: name
        ), current.identity == expected.identity,
              current.data == expected.data,
              Darwin.unlinkat(descriptor, name, 0) == 0,
              Darwin.fsync(descriptor) == 0,
              try readValueIfPresent(descriptor: descriptor, name: name) == nil else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private static func decode(_ data: Data) throws -> DeletionIntentV1 {
        do { return try DeletionIntentDecoderV1().decode(data) }
        catch { throw WholeSignDeletionServiceError.journalInvalid }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private struct ReadValue: Equatable {
        let data: Data
        let identity: Identity
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func fileIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func name(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func journalIdentifier(_ name: String) -> UUID? {
        guard name.count == 41,
              name.hasSuffix(".json"),
              let identifier = UUID(uuidString: String(name.dropLast(5))),
              Self.name(identifier) == name else {
            return nil
        }
        return identifier
    }

    private static func temporaryIdentifier(_ name: String) -> UUID? {
        guard name.count == 41,
              name.hasPrefix("."),
              name.hasSuffix(".tmp"),
              let identifier = UUID(
                uuidString: String(name.dropFirst().dropLast(4))
              ),
              ".\(identifier.uuidString.lowercased()).tmp" == name else {
            return nil
        }
        return identifier
    }
}
