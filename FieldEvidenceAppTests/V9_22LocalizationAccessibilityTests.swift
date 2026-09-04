import Foundation
import XCTest
@testable import FieldEvidenceApp

private final class V23P04C16LocalizationAccessibilityContractTests: XCTestCase {
    func testC16TypedShellLocalizationCatalogIsClosedAndEnglishOnly() throws {
        try C16ShellLocalizationPolicyV1.validate()
        let keys = C16ShellLocalizationKeyV1.allCases
        XCTAssertEqual(keys.count, 37)
        XCTAssertEqual(Set(keys.map(\.rawValue)).count, 37)
        XCTAssertEqual(C16ShellLocalizationPolicyV1.shippingLocales, ["en"])
        XCTAssertEqual(C16ShellLocalizationPolicyV1.pseudoLocales, ["en-XA", "ar-XB"])
        XCTAssertFalse(C16ShellLocalizationPolicyV1.runtimeDownloadsAllowed)
        XCTAssertFalse(C16ShellLocalizationPolicyV1.uiAdoptionClaimed)
        XCTAssertTrue(C16ShellLocalizationPolicyV1.requiresAcceptedS10_6Reconciliation)

        let registry = try BundledLocalizationCatalogV1.c16ShellRegistry()
        for key in keys {
            let definition = try registry.definition(for: LocalizationKeyV1(key.rawValue))
            XCTAssertEqual(definition.englishDefaultValue, key.englishDefaultValue)
            XCTAssertFalse(definition.englishDefaultValue.isEmpty)
        }
    }

    func testC16FourRootAndReasonBearingAccessibilitySemanticsAreStable() throws {
        try C16ShellAccessibilityPolicyV1.validate()
        XCTAssertEqual(C16ShellAccessibilityPolicyV1.rootIDs, [.today, .work, .assets, .reports])
        XCTAssertEqual(C16ShellAccessibilityPolicyV1.rootBindings.map(\.role), [.button, .button, .button, .button])
        XCTAssertTrue(C16ShellAccessibilityPolicyV1.stateAndReasonAreTextualNotColorOnly)
        XCTAssertTrue(C16ShellAccessibilityPolicyV1.rightToLeftMirroringRequired)
        XCTAssertTrue(C16ShellAccessibilityPolicyV1.pseudoLocaleExpansionRequired)
        XCTAssertFalse(C16ShellAccessibilityPolicyV1.uiAdoptionClaimed)
        XCTAssertEqual(WorkspaceExperienceRootV1.canonicalShellOrder, [.today, .work, .assets, .reports])
        XCTAssertEqual(WorkspaceExperienceAvailabilityReasonV1.allCases.count, 10)
        XCTAssertEqual(
            Set(WorkspaceExperienceAvailabilityReasonV1.allCases.map {
                C16ShellLocalizationKeyV1.availabilityReason($0).rawValue
            }).count,
            10
        )
        for reason in WorkspaceExperienceAvailabilityReasonV1.allCases {
            let key = C16ShellLocalizationKeyV1.availabilityReason(reason)
            let presentation = try FeatureAvailabilityPresentationV1(
                featureKey: "shell.feature.\(reason.rawValue.lowercased())",
                isAvailable: reason == .available,
                reason: reason,
                explanationKey: key.rawValue
            )
            XCTAssertEqual(presentation.reason, reason)
            XCTAssertEqual(presentation.explanationKey, key.rawValue)
        }
        XCTAssertEqual(WorkspaceResumeDispositionV1.allCases.count, 3)
        XCTAssertFalse(WorkspaceExperienceDataPolicyV1.restoreAutomaticallyRestartsWork)
    }

    func testC16ProvisionalFixtureMatchesTypedLocalizationAndAccessibilityBoundary() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Localization/V23P04C16ShellAccessibilityLocalizationCorpusV1.json")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(root["schema"] as? String, "V23P04C16ShellAccessibilityLocalizationCorpusV1")
        XCTAssertEqual(root["cardID"] as? String, "V23-P04-C16")
        XCTAssertEqual(root["rootOrder"] as? [String], ["TODAY", "WORK", "ASSETS", "REPORTS"])
        let localization = try XCTUnwrap(root["localization"] as? [String: Any])
        XCTAssertEqual(localization["keyCount"] as? Int, C16ShellLocalizationKeyV1.allCases.count)
        XCTAssertEqual(localization["shippingLocales"] as? [String], ["en"])
        let boundary = try XCTUnwrap(root["provisionalBoundary"] as? [String: Any])
        XCTAssertEqual(boundary["uiAdoptionClaimed"] as? Bool, false)
        XCTAssertEqual(boundary["shippingUIClaimed"] as? Bool, false)
        XCTAssertEqual(boundary["requiresAcceptedS10_6Reconciliation"] as? Bool, true)
        XCTAssertEqual((root["hostileCases"] as? [[String: Any]])?.count, 6)
        XCTAssertEqual((root["selectors"] as? [String])?.count, 5)
    }
}

private enum C52ServiceRequestBoundary_V9_22LocalizationAccessibilityTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V9_22LocalizationAccessibilityTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private final class C45LocalizationAccessibilityCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityIncludesAccessibleTextAndClosedDisclosures() {
        XCTAssertTrue(LabelArtifactKindV1.allCases.contains(.structuredText))
        XCTAssertEqual(LabelDisclosureProfileV1.allCases.count, 3)
        XCTAssertEqual(LabelDisclosureProfileV1.assetLocationAndShortCode.rawValue, "ASSET_LOCATION_AND_SHORT_CODE")
    }
}

private final class C51V922LocalizationAccessibilityAnchorTests: XCTestCase {
    func testV23P03C51ScheduleLocalizationAndAccessibilityAreTypedWithoutUIClaim() throws {
        XCTAssertEqual(ScheduleLocalizationKeyV1.recurrenceKey(for: .advanced(
            AdvancedScheduleConfigurationV1(
                recurrence: .daily(interval: 1),
                calendarRelease: AllDaysCompatibilityCalendarV1.reference(
                    workspaceID: WorkspaceID(rawValue: UUID(
                        uuidString: "51000000-0000-4000-8000-000000000922")!)),
                businessDayAdjustmentPolicy: .nextIncludedDay))), .advancedRecurrence)
        XCTAssertEqual(ScheduleAccessibilityIDV1.advancedRecurrence.localizationKey,
                       ScheduleLocalizationKeyV1.advancedRecurrence.localizationKey)
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.rtlReadingOrderRequired)
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.dynamicTypeRequired)
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.voiceOverLabelAndValueRequired)
        XCTAssertFalse(ScheduleAccessibilityPolicyV1.uiConformanceClaimed)
    }
}

private final class C30EvidenceContextAnchorV9_22LocalizationAccessibility: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

