import Foundation

struct KernelPersistenceV4SchemaDescriptor: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaID, schemaVersion, predecessorSchemaVersion, runtimePosture, integrationOwner
        case records, relationships, migrationRequired, backupRestoreRequired, deleteEraseRequired
        case exportRequired, activationEnabled, descriptorDigest
    }

    let schemaID: String
    let schemaVersion: Int
    let predecessorSchemaVersion: Int
    let runtimePosture: KernelPersistenceV4RuntimePosture
    let integrationOwner: String
    let records: [KernelPersistenceV4RecordDescriptor]
    let relationships: [KernelPersistenceV4RelationshipDescriptor]
    let migrationRequired: Bool
    let backupRestoreRequired: Bool
    let deleteEraseRequired: Bool
    let exportRequired: Bool
    let activationEnabled: Bool
    let descriptorDigest: String

    init(
        records: [KernelPersistenceV4RecordDescriptor],
        relationships: [KernelPersistenceV4RelationshipDescriptor],
        descriptorDigest: String? = nil
    ) throws {
        schemaID = KernelPersistenceV4Validation.schemaID
        schemaVersion = KernelPersistenceV4Validation.schemaVersion
        predecessorSchemaVersion = KernelPersistenceV4Validation.predecessorSchemaVersion
        runtimePosture = .dormantStatic
        integrationOwner = "V23-P10-C06"
        self.records = records
        self.relationships = relationships
        migrationRequired = true
        backupRestoreRequired = true
        deleteEraseRequired = true
        exportRequired = true
        activationEnabled = false
        let computedDigest = try Self.digest(
            records: records,
            relationships: relationships
        )
        self.descriptorDigest = descriptorDigest ?? computedDigest
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaID = try values.decode(String.self, forKey: .schemaID)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        predecessorSchemaVersion = try values.decode(Int.self, forKey: .predecessorSchemaVersion)
        runtimePosture = try values.decode(KernelPersistenceV4RuntimePosture.self, forKey: .runtimePosture)
        integrationOwner = try values.decode(String.self, forKey: .integrationOwner)
        records = try values.decode([KernelPersistenceV4RecordDescriptor].self, forKey: .records)
        relationships = try values.decode([KernelPersistenceV4RelationshipDescriptor].self, forKey: .relationships)
        migrationRequired = try values.decode(Bool.self, forKey: .migrationRequired)
        backupRestoreRequired = try values.decode(Bool.self, forKey: .backupRestoreRequired)
        deleteEraseRequired = try values.decode(Bool.self, forKey: .deleteEraseRequired)
        exportRequired = try values.decode(Bool.self, forKey: .exportRequired)
        activationEnabled = try values.decode(Bool.self, forKey: .activationEnabled)
        descriptorDigest = try values.decode(String.self, forKey: .descriptorDigest)
        try validate()
    }

    func validate() throws {
        let canonicalRecords = try KernelPersistenceV4Schema.canonicalRecordDescriptors()
        let canonicalRelationships = try KernelPersistenceV4Schema.canonicalRelationshipDescriptors()
        guard schemaID == KernelPersistenceV4Validation.schemaID,
              schemaVersion == KernelPersistenceV4Validation.schemaVersion,
              predecessorSchemaVersion == KernelPersistenceV4Validation.predecessorSchemaVersion,
              runtimePosture == .dormantStatic,
              integrationOwner == "V23-P10-C06",
              migrationRequired, backupRestoreRequired, deleteEraseRequired, exportRequired,
              !activationEnabled,
              records == canonicalRecords,
              relationships == canonicalRelationships else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try records.forEach { try $0.validate() }
        try relationships.forEach { try $0.validate() }
        guard descriptorDigest == (try Self.digest(records: records, relationships: relationships)) else {
            throw KernelPersistenceV4Failure.digestMismatch
        }
    }

    private struct DigestMaterial: Encodable {
        let schemaID: String
        let schemaVersion: Int
        let predecessorSchemaVersion: Int
        let runtimePosture: KernelPersistenceV4RuntimePosture
        let integrationOwner: String
        let records: [KernelPersistenceV4RecordDescriptor]
        let relationships: [KernelPersistenceV4RelationshipDescriptor]
        let migrationRequired: Bool
        let backupRestoreRequired: Bool
        let deleteEraseRequired: Bool
        let exportRequired: Bool
        let activationEnabled: Bool
    }

    private static func digest(
        records: [KernelPersistenceV4RecordDescriptor],
        relationships: [KernelPersistenceV4RelationshipDescriptor]
    ) throws -> String {
        try KernelPersistenceV4Validation.canonicalDigest(DigestMaterial(
            schemaID: KernelPersistenceV4Validation.schemaID,
            schemaVersion: KernelPersistenceV4Validation.schemaVersion,
            predecessorSchemaVersion: KernelPersistenceV4Validation.predecessorSchemaVersion,
            runtimePosture: .dormantStatic,
            integrationOwner: "V23-P10-C06",
            records: records,
            relationships: relationships,
            migrationRequired: true,
            backupRestoreRequired: true,
            deleteEraseRequired: true,
            exportRequired: true,
            activationEnabled: false
        ))
    }
}

