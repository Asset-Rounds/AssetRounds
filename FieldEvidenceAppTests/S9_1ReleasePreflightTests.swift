import Foundation
import CryptoKit
import XCTest

final class S9_1ReleasePreflightTests: XCTestCase {
    private let expectedInputKeys = [
        "age_rating_answers",
        "app_bundle_id",
        "app_privacy_answers",
        "app_review_information",
        "app_store_connect_api_issuer_id",
        "app_store_connect_api_key_id",
        "app_store_connect_api_private_key",
        "app_store_metadata",
        "app_store_record",
        "app_store_title_clearance",
        "apple_account_access",
        "apple_developer_program_membership",
        "apple_developer_team_id",
        "banking_configuration",
        "distribution_certificate_p12",
        "distribution_certificate_password",
        "export_compliance_answers",
        "github_environment_configuration",
        "live_billing_grace_period",
        "live_family_sharing_setting",
        "live_introductory_offer",
        "live_subscription_group",
        "live_subscription_price",
        "live_subscription_product_configuration",
        "live_subscription_storefronts",
        "monthly_product_id",
        "named_sandbox_tester",
        "owner_domain",
        "paid_apps_agreement",
        "physical_iphone_access",
        "privacy_policy_url",
        "release_build_number",
        "release_marketing_version",
        "six_of_ten_commitment_evidence",
        "small_business_program_status",
        "support_email",
        "support_url",
        "tax_configuration",
        "terms_of_use_url",
        "ui_test_bundle_id",
        "unit_test_bundle_id",
    ]

    func testUnsignedPackageHasExactClosedSchemasAndHonestPendingReadiness() throws {
        let manifest = try jsonObject("Release/ReleaseInputManifestV1.json")
        let provided = try jsonObject("Release/ProvidedReleaseValuesV1.json")
        let metadata = try jsonObject("Release/UnsignedRCMetadataV1.json")

        XCTAssertTrue(validateManifest(manifest, providedRoot: provided))
        XCTAssertEqual(Set(manifest.keys), ["inputs", "releaseReady", "schemaVersion"])
        XCTAssertEqual(manifest["schemaVersion"] as? Int, 1)
        XCTAssertEqual(manifest["releaseReady"] as? Bool, false)

        let inputs = try XCTUnwrap(manifest["inputs"] as? [[String: Any]])
        XCTAssertEqual(inputs.map { $0["key"] as? String }, expectedInputKeys)
        XCTAssertEqual(inputs.filter { $0["status"] as? String == "provided" }.count, 4)
        XCTAssertEqual(inputs.filter { $0["status"] as? String == "pending" }.count, 37)

        let values = try XCTUnwrap(provided["values"] as? [String: Any])
        XCTAssertEqual(
            Set(values.keys),
            [
                "appBundleID",
                "monthlyProductID",
                "uiTestBundleID",
                "unitTestBundleID",
            ]
        )
        XCTAssertEqual(values["appBundleID"] as? String, "com.palatis3.fieldrecord")
        XCTAssertEqual(
            values["monthlyProductID"] as? String,
            "com.palatis3.fieldrecord.sub.solo.monthly.v1"
        )
        XCTAssertEqual(
            values["uiTestBundleID"] as? String,
            "com.palatis3.fieldrecord.uitests"
        )
        XCTAssertEqual(
            values["unitTestBundleID"] as? String,
            "com.palatis3.fieldrecord.tests"
        )

        XCTAssertEqual(
            try nestedString(metadata, "app", "candidateAppStoreTitle"),
            "AssetRounds: Sign Inspection"
        )
        XCTAssertEqual(
            try nestedString(metadata, "app", "candidateTitleClearanceStatus"),
            "pending"
        )
        XCTAssertEqual(
            try nestedString(metadata, "commerce", "productionConfigurationStatus"),
            "pending"
        )
        XCTAssertEqual(metadata["releaseReady"] as? Bool, false)
        XCTAssertEqual(metadata["unsigned"] as? Bool, true)
        let nonClaims = try XCTUnwrap(metadata["nonClaims"] as? [String])
        XCTAssertTrue(nonClaims.contains("No signing was performed."))
        XCTAssertTrue(nonClaims.contains("No TestFlight or App Store upload was performed."))

        let project = try text("FieldEvidenceApp.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains(
            "PRODUCT_BUNDLE_IDENTIFIER = com.palatis3.fieldrecord;"
        ))
        XCTAssertTrue(project.contains(
            "PRODUCT_BUNDLE_IDENTIFIER = com.palatis3.fieldrecord.tests;"
        ))
        XCTAssertTrue(project.contains(
            "PRODUCT_BUNDLE_IDENTIFIER = com.palatis3.fieldrecord.uitests;"
        ))
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.0;"))
        XCTAssertTrue(project.contains("MARKETING_VERSION = 1.0;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 1;"))

