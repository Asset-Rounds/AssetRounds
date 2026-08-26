import Foundation
import SwiftData

enum ReportHistoryFilter: Hashable, Sendable {
    case all
    case site(UUID)
    case asset(UUID)
}

struct ReportHistoryFilterOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
}

struct ReportHistoryEvidenceValue: Identifiable, Equatable, Sendable {
    var id: UUID { evidenceID }

    let evidenceID: UUID
    let purposeKey: String
    let purposeDisplay: String
    let originalData: Data
    let thumbnailData: Data
}

struct ReportHistoryVisitValue: Identifiable, Equatable, Sendable {
    var id: UUID { stableRootID }

    let stableRootID: UUID
    let packetID: UUID
    let reportID: UUID
    let siteID: UUID
    let assetID: UUID
    let completedAt: Date
    let siteLabel: String
    let assetLabel: String
    let stage: String
    let outcome: String
    let localDate: String
    let localTime: String
    let evidence: [ReportHistoryEvidenceValue]
}

struct ReportHistoryIndexValue: Equatable, Sendable {
    let visits: [ReportHistoryVisitValue]
    let siteOptions: [ReportHistoryFilterOption]
    let assetOptions: [ReportHistoryFilterOption]
}

struct ReportSignHistoryValue: Equatable, Sendable {
    let assetID: UUID
    let siteLabel: String
    let assetLabel: String
    let visits: [ReportHistoryVisitValue]
}

struct ReportHistoryComparisonValue: Equatable, Sendable {
    let then: ReportHistoryVisitValue
    let now: ReportHistoryVisitValue
}

enum ReportHistoryCoordinatorError: Error, Equatable {
    case contextHasChanges
    case invalidAuthority
}

@MainActor
final class ReportHistoryCoordinator {
    private let modelContext: ModelContext
    private let deliveryCoordinator: ReportDeliveryCoordinator

    init(
        modelContext: ModelContext,
        deliveryCoordinator: ReportDeliveryCoordinator
    ) {
        self.modelContext = modelContext
        self.deliveryCoordinator = deliveryCoordinator
    }

    func index(
        filter: ReportHistoryFilter = .all
    ) throws -> ReportHistoryIndexValue {
        let authority = try buildAuthority()
        let visits = authority.visits.filter { visit in
            switch filter {
            case .all:
                return true
            case .site(let siteID):
                return visit.siteID == siteID
            case .asset(let assetID):
                return visit.assetID == assetID
            }
        }
        let assetOptions: [ReportHistoryFilterOption]
        if case .site = filter {
            let representedAssetIDs = Set(visits.map(\.assetID))
            assetOptions = authority.assetOptions.filter {
                representedAssetIDs.contains($0.id)
            }
        } else {
            assetOptions = authority.assetOptions
        }
        return ReportHistoryIndexValue(
            visits: visits,
            siteOptions: authority.siteOptions,
            assetOptions: assetOptions
        )
    }

    func signHistory(assetID: UUID) throws -> ReportSignHistoryValue? {
        let authority = try buildAuthority()
        let matches = authority.assets.filter { $0.id == assetID }
        guard matches.count <= 1 else {
            throw ReportHistoryCoordinatorError.invalidAuthority
        }
        guard let asset = matches.first else { return nil }
        let sites = authority.sites.filter { $0.id == asset.siteID }
        guard sites.count == 1, let site = sites.first else {
            throw ReportHistoryCoordinatorError.invalidAuthority
        }
        let visits = authority.visits.filter { $0.assetID == assetID }
        guard let newestVisit = visits.first,
              newestVisit.siteID == site.id else {
            return nil
        }
        return ReportSignHistoryValue(
            assetID: assetID,
            siteLabel: newestVisit.siteLabel,
            assetLabel: newestVisit.assetLabel,
            visits: visits
        )
    }

    func comparison(
        stableRootID: UUID
    ) throws -> ReportHistoryComparisonValue? {
        let authority = try buildAuthority()
        return try comparison(stableRootID: stableRootID, authority: authority)
    }

    /// Builds authority once for a list instead of repeating the complete
    /// report/file projection once per rendered row. The current views retain
    /// their synchronous API until provisional-kernel reconciliation.
    func comparableStableRootIDs(
        _ stableRootIDs: [UUID]
    ) throws -> Set<UUID> {
        guard Set(stableRootIDs).count == stableRootIDs.count else {
            throw ReportHistoryCoordinatorError.invalidAuthority
        }
        let authority = try buildAuthority()
        var result = Set<UUID>()
        result.reserveCapacity(stableRootIDs.count)
        for stableRootID in stableRootIDs {
            try Task.checkCancellation()
            if try comparison(stableRootID: stableRootID, authority: authority) != nil {
                result.insert(stableRootID)
            }
        }
        return result
    }

