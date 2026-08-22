import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

final class S10_4AutomatedBrandLabTests: XCTestCase {
    private struct ExpectedShard {
        let ordinal: Int
        let shardID: String
        let requirementID: String
        let deviceProfileID: String
        let runtime: String
        let simulator: String
        let osBuild: String
        let feature: String
        let appearance: String
        let contrast: String
        let contentSizeCategory: String
        let locale: String
        let layoutDirection: String
        let differentiateWithoutColor: Bool
        let reduceMotion: Bool
        let reduceTransparency: Bool
    }

    private struct PaletteEntry {
        let assetName: String
        let light: UInt32
        let dark: UInt32
        let lightContrast: Double?
        let darkContrast: Double?
    }

    private let overlayRoot =
        "docs/design/s10/authority/s10.4-automation-amendment-v1"
    private let acceptedMigrationHead =
        "e1004c9cfeff932e904046e0ad1aa31d2bb2c139"
    private let currentProfile = "iphone-17-ios-26.2-current"
    private let minimumProfile = "iphone-se-3-ios-18.0-minimum"
    private let expectedSourceTest =
        "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift::" +
        "S10_4AutomatedBrandLabUITests.testAutomatedBrandLabShard"

    private let requirementIDs = [
        "default_light", "default_dark", "increased_contrast", "ax_text",
        "double_length", "rtl", "rtl_string", "tall", "accented", "bounded",
        "differentiate_without_color", "reduce_motion", "reduce_transparency",
        "minimum_os",
    ]

    private let taskIDs = [
        "one_handed_start", "capture_and_review", "force_quit_draft_resume",
        "history_recovery", "work_and_recheck", "report_comprehension",
    ]

    private let accessibilityFeatures = [
        "voiceover", "voice_control", "larger_text", "dark_interface",
        "differentiate_without_color", "sufficient_contrast", "reduced_motion",
    ]

    private let tokenIDs = [
        "color.workBackground", "color.groupedBackground", "color.elevatedSurface",
        "color.primaryText", "color.secondaryText", "color.tertiaryText",
        "color.separator", "color.primaryAction", "color.brandHeading",
        "color.completed", "color.warning", "color.error", "color.unavailable",
        "color.selected", "color.disabled", "type.screenTitle", "type.sectionHeading",
        "type.primaryBody", "type.secondaryBody", "type.fieldLabel",
        "type.supportingCaption", "type.numericOrTimestamp", "space.4", "space.8",
        "space.12", "space.16", "space.20", "space.24", "space.32",
        "radius.compact", "radius.standard", "radius.prominent", "stroke.standard",
        "stroke.selected", "target.minimumInteractive", "environment.darkMode",
        "environment.increaseContrast", "environment.differentiateWithoutColor",
        "environment.reduceMotion", "environment.reduceTransparency",
        "environment.largerText", "environment.voiceOver", "environment.voiceControl",
        "environment.currentPlatform", "environment.minimumPlatform",
    ]

