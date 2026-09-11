import Foundation
import XCTest

final class S10_1BrandInventoryTests: XCTestCase {
    private let accessibilityFeatures: Set<String> = [
        "voiceover",
        "voice_control",
        "larger_text",
        "dark_interface",
        "differentiate_without_color",
        "sufficient_contrast",
        "reduced_motion",
    ]

    private let visualRequirements: Set<String> = [
        "default_light",
        "default_dark",
        "increased_contrast",
        "ax_text",
        "double_length",
        "rtl",
        "rtl_string",
        "tall",
        "accented",
        "bounded",
        "differentiate_without_color",
        "reduce_motion",
        "reduce_transparency",
        "minimum_os",
    ]

    private let routeIDs: Set<String> = [
        "route.shell.maintenance",
        "route.pack.unavailable",
        "route.signs.welcome",
        "route.reports.index",
        "route.signs.selection",
        "route.signs.new",
        "route.signs.detail",
        "route.check.preflight",
        "route.check.capture",
        "route.check.outcome",
        "route.check.review",
        "route.check.receipt",
        "route.reports.detail",
        "route.reports.history",
        "route.reports.comparison",
        "route.reports.correction",
        "route.reports.failure",
        "route.issues.detail",
        "route.issues.work",
        "route.settings.hub",
        "route.settings.backup",
        "route.settings.diagnostics",
        "route.settings.feedback",
        "route.settings.erase",
        "route.settings.restore",
        "route.subscription.status",
        "route.subscription.paywall",
    ]

    private let fixtureIDs: Set<String> = [
        "fixture.invalid-pack",
        "fixture.empty-install",
        "fixture.sample-report",
        "fixture.visible-issue-report",
        "fixture.capture-recovery",
        "fixture.alternative-outcomes",
        "fixture.work-recheck",
        "fixture.report-history",
        "fixture.report-failure",
        "fixture.settings-data-rights",
        "fixture.valid-backup",
        "fixture.feedback-review",
        "fixture.commerce",
    ]

    private let commonTaskIDs: Set<String> = [
        "one_handed_start",
        "capture_and_review",
        "force_quit_draft_resume",
        "history_recovery",
        "work_and_recheck",
        "report_comprehension",
    ]

