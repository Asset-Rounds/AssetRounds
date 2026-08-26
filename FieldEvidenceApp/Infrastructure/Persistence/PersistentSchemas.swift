import Foundation
import SwiftData

enum PersistentReferenceStorageDisposition: String, Equatable, Sendable {
    case none = "NONE"
    case applicationGovernedScalarUUID = "APPLICATION_GOVERNED_SCALAR_UUID"
}

enum PersistentSwiftDataDeleteRuleDisposition: String, Equatable, Sendable {
    case noneNoSwiftDataRelationship = "NONE_NO_SWIFTDATA_RELATIONSHIP"
}

enum PersistentScalarReferenceTargetModel: String, Equatable, Sendable {
    case site = "Site"
    case asset = "Asset"
    case workflowRecord = "WorkflowRecord"
    case evidenceFile = "EvidenceFile"
    case issue = "Issue"
    case packet = "Packet"
    case report = "Report"
}

struct PersistentScalarReferenceRegistration: Equatable, Sendable {
    let field: String
    let targetModel: PersistentScalarReferenceTargetModel
}

enum PersistentApplicationDeleteDisposition: String, Equatable, Sendable {
    case preserveEmptySiteUnlessExplicitlyDeleted =
        "PRESERVE_EMPTY_SITE_UNLESS_EXPLICITLY_DELETED"
    case deleteSelectedAssetAfterDependents =
        "DELETE_SELECTED_ASSET_AFTER_DEPENDENTS"
    case deleteSelectedAssetWorkflowRecords =
        "DELETE_SELECTED_ASSET_WORKFLOW_RECORDS"
    case deleteSelectedRecordEvidence =
        "DELETE_SELECTED_RECORD_EVIDENCE"
    case deleteSelectedAssetIssues =
        "DELETE_SELECTED_ASSET_ISSUES"
    case deleteUncountedPacketOrTombstoneCountedPacket =
        "DELETE_UNCOUNTED_PACKET_OR_TOMBSTONE_COUNTED_PACKET"
    case deleteSelectedPacketReports =
        "DELETE_SELECTED_PACKET_REPORTS"
}

struct PersistentModelRegistration {
    let stableName: String
    let modelType: any PersistentModel.Type
    let scalarReferences: [PersistentScalarReferenceRegistration]
    let referenceStorageDisposition: PersistentReferenceStorageDisposition
    let swiftDataDeleteRuleDisposition: PersistentSwiftDataDeleteRuleDisposition
    let applicationDeleteRuleOwner: String
    let applicationDeleteDisposition: PersistentApplicationDeleteDisposition

    var scalarReferenceFields: [String] {
        scalarReferences.map(\.field)
    }
}

enum PersistentModelCatalog {
    static let applicationDeleteRuleOwner =
        "WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)"

    static let registrations: [PersistentModelRegistration] = [
        PersistentModelRegistration(
            stableName: "Site",
            modelType: Site.self,
            scalarReferences: [],
            referenceStorageDisposition: .none,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition:
                .preserveEmptySiteUnlessExplicitlyDeleted
        ),
        PersistentModelRegistration(
            stableName: "Asset",
            modelType: Asset.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "siteID",
                    targetModel: .site
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedAssetAfterDependents
        ),
        PersistentModelRegistration(
            stableName: "WorkflowRecord",
            modelType: WorkflowRecord.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "assetID",
                    targetModel: .asset
                ),
                PersistentScalarReferenceRegistration(
                    field: "packetID",
                    targetModel: .packet
                ),
                PersistentScalarReferenceRegistration(
                    field: "issueID",
                    targetModel: .issue
                ),
                PersistentScalarReferenceRegistration(
                    field: "parentRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "recordRevisionRootID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "revisesRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "evidenceSourceRecordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedAssetWorkflowRecords
        ),
        PersistentModelRegistration(
            stableName: "EvidenceFile",
            modelType: EvidenceFile.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "recordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedRecordEvidence
        ),
        PersistentModelRegistration(
            stableName: "Issue",
            modelType: Issue.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "assetID",
                    targetModel: .asset
                ),
                PersistentScalarReferenceRegistration(
                    field: "openedByRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "resolvedByRecordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedAssetIssues
        ),
        PersistentModelRegistration(
            stableName: "Packet",
            modelType: Packet.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "stableRootID",
                    targetModel: .packet
                ),
                PersistentScalarReferenceRegistration(
                    field: "currentRecordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition:
                .deleteUncountedPacketOrTombstoneCountedPacket
        ),
        PersistentModelRegistration(
            stableName: "Report",
            modelType: Report.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "packetID",
                    targetModel: .packet
                ),
                PersistentScalarReferenceRegistration(
                    field: "sourceRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "replacesReportID",
                    targetModel: .report
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedPacketReports
        ),
    ]

