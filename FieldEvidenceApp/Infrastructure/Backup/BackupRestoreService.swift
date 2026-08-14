import Foundation
import SwiftData

enum BackupRestoreServiceError: Error, Equatable {
    case contextHasChanges
    case currentGenerationInvalid
    case currentGenerationEmpty
    case currentGenerationNotEmpty
    case invalidPackage
    case invalidRestoreAuthority
    case materializationFailed
    case recoveryRequired
    case injectedFailure
}

enum BackupRestoreMode: Equatable, Sendable {
    case emptyInstall
    case replaceExisting
}

struct BackupRestoreCurrentSummaryV1: Equatable, Sendable {
    let signCount: Int
    let reportCount: Int
    let photoCount: Int
    let declaredPayloadByteCount: Int
    let consumedRootCount: Int
}

enum BackupRestoreFailurePoint: CaseIterable, Equatable, Sendable {
    case beforePreparedWrite
    case afterPreparedWrite
    case beforeGenerationInstall
    case afterGenerationInstall
    case beforePointerSwitch
    case afterPointerSwitch
    case beforeNewGenerationValidation
    case afterNewGenerationValidation
    case beforeCleanup
}

@MainActor
final class BackupRestoreFailureInjection {
    private var pending: BackupRestoreFailurePoint?

    init(failOnceAt point: BackupRestoreFailurePoint) {
        pending = point
    }