    func testFrozenContractsHaveOneUniqueReferentiallyCompleteGraph() throws {
        let stages = try json("docs/design/s10/s10-stage-checkpoints.json")
        let inventory = try json("docs/design/s10/s10-screen-state-inventory.json")
        let accessibility = try json("docs/design/s10/s10-accessibility-common-tasks.json")
        let tokens = try json("docs/design/s10/s10-token-coverage.json")
        let visual = try json("docs/design/s10/s10-visual-regression.json")
        let experience = try json("docs/design/s10/s10-experience-validation.json")
        let store = try json("docs/design/s10/s10-store-readiness.json")

        for document in [stages, inventory, accessibility, tokens, visual, experience, store] {
            XCTAssertEqual(document["schema_version"] as? String, "4.1.0")
        }
        XCTAssertEqual(stages["document_status"] as? String, "tracking")
        XCTAssertEqual(stages["receipt_model"] as? String, "E_product_K_evidence_C_receipt")
        XCTAssertEqual(inventory["document_status"] as? String, "frozen")
        XCTAssertEqual(accessibility["document_status"] as? String, "frozen")
        XCTAssertEqual(tokens["document_status"] as? String, "planned")
        XCTAssertEqual(visual["document_status"] as? String, "baseline_frozen")
        XCTAssertEqual(experience["document_status"] as? String, "planned")
        XCTAssertEqual(store["document_status"] as? String, "planned")

        let activationIDs = try [stages, experience, store].map {
            try string($0, "activation_id")
        }
        XCTAssertEqual(Set(activationIDs).count, 1)

        let routes = try rows(inventory, "routes")
        let fixtures = try rows(inventory, "fixtures")
        let tasks = try rows(accessibility, "tasks")
        let components = try rows(tokens, "components")
        let coverage = try rows(tokens, "coverage")
        XCTAssertFalse(routes.isEmpty)
        XCTAssertFalse(fixtures.isEmpty)
        XCTAssertFalse(tasks.isEmpty)
        XCTAssertFalse(components.isEmpty)

        let actualRouteIDs = try routes.map { try string($0, "route_id") }
        let actualFixtureIDs = try fixtures.map { try string($0, "fixture_id") }
        let taskIDs = try tasks.map { try string($0, "task_id") }
        let componentIDs = try components.map { try string($0, "component_id") }
        let stateRows = try routes.flatMap { try rows($0, "states") }
        let stateIDs = try stateRows.map { try string($0, "state_id") }
        let coverageIDs = try coverage.map { try string($0, "screen_state_id") }
        XCTAssertEqual(stateIDs.count, 67)
        let uiSource = String(
            decoding: try data(
                "FieldEvidenceAppUITests/S10_1BrandInventoryUITests.swift"
            ),
            as: UTF8.self
        )
        let statePattern = try NSRegularExpression(
            pattern: #"state\.[a-z0-9.-]+"#
        )
        let sourceRange = NSRange(uiSource.startIndex..<uiSource.endIndex, in: uiSource)
        let capturedStateIDs = statePattern.matches(
            in: uiSource,
            range: sourceRange
        ).compactMap { match -> String? in
            guard let range = Range(match.range, in: uiSource) else { return nil }
            return String(uiSource[range])
        }
        XCTAssertEqual(capturedStateIDs.count, 67)
        XCTAssertEqual(Set(capturedStateIDs), Set(stateIDs))
        assertUnique(actualRouteIDs, "route IDs")
        assertUnique(actualFixtureIDs, "fixture IDs")
        assertUnique(taskIDs, "task IDs")
        assertUnique(componentIDs, "component IDs")
        assertUnique(stateIDs, "state IDs")
        assertUnique(coverageIDs, "token coverage state IDs")
        XCTAssertEqual(Set(coverageIDs), Set(stateIDs))

        let migrationOrder = try strings(inventory, "migration_order")
        let migrationSlices = try routes.map { try string($0, "migration_slice_id") }
        XCTAssertEqual(Set(migrationOrder), Set(migrationSlices))
        assertUnique(migrationOrder, "migration order")

        for route in routes {
            try assertRepositoryPathsExist(try strings(route, "source_paths"))
        }
        for fixture in fixtures {
            try assertRepositoryPathsExist(try strings(fixture, "source_paths"))
        }
        for component in components {
            try assertRepositoryPathsExist(try strings(component, "source_paths"))
        }

        XCTAssertEqual(Set(actualRouteIDs), routeIDs)
        XCTAssertEqual(Set(actualFixtureIDs), fixtureIDs)
        XCTAssertEqual(Set(taskIDs), commonTaskIDs)

        let knownFixtures = Set(actualFixtureIDs)
        let knownTasks = Set(taskIDs)
        let knownComponents = Set(componentIDs)
        let knownTokens = try Set(components.flatMap { try strings($0, "token_ids") })
        var coverageByState: [String: [String: Any]] = [:]
        for row in coverage {
            coverageByState[try string(row, "screen_state_id")] = row
        }
        var referencedTaskIDs = Set<String>()
        for state in stateRows {
            let stateID = try string(state, "state_id")
            XCTAssertTrue(knownFixtures.contains(try string(state, "fixture_id")))
            let stateTaskIDs = Set(try strings(state, "common_task_ids"))
            XCTAssertTrue(stateTaskIDs.isSubset(of: knownTasks))
            referencedTaskIDs.formUnion(stateTaskIDs)
            let stateComponentIDs = Set(try strings(state, "component_ids"))
            let stateTokenIDs = Set(try strings(state, "token_ids"))
            XCTAssertTrue(stateComponentIDs.isSubset(of: knownComponents))
            XCTAssertTrue(stateTokenIDs.isSubset(of: knownTokens))
            let stateCoverage = try XCTUnwrap(coverageByState[stateID])
            XCTAssertEqual(Set(try strings(stateCoverage, "component_ids")), stateComponentIDs)
            XCTAssertEqual(Set(try strings(stateCoverage, "token_ids")), stateTokenIDs)
            XCTAssertEqual(stateCoverage["status"] as? String, "NOT_RUN")
            XCTAssertTrue(try strings(stateCoverage, "evidence_ids").isEmpty)
            assertUnique(try strings(state, "baseline_ids"), "baseline IDs for \(stateID)")
        }
        XCTAssertEqual(referencedTaskIDs, knownTasks)

        for task in tasks {
            let taskID = try string(task, "task_id")
            let listedStateIDs = Set(try strings(task, "screen_state_ids"))
            let referencedStateIDs = try Set(stateRows.compactMap { state -> String? in
                guard try strings(state, "common_task_ids").contains(taskID) else { return nil }
                return try string(state, "state_id")
            })
            XCTAssertEqual(listedStateIDs, referencedStateIDs)
        }
        for component in components {
            XCTAssertEqual(component["status"] as? String, "NOT_RUN")
            XCTAssertTrue(try strings(component, "evidence_ids").isEmpty)
        }
        XCTAssertEqual(tokens["untracked_visual_constant_count"] as? Int, 16)
    }

