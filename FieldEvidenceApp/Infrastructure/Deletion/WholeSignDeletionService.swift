import CryptoKit
import Darwin
import Foundation

enum SurveySessionWholeSignDeletionEnrollmentV1{static func validate()throws{try SurveySessionDeletionLedgerPolicyV1.validate();guard SurveySessionDeletionLedgerPolicyV1.ordinaryAssetOrSiteDeleteRetainsFrozenPublications else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}

enum C30EvidenceContextWholeSignDeletionServiceV1 {
    static let ordinaryDeletionRetainsContexts = true
    static let ordinaryDeletionRetainsPairedLinks = true
    static let workspaceEraseClearsBothFamilies = true
    static let deletionUsesRecordedRowsOnly = true

    static func validateClosure(contexts: [EvidenceContextV1],
                                links: [PairedObservationLinkV1],
                                workspaceID: WorkspaceID) throws {
        try C30EvidenceContextWholeSignDeletionRuleV1.validate(
            workspaceID: workspaceID, contexts: contexts, links: links)
        guard ordinaryDeletionRetainsContexts, ordinaryDeletionRetainsPairedLinks,
              workspaceEraseClearsBothFamilies, deletionUsesRecordedRowsOnly else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

enum C31LightingWholeSignDeletionServiceBoundaryV1 {
    static let deletesTopologyAsOneClosure = true
    static let preservesImmutableHistoryForOrdinaryDelete = true
    static let removesAllLightingRootsOnWorkspaceErase = true
    static let leavesDerivedProjectionsForRebuild = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingWholeSignDeletionBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard deletesTopologyAsOneClosure,
              preservesImmutableHistoryForOrdinaryDelete,
              removesAllLightingRootsOnWorkspaceErase,
              leavesDerivedProjectionsForRebuild else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}
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

enum IntegrationProjectionOrdinaryDeletionPolicyV1 {
    static func validate() throws {
        try KernelDeletionEraseRegistryV4.validateIntegrationProjectionLifecycle()
    }

    static func purge(
        store: any IntegrationProjectionOperationalStoreV1,
        workspaceID: WorkspaceID
    ) async throws {
        try await store.dropDerivedProjection(
            consumerID: nil,
            workspaceID: workspaceID
        )
    }
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
    case retainedInspectionReviewReferences([String])
    case retainedWorkPacketReferences([String])
    case retainedPrivacyTransformReferences([String])
}

/// Report snapshots and recovery journals are separate canonical authorities
/// from the SwiftData clip/reservation rows.  Their adapter must return the
/// complete reference set at the requested workspace revision or throw.
struct TemporalEvidenceExternalReferenceSnapshotV1: Equatable, Sendable {
    let boundRevision: WorkspaceRevisionV1
    let reportLinks: [TemporalEvidenceReportLinkV1]
    let journalContentIDs: Set<String>
    let recoveryContentIDs: Set<String>
    let reportAuthoritySHA256: String
    let journalAuthoritySHA256: String
    let recoveryAuthoritySHA256: String

    func validate(workspaceID: WorkspaceID) throws {
        try reportLinks.forEach { try $0.validate() }
        guard boundRevision.workspaceID == workspaceID,
              reportLinks.allSatisfy({ $0.workspaceID == workspaceID }),
              journalContentIDs.allSatisfy(ContentContractValidationV1.validID),
              recoveryContentIDs.allSatisfy(ContentContractValidationV1.validID),
              KernelCanonicalHashV1.validSHA256(reportAuthoritySHA256),
              KernelCanonicalHashV1.validSHA256(journalAuthoritySHA256),
              KernelCanonicalHashV1.validSHA256(recoveryAuthoritySHA256) else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
    }
}

@MainActor
protocol TemporalEvidenceDeletionExternalReferenceResolvingV1: AnyObject {
    /// Reads all live report-snapshot and journal/recovery content owners at
    /// exactly `boundRevision`; partial or unavailable authorities must throw.
    func temporalEvidenceReferences(
        workspaceID: WorkspaceID,
        boundRevision: WorkspaceRevisionV1
    ) async throws -> TemporalEvidenceExternalReferenceSnapshotV1
}

/// Production adapter over the canonical report snapshots, mutation journal,
/// and promotion-recovery authority. It never accepts a prefiltered reference
/// list from a deletion caller.
@MainActor
final class TemporalEvidenceDeletionExternalReferenceResolverV1:
    TemporalEvidenceDeletionExternalReferenceResolvingV1 {
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let journal: MutationJournalStoreV1
    private let recovery: any TemporalEvidencePromotionRecoveryPortV1

    init(modelContext: ModelContext, generationRootURL: URL,
         journal: MutationJournalStoreV1,
         recovery: any TemporalEvidencePromotionRecoveryPortV1) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.journal = journal
        self.recovery = recovery
    }

    func temporalEvidenceReferences(
        workspaceID: WorkspaceID,
        boundRevision: WorkspaceRevisionV1
    ) async throws -> TemporalEvidenceExternalReferenceSnapshotV1 {
        guard !modelContext.hasChanges,
              generationRootURL.isFileURL,
              generationRootURL.lastPathComponent
                == boundRevision.generationID.uuidString.lowercased(),
              try journal.currentRevision(
                writerInstanceID: boundRevision.writerInstanceID
              ) == boundRevision else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>(
            sortBy: [SortDescriptor(\.id)]
        ))
        guard Set(reports.map(\.id)).count == reports.count else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(
            at: generationRootURL
        )
        var links: [TemporalEvidenceReportLinkV1] = []
        for report in reports {
            let expectedPath = "snapshots/\(report.id.uuidString.lowercased()).json"
            guard report.schemaVersion == 1,
                  report.snapshotRelativePath == expectedPath,
                  KernelCanonicalHashV1.validSHA256(report.snapshotSHA256) else {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            let bytes = try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(expectedPath),
                within: generationRootURL, rootIdentity: rootIdentity
            )
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }.joined()
            let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
            guard digest == report.snapshotSHA256,
                  snapshot.reportID == report.id,
                  snapshot.packetID == report.packetID,
                  snapshot.sourceRecordID == report.sourceRecordID,
                  snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion else {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            let snapshotLinks = snapshot.temporalEvidenceLinks ?? []
            try snapshotLinks.forEach { try $0.validate() }
            guard snapshotLinks.allSatisfy({ $0.workspaceID == workspaceID }) else {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            links.append(contentsOf: snapshotLinks)
        }
        let pending = try await recovery.recoverPending()
        let workspacePending = pending.filter { $0.workspaceID == workspaceID }
        let recoveryIDs = Set(workspacePending.map(\.contentID))
        let liveClips = try modelContext.fetch(
            FetchDescriptor<TemporalEvidenceClipRow>()
        ).map { try $0.value() }.filter { $0.workspaceID == workspaceID }
        let liveDerivativeReferences = Set(liveClips.flatMap(\.derivativeReferences))
        var journalContentIDs = Set<String>()
        var clipHistory: [String: TemporalEvidenceClipV1] = [:]
        var anchorHistory: [String: TimecodedEvidenceAnchorV1] = [:]
        func record(_ clip: TemporalEvidenceClipV1) throws {
            try clip.validateIntrinsic()
            let key = "\(clip.clipID.uuidString.lowercased())|\(clip.revision)|\(clip.clipSHA256)"
            if let existing = clipHistory[key], existing != clip {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            clipHistory[key] = clip
        }
        func record(_ anchor: TimecodedEvidenceAnchorV1) throws {
            try anchor.validateIntrinsic()
            let key = "\(anchor.anchorID.uuidString.lowercased())|\(anchor.revision)|\(anchor.anchorSHA256)"
            if let existing = anchorHistory[key], existing != anchor {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            anchorHistory[key] = anchor
        }
        let receiptRows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        for row in receiptRows {
            guard row.commandKind == WorkspaceCommandKindV1.applyTemporalEvidence.rawValue
            else { continue }
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            guard case let .applyTemporalEvidence(mutation) = envelope.command,
                  envelope.workspaceID == workspaceID,
                  envelope.mutationID.rawValue == row.mutationID,
                  try envelope.canonicalSHA256() == row.envelopeSHA256 else {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            let generic = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
            _ = try TemporalEvidenceMutationReceiptV1(
                mutation: mutation, mutationReceipt: generic
            )
            guard try generic.canonicalSHA256() == row.receiptSHA256 else {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            if case .registerDerivative(_, let derivative, _, _) = mutation.payload,
               liveDerivativeReferences.contains(try derivative.reference) {
                journalContentIDs.insert(derivative.content.contentID)
            }
            switch mutation.payload {
            case .acceptClip(let value, _, let predecessor):
                try record(value); if let predecessor { try record(predecessor) }
            case .appendAnchor(let value, let clip, let predecessor):
                try record(clip); try record(value)
                if let predecessor { try record(predecessor) }
            case .registerDerivative(let successor, _, let predecessor, _),
                 .applyRetention(let successor, _, let predecessor, _):
                try record(successor); try record(predecessor)
            case .removeClip(_, let clips, let anchors, _, _):
                try clips.forEach(record); try anchors.forEach(record)
            }
        }
        for link in links {
            let clipKey = "\(link.clipID.uuidString.lowercased())|\(link.clipRevision)|\(link.clipSHA256)"
            guard let clip = clipHistory[clipKey] else {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            let projectedAnchors = try link.anchorBindings.map { binding in
                let key = "\(binding.anchorID.uuidString.lowercased())|\(binding.revision)|\(binding.anchorSHA256)"
                guard let anchor = anchorHistory[key],
                      try binding.matches(anchor, clip: clip) else {
                    throw WholeSignDeletionServiceError.recoveryRequired
                }
                return anchor
            }
            try link.validate(clip: clip, anchors: projectedAnchors)
        }
        guard recoveryIDs.allSatisfy(ContentContractValidationV1.validID),
              !modelContext.hasChanges,
              try journal.currentRevision(
                writerInstanceID: boundRevision.writerInstanceID
              ) == boundRevision else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let reportDigest = try WorkspaceMutationCanonicalV1.sha256(
            reports.map { "\($0.id.uuidString.lowercased())|\($0.snapshotSHA256)" }
        )
        let recoveryDigest = try WorkspaceMutationCanonicalV1.sha256(
            workspacePending.map {
                "\($0.mutationID.rawValue.uuidString.lowercased())|\($0.contentID)|\($0.state.rawValue)"
            }.sorted()
        )
        let journalDigest = try WorkspaceMutationCanonicalV1.sha256(
            journalContentIDs.sorted()
        )
        return TemporalEvidenceExternalReferenceSnapshotV1(
            boundRevision: boundRevision, reportLinks: links,
            journalContentIDs: journalContentIDs,
            recoveryContentIDs: recoveryIDs,
            reportAuthoritySHA256: reportDigest,
            journalAuthoritySHA256: journalDigest,
            recoveryAuthoritySHA256: recoveryDigest
        )
    }
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
private enum WholeSignDeletionLifecycleRouteV1 {
    case live(dependencies: WorkspacePackageLifecycleDependenciesV1)
    case expiringCompatibility(package: SignPack, posture: String)

    func validate(generationRootURL: URL) throws {
        let root = generationRootURL.standardizedFileURL
        switch self {
        case .live(let dependencies):
            guard dependencies.generationRootURL.standardizedFileURL == root,
                  dependencies.generationRootURL.isFileURL,
                  dependencies.generationID.uuidString.lowercased()
                    == root.lastPathComponent else {
                throw WholeSignDeletionServiceError.invalidGeneration
            }
        case .expiringCompatibility(let package, let posture):
            guard posture == WorkspacePackageLifecycleCompatibilityV1.expiration else {
                throw WholeSignDeletionServiceError.invalidGeneration
            }
            do {
                let profile = try WorkspacePackageLifecycleCompatibilityV1
                    .legacyV3Profile(package: package)
                guard profile.release.matches(profile.package) else {
                    throw WholeSignDeletionServiceError.invalidGeneration
                }
            } catch let error as WholeSignDeletionServiceError {
                throw error
            } catch {
                throw WholeSignDeletionServiceError.invalidGeneration
            }
        }
    }

    func compatibilityProfile() throws -> WorkspacePackageLifecycleProfileV1 {
        switch self {
        case .live:
            throw WholeSignDeletionServiceError.graphInvalid
        case .expiringCompatibility(let package, let posture):
            guard posture == WorkspacePackageLifecycleCompatibilityV1.expiration else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
            do {
                return try WorkspacePackageLifecycleCompatibilityV1
                    .legacyV3Profile(package: package)
            } catch {
                throw WholeSignDeletionServiceError.graphInvalid
            }
        }
    }

    func currentRevision() throws -> WorkspaceRevisionV1 {
        switch self {
        case .live(let dependencies): return try dependencies.writer.currentRevision()
        case .expiringCompatibility: throw WholeSignDeletionServiceError.recoveryRequired
        }
    }
}

@MainActor
final class WholeSignDeletionService {
    typealias AssetLabelPublishedOutputRemovalV1 = @MainActor (
        AssetLabelRenderPublicationBindingV1
    ) async throws -> Void
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
    private let lifecycleRoute: WholeSignDeletionLifecycleRouteV1
    private let searchIndexStore: LocalSearchIndexStoreV1
    private let fileManager: FileManager
    private let assetLabelPublishedOutputRemoval: AssetLabelPublishedOutputRemovalV1

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: WholeSignDeletionFailureInjection? = nil,
        assetLabelPublishedOutputRemoval: AssetLabelPublishedOutputRemovalV1? = nil,
        signPack: SignPack = .illuminatedSignV1
    ) {
        self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            fileManager: fileManager,
            now: now,
            makeUUID: makeUUID,
            failureInjection: failureInjection,
            assetLabelPublishedOutputRemoval: assetLabelPublishedOutputRemoval,
            lifecycleRoute: .expiringCompatibility(
                package: signPack,
                posture: WorkspacePackageLifecycleCompatibilityV1.expiration
            )
        )
    }

    convenience init(
        modelContext: ModelContext,
        lifecycleDependencies dependencies: WorkspacePackageLifecycleDependenciesV1,
        fileManager: FileManager = .default,
        failureInjection: WholeSignDeletionFailureInjection? = nil,
        assetLabelPublishedOutputRemoval: AssetLabelPublishedOutputRemovalV1? = nil
    ) {
        self.init(
            modelContext: modelContext,
            generationRootURL: dependencies.generationRootURL,
            fileManager: fileManager,
            now: dependencies.clock.now,
            makeUUID: dependencies.idSource.makeID,
            failureInjection: failureInjection,
            assetLabelPublishedOutputRemoval: assetLabelPublishedOutputRemoval,
            lifecycleRoute: .live(dependencies: dependencies)
        )
    }

    private init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: WholeSignDeletionFailureInjection? = nil,
        assetLabelPublishedOutputRemoval: AssetLabelPublishedOutputRemovalV1?,
        lifecycleRoute: WholeSignDeletionLifecycleRouteV1
    ) {
        self.modelContext = modelContext
        ledgerStore = DeletionLedgerStore(context: modelContext)
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.now = now
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection
        self.lifecycleRoute = lifecycleRoute
        self.fileManager = fileManager

        let root = generationRootURL.standardizedFileURL
        let canonicalContentStore = EvidenceBundleStore(
            generationRootURL: root,
            fileManager: fileManager
        )
        self.assetLabelPublishedOutputRemoval = assetLabelPublishedOutputRemoval
            ?? { binding in
                try canonicalContentStore.removeAssetLabelPublishedOutput(binding)
            }
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        let applicationSupport = dataRoot.deletingLastPathComponent()
        do {
            searchIndexStore = try LocalSearchIndexStoreV1(
                applicationSupportURL: applicationSupport,
                fileManager: fileManager
            )
        } catch {
            preconditionFailure("Search-index lifecycle could not be bound: \(error)")
        }
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
        try IntegrationProjectionOrdinaryDeletionPolicyV1.validate()
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        guard try journal.isEmpty() else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let frozenMutationHistory = try mutationHistorySnapshot()

        let rows = try fetchRows()
        try validateLocationDeletionNoCascade(
            rows: rows,
            deletingAssetID: assetID,
            deletingSiteID: nil
        )
        _ = try lifecycleProfile(for: assetID, rows: rows)
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
        let acceptedLabelSnapshots = try acceptedLabelSnapshots(
            referencing: assetID, rows: rows
        )
        let augmentedIntent = try addingAcceptedLabelSnapshotLedgerEntries(
            to: rulePlan.intent,
            snapshots: acceptedLabelSnapshots
        )
        let canonicalIntent: DeletionIntentV1
        do {
            canonicalIntent = try DeletionIntentDecoderV1().decode(
                DeletionIntentEncoderV1().encode(augmentedIntent).data
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
        if case .live = lifecycleRoute {
            try validateKernelDeletionMappings()
            try validateDeleteCommand(for: plan)
        }
        try requireLedgerEntriesUnseen(plan.intent)
        try validateOwnedFiles(
            plan: plan,
            rows: rows
        )
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
            try await cleanup(plan.intent.withPhase(.databaseCommitted))
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
        try await purgeSearchProjectionAfterDeletion()
        try await purgeIntegrationProjectionAfterDeletion()
        do {
            try inject(.journalRemoval)
            try journal.remove(plan.intent.withPhase(.databaseCommitted))
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
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
        guard try journal.isEmpty() else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let rows = try fetchRows()
        guard let site = rows.sites.first(where: { $0.id == siteID }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        try validateLocationDeletionNoCascade(
            rows: rows,
            deletingAssetID: nil,
            deletingSiteID: siteID
        )
        _ = try packageProfiles(
            for: rows.assets.filter { $0.siteID == siteID }.map(\.id),
            rows: rows,
            additional: [try WorkspaceEntityIdentityV1(kind: .site, id: siteID)]
        )
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
        try IntegrationProjectionOrdinaryDeletionPolicyV1.validate()
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        guard try journal.isEmpty(),
              preview.generationID == generationID,
              preview.schemaVersion == 1 else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let frozenMutationHistory = try mutationHistorySnapshot()
        let rows = try fetchRows()
        guard let site = rows.sites.first(where: { $0.id == preview.siteID }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        try validateLocationDeletionNoCascade(
            rows: rows,
            deletingAssetID: nil,
            deletingSiteID: preview.siteID
        )
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
        _ = try packageProfiles(
            for: preview.assetPlans.map(\.assetID),
            rows: rows,
            additional: [try WorkspaceEntityIdentityV1(kind: .site, id: preview.siteID)]
        )
        if case .live = lifecycleRoute {
            try validateKernelDeletionMappings()
            try validateDeleteSiteCommand(for: preview)
        }
        for plan in preview.assetPlans {
            try validateOwnedFiles(
                plan: plan,
                rows: rows
            )
        }
        try requireLedgerIdentitiesUnseen(preview.ledgerEntries.map(\.identity))
        let siteSearchPurgeMarker = SiteSearchPurgeMarkerV1(
            siteID: preview.siteID,
            deletionID: preview.deletionID,
            generationID: generationID
        )
        try journal.createSiteSearchPurgeMarker(siteSearchPurgeMarker)
        try inject(.preparedJournal)
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
            do {
                try journal.removeSiteSearchPurgeMarker(siteSearchPurgeMarker)
            } catch {
                throw WholeSignDeletionServiceError.recoveryRequired
            }
            if error is WholeSignDeletionServiceError { throw error }
            throw WholeSignDeletionServiceError.saveFailed
        }
        do {
            try inject(.committedPhase)
            try journal.replaceSiteSearchPurgeMarker(
                siteSearchPurgeMarker.withPhase(.databaseCommitted)
            )
            try inject(.fileCleanup)
            for plan in preview.assetPlans {
                try await cleanup(plan.intent.withPhase(.databaseCommitted))
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
        try await purgeSearchProjectionAfterDeletion()
        try await purgeIntegrationProjectionAfterDeletion()
        do {
            try inject(.journalRemoval)
            try journal.removeSiteSearchPurgeMarker(
                siteSearchPurgeMarker.withPhase(.databaseCommitted)
            )
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
        }
        return ExplicitSiteDeletionOutcomeV1(
            siteID: preview.siteID,
            deletionID: preview.deletionID
        )
    }

    private func purgeSearchProjectionAfterDeletion() async throws {
        let workspaceID: UUID?
        switch lifecycleRoute {
        case .live(let dependencies):
            workspaceID = dependencies.workspaceID.rawValue
        case .expiringCompatibility:
            let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
            guard states.count <= 1 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            workspaceID = states.first?.workspaceID
        }
        guard let workspaceID else { return }
        do {
            try await searchIndexStore.purgeWorkspace(workspaceID)
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
        }
    }

    private func purgeIntegrationProjectionAfterDeletion() async throws {
        let workspaceID: WorkspaceID?
        switch lifecycleRoute {
        case .live(let dependencies):
            workspaceID = dependencies.workspaceID
        case .expiringCompatibility:
            let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
            guard states.count <= 1 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            workspaceID = states.first.map { WorkspaceID(rawValue: $0.workspaceID) }
        }
        guard let workspaceID else { return }
        do {
            let store = try IntegrationProjectionCheckpointStoreV1(
                generationRootURL: generationRootURL,
                generationID: generationID,
                workspaceID: workspaceID,
                fileManager: fileManager
            )
            try await IntegrationProjectionOrdinaryDeletionPolicyV1.purge(
                store: store,
                workspaceID: workspaceID
            )
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
        }
    }

    func reconcile() async throws -> WholeSignDeletionRecoverySummary {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        let frozenMutationHistory = try mutationHistorySnapshot()
        let intents = try journal.loadAll()
        let siteSearchPurgeMarkers = try journal.loadAllSiteSearchPurgeMarkers()
        let intentPaths = intents.flatMap(\.relativePaths)
        let intentPacketIDs = intents.flatMap {
            $0.countedPacketTombstones.map(\.id)
        }
        let intentLedgerIdentities = intents.flatMap {
            $0.ledgerEntries.map(\.identity)
        }
        guard Set(intents.map(\.assetID)).count == intents.count,
              Set(siteSearchPurgeMarkers.map(\.siteID)).count
                == siteSearchPurgeMarkers.count,
              Set(siteSearchPurgeMarkers.map(\.deletionID)).count
                == siteSearchPurgeMarkers.count,
              Set(intents.map(\.deletionID)).isDisjoint(
                with: Set(siteSearchPurgeMarkers.map(\.deletionID))
              ),
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
            if case .live = lifecycleRoute {
                try validateKernelDeletionMappings()
            }
            let rows = try fetchRows()
            if rows.assets.contains(where: { $0.id == intent.assetID }) {
                _ = try lifecycleProfile(for: intent.assetID, rows: rows)
                if intent.schemaVersion == 1 {
                    guard intent.phase == .prepared,
                          try legacyPreparedIntentMatches(
                              intent,
                              rows: rows
                          ) else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                    try journal.remove(intent)
                    cancelled += 1
                    continue
                }
                guard intent.phase == .prepared,
                      let plan = try preparedPlan(
                          intent,
                          rows: rows
                      ) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                if case .live = lifecycleRoute {
                    try validateDeleteCommand(for: plan)
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
                try await cleanup(intent.withPhase(.databaseCommitted))
                try await purgeSearchProjectionAfterDeletion()
                try await purgeIntegrationProjectionAfterDeletion()
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
            try await cleanup(intent.withPhase(.databaseCommitted))
            try await purgeSearchProjectionAfterDeletion()
            try await purgeIntegrationProjectionAfterDeletion()
            try journal.remove(intent.withPhase(.databaseCommitted))
            completed += 1
        }
        for marker in siteSearchPurgeMarkers {
            guard marker.generationID == generationID else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            let rows = try fetchRows()
            if rows.sites.contains(where: { $0.id == marker.siteID }) {
                guard marker.phase == .prepared else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                try journal.removeSiteSearchPurgeMarker(marker)
                cancelled += 1
                continue
            }
            if marker.phase == .prepared {
                try journal.replaceSiteSearchPurgeMarker(
                    marker.withPhase(.databaseCommitted)
                )
            }
            try await purgeSearchProjectionAfterDeletion()
            try await purgeIntegrationProjectionAfterDeletion()
            try journal.removeSiteSearchPurgeMarker(
                marker.withPhase(.databaseCommitted)
            )
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
        try lifecycleRoute.validate(generationRootURL: generationRootURL)
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

    private func cleanup(_ intent: DeletionIntentV1) async throws {
        if !intent.acceptedLabelOutputCleanups.isEmpty {
            let snapshotIdentities = try Set(intent.acceptedLabelOutputCleanups.map {
                try DeletionIdentityV2(
                    kind: .acceptedLabelGenerationSnapshot,
                    id: $0.snapshotID
                )
            })
            let liveSnapshotIDs = Set(try modelContext.fetch(
                FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()
            ).map(\.snapshotID))
            guard intent.phase == .databaseCommitted,
                  snapshotIdentities.allSatisfy({ !liveSnapshotIDs.contains($0.id) }) else {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
            do {
                try ledgerStore.requireContains(snapshotIdentities)
            } catch {
                throw WholeSignDeletionServiceError.cleanupFailed
            }
            var removedJobs = Set<UUID>()
            for cleanup in intent.acceptedLabelOutputCleanups {
                let binding = try cleanup.value(containingAssetID: intent.assetID)
                guard try cleanup.requiresPublishedOutputRemoval(
                    containingAssetID: intent.assetID
                ) else { continue }
                guard removedJobs.insert(cleanup.jobID).inserted else { continue }
                do {
                    try inject(.fileCleanup)
                    try await assetLabelPublishedOutputRemoval(binding)
                } catch {
                    throw WholeSignDeletionServiceError.cleanupFailed
                }
            }
        }
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
        do {
            try AssetLabelDerivedScratchCleanupV1(
                generationRootURL: generationRootURL,
                fileManager: fileManager
            ).removeAttempts(referencing: intent.assetID)
        } catch {
            throw WholeSignDeletionServiceError.cleanupFailed
        }
    }
}


@MainActor
extension WholeSignDeletionService {
    func makeTemporalEvidenceDeletionExternalReferenceResolver(
        journal: MutationJournalStoreV1,
        recovery: any TemporalEvidencePromotionRecoveryPortV1
    ) -> TemporalEvidenceDeletionExternalReferenceResolverV1 {
        TemporalEvidenceDeletionExternalReferenceResolverV1(
            modelContext: modelContext, generationRootURL: generationRootURL,
            journal: journal, recovery: recovery
        )
    }

    func makeTemporalEvidenceRetentionContentCleanup(
        externalReferences: any TemporalEvidenceDeletionExternalReferenceResolvingV1,
        cleanup: OrphanFileCleanupService
    ) -> TemporalEvidenceRetentionContentCleanupAdapterV1 {
        let resolver = TemporalEvidenceCanonicalRetentionCleanupResolverV1(
            deletion: self, externalReferences: externalReferences,
            cleanup: cleanup
        )
        return TemporalEvidenceRetentionContentCleanupAdapterV1(
            resolver: resolver
        )
    }

    /// Post-commit byte cleanup for a governed C33 delete. The canonical writer
    /// must already have removed the clip and its anchors; this service cannot
    /// use a missing file to authorize row deletion.
    func cleanupTemporalContentAfterCanonicalDelete(
        clip: TemporalEvidenceClipV1,
        externalReferences: any TemporalEvidenceDeletionExternalReferenceResolvingV1,
        cleanup: OrphanFileCleanupService
    ) async throws -> OrphanFileCleanupSummary {
        try clip.validateIntrinsic()
        let clipID = clip.clipID
        guard try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
            predicate: #Predicate { $0.clipID == clipID }
        )).isEmpty,
        try modelContext.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>(
            predicate: #Predicate { $0.clipID == clipID }
        )).isEmpty else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let closure = try await temporalEvidenceReferenceClosure(
            workspaceID: clip.workspaceID, externalReferences: externalReferences
        )
        return try cleanup.removeCanonicalContentIfUnreferenced(
            reference: clip.original, locator: clip.locator,
            authoritySnapshot: closure
        )
    }

    func cleanupTemporalDerivativeAfterCanonicalDelete(
        derivative: TemporalEvidenceDerivativeV1,
        deletedClip: TemporalEvidenceClipV1,
        externalReferences: any TemporalEvidenceDeletionExternalReferenceResolvingV1,
        cleanup: OrphanFileCleanupService
    ) async throws -> OrphanFileCleanupSummary {
        try derivative.validate(clip: deletedClip)
        let clipID = deletedClip.clipID
        guard try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>(
            predicate: #Predicate { $0.clipID == clipID }
        )).isEmpty else { throw WholeSignDeletionServiceError.recoveryRequired }
        let closure = try await temporalEvidenceReferenceClosure(
            workspaceID: derivative.workspaceID,
            externalReferences: externalReferences
        )
        return try cleanup.removeCanonicalContentIfUnreferenced(
            reference: derivative.content, locator: derivative.locator,
            authoritySnapshot: closure
        )
    }

    private func temporalEvidenceReferenceClosure(
        workspaceID: WorkspaceID,
        externalReferences: any TemporalEvidenceDeletionExternalReferenceResolvingV1
    ) async throws -> TemporalEvidenceLiveReferenceClosureV1 {
        let revisionBefore = try lifecycleRoute.currentRevision()
        guard revisionBefore.workspaceID == workspaceID,
              revisionBefore.generationID == generationID else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let external = try await externalReferences.temporalEvidenceReferences(
            workspaceID: workspaceID,
            boundRevision: revisionBefore
        )
        try external.validate(workspaceID: workspaceID)
        guard external.boundRevision == revisionBefore else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let liveClips = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>())
            .map { try $0.value() }
        let liveReservations = try modelContext.fetch(
            FetchDescriptor<DraftContentReservationRow>()
        ).map { try $0.value() }.filter {
            $0.workspaceID == workspaceID && $0.reconciliationState != .deleted
        }
        guard !modelContext.hasChanges,
              try lifecycleRoute.currentRevision() == revisionBefore else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }
        let liveClipContentIDs = Set(liveClips.map(\.original.contentID))
        let reportContentIDs = Set(external.reportLinks.map(\.contentID))
        let reservedContentIDs = Set(liveReservations.map(\.locator.contentID))
        return TemporalEvidenceLiveReferenceClosureV1(
            boundRevision: revisionBefore,
            liveClipContentIDs: liveClipContentIDs,
            liveJournalContentIDs: external.journalContentIDs,
            liveReportContentIDs: reportContentIDs,
            reservedContentIDs: reservedContentIDs,
            recoveryContentIDs: external.recoveryContentIDs
        )
    }
}

/// Resolver injected into the core retention adapter. The canonical tombstone
/// receipt is validated before any byte work, and replay is idempotent because
/// the anchored cleanup treats an already-absent exact content object as done.
@MainActor
final class TemporalEvidenceCanonicalRetentionCleanupResolverV1:
    TemporalEvidenceRetentionContentCleanupResolvingV1 {
    private let deletion: WholeSignDeletionService
    private let externalReferences:
        any TemporalEvidenceDeletionExternalReferenceResolvingV1
    private let cleanup: OrphanFileCleanupService

    init(deletion: WholeSignDeletionService,
         externalReferences: any TemporalEvidenceDeletionExternalReferenceResolvingV1,
         cleanup: OrphanFileCleanupService) {
        self.deletion = deletion
        self.externalReferences = externalReferences
        self.cleanup = cleanup
    }

    func removeCommittedContent(
        for mutation: TemporalEvidenceMutationV1,
        receipt: TemporalEvidenceMutationReceiptV1
    ) async throws {
        try mutation.validate()
        try receipt.validate(mutation: mutation)
        guard case let .removeClip(event, clips, anchors, derivatives, _) =
                mutation.payload,
              event.disposition == .deleteClip
                || event.disposition == .eraseWorkspace,
              receipt.mutationReceipt.resultingRevision.workspaceID
                == mutation.workspaceID else {
            throw TemporalEvidenceContractFailureV1.invalidTransition
        }
        let clipByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.clipID, $0) })
        guard anchors.allSatisfy({ clipByID[$0.clipID] != nil }),
              derivatives.allSatisfy({ clipByID[$0.clipID] != nil }) else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        for clip in clips.sorted(by: { $0.clipID.uuidString < $1.clipID.uuidString }) {
            _ = try await deletion.cleanupTemporalContentAfterCanonicalDelete(
                clip: clip, externalReferences: externalReferences,
                cleanup: cleanup
            )
        }
        for derivative in derivatives.sorted(by: {
            $0.derivativeID.uuidString < $1.derivativeID.uuidString
        }) {
            guard let clip = clipByID[derivative.clipID] else {
                throw TemporalEvidenceContractFailureV1.invalidValue
            }
            _ = try await deletion.cleanupTemporalDerivativeAfterCanonicalDelete(
                derivative: derivative, deletedClip: clip,
                externalReferences: externalReferences, cleanup: cleanup
            )
        }
    }
}

private extension WholeSignDeletionService {
    func lifecycleProfile(
        for assetID: UUID,
        rows: Rows
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        switch lifecycleRoute {
        case .live:
            guard let profile = try packageProfiles(
                for: [assetID],
                rows: rows,
                additional: []
            )[assetID] else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
            return profile
        case .expiringCompatibility:
            return try lifecycleRoute.compatibilityProfile()
        }
    }

    func packageProfiles(
        for assetIDs: [UUID],
        rows: Rows,
        additional: [WorkspaceEntityIdentityV1]
    ) throws -> [UUID: WorkspacePackageLifecycleProfileV1] {
        guard case let .live(dependencies) = lifecycleRoute else { return [:] }
        guard Set(assetIDs).count == assetIDs.count,
              assetIDs.allSatisfy({ assetID in
                  rows.assets.contains(where: { asset in asset.id == assetID })
              }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        let sortedAssetIDs = assetIDs.sorted { $0.uuidString < $1.uuidString }
        let assetIdentities = try sortedAssetIDs.map {
            try WorkspaceEntityIdentityV1(kind: .asset, id: $0)
        }
        let result = try packageLifecycleQuery(
            operation: .delete,
            identities: assetIdentities + additional,
            requireAllExisting: true
        )
        let bindings = Dictionary(
            uniqueKeysWithValues: result.packageBindings.map { ($0.assetID, $0) }
        )
        guard Set(bindings.keys) == Set(sortedAssetIDs) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }

        var profiles: [UUID: WorkspacePackageLifecycleProfileV1] = [:]
        for assetID in sortedAssetIDs {
            guard let asset = rows.assets.first(where: { $0.id == assetID }),
                  let binding = bindings[assetID],
                  binding.packageID == asset.packID,
                  binding.packageSchemaVersion == asset.packSchemaVersion,
                  binding.packageContentVersion == asset.packContentVersion else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
            do {
                let release = try PackageReleaseIdentityV1(
                    packageID: binding.packageID,
                    schemaVersion: binding.packageSchemaVersion,
                    contentVersion: binding.packageContentVersion
                )
                profiles[assetID] = try dependencies.profileRegistry.resolve(release)
            } catch {
                // Unknown package releases are not implicitly assigned to the
                // shipping pack. They fail closed at the package boundary.
                throw WholeSignDeletionServiceError.graphInvalid
            }
        }
        return profiles
    }

    func packageLifecycleQuery(
        operation: WorkspacePackageLifecycleOperationV1,
        identities: [WorkspaceEntityIdentityV1],
        requireAllExisting: Bool
    ) throws -> WorkspacePackageLifecycleQueryResultV1 {
        guard case let .live(dependencies) = lifecycleRoute else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        guard dependencies.generationID == generationID,
              dependencies.generationRootURL.standardizedFileURL == generationRootURL,
              dependencies.generationRootURL.isFileURL else {
            throw WholeSignDeletionServiceError.invalidGeneration
        }
        do {
            let request = try WorkspacePackageLifecycleQueryRequestV1(
                workspaceID: dependencies.workspaceID,
                generationID: dependencies.generationID,
                operation: operation,
                identities: identities
            )
            let result = try dependencies.queryClient.query(request)
            let expected = Set(request.identities)
            guard result.workspaceID == dependencies.workspaceID,
                  result.generationID == generationID,
                  result.operation == operation,
                  result.revision.workspaceID == dependencies.workspaceID,
                  result.revision.generationID == generationID,
                  Set(result.existingIdentities).isSubset(of: expected),
                  !requireAllExisting
                    || Set(result.existingIdentities) == expected,
                  try dependencies.queryClient.currentRevision() == result.revision else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
            return result
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func validateDeleteCommand(for plan: WholeSignDeletionPlan) throws {
        guard case let .live(dependencies) = lifecycleRoute else { return }
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: plan.assetID)
        let scope = try packageLifecycleQuery(
            operation: .delete,
            identities: [identity],
            requireAllExisting: true
        )
        let command = WorkspaceCommandV1.deleteAsset(
            DeleteAssetMutationV1(
                deletionID: plan.intent.deletionID,
                assetID: plan.assetID,
                planDigest: try deletionPlanDigest(plan.intent)
            )
        )
        let request = WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: plan.intent.deletionID),
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scope.revision),
            command: command
        )
        guard request.command.kind == .deleteAsset,
              case let .deleteAsset(value) = request.command,
              value.assetID == plan.assetID,
              value.deletionID == plan.intent.deletionID,
              Self.isSHA256(value.planDigest),
              scope.existingIdentities == [identity] else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        // The adapter remains the owner of command application. This request
        // is the immutable command/query identity checked before the legacy
        // deletion journal performs its effect.
        _ = dependencies.writer
    }

    func validateDeleteSiteCommand(
        for preview: ExplicitSiteDeletionPreviewV1
    ) throws {
        guard case let .live(dependencies) = lifecycleRoute else { return }
        let identities = try [
            WorkspaceEntityIdentityV1(kind: .site, id: preview.siteID),
        ] + preview.assetPlans.map {
            try WorkspaceEntityIdentityV1(kind: .asset, id: $0.assetID)
        }
        let scope = try packageLifecycleQuery(
            operation: .delete,
            identities: identities,
            requireAllExisting: true
        )
        let command = WorkspaceCommandV1.deleteSite(
            DeleteSiteMutationV1(
                deletionID: preview.deletionID,
                siteID: preview.siteID,
                planDigest: try deletionSitePlanDigest(preview)
            )
        )
        let request = WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: preview.deletionID),
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scope.revision),
            command: command
        )
        guard request.command.kind == .deleteSite,
              case let .deleteSite(value) = request.command,
              value.siteID == preview.siteID,
              value.deletionID == preview.deletionID,
              Self.isSHA256(value.planDigest) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        _ = dependencies.writer
    }

