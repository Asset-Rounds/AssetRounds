import Foundation
import SwiftData

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
