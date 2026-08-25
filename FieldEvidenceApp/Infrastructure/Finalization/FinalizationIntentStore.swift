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
    private let authorityResult: Result<PinnedAuthority, FinalizationIntentStoreError>
    private let failureInjection: FinalizationIntentStoreFailureInjection?
    private let authorityBarrier: FinalizationIntentStoreAuthorityBarrier?

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
        _ = fileManager // Kept only for source compatibility; never storage authority.
        do {
            authorityResult = .success(
                try PinnedAuthority(
                    generationRootURL: root,
                    expectedGenerationRootIdentity: expectedGenerationRootIdentity
                )
            )
        } catch let error as FinalizationIntentStoreError {
            authorityResult = .failure(error)
        } catch {
            authorityResult = .failure(.generationRootInvalid)
        }
    }

    func discoverRecoverableFinalizations() throws -> [RecoverableFinalization] {
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
                  intent.schemaVersion == 1 else {
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
        guard recovery.intent.phase == .prepared,
              recovery.hasStagingSnapshot,
              !recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let promoted = try promoteSnapshot(
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
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        let advanced = try advance(
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
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        try rollbackUncommitted(
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
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        try cleanupCommitted(
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

    func prepare(
        intent: FinalizationIntentV1,
        snapshot: EncodedReportSnapshotV1
    ) throws -> PreparedFinalization {
        let authority = try requireAuthority()
        guard intent.generationID == authority.generationID else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        let paths = try validatedPaths(for: intent)
        guard intent.phase == .prepared,
              intent.schemaVersion == 1,
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

        do {
            guard failureInjection?.consume(.snapshotStagingWrite) != true else {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            try createRegularFile(
                snapshot.data,
                components: paths.stagingComponents,
                authority: authority
            )
            try verifyRegularFile(
                components: paths.stagingComponents,
                expectedData: snapshot.data,
                expectedSHA256: snapshot.sha256,
                authority: authority
            )
            try createAndVerifyIntent(intent, name: paths.intentName, authority: authority)
            try authority.verify()
        } catch {
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
            try rollbackUncommitted(promoted)
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
            throw FinalizationIntentStoreError.intentInvalid
        }
    }

    private func requireAuthority() throws -> PinnedAuthority {
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

        func createRegularFile(
            _ data: Data,
            parent: Int32,
            name: String,
            policyKind: OwnedFileKindV1,
            policyURL: URL
        ) throws {
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
            let quarantine = ".remove-\(UUID().uuidString.lowercased())"
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
