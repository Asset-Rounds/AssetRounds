import Foundation

enum BundledInspectionPackageRegistryLoadResultV2: Equatable, Sendable {
    case available(
        registry: InspectionPackageRegistryV2,
        receipt: InspectionPackageRegistryPublicationReceiptV2,
        parity: ShippingIlluminatedSignParityReceiptV1
    )
    case unavailable(InspectionPackageFailureV2)
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
