import Foundation

struct EncodedBackupJSONV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum BackupCanonicalEncodingErrorV1: Error, Equatable {
    case invalidRecords
    case invalidManifest
}

struct BackupCanonicalEncoderV1: Sendable {
    func encodeRecordsOffMain(
        _ records: V4BackupRecordsV1,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> EncodedBackupJSONV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().encodeRecords(records)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func encodeManifestOffMain(
        _ manifest: V4BackupManifestV1,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> EncodedBackupJSONV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().encodeManifest(manifest)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func encodeRecords(_ records: V4BackupRecordsV1) throws -> EncodedBackupJSONV1 {
        guard Self.valid(records) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        var fields: [String: CanonicalJSONValueV1] = [
            "assets": .array(records.assets.map(Self.asset)),
            "evidenceFiles": .array(records.evidenceFiles.map(Self.evidenceFile)),
            "issues": .array(records.issues.map(Self.issue)),
            "packets": .array(records.packets.map(Self.packet)),
            "recordsSchemaVersion": .integer(records.recordsSchemaVersion),
            "reports": .array(records.reports.map(Self.report)),
            "sites": .array(records.sites.map(Self.site)),
            "workflowRecords": .array(records.workflowRecords.map(Self.workflowRecord)),
        ]
        if let deletionLedger = records.deletionLedger {
            fields["deletionLedger"] = Self.deletionLedger(deletionLedger)
        }
        if let mutationHistory = records.mutationHistory {
            fields["mutationHistory"] = try Self.mutationHistory(mutationHistory)
        }
        return try encoded(.object(fields))
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
        let ledgerIsValid: Bool
        switch (
            records.recordsSchemaVersion,
            records.deletionLedger,
            records.mutationHistory
        ) {
        case (1, nil, nil):
            ledgerIsValid = true
        case (2, let ledger?, nil):
            ledgerIsValid = (try? ledger.validate()) != nil
        case (3, let ledger?, let history?):
            ledgerIsValid = (try? ledger.validate()) != nil
                && (try? MutationJournalStoreV1.validateImportedSnapshot(history)) != nil
                && validMutationHistoryOrder(history)
        default:
            ledgerIsValid = false
        }
        return ledgerIsValid
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
        let zero = UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        ))
        let sourceIdentityIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.workspaceID,
            manifest.source.replicaID
        ) {
        case (1, nil, nil):
            sourceIdentityIsValid = true
        case (2, let workspaceID?, let replicaID?),
             (3, let workspaceID?, let replicaID?):
            sourceIdentityIsValid = workspaceID != zero
                && replicaID != zero
                && workspaceID != replicaID
        default:
            sourceIdentityIsValid = false
        }
        let schemaPairIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.persistentSchemaVersion,
            manifest.source.recordsSchemaVersion
        ) {
        case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3):
            schemaPairIsValid = true
        default:
            schemaPairIsValid = false
        }
        guard sourceIdentityIsValid,
              schemaPairIsValid,
              manifest.declaredPayloadByteCount >= 0,
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

    static func deletionLedger(_ value: DeletionLedgerV2) -> CanonicalJSONValueV1 {
        .object([
            "entries": .array(value.entries.map(deletionLedgerEntry)),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func deletionLedgerEntry(
        _ value: DeletionLedgerEntryV2
    ) -> CanonicalJSONValueV1 {
        .object([
            "deletedAt": CanonicalJSONV1.date(value.deletedAt),
            "identity": .object([
                "id": CanonicalJSONV1.uuid(value.identity.id),
                "kind": .string(value.identity.kind.rawValue),
            ]),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func mutationHistory(
        _ value: MutationHistorySnapshotV1
    ) throws -> CanonicalJSONValueV1 {
        guard validMutationHistoryOrder(value),
              value.workspaceRevision <= UInt64(Int.max),
              value.lastLocalSequence <= UInt64(Int.max) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "entityRevisions": .array(value.entityRevisions.map {
                var fields: [String: CanonicalJSONValueV1] = [
                    "identity": .object([
                        "id": CanonicalJSONV1.uuid($0.identity.id),
                        "kind": .string($0.identity.kind.rawValue),
                    ]),
                    "revision": .integer(Int($0.revision)),
                ]
                if let digest = $0.externalProjectionSHA256 {
                    fields["externalProjectionSHA256"] = .string(digest)
                }
                return .object(fields)
            }),
            "lastLocalSequence": .integer(Int(value.lastLocalSequence)),
            "quarantines": .array(value.quarantines.map {
                .object([
                    "acceptedIdentitySHA256": .string(
                        $0.acceptedIdentitySHA256
                    ),
                    "conflictingIdentitySHA256": .string(
                        $0.conflictingIdentitySHA256
                    ),
                    "detectedAt": CanonicalJSONV1.date($0.detectedAt),
                    "identityDomain": .string($0.identityDomain.rawValue),
                    "mutationID": CanonicalJSONV1.uuid($0.mutationID),
                    "workspaceID": CanonicalJSONV1.uuid(
                        $0.workspaceID.rawValue
                    ),
                ])
            }),
            "receipts": .array(value.receipts.map(mutationReceiptRecord)),
            "schemaVersion": .integer(value.schemaVersion),
            "workspaceRevision": .integer(Int(value.workspaceRevision)),
        ])
    }

    static func mutationReceiptRecord(
        _ value: MutationHistoryReceiptRecordV1
    ) -> CanonicalJSONValueV1 {
        var fields: [String: CanonicalJSONValueV1] = [
            "envelopeData": .string(value.envelopeData.base64EncodedString()),
            "receiptData": .string(value.receiptData.base64EncodedString()),
        ]
        if let reversalBasisData = value.reversalBasisData {
            fields["reversalBasisData"] = .string(
                reversalBasisData.base64EncodedString()
            )
        }
        if let semanticReversalData = value.semanticReversalData {
            fields["semanticReversalData"] = .string(
                semanticReversalData.base64EncodedString()
            )
        }
        return .object(fields)
    }

    static func validMutationHistoryOrder(
        _ value: MutationHistorySnapshotV1
    ) -> Bool {
        guard value.schemaVersion == MutationHistorySnapshotV1.schemaVersion,
              value.receipts.count
                <= MutationJournalStoreV1.maximumReceiptValidationCount,
              value.quarantines.count
                <= MutationJournalStoreV1.maximumReceiptValidationCount,
              value.entityRevisions.count
                <= MutationReceiptV1.maximumPostImageCount,
              value.workspaceRevision <= UInt64(Int.max),
              value.lastLocalSequence <= UInt64(Int.max),
              value.entityRevisions.allSatisfy({
                  $0.revision > 0
                    && $0.revision <= UInt64(Int.max)
                    && $0.externalProjectionSHA256.map {
                        validSHA256($0)
                    } != false
              }),
              value.quarantines.allSatisfy({
                  validSHA256($0.acceptedIdentitySHA256)
                    && validSHA256($0.conflictingIdentitySHA256)
                    && $0.acceptedIdentitySHA256
                        != $0.conflictingIdentitySHA256
                    && validDate($0.detectedAt)
              }) else {
            return false
        }
        let receiptKeys: [String]
        do {
            receiptKeys = try value.receipts.map {
                try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
                    .identity.stableKey
            }
        } catch {
            return false
        }
        let quarantineKeys = value.quarantines.map {
            "\($0.workspaceID.rawValue.uuidString.lowercased()):\($0.mutationID.uuidString.lowercased())"
        }
        let revisionKeys = value.entityRevisions.map(\.identity.stableKey)
        return receiptKeys == receiptKeys.sorted()
            && Set(receiptKeys).count == receiptKeys.count
            && quarantineKeys == quarantineKeys.sorted()
            && Set(quarantineKeys).count == quarantineKeys.count
            && revisionKeys == revisionKeys.sorted()
            && Set(revisionKeys).count == revisionKeys.count
    }

    static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains(Int($0.value))
                || (97...102).contains(Int($0.value))
        }
    }

    static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    static func source(_ value: V4BackupSourceV1) -> CanonicalJSONValueV1 {
        var fields: [String: CanonicalJSONValueV1] = [
            "appBuild": .string(value.appBuild),
            "appVersion": .string(value.appVersion),
            "persistentSchemaVersion": .integer(value.persistentSchemaVersion),
            "recordsSchemaVersion": .integer(value.recordsSchemaVersion),
        ]
        if let replicaID = value.replicaID,
           let workspaceID = value.workspaceID {
            fields["replicaID"] = CanonicalJSONV1.uuid(replicaID)
            fields["workspaceID"] = CanonicalJSONV1.uuid(workspaceID)
        }
        return .object(fields)
    }
}
