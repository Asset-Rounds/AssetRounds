import Foundation

struct EncodedBackupJSONV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum BackupCanonicalEncodingErrorV1: Error, Equatable {
    case invalidRecords
    case invalidManifest
}

struct BackupCanonicalEncoderV1 {
    func encodeRecords(_ records: V4BackupRecordsV1) throws -> EncodedBackupJSONV1 {
        guard Self.valid(records) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return try encoded(.object([
            "assets": .array(records.assets.map(Self.asset)),
            "evidenceFiles": .array(records.evidenceFiles.map(Self.evidenceFile)),
            "issues": .array(records.issues.map(Self.issue)),
            "packets": .array(records.packets.map(Self.packet)),
            "recordsSchemaVersion": .integer(records.recordsSchemaVersion),
            "reports": .array(records.reports.map(Self.report)),
            "sites": .array(records.sites.map(Self.site)),
            "workflowRecords": .array(records.workflowRecords.map(Self.workflowRecord)),
        ]))
    }

    func encodeManifest(_ manifest: V4BackupManifestV1) throws -> EncodedBackupJSONV1 {
        guard Self.valid(manifest) else {
            throw BackupCanonicalEncodingErrorV1.invalidManifest
        }
        return try encoded(.object([
            "backupSchemaVersion": .integer(manifest.backupSchemaVersion),
            "consumedEvaluationRootIDs": .array(
                manifest.consumedEvaluationRootIDs.map(CanonicalJSONV1.uuid)
            ),
            "declaredPayloadByteCount": .integer(manifest.declaredPayloadByteCount),
            "entries": .array(manifest.entries.map(Self.entry)),
            "exportedAt": CanonicalJSONV1.date(manifest.exportedAt),
            "packs": .array(manifest.packs.map(Self.pack)),
            "source": Self.source(manifest.source),
        ]))
    }

    private func encoded(_ value: CanonicalJSONValueV1) throws -> EncodedBackupJSONV1 {
        let data = try CanonicalJSONV1.encode(value)
        return EncodedBackupJSONV1(data: data, sha256: CanonicalJSONV1.sha256(data))
    }
}

