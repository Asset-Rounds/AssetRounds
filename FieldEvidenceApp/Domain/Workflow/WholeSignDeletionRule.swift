import Foundation

struct DeletionSitePayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
}

struct DeletionAssetPayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let siteID: UUID
}

struct DeletionEvidencePayloadV1: Codable, Equatable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let recordID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
}

struct WholeSignDeletionRuleInput: Codable, Equatable, Sendable {
    let assetID: UUID
    let deletionID: UUID
    let deletedAt: Date
    let generationID: UUID
    let sites: [DeletionSitePayloadV1]
    let assets: [DeletionAssetPayloadV1]
    let records: [WorkflowRecordPayloadV1]
    let evidence: [DeletionEvidencePayloadV1]
    let issues: [IssuePayloadV1]
    let packets: [PacketPayloadV1]
    let reports: [ReportPayloadV1]
}

struct WholeSignDeletionPlan: Codable, Equatable, Sendable {
    let assetID: UUID
    let evidenceIDs: [UUID]
    let intent: DeletionIntentV1
    let issueIDs: [UUID]
    let packetIDsToDelete: [UUID]
    let reportIDs: [UUID]
    let siteIDToDelete: UUID?
    let workflowRecordIDs: [UUID]
}

enum WholeSignDeletionRuleError: Error, Equatable {
    case invalidGraph
}

enum WholeSignDeletionRule {
    static func makePlan(
        _ input: WholeSignDeletionRuleInput
    ) throws -> WholeSignDeletionPlan {
        guard validGlobalGraph(input),
              let asset = only(input.assets, where: { $0.id == input.assetID }),
              only(input.sites, where: { $0.id == asset.siteID }) != nil else {
            throw WholeSignDeletionRuleError.invalidGraph
        }

        let selectedRecords = input.records.filter { $0.assetID == asset.id }
        let recordIDs = Set(selectedRecords.map(\.id))
        let selectedEvidence = input.evidence.filter { recordIDs.contains($0.recordID) }
        let selectedIssues = input.issues.filter { $0.assetID == asset.id }
        let selectedPacketIDs = Set(input.packets.compactMap { packet in
            packetOwner(packet, records: input.records, reports: input.reports) == asset.id
                ? packet.id
                : nil
        })
        let selectedPackets = input.packets.filter { selectedPacketIDs.contains($0.id) }
        let selectedReports = input.reports.filter { selectedPacketIDs.contains($0.packetID) }

        guard selectedEvidence.count == input.evidence.filter({
                  recordIDs.contains($0.recordID)
              }).count,
              selectedIssues.allSatisfy({ recordIDs.contains($0.openedByRecordID) }),
              selectedIssues.allSatisfy({ issue in
                  issue.resolvedByRecordID.map(recordIDs.contains) ?? true
              }),
              selectedReports.allSatisfy({ recordIDs.contains($0.sourceRecordID) }),
              selectedRecords.allSatisfy({ record in
                  record.packetID.map(selectedPacketIDs.contains) ?? true
              }) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }

