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