enum KernelPersistenceV4Schema {
    static let repositoryDerivedPersistentModelNames = [
        "Asset", "DeletionLedgerRow", "EntityMutationRevisionRow", "EvidenceFile",
        "Issue", "MutationQuarantineRow", "MutationReceiptRow", "ObservationAndTimeRow", "Packet",
        "PersistentSchemaReleaseMarker", "Report", "Site", "WorkflowRecord",
        "WorkspaceMutationStateRow",
    ]

    static let repositoryPersistentRecordKinds: [KernelPersistenceV4RecordKind] = [
        .asset, .deletionLedgerRow, .entityMutationRevisionRow, .evidenceFile, .issue,
        .mutationQuarantineRow, .mutationReceiptRow, .observationAndTimeRow, .packet,
        .persistentSchemaReleaseMarker, .report, .site, .workflowRecord, .workspaceMutationStateRow,
    ].sorted()

    static let dormantContractRecordKinds: [KernelPersistenceV4RecordKind] = [
        .completedActivitySnapshot, .contentReference, .contractSchemaDerivationReceipt,
        .controlledAmendmentSupersession, .openJSONSchemaProjection,
    ].sorted()

    static func descriptor() throws -> KernelPersistenceV4SchemaDescriptor {
        let records = try canonicalRecordDescriptors()
        let relationships = try canonicalRelationshipDescriptors()
        return try KernelPersistenceV4SchemaDescriptor(
            records: records,
            relationships: relationships
        )
    }