    func testPinnedOverlaySelectorAndExactSevenPlusSevenShardContract() throws {
        let manifestPath = "\(overlayRoot)/manifest.json"
        let visualSchemaPath = "\(overlayRoot)/s10-visual-regression.schema.json"
        let accessibilitySchemaPath =
            "\(overlayRoot)/s10-accessibility-common-tasks.schema.json"
        let shardPath = "Scripts/s10-4-shards.json"

        try assertFile(
            manifestPath,
            byteCount: 19_037,
            sha256: "7A517533F88A74A6EB2E3676DD3C5BD3D452D271BFC1EDD175F1CC83CAEDDB2E"
        )
        try assertFile(
            visualSchemaPath,
            byteCount: 18_485,
            sha256: "C922EDE2685691B488E8664F2AA89CE52D989C29FD54C0793EBD825DCC1A4DAE"
        )
        try assertFile(
            accessibilitySchemaPath,
            byteCount: 7_108,
            sha256: "E0893E86636F9F558103FED7173432998F18A459613EECAAB9A4B0CD65CEA0E3"
        )
        try assertFile(
            shardPath,
            byteCount: 6_678,
            sha256: "C023ADE99CAB0F9ED2984C90BCC0E03B0D05A05643DF7185201CC00772E3C8E4"
        )
        let workflowPath = ".github/workflows/ios-ci.yml"
        try assertFile(
            workflowPath,
            byteCount: 101_902,
            sha256: "119FF51D3C10E69558811AFFCE661AB98A640FC0F5BF803DF327183AC5E0B084"
        )
        let workflowSource = try text(workflowPath)
        let retainStepMarker = "      - name: Retain S10.4 shard evidence\n"
        let retainBoundaryMarker =
            "      - name: Begin evidence-finalization budget\n"
        let retainStepParts = workflowSource.components(separatedBy: retainStepMarker)
        guard retainStepParts.count == 2 else {
            XCTFail("The workflow must contain exactly one S10.4 retention step")
            return
        }
        let retainTail = retainStepParts[1]
        guard let retainBoundary = retainTail.range(of: retainBoundaryMarker) else {
            XCTFail("The S10.4 retention step has no exact finalization boundary")
            return
        }
        let retainStepSource = String(retainTail[..<retainBoundary.lowerBound])
        let retainRunMarker = "        run: |\n"
        let retainRunParts = retainStepSource.components(separatedBy: retainRunMarker)
        guard retainRunParts.count == 2 else {
            XCTFail("The S10.4 retention step must contain exactly one run block")
            return
        }
        let retainEnvironmentHandoff =
            "        env:\n" +
                #"          DISPATCH_S10_4_SHARD_ID: ${{ inputs.s10_4_shard_id }}"# +
                "\n        run: |"
        XCTAssertEqual(
            retainStepSource.components(separatedBy: retainEnvironmentHandoff).count - 1,
            1
        )
        let retainRunSource = retainRunParts[1]
        XCTAssertEqual(
            retainRunSource.components(
                separatedBy:
                    #"test "$CI_S10_4_SHARD_ID" = "$DISPATCH_S10_4_SHARD_ID""#
            ).count - 1,
            1
        )
        XCTAssertFalse(retainRunSource.contains("${{"))

        let manifest = try json(manifestPath)
        XCTAssertEqual(try string(manifest, "schema_version"), "1.0.0")
        XCTAssertEqual(try string(manifest, "document_status"), "frozen")
        XCTAssertEqual(
            try string(manifest, "amendment_id"),
            "assetrounds-s10.4-automation-amendment-v1"
        )

        let base = try object(manifest, "base_authority")
        let pinnedBaseFiles = [
            ("activation_path", "activation_sha256"),
            ("package_path", "package_sha256"),
            ("asset_manifest_path", "asset_manifest_sha256"),
            ("runbook_path", "runbook_sha256"),
        ]
        for (pathKey, hashKey) in pinnedBaseFiles {
            let path = try string(base, pathKey)
            XCTAssertEqual(try data(path).sha256, try string(base, hashKey), path)
        }
        XCTAssertEqual(
            try string(base, "workflow_sha256_before_amendment"),
            "BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7"
        )
        XCTAssertEqual(
            try string(base, "v4_1_visual_schema_sha256"),
            "EA0F3305B29117A8773285426AF362C7667E25171773CAAE2CFF37594AF8C0AB"
        )
        XCTAssertEqual(
            try string(base, "v4_1_accessibility_schema_sha256"),
            "DF5259ADA9BADD1CF54110FC2DE0D335C84BCF3AAA350A92FB30752E1D48F9EA"
        )
        XCTAssertEqual(
            try string(base, "v4_1_validator_sha256"),
            "01758757075941E35C298CB692C17A82C90167A283BBBEC0AF1CC05C963266D7"
        )
        XCTAssertEqual(try string(base, "accepted_migration_product_head"), acceptedMigrationHead)
        XCTAssertEqual(
            try string(base, "accepted_migration_evidence_head"),
            "9461a8ef52cdd2a1a49a95d34c7e7ea8abd9d284"
        )
        XCTAssertEqual(
            try string(base, "accepted_migration_receipt_head"),
            "d4661ef2096fb55c824842965bee06630cc0aeb7"
        )

        let overlayFiles = try rows(manifest, "overlay_files")
        XCTAssertEqual(try overlayFiles.map { try string($0, "path") }, [
            "s10-visual-regression.schema.json",
            "s10-accessibility-common-tasks.schema.json",
            "validate-s10-contracts.ps1",
        ])
        for row in overlayFiles {
            try assertFile(
                "\(overlayRoot)/\(try string(row, "path"))",
                byteCount: try int(row, "byte_length"),
                sha256: try string(row, "sha256")
            )
        }

        try assertOverlaySchemas(
            visual: json(visualSchemaPath),
            accessibility: json(accessibilitySchemaPath)
        )

        let matrix = try object(manifest, "matrix_contract")
        XCTAssertEqual(try int(matrix, "state_count"), 67)
        XCTAssertEqual(try int(matrix, "requirement_count"), 14)
        XCTAssertEqual(try int(matrix, "candidate_cell_count"), 938)
        XCTAssertEqual(try int(matrix, "shard_count"), 14)
        XCTAssertEqual(try int(matrix, "task_count"), 6)
        XCTAssertEqual(try int(matrix, "device_profile_count"), 2)
        XCTAssertEqual(try int(matrix, "accessibility_feature_count"), 7)
        XCTAssertEqual(try int(matrix, "accessibility_row_count"), 84)
        XCTAssertEqual(try string(matrix, "source_test"), expectedSourceTest)
        XCTAssertEqual(
            try string(matrix, "legacy_baseline_candidate_fields"),
            "immutable_blank"
        )
        XCTAssertEqual(try string(matrix, "manual_accessibility_status"), "NOT_RUN")
        XCTAssertEqual(try strings(manifest, "required_requirement_ids"), requirementIDs)
        XCTAssertEqual(try strings(manifest, "required_task_ids"), taskIDs)
        XCTAssertEqual(
            try strings(manifest, "required_accessibility_features"),
            accessibilityFeatures
        )

        let selector = #"{"schemaVersion":1,"taskID":"S10.4","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S10_4AutomatedBrandLabTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests"]}"# + "\n"
        let selectorData = try data("Scripts/ci-selection.json")
        XCTAssertEqual(selectorData, Data(selector.utf8))
        XCTAssertEqual(selectorData.count, 354)
        XCTAssertEqual(
            selectorData.sha256,
            "571AC854A230A95F90368EC50CA625AD13B170AFC06DFF503D1C9F99796EF7D5"
        )

        let shardContract = try json(shardPath)
        XCTAssertEqual(try int(shardContract, "schemaVersion"), 1)
        XCTAssertEqual(try string(shardContract, "taskID"), "S10.4")
        XCTAssertEqual(try int(shardContract, "expectedStateCount"), 67)
        XCTAssertEqual(try int(shardContract, "expectedVisualCellCount"), 938)
        XCTAssertEqual(try int(shardContract, "expectedAccessibilityRowCount"), 84)
        XCTAssertEqual(try int(shardContract, "commonTaskCount"), 6)
        try assertDeviceProfiles(try rows(shardContract, "deviceProfiles"))

        let manifestShards = try rows(manifest, "shards")
        let scriptShards = try rows(shardContract, "shards")
        XCTAssertEqual(manifestShards.count, 14)
        XCTAssertEqual(scriptShards.count, 14)
        XCTAssertEqual(expectedShards.count, 14)
        for (index, expected) in expectedShards.enumerated() {
            try assertManifestShard(manifestShards[index], equals: expected)
            try assertScriptShard(scriptShards[index], equals: expected)
        }
        for profile in [currentProfile, minimumProfile] {
            let profileShards = try manifestShards.filter {
                try string($0, "device_profile_id") == profile
            }
            XCTAssertEqual(profileShards.count, 7, profile)
            try assertExactSet(
                profileShards.map { try string($0, "accessibility_feature") },
                accessibilityFeatures,
                profile
            )
        }

        let sourceParts = expectedSourceTest.components(separatedBy: "::")
        XCTAssertEqual(sourceParts.count, 2)
        let diagnosticExportPath =
            "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift"
        try assertFile(
            diagnosticExportPath,
            byteCount: 9_899,
            sha256: "7F9330FE35C4DAEE956C103F3152184F5C1CAF4284EF36408B2EEC231BC6F70F"
        )
        let diagnosticExportSource = try text(diagnosticExportPath)
        XCTAssertEqual(
            diagnosticExportSource.components(
                separatedBy: "struct DiagnosticExportView: View {"
            ).count - 1,
            1
        )
        let diagnosticScrollBottomPaddingPlacement =
            "            }\n" +
                "            .padding(DesignTokens.Spacing.space16)\n" +
                "            .padding(.bottom, DesignTokens.Spacing.space32)\n" +
                "        }\n" +
                "        .modifier(DiagnosticExportScrollEdgeVisibility())\n" +
                #"        .navigationTitle("Diagnostics")"#
        XCTAssertEqual(
            diagnosticExportSource.components(
                separatedBy: diagnosticScrollBottomPaddingPlacement
            ).count - 1,
            1
        )
        XCTAssertEqual(
            diagnosticExportSource.components(
                separatedBy: ".padding(.bottom, DesignTokens.Spacing.space32)"
            ).count - 1,
            1
        )
        try assertFile(
            sourceParts[0],
            byteCount: 216_455,
            sha256: "83CE16A870DB880BC5B57AC9D18F906B77EB97D8F54B89CB69817D097F644676"
        )
        let uiSource = try text(sourceParts[0])
        XCTAssertTrue(uiSource.contains("class S10_4AutomatedBrandLabUITests"))
        for throwingDiagnosticsCallChainLock in [
            "        try assertMonthlyPaywallAtXXXL(in: app)",
            "    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) throws {",
            "        try captureSettingsDataSurfaces(in: app)",
            "    private func captureSettingsDataSurfaces(in app: XCUIApplication) throws {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: throwingDiagnosticsCallChainLock
                ).count - 1,
                1,
                throwingDiagnosticsCallChainLock
            )
        }
        for removedNonthrowingDiagnosticsCallChainLock in [
            "        assertMonthlyPaywallAtXXXL(in: app)",
            "    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) {",
            "        captureSettingsDataSurfaces(in: app)",
            "    private func captureSettingsDataSurfaces(in app: XCUIApplication) {",
        ] {
            XCTAssertFalse(
                uiSource.contains(removedNonthrowingDiagnosticsCallChainLock),
                removedNonthrowingDiagnosticsCallChainLock
            )
        }
        XCTAssertTrue(uiSource.contains("func testAutomatedBrandLabShard()"))
        XCTAssertTrue(uiSource.contains("printJSONLine(prefix: \"S10_4_AX_STATE\""))
        XCTAssertTrue(uiSource.contains("printJSONLine(prefix: \"S10_4_CONTRAST\""))
        XCTAssertTrue(uiSource.contains("printJSONLine(prefix: \"S10_4_AX\""))
        XCTAssertTrue(uiSource.contains(#""s10.4-ax-\(shard.shardID)-\(stateID)""#))
        XCTAssertTrue(uiSource.contains("s10.4-focus-order-"))
        XCTAssertTrue(uiSource.contains("s10.4-target-size-"))
        XCTAssertTrue(uiSource.contains("automatedEvidenceIDs"))
        XCTAssertTrue(uiSource.contains("22A3351"))

        let freshPreflightKeyboardDismissal =
            #"let doneKey = app.keyboards.buttons["Done"]"# + "\n" +
                "        if doneKey.exists && doneKey.isHittable {\n" +
                "            doneKey.tap()\n" +
                "        } else {\n" +
                "            dismissKeyboard(in: app)\n" +
                "        }\n" +
                "        XCTAssertTrue(\n" +
                "            wait(\n" +
                "                for: app.keyboards.firstMatch,\n" +
                #"                predicate: "exists == false","# + "\n" +
                "                timeout: 10\n" +
                "            )\n" +
                "        )\n" +
                #"        setToggle("s3.preflight.time-zone-confirmed", in: app)"# +
                "\n" +
                #"        setToggle("s3.preflight.after-dark", in: app)"# + "\n" +
                "        app.swipeUp()\n" +
                #"        setToggle("s3.preflight.safe-position", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: freshPreflightKeyboardDismissal
            ).count - 1,
            1
        )
        XCTAssertFalse(
            uiSource.contains(
                "doneKey.exists ? doneKey.tap() : dismissKeyboard(in: app)"
            )
        )

        let preflightQuickPathStart =
            #"        let preflight = element("s3.preflight.screen", in: app)"#
        let preflightQuickPathCapture =
            #"        captureBaseline("state.check-preflight.ready", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: preflightQuickPathStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: preflightQuickPathCapture).count - 1,
            1
        )
        guard let preflightQuickPathStartRange = uiSource.range(
            of: preflightQuickPathStart
        ),
        let preflightQuickPathCaptureRange = uiSource.range(
            of: preflightQuickPathCapture,
            range: preflightQuickPathStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the unique preflight QuickPath source slice")
            return
        }
        let preflightQuickPathSource = String(
            uiSource[
                preflightQuickPathStartRange.lowerBound..<preflightQuickPathCaptureRange.lowerBound
            ]
        )
        let preflightZoneMove =
            #"        let zone = element("s3.preflight.time-zone", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: preflightZoneMove).count - 1,
            1
        )
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: preflightZoneMove).count - 1,
            1
        )
        let preflightMinimumGate =
            #"        if automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" {"#
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: preflightMinimumGate).count - 1,
            1
        )
        let preflightReturnAbsenceDiscriminator =
            #"            let returnKey = app.keyboards.buttons["Return"]"# + "\n" +
                #"            if !returnKey.waitForExistence(timeout: 1) {"#
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightReturnAbsenceDiscriminator
            ).count - 1,
            1
        )
        XCTAssertFalse(preflightQuickPathSource.contains("returnKey.exists"))

        let preflightPreActionSnapshots = [
            "                let preActionZoneLabel = zone.label",
            "                let preActionZoneValue = zone.value as? String",
            "                let preActionPreflightExists = preflight.exists",
            #"                let detailRoute = element("s2.sign-detail.screen", in: app)"#,
            "                let preActionDetailRouteExists = detailRoute.exists",
            "                let keyboard = app.keyboards.firstMatch",
        ]
        for lock in preflightPreActionSnapshots {
            XCTAssertEqual(
                preflightQuickPathSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let preflightPrecondition =
            "                guard keyboard.waitForExistence(timeout: 10),\n" +
                "                      wait(\n" +
                "                          for: zone,\n" +
                #"                          predicate: "hasKeyboardFocus == true","# + "\n" +
                "                          timeout: 10\n" +
                "                      ),\n" +
                "                      preActionPreflightExists,\n" +
                "                      !preActionDetailRouteExists,\n" +
                "                      app.state == .runningForeground else {"
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: preflightPrecondition).count - 1,
            1
        )
        let preflightFrozenKeyboardFrame =
            "                let expectedKeyboardFrame = CGRect(\n" +
                "                    x: 0,\n" +
                "                    y: 451,\n" +
                "                    width: 375,\n" +
                "                    height: 216\n" +
                "                )"
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightFrozenKeyboardFrame
            ).count - 1,
            1
        )
        let preflightObservedKeyboardFrame =
            "                let observedKeyboardFrame = keyboard.frame\n" +
                "                guard observedKeyboardFrame == expectedKeyboardFrame else {"
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightObservedKeyboardFrame
            ).count - 1,
            1
        )
        let preflightNormalizedCoordinate =
            "                keyboard.coordinate(\n" +
                "                    withNormalizedOffset: CGVector(\n" +
                "                        dx: 0.5,\n" +
                "                        dy: 0.8425925925925926\n" +
                "                    )\n" +
                "                ).tap()"
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightNormalizedCoordinate
            ).count - 1,
            1
        )
        let preflightRestorationGuard =
            "                let restoredKeyboard = app.keyboards.firstMatch\n" +
                #"                let restoredDoneKey = app.keyboards.buttons["Done"]"# + "\n" +
                "                let expectedDoneFrame = CGRect(\n" +
                "                    x: 281.5,\n" +
                "                    y: 620,\n" +
                "                    width: 93.5,\n" +
                "                    height: 46\n" +
                "                )\n" +
                "                guard restoredDoneKey.waitForExistence(timeout: 10),\n" +
                "                      restoredDoneKey.elementType == .button,\n" +
                #"                      restoredDoneKey.identifier == "Done","# + "\n" +
                #"                      restoredDoneKey.label == "done","# + "\n" +
                "                      restoredDoneKey.frame == expectedDoneFrame,\n" +
                "                      restoredDoneKey.isHittable,\n" +
                "                      restoredKeyboard.waitForExistence(timeout: 10),\n" +
                "                      restoredKeyboard.frame == observedKeyboardFrame,\n" +
                "                      wait(\n" +
                "                          for: zone,\n" +
                #"                          predicate: "hasKeyboardFocus == true","# + "\n" +
                "                          timeout: 10\n" +
                "                      ),\n" +
                "                      preflight.waitForExistence(timeout: 10),\n" +
                "                      preflight.exists == preActionPreflightExists,\n" +
                "                      detailRoute.exists == preActionDetailRouteExists,\n" +
                "                      zone.label == preActionZoneLabel,\n" +
                "                      (zone.value as? String) == preActionZoneValue,\n" +
                "                      app.state == .runningForeground else {"
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightRestorationGuard
            ).count - 1,
            1
        )
        let preflightIncompleteFailure =
            "                    XCTFail(\"The iOS 18 preflight QuickPath state is incomplete.\")\n" +
                "                    return\n" +
                "                }"
        let preflightFrameFailure =
            "                    XCTFail(\"The iOS 18 preflight keyboard frame does not match the frozen QuickPath tutorial evidence.\")\n" +
                "                    return\n" +
                "                }"
        let preflightRestorationFailure =
            "                    XCTFail(\"The preflight state or content was not restored after dismissing the QuickPath tutorial.\")\n" +
                "                    return\n" +
                "                }"
        for lock in [
            preflightIncompleteFailure,
            preflightFrameFailure,
            preflightRestorationFailure,
        ] {
            XCTAssertEqual(
                preflightQuickPathSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: "XCTFail(").count - 1,
            3
        )
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: "                    return\n").count - 1,
            3
        )
        XCTAssertFalse(
            preflightQuickPathSource.contains(
                "guard returnKey.waitForExistence(timeout: 10)"
            )
        )
        let preflightQuickPathCapturePrecededByRestoration =
            preflightRestorationFailure + "\n            }\n        }\n" +
                preflightQuickPathCapture
        XCTAssertEqual(
            uiSource.components(
                separatedBy: preflightQuickPathCapturePrecededByRestoration
            ).count - 1,
            1
        )
        let preflightZoneUseAfterCapture =
            preflightQuickPathCapture + "\n\n        scroll(zone, in: app)"
        XCTAssertEqual(
            uiSource.components(separatedBy: preflightZoneUseAfterCapture).count - 1,
            1
        )

        let newSignQuickPathProfileGuard =
            #"        if automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" {"#
        let newSignRouteStart =
            "        let prePositionSiteValue = site.value as? String"
        let newSignFinalGuard =
            "        guard finalFocusPreserved,\n" +
                "              finalKeyboardExists,\n" +
                "              finalErrorContained,\n" +
                "              finalContentPreserved,\n" +
                "              finalDetailRoutePreserved,\n" +
                "              app.state == .runningForeground else {\n" +
                "            XCTFail(\"New-sign validation did not remain focused, unchanged, and fully visible above the keyboard.\")\n" +
                "            return\n" +
                "        }"
        let newSignRoutePreconditionStart =
            #"        let error = element("s2.new-sign.error", in: app)"#
        let preservedNewSignInputLocks = [
            #"        assertLocalizedValue(sign, equals: "Monument Sign")"#,
            #"        XCTAssertFalse(element("s2.sign-detail.screen", in: app).exists)"#,
        ]
        XCTAssertEqual(
            uiSource.components(separatedBy: newSignRoutePreconditionStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: newSignRouteStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: newSignQuickPathProfileGuard).count - 1,
            2
        )
        guard let newSignRoutePreconditionStartRange = uiSource.range(
            of: newSignRoutePreconditionStart
        ) else {
            XCTFail("Missing the new-sign validation route precondition start")
            return
        }
        guard let newSignRouteStartRange = uiSource.range(of: newSignRouteStart) else {
            XCTFail("Missing the new-sign validation viewport route start")
            return
        }
        guard let newSignQuickPathProfileRange = uiSource.range(
            of: newSignQuickPathProfileGuard
        ) else {
            XCTFail("Missing the H135 QuickPath profile guard after viewport recovery")
            return
        }
        let newSignRoutePreconditionSource = String(
            uiSource[
                newSignRoutePreconditionStartRange.lowerBound..<newSignRouteStartRange.lowerBound
            ]
        )
        for lock in preservedNewSignInputLocks {
            XCTAssertEqual(
                newSignRoutePreconditionSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let newSignRouteSource = String(
            uiSource[
                newSignRouteStartRange.lowerBound..<newSignQuickPathProfileRange.lowerBound
            ]
        )
        let newSignFinalStateLocks = [
            "        let finalFocusPreserved = wait(\n" +
                "            for: site,\n" +
                #"            predicate: "hasKeyboardFocus == true","# + "\n" +
                "            timeout: 10\n" +
                "        )",
            "        let finalKeyboardExists = keyboard.waitForExistence(timeout: 10)",
            "        let finalErrorExists = error.waitForExistence(timeout: 10)",
            "        let finalScrollFrame = scrollView.frame",
            "        let finalVisibleTop = max(finalScrollFrame.minY, navigationBottom)",
            "        let finalVisibleBottom = finalKeyboardExists\n" +
                "            ? min(finalScrollFrame.maxY, keyboard.frame.minY)\n" +
                "            : -CGFloat.greatestFiniteMagnitude",
            "        let finalErrorContained = finalErrorExists\n" +
                "            && error.frame.minY >= finalVisibleTop\n" +
                "            && error.frame.maxY <= finalVisibleBottom",
            "        let finalContentPreserved = finalErrorExists\n" +
                "            && (site.value as? String) == prePositionSiteValue\n" +
                "            && (sign.value as? String) == prePositionSignValue\n" +
                "            && error.label == prePositionErrorLabel\n" +
                "            && (error.value as? String) == prePositionErrorValue",
            "        let finalDetailRoutePreserved =\n" +
                "            validationDetailRoute.exists == prePositionDetailRouteExists",
        ]
        for lock in newSignFinalStateLocks {
            XCTAssertEqual(
                newSignRouteSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let newSignFinalGuardBeforeH135 =
            newSignFinalGuard + "\n" + newSignQuickPathProfileGuard
        XCTAssertEqual(
            uiSource.components(separatedBy: newSignFinalGuardBeforeH135).count - 1,
            1
        )
        let newSignRouteOrderedLocks = [
            "        let prePositionSiteValue = site.value as? String",
            "        let prePositionSignValue = sign.value as? String",
            "        let prePositionErrorLabel = error.label",
            "        let prePositionErrorValue = error.value as? String",
            "        let validationDetailRoute = element(\"s2.sign-detail.screen\", in: app)",
            "        let prePositionDetailRouteExists = validationDetailRoute.exists",
            "        let dragInset: CGFloat = 24",
            "        let minimumGestureDistance: CGFloat = 44",
            "        for _ in 0..<12 {",
            "            let liveScrollFrame = scrollView.frame",
            "            let liveVisibleTop = max(liveScrollFrame.minY, navigationBottom)",
            "            let liveVisibleBottom = min(\n" +
                "                liveScrollFrame.maxY,\n" +
                "                keyboard.frame.minY\n" +
                "            )",
            "            let errorFrame = error.frame",
            "            if errorFrame.minY >= liveVisibleTop,\n" +
                "               errorFrame.maxY <= liveVisibleBottom {\n" +
                "                break\n" +
                "            }",
            "            let minimumShift = liveVisibleTop - errorFrame.minY\n" +
                "            let maximumShift = liveVisibleBottom - errorFrame.maxY",
            "            let farFeasibleShift = abs(minimumShift) >= abs(maximumShift)\n" +
                "                ? minimumShift\n" +
                "                : maximumShift",
            "            let maximumGestureDistance =\n" +
                "                liveVisibleBottom - liveVisibleTop - (2 * dragInset)",
            "            let dragDistance = max(\n" +
                "                -maximumGestureDistance,\n" +
                "                min(farFeasibleShift, maximumGestureDistance)\n" +
                "            )",
            "            let scrollOrigin = scrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )",
            "            let dragStartOffsetY = dragDistance > 0\n" +
                "                ? liveVisibleTop - liveScrollFrame.minY + dragInset\n" +
                "                : liveVisibleBottom - liveScrollFrame.minY - dragInset",
            "            let dragStart = scrollOrigin.withOffset(\n" +
                "                CGVector(\n" +
                "                    dx: liveScrollFrame.width / 2,\n" +
                "                    dy: dragStartOffsetY\n" +
                "                )\n" +
                "            )",
            "            let dragEnd = dragStart.withOffset(\n" +
                "                CGVector(dx: 0, dy: dragDistance)\n" +
                "            )",
            "            let errorBeforeDrag = error.frame.minY\n" +
                "            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)\n" +
                "            let observedShift = error.frame.minY - errorBeforeDrag",
            newSignFinalGuard,
        ]
        var orderedNewSignRouteTail = newSignRouteSource
        for lock in newSignRouteOrderedLocks {
            XCTAssertEqual(
                newSignRouteSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
            guard let lockRange = orderedNewSignRouteTail.range(of: lock) else {
                XCTFail("New-sign validation viewport locks are out of order: \(lock)")
                return
            }
            orderedNewSignRouteTail = String(
                orderedNewSignRouteTail[lockRange.upperBound...]
            )
        }
        let newSignRouteFailureLocks = [
            "            guard liveVisibleBottom > liveVisibleTop else {\n" +
                "                XCTFail(\"New-sign validation has no visible keyboard-safe interval.\")\n" +
                "                return\n" +
                "            }",
            "            guard minimumShift <= maximumShift else {\n" +
                "                XCTFail(\"New-sign validation error cannot fit the keyboard-safe viewport.\")\n" +
                "                return\n" +
                "            }",
            "            guard maximumGestureDistance >= minimumGestureDistance else {\n" +
                "                XCTFail(\"New-sign validation viewport cannot recognize a safe gesture.\")\n" +
                "                return\n" +
                "            }",
            "            guard abs(dragDistance) >= minimumGestureDistance else {\n" +
                "                XCTFail(\"New-sign validation feasible shift is below gesture recognition.\")\n" +
                "                return\n" +
                "            }",
            "            guard observedShift * dragDistance > 0 else {\n" +
                "                XCTFail(\"New-sign validation positioning gesture was not recognized.\")\n" +
                "                return\n" +
                "            }",
        ]
        for lock in newSignRouteFailureLocks {
            XCTAssertEqual(
                newSignRouteSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            newSignRouteSource.components(separatedBy: "XCTFail(").count - 1,
            6
        )
        XCTAssertEqual(
            newSignRouteSource.components(
                separatedBy: "                return\n            }"
            ).count - 1,
            5
        )
        XCTAssertEqual(
            newSignRouteSource.components(
                separatedBy: "            return\n        }"
            ).count - 1,
            1
        )
        XCTAssertFalse(
            newSignRouteSource.contains(
                "        let dragStartOffsetY = visibleBottom - scrollFrame.minY - dragInset"
            )
        )
        XCTAssertFalse(
            newSignRouteSource.contains(
                "        let dragEndOffsetY = visibleTop - scrollFrame.minY + dragInset"
            )
        )

        let quickPathViewportTail =
            newSignFinalGuard
        let quickPathCapture =
            #"        captureBaseline("state.new-sign.validation-error", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: quickPathViewportTail).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: quickPathCapture).count - 1,
            1
        )
        guard let quickPathViewportRange = uiSource.range(of: quickPathViewportTail) else {
            XCTFail("Missing the new-sign validation viewport tail")
            return
        }
        let uiSourceAfterQuickPathViewport = uiSource[quickPathViewportRange.upperBound...]
        guard let quickPathCaptureRange = uiSourceAfterQuickPathViewport.range(
            of: quickPathCapture
        ) else {
            XCTFail("Missing the new-sign validation capture after QuickPath recovery")
            return
        }
        let quickPathViewportToCaptureSource = String(
            uiSource[quickPathViewportRange.upperBound..<quickPathCaptureRange.lowerBound]
        )
        let quickPathProfileGuard =
            #"        if automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" {"#
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(
                separatedBy: quickPathProfileGuard
            ).count - 1,
            1
        )
        let quickPathSemanticSnapshots = [
            "            let preActionSiteValue = site.value as? String",
            "            let preActionErrorLabel = error.label",
            "            let preActionErrorValue = error.value as? String",
        ]
        for lock in quickPathSemanticSnapshots {
            XCTAssertEqual(
                quickPathViewportToCaptureSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(quickPathSemanticSnapshots.count, 3)
        let quickPathReturnProbe =
            #"            let returnKey = app.keyboards.buttons["Return"]"# + "\n" +
                #"            if !returnKey.waitForExistence(timeout: 1) {"#
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathReturnProbe).count - 1,
            1
        )
        XCTAssertFalse(quickPathViewportToCaptureSource.contains("returnKey.exists"))
        let quickPathExpectedFrame =
            "                let expectedKeyboardFrame = CGRect(\n" +
                "                    x: 0,\n" +
                "                    y: 451,\n" +
                "                    width: 375,\n" +
                "                    height: 216\n" +
                "                )"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathExpectedFrame).count - 1,
            1
        )
        let quickPathObservedFrame =
            "                let observedKeyboardFrame = keyboard.frame\n" +
                "                guard observedKeyboardFrame == expectedKeyboardFrame else {"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathObservedFrame).count - 1,
            1
        )
        let quickPathFrameFailure =
            "                    XCTFail(\"The iOS 18 keyboard frame does not match the frozen QuickPath tutorial evidence.\")\n" +
                "                    return\n" +
                "                }"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathFrameFailure).count - 1,
            1
        )
        let quickPathNormalizedCoordinate =
            "                keyboard.coordinate(\n" +
                "                    withNormalizedOffset: CGVector(\n" +
                "                        dx: 0.5,\n" +
                "                        dy: 0.8425925925925926\n" +
                "                    )\n" +
                "                ).tap()"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(
                separatedBy: quickPathNormalizedCoordinate
            ).count - 1,
            1
        )
        let quickPathRestoredKeyboard =
            "                let restoredKeyboard = app.keyboards.firstMatch\n" +
                "                guard returnKey.waitForExistence(timeout: 10),\n" +
                "                      restoredKeyboard.waitForExistence(timeout: 10),\n" +
                "                      restoredKeyboard.frame == observedKeyboardFrame,"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(
                separatedBy: quickPathRestoredKeyboard
            ).count - 1,
            1
        )
        let quickPathRestorationLocks = [
            "                      wait(\n" +
                "                          for: site,\n" +
                #"                          predicate: "hasKeyboardFocus == true","# + "\n" +
                "                          timeout: 10\n" +
                "                      ),",
            "                      error.waitForExistence(timeout: 10),",
            "                      (site.value as? String) == preActionSiteValue,",
            "                      error.label == preActionErrorLabel,",
            "                      (error.value as? String) == preActionErrorValue,",
            "                      app.state == .runningForeground else {",
        ]
        for lock in quickPathRestorationLocks {
            XCTAssertEqual(
                quickPathViewportToCaptureSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let quickPathRestorationFailure =
            "                    XCTFail(\"The new-sign validation state or content was not restored after dismissing the QuickPath tutorial.\")\n" +
                "                    return\n" +
                "                }"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathRestorationFailure).count - 1,
            1
        )
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: "XCTFail(").count - 1,
            2
        )
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: "                    return\n").count - 1,
            2
        )
        let quickPathCapturePrecededByRestoration =
            quickPathRestorationFailure + "\n            }\n        }\n" + quickPathCapture
        XCTAssertEqual(
            uiSource.components(separatedBy: quickPathCapturePrecededByRestoration).count - 1,
            1
        )

        let positionedSafePositionToggle =
            #"        setToggle("s3.preflight.after-dark", in: app)"# + "\n" +
                "        app.swipeUp()\n" +
                #"        setToggle("s3.preflight.safe-position", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: positionedSafePositionToggle
            ).count - 1,
            4
        )
        let unpositionedSafePositionToggle =
            #"        setToggle("s3.preflight.after-dark", in: app)"# + "\n" +
                #"        setToggle("s3.preflight.safe-position", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: unpositionedSafePositionToggle
            ).count - 1,
            0
        )

        let unchangedGlobalSetToggleHelper =
            "    @MainActor\n" +
                "    private func setToggle(_ identifier: String, " +
                "in app: XCUIApplication) {\n" +
                "        let toggle = element(identifier, in: app)\n" +
                "        scroll(toggle, in: app)\n" +
                "        XCTAssertEqual(toggle.elementType, .switch)\n" +
                "        assertMinimumGeometry(toggle)\n" +
                #"        if (toggle.value as? String) != "1" {"# + "\n" +
                "            toggle.tap()\n" +
                "        }\n" +
                #"        XCTAssertTrue(wait(for: toggle, predicate: "value == '1'", timeout: 10))"# +
                "\n" +
                "    }"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: unchangedGlobalSetToggleHelper
            ).count - 1,
            1
        )

        let keyboardHelperStart =
            "    @MainActor\n" +
                "    private func dismissKeyboard(in app: XCUIApplication) {"
        let keyboardHelperEnd =
            "\n\n    @MainActor\n" +
                "    private func navigateBack(in app: XCUIApplication) {"
        XCTAssertEqual(
            uiSource.components(separatedBy: keyboardHelperStart).count - 1,
            1
        )
        guard let keyboardHelperStartRange = uiSource.range(of: keyboardHelperStart),
              let keyboardHelperEndRange = uiSource.range(of: keyboardHelperEnd, range: keyboardHelperStartRange.upperBound..<uiSource.endIndex) else {
            XCTFail("Missing the guarded global keyboard helper source slice")
            return
        }
        let keyboardHelperSource = String(uiSource[keyboardHelperStartRange.lowerBound..<keyboardHelperEndRange.lowerBound])
        let keyboardHelperLocks = [
            "let keyboard = app.keyboards.firstMatch",
            "guard keyboard.exists else { return }",
            #"let returnKey = keyboard.buttons["Return"]"#,
            "if returnKey.exists && returnKey.isHittable {",
            "returnKey.tap()",
            #"automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum""#,
            "&& returnKey.exists {",
            "returnKey.elementType == .button",
            #"returnKey.label.lowercased() == "return""#,
            "let expectedKeyboardFrame = CGRect(",
            "x: 0,",
            "y: 451,",
            "width: 375,",
            "height: 216",
            "returnFrame.minX == 281.5",
            "returnFrame.width == 93.5",
            "dx: 0.8753333333333333,",
            "dy: 0.5740740740740741",
            "app.swipeDown()",
            #"predicate: "exists == false""#,
            "timeout: 10",
            "app.state == .runningForeground",
        ]
        for lock in keyboardHelperLocks {
            XCTAssertTrue(keyboardHelperSource.contains(lock), lock)
        }
        XCTAssertEqual(
            keyboardHelperSource.components(separatedBy: "returnKey.tap()").count - 1,
            1
        )
        XCTAssertEqual(
            keyboardHelperSource.components(separatedBy: "app.swipeDown()").count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: "dismissKeyboard(in: app)").count - 1,
            6
        )
        let defaultKeyboardCallerLocks = [
            #"sign.typeText("Monument Sign")"# + "\n" +
                "        dismissKeyboard(in: app)",
            #"site.typeText("North Campus")"# + "\n" +
                "        dismissKeyboard(in: app)\n" +
                "        dismissKeyboard(in: app)",
            "        } else {\n" +
                "            dismissKeyboard(in: app)\n" +
                "        }\n" +
                "        XCTAssertTrue(\n" +
                "            wait(\n" +
                "                for: app.keyboards.firstMatch,",
            #"sign.typeText("Loading Dock Sign")"# + "\n" +
                "        dismissKeyboard(in: app)",
            #"confirmation.typeText("ERASE")"# + "\n" +
                "        dismissKeyboard(in: app)",
        ]
        for lock in defaultKeyboardCallerLocks {
            XCTAssertEqual(uiSource.components(separatedBy: lock).count - 1, 1)
        }
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "dismissMultilineKeyboard(\n            afterEditing:"
            ).count - 1,
            3
        )
        let multilineKeyboardCallerLocks = [
            #"description.typeText("Replaced failed power supply")"# + "\n" +
                "        dismissMultilineKeyboard(\n" +
                "            afterEditing: description,\n" +
                #"            on: element("s5.1.work.screen", in: app),"# + "\n" +
                "            clearedValidation: validation,\n" +
                "            in: app\n" +
                "        )",
            #"description.typeText("Replaced damaged component")"# + "\n" +
                "        dismissMultilineKeyboard(\n" +
                "            afterEditing: description,\n" +
                #"            on: element("s5.1.work.screen", in: app),"# + "\n" +
                "            in: app\n" +
                "        )",
            #"note.typeText("Verified connector label")"# + "\n" +
                "        dismissMultilineKeyboard(\n" +
                "            afterEditing: note,\n" +
                #"            on: element("s4.5.correction.screen", in: app),"# + "\n" +
                "            clearedValidation: validation,\n" +
                "            in: app\n" +
                "        )",
        ]
        for lock in multilineKeyboardCallerLocks {
            XCTAssertEqual(uiSource.components(separatedBy: lock).count - 1, 1, lock)
        }
        let multilineHelperStart =
            "    @MainActor\n" +
                "    private func dismissMultilineKeyboard("
        XCTAssertEqual(
            uiSource.components(separatedBy: multilineHelperStart).count - 1,
            1
        )
        guard let multilineHelperStartRange = uiSource.range(of: multilineHelperStart),
              let multilineKeyboardEndRange = uiSource.range(
                of: keyboardHelperStart,
                range: multilineHelperStartRange.upperBound..<uiSource.endIndex
              ) else {
            XCTFail("Missing the dedicated multiline keyboard helper source slice")
            return
        }
        let multilineHelperSource = String(
            uiSource[multilineHelperStartRange.lowerBound..<multilineKeyboardEndRange.lowerBound]
        )
        let multilineHelperLocks = [
            "afterEditing field: XCUIElement",
            "on route: XCUIElement",
            "clearedValidation: XCUIElement? = nil",
            "if let clearedValidation {",
            #"predicate: "exists == false""#,
            "timeout: 10",
            "let keyboard = app.keyboards.firstMatch",
            "let expectedRouteExists = route.exists",
            "let expectedApplicationState = app.state",
            "field.elementType == .textField",
            "!field.identifier.isEmpty",
            "expectedRouteExists",
            "expectedApplicationState == .runningForeground",
            #"let expectedValue = String(describing: field.value ?? "")"#,
            "let fieldScrollViews = app.scrollViews.containing(",
            ".textField,",
            "identifier: field.identifier",
            "guard fieldScrollViews.count == 1 else {",
            "let fieldScrollView = fieldScrollViews.firstMatch",
            "guard fieldScrollView.exists, fieldScrollView.isHittable else {",
            "fieldScrollView.swipeUp()",
            "keyboard.waitForNonExistence(timeout: 10)",
            #"String(describing: field.value ?? "") == expectedValue"#,
            "route.exists == expectedRouteExists",
            "app.state == expectedApplicationState",
            "Multiline dismissal changed content, route, or foreground state.",
        ]
        for lock in multilineHelperLocks {
            XCTAssertTrue(multilineHelperSource.contains(lock), lock)
        }
        XCTAssertEqual(
            multilineHelperSource.components(separatedBy: "fieldScrollView.swipeUp()").count - 1,
            1
        )
        XCTAssertEqual(
            multilineHelperSource.components(separatedBy: "timeout: 10").count - 1,
            2
        )
        for (fragment, count) in [
            ("field.exists", 2),
            ("route.exists", 2),
            ("app.state", 2),
            ("expectedRouteExists", 3),
            ("expectedApplicationState", 3),
            (#"String(describing: field.value ?? "")"#, 2),
            ("keyboard.waitForNonExistence(timeout: 10)", 1),
            ("fieldScrollViews.count == 1", 1),
        ] {
            XCTAssertEqual(
                multilineHelperSource.components(separatedBy: fragment).count - 1,
                count,
                fragment
            )
        }
        for prohibited in [
            "dismissKeyboard(",
            "app.swipeDown()",
            "returnKeyDismissesKeyboard",
            "returnKey.tap()",
            ".tap()",
        ] {
            XCTAssertFalse(multilineHelperSource.contains(prohibited), prohibited)
        }
        XCTAssertFalse(uiSource.contains("returnKeyDismissesKeyboard"))
        XCTAssertFalse(uiSource.contains("key.exists ? key.tap() : app.swipeDown()"))
        XCTAssertFalse(uiSource.contains("key.exists && key.isHittable ?"))

        let workEditingPositioningStart =
            #"        let workHelperLabel = "Add one optional photo showing the work performed.""#
        let workEditingPositioningEnd =
            #"        captureBaseline("state.work.editing", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: workEditingPositioningStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: workEditingPositioningEnd).count - 1,
            1
        )
        guard let workEditingPositioningStartRange = uiSource.range(
            of: workEditingPositioningStart
        ), let workEditingPositioningEndRange = uiSource.range(
            of: workEditingPositioningEnd,
            range: workEditingPositioningStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded Record-work editing positioning slice")
            return
        }
        let workEditingPositioningSource = String(
            uiSource[
                workEditingPositioningStartRange.lowerBound..<workEditingPositioningEndRange.upperBound
            ]
        )
        let workEditingBindingGuard =
            "        let workHelperTexts = app.staticTexts.matching(\n" +
                #"            NSPredicate(format: "label == %@", workHelperLabel)"# + "\n" +
                "        )\n" +
                "        let workScrollViews = app.scrollViews.containing(\n" +
                "            .image,\n" +
                #"            identifier: "s5.1.work.photo""# + "\n" +
                "        )\n" +
                "        let workNavigationBars = app.navigationBars.matching(\n" +
                #"            identifier: "Record work""# + "\n" +
                "        )\n" +
                "        guard workHelperTexts.count == 1,\n" +
                "              workScrollViews.count == 1,\n" +
                "              workNavigationBars.count == 1 else {\n" +
                #"            XCTFail("Record-work editing positioning bindings are ambiguous.")"# + "\n" +
                "            return\n" +
                "        }\n" +
                "        let workHelper = workHelperTexts.firstMatch\n" +
                "        let workScrollView = workScrollViews.firstMatch\n" +
                "        let workNavigationBar = workNavigationBars.firstMatch\n" +
                "        guard workHelper.exists,\n" +
                "              workScrollView.exists,\n" +
                "              workNavigationBar.exists else {\n" +
                #"            XCTFail("Record-work editing positioning bindings are missing.")"# + "\n" +
                "            return\n" +
                "        }\n" +
                "        let verticalInset: CGFloat = 16\n" +
                "        let receiverInset: CGFloat = 24\n" +
                "        let minimumGestureDistance: CGFloat = 44"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingBindingGuard
            ).count - 1,
            1
        )
        let workEditingLiveGeometry =
            "            let scrollFrame = workScrollView.frame\n" +
                "            let applicationFrame = app.frame\n" +
                "            let navigationFrame = workNavigationBar.frame\n" +
                "            let liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                "            let safeTop = max(\n" +
                "                liveScrollFrame.minY,\n" +
                "                navigationFrame.maxY\n" +
                "            ) + verticalInset\n" +
                "            let safeBottom = liveScrollFrame.maxY - verticalInset\n" +
                "            let receiverTop = max(\n" +
                "                liveScrollFrame.minY,\n" +
                "                navigationFrame.maxY\n" +
                "            ) + receiverInset\n" +
                "            let receiverBottom = liveScrollFrame.maxY - receiverInset\n" +
                "            let helperFrame = workHelper.frame"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingLiveGeometry
            ).count - 1,
            1
        )
        let workEditingPositiveInterval =
            "            let minimumShift = safeTop - helperFrame.minY\n" +
                "            let maximumShift = safeBottom - helperFrame.maxY\n" +
                "            let receiverCapacity = receiverBottom - receiverTop\n" +
                "            let recognizedMinimum = max(\n" +
                "                minimumShift,\n" +
                "                minimumGestureDistance\n" +
                "            )\n" +
                "            let recognizedMaximum = min(\n" +
                "                maximumShift,\n" +
                "                receiverCapacity\n" +
                "            )\n" +
                "            guard minimumShift > 0,\n" +
                "                  minimumShift <= maximumShift,\n" +
                "                  receiverCapacity >= minimumGestureDistance,\n" +
                "                  recognizedMinimum <= recognizedMaximum else {\n" +
                #"                XCTFail("Record-work editing has no feasible downward correction.")"# + "\n" +
                "                return\n" +
                "            }\n" +
                "            let dragDistance = recognizedMinimum"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingPositiveInterval
            ).count - 1,
            1
        )
        let workEditingDirectGesture =
            "            let scrollOrigin = workScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )\n" +
                "            let dragStart = scrollOrigin.withOffset(\n" +
                "                CGVector(\n" +
                "                    dx: scrollFrame.width / 2,\n" +
                "                    dy: receiverTop - scrollFrame.minY\n" +
                "                )\n" +
                "            )\n" +
                "            let dragEnd = dragStart.withOffset(\n" +
                "                CGVector(dx: 0, dy: dragDistance)\n" +
                "            )\n" +
                "            let helperMinYBeforeDrag = helperFrame.minY\n" +
                "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingDirectGesture
            ).count - 1,
            1
        )
        let workEditingFinalGuardAndCapture =
            "        guard app.state == .runningForeground,\n" +
                "              workHelperTexts.count == 1,\n" +
                "              workScrollViews.count == 1,\n" +
                "              workNavigationBars.count == 1,\n" +
                "              workHelper.exists,\n" +
                "              workScrollView.exists,\n" +
                "              workNavigationBar.exists,\n" +
                "              workPreview.exists,\n" +
                "              !finalApplicationFrame.isNull,\n" +
                "              !finalApplicationFrame.isEmpty,\n" +
                "              !finalNavigationFrame.isNull,\n" +
                "              !finalNavigationFrame.isEmpty,\n" +
                "              !finalScrollFrame.isNull,\n" +
                "              !finalScrollFrame.isEmpty,\n" +
                "              !finalHelperFrame.isNull,\n" +
                "              !finalHelperFrame.isEmpty,\n" +
                "              finalHelperFrame.minY >= finalSafeTop,\n" +
                "              finalHelperFrame.maxY <= finalSafeBottom,\n" +
                "              workHelper.isHittable,\n" +
                "              workPreview.isHittable else {\n" +
                #"            XCTFail("Record-work editing composition is outside the safe viewport.")"# + "\n" +
                "            return\n" +
                "        }\n" +
                #"        captureBaseline("state.work.editing", in: app)"#
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingFinalGuardAndCapture
            ).count - 1,
            1
        )
        for (workEditingLock, count) in [
            ("        for _ in 0..<4 {", 1),
            ("            guard app.state == .runningForeground,", 1),
            ("            let scrollFrame = workScrollView.frame", 1),
            ("            let liveScrollFrame = scrollFrame.intersection(applicationFrame)", 1),
            ("                  safeBottom > safeTop,", 1),
            ("                  helperFrame.height <= safeBottom - safeTop else {", 1),
            ("            if helperFrame.minY >= safeTop,", 1),
            ("               helperFrame.maxY <= safeBottom,", 1),
            ("               workHelper.isHittable {", 1),
            ("                  workHelper.frame.minY > helperMinYBeforeDrag else {", 1),
            ("        let finalScrollFrame = workScrollView.frame.intersection(", 1),
            ("        let finalSafeTop = max(", 1),
            ("        let finalSafeBottom = finalScrollFrame.maxY - verticalInset", 1),
            ("        let finalHelperFrame = workHelper.frame", 1),
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingLock
                ).count - 1,
                count,
                workEditingLock
            )
        }
        for (workEditingCardinalityLock, count) in [
            ("workHelperTexts.count == 1", 4),
            ("workScrollViews.count == 1", 4),
            ("workNavigationBars.count == 1", 4),
            ("workHelper.exists", 4),
            ("workScrollView.exists", 3),
            ("workNavigationBar.exists", 3),
            ("workPreview.exists", 2),
            ("workPreview.isHittable", 1),
            ("app.state == .runningForeground", 2),
            ("workScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingCardinalityLock
                ).count - 1,
                count,
                workEditingCardinalityLock
            )
        }
        let workEditingCaptureThenSave =
            workEditingPositioningEnd + "\n\n" +
                "        scroll(saveWork, in: app)"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: workEditingCaptureThenSave
            ).count - 1,
            1
        )
        for staleWorkEditingPositioningForm in [
            "dateLabel",
            #"app.staticTexts["Date"]"#,
            "app.swipeUp()",
            "app.swipeDown()",
            "workScrollView.swipeUp()",
            "workScrollView.swipeDown()",
            "app.coordinate(",
            "CGRect(",
            "Thread.sleep",
            "epsilon",
            "tolerance",
        ] {
            XCTAssertFalse(
                workEditingPositioningSource.contains(
                    staleWorkEditingPositioningForm
                ),
                staleWorkEditingPositioningForm
            )
        }

        let firstReportPreviewPositioning =
            #"        let preview = element("s4.3.report-detail.preview", in: app)"# +
                "\n" +
                "        XCTAssertTrue(preview.waitForExistence(timeout: 20))\n" +
                #"        if automationShard?.shardID == "s10.4.current.ax-text" {"# +
                "\n" +
                "            guard scrollReportPreviewForAXText(preview, in: app) else { return }\n" +
                "        } else {\n" +
                "            scroll(preview, in: app)\n" +
                "        }\n" +
                "        XCTAssertTrue(preview.isHittable)\n" +
                #"        captureBaseline("state.report-detail.ready", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: firstReportPreviewPositioning).count - 1,
            1
        )
        for restoredReportDetailRoute in [
            "        assertFirstReceiptAndReport(in: app)",
            "    private func assertFirstReceiptAndReport(in app: XCUIApplication) {",
            "            guard scrollReportPreviewForAXText(preview, in: app) else { return }",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: restoredReportDetailRoute
                ).count - 1,
                1,
                restoredReportDetailRoute
            )
        }
        let removedReportDetailDiagnosticFragments = [
            "diagnoseAXTextReportDetailRoute",
            "S10_4_REPORT_DETAIL_ROUTE_DIAGNOSTIC",
            "S10.4 AX-text report-detail route diagnostic",
            "receiptScreenQuery",
            "receiptViewReportQuery",
            "reportScreenQuery",
            "reportPreviewQuery",
            "reportScrollViewsQuery",
            "tabBarsQuery",
            "pageIndicatorsQuery",
            "scheduledOffsetMilliseconds",
            "Thread.sleep(forTimeInterval: 0.25)",
        ]
        for fragment in removedReportDetailDiagnosticFragments {
            XCTAssertEqual(
                uiSource.components(separatedBy: fragment).count - 1,
                0,
                fragment
            )
        }
        for removedThrowingReportDetailRoute in [
            "try assertFirstReceiptAndReport(in: app)",
            "private func assertFirstReceiptAndReport(in app: XCUIApplication) throws {",
            "try diagnoseAXTextReportDetailRoute(preview, in: app)",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedThrowingReportDetailRoute
                ).count - 1,
                0,
                removedThrowingReportDetailRoute
            )
        }
        let reportDetailDiagnosticGapStart =
            "    @MainActor\n" +
                "    private func scroll(_ value: XCUIElement, in app: XCUIApplication) {"
        let reportDetailDiagnosticGapEnd =
            "\n\n    @MainActor\n" +
                "    private func scrollReportPreviewForAXText("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reportDetailDiagnosticGapStart
            ).count - 1,
            1
        )
        guard let reportDetailDiagnosticGapStartRange = uiSource.range(
            of: reportDetailDiagnosticGapStart
        ), let reportDetailDiagnosticGapEndRange = uiSource.range(
            of: reportDetailDiagnosticGapEnd,
            range: reportDetailDiagnosticGapStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the restored diagnostic-free report-detail helper gap")
            return
        }
        let reportDetailDiagnosticGapSource = String(
            uiSource[
                reportDetailDiagnosticGapStartRange.lowerBound..<reportDetailDiagnosticGapEndRange.lowerBound
            ]
        )
        for removedDiagnosticMechanism in [
            "printJSONLine(",
            "XCTAttachment(",
            "XCUIScreen.main.screenshot()",
            "app.debugDescription",
            ".lifetime = .keepAlways",
            "throw AutomationConfigurationError.invalid(",
            "for ordinal in",
            "query.count",
            "query.element(boundBy:",
        ] {
            XCTAssertEqual(
                reportDetailDiagnosticGapSource.components(
                    separatedBy: removedDiagnosticMechanism
                ).count - 1,
                0,
                removedDiagnosticMechanism
            )
        }

        let axPreviewHelperStart =
            "    @MainActor\n" +
                "    private func scrollReportPreviewForAXText("
        let axPreviewHelperEnd =
            "\n\n    @MainActor\n" +
                "    private func scrollDown(_ value: XCUIElement, in app: XCUIApplication) {"
        XCTAssertEqual(
            uiSource.components(separatedBy: axPreviewHelperStart).count - 1,
            1
        )
        guard let axPreviewHelperStartRange = uiSource.range(of: axPreviewHelperStart),
              let axPreviewHelperEndRange = uiSource.range(of: axPreviewHelperEnd, range: axPreviewHelperStartRange.upperBound..<uiSource.endIndex) else {
            XCTFail("Missing the AX-text report-preview helper source slice")
            return
        }
        let axPreviewHelperSource = String(uiSource[axPreviewHelperStartRange.lowerBound..<axPreviewHelperEndRange.lowerBound])
        let axPreviewHelperLocks = [
            #"app.scrollViews.containing("#,
            ".other,",
            #"identifier: "s4.3.report-detail.preview""#,
            "guard reportScrollViews.count == 1 else {",
            "let reportScroll = reportScrollViews.firstMatch",
            "guard reportScroll.waitForExistence(timeout: 10) else {",
            "let navigationBars = app.navigationBars",
            "guard navigationBars.count == 1 else {",
            "let navigationBar = navigationBars.firstMatch",
            "let pageIndicators = app.descendants(matching: .other).matching(",
            "format: \"label == %@\"",
            "\"Vertical scroll bar, 4 pages\"",
            "func currentIndicatorGeometry(",
            "previewFrame: CGRect,",
            "liveScrollFrame: CGRect",
            "guard pageIndicators.count == 2 else { return nil }",
            "let indicators = (0..<2).map {",
            "pageIndicators.element(boundBy: $0)",
            #"let frames = indicators.map(\.frame)"#,
            #"indicators.allSatisfy(\.exists)"#,
            "frames.allSatisfy({ !$0.isNull && !$0.isEmpty })",
            "guard frames[0] != frames[1] else { return nil }",
            "let innerCandidates = frames.indices.filter {",
            "previewFrame.contains(frames[$0])",
            "guard innerCandidates.count == 1 else { return nil }",
            "let innerIndex = innerCandidates[0]",
            "let outerCandidates = frames.indices.filter {",
            "$0 != innerIndex",
            "&& liveScrollFrame.contains(frames[$0])",
            "guard outerCandidates.count == 1 else { return nil }",
            "return (frames[outerCandidates[0]], frames[innerIndex])",
            "let verticalInset: CGFloat = 24",
            "let horizontalInset: CGFloat = 24",
            "let minimumGestureDistance: CGFloat = 44",
            "for _ in 0..<4 {",
            "let reportScrollFrame = reportScroll.frame",
            "let liveScrollFrame = reportScrollFrame.intersection(app.frame)",
            "let previewFrame = preview.frame",
            "let indicators = currentIndicatorGeometry(",
            "previewFrame: previewFrame,",
            "liveScrollFrame: liveScrollFrame",
            "if preview.isHittable { return true }",
            "navigationBar.frame.maxY",
            "let safeBottom = min(",
            "indicators.outer.maxY",
            "let safeLeft = liveScrollFrame.minX + horizontalInset",
            "let safeRight = liveScrollFrame.maxX - horizontalInset",
            "let maximumGestureDistance = safeBottom - safeTop",
            "app.state == .runningForeground",
            "reportScrollViews.count == 1",
            "navigationBars.count == 1",
            "!liveScrollFrame.isNull",
            "!liveScrollFrame.isEmpty",
            "safeRight > safeLeft",
            "maximumGestureDistance >= minimumGestureDistance",
            "previewFrame.height <= maximumGestureDistance",
            "let minimumShift = safeTop - previewFrame.minY",
            "let maximumShift = safeBottom - previewFrame.maxY",
            "guard minimumShift <= maximumShift else {",
            "let recognizedMinimum = max(",
            "-maximumGestureDistance",
            "let recognizedMaximum = min(",
            "-minimumGestureDistance",
            "if recognizedMinimum <= recognizedMaximum {",
            "dragDistance = recognizedMaximum",
            "else if maximumShift < -maximumGestureDistance {",
            "dragDistance = -maximumGestureDistance",
            "AX-text report preview has no progressive or final upward shift.",
            "let previousPreviewMinY = previewFrame.minY",
            "let reportScrollOrigin = reportScroll.coordinate(",
            "withNormalizedOffset: CGVector(dx: 0, dy: 0)",
            "dx: liveScrollFrame.midX - reportScrollFrame.minX",
            "dy: safeBottom - reportScrollFrame.minY",
            "forDuration: 0.2,",
            "withVelocity: .slow,",
            "thenHoldForDuration: 0.2",
            "pageIndicators.count == 2,",
            "preview.frame.minY < previousPreviewMinY else {",
            "let finalLiveScrollFrame = reportScroll.frame.intersection(app.frame)",
            "previewFrame: preview.frame,",
            "liveScrollFrame: finalLiveScrollFrame",
            "preview.isHittable else {",
            "AX-text report preview remained nonhittable after four gestures.",
        ]
        for lock in axPreviewHelperLocks {
            XCTAssertTrue(axPreviewHelperSource.contains(lock), lock)
        }
        XCTAssertEqual(
            axPreviewHelperSource.components(separatedBy: "reportScroll.coordinate(").count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(separatedBy: "dragStart.press(").count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(separatedBy: "for _ in 0..<4 {").count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(
                separatedBy: #""Vertical scroll bar, 4 pages""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(
                separatedBy: "let indicators = (0..<2).map {"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(
                separatedBy: "pageIndicators.count == 2"
            ).count - 1,
            3
        )
        for uniqueTwoNodeDerivation in [
            "pageIndicators.element(boundBy: $0)",
            #"let frames = indicators.map(\.frame)"#,
            #"indicators.allSatisfy(\.exists)"#,
            "guard frames[0] != frames[1] else { return nil }",
            "let innerCandidates = frames.indices.filter {",
            "previewFrame.contains(frames[$0])",
            "let innerIndex = innerCandidates[0]",
            "let outerCandidates = frames.indices.filter {",
            "$0 != innerIndex",
            "&& liveScrollFrame.contains(frames[$0])",
            "return (frames[outerCandidates[0]], frames[innerIndex])",
        ] {
            XCTAssertEqual(
                axPreviewHelperSource.components(
                    separatedBy: uniqueTwoNodeDerivation
                ).count - 1,
                1,
                uniqueTwoNodeDerivation
            )
        }
        XCTAssertEqual(
            axPreviewHelperSource.components(
                separatedBy: "currentIndicatorGeometry("
            ).count - 1,
            3
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(
                separatedBy: "dragDistance = recognizedMaximum"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(
                separatedBy: "dragDistance = -maximumGestureDistance"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(separatedBy: "XCTFail(").count - 1,
            9
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(separatedBy: "return false").count - 1,
            9
        )
        XCTAssertEqual(
            axPreviewHelperSource.components(separatedBy: "return true").count - 1,
            2
        )
        for staleIndicatorAssumption in [
            "pageIndicators.count == 4",
            "let frames = (0..<4).map {",
            "var distinctFrames: [CGRect] = []",
            "distinctFrames.contains",
            "distinctFrames.append",
            "distinctFrames.count == 2",
            "frames.filter { $0 == distinctFrame }.count == 2",
            "CGRect(",
            "CGRect(x:",
            "1085.1666666666665",
            "1085.6666666666665",
            "370.00000000000006",
        ] {
            XCTAssertFalse(
                axPreviewHelperSource.contains(staleIndicatorAssumption),
                staleIndicatorAssumption
            )
        }
        XCTAssertFalse(axPreviewHelperSource.contains("reportScroll.swipeUp()"))
        XCTAssertFalse(axPreviewHelperSource.contains("app.swipeUp()"))
        XCTAssertFalse(axPreviewHelperSource.contains("app.swipeDown()"))
        XCTAssertFalse(axPreviewHelperSource.contains("app.tabBars"))
        XCTAssertFalse(axPreviewHelperSource.contains("CGVector(dx: 0.01"))
        XCTAssertFalse(axPreviewHelperSource.contains("upperPadding"))
        XCTAssertFalse(axPreviewHelperSource.contains("lowerPadding"))
        XCTAssertFalse(axPreviewHelperSource.contains("Set<CGRect>"))
        XCTAssertFalse(axPreviewHelperSource.contains("Set(frames)"))
        XCTAssertFalse(axPreviewHelperSource.contains(".scrollBar"))
        XCTAssertFalse(axPreviewHelperSource.contains(".scrollBars"))
        XCTAssertFalse(axPreviewHelperSource.contains("CGRect(x:"))
        XCTAssertFalse(axPreviewHelperSource.contains("Thread.sleep"))
        XCTAssertFalse(axPreviewHelperSource.contains("let safeBottom = liveScrollFrame.maxY - verticalInset"))
        XCTAssertFalse(axPreviewHelperSource.contains("guard maximumShift < 0 else {"))
        XCTAssertFalse(axPreviewHelperSource.contains("guard recognizedMinimum <= recognizedMaximum else {"))
        XCTAssertFalse(axPreviewHelperSource.contains(#"app.scrollViews.matching("#))
        XCTAssertFalse(
            axPreviewHelperSource.contains(
                #"identifier: "s4.3.report-detail.screen""#
            )
        )

        let diagnosticsPositioningStart =
            #"        let diagnosticsHeading = element("s8.3.diagnostics.heading", in: app)"#
        let diagnosticsPositioningEnd =
            #"        captureBaseline("state.diagnostics.ready", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: diagnosticsPositioningStart).count - 1,
            1
        )
        guard let diagnosticsPositioningStartRange = uiSource.range(of: diagnosticsPositioningStart),
              let diagnosticsPositioningEndRange = uiSource.range(of: diagnosticsPositioningEnd, range: diagnosticsPositioningStartRange.upperBound..<uiSource.endIndex) else {
            XCTFail("Missing the diagnostics positioning source slice")
            return
        }
        let diagnosticsPositioningSource = String(uiSource[diagnosticsPositioningStartRange.lowerBound..<diagnosticsPositioningEndRange.lowerBound])
        let diagnosticsRouteLocks = [
            #"app.scrollViews.containing("#,
            ".staticText,",
            #"identifier: "s8.3.diagnostics.heading""#,
            "guard diagnosticsScrollViews.count == 1 else {",
            "let diagnosticsScrollView = diagnosticsScrollViews.firstMatch",
            "guard diagnosticsScrollView.waitForExistence(timeout: 10) else {",
        ]
        for lock in diagnosticsRouteLocks {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertFalse(
            diagnosticsPositioningSource.contains(
                #"        if automationShard?.shardID == "s10.4.current.increased-contrast" {"#
            )
        )
        for (diagnosticsResidualForm, expectedCount) in [
            ("diagnoseIncreasedContrastDiagnosticsPositioning", 0),
            ("S10_4_INCREASED_CONTRAST_DIAGNOSTICS_POSITIONING", 0),
            ("XCTAttachment(", 0),
            ("XCUIScreen.main.screenshot()", 0),
            ("XCTAttachment(string: app.debugDescription)", 0),
            (".lifetime = .keepAlways", 0),
            ("throw AutomationConfigurationError.invalid(", 0),
            ("S10.4 increased-contrast Diagnostics positioning diagnostic", 0),
            ("for _ in 0..<2 {", 0),
            ("var measuredUndertravel: CGFloat = 0", 0),
            ("var correctionDirection: CGFloat?", 0),
            ("var previousResidualMagnitude: CGFloat?", 0),
            ("let targetDistance: CGFloat", 0),
            ("let requestedDistance = targetDistance", 0),
            ("Diagnostics positioning changed correction direction.", 0),
            ("Diagnostics positioning residual did not decrease.", 0),
        ] {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: diagnosticsResidualForm
                ).count - 1,
                expectedCount,
                diagnosticsResidualForm
            )
        }
        let diagnosticsResidualSetup =
            "        let topClearance: CGFloat = 12\n" +
                "        let bottomClearance: CGFloat = 16\n" +
                "        let minimumGestureDistance: CGFloat = 44\n" +
                "        let dragInset: CGFloat = 24\n" +
                "        var upwardUndertravel: CGFloat = 0\n" +
                "        var downwardUndertravel: CGFloat = 0\n" +
                "        var stagingCount = 0\n" +
                "        var stagedFinalDirection: CGFloat?"
        XCTAssertEqual(
            diagnosticsPositioningSource.components(
                separatedBy: diagnosticsResidualSetup
            ).count - 1,
            1
        )
        let diagnosticsResidualLoopFragments = [
            "        for _ in 0..<6 {",
            "            let requiredFinalDirection: CGFloat",
            "            if let stagedFinalDirection,",
            "               stagedFinalDirection != requiredFinalDirection {",
            "            let dragStart = diagnosticsScrollView.coordinate(",
            "                withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45)",
            "            let startPoint = dragStart.screenPoint",
            "            let upwardCapacity = startPoint.y",
            "            let downwardCapacity = diagnosticsScrollView.frame.maxY",
            "                        recognizedMaximum - upwardUndertravel",
            "                        recognizedMinimum + downwardUndertravel",
            "                        2 * minimumGestureDistance + downwardUndertravel",
            "                        2 * minimumGestureDistance + upwardUndertravel",
            "                    dragDistance = -stagingDistance",
            "                stagingCount += 1",
            "                if stagedFinalDirection == nil {",
            "                    stagedFinalDirection = requiredFinalDirection",
            "            guard (dragDistance < 0 ? upwardCapacity : downwardCapacity)",
            "            let dragEnd = dragStart.withOffset(",
            "            dragStart.press(",
            "                forDuration: 0.2,",
            "                withVelocity: .slow,",
            "                thenHoldForDuration: 0.2",
            "            guard actualDistance * dragDistance > 0 else {",
            "            let observedUndertravel = max(",
            "                upwardUndertravel = observedUndertravel",
            "                downwardUndertravel = observedUndertravel",
        ]
        for fragment in diagnosticsResidualLoopFragments {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: fragment
                ).count - 1,
                1,
                fragment
            )
        }
        for (fragment, expectedCount) in [
            ("for _ in 0..<6 {", 1),
            ("stagingCount < 2", 2),
            ("let stagingDistance = min(", 2),
            ("isStaging = true", 2),
            ("diagnosticsScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
            ("XCTFail(", 13),
            ("return", 13),
        ] {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: fragment
                ).count - 1,
                expectedCount,
                fragment
            )
        }

        let diagnosticsFinalShiftComputation =
            "        let finalMinimumShift = navigationBar.frame.maxY\n" +
                "            + topClearance\n" +
                "            - diagnosticsAuthority.frame.minY\n" +
                "        let finalMaximumShift = min(\n" +
                "            navigationBar.frame.maxY - diagnosticsHeading.frame.maxY,\n" +
                "            signsTab.frame.minY\n" +
                "                - bottomClearance\n" +
                "                - diagnosticsExport.frame.maxY\n" +
                "        )"
        XCTAssertEqual(
            diagnosticsPositioningSource.components(
                separatedBy: diagnosticsFinalShiftComputation
            ).count - 1,
            1
        )
        let removedDiagnosticsTelemetryFragments = [
            "S10_4_DIAGNOSTICS_POSITIONING_TELEMETRY",
            "diagnoseDefaultLightPositioning",
            "frameObject",
            "pointObject",
            "printJSONLine(",
            "XCTAttachment(",
            "XCUIScreen.main.screenshot()",
            "XCTAttachment(string: app.debugDescription)",
            ".lifetime = .keepAlways",
            "throw AutomationConfigurationError.invalid(",
            "S10.4 default-light Diagnostics positioning telemetry completed nonaccepting",
            "S10.4 default-light Diagnostics telemetry pre app",
            "S10.4 default-light Diagnostics telemetry pre accessibility tree",
            "S10.4 default-light Diagnostics telemetry post app",
            "S10.4 default-light Diagnostics telemetry post accessibility tree",
        ]
        for removedTelemetry in removedDiagnosticsTelemetryFragments {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: removedTelemetry
                ).count - 1,
                0,
                removedTelemetry
            )
        }
        for acceptingEmitter in [
            "assertMigrationStateCoverage",
            "emitAutomatedLabAccessibilityRowsIfNeeded",
            "performAccessibilityAudit",
            "eligibleExceptions",
            "S10_MIGRATION_STATE",
            "S10_4_AX_STATE",
            "S10_4_CONTRAST",
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "automatedEvidenceIDs.append",
            "automationAXTreeDigests",
            "automationContrastExceptions",
            "add(candidate)",
            "receipt",
            "retention",
        ] {
            XCTAssertFalse(
                diagnosticsPositioningSource.contains(acceptingEmitter),
                acceptingEmitter
            )
        }
        let diagnosticsFinalGeometryAndCapture =
            "        guard finalMinimumShift <= 0, finalMaximumShift >= 0 else {\n" +
                "            XCTFail(\"Diagnostics positioning exhausted its bounded strategy.\")\n" +
                "            return\n" +
                "        }\n" +
                "        XCTAssertLessThanOrEqual(\n" +
                "            diagnosticsHeading.frame.maxY,\n" +
                "            navigationBar.frame.maxY\n" +
                "        )\n" +
                "        XCTAssertGreaterThanOrEqual(\n" +
                "            diagnosticsAuthority.frame.minY,\n" +
                "            navigationBar.frame.maxY + topClearance\n" +
                "        )\n" +
                "        XCTAssertLessThanOrEqual(\n" +
                "            diagnosticsExport.frame.maxY,\n" +
                "            signsTab.frame.minY - bottomClearance\n" +
                "        )\n" +
                #"        captureBaseline("state.diagnostics.ready", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: diagnosticsFinalGeometryAndCapture
            ).count - 1,
            1
        )

        let removedDefaultLightPositioningFragments = [
            #"        if automationShard?.shardID == "s10.4.current.default-light" {"#,
            "try diagnoseDefaultLightDiagnosticsPositioning(in: app)",
            "diagnoseDefaultLightDiagnosticsPositioning",
            "S10_4_DIAGNOSTICS_POSITIONING_DIAGNOSTIC",
            "XCTAttachment(",
            "XCUIScreen.main.screenshot()",
            "XCTAttachment(string: app.debugDescription)",
            ".lifetime = .keepAlways",
            "throw AutomationConfigurationError.invalid(",
            "S10.4 default-light Diagnostics positioning diagnostic",
        ]
        for removedTelemetry in removedDefaultLightPositioningFragments {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: removedTelemetry
                ).count - 1,
                0,
                removedTelemetry
            )
        }
        XCTAssertFalse(
            diagnosticsPositioningSource.contains(
                #"        if automationShard?.shardID == "s10.4.current.default-light" {"#
            )
        )
        let initialStoreKitSetup =
            "        storeKitSession = try SKTestSession(contentsOf: fixtureURL)\n" +
                "        storeKitSession?.resetToDefaultState()\n" +
                "        storeKitSession?.clearTransactions()\n" +
                "        storeKitSession?.disableDialogs = true"
        XCTAssertEqual(
            uiSource.components(separatedBy: initialStoreKitSetup).count - 1,
            1
        )
        XCTAssertFalse(
            uiSource.contains("        let session = try SKTestSession(contentsOf: fixtureURL)")
        )
        XCTAssertFalse(uiSource.contains("        storeKitSession = session"))
        let purchaseRecoveryStart =
            #"        var purchase = firstPurchaseButton(in: app)"# + "\n" +
                "        scroll(purchase, in: app)\n" +
                "        purchase.tap()\n" +
                #"        var purchaseState = element("s7.2.paywall.purchase-state", in: app)"#
        let purchaseRecoveryEnd =
            #"        let terms = element("s7.2.paywall.terms", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: purchaseRecoveryStart).count - 1,
            1
        )
        guard let purchaseRecoveryStartRange = uiSource.range(of: purchaseRecoveryStart),
              let purchaseRecoveryEndRange = uiSource.range(
                of: purchaseRecoveryEnd,
                range: purchaseRecoveryStartRange.upperBound..<uiSource.endIndex
              ) else {
            XCTFail("Missing the bounded StoreKit purchase recovery source slice")
            return
        }
        let purchaseRecoverySource = String(
            uiSource[
                purchaseRecoveryStartRange.lowerBound..<purchaseRecoveryEndRange.lowerBound
            ]
        )
        let unverifiedRetryStart =
            "            if purchaseState.label == unverifiedPurchaseLabel {"
        let unverifiedRetryEnd =
            "            }\n" +
                "        }\n" +
                "        waitForLocalizedLabel("
        guard let unverifiedRetryStartRange = purchaseRecoverySource.range(
            of: unverifiedRetryStart
        ),
        let unverifiedRetryEndRange = purchaseRecoverySource.range(
            of: unverifiedRetryEnd,
            range: unverifiedRetryStartRange.upperBound..<purchaseRecoverySource.endIndex
        ) else {
            XCTFail("Missing the exact unverified-only StoreKit retry slice")
            return
        }
        let unverifiedRetrySource = String(
            purchaseRecoverySource[
                unverifiedRetryStartRange.lowerBound..<unverifiedRetryEndRange.lowerBound
            ]
        )
        let purchaseRecoveryPrefix = String(
            purchaseRecoverySource[
                purchaseRecoverySource.startIndex..<unverifiedRetryStartRange.lowerBound
            ]
        )
        let purchaseRecoverySuffix = String(
            purchaseRecoverySource[
                unverifiedRetryEndRange.lowerBound..<purchaseRecoverySource.endIndex
            ]
        )
        let terminalPurchasePredicate =
            "            let verifiedPurchaseLabel =\n" +
                "                \"Complete: Purchase verified. " +
                "Subscription access is ready.\"\n" +
                "            let unverifiedPurchaseLabel =\n" +
                "                \"Purchase couldn’t be verified. Your existing data is " +
                "still available. Try again.\"\n" +
                "            let terminalPurchaseExpectation = XCTNSPredicateExpectation(\n" +
                "                predicate: NSPredicate(\n" +
                "                    format: \"label == %@ OR label == %@\",\n" +
                "                    verifiedPurchaseLabel,\n" +
                "                    unverifiedPurchaseLabel\n" +
                "                ),\n" +
                "                object: purchaseState\n" +
                "            )\n" +
                "            XCTAssertEqual(\n" +
                "                XCTWaiter.wait(\n" +
                "                    for: [terminalPurchaseExpectation],\n" +
                "                    timeout: 45\n" +
                "                ),\n" +
                "                .completed\n" +
                "            )"
        XCTAssertEqual(
            purchaseRecoverySource.components(
                separatedBy: terminalPurchasePredicate
            ).count - 1,
            1
        )
        let finalVerifiedPurchaseWait =
            "        waitForLocalizedLabel(\n" +
                "            purchaseState,\n" +
                "            containing: \"Purchase verified. " +
                "Subscription access is ready.\",\n" +
                "            timeout: 45\n" +
                "        )"
        XCTAssertEqual(
            purchaseRecoverySuffix.components(
                separatedBy: finalVerifiedPurchaseWait
            ).count - 1,
            1
        )
        let mutablePurchaseBindings = [
            #"        var store = element("s7.2.paywall.store", in: app)"#,
            #"        var purchase = firstPurchaseButton(in: app)"#,
            #"        var purchaseState = element("s7.2.paywall.purchase-state", in: app)"#,
        ]
        for binding in mutablePurchaseBindings {
            XCTAssertEqual(
                uiSource.components(separatedBy: binding).count - 1,
                1,
                binding
            )
        }
        let exactRetryLocks = [
            unverifiedRetryStart,
            "                app.terminate()",
            "                storeKitSession = nil",
            #"                guard let fixtureURL = Bundle(for: Self.self).url("#,
            #"                    forResource: "FieldEvidence","#,
            #"                    withExtension: "storekit""#,
            "                ) else {",
            #"                    XCTFail("The checked-in StoreKit fixture is required")"#,
            #"                guard let freshSession = try? SKTestSession(contentsOf: fixtureURL) else {"#,
            #"                    XCTFail("A fresh StoreKit test session is required")"#,
            "                storeKitSession = freshSession",
            "                freshSession.resetToDefaultState()",
            "                freshSession.clearTransactions()",
            "                freshSession.disableDialogs = true",
            "                app.launch()",
            #"                XCTAssertTrue(element("s2.sign-detail.screen", in: app)"#,
            #"                let retrySettings = element("s1.settings.button", in: app)"#,
            #"                assertControl(retrySettings, label: "Settings")"#,
            "                retrySettings.tap()",
            #"                XCTAssertTrue(element("s1.settings.screen", in: app)"#,
            #"                let retryPaywall = element("s7.2.settings.paywall", in: app)"#,
            "                scroll(retryPaywall, in: app)",
            #"                assertControl(retryPaywall, label: "View subscription")"#,
            "                retryPaywall.tap()",
            #"                XCTAssertTrue(element("s7.2.paywall.screen", in: app)"#,
            "                usedSettingsRetry = true",
            #"                store = element("s7.2.paywall.store", in: app)"#,
            "                XCTAssertTrue(store.waitForExistence(timeout: 30))",
            #"                    predicate: "value == 'Ready'","#,
            "                XCTAssertTrue(store.isEnabled)",
            "                purchase = firstPurchaseButton(in: app)",
            "                scroll(purchase, in: app)",
            "                XCTAssertTrue(purchase.waitForExistence(timeout: 20))",
            "                XCTAssertTrue(purchase.isEnabled)",
            "                XCTAssertTrue(purchase.isHittable)",
            "                purchase.tap()",
            #"                purchaseState = element("s7.2.paywall.purchase-state", in: app)"#,
        ]
        for lock in exactRetryLocks {
            XCTAssertEqual(
                unverifiedRetrySource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let retryStoreKitResetAndRelaunch =
            "                app.terminate()\n" +
                "                storeKitSession = nil\n" +
                #"                guard let fixtureURL = Bundle(for: Self.self).url("# + "\n" +
                #"                    forResource: "FieldEvidence","# + "\n" +
                #"                    withExtension: "storekit""# + "\n" +
                "                ) else {\n" +
                #"                    XCTFail("The checked-in StoreKit fixture is required")"# + "\n" +
                "                    return usedSettingsRetry\n" +
                "                }\n" +
                #"                guard let freshSession = try? SKTestSession(contentsOf: fixtureURL) else {"# + "\n" +
                #"                    XCTFail("A fresh StoreKit test session is required")"# + "\n" +
                "                    return usedSettingsRetry\n" +
                "                }\n" +
                "                storeKitSession = freshSession\n" +
                "                freshSession.resetToDefaultState()\n" +
                "                freshSession.clearTransactions()\n" +
                "                freshSession.disableDialogs = true\n" +
                "                app.launch()\n" +
                #"                XCTAssertTrue(element("s2.sign-detail.screen", in: app)"# + "\n" +
                "                    .waitForExistence(timeout: 30))"
        XCTAssertEqual(
            unverifiedRetrySource.components(
                separatedBy: retryStoreKitResetAndRelaunch
            ).count - 1,
            1
        )
        let retryRouteReentry =
            #"                XCTAssertTrue(element("s2.sign-detail.screen", in: app)"# + "\n" +
                "                    .waitForExistence(timeout: 30))\n" +
                #"                let retrySettings = element("s1.settings.button", in: app)"# + "\n" +
                #"                assertControl(retrySettings, label: "Settings")"# + "\n" +
                "                retrySettings.tap()\n" +
                #"                XCTAssertTrue(element("s1.settings.screen", in: app)"# + "\n" +
                "                    .waitForExistence(timeout: 20))\n" +
                #"                let retryPaywall = element("s7.2.settings.paywall", in: app)"# + "\n" +
                "                scroll(retryPaywall, in: app)\n" +
                #"                assertControl(retryPaywall, label: "View subscription")"# + "\n" +
                "                retryPaywall.tap()\n" +
                #"                XCTAssertTrue(element("s7.2.paywall.screen", in: app)"# + "\n" +
                "                    .waitForExistence(timeout: 30))\n" +
                "                usedSettingsRetry = true\n" +
                #"                store = element("s7.2.paywall.store", in: app)"#
        XCTAssertEqual(
            unverifiedRetrySource.components(
                separatedBy: retryRouteReentry
            ).count - 1,
            1
        )
        let retryReadyToTapAdjacency =
            #"                store = element("s7.2.paywall.store", in: app)"# + "\n" +
                "                XCTAssertTrue(store.waitForExistence(timeout: 30))\n" +
                "                XCTAssertTrue(wait(\n" +
                "                    for: store,\n" +
                #"                    predicate: "value == 'Ready'","# + "\n" +
                "                    timeout: 20\n" +
                "                ))\n" +
                "                XCTAssertTrue(store.isEnabled)\n" +
                "                purchase = firstPurchaseButton(in: app)\n" +
                "                scroll(purchase, in: app)\n" +
                "                XCTAssertTrue(purchase.waitForExistence(timeout: 20))\n" +
                "                XCTAssertTrue(purchase.isEnabled)\n" +
                "                XCTAssertTrue(purchase.isHittable)\n" +
                "                purchase.tap()\n" +
                #"                purchaseState = element("s7.2.paywall.purchase-state", in: app)"#
        XCTAssertEqual(
            unverifiedRetrySource.components(
                separatedBy: retryReadyToTapAdjacency
            ).count - 1,
            1
        )
        let retryBranchToFinalVerifiedWait =
            #"                purchaseState = element("s7.2.paywall.purchase-state", in: app)"# + "\n" +
                "            }\n" +
                "        }\n" +
                finalVerifiedPurchaseWait
        XCTAssertEqual(
            purchaseRecoverySource.components(
                separatedBy: retryBranchToFinalVerifiedWait
            ).count - 1,
            1
        )
        XCTAssertEqual(
            unverifiedRetrySource.components(
                separatedBy: "scroll(purchase, in: app)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            purchaseRecoverySource.components(
                separatedBy: "        if !usesPseudolanguage {"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            purchaseRecoverySource.components(separatedBy: "timeout: 45").count - 1,
            2
        )
        XCTAssertEqual(
            purchaseRecoverySource.components(separatedBy: "timeout:").count - 1,
            8
        )
        XCTAssertEqual(
            unverifiedRetrySource.components(separatedBy: "timeout: 30").count - 1,
            3
        )
        XCTAssertEqual(
            unverifiedRetrySource.components(separatedBy: "timeout: 20").count - 1,
            3
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: "purchase.tap()").count - 1,
            2
        )
        XCTAssertEqual(
            unverifiedRetrySource.components(separatedBy: "retrySettings.tap()").count - 1,
            1
        )
        XCTAssertEqual(
            unverifiedRetrySource.components(separatedBy: "retryPaywall.tap()").count - 1,
            1
        )
        XCTAssertEqual(
            unverifiedRetrySource.components(separatedBy: "retryStart.tap()").count - 1,
            0
        )
        for removedRetryStartForm in [
            #"let retryStart = element("s2.sign-detail.start-check", in: app)"#,
            "scroll(retryStart, in: app)",
            #"assertControl(retryStart, label: "Start Check")"#,
            "retryStart.tap()",
        ] {
            XCTAssertEqual(
                unverifiedRetrySource.components(
                    separatedBy: removedRetryStartForm
                ).count - 1,
                0,
                removedRetryStartForm
            )
        }
        XCTAssertEqual(
            unverifiedRetrySource.components(
                separatedBy: "                    return usedSettingsRetry"
            ).count - 1,
            2
        )
        XCTAssertFalse(uiSource.contains("buyProduct("))
        for noRetrySource in [purchaseRecoveryPrefix, purchaseRecoverySuffix] {
            for prohibited in [
                "resetToDefaultState()",
                "clearTransactions()",
                "disableDialogs = true",
            ] {
                XCTAssertFalse(noRetrySource.contains(prohibited), prohibited)
            }
        }
        for prohibited in ["for ", "while ", "repeat {"] {
            XCTAssertFalse(unverifiedRetrySource.contains(prohibited), prohibited)
        }
        for prohibited in [
            "waitForLocalizedLabel(",
            "captureBaseline(",
            "attachCandidate(",
            "printJSONLine(",
            "XCTSkip",
            "buyProduct(",
            "Product.purchase(",
            "currentEntitlements",
            "purchaseCoordinator",
            "launchArguments",
            "launchEnvironment",
        ] {
            XCTAssertFalse(unverifiedRetrySource.contains(prohibited), prohibited)
        }
        for prohibited in [
            "containing: unverifiedPurchaseLabel",
            "equals: unverifiedPurchaseLabel",
            "timeout: 46",
            "timeout: 60",
            "timeout: 90",
        ] {
            XCTAssertFalse(purchaseRecoverySource.contains(prohibited), prohibited)
        }

        let availablePurchaseFunctionStart =
            "    @MainActor\n" +
                "    private func captureAvailablePaywallAndPurchase(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {\n" +
                "        var usedSettingsRetry = false"
        let availablePurchaseFunctionEnd =
            "\n\n    @MainActor\n" +
                "    private func assertMonthlyPaywallAtXXXL("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: availablePurchaseFunctionStart
            ).count - 1,
            1
        )
        guard let availablePurchaseFunctionStartRange = uiSource.range(
            of: availablePurchaseFunctionStart
        ), let availablePurchaseFunctionEndRange = uiSource.range(
            of: availablePurchaseFunctionEnd,
            range: availablePurchaseFunctionStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded Bool-returning available-purchase source slice")
            return
        }
        let availablePurchaseFunctionSource = String(
            uiSource[
                availablePurchaseFunctionStartRange.lowerBound..<availablePurchaseFunctionEndRange.lowerBound
            ]
        )
        XCTAssertEqual(
            availablePurchaseFunctionSource.components(
                separatedBy: "var usedSettingsRetry = false"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            availablePurchaseFunctionSource.components(
                separatedBy: "usedSettingsRetry = true"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            availablePurchaseFunctionSource.components(
                separatedBy: "return usedSettingsRetry"
            ).count - 1,
            12
        )
        XCTAssertFalse(availablePurchaseFunctionSource.contains("\n            return\n"))
        XCTAssertFalse(availablePurchaseFunctionSource.contains("\n                    return\n"))
        let availablePurchaseTerminalReturn =
            #"        captureBaseline("state.paywall.purchase-complete", in: app)"# + "\n" +
                "        return usedSettingsRetry\n" +
                "    }"
        XCTAssertTrue(
            availablePurchaseFunctionSource.hasSuffix(availablePurchaseTerminalReturn)
        )

        let purchaseCallerStart =
            "    @MainActor\n" +
                "    private func purchaseBlockedEvaluationAndBeginFreshCheck("
        let purchaseCallerEnd =
            "\n\n    @MainActor\n" +
                "    private func acceptImportedPhotoWithoutBaseline("
        XCTAssertEqual(
            uiSource.components(separatedBy: purchaseCallerStart).count - 1,
            1
        )
        guard let purchaseCallerStartRange = uiSource.range(of: purchaseCallerStart),
              let purchaseCallerEndRange = uiSource.range(
                of: purchaseCallerEnd,
                range: purchaseCallerStartRange.upperBound..<uiSource.endIndex
              ) else {
            XCTFail("Missing the bounded available-purchase caller source slice")
            return
        }
        let purchaseCallerSource = String(
            uiSource[purchaseCallerStartRange.lowerBound..<purchaseCallerEndRange.lowerBound]
        )
        let postCloseSettingsRestoration =
            "        let usedSettingsRetry = captureAvailablePaywallAndPurchase(in: app)\n" +
                "\n" +
                #"        let close = element("s7.2.paywall.close", in: app)"# + "\n" +
                "        scrollDown(close, in: app)\n" +
                #"        assertControl(close, label: "Close")"# + "\n" +
                "        close.tap()\n" +
                "        if usedSettingsRetry {\n" +
                #"            XCTAssertTrue(element("s1.settings.screen", in: app)"# + "\n" +
                "                .waitForExistence(timeout: 20))\n" +
                "            navigateBack(in: app)\n" +
                "        }\n" +
                #"        XCTAssertTrue(element("s2.sign-detail.screen", in: app)"# + "\n" +
                "            .waitForExistence(timeout: 20))\n" +
                "        beginFreshCheck(in: app)"
        XCTAssertEqual(
            purchaseCallerSource.components(
                separatedBy: postCloseSettingsRestoration
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "captureAvailablePaywallAndPurchase(in: app)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            purchaseCallerSource.components(
                separatedBy: "if usedSettingsRetry {"
            ).count - 1,
            1
        )

        let reportCorrectionSourcePath =
            "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift"
        try assertFile(
            reportCorrectionSourcePath,
            byteCount: 15_197,
            sha256: "BF7DB2A5038CBE910E308DC16DEE5118EEA3930A1847F8AEBBD5FE691EDE9E2F"
        )
        let reportCorrectionSource = try text(reportCorrectionSourcePath)
        let reportCorrectionOuterScrollComposition =
            "            .padding(DesignTokens.Spacing.space16)\n" +
                "        }\n" +
                "        .scrollDismissesKeyboard(validationMessage == nil ? .immediately : .never)\n" +
                #"        .navigationTitle("Correct report")"#
        XCTAssertEqual(
            reportCorrectionSource.components(
                separatedBy: reportCorrectionOuterScrollComposition
            ).count - 1,
            1
        )
        let reportCorrectionValidationClearAndFocus =
            #"                            .focused($keyboardFocus, equals: .note)"# + "\n" +
                #"                            .accessibilityFocused($accessibilityFocus, equals: .note)"# + "\n" +
                "                            .accessibilityLabel(\"Correction note\")\n" +
                "                            .accessibilityHint(\"Enter a different note, up to 1,000 characters. Leave it blank to remove the current note.\")\n" +
                "                            .accessibilityIdentifier(Self.noteAccessibilityIdentifier)\n" +
                "                            .onChange(of: note) { _, _ in\n" +
                "                                validationMessage = nil\n" +
                "                                if state == .failed { state = .editing }\n" +
                "                            }"
        XCTAssertEqual(
            reportCorrectionSource.components(
                separatedBy: reportCorrectionValidationClearAndFocus
            ).count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionSource.components(
                separatedBy: ".scrollDismissesKeyboard(.never)"
            ).count - 1,
            0
        )

        let recordWorkSourcePath =
            "FieldEvidenceApp/Features/Issues/RecordWorkView.swift"
        try assertFile(
            recordWorkSourcePath,
            byteCount: 14_867,
            sha256: "B2DF8E9F3E2C2A1E2B89C332742F4D4E2E56E2115CAFE867625C9F1B924FC2E6"
        )
        let recordWorkSource = try text(recordWorkSourcePath)
        let recordWorkDynamicKeyboardMode =
            "            .padding(DesignTokens.Spacing.space16)\n" +
                "        }\n" +
                "        .scrollDismissesKeyboard(showsDescriptionValidation ? .never : .immediately)\n" +
                #"        .navigationTitle("Record work")"#
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: recordWorkDynamicKeyboardMode
            ).count - 1,
            1
        )
        let recordWorkValidationClearAndFocus =
            #"                            .focused($fieldFocus)"# + "\n" +
                "                            .onChange(of: description) { _, value in\n" +
                "                                guard showsDescriptionValidation else { return }\n" +
                "                                let normalizedValue = value\n" +
                "                                    .trimmingCharacters(in: .whitespacesAndNewlines)\n" +
                "                                if !normalizedValue.isEmpty,\n" +
                "                                   normalizedValue.count <= 160 {\n" +
                "                                    showsDescriptionValidation = false\n" +
                "                                }\n" +
                "                            }"
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: recordWorkValidationClearAndFocus
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy:
                    #".accessibilityFocused("# + "\n" +
                    "                                $accessibilityFocus,\n" +
                    "                                equals: .description\n" +
                    "                            )"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionSource.components(
                separatedBy: ".scrollDismissesKeyboard(validationMessage == nil ? .immediately : .never)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionSource.components(
                separatedBy: #"AssetRoundsPrimaryAction("Save correction", action: save)"#
            ).count - 1,
            1
        )
        let unchangedReportCorrectionValidationFocusChain =
            "    private func showValidation(_ message: String) {\n" +
                "        validationMessage = message\n" +
                "        state = .editing\n" +
                "        Task { @MainActor in\n" +
                "            await Task.yield()\n" +
                "            keyboardFocus = .note\n" +
                "            accessibilityFocus = nil\n" +
                "            await Task.yield()\n" +
                "            accessibilityFocus = .validation\n" +
                "        }\n" +
                "    }"
        XCTAssertEqual(
            reportCorrectionSource.components(
                separatedBy: unchangedReportCorrectionValidationFocusChain
            ).count - 1,
            1
        )

        let correctionValidationStart =
            #"captureBaseline("state.report-correction.editing", in: app)"#
        let correctionValidationEnd =
            #"let saving = element("s4.5.correction.saving", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: correctionValidationStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: correctionValidationEnd).count - 1,
            1
        )
        guard let correctionValidationStartRange = uiSource.range(
            of: correctionValidationStart
        ) else {
            XCTFail("Missing Report correction validation route start")
            return
        }
        let correctionValidationTail = uiSource[
            correctionValidationStartRange.upperBound...
        ]
        guard let correctionValidationEndRange = correctionValidationTail.range(
            of: correctionValidationEnd
        ) else {
            XCTFail("Missing Report correction validation route end")
            return
        }
        let correctionValidationSource = String(
            uiSource[
                correctionValidationStartRange.lowerBound..<correctionValidationEndRange.lowerBound
            ]
        )
        let correctionValidationOrderedLocks = [
            #"let save = element("s4.5.correction.save", in: app)"# + "\n" +
                "        scroll(save, in: app)\n" +
                #"        assertControl(save, label: "Save correction")"# + "\n" +
                "        save.tap()\n" +
                #"        let validation = element("s4.5.correction.validation", in: app)"# +
                "\n" +
                "        XCTAssertTrue(validation.waitForExistence(timeout: 10))\n" +
                #"        assertLocalizedLabelContains(validation, "Change the note before saving.")"#,
            #"let note = element("s4.5.correction.note", in: app)"# + "\n" +
                "        guard note.waitForExistence(timeout: 10) else {\n" +
                #"            XCTFail("Report correction note did not appear after validation.")"# +
                "\n" +
                "            return\n" +
                "        }\n" +
                "        guard wait(\n" +
                "            for: note,\n" +
                #"            predicate: "hasKeyboardFocus == true","# + "\n" +
                "            timeout: 10\n" +
                "        ) else {\n" +
                #"            XCTFail("Report correction validation did not retain note focus.")"# +
                "\n" +
                "            return\n" +
                "        }",
            "let keyboard = app.keyboards.firstMatch\n" +
                "        let navigationBar = app.navigationBars.firstMatch\n" +
                "        guard keyboard.waitForExistence(timeout: 10),\n" +
                "              navigationBar.waitForExistence(timeout: 10) else {\n" +
                #"            XCTFail("Report correction keyboard or navigation bar is missing.")"# +
                "\n" +
                "            return\n" +
                "        }",
            "let correctionScrollViews = app.scrollViews.containing(\n" +
                "            .button,\n" +
                #"            identifier: "s4.5.correction.save""# + "\n" +
                "        )\n" +
                "        guard correctionScrollViews.count == 1 else {\n" +
                #"            XCTFail("Report correction must have one Save-containing ScrollView.")"# +
                "\n" +
                "            return\n" +
                "        }\n" +
                "        let correctionScrollView = correctionScrollViews.firstMatch\n" +
                "        guard correctionScrollView.waitForExistence(timeout: 10) else {\n" +
                #"            XCTFail("Report correction Save-containing ScrollView is missing.")"# +
                "\n" +
                "            return\n" +
                "        }",
            "let currentProfileInputViews: XCUIElementQuery?\n" +
                "        let keyboardInputView: XCUIElement?\n" +
                "        if automationShard?.deviceProfileID == \"iphone-17-ios-26.2-current\" {\n" +
                "            let inputViews = app.otherElements.matching(\n" +
                "                NSPredicate(format: \"identifier == %@\", \"inputView\")\n" +
                "            )\n" +
                "            guard inputViews.count == 1 else {\n" +
                "                XCTFail(\"Report correction must have one current-profile input view.\")\n" +
                "                return\n" +
                "            }\n" +
                "            let inputView = inputViews.firstMatch\n" +
                "            guard inputView.waitForExistence(timeout: 10) else {\n" +
                "                XCTFail(\"Report correction current-profile input view is missing.\")\n" +
                "                return\n" +
                "            }\n" +
                "            currentProfileInputViews = inputViews\n" +
                "            keyboardInputView = inputView\n" +
                "        } else {\n" +
                "            currentProfileInputViews = nil\n" +
                "            keyboardInputView = nil\n" +
                "        }",
            "let dragInset: CGFloat = 24\n" +
                "        let minimumGestureDistance: CGFloat = 44\n" +
                "        for _ in 0..<4 {\n" +
                "            let scrollFrame = correctionScrollView.frame\n" +
                "            let visibleTop = max(scrollFrame.minY, navigationBar.frame.maxY)",
            "            let keyboardFrame = keyboard.frame\n" +
                "            let visibleBottom: CGFloat\n" +
                "            if let inputViews = currentProfileInputViews,\n" +
                "               let inputView = keyboardInputView {\n" +
                "                guard inputViews.count == 1,\n" +
                "                      inputView.exists else {\n" +
                "                    XCTFail(\"Report correction current-profile input view changed.\")\n" +
                "                    return\n" +
                "                }\n" +
                "                let inputViewFrame = inputView.frame\n" +
                "                guard inputViewFrame.minX <= keyboardFrame.minX,\n" +
                "                      inputViewFrame.maxX >= keyboardFrame.maxX,\n" +
                "                      inputViewFrame.minY <= keyboardFrame.minY,\n" +
                "                      inputViewFrame.maxY >= keyboardFrame.maxY else {\n" +
                "                    XCTFail(\"Report correction input view does not contain the keyboard.\")\n" +
                "                    return\n" +
                "                }\n" +
                "                visibleBottom = min(\n" +
                "                    scrollFrame.maxY,\n" +
                "                    min(keyboardFrame.minY, inputViewFrame.minY)\n" +
                "                )\n" +
                "            } else {\n" +
                "                visibleBottom = min(scrollFrame.maxY, keyboardFrame.minY)\n" +
                "            }",
            "            guard visibleBottom > visibleTop else {\n" +
                #"                XCTFail("Report correction has no visible keyboard-safe interval.")"# +
                "\n" +
                "                return\n" +
                "            }",
            "let validationFrame = validation.frame\n" +
                "            let saveFrame = save.frame\n" +
                "            if validationFrame.minY >= visibleTop,\n" +
                "               validationFrame.maxY <= visibleBottom,\n" +
                "               saveFrame.minY >= visibleTop,\n" +
                "               saveFrame.maxY <= visibleBottom {\n" +
                "                break\n" +
                "            }",
            "let minimumShift = max(\n" +
                "                visibleTop - validationFrame.minY,\n" +
                "                visibleTop - saveFrame.minY\n" +
                "            )\n" +
                "            let maximumShift = min(\n" +
                "                visibleBottom - validationFrame.maxY,\n" +
                "                visibleBottom - saveFrame.maxY\n" +
                "            )\n" +
                "            guard minimumShift <= maximumShift else {\n" +
                #"                XCTFail("Report correction validation and Save cannot share the viewport.")"# +
                "\n" +
                "                return\n" +
                "            }",
            "let farFeasibleShift = abs(minimumShift) >= abs(maximumShift)\n" +
                "                ? minimumShift\n" +
                "                : maximumShift\n" +
                "            let maximumGestureDistance = visibleBottom\n" +
                "                - visibleTop\n" +
                "                - (2 * dragInset)\n" +
                "            guard maximumGestureDistance >= minimumGestureDistance else {\n" +
                #"                XCTFail("Report correction viewport cannot fit a recognized gesture.")"# +
                "\n" +
                "                return\n" +
                "            }\n" +
                "            let dragDistance = max(\n" +
                "                -maximumGestureDistance,\n" +
                "                min(farFeasibleShift, maximumGestureDistance)\n" +
                "            )\n" +
                "            guard abs(dragDistance) >= minimumGestureDistance else {\n" +
                #"                XCTFail("Report correction feasible shift is below gesture recognition.")"# +
                "\n" +
                "                return\n" +
                "            }",
            "let scrollOrigin = correctionScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )\n" +
                "            let dragStartOffsetY = dragDistance > 0\n" +
                "                ? visibleTop - scrollFrame.minY + dragInset\n" +
                "                : visibleBottom - scrollFrame.minY - dragInset\n" +
                "            let dragStart = scrollOrigin.withOffset(\n" +
                "                CGVector(dx: scrollFrame.width / 2, dy: dragStartOffsetY)\n" +
                "            )\n" +
                "            let dragEnd = dragStart.withOffset(\n" +
                "                CGVector(dx: 0, dy: dragDistance)\n" +
                "            )\n" +
                "            let saveBeforeDrag = save.frame.minY\n" +
                "            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)\n" +
                "            let observedShift = save.frame.minY - saveBeforeDrag\n" +
                "            guard observedShift * dragDistance > 0 else {\n" +
                #"                XCTFail("Report correction positioning gesture was not recognized.")"# +
                "\n" +
                "                return\n" +
                "            }\n" +
                "        }",
            "let finalFocusPreserved = wait(\n" +
                "            for: note,\n" +
                #"            predicate: "hasKeyboardFocus == true","# + "\n" +
                "            timeout: 10\n" +
                "        )\n" +
                "        let finalKeyboardExists = keyboard.waitForExistence(timeout: 10)\n" +
                "        let finalValidationExists = validation.waitForExistence(timeout: 10)\n" +
                "        let finalSaveExists = save.waitForExistence(timeout: 10)\n" +
                "        let finalScrollFrame = correctionScrollView.frame\n" +
                "        let finalVisibleTop = max(finalScrollFrame.minY, navigationBar.frame.maxY)\n" +
                "        let finalKeyboardFrame = keyboard.frame\n" +
                "        let finalKeyboardInputViewExists: Bool\n" +
                "        let finalKeyboardInputViewContainsKeyboard: Bool\n" +
                "        let finalVisibleBottom: CGFloat\n" +
                "        if let inputViews = currentProfileInputViews,\n" +
                "           let inputView = keyboardInputView {\n" +
                "            finalKeyboardInputViewExists = inputViews.count == 1\n" +
                "                && inputView.waitForExistence(timeout: 10)\n" +
                "            let finalInputViewFrame = inputView.frame\n" +
                "            finalKeyboardInputViewContainsKeyboard = finalKeyboardExists\n" +
                "                && finalKeyboardInputViewExists\n" +
                "                && finalInputViewFrame.minX <= finalKeyboardFrame.minX\n" +
                "                && finalInputViewFrame.maxX >= finalKeyboardFrame.maxX\n" +
                "                && finalInputViewFrame.minY <= finalKeyboardFrame.minY\n" +
                "                && finalInputViewFrame.maxY >= finalKeyboardFrame.maxY\n" +
                "            finalVisibleBottom = finalKeyboardInputViewContainsKeyboard\n" +
                "                ? min(\n" +
                "                    finalScrollFrame.maxY,\n" +
                "                    min(finalKeyboardFrame.minY, finalInputViewFrame.minY)\n" +
                "                )\n" +
                "                : -CGFloat.greatestFiniteMagnitude\n" +
                "        } else {\n" +
                "            finalKeyboardInputViewExists = true\n" +
                "            finalKeyboardInputViewContainsKeyboard = true\n" +
                "            finalVisibleBottom = finalKeyboardExists\n" +
                "                ? min(finalScrollFrame.maxY, finalKeyboardFrame.minY)\n" +
                "                : -CGFloat.greatestFiniteMagnitude\n" +
                "        }\n" +
                "        let finalValidationContained = finalValidationExists\n" +
                "            && validation.frame.minY >= finalVisibleTop\n" +
                "            && validation.frame.maxY <= finalVisibleBottom\n" +
                "        let finalSaveContained = finalSaveExists\n" +
                "            && save.frame.minY >= finalVisibleTop\n" +
                "            && save.frame.maxY <= finalVisibleBottom",
            "guard finalFocusPreserved,\n" +
                "              finalKeyboardExists,\n" +
                "              finalKeyboardInputViewExists,\n" +
                "              finalKeyboardInputViewContainsKeyboard,\n" +
                "              finalValidationExists,\n" +
                "              finalSaveExists,\n" +
                "              finalValidationContained,\n" +
                "              finalSaveContained,\n" +
                "              save.isHittable else {\n" +
                "            XCTFail(\n" +
                #"                "Report correction validation and Save did not remain fully actionable.""# +
                "\n" +
                "            )\n" +
                "            return\n" +
                "        }\n" +
                #"        captureBaseline("state.report-correction.validation-error", in: app)"# +
                "\n\n" +
                #"        note.typeText("Verified connector label")"#,
        ]
        var orderedCorrectionValidationTail = correctionValidationSource
        for lock in correctionValidationOrderedLocks {
            XCTAssertEqual(
                correctionValidationSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
            guard let lockRange = orderedCorrectionValidationTail.range(of: lock) else {
                XCTFail("Report correction validation locks are out of order: \(lock)")
                return
            }
            orderedCorrectionValidationTail = String(
                orderedCorrectionValidationTail[lockRange.upperBound...]
            )
        }
        let correctionCurrentProfileGate =
            #"if automationShard?.deviceProfileID == "iphone-17-ios-26.2-current" {"#
        XCTAssertEqual(
            correctionValidationSource.components(
                separatedBy: correctionCurrentProfileGate
            ).count - 1,
            1
        )
        let correctionInputViewQueryLiteral =
            #"NSPredicate(format: "identifier == %@", "inputView")"#
        XCTAssertEqual(
            correctionValidationSource.components(
                separatedBy: correctionInputViewQueryLiteral
            ).count - 1,
            1
        )

        let feedbackSourcePath =
            "FieldEvidenceApp/Features/Settings/FeedbackView.swift"
        try assertFile(
            feedbackSourcePath,
            byteCount: 14_394,
            sha256: "8CF0AF2E25352EE0EF7C19A2A063B9F51A06AD81188C05FFB736AFE05ABED056"
        )
        let feedbackSource = try text(feedbackSourcePath)
        let feedbackEdgeVisibility =
            "private struct FeedbackTopScrollEdgeVisibility: ViewModifier {\n" +
                "    @ViewBuilder\n" +
                "    func body(content: Content) -> some View {\n" +
                "        if #available(iOS 26.0, *) {\n" +
                "            content\n" +
                "                .scrollEdgeEffectHidden(true, for: .top)\n" +
                "                .scrollEdgeEffectHidden(true, for: .bottom)\n" +
                "        } else {\n" +
                "            content\n" +
                "        }\n" +
                "    }\n" +
                "}"
        XCTAssertEqual(
            feedbackSource.components(separatedBy: feedbackEdgeVisibility).count - 1,
            1
        )
        XCTAssertEqual(
            feedbackSource.components(
                separatedBy: ".modifier(FeedbackTopScrollEdgeVisibility())"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            feedbackSource.components(
                separatedBy: ".scrollEdgeEffectHidden(true, for: .top)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            feedbackSource.components(
                separatedBy: ".scrollEdgeEffectHidden(true, for: .bottom)"
            ).count - 1,
            1
        )

        let postPurchaseExistenceGeometryEnabledGuard =
            #"let terms = element("s7.2.paywall.terms", in: app)"# + "\n" +
                #"        let privacy = element("s7.2.paywall.privacy", in: app)"# + "\n" +
                #"        let support = element("s7.2.paywall.support", in: app)"# + "\n" +
                "        for control in [terms, privacy, support] {\n" +
                "            XCTAssertTrue(control.waitForExistence(timeout: 20))\n" +
                "            assertMinimumGeometry(control)\n" +
                "            XCTAssertTrue(control.isEnabled)\n" +
                "        }"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: postPurchaseExistenceGeometryEnabledGuard
            ).count - 1,
            1
        )
        let postPurchaseNonOverlapOrderGuard =
            "XCTAssertLessThanOrEqual(purchaseState.frame.maxY, terms.frame.minY)\n" +
                "        XCTAssertLessThanOrEqual(terms.frame.maxY, privacy.frame.minY)\n" +
                "        XCTAssertLessThanOrEqual(privacy.frame.maxY, support.frame.minY)"
        XCTAssertEqual(
            uiSource.components(separatedBy: postPurchaseNonOverlapOrderGuard).count - 1,
            1
        )

        let postPurchaseViewportStart =
            #"        let close = element("s7.2.paywall.close", in: app)"#
        let postPurchaseCapture =
            #"        captureBaseline("state.paywall.purchase-complete", in: app)"#
        guard let nonOverlapRange = uiSource.range(of: postPurchaseNonOverlapOrderGuard) else {
            XCTFail("Missing the pre-position purchase-complete order guard")
            return
        }
        let sourceAfterNonOverlap = uiSource[nonOverlapRange.upperBound...]
        guard let viewportStartRange = sourceAfterNonOverlap.range(
            of: postPurchaseViewportStart
        ) else {
            XCTFail("Missing the purchase-complete viewport positioning start")
            return
        }
        let sourceAfterViewportStart = uiSource[viewportStartRange.lowerBound...]
        guard let captureRange = sourceAfterViewportStart.range(of: postPurchaseCapture) else {
            XCTFail("Missing the purchase-complete capture after viewport positioning")
            return
        }
        let postPurchaseViewportSource = String(
            uiSource[viewportStartRange.lowerBound..<captureRange.lowerBound]
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: postPurchaseCapture).count - 1,
            1
        )

        let postPurchaseViewportIntervalLocks = [
            #"let close = element("s7.2.paywall.close", in: app)"#,
            "guard store.waitForExistence(timeout: 20),\n" +
                "              close.waitForExistence(timeout: 20),\n" +
                "              support.waitForExistence(timeout: 20),\n" +
                "              purchase.waitForExistence(timeout: 20) else",
            "The purchase-complete viewport controls must exist before positioning.",
            "var measuredUndertravel: CGFloat = 0",
            "for _ in 0..<4",
            "let viewportTop = store.frame.minY",
            "let viewportBottom = store.frame.maxY",
            "let minimumShift = max(\n" +
                "                viewportTop - close.frame.minY,\n" +
                "                viewportBottom - purchase.frame.minY\n" +
                "            )",
            "let maximumShift = viewportBottom - support.frame.maxY",
            "if minimumShift <= 0, maximumShift >= 0",
            "guard minimumShift <= maximumShift else",
            "The purchase-complete viewport has no feasible positioning interval.",
            "guard maximumShift > 0 else",
            "The purchase-complete viewport requires a non-positive correction."
        ]
        for lock in postPurchaseViewportIntervalLocks {
            XCTAssertEqual(
                postPurchaseViewportSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let postPurchaseViewportGestureLocks = [
            "let targetDistance = maximumShift",
            "let requestedDistance = targetDistance + measuredUndertravel",
            "let dragInset: CGFloat = 24",
            "let maximumGestureDistance = store.frame.height - 2 * dragInset",
            "guard maximumGestureDistance >= 44 else",
            "The Store viewport cannot contain a recognized positioning gesture.",
            "let dragDistance = min(requestedDistance, maximumGestureDistance)",
            "guard dragDistance >= 44 else",
            "The purchase-complete positioning gesture would not be recognized.",
            "let closeBeforeDrag = close.frame.minY",
            "let storeOrigin = store.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )",
            "let dragStart = storeOrigin.withOffset(\n" +
                "                CGVector(dx: store.frame.width / 2, dy: dragInset)\n" +
                "            )",
            "let dragEnd = storeOrigin.withOffset(\n" +
                "                CGVector(\n" +
                "                    dx: store.frame.width / 2,\n" +
                "                    dy: dragInset + dragDistance\n" +
                "                )\n" +
                "            )",
            "dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )",
            "let actualDistance = close.frame.minY - closeBeforeDrag",
            "guard actualDistance > 0 else",
            "The purchase-complete positioning gesture was not recognized.",
            "measuredUndertravel = max(0, dragDistance - actualDistance)"
        ]
        for lock in postPurchaseViewportGestureLocks {
            XCTAssertEqual(
                postPurchaseViewportSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let postPurchaseViewportFinalLocks = [
            "let finalViewportControls = [close, terms, privacy, support]",
            "guard finalViewportControls.allSatisfy({\n" +
                "            $0.waitForExistence(timeout: 20)\n" +
                "        }) else",
            "The purchase-complete viewport controls must remain present.",
            "for control in finalViewportControls {\n" +
                "            assertMinimumGeometry(control)\n" +
                "            XCTAssertTrue(control.isEnabled)\n" +
                "            XCTAssertTrue(control.isHittable)\n" +
                "        }",
            "guard finalViewportControls.allSatisfy({\n" +
                "            $0.frame.width + 0.001 >= 44\n" +
                "                && $0.frame.height + 0.001 >= 44\n" +
                "                && $0.isEnabled\n" +
                "                && $0.isHittable\n" +
                "        }) else",
            "The purchase-complete viewport controls must remain actionable.",
            "guard close.frame.minY >= store.frame.minY,\n" +
                "              close.frame.maxY <= store.frame.maxY,\n" +
                "              purchaseState.frame.maxY <= terms.frame.minY,\n" +
                "              terms.frame.maxY <= privacy.frame.minY,\n" +
                "              privacy.frame.maxY <= support.frame.minY,\n" +
                "              support.frame.maxY <= store.frame.maxY,\n" +
                "              purchase.frame.minY >= store.frame.maxY else",
            "The purchase-complete viewport composition was not reached."
        ]
        for lock in postPurchaseViewportFinalLocks {
            XCTAssertEqual(
                postPurchaseViewportSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let postPurchaseFinalGuardAndCapture =
            "            XCTFail(\"The purchase-complete viewport composition was not reached.\")\n" +
                "            return usedSettingsRetry\n" +
                "        }\n" +
                postPurchaseCapture
        XCTAssertEqual(
            uiSource.components(separatedBy: postPurchaseFinalGuardAndCapture).count - 1,
            1
        )

        let deleteCompositionLocks = [
            #"let deleteMessage = element("s6.1.delete.message", in: app)"#,
            "XCTAssertTrue(deleteMessage.waitForExistence(timeout: 5))",
            "let preferredMinimumShift = max(",
            "viewportTop - deleteMessage.frame.minY",
            "let preferredMaximumShift = min(",
            "viewportBottom - deleteMessage.frame.maxY",
            "let fallbackMinimumShift = max(",
            "let fallbackMaximumShift = min(",
            "if preferredContainsZero || fallbackContainsZero { break }",
            "let farPreferredDistance = preferredMaximumShift < 0",
            "? preferredMinimumShift\n                    : preferredMaximumShift",
            "if abs(farPreferredDistance) >= 44",
            "let farFallbackDistance = fallbackMaximumShift < 0",
            "? fallbackMinimumShift\n                    : fallbackMaximumShift",
            "if abs(farFallbackDistance) >= 44",
            "guard let targetDistance else {",
            "let dragInset: CGFloat = 24",
            "- 2 * dragInset",
            "guard maximumGestureDistance >= 44 else",
            "guard abs(dragDistance) >= 44 else",
            "Delete confirmation has no feasible recognized positioning gesture",
            "Delete confirmation viewport cannot fit a recognized gesture",
            "let preferredComposition = siteLabel.frame.maxY <= viewportTop",
            "&& deleteMessage.frame.minY >= viewportTop",
            "&& deleteMessage.frame.maxY <= viewportBottom",
            "let fallbackComposition = siteLabel.frame.maxY <= viewportTop",
            "&& deleteScreen.frame.maxY <= viewportTop\n" +
                "            && deleteMessage.frame.minY >= viewportTop\n" +
                "            && deleteMessage.frame.maxY <= viewportBottom",
            "&& cancelDelete.isHittable",
            "&& confirmDelete.isHittable",
            "XCTAssertTrue(preferredComposition || fallbackComposition)",
            "guard preferredComposition || fallbackComposition else { return }",
        ]
        for lock in deleteCompositionLocks {
            XCTAssertTrue(uiSource.contains(lock), lock)
        }
        XCTAssertEqual(
            uiSource.components(separatedBy:
                "Delete confirmation viewport cannot fit a recognized gesture"
            ).count - 1,
            2
        )

        let signDetailSourcePath =
            "FieldEvidenceApp/Features/Signs/SignDetailView.swift"
        try assertFile(
            signDetailSourcePath,
            byteCount: 11_435,
            sha256: "E0244763E542717E19E74BCDB9D7F2C29CCFF24F5EC23764841F2B07B41C73F8"
        )
        let signDetailSource = try text(signDetailSourcePath)
        XCTAssertTrue(signDetailSource.contains(
            ".padding(\n" +
                "                    .bottom,\n" +
                "                    isConfirmingDeletion ? DesignTokens.Spacing.space16 : 0\n" +
                "                )"
        ))

        let paywallSourcePath =
            "FieldEvidenceApp/Features/Subscription/PaywallView.swift"
        try assertFile(
            paywallSourcePath,
            byteCount: 13_476,
            sha256: "8C3D3F67C003B8A91B07068C99665752D2F02F18D42BAD1AF7A27EF88E75BFA6"
        )
        let paywallSource = try text(paywallSourcePath)
        let purchaseStatusSlotCallsite =
            "            purchaseStatusSlot\n\n" +
                "            VStack(alignment: .leading, spacing: " +
                "DesignTokens.Spacing.space8) {\n" +
                "                Link(\"Terms\", destination: links.terms)"
        XCTAssertEqual(
            paywallSource.components(separatedBy: purchaseStatusSlotCallsite).count - 1,
            1
        )
        let purchaseStatusSlot =
            "    private var purchaseStatusSlot: some View {\n" +
                "        ZStack(alignment: .topLeading) {\n" +
                "            ZStack(alignment: .topLeading) {\n" +
                "                verifiedPurchaseStatus\n" +
                "                recoveryPurchaseStatus(for: .cancelled)\n" +
                "                recoveryPurchaseStatus(for: .pending)\n" +
                "                recoveryPurchaseStatus(for: .unverified)\n" +
                "                recoveryPurchaseStatus(for: .failed)\n" +
                "            }\n" +
                "            .hidden()\n" +
                "            .accessibilityHidden(true)\n" +
                "            .allowsHitTesting(false)\n\n" +
                "            purchaseStatus(for: coordinator.purchaseState)\n" +
                "        }\n" +
                "        .fixedSize(horizontal: false, vertical: true)\n" +
                "        .frame(maxWidth: .infinity, alignment: .leading)\n" +
                "    }"
        XCTAssertEqual(
            paywallSource.components(separatedBy: purchaseStatusSlot).count - 1,
            1
        )
        let purchaseStatusSlotStart =
            "    private var purchaseStatusSlot: some View {\n"
        let purchaseStatusSlotEnd =
            "\n\n    @ViewBuilder\n" +
                "    private func purchaseStatus(for state: " +
                "PaywallPurchaseStateV1) -> some View {"
        let purchaseStatusSlotParts = paywallSource.components(
            separatedBy: purchaseStatusSlotStart
        )
        guard purchaseStatusSlotParts.count == 2 else {
            XCTFail("Paywall must contain exactly one stable purchase-status slot")
            return
        }
        let purchaseStatusSlotTail = purchaseStatusSlotParts[1]
        guard let purchaseStatusSlotBoundary = purchaseStatusSlotTail.range(
            of: purchaseStatusSlotEnd
        ) else {
            XCTFail("Stable purchase-status slot must end before its live renderer")
            return
        }
        let purchaseStatusSlotSlice = purchaseStatusSlotStart
            + String(
                purchaseStatusSlotTail[
                    ..<purchaseStatusSlotBoundary.lowerBound
                ]
            )
        for state in ["cancelled", "pending", "unverified", "failed"] {
            XCTAssertEqual(
                purchaseStatusSlotSlice.components(
                    separatedBy: "recoveryPurchaseStatus(for: .\(state))"
                ).count - 1,
                1,
                state
            )
        }
        XCTAssertEqual(
            purchaseStatusSlotSlice.components(
                separatedBy: "verifiedPurchaseStatus"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            purchaseStatusSlotSlice.components(
                separatedBy: "purchaseStatus(for: coordinator.purchaseState)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            paywallSource.components(
                separatedBy: "purchaseStatus(for: coordinator.purchaseState)"
            ).count - 1,
            1
        )
        for modifier in [
            ".hidden()",
            ".accessibilityHidden(true)",
            ".allowsHitTesting(false)",
            ".fixedSize(horizontal: false, vertical: true)",
            ".frame(maxWidth: .infinity, alignment: .leading)",
        ] {
            XCTAssertEqual(
                purchaseStatusSlotSlice.components(separatedBy: modifier).count - 1,
                1,
                modifier
            )
        }
        for forbidden in [
            ".frame(height:",
            ".frame(minHeight:",
            "GeometryReader",
            "PreferenceKey",
            ".preference(",
            ".onPreferenceChange(",
            "DispatchQueue",
            "Task.sleep",
            ".task",
            ".onAppear",
        ] {
            XCTAssertFalse(purchaseStatusSlotSlice.contains(forbidden), forbidden)
        }
        XCTAssertFalse(paywallSource.contains("purchaseStatusLayoutIdentity"))
        XCTAssertEqual(
            paywallSource.components(separatedBy: ".id(").count - 1,
            0
        )
        let livePurchaseStatusRenderer =
            "    @ViewBuilder\n" +
                "    private func purchaseStatus(for state: " +
                "PaywallPurchaseStateV1) -> some View {\n" +
                "        switch state {\n" +
                "        case .idle:\n" +
                "            EmptyView()\n" +
                "        case .purchasing:\n" +
                "            AssetRoundsStateLabel(kind: .selected, " +
                "\"Purchasing…\")\n" +
                "                .accessibilityLabel(" +
                "\"Information: Purchasing…\")\n" +
                "                .accessibilityValue(" +
                "Text(verbatim: String()))\n" +
                "                .accessibilityIdentifier(" +
                "Self.purchaseStateAccessibilityIdentifier)\n" +
                "        case .verified:\n" +
                "            verifiedPurchaseStatus\n" +
                "        case .cancelled, .pending, .unverified, .failed:\n" +
                "            recoveryPurchaseStatus(for: state)\n" +
                "                .accessibilityFocused(" +
                "$purchaseStatusFocused)\n" +
                "                .accessibilityIdentifier(" +
                "Self.purchaseStateAccessibilityIdentifier)\n" +
                "        }\n" +
                "    }"
        XCTAssertEqual(
            paywallSource.components(
                separatedBy: livePurchaseStatusRenderer
            ).count - 1,
            1
        )
        let verifiedPurchaseStatusRenderer =
            "    private var verifiedPurchaseStatus: some View {\n" +
                "        AssetRoundsStateLabel(\n" +
                "            kind: .completed,\n" +
                "            \"Purchase verified. Subscription access is ready.\"\n" +
                "        )\n" +
                "        .accessibilityLabel(\n" +
                "            \"Complete: Purchase verified. " +
                "Subscription access is ready.\"\n" +
                "        )\n" +
                "        .accessibilityValue(Text(verbatim: String()))\n" +
                "        .accessibilityIdentifier(" +
                "Self.purchaseStateAccessibilityIdentifier)\n" +
                "    }"
        XCTAssertEqual(
            paywallSource.components(
                separatedBy: verifiedPurchaseStatusRenderer
            ).count - 1,
            1
        )
        let recoveryPurchaseStatusRenderer =
            "    @ViewBuilder\n" +
                "    private func recoveryPurchaseStatus(\n" +
                "        for state: PaywallPurchaseStateV1\n" +
                "    ) -> some View {\n" +
                "        if let message = state.recoveryMessage {\n" +
                "            Text(message)\n" +
                "                .font(DesignTokens.Typography.primaryBody" +
                ".weight(.semibold))\n" +
                "                .foregroundStyle(" +
                "DesignTokens.SemanticColors.error)\n" +
                "                .fixedSize(horizontal: false, vertical: true)\n" +
                "        }\n" +
                "    }"
        XCTAssertEqual(
            paywallSource.components(
                separatedBy: recoveryPurchaseStatusRenderer
            ).count - 1,
            1
        )
        let legalLinkStack =
            "            VStack(alignment: .leading, spacing: " +
                "DesignTokens.Spacing.space8) {\n" +
                "                Link(\"Terms\", destination: links.terms)\n" +
                "                    .frame(minHeight: " +
                "DesignTokens.Target.minimumInteractiveHeight)\n" +
                "                    .contentShape(.interaction, Rectangle())\n" +
                "                    .contentShape(.accessibility, Rectangle())\n" +
                "                    .accessibilityIdentifier(" +
                "Self.termsAccessibilityIdentifier)\n" +
                "                Link(\"Privacy\", destination: links.privacy)\n" +
                "                    .frame(minHeight: " +
                "DesignTokens.Target.minimumInteractiveHeight)\n" +
                "                    .contentShape(.interaction, Rectangle())\n" +
                "                    .contentShape(.accessibility, Rectangle())\n" +
                "                    .accessibilityIdentifier(" +
                "Self.privacyAccessibilityIdentifier)\n" +
                "                Link(\"Support\", destination: links.support)\n" +
                "                    .frame(minHeight: " +
                "DesignTokens.Target.minimumInteractiveHeight)\n" +
                "                    .contentShape(.interaction, Rectangle())\n" +
                "                    .contentShape(.accessibility, Rectangle())\n" +
                "                    .accessibilityIdentifier(" +
                "Self.supportAccessibilityIdentifier)\n" +
                "            }\n" +
                "            .padding(.top, DesignTokens.Spacing.space8)\n" +
                "            .font(DesignTokens.Typography.sectionHeading)\n" +
                "            .buttonStyle(.plain)\n" +
                "            .frame(minHeight: " +
                "DesignTokens.Target.minimumInteractiveHeight)"
        XCTAssertEqual(
            paywallSource.components(separatedBy: legalLinkStack).count - 1,
            1
        )
        let scrollViewSubscriptionControlStyle =
            "        .subscriptionStoreControlStyle(\n" +
                "            AssetRoundsSubscriptionControlStyle(),\n" +
                "            placement: .scrollView\n" +
                "        )"
        XCTAssertEqual(
            paywallSource.components(
                separatedBy: scrollViewSubscriptionControlStyle
            ).count - 1,
            1
        )
        XCTAssertEqual(
            paywallSource.components(
                separatedBy: ".subscriptionStoreControlStyle("
            ).count - 1,
            1
        )
        XCTAssertEqual(
            paywallSource.components(separatedBy: "placement: .scrollView").count - 1,
            1
        )
        for forbiddenPlacement in [
            "placement: .automatic",
            "placement: .bottomBar",
        ] {
            XCTAssertEqual(
                paywallSource.components(
                    separatedBy: forbiddenPlacement
                ).count - 1,
                0,
                forbiddenPlacement
            )
        }
        let storeKitContracts = [
            "SubscriptionStoreView(productIDs: " +
                "[EntitlementReducerV1.productID]) {",
            "marketingContent(presentation: presentation, links: links)",
            ".storeButton(.hidden, for: .restorePurchases)",
            "_ = await coordinator.storeKitPurchaseStarted(productID: product.id)",
            "await coordinator.handleStoreKitCompletion(",
            "AssetRoundsPrimaryAction(\"Subscribe\", action: option.subscribe)",
        ]
        for contract in storeKitContracts {
            XCTAssertEqual(
                paywallSource.components(separatedBy: contract).count - 1,
                1,
                contract
            )
        }

        let captureSourcePath =
            "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift"
        try assertFile(
            captureSourcePath,
            byteCount: 17_147,
            sha256: "C99AF8E4D573E447F834282754CB5F65560737B090626EB836C6844FE2251223"
        )
        let captureSource = try text(captureSourcePath)
        let capturePrimaryOwners = [
            "AssetRoundsPrimaryAction(action: {\n" +
                "                            usePhoto(candidate)\n" +
                "                        }) {\n" +
                "                            Text(\"Use Photo\")\n" +
                "                                .frame(maxWidth: .infinity)\n" +
                "                        }\n" +
                "                        .disabled(isWorking)\n" +
                "                        .accessibilityIdentifier(Self.usePhotoAccessibilityIdentifier)",
            "AssetRoundsPrimaryAction(\"Take photo\") {\n" +
                "            takePhoto(for: step)\n" +
                "        }\n" +
                "        .disabled(isWorking)\n" +
                "        .accessibilityIdentifier(Self.takePhotoAccessibilityIdentifier)",
        ]
        let captureSecondaryOwners = [
            "AssetRoundsSecondaryAction(action: {\n" +
                "                            retake(candidate)\n" +
                "                        }) {\n" +
                "                            Text(\"Retake\")\n" +
                "                                .frame(maxWidth: .infinity)\n" +
                "                        }\n" +
                "                        .disabled(isWorking)\n" +
                "                        .accessibilityIdentifier(Self.retakeAccessibilityIdentifier)",
            "AssetRoundsSecondaryAction(\"Open Settings\") {\n" +
                "                openSettings()\n" +
                "            }\n" +
                "            .accessibilityIdentifier(Self.openSettingsAccessibilityIdentifier)",
            "AssetRoundsSecondaryAction(\"Cannot complete\") {\n" +
                "            showsCouldNotVerify = true\n" +
                "        }\n" +
                "        .disabled(isWorking)\n" +
                "        .accessibilityHint(\"Opens the reason flow to save this check as incomplete\")\n" +
                "        .accessibilityIdentifier(Self.cannotCompleteAccessibilityIdentifier)",
            "AssetRoundsSecondaryAction(\"Import test photo\") {\n" +
                "                importFixture(for: step)\n" +
                "            }\n" +
                "            .disabled(isWorking)\n" +
                "            .accessibilityIdentifier(Self.fixtureImportAccessibilityIdentifier)",
            "AssetRoundsSecondaryAction(\"Retry\") {\n" +
                "                errorMessage = nil\n" +
                "                loadPreparation()\n" +
                "            }",
        ]
        for owner in capturePrimaryOwners + captureSecondaryOwners {
            XCTAssertEqual(
                captureSource.components(separatedBy: owner).count - 1,
                1,
                owner
            )
        }
        XCTAssertEqual(
            captureSource.components(separatedBy: "AssetRoundsPrimaryAction").count - 1,
            2
        )
        XCTAssertEqual(
            captureSource.components(separatedBy: "AssetRoundsSecondaryAction").count - 1,
            5
        )
        let capturePhotosPickerOwner =
            "PhotosPicker(selection: $selectedPhotoItem, matching: .images) {\n" +
                "            Text(\"Choose from Photos\")\n" +
                "                .frame(maxWidth: .infinity)\n" +
                "        }\n" +
                "        .buttonStyle(WorklightSecondaryButtonStyle())\n" +
                "        .disabled(isWorking)\n" +
                "        .accessibilityIdentifier(Self.choosePhotosAccessibilityIdentifier)"
        XCTAssertEqual(
            captureSource.components(separatedBy: capturePhotosPickerOwner).count - 1,
            1
        )
        XCTAssertEqual(
            captureSource.components(
                separatedBy: ".buttonStyle(WorklightSecondaryButtonStyle())"
            ).count - 1,
            1
        )
        for forbidden in [
            ".buttonStyle(.bordered)",
            ".buttonStyle(.borderedProminent)",
            ".tint(DesignTokens.SemanticColors.primaryAction)",
        ] {
            XCTAssertEqual(
                captureSource.components(separatedBy: forbidden).count - 1,
                0,
                forbidden
            )
        }

        let canonicalActionOwners: [(
            path: String,
            byteCount: Int,
            sha256: String,
            fragments: [String],
            counts: [Int],
            primaryTintCount: Int
        )] = [
            (
                "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
                22_926,
                "82E2AA1A52DBE6A2D0FA8F61B6983F369B87325E0542E2385774F988F2F7697A",
                [
                    "AssetRoundsPrimaryAction(\"Continue\") {\n" +
                        "                prepareReview()\n" +
                        "            }",
                    "AssetRoundsPrimaryAction(action: {\n" +
                        "                finalize()\n" +
                        "            }) {\n" +
                        "                Text(isSaving ? \"Saving…\" : \"Save and finish\")\n" +
                        "            }",
                    "AssetRoundsSecondaryAction(\"Back\") {\n" +
                        "                self.review = nil\n" +
                        "                errorMessage = nil\n" +
                        "            }\n" +
                        "            .disabled(isSaving)\n" +
                        "            .accessibilityIdentifier(Self.backAccessibilityIdentifier)",
                    "AssetRoundsSecondaryAction(action: action) {\n" +
                        "            HStack {\n" +
                        "                Image(systemName: isSelected ? \"checkmark.circle.fill\" : \"circle\")\n" +
                        "                Text(title)\n" +
                        "                    .frame(maxWidth: .infinity, alignment: .leading)\n" +
                        "            }\n" +
                        "        }\n" +
                        "        .accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")\n" +
                        "        .accessibilityIdentifier(identifier)",
                ],
                [2, 2, 0, 0, 0],
                0
            ),
            (
                "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
                14_398,
                "35FA0E666279EE3D8D4B50950860EB99446EAC0C2BC1270C01CEFEF94680F72B",
                [
                    #"AssetRoundsPrimaryAction("Begin check", action: begin)"#,
                    "AssetRoundsSecondaryAction(\"Cancel — no check started\", action: cancel)\n" +
                        "                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)\n" +
                        "                .accessibilityHidden(focusedField == .timeZone)",
                ],
                [1, 1, 0, 0, 0],
                0
            ),
            (
                "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
                5_916,
                "59B875E2FB89CAD9AF4BC02A9214686A95896E3E99FF7581BEACA600AF2CCB72",
                [
                    "AssetRoundsPrimaryAction(\"View report\") {\n" +
                        "                        showsReport = true\n" +
                        "                    }",
                    "AssetRoundsSecondaryAction(\"Share PDF\") {\n" +
                        "                        showsShareSheet = true\n" +
                        "                    }\n" +
                        "                    .accessibilityHint(\"Opens the system share sheet for this report PDF\")\n" +
                        "                    .accessibilityIdentifier(Self.shareAccessibilityIdentifier)",
                    "AssetRoundsSecondaryAction(\"Done\") {\n" +
                        "                    dismiss()\n" +
                        "                }",
                ],
                [1, 2, 0, 0, 0],
                0
            ),
            (
                "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
                14_867,
                "B2DF8E9F3E2C2A1E2B89C332742F4D4E2E56E2115CAFE867625C9F1B924FC2E6",
                [
                    #"AssetRoundsPrimaryAction("Record work", action: save)"#,
                    "AssetRoundsSecondaryAction(\n" +
                        "                            \"Add one optional photo showing the work performed.\",\n" +
                        "                            action: importFixture\n" +
                        "                        )\n" +
                        "                        .disabled(isSaving)\n" +
                        "                        .accessibilityIdentifier(Self.importFixtureAccessibilityIdentifier)",
                    "PhotosPicker(\n" +
                        "                            selection: $selectedPhotoItem,\n" +
                        "                            matching: .images\n" +
                        "                        ) {\n" +
                        "                            Text(\"Add one optional photo showing the work performed.\")\n" +
                        "                                .frame(maxWidth: .infinity)\n" +
                        "                        }\n" +
                        "                        .buttonStyle(WorklightSecondaryButtonStyle())\n" +
                        "                        .disabled(isSaving)",
                ],
                [1, 1, 0, 0, 1],
                0
            ),
            (
                "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
                15_197,
                "BF7DB2A5038CBE910E308DC16DEE5118EEA3930A1847F8AEBBD5FE691EDE9E2F",
                [
                    #"AssetRoundsPrimaryAction("Save correction", action: save)"#,
                    "AssetRoundsSecondaryAction(\"View prior report\") {\n" +
                        "                    acknowledgeDeliveryFailureIfNeeded(reportID: reportID)\n" +
                        "                    didSelectReport(priorReportID)\n" +
                        "                    dismiss()\n" +
                        "                }\n" +
                        "                .accessibilityHint(\"Opens the immediately prior saved report.\")\n" +
                        "                .accessibilityIdentifier(Self.priorReportAccessibilityIdentifier)",
                    "AssetRoundsSecondaryAction(\"View prior report\") {\n" +
                        "                    didSelectReport(priorReportID)\n" +
                        "                    dismiss()\n" +
                        "                }\n" +
                        "                .accessibilityHint(\"Opens the immediately prior saved report.\")\n" +
                        "                .accessibilityIdentifier(Self.priorReportAccessibilityIdentifier)",
                    "AssetRoundsPrimaryAction(\"View corrected report\") {\n" +
                        "                didSelectReport(currentReportID)\n" +
                        "                dismiss()\n" +
                        "            }",
                ],
                [2, 2, 0, 0, 0],
                0
            ),
            (
                "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
                17_900,
                "09B2B7B3A747A4D8FACD20735B53B5B63FEDEE788613EFA3F26FC622D12FC64F",
                [
                    "AssetRoundsPrimaryAction(\"Share PDF\") {\n" +
                        "                        showsShareSheet = true\n" +
                        "                    }",
                    "AssetRoundsSecondaryAction(\"Save to Files\") {\n" +
                        "                        showsFilesExporter = true\n" +
                        "                    }\n" +
                        "                    .frame(maxWidth: .infinity)\n" +
                        "                    .accessibilityHint(\"Choose a Files destination for an identical copy of this report PDF\")\n" +
                        "                    .accessibilityIdentifier(Self.saveToFilesAccessibilityIdentifier)",
                    "AssetRoundsSecondaryAction(\"Close\") {\n" +
                        "                    dismiss()\n" +
                        "                }",
                    "AssetRoundsSecondaryAction(\"Correct report\") {\n" +
                        "                        activeCorrectionSource = source\n" +
                        "                    }\n" +
                        "                    .accessibilityHint(\"Change only the report note and keep the prior report.\")\n" +
                        "                    .accessibilityIdentifier(Self.correctAccessibilityIdentifier)",
                    "AssetRoundsSecondaryAction(\"View prior report\") {\n" +
                        "                        selectReport(id: prior.reportID)\n" +
                        "                    }",
                    "AssetRoundsSecondaryAction(\"View corrected report\") {\n" +
                        "                        selectReport(id: state.chain.current.reportID)\n" +
                        "                    }",
                ],
                [1, 5, 0, 0, 0],
                0
            ),
            (
                "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
                33_294,
                "63023BB6107A62F0450304F856B8E7CE796B74D4A08E912380C79DF0D75D58BA",
                [
                    "Label(siteFilterLabel, systemImage: \"building.2\")\n" +
                        "        }\n" +
                        "        .buttonStyle(WorklightSecondaryButtonStyle())\n" +
                        "        .accessibilityLabel(siteFilterLabel)",
                    "Label(signFilterLabel, systemImage: \"signpost.right\")\n" +
                        "        }\n" +
                        "        .buttonStyle(WorklightSecondaryButtonStyle())\n" +
                        "        .accessibilityLabel(signFilterLabel)",
                    "NavigationLink(\n" +
                        "                        \"View report\",\n" +
                        "                        value: ReportHistoryRoute.report(visit.reportID)\n" +
                        "                    )\n" +
                        "                    .buttonStyle(WorklightPrimaryButtonStyle())",
                    "NavigationLink(\n" +
                        "                            \"Compare with previous\",\n" +
                        "                            value: ReportHistoryRoute.comparison(visit.stableRootID)\n" +
                        "                        )\n" +
                        "                        .buttonStyle(WorklightSecondaryButtonStyle())",
                ],
                [0, 0, 0, 1, 3],
                0
            ),
            (
                "FieldEvidenceApp/Features/Shell/AppShellView.swift",
                25_864,
                "E6324CBF7BC93564FC05CD9307E01BBC15F161B1970E4B3F231D4EC71F6F9C43",
                [
                    #"AssetRoundsPrimaryNavigationLink("Back up current data") {"#,
                    #"AssetRoundsSecondaryAction("Restore data backup", action: restoreDataBackup)"#,
                    #"AssetRoundsSecondaryAction("View subscription") {"#,
                    #"AssetRoundsSecondaryAction("Restore Purchases") {"#,
                    #"AssetRoundsSecondaryAction("Erase All", action: eraseAllAction.call)"#,
                    "NavigationLink(\"View diagnostics\") {\n" +
                        "                    DiagnosticExportView(",
                    "DiagnosticExportView.settingsEntryAccessibilityIdentifier",
                    "NavigationLink(\"Send feedback\") {\n" +
                        "                    FeedbackView(",
                    "FeedbackView.settingsEntryAccessibilityIdentifier",
                ],
                [0, 4, 1, 0, 2],
                1
            ),
        ]
        let canonicalOwnerMarkers = [
            "AssetRoundsPrimaryAction",
            "AssetRoundsSecondaryAction",
            "AssetRoundsPrimaryNavigationLink",
            ".buttonStyle(WorklightPrimaryButtonStyle())",
            ".buttonStyle(WorklightSecondaryButtonStyle())",
        ]
        for owner in canonicalActionOwners {
            try assertFile(
                owner.path,
                byteCount: owner.byteCount,
                sha256: owner.sha256
            )
            let source = try text(owner.path)
            for fragment in owner.fragments {
                XCTAssertEqual(
                    source.components(separatedBy: fragment).count - 1,
                    1,
                    "\(owner.path): \(fragment)"
                )
            }
            XCTAssertEqual(owner.counts.count, canonicalOwnerMarkers.count)
            for (marker, expectedCount) in zip(canonicalOwnerMarkers, owner.counts) {
                XCTAssertEqual(
                    source.components(separatedBy: marker).count - 1,
                    expectedCount,
                    "\(owner.path): \(marker)"
                )
            }
            for forbidden in [
                ".buttonStyle(.bordered)",
                ".buttonStyle(.borderedProminent)",
                ".buttonStyle(.bordered)\n" +
                    "                .tint(DesignTokens.SemanticColors.primaryAction)",
            ] {
                XCTAssertEqual(
                    source.components(separatedBy: forbidden).count - 1,
                    0,
                    "\(owner.path): \(forbidden)"
                )
            }
            XCTAssertEqual(
                source.components(
                    separatedBy: ".tint(DesignTokens.SemanticColors.primaryAction)"
                ).count - 1,
                owner.primaryTintCount,
                owner.path
            )
        }

        let appShellSourcePath =
            "FieldEvidenceApp/Features/Shell/AppShellView.swift"
        let appShellSource = try text(appShellSourcePath)
        let verbatimColorSchemeSentinel =
            "                .accessibilityValue(\n" +
                "                    Text(\n" +
                "                        verbatim: exposesColorSchemeForUITest\n" +
                #"                            ? (colorScheme == .dark ? "Dark" : "Light")"# +
                "\n" +
                #"                            : """# + "\n" +
                "                    )\n" +
                "                )"
        XCTAssertEqual(
            appShellSource.components(
                separatedBy: verbatimColorSchemeSentinel
            ).count - 1,
            1
        )
        let formerBareColorSchemeSentinel =
            "                .accessibilityValue(\n" +
                "                    exposesColorSchemeForUITest\n" +
                #"                        ? (colorScheme == .dark ? "Dark" : "Light")"# +
                "\n" +
                #"                        : """# + "\n" +
                "                )"
        XCTAssertEqual(
            appShellSource.components(
                separatedBy: formerBareColorSchemeSentinel
            ).count - 1,
            0
        )

        let deleteViewportDiagnosticLocks = [
            #"let runsAXTextDeleteConfirmationDiagnostic ="#,
            #"automationShard?.shardID == "s10.4.current.ax-text""#,
            #"if runsAXTextDeleteConfirmationDiagnostic {"#,
            #"if !runsAXTextDeleteConfirmationDiagnostic {"#,
            "let expectedDeleteMessage =\n" +
                "                \"Delete this sign, its photos, and its reports from this app? \" +\n" +
                "                \"This cannot be undone. Your free-report count will not reset. \" +\n" +
                "                \"Erase All removes the remaining anonymous count.\"",
            "let hasExactDeleteMessage = deleteMessage.exists\n" +
                "                && deleteMessage.label == expectedDeleteMessage",
            "AX-text delete diagnostic requires the exact confirmation message",
            "let hasVisibleHittableDeleteActions =\n" +
                "                cancelDelete.frame.minY >= diagnosticViewportTop\n" +
                "                && cancelDelete.frame.maxY <= diagnosticViewportBottom\n" +
                "                && confirmDelete.frame.minY >= diagnosticViewportTop\n" +
                "                && confirmDelete.frame.maxY <= diagnosticViewportBottom\n" +
                "                && cancelDelete.isHittable\n" +
                "                && confirmDelete.isHittable",
            "AX-text delete diagnostic requires wholly visible, hittable actions",
            "guard hasExactDeleteMessage,\n" +
                "                  hasVisibleHittableDeleteActions else { return }",
            "captureBaseline(deleteConfirmationStateID, in: app)",
        ]
        for lock in deleteViewportDiagnosticLocks {
            XCTAssertTrue(uiSource.contains(lock), lock)
        }
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "state.sign-detail.delete-confirmation"
            ).count - 1,
            2
        )
        let deleteNormalEvidenceLocks = [
            "let eligibleExceptions = Self.contrastAuditExceptionSignatures.filter {",
            "let axTreeDigest = try accessibilityTreeDigest(in: app)",
            #"printJSONLine(prefix: "S10_4_AX_STATE""#,
            #"printJSONLine(prefix: "S10_4_CONTRAST""#,
            "automatedEvidenceIDs.append(",
        ]
        for lock in deleteNormalEvidenceLocks {
            XCTAssertTrue(uiSource.contains(lock), lock)
        }

        let removedCaptureWideDiagnosticFragments = [
            #"            if shard.shardID == "s10.4.current.ax-text","# + "\n" +
                #"               stateID == "state.capture.wide-ready" {"#,
            #"prefix: "S10_4_CAPTURE_WIDE_CONTEXT_DIAGNOSTIC""#,
            #"prefix: "S10_4_CAPTURE_WIDE_AUDIT_DIAGNOSTIC""#,
            #"prefix: "S10_4_CAPTURE_WIDE_AUDIT_COUNT_DIAGNOSTIC""#,
            "S10_4_CAPTURE_WIDE_",
            #"S10.4 AX-text capture-wide diagnostic"#,
            "let diagnosticElements:",
            "for diagnosticElement in diagnosticElements",
            "var liveElements: [[String: Any]] = []",
            "let queryFrames:",
            "throw AutomationConfigurationError.invalid(\n" +
                "                    \"S10.4 AX-text capture-wide diagnostic",
        ]
        for lock in removedCaptureWideDiagnosticFragments {
            XCTAssertEqual(
                uiSource.components(separatedBy: lock).count - 1,
                0,
                lock
            )
        }
        let restoredContrastSetup =
            "            let eligibleExceptions = " +
                "Self.contrastAuditExceptionSignatures.filter {"
        XCTAssertEqual(
            uiSource.components(separatedBy: restoredContrastSetup).count - 1,
            1
        )

        let captureWidePositioningStart =
            #"        if automationShard?.shardID == "s10.4.current.ax-text" {"# +
                "\n" +
                "            let captureScrollViews = app.scrollViews.matching("
        let captureWideReadyCapture =
            #"        captureBaseline("state.capture.wide-ready", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: captureWidePositioningStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: captureWideReadyCapture).count - 1,
            1
        )
        guard let captureWidePositioningStartRange = uiSource.range(
            of: captureWidePositioningStart
        ),
        let captureWideReadyCaptureRange = uiSource.range(
            of: captureWideReadyCapture,
            range: captureWidePositioningStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the sole AX-text capture-wide positioning route")
            return
        }
        let captureWidePositioningSource = String(
            uiSource[
                captureWidePositioningStartRange.lowerBound..<captureWideReadyCaptureRange.lowerBound
            ]
        )

        let captureWideBindingLocks = [
            "            let captureScrollViews = app.scrollViews.matching(\n" +
                "                identifier: \"s3.capture.screen\"\n" +
                "            )",
            "            let captureNavigationBars = app.navigationBars",
            "            let captureTabBars = app.tabBars",
            "            let captureInputViews = app.otherElements.matching(\n" +
                "                NSPredicate(format: \"identifier == %@\", \"inputView\")\n" +
                "            )",
            "            let captureScroll = captureScrollViews.firstMatch",
            "            let captureNavigationBar = captureNavigationBars.firstMatch",
            "            let captureHeadingQuery = app.descendants(matching: .any).matching(\n" +
                "                identifier: \"s3.capture.heading\"\n" +
                "            )",
            "            let takePhotoQuery = app.descendants(matching: .any).matching(\n" +
                "                identifier: \"s3.capture.take-photo\"\n" +
                "            )",
            "            let choosePhotosQuery = app.descendants(matching: .any).matching(\n" +
                "                identifier: \"s3.capture.choose-photos\"\n" +
                "            )",
            "            let cannotCompleteQuery = app.descendants(matching: .any).matching(\n" +
                "                identifier: \"s3.capture.cannot-complete\"\n" +
                "            )",
            "            let importFixtureQuery = app.descendants(matching: .any).matching(\n" +
                "                identifier: \"s3.capture.import-fixture\"\n" +
                "            )",
            "            let capturePreviewQuery = app.descendants(matching: .any).matching(\n" +
                "                identifier: \"s3.capture.preview\"\n" +
                "            )",
            "            let captureHeading = captureHeadingQuery.firstMatch",
            "            let takePhoto = takePhotoQuery.firstMatch",
            "            let choosePhotos = choosePhotosQuery.firstMatch",
            "            let cannotComplete = cannotCompleteQuery.firstMatch",
            "            let importFixture = importFixtureQuery.firstMatch",
            "            let capturePreview = capturePreviewQuery.firstMatch",
        ]
        for lock in captureWideBindingLocks {
            XCTAssertEqual(
                captureWidePositioningSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let captureWideFrozenElements =
            "            let frozenCaptureElements = [\n" +
                "                captureScroll,\n" +
                "                captureNavigationBar,\n" +
                "                captureHeading,\n" +
                "                takePhoto,\n" +
                "                choosePhotos,\n" +
                "                cannotComplete,\n" +
                "                importFixture,\n" +
                "            ]"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideFrozenElements
            ).count - 1,
            1
        )
        let captureWidePrecondition =
            "            guard captureScrollViews.count == 1,\n" +
                "                  captureNavigationBars.count == 1,\n" +
                "                  captureTabBars.count <= 1,\n" +
                "                  captureHeadingQuery.count == 1,\n" +
                "                  takePhotoQuery.count == 1,\n" +
                "                  choosePhotosQuery.count == 1,\n" +
                "                  cannotCompleteQuery.count == 1,\n" +
                "                  importFixtureQuery.count == 1,\n" +
                "                  capturePreviewQuery.count == 0,\n" +
                "                  app.keyboards.count == 0,\n" +
                "                  captureInputViews.count == 0,\n" +
                "                  frozenCaptureElements.allSatisfy({\n" +
                "                      $0.waitForExistence(timeout: 10)\n" +
                "                  }),\n" +
                "                  captureHeading.label == \"1 of 2 · Wide view\",\n" +
                "                  takePhoto.label == \"Take photo\",\n" +
                "                  choosePhotos.label == \"Choose from Photos\",\n" +
                "                  cannotComplete.label == \"Cannot complete\",\n" +
                "                  importFixture.label == \"Import test photo\",\n" +
                "                  !capturePreview.exists,\n" +
                "                  app.state == .runningForeground else {"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWidePrecondition
            ).count - 1,
            1
        )
        let captureWidePrePositionSnapshotLocks = [
            "            let prePositionTabBarCount = captureTabBars.count",
            "            let prePositionCaptureRouteExists = captureScroll.exists",
            "            let prePositionHeadingLabel = captureHeading.label",
            "            let prePositionTakePhotoLabel = takePhoto.label",
            "            let prePositionChoosePhotosLabel = choosePhotos.label",
            "            let prePositionCannotCompleteLabel = cannotComplete.label",
            "            let prePositionImportFixtureLabel = importFixture.label",
            "            let prePositionPreviewExists = capturePreview.exists",
        ]
        for lock in captureWidePrePositionSnapshotLocks {
            XCTAssertEqual(
                captureWidePositioningSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let captureWideGeometryConstants = [
            "            let horizontalInset: CGFloat = 24",
            "            let verticalInset: CGFloat = 16",
            "            let minimumGestureDistance: CGFloat = 44",
            "            for _ in 0..<4 {",
            "                dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)",
        ]
        for lock in captureWideGeometryConstants {
            XCTAssertEqual(
                captureWidePositioningSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let captureWideLiveRouteGuard =
            "                guard captureScrollViews.count == 1,\n" +
                "                      captureNavigationBars.count == 1,\n" +
                "                      captureTabBars.count == prePositionTabBarCount,\n" +
                "                      captureHeadingQuery.count == 1,\n" +
                "                      takePhotoQuery.count == 1,\n" +
                "                      choosePhotosQuery.count == 1,\n" +
                "                      cannotCompleteQuery.count == 1,\n" +
                "                      importFixtureQuery.count == 1,\n" +
                "                      capturePreviewQuery.count == 0,\n" +
                "                      captureScroll.exists,\n" +
                "                      captureNavigationBar.exists,\n" +
                "                      cannotComplete.exists,\n" +
                "                      importFixture.exists,\n" +
                "                      app.keyboards.count == 0,\n" +
                "                      captureInputViews.count == 0,\n" +
                "                      app.state == .runningForeground else {"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideLiveRouteGuard
            ).count - 1,
            1
        )
        let captureWideTabBarBranch =
            "                let liveTabBarTop: CGFloat\n" +
                "                if prePositionTabBarCount == 1 {\n" +
                "                    let tabBar = captureTabBars.firstMatch\n" +
                "                    guard tabBar.exists else {\n" +
                "                        XCTFail(\"AX-text capture-wide TabBar disappeared.\")\n" +
                "                        return\n" +
                "                    }\n" +
                "                    liveTabBarTop = tabBar.frame.minY\n" +
                "                } else {\n" +
                "                    liveTabBarTop = app.frame.maxY\n" +
                "                }"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideTabBarBranch
            ).count - 1,
            1
        )
        let captureWideLiveIntersectionLocks = [
            "                let scrollFrame = captureScroll.frame",
            "                let liveLeft = max(scrollFrame.minX, app.frame.minX)",
            "                let liveRight = min(scrollFrame.maxX, app.frame.maxX)",
            "                let liveTop = max(\n" +
                "                    scrollFrame.minY,\n" +
                "                    max(app.frame.minY, captureNavigationBar.frame.maxY)\n" +
                "                )",
            "                let liveBottom = min(\n" +
                "                    scrollFrame.maxY,\n" +
                "                    min(app.frame.maxY, liveTabBarTop)\n" +
                "                )",
            "                let safeLeft = liveLeft + horizontalInset",
            "                let safeRight = liveRight - horizontalInset",
            "                let safeTop = liveTop + verticalInset",
            "                let safeBottom = liveBottom - verticalInset",
        ]
        for lock in captureWideLiveIntersectionLocks {
            XCTAssertEqual(
                captureWidePositioningSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let captureWideTargetBounds =
            "                let cannotFrame = cannotComplete.frame\n" +
                "                let importFrame = importFixture.frame\n" +
                "                let targetLeft = min(cannotFrame.minX, importFrame.minX)\n" +
                "                let targetRight = max(cannotFrame.maxX, importFrame.maxX)\n" +
                "                let targetTop = min(cannotFrame.minY, importFrame.minY)\n" +
                "                let targetBottom = max(cannotFrame.maxY, importFrame.maxY)"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideTargetBounds
            ).count - 1,
            1
        )
        let captureWideFeasibleInterval =
            "                guard targetLeft >= safeLeft,\n" +
                "                      targetRight <= safeRight,\n" +
                "                      targetBottom - targetTop <= safeBottom - safeTop else {"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideFeasibleInterval
            ).count - 1,
            1
        )
        let captureWideContainedBreak =
            "                let cannotContained = cannotFrame.minY >= safeTop\n" +
                "                    && cannotFrame.maxY <= safeBottom\n" +
                "                let importContained = importFrame.minY >= safeTop\n" +
                "                    && importFrame.maxY <= safeBottom\n" +
                "                if cannotContained && importContained {\n" +
                "                    break\n" +
                "                }"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideContainedBreak
            ).count - 1,
            1
        )
        let captureWideCommonShift =
            "                let minimumShift = max(\n" +
                "                    safeTop - cannotFrame.minY,\n" +
                "                    safeTop - importFrame.minY\n" +
                "                )\n" +
                "                let maximumShift = min(\n" +
                "                    safeBottom - cannotFrame.maxY,\n" +
                "                    safeBottom - importFrame.maxY\n" +
                "                )\n" +
                "                let maximumGestureDistance = liveBottom\n" +
                "                    - liveTop\n" +
                "                    - (2 * verticalInset)\n" +
                "                guard minimumShift <= maximumShift,\n" +
                "                      maximumGestureDistance >= minimumGestureDistance else {"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideCommonShift
            ).count - 1,
            1
        )
        let captureWideNearestZeroShift =
            "                let dragDistance: CGFloat\n" +
                "                if maximumShift < 0 {\n" +
                "                    let recognizedMinimum = max(\n" +
                "                        minimumShift,\n" +
                "                        -maximumGestureDistance\n" +
                "                    )\n" +
                "                    let recognizedMaximum = min(\n" +
                "                        maximumShift,\n" +
                "                        -minimumGestureDistance\n" +
                "                    )\n" +
                "                    guard recognizedMinimum <= recognizedMaximum else {\n" +
                "                        XCTFail(\n" +
                "                            \"AX-text capture-wide upward shift is not recognizable.\"\n" +
                "                        )\n" +
                "                        return\n" +
                "                    }\n" +
                "                    dragDistance = recognizedMaximum\n" +
                "                } else if minimumShift > 0 {\n" +
                "                    let recognizedMinimum = max(\n" +
                "                        minimumShift,\n" +
                "                        minimumGestureDistance\n" +
                "                    )\n" +
                "                    let recognizedMaximum = min(\n" +
                "                        maximumShift,\n" +
                "                        maximumGestureDistance\n" +
                "                    )\n" +
                "                    guard recognizedMinimum <= recognizedMaximum else {\n" +
                "                        XCTFail(\n" +
                "                            \"AX-text capture-wide downward shift is not recognizable.\"\n" +
                "                        )\n" +
                "                        return\n" +
                "                    }\n" +
                "                    dragDistance = recognizedMinimum\n" +
                "                } else {\n" +
                "                    XCTFail(\n" +
                "                        \"AX-text capture-wide feasible shift is directionless.\"\n" +
                "                    )\n" +
                "                    return\n" +
                "                }"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideNearestZeroShift
            ).count - 1,
            1
        )
        for forbidden in [
            "targetDistance",
            "farFeasibleShift",
        ] {
            XCTAssertFalse(captureWidePositioningSource.contains(forbidden), forbidden)
        }
        let captureWideDragSource =
            "                let scrollOrigin = captureScroll.coordinate(\n" +
                "                    withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "                )\n" +
                "                let dragStartOffsetY = dragDistance > 0\n" +
                "                    ? liveTop - scrollFrame.minY + verticalInset\n" +
                "                    : liveBottom - scrollFrame.minY - verticalInset\n" +
                "                let dragStart = scrollOrigin.withOffset(\n" +
                "                    CGVector(\n" +
                "                        dx: scrollFrame.width / 2,\n" +
                "                        dy: dragStartOffsetY\n" +
                "                    )\n" +
                "                )\n" +
                "                let dragEnd = dragStart.withOffset(\n" +
                "                    CGVector(dx: 0, dy: dragDistance)\n" +
                "                )"
        XCTAssertEqual(
            captureWidePositioningSource.components(separatedBy: captureWideDragSource).count - 1,
            1
        )
        let captureWideDualSignProgress =
            "                let cannotBeforeDrag = cannotFrame.minY\n" +
                "                let importBeforeDrag = importFrame.minY\n" +
                "                dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)\n" +
                "                let observedCannotShift = cannotComplete.frame.minY\n" +
                "                    - cannotBeforeDrag\n" +
                "                let observedImportShift = importFixture.frame.minY\n" +
                "                    - importBeforeDrag\n" +
                "                guard observedCannotShift * dragDistance > 0,\n" +
                "                      observedImportShift * dragDistance > 0 else {"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideDualSignProgress
            ).count - 1,
            1
        )
        let captureWideFinalFrames =
            "            let finalTabBarExists = prePositionTabBarCount == 0\n" +
                "                || captureTabBars.firstMatch.waitForExistence(timeout: 10)\n" +
                "            let finalTabBarTop = prePositionTabBarCount == 1\n" +
                "                && finalTabBarExists\n" +
                "                ? captureTabBars.firstMatch.frame.minY\n" +
                "                : app.frame.maxY\n" +
                "            let finalScrollFrame = captureScroll.frame\n" +
                "            let finalSafeLeft = max(\n" +
                "                finalScrollFrame.minX,\n" +
                "                app.frame.minX\n" +
                "            ) + horizontalInset\n" +
                "            let finalSafeRight = min(\n" +
                "                finalScrollFrame.maxX,\n" +
                "                app.frame.maxX\n" +
                "            ) - horizontalInset\n" +
                "            let finalSafeTop = max(\n" +
                "                finalScrollFrame.minY,\n" +
                "                max(app.frame.minY, captureNavigationBar.frame.maxY)\n" +
                "            ) + verticalInset\n" +
                "            let finalSafeBottom = min(\n" +
                "                finalScrollFrame.maxY,\n" +
                "                min(app.frame.maxY, finalTabBarTop)\n" +
                "            ) - verticalInset\n" +
                "            let finalCannotFrame = cannotComplete.frame\n" +
                "            let finalImportFrame = importFixture.frame"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideFinalFrames
            ).count - 1,
            1
        )
        let captureWideFinalContainment = [
            "            let finalCannotContained = finalCannotFrame.minX >= finalSafeLeft\n" +
                "                && finalCannotFrame.maxX <= finalSafeRight\n" +
                "                && finalCannotFrame.minY >= finalSafeTop\n" +
                "                && finalCannotFrame.maxY <= finalSafeBottom",
            "            let finalImportContained = finalImportFrame.minX >= finalSafeLeft\n" +
                "                && finalImportFrame.maxX <= finalSafeRight\n" +
                "                && finalImportFrame.minY >= finalSafeTop\n" +
                "                && finalImportFrame.maxY <= finalSafeBottom",
        ]
        for lock in captureWideFinalContainment {
            XCTAssertEqual(
                captureWidePositioningSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let captureWideFinalGuard =
            "            guard captureScrollViews.count == 1,\n" +
                "                  captureNavigationBars.count == 1,\n" +
                "                  captureTabBars.count == prePositionTabBarCount,\n" +
                "                  captureHeadingQuery.count == 1,\n" +
                "                  takePhotoQuery.count == 1,\n" +
                "                  choosePhotosQuery.count == 1,\n" +
                "                  cannotCompleteQuery.count == 1,\n" +
                "                  importFixtureQuery.count == 1,\n" +
                "                  capturePreviewQuery.count == 0,\n" +
                "                  finalTabBarExists,\n" +
                "                  frozenCaptureElements.allSatisfy({ $0.exists }),\n" +
                "                  captureScroll.exists == prePositionCaptureRouteExists,\n" +
                "                  app.keyboards.count == 0,\n" +
                "                  captureInputViews.count == 0,\n" +
                "                  captureHeading.label == prePositionHeadingLabel,\n" +
                "                  takePhoto.label == prePositionTakePhotoLabel,\n" +
                "                  choosePhotos.label == prePositionChoosePhotosLabel,\n" +
                "                  cannotComplete.label == prePositionCannotCompleteLabel,\n" +
                "                  importFixture.label == prePositionImportFixtureLabel,\n" +
                "                  capturePreview.exists == prePositionPreviewExists,\n" +
                "                  !capturePreview.exists,\n" +
                "                  finalCannotContained,\n" +
                "                  finalImportContained,\n" +
                "                  cannotComplete.isHittable,\n" +
                "                  importFixture.isHittable,\n" +
                "                  app.state == .runningForeground else {"
        XCTAssertEqual(
            captureWidePositioningSource.components(
                separatedBy: captureWideFinalGuard
            ).count - 1,
            1
        )
        let captureWideFailureMessages = [
            "AX-text capture-wide positioning preconditions are incomplete.",
            "AX-text capture-wide live route geometry changed.",
            "AX-text capture-wide TabBar disappeared.",
            "AX-text capture-wide has no inset live viewport.",
            "AX-text capture-wide lower actions cannot fit the inset viewport.",
            "AX-text capture-wide has no feasible recognized shift.",
            "AX-text capture-wide upward shift is not recognizable.",
            "AX-text capture-wide downward shift is not recognizable.",
            "AX-text capture-wide feasible shift is directionless.",
            "AX-text capture-wide positioning gesture was not recognized.",
            "AX-text capture-wide lower actions were not restored fully visible and unchanged.",
        ]
        for message in captureWideFailureMessages {
            XCTAssertEqual(
                captureWidePositioningSource.components(separatedBy: message).count - 1,
                1,
                message
            )
        }
        XCTAssertEqual(
            captureWidePositioningSource.components(separatedBy: "XCTFail(").count - 1,
            11
        )
        XCTAssertEqual(
            captureWidePositioningSource.components(separatedBy: "return").count - 1,
            11
        )
        let captureWideReadyAdjacency =
            "            }\n" +
                "        }\n" +
                captureWideReadyCapture
        XCTAssertEqual(
            uiSource.components(separatedBy: captureWideReadyAdjacency).count - 1,
            1
        )
        for prohibited in [
            "performAccessibilityAudit(",
            "XCTAttachment(",
            "printJSONLine(",
            "attachCandidate(",
            "captureBaseline(",
            "automationContrastExceptions",
            "automationAXTreeDigests",
            "receipt",
            "throw ",
            "tap(",
            "swipe",
            "typeText(",
        ] {
            XCTAssertFalse(captureWidePositioningSource.contains(prohibited), prohibited)
        }

        let reportCorrectionDiagnosticStart =
            "            let reportCorrectionHeaderDiagnosticShardIDs: Set<String> = [\n" +
                "                \"s10.4.current.differentiate-without-color\",\n" +
                "                \"s10.4.current.reduce-motion\",\n" +
                "            ]\n" +
                "            if reportCorrectionHeaderDiagnosticShardIDs.contains(shard.shardID),\n" +
                "               stateID == \"state.report-correction.validation-error\" {"
        let reportCorrectionEligibleExceptions =
            "            let eligibleExceptions = " +
                "Self.contrastAuditExceptionSignatures.filter {"
        XCTAssertEqual(
            uiSource.components(separatedBy: reportCorrectionDiagnosticStart).count - 1,
            1
        )
        guard let reportCorrectionDiagnosticStartRange = uiSource.range(
            of: reportCorrectionDiagnosticStart
        ),
        let reportCorrectionEligibleRange = uiSource.range(
            of: reportCorrectionEligibleExceptions,
            range: reportCorrectionDiagnosticStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the exact two-shard report-correction diagnostic branch")
            return
        }
        let reportCorrectionDiagnostic = String(
            uiSource[
                reportCorrectionDiagnosticStartRange.lowerBound..<reportCorrectionEligibleRange.lowerBound
            ]
        )

        for lock in [
            "reportCorrectionHeaderDiagnosticShardIDs: Set<String> = [",
            "s10.4.current.differentiate-without-color",
            "s10.4.current.reduce-motion",
            "reportCorrectionHeaderDiagnosticShardIDs.contains(shard.shardID)",
            #"stateID == "state.report-correction.validation-error""#,
        ] {
            XCTAssertEqual(
                reportCorrectionDiagnostic.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for prohibitedShardID in [
            "s10.4.current.default-light",
            "s10.4.current.default-dark",
            "s10.4.current.increased-contrast",
        ] {
            XCTAssertFalse(
                reportCorrectionDiagnostic.contains(prohibitedShardID),
                prohibitedShardID
            )
        }

        let reportCorrectionPassiveBindings = [
            "                let headerElements = app.descendants(matching: .any).matching(\n" +
                "                    identifier: \"s4.5.correction.header\"\n" +
                "                )",
            "                let header = headerElements.firstMatch",
            "                guard headerElements.count == 1,\n" +
                "                      header.exists,\n" +
                "                      header.label == \"Correct report\",\n" +
                "                      header.elementType == .staticText else {",
            "                let correctionScrollViews = app.scrollViews.containing(\n" +
                "                    .button,\n" +
                "                    identifier: \"s4.5.correction.save\"\n" +
                "                )",
            "                let navigationBars = app.navigationBars",
            "                let validationElements = app.descendants(matching: .any).matching(\n" +
                "                    identifier: \"s4.5.correction.validation\"\n" +
                "                )",
            "                let saveElements = app.descendants(matching: .any).matching(\n" +
                "                    identifier: \"s4.5.correction.save\"\n" +
                "                )",
            "                let keyboards = app.keyboards",
            "                let inputViews = app.otherElements.matching(\n" +
                "                    NSPredicate(format: \"identifier == %@\", \"inputView\")\n" +
                "                )",
            "                let tabBars = app.tabBars",
        ]
        for lock in reportCorrectionPassiveBindings {
            XCTAssertEqual(
                reportCorrectionDiagnostic.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let reportCorrectionFrameObject =
            "                let diagnosticFrameObject: (CGRect) -> [String: Any] = { frame in\n" +
                "                    [\n" +
                "                        \"shardID\": shard.shardID,\n" +
                "                        \"x\": Double(frame.origin.x),\n" +
                "                        \"y\": Double(frame.origin.y),\n" +
                "                        \"width\": Double(frame.size.width),\n" +
                "                        \"height\": Double(frame.size.height),\n" +
                "                    ]\n" +
                "                }"
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(
                separatedBy: reportCorrectionFrameObject
            ).count - 1,
            1
        )
        let reportCorrectionElementObject =
            "                let diagnosticElementObject: (XCUIElement) -> [String: Any] = {\n" +
                "                    element in\n" +
                "                    [\n" +
                "                        \"shardID\": shard.shardID,\n" +
                "                        \"identifier\": element.identifier,\n" +
                "                        \"label\": element.label,\n" +
                "                        \"elementType\": String(describing: element.elementType),\n" +
                "                        \"frame\": diagnosticFrameObject(element.frame),\n" +
                "                        \"exists\": element.exists,\n" +
                "                        \"isHittable\": element.isHittable,\n" +
                "                    ]\n" +
                "                }"
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(
                separatedBy: reportCorrectionElementObject
            ).count - 1,
            1
        )
        let reportCorrectionQueryObject =
            "                let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {\n" +
                "                    query in\n" +
                "                    let cardinality = query.count\n" +
                "                    return [\n" +
                "                        \"shardID\": shard.shardID,\n" +
                "                        \"cardinality\": cardinality,\n" +
                "                        \"elements\": (0..<cardinality).map { index in\n" +
                "                            diagnosticElementObject(query.element(boundBy: index))\n" +
                "                        },\n" +
                "                    ]\n" +
                "                }"
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(
                separatedBy: reportCorrectionQueryObject
            ).count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(
                separatedBy: #""shardID": shard.shardID,"#
            ).count - 1,
            6
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "query.count").count - 1,
            1
        )

        let reportCorrectionContextObject =
            "                printJSONLine(\n" +
                "                    prefix: \"S10_4_REPORT_CORRECTION_HEADER_CONTEXT_DIAGNOSTIC\",\n" +
                "                    object: [\n" +
                "                        \"shardID\": shard.shardID,\n" +
                "                        \"application\": diagnosticElementObject(app),\n" +
                "                        \"header\": diagnosticQueryObject(headerElements),\n" +
                "                        \"reportCorrectionScrollView\": diagnosticQueryObject(\n" +
                "                            correctionScrollViews\n" +
                "                        ),\n" +
                "                        \"navigationBar\": diagnosticQueryObject(navigationBars),\n" +
                "                        \"validation\": diagnosticQueryObject(validationElements),\n" +
                "                        \"save\": diagnosticQueryObject(saveElements),\n" +
                "                        \"keyboard\": diagnosticQueryObject(keyboards),\n" +
                "                        \"inputView\": diagnosticQueryObject(inputViews),\n" +
                "                        \"tabBar\": diagnosticQueryObject(tabBars),\n" +
                "                    ]\n" +
                "                )"
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(
                separatedBy: reportCorrectionContextObject
            ).count - 1,
            1
        )

        let reportCorrectionAttachmentLocks = [
            "                let attachmentPrefix =\n" +
                "                    \"S10.4 \\(shard.shardID) Report-correction-header diagnostic\"",
            "                let appAttachment = XCTAttachment(screenshot: app.screenshot())",
            "                appAttachment.name = \"\\(attachmentPrefix) app\"",
            "                add(appAttachment)",
            "                let treeAttachment = XCTAttachment(string: app.debugDescription)",
            "                treeAttachment.name = \"\\(attachmentPrefix) accessibility tree\"",
            "                add(treeAttachment)",
            "                let headerAttachment = XCTAttachment(screenshot: header.screenshot())",
            "                headerAttachment.name = \"\\(attachmentPrefix) header\"",
            "                add(headerAttachment)",
            "                        let attachment = XCTAttachment(\n" +
                "                            screenshot: auditedElement.screenshot()\n" +
                "                        )",
            "                            \"\\(attachmentPrefix) audit issue \\(observedIssueCount)\"",
            "                        self.add(attachment)",
        ]
        for lock in reportCorrectionAttachmentLocks {
            XCTAssertEqual(
                reportCorrectionDiagnostic.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "XCTAttachment(").count - 1,
            4
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "lifetime = .keepAlways").count - 1,
            4
        )

        let reportCorrectionIssueFields = [
            "                var observedIssueCount = 0",
            "                    observedIssueCount += 1",
            "                try app.performAccessibilityAudit(for: .contrast) { issue in",
            "                        \"issueOrdinal\": observedIssueCount,",
            "                        \"auditTypeRawValue\": String(issue.auditType.rawValue),",
            "                        \"compactDescription\": issue.compactDescription,",
            "                        \"detailedDescription\": issue.detailedDescription,",
            "                        \"elementIdentifier\": NSNull(),",
            "                        \"elementLabel\": NSNull(),",
            "                        \"elementType\": NSNull(),",
            "                        \"elementFrame\": NSNull(),",
            "                        \"applicationFrame\": diagnosticFrameObject(app.frame),",
            "                    if let auditedElement = issue.element {",
            "                        diagnostic[\"elementIdentifier\"] = auditedElement.identifier",
            "                        diagnostic[\"elementLabel\"] = auditedElement.label",
            "                        diagnostic[\"elementType\"] = String(\n" +
                "                            describing: auditedElement.elementType\n" +
                "                        )",
            "                        diagnostic[\"elementFrame\"] = diagnosticFrameObject(\n" +
                "                            auditedElement.frame\n" +
                "                        )",
            "                    self.printJSONLine(\n" +
                "                        prefix: \"S10_4_REPORT_CORRECTION_HEADER_AUDIT_DIAGNOSTIC\",\n" +
                "                        object: diagnostic\n" +
                "                    )",
        ]
        for lock in reportCorrectionIssueFields {
            XCTAssertEqual(
                reportCorrectionDiagnostic.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "NSNull()").count - 1,
            4
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "return true").count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "return false").count - 1,
            0
        )

        let reportCorrectionAuditCount =
            "                printJSONLine(\n" +
                "                    prefix: \"S10_4_REPORT_CORRECTION_HEADER_AUDIT_COUNT_DIAGNOSTIC\",\n" +
                "                    object: [\n" +
                "                        \"shardID\": shard.shardID,\n" +
                "                        \"issueCount\": observedIssueCount,\n" +
                "                    ]\n" +
                "                )"
        let reportCorrectionTerminal =
            reportCorrectionAuditCount + "\n" +
                "                throw AutomationConfigurationError.invalid(\n" +
                "                    \"S10.4 \\(shard.shardID) Report-correction-header diagnostic completed nonaccepting\"\n" +
                "                )"
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: reportCorrectionAuditCount).count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: reportCorrectionTerminal).count - 1,
            1
        )
        let reportCorrectionTerminalBeforeEligible =
            reportCorrectionTerminal + "\n            }\n\n" +
                reportCorrectionEligibleExceptions
        XCTAssertEqual(
            uiSource.components(separatedBy: reportCorrectionTerminalBeforeEligible).count - 1,
            1
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(separatedBy: "printJSONLine(").count - 1,
            3
        )
        XCTAssertEqual(
            reportCorrectionDiagnostic.components(
                separatedBy: "throw AutomationConfigurationError.invalid("
            ).count - 1,
            2
        )
        for prohibited in [
            ".tap(",
            ".swipe",
            ".press(",
            ".coordinate(",
            ".typeText(",
            "scroll(",
            "navigateBack(",
            "setToggle(",
            "app.launch",
            "app.terminate",
            "migratedStateIDs.append",
            "captureBaseline(",
            "automationContrastExceptions",
            "automationAXTreeDigests",
            #"prefix: "S10_4_AX_STATE""#,
            #"prefix: "S10_4_CONTRAST""#,
            #"prefix: "S10_4_AX""#,
            "automatedEvidenceIDs.append(",
            "attachCandidate(",
            "let candidate = XCTAttachment(",
            "eligibleExceptions",
            "matchedExceptions",
            "stateIssueLimit",
            "CGRect(",
            "frame ==",
            "expectedHeaderFrame",
            "expectedIssueFrame",
            "Thread.sleep",
            "receipt",
            "retention",
        ] {
            XCTAssertFalse(reportCorrectionDiagnostic.contains(prohibited), prohibited)
        }

        let exceptionIDs = [
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-WIDE-VIEW",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-CUSTOMER-SITE-NAME",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-BEFORE-YOU-BEGIN",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-FEEDBACK-PRIVACY",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER",
        ]
        let exceptionRationales = [
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Wide view even though the audit-owned crop visibly renders white text on the dark elevated Sample card; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Customer / site name even though the audit-owned crop visibly renders black text on white and the public node is bound to the top navigation-region frame; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Before you begin while the frozen public node frame is bottom-clipped outside the 402x874 application frame in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the I confirm this is the site's time zone label even though the audit-owned crop contains only the iOS keyboard and the frozen public node frame is fully keyboard-occluded in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Feedback privacy copy while the frozen public node frame is top-clipped outside the 402x874 application frame and its remaining slice is bound to native status/navigation chrome; the live Feedback composition simultaneously preserves the frozen App-metadata and Save-diagnostics clearances, and the audit-owned crop confirms that unobscured primaryText renders white on the dark elevated surface; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in default light even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in default dark even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in increased contrast even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
        ]
        for lock in exceptionIDs {
            XCTAssertEqual(uiSource.components(separatedBy: lock).count - 1, 1, lock)
            let workflowCount = lock.contains("REPORT-CORRECTION-HEADER") ? 4 : 2
            XCTAssertEqual(
                workflowSource.components(separatedBy: lock).count - 1,
                workflowCount,
                lock
            )
        }
        for lock in exceptionRationales {
            XCTAssertEqual(uiSource.components(separatedBy: lock).count - 1, 1, lock)
            XCTAssertEqual(workflowSource.components(separatedBy: lock).count - 1, 1, lock)
        }
        let uiExceptionStateCounts = [
            ("state.check-preflight.ready", 2),
            ("state.new-sign.editing", 1),
            ("state.sample-report.ready", 1),
            ("state.feedback.review-ready", 1),
            ("state.report-correction.validation-error", 3),
        ]
        for (stateID, expectedCount) in uiExceptionStateCounts {
            let lock = #"stateID: "\#(stateID)""#
            XCTAssertEqual(
                uiSource.components(separatedBy: lock).count - 1,
                expectedCount,
                lock
            )
        }
        XCTAssertEqual(
            uiSource.components(separatedBy: "ContrastAuditExceptionSignature(").count - 1,
            8
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"issueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            8
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            16
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"owner: "palatis3""#).count - 1,
            8
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionOwner: "palatis3""#)
                .count - 1,
            8
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"expiresAt: "2026-11-20""#).count - 1,
            8
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionExpiresAt: "2026-11-20""#)
                .count - 1,
            8
        )

        let signatureLocks = [
            #"taskID: "report_comprehension""#,
            #"taskID: "one_handed_start""#,
            #"taskID: "history_recovery""#,
            #"elementLabel: "Wide view""#,
            #"elementLabel: "Customer / site name""#,
            #"elementLabel: "Before you begin""#,
            #"elementLabel: "I confirm this is the site's time zone.""#,
            #"elementIdentifier: "s8.4.feedback.privacy""#,
            #"elementLabel: "Your message stays editable. Only app version, build, device model, and iOS version are prefilled; customer and inspection content is never prefilled.""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.default-light""#,
            #"shardID: "s10.4.current.increased-contrast""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"elementIdentifier: "s4.5.correction.header""#,
            #"elementLabel: "Correct report""#,
            #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
            "x: 32,\n                y: 111.33333587646484,\n" +
                "                width: 248,\n                height: 40.666664123535156",
            "y: 810.33333333333337",
            "height: 20.333333333333258",
            "width: 251.66666666666663",
            "height: 116.66666666666663",
            "y: 844.33333333333337",
            "width: 231",
            "height: 125.33333333333326",
            "y: 547",
            "width: 238.33333333333331",
            "height: 249.33333333333337",
            "y: -34.333333333333343",
            "width: 298.33333333333331",
            "height: 86.333333333333343",
            "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
        ]
        for lock in signatureLocks {
            XCTAssertTrue(uiSource.contains(lock), lock)
        }
        let workflowSignatureLocks = [
            #"--arg timeZoneLabel "I confirm this is the site's time zone.""#,
            #"--arg timeZoneRationale "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue"#,
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: """#,
            #"elementLabel: "Before you begin""#,
            #"elementLabel: $timeZoneLabel"#,
            #"elementIdentifier: "s8.4.feedback.privacy""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.default-light""#,
            #"shardID: "s10.4.current.increased-contrast""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"elementIdentifier: "s4.5.correction.header""#,
            #"elementLabel: "Correct report""#,
            #"elementType: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: {\n" +
                "                      x: 32,\n" +
                "                      y: 111.33333587646484,\n" +
                "                      width: 248,\n" +
                "                      height: 40.666664123535156\n" +
                "                    }",
            "y: 844.33333333333337",
            "width: 231",
            "height: 125.33333333333326",
            "y: 547",
            "width: 238.33333333333331",
            "height: 249.33333333333337",
            "y: -34.333333333333343",
            "width: 298.33333333333331",
            "height: 86.333333333333343",
            "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        for lock in workflowSignatureLocks {
            XCTAssertTrue(workflowSource.contains(lock), lock)
        }

        let defaultLightUIAuthorityStart =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER","#
        let defaultLightUIAuthorityEnd =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER","#
        guard let defaultLightUIAuthorityStartRange = uiSource.range(
            of: defaultLightUIAuthorityStart
        ),
        let defaultLightUIAuthorityEndRange = uiSource.range(
            of: defaultLightUIAuthorityEnd,
            range: defaultLightUIAuthorityStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the exact default-light UI contrast authority")
            return
        }
        let defaultLightUIAuthority = String(
            uiSource[
                defaultLightUIAuthorityStartRange.lowerBound..<defaultLightUIAuthorityEndRange.lowerBound
            ]
        )
        let defaultLightWorkflowAuthorityStart =
            "              {\n" +
                #"                shardID: "s10.4.current.default-light","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER","#
        let defaultLightWorkflowAuthorityEnd =
            "              {\n" +
                #"                shardID: "s10.4.current.default-dark","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER","#
        guard let defaultLightWorkflowAuthorityStartRange = workflowSource.range(
            of: defaultLightWorkflowAuthorityStart
        ),
        let defaultLightWorkflowAuthorityEndRange = workflowSource.range(
            of: defaultLightWorkflowAuthorityEnd,
            range: defaultLightWorkflowAuthorityStartRange.upperBound..<workflowSource.endIndex
        ) else {
            XCTFail("Missing the exact default-light workflow contrast authority")
            return
        }
        let defaultLightWorkflowAuthority = String(
            workflowSource[
                defaultLightWorkflowAuthorityStartRange.lowerBound..<defaultLightWorkflowAuthorityEndRange.lowerBound
            ]
        )
        let defaultLightRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue " +
                "for the identified Correct report header in default light even though " +
                "the audit-owned crop visibly renders the complete header unobscured " +
                "and wholly above the keyboard; the exception is limited to the frozen " +
                "public issue signature."
        let defaultLightUIAuthorityLocks = [
            #"shardID: "s10.4.current.default-light""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"owner: "palatis3""#,
            #"expiresAt: "2026-11-20""#,
            "rationale: \"" + defaultLightRationale + "\"",
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: "s4.5.correction.header""#,
            #"elementLabel: "Correct report""#,
            #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: CGRect(\n" +
                "                x: 32,\n" +
                "                y: 111.33333587646484,\n" +
                "                width: 248,\n" +
                "                height: 40.666664123535156\n" +
                "            )",
            "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
        ]
        let defaultLightWorkflowAuthorityLocks = [
            #"shardID: "s10.4.current.default-light""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"exceptionOwner: "palatis3""#,
            #"exceptionExpiresAt: "2026-11-20""#,
            "exceptionRationale: \"" + defaultLightRationale + "\"",
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: "s4.5.correction.header""#,
            #"elementLabel: "Correct report""#,
            #"elementType: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: {\n" +
                "                      x: 32,\n" +
                "                      y: 111.33333587646484,\n" +
                "                      width: 248,\n" +
                "                      height: 40.666664123535156\n" +
                "                    }",
            "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        for lock in defaultLightUIAuthorityLocks {
            XCTAssertEqual(
                defaultLightUIAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for lock in defaultLightWorkflowAuthorityLocks {
            XCTAssertEqual(
                defaultLightWorkflowAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let failClosedHandlerLocks = [
            "private var automationContrastExceptions: [String: [ContrastAuditExceptionSignature]] = [:]",
            "let eligibleExceptions = Self.contrastAuditExceptionSignatures.filter {",
            "let stateIssueLimit =",
            #"shard.shardID == "s10.4.current.ax-text""#,
            #"&& stateID == "state.check-preflight.ready" ? 2 : 1"#,
            "guard eligibleExceptions.count <= stateIssueLimit else",
            "var matchedExceptions: [ContrastAuditExceptionSignature] = []",
            "if !eligibleExceptions.isEmpty",
            "var observedIssueCount = 0",
            "observedIssueCount += 1",
            "guard observedIssueCount <= stateIssueLimit,",
            "let auditedElement = issue.element else",
            "let matchingExceptions = eligibleExceptions.filter { signature in",
            "self.isActive(signature)",
            "String(issue.auditType.rawValue)",
            "== signature.auditTypeRawValue",
            "issue.compactDescription == signature.compactDescription",
            "issue.detailedDescription == signature.detailedDescription",
            "auditedElement.identifier == signature.elementIdentifier",
            "auditedElement.label == signature.elementLabel",
            "== signature.elementTypeDescription",
            "auditedElement.frame == signature.elementFrame",
            "app.frame == signature.applicationFrame",
            "guard matchingExceptions.count == 1,",
            "let matchedException = matchingExceptions.first,",
            "!matchedExceptions.contains(where:",
            "$0.issueID == matchedException.issueID",
            "matchedExceptions.append(matchedException)",
            "guard observedIssueCount == matchedExceptions.count,",
            "observedIssueCount <= stateIssueLimit else",
            "matchedExceptions.sort { $0.issueID < $1.issueID }",
            #"Set(matchedExceptions.map(\.issueID)).count == matchedExceptions.count"#,
            "matchedExceptions.allSatisfy({ $0.stateID == stateID })",
            "matchedExceptions.allSatisfy({ isActive($0) })",
            "formatter.string(from: Date()) <= signature.expiresAt",
        ]
        for lock in failClosedHandlerLocks {
            XCTAssertTrue(uiSource.contains(lock), lock)
        }
        XCTAssertTrue(uiSource.contains("matchedExceptions.append(matchedException)\n                    return true"))
        XCTAssertTrue(uiSource.contains(#""result": matchedExceptions.isEmpty ? "PASS" : "EXCEPTION""#))
        XCTAssertTrue(uiSource.contains(#""ignoredAuditIssues": matchedExceptions.map"#))
        XCTAssertTrue(uiSource.contains(#""result": "PASS""#))
        XCTAssertTrue(uiSource.contains("if !matchedExceptions.isEmpty {\n                automationContrastExceptions[stateID] = matchedExceptions"))
        XCTAssertTrue(uiSource.contains("contrastEvidence[\"exceptionIssueID\"] = matchedExceptions"))
        XCTAssertTrue(uiSource.contains(".joined(separator: \" | \")"))
        XCTAssertFalse(uiSource.contains("observedIssueCount == eligibleExceptions.count"))
        XCTAssertFalse(uiSource.contains("var matchedException: ContrastAuditExceptionSignature?"))
        XCTAssertTrue(uiSource.contains(#""automatedStatus": taskExceptions.isEmpty ? "PASS" : "EXCEPTION""#))
        let taskExceptionLocks = [
            #".flatMap { $0 }"#,
            #".filter { $0.taskID == task.taskID }"#,
            #"if $0.stateID == $1.stateID {"#,
            #"return $0.issueID < $1.issueID"#,
            #"let taskIssueLimit: Int"#,
            #"let taskStateLimit: Int"#,
            #"let permittedExceptionStateIDs: Set<String>"#,
            #"switch (shard.shardID, task.taskID)"#,
            #"case ("s10.4.current.ax-text", "one_handed_start")"#,
            #"taskIssueLimit = 3"#,
            #"taskStateLimit = 2"#,
            #"case ("s10.4.current.default-light", "report_comprehension")"#,
            #"taskIssueLimit = 1"#,
            #"taskStateLimit = 1"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.report-correction.validation-error","# + "\n" +
                #"                ]"#,
            #"case ("s10.4.current.default-dark", "report_comprehension")"#,
            #"taskIssueLimit = 2"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.report-correction.validation-error","# + "\n" +
                #"                    "state.sample-report.ready","# + "\n" +
                #"                ]"#,
            #"case ("s10.4.current.increased-contrast", "report_comprehension")"#,
            #"taskIssueLimit = 1"#,
            #"taskStateLimit = 1"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.report-correction.validation-error","# + "\n" +
                #"                ]"#,
            #"case ("s10.4.current.default-dark", "history_recovery")"#,
            #"permittedExceptionStateIDs = ["state.feedback.review-ready"]"#,
            #"guard taskExceptions.count <= taskIssueLimit else"#,
            #"A common task exceeded its exact contrast exception limit"#,
            #"let exceptionStateIDs = Array(Set(taskExceptions.map(\.stateID))).sorted()"#,
            #"let exceptionIssueIDs = taskExceptions.map(\.issueID)"#,
            #"let expectedUniqueMetadataCount = taskExceptions.isEmpty ? 0 : 1"#,
            #"guard exceptionStateIDs.count <= taskStateLimit"#,
            #"Set(exceptionStateIDs).isSubset(of: permittedExceptionStateIDs)"#,
            #"Set(exceptionIssueIDs).count == exceptionIssueIDs.count"#,
            #"Set(taskExceptions.map(\.owner)).count"#,
            #"== expectedUniqueMetadataCount"#,
            #"Set(taskExceptions.map(\.expiresAt)).count"#,
            #"taskExceptions.allSatisfy({ task.stateIDs.contains($0.stateID) })"#,
            #"taskExceptions.allSatisfy({ isActive($0) })"#,
            #"!(automationAXTreeDigests[$0.stateID] ?? "").isEmpty"#,
            #"A common task has ambiguous, expired, or missing contrast exception evidence"#,
            #"automatedEvidenceIDs.append(contentsOf: exceptionStateIDs.map {"#,
            #""s10.4-contrast-\(shard.shardID)-\($0)""#,
            #"taskEvidence["exceptionIssueID"] = exceptionIssueIDs.joined("#,
            #"separator: " | ""#,
            #"taskEvidence["exceptionOwner"] = firstTaskException.owner"#,
            #"taskEvidence["exceptionExpiresAt"] = firstTaskException.expiresAt"#,
            #"taskEvidence["exceptionRationale"] = taskExceptions"#,
            #".joined(separator: " | ")"#,
            #"taskEvidence["exceptionStateIDs"] = exceptionStateIDs"#,
            #"the sole Apple contrast issue is bound to the named, expiring exception."#,
            #"the exact Apple contrast issues are bound to the named, expiring exceptions."#,
        ]
        for lock in taskExceptionLocks {
            XCTAssertTrue(uiSource.contains(lock), lock)
        }
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"case ("s10.4.current.default-light""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"case ("s10.4.current.default-dark""#
            ).count - 1,
            2,
            "The three default-dark authorities must remain bounded across two tasks"
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"case ("s10.4.current.increased-contrast""#
            ).count - 1,
            1
        )
        let defaultLightTaskExceptionBound =
            #"            case ("s10.4.current.default-light", "report_comprehension"):"# +
                "\n" +
                "                taskIssueLimit = 1\n" +
                "                taskStateLimit = 1\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.report-correction.validation-error","# +
                "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: defaultLightTaskExceptionBound
            ).count - 1,
            1
        )
        for removedFeedbackDiagnostic in [
            "enumerateFeedbackContrastAuditIssues",
            "S10_4_AUDIT_DIAGNOSTIC",
            "S10.4 Feedback diagnostic",
        ] {
            XCTAssertFalse(uiSource.contains(removedFeedbackDiagnostic))
        }

        let workflowProtocolLocks = [
            "contrast_exception_authority_path=",
            #"if .result == "PASS" then"#,
            #"elif .result == "EXCEPTION" then"#,
            #"length == 8"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 7"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 8"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 6"#,
            #"| select(.exceptionIssueID | IN("#,
            #""S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER""#,
            #"| (.ignoredAuditIssues[0] | tojson)] | unique | length) == 1"#,
            #"| select((.exceptionIssueID | IN("#,
            #")) | not)"#,
            #"| (.ignoredAuditIssues[0] | tojson)] | unique | length) == 5"#,
            #"and (.exceptionOwner == "palatis3")"#,
            #"and (.exceptionExpiresAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))"#,
            #"and ($today <= .exceptionExpiresAt)"#,
            #"and (.ignoredAuditIssues | type == "array" and length == 1)"#,
            #"def expectedExceptionEvidence($matched):"#,
            #"ignoredAuditIssues: ($matched | map(.ignoredAuditIssues[0]))"#,
            #"def matchedStateAuthorities($row; $authorities; $today):"#,
            #"($row.ignoredAuditIssues // []) as $observedIssues"#,
            #"error("contrast exception state has no observed issues")"#,
            #"[$observedIssues[] as $observedIssue"#,
            #".ignoredAuditIssues[0] == $observedIssue"#,
            #"error("unmatched or ambiguous contrast exception issue")"#,
            #"] | sort_by(.exceptionIssueID)) as $matched"#,
            #"error("duplicate contrast exception issue")"#,
            #"error("noncanonical contrast exception issue order")"#,
            #"error("contrast exception owner or expiry is ambiguous")"#,
            #"error("expired or malformed contrast exception authority")"#,
            #"error("contrast exception state aggregate drift")"#,
            #"| map(select(.result == "EXCEPTION"))"#,
            #"| sort_by(.stateID)) as $stateExceptions"#,
            #"error("duplicate contrast exception state")"#,
            #"error("contrast exception state-to-issue cardinality drift")"#,
            #"error("contrast exception per-state issue limit exceeded")"#,
            #"error("default-light contrast exception bound exceeded")"#,
            #"error("default-dark contrast exception bound exceeded")"#,
            #"error("AX-text contrast exception bound exceeded")"#,
            #"error("contrast exception on ineligible shard")"#,
            #"def taskIssueLimit($shardID; $taskID):"#,
            #"and $taskID == "one_handed_start" then 3"#,
            #"and $taskID == "report_comprehension" then 2"#,
            #"and $taskID == "history_recovery" then 1"#,
            #"and $taskID == "report_comprehension" then 1"#,
            #"def taskStateLimit($shardID; $taskID):"#,
            #"and $taskID == "one_handed_start" then 2"#,
            #"| map(select(.taskID == $taskID))"#,
            #"| sort_by(.stateID, .exceptionIssueID)) as $taskExceptions"#,
            #"| map(.stateID) | unique | sort) as $taskExceptionStateIDs"#,
            #"| ($taskExceptions | map(.exceptionOwner) | unique) as $exceptionOwners"#,
            #"| ($taskExceptions | map(.exceptionExpiresAt) | unique) as $exceptionExpiries"#,
            #"(.automatedStatus == "EXCEPTION")"#,
            #"(.automatedStatus == "PASS")"#,
            #"+ ($taskExceptionStateIDs | map("#,
            #""s10.4-contrast-" + $shard + "-" + ."#,
            #"| map(.exceptionIssueID) | join(" | "))"#,
            #"and ($exceptionOwners | length) == 1"#,
            #"and (.exceptionOwner == $exceptionOwners[0])"#,
            #"and ($exceptionExpiries | length) == 1"#,
            #"and (.exceptionExpiresAt == $exceptionExpiries[0])"#,
            #"| map(.exceptionRationale) | join(" | "))"#,
            #"and (.exceptionStateIDs == $taskExceptionStateIDs)"#,
            "the sole Apple contrast issue is bound to the named, expiring exception.",
            "the exact Apple contrast issues are bound to the named, expiring exceptions.",
            #"and all($taskExceptionStateIDs[];"#,
            #"| index($exceptionStateID)) != null"#,
            #"if $shard == "s10.4.current.default-light" then"#,
            #"if $shard == "s10.4.current.default-dark" then"#,
            #"($matchedAuthorities | length) > 3"#,
            #"($matchedExceptionStateIDs | length) > 3"#,
            #"elif $shard == "s10.4.current.increased-contrast""#,
            #"($matchedAuthorities | length) > 1"#,
            #"($matchedExceptionStateIDs | length) > 1"#,
            #"elif $shard == "s10.4.current.ax-text" then"#,
            #"($matchedAuthorities | length) > 3"#,
            #"stateIssueLimit($shardID; $stateID)"#,
            #"and $stateID == "state.check-preflight.ready" then 2"#,
            #"and $stateID == "state.new-sign.editing" then 1"#,
            #"and ($stateID == "state.feedback.review-ready""#,
            #"or $stateID == "state.report-correction.validation-error""#,
            #"or $stateID == "state.sample-report.ready") then 1"#,
            #"and $stateID == "state.report-correction.validation-error" then 1"#,
            #"matchedStateAuthorities($row; $exceptions[0]; $today) as $matched"#,
            #"($matched | length) > 0"#,
            #"<= stateIssueLimit($row.shardID; $row.stateID)"#,
            "strict Apple contrast evidence.",
        ]
        for lock in workflowProtocolLocks {
            XCTAssertTrue(workflowSource.contains(lock), lock)
        }
        let workflowHeaderSharedOneAndHistoricalFive =
            "            and ([.[]\n" +
                "              | select(.exceptionIssueID | IN(\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER\"\n" +
                "                ))\n" +
                "              | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 1\n" +
            "            and ([.[]\n" +
                "              | select((.exceptionIssueID | IN(\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER\"\n" +
                "                )) | not)\n" +
                "              | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 5"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: workflowHeaderSharedOneAndHistoricalFive
            ).count - 1,
            1
        )
        let defaultLightWorkflowTaskIssueBound =
            #"                elif $shardID == "s10.4.current.default-light""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: defaultLightWorkflowTaskIssueBound
            ).count - 1,
            2
        )
        let defaultLightWorkflowStateIssueBound =
            #"                elif $shardID == "s10.4.current.default-light""# + "\n" +
                #"                     and $stateID == "state.report-correction.validation-error" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: defaultLightWorkflowStateIssueBound
            ).count - 1,
            1
        )
        let defaultLightWorkflowAggregateBound =
            #"                 elif $shard == "s10.4.current.default-light""# + "\n" +
                #"                      and (($matchedAuthorities | length) > 1"# + "\n" +
                #"                        or ($matchedExceptionStateIDs | length) > 1) then"# +
                "\n" +
                #"                   error("default-light contrast exception bound exceeded")"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: defaultLightWorkflowAggregateBound
            ).count - 1,
            1
        )
        let defaultLightWorkflowEligibility =
            #"                 elif $shard != "s10.4.current.default-light""# + "\n" +
                #"                      and $shard != "s10.4.current.default-dark""#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: defaultLightWorkflowEligibility
            ).count - 1,
            1
        )
        let defaultLightWorkflowDownstreamBound =
            #"                      if $shard == "s10.4.current.default-light" then"# + "\n" +
                #"                        ($matchedAuthorities | length) <= 1"# + "\n" +
                #"                        and ($matchedExceptionStateIDs | length) <= 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: defaultLightWorkflowDownstreamBound
            ).count - 1,
            1
        )
        let axWorkflowAggregateBound =
            #"elif $shard == "s10.4.current.ax-text""# + "\n" +
                #"                      and (($matchedAuthorities | length) > 3"# + "\n" +
                #"                        or ($matchedExceptionStateIDs | length) > 2) then"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowAggregateBound).count - 1,
            1
        )
        for staleLock in [
            #"length == 7"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 6"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 7"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 4"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 5"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 5"#,
            #"($matchedAuthorities | length) > 2"#,
        ] {
            XCTAssertFalse(workflowSource.contains(staleLock), staleLock)
        }
        for twiceLocked in [
            #"def expectedExceptionEvidence($matched):"#,
            #"def matchedStateAuthorities($row; $authorities; $today):"#,
            #"error("unmatched or ambiguous contrast exception issue")"#,
            #"error("duplicate contrast exception issue")"#,
            #"error("noncanonical contrast exception issue order")"#,
            #"error("contrast exception owner or expiry is ambiguous")"#,
            #"error("expired or malformed contrast exception authority")"#,
            #"error("contrast exception state aggregate drift")"#,
        ] {
            XCTAssertEqual(
                workflowSource.components(separatedBy: twiceLocked).count - 1,
                2,
                twiceLocked
            )
        }
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"taskID: "history_recovery""#
            ).count - 1,
            2
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"taskID: "report_comprehension""#
            ).count - 1,
            8
        )
        XCTAssertFalse(workflowSource.contains("S10_4_AUDIT_DIAGNOSTIC"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests.swift")
                    .path
            )
        )
    }

    func testFrozenInventoryDerivesExactUnpromotedVisualAndAccessibilityMatrices() throws {
        let manifest = try json("\(overlayRoot)/manifest.json")
        let matrix = try object(manifest, "matrix_contract")
        let inventory = try json("docs/design/s10/s10-screen-state-inventory.json")
        XCTAssertEqual(try string(inventory, "document_status"), "frozen")

        let routes = try rows(inventory, "routes")
        let fixtures = try rows(inventory, "fixtures")
        let states = try routes.flatMap { try rows($0, "states") }
        let stateIDs = try states.map { try string($0, "state_id") }
        XCTAssertEqual(routes.count, 27)
        XCTAssertEqual(states.count, 67)
        try assertExactSet(stateIDs, stateIDs, "inventory state IDs")
        XCTAssertEqual(
            stringSetSHA256(stateIDs),
            try string(matrix, "state_set_sha256")
        )
        XCTAssertEqual(
            stringSetSHA256(requirementIDs),
            try string(matrix, "requirement_set_sha256")
        )
        XCTAssertEqual(stringSetSHA256(taskIDs), try string(matrix, "task_set_sha256"))

        let fixtureIDs = try fixtures.map { try string($0, "fixture_id") }
        try assertExactSet(fixtureIDs, fixtureIDs, "fixture IDs")
        for route in routes {
            for path in try strings(route, "source_paths") {
                XCTAssertTrue(fileExists(path), path)
            }
        }
        for fixture in fixtures {
            for path in try strings(fixture, "source_paths") {
                XCTAssertTrue(fileExists(path), path)
            }
        }
        for state in states {
            XCTAssertTrue(fixtureIDs.contains(try string(state, "fixture_id")))
        }

        let candidateTuples = stateIDs.flatMap { stateID in
            requirementIDs.map { "\(stateID)|\($0)" }
        }
        XCTAssertEqual(candidateTuples.count, 938)
        try assertExactSet(candidateTuples, candidateTuples, "candidate tuples")
        XCTAssertEqual(
            stringSetSHA256(candidateTuples),
            try string(matrix, "candidate_tuple_set_sha256")
        )

        let visual = try json("docs/design/s10/s10-visual-regression.json")
        XCTAssertEqual(Set(visual.keys), Set([
            "schema_version", "document_status", "comparison_tool", "matrix_contract",
            "baselines", "change_records",
        ]))
        XCTAssertEqual(try string(visual, "schema_version"), "4.1.0")
        XCTAssertEqual(try string(visual, "document_status"), "baseline_frozen")
        XCTAssertNil(visual["automation_amendment_id"])
        XCTAssertNil(visual["candidate_cells"])
        XCTAssertNil(visual["shard_receipts"])
        XCTAssertNil(visual["aggregate"])
        try assertVisualMatrix(try object(visual, "matrix_contract"))

        let baselines = try rows(visual, "baselines")
        XCTAssertEqual(baselines.count, 67)
        try assertExactSet(
            baselines.map { try string($0, "screen_state_id") },
            stateIDs,
            "baseline state IDs"
        )
        try assertExactSet(
            baselines.map { try string($0, "baseline_id") },
            baselines.map { try string($0, "baseline_id") },
            "baseline IDs"
        )
        let stateByID = Dictionary(
            uniqueKeysWithValues: try states.map { (try string($0, "state_id"), $0) }
        )
        for baseline in baselines {
            let stateID = try string(baseline, "screen_state_id")
            let state = try XCTUnwrap(stateByID[stateID], stateID)
            XCTAssertEqual(
                try string(baseline, "fixture_id"),
                try string(state, "fixture_id"),
                stateID
            )
            XCTAssertEqual(try strings(baseline, "requirement_ids"), requirementIDs, stateID)
            XCTAssertEqual(
                try string(baseline, "baseline_product_head"),
                "44e9f9471f8ced9ecdd85f241a79c3750c38412d",
                stateID
            )
            XCTAssertEqual(try string(baseline, "baseline_review_status"), "APPROVED")
            XCTAssertEqual(try string(baseline, "baseline_reviewer"), "palatis3")
            XCTAssertTrue(try isUppercaseSHA256(string(baseline, "baseline_sha256")))
            XCTAssertFalse(try string(baseline, "baseline_screenshot_path").isEmpty)
            XCTAssertFalse(try strings(baseline, "baseline_evidence_ids").isEmpty)
            XCTAssertEqual(try string(baseline, "candidate_product_head"), "")
            XCTAssertEqual(try string(baseline, "candidate_screenshot_path"), "")
            XCTAssertEqual(try string(baseline, "candidate_sha256"), "")
            XCTAssertEqual(try strings(baseline, "intended_change_ids"), [])
            XCTAssertEqual(try string(baseline, "result"), "NOT_RUN")
            XCTAssertEqual(try string(baseline, "review_status"), "NOT_REVIEWED")
            XCTAssertEqual(try string(baseline, "reviewer"), "")
            XCTAssertEqual(try strings(baseline, "evidence_ids"), [])
        }
        let baselineProjection = try JSONSerialization.data(
            withJSONObject: baselines,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertEqual(
            baselineProjection.sha256,
            "EEF20A5A0CCD04E51496B99FE4A624DB51338B7F00DE561838E0461FA17C332D"
        )
        XCTAssertTrue(try rows(visual, "change_records").isEmpty)

        let accessibility = try json("docs/design/s10/s10-accessibility-common-tasks.json")
        XCTAssertEqual(Set(accessibility.keys), Set([
            "schema_version", "document_status", "device_profile_ids",
            "criteria_checked_date", "features", "eligible_features", "tasks",
        ]))
        XCTAssertEqual(try string(accessibility, "schema_version"), "4.1.0")
        XCTAssertEqual(try string(accessibility, "document_status"), "frozen")
        XCTAssertNil(accessibility["automation_amendment_id"])
        XCTAssertNil(accessibility["source_product_head"])
        XCTAssertNil(accessibility["aggregate"])
        XCTAssertEqual(
            try strings(accessibility, "device_profile_ids"),
            [currentProfile, minimumProfile]
        )
        XCTAssertEqual(try strings(accessibility, "features"), accessibilityFeatures)
        XCTAssertEqual(try strings(accessibility, "eligible_features"), [])

        let tasks = try rows(accessibility, "tasks")
        XCTAssertEqual(try tasks.map { try string($0, "task_id") }, taskIDs)
        var actualAccessibilityTuples = [String]()
        let stateIDSet = Set(stateIDs)
        for task in tasks {
            let taskID = try string(task, "task_id")
            XCTAssertTrue(Set(try strings(task, "screen_state_ids")).isSubset(of: stateIDSet))
            let results = try rows(task, "feature_results")
            XCTAssertEqual(results.count, 14, taskID)
            for row in results {
                let profile = try string(row, "device_profile_id")
                let feature = try string(row, "feature")
                actualAccessibilityTuples.append("\(taskID)|\(profile)|\(feature)")
                XCTAssertEqual(
                    expectedShards.filter {
                        $0.deviceProfileID == profile && $0.feature == feature
                    }.count,
                    1
                )
                XCTAssertEqual(try string(row, "automated_status"), "NOT_RUN")
                XCTAssertEqual(try strings(row, "automated_evidence_ids"), [])
                XCTAssertEqual(try string(row, "automated_reviewer"), "")
                for key in [
                    "exception_issue_id", "exception_owner", "exception_expires_at",
                    "exception_rationale",
                ] {
                    XCTAssertEqual(try string(row, key), "")
                }
                XCTAssertEqual(try string(row, "manual_status"), "NOT_RUN")
                XCTAssertEqual(try strings(row, "manual_evidence_ids"), [])
                XCTAssertEqual(try string(row, "manual_reviewer"), "")
                XCTAssertNil(row["automation_shard_id"])
                XCTAssertNil(row["source_product_head"])
                XCTAssertNil(row["run_id"])
            }
        }
        let expectedAccessibilityTuples = taskIDs.flatMap { taskID in
            [currentProfile, minimumProfile].flatMap { profile in
                accessibilityFeatures.map { "\(taskID)|\(profile)|\($0)" }
            }
        }
        XCTAssertEqual(actualAccessibilityTuples.count, 84)
        try assertExactSet(
            actualAccessibilityTuples,
            expectedAccessibilityTuples,
            "accessibility tuples"
        )
        XCTAssertEqual(
            stringSetSHA256(actualAccessibilityTuples),
            try string(matrix, "accessibility_tuple_set_sha256")
        )
    }

    func testMigratedProductAndTokenCoverageRemainBoundToFrozenInventory() throws {
        let manifest = try json("\(overlayRoot)/manifest.json")
        let base = try object(manifest, "base_authority")
        let tokenCoverage = try json("docs/design/s10/s10-token-coverage.json")
        XCTAssertEqual(try string(tokenCoverage, "schema_version"), "4.1.0")
        XCTAssertEqual(try string(tokenCoverage, "document_status"), "migrated")
        XCTAssertEqual(try string(tokenCoverage, "token_catalog_path"), "Brand/brand-tokens.json")
        XCTAssertEqual(
            try string(tokenCoverage, "token_catalog_sha256"),
            "2F044E9EAB2705F4265685B6F9370B07E0C1F6807D792744C8E4A35F6551E679"
        )
        XCTAssertEqual(
            try string(tokenCoverage, "component_system_product_head"),
            "28c5851a432db026251012de1e396a5896c9f91f"
        )
        XCTAssertEqual(
            try string(tokenCoverage, "migration_product_head"),
            try string(base, "accepted_migration_product_head")
        )
        XCTAssertEqual(try string(tokenCoverage, "migration_product_head"), acceptedMigrationHead)
        XCTAssertEqual(try int(tokenCoverage, "untracked_visual_constant_count"), 0)

        XCTAssertEqual(DesignTokens.tokenIDs, tokenIDs)
        XCTAssertEqual(Set(DesignTokens.tokenIDs).count, 45)
        XCTAssertEqual(DesignTokens.Target.minimumInteractiveWidth, 44)
        XCTAssertEqual(DesignTokens.Target.minimumInteractiveHeight, 44)
        XCTAssertEqual(DesignTokens.Environment.minimumSupportedIOSMajorVersion, 18)

        let components = try rows(tokenCoverage, "components")
        XCTAssertEqual(
            try components.map { try string($0, "component_id") },
            AssetRoundsComponentContract.roleIDs
        )
        XCTAssertEqual(components.count, 9)
        for component in components {
            XCTAssertEqual(try string(component, "status"), "PASS")
            XCTAssertFalse(try strings(component, "evidence_ids").isEmpty)
            for path in try strings(component, "source_paths") {
                XCTAssertTrue(fileExists(path), path)
            }
            XCTAssertTrue(Set(try strings(component, "token_ids")).isSubset(of: Set(tokenIDs)))
        }

        let inventory = try json("docs/design/s10/s10-screen-state-inventory.json")
        let states = try rows(inventory, "routes").flatMap { try rows($0, "states") }
        let stateByID = Dictionary(
            uniqueKeysWithValues: try states.map { (try string($0, "state_id"), $0) }
        )
        let coverage = try rows(tokenCoverage, "coverage")
        XCTAssertEqual(coverage.count, 67)
        try assertExactSet(
            coverage.map { try string($0, "screen_state_id") },
            Array(stateByID.keys),
            "token coverage states"
        )
        for row in coverage {
            let stateID = try string(row, "screen_state_id")
            let state = try XCTUnwrap(stateByID[stateID], stateID)
            XCTAssertEqual(
                try strings(row, "component_ids"),
                try strings(state, "component_ids"),
                stateID
            )
            XCTAssertEqual(
                try strings(row, "token_ids"),
                try strings(state, "token_ids"),
                stateID
            )
            XCTAssertEqual(try string(row, "status"), "PASS", stateID)
            XCTAssertFalse(try strings(row, "evidence_ids").isEmpty, stateID)
        }

        let activation = try json("docs/design/s10/s10-activation.json")
        let migrationCard = try XCTUnwrap(
            try rows(activation, "cards").first {
                ($0["card_id"] as? String) == "S10.3"
            }
        )
        let migratedSources = try strings(migrationCard, "allowed_paths").filter {
            $0.hasPrefix("FieldEvidenceApp/") && $0.hasSuffix(".swift")
        }
        XCTAssertEqual(migratedSources.count, 26)
        let literalPattern = try NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)
        var canonical = ""
        for path in migratedSources {
            let source = try text(path)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            let literals = literalPattern.matches(in: source, range: range).compactMap {
                Range($0.range, in: source).map { String(source[$0]) }
            }
            canonical += path + "\n" + literals.joined(separator: "\n") + "\n"
        }
        XCTAssertEqual(
            Data(canonical.utf8).sha256,
            "B27F236391630C9A8AFD02F1CDF6517EE16DAF406E64DE481D7DADAB711F8126"
        )
    }

    func testFrozenBrandPaletteProvidesExactOpaqueNormalAndIncreasedContrastTruth() throws {
        let palette = [
            PaletteEntry(
                assetName: "AssetRoundsAccentTeal", light: 0x006D75, dark: 0x2BB8C2,
                lightContrast: 5.73, darkContrast: 7.15
            ),
            PaletteEntry(
                assetName: "AssetRoundsDeepTeal", light: 0x0B4E53, dark: 0x8ADDE3,
                lightContrast: 8.85, darkContrast: 11.08
            ),
            PaletteEntry(
                assetName: "AssetRoundsCheckpointGreen", light: 0x147D47, dark: 0x53D78B,
                lightContrast: 4.87, darkContrast: 9.38
            ),
            PaletteEntry(
                assetName: "AssetRoundsBrandCanvas", light: 0xF3F9F9, dark: 0x061E26,
                lightContrast: nil, darkContrast: nil
            ),
            PaletteEntry(
                assetName: "AssetRoundsInk", light: 0x11181C, dark: 0xF7FAFA,
                lightContrast: 16.84, darkContrast: 16.38
            ),
            PaletteEntry(
                assetName: "AssetRoundsSlate", light: 0x47565D, dark: 0xB8C5C8,
                lightContrast: 7.16, darkContrast: 9.71
            ),
        ]
        XCTAssertEqual(
            AssetRoundsBrandColorAsset.allCases.map(\.rawValue),
            palette.map(\.assetName)
        )

        var normalLight = [String: UInt32]()
        var normalDark = [String: UInt32]()
        var highLight = [String: UInt32]()
        var highDark = [String: UInt32]()
        for expected in palette {
            let catalog = try json(
                "FieldEvidenceApp/Resources/Assets.xcassets/" +
                "\(expected.assetName).colorset/Contents.json"
            )
            let colors = try rows(catalog, "colors")
            XCTAssertEqual(colors.count, 4, expected.assetName)
            var colorsByTrait = [String: UInt32]()
            for row in colors {
                let appearances = try appearanceMap(row)
                let key = [
                    appearances["luminosity"] ?? "light",
                    appearances["contrast"] ?? "standard",
                ].joined(separator: "|")
                XCTAssertNil(
                    colorsByTrait.updateValue(try packedRGB(row), forKey: key),
                    expected.assetName
                )
            }
            XCTAssertEqual(Set(colorsByTrait.keys), Set([
                "light|standard", "dark|standard", "light|high", "dark|high",
            ]))
            XCTAssertEqual(colorsByTrait["light|standard"], expected.light)
            XCTAssertEqual(colorsByTrait["dark|standard"], expected.dark)
            XCTAssertNotEqual(colorsByTrait["light|high"], expected.light)
            XCTAssertNotEqual(colorsByTrait["dark|high"], expected.dark)
            normalLight[expected.assetName] = colorsByTrait["light|standard"]
            normalDark[expected.assetName] = colorsByTrait["dark|standard"]
            highLight[expected.assetName] = colorsByTrait["light|high"]
            highDark[expected.assetName] = colorsByTrait["dark|high"]
        }

        let canvas = "AssetRoundsBrandCanvas"
        for expected in palette where expected.assetName != canvas {
            let lightRatio = contrast(
                try XCTUnwrap(normalLight[expected.assetName]),
                try XCTUnwrap(normalLight[canvas])
            )
            let darkRatio = contrast(
                try XCTUnwrap(normalDark[expected.assetName]),
                try XCTUnwrap(normalDark[canvas])
            )
            XCTAssertEqual(
                roundedContrast(lightRatio),
                try XCTUnwrap(expected.lightContrast),
                accuracy: 0.001
            )
            XCTAssertEqual(
                roundedContrast(darkRatio),
                try XCTUnwrap(expected.darkContrast),
                accuracy: 0.001
            )
            XCTAssertGreaterThanOrEqual(lightRatio, 4.5)
            XCTAssertGreaterThanOrEqual(darkRatio, 4.5)
            XCTAssertGreaterThanOrEqual(
                contrast(
                    try XCTUnwrap(highLight[expected.assetName]),
                    try XCTUnwrap(highLight[canvas])
                ) + 0.000_001,
                lightRatio
            )
            XCTAssertGreaterThanOrEqual(
                contrast(
                    try XCTUnwrap(highDark[expected.assetName]),
                    try XCTUnwrap(highDark[canvas])
                ) + 0.000_001,
                darkRatio
            )
        }
    }

    private var expectedShards: [ExpectedShard] {
        let large = "UICTContentSizeCategoryL"
        let ax = "UICTContentSizeCategoryAccessibilityXXXL"
        return [
            ExpectedShard(ordinal: 1, shardID: "s10.4.current.default-light", requirementID: "default_light", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "voiceover", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 2, shardID: "s10.4.current.default-dark", requirementID: "default_dark", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "dark_interface", appearance: "dark", contrast: "standard", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 3, shardID: "s10.4.current.increased-contrast", requirementID: "increased_contrast", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "sufficient_contrast", appearance: "light", contrast: "increased", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 4, shardID: "s10.4.current.ax-text", requirementID: "ax_text", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "larger_text", appearance: "light", contrast: "standard", contentSizeCategory: ax, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 5, shardID: "s10.4.current.differentiate-without-color", requirementID: "differentiate_without_color", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "differentiate_without_color", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: true, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 6, shardID: "s10.4.current.reduce-motion", requirementID: "reduce_motion", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "reduced_motion", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: true, reduceTransparency: false),
            ExpectedShard(ordinal: 7, shardID: "s10.4.current.reduce-transparency", requirementID: "reduce_transparency", deviceProfileID: currentProfile, runtime: "iOS 26.2", simulator: "iPhone 17", osBuild: "23C54", feature: "voice_control", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: true),
            ExpectedShard(ordinal: 8, shardID: "s10.4.minimum.minimum-os", requirementID: "minimum_os", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "voiceover", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 9, shardID: "s10.4.minimum.double-length", requirementID: "double_length", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "larger_text", appearance: "light", contrast: "standard", contentSizeCategory: ax, locale: "en-US-double-length", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 10, shardID: "s10.4.minimum.rtl", requirementID: "rtl", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "dark_interface", appearance: "dark", contrast: "standard", contentSizeCategory: large, locale: "ar-RTL", layoutDirection: "right_to_left", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 11, shardID: "s10.4.minimum.rtl-string", requirementID: "rtl_string", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "voice_control", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "ar-RTL-string", layoutDirection: "right_to_left", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 12, shardID: "s10.4.minimum.tall", requirementID: "tall", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "reduced_motion", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-tall", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: true, reduceTransparency: false),
            ExpectedShard(ordinal: 13, shardID: "s10.4.minimum.accented", requirementID: "accented", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "sufficient_contrast", appearance: "light", contrast: "increased", contentSizeCategory: large, locale: "en-US-accented", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
            ExpectedShard(ordinal: 14, shardID: "s10.4.minimum.bounded", requirementID: "bounded", deviceProfileID: minimumProfile, runtime: "iOS 18.0", simulator: "iPhone SE (3rd generation)", osBuild: "22A3351", feature: "differentiate_without_color", appearance: "light", contrast: "standard", contentSizeCategory: large, locale: "en-US-bounded", layoutDirection: "left_to_right", differentiateWithoutColor: true, reduceMotion: false, reduceTransparency: false),
        ]
    }

    private func assertOverlaySchemas(
        visual: [String: Any],
        accessibility: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try string(visual, "$schema"),
            "https://json-schema.org/draft/2020-12/schema",
            file: file, line: line
        )
        XCTAssertEqual(visual["additionalProperties"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(try strings(visual, "required"), [
            "schema_version", "document_status", "automation_amendment_id",
            "comparison_tool", "matrix_contract", "baselines", "candidate_cells",
            "shard_receipts", "aggregate", "change_records",
        ], file: file, line: line)
        let visualProperties = try object(visual, "properties")
        XCTAssertEqual(
            try string(try object(visualProperties, "document_status"), "const"),
            "automated_evaluated",
            file: file, line: line
        )
        XCTAssertEqual(
            try string(try object(visualProperties, "automation_amendment_id"), "const"),
            "assetrounds-s10.4-automation-amendment-v1",
            file: file, line: line
        )
        for (key, count) in [("baselines", 67), ("candidate_cells", 938), ("shard_receipts", 14)] {
            let definition = try object(visualProperties, key)
            XCTAssertEqual(try int(definition, "minItems"), count, file: file, line: line)
            XCTAssertEqual(try int(definition, "maxItems"), count, file: file, line: line)
        }

        XCTAssertEqual(
            try string(accessibility, "$schema"),
            "https://json-schema.org/draft/2020-12/schema",
            file: file, line: line
        )
        XCTAssertEqual(
            accessibility["additionalProperties"] as? Bool,
            false,
            file: file, line: line
        )
        XCTAssertEqual(try strings(accessibility, "required"), [
            "schema_version", "document_status", "automation_amendment_id",
            "source_product_head", "device_profile_ids", "criteria_checked_date",
            "features", "eligible_features", "tasks", "aggregate",
        ], file: file, line: line)
        let accessibilityProperties = try object(accessibility, "properties")
        XCTAssertEqual(
            try string(try object(accessibilityProperties, "document_status"), "const"),
            "automated_evaluated",
            file: file, line: line
        )
        let tasks = try object(accessibilityProperties, "tasks")
        XCTAssertEqual(try int(tasks, "minItems"), 6, file: file, line: line)
        XCTAssertEqual(try int(tasks, "maxItems"), 6, file: file, line: line)
        let taskItem = try object(tasks, "items")
        let taskProperties = try object(taskItem, "properties")
        let featureResults = try object(taskProperties, "feature_results")
        XCTAssertEqual(try int(featureResults, "minItems"), 14, file: file, line: line)
        XCTAssertEqual(try int(featureResults, "maxItems"), 14, file: file, line: line)
        let resultItem = try object(featureResults, "items")
        let resultProperties = try object(resultItem, "properties")
        XCTAssertEqual(
            try strings(try object(resultProperties, "automated_status"), "enum"),
            ["PASS", "NOT_APPLICABLE", "EXCEPTION"],
            file: file, line: line
        )
        XCTAssertEqual(
            try string(try object(resultProperties, "manual_status"), "const"),
            "NOT_RUN",
            file: file, line: line
        )
    }

    private func assertDeviceProfiles(
        _ profiles: [[String: Any]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(profiles.count, 2, file: file, line: line)
        let current = profiles[0]
        XCTAssertEqual(try string(current, "deviceProfileID"), currentProfile, file: file, line: line)
        XCTAssertEqual(try string(current, "simulatorRuntime"), "iOS 26.2", file: file, line: line)
        XCTAssertEqual(try string(current, "simulatorRuntimeBuild"), "23C54", file: file, line: line)
        XCTAssertEqual(try string(current, "simulatorName"), "iPhone 17", file: file, line: line)
        XCTAssertEqual(current["provisionRuntime"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(try string(current, "runtimeDownloadVersion"), "", file: file, line: line)

        let minimum = profiles[1]
        XCTAssertEqual(try string(minimum, "deviceProfileID"), minimumProfile, file: file, line: line)
        XCTAssertEqual(try string(minimum, "simulatorRuntime"), "iOS 18.0", file: file, line: line)
        XCTAssertEqual(try string(minimum, "simulatorRuntimeBuild"), "22A3351", file: file, line: line)
        XCTAssertEqual(try string(minimum, "simulatorName"), "iPhone SE (3rd generation)", file: file, line: line)
        XCTAssertEqual(minimum["provisionRuntime"] as? Bool, true, file: file, line: line)
        XCTAssertEqual(try string(minimum, "runtimeDownloadVersion"), "18.0", file: file, line: line)
    }

    private func assertManifestShard(
        _ row: [String: Any],
        equals expected: ExpectedShard,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try int(row, "ordinal"), expected.ordinal, file: file, line: line)
        XCTAssertEqual(try string(row, "shard_id"), expected.shardID, file: file, line: line)
        XCTAssertEqual(try string(row, "requirement_id"), expected.requirementID, file: file, line: line)
        XCTAssertEqual(try string(row, "device_profile_id"), expected.deviceProfileID, file: file, line: line)
        XCTAssertEqual(try string(row, "simulator_runtime"), expected.runtime, file: file, line: line)
        XCTAssertEqual(try string(row, "simulator_name"), expected.simulator, file: file, line: line)
        XCTAssertEqual(try string(row, "os_build"), expected.osBuild, file: file, line: line)
        XCTAssertEqual(try string(row, "accessibility_feature"), expected.feature, file: file, line: line)
        XCTAssertEqual(try string(row, "appearance"), expected.appearance, file: file, line: line)
        XCTAssertEqual(try string(row, "contrast"), expected.contrast, file: file, line: line)
        XCTAssertEqual(try string(row, "content_size_category"), expected.contentSizeCategory, file: file, line: line)
        XCTAssertEqual(try string(row, "locale_profile_id"), expected.locale, file: file, line: line)
        XCTAssertEqual(try string(row, "layout_direction"), expected.layoutDirection, file: file, line: line)
        XCTAssertEqual(row["differentiate_without_color"] as? Bool, expected.differentiateWithoutColor, file: file, line: line)
        XCTAssertEqual(row["reduce_motion"] as? Bool, expected.reduceMotion, file: file, line: line)
        XCTAssertEqual(row["reduce_transparency"] as? Bool, expected.reduceTransparency, file: file, line: line)
    }

    private func assertScriptShard(
        _ row: [String: Any],
        equals expected: ExpectedShard,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try int(row, "ordinal"), expected.ordinal, file: file, line: line)
        XCTAssertEqual(try string(row, "shardID"), expected.shardID, file: file, line: line)
        XCTAssertEqual(try string(row, "requirementID"), expected.requirementID, file: file, line: line)
        XCTAssertEqual(try string(row, "deviceProfileID"), expected.deviceProfileID, file: file, line: line)
        XCTAssertEqual(try strings(row, "accessibilityFeatures"), [expected.feature], file: file, line: line)
        let environment = try object(row, "environment")
        XCTAssertEqual(try string(environment, "appearance"), expected.appearance, file: file, line: line)
        XCTAssertEqual(try string(environment, "contrast"), expected.contrast, file: file, line: line)
        XCTAssertEqual(try string(environment, "contentSizeCategory"), expected.contentSizeCategory, file: file, line: line)
        XCTAssertEqual(try string(environment, "locale"), expected.locale, file: file, line: line)
        XCTAssertEqual(try string(environment, "layoutDirection"), expected.layoutDirection, file: file, line: line)
        XCTAssertEqual(environment["differentiateWithoutColor"] as? Bool, expected.differentiateWithoutColor, file: file, line: line)
        XCTAssertEqual(environment["reduceMotion"] as? Bool, expected.reduceMotion, file: file, line: line)
        XCTAssertEqual(environment["reduceTransparency"] as? Bool, expected.reduceTransparency, file: file, line: line)
    }

    private func assertVisualMatrix(
        _ matrix: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expectedStrings = [
            "primary_locale": "en-US-release",
            "primary_layout_direction": "left_to_right",
            "double_length_locale": "en-US-double-length",
            "rtl_locale": "ar-RTL",
            "rtl_string_locale": "ar-RTL-string",
            "tall_locale": "en-US-tall",
            "accented_locale": "en-US-accented",
            "bounded_locale": "en-US-bounded",
            "default_content_size_category": "UICTContentSizeCategoryL",
            "ax_content_size_category": "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        for (key, value) in expectedStrings {
            XCTAssertEqual(try string(matrix, key), value, file: file, line: line)
        }
        XCTAssertEqual(try strings(matrix, "current_os_device_profile_ids"), [currentProfile], file: file, line: line)
        XCTAssertEqual(try strings(matrix, "minimum_os_device_profile_ids"), [minimumProfile], file: file, line: line)
        XCTAssertEqual(try strings(matrix, "required_requirement_ids"), requirementIDs, file: file, line: line)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(relativePath).path
        )
    }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func text(_ relativePath: String) throws -> String {
        String(decoding: try data(relativePath), as: UTF8.self)
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data(relativePath))
        return try XCTUnwrap(value as? [String: Any], relativePath)
    }

    private func rows(_ value: [String: Any], _ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(value[key] as? [[String: Any]], key)
    }

    private func object(_ value: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(value[key] as? [String: Any], key)
    }

    private func string(_ value: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(value[key] as? String, key)
    }

    private func strings(_ value: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(value[key] as? [String], key)
    }

    private func int(_ value: [String: Any], _ key: String) throws -> Int {
        try XCTUnwrap(value[key] as? Int, key)
    }

    private func assertFile(
        _ relativePath: String,
        byteCount: Int,
        sha256: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bytes = try data(relativePath)
        XCTAssertEqual(bytes.count, byteCount, relativePath, file: file, line: line)
        XCTAssertEqual(bytes.sha256, sha256, relativePath, file: file, line: line)
    }

    private func assertExactSet(
        _ actual: [String],
        _ expected: [String],
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(actual.count, Set(actual).count, "\(label) contains duplicates", file: file, line: line)
        XCTAssertEqual(expected.count, Set(expected).count, "\(label) expectation contains duplicates", file: file, line: line)
        XCTAssertEqual(Set(actual), Set(expected), label, file: file, line: line)
    }

    private func stringSetSHA256(_ values: [String]) -> String {
        Data(values.sorted().joined(separator: "\n").utf8).sha256
    }

    private func isUppercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("A"..."F").contains(String($0)) }
    }

    private func appearanceMap(_ row: [String: Any]) throws -> [String: String] {
        guard let appearances = row["appearances"] else {
            return [:]
        }
        let values = try XCTUnwrap(appearances as? [[String: Any]])
        return Dictionary(
            uniqueKeysWithValues: try values.map {
                (try string($0, "appearance"), try string($0, "value"))
            }
        )
    }

    private func packedRGB(_ row: [String: Any]) throws -> UInt32 {
        let color = try object(row, "color")
        XCTAssertEqual(try string(color, "color-space"), "srgb")
        let components = try object(color, "components")
        XCTAssertEqual(try double(components, "alpha"), 1, accuracy: 0.000_001)
        let red = UInt32((try double(components, "red") * 255).rounded())
        let green = UInt32((try double(components, "green") * 255).rounded())
        let blue = UInt32((try double(components, "blue") * 255).rounded())
        return red << 16 | green << 8 | blue
    }

    private func double(_ value: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(Double(try string(value, key)), key)
    }

    private func contrast(_ foreground: UInt32, _ background: UInt32) -> Double {
        let foregroundLuminance = luminance(foreground)
        let backgroundLuminance = luminance(background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    private func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let component = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private func roundedContrast(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

private extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02X", $0) }.joined()
    }
}
