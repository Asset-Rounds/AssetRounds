import Foundation

struct InspectionPackageRegistryPublicationReceiptV2: Equatable, Sendable {
    let schemaName: String
    let schemaVersion: Int
    let orderedPackageIDs: [String]
    let canonicalPackages: [Data]
    let adoptedExistingPublication: Bool
    let persistentWriteOccurred: Bool

    init(
        schemaName: String,
        schemaVersion: Int,
        orderedPackageIDs: [String],
        canonicalPackages: [Data],
        adoptedExistingPublication: Bool,
        persistentWriteOccurred: Bool
    ) throws {
        self.schemaName = schemaName
        self.schemaVersion = schemaVersion
        self.orderedPackageIDs = orderedPackageIDs
        self.canonicalPackages = canonicalPackages
        self.adoptedExistingPublication = adoptedExistingPublication
        self.persistentWriteOccurred = persistentWriteOccurred
        guard schemaName == InspectionPackageRegistrySchemaV2.name,
              schemaVersion == InspectionPackageRegistrySchemaV2.version,
              !orderedPackageIDs.isEmpty,
              orderedPackageIDs.count == canonicalPackages.count,
              orderedPackageIDs.count <= InspectionPackageRegistrySchemaV2.maximumPackageCount,
              orderedPackageIDs == orderedPackageIDs.sorted(),
              InspectionPackageValidationV2.unique(orderedPackageIDs),
              !persistentWriteOccurred else {
            throw InspectionPackageFailureV2.invalidValue
        }
        let decoded = try canonicalPackages.map {
            try InspectionPackageCanonicalCodecV2.decode($0)
        }
        guard decoded.map(\.packageID) == orderedPackageIDs else {
            throw InspectionPackageFailureV2.nonCanonicalData
        }
    }
}

struct InspectionPackageRegistryV2: Equatable, Sendable {
    let orderedPackages: [InspectionPackageV2]
    private let packagesByID: [String: InspectionPackageV2]

    init(packages: [InspectionPackageV2]) throws {
        guard !packages.isEmpty,
              packages.count <= InspectionPackageRegistrySchemaV2.maximumPackageCount else {
            throw InspectionPackageFailureV2.invalidValue
        }
        let ordered = packages.sorted { $0.packageID < $1.packageID }
        guard InspectionPackageValidationV2.unique(ordered.map(\.packageID)) else {
            throw InspectionPackageFailureV2.duplicatePackageID
        }
        try ordered.forEach { try InspectionPackageCompatibilityValidatorV2.validate($0) }
        var lookup: [String: InspectionPackageV2] = [:]
        for package in ordered { lookup[package.packageID] = package }
        self.orderedPackages = ordered
        self.packagesByID = lookup
    }

    var orderedPackageIDs: [String] { orderedPackages.map(\.packageID) }

    func package(id: String) throws -> InspectionPackageV2 {
        guard let value = packagesByID[id] else {
            throw InspectionPackageFailureV2.unknownPackage
        }
        return value
    }

    func publicationReceipt(adoptedExisting: Bool) throws
        -> InspectionPackageRegistryPublicationReceiptV2 {
        try InspectionPackageRegistryPublicationReceiptV2(
            schemaName: InspectionPackageRegistrySchemaV2.name,
            schemaVersion: InspectionPackageRegistrySchemaV2.version,
            orderedPackageIDs: orderedPackageIDs,
            canonicalPackages: try orderedPackages.map {
                try InspectionPackageCanonicalCodecV2.encode($0)
            },
            adoptedExistingPublication: adoptedExisting,
            persistentWriteOccurred: false
        )
    }
}

enum InspectionPackageRegistryPublicationBoundaryV2: String, CaseIterable, Sendable {
    case beforeValidation = "BEFORE_VALIDATION"
    case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
    case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
}

/// A publication value is constructed only after the entire candidate validates.
/// Since the declaration is nonpersistent, interruption returns no partial
/// registry; retry deterministically reconstructs the same immutable value.
enum InspectionPackageRegistryPublisherV2 {
    typealias Interruption = @Sendable (
        InspectionPackageRegistryPublicationBoundaryV2
    ) throws -> Void

    static func publish(
        packages: [InspectionPackageV2],
        interruption: Interruption = { _ in }
    ) throws -> (registry: InspectionPackageRegistryV2,
                 receipt: InspectionPackageRegistryPublicationReceiptV2) {
        try interruption(.beforeValidation)
        let registry = try InspectionPackageRegistryV2(packages: packages)
        try interruption(.afterValidationBeforePublication)
        let receipt = try registry.publicationReceipt(adoptedExisting: false)
        try interruption(.afterPublicationBeforeReceipt)
        return (registry, receipt)
    }

    static func recover(
        canonicalPackages: [Data],
        interruption: Interruption = { _ in }
    ) throws -> (registry: InspectionPackageRegistryV2,
                 receipt: InspectionPackageRegistryPublicationReceiptV2) {
        try interruption(.beforeValidation)
        guard !canonicalPackages.isEmpty,
              canonicalPackages.count <= InspectionPackageRegistrySchemaV2.maximumPackageCount else {
            throw InspectionPackageFailureV2.invalidValue
        }
        let packages = try canonicalPackages.map {
            try InspectionPackageCanonicalCodecV2.decode($0)
        }
        let registry = try InspectionPackageRegistryV2(packages: packages)
        guard packages.map(\.packageID) == registry.orderedPackageIDs else {
            throw InspectionPackageFailureV2.nonCanonicalData
        }
        try interruption(.afterValidationBeforePublication)
        let receipt = try registry.publicationReceipt(adoptedExisting: true)
        guard receipt.canonicalPackages == canonicalPackages else {
            throw InspectionPackageFailureV2.nonCanonicalData
        }
        try interruption(.afterPublicationBeforeReceipt)
        return (registry, receipt)
    }
}