    static func validate() throws {
        try CurrentSyncClassificationCatalogV1.validatePersistentModels()
        let value = try descriptor()
        try value.validate()
        guard Set(repositoryPersistentRecordKinds).isDisjoint(with: Set(dormantContractRecordKinds)),
              Set(repositoryPersistentRecordKinds + dormantContractRecordKinds)
                == Set(KernelPersistenceV4RecordKind.allCases),
              repositoryPersistentRecordKinds.map(\.rawValue) == repositoryDerivedPersistentModelNames,
              repositoryDerivedPersistentModelNames == CurrentSyncClassificationCatalogV1.persistentModelNames,
              repositoryDerivedPersistentModelNames == repositoryDerivedPersistentModelNames.sorted(),
              repositoryDerivedPersistentModelNames.count == 14,
              Set(repositoryDerivedPersistentModelNames).count == repositoryDerivedPersistentModelNames.count else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func recordDescriptor(
        for kind: KernelPersistenceV4RecordKind
    ) throws -> KernelPersistenceV4RecordDescriptor {
        let records = try canonicalRecordDescriptors()
        guard let result = records.first(where: { $0.kind == kind }) else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        return result
    }

    static func canonicalRecordDescriptors() throws -> [KernelPersistenceV4RecordDescriptor] {
        let declarationKinds: Set<KernelPersistenceV4RecordKind> = [.openJSONSchemaProjection]
        let immutableKinds: Set<KernelPersistenceV4RecordKind> = [
            .completedActivitySnapshot, .contentReference,
        ]
        let receiptKinds: Set<KernelPersistenceV4RecordKind> = [
            .contractSchemaDerivationReceipt, .controlledAmendmentSupersession,
            .deletionLedgerRow, .entityMutationRevisionRow, .mutationReceiptRow,
        ]
        let operationalKinds: Set<KernelPersistenceV4RecordKind> = [
            .mutationQuarantineRow, .persistentSchemaReleaseMarker, .workspaceMutationStateRow,
        ]
        return try KernelPersistenceV4RecordKind.allCases.map { kind in
            let classification: KernelPersistenceV4Classification
            if declarationKinds.contains(kind) {
                classification = .dormantContractDeclaration
            } else if immutableKinds.contains(kind) {
                classification = .immutableContentMetadata
            } else if receiptKinds.contains(kind) {
                classification = .appendOnlyReceipt
            } else if operationalKinds.contains(kind) {
                classification = kind == .mutationQuarantineRow ? .recoveryJournal : .deviceLocalOperational
            } else {
                classification = .canonicalWorkspace
            }
            return try KernelPersistenceV4RecordDescriptor(
                kind: kind,
                classification: classification,
                deleteRule: deleteRule(for: kind),
                canonicalMutationEffectID: "kernel-v4-effect-\(kind.rawValue.lowercased())",
                contentReferenceMapped: [
                    KernelPersistenceV4RecordKind.completedActivitySnapshot,
                    .contentReference, .evidenceFile,
                ].contains(kind),
                controlledAmendmentMapped: [
                    KernelPersistenceV4RecordKind.completedActivitySnapshot,
                    .controlledAmendmentSupersession, .report,
                ].contains(kind)
            )
        }.sorted()
    }

    private static func deleteRule(
        for kind: KernelPersistenceV4RecordKind
    ) -> KernelPersistenceV4DeleteRule {
        switch kind {
        case .site, .contractSchemaDerivationReceipt, .openJSONSchemaProjection:
            return .preserveUnlessExplicit
        case .asset:
            return .deleteAfterDependents
        case .packet:
            return .tombstoneWhenCounted
        case .deletionLedgerRow:
            return .appendEraseOnly
        case .entityMutationRevisionRow, .mutationQuarantineRow, .mutationReceiptRow,
             .persistentSchemaReleaseMarker, .workspaceMutationStateRow:
            return .clearOnErase
        case .completedActivitySnapshot, .contentReference, .controlledAmendmentSupersession,
             .evidenceFile, .issue, .observationAndTimeRow, .report, .workflowRecord:
            return .deleteWithOwner
        }
    }

    static func canonicalRelationshipDescriptors() throws -> [KernelPersistenceV4RelationshipDescriptor] {
        try [
            relationship(.assetSite, .asset, "siteID", .site, false, .deleteAfterDependents),
            relationship(.completedSnapshotSupersedes, .completedActivitySnapshot, "supersedesSnapshotID", .completedActivitySnapshot, true, .preserveUnlessExplicit),
            relationship(.controlledAmendmentOriginal, .controlledAmendmentSupersession, "originalSnapshotID", .completedActivitySnapshot, false, .preserveUnlessExplicit),
            relationship(.controlledAmendmentSuccessor, .controlledAmendmentSupersession, "successorSnapshotID", .completedActivitySnapshot, false, .preserveUnlessExplicit),
            relationship(.evidenceRecord, .evidenceFile, "recordID", .workflowRecord, false, .deleteWithOwner),
            relationship(.issueAsset, .issue, "assetID", .asset, false, .deleteWithOwner),
            relationship(.issueOpenedBy, .issue, "openedByRecordID", .workflowRecord, false, .preserveUnlessExplicit),
            relationship(.issueResolvedBy, .issue, "resolvedByRecordID", .workflowRecord, true, .preserveUnlessExplicit),
            relationship(.packetCurrentRecord, .packet, "currentRecordID", .workflowRecord, true, .preserveUnlessExplicit),
            relationship(.packetStableRoot, .packet, "stableRootID", .packet, false, .preserveUnlessExplicit),
            relationship(.reportPacket, .report, "packetID", .packet, false, .deleteWithOwner),
            relationship(.reportReplaces, .report, "replacesReportID", .report, true, .preserveUnlessExplicit),
            relationship(.reportSourceRecord, .report, "sourceRecordID", .workflowRecord, false, .preserveUnlessExplicit),
            relationship(.workflowAsset, .workflowRecord, "assetID", .asset, false, .deleteWithOwner),
            relationship(.workflowEvidenceSource, .workflowRecord, "evidenceSourceRecordID", .workflowRecord, true, .preserveUnlessExplicit),
            relationship(.workflowIssue, .workflowRecord, "issueID", .issue, true, .preserveUnlessExplicit),
            relationship(.workflowPacket, .workflowRecord, "packetID", .packet, true, .preserveUnlessExplicit),
            relationship(.workflowParent, .workflowRecord, "parentRecordID", .workflowRecord, true, .preserveUnlessExplicit),
            relationship(.workflowRevisionRoot, .workflowRecord, "recordRevisionRootID", .workflowRecord, true, .preserveUnlessExplicit),
            relationship(.workflowRevises, .workflowRecord, "revisesRecordID", .workflowRecord, true, .preserveUnlessExplicit),
        ].sorted()
    }

    private static func relationship(
        _ kind: KernelPersistenceV4RelationshipKind,
        _ source: KernelPersistenceV4RecordKind,
        _ field: String,
        _ target: KernelPersistenceV4RecordKind,
        _ optional: Bool,
        _ deleteRule: KernelPersistenceV4DeleteRule
    ) throws -> KernelPersistenceV4RelationshipDescriptor {
        try KernelPersistenceV4RelationshipDescriptor(
            kind: kind, source: source, fieldName: field, target: target,
            optional: optional, deleteRule: deleteRule
        )
    }
}