@MainActor
final class V9_22LocalizationAccessibilityTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
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

    func testV30P01C04PresentationAxisBridgePreservesInheritedCatalogTruth() throws {
        let manifest = LocalizationLocaleManifestV1.shippingV1()
        let registry = try BundledLocalizationCatalogV1.registry()
        try V30LocalizationAxisBridgeV1.validate(manifest: manifest, registry: registry)

        XCTAssertEqual(
            V30LocalizationAxisBridgeV1.declaredAppLanguages.map(\.rawValue),
            ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
        )
        XCTAssertEqual(manifest.sourceLanguage, "en")
        XCTAssertEqual(manifest.shippingRuntimeLanguages, ["en"])
        XCTAssertEqual(manifest.completeCatalogLanguages, ["en"])
        XCTAssertEqual(manifest.appStorePrimaryMetadataLocale, "en-US")
        XCTAssertFalse(V30LocalizationAxisBridgeV1.finalLocaleCatalogClaimed)
        XCTAssertEqual(
            V30LocalizationAxisBridgeV1.presentationCapabilities().map(\.catalogAvailability),
            [.inheritedEnglishCatalog, .declaredPendingCatalogCompletion, .declaredPendingCatalogCompletion,
             .declaredPendingCatalogCompletion, .declaredPendingCatalogCompletion, .declaredPendingCatalogCompletion]
        )

        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.languageOrFormattingChangesCanonicalIdentity)
        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.backupIncludesAxisPreferences)
        XCTAssertNoThrow(try GlobalizationCanonicalIdentityBoundaryV1.validateNoCanonicalIdentityMutation([]))
        XCTAssertFalse(BundledLocalizationCatalogV1.formattedInteger(
            1_234, regionSource: Locale(identifier: "es-US")
        ).isEmpty)
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

        XCTAssertEqual(value.legacyAllowlist.baseline, value.legacyAllowlist.testSupportAliases)
        XCTAssertTrue(value.legacyAllowlist.current.isEmpty)
        XCTAssertTrue(value.legacyAllowlist.newEntries.isEmpty)
        XCTAssertFalse(value.legacyAllowlist.growthAllowed)
        XCTAssertFalse(value.legacyAllowlist.productionParserEnabled)
        XCTAssertTrue(accessibility.entries.allSatisfy { $0.deprecatedAliases.isEmpty })
        XCTAssertTrue(try productionMailLegacyReferences().isEmpty)

        let legacy = try legacyAllowlist()
        try legacy.validate()
        XCTAssertTrue(legacy.entries.isEmpty)
        XCTAssertNoThrow(try legacy.validateObserved([]))
        let growth = LegacyLocalizationAccessibilityEntryV1(
            kind: .phaseAccessibilityID,
            stableFingerprint: KernelCanonicalHashV1.sha256(Data("s8.4.mail.new".utf8))
        )
        XCTAssertThrowsError(try legacy.validateObserved([growth])) { error in
            XCTAssertEqual(error as? LocalizationContractFailureV1, .legacyAllowlistGrowth)
        }
        let grownLegacy = try LegacyLocalizationAccessibilityAllowlistV1(
            entries: [growth]
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

    func testV23P03C38AccessibilityLocalizationMetadataIsTestOnlyAndNonIdentifying() throws {
        let root = repositoryRootURL()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let localization = try XCTUnwrap(fixture["localizationAccessibility"] as? [String: Any])
        XCTAssertEqual(localization["sourceLanguage"] as? String, "en")
        XCTAssertEqual(localization["shippingLocales"] as? [String], ["en"])
        XCTAssertEqual(
            Set(localization["pseudoLocalesTestOnly"] as? [String] ?? []),
            Set(["en-XA", "en-XB", "ar-XB", "en-XL", "en-XT"])
        )
        XCTAssertEqual(localization["rtlRequired"] as? Bool, true)
        XCTAssertEqual(localization["dynamicTypeRequired"] as? Bool, true)
        XCTAssertEqual(localization["voiceOverRequired"] as? Bool, true)
        XCTAssertEqual(localization["voiceControlRequired"] as? Bool, true)
        XCTAssertEqual(localization["switchControlRequired"] as? Bool, true)
        XCTAssertEqual(localization["nonColorStateTextRequired"] as? Bool, true)
        XCTAssertEqual((localization["semanticIDs"] as? [String])?.count, 7)

        let claims = try XCTUnwrap(fixture["claims"] as? [String: Any])
        XCTAssertTrue(claims.values.allSatisfy { ($0 as? Bool) == false })
        let appRoot = root.appendingPathComponent("FieldEvidenceApp", isDirectory: true)
        let appSwiftSources = try XCTUnwrap(
            FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        )
        let appSource = try appSwiftSources
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertFalse(appSource.contains("accessibilityIdentifier(\"party.email\")"))
    }

    func testV23P03C39TypedSemanticLocalizationAndAccessibilitySurfaceIsEnglishOnly() throws {
        let registry = try BundledLocalizationCatalogV1.assetSemanticRegistry()
        try registry.validate()

        let expectedKeys = Set(AssetSemanticLocalizationKeyV1.allCases.map(\.rawValue))
        let registeredKeys = Set(registry.definitions.map { $0.key.rawValue })
        XCTAssertTrue(expectedKeys.isSubset(of: registeredKeys))
        XCTAssertEqual(
            Set(AssetSemanticLocalizationPolicyV1.keys),
            expectedKeys
        )
        XCTAssertEqual(AssetSemanticLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(AssetSemanticLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(AssetSemanticLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertTrue(AssetSemanticLocalizationPolicyV1.excludesOperationalDisposition)
        XCTAssertTrue(AssetSemanticLocalizationPolicyV1.excludesIdentityClaims)
        XCTAssertTrue(AssetSemanticLocalizationPolicyV1.progressivelyDisclosedProductIdentity)
        XCTAssertEqual(
            Set(AssetSemanticLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )

        let accessibility = try BundledLocalizationCatalogV1
            .assetSemanticAccessibilityRegistry(localization: registry)
        XCTAssertEqual(
            Set(accessibility.entries.map(\.semanticID)),
            Set(AssetSemanticAccessibilityIDV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(AssetSemanticLocalizationPolicyV1.semanticIDs),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(accessibility.entries.allSatisfy {
            $0.dynamicSuffixPolicy == .none && $0.deprecatedAliases.isEmpty
        })
        XCTAssertTrue(accessibility.entries.contains {
            $0.semanticID == AssetSemanticAccessibilityIDV1.unknownState.rawValue
                && $0.role == .status
        })
        XCTAssertTrue(accessibility.entries.contains {
            $0.semanticID == AssetSemanticAccessibilityIDV1.duplicateState.rawValue
                && $0.role == .status
        })
        XCTAssertTrue(accessibility.entries.contains {
            $0.semanticID == AssetSemanticAccessibilityIDV1.retiredState.rawValue
                && $0.role == .status
        })
        XCTAssertTrue(accessibility.entries.contains {
            $0.semanticID == AssetSemanticAccessibilityIDV1.replacedState.rawValue
                && $0.role == .status
        })
        for semanticID in AssetSemanticAccessibilityIDV1.allCases {
            XCTAssertEqual(
                try accessibility.identifier(semanticID: semanticID.rawValue),
                semanticID.rawValue
            )
        }

        let source = try JSONSerialization.jsonObject(
            with: sourceCatalogData()
        ) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        for key in AssetSemanticLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            XCTAssertFalse((entry["comment"] as? String ?? "").isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            XCTAssertFalse((unit["value"] as? String ?? "").isEmpty)
            let bundledKey = try XCTUnwrap(
                BundledLocalizationKeyV1(rawValue: key.rawValue)
            )
            XCTAssertEqual(
                BundledLocalizationCatalogV1.localized(bundledKey),
                try XCTUnwrap(unit["value"] as? String)
            )
        }

        let hostile = AccessibilityContractV1(
            semanticID: AssetSemanticAccessibilityIDV1.heading.rawValue,
            role: .heading,
            reachability: .always,
            labelKey: AssetSemanticLocalizationKeyV1.heading.localizationKey,
            hintKey: nil,
            valueKey: nil,
            dynamicSuffixPolicy: .none,
            deprecatedAliases: []
        )
        XCTAssertThrowsError(
            try SemanticAccessibilityIDRegistryV1(
                entries: accessibility.entries + [hostile],
                localization: registry
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalizationContractFailureV1,
                .duplicateSemanticID
            )
        }
    }

    func testV23P03C40AuthorityCriterionLocalizationAndNonColorSemanticsAreEnglishOnly() throws {
        let registry = try BundledLocalizationCatalogV1.authorityCriterionRegistry()
        try registry.validate()

        let expectedKeys = Set(AuthorityCriterionLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(AuthorityCriterionLocalizationPolicyV1.keys), expectedKeys)
        XCTAssertTrue(expectedKeys.isSubset(of: Set(registry.definitions.map { $0.key.rawValue })))
        XCTAssertEqual(AuthorityCriterionLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(AuthorityCriterionLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(AuthorityCriterionLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertEqual(
            Set(AuthorityCriterionLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(AuthorityCriterionLocalizationPolicyV1.requiredReportWording, "assessed against")
        XCTAssertEqual(
            ApplicabilityDispositionV1.allCases.map {
                AuthorityCriterionLocalizationKeyV1.applicabilityKey($0).rawValue
            },
            [
                "authority.criterion.applicability.applicable",
                "authority.criterion.applicability.not_applicable_with_reason",
                "authority.criterion.applicability.unknown",
                "authority.criterion.applicability.conflict_review_required",
                "authority.criterion.applicability.unsupported",
            ]
        )
        XCTAssertEqual(
            ScreeningCriterionResultV1.allCases.map {
                AuthorityCriterionLocalizationKeyV1.resultKey($0).rawValue
            },
            [
                "authority.criterion.result.meets_screening_criterion",
                "authority.criterion.result.does_not_meet",
                "authority.criterion.result.inconclusive",
                "authority.criterion.result.not_evaluated",
            ]
        )
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesLicensedSourceText)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesRawMeasurementSamples)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesQualificationDetail)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesUnsupportedClaims)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(AuthorityCriterionLocalizationPolicyV1.allowsColorOnlySeverity)
        XCTAssertFalse(AuthorityCriterionLocalizationPolicyV1.allowsIconOnlyState)

        let accessibility = try BundledLocalizationCatalogV1
            .authorityCriterionAccessibilityRegistry(localization: registry)
        let c40IDs = Set(AuthorityCriterionAccessibilityIDV1.allCases.map(\.rawValue))
        let accessibilityIDs = Set(accessibility.entries.map(\.semanticID))
        XCTAssertTrue(c40IDs.isSubset(of: accessibilityIDs))
        XCTAssertEqual(Set(AuthorityCriterionAccessibilityPolicyV1.semanticIDs), c40IDs)
        XCTAssertTrue(accessibility.entries.allSatisfy {
            $0.dynamicSuffixPolicy == .none && $0.deprecatedAliases.isEmpty
        })

        let entriesByID = Dictionary(uniqueKeysWithValues: accessibility.entries.map {
            ($0.semanticID, $0)
        })
        for semanticID in AuthorityCriterionAccessibilityIDV1.allCases {
            let entry = try XCTUnwrap(entriesByID[semanticID.rawValue])
            XCTAssertEqual(
                try accessibility.identifier(semanticID: semanticID.rawValue),
                semanticID.rawValue
            )
            XCTAssertTrue(
                registry.definitions.contains { $0.key == entry.labelKey },
                "missing localized label for \(semanticID.rawValue)"
            )
        }
        for semanticID in AuthorityCriterionAccessibilityPolicyV1.indeterminateSemanticIDs {
            let entry = try XCTUnwrap(entriesByID[semanticID])
            XCTAssertEqual(entry.role, .status)
            XCTAssertNotNil(entry.hintKey, "\(semanticID) needs an actionable next-step hint")
            XCTAssertTrue(AuthorityCriterionAccessibilityPolicyV1.requiresTextAndIcon(for: semanticID))
            XCTAssertTrue(AuthorityCriterionAccessibilityPolicyV1.requiresActionableNextStep(for: semanticID))
        }
        XCTAssertFalse(AuthorityCriterionAccessibilityPolicyV1.colorOnlySeverityAllowed)
        XCTAssertFalse(AuthorityCriterionAccessibilityPolicyV1.iconOnlyStatusAllowed)

        let source = try JSONSerialization.jsonObject(with: sourceCatalogData()) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        var c40Values = [String]()
        for key in AuthorityCriterionLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            c40Values.append(contentsOf: [comment, value])
            let bundledKey = try XCTUnwrap(BundledLocalizationKeyV1(rawValue: key.rawValue))
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(bundledKey), value)
        }
        XCTAssertTrue(c40Values.contains("Assessed against"))
        XCTAssertFalse(
            AuthorityCriterionLocalizationPolicyV1.containsProhibitedClaim(in: c40Values)
        )

        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalogData(),
            legacy: legacyAllowlist(),
            includeAuthorityCriteria: true
        )
        guard case let .complete(
            publishedRegistry, publishedAccessibility, _, _, receipt
        ) = publication else {
            return XCTFail("C40 requires one complete authority-criterion catalog publication")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(
            Set(publishedAccessibility.entries.map(\.semanticID)),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))

    }

    func testV23P03C40ReportLabelsAreTypedAndAuthorityHostilesFailClosed() throws {
        XCTAssertEqual(
            Set(ReportAuthorityCriterionProjectionPolicyV1.localizationKeys.map(\.rawValue)),
            Set(AuthorityCriterionLocalizationPolicyV1.reportKeys)
        )
        XCTAssertEqual(
            ReportAuthorityCriterionProjectionPolicyV1.applicabilityLocalizationKey(.applicable),
            .applicabilityApplicable
        )
        XCTAssertEqual(
            ReportAuthorityCriterionProjectionPolicyV1.applicabilityLocalizationKey(.conflictReviewRequired),
            .applicabilityConflictReviewRequired
        )
        XCTAssertEqual(
            ReportAuthorityCriterionProjectionPolicyV1.resultLocalizationKey(.meetsScreeningCriterion),
            .resultMeetsScreeningCriterion
        )
        XCTAssertEqual(
            ReportAuthorityCriterionProjectionPolicyV1.resultLocalizationKey(.notEvaluated),
            .resultNotEvaluated
        )

        let hostileAuthorityText = [
            "safe-compliant-certified-copy-leak",
            "Legal research engine",
            "GPS-derived jurisdiction",
            "automatic legal precedence or AHJ selection",
            "automatic compliance or safety score",
            "licensed source text",
            "web-updated standards",
            "user-authored evaluator or script",
            "full UCUM or second unit system",
            "second reference store",
            "package-specific table or writer",
            "S10 release or brand approval",
        ]
        for value in hostileAuthorityText {
            XCTAssertTrue(
                AuthorityCriterionClaimVocabularyV1.containsProhibitedClaim(in: [value]),
                "hostile authority text escaped claim vocabulary: \(value)"
            )
        }
        XCTAssertFalse(
            AuthorityCriterionClaimVocabularyV1.containsProhibitedClaim(
                in: ["Observed reading", "safely recorded", "professional association"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://authority.example/source", "file:///Users/private/source"]
            )
        )
    }

    func testV23P03C41FunctionalRelationshipLocalizationAndAccessibilityIsEnglishOnly() throws {
        let registry = try BundledLocalizationCatalogV1.functionalRelationshipRegistry()
        try registry.validate()

        let expectedKeys = Set(FunctionalRelationshipLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(FunctionalRelationshipLocalizationPolicyV1.keys), expectedKeys)
        XCTAssertTrue(expectedKeys.isSubset(of: Set(registry.definitions.map { $0.key.rawValue })))
        XCTAssertEqual(FunctionalRelationshipLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(FunctionalRelationshipLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(FunctionalRelationshipLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.directionTextRequired)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.stateTextRequired)
        XCTAssertEqual(
            Set(FunctionalRelationshipLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(FunctionalRelationshipLocalizationPolicyV1.reportKeys),
            expectedKeys
        )

        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.directionKey(.directed),
            .directedSourceToTarget
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.directionKey(.undirected),
            .symmetric
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.symmetryKey(.symmetric),
            .symmetric
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.symmetryKey(.asymmetric),
            .directedSourceToTarget
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.eventStateKey(.added),
            .activeState
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.eventStateKey(.ended),
            .endedState
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.eventStateKey(.superseded),
            .supersededState
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.readinessStateKey(.incomplete),
            .incompleteState
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.dispositionStateKey(.reviewRequired),
            .blockedState
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.sitePolicyKey(.sameSiteRequired),
            .site
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.sitePolicyKey(.crossSiteLocalAllowed),
            .crossSiteState
        )
        XCTAssertEqual(
            FunctionalRelationshipLocalizationKeyV1.minimumRequirementKey(.readiness),
            .minimumNextRequirement
        )

        let accessibility = try BundledLocalizationCatalogV1
            .functionalRelationshipAccessibilityRegistry(localization: registry)
        let expectedIDs = Set(FunctionalRelationshipAccessibilityIDV1.allCases.map(\.rawValue))
        let accessibilityIDs = Set(accessibility.entries.map(\.semanticID))
        XCTAssertTrue(expectedIDs.isSubset(of: accessibilityIDs))
        XCTAssertEqual(Set(FunctionalRelationshipAccessibilityPolicyV1.semanticIDs), expectedIDs)
        XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.directionTextRequired)
        XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.stateTextRequired)
        XCTAssertTrue(accessibility.entries.allSatisfy {
            $0.dynamicSuffixPolicy == .none && $0.deprecatedAliases.isEmpty
        })

        let entriesByID = Dictionary(uniqueKeysWithValues: accessibility.entries.map {
            ($0.semanticID, $0)
        })
        for semanticID in FunctionalRelationshipAccessibilityIDV1.allCases {
            let entry = try XCTUnwrap(entriesByID[semanticID.rawValue])
            XCTAssertEqual(
                try accessibility.identifier(semanticID: semanticID.rawValue),
                semanticID.rawValue
            )
            XCTAssertTrue(
                registry.definitions.contains { $0.key == entry.labelKey },
                "missing localized label for \(semanticID.rawValue)"
            )
        }
        for semanticID in FunctionalRelationshipAccessibilityPolicyV1.stateSemanticIDs {
            XCTAssertEqual(try XCTUnwrap(entriesByID[semanticID]).role, .status)
        }
        for semanticID in FunctionalRelationshipAccessibilityPolicyV1.indeterminateSemanticIDs {
            let entry = try XCTUnwrap(entriesByID[semanticID])
            XCTAssertNotNil(entry.hintKey, "\(semanticID) needs a minimum next requirement")
            XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.requiresTextAndIcon(for: semanticID))
            XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.requiresActionableNextStep(for: semanticID))
        }
        XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.nonColorStateTextRequired)
        XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.textAndIconRequiredForIndeterminateStates)
        XCTAssertTrue(FunctionalRelationshipAccessibilityPolicyV1.actionableNextStepRequired)
        XCTAssertFalse(FunctionalRelationshipAccessibilityPolicyV1.colorOnlyStateAllowed)
        XCTAssertFalse(FunctionalRelationshipAccessibilityPolicyV1.iconOnlyStateAllowed)

        let source = try JSONSerialization.jsonObject(with: sourceCatalogData()) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        var c41Text = [String]()
        for key in FunctionalRelationshipLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            c41Text.append(contentsOf: [comment, value])
            let bundledKey = try XCTUnwrap(BundledLocalizationKeyV1(rawValue: key.rawValue))
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(bundledKey), value)
        }
        XCTAssertTrue(c41Text.contains("Source to target"))
        XCTAssertTrue(c41Text.contains("Minimum requirement"))
        XCTAssertFalse(
            FunctionalRelationshipLocalizationPolicyV1.containsProhibitedClaim(in: c41Text)
        )
        XCTAssertFalse(
            FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(
                in: ["Observed source to target association", "safely recorded"]
            )
        )
        XCTAssertTrue(
            FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(
                in: [
                    "ownership asserted", "authorization granted", "compliance status",
                    "safety result", "telemetry enabled", "remote command",
                ]
            )
        )

        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalogData(),
            legacy: legacyAllowlist(),
            includeFunctionalRelationships: true
        )
        guard case let .complete(
            publishedRegistry, publishedAccessibility, _, _, receipt
        ) = publication else {
            return XCTFail("C41 requires one complete functional-relationship catalog publication")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(
            Set(publishedAccessibility.entries.map(\.semanticID)),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))
    }

    func testV23P03C13EvidenceVisibilityLocalizationAndAccessibilityIsEnglishOnly() throws {
        let registry = try BundledLocalizationCatalogV1.evidenceVisibilityRegistry()
        try registry.validate()

        let expectedKeys = Set(EvidenceVisibilityLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(EvidenceVisibilityLocalizationPolicyV1.keys), expectedKeys)
        XCTAssertEqual(Set(EvidenceVisibilityLocalizationPolicyV1.reportKeys), expectedKeys)
        XCTAssertTrue(expectedKeys.isSubset(of: Set(registry.definitions.map { $0.key.rawValue })))
        XCTAssertEqual(EvidenceVisibilityLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(EvidenceVisibilityLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(EvidenceVisibilityLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertEqual(
            Set(EvidenceVisibilityLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresExplicitAudience)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresRecordedSensitivity)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(EvidenceVisibilityLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(EvidenceVisibilityLocalizationPolicyV1.allowsIconOnlyState)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.excludesCustomerDataLeakage)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.excludesPrivateLocators)

        for audience in EvidenceAudienceV1.allCases {
            XCTAssertTrue(expectedKeys.contains(EvidenceVisibilityLocalizationKeyV1.audienceKey(audience).rawValue))
        }
        for sensitivity in EvidenceSensitivityV1.allCases {
            XCTAssertTrue(expectedKeys.contains(EvidenceVisibilityLocalizationKeyV1.sensitivityKey(sensitivity).rawValue))
        }
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.inclusionKey(.included), .included
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.inclusionKey(.excluded), .excluded
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.limitationKey(.audienceNotDeclared), .unknown
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.limitationKey(.sensitivityRestricted), .limitation
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.limitationKey(.evidenceUnavailable), .omitted
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.previewStateKey(.ready), .previewReady
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.previewStateKey(.stale), .previewStale
        )
        for purpose in AttestationPurposeV1.allCases {
            XCTAssertEqual(
                EvidenceVisibilityLocalizationKeyV1.attestationPurposeKey(purpose),
                .attestationPurpose
            )
        }
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.attestationActionKey(.recorded),
            .attestationRecorded
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.attestationActionKey(.superseded),
            .attestationSuperseded
        )
        XCTAssertEqual(
            EvidenceVisibilityLocalizationKeyV1.attestationActionKey(.voided),
            .attestationVoid
        )

        let accessibility = try BundledLocalizationCatalogV1
            .evidenceVisibilityAccessibilityRegistry(localization: registry)
        let expectedIDs = Set(EvidenceVisibilityAccessibilityIDV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(EvidenceVisibilityAccessibilityPolicyV1.semanticIDs), expectedIDs)
        XCTAssertTrue(expectedIDs.isSubset(of: Set(accessibility.entries.map(\.semanticID))))
        XCTAssertTrue(EvidenceVisibilityAccessibilityPolicyV1.denyByDefault)
        XCTAssertTrue(EvidenceVisibilityAccessibilityPolicyV1.nonColorStateTextRequired)
        XCTAssertTrue(EvidenceVisibilityAccessibilityPolicyV1.textAndIconRequiredForIndeterminateStates)
        XCTAssertTrue(EvidenceVisibilityAccessibilityPolicyV1.actionableNextStepRequired)
        XCTAssertFalse(EvidenceVisibilityAccessibilityPolicyV1.colorOnlyStateAllowed)
        XCTAssertFalse(EvidenceVisibilityAccessibilityPolicyV1.iconOnlyStateAllowed)
        XCTAssertTrue(accessibility.entries.allSatisfy {
            $0.dynamicSuffixPolicy == .none && $0.deprecatedAliases.isEmpty
        })

        let entriesByID = Dictionary(uniqueKeysWithValues: accessibility.entries.map {
            ($0.semanticID, $0)
        })
        for semanticID in EvidenceVisibilityAccessibilityIDV1.allCases {
            let entry = try XCTUnwrap(entriesByID[semanticID.rawValue])
            XCTAssertEqual(
                try accessibility.identifier(semanticID: semanticID.rawValue),
                semanticID.rawValue
            )
            XCTAssertTrue(
                registry.definitions.contains { $0.key == entry.labelKey },
                "missing localized label for \(semanticID.rawValue)"
            )
        }
        for semanticID in EvidenceVisibilityAccessibilityPolicyV1.stateSemanticIDs {
            XCTAssertEqual(try XCTUnwrap(entriesByID[semanticID]).role, .status)
        }
        for semanticID in EvidenceVisibilityAccessibilityPolicyV1.indeterminateSemanticIDs {
            let entry = try XCTUnwrap(entriesByID[semanticID])
            XCTAssertNotNil(entry.hintKey, "\(semanticID) needs an actionable next step")
            XCTAssertTrue(EvidenceVisibilityAccessibilityPolicyV1.requiresTextAndIcon(for: semanticID))
            XCTAssertTrue(EvidenceVisibilityAccessibilityPolicyV1.requiresActionableNextStep(for: semanticID))
        }

        let source = try JSONSerialization.jsonObject(with: sourceCatalogData()) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        var c13Text = [String]()
        for key in EvidenceVisibilityLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            c13Text.append(contentsOf: [comment, value])
            let bundledKey = try XCTUnwrap(BundledLocalizationKeyV1(rawValue: key.rawValue))
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(bundledKey), value)
        }
        XCTAssertFalse(EvidenceVisibilityLocalizationPolicyV1.containsProhibitedClaim(in: c13Text))
        XCTAssertFalse(EvidenceVisibilityLocalizationPolicyV1.containsCustomerDataLeakage(in: c13Text))

        let hostileClaims = [
            "approval granted", "authorship recorded", "legal signature",
            "non-repudiation asserted", "tamper-proof archive", "verified identity",
            "secure delivery", "sent successfully", "delivered successfully",
            "compliance result", "professional service", "customer-data leakage",
        ]
        XCTAssertTrue(hostileClaims.allSatisfy {
            EvidenceVisibilityClaimVocabularyV1.containsProhibitedClaim(in: [$0])
        })
        XCTAssertTrue(
            EvidenceVisibilityClaimVocabularyV1.containsCustomerDataLeakage(
                in: ["customer-data leakage", "private data included"]
            )
        )
        XCTAssertFalse(
            EvidenceVisibilityClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded audience scope", "Observed limitation"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://evidence.example/source", "file:///Users/private/evidence"]
            )
        )

        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalogData(),
            legacy: legacyAllowlist(),
            includeEvidenceVisibility: true
        )
        guard case let .complete(
            publishedRegistry, publishedAccessibility, _, _, receipt
        ) = publication else {
            return XCTFail("C13 requires one complete evidence-visibility catalog publication")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(
            Set(publishedAccessibility.entries.map(\.semanticID)),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))
    }

    func testV23P03C14InspectionReviewLocalizationAndAccessibilityIsEnglishOnly() throws {
        let registry = try BundledLocalizationCatalogV1.inspectionReviewRegistry()
        try registry.validate()

        let expectedKeys = Set(InspectionReviewLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(InspectionReviewLocalizationPolicyV1.keys), expectedKeys)
        XCTAssertEqual(Set(InspectionReviewLocalizationPolicyV1.reportKeys), expectedKeys)
        XCTAssertTrue(expectedKeys.isSubset(of: Set(registry.definitions.map { $0.key.rawValue })))
        XCTAssertEqual(InspectionReviewLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(InspectionReviewLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(InspectionReviewLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertEqual(
            Set(InspectionReviewLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(InspectionReviewLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(InspectionReviewLocalizationPolicyV1.allowsIconOnlyState)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.excludesCustomerDataLeakage)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.excludesPrivateLocators)

        for state in InspectionReviewStateV1.allCases {
            XCTAssertTrue(expectedKeys.contains(InspectionReviewLocalizationKeyV1.stateKey(state).rawValue))
        }
        for disposition in ReviewDispositionKindV1.allCases {
            XCTAssertTrue(expectedKeys.contains(InspectionReviewLocalizationKeyV1.dispositionKey(disposition).rawValue))
        }
        for state in ChangeRequestStateV1.allCases {
            XCTAssertTrue(expectedKeys.contains(InspectionReviewLocalizationKeyV1.changeRequestStateKey(state).rawValue))
        }
        for resolution in ChangeRequestResolutionKindV1.allCases {
            XCTAssertTrue(expectedKeys.contains(InspectionReviewLocalizationKeyV1.changeRequestResolutionKey(resolution).rawValue))
        }
        for state in CorrectiveActionStateV1.allCases {
            XCTAssertTrue(expectedKeys.contains(InspectionReviewLocalizationKeyV1.correctiveActionStateKey(state).rawValue))
        }
        XCTAssertEqual(InspectionReviewLocalizationKeyV1.nextStepKey(), .nextStep)
        XCTAssertEqual(InspectionReviewLocalizationKeyV1.minimumRequirementKey(), .minimumNextRequirement)

        let accessibility = try BundledLocalizationCatalogV1
            .inspectionReviewAccessibilityRegistry(localization: registry)
        let expectedIDs = Set(InspectionReviewAccessibilityIDV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(InspectionReviewAccessibilityPolicyV1.semanticIDs), expectedIDs)
        XCTAssertTrue(expectedIDs.isSubset(of: Set(accessibility.entries.map(\.semanticID))))
        XCTAssertTrue(InspectionReviewAccessibilityPolicyV1.denyByDefault)
        XCTAssertTrue(InspectionReviewAccessibilityPolicyV1.nonColorStateTextRequired)
        XCTAssertTrue(InspectionReviewAccessibilityPolicyV1.textAndIconRequiredForIndeterminateStates)
        XCTAssertTrue(InspectionReviewAccessibilityPolicyV1.actionableNextStepRequired)
        XCTAssertFalse(InspectionReviewAccessibilityPolicyV1.colorOnlyStateAllowed)
        XCTAssertFalse(InspectionReviewAccessibilityPolicyV1.iconOnlyStateAllowed)
        XCTAssertTrue(accessibility.entries.allSatisfy {
            $0.dynamicSuffixPolicy == .none && $0.deprecatedAliases.isEmpty
        })

        let entriesByID = Dictionary(uniqueKeysWithValues: accessibility.entries.map {
            ($0.semanticID, $0)
        })
        for semanticID in InspectionReviewAccessibilityIDV1.allCases {
            let entry = try XCTUnwrap(entriesByID[semanticID.rawValue])
            XCTAssertEqual(
                try accessibility.identifier(semanticID: semanticID.rawValue),
                semanticID.rawValue
            )
            XCTAssertTrue(
                registry.definitions.contains { $0.key == entry.labelKey },
                "missing localized label for \(semanticID.rawValue)"
            )
        }
        for semanticID in InspectionReviewAccessibilityPolicyV1.stateSemanticIDs {
            XCTAssertEqual(try XCTUnwrap(entriesByID[semanticID]).role, .status)
        }
        for semanticID in InspectionReviewAccessibilityPolicyV1.indeterminateSemanticIDs {
            let entry = try XCTUnwrap(entriesByID[semanticID])
            XCTAssertNotNil(entry.hintKey, "\(semanticID) needs an actionable next step")
            XCTAssertTrue(InspectionReviewAccessibilityPolicyV1.requiresTextAndIcon(for: semanticID))
            XCTAssertTrue(InspectionReviewAccessibilityPolicyV1.requiresActionableNextStep(for: semanticID))
        }

        let source = try JSONSerialization.jsonObject(with: sourceCatalogData()) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        var c14Text = [String]()
        for key in InspectionReviewLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            c14Text.append(contentsOf: [comment, value])
            let bundledKey = try XCTUnwrap(BundledLocalizationKeyV1(rawValue: key.rawValue))
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(bundledKey), value)
        }
        XCTAssertFalse(InspectionReviewLocalizationPolicyV1.containsProhibitedClaim(in: c14Text))
        XCTAssertFalse(InspectionReviewLocalizationPolicyV1.containsCustomerDataLeakage(in: c14Text))

        let hostileClaims = [
            "approval granted", "authorization granted", "verified identity",
            "legal signature", "compliance result", "tamper-proof history",
            "non-repudiation asserted", "secure delivery", "sent successfully",
            "delivered successfully", "professional certification",
        ]
        XCTAssertTrue(hostileClaims.allSatisfy {
            InspectionReviewClaimVocabularyV1.containsProhibitedClaim(in: [$0])
        })
        XCTAssertTrue(
            InspectionReviewClaimVocabularyV1.containsCustomerDataLeakage(
                in: ["customer data", "customer-information leak", "private data"]
            )
        )
        XCTAssertFalse(
            InspectionReviewClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded review state", "Changes requested", "Awaiting recorded check"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://review.example/request", "file:///Users/private/review"]
            )
        )

        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalogData(),
            legacy: legacyAllowlist(),
            includeInspectionReview: true
        )
        guard case let .complete(
            publishedRegistry, publishedAccessibility, _, _, receipt
        ) = publication else {
            return XCTFail("C14 requires one complete review and corrective-action catalog publication")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(
            Set(publishedAccessibility.entries.map(\.semanticID)),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))
    }

    func testV23P03C15WorkPacketLocalizationAndAccessibilityIsEnglishOnly() throws {
        let registry = try BundledLocalizationCatalogV1.workPacketRegistry()
        try registry.validate()

        let expectedKeys = Set(WorkPacketLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(WorkPacketLocalizationPolicyV1.keys), expectedKeys)
        XCTAssertEqual(Set(WorkPacketLocalizationPolicyV1.reportKeys), expectedKeys)
        XCTAssertEqual(WorkPacketLocalizationPolicyV1.semanticNamespace, "work.packet")
        XCTAssertEqual(WorkPacketLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(WorkPacketLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(WorkPacketLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertEqual(
            Set(WorkPacketLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(WorkPacketLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(WorkPacketLocalizationPolicyV1.allowsIconOnlyState)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesSecrets)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesCustomerData)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesWorkData)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesCustomerDataLeakage)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesUnsupportedClaims)
        XCTAssertTrue(
            expectedKeys.isSubset(of: Set(registry.definitions.map { $0.key.rawValue }))
        )

        let localeManifest = LocalizationLocaleManifestV1.shippingV1()
        try localeManifest.validate()
        XCTAssertEqual(localeManifest.sourceLanguage, "en")
        XCTAssertEqual(localeManifest.shippingRuntimeLanguages, ["en"])
        XCTAssertEqual(localeManifest.completeCatalogLanguages, ["en"])
        XCTAssertEqual(localeManifest.appStorePrimaryMetadataLocale, "en-US")

        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.manifestStateKey("DRAFT"),
            .manifestDraft
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.claimStateKey("AVAILABLE"),
            .claimUnclaimed
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.leaseStateKey("EXPIRED"),
            .leaseExpired
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.releaseStateKey("RECORDED"),
            .releaseRecorded
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.handoffStateKey("COMPLETED"),
            .handoffCompleted
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.conflictStateKey("REVIEW_REQUIRED"),
            .conflictReviewRequired
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.expiryStateKey("NOT_EXPIRED"),
            .expiryNotExpired
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.replayStateKey("IDEMPOTENT"),
            .replayIdempotent
        )
        XCTAssertNil(WorkPacketLocalizationKeyV1.replayStateKey("UNKNOWN"))
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.replayDispositionKey(.apply),
            .replayApplied
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.replayDispositionKey(.idempotentReplay),
            .replayIdempotent
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.replayDispositionKey(.quarantineDivergentBytes),
            .replayQuarantined
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.conflictKindKey(.simultaneousClaim),
            .conflictDetected
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.conflictKindKey(.divergentSameIdentity),
            .conflictQuarantined
        )
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.releaseReasonKey(.leaseExpired),
            .releaseAvailable
        )
        XCTAssertTrue(
            WorkReleaseReasonV1.allCases.allSatisfy {
                WorkPacketLocalizationPolicyV1.stateKeys.contains(
                    WorkPacketLocalizationKeyV1.releaseReasonKey($0).rawValue
                )
            }
        )
        XCTAssertEqual(WorkPacketLocalizationKeyV1.nextStepKey(), .nextStep)
        XCTAssertEqual(
            WorkPacketLocalizationKeyV1.minimumRequirementKey(),
            .minimumNextRequirement
        )

        let accessibility = try BundledLocalizationCatalogV1
            .workPacketAccessibilityRegistry(localization: registry)
        let expectedIDs = Set(WorkPacketAccessibilityIDV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(WorkPacketAccessibilityPolicyV1.semanticIDs), expectedIDs)
        XCTAssertTrue(
            expectedIDs.isSubset(of: Set(accessibility.entries.map(\.semanticID)))
        )
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.denyByDefault)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.nonColorStateTextRequired)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.textAndIconRequiredForIndeterminateStates)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.actionableNextStepRequired)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.rtlRequired)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.dynamicTypeRequired)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.voiceOverRequired)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.voiceControlRequired)
        XCTAssertTrue(WorkPacketAccessibilityPolicyV1.switchControlRequired)
        XCTAssertFalse(WorkPacketAccessibilityPolicyV1.colorOnlyStateAllowed)
        XCTAssertFalse(WorkPacketAccessibilityPolicyV1.iconOnlyStateAllowed)
        XCTAssertTrue(accessibility.entries.allSatisfy {
            $0.dynamicSuffixPolicy == .none && $0.deprecatedAliases.isEmpty
        })

        let entriesByID = Dictionary(uniqueKeysWithValues: accessibility.entries.map {
            ($0.semanticID, $0)
        })
        for semanticID in WorkPacketAccessibilityIDV1.allCases {
            let entry = try XCTUnwrap(entriesByID[semanticID.rawValue])
            XCTAssertEqual(
                try accessibility.identifier(semanticID: semanticID.rawValue),
                semanticID.rawValue
            )
            XCTAssertTrue(
                registry.definitions.contains { $0.key == entry.labelKey },
                "missing localized label for \(semanticID.rawValue)"
            )
        }
        for semanticID in WorkPacketAccessibilityPolicyV1.stateSemanticIDs {
            XCTAssertEqual(try XCTUnwrap(entriesByID[semanticID]).role, .status)
        }
        for semanticID in WorkPacketAccessibilityPolicyV1.indeterminateSemanticIDs {
            let entry = try XCTUnwrap(entriesByID[semanticID])
            XCTAssertNotNil(entry.hintKey, "\(semanticID) needs an actionable next step")
            XCTAssertTrue(WorkPacketAccessibilityPolicyV1.requiresTextAndIcon(for: semanticID))
            XCTAssertTrue(WorkPacketAccessibilityPolicyV1.requiresActionableNextStep(for: semanticID))
        }

        let source = try JSONSerialization.jsonObject(with: sourceCatalogData()) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        var c15Text = [String]()
        for key in WorkPacketLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            c15Text.append(contentsOf: [comment, value])
            let bundledKey = try XCTUnwrap(BundledLocalizationKeyV1(rawValue: key.rawValue))
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(bundledKey), value)
        }
        XCTAssertFalse(WorkPacketLocalizationPolicyV1.containsProhibitedClaim(in: c15Text))
        XCTAssertFalse(WorkPacketLocalizationPolicyV1.containsSensitiveDataLeakage(in: c15Text))

        let hostileClaims = [
            "approval granted", "authorization granted", "verified identity",
            "legal signature", "compliance result", "tamper-proof history",
            "nonrepudiation asserted", "secure delivery", "sent successfully",
            "delivered successfully", "professional certification",
        ]
        XCTAssertTrue(hostileClaims.allSatisfy {
            WorkPacketClaimVocabularyV1.containsProhibitedClaim(in: [$0])
        })
        XCTAssertTrue(
            WorkPacketClaimVocabularyV1.containsSensitiveDataLeakage(
                in: [
                    "customer data", "private data", "personal data", "work-item data",
                    "secret credential", "password", "data leakage",
                ]
            )
        )
        XCTAssertTrue(
            WorkPacketClaimVocabularyV1.containsCustomerDataLeakage(
                in: ["customer information", "work data"]
            )
        )
        XCTAssertFalse(
            WorkPacketClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded packet state", "Lease approaching expiry", "Next step"]
            )
        )

        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalogData(),
            legacy: legacyAllowlist(),
            includeWorkPacket: true
        )
        guard case let .complete(
            publishedRegistry, publishedAccessibility, _, _, receipt
        ) = publication else {
            return XCTFail("C15 requires one complete packet-coordination catalog publication")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(
            Set(publishedAccessibility.entries.map(\.semanticID)),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))
    }

    func testV23P03C36FieldDraftLocalizationAndAccessibilityIsEnglishOnly() throws {
        let expectedKeys = Set(FieldDraftLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(expectedKeys.count, FieldDraftLocalizationKeyV1.allCases.count)
        XCTAssertEqual(Set(FieldDraftLocalizationPolicyV1.keys), expectedKeys)
        XCTAssertEqual(
            Set(FieldDraftLocalizationPolicyV1.semanticIDs),
            Set(FieldDraftAccessibilityIDV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(FieldDraftLocalizationPolicyV1.semanticNamespace, "field.draft")
        XCTAssertEqual(FieldDraftLocalizationPolicyV1.sourceLocale, "en")
        XCTAssertEqual(FieldDraftLocalizationPolicyV1.shippingLocale, "en")
        XCTAssertEqual(FieldDraftLocalizationPolicyV1.metadataLocale, "en-US")
        XCTAssertEqual(
            Set(FieldDraftLocalizationPolicyV1.testOnlyLocales),
            Set(TestOnlyPseudoLocaleV1.allCases.map(\.rawValue))
        )
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.requiresReceiptReadBackForSavedOnThisIPhone)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.readyLocallyIsStagingOnly)
        XCTAssertFalse(FieldDraftLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(FieldDraftLocalizationPolicyV1.allowsIconOnlyState)
        XCTAssertFalse(FieldDraftLocalizationPolicyV1.allowsMotionOnlyState)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesEvidenceTruth)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesReportTruth)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesExportTruth)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesSearchTruth)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesSecrets)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesCustomerData)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesWorkData)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesUnsupportedClaims)

        XCTAssertTrue(FieldDraftStateV1.allCases.allSatisfy {
            FieldDraftLocalizationPolicyV1.stateKeys.contains(
                FieldDraftLocalizationKeyV1.checkpointStateKey($0).rawValue
            )
        })
        XCTAssertTrue(DraftDurabilityPresentationStateV1.allCases.allSatisfy {
            FieldDraftLocalizationPolicyV1.stateKeys.contains(
                FieldDraftLocalizationKeyV1.durabilityStateKey($0).rawValue
            )
        })
        XCTAssertTrue(AttachmentStagingStateV1.allCases.allSatisfy {
            FieldDraftLocalizationPolicyV1.stateKeys.contains(
                FieldDraftLocalizationKeyV1.attachmentStateKey($0).rawValue
            )
        })
        XCTAssertTrue(DraftAttachmentPresentationStateV1.allCases.allSatisfy {
            FieldDraftLocalizationPolicyV1.stateKeys.contains(
                FieldDraftLocalizationKeyV1.attachmentPresentationStateKey($0).rawValue
            )
        })
        XCTAssertTrue(DraftCommitSagaStateV1.allCases.allSatisfy {
            FieldDraftLocalizationPolicyV1.stateKeys.contains(
                FieldDraftLocalizationKeyV1.commitSagaStateKey($0).rawValue
            )
        })
        XCTAssertTrue(DraftRecoveryStatusV1.allCases.allSatisfy {
            FieldDraftLocalizationPolicyV1.stateKeys.contains(
                FieldDraftLocalizationKeyV1.recoveryStateKey($0).rawValue
            )
        })

        let registry = try BundledLocalizationCatalogV1.fieldDraftRegistry()
        try registry.validate()
        let registeredDraftKeys = Set(
            registry.definitions.map(\.key.rawValue).filter { $0.hasPrefix("field.draft.") }
        )
        XCTAssertEqual(registeredDraftKeys, expectedKeys)

        let accessibility = try BundledLocalizationCatalogV1
            .fieldDraftAccessibilityRegistry(localization: registry)
        try accessibility.validate()
        let expectedIDs = Set(FieldDraftAccessibilityIDV1.allCases.map(\.rawValue))
        let entriesByID = Dictionary(uniqueKeysWithValues: accessibility.entries.map {
            ($0.semanticID, $0)
        })
        XCTAssertTrue(expectedIDs.isSubset(of: Set(entriesByID.keys)))
        XCTAssertTrue(FieldDraftAccessibilityPolicyV1.denyByDefault)
        XCTAssertTrue(FieldDraftAccessibilityPolicyV1.nonColorStateTextRequired)
        XCTAssertTrue(FieldDraftAccessibilityPolicyV1.textAndIconRequiredForIndeterminateStates)
        XCTAssertTrue(FieldDraftAccessibilityPolicyV1.actionableNextStepRequired)
        XCTAssertFalse(FieldDraftAccessibilityPolicyV1.colorOnlyStateAllowed)
        XCTAssertFalse(FieldDraftAccessibilityPolicyV1.iconOnlyStateAllowed)
        XCTAssertFalse(FieldDraftAccessibilityPolicyV1.motionOnlyStateAllowed)
        XCTAssertEqual(
            FieldDraftAccessibilityPolicyV1.perItemDynamicSuffixPolicy,
            .opaqueLowercaseHex
        )
        for semanticID in FieldDraftAccessibilityIDV1.allCases {
            let entry = try XCTUnwrap(entriesByID[semanticID.rawValue])
            XCTAssertEqual(entry.labelKey, semanticID.localizationKey.localizationKey)
            XCTAssertTrue(registry.definitions.contains { $0.key == entry.labelKey })
            if FieldDraftAccessibilityPolicyV1.stateSemanticIDs.contains(semanticID.rawValue) {
                XCTAssertEqual(entry.role, .status)
            }
            if FieldDraftAccessibilityPolicyV1.requiresTextAndIcon(for: semanticID.rawValue) {
                XCTAssertNotNil(entry.hintKey)
                XCTAssertTrue(
                    FieldDraftAccessibilityPolicyV1.requiresActionableNextStep(
                        for: semanticID.rawValue
                    )
                )
            }
        }

        let source = try JSONSerialization.jsonObject(with: sourceCatalogData()) as? [String: Any]
        let strings = try XCTUnwrap(source?["strings"] as? [String: Any])
        var text = [String]()
        for key in FieldDraftLocalizationKeyV1.allCases {
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            XCTAssertEqual(
                try XCTUnwrap(entry["comment"] as? String),
                key.translatorComment
            )
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertEqual(value, key.englishDefaultValue)
            text.append(contentsOf: [key.translatorComment, value])
            let bundledKey = try XCTUnwrap(BundledLocalizationKeyV1(rawValue: key.rawValue))
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(bundledKey), value)
        }
        XCTAssertFalse(FieldDraftLocalizationPolicyV1.containsProhibitedClaim(in: text))
        XCTAssertFalse(FieldDraftLocalizationPolicyV1.containsSensitiveDataLeakage(in: text))
        XCTAssertEqual(
            BundledLocalizationCatalogV1.localized(.fieldDraftDurabilitySavedOnThisIPhone),
            "Saved on this iPhone"
        )
        XCTAssertEqual(
            BundledLocalizationCatalogV1.localized(.fieldDraftAttachmentReadyLocal),
            "Ready locally"
        )

        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalogData(),
            legacy: legacyAllowlist(),
            includeFieldDraft: true
        )
        guard case let .complete(
            publishedRegistry, publishedAccessibility, _, _, receipt
        ) = publication else {
            return XCTFail("C36 requires one complete field-draft catalog publication")
        }
        XCTAssertEqual(publishedRegistry, registry)
        XCTAssertEqual(
            Set(publishedAccessibility.entries.map(\.semanticID)),
            Set(accessibility.entries.map(\.semanticID))
        )
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(receipt.release.releaseSHA256))
        let recovered = try BundledLocalizationCatalogV1.recover(
            sourceCatalogBytes: sourceCatalogData(),
            receipt: receipt,
            legacy: legacyAllowlist(),
            includeFieldDraft: true
        )
        guard case let .complete(
            recoveredRegistry, recoveredAccessibility, _, _, recoveredReceipt
        ) = recovered else {
            return XCTFail("C36 recovery must replay the receipt-backed catalog publication")
        }
        XCTAssertEqual(recoveredRegistry, publishedRegistry)
        XCTAssertEqual(recoveredAccessibility, publishedAccessibility)
        XCTAssertEqual(recoveredReceipt, receipt)
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
        try LegacyLocalizationAccessibilityAllowlistV1(entries: [])
    }

    private func productionMailLegacyReferences() throws -> [String] {
        let root = repositoryRootURL().appendingPathComponent("FieldEvidenceApp")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var matches: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  ["swift", "json", "xcstrings", "plist"].contains(url.pathExtension) else {
                continue
            }
            if String(decoding: try Data(contentsOf: url), as: UTF8.self)
                .contains("s8.4.mail.") {
                matches.append(url.path)
            }
        }
        return matches.sorted()
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
        let testSupportAliases: [String]
        let newEntries: [String]
        let growthAllowed: Bool
        let productionParserEnabled: Bool
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

