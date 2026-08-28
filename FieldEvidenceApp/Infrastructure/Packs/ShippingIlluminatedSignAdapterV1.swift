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

struct LegacySignCouldNotVerifyValueV1: Equatable, Sendable {
    let reasonKey: String
    let frozenDisplay: String
    let registryVersion: String
}

struct LegacySignResponseSourceV1: Equatable, Sendable {
    let acknowledgementValues: [String: Bool]
    let outcomeKey: String?
    let issueKeys: [String]
    let couldNotVerify: LegacySignCouldNotVerifyValueV1?
    let note: String?
    let entityReference: ResponseEntityReferenceV1?
    let contentReference: ResponseContentReferenceIDV1?

    init(
        acknowledgementValues: [String: Bool] = [:],
        outcomeKey: String? = nil,
        issueKeys: [String] = [],
        couldNotVerify: LegacySignCouldNotVerifyValueV1? = nil,
        note: String? = nil,
        entityReference: ResponseEntityReferenceV1? = nil,
        contentReference: ResponseContentReferenceIDV1? = nil
    ) {
        self.acknowledgementValues = acknowledgementValues
        self.outcomeKey = outcomeKey
        self.issueKeys = issueKeys
        self.couldNotVerify = couldNotVerify
        self.note = note
        self.entityReference = entityReference
        self.contentReference = contentReference
    }
}

struct LegacySignTypedResponseEntryV1: Codable, Equatable, Sendable {
    let fieldID: String
    let value: ResponseValueV1
}

struct LegacySignTypedResponseMappingReceiptV1: Equatable, Sendable {
    let packageID: String
    let packageContentVersion: Int
    let couldNotVerifyRegistryVersion: String
    let couldNotVerifyFrozenDisplay: String?
    let shippingPackCanonicalSHA256: String
    let orderedFieldIDs: [String]
    let canonicalResponsesSHA256: String
    let exactSemanticParity: Bool
    let inventedMeasurementCount: Int
}

struct LegacySignTypedResponseMappingV1: Equatable, Sendable {
    let responses: [LegacySignTypedResponseEntryV1]
    let receipt: LegacySignTypedResponseMappingReceiptV1
}

enum ShippingIlluminatedSignAdapterV1 {
    static let packageID = SignPack.illuminatedSignPackageID

    static func inspectionPackage(
        from source: SignPack = .illuminatedSignV1
    ) throws -> InspectionPackageV2 {
        // The bundled V1 resource remains the canonical shipping parity
        // source, while successor content versions may reuse this typed
        // adapter after passing the closed loader contract.
        guard SignPackLoader.valid(source),
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
        guard package.packageID == packageID, package.contentVersion > 0,
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
        guard SignPackLoader.valid(result), result.packID == packageID else {
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

    /// The only sign-specific response mapping. The neutral inspection kernel
    /// remains package-agnostic and receives only its closed typed values.
    static func typedResponses(
        from source: LegacySignResponseSourceV1,
        signPack: SignPack = .illuminatedSignV1
    ) throws -> LegacySignTypedResponseMappingV1 {
        guard SignPackLoader.valid(signPack),
              signPack.packID == packageID else {
            throw ResponseContractFailureV1.invalidValue
        }
        let acknowledgementKeys = signPack.acknowledgements.map(\.key)
        guard Set(source.acknowledgementValues.keys).isSubset(of: Set(acknowledgementKeys)) else {
            throw ResponseContractFailureV1.unknownKind
        }
        let outcomeKeys = Set(signPack.outcomeDisplays.map(\.key))
        if let outcomeKey = source.outcomeKey, !outcomeKeys.contains(outcomeKey) {
            throw ResponseContractFailureV1.unknownKind
        }
        let issueKeys = source.issueKeys.sorted()
        guard Set(issueKeys).count == issueKeys.count,
              Set(issueKeys).isSubset(of: Set(signPack.issueLabels.map(\.key))) else {
            throw ResponseContractFailureV1.invalidValue
        }
        let cnvEntries = Dictionary(uniqueKeysWithValues:
            signPack.couldNotVerifyReasons.entries.map { ($0.key, $0.display) }
        )
        if let cnv = source.couldNotVerify {
            guard source.outcomeKey == "could_not_verify",
                  cnv.registryVersion == signPack.couldNotVerifyReasons.version,
                  cnvEntries[cnv.reasonKey] == cnv.frozenDisplay else {
                throw ResponseContractFailureV1.invalidValue
            }
        } else if source.outcomeKey == "could_not_verify" {
            throw ResponseContractFailureV1.invalidValue
        }
        if source.outcomeKey != "could_not_verify", source.couldNotVerify != nil {
            throw ResponseContractFailureV1.invalidValue
        }
        if let note = source.note, note.utf8.count > ResponseValueV1.maximumTextUTF8Bytes {
            throw ResponseContractFailureV1.limitExceeded
        }

        var responses = acknowledgementKeys.map { key in
            LegacySignTypedResponseEntryV1(
                fieldID: "legacy.acknowledgement.\(key)",
                value: source.acknowledgementValues[key].map(ResponseValueV1.boolean) ?? .noValue
            )
        }
        responses.append(.init(
            fieldID: "legacy.outcome",
            value: source.outcomeKey.map(ResponseValueV1.singleOption) ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.issues",
            value: issueKeys.isEmpty ? .noValue : .multipleOptions(issueKeys)
        ))
        responses.append(.init(
            fieldID: "legacy.could_not_verify.reason",
            value: source.couldNotVerify.map { .singleOption($0.reasonKey) } ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.note",
            value: source.note.map(ResponseValueV1.text) ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.entity_reference",
            value: source.entityReference.map(ResponseValueV1.entityReference) ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.content_reference",
            value: source.contentReference.map(ResponseValueV1.contentReference) ?? .noValue
        ))
        responses.sort { $0.fieldID < $1.fieldID }
        try responses.forEach { try $0.value.validate() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(responses)
        let packageParity = try parityReceipt()
        return LegacySignTypedResponseMappingV1(
            responses: responses,
            receipt: LegacySignTypedResponseMappingReceiptV1(
                packageID: signPack.packID,
                packageContentVersion: signPack.contentVersion,
                couldNotVerifyRegistryVersion: signPack.couldNotVerifyReasons.version,
                couldNotVerifyFrozenDisplay: source.couldNotVerify?.frozenDisplay,
                shippingPackCanonicalSHA256: packageParity.sourceCanonicalSHA256,
                orderedFieldIDs: responses.map(\.fieldID),
                canonicalResponsesSHA256: digest(bytes),
                exactSemanticParity: true,
                inventedMeasurementCount: 0
            )
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
