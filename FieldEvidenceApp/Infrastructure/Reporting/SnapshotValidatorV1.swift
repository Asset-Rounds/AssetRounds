import CryptoKit
import Foundation
import SwiftData

enum SnapshotValidationErrorV1: Error, Equatable {
    case invalidAuthority
}

/// Computes the one stable integrity finding used when the immutable snapshot
/// bytes and their report authority disagree.  The validator still fails
/// closed; this helper makes the diagnostic classification deterministic for
/// non-production callers without changing the legacy error surface.
enum SnapshotIntegrityDiagnosticsV1 {
    static func snapshotReportDivergenceFindings(
        snapshotSHA256: String,
        reportSHA256: String
    ) -> [IntegrityFindingV1] {
        guard snapshotSHA256 != reportSHA256,
              let finding = try? IntegrityFindingV1(
                  kind: .snapshotReportDivergence,
                  reasonCode: "snapshot_report_divergence"
              ) else {
            return []
        }
        return [finding]
    }
}

@MainActor
enum ReportingPackageLifecycleRouteV1 {
    case live(
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        profile: WorkspacePackageLifecycleProfileV1
    )
    case expiringCompatibility(
        profile: WorkspacePackageLifecycleProfileV1,
        posture: String
    )

    var profile: WorkspacePackageLifecycleProfileV1 {
        switch self {
        case .live(_, let profile), .expiringCompatibility(let profile, _):
            profile
        }
    }

    func validate(generationRootURL: URL) throws {
        switch self {
        case .live(let dependencies, let profile):
            guard dependencies.generationRootURL.standardizedFileURL
                    == generationRootURL.standardizedFileURL,
                  dependencies.generationID.uuidString.lowercased()
                    == generationRootURL.standardizedFileURL.lastPathComponent,
                  try dependencies.profileRegistry.resolve(profile.release) == profile else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        case .expiringCompatibility(let profile, let posture):
            guard posture == WorkspacePackageLifecycleCompatibilityV1.expiration,
                  profile.release.matches(profile.package) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
    }
}

struct ValidatedReportSnapshotV1: Sendable {
    let snapshot: ReportSnapshotV1
    let snapshotSHA256: String
    let referencedImageByteCount: Int64
    let currentEvidencePurposes: [SignPack.EvidencePurpose]

    fileprivate let evidenceBytes: [UUID: ValidatedEvidenceBytesV1]
    private let currentOriginalIDs: Set<UUID>
    private let historyThumbnailIDs: Set<UUID>

    fileprivate init(
        snapshot: ReportSnapshotV1,
        snapshotSHA256: String,
        referencedImageByteCount: Int64,
        currentEvidencePurposes: [SignPack.EvidencePurpose],
        evidenceBytes: [UUID: ValidatedEvidenceBytesV1],
        currentOriginalIDs: Set<UUID>,
        historyThumbnailIDs: Set<UUID>
    ) {
        self.snapshot = snapshot
        self.snapshotSHA256 = snapshotSHA256
        self.referencedImageByteCount = referencedImageByteCount
        self.currentEvidencePurposes = currentEvidencePurposes
        self.evidenceBytes = evidenceBytes
        self.currentOriginalIDs = currentOriginalIDs
        self.historyThumbnailIDs = historyThumbnailIDs
    }

    func originalJPEG(for evidenceID: UUID) -> Data? {
        guard currentOriginalIDs.contains(evidenceID) else { return nil }
        return evidenceBytes[evidenceID]?.originalJPEG
    }

    func thumbnailJPEG(for evidenceID: UUID) -> Data? {
        guard historyThumbnailIDs.contains(evidenceID) else { return nil }
        return evidenceBytes[evidenceID]?.thumbnailJPEG
    }

