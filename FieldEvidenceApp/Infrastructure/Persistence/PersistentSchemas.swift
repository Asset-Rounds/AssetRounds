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

/// Declaration-only successor. Production construction remains pinned to V1
/// until a later migration-owning card supplies and activates a migration plan.
enum PersistentSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentModelCatalog.models
    }
}
