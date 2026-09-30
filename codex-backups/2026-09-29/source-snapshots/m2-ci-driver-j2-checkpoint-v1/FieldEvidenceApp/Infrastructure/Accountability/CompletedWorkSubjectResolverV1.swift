import Foundation
import SwiftData

/// One current-tip candidate returned by the listing. The resolution is
/// either a validated proof or the exact reason it is unavailable.
struct CompletedWorkSubjectTipV1: Hashable, Sendable {
    let key: CompletedWorkSubjectKeyV1
    let resolution: CompletedWorkSubjectResolutionV1
}

/// A report correction chain inside one packet: every member's fixed
/// position and the unique tip, when the chain has one.
struct CompletedWorkSubjectChainV1: Hashable, Sendable {
    let positions: [UUID: UInt64]
    let tipReportID: UUID?
}

/// Read-only SIG-1 resolver. It never writes, saves, inserts or deletes and
/// never substitutes one subject for another. Every validation reuses the
/// incumbent `SnapshotValidatorV1.validateCompletedInspection` path, whose
/// replacement-chain check covers the whole workspace and fails closed.
@MainActor
struct CompletedWorkSubjectResolverV1 {
    static let listingLimit = 25
    private static let maximumRows = 100_000

    let modelContext: ModelContext
    let workspaceID: WorkspaceID
    let generationID: UUID
    let generationRootURL: URL
    let signPack: SignPack

