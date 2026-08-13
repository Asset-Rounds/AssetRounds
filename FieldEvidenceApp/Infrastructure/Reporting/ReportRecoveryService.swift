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
    private let renderService: ReportRenderService
    private let launchAttemptRegistry: ReportLaunchAttemptRegistry
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let failureInjection: ReportRecoveryFailureInjection?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1,
        failNextRenderAttempt: Bool = false,
        failureInjection: ReportRenderFailureInjection? = nil,
        recoveryFailureInjection: ReportRecoveryFailureInjection? = nil,
        launchAttemptRegistry: ReportLaunchAttemptRegistry = .init()
    ) throws {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.fileManager = fileManager
        self.launchAttemptRegistry = launchAttemptRegistry
        self.failureInjection = recoveryFailureInjection
        do {
            self.rootIdentity = try ReportPDFAnchoredFile.rootIdentity(
                at: self.generationRootURL
            )
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        self.renderService = try ReportRenderService(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            fileManager: fileManager,
            signPack: signPack,
            failNextRenderAttempt: failNextRenderAttempt,
            failureInjection: failureInjection
        )
    }

    /// Validates the complete delivery-state matrix before changing any row or
    /// file. Each pending report is attempted at most once in this launch pass;
    /// failed and ready reports are never rendered automatically.
    func reconcileAtStartup() throws {
        guard !modelContext.hasChanges else {
            throw ReportRecoveryServiceError.contextHasChanges
        }
        let plans = try validatedPlans()
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
            guard launchAttemptRegistry.begin(plan.report.id) else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
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
        var packetIDs = Set<UUID>()
        var sourceRecordIDs = Set<UUID>()
        var snapshotPaths = Set<String>()
        var finalPaths = Set<String>()
        var plans: [Plan] = []
        plans.reserveCapacity(reports.count)

        for report in reports {
            guard ids.insert(report.id).inserted,
                  packetIDs.insert(report.packetID).inserted,
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
        return plans
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