    static var models: [any PersistentModel.Type] {
        registrations.map(\.modelType)
    }

}

enum PersistentSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentModelCatalog.models
    }

    static func makeSchema() -> Schema {
        Schema(models, version: versionIdentifier)
    }
}

@Model
final class PersistentSchemaReleaseMarker {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var releaseID: String
    var predecessorReleaseID: String?
    var migrationID: UUID?

    init(
        id: UUID,
        schemaVersion: Int,
        releaseID: String,
        predecessorReleaseID: String? = nil,
        migrationID: UUID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.releaseID = releaseID
        self.predecessorReleaseID = predecessorReleaseID
        self.migrationID = migrationID
    }
}

/// Successor with one directly persisted release marker. The release registry
/// below owns the active V1-to-V2 migration plan.
enum PersistentSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentModelCatalog.models + [PersistentSchemaReleaseMarker.self]
    }
}

/// V3 adds only the privacy-minimal append-only deletion ledger. The seven
/// content models and the V2 release marker retain their exact model types.
enum PersistentSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV2.models + [DeletionLedgerRow.self]
    }
}

/// V4 adds the durable local mutation journal and revision state. Existing
/// content and deletion-ledger model identities remain unchanged.
enum PersistentSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV3.models + [
            MutationReceiptRow.self,
            MutationQuarantineRow.self,
            WorkspaceMutationStateRow.self,
            EntityMutationRevisionRow.self,
        ]
    }
}

/// V5 preserves every V4 model identity and adds a separately versioned
/// companion row for the canonical observation/time pair.
enum PersistentSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV4.models + [ObservationAndTimeRow.self]
    }
}

enum PersistentSchemaMigrationStageV1: String, Equatable, Sendable {
    case bootstrap = "BOOTSTRAP"
    case lightweight = "LIGHTWEIGHT"
    case custom = "CUSTOM"
}

/// Card 29 versions the lifecycle-policy contract independently from the
/// SwiftData model universe. It intentionally binds V1 policy to store V5 and
/// does not invent a V6 schema or entity.
enum PersistentLifecycleContractReleaseV1: String, Codable, Equatable, Sendable {
    case v1 = "PERSISTENT_LIFECYCLE_POLICY_V1"

    var schemaVersion: Int { 1 }
    var boundStoreRelease: PersistentSchemaReleaseV1 { .v5 }
    var predecessor: PersistentLifecycleContractReleaseV1? { nil }
}

enum PersistentLifecycleContractReleaseRegistryV1 {
    static let releases: [PersistentLifecycleContractReleaseV1] = [.v1]
    static let activeRelease: PersistentLifecycleContractReleaseV1 = .v1

    static func validate() throws {
        guard releases == [.v1],
              activeRelease == .v1,
              activeRelease.schemaVersion == PersistentKindLifecycleRegistryV1.schemaVersion,
              activeRelease.rawValue == PersistentKindLifecycleRegistryV1.schemaID,
              activeRelease.boundStoreRelease == .v5,
              activeRelease.predecessor == nil else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidActiveRelease
        }
    }
}

/// Stable release identity used by manifests/journals as well as the runtime
/// registry. The descriptor values are computed from the canonical schemas so
/// a persisted release cannot silently acquire a second source of truth.
enum PersistentSchemaReleaseV1: String, Codable, Equatable, Sendable {
    case v1 = "V1"
    case v2 = "V2"
    case v3 = "V3"
    case v4 = "V4"
    case v5 = "V5"

    var compatibilityID: String {
        switch self {
        case .v1: return "FIELD_EVIDENCE_SCHEMA_V1"
        case .v2: return "FIELD_EVIDENCE_SCHEMA_V2"
        case .v3: return "FIELD_EVIDENCE_SCHEMA_V3_TOMBSTONES"
        case .v4: return "FIELD_EVIDENCE_SCHEMA_V4_MUTATION_RECEIPTS"
        case .v5: return "FIELD_EVIDENCE_SCHEMA_V5_OBSERVATION_AND_TIME"
        }
    }

