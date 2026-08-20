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
            byteCount: 93_469,
            sha256: "A11BE2D278A2415B9E19438F972F5597A3294800E08B9A15537E0B160DC122C6"
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
        try assertFile(
            sourceParts[0],
            byteCount: 153_834,
            sha256: "3B7CB29A51779B1145135AC8D8FF73324A376416E99DC9DC92198D53EF9F9A58"
        )
        let uiSource = try text(sourceParts[0])
        XCTAssertTrue(uiSource.contains("class S10_4AutomatedBrandLabUITests"))
        XCTAssertTrue(uiSource.contains("func testAutomatedBrandLabShard()"))
        XCTAssertTrue(uiSource.contains("printJSONLine(prefix: \"S10_4_AX_STATE\""))
        XCTAssertTrue(uiSource.contains("printJSONLine(prefix: \"S10_4_CONTRAST\""))
        XCTAssertTrue(uiSource.contains("printJSONLine(prefix: \"S10_4_AX\""))
        XCTAssertTrue(uiSource.contains(#""s10.4-ax-\(shard.shardID)-\(stateID)""#))
        XCTAssertTrue(uiSource.contains("s10.4-focus-order-"))
        XCTAssertTrue(uiSource.contains("s10.4-target-size-"))
        XCTAssertTrue(uiSource.contains("automatedEvidenceIDs"))
        XCTAssertTrue(uiSource.contains("22A3351"))

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
                "            return\n" +
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
                14_782,
                "42134ED62E5CA5B909E02540E5AF4B9458F4723F755AC780845562AF2E6954A3",
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
                15_114,
                "96E6B5F37BA346E4ACC803DB7F85A76BF75DD7A38940AC420595A74CD067C28D",
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
                25_794,
                "D791C50C2812F53B9BEBF128CE71A0C2A7C8EC0644C3EFC5CFA8C6F939A23535",
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

        let exceptionIDs = [
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-WIDE-VIEW",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-CUSTOMER-SITE-NAME",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-BEFORE-YOU-BEGIN",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION",
            "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-FEEDBACK-PRIVACY",
        ]
        let exceptionRationales = [
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Wide view even though the audit-owned crop visibly renders white text on the dark elevated Sample card; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Customer / site name even though the audit-owned crop visibly renders black text on white and the public node is bound to the top navigation-region frame; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Before you begin while the frozen public node frame is bottom-clipped outside the 402x874 application frame in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the I confirm this is the site's time zone label even though the audit-owned crop contains only the iOS keyboard and the frozen public node frame is fully keyboard-occluded in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Feedback privacy copy while the frozen public node frame is top-clipped outside the 402x874 application frame and its remaining slice is bound to native status/navigation chrome; the live Feedback composition simultaneously preserves the frozen App-metadata and Save-diagnostics clearances, and the audit-owned crop confirms that unobscured primaryText renders white on the dark elevated surface; the exception is limited to the frozen public issue signature.",
        ]
        for lock in exceptionIDs {
            XCTAssertEqual(uiSource.components(separatedBy: lock).count - 1, 1, lock)
            XCTAssertEqual(workflowSource.components(separatedBy: lock).count - 1, 2, lock)
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
            5
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"issueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            5
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            10
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"owner: "palatis3""#).count - 1,
            5
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionOwner: "palatis3""#)
                .count - 1,
            5
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"expiresAt: "2026-11-20""#).count - 1,
            5
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionExpiresAt: "2026-11-20""#)
                .count - 1,
            5
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
            #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
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
            #"elementType: "XCUIElementType(rawValue: 48)""#,
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
            #"case ("s10.4.current.default-dark", "report_comprehension")"#,
            #"permittedExceptionStateIDs = ["state.sample-report.ready"]"#,
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
                separatedBy: #"case ("s10.4.current.default-dark""#
            ).count - 1,
            2,
            "The two default-dark exception issues must remain bound to separate tasks"
        )
        let feedbackDiagnosticCall =
            #"            if shard.shardID == "s10.4.current.default-dark","# + "\n" +
                #"               stateID == "state.feedback.review-ready" {"# + "\n" +
                "                try enumerateFeedbackContrastAuditIssues(\n" +
                "                    in: app,\n" +
                "                    eligibleExceptions: eligibleExceptions\n" +
                "                )\n" +
                "            }"
        XCTAssertEqual(
            uiSource.components(separatedBy: feedbackDiagnosticCall).count - 1,
            1
        )
        let feedbackDiagnosticCallParts = uiSource.components(
            separatedBy: feedbackDiagnosticCall
        )
        XCTAssertEqual(feedbackDiagnosticCallParts.count, 2)
        let feedbackDiagnosticCallTail = feedbackDiagnosticCallParts[1]
        let genericStateIssueLimitMarker = "\n            let stateIssueLimit ="
        guard let genericStateIssueLimitRange = feedbackDiagnosticCallTail.range(
            of: genericStateIssueLimitMarker
        ) else {
            XCTFail("The Feedback diagnostic call must precede generic issue matching")
            return
        }
        let feedbackDiagnosticCallPrefix = String(
            feedbackDiagnosticCallTail[..<genericStateIssueLimitRange.lowerBound]
        )
        XCTAssertFalse(feedbackDiagnosticCallPrefix.contains("matchedExceptions"))
        XCTAssertFalse(feedbackDiagnosticCallPrefix.contains("accessibilityTreeDigest"))

        let feedbackDiagnosticStartMarker =
            "    @MainActor\n" +
                "    private func enumerateFeedbackContrastAuditIssues("
        let feedbackDiagnosticParts = uiSource.components(
            separatedBy: feedbackDiagnosticStartMarker
        )
        guard feedbackDiagnosticParts.count == 2 else {
            XCTFail("The UI source must contain exactly one Feedback enumeration helper")
            return
        }
        let feedbackDiagnosticTail = feedbackDiagnosticParts[1]
        let feedbackDiagnosticBoundary = "\n    private func isActive("
        guard let feedbackDiagnosticEnd = feedbackDiagnosticTail.range(
            of: feedbackDiagnosticBoundary
        ) else {
            XCTFail("The Feedback enumeration helper has no exact helper boundary")
            return
        }
        let feedbackDiagnosticSlice = feedbackDiagnosticStartMarker
            + String(feedbackDiagnosticTail[..<feedbackDiagnosticEnd.lowerBound])

        let feedbackBindingLocks = [
            #"let feedbackScreen = element("s8.4.feedback.screen", in: app)"#,
            "let feedbackScrollViews = app.scrollViews.allElementsBoundByIndex.filter {",
            #".matching(identifier: "s8.4.feedback.save-diagnostics")"#,
            ".count == 1",
            "guard feedbackScrollViews.count == 1,",
            "let feedbackScrollView = feedbackScrollViews.first else",
            #"let privacy = element("s8.4.feedback.privacy", in: app)"#,
            #"let review = element("s8.4.feedback.review", in: app)"#,
            #".matching(NSPredicate(format: "label BEGINSWITH %@", "App "))"#,
            #"let copyAddress = element("s8.4.feedback.copy-address", in: app)"#,
            "let saveDiagnostics = feedbackScrollView.descendants(matching: .any)",
            "let navigationBar = app.navigationBars.firstMatch",
            #"let signsTab = element("s1.tab.signs", in: app)"#,
            "S10.4 Feedback diagnostic live bindings are incomplete",
            "guard eligibleExceptions.count == 1,",
            "let privacyAuthority = eligibleExceptions.first,",
            "privacyAuthority.elementIdentifier == privacy.identifier,",
            #"privacyAuthority.taskID == "history_recovery" else"#,
        ]
        for lock in feedbackBindingLocks {
            XCTAssertTrue(feedbackDiagnosticSlice.contains(lock), lock)
        }
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(
                separatedBy: #".matching(identifier: "s8.4.feedback.save-diagnostics")"#
            ).count - 1,
            2
        )

        let feedbackPublicFieldLocks = [
            #""auditTypeRawValue": auditTypeRawValue,"#,
            #""compactDescription": issue.compactDescription,"#,
            #""detailedDescription": issue.detailedDescription,"#,
            #""elementIdentifier": elementIdentifier,"#,
            #""elementLabel": elementLabel,"#,
            #""elementType": elementType,"#,
            #""elementFrame": elementFrameObject,"#,
            #""applicationFrame": self.auditFrameObject(applicationFrame),"#,
        ]
        for lock in feedbackPublicFieldLocks {
            XCTAssertEqual(
                feedbackDiagnosticSlice.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let feedbackLiveFieldLocks = [
            #""liveFeedbackScreenFrame": self.auditFrameObject("#,
            #""liveFeedbackScrollViewFrame": self.auditFrameObject("#,
            #""livePrivacyFrame": self.auditFrameObject(privacy.frame)"#,
            #""liveReviewFrame": self.auditFrameObject(review.frame)"#,
            #""liveAppMetadataFrame": self.auditFrameObject(appMetadata.frame)"#,
            #""liveCopyAddressFrame": self.auditFrameObject(copyAddress.frame)"#,
            #""liveSaveDiagnosticsFrame": self.auditFrameObject("#,
            #""liveNavigationBarFrame": self.auditFrameObject("#,
            #""liveSignsTabFrame": self.auditFrameObject(signsTab.frame)"#,
            #""liveApplicationFrame": self.auditFrameObject(app.frame)"#,
        ]
        for lock in feedbackLiveFieldLocks {
            XCTAssertEqual(
                feedbackDiagnosticSlice.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let feedbackMatchLocks = [
            #"let eligibleIssueIDs = eligibleExceptions.map(\.issueID).sorted()"#,
            "var callbackCount = 0",
            "callbackCount += 1",
            "let issueIndex = callbackCount",
            "var orderedIssueIdentities: [String] = []",
            "orderedIssueIdentities.append(issueIdentity)",
            "let elementFrameObject: Any",
            "if let elementFrame {",
            "elementFrameObject = self.auditFrameObject(elementFrame)",
            "elementFrameObject = NSNull()",
            "let privacyAuthorityFieldMatches: [String: Bool] = [",
            "== privacyAuthority.auditTypeRawValue",
            "== privacyAuthority.compactDescription",
            "== privacyAuthority.detailedDescription",
            "== privacyAuthority.elementIdentifier",
            "elementLabel == privacyAuthority.elementLabel",
            "== privacyAuthority.elementTypeDescription",
            "elementFrame == privacyAuthority.elementFrame",
            "== privacyAuthority.applicationFrame",
            "let mismatchedPrivacyAuthorityFields = privacyAuthorityFieldMatches",
            ".filter { !$0.value }",
            #".map(\.key)"#,
            ".sorted()",
            #""eligibleIssueIDs": eligibleIssueIDs"#,
            #""privacyAuthority": self.publicAuditSignatureObject("#,
            #""privacyAuthorityFieldMatches": privacyAuthorityFieldMatches"#,
            #""privacyAuthorityMatchClassification":"#,
            #"? "EXACT_MATCH""#,
            #": "FIELD_MISMATCH""#,
            #""mismatchedPrivacyAuthorityFields":"#,
        ]
        for lock in feedbackMatchLocks {
            XCTAssertTrue(feedbackDiagnosticSlice.contains(lock), lock)
        }
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(
                separatedBy: #"prefix: "S10_4_AUDIT_DIAGNOSTIC""#
            ).count - 1,
            1
        )

        let feedbackAttachmentLocks = [
            "let appAttachment = XCTAttachment(screenshot: app.screenshot())",
            #"format: "S10.4 Feedback diagnostic app callback %03d""#,
            "appAttachment.lifetime = .keepAlways",
            "self.add(appAttachment)",
            "if let auditedElement {",
            "let issueAttachment = XCTAttachment(",
            "screenshot: auditedElement.screenshot()",
            #"format: "S10.4 Feedback diagnostic issue callback %03d %@""#,
            "issueAttachment.lifetime = .keepAlways",
            "self.add(issueAttachment)",
        ]
        for lock in feedbackAttachmentLocks {
            XCTAssertEqual(
                feedbackDiagnosticSlice.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(separatedBy: "XCTAttachment").count - 1,
            2
        )
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(separatedBy: "return true").count - 1,
            1
        )
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(separatedBy: "return false").count - 1,
            0
        )

        let feedbackDiagnosticTerminalLocks = [
            "guard callbackCount > 0 else {",
            "S10.4 Feedback diagnostic returned with callbackCount=0",
            "S10.4 Feedback diagnostic enumerated callbackCount=\\(callbackCount) ",
            "+ \"orderedIssueIdentities=\\(orderedIssueIdentities)\"",
        ]
        for lock in feedbackDiagnosticTerminalLocks {
            XCTAssertEqual(
                feedbackDiagnosticSlice.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        let feedbackDiagnosticPositiveCountGuard =
            "        guard callbackCount > 0 else {\n" +
                "            throw AutomationConfigurationError.invalid(\n" +
                "                \"S10.4 Feedback diagnostic returned with callbackCount=0\"\n" +
                "            )\n" +
                "        }"
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(
                separatedBy: feedbackDiagnosticPositiveCountGuard
            ).count - 1,
            1
        )
        let feedbackDiagnosticUnconditionalThrow =
            "        throw AutomationConfigurationError.invalid(\n" +
                "            \"S10.4 Feedback diagnostic enumerated callbackCount=\\(callbackCount) \"\n" +
                "                + \"orderedIssueIdentities=\\(orderedIssueIdentities)\"\n" +
                "        )"
        XCTAssertEqual(
            feedbackDiagnosticSlice.components(
                separatedBy: feedbackDiagnosticUnconditionalThrow
            ).count - 1,
            1
        )
        let auditRange = try XCTUnwrap(
            feedbackDiagnosticSlice.range(
                of: "try app.performAccessibilityAudit(for: .contrast) { issue in"
            )
        )
        let appAttachmentRange = try XCTUnwrap(
            feedbackDiagnosticSlice.range(of: "let appAttachment = XCTAttachment")
        )
        let conditionalIssueAttachmentRange = try XCTUnwrap(
            feedbackDiagnosticSlice.range(of: "if let auditedElement {")
        )
        let returnTrueRange = try XCTUnwrap(
            feedbackDiagnosticSlice.range(of: "return true")
        )
        let positiveCountRange = try XCTUnwrap(
            feedbackDiagnosticSlice.range(of: "guard callbackCount > 0 else {")
        )
        let orderedThrowRange = try XCTUnwrap(
            feedbackDiagnosticSlice.range(
                of: "S10.4 Feedback diagnostic enumerated callbackCount="
            )
        )
        XCTAssertLessThan(auditRange.lowerBound, appAttachmentRange.lowerBound)
        XCTAssertLessThan(
            appAttachmentRange.lowerBound,
            conditionalIssueAttachmentRange.lowerBound
        )
        XCTAssertLessThan(
            conditionalIssueAttachmentRange.lowerBound,
            returnTrueRange.lowerBound
        )
        XCTAssertLessThan(returnTrueRange.lowerBound, positiveCountRange.lowerBound)
        XCTAssertLessThan(positiveCountRange.lowerBound, orderedThrowRange.lowerBound)

        for forbidden in [
            "accessibilityTreeDigest(in: app)",
            "automationAXTreeDigests",
            #"printJSONLine(prefix: "S10_4_AX_STATE""#,
            #"printJSONLine(prefix: "S10_4_CONTRAST""#,
            "automationContrastExceptions[stateID]",
            "automatedEvidenceIDs",
            "matchedExceptions",
            "S10.4 candidate ",
            "shard-receipt",
        ] {
            XCTAssertFalse(feedbackDiagnosticSlice.contains(forbidden), forbidden)
        }
        XCTAssertEqual(
            uiSource.components(separatedBy: "S10_4_AUDIT_DIAGNOSTIC").count - 1,
            1
        )

        let workflowProtocolLocks = [
            "contrast_exception_authority_path=",
            #"if .result == "PASS" then"#,
            #"elif .result == "EXCEPTION" then"#,
            #"length == 5"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 4"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 5"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 5"#,
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
            #"error("default-dark contrast exception bound exceeded")"#,
            #"error("AX-text contrast exception bound exceeded")"#,
            #"error("contrast exception on ineligible shard")"#,
            #"def taskIssueLimit($shardID; $taskID):"#,
            #"and $taskID == "one_handed_start" then 3"#,
            #"and ($taskID == "history_recovery""#,
            #"or $taskID == "report_comprehension") then 1"#,
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
            #"if $shard == "s10.4.current.default-dark" then"#,
            #"($matchedAuthorities | length) > 2"#,
            #"($matchedExceptionStateIDs | length) > 2"#,
            #"elif $shard == "s10.4.current.ax-text" then"#,
            #"($matchedAuthorities | length) > 3"#,
            #"stateIssueLimit($shardID; $stateID)"#,
            #"and $stateID == "state.check-preflight.ready" then 2"#,
            #"and $stateID == "state.new-sign.editing" then 1"#,
            #"and ($stateID == "state.feedback.review-ready""#,
            #"or $stateID == "state.sample-report.ready") then 1"#,
            #"matchedStateAuthorities($row; $exceptions[0]; $today) as $matched"#,
            #"($matched | length) > 0"#,
            #"<= stateIssueLimit($row.shardID; $row.stateID)"#,
            "strict Apple contrast evidence.",
        ]
        for lock in workflowProtocolLocks {
            XCTAssertTrue(workflowSource.contains(lock), lock)
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
            2
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