private final class C27V922TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases, [.exactNFC, .asciiCaseInsensitive])
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testV23P03C18LocalizationBindingCanonicalizesOrdering() throws {
        let first = try PackageSemanticReleaseBindingsV1(
            localizationReleaseSHA256: String(repeating: "4", count: 64),
            functionalRelationshipBindingSHA256s: [
                String(repeating: "6", count: 64), String(repeating: "5", count: 64)
            ]
        )
        let second = try PackageSemanticReleaseBindingsV1(
            localizationReleaseSHA256: String(repeating: "4", count: 64),
            functionalRelationshipBindingSHA256s: [
                String(repeating: "5", count: 64), String(repeating: "6", count: 64)
            ]
        )
        XCTAssertEqual(first, second)
    }

    func testV23P03C19LocalizedDisplayCannotChangeCanonicalUnitIdentity() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let first = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.measurement)
        let second = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.measurement)
        XCTAssertEqual(first, second)
        XCTAssertEqual(fixture.measurement.canonicalUnitID, "lx")
        XCTAssertEqual(fixture.measurement.dimension, .illuminance)
        XCTAssertFalse(fixture.measurement.canonicalUnitID.contains("localized"))
    }

    func testC20PrivacyTransformCoordinateNormalizationIsLocaleIndependent() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        XCTAssertEqual(PrivacyTransformValidationV1.coordinateScale, 1_000_000)
        XCTAssertEqual(fixture.regions.map(\.order), [0, 1, 2])
        XCTAssertTrue(fixture.regions.allSatisfy { $0.coordinateSpaceVersion == PrivacyCoordinateSpaceV1.normalizedImage.rawValue })
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferenceAvailabilityV1.allCases.count, 8)
        XCTAssertFalse(FieldReferencePackLifecycleV1.runtimeFetchingAllowed)
        XCTAssertFalse(FieldReferencePackLifecycleV1.drmOrAccountRequired)
    }
}
extension V9_22LocalizationAccessibilityTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleStateV1.allCases.map(\.rawValue), ["DRAFT", "PUBLISHED", "RETIRED"])
        XCTAssertTrue(SurveyDefinitionLimitsV1.token("survey.section.heading"))
        XCTAssertEqual(SurveyDefinitionLifecycleV1.quarantinePersistence, "DERIVED_ONLY")
    }
}
extension V9_22LocalizationAccessibilityTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV922LocalizationAccessibilityTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testV23P03C42LocalizationPresentsTypedArchetypeDispositionThroughShippingCatalog() throws {
        let scenarios = [
            try CompositeAreaSafetyArchetypeV1.scenario(),
            try ControllerZoneDistributionArchetypeV1.scenario()
        ]
        let localization = try BundledLocalizationCatalogV1.registry()
        try localization.validate()