        let releaseBytes = try allReleaseText()
        XCTAssertFalse(releaseBytes.contains("example.invalid"))
        XCTAssertFalse(releaseBytes.contains("BEGIN PRIVATE KEY"))
        XCTAssertFalse(releaseBytes.contains("BEGIN RSA PRIVATE KEY"))
    }

    func testPrivacyManifestMatchesBuiltResourceAndSourceRequiredReasons() throws {
        let manifestData = try data("FieldEvidenceApp/PrivacyInfo.xcprivacy")
        let manifest = try plistObject(manifestData)
        XCTAssertTrue(validatePrivacy(manifest))
        XCTAssertEqual(
            Set(manifest.keys),
            [
                "NSPrivacyAccessedAPITypes",
                "NSPrivacyCollectedDataTypes",
                "NSPrivacyTracking",
                "NSPrivacyTrackingDomains",
            ]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(
            try XCTUnwrap(manifest["NSPrivacyTrackingDomains"] as? [Any]).count,
            0
        )
        XCTAssertEqual(
            try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [Any]).count,
            0
        )

        let builtURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        XCTAssertEqual(try Data(contentsOf: builtURL), manifestData)

        let source = try applicationSwiftSource()
        XCTAssertTrue(source.contains("volumeAvailableCapacityForImportantUsageKey"))
        XCTAssertTrue(source.contains("UserDefaults"))
        XCTAssertTrue(
            source.contains("fstatat(")
                || source.contains("fstat(")
                || source.contains("lstat(")
        )
        XCTAssertFalse(source.contains("systemUptime"))
        XCTAssertFalse(source.contains("mach_absolute_time"))

        let review = try text("Release/PrivacyReviewV1.md")
        for value in [
            "NSPrivacyAccessedAPICategoryDiskSpace",
            "E174.1",
            "NSPrivacyAccessedAPICategoryFileTimestamp",
            "3B52.1",
            "C617.1",
            "NSPrivacyAccessedAPICategoryUserDefaults",
            "CA92.1",
            "final App Store privacy answers remain an explicit owner-provided S9.3 input",
        ] {
            XCTAssertTrue(review.contains(value), "Missing privacy review truth: \(value)")
        }
    }

    func testSmokeIndexAndInactiveWorkflowHaveExactReleaseBoundaries() throws {
        let index = try jsonObject("Release/LaunchSmokeEvidenceIndexV1.json")
        XCTAssertEqual(
            Set(index.keys),
            ["finalRCSmoke", "phaseBaseSHA", "schemaVersion", "smokes"]
        )
        XCTAssertEqual(index["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            index["phaseBaseSHA"] as? String,
            "2e9f8a1bdade83f4510c6c6ff6bd18cefc7343a9"
        )
        let final = try XCTUnwrap(index["finalRCSmoke"] as? [String: Any])
        XCTAssertEqual(
            final["selector"] as? String,
            "FieldEvidenceAppUITests/S9_1FinalRCUITests"
        )
        XCTAssertEqual(final["evidenceStatus"] as? String, "pending_current_s9_1_ci")

        let smokes = try XCTUnwrap(index["smokes"] as? [[String: Any]])
        XCTAssertEqual(smokes.compactMap { $0["id"] as? Int }, Array(1...12))
        XCTAssertEqual(Set(smokes.compactMap { $0["key"] as? String }).count, 12)
        for smoke in smokes {
            XCTAssertEqual(smoke["automatedStatus"] as? String, "passed")
            XCTAssertEqual(
                smoke["ownerVerificationStatus"] as? String,
                "pending_s9_2"
            )
            let evidence = try XCTUnwrap(smoke["evidence"] as? [[String: Any]])
            XCTAssertFalse(evidence.isEmpty)
            for item in evidence {
                XCTAssertEqual(item["source"] as? String, "docs/execution/HANDOFF.md")
                XCTAssertTrue(isLowercaseSHA(item["headSHA"] as? String))
                XCTAssertGreaterThan(item["runID"] as? Int ?? 0, 0)
            }
        }

        let workflow = try text(".github/workflows/testflight.yml")
        XCTAssertTrue(validateWorkflow(workflow))
        XCTAssertFalse(workflow.contains("RELEASE_HOME: ${{ runner.temp }}"))
        XCTAssertTrue(workflow.contains(
            "printf 'RELEASE_HOME=%s\\n' \"$RUNNER_TEMP/asset-rounds-release-home\""
        ))
        XCTAssertTrue(workflow.contains("environment: app-store-connect"))
        XCTAssertTrue(workflow.contains("security create-keychain"))
        XCTAssertTrue(workflow.contains("security delete-keychain"))
        XCTAssertTrue(workflow.contains(
            "bash Scripts/release-preflight.sh --release-ready \"$REVIEWED_MAIN_SHA\""
        ))
        XCTAssertEqual(occurrences(of: "\n            archive\n", in: workflow), 1)
        XCTAssertEqual(occurrences(of: "xcodebuild -exportArchive", in: workflow), 1)
        XCTAssertEqual(occurrences(of: "xcrun altool --upload-app", in: workflow), 1)

        let secretInputs = try manifestSecretEnvironmentKeys()
        let expectedSecrets: Set<String> = [
            "APP_STORE_CONNECT_API_ISSUER_ID",
            "APP_STORE_CONNECT_API_KEY_ID",
            "APP_STORE_CONNECT_API_PRIVATE_KEY_P8_BASE64",
            "APPLE_DISTRIBUTION_CERTIFICATE_P12_BASE64",
            "APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD",
        ]
        XCTAssertEqual(secretInputs, expectedSecrets)
        for name in expectedSecrets {
            XCTAssertTrue(workflow.contains("secrets.\(name)"))
        }

        let options = try plistObject(try data("Release/TestFlightExportOptions.plist"))
        XCTAssertEqual(options["method"] as? String, "app-store-connect")
        XCTAssertEqual(options["destination"] as? String, "export")
        XCTAssertEqual(options["signingStyle"] as? String, "automatic")
        XCTAssertEqual(options["manageAppVersionAndBuildNumber"] as? Bool, false)
        XCTAssertEqual(options["stripSwiftSymbols"] as? Bool, true)
        XCTAssertEqual(options["uploadSymbols"] as? Bool, true)

        let script = try text("Scripts/release-preflight.sh")
        XCTAssertTrue(script.contains("--release-ready"))
        XCTAssertTrue(script.contains("releaseReady == true"))
        XCTAssertTrue(script.contains("git ls-remote --exit-code origin refs/heads/main"))
        XCTAssertTrue(script.contains("pending_count="))
    }

    func testMalformedAuthorityFamilyFailsClosedWithoutMakingPendingAnError() throws {
        let manifest = try jsonObject("Release/ReleaseInputManifestV1.json")
        let provided = try jsonObject("Release/ProvidedReleaseValuesV1.json")
        XCTAssertTrue(validateManifest(manifest, providedRoot: provided))

        var omitted = deepCopy(manifest)
        omitted.removeValue(forKey: "releaseReady")
        XCTAssertFalse(validateManifest(omitted, providedRoot: provided))

        var duplicate = deepCopy(manifest)
        var duplicateInputs = duplicate["inputs"] as? [[String: Any]] ?? []
        duplicateInputs.append(duplicateInputs[0])
        duplicate["inputs"] = duplicateInputs
        XCTAssertFalse(validateManifest(duplicate, providedRoot: provided))

        var unknown = deepCopy(manifest)
        var unknownInputs = unknown["inputs"] as? [[String: Any]] ?? []
        unknownInputs[0]["key"] = "unknown_release_fact"
        unknown["inputs"] = unknownInputs
        XCTAssertFalse(validateManifest(unknown, providedRoot: provided))

        var falseReady = deepCopy(manifest)
        falseReady["releaseReady"] = true
        XCTAssertFalse(validateManifest(falseReady, providedRoot: provided))

        var leakedSecret = deepCopy(manifest)
        var secretInputs = leakedSecret["inputs"] as? [[String: Any]] ?? []
        let secretIndex = try XCTUnwrap(
            secretInputs.firstIndex { $0["secret"] as? Bool == true }
        )
        secretInputs[secretIndex]["valueKey"] = "embeddedCredential"
        leakedSecret["inputs"] = secretInputs
        XCTAssertFalse(validateManifest(leakedSecret, providedRoot: provided))

        var wrongValues = deepCopy(provided)
        var valueObject = wrongValues["values"] as? [String: Any] ?? [:]
        valueObject["appBundleID"] = "com.example.wrong"
        wrongValues["values"] = valueObject
        XCTAssertFalse(validateManifest(manifest, providedRoot: wrongValues))

        let workflow = try text(".github/workflows/testflight.yml")
        XCTAssertTrue(validateWorkflow(workflow))
        XCTAssertFalse(validateWorkflow(
            workflow.replacingOccurrences(
                of: "  workflow_dispatch:",
                with: "  push:"
            )
        ))
        XCTAssertFalse(validateWorkflow(
            workflow.replacingOccurrences(
                of: "refs/heads/main",
                with: "refs/heads/phase/s9-release"
            )
        ))
        XCTAssertFalse(validateWorkflow(
            workflow.replacingOccurrences(
                of: "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
                with: "actions/checkout@main"
            )
        ))
        XCTAssertFalse(validateWorkflow(workflow + "\nretry: 3\n"))
        XCTAssertFalse(validateWorkflow(workflow + "\n-----BEGIN PRIVATE KEY-----\n"))

        let privacy = try plistObject(try data("FieldEvidenceApp/PrivacyInfo.xcprivacy"))
        XCTAssertTrue(validatePrivacy(privacy))
        var wrongPrivacy = deepCopy(privacy)
        var accessed = wrongPrivacy["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        accessed[0]["NSPrivacyAccessedAPITypeReasons"] = ["85F4.1"]
        wrongPrivacy["NSPrivacyAccessedAPITypes"] = accessed
        XCTAssertFalse(validatePrivacy(wrongPrivacy))
    }

    func testV23P04C15G01DiscoveryTruthCatalogValidatesLocalizedLimitsAndClosedArtifactSet() throws {
        let corpus = try c15Corpus()
        XCTAssertTrue(validateC15(corpus))
        let declarations = try c15SourceDeclarations()
        XCTAssertTrue(validateC15SourceDeclarations(declarations))
        let receipt = try c15EvidenceReceipt()
        XCTAssertTrue(validateC15EvidenceReceipt(receipt))

        let semantics = try XCTUnwrap(corpus["semantics"] as? [String: Any])
        XCTAssertEqual(semantics["persistentContractMode"] as? String, "DECLARATION_ONLY")
        XCTAssertEqual(semantics["persistentContractSchema"] as? String, "DISCOVERY_TRUTH_CATALOG_V1")
        XCTAssertEqual(semantics["publicationEligible"] as? Bool, false)
        XCTAssertEqual(semantics["aggregateNoJoinKey"] as? Bool, true)
        XCTAssertEqual(semantics["aggregateNoRealData"] as? Bool, true)

        let catalog = try XCTUnwrap(corpus["catalog"] as? [String: Any])
        let locales = try XCTUnwrap(catalog["locales"] as? [[String: Any]])
        XCTAssertEqual(locales.map { $0["locale"] as? String }, ["en-US", "fr-FR"])
        for locale in locales {
            XCTAssertLessThanOrEqual(c15CodePointCount(locale["name"] as? String), 30)
            XCTAssertLessThanOrEqual(c15CodePointCount(locale["subtitle"] as? String), 30)
            XCTAssertLessThanOrEqual((locale["keywords"] as? String)?.utf8.count ?? 0, 100)
            XCTAssertLessThanOrEqual(c15CodePointCount(locale["promotionalText"] as? String), 170)
            XCTAssertLessThanOrEqual(c15CodePointCount(locale["description"] as? String), 4000)
        }

        let artifacts = try XCTUnwrap(corpus["artifacts"] as? [[String: Any]])
        XCTAssertEqual(
            artifacts.compactMap { $0["kind"] as? String },
            ["HOME", "USE_CASE", "PRIVACY", "ACCESSIBILITY", "SUPPORT", "SAMPLE_REPORT"]
        )
        XCTAssertTrue(artifacts.allSatisfy { ($0["status"] as? String) == "DRAFT_ONLY" })
        XCTAssertTrue(artifacts.allSatisfy { ($0["publishable"] as? Bool) == false })
        XCTAssertTrue(artifacts.allSatisfy { c15SHA($0["contentSHA256"] as? String) })

        let script = try text("Scripts/release-preflight.sh")
        for requiredText in [
            "V23P04C15DiscoveryTruthCorpusV1",
            "DISCOVERY_TRUTH_CATALOG_V1",
            "ARBITRARY_NONEMPTY_METADATA",
            "ZERO_PARTIAL_OR_COMPLETE",
            "stableJoinKeys",
            "DISABLED_OR_DEFERRED",
        ] {
            XCTAssertTrue(script.contains(requiredText), "C15 preflight is missing \\(requiredText)")
        }
    }

    func testV23P04C15A01CategoriesAndAppTagsRemainSeparateTypedSets() throws {
        let corpus = try c15Corpus()
        XCTAssertTrue(validateC15(corpus))
        let declarations = try c15SourceDeclarations()
        XCTAssertTrue(validateC15SourceDeclarations(declarations))

        let catalog = try XCTUnwrap(corpus["catalog"] as? [String: Any])
        let categories = try XCTUnwrap(catalog["categories"] as? [String])
        let appTags = try XCTUnwrap(catalog["appTags"] as? [String])
        XCTAssertEqual(categories, ["BUSINESS", "PRODUCTIVITY"])
        XCTAssertEqual(appTags, ["EVIDENCE", "FIELD_WORK"])
        XCTAssertTrue(Set(categories).isDisjoint(with: Set(appTags)))

        let sourceCatalog = try XCTUnwrap(declarations[c15CatalogPath])
        let sourceCategories = try XCTUnwrap(
            (sourceCatalog["appStoreCategories"] as? [String: Any]).map {
                [$0["primary"] as? String, $0["secondary"] as? String]
            }
        )
        let sourceTags = try XCTUnwrap(
            (sourceCatalog["curatedAppTags"] as? [String: Any])?["tags"] as? [String]
        )
        XCTAssertEqual(sourceCategories.compactMap { $0 }, categories)
        XCTAssertEqual(sourceTags, appTags)

        var categoryAsTag = deepCopy(corpus)
        var categoryAsTagCatalog = try XCTUnwrap(categoryAsTag["catalog"] as? [String: Any])
        categoryAsTagCatalog["appTags"] = categories
        categoryAsTag["catalog"] = categoryAsTagCatalog
        XCTAssertFalse(validateC15(categoryAsTag))

        var tagAsCategory = deepCopy(corpus)
        var tagAsCategoryCatalog = try XCTUnwrap(tagAsCategory["catalog"] as? [String: Any])
        tagAsCategoryCatalog["categories"] = appTags
        tagAsCategory["catalog"] = tagAsCategoryCatalog
        XCTAssertFalse(validateC15(tagAsCategory))
    }

    func testV23P04C15H01HostileOpaqueStaleRealDataAndDraftPublishedInputsFailClosed() throws {
        let corpus = try c15Corpus()
        XCTAssertTrue(validateC15(corpus))
        let declarations = try c15SourceDeclarations()
        XCTAssertTrue(validateC15SourceDeclarations(declarations))
        let receipt = try c15EvidenceReceipt()
        XCTAssertTrue(validateC15EvidenceReceipt(receipt))
        let hostile = try XCTUnwrap(receipt["sourceContractsHostileSelfTest"] as? [String: Any])
        XCTAssertEqual(hostile["sourceContractsSelfTest"] as? String, "PASS")
        XCTAssertEqual(hostile["count"] as? Int, 8)
        XCTAssertEqual(
            hostile["rejected"] as? [String],
            [
                "brand-root-opaque",
                "synthetic-sample-opaque",
                "aggregate-evidence-opaque",
                "accessibility-root-opaque",
                "privacy-artifact-opaque",
                "catalog-ref-opaque",
                "candidate-digest-wrong",
                "approval-extra-key",
            ]
        )

        var opaque = deepCopy(corpus)
        opaque["arbitraryNonEmptyMetadata"] = ["unexpected": "value"]
        XCTAssertFalse(validateC15(opaque))

        var staleBrand = deepCopy(corpus)
        var staleCatalog = try XCTUnwrap(staleBrand["catalog"] as? [String: Any])
        var staleCandidate = try XCTUnwrap(staleCatalog["candidate"] as? [String: Any])
        staleCandidate["brandRevision"] = "c15-brand-revision-stale"
        staleCatalog["candidate"] = staleCandidate
        staleBrand["catalog"] = staleCatalog
        XCTAssertFalse(validateC15(staleBrand))

        var unsupportedLocale = deepCopy(corpus)
        var localeCatalog = try XCTUnwrap(unsupportedLocale["catalog"] as? [String: Any])
        var localeRecords = try XCTUnwrap(localeCatalog["locales"] as? [[String: Any]])
        localeRecords[0]["locale"] = "zz-ZZ"
        localeCatalog["locales"] = localeRecords
        unsupportedLocale["catalog"] = localeCatalog
        XCTAssertFalse(validateC15(unsupportedLocale))

        var overLimit = deepCopy(corpus)
        var overLimitCatalog = try XCTUnwrap(overLimit["catalog"] as? [String: Any])
        var overLimitLocales = try XCTUnwrap(overLimitCatalog["locales"] as? [[String: Any]])
        overLimitLocales[0]["name"] = String(repeating: "N", count: 31)
        overLimitCatalog["locales"] = overLimitLocales
        overLimit["catalog"] = overLimitCatalog
        XCTAssertFalse(validateC15(overLimit))

        var multiScalarOverLimit = deepCopy(corpus)
        var multiScalarCatalog = try XCTUnwrap(multiScalarOverLimit["catalog"] as? [String: Any])
        var multiScalarLocales = try XCTUnwrap(multiScalarCatalog["locales"] as? [[String: Any]])
        multiScalarLocales[0]["name"] = String(repeating: "e\u{301}", count: 16)
        multiScalarCatalog["locales"] = multiScalarLocales
        multiScalarOverLimit["catalog"] = multiScalarCatalog
        XCTAssertFalse(validateC15(multiScalarOverLimit), "Unicode scalar limits must match tooling code-point limits")

        var realDataIdentifier = deepCopy(corpus)
        var realDataArtifacts = try XCTUnwrap(realDataIdentifier["artifacts"] as? [[String: Any]])
        realDataArtifacts[0]["id"] = "customer-record-0001"
        realDataIdentifier["artifacts"] = realDataArtifacts
        XCTAssertFalse(validateC15(realDataIdentifier))

        var missingWatermark = deepCopy(corpus)
        var unwatermarkedArtifacts = try XCTUnwrap(missingWatermark["artifacts"] as? [[String: Any]])
        unwatermarkedArtifacts[0]["watermarks"] = []
        missingWatermark["artifacts"] = unwatermarkedArtifacts
        XCTAssertFalse(validateC15(missingWatermark))

        var stableJoinKey = deepCopy(corpus)
        var joinedAcquisition = try XCTUnwrap(stableJoinKey["acquisition"] as? [String: Any])
        joinedAcquisition["stableJoinKeys"] = ["workspace-0001"]
        stableJoinKey["acquisition"] = joinedAcquisition
        XCTAssertFalse(validateC15(stableJoinKey))

        var enabledClaim = deepCopy(corpus)
        var enabledClaimCatalog = try XCTUnwrap(enabledClaim["catalog"] as? [String: Any])
        var claims = try XCTUnwrap(enabledClaimCatalog["claims"] as? [[String: Any]])
        claims[0]["enabled"] = true
        enabledClaimCatalog["claims"] = claims
        enabledClaim["catalog"] = enabledClaimCatalog
        XCTAssertFalse(validateC15(enabledClaim))

        var draftPublished = deepCopy(corpus)
        var published = try XCTUnwrap(draftPublished["publication"] as? [String: Any])
        published["status"] = "PUBLISHED"
        published["publishable"] = true
        draftPublished["publication"] = published
        XCTAssertFalse(validateC15(draftPublished))

        var providerPath = deepCopy(corpus)
        var provider = try XCTUnwrap(providerPath["publication"] as? [String: Any])
        provider["provider"] = "APP_STORE_CONNECT"
        providerPath["publication"] = provider
        XCTAssertFalse(validateC15(providerPath))

        var opaqueDeclarations = declarations
        var opaqueCatalog = try XCTUnwrap(opaqueDeclarations[c15CatalogPath])
        opaqueCatalog["arbitraryNonemptyMetadata"] = ["unexpected": "value"]
        opaqueDeclarations[c15CatalogPath] = opaqueCatalog
        XCTAssertFalse(validateC15SourceDeclarations(opaqueDeclarations))

        var opaqueBrandDeclarations = declarations
        var opaqueBrand = try XCTUnwrap(opaqueBrandDeclarations[c15BrandPath])
        opaqueBrand["arbitraryNonemptyMetadata"] = ["unexpected": "value"]
        opaqueBrandDeclarations[c15BrandPath] = opaqueBrand
        XCTAssertFalse(validateC15SourceDeclarations(opaqueBrandDeclarations))

        var staleDeclarations = declarations
        var staleSourceCatalog = try XCTUnwrap(staleDeclarations[c15CatalogPath])
        var staleBrandReference = try XCTUnwrap(staleSourceCatalog["brandRevisionReference"] as? [String: Any])
        staleBrandReference["authoritySHA256"] = String(repeating: "0", count: 64)
        staleSourceCatalog["brandRevisionReference"] = staleBrandReference
        staleDeclarations[c15CatalogPath] = staleSourceCatalog
        XCTAssertFalse(validateC15SourceDeclarations(staleDeclarations))

        var staleDigestDeclarations = declarations
        var staleDigestCatalog = try XCTUnwrap(staleDigestDeclarations[c15CatalogPath])
        var staleDigestBrand = try XCTUnwrap(staleDigestCatalog["brandedStaticProof"] as? [String: Any])
        staleDigestBrand["sha256"] = String(repeating: "0", count: 64)
        staleDigestCatalog["brandedStaticProof"] = staleDigestBrand
        staleDigestDeclarations[c15CatalogPath] = staleDigestCatalog
        XCTAssertFalse(validateC15SourceDeclarations(staleDigestDeclarations))

        var candidateDigestDeclarations = declarations
        var candidateDigestCatalog = try XCTUnwrap(candidateDigestDeclarations[c15CatalogPath])
        var candidateBindings = try XCTUnwrap(candidateDigestCatalog["evidenceBindings"] as? [[String: Any]])
        candidateBindings[3]["sha256"] = String(repeating: "0", count: 64)
        candidateDigestCatalog["evidenceBindings"] = candidateBindings
        candidateDigestDeclarations[c15CatalogPath] = candidateDigestCatalog
        XCTAssertFalse(validateC15SourceDeclarations(candidateDigestDeclarations))

        var enabledClaimDeclarations = declarations
        var claimCatalog = try XCTUnwrap(enabledClaimDeclarations[c15CatalogPath])
        var sourceClaims = try XCTUnwrap(claimCatalog["claims"] as? [[String: Any]])
        sourceClaims[0]["publishEligibility"] = true
        claimCatalog["claims"] = sourceClaims
        enabledClaimDeclarations[c15CatalogPath] = claimCatalog
        XCTAssertFalse(validateC15SourceDeclarations(enabledClaimDeclarations))

        var expiryDeclarations = declarations
        var expiryCatalog = try XCTUnwrap(expiryDeclarations[c15CatalogPath])
        var expiryClaims = try XCTUnwrap(expiryCatalog["claims"] as? [[String: Any]])
        expiryClaims[0]["expiresAt"] = "2026-08-31T00:00:00Z"
        expiryCatalog["claims"] = expiryClaims
        expiryDeclarations[c15CatalogPath] = expiryCatalog
        XCTAssertFalse(validateC15SourceDeclarations(expiryDeclarations))

        var realIDDeclarations = declarations
        var synthetic = try XCTUnwrap(realIDDeclarations[c15SyntheticPath])
        var samples = try XCTUnwrap(synthetic["samples"] as? [[String: Any]])
        samples[0]["sampleID"] = "customer-record-0001"
        synthetic["samples"] = samples
        realIDDeclarations[c15SyntheticPath] = synthetic
        XCTAssertFalse(validateC15SourceDeclarations(realIDDeclarations))

        var watermarkDeclarations = declarations
        var missingWatermarkSynthetic = try XCTUnwrap(watermarkDeclarations[c15SyntheticPath])
        var watermarkSamples = try XCTUnwrap(missingWatermarkSynthetic["samples"] as? [[String: Any]])
        watermarkSamples[0]["displayWatermarks"] = []
        missingWatermarkSynthetic["samples"] = watermarkSamples
        watermarkDeclarations[c15SyntheticPath] = missingWatermarkSynthetic
        XCTAssertFalse(validateC15SourceDeclarations(watermarkDeclarations))

        var publishedDeclarations = declarations
        var publishedCatalog = try XCTUnwrap(publishedDeclarations[c15CatalogPath])
        publishedCatalog["status"] = "PUBLISHED"
        publishedDeclarations[c15CatalogPath] = publishedCatalog
        XCTAssertFalse(validateC15SourceDeclarations(publishedDeclarations))

        var networkDeclarations = declarations
        var aggregate = try XCTUnwrap(networkDeclarations[c15AggregatePath])
        aggregate["networkAccessEnabled"] = true
        networkDeclarations[c15AggregatePath] = aggregate
        XCTAssertFalse(validateC15SourceDeclarations(networkDeclarations))

        var unicodeDeclarations = declarations
        var unicodeCatalog = try XCTUnwrap(unicodeDeclarations[c15CatalogPath])
        var sourceLocales = try XCTUnwrap(unicodeCatalog["locales"] as? [[String: Any]])
        sourceLocales[0]["name"] = String(repeating: "e\u{301}", count: 16)
        unicodeCatalog["locales"] = sourceLocales
        unicodeDeclarations[c15CatalogPath] = unicodeCatalog
        XCTAssertFalse(validateC15SourceDeclarations(unicodeDeclarations))
    }

    func testV23P04C15I01InterruptedDeclarationGenerationLeavesZeroPartialOrCompleteArtifactSet() throws {
        let corpus = try c15Corpus()
        XCTAssertTrue(validateC15(corpus))
        XCTAssertTrue(validateC15SourceDeclarations(try c15SourceDeclarations()))
        let receipt = try c15EvidenceReceipt()
        XCTAssertTrue(validateC15EvidenceReceipt(receipt))
        let interruption = try XCTUnwrap(receipt["interruptionAcceptanceEvidence"] as? [String: Any])
        XCTAssertEqual(interruption["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        XCTAssertEqual(interruption["noWorktreeMutation"] as? Bool, true)
        let rows = try XCTUnwrap(interruption["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["boundary"] as? String }, [
            "BEFORE_ACCEPTED_ARTIFACT_WRITE",
            "AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT",
            "AFTER_RECEIPT_BEFORE_RETURN",
        ])
        XCTAssertEqual(rows.map { $0["acceptedSetCount"] as? Int }, [1, 0, 1])

        var missingArtifact = deepCopy(corpus)
        var incompleteArtifacts = try XCTUnwrap(missingArtifact["artifacts"] as? [[String: Any]])
        incompleteArtifacts.removeLast()
        missingArtifact["artifacts"] = incompleteArtifacts
        XCTAssertFalse(validateC15(missingArtifact))

        var partialArtifact = deepCopy(corpus)
        var partialArtifacts = try XCTUnwrap(partialArtifact["artifacts"] as? [[String: Any]])
        partialArtifacts[0]["status"] = "PARTIAL"
        partialArtifact["artifacts"] = partialArtifacts
        XCTAssertFalse(validateC15(partialArtifact))

        let dispositions = try XCTUnwrap(corpus["expectedDispositions"] as? [[String: Any]])
        let interrupted = try XCTUnwrap(
            dispositions.first { $0["case"] as? String == "INTERRUPTED_GENERATION" }
        )
        XCTAssertEqual(interrupted["disposition"] as? String, "ZERO_PARTIAL_OR_COMPLETE")
        XCTAssertEqual(interrupted["acceptedArtifactCount"] as? Int, 0)
        XCTAssertEqual(interrupted["productWrites"] as? Int, 0)
        XCTAssertEqual(interrupted["publicWrites"] as? Int, 0)

        let boundaries = try XCTUnwrap(corpus["journalFaultBoundaries"] as? [String])
        XCTAssertEqual(boundaries.count, 3)
        XCTAssertTrue(boundaries.contains("BEFORE_ACCEPTED_ARTIFACT_WRITE"))
        XCTAssertTrue(boundaries.contains("AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT"))
        XCTAssertTrue(boundaries.contains("AFTER_RECEIPT_BEFORE_RETURN"))
    }

    func testV23P04C15R01DeletingAndRebuildingDeclarationArtifactsLeavesProductAndPublicStateUnchanged() throws {
        let corpus = try c15Corpus()
        XCTAssertTrue(validateC15(corpus))
        let declarations = try c15SourceDeclarations()
        XCTAssertTrue(validateC15SourceDeclarations(declarations))
        let receipt = try c15EvidenceReceipt()
        XCTAssertTrue(validateC15EvidenceReceipt(receipt))

        let originalProductState = try XCTUnwrap(corpus["productState"] as? [String: Any])
        let originalPublicState = try XCTUnwrap(corpus["publicState"] as? [String: Any])
        let originalProductBytes = try c15CanonicalJSON(originalProductState)
        let originalPublicBytes = try c15CanonicalJSON(originalPublicState)

        var deleted = deepCopy(corpus)
        deleted["artifacts"] = []
        XCTAssertFalse(validateC15(deleted), "an incomplete declaration set cannot be accepted")
        XCTAssertEqual(
            try c15CanonicalJSON(try XCTUnwrap(deleted["productState"] as? [String: Any])),
            originalProductBytes
        )
        XCTAssertEqual(
            try c15CanonicalJSON(try XCTUnwrap(deleted["publicState"] as? [String: Any])),
            originalPublicBytes
        )

        var rebuilt = deepCopy(deleted)
        rebuilt["artifacts"] = try XCTUnwrap(corpus["artifacts"] as? [[String: Any]])
        XCTAssertTrue(validateC15(rebuilt))
        XCTAssertEqual(
            try c15CanonicalJSON(try XCTUnwrap(rebuilt["productState"] as? [String: Any])),
            originalProductBytes
        )
        XCTAssertEqual(
            try c15CanonicalJSON(try XCTUnwrap(rebuilt["publicState"] as? [String: Any])),
            originalPublicBytes
        )

        let recovery = try XCTUnwrap(corpus["recovery"] as? [String: Any])
        XCTAssertEqual(recovery["preservesProductState"] as? Bool, true)
        XCTAssertEqual(recovery["preservesPublicState"] as? Bool, true)
        XCTAssertEqual(recovery["noProviderConnection"] as? Bool, true)
        XCTAssertEqual(recovery["noUpload"] as? Bool, true)
    }

    private func c15Corpus() throws -> [String: Any] {
        try jsonObject(
            "FieldEvidenceAppTests/Fixtures/V21/DiscoveryTruth/V23P04C15DiscoveryTruthCorpusV1.json"
        )
    }

    private let c15CatalogPath = "docs/product/discovery/DiscoveryTruthCatalogV1.json"
    private let c15BrandPath = "docs/product/discovery/V23P04C15BrandedStaticProofManifestV1.json"
    private let c15SyntheticPath = "docs/product/discovery/V23P04C15SyntheticSampleManifestV1.json"
    private let c15AggregatePath = "docs/product/discovery/V23P04C15AggregateAcquisitionEvidenceV1.json"
    private let c15AccessibilityPath = "docs/accessibility/V23P04C15StaticProofAccessibilityManifestV1.json"
    private let c15PrivacyPath = "docs/privacy/V23P01C02OwnedFilePrivacyInventoryV1.json"
    private let c15EvidenceReceiptPath = "docs/design/v23/tooling/V23P04C15DiscoveryTruthEvidenceReceiptV1.json"

    private var c15DeclarationPaths: [String] {
        [
            c15CatalogPath,
            c15BrandPath,
            c15SyntheticPath,
            c15AggregatePath,
            c15AccessibilityPath,
            c15PrivacyPath,
        ]
    }

    private func c15SourceDeclarations() throws -> [String: [String: Any]] {
        try Dictionary(uniqueKeysWithValues: c15DeclarationPaths.map { path in
            (path, try jsonObject(path))
        })
    }

    private func c15EvidenceReceipt() throws -> [String: Any] {
        try jsonObject(c15EvidenceReceiptPath)
    }

    private func validateC15EvidenceReceipt(_ receipt: [String: Any]) -> Bool {
        guard c15Keys(receipt, ["authority", "cardID", "contractDigest", "interruptionAcceptanceEvidence", "provisional", "schema", "schemaVersion", "sourceContractsHostileSelfTest", "sourceProjection", "statusFlags"]),
              (receipt["schema"] as? String) == "V23P04C15DiscoveryTruthEvidenceReceiptV1",
              (receipt["schemaVersion"] as? Int) == 1,
              (receipt["cardID"] as? String) == "V23-P04-C15",
              (receipt["provisional"] as? Bool) == true,
              c15SHA(receipt["contractDigest"] as? String),
              let hostile = receipt["sourceContractsHostileSelfTest"] as? [String: Any],
              c15Keys(hostile, ["count", "rejected", "sourceContractsSelfTest"]),
              (hostile["sourceContractsSelfTest"] as? String) == "PASS",
              (hostile["count"] as? Int) == 8,
              (hostile["rejected"] as? [String]) == ["brand-root-opaque", "synthetic-sample-opaque", "aggregate-evidence-opaque", "accessibility-root-opaque", "privacy-artifact-opaque", "catalog-ref-opaque", "candidate-digest-wrong", "approval-extra-key"],
              let interruption = receipt["interruptionAcceptanceEvidence"] as? [String: Any],
              c15Keys(interruption, ["noWorktreeMutation", "protocol", "rows"]),
              (interruption["noWorktreeMutation"] as? Bool) == true,
              (interruption["protocol"] as? String) == "MANIFEST_LAST_ATOMIC_REPLACE",
              let rows = interruption["rows"] as? [[String: Any]],
              rows.count == 3,
              rows.allSatisfy({ c15Keys($0, ["acceptedSetCount", "boundary"]) }),
              rows.map({ $0["boundary"] as? String }) == ["BEFORE_ACCEPTED_ARTIFACT_WRITE", "AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT", "AFTER_RECEIPT_BEFORE_RETURN"],
              rows.map({ $0["acceptedSetCount"] as? Int }) == [1, 0, 1],
              let projection = receipt["sourceProjection"] as? [String: Any],
              c15Keys(projection, ["counts", "selectors", "sourceReady", "sourceRows"]),
              (projection["sourceReady"] as? Bool) == true,
              (projection["selectors"] as? [String]) == [
                  "testV23P04C15G01DiscoveryTruthCatalogValidatesLocalizedLimitsAndClosedArtifactSet",
                  "testV23P04C15A01CategoriesAndAppTagsRemainSeparateTypedSets",
                  "testV23P04C15H01HostileOpaqueStaleRealDataAndDraftPublishedInputsFailClosed",
                  "testV23P04C15I01InterruptedDeclarationGenerationLeavesZeroPartialOrCompleteArtifactSet",
                  "testV23P04C15R01DeletingAndRebuildingDeclarationArtifactsLeavesProductAndPublicStateUnchanged",
              ],
              let counts = projection["counts"] as? [String: Any],
              c15Keys(counts, ["changedPathCount", "missingPathCount", "s10ReservationOverlapCount", "unownedChangedPathCount"]),
              (counts["missingPathCount"] as? Int) == 0,
              (counts["s10ReservationOverlapCount"] as? Int) == 0,
              (counts["unownedChangedPathCount"] as? Int) == 0,
              let sourceRows = projection["sourceRows"] as? [[String: Any]],
              sourceRows.count == 7,
              sourceRows.allSatisfy({ c15Keys($0, ["path", "sha256", "status"]) && ($0["status"] as? String) == "SOURCE_PRESENT" && c15SHA($0["sha256"] as? String) }),
              Set(sourceRows.compactMap({ $0["path"] as? String })) == Set(c15DeclarationPaths + ["FieldEvidenceAppTests/Fixtures/V21/DiscoveryTruth/V23P04C15DiscoveryTruthCorpusV1.json"]),
              (receipt["statusFlags"] as? [String: Any])?.values.allSatisfy({ ($0 as? Bool) == false }) == true else {
            return false
        }
        return true
    }

    private func validateC15SourceDeclarations(_ values: [String: [String: Any]]) -> Bool {
        guard Set(values.keys) == Set(c15DeclarationPaths),
              let catalog = values[c15CatalogPath],
              let brand = values[c15BrandPath],
              let synthetic = values[c15SyntheticPath],
              let aggregate = values[c15AggregatePath],
              let accessibility = values[c15AccessibilityPath],
              let privacy = values[c15PrivacyPath] else {
            return false
        }

        let roots: [(value: [String: Any], keys: [String])] = [
            (catalog, ["acceptanceCredit", "adoptionEnabled", "aggregateAcquisitionEvidence", "appStoreCategories", "brandBaselineReference", "brandRevisionReference", "brandedStaticProof", "candidateReference", "cardID", "claims", "curatedAppTags", "deploymentEnabled", "evidenceBindings", "locales", "metadataLimits", "networkProviderEnabled", "optionalOwnerApprovalReference", "persistentContractMode", "persistentContractSchema", "provisional", "publicationEligible", "publish", "releaseCredit", "schema", "schemaVersion", "screenshots", "signingEnabled", "status", "statusFlags", "syntheticSamples", "upload"]),
            (brand, ["acceptanceCredit", "accessibilityManifest", "adoptionEnabled", "brandBaselineReference", "brandRevisionReference", "candidateReference", "cardID", "finalScreenshotBytes", "networkProviderEnabled", "proofs", "provisional", "publicationEligible", "publish", "releaseCredit", "schema", "schemaVersion", "status", "statusFlags", "syntheticSampleManifest", "upload"]),
            (synthetic, ["acceptanceCredit", "adoptionEnabled", "cardID", "containsCustomerData", "containsRealUserData", "defaultWatermark", "networkProviderEnabled", "practiceWatermark", "provisional", "publicationEligible", "publish", "releaseCredit", "samples", "schema", "schemaVersion", "status", "statusFlags", "upload"]),
            (aggregate, ["acceptanceCredit", "acquisitionEvidence", "adoptionEnabled", "analyticsEnabled", "attributionEnabled", "cardID", "containsClaimsOfAcquisitionPerformance", "containsCustomerData", "containsDeviceJoinKey", "containsEntityJoinKey", "containsFabricatedEvidence", "containsPersonJoinKey", "containsRatings", "containsReviews", "containsUserClaims", "containsUserRecords", "containsWorkspaceJoinKey", "deviceJoinKeyEnabled", "externalProviderEnabled", "networkAccessEnabled", "paidAcquisitionEnabled", "provisional", "publicationEligible", "publish", "releaseCredit", "schema", "schemaVersion", "sessionReplayEnabled", "stableJoinKeyEnabled", "status", "statusFlags", "upload"]),
            (accessibility, ["acceptanceCredit", "accessibilityCoverage", "adoptionEnabled", "approvals", "artifactKinds", "cardID", "containsRealCustomerData", "containsStableJoinKeys", "hiddenClaims", "networkProviderAnalyticsAttributionOrSessionReplay", "optionalApprovalsEnabled", "publicationEligible", "publish", "releaseCredit", "sampleAndPracticeWatermarksRequired", "schema", "schemaVersion", "status", "upload"]),
            (privacy, ["acceptanceCredit", "acceptanceEnabled", "adoptionEnabled", "appProtectionAttributeClaimForExternalDestination", "artifactDigest", "authority", "c15DeclarationOnlyArtifacts", "c15DeclarationOnlyPolicy", "cardID", "diagnosticsAllowlist", "externalExportSource", "externalProviderHandoff", "forbiddenSecretSurfaces", "handlingClassDeclarations", "hostedDispatchRan", "keychainUsage", "lifecycle", "nativeCompileRan", "ownedPathMatrix", "phase10PollingDuringParallelExecution", "physicalEvidenceComplete", "physicalLockedState", "releaseCredit", "releaseReady", "reportRecoverySource", "requiresAcceptedS10_6Reconciliation", "schema", "schemaVersion", "secretInventory", "sourceBindingDigest", "systemDiscoveryProjection"]),
        ]
        guard roots.allSatisfy({ c15Keys($0.value, $0.keys) }) else { return false }

        let brandDigest = "3675918ba2d7ff2037dedd790f53827d85b66184a5907c4d482955b98b744a11"
        let syntheticDigest = "41e17b55277dfb4758e6a185074c1ea91eaa84f6bded7e0ce322eca0a10ae384"
        let aggregateDigest = "5696c7edc2cf318a4f0002af45bf46cd6385ddb12c3849dbabbf9bea11c08be7"
        let accessibilityDigest = "1b9edc89e86716c27fb82365092112f8ce5b9794dd9a083279f0438d07361110"
        let privacyDigest = "3a4f5f8afe44daed06cbe8a95ccb16be7610495af780b8df36b4138b7beaeb4b"
        let capabilityDigest = "98a205edc22421ec4a4f2a5494628f4f40be7117a95cdd3cc94e2d6eab7c98ef"
        let receiptDigest = "a2be42fc9708cb3e6c648750ff4eeef66150451393ba660aed1f186ae50b88fc"
        let candidateDigest = "47ec42f675c92b994e301bf4218a53223a91b8ad49a0a0b4fa9478e0ab1dc8e3"
        let falseFlags = ["acceptanceCredit", "adoptionEnabled", "publicationEligible", "publish", "releaseCredit", "upload"]
        guard [catalog, brand, synthetic, aggregate, accessibility].allSatisfy({ declaration in
            falseFlags.allSatisfy { declaration[$0] as? Bool == false }
        }),
        (catalog["schema"] as? String) == "DiscoveryTruthCatalogV1",
        (brand["schema"] as? String) == "V23P04C15BrandedStaticProofManifestV1",
        (synthetic["schema"] as? String) == "V23P04C15SyntheticSampleManifestV1",
        (aggregate["schema"] as? String) == "V23P04C15AggregateAcquisitionEvidenceV1",
        (accessibility["schema"] as? String) == "V23P04C15StaticProofAccessibilityManifestV1",
        [catalog, brand, synthetic, aggregate, accessibility].allSatisfy({
            ($0["schemaVersion"] as? Int) == 1
                && ($0["cardID"] as? String) == "V23-P04-C15"
                && ($0["provisional"] as? Bool) == true
        }) else { return false }

        guard (catalog["persistentContractMode"] as? String) == "DECLARATION_ONLY",
              (catalog["persistentContractSchema"] as? String) == "DISCOVERY_TRUTH_CATALOG_V1",
              (catalog["status"] as? String) == "DISABLED_OR_DEFERRED",
              (catalog["optionalOwnerApprovalReference"] is NSNull),
              (catalog["statusFlags"] as? [String: Any])?.values.allSatisfy({ ($0 as? Bool) == false }) == true,
              (brand["statusFlags"] as? [String: Any])?.values.allSatisfy({ ($0 as? Bool) == false }) == true,
              (synthetic["statusFlags"] as? [String: Any])?.values.allSatisfy({ ($0 as? Bool) == false }) == true,
              (aggregate["statusFlags"] as? [String: Any])?.values.allSatisfy({ ($0 as? Bool) == false }) == true else {
            return false
        }

        guard let catalogBrand = catalog["brandedStaticProof"] as? [String: Any],
              let catalogSynthetic = catalog["syntheticSamples"] as? [String: Any],
              let catalogAggregate = catalog["aggregateAcquisitionEvidence"] as? [String: Any],
              let brandAccessibility = brand["accessibilityManifest"] as? [String: Any],
              let brandSynthetic = brand["syntheticSampleManifest"] as? [String: Any],
              [catalogBrand, catalogSynthetic, catalogAggregate, brandAccessibility, brandSynthetic].allSatisfy({
                  c15Keys($0, ["path", "sha256"]) && c15SHA($0["sha256"] as? String)
              }),
              (catalogBrand["path"] as? String) == c15BrandPath,
              (catalogBrand["sha256"] as? String) == brandDigest,
              (catalogSynthetic["path"] as? String) == c15SyntheticPath,
              (catalogSynthetic["sha256"] as? String) == syntheticDigest,
              (catalogAggregate["path"] as? String) == c15AggregatePath,
              (catalogAggregate["sha256"] as? String) == aggregateDigest,
              (brandAccessibility["path"] as? String) == c15AccessibilityPath,
              (brandAccessibility["sha256"] as? String) == accessibilityDigest,
              c15CanonicalEqual(catalogSynthetic, brandSynthetic),
              let catalogBaseline = catalog["brandBaselineReference"] as? [String: Any],
              let catalogRevision = catalog["brandRevisionReference"] as? [String: Any],
              let brandBaseline = brand["brandBaselineReference"] as? [String: Any],
              let brandRevision = brand["brandRevisionReference"] as? [String: Any],
              c15CanonicalEqual(catalogBaseline, brandBaseline),
              c15CanonicalEqual(catalogRevision, brandRevision),
              (catalogRevision["disposition"] as? String) == "DISABLED_OR_DEFERRED",
              catalogRevision["ownerApprovalReference"] is NSNull else {
            return false
        }

        guard let claims = catalog["claims"] as? [[String: Any]],
              claims.count == 1,
              let claim = claims.first,
              c15Keys(claim, ["brandSHA256", "capabilitySHA256", "claimEvidenceSHA256", "claimID", "expiresAt", "optionalOwnerApprovalReference", "privacySHA256", "publishEligibility", "receiptSHA256", "status", "supersededByClaimDigest", "supersedesClaimDigest", "syntheticSHA256"]),
              (claim["brandSHA256"] as? String) == brandDigest,
              (claim["capabilitySHA256"] as? String) == capabilityDigest,
              (claim["claimEvidenceSHA256"] as? String) == aggregateDigest,
              (claim["privacySHA256"] as? String) == privacyDigest,
              (claim["receiptSHA256"] as? String) == receiptDigest,
              (claim["syntheticSHA256"] as? String) == syntheticDigest,
              (claim["status"] as? String) == "DISABLED_OR_DEFERRED",
              (claim["publishEligibility"] as? Bool) == false,
              claim["expiresAt"] is NSNull,
              claim["optionalOwnerApprovalReference"] is NSNull,
              claim["supersededByClaimDigest"] is NSNull,
              claim["supersedesClaimDigest"] is NSNull,
              let bindings = catalog["evidenceBindings"] as? [[String: Any]],
              bindings.count == 6,
              bindings[0]["kind"] as? String == "CAPABILITY",
              bindings[0]["sha256"] as? String == capabilityDigest,
              bindings[1]["kind"] as? String == "EVIDENCE",
              bindings[1]["sha256"] as? String == aggregateDigest,
              bindings[2]["kind"] as? String == "BRAND",
              bindings[2]["sha256"] as? String == brandDigest,
              bindings[3]["kind"] as? String == "CANDIDATE",
              bindings[3]["sha256"] as? String == candidateDigest,
              c15Keys(bindings[4], ["disposition", "kind", "sha256"]),
              bindings[4]["kind"] as? String == "APPROVAL",
              bindings[4]["disposition"] as? String == "DISABLED_OR_DEFERRED",
              bindings[4]["sha256"] is NSNull,
              c15Keys(bindings[5], ["disposition", "kind", "sha256"]),
              bindings[5]["kind"] as? String == "EXPIRY_SUPERSESSION",
              bindings[5]["disposition"] as? String == "DISABLED_OR_DEFERRED",
              bindings[5]["sha256"] is NSNull else {
            return false
        }

        let proofKinds = ["ACCESSIBILITY", "HOME", "PRIVACY", "SAMPLE_REPORT", "SUPPORT", "USE_CASE"]
        guard (accessibility["artifactKinds"] as? [String]) == proofKinds,
              let samples = synthetic["samples"] as? [[String: Any]],
              let proofs = brand["proofs"] as? [[String: Any]],
              let screenshots = catalog["screenshots"] as? [[String: Any]],
              samples.map({ $0["proofKind"] as? String }) == proofKinds,
              proofs.map({ $0["proofKind"] as? String }) == proofKinds,
              screenshots.map({ $0["proofKind"] as? String }) == proofKinds,
              samples.allSatisfy({
                  c15Keys($0, ["containsCustomerData", "contentSHA256", "displayWatermarks", "practiceWorkspace", "proofKind", "sampleID"])
                      && ($0["containsCustomerData"] as? Bool) == false
                      && c15SHA($0["contentSHA256"] as? String)
                      && (($0["displayWatermarks"] as? [String])?.contains("SYNTHETIC EXAMPLE — NO CUSTOMER DATA") == true)
                      && (!(($0["practiceWorkspace"] as? Bool) == true) || (($0["displayWatermarks"] as? [String])?.contains("PRACTICE — NOT FOR FIELD USE") == true))
                      && !c15ForbiddenIdentifier($0["sampleID"] as? String ?? "")
              }),
              proofs.allSatisfy({
                  c15Keys($0, ["finalScreenshot", "proofID", "proofKind", "shotListReference", "syntheticSampleID", "uploadReady", "wireframeOnly"])
                      && ($0["finalScreenshot"] as? Bool) == false
                      && ($0["uploadReady"] as? Bool) == false
                      && ($0["wireframeOnly"] as? Bool) == true
              }) else { return false }

        guard let locales = catalog["locales"] as? [[String: Any]],
              locales.map({ $0["locale"] as? String }) == ["en-US", "fr-FR"],
              locales.allSatisfy({ locale in
                  guard c15Keys(locale, ["description", "keywords", "locale", "name", "promotionalText", "publishEligibility", "status", "subtitle"]),
                        let name = locale["name"] as? String,
                        let subtitle = locale["subtitle"] as? String,
                        let keywords = locale["keywords"] as? String,
                        let promotional = locale["promotionalText"] as? String,
                        let description = locale["description"] as? String else { return false }
                  return c15CodePointCount(name) <= 30
                      && c15CodePointCount(subtitle) <= 30
                      && keywords.utf8.count <= 100
                      && c15CodePointCount(promotional) <= 170
                      && c15CodePointCount(description) <= 4000
                      && (locale["publishEligibility"] as? Bool) == false
                      && (locale["status"] as? String) == "DISABLED_OR_DEFERRED"
              }) else { return false }

        let aggregateFalse = ["analyticsEnabled", "attributionEnabled", "containsCustomerData", "containsDeviceJoinKey", "containsEntityJoinKey", "containsPersonJoinKey", "containsWorkspaceJoinKey", "externalProviderEnabled", "networkAccessEnabled", "sessionReplayEnabled", "stableJoinKeyEnabled"]
        guard aggregateFalse.allSatisfy({ aggregate[$0] as? Bool == false }),
              (aggregate["status"] as? String) == "AGGREGATE_UNJOINED_DECLARATION_ONLY",
              (aggregate["acquisitionEvidence"] as? [String: Any])?["aggregateOnly"] as? Bool == true,
              (accessibility["status"] as? String) == "NONCANDIDATE_STATIC_PROOF_ONLY",
              (accessibility["containsRealCustomerData"] as? Bool) == false,
              (accessibility["containsStableJoinKeys"] as? Bool) == false,
              (accessibility["networkProviderAnalyticsAttributionOrSessionReplay"] as? Bool) == false,
              (accessibility["sampleAndPracticeWatermarksRequired"] as? Bool) == true else { return false }

        guard let policy = privacy["c15DeclarationOnlyPolicy"] as? [String: Any],
              c15Keys(policy, ["backup", "canonicalPersistence", "containsRealCustomerContactLocationNoteOrEvidenceData", "delete", "export", "hasStablePersonDeviceWorkspaceOrEntityJoinKeys", "networkOrProviderAccess", "productOrReleaseCredit", "report", "retention", "telemetryAnalyticsAttributionOrSessionReplay"]),
              (policy["canonicalPersistence"] as? Bool) == false,
              (policy["containsRealCustomerContactLocationNoteOrEvidenceData"] as? Bool) == false,
              (policy["hasStablePersonDeviceWorkspaceOrEntityJoinKeys"] as? Bool) == false,
              (policy["networkOrProviderAccess"] as? Bool) == false,
              (policy["productOrReleaseCredit"] as? Bool) == false,
              (policy["telemetryAnalyticsAttributionOrSessionReplay"] as? Bool) == false,
              let artifacts = privacy["c15DeclarationOnlyArtifacts"] as? [[String: Any]],
              artifacts.allSatisfy({ c15Keys($0, ["classification", "id", "path"]) }),
              Set(artifacts.compactMap({ $0["path"] as? String })).isSuperset(of: Set(c15DeclarationPaths.dropLast())) else {
            return false
        }

        return true
    }

    private func c15CanonicalEqual(_ left: [String: Any], _ right: [String: Any]) -> Bool {
        guard let leftBytes = try? c15CanonicalJSON(left),
              let rightBytes = try? c15CanonicalJSON(right) else {
            return false
        }
        return leftBytes == rightBytes
    }

    private func validateC15(_ root: [String: Any]) -> Bool {
        let expectedRootKeys: Set<String> = [
            "schema",
            "schemaVersion",
            "cardID",
            "ordinal",
            "testOnly",
            "synthetic",
            "immutable",
            "containsCustomerData",
            "containsSecrets",
            "authority",
            "semantics",
            "selectors",
            "requirements",
            "catalog",
            "artifacts",
            "acquisition",
            "publication",
            "expectedDispositions",
            "hostileCases",
            "journalFaultBoundaries",
            "lifecycleCoverage",
            "recovery",
            "productState",
            "publicState",
            "statusFlags",
            "uiAdoptionSkipped",
        ]
        guard Set(root.keys) == expectedRootKeys,
              (root["schema"] as? String) == "V23P04C15DiscoveryTruthCorpusV1",
              (root["schemaVersion"] as? Int) == 1,
              (root["cardID"] as? String) == "V23-P04-C15",
              (root["ordinal"] as? Int) == 103,
              (root["testOnly"] as? Bool) == true,
              (root["synthetic"] as? Bool) == true,
              (root["immutable"] as? Bool) == true,
              (root["containsCustomerData"] as? Bool) == false,
              (root["containsSecrets"] as? Bool) == false,
              (root["uiAdoptionSkipped"] as? Bool) == true else {
            return false
        }

        guard let authority = root["authority"] as? [String: Any],
              c15Keys(authority, ["contextDigest", "pathFenceDigest", "sequence", "finalHashesSealed"]),
              c15SHA(authority["contextDigest"] as? String),
              c15SHA(authority["pathFenceDigest"] as? String),
              (authority["sequence"] as? Int) == 448,
              (authority["finalHashesSealed"] as? Bool) == false else {
            return false
        }

        guard let semantics = root["semantics"] as? [String: Any],
              c15Keys(
                  semantics,
                  [
                      "persistentContractMode",
                      "persistentContractSchema",
                      "publicationEligible",
                      "sixProofKinds",
                      "aggregateNoJoinKey",
                      "aggregateNoRealData",
                      "uiAdoption",
                  ]
              ),
              (semantics["persistentContractMode"] as? String) == "DECLARATION_ONLY",
              (semantics["persistentContractSchema"] as? String) == "DISCOVERY_TRUTH_CATALOG_V1",
              (semantics["publicationEligible"] as? Bool) == false,
              (semantics["sixProofKinds"] as? [String]) == [
                  "CAPABILITY",
                  "EVIDENCE",
                  "BRAND",
                  "CANDIDATE",
                  "APPROVAL",
                  "EXPIRY_SUPERSESSION",
              ],
              (semantics["aggregateNoJoinKey"] as? Bool) == true,
              (semantics["aggregateNoRealData"] as? Bool) == true,
              (semantics["uiAdoption"] as? String) == "POST_S10_6_SKIP_NO_CREDIT" else {
            return false
        }

        let selectorValues: [(String, String, String)] = [
            (
                "G01",
                "testV23P04C15G01DiscoveryTruthCatalogValidatesLocalizedLimitsAndClosedArtifactSet",
                "GOLDEN"
            ),
            (
                "A01",
                "testV23P04C15A01CategoriesAndAppTagsRemainSeparateTypedSets",
                "ALTERNATE"
            ),
            (
                "H01",
                "testV23P04C15H01HostileOpaqueStaleRealDataAndDraftPublishedInputsFailClosed",
                "HOSTILE"
            ),
            (
                "I01",
                "testV23P04C15I01InterruptedDeclarationGenerationLeavesZeroPartialOrCompleteArtifactSet",
                "INTERRUPTION"
            ),
            (
                "R01",
                "testV23P04C15R01DeletingAndRebuildingDeclarationArtifactsLeavesProductAndPublicStateUnchanged",
                "RECOVERY"
            ),
        ]
        guard let selectors = root["selectors"] as? [[String: Any]], selectors.count == selectorValues.count else {
            return false
        }
        for (selector, expected) in zip(selectors, selectorValues) {
            guard c15Keys(selector, ["id", "selector", "tier"]),
                  (selector["id"] as? String) == expected.0,
                  (selector["selector"] as? String) == expected.1,
                  (selector["tier"] as? String) == expected.2 else {
                return false
            }
        }

        guard let requirements = root["requirements"] as? [String: Any],
              c15Keys(
                  requirements,
                  [
                      "closedLocalizedPlatformLimits",
                      "categoriesAndAppTagsAreSeparate",
                      "candidateAndBrandRevisionBindExactly",
                      "staticProofKindsAreClosed",
                      "syntheticSamplesOnly",
                      "aggregateEvidenceHasNoStableJoinKeys",
                      "unapprovedClaimsDisabledOrDeferred",
                      "publicationProviderAndNetworkDisabled",
                      "interruptionIsZeroPartialOrComplete",
                      "declarationDeletionPreservesProductAndPublicState",
                  ]
              ),
              requirements.values.allSatisfy({ ($0 as? Bool) == true }) else {
            return false
        }

        guard let catalog = root["catalog"] as? [String: Any],
              c15Keys(catalog, ["candidate", "locales", "categories", "appTags", "screenshots", "claims"]),
              let candidate = catalog["candidate"] as? [String: Any],
              c15Keys(candidate, ["candidateID", "status", "brandBaselineID", "brandRevision", "brandRevisionSHA256"]),
              (candidate["candidateID"] as? String) == "c15-candidate-synthetic-v1",
              (candidate["status"] as? String) == "DRAFT_ONLY",
              (candidate["brandBaselineID"] as? String) == "c15-brand-baseline-synthetic-v1",
              (candidate["brandRevision"] as? String) == "c15-brand-revision-v1",
              c15SHA(candidate["brandRevisionSHA256"] as? String) else {
            return false
        }

        guard let locales = catalog["locales"] as? [[String: Any]], locales.count == 2 else {
            return false
        }
        var localesSeen = Set<String>()
        for locale in locales {
            guard c15Keys(locale, ["locale", "name", "subtitle", "keywords", "promotionalText", "description"]),
                  let localeID = locale["locale"] as? String,
                  ["en-US", "fr-FR"].contains(localeID),
                  localesSeen.insert(localeID).inserted,
                  let name = locale["name"] as? String,
                  let subtitle = locale["subtitle"] as? String,
                  let keywords = locale["keywords"] as? String,
                  let promotionalText = locale["promotionalText"] as? String,
                  let description = locale["description"] as? String,
                  !name.isEmpty,
                  !subtitle.isEmpty,
                  c15CodePointCount(name) <= 30,
                  c15CodePointCount(subtitle) <= 30,
                  keywords.lengthOfBytes(using: .utf8) <= 100,
                  c15CodePointCount(promotionalText) <= 170,
                  c15CodePointCount(description) <= 4000 else {
                return false
            }
        }
        guard localesSeen == ["en-US", "fr-FR"] else {
            return false
        }

        guard (catalog["categories"] as? [String]) == ["BUSINESS", "PRODUCTIVITY"],
              (catalog["appTags"] as? [String]) == ["EVIDENCE", "FIELD_WORK"],
              let categories = catalog["categories"] as? [String],
              let appTags = catalog["appTags"] as? [String],
              Set(categories).isDisjoint(with: Set(appTags)) else {
            return false
        }

        guard let screenshots = catalog["screenshots"] as? [[String: Any]], screenshots.count == 2 else {
            return false
        }
        let expectedScreenshots: [(String, String, String)] = [
            ("c15-shot-home-v1", "HOME", "c15-home-proof-v1"),
            ("c15-shot-report-v1", "SAMPLE_REPORT", "c15-sample-report-proof-v1"),
        ]
        for (screenshot, expected) in zip(screenshots, expectedScreenshots) {
            guard c15Keys(screenshot, ["id", "surface", "artifactID", "status", "publishable"]),
                  (screenshot["id"] as? String) == expected.0,
                  (screenshot["surface"] as? String) == expected.1,
                  (screenshot["artifactID"] as? String) == expected.2,
                  (screenshot["status"] as? String) == "DRAFT_ONLY",
                  (screenshot["publishable"] as? Bool) == false else {
                return false
            }
        }

        guard let claims = catalog["claims"] as? [[String: Any]], claims.count == 3 else {
            return false
        }
        let expectedClaimIDs: Set<String> = ["verified-outcomes", "ratings", "privacy-certification"]
        guard Set(claims.compactMap { $0["id"] as? String }) == expectedClaimIDs else {
            return false
        }
        for claim in claims {
            guard c15Keys(claim, ["id", "enabled", "status", "evidenceID"]),
                  (claim["enabled"] as? Bool) == false,
                  (claim["status"] as? String) == "DISABLED_OR_DEFERRED",
                  claim["evidenceID"] is NSNull else {
                return false
            }
        }

        guard let artifacts = root["artifacts"] as? [[String: Any]], artifacts.count == 6 else {
            return false
        }
        let expectedArtifacts: [(String, String, Bool, [String])] = [
            (
                "c15-home-proof-v1",
                "HOME",
                false,
                ["SYNTHETIC EXAMPLE — NO CUSTOMER DATA"]
            ),
            (
                "c15-use-case-proof-v1",
                "USE_CASE",
                false,
                ["SYNTHETIC EXAMPLE — NO CUSTOMER DATA"]
            ),
            (
                "c15-privacy-proof-v1",
                "PRIVACY",
                false,
                ["SYNTHETIC EXAMPLE — NO CUSTOMER DATA"]
            ),
            (
                "c15-accessibility-proof-v1",
                "ACCESSIBILITY",
                false,
                ["SYNTHETIC EXAMPLE — NO CUSTOMER DATA"]
            ),
            (
                "c15-support-proof-v1",
                "SUPPORT",
                false,
                ["SYNTHETIC EXAMPLE — NO CUSTOMER DATA"]
            ),
            (
                "c15-sample-report-proof-v1",
                "SAMPLE_REPORT",
                true,
                ["PRACTICE — NOT FOR FIELD USE", "SYNTHETIC EXAMPLE — NO CUSTOMER DATA"]
            ),
        ]
        var artifactIDs = Set<String>()
        for (artifact, expected) in zip(artifacts, expectedArtifacts) {
            guard c15Keys(
                      artifact,
                      [
                          "id",
                          "kind",
                          "status",
                          "publishable",
                          "containsCustomerData",
                          "practiceWorkspace",
                          "watermarks",
                          "contentSHA256",
                      ]
                  ),
                  let artifactID = artifact["id"] as? String,
                  artifactID == expected.0,
                  artifactIDs.insert(artifactID).inserted,
                  (artifact["kind"] as? String) == expected.1,
                  (artifact["status"] as? String) == "DRAFT_ONLY",
                  (artifact["publishable"] as? Bool) == false,
                  (artifact["containsCustomerData"] as? Bool) == false,
                  (artifact["practiceWorkspace"] as? Bool) == expected.2,
                  (artifact["watermarks"] as? [String]) == expected.3,
                  c15SHA(artifact["contentSHA256"] as? String),
                  !c15ForbiddenIdentifier(artifactID) else {
                return false
            }
        }

        guard let acquisition = root["acquisition"] as? [String: Any],
              c15Keys(
                  acquisition,
                  [
                      "enabled",
                      "claimStatus",
                      "source",
                      "provider",
                      "networkAccess",
                      "containsRealData",
                      "stableJoinKeys",
                      "personIdentifiers",
                      "deviceIdentifiers",
                      "workspaceIdentifiers",
                      "entityIdentifiers",
                      "watermark",
                  ]
              ),
              (acquisition["enabled"] as? Bool) == false,
              (acquisition["claimStatus"] as? String) == "DISABLED_OR_DEFERRED",
              (acquisition["source"] as? String) == "AGGREGATE_SYNTHETIC_FIXTURE",
              (acquisition["provider"] as? String) == "NONE",
              (acquisition["networkAccess"] as? Bool) == false,
              (acquisition["containsRealData"] as? Bool) == false,
              (acquisition["stableJoinKeys"] as? [String])?.isEmpty == true,
              (acquisition["personIdentifiers"] as? [String])?.isEmpty == true,
              (acquisition["deviceIdentifiers"] as? [String])?.isEmpty == true,
              (acquisition["workspaceIdentifiers"] as? [String])?.isEmpty == true,
              (acquisition["entityIdentifiers"] as? [String])?.isEmpty == true,
              (acquisition["watermark"] as? String) == "SYNTHETIC EXAMPLE — NO CUSTOMER DATA" else {
            return false
        }

        guard let publication = root["publication"] as? [String: Any],
              c15Keys(
                  publication,
                  ["status", "publishable", "upload", "signing", "deployment", "networkAccess", "provider"]
              ),
              (publication["status"] as? String) == "DRAFT_ONLY",
              (publication["publishable"] as? Bool) == false,
              (publication["upload"] as? Bool) == false,
              (publication["signing"] as? Bool) == false,
              (publication["deployment"] as? Bool) == false,
              (publication["networkAccess"] as? Bool) == false,
              (publication["provider"] as? String) == "NONE" else {
            return false
        }

        guard let dispositions = root["expectedDispositions"] as? [[String: Any]],
              dispositions.count == 4,
              dispositions.allSatisfy({
                  c15Keys($0, ["case", "disposition", "acceptedArtifactCount", "productWrites", "publicWrites"])
                      && (($0["acceptedArtifactCount"] as? Int) ?? -1) >= 0
                      && (($0["productWrites"] as? Int) ?? -1) == 0
                      && (($0["publicWrites"] as? Int) ?? -1) == 0
              }) else {
            return false
        }

        guard (root["hostileCases"] as? [String]) == [
                  "ARBITRARY_NONEMPTY_METADATA",
                  "PLATFORM_LIMIT_OVERFLOW",
                  "UNSUPPORTED_LOCALE",
                  "CATEGORY_AS_APP_TAG",
                  "STALE_BRAND_REVISION",
                  "UNIMPLEMENTED_ENABLED_CLAIM",
                  "REAL_DATA_IDENTIFIER",
                  "MISSING_SYNTHETIC_WATERMARK",
                  "MISSING_PRACTICE_WATERMARK",
                  "STABLE_JOIN_KEY",
                  "DRAFT_LABELED_PUBLISHED",
                  "PUBLICATION_PROVIDER_PATH",
                  "NETWORK_ACCESS_PATH",
              ],
              (root["journalFaultBoundaries"] as? [String]) == [
                  "BEFORE_ACCEPTED_ARTIFACT_WRITE",
                  "AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT",
                  "AFTER_RECEIPT_BEFORE_RETURN",
              ],
              (root["lifecycleCoverage"] as? [String]) == [
                  "DELETE_DECLARATION_DRAFTS",
                  "REBUILD_DECLARATION_DRAFTS",
                  "EXPORT_DECLARATION_REPORT",
                  "SEARCH_DECLARATION_FIXTURES",
                  "REPLAY_DECLARATION_RECEIPT",
              ] else {
            return false
        }

        guard let recovery = root["recovery"] as? [String: Any],
              c15Keys(
                  recovery,
                  [
                      "backupRestore",
                      "delete",
                      "rebuild",
                      "replay",
                      "preservesProductState",
                      "preservesPublicState",
                      "noProviderConnection",
                      "noUpload",
                  ]
              ),
              (recovery["backupRestore"] as? String) == "NOT_APPLICABLE_DECLARATION_ONLY",
              (recovery["delete"] as? String) == "DECLARATION_ONLY_ARTIFACTS",
              (recovery["rebuild"] as? String) == "EXACT_CATALOG_AND_ARTIFACT_SET",
              (recovery["replay"] as? String) == "ZERO_PARTIAL_OR_ONE_COMPLETE_RECEIPT",
              (recovery["preservesProductState"] as? Bool) == true,
              (recovery["preservesPublicState"] as? Bool) == true,
              (recovery["noProviderConnection"] as? Bool) == true,
              (recovery["noUpload"] as? Bool) == true else {
            return false
        }

        guard let productState = root["productState"] as? [String: Any],
              c15Keys(productState, ["canonicalWrites", "workspaceRecords", "publishedRecords", "mutationReceipts"]),
              productState.values.allSatisfy({ ($0 as? Int) == 0 }),
              let publicState = root["publicState"] as? [String: Any],
              c15Keys(publicState, ["publishedArtifacts", "uploads", "providerConnections", "networkRequests"]),
              publicState.values.allSatisfy({ ($0 as? Int) == 0 }),
              let flags = root["statusFlags"] as? [String: Any],
              c15Keys(
                  flags,
                  [
                      "activation",
                      "native",
                      "hosted",
                      "adoption",
                      "acceptance",
                      "release",
                      "publish",
                      "nativeAcceptance",
                      "hostedAcceptance",
                      "physicalEvidence",
                      "phase10PollingDuringParallelExecution",
                      "uiAcceptanceCredit",
                  ]
              ),
              flags.values.allSatisfy({ ($0 as? Bool) == false }) else {
            return false
        }

        return true
    }

    private func c15Keys(_ object: [String: Any], _ expected: [String]) -> Bool {
        Set(object.keys) == Set(expected)
    }

    private func c15CodePointCount(_ value: String?) -> Int {
        value?.unicodeScalars.count ?? 0
    }

    private func c15SHA(_ value: String?) -> Bool {
        guard let value = value, value.count == 64 else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
        }
    }

    private func c15ForbiddenIdentifier(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return ["customer", "person", "device", "workspace", "entity", "production", "real"].contains {
            lowercased.contains($0)
        }
    }

    private func c15CanonicalJSON(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func text(_ relativePath: String) throws -> String {
        try String(decoding: data(relativePath), as: UTF8.self)
    }

    private func jsonObject(_ relativePath: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(
            with: data(relativePath),
            options: []
        )
        return try XCTUnwrap(value as? [String: Any])
    }

    private func plistObject(_ value: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(
            from: value,
            options: [],
            format: nil
        )
        return try XCTUnwrap(object as? [String: Any])
    }

    private func nestedString(
        _ root: [String: Any],
        _ objectKey: String,
        _ valueKey: String
    ) throws -> String {
        let object = try XCTUnwrap(root[objectKey] as? [String: Any])
        return try XCTUnwrap(object[valueKey] as? String)
    }

    private func allReleaseText() throws -> String {
        let directory = repositoryRoot.appendingPathComponent("Release")
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.reduce(into: "") { result, url in
            result += String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
    }

    private func applicationSwiftSource() throws -> String {
        let root = repositoryRoot.appendingPathComponent("FieldEvidenceApp")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var source = ""
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            source += String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
        return source
    }

    private func validateManifest(
        _ root: [String: Any],
        providedRoot: [String: Any]
    ) -> Bool {
        guard Set(root.keys) == ["inputs", "releaseReady", "schemaVersion"],
              root["schemaVersion"] as? Int == 1,
              let releaseReady = root["releaseReady"] as? Bool,
              let inputs = root["inputs"] as? [[String: Any]],
              inputs.count == expectedInputKeys.count,
              inputs.compactMap({ $0["key"] as? String }) == expectedInputKeys,
              Set(inputs.compactMap({ $0["key"] as? String })).count == inputs.count,
              Set(providedRoot.keys) == ["schemaVersion", "values"],
              providedRoot["schemaVersion"] as? Int == 1,
              let values = providedRoot["values"] as? [String: Any]
        else {
            return false
        }

        let entryKeys: Set<String> = [
            "environmentKey",
            "key",
            "requiredFor",
            "secret",
            "source",
            "status",
            "valueKey",
        ]
        let validSources = Set([
            "repository",
            "owner",
            "app_store_connect",
            "github_environment",
        ])
        let validRequired = Set(["S9.1", "S9.2", "S9.3"])
        var expectedValues = Set<String>()
        var allProvided = true

        for input in inputs {
            guard Set(input.keys) == entryKeys,
                  let key = input["key"] as? String,
                  expectedInputKeys.contains(key),
                  let required = input["requiredFor"] as? String,
                  validRequired.contains(required),
                  let source = input["source"] as? String,
                  validSources.contains(source),
                  let status = input["status"] as? String,
                  status == "provided" || status == "pending",
                  let secret = input["secret"] as? Bool
            else {
                return false
            }
            allProvided = allProvided && status == "provided"
            if secret {
                guard input["valueKey"] is NSNull,
                      let environmentKey = input["environmentKey"] as? String,
                      environmentKey.range(
                        of: "^[A-Z0-9_]+$",
                        options: .regularExpression
                      ) != nil
                else {
                    return false
                }
            } else {
                guard input["environmentKey"] is NSNull,
                      let valueKey = input["valueKey"] as? String
                else {
                    return false
                }
                if status == "provided" {
                    expectedValues.insert(valueKey)
                } else if values[valueKey] != nil {
                    return false
                }
            }
        }

        guard releaseReady == allProvided,
              Set(values.keys) == expectedValues,
              values["appBundleID"] as? String == "com.palatis3.fieldrecord",
              values["unitTestBundleID"] as? String
                == "com.palatis3.fieldrecord.tests",
              values["uiTestBundleID"] as? String
                == "com.palatis3.fieldrecord.uitests",
              values["monthlyProductID"] as? String
                == "com.palatis3.fieldrecord.sub.solo.monthly.v1"
        else {
            return false
        }
        return true
    }

    private func validatePrivacy(_ root: [String: Any]) -> Bool {
        guard Set(root.keys) == [
            "NSPrivacyAccessedAPITypes",
            "NSPrivacyCollectedDataTypes",
            "NSPrivacyTracking",
            "NSPrivacyTrackingDomains",
        ],
        root["NSPrivacyTracking"] as? Bool == false,
        let domains = root["NSPrivacyTrackingDomains"] as? [Any],
        domains.isEmpty,
        let collected = root["NSPrivacyCollectedDataTypes"] as? [Any],
        collected.isEmpty,
        let accessed = root["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        else {
            return false
        }
        var actual: [String: [String]] = [:]
        for value in accessed {
            guard Set(value.keys) == [
                "NSPrivacyAccessedAPIType",
                "NSPrivacyAccessedAPITypeReasons",
            ],
            let category = value["NSPrivacyAccessedAPIType"] as? String,
            let reasons = value["NSPrivacyAccessedAPITypeReasons"] as? [String],
            actual[category] == nil
            else {
                return false
            }
            actual[category] = reasons
        }
        return actual == [
            "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["3B52.1", "C617.1"],
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        ]
    }

    private func validateWorkflow(_ value: String) -> Bool {
        guard value.contains("\non:\n  workflow_dispatch:\n"),
              !value.contains("\n  push:"),
              !value.contains("\n  pull_request:"),
              !value.contains("\n  schedule:"),
              !value.contains("\n  workflow_run:"),
              value.contains("cancel-in-progress: false"),
              value.contains("test \"$GITHUB_REF\" = \"refs/heads/main\""),
              value.contains("git ls-remote --exit-code origin refs/heads/main"),
              value.contains("environment: app-store-connect"),
              occurrences(of: "\n            archive\n", in: value) == 1,
              occurrences(of: "xcodebuild -exportArchive", in: value) == 1,
              occurrences(of: "xcrun altool --upload-app", in: value) == 1,
              !value.lowercased().contains("retry"),
              !value.lowercased().contains("max-attempts"),
              !value.contains("BEGIN PRIVATE KEY"),
              !value.contains("BEGIN RSA PRIVATE KEY")
        else {
            return false
        }
        let actions = value.split(separator: "\n").compactMap { line -> String? in
            guard let range = line.range(of: "uses: actions/") else { return nil }
            return String(line[range.lowerBound...])
        }
        guard actions.count == 2 else { return false }
        for action in actions {
            guard let reference = action.split(separator: "@").last?
                .split(separator: " ").first,
                  reference.count == 40,
                  reference.allSatisfy({ "0123456789abcdef".contains($0) })
            else {
                return false
            }
        }
        return true
    }

    private func manifestSecretEnvironmentKeys() throws -> Set<String> {
        let root = try jsonObject("Release/ReleaseInputManifestV1.json")
        let inputs = try XCTUnwrap(root["inputs"] as? [[String: Any]])
        return Set(inputs.compactMap { input in
            guard input["secret"] as? Bool == true else { return nil }
            return input["environmentKey"] as? String
        })
    }

    private func isLowercaseSHA(_ value: String?) -> Bool {
        guard let value, value.count == 40 else { return false }
        return value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private func occurrences(of needle: String, in value: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return value.components(separatedBy: needle).count - 1
    }

    private func deepCopy(_ value: [String: Any]) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: value)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}

extension S9_1ReleasePreflightTests {
    func testV23P04C27ProvisionalBrandHIGInventoryPreflightIsClosedAndSourceBound() throws {
        let inventory = try c27JSON("docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json")
        let contract = try c27JSON("docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryContractV1.json")
        let evidence = try c27JSON("docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryEvidenceReceiptV1.json")
        let impact = try c27JSON("docs/design/v23/tooling/V23P04C27BrandImpactManifestV1.json")
        let manifest = try c27JSON("docs/design/v23/tooling/V23-P04-C27-tooling-manifest.json")

        for (path, root) in [
            ("inventory", inventory), ("contract", contract), ("evidence", evidence),
            ("impact", impact), ("manifest", manifest),
        ] {
            XCTAssertEqual(root["cardID"] as? String, "V23-P04-C27", path)
            XCTAssertEqual(root["schemaVersion"] as? Int, 1, path)
            let flags = try XCTUnwrap(
                (root["statusFlags"] as? [String: Bool])
                    ?? (root["flags"] as? [String: Bool]),
                path
            )
            XCTAssertFalse(flags.isEmpty, path)
            XCTAssertTrue(flags.values.allSatisfy { !$0 }, path)
        }

        let contracts = try XCTUnwrap(inventory["contracts"] as? [String: Any])
        XCTAssertEqual(try c27Contract(contracts, "brandHIGStateInventory"), "BrandHIGStateInventoryContractV1")
        XCTAssertEqual(try c27Contract(contracts, "applicationStateInventory"), "ApplicationStateInventoryV1")
        XCTAssertEqual(try c27Contract(contracts, "brandVocabularyMap"), "BrandVocabularyMapV1")
        XCTAssertEqual(try c27Contract(contracts, "technicalIdentityFreeze"), "TechnicalIdentityFreezeV1")
        XCTAssertEqual(try c27Contract(contracts, "affectedConsumerGraph"), "AffectedConsumerGraphV1")
        XCTAssertEqual(try c27Contract(contracts, "brandPrePolishFreezeReceipt"), "BrandPrePolishFreezeReceiptV1")
        XCTAssertEqual(try c27Contract(contracts, "appIconReleaseManifest"), "AppIconReleaseManifestV1")

        let semantics = try XCTUnwrap(contract["semantics"] as? [String: Any])
        XCTAssertEqual(semantics["sevenContracts"] as? String, "NONPERSISTENT_INVENTORY_EVIDENCE")
        XCTAssertEqual(semantics["newDurableRecordCount"] as? Int, 0)
        XCTAssertEqual(semantics["newDurableFamilies"] as? [String], [])
        XCTAssertEqual(contract["provisional"] as? Bool, true)
        XCTAssertEqual(manifest["finalHashesSealed"] as? Bool, false)
        XCTAssertEqual(impact["uiAdoptionSkipped"] as? Bool, true)
        XCTAssertEqual(impact["uiAcceptanceCredit"] as? Bool, false)

        let interruption = try XCTUnwrap(evidence["generatorInterruptionProtocol"] as? [String: Any])
        XCTAssertEqual(interruption["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        let rows = try XCTUnwrap(interruption["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["acceptedSetCount"] as? Int }, [0, 0, 1])
        XCTAssertEqual(rows.compactMap { $0["retryAcceptedSetCount"] as? Int }, [1, 1, 1])

        let sourceProjection = try XCTUnwrap(contract["sourceProjection"] as? [String: Any])
        XCTAssertEqual(sourceProjection["sourceReady"] as? Bool, true)
        let sourceRows = try XCTUnwrap(sourceProjection["sourceRows"] as? [[String: Any]])
        XCTAssertFalse(sourceRows.isEmpty)
        for row in sourceRows {
            let relativePath = try XCTUnwrap(row["path"] as? String)
            let expected = try XCTUnwrap(row["sha256"] as? String)
            XCTAssertFalse(relativePath.hasPrefix("/"))
            XCTAssertFalse(relativePath.contains(".."))
            XCTAssertEqual(c27Digest(try data(relativePath)), expected, relativePath)
        }

        let preflight = String(decoding: try data("Scripts/release-preflight.sh"), as: UTF8.self)
        XCTAssertTrue(preflight.contains("generate_p04_c27_contracts.py --check"))
        XCTAssertTrue(preflight.contains("verify_p04_c27_contracts.py --json"))
        XCTAssertTrue(preflight.contains("assert all(value is False for value in flags.values())"))
        XCTAssertTrue(preflight.contains("manifest[\"finalHashesSealed\"] is False"))
        XCTAssertTrue(preflight.contains("uiAcceptanceCredit\"] is False"))
    }

    private func c27JSON(_ relativePath: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(relativePath)) as? [String: Any])
    }

    private func c27Contract(_ contracts: [String: Any], _ key: String) throws -> String {
        let value = try XCTUnwrap(contracts[key] as? [String: Any])
        return try XCTUnwrap(value["contract"] as? String)
    }

    private func c27Digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

extension S9_1ReleasePreflightTests {
    func testV23P04C29ReleasePreflightBindsObservedGeneratorSelfTestWithoutReleaseClaim() throws {
        let corpus = try c29JSON(
            "FieldEvidenceAppTests/Fixtures/V23/Brand/V23P04C29ExactCandidateRegressionFreezeCorpusV1.json"
        )
        let ledger = try c29JSON(
            "docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json"
        )
        let observed = try XCTUnwrap(
            (try XCTUnwrap(corpus["productLedger"] as? [String: Any]))["observedSelfTest"] as? [String: Any]
        )
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C29")
        XCTAssertEqual(ledger["cardID"] as? String, "V23-P04-C29")
        let c13Coverage = try XCTUnwrap(ledger["p00C13Coverage"] as? [String: Any])
        XCTAssertEqual(c13Coverage["cardID"] as? String, "V23-P00-C13")
        XCTAssertEqual(c13Coverage["executionDependency"] as? String, "V23-P04-C28")
        XCTAssertEqual(c13Coverage["semanticDirectPrerequisite"] as? Bool, true)
        XCTAssertEqual(
            observed["commands"] as? [[String: String]],
            [
                ["command": "python -B Scripts/v23/generate_p04_c29_contracts.py --self-test --json", "mode": "GENERATOR_MANIFEST_LAST_RECOVERY"],
                ["command": "python -B Scripts/v23/verify_p04_c29_contracts.py --complete --json", "mode": "COMPLETE_STATIC_PROVISIONAL"],
            ]
        )
        XCTAssertEqual(observed["candidate"] as? [String: String], corpus["candidateFreeze"] as? [String: String])
        XCTAssertEqual(
            try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(observed["authority"] as? [String: Any]),
                options: [.sortedKeys]
            ),
            try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(corpus["authority"] as? [String: Any]),
                options: [.sortedKeys]
            )
        )
        XCTAssertTrue((corpus["statusFlags"] as? [String: Bool])?.values.allSatisfy { !$0 } == true)

        let preflight = try text("Scripts/release-preflight.sh")
        for required in [
            "generate_p04_c29_contracts.py --self-test --json",
            "verify_p04_c29_contracts.py --complete --json",
            "observed == verifier[\"observedSelfTest\"]",
            "canonicalResultSHA256",
            "PASS_STATIC_PROVISIONAL",
        ] {
            XCTAssertTrue(preflight.contains(required), required)
        }
    }

    private func c29JSON(_ path: String) throws -> [String: Any] {
        try jsonObject(path)
    }

    func testV23P04C28ReleasePreflightMirrorsProvisionalSharedRootCorrection() throws {
        let ledger = try c28JSON(
            "docs/product/brand/V23P04C28BrandHIGSharedRootCorrectionLedgerV1.json"
        )
        let corpus = try c28JSON(
            "FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C28BrandHIGSharedRootCorrectionCorpusV1.json"
        )
        let contract = try c28JSON(
            "docs/design/v23/tooling/V23P04C28BrandHIGSharedRootCorrectionContractV1.json"
        )
        let evidence = try c28JSON(
            "docs/design/v23/tooling/V23P04C28BrandHIGSharedRootCorrectionEvidenceReceiptV1.json"
        )
        let impact = try c28JSON(
            "docs/design/v23/tooling/V23P04C28BrandImpactManifestV1.json"
        )
        let manifest = try c28JSON(
            "docs/design/v23/tooling/V23-P04-C28-tooling-manifest.json"
        )
        let schema = try c28JSON("Scripts/v23/brand-hig-shared-root-correction.schema.json")

        for (path, root) in [
            ("ledger", ledger), ("corpus", corpus), ("contract", contract),
            ("evidence", evidence), ("impact", impact), ("manifest", manifest),
        ] {
            XCTAssertEqual(root["cardID"] as? String, "V23-P04-C28", path)
            if root["schemaVersion"] != nil {
                XCTAssertEqual(root["schemaVersion"] as? Int, 1, path)
            }
            let flags = try XCTUnwrap(
                (root["statusFlags"] as? [String: Bool])
                    ?? (root["flags"] as? [String: Bool]),
                path
            )
            XCTAssertFalse(flags.isEmpty, path)
            XCTAssertTrue(flags.values.allSatisfy { !$0 }, path)
        }
        XCTAssertEqual(
            schema["$schema"] as? String,
            "https://json-schema.org/draft/2020-12/schema"
        )

        let selectors = [
            "testV23P04C28G01LowestOwnerCorrectionsCloseC27FindingsAndPreserveHistoricReports",
            "testV23P04C28A01NativeSemanticParityPreservesTasksIdentityAndHistoricBytes",
            "testV23P04C28H01SharedStateRoleAXContrastClaimsAndReportDriftFailClosed",
            "testV23P04C28I01InterruptedCorrectionPreservesAcceptedC27BaselineAndNoPartialReceipt",
            "testV23P04C28R01RejectedDirectionAndFailedRetryPreserveAcceptedBrandRevision",
        ]
        XCTAssertEqual(ledger["selectors"] as? [String], selectors)
        XCTAssertEqual(corpus["selectors"] as? [String], selectors)
        XCTAssertEqual(contract["selectors"] as? [String], selectors)
        XCTAssertEqual(evidence["selectors"] as? [String], selectors)
        let c28Tests = try text(
            "FieldEvidenceAppTests/V9_91BrandHIGSharedRootCorrectionTests.swift"
        )
        for selector in selectors {
            XCTAssertTrue(c28Tests.contains("func \(selector)"), selector)
        }

        let predecessor = try XCTUnwrap(corpus["predecessor"] as? [String: Any])
        XCTAssertEqual(predecessor["cardID"] as? String, "V23-P04-C27")
        XCTAssertEqual(
            predecessor["inventorySHA256"] as? String,
            c28Digest(try data("docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json"))
        )
        let sourcePins = try XCTUnwrap(ledger["sourcePins"] as? [String: Any])
        let c27Binding = try XCTUnwrap(sourcePins["c27Inventory"] as? [String: Any])
        XCTAssertEqual(
            c27Binding["path"] as? String,
            "docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json"
        )
        XCTAssertEqual(
            c27Binding["sha256"] as? String,
            c28Digest(try data("docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json"))
        )
        XCTAssertEqual(c27Binding["utf8Length"] as? Int, 13934)
        let expectedSourcePinKeys: Set<String> = [
            "acceptedAppHead", "acceptedAppTree", "allocationRevision",
            "c27CheckpointDigest", "c27Inventory", "c27VerificationReceiptDigest",
            "casSequence", "contextDigest", "coordinationAuthorityHead",
            "coordinationAuthorityTree", "coordinationCorrectionTransitionDigest",
            "coordinationLedgerDigest", "frozenS10ReservationDigest",
            "ownerAuthorizedPathAllocationDigest", "pathFenceDigest",
            "provisionalPrerequisiteDigest", "sourceProjectionDigest",
            "supersedesOwnerAuthorizedPathAllocationDigest",
        ]
        XCTAssertEqual(Set(sourcePins.keys), expectedSourcePinKeys)
        XCTAssertEqual(
            sourcePins["acceptedAppHead"] as? String,
            "803f75bc94a46b7b0ca50b14f1a49401f38550f1"
        )
        XCTAssertEqual(
            sourcePins["acceptedAppTree"] as? String,
            "6f1cc0077cf74a1adb532124880b1cd5e4a031cc"
        )
        XCTAssertEqual(
            sourcePins["coordinationAuthorityHead"] as? String,
            "b30a1640d495bd2d6641ea2dbd816d8d4d23a186"
        )
        XCTAssertEqual(
            sourcePins["coordinationAuthorityTree"] as? String,
            "f5b3106d41380a906cfa1c0cbf9cdcc8268b4d22"
        )
        XCTAssertEqual(sourcePins["casSequence"] as? Int, 507)
        XCTAssertEqual(sourcePins["allocationRevision"] as? Int, 2)
        XCTAssertEqual(
            sourcePins["ownerAuthorizedPathAllocationDigest"] as? String,
            "27c242e6c316767b3731c3bda81948ad8a8dc5258b54c385994248c24033f48c"
        )
        XCTAssertEqual(
            sourcePins["supersedesOwnerAuthorizedPathAllocationDigest"] as? String,
            "f296173b2ae29f892447395bba5d2a48817607375e8da8d3173faf5ff739f3c1"
        )
        XCTAssertEqual(
            sourcePins["contextDigest"] as? String,
            "1b2bff5c876c8f618dae7015b12d4dd51d431c6756678824d72421b4d55a80a9"
        )
        XCTAssertEqual(
            sourcePins["pathFenceDigest"] as? String,
            "52a48f30deafc62962e99607f690e84fb393f668c548a01fe496b96b450d3817"
        )
        XCTAssertEqual(
            sourcePins["provisionalPrerequisiteDigest"] as? String,
            "83888037dd5c9762466f711f232ef5ecad7f34ffce1d773795f10dd8920763ce"
        )
        XCTAssertEqual(
            sourcePins["coordinationCorrectionTransitionDigest"] as? String,
            "2b610d2031667696ba09337e194c8b42e39e09265fc6245a3f94fdd6271ac294"
        )
        XCTAssertEqual(
            sourcePins["coordinationLedgerDigest"] as? String,
            "5dd37b9b75422a8366b9e052781d09d022951ed2b3cbe51492765ab58cf2eb5f"
        )
        XCTAssertEqual(
            sourcePins["sourceProjectionDigest"] as? String,
            "a7064d17aa0bdd7ef1401b411087ff38c64ecefff7a3a9515039aa009d963df5"
        )
        XCTAssertEqual(
            sourcePins["frozenS10ReservationDigest"] as? String,
            "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
        )
        XCTAssertEqual(
            sourcePins["c27CheckpointDigest"] as? String,
            "f0be43c24a0a88989a795cc288892165bda6f612af84168bff407f036ece7cd1"
        )
        XCTAssertEqual(
            sourcePins["c27VerificationReceiptDigest"] as? String,
            "d7325ff7763660b5a24d79e4a7174b00b825c30352a1b4972f4343a3d36d5c60"
        )

        let expectedStableIDs: Set<String> = [
            "feedback.mail.attachment-count", "feedback.mail.body",
            "feedback.mail.done", "feedback.mail.recipient", "feedback.mail.screen",
        ]
        let receipt = try XCTUnwrap(ledger["sharedBrandCorrectionReceipt"] as? [String: Any])
        let mappings = try XCTUnwrap(receipt["afterSemanticMappings"] as? [[String: Any]])
        XCTAssertEqual(Set(mappings.compactMap { $0["stableID"] as? String }), expectedStableIDs)
        XCTAssertTrue(mappings.allSatisfy {
            guard let stableID = $0["stableID"] as? String,
                  let legacyID = $0["legacyID"] as? String else { return false }
            return stableID != legacyID
        })
        let semantics = try XCTUnwrap(corpus["stableFeedbackSemantics"] as? [[String: Any]])
        XCTAssertEqual(Set(semantics.compactMap { $0["id"] as? String }), expectedStableIDs)
        XCTAssertTrue(semantics.allSatisfy {
            ($0["deprecatedAliases"] as? [String] ?? []).isEmpty
        })

        let expectedClusterIDs = [
            "all-other-shipping-phase-number-ids-in-S10-reserved-ui-root-paths",
            "visual-DesignTokens-and-WorklightComponents",
            "saved-photo-RecordWork-and-IssueDetail",
            "app-icon-and-artwork",
        ]
        let expectedClusterCounts = [18, 2, 2, 4]
        let deferred = try XCTUnwrap(ledger["deferredAcceptedS10_6Clusters"] as? [[String: Any]])
        XCTAssertEqual(deferred.count, expectedClusterIDs.count)
        XCTAssertEqual(deferred.map { $0["clusterID"] as? String }, expectedClusterIDs)
        XCTAssertEqual(
            deferred.compactMap { ($0["memberPaths"] as? [[String: Any]])?.count },
            expectedClusterCounts
        )
        XCTAssertTrue(deferred.allSatisfy {
            $0["adopted"] as? Bool == false
                && $0["disposition"] as? String == "DEFERRED_PENDING_ACCEPTED_S10_6"
                && $0["reservationDigest"] as? String
                    == "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
        })
        var deferredPaths = Set<String>()
        for row in deferred {
            let members = try XCTUnwrap(row["memberPaths"] as? [[String: Any]])
            let paths = try members.map { try XCTUnwrap($0["path"] as? String) }
            XCTAssertEqual(paths.count, Set(paths).count)
            paths.forEach { deferredPaths.insert($0) }
        }
        XCTAssertEqual(deferredPaths.count, 26)
        let corpusDeferred = try XCTUnwrap(corpus["deferredS10Clusters"] as? [[String: Any]])
        XCTAssertEqual(corpusDeferred.count, expectedClusterIDs.count)
        XCTAssertEqual(corpusDeferred.map { $0["clusterID"] as? String }, expectedClusterIDs)
        XCTAssertEqual(
            corpusDeferred.compactMap { ($0["memberPaths"] as? [[String: Any]])?.count },
            expectedClusterCounts
        )
        XCTAssertTrue(corpusDeferred.allSatisfy {
            $0["adopted"] as? Bool == false
                && $0["acceptanceCredit"] as? Bool == false
                && $0["disposition"] as? String == "DEFERRED_PENDING_ACCEPTED_S10_6"
                && $0["reservationDigest"] as? String
                    == "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
        })
        var corpusDeferredPaths = Set<String>()
        for row in corpusDeferred {
            let members = try XCTUnwrap(row["memberPaths"] as? [[String: Any]])
            let paths = try members.map { try XCTUnwrap($0["path"] as? String) }
            XCTAssertEqual(paths.count, Set(paths).count)
            paths.forEach { _ = corpusDeferredPaths.insert($0) }
        }
        XCTAssertEqual(corpusDeferredPaths, deferredPaths)

        let brandRevision = try XCTUnwrap(
            ledger["brandRevisionImplementationReceipt"] as? [String: Any]
        )
        XCTAssertEqual(brandRevision["activated"] as? Bool, false)
        XCTAssertEqual(brandRevision["authorizedChange"] as? Bool, false)
        XCTAssertEqual(brandRevision["disposition"] as? String, "NOT_ACTIVATED_NO_APPROVED_DECISION")
        let appIcon = try XCTUnwrap(ledger["appIconRevisionReceipt"] as? [String: Any])
        XCTAssertEqual(appIcon["adopted"] as? Bool, false)
        XCTAssertEqual(appIcon["authorizedChange"] as? Bool, false)
        XCTAssertEqual(appIcon["disposition"] as? String, "NOT_EMITTED_NO_AUTHORIZED_CHANGE")
        XCTAssertEqual(
            corpus["brandRevisionDisposition"] as? String,
            "UNCHANGED_NO_ACCEPTED_DIRECTION"
        )
        XCTAssertEqual(
            corpus["appIconDisposition"] as? String,
            "NO_CHANGE_NO_ACCEPTED_BRAND_INTENT"
        )

        let historic = try XCTUnwrap(corpus["historicReportBindings"] as? [[String: Any]])
        XCTAssertEqual(historic.count, 2)
        for binding in historic {
            let path = try XCTUnwrap(binding["path"] as? String)
            let expected = try XCTUnwrap(binding["sha256"] as? String)
            XCTAssertEqual(c28Digest(try data(path)), expected, path)
        }
        let preservation = try XCTUnwrap(ledger["preservation"] as? [String: Any])
        XCTAssertEqual(preservation["historicReportBytesRewritten"] as? Bool, false)
        XCTAssertEqual(preservation["technicalIdentityChanged"] as? Bool, false)
        let lifecycle = try XCTUnwrap(ledger["lifecycle"] as? [String: Any])
        XCTAssertEqual(lifecycle["persistentKindCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["writerCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["workspaceMutationReceiptCreated"] as? Bool, false)
        let candidate = try XCTUnwrap(ledger["candidate"] as? [String: Any])
        XCTAssertTrue(candidate["head"] is NSNull)
        XCTAssertEqual(candidate["sealDisposition"] as? String, "UNSEALED_PROVISIONAL")
        XCTAssertTrue(candidate["tree"] is NSNull)

        let preflight = try text("Scripts/release-preflight.sh")
        for token in [
            "c28_generator_script=\"Scripts/v23/generate_p04_c28_contracts.py\"",
            "c28_verifier_script=\"Scripts/v23/verify_p04_c28_contracts.py\"",
            "--check", "--self-test --json", "--complete --json",
            "recoveryAcceptedSetCount", "secondRetryAcceptedSetCount",
            "recoveryTreeDigest", "secondRetryTreeDigest",
            "c28_fence_path_count", "c28_required_fence_path_count",
            "missingPathCount", "unownedChangedPathCount", "s10ReservationOverlapCount",
            "finalHashesSealed", "flagsAllFalse", "s8.4.mail",
            "deferredAcceptedS10_6Clusters", "BrandRevision", "AppIcon",
        ] {
            XCTAssertTrue(preflight.contains(token), token)
        }
        XCTAssertFalse(preflight.contains("fencePathCount == 21"))
        XCTAssertFalse(preflight.contains("changedPathCount == 21"))
    }

    private func c28JSON(_ relativePath: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(relativePath)) as? [String: Any])
    }

    private func c28Digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

extension S9_1ReleasePreflightTests {
    func testV23P04C26G01BoundCatalogRefinementAndDisabledPublication() throws {
        let sources = try c26Sources()
        XCTAssertTrue(try c26Validate(sources))

        let claims = try XCTUnwrap(sources.acquisition["claims"] as? [[String: Any]])
        XCTAssertEqual(claims.count, 6)
        XCTAssertEqual(Set(claims.compactMap { $0["acceptedFeatureCard"] as? String }), [
            "V23-P04-C16", "V23-P04-C17", "V23-P04-C18",
            "V23-P04-C19", "V23-P04-C20", "V23-P04-C21",
        ])
        for claim in claims {
            let binding = try XCTUnwrap(claim["acceptanceBinding"] as? [String: Any])
            XCTAssertEqual(binding["currentness"] as? String, "CHECKPOINTED_CURRENT")
            XCTAssertEqual(binding["compatibilityDisposition"] as? String, "CURRENT_NOT_SUPERSEDED")
            XCTAssertEqual(binding["recoveryProof"] as? String, "MATCHING_PROVISIONAL_VERIFICATION_RECEIPT")
            XCTAssertTrue(c26SHA(binding["checkpointSHA256"] as? String))
            XCTAssertTrue(c26SHA(binding["verificationSHA256"] as? String))
            XCTAssertTrue(c26SHA(claim["receiptSHA256"] as? String))
        }

        let artifactBindings = try XCTUnwrap(
            sources.receipt["artifactBindings"] as? [[String: Any]]
        )
        XCTAssertEqual(artifactBindings.count, 3)
        for binding in artifactBindings {
            XCTAssertTrue(try c26BindingMatchesFile(binding))
        }
    }

    func testV23P04C26A01ApprovalAbsenceDefersAllPublication() throws {
        let sources = try c26Sources()
        XCTAssertTrue(try c26Validate(sources))

        for root in [sources.acquisition, sources.tags, sources.receipt, sources.metadata] {
            let approval = try XCTUnwrap(root["approval"] as? [String: Any])
            XCTAssertEqual(Set(approval.keys), ["decisionReference", "sha256", "status"])
            XCTAssertTrue(approval["decisionReference"] is NSNull)
            XCTAssertTrue(approval["sha256"] is NSNull)
            XCTAssertEqual(approval["status"] as? String, "DISABLED_OR_DEFERRED")
            XCTAssertEqual(root["publishEligibility"] as? Bool, false)
        }

        let control = try XCTUnwrap(sources.acquisition["control"] as? [String: Any])
        let hypotheses = try XCTUnwrap(sources.acquisition["ppoHypotheses"] as? [[String: Any]])
        XCTAssertEqual(control["status"] as? String, "DISABLED_OR_DEFERRED")
        XCTAssertLessThanOrEqual(hypotheses.count, 3)
        XCTAssertTrue(hypotheses.allSatisfy { ($0["uploadReady"] as? Bool) == false })
        let suggestions = try XCTUnwrap(sources.tags["observedSuggestions"] as? [String: Any])
        XCTAssertEqual(suggestions["suggestions"] as? [String], [])
        XCTAssertEqual(suggestions["displayGuaranteed"] as? Bool, false)
    }

    func testV23P04C26H01HostileClaimsBindingsAndMetadataLimitsFailClosed() throws {
        let valid = try c26Sources()
        XCTAssertTrue(try c26Validate(valid))

        var stale = valid
        var staleClaims = try XCTUnwrap(stale.acquisition["claims"] as? [[String: Any]])
        var staleBinding = try XCTUnwrap(staleClaims[0]["acceptanceBinding"] as? [String: Any])
        staleBinding["currentness"] = "STALE"
        staleClaims[0]["acceptanceBinding"] = staleBinding
        stale.acquisition["claims"] = staleClaims
        XCTAssertFalse(try c26Validate(stale))

        var forgedDigest = valid
        var forgedDigestClaims = try XCTUnwrap(
            forgedDigest.acquisition["claims"] as? [[String: Any]]
        )
        var forgedDigestBinding = try XCTUnwrap(
            forgedDigestClaims[0]["acceptanceBinding"] as? [String: Any]
        )
        forgedDigestBinding["checkpointSHA256"] = String(repeating: "a", count: 64)
        forgedDigestClaims[0]["acceptanceBinding"] = forgedDigestBinding
        forgedDigest.acquisition["claims"] = forgedDigestClaims
        XCTAssertFalse(try c26Validate(forgedDigest))

        var forgedHead = valid
        var forgedHeadClaims = try XCTUnwrap(forgedHead.acquisition["claims"] as? [[String: Any]])
        var forgedHeadBinding = try XCTUnwrap(
            forgedHeadClaims[0]["acceptanceBinding"] as? [String: Any]
        )
        forgedHeadBinding["acceptedCandidateHead"] = String(repeating: "a", count: 40)
        forgedHeadClaims[0]["acceptanceBinding"] = forgedHeadBinding
        forgedHead.acquisition["claims"] = forgedHeadClaims
        XCTAssertFalse(try c26Validate(forgedHead))

        var forgedTree = valid
        var forgedTreeClaims = try XCTUnwrap(forgedTree.acquisition["claims"] as? [[String: Any]])
        var forgedTreeBinding = try XCTUnwrap(
            forgedTreeClaims[0]["acceptanceBinding"] as? [String: Any]
        )
        forgedTreeBinding["acceptedCandidateTree"] = String(repeating: "b", count: 40)
        forgedTreeClaims[0]["acceptanceBinding"] = forgedTreeBinding
        forgedTree.acquisition["claims"] = forgedTreeClaims
        XCTAssertFalse(try c26Validate(forgedTree))

        var forgedCard = valid
        var forgedCardClaims = try XCTUnwrap(forgedCard.acquisition["claims"] as? [[String: Any]])
        forgedCardClaims[0]["acceptedFeatureCard"] = "V23-P04-C99"
        forgedCard.acquisition["claims"] = forgedCardClaims
        XCTAssertFalse(try c26Validate(forgedCard))

        var forgedReceipt = valid
        var forgedReceiptClaims = try XCTUnwrap(
            forgedReceipt.acquisition["claims"] as? [[String: Any]]
        )
        forgedReceiptClaims[0]["receiptSHA256"] = String(repeating: "c", count: 64)
        forgedReceipt.acquisition["claims"] = forgedReceiptClaims
        XCTAssertFalse(try c26Validate(forgedReceipt))

        var swappedCards = valid
        var swappedClaims = try XCTUnwrap(
            swappedCards.acquisition["claims"] as? [[String: Any]]
        )
        let firstAcceptedTuple = (
            swappedClaims[0]["acceptedFeatureCard"],
            swappedClaims[0]["receiptSHA256"],
            swappedClaims[0]["acceptanceBinding"]
        )
        swappedClaims[0]["acceptedFeatureCard"] = swappedClaims[1]["acceptedFeatureCard"]
        swappedClaims[0]["receiptSHA256"] = swappedClaims[1]["receiptSHA256"]
        swappedClaims[0]["acceptanceBinding"] = swappedClaims[1]["acceptanceBinding"]
        swappedClaims[1]["acceptedFeatureCard"] = firstAcceptedTuple.0
        swappedClaims[1]["receiptSHA256"] = firstAcceptedTuple.1
        swappedClaims[1]["acceptanceBinding"] = firstAcceptedTuple.2
        swappedCards.acquisition["claims"] = swappedClaims
        XCTAssertFalse(try c26Validate(swappedCards))

        let authoritativeClaim = try XCTUnwrap(
            (valid.acquisition["claims"] as? [[String: Any]])?.first
        )
        let authoritativeCard = try XCTUnwrap(
            authoritativeClaim["acceptedFeatureCard"] as? String
        )
        let authoritativeBinding = try XCTUnwrap(
            authoritativeClaim["acceptanceBinding"] as? [String: Any]
        )
        let authoritativeCheckpointPath = try XCTUnwrap(
            authoritativeBinding["checkpointPath"] as? String
        )
        let authoritativeCheckpointURL = try XCTUnwrap(
            c26EvidenceURL(authoritativeCheckpointPath)
        )
        let authoritativeCheckpoint = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: authoritativeCheckpointURL)
            ) as? [String: Any]
        )
        var unknownCheckpointSchema = authoritativeCheckpoint
        unknownCheckpointSchema["schema"] = "UnknownCheckpointReceiptV1"
        XCTAssertFalse(c26CheckpointProfileValid(unknownCheckpointSchema, cardID: authoritativeCard))
        var falseCheckpointFlag = authoritativeCheckpoint
        falseCheckpointFlag["flagsAllFalse"] = false
        XCTAssertFalse(c26CheckpointProfileValid(falseCheckpointFlag, cardID: authoritativeCard))
        var falseCheckpointSeal = authoritativeCheckpoint
        falseCheckpointSeal["finalHashesSealed"] = false
        XCTAssertFalse(c26CheckpointProfileValid(falseCheckpointSeal, cardID: authoritativeCard))

        var extraForbiddenField = valid
        extraForbiddenField.acquisition["networkAccess"] = false
        XCTAssertFalse(try c26Validate(extraForbiddenField))

        var trueForbiddenField = valid
        trueForbiddenField.acquisition["publish"] = true
        XCTAssertFalse(try c26Validate(trueForbiddenField))

        var trueForbiddenCapability = valid
        var forbiddenCapabilities = try XCTUnwrap(
            trueForbiddenCapability.acquisition["forbiddenCapabilities"] as? [String: Any]
        )
        forbiddenCapabilities["paidAcquisition"] = true
        trueForbiddenCapability.acquisition["forbiddenCapabilities"] = forbiddenCapabilities
        XCTAssertFalse(try c26Validate(trueForbiddenCapability))

        var coherentPageAndClaim = valid
        var coherentPages = try XCTUnwrap(
            coherentPageAndClaim.acquisition["supportPageSpecs"] as? [[String: Any]]
        )
        var coherentClaims = try XCTUnwrap(
            coherentPageAndClaim.acquisition["claims"] as? [[String: Any]]
        )
        coherentPages[0]["claimID"] = "c26-coherent-forgery-v1"
        let coherentClaimIndex = try XCTUnwrap(
            coherentClaims.firstIndex { $0["claimID"] as? String == "c26-accessibility-support-v1" }
        )
        coherentClaims[coherentClaimIndex]["claimID"] = "c26-coherent-forgery-v1"
        coherentPageAndClaim.acquisition["supportPageSpecs"] = coherentPages
        coherentPageAndClaim.acquisition["claims"] = coherentClaims
        XCTAssertFalse(try c26Validate(coherentPageAndClaim))

        var duplicateKeyword = valid
        var duplicateLocales = try XCTUnwrap(
            duplicateKeyword.acquisition["locales"] as? [[String: Any]]
        )
        duplicateLocales[0]["keywords"] = "field,inspection"
        duplicateKeyword.acquisition["locales"] = duplicateLocales
        XCTAssertFalse(try c26Validate(duplicateKeyword))

        var multibyteOverflow = valid
        var multibyteLocales = try XCTUnwrap(
            multibyteOverflow.acquisition["locales"] as? [[String: Any]]
        )
        multibyteLocales[0]["keywords"] = String(repeating: "é", count: 51)
        multibyteOverflow.acquisition["locales"] = multibyteLocales
        XCTAssertFalse(try c26Validate(multibyteOverflow))

        var nearDuplicate = valid
        var pages = try XCTUnwrap(nearDuplicate.acquisition["supportPageSpecs"] as? [[String: Any]])
        pages[1]["title"] = pages[0]["title"]
        pages[1]["summary"] = pages[0]["summary"]
        pages[1]["limitations"] = pages[0]["limitations"]
        var nearDuplicateMetadata = nearDuplicate.metadata
        try c26RecomputePageEvidence(&pages, metadata: &nearDuplicateMetadata)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(pages[1]["maximumPairwiseTokenOverlapBasisPoints"] as? Int),
            try XCTUnwrap(pages[1]["nearDuplicateThresholdBasisPoints"] as? Int)
        )
        nearDuplicate.acquisition["supportPageSpecs"] = pages
        nearDuplicate.metadata = nearDuplicateMetadata
        XCTAssertFalse(try c26Validate(nearDuplicate))

        var licensed = valid
        var structured = try XCTUnwrap(licensed.metadata["structuredData"] as? [String: Any])
        structured["licensedThirdPartyContentDetected"] = true
        licensed.metadata["structuredData"] = structured
        XCTAssertFalse(try c26Validate(licensed))

        var fabricated = valid
        var fabricatedClaims = try XCTUnwrap(fabricated.acquisition["claims"] as? [[String: Any]])
        fabricatedClaims[0]["claimID"] = "fabricated-rating-and-roi"
        fabricated.acquisition["claims"] = fabricatedClaims
        XCTAssertFalse(try c26Validate(fabricated))

        var unsupportedAX = valid
        unsupportedAX.accessibility["appWideAccessibilityLabelAllowed"] = true
        XCTAssertFalse(try c26Validate(unsupportedAX))

        var arbitraryTag = valid
        var tagSuggestions = try XCTUnwrap(arbitraryTag.tags["observedSuggestions"] as? [String: Any])
        tagSuggestions["suggestions"] = ["UNOBSERVED_ARBITRARY_TAG"]
        arbitraryTag.tags["observedSuggestions"] = tagSuggestions
        XCTAssertFalse(try c26Validate(arbitraryTag))

        let hostileIDs = try XCTUnwrap(valid.fixture["hostileCases"] as? [[String: Any]])
            .compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(hostileIDs), [
            "APPROVAL_ABSENT", "ARBITRARY_APP_TAG", "DUPLICATE_SUBTITLE_KEYWORD",
            "EXPIRED_CLAIM", "FABRICATED_RATING", "LICENSED_ASSET",
            "MISLEADING_STRUCTURED_DATA", "MULTIBYTE_KEYWORD_OVERFLOW",
            "NEAR_DUPLICATE_SUPPORT_PAGE", "STALE_ACCEPTANCE_RECEIPT",
            "SUPERSEDED_CLAIM", "UNSUPPORTED_ACCESSIBILITY_LABEL",
        ])
    }

    func testV23P04C26I01ExpiryWithdrawalAndInterruptedDraftRecovery() throws {
        let valid = try c26Sources()
        let protocolReceipt = try XCTUnwrap(
            valid.evidence["generatorInterruptionProtocol"] as? [String: Any]
        )
        XCTAssertEqual(Set(protocolReceipt.keys), [
            "deterministicRerun", "protocol", "realWorktreeUnchanged", "rows",
            "temporaryRootIncompleteStatePermitted",
        ])
        XCTAssertEqual(protocolReceipt["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        XCTAssertEqual(protocolReceipt["deterministicRerun"] as? Bool, true)
        XCTAssertEqual(protocolReceipt["realWorktreeUnchanged"] as? Bool, true)
        XCTAssertEqual(protocolReceipt["temporaryRootIncompleteStatePermitted"] as? Bool, true)
        let protocolRows = try XCTUnwrap(protocolReceipt["rows"] as? [[String: Any]])
        XCTAssertEqual(protocolRows.count, 3)
        XCTAssertEqual(
            protocolRows.compactMap { row -> String? in
                guard let boundary = row["boundary"] as? String,
                      let count = row["acceptedSetCount"] as? Int,
                      row["manifestLast"] as? Bool == true,
                      let retryCount = row["retryAcceptedSetCount"] as? Int,
                      row["retryDeterministic"] as? Bool == true,
                      row["realWorktreeUnchanged"] as? Bool == true,
                      let incomplete = row["temporaryRootMayContainIncompleteArtifacts"] as? Bool
                else { return nil }
                return "\(boundary):\(count):\(retryCount):\(incomplete)"
            },
            [
                "BEFORE_ARTIFACTS:0:1:true",
                "AFTER_ARTIFACTS_BEFORE_MANIFEST:0:1:true",
                "AFTER_MANIFEST:1:1:false",
            ]
        )
        XCTAssertTrue(
            try text("Scripts/release-preflight.sh").contains(
                "generate_p04_c26_contracts.py --self-test --json"
            )
        )
        let claims = try XCTUnwrap(valid.acquisition["claims"] as? [[String: Any]])
        XCTAssertTrue(c26WithdrawnClaimIDs(claims, now: "2026-09-01T00:00:00Z").isEmpty)

        var expiredClaims = claims
        expiredClaims[0]["expiry"] = "2026-08-31T23:59:59Z"
        let expiredClaimID = try XCTUnwrap(expiredClaims[0]["claimID"] as? String)
        XCTAssertEqual(
            c26WithdrawnClaimIDs(expiredClaims, now: "2026-09-01T00:00:00Z"),
            [expiredClaimID]
        )

        var supersededClaims = claims
        supersededClaims[1]["supersededByClaimDigest"] = String(repeating: "a", count: 64)
        let supersededClaimID = try XCTUnwrap(supersededClaims[1]["claimID"] as? String)
        XCTAssertEqual(
            c26WithdrawnClaimIDs(supersededClaims, now: "2026-09-01T00:00:00Z"),
            [supersededClaimID]
        )

        var interrupted = valid
        interrupted.receipt["artifactBindings"] = Array(
            try XCTUnwrap(interrupted.receipt["artifactBindings"] as? [[String: Any]]).dropLast()
        )
        XCTAssertFalse(try c26Validate(interrupted), "partial receipt must never accept")
        XCTAssertTrue(try c26Validate(valid), "exact source set recovers without product/public writes")

        let publication = try XCTUnwrap(valid.fixture["publicationBoundary"] as? [String: Any])
        XCTAssertEqual(publication["networkRequests"] as? Int, 0)
        XCTAssertEqual(publication["providerConnections"] as? Int, 0)
        XCTAssertEqual(publication["uploads"] as? Int, 0)
        XCTAssertEqual(publication["dnsMutations"] as? Int, 0)
        XCTAssertEqual(publication["hostingWrites"] as? Int, 0)
        XCTAssertEqual(publication["submissions"] as? Int, 0)
        XCTAssertEqual(publication["finalCaptures"] as? Int, 0)
    }

    func testV23P04C26R01ReleasePreflightAndAccessibilityGateRemainPublicationIneligible() throws {
        let sources = try c26Sources()
        XCTAssertTrue(try c26Validate(sources))

        let script = try text("Scripts/release-preflight.sh")
        XCTAssertTrue(script.contains("verify_p04_c15_contracts.py --source-contracts"))
        XCTAssertTrue(script.contains("verify_p04_c26_contracts.py --complete --json"))
        for selector in c26Selectors {
            XCTAssertTrue(script.contains(selector))
        }

        let predecessor = try XCTUnwrap(
            sources.accessibility["c15AccessibilityEvidence"] as? [String: Any]
        )
        XCTAssertTrue(try c26BindingMatchesFile(predecessor))
        let gate = try XCTUnwrap(
            sources.accessibility["accessibilityLabelGate"] as? [String: Any]
        )
        XCTAssertEqual(gate["status"] as? String, "REQUIRED_BEFORE_ANY_LABEL")
        XCTAssertEqual(gate["allCommonTaskEvidenceRequired"] as? Bool, true)
        XCTAssertEqual(gate["allDeviceFamilyEvidenceRequired"] as? Bool, true)
        XCTAssertEqual(gate["physicalEvidenceComplete"] as? Bool, false)
        XCTAssertEqual(gate["appWideClaimAllowed"] as? Bool, false)

        let pages = try XCTUnwrap(sources.acquisition["supportPageSpecs"] as? [[String: Any]])
        let accessiblePages = try XCTUnwrap(
            sources.accessibility["supportPages"] as? [[String: Any]]
        )
        XCTAssertEqual(
            Set(pages.compactMap { $0["pageID"] as? String }),
            Set(accessiblePages.compactMap { $0["pageID"] as? String })
        )
        XCTAssertEqual(
            Set(pages.compactMap { $0["canonicalURLPath"] as? String }),
            Set(accessiblePages.compactMap { $0["canonicalURLPath"] as? String })
        )
    }

    private struct C26Sources {
        var acquisition: [String: Any]
        var tags: [String: Any]
        var receipt: [String: Any]
        var metadata: [String: Any]
        var accessibility: [String: Any]
        var fixture: [String: Any]
        var contract: [String: Any]
        var evidence: [String: Any]
    }

    private var c26Selectors: [String] {
        [
            "testV23P04C26G01BoundCatalogRefinementAndDisabledPublication",
            "testV23P04C26A01ApprovalAbsenceDefersAllPublication",
            "testV23P04C26H01HostileClaimsBindingsAndMetadataLimitsFailClosed",
            "testV23P04C26I01ExpiryWithdrawalAndInterruptedDraftRecovery",
            "testV23P04C26R01ReleasePreflightAndAccessibilityGateRemainPublicationIneligible",
        ]
    }

    private func c26Sources() throws -> C26Sources {
        C26Sources(
            acquisition: try jsonObject("docs/product/discovery/V23P04C26AcquisitionContentDraftV1.json"),
            tags: try jsonObject("docs/product/discovery/V23P04C26AppTagDispositionV1.json"),
            receipt: try jsonObject("docs/product/discovery/V23P04C26DiscoveryTruthCatalogRefinementReceiptV1.json"),
            metadata: try jsonObject("docs/product/discovery/V23P04C26MetadataEvidenceReportV1.json"),
            accessibility: try jsonObject("docs/accessibility/V23P04C26SupportContentAccessibilityManifestV1.json"),
            fixture: try jsonObject("FieldEvidenceAppTests/Fixtures/V21/DiscoveryTruth/V23P04C26OrganicFindabilityCorpusV1.json"),
            contract: try jsonObject("docs/design/v23/tooling/V23P04C26OrganicFindabilityContractV1.json"),
            evidence: try jsonObject("docs/design/v23/tooling/V23P04C26OrganicFindabilityEvidenceReceiptV1.json")
        )
    }

    private func c26Validate(_ sources: C26Sources) throws -> Bool {
        guard (sources.acquisition["schema"] as? String) == "V23P04C26AcquisitionContentDraftV1",
              (sources.tags["schema"] as? String) == "V23P04C26AppTagDispositionV1",
              (sources.receipt["schema"] as? String) == "V23P04C26DiscoveryTruthCatalogRefinementReceiptV1",
              (sources.metadata["schema"] as? String) == "V23P04C26MetadataEvidenceReportV1",
              (sources.accessibility["schema"] as? String) == "V23P04C26SupportContentAccessibilityManifestV1",
              (sources.fixture["schema"] as? String) == "V23P04C26OrganicFindabilityCorpusV1",
              (sources.contract["schema"] as? String) == "V23P04C26OrganicFindabilityContractV1",
              (sources.evidence["schema"] as? String) == "V23P04C26OrganicFindabilityEvidenceReceiptV1",
              c26ExactRootKeys(sources) else {
            return false
        }

        let forbiddenCapabilityKeys: Set<String> = [
            "analyticsProvider", "appStoreSubmission", "customerDataUse", "dnsHosting",
            "finalKeywords", "finalScreenshots", "networkAccess", "paidAcquisition",
            "publication", "upload",
        ]
        for root in [sources.acquisition, sources.tags, sources.receipt, sources.metadata] {
            guard root["schemaVersion"] as? Int == 1,
                  root["cardID"] as? String == "V23-P04-C26",
                  root["publishEligibility"] as? Bool == false,
                  let approval = root["approval"] as? [String: Any],
                  Set(approval.keys) == ["decisionReference", "sha256", "status"],
                  approval["decisionReference"] is NSNull,
                  approval["sha256"] is NSNull,
                  approval["status"] as? String == "DISABLED_OR_DEFERRED",
                  let catalog = root["catalogBinding"] as? [String: Any],
                  let brand = root["brandBinding"] as? [String: Any],
                  let privacy = root["privacyBinding"] as? [String: Any],
                  let synthetic = root["syntheticAssetBinding"] as? [String: Any],
                  let forbidden = root["forbiddenCapabilities"] as? [String: Any],
                  Set(forbidden.keys) == forbiddenCapabilityKeys,
                  forbidden.values.allSatisfy({ ($0 as? Bool) == false }),
                  try c26BindingMatchesFile(catalog),
                  try c26BindingMatchesFile(brand),
                  try c26BindingMatchesFile(privacy),
                  try c26BindingMatchesFile(synthetic) else { return false }
        }

        let limits: [String: Int] = [
            "nameMinimumCharacters": 2, "nameMaximumCharacters": 30,
            "subtitleMaximumCharacters": 30, "promotionalTextMaximumCharacters": 170,
            "descriptionMaximumCharacters": 4000, "keywordsMaximumCharacters": 100,
            "keywordsMaximumUTF8Bytes": 100, "screenshotsMinimumCount": 1,
            "screenshotsMaximumCount": 10, "previewsMaximumCount": 3,
            "ppoMaximumTreatments": 3,
        ]
        guard let actualLimits = sources.acquisition["metadataLimits"] as? [String: Any],
              limits.allSatisfy({ actualLimits[$0.key] as? Int == $0.value }),
              let locales = sources.acquisition["locales"] as? [[String: Any]],
              locales.count == 2 else { return false }
        for locale in locales {
            guard let name = locale["name"] as? String,
                  let subtitle = locale["subtitle"] as? String,
                  let promotional = locale["promotionalText"] as? String,
                  let description = locale["description"] as? String,
                  let keywords = locale["keywords"] as? String,
                  (2...30).contains(name.unicodeScalars.count), subtitle.unicodeScalars.count <= 30,
                  promotional.unicodeScalars.count <= 170,
                  description.unicodeScalars.count <= 4000,
                  keywords.unicodeScalars.count <= 100, keywords.utf8.count <= 100,
                  let screenshots = locale["screenshotCount"] as? Int,
                  (1...10).contains(screenshots),
                  let previews = locale["previewCount"] as? Int, previews <= 3,
                  locale["finalKeywords"] as? Bool == false,
                  locale["publishEligibility"] as? Bool == false,
                  c26MetadataTokens(name: name, subtitle: subtitle).isDisjoint(
                    with: c26MetadataTokens(name: "", subtitle: keywords)
                  ) else { return false }
        }

        guard let control = sources.acquisition["control"] as? [String: Any],
              control["hypothesisID"] as? String == "CONTROL",
              control["finalScreenshot"] as? Bool == false,
              control["uploadReady"] as? Bool == false,
              let hypotheses = sources.acquisition["ppoHypotheses"] as? [[String: Any]],
              hypotheses.count <= 3,
              Set(hypotheses.compactMap { $0["hypothesisID"] as? String }).count == hypotheses.count,
              hypotheses.allSatisfy({ ($0["finalScreenshot"] as? Bool) == false && ($0["uploadReady"] as? Bool) == false }),
              let pages = sources.acquisition["supportPageSpecs"] as? [[String: Any]],
              pages.count == 6,
              pages.allSatisfy({
                  ($0["sourceIsSyntheticOnly"] as? Bool) == true
                      && ($0["status"] as? String) == "DISABLED_OR_DEFERRED"
                      && (($0["semanticHTML"] as? [String])?.contains("h1") == true)
                      && (($0["semanticHTML"] as? [String])?.contains("article") == true)
                      && (($0["structuredDataVisibleFields"] as? [String]) == ["headline", "description", "limitations"])
                      && !(($0["limitations"] as? [String]) ?? []).isEmpty
              }),
              try c26PageSemanticsValid(pages, metadata: sources.metadata) else { return false }

        let expectedClaims = Set(pages.compactMap { $0["claimID"] as? String })
        let pageByClaim = Dictionary(
            uniqueKeysWithValues: pages.compactMap { page -> (String, [String: Any])? in
                guard let claimID = page["claimID"] as? String else { return nil }
                return (claimID, page)
            }
        )
        let authorityRows = try XCTUnwrap(
            sources.evidence["claimAuthorityProjection"] as? [[String: Any]]
        )
        let authorityByCard = Dictionary(
            uniqueKeysWithValues: authorityRows.compactMap { row -> (String, [String: Any])? in
                guard let cardID = row["cardID"] as? String else { return nil }
                return (cardID, row)
            }
        )
        guard let claims = sources.acquisition["claims"] as? [[String: Any]],
              claims.count == 6,
              pageByClaim.count == pages.count,
              authorityRows.count == 6,
              authorityByCard.count == 6,
              Set(claims.compactMap { $0["claimID"] as? String }) == expectedClaims,
              Set(claims.compactMap { $0["acceptedFeatureCard"] as? String })
                == Set(authorityByCard.keys),
              try claims.allSatisfy({ claim in
                  guard claim["status"] as? String == "DISABLED_OR_DEFERRED",
                        claim["publishEligibility"] as? Bool == false,
                        c26SHA(claim["receiptSHA256"] as? String),
                        let binding = claim["acceptanceBinding"] as? [String: Any] else { return false }
                  guard binding["currentness"] as? String == "CHECKPOINTED_CURRENT",
                        binding["compatibilityDisposition"] as? String == "CURRENT_NOT_SUPERSEDED",
                        binding["recoveryProof"] as? String == "MATCHING_PROVISIONAL_VERIFICATION_RECEIPT",
                        c26SHA(binding["checkpointSHA256"] as? String),
                        c26SHA(binding["verificationSHA256"] as? String),
                        claim["expiry"] is NSNull,
                        claim["supersededByClaimDigest"] is NSNull else { return false }
                  guard let claimID = claim["claimID"] as? String,
                        let page = pageByClaim[claimID],
                        let cardID = claim["acceptedFeatureCard"] as? String,
                        page["acceptedFeatureCardID"] as? String == cardID,
                        let authority = authorityByCard[cardID] else { return false }
                  return try c26ClaimEvidenceMatches(claim, authority: authority)
              }) else { return false }

        guard let measurements = sources.metadata["localeMeasurements"] as? [[String: Any]],
              measurements.count == locales.count,
              zip(locales, measurements).allSatisfy({ locale, measurement in
                  guard locale["locale"] as? String == measurement["locale"] as? String,
                        let name = locale["name"] as? String,
                        let subtitle = locale["subtitle"] as? String,
                        let promotional = locale["promotionalText"] as? String,
                        let description = locale["description"] as? String,
                        let keywords = locale["keywords"] as? String else { return false }
                  return measurement["nameCharacters"] as? Int == name.unicodeScalars.count
                      && measurement["subtitleCharacters"] as? Int == subtitle.unicodeScalars.count
                      && measurement["promotionalTextCharacters"] as? Int == promotional.unicodeScalars.count
                      && measurement["descriptionCharacters"] as? Int == description.unicodeScalars.count
                      && measurement["keywordsCharacters"] as? Int == keywords.unicodeScalars.count
                      && measurement["keywordsUTF8Bytes"] as? Int == keywords.utf8.count
                      && measurement["screenshotCount"] as? Int == locale["screenshotCount"] as? Int
                      && measurement["previewCount"] as? Int == locale["previewCount"] as? Int
                      && measurement["keywordsDuplicateNameOrSubtitleTokens"] as? Bool == false
                      && measurement["withinLimits"] as? Bool == true
              }),
              let artifactBindings = sources.receipt["artifactBindings"] as? [[String: Any]],
              artifactBindings.count == 3,
              Set(artifactBindings.compactMap { $0["kind"] as? String }) == [
                "ACQUISITION_CONTENT_DRAFT", "APP_TAG_DISPOSITION", "METADATA_EVIDENCE_REPORT",
              ],
              try artifactBindings.allSatisfy({ try c26BindingMatchesFile($0) }),
              let suggestions = sources.tags["observedSuggestions"] as? [String: Any],
              (suggestions["suggestions"] as? [String])?.isEmpty == true,
              suggestions["displayGuaranteed"] as? Bool == false,
              let structured = sources.metadata["structuredData"] as? [String: Any],
              structured["contentOriginalityReview"] as? String == "PASS_SYNTHETIC_ORIGINAL_DRAFT_ONLY",
              structured["customerDataDetected"] as? Bool == false,
              structured["doorwayOrNearDuplicatePagesDetected"] as? Bool == false,
              structured["licensedThirdPartyContentDetected"] as? Bool == false,
              structured["visibleContentEqualityRequired"] as? Bool == true,
              structured["visibleContentEqualityVerified"] as? Bool == true else { return false }

        guard sources.accessibility["publicationEligible"] as? Bool == false,
              sources.accessibility["syntheticOnly"] as? Bool == true,
              sources.accessibility["containsRealCustomerData"] as? Bool == false,
              sources.accessibility["containsLicensedAssets"] as? Bool == false,
              sources.accessibility["appWideAccessibilityLabelAllowed"] as? Bool == false,
              sources.accessibility["networkAccess"] as? Bool == false,
              sources.accessibility["dnsOrHosting"] as? Bool == false,
              sources.accessibility["appStoreSubmission"] as? Bool == false,
              sources.accessibility["finalCapture"] as? Bool == false,
              let accessiblePages = sources.accessibility["supportPages"] as? [[String: Any]],
              Set(accessiblePages.compactMap({ $0["pageID"] as? String })) == Set(pages.compactMap({ $0["pageID"] as? String })),
              Set(accessiblePages.compactMap({ $0["canonicalURLPath"] as? String })) == Set(pages.compactMap({ $0["canonicalURLPath"] as? String })) else {
            return false
        }
        guard let accessibilityFlags = sources.accessibility["statusFlags"] as? [String: Any],
              accessibilityFlags.values.allSatisfy({ ($0 as? Bool) == false }),
              let draftShape = sources.fixture["draftShape"] as? [String: Any],
              draftShape["publicationEligible"] as? Bool == false,
              draftShape["networkAccess"] as? Bool == false,
              draftShape["dnsOrHosting"] as? Bool == false,
              draftShape["appStoreSubmission"] as? Bool == false,
              draftShape["finalCapture"] as? Bool == false,
              let publicationBoundary = sources.fixture["publicationBoundary"] as? [String: Any],
              publicationBoundary["publicationEligible"] as? Bool == false,
              publicationBoundary.values.allSatisfy({ value in
                  guard let count = value as? Int else { return true }
                  return count == 0
              }),
              let contractFlags = sources.contract["statusFlags"] as? [String: Any],
              Set(contractFlags.keys) == [
                  "acceptance", "adoption", "analyticsProvider", "appStoreSubmission",
                  "customerDataUse", "dnsHosting", "finalKeywords", "finalScreenshots",
                  "hosted", "native", "networkAccess", "paidAcquisition", "publication",
                  "release", "upload",
              ],
              contractFlags.values.allSatisfy({ ($0 as? Bool) == false }) else { return false }
        return true
    }

    private func c26ExactRootKeys(_ sources: C26Sources) -> Bool {
        let roots: [([String: Any], Set<String>)] = [
            (sources.acquisition, [
                "approval", "brandBinding", "cardID", "catalogBinding", "claims",
                "control", "evidenceBindings", "forbiddenCapabilities", "locales",
                "metadataLimits", "ppoHypotheses", "privacyBinding", "publishEligibility",
                "schema", "schemaVersion", "supportPageSpecs", "syntheticAssetBinding",
            ]),
            (sources.tags, [
                "approval", "brandBinding", "cardID", "catalogBinding",
                "forbiddenCapabilities", "locales", "metadataLimits", "observedSuggestions",
                "privacyBinding", "publishEligibility", "schema", "schemaVersion",
                "syntheticAssetBinding",
            ]),
            (sources.receipt, [
                "approval", "artifactBindings", "brandBinding", "cardID", "catalogBinding",
                "catalogRefinement", "forbiddenCapabilities", "locales", "metadataLimits",
                "privacyBinding", "publishEligibility", "schema", "schemaVersion",
                "syntheticAssetBinding",
            ]),
            (sources.metadata, [
                "approval", "brandBinding", "cardID", "catalogBinding",
                "forbiddenCapabilities", "limits", "localeMeasurements", "locales",
                "metadataLimits", "officialSource", "privacyBinding", "publishEligibility",
                "schema", "schemaVersion", "structuredData", "syntheticAssetBinding",
            ]),
            (sources.accessibility, [
                "accessibilityLabelGate", "appStoreSubmission",
                "appWideAccessibilityLabelAllowed", "authority", "c15AccessibilityEvidence",
                "cardID", "containsLicensedAssets", "containsRealCustomerData", "dnsOrHosting",
                "finalCapture", "networkAccess", "ordinal", "provisional",
                "publicationEligible", "publish", "requiredEvidence", "schema",
                "schemaVersion", "staticOnly", "statusFlags", "supportPages",
                "syntheticOnly", "upload",
            ]),
            (sources.fixture, [
                "authority", "cardID", "containsCustomerData", "containsLicensedAssets",
                "draftShape", "hostileCases", "metadataLimits", "ordinal",
                "publicationBoundary", "schema", "schemaVersion", "selectors", "synthetic",
                "syntheticAssetScan", "testOnly",
            ]),
            (sources.contract, [
                "authority", "cardID", "provisional", "schema", "schemaVersion", "semantics",
                "sourceProjection", "statusFlags", "testSelectors",
            ]),
            (sources.evidence, [
                "authority", "cardID", "claimAuthorityProjection", "contractDigest",
                "generatorInterruptionProtocol", "provisional", "schema", "schemaVersion",
                "sourceProjection", "statusFlags",
            ]),
        ]
        return roots.allSatisfy { Set($0.0.keys) == $0.1 }
    }

    private func c26PageSemanticsValid(
        _ pages: [[String: Any]], metadata: [String: Any]
    ) throws -> Bool {
        let expectedTuples: Set<String> = [
            "ACCESSIBILITY_SUPPORT|/support/accessibility-and-support|c26-accessibility-support-v1|V23-P04-C16",
            "DAY_NIGHT_EVIDENCE|/support/day-night-evidence|c26-day-night-evidence-v1|V23-P04-C18",
            "LIGHTING_WORKFLOW_LIMITS|/support/lighting-workflow-limits|c26-lighting-workflow-limits-v1|V23-P04-C17",
            "OFFLINE_PLAN_REBASE|/support/offline-plan-rebase|c26-offline-plan-rebase-v1|V23-P04-C19",
            "QR_BARCODE_ROUNDS|/support/qr-barcode-rounds|c26-qr-barcode-rounds-v1|V23-P04-C21",
            "SURVEY_VERSUS_INSPECTION|/support/survey-versus-inspection|c26-survey-versus-inspection-v1|V23-P04-C20",
        ]
        let actualTuples = Set(pages.compactMap { page -> String? in
            guard let pageID = page["pageID"] as? String,
                  let path = page["canonicalURLPath"] as? String,
                  let claimID = page["claimID"] as? String,
                  let cardID = page["acceptedFeatureCardID"] as? String else { return nil }
            return "\(pageID)|\(path)|\(claimID)|\(cardID)"
        })
        guard actualTuples == expectedTuples else { return false }

        var contentDigests: [String: String] = [:]
        var tokenSets: [String: Set<String>] = [:]
        for page in pages {
            guard let pageID = page["pageID"] as? String,
                  let title = page["title"] as? String,
                  let summary = page["summary"] as? String,
                  let limitations = page["limitations"] as? [String] else { return false }
            let visible: [String: Any] = [
                "headline": title,
                "description": summary,
                "limitations": limitations,
            ]
            let digest = try c26CanonicalDigest(visible)
            guard page["visibleContentSHA256"] as? String == digest,
                  page["structuredDataSHA256"] as? String == digest else { return false }
            contentDigests[pageID] = digest
            tokenSets[pageID] = c26OriginalityTokens(
                ([title, summary] + limitations).joined(separator: " ")
            )
        }

        for page in pages {
            guard let pageID = page["pageID"] as? String,
                  let ownTokens = tokenSets[pageID],
                  let compared = page["comparedPageContentSHA256s"] as? [String],
                  compared == contentDigests.filter({ $0.key != pageID }).map(\.value).sorted(),
                  let recordedMaximum = page["maximumPairwiseTokenOverlapBasisPoints"] as? Int,
                  let threshold = page["nearDuplicateThresholdBasisPoints"] as? Int,
                  threshold == 8000 else { return false }
            let overlaps = tokenSets.compactMap { otherID, otherTokens -> Int? in
                guard otherID != pageID else { return nil }
                let unionCount = ownTokens.union(otherTokens).count
                guard unionCount > 0 else { return 10_000 }
                return ownTokens.intersection(otherTokens).count * 10_000 / unionCount
            }
            guard recordedMaximum == overlaps.max(), recordedMaximum < threshold,
                  let visibleDigest = contentDigests[pageID] else { return false }
            let originalityPayload: [String: Any] = [
                "pageID": pageID,
                "visibleContentSHA256": visibleDigest,
                "comparedPageContentSHA256s": compared,
                "maximumPairwiseTokenOverlapBasisPoints": recordedMaximum,
                "nearDuplicateThresholdBasisPoints": threshold,
            ]
            guard page["originalityComparisonSHA256"] as? String
                    == (try c26CanonicalDigest(originalityPayload)) else { return false }
        }

        guard let structured = metadata["structuredData"] as? [String: Any],
              structured["pairwiseComparisonCount"] as? Int == 15,
              structured["customerDataDetected"] as? Bool == false,
              structured["licensedThirdPartyContentDetected"] as? Bool == false,
              let bindings = structured["pageBindings"] as? [[String: Any]],
              bindings.count == pages.count else { return false }
        let bindingsByID = Dictionary(
            uniqueKeysWithValues: bindings.compactMap { binding -> (String, [String: Any])? in
                guard let pageID = binding["pageID"] as? String else { return nil }
                return (pageID, binding)
            }
        )
        guard bindingsByID.count == pages.count else { return false }
        for page in pages {
            guard let pageID = page["pageID"] as? String,
                  let binding = bindingsByID[pageID],
                  binding["acceptedFeatureCardID"] as? String == page["acceptedFeatureCardID"] as? String,
                  binding["canonicalURLPath"] as? String == page["canonicalURLPath"] as? String,
                  binding["claimID"] as? String == page["claimID"] as? String,
                  binding["visibleContentSHA256"] as? String == page["visibleContentSHA256"] as? String,
                  binding["structuredDataSHA256"] as? String == page["structuredDataSHA256"] as? String,
                  binding["originalityComparisonSHA256"] as? String == page["originalityComparisonSHA256"] as? String,
                  binding["comparedPageContentSHA256s"] as? [String] == page["comparedPageContentSHA256s"] as? [String],
                  binding["maximumPairwiseTokenOverlapBasisPoints"] as? Int == page["maximumPairwiseTokenOverlapBasisPoints"] as? Int,
                  binding["nearDuplicateThresholdBasisPoints"] as? Int == page["nearDuplicateThresholdBasisPoints"] as? Int else {
                return false
            }
        }
        return true
    }

    private func c26CanonicalDigest(_ value: [String: Any]) throws -> String {
        var bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        bytes.append(0x0A)
        return c26Digest(bytes)
    }

    private func c26RecomputePageEvidence(
        _ pages: inout [[String: Any]], metadata: inout [String: Any]
    ) throws {
        var contentDigests: [String: String] = [:]
        var tokenSets: [String: Set<String>] = [:]
        for index in pages.indices {
            let pageID = try XCTUnwrap(pages[index]["pageID"] as? String)
            let title = try XCTUnwrap(pages[index]["title"] as? String)
            let summary = try XCTUnwrap(pages[index]["summary"] as? String)
            let limitations = try XCTUnwrap(pages[index]["limitations"] as? [String])
            let digest = try c26CanonicalDigest([
                "headline": title, "description": summary, "limitations": limitations,
            ])
            pages[index]["visibleContentSHA256"] = digest
            pages[index]["structuredDataSHA256"] = digest
            contentDigests[pageID] = digest
            tokenSets[pageID] = c26OriginalityTokens(
                ([title, summary] + limitations).joined(separator: " ")
            )
        }
        for index in pages.indices {
            let pageID = try XCTUnwrap(pages[index]["pageID"] as? String)
            let own = try XCTUnwrap(tokenSets[pageID])
            let compared = contentDigests
                .filter { $0.key != pageID }
                .map(\.value)
                .sorted()
            let maximum = tokenSets
                .filter { $0.key != pageID }
                .map { other -> Int in
                    let union = own.union(other.value)
                    return union.isEmpty ? 0 : own.intersection(other.value).count * 10_000 / union.count
                }
                .max() ?? 0
            pages[index]["comparedPageContentSHA256s"] = compared
            pages[index]["maximumPairwiseTokenOverlapBasisPoints"] = maximum
            pages[index]["nearDuplicateThresholdBasisPoints"] = 8_000
            pages[index]["originalityComparisonSHA256"] = try c26CanonicalDigest([
                "pageID": pageID,
                "visibleContentSHA256": try XCTUnwrap(contentDigests[pageID]),
                "comparedPageContentSHA256s": compared,
                "maximumPairwiseTokenOverlapBasisPoints": maximum,
                "nearDuplicateThresholdBasisPoints": 8_000,
            ])
        }
        var structured = try XCTUnwrap(metadata["structuredData"] as? [String: Any])
        var bindings = try XCTUnwrap(structured["pageBindings"] as? [[String: Any]])
        let pagesByID = Dictionary(
            uniqueKeysWithValues: pages.compactMap { page -> (String, [String: Any])? in
                guard let pageID = page["pageID"] as? String else { return nil }
                return (pageID, page)
            }
        )
        for index in bindings.indices {
            let pageID = try XCTUnwrap(bindings[index]["pageID"] as? String)
            let page = try XCTUnwrap(pagesByID[pageID])
            for key in [
                "visibleContentSHA256", "structuredDataSHA256",
                "originalityComparisonSHA256", "comparedPageContentSHA256s",
                "maximumPairwiseTokenOverlapBasisPoints", "nearDuplicateThresholdBasisPoints",
            ] {
                bindings[index][key] = page[key]
            }
        }
        structured["pageBindings"] = bindings
        metadata["structuredData"] = structured
    }

    private func c26OriginalityTokens(_ value: String) -> Set<String> {
        let normalized = value.precomposedStringWithCompatibilityMapping.lowercased()
        return Set(normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private func c26BindingMatchesFile(_ binding: [String: Any]) throws -> Bool {
        guard Set(binding.keys).isSuperset(of: ["path", "sha256"]),
              let path = binding["path"] as? String,
              let expected = binding["sha256"] as? String,
              c26SHA(expected), !path.hasPrefix("/"), !path.contains("..") else { return false }
        return c26Digest(try data(path)) == expected
    }

    private func c26ClaimEvidenceMatches(
        _ claim: [String: Any], authority: [String: Any]
    ) throws -> Bool {
        guard let cardID = claim["acceptedFeatureCard"] as? String,
              let receiptDigest = claim["receiptSHA256"] as? String,
              let binding = claim["acceptanceBinding"] as? [String: Any],
              let head = binding["acceptedCandidateHead"] as? String,
              let tree = binding["acceptedCandidateTree"] as? String,
              let checkpointDigest = binding["checkpointDigest"] as? String,
              let checkpointPath = binding["checkpointPath"] as? String,
              let checkpointSHA = binding["checkpointSHA256"] as? String,
              let verificationPath = binding["verificationPath"] as? String,
              let verificationSHA = binding["verificationSHA256"] as? String,
              checkpointPath == "receipts/\(cardID)-provisional-checkpoint.json",
              verificationPath == "receipts/\(cardID)-provisional-verification.json",
              Set(authority.keys) == [
                  "acceptedHead", "acceptedTree", "cardID", "checkpointDigest",
                  "checkpointPath", "checkpointSHA256", "compatibilityDisposition",
                  "currentness", "receiptDigest", "recoveryProof", "verificationPath",
                  "verificationSHA256", "claimID",
              ],
              authority["claimID"] as? String == claim["claimID"] as? String,
              authority["cardID"] as? String == cardID,
              authority["acceptedHead"] as? String == head,
              authority["acceptedTree"] as? String == tree,
              authority["checkpointDigest"] as? String == checkpointDigest,
              authority["checkpointPath"] as? String == checkpointPath,
              authority["checkpointSHA256"] as? String == checkpointSHA,
              authority["verificationPath"] as? String == verificationPath,
              authority["verificationSHA256"] as? String == verificationSHA,
              authority["receiptDigest"] as? String == receiptDigest,
              authority["currentness"] as? String == binding["currentness"] as? String,
              authority["compatibilityDisposition"] as? String
                == binding["compatibilityDisposition"] as? String,
              authority["recoveryProof"] as? String == binding["recoveryProof"] as? String
        else { return false }

        guard let checkpointURL = c26EvidenceURL(checkpointPath),
              let verificationURL = c26EvidenceURL(verificationPath) else {
            // Hosted macOS checkouts intentionally carry the manifest-bound projection,
            // not the Windows coordination checkout used to generate it.
            return true
        }
        let checkpointBytes = try Data(contentsOf: checkpointURL)
        let verificationBytes = try Data(contentsOf: verificationURL)
        let verificationSchemas = [
            "V23-P04-C16": "ProvisionalP04C16StaticVerificationReceiptV1",
            "V23-P04-C17": "ProvisionalP04C17StaticVerificationReceiptV1",
            "V23-P04-C18": "ProvisionalP04C18StaticVerificationReceiptV1",
            "V23-P04-C19": "ProvisionalVerificationReceiptV1",
            "V23-P04-C20": "ProvisionalVerificationReceiptV1",
            "V23-P04-C21": "ProvisionalVerificationReceiptV1",
        ]
        guard c26Digest(checkpointBytes) == checkpointSHA,
              c26Digest(verificationBytes) == verificationSHA,
              let checkpoint = try JSONSerialization.jsonObject(with: checkpointBytes) as? [String: Any],
              let verification = try JSONSerialization.jsonObject(with: verificationBytes) as? [String: Any],
              checkpoint["schema"] as? String == "ProvisionalCardCheckpointReceiptV1",
              verification["schema"] as? String == verificationSchemas[cardID],
              checkpoint["cardID"] as? String == cardID,
              verification["cardID"] as? String == cardID,
              checkpoint["acceptedCandidateHead"] as? String == head,
              verification["acceptedCandidateHead"] as? String == head,
              checkpoint["acceptedCandidateTree"] as? String == tree,
              verification["acceptedCandidateTree"] as? String == tree,
              checkpoint["checkpointDigest"] as? String == checkpointDigest,
              checkpoint["verificationReceiptDigest"] as? String == receiptDigest,
              verification["receiptDigest"] as? String == receiptDigest,
              checkpoint["canonicalState"] as? String == "CHECKPOINTED",
              c26CheckpointProfileValid(checkpoint, cardID: cardID),
              verification["finalHashesSealed"] as? Bool == true,
              verification["flagsAllFalse"] as? Bool == true,
              verification["sourceReady"] as? Bool == true,
              verification["releaseReady"] as? Bool == false,
              verification["acceptanceEnabled"] as? Bool == false,
              verification["adoptionEnabled"] as? Bool == false else { return false }
        switch cardID {
        case "V23-P04-C16", "V23-P04-C17", "V23-P04-C18":
            return verification["complete"] as? Bool == true
                && verification["completeVerifierResult"] as? String == "PASS_STATIC_PROVISIONAL"
                && verification["result"] as? String == "PASS_STATIC_PROVISIONAL"
        case "V23-P04-C19", "V23-P04-C20":
            return verification["verificationStatus"] as? String == "PASS_STATIC_PROVISIONAL"
        case "V23-P04-C21":
            return verification["toolingVerifierStatus"] as? String == "PASS_STATIC_PROVISIONAL"
        default:
            return false
        }
    }

    private func c26CheckpointProfileValid(
        _ checkpoint: [String: Any], cardID: String
    ) -> Bool {
        guard checkpoint["schema"] as? String == "ProvisionalCardCheckpointReceiptV1",
              checkpoint["cardID"] as? String == cardID,
              checkpoint["canonicalState"] as? String == "CHECKPOINTED",
              checkpoint["flagsAllFalse"] as? Bool == true else { return false }
        switch cardID {
        case "V23-P04-C16", "V23-P04-C17", "V23-P04-C18", "V23-P04-C19":
            return checkpoint["finalHashesSealed"] as? Bool == true
        case "V23-P04-C20", "V23-P04-C21":
            return checkpoint["finalHashesSealed"] == nil
        default:
            return false
        }
    }

    private func c26EvidenceURL(_ relativePath: String) -> URL? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !relativePath.hasPrefix("/"), !components.contains("..") else { return nil }
        let repositoryCandidate = repositoryRoot.appendingPathComponent(relativePath)
        let coordinationCandidate = repositoryRoot
            .deletingLastPathComponent()
            .appendingPathComponent("AssetRounds-v23-coordination")
            .appendingPathComponent(relativePath)
        let matches = [repositoryCandidate, coordinationCandidate].filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func c26MetadataTokens(name: String, subtitle: String) -> Set<String> {
        Set((name + " " + subtitle).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private func c26WithdrawnClaimIDs(
        _ claims: [[String: Any]], now: String
    ) -> [String] {
        claims.compactMap { claim in
            let expired = (claim["expiry"] as? String).map { $0 <= now } ?? false
            let superseded = claim["supersededByClaimDigest"] is String
            return expired || superseded ? claim["claimID"] as? String : nil
        }.sorted()
    }

    private func c26Digest(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    private func c26SHA(_ value: String?) -> Bool {
        guard let value, value.count == 64 else { return false }
        return value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }
}

extension S9_1ReleasePreflightTests {
    func testV23P03C42ReleasePreflightCoversEveryTypedExclusionSurface() throws {
        let observations = try ReleaseExclusionSurfaceV1.allCases.map(c42Observation)
        let receipt = try ReleaseExclusionReceiptV1(
            observations: observations,
            hostileFixtureCount: 28,
            generatedScratchRemoved: true
        )

        try receipt.validate()
        XCTAssertEqual(receipt.releaseConfiguration, "Release")
        XCTAssertEqual(receipt.testSupportPaths, ReleaseExclusionReceiptV1.requiredTestSupportPaths)
        XCTAssertTrue(receipt.testSupportPaths.allSatisfy { $0.contains("TestSupport") })
        XCTAssertEqual(receipt.forbiddenReleaseSymbols, ReleaseExclusionReceiptV1.forbiddenReleaseSymbols)
        XCTAssertEqual(
            receipt.observations.map(\.surface),
            ReleaseExclusionSurfaceV1.allCases.sorted { $0.rawValue < $1.rawValue }
        )
        XCTAssertTrue(receipt.observations.allSatisfy { $0.forbiddenMatches.isEmpty })
        XCTAssertEqual(Set(receipt.observations.map(\.surface)).count, ReleaseExclusionSurfaceV1.allCases.count)
        XCTAssertFalse(receipt.isComplete)
        XCTAssertFalse(receipt.certifiesReleaseExclusion)

        let source = try XCTUnwrap(
            receipt.observations.first { $0.surface == .sourceMembership }
        )
        XCTAssertEqual(source.disposition, .provenAbsent)
        XCTAssertTrue(source.certifiesAbsence)
        XCTAssertGreaterThan(source.inspectedByteCount ?? 0, 0)
        XCTAssertNotEqual(source.inspectedSHA256, String(repeating: "a", count: 64))

        let runtime = try XCTUnwrap(
            receipt.observations.first { $0.surface == .runtimeSurface }
        )
        XCTAssertEqual(runtime.disposition, .staticPendingNative)
        XCTAssertFalse(runtime.certifiesAbsence)
        XCTAssertNil(runtime.artifactIdentity)
        XCTAssertNil(runtime.inspectedByteCount)
        XCTAssertNil(runtime.inspectedSHA256)
        XCTAssertNil(runtime.releaseArtifactProvenance)

        let encoded = try CrossMarketCanonicalV1.data(receipt)
        let decoded = try CrossMarketCanonicalV1.decode(
            ReleaseExclusionReceiptV1.self,
            from: encoded
        )
        XCTAssertEqual(decoded, receipt)
        XCTAssertEqual(try CrossMarketCanonicalV1.data(decoded), encoded)
    }

    func testV23P03C42ReleaseReceiptRejectsFabricatedAndSubstitutedEvidence() throws {
        let observations = try ReleaseExclusionSurfaceV1.allCases.map(c42Observation)
        let receipt = try ReleaseExclusionReceiptV1(
            observations: observations,
            hostileFixtureCount: 28,
            generatedScratchRemoved: true
        )
        let encoded = try CrossMarketCanonicalV1.data(receipt)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        var fabricatedRoot = root
        var fabricatedObservations = try XCTUnwrap(
            fabricatedRoot["observations"] as? [[String: Any]]
        )
        let provenIndex = try XCTUnwrap(
            fabricatedObservations.firstIndex {
                $0["disposition"] as? String == "PROVEN_ABSENT"
            }
        )
        fabricatedObservations[provenIndex]["inspectedSHA256"] = String(
            repeating: "a",
            count: 64
        )
        fabricatedRoot["observations"] = fabricatedObservations
        let fabricatedBytes = try JSONSerialization.data(withJSONObject: fabricatedRoot)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ReleaseExclusionReceiptV1.self, from: fabricatedBytes)
        )

        for (surface, substitutedSource) in [
            ("RUNTIME_SURFACE", "RELEASE_EXECUTABLE_STRING_TABLE"),
            ("SCREENSHOTS", "REPOSITORY_PROJECT_FILE"),
            ("APP_STORE_DRAFTS", "RELEASE_EXECUTABLE_SYMBOL_TABLE"),
        ] {
            var substitutedRoot = root
            var substitutedObservations = try XCTUnwrap(
                substitutedRoot["observations"] as? [[String: Any]]
            )
            let index = try XCTUnwrap(
                substitutedObservations.firstIndex { $0["surface"] as? String == surface }
            )
            substitutedObservations[index]["sourceIdentity"] = substitutedSource
            substitutedRoot["observations"] = substitutedObservations
            let substitutedBytes = try JSONSerialization.data(withJSONObject: substitutedRoot)
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ReleaseExclusionReceiptV1.self,
                    from: substitutedBytes
                )
            )
        }

        let projectBytes = try data("FieldEvidenceApp.xcodeproj/project.pbxproj")
        XCTAssertThrowsError(
            try ReleaseExclusionObservationV1(
                surface: .runtimeSurface,
                sourceIdentity: .releaseRuntimeEnumeration,
                repositoryRelativeInputs: ["FieldEvidenceApp.xcodeproj/project.pbxproj"],
                artifactIdentity: "SOURCE_SCAN_MASQUERADING_AS_RUNTIME",
                evidenceBytes: projectBytes,
                forbiddenMatches: []
            )
        )
        XCTAssertThrowsError(
            try ReleaseExclusionObservationV1.staticPendingNative(
                surface: .sourceMembership,
                repositoryRelativeInputs: ["FieldEvidenceApp.xcodeproj/project.pbxproj"]
            )
        )
        XCTAssertThrowsError(
            try ReleaseExclusionReceiptV1(
                observations: Array(observations.dropLast()),
                hostileFixtureCount: 28,
                generatedScratchRemoved: true
            )
        )
        XCTAssertThrowsError(
            try ReleaseExclusionReceiptV1(
                observations: observations + [observations[0]],
                hostileFixtureCount: 28,
                generatedScratchRemoved: true
            )
        )
        XCTAssertThrowsError(
            try ReleaseExclusionObservationV1.staticPendingNative(
                surface: .runtimeSurface,
                repositoryRelativeInputs: ["../FieldEvidenceApp.xcodeproj/project.pbxproj"]
            )
        )
    }

    private func c42Observation(
        for surface: ReleaseExclusionSurfaceV1
    ) throws -> ReleaseExclusionObservationV1 {
        let inputs = c42RepositoryInputs(for: surface)
        if surface.requiresNativeOrExternalEvidence {
            return try .staticPendingNative(
                surface: surface,
                repositoryRelativeInputs: inputs
            )
        }

        let evidence = try c42EvidenceBytes(inputs)
        let text = String(decoding: evidence, as: UTF8.self)
        return try ReleaseExclusionObservationV1(
            surface: surface,
            sourceIdentity: surface.requiredSourceIdentity,
            repositoryRelativeInputs: inputs,
            artifactIdentity: inputs.joined(separator: "+"),
            evidenceBytes: evidence,
            forbiddenMatches: ReleaseExclusionReceiptV1.forbiddenReleaseSymbols.filter {
                text.contains($0)
            }
        )
    }

    private func c42RepositoryInputs(
        for surface: ReleaseExclusionSurfaceV1
    ) -> [String] {
        switch surface {
        case .sourceMembership, .targetDependencyGraph, .compiledArchive,
             .bundleResources, .publicSymbols, .publicStrings, .screenshots,
             .runtimeSurface:
            return ["FieldEvidenceApp.xcodeproj/project.pbxproj"]
        case .localizationCatalog:
            return ["FieldEvidenceApp/Resources/Localizable.xcstrings"]
        case .packageRegistry:
            return [
                "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
                "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
            ]
        case .routeRegistry:
            return ["FieldEvidenceApp/Features/Shell/AppShellView.swift"]
        case .settingsRegistry:
            return ["FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift"]
        case .appStoreDrafts:
            return ["Release/UnsignedRCMetadataV1.json"]
        }
    }

    private func c42EvidenceBytes(_ relativePaths: [String]) throws -> Data {
        var result = Data()
        for path in relativePaths.sorted() {
            let bytes = try data(path)
            result.append(Data("\(path.utf8.count):\(path):\(bytes.count):".utf8))
            result.append(bytes)
            result.append(0x0A)
        }
        return result
    }
}
