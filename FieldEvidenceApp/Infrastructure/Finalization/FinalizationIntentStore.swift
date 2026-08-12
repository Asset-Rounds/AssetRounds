import CryptoKit
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

actor FinalizationIntentStore {
    private let generationRootURL: URL
    private let fileManager: FileManager

    init(
        generationRootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func discoverRecoverableFinalizations() throws -> [RecoverableFinalization] {
        let generationID = try validatedGenerationID()
        let roots = try validatedRoots(generationID: generationID)
        let rootType = try itemType(
            at: roots.operationsRootURL.appendingPathComponent("finalization", isDirectory: true),
            within: roots.applicationSupportURL
        )
        guard let rootType else { return [] }
        guard rootType == .typeDirectory else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        let root = roots.operationsRootURL.appendingPathComponent("finalization", isDirectory: true)
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
        } catch {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
        return try names.map { name in
            guard name.count == 41, name.hasSuffix(".json"),
                  let mutationID = UUID(uuidString: String(name.dropLast(5))),
                  mutationID.uuidString.lowercased() + ".json" == name else {
                throw FinalizationIntentStoreError.intentInvalid
            }
            let url = root.appendingPathComponent(name)
            guard try itemType(at: url, within: roots.applicationSupportURL) == .typeRegular else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
            let intent: FinalizationIntentV1
            do {
                intent = try FinalizationContractDecoderV1().decodeIntent(data)
            } catch {
                throw FinalizationIntentStoreError.intentInvalid
            }
            guard intent.finalizationMutationID == mutationID,
                  intent.generationID == generationID,
                  intent.schemaVersion == 1 else {
                throw FinalizationIntentStoreError.intentInvalid
            }
            let paths = try validatedPaths(for: intent, roots: roots)
            let stage = try validatedSnapshotIfPresent(
                at: paths.stagingSnapshotURL,
                intent: intent
            )
            let final = try validatedSnapshotIfPresent(
                at: paths.finalSnapshotURL,
                intent: intent
            )
            if let stage, let final, stage.data != final.data {
                throw FinalizationIntentStoreError.bytesMismatch
            }
            return RecoverableFinalization(
                intent: intent,
                intentRelativePath: paths.intentRelativePath,
                snapshotStagingRelativePath: intent.snapshotStagingRelativePath,
                snapshotFinalRelativePath: intent.snapshotFinalRelativePath,
                snapshotByteCount: (final ?? stage)?.data.count ?? 0,
                snapshot: (final ?? stage)?.snapshot,
                hasStagingSnapshot: stage != nil,
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
        let prepared = PreparedFinalization(
            intent: recovery.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshotSHA256: recovery.intent.snapshotSHA256
        )
        _ = try promoteSnapshot(prepared)
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

    func removeIdenticalStagingForRecovery(
        _ recovery: RecoverableFinalization
    ) throws -> RecoverableFinalization {
        guard recovery.hasStagingSnapshot, recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        let roots = try validatedRoots(generationID: recovery.intent.generationID)
        let paths = try validatedPaths(for: recovery.intent, roots: roots)
        try verifyRecovery(recovery, paths: paths, roots: roots)
        try removeOwnedFileIfMatching(
            at: paths.stagingSnapshotURL,
            expectedByteCount: recovery.snapshotByteCount,
            expectedSHA256: recovery.intent.snapshotSHA256,
            within: generationRootURL
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
        let promoted = PromotedFinalization(
            intent: recovery.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshotSHA256: recovery.intent.snapshotSHA256
        )
        let advanced = try advance(promoted, to: phase)
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
        let roots = try validatedRoots(generationID: recovery.intent.generationID)
        let paths = try validatedPaths(for: recovery.intent, roots: roots)
        try verifyIntent(recovery.intent, at: paths.intentURL, roots: roots)
        try removeIntentIfMatching(recovery.intent, at: paths.intentURL, roots: roots)
    }

    func rollbackForRecovery(_ recovery: RecoverableFinalization) throws {
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        let promoted = PromotedFinalization(
            intent: recovery.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshotSHA256: recovery.intent.snapshotSHA256
        )
        try rollbackUncommitted(promoted)
    }

    func cleanupCommittedForRecovery(_ recovery: RecoverableFinalization) throws {
        guard recovery.hasFinalSnapshot else {
            throw FinalizationIntentStoreError.itemMissing
        }
        let committed = PromotedFinalization(
            intent: recovery.intent,
            intentRelativePath: recovery.intentRelativePath,
            snapshotStagingRelativePath: recovery.snapshotStagingRelativePath,
            snapshotFinalRelativePath: recovery.snapshotFinalRelativePath,
            snapshotByteCount: recovery.snapshotByteCount,
            snapshotSHA256: recovery.intent.snapshotSHA256
        )
        try cleanupCommitted(committed)
    }

    func prepare(
        intent: FinalizationIntentV1,
        snapshot: EncodedReportSnapshotV1
    ) throws -> PreparedFinalization {
        let roots = try validatedRoots(generationID: intent.generationID)
        let paths = try validatedPaths(for: intent, roots: roots)
        guard intent.phase == .prepared,
              intent.schemaVersion == 1,
              intent.snapshotSHA256 == snapshot.sha256,
              sha256(snapshot.data) == snapshot.sha256 else {
            throw FinalizationIntentStoreError.intentInvalid
        }
        guard try itemType(at: paths.intentURL, within: roots.applicationSupportURL) == nil,
              try itemType(at: paths.stagingSnapshotURL, within: generationRootURL) == nil,
              try itemType(at: paths.finalSnapshotURL, within: generationRootURL) == nil else {
            throw FinalizationIntentStoreError.itemAlreadyExists
        }

        try ensureDirectory(paths.operationsRootURL, within: roots.applicationSupportURL)
        try ensureDirectory(paths.finalizationRootURL, within: roots.applicationSupportURL)
        try ensureDirectory(paths.stagingRootURL, within: generationRootURL)
        try ensureDirectory(paths.stagingSnapshotsRootURL, within: generationRootURL)

        do {
            try snapshot.data.write(to: paths.stagingSnapshotURL, options: .atomic)
            try verifyRegularFile(
                at: paths.stagingSnapshotURL,
                expectedData: snapshot.data,
                expectedSHA256: snapshot.sha256,
                within: generationRootURL
            )
            try writeAndVerifyIntent(intent, at: paths.intentURL, roots: roots)
        } catch {
            try? removeOwnedFileIfMatching(
                at: paths.stagingSnapshotURL,
                expectedByteCount: snapshot.data.count,
                expectedSHA256: snapshot.sha256,
                within: generationRootURL
            )
            try? removeIntentIfMatching(intent, at: paths.intentURL, roots: roots)
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
        let roots = try validatedRoots(generationID: prepared.intent.generationID)
        let paths = try validatedPaths(for: prepared.intent, roots: roots)
        try verifyHandle(prepared, paths: paths, roots: roots)
        guard prepared.intent.phase == .prepared else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        guard try itemType(at: paths.finalSnapshotURL, within: generationRootURL) == nil else {
            throw FinalizationIntentStoreError.itemAlreadyExists
        }
        try ensureDirectory(paths.snapshotsRootURL, within: generationRootURL)

        var didPromote = false
        do {
            try fileManager.moveItem(
                at: paths.stagingSnapshotURL,
                to: paths.finalSnapshotURL
            )
            didPromote = true
            try verifyRegularFile(
                at: paths.finalSnapshotURL,
                expectedByteCount: prepared.snapshotByteCount,
                expectedSHA256: prepared.snapshotSHA256,
                within: generationRootURL
            )
        } catch {
            if didPromote {
                try? removeOwnedFileIfMatching(
                    at: paths.finalSnapshotURL,
                    expectedByteCount: prepared.snapshotByteCount,
                    expectedSHA256: prepared.snapshotSHA256,
                    within: generationRootURL
                )
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
        let roots = try validatedRoots(generationID: promoted.intent.generationID)
        let paths = try validatedPaths(for: promoted.intent, roots: roots)
        try verifyPromotedHandle(promoted, paths: paths, roots: roots)
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
        try writeAndVerifyIntent(advanced, at: paths.intentURL, roots: roots)
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
        let roots = try validatedRoots(generationID: committed.intent.generationID)
        let paths = try validatedPaths(for: committed.intent, roots: roots)
        try verifyPromotedHandle(committed, paths: paths, roots: roots)
        try removeOwnedFileIfMatching(
            at: paths.stagingSnapshotURL,
            expectedByteCount: committed.snapshotByteCount,
            expectedSHA256: committed.snapshotSHA256,
            within: generationRootURL
        )
        try removeIntentIfMatching(committed.intent, at: paths.intentURL, roots: roots)
    }

    func rollbackUncommitted(_ promoted: PromotedFinalization) throws {
        guard promoted.intent.phase != .databaseCommitted else {
            throw FinalizationIntentStoreError.phaseInvalid
        }
        let roots = try validatedRoots(generationID: promoted.intent.generationID)
        let paths = try validatedPaths(for: promoted.intent, roots: roots)
        try verifyIntent(promoted.intent, at: paths.intentURL, roots: roots)
        try removeOwnedFileIfMatching(
            at: paths.finalSnapshotURL,
            expectedByteCount: promoted.snapshotByteCount,
            expectedSHA256: promoted.snapshotSHA256,
            within: generationRootURL
        )
        try removeOwnedFileIfMatching(
            at: paths.stagingSnapshotURL,
            expectedByteCount: promoted.snapshotByteCount,
            expectedSHA256: promoted.snapshotSHA256,
            within: generationRootURL
        )
        try removeIntentIfMatching(promoted.intent, at: paths.intentURL, roots: roots)
    }

    private struct ValidatedRoots {
        let applicationSupportURL: URL
        let operationsRootURL: URL
    }

    private struct Paths {
        let intentRelativePath: String
        let operationsRootURL: URL
        let finalizationRootURL: URL
        let intentURL: URL
        let stagingRootURL: URL
        let stagingSnapshotsRootURL: URL
        let stagingSnapshotURL: URL
        let snapshotsRootURL: URL
        let finalSnapshotURL: URL
    }

    private func validatedRoots(generationID: UUID) throws -> ValidatedRoots {
        guard try rawItemType(at: generationRootURL) == .typeDirectory else {
            throw FinalizationIntentStoreError.generationRootInvalid
        }
        let canonicalID = generationID.uuidString.lowercased()
        guard generationRootURL.lastPathComponent == canonicalID,
              generationRootURL.deletingLastPathComponent().lastPathComponent == "generations",
              generationRootURL.deletingLastPathComponent()
                .deletingLastPathComponent().lastPathComponent == "FieldEvidenceData" else {
            throw FinalizationIntentStoreError.generationRootInvalid
        }
        let dataRootURL = generationRootURL.deletingLastPathComponent().deletingLastPathComponent()
        let applicationSupportURL = dataRootURL.deletingLastPathComponent().standardizedFileURL
        guard !applicationSupportURL.path.isEmpty,
              try rawItemType(at: applicationSupportURL) == .typeDirectory,
              isInside(generationRootURL, root: applicationSupportURL) else {
            throw FinalizationIntentStoreError.generationRootInvalid
        }
        return ValidatedRoots(
            applicationSupportURL: applicationSupportURL,
            operationsRootURL: applicationSupportURL.appendingPathComponent(
                "FieldEvidenceOperations",
                isDirectory: true
            )
        )
    }

    private func validatedGenerationID() throws -> UUID {
        guard let value = UUID(uuidString: generationRootURL.lastPathComponent),
              value.uuidString.lowercased() == generationRootURL.lastPathComponent else {
            throw FinalizationIntentStoreError.generationRootInvalid
        }
        return value
    }

    private func validatedSnapshotIfPresent(
        at url: URL,
        intent: FinalizationIntentV1
    ) throws -> (data: Data, snapshot: ReportSnapshotV1)? {
        guard let type = try itemType(at: url, within: generationRootURL) else { return nil }
        guard type == .typeRegular else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
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
        roots: ValidatedRoots
    ) throws {
        guard recovery.intentRelativePath == paths.intentRelativePath,
              recovery.snapshotStagingRelativePath == recovery.intent.snapshotStagingRelativePath,
              recovery.snapshotFinalRelativePath == recovery.intent.snapshotFinalRelativePath else {
            throw FinalizationIntentStoreError.notOwned
        }
        try verifyIntent(recovery.intent, at: paths.intentURL, roots: roots)
        if recovery.hasStagingSnapshot {
            try verifyRegularFile(
                at: paths.stagingSnapshotURL,
                expectedByteCount: recovery.snapshotByteCount,
                expectedSHA256: recovery.intent.snapshotSHA256,
                within: generationRootURL
            )
        }
        if recovery.hasFinalSnapshot {
            try verifyRegularFile(
                at: paths.finalSnapshotURL,
                expectedByteCount: recovery.snapshotByteCount,
                expectedSHA256: recovery.intent.snapshotSHA256,
                within: generationRootURL
            )
        }
    }

    private func validatedPaths(
        for intent: FinalizationIntentV1,
        roots: ValidatedRoots
    ) throws -> Paths {
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
        let finalizationRoot = roots.operationsRootURL.appendingPathComponent(
            "finalization",
            isDirectory: true
        )
        return Paths(
            intentRelativePath: "FieldEvidenceOperations/finalization/\(mutation).json",
            operationsRootURL: roots.operationsRootURL,
            finalizationRootURL: finalizationRoot,
            intentURL: finalizationRoot.appendingPathComponent("\(mutation).json"),
            stagingRootURL: generationRootURL.appendingPathComponent(".staging", isDirectory: true),
            stagingSnapshotsRootURL: generationRootURL
                .appendingPathComponent(".staging", isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true),
            stagingSnapshotURL: generationRootURL.appendingPathComponent(expectedStaging),
            snapshotsRootURL: generationRootURL.appendingPathComponent("snapshots", isDirectory: true),
            finalSnapshotURL: generationRootURL.appendingPathComponent(expectedFinal)
        )
    }

    private func verifyHandle(
        _ prepared: PreparedFinalization,
        paths: Paths,
        roots: ValidatedRoots
    ) throws {
        guard prepared.intentRelativePath == paths.intentRelativePath,
              prepared.snapshotStagingRelativePath == prepared.intent.snapshotStagingRelativePath,
              prepared.snapshotFinalRelativePath == prepared.intent.snapshotFinalRelativePath,
              prepared.snapshotSHA256 == prepared.intent.snapshotSHA256 else {
            throw FinalizationIntentStoreError.notOwned
        }
        try verifyIntent(prepared.intent, at: paths.intentURL, roots: roots)
        try verifyRegularFile(
            at: paths.stagingSnapshotURL,
            expectedByteCount: prepared.snapshotByteCount,
            expectedSHA256: prepared.snapshotSHA256,
            within: generationRootURL
        )
    }

    private func verifyPromotedHandle(
        _ promoted: PromotedFinalization,
        paths: Paths,
        roots: ValidatedRoots
    ) throws {
        guard promoted.intentRelativePath == paths.intentRelativePath,
              promoted.snapshotStagingRelativePath == promoted.intent.snapshotStagingRelativePath,
              promoted.snapshotFinalRelativePath == promoted.intent.snapshotFinalRelativePath,
              promoted.snapshotSHA256 == promoted.intent.snapshotSHA256 else {
            throw FinalizationIntentStoreError.notOwned
        }
        try verifyIntent(promoted.intent, at: paths.intentURL, roots: roots)
        try verifyRegularFile(
            at: paths.finalSnapshotURL,
            expectedByteCount: promoted.snapshotByteCount,
            expectedSHA256: promoted.snapshotSHA256,
            within: generationRootURL
        )
    }

    private func writeAndVerifyIntent(
        _ intent: FinalizationIntentV1,
        at url: URL,
        roots: ValidatedRoots
    ) throws {
        let encoded: EncodedFinalizationContractV1
        do {
            encoded = try FinalizationContractEncoderV1().encodeIntent(intent)
        } catch {
            throw FinalizationIntentStoreError.intentInvalid
        }
        do {
            try encoded.data.write(to: url, options: .atomic)
        } catch {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
        try verifyRegularFile(
            at: url,
            expectedData: encoded.data,
            expectedSHA256: encoded.sha256,
            within: roots.applicationSupportURL
        )
    }

    private func verifyIntent(
        _ intent: FinalizationIntentV1,
        at url: URL,
        roots: ValidatedRoots
    ) throws {
        let encoded: EncodedFinalizationContractV1
        do {
            encoded = try FinalizationContractEncoderV1().encodeIntent(intent)
        } catch {
            throw FinalizationIntentStoreError.intentInvalid
        }
        try verifyRegularFile(
            at: url,
            expectedData: encoded.data,
            expectedSHA256: encoded.sha256,
            within: roots.applicationSupportURL
        )
    }

    private func removeIntentIfMatching(
        _ intent: FinalizationIntentV1,
        at url: URL,
        roots: ValidatedRoots
    ) throws {
        guard try itemType(at: url, within: roots.applicationSupportURL) != nil else { return }
        try verifyIntent(intent, at: url, roots: roots)
        try removeFile(url)
    }

    private func removeOwnedFileIfMatching(
        at url: URL,
        expectedByteCount: Int,
        expectedSHA256: String,
        within root: URL
    ) throws {
        guard try itemType(at: url, within: root) != nil else { return }
        try verifyRegularFile(
            at: url,
            expectedByteCount: expectedByteCount,
            expectedSHA256: expectedSHA256,
            within: root
        )
        try removeFile(url)
    }

    private func verifyRegularFile(
        at url: URL,
        expectedData: Data? = nil,
        expectedByteCount: Int? = nil,
        expectedSHA256: String,
        within root: URL
    ) throws {
        guard try itemType(at: url, within: root) == .typeRegular else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
        guard expectedData.map({ $0 == data }) ?? true,
              expectedByteCount.map({ $0 == data.count }) ?? true,
              sha256(data) == expectedSHA256 else {
            throw FinalizationIntentStoreError.bytesMismatch
        }
    }

    private func ensureDirectory(_ url: URL, within root: URL) throws {
        switch try itemType(at: url, within: root) {
        case nil:
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            } catch {
                throw FinalizationIntentStoreError.fileOperationFailed
            }
        case .some(.typeDirectory):
            break
        case .some:
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
    }

    private func itemType(at url: URL, within root: URL) throws -> FileAttributeType? {
        guard isInside(url, root: root) else {
            throw FinalizationIntentStoreError.unsafePath
        }
        guard try rawItemType(at: root) == .typeDirectory else {
            throw FinalizationIntentStoreError.itemTypeInvalid
        }
        let relative = url.standardizedFileURL.path
            .dropFirst(root.standardizedFileURL.path.count)
            .split(separator: "/")
        var current = root.standardizedFileURL
        for (index, component) in relative.enumerated() {
            current.appendPathComponent(String(component))
            guard let type = try rawItemType(at: current) else { return nil }
            if index == relative.count - 1 { return type }
            guard type == .typeDirectory else {
                throw FinalizationIntentStoreError.itemTypeInvalid
            }
        }
        return .typeDirectory
    }

    private func rawItemType(at url: URL) throws -> FileAttributeType? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
    }

    private func removeFile(_ url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FinalizationIntentStoreError.fileOperationFailed
        }
    }

    private func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
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
}
