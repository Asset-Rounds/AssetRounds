import Foundation
import SwiftData

/// Applies content changes without saving. MutationJournalStoreV1 owns the
/// single atomic save containing content, revisions, and immutable receipt.
@MainActor
final class WorkspaceWriterAdapterV1: WorkspaceWriterAdapterPortV1 {
    static let supportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .createFirstSign,
        .createCheckDraft,
        .acceptCheckEvidence,
        .updateSiteTimeZone,
    ]

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard !modelContext.hasChanges else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        do {
            _ = try ObservationAndTimeRowStoreV1.validatedIndex(in: modelContext)
        } catch {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        switch command {
        case let .createFirstSign(value):
            return try createFirstSign(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .createCheckDraft(value):
            return try createCheckDraft(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .acceptCheckEvidence(value):
            return try acceptCheckEvidence(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .updateSiteTimeZone(value):
            return try updateSiteTimeZone(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case .deleteAsset,
             .deleteSite,
             .eraseWorkspace,
             .finalizeCheck,
             .finalizeCorrection,
             .recordWork,
             .restoreWorkspace,
             .archiveEntities:
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
    }

    func queryExisting(
        identities: [WorkspaceEntityIdentityV1]
    ) throws -> (
        identities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) {
        guard !modelContext.hasChanges,
              identities.count <= 256,
              Set(identities).count == identities.count else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        var existing: [WorkspaceEntityIdentityV1] = []
        var bindings: [WorkspacePackageBindingV1] = []
        let deletionLedgerRows: [DeletionLedgerRow]
        let deletionLedgerIdentities: [DeletionIdentityV2]
        if identities.contains(where: { $0.kind == .deletionLedgerEntry }) {
            deletionLedgerRows = try modelContext.fetch(FetchDescriptor<DeletionLedgerRow>())
            guard Set(deletionLedgerRows.map(\.typedID)).count == deletionLedgerRows.count else {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            do {
                deletionLedgerIdentities = try deletionLedgerRows.map {
                    try DeletionIdentityV2(typedID: $0.typedID)
                }
            } catch {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        } else {
            deletionLedgerRows = []
            deletionLedgerIdentities = []
        }
        for identity in identities {
            let id = identity.id
            let exists: Bool
            switch identity.kind {
            case .site:
                let values = try modelContext.fetch(FetchDescriptor<Site>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .asset:
                let assets = try modelContext.fetch(FetchDescriptor<Asset>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard assets.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = assets.count == 1
                if let asset = assets.first {
                    bindings.append(WorkspacePackageBindingV1(
                        assetID: asset.id,
                        packageID: asset.packID,
                        packageSchemaVersion: asset.packSchemaVersion,
                        packageContentVersion: asset.packContentVersion
                    ))
                }
            case .workflowRecord:
                let values = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .evidenceFile:
                let values = try modelContext.fetch(FetchDescriptor<EvidenceFile>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .issue:
                let values = try modelContext.fetch(FetchDescriptor<Issue>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .packet:
                let values = try modelContext.fetch(FetchDescriptor<Packet>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .report:
                let values = try modelContext.fetch(FetchDescriptor<Report>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .deletionLedgerEntry:
                let matches = deletionLedgerIdentities.filter { $0.id == identity.id }
                guard matches.count <= 1 else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = matches.count == 1
            }
            if exists { existing.append(identity) }
        }
        return (
            existing.sorted { $0.stableKey < $1.stableKey },
            bindings.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
        )
    }

    func createFirstSign(
        _ value: FirstSignMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard value.assetLabel == value.assetLabel.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.assetLabel.isEmpty,
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              Self.isFinite(value.createdAt),
              value.newSite == nil || value.newSite?.id == value.siteID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        let siteID = value.siteID
        let existingSites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        if value.newSite == nil {
            guard existingSites.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        } else {
            guard existingSites.isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        }

        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite {
            guard site.label == site.label.trimmingCharacters(in: .whitespacesAndNewlines),
                  !site.label.isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )

        if let site = value.newSite {
            modelContext.insert(Site(
                id: site.id,
                label: site.label,
                address: site.address,
                timeZoneID: site.timeZoneID,
                createdAt: value.createdAt
            ))
        }
        modelContext.insert(Asset(
            id: value.assetID,
            siteID: value.siteID,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            label: value.assetLabel,
            createdAt: value.createdAt
        ))
        return effect
    }

    func createCheckDraft(
        _ value: CheckDraftMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard let stage = WorkflowStage(rawValue: value.stage),
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              !value.pdfTemplateID.isEmpty,
              value.pdfTemplateVersion > 0,
              Self.isFinite(value.startedAt),
              value.observedAtUTC.map({ Self.isFinite($0) }) ?? true else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard (value.observationBasis == nil) == (value.temporalContext == nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let observationBasisData: Data
        let temporalContextData: Data
        do {
            if let observationBasis = value.observationBasis,
               let temporalContext = value.temporalContext {
                try Self.requireLegacyTimeProjectionMatches(
                    temporalContext,
                    command: value
                )
                observationBasisData = try ObservationAndTimeCodecV1.encode(
                    observationBasis
                )
                temporalContextData = try ObservationAndTimeCodecV1.encode(
                    temporalContext
                )
            } else {
                let migratedBasis = try ObservationAndTimeLegacyMigrationV1.observationBasis(
                    couldNotVerifyKey: nil,
                    displaySnapshot: nil,
                    registryVersion: nil
                )
                let migratedTemporal = try ObservationAndTimeLegacyMigrationV1.temporalContext(
                    observedAtUTC: value.observedAtUTC,
                    recordedAtUTC: value.startedAt,
                    timeZoneID: value.timeZoneID,
                    utcOffsetMinutes: value.utcOffsetMinutes,
                    localDate: value.localDate,
                    localTime: value.localTime
                )
                guard let migratedBasis, let migratedTemporal else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                observationBasisData = try ObservationAndTimeCodecV1.encode(migratedBasis)
                temporalContextData = try ObservationAndTimeCodecV1.encode(migratedTemporal)
            }
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftStep: WorkflowDraftStep?
        if let key = value.draftStepKey {
            guard let parsed = WorkflowDraftStep(rawValue: key) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            draftStep = parsed
        } else {
            draftStep = nil
        }
        guard (stage == .work && draftStep == nil)
                || (stage != .work && draftStep != nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let recordID = value.recordID
        guard try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).count == 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID)
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [identity],
            temporaryRelativePath: temporaryRelativePath
        )
        modelContext.insert(WorkflowRecord(
            id: value.recordID,
            assetID: value.assetID,
            packetID: nil,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordID,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: stage,
            state: .draft,
            draftStepKey: draftStep,
            startedAt: value.startedAt,
            completedAt: nil,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        ))
        modelContext.insert(try ObservationAndTimeRow(
            recordID: value.recordID,
            observationBasisV1Data: observationBasisData,
            temporalContextV1Data: temporalContextData
        ))
        return effect
    }

    private static func requireLegacyTimeProjectionMatches(
        _ temporal: TemporalContextV1,
        command: CheckDraftMutationV1
    ) throws {
        try temporal.validate()
        guard temporal.occurredAtUTC == command.observedAtUTC,
              temporal.localDate == command.localDate,
              temporal.localTime == command.localTime,
              temporal.ianaTimeZoneIdentifier == command.timeZoneID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let expectedOffsetSeconds: Int?
        if let minutes = command.utcOffsetMinutes {
            let (seconds, overflow) = minutes.multipliedReportingOverflow(
                by: 60
            )
            guard !overflow else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            expectedOffsetSeconds = seconds
        } else {
            expectedOffsetSeconds = nil
        }
        guard temporal.utcOffsetSeconds == expectedOffsetSeconds else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func acceptCheckEvidence(
        _ value: CheckEvidenceMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard WorkflowDraftStep(rawValue: value.nextDraftStepKey) != nil,
              value.byteCount >= 0,
              value.thumbnailByteCount >= 0,
              Self.isSHA256(value.sha256),
              Self.isSHA256(value.thumbnailSHA256),
              Self.isSafeRelativePath(value.relativePath),
              Self.isSafeRelativePath(value.thumbnailRelativePath),
              !value.mimeType.isEmpty,
              !value.purposeKey.isEmpty,
              Self.isFinite(value.createdAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftID = value.draftID
        let drafts = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == draftID }
        ))
        guard drafts.count == 1,
              let draft = drafts.first,
              draft.state == WorkflowState.draft.rawValue else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let evidenceID = value.evidenceID
        guard try modelContext.fetch(FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.id == evidenceID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identities = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
        ]
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
        draft.draftStepKey = value.nextDraftStepKey
        modelContext.insert(EvidenceFile(
            id: value.evidenceID,
            recordID: value.draftID,
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
        return effect
    }

    func updateSiteTimeZone(
        _ value: SiteTimeZoneMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard TimeZone(identifier: value.timeZoneID) != nil,
              Self.isFinite(value.confirmedAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let siteID = value.siteID
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [try WorkspaceEntityIdentityV1(kind: .site, id: siteID)],
            temporaryRelativePath: temporaryRelativePath
        )
        site.timeZoneID = value.timeZoneID
        site.updatedAt = value.confirmedAt
        return effect
    }

    func rollback() {
        modelContext.rollback()
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("..") && !value.contains("\\")
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }
}
