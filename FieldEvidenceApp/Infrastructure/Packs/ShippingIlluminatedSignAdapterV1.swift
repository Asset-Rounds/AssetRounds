import CryptoKit
import Foundation

struct ShippingIlluminatedSignParityReceiptV1: Equatable, Sendable {
    let packageID: String
    let sourceSchemaVersion: Int
    let sourceContentVersion: Int
    let inspectionPackageSchemaVersion: Int
    let sourceCanonicalSHA256: String
    let roundTripCanonicalSHA256: String
    let exactParity: Bool
}

enum ShippingIlluminatedSignAdapterV1 {
    static let packageID = SignPack.illuminatedSignPackageID

    static func inspectionPackage(
        from source: SignPack = .illuminatedSignV1
    ) throws -> InspectionPackageV2 {
        guard SignPackLoader.valid(source), source == .illuminatedSignV1,
              source.packID == packageID else {
            throw InspectionPackageFailureV2.unknownPackage
        }
        return try InspectionPackageV2(
            packageID: source.packID,
            contentVersion: source.contentVersion,
            capabilities: [
                .photoCapture,
                .photoImport,
                .visibleIssueClassification,
                .couldNotVerify,
                .recheck,
                .workEvidence,
            ],
            permissions: [.camera, .photoLibrarySelection],
            advisoryGuidance: [
                InspectionPackageGuidanceV2(
                    guidanceID: "evidence.required_views",
                    kind: .evidence,
                    localizationKey: "package.illuminated_sign.guidance.required_views"
                ),
                InspectionPackageGuidanceV2(
                    guidanceID: "limitation.visible_conditions_only",
                    kind: .limitation,
                    localizationKey: "package.illuminated_sign.guidance.visible_conditions_only"
                ),
                InspectionPackageGuidanceV2(
                    guidanceID: "safety.authorized_position",
                    kind: .safety,
                    localizationKey: "package.illuminated_sign.guidance.authorized_position"
                ),
            ],
            presentation: InspectionPackagePresentationV2(
                assetSingular: source.nouns.asset.singular,
                assetPlural: source.nouns.asset.plural,
                checkSingular: source.nouns.check.singular,
                checkPlural: source.nouns.check.plural,
                issueSingular: source.nouns.issue.singular,
                issuePlural: source.nouns.issue.plural,
                evidencePurposes: source.evidencePurposes.map {
                    InspectionPackageEvidencePurposeV2(
                        key: $0.key,
                        display: $0.display,
                        instruction: $0.instruction
                    )
                },
                acknowledgements: source.acknowledgements.map {
                    InspectionPackageAcknowledgementV2(
                        key: $0.key,
                        copy: $0.copy,
                        version: $0.version
                    )
                },
                issueLabels: entries(source.issueLabels),
                couldNotVerifyRegistryVersion: source.couldNotVerifyReasons.version,
                couldNotVerifyReasons: entries(source.couldNotVerifyReasons.entries),
                stageDisplays: entries(source.stageDisplays),
                outcomeDisplays: entries(source.outcomeDisplays),
                disclaimer: source.disclaimer
            )
        )
    }

    static func signPack(from package: InspectionPackageV2) throws -> SignPack {
        try InspectionPackageCompatibilityValidatorV2.validate(package)
        let expected = try inspectionPackage()
        guard package.packageID == packageID, package.contentVersion == 1,
              package.capabilities == expected.capabilities,
              package.permissions == expected.permissions,
              package.advisoryGuidance == expected.advisoryGuidance else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        let value = package.presentation
        let result = SignPack(
            schemaVersion: 1,
            packID: package.packageID,
            contentVersion: package.contentVersion,
            nouns: .init(
                asset: .init(singular: value.assetSingular, plural: value.assetPlural),
                check: .init(singular: value.checkSingular, plural: value.checkPlural),
                issue: .init(singular: value.issueSingular, plural: value.issuePlural)
            ),
            evidencePurposes: value.evidencePurposes.map {
                .init(key: $0.key, display: $0.display, instruction: $0.instruction)
            },
            acknowledgements: value.acknowledgements.map {
                .init(key: $0.key, copy: $0.copy, version: $0.version)
            },
            issueLabels: signEntries(value.issueLabels),
            couldNotVerifyReasons: .init(
                version: value.couldNotVerifyRegistryVersion,
                entries: signEntries(value.couldNotVerifyReasons)
            ),
            stageDisplays: signEntries(value.stageDisplays),
            outcomeDisplays: signEntries(value.outcomeDisplays),
            disclaimer: value.disclaimer
        )
        guard result == .illuminatedSignV1 else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        return result
    }

    static func parityReceipt() throws -> ShippingIlluminatedSignParityReceiptV1 {
        let source = SignPack.illuminatedSignV1
        let package = try inspectionPackage(from: source)
        let roundTrip = try signPack(from: package)
        let sourceData = try canonicalSignPack(source)
        let roundTripData = try canonicalSignPack(roundTrip)
        return ShippingIlluminatedSignParityReceiptV1(
            packageID: source.packID,
            sourceSchemaVersion: source.schemaVersion,
            sourceContentVersion: source.contentVersion,
            inspectionPackageSchemaVersion: package.schemaVersion,
            sourceCanonicalSHA256: digest(sourceData),
            roundTripCanonicalSHA256: digest(roundTripData),
            exactParity: sourceData == roundTripData && source == roundTrip
        )
    }

    private static func entries(
        _ values: [SignPack.RegistryEntry]
    ) -> [InspectionPackageDisplayEntryV2] {
        values.map { InspectionPackageDisplayEntryV2(key: $0.key, display: $0.display) }
    }

    private static func signEntries(
        _ values: [InspectionPackageDisplayEntryV2]
    ) -> [SignPack.RegistryEntry] {
        values.map { SignPack.RegistryEntry(key: $0.key, display: $0.display) }
    }

    private static func canonicalSignPack(_ value: SignPack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
