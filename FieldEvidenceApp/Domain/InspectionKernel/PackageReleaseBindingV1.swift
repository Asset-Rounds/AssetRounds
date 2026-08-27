import Foundation

enum PackageReleaseBindingKindV1: String, CaseIterable, Codable, Sendable {
    case draft = "DRAFT"
    case active = "ACTIVE"
    case completed = "COMPLETED"
    case amendment = "AMENDMENT"
    case export = "EXPORT"
}

struct PackageReleaseBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let bindingID: String
    let kind: PackageReleaseBindingKindV1
    let packageReleaseID: String
    let packageID: String
    let packageContentVersion: Int
    let packageSHA256: String
    let canonicalPackageBytes: Data
    let workflowSHA256: String
    let canonicalWorkflowBytes: Data

    private init(
        schemaVersion: Int,
        bindingID: String,
        kind: PackageReleaseBindingKindV1,
        packageReleaseID: String,
        packageID: String,
        packageContentVersion: Int,
        packageSHA256: String,
        canonicalPackageBytes: Data,
        workflowSHA256: String,
        canonicalWorkflowBytes: Data
    ) {
        self.schemaVersion = schemaVersion
        self.bindingID = bindingID
        self.kind = kind
        self.packageReleaseID = packageReleaseID
        self.packageID = packageID
        self.packageContentVersion = packageContentVersion
        self.packageSHA256 = packageSHA256
        self.canonicalPackageBytes = canonicalPackageBytes
        self.workflowSHA256 = workflowSHA256
        self.canonicalWorkflowBytes = canonicalWorkflowBytes
    }

    init(
        bindingID: String,
        kind: PackageReleaseBindingKindV1,
        publication: InspectionPackagePublishedReleaseV1
    ) throws {
        try publication.validate()
        let release = publication.release
        try release.validate()
        guard WorkflowGrammarValidationV1.validID(bindingID),
              release.state == .published else {
            throw InspectionKernelFailureV1.invalidTransition
        }
        schemaVersion = Self.schemaVersion
        self.bindingID = bindingID
        self.kind = kind
        self.packageReleaseID = release.packageReleaseID
        self.packageID = release.packageID
        self.packageContentVersion = release.packageContentVersion
        self.packageSHA256 = release.packageSHA256
        self.canonicalPackageBytes = release.canonicalPackageBytes
        self.workflowSHA256 = release.workflowSHA256
        self.canonicalWorkflowBytes = release.canonicalWorkflowBytes
    }

    func validateResume(against publication: InspectionPackagePublishedReleaseV1) throws {
        try validate()
        try publication.validate()
        let release = publication.release
        try release.validate()
        guard schemaVersion == Self.schemaVersion,
              release.state == .published,
              packageReleaseID == release.packageReleaseID,
              packageID == release.packageID,
              packageContentVersion == release.packageContentVersion,
              packageSHA256 == release.packageSHA256,
              canonicalPackageBytes == release.canonicalPackageBytes,
              workflowSHA256 == release.workflowSHA256,
              canonicalWorkflowBytes == release.canonicalWorkflowBytes else {
            throw InspectionKernelFailureV1.hashMismatch
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              WorkflowGrammarValidationV1.validID(bindingID),
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              WorkflowGrammarValidationV1.validID(packageID),
              packageContentVersion == 1,
              KernelCanonicalHashV1.sha256(canonicalPackageBytes) == packageSHA256,
              KernelCanonicalHashV1.sha256(canonicalWorkflowBytes) == workflowSHA256 else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        let package = try InspectionPackageCanonicalCodecV2.decode(canonicalPackageBytes)
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(canonicalWorkflowBytes)
        guard package.packageID == packageID, package.contentVersion == packageContentVersion else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        let expected = try InspectionPackageReleaseV1.makeDraft(
            package: package,
            workflow: workflow
        )
        guard expected.packageReleaseID == packageReleaseID else {
            throw InspectionKernelFailureV1.hashMismatch
        }
    }
}

enum PackageReleaseBindingCanonicalCodecV1 {
    static func encode(_ value: PackageReleaseBindingV1) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode(_ data: Data) throws -> PackageReleaseBindingV1 {
        guard !data.isEmpty, data.count <= 2_097_152 else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(PackageReleaseBindingV1.self, from: data)
        guard try encode(value) == data else { throw InspectionKernelFailureV1.invalidValue }
        return value
    }
}

extension PackageReleaseBindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, bindingID, kind, packageReleaseID, packageID
        case packageContentVersion, packageSHA256, canonicalPackageBytes
        case workflowSHA256, canonicalWorkflowBytes
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
            bindingID: try c.decode(String.self, forKey: .bindingID),
            kind: try c.decode(PackageReleaseBindingKindV1.self, forKey: .kind),
            packageReleaseID: try c.decode(String.self, forKey: .packageReleaseID),
            packageID: try c.decode(String.self, forKey: .packageID),
            packageContentVersion: try c.decode(Int.self, forKey: .packageContentVersion),
            packageSHA256: try c.decode(String.self, forKey: .packageSHA256),
            canonicalPackageBytes: try c.decode(Data.self, forKey: .canonicalPackageBytes),
            workflowSHA256: try c.decode(String.self, forKey: .workflowSHA256),
            canonicalWorkflowBytes: try c.decode(Data.self, forKey: .canonicalWorkflowBytes)
        )
        try validate()
    }
}

enum InspectionKernelLifecycleV1 {
    static let mode = "DECLARATION_ONLY"
    static let schema = "KERNEL_CONTRACT_V1"
    static let persistent = false
    static let migrationRequired = false
    static let backupRestoreRequired = false
    static let deleteEraseRequired = false
    static let exportReportEffectRequired = false
    static let searchRebuildReplayRequired = false
    static let downgradePolicy = "DORMANT_REVERT_ALLOWED"
    static let interruption = "ZERO_OR_COMPLETE"
    static let idempotentReceipt = "EXACT_CANONICAL_BYTES_ADOPTION"
}
