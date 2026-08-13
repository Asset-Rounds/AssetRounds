import CryptoKit
import Darwin
import Foundation
import PDFKit
import SwiftData

extension Notification.Name {
    static let reportPDFBecameUnavailable = Notification.Name(
        "FieldEvidence.reportPDFBecameUnavailable"
    )
}

final class ReportPDFUnavailableEvent: NSObject, @unchecked Sendable {
    let reportID: UUID

    init(reportID: UUID) {
        self.reportID = reportID
    }
}

struct ReportDeliveryValue: Equatable, Sendable {
    let reportID: UUID
    let pdfSHA256: String
    let pdfData: Data
    let filename: String
    let title: String
    let subtitle: String
    let detailLines: [String]
}

struct ValidatedReadyEvidenceValue: Equatable, Sendable {
    let snapshot: EvidenceSnapshotV1
    let originalData: Data
    let thumbnailData: Data
}

struct ValidatedReadyReportValue: Equatable, Sendable {
    let delivery: ReportDeliveryValue
    let snapshot: ReportSnapshotV1
    let evidence: [ValidatedReadyEvidenceValue]
}

struct ReportDeliveryChainValue: Equatable, Sendable {
    let current: ReportDeliveryValue
    let ancestors: [ReportDeliveryValue]
}

struct ReportCorrectionSourceValue: Equatable, Sendable {
    let sourceReportID: UUID
    let sourceRecordID: UUID
    let currentNote: String?
    let chain: ReportDeliveryChainValue
}

enum ReportCorrectionSubmissionResult: Equatable, Sendable {
    case ready(ReportDeliveryChainValue)
    case pdfUnavailable(reportID: UUID, prior: ReportDeliveryValue)
}

enum ReportDeliveryPreparation: Equatable, Sendable {
    case ready(ReportDeliveryValue)
    case failed(reportID: UUID)
}

enum ReportDeliveryCoordinatorError: Error, Equatable {
    case invalidGeneration
    case contextHasChanges
    case reportNotFound
    case invalidAuthority
    case invalidCorrection
    case correctionFinalizationFailed
}