    var versionIdentifier: Schema.Version {
        switch self {
        case .v1: return PersistentSchemaV1.versionIdentifier
        case .v2: return PersistentSchemaV2.versionIdentifier
        case .v3: return PersistentSchemaV3.versionIdentifier
        case .v4: return PersistentSchemaV4.versionIdentifier
        case .v5: return PersistentSchemaV5.versionIdentifier
        }
    }

    var predecessorVersionIdentifier: Schema.Version? {
        switch self {
        case .v1: return nil
        case .v2: return PersistentSchemaV1.versionIdentifier
        case .v3: return PersistentSchemaV2.versionIdentifier
        case .v4: return PersistentSchemaV3.versionIdentifier
        case .v5: return PersistentSchemaV4.versionIdentifier
        }
    }

    var models: [any PersistentModel.Type] {
        switch self {
        case .v1: return PersistentSchemaV1.models
        case .v2: return PersistentSchemaV2.models
        case .v3: return PersistentSchemaV3.models
        case .v4: return PersistentSchemaV4.models
        case .v5: return PersistentSchemaV5.models
        }
    }

    var migrationStage: PersistentSchemaMigrationStageV1 {
        switch self {
        case .v1: return .bootstrap
        case .v2, .v3, .v4: return .lightweight
        case .v5: return .custom
        }
    }
}

enum PersistentSchemaReleaseRegistryErrorV1: Error, Equatable, Sendable {
    case invalidReleaseCount
    case emptyCompatibilityID
    case duplicateCompatibilityID
    case duplicateVersionIdentifier
    case unorderedVersionIdentifiers
    case invalidBootstrapRelease
    case invalidSuccessorRelease
    case invalidActiveRelease
    case unknownVersion
}

enum PersistentSchemaMigrationPlanV1: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV1.self, PersistentSchemaV2.self]
    }

    static let migrateV1ToV2 = MigrationStage.lightweight(
        fromVersion: PersistentSchemaV1.self,
        toVersion: PersistentSchemaV2.self
    )

    static var stages: [MigrationStage] {
        [migrateV1ToV2]
    }
}

enum PersistentSchemaMigrationPlanV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV2.self, PersistentSchemaV3.self]
    }

    static let migrateV2ToV3 = MigrationStage.lightweight(
        fromVersion: PersistentSchemaV2.self,
        toVersion: PersistentSchemaV3.self
    )

    static var stages: [MigrationStage] {
        [migrateV2ToV3]
    }
}

enum PersistentSchemaMigrationPlanV3: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV3.self, PersistentSchemaV4.self]
    }

    static let migrateV3ToV4 = MigrationStage.lightweight(
        fromVersion: PersistentSchemaV3.self,
        toVersion: PersistentSchemaV4.self
    )

    static var stages: [MigrationStage] { [migrateV3ToV4] }
}

enum PersistentSchemaMigrationPlanV4: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV4.self, PersistentSchemaV5.self]
    }

    static let migrateV4ToV5 = MigrationStage.custom(
        fromVersion: PersistentSchemaV4.self,
        toVersion: PersistentSchemaV5.self,
        willMigrate: nil,
        didMigrate: { context in
            var descriptor = FetchDescriptor<WorkflowRecord>()
            descriptor.fetchLimit = ObservationAndTimeRowStoreV1.maximumRows + 1
            let records = try context.fetch(descriptor)
            guard records.count <= ObservationAndTimeRowStoreV1.maximumRows else {
                throw ObservationAndTimeRowFailureV1.rowLimitExceeded
            }
            for record in records {
                context.insert(try ObservationAndTimeStoreMigrationV1.row(
                    for: record
                ))
            }
            if context.hasChanges {
                try context.save()
            }
        }
    )

    static var stages: [MigrationStage] { [migrateV4ToV5] }
}

