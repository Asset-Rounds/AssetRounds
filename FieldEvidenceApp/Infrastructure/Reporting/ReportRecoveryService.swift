import CryptoKit
import Foundation
import SwiftData
import SwiftUI

enum GuidedSurveyReportRecoveryBoundaryV1 {
    static func validateRecovered(_ snapshot: ReportSnapshotV1) throws {
        try snapshot.surveyPublication?.validate()
    }
    static let recoveryRecomputesPublication = false
}

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

enum ReportRecoveryAccessibleDocumentPolicyV1{
    static let unacceptedTree="DROP_AND_REBUILD_FROM_FROZEN_SNAPSHOT"
    static let acceptedReceipt="REVALIDATE_INTRINSIC_THEN_REBUILD_TREE_CLOSURE"
    static func rebuild(receipt:AccessibleDocumentAssessmentReceiptV1,resolver:any AccessibleDocumentSemanticTreeResolvingV1)async throws->AccessibleDocumentSemanticTreeV1{try receipt.validateIntrinsic();return try await resolver.resolveValidatedTree(for:receipt)}
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
    private let lifecycleProfile: WorkspacePackageLifecycleProfileV1
    private let lifecycleRoute: ReportingPackageLifecycleRouteV1
    private let renderService: ReportRenderService
    private let launchAttemptRegistry: ReportLaunchAttemptRegistry
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let failureInjection: ReportRecoveryFailureInjection?
    private var unavailableObserver: NSObjectProtocol?

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1,
        failNextRenderAttempt: Bool = false,
        failureInjection: ReportRenderFailureInjection? = nil,
        recoveryFailureInjection: ReportRecoveryFailureInjection? = nil,
        launchAttemptRegistry: ReportLaunchAttemptRegistry? = nil
    ) throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: signPack
        )
        try self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            fileManager: fileManager,
            lifecycleRoute: .expiringCompatibility(
                profile: profile,
                posture: WorkspacePackageLifecycleCompatibilityV1.expiration
            ),
            failNextRenderAttempt: failNextRenderAttempt,
            failureInjection: failureInjection,
            recoveryFailureInjection: recoveryFailureInjection,
            launchAttemptRegistry: launchAttemptRegistry
        )
    }

    convenience init(
        modelContext: ModelContext,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        lifecycleProfile: WorkspacePackageLifecycleProfileV1,
        fileManager: FileManager = .default,
        failNextRenderAttempt: Bool = false,
        failureInjection: ReportRenderFailureInjection? = nil,
        recoveryFailureInjection: ReportRecoveryFailureInjection? = nil,
        launchAttemptRegistry: ReportLaunchAttemptRegistry? = nil
    ) throws {
        try self.init(
            modelContext: modelContext,
            generationRootURL: lifecycleDependencies.generationRootURL,
            fileManager: fileManager,
            lifecycleRoute: .live(
                dependencies: lifecycleDependencies,
                profile: lifecycleProfile
            ),
            failNextRenderAttempt: failNextRenderAttempt,
            failureInjection: failureInjection,
            recoveryFailureInjection: recoveryFailureInjection,
            launchAttemptRegistry: launchAttemptRegistry
        )
    }

    private init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager,
        lifecycleRoute: ReportingPackageLifecycleRouteV1,
        failNextRenderAttempt: Bool,
        failureInjection: ReportRenderFailureInjection?,
        recoveryFailureInjection: ReportRecoveryFailureInjection?,
        launchAttemptRegistry: ReportLaunchAttemptRegistry?
    ) throws {
        let root = generationRootURL.standardizedFileURL
        try lifecycleRoute.validate(generationRootURL: root)
        let lifecycleProfile = lifecycleRoute.profile
        let capturedRootIdentity: ReportPDFAnchoredFile.RootIdentity
        do {
            capturedRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        } catch {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        self.modelContext = modelContext
        self.generationRootURL = root
        self.fileManager = fileManager
        self.signPack = lifecycleProfile.package
        self.lifecycleProfile = lifecycleProfile
        self.lifecycleRoute = lifecycleRoute
        self.launchAttemptRegistry = launchAttemptRegistry
            ?? ReportLaunchAttemptRegistry()
        self.failureInjection = recoveryFailureInjection
        self.rootIdentity = capturedRootIdentity
        switch lifecycleRoute {
        case .live(let lifecycleDependencies, _):
            self.renderService = try ReportRenderService(
                modelContext: modelContext,
                lifecycleDependencies: lifecycleDependencies,
                lifecycleProfile: lifecycleProfile,
                fileManager: fileManager,
                failNextRenderAttempt: failNextRenderAttempt,
                failureInjection: failureInjection
            )
        case .expiringCompatibility:
            self.renderService = try ReportRenderService(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                fileManager: fileManager,
                signPack: lifecycleProfile.package,
                failNextRenderAttempt: failNextRenderAttempt,
                failureInjection: failureInjection
            )
        }
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
                  report.snapshotSchemaVersion == 1 || report.snapshotSchemaVersion == 2,
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
            guard snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion,
                  snapshot.reportID == report.id,
                  snapshot.packetID == report.packetID,
                  snapshot.sourceRecordID == report.sourceRecordID,
                  snapshot.pdfTemplate == lifecycleProfile.pdfTemplate,
                  snapshot.pack.id == lifecycleProfile.release.packageID,
                  snapshot.pack.schemaVersion == lifecycleProfile.release.schemaVersion,
                  snapshot.pack.contentVersion == lifecycleProfile.release.contentVersion else {
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
            switch lifecycleRoute {
            case .live(let lifecycleDependencies, _):
                authorityCoordinator = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    lifecycleDependencies: lifecycleDependencies,
                    lifecycleProfile: lifecycleProfile,
                    expectedRootIdentity: rootIdentity
                )
            case .expiringCompatibility:
                authorityCoordinator = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    signPack: signPack,
                    expectedRootIdentity: rootIdentity
                )
            }
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
        let observationAndTime = try validatedObservationAndTimeIndex(records: records)
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
                                currentRecord: try recordPayload(
                                    priorRecords[0],
                                    observationAndTime: observationAndTime
                                ),
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
                            correctionRecord: try recordPayload(
                                source,
                                observationAndTime: observationAndTime
                            ),
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

    private func recordPayload(
        _ value: WorkflowRecord,
        observationAndTime: [UUID: ObservationAndTimeRow]
    ) throws -> WorkflowRecordPayloadV1 {
        guard let companion = observationAndTime[value.id] else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        return WorkflowRecordPayloadV1(
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
            finalizationMutationID: value.finalizationMutationID,
            observationBasisV1Data: companion.observationBasisV1Data,
            temporalContextV1Data: companion.temporalContextV1Data
        )
    }

    private func validatedObservationAndTimeIndex(
        records: [WorkflowRecord]
    ) throws -> [UUID: ObservationAndTimeRow] {
        guard records.count <= ObservationAndTimeRowStoreV1.maximumRows else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        var rows: [ObservationAndTimeRow] = []
        rows.reserveCapacity(records.count)
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<ObservationAndTimeRow>(
                sortBy: [SortDescriptor(\.recordID)]
            )
            descriptor.fetchLimit = Self.observationAndTimeBatchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            rows.append(contentsOf: batch)
            guard rows.count <= ObservationAndTimeRowStoreV1.maximumRows else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            guard batch.count == Self.observationAndTimeBatchSize else { break }
            offset += batch.count
        }

        let recordIDs = Set(records.map(\.id))
        var result: [UUID: ObservationAndTimeRow] = [:]
        result.reserveCapacity(rows.count)
        for row in rows {
            guard recordIDs.contains(row.recordID),
                  result.updateValue(row, forKey: row.recordID) == nil else {
                throw ReportRecoveryServiceError.invalidAuthority
            }
            do { try row.validate() } catch {
                throw ReportRecoveryServiceError.invalidAuthority
            }
        }
        guard result.count == recordIDs.count else {
            throw ReportRecoveryServiceError.invalidAuthority
        }
        return result
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

    private static let observationAndTimeBatchSize = 512

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - C23 version-bound field-reference recovery

enum FieldReferenceReportRecoveryPolicyV1 {
    static let boundReleaseIsRecoverySource = true
    static let finalizedBindingIsImmutable = true
    static let silentReleaseReplacementAllowed = false
    static let discardUnboundReferenceMetadata = true
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true

    static func validateRecoveredProjection(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> FieldReferenceReportProjectionV1 {
        try projection.validate()
        guard boundReleaseIsRecoverySource,
              finalizedBindingIsImmutable,
              !silentReleaseReplacementAllowed,
              discardUnboundReferenceMetadata,
              excludesReferenceBytes,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity,
              projection.historicBindingImmutable,
              projection.restrictedContentOmitted else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }
}

// MARK: - C25 survey-definition recovery boundary

enum SurveyDefinitionReportRecoveryPolicyV1 {
    static let recoverySource = "CANONICAL_SURVEY_DEFINITION_RELEASE"
    static let releaseBindingIsFrozen = true
    static let draftPreviewsAreDiscarded = true
    static let rebuildDerivedConsumers = true
    static let historicReportsAreNotRewritten = true
    static let excludesAnswers = true
    static let excludesPromptText = true
    static let excludesActorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesEvidenceBytes = true

    static func validateRecoveredProjection(
        _ projection: SurveyDefinitionReportProjectionV1
    ) throws -> SurveyDefinitionReportProjectionV1 {
        try projection.validate(format: .openJSON)
        guard releaseBindingIsFrozen,
              draftPreviewsAreDiscarded,
              rebuildDerivedConsumers,
              historicReportsAreNotRewritten,
              excludesAnswers,
              excludesPromptText,
              excludesActorIdentity,
              excludesPrivateLocators,
              excludesEvidenceBytes else {
            throw SurveyDefinitionConsumerFailureV1.privacyViolation
        }
        return projection
    }
}

// MARK: - C27 asset-locator recovery boundary

enum AssetLocatorReportRecoveryPolicyV1 {
    static let recoverySource = "CANONICAL_ASSET_LOCATOR_AND_RESOLUTION_HISTORY"
    static let resolutionPreviewsAreDiscarded = true
    static let derivedSearchIsRebuilt = true
    static let historicInterpretationIsFrozen = true
    static let currentPointerCannotRewriteHistory = true
    static let excludesOpaqueInput = true
    static let excludesPrivateKeyMaterial = true
    static let excludesSecrets = true
    static let excludesVendorIdentifiers = true

    static func validateRecoveredProjection(
        _ projection: AssetLocatorReportProjectionV1
    ) throws -> AssetLocatorReportProjectionV1 {
        try projection.validate(format: .openJSON)
        guard resolutionPreviewsAreDiscarded, derivedSearchIsRebuilt,
              historicInterpretationIsFrozen, currentPointerCannotRewriteHistory,
              excludesOpaqueInput, excludesPrivateKeyMaterial,
              excludesSecrets, excludesVendorIdentifiers else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }
}

// MARK: - C28 schedule recovery boundary

enum ScheduleReportRecoveryPolicyV1 {
    static let recoverySource = "CANONICAL_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY"
    static let dueQueueRebuiltFromCanonicalHistory = true
    static let reminderRebuiltFromDueQueue = true
    static let finalizedReportIsNotRewritten = true
    static let notificationDeliveryIsTruth = false
    static let excludesNotificationPayload = true

    static func rebuildDueQueue(
        workspaceID: WorkspaceID,
        evaluatedAt: Date,
        definitions: [ScheduleDefinitionReleaseV1],
        history: [OccurrenceHistoryEventV1]
    ) throws -> DueQueueProjectionV1 {
        guard dueQueueRebuiltFromCanonicalHistory,
              reminderRebuiltFromDueQueue,
              finalizedReportIsNotRewritten,
              !notificationDeliveryIsTruth,
              excludesNotificationPayload else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        return try DueQueueProjectionV1(
            workspaceID: workspaceID,
            evaluatedAt: evaluatedAt,
            definitions: definitions,
            history: history
        )
    }

    static func validateRecovered(
        _ projection: ScheduleReportProjectionV1
    ) throws -> ScheduleReportProjectionV1 {
        try ScheduleReportProjectionPolicyV1.validate(projection)
        guard finalizedReportIsNotRewritten,
              !notificationDeliveryIsTruth else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        return projection
    }
}

// MARK: - C29 plan/rebase recovery boundary

enum PlanReportRecoveryPolicyV1 {
    static let recoverySource = "CANONICAL_PLAN_DOCUMENT_REVISION_PLACEMENT"
    static let rebasePreviewIsRecomputed = true
    static let historicProjectionIsNotRewritten = true
    static let stalePreviewFailsClosed = true
    static let componentConflictFailsClosed = true
    static let searchRowsAreRebuilt = true
    static let excludesSourceBytes = true
    static let excludesPrivateLocator = true
    static let excludesActorIdentity = true

    static func validateRecovered(
        _ projection: PlanReportProjectionV1
    ) throws -> PlanReportProjectionV1 {
        guard rebasePreviewIsRecomputed,
              historicProjectionIsNotRewritten,
              stalePreviewFailsClosed,
              componentConflictFailsClosed,
              searchRowsAreRebuilt,
              excludesSourceBytes, excludesPrivateLocator,
              excludesActorIdentity else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try PlanReportProjectionPolicyV1.validate(projection)
        return projection
    }
}

// MARK: - C37 pose history/rebase recovery boundary

enum C37PoseReportRecoveryPolicyV1 {
    static let staleCurrentTipRequiresReconciliation = true
    static let rebasePreviewMustBeRecomputed = true
    static let historicSnapshotRemainsReadable = true
    static let interruptionHasNoPartialCanonicalPose = true
    static let manualFallbackRemainsAvailable = true
    static let excludesSensorStream = true

    static func validate(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> C37PlacementPoseReportProjectionV1 {
        guard staleCurrentTipRequiresReconciliation,
              rebasePreviewMustBeRecomputed,
              historicSnapshotRemainsReadable,
              interruptionHasNoPartialCanonicalPose,
              manualFallbackRemainsAvailable,
              excludesSensorStream else {
            throw C37PoseReportProjectionFailureV1.privacyViolation
        }
        try C37PoseReportProjectionPolicyV1.validate(projection)
        return projection
    }

    static func recoverFrozenSnapshot(
        _ snapshot: C37PlacementPoseFrozenSnapshotV1
    ) throws -> C37PlacementPoseFrozenSnapshotV1 {
        try snapshot.validate()
        return snapshot
    }
}

extension ReportRecoveryService {
    static func recoverPlacementPoseProjection(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> C37PlacementPoseReportProjectionV1 {
        try C37PoseReportRecoveryPolicyV1.validate(projection)
    }
}

enum C48PortableReviewReportRecoveryBoundaryV1 {
    static let recoveryReadsImmutableResponseHistory = true
    static let recoveryDoesNotRewriteResponseBytes = true
    static let capabilityBytesRecoveredIntoDerivedSurface = false
    static let capabilityProofBytesRecoveredIntoDerivedSurface = false
    static let responseBodyRecoveredIntoDerivedSurface = false
    static let rawRequestResponseBytesRecoveredIntoDerivedSurface = false
    static let externalReviewCannotRecoverFinalization = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}
// MARK: - C30 operating-context recovery

extension ReportRecoveryService {
    static func recoverOperatingContextProjection(
        _ projection: C30EvidenceContextReportReferenceV1
    ) throws -> C30EvidenceContextReportReferenceV1 {
        // Recovery revalidates the frozen projection; it never recomputes a
        // condition from a timestamp, photo, or solar input.
        try SnapshotValidatorV1.validateOperatingContext(projection)
    }

    static let c30OperatingContextRecoveryIsValidationOnly = true
    static let c30OperatingContextManualOfflineFallback = true
    static let c30OperatingContextDoesNotRewriteHistory = true
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Reporting_ReportRecoveryService {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift", role: .report)
}

// MARK: - C31 lighting recovery

extension ReportRecoveryService {
    static func recoverLightingProjection(
        _ projection: C31LightingReportProjectionV1
    ) throws -> C31LightingReportProjectionV1 {
        // Recovery validates the immutable projection only.  It never
        // recalculates topology, measurements, solar context, or claim tier.
        try SnapshotValidatorV1.validateLightingProjection(projection)
    }

    static let c31LightingRecoveryIsValidationOnly = true
    static let c31LightingHistoryIsNeverRewritten = true
    static let c31LightingManualOfflineFallback = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Reporting_ReportRecoveryService {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportRecoveryService_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

/// C45 recovery adopts only exact complete manifests and deletes partial scratch.
enum C45AssetLabelBoundary_ReportRecoveryServiceV1 {
    static func validate(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws { try snapshot.validate() }
    static let adoptsPartialOutput = false
}

enum C46OperationalContactBoundary_31{static let defaultProjection="EXCLUDED";static let rawPhoneOrEmailEmitted=false;static let platformOutcomeClaimEmitted=false}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportRecoveryService_swift {
    static let integrationRole = "RECOVER_DURABLE_ONLY"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingReportInfrastructure = true
    static let createsSecondRendererWriterOrStore = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

extension ReportRecoveryService {
    static func reopenActivityContract(
        _ projection: ActivityContractReportProjectionV2,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        _ = try projection.canonicalCompletedSnapshotBytes()
        return try ReportProjectionRegistryV1().recoverActivityContract(
            projection, manifest: manifest, reportProfile: reportProfile,
            exportProfile: exportProfile, storedBundle: storedBundle
        )
    }
}
