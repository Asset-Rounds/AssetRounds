import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_22LocalizationAccessibilityTests: XCTestCase {
    func testV9_22G01CompilerExtractedCatalogAndShippingLocaleTruth() throws {
        let value = try corpus()
        XCTAssertEqual(value.schema, "V23-P03-C16-LocalizationAccessibilityCorpusV1")
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertEqual(value.runtimeUI.shippingLocale, "en")
        XCTAssertEqual(value.runtimeUI.primaryMetadataLocale, "en-US")
        XCTAssertEqual(value.runtimeUI.acceptedShippingLocales, ["en"])
        XCTAssertEqual(value.catalog.sourceLanguage, "en")
        XCTAssertEqual(value.catalog.extraction, "compiler")
        XCTAssertEqual(value.catalog.shippingLocales, ["en"])
        XCTAssertTrue(value.catalog.missingKeys.isEmpty)
        XCTAssertTrue(value.catalog.orphanKeys.isEmpty)

        let catalogKeys = value.catalog.keys.map(\.key)
        XCTAssertEqual(Set(catalogKeys).count, catalogKeys.count)
        XCTAssertTrue(value.catalog.keys.allSatisfy { entry in
            !entry.key.isEmpty && !entry.comment.isEmpty && !entry.meaning.isEmpty
        })
        XCTAssertTrue(value.catalog.keys.contains { !$0.plural.isEmpty })

        let registry = try BundledLocalizationCatalogV1.registry()
        try registry.validate()
        XCTAssertEqual(Set(registry.definitions.map { $0.key.rawValue }), Set(catalogKeys))
        let localeManifest = LocalizationLocaleManifestV1.shippingV1()
        try localeManifest.validate()
        XCTAssertEqual(localeManifest.sourceLanguage, value.catalog.sourceLanguage)
        XCTAssertEqual(localeManifest.shippingRuntimeLanguages, [value.runtimeUI.shippingLocale])
        XCTAssertEqual(
            localeManifest.completeCatalogLanguages,
            value.runtimeUI.completeCatalogLocales
        )
        XCTAssertEqual(
            Set(localeManifest.testOnlyPseudoLocaleIdentifiers),
            Set(value.runtimeUI.pseudoLocales.map(\.locale))
        )

        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let packageBinding = try XCTUnwrap(
            value.packageBindings.first { $0.packageID == package.packageID }
        )
        let packageKeys = package.advisoryGuidance.map(\.localizationKey)
        XCTAssertTrue(packageKeys.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(packageBinding.slotKeys, packageKeys)
        let slotBindings = try BundledInspectionPackageRegistryV2.shippingLocalizationSlotBindings()
        XCTAssertEqual(slotBindings.map { $0.localizationKey.rawValue }, packageKeys)

        let sourceCatalog = try sourceCatalogData()
        let legacy = try legacyAllowlist()
        let packagePublication = try publishedShippingPackage()
        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalog,
            packagePublications: [packagePublication],
            legacy: legacy
        )
        guard case let .complete(
            registry: publishedRegistry,
            accessibility: publishedAccessibility,
            legacy: publishedLegacy,
            packageBindings: publishedPackageBindings,
            receipt: receipt
        ) = publication else {
            return XCTFail("A valid source catalog must publish as one complete declaration")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(publishedLegacy, legacy)
        let publishedPackageBinding = try XCTUnwrap(publishedPackageBindings.first)
        let expectedSlotBindings = try BundledInspectionPackageRegistryV2
            .shippingLocalizationSlotBindings()
        XCTAssertEqual(
            publishedPackageBinding.packageReleaseID,
            packagePublication.release.packageReleaseID
        )
        XCTAssertEqual(
            publishedPackageBinding.orderedSlotBindings,
            expectedSlotBindings.sorted { $0.slotID < $1.slotID }
        )
        XCTAssertEqual(receipt.packageBindingSHA256s.count, 1)
        try publishedPackageBinding.validate(
            publication: packagePublication,
            localizationRelease: receipt.release,
            registry: publishedRegistry
        )
        XCTAssertFalse(receipt.persistentWriteOccurred)
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))
        XCTAssertEqual(
            publishedAccessibility.entries.map(\.semanticID),
            [
                "feedback.mail.attachment-count",
                "feedback.mail.body",
                "feedback.mail.done",
                "feedback.mail.recipient",
                "feedback.mail.screen",
            ]
        )

        let catalogURL = repositoryRootURL()
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: catalogURL.path),
            "C16 requires the sole runtime Localizable.xcstrings catalog"
        )
        guard FileManager.default.fileExists(atPath: catalogURL.path) else { return }
        let catalogObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        XCTAssertEqual(catalogObject["sourceLanguage"] as? String, "en")
        XCTAssertEqual(catalogObject["version"] as? String, "1.0")
        let extracted = try XCTUnwrap(catalogObject["strings"] as? [String: Any])
        XCTAssertTrue(Set(catalogKeys).isSubset(of: Set(extracted.keys)))

        let infoPlistCatalog = try infoPlistCatalogObject()
        XCTAssertEqual(infoPlistCatalog["sourceLanguage"] as? String, "en")
        let permissionKeys = try XCTUnwrap(infoPlistCatalog["strings"] as? [String: Any])
        XCTAssertEqual(Set(permissionKeys.keys), ["NSCameraUsageDescription"])
        let camera = try XCTUnwrap(permissionKeys["NSCameraUsageDescription"] as? [String: Any])
        let localizations = try XCTUnwrap(camera["localizations"] as? [String: Any])
        let english = try XCTUnwrap(localizations["en"] as? [String: Any])
        let stringUnit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
        XCTAssertEqual(
            stringUnit["value"] as? String,
            "Use the camera to add sign photos to reports stored on this iPhone."
        )
    }

    func testV9_22A01TestOnlyPseudoLocalesAndLocaleAwarePresentationRemainBounded() throws {
        let value = try corpus()
        XCTAssertEqual(value.presentation.numberFormatting, "locale-aware")
        XCTAssertEqual(value.presentation.dateFormatting, "locale-aware")
        XCTAssertEqual(value.presentation.unitFormatting, "locale-aware")
        XCTAssertEqual(value.presentation.canonicalDataFormatting, "en_US_POSIX")
        XCTAssertTrue(value.presentation.canonicalUnitIDsUnlocalized)

        let pseudo = value.runtimeUI.pseudoLocales
        XCTAssertEqual(
            Set(pseudo.map(\.locale)),
            ["en-XA", "en-XB", "ar-XB", "en-XL", "en-XT"]
        )
        XCTAssertTrue(pseudo.allSatisfy { $0.testOnly && !$0.shipping })
        XCTAssertEqual(pseudo.first { $0.locale == "ar-XB" }?.direction, "rtl")
        XCTAssertTrue(pseudo.allSatisfy { !value.runtimeUI.acceptedShippingLocales.contains($0.locale) })
        XCTAssertFalse(value.runtimeUI.acceptedShippingLocales.contains(value.runtimeUI.primaryMetadataLocale))
        XCTAssertFalse(value.permissionCatalog.pseudoLocalesShipping)

        let manifest = LocalizationLocaleManifestV1.shippingV1()
        XCTAssertEqual(
            Set(manifest.testOnlyPseudoLocaleIdentifiers),
            Set(pseudo.map(\.locale))
        )
        XCTAssertFalse(manifest.testOnlyPseudoLocaleIdentifiers.contains("en-US"))
        XCTAssertFalse(manifest.testOnlyPseudoLocaleIdentifiers.contains("en"))

        let number = BundledLocalizationCatalogV1.formattedInteger(
            1_234,
            regionSource: Locale(identifier: "de_DE")
        )
        let length = BundledLocalizationCatalogV1.formattedLength(
            Measurement(value: 2.5, unit: UnitLength.meters),
            regionSource: Locale(identifier: "fr_FR")
        )
        let date = BundledLocalizationCatalogV1.formattedDate(
            Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            regionSource: Locale(identifier: "ja_JP")
        )
        XCTAssertFalse(number.isEmpty)
        XCTAssertFalse(length.isEmpty)
        XCTAssertFalse(date.isEmpty)
    }

    func testV9_22H01MissingDuplicateReassignedAndLocaleDriftInputsFailClosed() throws {
        let value = try corpus()
        let semanticIDs = value.semanticAccessibility.entries.map(\.id)
        XCTAssertEqual(Set(semanticIDs).count, semanticIDs.count)
        XCTAssertTrue(value.semanticAccessibility.entries.allSatisfy { entry in
            entry.id.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
                && !entry.id.isEmpty
                && !entry.labelKey.isEmpty
                && !entry.id.localizedCaseInsensitiveContains("feedback message")
        })
        XCTAssertTrue(value.semanticAccessibility.entries.allSatisfy {
            $0.dynamicOpaqueSuffixPolicy == "NONE"
        })

        let registry = try BundledLocalizationCatalogV1.registry()
        let accessibility = try BundledLocalizationCatalogV1.accessibilityRegistry(
            localization: registry
        )
        XCTAssertEqual(
            Set(accessibility.entries.map(\.semanticID)),
            Set(value.semanticAccessibility.entries.map(\.id))
        )
        XCTAssertEqual(
            Set(accessibility.entries.flatMap(\.deprecatedAliases)),
            Set(value.semanticAccessibility.entries.flatMap(\.deprecatedAliases))
        )
        XCTAssertThrowsError(
            try accessibility.identifier(semanticID: "feedback.mail.missing")
        ) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .invalidAccessibilityBinding)
        }
        XCTAssertThrowsError(try LocalizationKeyV1("Feedback.Mail.Subject"))
        XCTAssertThrowsError(
            try registry.definition(for: LocalizationKeyV1("missing.key"))
        ) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .missingKey)
        }

        XCTAssertEqual(value.legacyAllowlist.baseline, value.legacyAllowlist.current)
        XCTAssertTrue(value.legacyAllowlist.newEntries.isEmpty)
        XCTAssertFalse(value.legacyAllowlist.growthAllowed)
        XCTAssertEqual(
            Set(BundledLocalizationCatalogV1.inheritedMailAccessibilityIDs),
            Set(value.legacyAllowlist.baseline)
        )

        let legacy = try legacyAllowlist()
        try legacy.validate()
        XCTAssertEqual(legacy.entries.count, value.legacyAllowlist.baseline.count)
        let growth = LegacyLocalizationAccessibilityEntryV1(
            kind: .phaseAccessibilityID,
            stableFingerprint: KernelCanonicalHashV1.sha256(Data("s8.4.mail.new".utf8))
        )
        XCTAssertThrowsError(try legacy.validateObserved(legacy.entries + [growth])) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .legacyAllowlistGrowth)
        }
        let grownLegacy = try LegacyLocalizationAccessibilityAllowlistV1(
            entries: legacy.entries + [growth]
        )
        XCTAssertThrowsError(
            try BundledLocalizationCatalogV1.publish(
                sourceCatalogBytes: sourceCatalogData(),
                legacy: grownLegacy
            )
        ) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .legacyAllowlistGrowth)
        }

        let activeKey = try LocalizationKeyV1("fixture.active")
        let deprecatedKey = try LocalizationKeyV1("fixture.deprecated")
        let activeDefinition = LocalizationKeyDefinitionV1(
            key: activeKey, meaningID: "fixture.active", translatorComment: "Active fixture key.",
            englishDefaultValue: "Active", arguments: [], requiredEnglishPluralCategories: [],
            state: .active, deprecatedFallbackKey: nil
        )
        let deprecatedDefinition = LocalizationKeyDefinitionV1(
            key: deprecatedKey, meaningID: "fixture.deprecated",
            translatorComment: "Deprecated fixture key.", englishDefaultValue: "Deprecated",
            arguments: [], requiredEnglishPluralCategories: [], state: .deprecated,
            deprecatedFallbackKey: activeKey
        )
        let hostileRegistry = try LocalizationKeyRegistryV1(
            definitions: [activeDefinition, deprecatedDefinition]
        )
        XCTAssertThrowsError(
            try SemanticAccessibilityIDRegistryV1(
                entries: [AccessibilityContractV1(
                    semanticID: "fixture.control", role: .button, reachability: .always,
                    labelKey: activeKey, hintKey: deprecatedKey, valueKey: nil,
                    dynamicSuffixPolicy: .none, deprecatedAliases: []
                )],
                localization: hostileRegistry
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalizationContractFailureV1,
                .invalidAccessibilityBinding
            )
        }

        let catalogKeys = Set(value.catalog.keys.map(\.key))
        for binding in value.packageBindings {
            XCTAssertEqual(Set(binding.slotKeys).count, binding.slotKeys.count)
            XCTAssertTrue(Set(binding.slotKeys).isSubset(of: catalogKeys))
            XCTAssertFalse(binding.catalogReleaseID.isEmpty)
            XCTAssertEqual(binding.deprecatedKeyFallback, "deterministic-source-locale")
        }

        let hostileIDs = Set(value.hostileCases.map(\.id))
        for required in [
            "V23-P03-C16-H01-MISSING_KEY",
            "V23-P03-C16-H01-DUPLICATE_ID",
            "V23-P03-C16-H01-ALLOWLIST_GROWTH",
            "V23-P03-C16-H01-PACKAGE_REMOVED_KEY",
            "V23-P03-C16-H01-CANONICAL_LOCALE_DRIFT",
        ] {
            XCTAssertTrue(hostileIDs.contains(required), "missing hostile case \(required)")
        }
        XCTAssertTrue(value.hostileCases.allSatisfy { $0.expectedResult == "REJECT" })
    }

    func testV9_22I01InterruptedExtractionLeavesNoPartialCatalogOrBinding() throws {
        let value = try corpus()
        XCTAssertGreaterThanOrEqual(value.interruptionCases.count, 2)
        XCTAssertTrue(value.interruptionCases.allSatisfy {
            $0.id.hasPrefix("V23-P03-C16-I01-") && $0.expectedResult == "NO_PARTIAL_ACCEPTANCE"
        })
        XCTAssertTrue(value.catalog.missingKeys.isEmpty)
        XCTAssertTrue(value.catalog.orphanKeys.isEmpty)
        XCTAssertTrue(value.packageBindings.allSatisfy { !$0.catalogReleaseID.isEmpty })

        let sourceCatalog = try sourceCatalogData()
        let legacy = try legacyAllowlist()
        for boundary in LocalizationCatalogPublicationBoundaryV1.allCases {
            XCTAssertThrowsError(
                try BundledLocalizationCatalogV1.publish(
                    sourceCatalogBytes: sourceCatalog,
                    legacy: legacy,
                    interruption: { reached in
                        if reached == boundary {
                            throw LocalizationContractFailureV1.partialPublication
                        }
                    }
                )
            ) { error in
                XCTAssertEqual(error as? LocalizationContractFailureV1, .partialPublication)
            }
        }
        XCTAssertEqual(
            try BundledLocalizationCatalogV1.recover(
                sourceCatalogBytes: nil, receipt: nil, legacy: legacy
            ),
            .zero
        )
        XCTAssertThrowsError(
            try BundledLocalizationCatalogV1.recover(
                sourceCatalogBytes: sourceCatalog, receipt: nil, legacy: legacy
            )
        ) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .partialPublication)
        }
    }

    func testV9_22R01FrozenDisplayAndPackageDigestsRecoverIdempotently() throws {
        let value = try corpus()
        XCTAssertTrue(value.frozenDisplay.localeInvariant)
        XCTAssertTrue(value.frozenDisplay.historicOutputByteIdentical)
        XCTAssertTrue(value.frozenDisplay.canonicalIDsUnlocalized)
        XCTAssertEqual(value.frozenDisplay.canonicalLocale, "en_US_POSIX")
        XCTAssertTrue(value.frozenDisplay.canonicalFormats.contains("ISO8601"))
        XCTAssertTrue(value.frozenDisplay.canonicalFormats.contains("en_US_POSIX"))

        XCTAssertTrue(value.frozenDisplay.historicFixtureDigests.allSatisfy { digest in
            digest.sha256.count == 64
                && digest.sha256.utf8.allSatisfy {
                    (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
                }
        })
        XCTAssertTrue(value.recoveryCases.contains {
            $0.id == "V23-P03-C16-R01-RETRY_SAME_DIGEST" && $0.expectedResult == "IDEMPOTENT"
        })
        XCTAssertTrue(value.recoveryCases.contains {
            $0.id == "V23-P03-C16-R01-HISTORIC_BYTES_PRESERVED" && $0.expectedResult == "PRESERVED"
        })

        let historic = try Data(contentsOf: repositoryRootURL()
            .appendingPathComponent("FieldEvidenceAppTests/Fixtures/S3_3ReportSnapshotV1.json"))
        let historicReport = try ReportSnapshotEncoderV1().decode(historic)
        let snapshot = try FrozenDisplaySnapshotV1(reportSnapshot: historicReport)
        XCTAssertEqual(snapshot.canonicalBytes, historic)
        XCTAssertEqual(snapshot.sha256, KernelCanonicalHashV1.sha256(historic))
        XCTAssertEqual(
            value.frozenDisplay.historicFixtureDigests.first {
                $0.fixtureID == "S3_3ReportSnapshotV1.json"
            }?.sha256,
            snapshot.sha256
        )
        try snapshot.validateUnchanged(reportSnapshot: historicReport)
        var changedHistoric = historic
        changedHistoric[changedHistoric.startIndex] ^= 1
        XCTAssertThrowsError(
            try snapshot.validateUnchanged(
                canonicalBytes: changedHistoric,
                sha256: KernelCanonicalHashV1.sha256(changedHistoric)
            )
        ) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .frozenDisplayChanged)
        }

        let sourceCatalog = try sourceCatalogData()
        let legacy = try legacyAllowlist()
        let first = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalog, legacy: legacy
        )
        guard case let .complete(_, _, _, _, receipt) = first else {
            return XCTFail("A complete catalog receipt is required before recovery")
        }
        let recovered = try BundledLocalizationCatalogV1.recover(
            sourceCatalogBytes: sourceCatalog, receipt: receipt, legacy: legacy
        )
        XCTAssertEqual(recovered, first)
    }

    private func corpus() throws -> Corpus {
        try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: try fixtureURL()))
    }

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        if let url = bundle.url(
            forResource: "V21P03C16LocalizationAccessibilityCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Localization"
        ) {
            return url
        }
        return repositoryRootURL()
            .appendingPathComponent(
                "FieldEvidenceAppTests/Fixtures/V21/Localization/V21P03C16LocalizationAccessibilityCorpusV1.json"
            )
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func infoPlistCatalogObject() throws -> [String: Any] {
        let url = repositoryRootURL().appendingPathComponent("FieldEvidenceApp/InfoPlist.xcstrings")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func sourceCatalogData() throws -> Data {
        try Data(contentsOf: repositoryRootURL()
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings"))
    }

    private func legacyAllowlist() throws -> LegacyLocalizationAccessibilityAllowlistV1 {
        try BundledLocalizationCatalogV1.mailLegacyAllowlist()
    }

    private func publishedShippingPackage() throws -> InspectionPackagePublishedReleaseV1 {
        let workflow = try WorkflowDefinitionV1(
            workflowID: "fixture.localization.binding.v1",
            entryNodeID: "node.section",
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "node.section",
                    kind: .section,
                    localizationKey: "workflow.section",
                    outgoingNodeIDs: ["node.terminal"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.terminal",
                    kind: .terminal,
                    localizationKey: "workflow.terminal",
                    outgoingNodeIDs: []
                ),
            ]
        )
        let draft = try BundledInspectionPackageRegistryV2.shippingDraftRelease(
            workflow: workflow
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        return try InspectionPackageReleasePublisherV1.publish(tested)
    }

    private struct Corpus: Decodable {
        let schema: String
        let schemaVersion: Int
        let runtimeUI: RuntimeUI
        let catalog: Catalog
        let permissionCatalog: PermissionCatalog
        let presentation: Presentation
        let semanticAccessibility: SemanticAccessibility
        let legacyAllowlist: LegacyAllowlist
        let packageBindings: [PackageBinding]
        let frozenDisplay: FrozenDisplay
        let goldenCases: [EvidenceCase]
        let alternateCases: [EvidenceCase]
        let hostileCases: [EvidenceCase]
        let interruptionCases: [EvidenceCase]
        let recoveryCases: [EvidenceCase]
    }

    private struct RuntimeUI: Decodable {
        let shippingLocale: String
        let primaryMetadataLocale: String
        let acceptedShippingLocales: [String]
        let completeCatalogLocales: [String]
        let pseudoLocales: [PseudoLocale]
    }

    private struct PseudoLocale: Decodable {
        let locale: String
        let direction: String
        let purpose: String
        let testOnly: Bool
        let shipping: Bool
    }

    private struct Catalog: Decodable {
        let path: String
        let sourceLanguage: String
        let version: String
        let extraction: String
        let shippingLocales: [String]
        let missingKeys: [String]
        let orphanKeys: [String]
        let keys: [CatalogKey]
    }

    private struct CatalogKey: Decodable {
        let key: String
        let comment: String
        let meaning: String
        let value: String
        let plural: [String: String]
    }

    private struct PermissionCatalog: Decodable {
        let path: String
        let owner: String
        let sourceLanguage: String
        let keys: [String]
        let shippingLocales: [String]
        let pseudoLocalesShipping: Bool
    }

    private struct Presentation: Decodable {
        let numberFormatting: String
        let dateFormatting: String
        let unitFormatting: String
        let canonicalDataFormatting: String
        let canonicalUnitIDsUnlocalized: Bool
    }

    private struct SemanticAccessibility: Decodable {
        let registry: String
        let contract: String
        let registryVersion: Int
        let entries: [SemanticEntry]
    }

    private struct SemanticEntry: Decodable {
        let id: String
        let role: String
        let reachability: String
        let labelKey: String
        let hintKey: String?
        let valueKey: String?
        let dynamicOpaqueSuffixPolicy: String
        let deprecatedAliases: [String]
    }

    private struct LegacyAllowlist: Decodable {
        let registry: String
        let version: Int
        let baseline: [String]
        let current: [String]
        let newEntries: [String]
        let growthAllowed: Bool
    }

    private struct PackageBinding: Decodable {
        let packageID: String
        let packageContentVersion: Int
        let slotKeys: [String]
        let catalogReleaseID: String
        let catalogKeyDigest: String
        let deprecatedKeyFallback: String
    }

    private struct FrozenDisplay: Decodable {
        let registry: String
        let snapshotID: String
        let canonicalLocale: String
        let canonicalFormats: [String]
        let localeInvariant: Bool
        let historicOutputByteIdentical: Bool
        let canonicalIDsUnlocalized: Bool
        let historicFixtureDigests: [FixtureDigest]
    }

    private struct FixtureDigest: Decodable {
        let fixtureID: String
        let sha256: String
    }

    private struct EvidenceCase: Decodable {
        let id: String
        let classification: String
        let expectedResult: String
        let reason: String
    }
}