    func deletionPlanDigest(_ intent: DeletionIntentV1) throws -> String {
        sha256(try DeletionIntentEncoderV1().encode(intent).data)
    }

    func deletionSitePlanDigest(
        _ preview: ExplicitSiteDeletionPreviewV1
    ) throws -> String {
        var components = [
            preview.siteID.uuidString.lowercased(),
            preview.generationID.uuidString.lowercased(),
            preview.deletionID.uuidString.lowercased(),
        ]
        for plan in preview.assetPlans.sorted(by: { $0.assetID.uuidString < $1.assetID.uuidString }) {
            components.append(
                try DeletionIntentEncoderV1().encode(plan.intent).data.base64EncodedString()
            )
        }
        components.append(contentsOf: preview.ledgerEntries.map { $0.identity.typedID }.sorted())
        return sha256(Data(components.map { "\($0.count):\($0)" }.joined().utf8))
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains(Int($0.value)) || (97...102).contains(Int($0.value))
        }
    }

    func validateKernelDeletionMappings() throws {
        do { try AuthorityCriterionDeletionLedgerPolicyV1.validate() }
        catch { throw WholeSignDeletionServiceError.graphInvalid }
        do {
            for kind in DeletionRecordKindV2.allCases {
                guard let kernelKind = kernelKind(for: kind) else {
                    guard kind == .acceptedLabelGenerationSnapshot else {
                        throw WholeSignDeletionServiceError.graphInvalid
                    }
                    try C45AcceptedLabelKernelDeletionEnrollmentV1.validate()
                    continue
                }
                let registration = try KernelDeletionEraseRegistryV4.registration(for: kernelKind)
                guard !registration.clearsTombstonesOnDelete else {
                    throw WholeSignDeletionServiceError.graphInvalid
                }
                if kind == .packet {
                    guard registration.deletion == .tombstonePreservingHistory,
                          registration.clearsTombstonesOnErase else {
                        throw WholeSignDeletionServiceError.graphInvalid
                    }
                }
            }
            let ledger = try KernelDeletionEraseRegistryV4.registration(
                for: .deletionLedgerRow
            )
            guard ledger.deletion == .preserveUntilErase,
                  !ledger.clearsTombstonesOnDelete,
                  ledger.clearsTombstonesOnErase else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func kernelKind(for kind: DeletionRecordKindV2) -> KernelPersistenceV4RecordKind? {
        switch kind {
        case .site: .site
        case .asset: .asset
        case .workflowRecord: .workflowRecord
        case .evidenceFile: .evidenceFile
        case .issue: .issue
        case .packet: .packet
        case .report: .report
        case .acceptedLabelGenerationSnapshot: nil
        }
    }

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
        let locationNodes: [LocationNodeRow]
        let placementEvents: [AssetPlacementEventRow]
        let compositionEdges: [AssetCompositionEdgeRow]
        let records: [WorkflowRecord]
        let requirementAssurance: [RequirementAssuranceRow]
        let serviceParties: [ServicePartyRow]
        let sitePartyRoles: [SitePartyRoleEventRow]
        let actorSnapshots: [ActorSnapshotRow]
        let qualificationSnapshots: [QualificationSnapshotRow]
        let signoffSnapshots: [SignoffSnapshotRow]
        let assetKindBindingEvents: [AssetKindBindingEventRow]
        let assetWorkflowCapabilityBindingEvents: [AssetWorkflowCapabilityBindingEventRow]
        let assetProductIdentities: [AssetProductIdentityRow]
        let assetLifecycleEvents: [AssetLifecycleEventRow]
        let assetSuccessorLinks: [AssetSuccessorLinkRow]
        let workSubjectScopeSnapshots: [WorkSubjectScopeSnapshotRow]
        let functionalRelationshipDescriptors: [FunctionalRelationshipTypeDescriptorRow]
        let functionalRelationshipEvents: [AssetFunctionalRelationshipEventRow]
        let evidenceVisibilities: [EvidenceVisibilityRow]
        let claimEvidenceLinks: [ClaimEvidenceLinkRow]
        let assuranceManifests: [AssuranceManifestRow]
        let attestations: [AttestationRow]
        let inspectionReviewTransitions: [InspectionReviewTransitionRow]
        let reviewDispositions: [ReviewDispositionRow]
        let changeRequests: [ChangeRequestRow]
        let correctiveActionPolicies: [CorrectiveActionPolicyRow]
        let correctiveActionEvents: [CorrectiveActionEventRow]
        let workPacketManifests:[WorkPacketManifestRow];let workItemClaims:[WorkItemClaimRow];let workLeases:[WorkLeaseRow];let workReleases:[WorkReleaseRow];let workHandoffs:[WorkHandoffRow]
        let fieldDraftCheckpoints:[FieldDraftCheckpointRow];let attachmentStagingItems:[AttachmentStagingItemRow]
        let draftCommitSagas:[DraftCommitSagaRow];let draftContentReservations:[DraftContentReservationRow]
        let draftCommitReceipts:[DraftCommitReceiptRow];let draftDiscardReceipts:[DraftDiscardReceiptRow]
        let promotedPackageReleases:[PromotedPackageReleaseRow];let packageSandboxRuns:[PackageSandboxRunRow]
        let packagePromotionReceipts:[PackagePromotionReceiptRow];let activePackageRegistryPointers:[ActivePackageRegistryPointerRow]
        let instrumentReferences:[InstrumentReferenceRow];let calibrationStatusSnapshots:[CalibrationStatusSnapshotRow]
        let measurementCaptures:[MeasurementCaptureRow];let measurementSeries:[MeasurementSeriesRow]
        let measurementQualityAssessments:[MeasurementQualityAssessmentRow]
        let privacyTransformPolicies:[PrivacyTransformPolicyRow];let privacyRegions:[PrivacyRegionRow]
        let privacyTransformManifests:[PrivacyTransformManifestRow];let privacyReviewReceipts:[PrivacyReviewReceiptRow]
        let clientCapabilityProfiles:[ClientCapabilityProfileRow];let packageLifecyclePolicies:[PackageLifecyclePolicyRow];let packageLifecycleDispositions:[PackageLifecycleDispositionRow];let clientCapabilityAdmissionDecisions:[ClientCapabilityAdmissionDecisionRow]
        let fieldReferenceReleases:[FieldReferenceReleaseRow];let fieldReferenceBindings:[FieldReferenceBindingRow]
        let accessibleDocumentAssessmentReceipts:[AccessibleDocumentAssessmentReceiptRow]
        let surveyDefinitionIdentities:[SurveyDefinitionIdentityRow];let surveyDefinitionReleases:[SurveyDefinitionReleaseRow]
        let surveySessions:[SurveySessionRow];let factCaptures:[FactCaptureRow];let provisionalSubjects:[ProvisionalSubjectRow];let subjectPromotionReceipts:[SubjectPromotionReceiptRow];let surveyPublicationSnapshots:[SurveyPublicationSnapshotRow]
        let scheduleDefinitionReleases: [ScheduleDefinitionReleaseRow]
        let occurrenceHistoryEvents: [OccurrenceHistoryEventRow]
        let assetLocators: [AssetLocatorRow]
        let locatorBindingReceipts: [LocatorBindingReceiptRow]
        let planDocuments: [PlanDocumentRow]
        let planRevisions: [PlanRevisionRow]
        let planPlacements: [PlanPlacementRow]
        let rebaseReceipts: [RebaseReceiptRow]
        let poseEvents: [AssetPoseEventRow]
        let spatialAnchorObservations: [SpatialAnchorObservationRow]
        let observationAndTime: [UUID: ObservationAndTimeRow]
        let recordPayloads: [WorkflowRecordPayloadV1]
        let evidence: [EvidenceFile]
        let issues: [Issue]
        let packets: [Packet]
        let reports: [Report]
        let acceptedLabelSnapshots: [AcceptedLabelGenerationSnapshotRow]
    }

    func fetchRows() throws -> Rows {
        do {
            let records = try boundedFetch(WorkflowRecord.self)
            let observationAndTime = try validatedObservationAndTimeIndex(
                records: records
            )
            let recordPayloads = try records.map { record in
                guard let companion = observationAndTime[record.id] else {
                    throw WholeSignDeletionServiceError.graphInvalid
                }
                return payload(record, companion: companion)
            }
            return Rows(
                sites: try boundedFetch(Site.self),
                assets: try boundedFetch(Asset.self),
                locationNodes: try boundedFetch(LocationNodeRow.self),
                placementEvents: try boundedFetch(AssetPlacementEventRow.self),
                compositionEdges: try boundedFetch(AssetCompositionEdgeRow.self),
                records: records,
                requirementAssurance: try boundedFetch(RequirementAssuranceRow.self),
                serviceParties: try boundedFetch(ServicePartyRow.self),
                sitePartyRoles: try boundedFetch(SitePartyRoleEventRow.self),
                actorSnapshots: try boundedFetch(ActorSnapshotRow.self),
                qualificationSnapshots: try boundedFetch(QualificationSnapshotRow.self),
                signoffSnapshots: try boundedFetch(SignoffSnapshotRow.self),
                assetKindBindingEvents: try boundedFetch(AssetKindBindingEventRow.self),
                assetWorkflowCapabilityBindingEvents: try boundedFetch(AssetWorkflowCapabilityBindingEventRow.self),
                assetProductIdentities: try boundedFetch(AssetProductIdentityRow.self),
                assetLifecycleEvents: try boundedFetch(AssetLifecycleEventRow.self),
                assetSuccessorLinks: try boundedFetch(AssetSuccessorLinkRow.self),
                workSubjectScopeSnapshots: try boundedFetch(WorkSubjectScopeSnapshotRow.self),
                functionalRelationshipDescriptors: try boundedFetch(FunctionalRelationshipTypeDescriptorRow.self),
                functionalRelationshipEvents: try boundedFetch(AssetFunctionalRelationshipEventRow.self),
                evidenceVisibilities: try boundedFetch(EvidenceVisibilityRow.self),
                claimEvidenceLinks: try boundedFetch(ClaimEvidenceLinkRow.self),
                assuranceManifests: try boundedFetch(AssuranceManifestRow.self),
                attestations: try boundedFetch(AttestationRow.self),
                inspectionReviewTransitions: try boundedFetch(InspectionReviewTransitionRow.self),
                reviewDispositions: try boundedFetch(ReviewDispositionRow.self),
                changeRequests: try boundedFetch(ChangeRequestRow.self),
                correctiveActionPolicies: try boundedFetch(CorrectiveActionPolicyRow.self),
                correctiveActionEvents: try boundedFetch(CorrectiveActionEventRow.self),
                workPacketManifests:try boundedFetch(WorkPacketManifestRow.self),workItemClaims:try boundedFetch(WorkItemClaimRow.self),workLeases:try boundedFetch(WorkLeaseRow.self),workReleases:try boundedFetch(WorkReleaseRow.self),workHandoffs:try boundedFetch(WorkHandoffRow.self),
                fieldDraftCheckpoints:try boundedFetch(FieldDraftCheckpointRow.self),attachmentStagingItems:try boundedFetch(AttachmentStagingItemRow.self),draftCommitSagas:try boundedFetch(DraftCommitSagaRow.self),draftContentReservations:try boundedFetch(DraftContentReservationRow.self),draftCommitReceipts:try boundedFetch(DraftCommitReceiptRow.self),draftDiscardReceipts:try boundedFetch(DraftDiscardReceiptRow.self),
                promotedPackageReleases:try boundedFetch(PromotedPackageReleaseRow.self),packageSandboxRuns:try boundedFetch(PackageSandboxRunRow.self),packagePromotionReceipts:try boundedFetch(PackagePromotionReceiptRow.self),activePackageRegistryPointers:try boundedFetch(ActivePackageRegistryPointerRow.self),
                instrumentReferences:try boundedFetch(InstrumentReferenceRow.self),calibrationStatusSnapshots:try boundedFetch(CalibrationStatusSnapshotRow.self),measurementCaptures:try boundedFetch(MeasurementCaptureRow.self),measurementSeries:try boundedFetch(MeasurementSeriesRow.self),measurementQualityAssessments:try boundedFetch(MeasurementQualityAssessmentRow.self),
                privacyTransformPolicies:try boundedFetch(PrivacyTransformPolicyRow.self),privacyRegions:try boundedFetch(PrivacyRegionRow.self),privacyTransformManifests:try boundedFetch(PrivacyTransformManifestRow.self),privacyReviewReceipts:try boundedFetch(PrivacyReviewReceiptRow.self),
                clientCapabilityProfiles:try boundedFetch(ClientCapabilityProfileRow.self),packageLifecyclePolicies:try boundedFetch(PackageLifecyclePolicyRow.self),packageLifecycleDispositions:try boundedFetch(PackageLifecycleDispositionRow.self),clientCapabilityAdmissionDecisions:try boundedFetch(ClientCapabilityAdmissionDecisionRow.self),
                fieldReferenceReleases:try boundedFetch(FieldReferenceReleaseRow.self),fieldReferenceBindings:try boundedFetch(FieldReferenceBindingRow.self),
                accessibleDocumentAssessmentReceipts:try boundedFetch(AccessibleDocumentAssessmentReceiptRow.self),
                surveyDefinitionIdentities:try boundedFetch(SurveyDefinitionIdentityRow.self),surveyDefinitionReleases:try boundedFetch(SurveyDefinitionReleaseRow.self),
                 surveySessions:try boundedFetch(SurveySessionRow.self),factCaptures:try boundedFetch(FactCaptureRow.self),provisionalSubjects:try boundedFetch(ProvisionalSubjectRow.self),subjectPromotionReceipts:try boundedFetch(SubjectPromotionReceiptRow.self),surveyPublicationSnapshots:try boundedFetch(SurveyPublicationSnapshotRow.self),
                 scheduleDefinitionReleases: try boundedFetch(ScheduleDefinitionReleaseRow.self),
                 occurrenceHistoryEvents: try boundedFetch(OccurrenceHistoryEventRow.self),
                 assetLocators: try boundedFetch(AssetLocatorRow.self),
                 locatorBindingReceipts: try boundedFetch(LocatorBindingReceiptRow.self),
                 planDocuments: try boundedFetch(PlanDocumentRow.self),
                 planRevisions: try boundedFetch(PlanRevisionRow.self),
                 planPlacements: try boundedFetch(PlanPlacementRow.self),
                 rebaseReceipts: try boundedFetch(RebaseReceiptRow.self),
                 poseEvents: try boundedFetch(AssetPoseEventRow.self),
                 spatialAnchorObservations: try boundedFetch(SpatialAnchorObservationRow.self),
                observationAndTime: observationAndTime,
                recordPayloads: recordPayloads,
                evidence: try boundedFetch(EvidenceFile.self),
                issues: try boundedFetch(Issue.self),
                packets: try boundedFetch(Packet.self),
                reports: try boundedFetch(Report.self),
                acceptedLabelSnapshots: try boundedFetch(AcceptedLabelGenerationSnapshotRow.self)
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func validateLocationDeletionNoCascade(
        rows: Rows,
        deletingAssetID: UUID?,
        deletingSiteID: UUID?
    ) throws {
        try validateInspectionReviewPreservation(
            rows, deletingAssetID: deletingAssetID, deletingSiteID: deletingSiteID
        )
        try validateWorkPacketPreservation(
            rows, deletingAssetID: deletingAssetID, deletingSiteID: deletingSiteID
        )
        let locatorValues = try rows.assetLocators.map { try $0.value() }
        let receiptValues = try rows.locatorBindingReceipts.map { try $0.value() }
        try AssetLocatorOrphanCleanupPolicyV1.validate(
            locators: locatorValues,
            receipts: receiptValues
        )
        let locatorInventory = try AssetLocatorDeletionInventoryV1(
            locators: locatorValues, receipts: receiptValues
        )
        try WholeSignDeletionRule.validateAssetLocatorLifecycle(
            before: locatorInventory, after: locatorInventory, workspaceErase: false
        )
        let workPacketInventory=WorkPacketDeletionInventoryV1(manifestIDs:Set(rows.workPacketManifests.map(\.manifestID)),claimIDs:Set(rows.workItemClaims.map(\.claimID)),leaseIDs:Set(rows.workLeases.map(\.leaseID)),releaseIDs:Set(rows.workReleases.map(\.releaseID)),handoffIDs:Set(rows.workHandoffs.map(\.handoffID)))
        try WholeSignDeletionRule.validateWorkPacketLifecycle(authority:.ordinaryAssetOrSiteDelete,before:workPacketInventory,after:workPacketInventory)
        let draftInventory = FieldDraftDeletionInventoryV1(
            draftIDs:Set(rows.fieldDraftCheckpoints.map(\.draftID)), stageIDs:Set(rows.attachmentStagingItems.map(\.stageID)),
            sagaIDs:Set(rows.draftCommitSagas.map(\.sagaID)), reservationIDs:Set(rows.draftContentReservations.map(\.reservationID)),
            commitReceiptIDs:Set(rows.draftCommitReceipts.map(\.receiptID)), discardReceiptIDs:Set(rows.draftDiscardReceipts.map(\.receiptID))
        )
        try WholeSignDeletionRule.validateFieldDraftLifecycle(authority:.ordinaryAssetOrSiteDelete,before:draftInventory,after:draftInventory)
        let packageInventory = PackageEvolutionDeletionInventoryV1(
            releaseRecordIDs: Set(rows.promotedPackageReleases.map(\.releaseRecordID)),
            sandboxRunIDs: Set(rows.packageSandboxRuns.map(\.runID)),
            promotionReceiptIDs: Set(rows.packagePromotionReceipts.map(\.receiptID)),
            pointerIDs: Set(rows.activePackageRegistryPointers.map(\.pointerID))
        )
        try WholeSignDeletionRule.validatePackageEvolutionLifecycle(
            authority: .ordinaryAssetOrSiteDelete, before: packageInventory, after: packageInventory
        )
        let measurementInventory=MeasurementIntegrityDeletionInventoryV1(instrumentReferences:rows.instrumentReferences.count,calibrationSnapshots:rows.calibrationStatusSnapshots.count,measurementCaptures:rows.measurementCaptures.count,measurementSeries:rows.measurementSeries.count,qualityAssessments:rows.measurementQualityAssessments.count)
        try WholeSignDeletionRule.validateMeasurementIntegrityLifecycle(authority:.ordinaryAssetOrSiteDelete,before:measurementInventory,after:measurementInventory)
        let privacyInventory=PrivacyTransformDeletionInventoryV1(policies:rows.privacyTransformPolicies.count,regions:rows.privacyRegions.count,manifests:rows.privacyTransformManifests.count,reviewReceipts:rows.privacyReviewReceipts.count)
        try WholeSignDeletionRule.validatePrivacyTransformLifecycle(authority:.ordinaryDelete,before:privacyInventory,after:privacyInventory)
        let capabilityInventory=ClientCapabilityDeletionInventoryV1(profiles:rows.clientCapabilityProfiles.count,policies:rows.packageLifecyclePolicies.count,dispositions:rows.packageLifecycleDispositions.count,decisions:rows.clientCapabilityAdmissionDecisions.count)
        try WholeSignDeletionRule.validateClientCapabilityLifecycle(before:capabilityInventory,after:capabilityInventory,workspaceErase:false)
        let fieldReferenceValues=try Dictionary(uniqueKeysWithValues:rows.fieldReferenceReleases.map{let value=try $0.value();return(value.releaseID,value)})
        for row in rows.fieldReferenceBindings{guard let release=fieldReferenceValues[row.releaseID]else{throw WholeSignDeletionServiceError.graphInvalid};_ = try row.value(release:release)}
        let retainedReleaseIDs=Set(rows.fieldReferenceBindings.map(\.releaseID))
        let fieldReferenceInventory=FieldReferenceDeletionInventoryV1(releaseIDs:Set(fieldReferenceValues.keys),bindingIDs:Set(rows.fieldReferenceBindings.map(\.bindingID)),retainedReleaseIDs:retainedReleaseIDs)
        try WholeSignDeletionRule.validateFieldReferenceLifecycle(before:fieldReferenceInventory,after:fieldReferenceInventory,workspaceErase:false)
        let accessibleReceipts=try rows.accessibleDocumentAssessmentReceipts.map{try $0.value()}
        let accessibleInventory=AccessibleDocumentDeletionInventoryV1(receiptIDs:Set(accessibleReceipts.map(\.receiptID)),outputSHA256:Set(accessibleReceipts.map(\.outputSHA256)))
        try WholeSignDeletionRule.validateAccessibleDocumentLifecycle(before:accessibleInventory,after:accessibleInventory,workspaceErase:false)
        let surveyInventory=SurveyDefinitionDeletionInventoryV1(identityIDs:Set(rows.surveyDefinitionIdentities.map(\.definitionID)),releaseIDs:Set(rows.surveyDefinitionReleases.map(\.releaseID)))
        try WholeSignDeletionRule.validateSurveyDefinitionLifecycle(before:surveyInventory,after:surveyInventory,workspaceErase:false)
        try rows.surveySessions.forEach{_ = try $0.value()};try rows.factCaptures.forEach{_ = try $0.value()};try rows.provisionalSubjects.forEach{_ = try $0.value()};try rows.subjectPromotionReceipts.forEach{_ = try $0.value()};try rows.surveyPublicationSnapshots.forEach{_ = try $0.value()};let sessionInventory=SurveySessionDeletionInventoryV1(sessionIDs:Set(rows.surveySessions.map(\.sessionID)),captureIDs:Set(rows.factCaptures.map(\.captureID)),provisionalSubjectIDs:Set(rows.provisionalSubjects.map(\.provisionalSubjectID)),promotionReceiptIDs:Set(rows.subjectPromotionReceipts.map(\.receiptID)),publicationSnapshotIDs:Set(rows.surveyPublicationSnapshots.map(\.snapshotID)));try WholeSignDeletionRule.validateSurveySessionLifecycle(before:sessionInventory,after:sessionInventory,workspaceErase:false);try SurveySessionDeletionLedgerPolicyV1.validate()
        let scheduleDefinitions = try rows.scheduleDefinitionReleases.map { try $0.value() }
        let scheduleHistory = try rows.occurrenceHistoryEvents.map { try $0.value() }
        let scheduleInventory = try ScheduleDeletionInventoryV1(
            definitions: scheduleDefinitions,
            history: scheduleHistory
        )
        try WholeSignDeletionRule.validateScheduleLifecycle(
            before: scheduleInventory,
            after: scheduleInventory,
            workspaceErase: false
        )
        let planDocuments = try rows.planDocuments.map { try $0.value() }
        let planRevisions = try rows.planRevisions.map { try $0.value() }
        let planPlacements = try rows.planPlacements.map { try $0.value() }
        let rebaseReceipts = try rows.rebaseReceipts.map { try $0.value() }
        try PlanLifecycleClosureV1(
            documentHistory: planDocuments,
            revisionHistory: planRevisions,
            placementHistory: planPlacements,
            receipts: rebaseReceipts
        ).validate()
        try PlanKernelDeletionEnrollmentV1.validate()
        try PlacementPoseKernelDeletionEnrollmentV1.validate()
        try PlacementPoseDeletionLedgerPolicyV1.validate()
        let poseRecords = try (
            rows.poseEvents.map { row -> V29BackupPlacementPoseRecordV1 in
                let value = try row.value()
                return .init(
                    kind: .poseEvent,
                    id: value.eventID,
                    workspaceID: value.workspaceID.rawValue,
                    revision: value.revision,
                    canonicalData: try PlacementPoseCanonicalCodecV1.encode(value)
                )
            }
            + rows.spatialAnchorObservations.map { row -> V29BackupPlacementPoseRecordV1 in
                let value = try row.value()
                return .init(
                    kind: .spatialAnchorObservation,
                    id: value.observationID,
                    workspaceID: value.workspaceID.rawValue,
                    revision: value.revision,
                    canonicalData: try PlacementPoseCanonicalCodecV1.encode(value)
                )
            }
        ).sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        _ = try PlacementPoseBackupRecordSetV1.decode(poseRecords)
        do {
            var assetIDs = Set<UUID>()
            if let deletingAssetID { assetIDs.insert(deletingAssetID) }
            if let deletingSiteID { assetIDs.formUnion(rows.assets.filter { $0.siteID == deletingSiteID }.map(\.id)) }
            let recordIDs = Set(rows.records.filter { assetIDs.contains($0.assetID) }.map(\.id))
            let evidenceIDs = Set(rows.evidence.filter { recordIDs.contains($0.recordID) }.map(\.id))
            let affectedContentIDs = Set(evidenceIDs.flatMap { [$0.uuidString, $0.uuidString.lowercased()] })
            let policies = try Dictionary(uniqueKeysWithValues: rows.privacyTransformPolicies.map { let value = try $0.value(); return (value.policyID, value) })
            let manifests = try rows.privacyTransformManifests.map { row -> PrivacyTransformManifestV1 in
                guard let policy = policies[row.policyID] else { throw WholeSignDeletionServiceError.graphInvalid }
                return try row.value(policy: policy)
            }
            var diagnostics = Set<String>()
            for value in manifests {
                if affectedContentIDs.contains(value.original.contentID) {
                    diagnostics.insert("ORIGINAL:\(value.original.contentID):\(value.sourceRevision):\(value.sourceSHA256)")
                }
                if affectedContentIDs.contains(value.derivative.contentID) {
                    diagnostics.insert("DERIVATIVE:\(value.derivative.contentID):\(value.revision):\(value.derivativeSHA256)")
                }
            }
            guard diagnostics.isEmpty else {
                throw WholeSignDeletionServiceError.retainedPrivacyTransformReferences(diagnostics.sorted())
            }
        } catch let error as WholeSignDeletionServiceError { throw error }
        catch { throw WholeSignDeletionServiceError.graphInvalid }
        do {
            let descriptors = try rows.functionalRelationshipDescriptors.map { try $0.value() }
            let events = try rows.functionalRelationshipEvents.map { try $0.value() }
            for workspaceID in Set(events.map(\.workspaceID)) {
                let projection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
                    workspaceID: workspaceID,
                    events: events.filter { $0.workspaceID == workspaceID },
                    descriptors: descriptors.filter { $0.workspaceID == workspaceID }
                )
                if let deletingAssetID,
                   let siteID = rows.assets.first(where: { $0.id == deletingAssetID })?.siteID {
                    let previews = try WholeSignDeletionRule
                        .functionalRelationshipEndpointDeletionPreviews(
                            assetID: deletingAssetID, assetSiteID: siteID,
                            projection: projection, descriptors: descriptors
                        )
                    guard previews.isEmpty,
                          previews.allSatisfy({ !$0.persistentWriteOccurred }) else {
                        throw WholeSignDeletionServiceError.graphInvalid
                    }
                }
                if let deletingSiteID {
                    let siteAssets = Set(rows.assets.filter { $0.siteID == deletingSiteID }.map(\.id))
                    guard !projection.currentRelationships.contains(where: {
                        siteAssets.contains($0.sourceAssetID) || siteAssets.contains($0.targetAssetID)
                    }) else { throw WholeSignDeletionServiceError.graphInvalid }
                }
            }
            try WholeSignDeletionRule.validateLocationDeletionNoCascade(
                deletingAssetID: deletingAssetID,
                deletingSiteID: deletingSiteID,
                liveAssetSiteByID: Dictionary(uniqueKeysWithValues: rows.assets.map { ($0.id, $0.siteID) }),
                locationNodes: try rows.locationNodes.map { try $0.value() },
                placementEvents: try rows.placementEvents.map { try $0.value() },
                compositionEdges: try rows.compositionEdges.map {
                    try LocationPersistenceCodecV1.decode(
                        AssetCompositionEdgeV1.self,
                        from: $0.canonicalData
                    )
                }
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
    }

    func validateInspectionReviewPreservation(
        _ rows: Rows, deletingAssetID: UUID?, deletingSiteID: UUID?
    ) throws {
        do {
            let transitions = try rows.inspectionReviewTransitions.map { try $0.value() }
            let dispositions = try rows.reviewDispositions.map { try $0.value() }
            let requests = try rows.changeRequests.map { try $0.value() }
            let policies = try rows.correctiveActionPolicies.map { try $0.value() }
            let actions = try rows.correctiveActionEvents.map { try $0.value() }
            let inventory = InspectionReviewDeletionInventoryV1(
                transitionIDs: Set(transitions.map(\.transitionID)),
                dispositionIDs: Set(dispositions.map(\.dispositionID)),
                requestRevisionIDs: Set(requests.map(\.requestRevisionID)),
                policyReleaseIDs: Set(policies.map(\.releaseID)), actionEventIDs: Set(actions.map(\.eventID)))
            try WholeSignDeletionRule.validateInspectionReviewLifecycle(
                authority: .ordinaryAssetOrSiteDelete, before: inventory, after: inventory
            )
            var assetIDs = Set<UUID>()
            if let deletingAssetID { assetIDs.insert(deletingAssetID) }
            if let deletingSiteID { assetIDs.formUnion(rows.assets.filter { $0.siteID == deletingSiteID }.map(\.id)) }
            let recordIDs = Set(rows.records.filter { assetIDs.contains($0.assetID) }.map(\.id))
            let affectedPackets = rows.packets.filter {
                $0.currentRecordID.map(recordIDs.contains) ?? false
            }
            let packetIDs = Set(affectedPackets.map(\.id))
            let stableRootIDs = Set(affectedPackets.map(\.stableRootID))
            let affectedReports = rows.reports.filter {
                recordIDs.contains($0.sourceRecordID) || packetIDs.contains($0.packetID)
            }
            let reportIDs = Set(affectedReports.map(\.id))
            let reportPacketIDs = Set(affectedReports.map(\.packetID))
            let evidenceIDs = Set(rows.evidence.filter { recordIDs.contains($0.recordID) }.map(\.id))
            let affected = Set((assetIDs.union(recordIDs).union(packetIDs).union(stableRootIDs)
                .union(reportIDs).union(reportPacketIDs).union(evidenceIDs)).flatMap {
                [$0.uuidString, $0.uuidString.lowercased()]
            })
            var diagnostics = Set<String>()
            for value in transitions where [.accepted,.finalized,.amended,.superseded].contains(value.toState) {
                if affected.contains(value.subject.subjectID) {
                    diagnostics.insert("SUBJECT:\(value.subject.kind.rawValue):\(value.subject.subjectID):\(value.subject.subjectRevision):\(value.subject.subjectSHA256)")
                }
            }
            for value in requests {
                if affected.contains(value.item.itemID) {
                    diagnostics.insert("CHANGE_ITEM:\(value.item.kind.rawValue):\(value.item.itemID):\(value.item.itemRevision):\(value.item.itemSHA256)")
                }
                for reference in value.resolution?.evidence ?? [] where affected.contains(reference.referenceID) {
                    diagnostics.insert("CHANGE_EVIDENCE:\(reference.kind.rawValue):\(reference.referenceID):\(reference.revision):\(reference.sha256)")
                }
            }
            for value in actions {
                if affected.contains(value.source.itemID) {
                    diagnostics.insert("ACTION_SOURCE:\(value.source.kind.rawValue):\(value.source.itemID):\(value.source.itemRevision):\(value.source.itemSHA256)")
                }
                for reference in value.closureEvidence where affected.contains(reference.referenceID) {
                    diagnostics.insert("ACTION_EVIDENCE:\(reference.kind.rawValue):\(reference.referenceID):\(reference.revision):\(reference.sha256)")
                }
            }
            guard diagnostics.isEmpty else {
                throw WholeSignDeletionServiceError.retainedInspectionReviewReferences(diagnostics.sorted())
            }
        } catch let error as WholeSignDeletionServiceError { throw error }
        catch { throw WholeSignDeletionServiceError.graphInvalid }
    }

    func validateWorkPacketPreservation(
        _ rows: Rows, deletingAssetID: UUID?, deletingSiteID: UUID?
    ) throws {
        do {
            var assetIDs = Set<UUID>()
            if let deletingAssetID { assetIDs.insert(deletingAssetID) }
            if let deletingSiteID {
                assetIDs.formUnion(rows.assets.filter { $0.siteID == deletingSiteID }.map(\.id))
            }
            let recordIDs = Set(rows.records.filter { assetIDs.contains($0.assetID) }.map(\.id))
            let packets = rows.packets.filter { $0.currentRecordID.map(recordIDs.contains) ?? false }
            let packetIDs = Set(packets.map(\.id))
            let stableRootIDs = Set(packets.map(\.stableRootID))
            let reports = rows.reports.filter {
                recordIDs.contains($0.sourceRecordID) || packetIDs.contains($0.packetID)
            }
            let reportIDs = Set(reports.map(\.id))
            let evidenceIDs = Set(rows.evidence.filter { recordIDs.contains($0.recordID) }.map(\.id))
            let affectedUUIDs = assetIDs.union(recordIDs).union(packetIDs).union(stableRootIDs)
                .union(reportIDs).union(evidenceIDs)
            let affectedStrings = Set(affectedUUIDs.flatMap {
                [$0.uuidString, $0.uuidString.lowercased()]
            })
            let manifests = try rows.workPacketManifests.map { try $0.value() }
            let claims = try rows.workItemClaims.map { try $0.value() }
            let leases = try rows.workLeases.map { try $0.value() }
            let releases = try rows.workReleases.map { try $0.value() }
            let handoffs = try rows.workHandoffs.map { try $0.value() }
            var diagnostics = Set<String>()
            for value in manifests {
                if packetIDs.contains(value.packetID) {
                    diagnostics.insert("MANIFEST_PACKET:\(value.manifestID.uuidString):\(value.packetID.uuidString):\(value.packetVersion):\(value.manifestSHA256)")
                }
                for item in value.items where affectedStrings.contains(item.itemID) {
                    diagnostics.insert("MANIFEST_ITEM:\(item.kind.rawValue):\(item.itemID):\(item.expectedRevision):\(item.itemSHA256)")
                }
            }
            func inspect(_ item: WorkPacketItemReferenceV1, results: [WorkPacketResultLinkV1]) {
                if affectedStrings.contains(item.itemID) {
                    diagnostics.insert("ITEM_REFERENCE:\(item.itemKind.rawValue):\(item.itemID):\(item.expectedRevision):\(item.itemSHA256)")
                }
                for result in results {
                    if affectedUUIDs.contains(result.resultID) {
                        diagnostics.insert("RESULT:\(result.resultID.uuidString):\(result.resultRevision):\(result.resultSHA256)")
                    }
                    for evidence in result.evidence where affectedStrings.contains(evidence.referenceID) {
                        diagnostics.insert("RESULT_EVIDENCE:\(evidence.kind.rawValue):\(evidence.referenceID):\(evidence.revision):\(evidence.sha256)")
                    }
                }
            }
            claims.forEach { inspect($0.item, results: []) }
            leases.forEach { inspect($0.item, results: []) }
            releases.forEach { inspect($0.item, results: $0.resultLinks) }
            handoffs.forEach { inspect($0.item, results: $0.resultLinks) }
            guard diagnostics.isEmpty else {
                throw WholeSignDeletionServiceError.retainedWorkPacketReferences(diagnostics.sorted())
            }
        } catch let error as WholeSignDeletionServiceError { throw error }
        catch { throw WholeSignDeletionServiceError.graphInvalid }
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

    func validatedObservationAndTimeIndex(
        records: [WorkflowRecord]
    ) throws -> [UUID: ObservationAndTimeRow] {
        guard records.count <= Self.maximumGraphRowsPerKind else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        var rows: [ObservationAndTimeRow] = []
        rows.reserveCapacity(records.count)
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<ObservationAndTimeRow>(
                sortBy: [SortDescriptor(\.recordID)]
            )
            descriptor.fetchLimit = Self.observationAndTimeBatchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            rows.append(contentsOf: batch)
            guard rows.count <= Self.maximumGraphRowsPerKind else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
            guard batch.count == Self.observationAndTimeBatchSize else { break }
            offset += batch.count
        }

        let recordIDs = Set(records.map(\.id))
        var result: [UUID: ObservationAndTimeRow] = [:]
        result.reserveCapacity(rows.count)
        for row in rows {
            guard recordIDs.contains(row.recordID),
                  result.updateValue(row, forKey: row.recordID) == nil else {
                throw WholeSignDeletionServiceError.graphInvalid
            }
            do { try row.validate() } catch {
                throw WholeSignDeletionServiceError.graphInvalid
            }
        }
        guard result.count == recordIDs.count else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        return result
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
            records: rows.recordPayloads,
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

    func payload(
        _ row: WorkflowRecord,
        companion: ObservationAndTimeRow
    ) -> WorkflowRecordPayloadV1 {
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
            finalizationMutationID: row.finalizationMutationID,
            observationBasisV1Data: companion.observationBasisV1Data,
            temporalContextV1Data: companion.temporalContextV1Data
        )
    }

    func validateOwnedFiles(
        plan: WholeSignDeletionPlan,
        rows: Rows
    ) throws {
        if !plan.reportIDs.isEmpty {
            let coordinator: ReportDeliveryCoordinator
            do {
                let packageProfile = try lifecycleProfile(
                    for: plan.assetID,
                    rows: rows
                )
                switch lifecycleRoute {
                case .live:
                    coordinator = try ReportDeliveryCoordinator(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL,
                        signPack: packageProfile.package
                    )
                case .expiringCompatibility:
                    // Legacy XCTest stores predate the package dependency
                    // boundary. The explicit compatibility route resolves
                    // the requested package's legacy V3 profile.
                    coordinator = try ReportDeliveryCoordinator(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL,
                        signPack: packageProfile.package
                    )
                }
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
        guard intent.schemaVersion == 2 || intent.schemaVersion == 3 else { return nil }
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
        guard let basePlan = try? WholeSignDeletionRule.makePlan(input),
              let augmentedIntent = try? addingAcceptedLabelSnapshotLedgerEntries(
                  to: basePlan.intent,
                  snapshots: acceptedLabelSnapshots(
                      referencing: intent.assetID, rows: rows
                  )
              ),
              augmentedIntent == intent else { return nil }
        let plan = WholeSignDeletionPlan(
            assetID: basePlan.assetID,
            evidenceIDs: basePlan.evidenceIDs,
            intent: augmentedIntent,
            issueIDs: basePlan.issueIDs,
            packetIDsToDelete: basePlan.packetIDsToDelete,
            reportIDs: basePlan.reportIDs,
            siteIDToDelete: basePlan.siteIDToDelete,
            workflowRecordIDs: basePlan.workflowRecordIDs
        )
        if case .live = lifecycleRoute {
            try validateDeleteCommand(for: plan)
        }
        try validateOwnedFiles(
            plan: plan,
            rows: rows
        )
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
        if case .live = lifecycleRoute {
            try validateDeleteCommand(for: plan)
        }
        try validateOwnedFiles(
            plan: plan,
            rows: rows
        )
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
              unique(rows.serviceParties.map(\.partyID)),
              unique(rows.sitePartyRoles.map(\.eventID)),
              unique(rows.actorSnapshots.map(\.snapshotID)),
              unique(rows.qualificationSnapshots.map(\.snapshotID)),
              unique(rows.signoffSnapshots.map(\.snapshotID)),
              unique(rows.assetKindBindingEvents.map(\.eventID)),
              unique(rows.assetWorkflowCapabilityBindingEvents.map(\.eventID)),
              unique(rows.assetProductIdentities.map(\.identityID)),
              unique(rows.assetLifecycleEvents.map(\.eventID)),
              unique(rows.assetSuccessorLinks.map(\.linkID)),
              unique(rows.workSubjectScopeSnapshots.map(\.snapshotID)),
              unique(rows.functionalRelationshipDescriptors.map(\.descriptorReleaseID)),
              unique(rows.functionalRelationshipEvents.map(\.eventID)),
              unique(rows.evidenceVisibilities.map(\.visibilityID)),
              unique(rows.claimEvidenceLinks.map(\.linkID)),
              unique(rows.assuranceManifests.map(\.manifestID)),
              unique(rows.attestations.map(\.attestationID)),
              rows.serviceParties.allSatisfy({ (try? $0.value()) != nil }),
              rows.sitePartyRoles.allSatisfy({ (try? $0.value()) != nil }),
              rows.actorSnapshots.allSatisfy({ (try? $0.value()) != nil }),
              rows.qualificationSnapshots.allSatisfy({ (try? $0.value()) != nil }),
              rows.signoffSnapshots.allSatisfy({ (try? $0.value()) != nil }),
              rows.assetKindBindingEvents.allSatisfy({ (try? $0.value()) != nil }),
              rows.assetWorkflowCapabilityBindingEvents.allSatisfy({ (try? $0.value()) != nil }),
              rows.assetProductIdentities.allSatisfy({ (try? $0.value()) != nil }),
              rows.assetLifecycleEvents.allSatisfy({ (try? $0.value()) != nil }),
              rows.assetSuccessorLinks.allSatisfy({ (try? $0.value()) != nil }),
              rows.workSubjectScopeSnapshots.allSatisfy({ (try? $0.value()) != nil }),
              rows.functionalRelationshipDescriptors.allSatisfy({ (try? $0.value()) != nil }),
              rows.functionalRelationshipEvents.allSatisfy({ (try? $0.value()) != nil }),
              rows.evidenceVisibilities.allSatisfy({ (try? $0.value()) != nil }),
              rows.claimEvidenceLinks.allSatisfy({ (try? $0.value()) != nil }),
              rows.assuranceManifests.allSatisfy({ (try? $0.value()) != nil }),
              rows.attestations.allSatisfy({ (try? $0.value()) != nil }),
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
        if intent.schemaVersion == 2 || intent.schemaVersion == 3 {
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

    func acceptedLabelSnapshots(
        referencing assetID: UUID,
        rows: Rows
    ) throws -> [AcceptedLabelGenerationSnapshotV1] {
        try rows.acceptedLabelSnapshots.compactMap { row in
            let snapshot = try row.value()
            return snapshot.plan.items.contains(where: { $0.assetID == assetID })
                ? snapshot : nil
        }.sorted { $0.snapshotID.uuidString < $1.snapshotID.uuidString }
    }

    func addingAcceptedLabelSnapshotLedgerEntries(
        to intent: DeletionIntentV1,
        snapshots: [AcceptedLabelGenerationSnapshotV1]
    ) throws -> DeletionIntentV1 {
        guard intent.schemaVersion == 2,
              let deletedAt = intent.ledgerEntries.first?.deletedAt,
              intent.ledgerEntries.allSatisfy({ $0.deletedAt == deletedAt }) else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        let additions = try snapshots.map {
            try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(
                    kind: .acceptedLabelGenerationSnapshot, id: $0.snapshotID
                ),
                deletedAt: deletedAt
            )
        }
        let cleanups = try snapshots.map {
            try AssetLabelPublishedOutputCleanupV1(snapshot: $0)
        }
        return DeletionIntentV1(
            acceptedLabelOutputCleanups: cleanups,
            assetID: intent.assetID,
            countedPacketTombstones: intent.countedPacketTombstones,
            deletionID: intent.deletionID,
            generationID: intent.generationID,
            ledgerEntries: (intent.ledgerEntries + additions).sorted {
                $0.identity < $1.identity
            },
            phase: intent.phase,
            relativePaths: intent.relativePaths,
            schemaVersion: cleanups.isEmpty ? intent.schemaVersion : 3
        )
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
        case .acceptedLabelGenerationSnapshot:
            return rows.acceptedLabelSnapshots.contains { $0.snapshotID == identity.id }
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
        let labelSnapshots = try rows.acceptedLabelSnapshots.compactMap {
            row -> AcceptedLabelGenerationSnapshotRow? in
            let snapshot = try row.value()
            guard snapshot.plan.items.contains(where: { $0.assetID == plan.assetID }) else {
                return nil
            }
            return row
        }
        let deletedLocatorIDs = Set(rows.assetLocators.filter {
            $0.assetID == plan.assetID
        }.map(\.locatorID))
        if !deletedLocatorIDs.isEmpty {
            rows.locatorBindingReceipts.filter {
                deletedLocatorIDs.contains($0.afterLocatorID)
                    || ($0.replacementLocatorID.map(deletedLocatorIDs.contains) ?? false)
            }.forEach { modelContext.delete($0) }
            rows.assetLocators.filter {
                deletedLocatorIDs.contains($0.locatorID)
            }.forEach { modelContext.delete($0) }
        }
        let remainingLocatorIDs = Set(rows.assetLocators.map(\.locatorID))
            .subtracting(deletedLocatorIDs)
        guard rows.locatorBindingReceipts.filter {
            !deletedLocatorIDs.contains($0.afterLocatorID)
                && !($0.replacementLocatorID.map(deletedLocatorIDs.contains) ?? false)
        }.allSatisfy {
            remainingLocatorIDs.contains($0.afterLocatorID)
                && ($0.replacementLocatorID.map(remainingLocatorIDs.contains) ?? true)
        } else {
            throw WholeSignDeletionServiceError.graphInvalid
        }
        rows.evidence.filter { evidenceIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        rows.issues.filter { issueIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        let retainedAccessibleOutputDigests=Set(try rows.accessibleDocumentAssessmentReceipts.map{try $0.value().outputSHA256})
        rows.reports.filter { reportIDs.contains($0.id) && !retainedAccessibleOutputDigests.contains($0.snapshotSHA256) && !($0.pdfSHA256.map(retainedAccessibleOutputDigests.contains) ?? false) }.forEach { modelContext.delete($0) }
        recordIDs.compactMap { rows.observationAndTime[$0] }
            .forEach { modelContext.delete($0) }
        rows.requirementAssurance.filter { recordIDs.contains($0.workflowRecordID) }
            .forEach { modelContext.delete($0) }
        let boundFieldReferenceReleaseIDs=Set(rows.fieldReferenceBindings.map(\.releaseID))
        for row in rows.fieldReferenceReleases where !boundFieldReferenceReleaseIDs.contains(row.releaseID){_ = try row.value();modelContext.delete(row)}
        rows.records.filter { recordIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        rows.packets.filter { packetDeleteIDs.contains($0.id) }.forEach { modelContext.delete($0) }
        labelSnapshots.forEach { modelContext.delete($0) }
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
    static let observationAndTimeBatchSize = 512
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

private struct SiteSearchPurgeMarkerV1: Codable, Equatable {
    let schemaVersion: Int
    let siteID: UUID
    let deletionID: UUID
    let generationID: UUID
    let phase: DeletionPhaseV1

    init(
        siteID: UUID,
        deletionID: UUID,
        generationID: UUID,
        phase: DeletionPhaseV1 = .prepared
    ) {
        schemaVersion = 1
        self.siteID = siteID
        self.deletionID = deletionID
        self.generationID = generationID
        self.phase = phase
    }

    func withPhase(_ phase: DeletionPhaseV1) -> Self {
        Self(
            siteID: siteID,
            deletionID: deletionID,
            generationID: generationID,
            phase: phase
        )
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

    func createSiteSearchPurgeMarker(_ marker: SiteSearchPurgeMarkerV1) throws {
        guard marker.phase == .prepared else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        try write(marker, exclusive: true)
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

    func replaceSiteSearchPurgeMarker(_ marker: SiteSearchPurgeMarkerV1) throws {
        guard marker.phase == .databaseCommitted else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        let expected = marker.withPhase(.prepared)
        let name = Self.siteMarkerName(marker.deletionID)
        try verifyExistingPolicy(.journal, name: name)
        try withDeletionDirectory { descriptor in
            let existing = try Self.decodeSiteMarker(
                Self.read(descriptor: descriptor, name: name)
            )
            guard existing == expected else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
        }
        try write(marker, exclusive: false)
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

    func removeSiteSearchPurgeMarker(_ expected: SiteSearchPurgeMarkerV1) throws {
        let name = Self.siteMarkerName(expected.deletionID)
        try verifyExistingPolicy(.journal, name: name)
        try withDeletionDirectory { descriptor in
            let existing = try Self.decodeSiteMarker(
                Self.read(descriptor: descriptor, name: name)
            )
            guard existing == expected,
                  Darwin.unlinkat(descriptor, name, 0) == 0,
                  Darwin.fsync(descriptor) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
        }
    }

    func isEmpty() throws -> Bool {
        let assetIntents = try loadAll()
        let siteMarkers = try loadAllSiteSearchPurgeMarkers()
        return assetIntents.isEmpty && siteMarkers.isEmpty
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
            let siteTemporaryNames = names.filter {
                Self.siteTemporaryIdentifier($0) != nil
            }
            let siteMarkerNames = names.filter {
                Self.siteMarkerIdentifier($0) != nil
            }
            guard temporaryNames.count + journalNames.count
                    + siteTemporaryNames.count + siteMarkerNames.count == names.count else {
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
                    let beforeSwap = existing.phase == .prepared
                        && replacement == existing.withPhase(.databaseCommitted)
                    let afterSwap = existing.phase == .databaseCommitted
                        && replacement == existing.withPhase(.prepared)
                    guard existing.deletionID == temporaryID,
                          beforeSwap || afterSwap else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                }
                try Self.removeIfExact(
                    descriptor: descriptor,
                    name: temporary,
                    expected: expectedTemporary
                )
            }
            let siteMarkerIDs = Set(
                siteMarkerNames.compactMap(Self.siteMarkerIdentifier)
            )
            for temporary in siteTemporaryNames {
                try verifyExistingPolicy(.journalTemporary, name: temporary)
                guard let temporaryID = Self.siteTemporaryIdentifier(temporary) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let file = Darwin.openat(descriptor, temporary, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let expectedTemporary = try Self.fileIdentity(file)
                Darwin.close(file)
                if siteMarkerIDs.contains(temporaryID) {
                    let existing = try Self.decodeSiteMarker(
                        Self.read(
                            descriptor: descriptor,
                            name: Self.siteMarkerName(temporaryID)
                        )
                    )
                    let replacement = try Self.decodeSiteMarker(
                        Self.read(descriptor: descriptor, name: temporary)
                    )
                    let beforeSwap = existing.phase == .prepared
                        && replacement == existing.withPhase(.databaseCommitted)
                    let afterSwap = existing.phase == .databaseCommitted
                        && replacement == existing.withPhase(.prepared)
                    guard existing.deletionID == temporaryID,
                          beforeSwap || afterSwap else {
                        throw WholeSignDeletionServiceError.journalInvalid
                    }
                }
                try Self.removeIfExact(
                    descriptor: descriptor,
                    name: temporary,
                    expected: expectedTemporary
                )
            }
            if (!temporaryNames.isEmpty || !siteTemporaryNames.isEmpty),
               Darwin.fsync(descriptor) != 0 {
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

    func loadAllSiteSearchPurgeMarkers() throws -> [SiteSearchPurgeMarkerV1] {
        _ = try loadAll()
        return try withDeletionDirectory { descriptor in
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
                if Self.siteMarkerIdentifier(name) != nil {
                    names.append(name)
                }
                errno = 0
            }
            guard errno == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            return try names.sorted().map { name in
                try verifyExistingPolicy(.journal, name: name)
                guard let identifier = Self.siteMarkerIdentifier(name) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let marker = try Self.decodeSiteMarker(
                    Self.read(descriptor: descriptor, name: name)
                )
                guard marker.deletionID == identifier else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                return marker
            }
        }
    }

    private func write(_ intent: DeletionIntentV1, exclusive: Bool) throws {
        let data: Data
        do { data = try DeletionIntentEncoderV1().encode(intent).data }
        catch { throw WholeSignDeletionServiceError.journalInvalid }
        let expectedData: Data?
        if exclusive {
            expectedData = nil
        } else {
            do {
                expectedData = try DeletionIntentEncoderV1()
                    .encode(intent.withPhase(.prepared)).data
            } catch {
                throw WholeSignDeletionServiceError.journalInvalid
            }
        }
        try write(
            data: data,
            name: Self.name(intent.deletionID),
            temporary: ".\(intent.deletionID.uuidString.lowercased()).tmp",
            exclusive: exclusive,
            expectedData: expectedData
        )
    }

    private func write(
        _ marker: SiteSearchPurgeMarkerV1,
        exclusive: Bool
    ) throws {
        let data = try Self.encodeSiteMarker(marker)
        let expectedData: Data?
        if exclusive {
            expectedData = nil
        } else {
            expectedData = try Self.encodeSiteMarker(
                marker.withPhase(.prepared)
            )
        }
        try write(
            data: data,
            name: Self.siteMarkerName(marker.deletionID),
            temporary: Self.siteTemporaryName(marker.deletionID),
            exclusive: exclusive,
            expectedData: expectedData
        )
    }

    private func write(
        data: Data,
        name: String,
        temporary: String,
        exclusive: Bool,
        expectedData: Data?
    ) throws {
        try withDeletionDirectory { descriptor in
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
                guard let expectedData else {
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

    private static func encodeSiteMarker(
        _ marker: SiteSearchPurgeMarkerV1
    ) throws -> Data {
        guard marker.schemaVersion == 1,
              marker.siteID != zeroUUID,
              marker.deletionID != zeroUUID,
              marker.generationID != zeroUUID else {
            throw WholeSignDeletionServiceError.journalInvalid
        }
        do {
            return try CanonicalJSONV1.encode(.object([
                "deletionID": CanonicalJSONV1.uuid(marker.deletionID),
                "generationID": CanonicalJSONV1.uuid(marker.generationID),
                "phase": .string(marker.phase.rawValue),
                "schemaVersion": .integer(marker.schemaVersion),
                "siteID": CanonicalJSONV1.uuid(marker.siteID),
            ]))
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
    }

    private static func decodeSiteMarker(
        _ data: Data
    ) throws -> SiteSearchPurgeMarkerV1 {
        do {
            let marker = try JSONDecoder().decode(
                SiteSearchPurgeMarkerV1.self,
                from: data
            )
            guard try encodeSiteMarker(marker) == data else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            return marker
        } catch let error as WholeSignDeletionServiceError {
            throw error
        } catch {
            throw WholeSignDeletionServiceError.journalInvalid
        }
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

    private static func siteMarkerName(_ id: UUID) -> String {
        "site-" + id.uuidString.lowercased() + ".json"
    }

    private static func siteTemporaryName(_ id: UUID) -> String {
        ".site-" + id.uuidString.lowercased() + ".tmp"
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

    private static func siteMarkerIdentifier(_ name: String) -> UUID? {
        guard name.hasPrefix("site-"),
              name.hasSuffix(".json"),
              let identifier = UUID(
                uuidString: String(name.dropFirst(5).dropLast(5))
              ),
              siteMarkerName(identifier) == name else {
            return nil
        }
        return identifier
    }

    private static func siteTemporaryIdentifier(_ name: String) -> UUID? {
        guard name.hasPrefix(".site-"),
              name.hasSuffix(".tmp"),
              let identifier = UUID(
                uuidString: String(name.dropFirst(6).dropLast(4))
              ),
              siteTemporaryName(identifier) == name else {
            return nil
        }
        return identifier
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Deletion_WholeSignDeletionService {
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


// MARK: - C33 temporal evidence whole-sign deletion

enum TemporalEvidenceWholeSignDeletionBoundaryV1 {
    static let removesClipGraphAtomically = true
    static let rebuildsDerivedSearchAndReportViews = true
    static let neverUsesLegacyEvidenceFileAsClipIdentity = true

    static func validate(clip: TemporalEvidenceClipV1,
                         anchors: [TimecodedEvidenceAnchorV1],
                         derivatives: [TemporalEvidenceDerivativeV1]) throws {
        try clip.validateIntrinsic()
        try anchors.forEach { try $0.validate(clip: clip) }
        try TemporalEvidenceContentReferenceBoundaryV1.validate(
            clip: clip, derivatives: derivatives
        )
        guard removesClipGraphAtomically,
              rebuildsDerivedSearchAndReportViews,
              neverUsesLegacyEvidenceFileAsClipIdentity else {
            throw TemporalEvidenceContractFailureV1.invalidTransition
        }
    }
}

enum C45AcceptedLabelDeletionServiceBoundaryV1 { static let resolvesSnapshotLocatorReferences=true;static let removesDerivedOutputScratch=true }