    var requirementExplanations: [RequirementExplanationItemV1] {
        snapshot.requirementAssurance.map {
            RequirementExplanationProjectionV1.project($0.evaluations)
        } ?? []
    }
}

fileprivate struct ValidatedEvidenceBytesV1: Sendable {
    let originalJPEG: Data
    let thumbnailJPEG: Data
}

@MainActor
struct SnapshotValidatorV1 {
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let resolvedGenerationRootURL: URL
    private let fileManager: FileManager
    private let signPack: SignPack
    private let lifecycleProfile: WorkspacePackageLifecycleProfileV1
    private let lifecycleRoute: ReportingPackageLifecycleRouteV1
    private let mediaValidator = MediaNormalizerV1()

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1
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
            )
        )
    }

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager = .default,
        lifecycleProfile: WorkspacePackageLifecycleProfileV1,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    ) throws {
        try self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            fileManager: fileManager,
            lifecycleRoute: .live(
                dependencies: lifecycleDependencies,
                profile: lifecycleProfile
            )
        )
    }

    private init(
        modelContext: ModelContext,
        generationRootURL: URL,
        fileManager: FileManager,
        lifecycleRoute: ReportingPackageLifecycleRouteV1
    ) throws {
        let root = generationRootURL.standardizedFileURL
        try lifecycleRoute.validate(generationRootURL: root)
        let lifecycleProfile = lifecycleRoute.profile
        guard generationRootURL.isFileURL,
              !root.path.isEmpty,
              !Self.isSymbolicLink(root, fileManager: fileManager),
              try Self.itemType(at: root, fileManager: fileManager) == .typeDirectory,
              lifecycleProfile.release.matches(lifecycleProfile.package) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        self.modelContext = modelContext
        self.generationRootURL = root
        self.resolvedGenerationRootURL = root.resolvingSymlinksInPath()
        self.fileManager = fileManager
        self.signPack = lifecycleProfile.package
        self.lifecycleProfile = lifecycleProfile
        self.lifecycleRoute = lifecycleRoute
    }

    func validate(report: Report) throws -> ValidatedReportSnapshotV1 {
        do {
            return try validateAuthority(report: report)
        } catch let error as SnapshotValidationErrorV1 {
            throw error
        } catch {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateAuthority(report: Report) throws -> ValidatedReportSnapshotV1 {
        let reportID = canonicalID(report.id)
        let expectedSnapshotPath = "snapshots/\(reportID).json"
        guard report.schemaVersion == 1,
              (1...3).contains(report.snapshotSchemaVersion),
              report.snapshotRelativePath == expectedSnapshotPath,
              isLowercaseSHA256(report.snapshotSHA256),
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }

        let snapshotURL = generationRootURL
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("\(reportID).json", isDirectory: false)
        let snapshotData = try readRegularNonsymlinkFile(
            snapshotURL,
            expectedRelativePath: expectedSnapshotPath
        )
        let encodedDigest = Self.sha256(snapshotData)
        guard SnapshotIntegrityDiagnosticsV1.snapshotReportDivergenceFindings(
            snapshotSHA256: encodedDigest,
            reportSHA256: report.snapshotSHA256
        ).isEmpty else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        let snapshot = try ReportSnapshotEncoderV1().decode(snapshotData)
        try validateRequirementAssurance(snapshot)
        try validateAuthorityCriterion(snapshot)
        guard try ReportSnapshotEncoderV1().encode(snapshot).data == snapshotData,
              snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion,
              snapshot.reportID == report.id,
              snapshot.packetID == report.packetID,
              snapshot.sourceRecordID == report.sourceRecordID,
              snapshot.pdfTemplate == lifecycleProfile.pdfTemplate,
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
              packet.currentRecordID == report.sourceRecordID,
              packet.evaluationCounted,
              packet.contentDeletedAt == nil,
              packets.filter({ $0.stableRootID == packet.stableRootID }).count == 1,
              packets.filter({ $0.currentRecordID == report.sourceRecordID }).count == 1 else {
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
        try validateWorkspaceScope(report: report, source: source)
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
            try validateHistory(
                history,
                against: record,
                snapshotSchemaVersion: snapshot.snapshotSchemaVersion
            )
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

        var validatedBytes: [UUID: ValidatedEvidenceBytesV1] = [:]
        for (value, row) in zip(snapshot.evidence, orderedRows) {
            guard validateEvidenceSnapshot(value, row: row) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            let id = canonicalID(row.id)
            let original = try readRegularNonsymlinkFile(
                generationRootURL
                    .appendingPathComponent("evidence", isDirectory: true)
                    .appendingPathComponent(id, isDirectory: true)
                    .appendingPathComponent("original.jpg", isDirectory: false),
                expectedRelativePath: "evidence/\(id)/original.jpg"
            )
            let thumbnail = try readRegularNonsymlinkFile(
                generationRootURL
                    .appendingPathComponent("evidence", isDirectory: true)
                    .appendingPathComponent(id, isDirectory: true)
                    .appendingPathComponent("thumbnail.jpg", isDirectory: false),
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
                ValidatedEvidenceBytesV1(
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

        return ValidatedReportSnapshotV1(
            snapshot: snapshot,
            snapshotSHA256: encodedDigest,
            referencedImageByteCount: referencedByteCount,
            currentEvidencePurposes: try currentEvidencePurposes(),
            evidenceBytes: validatedBytes,
            currentOriginalIDs: Set(currentRows.map(\.id)),
            historyThumbnailIDs: historyEvidenceIDs
        )
    }

    private func validateRequirementAssurance(
        _ snapshot: ReportSnapshotV1
    ) throws {
        guard let assurance = snapshot.requirementAssurance else { return }
        do {
            try assurance.validate()
        } catch {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateAuthorityCriterion(_ snapshot: ReportSnapshotV1) throws {
        guard let authority = snapshot.authorityCriterion else { return }
        do {
            try authority.validate()
            if case .live(let dependencies, _) = lifecycleRoute,
               authority.workspaceID.rawValue != dependencies.workspaceID {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        } catch {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateWorkspaceScope(report: Report, source: WorkflowRecord) throws {
        guard case .live(let lifecycleDependencies, _) = lifecycleRoute else { return }
        let identities = [
            try WorkspaceEntityIdentityV1(kind: .report, id: report.id),
            try WorkspaceEntityIdentityV1(kind: .asset, id: source.assetID),
        ]
        let request = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: lifecycleDependencies.workspaceID,
            generationID: lifecycleDependencies.generationID,
            operation: .reportPDF,
            identities: identities
        )
        let result = try lifecycleDependencies.writer.query(request)
        guard result.workspaceID == lifecycleDependencies.workspaceID,
              result.generationID == lifecycleDependencies.generationID,
              result.operation == .reportPDF,
              result.revision.workspaceID == lifecycleDependencies.workspaceID,
              result.revision.generationID == lifecycleDependencies.generationID,
              Set(result.existingIdentities) == Set(identities),
              result.packageBindings.count == 1,
              let binding = result.packageBindings.first,
              binding.assetID == source.assetID,
              binding.packageID == lifecycleProfile.release.packageID,
              binding.packageSchemaVersion == lifecycleProfile.release.schemaVersion,
              binding.packageContentVersion == lifecycleProfile.release.contentVersion else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateFrozenSourceFields(
        snapshot: ReportSnapshotV1,
        source: WorkflowRecord
    ) throws {
        let expectedCNV = frozenCNV(source)
        let companion = try ObservationAndTimeRowStoreV1.requireRow(
            recordID: source.id, in: modelContext
        )
        let expectedBasis = try companion.observationBasisV1()
        let expectedTemporal = try companion.temporalContextV1()
        let observationAndTimeMatches: Bool
        if snapshot.snapshotSchemaVersion == 1 {
            // Released v1 snapshots intentionally remain byte-identical after
            // a store migration enriches their source rows.
            observationAndTimeMatches = snapshot.observationBasis == nil
                && snapshot.temporalContext == nil
        } else {
            observationAndTimeMatches = snapshot.observationBasis == expectedBasis
                && snapshot.temporalContext == expectedTemporal
        }
        let requiredAcknowledgements = signPack.acknowledgements.filter {
            lifecycleProfile.requiredAcknowledgementKeys.contains($0.key)
        }
        guard let sourceAcknowledgements = acknowledgementSourceValues(source),
              requiredAcknowledgements.map(\.key)
                == lifecycleProfile.requiredAcknowledgementKeys,
              snapshot.couldNotVerify == expectedCNV,
              observationAndTimeMatches,
              canonicalOptionalDateEqual(
                snapshot.timeContext.observedAtUTC,
                source.observedAtUTC
              ),
              snapshot.timeContext.timeZoneID == source.timeZoneID,
              snapshot.timeContext.utcOffsetMinutes == source.utcOffsetMinutes,
              snapshot.timeContext.localDate == source.localDate,
              snapshot.timeContext.localTime == source.localTime,
              snapshot.acknowledgements.count == requiredAcknowledgements.count,
              sourceAcknowledgements.count == requiredAcknowledgements.count,
              snapshot.acknowledgements.indices.allSatisfy({ index in
                  let snapshotValue = snapshot.acknowledgements[index]
                  let sourceValue = sourceAcknowledgements[index]
                  let packageValue = requiredAcknowledgements[index]
                  return snapshotValue.key == sourceValue.key
                      && snapshotValue.copy == sourceValue.copy
                      && snapshotValue.version == sourceValue.version
                      && snapshotValue.accepted == sourceValue.accepted
                      && snapshotValue.key == packageValue.key
                      && snapshotValue.copy == packageValue.copy
                      && snapshotValue.version == packageValue.version
              }) else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func acknowledgementSourceValues(
        _ record: WorkflowRecord
    ) -> [(key: String, copy: String, version: String, accepted: Bool)]? {
        let groups: [(String?, String?, String?, Bool?)] = [
            (
                record.afterDarkAcknowledgementKey,
                record.afterDarkAcknowledgementCopy,
                record.afterDarkAcknowledgementVersion,
                record.afterDarkAcknowledgementAccepted
            ),
            (
                record.safePositionAcknowledgementKey,
                record.safePositionAcknowledgementCopy,
                record.safePositionAcknowledgementVersion,
                record.safePositionAcknowledgementAccepted
            ),
        ]
        var result: [(key: String, copy: String, version: String, accepted: Bool)] = []
        for group in groups {
            if group.0 == nil, group.1 == nil, group.2 == nil, group.3 == nil { continue }
            guard let key = group.0, let copy = group.1,
                  let version = group.2, let accepted = group.3 else { return nil }
            result.append((key, copy, version, accepted))
        }
        return result
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
              record.pdfTemplateID == lifecycleProfile.pdfTemplate.id,
              record.pdfTemplateVersion == lifecycleProfile.pdfTemplate.version,
              validOptionalTrimmed(record.note, maximum: 1_000) else {
            return false
        }
        guard validObservationAndTime(record) else { return false }

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
        guard outcomeRole(for: record) == .couldNotVerify
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

        let hasRequiredAcknowledgements = acknowledgementSourceValues(record).map {
            $0.map(\.key) == lifecycleProfile.requiredAcknowledgementKeys
        } ?? false
        let allRequiredAcknowledgementsAccepted = acknowledgementSourceValues(record)?.allSatisfy {
            $0.accepted
        } ?? false
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
            guard let stage = try? lifecycleProfile.stage(record.stage),
                  let outcomeKey = record.outcomeKey,
                  let role = outcomeRole(for: record) else { return false }
            return record.parentRecordID == nil
                && record.packetID != nil
                && stage.outcomeKeys.contains(outcomeKey)
                && ((role == .findingObserved) == (record.issueID != nil))
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && hasRequiredAcknowledgements
                && hasAllTimeFields
                && allRequiredAcknowledgementsAccepted

        case WorkflowStage.recheck.rawValue:
            guard let stage = try? lifecycleProfile.stage(record.stage),
                  let outcomeKey = record.outcomeKey else { return false }
            return record.parentRecordID != nil
                && record.issueID != nil
                && record.packetID != nil
                && stage.outcomeKeys.contains(outcomeKey)
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && hasRequiredAcknowledgements
                && hasAllTimeFields
                && allRequiredAcknowledgementsAccepted

        case WorkflowStage.work.rawValue:
            guard let stage = try? lifecycleProfile.stage(record.stage),
                  let outcomeKey = record.outcomeKey,
                  stage.outcomes.contains(where: {
                      $0.key == outcomeKey && $0.role == .workRecorded
                  }) else { return false }
            return record.parentRecordID != nil
                && record.issueID != nil
                && record.packetID == nil
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

    private func outcomeRole(
        for record: WorkflowRecord
    ) -> WorkspacePackageOutcomeRoleV1? {
        guard let outcomeKey = record.outcomeKey,
              let stage = try? lifecycleProfile.stage(record.stage),
              let outcome = stage.outcomes.first(where: { $0.key == outcomeKey }) else {
            return nil
        }
        return outcome.role
    }

    private func currentEvidencePurposes() throws -> [SignPack.EvidencePurpose] {
        let keys = lifecycleProfile.evidencePurposeKeys(for: .captureRequired)
        let values = keys.compactMap { key in
            signPack.evidencePurposes.first(where: { $0.key == key })
        }
        guard values.count == keys.count else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        return values
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
        let requiredKeys = lifecycleProfile.evidencePurposeKeys(for: .captureRequired)
        let supplementaryKeys = lifecycleProfile.evidencePurposeKeys(for: .captureSupplementary)
        let allowedKeys = requiredKeys + supplementaryKeys
        if outcomeRole(for: effective) == .couldNotVerify {
            guard rows.count <= allowedKeys.count,
                  Set(keys).count == keys.count,
                  keys.allSatisfy(allowedKeys.contains) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        } else {
            guard keys == requiredKeys else {
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
            let allowedKeys = lifecycleProfile.evidencePurposeKeys(for: .workSupplementary)
            guard rows.count <= allowedKeys.count,
                  Set(keys).count == keys.count,
                  keys.allSatisfy(allowedKeys.contains) else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        case WorkflowStage.check.rawValue, WorkflowStage.recheck.rawValue:
            let requiredKeys = lifecycleProfile.evidencePurposeKeys(for: .captureRequired)
            let supplementaryKeys = lifecycleProfile.evidencePurposeKeys(for: .captureSupplementary)
            let allowedKeys = requiredKeys + supplementaryKeys
            if outcomeRole(for: record) == .couldNotVerify {
                guard rows.count <= allowedKeys.count,
                      Set(keys).count == keys.count,
                      keys.allSatisfy(allowedKeys.contains) else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            } else {
                guard keys == requiredKeys else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            }
        default:
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validateHistory(
        _ value: HistoryEntrySnapshotV1,
        against record: WorkflowRecord,
        snapshotSchemaVersion: Int
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
        let companion = try ObservationAndTimeRowStoreV1.requireRow(
            recordID: record.id, in: modelContext
        )
        let expectedBasis = try companion.observationBasisV1()
        let expectedTemporal = try companion.temporalContextV1()
        let observationAndTimeMatches: Bool
        if snapshotSchemaVersion == 1 {
            observationAndTimeMatches = value.observationBasis == nil
                && value.temporalContext == nil
        } else {
            observationAndTimeMatches = value.observationBasis == expectedBasis
                && value.temporalContext == expectedTemporal
        }
        guard value.couldNotVerify == expectedCNV,
              observationAndTimeMatches else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
    }

    private func validObservationAndTime(_ record: WorkflowRecord) -> Bool {
        do {
            let companion = try ObservationAndTimeRowStoreV1.requireRow(
                recordID: record.id, in: modelContext
            )
            let basis = try companion.observationBasisV1()
            let temporal = try companion.temporalContextV1()
            let basisData = try ObservationAndTimeCodecV1.encode(basis)
            let temporalData = try ObservationAndTimeCodecV1.encode(temporal)
            return basisData == companion.observationBasisV1Data
                && temporalData == companion.temporalContextV1Data
        } catch {
            return false
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
                    switch outcomeRole(for: record) {
                    case .resolved, .originalResolvedDifferentFinding:
                        status = IssueStatus.resolved.rawValue
                        resolvedBy = record.id
                        updatedAt = completed
                    case .findingStillPresent:
                        status = IssueStatus.open.rawValue
                        resolvedBy = nil
                        updatedAt = completed
                    case .couldNotVerify:
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
            switch (record.stage, outcomeRole(for: record)) {
            case (WorkflowStage.check.rawValue, .findingObserved):
                guard opened.count == 1,
                      opened[0].id == record.issueID else {
                    throw SnapshotValidationErrorV1.invalidAuthority
                }
            case (WorkflowStage.recheck.rawValue, .originalResolvedDifferentFinding):
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
                guard outcomeRole(for: parent) == .originalResolvedDifferentFinding,
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
        _ url: URL,
        expectedRelativePath: String
    ) throws -> Data {
        let candidate = url.standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        let resolvedExpected = resolvedGenerationRootURL
            .appendingPathComponent(expectedRelativePath, isDirectory: false)
            .standardizedFileURL
        guard candidate.path.hasPrefix(generationRootURL.path + "/"),
              resolvedCandidate == resolvedExpected,
              relativePath(of: candidate) == expectedRelativePath else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        var ancestor = generationRootURL
        let components = expectedRelativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        for component in components.dropLast() {
            guard !component.isEmpty, component != ".", component != ".." else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
            ancestor.appendPathComponent(component, isDirectory: true)
            guard try Self.itemType(at: ancestor, fileManager: fileManager)
                    == .typeDirectory else {
                throw SnapshotValidationErrorV1.invalidAuthority
            }
        }
        guard try Self.itemType(at: candidate, fileManager: fileManager) == .typeRegular else {
            throw SnapshotValidationErrorV1.invalidAuthority
        }
        return try Data(contentsOf: candidate, options: [.mappedIfSafe])
    }

    private func relativePath(of url: URL) -> String? {
        let prefix = generationRootURL.path + "/"
        guard url.path.hasPrefix(prefix) else { return nil }
        return String(url.path.dropFirst(prefix.count))
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
        lifecycleProfile.evidencePurposes.firstIndex(where: { $0.key == value })
            ?? lifecycleProfile.evidencePurposes.count
    }

    private func stageDisplay(_ value: String) -> String? {
        try? lifecycleProfile.stage(value).stageDisplay
    }

    private func outcomeDisplay(_ value: String?) -> String? {
        guard let value else { return nil }
        let matches = lifecycleProfile.stages.flatMap(\.outcomes).filter {
            $0.key == value
        }
        guard let first = matches.first,
              matches.allSatisfy({ $0.display == first.display }) else { return nil }
        return first.display
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

    private static func itemType(
        at url: URL,
        fileManager: FileManager
    ) throws -> FileAttributeType? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private static func isSymbolicLink(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