    func testAccessibilityExperienceAndVisualPlansAreCompleteButUnrun() throws {
        let inventory = try json("docs/design/s10/s10-screen-state-inventory.json")
        let accessibility = try json("docs/design/s10/s10-accessibility-common-tasks.json")
        let visual = try json("docs/design/s10/s10-visual-regression.json")
        let experience = try json("docs/design/s10/s10-experience-validation.json")
        let stages = try json("docs/design/s10/s10-stage-checkpoints.json")

        let profiles = try rows(inventory, "device_profiles")
        let deviceProfileIDs = try profiles.map { try string($0, "device_profile_id") }
        XCTAssertEqual(Set(deviceProfileIDs), [
            "iphone-17-ios-26.2-current",
            "iphone-se-3-ios-18.0-minimum",
        ])
        assertUnique(deviceProfileIDs, "device profile IDs")
        XCTAssertEqual(
            Set(try strings(accessibility, "device_profile_ids")),
            Set(deviceProfileIDs)
        )
        XCTAssertEqual(Set(try strings(accessibility, "features")), accessibilityFeatures)
        XCTAssertTrue(
            Set(try strings(accessibility, "eligible_features"))
                .isSubset(of: accessibilityFeatures)
        )

        let expectedPairs = Set(deviceProfileIDs.flatMap { profileID in
            accessibilityFeatures.map { "\(profileID)|\($0)" }
        })
        let tasks = try rows(accessibility, "tasks")
        for task in tasks {
            let results = try rows(task, "feature_results")
            let actualPairs = try results.map {
                "\(try string($0, "device_profile_id"))|\(try string($0, "feature"))"
            }
            assertUnique(actualPairs, "accessibility profile/feature rows")
            XCTAssertEqual(Set(actualPairs), expectedPairs)
            for result in results {
                XCTAssertEqual(result["automated_status"] as? String, "NOT_RUN")
                XCTAssertEqual(result["manual_status"] as? String, "NOT_RUN")
                XCTAssertTrue(try strings(result, "automated_evidence_ids").isEmpty)
                XCTAssertTrue(try strings(result, "manual_evidence_ids").isEmpty)
                XCTAssertEqual(result["automated_reviewer"] as? String, "")
                XCTAssertEqual(result["manual_reviewer"] as? String, "")
                XCTAssertEqual(result["exception_issue_id"] as? String, "")
                XCTAssertEqual(result["exception_owner"] as? String, "")
                XCTAssertEqual(result["exception_expires_at"] as? String, "")
                XCTAssertEqual(result["exception_rationale"] as? String, "")
            }
        }

        let experiencePlan = try object(experience, "plan")
        let taskIDs = try tasks.map { try string($0, "task_id") }
        XCTAssertEqual(Set(try strings(experiencePlan, "required_common_task_ids")), Set(taskIDs))
        XCTAssertEqual(
            Set(try strings(experiencePlan, "device_profile_ids")),
            Set(deviceProfileIDs)
        )
        XCTAssertEqual(experiencePlan["minimum_physical_sessions"] as? Int, 5)
        XCTAssertEqual(experiencePlan["minimum_distinct_roles"] as? Int, 3)
        XCTAssertTrue(try rows(experience, "physical_sessions").isEmpty)
        XCTAssertTrue(try rows(experience, "durability_results").isEmpty)
        XCTAssertTrue(try rows(experience, "performance_results").isEmpty)
        XCTAssertEqual(experience["severe_issue_count"] as? Int, 0)

        let matrix = try object(visual, "matrix_contract")
        XCTAssertEqual(Set(try strings(matrix, "required_requirement_ids")), visualRequirements)
        let currentProfiles = try profileIDs(forRole: "current", in: profiles)
        let minimumProfiles = try profileIDs(forRole: "minimum_supported", in: profiles)
        XCTAssertEqual(Set(try strings(matrix, "current_os_device_profile_ids")), currentProfiles)
        XCTAssertEqual(Set(try strings(matrix, "minimum_os_device_profile_ids")), minimumProfiles)

        let stateRows = try rows(inventory, "routes").flatMap { try rows($0, "states") }
        let stateIDs = try stateRows.map { try string($0, "state_id") }
        var fixtureIDByState: [String: String] = [:]
        for state in stateRows {
            fixtureIDByState[try string(state, "state_id")] = try string(state, "fixture_id")
        }
        let knownFixtures = Set(try rows(inventory, "fixtures").map { try string($0, "fixture_id") })
        let baselines = try rows(visual, "baselines")
        XCTAssertTrue(try rows(visual, "change_records").isEmpty)
        let checkpoints = try rows(stages, "checkpoints")
        XCTAssertTrue(checkpoints.count == 0 || checkpoints.count == 1)
        XCTAssertEqual(baselines.isEmpty, checkpoints.isEmpty)
        if checkpoints.isEmpty {
            return
        }

        let checkpoint = try XCTUnwrap(checkpoints.first)
        XCTAssertEqual(checkpoint["stage"] as? String, "Inventory")
        XCTAssertEqual(checkpoint["evidence_head_role"] as? String, "K")
        XCTAssertFalse(try rows(checkpoint, "documents").isEmpty)
        XCTAssertFalse(try strings(checkpoint, "evidence_ids").isEmpty)
        let productHead = try string(checkpoint, "product_head")

        let baselineIDs = try baselines.map { try string($0, "baseline_id") }
        assertUnique(baselineIDs, "visual baseline IDs")
        var actualPairs = Set<String>()
        var actualRequirements = Set<String>()
        var baselineIDsByState: [String: Set<String>] = [:]
        for baseline in baselines {
            let stateID = try string(baseline, "screen_state_id")
            XCTAssertTrue(Set(stateIDs).contains(stateID))
            let fixtureID = try string(baseline, "fixture_id")
            XCTAssertTrue(knownFixtures.contains(fixtureID))
            XCTAssertEqual(fixtureID, try XCTUnwrap(fixtureIDByState[stateID]))
            XCTAssertEqual(baseline["baseline_product_head"] as? String, productHead)
            XCTAssertEqual(baseline["baseline_review_status"] as? String, "APPROVED")
            XCTAssertFalse(try string(baseline, "baseline_reviewer").isEmpty)
            XCTAssertFalse(try strings(baseline, "baseline_evidence_ids").isEmpty)
            XCTAssertEqual(baseline["candidate_product_head"] as? String, "")
            XCTAssertEqual(baseline["candidate_screenshot_path"] as? String, "")
            XCTAssertEqual(baseline["candidate_sha256"] as? String, "")
            XCTAssertTrue(try strings(baseline, "intended_change_ids").isEmpty)
            XCTAssertEqual(baseline["result"] as? String, "NOT_RUN")
            XCTAssertEqual(baseline["review_status"] as? String, "NOT_REVIEWED")
            XCTAssertEqual(baseline["reviewer"] as? String, "")
            XCTAssertTrue(try strings(baseline, "evidence_ids").isEmpty)
            XCTAssertTrue(try string(baseline, "source_test").hasPrefix(
                "FieldEvidenceAppUITests/S10_1BrandInventoryUITests"
            ))
            for requirement in try strings(baseline, "requirement_ids") {
                XCTAssertTrue(visualRequirements.contains(requirement))
                XCTAssertTrue(actualPairs.insert("\(stateID)|\(requirement)").inserted)
                actualRequirements.insert(requirement)
            }
            baselineIDsByState[stateID, default: []].insert(try string(baseline, "baseline_id"))
        }

        XCTAssertEqual(actualRequirements, visualRequirements)
        XCTAssertEqual(Set(baselineIDsByState.keys), Set(stateIDs))
        for state in stateRows {
            let stateID = try string(state, "state_id")
            XCTAssertEqual(
                Set(try strings(state, "baseline_ids")),
                try XCTUnwrap(baselineIDsByState[stateID])
            )
        }
    }

