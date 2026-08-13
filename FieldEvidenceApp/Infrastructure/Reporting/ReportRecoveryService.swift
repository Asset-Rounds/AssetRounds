import CryptoKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ReportLaunchAttemptRegistry {
    private var attemptedReportIDs = Set<UUID>()

    func begin(_ reportID: UUID) -> Bool {
        attemptedReportIDs.insert(reportID).inserted
    }

    func beginAll(_ reportIDs: [UUID]) -> Bool {
        guard Set(reportIDs).count == reportIDs.count,
              reportIDs.allSatisfy({ !attemptedReportIDs.contains($0) }) else {
            return false
        }
        attemptedReportIDs.formUnion(reportIDs)
        return true
    }
}

enum ReportRecoveryServiceError: Error, Equatable {
    case contextHasChanges
    case invalidAuthority
    case reportNotFailed
    case retryAlreadyRunning
    case cleanupFailed
    case transitionSaveFailed
}

enum ReportRecoveryFailurePoint: Equatable, Sendable {
    case retryTransitionSave
}

@MainActor
final class ReportRecoveryFailureInjection {
    private var pending: ReportRecoveryFailurePoint?

    init(failOnceAt point: ReportRecoveryFailurePoint) {
        pending = point
    }

    func consume(_ point: ReportRecoveryFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class ReportRecoveryService: ObservableObject {
    @Published private(set) var failedReportIDs: [UUID] = []
    @Published private(set) var isRetrying = false

    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let fileManager: FileManager
    private let signPack: SignPack
    private let renderService: ReportRenderService
    private let launchAttemptRegistry: ReportLaunchAttemptRegistry
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let failureInjection: ReportRecoveryFailureInjection?
    private var unavailableObserver: NSObjectProtocol?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1,
        failNextRenderAttempt: Bool = false,
        failureInjection: ReportRenderFailureInjection? = nil,
        recoveryFailureInjection: ReportRecoveryFailureInjection? = nil,
        launchAttemptRegistry: ReportLaunchAttemptRegistry? = nil
    ) throws {
        let root = generationRootURL.standardizedFileURL
        let capturedRootIdentity: ReportPDFAnchoredFile.RootIdentity
        do {
            capturedRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        self.modelContext = modelContext
        self.generationRootURL = root
        self.fileManager = fileManager
        self.signPack = signPack
        self.launchAttemptRegistry = launchAttemptRegistry
            ?? ReportLaunchAttemptRegistry()
        self.failureInjection = recoveryFailureInjection
        self.rootIdentity = capturedRootIdentity
        self.renderService = try ReportRenderService(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            fileManager: fileManager,
            signPack: signPack,
            failNextRenderAttempt: failNextRenderAttempt,
            failureInjection: failureInjection
        )
        guard try ReportPDFAnchoredFile.rootIdentity(at: root)
                == capturedRootIdentity else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        unavailableObserver = NotificationCenter.default.addObserver(
            forName: .reportPDFBecameUnavailable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? ReportPDFUnavailableEvent else {
                return
            }
            let reportID = event.reportID
            Task { @MainActor [weak self] in
                self?.registerPersistedFailure(reportID)
            }
        }
    }

    deinit {
        if let unavailableObserver {
            NotificationCenter.default.removeObserver(unavailableObserver)
        }
    }

    /// Validates the complete delivery-state matrix before changing any row or
    /// file. Each pending report is attempted at most once in this launch pass;
    /// failed and ready reports are never rendered automatically.
    func reconcileAtStartup() throws {
        guard !modelContext.hasChanges else {
            throw ReportRecoveryServiceError.contextHasChanges
        }
        let plans = try validatedPlans()
        let pendingIDs = plans.compactMap {
            $0.state == .pending ? $0.report.id : nil
        }
        guard launchAttemptRegistry.beginAll(pendingIDs) else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        for plan in plans where plan.state != .ready {
            try removeNonReadyArtifactIfPresent(
                plan.stageURL,
                quarantineAt: plan.finalURL,
                exists: plan.hasStage
            )
            try removeNonReadyArtifactIfPresent(
                plan.finalURL,
                quarantineAt: plan.stageURL,
                exists: plan.hasFinal
            )
        }
        for plan in plans where plan.state == .pending {
            _ = try renderService.attemptPendingReport(id: plan.report.id)
        }
        try refreshFailedReportIDs()
    }

    /// Persists the only legal user transition, failed -> pending, before one
    /// render attempt. A second call while this one is active is rejected.
    func retryFailedReport(id reportID: UUID) async throws -> ReportRenderAttemptResult {
        guard !isRetrying else {
            throw ReportRecoveryServiceError.retryAlreadyRunning
        }
        isRetrying = true
        defer { isRetrying = false }

        guard !modelContext.hasChanges else {
            throw ReportRecoveryServiceError.contextHasChanges
        }
        let plans = try validatedPlans()
        guard let plan = plans.first(where: { $0.report.id == reportID }),
              plan.state == .failed else {
            throw ReportRecoveryServiceError.reportNotFailed
        }
        try removeNonReadyArtifactIfPresent(
            plan.stageURL,
            quarantineAt: plan.finalURL,
            exists: plan.hasStage
        )
        try removeNonReadyArtifactIfPresent(
            plan.finalURL,
            quarantineAt: plan.stageURL,
            exists: plan.hasFinal
        )

        plan.report.pdfState = ReportPDFState.pending.rawValue
        do {
            if failureInjection?.consume(.retryTransitionSave) == true {
                throw ReportRecoveryServiceError.transitionSaveFailed
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            plan.report.pdfState = ReportPDFState.failed.rawValue
            plan.report.pdfRelativePath = nil
            plan.report.pdfSHA256 = nil
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw ReportRecoveryServiceError.transitionSaveFailed
            }
            try refreshFailedReportIDs()
            throw ReportRecoveryServiceError.transitionSaveFailed
        }

        do {
            let result = try renderService.attemptPendingReport(id: reportID)
            try refreshFailedReportIDs()
            return result
        } catch {
            // Unsafe storage/cleanup failures are deliberately not relabeled as
            // retryable. The caller must route them through startup maintenance.
            try? refreshFailedReportIDs()
            throw error
        }
    }

    private struct Plan {
        let report: Report
        let state: ReportPDFState
        let stageURL: URL
        let finalURL: URL
        let hasStage: Bool
        let hasFinal: Bool
    }

    private func validatedPlans() throws -> [Plan] {
        guard !modelContext.hasChanges else {
            throw ReportRecoveryServiceError.contextHasChanges
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return Self.canonical($0.id) < Self.canonical($1.id)
        }
        try validateStorageRoots(requiresSnapshots: !reports.isEmpty)
        var ids = Set<UUID>()
        var sourceRecordIDs = Set<UUID>()
        var snapshotPaths = Set<String>()
        var finalPaths = Set<String>()
        var plans: [Plan] = []
        plans.reserveCapacity(reports.count)

        for report in reports {
            guard ids.insert(report.id).inserted,
                  sourceRecordIDs.insert(report.sourceRecordID).inserted,
                  report.schemaVersion == 1,
                  report.snapshotSchemaVersion == 1,
                  Self.isLowercaseSHA256(report.snapshotSHA256) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            let id = Self.canonical(report.id)
            let expectedSnapshot = "snapshots/\(id).json"
            let expectedFinal = "pdfs/\(id).pdf"
            guard report.snapshotRelativePath == expectedSnapshot,
                  snapshotPaths.insert(expectedSnapshot).inserted,
                  finalPaths.insert(expectedFinal).inserted,
                  let state = ReportPDFState(rawValue: report.pdfState) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            let snapshotURL = generationRootURL.appendingPathComponent(
                expectedSnapshot,
                isDirectory: false
            )
            guard try itemType(at: snapshotURL) == .typeRegular,
                  !isSymbolicLink(snapshotURL) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            let snapshotBytes: Data
            do {
                snapshotBytes = try ReportPDFAnchoredFile.readRegularFile(
                    at: snapshotURL,
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
            } catch {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            guard Self.sha256(snapshotBytes) == report.snapshotSHA256 else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            let snapshot: ReportSnapshotV1
            do {
                snapshot = try ReportSnapshotEncoderV1().decode(snapshotBytes)
                guard try ReportSnapshotEncoderV1().encode(snapshot).data
                    == snapshotBytes else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            } catch {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            guard snapshot.snapshotSchemaVersion == 1,
                  snapshot.reportID == report.id,
                  snapshot.packetID == report.packetID,
                  snapshot.sourceRecordID == report.sourceRecordID,
                  snapshot.pdfTemplate.id == "field.evidence.pdf.worklight.v1",
                  snapshot.pdfTemplate.version == 1 else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            switch state {
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            case .ready:
                guard report.pdfRelativePath == expectedFinal,
                      let hash = report.pdfSHA256,
                      Self.isLowercaseSHA256(hash) else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            }

            let stageURL = generationRootURL.appendingPathComponent(
                ".staging/pdfs/\(id).pdf",
                isDirectory: false
            )
            let finalURL = generationRootURL.appendingPathComponent(
                expectedFinal,
                isDirectory: false
            )
            let stageType = try itemType(at: stageURL)
            let finalType = try itemType(at: finalURL)
            let hasStage = stageType != nil
            let hasFinal = finalType != nil
            if hasStage {
                guard stageType == .typeRegular, !isSymbolicLink(stageURL) else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            }
            if hasFinal {
                guard finalType == .typeRegular, !isSymbolicLink(finalURL) else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            }
            guard !(hasStage && hasFinal) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }

            if state == .ready {
                guard !hasStage, hasFinal, let expectedHash = report.pdfSHA256 else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
                let data: Data
                do {
                    data = try ReportPDFAnchoredFile.readRegularFile(
                        at: finalURL,
                        within: generationRootURL,
                        rootIdentity: rootIdentity
                    )
                } catch {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
                guard Self.sha256(data) == expectedHash else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            }
            plans.append(
                Plan(
                    report: report,
                    state: state,
                    stageURL: stageURL,
                    finalURL: finalURL,
                    hasStage: hasStage,
                    hasFinal: hasFinal
                )
            )
        }
        try validateReplacementChains(reports: reports)
        let authorityCoordinator: ReportDeliveryCoordinator
        do {
            authorityCoordinator = try ReportDeliveryCoordinator(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                signPack: signPack,
                expectedRootIdentity: rootIdentity
            )
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        for plan in plans {
            do {
                try authorityCoordinator.validateRecoveryAuthority(
                    id: plan.report.id
                )
            } catch {
                throw ReportRecoveryServiceError.invalidAuthority
            }
        }
        return plans
    }

    private func validateReplacementChains(reports: [Report]) throws {
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        guard Set(reports.map(\.id)).count == reports.count,
              Set(records.map(\.id)).count == records.count,
              Set(reports.map(\.sourceRecordID)).count == reports.count else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        for packetID in Set(reports.map(\.packetID)) {
            let packetMatches = packets.filter { $0.id == packetID }
            guard packetMatches.count == 1,
                  let packet = packetMatches.first,
                  packet.schemaVersion == 1,
                  packet.evaluationCounted,
                  packet.contentDeletedAt == nil,
                  let currentRecordID = packet.currentRecordID,
                  packets.filter({ $0.stableRootID == packet.stableRootID }).count == 1,
                  packets.filter({ $0.currentRecordID == currentRecordID }).count == 1 else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            let packetReports = reports.filter { $0.packetID == packetID }
            let tips = packetReports.filter { $0.sourceRecordID == currentRecordID }
            guard tips.count == 1,
                  reports.filter({ $0.replacesReportID == tips[0].id }).isEmpty,
                  records.filter({ $0.revisesRecordID == currentRecordID }).isEmpty else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            var report = tips[0]
            var visitedReports = Set<UUID>()
            var visitedRecords = Set<UUID>()
            while true {
                guard visitedReports.insert(report.id).inserted else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
                let sourceMatches = records.filter { $0.id == report.sourceRecordID }
                guard sourceMatches.count == 1,
                      let source = sourceMatches.first,
                      source.packetID == packetID,
                      visitedRecords.insert(source.id).inserted else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
                switch WorkflowRevisionKind(rawValue: source.revisionKind) {
                case .original:
                    guard source.revisesRecordID == nil,
                          source.evidenceSourceRecordID == nil,
                          source.recordRevisionRootID == source.id,
                          report.replacesReportID == nil else {
                        throw ReportRecoveryServiceError.invalidAuthority
                    }
                    break
                case .clericalCorrection:
                    guard let priorRecordID = source.revisesRecordID,
                          let priorReportID = report.replacesReportID,
                          source.evidenceSourceRecordID == source.recordRevisionRootID,
                          evidence.filter({ $0.recordID == source.id }).isEmpty,
                          records.filter({ $0.revisesRecordID == priorRecordID }).count == 1,
                          reports.filter({ $0.replacesReportID == priorReportID }).count == 1 else {
                        throw ReportRecoveryServiceError.invalidAuthority
                    }
                    let priorReports = packetReports.filter { $0.id == priorReportID }
                    let priorRecords = records.filter { $0.id == priorRecordID }
                    guard priorReports.count == 1,
                          priorRecords.count == 1,
                          priorReports[0].sourceRecordID == priorRecordID,
                          report.createdAt >= priorReports[0].createdAt else {
                        throw ReportRecoveryServiceError.invalidAuthority
                    }
                    let priorSnapshot = try canonicalSnapshot(priorReports[0])
                    let correctionSnapshot = try canonicalSnapshot(report)
                    do {
                        try ReportCorrectionRule().validateEdge(
                            prior: ReportCorrectionRuleSource(
                                currentRecord: recordPayload(priorRecords[0]),
                                packet: PacketPayloadV1(
                                    id: packet.id,
                                    schemaVersion: packet.schemaVersion,
                                    stableRootID: packet.stableRootID,
                                    currentRecordID: priorRecordID,
                                    evaluationCounted: packet.evaluationCounted,
                                    contentDeletedAt: packet.contentDeletedAt,
                                    createdAt: packet.createdAt
                                ),
                                currentReport: reportPayload(priorReports[0]),
                                currentSnapshot: priorSnapshot
                            ),
                            correctionRecord: recordPayload(source),
                            correctionReport: reportPayload(report),
                            correctionSnapshot: correctionSnapshot
                        )
                    } catch {
                        throw ReportRecoveryServiceError.invalidAuthority
                    }
                    report = priorReports[0]
                    continue
                case nil:
                    throw ReportRecoveryServiceError.invalidAuthority
                }
                break
            }
            let packetRecordIDs = Set(records.filter {
                $0.packetID == packetID
            }.map(\.id))
            guard visitedReports.count == packetReports.count,
                  packetRecordIDs == visitedRecords else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
        }
    }

    private func canonicalSnapshot(_ report: Report) throws -> ReportSnapshotV1 {
        let data: Data
        do {
            data = try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(report.snapshotRelativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        guard Self.sha256(data) == report.snapshotSHA256 else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        do {
            let value = try ReportSnapshotEncoderV1().decode(data)
            guard try ReportSnapshotEncoderV1().encode(value).data == data else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            return value
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
    }

    private func recordPayload(_ value: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
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
            utcOffsetMinutes: value.utcOffsetMinutes,
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
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }

    private func reportPayload(_ value: Report) -> ReportPayloadV1 {
        ReportPayloadV1(
            id: value.id, schemaVersion: value.schemaVersion,
            packetID: value.packetID, sourceRecordID: value.sourceRecordID,
            snapshotSchemaVersion: value.snapshotSchemaVersion,
            snapshotRelativePath: value.snapshotRelativePath,
            snapshotSHA256: value.snapshotSHA256,
            pdfState: value.pdfState, pdfRelativePath: value.pdfRelativePath,
            pdfSHA256: value.pdfSHA256, createdAt: value.createdAt,
            replacesReportID: value.replacesReportID
        )
    }

    private func validateStorageRoots(requiresSnapshots: Bool) throws {
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
            == rootIdentity else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        let snapshotsRoot = generationRootURL.appendingPathComponent(
            "snapshots",
            isDirectory: true
        )
        if requiresSnapshots {
            guard try itemType(at: snapshotsRoot) == .typeDirectory,
                  !isSymbolicLink(snapshotsRoot) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
        } else if let type = try itemType(at: snapshotsRoot) {
            guard type == .typeDirectory, !isSymbolicLink(snapshotsRoot) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
        }
        let optionalRoots = [
            generationRootURL.appendingPathComponent(".staging", isDirectory: true),
            generationRootURL.appendingPathComponent(".staging/pdfs", isDirectory: true),
            generationRootURL.appendingPathComponent("pdfs", isDirectory: true),
        ]
        for root in optionalRoots {
            if let type = try itemType(at: root) {
                guard type == .typeDirectory,
                      !isSymbolicLink(root) else {
                    throw ReportRecoveryServiceError.invalidAuthority
                }
            }
        }
    }

    private func removeNonReadyArtifactIfPresent(
        _ url: URL,
        quarantineAt quarantineURL: URL,
        exists: Bool
    ) throws {
        guard exists else { return }
        do {
            let quarantineDirectory: String
            let parentPath = quarantineURL.deletingLastPathComponent()
                .standardizedFileURL.path
            if parentPath == generationRootURL.appendingPathComponent(
                "pdfs",
                isDirectory: true
            ).standardizedFileURL.path {
                quarantineDirectory = "pdfs"
            } else if parentPath == generationRootURL.appendingPathComponent(
                ".staging/pdfs",
                isDirectory: true
            ).standardizedFileURL.path {
                try ReportPDFAnchoredFile.ensureDirectory(
                    relativePath: ".staging",
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
                quarantineDirectory = ".staging/pdfs"
            } else {
                throw ReportRecoveryServiceError.cleanupFailed
            }
            try ReportPDFAnchoredFile.ensureDirectory(
                relativePath: quarantineDirectory,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
            try ReportPDFAnchoredFile.removeRegularFile(
                at: url,
                quarantineAt: quarantineURL,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw ReportRecoveryServiceError.cleanupFailed
        }
        guard try itemType(at: url) == nil else {
            throw ReportRecoveryServiceError.cleanupFailed
        }
    }

    private func refreshFailedReportIDs() throws {
        failedReportIDs = try modelContext.fetch(FetchDescriptor<Report>())
            .filter {
                $0.pdfState == ReportPDFState.failed.rawValue
                    && $0.pdfRelativePath == nil
                    && $0.pdfSHA256 == nil
            }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return Self.canonical($0.id) < Self.canonical($1.id)
            }
            .map(\.id)
    }

    private func registerPersistedFailure(_ reportID: UUID) {
        guard !modelContext.hasChanges,
              (try? validatedPlans()).flatMap({ plans in
                  plans.first(where: {
                      $0.report.id == reportID && $0.state == .failed
                  })
              }) != nil else {
            return
        }
        try? refreshFailedReportIDs()
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)[.type]
                as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func canonical(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
