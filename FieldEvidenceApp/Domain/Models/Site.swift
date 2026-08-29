import Foundation
import SwiftData

enum PlanSitePersistenceBoundaryV1 { static let siteIdentityMayAnchorLocationSubjects = true; static let planRowsDoNotDuplicateSiteState = true }

@Model
final class Site {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var label: String
    var address: String?
    var timeZoneID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        address: String? = nil,
        timeZoneID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = 1
        self.label = label
        self.address = address
        self.timeZoneID = timeZoneID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