    func testStorePlanAndCISelectorAreExact() throws {
        let store = try json("docs/design/s10/s10-store-readiness.json")
        let inventory = try json("docs/design/s10/s10-screen-state-inventory.json")
        let knownProfileIDs = Set(try rows(inventory, "device_profiles").map {
            try string($0, "device_profile_id")
        })
        let plan = try object(store, "plan")
        XCTAssertEqual(Set(try strings(plan, "release_locale_profile_ids")), ["en-US-release"])

        let slots = try rows(plan, "screenshot_slots")
        XCTAssertFalse(slots.isEmpty)
        let slotIDs = try slots.map { try string($0, "slot_id") }
        assertUnique(slotIDs, "store screenshot slot IDs")
        let groups = Dictionary(grouping: slots) { slot in
            let deviceClass = slot["device_class"] as? String ?? ""
            let locale = slot["locale_profile_id"] as? String ?? ""
            return "\(deviceClass)|\(locale)"
        }
        let expectedStory = ["find_asset", "capture_evidence", "share_report"]
        for (groupID, groupSlots) in groups {
            XCTAssertTrue((3...10).contains(groupSlots.count), groupID)
            let ordered = groupSlots.sorted {
                ($0["slot_order"] as? Int ?? 0) < ($1["slot_order"] as? Int ?? 0)
            }
            XCTAssertEqual(ordered.compactMap { $0["slot_order"] as? Int }, Array(1...ordered.count))
            XCTAssertEqual(Array(ordered.prefix(3)).compactMap { $0["story_role"] as? String }, expectedStory)
            for slot in ordered {
                XCTAssertTrue(knownProfileIDs.contains(try string(slot, "device_profile_id")))
                try assertOfficialScreenshotSpecification(slot)
            }
        }

        for key in [
            "privacy_results",
            "appearance_results",
            "accessibility_labels",
            "app_tags",
            "localization_metadata",
            "sdk_inventory",
            "platform_compatibility",
            "legal_urls",
        ] {
            try assertPlannedRowsAreUnrun(try rows(store, key), label: key)
        }
        XCTAssertTrue(try rows(store, "screenshots").isEmpty)
        XCTAssertTrue(try rows(store, "claims").isEmpty)
        for key in [
            "archive_privacy_report",
            "platform_compatibility_escape",
            "custom_product_pages",
            "ppo_experiments",
            "age_rating",
        ] {
            XCTAssertEqual(try object(store, key)["status"] as? String, "NOT_RUN", key)
        }

        let selectorData = try data("Scripts/ci-selection.json")
        XCTAssertEqual(selectorData.last, UInt8(0x0A))
        XCTAssertFalse(selectorData.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertFalse(selectorData.contains(0x0D))
        let selector = try object(from: selectorData)
        XCTAssertEqual(Set(selector.keys), [
            "schemaVersion",
            "taskID",
            "tier",
            "runUISmoke",
            "setupArtifactTimeoutSeconds",
            "buildTimeoutSeconds",
            "testTimeoutSeconds",
            "uiTimeoutSeconds",
            "totalBudgetSeconds",
            "unitTestSelectors",
            "uiTestSelectors",
        ])
        XCTAssertEqual(selector["schemaVersion"] as? Int, 1)
        XCTAssertEqual(selector["taskID"] as? String, "S10.1")
        XCTAssertEqual(selector["tier"] as? String, "F25")
        XCTAssertEqual(selector["runUISmoke"] as? Bool, true)
        XCTAssertEqual(selector["setupArtifactTimeoutSeconds"] as? Int, 300)
        XCTAssertEqual(selector["buildTimeoutSeconds"] as? Int, 900)
        XCTAssertEqual(selector["testTimeoutSeconds"] as? Int, 1_200)
        XCTAssertEqual(selector["uiTimeoutSeconds"] as? Int, 1_800)
        XCTAssertEqual(selector["totalBudgetSeconds"] as? Int, 4_500)
        XCTAssertEqual(try strings(selector, "unitTestSelectors"), [
            "FieldEvidenceAppTests/S10_1BrandInventoryTests",
        ])
        XCTAssertEqual(try strings(selector, "uiTestSelectors"), [
            "FieldEvidenceAppUITests/S10_1BrandInventoryUITests",
        ])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        try object(from: data(relativePath))
    }

    private func object(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func object(_ root: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(root[key] as? [String: Any], "Missing object \(key)")
    }

    private func rows(_ root: [String: Any], _ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(root[key] as? [[String: Any]], "Missing object array \(key)")
    }

    private func string(_ root: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(root[key] as? String, "Missing string \(key)")
    }

    private func strings(_ root: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(root[key] as? [String], "Missing string array \(key)")
    }

    private func assertUnique(
        _ values: [String],
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(values).count, values.count, "Duplicate \(label)", file: file, line: line)
        XCTAssertFalse(values.contains(where: { $0.isEmpty }), "Blank \(label)", file: file, line: line)
    }

    private func assertRepositoryPathsExist(
        _ relativePaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        assertUnique(relativePaths, "source paths", file: file, line: line)
        for relativePath in relativePaths {
            XCTAssertFalse(relativePath.hasPrefix("/"), relativePath, file: file, line: line)
            XCTAssertFalse(relativePath.contains("\\"), relativePath, file: file, line: line)
            XCTAssertFalse(
                relativePath.split(separator: "/").contains(".."),
                relativePath,
                file: file,
                line: line
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent(relativePath).path
                ),
                "Missing repository source \(relativePath)",
                file: file,
                line: line
            )
        }
    }