    init(
        modelContext: ModelContext,
        workspaceID: WorkspaceID,
        generationID: UUID,
        generationRootURL: URL,
        signPack: SignPack
    ) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.signPack = signPack
    }

    // MARK: - Chain position

    private struct ChainLinkV1 {
        let packetID: UUID
        let replacesReportID: UUID?
    }

    /// 1 for the original, plus one per `replacesReportID` link back to it.
    /// A missing member, a cycle or a cross-packet link returns nil.
    private static func chainPosition(
        of reportID: UUID,
        links: [UUID: ChainLinkV1]
    ) -> UInt64? {
        guard let start = links[reportID] else { return nil }
        var position: UInt64 = 1
        var visited: Set<UUID> = [reportID]
        var current = start
        while let priorID = current.replacesReportID {
            guard let prior = links[priorID],
                  prior.packetID == start.packetID,
                  visited.insert(priorID).inserted,
                  position < UInt64.max else {
                return nil
            }
            position += 1
            current = prior
        }
        return position
    }

    // MARK: - Row loading

    private struct RowSetV1 {
        let reports: [Report]
        let packets: [Packet]
        let records: [WorkflowRecord]
        let links: [UUID: ChainLinkV1]
        let replacedReportIDs: Set<UUID>
        let duplicateReportIDs: Set<UUID>

        func reportRows(id: UUID) -> [Report] {
            reports.filter { $0.id == id }
        }

        func packetRows(id: UUID) -> [Packet] {
            packets.filter { $0.id == id }
        }

        func recordRows(id: UUID) -> [WorkflowRecord] {
            records.filter { $0.id == id }
        }
    }

    private func boundedFetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = Self.maximumRows + 1
        let values = try modelContext.fetch(descriptor)
        guard values.count <= Self.maximumRows else {
            throw CompletedWorkSubjectFailureV1.storeUnavailable
        }
        return values
    }

    private func loadRows() throws -> RowSetV1 {
        guard !modelContext.hasChanges else {
            throw CompletedWorkSubjectFailureV1.storeUnavailable
        }
        let reports = try boundedFetch(Report.self)
        let packets = try boundedFetch(Packet.self)
        let records = try boundedFetch(WorkflowRecord.self)
        var links: [UUID: ChainLinkV1] = [:]
        var duplicates = Set<UUID>()
        var replaced = Set<UUID>()
        for report in reports {
            if links[report.id] != nil {
                duplicates.insert(report.id)
            }
            links[report.id] = ChainLinkV1(
                packetID: report.packetID,
                replacesReportID: report.replacesReportID
            )
            if let priorID = report.replacesReportID {
                replaced.insert(priorID)
            }
        }
        return RowSetV1(
            reports: reports,
            packets: packets,
            records: records,
            links: links,
            replacedReportIDs: replaced,
            duplicateReportIDs: duplicates
        )
    }

    // MARK: - Validation

    private func makeValidator() throws -> SnapshotValidatorV1 {
        try SnapshotValidatorV1(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            signPack: signPack
        )
    }

    private func makeProof(
        report: Report,
        position: UInt64,
        isTip: Bool,
        validated: ValidatedReportSnapshotV1
    ) -> CompletedWorkSubjectProofV1? {
        let snapshot = validated.snapshot
        guard snapshot.reportID == report.id,
              snapshot.packetID == report.packetID,
              snapshot.sourceRecordID == report.sourceRecordID,
              validated.snapshotSHA256 == report.snapshotSHA256 else {
            return nil
        }
        let display = CompletedWorkSubjectDisplayV1(
            siteLabel: snapshot.site.label,
            assetLabel: snapshot.asset.label,
            stage: snapshot.display.stage,
            outcome: snapshot.display.outcome,
            localDate: snapshot.timeContext.localDate,
            localTime: snapshot.timeContext.localTime,
            version: position
        )
        return CompletedWorkSubjectProofV1(
            workspaceID: workspaceID,
            generationID: generationID,
            reportID: report.id,
            packetID: report.packetID,
            sourceRecordID: report.sourceRecordID,
            chainPosition: position,
            snapshotFamily: .legacyReportSnapshot,
            snapshotSchemaVersion: report.snapshotSchemaVersion,
            snapshotSHA256: report.snapshotSHA256,
            isTip: isTip,
            display: display
        )
    }

    // MARK: - Key to proof

    /// Resolves exactly the named version or reports why it is unavailable.
    /// A superseded version still resolves (for history), with `isTip` false.
    func resolve(_ key: CompletedWorkSubjectKeyV1) -> CompletedWorkSubjectResolutionV1 {
        guard key.workspaceID == workspaceID else { return .unavailable(.wrongWorkspace) }
        guard key.family == .legacyReportSnapshot else { return .unavailable(.unsupportedFamily) }
        let rows: RowSetV1
        do {
            rows = try loadRows()
        } catch {
            return .unavailable(.storeUnavailable)
        }
        return resolve(key, rows: rows)
    }

    private func resolve(
        _ key: CompletedWorkSubjectKeyV1,
        rows: RowSetV1
    ) -> CompletedWorkSubjectResolutionV1 {
        let matches = rows.reportRows(id: key.subjectID)
        guard !matches.isEmpty else { return .unavailable(.missing) }
        guard matches.count == 1, let report = matches.first,
              !rows.duplicateReportIDs.contains(report.id) else {
            return .unavailable(.tampered)
        }
        guard let position = Self.chainPosition(of: report.id, links: rows.links) else {
            return .unavailable(.tampered)
        }
        guard position == key.subjectRevision else { return .unavailable(.revisionMismatch) }
        let packets = rows.packetRows(id: report.packetID)
        guard packets.count == 1, let packet = packets.first else {
            return .unavailable(.tampered)
        }
        guard packet.contentDeletedAt == nil else { return .unavailable(.deleted) }
        let sources = rows.recordRows(id: report.sourceRecordID)
        guard sources.count == 1, let source = sources.first,
              source.state == WorkflowState.completed.rawValue else {
            return .unavailable(.notCompleted)
        }
        let isTip = !rows.replacedReportIDs.contains(report.id)
        if isTip, packet.currentRecordID != report.sourceRecordID {
            return .unavailable(.tampered)
        }
        do {
            let root = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
            let validated = try makeValidator().validateCompletedInspection(
                report: report,
                expectedRootIdentity: root
            )
            guard let proof = makeProof(
                report: report,
                position: position,
                isTip: isTip,
                validated: validated
            ) else {
                return .unavailable(.tampered)
            }
            return .resolved(proof)
        } catch {
            return .unavailable(.tampered)
        }
    }

    // MARK: - Current tips

    private struct TipCandidateV1 {
        let report: Report
        let position: UInt64
    }

    func currentTips() throws -> [CompletedWorkSubjectTipV1] {
        try currentTips(limit: Self.listingLimit)
    }

    /// Current-tip subjects, newest report first (then report identity),
    /// capped at `limit`. Deleted, non-current and non-completed packets are
    /// not tips. A tip whose frozen snapshot fails validation is returned
    /// as unavailable rather than dropped or substituted.
    func currentTips(limit: Int) throws -> [CompletedWorkSubjectTipV1] {
        let rows = try loadRows()
        var candidates: [TipCandidateV1] = []
        for report in rows.reports {
            guard !rows.replacedReportIDs.contains(report.id),
                  !rows.duplicateReportIDs.contains(report.id) else { continue }
            let packets = rows.packetRows(id: report.packetID)
            guard packets.count == 1, let packet = packets.first,
                  packet.contentDeletedAt == nil,
                  packet.currentRecordID == report.sourceRecordID else { continue }
            let sources = rows.recordRows(id: report.sourceRecordID)
            guard sources.count == 1,
                  sources[0].state == WorkflowState.completed.rawValue else { continue }
            guard let position = Self.chainPosition(of: report.id, links: rows.links) else {
                continue
            }
            candidates.append(TipCandidateV1(report: report, position: position))
        }
        candidates.sort { lhs, rhs in
            if lhs.report.createdAt != rhs.report.createdAt {
                return lhs.report.createdAt > rhs.report.createdAt
            }
            return lhs.report.id.uuidString.lowercased() < rhs.report.id.uuidString.lowercased()
        }
        let selected = Array(candidates.prefix(max(0, limit)))
        guard !selected.isEmpty else { return [] }

        // Each validated snapshot (including its evidence bytes) is reduced
        // to a lightweight proof inside the consumer and then released; no
        // snapshot or media bytes are retained by the listing.
        var positions: [UUID: UInt64] = [:]
        for candidate in selected {
            positions[candidate.report.id] = candidate.position
        }
        var proofs: [UUID: CompletedWorkSubjectProofV1] = [:]
        let root = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
        let validator = try makeValidator()
        let selectedReports: [Report] = selected.map { $0.report }
        do {
            try validator.validateCompletedInspectionReports(
                selectedReports,
                expectedRootIdentity: root
            ) { report, value in
                if let position = positions[report.id],
                   let proof = makeProof(
                       report: report, position: position, isTip: true, validated: value
                   ) {
                    proofs[report.id] = proof
                }
            }
        } catch {
            // Isolate a single failing report. A workspace-wide chain failure
            // fails every report closed.
            proofs = [:]
            for candidate in selected {
                if let proof = lightweightProof(
                    report: candidate.report,
                    position: candidate.position,
                    validator: validator,
                    root: root
                ) {
                    proofs[candidate.report.id] = proof
                }
            }
        }

        var tips: [CompletedWorkSubjectTipV1] = []
        for candidate in selected {
            let key = try CompletedWorkSubjectKeyV1(
                workspaceID: workspaceID,
                family: .legacyReportSnapshot,
                subjectID: candidate.report.id,
                subjectRevision: candidate.position
            )
            let resolution: CompletedWorkSubjectResolutionV1
            if let proof = proofs[candidate.report.id] {
                resolution = .resolved(proof)
            } else {
                resolution = .unavailable(.tampered)
            }
            tips.append(CompletedWorkSubjectTipV1(key: key, resolution: resolution))
        }
        return tips
    }

    /// Validates one report and keeps only its lightweight proof; the
    /// validated snapshot and its media bytes go out of scope here.
    private func lightweightProof(
        report: Report,
        position: UInt64,
        validator: SnapshotValidatorV1,
        root: ReportPDFAnchoredFile.RootIdentity
    ) -> CompletedWorkSubjectProofV1? {
        guard let value = try? validator.validateCompletedInspection(
            report: report,
            expectedRootIdentity: root
        ) else {
            return nil
        }
        return makeProof(report: report, position: position, isTip: true, validated: value)
    }

    // MARK: - Chain membership

    /// The correction chain containing `reportID`, or nil when that report
    /// does not exist. Positions come from stored links only; they are not a
    /// validation claim.
    func chain(containing reportID: UUID) throws -> CompletedWorkSubjectChainV1? {
        let rows = try loadRows()
        guard let link = rows.links[reportID] else { return nil }
        var positions: [UUID: UInt64] = [:]
        var tips: [UUID] = []
        for report in rows.reports where report.packetID == link.packetID {
            if let position = Self.chainPosition(of: report.id, links: rows.links) {
                positions[report.id] = position
            }
            if !rows.replacedReportIDs.contains(report.id) {
                tips.append(report.id)
            }
        }
        return CompletedWorkSubjectChainV1(
            positions: positions,
            tipReportID: tips.count == 1 ? tips.first : nil
        )
    }
}