        for scenario in scenarios {
            let replay = try XCTUnwrap(scenario.operations.first { $0.kind == .replay })
            let key: BundledLocalizationKeyV1 =
                replay.expectedDisposition == .idempotentReplay ? .commonDone : .mailMessageLabel
            let definition = try XCTUnwrap(
                localization.definitions.first { $0.key.rawValue == key.rawValue }
            )
            let localized = BundledLocalizationCatalogV1.localized(key)
            XCTAssertEqual(localized, definition.englishDefaultValue)
            XCTAssertEqual(localized, "Done")
            XCTAssertFalse(localized.localizedCaseInsensitiveContains(scenario.archetypeID))
            XCTAssertFalse(
                localized.localizedCaseInsensitiveContains(
                    scenario.capabilities.map(\.rawValue).joined(separator: " ")
                )
            )
        }
    }
}

private final class C33TemporalEvidenceAnchorV922LocalizationAccessibility: XCTestCase {
    func testC33V922LocalizationAccessibilityCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "accessibility.temporal-description",
            kind: .audio,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "accessibility.temporal-description",
            kind: .audio,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV922LocalizationAccessibility: XCTestCase {
    func testC32V922LocalizationAccessibilityCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .factCapture,
            fieldID: "localization.unverified-label",
            value: .text("localized manual value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .factCapture,
            fieldID: "localization.unverified-label",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V922AccessibilityCompatibilityTests: XCTestCase {
    func testC46AccessibilityKeepsExplicitHandoffSemantics() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "accessibility",
            kind: .phone,
            handoff: .text,
            slot: 46022
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift_Tests: XCTestCase {
    func testC47V922LocalizationAccessibilityTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_22LocalizationAccessibilityTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.completionClaimsCommissioningComplianceApprovalOrCertification)
        XCTAssertEqual(Set(ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies).count, 3)
    }
}

private final class C48PortableReviewV922LocalizationTests: XCTestCase {
    func testC48EnglishTrustWordingIsExplicitAndNonSecret() throws {
        try C48PortableReviewLocalizationPolicyV1.validate()
        try C48PortableReviewLocalizationCatalogBoundaryV1.validate()
        XCTAssertTrue(C48PortableReviewLocalizationPolicyV1.selfAssertedIdentityIsUnverified)
        XCTAssertTrue(C48PortableReviewLocalizationPolicyV1.noDeliveryOrApprovalClaim)
        XCTAssertFalse(C48PortableReviewAccessibilityPolicyV1.capabilityProofSpoken)
    }
}
private final class C49WorkResourceLocalizationBoundaryTests: XCTestCase {
    func testCanonicalCurrencyIsLocaleIndependentUppercaseISOCode() {
        XCTAssertEqual(try? ExactMoneyAmountV1(mantissa: 1, currencyCode: "USD", minorUnitScale: 2).currencyCode, "USD")
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "usd", minorUnitScale: 2))
    }

