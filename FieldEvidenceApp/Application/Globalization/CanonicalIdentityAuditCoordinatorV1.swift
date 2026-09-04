import Foundation

/// Pure application boundary for the C05 canonical-identity audit. The
/// coordinator only compares supplied snapshots; it performs no persistence,
/// migration, localization, or backup writes.
enum CanonicalIdentityAuditCoordinatorV1 {
    static func audit(_ fixture: CanonicalIdentityBaselineFixtureV1) throws -> CanonicalIdentityComparisonV1 {
        try CanonicalIdentityInvarianceV1.validateDeclaredSeams()
        return try CanonicalIdentityInvarianceV1.audit(fixture)
    }

    static func validate(_ fixture: CanonicalIdentityBaselineFixtureV1) throws {
        _ = try audit(fixture)
    }
}
