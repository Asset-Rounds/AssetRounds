import Foundation
import SwiftData

enum BackupExportServiceError: Error, Equatable {
    case invalidGeneration
    case contextHasChanges
    case invalidAuthority
    case stalePreview
    case destinationInvalid
    case destinationExists
    case writeFailed
}

@MainActor
final class BackupExportService {
    private struct Rows {
        let sites: [Site]
        let assets: [Asset]
        let records: [WorkflowRecord]
        let evidence: [EvidenceFile]
        let issues: [Issue]
        let packets: [Packet]
        let reports: [Report]
    }

    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity?
    private let storagePreflight: StoragePreflightService
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private let appVersion: () -> String
    private let appBuild: () -> String
    private let fileManager: FileManager
    private var prepared: PreparedV4BackupV1?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.storagePreflight = storagePreflight
        self.now = now
        self.makeUUID = makeUUID
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.fileManager = fileManager
        let root = generationRootURL.standardizedFileURL
        let dataRoot = root.deletingLastPathComponent().deletingLastPathComponent()
        if root.isFileURL,
           root.deletingLastPathComponent().lastPathComponent == "generations",
           dataRoot.lastPathComponent == "FieldEvidenceData",
           let id = UUID(uuidString: root.lastPathComponent),
           id.uuidString.lowercased() == root.lastPathComponent {
            rootIdentity = try? ReportPDFAnchoredFile.rootIdentity(at: root)
        } else {
            rootIdentity = nil
        }
    }

    func prepare() throws -> BackupExportPreviewV1 {
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        let value = try buildPrepared(
            previewID: makeUUID(),
            exportedAt: now()
        )
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        prepared = value
        return value.preview
    }

    func export(
        previewID: UUID,
        to destinationDirectoryURL: URL
    ) throws -> URL {
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        guard let frozen = prepared, frozen.preview.id == previewID else {
            throw BackupExportServiceError.stalePreview
        }
        let rebuilt = try buildPrepared(
            previewID: previewID,
            exportedAt: frozen.manifest.exportedAt
        )
        guard rebuilt == frozen else {
            throw BackupExportServiceError.stalePreview
        }
        guard destinationDirectoryURL.isFileURL else {
            throw BackupExportServiceError.destinationInvalid
        }

        let destination = destinationDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw BackupExportServiceError.destinationInvalid
        }
        do {
            try storagePreflight.checkBackupExport(
                declaredPayloadByteCount: Int64(frozen.preview.declaredPayloadByteCount),
                onVolumeContaining: destination
            )
        } catch {
            throw error
        }

        let packageURL = destination.appendingPathComponent(
            "AssetRounds.fieldrecordbackup",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw BackupExportServiceError.destinationExists
        }
        let wrapper = try makeFileWrapper(frozen)
        var coordinationError: NSError?
        var writeError: Error?
        var writtenPackageURL: URL?
        NSFileCoordinator().coordinate(
            writingItemAt: destination,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedDirectory in
            let coordinatedPackage = coordinatedDirectory.appendingPathComponent(
                packageURL.lastPathComponent,
                isDirectory: true
            )
            do {
                guard !fileManager.fileExists(atPath: coordinatedPackage.path) else {
                    throw BackupExportServiceError.destinationExists
                }
                try wrapper.write(
                    to: coordinatedPackage,
                    options: .atomic,
                    originalContentsURL: nil
                )
                writtenPackageURL = coordinatedPackage
                try verifyPackage(frozen, at: coordinatedPackage)
            } catch {
                writeError = error
            }
        }
        if coordinationError != nil {
            if let writtenPackageURL,
               fileManager.fileExists(atPath: writtenPackageURL.path) {
                try? fileManager.removeItem(at: writtenPackageURL)
            }
            throw BackupExportServiceError.writeFailed
        }
        if let writeError {
            if let writtenPackageURL,
               fileManager.fileExists(atPath: writtenPackageURL.path) {
                try? fileManager.removeItem(at: writtenPackageURL)
            }
            if let typed = writeError as? BackupExportServiceError {
                throw typed
            }
            throw BackupExportServiceError.writeFailed
        }
        prepared = nil
        return packageURL
    }
}

