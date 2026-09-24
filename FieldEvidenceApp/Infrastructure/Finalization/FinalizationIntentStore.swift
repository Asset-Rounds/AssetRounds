import CryptoKit
import Darwin
import Foundation

struct PreparedFinalization: Equatable, Sendable {
    let intent: FinalizationIntentV1
    let intentRelativePath: String
    let snapshotStagingRelativePath: String
    let snapshotFinalRelativePath: String
    let snapshotByteCount: Int
    let snapshotSHA256: String
}

enum FinalizationIntentAccessibleDocumentDispositionV1{
    static let pendingTreeOnLaunch="DROP_AND_REBUILD"
    static let acceptedAssessment="RETAIN_IMMUTABLE_HISTORY"
}

struct PromotedFinalization: Equatable, Sendable {
    let intent: FinalizationIntentV1
    let intentRelativePath: String
    let snapshotStagingRelativePath: String
    let snapshotFinalRelativePath: String
    let snapshotByteCount: Int
    let snapshotSHA256: String
}

struct RecoverableFinalization: Equatable, Sendable {
    let intent: FinalizationIntentV1
    let intentRelativePath: String
    let snapshotStagingRelativePath: String
    let snapshotFinalRelativePath: String
    let snapshotByteCount: Int
    let snapshot: ReportSnapshotV1?
    let hasStagingSnapshot: Bool
    let hasFinalSnapshot: Bool
}

enum FinalizationIntentStoreError: Error, Equatable {
    case generationRootInvalid
    case unsafePath
    case intentInvalid
    case phaseInvalid
    case itemAlreadyExists
    case itemMissing
    case itemTypeInvalid
    case bytesMismatch
    case notOwned
    case fileOperationFailed
}

enum FinalizationIntentStoreFailurePoint: Equatable, Sendable {
    case snapshotStagingWrite
    case snapshotPromotionMove
    case intentPhaseWrite(FinalizationPhaseV1)
}

final class FinalizationIntentStoreFailureInjection: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingFailure: FinalizationIntentStoreFailurePoint?

    init(failOnceAt failurePoint: FinalizationIntentStoreFailurePoint) {
        pendingFailure = failurePoint
    }

    func removeFailure() {
        lock.lock()
        pendingFailure = nil
        lock.unlock()
    }

    fileprivate func consume(_ failurePoint: FinalizationIntentStoreFailurePoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingFailure == failurePoint else { return false }
        pendingFailure = nil
        return true
    }
}

// MARK: - C37 pose finalization boundary

enum C37PoseFinalizationPolicyV1 {
    static let snapshotMustBeFrozen = true
    static let historyIsAmendOnly = true
    static let currentTipIsCapturedAtFinalization = true
    static let rebasePreviewIsNotApplied = true
    static let noSensorInputAtFinalization = true
    static let noPrivateLocatorInput = true

    static func validate(
        _ snapshot: C37PlacementPoseFrozenSnapshotV1
    ) throws -> C37PlacementPoseFrozenSnapshotV1 {
        guard snapshotMustBeFrozen, historyIsAmendOnly,
              currentTipIsCapturedAtFinalization, rebasePreviewIsNotApplied,
              noSensorInputAtFinalization, noPrivateLocatorInput else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        do {
            try snapshot.validate()
            return snapshot
        } catch {
            throw FinalizationIntentStoreError.intentInvalid
        }
    }
}

extension FinalizationIntentStore {
    static func validatePlacementPoseSnapshot(
        _ snapshot: C37PlacementPoseFrozenSnapshotV1
    ) throws -> C37PlacementPoseFrozenSnapshotV1 {
        try C37PoseFinalizationPolicyV1.validate(snapshot)
    }
}

// MARK: - C23 field-reference finalization boundary

/// Finalization consumes the already-bound projection as a value.  It never
/// follows a newer active release and it never serializes reference bytes or
/// private locators into a finalized artifact.
enum FinalizationFieldReferenceProjectionPolicyV1 {
    static let historicBindingIsImmutable = true
    static let releaseReplacementIsSilent = false
    static let retainsDigestProvenanceOnly = true
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true

    static func validateForFinalization(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> FieldReferenceReportProjectionV1 {
        try projection.validate()
        guard historicBindingIsImmutable,
              releaseReplacementIsSilent == false,
              retainsDigestProvenanceOnly,
              excludesReferenceBytes,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity,
              projection.historicBindingImmutable,
              projection.restrictedContentOmitted else {
            throw FieldReferenceReportProjectionFailureV1.invalidValue
        }
        return projection
    }
}

// MARK: - C29 plan/rebase finalization boundary

/// Finalization carries an already-frozen plan projection as report metadata.
/// It never applies a preview, resolves a newer revision, or admits source
/// bytes/private locator bindings into the finalized snapshot.
enum FinalizationPlanProjectionPolicyV1 {
    static let historicDisplayIsFrozen = true
    static let previewIsNotApplied = true
    static let currentRevisionResolutionIsForbidden = true
    static let excludesSourceBytes = true
    static let excludesPrivateLocators = true
    static let excludesActorIdentity = true

    static func validate(_ snapshot: ReportSnapshotV1) throws {
        guard historicDisplayIsFrozen, previewIsNotApplied,
              currentRevisionResolutionIsForbidden, excludesSourceBytes,
              excludesPrivateLocators, excludesActorIdentity else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        guard let projection = snapshot.planProjection else { return }
        do {
            try PlanReportProjectionPolicyV1.validate(projection, format: .openJSON)
        } catch {
            throw FinalizationIntentStoreError.bytesMismatch
        }
    }
}

/// Test-only synchronization at a verified authority boundary. Production
/// callers leave this nil; it neither changes storage names nor product state.
final class FinalizationIntentStoreAuthorityBarrier: @unchecked Sendable {
    enum Boundary: Equatable, Sendable {
        case authorityVerified
        case beforeLeafMutation
        case afterLeafMutation
    }

    private let handler: @Sendable (Boundary) -> Void

    init(_ handler: @escaping @Sendable (Boundary) -> Void) {
        self.handler = handler
    }

