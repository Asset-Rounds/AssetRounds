import Foundation

enum BundledInspectionPackageRegistryLoadResultV2: Equatable, Sendable {
    case available(
        registry: InspectionPackageRegistryV2,
        receipt: InspectionPackageRegistryPublicationReceiptV2,
        parity: ShippingIlluminatedSignParityReceiptV1
    )
    case unavailable(InspectionPackageFailureV2)
}

extension BundledInspectionPackageRegistryV2 {
    static func admittedShippingPackage(
        decision: ClientCapabilityAdmissionDecisionV1,
        closure: ClientCapabilityLifecycleClosureV1,
        bundle: Bundle = .main,
        forWrite: Bool
    ) throws -> InspectionPackageV2 {
        switch load(bundle: bundle) {
        case .available(let registry, _, _):
            return try registry.package(admittedBy: decision, closure: closure, forWrite: forWrite)
        case .unavailable:
            throw InspectionPackageFailureV2.bundledPackageUnavailable
        }
    }
}

enum BundledInspectionPackageRegistryV2 {
    static let source = "BUNDLED_ONLY"
    static let runtimeDownloadsAllowed = false
    static let shippingPackageIDs = [ShippingIlluminatedSignAdapterV1.packageID]
    static let shippingAssetSemanticID = "asset.sign.illuminated.v1"
    static let shippingAssetSemanticReleaseID = UUID(
        uuidString: "b3905cf4-741e-4c39-8c39-000000000001"
    )!
    static let shippingAssetSemanticReleasedAt = Date(
        timeIntervalSince1970: 1_735_689_600
    )
    static let shippingMeasurementProtocolReleaseID = UUID(
        uuidString: "c4000000-0000-4000-8000-000000000001"
    )!
    static let shippingMeasurementProtocolID = UUID(
        uuidString: "c4000000-0000-4000-8000-000000000002"
    )!
    static let shippingDerivedEvaluatorDescriptorID = UUID(
        uuidString: "c4000000-0000-4000-8000-000000000003"
    )!

    /// Localization is a sidecar release binding. The package's canonical V2
    /// bytes and release identity remain unchanged.
    static func shippingLocalizationSlotBindings() throws
        -> [PackageLocalizationSlotBindingV1] {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        return try package.advisoryGuidance.map {
            PackageLocalizationSlotBindingV1(
                slotID: "advisoryGuidance.\($0.guidanceID)",
                localizationKey: try LocalizationKeyV1($0.localizationKey)
            )
        }
    }

    static func localizationBinding(
        publication: InspectionPackagePublishedReleaseV1,
        localizationRelease: LocalizationCatalogReleaseV1,
        registry: LocalizationKeyRegistryV1
    ) throws -> PackageLocalizationReleaseBindingV1 {
        try PackageLocalizationReleaseBindingV1(
            publication: publication,
            localizationRelease: localizationRelease,
            slotBindings: try shippingLocalizationSlotBindings(),
            registry: registry
        )
    }

    static func shippingAssetSemanticCatalog() throws -> AssetSemanticCatalogReleaseV1 {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let identity = try PackageReleaseIdentityV1(
            packageID: package.packageID,
            schemaVersion: InspectionPackageV2.schemaVersion,
            contentVersion: package.contentVersion
        )
        let capabilities = try package.capabilities.map {
            try AssetSemanticCapabilityIDV1("inspection.\($0.rawValue.lowercased())")
        }
        let definition = try AssetKindDefinitionV1(
            semanticID: shippingAssetSemanticID,
            displayNameLocalizationKey: "asset.semantic.sign.illuminated.name",
            descriptionLocalizationKey: "asset.semantic.sign.illuminated.description",
            capabilityIDs: capabilities,
            compatibilityPolicy: .exactReleaseOnly
        )
        return try AssetSemanticCatalogReleaseV1(
            releaseID: shippingAssetSemanticReleaseID,
            packageRelease: identity,
            revision: 1,
            definitions: [definition],
            releasedAt: shippingAssetSemanticReleasedAt
        )
    }

    static func shippingAuthorityCriterionBinding(
        workspaceID: WorkspaceID,
        recordedAt: Date
    ) throws -> InspectionPackageAuthorityCriterionBindingV1 {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let packageRelease = try PackageReleaseIdentityV1(
            packageID: package.packageID,
            schemaVersion: package.schemaVersion,
            contentVersion: package.contentVersion
        )
        let descriptor = try BundledDerivedFactEvaluatorRegistryV1.descriptor(
            descriptorID: shippingDerivedEvaluatorDescriptorID,
            workspaceID: workspaceID,
            kind: .identityCanonical,
            inputDimension: .illuminance,
            recordedAt: recordedAt
        )
        let measurementProtocol = try MeasurementProtocolReleaseV1(
            releaseID: shippingMeasurementProtocolReleaseID,
            workspaceID: workspaceID,
            protocolID: shippingMeasurementProtocolID,
            designation: "Illuminance observation screening protocol",
            dimension: .illuminance,
            normativeUnitID: "lx",
            samplingPolicy: .single,
            minimumSampleCount: 1,
            maximumSampleCount: 1,
            missingSamplePolicy: .inconclusive,
            outlierPolicy: .retainAll,
            duplicatePolicy: .reject,
            requiresUncertainty: false,
            evaluatorDescriptorID: descriptor.descriptorID,
            recordedAt: recordedAt
        )
        let binding = try InspectionPackageAuthorityCriterionBindingV1(
            workspaceID: workspaceID,
            packageRelease: packageRelease,
            criterionIDs: [],
            measurementProtocolReleases: [measurementProtocol],
            evaluatorDescriptors: [descriptor]
        )
        try AuthorityCriterionPackageCompatibilityRegistryV1.validate(binding, package: package)
        return binding
    }

    /// Shipping currently declares no functional edge vocabulary. Returning an
    /// exact empty sidecar is deliberate: C41 does not infer a lighting graph
    /// from asset kinds or inspection capabilities.
    static func shippingFunctionalRelationshipBinding(
        workspaceID: WorkspaceID
    ) throws -> InspectionPackageFunctionalRelationshipBindingV1 {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        return try InspectionPackageFunctionalRelationshipBindingV1(
            workspaceID: workspaceID,
            packageRelease: PackageReleaseIdentityV1(
                packageID: package.packageID,
                schemaVersion: package.schemaVersion,
                contentVersion: package.contentVersion
            ),
            descriptorReleases: []
        )
    }

    static func shippingDraftRelease(
        workflow: WorkflowDefinitionV1
    ) throws -> InspectionPackageReleaseV1 {
        try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: workflow
        )
    }

    static func load(bundle: Bundle = .main) -> BundledInspectionPackageRegistryLoadResultV2 {
        guard case let .available(signPack) = SignPackLoader.loadBundled(bundle: bundle) else {
            return .unavailable(.bundledPackageUnavailable)
        }
        do {
            let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage(from: signPack)
            let publication = try InspectionPackageRegistryPublisherV2.publish(packages: [package])
            let parity = try ShippingIlluminatedSignAdapterV1.parityReceipt()
            guard publication.registry.orderedPackageIDs == Self.shippingPackageIDs,
                  parity.exactParity else {
                return .unavailable(.incompatiblePackage)
            }
            return .available(
                registry: publication.registry,
                receipt: publication.receipt,
                parity: parity
            )
        } catch let failure as InspectionPackageFailureV2 {
            return .unavailable(failure)
        } catch {
            return .unavailable(.invalidValue)
        }
    }
}