    private func comparison(
        stableRootID: UUID,
        authority: ReportHistoryAuthority
    ) throws -> ReportHistoryComparisonValue? {
        guard !authority.comparisonGloballyBlocked else { return nil }
        let selected = authority.visits.filter {
            $0.stableRootID == stableRootID
        }
        guard selected.count <= 1 else {
            throw ReportHistoryCoordinatorError.invalidAuthority
        }
        guard let now = selected.first else { return nil }
        guard !authority.comparisonBlockedAssetIDs.contains(now.assetID) else {
            return nil
        }
        let signChronology = authority.comparisonChronology.filter {
            $0.assetID == now.assetID
        }
        guard signChronology.filter({
            $0.stableRootID == stableRootID
        }).count == 1,
              signChronology.filter({
                $0.completedAt == now.completedAt
              }).count == 1,
              let index = signChronology.firstIndex(where: {
                $0.stableRootID == stableRootID
              }), index + 1 < signChronology.count else {
            return nil
        }
        let predecessor = signChronology[index + 1]
        let priorVisits = authority.visits.filter {
            $0.stableRootID == predecessor.stableRootID
        }
        guard priorVisits.count == 1, let then = priorVisits.first,
              predecessor.completedAt < now.completedAt,
              signChronology.filter({
                $0.completedAt == predecessor.completedAt
              }).count == 1,
              hasComparisonEvidence(then),
              hasComparisonEvidence(now) else {
            return nil
        }
        return ReportHistoryComparisonValue(then: then, now: now)
    }

    private func buildAuthority() throws -> ReportHistoryAuthority {
        guard !modelContext.hasChanges else {
            throw ReportHistoryCoordinatorError.contextHasChanges
        }
        let sites = try modelContext.fetch(FetchDescriptor<Site>())
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())

        try requireUniqueIDs(sites.map(\.id))
        try requireUniqueIDs(assets.map(\.id))
        try requireUniqueIDs(records.map(\.id))
        try requireUniqueIDs(packets.map(\.id))
        try requireUniqueIDs(reports.map(\.id))
        try requireUniqueIDs(packets.map(\.stableRootID))
        try requireUniqueIDs(reports.map(\.sourceRecordID))

        guard sites.allSatisfy({
            $0.schemaVersion == 1 && isNonemptyTrimmed($0.label)
        }), assets.allSatisfy({
            $0.schemaVersion == 1 && isNonemptyTrimmed($0.label)
        }) else {
            throw ReportHistoryCoordinatorError.invalidAuthority
        }
        for asset in assets {
            guard sites.filter({ $0.id == asset.siteID }).count == 1 else {
                throw ReportHistoryCoordinatorError.invalidAuthority
            }
        }

        let livePackets = packets.filter {
            $0.currentRecordID != nil && $0.contentDeletedAt == nil
        }
        try requireUniqueIDs(livePackets.compactMap(\.currentRecordID))

        var visits: [ReportHistoryVisitValue] = []
        var comparisonChronology: [ReportHistoryChronologyValue] = []
        var comparisonBlockedAssetIDs = Set<UUID>()
        var comparisonGloballyBlocked = false
        for packet in livePackets {
            let projection = chronologyProjection(
                packet: packet,
                records: records
            )
            if let projection {
                comparisonChronology.append(projection)
            }
            if let visit = try visit(
                packet: packet,
                sites: sites,
                assets: assets,
                records: records,
                reports: reports
            ) {
                visits.append(visit)
            } else if let assetID = projection?.assetID
                        ?? uniqueCurrentAssetID(packet: packet, records: records) {
                comparisonBlockedAssetIDs.insert(assetID)
            } else {
                comparisonGloballyBlocked = true
            }
        }
        visits.sort(by: newestFirst)
        comparisonChronology.sort(by: chronologyNewestFirst)