    fileprivate func reach(_ boundary: Boundary) {
        handler(boundary)
    }
}

actor FinalizationIntentStore {
    private let sourceMutationGuard: StoreMigrationSourceMutationGuardV1?
    private let authorityResult: Result<PinnedAuthority, FinalizationIntentStoreError>
    private let failureInjection: FinalizationIntentStoreFailureInjection?
    private let authorityBarrier: FinalizationIntentStoreAuthorityBarrier?
    private var liveMutationInFlight = false
    private var livePrivatePreparations: [LivePrivatePreparation] = []

    private final class MutationProgress {
        var didMutateLeaf = false
    }

    init(
        generationRootURL: URL,
        fileManager: FileManager = .default,
        failureInjection: FinalizationIntentStoreFailureInjection? = nil,
        expectedGenerationRootIdentity: ReportPDFAnchoredFile.RootIdentity? = nil,
        authorityBarrier: FinalizationIntentStoreAuthorityBarrier? = nil
    ) {
        let root = generationRootURL.standardizedFileURL
        self.failureInjection = failureInjection
        self.authorityBarrier = authorityBarrier
        self.sourceMutationGuard = nil
        _ = fileManager // Kept only for source compatibility; never storage authority.
        do {
            let open = {
                try PinnedAuthority(
                    generationRootURL: root,
                    expectedGenerationRootIdentity: expectedGenerationRootIdentity
                )
            }
            let authority = try open()
            authorityResult = .success(authority)
        } catch let error as FinalizationIntentStoreError {
            authorityResult = .failure(error)
        } catch {
            authorityResult = .failure(.generationRootInvalid)
        }
    }

    @MainActor
    init(sourceRecoveryAuthority authority: StoreMigrationSourceRecoveryAuthorityV1) throws {
        let guardValue = try authority.recoveryMutationGuard()
        let root = authority.generationRootURL.standardizedFileURL
        let pinned = try guardValue.withAuthorizedMutation {
            try PinnedAuthority(generationRootURL: root,
                                expectedGenerationRootIdentity: ReportPDFAnchoredFile.rootIdentity(at: root))
        }
        self.sourceMutationGuard = guardValue
        self.authorityResult = .success(pinned)
        self.failureInjection = nil
        self.authorityBarrier = nil
    }

    func discoverRecoverableFinalizations() throws -> [RecoverableFinalization] {
        try withSourceMutationAuthority { try discoverRecoverableFinalizationsUnprotected() }
    }

    private func withSourceMutationAuthority<T>(_ operation: () throws -> T) throws -> T {
        if let sourceMutationGuard {
            return try sourceMutationGuard.withAuthorizedMutation(operation)
        }
        return try operation()
    }

    private func discoverRecoverableFinalizationsUnprotected() throws -> [RecoverableFinalization] {
        let authority = try requireAuthority()
        return try authority.enumeratedIntentNames().map { name in
            guard name.count == 41, name.hasSuffix(".json"),
                  let mutationID = UUID(uuidString: String(name.dropLast(5))),
                  mutationID.uuidString.lowercased() + ".json" == name else {
                throw FinalizationIntentStoreError.intentInvalid
            }
            try authority.verifyRegularFilePolicy(
                .journal,
                parent: authority.finalizationDescriptor,
                name: name,
                policyURL: try authority.finalizationFileURL(name: name)
            )
            let data = try authority.readRegularFile(
                parent: authority.finalizationDescriptor,
                name: name
            ).data
            let intent: FinalizationIntentV1
            do {
                intent = try FinalizationContractDecoderV1().decodeIntent(data)
            } catch {
                throw FinalizationIntentStoreError.intentInvalid
            }
            guard intent.finalizationMutationID == mutationID,
                  intent.generationID == authority.generationID,
                  [1, 2].contains(intent.schemaVersion) else {
                throw FinalizationIntentStoreError.intentInvalid
            }
            let paths = try validatedPaths(for: intent)
            let staging = try validatedSnapshotIfPresent(
                components: paths.stagingComponents,
                intent: intent,
                authority: authority
            )
            let final = try validatedSnapshotIfPresent(
                components: paths.finalComponents,
                intent: intent,
                authority: authority
            )
            if let staging, let final, staging.data != final.data {
                throw FinalizationIntentStoreError.bytesMismatch
            }
            return RecoverableFinalization(
                intent: intent,
                intentRelativePath: paths.intentRelativePath,
                snapshotStagingRelativePath: intent.snapshotStagingRelativePath,
                snapshotFinalRelativePath: intent.snapshotFinalRelativePath,
                snapshotByteCount: (final ?? staging)?.data.count ?? 0,
                snapshot: (final ?? staging)?.snapshot,
                hasStagingSnapshot: staging != nil,
                hasFinalSnapshot: final != nil
            )
        }
    }

    func promoteForRecovery(_ recovery: RecoverableFinalization) throws -> RecoverableFinalization {
        try withSourceMutationAuthority { try promoteForRecoveryUnprotected(recovery) }
    }

    private func promoteForRecoveryUnprotected(_ recovery: RecoverableFinalization) throws -> RecoverableFinalization {
        guard recovery.intent.phase == .prepared,
              recovery.hasStagingSnapshot,
              !recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let promoted = try promoteSnapshotUnprotected(
            PreparedFinalization(
                intent: recovery.intent,
                intentRelativePath: recovery.intentRelativePath,
                snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
                snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
                snapshotByteCount: recovery.snapshotByteCount,
                snapshotSHA256: recovery.intent.snapshotSHA256
            )
        )
        return RecoverableFinalization(
            intent: promoted.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshot: recovery.snapshot,
            hasStagingSnapshot: false,
            hasFinalSnapshot: true
        )
    }

    func removeIdenticalStagingForRecovery(
        _ recovery: RecoverableFinalization
    ) throws -> RecoverableFinalization {
        try withSourceMutationAuthority { try removeIdenticalStagingForRecoveryUnprotected(recovery) }
    }

    private func removeIdenticalStagingForRecoveryUnprotected(
        _ recovery: RecoverableFinalization
    ) throws -> RecoverableFinalization {
        guard recovery.hasStagingSnapshot, recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        let authority = try requireAuthority()
        let paths = try validatedPaths(for: recovery.intent)
        try verifyRecovery(recovery, paths: paths, authority: authority)
        try removeOwnedFileIfMatching(
            components: paths.stagingComponents,
            expectedByteCount: recovery.snapshotByteCount,
            expectedSHA256: recovery.intent.snapshotSHA256,
            authority: authority
        )
        return RecoverableFinalization(
            intent: recovery.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshot: recovery.snapshot,
            hasStagingSnapshot: false,
            hasFinalSnapshot: true
        )
    }

    func advanceForRecovery(
        _ recovery: RecoverableFinalization,
        to phase: FinalizationPhaseV1
    ) throws -> RecoverableFinalization {
        try withSourceMutationAuthority { try advanceForRecoveryUnprotected(recovery, to: phase) }
    }

    private func advanceForRecoveryUnprotected(
        _ recovery: RecoverableFinalization, to phase: FinalizationPhaseV1
    ) throws -> RecoverableFinalization {
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        let advanced = try advanceUnprotected(
            PromotedFinalization(
                intent: recovery.intent,
                intentRelativePath: recovery.intentRelativePath,
                snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
                snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
                snapshotByteCount: recovery.snapshotByteCount,
                snapshotSHA256: recovery.intent.snapshotSHA256
            ),
            to: phase
        )
        return RecoverableFinalization(
            intent: advanced.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshot: recovery.snapshot,
            hasStagingSnapshot: recovery.hasStagingSnapshot,
            hasFinalSnapshot: true
        )
    }

    func abandonPreparedWithoutSnapshots(_ recovery: RecoverableFinalization) throws {
        try withSourceMutationAuthority { try abandonPreparedWithoutSnapshotsUnprotected(recovery) }
    }

    private func abandonPreparedWithoutSnapshotsUnprotected(_ recovery: RecoverableFinalization) throws {
        guard recovery.intent.phase == .prepared,
              !recovery.hasStagingSnapshot,
              !recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let authority = try requireAuthority()
        let paths = try validatedPaths(for: recovery.intent)
        try verifyIntent(recovery.intent, name: paths.intentName, authority: authority)
        try removeIntentIfMatching(recovery.intent, name: paths.intentName, authority: authority)
    }

    func rollbackForRecovery(_ recovery: RecoverableFinalization) throws {
        try withSourceMutationAuthority { try rollbackForRecoveryUnprotected(recovery) }
    }

    private func rollbackForRecoveryUnprotected(_ recovery: RecoverableFinalization) throws {
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        try rollbackUncommittedUnprotected(
            PromotedFinalization(
                intent: recovery.intent,
                intentRelativePath: recovery.intentRelativePath,
                snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
                snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
                snapshotByteCount: recovery.snapshotByteCount,
                snapshotSHA256: recovery.intent.snapshotSHA256
            )
        )
    }

    func cleanupCommittedForRecovery(_ recovery: RecoverableFinalization) throws {
        try withSourceMutationAuthority { try cleanupCommittedForRecoveryUnprotected(recovery) }
    }

    private func cleanupCommittedForRecoveryUnprotected(_ recovery: RecoverableFinalization) throws {
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        try cleanupCommittedUnprotected(
            PromotedFinalization(
                intent: recovery.intent,
                intentRelativePath: recovery.intentRelativePath,
                snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
                snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
                snapshotByteCount: recovery.snapshotByteCount,
                snapshotSHA256: recovery.intent.snapshotSHA256
            )
        )
    }

    /// The live path reserves the actor across its MainActor publication hop.
    /// Legacy/recovery entries fail closed until that operation returns.
    final class StartupPrivateRetirement: @unchecked Sendable {
        private let authority: StartupPrivatePreparationAuthorityV1
        private let body: @MainActor () throws -> Void
        private let consumption = NSLock()
        private var consumed = false

        fileprivate init(authority: StartupPrivatePreparationAuthorityV1,
            body: @escaping @MainActor () throws -> Void) {
            self.authority = authority; self.body = body
        }

        @MainActor
        func finish(authority expected: StartupPrivatePreparationAuthorityV1) throws {
            guard authority === expected, consumption.try() else { throw FinalizationIntentStoreError.notOwned }
            defer { consumption.unlock() }
            guard !consumed else { throw FinalizationIntentStoreError.notOwned }
            consumed = true
            try authority.revalidateCleanup()
            try body()
        }
    }

    /// Startup alone supplies the unpublished writer capability. Generic
    /// finalization discovery/reconciliation never invokes this disposal route.
    func prepareStartupPrivateRetirement(authority startup: StartupPrivatePreparationAuthorityV1) async throws
        -> StartupPrivateRetirement {
        try await withLiveMutation {
            let binding = try await startup.validatePreparation()
            let authority = try requireAuthority(allowLiveMutation: true)
            guard binding.root.standardizedFileURL == authority.liveGenerationRootURL,
                  try ReportPDFAnchoredFile.rootIdentity(at: binding.root) == binding.identity else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            try authority.verify()
            var leaves: [StartupPrivateLeaf] = []
            for atRoot in [false, true] {
                let parent = atRoot ? authority.generationDescriptor : authority.stagingSnapshotsDescriptor
                let prefix = atRoot ? ".immutable-" : ".live-finalization-"
                for name in try LivePrivatePreparation.names(in: parent) where name.hasPrefix(prefix) {
                    try Task.checkCancellation()
                    guard LivePrivatePreparation.isReservedName(name, prefix: prefix),
                          let info = try authority.itemInfo(parent: parent, name: name),
                          PinnedAuthority.isRegular(info), info.st_nlink == 1 else {
                        throw FinalizationIntentStoreError.itemTypeInvalid
                    }
                    let components = atRoot ? [name] : [".staging", "snapshots", name]
                    let url = try authority.generationFileURL(components: components)
                    var policy: OwnedFileKindV1 = atRoot ? .temporaryFile : .stagingFile
                    if !atRoot {
                        do { try authority.verifyRegularFilePolicy(policy, parent: parent, name: name, policyURL: url) }
                        catch {
                            // Rollback may have moved an immutable final snapshot
                            // to a private name before the process stopped.
                            policy = .reportSnapshot
                            try authority.verifyRegularFilePolicy(policy, parent: parent, name: name, policyURL: url)
                        }
                    }
                    leaves.append(try StartupPrivateLeaf(authority: authority, parent: parent,
                        name: name, url: url, policy: policy, facts: info))
                }
            }
            let retained = leaves
            return StartupPrivateRetirement(authority: startup) {
                try startup.revalidateCleanup()
                for leaf in retained { try leaf.verifyNamed() }
                for leaf in retained {
                    try startup.revalidateCleanup()
                    try Self.retirePreparedStartupPrivateLeaf(leaf, authority: startup)
                }
            }
        }
    }

    @MainActor
    private static func retirePreparedStartupPrivateLeaf(_ leaf: StartupPrivateLeaf,
        authority startup: StartupPrivatePreparationAuthorityV1) throws {
        let prefix = leaf.parent == leaf.authority.generationDescriptor ? ".immutable-" : ".live-finalization-"
        guard LivePrivatePreparation.isReservedName(leaf.name, prefix: prefix) else {
            throw FinalizationIntentStoreError.notOwned
        }
        try Task.checkCancellation()
        try leaf.withPinnedDescriptor { descriptor in
            try startup.revalidateCleanup()
            let quarantine = "\(prefix)\(UUID().uuidString.lowercased()).tmp"
            guard Darwin.renameatx_np(leaf.parent, leaf.name, leaf.parent, quarantine, UInt32(RENAME_EXCL)) == 0 else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            do {
                var moved = stat()
                guard Darwin.fstat(descriptor, &moved) == 0 else { throw FinalizationIntentStoreError.fileOperationFailed }
                try leaf.verify(descriptor: descriptor, name: quarantine, expectedChangeTime: moved.st_ctimespec)
                try startup.revalidateCleanup()
                guard Darwin.unlinkat(leaf.parent, quarantine, 0) == 0, Darwin.fsync(leaf.parent) == 0 else {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
            } catch {
                _ = Darwin.renameatx_np(leaf.parent, quarantine, leaf.parent, leaf.name, UInt32(RENAME_EXCL))
                _ = Darwin.fsync(leaf.parent)
                throw error
            }
        }
    }

    /// Startup discards private preparation regardless of its payload. Retain
    /// only metadata across the access hop, not unbounded Data or one FD per file.
    /// Canonical/live publication continues to use its byte-verified leaf below.
    private final class StartupPrivateLeaf: @unchecked Sendable {
        let authority: PinnedAuthority
        let parent: Int32
        let name: String
        let url: URL
        let policy: OwnedFileKindV1
        let facts: stat

        init(authority: PinnedAuthority, parent: Int32, name: String, url: URL,
             policy: OwnedFileKindV1, facts: stat) throws {
            self.authority = authority; self.parent = parent; self.name = name
            self.url = url; self.policy = policy; self.facts = facts
            try verifyNamed()
        }

        func verifyNamed() throws { try withPinnedDescriptor { _ in } }

        func withPinnedDescriptor<T>(_ body: (Int32) throws -> T) throws -> T {
            try Task.checkCancellation()
            try authority.verify()
            let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
            guard descriptor >= 0 else { throw FinalizationIntentStoreError.itemMissing }
            defer { _ = Darwin.close(descriptor) }
            try verify(descriptor: descriptor, name: name)
            return try body(descriptor)
        }

        func verify(descriptor: Int32, name: String, expectedChangeTime: timespec? = nil) throws {
            try authority.verify()
            var opened = stat(), named = stat()
            guard Darwin.fstat(descriptor, &opened) == 0,
                  Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw FinalizationIntentStoreError.notOwned
            }
            let changeTime = expectedChangeTime ?? facts.st_ctimespec
            for observed in [opened, named] {
                guard PinnedAuthority.isRegular(observed), observed.st_nlink == 1,
                      observed.st_dev == facts.st_dev, observed.st_ino == facts.st_ino,
                      observed.st_size == facts.st_size,
                      observed.st_mtimespec.tv_sec == facts.st_mtimespec.tv_sec,
                      observed.st_mtimespec.tv_nsec == facts.st_mtimespec.tv_nsec,
                      observed.st_ctimespec.tv_sec == changeTime.tv_sec,
                      observed.st_ctimespec.tv_nsec == changeTime.tv_nsec else {
                    throw FinalizationIntentStoreError.notOwned
                }
            }
            try authority.verifyRegularFilePolicy(policy, parent: parent, name: name,
                policyURL: url.deletingLastPathComponent().appendingPathComponent(name))
        }
    }

    func prepareLive(intent: FinalizationIntentV1, snapshot: EncodedReportSnapshotV1,
        authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) async throws
        -> PreparedFinalization {
        return try await withLiveMutation {
            let authority = try requireAuthority(allowLiveMutation: true)
            try await Self.validateLiveGeneration(authority, operation: operation)
            let paths = try validatedPaths(for: intent)
            guard intent.generationID == authority.generationID, intent.phase == .prepared,
                  [1, 2].contains(intent.schemaVersion), intent.snapshotSHA256 == snapshot.sha256,
                  sha256(snapshot.data) == snapshot.sha256 else { throw FinalizationIntentStoreError.intentInvalid }
            guard case nil = try authority.itemInfo(parent: authority.finalizationDescriptor, name: paths.intentName),
                  case nil = try itemInfo(components: paths.stagingComponents, authority: authority),
                  case nil = try itemInfo(components: paths.finalComponents, authority: authority) else {
                throw FinalizationIntentStoreError.itemAlreadyExists
            }
            guard failureInjection?.consume(.snapshotStagingWrite) != true,
                  failureInjection?.consume(.intentPhaseWrite(.prepared)) != true else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            let snapshotLeaf = try preparePrivateLiveLeaf(snapshot.data, policy: .stagingFile, authority: authority)
            let intentLeaf = try preparePrivateLiveLeaf(encodedIntent(intent).data, policy: .journal, authority: authority)
            let intentMove = try LivePreparedMove(source: intentLeaf, destinationParent: authority.finalizationDescriptor,
                destinationName: paths.intentName, destinationURL: authority.finalizationFileURL(name: paths.intentName),
                destinationPolicy: .journal, operation: operation, barrier: authorityBarrier)
            let snapshotMove = try LivePreparedMove(source: snapshotLeaf, destinationParent: authority.stagingSnapshotsDescriptor,
                destinationName: paths.stagingComponents.last!,
                destinationURL: authority.generationFileURL(components: paths.stagingComponents),
                destinationPolicy: .stagingFile, operation: operation, barrier: authorityBarrier)
            // Publishing the journal first leaves a recognized prepared intent if
            // snapshot publication fails. Recovery already handles a missing snapshot.
            try await Self.publishLivePreparation(intent: intentMove, snapshot: snapshotMove, operation: operation)
            let prepared = PreparedFinalization(intent: intent, intentRelativePath: paths.intentRelativePath,
                snapshotStagingRelativePath: intent.snapshotStagingRelativePath,
                snapshotFinalRelativePath: intent.snapshotFinalRelativePath,
                snapshotByteCount: snapshot.data.count, snapshotSHA256: snapshot.sha256)
            try verifyHandle(prepared, paths: paths, authority: authority)
            return prepared
        }
    }

    @MainActor
    private static func validateLiveGeneration(_ authority: PinnedAuthority,
        operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
        try operation.withFinalizationAuthorization(generationID: authority.generationID,
            generationRootURL: authority.liveGenerationRootURL) { try authority.verify() }
    }

    @MainActor
    private static func publishLivePreparation(intent: LivePreparedMove, snapshot: LivePreparedMove,
        operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
#if DEBUG
        try operation.beforeFinalizationPreparationPublicationForTesting?()
#endif
        try operation.withAuthorization {
            try intent.perform(authorizing: operation)
            try intent.verifyPublished()
            try snapshot.perform(authorizing: operation)
            try intent.verifyPublished()
            try snapshot.verifyPublished()
        }
    }

    func promoteSnapshotLive(_ prepared: PreparedFinalization,
        authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) async throws
        -> PromotedFinalization {
        return try await withLiveMutation {
            let authority = try requireAuthority(allowLiveMutation: true)
            try await Self.validateLiveGeneration(authority, operation: operation)
            let paths = try validatedPaths(for: prepared.intent)
            try verifyHandle(prepared, paths: paths, authority: authority)
            guard prepared.intent.phase == .prepared else { throw FinalizationIntentStoreError.phaseInvalid }
            guard failureInjection?.consume(.snapshotPromotionMove) != true else {
                // The valid prepared journal remains recoverable. No unguarded
                // catch-path deletion is permitted on a live operation.
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            let encoded = try encodedIntent(prepared.intent)
            let intentLeaf = try LivePreparedLeaf(authority: authority, parent: authority.finalizationDescriptor,
                name: paths.intentName, url: authority.finalizationFileURL(name: paths.intentName),
                policy: .journal, expectedCount: encoded.data.count, expectedSHA256: sha256(encoded.data),
                expectedData: encoded.data)
            let snapshotLeaf = try LivePreparedLeaf(authority: authority, parent: authority.stagingSnapshotsDescriptor,
                name: paths.stagingComponents.last!, url: authority.generationFileURL(components: paths.stagingComponents),
                policy: .stagingFile, expectedCount: prepared.snapshotByteCount, expectedSHA256: prepared.snapshotSHA256)
            let move = try LivePreparedMove(source: snapshotLeaf, destinationParent: authority.snapshotsDescriptor,
                destinationName: paths.finalComponents.last!, destinationURL: authority.generationFileURL(components: paths.finalComponents),
                destinationPolicy: .reportSnapshot, operation: operation, barrier: authorityBarrier,
                dependencies: [intentLeaf])
            try await move.perform(authorizing: operation)
            let promoted = PromotedFinalization(intent: prepared.intent, intentRelativePath: prepared.intentRelativePath,
                snapshotStagingRelativePath: prepared.snapshotStagingRelativePath,
                snapshotFinalRelativePath: prepared.snapshotFinalRelativePath,
                snapshotByteCount: prepared.snapshotByteCount, snapshotSHA256: prepared.snapshotSHA256)
            try verifyPromotedHandle(promoted, paths: paths, authority: authority)
            return promoted
        }
    }

    func advanceLive(_ promoted: PromotedFinalization, to phase: FinalizationPhaseV1,
        authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) async throws
        -> PromotedFinalization {
        return try await withLiveMutation {
            let authority = try requireAuthority(allowLiveMutation: true)
            try await Self.validateLiveGeneration(authority, operation: operation)
            let paths = try validatedPaths(for: promoted.intent)
            try verifyPromotedHandle(promoted, paths: paths, authority: authority)
            let expectedPhase: FinalizationPhaseV1
            switch promoted.intent.phase {
            case .prepared: expectedPhase = .snapshotPromoted
            case .snapshotPromoted: expectedPhase = .databaseCommitted
            case .databaseCommitted: throw FinalizationIntentStoreError.phaseInvalid
            }
            guard phase == expectedPhase else { throw FinalizationIntentStoreError.phaseInvalid }
            guard failureInjection?.consume(.intentPhaseWrite(phase)) != true else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            return try await replaceLivePhase(promoted, to: phase, paths: paths, authority: authority,
                operation: operation)
        }
    }

    private func replaceLivePhase(_ promoted: PromotedFinalization, to phase: FinalizationPhaseV1,
        paths: Paths, authority: PinnedAuthority,
        operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess,
        rollbackMutationID: UUID? = nil) async throws -> PromotedFinalization {
        let advanced = promoted.intent.withPhase(phase)
        let old = try encodedIntent(promoted.intent), new = try encodedIntent(advanced)
        let journal = try LivePreparedLeaf(authority: authority, parent: authority.finalizationDescriptor,
            name: paths.intentName, url: authority.finalizationFileURL(name: paths.intentName),
            policy: .journal, expectedCount: old.data.count, expectedSHA256: sha256(old.data), expectedData: old.data)
        let snapshot = try LivePreparedLeaf(authority: authority, parent: authority.snapshotsDescriptor,
            name: paths.finalComponents.last!, url: authority.generationFileURL(components: paths.finalComponents),
            policy: .reportSnapshot, expectedCount: promoted.snapshotByteCount, expectedSHA256: promoted.snapshotSHA256)
        let candidate = try preparePrivateLiveLeaf(new.data, policy: .journal, authority: authority)
        livePrivatePreparations.append(.init(authority: authority, name: candidate.name,
            identity: .init(device: journal.facts.st_dev, inode: journal.facts.st_ino),
            data: journal.verifiedData, policy: .journal))
        let replacement = try LivePreparedReplacement(original: journal, candidate: candidate,
            dependencies: [snapshot], operation: operation, barrier: authorityBarrier,
            rollbackMutationID: rollbackMutationID)
        try await replacement.perform(authorizing: operation)
        let result = PromotedFinalization(intent: advanced, intentRelativePath: promoted.intentRelativePath,
            snapshotStagingRelativePath: promoted.snapshotStagingRelativePath,
            snapshotFinalRelativePath: promoted.snapshotFinalRelativePath,
            snapshotByteCount: promoted.snapshotByteCount, snapshotSHA256: promoted.snapshotSHA256)
        try verifyPromotedHandle(result, paths: paths, authority: authority)
        return result
    }

    func cleanupCommittedLive(_ committed: PromotedFinalization,
        authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) async throws {
        return try await withLiveMutation {
            guard committed.intent.phase == .databaseCommitted,
                  let binding = committed.intent.writerCommitBinding else { throw FinalizationIntentStoreError.phaseInvalid }
            let authority = try requireAuthority(allowLiveMutation: true)
            try await Self.validateLiveGeneration(authority, operation: operation)
            let paths = try validatedPaths(for: committed.intent)
            try verifyPromotedHandle(committed, paths: paths, authority: authority)
            let journal = try pinLiveJournal(committed.intent, paths: paths, authority: authority)
            guard let snapshot = try pinLiveSnapshotIfPresent(committed, staged: false, paths: paths, authority: authority) else {
                throw FinalizationIntentStoreError.notOwned
            }
            var removals: [LivePreparedRemoval] = []
            var absences: [LivePreparedAbsence] = []
            if let staged = try pinLiveSnapshotIfPresent(committed, staged: true, paths: paths, authority: authority) {
                removals.append(makeLiveRemoval(source: staged, dependencies: [journal, snapshot], operation: operation,
                    mutationID: committed.intent.finalizationMutationID, committedBinding: binding, barrier: authorityBarrier))
            } else {
                absences.append(.init(authority: authority, parent: authority.stagingSnapshotsDescriptor,
                    name: paths.stagingComponents.last!))
            }
            removals.append(makeLiveRemoval(source: journal, dependencies: [snapshot], operation: operation,
                mutationID: committed.intent.finalizationMutationID, committedBinding: binding, barrier: authorityBarrier))
            try await Self.performLiveRemovals(removals, initialAbsences: absences, operation: operation)
            // The immutable final snapshot is never included in committed cleanup.
            try verifyRegularFile(components: paths.finalComponents, expectedByteCount: committed.snapshotByteCount,
                expectedSHA256: committed.snapshotSHA256, authority: authority)
        }
    }

    func rollbackUncommittedLive(_ promoted: PromotedFinalization,
        authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) async throws {
        return try await withLiveMutation {
            guard promoted.intent.phase != .databaseCommitted else { throw FinalizationIntentStoreError.phaseInvalid }
            let authority = try requireAuthority(allowLiveMutation: true)
            try await Self.validateLiveGeneration(authority, operation: operation)
            let paths = try validatedPaths(for: promoted.intent)
            try verifyPromotedHandle(promoted, paths: paths, authority: authority)
            var rollback = promoted
            if promoted.intent.phase == .snapshotPromoted {
                // Existing recovery can abandon a prepared intent with no snapshots.
                // Restore that phase before any deletions, so interrupted rollback
                // does not leave a snapshot-promoted journal naming missing bytes.
                rollback = try await replaceLivePhase(promoted, to: .prepared, paths: paths, authority: authority,
                    operation: operation, rollbackMutationID: promoted.intent.finalizationMutationID)
            }
            let journal = try pinLiveJournal(rollback.intent, paths: paths, authority: authority)
            var removals: [LivePreparedRemoval] = []
            var absences: [LivePreparedAbsence] = []
            for staged in [false, true] {
                if let leaf = try pinLiveSnapshotIfPresent(rollback, staged: staged, paths: paths, authority: authority) {
                    removals.append(makeLiveRemoval(source: leaf, dependencies: [journal], operation: operation,
                        mutationID: rollback.intent.finalizationMutationID, committedBinding: nil, barrier: authorityBarrier))
                } else {
                    absences.append(.init(authority: authority,
                        parent: staged ? authority.stagingSnapshotsDescriptor : authority.snapshotsDescriptor,
                        name: (staged ? paths.stagingComponents : paths.finalComponents).last!))
                }
            }
            removals.append(makeLiveRemoval(source: journal, dependencies: [], operation: operation,
                mutationID: rollback.intent.finalizationMutationID, committedBinding: nil, barrier: authorityBarrier))
            try await Self.performLiveRemovals(removals, initialAbsences: absences, operation: operation)
        }
    }

    private func makeLiveRemoval(source: LivePreparedLeaf, dependencies: [LivePreparedLeaf],
        operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess, mutationID: UUID,
        committedBinding: FinalizationWriterCommitBindingV1?, barrier: FinalizationIntentStoreAuthorityBarrier?)
        -> LivePreparedRemoval {
        let name = ".live-finalization-\(UUID().uuidString.lowercased()).tmp"
        livePrivatePreparations.append(.init(authority: source.authority, name: name,
            identity: .init(device: source.facts.st_dev, inode: source.facts.st_ino),
            data: source.verifiedData, policy: source.policy))
        return .init(source: source, dependencies: dependencies, operation: operation,
            mutationID: mutationID, committedBinding: committedBinding, barrier: barrier, privateName: name)
    }

    private func pinLiveJournal(_ intent: FinalizationIntentV1, paths: Paths,
        authority: PinnedAuthority) throws -> LivePreparedLeaf {
        let encoded = try encodedIntent(intent)
        return try LivePreparedLeaf(authority: authority, parent: authority.finalizationDescriptor,
            name: paths.intentName, url: authority.finalizationFileURL(name: paths.intentName),
            policy: .journal, expectedCount: encoded.data.count, expectedSHA256: sha256(encoded.data),
            expectedData: encoded.data)
    }

    private func pinLiveSnapshotIfPresent(_ promoted: PromotedFinalization, staged: Bool,
        paths: Paths, authority: PinnedAuthority) throws -> LivePreparedLeaf? {
        let components = staged ? paths.stagingComponents : paths.finalComponents
        let parent = staged ? authority.stagingSnapshotsDescriptor : authority.snapshotsDescriptor
        if case nil = try authority.itemInfo(parent: parent, name: components.last!) { return nil }
        return try LivePreparedLeaf(authority: authority, parent: parent, name: components.last!,
            url: authority.generationFileURL(components: components), policy: staged ? .stagingFile : .reportSnapshot,
            expectedCount: promoted.snapshotByteCount, expectedSHA256: promoted.snapshotSHA256)
    }

    @MainActor
    private static func performLiveRemovals(_ removals: [LivePreparedRemoval],
        initialAbsences: [LivePreparedAbsence],
        operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
        try operation.withAuthorization {
            var absences = initialAbsences
            for removal in removals {
                try removal.perform(authorizing: operation, expectedAbsences: absences)
                absences.append(removal.sourceAbsence)
            }
            for absence in absences { try absence.verify() }
        }
    }

    func prepare(
        intent: FinalizationIntentV1,
        snapshot: EncodedReportSnapshotV1
    ) throws -> PreparedFinalization {
        try requireProducerAuthority()
        let authority = try requireAuthority()
        guard intent.generationID == authority.generationID else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        let paths = try validatedPaths(for: intent)
        guard intent.phase == .prepared,
              [1, 2].contains(intent.schemaVersion),
              intent.snapshotSHA256 == snapshot.sha256,
              sha256(snapshot.data) == snapshot.sha256 else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        guard case nil = try authority.itemInfo(
            parent: authority.finalizationDescriptor,
            name: paths.intentName
        ), case nil = try itemInfo(
            components: paths.stagingComponents,
            authority: authority
        ), case nil = try itemInfo(
            components: paths.finalComponents,
            authority: authority
        ) else {
            throw FinalizationIntentStoreError.itemAlreadyExists
        }
        try authority.ensureGenerationDirectory(components: [".staging", "snapshots"])

#if DEBUG
        var preparationPhase = "snapshot-staging-write"
#endif
        do {
            guard failureInjection?.consume(.snapshotStagingWrite) != true else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            try createRegularFile(
                snapshot.data,
                components: paths.stagingComponents,
                authority: authority
            )
#if DEBUG
            preparationPhase = "verify-staging-snapshot"
#endif
            try verifyRegularFile(
                components: paths.stagingComponents,
                expectedData: snapshot.data,
                expectedSHA256: snapshot.sha256,
                authority: authority
            )
#if DEBUG
            preparationPhase = "create-and-verify-intent"
#endif
            try createAndVerifyIntent(intent, name: paths.intentName, authority: authority)
#if DEBUG
            preparationPhase = "verify-authority-after-prepare"
#endif
            try authority.verify()
        } catch {
#if DEBUG
            finalizationJournalDiagnosticFailureV1(
                component: "intent-store", phase: preparationPhase, error: error
            )
#endif
            var cleanupFailed = false
            do {
                try removeOwnedFileIfMatching(
                    components: paths.stagingComponents,
                    expectedByteCount: snapshot.data.count,
                    expectedSHA256: snapshot.sha256,
                    authority: authority,
                    requireCurrentAuthority: false
                )
            } catch {
                cleanupFailed = true
            }
            do {
                try removeIntentIfMatching(
                    intent,
                    name: paths.intentName,
                    authority: authority,
                    requireCurrentAuthority: false
                )
            } catch {
                cleanupFailed = true
            }
            if cleanupFailed {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            throw mapped(error)
        }

        return PreparedFinalization(
            intent: intent,
            intentRelativePath: paths.intentRelativePath,
            snapshotStagingRelativePath: intent.snapshotStagingRelativePath,
            snapshotFinalRelativePath: intent.snapshotFinalRelativePath,
            snapshotByteCount: snapshot.data.count,
            snapshotSHA256: snapshot.sha256
        )
    }

    func promoteSnapshot(_ prepared: PreparedFinalization) throws -> PromotedFinalization {
        try requireProducerAuthority()
        return try promoteSnapshotUnprotected(prepared)
    }

    private func promoteSnapshotUnprotected(_ prepared: PreparedFinalization) throws -> PromotedFinalization {
        let authority = try requireAuthority()
        let paths = try validatedPaths(for: prepared.intent)
        try verifyHandle(prepared, paths: paths, authority: authority)
        guard prepared.intent.phase == .prepared else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        guard case nil = try itemInfo(
            components: paths.finalComponents,
            authority: authority
        ) else {
            throw FinalizationIntentStoreError.itemAlreadyExists
        }
        try authority.ensureGenerationDirectory(components: ["snapshots"])

        if failureInjection?.consume(.snapshotPromotionMove) == true {
            try removeOwnedFileIfMatching(
                components: paths.stagingComponents,
                expectedByteCount: prepared.snapshotByteCount,
                expectedSHA256: prepared.snapshotSHA256,
                authority: authority
            )
            try removeIntentIfMatching(
                prepared.intent,
                name: paths.intentName,
                authority: authority
            )
            throw FinalizationIntentStoreError.fileOperationFailed
        }

        do {
            try beforeLeafMutation(authority)
            try authority.promoteNoReplace(
                sourceComponents: paths.stagingComponents,
                destinationComponents: paths.finalComponents,
                expectedByteCount: prepared.snapshotByteCount,
                expectedSHA256: prepared.snapshotSHA256,
                policyURL: try authority.generationFileURL(
                    components: paths.finalComponents
                ),
                afterMutation: { [authorityBarrier] in
                    authorityBarrier?.reach(.afterLeafMutation)
                }
            )
            try authority.verify()
        } catch {
            var cleanupFailed = false
            do {
                try removeOwnedFileIfMatching(
                    components: paths.finalComponents,
                    expectedByteCount: prepared.snapshotByteCount,
                    expectedSHA256: prepared.snapshotSHA256,
                    authority: authority,
                    requireCurrentAuthority: false
                )
            } catch {
                cleanupFailed = true
            }
            do {
                try removeOwnedFileIfMatching(
                    components: paths.stagingComponents,
                    expectedByteCount: prepared.snapshotByteCount,
                    expectedSHA256: prepared.snapshotSHA256,
                    authority: authority,
                    requireCurrentAuthority: false
                )
            } catch {
                cleanupFailed = true
            }
            do {
                try removeIntentIfMatching(
                    prepared.intent,
                    name: paths.intentName,
                    authority: authority,
                    requireCurrentAuthority: false
                )
            } catch {
                cleanupFailed = true
            }
            if cleanupFailed {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            throw mapped(error)
        }

        return PromotedFinalization(
            intent: prepared.intent,
            intentRelativePath: prepared.intentRelativePath,
            snapshotStagingRelativePath: prepared.snapshotStagingRelativePath,
            snapshotFinalRelativePath: prepared.snapshotFinalRelativePath,
            snapshotByteCount: prepared.snapshotByteCount,
            snapshotSHA256: prepared.snapshotSHA256
        )
    }

    func advance(
        _ promoted: PromotedFinalization,
        to phase: FinalizationPhaseV1
    ) throws -> PromotedFinalization {
        try requireProducerAuthority()
        return try advanceUnprotected(promoted, to: phase)
    }

    private func advanceUnprotected(
        _ promoted: PromotedFinalization, to phase: FinalizationPhaseV1
    ) throws -> PromotedFinalization {
        let authority = try requireAuthority()
        let paths = try validatedPaths(for: promoted.intent)
        try verifyPromotedHandle(promoted, paths: paths, authority: authority)
        let expectedPhase: FinalizationPhaseV1
        switch promoted.intent.phase {
        case .prepared:
            expectedPhase = .snapshotPromoted
        case .snapshotPromoted:
            expectedPhase = .databaseCommitted
        case .databaseCommitted:
            throw FinalizationIntentStoreError.phaseInvalid
        }
        guard phase == expectedPhase else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let advanced = promoted.intent.withPhase(phase)
        if phase == .snapshotPromoted,
           failureInjection?.consume(.intentPhaseWrite(phase)) == true {
            try rollbackUncommittedUnprotected(promoted)
            throw FinalizationIntentStoreError.fileOperationFailed
        }
        let mutationProgress = MutationProgress()
        do {
            try replaceAndVerifyIntent(
                promoted.intent,
                with: advanced,
                name: paths.intentName,
                authority: authority,
                mutationProgress: mutationProgress
            )
        } catch {
            if phase == .snapshotPromoted {
                // No database mutation exists yet. Even if the canonical root
                // or journal ancestry was persistently replaced after the
                // leaf swap, retained descriptors still identify the exact
                // mutation-owned snapshot and prepared journal to remove.
                try removeOwnedFileIfMatching(
                    components: paths.finalComponents,
                    expectedByteCount: promoted.snapshotByteCount,
                    expectedSHA256: promoted.snapshotSHA256,
                    authority: authority,
                    requireCurrentAuthority: false
                )
                try removeOwnedFileIfMatching(
                    components: paths.stagingComponents,
                    expectedByteCount: promoted.snapshotByteCount,
                    expectedSHA256: promoted.snapshotSHA256,
                    authority: authority,
                    requireCurrentAuthority: false
                )
                try removeIntentIfMatching(
                    promoted.intent,
                    name: paths.intentName,
                    authority: authority,
                    requireCurrentAuthority: false
                )
            } else if phase == .databaseCommitted,
                      mutationProgress.didMutateLeaf {
                // The database and final snapshot are already authoritative.
                // A persistent journal-ancestry replacement can make the
                // phase swap fail after restoring either exact owned phase in
                // the detached pinned directory. Remove only those canonical
                // intent bytes through the retained descriptor; recovery can
                // validate the committed row and render the final snapshot.
                try removeEitherIntentIfMatching(
                    promoted.intent,
                    advanced,
                    name: paths.intentName,
                    authority: authority
                )
            }
            throw mapped(error)
        }
        return PromotedFinalization(
            intent: advanced,
            intentRelativePath: promoted.intentRelativePath,
            snapshotStagingRelativePath: promoted.snapshotStagingRelativePath,
            snapshotFinalRelativePath: promoted.snapshotFinalRelativePath,
            snapshotByteCount: promoted.snapshotByteCount,
            snapshotSHA256: promoted.snapshotSHA256
        )
    }

    func cleanupCommitted(_ committed: PromotedFinalization) throws {
        try requireProducerAuthority()
        try cleanupCommittedUnprotected(committed)
    }

    private func cleanupCommittedUnprotected(_ committed: PromotedFinalization) throws {
        guard committed.intent.phase == .databaseCommitted else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let authority = try requireAuthority()
        let paths = try validatedPaths(for: committed.intent)
        try verifyPromotedHandle(committed, paths: paths, authority: authority)
        try removeOwnedFileIfMatching(
            components: paths.stagingComponents,
            expectedByteCount: committed.snapshotByteCount,
            expectedSHA256: committed.snapshotSHA256,
            authority: authority
        )
        try removeIntentIfMatching(committed.intent, name: paths.intentName, authority: authority)
    }

    func rollbackUncommitted(_ promoted: PromotedFinalization) throws {
        try requireProducerAuthority()
        try rollbackUncommittedUnprotected(promoted)
    }

    private func rollbackUncommittedUnprotected(_ promoted: PromotedFinalization) throws {
        guard promoted.intent.phase != .databaseCommitted else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let authority = try requireAuthority()
        let paths = try validatedPaths(for: promoted.intent)
        try verifyPromotedHandle(promoted, paths: paths, authority: authority)
        try removeOwnedFileIfMatching(
            components: paths.finalComponents,
            expectedByteCount: promoted.snapshotByteCount,
            expectedSHA256: promoted.snapshotSHA256,
            authority: authority
        )
        try removeOwnedFileIfMatching(
            components: paths.stagingComponents,
            expectedByteCount: promoted.snapshotByteCount,
            expectedSHA256: promoted.snapshotSHA256,
            authority: authority
        )
        try removeIntentIfMatching(promoted.intent, name: paths.intentName, authority: authority)
    }

    private struct Paths {
        let intentName: String
        let intentRelativePath: String
        let stagingComponents: [String]
        let finalComponents: [String]
    }

    private func validatedPaths(for intent: FinalizationIntentV1) throws -> Paths {
        let mutation = intent.finalizationMutationID.uuidString.lowercased()
        let report = intent.reportID.uuidString.lowercased()
        let expectedStaging = ".staging/snapshots/\(report).json"
        let expectedFinal = "snapshots/\(report).json"
        guard intent.snapshotStagingRelativePath == expectedStaging,
              intent.snapshotFinalRelativePath == expectedFinal,
              intent.finalizationPayloadSHA256.count == 64,
              intent.snapshotSHA256.count == 64,
              isLowercaseSHA256(intent.finalizationPayloadSHA256),
              isLowercaseSHA256(intent.snapshotSHA256) else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        return Paths(
            intentName: "\(mutation).json",
            intentRelativePath: "FieldEvidenceOperations/finalization/\(mutation).json",
            stagingComponents: [".staging", "snapshots", "\(report).json"],
            finalComponents: ["snapshots", "\(report).json"]
        )
    }

    private func validatedSnapshotIfPresent(
        components: [String],
        intent: FinalizationIntentV1,
        authority: PinnedAuthority
    ) throws -> (data: Data, snapshot: ReportSnapshotV1)? {
        guard let info = try itemInfo(components: components, authority: authority) else {
            return nil
        }
        guard PinnedAuthority.isRegular(info) else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        try authority.verifyGenerationFilePolicy(
            components.first == ".staging" ? .stagingFile : .reportSnapshot,
            components: components
        )
        let data = try authority.readGenerationRegularFile(components: components).data
        guard sha256(data) == intent.snapshotSHA256 else {
            throw FinalizationIntentStoreError.bytesMismatch
        }
        do {
            let snapshot = try ReportSnapshotEncoderV1().decode(data)
            try FinalizationPlanProjectionPolicyV1.validate(snapshot)
            let payload = intent.finalizationPayload
            let expectedEvidenceSource = payload.workflowRecordAfter.evidenceSourceRecordID
                ?? payload.workflowRecordAfter.id
            guard try ReportSnapshotEncoderV1().encode(snapshot).data == data,
                  snapshot.reportID == intent.reportID,
                  snapshot.packetID == intent.packetID,
                  snapshot.sourceRecordID == intent.recordID,
                  snapshot.evidenceSourceRecordID == expectedEvidenceSource,
                  snapshot.stableRootID == intent.stableRootID,
                  snapshot.snapshotCreatedAt == intent.snapshotCreatedAt,
                  snapshot.snapshotSchemaVersion == 1,
                  snapshot.stage == payload.workflowRecordAfter.stage,
                  snapshot.outcome == payload.workflowRecordAfter.outcomeKey,
                  snapshot.pdfTemplate.id == payload.workflowRecordAfter.pdfTemplateID,
                  snapshot.pdfTemplate.version == payload.workflowRecordAfter.pdfTemplateVersion,
                  snapshot.pack.id == payload.workflowRecordAfter.packID,
                  snapshot.pack.schemaVersion == payload.workflowRecordAfter.packSchemaVersion,
                  snapshot.pack.contentVersion == payload.workflowRecordAfter.packContentVersion else {
                throw FinalizationIntentStoreError.bytesMismatch
            }
            return (data, snapshot)
        } catch {
            throw FinalizationIntentStoreError.bytesMismatch
        }
    }

    private func verifyRecovery(
        _ recovery: RecoverableFinalization,
        paths: Paths,
        authority: PinnedAuthority
    ) throws {
        guard recovery.intentRelativePath == paths.intentRelativePath,
              recovery.snapshotStagingRelativePath == recovery.intent.snapshotStagingRelativePath,
              recovery.snapshotFinalRelativePath == recovery.intent.snapshotFinalRelativePath else {
            throw FinalizationIntentStoreError.notOwned
        }
        try verifyIntent(recovery.intent, name: paths.intentName, authority: authority)
        if recovery.hasStagingSnapshot {
            try verifyRegularFile(
                components: paths.stagingComponents,
                expectedByteCount: recovery.snapshotByteCount,
                expectedSHA256: recovery.intent.snapshotSHA256,
                authority: authority
            )
        }
        if recovery.hasFinalSnapshot {
            try verifyRegularFile(
                components: paths.finalComponents,
                expectedByteCount: recovery.snapshotByteCount,
                expectedSHA256: recovery.intent.snapshotSHA256,
                authority: authority
            )
        }
    }

    private func verifyHandle(
        _ prepared: PreparedFinalization,
        paths: Paths,
        authority: PinnedAuthority
    ) throws {
        guard prepared.intentRelativePath == paths.intentRelativePath,
              prepared.snapshotStagingRelativePath == prepared.intent.snapshotStagingRelativePath,
              prepared.snapshotFinalRelativePath == prepared.intent.snapshotFinalRelativePath,
              prepared.snapshotSHA256 == prepared.intent.snapshotSHA256 else {
            throw FinalizationIntentStoreError.notOwned
        }
        try verifyIntent(prepared.intent, name: paths.intentName, authority: authority)
        try verifyRegularFile(
            components: paths.stagingComponents,
            expectedByteCount: prepared.snapshotByteCount,
            expectedSHA256: prepared.snapshotSHA256,
            authority: authority
        )
    }

    private func verifyPromotedHandle(
        _ promoted: PromotedFinalization,
        paths: Paths,
        authority: PinnedAuthority
    ) throws {
        guard promoted.intentRelativePath == paths.intentRelativePath,
              promoted.snapshotStagingRelativePath == promoted.intent.snapshotStagingRelativePath,
              promoted.snapshotFinalRelativePath == promoted.intent.snapshotFinalRelativePath,
              promoted.snapshotSHA256 == promoted.intent.snapshotSHA256 else {
            throw FinalizationIntentStoreError.notOwned
        }
        try verifyIntent(promoted.intent, name: paths.intentName, authority: authority)
        try verifyRegularFile(
            components: paths.finalComponents,
            expectedByteCount: promoted.snapshotByteCount,
            expectedSHA256: promoted.snapshotSHA256,
            authority: authority
        )
    }

    private func createAndVerifyIntent(
        _ intent: FinalizationIntentV1,
        name: String,
        authority: PinnedAuthority
    ) throws {
        let encoded = try encodedIntent(intent)
        guard failureInjection?.consume(.intentPhaseWrite(intent.phase)) != true else {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
        try beforeLeafMutation(authority)
        try authority.createRegularFile(
            encoded.data,
            parent: authority.finalizationDescriptor,
            name: name,
            policyKind: .journal,
            policyURL: try authority.finalizationFileURL(name: name)
        )
        authorityBarrier?.reach(.afterLeafMutation)
        try verifyIntent(intent, name: name, authority: authority)
    }

    private func replaceAndVerifyIntent(
        _ previous: FinalizationIntentV1,
        with next: FinalizationIntentV1,
        name: String,
        authority: PinnedAuthority,
        mutationProgress: MutationProgress
    ) throws {
        let old = try encodedIntent(previous)
        let new = try encodedIntent(next)
        guard failureInjection?.consume(.intentPhaseWrite(next.phase)) != true else {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
        try beforeLeafMutation(authority)
        try authority.replaceExactRegularFile(
            parent: authority.finalizationDescriptor,
            name: name,
            expectedData: old.data,
            replacementData: new.data,
            policyURL: try authority.finalizationFileURL(name: name),
            afterMutation: { [authorityBarrier, mutationProgress] in
                mutationProgress.didMutateLeaf = true
                authorityBarrier?.reach(.afterLeafMutation)
            }
        )
        try verifyIntent(next, name: name, authority: authority)
    }

    private func verifyIntent(
        _ intent: FinalizationIntentV1,
        name: String,
        authority: PinnedAuthority
    ) throws {
        let encoded = try encodedIntent(intent)
        try authority.verifyRegularFilePolicy(
            .journal,
            parent: authority.finalizationDescriptor,
            name: name,
            policyURL: try authority.finalizationFileURL(name: name)
        )
        let read = try authority.readRegularFile(
            parent: authority.finalizationDescriptor,
            name: name
        ).data
        guard read == encoded.data, sha256(read) == encoded.sha256 else {
            throw FinalizationIntentStoreError.bytesMismatch
        }
    }

    private func removeIntentIfMatching(
        _ intent: FinalizationIntentV1,
        name: String,
        authority: PinnedAuthority,
        requireCurrentAuthority: Bool = true
    ) throws {
        guard let info = try authority.itemInfo(
            parent: authority.finalizationDescriptor,
            name: name
        ) else { return }
        guard PinnedAuthority.isRegular(info) else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        try authority.verifyRegularFilePolicy(
            .journal,
            parent: authority.finalizationDescriptor,
            name: name,
            policyURL: try authority.finalizationFileURL(name: name)
        )
        let expected = try encodedIntent(intent).data
        let file = try authority.readRegularFile(
            parent: authority.finalizationDescriptor,
            name: name
        )
        guard file.data == expected else {
            throw FinalizationIntentStoreError.notOwned
        }
        if requireCurrentAuthority {
            try beforeLeafMutation(authority)
        }
        try authority.quarantineAndRemove(
            parent: authority.finalizationDescriptor,
            name: name,
            expectedIdentity: file.identity,
            expectedData: expected,
            verifyCurrentAuthority: requireCurrentAuthority
        )
    }

    private func removeEitherIntentIfMatching(
        _ first: FinalizationIntentV1,
        _ second: FinalizationIntentV1,
        name: String,
        authority: PinnedAuthority
    ) throws {
        guard let info = try authority.itemInfo(
            parent: authority.finalizationDescriptor,
            name: name
        ) else { return }
        guard PinnedAuthority.isRegular(info) else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        try authority.verifyRegularFilePolicy(
            .journal,
            parent: authority.finalizationDescriptor,
            name: name,
            policyURL: try authority.finalizationFileURL(name: name)
        )
        let firstData = try encodedIntent(first).data
        let secondData = try encodedIntent(second).data
        let file = try authority.readRegularFile(
            parent: authority.finalizationDescriptor,
            name: name
        )
        guard file.data == firstData || file.data == secondData else {
            throw FinalizationIntentStoreError.notOwned
        }
        try authority.quarantineAndRemove(
            parent: authority.finalizationDescriptor,
            name: name,
            expectedIdentity: file.identity,
            expectedData: file.data,
            verifyCurrentAuthority: false
        )
    }

    private func removeOwnedFileIfMatching(
        components: [String],
        expectedByteCount: Int,
        expectedSHA256: String,
        authority: PinnedAuthority,
        requireCurrentAuthority: Bool = true
    ) throws {
        try authority.withGenerationParent(components: components) { parent, name in
            guard let info = try authority.itemInfo(parent: parent, name: name) else { return }
            guard PinnedAuthority.isRegular(info) else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            try authority.verifyGenerationFilePolicy(
                components.first == ".staging" ? .stagingFile : .reportSnapshot,
                components: components
            )
            let file = try authority.readRegularFile(parent: parent, name: name)
            guard file.data.count == expectedByteCount,
                  sha256(file.data) == expectedSHA256 else {
                throw FinalizationIntentStoreError.notOwned
            }
            if requireCurrentAuthority {
                try beforeLeafMutation(authority)
            }
            try authority.quarantineAndRemove(
                parent: parent,
                name: name,
                expectedIdentity: file.identity,
                expectedData: file.data,
                verifyCurrentAuthority: requireCurrentAuthority
            )
        }
    }

    private func verifyRegularFile(
        components: [String],
        expectedData: Data? = nil,
        expectedByteCount: Int? = nil,
        expectedSHA256: String,
        authority: PinnedAuthority
    ) throws {
        try authority.verifyGenerationFilePolicy(
            components.first == ".staging" ? .stagingFile : .reportSnapshot,
            components: components
        )
        let read = try authority.readGenerationRegularFile(components: components).data
        guard expectedData.map({ $0 == read }) ?? true,
              expectedByteCount.map({ $0 == read.count }) ?? true,
              sha256(read) == expectedSHA256 else {
            throw FinalizationIntentStoreError.bytesMismatch
        }
    }

    private func createRegularFile(
        _ data: Data,
        components: [String],
        authority: PinnedAuthority
    ) throws {
        try authority.withGenerationParent(components: components) { parent, name in
            try beforeLeafMutation(authority)
            try authority.createRegularFile(
                data,
                parent: parent,
                name: name,
                policyKind: .stagingFile,
                policyURL: try authority.generationFileURL(components: components)
            )
            authorityBarrier?.reach(.afterLeafMutation)
        }
    }

    private func itemInfo(
        components: [String],
        authority: PinnedAuthority
    ) throws -> stat? {
        do {
            return try authority.withGenerationParent(components: components) { parent, name in
                try authority.itemInfo(parent: parent, name: name)
            }
        } catch where errno == ENOENT {
            return nil
        }
    }

    private func encodedIntent(
        _ intent: FinalizationIntentV1
    ) throws -> EncodedFinalizationContractV1 {
        do {
            return try FinalizationContractEncoderV1().encodeIntent(intent)
        } catch {
#if DEBUG
            finalizationJournalDiagnosticFailureV1(
                component: "intent-store", phase: "encode-intent", error: error
            )
#endif
            throw FinalizationIntentStoreError.intentInvalid
        }
    }

    private func requireProducerAuthority() throws {
        guard sourceMutationGuard == nil else { throw FinalizationIntentStoreError.generationRootInvalid }
        guard !liveMutationInFlight else { throw FinalizationIntentStoreError.fileOperationFailed }
    }

    private func withLiveMutation<Value: Sendable>(_ body: () async throws -> Value) async throws -> Value {
        try beginLiveMutation()
        defer {
            livePrivatePreparations.removeAll()
            liveMutationInFlight = false
        }
        let result: Result<Value, Error>
        do { result = .success(try await body()) }
        catch { result = .failure(error) }
        // Disposal is actor-owned preparation work, even if live authority has
        // retired. It can touch only registered private names and exact bytes.
        try LivePrivatePreparation.dispose(livePrivatePreparations)
        return try result.get()
    }

    private func beginLiveMutation() throws {
        try Task.checkCancellation()
        try requireProducerAuthority()
        liveMutationInFlight = true
    }

    private func requireAuthority(allowLiveMutation: Bool = false) throws -> PinnedAuthority {
        guard allowLiveMutation || !liveMutationInFlight else { throw FinalizationIntentStoreError.fileOperationFailed }
        let authority: PinnedAuthority
        switch authorityResult {
        case .success(let value):
            authority = value
        case .failure(let error):
            throw error
        }
        try authority.verify()
        authorityBarrier?.reach(.authorityVerified)
        try authority.verify()
        return authority
    }

    private func beforeLeafMutation(_ authority: PinnedAuthority) throws {
        try authority.verify()
        authorityBarrier?.reach(.beforeLeafMutation)
        try authority.verify()
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func mapped(_ error: Error) -> FinalizationIntentStoreError {
        (error as? FinalizationIntentStoreError) ?? .fileOperationFailed
    }

    /// An exact-byte observation made on the store actor, retained through the
    /// later live publication fence. No bytes are read by verifyNamed.
    private struct LivePrivatePreparation {
        let authority: PinnedAuthority
        let name: String
        let identity: PinnedAuthority.Identity
        let data: Data
        let policy: OwnedFileKindV1

        static func isReservedName(_ name: String, prefix: String = ".live-finalization-") -> Bool {
            let suffix = ".tmp"
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
            let raw = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            return UUID(uuidString: raw)?.uuidString.lowercased() == raw
        }

        static func names(in parent: Int32) throws -> [String] {
            let fd = Darwin.openat(parent, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0, let directory = Darwin.fdopendir(fd) else {
                if fd >= 0 { _ = Darwin.close(fd) }
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            defer { _ = Darwin.closedir(directory) }
            var names: [String] = []
            errno = 0
            while let entry = Darwin.readdir(directory) {
                var tuple = entry.pointee.d_name
                let capacity = MemoryLayout.size(ofValue: tuple)
                let name = withUnsafePointer(to: &tuple) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
                }
                if name != "." && name != ".." { names.append(name) }
                errno = 0
            }
            guard errno == 0 else { throw FinalizationIntentStoreError.fileOperationFailed }
            return names.sorted()
        }

        static func dispose(_ preparations: [Self]) throws {
            for group in Dictionary(grouping: preparations, by: \.name).values {
                guard let first = group.first, isReservedName(first.name),
                      group.allSatisfy({ $0.authority === first.authority }) else {
                    throw FinalizationIntentStoreError.notOwned
                }
                let authority = first.authority, parent = authority.stagingSnapshotsDescriptor
                try authority.verify()
                guard let info = try authority.itemInfo(parent: parent, name: first.name) else { continue }
                guard PinnedAuthority.isRegular(info), info.st_nlink == 1 else {
                    throw FinalizationIntentStoreError.itemTypeInvalid
                }
                let original = try authority.readRegularFile(parent: parent, name: first.name)
                guard let owned = group.first(where: { $0.identity == original.identity && $0.data == original.data }) else {
                    throw FinalizationIntentStoreError.notOwned
                }
                try owned.disposeObservedPrivateLeaf()
            }
        }

        private func verify(at name: String) throws {
            try authority.verify()
            let parent = authority.stagingSnapshotsDescriptor
            guard Self.isReservedName(name),
                  let info = try authority.itemInfo(parent: parent, name: name),
                  PinnedAuthority.isRegular(info), info.st_nlink == 1 else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            let observed = try authority.readRegularFile(parent: parent, name: name)
            guard observed.identity == identity, observed.data == data else {
                throw FinalizationIntentStoreError.notOwned
            }
            try authority.verifyRegularFilePolicy(policy, parent: parent, name: name,
                policyURL: authority.generationFileURL(components: [".staging", "snapshots", name]))
        }

        private func disposeObservedPrivateLeaf() throws {
            try verify(at: name)
            let parent = authority.stagingSnapshotsDescriptor
            let quarantine = ".live-finalization-\(UUID().uuidString.lowercased()).tmp"
            guard Darwin.renameatx_np(parent, name, parent, quarantine, UInt32(RENAME_EXCL)) == 0 else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            do {
                try verify(at: quarantine)
                guard Darwin.unlinkat(parent, quarantine, 0) == 0, Darwin.fsync(parent) == 0 else {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
            } catch {
                // Both names are private. Never restore into a canonical path
                // or overwrite a leaf that appeared after preparation.
                _ = Darwin.renameatx_np(parent, quarantine, parent, name, UInt32(RENAME_EXCL))
                _ = Darwin.fsync(parent)
                throw error
            }
        }
    }

    private final class LivePreparedLeaf: @unchecked Sendable {
        let authority: PinnedAuthority
        let parent: Int32
        let name: String
        let url: URL
        let policy: OwnedFileKindV1
        let descriptor: Int32
        let facts: stat
        let verifiedData: Data

        init(authority: PinnedAuthority, parent: Int32, name: String, url: URL,
             policy: OwnedFileKindV1, expectedCount: Int, expectedSHA256: String,
             expectedData: Data? = nil) throws {
            try Task.checkCancellation()
            try authority.verify()
            let fd = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
            guard fd >= 0 else { throw FinalizationIntentStoreError.itemMissing }
            var transferred = false
            defer { if !transferred { _ = Darwin.close(fd) } }
            var before = stat()
            guard Darwin.fstat(fd, &before) == 0, PinnedAuthority.isRegular(before),
                  before.st_nlink == 1, before.st_size == Int64(expectedCount) else {
                throw FinalizationIntentStoreError.bytesMismatch
            }
            try authority.verifyRegularFilePolicy(policy, parent: parent, name: name, policyURL: url)
            let read = try authority.readRegularFile(parent: parent, name: name)
            guard read.identity == PinnedAuthority.Identity(device: before.st_dev, inode: before.st_ino),
                  read.data.count == expectedCount,
                  SHA256.hash(data: read.data).map({ String(format: "%02x", $0) }).joined() == expectedSHA256,
                  expectedData.map({ $0 == read.data }) ?? true else {
                throw FinalizationIntentStoreError.bytesMismatch
            }
            var after = stat()
            guard Darwin.fstat(fd, &after) == 0,
                  let named = try authority.itemInfo(parent: parent, name: name),
                  PinnedAuthority.isRegular(after), after.st_nlink == 1,
                  PinnedAuthority.isRegular(named), named.st_nlink == 1,
                  after.st_dev == before.st_dev, after.st_ino == before.st_ino,
                  named.st_dev == before.st_dev, named.st_ino == before.st_ino,
                  after.st_size == before.st_size,
                  after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else {
                throw FinalizationIntentStoreError.notOwned
            }
            try Task.checkCancellation()
            try authority.verify()
            self.authority = authority; self.parent = parent; self.name = name; self.url = url
            self.policy = policy; descriptor = fd; facts = before
            verifiedData = read.data
            transferred = true
        }

        deinit { _ = Darwin.close(descriptor) }

        func verifyNamed(parent movedParent: Int32? = nil, name movedName: String? = nil,
                         url movedURL: URL? = nil, policy movedPolicy: OwnedFileKindV1? = nil,
                         allowMetadataChange: Bool = false, verifyPolicy: Bool = true,
                         expectedChangeTime: timespec? = nil) throws {
            try authority.verify()
            let parent = movedParent ?? self.parent, name = movedName ?? self.name
            var now = stat(), named = stat()
            guard Darwin.fstat(descriptor, &now) == 0,
                  Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  PinnedAuthority.isRegular(now), now.st_nlink == 1,
                  PinnedAuthority.isRegular(named), named.st_nlink == 1,
                  now.st_dev == facts.st_dev, now.st_ino == facts.st_ino,
                  named.st_dev == facts.st_dev, named.st_ino == facts.st_ino,
                  now.st_size == facts.st_size, named.st_size == facts.st_size,
                  now.st_mtimespec.tv_sec == facts.st_mtimespec.tv_sec,
                  now.st_mtimespec.tv_nsec == facts.st_mtimespec.tv_nsec,
                  named.st_mtimespec.tv_sec == facts.st_mtimespec.tv_sec,
                  named.st_mtimespec.tv_nsec == facts.st_mtimespec.tv_nsec,
                  allowMetadataChange || (
                    now.st_ctimespec.tv_sec == facts.st_ctimespec.tv_sec &&
                    now.st_ctimespec.tv_nsec == facts.st_ctimespec.tv_nsec &&
                    named.st_ctimespec.tv_sec == facts.st_ctimespec.tv_sec &&
                    named.st_ctimespec.tv_nsec == facts.st_ctimespec.tv_nsec) else {
                throw FinalizationIntentStoreError.notOwned
            }
            if let expectedChangeTime {
                guard now.st_ctimespec.tv_sec == expectedChangeTime.tv_sec,
                      now.st_ctimespec.tv_nsec == expectedChangeTime.tv_nsec,
                      named.st_ctimespec.tv_sec == expectedChangeTime.tv_sec,
                      named.st_ctimespec.tv_nsec == expectedChangeTime.tv_nsec else {
                    throw FinalizationIntentStoreError.notOwned
                }
            }
            if verifyPolicy {
                try authority.verifyRegularFilePolicy(movedPolicy ?? policy, parent: parent,
                    name: name, policyURL: movedURL ?? url)
            }
        }
    }

    /// Private bytes live outside the strictly enumerated intent directory and
    /// never use a canonical report name. This is preparation, not publication.
    private func preparePrivateLiveLeaf(_ data: Data, policy: OwnedFileKindV1,
                                        authority: PinnedAuthority) throws -> LivePreparedLeaf {
        try Task.checkCancellation()
        let name = ".live-finalization-\(UUID().uuidString.lowercased()).tmp"
        let url = try authority.generationFileURL(components: [".staging", "snapshots", name])
        let identity = try authority.createRegularFile(data, parent: authority.stagingSnapshotsDescriptor,
            name: name, policyKind: policy, policyURL: url)
        livePrivatePreparations.append(.init(authority: authority, name: name,
            identity: identity, data: data, policy: policy))
        return try LivePreparedLeaf(authority: authority, parent: authority.stagingSnapshotsDescriptor,
            name: name, url: url, policy: policy, expectedCount: data.count,
            expectedSHA256: sha256(data), expectedData: data)
    }

    /// Single-use, no-overwrite publication of one already verified leaf.
    /// Construction is actor-owned; only the captured live operation can run it.
    private final class LivePreparedMove: @unchecked Sendable {
        private let source: LivePreparedLeaf
        private let destinationParent: Int32
        private let destinationName: String
        private let destinationURL: URL
        private let destinationPolicy: OwnedFileKindV1
        private let operationID: ObjectIdentifier
        private let barrier: FinalizationIntentStoreAuthorityBarrier?
        private let dependencies: [LivePreparedLeaf]
        private let consumption = NSLock()
        private var consumed = false
        @MainActor private var publishedChangeTime: timespec?

        init(source: LivePreparedLeaf, destinationParent: Int32, destinationName: String,
             destinationURL: URL, destinationPolicy: OwnedFileKindV1,
             operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess,
             barrier: FinalizationIntentStoreAuthorityBarrier?, dependencies: [LivePreparedLeaf] = []) throws {
            try source.verifyNamed()
            for dependency in dependencies { try dependency.verifyNamed() }
            guard case nil = try source.authority.itemInfo(parent: destinationParent, name: destinationName) else {
                throw FinalizationIntentStoreError.itemAlreadyExists
            }
            self.source = source; self.destinationParent = destinationParent
            self.destinationName = destinationName; self.destinationURL = destinationURL
            self.destinationPolicy = destinationPolicy; operationID = ObjectIdentifier(operation)
            self.barrier = barrier
            self.dependencies = dependencies
        }

        @MainActor
        func verifyPublished() throws {
            guard let publishedChangeTime else { throw FinalizationIntentStoreError.notOwned }
            try source.verifyNamed(parent: destinationParent, name: destinationName,
                url: destinationURL, policy: destinationPolicy, allowMetadataChange: true,
                expectedChangeTime: publishedChangeTime)
            for dependency in dependencies { try dependency.verifyNamed() }
        }

        @MainActor
        func perform(authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
            guard ObjectIdentifier(operation) == operationID else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try operation.withFinalizationAuthorization(generationID: source.authority.generationID,
                generationRootURL: source.authority.liveGenerationRootURL) {
                guard consumption.try() else { throw FinalizationIntentStoreError.fileOperationFailed }
                defer { consumption.unlock() }
                guard !consumed else { throw FinalizationIntentStoreError.fileOperationFailed }
                consumed = true
                try Task.checkCancellation()
                try source.verifyNamed()
                for dependency in dependencies { try dependency.verifyNamed() }
                barrier?.reach(.beforeLeafMutation)
                try source.verifyNamed()
                for dependency in dependencies { try dependency.verifyNamed() }
                // A boundary callback may retire the presentation. Reentering
                // the same synchronous scope validates it without relocking.
                try operation.withAuthorization {
                    guard case nil = try source.authority.itemInfo(parent: destinationParent, name: destinationName),
                          Darwin.renameatx_np(source.parent, source.name,
                            destinationParent, destinationName, UInt32(RENAME_EXCL)) == 0 else {
                        throw FinalizationIntentStoreError.itemAlreadyExists
                    }
                    var renamedFacts = stat()
                    guard Darwin.fstat(source.descriptor, &renamedFacts) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    barrier?.reach(.afterLeafMutation)
                    guard Darwin.fsync(source.parent) == 0, Darwin.fsync(destinationParent) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    // Failure after rename retains the exact named bytes for
                    // recovery. Never run unguarded compensating deletion.
                    try operation.withAuthorization {
                        try source.verifyNamed(parent: destinationParent, name: destinationName,
                            url: destinationURL, policy: source.policy, allowMetadataChange: true,
                            expectedChangeTime: renamedFacts.st_ctimespec)
                        try ProtectedFilePolicyV1.applyAndVerify(destinationPolicy, at: destinationURL) {
                            try source.verifyNamed(parent: destinationParent, name: destinationName,
                                url: destinationURL, allowMetadataChange: true, verifyPolicy: false)
                        }
                        guard Darwin.fsync(source.descriptor) == 0, Darwin.fsync(destinationParent) == 0 else {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                        var publishedFacts = stat()
                        guard Darwin.fstat(source.descriptor, &publishedFacts) == 0 else {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                        publishedChangeTime = publishedFacts.st_ctimespec
                        try verifyPublished()
                    }
                }
            }
        }
    }

    /// Atomic phase replacement always leaves either the old or new canonical
    /// journal. Failure after a swap retains the recoverable phase; it never
    /// deletes snapshots or falls back to an unguarded compensating write.
    private final class LivePreparedReplacement: @unchecked Sendable {
        private let original: LivePreparedLeaf
        private let candidate: LivePreparedLeaf
        private let dependencies: [LivePreparedLeaf]
        private let operationID: ObjectIdentifier
        private let barrier: FinalizationIntentStoreAuthorityBarrier?
        private let rollbackMutationID: UUID?
        private let consumption = NSLock()
        private var consumed = false

        init(original: LivePreparedLeaf, candidate: LivePreparedLeaf,
             dependencies: [LivePreparedLeaf], operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess,
             barrier: FinalizationIntentStoreAuthorityBarrier?, rollbackMutationID: UUID? = nil) throws {
            guard original.authority === candidate.authority,
                  original.parent == original.authority.finalizationDescriptor,
                  candidate.parent == original.authority.stagingSnapshotsDescriptor,
                  candidate.name.hasPrefix(".live-finalization-"), candidate.name.hasSuffix(".tmp") else {
                throw FinalizationIntentStoreError.notOwned
            }
            try original.verifyNamed(); try candidate.verifyNamed()
            for dependency in dependencies { try dependency.verifyNamed() }
            self.original = original; self.candidate = candidate; self.dependencies = dependencies
            operationID = ObjectIdentifier(operation); self.barrier = barrier
            self.rollbackMutationID = rollbackMutationID
            if let rollbackMutationID {
                guard original.name == rollbackMutationID.uuidString.lowercased() + ".json" else {
                    throw FinalizationIntentStoreError.notOwned
                }
            }
        }

        @MainActor
        func perform(authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
            guard ObjectIdentifier(operation) == operationID else { throw AppAccessContractFailureV1.accessDenied }
            try operation.withFinalizationAuthorization(generationID: original.authority.generationID,
                generationRootURL: original.authority.liveGenerationRootURL) {
                guard consumption.try() else { throw FinalizationIntentStoreError.fileOperationFailed }
                defer { consumption.unlock() }
                guard !consumed else { throw FinalizationIntentStoreError.fileOperationFailed }
                consumed = true
                try Task.checkCancellation()
                try original.verifyNamed(); try candidate.verifyNamed()
                for dependency in dependencies { try dependency.verifyNamed() }
                barrier?.reach(.beforeLeafMutation)
                try original.verifyNamed(); try candidate.verifyNamed()
                for dependency in dependencies { try dependency.verifyNamed() }
                try operation.withAuthorization {
                    if let rollbackMutationID { try operation.requireUncommittedFinalization(mutationID: rollbackMutationID) }
                    guard Darwin.renameatx_np(candidate.parent, candidate.name,
                        original.parent, original.name, UInt32(RENAME_SWAP)) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    var newFacts = stat(), oldFacts = stat()
                    guard Darwin.fstat(candidate.descriptor, &newFacts) == 0,
                          Darwin.fstat(original.descriptor, &oldFacts) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    barrier?.reach(.afterLeafMutation)
                    guard Darwin.fsync(original.parent) == 0, Darwin.fsync(candidate.parent) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    try operation.withAuthorization {
                        if let rollbackMutationID { try operation.requireUncommittedFinalization(mutationID: rollbackMutationID) }
                        try candidate.verifyNamed(parent: original.parent, name: original.name, url: original.url,
                            policy: .journal, allowMetadataChange: true, expectedChangeTime: newFacts.st_ctimespec)
                        try original.verifyNamed(parent: candidate.parent, name: candidate.name, url: candidate.url,
                            policy: .journal, allowMetadataChange: true, expectedChangeTime: oldFacts.st_ctimespec)
                        for dependency in dependencies { try dependency.verifyNamed() }
                        // The displaced exact journal is now a private leaf.
                        // Remove it only while the same operation is current.
                        guard Darwin.unlinkat(candidate.parent, candidate.name, 0) == 0,
                              Darwin.fsync(candidate.parent) == 0 else {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                        try candidate.verifyNamed(parent: original.parent, name: original.name, url: original.url,
                            policy: .journal, allowMetadataChange: true, expectedChangeTime: newFacts.st_ctimespec)
                        for dependency in dependencies { try dependency.verifyNamed() }
                    }
                }
            }
        }
    }

    private struct LivePreparedAbsence: Sendable {
        let authority: PinnedAuthority
        let parent: Int32
        let name: String

        func verify() throws {
            try authority.verify()
            guard case nil = try authority.itemInfo(parent: parent, name: name) else {
                throw FinalizationIntentStoreError.notOwned
            }
        }
    }

    private final class LivePreparedRemoval: @unchecked Sendable {
        private let source: LivePreparedLeaf
        private let dependencies: [LivePreparedLeaf]
        private let operationID: ObjectIdentifier
        private let mutationID: UUID
        private let committedBinding: FinalizationWriterCommitBindingV1?
        private let barrier: FinalizationIntentStoreAuthorityBarrier?
        private let privateName: String
        private let consumption = NSLock()
        private var consumed = false

        init(source: LivePreparedLeaf, dependencies: [LivePreparedLeaf],
             operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess,
             mutationID: UUID, committedBinding: FinalizationWriterCommitBindingV1?,
             barrier: FinalizationIntentStoreAuthorityBarrier?, privateName: String) {
            self.source = source; self.dependencies = dependencies; operationID = ObjectIdentifier(operation)
            self.mutationID = mutationID; self.committedBinding = committedBinding; self.barrier = barrier
            self.privateName = privateName
        }

        var sourceAbsence: LivePreparedAbsence {
            .init(authority: source.authority, parent: source.parent, name: source.name)
        }

        @MainActor
        private func validateReceipt(_ operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
            if let committedBinding { try operation.requireCommittedFinalization(binding: committedBinding) }
            else { try operation.requireUncommittedFinalization(mutationID: mutationID) }
        }

        @MainActor
        func perform(authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess,
            expectedAbsences: [LivePreparedAbsence]) throws {
            guard ObjectIdentifier(operation) == operationID else { throw AppAccessContractFailureV1.accessDenied }
            try operation.withFinalizationAuthorization(generationID: source.authority.generationID,
                generationRootURL: source.authority.liveGenerationRootURL) {
                guard consumption.try() else { throw FinalizationIntentStoreError.fileOperationFailed }
                defer { consumption.unlock() }
                guard !consumed else { throw FinalizationIntentStoreError.fileOperationFailed }
                consumed = true
                try Task.checkCancellation()
                try validateReceipt(operation)
                try source.verifyNamed()
                for dependency in dependencies { try dependency.verifyNamed() }
                for absence in expectedAbsences { try absence.verify() }
                barrier?.reach(.beforeLeafMutation)
                try source.verifyNamed()
                for dependency in dependencies { try dependency.verifyNamed() }
                for absence in expectedAbsences { try absence.verify() }
                try operation.withAuthorization {
                    try validateReceipt(operation)
                    let parent = source.authority.stagingSnapshotsDescriptor
                    let url = try source.authority.generationFileURL(components: [".staging", "snapshots", privateName])
                    guard case nil = try source.authority.itemInfo(parent: parent, name: privateName),
                          Darwin.renameatx_np(source.parent, source.name, parent, privateName, UInt32(RENAME_EXCL)) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    var moved = stat()
                    guard Darwin.fstat(source.descriptor, &moved) == 0 else { throw FinalizationIntentStoreError.fileOperationFailed }
                    barrier?.reach(.afterLeafMutation)
                    guard Darwin.fsync(source.parent) == 0, Darwin.fsync(parent) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    try operation.withAuthorization {
                        try validateReceipt(operation)
                        try source.verifyNamed(parent: parent, name: privateName, url: url,
                            allowMetadataChange: true, expectedChangeTime: moved.st_ctimespec)
                        for dependency in dependencies { try dependency.verifyNamed() }
                        for absence in expectedAbsences { try absence.verify() }
                        guard Darwin.unlinkat(parent, privateName, 0) == 0, Darwin.fsync(parent) == 0 else {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                        try sourceAbsence.verify()
                    }
                }
            }
        }
    }

    private final class PinnedAuthority: @unchecked Sendable {
        typealias Identity = ReportPDFAnchoredFile.RootIdentity

        let generationID: UUID
        let applicationSupportURL: URL
        let generationName: String
        let applicationSupportDescriptor: Int32
        let generationDescriptor: Int32
        let operationsDescriptor: Int32
        let finalizationDescriptor: Int32
        let stagingDescriptor: Int32
        let stagingSnapshotsDescriptor: Int32
        let snapshotsDescriptor: Int32
        var liveGenerationRootURL: URL { generationRootURL }

        private let applicationSupportIdentity: Identity
        private let generationIdentity: Identity
        private let operationsIdentity: Identity
        private let finalizationIdentity: Identity
        private let stagingIdentity: Identity
        private let stagingSnapshotsIdentity: Identity
        private let snapshotsIdentity: Identity

        init(
            generationRootURL: URL,
            expectedGenerationRootIdentity: Identity?
        ) throws {
            let root = generationRootURL.standardizedFileURL
            let generations = root.deletingLastPathComponent()
            let dataRoot = generations.deletingLastPathComponent()
            let applicationSupport = dataRoot.deletingLastPathComponent().standardizedFileURL
            guard generations.lastPathComponent == "generations",
                  dataRoot.lastPathComponent == "FieldEvidenceData",
                  let generationID = UUID(uuidString: root.lastPathComponent),
                  generationID.uuidString.lowercased() == root.lastPathComponent,
                  !applicationSupport.path.isEmpty else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }

            var retained: [Int32] = []
            var succeeded = false
            defer {
                if !succeeded {
                    retained.forEach { _ = Darwin.close($0) }
                }
            }

            let applicationSupportDescriptor = Darwin.open(
                applicationSupport.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard applicationSupportDescriptor >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            retained.append(applicationSupportDescriptor)

            let dataDescriptor = Darwin.openat(
                applicationSupportDescriptor,
                "FieldEvidenceData",
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard dataDescriptor >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            defer { _ = Darwin.close(dataDescriptor) }

            let generationsDescriptor = Darwin.openat(
                dataDescriptor,
                "generations",
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard generationsDescriptor >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            defer { _ = Darwin.close(generationsDescriptor) }

            let generationDescriptor = Darwin.openat(
                generationsDescriptor,
                root.lastPathComponent,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard generationDescriptor >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            retained.append(generationDescriptor)
            let generationIdentity = try Self.directoryIdentity(generationDescriptor)
            guard expectedGenerationRootIdentity.map({ $0 == generationIdentity }) ?? true else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }

            // Reprove the live canonical generation before creating or opening
            // any store-owned descendant through the retained descriptors.
            try Self.requireCanonicalGeneration(
                applicationSupportURL: applicationSupport,
                applicationSupportIdentity: try Self.directoryIdentity(
                    applicationSupportDescriptor
                ),
                generationName: root.lastPathComponent,
                generationIdentity: generationIdentity
            )

            let operationsDescriptor = try Self.openOrCreateDirectory(
                parent: applicationSupportDescriptor,
                name: "FieldEvidenceOperations"
            )
            retained.append(operationsDescriptor)
            let finalizationDescriptor = try Self.openOrCreateDirectory(
                parent: operationsDescriptor,
                name: "finalization"
            )
            retained.append(finalizationDescriptor)
            let stagingDescriptor = try Self.openOrCreateDirectory(
                parent: generationDescriptor,
                name: ".staging"
            )
            retained.append(stagingDescriptor)
            let stagingSnapshotsDescriptor = try Self.openOrCreateDirectory(
                parent: stagingDescriptor,
                name: "snapshots"
            )
            retained.append(stagingSnapshotsDescriptor)
            let snapshotsDescriptor = try Self.openOrCreateDirectory(
                parent: generationDescriptor,
                name: "snapshots"
            )
            retained.append(snapshotsDescriptor)

            let applicationSupportIdentity = try Self.directoryIdentity(
                applicationSupportDescriptor
            )
            let operationsIdentity = try Self.directoryIdentity(operationsDescriptor)
            let finalizationIdentity = try Self.directoryIdentity(finalizationDescriptor)
            let stagingIdentity = try Self.directoryIdentity(stagingDescriptor)
            let stagingSnapshotsIdentity = try Self.directoryIdentity(
                stagingSnapshotsDescriptor
            )
            let snapshotsIdentity = try Self.directoryIdentity(snapshotsDescriptor)
            let operationsURL = applicationSupport.appendingPathComponent(
                "FieldEvidenceOperations",
                isDirectory: true
            )
            let finalizationURL = operationsURL.appendingPathComponent(
                "finalization",
                isDirectory: true
            )
            let stagingURL = root.appendingPathComponent(
                ".staging",
                isDirectory: true
            )
            let stagingSnapshotsURL = stagingURL.appendingPathComponent(
                "snapshots",
                isDirectory: true
            )
            let snapshotsURL = root.appendingPathComponent(
                "snapshots",
                isDirectory: true
            )
            for (kind, url, descriptor, expected) in [
                (OwnedFileKindV1.stagingDirectory, operationsURL,
                 operationsDescriptor, operationsIdentity),
                (.stagingDirectory, finalizationURL,
                 finalizationDescriptor, finalizationIdentity),
                (.stagingDirectory, stagingURL,
                 stagingDescriptor, stagingIdentity),
                (.stagingDirectory, stagingSnapshotsURL,
                 stagingSnapshotsDescriptor, stagingSnapshotsIdentity),
                (.durableDirectory, snapshotsURL,
                 snapshotsDescriptor, snapshotsIdentity),
            ] {
                try ProtectedFilePolicyV1.applyAndVerify(
                    kind,
                    at: url,
                    authorityCheck: {
                        guard try Self.directoryIdentity(descriptor) == expected,
                              try Self.directoryIdentity(at: url) == expected else {
                            throw FinalizationIntentStoreError.generationRootInvalid
                        }
                        try Self.requireCanonicalGeneration(
                            applicationSupportURL: applicationSupport,
                            applicationSupportIdentity: applicationSupportIdentity,
                            generationName: root.lastPathComponent,
                            generationIdentity: generationIdentity
                        )
                    }
                )
            }
            try Self.requireCanonicalGeneration(
                applicationSupportURL: applicationSupport,
                applicationSupportIdentity: applicationSupportIdentity,
                generationName: root.lastPathComponent,
                generationIdentity: generationIdentity
            )

            self.generationID = generationID
            self.applicationSupportURL = applicationSupport
            self.generationName = root.lastPathComponent
            self.applicationSupportDescriptor = applicationSupportDescriptor
            self.generationDescriptor = generationDescriptor
            self.operationsDescriptor = operationsDescriptor
            self.finalizationDescriptor = finalizationDescriptor
            self.stagingDescriptor = stagingDescriptor
            self.stagingSnapshotsDescriptor = stagingSnapshotsDescriptor
            self.snapshotsDescriptor = snapshotsDescriptor
            self.applicationSupportIdentity = applicationSupportIdentity
            self.generationIdentity = generationIdentity
            self.operationsIdentity = operationsIdentity
            self.finalizationIdentity = finalizationIdentity
            self.stagingIdentity = stagingIdentity
            self.stagingSnapshotsIdentity = stagingSnapshotsIdentity
            self.snapshotsIdentity = snapshotsIdentity
            succeeded = true
        }

        deinit {
            _ = Darwin.close(snapshotsDescriptor)
            _ = Darwin.close(stagingSnapshotsDescriptor)
            _ = Darwin.close(stagingDescriptor)
            _ = Darwin.close(finalizationDescriptor)
            _ = Darwin.close(operationsDescriptor)
            _ = Darwin.close(generationDescriptor)
            _ = Darwin.close(applicationSupportDescriptor)
        }

        func verify() throws {
            try Self.requireDirectory(
                applicationSupportDescriptor,
                identity: applicationSupportIdentity
            )
            try Self.requireDirectory(generationDescriptor, identity: generationIdentity)
            try Self.requireDirectory(operationsDescriptor, identity: operationsIdentity)
            try Self.requireDirectory(finalizationDescriptor, identity: finalizationIdentity)
            try Self.requireDirectory(stagingDescriptor, identity: stagingIdentity)
            try Self.requireDirectory(
                stagingSnapshotsDescriptor,
                identity: stagingSnapshotsIdentity
            )
            try Self.requireDirectory(snapshotsDescriptor, identity: snapshotsIdentity)

            let currentApplicationSupport = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard currentApplicationSupport >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            defer { _ = Darwin.close(currentApplicationSupport) }
            try Self.requireDirectory(
                currentApplicationSupport,
                identity: applicationSupportIdentity
            )

            let data = try Self.openDirectory(
                parent: currentApplicationSupport,
                name: "FieldEvidenceData"
            )
            defer { _ = Darwin.close(data) }
            let generations = try Self.openDirectory(parent: data, name: "generations")
            defer { _ = Darwin.close(generations) }
            let currentGeneration = try Self.openDirectory(
                parent: generations,
                name: generationName
            )
            defer { _ = Darwin.close(currentGeneration) }
            try Self.requireDirectory(currentGeneration, identity: generationIdentity)
            let currentStaging = try Self.openDirectory(
                parent: currentGeneration,
                name: ".staging"
            )
            defer { _ = Darwin.close(currentStaging) }
            try Self.requireDirectory(currentStaging, identity: stagingIdentity)
            let currentStagingSnapshots = try Self.openDirectory(
                parent: currentStaging,
                name: "snapshots"
            )
            defer { _ = Darwin.close(currentStagingSnapshots) }
            try Self.requireDirectory(
                currentStagingSnapshots,
                identity: stagingSnapshotsIdentity
            )
            let currentSnapshots = try Self.openDirectory(
                parent: currentGeneration,
                name: "snapshots"
            )
            defer { _ = Darwin.close(currentSnapshots) }
            try Self.requireDirectory(currentSnapshots, identity: snapshotsIdentity)

            let currentOperations = try Self.openDirectory(
                parent: currentApplicationSupport,
                name: "FieldEvidenceOperations"
            )
            defer { _ = Darwin.close(currentOperations) }
            try Self.requireDirectory(currentOperations, identity: operationsIdentity)
            let currentFinalization = try Self.openDirectory(
                parent: currentOperations,
                name: "finalization"
            )
            defer { _ = Darwin.close(currentFinalization) }
            try Self.requireDirectory(currentFinalization, identity: finalizationIdentity)
        }

        func enumeratedIntentNames() throws -> [String] {
            let duplicate = Darwin.openat(
                finalizationDescriptor,
                ".",
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
                if duplicate >= 0 { _ = Darwin.close(duplicate) }
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            defer { _ = Darwin.closedir(directory) }
            var result: [String] = []
            errno = 0
            while let entry = Darwin.readdir(directory) {
                var tuple = entry.pointee.d_name
                let capacity = MemoryLayout.size(ofValue: tuple)
                let name = withUnsafePointer(to: &tuple) { pointer in
                    pointer.withMemoryRebound(
                        to: CChar.self,
                        capacity: capacity
                    ) { String(cString: $0) }
                }
                if name != "." && name != ".." {
                    result.append(name)
                }
                errno = 0
            }
            guard errno == 0 else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            return result.sorted()
        }

        func itemInfo(parent: Int32, name: String) throws -> stat? {
            guard Self.validComponent(name) else {
                throw FinalizationIntentStoreError.unsafePath
            }
            var info = stat()
            if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
                return info
            }
            if errno == ENOENT { return nil }
            throw FinalizationIntentStoreError.fileOperationFailed
        }

        func readGenerationRegularFile(
            components: [String]
        ) throws -> (data: Data, identity: Identity) {
            try withGenerationParent(components: components) { parent, name in
                try readRegularFile(parent: parent, name: name)
            }
        }

        func readRegularFile(
            parent: Int32,
            name: String
        ) throws -> (data: Data, identity: Identity) {
            guard Self.validComponent(name) else {
                throw FinalizationIntentStoreError.unsafePath
            }
            let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                if errno == ENOENT { throw FinalizationIntentStoreError.itemMissing }
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            var before = stat()
            guard Darwin.fstat(descriptor, &before) == 0,
                  Self.isRegular(before),
                  before.st_nlink == 1 else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            let identity = Identity(device: before.st_dev, inode: before.st_ino)
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    Darwin.read(descriptor, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
            }
            var after = stat()
            guard Darwin.fstat(descriptor, &after) == 0,
                   Self.isRegular(after),
                   after.st_nlink == 1,
                   Identity(device: after.st_dev, inode: after.st_ino) == identity,
                  before.st_size == after.st_size,
                  data.count == Int(after.st_size) else {
                throw FinalizationIntentStoreError.bytesMismatch
            }
            return (data, identity)
        }

        func ensureGenerationDirectory(components: [String]) throws {
            switch components {
            case [".staging", "snapshots"]:
                try verifyDirectoryPolicy(
                    .stagingDirectory,
                    descriptor: stagingDescriptor,
                    expected: stagingIdentity,
                    url: generationRootURL.appendingPathComponent(
                        ".staging",
                        isDirectory: true
                    )
                )
                try verifyDirectoryPolicy(
                    .stagingDirectory,
                    descriptor: stagingSnapshotsDescriptor,
                    expected: stagingSnapshotsIdentity,
                    url: generationRootURL.appendingPathComponent(
                        ".staging/snapshots",
                        isDirectory: true
                    )
                )
            case ["snapshots"]:
                try verifyDirectoryPolicy(
                    .durableDirectory,
                    descriptor: snapshotsDescriptor,
                    expected: snapshotsIdentity,
                    url: generationRootURL.appendingPathComponent(
                        "snapshots",
                        isDirectory: true
                    )
                )
            default:
                throw FinalizationIntentStoreError.unsafePath
            }
            try verify()
        }

        private func verifyDirectoryPolicy(
            _ kind: OwnedFileKindV1,
            descriptor: Int32,
            expected: Identity,
            url: URL
        ) throws {
            try ProtectedFilePolicyV1.verify(kind, at: url)
            guard try Self.directoryIdentity(descriptor) == expected,
                  try Self.directoryIdentity(at: url) == expected else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
        }

        func withGenerationParent<T>(
            components: [String],
            _ body: (Int32, String) throws -> T
        ) throws -> T {
            guard !components.isEmpty, components.allSatisfy(Self.validComponent),
                  let name = components.last else {
                throw FinalizationIntentStoreError.unsafePath
            }
            let parent: Int32
            switch Array(components.dropLast()) {
            case [".staging", "snapshots"]:
                parent = stagingSnapshotsDescriptor
            case ["snapshots"]:
                parent = snapshotsDescriptor
            default:
                throw FinalizationIntentStoreError.unsafePath
            }
            return try body(parent, name)
        }

        func generationFileURL(components: [String]) throws -> URL {
            guard !components.isEmpty, components.allSatisfy(Self.validComponent) else {
                throw FinalizationIntentStoreError.unsafePath
            }
            var url = generationRootURL
            for component in components {
                url.appendPathComponent(component, isDirectory: false)
            }
            return url
        }

        func finalizationFileURL(name: String) throws -> URL {
            guard Self.validComponent(name) else {
                throw FinalizationIntentStoreError.unsafePath
            }
            return applicationSupportURL
                .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
                .appendingPathComponent("finalization", isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
        }

        func verifyGenerationFilePolicy(
            _ kind: OwnedFileKindV1,
            components: [String]
        ) throws {
            try withGenerationParent(components: components) { parent, name in
                try verifyRegularFilePolicy(
                    kind,
                    parent: parent,
                    name: name,
                    policyURL: try generationFileURL(components: components)
                )
            }
        }

        func verifyRegularFilePolicy(
            _ kind: OwnedFileKindV1,
            parent: Int32,
            name: String,
            policyURL: URL
        ) throws {
            do {
                try verify()
                let expected = try Self.regularIdentity(parent: parent, name: name)
                try ProtectedFilePolicyV1.verify(kind, at: policyURL)
                guard try Self.regularIdentity(parent: parent, name: name) == expected,
                      try Self.regularIdentity(at: policyURL) == expected else {
                    throw FinalizationIntentStoreError.notOwned
                }
                try verify()
            } catch let error as FinalizationIntentStoreError {
                throw error
            } catch {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
        }

        private var generationRootURL: URL {
            applicationSupportURL
                .appendingPathComponent("FieldEvidenceData", isDirectory: true)
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(generationName, isDirectory: true)
        }

        @discardableResult
        func createRegularFile(
            _ data: Data,
            parent: Int32,
            name: String,
            policyKind: OwnedFileKindV1,
            policyURL: URL
        ) throws -> Identity {
            guard Self.validComponent(name) else {
                throw FinalizationIntentStoreError.unsafePath
            }
            let descriptor = Darwin.openat(
                parent,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                mode_t(0o600)
            )
            guard descriptor >= 0 else {
                if errno == EEXIST { throw FinalizationIntentStoreError.itemAlreadyExists }
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            let identity: Identity
            do {
                identity = try Self.regularIdentity(descriptor)
            } catch {
                _ = Darwin.close(descriptor)
                throw error
            }
            var descriptorIsOpen = true
            do {
                try ProtectedFilePolicyV1.applyAndVerify(
                    policyKind,
                    at: policyURL,
                    authorityCheck: {
                        try verify()
                        guard try Self.regularIdentity(descriptor) == identity,
                              try Self.regularIdentity(at: policyURL) == identity else {
                            throw FinalizationIntentStoreError.notOwned
                        }
                    }
                )
                try data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    var offset = 0
                    while offset < raw.count {
                        let written = Darwin.write(
                            descriptor,
                            base.advanced(by: offset),
                            raw.count - offset
                        )
                        if written > 0 {
                            offset += written
                        } else if written < 0, errno == EINTR {
                            continue
                        } else {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                    }
                }
                guard Darwin.fsync(descriptor) == 0 else {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
                let closeResult = Darwin.close(descriptor)
                descriptorIsOpen = false
                guard closeResult == 0, Darwin.fsync(parent) == 0 else {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
            } catch {
                if descriptorIsOpen {
                    _ = Darwin.close(descriptor)
                }
                do {
                    try quarantineAndRemove(
                        parent: parent,
                        name: name,
                        expectedIdentity: identity,
                        expectedData: nil,
                        verifyCurrentAuthority: false
                    )
                } catch {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
                throw error
            }
            return identity
        }

        func replaceExactRegularFile(
            parent: Int32,
            name: String,
            expectedData: Data,
            replacementData: Data,
            policyURL: URL,
            afterMutation: () -> Void
        ) throws {
            try verifyRegularFilePolicy(
                .journal,
                parent: parent,
                name: name,
                policyURL: policyURL
            )
            let original = try readRegularFile(parent: parent, name: name)
            guard original.data == expectedData else {
                throw FinalizationIntentStoreError.notOwned
            }
            let temporary = ".replace-\(UUID().uuidString.lowercased())"
            let temporaryURL = policyURL
                .deletingLastPathComponent()
                .appendingPathComponent(temporary, isDirectory: false)
            try createRegularFile(
                replacementData,
                parent: parent,
                name: temporary,
                policyKind: .journalTemporary,
                policyURL: temporaryURL
            )
            let replacement = try readRegularFile(parent: parent, name: temporary)
            var swapped = false
            do {
                guard Darwin.renameatx_np(
                    parent,
                    temporary,
                    parent,
                    name,
                    UInt32(RENAME_SWAP)
                ) == 0 else {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
                swapped = true
                afterMutation()
                guard Darwin.fsync(parent) == 0 else {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
                try ProtectedFilePolicyV1.applyAndVerify(
                    .journal,
                    at: policyURL,
                    authorityCheck: {
                        try verify()
                        guard try readRegularFile(parent: parent, name: name).identity
                                == replacement.identity,
                              try Self.regularIdentity(at: policyURL)
                                == replacement.identity else {
                            throw FinalizationIntentStoreError.notOwned
                        }
                    }
                )
                let current = try readRegularFile(parent: parent, name: name)
                let displaced = try readRegularFile(parent: parent, name: temporary)
                guard current.identity == replacement.identity,
                      current.data == replacementData,
                      displaced.identity == original.identity,
                      displaced.data == expectedData else {
                    throw FinalizationIntentStoreError.notOwned
                }
                try verify()
                try quarantineAndRemove(
                    parent: parent,
                    name: temporary,
                    expectedIdentity: original.identity,
                    expectedData: expectedData,
                    verifyCurrentAuthority: false
                )
            } catch {
                var cleanupFailed = false
                if swapped,
                   let current = try? readRegularFile(parent: parent, name: name),
                   current.identity == replacement.identity {
                    if Darwin.renameatx_np(
                        parent,
                        temporary,
                        parent,
                        name,
                        UInt32(RENAME_SWAP)
                    ) != 0 || Darwin.fsync(parent) != 0 {
                        cleanupFailed = true
                    }
                }
                // If the displaced temporary leaf was concurrently removed,
                // recreate the exact previously verified journal under the
                // private name and swap it back. This preserves recovery truth
                // even when this replacement follows a database commit.
                if let current = try? readRegularFile(parent: parent, name: name),
                   current.identity == replacement.identity,
                   current.data == replacementData {
                    if isMissing(parent: parent, name: temporary) {
                        do {
                            try createRegularFile(
                                expectedData,
                                parent: parent,
                                name: temporary,
                                policyKind: .journalTemporary,
                                policyURL: temporaryURL
                            )
                        } catch {
                            cleanupFailed = true
                        }
                    }
                    if let restored = try? readRegularFile(parent: parent, name: temporary),
                       restored.data == expectedData {
                        if Darwin.renameatx_np(
                            parent,
                            temporary,
                            parent,
                            name,
                            UInt32(RENAME_SWAP)
                        ) != 0 || Darwin.fsync(parent) != 0 {
                            cleanupFailed = true
                        }
                    }
                }
                // If exact restoration was impossible, remove only our exact
                // replacement rather than leave mutation-owned journal bytes.
                if let current = try? readRegularFile(parent: parent, name: name),
                   current.identity == replacement.identity,
                   current.data == replacementData {
                    do {
                        try quarantineAndRemove(
                            parent: parent,
                            name: name,
                            expectedIdentity: replacement.identity,
                            expectedData: replacementData,
                            verifyCurrentAuthority: false
                        )
                    } catch {
                        cleanupFailed = true
                    }
                }
                if let temporaryFile = try? readRegularFile(parent: parent, name: temporary),
                   temporaryFile.identity == replacement.identity {
                    do {
                        try quarantineAndRemove(
                            parent: parent,
                            name: temporary,
                            expectedIdentity: replacement.identity,
                            expectedData: replacementData,
                            verifyCurrentAuthority: false
                        )
                    } catch {
                        cleanupFailed = true
                    }
                } else if let temporaryFile = try? readRegularFile(
                    parent: parent,
                    name: temporary
                ), temporaryFile.identity == original.identity,
                   temporaryFile.data == expectedData {
                    // If a foreign leaf replaced the canonical journal after
                    // the swap, preserve it and remove only the exact prior
                    // mutation journal displaced to our private temp name.
                    do {
                        try quarantineAndRemove(
                            parent: parent,
                            name: temporary,
                            expectedIdentity: original.identity,
                            expectedData: expectedData,
                            verifyCurrentAuthority: false
                        )
                    } catch {
                        cleanupFailed = true
                    }
                }
                if cleanupFailed {
                    throw FinalizationIntentStoreError.fileOperationFailed
                }
                throw error
            }
        }

        func promoteNoReplace(
            sourceComponents: [String],
            destinationComponents: [String],
            expectedByteCount: Int,
            expectedSHA256: String,
            policyURL: URL,
            afterMutation: () -> Void
        ) throws {
            try withGenerationParent(components: sourceComponents) { sourceParent, sourceName in
                try withGenerationParent(
                    components: destinationComponents
                ) { destinationParent, destinationName in
                    let sourcePolicyURL = try generationFileURL(
                        components: sourceComponents
                    )
                    try verifyRegularFilePolicy(
                        .stagingFile,
                        parent: sourceParent,
                        name: sourceName,
                        policyURL: sourcePolicyURL
                    )
                    let source = try readRegularFile(parent: sourceParent, name: sourceName)
                    guard source.data.count == expectedByteCount,
                          Self.sha256(source.data) == expectedSHA256 else {
                        throw FinalizationIntentStoreError.notOwned
                    }
                    guard case nil = try itemInfo(
                        parent: destinationParent,
                        name: destinationName
                    ) else {
                        throw FinalizationIntentStoreError.itemAlreadyExists
                    }
                    guard Darwin.renameatx_np(
                        sourceParent,
                        sourceName,
                        destinationParent,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    ) == 0 else {
                        throw FinalizationIntentStoreError.fileOperationFailed
                    }
                    do {
                        guard Darwin.fsync(sourceParent) == 0,
                              Darwin.fsync(destinationParent) == 0 else {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                        afterMutation()
                        try ProtectedFilePolicyV1.applyAndVerify(
                            .reportSnapshot,
                            at: policyURL,
                            authorityCheck: {
                                try verify()
                                guard try readRegularFile(
                                    parent: destinationParent,
                                    name: destinationName
                                ).identity == source.identity,
                                      try Self.regularIdentity(at: policyURL)
                                        == source.identity else {
                                    throw FinalizationIntentStoreError.notOwned
                                }
                            }
                        )
                        let destination = try readRegularFile(
                            parent: destinationParent,
                            name: destinationName
                        )
                        guard destination.identity == source.identity,
                              destination.data == source.data else {
                            throw FinalizationIntentStoreError.notOwned
                        }
                        try verify()
                    } catch {
                        var cleanupFailed = false
                        if let destination = try? readRegularFile(
                            parent: destinationParent,
                            name: destinationName
                        ), destination.identity == source.identity,
                           isMissing(parent: sourceParent, name: sourceName) {
                            let restored = Darwin.renameatx_np(
                                destinationParent,
                                destinationName,
                                sourceParent,
                                sourceName,
                                UInt32(RENAME_EXCL)
                            ) == 0
                            guard restored else {
                                cleanupFailed = true
                                throw FinalizationIntentStoreError.fileOperationFailed
                            }
                            guard Darwin.fsync(destinationParent) == 0,
                                  Darwin.fsync(sourceParent) == 0 else {
                                cleanupFailed = true
                                throw FinalizationIntentStoreError.fileOperationFailed
                            }
                            do {
                                try ProtectedFilePolicyV1.applyAndVerify(
                                    .stagingFile,
                                    at: sourcePolicyURL,
                                    authorityCheck: {
                                        try verify()
                                        guard try Self.regularIdentity(
                                            parent: sourceParent,
                                            name: sourceName
                                        ) == source.identity,
                                              try Self.regularIdentity(
                                                at: sourcePolicyURL
                                              ) == source.identity else {
                                            throw FinalizationIntentStoreError.notOwned
                                        }
                                    }
                                )
                            } catch {
                                do {
                                    try quarantineAndRemove(
                                        parent: sourceParent,
                                        name: sourceName,
                                        expectedIdentity: source.identity,
                                        expectedData: source.data,
                                        verifyCurrentAuthority: false
                                    )
                                } catch {
                                    cleanupFailed = true
                                }
                                cleanupFailed = true
                            }
                        }
                        if cleanupFailed {
                            throw FinalizationIntentStoreError.fileOperationFailed
                        }
                        throw error
                    }
                }
            }
        }

        func quarantineAndRemove(
            parent: Int32,
            name: String,
            expectedIdentity: Identity,
            expectedData: Data?,
            verifyCurrentAuthority: Bool = true
        ) throws {
            let current = try readRegularFile(parent: parent, name: name)
            guard current.identity == expectedIdentity,
                  expectedData.map({ $0 == current.data }) ?? true else {
                throw FinalizationIntentStoreError.notOwned
            }
            let quarantine = LivePrivatePreparation.isReservedName(name)
                ? ".live-finalization-\(UUID().uuidString.lowercased()).tmp"
                : ".remove-\(UUID().uuidString.lowercased())"
            guard Darwin.renameatx_np(
                parent,
                name,
                parent,
                quarantine,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            let moved: (data: Data, identity: Identity)
            do {
                moved = try readRegularFile(parent: parent, name: quarantine)
                guard moved.identity == expectedIdentity,
                      expectedData.map({ $0 == moved.data }) ?? true else {
                    throw FinalizationIntentStoreError.notOwned
                }
                if verifyCurrentAuthority {
                    try verify()
                }
            } catch {
                restoreQuarantined(
                    parent: parent,
                    quarantine: quarantine,
                    name: name
                )
                throw error
            }
            guard Darwin.unlinkat(parent, quarantine, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                restoreQuarantined(
                    parent: parent,
                    quarantine: quarantine,
                    name: name
                )
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            var after = stat()
            guard Darwin.fstatat(
                parent,
                quarantine,
                &after,
                AT_SYMLINK_NOFOLLOW
            ) == -1, errno == ENOENT else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
        }

        private func restoreQuarantined(
            parent: Int32,
            quarantine: String,
            name: String
        ) {
            _ = Darwin.renameatx_np(
                parent,
                quarantine,
                parent,
                name,
                UInt32(RENAME_EXCL)
            )
            _ = Darwin.fsync(parent)
        }

        static func isRegular(_ info: stat) -> Bool {
            (info.st_mode & S_IFMT) == S_IFREG
        }

        private static func isDirectory(_ info: stat) -> Bool {
            (info.st_mode & S_IFMT) == S_IFDIR
        }

        private static func validComponent(_ value: String) -> Bool {
            !value.isEmpty && value != "." && value != ".." && !value.contains("/")
        }

        private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0, isDirectory(info) else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            return Identity(device: info.st_dev, inode: info.st_ino)
        }

        private static func directoryIdentity(at url: URL) throws -> Identity {
            let descriptor = Darwin.open(
                url.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            defer { _ = Darwin.close(descriptor) }
            return try directoryIdentity(descriptor)
        }

        private static func regularIdentity(_ descriptor: Int32) throws -> Identity {
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0, isRegular(info) else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            return Identity(device: info.st_dev, inode: info.st_ino)
        }

        private static func regularIdentity(at url: URL) throws -> Identity {
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            defer { _ = Darwin.close(descriptor) }
            return try regularIdentity(descriptor)
        }

        private static func regularIdentity(
            parent: Int32,
            name: String
        ) throws -> Identity {
            let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            defer { _ = Darwin.close(descriptor) }
            return try regularIdentity(descriptor)
        }

        private static func requireDirectory(
            _ descriptor: Int32,
            identity: Identity
        ) throws {
            guard try directoryIdentity(descriptor) == identity else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
        }

        private static func requireCanonicalGeneration(
            applicationSupportURL: URL,
            applicationSupportIdentity: Identity,
            generationName: String,
            generationIdentity: Identity
        ) throws {
            let applicationSupport = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard applicationSupport >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            defer { _ = Darwin.close(applicationSupport) }
            try requireDirectory(applicationSupport, identity: applicationSupportIdentity)
            let data = try openDirectory(parent: applicationSupport, name: "FieldEvidenceData")
            defer { _ = Darwin.close(data) }
            let generations = try openDirectory(parent: data, name: "generations")
            defer { _ = Darwin.close(generations) }
            let generation = try openDirectory(parent: generations, name: generationName)
            defer { _ = Darwin.close(generation) }
            try requireDirectory(generation, identity: generationIdentity)
        }

        private static func openDirectory(parent: Int32, name: String) throws -> Int32 {
            guard validComponent(name) else {
                throw FinalizationIntentStoreError.unsafePath
            }
            let descriptor = Darwin.openat(
                parent,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw FinalizationIntentStoreError.generationRootInvalid
            }
            return descriptor
        }

        private static func openOrCreateDirectory(parent: Int32, name: String) throws -> Int32 {
            do {
                return try openDirectory(parent: parent, name: name)
            } catch {
                guard errno == ENOENT else {
                    throw FinalizationIntentStoreError.generationRootInvalid
                }
                let creationResult = Darwin.mkdirat(parent, name, mode_t(0o700))
                if creationResult == 0 {
                    guard Darwin.fsync(parent) == 0 else {
                        throw FinalizationIntentStoreError.generationRootInvalid
                    }
                } else if errno != EEXIST {
                    throw FinalizationIntentStoreError.generationRootInvalid
                }
                return try openDirectory(parent: parent, name: name)
            }
        }

        private static func sha256(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        private func isMissing(parent: Int32, name: String) -> Bool {
            do {
                if case nil = try itemInfo(parent: parent, name: name) {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
    }
}
// MARK: - C30 operating-context finalization boundary

extension FinalizationIntentStore {
    static func validateOperatingContextBeforeFinalization(
        _ projection: C30EvidenceContextReportReferenceV1
    ) throws -> C30EvidenceContextReportReferenceV1 {
        try projection.validate()
        guard projection.frozenDisplay,
              C30OperatingContextConsumerPolicyV1.originalsAndManualOfflinePathPreserved else {
            throw C30ConsumerProjectionFailureV1.invalidValue
        }
        return projection
    }

    static let c30OperatingContextFinalizationIsAmendOnly = true
    static let c30OperatingContextDoesNotPromoteDerivedFacts = true
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Finalization_FinalizationIntentStore {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift", role: .finalization)
}

enum C31LightingFinalizationIntentBoundaryV1 {
    static let finalizationUsesRecordedLightingRoots = true
    static let historicReportDisplayIsImmutable = true
    static let derivedProjectionIsNotCanonical = true
    static let licensedCriterionTextIsNotGenerated = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        let roots = try LightingBackupRecordSetV1.decode(records)
        let workspaces = roots.systems.map(\.workspaceID)
            + roots.observations.map(\.workspaceID)
            + roots.issues.map(\.workspaceID)
            + roots.plans.map(\.workspaceID)
            + roots.claims.map(\.workspaceID)
        guard workspaces.allSatisfy({ $0 == workspaceID }),
              finalizationUsesRecordedLightingRoots,
              historicReportDisplayIsImmutable,
              derivedProjectionIsNotCanonical,
              licensedCriterionTextIsNotGenerated else {
            throw LightingContractFailureV1.wrongWorkspace
        }
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Finalization_FinalizationIntentStore {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Finalization_FinalizationIntentStore_swift {
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
enum C45AssetLabelBoundary_Row155 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Finalization_FinalizationIntentStore_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C48 portable-review finalization boundary

enum C48PortableReviewFinalizationIntentBoundaryV1 {
    static let externalResponseIsNotFinalizationIntent = true
    static let responseDispositionIsNotCompletionTruth = true
    static let capabilityBytesEnterFinalization = false
    static let capabilityProofBytesEnterFinalization = false
    static let responseBodyEntersFinalization = false
    static let rawRequestResponseBytesEnterFinalization = false
    static let existingFinalizationIntentStoreRemainsCanonical = true
}

// MARK: - C49 work-resource finalization admission

enum C49WorkResourceFinalizationIntentBoundaryV1 {
    static let finalizationConsumesDerivedSnapshot = true
    static let finalizationDoesNotCreateASecondWriter = true
    static let customerSafeDirectCostPreviewRequiresOptIn = true
    static let formulaSafeCSVIsTheOnlyCSVRoute = true
    static let rawStockAndLiveInventoryClaimsEnterIntent = false

    static func prepare(
        _ projection: C49WorkResourceReportProjectionV1,
        format: String = "OPEN_JSON"
    ) throws -> C49WorkResourceProjectionEnvelopeV1 {
        let envelope = try C49WorkResourceProjectionSupportV1.envelope(
            projection,
            format: format
        )
        try envelope.validate(expectedFormat: format)
        return envelope
    }

    static func validateCustomerSafe(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws {
        _ = try C49WorkResourcePrivacyTransformBoundaryV1.customerSafe(projection)
    }

    static func formulaSafeCSV(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> Data {
        try C49WorkResourceReportSnapshotEncoderBoundaryV1.encodeFormulaSafeCSV(projection)
    }
}

/// Finalization consumes validated canonical/report projections only.  A C50
/// preview or scratch terminal receipt cannot finalize, persist, or alter a
/// historic report snapshot.
enum C50IncumbentFileExchangeFinalizationBoundaryV1 {
    static let previewIsZeroWrite = true
    static let scratchTerminalReceiptCannotFinalize = true
    static let appendOnlySnapshotHistory = true
    static let deterministicOpenJSONAndPDFInputs = true
    static let formulaSafeCSVRequired = true
    static let directCostProjectionIsAbsent = C50IncumbentFileExchangeLifecycleBoundaryV1.directCostProjectionIsAbsent
    static let rawSourceBytesAndLiveInventoryClaimsExcluded = true

    static func validate() -> Bool {
        previewIsZeroWrite
            && scratchTerminalReceiptCannotFinalize
            && appendOnlySnapshotHistory
            && deterministicOpenJSONAndPDFInputs
            && formulaSafeCSVRequired
            && directCostProjectionIsAbsent
            && rawSourceBytesAndLiveInventoryClaimsExcluded
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Finalization_FinalizationIntentStore_swift {
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
