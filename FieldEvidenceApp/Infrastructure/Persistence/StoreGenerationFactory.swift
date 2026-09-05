import CryptoKit
import Darwin
import Foundation
import SwiftData

struct StoreApplicationSupportIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

enum StoreGenerationFailure: Error, Equatable {
    case dataPointerInvalid
    case dataGenerationMissing
}

private enum StorePointerSchemaRegistry {
    static let legacyCurrentVersion = 1
    static let manifestCurrentVersion = 2
    static let identityCurrentVersion = 3
    static let retiredVersion = 1

    static func requireCurrent(_ version: Int) throws {
        guard version == legacyCurrentVersion
                || version == manifestCurrentVersion
                || version == identityCurrentVersion else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    static func requireRetired(_ version: Int) throws {
        guard version == retiredVersion else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }
}

private extension StoreGenerationFactory {
    @MainActor
    private func beginMigration(
        sourcePointer: CurrentGenerationPointerV3,
        sourcePointerData: Data,
        retired: RetiredPointerV1,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        processID: UUID
    ) throws -> StoreGenerationSession {
        try sourcePointer.validate()
        guard (2...36).contains(sourcePointer.storeSchemaVersion),
              let sourceID = canonicalUUID(from: sourcePointer.generationID),
              !retired.generationIDs.contains(sourcePointer.generationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let sourceManifest = try store.loadManifest(
            targetGenerationID: sourceID,
            expectedDigest: sourcePointer.generationManifestSHA256
        )
        let sourceRelease: PersistentSchemaReleaseV1
        let targetRelease: PersistentSchemaReleaseV1
        switch sourcePointer.storeSchemaVersion {
        case 2:
            sourceRelease = .v2
            targetRelease = .v3
        case 3:
            sourceRelease = .v3
            targetRelease = .v4
        case 4:
            sourceRelease = .v4
            targetRelease = .v5
        case 5:
            sourceRelease = .v5
            targetRelease = .v6
        case 6:
            sourceRelease = .v6
            targetRelease = .v7
        case 7:
            sourceRelease = .v7
            targetRelease = .v8
        case 8:
            sourceRelease = .v8
            targetRelease = .v9
        case 9:
            sourceRelease = .v9
            targetRelease = .v10
        case 10:
            sourceRelease = .v10
            targetRelease = .v11
        case 11:
            sourceRelease = .v11
            targetRelease = .v12
        case 12:
            sourceRelease = .v12
            targetRelease = .v13
        case 13:
            sourceRelease = .v13
            targetRelease = .v14
        case 14:
            sourceRelease = .v14
            targetRelease = .v15
        case 15:
            sourceRelease = .v15
            targetRelease = .v16
        case 16:
            sourceRelease = .v16
            targetRelease = .v17
        case 17:
            sourceRelease = .v17
            targetRelease = .v18
        case 18:
            sourceRelease = .v18
            targetRelease = .v19
        case 19:
            sourceRelease = .v19
            targetRelease = .v20
        case 20:
            sourceRelease = .v20
            targetRelease = .v21
        case 21:
            sourceRelease = .v21
            targetRelease = .v22
        case 22:
            sourceRelease = .v22
            targetRelease = .v23
        case 23:
            sourceRelease = .v23
            targetRelease = .v24
        case 24:
            sourceRelease = .v24
            targetRelease = .v25
        case 25:
            sourceRelease = .v25
            targetRelease = .v26
        case 26:
            sourceRelease = .v26
            targetRelease = .v27
        case 27:
            sourceRelease = .v27
            targetRelease = .v28
        case 28:
            sourceRelease = .v28
            targetRelease = .v29
        case 29:
            sourceRelease = .v29
            targetRelease = .v30
        case 30:
            sourceRelease = .v30
            targetRelease = .v31
        case 31:
            sourceRelease = .v31
            targetRelease = .v32
        case 32:
            sourceRelease = .v32
            targetRelease = .v33
        case 33:
            sourceRelease = .v33
            targetRelease = .v34
        case 34:
            sourceRelease = .v34
            targetRelease = .v35
        case 35:
            sourceRelease = .v35
            targetRelease = .v36
        case 36:
            sourceRelease = .v36
            targetRelease = .v37
        case 37:
            sourceRelease = .v37
            targetRelease = .v38
        case 38:
            sourceRelease = .v38
            targetRelease = .v39
        case 39:
            sourceRelease = .v39
            targetRelease = .v40
        case 40:
            sourceRelease = .v40
            targetRelease = .v41
        case 41:
            sourceRelease = .v41
            targetRelease = .v42
        case 42:
            sourceRelease = .v42
            targetRelease = .v43
        case 43:
            sourceRelease = .v43
            targetRelease = .v44
        case 44:
            sourceRelease = .v44
            targetRelease = .v45
        case 45:
            sourceRelease = .v45
            targetRelease = .v46
        case 46:
            sourceRelease = .v46
            targetRelease = .v47
        case 47:
            sourceRelease = .v47
            targetRelease = .v48
        case 48:
            sourceRelease = .v48
            targetRelease = .v49
        case 49:
            sourceRelease = .v49
            targetRelease = .v50
        case 50:
            sourceRelease = .v50
            targetRelease = .v53
        default: throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        guard sourceManifest.storeSchemaRelease == sourceRelease,
              sourceManifest.semanticSHA256 != nil else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        let identities = migrationIdentitySource ?? .live
        let targetID = identities.makeGenerationID()
        guard sourceManifest.migrationID != targetID,
              sourceID != targetID else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let authority = try makeRestoreGenerationAuthority()
        try authority.requireNoRestoreJournal()
        try authority.requireNoEraseAuthority()
        let snapshot = try authority.snapshotInstalledGeneration(id: sourceID)
        guard snapshot.files == sourceManifest.files,
              snapshot.frozenIdentityDigest == sourceManifest.frozenIdentityDigest else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        let pointerDigest = StoreMigrationCanonicalJSONV1.sha256(sourcePointerData)
        let prepared = try StoreMigrationJournalV1(
            migrationID: sourceManifest.migrationID,
            sourceGenerationID: sourceID,
            targetGenerationID: targetID,
            sourceRelease: sourceRelease,
            targetRelease: targetRelease,
            sourcePointerDigest: pointerDigest,
            sourceTreeDigest: snapshot.sourceTreeDigest,
            sourceManifestDigest: sourcePointer.generationManifestSHA256,
            frozenIdentityDigest: snapshot.frozenIdentityDigest,
            expectedPointerDigest: pointerDigest,
            originatingProcessID: processID,
            phase: .prepared,
            targetWritePossible: false,
            pointerPublicationAttempted: false
        )
        try reachMigrationBoundary(.beforePreparedJournalWrite)
        try store.createPreparedMigration(journal: prepared, sourceManifest: sourceManifest)
        try reachMigrationBoundary(.afterPreparedJournalWrite)
        return try resumeMigration(
            prepared,
            dataRootURL: dataRootURL,
            store: store,
            processID: processID
        )
    }

    @MainActor
    private func beginMigration(
        sourcePointer: CurrentPointerV1,
        sourcePointerData: Data,
        retired: RetiredPointerV1,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        processID: UUID
    ) throws -> StoreGenerationSession {
        guard sourcePointer.schemaVersion
                == StorePointerSchemaRegistry.legacyCurrentVersion,
              let sourceID = canonicalUUID(from: sourcePointer.generationID),
              !retired.generationIDs.contains(sourcePointer.generationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let identities = migrationIdentitySource ?? .live
        let migrationID = identities.makeMigrationID()
        let targetID = identities.makeGenerationID()
        guard migrationID != sourceID,
              migrationID != targetID,
              sourceID != targetID else {
            throw StoreMigrationFailure.invalidIdentity
        }

        do {
            let authority = try makeRestoreGenerationAuthority()
            try authority.requireNoRestoreJournal()
            try authority.requireNoEraseAuthority()
            let sourceSnapshot = try authority.snapshotInstalledGeneration(id: sourceID)
            let sourceManifest = try StoreGenerationManifestV1(
                generationID: sourceID,
                predecessorGenerationID: syntheticPredecessor(excluding: sourceID),
                migrationID: migrationID,
                storeSchemaRelease: .v1,
                semanticSHA256: nil,
                frozenIdentityDigest: sourceSnapshot.frozenIdentityDigest,
                files: sourceSnapshot.files
            )
            let sourceManifestDigest = try sourceManifest.canonicalSHA256()
            let pointerDigest = StoreMigrationCanonicalJSONV1.sha256(sourcePointerData)
            let prepared = try StoreMigrationJournalV1(
                migrationID: migrationID,
                sourceGenerationID: sourceID,
                targetGenerationID: targetID,
                sourceRelease: .v1,
                targetRelease: .v2,
                sourcePointerDigest: pointerDigest,
                sourceTreeDigest: sourceSnapshot.sourceTreeDigest,
                sourceManifestDigest: sourceManifestDigest,
                frozenIdentityDigest: sourceSnapshot.frozenIdentityDigest,
                expectedPointerDigest: pointerDigest,
                originatingProcessID: processID,
                phase: .prepared,
                targetWritePossible: false,
                pointerPublicationAttempted: false
            )
            try reachMigrationBoundary(.beforePreparedJournalWrite)
            try store.createPreparedMigration(
                journal: prepared,
                sourceManifest: sourceManifest
            )
            try reachMigrationBoundary(.afterPreparedJournalWrite)
            return try resumeMigration(
                prepared,
                dataRootURL: dataRootURL,
                store: store,
                processID: processID
            )
        } catch let failure as StoreMigrationFailure {
            throw failure
        } catch {
            if let reason = migrationMaintenanceReason(for: error) {
                throw StoreMigrationFailure.maintenanceRequired(reason)
            }
            throw error
        }
    }

    @MainActor
    private func resumeMigration(
        _ persisted: StoreMigrationJournalV1,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        processID: UUID
    ) throws -> StoreGenerationSession {
        do {
            return try resumeMigrationForward(
                persisted,
                dataRootURL: dataRootURL,
                store: store,
                processID: processID
            )
        } catch let failure as StoreMigrationFailure {
            let effectivePhase = (try? store.loadJournal())?.phase
                ?? persisted.phase
            switch failure {
            case .injectedFault, .maintenanceRequired:
                throw failure
            default:
                if effectivePhase.isAtLeast(.v2WriteAuthorized) {
                    throw StoreMigrationFailure.maintenanceRequired(
                        .forwardFixRequired
                    )
                }
                throw failure
            }
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw StoreMigrationFailure.maintenanceRequired(
                .protectedDataUnavailable
            )
        } catch {
            let effectivePhase = (try? store.loadJournal())?.phase
                ?? persisted.phase
            if let reason = migrationMaintenanceReason(for: error) {
                throw StoreMigrationFailure.maintenanceRequired(reason)
            }
            if effectivePhase.isAtLeast(.v2WriteAuthorized) {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            throw error
        }
    }

    private func migrationMaintenanceReason(
        for error: Error
    ) -> StoreMigrationMaintenanceReasonV1? {
        var current = error as NSError
        for _ in 0..<8 {
            if ProtectedFilePolicyV1.isProtectedDataUnavailable(current) {
                return .protectedDataUnavailable
            }
            if current.domain == NSPOSIXErrorDomain,
               current.code == ENOSPC {
                return .insufficientStorage
            }
            if current.domain == NSCocoaErrorDomain,
               current.code == NSFileWriteOutOfSpaceError {
                return .insufficientStorage
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey]
                    as? NSError,
                  underlying !== current else {
                break
            }
            current = underlying
        }
        return nil
    }

    @MainActor
    private func resumeMigrationForward(
        _ persisted: StoreMigrationJournalV1,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        processID: UUID
    ) throws -> StoreGenerationSession {
        var journal = persisted
        try journal.validate()
        let authority = try makeRestoreGenerationAuthority()
        try authority.requireNoRestoreJournal()
        try authority.requireNoEraseAuthority()

        while true {
            try requireMigrationPointerState(journal)
            switch journal.phase {
            case .prepared:
                let sourceManifest = try requireSourceManifest(
                    journal,
                    store: store
                )
                let sourceSnapshot = try authority.snapshotInstalledGeneration(
                    id: journal.sourceGenerationID
                )
                guard sourceSnapshot.sourceTreeDigest == journal.sourceTreeDigest,
                      sourceSnapshot.frozenIdentityDigest == journal.frozenIdentityDigest,
                      sourceSnapshot.files == sourceManifest.files else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                let presence = try authority.presence(id: journal.targetGenerationID)
                guard !presence.installed else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                if presence.staging {
                    try authority.removeStagingGeneration(id: journal.targetGenerationID)
                }
                try reachMigrationBoundary(.beforeSourceClone)
                try authority.createStagingGeneration(id: journal.targetGenerationID)
                let cloned = try authority.cloneInstalledGeneration(
                    sourceID: journal.sourceGenerationID,
                    toStagingGeneration: journal.targetGenerationID
                )
                guard cloned.sourceTreeDigest == journal.sourceTreeDigest,
                      cloned.frozenIdentityDigest == journal.frozenIdentityDigest,
                      cloned.files == sourceManifest.files else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                let sourceSemantic = try semanticExport(
                    at: restoreStagingGenerationURL(
                        id: journal.targetGenerationID
                    ).appendingPathComponent(Self.modelStoreName),
                    release: journal.sourceRelease,
                    markerMigrationID: nil
                )
                if journal.sourceRelease != .v1,
                   sourceManifest.semanticSHA256
                    != StoreMigrationCanonicalJSONV1.sha256(sourceSemantic) {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                let next = try migrationJournal(
                    journal,
                    phase: .sourceCloned,
                    sourceSemanticDigest:
                        StoreMigrationCanonicalJSONV1.sha256(sourceSemantic)
                )
                try store.replaceJournal(expected: journal, with: next)
                journal = next
                try reachMigrationBoundary(.afterSourceClone)

            case .sourceCloned:
                let targetRoot = restoreStagingGenerationURL(
                    id: journal.targetGenerationID
                )
                if processID != journal.originatingProcessID {
                    let recoveredPresence = try authority.presence(
                        id: journal.targetGenerationID
                    )
                    guard !recoveredPresence.installed else {
                        throw StoreMigrationFailure.maintenanceRequired(
                            .targetMismatch
                        )
                    }
                    if recoveredPresence.staging {
                        try authority.removeStagingGeneration(
                            id: journal.targetGenerationID
                        )
                    }
                    try authority.createStagingGeneration(
                        id: journal.targetGenerationID
                    )
                    let recoveredClone = try authority.cloneInstalledGeneration(
                        sourceID: journal.sourceGenerationID,
                        toStagingGeneration: journal.targetGenerationID
                    )
                    guard recoveredClone.sourceTreeDigest
                            == journal.sourceTreeDigest,
                          recoveredClone.frozenIdentityDigest
                            == journal.frozenIdentityDigest else {
                        throw StoreMigrationFailure.maintenanceRequired(
                            .sourceMismatch
                        )
                    }
                }
                guard try authority.presence(id: journal.targetGenerationID).staging,
                      try generationTreeDigest(at: targetRoot)
                        == journal.sourceTreeDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                let recoveredSourceSemantic = try semanticExport(
                    at: targetRoot.appendingPathComponent(Self.modelStoreName),
                    release: journal.sourceRelease,
                    markerMigrationID: nil
                )
                guard StoreMigrationCanonicalJSONV1.sha256(
                    recoveredSourceSemantic
                ) == journal.sourceSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try reachMigrationBoundary(.beforeV2WriteAuthorization)
                let next = try migrationJournal(
                    journal,
                    phase: .v2WriteAuthorized,
                    targetWritePossible: true
                )
                try store.replaceJournal(expected: journal, with: next)
                journal = next
                try reachMigrationBoundary(.afterV2WriteAuthorization)

            case .v2WriteAuthorized:
                let targetRoot = restoreStagingGenerationURL(
                    id: journal.targetGenerationID
                )
                guard try authority.presence(id: journal.targetGenerationID).staging else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetUnavailable)
                }
                try reachMigrationBoundary(.beforeV2Validation)
                let targetSemantic = try migrateAndValidateClone(
                    at: targetRoot,
                    sourceRelease: journal.sourceRelease,
                    targetRelease: journal.targetRelease,
                    migrationID: journal.migrationID,
                    sourceGenerationID: journal.sourceGenerationID,
                    targetGenerationID: journal.targetGenerationID,
                    expectedSemanticDigest: try requiredSourceSemanticDigest(
                        journal
                    )
                )
                try protectGeneration(
                    at: targetRoot,
                    staging: true,
                    requireModel: true
                )
                let targetManifest = try StoreGenerationManifestV1(
                    generationID: journal.targetGenerationID,
                    predecessorGenerationID: journal.sourceGenerationID,
                    migrationID: journal.migrationID,
                    storeSchemaRelease: journal.targetRelease,
                    semanticSHA256: targetSemantic,
                    frozenIdentityDigest: try frozenIdentityDigest(for: targetRoot),
                    files: try generationFileDigests(at: targetRoot, durable: true)
                )
                let targetManifestDigest = try store.writeManifest(targetManifest)
                let desiredPointerDigest = StoreMigrationCanonicalJSONV1.sha256(
                    try desiredMigrationPointerData(
                        journal: journal,
                        manifestDigest: targetManifestDigest
                    )
                )
                let next = try migrationJournal(
                    journal,
                    phase: .v2Validated,
                    targetManifestDigest: targetManifestDigest,
                    targetSemanticDigest: targetSemantic,
                    desiredPointerDigest: desiredPointerDigest
                )
                try store.replaceJournal(expected: journal, with: next)
                journal = next
                try reachMigrationBoundary(.afterV2Validation)

            case .v2Validated:
                let targetManifest = try requireTargetManifest(
                    journal,
                    store: store
                )
                let presence = try authority.presence(id: journal.targetGenerationID)
                guard presence.staging != presence.installed else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                if presence.staging {
                    try requireTargetGenerationSnapshot(
                        journal,
                        manifest: targetManifest,
                        at: restoreStagingGenerationURL(
                            id: journal.targetGenerationID
                        )
                    )
                    try reachMigrationBoundary(.beforeGenerationInstall)
                    try authority.installStagingGeneration(id: journal.targetGenerationID)
                }
                try authority.requireInstalledGeneration(id: journal.targetGenerationID)
                try requireTargetGenerationSnapshot(
                    journal,
                    manifest: targetManifest,
                    at: installedGenerationURL(id: journal.targetGenerationID)
                )
                let next = try migrationJournal(
                    journal,
                    phase: .generationInstalled
                )
                try store.replaceJournal(expected: journal, with: next)
                journal = next
                try reachMigrationBoundary(.afterGenerationInstall)

            case .generationInstalled:
                try authority.requireInstalledGeneration(id: journal.targetGenerationID)
                try requireTargetGenerationSnapshot(
                    journal,
                    manifest: try requireTargetManifest(journal, store: store),
                    at: installedGenerationURL(id: journal.targetGenerationID)
                )
                if !journal.pointerPublicationAttempted {
                    let next = try migrationJournal(
                        journal,
                        phase: .generationInstalled,
                        publicationProcessID: processID,
                        pointerPublicationAttempted: true
                    )
                    try store.replaceJournal(expected: journal, with: next)
                    journal = next
                    continue
                }
                try reachMigrationBoundary(.beforePointerPublication)
                try publishMigrationPointerForwardOnly(journal, store: store)
                let next = try migrationJournal(
                    journal,
                    phase: .pointerPublished
                )
                try store.replaceJournal(expected: journal, with: next)
                journal = next
                try reachMigrationBoundary(.afterPointerPublication)

            case .pointerPublished:
                try reachMigrationBoundary(.beforeFirstLaunchValidation)
                let session = try openPublishedMigrationTarget(
                    journal,
                    dataRootURL: dataRootURL,
                    store: store
                )
                let next = try migrationJournal(
                    journal,
                    phase: .firstLaunchValidated,
                    firstValidationProcessID: processID
                )
                try store.replaceJournal(expected: journal, with: next)
                try reachMigrationBoundary(.afterFirstLaunchValidation)
                return session

            case .firstLaunchValidated:
                guard processID != journal.publicationProcessID,
                      processID != journal.originatingProcessID,
                      processID != journal.firstValidationProcessID else {
                    return try openPublishedMigrationTarget(
                        journal,
                        dataRootURL: dataRootURL,
                        store: store
                    )
                }
                try reachMigrationBoundary(.beforeSecondLaunchValidation)
                let session = try openPublishedMigrationTarget(
                    journal,
                    dataRootURL: dataRootURL,
                    store: store
                )
                let next = try migrationJournal(
                    journal,
                    phase: .secondLaunchValidated,
                    secondValidationProcessID: processID
                )
                try store.replaceJournal(expected: journal, with: next)
                journal = next
                try reachMigrationBoundary(.afterSecondLaunchValidation)
                try finishMigration(
                    journal,
                    authority: authority,
                    store: store
                )
                return try continueIntoActiveReleaseIfNeeded(
                    after: journal,
                    validatedSession: session,
                    authority: authority,
                    dataRootURL: dataRootURL,
                    store: store,
                    processID: processID
                )

            case .secondLaunchValidated:
                let session = try openPublishedMigrationTarget(
                    journal,
                    dataRootURL: dataRootURL,
                    store: store
                )
                try finishMigration(
                    journal,
                    authority: authority,
                    store: store
                )
                return try continueIntoActiveReleaseIfNeeded(
                    after: journal,
                    validatedSession: session,
                    authority: authority,
                    dataRootURL: dataRootURL,
                    store: store,
                    processID: processID
                )
            }
        }
    }

    /// Closes one accepted adjacent migration and starts the next without
    /// recursively re-entering startup. A V2 session must never escape once
    /// V3 is the active release because ledger-aware callers can only use a
    /// V3 ModelContext.
    @MainActor
    private func continueIntoActiveReleaseIfNeeded(
        after completed: StoreMigrationJournalV1,
        validatedSession: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        processID: UUID
    ) throws -> StoreGenerationSession {
        guard completed.targetRelease != PersistentSchemaReleaseRegistryV1.activeRelease else {
            return validatedSession
        }
              guard [.v2, .v3, .v4, .v5, .v6, .v7, .v8, .v9, .v10, .v11, .v12, .v13, .v14, .v15, .v16, .v17, .v18, .v19, .v20, .v21, .v22, .v23, .v24, .v25, .v26,.v27,.v28,.v29,.v30,.v31,.v32,.v33,.v34,.v35,.v36,.v37,.v38,.v39,.v40,.v41,.v42,.v43,.v44,.v45,.v46,.v47,.v48,.v49,.v50,.v51,.v52,.v53].contains(completed.targetRelease),
              PersistentSchemaReleaseRegistryV1.activeRelease == .v53 else {
            throw StoreMigrationFailure.maintenanceRequired(.futureVersion)
        }
        let current = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        let completedVersion: Int
        switch completed.targetRelease {
        case .v2: completedVersion = 2
        case .v3: completedVersion = 3
        case .v4: completedVersion = 4
        case .v5: completedVersion = 5
        case .v6: completedVersion = 6
        case .v7: completedVersion = 7
        case .v8: completedVersion = 8
        case .v9: completedVersion = 9
        case .v10: completedVersion = 10
        case .v11: completedVersion = 11
        case .v12: completedVersion = 12
        case .v13: completedVersion = 13
        case .v14: completedVersion = 14
        case .v15: completedVersion = 15
        case .v16: completedVersion = 16
        case .v17: completedVersion = 17
        case .v18: completedVersion = 18
        case .v19: completedVersion = 19
        case .v20: completedVersion = 20
        case .v21: completedVersion = 21
        case .v22: completedVersion = 22
        case .v23: completedVersion = 23
        case .v24: completedVersion = 24
        case .v25: completedVersion = 25
        case .v26: completedVersion = 26
        case .v27: completedVersion = 27
        case .v28: completedVersion = 28
        case .v29: completedVersion = 29
        case .v30: completedVersion = 30
        case .v31: completedVersion = 31
        case .v32: completedVersion = 32
        case .v33: completedVersion = 33
        case .v34: completedVersion = 34
        case .v35: completedVersion = 35
        case .v36: completedVersion = 36
        case .v37: completedVersion = 37
        case .v38: completedVersion = 38
        case .v39: completedVersion = 39
        case .v40: completedVersion = 40
        case .v41: completedVersion = 41
        case .v42: completedVersion = 42
        case .v43: completedVersion = 43
        case .v44: completedVersion = 44
        case .v45: completedVersion = 45
        case .v46: completedVersion = 46
        case .v47: completedVersion = 47
        case .v48: completedVersion = 48
        case .v49: completedVersion = 49
        case .v50: completedVersion = 50
        case .v51: completedVersion = 51
        case .v52: completedVersion = 52
        case .v53: completedVersion = 53
        default: throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        guard case .v3(let pointer, let pointerData) = current,
              pointer.storeSchemaVersion == completedVersion,
              canonicalUUID(from: pointer.generationID)
                == completed.targetGenerationID else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let retiredIDs = try authority.retiredGenerationIDs()
        let retired = RetiredPointerV1(
            generationIDs: retiredIDs
                .map { canonicalString(for: $0) }
                .sorted(),
            schemaVersion: StorePointerSchemaRegistry.retiredVersion
        )
        return try beginMigration(
            sourcePointer: pointer,
            sourcePointerData: pointerData,
            retired: retired,
            dataRootURL: dataRootURL,
            store: store,
            processID: processID
        )
    }

    @MainActor
    private func finishMigration(
        _ journal: StoreMigrationJournalV1,
        authority: StoreRestoreGenerationAuthority,
        store: StoreMigrationJournalStoreV1
    ) throws {
        let retired = try authority.retiredGenerationIDs()
        if !retired.contains(journal.sourceGenerationID) {
            let registry = try makeGenerationLeaseRegistry()
            try registry.withExclusiveGenerationMutationLock {
                try authority.retireGeneration(
                    oldID: journal.sourceGenerationID,
                    currentID: journal.targetGenerationID
                )
            }
        }
        try reachMigrationBoundary(.beforeJournalRemoval)
        try store.removeJournal(expected: journal)
        try reachMigrationBoundary(.afterJournalRemoval)
        let current = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        if case .v2(let pointer, _) = current {
            _ = try enrichCurrentPointer(pointer)
        }
    }

    @MainActor
    private func openPublishedMigrationTarget(
        _ journal: StoreMigrationJournalV1,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1
    ) throws -> StoreGenerationSession {
        let envelope = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        guard StoreMigrationCanonicalJSONV1.sha256(envelope.data)
                == journal.desiredPointerDigest,
              envelope.generationID
                == canonicalString(for: journal.targetGenerationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        switch envelope {
        case .v2(let pointer, _):
            guard journal.targetRelease == .v2,
                  pointer.generationManifestSHA256 == journal.targetManifestDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            return try openValidatedV2Current(
                pointer: pointer,
                dataRootURL: dataRootURL,
                store: store,
                identity: try compatibilityIdentity(for: pointer)
            )
        case .v3(let pointer, _):
            guard [.v3, .v4, .v5, .v6, .v7, .v8, .v9, .v10, .v11, .v12, .v13, .v14, .v15, .v16, .v17, .v18, .v19, .v20, .v21, .v22, .v23, .v24, .v25, .v26, .v27, .v28, .v29, .v30, .v31, .v32, .v33, .v34, .v35, .v36, .v37, .v38, .v39, .v40, .v41, .v42, .v43, .v44, .v45, .v46].contains(journal.targetRelease),
                  pointer.generationManifestSHA256 == journal.targetManifestDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            return try openValidatedV3Current(
                pointer: pointer,
                dataRootURL: dataRootURL,
                store: store
            )
        case .legacy:
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
    }

    private func requireMigrationPointerState(
        _ journal: StoreMigrationJournalV1
    ) throws {
        let envelope = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        let data = envelope.data
        let digest = StoreMigrationCanonicalJSONV1.sha256(data)
        if journal.phase.isAtLeast(.pointerPublished) {
            guard digest == journal.desiredPointerDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
        } else if journal.phase == .generationInstalled,
                  journal.pointerPublicationAttempted {
            guard digest == journal.expectedPointerDigest
                    || digest == journal.desiredPointerDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
        } else {
            guard digest == journal.expectedPointerDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
        }
    }

    private func requireSourceManifest(
        _ journal: StoreMigrationJournalV1,
        store: StoreMigrationJournalStoreV1
    ) throws -> StoreGenerationManifestV1 {
        let manifest = try store.loadManifest(
            targetGenerationID: journal.sourceGenerationID,
            expectedDigest: journal.sourceManifestDigest
        )
        guard manifest.generationID == journal.sourceGenerationID,
              manifest.migrationID == journal.migrationID,
              manifest.storeSchemaRelease == journal.sourceRelease,
              manifest.frozenIdentityDigest == journal.frozenIdentityDigest,
              (journal.sourceRelease == .v1
                ? manifest.semanticSHA256 == nil
                : manifest.semanticSHA256 != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        return manifest
    }

    private func requiredSourceSemanticDigest(
        _ journal: StoreMigrationJournalV1
    ) throws -> String {
        guard let digest = journal.sourceSemanticDigest,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(digest) else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        return digest
    }

    private func requireTargetManifest(
        _ journal: StoreMigrationJournalV1,
        store: StoreMigrationJournalStoreV1
    ) throws -> StoreGenerationManifestV1 {
        guard let digest = journal.targetManifestDigest,
              let semantic = journal.targetSemanticDigest else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let manifest = try store.loadManifest(
            targetGenerationID: journal.targetGenerationID,
            expectedDigest: digest
        )
        guard manifest.generationID == journal.targetGenerationID,
              manifest.predecessorGenerationID == journal.sourceGenerationID,
              manifest.migrationID == journal.migrationID,
              manifest.storeSchemaRelease == journal.targetRelease,
              manifest.semanticSHA256 == semantic else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return manifest
    }

    private func requireTargetGenerationSnapshot(
        _ journal: StoreMigrationJournalV1,
        manifest: StoreGenerationManifestV1,
        at generationRootURL: URL
    ) throws {
        guard manifest.generationID == journal.targetGenerationID,
              manifest.files == (try generationFileDigests(
                  at: generationRootURL,
                  durable: true
              )),
              manifest.frozenIdentityDigest
                == (try frozenIdentityDigest(for: generationRootURL)) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
    }

    private func migrationJournal(
        _ value: StoreMigrationJournalV1,
        phase: StoreMigrationPhaseV1,
        sourceSemanticDigest: String? = nil,
        targetManifestDigest: String? = nil,
        targetSemanticDigest: String? = nil,
        desiredPointerDigest: String? = nil,
        publicationProcessID: UUID? = nil,
        firstValidationProcessID: UUID? = nil,
        secondValidationProcessID: UUID? = nil,
        targetWritePossible: Bool? = nil,
        pointerPublicationAttempted: Bool? = nil
    ) throws -> StoreMigrationJournalV1 {
        try StoreMigrationJournalV1(
            schemaVersion: value.schemaVersion,
            migrationID: value.migrationID,
            sourceGenerationID: value.sourceGenerationID,
            targetGenerationID: value.targetGenerationID,
            sourceRelease: value.sourceRelease,
            targetRelease: value.targetRelease,
            sourcePointerDigest: value.sourcePointerDigest,
            sourceTreeDigest: value.sourceTreeDigest,
            sourceManifestDigest: value.sourceManifestDigest,
            sourceSemanticDigest: sourceSemanticDigest ?? value.sourceSemanticDigest,
            targetManifestDigest: targetManifestDigest ?? value.targetManifestDigest,
            targetSemanticDigest: targetSemanticDigest ?? value.targetSemanticDigest,
            frozenIdentityDigest: value.frozenIdentityDigest,
            expectedPointerDigest: value.expectedPointerDigest,
            desiredPointerDigest: desiredPointerDigest ?? value.desiredPointerDigest,
            originatingProcessID: value.originatingProcessID,
            publicationProcessID: publicationProcessID ?? value.publicationProcessID,
            firstValidationProcessID:
                firstValidationProcessID ?? value.firstValidationProcessID,
            secondValidationProcessID:
                secondValidationProcessID ?? value.secondValidationProcessID,
            phase: phase,
            targetWritePossible: targetWritePossible ?? value.targetWritePossible,
            pointerPublicationAttempted:
                pointerPublicationAttempted ?? value.pointerPublicationAttempted
        )
    }

    private func publishMigrationPointerForwardOnly(
        _ journal: StoreMigrationJournalV1,
        store: StoreMigrationJournalStoreV1
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try publishMigrationPointerForwardOnlyLocked(journal, store: store)
        }
    }

    private func publishMigrationPointerForwardOnlyLocked(
        _ journal: StoreMigrationJournalV1,
        store: StoreMigrationJournalStoreV1
    ) throws {
        let manifest = try requireTargetManifest(journal, store: store)
        guard let manifestDigest = journal.targetManifestDigest else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let desiredData = try desiredMigrationPointerData(
            journal: journal,
            manifestDigest: manifestDigest
        )
        guard StoreMigrationCanonicalJSONV1.sha256(desiredData)
                == journal.desiredPointerDigest else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }

        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        let root = dataRootURL
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let currentName = Self.currentPointerName
        let temporaryName = ".current.json.migration-next"
        let targetURL = root.appendingPathComponent(currentName, isDirectory: false)
        let temporaryURL = root.appendingPathComponent(temporaryName, isDirectory: false)
        try protectPointer(at: targetURL, parent: parent, root: root)
        let current = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
            parent: parent,
            name: currentName
        )
        let currentDigest = StoreMigrationCanonicalJSONV1.sha256(current.data)
        if currentDigest == journal.desiredPointerDigest {
            guard current.data == desiredData else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            if try StoreRestoreGenerationAuthority.itemExists(
                parent: parent,
                name: temporaryName
            ) {
                let displaced = try StoreRestoreGenerationAuthority
                    .readRegularFileWithIdentity(
                        parent: parent,
                        name: temporaryName
                    )
                guard StoreMigrationCanonicalJSONV1.sha256(displaced.data)
                        == journal.expectedPointerDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(
                        .forwardFixRequired
                    )
                }
                try removeOwnedEntry(parent: parent, name: temporaryName)
            }
            return
        }
        guard currentDigest == journal.expectedPointerDigest else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: temporaryName
        ) {
            let existing = try StoreRestoreGenerationAuthority
                .readRegularFileWithIdentity(parent: parent, name: temporaryName)
            guard existing.data == desiredData else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            try removeOwnedEntry(parent: parent, name: temporaryName)
        }
        var publicationMayHaveOccurred = false
        do {
            try StoreRestoreGenerationAuthority.createRegularFile(
                parent: parent,
                name: temporaryName,
                data: desiredData
            )
            try protectPointerFile(
                .generationPointerTemporary,
                at: temporaryURL,
                parent: parent,
                root: root
            )
            let desiredIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: temporaryName
            )
            let currentBeforeSwap = try StoreRestoreGenerationAuthority
                .readRegularFileWithIdentity(parent: parent, name: currentName)
            guard currentBeforeSwap.data == current.data,
                  currentBeforeSwap.identity == current.identity,
                  Darwin.renameatx_np(
                      parent,
                      temporaryName,
                      parent,
                      currentName,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            publicationMayHaveOccurred = true
            guard Darwin.fsync(parent) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            try protectPointer(at: targetURL, parent: parent, root: root)
            let published = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: currentName
            )
            let displaced = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: temporaryName
            )
            guard published.data == desiredData,
                  published.identity == desiredIdentity,
                  displaced.data == current.data,
                  displaced.identity == current.identity else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            try removeOwnedEntry(parent: parent, name: temporaryName)
        } catch {
            if publicationMayHaveOccurred {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            if (try? StoreRestoreGenerationAuthority.itemExists(
                parent: parent,
                name: temporaryName
            )) == true {
                try? removeOwnedEntry(parent: parent, name: temporaryName)
            }
            throw error
        }
    }

    private func desiredMigrationPointerData(
        journal: StoreMigrationJournalV1,
        manifestDigest: String
    ) throws -> Data {
        switch (journal.sourceRelease, journal.targetRelease) {
        case (.v1, .v2):
            return try CurrentGenerationPointerV2(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest
            ).canonicalData()
        case (.v2, .v3):
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard case .v3(let pointer, let data) = current else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest
                && pointer.generationID
                    == canonicalString(for: journal.sourceGenerationID)
                && pointer.storeSchemaVersion == 2
            let isTarget = digest == journal.desiredPointerDigest
                && pointer.generationID
                    == canonicalString(for: journal.targetGenerationID)
                && pointer.storeSchemaVersion == 3
            guard isSource || isTarget else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest,
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                knownReplicaIDs: try pointer.knownReplicaIdentitySet(),
                storeSchemaVersion: 3
            ).canonicalData()
        case (.v3, .v4):
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard case .v3(let pointer, let data) = current else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest
                && pointer.generationID == canonicalString(for: journal.sourceGenerationID)
                && pointer.storeSchemaVersion == 3
            let isTarget = digest == journal.desiredPointerDigest
                && pointer.generationID == canonicalString(for: journal.targetGenerationID)
                && pointer.storeSchemaVersion == 4
            guard isSource || isTarget else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest,
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                knownReplicaIDs: try pointer.knownReplicaIdentitySet(),
                storeSchemaVersion: 4
            ).canonicalData()
        case (.v4, .v5):
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard case .v3(let pointer, let data) = current else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest
                && pointer.generationID == canonicalString(for: journal.sourceGenerationID)
                && pointer.storeSchemaVersion == 4
            let isTarget = digest == journal.desiredPointerDigest
                && pointer.generationID == canonicalString(for: journal.targetGenerationID)
                && pointer.storeSchemaVersion == 5
            guard isSource || isTarget else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest,
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                knownReplicaIDs: try pointer.knownReplicaIdentitySet(),
                storeSchemaVersion: 5
            ).canonicalData()
        case (.v5, .v6):
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard case .v3(let pointer, let data) = current else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest
                && pointer.generationID == canonicalString(for: journal.sourceGenerationID)
                && pointer.storeSchemaVersion == 5
            let isTarget = digest == journal.desiredPointerDigest
                && pointer.generationID == canonicalString(for: journal.targetGenerationID)
                && pointer.storeSchemaVersion == 6
            guard isSource || isTarget else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest,
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                knownReplicaIDs: try pointer.knownReplicaIdentitySet(),
                storeSchemaVersion: 6
            ).canonicalData()
        case (.v6, .v7):
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard case .v3(let pointer, let data) = current else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest
                && pointer.generationID == canonicalString(for: journal.sourceGenerationID)
                && pointer.storeSchemaVersion == 6
            let isTarget = digest == journal.desiredPointerDigest
                && pointer.generationID == canonicalString(for: journal.targetGenerationID)
                && pointer.storeSchemaVersion == 7
            guard isSource || isTarget else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest,
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                knownReplicaIDs: try pointer.knownReplicaIdentitySet(),
                storeSchemaVersion: 7
            ).canonicalData()
        case (.v7, .v8):
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard case .v3(let pointer, let data) = current else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest
                && pointer.generationID == canonicalString(for: journal.sourceGenerationID)
                && pointer.storeSchemaVersion == 7
            let isTarget = digest == journal.desiredPointerDigest
                && pointer.generationID == canonicalString(for: journal.targetGenerationID)
                && pointer.storeSchemaVersion == 8
            guard isSource || isTarget else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
            }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(
                generationID: journal.targetGenerationID,
                generationManifestSHA256: manifestDigest,
                workspaceID: identity.workspaceID,
                replicaID: identity.replicaID,
                knownReplicaIDs: try pointer.knownReplicaIdentitySet(),
                storeSchemaVersion: 8
            ).canonicalData()
        case (.v8, .v9):
            let current = try decodeCurrentPointer(at: dataRootURL.appendingPathComponent(Self.currentPointerName))
            guard case .v3(let pointer, let data) = current else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest && pointer.generationID == canonicalString(for: journal.sourceGenerationID) && pointer.storeSchemaVersion == 8
            let isTarget = digest == journal.desiredPointerDigest && pointer.generationID == canonicalString(for: journal.targetGenerationID) && pointer.storeSchemaVersion == 9
            guard isSource || isTarget else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(generationID: journal.targetGenerationID, generationManifestSHA256: manifestDigest, workspaceID: identity.workspaceID, replicaID: identity.replicaID, knownReplicaIDs: try pointer.knownReplicaIdentitySet(), storeSchemaVersion: 9).canonicalData()
        case (.v9, .v10):
            let current = try decodeCurrentPointer(at: dataRootURL.appendingPathComponent(Self.currentPointerName))
            guard case .v3(let pointer, let data) = current else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest && pointer.generationID == canonicalString(for: journal.sourceGenerationID) && pointer.storeSchemaVersion == 9
            let isTarget = digest == journal.desiredPointerDigest && pointer.generationID == canonicalString(for: journal.targetGenerationID) && pointer.storeSchemaVersion == 10
            guard isSource || isTarget else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(generationID: journal.targetGenerationID, generationManifestSHA256: manifestDigest, workspaceID: identity.workspaceID, replicaID: identity.replicaID, knownReplicaIDs: try pointer.knownReplicaIdentitySet(), storeSchemaVersion: 10).canonicalData()
        case (.v10, .v11):
            let current = try decodeCurrentPointer(at: dataRootURL.appendingPathComponent(Self.currentPointerName))
            guard case .v3(let pointer, let data) = current else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let digest = StoreMigrationCanonicalJSONV1.sha256(data)
            let isSource = digest == journal.expectedPointerDigest && pointer.generationID == canonicalString(for: journal.sourceGenerationID) && pointer.storeSchemaVersion == 10
            let isTarget = digest == journal.desiredPointerDigest && pointer.generationID == canonicalString(for: journal.targetGenerationID) && pointer.storeSchemaVersion == 11
            guard isSource || isTarget else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(generationID: journal.targetGenerationID, generationManifestSHA256: manifestDigest, workspaceID: identity.workspaceID, replicaID: identity.replicaID, knownReplicaIDs: try pointer.knownReplicaIdentitySet(), storeSchemaVersion: 11).canonicalData()
        case (.v11, .v12):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:11,targetVersion:12)
        case (.v12, .v13):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:12,targetVersion:13)
        case (.v13, .v14):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:13,targetVersion:14)
        case (.v14, .v15):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:14,targetVersion:15)
        case (.v15, .v16):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:15,targetVersion:16)
        case (.v16, .v17):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:16,targetVersion:17)
        case (.v17, .v18):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:17,targetVersion:18)
        case (.v18, .v19):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:18,targetVersion:19)
        case (.v19, .v20):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:19,targetVersion:20)
        case (.v20, .v21):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:20,targetVersion:21)
        case (.v21, .v22):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:21,targetVersion:22)
        case (.v22, .v23):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:22,targetVersion:23)
        case (.v23, .v24):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:23,targetVersion:24)
        case (.v24, .v25):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:24,targetVersion:25)
        case (.v25, .v26):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:25,targetVersion:26)
        case (.v26, .v27):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:26,targetVersion:27)
        case (.v27, .v28):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:27,targetVersion:28)
        case (.v28, .v29):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:28,targetVersion:29)
        case (.v29, .v30):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:29,targetVersion:30)
        case (.v30, .v31):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:30,targetVersion:31)
        case (.v31, .v32):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:31,targetVersion:32)
        case (.v32, .v33):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:32,targetVersion:33)
        case (.v33, .v34):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:33,targetVersion:34)
        case (.v34, .v35):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:34,targetVersion:35)
        case (.v35, .v36):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:35,targetVersion:36)
        case (.v36, .v37):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:36,targetVersion:37)
        case (.v37, .v38):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:37,targetVersion:38)
        case (.v38, .v39):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:38,targetVersion:39)
        case (.v39, .v40):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:39,targetVersion:40)
        case (.v40, .v41):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:40,targetVersion:41)
        case (.v41, .v42):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:41,targetVersion:42)
        case (.v42, .v43):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:42,targetVersion:43)
        case (.v43, .v44):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:43,targetVersion:44)
        case (.v44, .v45):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:44,targetVersion:45)
        case (.v45, .v46):return try desiredSuccessorPointerData(journal:journal,manifestDigest:manifestDigest,sourceVersion:45,targetVersion:46)
        default:
            throw StoreMigrationFailure.invalidContract
        }
    }

    private func desiredSuccessorPointerData(journal:StoreMigrationJournalV1,manifestDigest:String,sourceVersion:Int,targetVersion:Int)throws->Data{let current=try decodeCurrentPointer(at:dataRootURL.appendingPathComponent(Self.currentPointerName));guard case .v3(let pointer,let data)=current else{throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)};let digest=StoreMigrationCanonicalJSONV1.sha256(data);let isSource=digest==journal.expectedPointerDigest&&pointer.generationID==canonicalString(for:journal.sourceGenerationID)&&pointer.storeSchemaVersion==sourceVersion;let isTarget=digest==journal.desiredPointerDigest&&pointer.generationID==canonicalString(for:journal.targetGenerationID)&&pointer.storeSchemaVersion==targetVersion;guard isSource||isTarget else{throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)};let identity=try pointer.identity();return try CurrentGenerationPointerV3(generationID:journal.targetGenerationID,generationManifestSHA256:manifestDigest,workspaceID:identity.workspaceID,replicaID:identity.replicaID,knownReplicaIDs:try pointer.knownReplicaIdentitySet(),storeSchemaVersion:targetVersion).canonicalData()}

    @MainActor
    private func openValidatedV2Current(
        pointer: CurrentGenerationPointerV2,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        identity: WorkspaceReplicaIdentityV1,
        expectedPointerData: Data? = nil
    ) throws -> StoreGenerationSession {
        try pointer.validate()
        guard let generationID = canonicalUUID(from: pointer.generationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let manifest = try store.loadManifest(
            targetGenerationID: generationID,
            expectedDigest: pointer.generationManifestSHA256
        )
        let expectedRelease: PersistentSchemaReleaseV1
        switch pointer.storeSchemaVersion {
        case 2: expectedRelease = .v2
        case 3: expectedRelease = .v3
        case 4: expectedRelease = .v4
        case 5: expectedRelease = .v5
        case 6: expectedRelease = .v6
        case 7: expectedRelease = .v7
        case 8: expectedRelease = .v8
        case 9: expectedRelease = .v9
        case 10: expectedRelease = .v10
        case 11: expectedRelease = .v11
        case 12: expectedRelease = .v12
        case 13: expectedRelease = .v13
        case 14: expectedRelease = .v14
        case 15: expectedRelease = .v15
        case 16: expectedRelease = .v16
        case 17: expectedRelease = .v17
        case 18: expectedRelease = .v18
        case 19: expectedRelease = .v19
        case 20: expectedRelease = .v20
        case 21: expectedRelease = .v21
        case 22: expectedRelease = .v22
        case 23: expectedRelease = .v23
        case 24: expectedRelease = .v24
        case 25: expectedRelease = .v25
        case 26: expectedRelease = .v26
        case 27: expectedRelease = .v27
        case 28: expectedRelease = .v28
        case 29: expectedRelease = .v29
        case 30: expectedRelease = .v30
        case 31: expectedRelease = .v31
        case 32: expectedRelease = .v32
        case 33: expectedRelease = .v33
        case 34: expectedRelease = .v34
        case 35: expectedRelease = .v35
        case 36: expectedRelease = .v36
        case 37: expectedRelease = .v37
        case 38: expectedRelease = .v38
        case 39: expectedRelease = .v39
        case 40: expectedRelease = .v40
        case 41: expectedRelease = .v41
        case 42: expectedRelease = .v42
        case 43: expectedRelease = .v43
        case 44: expectedRelease = .v44
        case 45: expectedRelease = .v45
        case 46: expectedRelease = .v46
        default: throw StoreMigrationFailure.maintenanceRequired(.futureVersion)
        }
        guard manifest.generationID == generationID,
              manifest.storeSchemaRelease == expectedRelease else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let epoch = try GenerationEpochV1(
            generationID: generationID,
            generationManifestSHA256: pointer.generationManifestSHA256
        )
        let readerLease = try acquireCurrentReaderLease(
            epoch: epoch,
            expectedPointerData: expectedPointerData
                ?? (try pointer.canonicalData())
        )
        let generationRootURL = dataRootURL
            .appendingPathComponent(Self.generationsDirectoryName, isDirectory: true)
            .appendingPathComponent(pointer.generationID, isDirectory: true)
        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        guard try itemType(at: generationRootURL) == .typeDirectory,
              try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        try protectGeneration(
            at: generationRootURL,
            staging: false,
            requireModel: true
        )
        let container: ModelContainer
        do {
            container = try makeV2Container(at: modelStoreURL, migrate: false)
            _ = try requireV2Marker(
                in: container.mainContext,
                expectedMigrationID: manifest.migrationID
            )
        } catch let failure as StoreMigrationFailure {
            throw failure
        } catch {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        try protectGeneration(
            at: generationRootURL,
            staging: false,
            requireModel: true
        )
        return StoreGenerationSession(
            generationID: generationID,
            generationRootURL: generationRootURL,
            workspaceIdentity: identity,
            modelContainer: container,
            generationEpoch: epoch,
            readerLeaseHandle: readerLease,
            afterSaveReproof: { [self] in
                try self.protectGeneration(
                    at: generationRootURL,
                    staging: false,
                    requireModel: true
                )
            }
        )
    }

    @MainActor
    private func openValidatedV3Current(
        pointer: CurrentGenerationPointerV3,
        dataRootURL: URL,
        store: StoreMigrationJournalStoreV1
    ) throws -> StoreGenerationSession {
        let identity = try pointer.identity()
        if pointer.storeSchemaVersion == 2 {
            return try openValidatedV2Current(
                pointer: CurrentGenerationPointerV2(
                    generationID: UUID(uuidString: pointer.generationID)!,
                    generationManifestSHA256: pointer.generationManifestSHA256
                ),
                dataRootURL: dataRootURL,
                store: store,
                identity: identity,
                expectedPointerData: try pointer.canonicalData()
            )
        }
        guard (3...37).contains(pointer.storeSchemaVersion),
              let generationID = canonicalUUID(from: pointer.generationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let manifest = try store.loadManifest(
            targetGenerationID: generationID,
            expectedDigest: pointer.generationManifestSHA256
        )
        let release: PersistentSchemaReleaseV1
        switch pointer.storeSchemaVersion {
        case 3: release = .v3
        case 4: release = .v4
        case 5: release = .v5
        case 6: release = .v6
        case 7: release = .v7
        case 8: release = .v8
        case 9: release = .v9
        case 10: release = .v10
        case 11: release = .v11
        case 12: release = .v12
        case 13: release = .v13
        case 14: release = .v14
        case 15: release = .v15
        case 16: release = .v16
        case 17: release = .v17
        case 18: release = .v18
        case 19: release = .v19
        case 20: release = .v20
        case 21: release = .v21
        case 22: release = .v22
        case 23: release = .v23
        case 24: release = .v24
        case 25: release = .v25
        case 26: release = .v26
        case 27: release = .v27
        case 28: release = .v28
        case 29: release = .v29
        case 30: release = .v30
        case 31: release = .v31
        case 32: release = .v32
        case 33: release = .v33
        case 34: release = .v34
        case 35: release = .v35
        case 36: release = .v36
        case 37: release = .v37
        case 38: release = .v38
        case 39: release = .v39
        case 40: release = .v40
        case 41: release = .v41
        case 42: release = .v42
        case 43: release = .v43
        case 44: release = .v44
        case 45: release = .v45
        case 46: release = .v46
        default: throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        guard manifest.storeSchemaRelease == release else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let epoch = try GenerationEpochV1(
            generationID: generationID,
            generationManifestSHA256: pointer.generationManifestSHA256
        )
        let readerLease = try acquireCurrentReaderLease(
            epoch: epoch,
            expectedPointerData: try pointer.canonicalData()
        )
        let generationRootURL = installedGenerationURL(id: generationID)
        let modelStoreURL = generationRootURL.appendingPathComponent(Self.modelStoreName)
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)
        let container: ModelContainer
        switch pointer.storeSchemaVersion {
        case 3: container = try makeV3Container(at: modelStoreURL, migrate: false)
        case 4: container = try makeV4Container(at: modelStoreURL, migrate: false)
        case 5: container = try makeV5Container(at: modelStoreURL, migrate: false)
        case 6: container = try makeV6Container(at: modelStoreURL, migrate: false)
        case 7: container = try makeV7Container(at: modelStoreURL, migrate: false)
        case 8: container = try makeV8Container(at: modelStoreURL, migrate: false)
        case 9: container = try makeV9Container(at: modelStoreURL, migrate: false)
        case 10: container = try makeV10Container(at: modelStoreURL, migrate: false)
        case 11: container = try makeV11Container(at: modelStoreURL, migrate: false)
        case 12: container = try makeV12Container(at: modelStoreURL, migrate: false)
        case 13: container = try makeV13Container(at:modelStoreURL,migrate:false)
        case 14: container = try makeV14Container(at:modelStoreURL,migrate:false)
        case 15: container = try makeV15Container(at:modelStoreURL,migrate:false)
        case 16: container = try makeV16Container(at:modelStoreURL,migrate:false)
        case 17: container = try makeV17Container(at:modelStoreURL,migrate:false)
        case 18: container = try makeV18Container(at:modelStoreURL,migrate:false)
        case 19: container = try makeV19Container(at:modelStoreURL,migrate:false)
        case 20: container = try makeV20Container(at:modelStoreURL,migrate:false)
        case 21: container = try makeV21Container(at:modelStoreURL,migrate:false)
        case 22: container = try makeV22Container(at:modelStoreURL,migrate:false)
        case 23: container = try makeV23Container(at:modelStoreURL,migrate:false)
        case 24: container = try makeV24Container(at:modelStoreURL,migrate:false)
        case 25: container = try makeV25Container(at:modelStoreURL,migrate:false)
        case 26: container = try makeV26Container(at:modelStoreURL,migrate:false)
        case 27: container = try makeV27Container(at:modelStoreURL,migrate:false)
        case 28: container = try makeV28Container(at:modelStoreURL,migrate:false)
        case 29: container = try makeV29Container(at:modelStoreURL,migrate:false)
        case 30: container = try makeV30Container(at:modelStoreURL,migrate:false)
        case 31: container = try makeV31Container(at:modelStoreURL,migrate:false)
        case 32: container = try makeV32Container(at:modelStoreURL,migrate:false)
        case 33: container = try makeV33Container(at:modelStoreURL,migrate:false)
        case 34: container = try makeV34Container(at:modelStoreURL,migrate:false)
        case 35: container = try makeV35Container(at:modelStoreURL,migrate:false)
        case 36: container = try makeV36Container(at:modelStoreURL,migrate:false)
        case 37: container = try makeV37Container(at:modelStoreURL,migrate:false)
        case 38: container = try makeV38Container(at:modelStoreURL,migrate:false)
        case 39: container = try makeV39Container(at:modelStoreURL,migrate:false)
        case 40: container = try makeV40Container(at:modelStoreURL,migrate:false)
        case 41: container = try makeV41Container(at:modelStoreURL,migrate:false)
        case 42: container = try makeV42Container(at:modelStoreURL,migrate:false)
        case 43: container = try makeV43Container(at:modelStoreURL,migrate:false)
        case 44: container = try makeV44Container(at:modelStoreURL,migrate:false)
        case 45: container = try makeV45Container(at:modelStoreURL,migrate:false)
        case 46: container = try makeV46Container(at:modelStoreURL,migrate:false)
        case 47: container = try makeV47Container(at:modelStoreURL,migrate:false)
        case 48: container = try makeV48Container(at:modelStoreURL,migrate:false)
        case 49: container = try makeV49Container(at:modelStoreURL,migrate:false)
        case 50: container = try makeV50Container(at:modelStoreURL,migrate:false)
        case 51: container = try makeV51Container(at:modelStoreURL,migrate:false)
        case 52: container = try makeV52Container(at:modelStoreURL,migrate:false)
        case 53: container = try makeV53Container(at:modelStoreURL,migrate:false)
        default: throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        if pointer.storeSchemaVersion == 3 {
            _ = try requireV3Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 4 {
            _ = try requireV4Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 5 {
            _ = try requireV5Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 6 {
            _ = try requireV6Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 7 {
            _ = try requireV7Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 8 {
            _ = try requireV8Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 9 {
            _ = try requireV9Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 10 {
            _ = try requireV10Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 11 {
            _ = try requireV11Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        } else if pointer.storeSchemaVersion == 12 {
            _ = try requireV12Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
        }else if pointer.storeSchemaVersion == 13{_ = try requireV13Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 14{_ = try requireV14Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 15{_ = try requireV15Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 16{_ = try requireV16Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 17{_ = try requireV17Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 18{_ = try requireV18Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 19{_ = try requireV19Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 20{_ = try requireV20Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 21{_ = try requireV21Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 22{_ = try requireV22Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 23{_ = try requireV23Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 24{_ = try requireV24Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 25{_ = try requireV25Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 26{_ = try requireV26Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 27{_ = try requireV27Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 28{_ = try requireV28Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 29{_ = try requireV29Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 30{_ = try requireV30Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 31{_ = try requireV31Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 32{_ = try requireV32Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 33{_ = try requireV33Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
        }else if pointer.storeSchemaVersion == 34{_ = try requireV34Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 35{_ = try requireV35Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 36{_ = try requireV36Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 37{_ = try requireV37Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 38{_ = try requireV38Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 39{_ = try requireV39Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 40{_ = try requireV40Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 41{_ = try requireV41Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 42{_ = try requireV42Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 43{_ = try requireV43Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 44{_ = try requireV44Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 45{_ = try requireV45Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 46{_ = try requireV46Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 47{_ = try requireV47Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 48{_ = try requireV48Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 49{_ = try requireV49Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if pointer.storeSchemaVersion == 50{_ = try requireV50Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if manifest.storeSchemaRelease == .v53 {_ = try requireV53Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else if manifest.storeSchemaRelease == .v52 {_ = try requireV52Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }else{_ = try requireV51Marker(in:container.mainContext,expectedMigrationID:manifest.migrationID)
         }
        if pointer.storeSchemaVersion == 3 {
            guard manifest.semanticSHA256 == (try semanticDigest(at: modelStoreURL, release: release)) else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
        }
        return StoreGenerationSession(
            generationID: generationID,
            generationRootURL: generationRootURL,
            workspaceIdentity: identity,
            modelContainer: container,
            generationEpoch: epoch,
            readerLeaseHandle: readerLease,
            afterSaveReproof: { [self] in
                try self.protectGeneration(
                    at: generationRootURL,
                    staging: false,
                    requireModel: true
                )
            }
        )
    }

    @MainActor
    private func migrateAndValidateClone(
        at generationRootURL: URL,
        sourceRelease: PersistentSchemaReleaseV1,
        targetRelease: PersistentSchemaReleaseV1,
        migrationID: UUID,
        sourceGenerationID: UUID,
        targetGenerationID: UUID,
        expectedSemanticDigest: String
    ) throws -> String {
        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        switch (sourceRelease, targetRelease) {
        case (.v1, .v2):
            let semantic = try autoreleasepool { () throws -> Data in
                let container = try makeV2Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                try insertOrRequireV2Marker(
                    in: context,
                    migrationID: migrationID
                )
                return try semanticExport(in: context)
            }
            let digest = StoreMigrationCanonicalJSONV1.sha256(semantic)
            guard digest == expectedSemanticDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            return digest
        case (.v2, .v3):
            let sourceSemantic = try semanticExport(
                at: modelStoreURL,
                release: .v2,
                markerMigrationID: migrationID
            )
            guard StoreMigrationCanonicalJSONV1.sha256(sourceSemantic)
                    == expectedSemanticDigest else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            return try autoreleasepool { () throws -> String in
                let container = try makeV3Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                try backfillV3DeletionLedger(in: context)
                try requireV3Marker(in: context, expectedMigrationID: migrationID)
                return StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV3(in: context)
                )
            }
        case (.v3, .v4):
            return try autoreleasepool { () throws -> String in
                let container = try makeV4Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                // The V3 semantic projection contains only the shared content
                // models plus the deletion ledger, so it remains readable from
                // an already-migrated V4 clone. This is essential on retry after
                // the V4 marker save but before the outer journal advanced.
                guard StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV3(in: context)
                ) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV4MutationState(in: context, migrationID: migrationID)
                let current = try decodeCurrentPointer(
                    at: dataRootURL.appendingPathComponent(Self.currentPointerName)
                )
                guard case .v3(let pointer, _) = current,
                      pointer.storeSchemaVersion == 3 else {
                    throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
                }
                return StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV4(in: context)
                )
            }
        case (.v4, .v5):
            return try autoreleasepool { () throws -> String in
                let container = try makeV5Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                // V4 intentionally projects only records schema 3, so the
                // source digest remains stable after V5 derives the new bytes.
                guard StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV4(in: context)
                ) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV5ObservationAndTimeMarker(
                    in: context,
                    migrationID: migrationID
                )
                let current = try decodeCurrentPointer(
                    at: dataRootURL.appendingPathComponent(Self.currentPointerName)
                )
                guard case .v3(let pointer, _) = current,
                      pointer.storeSchemaVersion == 4 else {
                    throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
                }
                return StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV5(in: context)
                )
            }
        case (.v5, .v6):
            return try autoreleasepool { () throws -> String in
                let container = try makeV6Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                guard StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV5(in: context)
                ) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV6LocationBaseline(
                    in: context,
                    migrationID: migrationID,
                    sourceGenerationID: sourceGenerationID,
                    targetGenerationID: targetGenerationID
                )
                let current = try decodeCurrentPointer(
                    at: dataRootURL.appendingPathComponent(Self.currentPointerName)
                )
                guard case .v3(let pointer, _) = current,
                      pointer.storeSchemaVersion == 5 else {
                    throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
                }
                return StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV6(in: context)
                )
            }
        case (.v6, .v7):
            return try autoreleasepool { () throws -> String in
                let container = try makeV7Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                guard StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV6(in: context)
                ) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV7Marker(in: context, migrationID: migrationID)
                return StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV7(in: context)
                )
            }
        case (.v7, .v8):
            return try autoreleasepool { () throws -> String in
                let container = try makeV8Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
                if markers.count == 1, markers[0].schemaVersion == 8 {
                    _ = try requireV8Marker(in: context, expectedMigrationID: migrationID)
                    let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                    guard states.count == 1,
                          states[0].generationID == targetGenerationID else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                    return StoreMigrationCanonicalJSONV1.sha256(
                        try semanticExportV8(in: context)
                    )
                }
                guard StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV7(in: context)
                ) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                let current = try decodeCurrentPointer(
                    at: dataRootURL.appendingPathComponent(Self.currentPointerName)
                )
                guard case .v3(let pointer, _) = current,
                      pointer.storeSchemaVersion == 7 else {
                    throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
                }
                try backfillV8RequirementAssurance(
                    in: context,
                    workspaceID: try pointer.identity().workspaceID.rawValue,
                    migrationID: migrationID,
                    targetGenerationID: targetGenerationID
                )
                return StoreMigrationCanonicalJSONV1.sha256(
                    try semanticExportV8(in: context)
                )
            }
        case (.v8, .v9):
            return try autoreleasepool { () throws -> String in
                let container = try makeV9Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
                if markers.count == 1, markers[0].schemaVersion == 9 {
                    _ = try requireV9Marker(in: context, expectedMigrationID: migrationID)
                    let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                    guard states.count == 1,
                          states[0].generationID == targetGenerationID,
                          try context.fetch(FetchDescriptor<ServicePartyRow>()).isEmpty,
                          try context.fetch(FetchDescriptor<SitePartyRoleEventRow>()).isEmpty,
                          try context.fetch(FetchDescriptor<ActorSnapshotRow>()).isEmpty,
                          try context.fetch(FetchDescriptor<QualificationSnapshotRow>()).isEmpty,
                          try context.fetch(FetchDescriptor<SignoffSnapshotRow>()).isEmpty else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                    return StoreMigrationCanonicalJSONV1.sha256(
                        try semanticExportV9(in: context)
                    )
                }
                guard markers.count == 1, markers[0].schemaVersion == 8 else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                guard StoreMigrationCanonicalJSONV1.sha256(try semanticExportV8(in: context)) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                let parties = try context.fetch(FetchDescriptor<ServicePartyRow>())
                let roles = try context.fetch(FetchDescriptor<SitePartyRoleEventRow>())
                let actors = try context.fetch(FetchDescriptor<ActorSnapshotRow>())
                let qualifications = try context.fetch(FetchDescriptor<QualificationSnapshotRow>())
                let signoffs = try context.fetch(FetchDescriptor<SignoffSnapshotRow>())
                guard parties.isEmpty, roles.isEmpty, actors.isEmpty, qualifications.isEmpty, signoffs.isEmpty else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                try backfillV9Marker(in: context, migrationID: migrationID)
                return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV9(in: context))
            }
        case (.v9, .v10):
            return try autoreleasepool { () throws -> String in
                let container = try makeV10Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
                if markers.count == 1, markers[0].schemaVersion == 10 {
                    _ = try requireV10Marker(in: context, expectedMigrationID: migrationID)
                    let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                    guard states.count == 1, states[0].generationID == targetGenerationID else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                    try requireV10LegacyMigrationState(
                        in: context,
                        migrationID: migrationID
                    )
                    return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV10(in: context))
                }
                guard markers.count == 1, markers[0].schemaVersion == 9,
                      StoreMigrationCanonicalJSONV1.sha256(try semanticExportV9(in: context)) == expectedSemanticDigest else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV10AssetSemantics(
                    in: context,
                    migrationID: migrationID,
                    targetGenerationID: targetGenerationID
                )
                return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV10(in: context))
            }
        case (.v10, .v11):
            return try autoreleasepool { () throws -> String in
                let container = try makeV11Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
                if markers.count == 1, markers[0].schemaVersion == 11 {
                    _ = try requireV11Marker(in: context, expectedMigrationID: migrationID)
                    return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV11(in: context))
                }
                guard markers.count == 1, markers[0].schemaVersion == 10,
                      StoreMigrationCanonicalJSONV1.sha256(try semanticExportV10(in: context)) == expectedSemanticDigest,
                      try context.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<RequirementBasisBindingRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<SeverityScaleReleaseRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<FindingClassificationBindingRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<DerivedFactProvenanceRow>()).isEmpty else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV11Marker(in: context, migrationID: migrationID)
                return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV11(in: context))
            }
        case (.v11, .v12):
            return try autoreleasepool { () throws -> String in
                let container = try makeV12Container(at: modelStoreURL, migrate: true)
                let context = container.mainContext
                let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
                if markers.count == 1, markers[0].schemaVersion == 12 {
                    _ = try requireV12Marker(in: context, expectedMigrationID: migrationID)
                    return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV12(in: context))
                }
                guard markers.count == 1, markers[0].schemaVersion == 11,
                      StoreMigrationCanonicalJSONV1.sha256(try semanticExportV11(in: context)) == expectedSemanticDigest,
                      try context.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).isEmpty,
                      try context.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>()).isEmpty else {
                    throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
                }
                try backfillV12Marker(in: context, migrationID: migrationID)
                return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV12(in: context))
            }
        case (.v12,.v13):return try autoreleasepool{let container=try makeV13Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==13{_ = try requireV13Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV13(in:context))};guard markers.count==1,markers[0].schemaVersion==12,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV12(in:context))==expectedSemanticDigest,try context.fetch(FetchDescriptor<EvidenceVisibilityRow>()).isEmpty,try context.fetch(FetchDescriptor<ClaimEvidenceLinkRow>()).isEmpty,try context.fetch(FetchDescriptor<AssuranceManifestRow>()).isEmpty,try context.fetch(FetchDescriptor<AttestationRow>()).isEmpty else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV13Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV13(in:context))}
        case (.v13,.v14):return try autoreleasepool{let container=try makeV14Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==14{_ = try requireV14Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV14(in:context))};guard markers.count==1,markers[0].schemaVersion==13,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV13(in:context))==expectedSemanticDigest,try reviewRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV14Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV14(in:context))}
        case (.v14,.v15):return try autoreleasepool{let c=try makeV15Container(at:modelStoreURL,migrate:true);let x=c.mainContext;let m=try x.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if m.count==1,m[0].schemaVersion==15{_ = try requireV15Marker(in:x,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV15(in:x))};guard m.count==1,m[0].schemaVersion==14,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV14(in:x))==expectedSemanticDigest,try workPacketRowsAreEmpty(in:x)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV15Marker(in:x,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV15(in:x))}
        case (.v15,.v16):return try autoreleasepool{let container=try makeV16Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==16{_ = try requireV16Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV16(in:context))};guard markers.count==1,markers[0].schemaVersion==15,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV15(in:context))==expectedSemanticDigest,try fieldDraftRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV16Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV16(in:context))}
        case (.v16,.v17):return try autoreleasepool{let container=try makeV17Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==17{_ = try requireV17Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV17(in:context))};guard markers.count==1,markers[0].schemaVersion==16,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV16(in:context))==expectedSemanticDigest,try packageEvolutionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV17Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV17(in:context))}
        case (.v17,.v18):return try autoreleasepool{let container=try makeV18Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==18{_ = try requireV18Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV18(in:context))};guard markers.count==1,markers[0].schemaVersion==17,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV17(in:context))==expectedSemanticDigest,try measurementIntegrityRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV18Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV18(in:context))}
        case (.v18,.v19):return try autoreleasepool{let container=try makeV19Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==19{_ = try requireV19Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV19(in:context))};guard markers.count==1,markers[0].schemaVersion==18,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV18(in:context))==expectedSemanticDigest,try privacyTransformRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV19Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV19(in:context))}
        case (.v19,.v20):return try autoreleasepool{let container=try makeV20Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==20{_ = try requireV20Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV20(in:context))};guard markers.count==1,markers[0].schemaVersion==19,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV19(in:context))==expectedSemanticDigest,try clientCapabilityRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV20Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV20(in:context))}
        case (.v20,.v21):return try autoreleasepool{let container=try makeV21Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==21{_ = try requireV21Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV21(in:context))};guard markers.count==1,markers[0].schemaVersion==20,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV20(in:context))==expectedSemanticDigest,try recoverabilityVerificationRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV21Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV21(in:context))}
        case (.v21,.v22):return try autoreleasepool{let container=try makeV22Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==22{_ = try requireV22Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV22(in:context))};guard markers.count==1,markers[0].schemaVersion==21,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV21(in:context))==expectedSemanticDigest,try fieldReferenceRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV22Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV22(in:context))}
        case (.v22,.v23):return try autoreleasepool{let container=try makeV23Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==23{_ = try requireV23Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV23(in:context))};guard markers.count==1,markers[0].schemaVersion==22,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV22(in:context))==expectedSemanticDigest,try accessibleDocumentRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV23Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV23(in:context))}
        case (.v23,.v24):return try autoreleasepool{let container=try makeV24Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==24{_ = try requireV24Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV24(in:context))};guard markers.count==1,markers[0].schemaVersion==23,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV23(in:context))==expectedSemanticDigest,try surveyDefinitionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV24Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV24(in:context))}
        case (.v24,.v25):return try autoreleasepool{let container=try makeV25Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==25{_ = try requireV25Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV25(in:context))};guard markers.count==1,markers[0].schemaVersion==24,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV24(in:context))==expectedSemanticDigest,try surveySessionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV25Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV25(in:context))}
        case (.v25,.v26):return try autoreleasepool{let container=try makeV26Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==26{_ = try requireV26Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV26(in:context))};guard markers.count==1,markers[0].schemaVersion==25,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV25(in:context))==expectedSemanticDigest,try assetLocatorRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV26Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV26(in:context))}
        case (.v26,.v27):return try autoreleasepool{let container=try makeV27Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==27{_ = try requireV27Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV27(in:context))};guard markers.count==1,markers[0].schemaVersion==26,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV26(in:context))==expectedSemanticDigest,try scheduleRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV27Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV27(in:context))}
        case (.v27,.v28):return try autoreleasepool{let container=try makeV28Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==28{_ = try requireV28Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV28(in:context))};guard markers.count==1,markers[0].schemaVersion==27,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV27(in:context))==expectedSemanticDigest,try planRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV28Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV28(in:context))}
        case (.v28,.v29):return try autoreleasepool{let container=try makeV29Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==29{_ = try requireV29Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV29(in:context))};guard markers.count==1,markers[0].schemaVersion==28,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV28(in:context))==expectedSemanticDigest,try placementPoseRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV29Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV29(in:context))}
        case (.v29,.v30):return try autoreleasepool{let container=try makeV30Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==30{_ = try requireV30Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV30(in:context))};guard markers.count==1,markers[0].schemaVersion==29,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV29(in:context))==expectedSemanticDigest,try evidenceContextRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV30Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV30(in:context))}
        case (.v30,.v31):return try autoreleasepool{let container=try makeV31Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==31{_ = try requireV31Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV31(in:context))};guard markers.count==1,markers[0].schemaVersion==30,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV30(in:context))==expectedSemanticDigest,try lightingRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV31Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV31(in:context))}
        case (.v31,.v32):return try autoreleasepool{let container=try makeV32Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==32{_ = try requireV32Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV32(in:context))};guard markers.count==1,markers[0].schemaVersion==31,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV31(in:context))==expectedSemanticDigest,try assistanceAcceptanceReceiptRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV32Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV32(in:context))}
        case (.v32,.v33):return try autoreleasepool{let container=try makeV33Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==33{_ = try requireV33Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV33(in:context))};guard markers.count==1,markers[0].schemaVersion==32,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV32(in:context))==expectedSemanticDigest,try temporalEvidenceRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV33Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV33(in:context))}
        case (.v33,.v34):return try autoreleasepool{let container=try makeV34Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==34{_ = try requireV34Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV34(in:context))};guard markers.count==1,markers[0].schemaVersion==33,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV33(in:context))==expectedSemanticDigest,try assetLabelRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV34Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV34(in:context))}
        case (.v34,.v35):return try autoreleasepool{let container=try makeV35Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==35{_ = try requireV35Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV35(in:context))};guard markers.count==1,markers[0].schemaVersion==34,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV34(in:context))==expectedSemanticDigest,try operationalContactRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV35Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV35(in:context))}
        case (.v35,.v36):return try autoreleasepool{let container=try makeV36Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==36{_ = try requireV36Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV36(in:context))};guard markers.count==1,markers[0].schemaVersion==35,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV35(in:context))==expectedSemanticDigest,try activityContractRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV36Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV36(in:context))}
        case (.v36,.v37):return try autoreleasepool{let container=try makeV37Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==37{_ = try requireV37Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV37(in:context))};guard markers.count==1,markers[0].schemaVersion==36,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV36(in:context))==expectedSemanticDigest,try workResourceRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV37Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV37(in:context))}
        case (.v37,.v38):return try autoreleasepool{let container=try makeV38Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==38{_ = try requireV38Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV38(in:context))};guard markers.count==1,markers[0].schemaVersion==37,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV37(in:context))==expectedSemanticDigest,try scheduleExceptionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV38Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV38(in:context))}
        case (.v38,.v39):return try autoreleasepool{let container=try makeV39Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==39{_ = try requireV39Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV39(in:context))};guard markers.count==1,markers[0].schemaVersion==38,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV38(in:context))==expectedSemanticDigest,try serviceRequestRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV39Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV39(in:context))}
        case (.v39,.v40):return try autoreleasepool{let container=try makeV40Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==40{_ = try requireV40Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV40(in:context))};guard markers.count==1,markers[0].schemaVersion==39,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV39(in:context))==expectedSemanticDigest,try serviceReliabilityRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV40Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV40(in:context))}
        case (.v40,.v41):return try autoreleasepool{let container=try makeV41Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==41{_ = try requireV41Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV41(in:context))};guard markers.count==1,markers[0].schemaVersion==40,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV40(in:context))==expectedSemanticDigest,try partsStockRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV41Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV41(in:context))}
        case (.v41,.v42):return try autoreleasepool{let container=try makeV42Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==42{_ = try requireV42Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV42(in:context))};guard markers.count==1,markers[0].schemaVersion==41,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV41(in:context))==expectedSemanticDigest,try myDayRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV42Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV42(in:context))}
        case (.v42,.v43):return try autoreleasepool{let container=try makeV43Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==43{_ = try requireV43Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV43(in:context))};guard markers.count==1,markers[0].schemaVersion==42,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV42(in:context))==expectedSemanticDigest,try evidenceCurationRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV43Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV43(in:context))}
        case (.v43,.v44):return try autoreleasepool{let container=try makeV44Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==44{_ = try requireV44Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV44(in:context))};guard markers.count==1,markers[0].schemaVersion==43,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV43(in:context))==expectedSemanticDigest,try shopReportProfileRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV44Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV44(in:context))}
        case (.v44,.v45):return try autoreleasepool{let container=try makeV45Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==45{_ = try requireV45Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV45(in:context))};guard markers.count==1,markers[0].schemaVersion==44,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV44(in:context))==expectedSemanticDigest,try roundSessionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV45Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV45(in:context))}
        case (.v45,.v46):return try autoreleasepool{let container=try makeV46Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==46{_ = try requireV46Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV46(in:context))};guard markers.count==1,markers[0].schemaVersion==45,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV45(in:context))==expectedSemanticDigest,try importBulkRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV46Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV46(in:context))}
        case (.v46,.v47):return try autoreleasepool{let container=try makeV47Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==47{_ = try requireV47Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV47(in:context))};guard markers.count==1,markers[0].schemaVersion==46,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV46(in:context))==expectedSemanticDigest,try evidenceQualityRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV47Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV47(in:context))}
        case (.v47,.v48):return try autoreleasepool{let container=try makeV48Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==48{_ = try requireV48Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV48(in:context))};guard markers.count==1,markers[0].schemaVersion==47,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV47(in:context))==expectedSemanticDigest,try fastSurveyInboxRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV48Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV48(in:context))}
        case (.v48,.v49):return try autoreleasepool{let container=try makeV49Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==49{_ = try requireV49Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV49(in:context))};guard markers.count==1,markers[0].schemaVersion==48,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV48(in:context))==expectedSemanticDigest,try reinspectionExceptionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV49Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV49(in:context))}
        case (.v49,.v50):return try autoreleasepool{let container=try makeV50Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==50{_ = try requireV50Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV50(in:context))};guard markers.count==1,markers[0].schemaVersion==49,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV49(in:context))==expectedSemanticDigest,try entityIdentityResolutionRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV50Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV50(in:context))}
        case (.v50,.v51):return try autoreleasepool{let container=try makeV51Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==51{_ = try requireV51Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV51(in:context))};guard markers.count==1,markers[0].schemaVersion==50,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV50(in:context))==expectedSemanticDigest,try workspaceExperienceRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV51Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV51(in:context))}
        case (.v51,.v52):return try autoreleasepool{let container=try makeV52Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==52{_ = try requireV52Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV52(in:context))};guard markers.count==1,markers[0].schemaVersion==51,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV51(in:context))==expectedSemanticDigest,try lightingDayInventoryRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV52Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV52(in:context))}
        case (.v52,.v53):return try autoreleasepool{let container=try makeV53Container(at:modelStoreURL,migrate:true);let context=container.mainContext;let markers=try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());if markers.count==1,markers[0].schemaVersion==53{_ = try requireV53Marker(in:context,expectedMigrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV53(in:context))};guard markers.count==1,markers[0].schemaVersion==52,StoreMigrationCanonicalJSONV1.sha256(try semanticExportV52(in:context))==expectedSemanticDigest,try lightingNightWorkflowRowsAreEmpty(in:context)else{throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)};try backfillV53Marker(in:context,migrationID:migrationID);return StoreMigrationCanonicalJSONV1.sha256(try semanticExportV53(in:context))}
        default:
            throw StoreMigrationFailure.invalidContract
        }
    }

    @MainActor
    private func semanticExport(
        at modelStoreURL: URL,
        release: PersistentSchemaReleaseV1,
        markerMigrationID: UUID?
    ) throws -> Data {
        try autoreleasepool {
            let container: ModelContainer
            switch release {
            case .v1:
                guard markerMigrationID == nil else {
                    throw StoreMigrationFailure.invalidContract
                }
                container = try makeV1Container(at: modelStoreURL)
            case .v2:
                container = try makeV2Container(at: modelStoreURL, migrate: false)
                _ = try requireV2Marker(
                    in: container.mainContext,
                    expectedMigrationID: markerMigrationID
                )
            case .v3:
                container = try makeV3Container(at: modelStoreURL, migrate: false)
                _ = try requireV3Marker(
                    in: container.mainContext,
                    expectedMigrationID: markerMigrationID
                )
            case .v4:
                container = try makeV4Container(at: modelStoreURL, migrate: false)
                _ = try requireV4Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v5:
                container = try makeV5Container(at: modelStoreURL, migrate: false)
                _ = try requireV5Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v6:
                container = try makeV6Container(at: modelStoreURL, migrate: false)
                _ = try requireV6Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v7:
                container = try makeV7Container(at: modelStoreURL, migrate: false)
                _ = try requireV7Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v8:
                container = try makeV8Container(at: modelStoreURL, migrate: false)
                _ = try requireV8Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v9:
                container = try makeV9Container(at: modelStoreURL, migrate: false)
                _ = try requireV9Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v10:
                container = try makeV10Container(at: modelStoreURL, migrate: false)
                _ = try requireV10Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v11:
                container = try makeV11Container(at: modelStoreURL, migrate: false)
                _ = try requireV11Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v12:
                container = try makeV12Container(at: modelStoreURL, migrate: false)
                _ = try requireV12Marker(in: container.mainContext, expectedMigrationID: markerMigrationID)
            case .v13:container=try makeV13Container(at:modelStoreURL,migrate:false);_ = try requireV13Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v14:container=try makeV14Container(at:modelStoreURL,migrate:false);_ = try requireV14Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v15:container=try makeV15Container(at:modelStoreURL,migrate:false);_ = try requireV15Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v16:container=try makeV16Container(at:modelStoreURL,migrate:false);_ = try requireV16Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v17:container=try makeV17Container(at:modelStoreURL,migrate:false);_ = try requireV17Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v18:container=try makeV18Container(at:modelStoreURL,migrate:false);_ = try requireV18Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v19:container=try makeV19Container(at:modelStoreURL,migrate:false);_ = try requireV19Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v20:container=try makeV20Container(at:modelStoreURL,migrate:false);_ = try requireV20Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v21:container=try makeV21Container(at:modelStoreURL,migrate:false);_ = try requireV21Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v22:container=try makeV22Container(at:modelStoreURL,migrate:false);_ = try requireV22Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v23:container=try makeV23Container(at:modelStoreURL,migrate:false);_ = try requireV23Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v24:container=try makeV24Container(at:modelStoreURL,migrate:false);_ = try requireV24Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v25:container=try makeV25Container(at:modelStoreURL,migrate:false);_ = try requireV25Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v26:container=try makeV26Container(at:modelStoreURL,migrate:false);_ = try requireV26Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v27:container=try makeV27Container(at:modelStoreURL,migrate:false);_ = try requireV27Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v28:container=try makeV28Container(at:modelStoreURL,migrate:false);_ = try requireV28Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v29:container=try makeV29Container(at:modelStoreURL,migrate:false);_ = try requireV29Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v30:container=try makeV30Container(at:modelStoreURL,migrate:false);_ = try requireV30Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v31:container=try makeV31Container(at:modelStoreURL,migrate:false);_ = try requireV31Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v32:container=try makeV32Container(at:modelStoreURL,migrate:false);_ = try requireV32Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v33:container=try makeV33Container(at:modelStoreURL,migrate:false);_ = try requireV33Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v34:container=try makeV34Container(at:modelStoreURL,migrate:false);_ = try requireV34Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v35:container=try makeV35Container(at:modelStoreURL,migrate:false);_ = try requireV35Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v36:container=try makeV36Container(at:modelStoreURL,migrate:false);_ = try requireV36Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v37:container=try makeV37Container(at:modelStoreURL,migrate:false);_ = try requireV37Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v38:container=try makeV38Container(at:modelStoreURL,migrate:false);_ = try requireV38Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v39:container=try makeV39Container(at:modelStoreURL,migrate:false);_ = try requireV39Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v40:container=try makeV40Container(at:modelStoreURL,migrate:false);_ = try requireV40Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v41:container=try makeV41Container(at:modelStoreURL,migrate:false);_ = try requireV41Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v42:container=try makeV42Container(at:modelStoreURL,migrate:false);_ = try requireV42Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v43:container=try makeV43Container(at:modelStoreURL,migrate:false);_ = try requireV43Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v44:container=try makeV44Container(at:modelStoreURL,migrate:false);_ = try requireV44Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v45:container=try makeV45Container(at:modelStoreURL,migrate:false);_ = try requireV45Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v46:container=try makeV46Container(at:modelStoreURL,migrate:false);_ = try requireV46Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v47:container=try makeV47Container(at:modelStoreURL,migrate:false);_ = try requireV47Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v48:container=try makeV48Container(at:modelStoreURL,migrate:false);_ = try requireV48Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v49:container=try makeV49Container(at:modelStoreURL,migrate:false);_ = try requireV49Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v50:container=try makeV50Container(at:modelStoreURL,migrate:false);_ = try requireV50Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v51:container=try makeV51Container(at:modelStoreURL,migrate:false);_ = try requireV51Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v52:container=try makeV52Container(at:modelStoreURL,migrate:false);_ = try requireV52Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            case .v53:container=try makeV53Container(at:modelStoreURL,migrate:false);_ = try requireV53Marker(in:container.mainContext,expectedMigrationID:markerMigrationID)
            }
            if release == .v21{return try semanticExportV21(in:container.mainContext)}
            if release == .v22{return try semanticExportV22(in:container.mainContext)}
            if release == .v23{return try semanticExportV23(in:container.mainContext)}
            if release == .v24{return try semanticExportV24(in:container.mainContext)}
            if release == .v25{return try semanticExportV25(in:container.mainContext)}
            if release == .v26{return try semanticExportV26(in:container.mainContext)}
            if release == .v27{return try semanticExportV27(in:container.mainContext)}
            if release == .v28{return try semanticExportV28(in:container.mainContext)}
            if release == .v29{return try semanticExportV29(in:container.mainContext)}
            if release == .v30{return try semanticExportV30(in:container.mainContext)}
            if release == .v31{return try semanticExportV31(in:container.mainContext)}
            if release == .v32{return try semanticExportV32(in:container.mainContext)}
            if release == .v33{return try semanticExportV33(in:container.mainContext)}
            if release == .v34{return try semanticExportV34(in:container.mainContext)}
            if release == .v35{return try semanticExportV35(in:container.mainContext)}
            if release == .v36{return try semanticExportV36(in:container.mainContext)}
            if release == .v37{return try semanticExportV37(in:container.mainContext)}
            if release == .v38{return try semanticExportV38(in:container.mainContext)}
            if release == .v39{return try semanticExportV39(in:container.mainContext)}
            if release == .v40{return try semanticExportV40(in:container.mainContext)}
            if release == .v41{return try semanticExportV41(in:container.mainContext)}
            if release == .v42{return try semanticExportV42(in:container.mainContext)}
            if release == .v43{return try semanticExportV43(in:container.mainContext)}
            if release == .v44{return try semanticExportV44(in:container.mainContext)}
            if release == .v45{return try semanticExportV45(in:container.mainContext)}
            if release == .v46{return try semanticExportV46(in:container.mainContext)}
            if release == .v47{return try semanticExportV47(in:container.mainContext)}
            if release == .v48{return try semanticExportV48(in:container.mainContext)}
            if release == .v49{return try semanticExportV49(in:container.mainContext)}
            if release == .v50{return try semanticExportV50(in:container.mainContext)}
            if release == .v51{return try semanticExportV51(in:container.mainContext)}
            if release == .v52{return try semanticExportV52(in:container.mainContext)}
            if release == .v53{return try semanticExportV53(in:container.mainContext)}
            if release == .v20{return try semanticExportV20(in:container.mainContext)}
            if release == .v19{return try semanticExportV19(in:container.mainContext)}
            if release == .v18{return try semanticExportV18(in:container.mainContext)}
            if release == .v17{return try semanticExportV17(in:container.mainContext)}
            if release == .v16{return try semanticExportV16(in:container.mainContext)}
            if release == .v15{return try semanticExportV15(in:container.mainContext)}
            if release == .v14{return try semanticExportV14(in:container.mainContext)}
            if release == .v13{return try semanticExportV13(in:container.mainContext)}
            if release == .v12 { return try semanticExportV12(in: container.mainContext) }
            if release == .v11 { return try semanticExportV11(in: container.mainContext) }
            if release == .v10 { return try semanticExportV10(in: container.mainContext) }
            if release == .v9 { return try semanticExportV9(in: container.mainContext) }
            if release == .v8 { return try semanticExportV8(in: container.mainContext) }
            if release == .v7 { return try semanticExportV7(in: container.mainContext) }
            if release == .v6 { return try semanticExportV6(in: container.mainContext) }
            if release == .v5 { return try semanticExportV5(in: container.mainContext) }
            if release == .v4 { return try semanticExportV4(in: container.mainContext) }
            if release == .v3 { return try semanticExportV3(in: container.mainContext) }
            return try semanticExport(in: container.mainContext)
        }
    }

    @MainActor
    private func semanticExport(in context: ModelContext) throws -> Data {
        let records = try frozenPreV6SemanticRecords(in: context)
        return try BackupCanonicalEncoderV1().encodeRecords(records).data
    }

    /// Frozen records-schema-1 projection used only to compare pre-V6 store
    /// generations. It deliberately cannot fetch or encode V6 location rows.
    @MainActor
    private func frozenPreV6SemanticRecords(
        in context: ModelContext
    ) throws -> V4BackupRecordsV1 {
        func ordered(_ value: UUID) -> String { value.uuidString.lowercased() }
        let sites = try context.fetch(FetchDescriptor<Site>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let workflow = try context.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try context.fetch(FetchDescriptor<EvidenceFile>())
        let issues = try context.fetch(FetchDescriptor<Issue>())
        let packets = try context.fetch(FetchDescriptor<Packet>())
        let reports = try context.fetch(FetchDescriptor<Report>())
        return V4BackupRecordsV1(
            assets: assets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                    packContentVersion: $0.packContentVersion, label: $0.label,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            deletionLedger: nil,
            evidenceFiles: evidence.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    recordID: $0.recordID, purposeKey: $0.purposeKey,
                    relativePath: $0.relativePath, mimeType: $0.mimeType,
                    byteCount: $0.byteCount, sha256: $0.sha256,
                    createdAt: $0.createdAt,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount,
                    thumbnailSHA256: $0.thumbnailSHA256
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            issues: issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    assetID: $0.assetID, openedByRecordID: $0.openedByRecordID,
                    labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot,
                    status: $0.status, resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            mutationHistory: nil,
            packets: packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt,
                    createdAt: $0.createdAt
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            recordsSchemaVersion: 1,
            reports: reports.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    packetID: $0.packetID, sourceRecordID: $0.sourceRecordID,
                    snapshotSchemaVersion: $0.snapshotSchemaVersion,
                    snapshotRelativePath: $0.snapshotRelativePath,
                    snapshotSHA256: $0.snapshotSHA256, pdfState: $0.pdfState,
                    pdfRelativePath: $0.pdfRelativePath,
                    pdfSHA256: $0.pdfSHA256, createdAt: $0.createdAt,
                    replacesReportID: $0.replacesReportID
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            sites: sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    label: $0.label, address: $0.address,
                    timeZoneID: $0.timeZoneID, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            workflowRecords: workflow.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    assetID: $0.assetID, packetID: $0.packetID,
                    issueID: $0.issueID, parentRecordID: $0.parentRecordID,
                    recordRevisionRootID: $0.recordRevisionRootID,
                    revisesRecordID: $0.revisesRecordID,
                    evidenceSourceRecordID: $0.evidenceSourceRecordID,
                    revisionKind: $0.revisionKind, stage: $0.stage,
                    state: $0.state, draftStepKey: $0.draftStepKey,
                    startedAt: $0.startedAt, completedAt: $0.completedAt,
                    observedAtUTC: $0.observedAtUTC, timeZoneID: $0.timeZoneID,
                    utcOffsetMinutes: $0.utcOffsetMinutes, localDate: $0.localDate,
                    localTime: $0.localTime,
                    afterDarkAcknowledgementKey: $0.afterDarkAcknowledgementKey,
                    afterDarkAcknowledgementCopy: $0.afterDarkAcknowledgementCopy,
                    afterDarkAcknowledgementVersion: $0.afterDarkAcknowledgementVersion,
                    afterDarkAcknowledgementAccepted: $0.afterDarkAcknowledgementAccepted,
                    safePositionAcknowledgementKey: $0.safePositionAcknowledgementKey,
                    safePositionAcknowledgementCopy: $0.safePositionAcknowledgementCopy,
                    safePositionAcknowledgementVersion: $0.safePositionAcknowledgementVersion,
                    safePositionAcknowledgementAccepted: $0.safePositionAcknowledgementAccepted,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                    packContentVersion: $0.packContentVersion,
                    pdfTemplateID: $0.pdfTemplateID,
                    pdfTemplateVersion: $0.pdfTemplateVersion,
                    outcomeKey: $0.outcomeKey,
                    couldNotVerifyKey: $0.couldNotVerifyKey,
                    couldNotVerifyDisplaySnapshot: $0.couldNotVerifyDisplaySnapshot,
                    couldNotVerifyRegistryVersion: $0.couldNotVerifyRegistryVersion,
                    workPerformedLocalDate: $0.workPerformedLocalDate,
                    workDescription: $0.workDescription, note: $0.note,
                    finalizationMutationID: $0.finalizationMutationID
                )
            }.sorted { ordered($0.id) < ordered($1.id) },
            activityContracts: []
        )
    }

    @MainActor
    private func semanticExportV3(in context: ModelContext) throws -> Data {
        let records = try semanticExport(in: context)
        let ledger = try DeletionLedgerStore(context: context).snapshot().canonicalData()
        return try StoreMigrationCanonicalJSONV1.encode(
            StoreSemanticEnvelopeV3(records: records, deletionLedger: ledger)
        )
    }

    @MainActor
    private func semanticExportV4(in context: ModelContext) throws -> Data {
        let base = try semanticExportV3(in: context)
        let receipts = try context.fetch(FetchDescriptor<MutationReceiptRow>(sortBy: [SortDescriptor(\.receiptIdentity)])).map {
            MutationReceiptSemanticV1(
                mutationID: $0.mutationID,
                receiptIdentity: $0.receiptIdentity,
                envelopeData: $0.envelopeData,
                receiptData: $0.receiptData,
                reversalBasisData: $0.reversalBasisData,
                semanticReversalData: $0.semanticReversalData
            )
        }
        let quarantines = try context.fetch(FetchDescriptor<MutationQuarantineRow>()).sorted {
            $0.workspaceMutationKey < $1.workspaceMutationKey
        }.map {
            MutationQuarantineSemanticV1(
                workspaceMutationKey: $0.workspaceMutationKey,
                workspaceID: $0.workspaceID,
                mutationID: $0.mutationID,
                identityDomain: $0.identityDomain,
                acceptedIdentitySHA256: $0.acceptedIdentitySHA256,
                conflictingIdentitySHA256: $0.conflictingIdentitySHA256,
                detectedAt: $0.detectedAt
            )
        }
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>(sortBy: [SortDescriptor(\.workspaceID)])).map {
            WorkspaceMutationStateSemanticV1(workspaceID: $0.workspaceID, generationID: $0.generationID, replicaID: $0.activeReplicaID, revision: $0.workspaceRevision, sequence: $0.lastLocalSequence, mutableSemanticSHA256: $0.mutableSemanticSHA256)
        }
        let revisions = try context.fetch(FetchDescriptor<EntityMutationRevisionRow>(sortBy: [SortDescriptor(\.stableIdentity)])).map {
            EntityMutationRevisionSemanticV1(identity: $0.stableIdentity, revision: $0.revision, externalProjectionSHA256: $0.externalProjectionSHA256)
        }
        return try StoreMigrationCanonicalJSONV1.encode(
            StoreSemanticEnvelopeV4(base: base, receipts: receipts, quarantines: quarantines, states: states, entityRevisions: revisions)
        )
    }

    @MainActor
    private func semanticExportV5(in context: ModelContext) throws -> Data {
        let base = try semanticExportV4(in: context)
        let records = try context.fetch(
            FetchDescriptor<WorkflowRecord>(sortBy: [SortDescriptor(\.id)])
        )
        let rows = try ObservationAndTimeRowStoreV1.validatedIndex(in: context)
        let observationAndTime = try records.map { record in
            guard let row = rows[record.id] else {
                throw ObservationAndTimeRowFailureV1.missingRow(record.id)
            }
            try ObservationAndTimeSemanticV1(
                recordID: record.id,
                observationBasisData: row.observationBasisV1Data,
                temporalContextData: row.temporalContextV1Data
            )
        }
        return try StoreMigrationCanonicalJSONV1.encode(
            StoreSemanticEnvelopeV5(
                base: base,
                observationAndTime: observationAndTime
            )
        )
    }

    @MainActor
    private func semanticExportV6(in context: ModelContext) throws -> Data {
        let base = try semanticExportV5(in: context)
        let locationNodes = try context.fetch(
            FetchDescriptor<LocationNodeRow>(sortBy: [SortDescriptor(\.id)])
        ).map { row -> Data in
            _ = try row.value()
            return row.canonicalData
        }
        let hierarchyEvents = try context.fetch(
            FetchDescriptor<LocationHierarchyEventRow>(sortBy: [SortDescriptor(\.operationID)])
        ).map { row -> Data in
            _ = try row.values()
            return try StoreMigrationCanonicalJSONV1.encode(
                LocationHierarchySemanticV6(
                    planData: row.planData,
                    receiptData: row.receiptData
                )
            )
        }
        let placementEvents = try context.fetch(
            FetchDescriptor<AssetPlacementEventRow>(sortBy: [SortDescriptor(\.id)])
        ).map { row -> Data in
            _ = try row.value()
            return row.canonicalData
        }
        let compositionEdges = try context.fetch(
            FetchDescriptor<AssetCompositionEdgeRow>(sortBy: [SortDescriptor(\.id)])
        ).map { row -> Data in
            _ = try row.value()
            return row.canonicalData
        }
        let compositionEvents = try context.fetch(
            FetchDescriptor<AssetCompositionEventRow>(sortBy: [SortDescriptor(\.id)])
        ).map { row -> Data in
            _ = try row.value()
            return row.canonicalData
        }
        let migrationReceipts = try context.fetch(
            FetchDescriptor<LocationMigrationReceiptRow>(sortBy: [SortDescriptor(\.candidateGenerationID)])
        ).map { row -> Data in
            _ = try row.value()
            return row.canonicalData
        }
        return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV6(
            base: base,
            locationNodes: locationNodes,
            hierarchyEvents: hierarchyEvents,
            placementEvents: placementEvents,
            compositionEdges: compositionEdges,
            compositionEvents: compositionEvents,
            migrationReceipts: migrationReceipts
        ))
    }

    @MainActor
    private func semanticExportV7(in context: ModelContext) throws -> Data {
        let base = try semanticExportV6(in: context)
        let savedSmartViews = try context.fetch(
            FetchDescriptor<SavedSmartViewRowV1>(sortBy: [SortDescriptor(\.id)])
        ).map { row -> Data in
            _ = try row.descriptor()
            return row.canonicalData
        }
        return try StoreMigrationCanonicalJSONV1.encode(
            StoreSemanticEnvelopeV7(base: base, savedSmartViews: savedSmartViews)
        )
    }

    @MainActor
    private func semanticExportV8(in context: ModelContext) throws -> Data {
        let base = try semanticExportV7(in: context)
        let assurance = try context.fetch(
            FetchDescriptor<RequirementAssuranceRow>(sortBy: [SortDescriptor(\.workflowRecordID)])
        ).map { try $0.snapshot() }
        return try StoreMigrationCanonicalJSONV1.encode(
            StoreSemanticEnvelopeV8(base: base, requirementAssurance: assurance)
        )
    }

    @MainActor
    private func semanticExportV9(in context: ModelContext) throws -> Data {
        let base = try semanticExportV8(in: context)
        let parties = try context.fetch(FetchDescriptor<ServicePartyRow>(sortBy: [SortDescriptor(\.partyID)])).map { try $0.value() }
        let roles = try context.fetch(FetchDescriptor<SitePartyRoleEventRow>(sortBy: [SortDescriptor(\.eventID)])).map { try $0.value() }
        let actors = try context.fetch(FetchDescriptor<ActorSnapshotRow>(sortBy: [SortDescriptor(\.snapshotID)])).map { try $0.value() }
        let qualifications = try context.fetch(FetchDescriptor<QualificationSnapshotRow>(sortBy: [SortDescriptor(\.snapshotID)])).map { try $0.value() }
        let signoffs = try context.fetch(FetchDescriptor<SignoffSnapshotRow>(sortBy: [SortDescriptor(\.snapshotID)])).map { try $0.value() }
        return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV9(base: base, parties: parties, roles: roles, actors: actors, qualifications: qualifications, signoffs: signoffs))
    }

    @MainActor
    private func semanticExportV10(in context: ModelContext) throws -> Data {
        let base = try semanticExportV9(in: context)
        let kindBindings = try context.fetch(FetchDescriptor<AssetKindBindingEventRow>(sortBy: [SortDescriptor(\.eventID)])).map { try $0.value() }
        let workflowBindings = try context.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>(sortBy: [SortDescriptor(\.eventID)])).map { try $0.value() }
        let productIdentities = try context.fetch(FetchDescriptor<AssetProductIdentityRow>(sortBy: [SortDescriptor(\.identityID)])).map { try $0.value() }
        let lifecycleEvents = try context.fetch(FetchDescriptor<AssetLifecycleEventRow>(sortBy: [SortDescriptor(\.eventID)])).map { try $0.value() }
        let successorLinks = try context.fetch(FetchDescriptor<AssetSuccessorLinkRow>(sortBy: [SortDescriptor(\.linkID)])).map { try $0.value() }
        let subjectScopes = try context.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>(sortBy: [SortDescriptor(\.snapshotID)])).map { try $0.value() }
        return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV10(
            base: base,
            kindBindings: kindBindings,
            workflowBindings: workflowBindings,
            productIdentities: productIdentities,
            lifecycleEvents: lifecycleEvents,
            successorLinks: successorLinks,
            subjectScopes: subjectScopes
        ))
    }

    @MainActor
    private func semanticExportV11(in context: ModelContext) throws -> Data {
        try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV11(
            base: semanticExportV10(in: context),
            authoritySources: context.fetch(FetchDescriptor<AuthoritySourceReleaseRow>(sortBy: [SortDescriptor(\.releaseID)])).map { try $0.value() },
            requirementBindings: context.fetch(FetchDescriptor<RequirementBasisBindingRow>(sortBy: [SortDescriptor(\.bindingID)])).map { try $0.value() },
            applicabilityContexts: context.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>(sortBy: [SortDescriptor(\.snapshotID)])).map { try $0.value() },
            assessmentScopes: context.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>(sortBy: [SortDescriptor(\.snapshotID)])).map { try $0.value() },
            severityScales: context.fetch(FetchDescriptor<SeverityScaleReleaseRow>(sortBy: [SortDescriptor(\.releaseID)])).map { try $0.value() },
            findingBindings: context.fetch(FetchDescriptor<FindingClassificationBindingRow>(sortBy: [SortDescriptor(\.bindingID)])).map { try $0.value() },
            measurementProtocols: context.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(sortBy: [SortDescriptor(\.releaseID)])).map { try $0.value() },
            evaluatorDescriptors: context.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>(sortBy: [SortDescriptor(\.descriptorID)])).map { try $0.value() },
            derivedFacts: context.fetch(FetchDescriptor<DerivedFactProvenanceRow>(sortBy: [SortDescriptor(\.provenanceID)])).map { try $0.value() }
        ))
    }

    @MainActor
    private func semanticExportV12(in context: ModelContext) throws -> Data {
        try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV12(
            base: semanticExportV11(in: context),
            descriptors: context.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(sortBy: [SortDescriptor(\.descriptorReleaseID)])).map { try $0.value() },
            events: context.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(sortBy: [SortDescriptor(\.eventID)])).map { try $0.value() }
        ))
    }
    @MainActor private func semanticExportV13(in context:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV13(base:semanticExportV12(in:context),visibilities:context.fetch(FetchDescriptor<EvidenceVisibilityRow>(sortBy:[SortDescriptor(\.visibilityID)])).map{try $0.value()},links:context.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(sortBy:[SortDescriptor(\.linkID)])).map{try $0.value()},manifests:context.fetch(FetchDescriptor<AssuranceManifestRow>(sortBy:[SortDescriptor(\.manifestID)])).map{try $0.value()},attestations:context.fetch(FetchDescriptor<AttestationRow>(sortBy:[SortDescriptor(\.attestationID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV14(in context:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV14(base:semanticExportV13(in:context),transitions:context.fetch(FetchDescriptor<InspectionReviewTransitionRow>(sortBy:[SortDescriptor(\.transitionID)])).map{try $0.value()},dispositions:context.fetch(FetchDescriptor<ReviewDispositionRow>(sortBy:[SortDescriptor(\.dispositionID)])).map{try $0.value()},changeRequests:context.fetch(FetchDescriptor<ChangeRequestRow>(sortBy:[SortDescriptor(\.requestRevisionID)])).map{try $0.value()},policies:context.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(sortBy:[SortDescriptor(\.releaseID)])).map{try $0.value()},events:context.fetch(FetchDescriptor<CorrectiveActionEventRow>(sortBy:[SortDescriptor(\.eventID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV15(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV15(base:semanticExportV14(in:c),manifests:c.fetch(FetchDescriptor<WorkPacketManifestRow>(sortBy:[SortDescriptor(\.manifestID)])).map{try $0.value()},claims:c.fetch(FetchDescriptor<WorkItemClaimRow>(sortBy:[SortDescriptor(\.claimID)])).map{try $0.value()},leases:c.fetch(FetchDescriptor<WorkLeaseRow>(sortBy:[SortDescriptor(\.leaseID)])).map{try $0.value()},releases:c.fetch(FetchDescriptor<WorkReleaseRow>(sortBy:[SortDescriptor(\.releaseID)])).map{try $0.value()},handoffs:c.fetch(FetchDescriptor<WorkHandoffRow>(sortBy:[SortDescriptor(\.handoffID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV16(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV16(base:semanticExportV15(in:c),checkpoints:c.fetch(FetchDescriptor<FieldDraftCheckpointRow>(sortBy:[SortDescriptor(\.draftID)])).map{try $0.value()},stages:c.fetch(FetchDescriptor<AttachmentStagingItemRow>(sortBy:[SortDescriptor(\.stageID)])).map{try $0.value()},sagas:c.fetch(FetchDescriptor<DraftCommitSagaRow>(sortBy:[SortDescriptor(\.sagaID)])).map{try $0.value()},reservations:c.fetch(FetchDescriptor<DraftContentReservationRow>(sortBy:[SortDescriptor(\.reservationID)])).map{try $0.value()},commitReceipts:c.fetch(FetchDescriptor<DraftCommitReceiptRow>(sortBy:[SortDescriptor(\.receiptID)])).map{try $0.value()},discardReceipts:c.fetch(FetchDescriptor<DraftDiscardReceiptRow>(sortBy:[SortDescriptor(\.receiptID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV17(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV17(base:semanticExportV16(in:c),promotedReleases:c.fetch(FetchDescriptor<PromotedPackageReleaseRow>(sortBy:[SortDescriptor(\.releaseRecordID)])).map{try $0.value()},sandboxRuns:c.fetch(FetchDescriptor<PackageSandboxRunRow>(sortBy:[SortDescriptor(\.runID)])).map{try $0.value()},promotionReceipts:c.fetch(FetchDescriptor<PackagePromotionReceiptRow>(sortBy:[SortDescriptor(\.receiptID)])).map{try $0.value()},activePointers:c.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(sortBy:[SortDescriptor(\.pointerID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV18(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV18(base:semanticExportV17(in:c),instruments:c.fetch(FetchDescriptor<InstrumentReferenceRow>(sortBy:[SortDescriptor(\.referenceID)])).map{try $0.value()},calibrations:c.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>(sortBy:[SortDescriptor(\.snapshotID)])).map{try $0.value()},captures:c.fetch(FetchDescriptor<MeasurementCaptureRow>(sortBy:[SortDescriptor(\.captureID)])).map{try $0.value()},series:c.fetch(FetchDescriptor<MeasurementSeriesRow>(sortBy:[SortDescriptor(\.snapshotID)])).map{try $0.value()},assessments:c.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>(sortBy:[SortDescriptor(\.assessmentID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV19(in c:ModelContext)throws->Data{let values=try privacyTransformValuesV19(in:c);return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV19(base:semanticExportV18(in:c),policies:values.policies,regions:values.regions,manifests:values.manifests,reviews:values.reviews))}
    @MainActor private func semanticExportV20(in c:ModelContext)throws->Data{let v=try clientCapabilityValuesV20(in:c);return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV20(base:semanticExportV19(in:c),profiles:v.profiles,decisions:v.decisions,policies:v.policies,dispositions:v.dispositions))}
    @MainActor private func semanticExportV21(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV21(base:semanticExportV20(in:c),receipts:c.fetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>(sortBy:[SortDescriptor(\.receiptID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV22(in c:ModelContext)throws->Data{let releases=try c.fetch(FetchDescriptor<FieldReferenceReleaseRow>(sortBy:[SortDescriptor(\.releaseID)])).map{try $0.value()};let bindings=try c.fetch(FetchDescriptor<FieldReferenceBindingRow>(sortBy:[SortDescriptor(\.bindingID)])).map{row in guard let release=releases.first(where:{$0.releaseID==row.releaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return try row.value(release:release)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV22(base:semanticExportV21(in:c),releases:releases,bindings:bindings))}
    @MainActor private func semanticExportV23(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV23(base:semanticExportV22(in:c),receipts:c.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>(sortBy:[SortDescriptor(\.receiptID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV24(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV24(base:semanticExportV23(in:c),identities:c.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>(sortBy:[SortDescriptor(\.definitionID)])).map{try $0.value()},releases:c.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(sortBy:[SortDescriptor(\.releaseID)])).map{try $0.value()}))}
    @MainActor private func semanticExportV25(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV25(base:semanticExportV24(in:c),sessions:c.fetch(FetchDescriptor<SurveySessionRow>()).map{try $0.value()}.sorted{$0.sessionID.uuidString<$1.sessionID.uuidString},facts:c.fetch(FetchDescriptor<FactCaptureRow>()).map{try $0.value()}.sorted{$0.captureID.uuidString<$1.captureID.uuidString},subjects:c.fetch(FetchDescriptor<ProvisionalSubjectRow>()).map{try $0.value()}.sorted{$0.provisionalSubjectID.uuidString<$1.provisionalSubjectID.uuidString},promotions:c.fetch(FetchDescriptor<SubjectPromotionReceiptRow>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString},publications:c.fetch(FetchDescriptor<SurveyPublicationSnapshotRow>()).map{try $0.value()}.sorted{$0.snapshotID.uuidString<$1.snapshotID.uuidString}))}
    @MainActor private func semanticExportV26(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV26(base:semanticExportV25(in:c),locators:c.fetch(FetchDescriptor<AssetLocatorRow>()).map{try $0.value()}.sorted{$0.locatorID.uuidString<$1.locatorID.uuidString},receipts:c.fetch(FetchDescriptor<LocatorBindingReceiptRow>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString}))}
    @MainActor private func semanticExportV27(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV27(base:semanticExportV26(in:c),releases:c.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>()).map{try $0.value()}.sorted{$0.releaseID.uuidString<$1.releaseID.uuidString},events:c.fetch(FetchDescriptor<OccurrenceHistoryEventRow>()).map{try $0.value()}.sorted{$0.eventID.uuidString<$1.eventID.uuidString}))}
    @MainActor private func semanticExportV28(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV28(base:semanticExportV27(in:c),documents:c.fetch(FetchDescriptor<PlanDocumentRow>()).map{try $0.value()}.sorted{($0.planDocumentID.uuidString,$0.revision)<($1.planDocumentID.uuidString,$1.revision)},revisions:c.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()}.sorted{$0.planRevisionID.uuidString<$1.planRevisionID.uuidString},placements:c.fetch(FetchDescriptor<PlanPlacementRow>()).map{try $0.value()}.sorted{($0.placementID.uuidString,$0.revision)<($1.placementID.uuidString,$1.revision)},receipts:c.fetch(FetchDescriptor<RebaseReceiptRow>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString}))}
    @MainActor private func semanticExportV29(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV29(base:semanticExportV28(in:c),events:c.fetch(FetchDescriptor<AssetPoseEventRow>()).map{try $0.value()}.sorted{$0.eventID.uuidString<$1.eventID.uuidString},observations:c.fetch(FetchDescriptor<SpatialAnchorObservationRow>()).map{try $0.value()}.sorted{$0.observationID.uuidString<$1.observationID.uuidString}))}
    @MainActor private func semanticExportV30(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV30(base:semanticExportV29(in:c),contexts:c.fetch(FetchDescriptor<EvidenceContextRow>()).map{try $0.value()}.sorted{$0.contextID.uuidString<$1.contextID.uuidString},pairs:c.fetch(FetchDescriptor<PairedObservationLinkRow>()).map{try $0.value()}.sorted{$0.linkID.uuidString<$1.linkID.uuidString}))}
    @MainActor private func semanticExportV31(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV31(base:semanticExportV30(in:c),systems:c.fetch(FetchDescriptor<LightingSystemRow>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString},observations:c.fetch(FetchDescriptor<LightingObservationRow>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString},issues:c.fetch(FetchDescriptor<LightingIssueRow>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString},plans:c.fetch(FetchDescriptor<MeasurementPlanRow>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString},claims:c.fetch(FetchDescriptor<LightingClaimStateRow>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString}))}
    @MainActor private func semanticExportV32(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV32(base:semanticExportV31(in:c),assistanceAcceptanceReceipts:c.fetch(FetchDescriptor<AssistanceAcceptanceReceiptRow>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString}))}
    @MainActor private func semanticExportV33(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV33(base:semanticExportV32(in:c),clips:c.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).map{try $0.value()}.sorted{$0.clipID.uuidString<$1.clipID.uuidString},anchors:c.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>()).map{try $0.value()}.sorted{$0.anchorID.uuidString<$1.anchorID.uuidString}))}
    @MainActor private func semanticExportV34(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV34(base:semanticExportV33(in:c),snapshots:c.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.snapshotID.uuidString)<($1.workspaceID.rawValue.uuidString,$1.snapshotID.uuidString)}))}
    @MainActor private func semanticExportV35(in c:ModelContext)throws->Data{let contacts=try c.fetch(FetchDescriptor<ServiceContactPointRow>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.contactPointID.uuidString)<($1.workspaceID.rawValue.uuidString,$1.contactPointID.uuidString)},intents=try c.fetch(FetchDescriptor<SystemHandoffIntentRow>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.intentID.uuidString)<($1.workspaceID.rawValue.uuidString,$1.intentID.uuidString)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV35(base:semanticExportV34(in:c),contacts:contacts,handoffIntents:intents))}
    @MainActor private func semanticExportV36(in c:ModelContext)throws->Data{try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV36(base:semanticExportV35(in:c),envelopes:c.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.activityID.uuidString)<($1.workspaceID.rawValue.uuidString,$1.activityID.uuidString)},transitions:c.fetch(FetchDescriptor<ActivityStateTransitionRow>()).map{try $0.value()}.sorted{$0.transitionID.uuidString<$1.transitionID.uuidString},installationTaskResults:c.fetch(FetchDescriptor<InstallationTaskResultRow>()).map{try $0.value()}.sorted(),installationAsBuiltSnapshots:c.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).map{try $0.value()}.sorted{$0.snapshotID.uuidString<$1.snapshotID.uuidString},punchReviewBasisSnapshots:c.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).map{try $0.value()}.sorted{$0.basisID.uuidString<$1.basisID.uuidString}))}
    @MainActor private func semanticExportV37(in c:ModelContext)throws->Data{let entries=try c.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString.lowercased(),$0.entryID.uuidString.lowercased())<($1.workspaceID.rawValue.uuidString.lowercased(),$1.entryID.uuidString.lowercased())};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV37(base:semanticExportV36(in:c),workResources:entries))}
    @MainActor private func semanticExportV38(in c:ModelContext)throws->Data{let calendars=try c.fetch(FetchDescriptor<ExceptionCalendarReleaseRow>()).map{try $0.value()}.sorted{$0.releaseID.uuidString.lowercased()<$1.releaseID.uuidString.lowercased()},overrides=try c.fetch(FetchDescriptor<ScheduleOverrideEventRow>()).map{try $0.value()}.sorted{$0.eventID.uuidString.lowercased()<$1.eventID.uuidString.lowercased()};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV38(base:semanticExportV37(in:c),calendars:calendars,overrides:overrides))}
    @MainActor private func semanticExportV39(in c:ModelContext)throws->Data{let records=try c.fetch(FetchDescriptor<ServiceRequestRecordRow>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.recordID.uuidString,$0.revision)<($1.workspaceID.rawValue.uuidString,$1.recordID.uuidString,$1.revision)},dispositions=try c.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>()).map{try $0.value()}.sorted{$0.eventID.uuidString<$1.eventID.uuidString},links=try c.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>()).map{try $0.value()}.sorted{$0.eventID.uuidString<$1.eventID.uuidString};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV39(base:semanticExportV38(in:c),records:records,dispositions:dispositions,workLinks:links))}
    @MainActor private func semanticExportV40(in c:ModelContext)throws->Data{func ordered<T>(_ values:[T],key:(T)->(String,String,UInt64))->[T]{values.sorted{key($0)<key($1)}};let incidents=ordered(try c.fetch(FetchDescriptor<AssetServiceIncidentRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)},impacts=ordered(try c.fetch(FetchDescriptor<ServiceImpactSegmentRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)},causes=ordered(try c.fetch(FetchDescriptor<ServiceCauseAssertionRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)},remedies=ordered(try c.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)},repairs=ordered(try c.fetch(FetchDescriptor<ServiceRepairIntervalRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)},restorations=ordered(try c.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)},exposures=ordered(try c.fetch(FetchDescriptor<QualifiedServiceExposureRow>()).map{try $0.value()}){($0.workspaceID.rawValue.uuidString,$0.eventID.uuidString,$0.revision)};let events=try (incidents.map{try ServiceReliabilityCanonicalCodecV1.encode($0)}+impacts.map{try ServiceReliabilityCanonicalCodecV1.encode($0)}+causes.map{try ServiceReliabilityCanonicalCodecV1.encode($0)}+remedies.map{try ServiceReliabilityCanonicalCodecV1.encode($0)}+repairs.map{try ServiceReliabilityCanonicalCodecV1.encode($0)}+restorations.map{try ServiceReliabilityCanonicalCodecV1.encode($0)}+exposures.map{try ServiceReliabilityCanonicalCodecV1.encode($0)});return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV40(base:semanticExportV39(in:c),events:events))}
    @MainActor private func semanticExportV41(in c:ModelContext)throws->Data{let parts=try c.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).map{try $0.value()}.sorted{$0.partID.uuidString<$1.partID.uuidString},locations=try c.fetch(FetchDescriptor<StockStorageLocationRowV1>()).map{try $0.value()}.sorted{$0.locationID.uuidString<$1.locationID.uuidString},movements=try c.fetch(FetchDescriptor<StockMovementEventRowV1>()).map{try $0.value()}.sorted{$0.movementID.uuidString<$1.movementID.uuidString},uses=try c.fetch(FetchDescriptor<StockUseReceiptRowV1>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString},reversals=try c.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString},returns=try c.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString},abandonments=try c.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).map{try $0.value()}.sorted{$0.dispositionID.uuidString<$1.dispositionID.uuidString};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV41(base:semanticExportV40(in:c),parts:parts,locations:locations,movements:movements,uses:uses,reversals:reversals,returns:returns,abandonments:abandonments))}
    @MainActor private func semanticExportV42(in c:ModelContext)throws->Data{let plans=try c.fetch(FetchDescriptor<MyDayPlanRowV1>()).map{try $0.value()}.sorted{($0.key.stableKey,$0.revision,$0.planID.uuidString)<($1.key.stableKey,$1.revision,$1.planID.uuidString)},receipts=try c.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).map{try $0.value()}.sorted{$0.receiptSHA256<$1.receiptSHA256};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV42(base:semanticExportV41(in:c),plans:plans,carryoverReceipts:receipts))}
    @MainActor private func semanticExportV43(in c:ModelContext)throws->Data{let associations=try c.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).map{try $0.value()}.sorted{($0.workspaceID,$0.evidenceID,$0.resultingEvidenceRevision,$0.associationEventID)<($1.workspaceID,$1.evidenceID,$1.resultingEvidenceRevision,$1.associationEventID)},sequences=try c.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.sequenceID.uuidString,$0.revision)<($1.workspaceID.rawValue.uuidString,$1.sequenceID.uuidString,$1.revision)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV43(base:semanticExportV42(in:c),associations:associations,sequences:sequences))}
    @MainActor private func semanticExportV44(in c:ModelContext)throws->Data{let profiles=try validatedShopReportProfileValues(in:c);return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV44(base:semanticExportV43(in:c),profiles:profiles))}
    @MainActor private func semanticExportV45(in c:ModelContext)throws->Data{let sessions=try validatedRoundSessionValues(in:c);return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV45(base:semanticExportV44(in:c),sessions:sessions))}
    @MainActor private func semanticExportV46(in c:ModelContext)throws->Data{let profiles=try c.fetch(FetchDescriptor<ImportMappingProfileRowV1>()).map{try $0.value()}.sorted{$0.profileID.uuidString<$1.profileID.uuidString};let sessions=try c.fetch(FetchDescriptor<BulkSessionRowV1>()).map{try $0.value()}.sorted{$0.sessionID.uuidString<$1.sessionID.uuidString};let receipts=try c.fetch(FetchDescriptor<BulkCommitReceiptRowV1>()).map{try $0.value()}.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString};try profiles.forEach{try $0.validate()};try sessions.forEach{try $0.validate()};try receipts.forEach{try $0.validate()};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV46(base:semanticExportV45(in:c),profiles:profiles,sessions:sessions,receipts:receipts))}
    @MainActor private func semanticExportV47(in c:ModelContext)throws->Data{let rows=try (c.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).map(\.canonicalData)).sorted{$0.lexicographicallyPrecedes($1)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV47(base:semanticExportV46(in:c),rows:rows))}
    @MainActor private func semanticExportV48(in c:ModelContext)throws->Data{let rows=try (c.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<CapturePromotionRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<SnippetRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).map(\.canonicalData)).sorted{$0.lexicographicallyPrecedes($1)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV48(base:semanticExportV47(in:c),rows:rows))}
    @MainActor private func semanticExportV49(in c:ModelContext)throws->Data{let rows=try (c.fetch(FetchDescriptor<ReinspectionPlanRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<UnchangedAttestationRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>()).map(\.canonicalData)).sorted{$0.lexicographicallyPrecedes($1)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV49(base:semanticExportV48(in:c),rows:rows))}
    @MainActor private func semanticExportV50(in c:ModelContext)throws->Data{let rows=try (c.fetch(FetchDescriptor<EntityAliasLinkRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).map(\.canonicalData)+c.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()).map(\.canonicalData)).sorted{$0.lexicographicallyPrecedes($1)};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV50(base:semanticExportV49(in:c),rows:rows))}
    @MainActor private func semanticExportV51(in c:ModelContext)throws->Data{let rows=try c.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()).map{try $0.value()}.sorted{$0.provenanceID.uuidString<$1.provenanceID.uuidString};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV51(base:semanticExportV50(in:c),rows:rows))}
    @MainActor private func semanticExportV52(in c:ModelContext)throws->Data{let rows=try c.fetch(FetchDescriptor<LightingDayInventoryWorkflowRowV1>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV52(base:semanticExportV51(in:c),rows:rows))}
    @MainActor private func semanticExportV53(in c:ModelContext)throws->Data{let rows=try c.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()).map{try $0.value()}.sorted{$0.recordID.uuidString<$1.recordID.uuidString};return try StoreMigrationCanonicalJSONV1.encode(StoreSemanticEnvelopeV53(base:semanticExportV52(in:c),rows:rows))}

    @MainActor
    private func semanticDigest(
        at modelStoreURL: URL,
        release: PersistentSchemaReleaseV1
    ) throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(
            try semanticExport(
                at: modelStoreURL,
                release: release,
                markerMigrationID: nil
            )
        )
    }

    @MainActor
    private func makeV1Container(at modelStoreURL: URL) throws -> ModelContainer {
        let schema = PersistentSchemaV1.makeSchema()
        let configuration = ModelConfiguration(
            "FieldEvidenceV1",
            schema: schema,
            url: modelStoreURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV2Container(
        at modelStoreURL: URL,
        migrate: Bool
    ) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV2.models,
            version: PersistentSchemaV2.versionIdentifier
        )
        let configuration = ModelConfiguration(
            "FieldEvidenceV2",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        if migrate {
            return try ModelContainer(
                for: schema,
                migrationPlan: PersistentSchemaMigrationPlanV1.self,
                configurations: [configuration]
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV3Container(
        at modelStoreURL: URL,
        migrate: Bool
    ) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV3.models, version: PersistentSchemaV3.versionIdentifier)
        let configuration = ModelConfiguration(
            "FieldEvidenceV3",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        if migrate {
            return try ModelContainer(
                for: schema,
                migrationPlan: PersistentSchemaMigrationPlanV2.self,
                configurations: [configuration]
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV4Container(at modelStoreURL: URL, migrate: Bool) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV4.models, version: PersistentSchemaV4.versionIdentifier)
        let configuration = ModelConfiguration(
            "FieldEvidenceV4",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: migrate ? PersistentSchemaMigrationPlanV3.self : nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV5Container(
        at modelStoreURL: URL,
        migrate: Bool
    ) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV5.models,
            version: PersistentSchemaV5.versionIdentifier
        )
        let configuration = ModelConfiguration(
            "FieldEvidenceV5",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: migrate ? PersistentSchemaMigrationPlanV4.self : nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV6Container(
        at modelStoreURL: URL,
        migrate: Bool
    ) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV6.models,
            version: PersistentSchemaV6.versionIdentifier
        )
        let configuration = ModelConfiguration(
            "FieldEvidenceV6",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: migrate ? PersistentSchemaMigrationPlanV5.self : nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV7Container(
        at modelStoreURL: URL,
        migrate: Bool
    ) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV7.models,
            version: PersistentSchemaV7.versionIdentifier
        )
        let configuration = ModelConfiguration(
            "FieldEvidenceV7",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: migrate ? PersistentSchemaMigrationPlanV6.self : nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV8Container(
        at modelStoreURL: URL,
        migrate: Bool
    ) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV8.models,
            version: PersistentSchemaV8.versionIdentifier
        )
        let configuration = ModelConfiguration(
            "FieldEvidenceV8",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: migrate ? PersistentSchemaMigrationPlanV7.self : nil,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeV9Container(at modelStoreURL: URL, migrate: Bool) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV9.models, version: PersistentSchemaV9.versionIdentifier)
        let configuration = ModelConfiguration("FieldEvidenceV9", schema: schema, url: modelStoreURL, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: migrate ? PersistentSchemaMigrationPlanV8.self : nil, configurations: [configuration])
    }

    @MainActor
    private func makeV10Container(at modelStoreURL: URL, migrate: Bool) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV10.models, version: PersistentSchemaV10.versionIdentifier)
        let configuration = ModelConfiguration("FieldEvidenceV10", schema: schema, url: modelStoreURL, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: migrate ? PersistentSchemaMigrationPlanV9.self : nil, configurations: [configuration])
    }

    @MainActor
    private func makeV11Container(at modelStoreURL: URL, migrate: Bool) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV11.models, version: PersistentSchemaV11.versionIdentifier)
        let configuration = ModelConfiguration("FieldEvidenceV11", schema: schema, url: modelStoreURL, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: migrate ? PersistentSchemaMigrationPlanV10.self : nil, configurations: [configuration])
    }

    @MainActor
    private func makeV12Container(at modelStoreURL: URL, migrate: Bool) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV12.models, version: PersistentSchemaV12.versionIdentifier)
        let configuration = ModelConfiguration("FieldEvidenceV12", schema: schema, url: modelStoreURL, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: migrate ? PersistentSchemaMigrationPlanV11.self : nil, configurations: [configuration])
    }
    @MainActor private func makeV13Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV13.models,version:PersistentSchemaV13.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV13",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV12.self:nil,configurations:[configuration])}
    @MainActor private func makeV14Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV14.models,version:PersistentSchemaV14.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV14",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV13.self:nil,configurations:[configuration])}
    @MainActor private func makeV15Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV15.models,version:PersistentSchemaV15.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV15",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV14.self:nil,configurations:[configuration])}
    @MainActor private func makeV16Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV16.models,version:PersistentSchemaV16.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV16",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV15.self:nil,configurations:[configuration])}
    @MainActor private func makeV17Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV17.models,version:PersistentSchemaV17.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV17",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV16.self:nil,configurations:[configuration])}
    @MainActor private func makeV18Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV18.models,version:PersistentSchemaV18.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV18",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV17.self:nil,configurations:[configuration])}
    @MainActor private func makeV19Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV19.models,version:PersistentSchemaV19.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV19",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV18.self:nil,configurations:[configuration])}
    @MainActor private func makeV20Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV20.models,version:PersistentSchemaV20.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV20",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV19.self:nil,configurations:[configuration])}
    @MainActor private func makeV21Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV21.models,version:PersistentSchemaV21.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV21",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV20.self:nil,configurations:[configuration])}
    @MainActor private func makeV22Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV22.models,version:PersistentSchemaV22.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV22",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV21.self:nil,configurations:[configuration])}
    @MainActor private func makeV23Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV23.models,version:PersistentSchemaV23.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV23",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV22.self:nil,configurations:[configuration])}
    @MainActor private func makeV24Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV24.models,version:PersistentSchemaV24.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV24",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV23.self:nil,configurations:[configuration])}
    @MainActor private func makeV25Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV25.models,version:PersistentSchemaV25.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV25",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV24.self:nil,configurations:[configuration])}
    @MainActor private func makeV26Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV26.models,version:PersistentSchemaV26.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV26",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV25.self:nil,configurations:[configuration])}
    @MainActor private func makeV27Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV27.models,version:PersistentSchemaV27.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV27",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV26.self:nil,configurations:[configuration])}
    @MainActor private func makeV28Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV28.models,version:PersistentSchemaV28.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV28",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV27.self:nil,configurations:[configuration])}
    @MainActor private func makeV29Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV29.models,version:PersistentSchemaV29.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV29",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV28.self:nil,configurations:[configuration])}
    @MainActor private func makeV30Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV30.models,version:PersistentSchemaV30.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV30",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV29.self:nil,configurations:[configuration])}
    @MainActor private func makeV31Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV31.models,version:PersistentSchemaV31.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV31",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV30.self:nil,configurations:[configuration]);try validateV31LightingAdmissions(in:container.mainContext);return container}
    @MainActor private func makeV32Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV32.models,version:PersistentSchemaV32.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV32",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV31.self:nil,configurations:[configuration]);_ = try requireAssistanceAcceptanceReceipts(in:container.mainContext);return container}
    @MainActor private func makeV33Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV33.models,version:PersistentSchemaV33.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV33",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV32.self:nil,configurations:[configuration]);_ = try requireTemporalEvidence(in:container.mainContext);return container}
    @MainActor private func makeV34Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV34.models,version:PersistentSchemaV34.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV34",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV33.self:nil,configurations:[configuration]);_ = try requireAssetLabels(in:container.mainContext);return container}
    @MainActor private func makeV35Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV35.models,version:PersistentSchemaV35.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV35",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV34.self:nil,configurations:[configuration]);_ = try requireOperationalContacts(in:container.mainContext);return container}
    @MainActor private func makeV36Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV36.models,version:PersistentSchemaV36.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV36",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV35.self:nil,configurations:[configuration]);_ = try requireActivityContracts(in:container.mainContext);return container}
    @MainActor private func makeV37Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{guard C50IncumbentFileExchangeStoreGenerationBoundaryV1.validate() else{throw StoreMigrationFailure.invalidContract};let schema=Schema(PersistentSchemaV37.models,version:PersistentSchemaV37.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV37",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV36.self:nil,configurations:[configuration]);_ = try requireActivityContracts(in:container.mainContext);_ = try requireWorkResources(in:container.mainContext);return container}
    @MainActor private func makeV38Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{guard C51ScheduleExceptionStoreGenerationBoundaryV1.validate() else{throw StoreMigrationFailure.invalidContract};let schema=Schema(PersistentSchemaV38.models,version:PersistentSchemaV38.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV38",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV37.self:nil,configurations:[configuration]);_ = try requireActivityContracts(in:container.mainContext);_ = try requireWorkResources(in:container.mainContext);_ = try requireScheduleExceptions(in:container.mainContext);return container}
    @MainActor private func makeV39Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{guard C52ServiceRequestStoreGenerationBoundaryV1.validate() else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let schema=Schema(PersistentSchemaV39.models,version:PersistentSchemaV39.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV39",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV38.self:nil,configurations:[configuration]);_ = try requireActivityContracts(in:container.mainContext);_ = try requireWorkResources(in:container.mainContext);_ = try requireScheduleExceptions(in:container.mainContext);_ = try requireServiceRequests(in:container.mainContext);return container}
    @MainActor private func makeV40Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV40.models,version:PersistentSchemaV40.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV40",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);let container=try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV39.self:nil,configurations:[configuration]);_ = try requireActivityContracts(in:container.mainContext);_ = try requireWorkResources(in:container.mainContext);_ = try requireScheduleExceptions(in:container.mainContext);_ = try requireServiceRequests(in:container.mainContext);_ = try requireServiceReliability(in:container.mainContext);return container}
    @MainActor private func makeV41Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV41.models,version:PersistentSchemaV41.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV41",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV40.self:nil,configurations:[configuration])}
    @MainActor private func makeV42Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV42.models,version:PersistentSchemaV42.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV42",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV41.self:nil,configurations:[configuration])}
    @MainActor private func makeV43Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV43.models,version:PersistentSchemaV43.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV43",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV42.self:nil,configurations:[configuration])}
    @MainActor private func makeV44Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV44.models,version:PersistentSchemaV44.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV44",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV43.self:nil,configurations:[configuration])}
    @MainActor private func makeV45Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV45.models,version:PersistentSchemaV45.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV45",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV44.self:nil,configurations:[configuration])}
    @MainActor private func makeV46Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV46.models,version:PersistentSchemaV46.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV46",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV45.self:nil,configurations:[configuration])}
    @MainActor private func makeV47Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV47.models,version:PersistentSchemaV47.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV47",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV46.self:nil,configurations:[configuration])}
    @MainActor private func makeV48Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV48.models,version:PersistentSchemaV48.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV48",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV47.self:nil,configurations:[configuration])}
    @MainActor private func makeV49Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV49.models,version:PersistentSchemaV49.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV49",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV48.self:nil,configurations:[configuration])}
    @MainActor private func makeV50Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV50.models,version:PersistentSchemaV50.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV50",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV49.self:nil,configurations:[configuration])}
    @MainActor private func makeV51Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV51.models,version:PersistentSchemaV51.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV51",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV50.self:nil,configurations:[configuration])}
    @MainActor private func makeV52Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV52.models,version:PersistentSchemaV52.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV52",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV51.self:nil,configurations:[configuration])}
    @MainActor private func makeV53Container(at modelStoreURL:URL,migrate:Bool)throws->ModelContainer{let schema=Schema(PersistentSchemaV53.models,version:PersistentSchemaV53.versionIdentifier);let configuration=ModelConfiguration("FieldEvidenceV53",schema:schema,url:modelStoreURL,allowsSave:true,cloudKitDatabase:.none);return try ModelContainer(for:schema,migrationPlan:migrate ? PersistentSchemaMigrationPlanV52.self:nil,configurations:[configuration])}
    @MainActor private func assetLabelRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()).isEmpty}
    @MainActor private func requireAssetLabels(in c:ModelContext)throws->Int{let rows=try c.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>());for row in rows{_ = try row.value()};guard Set(rows.map(\.stableIdentity)).count==rows.count else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};return rows.count}
    @MainActor private func operationalContactRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ServiceContactPointRow>()).isEmpty&&c.fetch(FetchDescriptor<SystemHandoffIntentRow>()).isEmpty}
    @MainActor private func requireOperationalContacts(in c:ModelContext)throws->Int{let contacts=try c.fetch(FetchDescriptor<ServiceContactPointRow>()),intents=try c.fetch(FetchDescriptor<SystemHandoffIntentRow>());let values=try contacts.map{try $0.value()},handoffs=try intents.map{try $0.value()};guard Set(contacts.map(\.stableIdentity)).count==contacts.count,Set(intents.map(\.stableIdentity)).count==intents.count,values.allSatisfy({$0.privacyClass == .workspaceCustomerData}),Set(handoffs.map(\.intentID)).count==handoffs.count else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};return contacts.count+intents.count}

    @MainActor private func validateV31LightingAdmissions(in context:ModelContext)throws{
        let systems=try context.fetch(FetchDescriptor<LightingSystemRow>()).map{try $0.value()}
        let observations=try context.fetch(FetchDescriptor<LightingObservationRow>()).map{try $0.value()}
        let issues=try context.fetch(FetchDescriptor<LightingIssueRow>()).map{try $0.value()}
        let plans=try context.fetch(FetchDescriptor<MeasurementPlanRow>()).map{try $0.value()}
        let claims=try context.fetch(FetchDescriptor<LightingClaimStateRow>()).map{try $0.value()}
        var journalSystems:[LightingSystemV1]=[],journalObservations:[LightingObservationV1]=[],journalIssues:[LightingIssueV1]=[],journalPlans:[MeasurementPlanV1]=[],journalClaims:[LightingClaimStateV1]=[]
        for row in try context.fetch(FetchDescriptor<MutationReceiptRow>()){
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
            guard envelope.workspaceID.rawValue==row.workspaceID,envelope.mutationID.rawValue==row.mutationID,envelope.commandKind.rawValue==row.commandKind,(try envelope.canonicalSHA256())==row.envelopeSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            guard case let .applyLighting(operation)=envelope.command else{continue}
            do{try operation.validate();try LightingPersistedAdmissionV1.validate(operation,in:context)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            switch operation{case let .appendSystem(v,_,_):journalSystems.append(v);case let .appendObservation(v,_,_):journalObservations.append(v);case let .appendIssue(v,_,_):journalIssues.append(v);case let .appendMeasurementPlan(v,_,_):journalPlans.append(v);case let .appendClaim(v,_,_):journalClaims.append(v)}
        }
        guard journalSystems.count==systems.count,journalObservations.count==observations.count,journalIssues.count==issues.count,journalPlans.count==plans.count,journalClaims.count==claims.count,Set(journalSystems.map(\.recordID))==Set(systems.map(\.recordID)),Set(journalObservations.map(\.recordID))==Set(observations.map(\.recordID)),Set(journalIssues.map(\.recordID))==Set(issues.map(\.recordID)),Set(journalPlans.map(\.recordID))==Set(plans.map(\.recordID)),Set(journalClaims.map(\.recordID))==Set(claims.map(\.recordID)),journalSystems.allSatisfy({systems.contains($0)}),journalObservations.allSatisfy({observations.contains($0)}),journalIssues.allSatisfy({issues.contains($0)}),journalPlans.allSatisfy({plans.contains($0)}),journalClaims.allSatisfy({claims.contains($0)}) else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
    }

    @MainActor
    private func makeFreshV2Container(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let container = try makeV2Container(at: modelStoreURL, migrate: false)
        try insertOrRequireV2Marker(
            in: container.mainContext,
            migrationID: markerMigrationID
        )
        return container
    }

    @MainActor
    private func makeFreshV3Container(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let container = try makeV3Container(at: modelStoreURL, migrate: false)
        try insertOrRequireV3Marker(
            in: container.mainContext,
            migrationID: markerMigrationID
        )
        return container
    }

    @MainActor
    private func makeFreshV4Container(at modelStoreURL: URL, markerMigrationID: UUID) throws -> ModelContainer {
        let container = try makeV4Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 4,
            releaseID: PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
            migrationID: markerMigrationID
        ))
        try context.save()
        _ = try requireV4Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV5Container(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let container = try makeV5Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 5,
            releaseID: PersistentSchemaReleaseRegistryV1.v5CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
            migrationID: markerMigrationID
        ))
        try context.save()
        _ = try requireV5Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV6Container(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let container = try makeV6Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 6,
            releaseID: PersistentSchemaReleaseRegistryV1.v6CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v5CompatibilityID,
            migrationID: markerMigrationID
        ))
        try context.save()
        _ = try requireV6Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV7Container(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let container = try makeV7Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 7,
            releaseID: PersistentSchemaReleaseRegistryV1.v7CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v6CompatibilityID,
            migrationID: markerMigrationID
        ))
        try context.save()
        _ = try requireV7Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV8Container(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let container = try makeV8Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 8,
            releaseID: PersistentSchemaReleaseRegistryV1.v8CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v7CompatibilityID,
            migrationID: markerMigrationID
        ))
        try context.save()
        _ = try requireV8Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV9Container(at modelStoreURL: URL, markerMigrationID: UUID) throws -> ModelContainer {
        let container = try makeV9Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(id: PersistentSchemaReleaseRegistryV1.v2MarkerID, schemaVersion: 9, releaseID: PersistentSchemaReleaseRegistryV1.v9CompatibilityID, predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v8CompatibilityID, migrationID: markerMigrationID))
        try context.save(); _ = try requireV9Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV10Container(at modelStoreURL: URL, markerMigrationID: UUID) throws -> ModelContainer {
        let container = try makeV10Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(id: PersistentSchemaReleaseRegistryV1.v2MarkerID, schemaVersion: 10, releaseID: PersistentSchemaReleaseRegistryV1.v10CompatibilityID, predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v9CompatibilityID, migrationID: markerMigrationID))
        try context.save(); _ = try requireV10Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV11Container(at modelStoreURL: URL, markerMigrationID: UUID) throws -> ModelContainer {
        let container = try makeV11Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(id: PersistentSchemaReleaseRegistryV1.v2MarkerID, schemaVersion: 11, releaseID: PersistentSchemaReleaseRegistryV1.v11CompatibilityID, predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v10CompatibilityID, migrationID: markerMigrationID))
        try context.save(); _ = try requireV11Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func makeFreshV12Container(at modelStoreURL: URL, markerMigrationID: UUID) throws -> ModelContainer {
        let container = try makeV12Container(at: modelStoreURL, migrate: false)
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(id: PersistentSchemaReleaseRegistryV1.v2MarkerID, schemaVersion: 12, releaseID: PersistentSchemaReleaseRegistryV1.v12CompatibilityID, predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v11CompatibilityID, migrationID: markerMigrationID))
        try context.save(); _ = try requireV12Marker(in: context, expectedMigrationID: markerMigrationID)
        return container
    }

    @MainActor
    private func insertOrRequireV3Marker(
        in context: ModelContext,
        migrationID: UUID
    ) throws {
        let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        if markers.isEmpty {
            context.insert(
                PersistentSchemaReleaseMarker(
                    id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
                    schemaVersion: 3,
                    releaseID: PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
                    predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v2CompatibilityID,
                    migrationID: migrationID
                )
            )
            try context.save()
        }
        _ = try requireV3Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    @discardableResult
    private func requireV3Marker(
        in context: ModelContext,
        expectedMigrationID: UUID?
    ) throws -> PersistentSchemaReleaseMarker {
        let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 3,
              marker.releaseID == PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v2CompatibilityID,
              marker.migrationID != nil,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV3DeletionLedger(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<Packet>(
            predicate: #Predicate { $0.contentDeletedAt != nil }
        )
        descriptor.fetchLimit = DeletionLedgerV2.maximumEntryCount + 1
        let packets = try context.fetch(descriptor)
        guard packets.count <= DeletionLedgerV2.maximumEntryCount else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let store = DeletionLedgerStore(context: context)
        var entries: [DeletionLedgerEntryV2] = []
        for packet in packets {
            guard let deletedAt = packet.contentDeletedAt else { continue }
            guard packet.evaluationCounted, packet.currentRecordID == nil else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            entries.append(
                try DeletionLedgerEntryV2(
                    identity: DeletionIdentityV2(kind: .packet, id: packet.id),
                    deletedAt: deletedAt
                )
            )
        }
        try store.stageUnion(entries)
        let marker = try requireV2Marker(in: context, expectedMigrationID: nil)
        guard let markerMigrationID = marker.migrationID else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        marker.schemaVersion = 3
        marker.releaseID = PersistentSchemaReleaseRegistryV1.v3CompatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        try context.save()
        _ = try requireV3Marker(in: context, expectedMigrationID: markerMigrationID)
    }

    @MainActor
    private func backfillV4MutationState(in context: ModelContext, migrationID: UUID) throws {
        let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        guard markers.count == 1, let marker = markers.first else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        if marker.schemaVersion == 4 {
            _ = try requireV4Marker(in: context, expectedMigrationID: migrationID)
            return
        }
        _ = try requireV3Marker(in: context, expectedMigrationID: migrationID)
        marker.schemaVersion = 4
        marker.releaseID = PersistentSchemaReleaseRegistryV1.v4CompatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseRegistryV1.v3CompatibilityID
        try context.save()
        _ = try requireV4Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    @discardableResult
    private func requireV4Marker(in context: ModelContext, expectedMigrationID: UUID?) throws -> PersistentSchemaReleaseMarker {
        let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 4,
              marker.releaseID == PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
              marker.migrationID != nil,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV5ObservationAndTimeMarker(
        in context: ModelContext,
        migrationID: UUID
    ) throws {
        let markers = try context.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        guard markers.count == 1, let marker = markers.first else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        if marker.schemaVersion == 5 {
            _ = try requireV5Marker(in: context, expectedMigrationID: migrationID)
        } else {
            _ = try requireV4Marker(in: context, expectedMigrationID: migrationID)
            marker.schemaVersion = 5
            marker.releaseID = PersistentSchemaReleaseRegistryV1.v5CompatibilityID
            marker.predecessorReleaseID = PersistentSchemaReleaseRegistryV1.v4CompatibilityID
            try context.save()
            _ = try requireV5Marker(in: context, expectedMigrationID: migrationID)
        }
        _ = try semanticExportV5(in: context)
    }

    @MainActor
    @discardableResult
    private func requireV5Marker(
        in context: ModelContext,
        expectedMigrationID: UUID?
    ) throws -> PersistentSchemaReleaseMarker {
        let markers = try context.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 5,
              marker.releaseID == PersistentSchemaReleaseRegistryV1.v5CompatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
              marker.migrationID != nil,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV6LocationBaseline(
        in context: ModelContext,
        migrationID: UUID,
        sourceGenerationID: UUID,
        targetGenerationID: UUID
    ) throws {
        let existingReceipts = try context.fetch(
            FetchDescriptor<LocationMigrationReceiptRow>()
        )
        if !existingReceipts.isEmpty {
            guard existingReceipts.count == 1 else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            _ = try requireV6Marker(
                in: context,
                expectedMigrationID: migrationID
            )
            let receipt = try LocationPersistenceCodecV1.decode(
                LocationMigrationReceiptV1.self,
                from: existingReceipts[0].canonicalData
            )
            guard receipt.sourceGenerationID == sourceGenerationID,
                  receipt.candidateGenerationID == targetGenerationID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            return
        }

        guard try context.fetch(FetchDescriptor<LocationNodeRow>()).isEmpty,
              try context.fetch(FetchDescriptor<LocationHierarchyEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetPlacementEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetCompositionEdgeRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetCompositionEventRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1,
              states[0].generationID == sourceGenerationID else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        let workspaceID = WorkspaceID(rawValue: states[0].workspaceID)
        let sites = try context.fetch(
            FetchDescriptor<Site>(sortBy: [SortDescriptor(\.id)])
        )
        let siteByID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
        let assets = try context.fetch(
            FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.id)])
        )
        var bindings: [LocationMigratedBaselineBindingV1] = []
        for asset in assets {
            guard let site = siteByID[asset.siteID] else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            let eventID = deterministicLocationUUID(
                domain: "field-evidence/v23/c35/migrated-placement",
                workspaceID: workspaceID.rawValue,
                assetID: asset.id
            )
            let episodeID = deterministicLocationUUID(
                domain: "field-evidence/v23/c35/migrated-episode",
                workspaceID: workspaceID.rawValue,
                assetID: asset.id
            )
            let mutationID = deterministicLocationUUID(
                domain: "field-evidence/v23/c35/migrated-mutation",
                workspaceID: workspaceID.rawValue,
                assetID: asset.id
            )
            let event = try AssetPlacementEventV1(
                id: eventID,
                workspaceID: workspaceID,
                assetID: asset.id,
                siteID: asset.siteID,
                locationNodeID: nil,
                predecessorEventID: nil,
                source: .migratedBaseline,
                physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: episodeID),
                continuity: .samePhysicalInstallation,
                pathSnapshot: try LocationPathSnapshotV1(
                    siteID: site.id,
                    siteDisplay: site.label,
                    nodes: []
                ),
                mutationID: try MutationIDV1(rawValue: mutationID),
                occurredAt: asset.createdAt
            )
            context.insert(try AssetPlacementEventRow(event))
            bindings.append(LocationMigratedBaselineBindingV1(
                assetID: asset.id,
                siteID: asset.siteID,
                placementEventID: eventID,
                physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: episodeID)
            ))
        }
        let receipt = try LocationMigrationReceiptV1(
            workspaceID: workspaceID,
            sourceGenerationID: sourceGenerationID,
            candidateGenerationID: targetGenerationID,
            sourceSiteCount: sites.count,
            sourceAssetCount: assets.count,
            bindings: bindings.sorted()
        )
        context.insert(try LocationMigrationReceiptRow(receipt))
        states[0].generationID = targetGenerationID
        let marker = try requireV5Marker(
            in: context,
            expectedMigrationID: migrationID
        )
        marker.schemaVersion = 6
        marker.releaseID = PersistentSchemaReleaseV1.v6.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v5.compatibilityID
        marker.migrationID = migrationID
        try context.save()
        _ = try requireV6Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func requireV6Marker(
        in context: ModelContext,
        expectedMigrationID: UUID?
    ) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>()
        descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 6,
              marker.releaseID == PersistentSchemaReleaseV1.v6.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v5.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        let receipts = try context.fetch(FetchDescriptor<LocationMigrationReceiptRow>())
        guard receipts.count <= 1 else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let placements = try context.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { try $0.value() }
        let liveAssetSiteByID = Dictionary(uniqueKeysWithValues: try context.fetch(
            FetchDescriptor<Asset>()
        ).map { ($0.id, $0.siteID) })
        let deletedAssetIDs = Set(try context.fetch(FetchDescriptor<DeletionLedgerRow>()).compactMap {
            let identity = try DeletionIdentityV2(typedID: $0.typedID)
            return identity.kind == .asset ? identity.id : nil
        })
        let knownAssetIDs = Set(liveAssetSiteByID.keys).union(deletedAssetIDs)
        // Fresh V6 bootstrap/erase generations have no V5 migration receipt.
        guard let receiptRow = receipts.first else {
            try LocationMigrationIntegrityV1.validate(
                receipt: nil,
                placementEvents: placements,
                knownAssetIDs: knownAssetIDs,
                liveAssetSiteByID: liveAssetSiteByID
            )
            return marker
        }
        guard states.count == 1,
              states[0].generationID == receipts[0].candidateGenerationID else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let receipt = try receiptRow.value()
        guard receipt.workspaceID.rawValue == states[0].workspaceID,
              receipt.candidateGenerationID == states[0].generationID else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        do {
            try LocationMigrationIntegrityV1.validate(
                receipt: receipt,
                placementEvents: placements,
                knownAssetIDs: knownAssetIDs,
                liveAssetSiteByID: liveAssetSiteByID
            )
        } catch {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV7Marker(
        in context: ModelContext,
        migrationID: UUID
    ) throws {
        guard try context.fetch(FetchDescriptor<SavedSmartViewRowV1>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let marker = try requireV6Marker(in: context, expectedMigrationID: migrationID)
        marker.schemaVersion = 7
        marker.releaseID = PersistentSchemaReleaseV1.v7.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v6.compatibilityID
        try context.save()
        _ = try requireV7Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func requireV7Marker(
        in context: ModelContext,
        expectedMigrationID: UUID?
    ) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>()
        descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 7,
              marker.releaseID == PersistentSchemaReleaseV1.v7.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v6.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let rows = try context.fetch(FetchDescriptor<SavedSmartViewRowV1>())
        let descriptors = try rows.map { try $0.descriptor() }
        guard Set(rows.map(\.id)).count == rows.count,
              Set(descriptors.map {
                  SavedSmartViewRowV1.key(workspaceID: $0.workspaceID, stableID: $0.stableID)
              }).count == descriptors.count else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV8RequirementAssurance(
        in context: ModelContext,
        workspaceID: UUID,
        migrationID: UUID,
        targetGenerationID: UUID? = nil
    ) throws {
        guard try context.fetch(FetchDescriptor<RequirementAssuranceRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let records = try context.fetch(
            FetchDescriptor<WorkflowRecord>(sortBy: [SortDescriptor(\.id)])
        )
        let policySHA256 = StoreMigrationCanonicalJSONV1.sha256(
            Data("legacy-assurance-unknown-v1".utf8)
        )
        for record in records {
            context.insert(try RequirementAssuranceRow.blockingUnknownBackfill(
                workflowRecordID: record.id,
                workspaceID: workspaceID,
                evaluatedRevision: 1,
                requirementID: "legacy_assurance_unknown",
                requirementVersion: 1,
                requirementTypeID: "legacy_assurance_unknown",
                policySHA256: policySHA256,
                mutationID: record.finalizationMutationID ?? record.id,
                timestamp: record.completedAt ?? record.startedAt
            ))
        }
        let marker = try requireV7Marker(in: context, expectedMigrationID: migrationID)
        marker.schemaVersion = 8
        marker.releaseID = PersistentSchemaReleaseV1.v8.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v7.compatibilityID
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        if let state = states.first {
            guard states.count == 1, state.workspaceID == workspaceID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            if let targetGenerationID {
                state.generationID = targetGenerationID
            }
            let identity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: state.workspaceID),
                replicaID: ReplicaID(rawValue: state.activeReplicaID)
            )
            let journal = try MutationJournalStoreV1(
                modelContext: context,
                identity: identity,
                generationID: state.generationID,
                allowStateBootstrap: false
            )
            try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        } else if !records.isEmpty {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        try context.save()
        _ = try requireV8Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func requireV8Marker(
        in context: ModelContext,
        expectedMigrationID: UUID?
    ) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>()
        descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 8,
              marker.releaseID == PersistentSchemaReleaseV1.v8.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v7.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>())
        let rows = try context.fetch(FetchDescriptor<RequirementAssuranceRow>())
        let snapshots = try rows.map { try $0.snapshot() }
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count <= 1 else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let expectedWorkspaceID = states.first?.workspaceID
        guard rows.count == records.count,
              Set(rows.map(\.workflowRecordID)).count == rows.count,
              Set(rows.map(\.workflowRecordID)) == Set(records.map(\.id)),
              snapshots.allSatisfy({ snapshot in
                  expectedWorkspaceID.map { $0 == snapshot.workspaceID } ?? true
              }),
              snapshots.allSatisfy({
                  $0.workflowRecordID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
              }) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV9Marker(in context: ModelContext, migrationID: UUID) throws {
        guard try context.fetch(FetchDescriptor<ServicePartyRow>()).isEmpty,
              try context.fetch(FetchDescriptor<SitePartyRoleEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<ActorSnapshotRow>()).isEmpty,
              try context.fetch(FetchDescriptor<QualificationSnapshotRow>()).isEmpty,
              try context.fetch(FetchDescriptor<SignoffSnapshotRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let marker = try requireV8Marker(in: context, expectedMigrationID: migrationID)
        marker.schemaVersion = 9; marker.releaseID = PersistentSchemaReleaseV1.v9.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v8.compatibilityID
        try context.save(); _ = try requireV9Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func requireV9Marker(in context: ModelContext, expectedMigrationID: UUID?) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>(); descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 9,
              marker.releaseID == PersistentSchemaReleaseV1.v9.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v8.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let workspaceIDs = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map(\.workspaceID)
        guard workspaceIDs.count <= 1 else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
        let expected = workspaceIDs.first
        let parties = try context.fetch(FetchDescriptor<ServicePartyRow>()).map { try $0.value() }
        let roles = try context.fetch(FetchDescriptor<SitePartyRoleEventRow>()).map { try $0.value() }
        let actors = try context.fetch(FetchDescriptor<ActorSnapshotRow>()).map { try $0.value() }
        let qualifications = try context.fetch(FetchDescriptor<QualificationSnapshotRow>()).map { try $0.value() }
        let signoffs = try context.fetch(FetchDescriptor<SignoffSnapshotRow>()).map { try $0.value() }
        let values = parties.map { $0.workspaceID.rawValue } + roles.map { $0.workspaceID.rawValue } + actors.map { $0.workspaceID.rawValue } + qualifications.map { $0.workspaceID.rawValue } + signoffs.map { $0.workspaceID.rawValue }
        guard expected.map({ id in values.allSatisfy { $0 == id } }) ?? values.isEmpty else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
        return marker
    }

    @MainActor
    private func backfillV10Marker(in context: ModelContext, migrationID: UUID) throws {
        let marker = try requireV9Marker(in: context, expectedMigrationID: migrationID)
        marker.schemaVersion = 10
        marker.releaseID = PersistentSchemaReleaseV1.v10.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v9.compatibilityID
        try context.save()
        _ = try requireV10Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func requireV10Marker(in context: ModelContext, expectedMigrationID: UUID?) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>()
        descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 10,
              marker.releaseID == PersistentSchemaReleaseV1.v10.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v9.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let workspaceIDs = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map(\.workspaceID)
        guard workspaceIDs.count <= 1 else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
        let expectedWorkspaceID = workspaceIDs.first
        let kindBindings = try context.fetch(FetchDescriptor<AssetKindBindingEventRow>()).map { try $0.value() }
        let workflowBindings = try context.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>()).map { try $0.value() }
        let productIdentities = try context.fetch(FetchDescriptor<AssetProductIdentityRow>()).map { try $0.value() }
        let lifecycleEvents = try context.fetch(FetchDescriptor<AssetLifecycleEventRow>()).map { try $0.value() }
        let successorLinks = try context.fetch(FetchDescriptor<AssetSuccessorLinkRow>()).map { try $0.value() }
        let subjectScopes = try context.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>()).map { try $0.value() }
        let assetIDs = Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id))
        let valueWorkspaceIDs = kindBindings.map { $0.workspaceID.rawValue }
            + workflowBindings.map { $0.workspaceID.rawValue }
            + productIdentities.map { $0.workspaceID.rawValue }
            + lifecycleEvents.map { $0.record.workspaceID.rawValue }
            + successorLinks.map { $0.workspaceID.rawValue }
            + subjectScopes.map { $0.workspaceID.rawValue }
        guard expectedWorkspaceID.map({ expected in valueWorkspaceIDs.allSatisfy { $0 == expected } })
                ?? valueWorkspaceIDs.isEmpty,
              kindBindings.allSatisfy({ assetIDs.contains($0.assetID) }),
              workflowBindings.allSatisfy({ assetIDs.contains($0.assetID) }),
              productIdentities.allSatisfy({ assetIDs.contains($0.assetID) }),
              lifecycleEvents.allSatisfy({ assetIDs.contains($0.record.assetID) }),
              successorLinks.allSatisfy({ assetIDs.contains($0.predecessorAssetID) && assetIDs.contains($0.successorAssetID) }),
              subjectScopes.flatMap(\.semanticBindings).allSatisfy({ assetIDs.contains($0.assetID) }) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let kindsByID = Dictionary(uniqueKeysWithValues: kindBindings.map { ($0.eventID, $0) })
        let linksByID = Dictionary(uniqueKeysWithValues: successorLinks.map { ($0.linkID, $0) })
        guard kindsByID.count == kindBindings.count, linksByID.count == successorLinks.count else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        for binding in workflowBindings {
            guard let kind = kindsByID[binding.kindBindingEventID],
                  kind.workspaceID == binding.workspaceID,
                  kind.assetID == binding.assetID,
                  kind.revision == binding.kindBindingRevision else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
        }
        for event in lifecycleEvents {
            if event.kind == .classificationChangedRecorded {
                guard let id = event.record.kindBindingEventID, let kind = kindsByID[id] else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                try event.validateAtomicReference(kindBinding: kind)
            } else if event.kind == .replacedRecorded {
                guard let id = event.record.successorLinkID, let link = linksByID[id] else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                try event.validateAtomicReference(successorLink: link)
            }
        }
        try AssetSuccessorLinkV1.validateAcyclic(successorLinks)
        return marker
    }

    @MainActor
    private func backfillV11Marker(in context: ModelContext, migrationID: UUID) throws {
        let marker = try requireV10Marker(in: context, expectedMigrationID: migrationID)
        guard try context.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()).isEmpty,
              try context.fetch(FetchDescriptor<RequirementBasisBindingRow>()).isEmpty,
              try context.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).isEmpty,
              try context.fetch(FetchDescriptor<SeverityScaleReleaseRow>()).isEmpty,
              try context.fetch(FetchDescriptor<FindingClassificationBindingRow>()).isEmpty,
              try context.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).isEmpty,
              try context.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).isEmpty,
              try context.fetch(FetchDescriptor<DerivedFactProvenanceRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        marker.schemaVersion = 11
        marker.releaseID = PersistentSchemaReleaseV1.v11.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v10.compatibilityID
        try context.save()
        _ = try requireV11Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func backfillV12Marker(in context: ModelContext, migrationID: UUID) throws {
        let marker = try requireV11Marker(in: context, expectedMigrationID: migrationID)
        guard try context.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        marker.schemaVersion = 12
        marker.releaseID = PersistentSchemaReleaseV1.v12.compatibilityID
        marker.predecessorReleaseID = PersistentSchemaReleaseV1.v11.compatibilityID
        try context.save()
        _ = try requireV12Marker(in: context, expectedMigrationID: migrationID)
    }

    @MainActor
    private func backfillV13Marker(in context:ModelContext,migrationID:UUID)throws{let marker=try requireV12Marker(in:context,expectedMigrationID:migrationID);guard try context.fetch(FetchDescriptor<EvidenceVisibilityRow>()).isEmpty,try context.fetch(FetchDescriptor<ClaimEvidenceLinkRow>()).isEmpty,try context.fetch(FetchDescriptor<AssuranceManifestRow>()).isEmpty,try context.fetch(FetchDescriptor<AttestationRow>()).isEmpty else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=13;marker.releaseID=PersistentSchemaReleaseV1.v13.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v12.compatibilityID;try context.save();_ = try requireV13Marker(in:context,expectedMigrationID:migrationID)}
    @MainActor private func requireV13Marker(in context:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let m=try context.fetch(d);guard m.count==1,let marker=m.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==13,marker.releaseID==PersistentSchemaReleaseV1.v13.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v12.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try context.fetch(FetchDescriptor<EvidenceVisibilityRow>()).forEach{_ = try $0.value()};try context.fetch(FetchDescriptor<ClaimEvidenceLinkRow>()).forEach{_ = try $0.value()};try context.fetch(FetchDescriptor<AssuranceManifestRow>()).forEach{_ = try $0.value()};try context.fetch(FetchDescriptor<AttestationRow>()).forEach{_ = try $0.value()};return marker}
    @MainActor private func reviewRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).isEmpty&&c.fetch(FetchDescriptor<ReviewDispositionRow>()).isEmpty&&c.fetch(FetchDescriptor<ChangeRequestRow>()).isEmpty&&c.fetch(FetchDescriptor<CorrectiveActionPolicyRow>()).isEmpty&&c.fetch(FetchDescriptor<CorrectiveActionEventRow>()).isEmpty}
    @MainActor private func backfillV14Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV13Marker(in:c,expectedMigrationID:migrationID);guard try reviewRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=14;marker.releaseID=PersistentSchemaReleaseV1.v14.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v13.compatibilityID;try c.save();_ = try requireV14Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV14Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let m=try c.fetch(d);guard m.count==1,let marker=m.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==14,marker.releaseID==PersistentSchemaReleaseV1.v14.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v13.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try c.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<ReviewDispositionRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<ChangeRequestRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<CorrectiveActionPolicyRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<CorrectiveActionEventRow>()).forEach{_ = try $0.value()};return marker}
    @MainActor private func workPacketRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<WorkPacketManifestRow>()).isEmpty&&c.fetch(FetchDescriptor<WorkItemClaimRow>()).isEmpty&&c.fetch(FetchDescriptor<WorkLeaseRow>()).isEmpty&&c.fetch(FetchDescriptor<WorkReleaseRow>()).isEmpty&&c.fetch(FetchDescriptor<WorkHandoffRow>()).isEmpty}
    @MainActor private func backfillV15Marker(in c:ModelContext,migrationID:UUID)throws{let m=try requireV14Marker(in:c,expectedMigrationID:migrationID);guard try workPacketRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};m.schemaVersion=15;m.releaseID=PersistentSchemaReleaseV1.v15.compatibilityID;m.predecessorReleaseID=PersistentSchemaReleaseV1.v14.compatibilityID;try c.save();_ = try requireV15Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV15Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let ms=try c.fetch(d);guard ms.count==1,let m=ms.first,m.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,m.schemaVersion==15,m.releaseID==PersistentSchemaReleaseV1.v15.compatibilityID,m.predecessorReleaseID==PersistentSchemaReleaseV1.v14.compatibilityID,expectedMigrationID.map({m.migrationID==$0}) ?? m.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try c.fetch(FetchDescriptor<WorkPacketManifestRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<WorkItemClaimRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<WorkLeaseRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<WorkReleaseRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<WorkHandoffRow>()).forEach{_ = try $0.value()};return m}
    @MainActor private func fieldDraftRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).isEmpty&&c.fetch(FetchDescriptor<AttachmentStagingItemRow>()).isEmpty&&c.fetch(FetchDescriptor<DraftCommitSagaRow>()).isEmpty&&c.fetch(FetchDescriptor<DraftContentReservationRow>()).isEmpty&&c.fetch(FetchDescriptor<DraftCommitReceiptRow>()).isEmpty&&c.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).isEmpty}
    @MainActor private func backfillV16Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV15Marker(in:c,expectedMigrationID:migrationID);guard try fieldDraftRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=16;marker.releaseID=PersistentSchemaReleaseV1.v16.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v15.compatibilityID;try c.save();_ = try requireV16Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV16Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var descriptor=FetchDescriptor<PersistentSchemaReleaseMarker>();descriptor.fetchLimit=2;let rows=try c.fetch(descriptor);guard rows.count==1,let marker=rows.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==16,marker.releaseID==PersistentSchemaReleaseV1.v16.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v15.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try c.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<AttachmentStagingItemRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<DraftCommitSagaRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<DraftContentReservationRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<DraftCommitReceiptRow>()).forEach{_ = try $0.value()};try c.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).forEach{_ = try $0.value()};return marker}
    @MainActor private func packageEvolutionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).isEmpty&&c.fetch(FetchDescriptor<PackageSandboxRunRow>()).isEmpty&&c.fetch(FetchDescriptor<PackagePromotionReceiptRow>()).isEmpty&&c.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).isEmpty}
    @MainActor private func backfillV17Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV16Marker(in:c,expectedMigrationID:migrationID);guard try packageEvolutionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=17;marker.releaseID=PersistentSchemaReleaseV1.v17.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v16.compatibilityID;try c.save();_ = try requireV17Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV17Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var descriptor=FetchDescriptor<PersistentSchemaReleaseMarker>();descriptor.fetchLimit=2;let rows=try c.fetch(descriptor);guard rows.count==1,let marker=rows.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==17,marker.releaseID==PersistentSchemaReleaseV1.v17.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v16.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let releases=try c.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try $0.value()},runs=try c.fetch(FetchDescriptor<PackageSandboxRunRow>()).map{try $0.value()},receipts=try c.fetch(FetchDescriptor<PackagePromotionReceiptRow>()).map{try $0.value()},pointers=try c.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).map{try $0.value()};_ = try PackageEvolutionLifecycleClosureV1(promotedReleases:releases,sandboxRuns:runs,promotionReceipts:receipts,activePointers:pointers);return marker}
    @MainActor private func measurementIntegrityRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<InstrumentReferenceRow>()).isEmpty&&c.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).isEmpty&&c.fetch(FetchDescriptor<MeasurementCaptureRow>()).isEmpty&&c.fetch(FetchDescriptor<MeasurementSeriesRow>()).isEmpty&&c.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).isEmpty}
    @MainActor private func backfillV18Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV17Marker(in:c,expectedMigrationID:migrationID);guard try measurementIntegrityRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=18;marker.releaseID=PersistentSchemaReleaseV1.v18.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v17.compatibilityID;try c.save();_ = try requireV18Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV18Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{
        var descriptor=FetchDescriptor<PersistentSchemaReleaseMarker>();descriptor.fetchLimit=2
        let rows=try c.fetch(descriptor)
        guard rows.count==1,let marker=rows.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==18,marker.releaseID==PersistentSchemaReleaseV1.v18.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v17.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let instruments=try c.fetch(FetchDescriptor<InstrumentReferenceRow>()).map{try $0.value()}
        let calibrations=try c.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).map{try $0.value()}
        let captures=try c.fetch(FetchDescriptor<MeasurementCaptureRow>()).map{try $0.value()}
        let series=try c.fetch(FetchDescriptor<MeasurementSeriesRow>()).map{try $0.value()}
        let assessments=try c.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).map{try $0.value()}
        try validateMeasurementIntegrityClosure(in:c,instruments:instruments,calibrations:calibrations,captures:captures,series:series,assessments:assessments)
        return marker
    }
    @MainActor private func privacyTransformRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<PrivacyTransformPolicyRow>()).isEmpty&&c.fetch(FetchDescriptor<PrivacyRegionRow>()).isEmpty&&c.fetch(FetchDescriptor<PrivacyTransformManifestRow>()).isEmpty&&c.fetch(FetchDescriptor<PrivacyReviewReceiptRow>()).isEmpty}
    @MainActor private func backfillV19Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV18Marker(in:c,expectedMigrationID:migrationID);guard try privacyTransformRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=19;marker.releaseID=PersistentSchemaReleaseV1.v19.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v18.compatibilityID;try c.save();_ = try requireV19Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV19Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{
        var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2
        let markers=try c.fetch(d)
        guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion==19,marker.releaseID==PersistentSchemaReleaseV1.v19.compatibilityID,
              marker.predecessorReleaseID==PersistentSchemaReleaseV1.v18.compatibilityID,
              expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let values=try privacyTransformValuesV19(in:c)
        let policies=values.policies,regions=values.regions,manifests=values.manifests,reviews=values.reviews
        for manifest in manifests{
            guard let policy=policies.first(where:{$0.policyID==manifest.policyID&&$0.revision==manifest.policyRevision&&$0.policySHA256==manifest.policySHA256})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            let exactRegions=manifest.orderedRegions.compactMap{embedded in regions.first(where:{$0==embedded})}
            try PrivacyTransformLifecycleClosureV1(policy:policy,regions:exactRegions,manifest:manifest,review:nil).validate()
        }
        for review in reviews{
            guard let manifest=manifests.first(where:{$0.manifestID==review.manifestID&&$0.revision==review.manifestRevision&&$0.manifestSHA256==review.manifestSHA256}),
                  let policy=policies.first(where:{$0.policyID==review.policyID&&$0.revision==review.policyRevision&&$0.policySHA256==review.policySHA256})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            try review.validate(manifest:manifest,policy:policy)
            if let predecessorID=review.supersedesReceiptID{
                guard let predecessor=reviews.first(where:{$0.receiptID==predecessorID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
                try review.validateSuccessor(of:predecessor,manifest:manifest,policy:policy)
            }else if review.revision != 1{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            guard reviews.filter({$0.supersedesReceiptID==review.receiptID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        for policy in policies{
            if let predecessorID=policy.supersedesPolicyID{
                guard let predecessor=policies.first(where:{$0.policyID==predecessorID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
                try policy.validateSuccessor(of:predecessor)
            }else if policy.revision != 1{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            guard policies.filter({$0.supersedesPolicyID==policy.policyID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        for manifest in manifests{
            guard let policy=policies.first(where:{$0.policyID==manifest.policyID&&$0.revision==manifest.policyRevision&&$0.policySHA256==manifest.policySHA256})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            if let predecessorID=manifest.supersedesManifestID{
                guard let predecessor=manifests.first(where:{$0.manifestID==predecessorID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
                try manifest.validateSuccessor(of:predecessor,policy:policy)
            }else if manifest.revision != 1{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            guard manifests.filter({$0.supersedesManifestID==manifest.manifestID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        guard regions.allSatisfy({region in manifests.contains(where:{$0.orderedRegions.contains(region)})})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        return marker
    }
    @MainActor private func privacyTransformValuesV19(in c:ModelContext)throws->(policies:[PrivacyTransformPolicyV1],regions:[PrivacyRegionV1],manifests:[PrivacyTransformManifestV1],reviews:[PrivacyReviewReceiptV1]){
        let policies=try c.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(sortBy:[SortDescriptor(\.policyID)])).map{try $0.value()}
        let regions=try c.fetch(FetchDescriptor<PrivacyRegionRow>(sortBy:[SortDescriptor(\.regionID)])).map{try $0.value()}
        let manifestRows=try c.fetch(FetchDescriptor<PrivacyTransformManifestRow>(sortBy:[SortDescriptor(\.manifestID)]))
        let manifests=try manifestRows.map{row in
            guard let policy=policies.first(where:{$0.policyID==row.policyID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            return try row.value(policy:policy)
        }
        let reviewRows=try c.fetch(FetchDescriptor<PrivacyReviewReceiptRow>(sortBy:[SortDescriptor(\.receiptID)]))
        let reviews=try reviewRows.map{row in
            guard let manifest=manifests.first(where:{$0.manifestID==row.manifestID}),
                  let policy=policies.first(where:{$0.policyID==row.policyID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            return try row.value(manifest:manifest,policy:policy)
        }
        return(policies,regions,manifests,reviews)
    }
    @MainActor private func clientCapabilityRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ClientCapabilityProfileRow>()).isEmpty&&c.fetch(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>()).isEmpty&&c.fetch(FetchDescriptor<PackageLifecyclePolicyRow>()).isEmpty&&c.fetch(FetchDescriptor<PackageLifecycleDispositionRow>()).isEmpty}
    @MainActor private func backfillV20Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV19Marker(in:c,expectedMigrationID:migrationID);guard try clientCapabilityRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=20;marker.releaseID=PersistentSchemaReleaseV1.v20.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v19.compatibilityID;try c.save();_ = try requireV20Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV20Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let rows=try c.fetch(d);guard rows.count==1,let marker=rows.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==20,marker.releaseID==PersistentSchemaReleaseV1.v20.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v19.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try clientCapabilityValuesV20(in:c);return marker}
    @MainActor private func clientCapabilityValuesV20(in c:ModelContext)throws->(profiles:[ClientCapabilityProfileV1],decisions:[ClientCapabilityAdmissionDecisionV1],policies:[PackageLifecyclePolicyV1],dispositions:[PackageLifecycleDispositionV1]){
        let releases=try c.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try $0.value().packageRelease}
        guard Set(releases.map(\.packageReleaseID)).count==releases.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let profiles=try c.fetch(FetchDescriptor<ClientCapabilityProfileRow>(sortBy:[SortDescriptor(\.profileID)])).map{try $0.value()}
        let policyRows=try c.fetch(FetchDescriptor<PackageLifecyclePolicyRow>(sortBy:[SortDescriptor(\.policyID)]))
        let policies=try policyRows.map{row in guard let release=releases.first(where:{$0.packageReleaseID==row.packageReleaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return try row.value(release:release)}
        let dispositionRows=try c.fetch(FetchDescriptor<PackageLifecycleDispositionRow>(sortBy:[SortDescriptor(\.dispositionID)]))
        let dispositions=try dispositionRows.map{row in guard let release=releases.first(where:{$0.packageReleaseID==row.packageReleaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return try row.value(release:release)}
        let decisionRows=try c.fetch(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>(sortBy:[SortDescriptor(\.decisionID)]))
        let decisions=try decisionRows.map{row in guard let profile=profiles.first(where:{$0.profileID==row.profileID}),let policy=policies.first(where:{$0.policyID==row.policyID}),let disposition=dispositions.first(where:{$0.dispositionID==row.dispositionID}),let release=releases.first(where:{$0.packageReleaseID==row.packageReleaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return try row.value(profile:profile,policy:policy,disposition:disposition,release:release)}
        let workspaces=try c.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map(\.workspaceID)
        let valueWorkspaces=profiles.map{$0.workspaceID.rawValue}+policies.map{$0.workspaceID.rawValue}+dispositions.map{$0.workspaceID.rawValue}+decisions.map{$0.workspaceID.rawValue}
        guard workspaces.count<=1,
              workspaces.first.map({workspaceID in valueWorkspaces.allSatisfy{$0==workspaceID}}) ?? valueWorkspaces.isEmpty,
              Set(profiles.map(\.profileID)).count==profiles.count,
              Set(policies.map(\.policyID)).count==policies.count,
              Set(dispositions.map(\.dispositionID)).count==dispositions.count,
              Set(decisions.map(\.decisionID)).count==decisions.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        for p in profiles{if let id=p.supersedesProfileID{guard let old=profiles.first(where:{$0.profileID==id})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try p.validateSuccessor(of:old)};guard profiles.filter({$0.supersedesProfileID==p.profileID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        for p in policies{guard let release=releases.first(where:{$0.packageReleaseID==p.packageReleaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};if let id=p.supersedesPolicyID{guard let old=policies.first(where:{$0.policyID==id})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try p.validateSuccessor(of:old,release:release)};guard policies.filter({$0.supersedesPolicyID==p.policyID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        for value in dispositions{guard let release=releases.first(where:{$0.packageReleaseID==value.packageReleaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};if let id=value.supersedesDispositionID{guard let old=dispositions.first(where:{$0.dispositionID==id})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:old,release:release)};guard dispositions.filter({$0.supersedesDispositionID==value.dispositionID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        return(profiles,decisions,policies,dispositions)
    }
    @MainActor private func recoverabilityVerificationRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>()).isEmpty}
    @MainActor private func backfillV21Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV20Marker(in:c,expectedMigrationID:migrationID);guard try recoverabilityVerificationRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=21;marker.releaseID=PersistentSchemaReleaseV1.v21.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v20.compatibilityID;try c.save();_ = try requireV21Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV21Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let rows=try c.fetch(d);guard rows.count==1,let marker=rows.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==21,marker.releaseID==PersistentSchemaReleaseV1.v21.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v20.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let receipts=try c.fetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>()).map{try $0.value()};let workspaces=try c.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map(\.workspaceID);guard workspaces.count<=1,workspaces.first.map({id in receipts.allSatisfy{$0.workspaceID.rawValue==id}}) ?? receipts.isEmpty,Set(receipts.map(\.receiptID)).count==receipts.count,Set(receipts.map(\.verificationID)).count==receipts.count,Set(receipts.map{$0.mutationID.rawValue}).count==receipts.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for receipt in receipts{if let predecessorID=receipt.supersedesReceiptID{guard let predecessor=receipts.first(where:{$0.receiptID==predecessorID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try receipt.validateSuccessor(of:predecessor)};guard receipts.filter({$0.supersedesReceiptID==receipt.receiptID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};return marker}
    @MainActor private func fieldReferenceRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<FieldReferenceReleaseRow>()).isEmpty&&c.fetch(FetchDescriptor<FieldReferenceBindingRow>()).isEmpty}
    @MainActor private func accessibleDocumentRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>()).isEmpty}
    @MainActor private func backfillV23Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV22Marker(in:c,expectedMigrationID:migrationID);guard try accessibleDocumentRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=23;marker.releaseID=PersistentSchemaReleaseV1.v23.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v22.compatibilityID;try c.save();_ = try requireV23Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV23Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let markers=try c.fetch(d);guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==23,marker.releaseID==PersistentSchemaReleaseV1.v23.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v22.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let values=try c.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>()).map{try $0.value()};guard Set(values.map(\.receiptID)).count==values.count,Set(values.map{$0.mutationID.rawValue}).count==values.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for value in values{if let id=value.supersedesReceiptID{guard let prior=values.first(where:{$0.receiptID==id}),value.workspaceID==prior.workspaceID,value.treeSHA256==prior.treeSHA256,value.snapshotSHA256==prior.snapshotSHA256,value.audience==prior.audience,value.projectionVersion==prior.projectionVersion,value.manifestID==prior.manifestID,value.manifestVersion==prior.manifestVersion,value.manifestSHA256==prior.manifestSHA256,value.outputSHA256==prior.outputSHA256,value.outputByteCount==prior.outputByteCount,value.outputMediaType==prior.outputMediaType,value.localeIdentifier==prior.localeIdentifier,value.profileID==prior.profileID,value.profileRelease==prior.profileRelease,value.profileSHA256==prior.profileSHA256,value.brandProfileID==prior.brandProfileID,value.brandProfileRelease==prior.brandProfileRelease,value.brandProfileSHA256==prior.brandProfileSHA256,value.rendererID==prior.rendererID,value.rendererVersion==prior.rendererVersion,value.assessmentToolID==prior.assessmentToolID,value.assessmentToolVersion==prior.assessmentToolVersion,(prior.scope == .historicSource && value.scope == .currentOutput)||value.scope==prior.scope,prior.revision<UInt64.max,value.revision==prior.revision+1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};guard values.filter({$0.supersedesReceiptID==value.receiptID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};return marker}
    @MainActor private func surveyDefinitionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>()).isEmpty&&c.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>()).isEmpty}
    @MainActor private func backfillV24Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV23Marker(in:c,expectedMigrationID:migrationID);guard try surveyDefinitionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=24;marker.releaseID=PersistentSchemaReleaseV1.v24.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v23.compatibilityID;try c.save();_ = try requireV24Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV24Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{
        var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2
        let markers=try c.fetch(d)
        guard markers.count==1,let marker=markers.first,
              marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion==24,
              marker.releaseID==PersistentSchemaReleaseV1.v24.compatibilityID,
              marker.predecessorReleaseID==PersistentSchemaReleaseV1.v23.compatibilityID,
              expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let identities=try c.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>()).map{try $0.value()}
        let releases=try c.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>()).map{try $0.value()}
        var events:[SurveyDefinitionLifecycleEventV1]=[]
        for row in try c.fetch(FetchDescriptor<MutationReceiptRow>()) {
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
            let envelopeSHA256=try envelope.canonicalSHA256()
            guard envelope.workspaceID.rawValue==row.workspaceID,
                  envelope.mutationID.rawValue==row.mutationID,
                  envelope.commandKind.rawValue==row.commandKind,
                  envelopeSHA256==row.envelopeSHA256 else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            if case let .applySurveyDefinition(mutation)=envelope.command {
                try mutation.validate()
                guard envelope.workspaceID==mutation.workspaceID,
                      envelope.mutationID==mutation.mutationID else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                events.append(mutation.event)
            }
        }
        try Self.validateV24SurveyDefinitionGraph(identities:identities,releases:releases,events:events)
        return marker
    }
    @MainActor private func surveySessionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetchCount(FetchDescriptor<SurveySessionRow>())==0&&c.fetchCount(FetchDescriptor<FactCaptureRow>())==0&&c.fetchCount(FetchDescriptor<ProvisionalSubjectRow>())==0&&c.fetchCount(FetchDescriptor<SubjectPromotionReceiptRow>())==0&&c.fetchCount(FetchDescriptor<SurveyPublicationSnapshotRow>())==0}
    @MainActor private func backfillV25Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV24Marker(in:c,expectedMigrationID:migrationID);guard try surveySessionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=25;marker.releaseID=PersistentSchemaReleaseV1.v25.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v24.compatibilityID;try c.save();_ = try requireV25Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV25Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{
        var descriptor=FetchDescriptor<PersistentSchemaReleaseMarker>();descriptor.fetchLimit=2
        let rows=try c.fetch(descriptor)
        guard rows.count==1,let marker=rows.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==25,marker.releaseID==PersistentSchemaReleaseV1.v25.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v24.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        var mutations:[SurveySessionMutationV1]=[],mutationWorkspaceRevisions:[UUID:UInt64]=[:]
        for row in try c.fetch(FetchDescriptor<MutationReceiptRow>()){
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
            guard envelope.workspaceID.rawValue==row.workspaceID,envelope.mutationID.rawValue==row.mutationID,envelope.commandKind.rawValue==row.commandKind,(try envelope.canonicalSHA256())==row.envelopeSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            if case let .applySurveySession(mutation)=envelope.command{let receipt=try MutationReceiptV1.decodeCanonical(from:row.receiptData);guard receipt.mutationID==mutation.mutationID,receipt.envelopeSHA256==row.envelopeSHA256,row.receiptSHA256==(try receipt.canonicalSHA256()),mutationWorkspaceRevisions.updateValue(receipt.resultingRevision.workspaceRevision,forKey:mutation.mutationID.rawValue)==nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try mutation.validate();mutations.append(mutation)}
        }
        let sessions=try c.fetch(FetchDescriptor<SurveySessionRow>()).map{try $0.value()},facts=try c.fetch(FetchDescriptor<FactCaptureRow>()).map{try $0.value()},subjects=try c.fetch(FetchDescriptor<ProvisionalSubjectRow>()).map{try $0.value()},promotions=try c.fetch(FetchDescriptor<SubjectPromotionReceiptRow>()).map{try $0.value()},publications=try c.fetch(FetchDescriptor<SurveyPublicationSnapshotRow>()).map{try $0.value()}
        guard Set(sessions.map(\.sessionID)).count==sessions.count,Set(facts.map(\.captureID)).count==facts.count,Set(subjects.map(\.provisionalSubjectID)).count==subjects.count,Set(promotions.map(\.receiptID)).count==promotions.count,Set(publications.map(\.snapshotID)).count==publications.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        guard Set(mutationWorkspaceRevisions.values).count==mutationWorkspaceRevisions.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        try validateV25SurveySessionGraph(in:c,mutations:mutations,mutationWorkspaceRevisions:mutationWorkspaceRevisions,sessions:sessions,facts:facts,subjects:subjects,promotions:promotions,publications:publications)
        return marker
    }

    @MainActor private func assetLocatorRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetchCount(FetchDescriptor<AssetLocatorRow>())==0&&c.fetchCount(FetchDescriptor<LocatorBindingReceiptRow>())==0}
    @MainActor private func backfillV26Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV25Marker(in:c,expectedMigrationID:migrationID);guard try assetLocatorRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=26;marker.releaseID=PersistentSchemaReleaseV1.v26.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v25.compatibilityID;try c.save();_ = try requireV26Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV26Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{
        var descriptor=FetchDescriptor<PersistentSchemaReleaseMarker>();descriptor.fetchLimit=2
        let markers=try c.fetch(descriptor)
        guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==26,marker.releaseID==PersistentSchemaReleaseV1.v26.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v25.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let currentLocators=try c.fetch(FetchDescriptor<AssetLocatorRow>()).map{try $0.value()},currentReceipts=try c.fetch(FetchDescriptor<LocatorBindingReceiptRow>()).map{try $0.value()}
        guard Set(currentLocators.map(\.locatorID)).count==currentLocators.count,Set(currentReceipts.map(\.receiptID)).count==currentReceipts.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        var historicalLocators:[AssetLocatorV1]=[],historicalReceipts:[LocatorBindingReceiptV1]=[]
        for row in try c.fetch(FetchDescriptor<MutationReceiptRow>()){
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
            guard envelope.workspaceID.rawValue==row.workspaceID,envelope.mutationID.rawValue==row.mutationID,envelope.commandKind.rawValue==row.commandKind,(try envelope.canonicalSHA256())==row.envelopeSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            guard case let .applyAssetLocator(mutation)=envelope.command else{continue}
            let generic=try MutationReceiptV1.decodeCanonical(from:row.receiptData)
            guard generic.envelopeSHA256==row.envelopeSHA256,row.receiptSHA256==(try generic.canonicalSHA256()) else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            _ = try AssetLocatorMutationReceiptV1(mutation:mutation,mutationReceipt:generic)
            switch mutation.payload{case let .bind(value,receipt,_):historicalLocators.append(value);historicalReceipts.append(receipt);case let .transition(value,receipt,prior,_):historicalLocators += [prior,value];historicalReceipts.append(receipt);case let .replace(value,replacement,receipt,prior,_):historicalLocators += [prior,value,replacement];historicalReceipts.append(receipt)}
        }
        var locatorHistory:[String:AssetLocatorV1]=[:]
        for value in historicalLocators{let key="\(value.locatorID.uuidString):\(value.revision)";if let prior=locatorHistory[key],prior != value{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};locatorHistory[key]=value}
        var receiptHistory:[UUID:LocatorBindingReceiptV1]=[:]
        for value in historicalReceipts{if let prior=receiptHistory[value.receiptID],prior != value{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};receiptHistory[value.receiptID]=value}
        let heads=Dictionary(grouping:locatorHistory.values,by:\.locatorID).compactMap{$0.value.sorted{$0.revision<$1.revision}.last}
        guard currentLocators.allSatisfy({heads.contains($0)}),heads.count==currentLocators.count,currentReceipts.allSatisfy({receiptHistory[$0.receiptID]==$0}),receiptHistory.count==currentReceipts.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        do{_ = try AssetLocatorLifecycleClosureV1(locators:Array(locatorHistory.values),receipts:currentReceipts)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        return marker
    }
    @MainActor private func scheduleRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetchCount(FetchDescriptor<ScheduleDefinitionReleaseRow>())==0&&c.fetchCount(FetchDescriptor<OccurrenceHistoryEventRow>())==0}
    @MainActor private func backfillV27Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV26Marker(in:c,expectedMigrationID:migrationID);guard try scheduleRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=27;marker.releaseID=PersistentSchemaReleaseV1.v27.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v26.compatibilityID;try c.save();_ = try requireV27Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV27Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{
        let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
        guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==27,marker.releaseID==PersistentSchemaReleaseV1.v27.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v26.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let releases=try c.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>()).map{try $0.value()},events=try c.fetch(FetchDescriptor<OccurrenceHistoryEventRow>()).map{try $0.value()}
        guard Set(releases.map(\.releaseID)).count==releases.count,Set(events.map(\.eventID)).count==events.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let definitions=try c.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>()).map{try $0.value()},packages=try c.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try $0.value().packageRelease}
        for release in releases{let reference=release.workDefinition.definitionRelease,definitionMatches=definitions.filter{$0.releaseID==reference.releaseID},packageMatches=packages.filter{$0.packageReleaseID==release.workDefinition.packageReleaseID};guard definitionMatches.count==1,let definition=definitionMatches.first,definition.workspaceID==release.workDefinition.definitionWorkspaceID,try SurveyDefinitionReleaseReferenceV1(definition)==reference,packageMatches.count==1,let package=packageMatches.first,package.state == .published,package.packageID==release.workDefinition.packageID,package.packageContentVersion==release.workDefinition.packageContentVersion,package.packageSHA256==release.workDefinition.packageSHA256,package.workflowSHA256==release.workDefinition.workflowSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        let packets=try c.fetch(FetchDescriptor<WorkPacketManifestRow>()).map{try $0.value()},sessions=try c.fetch(FetchDescriptor<SurveySessionRow>()).map{try $0.value()}
        for event in events{let matches=releases.filter{$0.releaseID==event.scheduleRelease.releaseID};guard matches.count==1,let release=matches.first,try ScheduleDefinitionReleaseReferenceV1(release)==event.scheduleRelease else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};if let work=event.workInstance{switch work{case let .workPacket(reference):let matches=packets.filter{$0.manifestID==reference.manifestID};guard matches.count==1,let packet=matches.first,try WorkPacketManifestReferenceV1(packet)==reference else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};case let .roundSession(id,revision,digest):let matches=sessions.filter{$0.sessionID==id};guard matches.count==1,let session=matches.first,session.revision==revision,session.sessionSHA256==digest else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}}}
        for group in Dictionary(grouping:releases,by:\.scheduleDefinitionID).values{let ordered=group.sorted{$0.revision<$1.revision};guard let first=ordered.first,first.revision==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for index in 1..<ordered.count{try ordered[index].validateSuccessor(of:ordered[index-1])}}
        for group in Dictionary(grouping:events,by:\.occurrenceID).values{let ordered=group.sorted{$0.revision<$1.revision};guard let first=ordered.first else{continue};try first.validate(predecessor:nil);for index in 1..<ordered.count{try ordered[index].validate(predecessor:ordered[index-1])}}
        var journalReleases:[UUID:ScheduleDefinitionReleaseV1]=[:],journalEvents:[UUID:OccurrenceHistoryEventV1]=[:]
        for row in try c.fetch(FetchDescriptor<MutationReceiptRow>()){
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard envelope.workspaceID.rawValue==row.workspaceID,envelope.mutationID.rawValue==row.mutationID,envelope.commandKind.rawValue==row.commandKind,(try envelope.canonicalSHA256())==row.envelopeSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};guard case let .applySchedule(mutation)=envelope.command else{continue}
            let receipt=try MutationReceiptV1.decodeCanonical(from:row.receiptData);guard receipt.envelopeSHA256==row.envelopeSHA256,row.receiptSHA256==(try receipt.canonicalSHA256()) else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try ScheduleMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)
            switch mutation.payload{case let .appendRelease(value,_):guard journalReleases.updateValue(value,forKey:value.releaseID)==nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};case let .appendOccurrenceEvent(value,_,_),let .startOccurrence(value,_,_):guard journalEvents.updateValue(value,forKey:value.eventID)==nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};case let .generateOccurrences(_,_,values):for value in values{guard journalEvents.updateValue(value,forKey:value.eventID)==nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}}
        }
        guard releases.allSatisfy({journalReleases[$0.releaseID]==$0}),events.allSatisfy({journalEvents[$0.eventID]==$0}),journalReleases.count==releases.count,journalEvents.count==events.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        return marker
    }
    @MainActor private func planRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetchCount(FetchDescriptor<PlanDocumentRow>())==0&&c.fetchCount(FetchDescriptor<PlanRevisionRow>())==0&&c.fetchCount(FetchDescriptor<PlanPlacementRow>())==0&&c.fetchCount(FetchDescriptor<RebaseReceiptRow>())==0}
    @MainActor private func backfillV28Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV27Marker(in:c,expectedMigrationID:migrationID);guard try planRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=28;marker.releaseID=PersistentSchemaReleaseV1.v28.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v27.compatibilityID;try c.save();_ = try requireV28Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV28Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==28,marker.releaseID==PersistentSchemaReleaseV1.v28.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v27.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let documents=try c.fetch(FetchDescriptor<PlanDocumentRow>()).map{try $0.value()},revisions=try c.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()},placements=try c.fetch(FetchDescriptor<PlanPlacementRow>()).map{try $0.value()},receipts=try c.fetch(FetchDescriptor<RebaseReceiptRow>()).map{try $0.value()};try PlanLifecycleClosureV1(documentHistory:documents,revisionHistory:revisions,placementHistory:placements,receipts:receipts).validate();guard Set(documents.map(\.mutationID)).count==documents.count,Set(revisions.map(\.planRevisionID)).count==revisions.count,Set(placements.map{($0.placementID.uuidString)+":"+String($0.revision)}).count==placements.count,Set(receipts.map(\.receiptID)).count==receipts.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func placementPoseRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<AssetPoseEventRow>()).isEmpty&&c.fetch(FetchDescriptor<SpatialAnchorObservationRow>()).isEmpty}
    @MainActor private func backfillV29Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV28Marker(in:c,expectedMigrationID:migrationID);guard try placementPoseRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=29;marker.releaseID=PersistentSchemaReleaseV1.v29.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v28.compatibilityID;try c.save();_ = try requireV29Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV29Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==29,marker.releaseID==PersistentSchemaReleaseV1.v29.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v28.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let events=try c.fetch(FetchDescriptor<AssetPoseEventRow>()).map{try $0.value()},observations=try c.fetch(FetchDescriptor<SpatialAnchorObservationRow>()).map{try $0.value()};let groups=Dictionary(grouping:events,by:{"\($0.workspaceID.rawValue.uuidString.lowercased()):\($0.assetID.uuidString.lowercased())"});for group in groups.values{guard let first=group.first else{continue};_ = try AssetPoseHistoryV1.currentTip(workspaceID:first.workspaceID,assetID:first.assetID,events:group)};try validateV29PoseReferences(in:c,events:events,observations:observations);guard Set(events.map(\.eventID)).count==events.count,Set(observations.map(\.observationID)).count==observations.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func evidenceContextRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<EvidenceContextRow>()).isEmpty&&c.fetch(FetchDescriptor<PairedObservationLinkRow>()).isEmpty}
    @MainActor private func backfillV30Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV29Marker(in:c,expectedMigrationID:migrationID);guard try evidenceContextRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=30;marker.releaseID=PersistentSchemaReleaseV1.v30.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v29.compatibilityID;try c.save();_ = try requireV30Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV30Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==30,marker.releaseID==PersistentSchemaReleaseV1.v30.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v29.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let contexts=try c.fetch(FetchDescriptor<EvidenceContextRow>()).map{try $0.value()},pairs=try c.fetch(FetchDescriptor<PairedObservationLinkRow>()).map{try $0.value()};guard Set(contexts.map(\.contextID)).count==contexts.count,Set(pairs.map(\.linkID)).count==pairs.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for value in contexts{if let digest=value.predecessorContextSHA256{let predecessors=contexts.filter{$0.contextSHA256==digest};guard predecessors.count==1,let predecessor=predecessors.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)};guard contexts.filter({$0.predecessorContextSHA256==value.contextSHA256}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};for value in pairs{if let digest=value.predecessorLinkSHA256{let predecessors=pairs.filter{$0.linkSHA256==digest};guard predecessors.count==1,let predecessor=predecessors.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)};guard pairs.filter({$0.predecessorLinkSHA256==value.linkSHA256}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};try validateEvidencePairPurposeHistory(pairs);return marker}
    @MainActor private func lightingRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<LightingSystemRow>()).isEmpty&&c.fetch(FetchDescriptor<LightingObservationRow>()).isEmpty&&c.fetch(FetchDescriptor<LightingIssueRow>()).isEmpty&&c.fetch(FetchDescriptor<MeasurementPlanRow>()).isEmpty&&c.fetch(FetchDescriptor<LightingClaimStateRow>()).isEmpty}
    @MainActor private func backfillV31Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV30Marker(in:c,expectedMigrationID:migrationID);guard try lightingRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=31;marker.releaseID=PersistentSchemaReleaseV1.v31.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v30.compatibilityID;try c.save();_ = try requireV31Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV31Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==31,marker.releaseID==PersistentSchemaReleaseV1.v31.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v30.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let systems=try c.fetch(FetchDescriptor<LightingSystemRow>()).map{try $0.value()},observations=try c.fetch(FetchDescriptor<LightingObservationRow>()).map{try $0.value()},issues=try c.fetch(FetchDescriptor<LightingIssueRow>()).map{try $0.value()},plans=try c.fetch(FetchDescriptor<MeasurementPlanRow>()).map{try $0.value()},claims=try c.fetch(FetchDescriptor<LightingClaimStateRow>()).map{try $0.value()};guard Set(systems.map(\.recordID)).count==systems.count,Set(observations.map(\.recordID)).count==observations.count,Set(issues.map(\.recordID)).count==issues.count,Set(plans.map(\.recordID)).count==plans.count,Set(claims.map(\.recordID)).count==claims.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};func oneSuccessor<T>(_ values:[T],_ f:(T)->UUID?,_ id:UUID)throws{guard values.filter({f($0)==id}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};for v in systems{if let id=v.supersedesRecordID{guard let p=systems.first(where:{$0.recordID==id})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try v.validateSuccessor(of:p)};try oneSuccessor(systems,{ $0.supersedesRecordID },v.recordID)};for v in observations{guard let system=systems.first(where:{$0.systemID==v.systemID&&$0.revision==v.systemRevision&&$0.systemSHA256==v.systemSHA256})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try v.validate(system:system);try oneSuccessor(observations,{ $0.supersedesRecordID },v.recordID)};for v in issues{try oneSuccessor(issues,{ $0.supersedesRecordID },v.recordID)};for v in plans{guard let system=systems.first(where:{$0.systemID==v.systemID&&$0.revision==v.systemRevision&&$0.systemSHA256==v.systemSHA256})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try v.validate(system:system);try oneSuccessor(plans,{ $0.supersedesRecordID },v.recordID)};for v in claims{try oneSuccessor(claims,{ $0.supersedesRecordID },v.recordID)};return marker}
    @MainActor private func assistanceAcceptanceReceiptRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<AssistanceAcceptanceReceiptRow>()).isEmpty}
    @MainActor private func backfillV32Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV31Marker(in:c,expectedMigrationID:migrationID);guard try assistanceAcceptanceReceiptRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=32;marker.releaseID=PersistentSchemaReleaseV1.v32.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v31.compatibilityID;try c.save();_ = try requireV32Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV32Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==32,marker.releaseID==PersistentSchemaReleaseV1.v32.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v31.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireAssistanceAcceptanceReceipts(in:c);return marker}
    @MainActor private func requireAssistanceAcceptanceReceipts(in c:ModelContext)throws->[AssistanceAcceptanceReceiptV1]{let values=try c.fetch(FetchDescriptor<AssistanceAcceptanceReceiptRow>()).map{try $0.value()};guard Set(values.map(\.receiptID)).count==values.count,Set(values.map{ $0.mutationID.rawValue }).count==values.count,Set(values.map(\.proposalID)).count==values.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for value in values{do{try value.validate();let key=MutationWorkspaceKeyV1.value(workspaceID:value.workspaceID,mutationID:value.mutationID),rows=try c.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count==1,let row=rows.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData),receipt=try MutationReceiptV1.decodeCanonical(from:row.receiptData);guard case let .applyAssistanceAcceptance(request)=envelope.command else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validate(request:request);try value.validate(canonicalMutationReceipt:receipt)}catch let failure as StoreMigrationFailure{throw failure}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};return values}
    @MainActor private func temporalEvidenceRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).isEmpty&&c.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>()).isEmpty}
    @MainActor private func backfillV33Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV32Marker(in:c,expectedMigrationID:migrationID);guard try temporalEvidenceRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=33;marker.releaseID=PersistentSchemaReleaseV1.v33.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v32.compatibilityID;try c.save();_ = try requireV33Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV33Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==33,marker.releaseID==PersistentSchemaReleaseV1.v33.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v32.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireTemporalEvidence(in:c);return marker}
    @MainActor private func backfillV34Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV33Marker(in:c,expectedMigrationID:migrationID);guard try assetLabelRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=34;marker.releaseID=PersistentSchemaReleaseV1.v34.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v33.compatibilityID;try c.save();_ = try requireV34Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV34Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==34,marker.releaseID==PersistentSchemaReleaseV1.v34.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v33.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireAssetLabels(in:c);return marker}
    @MainActor private func backfillV35Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV34Marker(in:c,expectedMigrationID:migrationID);guard try operationalContactRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=35;marker.releaseID=PersistentSchemaReleaseV1.v35.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v34.compatibilityID;try c.save();_ = try requireV35Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV35Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==35,marker.releaseID==PersistentSchemaReleaseV1.v35.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v34.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireOperationalContacts(in:c);return marker}
    @MainActor private func activityContractRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).isEmpty&&c.fetch(FetchDescriptor<ActivityStateTransitionRow>()).isEmpty&&c.fetch(FetchDescriptor<InstallationTaskResultRow>()).isEmpty&&c.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).isEmpty&&c.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).isEmpty}
    @MainActor private func backfillV36Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV35Marker(in:c,expectedMigrationID:migrationID);guard try activityContractRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=36;marker.releaseID=PersistentSchemaReleaseV1.v36.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v35.compatibilityID;try c.save();_ = try requireV36Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV36Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==36,marker.releaseID==PersistentSchemaReleaseV1.v36.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v35.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireActivityContracts(in:c);return marker}
    @MainActor private func workResourceRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).isEmpty}
    @MainActor private func backfillV37Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV36Marker(in:c,expectedMigrationID:migrationID);guard try workResourceRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=37;marker.releaseID=PersistentSchemaReleaseV1.v37.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v36.compatibilityID;try c.save();_ = try requireV37Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV37Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==37,marker.releaseID==PersistentSchemaReleaseV1.v37.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v36.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireActivityContracts(in:c);_ = try requireWorkResources(in:c);return marker}
    @MainActor private func scheduleExceptionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ExceptionCalendarReleaseRow>()).isEmpty&&c.fetch(FetchDescriptor<ScheduleOverrideEventRow>()).isEmpty}
    @MainActor private func backfillV38Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV37Marker(in:c,expectedMigrationID:migrationID);guard try scheduleExceptionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=38;marker.releaseID=PersistentSchemaReleaseV1.v38.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v37.compatibilityID;try c.save();_ = try requireV38Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV38Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==38,marker.releaseID==PersistentSchemaReleaseV1.v38.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v37.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireActivityContracts(in:c);_ = try requireWorkResources(in:c);_ = try requireScheduleExceptions(in:c);return marker}
    @MainActor private func serviceRequestRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ServiceRequestRecordRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>()).isEmpty}
    @MainActor private func backfillV39Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV38Marker(in:c,expectedMigrationID:migrationID);guard try serviceRequestRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=39;marker.releaseID=PersistentSchemaReleaseV1.v39.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v38.compatibilityID;try c.save();_ = try requireV39Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV39Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==39,marker.releaseID==PersistentSchemaReleaseV1.v39.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v38.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireActivityContracts(in:c);_ = try requireWorkResources(in:c);_ = try requireScheduleExceptions(in:c);_ = try requireServiceRequests(in:c);return marker}
    @MainActor private func serviceReliabilityRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<AssetServiceIncidentRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceImpactSegmentRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceCauseAssertionRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceRepairIntervalRow>()).isEmpty&&c.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()).isEmpty&&c.fetch(FetchDescriptor<QualifiedServiceExposureRow>()).isEmpty}
    @MainActor private func requireReliabilityChain<T>(_ values:[T],eventID:(T)->UUID,workspaceID:(T)->WorkspaceID,revision:(T)->UInt64,digest:(T)->String,predecessor:(T)->ServiceReliabilityEventReferenceV1?)throws->Int{let identities=values.map{"\(workspaceID($0).rawValue.uuidString.lowercased()):\(eventID($0).uuidString.lowercased())"};guard Set(identities).count==identities.count else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};for value in values{if let reference=predecessor(value){let priors=values.filter{workspaceID($0)==workspaceID(value)&&eventID($0)==reference.eventID&&revision($0)==reference.revision&&digest($0)==reference.eventSHA256};guard priors.count==1,revision(priors[0])<UInt64.max,revision(value)==revision(priors[0])+1 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}}else if revision(value) != 1{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};let successors=values.filter{candidate in guard workspaceID(candidate)==workspaceID(value),let reference=predecessor(candidate)else{return false};return reference.eventID==eventID(value)&&reference.revision==revision(value)&&reference.eventSHA256==digest(value)};guard successors.count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}};return values.count}
    @MainActor private func requireServiceReliability(in c:ModelContext)throws->Int{let incidents=try c.fetch(FetchDescriptor<AssetServiceIncidentRow>()).map{try $0.value()},impacts=try c.fetch(FetchDescriptor<ServiceImpactSegmentRow>()).map{try $0.value()},causes=try c.fetch(FetchDescriptor<ServiceCauseAssertionRow>()).map{try $0.value()},remedies=try c.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()).map{try $0.value()},repairs=try c.fetch(FetchDescriptor<ServiceRepairIntervalRow>()).map{try $0.value()},restorations=try c.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()).map{try $0.value()},exposures=try c.fetch(FetchDescriptor<QualifiedServiceExposureRow>()).map{try $0.value()};return try requireReliabilityChain(incidents,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })+requireReliabilityChain(impacts,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })+requireReliabilityChain(causes,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })+requireReliabilityChain(remedies,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })+requireReliabilityChain(repairs,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })+requireReliabilityChain(restorations,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })+requireReliabilityChain(exposures,eventID:{ $0.eventID },workspaceID:{ $0.workspaceID },revision:{ $0.revision },digest:{ $0.eventSHA256 },predecessor:{ $0.predecessor })}
    @MainActor private func backfillV40Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV39Marker(in:c,expectedMigrationID:migrationID);guard try serviceReliabilityRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=40;marker.releaseID=PersistentSchemaReleaseV1.v40.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v39.compatibilityID;try c.save();_ = try requireV40Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV40Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==40,marker.releaseID==PersistentSchemaReleaseV1.v40.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v39.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};_ = try requireActivityContracts(in:c);_ = try requireWorkResources(in:c);_ = try requireScheduleExceptions(in:c);_ = try requireServiceRequests(in:c);_ = try requireServiceReliability(in:c);return marker}
    @MainActor private func partsStockRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).isEmpty&&c.fetch(FetchDescriptor<StockStorageLocationRowV1>()).isEmpty&&c.fetch(FetchDescriptor<StockMovementEventRowV1>()).isEmpty&&c.fetch(FetchDescriptor<StockUseReceiptRowV1>()).isEmpty&&c.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).isEmpty&&c.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).isEmpty&&c.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).isEmpty}
    @MainActor private func myDayRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<MyDayPlanRowV1>()).isEmpty&&c.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).isEmpty}
    @MainActor private func evidenceCurationRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).isEmpty&&c.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).isEmpty}
    @MainActor private func backfillV41Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV40Marker(in:c,expectedMigrationID:migrationID);guard try partsStockRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=41;marker.releaseID=PersistentSchemaReleaseV1.v41.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v40.compatibilityID;try c.save();_ = try requireV41Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV41Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==41,marker.releaseID==PersistentSchemaReleaseV1.v41.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v40.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func backfillV42Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV41Marker(in:c,expectedMigrationID:migrationID);guard try myDayRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=42;marker.releaseID=PersistentSchemaReleaseV1.v42.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v41.compatibilityID;try c.save();_ = try requireV42Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV42Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==42,marker.releaseID==PersistentSchemaReleaseV1.v42.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v41.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func backfillV43Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV42Marker(in:c,expectedMigrationID:migrationID);guard try evidenceCurationRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=43;marker.releaseID=PersistentSchemaReleaseV1.v43.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v42.compatibilityID;try c.save();_ = try requireV43Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV43Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==43,marker.releaseID==PersistentSchemaReleaseV1.v43.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v42.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{let associations=try c.fetch(FetchDescriptor<EvidenceAssociationEventRowV1>()).map{try $0.value()},sequences=try c.fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>()).map{try $0.value()},states=try c.fetch(FetchDescriptor<WorkspaceMutationStateRow>());if !associations.isEmpty||!sequences.isEmpty{guard states.count==1,let workspaceID=states.first?.workspaceID,associations.allSatisfy({$0.workspaceID==workspaceID.uuidString.lowercased()}),sequences.allSatisfy({$0.workspaceID.rawValue==workspaceID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};try EvidenceMetadataGraphV1.validate(sequences:sequences,associationEvents:associations)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func shopReportProfileRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ShopReportProfileRowV1>()).isEmpty}
    @MainActor private func validatedShopReportProfileValues(in c:ModelContext)throws->[ShopReportProfileV1]{let values=try c.fetch(FetchDescriptor<ShopReportProfileRowV1>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.profileID.uuidString,$0.revision,$0.mutationID.rawValue.uuidString)<($1.workspaceID.rawValue.uuidString,$1.profileID.uuidString,$1.revision,$1.mutationID.rawValue.uuidString)};let mutationKeys=values.map{MutationWorkspaceKeyV1.value(workspaceID:$0.workspaceID,mutationID:$0.mutationID)};guard Set(mutationKeys).count==mutationKeys.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for group in Dictionary(grouping:values,by:{"\($0.workspaceID.rawValue.uuidString)|\($0.profileID.uuidString)"}).values{let history=group.sorted{($0.revision,$0.mutationID.rawValue.uuidString)<($1.revision,$1.mutationID.rawValue.uuidString)};guard Set(history.map(\.revision)).count==history.count,history.first?.revision==1,history.first?.predecessor==nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try history.forEach{try $0.validateIntrinsic()};for index in history.indices.dropFirst(){let prior=history[index-1],current=history[index];guard current.revision==prior.revision+1,current.predecessor==(try prior.reference),current.recordedAt>=prior.recordedAt else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}};return values}
    @MainActor private func backfillV44Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV43Marker(in:c,expectedMigrationID:migrationID);guard try shopReportProfileRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=44;marker.releaseID=PersistentSchemaReleaseV1.v44.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v43.compatibilityID;try c.save();_ = try requireV44Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV44Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==44,marker.releaseID==PersistentSchemaReleaseV1.v44.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v43.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try validatedShopReportProfileValues(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func roundSessionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).isEmpty}
    @MainActor private func validatedRoundSessionValues(in c:ModelContext)throws->[RoundSessionV1]{let values=try c.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).map{try $0.value()}.sorted{($0.workspaceID.rawValue.uuidString,$0.sessionID.uuidString,$0.revision,$0.mutationID.rawValue.uuidString)<($1.workspaceID.rawValue.uuidString,$1.sessionID.uuidString,$1.revision,$1.mutationID.rawValue.uuidString)};let mutationKeys=values.map{MutationWorkspaceKeyV1.value(workspaceID:$0.workspaceID,mutationID:$0.mutationID)};guard Set(mutationKeys).count==mutationKeys.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for group in Dictionary(grouping:values,by:{"\($0.workspaceID.rawValue.uuidString)|\($0.sessionID.uuidString)"}).values{let history=group.sorted{($0.revision,$0.mutationID.rawValue.uuidString)<($1.revision,$1.mutationID.rawValue.uuidString)};guard let first=history.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try RoundSessionHistoryValidatorV1.validate(history,workspaceID:first.workspaceID,sessionID:first.sessionID)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};return values}
    @MainActor private func backfillV45Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV44Marker(in:c,expectedMigrationID:migrationID);guard try roundSessionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=45;marker.releaseID=PersistentSchemaReleaseV1.v45.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v44.compatibilityID;try c.save();_ = try requireV45Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV45Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==45,marker.releaseID==PersistentSchemaReleaseV1.v45.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v44.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try validatedShopReportProfileValues(in:c);_ = try validatedRoundSessionValues(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func importBulkRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ImportMappingProfileRowV1>()).isEmpty&&c.fetch(FetchDescriptor<BulkSessionRowV1>()).isEmpty&&c.fetch(FetchDescriptor<BulkCommitReceiptRowV1>()).isEmpty}
    @MainActor private func backfillV46Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV45Marker(in:c,expectedMigrationID:migrationID);guard try importBulkRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=46;marker.releaseID=PersistentSchemaReleaseV1.v46.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v45.compatibilityID;try c.save();_ = try requireV46Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV46Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==46,marker.releaseID==PersistentSchemaReleaseV1.v46.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v45.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV46(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func evidenceQualityRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).isEmpty&&c.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).isEmpty&&c.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).isEmpty&&c.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).isEmpty}
    @MainActor private func backfillV47Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV46Marker(in:c,expectedMigrationID:migrationID);guard try evidenceQualityRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=47;marker.releaseID=PersistentSchemaReleaseV1.v47.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v46.compatibilityID;try c.save();_ = try requireV47Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV47Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==47,marker.releaseID==PersistentSchemaReleaseV1.v47.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v46.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV47(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func fastSurveyInboxRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).isEmpty&&c.fetch(FetchDescriptor<CapturePromotionRowV1>()).isEmpty&&c.fetch(FetchDescriptor<SnippetRowV1>()).isEmpty&&c.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>()).isEmpty&&c.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).isEmpty}
    @MainActor private func backfillV48Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV47Marker(in:c,expectedMigrationID:migrationID);guard try fastSurveyInboxRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=48;marker.releaseID=PersistentSchemaReleaseV1.v48.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v47.compatibilityID;try c.save();_ = try requireV48Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV48Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==48,marker.releaseID==PersistentSchemaReleaseV1.v48.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v47.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV48(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func reinspectionExceptionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<ReinspectionPlanRowV1>()).isEmpty&&c.fetch(FetchDescriptor<UnchangedAttestationRowV1>()).isEmpty&&c.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>()).isEmpty&&c.fetch(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>()).isEmpty}
    @MainActor private func backfillV49Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV48Marker(in:c,expectedMigrationID:migrationID);guard try reinspectionExceptionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=49;marker.releaseID=PersistentSchemaReleaseV1.v49.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v48.compatibilityID;try c.save();_ = try requireV49Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV49Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==49,marker.releaseID==PersistentSchemaReleaseV1.v49.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v48.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV49(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func entityIdentityResolutionRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<EntityAliasLinkRowV1>()).isEmpty&&c.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).isEmpty&&c.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()).isEmpty}
    @MainActor private func backfillV50Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV49Marker(in:c,expectedMigrationID:migrationID);guard try entityIdentityResolutionRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=50;marker.releaseID=PersistentSchemaReleaseV1.v50.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v49.compatibilityID;try c.save();_ = try requireV50Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV50Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==50,marker.releaseID==PersistentSchemaReleaseV1.v50.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v49.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV50(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func workspaceExperienceRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()).isEmpty}
    @MainActor private func lightingDayInventoryRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<LightingDayInventoryWorkflowRowV1>()).isEmpty}
    @MainActor private func backfillV51Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV50Marker(in:c,expectedMigrationID:migrationID);guard try workspaceExperienceRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=51;marker.releaseID=PersistentSchemaReleaseV1.v51.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v50.compatibilityID;try c.save();_ = try requireV51Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV51Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==51,marker.releaseID==PersistentSchemaReleaseV1.v51.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v50.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV51(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func backfillV52Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV51Marker(in:c,expectedMigrationID:migrationID);guard try lightingDayInventoryRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=52;marker.releaseID=PersistentSchemaReleaseV1.v52.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v51.compatibilityID;try c.save();_ = try requireV52Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV52Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==52,marker.releaseID==PersistentSchemaReleaseV1.v52.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v51.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV52(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func lightingNightWorkflowRowsAreEmpty(in c:ModelContext)throws->Bool{try c.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()).isEmpty}
    @MainActor private func backfillV53Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV52Marker(in:c,expectedMigrationID:migrationID);guard try lightingNightWorkflowRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=53;marker.releaseID=PersistentSchemaReleaseV1.v53.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v52.compatibilityID;try c.save();_ = try requireV53Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV53Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{let markers=try c.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>());guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==53,marker.releaseID==PersistentSchemaReleaseV1.v53.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v52.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};do{_ = try semanticExportV53(in:c)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return marker}
    @MainActor private func requireServiceRequests(in c:ModelContext)throws->Int {
        let recordRows=try c.fetch(FetchDescriptor<ServiceRequestRecordRow>())
        let dispositionRows=try c.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>())
        let linkRows=try c.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>())
        let records=try recordRows.map{try $0.value()}
        let dispositions=try dispositionRows.map{try $0.value()}
        let links=try linkRows.map{try $0.value()}
        guard Set(recordRows.map(\.stableIdentity)).count==recordRows.count,
              Set(dispositions.map(\.eventID)).count==dispositions.count,
              Set(links.map(\.eventID)).count==links.count else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        for value in records {
            if let predecessorReference=value.supersedes {
                let predecessors=records.filter{$0.workspaceID==value.workspaceID&&$0.recordID==value.recordID&&$0.revision==predecessorReference.revision}
                guard predecessors.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}
                try value.validateSuccessor(of:predecessors[0])
            } else if value.revision != 1 {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            guard records.filter{$0.supersedes?.recordID==value.recordID&&$0.supersedes?.revision==value.revision&&$0.supersedes?.recordSHA256==value.recordSHA256}.count<=1 else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
        }
        for value in dispositions {
            let matchingRecords=records.filter{$0.workspaceID==value.workspaceID&&$0.recordID==value.request.recordID&&$0.revision==value.request.revision&&$0.recordSHA256==value.request.recordSHA256}
            guard matchingRecords.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}
            if let predecessorID=value.predecessorEventID {
                let predecessors=dispositions.filter{$0.workspaceID==value.workspaceID&&$0.eventID==predecessorID}
                guard predecessors.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}
                try value.validateSuccessor(of:predecessors[0])
            } else if value.revision != 1 {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            guard dispositions.filter{$0.workspaceID==value.workspaceID&&$0.predecessorEventID==value.eventID}.count<=1 else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
        }
        for value in links {
            let matchingRecords=records.filter{$0.workspaceID==value.workspaceID&&$0.recordID==value.request.recordID&&$0.revision==value.request.revision&&$0.recordSHA256==value.request.recordSHA256}
            guard matchingRecords.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}
            if let predecessorID=value.predecessorEventID {
                let predecessors=links.filter{$0.workspaceID==value.workspaceID&&$0.eventID==predecessorID}
                guard predecessors.count==1,predecessors[0].kind == .link else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}
                try value.validateSuccessor(of:predecessors[0])
                guard value.target==predecessors[0].target,value.choice==predecessors[0].choice,value.canonicalWorkRevision==predecessors[0].canonicalWorkRevision,value.canonicalWorkSHA256==predecessors[0].canonicalWorkSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)}
            } else if value.revision != 1 || value.kind != .link {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            guard links.filter{$0.workspaceID==value.workspaceID&&$0.predecessorEventID==value.eventID}.count<=1 else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
        }
        return records.count+dispositions.count+links.count
    }
    @MainActor private func requireScheduleExceptions(in c:ModelContext)throws->([ExceptionCalendarReleaseV1],[ScheduleOverrideEventV1]){let calendars=try c.fetch(FetchDescriptor<ExceptionCalendarReleaseRow>()).map{try $0.value()},overrides=try c.fetch(FetchDescriptor<ScheduleOverrideEventRow>()).map{try $0.value()};guard Set(calendars.map(\.releaseID)).count==calendars.count,Set(overrides.map(\.eventID)).count==overrides.count else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};_ = try ScheduleOverridePrecedenceV1.activeEvents(overrides);return(calendars,overrides)}
    @MainActor private func requireWorkResources(in c:ModelContext)throws->[WorkResourceEntryV1]{let rows=try c.fetch(FetchDescriptor<ManualWorkResourceRecordRow>());guard Set(rows.map(\.stableIdentity)).count==rows.count else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};let values=try rows.map{try $0.value()};guard Set(values.map(\.entryID)).count==values.count else{throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)};return values}
    @MainActor private func requireActivityContracts(in c: ModelContext) throws -> (
        [ActivitySessionEnvelopeV2], [ActivityStateTransitionV2], [InstallationTaskResultV1],
        [InstallationAsBuiltSnapshotV1], [PunchReviewBasisSnapshotV1]
    ) {
        do {
            let envelopes = try c.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).map { try $0.value() }
            let transitions = try c.fetch(FetchDescriptor<ActivityStateTransitionRow>()).map { try $0.value() }
            let results = try c.fetch(FetchDescriptor<InstallationTaskResultRow>()).map { try $0.value() }
            let asBuilt = try c.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).map { try $0.value() }
            let punch = try c.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).map { try $0.value() }
            guard Set(envelopes.map { $0.workspaceID.rawValue.uuidString + ":" + $0.activityID.uuidString }).count == envelopes.count,
                  Set(transitions.map { $0.workspaceID.rawValue.uuidString + ":" + $0.transitionID.uuidString }).count == transitions.count,
                  Set(results.map { $0.workspaceID.rawValue.uuidString + ":" + $0.resultID.uuidString }).count == results.count,
                  Set(asBuilt.map { $0.workspaceID.rawValue.uuidString + ":" + $0.snapshotID.uuidString }).count == asBuilt.count,
                  Set(punch.map { $0.workspaceID.rawValue.uuidString + ":" + $0.basisID.uuidString }).count == punch.count else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            for value in transitions {
                guard envelopes.contains(where: {
                    $0.workspaceID == value.workspaceID && $0.activityID == value.activityID
                        && $0.kind == value.kind && $0.revision >= value.revision
                }) else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
            }
            let groupedResults = Dictionary(grouping: results) {
                $0.workspaceID.rawValue.uuidString + ":" + $0.activityID.uuidString
            }
            var currentResultHeads: [String: [String: InstallationTaskResultV1]] = [:]
            for (key, values) in groupedResults {
                currentResultHeads[key] = try InstallationTaskResultLineageV1
                    .validateAndCurrentHeads(values)
            }
            for value in results {
                guard envelopes.contains(where: {
                    $0.workspaceID == value.workspaceID && $0.activityID == value.activityID
                        && $0.kind == .installation
                }) else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
            }
            let receipts = try c.fetch(FetchDescriptor<MutationReceiptRow>())
            let activityHistory: [(workspaceRevision: UInt64, mutation: ActivityContractMutationV2)] =
                try receipts.compactMap { row in
                    let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
                    guard case let .applyActivityContract(mutation) = envelope.command else {
                        return nil
                    }
                    let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
                    guard row.workspaceID == mutation.workspaceID.rawValue,
                          receipt.identity.workspaceID == mutation.workspaceID,
                          receipt.mutationID == mutation.mutationID,
                          receipt.resultingRevision.workspaceID == mutation.workspaceID else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                    return (receipt.resultingRevision.workspaceRevision, mutation)
                }
                .sorted { lhs, rhs in
                    if lhs.mutation.workspaceID == rhs.mutation.workspaceID {
                        return lhs.workspaceRevision < rhs.workspaceRevision
                    }
                    return lhs.mutation.workspaceID.rawValue.uuidString
                        < rhs.mutation.workspaceID.rawValue.uuidString
                }
            let historyKeys = activityHistory.map {
                $0.mutation.workspaceID.rawValue.uuidString + ":" + String($0.workspaceRevision)
            }
            guard Set(historyKeys).count == historyKeys.count else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            var installationBasisHeads: [String: InstallationBasisSnapshotV1] = [:]
            var asBuiltAuthorities: [String: (
                snapshot: InstallationAsBuiltSnapshotV1,
                basis: InstallationBasisSnapshotV1
            )] = [:]
            for entry in activityHistory {
                let mutation = entry.mutation
                let activityKey = mutation.workspaceID.rawValue.uuidString + ":"
                    + mutation.successorEnvelope.activityID.uuidString
                if let candidate = mutation.installationBasisSnapshot {
                    if let predecessor = installationBasisHeads[activityKey] {
                        try candidate.validateSuccessor(of: predecessor)
                    } else {
                        try candidate.validate()
                        guard candidate.revision == 1,
                              candidate.predecessorBasisID == nil,
                              candidate.predecessorBasisSHA256 == nil else {
                            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                        }
                    }
                    installationBasisHeads[activityKey] = candidate
                }
                if let snapshot = mutation.installationAsBuiltSnapshot {
                    guard let basis = installationBasisHeads[activityKey] else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                    try snapshot.validateBasis(basis)
                    let snapshotKey = snapshot.workspaceID.rawValue.uuidString + ":"
                        + snapshot.snapshotID.uuidString
                    guard asBuiltAuthorities[snapshotKey] == nil else {
                        throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                    }
                    asBuiltAuthorities[snapshotKey] = (snapshot, basis)
                }
            }
            let persistedAsBuiltKeys = Set(asBuilt.map {
                $0.workspaceID.rawValue.uuidString + ":" + $0.snapshotID.uuidString
            })
            guard Set(asBuiltAuthorities.keys) == persistedAsBuiltKeys else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            for value in asBuilt {
                let key = value.workspaceID.rawValue.uuidString + ":" + value.activityID.uuidString
                guard envelopes.contains(where: {
                    $0.workspaceID == value.workspaceID && $0.activityID == value.activityID
                        && $0.kind == .installation
                }),
                Set(value.taskResultSHA256s) == Set((currentResultHeads[key] ?? [:]).values.map(\.resultSHA256)) else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                let snapshotKey = value.workspaceID.rawValue.uuidString + ":" + value.snapshotID.uuidString
                guard let authority = asBuiltAuthorities[snapshotKey],
                      authority.snapshot == value else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                try value.validateBasis(authority.basis)
            }
            for value in punch {
                guard envelopes.contains(where: {
                    $0.workspaceID == value.workspaceID && $0.activityID == value.activityID
                        && $0.kind == .punchReview
                }) else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
            }
            return (envelopes, transitions, results, asBuilt, punch)
        } catch let failure as StoreMigrationFailure {
            throw failure
        } catch {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
    }
    @MainActor private func requireTemporalEvidence(in c:ModelContext)throws->([TemporalEvidenceClipV1],[TimecodedEvidenceAnchorV1]){do{let clips=try c.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).map{try $0.value()},anchors=try c.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>()).map{try $0.value()};guard Set(clips.map(\.clipID)).count==clips.count,Set(anchors.map(\.anchorID)).count==anchors.count,Set(clips.map{$0.mutationID.rawValue}).count==clips.count,Set(anchors.map{$0.mutationID.rawValue}).count==anchors.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let byID=Dictionary(uniqueKeysWithValues:clips.map{($0.clipID,$0)});for anchor in anchors{guard let clip=byID[anchor.clipID]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try anchor.validate(clip:clip)};return(clips,anchors)}catch let failure as StoreMigrationFailure{throw failure}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
    private func validateEvidencePairPurposeHistory(_ pairs:[PairedObservationLinkV1])throws{var purposeByEvidence:[String:String]=[:];for pair in pairs{for reference in [pair.first,pair.second]{let evidenceKey="\(pair.workspaceID.rawValue.uuidString.lowercased()):\(reference.evidenceID)",purposeKey="\(reference.purpose.rawValue):\(reference.purposeRevision)";if let existing=purposeByEvidence[evidenceKey]{guard existing==purposeKey else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}else{purposeByEvidence[evidenceKey]=purposeKey}}}}

    @MainActor private func validateV29PoseReferences(in c:ModelContext,events:[AssetPoseEventV1],observations:[SpatialAnchorObservationV1])throws{
        let placementEvents=try c.fetch(FetchDescriptor<AssetPlacementEventRow>()).map{try $0.value()}
        let planRevisions=try c.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()}
        for event in events{
            guard placementEvents.filter({$0.id==event.placementEventID&&$0.workspaceID==event.workspaceID&&$0.assetID==event.assetID&&$0.physicalEpisodeID==event.placementEpisodeID&&$0.pathSnapshot==event.locationPathSnapshot}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        let observationsByID=Dictionary(grouping:observations,by:\.observationID)
        guard observationsByID.values.allSatisfy({$0.count==1}) else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        for observation in observations{
            guard planRevisions.filter({$0.workspaceID==observation.workspaceID&&$0.planRevisionID==observation.planFrame.planRevision.planRevisionID&&$0.revision==observation.planFrame.planRevision.revision&&$0.revisionSHA256==observation.planFrame.planRevision.revisionSHA256&&$0.spatialFrames.contains(where:{$0.frameID==observation.planFrame.spatialFrameID&&$0.pageID==observation.planFrame.pageID})}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            if let predecessorID=observation.predecessorObservationID{
                guard let predecessor=observationsByID[predecessorID]?.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
                try observation.validateSuccessor(of:predecessor)
            }
            guard observations.filter({$0.predecessorObservationID==observation.observationID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        let packageReleases=try c.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try $0.value().packageRelease}
        let journalRows=try c.fetch(FetchDescriptor<MutationReceiptRow>())
        var mutations:[PlacementPoseMutationV1]=[]
        for row in journalRows{
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
            switch envelope.command{
            case let .applyPlacementPose(value):mutations.append(value)
            case let .applyPlan(value):if case let .applyRebase(_,_,_,_,_,_,poseEffects)=value.payload,let poseEffects{mutations.append(poseEffects)}
            case let .applyAssetPlacementChange(value):if let pose=try value.placementPoseMutation{mutations.append(pose)}
            case let .applyLocationHierarchyChange(value):if let pose=try value.placementPoseMutation{mutations.append(pose)}
            default:break
            }
        }
        for mutation in mutations{
            try mutation.validate()
            let closure=mutation.admissionClosure
            guard packageReleases.filter({$0==closure.packageRelease}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            for value in closure.planRevisions{guard planRevisions.filter({$0==value}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
            for value in closure.placementEvents{guard placementEvents.filter({$0==value}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        }
        guard Set(mutations.flatMap(\.events).map(\.eventID))==Set(events.map(\.eventID)),
              Set(mutations.flatMap(\.observations).map(\.observationID))==Set(observations.map(\.observationID)) else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
    }

    @MainActor private func validateV25SurveySessionGraph(in c:ModelContext,mutations:[SurveySessionMutationV1],mutationWorkspaceRevisions:[UUID:UInt64],sessions:[SurveySessionV1],facts:[FactCaptureV1],subjects:[ProvisionalSubjectV1],promotions:[SubjectPromotionReceiptV1],publications:[SurveyPublicationSnapshotV1])throws{
        let packageReleases=try c.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try $0.value().packageRelease}
        func validateAuthority(_ session:SurveySessionV1,_ definition:SurveyDefinitionReleaseV1)throws{
            let releaseID=session.authority.packageRelease.packageReleaseID,matches=packageReleases.filter{$0.packageReleaseID==releaseID}
            guard matches.count==1,let release=matches.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            do{try session.authority.validate(definition:definition,packageRelease:release)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        func sessionBinding(_ mutation:SurveySessionMutationV1)->(SurveySessionV1,SurveyDefinitionReleaseV1)?{switch mutation.payload{case let .applySession(session,definition,_),let .captureFact(_,session,definition,_),let .publish(session,_,definition,_):return(session,definition);case .applyProvisionalSubject,.promoteSubject:return nil}}
        for mutation in mutations{if let (session,definition)=sessionBinding(mutation){try validateAuthority(session,definition)}}
        for value in sessions{let matches=mutations.filter{mutation in switch mutation.payload{case .applySession(let candidate,_,_),.publish(let candidate,_,_,_):return candidate==value;default:return false}};guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        for value in facts{let matches=mutations.filter{if case let .captureFact(candidate,_,_,_)=$0.payload{return candidate==value};return false};guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        for value in subjects{let matches=mutations.filter{mutation in switch mutation.payload{case .applyProvisionalSubject(let candidate),.promoteSubject(let candidate,_,_,_):return candidate==value;default:return false}};guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        for value in promotions{let matches=mutations.filter{if case let .promoteSubject(_,candidate,_,_)=$0.payload{return candidate==value};return false};guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        for value in publications{let matches=mutations.filter{if case let .publish(_,candidate,_,_)=$0.payload{return candidate==value};return false};guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}

        for session in sessions{
            let bindings=mutations.compactMap(sessionBinding).filter{$0.0.sessionID==session.sessionID},definitions=bindings.map(\.1)
            guard let definition=definitions.first,definitions.allSatisfy({$0==definition})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            try validateAuthority(session,definition)
            let versions=mutations.compactMap{mutation->SurveySessionV1? in switch mutation.payload{case let .applySession(value,_,_),let .publish(value,_,_,_):return value.sessionID==session.sessionID ? value:nil;default:return nil}}.sorted{$0.revision<$1.revision}
            guard !versions.isEmpty,versions.last==session,versions[0].revision==1,Set(versions.map(\.revision)).count==versions.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            for index in versions.indices.dropFirst(){let value=versions[index],prior=versions[versions.index(before:index)],publication:SurveyPublicationSnapshotV1?;if value.transition == .complete{let values=mutations.compactMap{mutation->SurveyPublicationSnapshotV1? in if case let .publish(candidate,candidatePublication,_,_)=mutation.payload,candidate==value{return candidatePublication};return nil};guard values.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};publication=values[0]}else{publication=nil};do{try value.validateSuccessor(of:prior,publication:publication)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
            let sessionFacts=facts.filter{$0.workspaceID==session.workspaceID&&$0.sessionID==session.sessionID}
            do{_ = try SurveySessionLifecycleClosureV1(definition:definition,sessions:[session],captures:sessionFacts,provisionalSubjects:[],promotionReceipts:[],publications:[])}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            let referenced=Set(sessionFacts.flatMap{$0.predecessors.map(\.captureID)}),heads=sessionFacts.filter{!referenced.contains($0.captureID)}
            if session.state == .completed,let publicationReference=session.latestPublication{
                let publicationMatches=publications.filter{$0.snapshotID==publicationReference.snapshotID&&$0.revision==publicationReference.revision&&$0.snapshotSHA256==publicationReference.snapshotSHA256}
                guard publicationMatches.count==1,let publication=publicationMatches.first else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
                let publishMutations=mutations.filter{if case let .publish(candidateSession,candidateSnapshot,_,_)=$0.payload{return candidateSession==session&&candidateSnapshot==publication};return false}
                guard publishMutations.count==1,case let .publish(_,_,_,publishedCaptures)=publishMutations[0].payload,Set(publishedCaptures.map(\.captureID)).count==publishedCaptures.count,Set(publishedCaptures.map(\.captureID))==Set(heads.map(\.captureID)),publishedCaptures.allSatisfy({value in heads.filter{$0.captureID==value.captureID}.count==1&&heads.first(where:{$0.captureID==value.captureID})==value})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            }
        }
        for receipt in promotions{
            let predecessor=receipt.predecessorReceiptID.flatMap{id in promotions.first{$0.receiptID==id}}
            do{try receipt.validate(preview:receipt.reconstructedPreview,predecessor:predecessor)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            if let predecessorID=receipt.predecessorReceiptID{guard promotions.filter({$0.receiptID==predecessorID}).count==1,promotions.filter({$0.predecessorReceiptID==predecessorID}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
            guard receipt.affectedSessionIDs.allSatisfy({id in sessions.contains(where:{$0.sessionID==id&&$0.workspaceID==receipt.workspaceID})})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        }
        for subject in subjects{
            let versions=mutations.compactMap{mutation->(ProvisionalSubjectV1,SubjectPromotionActionV1?)? in switch mutation.payload{case let .applyProvisionalSubject(value):return value.provisionalSubjectID==subject.provisionalSubjectID ? (value,nil):nil;case let .promoteSubject(value,receipt,_,_):return value.provisionalSubjectID==subject.provisionalSubjectID ? (value,receipt.action):nil;default:return nil}}.sorted{$0.0.revision<$1.0.revision}
            guard !versions.isEmpty,versions.last?.0==subject,versions[0].0.revision==1,versions[0].0.state == .active,Set(versions.map{$0.0.revision}).count==versions.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            for index in versions.indices.dropFirst(){let value=versions[index].0,action=versions[index].1,prior=versions[versions.index(before:index)].0;guard prior.revision<UInt64.max,value.revision==prior.revision+1,value.supersedesSubjectSHA256==prior.subjectSHA256,value.workspaceID==prior.workspaceID,value.siteID==prior.siteID else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};if let action{let target:ProvisionalSubjectStateV1=action == .promoteToAsset ? .promoted:(action == .reconcileAsAlias ? .reconciledAlias:.promotionReversed),sourceIsValid=action == .reverse ? (prior.state == .promoted || prior.state == .reconciledAlias):(prior.state == .active || prior.state == .promotionReversed);guard sourceIsValid,value.state==target else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}else{let allowed=(prior.state == .active&&value.state == .active)||(prior.state != .archived&&value.state == .archived);guard allowed else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}}
        }
        for publication in publications{
            let matches=mutations.compactMap{mutation->(SurveySessionV1,SurveyDefinitionReleaseV1,[FactCaptureV1],MutationIDV1)? in if case let .publish(session,candidate,definition,captures)=mutation.payload,candidate==publication{return(session,definition,captures,mutation.mutationID)};return nil}
            guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            let (session,definition,captures,publicationMutationID)=matches[0]
            try validateAuthority(session,definition)
            guard let publicationWorkspaceRevision=mutationWorkspaceRevisions[publicationMutationID.rawValue]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            let factsAtPublication=mutations.compactMap{mutation->FactCaptureV1? in guard let workspaceRevision=mutationWorkspaceRevisions[mutation.mutationID.rawValue],workspaceRevision<=publicationWorkspaceRevision,case let .captureFact(value,capturedSession,_,_)=mutation.payload,value.sessionID==session.sessionID,capturedSession.revision<session.revision else{return nil};return value},referencedAtPublication=Set(factsAtPublication.flatMap{$0.predecessors.map(\.captureID)}),factHeadsAtPublication=factsAtPublication.filter{!referencedAtPublication.contains($0.captureID)}
            let promotionsAtPublication=mutations.compactMap{mutation->SubjectPromotionReceiptV1? in guard let workspaceRevision=mutationWorkspaceRevisions[mutation.mutationID.rawValue],workspaceRevision<=publicationWorkspaceRevision,case let .promoteSubject(_,receipt,_,_)=mutation.payload,receipt.workspaceID==session.workspaceID,receipt.affectedSessionIDs.contains(session.sessionID)else{return nil};return receipt},supersededAtPublication=Set(promotionsAtPublication.compactMap(\.predecessorReceiptID)),promotionHeadsAtPublication=promotionsAtPublication.filter{!supersededAtPublication.contains($0.receiptID)}
            guard Set(captures.map(\.captureID)).count==captures.count,Set(captures.map(\.captureID))==Set(factHeadsAtPublication.map(\.captureID)),captures.allSatisfy({value in facts.filter{$0.captureID==value.captureID}.count==1&&facts.first(where:{$0.captureID==value.captureID})==value}),Set(publication.promotionReceiptsAtPublication.map(\.receiptID)).count==publication.promotionReceiptsAtPublication.count,Set(publication.promotionReceiptsAtPublication.map(\.receiptID))==Set(promotionHeadsAtPublication.map(\.receiptID)),publication.promotionReceiptsAtPublication.allSatisfy({value in promotions.filter{$0.receiptID==value.receiptID}.count==1&&promotions.first(where:{$0.receiptID==value.receiptID})==value})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            do{try publication.validate(session:session,definition:definition,captures:captures)}catch{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
            if let predecessorID=publication.supersedesSnapshotID{let prior=publications.filter{$0.snapshotID==predecessorID};guard prior.count==1,let predecessor=prior.first,predecessor.workspaceID==publication.workspaceID,predecessor.sessionID==publication.sessionID,predecessor.revision<UInt64.max,publication.revision==predecessor.revision+1,publications.filter({$0.supersedesSnapshotID==predecessorID}).count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}else{guard publication.revision==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}}
        }
    }

    private static func validateV24SurveyDefinitionGraph(
        identities:[SurveyDefinitionIdentityV1],
        releases:[SurveyDefinitionReleaseV1],
        events:[SurveyDefinitionLifecycleEventV1]
    )throws{
        guard Set(identities.map(\.definitionID)).count==identities.count,
              Set(releases.map(\.releaseID)).count==releases.count,
              Set(events.map(\.eventID)).count==events.count,
              Set(events.map{$0.mutationID.rawValue}).count==events.count else{
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let identityByID=Dictionary(uniqueKeysWithValues:identities.map{($0.definitionID,$0)})
        let releaseByID=Dictionary(uniqueKeysWithValues:releases.map{($0.releaseID,$0)})
        let eventByID=Dictionary(uniqueKeysWithValues:events.map{($0.eventID,$0)})
        var releaseChildCount:[UUID:Int]=[:]
        for release in releases {
            guard let identity=identityByID[release.definitionID],identity.workspaceID==release.workspaceID else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            if let predecessorID=release.supersedesReleaseID {
                guard let predecessor=releaseByID[predecessorID] else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                try release.validateSuccessor(of:predecessor)
                releaseChildCount[predecessorID,default:0]+=1
                guard releaseChildCount[predecessorID,default:0]==1 else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
            }
        }
        var eventChildCount:[UUID:Int]=[:]
        for event in events {
            guard let identity=identityByID[event.definitionID],identity.workspaceID==event.workspaceID,
                  let release=releaseByID[event.release.releaseID] else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            try event.validate(release:release)
            if let predecessorID=event.predecessorEventID {
                guard let predecessor=eventByID[predecessorID] else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                try event.validateSuccessor(of:predecessor,release:release)
                eventChildCount[predecessorID,default:0]+=1
                guard eventChildCount[predecessorID,default:0]==1 else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
            }
        }
        for identity in identities {
            guard let release=releaseByID[identity.currentRelease.releaseID],
                  let event=eventByID[identity.latestLifecycleEventID],
                  identity.latestLifecycleEventSHA256==event.eventSHA256 else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            try identity.validate(currentRelease:release,event:event)
            let definitionEvents=events.filter{$0.definitionID==identity.definitionID}
            let roots=definitionEvents.filter{$0.predecessorEventID==nil}
            let heads=definitionEvents.filter{eventChildCount[$0.eventID,default:0]==0}
            guard roots.count==1,heads.count==1,heads[0].eventID==identity.latestLifecycleEventID else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            var visited=Set<UUID>(),cursor:SurveyDefinitionLifecycleEventV1?=event
            while let current=cursor {
                guard visited.insert(current.eventID).inserted else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                cursor=current.predecessorEventID.flatMap{eventByID[$0]}
            }
            guard visited.count==definitionEvents.count else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            let definitionReleases=releases.filter{$0.definitionID==identity.definitionID}
            let releaseRoots=definitionReleases.filter{$0.supersedesReleaseID==nil}
            let releaseHeads=definitionReleases.filter{releaseChildCount[$0.releaseID,default:0]==0}
            guard releaseRoots.count==1,releaseHeads.count==1,
                  releaseHeads[0].releaseID==identity.currentRelease.releaseID else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            var visitedReleases=Set<UUID>(),releaseCursor:SurveyDefinitionReleaseV1?=release
            while let current=releaseCursor {
                guard visitedReleases.insert(current.releaseID).inserted else{
                    throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
                }
                releaseCursor=current.supersedesReleaseID.flatMap{releaseByID[$0]}
            }
            guard visitedReleases.count==definitionReleases.count else{
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
        }
        guard events.allSatisfy({identityByID[$0.definitionID] != nil}),
              releases.allSatisfy({identityByID[$0.definitionID] != nil}) else{
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
    }
    @MainActor private func backfillV22Marker(in c:ModelContext,migrationID:UUID)throws{let marker=try requireV21Marker(in:c,expectedMigrationID:migrationID);guard try fieldReferenceRowsAreEmpty(in:c)else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};marker.schemaVersion=22;marker.releaseID=PersistentSchemaReleaseV1.v22.compatibilityID;marker.predecessorReleaseID=PersistentSchemaReleaseV1.v21.compatibilityID;try c.save();_ = try requireV22Marker(in:c,expectedMigrationID:migrationID)}
    @MainActor private func requireV22Marker(in c:ModelContext,expectedMigrationID:UUID?)throws->PersistentSchemaReleaseMarker{var d=FetchDescriptor<PersistentSchemaReleaseMarker>();d.fetchLimit=2;let markers=try c.fetch(d);guard markers.count==1,let marker=markers.first,marker.id==PersistentSchemaReleaseRegistryV1.v2MarkerID,marker.schemaVersion==22,marker.releaseID==PersistentSchemaReleaseV1.v22.compatibilityID,marker.predecessorReleaseID==PersistentSchemaReleaseV1.v21.compatibilityID,expectedMigrationID.map({marker.migrationID==$0}) ?? marker.migrationID != nil else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let releases=try c.fetch(FetchDescriptor<FieldReferenceReleaseRow>()).map{try $0.value()},bindingRows=try c.fetch(FetchDescriptor<FieldReferenceBindingRow>());guard Set(releases.map(\.releaseID)).count==releases.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};let bindings=try bindingRows.map{row in guard let release=releases.first(where:{$0.releaseID==row.releaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};return try row.value(release:release)};let workspaceRows=try c.fetch(FetchDescriptor<WorkspaceMutationStateRow>()),mutationIDs=releases.map{$0.mutationID.rawValue}+bindings.map{$0.mutationID.rawValue};guard workspaceRows.count<=1,workspaceRows.first.map({id in releases.allSatisfy{$0.workspaceID.rawValue==id.workspaceID}&&bindings.allSatisfy{$0.workspaceID.rawValue==id.workspaceID}}) ?? (releases.isEmpty&&bindings.isEmpty),Set(bindings.map(\.bindingID)).count==bindings.count,Set(mutationIDs).count==mutationIDs.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};for release in releases{if let id=release.supersedesReleaseID{guard let prior=releases.first(where:{$0.releaseID==id})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try release.validateSuccessor(of:prior)};guard releases.filter({$0.supersedesReleaseID==release.releaseID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};for binding in bindings{guard let release=releases.first(where:{$0.releaseID==binding.releaseID})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};if let id=binding.supersedesBindingID{guard let prior=bindings.first(where:{$0.bindingID==id})else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try binding.validateSuccessor(of:prior,release:release)};guard bindings.filter({$0.supersedesBindingID==binding.bindingID}).count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};return marker}
    @MainActor private func validateMeasurementIntegrityClosure(in c:ModelContext,instruments:[InstrumentReferenceV1],calibrations:[CalibrationStatusSnapshotV1],captures:[MeasurementCaptureV1],series:[MeasurementSeriesV1],assessments:[MeasurementQualityAssessmentV1])throws{
        let workspaceRows=try c.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard workspaceRows.count<=1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let expectedWorkspace=workspaceRows.first?.workspaceID
        let allWorkspaceIDs=instruments.map{$0.workspaceID.rawValue}+calibrations.map{$0.workspaceID.rawValue}+captures.map{$0.workspaceID.rawValue}+series.map{$0.workspaceID.rawValue}+assessments.map{$0.workspaceID.rawValue}
        guard expectedWorkspace.map({id in allWorkspaceIDs.allSatisfy{$0==id}}) ?? allWorkspaceIDs.isEmpty else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        guard Set(instruments.map(\.referenceID)).count==instruments.count,Set(calibrations.map(\.snapshotID)).count==calibrations.count,Set(captures.map(\.captureID)).count==captures.count,Set(series.map(\.snapshotID)).count==series.count,Set(assessments.map(\.assessmentID)).count==assessments.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let instrumentByID=Dictionary(uniqueKeysWithValues:instruments.map{($0.referenceID,$0)})
        let calibrationByID=Dictionary(uniqueKeysWithValues:calibrations.map{($0.snapshotID,$0)})
        let captureByID=Dictionary(uniqueKeysWithValues:captures.map{($0.captureID,$0)})
        let seriesByID=Dictionary(uniqueKeysWithValues:series.map{($0.snapshotID,$0)})
        let assessmentByID=Dictionary(uniqueKeysWithValues:assessments.map{($0.assessmentID,$0)})
        let protocols=try c.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).map{try $0.value()}
        guard Set(protocols.map(\.releaseID)).count==protocols.count else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}
        let protocolByID=Dictionary(uniqueKeysWithValues:protocols.map{($0.releaseID,$0)})
        var predecessorKeys=Set<String>()
        for value in instruments{if let id=value.supersedesReferenceID{guard predecessorKeys.insert("instrument:\(id.uuidString)").inserted,let predecessor=instrumentByID[id]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)}}
        for value in calibrations{guard let instrument=instrumentByID[value.instrument.referenceID],try InstrumentRevisionReferenceV1(instrument)==value.instrument else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};if let id=value.supersedesSnapshotID{guard predecessorKeys.insert("calibration:\(id.uuidString)").inserted,let predecessor=calibrationByID[id]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)}}
        for value in captures{try value.validateClosure(instrument:value.instrument.flatMap{instrumentByID[$0.referenceID]},calibration:value.calibration.flatMap{calibrationByID[$0.snapshotID]})}
        for value in captures{if let id=value.supersedesCaptureID{guard predecessorKeys.insert("capture:\(id.uuidString)").inserted,let predecessor=captureByID[id]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)}}
        for value in series{guard let protocolRelease=protocolByID[value.protocolReference.releaseID]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateClosure(captures:value.samples.compactMap{captureByID[$0.captureID]},protocolRelease:protocolRelease);if let id=value.supersedesSnapshotID{guard predecessorKeys.insert("series:\(id.uuidString)").inserted,let predecessor=seriesByID[id]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)}}
        for value in assessments{switch value.subjectKind{case .capture:guard let subject=captureByID[value.subjectID],subject.revision==value.subjectRevision,subject.captureSHA256==value.subjectSHA256 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};case .series:let matches=series.filter{$0.seriesID==value.subjectID&&$0.revision==value.subjectRevision&&$0.seriesSHA256==value.subjectSHA256};guard matches.count==1 else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)}};if let id=value.supersedesAssessmentID{guard predecessorKeys.insert("assessment:\(id.uuidString)").inserted,let predecessor=assessmentByID[id]else{throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)};try value.validateSuccessor(of:predecessor)}}
    }
    @MainActor
    private func requireV12Marker(in context: ModelContext, expectedMigrationID: UUID?) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>(); descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 12,
              marker.releaseID == PersistentSchemaReleaseV1.v12.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v11.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let descriptors = try context.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>())
        let events = try context.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>())
        try descriptors.forEach { _ = try $0.value() }; try events.forEach { _ = try $0.value() }
        let workspaceIDs = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map(\.workspaceID)
        guard workspaceIDs.count <= 1 else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
        let expectedWorkspaceID = workspaceIDs.first
        guard Set(descriptors.map(\.descriptorReleaseID)).count == descriptors.count,
              Set(events.map(\.eventID)).count == events.count,
              expectedWorkspaceID.map({ id in
                descriptors.allSatisfy { $0.workspaceID == id }
                    && events.allSatisfy { $0.workspaceID == id }
              }) ?? (descriptors.isEmpty && events.isEmpty) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func requireV11Marker(in context: ModelContext, expectedMigrationID: UUID?) throws -> PersistentSchemaReleaseMarker {
        var descriptor = FetchDescriptor<PersistentSchemaReleaseMarker>(); descriptor.fetchLimit = 2
        let markers = try context.fetch(descriptor)
        guard markers.count == 1, let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 11,
              marker.releaseID == PersistentSchemaReleaseV1.v11.compatibilityID,
              marker.predecessorReleaseID == PersistentSchemaReleaseV1.v10.compatibilityID,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? (marker.migrationID != nil) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let workspaceIDs = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map(\.workspaceID)
        guard workspaceIDs.count <= 1 else { throw StoreMigrationFailure.maintenanceRequired(.targetMismatch) }
        let expected = workspaceIDs.first
        let authoritySources = try context.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
        let requirementBindings = try context.fetch(FetchDescriptor<RequirementBasisBindingRow>())
        let applicabilitySnapshots = try context.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>())
        let assessmentScopes = try context.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>())
        let severityScales = try context.fetch(FetchDescriptor<SeverityScaleReleaseRow>())
        let findingClassifications = try context.fetch(FetchDescriptor<FindingClassificationBindingRow>())
        let measurementProtocols = try context.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>())
        let evaluatorDescriptors = try context.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>())
        let derivedFacts = try context.fetch(FetchDescriptor<DerivedFactProvenanceRow>())
        try authoritySources.forEach { _ = try $0.value() }
        try requirementBindings.forEach { _ = try $0.value() }
        try applicabilitySnapshots.forEach { _ = try $0.value() }
        try assessmentScopes.forEach { _ = try $0.value() }
        try severityScales.forEach { _ = try $0.value() }
        try findingClassifications.forEach { _ = try $0.value() }
        try measurementProtocols.forEach { _ = try $0.value() }
        try evaluatorDescriptors.forEach { _ = try $0.value() }
        try derivedFacts.forEach { _ = try $0.value() }
        let observed = authoritySources.map(\.workspaceID)
            + requirementBindings.map(\.workspaceID)
            + applicabilitySnapshots.map(\.workspaceID)
            + assessmentScopes.map(\.workspaceID)
            + severityScales.map(\.workspaceID)
            + findingClassifications.map(\.workspaceID)
            + measurementProtocols.map(\.workspaceID)
            + evaluatorDescriptors.map(\.workspaceID)
            + derivedFacts.map(\.workspaceID)
        guard expected.map({ id in observed.allSatisfy { $0 == id } }) ?? observed.isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    @MainActor
    private func backfillV10AssetSemantics(
        in context: ModelContext,
        migrationID: UUID,
        targetGenerationID: UUID
    ) throws {
        guard try context.fetch(FetchDescriptor<AssetKindBindingEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetProductIdentityRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetLifecycleEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetSuccessorLinkRow>()).isEmpty,
              try context.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1, let state = states.first,
              state.generationID == targetGenerationID else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let assets = try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.id)]))
        let workspaceID = WorkspaceID(rawValue: state.workspaceID)
        let mutationID = try MutationIDV1(rawValue: migrationID)
        let acceptedCatalog = try BundledInspectionPackageRegistryV2.shippingAssetSemanticCatalog()
        for asset in assets {
            let recordedAt = try canonicalAssetSemanticDate(asset.createdAt)
            let packageRelease = try asset.legacyPackageReleaseIdentityForAssetSemanticMigration()
            guard packageRelease == acceptedCatalog.packageRelease else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            let catalogRelease = acceptedCatalog.reference
            let kindEventID = deterministicAssetSemanticUUID(
                domain: "asset-semantics/legacy-kind-binding/v1",
                workspaceID: state.workspaceID,
                assetID: asset.id
            )
            let kindDraft = AssetKindBindingEventV1(
                eventID: kindEventID,
                workspaceID: workspaceID,
                assetID: asset.id,
                catalogRelease: catalogRelease,
                semanticID: AssetSemanticPersistenceReleaseV1.acceptedLegacySignSemanticID,
                predecessorEventID: nil,
                revision: 1,
                mutationID: mutationID,
                recordedAt: recordedAt,
                eventSHA256: String(repeating: "0", count: 64)
            )
            let kind = try kindDraft.rebound(to: workspaceID)
            try kind.validate()
            let workflowEventID = deterministicAssetSemanticUUID(
                domain: "asset-semantics/legacy-workflow-binding/v1",
                workspaceID: state.workspaceID,
                assetID: asset.id
            )
            let workflowDraft = try AssetWorkflowCapabilityBindingEventV1(
                eventID: workflowEventID,
                workspaceID: workspaceID,
                assetID: asset.id,
                kindBindingEventID: kindEventID,
                kindBindingRevision: 1,
                workflowPackageRelease: packageRelease,
                capabilityIDs: [],
                disposition: .bound,
                predecessorEventID: nil,
                revision: 1,
                mutationID: mutationID,
                recordedAt: recordedAt,
                eventSHA256: String(repeating: "0", count: 64)
            )
            let workflow = try workflowDraft.rebound(to: workspaceID)
            context.insert(try AssetKindBindingEventRow(kind))
            context.insert(try AssetWorkflowCapabilityBindingEventRow(workflow))
        }
        try backfillV10Marker(in: context, migrationID: migrationID)
        try requireV10LegacyMigrationState(in: context, migrationID: migrationID)
    }

    @MainActor
    private func requireV10LegacyMigrationState(
        in context: ModelContext,
        migrationID: UUID
    ) throws {
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let kinds = try context.fetch(FetchDescriptor<AssetKindBindingEventRow>()).map { try $0.value() }
        let workflows = try context.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>()).map { try $0.value() }
        guard states.count == 1, let state = states.first,
              kinds.count == assets.count, workflows.count == assets.count,
              Set(kinds.map(\.assetID)) == Set(assets.map(\.id)),
              Set(workflows.map(\.assetID)) == Set(assets.map(\.id)),
              Set(kinds.map(\.assetID)).count == kinds.count,
              Set(workflows.map(\.assetID)).count == workflows.count,
              try context.fetch(FetchDescriptor<AssetProductIdentityRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetLifecycleEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetSuccessorLinkRow>()).isEmpty,
              try context.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let mutation = try MutationIDV1(rawValue: migrationID)
        let acceptedCatalog = try BundledInspectionPackageRegistryV2.shippingAssetSemanticCatalog()
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let kindsByAsset = Dictionary(uniqueKeysWithValues: kinds.map { ($0.assetID, $0) })
        for asset in assets {
            guard let kind = kindsByAsset[asset.id] else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            let expectedPackage = try asset.legacyPackageReleaseIdentityForAssetSemanticMigration()
            guard kind.workspaceID.rawValue == state.workspaceID,
                  expectedPackage == acceptedCatalog.packageRelease,
                  kind.catalogRelease == acceptedCatalog.reference,
                  kind.semanticID == AssetSemanticPersistenceReleaseV1.acceptedLegacySignSemanticID,
                  kind.predecessorEventID == nil, kind.revision == 1,
                  kind.mutationID == mutation,
                  kind.recordedAt == (try canonicalAssetSemanticDate(asset.createdAt)) else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
        }
        for workflow in workflows {
            guard let asset = assetsByID[workflow.assetID], let kind = kindsByAsset[workflow.assetID],
                  workflow.workspaceID.rawValue == state.workspaceID,
                  workflow.kindBindingEventID == kind.eventID,
                  workflow.kindBindingRevision == kind.revision,
                  workflow.workflowPackageRelease == (try PackageReleaseIdentityV1(
                      packageID: asset.packID,
                      schemaVersion: asset.packSchemaVersion,
                      contentVersion: asset.packContentVersion
                  )),
                  workflow.capabilityIDs.isEmpty, workflow.disposition == .bound,
                  workflow.predecessorEventID == nil, workflow.revision == 1,
                  workflow.mutationID == mutation,
                  workflow.recordedAt == (try canonicalAssetSemanticDate(asset.createdAt)) else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
        }
    }

    private func deterministicAssetSemanticUUID(
        domain: String,
        workspaceID: UUID,
        assetID: UUID
    ) -> UUID {
        let material = Data("\(domain)|\(workspaceID.uuidString.lowercased())|\(assetID.uuidString.lowercased())".utf8)
        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func canonicalAssetSemanticDate(_ value: Date) throws -> Date {
        let data = try AssetSemanticCanonicalCodecV1.encode(
            AssetSemanticDateBoxV1(value: value)
        )
        return try AssetSemanticCanonicalCodecV1.decode(
            AssetSemanticDateBoxV1.self,
            from: data
        ).value
    }

    private func deterministicLocationUUID(
        domain: String,
        workspaceID: UUID,
        assetID: UUID
    ) -> UUID {
        let material = Data(
            "\(domain)|\(workspaceID.uuidString.lowercased())|\(assetID.uuidString.lowercased())".utf8
        )
        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @MainActor
    private func backfillLegacyRestoreV6LocationBaseline(
        in context: ModelContext,
        migrationID: UUID,
        archivalSourceGenerationID: UUID,
        targetGenerationID: UUID
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard archivalSourceGenerationID != zero,
              archivalSourceGenerationID != targetGenerationID,
              try context.fetch(FetchDescriptor<LocationNodeRow>()).isEmpty,
              try context.fetch(FetchDescriptor<LocationHierarchyEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetPlacementEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetCompositionEdgeRow>()).isEmpty,
              try context.fetch(FetchDescriptor<AssetCompositionEventRow>()).isEmpty,
              try context.fetch(FetchDescriptor<LocationMigrationReceiptRow>()).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let states = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1,
              states[0].generationID == targetGenerationID else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        let workspaceID = WorkspaceID(rawValue: states[0].workspaceID)
        let sites = try context.fetch(
            FetchDescriptor<Site>(sortBy: [SortDescriptor(\.id)])
        )
        let siteByID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
        let assets = try context.fetch(
            FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.id)])
        )
        var bindings: [LocationMigratedBaselineBindingV1] = []
        for asset in assets {
            guard let site = siteByID[asset.siteID] else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            let eventID = deterministicLocationUUID(
                domain: "field-evidence/v23/c35/restore-migrated-placement",
                workspaceID: workspaceID.rawValue,
                assetID: asset.id
            )
            let episodeID = deterministicLocationUUID(
                domain: "field-evidence/v23/c35/restore-migrated-episode",
                workspaceID: workspaceID.rawValue,
                assetID: asset.id
            )
            let mutationID = deterministicLocationUUID(
                domain: "field-evidence/v23/c35/restore-migrated-mutation",
                workspaceID: workspaceID.rawValue,
                assetID: asset.id
            )
            let event = try AssetPlacementEventV1(
                id: eventID,
                workspaceID: workspaceID,
                assetID: asset.id,
                siteID: asset.siteID,
                locationNodeID: nil,
                predecessorEventID: nil,
                source: .migratedBaseline,
                physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: episodeID),
                continuity: .samePhysicalInstallation,
                pathSnapshot: try LocationPathSnapshotV1(
                    siteID: site.id,
                    siteDisplay: site.label,
                    nodes: []
                ),
                mutationID: try MutationIDV1(rawValue: mutationID),
                occurredAt: asset.createdAt
            )
            context.insert(try AssetPlacementEventRow(event))
            bindings.append(LocationMigratedBaselineBindingV1(
                assetID: asset.id,
                siteID: asset.siteID,
                placementEventID: eventID,
                physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: episodeID)
            ))
        }
        context.insert(try LocationMigrationReceiptRow(LocationMigrationReceiptV1(
            workspaceID: workspaceID,
            sourceGenerationID: archivalSourceGenerationID,
            candidateGenerationID: targetGenerationID,
            sourceSiteCount: sites.count,
            sourceAssetCount: assets.count,
            bindings: bindings.sorted()
        )))
        try context.save()
        _ = try requireV6Marker(in: context, expectedMigrationID: migrationID)
    }

    private func archivalSourceGenerationID(
        archiveProvenanceSHA256: String,
        targetGenerationID: UUID
    ) throws -> UUID {
        guard CompatibilityCanonicalV1.validSHA256(archiveProvenanceSHA256) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let material = Data(
            "field-evidence/v23/c35/legacy-archive-source|\(archiveProvenanceSHA256)".utf8
        )
        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let derived = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard derived != zero, derived != targetGenerationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return derived
    }

    @MainActor
    private func insertOrRequireV2Marker(
        in context: ModelContext,
        migrationID: UUID
    ) throws {
        let markers = try context.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        if markers.isEmpty {
            context.insert(
                PersistentSchemaReleaseMarker(
                    id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
                    schemaVersion: 2,
                    releaseID: PersistentSchemaReleaseRegistryV1.v2CompatibilityID,
                    predecessorReleaseID:
                        PersistentSchemaReleaseRegistryV1.v1CompatibilityID,
                    migrationID: migrationID
                )
            )
            try context.save()
            guard !context.hasChanges else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
        }
        _ = try requireV2Marker(
            in: context,
            expectedMigrationID: migrationID
        )
    }

    @MainActor
    private func requireV2Marker(
        in context: ModelContext,
        expectedMigrationID: UUID?
    ) throws -> PersistentSchemaReleaseMarker {
        let markers = try context.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        guard markers.count == 1,
              let marker = markers.first,
              marker.id == PersistentSchemaReleaseRegistryV1.v2MarkerID,
              marker.schemaVersion == 2,
              marker.releaseID == PersistentSchemaReleaseRegistryV1.v2CompatibilityID,
              marker.predecessorReleaseID
                == PersistentSchemaReleaseRegistryV1.v1CompatibilityID,
              marker.migrationID != nil,
              expectedMigrationID.map({ marker.migrationID == $0 }) ?? true else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return marker
    }

    private func generationFileDigests(
        at generationRootURL: URL,
        durable: Bool
    ) throws -> [StoreGenerationFileDigestV1] {
        let descriptor = try openOwnedDirectory(at: generationRootURL)
        defer { _ = Darwin.close(descriptor) }
        let names = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: true
        ).sorted()
        var values = [StoreGenerationFileDigestV1]()
        for name in names {
            let captured = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: descriptor,
                name: name
            )
            let kind: OwnedFileKindV1
            switch name {
            case Self.modelStoreName: kind = .database
            case "\(Self.modelStoreName)-wal": kind = .databaseWAL
            case "\(Self.modelStoreName)-shm": kind = .databaseSHM
            default: throw StoreMigrationFailure.invalidPath
            }
            values.append(
                try StoreGenerationFileDigestV1(
                    relativePath: name,
                    byteCount: captured.data.count,
                    sha256: StoreMigrationCanonicalJSONV1.sha256(captured.data),
                    kind: kind
                )
            )
            if durable {
                let file = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetUnavailable)
                }
                defer { _ = Darwin.close(file) }
                guard Darwin.fsync(file) == 0 else {
                    throw StoreMigrationFailure.maintenanceRequired(.targetUnavailable)
                }
            }
        }
        if durable, Darwin.fsync(descriptor) != 0 {
            throw StoreMigrationFailure.maintenanceRequired(.targetUnavailable)
        }
        return values
    }

    private func generationTreeDigest(at generationRootURL: URL) throws -> String {
        let files = try generationFileDigests(
            at: generationRootURL,
            durable: false
        )
        return StoreMigrationCanonicalJSONV1.sha256(
            try StoreMigrationCanonicalJSONV1.encode(files)
        )
    }

    private func frozenIdentityDigest(for generationRootURL: URL) throws -> String {
        let descriptor = try openOwnedDirectory(at: generationRootURL)
        defer { _ = Darwin.close(descriptor) }
        let directory = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        let names = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: true
        ).sorted()
        var tokens = ["directory|\(directory.device)|\(directory.inode)"]
        for name in names {
            let identity = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: descriptor,
                name: name
            )
            tokens.append(
                "\(name)|\(identity.device)|\(identity.inode)|\(identity.linkCount)"
            )
        }
        return StoreMigrationCanonicalJSONV1.sha256(
            Data(tokens.joined(separator: "\n").utf8)
        )
    }

    private func syntheticPredecessor(excluding generationID: UUID) -> UUID {
        let first = Self.bootstrapPredecessorGenerationID
        if first != generationID { return first }
        return UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    }

    private func decodeCurrentPointer(at url: URL) throws -> CurrentPointerEnvelopeV1 {
        let parentURL = url.deletingLastPathComponent()
        let parent = try openOwnedDirectory(at: parentURL)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: parentURL, descriptor: parent)
        let captured = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
            parent: parent,
            name: url.lastPathComponent
        )
        let value = try CurrentPointerCodecV1.decode(captured.data)
        guard try StoreRestoreGenerationAuthority.regularFileIdentity(
                  parent: parent,
                  name: url.lastPathComponent
              ) == captured.identity else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        return value
    }

    @MainActor
    private func requireCurrentManifest(
        _ pointer: CurrentGenerationPointerV2
    ) throws -> StoreGenerationManifestV1 {
        try pointer.validate()
        guard let generationID = canonicalUUID(from: pointer.generationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let manifest = try store.loadManifest(
            targetGenerationID: generationID,
            expectedDigest: pointer.generationManifestSHA256
        )
        guard manifest.generationID == generationID,
              manifest.storeSchemaRelease == .v2 else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return manifest
    }

    @MainActor
    private func requireCurrentManifest(
        _ pointer: CurrentGenerationPointerV3
    ) throws -> StoreGenerationManifestV1 {
        try pointer.validate()
        guard let generationID = canonicalUUID(from: pointer.generationID) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let manifest = try store.loadManifest(
            targetGenerationID: generationID,
            expectedDigest: pointer.generationManifestSHA256
        )
        let expectedRelease: PersistentSchemaReleaseV1
        switch pointer.storeSchemaVersion {
        case 2: expectedRelease = .v2
        case 3: expectedRelease = .v3
        case 4: expectedRelease = .v4
        case 5: expectedRelease = .v5
        case 6: expectedRelease = .v6
        case 7: expectedRelease = .v7
        case 8: expectedRelease = .v8
        case 9: expectedRelease = .v9
        case 10: expectedRelease = .v10
        case 11: expectedRelease = .v11
        case 12: expectedRelease = .v12
        case 13: expectedRelease = .v13
        case 14: expectedRelease = .v14
        case 15: expectedRelease = .v15
        case 16: expectedRelease = .v16
        case 17: expectedRelease = .v17
        case 18: expectedRelease = .v18
        case 19: expectedRelease = .v19
        case 20: expectedRelease = .v20
        case 21: expectedRelease = .v21
        case 22: expectedRelease = .v22
        case 23: expectedRelease = .v23
        case 24: expectedRelease = .v24
        case 25: expectedRelease = .v25
        case 26: expectedRelease = .v26
        case 27: expectedRelease = .v27
        case 28: expectedRelease = .v28
        case 29: expectedRelease = .v29
        case 30: expectedRelease = .v30
        case 31: expectedRelease = .v31
        case 32: expectedRelease = .v32
        case 33: expectedRelease = .v33
        case 34: expectedRelease = .v34
        case 35: expectedRelease = .v35
        default:
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
        guard manifest.generationID == generationID,
              manifest.storeSchemaRelease == expectedRelease else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return manifest
    }

    @MainActor
    private func enrichCurrentPointer(
        _ pointer: CurrentGenerationPointerV2
    ) throws -> CurrentGenerationPointerV3 {
        let manifest = try requireCurrentManifest(pointer)
        guard let generationID = canonicalUUID(from: pointer.generationID),
              manifest.generationID == generationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let identity = try compatibilityIdentity(for: pointer)
        guard generationID != identity.workspaceID.rawValue,
              generationID != identity.replicaID.rawValue else {
            throw WorkspaceIdentityFailure.roleCollision
        }
        let enriched = try CurrentGenerationPointerV3(
            generationID: generationID,
            generationManifestSHA256: pointer.generationManifestSHA256,
            workspaceID: identity.workspaceID,
            replicaID: identity.replicaID
        )
        try replacePointer(
            name: Self.currentPointerName,
            value: enriched,
            expectedData: try pointer.canonicalData()
        )
        guard case .v3(let published, _) = try decodeCurrentPointer(
                  at: dataRootURL.appendingPathComponent(Self.currentPointerName)
              ), published == enriched else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return published
    }

    private func compatibilityIdentity(
        for pointer: CurrentGenerationPointerV2
    ) throws -> WorkspaceReplicaIdentityV1 {
        let data = try pointer.canonicalData()
        func identifier(_ domain: String) -> UUID {
            var bytes = Array(
                SHA256.hash(data: Data(domain.utf8) + data).prefix(16)
            )
            bytes[6] = (bytes[6] & 0x0f) | 0x50
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }
        return try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(
                rawValue: identifier("field-evidence/v23/workspace/v2-enrichment")
            ),
            replicaID: ReplicaID(
                rawValue: identifier("field-evidence/v23/replica/v2-enrichment")
            )
        )
    }

    @MainActor
    private func makeRestoreCurrentPointer(
        expectedOldID: UUID,
        newID: UUID
    ) throws -> CurrentGenerationPointerV3 {
        guard try currentGenerationID() == expectedOldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let root = installedGenerationURL(id: newID)
        let modelStoreURL = root.appendingPathComponent(Self.modelStoreName)
        let markerMigrationID = try autoreleasepool { () throws -> UUID in
            let container = try makeV53Container(at: modelStoreURL, migrate: false)
            let marker = try requireV53Marker(
                in: container.mainContext,
                expectedMigrationID: nil
            )
            guard let value = marker.migrationID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            return value
        }
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        if let existing = try store.loadManifestIfPresent(
            targetGenerationID: newID
        ) {
            guard existing.manifest.storeSchemaRelease == .v53,
                  existing.manifest.migrationID == markerMigrationID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            try requireRestoreManifestSnapshot(
                existing.manifest,
                expectedOldID: expectedOldID,
                generationID: newID,
                at: root,
                staging: false
            )
            return try restorePointerV3(
                generationID: newID,
                manifestDigest: existing.digest
            )
        }
        let semantic = try semanticExport(
            at: modelStoreURL,
            release: .v46,
            markerMigrationID: markerMigrationID
        )
        try protectGeneration(at: root, staging: false, requireModel: true)
        let manifest = try StoreGenerationManifestV1(
            generationID: newID,
            predecessorGenerationID: expectedOldID,
            migrationID: markerMigrationID,
            storeSchemaRelease: .v46,
            semanticSHA256: StoreMigrationCanonicalJSONV1.sha256(semantic),
            frozenIdentityDigest: try frozenIdentityDigest(for: root),
            files: try generationFileDigests(at: root, durable: true)
        )
        let digest = try store.writeManifest(manifest)
        return try restorePointerV3(generationID: newID, manifestDigest: digest)
    }

    @MainActor
    private func restorePointerV3(
        generationID: UUID,
        manifestDigest: String
    ) throws -> CurrentGenerationPointerV3 {
        let envelope = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        let identity: WorkspaceReplicaIdentityV1
        let history: Set<ReplicaID>
        switch envelope {
        case .v3(let pointer, _):
            identity = try pointer.identity()
            history = try pointer.knownReplicaIdentitySet()
        case .v2(let pointer, _):
            identity = try compatibilityIdentity(for: pointer)
            history = [identity.replicaID]
        case .legacy:
            identity = pointerEnrichmentIdentity
            history = [identity.replicaID]
        }
        return try CurrentGenerationPointerV3(
            generationID: generationID,
            generationManifestSHA256: manifestDigest,
            workspaceID: identity.workspaceID,
            replicaID: identity.replicaID,
            knownReplicaIDs: history,
            storeSchemaVersion: 46
        )
    }

    @MainActor
    private func makeRestoreCurrentPointerV3(
        expectedOldID: UUID,
        newID: UUID,
        identity: WorkspaceReplicaIdentityV1,
        knownReplicaIDs: Set<ReplicaID>,
        preparedGenerationManifestSHA256: String
    ) throws -> CurrentGenerationPointerV3 {
        guard try currentGenerationID() == expectedOldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let manifest = try store.loadManifest(
            targetGenerationID: newID,
            expectedDigest: preparedGenerationManifestSHA256
        )
        guard manifest.storeSchemaRelease == .v46 else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        try requireRestoreManifestSnapshot(
            manifest,
            expectedOldID: expectedOldID,
            generationID: newID,
            at: installedGenerationURL(id: newID),
            staging: false
        )
        return try CurrentGenerationPointerV3(
            generationID: newID,
            generationManifestSHA256: preparedGenerationManifestSHA256,
            workspaceID: identity.workspaceID,
            replicaID: identity.replicaID,
            knownReplicaIDs: knownReplicaIDs,
            storeSchemaVersion: 46
        )
    }

    @MainActor
    private func requireRestoreManifestSnapshot(
        _ manifest: StoreGenerationManifestV1,
        expectedOldID: UUID,
        generationID: UUID,
        at root: URL,
        staging: Bool
    ) throws {
        let modelStoreURL = root.appendingPathComponent(Self.modelStoreName)
        let markerMigrationID = try autoreleasepool { () throws -> UUID in
            let context: ModelContext
            let marker: PersistentSchemaReleaseMarker
            switch manifest.storeSchemaRelease {
            case .v2:
                context = try makeV2Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV2Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v3:
                context = try makeV3Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV3Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v4:
                context = try makeV4Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV4Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v5:
                context = try makeV5Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV5Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v6:
                context = try makeV6Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV6Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v7:
                context = try makeV7Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV7Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v8:
                context = try makeV8Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV8Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v9:
                context = try makeV9Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV9Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v10:
                context = try makeV10Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV10Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v11:
                context = try makeV11Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV11Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v12:
                context = try makeV12Container(at: modelStoreURL, migrate: false).mainContext
                marker = try requireV12Marker(in: context, expectedMigrationID: manifest.migrationID)
            case .v13:
                context = try makeV13Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV13Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v14:
                context = try makeV14Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV14Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v15:
                context = try makeV15Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV15Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v16:
                context = try makeV16Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV16Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v17:
                context = try makeV17Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV17Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v18:
                context = try makeV18Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV18Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v19:
                context = try makeV19Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV19Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v20:
                context = try makeV20Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV20Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v21:
                context = try makeV21Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV21Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v22:
                context = try makeV22Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV22Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v23:
                context = try makeV23Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV23Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v24:
                context = try makeV24Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV24Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v25:
                context = try makeV25Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV25Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v26:
                context = try makeV26Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV26Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v27:
                context = try makeV27Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV27Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v28:
                context = try makeV28Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV28Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v29:
                context = try makeV29Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV29Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v30:
                context = try makeV30Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV30Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v31:
                context = try makeV31Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV31Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v32:
                context = try makeV32Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV32Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v33:
                context = try makeV33Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV33Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v34:
                context = try makeV34Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV34Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v35:
                context = try makeV35Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV35Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v36:
                context = try makeV36Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV36Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v37:
                context = try makeV37Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV37Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v38:
                context = try makeV38Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV38Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v39:
                context = try makeV39Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV39Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v40:
                context = try makeV40Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV40Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v41:
                context = try makeV41Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV41Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v42:
                context = try makeV42Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV42Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v43:
                context = try makeV43Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV43Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v44:
                context = try makeV44Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV44Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v45:
                context = try makeV45Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV45Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v46:
                context = try makeV46Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV46Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v47:
                context = try makeV47Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV47Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v48:
                context = try makeV48Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV48Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v49:
                context = try makeV49Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV49Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v50:
                context = try makeV50Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV50Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v51:
                context = try makeV51Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV51Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v52:
                context = try makeV52Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV52Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v53:
                context = try makeV53Container(at:modelStoreURL,migrate:false).mainContext
                marker = try requireV53Marker(in:context,expectedMigrationID:manifest.migrationID)
            case .v1:
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            guard let value = marker.migrationID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            return value
        }
        guard manifest.generationID == generationID,
              manifest.predecessorGenerationID == expectedOldID,
              manifest.migrationID == markerMigrationID,
              manifest.semanticSHA256 == (try semanticDigest(
                  at: modelStoreURL,
                  release: manifest.storeSchemaRelease
              )),
              manifest.files == (try generationFileDigests(
                  at: root,
                  durable: true
              )),
              manifest.frozenIdentityDigest == (try frozenIdentityDigest(for: root)) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        try protectGeneration(at: root, staging: staging, requireModel: true)
    }

}

@MainActor
final class StoreGenerationSession {
    let generationID: UUID
    let generationRootURL: URL
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let workspaceIdentity: WorkspaceReplicaIdentityV1
    let modelContext: ModelContext
    let generationEpoch: GenerationEpochV1?

    var readerLeaseToken: GenerationLeaseTokenV1? {
        readerLeaseHandle?.token
    }

    private let modelContainer: ModelContainer
    private let readerLeaseHandle: GenerationLeaseHandleV1?
    private let afterSaveReproof: () throws -> Void
    private var didSaveObserver: NSObjectProtocol? = nil
    private var afterSaveFailure: Error? = nil

    fileprivate init(
        generationID: UUID,
        generationRootURL: URL,
        workspaceIdentity: WorkspaceReplicaIdentityV1,
        modelContainer: ModelContainer,
        generationEpoch: GenerationEpochV1? = nil,
        readerLeaseHandle: GenerationLeaseHandleV1? = nil,
        afterSaveReproof: @escaping () throws -> Void
    ) {
        self.generationID = generationID
        self.generationRootURL = generationRootURL
        self.workspaceID = workspaceIdentity.workspaceID
        self.replicaID = workspaceIdentity.replicaID
        self.workspaceIdentity = workspaceIdentity
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.generationEpoch = generationEpoch
        self.readerLeaseHandle = readerLeaseHandle
        self.afterSaveReproof = afterSaveReproof
        let context = self.modelContext
        self.didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAutomaticSaveReproof()
            }
        }
    }

    deinit {
        if let didSaveObserver {
            NotificationCenter.default.removeObserver(didSaveObserver)
        }
    }

    private func handleAutomaticSaveReproof() {
        guard afterSaveFailure == nil else { return }
        do {
            try afterSaveReproof()
        } catch {
            recordAfterSaveFailure(error)
        }
    }

    private func recordAfterSaveFailure(_ error: Error) {
        guard afterSaveFailure == nil else { return }
        afterSaveFailure = error
        modelContext.autosaveEnabled = false
    }

    /// Revalidates the closed generation file set and protection policy after a
    /// successful ModelContext save. Automatic didSave reproof failures are
    /// retained and surfaced here; callers retain ownership of the save.
    func reproofAfterSave() throws {
        if let afterSaveFailure {
            throw afterSaveFailure
        }
        do {
            try afterSaveReproof()
        } catch {
            recordAfterSaveFailure(error)
            throw error
        }
    }
}

/// Descriptor-pinned authority used only by atomic backup restore. It keeps the
/// installed and restore-staging generation parents bound to the same directory
/// identities for the complete restore/recovery operation, so a renamed or
/// replaced ancestor can never redirect a cleanup or installation mutation.
final class StoreRestoreGenerationAuthority {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    fileprivate struct RegularFileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
    }

    fileprivate struct RegularFileRead {
        let data: Data
        let identity: RegularFileIdentity
    }

    private struct RegularFileSnapshot: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
        let type: mode_t
        let byteCount: off_t
    }

    private struct StreamedFileDigest {
        let byteCount: Int
        let sha256: String
        let snapshot: RegularFileSnapshot
    }

    private struct PinnedMigrationSourceFile {
        let name: String
        let descriptor: Int32
        let snapshot: RegularFileSnapshot
        var initialSHA256: String?
    }

    private static let migrationStreamBufferByteCount = 64 * 1024
    private static let maximumControlFileByteCount = 4 * 1024 * 1024

    struct Presence {
        let staging: Bool
        let installed: Bool
    }

    struct Tree: Equatable {
        let directories: Set<String>
        let files: Set<String>
    }

    /// Descriptor-relative, byte-stable snapshot returned by the V1 -> V2
    /// copy-on-write clone.  The source identities are deliberately reduced to
    /// digests before this value leaves the authority; callers never receive a
    /// path-derived authority that could be rebound after a rename.
    struct MigrationCloneResult {
        let files: [StoreGenerationFileDigestV1]
        let sourceTreeDigest: String
        let frozenIdentityDigest: String
    }

    final class InstalledGenerationHandle {
        fileprivate let id: UUID
        fileprivate let descriptor: Int32
        fileprivate let identity: Identity

        fileprivate init(id: UUID, descriptor: Int32, identity: Identity) {
            self.id = id
            self.descriptor = descriptor
            self.identity = identity
        }

        deinit {
            _ = Darwin.close(descriptor)
        }
    }

    private static let dataName = "FieldEvidenceData"
    private static let restoreName = "FieldEvidenceRestore"
    private static let generationsName = "generations"
    private static let importStagingName = "staging"
    private static let pointerMutationLock = NSLock()
    fileprivate static let generationStoreNames: Set<String> = [
        "model.sqlite",
        "model.sqlite-wal",
        "model.sqlite-shm"
    ]

    private let applicationSupportURL: URL
    private let applicationSupportDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let dataDescriptor: Int32
    private let dataIdentity: Identity
    private let installedGenerationsDescriptor: Int32
    private let installedGenerationsIdentity: Identity
    private let restoreDescriptor: Int32
    private let restoreIdentity: Identity
    private let stagingGenerationsDescriptor: Int32
    private let stagingGenerationsIdentity: Identity
    private let importStagingDescriptor: Int32
    private let importStagingIdentity: Identity

    init(
        applicationSupportURL: URL,
        expectedApplicationSupportIdentity: StoreApplicationSupportIdentity? = nil
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else { throw StoreGenerationFailure.dataPointerInvalid }
        let app = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard app >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        var retained = [app]
        var succeeded = false
        defer {
            if !succeeded {
                for descriptor in retained.reversed() { _ = Darwin.close(descriptor) }
            }
        }

        let appIdentity = try Self.identity(app)
        if let expectedApplicationSupportIdentity {
            guard appIdentity.device == expectedApplicationSupportIdentity.device,
                  appIdentity.inode == expectedApplicationSupportIdentity.inode else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        let data = try Self.openDirectory(parent: app, name: Self.dataName)
        retained.append(data)
        let dataIdentity = try Self.identity(data)
        let installed = try Self.openDirectory(
            parent: data,
            name: Self.generationsName
        )
        retained.append(installed)
        let installedIdentity = try Self.identity(installed)
        let restore = try Self.openOrCreateDirectory(
            parent: app,
            name: Self.restoreName
        )
        retained.append(restore)
        let restoreIdentity = try Self.identity(restore)
        let stagingGenerations = try Self.openOrCreateDirectory(
            parent: restore,
            name: Self.generationsName
        )
        retained.append(stagingGenerations)
        let stagingGenerationsIdentity = try Self.identity(stagingGenerations)
        let importStaging = try Self.openOrCreateDirectory(
            parent: restore,
            name: Self.importStagingName
        )
        retained.append(importStaging)
        let importStagingIdentity = try Self.identity(importStaging)

        self.applicationSupportURL = root
        self.applicationSupportDescriptor = app
        self.applicationSupportIdentity = appIdentity
        self.dataDescriptor = data
        self.dataIdentity = dataIdentity
        self.installedGenerationsDescriptor = installed
        self.installedGenerationsIdentity = installedIdentity
        self.restoreDescriptor = restore
        self.restoreIdentity = restoreIdentity
        self.stagingGenerationsDescriptor = stagingGenerations
        self.stagingGenerationsIdentity = stagingGenerationsIdentity
        self.importStagingDescriptor = importStaging
        self.importStagingIdentity = importStagingIdentity
        try protectAuthorityRoots()
        succeeded = true
    }

    deinit {
        _ = Darwin.close(importStagingDescriptor)
        _ = Darwin.close(stagingGenerationsDescriptor)
        _ = Darwin.close(restoreDescriptor)
        _ = Darwin.close(installedGenerationsDescriptor)
        _ = Darwin.close(dataDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    private var dataURL: URL {
        applicationSupportURL.appendingPathComponent(Self.dataName, isDirectory: true)
    }

    private var installedGenerationsURL: URL {
        dataURL.appendingPathComponent(Self.generationsName, isDirectory: true)
    }

    private var restoreURL: URL {
        applicationSupportURL.appendingPathComponent(Self.restoreName, isDirectory: true)
    }

    private var stagingGenerationsURL: URL {
        restoreURL.appendingPathComponent(Self.generationsName, isDirectory: true)
    }

    private var importStagingURL: URL {
        restoreURL.appendingPathComponent(Self.importStagingName, isDirectory: true)
    }

    private func enforce(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        do {
            let root = applicationSupportURL.standardizedFileURL
            let target = url.standardizedFileURL
            let insideRoot = root.path == "/"
                ? target.path.hasPrefix("/")
                : target.path.hasPrefix(root.path + "/")
            guard insideRoot else {
                throw ProtectedFilePolicyError.invalidRelativePath
            }
            let relativePath = String(target.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: relativePath,
                within: root,
                authorityCheck: {
                    try self.verify()
                    try authorityCheck()
                }
            )
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch let error as ProtectedFilePolicyError
            where error == .protectedDataUnavailable {
            throw error
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func enforceGenerationFile(
        descriptor: Int32,
        root: URL,
        name: String,
        kind: OwnedFileKindV1
    ) throws {
        try Self.requireSafeBasename(name)
        let generationIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        let fileDescriptor = Darwin.openat(
            descriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard fileDescriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(fileDescriptor) }
        let fileIdentity = try Self.regularFileIdentity(descriptor: fileDescriptor)
        let url = root.appendingPathComponent(name, isDirectory: false)
        try enforce(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: descriptor
                      ) == generationIdentity,
                      try Self.directoryIdentity(at: root) == generationIdentity,
                      try Self.regularFileIdentity(descriptor: fileDescriptor)
                          == fileIdentity,
                      try Self.regularFileIdentity(at: url) == fileIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )
    }

    private func protectAuthorityRoots() throws {
        try enforce(.durableDirectory, at: dataURL)
        try enforce(.durableDirectory, at: installedGenerationsURL)
        try enforce(.stagingDirectory, at: restoreURL)
        try enforce(.stagingDirectory, at: stagingGenerationsURL)
        try enforce(.stagingDirectory, at: importStagingURL)
    }

    private func protectKnownStoreFiles(
        parent: Int32,
        id: UUID,
        root: URL,
        rootKind: OwnedFileKindV1,
        requireModel: Bool = false
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }

        let generationIdentity = try Self.identity(descriptor)
        try enforce(
            rootKind,
            at: root,
            authorityCheck: {
                guard try Self.identity(descriptor) == generationIdentity,
                      try Self.directoryIdentity(at: root) == generationIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )

        let before = try Self.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )

        let modelKind: OwnedFileKindV1 = rootKind == .restoreStaging
            ? .stagingFile
            : .database
        let walKind: OwnedFileKindV1 = rootKind == .restoreStaging
            ? .stagingFile
            : .databaseWAL
        let shmKind: OwnedFileKindV1 = rootKind == .restoreStaging
            ? .stagingFile
            : .databaseSHM

        for name in before {
            let kind: OwnedFileKindV1
            switch name {
            case "model.sqlite": kind = modelKind
            case "model.sqlite-wal": kind = walKind
            case "model.sqlite-shm": kind = shmKind
            default: throw StoreGenerationFailure.dataPointerInvalid
            }
            try enforceGenerationFile(
                descriptor: descriptor,
                root: root,
                name: name,
                kind: kind
            )
        }
        let after = try Self.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )
        guard before == after else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func protectStagingGeneration(
        id: UUID,
        requireModel: Bool = false
    ) throws {
        try requireStagingGeneration(id: id)
        let root = stagingGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        try protectKnownStoreFiles(
            parent: stagingGenerationsDescriptor,
            id: id,
            root: root,
            rootKind: .restoreStaging,
            requireModel: requireModel
        )
        try requireStagingGeneration(id: id)
    }

    func protectInstalledGeneration(
        id: UUID,
        requireModel: Bool = false
    ) throws {
        try requireInstalledGeneration(id: id)
        let root = installedGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        try protectKnownStoreFiles(
            parent: installedGenerationsDescriptor,
            id: id,
            root: root,
            rootKind: .durableDirectory,
            requireModel: requireModel
        )
        try requireInstalledGeneration(id: id)
    }

    func protectStagingFile(
        id: UUID,
        name: String,
        kind: OwnedFileKindV1,
        ifPresent: Bool = false
    ) throws {
        try Self.requireSafeBasename(name)
        try requireStagingGeneration(id: id)
        let root = stagingGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        let descriptor = Darwin.openat(
            stagingGenerationsDescriptor,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        if ifPresent, try !Self.itemExists(parent: descriptor, name: name) { return }
        try enforceGenerationFile(
            descriptor: descriptor,
            root: root,
            name: name,
            kind: kind
        )
        try requireStagingGeneration(id: id)
    }

    func protectInstalledFile(
        id: UUID,
        name: String,
        kind: OwnedFileKindV1,
        ifPresent: Bool = false
    ) throws {
        try Self.requireSafeBasename(name)
        try requireInstalledGeneration(id: id)
        let root = installedGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        let descriptor = Darwin.openat(
            installedGenerationsDescriptor,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        if ifPresent, try !Self.itemExists(parent: descriptor, name: name) { return }
        try enforceGenerationFile(
            descriptor: descriptor,
            root: root,
            name: name,
            kind: kind
        )
        try requireInstalledGeneration(id: id)
    }

    fileprivate static func requireSafeBasename(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\") else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    fileprivate static func requireExactGenerationContents(
        parent: Int32,
        requireModel: Bool
    ) throws {
        _ = try exactGenerationEntries(parent: parent, requireModel: requireModel)
    }

    fileprivate static func exactGenerationEntries(
        parent: Int32,
        requireModel: Bool
    ) throws -> Set<String> {
        let entries = Set(try Self.names(in: parent))
        guard entries.isSubset(of: Self.generationStoreNames) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let hasModel = entries.contains("model.sqlite")
        guard !requireModel || hasModel else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard hasModel ||
                (!entries.contains("model.sqlite-wal") &&
                 !entries.contains("model.sqlite-shm")) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        for name in entries {
            var info = stat()
            guard Darwin.fstatat(
                parent,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_nlink == 1 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        return entries
    }

    func verify() throws {
        try Self.require(applicationSupportDescriptor, applicationSupportIdentity)
        try Self.require(dataDescriptor, dataIdentity)
        try Self.require(installedGenerationsDescriptor, installedGenerationsIdentity)
        try Self.require(restoreDescriptor, restoreIdentity)
        try Self.require(stagingGenerationsDescriptor, stagingGenerationsIdentity)
        try Self.require(importStagingDescriptor, importStagingIdentity)

        let app = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard app >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(app) }
        guard try Self.identity(app) == applicationSupportIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let data = try Self.openDirectory(parent: app, name: Self.dataName)
        defer { _ = Darwin.close(data) }
        guard try Self.identity(data) == dataIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let installed = try Self.openDirectory(
            parent: data,
            name: Self.generationsName
        )
        defer { _ = Darwin.close(installed) }
        guard try Self.identity(installed) == installedGenerationsIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let restore = try Self.openDirectory(parent: app, name: Self.restoreName)
        defer { _ = Darwin.close(restore) }
        guard try Self.identity(restore) == restoreIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let stagingGenerations = try Self.openDirectory(
            parent: restore,
            name: Self.generationsName
        )
        defer { _ = Darwin.close(stagingGenerations) }
        guard try Self.identity(stagingGenerations) == stagingGenerationsIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let importStaging = try Self.openDirectory(
            parent: restore,
            name: Self.importStagingName
        )
        defer { _ = Darwin.close(importStaging) }
        guard try Self.identity(importStaging) == importStagingIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func requireNoEraseAuthority() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        let expected = try Self.identity(descriptor)
        guard try Self.names(in: descriptor).isEmpty else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reopened = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopened >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(reopened) }
        guard try Self.identity(reopened) == expected else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
    }

    func requireNoRestoreJournal() throws {
        try verify()
        guard try !Self.itemExists(
            parent: restoreDescriptor,
            name: "restore.json"
        ),
              try !Self.itemExists(
                parent: restoreDescriptor,
                name: ".restore.json.next"
              ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
    }

    func presence(id: UUID) throws -> Presence {
        try verify()
        let name = Self.canonical(id)
        return Presence(
            staging: try Self.directoryPresence(
                parent: stagingGenerationsDescriptor,
                name: name
            ),
            installed: try Self.directoryPresence(
                parent: installedGenerationsDescriptor,
                name: name
            )
        )
    }

    func currentGenerationID() throws -> UUID {
        try verify()
        try reconcileRestorePointerTemporary(name: "current.json")
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent("current.json", isDirectory: false)
        )
        let captured = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: "current.json"
        )
        let envelope = try CurrentPointerCodecV1.decode(captured.data)
        guard try Self.regularFileIdentity(
                  parent: dataDescriptor,
                  name: "current.json"
              ) == captured.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch envelope {
        case .legacy(let value, _):
            guard let id = UUID(uuidString: value.generationID),
                  Self.canonical(id) == value.generationID else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return id
        case .v2(let value, _):
            guard let id = UUID(uuidString: value.generationID) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return id
        case .v3(let value, _):
            guard let id = UUID(uuidString: value.generationID) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return id
        }
    }

    func retiredGenerationIDs() throws -> [UUID] {
        try verify()
        try reconcileRestorePointerTemporary(name: "retired.json")
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent("retired.json", isDirectory: false)
        )
        let value: RetiredPointerV1 = try Self.decodeCanonicalPointer(
            parent: dataDescriptor,
            name: "retired.json"
        )
        try StorePointerSchemaRegistry.requireRetired(value.schemaVersion)
        guard value.generationIDs == value.generationIDs.sorted(),
              Set(value.generationIDs).count == value.generationIDs.count else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let ids = value.generationIDs.compactMap(UUID.init(uuidString:))
        guard ids.count == value.generationIDs.count,
              zip(ids, value.generationIDs).allSatisfy({
                  Self.canonical($0.0) == $0.1
              }) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return ids
    }

    func switchCurrentGeneration(expected oldID: UUID, to newID: UUID) throws {
        try verify()
        guard oldID != newID,
              try currentGenerationID() == oldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(oldID)
        )
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(newID)
        )
        let captured = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: "current.json"
        )
        guard case .legacy = try CurrentPointerCodecV1.decode(captured.data) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try replacePointer(
            name: "current.json",
            value: CurrentPointerV1(
                generationID: Self.canonical(newID),
                schemaVersion: StorePointerSchemaRegistry.legacyCurrentVersion
            )
        )
        guard try currentGenerationID() == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func switchCurrentGeneration(
        expected oldID: UUID,
        to newID: UUID,
        pointer: CurrentGenerationPointerV2
    ) throws {
        try pointer.validate()
        guard pointer.generationID == Self.canonical(newID),
              oldID != newID,
              try currentGenerationID() == oldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(oldID)
        )
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(newID)
        )
        let captured = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: "current.json"
        )
        _ = try CurrentPointerCodecV1.decode(captured.data)
        try replacePointer(name: "current.json", value: pointer)
        guard try currentGenerationID() == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func switchCurrentGeneration(
        expected oldID: UUID,
        to newID: UUID,
        pointer: CurrentGenerationPointerV3,
        expectedCurrentPointer: CurrentGenerationPointerV3
    ) throws {
        try pointer.validate()
        guard pointer.generationID == Self.canonical(newID),
              oldID != newID,
              try currentGenerationID() == oldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(oldID)
        )
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(newID)
        )
        let captured = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: "current.json"
        )
        _ = try CurrentPointerCodecV1.decode(captured.data)
        if captured.data != (try expectedCurrentPointer.canonicalData()) {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try replacePointer(
            name: "current.json",
            value: pointer,
            expectedData: try expectedCurrentPointer.canonicalData()
        )
        guard try currentGenerationID() == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retireGeneration(oldID: UUID, currentID: UUID) throws {
        try verify()
        guard oldID != currentID,
              try currentGenerationID() == currentID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(oldID)
        )
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(currentID)
        )
        let retired = try retiredGenerationIDs()
        guard !retired.contains(currentID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let values = Array(Set(retired + [oldID])).sorted {
            Self.canonical($0) < Self.canonical($1)
        }
        try replacePointer(
            name: "retired.json",
            value: RetiredPointerV1(
                generationIDs: values.map(Self.canonical),
                schemaVersion: StorePointerSchemaRegistry.retiredVersion
            )
        )
        guard try retiredGenerationIDs() == values else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func createStagingGeneration(id: UUID) throws {
        try verify()
        let name = Self.canonical(id)
        guard try !Self.itemExists(parent: stagingGenerationsDescriptor, name: name),
              try !Self.itemExists(parent: installedGenerationsDescriptor, name: name) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard Darwin.mkdirat(
            stagingGenerationsDescriptor,
            name,
            mode_t(0o700)
        ) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(stagingGenerationsDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try verify()
        guard try Self.directoryPresence(
            parent: stagingGenerationsDescriptor,
            name: name
        ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try enforce(
            .restoreStaging,
            at: stagingGenerationsURL.appendingPathComponent(name, isDirectory: true)
        )
    }

    func createInstalledGeneration(id: UUID) throws -> InstalledGenerationHandle {
        try verify()
        let name = Self.canonical(id)
        guard try !Self.itemExists(parent: stagingGenerationsDescriptor, name: name),
              try !Self.itemExists(parent: installedGenerationsDescriptor, name: name),
              Darwin.mkdirat(
                  installedGenerationsDescriptor,
                  name,
                  mode_t(0o700)
              ) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let descriptor = Darwin.openat(
            installedGenerationsDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            _ = Darwin.unlinkat(
                installedGenerationsDescriptor,
                name,
                AT_REMOVEDIR
            )
            _ = Darwin.fsync(installedGenerationsDescriptor)
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var createdIdentity: Identity?
        do {
            let identity = try Self.identity(descriptor)
            createdIdentity = identity
            guard Darwin.fsync(installedGenerationsDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
            try Self.require(descriptor, identity)
            guard try Self.requiredDirectoryIdentity(
                parent: installedGenerationsDescriptor,
                name: name
            ) == identity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectInstalledGeneration(id: id)
            return InstalledGenerationHandle(
                id: id,
                descriptor: descriptor,
                identity: identity
            )
        } catch {
            if let createdIdentity,
               let currentIdentity = try? Self.requiredDirectoryIdentity(
                   parent: installedGenerationsDescriptor,
                   name: name
               ), currentIdentity == createdIdentity {
                _ = Darwin.unlinkat(
                    installedGenerationsDescriptor,
                    name,
                    AT_REMOVEDIR
                )
                _ = Darwin.fsync(installedGenerationsDescriptor)
            }
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    func modelStoreURL(
        for handle: InstalledGenerationHandle,
        name: String
    ) throws -> URL {
        try Self.requireSafeBasename(name)
        try requireInstalledGeneration(handle)
        let root = try Self.currentURL(for: handle.descriptor)
        guard root.isFileURL,
              root.lastPathComponent == Self.canonical(handle.id) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reopened = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopened >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(reopened) }
        guard try Self.identity(reopened) == handle.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try requireInstalledGeneration(handle)
        return root.appendingPathComponent(name, isDirectory: false)
    }

    func requireRegularFile(
        named name: String,
        in handle: InstalledGenerationHandle
    ) throws {
        try Self.requireSafeBasename(name)
        try requireInstalledGeneration(handle)
        let descriptor = Darwin.openat(
            handle.descriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Darwin.fsync(descriptor) == 0,
              Darwin.fsync(handle.descriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let before = try Self.exactGenerationEntries(
            parent: handle.descriptor,
            requireModel: true
        )
        guard before.contains(name) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        if name == "model.sqlite" {
            let root = try Self.currentURL(for: handle.descriptor)
            for entry in before {
                let kind: OwnedFileKindV1
                switch entry {
                case "model.sqlite": kind = .database
                case "model.sqlite-wal": kind = .databaseWAL
                case "model.sqlite-shm": kind = .databaseSHM
                default: throw StoreGenerationFailure.dataPointerInvalid
                }
                try enforceGenerationFile(
                    descriptor: handle.descriptor,
                    root: root,
                    name: entry,
                    kind: kind
                )
            }
        }
        let after = try Self.exactGenerationEntries(
            parent: handle.descriptor,
            requireModel: true
        )
        guard before == after else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try requireInstalledGeneration(handle)
    }

    func requireInstalledGeneration(
        _ handle: InstalledGenerationHandle
    ) throws {
        try verify()
        try Self.require(handle.descriptor, handle.identity)
        guard try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(handle.id)
        ) == handle.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func removeCreatedInstalledGeneration(
        _ handle: InstalledGenerationHandle
    ) throws {
        try Self.require(handle.descriptor, handle.identity)
        let currentURL = try Self.currentURL(for: handle.descriptor)
        let parentURL = currentURL.deletingLastPathComponent()
        let parent = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parent >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(parent) }
        guard try Self.identity(parent) == installedGenerationsIdentity,
              try Self.requiredDirectoryIdentity(
                  parent: parent,
                  name: currentURL.lastPathComponent
              ) == handle.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try Self.removeContents(of: handle.descriptor)
        guard try Self.requiredDirectoryIdentity(
            parent: parent,
            name: currentURL.lastPathComponent
        ) == handle.identity,
              Darwin.unlinkat(
                  parent,
                  currentURL.lastPathComponent,
                  AT_REMOVEDIR
              ) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func installStagingGeneration(id: UUID) throws {
        try verify()
        let name = Self.canonical(id)
        try protectStagingGeneration(id: id, requireModel: true)
        let sourceIdentity = try Self.requiredDirectoryIdentity(
            parent: stagingGenerationsDescriptor,
            name: name
        )
        guard try !Self.itemExists(parent: installedGenerationsDescriptor, name: name),
              Darwin.renameatx_np(
                  stagingGenerationsDescriptor,
                  name,
                  installedGenerationsDescriptor,
                  name,
                  UInt32(RENAME_EXCL)
              ) == 0,
              Darwin.fsync(stagingGenerationsDescriptor) == 0,
              Darwin.fsync(installedGenerationsDescriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
        guard try !Self.itemExists(parent: stagingGenerationsDescriptor, name: name),
              try Self.requiredDirectoryIdentity(
                  parent: installedGenerationsDescriptor,
                  name: name
              ) == sourceIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protectInstalledGeneration(id: id, requireModel: true)
    }

    /// Clones the exact SQLite file set from an installed generation into an
    /// already-created restore staging generation.  Every source file is read
    /// through a retained parent descriptor, reread after the clone, and
    /// compared by both bytes and inode identity.  This is intentionally
    /// separate from the restore pointer swap: migration publication cannot
    /// acquire the legacy restore rollback semantics by accident.
    func snapshotInstalledGeneration(
        id: UUID
    ) throws -> MigrationCloneResult {
        try verify()
        try requireInstalledGeneration(id: id)
        let descriptor = Darwin.openat(
            installedGenerationsDescriptor,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
        }
        defer { _ = Darwin.close(descriptor) }
        let directory = try Self.identity(descriptor)
        let names = try Self.exactGenerationEntries(
            parent: descriptor,
            requireModel: true
        ).sorted()
        var files = [StoreGenerationFileDigestV1]()
        var tokens = ["source-directory|\(directory.device)|\(directory.inode)"]
        var pinnedSourceFiles = [PinnedMigrationSourceFile]()
        defer {
            pinnedSourceFiles.forEach { _ = Darwin.close($0.descriptor) }
        }
        for name in names {
            let sourceDescriptor = Darwin.openat(
                descriptor,
                name,
                O_RDONLY | O_NOFOLLOW
            )
            guard sourceDescriptor >= 0 else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
            }
            let sourceSnapshot: RegularFileSnapshot
            let captured: StreamedFileDigest
            do {
                sourceSnapshot = try Self.regularFileSnapshot(
                    descriptor: sourceDescriptor,
                    mismatchReason: .sourceMismatch
                )
                captured = try Self.streamedDigest(
                    descriptor: sourceDescriptor,
                    expectedSnapshot: sourceSnapshot,
                    mismatchReason: .sourceMismatch
                )
            } catch {
                _ = Darwin.close(sourceDescriptor)
                throw error
            }
            pinnedSourceFiles.append(
                PinnedMigrationSourceFile(
                    name: name,
                    descriptor: sourceDescriptor,
                    snapshot: sourceSnapshot,
                    initialSHA256: captured.sha256
                )
            )
            let kind: OwnedFileKindV1
            switch name {
            case "model.sqlite": kind = .database
            case "model.sqlite-wal": kind = .databaseWAL
            case "model.sqlite-shm": kind = .databaseSHM
            default: throw StoreMigrationFailure.invalidPath
            }
            let file = try StoreGenerationFileDigestV1(
                relativePath: name,
                byteCount: captured.byteCount,
                sha256: captured.sha256,
                kind: kind
            )
            files.append(file)
            tokens.append(
                "\(name)|\(captured.snapshot.device)|\(captured.snapshot.inode)|\(captured.snapshot.linkCount)|\(file.sha256)"
            )
        }
        guard try Self.exactGenerationEntries(parent: descriptor, requireModel: true)
                == Set(names),
              try Self.identity(descriptor) == directory,
              try Self.requiredDirectoryIdentity(
                  parent: installedGenerationsDescriptor,
                  name: Self.canonical(id)
              ) == directory else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        for pinned in pinnedSourceFiles {
            guard let initialSHA256 = pinned.initialSHA256 else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            let reproof = try Self.streamedDigest(
                descriptor: pinned.descriptor,
                expectedSnapshot: pinned.snapshot,
                mismatchReason: .sourceMismatch
            )
            guard reproof.sha256 == initialSHA256,
                  try Self.namedRegularFileSnapshot(
                      parent: descriptor,
                      name: pinned.name,
                      mismatchReason: .sourceMismatch
                  ) == pinned.snapshot else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
        }
        guard try Self.exactGenerationEntries(parent: descriptor, requireModel: true)
                == Set(names),
              try Self.identity(descriptor) == directory,
              try Self.requiredDirectoryIdentity(
                  parent: installedGenerationsDescriptor,
                  name: Self.canonical(id)
              ) == directory else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        let treeData = try StoreMigrationCanonicalJSONV1.encode(files)
        let identityData = Data(tokens.sorted().joined(separator: "\n").utf8)
        return MigrationCloneResult(
            files: files,
            sourceTreeDigest: StoreMigrationCanonicalJSONV1.sha256(treeData),
            frozenIdentityDigest: StoreMigrationCanonicalJSONV1.sha256(identityData)
        )
    }

    func cloneInstalledGeneration(
        sourceID: UUID,
        toStagingGeneration targetID: UUID
    ) throws -> MigrationCloneResult {
        try verify()
        try requireInstalledGeneration(id: sourceID)
        try requireStagingGeneration(id: targetID)

        let sourceName = Self.canonical(sourceID)
        let targetName = Self.canonical(targetID)
        let source = Darwin.openat(
            installedGenerationsDescriptor,
            sourceName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard source >= 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
        }
        let target = Darwin.openat(
            stagingGenerationsDescriptor,
            targetName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard target >= 0 else {
            _ = Darwin.close(source)
            throw StoreMigrationFailure.maintenanceRequired(.targetUnavailable)
        }
        defer {
            _ = Darwin.close(target)
            _ = Darwin.close(source)
        }

        let sourceIdentity = try Self.identity(source)
        let targetIdentity = try Self.identity(target)
        guard try Self.exactGenerationEntries(parent: target, requireModel: false).isEmpty else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let sourceNames = try Self.exactGenerationEntries(parent: source, requireModel: true).sorted()
        var fileDigests = [StoreGenerationFileDigestV1]()
        var identityTokens = [
            "source-directory|\(sourceIdentity.device)|\(sourceIdentity.inode)"
        ]
        var pinnedSourceFiles = [PinnedMigrationSourceFile]()
        defer {
            pinnedSourceFiles.forEach { _ = Darwin.close($0.descriptor) }
        }

        for name in sourceNames {
            let sourceDescriptor = Darwin.openat(
                source,
                name,
                O_RDONLY | O_NOFOLLOW
            )
            guard sourceDescriptor >= 0 else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
            }
            let sourceSnapshot: RegularFileSnapshot
            do {
                sourceSnapshot = try Self.regularFileSnapshot(
                    descriptor: sourceDescriptor,
                    mismatchReason: .sourceMismatch
                )
            } catch {
                _ = Darwin.close(sourceDescriptor)
                throw error
            }
            pinnedSourceFiles.append(
                PinnedMigrationSourceFile(
                    name: name,
                    descriptor: sourceDescriptor,
                    snapshot: sourceSnapshot,
                    initialSHA256: nil
                )
            )
            let kind: OwnedFileKindV1
            switch name {
            case "model.sqlite": kind = .database
            case "model.sqlite-wal": kind = .databaseWAL
            case "model.sqlite-shm": kind = .databaseSHM
            default: throw StoreMigrationFailure.invalidPath
            }
            let copied = try createProtectedStagingFile(
                targetID: targetID,
                parent: target,
                name: name,
                sourceDescriptor: sourceDescriptor,
                sourceSnapshot: sourceSnapshot
            )
            pinnedSourceFiles[pinnedSourceFiles.count - 1].initialSHA256 =
                copied.sha256
            let digest = try StoreGenerationFileDigestV1(
                relativePath: name,
                byteCount: copied.byteCount,
                sha256: copied.sha256,
                kind: kind
            )
            fileDigests.append(digest)
            identityTokens.append(
                "\(name)|\(sourceSnapshot.device)|\(sourceSnapshot.inode)|\(sourceSnapshot.linkCount)|\(digest.sha256)"
            )
        }

        guard try Self.exactGenerationEntries(parent: target, requireModel: true)
            == Set(sourceNames) else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        guard try Self.identity(target) == targetIdentity,
              try Self.requiredDirectoryIdentity(
                  parent: stagingGenerationsDescriptor,
                  name: targetName
              ) == targetIdentity else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        guard Darwin.fsync(target) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(stagingGenerationsDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try protectStagingGeneration(id: targetID, requireModel: true)
        try verify()
        guard try Self.exactGenerationEntries(parent: source, requireModel: true)
                == Set(sourceNames),
              try Self.identity(source) == sourceIdentity,
              try Self.requiredDirectoryIdentity(
                  parent: installedGenerationsDescriptor,
                  name: sourceName
              ) == sourceIdentity else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        for pinned in pinnedSourceFiles {
            guard let initialSHA256 = pinned.initialSHA256 else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            let reproof = try Self.streamedDigest(
                descriptor: pinned.descriptor,
                expectedSnapshot: pinned.snapshot,
                mismatchReason: .sourceMismatch
            )
            guard reproof.sha256 == initialSHA256,
                  try Self.namedRegularFileSnapshot(
                      parent: source,
                      name: pinned.name,
                      mismatchReason: .sourceMismatch
                  ) == pinned.snapshot else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
        }
        guard try Self.exactGenerationEntries(parent: source, requireModel: true)
                == Set(sourceNames),
              try Self.identity(source) == sourceIdentity,
              try Self.requiredDirectoryIdentity(
                  parent: installedGenerationsDescriptor,
                  name: sourceName
              ) == sourceIdentity else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        let identityData = Data(identityTokens.sorted().joined(separator: "\n").utf8)
        let treeData = try StoreMigrationCanonicalJSONV1.encode(fileDigests)
        return MigrationCloneResult(
            files: fileDigests,
            sourceTreeDigest: StoreMigrationCanonicalJSONV1.sha256(treeData),
            frozenIdentityDigest: StoreMigrationCanonicalJSONV1.sha256(identityData)
        )
    }

    private func createProtectedStagingFile(
        targetID: UUID,
        parent: Int32,
        name: String,
        sourceDescriptor: Int32,
        sourceSnapshot: RegularFileSnapshot
    ) throws -> StreamedFileDigest {
        try Self.requireSafeBasename(name)
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        let createdSnapshot = try Self.regularFileSnapshot(
            descriptor: descriptor,
            mismatchReason: .targetMismatch
        )
        guard createdSnapshot.byteCount == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        var removeCreated = true
        defer {
            if removeCreated,
               let namedSnapshot = try? Self.namedRegularFileSnapshot(
                   parent: parent,
                   name: name,
                   mismatchReason: .targetMismatch
               ),
               namedSnapshot.device == createdSnapshot.device,
               namedSnapshot.inode == createdSnapshot.inode {
                _ = Darwin.unlinkat(parent, name, 0)
                _ = Darwin.fsync(parent)
            }
        }
        let root = stagingGenerationsURL.appendingPathComponent(
            Self.canonical(targetID),
            isDirectory: true
        )
        try enforceGenerationFile(
            descriptor: parent,
            root: root,
            name: name,
            kind: .stagingFile
        )
        guard Darwin.lseek(sourceDescriptor, 0, SEEK_SET) == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
        }
        var sourceHasher = SHA256()
        var copiedByteCount = 0
        var buffer = [UInt8](
            repeating: 0,
            count: Self.migrationStreamBufferByteCount
        )
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(sourceDescriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
            }
            let (nextCount, overflow) = copiedByteCount.addingReportingOverflow(count)
            guard !overflow, off_t(nextCount) <= sourceSnapshot.byteCount else {
                throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
            }
            copiedByteCount = nextCount
            let chunk = Data(buffer.prefix(count))
            sourceHasher.update(data: chunk)
            try chunk.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(
                        descriptor,
                        raw.baseAddress?.advanced(by: offset),
                        raw.count - offset
                    )
                    if written > 0 {
                        offset += written
                    } else if written < 0, errno == EINTR {
                        continue
                    } else {
                        throw NSError(
                            domain: NSPOSIXErrorDomain,
                            code: Int(errno)
                        )
                    }
                }
            }
        }
        guard copiedByteCount == Int(sourceSnapshot.byteCount),
              try Self.regularFileSnapshot(
                  descriptor: sourceDescriptor,
                  mismatchReason: .sourceMismatch
              ) == sourceSnapshot else {
            throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch)
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(parent) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let targetSnapshot = try Self.regularFileSnapshot(
            descriptor: descriptor,
            mismatchReason: .targetMismatch
        )
        guard targetSnapshot.device == createdSnapshot.device,
              targetSnapshot.inode == createdSnapshot.inode,
              targetSnapshot.linkCount == 1,
              targetSnapshot.type == S_IFREG,
              targetSnapshot.byteCount == off_t(copiedByteCount),
              try Self.namedRegularFileSnapshot(
                  parent: parent,
                  name: name,
                  mismatchReason: .targetMismatch
              ) == targetSnapshot else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let targetDigest = try Self.streamedDigest(
            descriptor: descriptor,
            expectedSnapshot: targetSnapshot,
            mismatchReason: .targetMismatch
        )
        let sourceDigest = Self.hexDigest(sourceHasher.finalize())
        guard targetDigest.byteCount == copiedByteCount,
              targetDigest.sha256 == sourceDigest,
              targetDigest.snapshot == targetSnapshot else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        try enforceGenerationFile(
            descriptor: parent,
            root: root,
            name: name,
            kind: .stagingFile
        )
        guard try Self.regularFileSnapshot(
                  descriptor: descriptor,
                  mismatchReason: .targetMismatch
              ) == targetSnapshot,
              try Self.namedRegularFileSnapshot(
                  parent: parent,
                  name: name,
                  mismatchReason: .targetMismatch
              ) == targetSnapshot else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        removeCreated = false
        return StreamedFileDigest(
            byteCount: copiedByteCount,
            sha256: sourceDigest,
            snapshot: sourceSnapshot
        )
    }

    func requireStagingGeneration(id: UUID) throws {
        try verify()
        _ = try Self.requiredDirectoryIdentity(
            parent: stagingGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func requireInstalledGeneration(id: UUID) throws {
        try verify()
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func stagingTree(id: UUID) throws -> Tree {
        try tree(parent: stagingGenerationsDescriptor, id: id)
    }

    func installedTree(id: UUID) throws -> Tree {
        try tree(parent: installedGenerationsDescriptor, id: id)
    }

    func removeStagingGeneration(id: UUID) throws {
        try removeDirectory(
            parent: stagingGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func removeInstalledGeneration(id: UUID) throws {
        try removeDirectory(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func replaceRetiredGenerationIDs(
        expected: [UUID],
        with replacement: [UUID],
        currentID: UUID
    ) throws {
        try verify()
        guard try currentGenerationID() == currentID,
              try retiredGenerationIDs() == expected,
              !replacement.contains(currentID),
              Set(replacement).count == replacement.count,
              replacement == replacement.sorted(by: Self.idOrder) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try replacePointer(
            name: "retired.json",
            value: RetiredPointerV1(
                generationIDs: replacement.map(Self.canonical),
                schemaVersion: StorePointerSchemaRegistry.retiredVersion
            )
        )
        guard try retiredGenerationIDs() == replacement else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func restoreGenerationNames() throws -> [String] {
        try verify()
        return try Self.names(in: stagingGenerationsDescriptor)
    }

    func installedGenerationNames() throws -> [String] {
        try verify()
        return try Self.names(in: installedGenerationsDescriptor)
    }

    func importStagingNames() throws -> [String] {
        try verify()
        return try Self.names(in: importStagingDescriptor)
    }

    func removeImportStagingPackage(name: String) throws {
        try Self.requireSafeBasename(name)
        try removeDirectory(parent: importStagingDescriptor, name: name)
    }

    private func reconcileRestorePointerTemporary(name: String) throws {
        let temporary = ".\(name).restore-next"
        guard try Self.itemExists(
            parent: dataDescriptor,
            name: temporary
        ) else {
            return
        }

        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        guard try Self.itemExists(
            parent: dataDescriptor,
            name: temporary
        ) else {
            return
        }
        try verify()
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent(name, isDirectory: false)
        )
        try enforce(
            .generationPointerTemporary,
            at: dataURL.appendingPathComponent(temporary, isDirectory: false)
        )
        let current = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: name
        )
        let candidate = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: temporary
        )
        switch name {
        case "current.json":
            _ = try CurrentPointerCodecV1.decode(current.data)
            _ = try CurrentPointerCodecV1.decode(candidate.data)
        case "retired.json":
            let currentValue = try JSONDecoder().decode(
                RetiredPointerV1.self,
                from: current.data
            )
            let candidateValue = try JSONDecoder().decode(
                RetiredPointerV1.self,
                from: candidate.data
            )
            guard try Self.canonicalData(currentValue) == current.data,
                  try Self.canonicalData(candidateValue) == candidate.data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try StorePointerSchemaRegistry.requireRetired(
                currentValue.schemaVersion
            )
            try StorePointerSchemaRegistry.requireRetired(
                candidateValue.schemaVersion
            )
        default:
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard current.identity.linkCount == 1,
              candidate.identity.linkCount == 1,
              try Self.regularFileIdentity(
                  parent: dataDescriptor,
                  name: name
              ) == current.identity,
              try Self.regularFileIdentity(
                  parent: dataDescriptor,
                  name: temporary
              ) == candidate.identity,
              Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
              Darwin.fsync(dataDescriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent(name, isDirectory: false)
        )
    }

    private func replacePointer<Value: Encodable>(
        name: String,
        value: Value,
        expectedData requiredExpectedData: Data? = nil
    ) throws {
        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        try verify()
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent(name, isDirectory: false)
        )
        let expectedRead = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: name
        )
        let expectedIdentity = expectedRead.identity
        let expected = expectedRead.data
        if let requiredExpectedData,
           expected != requiredExpectedData {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let replacement = try Self.canonicalData(value)
        let temporary = ".\(name).restore-next"
        if try Self.itemExists(parent: dataDescriptor, name: temporary) {
            try enforce(
                .generationPointerTemporary,
                at: dataURL.appendingPathComponent(temporary, isDirectory: false)
            )
            let existingTemporary = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: temporary
            )
            let existingCurrent = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            guard existingTemporary.data == replacement,
                  existingTemporary.identity.linkCount == 1,
                  existingCurrent.data == expected,
                  existingCurrent.identity == expectedIdentity,
                  Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
        }
        try Self.createRegularFile(
            parent: dataDescriptor,
            name: temporary,
            data: replacement
        )
        try enforce(
            .generationPointerTemporary,
            at: dataURL.appendingPathComponent(temporary, isDirectory: false)
        )
        let replacementIdentity = try Self.regularFileIdentity(
            parent: dataDescriptor,
            name: temporary
        )
        var published = false
        let publishedIdentity = replacementIdentity
        do {
            try verify()
            let currentBeforeSwap = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            guard currentBeforeSwap.identity == expectedIdentity,
                  currentBeforeSwap.data == expected,
                  Darwin.renameatx_np(
                      dataDescriptor,
                      temporary,
                      dataDescriptor,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            published = true
            guard Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
            try enforce(
                .generationPointer,
                at: dataURL.appendingPathComponent(name, isDirectory: false)
            )
            let currentAfterSwap = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            let oldTemporary = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: temporary
            )
            guard currentAfterSwap.data == replacement,
                  currentAfterSwap.identity == replacementIdentity,
                  oldTemporary.data == expected,
                  oldTemporary.identity == expectedIdentity,
                  Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            if published,
               let current = try? Self.readRegularFileWithIdentity(
                   parent: dataDescriptor,
                   name: name
               ),
               current.data == replacement,
               current.identity == publishedIdentity {
                do {
                    let oldTemporary = try Self.readRegularFileWithIdentity(
                        parent: dataDescriptor,
                        name: temporary
                    )
                    guard oldTemporary.data == expected,
                          oldTemporary.identity == expectedIdentity,
                          Darwin.renameatx_np(
                              dataDescriptor,
                              name,
                              dataDescriptor,
                              temporary,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(dataDescriptor) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                    try verify()
                    try enforce(
                        .generationPointer,
                        at: dataURL.appendingPathComponent(name, isDirectory: false)
                    )
                    let restored = try Self.readRegularFileWithIdentity(
                        parent: dataDescriptor,
                        name: name
                    )
                    let replacementTemporary = try Self.readRegularFileWithIdentity(
                        parent: dataDescriptor,
                        name: temporary
                    )
                    guard restored.data == expected,
                          restored.identity == expectedIdentity,
                          replacementTemporary.data == replacement,
                          replacementTemporary.identity == replacementIdentity,
                          Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
                          Darwin.fsync(dataDescriptor) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            if let temporaryData = try? Self.readRegularFile(
                parent: dataDescriptor,
                name: temporary
            ), temporaryData == replacement {
                _ = Darwin.unlinkat(dataDescriptor, temporary, 0)
                _ = Darwin.fsync(dataDescriptor)
            }
            throw error
        }
    }

    private func restorePointer(
        name: String,
        data: Data,
        expectedCurrentIdentity: RegularFileIdentity? = nil
    ) throws {
        let rollback = ".\(name).restore-rollback"
        let replacedIdentity = try Self.regularFileIdentity(
            parent: dataDescriptor,
            name: name
        )
        if let expectedCurrentIdentity {
            guard replacedIdentity == expectedCurrentIdentity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        if try Self.itemExists(parent: dataDescriptor, name: rollback) {
            guard try Self.readRegularFile(parent: dataDescriptor, name: rollback)
                    == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            guard Darwin.unlinkat(dataDescriptor, rollback, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        try Self.createRegularFile(
            parent: dataDescriptor,
            name: rollback,
            data: data
        )
        try enforce(
            .generationPointerTemporary,
            at: dataURL.appendingPathComponent(rollback, isDirectory: false)
        )
        let publishedIdentity = try Self.regularFileIdentity(
            parent: dataDescriptor,
            name: rollback
        )
        var swapped = false
        do {
            guard try Self.regularFileIdentity(
                      parent: dataDescriptor,
                      name: name
                  ) == replacedIdentity,
                  Darwin.renameatx_np(
                      dataDescriptor,
                      rollback,
                      dataDescriptor,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = true
            guard Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try enforce(
                .generationPointer,
                at: dataURL.appendingPathComponent(name, isDirectory: false)
            )
            let restored = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            let replaced = try Self.regularFileIdentity(
                parent: dataDescriptor,
                name: rollback
            )
            guard restored.data == data,
                  restored.identity == publishedIdentity,
                  replaced == replacedIdentity,
                  Darwin.unlinkat(dataDescriptor, rollback, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = false
        } catch {
            if swapped,
               let currentIdentity = try? Self.regularFileIdentity(
                   parent: dataDescriptor,
                   name: name
               ),
               currentIdentity == publishedIdentity,
               let rollbackIdentity = try? Self.regularFileIdentity(
                   parent: dataDescriptor,
                   name: rollback
               ),
               rollbackIdentity == replacedIdentity {
                do {
                    guard Darwin.renameatx_np(
                              dataDescriptor,
                              name,
                              dataDescriptor,
                              rollback,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(dataDescriptor) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            throw error
        }
    }

    private func tree(parent: Int32, id: UUID) throws -> Tree {
        try verify()
        let name = Self.canonical(id)
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        let expected = try Self.identity(descriptor)
        var directories = Set<String>()
        var files = Set<String>()
        try Self.enumerateTree(
            directory: descriptor,
            prefix: "",
            directories: &directories,
            files: &files
        )
        try verify()
        guard try Self.requiredDirectoryIdentity(parent: parent, name: name) == expected else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return Tree(directories: directories, files: files)
    }

    private func removeDirectory(parent: Int32, name: String) throws {
        try Self.requireSafeBasename(name)
        try verify()
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        let expected = try Self.identity(descriptor)
        try Self.removeContents(of: descriptor)
        try verify()
        guard try Self.requiredDirectoryIdentity(parent: parent, name: name) == expected,
              Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
        guard try !Self.itemExists(parent: parent, name: name) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    fileprivate static func removeContents(of directory: Int32) throws {
        for name in try names(in: directory) {
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                let expected: Identity
                do {
                    expected = try identity(child)
                    try removeContents(of: child)
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
                guard try requiredDirectoryIdentity(parent: directory, name: name)
                        == expected,
                      Darwin.unlinkat(directory, name, AT_REMOVEDIR) == 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            case S_IFREG:
                guard info.st_nlink == 1,
                      Darwin.unlinkat(directory, name, 0) == 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            default:
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        guard Darwin.fsync(directory) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private static func enumerateTree(
        directory: Int32,
        prefix: String,
        directories: inout Set<String>,
        files: inout Set<String>
    ) throws {
        for name in try names(in: directory) {
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                let expected: Identity
                do {
                    expected = try identity(child)
                    directories.insert(path)
                    try enumerateTree(
                        directory: child,
                        prefix: path,
                        directories: &directories,
                        files: &files
                    )
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
                guard try requiredDirectoryIdentity(parent: directory, name: name)
                        == expected else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            case S_IFREG:
                guard info.st_nlink == 1 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                files.insert(path)
            default:
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
    }

    fileprivate static func names(in descriptor: Int32) throws -> [String] {
        let independent = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard independent >= 0, let directory = Darwin.fdopendir(independent) else {
            if independent >= 0 { _ = Darwin.close(independent) }
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.closedir(directory) }
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
            if name != "." && name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        return result.sorted()
    }

    fileprivate static func itemExists(parent: Int32, name: String) throws -> Bool {
        try requireSafeBasename(name)
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            return true
        }
        guard errno == ENOENT else { throw StoreGenerationFailure.dataPointerInvalid }
        return false
    }

    private static func directoryPresence(parent: Int32, name: String) throws -> Bool {
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw StoreGenerationFailure.dataPointerInvalid }
            return false
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return true
    }

    fileprivate static func requiredDirectoryIdentity(
        parent: Int32,
        name: String
    ) throws -> Identity {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        return try identity(descriptor)
    }

    private static func openDirectory(parent: Int32, name: String) throws -> Int32 {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        return descriptor
    }

    private static func openOrCreateDirectory(parent: Int32, name: String) throws -> Int32 {
        var descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT {
            guard Darwin.mkdirat(parent, name, mode_t(0o700)) == 0 || errno == EEXIST,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            descriptor = Darwin.openat(
                parent,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        return descriptor
    }

    private static func regularFileSnapshot(
        descriptor: Int32,
        mismatchReason: StoreMigrationMaintenanceReasonV1
    ) throws -> RegularFileSnapshot {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              information.st_size <= off_t(Int.max) else {
            throw StoreMigrationFailure.maintenanceRequired(mismatchReason)
        }
        return RegularFileSnapshot(
            device: information.st_dev,
            inode: information.st_ino,
            linkCount: information.st_nlink,
            type: information.st_mode & S_IFMT,
            byteCount: information.st_size
        )
    }

    private static func namedRegularFileSnapshot(
        parent: Int32,
        name: String,
        mismatchReason: StoreMigrationMaintenanceReasonV1
    ) throws -> RegularFileSnapshot {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.maintenanceRequired(mismatchReason)
        }
        defer { _ = Darwin.close(descriptor) }
        return try regularFileSnapshot(
            descriptor: descriptor,
            mismatchReason: mismatchReason
        )
    }

    private static func streamedDigest(
        descriptor: Int32,
        expectedSnapshot: RegularFileSnapshot,
        mismatchReason: StoreMigrationMaintenanceReasonV1
    ) throws -> StreamedFileDigest {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(mismatchReason)
        }
        var hasher = SHA256()
        var byteCount = 0
        var buffer = [UInt8](
            repeating: 0,
            count: migrationStreamBufferByteCount
        )
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw StoreMigrationFailure.maintenanceRequired(mismatchReason)
            }
            let (nextCount, overflow) = byteCount.addingReportingOverflow(count)
            guard !overflow, off_t(nextCount) <= expectedSnapshot.byteCount else {
                throw StoreMigrationFailure.maintenanceRequired(mismatchReason)
            }
            byteCount = nextCount
            hasher.update(data: Data(buffer.prefix(count)))
        }
        guard byteCount == Int(expectedSnapshot.byteCount),
              try regularFileSnapshot(
                  descriptor: descriptor,
                  mismatchReason: mismatchReason
              ) == expectedSnapshot else {
            throw StoreMigrationFailure.maintenanceRequired(mismatchReason)
        }
        return StreamedFileDigest(
            byteCount: byteCount,
            sha256: hexDigest(hasher.finalize()),
            snapshot: expectedSnapshot
        )
    }

    private static func hexDigest(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func readRegularFileWithIdentity(
        parent: Int32,
        name: String
    ) throws -> RegularFileRead {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size >= 0,
              before.st_size <= off_t(Self.maximumControlFileByteCount) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RegularFileRead(
            data: data,
            identity: RegularFileIdentity(
                device: after.st_dev,
                inode: after.st_ino,
                linkCount: after.st_nlink
            )
        )
    }

    fileprivate static func readRegularFile(
        parent: Int32,
        name: String
    ) throws -> Data {
        try readRegularFileWithIdentity(parent: parent, name: name).data
    }

    fileprivate static func createRegularFile(
        parent: Int32,
        name: String,
        data: Data
    ) throws {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(
            parent,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        do {
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        raw.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if errno != EINTR {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                }
            }
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            _ = Darwin.unlinkat(parent, name, 0)
            _ = Darwin.fsync(parent)
            throw error
        }
    }

    private static func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func decodeCanonicalPointer<Value: Codable>(
        _ data: Data
    ) throws -> Value {
        do {
            let value = try JSONDecoder().decode(Value.self, from: data)
            guard try canonicalData(value) == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return value
        } catch let error as StoreGenerationFailure {
            throw error
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    fileprivate static func decodeCanonicalPointer<Value: Codable>(
        parent: Int32,
        name: String
    ) throws -> Value {
        let captured = try readRegularFileWithIdentity(parent: parent, name: name)
        let value: Value = try decodeCanonicalPointer(captured.data)
        guard try regularFileIdentity(parent: parent, name: name) == captured.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return value
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    fileprivate static func regularFileIdentity(
        parent: Int32,
        name: String
    ) throws -> RegularFileIdentity {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RegularFileIdentity(
            device: after.st_dev,
            inode: after.st_ino,
            linkCount: after.st_nlink
        )
    }

    fileprivate static func regularFileIdentity(
        descriptor: Int32
    ) throws -> RegularFileIdentity {
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RegularFileIdentity(
            device: after.st_dev,
            inode: after.st_ino,
            linkCount: after.st_nlink
        )
    }

    fileprivate static func regularFileIdentity(
        at url: URL
    ) throws -> RegularFileIdentity {
        let descriptor = Darwin.open(url.standardizedFileURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        return try regularFileIdentity(descriptor: descriptor)
    }

    fileprivate static func directoryIdentity(
        at url: URL
    ) throws -> Identity {
        let descriptor = Darwin.open(
            url.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        return try identity(descriptor)
    }

    fileprivate static func directoryIdentity(
        descriptor: Int32
    ) throws -> Identity {
        try identity(descriptor)
    }

    private static func require(_ descriptor: Int32, _ expected: Identity) throws {
        guard try identity(descriptor) == expected else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private static func currentURL(for descriptor: Int32) throws -> URL {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = Darwin.fcntl(descriptor, F_GETPATH, &path)
        guard result >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let value = String(cString: path)
        guard !value.isEmpty else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return URL(fileURLWithPath: value, isDirectory: true)
            .standardizedFileURL
    }

    private static func canonical(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }
}

enum StoreGenerationPruneFaultBoundaryV1: String, CaseIterable, Equatable, Sendable {
    case prepared
    case bytesRemoved
    case retiredPointerPublished
    case receiptPublished
}

#if DEBUG
enum StoreGenerationPruneInjectedFailureV1: Error, Equatable {
    case injectedFault(StoreGenerationPruneFaultBoundaryV1)
}

final class StoreGenerationPruneFailureInjectionV1 {
    private var pending: StoreGenerationPruneFaultBoundaryV1?

    init(failOnceAt boundary: StoreGenerationPruneFaultBoundaryV1) {
        self.pending = boundary
    }

    func reach(_ boundary: StoreGenerationPruneFaultBoundaryV1) throws {
        guard pending == boundary else { return }
        pending = nil
        throw StoreGenerationPruneInjectedFailureV1.injectedFault(boundary)
    }
}
#endif

struct StoreGenerationFactory {
    private static let dataDirectoryName = "FieldEvidenceData"
    private static let bootstrapDirectoryName = ".FieldEvidenceData.bootstrap"
    private static let generationsDirectoryName = "generations"
    private static let currentPointerName = "current.json"
    private static let retiredPointerName = "retired.json"
    private static let modelStoreName = "model.sqlite"
    private static let bootstrapManifestMigrationID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000003"
    )!
    private static let bootstrapPredecessorGenerationID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    )!
    private static let pointerMutationLock = NSLock()

    private let applicationSupportURL: URL
    private let fileManager: FileManager
    private let migrationIdentitySource: StoreMigrationIdentitySourceV1?
    private let pointerEnrichmentIdentity: WorkspaceReplicaIdentityV1
    private let generationLeaseRegistryProvider: StoreGenerationLeaseRegistryProvider
#if DEBUG
    private let migrationFailureInjection: StoreMigrationFailureInjection?
    private let pruneFailureInjection: StoreGenerationPruneFailureInjectionV1?
#endif

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        migrationIdentitySource: StoreMigrationIdentitySourceV1? = nil,
        pointerEnrichmentIdentity: WorkspaceReplicaIdentityV1? = nil
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
        self.migrationIdentitySource = migrationIdentitySource
        self.pointerEnrichmentIdentity = pointerEnrichmentIdentity
            ?? Self.makeLiveWorkspaceIdentity()
        self.generationLeaseRegistryProvider = StoreGenerationLeaseRegistryProvider()
        #if DEBUG
        self.migrationFailureInjection = nil
        self.pruneFailureInjection = nil
        #endif
    }

#if DEBUG
    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        migrationIdentitySource: StoreMigrationIdentitySourceV1? = nil,
        pointerEnrichmentIdentity: WorkspaceReplicaIdentityV1? = nil,
        migrationFailureInjection: StoreMigrationFailureInjection
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
        self.migrationIdentitySource = migrationIdentitySource
        self.pointerEnrichmentIdentity = pointerEnrichmentIdentity
            ?? Self.makeLiveWorkspaceIdentity()
        self.generationLeaseRegistryProvider = StoreGenerationLeaseRegistryProvider()
        self.migrationFailureInjection = migrationFailureInjection
        self.pruneFailureInjection = nil
    }

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        migrationIdentitySource: StoreMigrationIdentitySourceV1? = nil,
        pointerEnrichmentIdentity: WorkspaceReplicaIdentityV1? = nil,
        pruneFailureInjection: StoreGenerationPruneFailureInjectionV1
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
        self.migrationIdentitySource = migrationIdentitySource
        self.pointerEnrichmentIdentity = pointerEnrichmentIdentity
            ?? Self.makeLiveWorkspaceIdentity()
        self.generationLeaseRegistryProvider = StoreGenerationLeaseRegistryProvider()
        self.migrationFailureInjection = nil
        self.pruneFailureInjection = pruneFailureInjection
    }
#endif

    private static func makeLiveWorkspaceIdentity() -> WorkspaceReplicaIdentityV1 {
        for _ in 0..<16 {
            let workspaceID = WorkspaceID()
            let replicaID = ReplicaID()
            if let identity = try? WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: replicaID
            ) {
                return identity
            }
        }
        preconditionFailure("Unable to create distinct workspace and replica identities")
    }

    private func reachMigrationBoundary(
        _ boundary: StoreMigrationFaultBoundaryV1
    ) throws {
#if DEBUG
        try migrationFailureInjection?.reach(boundary)
#else
        _ = boundary
#endif
    }

    private func reachPruneBoundary(
        _ boundary: StoreGenerationPruneFaultBoundaryV1
    ) throws {
#if DEBUG
        try pruneFailureInjection?.reach(boundary)
#else
        _ = boundary
#endif
    }

    var restoreApplicationSupportURL: URL {
        applicationSupportURL
    }

    func makeGenerationLeaseRegistry() throws -> GenerationLeaseRegistryV1 {
        try generationLeaseRegistryProvider.registry(
            applicationSupportURL: applicationSupportURL
        )
    }

    func makeGenerationLeaseRegistry(
        ownerID: UUID
    ) throws -> GenerationLeaseRegistryV1 {
        try GenerationLeaseRegistryV1(
            applicationSupportURL: applicationSupportURL,
            ownerID: ownerID
        )
    }

    @MainActor
    func currentGenerationEpoch() throws -> GenerationEpochV1 {
        let pointer = try currentGenerationPointerV3(
            expectedGenerationID: currentGenerationID()
        )
        guard let generationID = canonicalUUID(from: pointer.generationID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return try GenerationEpochV1(
            generationID: generationID,
            generationManifestSHA256: pointer.generationManifestSHA256
        )
    }

    @MainActor
    func makeWriterFence(
        expectedGenerationEpoch: GenerationEpochV1,
        writerLeaseToken: GenerationLeaseTokenV1,
        registry: GenerationLeaseRegistryV1
    ) throws -> StaleWriterFenceV1 {
        try StaleWriterFenceV1(
            expectedGenerationEpoch: expectedGenerationEpoch,
            writerLeaseToken: writerLeaseToken,
            registry: registry,
            currentGenerationEpoch: { [self] in
                try self.currentGenerationEpoch()
            }
        )
    }

    private func acquireCurrentReaderLease(
        epoch: GenerationEpochV1,
        expectedPointerData: Data
    ) throws -> GenerationLeaseHandleV1 {
        let registry = try makeGenerationLeaseRegistry()
        return try registry.withExclusiveGenerationMutationLock {
            let current = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
            )
            guard current.data == expectedPointerData else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            return try registry.acquireHandle(epoch: epoch, role: .reader)
        }
    }

    private func acquireAcceptedReaderLease(
        epoch: GenerationEpochV1
    ) throws -> GenerationLeaseHandleV1 {
        let registry = try makeGenerationLeaseRegistry()
        return try registry.withExclusiveGenerationMutationLock {
            let authority = try makeRestoreGenerationAuthority()
            let acceptedIDs = Set(
                [try authority.currentGenerationID()]
                    + authority.retiredGenerationIDs()
            )
            guard acceptedIDs.contains(epoch.generationID) else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            return try registry.acquireHandle(epoch: epoch, role: .reader)
        }
    }

    @MainActor
    func currentGenerationID() throws -> UUID {
        let authority = try makeRestoreGenerationAuthority()
        return try currentGenerationID(authority: authority)
    }

    @MainActor
    func currentGenerationID(
        authority: StoreRestoreGenerationAuthority
    ) throws -> UUID {
        let authorityValue = try authority.currentGenerationID()
        let envelope = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        switch envelope {
        case .legacy(let pointer, _):
            guard canonicalUUID(from: pointer.generationID) == authorityValue else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        case .v2(let pointer, _):
            guard canonicalUUID(from: pointer.generationID) == authorityValue else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            _ = try requireCurrentManifest(pointer)
        case .v3(let pointer, _):
            guard canonicalUUID(from: pointer.generationID) == authorityValue else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            _ = try requireCurrentManifest(pointer)
        }
        return authorityValue
    }

    @MainActor
    func currentWorkspaceIdentity(
        expectedGenerationID: UUID,
        authority suppliedAuthority: StoreRestoreGenerationAuthority? = nil
    ) throws -> WorkspaceReplicaIdentityV1 {
        let pointer = try currentGenerationPointerV3(
            expectedGenerationID: expectedGenerationID,
            authority: suppliedAuthority
        )
        return try pointer.identity()
    }

    @MainActor
    func currentGenerationPointerV3(
        expectedGenerationID: UUID,
        authority suppliedAuthority: StoreRestoreGenerationAuthority? = nil
    ) throws -> CurrentGenerationPointerV3 {
        let authority: StoreRestoreGenerationAuthority
        if let suppliedAuthority {
            authority = suppliedAuthority
        } else {
            authority = try makeRestoreGenerationAuthority()
        }
        guard try authority.currentGenerationID() == expectedGenerationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard case .v3(let pointer, _) = try decodeCurrentPointer(
                  at: dataRootURL.appendingPathComponent(Self.currentPointerName)
              ), canonicalUUID(from: pointer.generationID) == expectedGenerationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try requireCurrentManifest(pointer)
        return pointer
    }

    @MainActor
    func currentGenerationDeletionLedgerProof(
        expectedPointer: RestorePointerIdentityV1,
        authority: StoreRestoreGenerationAuthority
    ) throws -> DeletionLedgerProofV2 {
        let pointer = try requireCurrentPointer(expectedPointer, authority: authority)
        let session = try openValidatedV3Current(
            pointer: pointer,
            dataRootURL: dataRootURL,
            store: StoreMigrationJournalStoreV1(applicationSupportURL: applicationSupportURL)
        )
        return try deletionLedgerProof(in: session.modelContext)
    }

    @MainActor
    func createEmptyEraseGeneration(
        id: UUID,
        expectedOldPointer: RestorePointerIdentityV1,
        identity: WorkspaceReplicaIdentityV1,
        authority: StoreRestoreGenerationAuthority
    ) throws -> (pointer: RestorePointerIdentityV1, ledgerProof: DeletionLedgerProofV2) {
        _ = try requireCurrentPointer(expectedOldPointer, authority: authority)
        try createEmptyInstalledGeneration(id: id, authority: authority)
        let session = try openGeneration(
            id: id,
            at: installedGenerationURL(id: id),
            identity: identity
        )
        _ = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: identity,
            generationID: id
        )
        let prepared = try makeRestoreCurrentPointer(
            expectedOldID: expectedOldPointer.generationID,
            newID: id
        )
        let pointer = try CurrentGenerationPointerV3(
            generationID: id,
            generationManifestSHA256: prepared.generationManifestSHA256,
            workspaceID: identity.workspaceID,
            replicaID: identity.replicaID,
            knownReplicaIDs: [identity.replicaID],
            storeSchemaVersion: 46
        )
        let proof = try deletionLedgerProof(in: session.modelContext)
        guard proof.entryCount == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        _ = try requireCurrentPointer(expectedOldPointer, authority: authority)
        return (try restorePointerIdentity(pointer), proof)
    }

    @MainActor
    func publishEmptyEraseGeneration(
        expectedOldPointer: RestorePointerIdentityV1,
        targetPointer: RestorePointerIdentityV1,
        expectedEmptyLedger: DeletionLedgerProofV2,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try expectedEmptyLedger.validate()
        guard expectedOldPointer.generationID != targetPointer.generationID,
              expectedEmptyLedger.entryCount == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let old = try requireCurrentPointer(expectedOldPointer, authority: authority)
        let target = try currentPointer(from: targetPointer)
        _ = try requireCurrentManifest(target)
        let session = try openGeneration(
            id: targetPointer.generationID,
            at: installedGenerationURL(id: targetPointer.generationID),
            identity: try target.identity()
        )
        guard try deletionLedgerProof(in: session.modelContext) == expectedEmptyLedger else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try authority.switchCurrentGeneration(
                expected: expectedOldPointer.generationID,
                to: targetPointer.generationID,
                pointer: target,
                expectedCurrentPointer: old
            )
        }
    }

    @MainActor
    func requirePublishedEmptyEraseGeneration(
        oldPointer: RestorePointerIdentityV1,
        targetPointer: RestorePointerIdentityV1,
        expectedEmptyLedger: DeletionLedgerProofV2,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        try expectedEmptyLedger.validate()
        guard oldPointer.generationID != targetPointer.generationID,
              expectedEmptyLedger.entryCount == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let pointer = try requireCurrentPointer(targetPointer, authority: authority)
        let session = try openValidatedV3Current(
            pointer: pointer,
            dataRootURL: dataRootURL,
            store: StoreMigrationJournalStoreV1(applicationSupportURL: applicationSupportURL)
        )
        guard try deletionLedgerProof(in: session.modelContext) == expectedEmptyLedger else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        return session
    }

    @MainActor
    func discardPreparedEmptyEraseGeneration(
        expectedOldPointer: RestorePointerIdentityV1,
        targetGenerationID: UUID,
        targetIdentity: WorkspaceReplicaIdentityV1,
        expectedEmptyLedger: DeletionLedgerProofV2,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try expectedEmptyLedger.validate()
        let old = try requireCurrentPointer(expectedOldPointer, authority: authority)
        let oldIdentityValues = Set(
            [
                expectedOldPointer.workspaceID,
                expectedOldPointer.replicaID,
            ] + expectedOldPointer.knownReplicaIDs
        )
        let forbidden = Set(
            [
                expectedOldPointer.generationID,
                expectedOldPointer.workspaceID,
                expectedOldPointer.replicaID,
                targetGenerationID,
            ] + expectedOldPointer.knownReplicaIDs
        )
        guard old.storeSchemaVersion == 8,
              expectedEmptyLedger.entryCount == 0,
              targetGenerationID != expectedOldPointer.generationID,
              !oldIdentityValues.contains(targetGenerationID),
              targetIdentity.workspaceID != targetIdentity.replicaID,
              !forbidden.contains(targetIdentity.workspaceID.rawValue),
              !forbidden.contains(targetIdentity.replicaID.rawValue) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try authority.requireNoRestoreJournal()

        let retired = try authority.retiredGenerationIDs()
        guard !retired.contains(targetGenerationID),
              try authority.restoreGenerationNames().isEmpty,
              try authority.importStagingNames().isEmpty else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let expectedNames = Set(
            ([expectedOldPointer.generationID] + retired).map {
                canonicalString(for: $0)
            }
        )
        let actualNames = Set(try authority.installedGenerationNames())
        let targetName = canonicalString(for: targetGenerationID)
        guard actualNames == expectedNames
                || actualNames == expectedNames.union([targetName]) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let presence = try authority.presence(id: targetGenerationID)
        guard !presence.staging,
              presence.installed == actualNames.contains(targetName) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        guard presence.installed else {
            guard try store.loadManifestIfPresent(
                targetGenerationID: targetGenerationID
            ) == nil else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            _ = try requireCurrentPointer(expectedOldPointer, authority: authority)
            return
        }

        let root = installedGenerationURL(id: targetGenerationID)
        let session = try openGeneration(
            id: targetGenerationID,
            at: root,
            identity: targetIdentity
        )
        let marker = try session.modelContext.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        guard marker.count == 1,
              marker.first?.schemaVersion == 17,
              marker.first?.releaseID
                == PersistentSchemaReleaseRegistryV1.v17CompatibilityID,
              marker.first?.migrationID == targetGenerationID,
              BackupRestoreService.isEmptyCurrent(session.modelContext),
              try deletionLedgerProof(in: session.modelContext)
                == expectedEmptyLedger else {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }

        if let prepared = try store.loadManifestIfPresent(
            targetGenerationID: targetGenerationID
        ) {
            guard prepared.manifest.generationID == targetGenerationID,
                  prepared.manifest.predecessorGenerationID
                    == expectedOldPointer.generationID,
                  prepared.manifest.storeSchemaRelease == .v11,
                  prepared.manifest.migrationID == targetGenerationID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            try requireRestoreManifestSnapshot(
                prepared.manifest,
                expectedOldID: expectedOldPointer.generationID,
                generationID: targetGenerationID,
                at: root,
                staging: false
            )
            try removePreparedRestoreGenerationManifestBeforeDiscard(
                expectedOldID: expectedOldPointer.generationID,
                generationID: targetGenerationID,
                expectedDigest: prepared.digest,
                authority: authority
            )
        }

        _ = try requireCurrentPointer(expectedOldPointer, authority: authority)
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            guard try !registry.activeEpochs().contains(where: {
                $0.generationID == targetGenerationID
            }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try authority.removeInstalledGeneration(id: targetGenerationID)
        }
        let finalPresence = try authority.presence(id: targetGenerationID)
        guard !finalPresence.staging,
              !finalPresence.installed,
              Set(try authority.installedGenerationNames()) == expectedNames,
              try store.loadManifestIfPresent(
                targetGenerationID: targetGenerationID
              ) == nil else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        _ = try requireCurrentPointer(expectedOldPointer, authority: authority)
    }

    @MainActor
    private func deletionLedgerProof(
        in context: ModelContext
    ) throws -> DeletionLedgerProofV2 {
        let ledger = try DeletionLedgerStore(context: context).snapshot()
        return try DeletionLedgerProofV2(
            entryCount: ledger.entries.count,
            canonicalSHA256: StoreMigrationCanonicalJSONV1.sha256(
                try ledger.canonicalData()
            )
        )
    }

    private func currentPointer(
        from identity: RestorePointerIdentityV1
    ) throws -> CurrentGenerationPointerV3 {
        try CurrentGenerationPointerV3(
            generationID: identity.generationID,
            generationManifestSHA256: identity.generationManifestSHA256,
            workspaceID: WorkspaceID(rawValue: identity.workspaceID),
            replicaID: ReplicaID(rawValue: identity.replicaID),
            knownReplicaIDs: Set(identity.knownReplicaIDs.map { ReplicaID(rawValue: $0) }),
            storeSchemaVersion: 46
        )
    }

    @MainActor
    private func requireCurrentPointer(
        _ identity: RestorePointerIdentityV1,
        authority: StoreRestoreGenerationAuthority
    ) throws -> CurrentGenerationPointerV3 {
        guard try authority.currentGenerationID() == identity.generationID,
              case .v3(let actual, let data) = try decodeCurrentPointer(
                at: dataRootURL.appendingPathComponent(Self.currentPointerName)
              ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let expected = try currentPointer(from: identity)
        guard actual == expected,
              data == (try expected.canonicalData()) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try requireCurrentManifest(actual)
        return actual
    }

    private func restorePointerIdentity(
        _ pointer: CurrentGenerationPointerV3
    ) throws -> RestorePointerIdentityV1 {
        try pointer.validate()
        guard let generationID = canonicalUUID(from: pointer.generationID),
              let workspaceID = canonicalUUID(from: pointer.workspaceID),
              let replicaID = canonicalUUID(from: pointer.replicaID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RestorePointerIdentityV1(
            generationID: generationID,
            generationManifestSHA256: pointer.generationManifestSHA256,
            knownReplicaIDs: Set(try pointer.knownReplicaIdentitySet().map(\.rawValue)),
            workspaceID: workspaceID,
            replicaID: replicaID
        )
    }

    @MainActor
    func prepareRestoreStagingGenerationManifest(
        expectedOldID: UUID,
        newID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> String {
        guard try authority.currentGenerationID() == expectedOldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try authority.requireStagingGeneration(id: newID)
        try authority.protectStagingGeneration(id: newID)
        let root = restoreStagingGenerationURL(id: newID)
        let modelStoreURL = root.appendingPathComponent(Self.modelStoreName)
        let markerMigrationID = try autoreleasepool { () throws -> UUID in
            let container = try makeV48Container(at: modelStoreURL, migrate: false)
            let marker = try requireV48Marker(
                in: container.mainContext,
                expectedMigrationID: nil
            )
            guard let value = marker.migrationID else {
                throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
            }
            return value
        }
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let digest: String
        if let existing = try store.loadManifestIfPresent(targetGenerationID: newID) {
            try requireRestoreManifestSnapshot(
                existing.manifest,
                expectedOldID: expectedOldID,
                generationID: newID,
                at: root,
                staging: true
            )
            digest = existing.digest
        } else {
            let manifest = try StoreGenerationManifestV1(
                generationID: newID,
                predecessorGenerationID: expectedOldID,
                migrationID: markerMigrationID,
                storeSchemaRelease: .v46,
                semanticSHA256: try semanticDigest(
                    at: modelStoreURL,
                    release: .v46
                ),
                frozenIdentityDigest: try frozenIdentityDigest(for: root),
                files: try generationFileDigests(at: root, durable: true)
            )
            digest = try store.writeManifest(manifest)
            try requireRestoreManifestSnapshot(
                manifest,
                expectedOldID: expectedOldID,
                generationID: newID,
                at: root,
                staging: true
            )
        }
        guard try authority.currentGenerationID() == expectedOldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try authority.requireStagingGeneration(id: newID)
        return digest
    }

    @MainActor
    func requireInstalledRestoreGenerationSnapshot(
        expectedOldID: UUID,
        generationID: UUID,
        expectedManifestDigest: String,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
            expectedManifestDigest
        ) else {
            throw StoreMigrationFailure.invalidDigest
        }
        try authority.requireInstalledGeneration(id: generationID)
        try authority.protectInstalledGeneration(id: generationID)
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let manifest = try store.loadManifest(
            targetGenerationID: generationID,
            expectedDigest: expectedManifestDigest
        )
        try requireRestoreManifestSnapshot(
            manifest,
            expectedOldID: expectedOldID,
            generationID: generationID,
            at: installedGenerationURL(id: generationID),
            staging: false
        )
        try authority.protectInstalledGeneration(id: generationID)
        try authority.requireInstalledGeneration(id: generationID)
    }

    @MainActor
    func removePreparedRestoreGenerationManifestBeforeDiscard(
        expectedOldID: UUID,
        generationID: UUID,
        expectedDigest: String,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard generationID != expectedOldID,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(expectedDigest),
              try currentGenerationID(authority: authority) == expectedOldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let presence = try generationPresence(
            id: generationID,
            authority: authority
        )
        guard !(presence.staging && presence.installed) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        if presence.staging {
            try authority.protectStagingGeneration(id: generationID)
            try authority.requireStagingGeneration(id: generationID)
        } else if presence.installed {
            try authority.protectInstalledGeneration(id: generationID)
            try authority.requireInstalledGeneration(id: generationID)
        }

        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        if let existing = try store.loadManifestIfPresent(
            targetGenerationID: generationID
        ) {
            guard existing.digest == expectedDigest,
                  existing.manifest.generationID == generationID,
                  presence.staging || presence.installed else {
                throw StoreMigrationFailure.digestMismatch
            }
            try requireRestoreManifestSnapshot(
                existing.manifest,
                expectedOldID: expectedOldID,
                generationID: generationID,
                at: presence.staging
                    ? restoreStagingGenerationURL(id: generationID)
                    : installedGenerationURL(id: generationID),
                staging: presence.staging
            )
            try store.removeManifest(
                targetGenerationID: generationID,
                expectedDigest: expectedDigest
            )
        }

        if let _ = try store.loadManifestIfPresent(
            targetGenerationID: generationID
        ) {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
        guard try currentGenerationID(authority: authority) == expectedOldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let after = try generationPresence(
            id: generationID,
            authority: authority
        )
        guard after.staging == presence.staging,
              after.installed == presence.installed,
              !(after.staging && after.installed) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        if after.staging {
            try authority.protectStagingGeneration(id: generationID)
            try authority.requireStagingGeneration(id: generationID)
        } else if after.installed {
            try authority.protectInstalledGeneration(id: generationID)
            try authority.requireInstalledGeneration(id: generationID)
        }
    }

    @MainActor
    func removePreparedRestoreStagingGenerationManifest(
        generationID: UUID,
        expectedDigest: String,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(expectedDigest),
              try authority.currentGenerationID() != generationID,
              !(try generationPresence(
                  id: generationID,
                  authority: authority
              ).installed) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        guard let existing = try store.loadManifestIfPresent(
            targetGenerationID: generationID
        ) else {
            return
        }
        guard existing.digest == expectedDigest,
              existing.manifest.generationID == generationID else {
            throw StoreMigrationFailure.digestMismatch
        }
        try store.removeManifest(
            targetGenerationID: generationID,
            expectedDigest: expectedDigest
        )
        if let _ = try store.loadManifestIfPresent(
            targetGenerationID: generationID
        ) {
            throw StoreMigrationFailure.maintenanceRequired(.targetMismatch)
        }
    }

    func restoreStagingGenerationURL(id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(canonicalString(for: id), isDirectory: true)
    }

    func installedGenerationURL(id: UUID) -> URL {
        generationsURL.appendingPathComponent(
            canonicalString(for: id),
            isDirectory: true
        )
    }

    func makeRestoreGenerationAuthority(
        expectedApplicationSupportIdentity: StoreApplicationSupportIdentity? = nil
    ) throws -> StoreRestoreGenerationAuthority {
        try StoreRestoreGenerationAuthority(
            applicationSupportURL: applicationSupportURL,
            expectedApplicationSupportIdentity: expectedApplicationSupportIdentity
        )
    }

    func generationPresence(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreRestoreGenerationAuthority.Presence {
        try authority.presence(id: id)
    }

    @MainActor
    func createRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority,
        recordsSchemaVersion: Int,
        sourceGenerationID: UUID?,
        archiveProvenanceSHA256: String,
        populate: (ModelContext) throws -> Void
    ) throws {
        guard (1...C05EvidenceCurationMigrationBoundaryV1.currentRecordsSchemaVersion)
                .contains(recordsSchemaVersion),
              CompatibilityCanonicalV1.validSHA256(archiveProvenanceSHA256),
              (recordsSchemaVersion >= 5) == (sourceGenerationID != nil) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let root = restoreStagingGenerationURL(id: id)
        do {
            try authority.createStagingGeneration(id: id)
            let modelURL = root.appendingPathComponent(Self.modelStoreName)
            if recordsSchemaVersion >= 9 {
                try autoreleasepool {
                    let container = try makeFreshRestoreSourceContainer(
                        at: modelURL,
                        recordsSchemaVersion: recordsSchemaVersion,
                        markerMigrationID: id
                    )
                    let context = container.mainContext
                    try populate(context)
                    if context.hasChanges { try context.save() }
                }
            } else if recordsSchemaVersion == 8 {
                try autoreleasepool {
                    let container = try makeFreshV9Container(at: modelURL, markerMigrationID: id)
                    let context = container.mainContext; try populate(context)
                    if context.hasChanges { try context.save() }
                    _ = try requireV9Marker(in: context, expectedMigrationID: id)
                }
            } else if recordsSchemaVersion == 7 {
                try autoreleasepool {
                    let container = try makeFreshV8Container(
                        at: modelURL,
                        markerMigrationID: id
                    )
                    let context = container.mainContext
                    try populate(context)
                    if context.hasChanges { try context.save() }
                    _ = try requireV8Marker(in: context, expectedMigrationID: id)
                }
            } else if recordsSchemaVersion == 6 {
                try autoreleasepool {
                    let container = try makeFreshV7Container(
                        at: modelURL,
                        markerMigrationID: id
                    )
                    let context = container.mainContext
                    try populate(context)
                    if context.hasChanges {
                        try context.save()
                        guard !context.hasChanges else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                    }
                    _ = try requireV7Marker(in: context, expectedMigrationID: id)
                }
            } else {
                try autoreleasepool {
                    let container = try makeFreshV6Container(
                        at: modelURL,
                        markerMigrationID: id
                    )
                    let context = container.mainContext
                    try populate(context)
                    if context.hasChanges {
                        try context.save()
                        guard !context.hasChanges else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                    }
                    if recordsSchemaVersion <= 4 {
                        try backfillLegacyRestoreV6LocationBaseline(
                            in: context,
                            migrationID: id,
                            archivalSourceGenerationID: try archivalSourceGenerationID(
                                archiveProvenanceSHA256: archiveProvenanceSHA256,
                                targetGenerationID: id
                            ),
                            targetGenerationID: id
                        )
                    } else {
                        guard let sourceGenerationID,
                              sourceGenerationID != id else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                        _ = try requireV6Marker(in: context, expectedMigrationID: id)
                    }
                }
                try autoreleasepool {
                    let container = try makeV7Container(at: modelURL, migrate: true)
                    try backfillV7Marker(in: container.mainContext, migrationID: id)
                }
            }
            if recordsSchemaVersion < 7 {
                try autoreleasepool {
                    let container = try makeV8Container(at: modelURL, migrate: true)
                    let context = container.mainContext
                    let workspaceID = try restoreBackfillWorkspaceID(
                        in: context,
                        fallback: id
                    )
                    try backfillV8RequirementAssurance(
                        in: context,
                        workspaceID: workspaceID,
                        migrationID: id
                    )
                }
            }
            if recordsSchemaVersion < 8 {
                try autoreleasepool {
                    let container = try makeV9Container(at: modelURL, migrate: true)
                    try backfillV9Marker(in: container.mainContext, migrationID: id)
                }
            }
            let firstTargetPersistentSchemaVersion = max(recordsSchemaVersion + 2, 10)
            let currentPersistentSchemaVersion = 48
            if firstTargetPersistentSchemaVersion <= currentPersistentSchemaVersion {
                for targetPersistentSchemaVersion in
                    firstTargetPersistentSchemaVersion...currentPersistentSchemaVersion {
                    try autoreleasepool {
                        try advanceRestoreStagingGeneration(
                            at: modelURL,
                            toPersistentSchemaVersion: targetPersistentSchemaVersion,
                            migrationID: id
                        )
                    }
                }
            } else {
                _ = try autoreleasepool {
                    let container = try makeV48Container(at: modelURL, migrate: false)
                    return try requireV48Marker(
                        in: container.mainContext,
                        expectedMigrationID: id
                    )
                }
            }
            try authority.protectStagingGeneration(id: id)
            try authority.requireStagingGeneration(id: id)
            guard try itemType(
                at: root.appendingPathComponent(Self.modelStoreName)
            ) == .typeRegular else {
                throw StoreGenerationFailure.dataGenerationMissing
            }
        } catch {
            try? authority.removeStagingGeneration(id: id)
            throw error
        }
    }

    @MainActor
    private func makeFreshRestoreSourceContainer(
        at modelStoreURL: URL,
        recordsSchemaVersion: Int,
        markerMigrationID: UUID
    ) throws -> ModelContainer {
        let persistentSchemaVersion = recordsSchemaVersion + 1
        let container: ModelContainer
        switch persistentSchemaVersion {
        case 10: return try makeFreshV10Container(at: modelStoreURL, markerMigrationID: markerMigrationID)
        case 11: return try makeFreshV11Container(at: modelStoreURL, markerMigrationID: markerMigrationID)
        case 12: return try makeFreshV12Container(at: modelStoreURL, markerMigrationID: markerMigrationID)
        case 13: container = try makeV13Container(at: modelStoreURL, migrate: false)
        case 14: container = try makeV14Container(at: modelStoreURL, migrate: false)
        case 15: container = try makeV15Container(at: modelStoreURL, migrate: false)
        case 16: container = try makeV16Container(at: modelStoreURL, migrate: false)
        case 17: container = try makeV17Container(at: modelStoreURL, migrate: false)
        case 18: container = try makeV18Container(at: modelStoreURL, migrate: false)
        case 19: container = try makeV19Container(at: modelStoreURL, migrate: false)
        case 20: container = try makeV20Container(at: modelStoreURL, migrate: false)
        case 21: container = try makeV21Container(at: modelStoreURL, migrate: false)
        case 22: container = try makeV22Container(at: modelStoreURL, migrate: false)
        case 23: container = try makeV23Container(at: modelStoreURL, migrate: false)
        case 24: container = try makeV24Container(at: modelStoreURL, migrate: false)
        case 25: container = try makeV25Container(at: modelStoreURL, migrate: false)
        case 26: container = try makeV26Container(at: modelStoreURL, migrate: false)
        case 27: container = try makeV27Container(at: modelStoreURL, migrate: false)
        case 28: container = try makeV28Container(at: modelStoreURL, migrate: false)
        case 29: container = try makeV29Container(at: modelStoreURL, migrate: false)
        case 30: container = try makeV30Container(at: modelStoreURL, migrate: false)
        case 31: container = try makeV31Container(at: modelStoreURL, migrate: false)
        case 32: container = try makeV32Container(at: modelStoreURL, migrate: false)
        case 33: container = try makeV33Container(at: modelStoreURL, migrate: false)
        case 34: container = try makeV34Container(at: modelStoreURL, migrate: false)
        case 35: container = try makeV35Container(at: modelStoreURL, migrate: false)
        case 36: container = try makeV36Container(at: modelStoreURL, migrate: false)
        case 37: container = try makeV37Container(at: modelStoreURL, migrate: false)
        case 38: container = try makeV38Container(at: modelStoreURL, migrate: false)
        case 39: container = try makeV39Container(at: modelStoreURL, migrate: false)
        case 40: container = try makeV40Container(at: modelStoreURL, migrate: false)
        case 41: container = try makeV41Container(at: modelStoreURL, migrate: false)
        case 42: container = try makeV42Container(at: modelStoreURL, migrate: false)
        case 43: container = try makeV43Container(at: modelStoreURL, migrate: false)
        case 44: container = try makeV44Container(at: modelStoreURL, migrate: false)
        case 45: container = try makeV45Container(at: modelStoreURL, migrate: false)
        case 46: container = try makeV46Container(at: modelStoreURL, migrate: false)
        case 47: container = try makeV47Container(at: modelStoreURL, migrate: false)
        case 48: container = try makeV48Container(at: modelStoreURL, migrate: false)
        case 49: container = try makeV49Container(at: modelStoreURL, migrate: false)
        case 50: container = try makeV50Container(at: modelStoreURL, migrate: false)
        case 51: container = try makeV51Container(at: modelStoreURL, migrate: false)
        case 52: container = try makeV52Container(at: modelStoreURL, migrate: false)
        case 53: container = try makeV53Container(at: modelStoreURL, migrate: false)
        default: throw StoreGenerationFailure.dataPointerInvalid
        }
        guard let release = PersistentSchemaReleaseV1(rawValue: "V\(persistentSchemaVersion)"),
              let predecessor = PersistentSchemaReleaseV1(
                  rawValue: "V\(persistentSchemaVersion - 1)"
              ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let context = container.mainContext
        context.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: persistentSchemaVersion,
            releaseID: release.compatibilityID,
            predecessorReleaseID: predecessor.compatibilityID,
            migrationID: markerMigrationID
        ))
        try context.save()
        return container
    }

    @MainActor
    private func advanceRestoreStagingGeneration(
        at modelStoreURL: URL,
        toPersistentSchemaVersion target: Int,
        migrationID: UUID
    ) throws {
        switch target {
        case 10:
            let container = try makeV10Container(at: modelStoreURL, migrate: true)
            try backfillV10AssetSemantics(
                in: container.mainContext,
                migrationID: migrationID,
                targetGenerationID: migrationID
            )
        case 11:
            let container = try makeV11Container(at: modelStoreURL, migrate: true)
            try backfillV11Marker(in: container.mainContext, migrationID: migrationID)
        case 12:
            let container = try makeV12Container(at: modelStoreURL, migrate: true)
            try backfillV12Marker(in: container.mainContext, migrationID: migrationID)
        case 13:
            let container = try makeV13Container(at: modelStoreURL, migrate: true)
            try backfillV13Marker(in: container.mainContext, migrationID: migrationID)
        case 14:
            let container = try makeV14Container(at: modelStoreURL, migrate: true)
            try backfillV14Marker(in: container.mainContext, migrationID: migrationID)
        case 15:
            let container = try makeV15Container(at: modelStoreURL, migrate: true)
            try backfillV15Marker(in: container.mainContext, migrationID: migrationID)
        case 16:
            let container = try makeV16Container(at: modelStoreURL, migrate: true)
            try backfillV16Marker(in: container.mainContext, migrationID: migrationID)
        case 17:
            let container = try makeV17Container(at: modelStoreURL, migrate: true)
            try backfillV17Marker(in: container.mainContext, migrationID: migrationID)
        case 18:
            let container = try makeV18Container(at: modelStoreURL, migrate: true)
            try backfillV18Marker(in: container.mainContext, migrationID: migrationID)
        case 19:
            let container = try makeV19Container(at: modelStoreURL, migrate: true)
            try backfillV19Marker(in: container.mainContext, migrationID: migrationID)
        case 20:
            let container = try makeV20Container(at: modelStoreURL, migrate: true)
            try backfillV20Marker(in: container.mainContext, migrationID: migrationID)
        case 21:
            let container = try makeV21Container(at: modelStoreURL, migrate: true)
            try backfillV21Marker(in: container.mainContext, migrationID: migrationID)
        case 22:
            let container = try makeV22Container(at: modelStoreURL, migrate: true)
            try backfillV22Marker(in: container.mainContext, migrationID: migrationID)
        case 23:
            let container = try makeV23Container(at: modelStoreURL, migrate: true)
            try backfillV23Marker(in: container.mainContext, migrationID: migrationID)
        case 24:
            let container = try makeV24Container(at: modelStoreURL, migrate: true)
            try backfillV24Marker(in: container.mainContext, migrationID: migrationID)
        case 25:
            let container = try makeV25Container(at: modelStoreURL, migrate: true)
            try backfillV25Marker(in: container.mainContext, migrationID: migrationID)
        case 26:
            let container = try makeV26Container(at: modelStoreURL, migrate: true)
            try backfillV26Marker(in: container.mainContext, migrationID: migrationID)
        case 27:
            let container = try makeV27Container(at: modelStoreURL, migrate: true)
            try backfillV27Marker(in: container.mainContext, migrationID: migrationID)
        case 28:
            let container = try makeV28Container(at: modelStoreURL, migrate: true)
            try backfillV28Marker(in: container.mainContext, migrationID: migrationID)
        case 29:
            let container = try makeV29Container(at: modelStoreURL, migrate: true)
            try backfillV29Marker(in: container.mainContext, migrationID: migrationID)
        case 30:
            let container = try makeV30Container(at: modelStoreURL, migrate: true)
            try backfillV30Marker(in: container.mainContext, migrationID: migrationID)
        case 31:
            let container = try makeV31Container(at: modelStoreURL, migrate: true)
            try backfillV31Marker(in: container.mainContext, migrationID: migrationID)
        case 32:
            let container = try makeV32Container(at: modelStoreURL, migrate: true)
            try backfillV32Marker(in: container.mainContext, migrationID: migrationID)
        case 33:
            let container = try makeV33Container(at: modelStoreURL, migrate: true)
            try backfillV33Marker(in: container.mainContext, migrationID: migrationID)
        case 34:
            let container = try makeV34Container(at: modelStoreURL, migrate: true)
            try backfillV34Marker(in: container.mainContext, migrationID: migrationID)
        case 35:
            let container = try makeV35Container(at: modelStoreURL, migrate: true)
            try backfillV35Marker(in: container.mainContext, migrationID: migrationID)
        case 36:
            let container = try makeV36Container(at: modelStoreURL, migrate: true)
            try backfillV36Marker(in: container.mainContext, migrationID: migrationID)
        case 37:
            let container = try makeV37Container(at: modelStoreURL, migrate: true)
            try backfillV37Marker(in: container.mainContext, migrationID: migrationID)
        case 38:
            let container = try makeV38Container(at: modelStoreURL, migrate: true)
            try backfillV38Marker(in: container.mainContext, migrationID: migrationID)
        case 39:
            let container = try makeV39Container(at: modelStoreURL, migrate: true)
            try backfillV39Marker(in: container.mainContext, migrationID: migrationID)
        case 40:
            let container = try makeV40Container(at: modelStoreURL, migrate: true)
            try backfillV40Marker(in: container.mainContext, migrationID: migrationID)
        case 41:
            let container = try makeV41Container(at: modelStoreURL, migrate: true)
            try backfillV41Marker(in: container.mainContext, migrationID: migrationID)
        case 42:
            let container = try makeV42Container(at: modelStoreURL, migrate: true)
            try backfillV42Marker(in: container.mainContext, migrationID: migrationID)
        case 43:
            let container = try makeV43Container(at: modelStoreURL, migrate: true)
            try backfillV43Marker(in: container.mainContext, migrationID: migrationID)
        case 44:
            let container = try makeV44Container(at: modelStoreURL, migrate: true)
            try backfillV44Marker(in: container.mainContext, migrationID: migrationID)
        case 45:
            let container = try makeV45Container(at: modelStoreURL, migrate: true)
            try backfillV45Marker(in: container.mainContext, migrationID: migrationID)
        case 46:
            let container = try makeV46Container(at: modelStoreURL, migrate: true)
            try backfillV46Marker(in: container.mainContext, migrationID: migrationID)
        case 47:
            let container = try makeV47Container(at: modelStoreURL, migrate: true)
            try backfillV47Marker(in: container.mainContext, migrationID: migrationID)
        case 48:
            let container = try makeV48Container(at: modelStoreURL, migrate: true)
            try backfillV48Marker(in: container.mainContext, migrationID: migrationID)
        case 49:
            let container = try makeV49Container(at: modelStoreURL, migrate: true)
            try backfillV49Marker(in: container.mainContext, migrationID: migrationID)
        case 50:
            let container = try makeV50Container(at: modelStoreURL, migrate: true)
            try backfillV50Marker(in: container.mainContext, migrationID: migrationID)
        case 51:
            let container = try makeV51Container(at: modelStoreURL, migrate: true)
            try backfillV51Marker(in: container.mainContext, migrationID: migrationID)
        case 52:
            let container = try makeV52Container(at: modelStoreURL, migrate: true)
            try backfillV52Marker(in: container.mainContext, migrationID: migrationID)
        case 53:
            let container = try makeV53Container(at: modelStoreURL, migrate: true)
            try backfillV53Marker(in: container.mainContext, migrationID: migrationID)
        default:
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    @MainActor
    private func restoreBackfillWorkspaceID(
        in context: ModelContext,
        fallback: UUID
    ) throws -> UUID {
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>())
        if records.isEmpty { return fallback }
        var descriptor = FetchDescriptor<WorkspaceMutationStateRow>()
        descriptor.fetchLimit = 2
        let states = try context.fetch(descriptor)
        guard states.count == 1, let workspaceID = states.first?.workspaceID else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        return workspaceID
    }

    func installRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.installStagingGeneration(id: id)
    }

    @MainActor
    func createEmptyInstalledGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority,
        beforeStoreCreate: () throws -> Void = {}
    ) throws {
        var handle: StoreRestoreGenerationAuthority.InstalledGenerationHandle?
        do {
            let created = try authority.createInstalledGeneration(id: id)
            handle = created
            try beforeStoreCreate()
            try createAndReleaseEmptyContainer(
                at: try authority.modelStoreURL(
                    for: created,
                    name: Self.modelStoreName
                ),
                markerMigrationID: id
            )
            try authority.protectInstalledGeneration(id: id)
            try authority.requireRegularFile(
                named: Self.modelStoreName,
                in: created
            )
        } catch {
            if let handle {
                try? authority.removeCreatedInstalledGeneration(handle)
            }
            throw error
        }
    }

    func removeRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.removeStagingGeneration(id: id)
    }

    func removeInstalledGeneration(
        id: UUID,
        keeping currentID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard id != currentID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            guard try !registry.activeEpochs().contains(where: {
                $0.generationID == id
            }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try authority.removeInstalledGeneration(id: id)
        }
    }

    @MainActor
    func switchCurrentGeneration(
        expected oldID: UUID,
        to newID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try switchCurrentGenerationLocked(
                expected: oldID,
                to: newID,
                authority: authority
            )
        }
    }

    @MainActor
    private func switchCurrentGenerationLocked(
        expected oldID: UUID,
        to newID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let envelope = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        switch envelope {
        case .legacy:
            let pointer = try makeRestoreCurrentPointer(
                expectedOldID: oldID,
                newID: newID
            )
            try authority.switchCurrentGeneration(
                expected: oldID,
                to: newID,
                pointer: pointer
            )
        case .v2:
            let pointer = try makeRestoreCurrentPointer(
                expectedOldID: oldID,
                newID: newID
            )
            try authority.switchCurrentGeneration(
                expected: oldID,
                to: newID,
                pointer: pointer
            )
        case .v3(let current, _):
            let history = try current.knownReplicaIdentitySet()
            let prepared = try makeRestoreCurrentPointer(
                expectedOldID: oldID,
                newID: newID
            ).generationManifestSHA256
            let pointer = try makeRestoreCurrentPointerV3(
                expectedOldID: oldID,
                newID: newID,
                identity: try current.identity(),
                knownReplicaIDs: history,
                preparedGenerationManifestSHA256: prepared
            )
            try authority.switchCurrentGeneration(
                expected: oldID,
                to: newID,
                pointer: pointer,
                expectedCurrentPointer: current
            )
        }
        guard try currentGenerationID(authority: authority) == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    @MainActor
    func switchCurrentGeneration(
        expected oldID: UUID,
        to newID: UUID,
        expectedCurrentPointer: CurrentGenerationPointerV3,
        identity: WorkspaceReplicaIdentityV1,
        sourceReplicaID: ReplicaID? = nil,
        knownReplicaIDs: Set<ReplicaID> = [],
        preparedGenerationManifestSHA256: String,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try switchCurrentGenerationLocked(
                expected: oldID,
                to: newID,
                expectedCurrentPointer: expectedCurrentPointer,
                identity: identity,
                sourceReplicaID: sourceReplicaID,
                knownReplicaIDs: knownReplicaIDs,
                preparedGenerationManifestSHA256:
                    preparedGenerationManifestSHA256,
                authority: authority
            )
        }
    }

    @MainActor
    private func switchCurrentGenerationLocked(
        expected oldID: UUID,
        to newID: UUID,
        expectedCurrentPointer: CurrentGenerationPointerV3,
        identity: WorkspaceReplicaIdentityV1,
        sourceReplicaID: ReplicaID?,
        knownReplicaIDs: Set<ReplicaID>,
        preparedGenerationManifestSHA256: String,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard expectedCurrentPointer.generationID == canonicalString(for: oldID),
              try currentGenerationPointerV3(
                  expectedGenerationID: oldID,
                  authority: authority
              ) == expectedCurrentPointer else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard sourceReplicaID != identity.replicaID else {
            throw WorkspaceIdentityFailure.roleCollision
        }
        var history = knownReplicaIDs
        if let sourceReplicaID { history.insert(sourceReplicaID) }
        let pointer = try makeRestoreCurrentPointerV3(
            expectedOldID: oldID,
            newID: newID,
            identity: identity,
            knownReplicaIDs: history,
            preparedGenerationManifestSHA256:
                preparedGenerationManifestSHA256
        )
        if pointer.generationManifestSHA256 != preparedGenerationManifestSHA256 {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try authority.switchCurrentGeneration(
            expected: oldID,
            to: newID,
            pointer: pointer,
            expectedCurrentPointer: expectedCurrentPointer
        )
        guard try currentGenerationID(authority: authority) == newID,
              try currentWorkspaceIdentity(
                  expectedGenerationID: newID,
                  authority: authority
              ) == identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    @MainActor
    func switchCurrentGeneration(expected oldID: UUID, to newID: UUID) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try switchCurrentGenerationLocked(expected: oldID, to: newID)
        }
    }

    @MainActor
    private func switchCurrentGenerationLocked(
        expected oldID: UUID,
        to newID: UUID
    ) throws {
        guard oldID != newID,
              try currentGenerationID() == oldID,
              try itemType(at: installedGenerationURL(id: oldID)) == .typeDirectory,
              try itemType(at: installedGenerationURL(id: newID)) == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        ) {
        case .legacy:
            try replacePointerLocked(
                name: Self.currentPointerName,
                value: try makeRestoreCurrentPointer(
                    expectedOldID: oldID,
                    newID: newID
                )
            )
        case .v2:
            try replacePointerLocked(
                name: Self.currentPointerName,
                value: try makeRestoreCurrentPointer(
                    expectedOldID: oldID,
                    newID: newID
                )
            )
        case .v3(let current, _):
            let history = try current.knownReplicaIdentitySet()
            let prepared = try makeRestoreCurrentPointer(
                expectedOldID: oldID,
                newID: newID
            ).generationManifestSHA256
            try replacePointerLocked(
                name: Self.currentPointerName,
                value: try makeRestoreCurrentPointerV3(
                    expectedOldID: oldID,
                    newID: newID,
                    identity: try current.identity(),
                    knownReplicaIDs: history,
                    preparedGenerationManifestSHA256: prepared
                )
            )
        }
        guard try currentGenerationID() == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    @MainActor
    func switchCurrentGeneration(
        expected oldID: UUID,
        to newID: UUID,
        expectedCurrentPointer: CurrentGenerationPointerV3,
        identity: WorkspaceReplicaIdentityV1,
        sourceReplicaID: ReplicaID? = nil,
        knownReplicaIDs: Set<ReplicaID> = [],
        preparedGenerationManifestSHA256: String
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try switchCurrentGenerationLocked(
                expected: oldID,
                to: newID,
                expectedCurrentPointer: expectedCurrentPointer,
                identity: identity,
                sourceReplicaID: sourceReplicaID,
                knownReplicaIDs: knownReplicaIDs,
                preparedGenerationManifestSHA256:
                    preparedGenerationManifestSHA256
            )
        }
    }

    @MainActor
    private func switchCurrentGenerationLocked(
        expected oldID: UUID,
        to newID: UUID,
        expectedCurrentPointer: CurrentGenerationPointerV3,
        identity: WorkspaceReplicaIdentityV1,
        sourceReplicaID: ReplicaID?,
        knownReplicaIDs: Set<ReplicaID>,
        preparedGenerationManifestSHA256: String
    ) throws {
        guard expectedCurrentPointer.generationID == canonicalString(for: oldID),
              try currentGenerationPointerV3(
                  expectedGenerationID: oldID
              ) == expectedCurrentPointer else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard sourceReplicaID != identity.replicaID else {
            throw WorkspaceIdentityFailure.roleCollision
        }
        var history = knownReplicaIDs
        if let sourceReplicaID { history.insert(sourceReplicaID) }
        let pointer = try makeRestoreCurrentPointerV3(
            expectedOldID: oldID,
            newID: newID,
            identity: identity,
            knownReplicaIDs: history,
            preparedGenerationManifestSHA256:
                preparedGenerationManifestSHA256
        )
        if pointer.generationManifestSHA256 != preparedGenerationManifestSHA256 {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try replacePointerLocked(
            name: Self.currentPointerName,
            value: pointer,
            expectedData: try expectedCurrentPointer.canonicalData()
        )
        guard try currentGenerationID() == newID,
              try currentWorkspaceIdentity(expectedGenerationID: newID) == identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retireGeneration(
        oldID: UUID,
        currentID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try authority.retireGeneration(oldID: oldID, currentID: currentID)
        }
    }

    func replaceRetiredGenerationIDs(
        expected: [UUID],
        with replacement: [UUID],
        currentID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try authority.replaceRetiredGenerationIDs(
                expected: expected,
                with: replacement,
                currentID: currentID
            )
        }
    }

    @MainActor
    func retireGeneration(oldID: UUID, currentID: UUID) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try retireGenerationLocked(oldID: oldID, currentID: currentID)
        }
    }

    @MainActor
    private func retireGenerationLocked(
        oldID: UUID,
        currentID: UUID
    ) throws {
        guard oldID != currentID,
              try currentGenerationID() == currentID,
              try itemType(at: installedGenerationURL(id: oldID)) == .typeDirectory,
              try itemType(at: installedGenerationURL(id: currentID)) == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let retired = try retiredGenerationIDs()
        guard !retired.contains(currentID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let values = Array(Set(retired + [oldID])).sorted {
            canonicalString(for: $0) < canonicalString(for: $1)
        }
        let pointer = RetiredPointerV1(
            generationIDs: values.map { canonicalString(for: $0) },
            schemaVersion: StorePointerSchemaRegistry.retiredVersion
        )
        try replacePointerLocked(name: Self.retiredPointerName, value: pointer)
        guard try retiredGenerationIDs() == values else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retiredGenerationIDs() throws -> [UUID] {
        let authority = try makeRestoreGenerationAuthority()
        return try authority.retiredGenerationIDs()
    }

    @MainActor
    @discardableResult
    func reconcileGenerationLeasesAndPrune(
        policy: GenerationPrunePolicyV1 = .production
    ) throws -> GenerationPruneReceiptV1 {
        try policy.validate()
        let registry = try makeGenerationLeaseRegistry()
        return try registry.withExclusiveGenerationMutationLock {
            var ownershipIsCertain = true
            do {
                _ = try registry.reconcileAbandonedOwners()
            } catch let failure as GenerationLeaseRegistryFailureV1
                where failure == .uncertainOwner {
                ownershipIsCertain = false
            }

            if let intent = try registry.loadPruneIntent() {
                return try recoverPruneLocked(intent, registry: registry)
            }

            let currentEpoch = try currentGenerationEpoch()
            let authority = try makeRestoreGenerationAuthority()
            let retiredIDs = try authority.retiredGenerationIDs()
            let activeEpochs: Set<GenerationEpochV1>
            var leaseInventoryIsReadable = true
            do {
                activeEpochs = try registry.activeEpochs()
            } catch {
                guard !ownershipIsCertain else { throw error }
                activeEpochs = []
                leaseInventoryIsReadable = false
            }
            let store = try StoreMigrationJournalStoreV1(
                applicationSupportURL: applicationSupportURL
            )
            var acceptedRetired: [GenerationEpochV1] = []
            var uncertainIDs: [UUID] = []
            let expectedNames = Set(
                ([currentEpoch.generationID] + retiredIDs).map {
                    canonicalString(for: $0)
                }
            )
            let actualNames = Set(try authority.installedGenerationNames())
            if actualNames != expectedNames {
                ownershipIsCertain = false
                let difference = actualNames.symmetricDifference(expectedNames)
                let uncertainDifference = difference.compactMap {
                    canonicalUUID(from: $0)
                }
                guard uncertainDifference.count == difference.count else {
                    throw GenerationLeaseRegistryFailureV1.invalidIdentity
                }
                uncertainIDs.append(contentsOf: uncertainDifference)
            }
            for id in retiredIDs {
                do {
                    guard let epoch = try acceptedGenerationEpoch(
                        id: id,
                        store: store
                    ) else {
                        uncertainIDs.append(id)
                        continue
                    }
                    acceptedRetired.append(epoch)
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                    uncertainIDs.append(id)
                }
            }
            acceptedRetired.sort(by: Self.epochOrder)
            uncertainIDs = Array(Set(uncertainIDs)).sorted(by: Self.idOrder)

            if !ownershipIsCertain {
                let durableLeaseGenerationIDs = activeEpochs.map(\.generationID)
                if leaseInventoryIsReadable,
                   !durableLeaseGenerationIDs.isEmpty {
                    uncertainIDs.append(contentsOf: durableLeaseGenerationIDs)
                } else {
                    uncertainIDs.append(currentEpoch.generationID)
                    uncertainIDs.append(contentsOf: retiredIDs)
                    uncertainIDs.append(contentsOf: actualNames.compactMap {
                        canonicalUUID(from: $0)
                    })
                }
                uncertainIDs = Array(Set(uncertainIDs)).sorted(by: Self.idOrder)
            }

            let knownEpochs = Set(acceptedRetired + [currentEpoch])
            if activeEpochs.contains(where: { !knownEpochs.contains($0) }) {
                ownershipIsCertain = false
                uncertainIDs = Array(Set(
                    uncertainIDs + activeEpochs
                        .filter { !knownEpochs.contains($0) }
                        .map(\.generationID)
                )).sorted(by: Self.idOrder)
            }
            let activeRetired = acceptedRetired.filter(activeEpochs.contains)
            let inactive = acceptedRetired.filter { !activeEpochs.contains($0) }
            let retainCount = min(
                policy.retainedInactiveAcceptedGenerationCount,
                inactive.count
            )
            let retainedInactive = Array(inactive.suffix(retainCount))
            let candidates = Array(inactive.dropLast(retainCount))
            let retainedRetired = (activeRetired + retainedInactive)
                .sorted(by: Self.epochOrder)
            let retainedEpochs = ([currentEpoch] + retainedRetired)
                .sorted(by: Self.epochOrder)
            let activeRetained = retainedEpochs.filter(activeEpochs.contains)
            let acceptedGenerationIDs = Set(
                ([currentEpoch] + acceptedRetired).map(\.generationID)
            )
            let receiptUncertainIDs = uncertainIDs.filter {
                !acceptedGenerationIDs.contains($0)
            }
            let beforeDigest = try pruneInventoryDigest(
                currentEpoch: currentEpoch,
                retiredEpochs: acceptedRetired,
                activeEpochs: activeEpochs,
                uncertainGenerationIDs: uncertainIDs
            )

            guard policy.pruningEnabled else {
                let receipt = try GenerationPruneReceiptV1(
                    operationID: UUID(),
                    currentEpoch: currentEpoch,
                    retainedEpochs: ([currentEpoch] + acceptedRetired)
                        .sorted(by: Self.epochOrder),
                    prunedEpochs: [],
                    activeRetainedEpochs: activeRetained,
                    uncertainRetainedGenerationIDs: receiptUncertainIDs,
                    inventoryBeforeSHA256: beforeDigest,
                    inventoryAfterSHA256: beforeDigest,
                    disposition: .disabledRetainAll
                )
                try registry.publishPruneReceipt(receipt)
                return receipt
            }
            guard ownershipIsCertain, uncertainIDs.isEmpty else {
                let receipt = try GenerationPruneReceiptV1(
                    operationID: UUID(),
                    currentEpoch: currentEpoch,
                    retainedEpochs: ([currentEpoch] + acceptedRetired)
                        .sorted(by: Self.epochOrder),
                    prunedEpochs: [],
                    activeRetainedEpochs: activeRetained,
                    uncertainRetainedGenerationIDs: receiptUncertainIDs,
                    ownerLivenessUncertain: !ownershipIsCertain,
                    inventoryBeforeSHA256: beforeDigest,
                    inventoryAfterSHA256: beforeDigest,
                    disposition: .uncertainRetainAll
                )
                try registry.publishPruneReceipt(receipt)
                return receipt
            }
            guard !candidates.isEmpty else {
                let receipt = try GenerationPruneReceiptV1(
                    operationID: UUID(),
                    currentEpoch: currentEpoch,
                    retainedEpochs: retainedEpochs,
                    prunedEpochs: [],
                    activeRetainedEpochs: activeRetained,
                    uncertainRetainedGenerationIDs: [],
                    inventoryBeforeSHA256: beforeDigest,
                    inventoryAfterSHA256: beforeDigest,
                    disposition: .noEligibleGenerations
                )
                try registry.publishPruneReceipt(receipt)
                return receipt
            }

            let desiredRetiredIDs = retainedRetired.map(\.generationID)
                .sorted(by: Self.idOrder)
            let intent = try GenerationPruneIntentV1(
                operationID: UUID(),
                currentEpoch: currentEpoch,
                candidateEpochs: candidates,
                retainedEpochs: retainedEpochs,
                activeRetainedEpochs: activeRetained,
                uncertainRetainedGenerationIDs: [],
                inventoryBeforeSHA256: beforeDigest,
                expectedRetiredGenerationIDs: retiredIDs,
                desiredRetiredGenerationIDs: desiredRetiredIDs
            )
            try registry.createPruneIntent(intent)
            try reachPruneBoundary(.prepared)
            return try recoverPruneLocked(intent, registry: registry)
        }
    }

    @MainActor
    private func recoverPruneLocked(
        _ initialIntent: GenerationPruneIntentV1,
        registry: GenerationLeaseRegistryV1
    ) throws -> GenerationPruneReceiptV1 {
        var intent = initialIntent
        guard try currentGenerationEpoch() == intent.currentEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        let activeEpochs = try registry.activeEpochs()
        let candidateIDs = Set(intent.candidateEpochs.map(\.generationID))
        guard activeEpochs.allSatisfy({ !candidateIDs.contains($0.generationID) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let authority = try makeRestoreGenerationAuthority()
        let retiredIDs = try authority.retiredGenerationIDs()
        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )

        if intent.phase == .prepared {
            guard retiredIDs == intent.expectedRetiredGenerationIDs else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            for epoch in intent.candidateEpochs {
                try quarantineAndRemovePruneCandidate(
                    epoch,
                    operationID: intent.operationID,
                    store: store
                )
                if let manifest = try store.loadManifestIfPresent(
                    targetGenerationID: epoch.generationID
                ) {
                    guard manifest.digest == epoch.generationManifestSHA256 else {
                        throw GenerationLeaseRegistryFailureV1.corruptRegistry
                    }
                    try store.removeManifest(
                        targetGenerationID: epoch.generationID,
                        expectedDigest: manifest.digest
                    )
                }
            }
            let next = try intent.advancing(to: .bytesRemoved)
            try registry.replacePruneIntent(expected: intent, with: next)
            intent = next
            try reachPruneBoundary(.bytesRemoved)
        }

        if intent.phase == .bytesRemoved {
            guard intent.candidateEpochs.allSatisfy({
                (try? itemType(at: installedGenerationURL(id: $0.generationID))) == nil
            }) else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            let currentRetired = try authority.retiredGenerationIDs()
            if currentRetired == intent.expectedRetiredGenerationIDs {
                try replacePointerLocked(
                    name: Self.retiredPointerName,
                    value: RetiredPointerV1(
                        generationIDs: intent.desiredRetiredGenerationIDs.map {
                            canonicalString(for: $0)
                        },
                        schemaVersion: StorePointerSchemaRegistry.retiredVersion
                    )
                )
            } else if currentRetired != intent.desiredRetiredGenerationIDs {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            let next = try intent.advancing(to: .retiredPointerPublished)
            try registry.replacePruneIntent(expected: intent, with: next)
            intent = next
            try reachPruneBoundary(.retiredPointerPublished)
        }

        if intent.phase == .retiredPointerPublished {
            guard try authority.retiredGenerationIDs()
                    == intent.desiredRetiredGenerationIDs else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            let next = try intent.advancing(to: .receiptPublished)
            try registry.replacePruneIntent(expected: intent, with: next)
            intent = next
            try reachPruneBoundary(.receiptPublished)
        }

        let afterDigest = try pruneInventoryDigest(
            currentEpoch: intent.currentEpoch,
            retiredEpochs: intent.retainedEpochs.filter {
                $0.generationID != intent.currentEpoch.generationID
            },
            activeEpochs: activeEpochs,
            uncertainGenerationIDs: intent.uncertainRetainedGenerationIDs
        )
        let receipt = try GenerationPruneReceiptV1(
            operationID: intent.operationID,
            currentEpoch: intent.currentEpoch,
            retainedEpochs: intent.retainedEpochs,
            prunedEpochs: intent.candidateEpochs,
            activeRetainedEpochs: intent.activeRetainedEpochs,
            uncertainRetainedGenerationIDs:
                intent.uncertainRetainedGenerationIDs,
            inventoryBeforeSHA256: intent.inventoryBeforeSHA256,
            inventoryAfterSHA256: afterDigest,
            disposition: .pruned
        )
        try registry.publishPruneReceipt(receipt, completing: intent)
        return receipt
    }

    @MainActor
    private func acceptedGenerationEpoch(
        id: UUID,
        store: StoreMigrationJournalStoreV1,
        expectedRootIdentity: StoreRestoreGenerationAuthority.Identity? = nil
    ) throws -> GenerationEpochV1? {
        guard let loaded = try store.loadManifestIfPresent(
            targetGenerationID: id
        ) else {
            return nil
        }
        let root = installedGenerationURL(id: id)
        guard try itemType(at: root) == .typeDirectory,
              loaded.manifest.generationID == id else {
            return nil
        }
        try protectGeneration(at: root, staging: false, requireModel: true)
        let descriptor = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(descriptor) }
        let provedIdentity = try StoreRestoreGenerationAuthority
            .directoryIdentity(descriptor: descriptor)
        guard expectedRootIdentity.map({ $0 == provedIdentity }) ?? true else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        try verifyOwnedDirectory(at: root, descriptor: descriptor)
        _ = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: true
        )
        let modelURL = root.appendingPathComponent(Self.modelStoreName)
        // A V4 manifest is the immutable logical-lineage authority, while its
        // SQLite bytes and sidecars are intentionally mutable. Install-time
        // file/inode identity cannot be a semantic anchor: normal WAL/SHM
        // lifecycle and a legitimate backup/replace restore assign new
        // identities. V4 therefore proves the manifest-bound schema and
        // migration marker plus the unique workspace/replica state and its
        // canonical mutable semantics below. Physical identity is only a
        // local TOCTOU boundary: it starts at `provedIdentity` and, for prune,
        // must match the descriptor identity consumed by quarantine removal.
        if loaded.manifest.storeSchemaRelease != .v4,
           loaded.manifest.storeSchemaRelease != .v5,
           loaded.manifest.storeSchemaRelease != .v6,
           loaded.manifest.storeSchemaRelease != .v7,
           loaded.manifest.storeSchemaRelease != .v8,
           loaded.manifest.storeSchemaRelease != .v9,
           loaded.manifest.storeSchemaRelease != .v10,
           loaded.manifest.storeSchemaRelease != .v11 {
            let observedFiles = try generationFileDigests(
                at: root,
                durable: true
            )
            guard observedFiles == loaded.manifest.files,
                  loaded.manifest.frozenIdentityDigest
                    == (try frozenIdentityDigest(for: root)),
                  loaded.manifest.semanticSHA256
                    == (try semanticDigest(
                        at: modelURL,
                        release: loaded.manifest.storeSchemaRelease
                    )) else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
        }
        try autoreleasepool {
            let container: ModelContainer
            switch loaded.manifest.storeSchemaRelease {
            case .v1:
                container = try makeV1Container(at: modelURL)
            case .v2:
                container = try makeV2Container(at: modelURL, migrate: false)
                _ = try requireV2Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
            case .v3:
                container = try makeV3Container(at: modelURL, migrate: false)
                _ = try requireV3Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
            case .v4:
                container = try makeV4Container(at: modelURL, migrate: false)
                _ = try requireV4Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
                let states = try container.mainContext.fetch(
                    FetchDescriptor<WorkspaceMutationStateRow>()
                )
                guard states.count == 1,
                      let state = states.first,
                      state.generationID == id else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                let identity = try WorkspaceReplicaIdentityV1(
                    workspaceID: WorkspaceID(rawValue: state.workspaceID),
                    replicaID: ReplicaID(rawValue: state.activeReplicaID)
                )
                let journal = try MutationJournalStoreV1(
                    modelContext: container.mainContext,
                    identity: identity,
                    generationID: id,
                    allowStateBootstrap: false
                )
                try journal.validateAll()
            case .v5:
                container = try makeV5Container(at: modelURL, migrate: false)
                _ = try requireV5Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
                _ = try semanticExportV5(in: container.mainContext)
                let states = try container.mainContext.fetch(
                    FetchDescriptor<WorkspaceMutationStateRow>()
                )
                guard states.count == 1,
                      let state = states.first,
                      state.generationID == id else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                let identity = try WorkspaceReplicaIdentityV1(
                    workspaceID: WorkspaceID(rawValue: state.workspaceID),
                    replicaID: ReplicaID(rawValue: state.activeReplicaID)
                )
                let journal = try MutationJournalStoreV1(
                    modelContext: container.mainContext,
                    identity: identity,
                    generationID: id,
                    allowStateBootstrap: false
                )
                try journal.validateAll()
            case .v6:
                container = try makeV6Container(at: modelURL, migrate: false)
                _ = try requireV6Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
                _ = try semanticExportV6(in: container.mainContext)
            case .v7:
                container = try makeV7Container(at: modelURL, migrate: false)
                _ = try requireV7Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
                _ = try semanticExportV7(in: container.mainContext)
            case .v8:
                container = try makeV8Container(at: modelURL, migrate: false)
                _ = try requireV8Marker(
                    in: container.mainContext,
                    expectedMigrationID: loaded.manifest.migrationID
                )
                _ = try semanticExportV8(in: container.mainContext)
                let states = try container.mainContext.fetch(
                    FetchDescriptor<WorkspaceMutationStateRow>()
                )
                guard states.count == 1,
                      let state = states.first,
                      state.generationID == id else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
            case .v9:
                container = try makeV9Container(at: modelURL, migrate: false)
                _ = try requireV9Marker(in: container.mainContext, expectedMigrationID: loaded.manifest.migrationID)
            case .v10:
                container = try makeV10Container(at: modelURL, migrate: false)
                _ = try requireV10Marker(in: container.mainContext, expectedMigrationID: loaded.manifest.migrationID)
                _ = try semanticExportV9(in: container.mainContext)
                let states = try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                guard states.count == 1, let state = states.first, state.generationID == id else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                let identity = try WorkspaceReplicaIdentityV1(
                    workspaceID: WorkspaceID(rawValue: state.workspaceID),
                    replicaID: ReplicaID(rawValue: state.activeReplicaID)
                )
                let journal = try MutationJournalStoreV1(
                    modelContext: container.mainContext,
                    identity: identity,
                    generationID: id,
                    allowStateBootstrap: false
                )
                try journal.validateAll()
            case .v11:
                container = try makeV11Container(at: modelURL, migrate: false)
                _ = try requireV11Marker(in: container.mainContext, expectedMigrationID: loaded.manifest.migrationID)
                _ = try semanticExportV11(in: container.mainContext)
                let states = try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                guard states.count == 1, let state = states.first, state.generationID == id else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                let identity = try WorkspaceReplicaIdentityV1(
                    workspaceID: WorkspaceID(rawValue: state.workspaceID),
                    replicaID: ReplicaID(rawValue: state.activeReplicaID)
                )
                let journal = try MutationJournalStoreV1(
                    modelContext: container.mainContext,
                    identity: identity,
                    generationID: id,
                    allowStateBootstrap: false
                )
                try journal.validateAll()
            case .v12:
                container = try makeV12Container(at: modelURL, migrate: false)
                _ = try requireV12Marker(in: container.mainContext, expectedMigrationID: loaded.manifest.migrationID)
                _ = try semanticExportV12(in: container.mainContext)
                let states = try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                guard states.count == 1, let state = states.first, state.generationID == id else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                let identity = try WorkspaceReplicaIdentityV1(
                    workspaceID: WorkspaceID(rawValue: state.workspaceID),
                    replicaID: ReplicaID(rawValue: state.activeReplicaID)
                )
                let journal = try MutationJournalStoreV1(
                    modelContext: container.mainContext, identity: identity,
                    generationID: id, allowStateBootstrap: false
                )
                try journal.validateAll()
            case .v13:
                container=try makeV13Container(at:modelURL,migrate:false);_ = try requireV13Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV13(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v14:
                container=try makeV14Container(at:modelURL,migrate:false);_ = try requireV14Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV14(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v15:
                container=try makeV15Container(at:modelURL,migrate:false);_ = try requireV15Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV15(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v16:
                container=try makeV16Container(at:modelURL,migrate:false);_ = try requireV16Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV16(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v17:
                container=try makeV17Container(at:modelURL,migrate:false);_ = try requireV17Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV17(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v18:
                container=try makeV18Container(at:modelURL,migrate:false);_ = try requireV18Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV18(in:container.mainContext)
            case .v19:
                container=try makeV19Container(at:modelURL,migrate:false);_ = try requireV19Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV19(in:container.mainContext)
            case .v20:
                container=try makeV20Container(at:modelURL,migrate:false);_ = try requireV20Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV20(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v21:
                container=try makeV21Container(at:modelURL,migrate:false);_ = try requireV21Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV21(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v22:
                container=try makeV22Container(at:modelURL,migrate:false);_ = try requireV22Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV22(in:container.mainContext)
            case .v23:
                container=try makeV23Container(at:modelURL,migrate:false);_ = try requireV23Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV23(in:container.mainContext)
            case .v24:
                container=try makeV24Container(at:modelURL,migrate:false);_ = try requireV24Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV24(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v25:
                container=try makeV25Container(at:modelURL,migrate:false);_ = try requireV25Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV25(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v26:
                container=try makeV26Container(at:modelURL,migrate:false);_ = try requireV26Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV26(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v27:
                container=try makeV27Container(at:modelURL,migrate:false);_ = try requireV27Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV27(in:container.mainContext)
            case .v28:
                container=try makeV28Container(at:modelURL,migrate:false);_ = try requireV28Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV28(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v29:
                container=try makeV29Container(at:modelURL,migrate:false);_ = try requireV29Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV29(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v30:
                container=try makeV30Container(at:modelURL,migrate:false);_ = try requireV30Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV30(in:container.mainContext)
            case .v31:
                container=try makeV31Container(at:modelURL,migrate:false);_ = try requireV31Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV31(in:container.mainContext)
            case .v32:
                container=try makeV32Container(at:modelURL,migrate:false);_ = try requireV32Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV32(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v33:
                container=try makeV33Container(at:modelURL,migrate:false);_ = try requireV33Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV33(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v34:
                container=try makeV34Container(at:modelURL,migrate:false);_ = try requireV34Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV34(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v35:
                container=try makeV35Container(at:modelURL,migrate:false);_ = try requireV35Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV35(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
            case .v36:
                container=try makeV36Container(at:modelURL,migrate:false);_ = try requireV36Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV36(in:container.mainContext)
                let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v37:
                 container=try makeV37Container(at:modelURL,migrate:false);_ = try requireV37Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV37(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v38:
                 container=try makeV38Container(at:modelURL,migrate:false);_ = try requireV38Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV38(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v39:
                 container=try makeV39Container(at:modelURL,migrate:false);_ = try requireV39Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV39(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v40:
                 container=try makeV40Container(at:modelURL,migrate:false);_ = try requireV40Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV40(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v41:
                 container=try makeV41Container(at:modelURL,migrate:false);_ = try requireV41Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV41(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v42:
                 container=try makeV42Container(at:modelURL,migrate:false);_ = try requireV42Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV42(in:container.mainContext)
             case .v43:
                 container=try makeV43Container(at:modelURL,migrate:false);_ = try requireV43Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV43(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v44:
                 container=try makeV44Container(at:modelURL,migrate:false);_ = try requireV44Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV44(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v45:
                 container=try makeV45Container(at:modelURL,migrate:false);_ = try requireV45Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV45(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v46:
                 container=try makeV46Container(at:modelURL,migrate:false);_ = try requireV46Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV46(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v47:
                 container=try makeV47Container(at:modelURL,migrate:false);_ = try requireV47Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV47(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v48:
                 container=try makeV48Container(at:modelURL,migrate:false);_ = try requireV48Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV48(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v49:
                 container=try makeV49Container(at:modelURL,migrate:false);_ = try requireV49Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV49(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v50:
                 container=try makeV50Container(at:modelURL,migrate:false);_ = try requireV50Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV50(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v51:
                 container=try makeV51Container(at:modelURL,migrate:false);_ = try requireV51Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV51(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             case .v52:
                 container=try makeV52Container(at:modelURL,migrate:false);_ = try requireV52Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV52(in:container.mainContext)
             case .v53:
                 container=try makeV53Container(at:modelURL,migrate:false);_ = try requireV53Marker(in:container.mainContext,expectedMigrationID:loaded.manifest.migrationID);_ = try semanticExportV53(in:container.mainContext)
                 let states=try container.mainContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>());guard states.count==1,let state=states.first,state.generationID==id else{throw GenerationLeaseRegistryFailureV1.corruptRegistry};let identity=try WorkspaceReplicaIdentityV1(workspaceID:WorkspaceID(rawValue:state.workspaceID),replicaID:ReplicaID(rawValue:state.activeReplicaID));let journal=try MutationJournalStoreV1(modelContext:container.mainContext,identity:identity,generationID:id,allowStateBootstrap:false);try journal.validateAll()
             }
        }
        try verifyOwnedDirectory(at: root, descriptor: descriptor)
        guard try StoreRestoreGenerationAuthority.directoryIdentity(
                  descriptor: descriptor
              ) == provedIdentity else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        if loaded.manifest.storeSchemaRelease != .v4,
           loaded.manifest.storeSchemaRelease != .v5,
           loaded.manifest.storeSchemaRelease != .v6,
           loaded.manifest.storeSchemaRelease != .v7,
           loaded.manifest.storeSchemaRelease != .v8,
           loaded.manifest.storeSchemaRelease != .v9,
           loaded.manifest.storeSchemaRelease != .v10,
           loaded.manifest.storeSchemaRelease != .v11,
           loaded.manifest.frozenIdentityDigest
            != (try frozenIdentityDigest(for: root)) {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        return try GenerationEpochV1(
            generationID: id,
            generationManifestSHA256: loaded.digest
        )
    }

    private func quarantineAndRemovePruneCandidate(
        _ epoch: GenerationEpochV1,
        operationID: UUID,
        store: StoreMigrationJournalStoreV1
    ) throws {
        let parent = try openOwnedDirectory(at: generationsURL)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: generationsURL, descriptor: parent)
        let sourceName = canonicalString(for: epoch.generationID)
        let prefix = ".prune-\(canonicalString(for: operationID))-\(sourceName)-"
        let existing = try StoreRestoreGenerationAuthority.names(in: parent)
            .filter { $0.hasPrefix(prefix) }
        guard existing.count <= 1 else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }

        let quarantineName: String
        let expectedIdentity: StoreRestoreGenerationAuthority.Identity
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: sourceName
        ) {
            guard existing.isEmpty else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            let source = Darwin.openat(
                parent,
                sourceName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard source >= 0 else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            defer { _ = Darwin.close(source) }
            expectedIdentity = try StoreRestoreGenerationAuthority
                .directoryIdentity(descriptor: source)
            guard let provedEpoch = try acceptedGenerationEpoch(
                id: epoch.generationID,
                store: store,
                expectedRootIdentity: expectedIdentity
            ), provedEpoch == epoch,
                  try StoreRestoreGenerationAuthority.requiredDirectoryIdentity(
                      parent: parent,
                      name: sourceName
                  ) == expectedIdentity else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            quarantineName = "\(prefix)\(expectedIdentity.device)-\(expectedIdentity.inode)"
            guard Darwin.renameatx_np(
                parent,
                sourceName,
                parent,
                quarantineName,
                UInt32(RENAME_EXCL)
            ) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            let renamedIdentity = try StoreRestoreGenerationAuthority
                .requiredDirectoryIdentity(parent: parent, name: quarantineName)
            guard renamedIdentity == expectedIdentity else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            try removeQuarantinedGeneration(
                parent: parent,
                name: quarantineName,
                expectedIdentity: expectedIdentity
            )
            return
        }

        guard let recoveredName = existing.first,
              let recoveredIdentity = pruneQuarantineIdentity(
                  name: recoveredName,
                  prefix: prefix
              ) else {
            // Neither source nor quarantine exists: a prior attempt completed
            // byte removal before it could advance the durable intent.
            return
        }
        quarantineName = recoveredName
        expectedIdentity = recoveredIdentity
        try removeQuarantinedGeneration(
            parent: parent,
            name: quarantineName,
            expectedIdentity: expectedIdentity
        )
    }

    private func removeQuarantinedGeneration(
        parent: Int32,
        name: String,
        expectedIdentity: StoreRestoreGenerationAuthority.Identity
    ) throws {
        guard try StoreRestoreGenerationAuthority.requiredDirectoryIdentity(
            parent: parent,
            name: name
        ) == expectedIdentity else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        ) == expectedIdentity else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        let names = try StoreRestoreGenerationAuthority.names(in: descriptor)
        guard Set(names).isSubset(
            of: StoreRestoreGenerationAuthority.generationStoreNames
        ) else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
        for childName in names {
            let captured = try StoreRestoreGenerationAuthority
                .regularFileIdentity(parent: descriptor, name: childName)
            guard captured.linkCount == 1,
                  try StoreRestoreGenerationAuthority.regularFileIdentity(
                      parent: descriptor,
                      name: childName
                  ) == captured,
                  Darwin.unlinkat(descriptor, childName, 0) == 0 else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
        }
        guard Darwin.fsync(descriptor) == 0,
              try StoreRestoreGenerationAuthority.requiredDirectoryIdentity(
                  parent: parent,
                  name: name
              ) == expectedIdentity,
              Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0,
              Darwin.fsync(parent) == 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
    }

    private func pruneQuarantineIdentity(
        name: String,
        prefix: String
    ) -> StoreRestoreGenerationAuthority.Identity? {
        guard name.hasPrefix(prefix) else { return nil }
        let components = name.dropFirst(prefix.count).split(separator: "-")
        guard components.count == 2,
              let device = UInt64(components[0]),
              let inode = UInt64(components[1]) else {
            return nil
        }
        return StoreRestoreGenerationAuthority.Identity(
            device: dev_t(device),
            inode: ino_t(inode)
        )
    }

    private func pruneInventoryDigest(
        currentEpoch: GenerationEpochV1,
        retiredEpochs: [GenerationEpochV1],
        activeEpochs: Set<GenerationEpochV1>,
        uncertainGenerationIDs: [UUID]
    ) throws -> String {
        let inventory = StoreGenerationPruneInventoryV1(
            currentEpoch: currentEpoch,
            retiredEpochs: retiredEpochs.sorted(by: Self.epochOrder),
            activeEpochs: activeEpochs.sorted(by: Self.epochOrder),
            uncertainGenerationIDs: uncertainGenerationIDs.sorted(
                by: Self.idOrder
            )
        )
        return StoreMigrationCanonicalJSONV1.sha256(
            try StoreMigrationCanonicalJSONV1.encode(inventory)
        )
    }

    private static func epochOrder(
        _ lhs: GenerationEpochV1,
        _ rhs: GenerationEpochV1
    ) -> Bool {
        idOrder(lhs.generationID, rhs.generationID)
    }

    private static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    @MainActor
    func openInstalledGeneration(id: UUID) throws -> StoreGenerationSession {
        try openInstalledGeneration(
            id: id,
            authority: makeRestoreGenerationAuthority()
        )
    }

    @MainActor
    func openInstalledGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        let currentBefore = try authority.currentGenerationID()
        let identity = try installedOpenIdentity(
            id: id,
            currentGenerationID: currentBefore
        )
        let session = try openGeneration(
            id: id,
            at: installedGenerationURL(id: id),
            identity: identity
        )
        try authority.protectInstalledGeneration(id: id)
        try authority.requireInstalledGeneration(id: id)
        guard try authority.currentGenerationID() == currentBefore else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return session
    }

    @MainActor
    func openInstalledGeneration(
        id: UUID,
        identity: WorkspaceReplicaIdentityV1,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        let session = try openGeneration(
            id: id,
            at: installedGenerationURL(id: id),
            identity: identity
        )
        try authority.protectInstalledGeneration(id: id)
        try authority.requireInstalledGeneration(id: id)
        return session
    }

    @MainActor
    private func installedOpenIdentity(
        id: UUID,
        currentGenerationID: UUID
    ) throws -> WorkspaceReplicaIdentityV1 {
        guard id == currentGenerationID else {
            return pointerEnrichmentIdentity
        }
        let envelope = try decodeCurrentPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        guard canonicalUUID(from: envelope.generationID) == id else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch envelope {
        case .legacy:
            return pointerEnrichmentIdentity
        case .v2(let pointer, _):
            return try compatibilityIdentity(for: pointer)
        case .v3(let pointer, _):
            _ = try requireCurrentManifest(pointer)
            return try pointer.identity()
        }
    }

    @MainActor
    func openRestoreStagingGeneration(id: UUID) throws -> StoreGenerationSession {
        try openGeneration(id: id, at: restoreStagingGenerationURL(id: id))
    }

    @MainActor
    func openRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        try authority.requireStagingGeneration(id: id)
        try authority.protectStagingGeneration(id: id)
        let session = try openGeneration(id: id, at: restoreStagingGenerationURL(id: id))
        try authority.protectStagingGeneration(id: id)
        try authority.requireStagingGeneration(id: id)
        return session
    }

    @MainActor
    func openRestoreStagingGeneration(
        id: UUID,
        identity: WorkspaceReplicaIdentityV1,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        try authority.requireStagingGeneration(id: id)
        try authority.protectStagingGeneration(id: id)
        let session = try openGeneration(
            id: id,
            at: restoreStagingGenerationURL(id: id),
            identity: identity
        )
        try authority.protectStagingGeneration(id: id)
        try authority.requireStagingGeneration(id: id)
        return session
    }

    static func backupImportStagingDirectory(
        containing generationRootURL: URL
    ) throws -> URL {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        guard root.isFileURL,
              generations.lastPathComponent == Self.generationsDirectoryName,
              dataRoot.lastPathComponent == Self.dataDirectoryName,
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return dataRoot.deletingLastPathComponent()
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
    }

    private var dataRootURL: URL {
        applicationSupportURL.appendingPathComponent(
            Self.dataDirectoryName,
            isDirectory: true
        )
    }

    private var generationsURL: URL {
        dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
    }

    private func openOwnedDirectory(at url: URL) throws -> Int32 {
        let root = applicationSupportURL.standardizedFileURL
        let target = url.standardizedFileURL
        let insideRoot = target.path == root.path ||
            (root.path == "/"
                ? target.path.hasPrefix("/")
                : target.path.hasPrefix(root.path + "/"))
        guard root.isFileURL, target.isFileURL, insideRoot else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let relativePath = String(target.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relativePath.isEmpty
            ? []
            : relativePath.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        var descriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        for component in components {
            let next = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard next >= 0 else {
                _ = Darwin.close(descriptor)
                throw StoreGenerationFailure.dataPointerInvalid
            }
            _ = Darwin.close(descriptor)
            descriptor = next
        }
        return descriptor
    }

    private func verifyOwnedDirectory(
        at url: URL,
        descriptor: Int32
    ) throws {
        var expected = stat()
        guard Darwin.fstat(descriptor, &expected) == 0,
              (expected.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reopened = try openOwnedDirectory(at: url)
        defer { _ = Darwin.close(reopened) }
        var actual = stat()
        guard Darwin.fstat(reopened, &actual) == 0,
              (actual.st_mode & S_IFMT) == S_IFDIR,
              actual.st_dev == expected.st_dev,
              actual.st_ino == expected.st_ino else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func removeOwnedEntry(parent: Int32, name: String) throws {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
            guard Darwin.unlinkat(parent, name, 0) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        case S_IFREG:
            guard info.st_nlink == 1,
                  Darwin.unlinkat(parent, name, 0) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        case S_IFDIR:
            let child = Darwin.openat(
                parent,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard child >= 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            do {
                for childName in try StoreRestoreGenerationAuthority.names(in: child) {
                    try removeOwnedEntry(parent: child, name: childName)
                }
            } catch {
                _ = Darwin.close(child)
                throw error
            }
            _ = Darwin.close(child)
            guard Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        default:
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func createOwnedDirectory(parent: Int32, name: String) throws -> Int32 {
        guard Darwin.mkdirat(parent, name, mode_t(0o700)) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return descriptor
    }

    private func protect(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        do {
            let root = applicationSupportURL.standardizedFileURL
            let target = url.standardizedFileURL
            let insideRoot = root.path == "/"
                ? target.path.hasPrefix("/")
                : target.path.hasPrefix(root.path + "/")
            guard insideRoot else {
                throw ProtectedFilePolicyError.invalidRelativePath
            }
            let relativePath = String(target.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: relativePath,
                within: root,
                authorityCheck: authorityCheck
            )
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch let error as ProtectedFilePolicyError
            where error == .protectedDataUnavailable {
            throw error
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func protectGenerationFile(
        descriptor: Int32,
        root: URL,
        name: String,
        kind: OwnedFileKindV1
    ) throws {
        try StoreRestoreGenerationAuthority.requireSafeBasename(name)
        let generationIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        let fileDescriptor = Darwin.openat(
            descriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard fileDescriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(fileDescriptor) }
        let fileIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
            descriptor: fileDescriptor
        )
        let url = root.appendingPathComponent(name, isDirectory: false)
        try protect(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: descriptor
                      ) == generationIdentity,
                      try StoreRestoreGenerationAuthority.directoryIdentity(
                          at: root
                      ) == generationIdentity,
                      try StoreRestoreGenerationAuthority.regularFileIdentity(
                          descriptor: fileDescriptor
                      ) == fileIdentity,
                      try StoreRestoreGenerationAuthority.regularFileIdentity(
                          at: url
                      ) == fileIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )
    }

    private func protectPointer(at url: URL) throws {
        try protectPointerFile(.generationPointer, at: url)
    }

    private func protectPointer(
        at url: URL,
        parent: Int32,
        root: URL
    ) throws {
        try protectPointerFile(
            .generationPointer,
            at: url,
            parent: parent,
            root: root
        )
    }

    private func protectPointerFile(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        let root = url.deletingLastPathComponent().standardizedFileURL
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let parentIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: parent
        )
        try protect(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: parent
                      ) == parentIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                try self.verifyOwnedDirectory(at: root, descriptor: parent)
            }
        )
    }

    private func protectPointerFile(
        _ kind: OwnedFileKindV1,
        at url: URL,
        parent: Int32,
        root: URL
    ) throws {
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let parentIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: parent
        )
        try protect(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: parent
                      ) == parentIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                try self.verifyOwnedDirectory(at: root, descriptor: parent)
            }
        )
    }

    private func protectGeneration(
        at root: URL,
        staging: Bool,
        requireModel: Bool
    ) throws {
        let descriptor = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(descriptor) }
        let generationIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        try protect(
            staging ? .restoreStaging : .durableDirectory,
            at: root,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: descriptor
                      ) == generationIdentity,
                      try StoreRestoreGenerationAuthority.directoryIdentity(
                          at: root
                      ) == generationIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )
        let before = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )
        let modelKind: OwnedFileKindV1 = staging ? .stagingFile : .database
        let walKind: OwnedFileKindV1 = staging ? .stagingFile : .databaseWAL
        let shmKind: OwnedFileKindV1 = staging ? .stagingFile : .databaseSHM
        for name in before {
            let kind: OwnedFileKindV1
            switch name {
            case "model.sqlite": kind = modelKind
            case "\(Self.modelStoreName)-wal": kind = walKind
            case "\(Self.modelStoreName)-shm": kind = shmKind
            default: throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectGenerationFile(
                descriptor: descriptor,
                root: root,
                name: name,
                kind: kind
            )
        }
        let after = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )
        guard before == after else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func publishPointer<Value: Encodable>(
        name: String,
        value: Value,
        in root: URL
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try publishPointerLocked(name: name, value: value, in: root)
        }
    }

    private func publishPointerLocked<Value: Encodable>(
        name: String,
        value: Value,
        in root: URL
    ) throws {
        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        try StoreRestoreGenerationAuthority.requireSafeBasename(name)
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let temporaryName = ".\(name).restore-next"
        guard try !StoreRestoreGenerationAuthority.itemExists(parent: parent, name: name),
              try !StoreRestoreGenerationAuthority.itemExists(
                  parent: parent,
                  name: temporaryName
              ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let target = root.appendingPathComponent(name, isDirectory: false)
        let temporary = root.appendingPathComponent(temporaryName, isDirectory: false)
        let data = try canonicalData(for: value)
        var published = false
        var publishedIdentity: StoreRestoreGenerationAuthority.RegularFileIdentity?
        do {
            try StoreRestoreGenerationAuthority.createRegularFile(
                parent: parent,
                name: temporaryName,
                data: data
            )
            try protectPointerFile(
                .generationPointerTemporary,
                at: temporary,
                parent: parent,
                root: root
            )
            try verifyOwnedDirectory(at: root, descriptor: parent)
            let temporaryIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: temporaryName
            )
            publishedIdentity = temporaryIdentity
            guard try !StoreRestoreGenerationAuthority.itemExists(parent: parent, name: name),
                  Darwin.renameatx_np(
                      parent,
                      temporaryName,
                      parent,
                      name,
                      UInt32(RENAME_EXCL)
            ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            published = true
            guard Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verifyOwnedDirectory(at: root, descriptor: parent)
            try protectPointer(at: target, parent: parent, root: root)
            let current = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            guard current.data == data,
                  current.identity == temporaryIdentity,
                  try !StoreRestoreGenerationAuthority.itemExists(
                      parent: parent,
                      name: temporaryName
                  ) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            if published,
               let publishedIdentity,
               let current = try? StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                   parent: parent,
                   name: name
               ),
               current.data == data,
               current.identity == publishedIdentity {
                _ = Darwin.unlinkat(parent, name, 0)
                _ = Darwin.fsync(parent)
            } else if (try? StoreRestoreGenerationAuthority.itemExists(
                parent: parent,
                name: temporaryName
            )) == true {
                _ = Darwin.unlinkat(parent, temporaryName, 0)
                _ = Darwin.fsync(parent)
            }
            throw error
        }
    }

    private func replacePointer<Value: Encodable>(
        name: String,
        value: Value,
        expectedData requiredExpectedData: Data? = nil
    ) throws {
        let registry = try makeGenerationLeaseRegistry()
        try registry.withExclusiveGenerationMutationLock {
            try replacePointerLocked(
                name: name,
                value: value,
                expectedData: requiredExpectedData
            )
        }
    }

    private func replacePointerLocked<Value: Encodable>(
        name: String,
        value: Value,
        expectedData requiredExpectedData: Data? = nil
    ) throws {
        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        try StoreRestoreGenerationAuthority.requireSafeBasename(name)
        let root = dataRootURL
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let target = root.appendingPathComponent(name, isDirectory: false)
        try protectPointer(at: target, parent: parent, root: root)
        let expectedRead = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
            parent: parent,
            name: name
        )
        let expected = expectedRead.data
        let expectedIdentity = expectedRead.identity
        if let requiredExpectedData,
           expected != requiredExpectedData {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let replacement = try canonicalData(for: value)
        let temporaryName = ".\(name).restore-next"
        let temporary = root.appendingPathComponent(temporaryName, isDirectory: false)
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: temporaryName
        ) {
            guard try StoreRestoreGenerationAuthority.readRegularFile(
                parent: parent,
                name: temporaryName
            ) == replacement else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try removeOwnedEntry(parent: parent, name: temporaryName)
        }
        let currentBeforeSwap = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
            parent: parent,
            name: name
        )
        guard currentBeforeSwap.data == expected,
              currentBeforeSwap.identity == expectedIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var published = false
        var publishedIdentity: StoreRestoreGenerationAuthority.RegularFileIdentity?
        do {
            try StoreRestoreGenerationAuthority.createRegularFile(
                parent: parent,
                name: temporaryName,
                data: replacement
            )
            try protectPointerFile(
                .generationPointerTemporary,
                at: temporary,
                parent: parent,
                root: root
            )
            try verifyOwnedDirectory(at: root, descriptor: parent)
            let replacementIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: temporaryName
            )
            let current = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            guard current.identity == expectedIdentity,
                  current.data == expected,
                  Darwin.renameatx_np(
                      parent,
                      temporaryName,
                      parent,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            published = true
            publishedIdentity = replacementIdentity
            guard Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verifyOwnedDirectory(at: root, descriptor: parent)
            try protectPointer(at: target, parent: parent, root: root)
            let currentAfterSwap = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            let oldTemporary = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: temporaryName
            )
            guard currentAfterSwap.data == replacement,
                  currentAfterSwap.identity == replacementIdentity,
                  oldTemporary.data == expected,
                  oldTemporary.identity == expectedIdentity,
                  Darwin.unlinkat(parent, temporaryName, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            if published,
               let publishedIdentity,
               let current = try? StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                   parent: parent,
                   name: name
               ),
               current.data == replacement,
               current.identity == publishedIdentity {
                do {
                    let oldTemporary = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                        parent: parent,
                        name: temporaryName
                    )
                    guard oldTemporary.data == expected,
                          oldTemporary.identity == expectedIdentity,
                          Darwin.renameatx_np(
                              parent,
                              name,
                              parent,
                              temporaryName,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(parent) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                    try verifyOwnedDirectory(at: root, descriptor: parent)
                    try protectPointer(at: target, parent: parent, root: root)
                    let restored = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                        parent: parent,
                        name: name
                    )
                    let replacementTemporary = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                        parent: parent,
                        name: temporaryName
                    )
                    guard restored.data == expected,
                          restored.identity == expectedIdentity,
                          replacementTemporary.data == replacement,
                          replacementTemporary.identity == publishedIdentity,
                          Darwin.unlinkat(parent, temporaryName, 0) == 0,
                          Darwin.fsync(parent) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            if (try? StoreRestoreGenerationAuthority.itemExists(
                parent: parent,
                name: temporaryName
            )) == true {
                _ = Darwin.unlinkat(parent, temporaryName, 0)
                _ = Darwin.fsync(parent)
            }
            throw error
        }
    }

    private func restorePointer(
        parent: Int32,
        root: URL,
        name: String,
        data: Data,
        expectedCurrentIdentity: StoreRestoreGenerationAuthority.RegularFileIdentity? = nil
    ) throws {
        let rollbackName = ".\(name).restore-rollback"
        let replacedIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
            parent: parent,
            name: name
        )
        if let expectedCurrentIdentity {
            guard replacedIdentity == expectedCurrentIdentity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: rollbackName
        ) {
            try removeOwnedEntry(parent: parent, name: rollbackName)
        }
        try StoreRestoreGenerationAuthority.createRegularFile(
            parent: parent,
            name: rollbackName,
            data: data
        )
        let rollbackURL = root.appendingPathComponent(rollbackName, isDirectory: false)
        try protectPointerFile(
            .generationPointerTemporary,
            at: rollbackURL,
            parent: parent,
            root: root
        )
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let publishedIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
            parent: parent,
            name: rollbackName
        )
        var swapped = false
        do {
            guard try StoreRestoreGenerationAuthority.regularFileIdentity(
                      parent: parent,
                      name: name
                  ) == replacedIdentity,
                  Darwin.renameatx_np(
                      parent,
                      rollbackName,
                      parent,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = true
            guard Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectPointer(
                at: root.appendingPathComponent(name, isDirectory: false),
                parent: parent,
                root: root
            )
            let restored = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            let replaced = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: rollbackName
            )
            guard restored.data == data,
                  restored.identity == publishedIdentity,
                  replaced == replacedIdentity,
                  Darwin.unlinkat(parent, rollbackName, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = false
        } catch {
            if swapped,
               let currentIdentity = try? StoreRestoreGenerationAuthority.regularFileIdentity(
                   parent: parent,
                   name: name
               ),
               currentIdentity == publishedIdentity,
               let rollbackIdentity = try? StoreRestoreGenerationAuthority.regularFileIdentity(
                   parent: parent,
                   name: rollbackName
               ),
               rollbackIdentity == replacedIdentity {
                do {
                    guard Darwin.renameatx_np(
                              parent,
                              name,
                              parent,
                              rollbackName,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(parent) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            throw error
        }
    }

    @MainActor
    func openOrBootstrapCurrent() throws -> StoreGenerationSession {
        try PersistentSchemaReleaseRegistryV1.validate()
        let dataRootURL = applicationSupportURL.appendingPathComponent(
            Self.dataDirectoryName,
            isDirectory: true
        )

        switch try itemType(at: dataRootURL) {
        case nil:
            try bootstrapDataRoot(at: dataRootURL)
        case .some(.typeDirectory):
            break
        case .some:
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let pointerAuthority = try makeRestoreGenerationAuthority()
        _ = try pointerAuthority.currentGenerationID()
        _ = try pointerAuthority.retiredGenerationIDs()
        let leaseRegistry = try makeGenerationLeaseRegistry()
        if try leaseRegistry.loadPruneIntent() != nil {
            _ = try reconcileGenerationLeasesAndPrune()
        }

        do {
            let migrationStore = try StoreMigrationJournalStoreV1(
                applicationSupportURL: applicationSupportURL
            )
            let processID = (migrationIdentitySource ?? .live).makeProcessID()
            if let journal = try migrationStore.loadJournal() {
                return try resumeMigration(
                    journal,
                    dataRootURL: dataRootURL,
                    store: migrationStore,
                    processID: processID
                )
            }
            return try openCurrent(
                in: dataRootURL,
                store: migrationStore,
                processID: processID
            )
        } catch let failure as StoreMigrationFailure {
            throw failure
        } catch {
            if let reason = migrationMaintenanceReason(for: error) {
                throw StoreMigrationFailure.maintenanceRequired(reason)
            }
            throw error
        }
    }

    @MainActor
    private func bootstrapDataRoot(at dataRootURL: URL) throws {
        if let type = try itemType(at: applicationSupportURL),
           type != .typeDirectory {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        guard try itemType(at: applicationSupportURL) == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let bootstrapURL = applicationSupportURL.appendingPathComponent(
            Self.bootstrapDirectoryName,
            isDirectory: true
        )
        let applicationSupportDescriptor = try openOwnedDirectory(at: applicationSupportURL)
        defer { _ = Darwin.close(applicationSupportDescriptor) }
        try verifyOwnedDirectory(
            at: applicationSupportURL,
            descriptor: applicationSupportDescriptor
        )
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: applicationSupportDescriptor,
            name: Self.bootstrapDirectoryName
        ) {
            try removeOwnedEntry(
                parent: applicationSupportDescriptor,
                name: Self.bootstrapDirectoryName
            )
        }

        let generationID = migrationIdentitySource?.makeGenerationID() ?? UUID()
        let generationName = canonicalString(for: generationID)
        let bootstrapDescriptor = try createOwnedDirectory(
            parent: applicationSupportDescriptor,
            name: Self.bootstrapDirectoryName
        )
        defer { _ = Darwin.close(bootstrapDescriptor) }
        let bootstrapGenerationsDescriptor = try createOwnedDirectory(
            parent: bootstrapDescriptor,
            name: Self.generationsDirectoryName
        )
        defer { _ = Darwin.close(bootstrapGenerationsDescriptor) }
        let generationDescriptor = try createOwnedDirectory(
            parent: bootstrapGenerationsDescriptor,
            name: generationName
        )
        defer { _ = Darwin.close(generationDescriptor) }
        let generationRootURL = bootstrapURL
            .appendingPathComponent(Self.generationsDirectoryName, isDirectory: true)
            .appendingPathComponent(generationName, isDirectory: true)

        let bootstrapGenerationsURL = bootstrapURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        try protect(.stagingDirectory, at: bootstrapURL)
        try protect(.stagingDirectory, at: bootstrapGenerationsURL)
        try protect(.restoreStaging, at: generationRootURL)

        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        try createAndReleaseEmptyContainer(
            at: modelStoreURL,
            markerMigrationID: Self.bootstrapManifestMigrationID
        )
        try autoreleasepool {
            let container = try makeV48Container(at: modelStoreURL, migrate: false)
            _ = try MutationJournalStoreV1(
                modelContext: container.mainContext,
                identity: pointerEnrichmentIdentity,
                generationID: generationID
            )
        }

        guard try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)

        let manifest = try StoreGenerationManifestV1(
            generationID: generationID,
            predecessorGenerationID: syntheticPredecessor(
                excluding: generationID
            ),
            migrationID: Self.bootstrapManifestMigrationID,
            storeSchemaRelease: .v46,
            semanticSHA256: try semanticDigest(
                at: modelStoreURL,
                release: .v46
            ),
            frozenIdentityDigest: try frozenIdentityDigest(
                for: generationRootURL
            ),
            files: try generationFileDigests(
                at: generationRootURL,
                durable: true
            )
        )
        let migrationStore = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let manifestDigest = try migrationStore.writeManifest(manifest)
        let currentPointer = try CurrentGenerationPointerV3(
            generationID: generationID,
            generationManifestSHA256: manifestDigest,
            workspaceID: pointerEnrichmentIdentity.workspaceID,
            replicaID: pointerEnrichmentIdentity.replicaID,
            storeSchemaVersion: 46
        )
        let retiredPointer = RetiredPointerV1(
            generationIDs: [],
            schemaVersion: StorePointerSchemaRegistry.retiredVersion
        )
        try publishPointer(
            name: Self.currentPointerName,
            value: currentPointer,
            in: bootstrapURL
        )
        try publishPointer(
            name: Self.retiredPointerName,
            value: retiredPointer,
            in: bootstrapURL
        )

        try protect(.durableDirectory, at: bootstrapURL)
        try protect(.durableDirectory, at: bootstrapGenerationsURL)
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)
        try protectPointer(
            at: bootstrapURL.appendingPathComponent(Self.currentPointerName, isDirectory: false)
        )
        try protectPointer(
            at: bootstrapURL.appendingPathComponent(Self.retiredPointerName, isDirectory: false)
        )

        // The staging root is a fixed sibling, so this move is a same-volume
        // atomic publication of an already complete generation and pointers.
        try verifyOwnedDirectory(
            at: applicationSupportURL,
            descriptor: applicationSupportDescriptor
        )
        guard try !StoreRestoreGenerationAuthority.itemExists(
            parent: applicationSupportDescriptor,
            name: Self.dataDirectoryName
        ),
              Darwin.renameatx_np(
                  applicationSupportDescriptor,
                  Self.bootstrapDirectoryName,
                  applicationSupportDescriptor,
                  Self.dataDirectoryName,
                  UInt32(RENAME_EXCL)
              ) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protect(.durableDirectory, at: dataRootURL)
        let publishedGenerationsURL = dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        try protect(.durableDirectory, at: publishedGenerationsURL)
        try protectGeneration(
            at: publishedGenerationsURL.appendingPathComponent(
                generationName,
                isDirectory: true
            ),
            staging: false,
            requireModel: true
        )
        try protectPointer(
            at: dataRootURL.appendingPathComponent(
                Self.currentPointerName,
                isDirectory: false
            )
        )
        try protectPointer(
            at: dataRootURL.appendingPathComponent(
                Self.retiredPointerName,
                isDirectory: false
            )
        )
    }

    @MainActor
    private func openCurrent(
        in dataRootURL: URL,
        store: StoreMigrationJournalStoreV1,
        processID: UUID
    ) throws -> StoreGenerationSession {
        try protect(.durableDirectory, at: dataRootURL)
        let generationsRoot = dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        try protect(.durableDirectory, at: generationsRoot)
        let currentURL = dataRootURL.appendingPathComponent(
            Self.currentPointerName,
            isDirectory: false
        )
        let retiredURL = dataRootURL.appendingPathComponent(
            Self.retiredPointerName,
            isDirectory: false
        )
        guard try itemType(at: currentURL) == .typeRegular,
              try itemType(at: retiredURL) == .typeRegular else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protectPointer(at: currentURL)
        try protectPointer(at: retiredURL)

        let current = try decodeCurrentPointer(at: currentURL)
        let retired: RetiredPointerV1 = try decodeCanonicalPointer(at: retiredURL)
        try StorePointerSchemaRegistry.requireRetired(retired.schemaVersion)
        let currentName: String
        let currentID: UUID
        switch current {
        case .legacy(let pointer, _):
            currentName = pointer.generationID
            guard let identifier = canonicalUUID(from: currentName) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            currentID = identifier
        case .v2(let pointer, _):
            currentName = pointer.generationID
            guard let identifier = canonicalUUID(from: currentName) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            currentID = identifier
        case .v3(let pointer, _):
            currentName = pointer.generationID
            guard let identifier = canonicalUUID(from: currentName) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            currentID = identifier
        }
        guard retired.generationIDs.allSatisfy({ canonicalUUID(from: $0) != nil }),
              retired.generationIDs == retired.generationIDs.sorted(),
              Set(retired.generationIDs).count == retired.generationIDs.count,
              !retired.generationIDs.contains(currentName) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let generationsURL = generationsRoot
        guard let generationsType = try itemType(at: generationsURL) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard generationsType == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let expectedGenerationNames = Set(
            [currentName] + retired.generationIDs
        )
        let actualGenerationNames: Set<String>
        do {
            actualGenerationNames = Set(
                try fileManager.contentsOfDirectory(atPath: generationsURL.path)
            )
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard actualGenerationNames == expectedGenerationNames else {
            if expectedGenerationNames.subtracting(actualGenerationNames).isEmpty {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            throw StoreGenerationFailure.dataGenerationMissing
        }

        switch current {
        case .legacy(let pointer, let data):
            return try beginMigration(
                sourcePointer: pointer,
                sourcePointerData: data,
                retired: retired,
                dataRootURL: dataRootURL,
                store: store,
                processID: processID
            )
        case .v2(let pointer, _):
            let enriched = try enrichCurrentPointer(pointer)
            let sourceLease = try acquireCurrentReaderLease(
                epoch: GenerationEpochV1(
                    generationID: currentID,
                    generationManifestSHA256:
                        enriched.generationManifestSHA256
                ),
                expectedPointerData: try enriched.canonicalData()
            )
            return try withExtendedLifetime(sourceLease) {
                try beginMigration(
                    sourcePointer: enriched,
                    sourcePointerData: try enriched.canonicalData(),
                    retired: retired,
                    dataRootURL: dataRootURL,
                    store: store,
                    processID: processID
                )
            }
        case .v3(let pointer, let data):
            if pointer.storeSchemaVersion < 11 {
                let sourceLease = try acquireCurrentReaderLease(
                    epoch: GenerationEpochV1(
                        generationID: currentID,
                        generationManifestSHA256:
                            pointer.generationManifestSHA256
                    ),
                    expectedPointerData: data
                )
                return try withExtendedLifetime(sourceLease) {
                    try beginMigration(
                        sourcePointer: pointer,
                        sourcePointerData: data,
                        retired: retired,
                        dataRootURL: dataRootURL,
                        store: store,
                        processID: processID
                    )
                }
            }
            return try openValidatedV3Current(pointer: pointer, dataRootURL: dataRootURL, store: store)
        }
    }

    @MainActor
    private func createAndReleaseEmptyContainer(
        at modelStoreURL: URL,
        markerMigrationID: UUID
    ) throws {
        try autoreleasepool {
            let container = try makeV48Container(
                at: modelStoreURL,
                migrate: false
            )
            do {
                let context = container.mainContext
                context.insert(PersistentSchemaReleaseMarker(
                    id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
                    schemaVersion: 48,
                    releaseID: PersistentSchemaReleaseV1.v48.compatibilityID,
                    predecessorReleaseID: PersistentSchemaReleaseV1.v47.compatibilityID,
                    migrationID: markerMigrationID
                ))
                try context.save()
                _ = try requireV48Marker(in: context, expectedMigrationID: markerMigrationID)
            }
        }
    }

    @MainActor
    private func openGeneration(
        id: UUID,
        at generationRootURL: URL,
        identity: WorkspaceReplicaIdentityV1? = nil
    ) throws -> StoreGenerationSession {
        guard generationRootURL.lastPathComponent == canonicalString(for: id) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        let restoreRoot = restoreStagingGenerationURL(id: id)
        let staging = generationRootURL.standardizedFileURL == restoreRoot.standardizedFileURL
        let epoch: GenerationEpochV1?
        let readerLease: GenerationLeaseHandleV1?
        let acceptedInstalledGeneration: Bool
        if staging {
            acceptedInstalledGeneration = false
        } else {
            let authority = try makeRestoreGenerationAuthority()
            acceptedInstalledGeneration = try authority.currentGenerationID() == id
                || authority.retiredGenerationIDs().contains(id)
        }
        if acceptedInstalledGeneration {
            guard let manifest = try StoreMigrationJournalStoreV1(
                applicationSupportURL: applicationSupportURL
            ).loadManifestIfPresent(targetGenerationID: id),
                  manifest.manifest.generationID == id else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            let acceptedEpoch = try GenerationEpochV1(
                generationID: id,
                generationManifestSHA256: manifest.digest
            )
            epoch = acceptedEpoch
            readerLease = try acquireAcceptedReaderLease(epoch: acceptedEpoch)
        } else {
            epoch = nil
            readerLease = nil
        }
        guard try itemType(at: generationRootURL) == .typeDirectory else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        try protectGeneration(at: generationRootURL, staging: staging, requireModel: true)
        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        guard try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        let container: ModelContainer
        do {
            container = try makeV48Container(at: modelStoreURL, migrate: false)
            _ = try requireV48Marker(in: container.mainContext, expectedMigrationID: nil)
        }
        catch { throw StoreGenerationFailure.dataPointerInvalid }
        try protectGeneration(at: generationRootURL, staging: staging, requireModel: true)
        let resolvedIdentity = identity ?? pointerEnrichmentIdentity
        return StoreGenerationSession(
            generationID: id,
            generationRootURL: generationRootURL,
            workspaceIdentity: resolvedIdentity,
            modelContainer: container,
            generationEpoch: epoch,
            readerLeaseHandle: readerLease,
            afterSaveReproof: { [self] in
                try self.protectGeneration(
                    at: generationRootURL,
                    staging: staging,
                    requireModel: true
                )
            }
        )
    }

    private func removeOwnedDirectory(
        _ url: URL,
        expectedParent: URL
    ) throws {
        let value = url.standardizedFileURL
        guard value.deletingLastPathComponent() == expectedParent.standardizedFileURL,
              let id = UUID(uuidString: value.lastPathComponent),
              canonicalString(for: id) == value.lastPathComponent else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let parent = try openOwnedDirectory(at: expectedParent)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: expectedParent, descriptor: parent)
        try removeOwnedEntry(parent: parent, name: value.lastPathComponent)
        guard try !StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: value.lastPathComponent
        ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func decodeCanonicalPointer<Value: Decodable & Encodable>(
        at url: URL
    ) throws -> Value {
        let parentURL = url.deletingLastPathComponent()
        let parent = try openOwnedDirectory(at: parentURL)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: parentURL, descriptor: parent)
        return try decodeCanonicalPointer(parent: parent, name: url.lastPathComponent)
    }

    private func decodeCanonicalPointer<Value: Decodable & Encodable>(
        parent: Int32,
        name: String
    ) throws -> Value {
        do {
            let captured = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            let data = captured.data
            let value = try JSONDecoder().decode(Value.self, from: data)
            guard try canonicalData(for: value) == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            guard try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: name
            ) == captured.identity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return value
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func canonicalData<Value: Encodable>(for value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func canonicalUUID(from value: String) -> UUID? {
        guard let uuid = UUID(uuidString: value),
              canonicalString(for: uuid) == value else {
            return nil
        }
        return uuid
    }

    private func canonicalString(for uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return .typeDirectory
        case S_IFREG:
            return .typeRegular
        case S_IFLNK:
            return .typeSymbolicLink
        default:
            return .typeUnknown
        }
    }
}

private final class StoreGenerationLeaseRegistryProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var retainedRegistry: GenerationLeaseRegistryV1?

    func registry(
        applicationSupportURL: URL
    ) throws -> GenerationLeaseRegistryV1 {
        lock.lock()
        defer { lock.unlock() }
        if let retainedRegistry {
            return retainedRegistry
        }
        let registry = try GenerationLeaseRegistryV1(
            applicationSupportURL: applicationSupportURL
        )
        retainedRegistry = registry
        return registry
    }
}

private struct StoreGenerationPruneInventoryV1: Codable {
    let currentEpoch: GenerationEpochV1
    let retiredEpochs: [GenerationEpochV1]
    let activeEpochs: [GenerationEpochV1]
    let uncertainGenerationIDs: [UUID]
}

private struct StoreSemanticEnvelopeV3: Codable {
    let records: Data
    let deletionLedger: Data
}

private struct StoreSemanticEnvelopeV4: Codable {
    let base: Data
    let receipts: [MutationReceiptSemanticV1]
    let quarantines: [MutationQuarantineSemanticV1]
    let states: [WorkspaceMutationStateSemanticV1]
    let entityRevisions: [EntityMutationRevisionSemanticV1]
}

private struct StoreSemanticEnvelopeV5: Codable {
    let base: Data
    let observationAndTime: [ObservationAndTimeSemanticV1]
}

private struct StoreSemanticEnvelopeV6: Codable {
    let base: Data
    let locationNodes: [Data]
    let hierarchyEvents: [Data]
    let placementEvents: [Data]
    let compositionEdges: [Data]
    let compositionEvents: [Data]
    let migrationReceipts: [Data]
}

private struct StoreSemanticEnvelopeV7: Codable {
    let base: Data
    let savedSmartViews: [Data]
}

private struct StoreSemanticEnvelopeV8: Codable {
    let base: Data
    let requirementAssurance: [RequirementAssuranceSnapshotV1]
}

private struct StoreSemanticEnvelopeV9: Codable {
    let base: Data
    let parties: [ServicePartyReferenceV1]
    let roles: [SitePartyRoleEventV1]
    let actors: [ActorSnapshotV1]
    let qualifications: [QualificationSnapshotV1]
    let signoffs: [SignoffSnapshotV1]
}

private struct StoreSemanticEnvelopeV10: Codable {
    let base: Data
    let kindBindings: [AssetKindBindingEventV1]
    let workflowBindings: [AssetWorkflowCapabilityBindingEventV1]
    let productIdentities: [AssetProductIdentityV1]
    let lifecycleEvents: [AssetLifecycleEventV1]
    let successorLinks: [AssetSuccessorLinkV1]
    let subjectScopes: [WorkSubjectScopeSnapshotV1]
}

private struct StoreSemanticEnvelopeV11: Codable {
    let base: Data
    let authoritySources: [AuthoritySourceReleaseV1]
    let requirementBindings: [RequirementBasisBindingV1]
    let applicabilityContexts: [ApplicabilityContextSnapshotV1]
    let assessmentScopes: [AssessmentScopeSnapshotV1]
    let severityScales: [SeverityScaleReleaseV1]
    let findingBindings: [FindingClassificationBindingV1]
    let measurementProtocols: [MeasurementProtocolReleaseV1]
    let evaluatorDescriptors: [DerivedFactEvaluatorDescriptorV1]
    let derivedFacts: [DerivedFactProvenanceV1]
}

private struct StoreSemanticEnvelopeV12: Codable {
    let base: Data
    let descriptors: [FunctionalRelationshipTypeDescriptorV1]
    let events: [AssetFunctionalRelationshipEventV1]
}
private struct StoreSemanticEnvelopeV13:Codable{let base:Data;let visibilities:[EvidenceVisibilityV1];let links:[ClaimEvidenceLinkV1];let manifests:[AssuranceManifestV1];let attestations:[AttestationV1]}
private struct StoreSemanticEnvelopeV14:Codable{let base:Data;let transitions:[InspectionReviewTransitionV1];let dispositions:[ReviewDispositionV1];let changeRequests:[ChangeRequestV1];let policies:[CorrectiveActionPolicyV1];let events:[CorrectiveActionEventV1]}
private struct StoreSemanticEnvelopeV15:Codable{let base:Data;let manifests:[WorkPacketManifestV1];let claims:[WorkItemClaimV1];let leases:[WorkLeaseV1];let releases:[WorkReleaseV1];let handoffs:[WorkHandoffV1]}
private struct StoreSemanticEnvelopeV16:Codable{let base:Data;let checkpoints:[FieldDraftCheckpointV1];let stages:[AttachmentStagingItemV1];let sagas:[DraftCommitSagaV1];let reservations:[DraftContentReservationV1];let commitReceipts:[DraftCommitReceiptV1];let discardReceipts:[DraftDiscardReceiptV1]}
private struct StoreSemanticEnvelopeV17:Codable{let base:Data;let promotedReleases:[PromotedPackageReleaseV1];let sandboxRuns:[PackageSandboxRunV1];let promotionReceipts:[PackagePromotionReceiptV1];let activePointers:[ActivePackageRegistryPointerV1]}
private struct StoreSemanticEnvelopeV18:Codable{let base:Data;let instruments:[InstrumentReferenceV1];let calibrations:[CalibrationStatusSnapshotV1];let captures:[MeasurementCaptureV1];let series:[MeasurementSeriesV1];let assessments:[MeasurementQualityAssessmentV1]}
private struct StoreSemanticEnvelopeV19:Codable{let base:Data;let policies:[PrivacyTransformPolicyV1];let regions:[PrivacyRegionV1];let manifests:[PrivacyTransformManifestV1];let reviews:[PrivacyReviewReceiptV1]}
private struct StoreSemanticEnvelopeV20:Codable{let base:Data;let profiles:[ClientCapabilityProfileV1];let decisions:[ClientCapabilityAdmissionDecisionV1];let policies:[PackageLifecyclePolicyV1];let dispositions:[PackageLifecycleDispositionV1]}
private struct StoreSemanticEnvelopeV21:Codable{let base:Data;let receipts:[RecoverabilityVerificationReceiptV1]}
private struct StoreSemanticEnvelopeV22:Codable{let base:Data;let releases:[FieldReferenceReleaseV1];let bindings:[FieldReferenceBindingV1]}
private struct StoreSemanticEnvelopeV23:Codable{let base:Data;let receipts:[AccessibleDocumentAssessmentReceiptV1]}
private struct StoreSemanticEnvelopeV24:Codable{let base:Data;let identities:[SurveyDefinitionIdentityV1];let releases:[SurveyDefinitionReleaseV1]}
private struct StoreSemanticEnvelopeV25:Codable{let base:Data;let sessions:[SurveySessionV1];let facts:[FactCaptureV1];let subjects:[ProvisionalSubjectV1];let promotions:[SubjectPromotionReceiptV1];let publications:[SurveyPublicationSnapshotV1]}
private struct StoreSemanticEnvelopeV26:Codable{let base:Data;let locators:[AssetLocatorV1];let receipts:[LocatorBindingReceiptV1]}
private struct StoreSemanticEnvelopeV27:Codable{let base:Data;let releases:[ScheduleDefinitionReleaseV1];let events:[OccurrenceHistoryEventV1]}
private struct StoreSemanticEnvelopeV28:Codable{let base:Data;let documents:[PlanDocumentV1];let revisions:[PlanRevisionV1];let placements:[PlanPlacementV1];let receipts:[RebaseReceiptV1]}
private struct StoreSemanticEnvelopeV29:Codable{let base:Data;let events:[AssetPoseEventV1];let observations:[SpatialAnchorObservationV1]}
private struct StoreSemanticEnvelopeV30:Codable{let base:Data;let contexts:[EvidenceContextV1];let pairs:[PairedObservationLinkV1]}
private struct StoreSemanticEnvelopeV31:Codable{let base:Data;let systems:[LightingSystemV1];let observations:[LightingObservationV1];let issues:[LightingIssueV1];let plans:[MeasurementPlanV1];let claims:[LightingClaimStateV1]}
private struct StoreSemanticEnvelopeV32:Codable{let base:Data;let assistanceAcceptanceReceipts:[AssistanceAcceptanceReceiptV1]}
private struct StoreSemanticEnvelopeV33:Codable{let base:Data;let clips:[TemporalEvidenceClipV1];let anchors:[TimecodedEvidenceAnchorV1]}
private struct StoreSemanticEnvelopeV34:Codable{let base:Data;let snapshots:[AcceptedLabelGenerationSnapshotV1]}
private struct StoreSemanticEnvelopeV35:Codable{let base:Data;let contacts:[ServiceContactPointV1];let handoffIntents:[SystemHandoffIntentV1]}
private struct StoreSemanticEnvelopeV36:Codable{let base:Data;let envelopes:[ActivitySessionEnvelopeV2];let transitions:[ActivityStateTransitionV2];let installationTaskResults:[InstallationTaskResultV1];let installationAsBuiltSnapshots:[InstallationAsBuiltSnapshotV1];let punchReviewBasisSnapshots:[PunchReviewBasisSnapshotV1]}
private struct StoreSemanticEnvelopeV37:Codable{let base:Data;let workResources:[WorkResourceEntryV1]}
private struct StoreSemanticEnvelopeV38:Codable{let base:Data;let calendars:[ExceptionCalendarReleaseV1];let overrides:[ScheduleOverrideEventV1]}
private struct StoreSemanticEnvelopeV39:Codable{let base:Data;let records:[ServiceRequestRecordV1];let dispositions:[ServiceRequestDispositionEventV1];let workLinks:[ServiceRequestWorkLinkEventV1]}
private struct StoreSemanticEnvelopeV40:Codable{let base:Data;let events:[Data]}
private struct StoreSemanticEnvelopeV41:Codable{let base:Data;let parts:[LocalPartDefinitionV1];let locations:[StockStorageLocationV1];let movements:[StockMovementEventV1];let uses:[StockUseOnWorkReceiptV1];let reversals:[StockUseReversalReceiptV1];let returns:[StockReturnAgainstUseReceiptV1];let abandonments:[AbandonUnverifiedStockDispositionV1]}
private struct StoreSemanticEnvelopeV42:Codable{let base:Data;let plans:[MyDayPlanV1];let carryoverReceipts:[MyDayCarryoverReceiptV1]}
private struct StoreSemanticEnvelopeV43:Codable{let base:Data;let associations:[EvidenceAssociationV1];let sequences:[EvidenceSequenceV1]}
private struct StoreSemanticEnvelopeV44:Codable{let base:Data;let profiles:[ShopReportProfileV1]}
private struct StoreSemanticEnvelopeV45:Codable{let base:Data;let sessions:[RoundSessionV1]}
private struct StoreSemanticEnvelopeV46:Codable{let base:Data;let profiles:[ImportMappingProfileV1];let sessions:[BulkSessionV1];let receipts:[BulkCommitReceiptV1]}
private struct StoreSemanticEnvelopeV47:Codable{let base:Data;let rows:[Data]}
private struct StoreSemanticEnvelopeV48:Codable{let base:Data;let rows:[Data]}
private struct StoreSemanticEnvelopeV49:Codable{let base:Data;let rows:[Data]}
private struct StoreSemanticEnvelopeV50:Codable{let base:Data;let rows:[Data]}
private struct StoreSemanticEnvelopeV51:Codable{let base:Data;let rows:[PracticeWorkspaceProvenanceV1]}
private struct StoreSemanticEnvelopeV52:Codable{let base:Data;let rows:[LightingDayInventoryWorkflowV1]}
private struct StoreSemanticEnvelopeV53:Codable{let base:Data;let rows:[LightingNightWorkflowV1]}

private struct AssetSemanticDateBoxV1: Codable {
    let value: Date
}


private struct LocationHierarchySemanticV6: Codable {
    let planData: Data
    let receiptData: Data
}

private struct ObservationAndTimeSemanticV1: Codable {
    let recordID: UUID
    let observationBasisData: Data
    let temporalContextData: Data

    init(
        recordID: UUID,
        observationBasisData: Data?,
        temporalContextData: Data?
    ) throws {
        guard let observationBasisData, let temporalContextData else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        let basis = try ObservationAndTimeCodecV1.decodeObservationBasis(
            observationBasisData
        )
        let time = try ObservationAndTimeCodecV1.decodeTemporalContext(
            temporalContextData
        )
        guard try ObservationAndTimeCodecV1.encode(basis) == observationBasisData,
              try ObservationAndTimeCodecV1.encode(time) == temporalContextData else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        self.recordID = recordID
        self.observationBasisData = observationBasisData
        self.temporalContextData = temporalContextData
    }
}

private struct MutationReceiptSemanticV1: Codable {
    let mutationID: UUID
    let receiptIdentity: String
    let envelopeData: Data
    let receiptData: Data
    let reversalBasisData: Data?
    let semanticReversalData: Data?
}

private struct MutationQuarantineSemanticV1: Codable {
    let workspaceMutationKey: String
    let workspaceID: UUID
    let mutationID: UUID
    let identityDomain: String
    let acceptedIdentitySHA256: String
    let conflictingIdentitySHA256: String
    let detectedAt: Date
}

private struct WorkspaceMutationStateSemanticV1: Codable {
    let workspaceID: UUID
    let generationID: UUID
    let replicaID: UUID
    let revision: Int64
    let sequence: Int64
    let mutableSemanticSHA256: String?
}

private struct EntityMutationRevisionSemanticV1: Codable {
    let identity: String
    let revision: Int64
    let externalProjectionSHA256: String?
}

private enum CurrentPointerEnvelopeV1 {
    case legacy(CurrentPointerV1, Data)
    case v2(CurrentGenerationPointerV2, Data)
    case v3(CurrentGenerationPointerV3, Data)

    var data: Data {
        switch self {
        case .legacy(_, let data), .v2(_, let data), .v3(_, let data):
            return data
        }
    }

    var generationID: String {
        switch self {
        case .legacy(let pointer, _): return pointer.generationID
        case .v2(let pointer, _): return pointer.generationID
        case .v3(let pointer, _): return pointer.generationID
        }
    }
}

private struct CurrentPointerV1: Codable {
    let generationID: String
    let schemaVersion: Int
}

private struct RetiredPointerV1: Codable {
    let generationIDs: [String]
    let schemaVersion: Int
}

private enum CurrentPointerCodecV1 {
    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    static func decode(_ data: Data) throws -> CurrentPointerEnvelopeV1 {
        do {
            let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
            switch probe.schemaVersion {
            case StorePointerSchemaRegistry.legacyCurrentVersion:
                let value = try JSONDecoder().decode(CurrentPointerV1.self, from: data)
                guard value.schemaVersion
                        == StorePointerSchemaRegistry.legacyCurrentVersion,
                      try StoreMigrationCanonicalJSONV1.encode(value) == data,
                      let identifier = UUID(uuidString: value.generationID),
                      identifier.uuidString.lowercased() == value.generationID else {
                    throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
                }
                return .legacy(value, data)
            case StorePointerSchemaRegistry.manifestCurrentVersion:
                let value = try CurrentGenerationPointerV2.decodeCanonical(from: data)
                return .v2(value, data)
            case StorePointerSchemaRegistry.identityCurrentVersion:
                let value = try CurrentGenerationPointerV3.decodeCanonical(from: data)
                return .v3(value, data)
            default:
                throw StoreMigrationFailure.maintenanceRequired(.futureVersion)
            }
        } catch let failure as StoreMigrationFailure {
            throw failure
        } catch {
            throw StoreMigrationFailure.maintenanceRequired(.invalidPointer)
        }
    }
}

enum C48PortableReviewStoreGenerationBoundaryV1 {
    static let activePersistentSchemaVersion = 36
    static let semanticEnvelopeUnchanged = true
    static let sessionStoreIsNonpersistent = true
    static let historicalPreC47ActivityContractsRemainUntouched = true
}

enum C50IncumbentFileExchangeStoreGenerationBoundaryV1 {
    static let activePersistentSchemaVersion = 37
    static let activePersistentModelCount = 121
    static let recordsSchemaVersion = 36
    static let profileSelectionSessionSourceQuarantineAreNonpersistent = true
    static let noAdapterGeneration = true
    static let noAdapterSwiftDataModel = true
    static let acceptedCanonicalEffectsUseExistingGeneration = true
    static let migrationDisposition = "NOT_APPLICABLE"
    static let backupRestoreDisposition = "NOT_APPLICABLE"

    static func validate() -> Bool {
        activePersistentSchemaVersion == 37
            && activePersistentModelCount == 121
            && recordsSchemaVersion == 36
            && profileSelectionSessionSourceQuarantineAreNonpersistent
            && noAdapterGeneration
            && noAdapterSwiftDataModel
            && acceptedCanonicalEffectsUseExistingGeneration
            && migrationDisposition == "NOT_APPLICABLE"
            && backupRestoreDisposition == "NOT_APPLICABLE"
            && C50IncumbentFileExchangePersistenceBoundaryV1.validate()
    }
}

enum C51ScheduleExceptionStoreGenerationBoundaryV1 {
    static let activePersistentSchemaVersion = 38
    static let activePersistentModelCount = 123
    static let recordsSchemaVersion = 37
    static let calendarAndOverrideRowsAreCanonical = true
    static let advancedConfigurationIsEmbeddedInScheduleReleaseBytes = true
    static let createsParallelScheduleWriter = false

    static func validate() -> Bool {
        activePersistentSchemaVersion == 38
            && activePersistentModelCount == 123
            && recordsSchemaVersion == 37
            && calendarAndOverrideRowsAreCanonical
            && advancedConfigurationIsEmbeddedInScheduleReleaseBytes
            && !createsParallelScheduleWriter
            && C51ScheduleExceptionMigrationBoundaryV1.validate()
    }
}

enum C34SceneNavigationStoreGenerationBoundaryV1 {
    static let generatedStoreFamilyCount = 0
    static let generatesRouteRows = false
    static func validate() -> Bool { generatedStoreFamilyCount == 0 && !generatesRouteRows && C34SceneNavigationPersistentSchemaBoundaryV1.validate() }
}
// C52_BOUNDARY_ANCHOR: clone-fork-service-request-history
enum C52ServiceRequestStoreGenerationBoundaryV1 {
    static let sourcePersistentSchemaVersion = 38
    static let targetPersistentSchemaVersion = 39
    static let recordsSchemaVersion = 38
    static let targetModels = PersistentSchemaV39.models
    static let clonePreservesCanonicalHistory = true
    static let forkPreservesCanonicalHistory = true
    static let cloneAndForkInvalidateOutstandingSubmissionCapabilities = true
    static let derivedDuplicateProjectionIsRebuilt = true

    static func validate() -> Bool {
        sourcePersistentSchemaVersion == 38
            && targetPersistentSchemaVersion == 39
            && recordsSchemaVersion == 38
            && targetModels.count == 126
            && clonePreservesCanonicalHistory
            && forkPreservesCanonicalHistory
            && cloneAndForkInvalidateOutstandingSubmissionCapabilities
            && derivedDuplicateProjectionIsRebuilt
    }
}
enum C53AssetServiceReliabilityStoreGenerationBoundaryV1{static let sourcePersistentSchemaVersion=39,targetPersistentSchemaVersion=40,recordsSchemaVersion=39;static let derivedProjectionPersistent=false}