        let tombstones = selectedPackets
            .filter(\.evaluationCounted)
            .map { packet in
                PacketPayloadV1(
                    id: packet.id,
                    schemaVersion: packet.schemaVersion,
                    stableRootID: packet.stableRootID,
                    currentRecordID: nil,
                    evaluationCounted: true,
                    contentDeletedAt: input.deletedAt,
                    createdAt: packet.createdAt
                )
            }
            .sorted { canonicalID($0.id) < canonicalID($1.id) }
        let paths = (selectedEvidence.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath]
        } + selectedReports.flatMap { report in
            [report.snapshotRelativePath, report.pdfRelativePath].compactMap { $0 }
        }).sorted()
        guard Set(paths).count == paths.count,
              paths.allSatisfy(DeletionIntentEncoderV1.validRelativePath),
              tombstones.allSatisfy({ $0.contentDeletedAt == input.deletedAt }) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }

        let intent = DeletionIntentV1(
            assetID: asset.id,
            countedPacketTombstones: tombstones,
            deletionID: input.deletionID,
            generationID: input.generationID,
            phase: .prepared,
            relativePaths: paths,
            schemaVersion: 1
        )
        guard DeletionIntentEncoderV1.valid(intent) else {
            throw WholeSignDeletionRuleError.invalidGraph
        }
        let deletesSite = input.assets.filter { $0.siteID == asset.siteID }.count == 1
        return WholeSignDeletionPlan(
            assetID: asset.id,
            evidenceIDs: sortedIDs(selectedEvidence.map(\.id)),
            intent: intent,
            issueIDs: sortedIDs(selectedIssues.map(\.id)),
            packetIDsToDelete: sortedIDs(
                selectedPackets.filter { !$0.evaluationCounted }.map(\.id)
            ),
            reportIDs: sortedIDs(selectedReports.map(\.id)),
            siteIDToDelete: deletesSite ? asset.siteID : nil,
            workflowRecordIDs: sortedIDs(selectedRecords.map(\.id))
        )
    }

    private static func validGlobalGraph(_ input: WholeSignDeletionRuleInput) -> Bool {
        guard !input.sites.isEmpty,
              !input.assets.isEmpty,
              unique(input.sites.map(\.id)),
              unique(input.assets.map(\.id)),
              unique(input.records.map(\.id)),
              unique(input.records.compactMap(\.revisesRecordID)),
              unique(input.evidence.map(\.id)),
              unique(input.issues.map(\.id)),
              unique(input.issues.map(\.openedByRecordID)),
              unique(input.packets.map(\.id)),
              unique(input.packets.map(\.stableRootID)),
              unique(input.packets.compactMap(\.currentRecordID)),
              unique(input.reports.map(\.id)),
              unique(input.reports.map(\.sourceRecordID)),
              unique(input.reports.compactMap(\.replacesReportID)),
              unique(input.records.compactMap(\.finalizationMutationID)),
              uniqueAcrossAuthorities(input),
              input.sites.allSatisfy({ site in
                  site.schemaVersion == 1
                    && input.assets.contains(where: { $0.siteID == site.id })
              }),
              input.assets.allSatisfy({ asset in
                  asset.schemaVersion == 1
                    && exactlyOne(input.sites, where: { $0.id == asset.siteID })
              }),
              validRecords(input),
              validEvidence(input),
              validIssues(input),
              validPacketsAndReports(input) else {
            return false
        }
        return true
    }

    private static func validRecords(_ input: WholeSignDeletionRuleInput) -> Bool {
        let assetsByID = Dictionary(uniqueKeysWithValues: input.assets.map { ($0.id, $0) })
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        let issuesByID = Dictionary(uniqueKeysWithValues: input.issues.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: input.packets.map { ($0.id, $0) })
        guard input.records.allSatisfy({ record in
            guard record.schemaVersion == 1,
                  assetsByID[record.assetID] != nil,
                  let revisionKind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  WorkflowStage(rawValue: record.stage) != nil,
                  let state = WorkflowState(rawValue: record.state),
                  let revisionRoot = recordsByID[record.recordRevisionRootID],
                  revisionRoot.assetID == record.assetID,
                  revisionRoot.revisionKind == WorkflowRevisionKind.original.rawValue,
                  revisionRoot.recordRevisionRootID == revisionRoot.id,
                  record.parentRecordID.map({
                      recordsByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.issueID.map({
                      issuesByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.packetID.map({ packetsByID[$0] != nil }) ?? true else {
                return false
            }
            switch state {
            case .draft:
                guard record.completedAt == nil else { return false }
            case .completed:
                guard record.completedAt.map({ $0 >= record.startedAt }) == true else {
                    return false
                }
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
                return revised.assetID == record.assetID
                    && revised.recordRevisionRootID == record.recordRevisionRootID
                    && source.assetID == record.assetID
            }
        }) else {
            return false
        }
        let parentEdges = Dictionary(uniqueKeysWithValues: input.records.map {
            ($0.id, $0.parentRecordID)
        })
        let revisionEdges = Dictionary(uniqueKeysWithValues: input.records.map {
            ($0.id, $0.revisesRecordID)
        })
        let evidenceSourceEdges = Dictionary(uniqueKeysWithValues: input.records.map {
            ($0.id, $0.evidenceSourceRecordID)
        })
        return acyclic(parentEdges)
            && acyclic(revisionEdges)
            && acyclic(evidenceSourceEdges)
    }

    private static func validEvidence(_ input: WholeSignDeletionRuleInput) -> Bool {
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        return input.evidence.allSatisfy { value in
            let id = canonicalID(value.id)
            return value.schemaVersion == 1
                && recordsByID[value.recordID] != nil
                && !value.purposeKey.isEmpty
                && value.mimeType == MediaContractV1.durableMIMEType
                && value.relativePath == "evidence/\(id)/original.jpg"
                && value.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg"
                && value.byteCount > 0
                && value.thumbnailByteCount > 0
                && isLowercaseSHA256(value.sha256)
                && isLowercaseSHA256(value.thumbnailSHA256)
        }
    }

    private static func validIssues(_ input: WholeSignDeletionRuleInput) -> Bool {
        let assetsByID = Dictionary(uniqueKeysWithValues: input.assets.map { ($0.id, $0) })
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        return input.issues.allSatisfy { issue in
            issue.schemaVersion == 1
                && assetsByID[issue.assetID] != nil
                && recordsByID[issue.openedByRecordID]?.assetID == issue.assetID
                && (issue.resolvedByRecordID.map {
                    recordsByID[$0]?.assetID == issue.assetID
                } ?? true)
                && !issue.labelKey.isEmpty
                && !issue.labelDisplaySnapshot.isEmpty
                && IssueStatus(rawValue: issue.status) != nil
                && issue.updatedAt >= issue.createdAt
        }
    }

    private static func validPacketsAndReports(
        _ input: WholeSignDeletionRuleInput
    ) -> Bool {
        let recordsByID = Dictionary(uniqueKeysWithValues: input.records.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: input.packets.map { ($0.id, $0) })
        let reportsByID = Dictionary(uniqueKeysWithValues: input.reports.map { ($0.id, $0) })
        guard input.packets.allSatisfy({ packet in
            guard packet.schemaVersion == 1,
                  packet.createdAt <= (packet.contentDeletedAt ?? .distantFuture) else {
                return false
            }
            if let currentRecordID = packet.currentRecordID {
                return packet.contentDeletedAt == nil
                    && recordsByID[currentRecordID]?.packetID == packet.id
                    && packetOwner(packet, records: input.records, reports: input.reports) != nil
            }
            return packet.evaluationCounted
                && packet.contentDeletedAt != nil
                && input.records.allSatisfy { $0.packetID != packet.id }
                && input.reports.allSatisfy { $0.packetID != packet.id }
        }), input.reports.allSatisfy({ report in
            guard report.schemaVersion == 1,
                  let packet = packetsByID[report.packetID],
                  let source = recordsByID[report.sourceRecordID],
                  packet.currentRecordID != nil,
                  packetOwner(packet, records: input.records, reports: input.reports)
                    == source.assetID,
                  report.snapshotSchemaVersion == 1,
                  report.snapshotRelativePath
                    == "snapshots/\(canonicalID(report.id)).json",
                  isLowercaseSHA256(report.snapshotSHA256),
                  let state = ReportPDFState(rawValue: report.pdfState) else {
                return false
            }
            switch state {
            case .ready:
                return report.pdfRelativePath == "pdfs/\(canonicalID(report.id)).pdf"
                    && report.pdfSHA256.map(isLowercaseSHA256) == true
            case .pending, .failed:
                return report.pdfRelativePath == nil && report.pdfSHA256 == nil
            }
        }) else {
            return false
        }
        let replacementEdges = Dictionary(uniqueKeysWithValues: input.reports.map {
            ($0.id, $0.replacesReportID)
        })
        return acyclic(replacementEdges) && input.reports.allSatisfy { report in
            report.replacesReportID.map { replacedID in
                guard let replaced = reportsByID[replacedID] else { return false }
                return replaced.packetID == report.packetID
                    && replaced.createdAt <= report.createdAt
            } ?? true
        }
    }

    private static func packetOwner(
        _ packet: PacketPayloadV1,
        records: [WorkflowRecordPayloadV1],
        reports: [ReportPayloadV1]
    ) -> UUID? {
        var owners = Set<UUID>()
        if let currentRecordID = packet.currentRecordID,
           let record = records.first(where: { $0.id == currentRecordID }) {
            owners.insert(record.assetID)
        }
        for record in records where record.packetID == packet.id {
            owners.insert(record.assetID)
        }
        for report in reports where report.packetID == packet.id {
            if let record = records.first(where: { $0.id == report.sourceRecordID }) {
                owners.insert(record.assetID)
            }
        }
        return owners.count == 1 ? owners.first : nil
    }

    private static func uniqueAcrossAuthorities(
        _ input: WholeSignDeletionRuleInput
    ) -> Bool {
        let values = input.sites.map(\.id)
            + input.assets.map(\.id)
            + input.records.map(\.id)
            + input.evidence.map(\.id)
            + input.issues.map(\.id)
            + input.packets.map(\.id)
            + input.packets.map(\.stableRootID)
            + input.reports.map(\.id)
            + input.records.compactMap(\.finalizationMutationID)
            + [input.deletionID, input.generationID]
        return unique(values)
    }

    private static func acyclic(_ edges: [UUID: UUID?]) -> Bool {
        for start in edges.keys {
            var seen = Set<UUID>()
            var current: UUID? = start
            while let value = current {
                guard seen.insert(value).inserted else { return false }
                current = edges[value] ?? nil
            }
        }
        return true
    }

    private static func exactlyOne<T>(
        _ values: [T],
        where predicate: (T) -> Bool
    ) -> Bool {
        values.filter(predicate).count == 1
    }

    private static func only<T>(
        _ values: [T],
        where predicate: (T) -> Bool
    ) -> T? {
        let matches = values.filter(predicate)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private static func sortedIDs(_ values: [UUID]) -> [UUID] {
        values.sorted { canonicalID($0) < canonicalID($1) }
    }

    private static func canonicalID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}