private extension BackupCanonicalEncoderV1 {
    static func valid(_ records: V4BackupRecordsV1) -> Bool {
        records.recordsSchemaVersion == 1
            && sortedUniqueIDs(records.assets.map(\.id))
            && records.assets.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.evidenceFiles.map(\.id))
            && records.evidenceFiles.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.issues.map(\.id))
            && records.issues.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.packets.map(\.id))
            && records.packets.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.reports.map(\.id))
            && records.reports.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.sites.map(\.id))
            && records.sites.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.workflowRecords.map(\.id))
            && records.workflowRecords.allSatisfy({ $0.schemaVersion == 1 })
    }

    static func valid(_ manifest: V4BackupManifestV1) -> Bool {
        guard manifest.backupSchemaVersion == 1,
              manifest.declaredPayloadByteCount >= 0,
              manifest.source.persistentSchemaVersion == 1,
              manifest.source.recordsSchemaVersion == 1,
              !manifest.source.appBuild.isEmpty,
              !manifest.source.appVersion.isEmpty,
              sortedUniqueIDs(manifest.consumedEvaluationRootIDs),
              manifest.entries == manifest.entries.sorted(by: { $0.path < $1.path }),
              Set(manifest.entries.map(\.path)).count == manifest.entries.count,
              manifest.entries.allSatisfy(validEntry),
              manifest.entries.filter({ $0.path == "records.json" }).count == 1,
              manifest.packs == manifest.packs.sorted(by: packOrder),
              manifest.packs.allSatisfy({
                  !$0.packID.isEmpty && $0.schemaVersion > 0 && $0.contentVersion > 0
              }),
              Set(manifest.packs.map(packIdentity)).count == manifest.packs.count else {
            return false
        }
        var total = 0
        for value in manifest.entries.map(\.byteCount) {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return false }
            total = next
        }
        return total == manifest.declaredPayloadByteCount
    }

    static func sortedUniqueIDs(_ values: [UUID]) -> Bool {
        let strings = values.map { $0.uuidString.lowercased() }
        return Set(values).count == values.count && strings == strings.sorted()
    }

    static func validEntry(_ value: V4BackupEntryV1) -> Bool {
        guard value.byteCount >= 0,
              isLowercaseSHA256(value.sha256),
              value.path == value.path.precomposedStringWithCanonicalMapping else {
            return false
        }
        switch pathKind(value.path) {
        case .records:
            return value.mimeType == "application/json"
        case .media, .thumbnail:
            return value.mimeType == "image/jpeg"
        case .snapshot:
            return value.mimeType == "application/json"
        case .pdf:
            return value.mimeType == "application/pdf"
        case nil:
            return false
        }
    }

    enum PathKind { case records, media, thumbnail, snapshot, pdf }

    static func pathKind(_ path: String) -> PathKind? {
        if path == "records.json" { return .records }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 2 else { return nil }
        switch components[0] {
        case "media":
            return canonicalUUIDFilename(components[1], pathExtension: "jpg") ? .media : nil
        case "thumbnails":
            return canonicalUUIDFilename(components[1], pathExtension: "jpg") ? .thumbnail : nil
        case "snapshots":
            return canonicalUUIDFilename(components[1], pathExtension: "json") ? .snapshot : nil
        case "pdfs":
            return canonicalUUIDFilename(components[1], pathExtension: "pdf") ? .pdf : nil
        default:
            return nil
        }
    }

    static func canonicalUUIDFilename(_ filename: String, pathExtension value: String) -> Bool {
        let suffix = ".\(value)"
        guard filename.hasSuffix(suffix),
              let id = UUID(uuidString: String(filename.dropLast(suffix.count))) else {
            return false
        }
        return id.uuidString.lowercased() + suffix == filename
    }

    static func packOrder(_ lhs: V4BackupPackV1, _ rhs: V4BackupPackV1) -> Bool {
        if lhs.packID != rhs.packID { return lhs.packID < rhs.packID }
        if lhs.schemaVersion != rhs.schemaVersion {
            return lhs.schemaVersion < rhs.schemaVersion
        }
        return lhs.contentVersion < rhs.contentVersion
    }

    static func packIdentity(_ value: V4BackupPackV1) -> String {
        "\(value.packID)\u{0}\(value.schemaVersion)\u{0}\(value.contentVersion)"
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    static func site(_ value: V4BackupSiteDTO) -> CanonicalJSONValueV1 {
        .object([
            "address": CanonicalJSONV1.optionalString(value.address),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "label": .string(value.label),
            "schemaVersion": .integer(value.schemaVersion),
            "timeZoneID": CanonicalJSONV1.optionalString(value.timeZoneID),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
        ])
    }

    static func asset(_ value: V4BackupAssetDTO) -> CanonicalJSONValueV1 {
        .object([
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "label": .string(value.label),
            "packContentVersion": .integer(value.packContentVersion),
            "packID": .string(value.packID),
            "packSchemaVersion": .integer(value.packSchemaVersion),
            "schemaVersion": .integer(value.schemaVersion),
            "siteID": CanonicalJSONV1.uuid(value.siteID),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
        ])
    }

    static func workflowRecord(_ value: V4BackupWorkflowRecordDTO) -> CanonicalJSONValueV1 {
        .object([
            "afterDarkAcknowledgementAccepted": CanonicalJSONV1.optionalBool(value.afterDarkAcknowledgementAccepted),
            "afterDarkAcknowledgementCopy": CanonicalJSONV1.optionalString(value.afterDarkAcknowledgementCopy),
            "afterDarkAcknowledgementKey": CanonicalJSONV1.optionalString(value.afterDarkAcknowledgementKey),
            "afterDarkAcknowledgementVersion": CanonicalJSONV1.optionalString(value.afterDarkAcknowledgementVersion),
            "assetID": CanonicalJSONV1.uuid(value.assetID),
            "completedAt": CanonicalJSONV1.optionalDate(value.completedAt),
            "couldNotVerifyDisplaySnapshot": CanonicalJSONV1.optionalString(value.couldNotVerifyDisplaySnapshot),
            "couldNotVerifyKey": CanonicalJSONV1.optionalString(value.couldNotVerifyKey),
            "couldNotVerifyRegistryVersion": CanonicalJSONV1.optionalString(value.couldNotVerifyRegistryVersion),
            "draftStepKey": CanonicalJSONV1.optionalString(value.draftStepKey),
            "evidenceSourceRecordID": CanonicalJSONV1.optionalUUID(value.evidenceSourceRecordID),
            "finalizationMutationID": CanonicalJSONV1.optionalUUID(value.finalizationMutationID),
            "id": CanonicalJSONV1.uuid(value.id),
            "issueID": CanonicalJSONV1.optionalUUID(value.issueID),
            "localDate": CanonicalJSONV1.optionalString(value.localDate),
            "localTime": CanonicalJSONV1.optionalString(value.localTime),
            "note": CanonicalJSONV1.optionalString(value.note),
            "observedAtUTC": CanonicalJSONV1.optionalDate(value.observedAtUTC),
            "outcomeKey": CanonicalJSONV1.optionalString(value.outcomeKey),
            "packContentVersion": .integer(value.packContentVersion),
            "packID": .string(value.packID),
            "packSchemaVersion": .integer(value.packSchemaVersion),
            "packetID": CanonicalJSONV1.optionalUUID(value.packetID),
            "parentRecordID": CanonicalJSONV1.optionalUUID(value.parentRecordID),
            "pdfTemplateID": .string(value.pdfTemplateID),
            "pdfTemplateVersion": .integer(value.pdfTemplateVersion),
            "recordRevisionRootID": CanonicalJSONV1.uuid(value.recordRevisionRootID),
            "revisesRecordID": CanonicalJSONV1.optionalUUID(value.revisesRecordID),
            "revisionKind": .string(value.revisionKind),
            "safePositionAcknowledgementAccepted": CanonicalJSONV1.optionalBool(value.safePositionAcknowledgementAccepted),
            "safePositionAcknowledgementCopy": CanonicalJSONV1.optionalString(value.safePositionAcknowledgementCopy),
            "safePositionAcknowledgementKey": CanonicalJSONV1.optionalString(value.safePositionAcknowledgementKey),
            "safePositionAcknowledgementVersion": CanonicalJSONV1.optionalString(value.safePositionAcknowledgementVersion),
            "schemaVersion": .integer(value.schemaVersion),
            "stage": .string(value.stage),
            "startedAt": CanonicalJSONV1.date(value.startedAt),
            "state": .string(value.state),
            "timeZoneID": CanonicalJSONV1.optionalString(value.timeZoneID),
            "utcOffsetMinutes": CanonicalJSONV1.optionalInteger(value.utcOffsetMinutes),
            "workDescription": CanonicalJSONV1.optionalString(value.workDescription),
            "workPerformedLocalDate": CanonicalJSONV1.optionalString(value.workPerformedLocalDate),
        ])
    }

    static func evidenceFile(_ value: V4BackupEvidenceFileDTO) -> CanonicalJSONValueV1 {
        .object([
            "byteCount": .integer(value.byteCount),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "mimeType": .string(value.mimeType),
            "purposeKey": .string(value.purposeKey),
            "recordID": CanonicalJSONV1.uuid(value.recordID),
            "relativePath": .string(value.relativePath),
            "schemaVersion": .integer(value.schemaVersion),
            "sha256": .string(value.sha256),
            "thumbnailByteCount": .integer(value.thumbnailByteCount),
            "thumbnailRelativePath": .string(value.thumbnailRelativePath),
            "thumbnailSHA256": .string(value.thumbnailSHA256),
        ])
    }

    static func issue(_ value: V4BackupIssueDTO) -> CanonicalJSONValueV1 {
        .object([
            "assetID": CanonicalJSONV1.uuid(value.assetID),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "labelDisplaySnapshot": .string(value.labelDisplaySnapshot),
            "labelKey": .string(value.labelKey),
            "openedByRecordID": CanonicalJSONV1.uuid(value.openedByRecordID),
            "resolvedByRecordID": CanonicalJSONV1.optionalUUID(value.resolvedByRecordID),
            "schemaVersion": .integer(value.schemaVersion),
            "status": .string(value.status),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
        ])
    }

    static func packet(_ value: V4BackupPacketDTO) -> CanonicalJSONValueV1 {
        .object([
            "contentDeletedAt": CanonicalJSONV1.optionalDate(value.contentDeletedAt),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "currentRecordID": CanonicalJSONV1.optionalUUID(value.currentRecordID),
            "evaluationCounted": .bool(value.evaluationCounted),
            "id": CanonicalJSONV1.uuid(value.id),
            "schemaVersion": .integer(value.schemaVersion),
            "stableRootID": CanonicalJSONV1.uuid(value.stableRootID),
        ])
    }

    static func report(_ value: V4BackupReportDTO) -> CanonicalJSONValueV1 {
        .object([
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "packetID": CanonicalJSONV1.uuid(value.packetID),
            "pdfRelativePath": CanonicalJSONV1.optionalString(value.pdfRelativePath),
            "pdfSHA256": CanonicalJSONV1.optionalString(value.pdfSHA256),
            "pdfState": .string(value.pdfState),
            "replacesReportID": CanonicalJSONV1.optionalUUID(value.replacesReportID),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotRelativePath": .string(value.snapshotRelativePath),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "snapshotSchemaVersion": .integer(value.snapshotSchemaVersion),
            "sourceRecordID": CanonicalJSONV1.uuid(value.sourceRecordID),
        ])
    }

    static func entry(_ value: V4BackupEntryV1) -> CanonicalJSONValueV1 {
        .object([
            "byteCount": .integer(value.byteCount),
            "mimeType": .string(value.mimeType),
            "path": .string(value.path),
            "sha256": .string(value.sha256),
        ])
    }

    static func pack(_ value: V4BackupPackV1) -> CanonicalJSONValueV1 {
        .object([
            "contentVersion": .integer(value.contentVersion),
            "packID": .string(value.packID),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func source(_ value: V4BackupSourceV1) -> CanonicalJSONValueV1 {
        .object([
            "appBuild": .string(value.appBuild),
            "appVersion": .string(value.appVersion),
            "persistentSchemaVersion": .integer(value.persistentSchemaVersion),
            "recordsSchemaVersion": .integer(value.recordsSchemaVersion),
        ])
    }
}