    func testC49ManualDurationAndDirectCostDisclosuresAreExactAndBundled() throws {
        let duration = "Time spent — entered manually"
        let directCost = "Direct cost — entered amount; no tax, rates, markup, or invoice calculation."
        XCTAssertEqual(C49WorkResourceLocalizationPolicyV1.english(.durationManual), duration)
        XCTAssertEqual(C49WorkResourceLocalizationPolicyV1.english(.directCostInternal), directCost)
        XCTAssertEqual(BundledLocalizationCatalogV1.workResourceEnglish(.durationManual), duration)
        XCTAssertEqual(BundledLocalizationCatalogV1.workResourceEnglish(.directCostInternal), directCost)

        let registry = try BundledLocalizationCatalogV1.workResourceRegistry()
        XCTAssertEqual(
            try registry.definition(for: LocalizationKeyV1(C49WorkResourceLocalizationKeyV1.durationManual.rawValue)).englishDefaultValue,
            duration
        )
        XCTAssertEqual(
            try registry.definition(for: LocalizationKeyV1(C49WorkResourceLocalizationKeyV1.directCostInternal.rawValue)).englishDefaultValue,
            directCost
        )
        try C49WorkResourceLocalizationBoundaryV1.validate()

        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        XCTAssertNotNil(strings[C49WorkResourceLocalizationKeyV1.durationManual.rawValue])
        XCTAssertNotNil(strings[C49WorkResourceLocalizationKeyV1.directCostInternal.rawValue])
        let source = try String(contentsOf: catalogURL, encoding: .utf8)
        XCTAssertTrue(source.contains("\"value\" : \"\(duration)\""))
        XCTAssertTrue(source.contains("\"value\" : \"\(directCost)\""))
    }
}