    func consume(_ point: BackupRestoreFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class BackupRestoreService {
    private let applicationSupportURL: URL
    private let generationFactory: StoreGenerationFactory
    private var generationAuthority: StoreRestoreGenerationAuthority!
    private let intentStore: RestoreIntentStore
    private let storagePreflight: StoragePreflightService
    private let fileManager: FileManager
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private let failureInjection: BackupRestoreFailureInjection?

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: BackupRestoreFailureInjection? = nil
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        let factory = StoreGenerationFactory(
            applicationSupportURL: root,
            fileManager: fileManager
        )
        let store = try RestoreIntentStore(
            applicationSupportURL: root,
            fileManager: fileManager
        )
        let dataRoot = root.appendingPathComponent(
            "FieldEvidenceData",
            isDirectory: true
        )
        let authority: StoreRestoreGenerationAuthority?
        if fileManager.fileExists(atPath: dataRoot.path) {
            authority = try factory.makeRestoreGenerationAuthority()
        } else {
            authority = nil
        }
        self.applicationSupportURL = root
        self.generationFactory = factory
        self.generationAuthority = authority
        self.intentStore = store
        self.storagePreflight = storagePreflight
        self.fileManager = fileManager
        self.now = now
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection
    }

    static func applicationSupportURL(
        containing generationRootURL: URL
    ) throws -> URL {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let data = generations.deletingLastPathComponent()
        let support = data.deletingLastPathComponent()
        guard generations.lastPathComponent == "generations",
              data.lastPathComponent == "FieldEvidenceData",
              let id = UUID(uuidString: root.lastPathComponent),
              id.uuidString.lowercased() == root.lastPathComponent else {
            throw BackupRestoreServiceError.currentGenerationInvalid
        }
        return support
    }

    static func isEmptyCurrent(_ modelContext: ModelContext) -> Bool {
        guard !modelContext.hasChanges else { return false }
        do {
            return try modelContext.fetchCount(FetchDescriptor<Site>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Asset>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()) == 0
                && modelContext.fetchCount(FetchDescriptor<EvidenceFile>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Issue>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Packet>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Report>()) == 0
        } catch {
            return false
        }
    }

    static func currentSummary(
        modelContext: ModelContext,
        generationRootURL: URL
    ) throws -> BackupRestoreCurrentSummaryV1 {
        guard !modelContext.hasChanges else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        let preview = try BackupExportService(
            modelContext: modelContext,
            generationRootURL: generationRootURL
        ).prepare()
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let roots = packets.filter(\.evaluationCounted).map(\.stableRootID)
        guard Set(roots).count == roots.count,
              !modelContext.hasChanges else {
            throw BackupRestoreServiceError.currentGenerationInvalid
        }
        return BackupRestoreCurrentSummaryV1(
            signCount: preview.signCount,
            reportCount: preview.reportCount,
            photoCount: preview.photoCount,
            declaredPayloadByteCount: preview.declaredPayloadByteCount,
            consumedRootCount: roots.count
        )
    }

    /// The only restore mutation path. Its explicit mode keeps Welcome and
    /// maintenance empty-only while Settings owns confirmed replacement.
    func restore(
        validatedPackage: ValidatedV4BackupPackageV1,
        currentModelContext: ModelContext,
        currentGenerationID: UUID,
        currentGenerationRootURL: URL,
        mode: BackupRestoreMode = .emptyInstall
    ) async throws -> StoreGenerationSession {
        guard !currentModelContext.hasChanges else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        try ensureGenerationAuthority()
        try generationAuthority.requireNoEraseAuthority()
        let initialRetiredIDs = try generationAuthority.retiredGenerationIDs()
        guard try generationFactory.currentGenerationID(
                  authority: generationAuthority
              ) == currentGenerationID,
              !initialRetiredIDs.contains(currentGenerationID),
              generationFactory.installedGenerationURL(id: currentGenerationID)
                == currentGenerationRootURL.standardizedFileURL,
              try ReportPDFAnchoredFile.rootIdentity(at: currentGenerationRootURL)
                == ReportPDFAnchoredFile.rootIdentity(
                    at: generationFactory.installedGenerationURL(
                        id: currentGenerationID
                    )
                ),
               try intentStore.load() == nil else {
            throw BackupRestoreServiceError.currentGenerationInvalid
        }
        let initialIsEmpty = Self.isEmptyCurrent(currentModelContext)
        let frozenCurrentRecords: V4BackupRecordsV1?
        switch mode {
        case .emptyInstall:
            guard initialIsEmpty else {
                throw BackupRestoreServiceError.currentGenerationNotEmpty
            }
            frozenCurrentRecords = nil
        case .replaceExisting:
            guard !initialIsEmpty else {
                throw BackupRestoreServiceError.currentGenerationEmpty
            }
            _ = try Self.currentSummary(
                modelContext: currentModelContext,
                generationRootURL: currentGenerationRootURL
            )
            frozenCurrentRecords = try records(in: currentModelContext)
        }
        do {
            _ = try BackupPackageValidatorV1().validate(
                stagedPackageURL: validatedPackage.stagedPackageURL
            )
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
        guard try BackupPackageValidatorV1().validate(
            stagedPackageURL: validatedPackage.stagedPackageURL
        ) == validatedPackage else {
            throw BackupRestoreServiceError.invalidPackage
        }
        try storagePreflight.checkBackupImport(
            declaredPayloadByteCount: Int64(
                validatedPackage.manifest.declaredPayloadByteCount
            ),
            onVolumeContaining: applicationSupportURL
        )
        try generationAuthority.requireNoEraseAuthority()
        try requireExclusiveLiveStaging(
            validatedPackage,
            currentGenerationID: currentGenerationID,
            retiredIDs: initialRetiredIDs
        )
        guard !currentModelContext.hasChanges,
              try generationFactory.currentGenerationID(
                  authority: generationAuthority
              ) == currentGenerationID else {
            throw BackupRestoreServiceError.contextHasChanges
        }

        let expectedRecords: V4BackupRecordsV1
        switch mode {
        case .emptyInstall:
            guard Self.isEmptyCurrent(currentModelContext) else {
                throw BackupRestoreServiceError.currentGenerationNotEmpty
            }
            expectedRecords = validatedPackage.records
        case .replaceExisting:
            guard !Self.isEmptyCurrent(currentModelContext),
                  let frozenCurrentRecords,
                  try records(in: currentModelContext) == frozenCurrentRecords else {
                throw BackupRestoreServiceError.contextHasChanges
            }
            _ = try Self.currentSummary(
                modelContext: currentModelContext,
                generationRootURL: currentGenerationRootURL
            )
            let plan: ReplacementRestorePlan
            do {
                plan = try ReplacementRestoreRule.makePlan(
                    ReplacementRestoreRuleInput(
                        currentPackets: frozenCurrentRecords.packets,
                        incomingPackets: validatedPackage.records.packets,
                        replacementAt: now()
                    )
                )
            } catch {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let replacementRecords = replacingPackets(
                in: validatedPackage.records,
                with: plan.packetsAfter
            )
            guard uniqueModelIDs(in: replacementRecords) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            expectedRecords = replacementRecords
        }

        let newGenerationID = makeUUID()
        let restoreID = makeUUID()
        guard newGenerationID != currentGenerationID,
              restoreID != currentGenerationID,
              restoreID != newGenerationID,
              !initialRetiredIDs.contains(newGenerationID) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let intent = RestoreIntentV1(
            newGenerationID: newGenerationID,
            newGenerationRelativePath:
                "FieldEvidenceData/generations/\(canonical(newGenerationID))",
            oldGenerationID: currentGenerationID,
            phase: .prepared,
            restoreID: restoreID,
            schemaVersion: 1,
            stagingGenerationRelativePath:
                "FieldEvidenceRestore/generations/\(canonical(newGenerationID))"
        )
        guard RestoreIntentCodecV1.valid(intent) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }

        do {
            try materialize(
                validatedPackage,
                records: expectedRecords,
                generationID: newGenerationID
            )
            try validateStagingGeneration(
                id: newGenerationID,
                expected: expectedRecords
            )
            try discardImportedPackage(validatedPackage, currentGenerationRootURL)
            let expectedInstalledNames = Set(
                (initialRetiredIDs + [currentGenerationID]).map(canonical)
            )
            guard Set(try generationAuthority.installedGenerationNames())
                    == expectedInstalledNames,
                  Set(try generationAuthority.restoreGenerationNames())
                    == [canonical(newGenerationID)],
                  try generationAuthority.importStagingNames().isEmpty else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }

            try inject(.beforePreparedWrite)
            try intentStore.create(intent)
            try inject(.afterPreparedWrite)

            try inject(.beforeGenerationInstall)
            try generationFactory.installRestoreStagingGeneration(
                id: newGenerationID,
                authority: generationAuthority
            )
            let installed = intent.advancing(to: .generationInstalled)
            try intentStore.replace(expected: intent, with: installed)
            try validateInstalledGeneration(
                id: newGenerationID,
                expected: expectedRecords
            )
            try inject(.afterGenerationInstall)

            try inject(.beforePointerSwitch)
            try generationFactory.switchCurrentGeneration(
                expected: currentGenerationID,
                to: newGenerationID,
                authority: generationAuthority
            )
            let switched = installed.advancing(to: .pointerSwitched)
            try intentStore.replace(expected: installed, with: switched)
            try inject(.afterPointerSwitch)

            try inject(.beforeNewGenerationValidation)
            let session = try generationFactory.openInstalledGeneration(
                id: newGenerationID,
                authority: generationAuthority
            )
            try validateLiveSession(
                session,
                expected: expectedRecords
            )
            let validated = switched.advancing(to: .newGenerationValidated)
            try intentStore.replace(expected: switched, with: validated)
            try inject(.afterNewGenerationValidation)

            try inject(.beforeCleanup)
            try generationFactory.retireGeneration(
                oldID: currentGenerationID,
                currentID: newGenerationID,
                authority: generationAuthority
            )
            try intentStore.remove(expected: validated)
            try cleanupEmptyRestoreDirectories()
            return session
        } catch let error as BackupRestoreServiceError
            where error == .injectedFailure {
            throw error
        } catch {
            if let recovered = try? reconcileAtStartup() {
                return recovered
            }
            throw error
        }
    }

    /// Runs before ordinary pointer maintenance. A returned session is the
    /// fully validated new current generation; nil means old remains current or
    /// no intent existed.
    func reconcileAtStartup() throws -> StoreGenerationSession? {
        guard let intent = try intentStore.load() else {
            let dataRoot = applicationSupportURL.appendingPathComponent(
                "FieldEvidenceData",
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: dataRoot.path) else {
                return nil
            }
            try ensureGenerationAuthority()
            try cleanupAbandonedRestoreStaging()
            return nil
        }
        try ensureGenerationAuthority()
        guard RestoreIntentCodecV1.valid(intent) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let currentID = try generationFactory.currentGenerationID(
            authority: generationAuthority
        )
        let retiredIDs = try generationAuthority.retiredGenerationIDs()
        let presence = try generationFactory.generationPresence(
            id: intent.newGenerationID,
            authority: generationAuthority
        )
        var expectedInstalledNames = Set(retiredIDs.map(canonical))
        expectedInstalledNames.insert(canonical(intent.oldGenerationID))
        if presence.installed {
            expectedInstalledNames.insert(canonical(intent.newGenerationID))
        }
        let expectedStagingNames: Set<String> = presence.staging
            ? [canonical(intent.newGenerationID)]
            : []
        guard Set(try generationAuthority.installedGenerationNames())
                == expectedInstalledNames,
              Set(try generationAuthority.restoreGenerationNames())
                == expectedStagingNames,
              try generationAuthority.importStagingNames().isEmpty else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        guard let oldSession = validInstalledGeneration(
            id: intent.oldGenerationID
        ), let oldRecords = try? records(in: oldSession.modelContext) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        switch intent.phase {
        case .prepared, .generationInstalled, .pointerSwitched:
            guard !retiredIDs.contains(intent.oldGenerationID),
                  !retiredIDs.contains(intent.newGenerationID) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        case .newGenerationValidated:
            guard !retiredIDs.contains(intent.newGenerationID) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        if presence.installed {
            try requireNoUnexpectedInstalledBytes(id: intent.newGenerationID)
        }
        if presence.staging {
            try requireNoUnexpectedStagingBytes(id: intent.newGenerationID)
        }
        let installedNewSession = presence.installed
            ? validInstalledGeneration(id: intent.newGenerationID)
            : nil
        if let installedNewSession {
            let newRecords = try records(in: installedNewSession.modelContext)
            guard validMonotonicUnion(from: oldRecords, to: newRecords) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        if presence.staging,
           let stagedRecords = validStagingGenerationRecords(
               id: intent.newGenerationID
           ),
           !validMonotonicUnion(from: oldRecords, to: stagedRecords) {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }

        switch intent.phase {
        case .prepared:
            guard currentID == intent.oldGenerationID else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            if presence.installed {
                guard installedNewSession != nil,
                      !presence.staging else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try generationFactory.removeInstalledGeneration(
                    id: intent.newGenerationID,
                    keeping: intent.oldGenerationID,
                    authority: generationAuthority
                )
            } else if presence.staging {
                try generationFactory.removeRestoreStagingGeneration(
                    id: intent.newGenerationID,
                    authority: generationAuthority
                )
            }
            try intentStore.remove(expected: intent)
            try cleanupEmptyRestoreDirectories()
            return nil

        case .generationInstalled:
            guard !presence.staging, presence.installed else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let newSession = installedNewSession
            guard let newSession else {
                if currentID == intent.newGenerationID {
                    try generationFactory.switchCurrentGeneration(
                        expected: intent.newGenerationID,
                        to: intent.oldGenerationID,
                        authority: generationAuthority
                    )
                } else if currentID != intent.oldGenerationID {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try generationFactory.removeInstalledGeneration(
                    id: intent.newGenerationID,
                    keeping: intent.oldGenerationID,
                    authority: generationAuthority
                )
                try intentStore.remove(expected: intent)
                try cleanupEmptyRestoreDirectories()
                return nil
            }
            if currentID == intent.oldGenerationID {
                try generationFactory.switchCurrentGeneration(
                    expected: intent.oldGenerationID,
                    to: intent.newGenerationID,
                    authority: generationAuthority
                )
            } else if currentID != intent.newGenerationID {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let switched = intent.advancing(to: .pointerSwitched)
            try intentStore.replace(expected: intent, with: switched)
            return try finishValidatedNew(
                switched,
                session: newSession
            )

        case .pointerSwitched:
            guard !presence.staging, presence.installed else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let newSession = installedNewSession
            guard let newSession else {
                guard currentID == intent.newGenerationID else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try generationFactory.switchCurrentGeneration(
                    expected: intent.newGenerationID,
                    to: intent.oldGenerationID,
                    authority: generationAuthority
                )
                try generationFactory.removeInstalledGeneration(
                    id: intent.newGenerationID,
                    keeping: intent.oldGenerationID,
                    authority: generationAuthority
                )
                try intentStore.remove(expected: intent)
                try cleanupEmptyRestoreDirectories()
                return nil
            }
            guard currentID == intent.newGenerationID else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            return try finishValidatedNew(intent, session: newSession)

        case .newGenerationValidated:
            let newSession = installedNewSession
            guard !presence.staging,
                  presence.installed,
                  currentID == intent.newGenerationID,
                  let newSession else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try generationFactory.retireGeneration(
                oldID: intent.oldGenerationID,
                currentID: intent.newGenerationID,
                authority: generationAuthority
            )
            try intentStore.remove(expected: intent)
            try cleanupEmptyRestoreDirectories()
            return newSession
        }
    }
}

private extension BackupRestoreService {
    func ensureGenerationAuthority() throws {
        if generationAuthority == nil {
            generationAuthority = try generationFactory.makeRestoreGenerationAuthority()
        } else {
            try generationAuthority.verify()
        }
    }

    func requireExclusiveLiveStaging(
        _ value: ValidatedV4BackupPackageV1,
        currentGenerationID: UUID,
        retiredIDs: [UUID]
    ) throws {
        let expectedParent = applicationSupportURL
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
            .standardizedFileURL
        let stage = value.stagedPackageURL.standardizedFileURL
        let name = stage.lastPathComponent
        let base = stage.deletingLastPathComponent()
        let stem = stage.deletingPathExtension().lastPathComponent
        guard base == expectedParent,
              stage.pathExtension == "fieldrecordbackup",
              let identifier = UUID(uuidString: stem),
              canonical(identifier) == stem,
              Set(try generationAuthority.importStagingNames()) == [name],
              try generationAuthority.restoreGenerationNames().isEmpty,
              Set(try generationAuthority.installedGenerationNames())
                == Set((retiredIDs + [currentGenerationID]).map(canonical)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func finishValidatedNew(
        _ intent: RestoreIntentV1,
        session: StoreGenerationSession
    ) throws -> StoreGenerationSession {
        try validateLiveSession(session, expected: nil)
        let validated = intent.advancing(to: .newGenerationValidated)
        try intentStore.replace(expected: intent, with: validated)
        try generationFactory.retireGeneration(
            oldID: intent.oldGenerationID,
            currentID: intent.newGenerationID,
            authority: generationAuthority
        )
        try intentStore.remove(expected: validated)
        try cleanupEmptyRestoreDirectories()
        return session
    }

    func replacingPackets(
        in records: V4BackupRecordsV1,
        with packets: [V4BackupPacketDTO]
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: records.assets,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            packets: packets,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func uniqueModelIDs(in records: V4BackupRecordsV1) -> Bool {
        let ids = records.sites.map(\.id)
            + records.assets.map(\.id)
            + records.workflowRecords.map(\.id)
            + records.evidenceFiles.map(\.id)
            + records.issues.map(\.id)
            + records.packets.map(\.id)
            + records.reports.map(\.id)
        return Set(ids).count == ids.count
    }

    func materialize(
        _ value: ValidatedV4BackupPackageV1,
        records: V4BackupRecordsV1,
        generationID: UUID
    ) throws {
        do {
            try generationFactory.createRestoreStagingGeneration(
                id: generationID,
                authority: generationAuthority
            ) { context in
                try insert(records, into: context)
            }
            try writeMembers(
                value,
                to: generationFactory.restoreStagingGenerationURL(
                    id: generationID
                )
            )
        } catch {
            try? generationFactory.removeRestoreStagingGeneration(
                id: generationID,
                authority: generationAuthority
            )
            throw BackupRestoreServiceError.materializationFailed
        }
    }

    func insert(_ records: V4BackupRecordsV1, into context: ModelContext) throws {
        guard records.recordsSchemaVersion == 1 else {
            throw BackupRestoreServiceError.invalidPackage
        }
        for value in records.sites {
            context.insert(Site(
                id: value.id,
                label: value.label,
                address: value.address,
                timeZoneID: value.timeZoneID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in records.assets {
            context.insert(Asset(
                id: value.id,
                siteID: value.siteID,
                packID: value.packID,
                packSchemaVersion: value.packSchemaVersion,
                packContentVersion: value.packContentVersion,
                label: value.label,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in records.workflowRecords {
            guard let revision = WorkflowRevisionKind(rawValue: value.revisionKind),
                  let stage = WorkflowStage(rawValue: value.stage),
                  let state = WorkflowState(rawValue: value.state),
                  value.draftStepKey == nil
                    || WorkflowDraftStep(rawValue: value.draftStepKey!) != nil else {
                throw BackupRestoreServiceError.invalidPackage
            }
            context.insert(WorkflowRecord(
                id: value.id,
                assetID: value.assetID,
                packetID: value.packetID,
                issueID: value.issueID,
                parentRecordID: value.parentRecordID,
                recordRevisionRootID: value.recordRevisionRootID,
                revisesRecordID: value.revisesRecordID,
                evidenceSourceRecordID: value.evidenceSourceRecordID,
                revisionKind: revision,
                stage: stage,
                state: state,
                draftStepKey: value.draftStepKey.flatMap(WorkflowDraftStep.init),
                startedAt: value.startedAt,
                completedAt: value.completedAt,
                observedAtUTC: value.observedAtUTC,
                timeZoneID: value.timeZoneID,
                utcOffsetMinutes: value.utcOffsetMinutes,
                localDate: value.localDate,
                localTime: value.localTime,
                afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
                afterDarkAcknowledgementAccepted:
                    value.afterDarkAcknowledgementAccepted,
                safePositionAcknowledgementKey:
                    value.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy:
                    value.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion:
                    value.safePositionAcknowledgementVersion,
                safePositionAcknowledgementAccepted:
                    value.safePositionAcknowledgementAccepted,
                packID: value.packID,
                packSchemaVersion: value.packSchemaVersion,
                packContentVersion: value.packContentVersion,
                pdfTemplateID: value.pdfTemplateID,
                pdfTemplateVersion: value.pdfTemplateVersion,
                outcomeKey: value.outcomeKey,
                couldNotVerifyKey: value.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot:
                    value.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion:
                    value.couldNotVerifyRegistryVersion,
                workPerformedLocalDate: value.workPerformedLocalDate,
                workDescription: value.workDescription,
                note: value.note,
                finalizationMutationID: value.finalizationMutationID
            ))
        }
        for value in records.evidenceFiles {
            context.insert(EvidenceFile(
                id: value.id,
                recordID: value.recordID,
                purposeKey: value.purposeKey,
                relativePath: value.relativePath,
                mimeType: value.mimeType,
                byteCount: value.byteCount,
                sha256: value.sha256,
                createdAt: value.createdAt,
                thumbnailRelativePath: value.thumbnailRelativePath,
                thumbnailByteCount: value.thumbnailByteCount,
                thumbnailSHA256: value.thumbnailSHA256
            ))
        }
        for value in records.issues {
            guard let status = IssueStatus(rawValue: value.status) else {
                throw BackupRestoreServiceError.invalidPackage
            }
            context.insert(Issue(
                id: value.id,
                assetID: value.assetID,
                openedByRecordID: value.openedByRecordID,
                labelKey: value.labelKey,
                labelDisplaySnapshot: value.labelDisplaySnapshot,
                status: status,
                resolvedByRecordID: value.resolvedByRecordID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in records.packets {
            context.insert(Packet(
                id: value.id,
                stableRootID: value.stableRootID,
                currentRecordID: value.currentRecordID,
                evaluationCounted: value.evaluationCounted,
                contentDeletedAt: value.contentDeletedAt,
                createdAt: value.createdAt
            ))
        }
        for value in records.reports {
            guard let state = ReportPDFState(rawValue: value.pdfState) else {
                throw BackupRestoreServiceError.invalidPackage
            }
            context.insert(Report(
                id: value.id,
                packetID: value.packetID,
                sourceRecordID: value.sourceRecordID,
                snapshotSchemaVersion: value.snapshotSchemaVersion,
                snapshotRelativePath: value.snapshotRelativePath,
                snapshotSHA256: value.snapshotSHA256,
                pdfState: state,
                pdfRelativePath: value.pdfRelativePath,
                pdfSHA256: value.pdfSHA256,
                createdAt: value.createdAt,
                replacesReportID: value.replacesReportID
            ))
        }
    }

    func writeMembers(
        _ value: ValidatedV4BackupPackageV1,
        to root: URL
    ) throws {
        for evidence in value.records.evidenceFiles {
            let id = canonical(evidence.id)
            let directory = root.appendingPathComponent(
                "evidence/\(id)",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try writeExact(
                value.members["media/\(id).jpg"],
                to: root.appendingPathComponent(evidence.relativePath),
                expectedHash: evidence.sha256
            )
            try writeExact(
                value.members["thumbnails/\(id).jpg"],
                to: root.appendingPathComponent(evidence.thumbnailRelativePath),
                expectedHash: evidence.thumbnailSHA256
            )
        }
        if !value.records.reports.isEmpty {
            try fileManager.createDirectory(
                at: root.appendingPathComponent("snapshots", isDirectory: true),
                withIntermediateDirectories: false
            )
        }
        if value.records.reports.contains(where: { $0.pdfState == "ready" }) {
            try fileManager.createDirectory(
                at: root.appendingPathComponent("pdfs", isDirectory: true),
                withIntermediateDirectories: false
            )
        }
        for report in value.records.reports {
            try writeExact(
                value.members[report.snapshotRelativePath],
                to: root.appendingPathComponent(report.snapshotRelativePath),
                expectedHash: report.snapshotSHA256
            )
            if let path = report.pdfRelativePath,
               let hash = report.pdfSHA256 {
                try writeExact(
                    value.members[path],
                    to: root.appendingPathComponent(path),
                    expectedHash: hash
                )
            }
        }
    }

    func writeExact(_ data: Data?, to url: URL, expectedHash: String) throws {
        guard let data,
              CanonicalJSONV1.sha256(data) == expectedHash else {
            throw BackupRestoreServiceError.invalidPackage
        }
        try data.write(to: url, options: .withoutOverwriting)
        guard try Data(contentsOf: url) == data else {
            throw BackupRestoreServiceError.materializationFailed
        }
    }

    func validateStagingGeneration(
        id: UUID,
        expected: V4BackupRecordsV1
    ) throws {
        let session = try generationFactory.openRestoreStagingGeneration(
            id: id,
            authority: generationAuthority
        )
        try validateRows(session.modelContext, expected: expected)
        try validateFrozenFiles(
            root: session.generationRootURL,
            records: expected
        )
        try validateGenerationTree(
            generationAuthority.stagingTree(id: id),
            records: expected
        )
    }

    func validateInstalledGeneration(
        id: UUID,
        expected: V4BackupRecordsV1
    ) throws {
        let session = try generationFactory.openInstalledGeneration(
            id: id,
            authority: generationAuthority
        )
        try validateLiveSession(session, expected: expected)
    }

    func validateLiveSession(
        _ session: StoreGenerationSession,
        expected: V4BackupRecordsV1?
    ) throws {
        guard !session.modelContext.hasChanges else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        if let expected {
            try validateRows(session.modelContext, expected: expected)
        }
        do {
            _ = try BackupExportService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                now: { Date(timeIntervalSince1970: 0) }
            ).prepare()
        } catch {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let frozenRecords: V4BackupRecordsV1
        if let expected {
            frozenRecords = expected
        } else {
            frozenRecords = try records(in: session.modelContext)
        }
        try validateGenerationTree(
            generationAuthority.installedTree(id: session.generationID),
            records: frozenRecords
        )
    }

    func validateGenerationTree(
        _ tree: StoreRestoreGenerationAuthority.Tree,
        records: V4BackupRecordsV1
    ) throws {
        let expected = expectedGenerationTree(records: records)
        guard tree.directories == expected.directories,
              expected.files.isSubset(of: tree.files),
              tree.files.isSubset(of: expected.files.union(expected.optionalFiles)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func requireNoUnexpectedInstalledBytes(id: UUID) throws {
        let session = try generationFactory.openInstalledGeneration(
            id: id,
            authority: generationAuthority
        )
        let frozenRecords = try records(in: session.modelContext)
        let tree = try generationAuthority.installedTree(id: id)
        let expected = expectedGenerationTree(records: frozenRecords)
        guard tree.directories.isSubset(of: expected.directories),
              tree.files.isSubset(of: expected.files.union(expected.optionalFiles)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func requireNoUnexpectedStagingBytes(id: UUID) throws {
        let session = try generationFactory.openRestoreStagingGeneration(
            id: id,
            authority: generationAuthority
        )
        let frozenRecords = try records(in: session.modelContext)
        let tree = try generationAuthority.stagingTree(id: id)
        let expected = expectedGenerationTree(records: frozenRecords)
        guard tree.directories.isSubset(of: expected.directories),
              tree.files.isSubset(of: expected.files.union(expected.optionalFiles)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func expectedGenerationTree(
        records: V4BackupRecordsV1
    ) -> (
        directories: Set<String>,
        files: Set<String>,
        optionalFiles: Set<String>
    ) {
        var expectedFiles: Set<String> = ["model.sqlite"]
        var expectedDirectories = Set<String>()
        if !records.evidenceFiles.isEmpty {
            expectedDirectories.insert("evidence")
        }
        for evidence in records.evidenceFiles {
            expectedDirectories.insert("evidence/\(canonical(evidence.id))")
            expectedFiles.insert(evidence.relativePath)
            expectedFiles.insert(evidence.thumbnailRelativePath)
        }
        if !records.reports.isEmpty {
            expectedDirectories.insert("snapshots")
        }
        if records.reports.contains(where: {
            $0.pdfState == ReportPDFState.ready.rawValue
        }) {
            expectedDirectories.insert("pdfs")
        }
        for report in records.reports {
            expectedFiles.insert(report.snapshotRelativePath)
            if let path = report.pdfRelativePath {
                expectedFiles.insert(path)
            }
        }
        let optionalSQLiteSidecars: Set<String> = [
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        return (
            expectedDirectories,
            expectedFiles,
            optionalSQLiteSidecars
        )
    }

    func validInstalledGeneration(id: UUID) -> StoreGenerationSession? {
        guard let session = try? generationFactory.openInstalledGeneration(
            id: id,
            authority: generationAuthority
        ),
              (try? validateLiveSession(session, expected: nil)) != nil else {
            return nil
        }
        return session
    }

    func validStagingGenerationRecords(id: UUID) -> V4BackupRecordsV1? {
        do {
            let session = try generationFactory.openRestoreStagingGeneration(
                id: id,
                authority: generationAuthority
            )
            guard !session.modelContext.hasChanges else { return nil }
            let frozenRecords = try records(in: session.modelContext)
            _ = try BackupExportService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                now: { Date(timeIntervalSince1970: 0) }
            ).prepare()
            try validateGenerationTree(
                generationAuthority.stagingTree(id: id),
                records: frozenRecords
            )
            return frozenRecords
        } catch {
            return nil
        }
    }

    func validMonotonicUnion(
        from current: V4BackupRecordsV1,
        to replacement: V4BackupRecordsV1
    ) -> Bool {
        guard let plan = try? ReplacementRestoreRule.makePlan(
            ReplacementRestoreRuleInput(
                currentPackets: current.packets,
                incomingPackets: replacement.packets,
                replacementAt: now()
            )
        ) else {
            return false
        }
        return plan.packetsAfter == replacement.packets
    }

    func validateRows(
        _ context: ModelContext,
        expected: V4BackupRecordsV1
    ) throws {
        guard try records(in: context) == expected else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func validateFrozenFiles(root: URL, records: V4BackupRecordsV1) throws {
        for evidence in records.evidenceFiles {
            let original = try Data(contentsOf: root.appendingPathComponent(
                evidence.relativePath
            ))
            let thumbnail = try Data(contentsOf: root.appendingPathComponent(
                evidence.thumbnailRelativePath
            ))
            guard original.count == evidence.byteCount,
                  thumbnail.count == evidence.thumbnailByteCount,
                  CanonicalJSONV1.sha256(original) == evidence.sha256,
                  CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        for report in records.reports {
            let snapshot = try Data(contentsOf: root.appendingPathComponent(
                report.snapshotRelativePath
            ))
            guard CanonicalJSONV1.sha256(snapshot) == report.snapshotSHA256 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            if let path = report.pdfRelativePath,
               let hash = report.pdfSHA256 {
                let pdf = try Data(contentsOf: root.appendingPathComponent(path))
                guard CanonicalJSONV1.sha256(pdf) == hash else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
            }
        }
    }

    func records(in context: ModelContext) throws -> V4BackupRecordsV1 {
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
            }.sorted { canonical($0.id) < canonical($1.id) },
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
            }.sorted { canonical($0.id) < canonical($1.id) },
            issues: issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    assetID: $0.assetID, openedByRecordID: $0.openedByRecordID,
                    labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot,
                    status: $0.status,
                    resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            packets: packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt,
                    createdAt: $0.createdAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
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
            }.sorted { canonical($0.id) < canonical($1.id) },
            sites: sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    label: $0.label, address: $0.address,
                    timeZoneID: $0.timeZoneID, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            workflowRecords: workflow.map(workflowDTO)
                .sorted { canonical($0.id) < canonical($1.id) }
        )
    }

    func workflowDTO(_ value: WorkflowRecord) -> V4BackupWorkflowRecordDTO {
        .init(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID,
            issueID: value.issueID, parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage,
            state: value.state, draftStepKey: value.draftStepKey,
            startedAt: value.startedAt, completedAt: value.completedAt,
            observedAtUTC: value.observedAtUTC, timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes, localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted:
                value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy:
                value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion:
                value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted:
                value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }

    func discardImportedPackage(
        _ value: ValidatedV4BackupPackageV1,
        _ currentGenerationRootURL: URL
    ) throws {
        do {
            try BackupImportService(
                generationRootURL: currentGenerationRootURL,
                scopedAccess: .alreadyAuthorized
            ).discard(value)
        } catch {
            throw BackupRestoreServiceError.materializationFailed
        }
    }

    func cleanupAbandonedRestoreStaging() throws {
        for name in try generationAuthority.restoreGenerationNames() {
            guard let id = UUID(uuidString: name), canonical(id) == name else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try generationAuthority.removeStagingGeneration(id: id)
        }
        for name in try generationAuthority.importStagingNames() {
            let url = URL(fileURLWithPath: name)
            let canonicalName = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "fieldrecordbackup",
                  let id = UUID(uuidString: canonicalName),
                  canonical(id) == canonicalName else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try generationAuthority.removeImportStagingPackage(name: name)
        }
        try cleanupEmptyRestoreDirectories()
    }

    func cleanupEmptyRestoreDirectories() throws {
        // These empty parents remain pinned for the service lifetime. Removing
        // and recreating them would weaken the authority that makes recovery
        // cleanup descriptor-relative.
        try generationAuthority.verify()
    }

    func inject(_ point: BackupRestoreFailurePoint) throws {
        if failureInjection?.consume(point) == true {
            throw BackupRestoreServiceError.injectedFailure
        }
    }

    func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}