@MainActor
final class ReportDeliveryCoordinator {
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let diagnosticsStore: DiagnosticsStore?
    private let signPack: SignPack
    private let renderService: ReportRenderService
    private let finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection?
    private let finalizationServiceFailureInjection: FinalizationServiceFailureInjection?
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private var receiptAttempts: Set<UUID> = []

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        diagnosticsStore: DiagnosticsStore? = nil,
        signPack: SignPack = .illuminatedSignV1,
        renderFailureInjection: ReportRenderFailureInjection? = nil,
        finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        finalizationServiceFailureInjection: FinalizationServiceFailureInjection? = nil,
        expectedRootIdentity: ReportPDFAnchoredFile.RootIdentity? = nil
    ) throws {
        let root = generationRootURL.standardizedFileURL
        guard generationRootURL.isFileURL,
              root.deletingLastPathComponent().lastPathComponent == "generations",
              root.deletingLastPathComponent().deletingLastPathComponent()
                .lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw ReportDeliveryCoordinatorError.invalidGeneration
        }
        do {
            let observedRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
            guard expectedRootIdentity.map({ $0 == observedRootIdentity }) ?? true else {
                throw ReportDeliveryCoordinatorError.invalidGeneration
            }
            let capturedRootIdentity = expectedRootIdentity ?? observedRootIdentity
            self.rootIdentity = capturedRootIdentity
            self.renderService = try ReportRenderService(
                modelContext: modelContext,
                generationRootURL: root,
                signPack: signPack,
                failureInjection: renderFailureInjection
            )
            guard try ReportPDFAnchoredFile.rootIdentity(at: root)
                    == capturedRootIdentity else {
                throw ReportDeliveryCoordinatorError.invalidGeneration
            }
        } catch {
            throw ReportDeliveryCoordinatorError.invalidGeneration
        }
        self.modelContext = modelContext
        self.generationRootURL = root
        self.diagnosticsStore = diagnosticsStore
        self.signPack = signPack
        self.finalizationStoreFailureInjection = finalizationStoreFailureInjection
        self.finalizationServiceFailureInjection = finalizationServiceFailureInjection
    }

    func prepareFinalizedReport(id reportID: UUID) throws -> ReportDeliveryPreparation {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let report = try uniqueReport(id: reportID)
        try requireUnambiguousReportAuthority(report)
        let chain = try validatedReplacementChain(containing: report)
        guard chain.first?.id == report.id else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        for ancestor in chain.dropFirst() {
            _ = try validatedReadyReport(
                ancestor,
                requiresCurrentTip: false
            )
        }
        if receiptAttempts.contains(reportID) {
            if report.pdfState == ReportPDFState.ready.rawValue {
                return .ready(try loadReadyReport(id: reportID))
            }
            guard report.pdfState == ReportPDFState.failed.rawValue,
                  report.pdfRelativePath == nil,
                  report.pdfSHA256 == nil else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            return .failed(reportID: reportID)
        }
        guard report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil else {
            if report.pdfState == ReportPDFState.ready.rawValue {
                return .ready(try loadReadyReport(id: reportID))
            }
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }

        receiptAttempts.insert(reportID)
        switch try renderService.attemptPendingReport(id: reportID) {
        case .ready:
            return .ready(try loadReadyReport(id: reportID))
        case .failed(let failedID):
            guard failedID == reportID else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            return .failed(reportID: reportID)
        }
    }

    func loadReadyReport(id reportID: UUID) throws -> ReportDeliveryValue {
        try validatedReadyReport(id: reportID).delivery
    }

    func validatedReadyReport(id reportID: UUID) throws -> ValidatedReadyReportValue {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let report = try uniqueReport(id: reportID)
        try requireUnambiguousReportAuthority(report)
        let chain = try validatedReplacementChain(containing: report)
        guard chain.contains(where: { $0.id == report.id }) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return try validatedReadyReport(
            report,
            requiresCurrentTip: chain.first?.id == report.id
        )
    }

    /// Startup/retry authority gate. The current tip may be pending or failed,
    /// but its complete immutable snapshot/evidence graph must still validate;
    /// every replaced ancestor must remain a fully readable ready delivery.
    func validateRecoveryAuthority(id reportID: UUID) throws {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let report = try uniqueReport(id: reportID)
        try requireUnambiguousReportAuthority(report)
        let chain = try validatedReplacementChain(containing: report)
        guard let current = chain.first,
              chain.contains(where: { $0.id == report.id }) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        for ancestor in chain.dropFirst() {
            _ = try validatedReadyReport(
                ancestor,
                requiresCurrentTip: false
            )
        }
        if report.id != current.id {
            return
        }
        switch ReportPDFState(rawValue: report.pdfState) {
        case .ready:
            _ = try validatedReadyReport(report, requiresCurrentTip: true)
        case .pending, .failed:
            guard report.pdfRelativePath == nil,
                  report.pdfSHA256 == nil else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            _ = try validateCompleteSnapshotAuthority(
                report: report,
                requiresCurrentTip: true,
                requiresReadyDelivery: false
            )
        case nil:
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
    }

    private func validatedReadyReport(
        _ report: Report,
        requiresCurrentTip: Bool
    ) throws -> ValidatedReadyReportValue {
        let reportID = report.id
        let canonicalID = reportID.uuidString.lowercased()
        let expectedPDFPath = "pdfs/\(canonicalID).pdf"
        guard report.schemaVersion == 1,
              report.pdfState == ReportPDFState.ready.rawValue,
              report.pdfRelativePath == expectedPDFPath,
              let storedPDFSHA256 = report.pdfSHA256,
              Self.isLowercaseSHA256(storedPDFSHA256),
              report.snapshotSchemaVersion == 1,
              report.snapshotRelativePath == "snapshots/\(canonicalID).json",
              Self.isLowercaseSHA256(report.snapshotSHA256),
              try anchoredLeafIsAbsent(relativePath: ".staging/pdfs/\(canonicalID).pdf") else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }

        let validated = try validateCompleteSnapshotAuthority(
            report: report,
            requiresCurrentTip: requiresCurrentTip
        )
        let snapshot = validated.snapshot

        let pdfData = try anchoredRead(relativePath: expectedPDFPath)
        guard !pdfData.isEmpty,
              Self.sha256(pdfData) == storedPDFSHA256,
              let document = PDFDocument(data: pdfData),
              document.pageCount > 0,
              try anchoredLeafIsAbsent(
                relativePath: ".staging/pdfs/\(canonicalID).pdf"
              ) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        let delivery = ReportDeliveryValue(
            reportID: reportID,
            pdfSHA256: storedPDFSHA256,
            pdfData: pdfData,
            filename: "report-\(canonicalID).pdf",
            title: snapshot.asset.label,
            subtitle: snapshot.site.label,
            detailLines: [
                snapshot.display.stage,
                snapshot.display.outcome,
                snapshot.timeContext.localDate,
                snapshot.timeContext.localTime,
            ]
        )
        return ValidatedReadyReportValue(
            delivery: delivery,
            snapshot: snapshot,
            evidence: validated.evidence
        )
    }

    func onlyReadyReport(assetID: UUID) throws -> ReportDeliveryValue? {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        var candidates: [Report] = []
        for packet in packets where packet.currentRecordID != nil
            && packet.contentDeletedAt == nil {
            guard packet.schemaVersion == 1,
                  let currentRecordID = packet.currentRecordID,
                  packets.filter({ $0.id == packet.id }).count == 1,
                  packets.filter({ $0.stableRootID == packet.stableRootID }).count == 1,
                  packets.filter({ $0.currentRecordID == currentRecordID }).count == 1 else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            let sources = records.filter { $0.id == currentRecordID }
            guard sources.count == 1 else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            guard sources[0].assetID == assetID else { continue }
            let matches = reports.filter {
                $0.packetID == packet.id && $0.sourceRecordID == currentRecordID
            }
            guard matches.count == 1 else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            if matches[0].pdfState == ReportPDFState.ready.rawValue {
                candidates.append(matches[0])
            }
        }
        guard candidates.count <= 1 else { return nil }
        guard let report = candidates.first else { return nil }
        return try loadReadyReport(id: report.id)
    }

    func readyDeliveryChain(
        currentReportID: UUID
    ) throws -> ReportDeliveryChainValue {
        let chain = try readyDeliveryChain(containingReportID: currentReportID)
        guard chain.current.reportID == currentReportID else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return chain
    }

    /// Returns the unique complete replacement chain containing a supplied
    /// ready report. The current tip is first even when the supplied report is
    /// a historical ancestor reached from a stale receipt or route.
    func readyDeliveryChain(
        containingReportID reportID: UUID
    ) throws -> ReportDeliveryChainValue {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let selectedReport = try uniqueReport(id: reportID)
        let chain = try validatedReplacementChain(containing: selectedReport)
        guard chain.contains(where: { $0.id == reportID }) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        let deliveries = try chain.enumerated().map { index, report in
            try validatedReadyReport(report, requiresCurrentTip: index == 0).delivery
        }
        guard let current = deliveries.first else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return ReportDeliveryChainValue(
            current: current,
            ancestors: Array(deliveries.dropFirst())
        )
    }

    func correctionSource(reportID: UUID) throws -> ReportCorrectionSourceValue {
        let chain = try readyDeliveryChain(currentReportID: reportID)
        let report = try uniqueReport(id: reportID)
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == report.sourceRecordID
        }
        guard records.count == 1 else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return ReportCorrectionSourceValue(
            sourceReportID: report.id,
            sourceRecordID: records[0].id,
            currentNote: records[0].note,
            chain: chain
        )
    }

    func submitCorrection(
        from source: ReportCorrectionSourceValue,
        note: String?
    ) async throws -> ReportCorrectionSubmissionResult {
        let info = Bundle.main.infoDictionary ?? [:]
        return try await submitCorrection(
            from: source,
            note: note,
            snapshotCreatedAt: Date(),
            sourceApp: SourceAppSnapshotV1(
                build: info["CFBundleVersion"] as? String ?? "0",
                version: info["CFBundleShortVersionString"] as? String ?? "0"
            )
        )
    }

    func submitCorrection(
        from source: ReportCorrectionSourceValue,
        note: String?,
        snapshotCreatedAt: Date,
        sourceApp: SourceAppSnapshotV1,
        identifiers suppliedIdentifiers: ReportCorrectionIdentifiers? = nil
    ) async throws -> ReportCorrectionSubmissionResult {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let report = try uniqueReport(id: source.sourceReportID)
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == source.sourceRecordID
        }
        let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == report.packetID
        }
        guard records.count == 1, packets.count == 1 else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        let identifiers = suppliedIdentifiers ?? ReportCorrectionIdentifiers(
            mutationID: UUID(),
            recordID: UUID(),
            reportID: UUID()
        )
        let existingReplayReports = try modelContext.fetch(
            FetchDescriptor<Report>()
        ).filter { $0.id == identifiers.reportID }
        let isReadyReplay = existingReplayReports.count == 1
            && existingReplayReports[0].pdfState == ReportPDFState.ready.rawValue
        if existingReplayReports.count == 1, !isReadyReplay {
            // A persisted pending/failed correction is never resubmitted through
            // this command. Pending is startup-recovered; failed uses the saved
            // report's explicit retry surface.
            throw ReportDeliveryCoordinatorError.invalidCorrection
        }
        let validated: ValidatedReadyReportValue
        if isReadyReplay {
            let fullChain = try validatedReplacementChain(containing: report)
            guard fullChain.contains(where: { $0.id == report.id }) else {
                throw ReportDeliveryCoordinatorError.invalidCorrection
            }
            validated = try validatedReadyReport(
                report,
                requiresCurrentTip: fullChain.first?.id == report.id
            )
            guard let sourceIndex = fullChain.firstIndex(where: {
                $0.id == report.id
            }) else {
                throw ReportDeliveryCoordinatorError.invalidCorrection
            }
            let suffix = Array(fullChain[sourceIndex...])
            let deliveries = try suffix.map { value in
                try validatedReadyReport(
                    value,
                    requiresCurrentTip: fullChain.first?.id == value.id
                ).delivery
            }
            guard let historicalCurrent = deliveries.first,
                  source == ReportCorrectionSourceValue(
                    sourceReportID: report.id,
                    sourceRecordID: records[0].id,
                    currentNote: records[0].note,
                    chain: ReportDeliveryChainValue(
                        current: historicalCurrent,
                        ancestors: Array(deliveries.dropFirst())
                    )
                  ) else {
                throw ReportDeliveryCoordinatorError.invalidCorrection
            }
        } else {
            let refreshed = try correctionSource(reportID: source.sourceReportID)
            guard refreshed == source else {
                throw ReportDeliveryCoordinatorError.invalidCorrection
            }
            validated = try validatedReadyReport(report, requiresCurrentTip: true)
        }
        let finalization: ReportCorrectionFinalizationOutcome
        do {
            finalization = try await FinalizationService(
                modelContext: modelContext,
                signPack: signPack,
                generationRootURL: generationRootURL,
                intentStoreFailureInjection: finalizationStoreFailureInjection,
                failureInjection: finalizationServiceFailureInjection,
                expectedRootIdentity: rootIdentity
            ).finalizeCorrection(ReportCorrectionFinalizationInput(
                currentRecord: records[0],
                packet: packets[0],
                currentReport: report,
                currentSnapshot: validated.snapshot,
                note: note,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: sourceApp,
                identifiers: identifiers
            ))
        } catch let error as FinalizationServiceError {
            switch error {
            case .invalidSelection:
                throw ReportDeliveryCoordinatorError.invalidCorrection
            case .committedRecoveryRequired(let reportID):
                guard reportID == identifiers.reportID,
                      let persisted = try? persistedUnavailableCorrection(
                        source: source,
                        note: note,
                        snapshotCreatedAt: snapshotCreatedAt,
                        sourceApp: sourceApp,
                        identifiers: identifiers
                      ) else {
                    throw ReportDeliveryCoordinatorError.correctionFinalizationFailed
                }
                return persisted
            default:
                throw ReportDeliveryCoordinatorError.correctionFinalizationFailed
            }
        } catch {
            throw ReportDeliveryCoordinatorError.correctionFinalizationFailed
        }
        let newReport = try uniqueReport(id: finalization.reportID)
        if !finalization.createdAuthority {
            switch ReportPDFState(rawValue: newReport.pdfState) {
            case .ready:
                return .ready(try readyDeliveryChain(currentReportID: newReport.id))
            case .failed, .pending:
                return try persistedUnavailableCorrection(
                    source: source,
                    note: note,
                    snapshotCreatedAt: snapshotCreatedAt,
                    sourceApp: sourceApp,
                    identifiers: identifiers
                )
            case nil:
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
        }
        switch ReportPDFState(rawValue: newReport.pdfState) {
        case .ready:
            return .ready(try readyDeliveryChain(currentReportID: newReport.id))
        case .failed:
            return try persistedUnavailableCorrection(
                source: source,
                note: note,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: sourceApp,
                identifiers: identifiers
            )
        case .pending:
            switch try prepareFinalizedReport(id: newReport.id) {
            case .ready:
                return .ready(try readyDeliveryChain(currentReportID: newReport.id))
            case .failed(let reportID):
                guard reportID == identifiers.reportID else {
                    throw ReportDeliveryCoordinatorError.invalidAuthority
                }
                return try persistedUnavailableCorrection(
                    source: source,
                    note: note,
                    snapshotCreatedAt: snapshotCreatedAt,
                    sourceApp: sourceApp,
                    identifiers: identifiers
                )
            }
        case nil:
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
    }

    /// Proves that a correction committed even though its PDF is unavailable.
    /// This is the only path that may produce the persisted-failure UI result;
    /// a caller-visible throw therefore continues to mean that no such complete
    /// correction authority could be proven.
    private func persistedUnavailableCorrection(
        source: ReportCorrectionSourceValue,
        note: String?,
        snapshotCreatedAt: Date,
        sourceApp: SourceAppSnapshotV1,
        identifiers: ReportCorrectionIdentifiers
    ) throws -> ReportCorrectionSubmissionResult {
        guard !modelContext.hasChanges else {
            throw ReportDeliveryCoordinatorError.contextHasChanges
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let newReports = reports.filter { $0.id == identifiers.reportID }
        let newRecords = records.filter {
            $0.id == identifiers.recordID
                || $0.finalizationMutationID == identifiers.mutationID
        }
        let priorReports = reports.filter { $0.id == source.sourceReportID }
        let priorRecords = records.filter { $0.id == source.sourceRecordID }
        guard newReports.count == 1,
              newRecords.count == 1,
              priorReports.count == 1,
              priorRecords.count == 1,
              newRecords[0].id == identifiers.recordID,
              newRecords[0].finalizationMutationID == identifiers.mutationID,
              let state = ReportPDFState(rawValue: newReports[0].pdfState),
              state == .pending || state == .failed,
              newReports[0].pdfRelativePath == nil,
              newReports[0].pdfSHA256 == nil else {
            throw ReportDeliveryCoordinatorError.invalidCorrection
        }
        let packetMatches = packets.filter { $0.id == newReports[0].packetID }
        guard packetMatches.count == 1 else {
            throw ReportDeliveryCoordinatorError.invalidCorrection
        }
        let packet = packetMatches[0]
        let chain = try validatedReplacementChain(containing: newReports[0])
        let expectedAncestorIDs = [source.chain.current.reportID]
            + source.chain.ancestors.map(\.reportID)
        guard chain.first?.id == newReports[0].id,
              Array(chain.dropFirst()).map(\.id) == expectedAncestorIDs,
              chain.dropFirst().first?.id == priorReports[0].id else {
            throw ReportDeliveryCoordinatorError.invalidCorrection
        }
        let prior = try validatedReadyReport(
            priorReports[0],
            requiresCurrentTip: false
        )
        guard prior.delivery == source.chain.current,
              priorReports[0].sourceRecordID == priorRecords[0].id,
              priorRecords[0].id == source.sourceRecordID else {
            throw ReportDeliveryCoordinatorError.invalidCorrection
        }
        let packetBefore = PacketPayloadV1(
            id: packet.id,
            schemaVersion: packet.schemaVersion,
            stableRootID: packet.stableRootID,
            currentRecordID: priorRecords[0].id,
            evaluationCounted: packet.evaluationCounted,
            contentDeletedAt: packet.contentDeletedAt,
            createdAt: packet.createdAt
        )
        let expected = try ReportCorrectionRule().makePlan(
            source: ReportCorrectionRuleSource(
                currentRecord: recordPayload(priorRecords[0]),
                packet: packetBefore,
                currentReport: reportPayload(priorReports[0]),
                currentSnapshot: prior.snapshot
            ),
            request: ReportCorrectionRuleRequest(
                note: note,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: sourceApp,
                identifiers: identifiers
            )
        )
        let storedReport = newReports[0]
        let normalizedStoredReport = ReportPayloadV1(
            id: storedReport.id,
            schemaVersion: storedReport.schemaVersion,
            packetID: storedReport.packetID,
            sourceRecordID: storedReport.sourceRecordID,
            snapshotSchemaVersion: storedReport.snapshotSchemaVersion,
            snapshotRelativePath: storedReport.snapshotRelativePath,
            snapshotSHA256: storedReport.snapshotSHA256,
            pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: storedReport.createdAt,
            replacesReportID: storedReport.replacesReportID
        )
        let packetAfter = PacketPayloadV1(
            id: packet.id,
            schemaVersion: packet.schemaVersion,
            stableRootID: packet.stableRootID,
            currentRecordID: packet.currentRecordID,
            evaluationCounted: packet.evaluationCounted,
            contentDeletedAt: packet.contentDeletedAt,
            createdAt: packet.createdAt
        )
        guard recordPayload(newRecords[0]) == expected.recordAfter,
              normalizedStoredReport == expected.reportInsert,
              packetAfter == expected.packetAfter,
              try readCanonicalSnapshot(for: storedReport) == expected.snapshot else {
            throw ReportDeliveryCoordinatorError.invalidCorrection
        }
        try validateRecoveryAuthority(id: storedReport.id)
        return .pdfUnavailable(
            reportID: storedReport.id,
            prior: source.chain.current
        )
    }

    /// Shows the existing retry surface only after the persisted-failure result
    /// has been consumed. This keeps the owner-approved result copy stable.
    func acknowledgePersistedPDFUnavailable(reportID: UUID) throws {
        let report = try uniqueReport(id: reportID)
        guard report.pdfState == ReportPDFState.failed.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        try validateRecoveryAuthority(id: reportID)
        NotificationCenter.default.post(
            name: .reportPDFBecameUnavailable,
            object: ReportPDFUnavailableEvent(reportID: reportID)
        )
    }

    func shareSheetDidPresent() async {
        await diagnosticsStore?.increment(.reportShareSheetPresented)
    }

    private func uniqueReport(id: UUID) throws -> Report {
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == id
        }
        guard reports.count == 1 else {
            throw reports.isEmpty
                ? ReportDeliveryCoordinatorError.reportNotFound
                : ReportDeliveryCoordinatorError.invalidAuthority
        }
        return reports[0]
    }

    private func requireUnambiguousReportAuthority(_ report: Report) throws {
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        guard reports.filter({ $0.id == report.id }).count == 1,
              reports.filter({ $0.sourceRecordID == report.sourceRecordID }).count == 1 else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
    }

    private func validateCompleteSnapshotAuthority(
        report: Report,
        requiresCurrentTip: Bool,
        requiresReadyDelivery: Bool = true
    ) throws -> ReadyReportAuthorityValidation {
        do {
            return try ReadyReportAuthorityValidator(
                modelContext: modelContext,
                signPack: signPack,
                anchoredRead: anchoredRead(relativePath:)
            ).validate(
                report: report,
                requiresCurrentTip: requiresCurrentTip,
                requiresReadyDelivery: requiresReadyDelivery
            )
        } catch {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
    }

    /// Returns the one complete Packet-local replacement chain, current first.
    /// Each report edge must mirror the record revision edge exactly; no stray
    /// report or revision beneath the same Packet/root is accepted.
    private func validatedReplacementChain(
        containing selected: Report
    ) throws -> [Report] {
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let packetMatches = packets.filter { $0.id == selected.packetID }
        guard packetMatches.count == 1,
              let packet = packetMatches.first,
              packet.schemaVersion == 1,
              packet.contentDeletedAt == nil,
              packet.evaluationCounted,
              let currentRecordID = packet.currentRecordID,
              packets.filter({ $0.stableRootID == packet.stableRootID }).count == 1,
              packets.filter({ $0.currentRecordID == currentRecordID }).count == 1 else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        let packetReports = reports.filter { $0.packetID == packet.id }
        guard !packetReports.isEmpty,
              Set(reports.map(\.id)).count == reports.count,
              Set(reports.map(\.sourceRecordID)).count == reports.count,
              Set(records.map(\.id)).count == records.count,
              Set(packetReports.map(\.id)).count == packetReports.count,
              Set(packetReports.map(\.sourceRecordID)).count == packetReports.count,
              packetReports.contains(where: { $0.id == selected.id }) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        let currentReports = packetReports.filter {
            $0.sourceRecordID == currentRecordID
        }
        guard currentReports.count == 1,
              reports.filter({ $0.replacesReportID == currentReports[0].id }).isEmpty,
              records.filter({ $0.revisesRecordID == currentRecordID }).isEmpty else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }

        var result: [Report] = []
        var report = currentReports[0]
        var visitedReports = Set<UUID>()
        var visitedRecords = Set<UUID>()
        while true {
            guard visitedReports.insert(report.id).inserted else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            let sourceMatches = records.filter { $0.id == report.sourceRecordID }
            guard sourceMatches.count == 1,
                  let source = sourceMatches.first,
                  source.packetID == packet.id,
                  visitedRecords.insert(source.id).inserted else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            result.append(report)
            switch WorkflowRevisionKind(rawValue: source.revisionKind) {
            case .original:
                guard source.recordRevisionRootID == source.id,
                      source.revisesRecordID == nil,
                      source.evidenceSourceRecordID == nil,
                      report.replacesReportID == nil else {
                    throw ReportDeliveryCoordinatorError.invalidAuthority
                }
                break
            case .clericalCorrection:
                guard let priorRecordID = source.revisesRecordID,
                      let priorReportID = report.replacesReportID,
                      source.evidenceSourceRecordID == source.recordRevisionRootID,
                      records.filter({ $0.revisesRecordID == priorRecordID }).count == 1,
                      evidence.filter({ $0.recordID == source.id }).isEmpty else {
                    throw ReportDeliveryCoordinatorError.invalidAuthority
                }
                let priorReports = packetReports.filter { $0.id == priorReportID }
                guard priorReports.count == 1,
                      priorReports[0].sourceRecordID == priorRecordID,
                      reports.filter({ $0.replacesReportID == priorReportID }).count == 1 else {
                    throw ReportDeliveryCoordinatorError.invalidAuthority
                }
                report = priorReports[0]
                continue
            case nil:
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            break
        }
        let packetRecordIDs = Set(records.filter {
            $0.packetID == packet.id
        }.map(\.id))
        guard result.count == packetReports.count,
              packetRecordIDs == visitedRecords else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        for index in result.indices.dropLast() {
            let newer = result[index]
            let prior = result[result.index(after: index)]
            let newerSnapshot = try readCanonicalSnapshot(for: newer)
            let priorSnapshot = try readCanonicalSnapshot(for: prior)
            let newerRecords = records.filter { $0.id == newer.sourceRecordID }
            let priorRecords = records.filter { $0.id == prior.sourceRecordID }
            guard newerRecords.count == 1, priorRecords.count == 1 else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            do {
                try ReportCorrectionRule().validateEdge(
                    prior: ReportCorrectionRuleSource(
                        currentRecord: recordPayload(priorRecords[0]),
                        packet: PacketPayloadV1(
                            id: packet.id,
                            schemaVersion: packet.schemaVersion,
                            stableRootID: packet.stableRootID,
                            currentRecordID: priorRecords[0].id,
                            evaluationCounted: packet.evaluationCounted,
                            contentDeletedAt: packet.contentDeletedAt,
                            createdAt: packet.createdAt
                        ),
                        currentReport: reportPayload(prior),
                        currentSnapshot: priorSnapshot
                    ),
                    correctionRecord: recordPayload(newerRecords[0]),
                    correctionReport: reportPayload(newer),
                    correctionSnapshot: newerSnapshot
                )
            } catch {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
        }
        return result
    }

    private func readCanonicalSnapshot(for report: Report) throws -> ReportSnapshotV1 {
        let data = try anchoredRead(relativePath: report.snapshotRelativePath)
        guard Self.sha256(data) == report.snapshotSHA256 else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        do {
            let value = try ReportSnapshotEncoderV1().decode(data)
            guard try ReportSnapshotEncoderV1().encode(value).data == data else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            return value
        } catch {
            throw ReportDeliveryCoordinatorError.invalidAuthority
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
    private func anchoredRead(relativePath: String) throws -> Data {
        guard Self.isCanonicalRelativePath(relativePath) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        do {
            return try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(relativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
    }

    private func anchoredLeafIsAbsent(relativePath: String) throws -> Bool {
        guard Self.isCanonicalRelativePath(relativePath) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        let components = relativePath.split(separator: "/").map(String.init)
        var descriptor = Darwin.open(
            generationRootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        defer { Darwin.close(descriptor) }
        var rootInfo = stat()
        guard Darwin.fstat(descriptor, &rootInfo) == 0,
              (rootInfo.st_mode & S_IFMT) == S_IFDIR,
              rootInfo.st_dev == rootIdentity.device,
              rootInfo.st_ino == rootIdentity.inode else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        for component in components.dropLast() {
            let next = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if next < 0, errno == ENOENT { return true }
            guard next >= 0 else {
                throw ReportDeliveryCoordinatorError.invalidAuthority
            }
            Darwin.close(descriptor)
            descriptor = next
        }
        var info = stat()
        let status = Darwin.fstatat(
            descriptor,
            components.last!,
            &info,
            AT_SYMLINK_NOFOLLOW
        )
        if status == 0 { return false }
        guard errno == ENOENT else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return true
    }

    private static func isCanonicalRelativePath(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("/")
            && !value.contains("\\")
            && value.split(separator: "/").allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func draftStep(_ value: String?) throws -> WorkflowDraftStep? {
        guard let value else { return nil }
        guard let step = WorkflowDraftStep(rawValue: value) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return step
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value)
                    || (97...102).contains(scalar.value)
            }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalOptionalDateEqual(
        _ lhs: Date,
        _ rhs: Date?
    ) -> Bool {
        guard let rhs else { return false }
        return canonicalTimestamp(lhs) == canonicalTimestamp(rhs)
    }

    private static func canonicalTimestamp(_ value: Date) -> String {
        timestampFormatter.string(from: value)
    }

    private static func stageDisplay(_ value: String) -> String? {
        switch value {
        case WorkflowStage.check.rawValue: return "Check"
        case WorkflowStage.work.rawValue: return "Work"
        case WorkflowStage.recheck.rawValue: return "Recheck"
        default: return nil
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
private struct ReadyValidatedEvidenceBytes: Sendable {
    let originalJPEG: Data
    let thumbnailJPEG: Data
}

private struct ReadyReportAuthorityValidation: Sendable {
    let snapshot: ReportSnapshotV1
    let evidence: [ValidatedReadyEvidenceValue]
}
@MainActor
private struct ReadyReportAuthorityValidator {
    private static let templateID = "field.evidence.pdf.worklight.v1"

    private let modelContext: ModelContext
    private let signPack: SignPack
    private let anchoredRead: @MainActor (String) throws -> Data
    private let mediaValidator = MediaNormalizerV1()

    init(
        modelContext: ModelContext,
        signPack: SignPack,
        anchoredRead: @escaping @MainActor (String) throws -> Data
    ) {
        self.modelContext = modelContext
        self.signPack = signPack
        self.anchoredRead = anchoredRead
    }

    func validate(
        report: Report,
        requiresCurrentTip: Bool,
        requiresReadyDelivery: Bool
    ) throws -> ReadyReportAuthorityValidation {
        do {
            return try validateAuthority(
                report: report,
                requiresCurrentTip: requiresCurrentTip,
                requiresReadyDelivery: requiresReadyDelivery
            )
        } catch let error as SnapshotValidationErrorV1 {
            throw error
        } catch {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateAuthority(
        report: Report,
        requiresCurrentTip: Bool,
        requiresReadyDelivery: Bool
    ) throws -> ReadyReportAuthorityValidation {
        let reportID = canonicalID(report.id)
        let expectedSnapshotPath = "snapshots/\(reportID).json"
        let hasLegalDeliveryState: Bool
        if requiresReadyDelivery {
            hasLegalDeliveryState = report.pdfState == ReportPDFState.ready.rawValue
                && report.pdfRelativePath == "pdfs/\(reportID).pdf"
                && report.pdfSHA256.map(isLowercaseSHA256) == true
        } else {
            hasLegalDeliveryState = (report.pdfState == ReportPDFState.pending.rawValue
                || report.pdfState == ReportPDFState.failed.rawValue)
                && report.pdfRelativePath == nil
                && report.pdfSHA256 == nil
        }
        guard report.schemaVersion == 1,
              report.snapshotSchemaVersion == 1,
              report.snapshotRelativePath == expectedSnapshotPath,
              isLowercaseSHA256(report.snapshotSHA256),
              hasLegalDeliveryState else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let snapshotData = try readRegularNonsymlinkFile(
            expectedRelativePath: expectedSnapshotPath
        )
        let encodedDigest = Self.sha256(snapshotData)
        guard encodedDigest == report.snapshotSHA256 else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        let snapshot = try ReportSnapshotEncoderV1().decode(snapshotData)
        guard try ReportSnapshotEncoderV1().encode(snapshot).data == snapshotData,
              snapshot.snapshotSchemaVersion == 1,
              snapshot.reportID == report.id,
              snapshot.packetID == report.packetID,
              snapshot.sourceRecordID == report.sourceRecordID,
              snapshot.pdfTemplate.id == Self.templateID,
              snapshot.pdfTemplate.version == 1,
              snapshot.pack.id == signPack.packID,
              snapshot.pack.schemaVersion == signPack.schemaVersion,
              snapshot.pack.contentVersion == signPack.contentVersion,
              snapshot.display.assetSingular == signPack.nouns.asset.singular,
              snapshot.display.checkSingular == signPack.nouns.check.singular,
              snapshot.display.issueSingular == signPack.nouns.issue.singular,
              snapshot.display.stage == stageDisplay(snapshot.stage),
              snapshot.display.outcome == outcomeDisplay(snapshot.outcome),
              snapshot.disclaimer == signPack.disclaimer,
              canonicalDateEqual(snapshot.snapshotCreatedAt, report.createdAt) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        guard let storedReport = unique(reports.filter { $0.id == report.id }),
              storedReport.schemaVersion == report.schemaVersion,
              storedReport.packetID == report.packetID,
              storedReport.sourceRecordID == report.sourceRecordID,
              storedReport.snapshotSchemaVersion == report.snapshotSchemaVersion,
              storedReport.snapshotRelativePath == report.snapshotRelativePath,
              storedReport.snapshotSHA256 == report.snapshotSHA256,
              storedReport.pdfState == report.pdfState,
              storedReport.pdfRelativePath == report.pdfRelativePath,
              storedReport.pdfSHA256 == report.pdfSHA256,
              canonicalDateEqual(storedReport.createdAt, report.createdAt),
              storedReport.replacesReportID == report.replacesReportID else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        guard let packet = unique(packets.filter { $0.id == report.packetID }),
              packet.schemaVersion == 1,
              packet.stableRootID == snapshot.stableRootID,
              (!requiresCurrentTip
                || packet.currentRecordID == report.sourceRecordID),
              packet.currentRecordID != nil,
              packet.evaluationCounted,
              packet.contentDeletedAt == nil,
              packets.filter({ $0.stableRootID == packet.stableRootID }).count == 1,
              packets.filter({ $0.currentRecordID == packet.currentRecordID }).count == 1 else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let recordsByID = try uniqueRecords(records)
        guard let source = recordsByID[report.sourceRecordID],
              source.schemaVersion == 1,
              source.state == WorkflowState.completed.rawValue,
              source.packetID == report.packetID,
              source.finalizationMutationID != nil,
              source.packID == snapshot.pack.id,
              source.packSchemaVersion == snapshot.pack.schemaVersion,
              source.packContentVersion == snapshot.pack.contentVersion,
              source.pdfTemplateID == snapshot.pdfTemplate.id,
              source.pdfTemplateVersion == snapshot.pdfTemplate.version,
              source.stage == snapshot.stage,
              source.outcomeKey == snapshot.outcome,
              source.note == snapshot.note,
              validCompletedRecord(source) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        try validateFrozenSourceFields(snapshot: snapshot, source: source)

        let effectiveID = source.evidenceSourceRecordID ?? source.id
        guard effectiveID == snapshot.evidenceSourceRecordID,
              let effective = recordsByID[effectiveID],
              effective.schemaVersion == 1,
              effective.state == WorkflowState.completed.rawValue,
              effective.revisionKind == WorkflowRevisionKind.original.rawValue,
              effective.finalizationMutationID != nil,
              effective.assetID == source.assetID,
              effective.packetID == source.packetID,
              validCompletedRecord(effective),
              validSourceRevision(source, effective: effective, recordsByID: recordsByID) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let chain = try parentChain(endingAt: effective, recordsByID: recordsByID)
        try validateLineage(chain)
        try validatePacketAuthorities(
            for: chain,
            packets: packets,
            recordsByID: recordsByID
        )
        let issueSnapshots = try expectedIssues(
            for: chain,
            assetID: source.assetID
        )
        guard issueSnapshotsEqual(snapshot.issues, issueSnapshots) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let expectedHistoryRecords: [WorkflowRecord]
        if snapshot.issues.isEmpty {
            expectedHistoryRecords = []
        } else {
            let ancestors = Array(chain.dropLast())
            guard ancestors.allSatisfy({
                $0.revisionKind == WorkflowRevisionKind.original.rawValue
                    && validCompletedRecord($0)
            }) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            expectedHistoryRecords = ancestors.sorted(by: recordChronology)
        }
        guard let effectiveCompletedAt = effective.completedAt,
              expectedHistoryRecords.allSatisfy({ record in
                guard let completedAt = record.completedAt else { return false }
                return completedAt < effectiveCompletedAt
              }) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        guard snapshot.history.map(\.recordID) == expectedHistoryRecords.map(\.id),
              !snapshot.history.contains(where: { $0.recordID == effective.id }) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let allEvidenceRows = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let evidenceRowsByID = try uniqueEvidenceRows(allEvidenceRows)
        let currentRows = allEvidenceRows
            .filter { $0.recordID == effective.id }
            .sorted(by: evidenceOrder)
        try validateCurrentCardinality(rows: currentRows, effective: effective)

        var orderedRows = currentRows
        var seenEvidenceIDs = Set(currentRows.map(\.id))
        for (history, record) in zip(snapshot.history, expectedHistoryRecords) {
            try validateHistory(history, against: record)
            let rows = allEvidenceRows
                .filter { $0.recordID == record.id }
                .sorted(by: evidenceOrder)
            try validateHistoricalCardinality(rows: rows, record: record)
            guard history.evidenceIDs == rows.map(\.id),
                  history.issueIDs == (try historyIssueIDs(
                    record: record,
                    assetID: source.assetID,
                    allIssues: try modelContext.fetch(FetchDescriptor<Issue>())
                  )) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            for row in rows where seenEvidenceIDs.insert(row.id).inserted {
                orderedRows.append(row)
            }
        }

        guard snapshot.evidence.count == orderedRows.count,
              snapshot.evidence.map(\.evidenceID) == orderedRows.map(\.id),
              Set(snapshot.evidence.map(\.evidenceID)).count == snapshot.evidence.count,
              orderedRows.allSatisfy({ evidenceRowsByID[$0.id] != nil }) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        var validatedBytes: [UUID: ReadyValidatedEvidenceBytes] = [:]
        for (value, row) in zip(snapshot.evidence, orderedRows) {
            guard validateEvidenceSnapshot(value, row: row) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            let id = canonicalID(row.id)
            let original = try readRegularNonsymlinkFile(
                expectedRelativePath: "evidence/\(id)/original.jpg"
            )
            let thumbnail = try readRegularNonsymlinkFile(
                expectedRelativePath: "evidence/\(id)/thumbnail.jpg"
            )
            guard original.count == row.byteCount,
                  thumbnail.count == row.thumbnailByteCount,
                  Self.sha256(original) == row.sha256,
                  Self.sha256(thumbnail) == row.thumbnailSHA256 else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            _ = try mediaValidator.validateCanonicalJPEG(original, kind: .original)
            _ = try mediaValidator.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            guard validatedBytes.updateValue(
                ReadyValidatedEvidenceBytes(
                    originalJPEG: original,
                    thumbnailJPEG: thumbnail
                ),
                forKey: row.id
            ) == nil else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }

        let historyEvidenceIDs = Set(snapshot.history.flatMap(\.evidenceIDs))
        var referencedByteCount: Int64 = 0
        for row in orderedRows {
            let selectedCount: Int
            if row.recordID == effective.id {
                selectedCount = row.byteCount
            } else if historyEvidenceIDs.contains(row.id) {
                selectedCount = row.thumbnailByteCount
            } else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            let (next, overflow) = referencedByteCount.addingReportingOverflow(
                Int64(selectedCount)
            )
            guard !overflow else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            referencedByteCount = next
        }

        let evidence = try snapshot.evidence.map { value in
            guard let bytes = validatedBytes[value.evidenceID] else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            return ValidatedReadyEvidenceValue(
                snapshot: value,
                originalData: bytes.originalJPEG,
                thumbnailData: bytes.thumbnailJPEG
            )
        }
        return ReadyReportAuthorityValidation(
            snapshot: snapshot,
            evidence: evidence
        )
    }

    private func validateFrozenSourceFields(
        snapshot: ReportSnapshotV1,
        source: WorkflowRecord
    ) throws {
        let expectedCNV = frozenCNV(source)
        guard signPack.acknowledgements.count == 2,
              snapshot.couldNotVerify == expectedCNV,
              canonicalOptionalDateEqual(
                snapshot.timeContext.observedAtUTC,
                source.observedAtUTC
              ),
              snapshot.timeContext.timeZoneID == source.timeZoneID,
              snapshot.timeContext.utcOffsetMinutes == source.utcOffsetMinutes,
              snapshot.timeContext.localDate == source.localDate,
              snapshot.timeContext.localTime == source.localTime,
              snapshot.acknowledgements.count == 2,
              snapshot.acknowledgements[0].key == source.afterDarkAcknowledgementKey,
              snapshot.acknowledgements[0].copy == source.afterDarkAcknowledgementCopy,
              snapshot.acknowledgements[0].version == source.afterDarkAcknowledgementVersion,
              snapshot.acknowledgements[0].accepted
                == source.afterDarkAcknowledgementAccepted,
              snapshot.acknowledgements[0].key
                == signPack.acknowledgements[0].key,
              snapshot.acknowledgements[0].copy
                == signPack.acknowledgements[0].copy,
              snapshot.acknowledgements[0].version
                == signPack.acknowledgements[0].version,
              snapshot.acknowledgements[1].key == source.safePositionAcknowledgementKey,
              snapshot.acknowledgements[1].copy == source.safePositionAcknowledgementCopy,
              snapshot.acknowledgements[1].version == source.safePositionAcknowledgementVersion,
              snapshot.acknowledgements[1].accepted
                == source.safePositionAcknowledgementAccepted,
              snapshot.acknowledgements[1].key
                == signPack.acknowledgements[1].key,
              snapshot.acknowledgements[1].copy
                == signPack.acknowledgements[1].copy,
              snapshot.acknowledgements[1].version
                == signPack.acknowledgements[1].version else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validCompletedRecord(_ record: WorkflowRecord) -> Bool {
        guard record.schemaVersion == 1,
              record.state == WorkflowState.completed.rawValue,
              record.draftStepKey == nil,
              record.completedAt != nil,
              record.outcomeKey != nil,
              record.finalizationMutationID != nil,
              record.packID == signPack.packID,
              record.packSchemaVersion == signPack.schemaVersion,
              record.packContentVersion == signPack.contentVersion,
              record.pdfTemplateID == Self.templateID,
              record.pdfTemplateVersion == 1,
              validOptionalTrimmed(record.note, maximum: 1_000) else {
            return false
        }

        switch record.revisionKind {
        case WorkflowRevisionKind.original.rawValue:
            guard record.recordRevisionRootID == record.id,
                  record.revisesRecordID == nil,
                  record.evidenceSourceRecordID == nil else {
                return false
            }
        case WorkflowRevisionKind.clericalCorrection.rawValue:
            guard record.recordRevisionRootID != record.id,
                  record.revisesRecordID != nil,
                  record.evidenceSourceRecordID == record.recordRevisionRootID else {
                return false
            }
        default:
            return false
        }

        let hasAnyCNV = record.couldNotVerifyKey != nil
            || record.couldNotVerifyDisplaySnapshot != nil
            || record.couldNotVerifyRegistryVersion != nil
        let hasCompleteCNV = record.couldNotVerifyKey != nil
            && record.couldNotVerifyDisplaySnapshot != nil
            && record.couldNotVerifyRegistryVersion != nil
        guard record.outcomeKey == "could_not_verify"
                ? hasCompleteCNV
                : !hasAnyCNV else {
            return false
        }
        if let cnv = frozenCNV(record) {
            let matches = signPack.couldNotVerifyReasons.entries.filter {
                $0.key == cnv.key
            }
            guard cnv.registryVersion == signPack.couldNotVerifyReasons.version,
                  matches.count == 1,
                  cnv.display == matches[0].display else {
                return false
            }
        }

        let hasAllAcknowledgements = record.afterDarkAcknowledgementKey != nil
            && record.afterDarkAcknowledgementCopy != nil
            && record.afterDarkAcknowledgementVersion != nil
            && record.afterDarkAcknowledgementAccepted != nil
            && record.safePositionAcknowledgementKey != nil
            && record.safePositionAcknowledgementCopy != nil
            && record.safePositionAcknowledgementVersion != nil
            && record.safePositionAcknowledgementAccepted != nil
        let hasNoAcknowledgements = record.afterDarkAcknowledgementKey == nil
            && record.afterDarkAcknowledgementCopy == nil
            && record.afterDarkAcknowledgementVersion == nil
            && record.afterDarkAcknowledgementAccepted == nil
            && record.safePositionAcknowledgementKey == nil
            && record.safePositionAcknowledgementCopy == nil
            && record.safePositionAcknowledgementVersion == nil
            && record.safePositionAcknowledgementAccepted == nil
        let hasAllTimeFields = record.observedAtUTC != nil
            && record.timeZoneID != nil
            && record.utcOffsetMinutes != nil
            && record.localDate != nil
            && record.localTime != nil
        let hasNoTimeFields = record.observedAtUTC == nil
            && record.timeZoneID == nil
            && record.utcOffsetMinutes == nil
            && record.localDate == nil
            && record.localTime == nil

        switch record.stage {
        case WorkflowStage.check.rawValue:
            return record.parentRecordID == nil
                && record.packetID != nil
                && ["no_visible_issue", "visible_issue", "could_not_verify"]
                    .contains(record.outcomeKey ?? "")
                && ((record.outcomeKey == "visible_issue") == (record.issueID != nil))
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && hasAllAcknowledgements
                && hasAllTimeFields
                && record.afterDarkAcknowledgementAccepted == true
                && record.safePositionAcknowledgementAccepted == true

        case WorkflowStage.recheck.rawValue:
            return record.parentRecordID != nil
                && record.issueID != nil
                && record.packetID != nil
                && [
                    "resolved",
                    "issue_still_visible",
                    "original_resolved_different_issue",
                    "could_not_verify",
                ].contains(record.outcomeKey ?? "")
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && hasAllAcknowledgements
                && hasAllTimeFields
                && record.afterDarkAcknowledgementAccepted == true
                && record.safePositionAcknowledgementAccepted == true

        case WorkflowStage.work.rawValue:
            return record.parentRecordID != nil
                && record.issueID != nil
                && record.packetID == nil
                && record.outcomeKey == "work_recorded"
                && record.workPerformedLocalDate?.range(
                    of: #"^\d{4}-\d{2}-\d{2}$"#,
                    options: .regularExpression
                ) != nil
                && validRequiredTrimmed(record.workDescription, maximum: 160)
                && hasNoAcknowledgements
                && hasNoTimeFields

        default:
            return false
        }
    }

    private func validSourceRevision(
        _ source: WorkflowRecord,
        effective: WorkflowRecord,
        recordsByID: [UUID: WorkflowRecord]
    ) -> Bool {
        if source.id == effective.id {
            return source.revisionKind == WorkflowRevisionKind.original.rawValue
        }
        guard source.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue,
              source.recordRevisionRootID == effective.id,
              source.evidenceSourceRecordID == effective.id else {
            return false
        }
        var visited: Set<UUID> = [source.id]
        var correction = source
        var revisedID = correction.revisesRecordID
        while let id = revisedID,
              visited.insert(id).inserted,
              let revision = recordsByID[id],
              revision.assetID == source.assetID,
              revision.packetID == source.packetID,
              revision.recordRevisionRootID == effective.id,
              validCompletedRecord(revision),
              noteOnlyCorrection(correction, revises: revision) {
            if revision.id == effective.id { return true }
            guard revision.revisionKind
                    == WorkflowRevisionKind.clericalCorrection.rawValue else {
                return false
            }
            correction = revision
            revisedID = revision.revisesRecordID
        }
        return false
    }

    private func noteOnlyCorrection(
        _ correction: WorkflowRecord,
        revises prior: WorkflowRecord
    ) -> Bool {
        correction.assetID == prior.assetID
            && correction.packetID == prior.packetID
            && correction.issueID == prior.issueID
            && correction.parentRecordID == prior.parentRecordID
            && correction.recordRevisionRootID == prior.recordRevisionRootID
            && correction.evidenceSourceRecordID == prior.recordRevisionRootID
            && correction.stage == prior.stage
            && canonicalOptionalDatesEqual(
                correction.observedAtUTC,
                prior.observedAtUTC
            )
            && correction.timeZoneID == prior.timeZoneID
            && correction.utcOffsetMinutes == prior.utcOffsetMinutes
            && correction.localDate == prior.localDate
            && correction.localTime == prior.localTime
            && correction.afterDarkAcknowledgementKey
                == prior.afterDarkAcknowledgementKey
            && correction.afterDarkAcknowledgementCopy
                == prior.afterDarkAcknowledgementCopy
            && correction.afterDarkAcknowledgementVersion
                == prior.afterDarkAcknowledgementVersion
            && correction.afterDarkAcknowledgementAccepted
                == prior.afterDarkAcknowledgementAccepted
            && correction.safePositionAcknowledgementKey
                == prior.safePositionAcknowledgementKey
            && correction.safePositionAcknowledgementCopy
                == prior.safePositionAcknowledgementCopy
            && correction.safePositionAcknowledgementVersion
                == prior.safePositionAcknowledgementVersion
            && correction.safePositionAcknowledgementAccepted
                == prior.safePositionAcknowledgementAccepted
            && correction.packID == prior.packID
            && correction.packSchemaVersion == prior.packSchemaVersion
            && correction.packContentVersion == prior.packContentVersion
            && correction.pdfTemplateID == prior.pdfTemplateID
            && correction.pdfTemplateVersion == prior.pdfTemplateVersion
            && correction.outcomeKey == prior.outcomeKey
            && correction.couldNotVerifyKey == prior.couldNotVerifyKey
            && correction.couldNotVerifyDisplaySnapshot
                == prior.couldNotVerifyDisplaySnapshot
            && correction.couldNotVerifyRegistryVersion
                == prior.couldNotVerifyRegistryVersion
            && correction.workPerformedLocalDate == prior.workPerformedLocalDate
            && correction.workDescription == prior.workDescription
    }

    private func frozenCNV(_ record: WorkflowRecord) -> CouldNotVerifySnapshotV1? {
        guard let key = record.couldNotVerifyKey,
              let display = record.couldNotVerifyDisplaySnapshot,
              let version = record.couldNotVerifyRegistryVersion else {
            return nil
        }
        return CouldNotVerifySnapshotV1(
            display: display,
            key: key,
            registryVersion: version
        )
    }

    private func validRequiredTrimmed(_ value: String?, maximum: Int) -> Bool {
        guard let value else { return false }
        return !value.isEmpty
            && value.count <= maximum
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validOptionalTrimmed(_ value: String?, maximum: Int) -> Bool {
        value == nil || validRequiredTrimmed(value, maximum: maximum)
    }

    private func validateCurrentCardinality(
        rows: [EvidenceFile],
        effective: WorkflowRecord
    ) throws {
        let keys = rows.map(\.purposeKey)
        guard effective.stage == WorkflowStage.check.rawValue
                || effective.stage == WorkflowStage.recheck.rawValue else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        if effective.outcomeKey == "could_not_verify" {
            guard rows.count <= 2,
                  Set(keys).count == keys.count,
                  keys.allSatisfy({ $0 == "wide_context" || $0 == "close_detail" }) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        } else {
            guard keys == ["wide_context", "close_detail"] else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
    }

    private func validateHistoricalCardinality(
        rows: [EvidenceFile],
        record: WorkflowRecord
    ) throws {
        let keys = rows.map(\.purposeKey)
        switch record.stage {
        case WorkflowStage.work.rawValue:
            guard rows.count <= 1,
                  keys.allSatisfy({ $0 == "work_context" }) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        case WorkflowStage.check.rawValue, WorkflowStage.recheck.rawValue:
            if record.outcomeKey == "could_not_verify" {
                guard rows.count <= 2,
                      Set(keys).count == keys.count,
                      keys.allSatisfy({
                        $0 == "wide_context" || $0 == "close_detail"
                      }) else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            } else {
                guard keys == ["wide_context", "close_detail"] else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            }
        default:
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateHistory(
        _ value: HistoryEntrySnapshotV1,
        against record: WorkflowRecord
    ) throws {
        guard let completedAt = record.completedAt,
              canonicalDateEqual(value.completedAt, completedAt),
              value.recordID == record.id,
              value.stage == record.stage,
              value.outcome == record.outcomeKey,
              value.stageDisplay == stageDisplay(record.stage),
              value.outcomeDisplay == outcomeDisplay(record.outcomeKey),
              value.note == record.note,
              value.workDescription == record.workDescription,
              value.workPerformedLocalDate == record.workPerformedLocalDate,
              Set(value.evidenceIDs).count == value.evidenceIDs.count,
              Set(value.issueIDs).count == value.issueIDs.count,
              value.issueIDs == value.issueIDs.sorted(by: {
                canonicalID($0) < canonicalID($1)
              }),
              validCompletedRecord(record) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        let expectedCNV = frozenCNV(record)
        guard value.couldNotVerify == expectedCNV else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateEvidenceSnapshot(
        _ value: EvidenceSnapshotV1,
        row: EvidenceFile
    ) -> Bool {
        let id = canonicalID(row.id)
        let purposeMatches = signPack.evidencePurposes.filter {
            $0.key == row.purposeKey
        }
        return row.schemaVersion == 1
            && value.evidenceID == row.id
            && value.recordID == row.recordID
            && value.purposeKey == row.purposeKey
            && purposeMatches.count == 1
            && value.purposeDisplay == purposeMatches[0].display
            && row.relativePath == "evidence/\(id)/original.jpg"
            && value.relativePath == row.relativePath
            && row.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg"
            && value.thumbnailRelativePath == row.thumbnailRelativePath
            && row.mimeType == MediaContractV1.durableMIMEType
            && value.mimeType == row.mimeType
            && row.byteCount > 0
            && row.byteCount <= MediaContractV1.originalByteCountMaximum
            && value.byteCount == row.byteCount
            && row.thumbnailByteCount > 0
            && row.thumbnailByteCount <= MediaContractV1.thumbnailByteCountMaximum
            && value.thumbnailByteCount == row.thumbnailByteCount
            && isLowercaseSHA256(row.sha256)
            && value.sha256 == row.sha256
            && isLowercaseSHA256(row.thumbnailSHA256)
            && value.thumbnailSHA256 == row.thumbnailSHA256
            && canonicalDateEqual(value.createdAt, row.createdAt)
    }

    private func expectedIssues(
        for chain: [WorkflowRecord],
        assetID: UUID
    ) throws -> [IssueSnapshotV1] {
        let allIssues = try modelContext.fetch(FetchDescriptor<Issue>())
        var issueIDs = Set<UUID>()
        for record in chain {
            if let issueID = record.issueID { issueIDs.insert(issueID) }
        }
        for issue in allIssues where chain.contains(where: { $0.id == issue.openedByRecordID }) {
            issueIDs.insert(issue.id)
        }
        var result: [IssueSnapshotV1] = []
        for issueID in issueIDs {
            guard let issue = unique(allIssues.filter { $0.id == issueID }),
                  issue.schemaVersion == 1,
                  issue.assetID == assetID,
                  let openingRecord = chain.first(where: {
                    $0.id == issue.openedByRecordID
                  }),
                  let openingCompletedAt = openingRecord.completedAt,
                  canonicalDateEqual(issue.createdAt, openingCompletedAt),
                  exactIssueDisplay(issue) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            var status = IssueStatus.open.rawValue
            var resolvedBy: UUID?
            var updatedAt = issue.createdAt
            for record in chain where record.issueID == issue.id {
                guard let completed = record.completedAt else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
                if record.stage == WorkflowStage.work.rawValue {
                    status = IssueStatus.recheckDue.rawValue
                    resolvedBy = nil
                    updatedAt = completed
                } else if record.stage == WorkflowStage.recheck.rawValue {
                    switch record.outcomeKey {
                    case "resolved", "original_resolved_different_issue":
                        status = IssueStatus.resolved.rawValue
                        resolvedBy = record.id
                        updatedAt = completed
                    case "issue_still_visible":
                        status = IssueStatus.open.rawValue
                        resolvedBy = nil
                        updatedAt = completed
                    case "could_not_verify":
                        break
                    default:
                        throw SnapshotValidationErrorV1.invalidAuthority
                    }
                }
            }
            result.append(IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: resolvedBy,
                status: status,
                updatedAt: updatedAt
            ))
        }
        return result.sorted {
            $0.createdAt < $1.createdAt
                || ($0.createdAt == $1.createdAt
                    && canonicalID($0.issueID) < canonicalID($1.issueID))
        }
    }

    private func validateLineage(_ chain: [WorkflowRecord]) throws {
        guard !chain.isEmpty else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        let allIssues = try modelContext.fetch(FetchDescriptor<Issue>())
        for record in chain {
            let opened = allIssues.filter { $0.openedByRecordID == record.id }
            switch (record.stage, record.outcomeKey) {
            case (WorkflowStage.check.rawValue, "visible_issue"):
                guard opened.count == 1,
                      opened[0].id == record.issueID else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            case (
                WorkflowStage.recheck.rawValue,
                "original_resolved_different_issue"
            ):
                guard opened.count == 1,
                      opened[0].id != record.issueID else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            default:
                guard opened.isEmpty else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            }
        }
        for index in chain.indices.dropFirst() {
            let parent = chain[chain.index(before: index)]
            let child = chain[index]
            guard child.parentRecordID == parent.id,
                  child.assetID == parent.assetID,
                  (child.stage == WorkflowStage.work.rawValue
                    || child.stage == WorkflowStage.recheck.rawValue),
                  let childIssueID = child.issueID else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            if childIssueID != parent.issueID {
                guard parent.outcomeKey == "original_resolved_different_issue",
                      let opened = unique(allIssues.filter {
                        $0.id == childIssueID && $0.openedByRecordID == parent.id
                      }),
                      opened.assetID == child.assetID else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            }
        }
    }

    private func validatePacketAuthorities(
        for chain: [WorkflowRecord],
        packets: [Packet],
        recordsByID: [UUID: WorkflowRecord]
    ) throws {
        for record in chain {
            if record.stage == WorkflowStage.work.rawValue {
                guard record.packetID == nil else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
                continue
            }
            guard record.stage == WorkflowStage.check.rawValue
                    || record.stage == WorkflowStage.recheck.rawValue,
                  let packetID = record.packetID,
                  let packet = unique(packets.filter { $0.id == packetID }),
                  packet.schemaVersion == 1,
                  packet.evaluationCounted,
                  packet.contentDeletedAt == nil,
                  packets.filter({
                    $0.stableRootID == packet.stableRootID
                  }).count == 1,
                  let currentRecordID = packet.currentRecordID,
                  packets.filter({
                    $0.currentRecordID == currentRecordID
                  }).count == 1,
                  let current = recordsByID[currentRecordID],
                  current.assetID == record.assetID,
                  current.packetID == packetID,
                  current.recordRevisionRootID == record.id,
                  validCompletedRecord(current),
                  validSourceRevision(
                    current,
                    effective: record,
                    recordsByID: recordsByID
                  ) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
    }

    private func historyIssueIDs(
        record: WorkflowRecord,
        assetID: UUID,
        allIssues: [Issue]
    ) throws -> [UUID] {
        var issuesByID: [UUID: Issue] = [:]
        for issue in allIssues {
            guard issuesByID.updateValue(issue, forKey: issue.id) == nil else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
        var result = Set(record.issueID.map { [$0] } ?? [])
        result.formUnion(allIssues.compactMap {
            $0.openedByRecordID == record.id ? $0.id : nil
        })
        guard result.allSatisfy({ id in
            guard let issue = issuesByID[id] else { return false }
            return issue.schemaVersion == 1
                && issue.assetID == assetID
                && !issue.labelKey.isEmpty
                && !issue.labelDisplaySnapshot.isEmpty
        }) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        return result.sorted { canonicalID($0) < canonicalID($1) }
    }

    private func issueSnapshotsEqual(
        _ lhs: [IssueSnapshotV1],
        _ rhs: [IssueSnapshotV1]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { pair in
            let (left, right) = pair
            return left.display == right.display
                && left.issueID == right.issueID
                && left.key == right.key
                && left.openedByRecordID == right.openedByRecordID
                && left.resolvedByRecordID == right.resolvedByRecordID
                && left.status == right.status
                && canonicalDateEqual(left.createdAt, right.createdAt)
                && canonicalDateEqual(left.updatedAt, right.updatedAt)
        }
    }

    private func exactIssueDisplay(_ issue: Issue) -> Bool {
        let matches = signPack.issueLabels.filter { $0.key == issue.labelKey }
        return matches.count == 1
            && matches[0].display == issue.labelDisplaySnapshot
    }

    private func parentChain(
        endingAt record: WorkflowRecord,
        recordsByID: [UUID: WorkflowRecord]
    ) throws -> [WorkflowRecord] {
        var reversed: [WorkflowRecord] = []
        var visited = Set<UUID>()
        var current: WorkflowRecord? = record
        while let value = current {
            guard visited.insert(value.id).inserted else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            reversed.append(value)
            if let parentID = value.parentRecordID {
                guard let parent = recordsByID[parentID],
                      parent.assetID == record.assetID else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
                current = parent
            } else {
                current = nil
            }
        }
        return Array(reversed.reversed())
    }

    private func readRegularNonsymlinkFile(
        expectedRelativePath: String
    ) throws -> Data {
        try anchoredRead(expectedRelativePath)
    }

    private func uniqueRecords(
        _ records: [WorkflowRecord]
    ) throws -> [UUID: WorkflowRecord] {
        var result: [UUID: WorkflowRecord] = [:]
        for record in records {
            guard result.updateValue(record, forKey: record.id) == nil else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
        return result
    }

    private func uniqueEvidenceRows(
        _ rows: [EvidenceFile]
    ) throws -> [UUID: EvidenceFile] {
        var result: [UUID: EvidenceFile] = [:]
        for row in rows {
            guard result.updateValue(row, forKey: row.id) == nil else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
        return result
    }

    private func unique<Value>(_ values: [Value]) -> Value? {
        values.count == 1 ? values[0] : nil
    }

    private func evidenceOrder(_ lhs: EvidenceFile, _ rhs: EvidenceFile) -> Bool {
        let left = purposeOrder(lhs.purposeKey)
        let right = purposeOrder(rhs.purposeKey)
        return left == right
            ? canonicalID(lhs.id) < canonicalID(rhs.id)
            : left < right
    }

    private func purposeOrder(_ value: String) -> Int {
        switch value {
        case "wide_context": 0
        case "close_detail": 1
        case "work_context": 2
        default: 3
        }
    }

    private func stageDisplay(_ value: String) -> String? {
        if value == WorkflowStage.work.rawValue { return "Work" }
        let matches = signPack.stageDisplays.filter { $0.key == value }
        return matches.count == 1 ? matches[0].display : nil
    }

    private func outcomeDisplay(_ value: String?) -> String? {
        guard let value else { return nil }
        if value == "work_recorded" { return "Work recorded" }
        let matches = signPack.outcomeDisplays.filter { $0.key == value }
        return matches.count == 1 ? matches[0].display : nil
    }

    private func recordChronology(_ lhs: WorkflowRecord, _ rhs: WorkflowRecord) -> Bool {
        guard let left = lhs.completedAt, let right = rhs.completedAt else { return false }
        return left < right || (left == right && canonicalID(lhs.id) < canonicalID(rhs.id))
    }

    private func canonicalOptionalDateEqual(_ lhs: Date, _ rhs: Date?) -> Bool {
        guard let rhs else { return false }
        return canonicalDateEqual(lhs, rhs)
    }

    private func canonicalOptionalDatesEqual(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let left), .some(let right)): canonicalDateEqual(left, right)
        default: false
        }
    }

    private func canonicalDateEqual(_ lhs: Date, _ rhs: Date) -> Bool {
        Self.canonicalTimestamp(lhs) == Self.canonicalTimestamp(rhs)
    }

    private func canonicalID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func canonicalTimestamp(_ value: Date) -> String {
        timestampFormatter.string(from: value)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