        var siteOptionsByID: [UUID: ReportHistoryFilterOption] = [:]
        var assetOptionsByID: [UUID: ReportHistoryFilterOption] = [:]
        for visit in visits {
            if siteOptionsByID[visit.siteID] == nil {
                siteOptionsByID[visit.siteID] = ReportHistoryFilterOption(
                    id: visit.siteID,
                    label: visit.siteLabel
                )
            }
            if assetOptionsByID[visit.assetID] == nil {
                assetOptionsByID[visit.assetID] = ReportHistoryFilterOption(
                    id: visit.assetID,
                    label: visit.assetLabel
                )
            }
        }
        let siteOptions = siteOptionsByID.values.sorted(by: optionOrder)
        let assetOptions = assetOptionsByID.values.sorted(by: optionOrder)
        return ReportHistoryAuthority(
            visits: visits,
            comparisonChronology: comparisonChronology,
            comparisonBlockedAssetIDs: comparisonBlockedAssetIDs,
            comparisonGloballyBlocked: comparisonGloballyBlocked,
            siteOptions: siteOptions,
            assetOptions: assetOptions,
            sites: sites,
            assets: assets
        )
    }

    private func uniqueCurrentAssetID(
        packet: Packet,
        records: [WorkflowRecord]
    ) -> UUID? {
        guard let currentRecordID = packet.currentRecordID,
              let current = unique(records.filter { $0.id == currentRecordID }),
              current.packetID == packet.id else {
            return nil
        }
        return current.assetID
    }

    private func chronologyProjection(
        packet: Packet,
        records: [WorkflowRecord]
    ) -> ReportHistoryChronologyValue? {
        guard packet.schemaVersion == 1,
              packet.contentDeletedAt == nil,
              let currentRecordID = packet.currentRecordID,
              let current = unique(records.filter { $0.id == currentRecordID }),
              current.schemaVersion == 1,
              current.packetID == packet.id,
              current.state == WorkflowState.completed.rawValue else {
            return nil
        }
        let effectiveID = current.evidenceSourceRecordID ?? current.id
        guard let effective = unique(records.filter { $0.id == effectiveID }),
              effective.schemaVersion == 1,
              effective.packetID == packet.id,
              effective.assetID == current.assetID,
              effective.state == WorkflowState.completed.rawValue,
              let completedAt = effective.completedAt else {
            return nil
        }
        return ReportHistoryChronologyValue(
            stableRootID: packet.stableRootID,
            assetID: current.assetID,
            completedAt: completedAt
        )
    }

    private func visit(
        packet: Packet,
        sites: [Site],
        assets: [Asset],
        records: [WorkflowRecord],
        reports: [Report]
    ) throws -> ReportHistoryVisitValue? {
        guard packet.schemaVersion == 1,
              packet.contentDeletedAt == nil,
              let currentRecordID = packet.currentRecordID else {
            return nil
        }
        let currentRecords = records.filter { $0.id == currentRecordID }
        guard currentRecords.count == 1, let currentRecord = currentRecords.first,
              currentRecord.schemaVersion == 1,
              currentRecord.state == WorkflowState.completed.rawValue,
              currentRecord.packetID == packet.id else {
            return nil
        }
        let packetReports = reports.filter { $0.packetID == packet.id }
        let currentReports = packetReports.filter {
            $0.sourceRecordID == currentRecordID
        }
        guard currentReports.count == 1, let report = currentReports.first,
              validReplacementChain(
                endingAt: report,
                packetReports: packetReports,
                allReports: reports,
                records: records
              ) else {
            return nil
        }

        let validated: ValidatedReadyReportValue
        do {
            validated = try deliveryCoordinator.validatedReadyReport(id: report.id)
        } catch ReportDeliveryCoordinatorError.contextHasChanges {
            throw ReportHistoryCoordinatorError.contextHasChanges
        } catch {
            return nil
        }
        let snapshot = validated.snapshot
        let effective = records.filter {
            $0.id == snapshot.evidenceSourceRecordID
        }
        guard effective.count == 1, let effectiveRecord = effective.first,
              let completedAt = effectiveRecord.completedAt,
              effectiveRecord.assetID == currentRecord.assetID else {
            return nil
        }
        let matchingAssets = assets.filter { $0.id == currentRecord.assetID }
        guard matchingAssets.count == 1, let asset = matchingAssets.first else {
            return nil
        }
        let matchingSites = sites.filter { $0.id == asset.siteID }
        guard matchingSites.count == 1, let site = matchingSites.first else {
            return nil
        }
        guard snapshot.stableRootID == packet.stableRootID,
              snapshot.packetID == packet.id,
              snapshot.reportID == report.id,
              snapshot.sourceRecordID == currentRecordID else {
            return nil
        }

        let currentEvidence = validated.evidence.filter {
            $0.snapshot.recordID == snapshot.evidenceSourceRecordID
        }.map {
            ReportHistoryEvidenceValue(
                evidenceID: $0.snapshot.evidenceID,
                purposeKey: $0.snapshot.purposeKey,
                purposeDisplay: $0.snapshot.purposeDisplay,
                originalData: $0.originalData,
                thumbnailData: $0.thumbnailData
            )
        }
        return ReportHistoryVisitValue(
            stableRootID: packet.stableRootID,
            packetID: packet.id,
            reportID: report.id,
            siteID: site.id,
            assetID: asset.id,
            completedAt: completedAt,
            siteLabel: snapshot.site.label,
            assetLabel: snapshot.asset.label,
            stage: snapshot.display.stage,
            outcome: snapshot.display.outcome,
            localDate: snapshot.timeContext.localDate,
            localTime: snapshot.timeContext.localTime,
            evidence: currentEvidence
        )
    }

    private func validReplacementChain(
        endingAt target: Report,
        packetReports: [Report],
        allReports: [Report],
        records: [WorkflowRecord]
    ) -> Bool {
        guard !packetReports.isEmpty,
              packetReports.allSatisfy({ $0.schemaVersion == 1 }),
              allReports.filter({ $0.replacesReportID == target.id }).isEmpty else {
            return false
        }
        var visited = Set<UUID>()
        var current = target
        while visited.insert(current.id).inserted {
            let sourceMatches = records.filter { $0.id == current.sourceRecordID }
            guard allReports.filter({
                    $0.sourceRecordID == current.sourceRecordID
                  }).count == 1,
                  sourceMatches.count == 1, let source = sourceMatches.first,
                  source.packetID == current.packetID else {
                return false
            }
            guard let priorID = current.replacesReportID else {
                return source.revisionKind == WorkflowRevisionKind.original.rawValue
                    && source.revisesRecordID == nil
                    && visited.count == packetReports.count
            }
            let priorMatches = packetReports.filter { $0.id == priorID }
            guard priorMatches.count == 1, let prior = priorMatches.first,
                  allReports.filter({ $0.replacesReportID == prior.id }).count == 1,
                  source.revisionKind
                    == WorkflowRevisionKind.clericalCorrection.rawValue,
                  source.revisesRecordID == prior.sourceRecordID else {
                return false
            }
            current = prior
        }
        return false
    }

    private func hasComparisonEvidence(_ visit: ReportHistoryVisitValue) -> Bool {
        let purposes = visit.evidence.map(\.purposeKey)
        return purposes.filter { $0 == "wide_context" }.count == 1
            && purposes.filter { $0 == "close_detail" }.count == 1
            && Set(purposes).count == purposes.count
    }

    private func requireUniqueIDs(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else {
            throw ReportHistoryCoordinatorError.invalidAuthority
        }
    }

    private func isNonemptyTrimmed(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func newestFirst(
        _ lhs: ReportHistoryVisitValue,
        _ rhs: ReportHistoryVisitValue
    ) -> Bool {
        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt > rhs.completedAt
        }
        return canonicalID(lhs.stableRootID) < canonicalID(rhs.stableRootID)
    }

    private func chronologyNewestFirst(
        _ lhs: ReportHistoryChronologyValue,
        _ rhs: ReportHistoryChronologyValue
    ) -> Bool {
        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt > rhs.completedAt
        }
        return canonicalID(lhs.stableRootID) < canonicalID(rhs.stableRootID)
    }

    private func optionOrder(
        _ lhs: ReportHistoryFilterOption,
        _ rhs: ReportHistoryFilterOption
    ) -> Bool {
        let comparison = lhs.label.compare(
            rhs.label,
            options: [.caseInsensitive, .literal],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return canonicalID(lhs.id) < canonicalID(rhs.id)
    }

    private func canonicalID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private func unique<T>(_ values: [T]) -> T? {
        values.count == 1 ? values[0] : nil
    }
}

private struct ReportHistoryAuthority {
    let visits: [ReportHistoryVisitValue]
    let comparisonChronology: [ReportHistoryChronologyValue]
    let comparisonBlockedAssetIDs: Set<UUID>
    let comparisonGloballyBlocked: Bool
    let siteOptions: [ReportHistoryFilterOption]
    let assetOptions: [ReportHistoryFilterOption]
    let sites: [Site]
    let assets: [Asset]
}

private struct ReportHistoryChronologyValue {
    let stableRootID: UUID
    let assetID: UUID
    let completedAt: Date
}