enum PersistentSchemaReleaseRegistryV1 {
    static let v1CompatibilityID = PersistentSchemaReleaseV1.v1.compatibilityID
    static let v2CompatibilityID = PersistentSchemaReleaseV1.v2.compatibilityID
    static let v3CompatibilityID = PersistentSchemaReleaseV1.v3.compatibilityID
    static let v4CompatibilityID = PersistentSchemaReleaseV1.v4.compatibilityID
    static let v5CompatibilityID = PersistentSchemaReleaseV1.v5.compatibilityID
    static let v2MarkerIDString = "00000000-0000-0000-0000-000000000002"
    static let v2MarkerID = UUID(uuidString: v2MarkerIDString)!

    static let releases: [PersistentSchemaReleaseV1] = [.v1, .v2, .v3, .v4, .v5]

    static let activeVersionIdentifier = PersistentSchemaV5.versionIdentifier
    static let activeCompatibilityID = v5CompatibilityID

    static var activeRelease: PersistentSchemaReleaseV1 {
        .v5
    }

    static var activeReleaseDescriptor: PersistentSchemaReleaseV1 {
        activeRelease
    }

    static var activeMigrationPlan: any SchemaMigrationPlan.Type {
        PersistentSchemaMigrationPlanV4.self
    }

    static func validate() throws {
        try PersistentLifecycleContractReleaseRegistryV1.validate()
        try validate(releases)
    }

    static func validate(
        _ candidate: [PersistentSchemaReleaseV1]
    ) throws {
        guard candidate.count == 5 else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidReleaseCount
        }

        guard candidate.allSatisfy({ !$0.compatibilityID.isEmpty }) else {
            throw PersistentSchemaReleaseRegistryErrorV1.emptyCompatibilityID
        }
        guard Set(candidate.map(\.compatibilityID)).count == candidate.count else {
            throw PersistentSchemaReleaseRegistryErrorV1.duplicateCompatibilityID
        }

        let versions = candidate.map(\.versionIdentifier)
        guard Set(versions).count == versions.count else {
            throw PersistentSchemaReleaseRegistryErrorV1.duplicateVersionIdentifier
        }
        guard zip(versions, versions.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw PersistentSchemaReleaseRegistryErrorV1.unorderedVersionIdentifiers
        }

        let expectedV1ModelIDs = PersistentModelCatalog.models.map {
            ObjectIdentifier($0)
        }
        let expectedV2ModelIDs = expectedV1ModelIDs + [
            ObjectIdentifier(PersistentSchemaReleaseMarker.self)
        ]
        let expectedV3ModelIDs = expectedV2ModelIDs + [
            ObjectIdentifier(DeletionLedgerRow.self)
        ]
        let expectedV4ModelIDs = expectedV3ModelIDs + [
            ObjectIdentifier(MutationReceiptRow.self),
            ObjectIdentifier(MutationQuarantineRow.self),
            ObjectIdentifier(WorkspaceMutationStateRow.self),
            ObjectIdentifier(EntityMutationRevisionRow.self),
        ]
        let expectedV5ModelIDs = expectedV4ModelIDs + [
            ObjectIdentifier(ObservationAndTimeRow.self)
        ]

