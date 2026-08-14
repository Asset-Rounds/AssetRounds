import CryptoKit
import Darwin
import Foundation
import SwiftData

struct WholeSignDeletionOutcome: Equatable, Sendable {
    let assetID: UUID
    let deletionID: UUID
    let countedTombstoneCount: Int
}

struct WholeSignDeletionRecoverySummary: Equatable, Sendable {
    let cancelledPreparedCount: Int
    let completedCommittedCount: Int
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
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let generationID: UUID
    private let journal: DeletionJournalStore
    private let files: DeletionGenerationFiles
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
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.now = now
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection
        _ = fileManager // Kept for source-compatible test construction only.

        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        let applicationSupport = dataRoot.deletingLastPathComponent()
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
        } else {
            generationID = UUID()
            files = DeletionGenerationFiles.invalid
            journal = DeletionJournalStore.invalid
        }
    }

    func delete(assetID: UUID) async throws -> WholeSignDeletionOutcome {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        guard try journal.loadAll().isEmpty else {
            throw WholeSignDeletionServiceError.recoveryRequired
        }

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
        try validateOwnedFiles(plan: plan, rows: rows)
        try journal.create(plan.intent)
        try inject(.preparedJournal)

        let packetStates = Dictionary(uniqueKeysWithValues: rows.packets.map {
            ($0.id, ($0.currentRecordID, $0.evaluationCounted, $0.contentDeletedAt))
        })
        do {
            try apply(plan: plan, rows: rows)
            try inject(.databaseSave)
            try modelContext.save()
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
        return WholeSignDeletionOutcome(
            assetID: assetID,
            deletionID: deletionID,
            countedTombstoneCount: plan.intent.countedPacketTombstones.count
        )
    }

    func reconcile() async throws -> WholeSignDeletionRecoverySummary {
        try requireAuthority()
        guard !modelContext.hasChanges else {
            throw WholeSignDeletionServiceError.contextHasChanges
        }
        let intents = try journal.loadAll()
        let intentPaths = intents.flatMap(\.relativePaths)
        let intentPacketIDs = intents.flatMap {
            $0.countedPacketTombstones.map(\.id)
        }
        guard Set(intents.map(\.assetID)).count == intents.count,
              Set(intentPaths).count == intentPaths.count,
              Set(intentPacketIDs).count == intentPacketIDs.count else {
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
                guard intent.phase == .prepared,
                      try preparedIntentMatches(intent, rows: rows) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                try journal.remove(intent)
                cancelled += 1
                continue
            }
            guard committedStateMatches(intent, rows: rows) else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            if intent.phase == .prepared {
                try journal.replace(intent.withPhase(.databaseCommitted))
            }
            try cleanup(intent)
            try journal.remove(intent.withPhase(.databaseCommitted))
            completed += 1
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
    }

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
                sites: try modelContext.fetch(FetchDescriptor<Site>()),
                assets: try modelContext.fetch(FetchDescriptor<Asset>()),
                records: try modelContext.fetch(FetchDescriptor<WorkflowRecord>()),
                evidence: try modelContext.fetch(FetchDescriptor<EvidenceFile>()),
                issues: try modelContext.fetch(FetchDescriptor<Issue>()),
                packets: try modelContext.fetch(FetchDescriptor<Packet>()),
                reports: try modelContext.fetch(FetchDescriptor<Report>())
            )
        } catch {
            throw WholeSignDeletionServiceError.graphInvalid
        }
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
            do { data = try files.read(relativePath: path) }
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

    func preparedIntentMatches(_ intent: DeletionIntentV1, rows: Rows) throws -> Bool {
        let dates = Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt))
        guard dates.count <= 1 else { return false }
        let input = makeRuleInput(
            rows: rows, assetID: intent.assetID,
            deletionID: intent.deletionID,
            deletedAt: dates.first ?? .distantPast
        )
        guard let plan = try? WholeSignDeletionRule.makePlan(input),
              plan.intent == intent else { return false }
        try validateOwnedFiles(plan: plan, rows: rows)
        return true
    }

    func committedStateMatches(_ intent: DeletionIntentV1, rows: Rows) -> Bool {
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
              rows.sites.allSatisfy({ site in
                  site.schemaVersion == 1
                    && rows.assets.contains(where: { $0.siteID == site.id })
              }),
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
              }) else { return false }
        return true
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
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
        if let siteID = plan.siteIDToDelete,
           let site = rows.sites.first(where: { $0.id == siteID }) {
            modelContext.delete(site)
        }
    }

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
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

    func read(relativePath: String) throws -> Data {
        try withParent(relativePath) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw WholeSignDeletionServiceError.fileInvalid }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_nlink == 1 else {
                try? handle.close()
                throw WholeSignDeletionServiceError.fileInvalid
            }
            do { return try handle.readToEnd() ?? Data() }
            catch { throw WholeSignDeletionServiceError.fileInvalid }
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
            if name != "." && name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw WholeSignDeletionServiceError.fileInvalid }
        return result.sorted()
    }
}

private final class DeletionJournalStore {
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
        let deletion = try Self.openOrCreateDirectory(
            parent: operations,
            name: "deletion"
        )
        defer { Darwin.close(deletion) }
        let capturedDeletionIdentity = try Self.identity(deletion)
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
                if name != "." && name != ".." { names.append(name) }
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
            let journalIDs = Set(journalNames.compactMap(Self.journalIdentifier))
            for temporary in temporaryNames {
                guard let temporaryID = Self.temporaryIdentifier(temporary) else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                let file = Darwin.openat(descriptor, temporary, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
                var info = stat()
                let valid = Darwin.fstat(file, &info) == 0
                    && (info.st_mode & S_IFMT) == S_IFREG
                    && info.st_nlink == 1
                Darwin.close(file)
                guard valid else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
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
                guard Darwin.unlinkat(descriptor, temporary, 0) == 0 else {
                    throw WholeSignDeletionServiceError.journalInvalid
                }
            }
            if !temporaryNames.isEmpty, Darwin.fsync(descriptor) != 0 {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            return try journalNames.sorted().map { name in
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
            var succeeded = false
            defer {
                Darwin.close(file)
                if !succeeded { _ = Darwin.unlinkat(descriptor, temporary, 0) }
            }
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
            let flags = exclusive ? UInt32(RENAME_EXCL) : UInt32(0)
            guard Darwin.renameatx_np(descriptor, temporary, descriptor, name, flags) == 0,
                  Darwin.fsync(descriptor) == 0 else {
                throw WholeSignDeletionServiceError.journalInvalid
            }
            succeeded = true
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
        let file = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { throw WholeSignDeletionServiceError.journalInvalid }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        var info = stat()
        guard Darwin.fstat(file, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            try? handle.close()
            throw WholeSignDeletionServiceError.journalInvalid
        }
        do { return try handle.readToEnd() ?? Data() }
        catch { throw WholeSignDeletionServiceError.journalInvalid }
    }

    private static func decode(_ data: Data) throws -> DeletionIntentV1 {
        do { return try DeletionIntentDecoderV1().decode(data) }
        catch { throw WholeSignDeletionServiceError.journalInvalid }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw WholeSignDeletionServiceError.invalidGeneration
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
