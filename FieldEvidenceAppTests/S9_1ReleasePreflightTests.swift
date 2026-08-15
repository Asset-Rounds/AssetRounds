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