        guard candidate[0] == .v1,
              candidate[0].versionIdentifier == PersistentSchemaV1.versionIdentifier,
              candidate[0].compatibilityID == v1CompatibilityID,
              candidate[0].predecessorVersionIdentifier == nil,
              candidate[0].models.count == 7,
              candidate[0].models.map({ ObjectIdentifier($0) })
                  == expectedV1ModelIDs,
              candidate[0].migrationStage == .bootstrap else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidBootstrapRelease
        }

        guard candidate[1] == .v2,
              candidate[1].versionIdentifier == PersistentSchemaV2.versionIdentifier,
              candidate[1].compatibilityID == v2CompatibilityID,
              candidate[1].predecessorVersionIdentifier == PersistentSchemaV1.versionIdentifier,
              candidate[1].models.count == 8,
              candidate[1].models.map({ ObjectIdentifier($0) })
                  == expectedV2ModelIDs,
              PersistentSchemaV1.models.map({ ObjectIdentifier($0) })
                  == expectedV1ModelIDs,
              PersistentSchemaV2.models.map({ ObjectIdentifier($0) })
                  == expectedV2ModelIDs,
              Array(expectedV2ModelIDs.dropLast()) == expectedV1ModelIDs,
              expectedV1ModelIDs != expectedV2ModelIDs,
              expectedV2ModelIDs.last
                  == ObjectIdentifier(PersistentSchemaReleaseMarker.self),
              v2MarkerIDString == v2MarkerIDString.lowercased(),
              v2MarkerID.uuidString.lowercased() == v2MarkerIDString,
              candidate[1].migrationStage == .lightweight else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[2] == .v3,
              candidate[2].versionIdentifier == PersistentSchemaV3.versionIdentifier,
              candidate[2].compatibilityID == v3CompatibilityID,
              candidate[2].predecessorVersionIdentifier == PersistentSchemaV2.versionIdentifier,
              candidate[2].models.count == 9,
              candidate[2].models.map({ ObjectIdentifier($0) }) == expectedV3ModelIDs,
              Array(expectedV3ModelIDs.dropLast()) == expectedV2ModelIDs,
              expectedV3ModelIDs.last == ObjectIdentifier(DeletionLedgerRow.self),
              candidate[2].migrationStage == .lightweight else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[3] == .v4,
              candidate[3].versionIdentifier == PersistentSchemaV4.versionIdentifier,
              candidate[3].compatibilityID == v4CompatibilityID,
              candidate[3].predecessorVersionIdentifier == PersistentSchemaV3.versionIdentifier,
              candidate[3].models.count == 13,
              candidate[3].models.map({ ObjectIdentifier($0) }) == expectedV4ModelIDs,
              Array(expectedV4ModelIDs.dropLast(4)) == expectedV3ModelIDs,
              candidate[3].migrationStage == .lightweight else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[4] == .v5,
              candidate[4].versionIdentifier == PersistentSchemaV5.versionIdentifier,
              candidate[4].compatibilityID == v5CompatibilityID,
              candidate[4].predecessorVersionIdentifier == PersistentSchemaV4.versionIdentifier,
              candidate[4].models.count == 14,
              candidate[4].models.map({ ObjectIdentifier($0) }) == expectedV5ModelIDs,
              PersistentSchemaV5.models.map({ ObjectIdentifier($0) }) == expectedV5ModelIDs,
              Array(expectedV5ModelIDs.dropLast()) == expectedV4ModelIDs,
              expectedV5ModelIDs.last == ObjectIdentifier(ObservationAndTimeRow.self),
              candidate[4].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard activeRelease == .v5,
              activeVersionIdentifier == candidate[4].versionIdentifier,
              activeCompatibilityID == candidate[4].compatibilityID,
              PersistentSchemaMigrationPlanV1.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV1.schemas[0])
                  == ObjectIdentifier(PersistentSchemaV1.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV1.schemas[1])
                  == ObjectIdentifier(PersistentSchemaV2.self),
              PersistentSchemaMigrationPlanV1.stages.count == 1,
              PersistentSchemaMigrationPlanV2.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV2.schemas[0])
                  == ObjectIdentifier(PersistentSchemaV2.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV2.schemas[1])
                  == ObjectIdentifier(PersistentSchemaV3.self),
              PersistentSchemaMigrationPlanV2.stages.count == 1,
              PersistentSchemaMigrationPlanV3.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV3.schemas[0]) == ObjectIdentifier(PersistentSchemaV3.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV3.schemas[1]) == ObjectIdentifier(PersistentSchemaV4.self),
              PersistentSchemaMigrationPlanV3.stages.count == 1,
              PersistentSchemaMigrationPlanV4.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV4.schemas[0]) == ObjectIdentifier(PersistentSchemaV4.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV4.schemas[1]) == ObjectIdentifier(PersistentSchemaV5.self),
              PersistentSchemaMigrationPlanV4.stages.count == 1 else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidActiveRelease
        }
    }

    static func release(
        for versionIdentifier: Schema.Version
    ) throws -> PersistentSchemaReleaseV1 {
        try validate()
        guard let release = releases.first(where: {
            $0.versionIdentifier == versionIdentifier
        }) else {
            throw PersistentSchemaReleaseRegistryErrorV1.unknownVersion
        }
        return release
    }

    static func schema(
        for versionIdentifier: Schema.Version
    ) throws -> Schema {
        let release = try release(for: versionIdentifier)
        return Schema(release.models, version: release.versionIdentifier)
    }

    static func activeSchema() throws -> Schema {
        try validate()
        return Schema(PersistentSchemaV5.models, version: PersistentSchemaV5.versionIdentifier)
    }
}
