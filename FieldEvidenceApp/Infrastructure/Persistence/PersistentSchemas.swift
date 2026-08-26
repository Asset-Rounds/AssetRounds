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
    case deleteOrphanSiteIfSelectedAssetWasLastSiteAsset =
        "DELETE_ORPHAN_SITE_IF_SELECTED_ASSET_WAS_LAST_SITE_ASSET"
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
                .deleteOrphanSiteIfSelectedAssetWasLastSiteAsset
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

enum PersistentSchemaMigrationStageV1: String, Equatable, Sendable {
    case bootstrap = "BOOTSTRAP"
    case lightweight = "LIGHTWEIGHT"
}

/// Stable release identity used by manifests/journals as well as the runtime
/// registry. The descriptor values are computed from the canonical schemas so
/// a persisted release cannot silently acquire a second source of truth.
enum PersistentSchemaReleaseV1: String, Codable, Equatable, Sendable {
    case v1 = "V1"
    case v2 = "V2"

    var compatibilityID: String {
        switch self {
        case .v1: return "FIELD_EVIDENCE_SCHEMA_V1"
        case .v2: return "FIELD_EVIDENCE_SCHEMA_V2"
        }
    }

    var versionIdentifier: Schema.Version {
        switch self {
        case .v1: return PersistentSchemaV1.versionIdentifier
        case .v2: return PersistentSchemaV2.versionIdentifier
        }
    }

    var predecessorVersionIdentifier: Schema.Version? {
        switch self {
        case .v1: return nil
        case .v2: return PersistentSchemaV1.versionIdentifier
        }
    }

    var models: [any PersistentModel.Type] {
        switch self {
        case .v1: return PersistentSchemaV1.models
        case .v2: return PersistentSchemaV2.models
        }
    }

    var migrationStage: PersistentSchemaMigrationStageV1 {
        switch self {
        case .v1: return .bootstrap
        case .v2: return .lightweight
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

enum PersistentSchemaReleaseRegistryV1 {
    static let v1CompatibilityID = PersistentSchemaReleaseV1.v1.compatibilityID
    static let v2CompatibilityID = PersistentSchemaReleaseV1.v2.compatibilityID
    static let v2MarkerIDString = "00000000-0000-0000-0000-000000000002"
    static let v2MarkerID = UUID(uuidString: v2MarkerIDString)!

    static let releases: [PersistentSchemaReleaseV1] = [.v1, .v2]

    static let activeVersionIdentifier = PersistentSchemaV2.versionIdentifier
    static let activeCompatibilityID = v2CompatibilityID

    static var activeRelease: PersistentSchemaReleaseV1 {
        .v2
    }

    static var activeReleaseDescriptor: PersistentSchemaReleaseV1 {
        activeRelease
    }

    static var activeMigrationPlan: any SchemaMigrationPlan.Type {
        PersistentSchemaMigrationPlanV1.self
    }

    static func validate() throws {
        try validate(releases)
    }

    static func validate(
        _ candidate: [PersistentSchemaReleaseV1]
    ) throws {
        guard candidate.count == 2 else {
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

        guard activeRelease == .v2,
              activeVersionIdentifier == candidate[1].versionIdentifier,
              activeCompatibilityID == candidate[1].compatibilityID,
              PersistentSchemaMigrationPlanV1.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV1.schemas[0])
                  == ObjectIdentifier(PersistentSchemaV1.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV1.schemas[1])
                  == ObjectIdentifier(PersistentSchemaV2.self),
              PersistentSchemaMigrationPlanV1.stages.count == 1 else {
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
        return Schema(PersistentSchemaV2.models, version: PersistentSchemaV2.versionIdentifier)
    }
}
