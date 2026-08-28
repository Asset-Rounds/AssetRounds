import Foundation
import SwiftData

private func packageEvolutionStoredRevision(_ value: UInt64) throws -> Int64 {
    guard value > 0, value <= UInt64(Int64.max) else { throw PackageEvolutionFailureV1.invalidValue }
    return Int64(value)
}
private func packageEvolutionDomainRevision(_ value: Int64) throws -> UInt64 {
    guard value > 0 else { throw PackageEvolutionFailureV1.invalidValue }
    return UInt64(value)
}

@Model final class PromotedPackageReleaseRow {
    @Attribute(.unique) private(set) var releaseRecordID: UUID
    private(set) var workspaceID: UUID; private(set) var revision: Int64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: PromotedPackageReleaseV1) throws { try value.validate(); releaseRecordID=value.releaseRecordID; workspaceID=value.workspaceID.rawValue; revision=try packageEvolutionStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.releaseRecordSHA256; canonicalData=try PackageEvolutionCanonicalCodecV1.encode(value) }
    func value() throws -> PromotedPackageReleaseV1 { let value=try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self,from:canonicalData); try value.validate(); guard value.releaseRecordID==releaseRecordID,value.workspaceID.rawValue==workspaceID,value.revision==(try packageEvolutionDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.releaseRecordSHA256==canonicalSHA256 else{throw PackageEvolutionFailureV1.invalidDigest};return value }
}

@Model final class PackageSandboxRunRow {
    @Attribute(.unique) private(set) var runID: UUID
    private(set) var workspaceID: UUID; private(set) var revision: Int64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: PackageSandboxRunV1) throws { try value.validate(); runID=value.runID; workspaceID=value.workspaceID.rawValue; revision=try packageEvolutionStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.runSHA256; canonicalData=try PackageEvolutionCanonicalCodecV1.encode(value) }
    func value() throws -> PackageSandboxRunV1 { let value=try PackageEvolutionCanonicalCodecV1.decode(PackageSandboxRunV1.self,from:canonicalData); try value.validate(); guard value.runID==runID,value.workspaceID.rawValue==workspaceID,value.revision==(try packageEvolutionDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.runSHA256==canonicalSHA256 else{throw PackageEvolutionFailureV1.invalidDigest};return value }
}

@Model final class PackagePromotionReceiptRow {
    @Attribute(.unique) private(set) var receiptID: UUID
    private(set) var workspaceID: UUID; private(set) var promotedReleaseRecordID: UUID; private(set) var sandboxRunID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: PackagePromotionReceiptV1) throws { try value.validate(); receiptID=value.receiptID; workspaceID=value.workspaceID.rawValue; promotedReleaseRecordID=value.promotedReleaseRecordID; sandboxRunID=value.sandboxRunID; revision=try packageEvolutionStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.receiptSHA256; canonicalData=try PackageEvolutionCanonicalCodecV1.encode(value) }
    func value() throws -> PackagePromotionReceiptV1 { let value=try PackageEvolutionCanonicalCodecV1.decode(PackagePromotionReceiptV1.self,from:canonicalData); try value.validate(); guard value.receiptID==receiptID,value.workspaceID.rawValue==workspaceID,value.promotedReleaseRecordID==promotedReleaseRecordID,value.sandboxRunID==sandboxRunID,value.revision==(try packageEvolutionDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.receiptSHA256==canonicalSHA256 else{throw PackageEvolutionFailureV1.invalidDigest};return value }
}

@Model final class ActivePackageRegistryPointerRow {
    @Attribute(.unique) private(set) var pointerID: UUID
    private(set) var workspaceID: UUID; private(set) var packageID: String; private(set) var promotionReceiptID: UUID; private(set) var supersedesPointerID: UUID?
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: ActivePackageRegistryPointerV1) throws { try value.validate(); pointerID=value.pointerID; workspaceID=value.workspaceID.rawValue; packageID=value.packageID; promotionReceiptID=value.promotionReceiptID; supersedesPointerID=value.supersedesPointerID; revision=try packageEvolutionStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.pointerSHA256; canonicalData=try PackageEvolutionCanonicalCodecV1.encode(value) }
    func value() throws -> ActivePackageRegistryPointerV1 { let value=try PackageEvolutionCanonicalCodecV1.decode(ActivePackageRegistryPointerV1.self,from:canonicalData); try value.validate(); guard value.pointerID==pointerID,value.workspaceID.rawValue==workspaceID,value.packageID==packageID,value.promotionReceiptID==promotionReceiptID,value.supersedesPointerID==supersedesPointerID,value.revision==(try packageEvolutionDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.pointerSHA256==canonicalSHA256 else{throw PackageEvolutionFailureV1.invalidDigest};return value }
}

/// C21 capability records are owned by the package-lifecycle persistence
/// models.  Package evolution consumes them as a validated, nonpersistent
/// admission input; no capability columns are added to the C18 rows above.
enum PackageEvolutionC21PersistenceBoundaryV1 {
    static let capabilityInputStore = "ClientCapabilityPersistenceModelsV1"
    static let draftUpgradePlanPersistence = "NONPERSISTENT"
    static let requiredOperation = PackageLifecycleOperationV1.upgradeDraft

    static func validateCapabilityBinding(
        _ packageClosure: PackageEvolutionLifecycleClosureV1,
        admittedBy capability: ClientCapabilityLifecycleClosureV1
    ) throws {
        try packageClosure.validate()
        try C21CapabilityAdmissionBoundaryV1.validate(
            capability,
            for: requiredOperation,
            historic: false
        )
        guard capability.decision.admission == .readWrite
                || capability.decision.admission == .migrationRequired,
              packageClosure.promotedReleases.contains(where: {
                  $0.packageRelease.packageReleaseID == capability.release.packageReleaseID
                    && $0.packageRelease.packageSHA256 == capability.release.packageSHA256
                    && $0.packageRelease.workflowSHA256 == capability.release.workflowSHA256
              }) else {
            throw ClientCapabilityFailureV1.staleReference
        }
    }
}

extension PackageEvolutionLifecycleClosureV1 {
    /// Validates the exact package release bound by a C21 admission before a
    /// package-evolution consumer uses its durable closure.
    func c21ValidateCapabilityBinding(
        admittedBy capability: ClientCapabilityLifecycleClosureV1
    ) throws {
        try PackageEvolutionC21PersistenceBoundaryV1.validateCapabilityBinding(
            self,
            admittedBy: capability
        )
    }
}