private extension BackupExportService {
    func buildPrepared(
        previewID: UUID,
        exportedAt: Date
    ) throws -> PreparedV4BackupV1 {
        guard let rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        let rows = try fetchRows()
        try validateGraph(rows)
        let records = makeRecords(rows)
        let recordsData: Data
        do {
            recordsData = try BackupCanonicalEncoderV1().encodeRecords(records).data
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }

        var members = [V4BackupPackageMemberV1(
            path: "records.json",
            mimeType: "application/json",
            data: recordsData
        )]
        let normalizer = MediaNormalizerV1()
        for evidence in rows.evidence.sorted(by: { uuid($0.id) < uuid($1.id) }) {
            let canonicalID = uuid(evidence.id)
            guard evidence.relativePath == "evidence/\(canonicalID)/original.jpg",
                  evidence.thumbnailRelativePath
                    == "evidence/\(canonicalID)/thumbnail.jpg",
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0,
                  evidence.thumbnailByteCount >= 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            let original = try anchoredRead(evidence.relativePath, rootIdentity: rootIdentity)
            let thumbnail = try anchoredRead(
                evidence.thumbnailRelativePath,
                rootIdentity: rootIdentity
            )
            guard original.count == evidence.byteCount,
                  thumbnail.count == evidence.thumbnailByteCount,
                  CanonicalJSONV1.sha256(original) == evidence.sha256,
                  CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                throw BackupExportServiceError.invalidAuthority
            }
            do {
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            } catch {
                throw BackupExportServiceError.invalidAuthority
            }
            members.append(.init(
                path: "media/\(canonicalID).jpg",
                mimeType: "image/jpeg",
                data: original
            ))
            members.append(.init(
                path: "thumbnails/\(canonicalID).jpg",
                mimeType: "image/jpeg",
                data: thumbnail
            ))
        }

        let delivery: ReportDeliveryCoordinator
        do {
            delivery = try ReportDeliveryCoordinator(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                signPack: .illuminatedSignV1,
                expectedRootIdentity: rootIdentity
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        for report in rows.reports.sorted(by: { uuid($0.id) < uuid($1.id) }) {
            do { try delivery.validateRecoveryAuthority(id: report.id) }
            catch { throw BackupExportServiceError.invalidAuthority }
            let canonicalID = uuid(report.id)
            guard report.snapshotSchemaVersion == 1,
                  report.snapshotRelativePath == "snapshots/\(canonicalID).json" else {
                throw BackupExportServiceError.invalidAuthority
            }
            let snapshot = try anchoredRead(
                report.snapshotRelativePath,
                rootIdentity: rootIdentity
            )
            guard CanonicalJSONV1.sha256(snapshot) == report.snapshotSHA256 else {
                throw BackupExportServiceError.invalidAuthority
            }
            members.append(.init(
                path: "snapshots/\(canonicalID).json",
                mimeType: "application/json",
                data: snapshot
            ))
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                guard report.pdfRelativePath == "pdfs/\(canonicalID).pdf",
                      let expectedHash = report.pdfSHA256 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let pdf = try anchoredRead(
                    "pdfs/\(canonicalID).pdf",
                    rootIdentity: rootIdentity
                )
                guard CanonicalJSONV1.sha256(pdf) == expectedHash,
                      pdf.starts(with: Data("%PDF-".utf8)) else {
                    throw BackupExportServiceError.invalidAuthority
                }
                members.append(.init(
                    path: "pdfs/\(canonicalID).pdf",
                    mimeType: "application/pdf",
                    data: pdf
                ))
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
                    throw BackupExportServiceError.invalidAuthority
                }
            case nil:
                throw BackupExportServiceError.invalidAuthority
            }
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              !modelContext.hasChanges else {
            throw BackupExportServiceError.invalidGeneration
        }

        members.sort { $0.path < $1.path }
        var entries: [V4BackupEntryV1] = []
        var declaredPayloadByteCount = 0
        for member in members {
            let (next, overflow) = declaredPayloadByteCount.addingReportingOverflow(
                member.data.count
            )
            guard !overflow else {
                throw BackupExportServiceError.invalidAuthority
            }
            declaredPayloadByteCount = next
            entries.append(.init(
                byteCount: member.data.count,
                mimeType: member.mimeType,
                path: member.path,
                sha256: CanonicalJSONV1.sha256(member.data)
            ))
        }
        let packValues = Set(
            rows.assets.map { "\($0.packID)|\($0.packSchemaVersion)|\($0.packContentVersion)" }
                + rows.records.map {
                    "\($0.packID)|\($0.packSchemaVersion)|\($0.packContentVersion)"
                }
        )
        let packs = packValues.compactMap { value -> V4BackupPackV1? in
            let parts = value.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let schema = Int(parts[1]),
                  let content = Int(parts[2]) else { return nil }
            return .init(
                contentVersion: content,
                packID: String(parts[0]),
                schemaVersion: schema
            )
        }.sorted {
            ($0.packID, $0.schemaVersion, $0.contentVersion)
                < ($1.packID, $1.schemaVersion, $1.contentVersion)
        }
        guard packs.count == packValues.count else {
            throw BackupExportServiceError.invalidAuthority
        }
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 1,
            consumedEvaluationRootIDs: rows.packets
                .filter(\.evaluationCounted)
                .map(\.stableRootID)
                .sorted { uuid($0) < uuid($1) },
            declaredPayloadByteCount: declaredPayloadByteCount,
            entries: entries,
            exportedAt: exportedAt,
            packs: packs,
            source: .init(
                appBuild: appBuild(),
                appVersion: appVersion(),
                persistentSchemaVersion: 1,
                recordsSchemaVersion: 1
            )
        )
        do { _ = try BackupCanonicalEncoderV1().encodeManifest(manifest) }
        catch { throw BackupExportServiceError.invalidAuthority }
        return PreparedV4BackupV1(
            preview: .init(
                id: previewID,
                signCount: rows.assets.count,
                reportCount: rows.reports.count,
                photoCount: rows.evidence.count,
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            records: records,
            manifest: manifest,
            members: members
        )
    }

