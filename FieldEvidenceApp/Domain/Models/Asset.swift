import Foundation
enum EvidenceContextAssetBoundaryV1{static let evidenceContextsReferenceAssetIdentity=true;static let assetRowsDoNotCacheLightingOrSolarContext=true}
enum PlacementPoseAssetPersistenceBoundaryV1{static let assetIdentityIsReferenced=true;static let poseHistoryIsStoredSeparately=true}

enum AssetScheduleOwnershipBoundaryV1 { static let assetRowsStoreScheduleState = false }
import SwiftData

enum PlanAssetIdentityBindingV1 { static let assetIdentityIsReferencedNotCopied = true; static let planSchemaVersion = 28 }

@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var siteID: UUID
    var packID: String
    var packSchemaVersion: Int
    var packContentVersion: Int
    var label: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        siteID: UUID,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        label: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = 1
        self.siteID = siteID
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

extension Asset {
    /// A locator resolves to this stable asset identifier only. It never
    /// changes the asset label, package binding, or workflow state.
    func validateResolvedLocator(_ locator: AssetLocatorV1) throws {
        try locator.validate()
        guard locator.assetID == id else { throw AssetLocatorFailureV1.invalidValue }
    }

    /// Existing values are the complete authority for the V9→V10 legacy
    /// semantic migration. No product identifier, installation date, lifecycle
    /// event, condition, recall, warranty, or operational disposition is
    /// derivable from this row.
    func legacyPackageReleaseIdentityForAssetSemanticMigration() throws
        -> PackageReleaseIdentityV1 {
        try PackageReleaseIdentityV1(
            packageID: packID,
            schemaVersion: packSchemaVersion,
            contentVersion: packContentVersion
        )
    }
}

enum LightingAssetIdentityEnrollmentV1 { static let lightingRowsReferenceCanonicalAssetID = true; static let topologyDoesNotCloneAssets = true }

enum C31LightingAssetDisplayBoundaryV1 {
    static let labelsComeFromLocalizationCatalog = true
    static let systemTopologyIsNotAnOperationalConclusion = true

    static func assetIDs(from system: LightingSystemV1) -> [UUID] {
        system.luminaires.map(\.assetID).sorted { $0.uuidString < $1.uuidString }
    }
}
