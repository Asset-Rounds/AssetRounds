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
        guard (2...10).contains(sourcePointer.storeSchemaVersion),
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
        guard [.v2, .v3, .v4, .v5, .v6, .v7, .v8, .v9, .v10].contains(completed.targetRelease),
              PersistentSchemaReleaseRegistryV1.activeRelease == .v11 else {
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
            guard [.v3, .v4, .v5, .v6, .v7, .v8, .v9, .v10].contains(journal.targetRelease),
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
            let isTarget = digest == journal.desiredPointerDigest && pointer.generationID == canonicalString(for: journal.targetGenerationID) && pointer.storeSchemaVersion == 12
            guard isSource || isTarget else { throw StoreMigrationFailure.maintenanceRequired(.invalidPointer) }
            let identity = try pointer.identity()
            return try CurrentGenerationPointerV3(generationID: journal.targetGenerationID, generationManifestSHA256: manifestDigest, workspaceID: identity.workspaceID, replicaID: identity.replicaID, knownReplicaIDs: try pointer.knownReplicaIdentitySet(), storeSchemaVersion: 12).canonicalData()
        default:
            throw StoreMigrationFailure.invalidContract
        }
    }

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
        guard (3...11).contains(pointer.storeSchemaVersion),
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
        } else {
            _ = try requireV12Marker(in: container.mainContext, expectedMigrationID: manifest.migrationID)
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
            }
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
            }.sorted { ordered($0.id) < ordered($1.id) }
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
            let container = try makeV12Container(at: modelStoreURL, migrate: false)
            let marker = try requireV12Marker(
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
            guard existing.manifest.storeSchemaRelease == .v12,
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
            release: .v12,
            markerMigrationID: markerMigrationID
        )
        try protectGeneration(at: root, staging: false, requireModel: true)
        let manifest = try StoreGenerationManifestV1(
            generationID: newID,
            predecessorGenerationID: expectedOldID,
            migrationID: markerMigrationID,
            storeSchemaRelease: .v12,
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
            storeSchemaVersion: 12
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
        guard manifest.storeSchemaRelease == .v12 else {
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
            storeSchemaVersion: 12
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
            storeSchemaVersion: 12
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
              marker.first?.schemaVersion == 12,
              marker.first?.releaseID
                == PersistentSchemaReleaseRegistryV1.v12CompatibilityID,
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
            storeSchemaVersion: 12
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
            let container = try makeV12Container(at: modelStoreURL, migrate: false)
            let marker = try requireV12Marker(
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
                storeSchemaRelease: .v12,
                semanticSHA256: try semanticDigest(
                    at: modelStoreURL,
                    release: .v12
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
        guard (1...8).contains(recordsSchemaVersion),
              CompatibilityCanonicalV1.validSHA256(archiveProvenanceSHA256),
              (recordsSchemaVersion >= 5) == (sourceGenerationID != nil) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let root = restoreStagingGenerationURL(id: id)
        do {
            try authority.createStagingGeneration(id: id)
            let modelURL = root.appendingPathComponent(Self.modelStoreName)
            if recordsSchemaVersion == 8 {
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
            try autoreleasepool {
                let container = try makeV10Container(at: modelURL, migrate: true)
                try backfillV10AssetSemantics(
                    in: container.mainContext,
                    migrationID: id,
                    targetGenerationID: id
                )
            }
            try autoreleasepool {
                let container = try makeV11Container(at: modelURL, migrate: true)
                try backfillV11Marker(in: container.mainContext, migrationID: id)
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
            let container = try makeV12Container(at: modelStoreURL, migrate: false)
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
            storeSchemaRelease: .v12,
            semanticSHA256: try semanticDigest(
                at: modelStoreURL,
                release: .v12
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
            storeSchemaVersion: 12
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
            let container = try makeV12Container(
                at: modelStoreURL,
                migrate: false
            )
            do {
                let context = container.mainContext
                context.insert(PersistentSchemaReleaseMarker(
                    id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
                    schemaVersion: 12,
                    releaseID: PersistentSchemaReleaseRegistryV1.v12CompatibilityID,
                    predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v11CompatibilityID,
                    migrationID: markerMigrationID
                ))
                try context.save()
                _ = try requireV12Marker(in: context, expectedMigrationID: markerMigrationID)
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
            container = try makeV12Container(at: modelStoreURL, migrate: false)
            _ = try requireV12Marker(in: container.mainContext, expectedMigrationID: nil)
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
