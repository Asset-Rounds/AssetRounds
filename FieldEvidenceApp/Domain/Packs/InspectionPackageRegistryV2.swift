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

extension InspectionPackageRegistryV2 {
    func validateSurveySession(_ session:SurveySessionV1,definition:SurveyDefinitionReleaseV1,package:InspectionPackageV2)throws{try validateSurveyDefinition(definition,package:package);try package.validateSurveySession(session,definition:definition)}
}

extension InspectionPackageRegistryV2 {
    func validateSurveyDefinition(_ survey: SurveyDefinitionReleaseV1, package: InspectionPackageV2) throws {
        try survey.validate(); try package.validateSurveyDefinition(survey)
    }
}

extension InspectionPackageRegistryV2 {
    func package(id: String, admitting release: FieldReferenceReleaseV1) throws -> InspectionPackageV2 {
        let value = try package(id: id)
        try value.validateFieldReference(release)
        return value
    }
}

extension InspectionPackageRegistryV2 {
    func package(admittedBy decision: ClientCapabilityAdmissionDecisionV1,
                 closure: ClientCapabilityLifecycleClosureV1,
                 forWrite: Bool) throws -> InspectionPackageV2 {
        try closure.validate()
        guard decision == closure.decision,
              decision.admission == .readWrite || (!forWrite && decision.admission == .readOnly) else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        let value = try package(id: closure.release.packageID)
        try value.validateClientCapabilityBinding(policy: closure.policy, release: closure.release)
        return value
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

/// Admission only. Structural composition remains owned by P03-C35 and
/// functional relationship policy remains owned by P03-C41.
enum AssetSemanticPackageCompatibilityRegistryV1 {
    static func validate(
        kindBinding: AssetKindBindingEventV1,
        catalog: AssetSemanticCatalogReleaseV1,
        workflowBinding: AssetWorkflowCapabilityBindingEventV1
    ) throws {
        try kindBinding.validate(against: catalog)
        try workflowBinding.validate()
        let definition = try catalog.definition(semanticID: kindBinding.semanticID)
        let compatibleReleases = Set(
            [catalog.packageRelease] + definition.compatibleWorkflowPackageReleases
        )
        guard workflowBinding.workspaceID == kindBinding.workspaceID,
              workflowBinding.assetID == kindBinding.assetID,
              workflowBinding.kindBindingEventID == kindBinding.eventID,
              workflowBinding.kindBindingRevision == kindBinding.revision,
              compatibleReleases.contains(workflowBinding.workflowPackageRelease),
              Set(workflowBinding.capabilityIDs).isSubset(of: Set(definition.capabilityIDs)) else {
            throw AssetSemanticContractFailureV1.incompatibleRelease
        }
    }

    static func validateMultiplePackageBindings(
        _ bindings: [AssetWorkflowCapabilityBindingEventV1],
        kindBinding: AssetKindBindingEventV1,
        catalog: AssetSemanticCatalogReleaseV1
    ) throws {
        guard bindings.count <= InspectionPackageRegistrySchemaV2.maximumPackageCount,
              Set(bindings.map(\.eventID)).count == bindings.count else {
            throw AssetSemanticContractFailureV1.duplicateValue
        }
        try bindings.forEach {
            try validate(kindBinding: kindBinding, catalog: catalog, workflowBinding: $0)
        }
    }
}

enum AuthorityCriterionPackageCompatibilityRegistryV1 {
    static func validate(
        _ binding: InspectionPackageAuthorityCriterionBindingV1,
        package: InspectionPackageV2
    ) throws {
        try binding.validate()
        try package.validate()
        guard binding.packageRelease.packageID == package.packageID,
              binding.packageRelease.schemaVersion == package.schemaVersion,
              binding.packageRelease.contentVersion == package.contentVersion else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
    }

    static func validate(
        _ bindings: [InspectionPackageAuthorityCriterionBindingV1],
        registry: InspectionPackageRegistryV2
    ) throws {
        guard bindings.count <= InspectionPackageRegistrySchemaV2.maximumPackageCount,
              Set(bindings.map(\.packageRelease)).count == bindings.count else {
            throw InspectionPackageFailureV2.duplicateDeclaration
        }
        for binding in bindings {
            try validate(binding, package: registry.package(id: binding.packageRelease.packageID))
        }
    }
}

enum FunctionalRelationshipPackageCompatibilityRegistryV1 {
    static func validate(
        _ binding: InspectionPackageFunctionalRelationshipBindingV1,
        package: InspectionPackageV2,
        semanticCatalogs: [AssetSemanticCatalogReleaseV1]
    ) throws {
        try binding.validate(); try package.validate()
        guard binding.packageRelease.packageID == package.packageID,
              binding.packageRelease.schemaVersion == package.schemaVersion,
              binding.packageRelease.contentVersion == package.contentVersion else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        guard Set(semanticCatalogs.map(\.releaseID)).count == semanticCatalogs.count else {
            throw InspectionPackageFailureV2.duplicateDeclaration
        }
        let catalogs = Dictionary(uniqueKeysWithValues: semanticCatalogs.map { ($0.releaseID, $0) })
        for descriptor in binding.descriptorReleases {
            guard let source = catalogs[descriptor.sourceCatalogRelease.releaseID],
                  let target = catalogs[descriptor.targetCatalogRelease.releaseID] else {
                throw InspectionPackageFailureV2.incompatiblePackage
            }
            try descriptor.validate(sourceCatalog: source, targetCatalog: target)
        }
    }

    static func validate(
        _ bindings: [InspectionPackageFunctionalRelationshipBindingV1],
        registry: InspectionPackageRegistryV2,
        semanticCatalogs: [AssetSemanticCatalogReleaseV1]
    ) throws {
        guard bindings.count <= InspectionPackageRegistrySchemaV2.maximumPackageCount,
              Set(bindings.map(\.packageRelease)).count == bindings.count else {
            throw InspectionPackageFailureV2.duplicateDeclaration
        }
        for binding in bindings {
            try validate(binding,
                package: registry.package(id: binding.packageRelease.packageID),
                semanticCatalogs: semanticCatalogs)
        }
    }
}

// MARK: - C19 measurement package admission

extension AuthorityCriterionPackageCompatibilityRegistryV1 {
    /// Admission is declaration-only: the registry validates the existing
    /// package/sidecar pair and never persists or evaluates a measurement.
    static func c19ValidateMeasurementCapture(
        _ capture: MeasurementCaptureV1,
        release: InspectionPackageReleaseV1,
        package: InspectionPackageV2,
        binding: InspectionPackageAuthorityCriterionBindingV1
    ) throws {
        try validate(binding, package: package)
        try binding.c19ValidateMeasurementCapture(capture, release: release, package: package)
    }

    static func c19ValidateMeasurementProtocol(
        _ protocolRelease: MeasurementProtocolReleaseV1,
        binding: InspectionPackageAuthorityCriterionBindingV1,
        package: InspectionPackageV2
    ) throws {
        try validate(binding, package: package)
        try binding.c19ValidateMeasurementProtocol(protocolRelease)
    }
}

// MARK: - C20 reviewed-derivative package admission

extension InspectionPackageRegistryV2 {
    /// Resolves one immutable declaration and validates a reviewed derivative
    /// against it. Registry admission remains declaration-only; this method
    /// cannot publish, persist, classify, or infer privacy/compliance state.
    func c20ValidateReviewedDerivative(
        packageID: String,
        binding: InspectionPackageAuthorityCriterionBindingV1,
        release: InspectionPackageReleaseV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        let declaration = try self.package(id: packageID)
        try AuthorityCriterionPackageCompatibilityRegistryV1.validate(binding, package: declaration)
        try release.validate()
        guard release.packageID == declaration.packageID,
              release.packageContentVersion == declaration.contentVersion else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        return try binding.c20ValidateReviewedDerivative(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now,
            release: release,
            package: declaration
        )
    }
}