private final class C50IncumbentAdapterLocalizationAccessibilityTests: XCTestCase {
    func testDisabledProfileCopyIsStableAndContainsNoProviderOrPrivateFieldClaim() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterStatus") as? String,
            "DISABLED_NO_SELECTED_PROFILE"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterDeclaresProviderType") as? Bool,
            false
        )
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V22/IncumbentExchange/V22P03C50IncumbentFileAdapterCorpusV1.json")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("private@example.invalid"))
        XCTAssertFalse(source.contains("WorkspaceID"))
        XCTAssertTrue(source.contains("no selected profile"))
    }
}

extension V9_22LocalizationAccessibilityTests {
    func testV23P03C34DraftResumeAnchorRetainsStableSemanticLabels() throws {
        let anchor = try DraftResumeAnchorV1(
            sectionID: "accessibility.section",
            fieldID: "accessibility.field",
            selectedStableID: "accessibility.selection",
            boundedPosition: 1
        )
        let target = try NavigationTargetV1(
            workspaceID: WorkspaceID(),
            destination: .draftReview,
            requestedMode: .resume,
            draftResumeAnchor: anchor
        )
        try target.validate()
        XCTAssertEqual(target.requestedMode, .resume)
        XCTAssertEqual(target.draftResumeAnchor?.selectedStableID, "accessibility.selection")
    }
}
