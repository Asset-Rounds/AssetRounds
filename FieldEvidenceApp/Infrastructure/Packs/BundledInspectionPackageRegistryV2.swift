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
