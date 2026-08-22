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
            byteCount: 113_339,
            sha256: "BEC94B7AF2983F37C06D448C9EC1B384137220A2154FCD4D9898D2048E8B90F3"
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
        let worklightComponentsPath =
            "FieldEvidenceApp/DesignSystem/WorklightComponents.swift"
        try assertFile(
            worklightComponentsPath,
            byteCount: 22_720,
            sha256: "333A2B8462C86E7EB2D37E65E7501BCBAA80B3002BAD77251EA56669D9569C71"
        )
        let worklightComponentsSource = try text(worklightComponentsPath)
        let emptyStateStartMarker = "struct AssetRoundsEmptyState: View {"
        let emptyStateEndMarker = "enum AssetRoundsBrandSymbolRendering: String, CaseIterable {"
        let emptyStateStartParts = worklightComponentsSource.components(
            separatedBy: emptyStateStartMarker
        )
        guard emptyStateStartParts.count == 2 else {
            XCTFail("The shared empty-state component must have one exact owner")
            return
        }
        let emptyStateTail = emptyStateStartParts[1]
        guard let emptyStateEnd = emptyStateTail.range(of: emptyStateEndMarker) else {
            XCTFail("The shared empty-state component has no exact end boundary")
            return
        }
        let emptyStateSource = String(emptyStateTail[..<emptyStateEnd.lowerBound])
        let emptyStateMessagePrimaryText =
            "            message\n" +
                "                .font(DesignTokens.Typography.primaryBody)\n" +
                "                .foregroundStyle(DesignTokens.SemanticColors.primaryText)\n" +
                "                .fixedSize(horizontal: false, vertical: true)"
        XCTAssertEqual(
            emptyStateSource.components(
                separatedBy: emptyStateMessagePrimaryText
            ).count - 1,
            1
        )
        let emptyStateMessageSecondaryText =
            "            message\n" +
                "                .font(DesignTokens.Typography.primaryBody)\n" +
                "                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)\n" +
                "                .fixedSize(horizontal: false, vertical: true)"
        XCTAssertEqual(
            emptyStateSource.components(
                separatedBy: emptyStateMessageSecondaryText
            ).count - 1,
            0
        )
        let emptyStateTitleContract =
            "            title\n" +
                "                .font(DesignTokens.Typography.screenTitle)\n" +
                "                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)\n" +
                "                .fixedSize(horizontal: false, vertical: true)\n" +
                "                .accessibilityAddTraits(.isHeader)"
        XCTAssertEqual(
            emptyStateSource.components(separatedBy: emptyStateTitleContract).count - 1,
            1
        )
        let emptyStateActionContract =
            "            if let actionLabel, let action {\n" +
                "                AssetRoundsPrimaryAction(action: action) {\n" +
                "                    actionLabel\n" +
                "                }\n" +
                "            }"
        XCTAssertEqual(
            emptyStateSource.components(separatedBy: emptyStateActionContract).count - 1,
            1
        )
        let emptyStateLayoutContract =
            "        .padding(DesignTokens.Spacing.space24)\n" +
                "        .frame(maxWidth: .infinity, alignment: .leading)\n" +
                "        .background(DesignTokens.SemanticColors.workBackground)"
        XCTAssertEqual(
            emptyStateSource.components(separatedBy: emptyStateLayoutContract).count - 1,
            1
        )
        let diagnosticExportPath =
            "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift"
        try assertFile(
            diagnosticExportPath,
            byteCount: 9_966,
            sha256: "E230A9539BE2FC6A2004486D83BFBDD79E4889C28CEFD90F84CD2B548E964931"
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
        let diagnosticHeadingAuthoritySpacing =
            "                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)\n" +
                "                    .padding(.bottom, DesignTokens.Spacing.space4)\n\n" +
                "                Text(\n" +
                "                    \"These counters are best-effort lower-bound signals. They may be incomplete and are not payment, access, or cohort authority.\"\n" +
                "                )\n" +
                "                .font(DesignTokens.Typography.primaryBody)\n" +
                "                .foregroundStyle(DesignTokens.SemanticColors.primaryText)\n" +
                "                .fixedSize(horizontal: false, vertical: true)\n" +
                "                .accessibilityIdentifier(Self.authorityAccessibilityIdentifier)"
        XCTAssertEqual(
            diagnosticExportSource.components(
                separatedBy: diagnosticHeadingAuthoritySpacing
            ).count - 1,
            1
        )
        XCTAssertEqual(
            diagnosticExportSource.components(
                separatedBy: ".padding(.bottom, DesignTokens.Spacing.space4)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            diagnosticExportSource.components(
                separatedBy:
                    ".accessibilityIdentifier(Self.headingAccessibilityIdentifier)\n\n" +
                        "                Text("
            ).count - 1,
            0
        )
        try assertFile(
            sourceParts[0],
            byteCount: 291_771,
            sha256: "FC69B4A9E6A6F55128B8683254C16F46EBC538B18CDAF6690DB31538B49A9819"
        )
        let uiSource = try text(sourceParts[0])
        XCTAssertTrue(uiSource.contains("class S10_4AutomatedBrandLabUITests"))
        let minimumKeyboardThrowingCall =
            "        try assertLightFirstSignValidationAndCreation(in: app)"
        let minimumKeyboardThrowingSignature =
            "    private func assertLightFirstSignValidationAndCreation(\n" +
                "        in app: XCUIApplication\n" +
                "    ) throws {"
        for throwingMinimumKeyboardLock in [
            minimumKeyboardThrowingCall,
            minimumKeyboardThrowingSignature,
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: throwingMinimumKeyboardLock
                ).count - 1,
                1,
                throwingMinimumKeyboardLock
            )
        }
        for staleNonthrowingMinimumKeyboardLock in [
            "        assertLightFirstSignValidationAndCreation(in: app)",
            "    private func assertLightFirstSignValidationAndCreation(\n" +
                "        in app: XCUIApplication\n" +
                "    ) {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: staleNonthrowingMinimumKeyboardLock
                ).count - 1,
                0,
                staleNonthrowingMinimumKeyboardLock
            )
        }
        for throwingDiagnosticsCallChainLock in [
            "        try assertMonthlyPaywallAtXXXL(in: app)",
            "    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) throws {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: throwingDiagnosticsCallChainLock
                ).count - 1,
                1,
                throwingDiagnosticsCallChainLock
            )
        }
        for restoredNonthrowingSettingsDataSurfacesLock in [
            "        captureSettingsDataSurfaces(in: app)",
            "    private func captureSettingsDataSurfaces(in app: XCUIApplication) {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: restoredNonthrowingSettingsDataSurfacesLock
                ).count - 1,
                1,
                restoredNonthrowingSettingsDataSurfacesLock
            )
        }
        for removedDiagnosticsCallChainLock in [
            "        assertMonthlyPaywallAtXXXL(in: app)",
            "    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) {",
            "        try captureSettingsDataSurfaces(in: app)",
            "    private func captureSettingsDataSurfaces(in app: XCUIApplication) throws {",
        ] {
            XCTAssertFalse(
                uiSource.contains(removedDiagnosticsCallChainLock),
                removedDiagnosticsCallChainLock
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
        guard let preflightMinimumStartRange = preflightQuickPathSource.range(
            of: preflightMinimumGate
        ) else {
            XCTFail("Missing the minimum-profile preflight source slice")
            return
        }
        let preflightMinimumSource = String(
            preflightQuickPathSource[
                preflightMinimumStartRange.lowerBound..<preflightQuickPathSource.endIndex
            ]
        )
        XCTAssertEqual(preflightMinimumSource.utf8.count, 23_121)
        XCTAssertEqual(
            Data(preflightMinimumSource.utf8).sha256,
            "F8FC3E5144D26D6D9F2ABBEBE7E4B48E049298E0D8518B607D61136DA8BB484A"
        )
        let preflightReturnAbsenceDiscriminator =
            #"            let returnKey = app.keyboards.buttons["Return"]"# + "\n" +
                #"            if !returnKey.waitForExistence(timeout: 1) || !returnKey.isHittable {"#
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightReturnAbsenceDiscriminator
            ).count - 1,
            1
        )
        XCTAssertFalse(preflightQuickPathSource.contains("returnKey.exists"))

        let preflightRelationalClassifier = [
            "                let applicationFrame = app.frame",
            "                let observedKeyboardFrame = keyboard.frame",
            "                guard !applicationFrame.isNull,\n" +
                "                      !applicationFrame.isEmpty,\n" +
                "                      !observedKeyboardFrame.isNull,\n" +
                "                      !observedKeyboardFrame.isEmpty else {",
            "                let keyboardIsOffApp =\n" +
                "                    observedKeyboardFrame.minY >= applicationFrame.maxY",
            "                let keyboardIsVisibleInApp =\n" +
                "                    observedKeyboardFrame.minY < applicationFrame.maxY",
            "                guard keyboardIsOffApp != keyboardIsVisibleInApp else {",
            "                if keyboardIsOffApp {",
        ]
        for lock in preflightRelationalClassifier {
            XCTAssertEqual(
                preflightQuickPathSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        guard let preflightOffAppStartRange = preflightQuickPathSource.range(
            of: "                if keyboardIsOffApp {"
        ), let preflightVisibleStartRange = preflightQuickPathSource.range(
            of: "                } else {",
            range: preflightOffAppStartRange.upperBound..<preflightQuickPathSource.endIndex
        ) else {
            XCTFail("Missing the preflight keyboard class branches")
            return
        }
        let preflightOffAppSource = String(
            preflightQuickPathSource[
                preflightOffAppStartRange.lowerBound..<preflightVisibleStartRange.lowerBound
            ]
        )
        let preflightVisibleSource = String(
            preflightQuickPathSource[
                preflightVisibleStartRange.lowerBound..<preflightQuickPathSource.endIndex
            ]
        )
        let normalizedPreflightVisibleSource = preflightVisibleSource
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        let preflightOffAppGuard =
            "                    let inputAssistantFrame = inputAssistantView.frame\n" +
                "                    guard inputAssistantViews.count == 1,\n" +
                "                          !inputAssistantFrame.isNull,\n" +
                "                          !inputAssistantFrame.isEmpty,\n" +
                "                          inputAssistantFrame.minY\n" +
                "                            >= applicationFrame.maxY,\n" +
                "                          keyboardIsAbsentOrInertOffApp(in: app),\n" +
                "                          wait(\n" +
                "                              for: zone,\n" +
                #"                              predicate: "hasKeyboardFocus == true","# + "\n" +
                "                              timeout: 10\n" +
                "                          ),\n" +
                "                          preflight.exists\n" +
                "                            == preActionPreflightExists,\n" +
                "                          detailRoute.exists\n" +
                "                            == preActionDetailRouteExists,\n" +
                "                          zone.label == preActionZoneLabel,\n" +
                "                          (zone.value as? String) == preActionZoneValue,\n" +
                "                          afterDark.label == preActionAfterDarkLabel,\n" +
                "                          (afterDark.value as? String)\n" +
                "                            == preActionAfterDarkValue,\n" +
                "                          safePosition.label\n" +
                "                            == preActionSafePositionLabel,\n" +
                "                          (safePosition.value as? String)\n" +
                "                            == preActionSafePositionValue,\n" +
                "                          app.state == .runningForeground else {"
        XCTAssertEqual(
            preflightOffAppSource.components(separatedBy: preflightOffAppGuard).count - 1,
            1
        )
        for prohibitedOffAppAction in [
            "tap(",
            "press(",
            "coordinate(",
            "swipe",
            "scroll(",
            "typeText(",
            "dismissKeyboard(",
            "app.swipe",
            "app.coordinate",
            "Thread.sleep",
            "Task.sleep",
            "sleep(",
            "tolerance",
            "epsilon",
            "711",
            "880",
            "-91",
        ] {
            XCTAssertFalse(
                preflightOffAppSource.contains(prohibitedOffAppAction),
                prohibitedOffAppAction
            )
        }

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
                "                      preflightScrollViews.count == 1,\n" +
                "                      preflightNavigationBars.count == 1,\n" +
                "                      inputAssistantViews.count == 1,\n" +
                "                      afterDarkToggles.count == 1,\n" +
                "                      safePositionToggles.count == 1,\n" +
                "                      preflightScrollView.exists,\n" +
                "                      preflightNavigationBar.exists,\n" +
                "                      inputAssistantView.exists,\n" +
                "                      afterDark.exists,\n" +
                "                      safePosition.exists,\n" +
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
        let normalizedPreflightFrozenKeyboardFrame = preflightFrozenKeyboardFrame
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        XCTAssertEqual(
            normalizedPreflightVisibleSource.components(
                separatedBy: normalizedPreflightFrozenKeyboardFrame
            ).count - 1,
            1
        )
        let preflightObservedKeyboardFrame =
            "                let observedKeyboardFrame = keyboard.frame"
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
        let normalizedPreflightCoordinate = preflightNormalizedCoordinate
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        XCTAssertEqual(
            normalizedPreflightVisibleSource.components(
                separatedBy: normalizedPreflightCoordinate
            ).count - 1,
            1
        )
        for retainedVisiblePreflightLock in [
            preflightFrozenKeyboardFrame,
            preflightNormalizedCoordinate,
            "                    let observedAssistantFrame = inputAssistantView.frame",
            "                    guard observedKeyboardFrame == expectedKeyboardFrame,\n" +
                "                          !observedAssistantFrame.isNull,\n" +
                "                          !observedAssistantFrame.isEmpty,\n" +
                "                          observedAssistantFrame.minY\n" +
                "                            < applicationFrame.maxY,\n" +
                "                          observedAssistantFrame.maxY\n" +
                "                            <= applicationFrame.maxY else {",
            "                    let restoredDoneKey = app.keyboards.buttons[\"Done\"]",
            "                    let expectedDoneFrame = CGRect(\n" +
                "                        x: 281.5,\n" +
                "                        y: 620,\n" +
                "                        width: 93.5,\n" +
                "                        height: 46\n" +
                "                    )",
            "                           inputAssistantViews.count == 1,\n" +
            "                           inputAssistantView.exists,\n" +
                "                           inputAssistantView.frame\n" +
                "                             == observedAssistantFrame,",
            "                           finalAssistantFrame == observedAssistantFrame,",
            "                           finalAfterDarkFrame.minY >= finalSafeTop,\n" +
                "                           finalAfterDarkFrame.maxY\n" +
                "                             <= finalSafeBottom,\n" +
                "                           finalSafePositionFrame.minY >= finalSafeTop,\n" +
                "                           finalSafePositionFrame.maxY\n" +
                "                             <= finalSafeBottom,\n" +
                "                           afterDark.isHittable,\n" +
                "                           safePosition.isHittable else {",
        ] {
            let normalizedLock = retainedVisiblePreflightLock
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            XCTAssertEqual(
                normalizedPreflightVisibleSource.components(
                    separatedBy: normalizedLock
                ).count - 1,
                1,
                retainedVisiblePreflightLock
            )
        }
        let normalizedPreflightRestoredContentLock = [
            "afterDark.label == preActionAfterDarkLabel,",
            "(afterDark.value as? String)",
            "== preActionAfterDarkValue,",
            "safePosition.label",
            "== preActionSafePositionLabel,",
            "(safePosition.value as? String)",
            "== preActionSafePositionValue,",
        ].joined(separator: "\n")
        XCTAssertEqual(
            normalizedPreflightVisibleSource.components(
                separatedBy: normalizedPreflightRestoredContentLock
            ).count - 1,
            2
        )
        let normalizedPreflightRestoredDoneLock = [
            "restoredDoneKey.elementType == .button,",
            #"restoredDoneKey.identifier == "Done","#,
            #"restoredDoneKey.label == "done","#,
            "restoredDoneKey.frame == expectedDoneFrame,",
            "restoredDoneKey.isHittable,",
        ].joined(separator: "\n")
        XCTAssertEqual(
            normalizedPreflightVisibleSource.components(
                separatedBy: normalizedPreflightRestoredDoneLock
            ).count - 1,
            2
        )
        let preflightVisiblePositioningLocks = [
            "                    let verticalInset: CGFloat = 16",
            "                    let receiverInset: CGFloat = 24",
            "                    let minimumGestureDistance: CGFloat = 44",
            "                    var preflightPositioningDirection: CGFloat?",
            "                    for _ in 0..<4 {",
            "                         let liveApplicationFrame = app.frame",
            "                         let scrollFrame = preflightScrollView.frame",
            "                         let liveScrollFrame = scrollFrame.intersection(\n" +
                "                             liveApplicationFrame\n" +
                "                         )",
            "                         let navigationFrame = preflightNavigationBar.frame",
            "                         let assistantFrame = inputAssistantView.frame",
            "                         let safeTop = max(\n" +
                "                             liveScrollFrame.minY,\n" +
                "                             navigationFrame.maxY\n" +
                "                         ) + verticalInset",
            "                         let safeBottom = min(\n" +
                "                             liveScrollFrame.maxY,\n" +
                "                             assistantFrame.minY\n" +
                "                         ) - verticalInset",
            "                         let receiverTop = max(\n" +
                "                             liveScrollFrame.minY,\n" +
                "                             navigationFrame.maxY\n" +
                "                         ) + receiverInset",
            "                         let receiverBottom = min(\n" +
                "                             liveScrollFrame.maxY,\n" +
                "                             assistantFrame.minY\n" +
                "                         ) - receiverInset",
            "                         let targetTop = min(\n" +
                "                             afterDarkFrame.minY,\n" +
                "                             safePositionFrame.minY\n" +
                "                         )",
            "                         let targetBottom = max(\n" +
                "                             afterDarkFrame.maxY,\n" +
                "                             safePositionFrame.maxY\n" +
                "                         )",
            "                     let finalApplicationFrame = app.frame",
            "                     let finalScrollFrame = preflightScrollView.frame\n" +
                "                         .intersection(finalApplicationFrame)",
            "                     let finalSafeTop = max(\n" +
                "                         finalScrollFrame.minY,\n" +
                "                         finalNavigationFrame.maxY\n" +
                "                     ) + verticalInset",
            "                     let finalSafeBottom = min(\n" +
                "                         finalScrollFrame.maxY,\n" +
                "                         finalAssistantFrame.minY\n" +
                "                     ) - verticalInset",
            "                     let finalAfterDarkFrame = afterDark.frame",
            "                     let finalSafePositionFrame = safePosition.frame",
            "                               safeBottom > safeTop,\n" +
                "                               receiverBottom > receiverTop,\n" +
                "                               targetBottom - targetTop\n" +
                "                                 <= safeBottom - safeTop else {",
            "                         let minimumShift = max(\n" +
                "                             safeTop - afterDarkFrame.minY,\n" +
                "                             safeTop - safePositionFrame.minY\n" +
                "                         )",
            "                         let maximumShift = min(\n" +
                "                             safeBottom - afterDarkFrame.maxY,\n" +
                "                             safeBottom - safePositionFrame.maxY\n" +
                "                         )",
            "                         let receiverCapacity = receiverBottom - receiverTop",
            "                         guard minimumShift <= maximumShift,\n" +
                "                               receiverCapacity\n" +
                "                                 >= minimumGestureDistance else {",
            "                             let recognizedMinimum = max(\n" +
                "                                 minimumShift,\n" +
                "                                 -receiverCapacity\n" +
                "                             )",
            "                             let recognizedMaximum = min(\n" +
                "                                 maximumShift,\n" +
                "                                 -minimumGestureDistance\n" +
                "                             )",
            "                             if recognizedMinimum <= recognizedMaximum {\n" +
                "                                 dragDistance = recognizedMaximum\n" +
                "                             } else if maximumShift < -receiverCapacity {\n" +
                "                                 dragDistance = -receiverCapacity\n" +
                "                             } else {\n" +
                #"                                 XCTFail("The visible preflight upward shift is not recognizable.")"# + "\n" +
                "                                 return\n" +
                "                             }",
            "                             let recognizedMinimum = max(\n" +
                "                                 minimumShift,\n" +
                "                                 minimumGestureDistance\n" +
                "                             )",
            "                             let recognizedMaximum = min(\n" +
                "                                 maximumShift,\n" +
                "                                 receiverCapacity\n" +
                "                             )",
            "                             if recognizedMinimum <= recognizedMaximum {\n" +
                "                                 dragDistance = recognizedMinimum\n" +
                "                             } else if minimumShift > receiverCapacity {\n" +
                "                                 dragDistance = receiverCapacity\n" +
                "                             } else {\n" +
                #"                                 XCTFail("The visible preflight downward shift is not recognizable.")"# + "\n" +
                "                                 return\n" +
                "                             }",
            "                             dragDistance = recognizedMaximum",
            "                             dragDistance = recognizedMinimum",
            "                         let dragDirection: CGFloat = dragDistance > 0\n" +
                "                             ? 1\n" +
                "                             : -1",
            "                         if let preflightPositioningDirection {\n" +
                "                             guard dragDirection\n" +
                "                                 == preflightPositioningDirection else {\n" +
                #"                                 XCTFail("The visible preflight correction would reverse direction.")"# + "\n" +
                "                                 return\n" +
                "                             }\n" +
                "                         } else {\n" +
                "                             preflightPositioningDirection = dragDirection\n" +
                "                         }",
            "                         let scrollOrigin = preflightScrollView.coordinate(\n" +
                "                             withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "                         )",
            "                         let dragStartOffsetY = dragDistance > 0\n" +
                "                             ? receiverTop - scrollFrame.minY\n" +
                "                             : receiverBottom - scrollFrame.minY",
            "                         dragStart.press(\n" +
                "                             forDuration: 0.2,\n" +
                "                             thenDragTo: dragEnd,\n" +
                "                             withVelocity: .slow,\n" +
                "                             thenHoldForDuration: 0.2\n" +
                "                         )",
            "                         let afterDarkMovement =\n" +
                "                             afterDark.frame.minY - afterDarkMinYBeforeDrag",
            "                         let safePositionMovement =\n" +
                "                             safePosition.frame.minY\n" +
                "                                 - safePositionMinYBeforeDrag",
            "                         guard afterDarkMovement * dragDistance > 0,\n" +
                "                               safePositionMovement * dragDistance > 0 else {",
        ]
        for lock in preflightVisiblePositioningLocks {
            let normalizedLock = lock
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            XCTAssertEqual(
                normalizedPreflightVisibleSource.components(
                    separatedBy: normalizedLock
                ).count - 1,
                1,
                lock
            )
        }
        for (queryCardinalityLock, count) in [
            ("preflightScrollViews.count == 1", 2),
            ("preflightNavigationBars.count == 1", 2),
            ("inputAssistantViews.count == 1", 3),
            ("afterDarkToggles.count == 1", 2),
            ("safePositionToggles.count == 1", 2),
        ] {
            XCTAssertEqual(
                preflightVisibleSource.components(
                    separatedBy: queryCardinalityLock
                ).count - 1,
                count,
                queryCardinalityLock
            )
        }
        for (preflightDirectionLock, count) in [
            ("preflightPositioningDirection", 4),
            ("dragDirection", 3),
            ("maximumShift < -receiverCapacity", 1),
            ("dragDistance = -receiverCapacity", 1),
            ("minimumShift > receiverCapacity", 1),
            ("dragDistance = receiverCapacity", 1),
        ] {
            XCTAssertEqual(
                preflightVisibleSource.components(
                    separatedBy: preflightDirectionLock
                ).count - 1,
                count,
                preflightDirectionLock
            )
        }
        for prohibitedVisiblePreflightForm in [
            "app.swipeUp()",
            "app.swipeDown()",
            "app.coordinate(",
            "preflightScrollView.swipeUp()",
            "preflightScrollView.swipeDown()",
            "Thread.sleep",
            "Task.sleep",
            "sleep(",
            "tolerance",
            "epsilon",
            "711",
            "880",
            "-91",
        ] {
            XCTAssertFalse(
                preflightQuickPathSource.contains(prohibitedVisiblePreflightForm),
                prohibitedVisiblePreflightForm
            )
        }
        for (preflightActionLock, count) in [
            ("keyboard.coordinate(", 1),
            ("preflightScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                preflightVisibleSource.components(
                    separatedBy: preflightActionLock
                ).count - 1,
                count,
                preflightActionLock
            )
        }
        let preflightIncompleteFailure =
            "                    XCTFail(\"The iOS 18 preflight QuickPath state is incomplete.\")\n" +
                "                    return\n" +
                "                }"
        let preflightFrameFailure =
            "                    XCTFail(\"The minimum-profile preflight application or keyboard frame is empty.\")\n" +
                "                    return\n" +
                "                }"
        let preflightRestorationFailure =
            "                        XCTFail(\"The preflight state or content was not restored after dismissing the QuickPath tutorial.\")\n" +
                "                        return\n" +
                "                    }"
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
            15
        )
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: "                    return\n").count - 1,
            15
        )
        XCTAssertFalse(
            preflightQuickPathSource.contains(
                "guard returnKey.waitForExistence(timeout: 10)"
            )
        )
        let preflightFinalFailure =
            "                        XCTFail(\"The visible preflight state was not fully restored and positioned before capture.\")\n" +
                "                        return\n" +
                "                    }"
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: preflightFinalFailure
            ).count - 1,
            1
        )
        let preflightQuickPathCapturePrecededByFinalGuard =
            preflightFinalFailure + "\n                }\n            }\n        }\n" +
                preflightQuickPathCapture
        XCTAssertEqual(
            uiSource.components(
                separatedBy: preflightQuickPathCapturePrecededByFinalGuard
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
        guard let h135SourceStartRange = uiSource.range(
            of: quickPathProfileGuard
        ), let h135CaptureRange = uiSource.range(
            of: quickPathCapture,
            range: h135SourceStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the minimum-profile new-sign source slice")
            return
        }
        let h135Source = String(
            uiSource[
                h135SourceStartRange.lowerBound..<h135CaptureRange.lowerBound
            ]
        )
        XCTAssertEqual(h135Source.utf8.count, 5_796)
        XCTAssertEqual(
            Data(h135Source.utf8).sha256,
            "3350DA2976EE30EDD944F2C80295C4751256AA1DFDF5EAD005898EBDB5EF610B"
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
                #"            if !returnKey.waitForExistence(timeout: 1) || !returnKey.isHittable {"#
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathReturnProbe).count - 1,
            1
        )
        XCTAssertFalse(
            quickPathViewportToCaptureSource.contains(
                #"            if !returnKey.waitForExistence(timeout: 1) {"#
            )
        )
        XCTAssertFalse(quickPathViewportToCaptureSource.contains("returnKey.exists"))

        let quickPathRelationalClassifier = [
            "                let applicationFrame = app.frame",
            "                let observedKeyboardFrame = keyboard.frame",
            "                guard !applicationFrame.isNull,\n" +
                "                      !applicationFrame.isEmpty,\n" +
                "                      !observedKeyboardFrame.isNull,\n" +
                "                      !observedKeyboardFrame.isEmpty else {",
            "                let keyboardIsOffApp =\n" +
                "                    observedKeyboardFrame.minY >= applicationFrame.maxY",
            "                let keyboardIsVisibleInApp =\n" +
                "                    observedKeyboardFrame.minY < applicationFrame.maxY",
            "                guard keyboardIsOffApp != keyboardIsVisibleInApp else {",
            "                if keyboardIsOffApp {",
            "                } else {",
        ]
        for lock in quickPathRelationalClassifier {
            XCTAssertEqual(
                quickPathViewportToCaptureSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        guard let quickPathOffAppStartRange = quickPathViewportToCaptureSource.range(
            of: "                if keyboardIsOffApp {"
        ), let quickPathVisibleStartRange = quickPathViewportToCaptureSource.range(
            of: "                } else {",
            range: quickPathOffAppStartRange.upperBound..<quickPathViewportToCaptureSource.endIndex
        ) else {
            XCTFail("Missing the new-sign keyboard class branches")
            return
        }
        let quickPathOffAppSource = String(
            quickPathViewportToCaptureSource[
                quickPathOffAppStartRange.lowerBound..<quickPathVisibleStartRange.lowerBound
            ]
        )
        let quickPathVisibleSource = String(
            quickPathViewportToCaptureSource[
                quickPathVisibleStartRange.lowerBound..<quickPathViewportToCaptureSource.endIndex
            ]
        )
        let normalizedQuickPathVisibleSource = quickPathVisibleSource
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        let quickPathOffAppGuard =
            "                    guard inputAssistantViews.count == 1,\n" +
                "                          inputAssistantView.exists,\n" +
                "                          !inputAssistantView.frame.isNull,\n" +
                "                          !inputAssistantView.frame.isEmpty,\n" +
                "                          inputAssistantView.frame.minY\n" +
                "                            >= applicationFrame.maxY,\n" +
                "                          keyboardIsAbsentOrInertOffApp(in: app),\n" +
                "                          wait(\n" +
                "                              for: site,\n" +
                #"                              predicate: "hasKeyboardFocus == true","# + "\n" +
                "                              timeout: 10\n" +
                "                          ),\n" +
                "                          newSignRoute.exists\n" +
                "                            == preActionNewSignRouteExists,\n" +
                "                          validationDetailRoute.exists\n" +
                "                            == preActionDetailRouteExists,\n" +
                "                          (site.value as? String) == preActionSiteValue,\n" +
                "                          (sign.value as? String) == preActionSignValue,\n" +
                "                          error.label == preActionErrorLabel,\n" +
                "                          (error.value as? String) == preActionErrorValue,\n" +
                "                          app.state == .runningForeground else {"
        XCTAssertEqual(
            quickPathOffAppSource.components(separatedBy: quickPathOffAppGuard).count - 1,
            1
        )
        for prohibitedOffAppAction in [
            "tap(",
            "press(",
            "coordinate(",
            "swipe",
            "scroll(",
            "typeText(",
            "dismissKeyboard(",
            "app.swipe",
            "app.coordinate",
            "Thread.sleep",
            "Task.sleep",
            "sleep(",
            "tolerance",
            "epsilon",
            "711",
            "880",
            "-91",
        ] {
            XCTAssertFalse(
                quickPathOffAppSource.contains(prohibitedOffAppAction),
                prohibitedOffAppAction
            )
        }
        for retainedVisibleQuickPathLock in [
            "                let expectedKeyboardFrame = CGRect(\n" +
                "                    x: 0,\n" +
                "                    y: 451,\n" +
                "                    width: 375,\n" +
                "                    height: 216\n" +
                "                )",
            "                keyboard.coordinate(\n" +
                "                    withNormalizedOffset: CGVector(\n" +
                "                        dx: 0.5,\n" +
                "                        dy: 0.8425925925925926\n" +
                "                    )\n" +
                "                ).tap()",
            "                let expectedReturnFrame = CGRect(\n" +
                "                    x: 281.5,\n" +
                "                    y: 620,\n" +
                "                    width: 93.5,\n" +
                "                    height: 46\n" +
                "                )",
            "                          returnKey.elementType == .button,\n" +
                #"                          returnKey.identifier == "Return","# + "\n" +
                #"                          returnKey.label.lowercased() == "return","# + "\n" +
                "                          returnKey.frame == expectedReturnFrame,\n" +
                "                          returnKey.isHittable,",
        ] {
            let normalizedLock = retainedVisibleQuickPathLock
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            XCTAssertEqual(
                normalizedQuickPathVisibleSource.components(
                    separatedBy: normalizedLock
                ).count - 1,
                1,
                retainedVisibleQuickPathLock
            )
        }
        for prohibitedQuickPathForm in [
            "711",
            "880",
            "-91",
            "app.swipeUp()",
            "app.swipeDown()",
            "app.coordinate(",
            "Thread.sleep",
            "Task.sleep",
            "sleep(",
            "tolerance",
            "epsilon",
        ] {
            XCTAssertFalse(
                quickPathViewportToCaptureSource.contains(prohibitedQuickPathForm),
                prohibitedQuickPathForm
            )
        }
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(
                separatedBy: "returnKey.isHittable"
            ).count - 1,
            2
        )
        let quickPathExpectedFrame =
            "                let expectedKeyboardFrame = CGRect(\n" +
                "                    x: 0,\n" +
                "                    y: 451,\n" +
                "                    width: 375,\n" +
                "                    height: 216\n" +
                "                )"
        let normalizedQuickPathExpectedFrame = quickPathExpectedFrame
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        XCTAssertEqual(
            normalizedQuickPathVisibleSource.components(
                separatedBy: normalizedQuickPathExpectedFrame
            ).count - 1,
            1
        )
        let quickPathObservedFrame =
            "                let observedKeyboardFrame = keyboard.frame"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathObservedFrame).count - 1,
            1
        )
        let quickPathFrameFailure =
            "                        XCTFail(\"The iOS 18 keyboard frame does not match the frozen QuickPath tutorial evidence.\")\n" +
                "                        return\n" +
                "                    }"
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
        let normalizedQuickPathCoordinate = quickPathNormalizedCoordinate
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        XCTAssertEqual(
            normalizedQuickPathVisibleSource.components(
                separatedBy: normalizedQuickPathCoordinate
            ).count - 1,
            1
        )
        let quickPathRestoredKeyboard =
            "                let restoredKeyboard = app.keyboards.firstMatch\n" +
                "                let expectedReturnFrame = CGRect(\n" +
                "                    x: 281.5,\n" +
                "                    y: 620,\n" +
                "                    width: 93.5,\n" +
                "                    height: 46\n" +
                "                )"
        let normalizedQuickPathRestoredKeyboard = quickPathRestoredKeyboard
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        XCTAssertEqual(
            normalizedQuickPathVisibleSource.components(
                separatedBy: normalizedQuickPathRestoredKeyboard
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
            let normalizedLock = lock
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            XCTAssertEqual(
                normalizedQuickPathVisibleSource.components(
                    separatedBy: normalizedLock
                ).count - 1,
                1,
                lock
            )
        }
        let quickPathRestorationFailure =
            "                        XCTFail(\"The new-sign validation state or content was not restored after dismissing the QuickPath tutorial.\")\n" +
                "                        return\n" +
                "                    }"
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: quickPathRestorationFailure).count - 1,
            1
        )
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: "XCTFail(").count - 1,
            5
        )
        XCTAssertEqual(
            quickPathViewportToCaptureSource.components(separatedBy: "                    return\n").count - 1,
            5
        )
        let quickPathCapturePrecededByRestoration =
            quickPathRestorationFailure + "\n                }\n            }\n        }\n" + quickPathCapture
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
        XCTAssertEqual(keyboardHelperSource.utf8.count, 5_456)
        XCTAssertEqual(
            Data(keyboardHelperSource.utf8).sha256,
            "90449D0206CB73E7D739329EC932E170C179364F431B24B7951E637F40230DA9"
        )

        let passiveKeyboardHelperStart =
            "    @MainActor\n" +
                "    private func keyboardIsAbsentOrInertOffApp(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {"
        let passiveKeyboardHelperEnd = "\n\n" + keyboardHelperStart
        XCTAssertEqual(
            uiSource.components(separatedBy: passiveKeyboardHelperStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "keyboardIsAbsentOrInertOffApp("
            ).count - 1,
            4
        )
        guard let passiveKeyboardHelperStartRange = uiSource.range(
            of: passiveKeyboardHelperStart
        ), let passiveKeyboardHelperEndRange = uiSource.range(
            of: passiveKeyboardHelperEnd,
            range: passiveKeyboardHelperStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded passive keyboard postcondition helper")
            return
        }
        let passiveKeyboardHelperSource = String(
            uiSource[
                passiveKeyboardHelperStartRange.lowerBound..<passiveKeyboardHelperEndRange.lowerBound
            ]
        )
        XCTAssertEqual(passiveKeyboardHelperSource.utf8.count, 2_686)
        XCTAssertEqual(
            Data(passiveKeyboardHelperSource.utf8).sha256,
            "409318C12E31EC223DE3AA602085A378C1FEE6E35669FCC81413F3A341E57E34"
        )

        let passiveKeyboardHelperContracts = [
            "        let keyboardQuery = app.keyboards",
            "        let keyboardCount = keyboardQuery.count",
            "        if keyboardCount == 0 {",
            "            return app.state == .runningForeground",
            "        guard keyboardCount == 1,",
            #"              automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" else {"#,
            "        let keyboard = keyboardQuery.firstMatch",
            "        guard keyboard.exists else { return false }",
            "        let applicationFrame = app.frame",
            "        let keyboardFrame = keyboard.frame",
            "        let keyboardDescendants = keyboard.descendants(\n" +
                "            matching: .any\n" +
                "        )",
            "        let keyboardKeys = keyboard.keys",
            "        let keyboardDescendantCount = keyboardDescendants.count",
            "        let keyboardKeyCount = keyboardKeys.count",
            "        let keyboardDescendantElements =\n" +
                "            keyboardDescendants.allElementsBoundByIndex",
            "        let keyboardKeyElements = keyboardKeys.allElementsBoundByIndex",
            "        let focusIsAbsent = NSPredicate(\n" +
                #"            format: "hasKeyboardFocus == false""# + "\n" +
                "        )",
            "        let keyboardFocusIsAbsent = focusIsAbsent.evaluate(with: keyboard)",
            "        let isWhollyOffAppAndInert: (XCUIElement) -> Bool = { element in",
            "            guard element.exists else { return false }",
            "            let elementFrame = element.frame",
            "            return !elementFrame.isEmpty\n" +
                "                && elementFrame.minY >= applicationFrame.maxY\n" +
                "                && focusIsAbsent.evaluate(with: element)\n" +
                "                && !element.isHittable",
            "        let keyboardTreeIsEmpty =",
            "        let keyboardTreeIsNonemptyAndInert =",
            "            && (keyboardTreeIsEmpty || keyboardTreeIsNonemptyAndInert)",
            "        return !applicationFrame.isEmpty",
            "            && !keyboardFrame.isEmpty",
            "            && keyboardFrame.minY >= applicationFrame.maxY",
            "            && keyboardFocusIsAbsent",
            "            && !keyboard.isHittable",
            "            && (keyboardTreeIsEmpty || keyboardTreeIsNonemptyAndInert)",
            "            && app.state == .runningForeground",
        ]
        for contract in passiveKeyboardHelperContracts {
            XCTAssertTrue(
                passiveKeyboardHelperSource.contains(contract),
                contract
            )
        }
        for (passiveKeyboardHelperFragment, count) in [
            ("keyboardDescendantCount", 5),
            ("keyboardKeyCount", 5),
            ("keyboardDescendantElements", 4),
            ("keyboardKeyElements", 4),
            ("focusIsAbsent", 3),
            ("keyboardFocusIsAbsent", 2),
            ("isWhollyOffAppAndInert", 3),
            ("keyboardTreeIsEmpty", 2),
            ("keyboardTreeIsNonemptyAndInert", 2),
            ("allElementsBoundByIndex", 2),
            ("allSatisfy(", 2),
            ("return false", 3),
            ("return app.state == .runningForeground", 1),
            ("app.state == .runningForeground", 2),
        ] {
            XCTAssertEqual(
                passiveKeyboardHelperSource.components(
                    separatedBy: passiveKeyboardHelperFragment
                ).count - 1,
                count,
                passiveKeyboardHelperFragment
            )
        }
        for prohibitedPassiveKeyboardHelperForm in [
            "tap(",
            ".tap",
            "press(",
            "coordinate(",
            "swipe",
            "wait(",
            "waitFor",
            "timeout",
            "sleep(",
            "Thread.sleep",
            "dismissKeyboard(",
            "scroll(",
            "typeText(",
            "XCTAttachment",
            "printJSONLine",
            "attachCandidate",
            "performAccessibilityAudit",
            "audit",
            "automationAX",
            "automationContrast",
            "eligibleExceptions",
            "receipt",
            "711",
            "880",
            "402",
            "874",
            "375",
            "216",
            "CGRect(",
        ] {
            XCTAssertFalse(
                passiveKeyboardHelperSource.contains(
                    prohibitedPassiveKeyboardHelperForm
                ),
                prohibitedPassiveKeyboardHelperForm
            )
        }
        let postSwipeOffAppKeyboardAcceptance =
            "            if keyboardFrame.minY >= applicationFrame.maxY {\n" +
                "                app.swipeDown()\n" +
                "                if wait(\n" +
                "                    for: keyboard,\n" +
                #"                    predicate: "exists == false","# + "\n" +
                "                    timeout: 10\n" +
                "                ) {\n" +
                "                    guard app.state == .runningForeground else {\n" +
                "                        XCTFail(\n" +
                #"                            "The app left the foreground while dismissing the minimum-profile keyboard.""# + "\n" +
                "                        )\n" +
                "                        return\n" +
                "                    }\n" +
                "                    return\n" +
                "                }\n" +
                "                let postSwipeApplicationFrame = app.frame\n" +
                "                let postSwipeKeyboardFrame = keyboard.frame\n" +
                "                let keyboardDescendants = keyboard.descendants(\n" +
                "                    matching: .any\n" +
                "                )\n" +
                "                let keyboardKeys = keyboard.keys\n" +
                "                let keyboardDescendantCount = keyboardDescendants.count\n" +
                "                let keyboardKeyCount = keyboardKeys.count\n" +
                "                let keyboardDescendantElements =\n" +
                "                    keyboardDescendants.allElementsBoundByIndex\n" +
                "                let keyboardKeyElements = keyboardKeys.allElementsBoundByIndex\n" +
                "                let focusIsAbsent = NSPredicate(\n" +
                #"                    format: "hasKeyboardFocus == false""# + "\n" +
                "                )\n" +
                "                let keyboardFocusIsAbsent = focusIsAbsent.evaluate(with: keyboard)\n" +
                "                let isWhollyOffAppAndInert: (XCUIElement) -> Bool = { element in\n" +
                "                    guard element.exists else { return false }\n" +
                "                    let elementFrame = element.frame\n" +
                "                    return !elementFrame.isEmpty\n" +
                "                        && elementFrame.minY >= postSwipeApplicationFrame.maxY\n" +
                "                        && focusIsAbsent.evaluate(with: element)\n" +
                "                        && !element.isHittable\n" +
                "                }\n" +
                "                let keyboardTreeIsEmpty =\n" +
                "                    keyboardDescendantCount == 0\n" +
                "                    && keyboardKeyCount == 0\n" +
                "                    && keyboardDescendantElements.isEmpty\n" +
                "                    && keyboardKeyElements.isEmpty\n" +
                "                let keyboardTreeIsNonemptyAndInert =\n" +
                "                    keyboardDescendantCount > 0\n" +
                "                    && keyboardKeyCount > 0\n" +
                "                    && keyboardKeyCount <= keyboardDescendantCount\n" +
                "                    && keyboardDescendantElements.count\n" +
                "                        == keyboardDescendantCount\n" +
                "                    && keyboardKeyElements.count == keyboardKeyCount\n" +
                "                    && keyboardDescendantElements.allSatisfy(\n" +
                "                        isWhollyOffAppAndInert\n" +
                "                    )\n" +
                "                    && keyboardKeyElements.allSatisfy(\n" +
                "                        isWhollyOffAppAndInert\n" +
                "                    )\n" +
                "                guard !postSwipeApplicationFrame.isEmpty,\n" +
                "                      !postSwipeKeyboardFrame.isEmpty,\n" +
                "                      postSwipeKeyboardFrame.minY >= postSwipeApplicationFrame.maxY,\n" +
                "                      keyboardFocusIsAbsent,\n" +
                "                      keyboardTreeIsEmpty || keyboardTreeIsNonemptyAndInert,\n" +
                "                      app.state == .runningForeground else {\n" +
                "                    XCTFail(\n" +
                #"                        "The minimum-profile off-app keyboard wrapper did not become inert.""# + "\n" +
                "                    )\n" +
                "                    return\n" +
                "                }\n" +
                "                return\n" +
                "            } else {"
        XCTAssertEqual(
            keyboardHelperSource.components(
                separatedBy: postSwipeOffAppKeyboardAcceptance
            ).count - 1,
            1
        )
        let keyboardHelperLocks = [
            "let keyboard = app.keyboards.firstMatch",
            "guard keyboard.exists else { return }",
            #"let returnKey = keyboard.buttons["Return"]"#,
            "if returnKey.exists && returnKey.isHittable {",
            "returnKey.tap()",
            #"automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum""#,
            "&& returnKey.exists {",
            "let applicationFrame = app.frame",
            "let keyboardFrame = keyboard.frame",
            "guard !applicationFrame.isEmpty,",
            "!keyboardFrame.isEmpty else {",
            "keyboardFrame.minY >= applicationFrame.maxY",
            "let postSwipeApplicationFrame = app.frame",
            "let postSwipeKeyboardFrame = keyboard.frame",
            "let keyboardDescendants = keyboard.descendants(",
            "let keyboardKeys = keyboard.keys",
            "let keyboardDescendantCount = keyboardDescendants.count",
            "let keyboardKeyCount = keyboardKeys.count",
            "keyboardDescendants.allElementsBoundByIndex",
            "keyboardKeys.allElementsBoundByIndex",
            "let focusIsAbsent = NSPredicate(",
            #"format: "hasKeyboardFocus == false""#,
            "focusIsAbsent.evaluate(with: keyboard)",
            "let isWhollyOffAppAndInert: (XCUIElement) -> Bool = { element in",
            "guard element.exists else { return false }",
            "let elementFrame = element.frame",
            "!elementFrame.isEmpty",
            "elementFrame.minY >= postSwipeApplicationFrame.maxY",
            "focusIsAbsent.evaluate(with: element)",
            "!element.isHittable",
            "let keyboardTreeIsEmpty =",
            "let keyboardTreeIsNonemptyAndInert =",
            "postSwipeKeyboardFrame.minY >= postSwipeApplicationFrame.maxY",
            "keyboardDescendantCount == 0",
            "keyboardKeyCount == 0",
            "keyboardDescendantCount > 0",
            "keyboardKeyCount > 0",
            "keyboardKeyCount <= keyboardDescendantCount",
            "keyboardDescendantElements.count",
            "keyboardKeyElements.count == keyboardKeyCount",
            "keyboardDescendantElements.allSatisfy(",
            "keyboardKeyElements.allSatisfy(",
            "keyboardTreeIsEmpty || keyboardTreeIsNonemptyAndInert",
            #"The app left the foreground while dismissing the minimum-profile keyboard."#,
            #"The minimum-profile off-app keyboard wrapper did not become inert."#,
            "returnKey.elementType == .button",
            #"returnKey.label.lowercased() == "return""#,
            "let expectedKeyboardFrame = CGRect(",
            "x: 0,",
            "y: 451,",
            "width: 375,",
            "height: 216",
            "guard keyboardFrame == expectedKeyboardFrame,",
            "returnFrame.minX == 281.5",
            "returnFrame.width == 93.5",
            "keyboard.coordinate(",
            "withNormalizedOffset: CGVector(",
            "dx: 0.8753333333333333,",
            "dy: 0.5740740740740741",
            ").tap()",
            "app.swipeDown()",
            "        } else {\n" +
                "            app.swipeDown()\n" +
                "        }",
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
            2
        )
        XCTAssertEqual(
            keyboardHelperSource.components(
                separatedBy: #"predicate: "exists == false""#
            ).count - 1,
            2
        )
        XCTAssertEqual(
            keyboardHelperSource.components(separatedBy: "timeout: 10").count - 1,
            2
        )
        XCTAssertEqual(
            keyboardHelperSource.components(
                separatedBy: "app.state == .runningForeground"
            ).count - 1,
            3
        )
        for twiceLocked in [
            "allElementsBoundByIndex",
            "allSatisfy(",
            "focusIsAbsent.evaluate(with:",
            "keyboardTreeIsEmpty",
            "keyboardTreeIsNonemptyAndInert",
        ] {
            XCTAssertEqual(
                keyboardHelperSource.components(separatedBy: twiceLocked).count - 1,
                2,
                twiceLocked
            )
        }
        let exactKeyboardHelperCounts = [
            "keyboardDescendantCount": 5,
            "keyboardKeyCount": 5,
            "keyboardDescendantElements": 4,
            "keyboardKeyElements": 4,
            "focusIsAbsent": 3,
            "keyboardFocusIsAbsent": 2,
            "isWhollyOffAppAndInert": 3,
        ]
        for (lock, expectedCount) in exactKeyboardHelperCounts {
            XCTAssertEqual(
                keyboardHelperSource.components(separatedBy: lock).count - 1,
                expectedCount,
                lock
            )
        }
        for exactOnce in [
            "keyboardFrame.minY >= applicationFrame.maxY",
            "let postSwipeApplicationFrame = app.frame",
            "let postSwipeKeyboardFrame = keyboard.frame",
            "postSwipeKeyboardFrame.minY >= postSwipeApplicationFrame.maxY",
            #"format: "hasKeyboardFocus == false""#,
            "keyboard.descendants(",
            "matching: .any",
            "let keyboardKeys = keyboard.keys",
            "keyboardDescendantCount == 0",
            "keyboardKeyCount == 0",
            "keyboardDescendantCount > 0",
            "keyboardKeyCount > 0",
            "keyboardKeyCount <= keyboardDescendantCount",
            "guard element.exists else { return false }",
            "elementFrame.minY >= postSwipeApplicationFrame.maxY",
            "!element.isHittable",
            #"The app left the foreground while dismissing the minimum-profile keyboard."#,
            #"The minimum-profile off-app keyboard wrapper did not become inert."#,
        ] {
            XCTAssertEqual(
                keyboardHelperSource.components(separatedBy: exactOnce).count - 1,
                1,
                exactOnce
            )
        }
        XCTAssertFalse(keyboardHelperSource.contains("keyboard.hasKeyboardFocus"))
        for staleEmptyOnlyKeyboardForm in [
            "let keyboardFocusIsAbsent = NSPredicate(",
            "let keyboardKeyCount = keyboard.keys.count",
            "                      keyboardDescendantCount == 0,",
            "                      keyboardKeyCount == 0,",
        ] {
            XCTAssertFalse(
                keyboardHelperSource.contains(staleEmptyOnlyKeyboardForm),
                staleEmptyOnlyKeyboardForm
            )
        }
        let commonKeyboardPostcondition =
            "        guard wait(\n" +
                "            for: keyboard,\n" +
                #"            predicate: "exists == false","# + "\n" +
                "            timeout: 10\n" +
                "        ), app.state == .runningForeground else {"
        XCTAssertEqual(
            keyboardHelperSource.components(
                separatedBy: commonKeyboardPostcondition
            ).count - 1,
            1
        )
        for prohibitedKeyboardHelperForm in [
            "711",
            "880",
            "sleep(",
            "Thread.sleep",
            "tolerance",
            "epsilon",
            "ScrollView",
        ] {
            XCTAssertFalse(
                keyboardHelperSource.contains(prohibitedKeyboardHelperForm),
                prohibitedKeyboardHelperForm
            )
        }
        XCTAssertEqual(
            uiSource.components(separatedBy: "dismissKeyboard(in: app)").count - 1,
            6
        )
        let removedMinimumKeyboardDiagnosticForms = [
            "runMinimumKeyboardGeometryDiagnostic",
            "S10_4_MINIMUM_KEYBOARD_GEOMETRY_DIAGNOSTIC",
            "minimum keyboard geometry diagnostic completed nonaccepting",
            #"shard.shardID == "s10.4.minimum.minimum-os""#,
            #"identifier: "s2.new-sign.screen""#,
            #"identifier: "s2.sign-detail.screen""#,
            #"identifier: "s2.new-sign.sign-label""#,
            #"NSPredicate(format: "label == %@", "Return")"#,
            "minimum keyboard geometry app",
            "minimum keyboard geometry accessibility tree",
            "minimum keyboard geometry keyboard",
            "minimum keyboard geometry Return",
        ]
        for removed in removedMinimumKeyboardDiagnosticForms {
            XCTAssertFalse(uiSource.contains(removed), removed)
        }
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"NSPredicate(format: "identifier == %@", "inputView")"#
            ).count - 1,
            2
        )
        let restoredMinimumKeyboardCaller =
            #"        sign.typeText("Monument Sign")"# + "\n" +
                "        dismissKeyboard(in: app)\n" +
                #"        captureBaseline("state.new-sign.editing", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: restoredMinimumKeyboardCaller
            ).count - 1,
            1
        )

        let defaultKeyboardCallerLocks = [
            restoredMinimumKeyboardCaller,
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
        let northCampusKeyboardCallerStart =
            #"        site.typeText("North Campus")"#
        let northCampusKeyboardCallerEnd = "        scroll(save, in: app)"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: northCampusKeyboardCallerStart
            ).count - 1,
            1
        )
        guard let northCampusKeyboardCallerStartRange = uiSource.range(
            of: northCampusKeyboardCallerStart
        ), let northCampusKeyboardCallerEndRange = uiSource.range(
            of: northCampusKeyboardCallerEnd,
            range: northCampusKeyboardCallerStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded North Campus keyboard caller slice")
            return
        }
        let northCampusKeyboardCallerSource = String(
            uiSource[
                northCampusKeyboardCallerStartRange.lowerBound..<northCampusKeyboardCallerEndRange.lowerBound
            ]
        )
        let northCampusKeyboardCallerLocks = [
            #"automationShard?.deviceProfileID == "iphone-17-ios-26.2-current""#,
            #""Speed up your typing by sliding your finger across the letters to compose a word.""#,
            #"let currentQuickPathContinueLabel = "Continue""#,
            "let currentQuickPathTutorialTexts = app.staticTexts.matching(",
            "let currentQuickPathContinueButtons = app.buttons.matching(",
            "let currentQuickPathTutorialCount =\n                currentQuickPathTutorialTexts.count",
            "let currentQuickPathContinueCount =\n                currentQuickPathContinueButtons.count",
            "let currentQuickPathTutorialText =\n                    currentQuickPathTutorialTexts.firstMatch",
            "let currentQuickPathContinueButton =\n                    currentQuickPathContinueButtons.firstMatch",
            "let currentQuickPathKeyboard = app.keyboards.firstMatch",
            #"currentQuickPathKeyboard.buttons["Return"]"#,
            "if currentQuickPathTutorialCount > 0\n                || currentQuickPathContinueCount > 0 {",
            "currentQuickPathTutorialCount == 1",
            "currentQuickPathContinueCount == 1",
            "currentQuickPathTutorialText.exists",
            "currentQuickPathTutorialText.elementType == .staticText",
            "currentQuickPathTutorialText.identifier.isEmpty",
            "currentQuickPathTutorialText.label\n                        == currentQuickPathTutorialLabel",
            "currentQuickPathContinueButton.exists",
            "currentQuickPathContinueButton.elementType == .button",
            "currentQuickPathContinueButton.identifier.isEmpty",
            "currentQuickPathContinueButton.label\n                        == currentQuickPathContinueLabel",
            "currentQuickPathContinueButton.isEnabled",
            "currentQuickPathContinueButton.isHittable",
            "!applicationFrame.isNull",
            "!applicationFrame.isEmpty",
            "!currentQuickPathTutorialText.frame.isNull",
            "!currentQuickPathTutorialText.frame.isEmpty",
            "applicationFrame.contains(\n                          currentQuickPathTutorialText.frame\n                      )",
            "!currentQuickPathContinueButton.frame.isNull",
            "!currentQuickPathContinueButton.frame.isEmpty",
            "applicationFrame.contains(\n                          currentQuickPathContinueButton.frame\n                      )",
            "currentQuickPathKeyboard.exists",
            "currentQuickPathReturnKey.exists",
            "currentQuickPathReturnKey.elementType == .button",
            #"currentQuickPathReturnKey.identifier == "Return""#,
            #"currentQuickPathReturnKey.label.lowercased() == "return""#,
            "!currentQuickPathReturnKey.isHittable",
            "currentQuickPathNewSignRoute.exists",
            "!validationDetailRoute.exists",
            #"predicate: "hasKeyboardFocus == true""#,
            #"(site.value as? String) == "North Campus""#,
            #"(sign.value as? String) == "Monument Sign""#,
            "app.state == .runningForeground",
            "currentQuickPathContinueButton.tap()",
            "currentQuickPathTutorialText.waitForNonExistence(",
            "currentQuickPathContinueButton.waitForNonExistence(",
            "currentQuickPathReturnKey.waitForExistence(timeout: 10)",
            "currentQuickPathReturnKey.isHittable",
            "dismissKeyboard(in: app)\n        dismissKeyboard(in: app)\n        XCTAssertTrue(keyboardIsAbsentOrInertOffApp(in: app))",
        ]
        for lock in northCampusKeyboardCallerLocks {
            XCTAssertTrue(northCampusKeyboardCallerSource.contains(lock), lock)
        }
        let northCampusKeyboardCallerCounts: [(String, Int)] = [
            (#"site.typeText("North Campus")"#, 1),
            (#"automationShard?.deviceProfileID == "iphone-17-ios-26.2-current""#, 1),
            (#""Speed up your typing by sliding your finger across the letters to compose a word.""#, 1),
            (#"let currentQuickPathContinueLabel = "Continue""#, 1),
            ("app.staticTexts.matching(", 1),
            ("app.buttons.matching(", 1),
            (#"format: "label == %@""#, 2),
            ("currentQuickPathTutorialTexts.count", 1),
            ("currentQuickPathContinueButtons.count", 1),
            ("currentQuickPathTutorialTexts.firstMatch", 1),
            ("currentQuickPathContinueButtons.firstMatch", 1),
            ("if currentQuickPathTutorialCount > 0\n                || currentQuickPathContinueCount > 0 {", 1),
            ("currentQuickPathTutorialCount == 1", 1),
            ("currentQuickPathContinueCount == 1", 1),
            ("currentQuickPathTutorialText.exists", 1),
            ("currentQuickPathContinueButton.exists", 1),
            ("currentQuickPathTutorialText.elementType == .staticText", 1),
            ("currentQuickPathContinueButton.elementType == .button", 1),
            ("currentQuickPathReturnKey.elementType == .button", 2),
            (".identifier.isEmpty", 2),
            ("currentQuickPathContinueButton.isEnabled", 1),
            ("currentQuickPathContinueButton.isHittable", 1),
            ("!applicationFrame.isNull", 1),
            ("!applicationFrame.isEmpty", 1),
            ("!currentQuickPathTutorialText.frame.isNull", 1),
            ("!currentQuickPathTutorialText.frame.isEmpty", 1),
            ("!currentQuickPathContinueButton.frame.isNull", 1),
            ("!currentQuickPathContinueButton.frame.isEmpty", 1),
            ("applicationFrame.contains(", 2),
            ("currentQuickPathKeyboard.exists", 2),
            ("currentQuickPathReturnKey.exists", 1),
            ("currentQuickPathContinueButton.tap()", 1),
            ("waitForNonExistence(", 2),
            (#"currentQuickPathReturnKey.identifier == "Return""#, 2),
            (#"currentQuickPathReturnKey.label.lowercased() == "return""#, 2),
            ("currentQuickPathReturnKey.isHittable", 2),
            ("currentQuickPathNewSignRoute.exists", 2),
            ("!validationDetailRoute.exists", 2),
            (#"predicate: "hasKeyboardFocus == true""#, 2),
            (#"(site.value as? String) == "North Campus""#, 2),
            (#"(sign.value as? String) == "Monument Sign""#, 2),
            ("app.state == .runningForeground", 2),
            ("dismissKeyboard(in: app)", 2),
            ("XCTAssertTrue(keyboardIsAbsentOrInertOffApp(in: app))", 1),
            ("XCTFail(", 2),
            ("\n                    return\n", 2),
        ]
        for (lock, count) in northCampusKeyboardCallerCounts {
            XCTAssertEqual(
                northCampusKeyboardCallerSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }
        for prohibitedNorthCampusKeyboardCallerForm in [
            "CGRect(",
            "402",
            "874",
            "539",
            "583",
            "233",
            "737.333",
            "819",
            "224",
            "752",
            "99",
            ".coordinate(",
            "withNormalizedOffset",
            "withOffset",
            ".press(",
            ".swipe",
            "Thread.sleep",
            "sleep(",
            "tolerance",
            "epsilon",
            "currentQuickPathReturnKey.tap()",
            "for _ in",
            "while ",
            "s10.4.current.increased-contrast",
            "iphone-se-3-ios-18.0-minimum",
            "captureBaseline(",
            "performAccessibilityAudit",
            "printJSONLine",
            "S10_4_CANDIDATE",
            "S10_4_AX",
            "S10_4_CONTRAST",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "ContrastAuditExceptionSignature",
        ] {
            XCTAssertFalse(
                northCampusKeyboardCallerSource.contains(
                    prohibitedNorthCampusKeyboardCallerForm
                ),
                prohibitedNorthCampusKeyboardCallerForm
            )
        }
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "XCTAssertTrue(keyboardIsAbsentOrInertOffApp(in: app))"
            ).count - 1,
            1
        )
        let staleNorthCampusKeyboardCaller =
            #"        site.typeText("North Campus")"# + "\n" +
                "        dismissKeyboard(in: app)\n" +
                "        dismissKeyboard(in: app)\n" +
                "        XCTAssertTrue(wait(\n" +
                "            for: app.keyboards.firstMatch,\n" +
                #"            predicate: "exists == false","# + "\n" +
                "            timeout: 10\n" +
                "        ))"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: staleNorthCampusKeyboardCaller
            ).count - 1,
            0
        )
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
        let multilinePassiveKeyboardHelperStart =
            "    @MainActor\n" +
                "    private func keyboardIsAbsentOrInertOffApp("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: multilinePassiveKeyboardHelperStart
            ).count - 1,
            1
        )
        guard let multilineHelperStartRange = uiSource.range(of: multilineHelperStart),
              let multilinePassiveKeyboardHelperStartRange = uiSource.range(
                of: multilinePassiveKeyboardHelperStart,
                range: multilineHelperStartRange.upperBound..<uiSource.endIndex
              ) else {
            XCTFail("Missing the dedicated multiline keyboard helper source slice")
            return
        }
        let multilineHelperSource = String(
            uiSource[
                multilineHelperStartRange.lowerBound..<multilinePassiveKeyboardHelperStartRange.lowerBound
            ]
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

        let workSavingPositioningStart =
            "        XCTAssertTrue(progress.waitForExistence(timeout: 10))\n" +
                #"        assertLocalizedLabel(progress, equals: "Record work")"#
        let workSavingPositioningEnd =
            #"        captureBaseline("state.work.saving", in: app)"#
        XCTAssertEqual(
            uiSource.components(separatedBy: workSavingPositioningStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: workSavingPositioningEnd).count - 1,
            1
        )
        guard let workSavingPositioningStartRange = uiSource.range(
            of: workSavingPositioningStart
        ), let workSavingPositioningEndRange = uiSource.range(
            of: workSavingPositioningEnd,
            range: workSavingPositioningStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded Record-work saving positioning slice")
            return
        }
        let workSavingPositioningSource = String(
            uiSource[
                workSavingPositioningStartRange.lowerBound..<workSavingPositioningEndRange.upperBound
            ]
        )

        let workSavingNoteAndTabBindings =
            "        let workNoteHeadings = app.staticTexts.matching(\n" +
                #"            NSPredicate(format: "label == %@", "Note")"# + "\n" +
                "        )\n" +
                "        let workTabBars = app.tabBars\n" +
                "        let workNoteHeading = workNoteHeadings.firstMatch\n" +
                "        let workTabBar = workTabBars.firstMatch"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingNoteAndTabBindings
            ).count - 1,
            1
        )

        let workSavingInitialGuard =
            "        guard app.state == .runningForeground,\n" +
                "              workNoteHeadings.count == 1,\n" +
                "              workTabBars.count == 1,\n" +
                "              workHelperTexts.count == 1,\n" +
                "              workScrollViews.count == 1,\n" +
                "              workNavigationBars.count == 1,\n" +
                "              workNoteHeading.exists,\n" +
                "              workTabBar.exists,\n" +
                "              workNoteHeading.identifier.isEmpty,\n" +
                #"              workNoteHeading.label == "Note","# + "\n" +
                "              workNoteHeading.elementType == .staticText,\n" +
                "              workHelper.exists,\n" +
                "              workScrollView.exists,\n" +
                "              workNavigationBar.exists,\n" +
                "              workPreview.exists,\n" +
                "              progress.exists else {\n" +
                #"            XCTFail("Record-work saving positioning route changed.")"# + "\n" +
                "            return\n" +
                "        }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingInitialGuard
            ).count - 1,
            1
        )

        let workSavingLoopGuard =
            "            guard app.state == .runningForeground,\n" +
                "                  workNoteHeadings.count == 1,\n" +
                "                  workTabBars.count == 1,\n" +
                "                  workHelperTexts.count == 1,\n" +
                "                  workScrollViews.count == 1,\n" +
                "                  workNavigationBars.count == 1,\n" +
                "                  workNoteHeading.exists,\n" +
                "                  workTabBar.exists,\n" +
                "                  workHelper.exists,\n" +
                "                  workScrollView.exists,\n" +
                "                  workNavigationBar.exists,\n" +
                "                  workPreview.exists,\n" +
                "                  progress.exists else {\n" +
                #"                XCTFail("Record-work saving positioning route changed.")"# + "\n" +
                "                return\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingLoopGuard
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: "        for _ in 0..<4 {"
            ).count - 1,
            1
        )

        let workSavingLiveGeometry =
            "            let scrollFrame = workScrollView.frame\n" +
                "            let applicationFrame = app.frame\n" +
                "            let navigationFrame = workNavigationBar.frame\n" +
                "            let liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                "            let tabBarFrame = workTabBar.frame\n" +
                "            let liveBottom = min(\n" +
                "                liveScrollFrame.maxY,\n" +
                "                min(applicationFrame.maxY, tabBarFrame.minY)\n" +
                "            )\n" +
                "            let safeTop = max(\n" +
                "                liveScrollFrame.minY,\n" +
                "                navigationFrame.maxY\n" +
                "            ) + verticalInset\n" +
                "            let safeBottom = liveBottom - verticalInset\n" +
                "            let receiverTop = max(\n" +
                "                liveScrollFrame.minY,\n" +
                "                navigationFrame.maxY\n" +
                "            ) + receiverInset\n" +
                "            let receiverBottom = liveBottom - receiverInset\n" +
                "            let noteFrame = workNoteHeading.frame\n" +
                "            let helperFrame = workHelper.frame\n" +
                "            let targetTop = min(noteFrame.minY, helperFrame.minY)\n" +
                "            let targetBottom = max(noteFrame.maxY, helperFrame.maxY)"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingLiveGeometry
            ).count - 1,
            1
        )
        let workSavingGeometryGuard =
            "            guard !applicationFrame.isNull,\n" +
                "                  !applicationFrame.isEmpty,\n" +
                "                  !navigationFrame.isNull,\n" +
                "                  !navigationFrame.isEmpty,\n" +
                "                  !scrollFrame.isNull,\n" +
                "                  !scrollFrame.isEmpty,\n" +
                "                  !liveScrollFrame.isNull,\n" +
                "                  !liveScrollFrame.isEmpty,\n" +
                "                  !tabBarFrame.isNull,\n" +
                "                  !tabBarFrame.isEmpty,\n" +
                "                  !noteFrame.isNull,\n" +
                "                  !noteFrame.isEmpty,\n" +
                "                  !helperFrame.isNull,\n" +
                "                  !helperFrame.isEmpty,\n" +
                "                  safeBottom > safeTop,\n" +
                "                  targetBottom - targetTop <= safeBottom - safeTop else {"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingGeometryGuard
            ).count - 1,
            1
        )
        let workSavingStopCondition =
            "            if noteFrame.minY >= safeTop,\n" +
                "               noteFrame.maxY <= safeBottom,\n" +
                "               helperFrame.minY >= safeTop,\n" +
                "               helperFrame.maxY <= safeBottom,\n" +
                "               workNoteHeading.isHittable,\n" +
                "               workHelper.isHittable {\n" +
                "                break\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingStopCondition
            ).count - 1,
            1
        )

        let workSavingSignedInterval =
            "            let minimumShift = max(\n" +
                "                safeTop - noteFrame.minY,\n" +
                "                safeTop - helperFrame.minY\n" +
                "            )\n" +
                "            let maximumShift = min(\n" +
                "                safeBottom - noteFrame.maxY,\n" +
                "                safeBottom - helperFrame.maxY\n" +
                "            )\n" +
                "            let receiverCapacity = receiverBottom - receiverTop\n" +
                "            guard minimumShift <= maximumShift,\n" +
                "                  receiverCapacity >= minimumGestureDistance else {\n" +
                #"                XCTFail("Record-work saving has no feasible recognized shift.")"# + "\n" +
                "                return\n" +
                "            }\n" +
                "            let dragDistance: CGFloat\n" +
                "            if maximumShift < 0 {\n" +
                "                let recognizedMinimum = max(\n" +
                "                    minimumShift,\n" +
                "                    -receiverCapacity\n" +
                "                )\n" +
                "                let recognizedMaximum = min(\n" +
                "                    maximumShift,\n" +
                "                    -minimumGestureDistance\n" +
                "                )\n" +
                "                guard recognizedMinimum <= recognizedMaximum else {\n" +
                #"                    XCTFail("Record-work saving upward shift is not recognizable.")"# + "\n" +
                "                    return\n" +
                "                }\n" +
                "                dragDistance = recognizedMaximum\n" +
                "            } else if minimumShift > 0 {\n" +
                "                let recognizedMinimum = max(\n" +
                "                    minimumShift,\n" +
                "                    minimumGestureDistance\n" +
                "                )\n" +
                "                let recognizedMaximum = min(\n" +
                "                    maximumShift,\n" +
                "                    receiverCapacity\n" +
                "                )\n" +
                "                guard recognizedMinimum <= recognizedMaximum else {\n" +
                #"                    XCTFail("Record-work saving downward shift is not recognizable.")"# + "\n" +
                "                    return\n" +
                "                }\n" +
                "                dragDistance = recognizedMinimum\n" +
                "            } else {\n" +
                #"                XCTFail("Record-work saving feasible shift is directionless.")"# + "\n" +
                "                return\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingSignedInterval
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: "                CGVector(dx: 0, dy: dragDistance)"
            ).count - 1,
            1
        )

        let workSavingDirectGesture =
            "            let scrollOrigin = workScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )\n" +
                "            let dragStartY = dragDistance > 0 ? receiverTop : receiverBottom\n" +
                "            let dragStart = scrollOrigin.withOffset(\n" +
                "                CGVector(\n" +
                "                    dx: scrollFrame.width / 2,\n" +
                "                    dy: dragStartY - scrollFrame.minY\n" +
                "                )\n" +
                "            )\n" +
                "            let dragEnd = dragStart.withOffset(\n" +
                "                CGVector(dx: 0, dy: dragDistance)\n" +
                "            )\n" +
                "            let noteMinYBeforeDrag = noteFrame.minY\n" +
                "            let helperMinYBeforeDrag = helperFrame.minY\n" +
                "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingDirectGesture
            ).count - 1,
            1
        )
        let workSavingObservedShiftGuard =
            "            let observedNoteShift = workNoteHeading.frame.minY - noteMinYBeforeDrag\n" +
                "            let observedHelperShift = workHelper.frame.minY - helperMinYBeforeDrag\n" +
                "            guard workNoteHeadings.count == 1,\n" +
                "                  workTabBars.count == 1,\n" +
                "                  workHelperTexts.count == 1,\n" +
                "                  workScrollViews.count == 1,\n" +
                "                  workNavigationBars.count == 1,\n" +
                "                  workNoteHeading.exists,\n" +
                "                  workTabBar.exists,\n" +
                "                  workHelper.exists,\n" +
                "                  progress.exists,\n" +
                "                  observedNoteShift * dragDistance > 0,\n" +
                "                  observedHelperShift * dragDistance > 0 else {\n" +
                #"                XCTFail("Record-work saving positioning gesture was not recognized.")"# + "\n" +
                "                return\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingObservedShiftGuard
            ).count - 1,
            1
        )
        for (workSavingDirectGestureLock, count) in [
            ("workScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: workSavingDirectGestureLock
                ).count - 1,
                count,
                workSavingDirectGestureLock
            )
        }

        for savingFinalFrameBinding in [
            "        let savingFinalApplicationFrame = app.frame",
            "        let savingFinalNavigationFrame = workNavigationBar.frame",
            "        let savingFinalScrollFrame = workScrollView.frame.intersection(",
            "        let savingFinalSafeTop = max(",
            "        let savingFinalTabBarFrame = workTabBar.frame",
            "        let savingFinalLiveBottom = min(",
            "            min(savingFinalApplicationFrame.maxY, savingFinalTabBarFrame.minY)",
            "        let savingFinalSafeBottom = savingFinalLiveBottom - verticalInset",
            "        let savingFinalNoteFrame = workNoteHeading.frame",
            "        let savingFinalHelperFrame = workHelper.frame",
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: savingFinalFrameBinding
                ).count - 1,
                1,
                savingFinalFrameBinding
            )
        }
        let workSavingFinalGuard =
            "        guard app.state == .runningForeground,\n" +
                "              workNoteHeadings.count == 1,\n" +
                "              workTabBars.count == 1,\n" +
                "              workHelperTexts.count == 1,\n" +
                "              workScrollViews.count == 1,\n" +
                "              workNavigationBars.count == 1,\n" +
                "              workNoteHeading.exists,\n" +
                "              workTabBar.exists,\n" +
                "              workNoteHeading.identifier.isEmpty,\n" +
                #"              workNoteHeading.label == "Note","# + "\n" +
                "              workNoteHeading.elementType == .staticText,\n" +
                "              workHelper.exists,\n" +
                "              workScrollView.exists,\n" +
                "              workNavigationBar.exists,\n" +
                "              workPreview.exists,\n" +
                "              progress.exists,\n" +
                "              !savingFinalApplicationFrame.isNull,\n" +
                "              !savingFinalApplicationFrame.isEmpty,\n" +
                "              !savingFinalNavigationFrame.isNull,\n" +
                "              !savingFinalNavigationFrame.isEmpty,\n" +
                "              !savingFinalScrollFrame.isNull,\n" +
                "              !savingFinalScrollFrame.isEmpty,\n" +
                "              !savingFinalTabBarFrame.isNull,\n" +
                "              !savingFinalTabBarFrame.isEmpty,\n" +
                "              !savingFinalNoteFrame.isNull,\n" +
                "              !savingFinalNoteFrame.isEmpty,\n" +
                "              !savingFinalHelperFrame.isNull,\n" +
                "              !savingFinalHelperFrame.isEmpty,\n" +
                "              savingFinalSafeBottom > savingFinalSafeTop,\n" +
                "              savingFinalNoteFrame.minY >= savingFinalSafeTop,\n" +
                "              savingFinalNoteFrame.maxY <= savingFinalSafeBottom,\n" +
                "              savingFinalHelperFrame.minY >= savingFinalSafeTop,\n" +
                "              savingFinalHelperFrame.maxY <= savingFinalSafeBottom,\n" +
                "              workNoteHeading.isHittable,\n" +
                "              workHelper.isHittable,\n" +
                "              workPreview.isHittable else {\n" +
                #"            XCTFail("Record-work saving composition is outside the safe viewport.")"# + "\n" +
                "            return\n" +
                "        }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingFinalGuard
            ).count - 1,
            1
        )
        let workSavingFinalGuardAndCapture =
            workSavingFinalGuard + "\n" + workSavingPositioningEnd
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingFinalGuardAndCapture
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: "captureBaseline("
            ).count - 1,
            1
        )

        for (workSavingCardinalityLock, count) in [
            ("app.state == .runningForeground", 3),
            ("workNoteHeadings.count == 1", 4),
            ("workTabBars.count == 1", 4),
            ("workHelperTexts.count == 1", 4),
            ("workScrollViews.count == 1", 4),
            ("workNavigationBars.count == 1", 4),
            ("workNoteHeading.exists", 4),
            ("workTabBar.exists", 4),
            ("workNoteHeading.identifier.isEmpty", 2),
            (#"workNoteHeading.label == "Note""#, 2),
            ("workNoteHeading.elementType == .staticText", 2),
            ("workHelper.exists", 4),
            ("workScrollView.exists", 3),
            ("workNavigationBar.exists", 3),
            ("workPreview.exists", 3),
            ("progress.exists", 4),
            ("workNoteHeading.isHittable", 2),
            ("workHelper.isHittable", 2),
            ("workPreview.isHittable", 1),
            ("workTabBar.frame", 2),
            ("workNoteHeading.frame", 3),
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: workSavingCardinalityLock
                ).count - 1,
                count,
                workSavingCardinalityLock
            )
        }

        for staleWorkSavingPositioningForm in [
            "let workHelperLabel =",
            "let workHelperTexts =",
            "let workScrollViews =",
            "let workNavigationBars =",
            "let workHelper =",
            "let workScrollView =",
            "let workNavigationBar =",
            "let workPreview =",
            "let verticalInset",
            "let receiverInset",
            "let minimumGestureDistance",
            "let safeBottom = liveScrollFrame.maxY - verticalInset",
            "let receiverBottom = liveScrollFrame.maxY - receiverInset",
            "let savingFinalSafeBottom = savingFinalScrollFrame.maxY - verticalInset",
            "helperFrame.height <= safeBottom - safeTop",
            "if helperFrame.minY >= safeTop",
            "guard minimumShift > 0",
            "Record-work saving has no feasible downward correction.",
            "workHelper.frame.minY > helperMinYBeforeDrag",
            "automationShard",
            "ContrastAuditExceptionSignature",
            "app.swipeUp()",
            "app.swipeDown()",
            "workScrollView.swipeUp()",
            "workScrollView.swipeDown()",
            "app.coordinate(",
            "scroll(",
            "CGRect(",
            "Thread.sleep",
            "sleep(",
            "epsilon",
            "tolerance",
            "performAccessibilityAudit(",
            "XCTAttachment(",
            "printJSONLine(",
            "attachCandidate(",
            "automationContrastExceptions",
            "automationAXTreeDigests",
            "eligibleExceptions",
            "receipt",
            "throw ",
            "tap(",
            "swipe",
            "diagnostic",
            "audit",
            #"captureBaseline("state.work.editing"#,
            #"captureBaseline("state.report-correction"#,
        ] {
            XCTAssertFalse(
                workSavingPositioningSource.contains(
                    staleWorkSavingPositioningForm
                ),
                staleWorkSavingPositioningForm
            )
        }

        let reportHistoryLowerNorthCall =
            "            guard positionLowerNorthCampusForAXText(in: app) else { return }"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reportHistoryLowerNorthCall
            ).count - 1,
            1
        )
        let reportHistoryAXPositioningCall =
            #"        XCTAssertTrue(element("s4.4.reports.view-report", in: app)"# + "\n" +
                "            .waitForExistence(timeout: 20))\n" +
                #"        if automationShard?.shardID == "s10.4.current.ax-text" {"# + "\n" +
                "            guard positionLowerNorthCampusForAXText(in: app) else { return }\n" +
                "            guard positionReportHistoryHeaderAndVisitForAXTextDiagnostic(\n" +
                "                in: app\n" +
                "            ) else { return }\n" +
                "        }\n" +
                #"        captureBaseline("state.report-history.ready", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reportHistoryAXPositioningCall
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"        XCTAssertTrue(element("s4.4.reports.view-report", in: app)"# + "\n" +
                    "            .waitForExistence(timeout: 20))"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "positionLowerNorthCampusForAXText("
            ).count - 1,
            2
        )

        let reportHistoryPositioningStart =
            "    @MainActor\n" +
                "    private func positionLowerNorthCampusForAXText(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {"
        let reportHistoryPositioningEnd =
            "\n\n    @MainActor\n" +
                "    private func positionReportHistoryHeaderAndVisitForAXTextDiagnostic("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reportHistoryPositioningStart
            ).count - 1,
            1
        )
        guard let reportHistoryPositioningStartRange = uiSource.range(
            of: reportHistoryPositioningStart
        ), let reportHistoryPositioningEndRange = uiSource.range(
            of: reportHistoryPositioningEnd,
            range: reportHistoryPositioningStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text report-history positioning helper")
            return
        }
        let reportHistoryPositioningSource = String(
            uiSource[
                reportHistoryPositioningStartRange.lowerBound..<reportHistoryPositioningEndRange.lowerBound
            ]
        )
        XCTAssertEqual(reportHistoryPositioningSource.utf8.count, 10_461)
        XCTAssertEqual(
            Data(reportHistoryPositioningSource.utf8).sha256,
            "6C7119CAD86A5470FF53AB8E310923C124EB1ACA25AFF2F2270236B8BB85D74F"
        )

        let reportHistoryPositioningBindings = [
            "let historyScreens = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s4.4.history.screen""#,
            "let historyHeaders = app.staticTexts.matching(\n" +
                #"            identifier: "s4.4.history.header""#,
            "let northCampusTexts = app.staticTexts.matching(\n" +
                #"            NSPredicate(format: "label == %@", "North Campus")"#,
            "let viewReportControls = app.buttons.matching(\n" +
                #"            identifier: "s4.4.reports.view-report""#,
            "let historyScrollViews = app.scrollViews.containing(\n" +
                "            .button,\n" +
                #"            identifier: "s4.4.reports.view-report""#,
            "let historyNavigationBars = app.navigationBars.matching(\n" +
                #"            identifier: "Report history""#,
            "let historyTabBars = app.tabBars",
            "let historyScreen = historyScreens.firstMatch",
            "let historyHeader = historyHeaders.firstMatch",
            "let viewReportControl = viewReportControls.firstMatch",
            "let historyScrollView = historyScrollViews.firstMatch",
            "let historyNavigationBar = historyNavigationBars.firstMatch",
            "let historyTabBar = historyTabBars.firstMatch",
        ]
        for binding in reportHistoryPositioningBindings {
            XCTAssertEqual(
                reportHistoryPositioningSource.components(
                    separatedBy: binding
                ).count - 1,
                1,
                binding
            )
        }

        let lowerNorthCampusResolver =
            "        func lowerNorthCampus() -> XCUIElement? {\n" +
                "            guard northCampusTexts.count == 2 else {\n" +
                #"                XCTFail("Report-history North Campus cardinality is ambiguous.")"# + "\n" +
                "                return nil\n" +
                "            }\n" +
                "            let first = northCampusTexts.element(boundBy: 0)\n" +
                "            let second = northCampusTexts.element(boundBy: 1)\n" +
                "            let firstFrame = first.frame\n" +
                "            let secondFrame = second.frame\n" +
                "            guard first.exists,\n" +
                "                  second.exists,\n" +
                "                  first.identifier.isEmpty,\n" +
                "                  second.identifier.isEmpty,\n" +
                #"                  first.label == "North Campus","# + "\n" +
                #"                  second.label == "North Campus","# + "\n" +
                "                  first.elementType == .staticText,\n" +
                "                  second.elementType == .staticText,\n" +
                "                  !firstFrame.isNull,\n" +
                "                  !firstFrame.isEmpty,\n" +
                "                  !secondFrame.isNull,\n" +
                "                  !secondFrame.isEmpty,\n" +
                "                  firstFrame != secondFrame,\n" +
                "                  (\n" +
                "                    firstFrame.maxY < secondFrame.minY\n" +
                "                        || secondFrame.maxY < firstFrame.minY\n" +
                "                  ) else {\n" +
                #"                XCTFail("Report-history North Campus frames are not strictly ordered.")"# + "\n" +
                "                return nil\n" +
                "            }\n" +
                "            return firstFrame.minY > secondFrame.minY ? first : second\n" +
                "        }"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: lowerNorthCampusResolver
            ).count - 1,
            1
        )

        let reportHistoryLiveGeometry =
            "            let scrollFrame = historyScrollView.frame\n" +
                "            let applicationFrame = app.frame\n" +
                "            let navigationFrame = historyNavigationBar.frame\n" +
                "            let tabBarFrame = historyTabBar.frame\n" +
                "            let liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)\n" +
                "            let liveBottom = min(\n" +
                "                liveScrollFrame.maxY,\n" +
                "                min(applicationFrame.maxY, tabBarFrame.minY)\n" +
                "            )\n" +
                "            let safeTop = liveTop + contentInset\n" +
                "            let safeBottom = liveBottom - contentInset\n" +
                "            let receiverTop = liveTop + receiverInset\n" +
                "            let receiverBottom = liveBottom - receiverInset\n" +
                "            let lowerFrame = lowerSite.frame"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: reportHistoryLiveGeometry
            ).count - 1,
            1
        )
        let reportHistoryNegativeInterval =
            "            let minimumShift = safeTop - lowerFrame.minY\n" +
                "            let maximumShift = safeBottom - lowerFrame.maxY\n" +
                "            let receiverCapacity = receiverBottom - receiverTop\n" +
                "            guard minimumShift <= maximumShift,\n" +
                "                  maximumShift < 0,\n" +
                "                  receiverCapacity >= minimumGestureDistance else {\n" +
                #"                XCTFail("Report-history AX-text requires no feasible negative shift.")"# + "\n" +
                "                return false\n" +
                "            }\n" +
                "            let recognizedMinimum = max(\n" +
                "                minimumShift,\n" +
                "                -receiverCapacity\n" +
                "            )\n" +
                "            let recognizedMaximum = min(\n" +
                "                maximumShift,\n" +
                "                -minimumGestureDistance\n" +
                "            )\n" +
                "            guard recognizedMinimum <= recognizedMaximum,\n" +
                "                  recognizedMaximum < 0 else {\n" +
                #"                XCTFail("Report-history AX-text upward shift is not recognizable.")"# + "\n" +
                "                return false\n" +
                "            }\n" +
                "            let dragDistance = recognizedMaximum\n" +
                "            guard abs(dragDistance) >= minimumGestureDistance else {\n" +
                #"                XCTFail("Report-history AX-text positioning gesture undertravels.")"# + "\n" +
                "                return false\n" +
                "            }"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: reportHistoryNegativeInterval
            ).count - 1,
            1
        )

        let reportHistoryDirectGesture =
            "            let scrollOrigin = historyScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )\n" +
                "            let dragStart = scrollOrigin.withOffset(\n" +
                "                CGVector(\n" +
                "                    dx: scrollFrame.width / 2,\n" +
                "                    dy: receiverBottom - scrollFrame.minY\n" +
                "                )\n" +
                "            )\n" +
                "            let dragEnd = dragStart.withOffset(\n" +
                "                CGVector(dx: 0, dy: dragDistance)\n" +
                "            )\n" +
                "            let lowerMinYBeforeDrag = lowerFrame.minY\n" +
                "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: reportHistoryDirectGesture
            ).count - 1,
            1
        )
        let reportHistoryObservedShift =
            "            let observedShift = movedLowerSite.frame.minY - lowerMinYBeforeDrag\n" +
                "            guard observedShift < 0,\n" +
                "                  observedShift * dragDistance > 0 else {\n" +
                #"                XCTFail("Report-history AX-text positioning gesture was not recognized.")"# + "\n" +
                "                return false\n" +
                "            }"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: reportHistoryObservedShift
            ).count - 1,
            1
        )

        let reportHistoryFinalGeometry =
            "        let finalApplicationFrame = app.frame\n" +
                "        let finalNavigationFrame = historyNavigationBar.frame\n" +
                "        let finalTabBarFrame = historyTabBar.frame\n" +
                "        let finalScrollFrame = historyScrollView.frame.intersection(\n" +
                "            finalApplicationFrame\n" +
                "        )\n" +
                "        let finalSafeTop = max(\n" +
                "            finalScrollFrame.minY,\n" +
                "            finalNavigationFrame.maxY\n" +
                "        ) + contentInset\n" +
                "        let finalSafeBottom = min(\n" +
                "            finalScrollFrame.maxY,\n" +
                "            min(finalApplicationFrame.maxY, finalTabBarFrame.minY)\n" +
                "        ) - contentInset\n" +
                "        let finalLowerFrame = finalLowerSite.frame"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: reportHistoryFinalGeometry
            ).count - 1,
            1
        )
        let reportHistoryFinalContainment =
            "              finalSafeBottom > finalSafeTop,\n" +
                "              finalLowerFrame.minY >= finalSafeTop,\n" +
                "              finalLowerFrame.maxY <= finalSafeBottom,\n" +
                "              finalLowerSite.isHittable else {\n" +
                #"            XCTFail("Report-history lower North Campus is outside the safe viewport.")"# + "\n" +
                "            return false\n" +
                "        }\n" +
                "        return true"
        XCTAssertEqual(
            reportHistoryPositioningSource.components(
                separatedBy: reportHistoryFinalContainment
            ).count - 1,
            1
        )

        for (reportHistoryCardinalityLock, count) in [
            ("app.state == .runningForeground", 3),
            ("historyScreens.count == 1", 3),
            ("historyHeaders.count == 1", 3),
            ("viewReportControls.count == 1", 3),
            ("historyScrollViews.count == 1", 3),
            ("historyNavigationBars.count == 1", 3),
            ("historyTabBars.count == 1", 3),
            ("historyScreen.exists", 3),
            ("historyHeader.exists", 3),
            ("viewReportControl.exists", 3),
            ("historyScrollView.exists", 3),
            ("historyNavigationBar.exists", 3),
            ("historyTabBar.exists", 3),
            ("lowerNorthCampus()", 4),
            ("northCampusTexts.count == 2", 1),
            ("northCampusTexts.element(boundBy:", 2),
            ("for _ in 0..<4", 1),
            ("historyScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
            ("return true", 2),
        ] {
            XCTAssertEqual(
                reportHistoryPositioningSource.components(
                    separatedBy: reportHistoryCardinalityLock
                ).count - 1,
                count,
                reportHistoryCardinalityLock
            )
        }
        for prohibitedReportHistoryPositioningForm in [
            "app.coordinate(",
            "app.swipe",
            "historyScrollView.swipe",
            "scroll(",
            "tap(",
            "CGRect(",
            "Thread.sleep",
            "sleep(",
            "epsilon",
            "tolerance",
            "performAccessibilityAudit(",
            "ContrastAuditExceptionSignature",
            "captureBaseline(",
            "attachCandidate(",
            "printJSONLine(",
            "automationContrastExceptions",
            "automationAXTreeDigests",
            "eligibleExceptions",
            "receipt",
            "throw ",
            "minimumShift > 0",
            "maximumShift >= 0",
        ] {
            XCTAssertFalse(
                reportHistoryPositioningSource.contains(
                    prohibitedReportHistoryPositioningForm
                ),
                prohibitedReportHistoryPositioningForm
            )
        }

        let reportHistoryDiagnosticPositioningStart =
            "    @MainActor\n" +
                "    private func positionReportHistoryHeaderAndVisitForAXTextDiagnostic(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {"
        let reportHistoryDiagnosticPositioningEnd =
            "\n\n    @MainActor\n" +
                "    private func completeWorkAndResolvedRecheckAtXXXL("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reportHistoryDiagnosticPositioningStart
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "positionReportHistoryHeaderAndVisitForAXTextDiagnostic("
            ).count - 1,
            2
        )
        guard let reportHistoryDiagnosticPositioningStartRange = uiSource.range(
            of: reportHistoryDiagnosticPositioningStart
        ), let reportHistoryDiagnosticPositioningEndRange = uiSource.range(
            of: reportHistoryDiagnosticPositioningEnd,
            range: reportHistoryDiagnosticPositioningStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded positioned AX-text Report-history helper")
            return
        }
        let reportHistoryDiagnosticPositioningSource = String(
            uiSource[
                reportHistoryDiagnosticPositioningStartRange.lowerBound..<reportHistoryDiagnosticPositioningEndRange.lowerBound
            ]
        )
        XCTAssertEqual(reportHistoryDiagnosticPositioningSource.utf8.count, 13_066)
        XCTAssertEqual(
            Data(reportHistoryDiagnosticPositioningSource.utf8).sha256,
            "CF59279AB3B55DD4DA485361FBDA659234DE3B753403AB9F22AC330E33181C02"
        )

        let reportHistoryDiagnosticPositioningQueries = [
            "let historyScreens = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s4.4.history.screen""#,
            "let historyHeaders = app.staticTexts.matching(\n" +
                #"            identifier: "s4.4.history.header""#,
            "let northCampusTexts = app.staticTexts.matching(\n" +
                #"            NSPredicate(format: "label == %@", "North Campus")"#,
            "let viewReportControls = app.buttons.matching(\n" +
                #"            identifier: "s4.4.reports.view-report""#,
            "let historyScrollViews = app.scrollViews.containing(\n" +
                "            .button,\n" +
                #"            identifier: "s4.4.reports.view-report""#,
            "let historyNavigationBars = app.navigationBars.matching(\n" +
                #"            identifier: "Report history""#,
            "let historyTabBars = app.tabBars",
            "let reportHistoryVisits = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s4.4.reports.visit""#,
            "let visitComposites = reportHistoryVisit.descendants(\n" +
                "            matching: .staticText\n" +
                "        ).matching(\n" +
                #"            NSPredicate(format: "label BEGINSWITH %@", "Visit, ")"#,
        ]
        XCTAssertEqual(reportHistoryDiagnosticPositioningQueries.count, 9)
        for query in reportHistoryDiagnosticPositioningQueries {
            XCTAssertEqual(
                reportHistoryDiagnosticPositioningSource.components(
                    separatedBy: query
                ).count - 1,
                1,
                query
            )
        }
        let reportHistoryDiagnosticPositioningElements = [
            "let reportHistoryVisit = reportHistoryVisits.firstMatch",
            "let historyScreen = historyScreens.firstMatch",
            "let historyHeader = historyHeaders.firstMatch",
            "let viewReportControl = viewReportControls.firstMatch",
            "let historyScrollView = historyScrollViews.firstMatch",
            "let historyNavigationBar = historyNavigationBars.firstMatch",
            "let historyTabBar = historyTabBars.firstMatch",
            "let visitComposite = visitComposites.firstMatch",
        ]
        for binding in reportHistoryDiagnosticPositioningElements {
            XCTAssertEqual(
                reportHistoryDiagnosticPositioningSource.components(
                    separatedBy: binding
                ).count - 1,
                1,
                binding
            )
        }

        let reportHistoryDiagnosticNorthCampusContract =
            "        func hasExactNorthCampusTexts() -> Bool {\n" +
                "            guard northCampusTexts.count == 2 else { return false }\n" +
                "            let first = northCampusTexts.element(boundBy: 0)\n" +
                "            let second = northCampusTexts.element(boundBy: 1)\n" +
                "            let firstFrame = first.frame\n" +
                "            let secondFrame = second.frame\n" +
                "            return first.exists\n" +
                "                && second.exists\n" +
                "                && first.identifier.isEmpty\n" +
                "                && second.identifier.isEmpty\n" +
                #"                && first.label == "North Campus""# + "\n" +
                #"                && second.label == "North Campus""# + "\n" +
                "                && first.elementType == .staticText\n" +
                "                && second.elementType == .staticText\n" +
                "                && !firstFrame.isNull\n" +
                "                && !firstFrame.isEmpty\n" +
                "                && !secondFrame.isNull\n" +
                "                && !secondFrame.isEmpty\n" +
                "                && firstFrame != secondFrame\n" +
                "                && (\n" +
                "                    firstFrame.maxY < secondFrame.minY\n" +
                "                        || secondFrame.maxY < firstFrame.minY\n" +
                "                )\n" +
                "        }"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticNorthCampusContract
            ).count - 1,
            1
        )
        for diagnosticPositioningConstant in [
            "        let contentInset: CGFloat = 16",
            "        let receiverInset: CGFloat = 24",
            "        let minimumGestureDistance: CGFloat = 44",
        ] {
            XCTAssertEqual(
                reportHistoryDiagnosticPositioningSource.components(
                    separatedBy: diagnosticPositioningConstant
                ).count - 1,
                1,
                diagnosticPositioningConstant
            )
        }

        let reportHistoryDiagnosticRouteContracts = [
            "        func hasExactRoute() -> Bool {",
            "            let applicationFrame = app.frame\n" +
                "            let historyScreenFrame = historyScreen.frame",
            "            let historyScreenFrame = historyScreen.frame",
            "            let historyHeaderFrame = historyHeader.frame",
            "            let viewReportFrame = viewReportControl.frame",
            "            let historyScrollFrame = historyScrollView.frame",
            "            let historyNavigationFrame = historyNavigationBar.frame",
            "            let historyTabFrame = historyTabBar.frame",
            "            let reportHistoryVisitFrame = reportHistoryVisit.frame",
            "            let reportHistoryVisitFrame = reportHistoryVisit.frame\n" +
                "            let visitCompositeFrame = visitComposite.frame",
            "                && historyScreens.count == 1",
            "                && historyHeaders.count == 1",
            "                && northCampusTexts.count == 2",
            "                && viewReportControls.count == 1",
            "                && historyScrollViews.count == 1",
            "                && historyNavigationBars.count == 1",
            "                && historyTabBars.count == 1",
            "                && reportHistoryVisits.count == 1",
            "                && visitComposites.count == 1",
            "                && historyScreen.exists",
            #"                && historyScreen.identifier == "s4.4.history.screen""#,
            "                && historyScreen.elementType == .scrollView",
            "                && historyHeader.exists",
            #"                && historyHeader.identifier == "s4.4.history.header""#,
            #"                && historyHeader.label == "Monument Sign""#,
            "                && historyHeader.elementType == .staticText",
            "                && viewReportControl.exists",
            #"                && viewReportControl.identifier == "s4.4.reports.view-report""#,
            #"                && viewReportControl.label == "View report""#,
            "                && viewReportControl.elementType == .button",
            "                && historyScrollView.exists",
            #"                && historyScrollView.identifier == "s4.4.history.screen""#,
            "                && historyScrollView.elementType == .scrollView",
            "                && historyNavigationBar.exists",
            #"                && historyNavigationBar.identifier == "Report history""#,
            "                && historyNavigationBar.elementType == .navigationBar",
            "                && historyTabBar.exists",
            #"                && historyTabBar.label == "Tab Bar""#,
            "                && historyTabBar.elementType == .tabBar",
            "                && reportHistoryVisit.exists",
            #"                && reportHistoryVisit.identifier == "s4.4.reports.visit""#,
            "                && reportHistoryVisit.elementType == .other",
            "                && visitComposite.exists",
            "                && visitComposite.identifier.isEmpty",
            #"                && visitComposite.label.hasPrefix("Visit, ")"#,
            "                && visitComposite.elementType == .staticText",
            "                && !applicationFrame.isNull",
            "                && !applicationFrame.isEmpty",
            "                && !historyScreenFrame.isNull",
            "                && !historyScreenFrame.isEmpty",
            "                && !historyHeaderFrame.isNull",
            "                && !historyHeaderFrame.isEmpty",
            "                && !viewReportFrame.isNull",
            "                && !viewReportFrame.isEmpty",
            "                && !historyScrollFrame.isNull",
            "                && !historyScrollFrame.isEmpty",
            "                && !historyNavigationFrame.isNull",
            "                && !historyNavigationFrame.isEmpty",
            "                && !historyTabFrame.isNull",
            "                && !historyTabFrame.isEmpty",
            "                && !reportHistoryVisitFrame.isNull",
            "                && !reportHistoryVisitFrame.isEmpty",
            "                && !visitCompositeFrame.isNull",
            "                && !visitCompositeFrame.isEmpty",
        ]
        for contract in reportHistoryDiagnosticRouteContracts {
            XCTAssertEqual(
                reportHistoryDiagnosticPositioningSource.components(
                    separatedBy: contract
                ).count - 1,
                1,
                contract
            )
        }

        let reportHistoryDiagnosticLiveGeometry =
            "            let applicationFrame = app.frame\n" +
                "            let scrollFrame = historyScrollView.frame\n" +
                "            let navigationFrame = historyNavigationBar.frame\n" +
                "            let tabBarFrame = historyTabBar.frame\n" +
                "            let liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)\n" +
                "            let liveBottom = min(\n" +
                "                liveScrollFrame.maxY,\n" +
                "                min(applicationFrame.maxY, tabBarFrame.minY)\n" +
                "            )\n" +
                "            let safeTop = liveTop + contentInset\n" +
                "            let safeBottom = liveBottom - contentInset\n" +
                "            let receiverTop = liveTop + receiverInset\n" +
                "            let receiverBottom = liveBottom - receiverInset\n" +
                "            let headerFrame = historyHeader.frame\n" +
                "            let visitCompositeFrame = visitComposite.frame"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticLiveGeometry
            ).count - 1,
            1
        )
        let reportHistoryDiagnosticPositiveInterval =
            "            let minimumShift = max(\n" +
                "                safeTop - headerFrame.minY,\n" +
                "                applicationFrame.maxY - visitCompositeFrame.minY\n" +
                "            )\n" +
                "            let maximumShift = safeBottom - headerFrame.maxY\n" +
                "            let receiverCapacity = receiverBottom - receiverTop\n" +
                "            guard minimumShift <= maximumShift,\n" +
                "                  minimumShift > 0,\n" +
                "                  receiverCapacity >= minimumGestureDistance else {\n" +
                #"                XCTFail("Report-history AX-text positioned diagnostic has no positive interval.")"# + "\n" +
                "                return false\n" +
                "            }\n" +
                "            let recognizedMinimum = max(\n" +
                "                minimumShift,\n" +
                "                minimumGestureDistance\n" +
                "            )\n" +
                "            let recognizedMaximum = min(\n" +
                "                maximumShift,\n" +
                "                receiverCapacity\n" +
                "            )\n" +
                "            guard recognizedMinimum <= recognizedMaximum,\n" +
                "                  recognizedMinimum > 0 else {\n" +
                #"                XCTFail("Report-history AX-text positive shift is not recognizable.")"# + "\n" +
                "                return false\n" +
                "            }\n" +
                "            let dragDistance = recognizedMinimum"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticPositiveInterval
            ).count - 1,
            1
        )

        let reportHistoryDiagnosticDirectGesture =
            "            let scrollOrigin = historyScrollView.coordinate(\n" +
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
                "            let headerMinYBeforeDrag = headerFrame.minY\n" +
                "            let visitMinYBeforeDrag = visitCompositeFrame.minY\n" +
                "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticDirectGesture
            ).count - 1,
            1
        )
        let reportHistoryDiagnosticObservedShift =
            "            let observedHeaderShift = historyHeader.frame.minY - headerMinYBeforeDrag\n" +
                "            let observedVisitShift = visitComposite.frame.minY - visitMinYBeforeDrag\n" +
                "            guard observedHeaderShift > 0,\n" +
                "                  observedVisitShift > 0,\n" +
                "                  observedHeaderShift * dragDistance > 0,\n" +
                "                  observedVisitShift * dragDistance > 0 else {\n" +
                #"                XCTFail("Report-history AX-text positioned diagnostic drag was not recognized.")"# + "\n" +
                "                return false\n" +
                "            }"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticObservedShift
            ).count - 1,
            1
        )
        let reportHistoryDiagnosticFinalGeometry =
            "        let finalApplicationFrame = app.frame\n" +
                "        let finalScrollFrame = historyScrollView.frame.intersection(\n" +
                "            finalApplicationFrame\n" +
                "        )\n" +
                "        let finalNavigationFrame = historyNavigationBar.frame\n" +
                "        let finalTabBarFrame = historyTabBar.frame\n" +
                "        let finalSafeTop = max(\n" +
                "            finalScrollFrame.minY,\n" +
                "            finalNavigationFrame.maxY\n" +
                "        ) + contentInset\n" +
                "        let finalSafeBottom = min(\n" +
                "            finalScrollFrame.maxY,\n" +
                "            min(finalApplicationFrame.maxY, finalTabBarFrame.minY)\n" +
                "        ) - contentInset\n" +
                "        let finalHeaderFrame = historyHeader.frame\n" +
                "        let finalVisitCompositeFrame = visitComposite.frame"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticFinalGeometry
            ).count - 1,
            1
        )
        let reportHistoryDiagnosticFinalContainment =
            "              finalSafeBottom > finalSafeTop,\n" +
                "              finalHeaderFrame.minY >= finalSafeTop,\n" +
                "              finalHeaderFrame.maxY <= finalSafeBottom,\n" +
                "              historyHeader.isHittable,\n" +
                "              finalVisitCompositeFrame.minY >= finalApplicationFrame.maxY,\n" +
                "              !visitComposite.isHittable else {\n" +
                #"            XCTFail("Report-history AX-text positioned diagnostic final geometry is unsafe.")"# + "\n" +
                "            return false\n" +
                "        }\n" +
                "        return true"
        XCTAssertEqual(
            reportHistoryDiagnosticPositioningSource.components(
                separatedBy: reportHistoryDiagnosticFinalContainment
            ).count - 1,
            1
        )

        for (reportHistoryDiagnosticCardinalityLock, count) in [
            ("hasExactRoute() else", 3),
            ("historyScreens.count == 1", 1),
            ("historyHeaders.count == 1", 1),
            ("northCampusTexts.count == 2", 2),
            ("viewReportControls.count == 1", 1),
            ("historyScrollViews.count == 1", 1),
            ("historyNavigationBars.count == 1", 1),
            ("historyTabBars.count == 1", 1),
            ("reportHistoryVisits.count == 1", 1),
            ("visitComposites.count == 1", 1),
            ("historyScreen.exists", 1),
            ("historyHeader.exists", 1),
            ("viewReportControl.exists", 1),
            ("historyScrollView.exists", 1),
            ("historyNavigationBar.exists", 1),
            ("historyTabBar.exists", 1),
            ("reportHistoryVisit.exists", 1),
            ("visitComposite.exists", 1),
            ("for _ in 0..<4", 1),
            ("historyScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
            ("return true", 2),
        ] {
            XCTAssertEqual(
                reportHistoryDiagnosticPositioningSource.components(
                    separatedBy: reportHistoryDiagnosticCardinalityLock
                ).count - 1,
                count,
                reportHistoryDiagnosticCardinalityLock
            )
        }
        for prohibitedReportHistoryDiagnosticPositioningForm in [
            "app.coordinate(",
            "app.swipe",
            "historyScrollView.swipe",
            "scroll(",
            "tap(",
            "waitForExistence",
            "Thread.sleep",
            "sleep(",
            "CGRect(",
            "epsilon",
            "tolerance",
            "performAccessibilityAudit(",
            "ContrastAuditExceptionSignature",
            "captureBaseline(",
            "attachCandidate(",
            "printJSONLine(",
            "automationContrastExceptions",
            "automationAXTreeDigests",
            "eligibleExceptions",
            "receipt",
            "120",
            "402",
            "874",
            "2026-08-22",
        ] {
            XCTAssertFalse(
                reportHistoryDiagnosticPositioningSource.contains(
                    prohibitedReportHistoryDiagnosticPositioningForm
                ),
                prohibitedReportHistoryDiagnosticPositioningForm
            )
        }

        let removedReportHistoryDiagnosticFragments = [
            #"            if shard.shardID == "s10.4.current.ax-text","# + "\n" +
                #"               stateID == "state.report-history.ready" {"#,
            "S10_4_REPORT_HISTORY_CONTEXT_DIAGNOSTIC",
            "S10_4_REPORT_HISTORY_AUDIT_DIAGNOSTIC",
            "S10_4_REPORT_HISTORY_AUDIT_COUNT_DIAGNOSTIC",
            "S10_4_REPORT_HISTORY_POSITIONING_DIAGNOSTIC",
            "S10.4 s10.4.current.ax-text Report-history contrast diagnostic",
            "let reportHistoryScreens = app.descendants(matching: .any).matching(",
            "let reportHistoryHeaders = app.staticTexts.matching(",
            "diagnosticElementObject",
            "diagnosticQueryObject",
            "historyContextAttachment",
            "lowerNorthCampusElement",
            "lowerNorthCampusFrame",
            "lowerNorthCampusMinYBeforeDrag",
            "observedLowerNorthCampusShift",
            "finalLowerNorthCampus",
            "applicationFrameAfterDrag",
            "applicationFrame.maxY - lowerNorthCampusFrame.minY",
            "lowerNorthCampusFrame.minY >= applicationFrame.maxY",
            "!lowerNorthCampusElement.isHittable",
            "!finalLowerNorthCampus.isHittable",
        ]
        for fragment in removedReportHistoryDiagnosticFragments {
            XCTAssertEqual(
                uiSource.components(separatedBy: fragment).count - 1,
                0,
                fragment
            )
            XCTAssertEqual(
                workflowSource.components(separatedBy: fragment).count - 1,
                0,
                fragment
            )
        }
        let removedReportHistoryDiagnosticAttachmentAndCallbackFragments = [
            "Report-history route context",
            "audit issue \\(observedIssueCount)",
            "S10.4 AX-text Report-history contrast diagnostic completed nonaccepting",
        ]
        for fragment in removedReportHistoryDiagnosticAttachmentAndCallbackFragments {
            XCTAssertEqual(
                uiSource.components(separatedBy: fragment).count - 1,
                0,
                fragment
            )
        }
        let reportHistoryResidualDiagnosticMutation =
            uiSource + "\nS10_4_REPORT_HISTORY_AUDIT_COUNT_DIAGNOSTIC"
        XCTAssertNotEqual(
            reportHistoryResidualDiagnosticMutation.components(
                separatedBy: "S10_4_REPORT_HISTORY_AUDIT_COUNT_DIAGNOSTIC"
            ).count - 1,
            0
        )

        let restoredEligibleExceptionsBinding =
            "            let eligibleExceptions = " +
                "Self.contrastAuditExceptionSignatures.filter {"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: restoredEligibleExceptionsBinding
            ).count - 1,
            1
        )
        let restoredBareContrastAudit =
            "            } else {\n" +
                "                try app.performAccessibilityAudit(for: .contrast)\n" +
                "            }\n" +
                "            matchedExceptions.sort { $0.issueID < $1.issueID }"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: restoredBareContrastAudit
            ).count - 1,
            1
        )

        let restoredCaptureBaselineStart =
            "    @MainActor\n" +
                "    private func captureBaseline("
        let restoredCaptureBaselineEnd =
            "\n\n    private func isActive("
        guard let restoredCaptureBaselineStartRange = uiSource.range(
            of: restoredCaptureBaselineStart
        ), let restoredCaptureBaselineEndRange = uiSource.range(
            of: restoredCaptureBaselineEnd,
            range: restoredCaptureBaselineStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the restored bounded captureBaseline source")
            return
        }
        let restoredCaptureBaselineSource = String(
            uiSource[
                restoredCaptureBaselineStartRange.lowerBound..<restoredCaptureBaselineEndRange.lowerBound
            ]
        )

        for removedReduceMotionWorkSavingDiagnosticForm in [
            "diagnoseReduceMotionWorkSavingContrast",
            "S10_4_REDUCE_MOTION_WORK_SAVING_CONTEXT_DIAGNOSTIC",
            "S10_4_REDUCE_MOTION_WORK_SAVING_ISSUE_DIAGNOSTIC",
            "S10_4_REDUCE_MOTION_WORK_SAVING_COUNT_DIAGNOSTIC",
            "S10.4 s10.4.current.reduce-motion Record-work saving contrast diagnostic",
            "Record-work saving contrast diagnostic completed nonaccepting",
            #"if shard.shardID == "s10.4.current.reduce-motion","# + "\n" +
                #"               stateID == "state.work.saving""#,
            "let workScreenCount = workScreens.count",
            "let savingStatusCount = savingStatuses.count",
            "let noteHeadingCount = noteHeadings.count",
            "let helperTextCount = helperTexts.count",
            #""callbackCount": observedIssueCount"#,
        ] {
            XCTAssertFalse(
                uiSource.contains(removedReduceMotionWorkSavingDiagnosticForm),
                removedReduceMotionWorkSavingDiagnosticForm
            )
            XCTAssertFalse(
                restoredCaptureBaselineSource.contains(
                    removedReduceMotionWorkSavingDiagnosticForm
                ),
                removedReduceMotionWorkSavingDiagnosticForm
            )
        }

        let contrastAuthorityStart =
            "    private static let contrastAuditExceptionSignatures = ["
        let contrastAuthorityEnd =
            "\n\n    private static let commonTaskStateIDs:"
        guard let contrastAuthorityStartRange = uiSource.range(
            of: contrastAuthorityStart
        ), let contrastAuthorityEndRange = uiSource.range(
            of: contrastAuthorityEnd,
            range: contrastAuthorityStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded contrast authority source")
            return
        }
        let contrastAuthoritySource = String(
            uiSource[
                contrastAuthorityStartRange.lowerBound..<contrastAuthorityEndRange.lowerBound
            ]
        )
        XCTAssertFalse(
            contrastAuthoritySource.contains(
                #"stateID: "state.work.saving""#
            )
        )
        XCTAssertEqual(
            contrastAuthoritySource.components(
                separatedBy: "ContrastAuditExceptionSignature("
            ).count - 1,
            12
        )
        for prohibitedReduceMotionSavingTaskExpansion in [
            #"case ("s10.4.current.reduce-motion", "work_and_recheck")"#,
            #"case ("s10.4.current.reduce-motion", "force_quit_draft_resume")"#,
        ] {
            XCTAssertFalse(
                uiSource.contains(prohibitedReduceMotionSavingTaskExpansion),
                prohibitedReduceMotionSavingTaskExpansion
            )
            XCTAssertFalse(
                workflowSource.contains(prohibitedReduceMotionSavingTaskExpansion),
                prohibitedReduceMotionSavingTaskExpansion
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
        ] {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: diagnosticsResidualForm
                ).count - 1,
                expectedCount,
                diagnosticsResidualForm
            )
        }
        let diagnosticsTwoAttemptSetup =
            "        let topClearance: CGFloat = 12\n" +
                "        let bottomClearance: CGFloat = 16\n" +
                "        let minimumGestureDistance: CGFloat = 44\n" +
                "        let dragInset: CGFloat = 24\n" +
                "        var measuredUndertravel: CGFloat = 0\n" +
                "        var correctionDirection: CGFloat?\n" +
                "        var previousResidualMagnitude: CGFloat?"
        XCTAssertEqual(
            diagnosticsPositioningSource.components(
                separatedBy: diagnosticsTwoAttemptSetup
            ).count - 1,
            1
        )
        let diagnosticsTwoAttemptLoop =
            "        for _ in 0..<2 {\n" +
                "            let minimumShift = navigationBar.frame.maxY\n" +
                "                + topClearance\n" +
                "                - diagnosticsAuthority.frame.minY\n" +
                "            let maximumShift = min(\n" +
                "                navigationBar.frame.maxY - diagnosticsHeading.frame.maxY,\n" +
                "                signsTab.frame.minY\n" +
                "                    - bottomClearance\n" +
                "                    - diagnosticsExport.frame.maxY\n" +
                "            )\n" +
                "            guard minimumShift <= maximumShift else {\n" +
                "                XCTFail(\"Diagnostics positioning interval is impossible.\")\n" +
                "                return\n" +
                "            }\n" +
                "            if minimumShift <= 0, maximumShift >= 0 {\n" +
                "                break\n" +
                "            }\n" +
                "            let targetDistance: CGFloat\n" +
                "            if maximumShift < 0 {\n" +
                "                targetDistance = maximumShift\n" +
                "            } else if minimumShift > 0 {\n" +
                "                targetDistance = minimumShift\n" +
                "            } else {\n" +
                "                XCTFail(\"Diagnostics positioning interval has no signed correction.\")\n" +
                "                return\n" +
                "            }\n" +
                "            let direction: CGFloat = targetDistance > 0 ? 1 : -1\n" +
                "            if let correctionDirection {\n" +
                "                guard correctionDirection == direction else {\n" +
                "                    XCTFail(\"Diagnostics positioning changed correction direction.\")\n" +
                "                    return\n" +
                "                }\n" +
                "            } else {\n" +
                "                correctionDirection = direction\n" +
                "            }\n" +
                "            let residualMagnitude = abs(targetDistance)\n" +
                "            if let previousResidualMagnitude {\n" +
                "                guard residualMagnitude < previousResidualMagnitude else {\n" +
                "                    XCTFail(\"Diagnostics positioning residual did not decrease.\")\n" +
                "                    return\n" +
                "                }\n" +
                "            }\n" +
                "            previousResidualMagnitude = residualMagnitude\n" +
                "            let requestedDistance = targetDistance\n" +
                "                + direction * measuredUndertravel\n" +
                "            guard abs(requestedDistance) >= minimumGestureDistance else {\n" +
                "                XCTFail(\"Diagnostics positioning gesture is not recognizable.\")\n" +
                "                return\n" +
                "            }\n" +
                "            let dragStart = diagnosticsScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45)\n" +
                "            )\n" +
                "            let startPoint = dragStart.screenPoint\n" +
                "            let availableDistance = direction < 0\n" +
                "                ? startPoint.y - (diagnosticsScrollView.frame.minY + dragInset)\n" +
                "                : diagnosticsScrollView.frame.maxY - dragInset - startPoint.y\n" +
                "            guard availableDistance >= abs(requestedDistance) else {\n" +
                "                XCTFail(\"Diagnostics positioning request exceeds receiver capacity.\")\n" +
                "                return\n" +
                "            }\n" +
                "            let dragEnd = dragStart.withOffset(\n" +
                "                CGVector(dx: 0, dy: requestedDistance)\n" +
                "            )\n" +
                "            let authorityBeforeDrag = diagnosticsAuthority.frame.minY\n" +
                "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )\n" +
                "            let actualDistance = diagnosticsAuthority.frame.minY\n" +
                "                - authorityBeforeDrag\n" +
                "            guard actualDistance * direction > 0 else {\n" +
                "                XCTFail(\"Diagnostics positioning gesture was not recognized.\")\n" +
                "                return\n" +
                "            }\n" +
                "            measuredUndertravel = max(\n" +
                "                0,\n" +
                "                abs(requestedDistance) - abs(actualDistance)\n" +
                "            )\n" +
                "        }"
        XCTAssertEqual(
            diagnosticsPositioningSource.components(
                separatedBy: diagnosticsTwoAttemptLoop
            ).count - 1,
            1
        )
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
        for (fragment, expectedCount) in [
            ("for _ in 0..<2 {", 1),
            ("diagnosticsScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
            ("measuredUndertravel = max(", 1),
            ("XCTFail(", 10),
            ("return", 10),
        ] {
            XCTAssertEqual(
                diagnosticsPositioningSource.components(
                    separatedBy: fragment
                ).count - 1,
                expectedCount,
                fragment
            )
        }
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
        for removedPositioningForm in [
            "let dragDistance: CGFloat",
            "dragDistance = 0",
            "dragDistance = maximumShift",
            "dragDistance = minimumShift",
            "if dragDistance != 0 {",
            "guard maximumShift <= -minimumGestureDistance else {",
            "guard minimumShift >= minimumGestureDistance else {",
            "for _ in 0..<4 {",
            "for _ in 0..<6 {",
            "upwardUndertravel",
            "downwardUndertravel",
            "observedUndertravel",
            "stagingCount",
            "stagedFinalDirection",
            "requiredFinalDirection",
            "stagingDistance",
            "isStaging",
            "upwardCapacity",
            "downwardCapacity",
            "maximumGestureDistance",
            "recognizedMinimum",
            "recognizedMaximum",
            "residual strategy",
            "2 * minimumGestureDistance",
            "Diagnostics upward correction is not recognizable.",
            "Diagnostics downward correction is not recognizable.",
            "Diagnostics has no recognized feasible upward shift.",
            "Diagnostics has no recognized feasible downward shift.",
            "Diagnostics has no bounded upward residual strategy.",
            "Diagnostics has no bounded downward residual strategy.",
            "Diagnostics upward staging is not recognizable.",
            "Diagnostics downward staging is not recognizable.",
            "dragDistance = recognizedMaximum",
            "dragDistance = recognizedMinimum",
            "diagnosticsScrollView.frame.height",
            "Thread.sleep",
            "epsilon",
            "tolerance",
            "app.coordinate(",
            "app.swipeUp()",
            "app.swipeDown()",
        ] {
            XCTAssertFalse(
                diagnosticsPositioningSource.contains(removedPositioningForm),
                removedPositioningForm
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

        let restoredDiagnosticsControllerEntry =
            "        guard diagnosticsScrollView.waitForExistence(timeout: 10) else {\n" +
                "            XCTFail(\"Diagnostics route ScrollView is missing.\")\n" +
                "            return\n" +
                "        }\n" +
                "        let topClearance: CGFloat = 12"
        XCTAssertEqual(
            diagnosticsPositioningSource.components(
                separatedBy: restoredDiagnosticsControllerEntry
            ).count - 1,
            1
        )
        let removedDifferentiateDiagnosticsTelemetryForms = [
            "        if automationShard?.shardID ==\n" +
                "            \"s10.4.current.differentiate-without-color\" {\n" +
                "            try diagnoseDifferentiateWithoutColorDiagnosticsPositioning(in: app)\n" +
                "        }",
            "diagnoseDifferentiateWithoutColorDiagnosticsPositioning",
            "S10_4_DIAGNOSTICS_POSITIONING_TELEMETRY",
            "S10.4 differentiate-without-color Diagnostics positioning telemetry",
            "Diagnostics positioning telemetry pre app",
            "Diagnostics positioning telemetry pre accessibility tree",
            "Diagnostics positioning telemetry terminal app",
            "Diagnostics positioning telemetry terminal accessibility tree",
            "diagnosticsScreenQuery",
            "diagnosticsHeadingQuery",
            "diagnosticsAuthorityQuery",
            "diagnosticsExportQuery",
            "signsTabQuery",
            "func elementObject(_ value: XCUIElement)",
            "func routeObject()",
            "S10.4 differentiate-without-color Diagnostics positioning telemetry completed nonaccepting",
        ]
        for removedTelemetry in removedDifferentiateDiagnosticsTelemetryForms {
            XCTAssertEqual(
                uiSource.components(separatedBy: removedTelemetry).count - 1,
                0,
                removedTelemetry
            )
        }

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
        let storeKitCoordinatorPath =
            "FieldEvidenceApp/Infrastructure/Commerce/StoreKitPurchaseCoordinator.swift"
        try assertFile(
            storeKitCoordinatorPath,
            byteCount: 11_262,
            sha256: "6C7492636F9DC17D0ED23EC2CD3BE516E7F32ECD8B3F142255AFBC0F1624D151"
        )
        let storeKitCoordinatorSource = try text(storeKitCoordinatorPath)
        let storeKitProcessorPath =
            "FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift"
        try assertFile(
            storeKitProcessorPath,
            byteCount: 20_511,
            sha256: "C7CD2DB4B51310DCD5670519453B6AE9DF95E125B1AA4A8E001DCEC539C47A7C"
        )
        let storeKitProcessorSource = try text(storeKitProcessorPath)
        XCTAssertEqual(
            storeKitProcessorSource.components(
                separatedBy: "private static let subscriptionStatusMaximumReads = 20"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            storeKitProcessorSource.components(
                separatedBy:
                    "private static let subscriptionStatusReadDelayNanoseconds: UInt64 =\n" +
                        "        250_000_000"
            ).count - 1,
            1
        )
        let subscriptionStatusResolverStart =
            "    private static func resolvedSubscriptionStatus(\n"
        let subscriptionStatusResolverEnd =
            "\n\n    static func event(\n" +
                "        from status: Product.SubscriptionInfo.Status"
        guard let subscriptionStatusResolverStartRange = storeKitProcessorSource.range(
            of: subscriptionStatusResolverStart
        ), let subscriptionStatusResolverEndRange = storeKitProcessorSource.range(
            of: subscriptionStatusResolverEnd,
            range: subscriptionStatusResolverStartRange.upperBound..<storeKitProcessorSource.endIndex
        ) else {
            XCTFail("Missing the bounded same-transaction subscription-status resolver")
            return
        }
        let subscriptionStatusResolverSource = String(
            storeKitProcessorSource[
                subscriptionStatusResolverStartRange.lowerBound..<subscriptionStatusResolverEndRange.lowerBound
            ]
        )
        for resolverLock in [
            "private static func resolvedSubscriptionStatus(",
            "for transaction: Transaction",
            ") async -> Product.SubscriptionInfo.Status?",
            "for _ in 1..<subscriptionStatusMaximumReads",
            "try await Task<Never, Never>.sleep(",
            "nanoseconds: subscriptionStatusReadDelayNanoseconds",
            "} catch {",
        ] {
            XCTAssertEqual(
                subscriptionStatusResolverSource.components(
                    separatedBy: resolverLock
                ).count - 1,
                1,
                resolverLock
            )
        }
        XCTAssertEqual(
            storeKitProcessorSource.components(
                separatedBy: "private static func resolvedSubscriptionStatus("
            ).count - 1,
            1
        )
        XCTAssertEqual(
            subscriptionStatusResolverSource.components(
                separatedBy: "await transaction.subscriptionStatus"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            subscriptionStatusResolverSource.components(
                separatedBy: "guard !Task<Never, Never>.isCancelled else { return nil }"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            subscriptionStatusResolverSource.components(
                separatedBy: "return status"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            subscriptionStatusResolverSource.components(
                separatedBy: "return nil"
            ).count - 1,
            4
        )
        for prohibited in ["while ", "repeat {", "Task.detached", "withTaskGroup"] {
            XCTAssertFalse(subscriptionStatusResolverSource.contains(prohibited), prohibited)
        }
        var resolverCursor = subscriptionStatusResolverSource.startIndex
        for orderedToken in [
            "Task<Never, Never>.isCancelled",
            "await transaction.subscriptionStatus",
            "return status",
            "for _ in 1..<subscriptionStatusMaximumReads",
            "Task<Never, Never>.sleep(",
            "} catch {",
            "Task<Never, Never>.isCancelled",
            "await transaction.subscriptionStatus",
            "return status",
            "return nil",
        ] {
            guard let orderedRange = subscriptionStatusResolverSource.range(
                of: orderedToken,
                range: resolverCursor..<subscriptionStatusResolverSource.endIndex
            ) else {
                XCTFail("StoreKit status resolver ordering lost \(orderedToken)")
                return
            }
            resolverCursor = orderedRange.upperBound
        }
        let coordinatorCompletionStart =
            "    func handleStoreKitCompletion("
        let coordinatorCompletionEnd =
            "\n\n    func complete(_ result: PaywallPurchaseAttemptV1) async {"
        guard let coordinatorCompletionStartRange = storeKitCoordinatorSource.range(
            of: coordinatorCompletionStart
        ), let coordinatorCompletionEndRange = storeKitCoordinatorSource.range(
            of: coordinatorCompletionEnd,
            range: coordinatorCompletionStartRange.upperBound..<storeKitCoordinatorSource.endIndex
        ) else {
            XCTFail("Missing the bounded StoreKit completion source slice")
            return
        }
        let coordinatorCompletionSource = String(
            storeKitCoordinatorSource[
                coordinatorCompletionStartRange.lowerBound..<coordinatorCompletionEndRange.lowerBound
            ]
        )
        var coordinatorCompletionCursor = coordinatorCompletionSource.startIndex
        for orderedToken in [
            "guard purchaseReservation?.productID == productID else",
            "await complete(.unverified)",
            "switch result",
            "case .failure:",
            "case let .success(purchaseResult):",
            "case let .success(verification):",
            "case .unverified:",
            "case let .verified(transaction):",
            "let processor = verifiedTransactionProcessor",
            "await complete(.verified {",
            "await processor(transaction)",
        ] {
            guard let orderedRange = coordinatorCompletionSource.range(
                of: orderedToken,
                range: coordinatorCompletionCursor..<coordinatorCompletionSource.endIndex
            ) else {
                XCTFail("StoreKit completion ordering lost \(orderedToken)")
                return
            }
            coordinatorCompletionCursor = orderedRange.upperBound
        }
        let verifiedEventStart =
            "    static func verifiedEvent(\n" +
                "        from transaction: Transaction,\n" +
                "        shouldFinish: Bool\n" +
                "    ) async -> VerifiedEntitlementProcessorEventV1? {"
        let verifiedEventEnd =
            "\n\n    static func event(\n" +
                "        from status: Product.SubscriptionInfo.Status"
        guard let verifiedEventStartRange = storeKitProcessorSource.range(
            of: verifiedEventStart
        ), let verifiedEventEndRange = storeKitProcessorSource.range(
            of: verifiedEventEnd,
            range: verifiedEventStartRange.upperBound..<storeKitProcessorSource.endIndex
        ) else {
            XCTFail("Missing the bounded verified StoreKit transaction adapter")
            return
        }
        let verifiedEventSource = String(
            storeKitProcessorSource[
                verifiedEventStartRange.lowerBound..<verifiedEventEndRange.lowerBound
            ]
        )
        var verifiedEventCursor = verifiedEventSource.startIndex
        for orderedToken in [
            "transaction.productID == EntitlementReducerV1.productID",
            "transaction.productType == .autoRenewable",
            "transaction.ownershipType == .purchased",
            "await resolvedSubscriptionStatus(for: transaction)",
            "let fact = fact(from: status)",
            "return nil",
            "finish = { await transaction.finish() }",
            "fact: fact",
        ] {
            guard let orderedRange = verifiedEventSource.range(
                of: orderedToken,
                range: verifiedEventCursor..<verifiedEventSource.endIndex
            ) else {
                XCTFail("Verified StoreKit adapter ordering lost \(orderedToken)")
                return
            }
            verifiedEventCursor = orderedRange.upperBound
        }
        XCTAssertEqual(
            storeKitProcessorSource.components(
                separatedBy: "resolvedSubscriptionStatus(for: transaction)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            verifiedEventSource.components(separatedBy: "fact(from: status)").count - 1,
            1
        )
        for preservedBaselineInventoryQuery in [
            "Transaction.currentEntitlements",
            "Transaction.unfinished",
        ] {
            XCTAssertEqual(
                storeKitProcessorSource.components(
                    separatedBy: preservedBaselineInventoryQuery
                ).count - 1,
                1,
                preservedBaselineInventoryQuery
            )
        }
        for globallyProhibitedStoreKitFallback in [
            "Product.products",
            "Transaction.all",
            "allTransactions",
            "currentEntitlement(for:",
        ] {
            XCTAssertEqual(
                storeKitProcessorSource.components(
                    separatedBy: globallyProhibitedStoreKitFallback
                ).count - 1,
                0,
                globallyProhibitedStoreKitFallback
            )
        }
        XCTAssertEqual(
            storeKitProcessorSource.components(
                separatedBy: "transaction.finish()"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            storeKitProcessorSource.components(
                separatedBy: "applyVerified([event])"
            ).count - 1,
            1
        )
        for prohibited in [
            "Product.products",
            "subscription.status",
            "currentEntitlement",
            "currentEntitlements",
            "Transaction.all",
            "allTransactions",
            "Transaction.unfinished",
            "EntitlementStore",
            "EntitlementReducerV1.reduce",
            "VerifiedSubscriptionStateV1.active",
            "state: .active",
        ] {
            XCTAssertFalse(verifiedEventSource.contains(prohibited), prohibited)
        }
        let verifiedFactStart =
            "    static func fact(\n" +
                "        from status: Product.SubscriptionInfo.Status\n" +
                "    ) -> VerifiedEntitlementFactV1? {"
        guard let verifiedFactStartRange = storeKitProcessorSource.range(
            of: verifiedFactStart
        ) else {
            XCTFail("Missing the unchanged verified subscription fact adapter")
            return
        }
        let verifiedFactSource = String(
            storeKitProcessorSource[verifiedFactStartRange.lowerBound...]
        )
        var verifiedFactCursor = verifiedFactSource.startIndex
        for orderedToken in [
            "case let .verified(transaction) = status.transaction",
            "case let .verified(renewal) = status.renewalInfo",
            "transaction.productID == EntitlementReducerV1.productID",
            "renewal.currentProductID == EntitlementReducerV1.productID",
            "transaction.productType == .autoRenewable",
            "transaction.ownershipType == .purchased",
            "status.state == .subscribed",
            "status.state == .inGracePeriod",
            "status.state == .inBillingRetryPeriod",
            "status.state == .expired",
            "status.state == .revoked",
            "let date = transaction.revocationDate",
            "let fact = VerifiedEntitlementFactV1(",
            "StoreKitPaidGraceAuthorityV1.accepts(fact) ? fact : nil",
        ] {
            guard let orderedRange = verifiedFactSource.range(
                of: orderedToken,
                range: verifiedFactCursor..<verifiedFactSource.endIndex
            ) else {
                XCTFail("Verified subscription fact ordering lost \(orderedToken)")
                return
            }
            verifiedFactCursor = orderedRange.upperBound
        }
        for prohibited in [
            "resolvedSubscriptionStatus",
            "transaction.subscriptionStatus",
            "Task<Never, Never>.sleep",
        ] {
            XCTAssertFalse(verifiedFactSource.contains(prohibited), prohibited)
        }
        let applyVerifiedStart =
            "    func applyVerified(\n" +
                "        _ events: [VerifiedEntitlementProcessorEventV1]\n" +
                "    ) async -> Bool {"
        let applyVerifiedEnd =
            "\n\n    func finish(_ events: [VerifiedEntitlementProcessorEventV1]) async {"
        guard let applyVerifiedStartRange = storeKitProcessorSource.range(
            of: applyVerifiedStart
        ), let applyVerifiedEndRange = storeKitProcessorSource.range(
            of: applyVerifiedEnd,
            range: applyVerifiedStartRange.upperBound..<storeKitProcessorSource.endIndex
        ) else {
            XCTFail("Missing the durable verified-entitlement application slice")
            return
        }
        let applyVerifiedSource = String(
            storeKitProcessorSource[
                applyVerifiedStartRange.lowerBound..<applyVerifiedEndRange.lowerBound
            ]
        )
        var durableApplyCursor = applyVerifiedSource.startIndex
        for orderedToken in [
            "events.allSatisfy({ StoreKitPaidGraceAuthorityV1.accepts($0.fact) })",
            "let durable = try store.persist(replacement)",
            "guard durable == replacement else { return false }",
            "state = reduction.state",
            "await finish(finishable)",
        ] {
            guard let orderedRange = applyVerifiedSource.range(
                of: orderedToken,
                range: durableApplyCursor..<applyVerifiedSource.endIndex
            ) else {
                XCTFail("Durable entitlement ordering lost \(orderedToken)")
                return
            }
            durableApplyCursor = orderedRange.upperBound
        }
        let removedStoreKitDiagnosticFragments = [
            "S10_4StoreKitPurchaseDiagnostic",
            "S10_4StoreKitVerificationErrorV1",
            "S10_4StoreKitProcessorFailureV1",
            "purchaseDiagnosticVerifiedEvent",
            "purchaseDiagnosticFact",
            "firstPurchaseDiagnosticFailure",
            "s10_4StoreKitPurchaseDiagnosticJSON",
            "publishS10_4StoreKitPurchaseDiagnostic",
            "verificationErrorCase",
            "missingPurchaseReservation",
            "completionProductMismatch",
            "purchaseVerificationUnverified",
            "transactionProductIDMismatch",
            "transactionProductTypeMismatch",
            "transactionOwnershipMismatch",
            "subscriptionStatusUnavailable",
            "statusTransactionUnverified",
            "statusRenewalInfoUnverified",
            "statusTransactionProductIDMismatch",
            "statusRenewalProductIDMismatch",
            "statusTransactionProductTypeMismatch",
            "statusTransactionOwnershipMismatch",
            "statusRevokedWithoutRevocationDate",
            "statusUnsupportedState",
            "paidGraceAuthorityRejected",
            "processorUnverifiedWithoutReason",
            "invalidCertificateChain",
            "invalidDeviceVerification",
            "invalidEncoding",
            "invalidSignature",
            "missingRequiredProperties",
            "revokedCertificate",
            "case let .unverified(_, error):",
        ]
        for removedDiagnostic in removedStoreKitDiagnosticFragments {
            XCTAssertEqual(
                (storeKitCoordinatorSource + storeKitProcessorSource)
                    .components(separatedBy: removedDiagnostic).count - 1,
                0,
                removedDiagnostic
            )
        }
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
            #"                guard let retainedSession = storeKitSession else {"#,
            #"                    XCTFail("The retained StoreKit test session is required")"#,
            "                    return usedSettingsRetry",
            "                app.terminate()",
            "                retainedSession.resetToDefaultState()",
            "                retainedSession.clearTransactions()",
            "                retainedSession.disableDialogs = true",
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
        let retainedStoreKitResetAndRelaunch =
            #"                guard let retainedSession = storeKitSession else {"# + "\n" +
                #"                    XCTFail("The retained StoreKit test session is required")"# + "\n" +
                "                    return usedSettingsRetry\n" +
                "                }\n" +
                "                app.terminate()\n" +
                "                retainedSession.resetToDefaultState()\n" +
                "                retainedSession.clearTransactions()\n" +
                "                retainedSession.disableDialogs = true\n" +
                "                app.launch()\n" +
                #"                XCTAssertTrue(element("s2.sign-detail.screen", in: app)"# + "\n" +
                "                    .waitForExistence(timeout: 30))"
        XCTAssertEqual(
            unverifiedRetrySource.components(
                separatedBy: retainedStoreKitResetAndRelaunch
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
        let retryReadyTapAndFinalVerifiedWait =
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
                #"                purchaseState = element("s7.2.paywall.purchase-state", in: app)"# + "\n" +
                "            }\n" +
                "        }\n" +
                finalVerifiedPurchaseWait
        XCTAssertEqual(
            purchaseRecoverySource.components(
                separatedBy: retryReadyTapAndFinalVerifiedWait
            ).count - 1,
            1
        )
        for staleFreshSessionRetryForm in [
            "                storeKitSession = nil",
            #"                guard let fixtureURL = Bundle(for: Self.self).url("#,
            #"                    forResource: "FieldEvidence","#,
            #"                    withExtension: "storekit""#,
            #"                    XCTFail("The checked-in StoreKit fixture is required")"#,
            #"                guard let freshSession = try? SKTestSession(contentsOf: fixtureURL) else {"#,
            #"                    XCTFail("A fresh StoreKit test session is required")"#,
            "                storeKitSession = freshSession",
            "freshSession",
            "isDifferentiateStoreKitTransactionInventoryDiagnostic",
            "transactionInventoryBeforeRetryTap",
            "transactionInventoryAfterRetryTap",
            "terminalTransactionInventory",
        ] {
            XCTAssertEqual(
                unverifiedRetrySource.components(
                    separatedBy: staleFreshSessionRetryForm
                ).count - 1,
                0,
                staleFreshSessionRetryForm
            )
        }
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "SKTestSession(contentsOf: fixtureURL)"
            ).count - 1,
            1
        )
        XCTAssertFalse(uiSource.contains("freshSession"))
        XCTAssertFalse(uiSource.contains("storeKitSession = nil"))
        for retainedSessionMutation in [
            "retainedSession.resetToDefaultState()",
            "retainedSession.clearTransactions()",
            "retainedSession.disableDialogs = true",
        ] {
            XCTAssertEqual(
                unverifiedRetrySource.components(
                    separatedBy: retainedSessionMutation
                ).count - 1,
                1,
                retainedSessionMutation
            )
        }
        for removedStoreKitRetryDiagnosticForm in [
            "diagnoseDifferentiateWithoutColorStoreKitRetry",
            "S10_4_STOREKIT_RETRY_RESULT_DIAGNOSTIC",
            "StoreKit retry diagnostic completed nonaccepting",
        ] {
            XCTAssertFalse(
                uiSource.contains(removedStoreKitRetryDiagnosticForm),
                removedStoreKitRetryDiagnosticForm
            )
        }
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
            1
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
            "Thread.sleep",
            "Task.sleep",
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
        for restoredNonthrowingStoreKitCallChainLock in [
            "        captureAlternativeCompletedCheckStates(in: app)",
            "    private func captureAlternativeCompletedCheckStates(\n" +
                "        in app: XCUIApplication\n" +
                "    ) {",
            "        purchaseBlockedEvaluationAndBeginFreshCheck(in: app)",
            "    private func purchaseBlockedEvaluationAndBeginFreshCheck(\n" +
                "        in app: XCUIApplication\n" +
                "    ) {",
            "        let usedSettingsRetry = captureAvailablePaywallAndPurchase(in: app)",
            "    private func captureAvailablePaywallAndPurchase(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: restoredNonthrowingStoreKitCallChainLock
                ).count - 1,
                1,
                restoredNonthrowingStoreKitCallChainLock
            )
        }
        for removedThrowingStoreKitDiagnosticCallChainLock in [
            "        try captureAlternativeCompletedCheckStates(in: app)",
            "    private func captureAlternativeCompletedCheckStates(\n" +
                "        in app: XCUIApplication\n" +
                "    ) throws {",
            "        try purchaseBlockedEvaluationAndBeginFreshCheck(in: app)",
            "    private func purchaseBlockedEvaluationAndBeginFreshCheck(\n" +
                "        in app: XCUIApplication\n" +
                "    ) throws {",
            "        let usedSettingsRetry = try captureAvailablePaywallAndPurchase(in: app)",
            "    private func captureAvailablePaywallAndPurchase(\n" +
                "        in app: XCUIApplication\n" +
                "    ) throws -> Bool {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedThrowingStoreKitDiagnosticCallChainLock
                ).count - 1,
                0,
                removedThrowingStoreKitDiagnosticCallChainLock
            )
        }
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
            11
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
        for removedStoreKitUIDiagnosticFragment in [
            "firstStoreKitDiagnosticValue",
            "finalStoreKitDiagnosticValue",
            "diagnosticValue",
            "firstValue: String",
            "finalValue: String",
            "usedSettingsRetry: Bool",
            "diagnoseStoreKitVerificationAndProcessor",
            "XCTAttachment(string: firstValue)",
            "XCTAttachment(string: finalValue)",
            "S10.4 default-dark StoreKit diagnostic first value",
            "S10.4 default-dark StoreKit diagnostic final value",
            "S10.4 default-dark StoreKit diagnostic accessibility tree",
            "S10.4 default-dark StoreKit diagnostic screenshot",
            "S10_4_STOREKIT_VERIFICATION_PROCESSOR_DIAGNOSTIC",
            "StoreKit verification/processor diagnostic completed nonaccepting",
            #""--s10-4-storekit-purchase-diagnostic""#,
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedStoreKitUIDiagnosticFragment
                ).count - 1,
                0,
                removedStoreKitUIDiagnosticFragment
            )
        }
        XCTAssertEqual(
            purchaseRecoverySource.components(
                separatedBy: "        }\n" + finalVerifiedPurchaseWait
            ).count - 1,
            1
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

        for removedStoreKitTransactionDiagnosticForm in [
            "diagnoseDifferentiateWithoutColorStoreKitTransactionInventory",
            "storeKitTestTransactionObject",
            "storeKitTestTransactionInventory",
            "isDifferentiateStoreKitTransactionInventoryDiagnostic",
            "transactionInventoryBeforeRetryTap",
            "transactionInventoryAfterRetryTap",
            "terminalTransactionInventory",
            "S10_4_STOREKIT_TRANSACTION_INVENTORY_DIAGNOSTIC",
            "StoreKit transaction-inventory diagnostic",
            "StoreKit transaction-inventory diagnostic completed nonaccepting",
            "sessionMatchesRetainedProperty",
            "storeKitSessionPresent",
            #""transactionInventories":"#,
            #""beforeRetryTap":"#,
            #""afterRetryTap":"#,
            "S10.4 s10.4.current.differentiate-without-color StoreKit transaction-inventory diagnostic",
            #"startScreenshot.name = "\(attachmentPrefix) start app""#,
            #"startTree.name = "\(attachmentPrefix) start accessibility tree""#,
            #"terminalScreenshot.name = "\(attachmentPrefix) terminal app""#,
            #"terminalTree.name = "\(attachmentPrefix) terminal accessibility tree""#,
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedStoreKitTransactionDiagnosticForm
                ).count - 1,
                0,
                removedStoreKitTransactionDiagnosticForm
            )
        }

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
            sha256: "F51E4F1FCED9CD3B4C18E219646135B4DD0B102F174F569236F521C23E9957DD"
        )
        let recordWorkSource = try text(recordWorkSourcePath)
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy:
                    "usesImportedFixtureForUITest ? 30_000_000_000 : 5_000_000_000"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "30_000_000_000"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "15_000_000_000"
            ).count - 1,
            0
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "5_000_000_000"
            ).count - 1,
            1
        )
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
        for removedPaywallStoreKitDiagnosticFragment in [
            "S10_4StoreKitPurchaseDiagnosticGate",
            "s10_4StoreKitPurchaseDiagnosticJSON",
            ".accessibilityValue(Text(verbatim: diagnostic))",
            "let diagnostic =",
        ] {
            XCTAssertEqual(
                paywallSource.components(
                    separatedBy: removedPaywallStoreKitDiagnosticFragment
                ).count - 1,
                0,
                removedPaywallStoreKitDiagnosticFragment
            )
        }
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
                "F51E4F1FCED9CD3B4C18E219646135B4DD0B102F174F569236F521C23E9957DD",
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
        let doubleLengthDiagnosticStart =
            #"        if automationShard?.shardID == "s10.4.minimum.double-length" {"#
        let doubleLengthDiagnosticAXBoundary =
            "        let runsAXTextDeleteConfirmationDiagnostic ="
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthDiagnosticStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthDiagnosticAXBoundary).count - 1,
            1
        )
        guard let doubleLengthDiagnosticStartRange = uiSource.range(
            of: doubleLengthDiagnosticStart
        ), let doubleLengthDiagnosticAXRange = uiSource.range(
            of: doubleLengthDiagnosticAXBoundary,
            range: doubleLengthDiagnosticStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the minimum double-length delete diagnostic source slice")
            return
        }
        let doubleLengthDiagnosticSource = String(
            uiSource[
                doubleLengthDiagnosticStartRange.lowerBound..<doubleLengthDiagnosticAXRange.lowerBound
            ]
        )
        let doubleLengthDiagnosticGate =
            "        let deleteConfirmationStateID = \"state.sign-detail.delete-confirmation\"\n" +
                doubleLengthDiagnosticStart
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthDiagnosticGate).count - 1,
            1
        )
        let doubleLengthDiagnosticQueryLocks = [
            #"                    "detail","#,
            #"                        .matching(identifier: "s2.sign-detail.screen")"#,
            #"                    "deleteScreen","#,
            #"                        .matching(identifier: "s6.1.delete.screen")"#,
            #"                    "deleteMessage","#,
            #"                        .matching(identifier: "s6.1.delete.message")"#,
            #"                    "cancelDelete","#,
            #"                        .matching(identifier: "s6.1.delete.cancel")"#,
            #"                    "confirmDelete","#,
            #"                        .matching(identifier: "s6.1.delete.confirm")"#,
            #"                    "siteLabel","#,
            #"                        .matching(identifier: "s2.sign-detail.site-label")"#,
            "                    app.scrollViews.containing(\n" +
                "                        .staticText,\n" +
                #"                        identifier: "s6.1.delete.message""# + "\n" +
                "                    )",
            "                    app.scrollViews.containing(\n" +
                "                        .button,\n" +
                #"                        identifier: "s6.1.delete.cancel""# + "\n" +
                "                    )",
            "                    app.scrollViews.containing(\n" +
                "                        .button,\n" +
                #"                        identifier: "s6.1.delete.confirm""# + "\n" +
                "                    )",
            "                    app.scrollViews.containing(\n" +
                "                        .staticText,\n" +
                #"                        identifier: "s2.sign-detail.site-label""# + "\n" +
                "                    )",
        ]
        for lock in doubleLengthDiagnosticQueryLocks {
            XCTAssertEqual(
                doubleLengthDiagnosticSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(separatedBy: "                (\n").count - 1,
            10
        )
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(
                separatedBy: "            let diagnosticQueries: [(String, XCUIElementQuery)] = ["
            ).count - 1,
            1
        )
        let doubleLengthDiagnosticElementSerializer =
            "            let diagnosticElementObject: (XCUIElement) -> [String: Any] = {\n" +
                "                element in\n" +
                "                let valueObject: Any\n" +
                "                if let value = element.value as? String {\n" +
                "                    valueObject = value\n" +
                "                } else {\n" +
                "                    valueObject = NSNull()\n" +
                "                }\n" +
                "                return [\n" +
                #"                    "exists": element.exists,"# + "\n" +
                #"                    "isHittable": element.isHittable,"# + "\n" +
                #"                    "identifier": element.identifier,"# + "\n" +
                #"                    "label": element.label,"# + "\n" +
                #"                    "value": valueObject,"# + "\n" +
                #"                    "elementTypeRawValue": element.elementType.rawValue,"# + "\n" +
                #"                    "frame": self.auditFrameObject(element.frame),"# + "\n" +
                "                ]\n" +
                "            }"
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(
                separatedBy: doubleLengthDiagnosticElementSerializer
            ).count - 1,
            1
        )
        let doubleLengthAuditFrameHelper =
            "    private func auditFrameObject(_ frame: CGRect) -> [String: Double] {\n" +
                "        [\n" +
                #"            "x": Double(frame.origin.x),"# + "\n" +
                #"            "y": Double(frame.origin.y),"# + "\n" +
                #"            "width": Double(frame.size.width),"# + "\n" +
                #"            "height": Double(frame.size.height),"# + "\n" +
                "        ]\n" +
                "    }"
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthAuditFrameHelper).count - 1,
            1
        )
        let doubleLengthDiagnosticQuerySerializer =
            "            let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {\n" +
                "                query in\n" +
                "                let count = query.count\n" +
                "                var elements: [[String: Any]] = []\n" +
                "                for index in 0..<count {\n" +
                "                    elements.append(\n" +
                "                        diagnosticElementObject(query.element(boundBy: index))\n" +
                "                    )\n" +
                "                }\n" +
                "                return [\n" +
                #"                    "count": count,"# + "\n" +
                #"                    "elements": elements,"# + "\n" +
                "                ]\n" +
                "            }"
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(
                separatedBy: doubleLengthDiagnosticQuerySerializer
            ).count - 1,
            1
        )
        for lock in [
            "            var diagnosticQueryObjects: [String: Any] = [:]",
            "            for (name, query) in diagnosticQueries {\n" +
                "                diagnosticQueryObjects[name] = diagnosticQueryObject(query)\n" +
                "            }",
        ] {
            XCTAssertEqual(
                doubleLengthDiagnosticSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let doubleLengthDiagnosticIntervalLocks = [
            ("            let diagnosticViewportTop = detail.frame.minY\n" +
                "            let diagnosticViewportBottom = detail.frame.maxY", 1),
            ("            let diagnosticPreferredMinimumShift = max(", 1),
            ("            let diagnosticPreferredMaximumShift = min(", 1),
            ("            let diagnosticFallbackMinimumShift = max(", 1),
            ("            let diagnosticFallbackMaximumShift = min(", 1),
            ("                diagnosticViewportTop - deleteScreen.frame.minY,", 1),
            ("                diagnosticViewportTop - deleteMessage.frame.minY,", 2),
            ("                diagnosticViewportTop - cancelDelete.frame.minY,", 2),
            ("                diagnosticViewportTop - confirmDelete.frame.minY", 2),
            ("                diagnosticViewportTop - siteLabel.frame.maxY,", 2),
            ("                    diagnosticViewportBottom - deleteScreen.frame.maxY,", 1),
            ("                        diagnosticViewportBottom - deleteMessage.frame.maxY,", 2),
            ("                            diagnosticViewportBottom - cancelDelete.frame.maxY,", 2),
            ("                            diagnosticViewportBottom - confirmDelete.frame.maxY", 2),
        ]
        for (lock, count) in doubleLengthDiagnosticIntervalLocks {
            XCTAssertEqual(
                doubleLengthDiagnosticSource.components(separatedBy: lock).count - 1,
                count,
                lock
            )
        }
        let doubleLengthDiagnosticZeroAndTargetLocks = [
            "            let diagnosticPreferredContainsZero =\n" +
                "                diagnosticPreferredMinimumShift <= 0\n" +
                "                && diagnosticPreferredMaximumShift >= 0",
            "            let diagnosticFallbackContainsZero =\n" +
                "                diagnosticFallbackMinimumShift <= 0\n" +
                "                && diagnosticFallbackMaximumShift >= 0",
            "            var diagnosticTargetDistance: CGFloat?",
            "            if !diagnosticPreferredContainsZero,\n" +
                "               !diagnosticFallbackContainsZero,\n" +
                "               diagnosticPreferredMinimumShift <= diagnosticPreferredMaximumShift {",
            "            if !diagnosticPreferredContainsZero,\n" +
                "               !diagnosticFallbackContainsZero,\n" +
                "               diagnosticTargetDistance == nil,\n" +
                "               diagnosticFallbackMinimumShift <= diagnosticFallbackMaximumShift {",
            "                let farPreferredDistance =\n" +
                "                    diagnosticPreferredMaximumShift < 0\n" +
                "                    ? diagnosticPreferredMinimumShift\n" +
                "                    : diagnosticPreferredMaximumShift",
            "                let farFallbackDistance =\n" +
                "                    diagnosticFallbackMaximumShift < 0\n" +
                "                    ? diagnosticFallbackMinimumShift\n" +
                "                    : diagnosticFallbackMaximumShift",
            "            let diagnosticTargetDistanceObject: Any\n" +
                "            if let diagnosticTargetDistance {\n" +
                "                diagnosticTargetDistanceObject = Double(diagnosticTargetDistance)\n" +
                "            } else {\n" +
                "                diagnosticTargetDistanceObject = NSNull()\n" +
                "            }",
        ]
        for lock in doubleLengthDiagnosticZeroAndTargetLocks {
            XCTAssertEqual(
                doubleLengthDiagnosticSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let doubleLengthDiagnosticAttachmentLocks = [
            "            let appScreenshot = XCTAttachment(screenshot: app.screenshot())",
            "            let appTree = XCTAttachment(string: app.debugDescription)",
            "            let detailScreenshot = XCTAttachment(screenshot: detail.screenshot())",
            "            let messageScreenshot = XCTAttachment(\n" +
                "                screenshot: deleteMessage.screenshot()\n" +
                "            )",
            "appScreenshot.name = \"S10.4 double-length delete diagnostic app\"",
            "appTree.name = \"S10.4 double-length delete diagnostic tree\"",
            "detailScreenshot.name = \"S10.4 double-length delete diagnostic detail\"",
            "messageScreenshot.name = \"S10.4 double-length delete diagnostic message\"",
            "add(appScreenshot)",
            "add(appTree)",
            "add(detailScreenshot)",
            "add(messageScreenshot)",
        ]
        for lock in doubleLengthDiagnosticAttachmentLocks {
            XCTAssertEqual(
                doubleLengthDiagnosticSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(separatedBy: "XCTAttachment(").count - 1,
            4
        )
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(separatedBy: ".lifetime = .keepAlways").count - 1,
            4
        )
        let doubleLengthDiagnosticJSONLocks = [
            #"                prefix: "S10_4_DOUBLE_LENGTH_DELETE_DIAGNOSTIC","#,
            #"                    "shardID": "s10.4.minimum.double-length","#,
            #"                    "stateID": deleteConfirmationStateID,"#,
            #"                    "applicationStateRawValue": app.state.rawValue,"#,
            #"                    "applicationFrame": auditFrameObject(app.frame),"#,
            #"                    "detailViewportFrame": auditFrameObject(detail.frame),"#,
            #"                    "queries": diagnosticQueryObjects,"#,
            #"                    "preferredMinimumShift": Double("#,
            #"                    "preferredMaximumShift": Double("#,
            #"                    "fallbackMinimumShift": Double("#,
            #"                    "fallbackMaximumShift": Double("#,
            #"                    "preferredContainsZero": diagnosticPreferredContainsZero,"#,
            #"                    "fallbackContainsZero": diagnosticFallbackContainsZero,"#,
            #"                    "preferredIntervalFeasible": diagnosticPreferredMinimumShift"#,
            #"                    "fallbackIntervalFeasible": diagnosticFallbackMinimumShift"#,
            #"                    "recognizedMinimumDistance": 44,"#,
            #"                    "targetDistance": diagnosticTargetDistanceObject,"#,
        ]
        for lock in doubleLengthDiagnosticJSONLocks {
            XCTAssertEqual(
                doubleLengthDiagnosticSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let doubleLengthDiagnosticTerminalThrow =
            "            throw AutomationConfigurationError.invalid(\n" +
                #"                "S10.4 minimum double-length delete-confirmation diagnostic""# + "\n" +
                "            )"
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(
                separatedBy: doubleLengthDiagnosticTerminalThrow
            ).count - 1,
            1
        )
        let doubleLengthDiagnosticBeforeAX =
            doubleLengthDiagnosticTerminalThrow +
                "\n        }\n" +
                doubleLengthDiagnosticAXBoundary
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthDiagnosticBeforeAX).count - 1,
            1
        )
        for prohibitedDoubleLengthDiagnosticForm in [
            "tap(",
            "swipe",
            "coordinate(",
            "press(",
            "drag",
            "scroll(",
            "sleep",
            "wait(",
            "XCTAssert",
            "captureBaseline(",
            "automatedEvidenceIDs",
            "accessibilityTreeDigest",
            "S10_4_AX",
            "S10_4_CONTRAST",
            "return true",
            "return false",
            "firstMatch",
            "element(boundBy: 0)",
            "== 1",
            "CGRect(",
            "711",
            "880",
            "-91",
        ] {
            XCTAssertFalse(
                doubleLengthDiagnosticSource.contains(prohibitedDoubleLengthDiagnosticForm),
                prohibitedDoubleLengthDiagnosticForm
            )
        }
        XCTAssertEqual(
            doubleLengthDiagnosticSource.components(separatedBy: "printJSONLine(").count - 1,
            1
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

        for staleReportCorrectionDiagnosticForm in [
            "let reportCorrectionHeaderDiagnosticShardIDs: Set<String> = [",
            "reportCorrectionHeaderDiagnosticShardIDs.contains(shard.shardID)",
        ] {
            XCTAssertFalse(
                uiSource.contains(staleReportCorrectionDiagnosticForm),
                staleReportCorrectionDiagnosticForm
            )
        }

        let removedReduceTransparencyHeaderDiagnosticForms = [
            "S10_4_REPORT_CORRECTION_HEADER_CONTEXT_DIAGNOSTIC",
            "S10_4_REPORT_CORRECTION_HEADER_AUDIT_DIAGNOSTIC",
            "S10_4_REPORT_CORRECTION_HEADER_AUDIT_COUNT_DIAGNOSTIC",
            "S10.4 reduce-transparency Report-correction-header diagnostic",
            "Report-correction-header diagnostic completed nonaccepting",
            #"if shard.shardID == "s10.4.current.reduce-transparency","#,
            #"identifier: "s4.5.correction.header""#,
            #"identifier: "s4.5.correction.validation""#,
            #"identifier: "s4.5.correction.save""#,
            #"NSPredicate(format: "identifier == %@", "inputView")"#,
            "Report-correction-header audit issue ",
        ]
        for removed in removedReduceTransparencyHeaderDiagnosticForms {
            XCTAssertFalse(restoredCaptureBaselineSource.contains(removed), removed)
        }
        for globallyRemoved in [
            "S10_4_REPORT_CORRECTION_HEADER_CONTEXT_DIAGNOSTIC",
            "S10_4_REPORT_CORRECTION_HEADER_AUDIT_DIAGNOSTIC",
            "S10_4_REPORT_CORRECTION_HEADER_AUDIT_COUNT_DIAGNOSTIC",
            "S10.4 reduce-transparency Report-correction-header diagnostic",
            "Report-correction-header diagnostic completed nonaccepting",
            #"if shard.shardID == "s10.4.current.reduce-transparency","#,
        ] {
            XCTAssertFalse(uiSource.contains(globallyRemoved), globallyRemoved)
        }
        let restoredNormalEligibleExceptionsBinding =
            "            let eligibleExceptions = " +
                "Self.contrastAuditExceptionSignatures.filter {"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: restoredNormalEligibleExceptionsBinding
            ).count - 1,
            1
        )
        XCTAssertEqual(
            restoredCaptureBaselineSource.components(
                separatedBy: restoredNormalEligibleExceptionsBinding
            ).count - 1,
            1
        )

        let exceptionIDs = [
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-WIDE-VIEW",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-CUSTOMER-SITE-NAME",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-BEFORE-YOU-BEGIN",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-FEEDBACK-PRIVACY",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER",
            "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER",
        ]
        let exceptionRationales = [
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Wide view even though the audit-owned crop visibly renders white text on the dark elevated Sample card; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Customer / site name even though the audit-owned crop visibly renders black text on white and the public node is bound to the top navigation-region frame; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Before you begin while the frozen public node frame is bottom-clipped outside the 402x874 application frame in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the I confirm this is the site's time zone label even though the audit-owned crop contains only the iOS keyboard and the frozen public node frame is fully keyboard-occluded in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the lower North Campus label whose frozen public node frame intersects native bottom chrome after bounded positioning makes the header safe and hittable and moves the Visit composite below the application; an exact remaining positive ScrollView drag is unrecognized with zero measured header, lower-label, and Visit movement, while ReportsRootView already renders the label with primaryText; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Feedback privacy copy while the frozen public node frame is top-clipped outside the 402x874 application frame and its remaining slice is bound to native status/navigation chrome; the live Feedback composition simultaneously preserves the frozen App-metadata and Save-diagnostics clearances, and the audit-owned crop confirms that unobscured primaryText renders white on the dark elevated surface; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in default light even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in default dark even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in increased contrast even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in reduce motion even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header with Differentiate Without Color enabled even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header with Reduce Transparency enabled even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
        ]
        XCTAssertEqual(
            exceptionIDs.filter { $0.hasSuffix("REPORT-CORRECTION-HEADER") }.count,
            6
        )
        XCTAssertEqual(
            exceptionIDs.filter { !$0.hasSuffix("REPORT-CORRECTION-HEADER") }.count,
            6
        )
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
            ("state.report-history.ready", 1),
            ("state.report-correction.validation-error", 6),
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
            12
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"issueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            12
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            24
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"owner: "palatis3""#).count - 1,
            12
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionOwner: "palatis3""#)
                .count - 1,
            12
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"expiresAt: "2026-11-20""#).count - 1,
            12
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionExpiresAt: "2026-11-20""#)
                .count - 1,
            12
        )

        let signatureLocks = [
            #"taskID: "report_comprehension""#,
            #"taskID: "one_handed_start""#,
            #"taskID: "history_recovery""#,
            #"elementLabel: "Wide view""#,
            #"elementLabel: "Customer / site name""#,
            #"elementLabel: "Before you begin""#,
            #"elementLabel: "I confirm this is the site's time zone.""#,
            #"elementLabel: "North Campus""#,
            #"elementIdentifier: "s8.4.feedback.privacy""#,
            #"elementLabel: "Your message stays editable. Only app version, build, device model, and iOS version are prefilled; customer and inspection content is never prefilled.""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS""#,
            #"shardID: "s10.4.current.default-light""#,
            #"shardID: "s10.4.current.increased-contrast""#,
            #"shardID: "s10.4.current.reduce-motion""#,
            #"shardID: "s10.4.current.differentiate-without-color""#,
            #"shardID: "s10.4.current.reduce-transparency""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.report-history.ready""#,
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
            "y: 823.66666666666663",
            "width: 329.33333333333331",
            "height: 63.333333333333371",
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
            #"elementLabel: "North Campus""#,
            #"elementLabel: $timeZoneLabel"#,
            #"elementIdentifier: "s8.4.feedback.privacy""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS""#,
            #"shardID: "s10.4.current.default-light""#,
            #"shardID: "s10.4.current.increased-contrast""#,
            #"shardID: "s10.4.current.reduce-motion""#,
            #"shardID: "s10.4.current.differentiate-without-color""#,
            #"shardID: "s10.4.current.reduce-transparency""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.report-history.ready""#,
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
            "y: 823.66666666666663",
            "width: 329.33333333333331",
            "height: 63.333333333333371",
            "y: -34.333333333333343",
            "width: 298.33333333333331",
            "height: 86.333333333333343",
            "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        for lock in workflowSignatureLocks {
            XCTAssertTrue(workflowSource.contains(lock), lock)
        }

        let reportHistoryRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the lower North Campus label whose frozen public node frame intersects native bottom chrome after bounded positioning makes the header safe and hittable and moves the Visit composite below the application; an exact remaining positive ScrollView drag is unrecognized with zero measured header, lower-label, and Visit movement, while ReportsRootView already renders the label with primaryText; the exception is limited to the frozen public issue signature."
        let reportHistoryUIAuthority =
            "        ContrastAuditExceptionSignature(\n" +
                #"            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS","# + "\n" +
                #"            shardID: "s10.4.current.ax-text","# + "\n" +
                #"            stateID: "state.report-history.ready","# + "\n" +
                #"            taskID: "report_comprehension","# + "\n" +
                #"            owner: "palatis3","# + "\n" +
                #"            expiresAt: "2026-11-20","# + "\n" +
                "            rationale: \"" + reportHistoryRationale + "\",\n" +
                #"            auditTypeRawValue: "1","# + "\n" +
                #"            compactDescription: "Contrast failed","# + "\n" +
                #"            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","# + "\n" +
                #"            elementIdentifier: "","# + "\n" +
                #"            elementLabel: "North Campus","# + "\n" +
                #"            elementTypeDescription: "XCUIElementType(rawValue: 48)","# + "\n" +
                "            elementFrame: CGRect(\n" +
                "                x: 32,\n" +
                "                y: 823.66666666666663,\n" +
                "                width: 329.33333333333331,\n" +
                "                height: 63.333333333333371\n" +
                "            ),\n" +
                "            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)\n" +
                "        ),"
        XCTAssertEqual(
            uiSource.components(separatedBy: reportHistoryUIAuthority).count - 1,
            1
        )
        let reportHistoryWorkflowAuthority =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.report-history.ready","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS","# + "\n" +
                #"                exceptionOwner: "palatis3","# + "\n" +
                #"                exceptionExpiresAt: "2026-11-20","# + "\n" +
                "                exceptionRationale: \"" + reportHistoryRationale + "\",\n" +
                "                ignoredAuditIssues: [\n" +
                "                  {\n" +
                #"                    auditTypeRawValue: "1","# + "\n" +
                #"                    compactDescription: "Contrast failed","# + "\n" +
                #"                    detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","# + "\n" +
                #"                    elementIdentifier: "","# + "\n" +
                #"                    elementLabel: "North Campus","# + "\n" +
                #"                    elementType: "XCUIElementType(rawValue: 48)","# + "\n" +
                "                    elementFrame: {\n" +
                "                      x: 32,\n" +
                "                      y: 823.66666666666663,\n" +
                "                      width: 329.33333333333331,\n" +
                "                      height: 63.333333333333371\n" +
                "                    },\n" +
                "                    applicationFrame: {x: 0, y: 0, width: 402, height: 874}\n" +
                "                  }\n" +
                "                ]\n" +
                "              },"
        XCTAssertEqual(
            workflowSource.components(separatedBy: reportHistoryWorkflowAuthority).count - 1,
            1
        )
        let reportHistoryWorkflowTuple =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.report-history.ready","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS""# + "\n" +
                "              },"
        XCTAssertEqual(
            workflowSource.components(separatedBy: reportHistoryWorkflowTuple).count - 1,
            1
        )

        let reportHistoryMissingUIAuthority = uiSource.replacingOccurrences(
            of: reportHistoryUIAuthority,
            with: ""
        )
        XCTAssertEqual(
            reportHistoryMissingUIAuthority.components(
                separatedBy: reportHistoryUIAuthority
            ).count - 1,
            0
        )
        let reportHistoryDuplicateUIAuthority = uiSource.replacingOccurrences(
            of: reportHistoryUIAuthority,
            with: reportHistoryUIAuthority + "\n" + reportHistoryUIAuthority
        )
        XCTAssertEqual(
            reportHistoryDuplicateUIAuthority.components(
                separatedBy: reportHistoryUIAuthority
            ).count - 1,
            2
        )

        let reportHistoryMissingWorkflowAuthority = workflowSource.replacingOccurrences(
            of: reportHistoryWorkflowAuthority,
            with: ""
        )
        XCTAssertEqual(
            reportHistoryMissingWorkflowAuthority.components(
                separatedBy: reportHistoryWorkflowAuthority
            ).count - 1,
            0
        )
        let reportHistoryDuplicateWorkflowAuthority = workflowSource.replacingOccurrences(
            of: reportHistoryWorkflowAuthority,
            with: reportHistoryWorkflowAuthority + "\n" + reportHistoryWorkflowAuthority
        )
        XCTAssertEqual(
            reportHistoryDuplicateWorkflowAuthority.components(
                separatedBy: reportHistoryWorkflowAuthority
            ).count - 1,
            2
        )

        let reportHistoryWorkflowAuthorityFieldMutations = [
            (
                "duplicate issue ID",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-CUSTOMER-SITE-NAME"
            ),
            (
                "ineligible shard",
                "shardID: \"s10.4.current.ax-text\"",
                "shardID: \"s10.4.minimum.bounded\""
            ),
            (
                "wrong state",
                "stateID: \"state.report-history.ready\"",
                "stateID: \"state.report-detail.ready\""
            ),
            (
                "wrong task",
                "taskID: \"report_comprehension\"",
                "taskID: \"history_recovery\""
            ),
            (
                "wrong owner",
                "exceptionOwner: \"palatis3\"",
                "exceptionOwner: \"unknown\""
            ),
            (
                "expired authority",
                "exceptionExpiresAt: \"2026-11-20\"",
                "exceptionExpiresAt: \"2026-08-21\""
            ),
            (
                "drifted rationale",
                "the exception is limited to the frozen public issue signature.",
                "the exception is not limited to the frozen public issue signature."
            ),
            (
                "wrong audit type",
                "auditTypeRawValue: \"1\"",
                "auditTypeRawValue: \"2\""
            ),
            (
                "wrong compact description",
                "compactDescription: \"Contrast failed\"",
                "compactDescription: \"Contrast passed\""
            ),
            (
                "wrong detailed description",
                "detailedDescription: \"Contrast failed for SwiftUI.AccessibilityNode\"",
                "detailedDescription: \"Contrast failed for another node\""
            ),
            (
                "wrong element identifier",
                "elementIdentifier: \"\"",
                "elementIdentifier: \"unexpected\""
            ),
            (
                "wrong element label",
                "elementLabel: \"North Campus\"",
                "elementLabel: \"South Campus\""
            ),
            (
                "wrong element type",
                "elementType: \"XCUIElementType(rawValue: 48)\"",
                "elementType: \"XCUIElementType(rawValue: 49)\""
            ),
            ("wrong frame x", "                      x: 32,", "                      x: 31,"),
            (
                "wrong frame y",
                "                      y: 823.66666666666663,",
                "                      y: 823.66666666666664,"
            ),
            (
                "wrong frame width",
                "                      width: 329.33333333333331,",
                "                      width: 329.33333333333332,"
            ),
            (
                "wrong frame height",
                "                      height: 63.333333333333371",
                "                      height: 63.333333333333372"
            ),
            (
                "wrong application frame",
                "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
                "applicationFrame: {x: 0, y: 0, width: 401, height: 874}"
            ),
        ]
        for (label, originalField, mutatedField) in reportHistoryWorkflowAuthorityFieldMutations {
            XCTAssertTrue(reportHistoryWorkflowAuthority.contains(originalField), label)
            let mutatedAuthority = reportHistoryWorkflowAuthority.replacingOccurrences(
                of: originalField,
                with: mutatedField
            )
            XCTAssertNotEqual(mutatedAuthority, reportHistoryWorkflowAuthority, label)
            let mutatedWorkflowSource = workflowSource.replacingOccurrences(
                of: reportHistoryWorkflowAuthority,
                with: mutatedAuthority
            )
            XCTAssertEqual(
                mutatedWorkflowSource.components(
                    separatedBy: reportHistoryWorkflowAuthority
                ).count - 1,
                0,
                label
            )
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

        let reduceMotionUIAuthorityStart =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER","#
        let reduceMotionUIAuthorityEnd =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER","#
        guard let reduceMotionUIAuthorityStartRange = uiSource.range(
            of: reduceMotionUIAuthorityStart
        ),
        let reduceMotionUIAuthorityEndRange = uiSource.range(
            of: reduceMotionUIAuthorityEnd,
            range: reduceMotionUIAuthorityStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the exact reduce-motion UI contrast authority")
            return
        }
        let reduceMotionUIAuthority = String(
            uiSource[
                reduceMotionUIAuthorityStartRange.lowerBound..<reduceMotionUIAuthorityEndRange.lowerBound
            ]
        )
        let reduceMotionWorkflowAuthorityStart =
            "              {\n" +
                #"                shardID: "s10.4.current.reduce-motion","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER","#
        let reduceMotionWorkflowAuthorityEnd =
            "              {\n" +
                #"                shardID: "s10.4.current.differentiate-without-color","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER","#
        guard let reduceMotionWorkflowAuthorityStartRange = workflowSource.range(
            of: reduceMotionWorkflowAuthorityStart
        ),
        let reduceMotionWorkflowAuthorityEndRange = workflowSource.range(
            of: reduceMotionWorkflowAuthorityEnd,
            range: reduceMotionWorkflowAuthorityStartRange.upperBound..<workflowSource.endIndex
        ) else {
            XCTFail("Missing the exact reduce-motion workflow contrast authority")
            return
        }
        let reduceMotionWorkflowAuthority = String(
            workflowSource[
                reduceMotionWorkflowAuthorityStartRange.lowerBound..<reduceMotionWorkflowAuthorityEndRange.lowerBound
            ]
        )
        let reduceMotionRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue " +
                "for the identified Correct report header in reduce motion even though " +
                "the audit-owned crop visibly renders the complete header unobscured " +
                "and wholly above the keyboard; the exception is limited to the frozen " +
                "public issue signature."
        let reduceMotionUIAuthorityLocks = [
            #"issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.reduce-motion""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"owner: "palatis3""#,
            #"expiresAt: "2026-11-20""#,
            "rationale: \"" + reduceMotionRationale + "\"",
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
        let reduceMotionWorkflowAuthorityLocks = [
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.reduce-motion""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"exceptionOwner: "palatis3""#,
            #"exceptionExpiresAt: "2026-11-20""#,
            "exceptionRationale: \"" + reduceMotionRationale + "\"",
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
        for lock in reduceMotionUIAuthorityLocks {
            XCTAssertEqual(
                reduceMotionUIAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for lock in reduceMotionWorkflowAuthorityLocks {
            XCTAssertEqual(
                reduceMotionWorkflowAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let differentiateUIAuthorityStart =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER","#
        let differentiateUIAuthorityEnd =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER","#
        guard let differentiateUIAuthorityStartRange = uiSource.range(
            of: differentiateUIAuthorityStart
        ),
        let differentiateUIAuthorityEndRange = uiSource.range(
            of: differentiateUIAuthorityEnd,
            range: differentiateUIAuthorityStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the exact Differentiate Without Color UI contrast authority")
            return
        }
        let differentiateUIAuthority = String(
            uiSource[
                differentiateUIAuthorityStartRange.lowerBound..<differentiateUIAuthorityEndRange.lowerBound
            ]
        )
        let differentiateWorkflowAuthorityStart =
            "              {\n" +
                #"                shardID: "s10.4.current.differentiate-without-color","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER","#
        let differentiateWorkflowAuthorityEnd =
            "              {\n" +
                #"                shardID: "s10.4.current.reduce-transparency","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER","#
        guard let differentiateWorkflowAuthorityStartRange = workflowSource.range(
            of: differentiateWorkflowAuthorityStart
        ),
        let differentiateWorkflowAuthorityEndRange = workflowSource.range(
            of: differentiateWorkflowAuthorityEnd,
            range: differentiateWorkflowAuthorityStartRange.upperBound..<workflowSource.endIndex
        ) else {
            XCTFail("Missing the exact Differentiate Without Color workflow contrast authority")
            return
        }
        let differentiateWorkflowAuthority = String(
            workflowSource[
                differentiateWorkflowAuthorityStartRange.lowerBound..<differentiateWorkflowAuthorityEndRange.lowerBound
            ]
        )
        let differentiateRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue " +
                "for the identified Correct report header with Differentiate Without Color " +
                "enabled even though the audit-owned crop visibly renders the complete " +
                "header unobscured and wholly above the keyboard; the exception is limited " +
                "to the frozen public issue signature."
        let differentiateUIAuthorityLocks = [
            #"issueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.differentiate-without-color""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"owner: "palatis3""#,
            #"expiresAt: "2026-11-20""#,
            "rationale: \"\(differentiateRationale)\"",
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
        let differentiateWorkflowAuthorityLocks = [
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.differentiate-without-color""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"exceptionOwner: "palatis3""#,
            #"exceptionExpiresAt: "2026-11-20""#,
            "exceptionRationale: \"\(differentiateRationale)\"",
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
        for lock in differentiateUIAuthorityLocks {
            XCTAssertEqual(
                differentiateUIAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for lock in differentiateWorkflowAuthorityLocks {
            XCTAssertEqual(
                differentiateWorkflowAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let reduceTransparencyUIAuthorityStart = differentiateUIAuthorityEnd
        let reduceTransparencyUIAuthorityEnd =
            "    ]\n\n    private static let commonTaskStateIDs:"
        guard let reduceTransparencyUIAuthorityStartRange = uiSource.range(
            of: reduceTransparencyUIAuthorityStart
        ), let reduceTransparencyUIAuthorityEndRange = uiSource.range(
            of: reduceTransparencyUIAuthorityEnd,
            range: reduceTransparencyUIAuthorityStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the exact Reduce Transparency UI contrast authority")
            return
        }
        let reduceTransparencyUIAuthority = String(
            uiSource[
                reduceTransparencyUIAuthorityStartRange.lowerBound..<reduceTransparencyUIAuthorityEndRange.lowerBound
            ]
        )
        let reduceTransparencyWorkflowAuthorityStart =
            differentiateWorkflowAuthorityEnd
        let reduceTransparencyWorkflowAuthorityEnd =
            "            ]\n          ' > \"$contrast_exception_authority_path\""
        guard let reduceTransparencyWorkflowAuthorityStartRange = workflowSource.range(
            of: reduceTransparencyWorkflowAuthorityStart
        ), let reduceTransparencyWorkflowAuthorityEndRange = workflowSource.range(
            of: reduceTransparencyWorkflowAuthorityEnd,
            range: reduceTransparencyWorkflowAuthorityStartRange.upperBound..<workflowSource.endIndex
        ) else {
            XCTFail("Missing the exact Reduce Transparency workflow contrast authority")
            return
        }
        let reduceTransparencyWorkflowAuthority = String(
            workflowSource[
                reduceTransparencyWorkflowAuthorityStartRange.lowerBound..<reduceTransparencyWorkflowAuthorityEndRange.lowerBound
            ]
        )
        let reduceTransparencyRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue " +
                "for the identified Correct report header with Reduce Transparency enabled " +
                "even though the audit-owned crop visibly renders the complete header " +
                "unobscured and wholly above the keyboard; the exception is limited to " +
                "the frozen public issue signature."
        let reduceTransparencyUIAuthorityLocks = [
            #"issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.reduce-transparency""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"owner: "palatis3""#,
            #"expiresAt: "2026-11-20""#,
            "rationale: \"\(reduceTransparencyRationale)\"",
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
        let reduceTransparencyWorkflowAuthorityLocks = [
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER""#,
            #"shardID: "s10.4.current.reduce-transparency""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"taskID: "report_comprehension""#,
            #"exceptionOwner: "palatis3""#,
            #"exceptionExpiresAt: "2026-11-20""#,
            "exceptionRationale: \"\(reduceTransparencyRationale)\"",
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
        for lock in reduceTransparencyUIAuthorityLocks {
            XCTAssertEqual(
                reduceTransparencyUIAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for lock in reduceTransparencyWorkflowAuthorityLocks {
            XCTAssertEqual(
                reduceTransparencyWorkflowAuthority.components(separatedBy: lock).count - 1,
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
            #"case ("s10.4.current.ax-text", "report_comprehension")"#,
            #"taskIssueLimit = 1"#,
            #"taskStateLimit = 1"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.report-history.ready","# + "\n" +
                #"                ]"#,
            #"case ("s10.4.current.increased-contrast", "report_comprehension")"#,
            #"case ("s10.4.current.differentiate-without-color", "report_comprehension")"#,
            #"taskIssueLimit = 1"#,
            #"taskStateLimit = 1"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.report-correction.validation-error","# + "\n" +
                #"                ]"#,
            #"case ("s10.4.current.reduce-motion", "report_comprehension")"#,
            #"case ("s10.4.current.reduce-transparency", "report_comprehension")"#,
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
                separatedBy: #"case ("s10.4.current.ax-text""#
            ).count - 1,
            2
        )
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
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"case ("s10.4.current.reduce-motion""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"case ("s10.4.current.reduce-transparency""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"case ("s10.4.current.differentiate-without-color""#
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
        let axReportHistoryTaskExceptionBound =
            #"            case ("s10.4.current.ax-text", "report_comprehension"):"# +
                "\n" +
                "                taskIssueLimit = 1\n" +
                "                taskStateLimit = 1\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.report-history.ready","# +
                "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: axReportHistoryTaskExceptionBound
            ).count - 1,
            1
        )
        let reduceMotionTaskExceptionBound =
            #"            case ("s10.4.current.reduce-motion", "report_comprehension"):"# +
                "\n" +
                "                taskIssueLimit = 1\n" +
                "                taskStateLimit = 1\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.report-correction.validation-error","# +
                "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reduceMotionTaskExceptionBound
            ).count - 1,
            1
        )
        let reduceTransparencyTaskExceptionBound =
            #"            case ("s10.4.current.reduce-transparency", "report_comprehension"):"# +
                "\n" +
                "                taskIssueLimit = 1\n" +
                "                taskStateLimit = 1\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.report-correction.validation-error","# +
                "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: reduceTransparencyTaskExceptionBound
            ).count - 1,
            1
        )
        let differentiateTaskExceptionBound =
            #"            case ("s10.4.current.differentiate-without-color", "report_comprehension"):"# +
                "\n" +
                "                taskIssueLimit = 1\n" +
                "                taskStateLimit = 1\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.report-correction.validation-error","# +
                "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: differentiateTaskExceptionBound
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
            #"length == 12"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 11"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 12"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 7"#,
            #"| select(.exceptionIssueID | IN("#,
            #""S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER","#,
            #""S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER""#,
            #"| (.ignoredAuditIssues[0] | tojson)] | unique | length) == 1"#,
            #"| select((.exceptionIssueID | IN("#,
            #")) | not)"#,
            #"| (.ignoredAuditIssues[0] | tojson)] | unique | length) == 6"#,
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
            #"error("reduce-motion contrast exception bound exceeded")"#,
            #"error("differentiate-without-color contrast exception bound exceeded")"#,
            #"error("reduce-transparency contrast exception bound exceeded")"#,
            #"error("AX-text contrast exception bound exceeded")"#,
            #"error("contrast exception on ineligible shard")"#,
            #"def taskIssueLimit($shardID; $taskID):"#,
            #"and $taskID == "one_handed_start" then 3"#,
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#,
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
            #"elif $shard == "s10.4.current.reduce-motion""#,
            #"elif $shard == "s10.4.current.differentiate-without-color""#,
            #"elif $shard == "s10.4.current.reduce-transparency""#,
            #"($matchedAuthorities | length) > 1"#,
            #"($matchedExceptionStateIDs | length) > 1"#,
            #"elif $shard == "s10.4.current.ax-text" then"#,
            #"($matchedAuthorities | length) > 4"#,
            #"($matchedExceptionStateIDs | length) > 3"#,
            #"stateIssueLimit($shardID; $stateID)"#,
            #"and $stateID == "state.check-preflight.ready" then 2"#,
            #"and $stateID == "state.new-sign.editing" then 1"#,
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $stateID == "state.report-history.ready" then 1"#,
            #"and ($stateID == "state.feedback.review-ready""#,
            #"or $stateID == "state.report-correction.validation-error""#,
            #"or $stateID == "state.sample-report.ready") then 1"#,
            #"and $stateID == "state.report-correction.validation-error" then 1"#,
            #"and $shard != "s10.4.current.reduce-motion""#,
            #"and $shard != "s10.4.current.differentiate-without-color""#,
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
                "                  \"S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER\"\n" +
                "                ))\n" +
                "              | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 1\n" +
            "            and ([.[]\n" +
                "              | select((.exceptionIssueID | IN(\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER\"\n" +
                "                )) | not)\n" +
                "              | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 6"
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
        let reduceMotionWorkflowTaskIssueBound =
            #"                elif $shardID == "s10.4.current.reduce-motion""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceMotionWorkflowTaskIssueBound
            ).count - 1,
            2
        )
        let differentiateWorkflowTaskIssueBound =
            #"                elif $shardID == "s10.4.current.differentiate-without-color""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: differentiateWorkflowTaskIssueBound
            ).count - 1,
            2
        )
        let differentiateWorkflowTuple =
            #"                shardID: "s10.4.current.differentiate-without-color","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER""#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: differentiateWorkflowTuple
            ).count - 1,
            2
        )
        let differentiateWorkflowTupleOrder =
            #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-WIDE-VIEW""# + "\n" +
                "              },\n" +
                "              {\n" +
                differentiateWorkflowTuple + "\n" +
                "              },\n" +
                "              {\n" +
                #"                shardID: "s10.4.current.increased-contrast","#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: differentiateWorkflowTupleOrder
            ).count - 1,
            1
        )
        let differentiateWorkflowStateIssueBound =
            #"                elif $shardID == "s10.4.current.differentiate-without-color""# + "\n" +
                #"                     and $stateID == "state.report-correction.validation-error" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: differentiateWorkflowStateIssueBound
            ).count - 1,
            1
        )
        let differentiateWorkflowAggregateBound =
            #"                 elif $shard == "s10.4.current.differentiate-without-color""# + "\n" +
                #"                     and (($matchedAuthorities | length) > 1"# + "\n" +
                #"                       or ($matchedExceptionStateIDs | length) > 1) then"# +
                "\n" +
                #"                   error("differentiate-without-color contrast exception bound exceeded")"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: differentiateWorkflowAggregateBound
            ).count - 1,
            1
        )
        let differentiateWorkflowDownstreamBound =
            #"                      elif $shard == "s10.4.current.differentiate-without-color" then"# + "\n" +
                #"                        ($matchedAuthorities | length) <= 1"# + "\n" +
                #"                        and ($matchedExceptionStateIDs | length) <= 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: differentiateWorkflowDownstreamBound
            ).count - 1,
            1
        )
        let reduceMotionWorkflowTuple =
            #"                shardID: "s10.4.current.reduce-motion","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER""#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceMotionWorkflowTuple
            ).count - 1,
            2
        )
        let reduceMotionWorkflowStateIssueBound =
            #"                elif $shardID == "s10.4.current.reduce-motion""# + "\n" +
                #"                     and $stateID == "state.report-correction.validation-error" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceMotionWorkflowStateIssueBound
            ).count - 1,
            1
        )
        let reduceMotionWorkflowAggregateBound =
            #"                 elif $shard == "s10.4.current.reduce-motion""# + "\n" +
                #"                     and (($matchedAuthorities | length) > 1"# + "\n" +
                #"                       or ($matchedExceptionStateIDs | length) > 1) then"# +
                "\n" +
                #"                   error("reduce-motion contrast exception bound exceeded")"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceMotionWorkflowAggregateBound
            ).count - 1,
            1
        )
        let reduceMotionWorkflowEligibility =
            #"                      and $shard != "s10.4.current.increased-contrast""# + "\n" +
                #"                      and $shard != "s10.4.current.differentiate-without-color""# + "\n" +
                #"                      and $shard != "s10.4.current.ax-text""# + "\n" +
                #"                      and $shard != "s10.4.current.reduce-motion""#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceMotionWorkflowEligibility
            ).count - 1,
            1
        )
        let reduceMotionWorkflowDownstreamBound =
            #"                      elif $shard == "s10.4.current.reduce-motion" then"# + "\n" +
                #"                        ($matchedAuthorities | length) <= 1"# + "\n" +
                #"                        and ($matchedExceptionStateIDs | length) <= 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceMotionWorkflowDownstreamBound
            ).count - 1,
            1
        )
        let reduceTransparencyWorkflowTaskIssueBound =
            #"                elif $shardID == "s10.4.current.reduce-transparency""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowTaskIssueBound
            ).count - 1,
            2
        )
        let reduceTransparencyWorkflowTuple =
            #"                shardID: "s10.4.current.reduce-transparency","# + "\n" +
                #"                stateID: "state.report-correction.validation-error","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER""#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowTuple
            ).count - 1,
            2
        )
        let reduceTransparencyWorkflowTupleOrder =
            reduceMotionWorkflowTuple + "\n" +
                "              },\n" +
                "              {\n" +
                reduceTransparencyWorkflowTuple + "\n" +
                "              }"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowTupleOrder
            ).count - 1,
            1
        )
        let reduceTransparencyWorkflowStateIssueBound =
            #"                elif $shardID == "s10.4.current.reduce-transparency""# + "\n" +
                #"                     and $stateID == "state.report-correction.validation-error" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowStateIssueBound
            ).count - 1,
            1
        )
        let reduceTransparencyWorkflowAggregateBound =
            #"                 elif $shard == "s10.4.current.reduce-transparency""# + "\n" +
                #"                     and (($matchedAuthorities | length) > 1"# + "\n" +
                #"                       or ($matchedExceptionStateIDs | length) > 1) then"# +
                "\n" +
                #"                   error("reduce-transparency contrast exception bound exceeded")"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowAggregateBound
            ).count - 1,
            1
        )
        let reduceTransparencyWorkflowDownstreamBound =
            #"                      elif $shard == "s10.4.current.reduce-transparency" then"# + "\n" +
                #"                        ($matchedAuthorities | length) <= 1"# + "\n" +
                #"                        and ($matchedExceptionStateIDs | length) <= 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowDownstreamBound
            ).count - 1,
            1
        )
        let reduceTransparencyWorkflowEligibility =
            #"                      and $shard != "s10.4.current.reduce-motion""# + "\n" +
                #"                      and $shard != "s10.4.current.reduce-transparency""# + "\n" +
                #"                      and ($matchedAuthorities | length) != 0 then"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reduceTransparencyWorkflowEligibility
            ).count - 1,
            1
        )
        let axWorkflowAggregateBound =
            #"elif $shard == "s10.4.current.ax-text""# + "\n" +
                #"                     and (($matchedAuthorities | length) > 4"# + "\n" +
                #"                       or ($matchedExceptionStateIDs | length) > 3) then"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowAggregateBound).count - 1,
            1
        )
        let axWorkflowTaskIssueBound =
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowTaskIssueBound).count - 1,
            2
        )
        let axWorkflowTaskIssueFunctionBound =
            #"              def taskIssueLimit($shardID; $taskID):"# + "\n" +
                #"                if $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                   and $taskID == "one_handed_start" then 3"# + "\n" +
                #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: axWorkflowTaskIssueFunctionBound
            ).count - 1,
            1
        )
        let axWorkflowTaskStateFunctionBound =
            #"              def taskStateLimit($shardID; $taskID):"# + "\n" +
                #"                if $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                   and $taskID == "one_handed_start" then 2"# + "\n" +
                #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: axWorkflowTaskStateFunctionBound
            ).count - 1,
            1
        )
        let axWorkflowStateIssueBound =
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $stateID == "state.report-history.ready" then 1"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowStateIssueBound).count - 1,
            1
        )
        let axWorkflowDownstreamBound =
            #"                      elif $shard == "s10.4.current.ax-text" then"# + "\n" +
                #"                        ($matchedAuthorities | length) <= 4"# + "\n" +
                #"                        and ($matchedExceptionStateIDs | length) <= 3"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowDownstreamBound).count - 1,
            1
        )
        let axWorkflowLimitMutations = [
            (
                "AX task issue limit expansion",
                axWorkflowTaskIssueFunctionBound,
                axWorkflowTaskIssueFunctionBound.replacingOccurrences(
                    of: #"and $taskID == "report_comprehension" then 1"#,
                    with: #"and $taskID == "report_comprehension" then 2"#
                )
            ),
            (
                "AX task state limit expansion",
                axWorkflowTaskStateFunctionBound,
                axWorkflowTaskStateFunctionBound.replacingOccurrences(
                    of: #"and $taskID == "report_comprehension" then 1"#,
                    with: #"and $taskID == "report_comprehension" then 2"#
                )
            ),
            (
                "AX Report-history state issue limit expansion",
                axWorkflowStateIssueBound,
                axWorkflowStateIssueBound.replacingOccurrences(
                    of: "then 1",
                    with: "then 2"
                )
            ),
            (
                "AX aggregate limit expansion",
                axWorkflowAggregateBound,
                axWorkflowAggregateBound
                    .replacingOccurrences(of: "> 4", with: "> 5")
                    .replacingOccurrences(of: "> 3", with: "> 4")
            ),
            (
                "AX downstream limit expansion",
                axWorkflowDownstreamBound,
                axWorkflowDownstreamBound
                    .replacingOccurrences(of: "<= 4", with: "<= 5")
                    .replacingOccurrences(of: "<= 3", with: "<= 4")
            ),
        ]
        for (label, canonicalBound, mutatedBound) in axWorkflowLimitMutations {
            XCTAssertNotEqual(mutatedBound, canonicalBound, label)
            let mutatedWorkflowSource = workflowSource.replacingOccurrences(
                of: canonicalBound,
                with: mutatedBound
            )
            XCTAssertEqual(
                mutatedWorkflowSource.components(separatedBy: canonicalBound).count - 1,
                0,
                label
            )
        }
        for staleLock in [
            #"length == 7"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 6"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 7"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 4"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 5"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 5"#,
            #"($matchedAuthorities | length) > 2"#,
            "            length == 8\n" +
                "            and ([.[] | [.shardID, .stateID] | join(\"|\")] | unique | length) == 7\n" +
                "            and ([.[].exceptionIssueID] | unique | length) == 8",
            "            length == 9\n" +
                "            and ([.[] | [.shardID, .stateID] | join(\"|\")] | unique | length) == 8\n" +
                "            and ([.[].exceptionIssueID] | unique | length) == 9",
            "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER\"\n" +
                "                ))",
            "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER\",\n" +
                "                  \"S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER\"\n" +
                "                ))",
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
            16
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