    private func profileIDs(
        forRole role: String,
        in profiles: [[String: Any]]
    ) throws -> Set<String> {
        try Set(profiles.compactMap { profile in
            guard try strings(profile, "os_roles").contains(role) else { return nil }
            return try string(profile, "device_profile_id")
        })
    }

    private func assertPlannedRowsAreUnrun(
        _ rows: [[String: Any]],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for row in rows {
            XCTAssertEqual(row["status"] as? String, "NOT_RUN", label, file: file, line: line)
            XCTAssertEqual(row["reviewer"] as? String, "", label, file: file, line: line)
            XCTAssertTrue(try strings(row, "evidence_ids").isEmpty, label, file: file, line: line)
        }
    }

    private func assertOfficialScreenshotSpecification(
        _ slot: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try string(slot, "apple_specification_url")
        let url = try XCTUnwrap(URL(string: source), file: file, line: line)
        XCTAssertEqual(url.scheme, "https", file: file, line: line)
        XCTAssertEqual(url.host, "developer.apple.com", file: file, line: line)
        XCTAssertEqual(
            url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "help/app-store-connect/reference/app-information/screenshot-specifications",
            file: file,
            line: line
        )
        let width = try XCTUnwrap(slot["pixel_width"] as? Int, file: file, line: line)
        let height = try XCTUnwrap(slot["pixel_height"] as? Int, file: file, line: line)
        let orientation = try string(slot, "orientation")
        let portraitSizes: Set<String> = [
            "1260x2736", "1290x2796", "1320x2868",
            "1284x2778", "1242x2688",
            "1179x2556", "1206x2622",
            "1170x2532", "1125x2436", "1080x2340",
        ]
        let normalizedSize = orientation == "portrait"
            ? "\(width)x\(height)"
            : "\(height)x\(width)"
        XCTAssertTrue(portraitSizes.contains(normalizedSize), normalizedSize, file: file, line: line)
    }
}