    func anchoredRead(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> Data {
        guard validRelativePath(relativePath) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            return try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(relativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func fetchRows() throws -> Rows {
        do {
            return Rows(
                sites: try modelContext.fetch(FetchDescriptor<Site>()),
                assets: try modelContext.fetch(FetchDescriptor<Asset>()),
                records: try modelContext.fetch(FetchDescriptor<WorkflowRecord>()),
                evidence: try modelContext.fetch(FetchDescriptor<EvidenceFile>()),
                issues: try modelContext.fetch(FetchDescriptor<Issue>()),
                packets: try modelContext.fetch(FetchDescriptor<Packet>()),
                reports: try modelContext.fetch(FetchDescriptor<Report>())
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateGraph(_ rows: Rows) throws {
        guard unique(rows.sites.map(\.id)),
              unique(rows.assets.map(\.id)),
              unique(rows.records.map(\.id)),
              unique(rows.evidence.map(\.id)),
              unique(rows.issues.map(\.id)),
              unique(rows.packets.map(\.id)),
              unique(rows.packets.map(\.stableRootID)),
              unique(rows.reports.map(\.id)),
              rows.sites.allSatisfy({ $0.schemaVersion == 1 }),
              rows.assets.allSatisfy({ $0.schemaVersion == 1 }),
              rows.records.allSatisfy({ $0.schemaVersion == 1 }),
              rows.evidence.allSatisfy({ $0.schemaVersion == 1 }),
              rows.issues.allSatisfy({ $0.schemaVersion == 1 }),
              rows.packets.allSatisfy({ $0.schemaVersion == 1 }),
              rows.reports.allSatisfy({ $0.schemaVersion == 1 }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let siteIDs = Set(rows.sites.map(\.id))
        let assetIDs = Set(rows.assets.map(\.id))
        let recordIDs = Set(rows.records.map(\.id))
        let issueIDs = Set(rows.issues.map(\.id))
        let packetIDs = Set(rows.packets.map(\.id))
        let recordsByID = Dictionary(uniqueKeysWithValues: rows.records.map { ($0.id, $0) })
        let issuesByID = Dictionary(uniqueKeysWithValues: rows.issues.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: rows.packets.map { ($0.id, $0) })
        let reportsByID = Dictionary(uniqueKeysWithValues: rows.reports.map { ($0.id, $0) })
        let exactPack = SignPack.illuminatedSignV1
        let validRecordRelationships = rows.records.allSatisfy { record in
            guard let revisionKind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  let revisionRoot = recordsByID[record.recordRevisionRootID],
                  revisionRoot.assetID == record.assetID,
                  revisionRoot.revisionKind == WorkflowRevisionKind.original.rawValue,
                  revisionRoot.recordRevisionRootID == revisionRoot.id,
                  revisionRoot.revisesRecordID == nil,
                  revisionRoot.evidenceSourceRecordID == nil,
                  record.parentRecordID.map({
                      recordsByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.issueID.map({ issuesByID[$0]?.assetID == record.assetID }) ?? true,
                  record.packetID.map({ packetsByID[$0] != nil }) ?? true else {
                return false
            }
            switch revisionKind {
            case .original:
                return record.recordRevisionRootID == record.id
                    && record.revisesRecordID == nil
                    && record.evidenceSourceRecordID == nil
            case .clericalCorrection:
                guard let revisedID = record.revisesRecordID,
                      let sourceID = record.evidenceSourceRecordID,
                      let revised = recordsByID[revisedID],
                      let source = recordsByID[sourceID] else {
                    return false
                }
                return record.recordRevisionRootID != record.id
                    && revised.assetID == record.assetID
                    && revised.recordRevisionRootID == record.recordRevisionRootID
                    && source.id == record.recordRevisionRootID
                    && source.assetID == record.assetID
                    && record.parentRecordID == revised.parentRecordID
                    && record.issueID == revised.issueID
                    && record.packetID == revised.packetID
            }
        }
        let validPacketOwnership = rows.packets.allSatisfy { packet in
            var owners = Set<UUID>()
            if let currentID = packet.currentRecordID,
               let current = recordsByID[currentID] {
                owners.insert(current.assetID)
            }
            for record in rows.records where record.packetID == packet.id {
                owners.insert(record.assetID)
            }
            for report in rows.reports where report.packetID == packet.id {
                guard let source = recordsByID[report.sourceRecordID] else { return false }
                owners.insert(source.assetID)
            }
            return packet.currentRecordID == nil ? owners.isEmpty : owners.count == 1
        }
        guard rows.sites.allSatisfy({ site in
                  rows.assets.contains(where: { $0.siteID == site.id })
              }),
              rows.assets.allSatisfy({ asset in
                  siteIDs.contains(asset.siteID)
                    && asset.packID == exactPack.packID
                    && asset.packSchemaVersion == exactPack.schemaVersion
                    && asset.packContentVersion == exactPack.contentVersion
              }),
              rows.records.allSatisfy({ record in
                  assetIDs.contains(record.assetID)
                    && record.packetID.map(packetIDs.contains) ?? true
                    && record.issueID.map(issueIDs.contains) ?? true
                    && record.parentRecordID.map(recordIDs.contains) ?? true
                    && record.revisesRecordID.map(recordIDs.contains) ?? true
                    && record.evidenceSourceRecordID.map(recordIDs.contains) ?? true
                    && recordIDs.contains(record.recordRevisionRootID)
                    && WorkflowRevisionKind(rawValue: record.revisionKind) != nil
                    && WorkflowStage(rawValue: record.stage) != nil
                    && WorkflowState(rawValue: record.state) != nil
                    && record.draftStepKey.map({ WorkflowDraftStep(rawValue: $0) != nil }) ?? true
                    && record.packID == exactPack.packID
                    && record.packSchemaVersion == exactPack.schemaVersion
                    && record.packContentVersion == exactPack.contentVersion
                    && record.pdfTemplateID == "field.evidence.pdf.worklight.v1"
                    && record.pdfTemplateVersion == 1
              }),
              validRecordRelationships,
              rows.evidence.allSatisfy({ recordIDs.contains($0.recordID) }),
              rows.issues.allSatisfy({ issue in
                  assetIDs.contains(issue.assetID)
                    && recordsByID[issue.openedByRecordID]?.assetID == issue.assetID
                    && issue.resolvedByRecordID.map({
                        recordsByID[$0]?.assetID == issue.assetID
                    }) ?? true
                    && IssueStatus(rawValue: issue.status) != nil
              }),
              validPacketOwnership,
              rows.packets.allSatisfy({ packet in
                  if let current = packet.currentRecordID {
                      return packet.contentDeletedAt == nil
                        && rows.records.filter({ $0.id == current }).count == 1
                        && rows.records.first(where: { $0.id == current })?.packetID
                            == packet.id
                  }
                  return packet.evaluationCounted
                    && packet.contentDeletedAt != nil
                    && !rows.records.contains(where: { $0.packetID == packet.id })
                    && !rows.reports.contains(where: { $0.packetID == packet.id })
              }),
              rows.reports.allSatisfy({ report in
                  packetIDs.contains(report.packetID)
                    && recordIDs.contains(report.sourceRecordID)
                    && report.replacesReportID.map({ replacedID in
                        guard let replaced = reportsByID[replacedID] else { return false }
                        return replaced.packetID == report.packetID
                            && replaced.createdAt <= report.createdAt
                    }) ?? true
                    && ReportPDFState(rawValue: report.pdfState) != nil
              }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        try requireAcyclic(rows.records, id: \.id, next: \.parentRecordID)
        try requireAcyclic(rows.records, id: \.id, next: \.revisesRecordID)
        try requireAcyclic(rows.reports, id: \.id, next: \.replacesReportID)
        guard unique(rows.records.compactMap(\.revisesRecordID)),
              unique(rows.reports.compactMap(\.replacesReportID)) else {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func makeRecords(_ rows: Rows) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: rows.assets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                    packContentVersion: $0.packContentVersion, label: $0.label,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            evidenceFiles: rows.evidence.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, recordID: $0.recordID,
                    purposeKey: $0.purposeKey, relativePath: $0.relativePath,
                    mimeType: $0.mimeType, byteCount: $0.byteCount,
                    sha256: $0.sha256, createdAt: $0.createdAt,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount,
                    thumbnailSHA256: $0.thumbnailSHA256
                )
            }.sorted(by: dtoOrder),
            issues: rows.issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, assetID: $0.assetID,
                    openedByRecordID: $0.openedByRecordID, labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot, status: $0.status,
                    resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            packets: rows.packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt, createdAt: $0.createdAt
                )
            }.sorted(by: dtoOrder),
            recordsSchemaVersion: 1,
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
            }.sorted(by: dtoOrder),
            sites: rows.sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, label: $0.label,
                    address: $0.address, timeZoneID: $0.timeZoneID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            workflowRecords: rows.records.map(workflowDTO).sorted(by: dtoOrder)
        )
    }

    func workflowDTO(_ value: WorkflowRecord) -> V4BackupWorkflowRecordDTO {
        .init(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID, issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage, state: value.state,
            draftStepKey: value.draftStepKey, startedAt: value.startedAt,
            completedAt: value.completedAt, observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID, utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey, couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }
}

private extension BackupExportService {
    func makeFileWrapper(_ value: PreparedV4BackupV1) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let manifestData = try BackupCanonicalEncoderV1().encodeManifest(value.manifest).data
        try add(
            V4BackupPackageMemberV1(
                path: "manifest.json", mimeType: "application/json", data: manifestData
            ),
            to: root
        )
        for member in value.members { try add(member, to: root) }
        return root
    }

    func add(_ member: V4BackupPackageMemberV1, to root: FileWrapper) throws {
        let components = member.path.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw BackupExportServiceError.invalidAuthority
        }
        var directory = root
        for component in components.dropLast() {
            if let existing = directory.fileWrappers?[component] {
                guard existing.isDirectory else {
                    throw BackupExportServiceError.invalidAuthority
                }
                directory = existing
            } else {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            }
        }
        let leaf = FileWrapper(regularFileWithContents: member.data)
        leaf.preferredFilename = components.last
        guard directory.fileWrappers?[components.last!] == nil else {
            throw BackupExportServiceError.invalidAuthority
        }
        directory.addFileWrapper(leaf)
    }

    func verifyPackage(_ value: PreparedV4BackupV1, at url: URL) throws {
        let expectedManifest = try BackupCanonicalEncoderV1().encodeManifest(
            value.manifest
        ).data
        let expected = Dictionary(uniqueKeysWithValues:
            [("manifest.json", expectedManifest)]
                + value.members.map { ($0.path, $0.data) }
        )
        let wrapper = try FileWrapper(url: url, options: [.immediate])
        var actual: [String: Data] = [:]
        try flatten(wrapper, prefix: "", into: &actual)
        guard actual == expected else {
            throw BackupExportServiceError.writeFailed
        }
    }

    func flatten(
        _ wrapper: FileWrapper,
        prefix: String,
        into output: inout [String: Data]
    ) throws {
        guard !wrapper.isSymbolicLink else {
            throw BackupExportServiceError.writeFailed
        }
        if wrapper.isRegularFile {
            guard !prefix.isEmpty, let data = wrapper.regularFileContents,
                  output[prefix] == nil else {
                throw BackupExportServiceError.writeFailed
            }
            output[prefix] = data
            return
        }
        guard wrapper.isDirectory, let children = wrapper.fileWrappers else {
            throw BackupExportServiceError.writeFailed
        }
        for (name, child) in children {
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                throw BackupExportServiceError.writeFailed
            }
            let childPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            try flatten(child, prefix: childPath, into: &output)
        }
    }

    func validRelativePath(_ value: String) -> Bool {
        value == value.precomposedStringWithCanonicalMapping
            && !value.hasPrefix("/")
            && value.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    func dtoOrder<T>(_ lhs: T, _ rhs: T) -> Bool where T: Identifiable, T.ID == UUID {
        uuid(lhs.id) < uuid(rhs.id)
    }

    func requireAcyclic<T>(
        _ values: [T],
        id: KeyPath<T, UUID>,
        next: KeyPath<T, UUID?>
    ) throws {
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0[keyPath: id], $0) })
        for value in values {
            var seen = Set<UUID>()
            var cursor: UUID? = value[keyPath: id]
            while let current = cursor {
                guard seen.insert(current).inserted, let row = byID[current] else {
                    throw BackupExportServiceError.invalidAuthority
                }
                cursor = row[keyPath: next]
            }
        }
    }
}
