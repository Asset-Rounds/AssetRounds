import Foundation
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
