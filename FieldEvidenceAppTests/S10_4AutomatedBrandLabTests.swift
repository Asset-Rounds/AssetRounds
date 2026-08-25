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
        let dispatcherPath = ".github/workflows/ios-ci.yml"
        try assertFile(
            dispatcherPath,
            byteCount: 48_773,
            sha256: "C3B8D302792803A46BC48BB3F8B08E05248579E29BC31848E4653C15F23640E7"
        )
        let dispatcherSource = try text(dispatcherPath)
        let workflowPath = ".github/workflows/ios-ci-worker.yml"
        try assertFile(
            workflowPath,
            byteCount: 132_120,
            sha256: "861A3705A343BF1BA580BBFEB3D00CC7E20EB7E2CDC8F5AA28B93BBA05AA9E83"
        )
        let workflowSource = try text(workflowPath)
        let workerCallHeader =
            "  workflow_call:\n" +
                "    inputs:\n" +
                "      runner_label:\n" +
                "        description: Runner label supplied by the Phase 10 dispatcher\n" +
                "        required: true\n" +
                "        type: string\n" +
                "      runner_provider:\n" +
                "        description: Closed runner provider supplied by the Phase 10 dispatcher\n" +
                "        required: true\n" +
                "        type: string\n" +
                "      run_ui_smoke:"
        let dynamicRunnerLine = #"    runs-on: ${{ inputs.runner_label }}"#
        let warpBuildRunnerLine = "    runs-on: warp-macos-26-arm64-6x"
        XCTAssertEqual(workflowSource.components(separatedBy: workerCallHeader).count - 1, 1)
        XCTAssertEqual(workflowSource.components(separatedBy: dynamicRunnerLine).count - 1, 1)
        XCTAssertEqual(workflowSource.components(separatedBy: warpBuildRunnerLine).count - 1, 0)
        XCTAssertEqual(workflowSource.components(separatedBy: "    runs-on: macos-26").count - 1, 0)
        let predecessorWorkerByteCount = 119_764
        let predecessorWorkerSHA256 =
            "E3B011AC1E86724599FC75BC5A6AAEC674CDCEEBC53C59FA8E6AE5DDDF7BE426"
        XCTAssertGreaterThan(workflowSource.utf8.count, predecessorWorkerByteCount)
        XCTAssertNotEqual(Data(workflowSource.utf8).sha256, predecessorWorkerSHA256)
        let dispatcherShardOptions =
            "        options:\n" +
                "          - none\n" +
                "          - s10.4.current.default-light\n" +
                "          - s10.4.current.default-dark\n" +
                "          - s10.4.current.increased-contrast\n" +
                "          - s10.4.current.ax-text\n" +
                "          - s10.4.current.differentiate-without-color\n" +
                "          - s10.4.current.reduce-motion\n" +
                "          - s10.4.current.reduce-transparency\n" +
                "          - s10.4.minimum.minimum-os\n" +
                "          - s10.4.minimum.double-length\n" +
                "          - s10.4.minimum.rtl\n" +
                "          - s10.4.minimum.rtl-string\n" +
                "          - s10.4.minimum.tall\n" +
                "          - s10.4.minimum.accented\n" +
                "          - s10.4.minimum.bounded"
        let dispatcherRunUIInput =
            "      run_ui_smoke:\n" +
                "        description: Run the task-authorized XCUITest smoke after build and unit tests\n" +
                "        required: true\n" +
                "        default: false\n" +
                "        type: boolean"
        let dispatcherShardInput =
            "      s10_4_shard_id:\n" +
                "        description: Select one exact S10.4 shard, or none for other tasks\n" +
                "        required: true\n" +
                "        default: none\n" +
                "        type: choice\n" +
                dispatcherShardOptions
        let exactDispatcherShardIDs = [
            "s10.4.current.default-light",
            "s10.4.current.default-dark",
            "s10.4.current.increased-contrast",
            "s10.4.current.ax-text",
            "s10.4.current.differentiate-without-color",
            "s10.4.current.reduce-motion",
            "s10.4.current.reduce-transparency",
            "s10.4.minimum.minimum-os",
            "s10.4.minimum.double-length",
            "s10.4.minimum.rtl",
            "s10.4.minimum.rtl-string",
            "s10.4.minimum.tall",
            "s10.4.minimum.accented",
            "s10.4.minimum.bounded",
        ]
        XCTAssertEqual(Set(exactDispatcherShardIDs).count, 14)
        XCTAssertEqual(dispatcherSource.components(separatedBy: "  workflow_dispatch:").count - 1, 1)
        XCTAssertEqual(dispatcherSource.components(separatedBy: dispatcherRunUIInput).count - 1, 1)
        XCTAssertEqual(dispatcherSource.components(separatedBy: dispatcherShardInput).count - 1, 1)
        XCTAssertEqual(dispatcherSource.components(separatedBy: dispatcherShardOptions).count - 1, 1)
        let dispatcherShardOptionLines = dispatcherShardOptions
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(dispatcherShardOptionLines.count, 16)
        XCTAssertEqual(
            dispatcherShardOptionLines.filter { $0 == "          - none" }.count,
            1
        )
        for shardID in exactDispatcherShardIDs {
            XCTAssertEqual(
                dispatcherShardOptionLines.filter { $0 == "          - \(shardID)" }.count,
                1,
                shardID
            )
        }

        let dispatcherRunName =
            #"run-name: iOS CI · lane=${{ inputs.execution_lane }} · shard=${{ inputs.s10_4_shard_id }} · head=${{ github.sha }}"#
        XCTAssertTrue(
            dispatcherSource.hasPrefix(
                "name: iOS CI\n\(dispatcherRunName)\n\non:\n"
            )
        )
        XCTAssertEqual(dispatcherSource.components(separatedBy: "run-name:").count - 1, 1)
        XCTAssertEqual(dispatcherSource.components(separatedBy: dispatcherRunName).count - 1, 1)
        for forbidden in ["${{ github.ref }}", "${{ github.head_ref }}", "${{ github.run_id }}"] {
            XCTAssertFalse(dispatcherRunName.contains(forbidden), forbidden)
        }
        XCTAssertEqual(
            dispatcherRunName.components(separatedBy: "${{ inputs.execution_lane }}").count - 1,
            1
        )
        XCTAssertEqual(
            dispatcherRunName.components(separatedBy: "${{ inputs.s10_4_shard_id }}").count - 1,
            1
        )
        XCTAssertEqual(
            dispatcherRunName.components(separatedBy: "${{ github.sha }}").count - 1,
            1
        )

        let executionLaneMarker = "      execution_lane:\n"
        let runUIInputMarker = "      run_ui_smoke:\n"
        XCTAssertEqual(dispatcherSource.components(separatedBy: executionLaneMarker).count - 1, 1)
        guard
            let executionLaneRange = dispatcherSource.range(of: executionLaneMarker),
            let runUIInputRange = dispatcherSource.range(
                of: runUIInputMarker,
                range: executionLaneRange.upperBound..<dispatcherSource.endIndex
            )
        else {
            XCTFail("The dispatcher execution-lane input is not ordered before run_ui_smoke")
            return
        }
        let executionLaneSource = String(
            dispatcherSource[executionLaneRange.lowerBound..<runUIInputRange.lowerBound]
        )
        XCTAssertEqual(executionLaneSource.components(separatedBy: "        required: true").count - 1, 1)
        XCTAssertEqual(
            executionLaneSource.components(
                separatedBy: "        default: github-xcode-26.6-acceptance"
            ).count - 1,
            1
        )
        XCTAssertEqual(executionLaneSource.components(separatedBy: "        type: choice").count - 1, 1)
        XCTAssertEqual(executionLaneSource.components(separatedBy: "          - ").count - 1, 3)
        XCTAssertEqual(
            executionLaneSource.components(
                separatedBy: "          - github-xcode-26.6-acceptance"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            executionLaneSource.components(
                separatedBy: "          - getmac-xcode-26.6-development-only"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            executionLaneSource.components(
                separatedBy: "          - warp-xcode-26.5-development-only"
            ).count - 1,
            1
        )
        XCTAssertFalse(executionLaneSource.contains("default: getmac-xcode-26.6-development-only"))
        XCTAssertFalse(executionLaneSource.contains("default: warp-xcode-26.5-development-only"))
        XCTAssertFalse(executionLaneSource.contains("type: string"))

        let dispatcherConcurrency =
            "concurrency:\n" +
                #"  group: ios-ci-dispatch-${{ github.ref }}-${{ inputs.s10_4_shard_id }}"# +
                "\n  cancel-in-progress: false"
        XCTAssertEqual(dispatcherSource.components(separatedBy: dispatcherConcurrency).count - 1, 1)
        XCTAssertEqual(dispatcherSource.components(separatedBy: "concurrency:").count - 1, 1)
        XCTAssertFalse(dispatcherConcurrency.contains("execution_lane"))

        let jobsMarker = "jobs:\n"
        let githubJobMarker = "  github-shard:\n"
        let getMacJobMarker = "  getmac-shard:\n"
        let warpJobMarker = "  warpbuild-shard:\n"
        guard
            let jobsRange = dispatcherSource.range(of: jobsMarker),
            let githubJobRange = dispatcherSource.range(
                of: githubJobMarker,
                range: jobsRange.upperBound..<dispatcherSource.endIndex
            ),
            let getMacJobRange = dispatcherSource.range(
                of: getMacJobMarker,
                range: githubJobRange.upperBound..<dispatcherSource.endIndex
            ),
            let warpJobRange = dispatcherSource.range(
                of: warpJobMarker,
                range: getMacJobRange.upperBound..<dispatcherSource.endIndex
            )
        else {
            XCTFail("The dispatcher must contain the exact three provider-lane jobs")
            return
        }
        let jobsSource = String(dispatcherSource[jobsRange.upperBound...])
        let githubJobSource = String(
            dispatcherSource[githubJobRange.lowerBound..<getMacJobRange.lowerBound]
        )
        let getMacJobSource = String(
            dispatcherSource[getMacJobRange.lowerBound..<warpJobRange.lowerBound]
        )
        let warpJobSource = String(dispatcherSource[warpJobRange.lowerBound...])
        let jobHeaderExpression = try NSRegularExpression(
            pattern: #"(?m)^  [A-Za-z0-9_-]+:\n"#
        )
        XCTAssertEqual(
            jobHeaderExpression.numberOfMatches(
                in: jobsSource,
                range: NSRange(location: 0, length: jobsSource.utf16.count)
            ),
            3
        )

        let githubLaneGate =
            #"    if: ${{ inputs.execution_lane == 'github-xcode-26.6-acceptance' }}"#
        let getMacLaneGate =
            #"    if: ${{ inputs.execution_lane == 'getmac-xcode-26.6-development-only' }}"#
        let warpLaneGate =
            #"    if: ${{ inputs.execution_lane == 'warp-xcode-26.5-development-only' }}"#
        XCTAssertEqual(githubJobSource.components(separatedBy: githubLaneGate).count - 1, 1)
        XCTAssertEqual(getMacJobSource.components(separatedBy: getMacLaneGate).count - 1, 1)
        XCTAssertEqual(warpJobSource.components(separatedBy: warpLaneGate).count - 1, 1)
        XCTAssertEqual(
            getMacJobSource.components(
                separatedBy: #"    name: GetMac Xcode 26.6 development-only · ${{ inputs.s10_4_shard_id }}"#
            ).count - 1,
            1
        )
        XCTAssertFalse(githubJobSource.contains("getmac-xcode-26.6-development-only"))
        XCTAssertFalse(githubJobSource.contains("warp-xcode-26.5-development-only"))
        XCTAssertFalse(getMacJobSource.contains("github-xcode-26.6-acceptance"))
        XCTAssertFalse(getMacJobSource.contains("warp-xcode-26.5-development-only"))
        XCTAssertFalse(warpJobSource.contains("github-xcode-26.6-acceptance"))
        XCTAssertFalse(warpJobSource.contains("getmac-xcode-26.6-development-only"))
        XCTAssertEqual(
            dispatcherSource.components(
                separatedBy: "    uses: ./.github/workflows/ios-ci-worker.yml"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            githubJobSource.components(
                separatedBy: "    uses: ./.github/workflows/ios-ci-worker.yml"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            getMacJobSource.components(
                separatedBy: "    uses: ./.github/workflows/ios-ci-worker.yml"
            ).count - 1,
            1
        )
        XCTAssertFalse(warpJobSource.contains("uses: ./.github/workflows/ios-ci-worker.yml"))
        XCTAssertEqual(githubJobSource.components(separatedBy: "      runner_label: macos-26").count - 1, 1)
        XCTAssertEqual(githubJobSource.components(separatedBy: "      runner_provider: github").count - 1, 1)
        XCTAssertEqual(
            githubJobSource.components(
                separatedBy: #"      run_ui_smoke: ${{ inputs.run_ui_smoke }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(getMacJobSource.components(separatedBy: "      runner_label: getmac-tahoe").count - 1, 1)
        XCTAssertEqual(getMacJobSource.components(separatedBy: "      runner_provider: getmac").count - 1, 1)
        XCTAssertEqual(
            getMacJobSource.components(
                separatedBy: #"      run_ui_smoke: ${{ inputs.run_ui_smoke }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            getMacJobSource.components(
                separatedBy: #"      s10_4_shard_id: ${{ inputs.s10_4_shard_id }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            githubJobSource.components(
                separatedBy: #"      s10_4_shard_id: ${{ inputs.s10_4_shard_id }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            warpJobSource.components(
                separatedBy: "    runs-on: warp-macos-26-arm64-6x"
            ).count - 1,
            1
        )
        XCTAssertEqual(warpJobSource.components(separatedBy: "    timeout-minutes: 90").count - 1, 1)
        XCTAssertFalse(dispatcherSource.contains("      runner_label: warp-macos-26-arm64-6x"))
        XCTAssertFalse(dispatcherSource.contains("getmac-macos"))
        XCTAssertFalse(dispatcherSource.contains("getmac-latest"))
        XCTAssertFalse(dispatcherSource.contains("inputs.runner_label"))
        XCTAssertFalse(dispatcherSource.contains("inputs.runner_provider"))
        XCTAssertFalse(dispatcherSource.contains("fromJSON("))
        XCTAssertFalse(dispatcherSource.contains("contains("))
        XCTAssertFalse(dispatcherSource.contains("          - all"))
        XCTAssertFalse(dispatcherSource.contains("strategy:"))
        XCTAssertFalse(dispatcherSource.contains("matrix:"))
        XCTAssertFalse(dispatcherSource.contains("max-parallel:"))

        let workerEnvironmentMarker = "    env:\n"
        let workerStepsMarker = "    steps:\n"
        guard
            let workerEnvironmentRange = workflowSource.range(of: workerEnvironmentMarker),
            let workerStepsRange = workflowSource.range(
                of: workerStepsMarker,
                range: workerEnvironmentRange.upperBound..<workflowSource.endIndex
            )
        else {
            XCTFail("The reusable worker job environment is not uniquely bounded")
            return
        }
        let workerEnvironmentSource = String(
            workflowSource[workerEnvironmentRange.lowerBound..<workerStepsRange.lowerBound]
        )
        XCTAssertEqual(
            workerEnvironmentSource.components(
                separatedBy: #"      CI_RUNNER_LABEL: ${{ inputs.runner_label }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workerEnvironmentSource.components(
                separatedBy: #"      CI_RUNNER_PROVIDER: ${{ inputs.runner_provider }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workerEnvironmentSource.components(
                separatedBy: "/Applications/Xcode_26.6.app/Contents/Developer"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workerEnvironmentSource.components(
                separatedBy: #"      EXPECTED_XCODE_VERSION: "Xcode 26.6""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workerEnvironmentSource.components(
                separatedBy: #"      EXPECTED_XCODE_BUILD: "Build version 17F113""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            warpJobSource.components(
                separatedBy: "      DEVELOPER_DIR: /Applications/Xcode_26.5.app/Contents/Developer"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            warpJobSource.components(
                separatedBy: #"      EXPECTED_XCODE_VERSION: "Xcode 26.5""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            warpJobSource.components(
                separatedBy: #"      EXPECTED_XCODE_BUILD: "Build version 17F42""#
            ).count - 1,
            1
        )
        XCTAssertFalse(warpJobSource.contains("/Applications/Xcode_26.6.app/Contents/Developer"))
        XCTAssertFalse(warpJobSource.contains(#"EXPECTED_XCODE_VERSION: "Xcode 26.6""#))
        XCTAssertFalse(warpJobSource.contains(#"EXPECTED_XCODE_BUILD: "Build version 17F113""#))
        XCTAssertFalse(workflowSource.contains("/Applications/Xcode_26.5.app/Contents/Developer"))
        XCTAssertFalse(workflowSource.contains(#"EXPECTED_XCODE_VERSION: "Xcode 26.5""#))
        XCTAssertFalse(workflowSource.contains(#"EXPECTED_XCODE_BUILD: "Build version 17F42""#))

        let warpScopeStartMarker =
            "      - name: Enforce WarpBuild current-profile development scope\n"
        let executionStartMarker = "      - name: Prepare evidence directory\n"
        let workerExecutionEndMarker = "      - name: Retain S10.4 shard evidence\n"
        let warpExecutionEndMarker = "      - name: Record WarpBuild development-only lane\n"
        guard
            let workerExecutionStart = workflowSource.range(of: executionStartMarker),
            let workerExecutionEnd = workflowSource.range(
                of: workerExecutionEndMarker,
                range: workerExecutionStart.upperBound..<workflowSource.endIndex
            ),
            let warpScopeStart = warpJobSource.range(of: warpScopeStartMarker),
            let warpExecutionStart = warpJobSource.range(of: executionStartMarker),
            let warpExecutionEnd = warpJobSource.range(
                of: warpExecutionEndMarker,
                range: warpExecutionStart.upperBound..<warpJobSource.endIndex
            )
        else {
            XCTFail("The reusable worker and Warp execution slices are not exactly bounded")
            return
        }
        let workerExecutionSource = String(
            workflowSource[workerExecutionStart.lowerBound..<workerExecutionEnd.lowerBound]
        )
        let warpScopeSource = String(
            warpJobSource[warpScopeStart.lowerBound..<warpExecutionStart.lowerBound]
        )
        let warpExecutionSource = String(
            warpJobSource[warpExecutionStart.lowerBound..<warpExecutionEnd.lowerBound]
        )
        XCTAssertEqual(warpScopeSource.utf8.count, 324)
        XCTAssertEqual(
            Data(warpScopeSource.utf8).sha256,
            "EC21360D4B86F961C6D4AAAA016F4947713BC52DF177A8281372BAE12DDC3821"
        )
        XCTAssertEqual(
            warpScopeSource.components(
                separatedBy: #"DISPATCH_S10_4_SHARD_ID: ${{ inputs.s10_4_shard_id }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            warpScopeSource.components(separatedBy: "            s10.4.current.*) ;;").count - 1,
            1
        )
        XCTAssertFalse(warpScopeSource.contains("s10.4.minimum."))
        XCTAssertNotEqual(workerExecutionSource, warpExecutionSource)
        XCTAssertEqual(workerExecutionSource.utf8.count, 40_025)
        XCTAssertEqual(
            Data(workerExecutionSource.utf8).sha256,
            "47CF2AF4092925F00C25FC7C1E064FF95481166B8658BA67C3DED58C8F9EFAE9"
        )
        XCTAssertEqual(warpExecutionSource.utf8.count, 36_775)
        XCTAssertEqual(
            Data(warpExecutionSource.utf8).sha256,
            "7653353DC11C8C0E4382B88E88CDACA5DD87177D537E333B2AEC844703CFB68C"
        )
        XCTAssertEqual(
            warpExecutionSource.components(
                separatedBy: #"test "$DISPATCH_S10_4_SHARD_ID" != "none""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            warpExecutionSource.components(separatedBy: "bash Scripts/ui-smoke.sh").count - 1,
            1
        )

        let exactProviderPolicyFragments = [
            "            github:macos-26 | getmac:getmac-tahoe) ;;",
            "            github:macos-26)",
            "            getmac:getmac-tahoe)",
            #"test "$DEVELOPER_DIR" = "/Applications/Xcode_26.6.app/Contents/Developer""#,
            #"test "$RUNNER_ARCH" = "ARM64""#,
            #"test "$(uname -m)" = "arm64""#,
            #"test "$(sw_vers -productVersion)" = "26.5.2""#,
            #"resolved_developer_dir="$(env -u DEVELOPER_DIR xcode-select -p)""#,
            #"case "$resolved_developer_dir" in /*/Contents/Developer) ;; *) exit 1 ;; esac"#,
            #"printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV""#,
            #"| tee "$CI_ARTIFACT_DIR/runner-provider.txt""#,
        ]
        for fragment in exactProviderPolicyFragments {
            XCTAssertEqual(workflowSource.components(separatedBy: fragment).count - 1, 1, fragment)
        }
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"case "$CI_RUNNER_PROVIDER:$CI_RUNNER_LABEL" in"#
            ).count - 1,
            2
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"test -s "$CI_ARTIFACT_DIR/runner-provider.txt""#
            ).count - 1,
            1
        )
        XCTAssertFalse(workflowSource.contains("getmac-latest"))
        XCTAssertFalse(workflowSource.contains("getmac-macos"))

        let exactRuntimeOverlayFragments = [
            #"CI_S10_4_EFFECTIVE_PROVISION_RUNTIME="$CI_S10_4_PROVISION_RUNTIME""#,
            #"CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION="$CI_S10_4_RUNTIME_DOWNLOAD_VERSION""#,
            #"if test "$CI_RUNNER_PROVIDER" = "getmac"; then"#,
            "              CI_S10_4_EFFECTIVE_PROVISION_RUNTIME=true",
            "                iphone-17-ios-26.2-current)",
            #"test "$CI_S10_4_PROVISION_RUNTIME" = "false""#,
            #"test -z "$CI_S10_4_RUNTIME_DOWNLOAD_VERSION""#,
            "                  CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION=26.2",
            "                iphone-se-3-ios-18.0-minimum)",
            #"test "$CI_S10_4_PROVISION_RUNTIME" = "true""#,
            #"test "$CI_S10_4_RUNTIME_DOWNLOAD_VERSION" = "18.0""#,
            "                  CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION=18.0",
            #""CI_S10_4_PROVISION_RUNTIME=$CI_S10_4_PROVISION_RUNTIME" \"#,
            #""CI_S10_4_RUNTIME_DOWNLOAD_VERSION=$CI_S10_4_RUNTIME_DOWNLOAD_VERSION" \"#,
            #""CI_S10_4_EFFECTIVE_PROVISION_RUNTIME=$CI_S10_4_EFFECTIVE_PROVISION_RUNTIME" \"#,
            #""CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION=$CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION" \"#,
            #"| tee "$CI_ARTIFACT_DIR/simulator-runtime-policy.txt""#,
            #"case "$SIMULATOR_RUNTIME:$SIMULATOR_RUNTIME_BUILD:$CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION" in"#,
            #""iOS 18.0:22A3351:18.0" | "iOS 26.2:23C54:26.2") ;;"#,
            #"-buildVersion "$CI_S10_4_EFFECTIVE_RUNTIME_DOWNLOAD_VERSION" \"#,
            #"test -s "$CI_ARTIFACT_DIR/simulator-runtime-policy.txt""#,
        ]
        for fragment in exactRuntimeOverlayFragments {
            XCTAssertEqual(workflowSource.components(separatedBy: fragment).count - 1, 1, fragment)
        }
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"test "${CI_S10_4_EFFECTIVE_PROVISION_RUNTIME:-}" = "true"; then"#
            ).count - 1,
            2
        )
        XCTAssertFalse(
            workflowSource.contains(#"xcodebuild -downloadPlatform iOS -buildVersion 26.2"#)
        )

        let forbiddenWarpAcceptanceFragments = [
            "Retain S10.4 shard evidence",
            "Begin evidence-finalization budget",
            "Validate required build and test evidence",
            "Hash collected evidence",
            "Recheck evidence-finalization budget",
            "Verify selected total budget before upload",
            "Upload build evidence",
            "shard-receipt.json",
            "final-matrix",
        ]
        for fragment in forbiddenWarpAcceptanceFragments {
            XCTAssertFalse(warpJobSource.contains(fragment), fragment)
        }

        let recordMarker = "      - name: Record WarpBuild development-only lane\n"
        let hashMarker = "      - name: Hash WarpBuild development-only raw evidence\n"
        let uploadMarker = "      - name: Upload WarpBuild development-only raw evidence\n"
        let failMarker = "      - name: Fail closed after WarpBuild development-only evidence\n"
        guard
            let recordRange = warpJobSource.range(of: recordMarker),
            let hashRange = warpJobSource.range(
                of: hashMarker,
                range: recordRange.upperBound..<warpJobSource.endIndex
            ),
            let uploadRange = warpJobSource.range(
                of: uploadMarker,
                range: hashRange.upperBound..<warpJobSource.endIndex
            ),
            let failRange = warpJobSource.range(
                of: failMarker,
                range: uploadRange.upperBound..<warpJobSource.endIndex
            )
        else {
            XCTFail("The four WarpBuild terminal steps are missing or out of order")
            return
        }
        let warpTailSource = String(warpJobSource[recordRange.lowerBound...])
        let recordStepSource = String(
            warpJobSource[recordRange.lowerBound..<hashRange.lowerBound]
        )
        let hashStepSource = String(
            warpJobSource[hashRange.lowerBound..<uploadRange.lowerBound]
        )
        let uploadStepSource = String(
            warpJobSource[uploadRange.lowerBound..<failRange.lowerBound]
        )
        let failStepSource = String(warpJobSource[failRange.lowerBound...])
        let tailIdentities: [(String, Int, String)] = [
            (recordStepSource, 4_502, "FCF665376837CD82D19B5A3070F6B5CE1060A3F69FD66544C03F792F0246C1D8"),
            (hashStepSource, 3_308, "2536189FF7D9E3B0B70C9A7CFC0566C2468DE786D73031CB197E5E31EC95DB84"),
            (uploadStepSource, 471, "A126239E068B2667EDAC7818EFB3BCE2C13358A2428031BAC63A40E0B0C800D8"),
            (failStepSource, 299, "202F52098711873A5914ABE7694DA7E8183A77579A0EB39F898D2B4BAF8FA4FF"),
        ]
        for (source, byteCount, sha256) in tailIdentities {
            XCTAssertEqual(source.utf8.count, byteCount)
            XCTAssertEqual(Data(source.utf8).sha256, sha256)
        }

        let alwaysCondition = #"        if: ${{ always() }}"#
        XCTAssertEqual(warpTailSource.components(separatedBy: alwaysCondition).count - 1, 4)
        for source in [recordStepSource, hashStepSource, uploadStepSource, failStepSource] {
            XCTAssertEqual(source.components(separatedBy: alwaysCondition).count - 1, 1)
        }
        XCTAssertFalse(warpTailSource.contains("continue-on-error"))
        XCTAssertFalse(warpTailSource.contains("exit 0"))

        let developmentLaneKeys = [
            "schemaVersion",
            "laneID",
            "provider",
            "runnerLabel",
            "runnerName",
            "runnerArchitecture",
            "repository",
            "ref",
            "headSHA",
            "runID",
            "runAttempt",
            "shardID",
            "expectedXcodeVersion",
            "expectedXcodeBuild",
            "priorJobStatus",
            "rawEvidenceOnly",
            "acceptanceRetentionPerformed",
            "finalAcceptanceEligible",
        ]
        XCTAssertEqual(developmentLaneKeys.count, 18)
        XCTAssertEqual(Set(developmentLaneKeys).count, 18)
        for key in developmentLaneKeys {
            XCTAssertEqual(recordStepSource.components(separatedBy: "\(key):").count - 1, 1, key)
            XCTAssertEqual(recordStepSource.components(separatedBy: "\"\(key)\"").count - 1, 1, key)
        }
        let recordLiveValueBindings = [
            #"DEVELOPMENT_EXECUTION_LANE: ${{ inputs.execution_lane }}"#,
            #"DEVELOPMENT_SHARD_ID: ${{ inputs.s10_4_shard_id }}"#,
            #"DEVELOPMENT_RUNNER_NAME: ${{ runner.name }}"#,
            #"DEVELOPMENT_RUNNER_ARCHITECTURE: ${{ runner.arch }}"#,
            #"DEVELOPMENT_PRIOR_JOB_STATUS: ${{ job.status }}"#,
            #".laneID == $laneID"#,
            #".runnerName == $runnerName"#,
            #".runnerArchitecture == $runnerArchitecture"#,
            #".repository == $repository"#,
            #".ref == $ref"#,
            #".headSHA == $headSHA"#,
            #".runID == $runID"#,
            #".runAttempt == $runAttempt"#,
            #".shardID == $shardID"#,
            #".priorJobStatus == $priorJobStatus"#,
        ]
        for binding in recordLiveValueBindings {
            XCTAssertEqual(recordStepSource.components(separatedBy: binding).count - 1, 1, binding)
        }
        let recordExactValueFragments = [
            "schemaVersion: 1",
            #"provider: "WarpBuild""#,
            #"runnerLabel: "warp-macos-26-arm64-6x""#,
            #"expectedXcodeVersion: "Xcode 26.5""#,
            #"expectedXcodeBuild: "Build version 17F42""#,
            "rawEvidenceOnly: true",
            "acceptanceRetentionPerformed: false",
            "finalAcceptanceEligible: false",
            #".laneID == "warp-xcode-26.5-development-only""#,
            #".provider == "WarpBuild""#,
            #".runnerLabel == "warp-macos-26-arm64-6x""#,
            #".expectedXcodeVersion == "Xcode 26.5""#,
            #".expectedXcodeBuild == "Build version 17F42""#,
            #".runID | type == "string""#,
            #".runAttempt | type == "string""#,
            #".priorJobStatus | type == "string""#,
            ".rawEvidenceOnly == true",
            ".acceptanceRetentionPerformed == false",
            ".finalAcceptanceEligible == false",
        ]
        for fragment in recordExactValueFragments {
            XCTAssertEqual(recordStepSource.components(separatedBy: fragment).count - 1, 1, fragment)
        }
        XCTAssertEqual(
            recordStepSource.components(
                separatedBy: #"artifact_dir="${CI_ARTIFACT_DIR:-$RUNNER_TEMP/FieldEvidenceCI}""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordStepSource.components(
                separatedBy: "CI_DEVELOPMENT_ONLY_FINALIZATION_START_EPOCH"
            ).count - 1,
            1
        )
        XCTAssertEqual(recordStepSource.components(separatedBy: "development-only-lane.json").count - 1, 2)
        XCTAssertEqual(recordStepSource.components(separatedBy: "          jq -n \\").count - 1, 1)
        XCTAssertEqual(recordStepSource.components(separatedBy: "          jq -e \\").count - 1, 1)
        XCTAssertEqual(recordStepSource.components(separatedBy: "              (keys == [").count - 1, 1)

        let exactHashFragments = [
            #"artifact_dir="${CI_ARTIFACT_DIR:-$RUNNER_TEMP/FieldEvidenceCI}""#,
            #"finalization_start_epoch="${CI_DEVELOPMENT_ONLY_FINALIZATION_START_EPOCH:-$(date +%s)}""#,
            #"setup_artifact_budget_seconds="${CI_SETUP_ARTIFACT_TIMEOUT_SECONDS:-300}""#,
            #"total_budget_seconds="${CI_TOTAL_BUDGET_SECONDS:-4500}""#,
            "development-only-budget.txt",
            #"test "$setup_finalization_elapsed_seconds" -le "$setup_artifact_budget_seconds""#,
            #"test "$total_elapsed_seconds" -le "$total_budget_seconds""#,
            #"find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do"#,
            #"shasum -a 256 "$file""#,
            #"test "$(grep -cF '  ./SHA256SUMS.txt' SHA256SUMS.txt || true)" -eq 0"#,
            #"find . -type f ! -name 'SHA256SUMS.txt' -print"#,
            #"test "$checksum_row_count" -eq "$payload_file_count""#,
            "shasum -a 256 -c SHA256SUMS.txt",
            #"test "$post_hash_setup_finalization_elapsed_seconds" -le "$setup_artifact_budget_seconds""#,
            #"test "$post_hash_total_elapsed_seconds" -le "$total_budget_seconds""#,
        ]
        for fragment in exactHashFragments {
            XCTAssertEqual(hashStepSource.components(separatedBy: fragment).count - 1, 1, fragment)
        }
        XCTAssertFalse(hashStepSource.contains(#"! -name './SHA256SUMS.txt'"#))

        XCTAssertEqual(
            uploadStepSource.components(
                separatedBy: "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uploadStepSource.components(
                separatedBy: #"name: ios-ci-development-only-xcode-26.5-${{ github.run_id }}-${{ github.run_attempt }}-${{ inputs.s10_4_shard_id }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uploadStepSource.components(
                separatedBy: #"path: ${{ runner.temp }}/FieldEvidenceCI"#
            ).count - 1,
            1
        )
        XCTAssertEqual(uploadStepSource.components(separatedBy: "if-no-files-found: error").count - 1, 1)
        XCTAssertEqual(uploadStepSource.components(separatedBy: "include-hidden-files: true").count - 1, 1)
        XCTAssertEqual(uploadStepSource.components(separatedBy: "retention-days: 14").count - 1, 1)
        XCTAssertEqual(warpTailSource.components(separatedBy: "actions/upload-artifact@").count - 1, 1)

        let forcedRedMessage =
            "WarpBuild Xcode 26.5 development-only evidence is never eligible for S10.4 final acceptance."
        XCTAssertEqual(failStepSource.components(separatedBy: forcedRedMessage).count - 1, 1)
        XCTAssertEqual(failStepSource.components(separatedBy: ">&2").count - 1, 1)
        XCTAssertEqual(failStepSource.components(separatedBy: "          exit 1").count - 1, 1)
        guard
            let forcedRedMessageRange = failStepSource.range(of: forcedRedMessage),
            let forcedRedExitRange = failStepSource.range(of: "          exit 1")
        else {
            XCTFail("The WarpBuild terminal must emit its exact reason and exit nonzero")
            return
        }
        XCTAssertLessThan(forcedRedMessageRange.lowerBound, forcedRedExitRange.lowerBound)

        let getMacRecordMarker = "      - name: Record GetMac development-only lane\n"
        let workerHashMarker = "      - name: Hash collected evidence\n"
        let workerUploadMarker = "      - name: Upload build evidence\n"
        let getMacFailMarker = "      - name: Fail closed after GetMac development-only evidence\n"
        guard
            let getMacRecordRange = workflowSource.range(of: getMacRecordMarker),
            let workerHashRange = workflowSource.range(
                of: workerHashMarker,
                range: getMacRecordRange.upperBound..<workflowSource.endIndex
            ),
            let workerUploadRange = workflowSource.range(
                of: workerUploadMarker,
                range: workerHashRange.upperBound..<workflowSource.endIndex
            ),
            let getMacFailRange = workflowSource.range(
                of: getMacFailMarker,
                range: workerUploadRange.upperBound..<workflowSource.endIndex
            )
        else {
            XCTFail("The GetMac record, hash, upload, and forced-red steps are missing or out of order")
            return
        }
        let getMacRecordSource = String(
            workflowSource[getMacRecordRange.lowerBound..<workerHashRange.lowerBound]
        )
        let getMacHashAndBudgetSource = String(
            workflowSource[workerHashRange.lowerBound..<workerUploadRange.lowerBound]
        )
        let getMacUploadSource = String(
            workflowSource[workerUploadRange.lowerBound..<getMacFailRange.lowerBound]
        )
        let getMacFailSource = String(workflowSource[getMacFailRange.lowerBound...])
        let getMacAlwaysCondition = #"        if: ${{ always() && inputs.runner_provider == 'getmac' }}"#
        XCTAssertEqual(
            getMacRecordSource.components(separatedBy: getMacAlwaysCondition).count - 1,
            1
        )
        XCTAssertEqual(
            getMacFailSource.components(separatedBy: getMacAlwaysCondition).count - 1,
            1
        )
        XCTAssertFalse(getMacRecordSource.contains("continue-on-error"))
        XCTAssertFalse(getMacFailSource.contains("continue-on-error"))

        let getMacDevelopmentLaneKeys = [
            "schemaVersion",
            "laneID",
            "provider",
            "runnerLabel",
            "runnerName",
            "runnerArchitecture",
            "runnerImageOS",
            "runnerImageVersion",
            "runnerImageArchitecture",
            "resolvedDeveloperDirectory",
            "repository",
            "ref",
            "headSHA",
            "runID",
            "runAttempt",
            "shardID",
            "expectedXcodeVersion",
            "expectedXcodeBuild",
            "simulatorRuntime",
            "simulatorRuntimeBuild",
            "priorJobStatus",
            "rawEvidenceOnly",
            "finalAcceptanceEligible",
        ]
        XCTAssertEqual(getMacDevelopmentLaneKeys.count, 23)
        XCTAssertEqual(Set(getMacDevelopmentLaneKeys).count, 23)
        for key in getMacDevelopmentLaneKeys {
            XCTAssertEqual(
                getMacRecordSource.components(separatedBy: "\(key):").count - 1,
                1,
                key
            )
            XCTAssertEqual(
                getMacRecordSource.components(separatedBy: "\"\(key)\"").count - 1,
                1,
                key
            )
        }
        let getMacRecordBindings = [
            #"GETMAC_DISPATCH_SHARD_ID: ${{ inputs.s10_4_shard_id }}"#,
            #"GETMAC_PRIOR_JOB_STATUS: ${{ job.status }}"#,
            #"GETMAC_RUNNER_NAME: ${{ runner.name }}"#,
            #"GETMAC_RUNNER_ARCHITECTURE: ${{ runner.arch }}"#,
            #"runner_image_os="$(sw_vers -productName)""#,
            #"runner_image_version="$(sw_vers -productVersion)""#,
            #"runner_image_architecture="$(uname -m)""#,
            #"record_shard_id="${CI_S10_4_SHARD_ID:-$GETMAC_DISPATCH_SHARD_ID}""#,
            #"test -n "$runner_image_os""#,
            #"test -n "$runner_image_version""#,
            #"test -n "$runner_image_architecture""#,
            #"test "$record_shard_id" = "$GETMAC_DISPATCH_SHARD_ID""#,
            #"--arg runnerImageOS "$runner_image_os" \"#,
            #"--arg runnerImageVersion "$runner_image_version" \"#,
            #"--arg runnerImageArchitecture "$runner_image_architecture" \"#,
            #"--arg shardID "$record_shard_id" \"#,
            #"--arg expectedXcodeVersion "$EXPECTED_XCODE_VERSION" \"#,
            #"--arg expectedXcodeBuild "$EXPECTED_XCODE_BUILD" \"#,
            #"--arg simulatorRuntime "${SIMULATOR_RUNTIME:-}" \"#,
            #"--arg simulatorRuntimeBuild "${SIMULATOR_RUNTIME_BUILD:-}" \"#,
            #".shardID == env.GETMAC_DISPATCH_SHARD_ID"#,
        ]
        for binding in getMacRecordBindings {
            XCTAssertEqual(getMacRecordSource.components(separatedBy: binding).count - 1, 1, binding)
        }
        let getMacRecordValues = [
            #"--arg laneID "getmac-xcode-26.6-development-only" \"#,
            #"--arg provider "GetMac" \"#,
            #".laneID == "getmac-xcode-26.6-development-only""#,
            #".provider == "GetMac""#,
            #".runnerLabel == "getmac-tahoe""#,
            #".runnerArchitecture == "ARM64""#,
            #".runnerImageOS == "macOS""#,
            #".runnerImageVersion == "26.5.2""#,
            #".runnerImageArchitecture == "arm64""#,
            #"type == "string" and test("^/.+/Contents/Developer$")"#,
            #".expectedXcodeVersion == "Xcode 26.6""#,
            #".expectedXcodeBuild == "Build version 17F113""#,
            #"(.shardID | startswith("s10.4.current."))"#,
            #".simulatorRuntime == "iOS 26.2""#,
            #".simulatorRuntimeBuild == "23C54""#,
            #"(.shardID | startswith("s10.4.minimum."))"#,
            #".simulatorRuntime == "iOS 18.0""#,
            #".simulatorRuntimeBuild == "22A3351""#,
            #".priorJobStatus == env.GETMAC_PRIOR_JOB_STATUS"#,
            #".priorJobStatus == "success""#,
            #".priorJobStatus == "failure""#,
            #".priorJobStatus == "cancelled""#,
            "rawEvidenceOnly: true",
            "finalAcceptanceEligible: false",
            ".rawEvidenceOnly == true",
            ".finalAcceptanceEligible == false",
        ]
        for fragment in getMacRecordValues {
            XCTAssertEqual(getMacRecordSource.components(separatedBy: fragment).count - 1, 1, fragment)
        }
        XCTAssertEqual(
            getMacRecordSource.components(separatedBy: "getmac-development-only-lane.json").count - 1,
            2
        )
        XCTAssertEqual(
            getMacHashAndBudgetSource.components(
                separatedBy: #"find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do"#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            getMacHashAndBudgetSource.components(separatedBy: "shasum -a 256 -c SHA256SUMS.txt").count - 1,
            1
        )
        XCTAssertEqual(
            getMacUploadSource.components(
                separatedBy: "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            getMacUploadSource.components(
                separatedBy: "ios-ci-development-only-getmac-xcode-26.6-{0}-{1}-{2}"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            getMacUploadSource.components(
                separatedBy: #"inputs.runner_provider == 'getmac'"#
            ).count - 1,
            1
        )
        XCTAssertFalse(getMacUploadSource.contains("include-hidden-files: false"))
        let getMacForcedRedMessage =
            "GetMac Xcode 26.6 development-only evidence is not yet eligible for S10.4 final acceptance."
        XCTAssertEqual(
            getMacFailSource.components(separatedBy: getMacForcedRedMessage).count - 1,
            1
        )
        XCTAssertEqual(getMacFailSource.components(separatedBy: ">&2").count - 1, 1)
        XCTAssertEqual(getMacFailSource.components(separatedBy: "          exit 1").count - 1, 1)
        XCTAssertFalse(getMacFailSource.contains("exit 0"))

        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"  group: ios-ci-${{ github.ref }}-${{ inputs.s10_4_shard_id }}"#
            ).count - 1,
            1
        )
        XCTAssertEqual(workflowSource.components(separatedBy: "  cancel-in-progress: false").count - 1, 1)
        let unitPath = "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift"
        let unitSource = try text(unitPath)
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
            byteCount: 471_225,
            sha256: "A463AF1696359361E6AA3CF0B0B773A5E0F2034D4D59E4D934BFA81B51CE7B5A"
        )
        let uiSource = try text(sourceParts[0])
        XCTAssertTrue(uiSource.contains("class S10_4AutomatedBrandLabUITests"))
        let recordWorkWithoutBaselineStart =
            "    @MainActor\n" +
                "    private func recordWorkWithoutBaseline(in app: XCUIApplication) {"
        XCTAssertEqual(
            uiSource.components(separatedBy: recordWorkWithoutBaselineStart).count - 1,
            1
        )
        guard let recordWorkWithoutBaselineStartRange = uiSource.range(
            of: recordWorkWithoutBaselineStart
        ), let recordWorkWithoutBaselineEndRange = uiSource.range(
            of: "\n    @MainActor\n",
            range: recordWorkWithoutBaselineStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded Record-work helper source")
            return
        }
        let recordWorkWithoutBaselineSource = String(
            uiSource[
                recordWorkWithoutBaselineStartRange.lowerBound ..<
                    recordWorkWithoutBaselineEndRange.lowerBound
            ]
        )
        XCTAssertEqual(recordWorkWithoutBaselineSource.utf8.count, 1_089)
        XCTAssertEqual(
            Data(recordWorkWithoutBaselineSource.utf8).sha256,
            "44CA61EAC4973A2D5957CB81A1A3AEFDFE621EA5392E52C0EB474B204BDC84C0"
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "recordWorkWithoutBaseline(in: app)"
            ).count - 1,
            2
        )
        let recordWorkNavigationWait =
            "        save.tap()\n" +
                #"        XCTAssertTrue(element("s5.1.issue.screen", in: app)"# + "\n" +
                "            .waitForExistence(timeout: 55))\n" +
                "        navigateBack(in: app)"
        XCTAssertEqual(
            recordWorkWithoutBaselineSource.components(
                separatedBy: recordWorkNavigationWait
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkWithoutBaselineSource.components(
                separatedBy: "waitForExistence(timeout: 55)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkWithoutBaselineSource.components(
                separatedBy: "waitForExistence(timeout: 20)"
            ).count - 1,
            2
        )
        for staleRecordWorkTimeout in [
            "waitForExistence(timeout: 35)",
            "waitForExistence(timeout: 45)",
            "waitForExistence(timeout: 50)",
            "waitForExistence(timeout: 60)",
        ] {
            XCTAssertEqual(
                recordWorkWithoutBaselineSource.components(
                    separatedBy: staleRecordWorkTimeout
                ).count - 1,
                0,
                staleRecordWorkTimeout
            )
        }
        for prohibitedRecordWorkWaitMutation in [
            "Thread.sleep",
            "Task.sleep",
            "performAccessibilityAudit",
            "captureBaseline(",
            "printJSONLine(",
            "while ",
            "for _ in",
        ] {
            XCTAssertFalse(
                recordWorkWithoutBaselineSource.contains(
                    prohibitedRecordWorkWaitMutation
                ),
                prohibitedRecordWorkWaitMutation
            )
        }
        let pseudolanguageClassifierStart = try XCTUnwrap(
            uiSource.range(of: "    private var usesPseudolanguage: Bool {")
        )
        let pseudolanguageClassifierEnd = try XCTUnwrap(
            uiSource.range(
                of: "\n\n    @MainActor\n    private func assertUnidentifiedLocalizedLabel(",
                range: pseudolanguageClassifierStart.upperBound..<uiSource.endIndex
            )
        )
        let pseudolanguageClassifierSource = String(
            uiSource[pseudolanguageClassifierStart.lowerBound..<pseudolanguageClassifierEnd.lowerBound]
        )
        let exactPseudolanguageClassifier =
            "    private var usesPseudolanguage: Bool {\n" +
                "        guard let shard = automationShard else { return false }\n" +
                "        return [\n" +
                "            \"en-US-double-length\",\n" +
                "            \"ar-RTL-string\",\n" +
                "            \"en-US-tall\",\n" +
                "            \"en-US-accented\",\n" +
                "            \"en-US-bounded\",\n" +
                "        ].contains(shard.locale)\n" +
                "    }"
        XCTAssertEqual(pseudolanguageClassifierSource, exactPseudolanguageClassifier)
        XCTAssertEqual(
            uiSource.components(separatedBy: "usesPseudolanguage").count - 1,
            13
        )
        for transformingLocale in [
            "en-US-double-length",
            "ar-RTL-string",
            "en-US-tall",
            "en-US-accented",
            "en-US-bounded",
        ] {
            XCTAssertEqual(
                pseudolanguageClassifierSource.components(
                    separatedBy: "\"\(transformingLocale)\""
                ).count - 1,
                1,
                transformingLocale
            )
        }
        for nontransformingLocale in ["en-US-release", "ar-RTL"] {
            XCTAssertEqual(
                pseudolanguageClassifierSource.components(
                    separatedBy: "\"\(nontransformingLocale)\""
                ).count - 1,
                0,
                nontransformingLocale
            )
            XCTAssertNotEqual(
                pseudolanguageClassifierSource,
                exactPseudolanguageClassifier.replacingOccurrences(
                    of: "        ].contains(shard.locale)",
                    with: "            \"\(nontransformingLocale)\",\n" +
                        "        ].contains(shard.locale)"
                ),
                "A non-transforming locale must not be added"
            )
        }
        for transformingLocale in [
            "en-US-double-length",
            "ar-RTL-string",
            "en-US-tall",
            "en-US-accented",
            "en-US-bounded",
        ] {
            XCTAssertNotEqual(
                pseudolanguageClassifierSource,
                exactPseudolanguageClassifier.replacingOccurrences(
                    of: "            \"\(transformingLocale)\",\n",
                    with: ""
                ),
                "A string-transforming locale must not be omitted"
            )
        }
        for staleOrInferredClassifier in [
            "shard.locale != \"en-US-release\"",
            "shard.locale == \"ar-RTL\"",
            "shard.locale.hasPrefix",
            "shard.locale.hasSuffix",
            "shard.locale.contains",
            "shard.layoutDirection",
            "shard.shardID",
            "shard.requirementID",
            "shard.accessibilityFeature",
        ] {
            XCTAssertFalse(
                pseudolanguageClassifierSource.contains(staleOrInferredClassifier),
                staleOrInferredClassifier
            )
        }
        let unidentifiedLabelStart = pseudolanguageClassifierEnd.upperBound
        let unidentifiedLabelEnd = try XCTUnwrap(
            uiSource.range(
                of: "\n\n    @MainActor\n    private func assertLocalizedLabel(",
                range: unidentifiedLabelStart..<uiSource.endIndex
            )
        )
        let unidentifiedLabelSource = String(
            uiSource[unidentifiedLabelStart..<unidentifiedLabelEnd.lowerBound]
        )
        let exactLabelQuery =
            "labelledElement(releaseLabel, in: app).waitForExistence(timeout: timeout)"
        XCTAssertEqual(
            unidentifiedLabelSource.components(separatedBy: "guard usesPseudolanguage else {").count - 1,
            1
        )
        XCTAssertEqual(
            unidentifiedLabelSource.components(separatedBy: exactLabelQuery).count - 1,
            1
        )
        XCTAssertEqual(
            unidentifiedLabelSource.components(
                separatedBy: "pseudoLabelSentinelValidated"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            unidentifiedLabelSource.components(
                separatedBy: "app.descendants(matching: .any).allElementsBoundByIndex.contains"
            ).count - 1,
            1
        )
        XCTAssertLessThan(
            try XCTUnwrap(unidentifiedLabelSource.range(of: exactLabelQuery)).lowerBound,
            try XCTUnwrap(unidentifiedLabelSource.range(of: "            return")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(unidentifiedLabelSource.range(of: "pseudoLabelSentinelValidated")).lowerBound,
            try XCTUnwrap(
                unidentifiedLabelSource.range(
                    of: "app.descendants(matching: .any).allElementsBoundByIndex.contains"
                )
            ).lowerBound
        )
        let realRTLShard =
            "locale: \"ar-RTL\", layoutDirection: \"right_to_left\""
        let stringRTLShard =
            "locale: \"ar-RTL-string\", layoutDirection: \"right_to_left\""
        XCTAssertEqual(uiSource.components(separatedBy: realRTLShard).count - 1, 1)
        XCTAssertEqual(uiSource.components(separatedBy: stringRTLShard).count - 1, 1)
        let minimumKeyboardNonthrowingCall =
            "        assertLightFirstSignValidationAndCreation(in: app)"
        let minimumKeyboardNonthrowingSignature =
            "    private func assertLightFirstSignValidationAndCreation(\n" +
                "        in app: XCUIApplication\n" +
                "    ) {"
        for nonthrowingMinimumKeyboardLock in [
            minimumKeyboardNonthrowingCall,
            minimumKeyboardNonthrowingSignature,
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: nonthrowingMinimumKeyboardLock
                ).count - 1,
                1,
                nonthrowingMinimumKeyboardLock
            )
        }
        for removedThrowingMinimumKeyboardLock in [
            "        try assertLightFirstSignValidationAndCreation(in: app)",
            "    private func assertLightFirstSignValidationAndCreation(\n" +
                "        in app: XCUIApplication\n" +
                "    ) throws {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedThrowingMinimumKeyboardLock
                ).count - 1,
                0,
                removedThrowingMinimumKeyboardLock
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
        let currentProfilePreflightQuickPathGate =
            "        if automationShard?.deviceProfileID\n" +
                #"            == "iphone-17-ios-26.2-current" {"#
        XCTAssertEqual(
            preflightQuickPathSource.components(separatedBy: preflightMinimumGate).count - 1,
            1
        )
        XCTAssertEqual(
            preflightQuickPathSource.components(
                separatedBy: currentProfilePreflightQuickPathGate
            ).count - 1,
            1
        )
        guard let preflightMinimumStartRange = preflightQuickPathSource.range(
            of: preflightMinimumGate
        ), let currentProfilePreflightQuickPathStartRange =
            preflightQuickPathSource.range(
                of: currentProfilePreflightQuickPathGate,
                range:
                    preflightMinimumStartRange.upperBound..<preflightQuickPathSource.endIndex
            )
        else {
            XCTFail("Missing the isolated minimum/current preflight source slices")
            return
        }
        let preflightMinimumSource = String(
            preflightQuickPathSource[
                preflightMinimumStartRange.lowerBound ..<
                    currentProfilePreflightQuickPathStartRange.lowerBound
            ]
        )
        let currentProfilePreflightQuickPathSource = String(
            preflightQuickPathSource[
                currentProfilePreflightQuickPathStartRange.lowerBound ..<
                    preflightQuickPathSource.endIndex
            ]
        )
        XCTAssertEqual(preflightMinimumSource.utf8.count, 53_955)
        XCTAssertEqual(
            Data(preflightMinimumSource.utf8).sha256,
            "DCFFA6B9674317E774FBF4EDD1661426FD397297FC6226B578CB9FDD93B034D2"
        )
        XCTAssertEqual(currentProfilePreflightQuickPathSource.utf8.count, 29_876)
        XCTAssertEqual(
            Data(currentProfilePreflightQuickPathSource.utf8).sha256,
            "0F0B1CEB5A80D8DA541B032DE0716317B48739B7D599715AE091AFF00BC30FA7"
        )

        let preflightZoneScroll = "        scroll(zone, in: app)"
        XCTAssertEqual(
            uiSource.components(separatedBy: preflightZoneScroll).count - 1,
            1
        )
        guard let preflightZoneScrollRange = uiSource.range(
            of: preflightZoneScroll,
            range: preflightQuickPathCaptureRange.upperBound..<uiSource.endIndex
        ), let preflightBeginRange = uiSource.range(
            of: #"        let begin = element("s3.preflight.begin", in: app)"#,
            range: preflightZoneScrollRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the unchanged post-capture Preflight input slices")
            return
        }
        let preflightCaptureToZoneScrollSource = String(
            uiSource[
                preflightQuickPathCaptureRange.lowerBound ..<
                    preflightZoneScrollRange.lowerBound
            ]
        )
        let preflightZoneScrollToBeginSource = String(
            uiSource[
                preflightZoneScrollRange.lowerBound..<preflightBeginRange.lowerBound
            ]
        )
        XCTAssertEqual(preflightCaptureToZoneScrollSource.utf8.count, 65)
        XCTAssertEqual(
            Data(preflightCaptureToZoneScrollSource.utf8).sha256,
            "B78B48127DD3FCFA516B8CB01366643048DB212368A68EBF0809E5CEB84D17D8"
        )
        XCTAssertEqual(preflightZoneScrollToBeginSource.utf8.count, 666)
        XCTAssertEqual(
            Data(preflightZoneScrollToBeginSource.utf8).sha256,
            "FB7652BD31787249CBDEA44A82E50DCDE201E155A5BAEBE339942B659836D3BD"
        )

        let currentProfilePreflightQuickPathStructureLocks = [
            "let currentPreflightQuickPathIntroductionViews =",
            "app.descendants(matching: .other).matching(",
            #"identifier: "UIContinuousPathIntroductionView""#,
            "let currentPreflightQuickPathIntroductionCount =",
            "if currentPreflightQuickPathIntroductionCount > 0 {",
            "let currentPreflightQuickPathIntroductionView =",
            "currentPreflightQuickPathIntroductionView.descendants(",
            "matching: .button",
            "matching: .staticText",
            "let currentPreflightQuickPathButton =",
            "let currentPreflightQuickPathFirstStaticText =",
            "let currentPreflightQuickPathSecondStaticText =",
            "let currentPreflightQuickPathPreflightScreens =",
            #"identifier: "s3.preflight.screen""#,
            "let currentPreflightQuickPathScrollViews =",
            "app.scrollViews.containing(",
            "let currentPreflightQuickPathZoneFields =",
            "app.textFields.matching(",
            #"identifier: "s3.preflight.time-zone""#,
            "let currentPreflightQuickPathSignDetailScreens =",
            #"identifier: "s2.sign-detail.screen""#,
            "let currentPreflightQuickPathKeyboards = app.keyboards",
            "currentPreflightQuickPathKeyboard.buttons.matching(",
            #"identifier: "Done""#,
            "let currentPreflightQuickPathConfirmationSwitches =",
            #"identifier: "s3.preflight.time-zone-confirmed""#,
            "let currentPreflightQuickPathAfterDarkSwitches =",
            #"identifier: "s3.preflight.after-dark""#,
            "let currentPreflightQuickPathSafePositionSwitches =",
            #"identifier: "s3.preflight.safe-position""#,
            "let currentPreflightQuickPathFrameIsValid:",
            "(CGRect) -> Bool = { frame in",
            "!frame.isNull",
            "&& !frame.isEmpty",
            "&& !frame.isInfinite",
            "&& frame.origin.x.isFinite",
            "&& frame.origin.y.isFinite",
            "&& frame.size.width.isFinite",
            "&& frame.size.height.isFinite",
            "let currentPreflightQuickPathZoneFocus = NSPredicate(",
            #"format: "hasKeyboardFocus == true""#,
            "currentPreflightQuickPathButton.identifier.isEmpty",
            "currentPreflightQuickPathFirstStaticText.identifier",
            "currentPreflightQuickPathSecondStaticText.identifier",
            "currentPreflightQuickPathButton.label",
            "currentPreflightQuickPathFirstStaticText.label",
            "currentPreflightQuickPathSecondStaticText.label",
            "currentPreflightQuickPathZoneField.placeholderValue?",
            "currentPreflightQuickPathDoneKey.label.lowercased()",
            "currentPreflightQuickPathButton.tap()",
            ".waitForNonExistence(timeout: 10)",
        ]
        for lock in currentProfilePreflightQuickPathStructureLocks {
            XCTAssertTrue(
                currentProfilePreflightQuickPathSource.contains(lock),
                lock
            )
        }

        let currentProfilePreflightQuickPathQueryCountLocks: [(String, Int)] = [
            ("currentPreflightQuickPathIntroductionViews.count", 2),
            ("currentPreflightQuickPathButtons.count", 2),
            ("currentPreflightQuickPathStaticTexts.count", 2),
            ("currentPreflightQuickPathPreflightScreens.count", 2),
            ("currentPreflightQuickPathScrollViews.count", 2),
            ("currentPreflightQuickPathZoneFields.count", 2),
            ("currentPreflightQuickPathSignDetailScreens.count", 2),
            ("currentPreflightQuickPathKeyboards.count", 2),
            ("currentPreflightQuickPathDoneKeys.count", 2),
            ("currentPreflightQuickPathConfirmationSwitches.count", 2),
            ("currentPreflightQuickPathAfterDarkSwitches.count", 2),
            ("currentPreflightQuickPathSafePositionSwitches.count", 2),
        ]
        for (lock, count) in currentProfilePreflightQuickPathQueryCountLocks {
            XCTAssertEqual(
                currentProfilePreflightQuickPathSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }
        let currentProfilePreflightQuickPathExactBindings = [
            "let currentPreflightQuickPathIntroductionViews =",
            "let currentPreflightQuickPathIntroductionCount =",
            "let currentPreflightQuickPathIntroductionView =",
            "let currentPreflightQuickPathButtons =",
            "let currentPreflightQuickPathStaticTexts =",
            "let currentPreflightQuickPathButton =",
            "let currentPreflightQuickPathFirstStaticText =",
            "let currentPreflightQuickPathSecondStaticText =",
            "let currentPreflightQuickPathPreflightScreens =",
            "let currentPreflightQuickPathScrollViews =",
            "let currentPreflightQuickPathZoneFields =",
            "let currentPreflightQuickPathSignDetailScreens =",
            "let currentPreflightQuickPathKeyboards = app.keyboards",
            "let currentPreflightQuickPathPreflightScreen =",
            "let currentPreflightQuickPathScrollView =",
            "let currentPreflightQuickPathZoneField =",
            "let currentPreflightQuickPathKeyboard =",
            "let currentPreflightQuickPathDoneKeys =",
            "let currentPreflightQuickPathDoneKey =",
            "let currentPreflightQuickPathConfirmationSwitches =",
            "let currentPreflightQuickPathAfterDarkSwitches =",
            "let currentPreflightQuickPathSafePositionSwitches =",
            "let currentPreflightQuickPathConfirmationSwitch =",
            "let currentPreflightQuickPathAfterDarkSwitch =",
            "let currentPreflightQuickPathSafePositionSwitch =",
        ]
        for binding in currentProfilePreflightQuickPathExactBindings {
            XCTAssertEqual(
                currentProfilePreflightQuickPathSource.components(
                    separatedBy: binding
                ).count - 1,
                1,
                binding
            )
        }
        for (lock, count) in [
            (".firstMatch", 10),
            ("element(boundBy:", 2),
            ("currentPreflightQuickPathFrameIsValid", 14),
            (".contains(", 12),
            (".intersects(", 4),
            ("currentPreflightQuickPathZoneFocus", 4),
            ("expectedCurrentPreflightQuickPathZoneHasFocus", 2),
            ("currentPreflightQuickPathButton.tap()", 1),
            (".tap()", 1),
            ("waitForNonExistence(", 1),
            ("timeout: 10", 1),
            ("XCTFail(", 2),
            ("\n                    return\n", 2),
        ] {
            XCTAssertEqual(
                currentProfilePreflightQuickPathSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }

        let currentProfilePreActionGuard =
            "                guard currentPreflightQuickPathIntroductionCount == 1,"
        let currentProfileFirstElementProperty =
            "                      currentPreflightQuickPathIntroductionView.exists,"
        guard let currentProfilePreActionGuardRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfilePreActionGuard
            ), let currentProfileFirstElementPropertyRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileFirstElementProperty,
                range:
                    currentProfilePreActionGuardRange.upperBound ..<
                        currentProfilePreflightQuickPathSource.endIndex
            ) else {
            XCTFail("Missing the ordered current-profile Preflight pre-action guard")
            return
        }
        let currentProfilePreActionCardinalitySource = String(
            currentProfilePreflightQuickPathSource[
                currentProfilePreActionGuardRange.lowerBound ..<
                    currentProfileFirstElementPropertyRange.lowerBound
            ]
        )
        for cardinality in [
            "currentPreflightQuickPathIntroductionCount == 1",
            "currentPreflightQuickPathButtons.count == 1",
            "currentPreflightQuickPathStaticTexts.count == 2",
            "currentPreflightQuickPathPreflightScreens.count == 1",
            "currentPreflightQuickPathScrollViews.count == 1",
            "currentPreflightQuickPathZoneFields.count == 1",
            "currentPreflightQuickPathSignDetailScreens.count == 0",
            "currentPreflightQuickPathKeyboards.count == 1",
            "currentPreflightQuickPathDoneKeys.count == 1",
            "currentPreflightQuickPathConfirmationSwitches.count\n" +
                "                        == 1",
            "currentPreflightQuickPathAfterDarkSwitches.count == 1",
            "currentPreflightQuickPathSafePositionSwitches.count\n" +
                "                        == 1",
        ] {
            XCTAssertEqual(
                currentProfilePreActionCardinalitySource.components(
                    separatedBy: cardinality
                ).count - 1,
                1,
                cardinality
            )
        }
        for prematureElementRead in [
            ".exists",
            ".elementType",
            ".identifier",
            ".label",
            ".value",
            ".placeholderValue",
            ".frame",
            ".isEnabled",
            ".isHittable",
            ".evaluate(",
        ] {
            XCTAssertFalse(
                currentProfilePreActionCardinalitySource.contains(
                    prematureElementRead
                ),
                prematureElementRead
            )
        }

        let currentProfilePreflightQuickPathGeometryLocks = [
            "app.frame.contains(\n" +
                "                          currentPreflightQuickPathPreflightScreen.frame",
            "app.frame.contains(\n" +
                "                          currentPreflightQuickPathScrollView.frame",
            "app.frame.contains(\n" +
                "                          currentPreflightQuickPathZoneField.frame",
            "app.frame.contains(\n" +
                "                          currentPreflightQuickPathKeyboard.frame",
            "app.frame.contains(\n" +
                "                          currentPreflightQuickPathIntroductionView.frame",
            "currentPreflightQuickPathPreflightScreen.frame.contains(\n" +
                "                          currentPreflightQuickPathZoneField.frame",
            "currentPreflightQuickPathScrollView.frame.contains(\n" +
                "                          currentPreflightQuickPathZoneField.frame",
            "currentPreflightQuickPathKeyboard.frame.contains(\n" +
                "                          currentPreflightQuickPathDoneKey.frame",
            "currentPreflightQuickPathIntroductionView.frame.contains(\n" +
                "                          currentPreflightQuickPathButton.frame",
            "currentPreflightQuickPathIntroductionView.frame.contains(\n" +
                "                          currentPreflightQuickPathFirstStaticText.frame",
            "currentPreflightQuickPathIntroductionView.frame.contains(\n" +
                "                          currentPreflightQuickPathSecondStaticText.frame",
            "currentPreflightQuickPathIntroductionView.frame.contains(\n" +
                "                          currentPreflightQuickPathDoneKey.frame",
            "currentPreflightQuickPathIntroductionView.frame\n" +
                "                        .intersects(\n" +
                "                            currentPreflightQuickPathKeyboard.frame",
            "(currentPreflightQuickPathFirstStaticText.label\n" +
                "                        == currentPreflightQuickPathButton.label)\n" +
                "                        != (currentPreflightQuickPathSecondStaticText.label",
            "currentPreflightQuickPathFirstStaticText.frame\n" +
                "                        .intersects(\n" +
                "                            currentPreflightQuickPathButton.frame\n" +
                "                        )\n" +
                "                        == (currentPreflightQuickPathFirstStaticText.label",
            "currentPreflightQuickPathSecondStaticText.frame\n" +
                "                        .intersects(\n" +
                "                            currentPreflightQuickPathButton.frame\n" +
                "                        )\n" +
                "                        == (currentPreflightQuickPathSecondStaticText.label",
            "!currentPreflightQuickPathFirstStaticText.frame\n" +
                "                        .intersects(\n" +
                "                            currentPreflightQuickPathSecondStaticText.frame",
        ]
        for lock in currentProfilePreflightQuickPathGeometryLocks {
            XCTAssertEqual(
                currentProfilePreflightQuickPathSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }

        let currentProfileFirstFrameValidation =
            "currentPreflightQuickPathFrameIsValid(app.frame),"
        let currentProfileLastFrameValidation =
            "currentPreflightQuickPathFrameIsValid(\n" +
                "                          currentPreflightQuickPathSafePositionSwitch.frame\n" +
                "                      ),"
        let currentProfileFirstDynamicRoleProof =
            "(currentPreflightQuickPathFirstStaticText.label\n" +
                "                        == currentPreflightQuickPathButton.label)\n" +
                "                        != (currentPreflightQuickPathSecondStaticText.label"
        guard let currentProfileFirstFrameValidationRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileFirstFrameValidation
            ), let currentProfileLastFrameValidationRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileLastFrameValidation,
                range:
                    currentProfileFirstFrameValidationRange.upperBound ..<
                        currentProfilePreflightQuickPathSource.endIndex
            ), let currentProfileFirstDynamicRoleProofRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileFirstDynamicRoleProof,
                range:
                    currentProfileLastFrameValidationRange.upperBound ..<
                        currentProfilePreflightQuickPathSource.endIndex
            ) else {
            XCTFail("Missing current-profile frame-before-geometry ordering")
            return
        }
        XCTAssertLessThan(
            currentProfileFirstElementPropertyRange.lowerBound,
            currentProfileFirstFrameValidationRange.lowerBound
        )
        XCTAssertLessThan(
            currentProfileFirstFrameValidationRange.lowerBound,
            currentProfileLastFrameValidationRange.lowerBound
        )
        XCTAssertLessThan(
            currentProfileLastFrameValidationRange.lowerBound,
            currentProfileFirstDynamicRoleProofRange.lowerBound
        )

        let currentProfileTutorialTopRole =
            "currentPreflightQuickPathFirstStaticText.label\n" +
                "                            == currentPreflightQuickPathButton.label\n" +
                "                              ? currentPreflightQuickPathSecondStaticText\n" +
                "                                  .frame.maxY\n" +
                "                              : currentPreflightQuickPathFirstStaticText\n" +
                "                                  .frame.maxY"
        XCTAssertEqual(
            currentProfilePreflightQuickPathSource.components(
                separatedBy: currentProfileTutorialTopRole
            ).count - 1,
            2
        )
        let currentProfileActionTopRole =
            "currentPreflightQuickPathFirstStaticText.label\n" +
                "                            == currentPreflightQuickPathButton.label\n" +
                "                              ? currentPreflightQuickPathFirstStaticText\n" +
                "                                  .frame.minY\n" +
                "                              : currentPreflightQuickPathSecondStaticText\n" +
                "                                  .frame.minY"
        XCTAssertEqual(
            currentProfilePreflightQuickPathSource.components(
                separatedBy: currentProfileActionTopRole
            ).count - 1,
            1
        )
        XCTAssertEqual(
            currentProfilePreflightQuickPathSource.components(
                separatedBy:
                    ") <= currentPreflightQuickPathButton.frame.minY,"
            ).count - 1,
            1
        )

        let currentProfileExpectedSnapshotNames = [
            "expectedCurrentPreflightQuickPathApplicationFrame",
            "expectedCurrentPreflightQuickPathPreflightFrame",
            "expectedCurrentPreflightQuickPathScrollFrame",
            "expectedCurrentPreflightQuickPathZoneFrame",
            "expectedCurrentPreflightQuickPathKeyboardFrame",
            "expectedCurrentPreflightQuickPathDoneFrame",
            "expectedCurrentPreflightQuickPathZoneLabel",
            "expectedCurrentPreflightQuickPathZoneValue",
            "expectedCurrentPreflightQuickPathZonePlaceholder",
            "expectedCurrentPreflightQuickPathZoneHasFocus",
            "expectedCurrentPreflightQuickPathDoneLabel",
            "expectedCurrentPreflightQuickPathConfirmationLabel",
            "expectedCurrentPreflightQuickPathConfirmationValue",
            "expectedCurrentPreflightQuickPathConfirmationEnabled",
            "expectedCurrentPreflightQuickPathConfirmationHittable",
            "expectedCurrentPreflightQuickPathConfirmationFrame",
            "expectedCurrentPreflightQuickPathAfterDarkLabel",
            "expectedCurrentPreflightQuickPathAfterDarkValue",
            "expectedCurrentPreflightQuickPathAfterDarkEnabled",
            "expectedCurrentPreflightQuickPathAfterDarkHittable",
            "expectedCurrentPreflightQuickPathAfterDarkFrame",
            "expectedCurrentPreflightQuickPathSafePositionLabel",
            "expectedCurrentPreflightQuickPathSafePositionValue",
            "expectedCurrentPreflightQuickPathSafePositionEnabled",
            "expectedCurrentPreflightQuickPathSafePositionHittable",
            "expectedCurrentPreflightQuickPathSafePositionFrame",
        ]
        for snapshotName in currentProfileExpectedSnapshotNames {
            XCTAssertEqual(
                currentProfilePreflightQuickPathSource.components(
                    separatedBy: snapshotName
                ).count - 1,
                2,
                snapshotName
            )
        }

        let currentProfilePreActionFailure =
            "                    XCTFail(\n" +
                "                        \"The current-profile preflight QuickPath tutorial is incomplete or state changed before dismissal.\"\n" +
                "                    )\n" +
                "                    return\n" +
                "                }"
        let currentProfileRestorationFailure =
            "                    XCTFail(\n" +
                "                        \"The current-profile preflight QuickPath tutorial did not dismiss with state preserved.\"\n" +
                "                    )\n" +
                "                    return\n" +
                "                }"
        let currentProfileFirstSnapshot =
            "                let expectedCurrentPreflightQuickPathApplicationFrame ="
        let currentProfileQuickPathAction =
            "                currentPreflightQuickPathButton.tap()"
        let currentProfileQuickPathWait =
            "currentPreflightQuickPathIntroductionView\n" +
                "                        .waitForNonExistence(timeout: 10)"
        guard let currentProfilePreActionFailureRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfilePreActionFailure
            ), let currentProfileFirstSnapshotRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileFirstSnapshot
            ), let currentProfileQuickPathActionRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileQuickPathAction
            ), let currentProfileQuickPathWaitRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileQuickPathWait
            ), let currentProfileRestorationFailureRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileRestorationFailure
            ) else {
            XCTFail("Missing the ordered current-profile Preflight action/restoration")
            return
        }
        XCTAssertLessThan(
            currentProfilePreActionFailureRange.lowerBound,
            currentProfileFirstSnapshotRange.lowerBound
        )
        XCTAssertLessThan(
            currentProfileFirstSnapshotRange.lowerBound,
            currentProfileQuickPathActionRange.lowerBound
        )
        XCTAssertLessThan(
            currentProfileQuickPathActionRange.lowerBound,
            currentProfileQuickPathWaitRange.lowerBound
        )
        XCTAssertLessThan(
            currentProfileQuickPathWaitRange.lowerBound,
            currentProfileRestorationFailureRange.lowerBound
        )
        let currentProfilePreActionSemanticSource = String(
            currentProfilePreflightQuickPathSource[
                currentProfilePreActionGuardRange.lowerBound ..<
                    currentProfilePreActionFailureRange.upperBound
            ]
        )
        for preActionLock in [
            "currentPreflightQuickPathIntroductionView.elementType",
            #"== "UIContinuousPathIntroductionView""#,
            "currentPreflightQuickPathButton.elementType == .button",
            "currentPreflightQuickPathButton.identifier.isEmpty",
            "currentPreflightQuickPathButton.isEnabled",
            "currentPreflightQuickPathButton.isHittable",
            "currentPreflightQuickPathFirstStaticText.elementType",
            "currentPreflightQuickPathFirstStaticText.identifier",
            "currentPreflightQuickPathSecondStaticText.elementType",
            "currentPreflightQuickPathSecondStaticText.identifier",
            "currentPreflightQuickPathPreflightScreen.elementType",
            #"== "s3.preflight.screen""#,
            "currentPreflightQuickPathScrollView.elementType",
            "currentPreflightQuickPathZoneField.elementType",
            #"== "s3.preflight.time-zone""#,
            "currentPreflightQuickPathZoneField.placeholderValue?",
            "currentPreflightQuickPathZoneFocus.evaluate(",
            "currentPreflightQuickPathKeyboard.elementType",
            "currentPreflightQuickPathDoneKey.elementType == .button",
            #"currentPreflightQuickPathDoneKey.identifier == "Done""#,
            "currentPreflightQuickPathDoneKey.label.lowercased()",
            "currentPreflightQuickPathDoneKey.isEnabled",
            "!currentPreflightQuickPathDoneKey.isHittable",
            "currentPreflightQuickPathConfirmationSwitch.elementType",
            #"== "s3.preflight.time-zone-confirmed""#,
            "currentPreflightQuickPathAfterDarkSwitch.elementType",
            #"== "s3.preflight.after-dark""#,
            "currentPreflightQuickPathSafePositionSwitch.elementType",
            #"== "s3.preflight.safe-position""#,
            "app.state == .runningForeground else {",
        ] {
            XCTAssertTrue(
                currentProfilePreActionSemanticSource.contains(preActionLock),
                preActionLock
            )
        }

        let currentProfileRestorationSource = String(
            currentProfilePreflightQuickPathSource[
                currentProfileQuickPathActionRange.lowerBound ..<
                    currentProfileRestorationFailureRange.upperBound
            ]
        )
        let currentProfilePostWaitCardinalityStart =
            "currentPreflightQuickPathIntroductionViews.count == 0"
        let currentProfileFirstRestoredProperty =
            "currentPreflightQuickPathPreflightScreen.exists"
        guard let currentProfilePostWaitCardinalityStartRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfilePostWaitCardinalityStart,
                range:
                    currentProfileQuickPathWaitRange.upperBound ..<
                        currentProfileRestorationFailureRange.lowerBound
            ), let currentProfileFirstRestoredPropertyRange =
            currentProfilePreflightQuickPathSource.range(
                of: currentProfileFirstRestoredProperty,
                range:
                    currentProfilePostWaitCardinalityStartRange.upperBound ..<
                        currentProfileRestorationFailureRange.lowerBound
            ) else {
            XCTFail("Missing the ordered current-profile post-wait cardinalities")
            return
        }
        let currentProfilePostWaitCardinalitySource = String(
            currentProfilePreflightQuickPathSource[
                currentProfilePostWaitCardinalityStartRange.lowerBound ..<
                    currentProfileFirstRestoredPropertyRange.lowerBound
            ]
        )
        let currentProfilePostWaitCardinalities = [
            "currentPreflightQuickPathIntroductionViews.count == 0",
            "currentPreflightQuickPathButtons.count == 0",
            "currentPreflightQuickPathStaticTexts.count == 0",
            "currentPreflightQuickPathPreflightScreens.count == 1",
            "currentPreflightQuickPathScrollViews.count == 1",
            "currentPreflightQuickPathZoneFields.count == 1",
            "currentPreflightQuickPathSignDetailScreens.count == 0",
            "currentPreflightQuickPathKeyboards.count == 1",
            "currentPreflightQuickPathDoneKeys.count == 1",
            "currentPreflightQuickPathConfirmationSwitches.count\n" +
                "                        == 1",
            "currentPreflightQuickPathAfterDarkSwitches.count == 1",
            "currentPreflightQuickPathSafePositionSwitches.count\n" +
                "                        == 1",
        ]
        XCTAssertEqual(currentProfilePostWaitCardinalities.count, 12)
        for restoredCardinality in currentProfilePostWaitCardinalities {
            XCTAssertEqual(
                currentProfilePostWaitCardinalitySource.components(
                    separatedBy: restoredCardinality
                ).count - 1,
                1,
                restoredCardinality
            )
        }
        for prematureRestoredPropertyRead in [
            ".exists",
            ".elementType",
            ".identifier",
            ".label",
            ".value",
            ".placeholderValue",
            ".frame",
            ".isEnabled",
            ".isHittable",
            ".evaluate(",
        ] {
            XCTAssertFalse(
                currentProfilePostWaitCardinalitySource.contains(
                    prematureRestoredPropertyRead
                ),
                prematureRestoredPropertyRead
            )
        }
        for restoredProperty in [
            "currentPreflightQuickPathPreflightScreen.exists",
            "currentPreflightQuickPathPreflightScreen.elementType",
            "currentPreflightQuickPathScrollView.exists",
            "currentPreflightQuickPathScrollView.elementType",
            "currentPreflightQuickPathZoneField.exists",
            "currentPreflightQuickPathZoneField.elementType",
            "currentPreflightQuickPathZoneFocus.evaluate(",
            "currentPreflightQuickPathKeyboard.exists",
            "currentPreflightQuickPathKeyboard.elementType",
            "currentPreflightQuickPathDoneKey.exists",
            "currentPreflightQuickPathDoneKey.elementType == .button",
            #"currentPreflightQuickPathDoneKey.identifier == "Done""#,
            "currentPreflightQuickPathDoneKey.label.lowercased()",
            "currentPreflightQuickPathDoneKey.isEnabled",
            "currentPreflightQuickPathDoneKey.isHittable",
            "currentPreflightQuickPathConfirmationSwitch.exists",
            "currentPreflightQuickPathConfirmationSwitch.elementType",
            "currentPreflightQuickPathAfterDarkSwitch.exists",
            "currentPreflightQuickPathAfterDarkSwitch.elementType",
            "currentPreflightQuickPathSafePositionSwitch.exists",
            "currentPreflightQuickPathSafePositionSwitch.elementType",
            "app.state == .runningForeground else {",
        ] {
            XCTAssertTrue(
                currentProfileRestorationSource.contains(restoredProperty),
                restoredProperty
            )
        }
        for snapshotName in currentProfileExpectedSnapshotNames {
            XCTAssertTrue(
                currentProfileRestorationSource.contains(snapshotName),
                snapshotName
            )
        }
        let currentProfileBeforePreActionGuard = String(
            currentProfilePreflightQuickPathSource[
                currentProfilePreflightQuickPathSource.startIndex ..<
                    currentProfilePreActionGuardRange.lowerBound
            ]
        )
        XCTAssertFalse(
            currentProfileBeforePreActionGuard.contains(
                "expectedCurrentPreflightQuickPath"
            )
        )

        let currentProfileRestorationBeforeCapture =
            currentProfileRestorationFailure +
                "\n            }\n        }\n" +
                preflightQuickPathCapture
        XCTAssertEqual(
            uiSource.components(
                separatedBy: currentProfileRestorationBeforeCapture
            ).count - 1,
            1
        )

        for fixedSwitchState in [
            "currentPreflightQuickPathConfirmationSwitch.isEnabled == true",
            "currentPreflightQuickPathConfirmationSwitch.isEnabled == false",
            "currentPreflightQuickPathConfirmationSwitch.isHittable == true",
            "currentPreflightQuickPathConfirmationSwitch.isHittable == false",
            "currentPreflightQuickPathAfterDarkSwitch.isEnabled == true",
            "currentPreflightQuickPathAfterDarkSwitch.isEnabled == false",
            "currentPreflightQuickPathAfterDarkSwitch.isHittable == true",
            "currentPreflightQuickPathAfterDarkSwitch.isHittable == false",
            "currentPreflightQuickPathSafePositionSwitch.isEnabled == true",
            "currentPreflightQuickPathSafePositionSwitch.isEnabled == false",
            "currentPreflightQuickPathSafePositionSwitch.isHittable == true",
            "currentPreflightQuickPathSafePositionSwitch.isHittable == false",
            "                      currentPreflightQuickPathConfirmationSwitch.isEnabled,",
            "                      !currentPreflightQuickPathConfirmationSwitch.isEnabled,",
            "                      currentPreflightQuickPathConfirmationSwitch.isHittable,",
            "                      !currentPreflightQuickPathConfirmationSwitch.isHittable,",
            "                      currentPreflightQuickPathAfterDarkSwitch.isEnabled,",
            "                      !currentPreflightQuickPathAfterDarkSwitch.isEnabled,",
            "                      currentPreflightQuickPathAfterDarkSwitch.isHittable,",
            "                      !currentPreflightQuickPathAfterDarkSwitch.isHittable,",
            "                      currentPreflightQuickPathSafePositionSwitch.isEnabled,",
            "                      !currentPreflightQuickPathSafePositionSwitch.isEnabled,",
            "                      currentPreflightQuickPathSafePositionSwitch.isHittable,",
            "                      !currentPreflightQuickPathSafePositionSwitch.isHittable,",
            #"== "0""#,
            #"== "1""#,
        ] {
            XCTAssertFalse(
                currentProfilePreflightQuickPathSource.contains(fixedSwitchState),
                fixedSwitchState
            )
        }
        for prohibitedCurrentProfileQuickPathForm in [
            "Speed up your typing",
            "Continue",
            "app.staticTexts",
            "app.buttons",
            #"format: "label == %@""#,
            #"format: "label CONTAINS""#,
            #"format: "label BEGINSWITH""#,
            "private func",
            "return false",
            "return true",
            "iphone-se-3-ios-18.0-minimum",
            "automationShard?.shardID",
            "automationShard?.locale",
            "CGRect(",
            ".coordinate(",
            ".press(",
            ".swipe",
            "scroll(",
            "typeText(",
            "dismissKeyboard(",
            "currentPreflightQuickPathDoneKey.tap()",
            "setToggle(",
            "waitForExistence(",
            "Thread.sleep",
            "Task.sleep",
            "sleep(",
            "for _ in",
            "while ",
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
                currentProfilePreflightQuickPathSource.contains(
                    prohibitedCurrentProfileQuickPathForm
                ),
                prohibitedCurrentProfileQuickPathForm
            )
        }
        for (preflightNavigationBinding, count) in [
            ("let preflightNavigationBars = app.navigationBars", 1),
            ("let preflightNavigationBar = preflightNavigationBars.firstMatch", 1),
            ("preflightNavigationBars.count == 1", 6),
            ("preflightNavigationBar.exists", 6),
            ("preflightNavigationBar.frame", 4),
            ("let navigationFrame = preflightNavigationBar.frame", 2),
            ("let finalNavigationFrame =\n" +
                "                        preflightNavigationBar.frame", 1),
        ] {
            XCTAssertEqual(
                preflightMinimumSource.components(
                    separatedBy: preflightNavigationBinding
                ).count - 1,
                count,
                preflightNavigationBinding
            )
        }
        for removedPreflightNavigationLookup in [
            "app.navigationBars.matching(",
            #"identifier: "Ready for night check""#,
        ] {
            XCTAssertFalse(
                preflightMinimumSource.contains(removedPreflightNavigationLookup),
                removedPreflightNavigationLookup
            )
        }

        let reportsIndexStart =
            "    private func assertReportsIndex(in app: XCUIApplication) {"
        let reportsIndexEnd =
            "\n    @MainActor\n    private func positionLowerNorthCampusForAXText("
        guard let reportsIndexStartRange = uiSource.range(of: reportsIndexStart),
              let reportsIndexEndRange = uiSource.range(
                of: reportsIndexEnd,
                range: reportsIndexStartRange.upperBound..<uiSource.endIndex
              ) else {
            XCTFail("Missing the reports-index source slice")
            return
        }
        let reportsIndexSource = String(
            uiSource[
                reportsIndexStartRange.lowerBound..<reportsIndexEndRange.lowerBound
            ]
        )
        XCTAssertEqual(reportsIndexSource.utf8.count, 1_513)
        XCTAssertEqual(
            Data(reportsIndexSource.utf8).sha256,
            "7FA0D9FD19E7B8FD37DD718893A776B4D94D84CC6B5DCD2521B377A5BF27238A"
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: reportsIndexStart).count - 1,
            1
        )
        let reportsIndexCall = "        assertReportsIndex(in: app)"
        XCTAssertEqual(
            uiSource.components(separatedBy: reportsIndexCall).count - 1,
            1
        )
        for removedThrowingReportsIndexForm in [
            "        try assertReportsIndex(in: app)",
            "    private func assertReportsIndex(in app: XCUIApplication) throws {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedThrowingReportsIndexForm
                ).count - 1,
                0,
                removedThrowingReportsIndexForm
            )
        }
        let restoredReportsScreenWait =
            #"        XCTAssertTrue(element("s4.4.reports.screen", in: app)"# + "\n" +
                "            .waitForExistence(timeout: 30))"
        let reportsBaseline =
            #"        captureBaseline("state.reports-index.ready", in: app)"#
        let restoredReportsAcceptance =
            restoredReportsScreenWait + "\n" + reportsBaseline
        XCTAssertEqual(
            reportsIndexSource.components(
                separatedBy: restoredReportsAcceptance
            ).count - 1,
            1
        )
        for removedReportsIndexDiagnosticForm in [
            "S10_4_REPORTS_INDEX_CONTRAST_DIAGNOSTIC",
            "S10.4 reports-index contrast diagnostic",
            "let northCampusPredicate = NSPredicate(",
            "reportsScreens",
            "northCampusStaticTexts",
            "reportVisits",
            "northCampusScrollViews",
            #"let reportsScreen = element("s4.4.reports.screen", in: app)"#,
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedReportsIndexDiagnosticForm
                ).count - 1,
                0,
                removedReportsIndexDiagnosticForm
            )
        }
        for removedReportsIndexSerializerForm in [
            "let diagnosticQueries: [(String, XCUIElementQuery)] = [",
            "var diagnosticQueryObjects",
            "var diagnosticIssueObjects",
            "var diagnosticAuditedElements",
            "let diagnosticAuditedElementObjects",
        ] {
            XCTAssertEqual(
                reportsIndexSource.components(
                    separatedBy: removedReportsIndexSerializerForm
                ).count - 1,
                0,
                removedReportsIndexSerializerForm
            )
        }
        let residualReportsIndexDiagnosticMutation =
            uiSource + "\nS10_4_REPORTS_INDEX_CONTRAST_DIAGNOSTIC"
        XCTAssertNotEqual(
            residualReportsIndexDiagnosticMutation.components(
                separatedBy: "S10_4_REPORTS_INDEX_CONTRAST_DIAGNOSTIC"
            ).count - 1,
            0
        )
        let unchangedReportsContinuation =
            reportsBaseline + "\n\n" +
                #"        let signsTab = element("s1.tab.signs", in: app)"# + "\n" +
                "        XCTAssertTrue(signsTab.waitForExistence(timeout: 20))\n" +
                "        signsTab.tap()"
        XCTAssertEqual(
            reportsIndexSource.components(
                separatedBy: unchangedReportsContinuation
            ).count - 1,
            1
        )

        let signDetailOpenIssueCaller =
            "        try completeWorkAndResolvedRecheckAtXXXL(in: app)"
        let signDetailOpenIssueSignature =
            "    private func completeWorkAndResolvedRecheckAtXXXL(\n" +
                "        in app: XCUIApplication\n" +
                "    ) throws {"
        XCTAssertEqual(
            uiSource.components(separatedBy: signDetailOpenIssueCaller).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: signDetailOpenIssueSignature).count - 1,
            1
        )
        for staleNonthrowingSignDetailForm in [
            "        completeWorkAndResolvedRecheckAtXXXL(in: app)",
            "    private func completeWorkAndResolvedRecheckAtXXXL(\n" +
                "        in app: XCUIApplication\n" +
                "    ) {",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: staleNonthrowingSignDetailForm
                ).count - 1,
                0,
                staleNonthrowingSignDetailForm
            )
        }

        let signDetailPositioningHelperStart =
            "    @MainActor\n" +
                "    private func positionSignDetailTimeZoneForAXText(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {"
        let signDetailRouteHeadStart =
            "    @MainActor\n" + signDetailOpenIssueSignature
        let signDetailRecordWorkTap = "        recordWork.tap()"
        guard let signDetailPositioningHelperStartRange = uiSource.range(
            of: signDetailPositioningHelperStart
        ), let signDetailRouteHeadStartRange = uiSource.range(
            of: signDetailRouteHeadStart,
            range: signDetailPositioningHelperStartRange.upperBound..<uiSource.endIndex
        ), let signDetailRecordWorkTapRange = uiSource.range(
            of: signDetailRecordWorkTap,
            range: signDetailRouteHeadStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text sign-detail positioning sources")
            return
        }
        let signDetailPositioningHelperSource = String(
            uiSource[
                signDetailPositioningHelperStartRange.lowerBound ..<
                    signDetailRouteHeadStartRange.lowerBound
            ]
        )
        XCTAssertEqual(signDetailPositioningHelperSource.utf8.count, 15_476)
        XCTAssertEqual(
            Data(signDetailPositioningHelperSource.utf8).sha256,
            "6FC659E4657089B4932B3AF614A1C3238179FCEFA97F863D7E58143D94ABF262"
        )
        let signDetailRouteHeadSource = String(
            uiSource[
                signDetailRouteHeadStartRange.lowerBound ..<
                    signDetailRecordWorkTapRange.upperBound
            ]
        )
        XCTAssertEqual(signDetailRouteHeadSource.utf8.count, 1_023)
        XCTAssertEqual(
            Data(signDetailRouteHeadSource.utf8).sha256,
            "26FFC59CB430880855552D15BFF36CA21D766F8E3A39E7F6B520AB6A1F8B8326"
        )
        let workValidationRouteStart =
            #"        let description = element("s5.1.work.description", in: app)"#
        let workValidationRouteEnd = "        scroll(description, in: app)"
        guard let workValidationRouteStartRange = uiSource.range(
            of: workValidationRouteStart,
            range: signDetailRecordWorkTapRange.upperBound..<uiSource.endIndex
        ), let workValidationRouteEndRange = uiSource.range(
            of: workValidationRouteEnd,
            range: workValidationRouteStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text work-validation route")
            return
        }
        let workValidationRouteSource = String(
            uiSource[
                workValidationRouteStartRange.lowerBound ..<
                    workValidationRouteEndRange.upperBound
            ]
        )
        XCTAssertEqual(workValidationRouteSource.utf8.count, 875)
        XCTAssertEqual(
            Data(workValidationRouteSource.utf8).sha256,
            "8BE7415970056426117AA79383D4F0D7ED1AF2BC74F0C3FB05CEE9ADD231FD13"
        )
        let workValidationPositioningHelperStart =
            "    @MainActor\n" +
                "    private func positionWorkValidationShortDescriptionForAXText(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {"
        let reportComparisonRouteStart =
            "    @MainActor\n" +
                "    private func captureReportComparisonAndCorrectionStates("
        guard let workValidationPositioningHelperStartRange = uiSource.range(
            of: workValidationPositioningHelperStart,
            range: workValidationRouteEndRange.upperBound..<uiSource.endIndex
        ), let reportComparisonRouteStartRange = uiSource.range(
            of: reportComparisonRouteStart,
            range: workValidationPositioningHelperStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text work-validation positioning helper")
            return
        }
        let workValidationPositioningHelperSource = String(
            uiSource[
                workValidationPositioningHelperStartRange.lowerBound ..<
                    reportComparisonRouteStartRange.lowerBound
            ]
        )
        XCTAssertEqual(workValidationPositioningHelperSource.utf8.count, 31_293)
        XCTAssertEqual(
            Data(workValidationPositioningHelperSource.utf8).sha256,
            "CBE290996554242DC5EB92F3B379BC5053318C14187F7ECA1398EE2388BE5D41"
        )
        let workValidationDiagnosticStart =
            "            if diagnosticAttemptIndex == 0 {"
        let workValidationDiagnosticEnd =
            "            guard diagnosticAttemptIndex != 0,\n" +
                "                  hasExactRoute() else {"
        guard let workValidationDiagnosticStartRange =
            workValidationPositioningHelperSource.range(
                of: workValidationDiagnosticStart
            ),
              let workValidationDiagnosticEndRange =
                workValidationPositioningHelperSource.range(
                    of: workValidationDiagnosticEnd,
                    range: workValidationDiagnosticStartRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ) else {
            XCTFail("Missing bounded work-validation route diagnostic")
            return
        }
        let workValidationDiagnosticSource = String(
            workValidationPositioningHelperSource[
                workValidationDiagnosticStartRange.lowerBound ..<
                    workValidationDiagnosticEndRange.lowerBound
            ]
        )
        XCTAssertEqual(workValidationDiagnosticSource.utf8.count, 6_205)
        XCTAssertEqual(
            Data(workValidationDiagnosticSource.utf8).sha256,
            "B7EE5A46D12E8D7FE84D67250075AAEFCEA05A148CEAB026DD7C0ABED87B9CC0"
        )

        let signDetailPositioningGate =
            #"        if automationShard?.shardID == "s10.4.current.ax-text" {"#
        let signDetailPositioningGuard =
            "            guard positionSignDetailTimeZoneForAXText(in: app) else {\n" +
                "                throw AutomationConfigurationError.invalid(\n" +
                "                    \"S10.4 AX-text sign-detail time-zone positioning failed\"\n" +
                "                )\n" +
                "            }"
        let signDetailOpenIssueBaseline =
            #"        captureBaseline("state.sign-detail.open-issue", in: app)"#
        let signDetailPositioningAdjacency =
            signDetailPositioningGate + "\n" +
                signDetailPositioningGuard + "\n" +
                "        }\n" +
                signDetailOpenIssueBaseline
        XCTAssertEqual(
            signDetailRouteHeadSource.components(
                separatedBy: signDetailPositioningAdjacency
            ).count - 1,
            1
        )
        let signDetailWaitBeforePositioning =
            #"        let signDetail = element("s2.sign-detail.screen", in: app)"# +
                "\n" +
                "        XCTAssertTrue(signDetail.waitForExistence(timeout: 30))\n" +
                signDetailPositioningGate
        XCTAssertEqual(
            signDetailRouteHeadSource.components(
                separatedBy: signDetailWaitBeforePositioning
            ).count - 1,
            1
        )
        XCTAssertEqual(
            signDetailRouteHeadSource.components(
                separatedBy: signDetailPositioningGate
            ).count - 1,
            1
        )
        XCTAssertEqual(
            signDetailRouteHeadSource.components(
                separatedBy: signDetailPositioningGuard
            ).count - 1,
            1
        )
        guard let signDetailPositioningGateRange =
            signDetailRouteHeadSource.range(of: signDetailPositioningGate),
              let signDetailOpenIssueBaselineRange =
                signDetailRouteHeadSource.range(
                    of: signDetailOpenIssueBaseline,
                    range: signDetailPositioningGateRange.upperBound ..<
                        signDetailRouteHeadSource.endIndex
                ) else {
            XCTFail("Missing the exact sign-detail positioning gate boundary")
            return
        }
        let signDetailPositioningGateSource = String(
            signDetailRouteHeadSource[
                signDetailPositioningGateRange.lowerBound ..<
                    signDetailOpenIssueBaselineRange.lowerBound
            ]
        )

        let signDetailQueryLocks = [
            "        let timeZonePredicate = NSPredicate(\n" +
                #"            format: "label == %@","# + "\n" +
                #"            "America/New_York""# + "\n" +
                "        )",
            "        let signDetailScreens = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s2.sign-detail.screen""# + "\n" +
                "        )",
            "        let timeZoneRows = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s2.sign-detail.time-zone""# + "\n" +
                "        )",
            "        let timeZoneStaticTexts = app.staticTexts.matching(timeZonePredicate)",
            "        let timeZoneScrollViews = app.scrollViews.containing(timeZonePredicate)",
            "        let navigationBars = app.navigationBars.matching(\n" +
                #"            identifier: "Sign detail""# + "\n" +
                "        )",
            "        let tabBars = app.tabBars",
        ]
        for lock in signDetailQueryLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        let signDetailBindingLocks = [
            "        let signDetailScreen = signDetailScreens.firstMatch",
            "        let timeZoneRow = timeZoneRows.firstMatch",
            "        let timeZoneStaticText = timeZoneStaticTexts.firstMatch",
            "        let timeZoneScrollView = timeZoneScrollViews.firstMatch",
            "        let navigationBar = navigationBars.firstMatch",
            "        let tabBar = tabBars.firstMatch",
        ]
        for lock in signDetailBindingLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        let signDetailExactRouteLocks = [
            "            app.state == .runningForeground",
            "                && signDetailScreens.count == 1",
            "                && timeZoneRows.count == 1",
            "                && timeZoneStaticTexts.count == 1",
            "                && timeZoneScrollViews.count == 1",
            "                && navigationBars.count == 1",
            "                && tabBars.count == 1",
            "                && signDetailScreen.elementType == .scrollView",
            #"                && signDetailScreen.identifier == "s2.sign-detail.screen""#,
            #"                && (signDetailScreen.value as? String) == """#,
            "                && signDetailScreen.isHittable",
            "                && timeZoneRow.elementType == .staticText",
            #"                && timeZoneRow.identifier == "s2.sign-detail.time-zone""#,
            #"                && timeZoneRow.label == "Time zone, America/New_York""#,
            #"                && (timeZoneRow.value as? String) == """#,
            "                && timeZoneStaticText.elementType == .staticText",
            "                && timeZoneStaticText.identifier.isEmpty",
            #"                && timeZoneStaticText.label == "America/New_York""#,
            #"                && (timeZoneStaticText.value as? String) == """#,
            "                && timeZoneScrollView.elementType == .scrollView",
            #"                && timeZoneScrollView.identifier == "s2.sign-detail.screen""#,
            #"                && (timeZoneScrollView.value as? String) == """#,
            "                && timeZoneScrollView.isHittable",
            "                && navigationBar.elementType == .navigationBar",
            #"                && navigationBar.identifier == "Sign detail""#,
            #"                && (navigationBar.value as? String) == """#,
            "                && navigationBar.isHittable",
            "                && tabBar.elementType == .tabBar",
            "                && tabBar.identifier.isEmpty",
            #"                && tabBar.label == "Tab Bar""#,
            #"                && (tabBar.value as? String) == """#,
            "                && tabBar.isHittable",
        ]
        for lock in signDetailExactRouteLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        for lock in [
            "                && timeZoneRow.isHittable",
            "                && timeZoneStaticText.isHittable",
        ] {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                2,
                lock
            )
        }
        for (lock, count) in [
            (".count == 1", 6),
            (".firstMatch", 6),
            ("let hasExactRoute: () -> Bool", 1),
            ("hasExactRoute()", 4),
        ] {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }

        let signDetailFrameValidationLocks = [
            "        let isValidFrame: (CGRect) -> Bool = { frame in\n" +
                "            !frame.isNull\n" +
                "                && !frame.isEmpty\n" +
                "                && !frame.isInfinite\n" +
                "                && frame.origin.x.isFinite\n" +
                "                && frame.origin.y.isFinite\n" +
                "                && frame.size.width.isFinite\n" +
                "                && frame.size.height.isFinite\n" +
                "        }",
            "            let applicationFrame = app.frame",
            "            let screenFrame = signDetailScreen.frame",
            "            let rowFrame = timeZoneRow.frame",
            "            let targetFrame = timeZoneStaticText.frame",
            "            let scrollFrame = timeZoneScrollView.frame",
            "            let navigationFrame = navigationBar.frame",
            "            let tabFrame = tabBar.frame",
            "            let liveFramesAreValid = isValidFrame(applicationFrame)",
            "            var liveScrollFrame = CGRect.null",
            "            if liveFramesAreValid {\n" +
                "                liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                "            }",
            "            guard liveFramesAreValid,",
            "                  screenFrame == scrollFrame else {",
            "        let finalFramesAreValid = isValidFrame(finalApplicationFrame)",
            "            && finalScreenFrame == finalScrollFrame",
            "        var finalCompositionIsSafe = false",
            "        if finalFramesAreValid {",
            "            let finalLiveScrollFrame = finalScrollFrame.intersection(",
            "            if isValidFrame(finalLiveScrollFrame) {",
            "        guard finalCompositionIsSafe else {",
        ]
        for lock in signDetailFrameValidationLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        guard let liveValidityRange = signDetailPositioningHelperSource.range(
            of: "            let liveFramesAreValid = isValidFrame(applicationFrame)"
        ), let liveIntersectionRange = signDetailPositioningHelperSource.range(
            of: "                liveScrollFrame = scrollFrame.intersection(applicationFrame)",
            range: liveValidityRange.upperBound..<signDetailPositioningHelperSource.endIndex
        ), let liveGuardRange = signDetailPositioningHelperSource.range(
            of: "            guard liveFramesAreValid,",
            range: liveIntersectionRange.upperBound..<signDetailPositioningHelperSource.endIndex
        ), let liveArithmeticRange = signDetailPositioningHelperSource.range(
            of: "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)",
            range: liveGuardRange.upperBound..<signDetailPositioningHelperSource.endIndex
        ), let finalValidityRange = signDetailPositioningHelperSource.range(
            of: "        let finalFramesAreValid = isValidFrame(finalApplicationFrame)"
        ), let finalIntersectionRange = signDetailPositioningHelperSource.range(
            of: "            let finalLiveScrollFrame = finalScrollFrame.intersection(",
            range: finalValidityRange.upperBound..<signDetailPositioningHelperSource.endIndex
        ), let finalArithmeticRange = signDetailPositioningHelperSource.range(
            of: "                let finalSafeTop = max(",
            range: finalIntersectionRange.upperBound..<signDetailPositioningHelperSource.endIndex
        ) else {
            XCTFail("Missing frame-validity-before-arithmetic ordering")
            return
        }
        XCTAssertLessThan(liveValidityRange.lowerBound, liveIntersectionRange.lowerBound)
        XCTAssertLessThan(liveIntersectionRange.lowerBound, liveGuardRange.lowerBound)
        XCTAssertLessThan(liveGuardRange.lowerBound, liveArithmeticRange.lowerBound)
        XCTAssertLessThan(finalValidityRange.lowerBound, finalIntersectionRange.lowerBound)
        XCTAssertLessThan(finalIntersectionRange.lowerBound, finalArithmeticRange.lowerBound)

        let signDetailGeometryLocks = [
            "        let verticalInset: CGFloat = 16",
            "        let receiverInset: CGFloat = 24",
            "        let minimumGestureDistance: CGFloat = 44",
            "        var previousRowMinYAfterDrag: CGFloat?",
            "        var previousTargetMinYAfterDrag: CGFloat?",
            "        for _ in 0..<4 {",
            "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)",
            "            let safeTop = liveTop + verticalInset",
            "            let safeBottom = liveBottom - verticalInset",
            "            let receiverTop = liveTop + receiverInset",
            "            let receiverBottom = liveBottom - receiverInset",
            "            let receiverLeft = liveScrollFrame.minX + receiverInset",
            "            let receiverRight = liveScrollFrame.maxX - receiverInset",
            "            let receiverCapacity = receiverBottom - receiverTop",
            "            let minimumShift = max(\n" +
                "                safeTop - rowFrame.minY,\n" +
                "                safeTop - targetFrame.minY\n" +
                "            )",
            "            let maximumShift = min(\n" +
                "                safeBottom - rowFrame.maxY,\n" +
                "                safeBottom - targetFrame.maxY\n" +
                "            )",
            "                  (rowIsContained && targetIsContained) || maximumShift < 0 else {",
            "            if rowIsContained && targetIsContained { break }",
            "            if maximumShift >= -receiverCapacity {",
            "                let recognizedMinimum = max(\n" +
                "                    minimumShift,\n" +
                "                    -receiverCapacity\n" +
                "                )",
            "                let recognizedMaximum = min(\n" +
                "                    maximumShift,\n" +
                "                    -minimumGestureDistance\n" +
                "                )",
            "                dragDistance = recognizedMaximum",
            "                let stagedDistance = max(\n" +
                "                    -receiverCapacity,\n" +
                "                    maximumShift + minimumGestureDistance\n" +
                "                )",
            "                guard stagedDistance <= -minimumGestureDistance else {",
            "                dragDistance = stagedDistance",
            "                  dragDistance < 0,",
            "                  abs(dragDistance) >= minimumGestureDistance else {",
        ]
        for lock in signDetailGeometryLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }

        let signDetailReceiverLocks = [
            "            let receiverFrame = CGRect(\n" +
                "                x: receiverLeft,\n" +
                "                y: receiverTop,\n" +
                "                width: receiverRight - receiverLeft,\n" +
                "                height: receiverBottom - receiverTop\n" +
                "            )",
            "            let startPoint = CGPoint(\n" +
                "                x: receiverRight,\n" +
                "                y: receiverBottom\n" +
                "            )",
            "            let endPoint = CGPoint(\n" +
                "                x: startPoint.x,\n" +
                "                y: startPoint.y + dragDistance\n" +
                "            )",
            "                  isValidFrame(receiverFrame),",
            "                  startPoint.x >= receiverFrame.minX,",
            "                  startPoint.x <= receiverFrame.maxX,",
            "                  startPoint.y >= receiverFrame.minY,",
            "                  startPoint.y <= receiverFrame.maxY,",
            "                  endPoint.x >= receiverFrame.minX,",
            "                  endPoint.x <= receiverFrame.maxX,",
            "                  endPoint.y >= receiverFrame.minY,",
            "                  endPoint.y <= receiverFrame.maxY,",
            "                  liveScrollFrame.contains(startPoint),",
            "                  liveScrollFrame.contains(endPoint),",
            "                  !rowFrame.contains(startPoint),",
            "                  !rowFrame.contains(endPoint),",
            "                  !targetFrame.contains(startPoint),",
            "                  !targetFrame.contains(endPoint) else {",
            "            let scrollOrigin = timeZoneScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )",
            "                    dx: startPoint.x - scrollFrame.minX,",
            "                    dy: startPoint.y - scrollFrame.minY",
            "                    dx: endPoint.x - scrollFrame.minX,",
            "                    dy: endPoint.y - scrollFrame.minY",
            "                forDuration: 0.2,",
            "                withVelocity: .slow,",
            "                thenHoldForDuration: 0.2",
        ]
        for lock in signDetailReceiverLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        for (lock, count) in [
            (".coordinate(", 1),
            (".press(", 1),
            ("thenDragTo:", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }

        let signDetailProgressLocks = [
            "            let rowBeforeDrag = rowFrame.minY",
            "            let targetBeforeDrag = targetFrame.minY",
            "            let rowAfterDrag = timeZoneRow.frame",
            "            let targetAfterDrag = timeZoneStaticText.frame",
            "            var observedRowShift: CGFloat?",
            "            var observedTargetShift: CGFloat?",
            "            if isValidFrame(rowAfterDrag), isValidFrame(targetAfterDrag) {",
            "                observedRowShift = rowAfterDrag.minY - rowBeforeDrag",
            "                observedTargetShift = targetAfterDrag.minY - targetBeforeDrag",
            "            guard let observedRowShift,",
            "                  let observedTargetShift,",
            "                  observedRowShift * dragDistance > 0,",
            "                  observedTargetShift * dragDistance > 0 else {",
            "            if let previousRowMinYAfterDrag,",
            "               let previousTargetMinYAfterDrag {",
            "                guard rowAfterDrag.minY < previousRowMinYAfterDrag,",
            "                      targetAfterDrag.minY < previousTargetMinYAfterDrag else {",
            "            previousRowMinYAfterDrag = rowAfterDrag.minY",
            "            previousTargetMinYAfterDrag = targetAfterDrag.minY",
            "                    && finalRowFrame.minY >= finalSafeTop",
            "                    && finalRowFrame.maxY <= finalSafeBottom",
            "                    && finalTargetFrame.minY >= finalSafeTop",
            "                    && finalTargetFrame.maxY <= finalSafeBottom",
            "                    && timeZoneRow.isHittable",
            "                    && timeZoneStaticText.isHittable",
        ]
        for lock in signDetailProgressLocks {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }

        let signDetailFailureMessages = [
            "AX-text sign-detail time-zone positioning bindings are ambiguous.",
            "AX-text sign-detail time-zone positioning route changed.",
            "AX-text sign-detail time-zone positioning geometry is invalid.",
            "AX-text sign-detail time-zone composition has no supported upward interval.",
            "AX-text sign-detail time-zone direct interval is not recognizable.",
            "AX-text sign-detail time-zone staged remainder is not recognizable.",
            "AX-text sign-detail time-zone drag direction is invalid.",
            "AX-text sign-detail time-zone drag receiver is obstructed.",
            "AX-text sign-detail time-zone route changed after positioning.",
            "AX-text sign-detail time-zone gesture made no signed progress.",
            "AX-text sign-detail time-zone positioning reversed direction.",
            "AX-text sign-detail time-zone final route is invalid.",
            "AX-text sign-detail time-zone final composition is unsafe.",
        ]
        var signDetailFailureSearchStart =
            signDetailPositioningHelperSource.startIndex
        for message in signDetailFailureMessages {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: message
                ).count - 1,
                1,
                message
            )
            guard let messageRange = signDetailPositioningHelperSource.range(
                of: message,
                range: signDetailFailureSearchStart ..<
                    signDetailPositioningHelperSource.endIndex
            ) else {
                XCTFail("Missing ordered sign-detail positioning failure message")
                return
            }
            signDetailFailureSearchStart = messageRange.upperBound
        }
        for (lock, count) in [
            ("XCTFail(", 13),
            ("return false", 13),
            ("return true", 1),
        ] {
            XCTAssertEqual(
                signDetailPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }

        for prohibitedSignDetailPositioningHelperForm in [
            ".tap(",
            ".swipe",
            "scroll(",
            "waitForExistence",
            ".typeText(",
            "Thread.sleep",
            "sleep(",
            "performAccessibilityAudit",
            "XCTAttachment",
            "printJSONLine",
            "NSNull",
            "S10_4_SIGN_DETAIL_OPEN_ISSUE_CONTRAST_DIAGNOSTIC",
            "sign-detail open-issue contrast diagnostic",
            "captureBaseline(",
            "ContrastAuditExceptionSignature",
            "contrastAuditExceptionSignatures",
            "automationContrastExceptions",
            "attachCandidate(",
            #"prefix: "S10_4_AX_STATE""#,
            #"prefix: "S10_4_CONTRAST""#,
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "return false &&",
            "maximumShift > 0",
            "minimumShift > 0",
            "positionedDirection",
            "observedDirection",
        ] {
            XCTAssertFalse(
                signDetailPositioningHelperSource.contains(
                    prohibitedSignDetailPositioningHelperForm
                ),
                prohibitedSignDetailPositioningHelperForm
            )
        }
        for prohibitedSignDetailGateForm in [
            ".tap(",
            ".swipe",
            ".coordinate(",
            ".press(",
            "thenDragTo:",
            "scroll(",
            "waitForExistence",
            "Thread.sleep",
            "performAccessibilityAudit",
            "XCTAttachment",
            "printJSONLine",
            "NSNull",
            "S10_4_SIGN_DETAIL_OPEN_ISSUE_CONTRAST_DIAGNOSTIC",
            "sign-detail open-issue contrast diagnostic",
            "return",
        ] {
            XCTAssertFalse(
                signDetailPositioningGateSource.contains(
                    prohibitedSignDetailGateForm
                ),
                prohibitedSignDetailGateForm
            )
        }
        for removedSignDetailDiagnosticForm in [
            "S10_4_SIGN_DETAIL_OPEN_ISSUE_CONTRAST_DIAGNOSTIC",
            "S10.4 sign-detail open-issue contrast diagnostic",
            "let diagnosticIssueObjects:",
            "let diagnosticAuditedElements:",
            "diagnosticAuditedElementObjects",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedSignDetailDiagnosticForm
                ).count - 1,
                0,
                removedSignDetailDiagnosticForm
            )
        }
        let workValidationBaseline =
            #"        captureBaseline("state.work.validation-error", in: app)"#
        let workValidationPositioningGate =
            #"        if automationShard?.shardID == "s10.4.current.ax-text" {"#
        let workValidationPositioningGuard =
            "            guard positionWorkValidationShortDescriptionForAXText(in: app) else {\n" +
                "                throw AutomationConfigurationError.invalid(\n" +
                "                    \"S10.4 AX-text work-validation Short description positioning failed\"\n" +
                "                )\n" +
                "            }"
        let workValidationPositioningAdjacency =
            workValidationPositioningGate + "\n" +
                workValidationPositioningGuard + "\n" +
                "        }\n" +
                workValidationBaseline
        XCTAssertEqual(
            workValidationRouteSource.components(
                separatedBy: workValidationPositioningAdjacency
            ).count - 1,
            1
        )
        let workValidationWaitBeforePositioning =
            #"        let validation = element("s5.1.work.validation", in: app)"# +
                "\n" +
                "        XCTAssertTrue(validation.waitForExistence(timeout: 10))\n" +
                #"        assertLocalizedLabel(validation, equals: "Short description")"# +
                "\n" +
                workValidationPositioningGate
        XCTAssertEqual(
            workValidationRouteSource.components(
                separatedBy: workValidationWaitBeforePositioning
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workValidationRouteSource.components(
                separatedBy: workValidationBaseline
            ).count - 1,
            1
        )

        let workValidationQueryLocks = [
            "        let shortDescriptionPredicate = NSPredicate(\n" +
                #"            format: "label == %@","# + "\n" +
                #"            "Short description""# + "\n" +
                "        )",
            "        let emptyShortDescriptionPredicate = NSPredicate(\n" +
                #"            format: "identifier == '' AND label == %@","# + "\n" +
                #"            "Short description""# + "\n" +
                "        )",
            #"            format: "hasKeyboardFocus == true""#,
            #"            identifier: "s5.1.work.screen""#,
            #"            identifier: "s5.1.work.description""#,
            "        let focusedDescriptionFields = descriptionFields.matching(\n" +
                "            focusedPredicate\n" +
                "        )",
            #"            identifier: "s5.1.work.validation""#,
            "        let shortDescriptionStaticTexts = app.staticTexts.matching(\n" +
                "            shortDescriptionPredicate\n" +
                "        )",
            "        let shortDescriptionFieldLabels = app.staticTexts.matching(\n" +
                "            emptyShortDescriptionPredicate\n" +
                "        )",
            "        let descriptionScrollViews = app.scrollViews.containing(\n" +
                "            .textField,\n" +
                #"            identifier: "s5.1.work.description""# + "\n" +
                "        )",
            #"            identifier: "Record work""#,
            "        let tabBars = app.tabBars",
            "        let keyboards = app.keyboards",
        ]
        for lock in workValidationQueryLocks {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                lock == #"            identifier: "s5.1.work.description""# ? 2 : 1,
                lock
            )
        }
        for lock in [
            "        let workScreen = workScreens.firstMatch",
            "        let descriptionField = descriptionFields.firstMatch",
            "        let focusedDescriptionField = focusedDescriptionFields.firstMatch",
            "        let validationLabel = validationLabels.firstMatch",
            "        let shortDescriptionFieldLabel = shortDescriptionFieldLabels.firstMatch",
            "        let descriptionScrollView = descriptionScrollViews.firstMatch",
            "        let navigationBar = navigationBars.firstMatch",
            "        let tabBar = tabBars.firstMatch",
            "        let keyboard = keyboards.firstMatch",
        ] {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        let workValidationCardinalityLocks = [
            "workScreens.count == 1",
            "descriptionFields.count == 1",
            "focusedDescriptionFields.count == 1",
            "validationLabels.count == 1",
            "shortDescriptionStaticTexts.count == 2",
            "shortDescriptionFieldLabels.count == 1",
            "descriptionScrollViews.count == 1",
            "navigationBars.count == 1",
            "tabBars.count == 1",
            "keyboards.count == 1",
        ]
        for lock in workValidationCardinalityLocks {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                2,
                lock
            )
        }
        let workValidationRouteRelationNames = [
            "applicationForeground",
            "workScreensCountOne",
            "descriptionFieldsCountOne",
            "focusedDescriptionFieldsCountOne",
            "validationLabelsCountOne",
            "shortDescriptionStaticTextsCountTwo",
            "shortDescriptionFieldLabelsCountOne",
            "descriptionScrollViewsCountOne",
            "navigationBarsCountOne",
            "tabBarsCountOne",
            "keyboardsCountOne",
            "workScreenExists",
            "workScreenTypeScrollView",
            "workScreenIdentifier",
            "workScreenLabelEmpty",
            "workScreenValueEmpty",
            "workScreenHittable",
            "descriptionFieldExists",
            "descriptionFieldTypeTextField",
            "descriptionFieldIdentifier",
            "descriptionFieldLabel",
            "descriptionFieldValue",
            "descriptionFieldHittable",
            "focusedDescriptionFieldExists",
            "focusedDescriptionFieldTypeTextField",
            "focusedDescriptionFieldIdentifier",
            "focusedDescriptionFieldLabel",
            "focusedDescriptionFieldValue",
            "focusedDescriptionFieldHittable",
            "validationLabelExists",
            "validationLabelTypeStaticText",
            "validationLabelIdentifier",
            "validationLabelLabel",
            "validationLabelValueEmpty",
            "validationLabelHittable",
            "shortDescriptionFieldLabelExists",
            "shortDescriptionFieldLabelTypeStaticText",
            "shortDescriptionFieldLabelIdentifierEmpty",
            "shortDescriptionFieldLabelLabel",
            "shortDescriptionFieldLabelValueEmpty",
            "descriptionScrollViewExists",
            "descriptionScrollViewTypeScrollView",
            "descriptionScrollViewIdentifier",
            "descriptionScrollViewLabelEmpty",
            "descriptionScrollViewValueEmpty",
            "descriptionScrollViewHittable",
            "navigationBarExists",
            "navigationBarTypeNavigationBar",
            "navigationBarIdentifier",
            "navigationBarLabelEmpty",
            "navigationBarValueEmpty",
            "navigationBarHittable",
            "tabBarExists",
            "tabBarTypeTabBar",
            "tabBarIdentifierEmpty",
            "tabBarLabel",
            "tabBarValueEmpty",
            "tabBarHittable",
            "keyboardExists",
            "keyboardTypeKeyboard",
            "keyboardIdentifierEmpty",
            "keyboardLabelEmpty",
            "keyboardValueEmpty",
            "keyboardHittable",
        ]
        XCTAssertEqual(workValidationRouteRelationNames.count, 64)
        let workValidationRouteRelationPredicates = [
            "app.state == .runningForeground",
            "workScreens.count == 1",
            "descriptionFields.count == 1",
            "focusedDescriptionFields.count == 1",
            "validationLabels.count == 1",
            "shortDescriptionStaticTexts.count == 2",
            "shortDescriptionFieldLabels.count == 1",
            "descriptionScrollViews.count == 1",
            "navigationBars.count == 1",
            "tabBars.count == 1",
            "keyboards.count == 1",
            "workScreen.exists",
            "workScreen.elementType == .scrollView",
            #"workScreen.identifier == "s5.1.work.screen""#,
            "workScreen.label.isEmpty",
            #"(workScreen.value as? String) == """#,
            "workScreen.isHittable",
            "descriptionField.exists",
            "descriptionField.elementType == .textField",
            #"descriptionField.identifier == "s5.1.work.description""#,
            #"descriptionField.label == "Short description""#,
            #"(descriptionField.value as? String) == "Short description""#,
            "descriptionField.isHittable",
            "focusedDescriptionField.exists",
            "focusedDescriptionField.elementType == .textField",
            #"focusedDescriptionField.identifier == "s5.1.work.description""#,
            #"focusedDescriptionField.label == "Short description""#,
            #"(focusedDescriptionField.value as? String) == "Short description""#,
            "focusedDescriptionField.isHittable",
            "validationLabel.exists",
            "validationLabel.elementType == .staticText",
            #"validationLabel.identifier == "s5.1.work.validation""#,
            #"validationLabel.label == "Short description""#,
            #"(validationLabel.value as? String) == """#,
            "validationLabel.isHittable",
            "shortDescriptionFieldLabel.exists",
            "shortDescriptionFieldLabel.elementType == .staticText",
            "shortDescriptionFieldLabel.identifier.isEmpty",
            #"shortDescriptionFieldLabel.label == "Short description""#,
            #"(shortDescriptionFieldLabel.value as? String) == """#,
            "descriptionScrollView.exists",
            "descriptionScrollView.elementType == .scrollView",
            #"descriptionScrollView.identifier == "s5.1.work.screen""#,
            "descriptionScrollView.label.isEmpty",
            #"(descriptionScrollView.value as? String) == """#,
            "descriptionScrollView.isHittable",
            "navigationBar.exists",
            "navigationBar.elementType == .navigationBar",
            #"navigationBar.identifier == "Record work""#,
            "navigationBar.label.isEmpty",
            #"(navigationBar.value as? String) == """#,
            "navigationBar.isHittable",
            "tabBar.exists",
            "tabBar.elementType == .tabBar",
            "tabBar.identifier.isEmpty",
            #"tabBar.label == "Tab Bar""#,
            #"(tabBar.value as? String) == """#,
            "tabBar.isHittable",
            "keyboard.exists",
            "keyboard.elementType == .keyboard",
            "keyboard.identifier.isEmpty",
            "keyboard.label.isEmpty",
            #"(keyboard.value as? String) == """#,
            "keyboard.isHittable",
        ]
        XCTAssertEqual(workValidationRouteRelationPredicates.count, 64)
        var workValidationRelationSearchStart =
            workValidationPositioningHelperSource.startIndex
        for (relationName, predicate) in zip(
            workValidationRouteRelationNames,
            workValidationRouteRelationPredicates
        ) {
            let quotedRelationName = "\"" + relationName + "\""
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: quotedRelationName
                ).count - 1,
                1,
                relationName
            )
            guard let relationRange = workValidationPositioningHelperSource.range(
                of: quotedRelationName,
                range: workValidationRelationSearchStart ..<
                    workValidationPositioningHelperSource.endIndex
            ) else {
                XCTFail("Missing ordered work-validation route relation")
                return
            }
            guard let predicateRange = workValidationPositioningHelperSource.range(
                of: predicate,
                range: relationRange.upperBound ..<
                    workValidationPositioningHelperSource.endIndex
            ) else {
                XCTFail("Missing predicate for ordered work-validation route relation")
                return
            }
            workValidationRelationSearchStart = predicateRange.upperBound
        }
        XCTAssertEqual(
            workValidationPositioningHelperSource.components(
                separatedBy: "        let exactRouteRelations: () -> [(String, Bool)] = {"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workValidationPositioningHelperSource.components(
                separatedBy:
                    "        let hasExactRoute: () -> Bool = {\n" +
                    "            exactRouteRelations().allSatisfy { relation in relation.1 }\n" +
                    "        }"
            ).count - 1,
            1
        )
        let workValidationDiagnosticQueryCountLocks = [
            #"                    "workScreens": workScreens.count,"#,
            #"                    "descriptionFields": descriptionFields.count,"#,
            #"                    "focusedDescriptionFields": focusedDescriptionFields.count,"#,
            #"                    "validationLabels": validationLabels.count,"#,
            #"                    "shortDescriptionStaticTexts": shortDescriptionStaticTexts.count,"#,
            #"                    "shortDescriptionFieldLabels": shortDescriptionFieldLabels.count,"#,
            #"                    "descriptionScrollViews": descriptionScrollViews.count,"#,
            #"                    "navigationBars": navigationBars.count,"#,
            #"                    "tabBars": tabBars.count,"#,
            #"                    "keyboards": keyboards.count,"#,
        ]
        for lock in workValidationDiagnosticQueryCountLocks {
            XCTAssertEqual(
                workValidationDiagnosticSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        let workValidationDiagnosticNodeLocks = [
            #"                    "workScreen": workValidationRouteDiagnosticElementObject("#,
            #"                    "descriptionField": workValidationRouteDiagnosticElementObject("#,
            #"                    "focusedDescriptionField":"#,
            #"                    "validationLabel": workValidationRouteDiagnosticElementObject("#,
            #"                    "shortDescriptionFieldLabel":"#,
            #"                    "descriptionScrollView":"#,
            #"                    "navigationBar": workValidationRouteDiagnosticElementObject("#,
            #"                    "tabBar": workValidationRouteDiagnosticElementObject(tabBar),"#,
            #"                    "keyboard": workValidationRouteDiagnosticElementObject(keyboard),"#,
        ]
        for lock in workValidationDiagnosticNodeLocks {
            XCTAssertEqual(
                workValidationDiagnosticSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        let workValidationDiagnosticSerializerLocks = [
            "                let diagnosticRelations = exactRouteRelations()",
            "                let diagnosticRelationObjects: [[String: Any]] =",
            "                    diagnosticRelations.map {",
            #"                        "name": relation.0,"#,
            #"                        "passed": relation.1,"#,
            "                let workValidationRouteDiagnosticElementObject:",
            "                    (XCUIElement) -> [String: Any] = { element in",
            "                    if let value = element.value as? String {",
            "                        valueObject = NSNull()",
            #"                        "exists": element.exists,"#,
            #"                        "isHittable": element.isHittable,"#,
            #"                        "isEnabled": element.isEnabled,"#,
            #"                        "identifier": element.identifier,"#,
            #"                        "label": element.label,"#,
            #"                        "value": valueObject,"#,
            #"                        "elementTypeRawValue": element.elementType.rawValue,"#,
            #"                        "elementTypeDescription": String("#,
            #"                        "frame": self.auditFrameObject(element.frame),"#,
            #"                    "shardID": automationShard?.shardID ?? "","#,
            #"                    "deviceProfileID": automationShard?.deviceProfileID ?? "","#,
            #"                    "stateID": "state.work.validation-error","#,
            #"                    "applicationState": String(describing: app.state),"#,
            #"                    "applicationStateRawValue": app.state.rawValue,"#,
            #"                    "isRunningForeground": app.state == .runningForeground,"#,
            #"                    "applicationFrame": auditFrameObject(app.frame),"#,
            #"                    "queryCounts": diagnosticQueryCounts,"#,
            #"                    "relations": diagnosticRelationObjects,"#,
            #"                    "failedRelations": diagnosticRelations.compactMap {"#,
            #"                    "nodes": diagnosticNodeObjects,"#,
            #"                    prefix: "S10_4_AX_TEXT_WORK_VALIDATION_ROUTE_DIAGNOSTIC","#,
            "                    object: diagnosticContextObject",
        ]
        for lock in workValidationDiagnosticSerializerLocks {
            XCTAssertEqual(
                workValidationDiagnosticSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        for (lock, count) in [
            ("printJSONLine(", 1),
            ("XCTAttachment(", 3),
            (".lifetime = .keepAlways", 3),
            ("add(diagnostic", 3),
            ("JSONSerialization.data(", 1),
            ("options: [.prettyPrinted, .sortedKeys]", 1),
        ] {
            XCTAssertEqual(
                workValidationDiagnosticSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }
        let workValidationDiagnosticOrder = [
            "                let diagnosticRelations = exactRouteRelations()",
            "                let diagnosticRelationObjects: [[String: Any]] =",
            "                    diagnosticRelations.map {",
            "                let workValidationRouteDiagnosticElementObject:",
            "                let diagnosticQueryCounts: [String: Int] = [",
            "                let diagnosticNodeObjects: [String: Any] = [",
            "                let diagnosticContextObject: [String: Any] = [",
            "                printJSONLine(",
            "                let diagnosticAppAttachment = XCTAttachment(",
            "                add(diagnosticAppAttachment)",
            "                let diagnosticTreeAttachment = XCTAttachment(",
            "                add(diagnosticTreeAttachment)",
            "                let diagnosticContextData = try? JSONSerialization.data(",
            "                let diagnosticContextAttachment = XCTAttachment(",
            "                add(diagnosticContextAttachment)",
        ]
        var workValidationDiagnosticOrderStart =
            workValidationDiagnosticSource.startIndex
        for lock in workValidationDiagnosticOrder {
            guard let lockRange = workValidationDiagnosticSource.range(
                of: lock,
                range: workValidationDiagnosticOrderStart ..<
                    workValidationDiagnosticSource.endIndex
            ) else {
                XCTFail("Missing ordered work-validation route diagnostic source")
                return
            }
            workValidationDiagnosticOrderStart = lockRange.upperBound
        }
        for prohibitedDiagnosticForm in [
            ".tap(",
            ".swipe",
            ".coordinate(",
            ".press(",
            "thenDragTo:",
            "scroll(",
            "waitForExistence",
            "waitForNonExistence",
            ".typeText(",
            "Thread.sleep",
            "sleep(",
            "performAccessibilityAudit",
            "eligibleExceptions",
            "ContrastAuditExceptionSignature",
            "captureBaseline(",
            "attachCandidate(",
            #"prefix: "S10_4_AX_STATE""#,
            #"prefix: "S10_4_CONTRAST""#,
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "liveScrollFrame",
            "minimumShift",
            "maximumShift",
        ] {
            XCTAssertFalse(
                workValidationDiagnosticSource.contains(prohibitedDiagnosticForm),
                prohibitedDiagnosticForm
            )
        }
        guard let diagnosticAttemptRange =
            workValidationPositioningHelperSource.range(
                of: workValidationDiagnosticStart
            ),
              let diagnosticGuardRange =
                workValidationPositioningHelperSource.range(
                    of: workValidationDiagnosticEnd,
                    range: diagnosticAttemptRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let diagnosticFailureRange =
                workValidationPositioningHelperSource.range(
                    of: "                XCTFail(\"AX-text work-validation positioning route or focus changed.\")",
                    range: diagnosticGuardRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let diagnosticReturnFalseRange =
                workValidationPositioningHelperSource.range(
                    of: "                return false",
                    range: diagnosticFailureRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let postDiagnosticGeometryRange =
                workValidationPositioningHelperSource.range(
                    of: "            let applicationFrame = app.frame",
                    range: diagnosticReturnFalseRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ) else {
            XCTFail("Missing diagnostic-to-existing-failure ordering")
            return
        }
        XCTAssertLessThan(diagnosticAttemptRange.lowerBound, diagnosticGuardRange.lowerBound)
        XCTAssertLessThan(diagnosticGuardRange.lowerBound, diagnosticFailureRange.lowerBound)
        XCTAssertLessThan(diagnosticFailureRange.lowerBound, diagnosticReturnFalseRange.lowerBound)
        XCTAssertLessThan(diagnosticReturnFalseRange.lowerBound, postDiagnosticGeometryRange.lowerBound)

        let workValidationFrameLocks = [
            "        let isValidFrame: (CGRect) -> Bool = { frame in\n" +
                "            !frame.isNull\n" +
                "                && !frame.isEmpty\n" +
                "                && !frame.isInfinite\n" +
                "                && frame.origin.x.isFinite\n" +
                "                && frame.origin.y.isFinite\n" +
                "                && frame.size.width.isFinite\n" +
                "                && frame.size.height.isFinite\n" +
                "        }",
            "        let frozenApplicationFrame = app.frame",
            "        let frozenKeyboardFrame = keyboard.frame",
            "            let applicationFrame = app.frame",
            "            let screenFrame = workScreen.frame",
            "            let scrollFrame = descriptionScrollView.frame",
            "            let navigationFrame = navigationBar.frame",
            "            let tabFrame = tabBar.frame",
            "            let keyboardFrame = keyboard.frame",
            "            let fieldLabelFrame = shortDescriptionFieldLabel.frame",
            "            let descriptionFrame = descriptionField.frame",
            "            let validationFrame = validationLabel.frame",
            "            var liveScrollFrame = CGRect.null",
            "                liveScrollFrame = scrollFrame.intersection(applicationFrame)",
            "                  applicationFrame == frozenApplicationFrame,",
            "                  keyboardFrame == frozenKeyboardFrame else {",
            "        let finalFramesAreValid = isValidFrame(finalApplicationFrame)",
            "            && finalApplicationFrame == frozenApplicationFrame",
            "            && finalKeyboardFrame == frozenKeyboardFrame",
        ]
        for lock in workValidationFrameLocks {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        guard let workValidationValidityRange =
            workValidationPositioningHelperSource.range(
                of: "            let liveFramesAreValid = isValidFrame(applicationFrame)"
            ),
              let workValidationIntersectionRange =
                workValidationPositioningHelperSource.range(
                    of: "                liveScrollFrame = scrollFrame.intersection(applicationFrame)",
                    range: workValidationValidityRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let workValidationGuardRange =
                workValidationPositioningHelperSource.range(
                    of: "            guard liveFramesAreValid,",
                    range: workValidationIntersectionRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let workValidationArithmeticRange =
                workValidationPositioningHelperSource.range(
                    of: "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)",
                    range: workValidationGuardRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let workValidationFinalValidityRange =
                workValidationPositioningHelperSource.range(
                    of: "        let finalFramesAreValid = isValidFrame(finalApplicationFrame)"
                ),
              let workValidationFinalIntersectionRange =
                workValidationPositioningHelperSource.range(
                    of: "            let finalLiveScrollFrame = finalScrollFrame.intersection(",
                    range: workValidationFinalValidityRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ),
              let workValidationFinalArithmeticRange =
                workValidationPositioningHelperSource.range(
                    of: "                let finalSafeTop = max(",
                    range: workValidationFinalIntersectionRange.upperBound ..<
                        workValidationPositioningHelperSource.endIndex
                ) else {
            XCTFail("Missing work-validation validity-before-arithmetic order")
            return
        }
        XCTAssertLessThan(
            workValidationValidityRange.lowerBound,
            workValidationIntersectionRange.lowerBound
        )
        XCTAssertLessThan(
            workValidationIntersectionRange.lowerBound,
            workValidationGuardRange.lowerBound
        )
        XCTAssertLessThan(
            workValidationGuardRange.lowerBound,
            workValidationArithmeticRange.lowerBound
        )
        XCTAssertLessThan(
            workValidationFinalValidityRange.lowerBound,
            workValidationFinalIntersectionRange.lowerBound
        )
        XCTAssertLessThan(
            workValidationFinalIntersectionRange.lowerBound,
            workValidationFinalArithmeticRange.lowerBound
        )

        let workValidationGeometryLocks = [
            "        let verticalInset: CGFloat = 16",
            "        let receiverInset: CGFloat = 24",
            "        let minimumGestureDistance: CGFloat = 44",
            "        for diagnosticAttemptIndex in 0..<4 {",
            "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)",
            "                    min(keyboardFrame.minY, tabFrame.minY)",
            "            let safeTop = liveTop + verticalInset",
            "            let safeBottom = liveBottom - verticalInset",
            "            let receiverTop = liveTop + receiverInset",
            "            let receiverBottom = liveBottom - receiverInset",
            "            let receiverLeft = liveScrollFrame.minX + receiverInset",
            "            let receiverRight = liveScrollFrame.maxX - receiverInset",
            "            let receiverCapacity = receiverBottom - receiverTop",
            "            let minimumShift = max(",
            "            let maximumShift = min(",
            "                  minimumShift <= maximumShift,",
            "                  allTargetsAreContained || minimumShift > 0 else {",
            "            if allTargetsAreContained { break }",
            "            if minimumShift <= receiverCapacity {",
            "                let recognizedMinimum = max(\n" +
                "                    minimumShift,\n" +
                "                    minimumGestureDistance\n" +
                "                )",
            "                let recognizedMaximum = min(\n" +
                "                    maximumShift,\n" +
                "                    receiverCapacity\n" +
                "                )",
            "                guard recognizedMinimum <= recognizedMaximum else {",
            "                dragDistance = recognizedMaximum",
            "                let stagedDistance = min(\n" +
                "                    receiverCapacity,\n" +
                "                    minimumShift - minimumGestureDistance\n" +
                "                )",
            "                guard stagedDistance >= minimumGestureDistance else {",
            "                dragDistance = stagedDistance",
            "            guard dragDistance > 0,",
            "                  dragDistance >= minimumGestureDistance else {",
        ]
        for lock in workValidationGeometryLocks {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        let workValidationReceiverLocks = [
            "            let receiverFrame = CGRect(",
            "            let startPoint = CGPoint(\n" +
                "                x: receiverRight,\n" +
                "                y: receiverTop\n" +
                "            )",
            "            let endPoint = CGPoint(\n" +
                "                x: startPoint.x,\n" +
                "                y: startPoint.y + dragDistance\n" +
                "            )",
            "                  liveScrollFrame.contains(startPoint),",
            "                  liveScrollFrame.contains(endPoint),",
            "                  !fieldLabelFrame.contains(startPoint),",
            "                  !fieldLabelFrame.contains(endPoint),",
            "                  !descriptionFrame.contains(startPoint),",
            "                  !descriptionFrame.contains(endPoint),",
            "                  !validationFrame.contains(startPoint),",
            "                  !validationFrame.contains(endPoint) else {",
            "            let scrollOrigin = descriptionScrollView.coordinate(",
            "                    dx: startPoint.x - scrollFrame.minX,",
            "                    dy: startPoint.y - scrollFrame.minY",
            "                    dx: endPoint.x - scrollFrame.minX,",
            "                    dy: endPoint.y - scrollFrame.minY",
            "                forDuration: 0.2,",
            "                withVelocity: .slow,",
            "                thenHoldForDuration: 0.2",
        ]
        for lock in workValidationReceiverLocks {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        for (lock, count) in [
            (".coordinate(", 1),
            (".press(", 1),
            ("thenDragTo:", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }

        let workValidationProgressLocks = [
            "            let fieldLabelBeforeDrag = fieldLabelFrame.minY",
            "            let descriptionBeforeDrag = descriptionFrame.minY",
            "            let validationBeforeDrag = validationFrame.minY",
            "            let fieldLabelAfterDrag = shortDescriptionFieldLabel.frame",
            "            let descriptionAfterDrag = descriptionField.frame",
            "            let validationAfterDrag = validationLabel.frame",
            "                  observedFieldLabelShift > 0,",
            "                  observedDescriptionShift > 0,",
            "                  observedValidationShift > 0,",
            "                  observedFieldLabelShift * dragDistance > 0,",
            "                  observedDescriptionShift * dragDistance > 0,",
            "                  observedValidationShift * dragDistance > 0 else {",
            "                guard fieldLabelAfterDrag.minY > previousFieldLabelMinYAfterDrag,",
            "                      descriptionAfterDrag.minY > previousDescriptionMinYAfterDrag,",
            "                      validationAfterDrag.minY > previousValidationMinYAfterDrag else {",
            "            previousFieldLabelMinYAfterDrag = fieldLabelAfterDrag.minY",
            "            previousDescriptionMinYAfterDrag = descriptionAfterDrag.minY",
            "            previousValidationMinYAfterDrag = validationAfterDrag.minY",
            "                    && finalFieldLabelFrame.minY >= finalSafeTop",
            "                    && finalFieldLabelFrame.maxY <= finalSafeBottom",
            "                    && finalDescriptionFrame.minY >= finalSafeTop",
            "                    && finalDescriptionFrame.maxY <= finalSafeBottom",
            "                    && finalValidationFrame.minY >= finalSafeTop",
            "                    && finalValidationFrame.maxY <= finalSafeBottom",
            "                    && shortDescriptionFieldLabel.isHittable",
            "                    && descriptionField.isHittable",
            "                    && validationLabel.isHittable",
        ]
        for lock in workValidationProgressLocks {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        for lock in [
            "                  app.frame == frozenApplicationFrame,",
            "                  keyboard.frame == frozenKeyboardFrame else {",
        ] {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }

        let workValidationFailureMessages = [
            "AX-text work-validation positioning bindings are ambiguous.",
            "AX-text work-validation positioning route or focus changed.",
            "AX-text work-validation positioning geometry is invalid.",
            "AX-text work-validation composition has no supported downward interval.",
            "AX-text work-validation direct interval is not recognizable.",
            "AX-text work-validation staged remainder is not recognizable.",
            "AX-text work-validation drag direction is invalid.",
            "AX-text work-validation drag receiver is obstructed.",
            "AX-text work-validation route, focus, or keyboard changed after positioning.",
            "AX-text work-validation gesture made no signed triple-node progress.",
            "AX-text work-validation positioning reversed direction.",
            "AX-text work-validation final route, focus, or keyboard is invalid.",
            "AX-text work-validation final composition is unsafe.",
        ]
        var workValidationFailureSearchStart =
            workValidationPositioningHelperSource.startIndex
        for message in workValidationFailureMessages {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: message
                ).count - 1,
                1,
                message
            )
            guard let messageRange = workValidationPositioningHelperSource.range(
                of: message,
                range: workValidationFailureSearchStart ..<
                    workValidationPositioningHelperSource.endIndex
            ) else {
                XCTFail("Missing ordered work-validation positioning failure message")
                return
            }
            workValidationFailureSearchStart = messageRange.upperBound
        }
        for (lock, count) in [
            ("XCTFail(", 13),
            ("return false", 13),
            ("return true", 1),
            ("let hasExactRoute: () -> Bool", 1),
            ("hasExactRoute()", 3),
            (".firstMatch", 9),
        ] {
            XCTAssertEqual(
                workValidationPositioningHelperSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }
        for prohibitedWorkValidationPositioningForm in [
            ".tap(",
            ".swipe",
            "scroll(",
            "waitForExistence",
            "waitForNonExistence",
            ".typeText(",
            "Thread.sleep",
            "sleep(",
            "performAccessibilityAudit",
            "eligibleExceptions",
            "ContrastAuditExceptionSignature",
            "contrastAuditExceptionSignatures",
            "automationContrastExceptions",
            "AutomationConfigurationError",
            "captureBaseline(",
            "attachCandidate(",
            #"prefix: "S10_4_AX_STATE""#,
            #"prefix: "S10_4_CONTRAST""#,
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "tolerance",
            "epsilon",
            "CGRect(x:",
        ] {
            XCTAssertFalse(
                workValidationPositioningHelperSource.contains(
                    prohibitedWorkValidationPositioningForm
                ),
                prohibitedWorkValidationPositioningForm
            )
        }
        for removedWorkValidationDiagnosticForm in [
            "diagnoseAXTextWorkValidationContrast",
            "S10_4_WORK_VALIDATION_ROUTE_DIAGNOSTIC",
            "S10_4_WORK_VALIDATION_CONTRAST_DIAGNOSTIC",
            "S10_4_WORK_VALIDATION_CONTRAST_DIAGNOSTIC_COUNT",
            "S10.4 work-validation contrast diagnostic app",
            "S10.4 work-validation contrast diagnostic tree",
            "S10.4 work-validation contrast diagnostic work-route",
            "S10.4 work-validation contrast diagnostic element",
            "S10.4 AX-text Record-work validation contrast diagnostic",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedWorkValidationDiagnosticForm
                ).count - 1,
                0,
                removedWorkValidationDiagnosticForm
            )
            XCTAssertEqual(
                workflowSource.components(
                    separatedBy: removedWorkValidationDiagnosticForm
                ).count - 1,
                0,
                removedWorkValidationDiagnosticForm
            )
        }
        let preflightReturnAbsenceDiscriminator =
            #"            let returnKey = app.keyboards.buttons["Return"]"# + "\n" +
                #"            if !returnKey.waitForExistence(timeout: 1) || !returnKey.isHittable {"#
        XCTAssertEqual(
            preflightMinimumSource.components(
                separatedBy: preflightReturnAbsenceDiscriminator
            ).count - 1,
            1
        )
        XCTAssertFalse(preflightMinimumSource.contains("returnKey.exists"))

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
                preflightMinimumSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        guard let preflightOffAppStartRange = preflightMinimumSource.range(
            of: "                if keyboardIsOffApp {"
        ), let preflightVisibleStartRange = preflightMinimumSource.range(
            of: "\n                } else {",
            range: preflightOffAppStartRange.upperBound..<preflightMinimumSource.endIndex
        ) else {
            XCTFail("Missing the preflight keyboard class branches")
            return
        }
        let preflightOffAppSource = String(
            preflightMinimumSource[
                preflightOffAppStartRange.lowerBound..<preflightVisibleStartRange.lowerBound
            ]
        )
        let preflightVisibleSource = String(
            preflightMinimumSource[
                preflightVisibleStartRange.lowerBound..<preflightMinimumSource.endIndex
            ]
        )
        XCTAssertEqual(preflightVisibleSource.utf8.count, 31_479)
        XCTAssertEqual(
            Data(preflightVisibleSource.utf8).sha256,
            "27917894D5B077D615D52C4A1186C0C9941B03F31860625986839A9886C5CCFF"
        )
        let minimumPreflightQuickPathWrapperStart =
            "                    let minimumPreflightQuickPathIntroductionViews ="
        let minimumPreflightQuickPathCommonTailStart =
            "                    let restoredKeyboard = app.keyboards.firstMatch"
        guard let minimumPreflightQuickPathWrapperStartRange =
            preflightVisibleSource.range(
                of: minimumPreflightQuickPathWrapperStart
            ), let minimumPreflightQuickPathCommonTailStartRange =
            preflightVisibleSource.range(
                of: minimumPreflightQuickPathCommonTailStart,
                range:
                    minimumPreflightQuickPathWrapperStartRange.upperBound..<preflightVisibleSource.endIndex
            )
        else {
            XCTFail("Missing the minimum Preflight QuickPath wrapper/common-tail slices")
            return
        }
        let minimumPreflightQuickPathWrapperSource = String(
            preflightVisibleSource[
                minimumPreflightQuickPathWrapperStartRange.lowerBound ..<
                    minimumPreflightQuickPathCommonTailStartRange.lowerBound
            ]
        )
        let minimumPreflightQuickPathCommonTailSource = String(
            preflightVisibleSource[
                minimumPreflightQuickPathCommonTailStartRange.lowerBound..<preflightVisibleSource.endIndex
            ]
        )
        XCTAssertEqual(minimumPreflightQuickPathWrapperSource.utf8.count, 14_199)
        XCTAssertEqual(
            Data(minimumPreflightQuickPathWrapperSource.utf8).sha256,
            "B99E943C870A4FA3B6E042AC727F480ED4E84FF8B4527A7214A9E58778A91292"
        )
        XCTAssertEqual(minimumPreflightQuickPathCommonTailSource.utf8.count, 16_378)
        XCTAssertEqual(
            Data(minimumPreflightQuickPathCommonTailSource.utf8).sha256,
            "468D540185455C67D65AF09EB0B7207E1AE524CAE03A708A92216DC724AD9B1D"
        )
        let minimumDoubleLengthPositioningGate =
            "                    if automationShard?.shardID\n" +
                #"                        == "s10.4.minimum.double-length" {"#
        guard let minimumDoubleLengthPositioningStartRange =
            preflightOffAppSource.range(of: minimumDoubleLengthPositioningGate) else {
            XCTFail("Missing the minimum double-length off-app positioning slice")
            return
        }
        let minimumDoubleLengthPositioningSource = String(
            preflightOffAppSource[
                minimumDoubleLengthPositioningStartRange.lowerBound..<preflightOffAppSource.endIndex
            ]
        )
        let passivePreflightOffAppSource = String(
            preflightOffAppSource[
                preflightOffAppSource.startIndex..<minimumDoubleLengthPositioningStartRange.lowerBound
            ]
        )
        XCTAssertEqual(minimumDoubleLengthPositioningSource.utf8.count, 16_957)
        XCTAssertEqual(
            Data(minimumDoubleLengthPositioningSource.utf8).sha256,
            "72D734F5AA3860A8B2D18841D7568969433F7963D5E688CEFB0288F9E33BAE92"
        )
        XCTAssertEqual(
            preflightOffAppSource.components(
                separatedBy: minimumDoubleLengthPositioningGate
            ).count - 1,
            1
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
                passivePreflightOffAppSource.contains(prohibitedOffAppAction),
                prohibitedOffAppAction
            )
        }
        let normalizedMinimumDoubleLengthPositioningSource =
            minimumDoubleLengthPositioningSource
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        let minimumDoubleLengthPositioningLocks = [
            "if automationShard?.shardID\n" +
                #"== "s10.4.minimum.double-length" {"#,
            "let preflightTabBars = app.tabBars",
            "let confirmationLabel =\n" +
                #""I confirm this is the site's time zone. " +"# + "\n" +
                #""I confirm this is the site's time zone.""#,
            "let confirmationTexts = app.staticTexts.matching(\n" +
                "NSPredicate(\n" +
                #"format: "label == %@","# + "\n" +
                "confirmationLabel\n" +
                ")\n" +
                ")",
            "let preflightTabBar = preflightTabBars.firstMatch",
            "let confirmationText = confirmationTexts.firstMatch",
            "let observedAssistantFrame = inputAssistantFrame",
            "let verticalInset: CGFloat = 16",
            "let receiverInset: CGFloat = 24",
            "let minimumGestureDistance: CGFloat = 44",
            "var preflightPositioningDirection: CGFloat?",
            "for _ in 0..<4 {",
            "let liveApplicationFrame = app.frame",
            "let scrollFrame = preflightScrollView.frame",
            "let liveScrollFrame = scrollFrame.intersection(\n" +
                "liveApplicationFrame\n" +
                ")",
            "let navigationFrame = preflightNavigationBar.frame",
            "let tabBarFrame = preflightTabBar.frame",
            "let confirmationFrame = confirmationText.frame",
            "let liveBottom = min(\n" +
                "liveScrollFrame.maxY,\n" +
                "min(\n" +
                "liveApplicationFrame.maxY,\n" +
                "tabBarFrame.minY\n" +
                ")\n" +
                ")",
            "let safeTop = max(\n" +
                "liveScrollFrame.minY,\n" +
                "navigationFrame.maxY\n" +
                ") + verticalInset",
            "let safeBottom = liveBottom - verticalInset",
            "let receiverTop = max(\n" +
                "liveScrollFrame.minY,\n" +
                "navigationFrame.maxY\n" +
                ") + receiverInset",
            "let receiverBottom = liveBottom - receiverInset",
            "let minimumShift =\n" +
                "safeTop - confirmationFrame.minY",
            "let maximumShift =\n" +
                "safeBottom - confirmationFrame.maxY",
            "confirmationFrame.height\n" +
                "<= safeBottom - safeTop,\n" +
                "minimumShift <= maximumShift else {",
            "if confirmationFrame.minY >= safeTop,\n" +
                "confirmationFrame.maxY <= safeBottom {\n" +
                "break\n" +
                "}",
            "guard maximumShift < 0 else {",
            "let receiverCapacity = receiverBottom - receiverTop",
            "guard receiverCapacity >= minimumGestureDistance else {",
            "if maximumShift > -minimumGestureDistance {",
            "let recognizedResidualDistance =\n" +
                "-minimumGestureDistance",
            "guard minimumShift\n" +
                "<= recognizedResidualDistance else {",
            "dragDistance = recognizedResidualDistance",
            "} else if abs(maximumShift) <= receiverCapacity {\n" +
                "dragDistance = maximumShift\n" +
                "} else {",
            "let stagedDistance = max(\n" +
                "-receiverCapacity,\n" +
                "maximumShift + minimumGestureDistance\n" +
                ")",
            "guard stagedDistance\n" +
                "<= -minimumGestureDistance else {",
            "dragDistance = stagedDistance",
            "let dragDirection: CGFloat = dragDistance > 0\n" +
                "? 1\n" +
                ": -1",
            "if let preflightPositioningDirection {\n" +
                "guard dragDirection\n" +
                "== preflightPositioningDirection else {",
            "preflightPositioningDirection = dragDirection",
            "let dragStartPoint = CGPoint(\n" +
                "x: liveScrollFrame.minX + receiverInset,\n" +
                "y: receiverBottom\n" +
                ")",
            "guard liveScrollFrame.contains(dragStartPoint),\n" +
                "!zone.frame.contains(dragStartPoint) else {",
            #""The minimum double-length preflight drag receiver overlaps the focused time-zone field.""#,
            "let scrollOrigin = preflightScrollView.coordinate(\n" +
                "withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                ")",
            "dx: dragStartPoint.x - scrollFrame.minX",
            "dy: receiverBottom - scrollFrame.minY",
            "let dragEnd = dragStart.withOffset(\n" +
                "CGVector(dx: 0, dy: dragDistance)\n" +
                ")",
            "dragStart.press(\n" +
                "forDuration: 0.2,\n" +
                "thenDragTo: dragEnd,\n" +
                "withVelocity: .slow,\n" +
                "thenHoldForDuration: 0.2\n" +
                ")",
            "let confirmationMovement =\n" +
                "confirmationText.frame.minY\n" +
                "- confirmationMinYBeforeDrag",
            "guard confirmationMovement * dragDistance > 0 else {",
            "let finalApplicationFrame = app.frame",
            "let finalScrollFrame = preflightScrollView.frame.intersection(\n" +
                "finalApplicationFrame\n" +
                ")",
            "let finalNavigationFrame = preflightNavigationBar.frame",
            "let finalTabBarFrame = preflightTabBar.frame",
            "let finalConfirmationFrame = confirmationText.frame",
            "let finalSafeTop = max(\n" +
                "finalScrollFrame.minY,\n" +
                "finalNavigationFrame.maxY\n" +
                ") + verticalInset",
            "let finalSafeBottom = min(\n" +
                "finalScrollFrame.maxY,\n" +
                "min(\n" +
                "finalApplicationFrame.maxY,\n" +
                "finalTabBarFrame.minY\n" +
                ")\n" +
                ") - verticalInset",
            "preflight.exists\n" +
                "== preActionPreflightExists,\n" +
                "detailRoute.exists\n" +
                "== preActionDetailRouteExists,",
            "wait(\n" +
                "for: zone,\n" +
                #"predicate: "hasKeyboardFocus == true","# + "\n" +
                "timeout: 10\n" +
                ")",
            "zone.label == preActionZoneLabel,\n" +
                "(zone.value as? String)\n" +
                "== preActionZoneValue,",
            "afterDark.label == preActionAfterDarkLabel,\n" +
                "(afterDark.value as? String)\n" +
                "== preActionAfterDarkValue,",
            "safePosition.label\n" +
                "== preActionSafePositionLabel,\n" +
                "(safePosition.value as? String)\n" +
                "== preActionSafePositionValue,",
            "finalConfirmationFrame.minY >= finalSafeTop,\n" +
                "finalConfirmationFrame.maxY <= finalSafeBottom else {",
        ]
        for lock in minimumDoubleLengthPositioningLocks {
            XCTAssertEqual(
                normalizedMinimumDoubleLengthPositioningSource.components(
                    separatedBy: lock
                ).count - 1,
                1,
                lock
            )
        }
        guard let recognizedResidualBranch =
            normalizedMinimumDoubleLengthPositioningSource.range(
                of: "if maximumShift > -minimumGestureDistance {"
            ), let directMaximumShiftBranch =
            normalizedMinimumDoubleLengthPositioningSource.range(
                of: "} else if abs(maximumShift) <= receiverCapacity {"
            ), let stagedMaximumShiftBranch =
            normalizedMinimumDoubleLengthPositioningSource.range(
                of: "let stagedDistance = max("
            ) else {
            XCTFail("Missing the minimum double-length residual branch order")
            return
        }
        XCTAssertLessThan(
            recognizedResidualBranch.lowerBound,
            directMaximumShiftBranch.lowerBound
        )
        XCTAssertLessThan(
            directMaximumShiftBranch.lowerBound,
            stagedMaximumShiftBranch.lowerBound
        )
        for (lock, count) in [
            ("preflightScrollViews.count == 1", 3),
            ("preflightNavigationBars.count == 1", 3),
            ("preflightTabBars.count == 1", 3),
            ("confirmationTexts.count == 1", 3),
            ("inputAssistantViews.count == 1", 3),
            ("preflightScrollView.exists", 3),
            ("preflightNavigationBar.exists", 3),
            ("preflightTabBar.exists", 3),
            ("confirmationText.exists", 3),
            ("confirmationText.identifier.isEmpty", 3),
            ("confirmationText.elementType == .staticText", 3),
            ("confirmationText.label == confirmationLabel", 3),
            ("keyboardIsAbsentOrInertOffApp(in: app)", 3),
            ("preflightPositioningDirection", 4),
            ("dragDirection", 3),
            ("dragStartPoint", 4),
            ("CGPoint(", 1),
            ("zone.frame", 1),
            ("preflightScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                minimumDoubleLengthPositioningSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }
        let minimumDoubleLengthFinalGuardTail =
            "                              finalConfirmationFrame.minY >= finalSafeTop,\n" +
                "                              finalConfirmationFrame.maxY <= finalSafeBottom else {\n" +
                "                            XCTFail(\n" +
                #"                                "The minimum double-length preflight confirmation was not fully contained before capture.""# +
                "\n                            )\n" +
                "                            return\n" +
                "                        }\n" +
                "                    }"
        XCTAssertTrue(
            minimumDoubleLengthPositioningSource.hasSuffix(
                minimumDoubleLengthFinalGuardTail
            )
        )
        for prohibitedMinimumDoubleLengthPositioningForm in [
            "626.012451171875",
            "1123.512451171875",
            "497.5",
            "-521.512451171875",
            "711",
            "scrollFrame.width / 2",
            "app.coordinate(",
            "keyboard.coordinate(",
            ".swipe",
            ".tap(",
            "scroll(",
            "typeText(",
            "dismissKeyboard(",
            "setToggle(",
            "Thread.sleep",
            "Task.sleep",
            "sleep(",
            "tolerance",
            "epsilon",
            "abs(maximumShift)\n>= minimumGestureDistance",
            "maximumShift >= -minimumGestureDistance",
            "recognizedResidualDistance = minimumGestureDistance",
            "recognizedResidualDistance = maximumShift",
            "minimumShift >= recognizedResidualDistance",
            "performAccessibilityAudit",
            "automationContrastExceptions",
            "matchingExceptions",
            "captureBaseline(",
            "attachCandidate(",
            "S10_4_AX_STATE",
            "S10_4_CONTRAST",
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
        ] {
            XCTAssertFalse(
                minimumDoubleLengthPositioningSource.contains(
                    prohibitedMinimumDoubleLengthPositioningForm
                ),
                prohibitedMinimumDoubleLengthPositioningForm
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
                preflightMinimumSource.components(separatedBy: lock).count - 1,
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
            preflightMinimumSource.components(separatedBy: preflightPrecondition).count - 1,
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
            preflightMinimumSource.components(
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
        let minimumPreflightQuickPathStructureLocks = [
            "let minimumPreflightQuickPathIntroductionViews =",
            "app.descendants(matching: .other).matching(",
            #"identifier: "UIContinuousPathIntroductionView""#,
            "let minimumPreflightQuickPathIntroductionCount =",
            "if minimumPreflightQuickPathIntroductionCount > 0 {",
            "minimumPreflightQuickPathIntroductionView.descendants(",
            "matching: .button",
            "matching: .staticText",
            "let minimumPreflightQuickPathButton =",
            "let minimumPreflightQuickPathFirstStaticText =",
            "let minimumPreflightQuickPathSecondStaticText =",
            "boundBy: 0",
            "boundBy: 1",
            "let minimumPreflightQuickPathFrameIsValid:",
            "minimumPreflightQuickPathIntroductionCount == 1",
            "minimumPreflightQuickPathButtons.count == 1",
            "minimumPreflightQuickPathStaticTexts.count == 2",
            ".elementType == .other",
            "minimumPreflightQuickPathButton.elementType\n" +
                "                                == .button",
            ".elementType == .staticText",
            ".identifier.isEmpty",
            ".trimmingCharacters(",
            "in: .whitespacesAndNewlines",
            "minimumPreflightQuickPathButton.isEnabled",
            "minimumPreflightQuickPathButton.isHittable",
            "&& !frame.isInfinite",
            "&& frame.origin.x.isFinite",
            "&& frame.origin.y.isFinite",
            "&& frame.size.width.isFinite",
            "&& frame.size.height.isFinite",
            "applicationFrame.contains(",
            ".intersects(observedKeyboardFrame)",
            "!= (minimumPreflightQuickPathSecondStaticText.label",
            "? minimumPreflightQuickPathSecondStaticText",
            "? minimumPreflightQuickPathFirstStaticText",
            "* 0.8425925925925926",
            ".waitForNonExistence(timeout: 10)",
            "minimumPreflightQuickPathIntroductionViews.count",
            "minimumPreflightQuickPathButtons.count == 0",
            "minimumPreflightQuickPathStaticTexts.count == 0",
        ]
        for lock in minimumPreflightQuickPathStructureLocks {
            XCTAssertTrue(
                minimumPreflightQuickPathWrapperSource.contains(lock),
                lock
            )
        }
        for (lock, count) in [
            ("minimumPreflightQuickPathIntroductionCount == 1", 1),
            ("minimumPreflightQuickPathButtons.count == 1", 1),
            ("minimumPreflightQuickPathStaticTexts.count == 2", 1),
            ("minimumPreflightQuickPathButtons.count == 0", 1),
            ("minimumPreflightQuickPathStaticTexts.count == 0", 1),
            ("keyboard.coordinate(", 1),
            (".waitForNonExistence(timeout: 10)", 1),
            ("XCTFail(", 2),
        ] {
            XCTAssertEqual(
                minimumPreflightQuickPathWrapperSource.components(
                    separatedBy: lock
                ).count - 1,
                count,
                lock
            )
        }
        let minimumPreflightQuickPathCardinality =
            "                        guard minimumPreflightQuickPathIntroductionCount == 1,\n" +
                "                              minimumPreflightQuickPathButtons.count == 1,\n" +
                "                              minimumPreflightQuickPathStaticTexts.count == 2,"
        let minimumPreflightQuickPathFirstProperty =
            "                              minimumPreflightQuickPathIntroductionView.exists,"
        let minimumPreflightQuickPathLastFrameValidator =
            "                              minimumPreflightQuickPathFrameIsValid(\n" +
                "                                  minimumPreflightQuickPathSecondStaticText.frame\n" +
                "                              ),"
        let minimumPreflightQuickPathFirstGeometry =
            "                              applicationFrame.contains("
        let minimumPreflightQuickPathAction =
            "                        keyboard.coordinate("
        let minimumPreflightQuickPathWait =
            "                        guard minimumPreflightQuickPathIntroductionView\n" +
                "                                .waitForNonExistence(timeout: 10),"
        guard let minimumPreflightQuickPathCardinalityRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathCardinality
            ), let minimumPreflightQuickPathFirstPropertyRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathFirstProperty
            ), let minimumPreflightQuickPathLastFrameValidatorRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathLastFrameValidator
            ), let minimumPreflightQuickPathFirstGeometryRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathFirstGeometry
            ), let minimumPreflightQuickPathActionRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathAction
            ), let minimumPreflightQuickPathWaitRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathWait
            )
        else {
            XCTFail("Missing the ordered minimum Preflight QuickPath contract")
            return
        }
        XCTAssertLessThan(
            minimumPreflightQuickPathCardinalityRange.lowerBound,
            minimumPreflightQuickPathFirstPropertyRange.lowerBound
        )
        XCTAssertLessThan(
            minimumPreflightQuickPathFirstPropertyRange.lowerBound,
            minimumPreflightQuickPathLastFrameValidatorRange.lowerBound
        )
        XCTAssertLessThan(
            minimumPreflightQuickPathLastFrameValidatorRange.lowerBound,
            minimumPreflightQuickPathFirstGeometryRange.lowerBound
        )
        XCTAssertLessThan(
            minimumPreflightQuickPathFirstGeometryRange.lowerBound,
            minimumPreflightQuickPathActionRange.lowerBound
        )
        XCTAssertLessThan(
            minimumPreflightQuickPathActionRange.lowerBound,
            minimumPreflightQuickPathWaitRange.lowerBound
        )
        let minimumPreflightQuickPathButtonPointContainment =
            "                              minimumPreflightQuickPathButton.frame.contains(\n" +
                "                                  CGPoint(\n" +
                "                                      x: observedKeyboardFrame.midX,\n" +
                "                                      y: observedKeyboardFrame.minY\n" +
                "                                        + observedKeyboardFrame.height\n" +
                "                                            * 0.8425925925925926\n" +
                "                                  )\n" +
                "                              ),"
        XCTAssertEqual(
            minimumPreflightQuickPathWrapperSource.components(
                separatedBy: minimumPreflightQuickPathButtonPointContainment
            ).count - 1,
            1
        )
        let minimumPreflightQuickPathPositiveGate =
            "                    if minimumPreflightQuickPathIntroductionCount > 0 {"
        guard let minimumPreflightQuickPathPositiveGateRange =
            minimumPreflightQuickPathWrapperSource.range(
                of: minimumPreflightQuickPathPositiveGate
            )
        else {
            XCTFail("Missing the minimum Preflight QuickPath positive gate")
            return
        }
        let minimumPreflightQuickPathZeroPrefix = String(
            minimumPreflightQuickPathWrapperSource[
                minimumPreflightQuickPathWrapperSource.startIndex ..<
                    minimumPreflightQuickPathPositiveGateRange.lowerBound
            ]
        )
        for prohibitedZeroPathAction in [
            ".tap()",
            ".waitForNonExistence(",
            ".coordinate(",
            ".press(",
            ".swipe",
        ] {
            XCTAssertFalse(
                minimumPreflightQuickPathZeroPrefix.contains(
                    prohibitedZeroPathAction
                ),
                prohibitedZeroPathAction
            )
        }
        let minimumPreflightQuickPathToCommonTailAdjacency =
            "                    }\n" +
                minimumPreflightQuickPathCommonTailStart
        XCTAssertEqual(
            preflightVisibleSource.components(
                separatedBy: minimumPreflightQuickPathToCommonTailAdjacency
            ).count - 1,
            1
        )
        XCTAssertTrue(
            minimumPreflightQuickPathWrapperSource.hasSuffix(
                "                    }\n"
            )
        )
        XCTAssertLessThan(
            minimumPreflightQuickPathPositiveGateRange.lowerBound,
            minimumPreflightQuickPathActionRange.lowerBound
        )
        for (action, count) in [
            (".coordinate(", 1),
            (".tap()", 1),
            (".waitForNonExistence(timeout: 10)", 1),
            (".press(", 0),
            (".swipe", 0),
            ("typeText(", 0),
            ("scroll(", 0),
            ("dismissKeyboard(", 0),
            ("minimumPreflightQuickPathButton.tap()", 0),
            ("buttons[\"Done\"].tap()", 0),
            ("buttons[\"Return\"].tap()", 0),
        ] {
            XCTAssertEqual(
                minimumPreflightQuickPathWrapperSource.components(
                    separatedBy: action
                ).count - 1,
                count,
                action
            )
        }
        let minimumPreflightQuickPathStructureFailure =
            #"                            XCTFail("The minimum-profile preflight QuickPath tutorial is incomplete or state changed before dismissal.")"# +
                "\n                            return"
        let minimumPreflightQuickPathDismissalFailure =
            #"                            XCTFail("The minimum-profile preflight QuickPath tutorial did not dismiss with state preserved.")"# +
                "\n                            return"
        for failure in [
            minimumPreflightQuickPathStructureFailure,
            minimumPreflightQuickPathDismissalFailure,
        ] {
            XCTAssertEqual(
                minimumPreflightQuickPathWrapperSource.components(
                    separatedBy: failure
                ).count - 1,
                1,
                failure
            )
        }
        for prohibitedMinimumPreflightQuickPathForm in [
            #"label == "Continue""#,
            #"label == "Continuer""#,
            "NSPredicate(",
            "label == %@",
            "CONTAINS",
            "BEGINSWITH",
            "localized",
            "folding(",
            "precomposedStringWithCanonicalMapping",
            "minimumPreflightQuickPathButton.tap()",
            "app.keyboards.buttons[\"Done\"].tap()",
            "app.keyboards.buttons[\"Return\"].tap()",
            "app.coordinate(",
            "Thread.sleep",
            "Task.sleep",
            "tolerance",
            "epsilon",
            "automationShard",
            "deviceProfileID",
            "shardID",
            "private func",
            "func minimumPreflightQuickPath",
            "CGRect(",
            "performAccessibilityAudit",
            "automationContrastExceptions",
            "matchingExceptions",
            "printJSONLine",
            "captureBaseline(",
            "attachCandidate(",
            "S10_4_AX_STATE",
            "S10_4_CONTRAST",
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
        ] {
            XCTAssertFalse(
                minimumPreflightQuickPathWrapperSource.contains(
                    prohibitedMinimumPreflightQuickPathForm
                ),
                prohibitedMinimumPreflightQuickPathForm
            )
        }
        XCTAssertFalse(
            minimumPreflightQuickPathCommonTailSource.contains(
                "minimumPreflightQuickPathIntroduction"
            )
        )
        XCTAssertFalse(
            minimumPreflightQuickPathCommonTailSource.contains(
                "keyboard.coordinate("
            )
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
                preflightMinimumSource.contains(prohibitedVisiblePreflightForm),
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
                preflightMinimumSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        XCTAssertEqual(
            preflightMinimumSource.components(separatedBy: "XCTFail(").count - 1,
            28
        )
        XCTAssertEqual(
            preflightMinimumSource.components(separatedBy: "                    return\n").count - 1,
            28
        )
        XCTAssertFalse(
            preflightMinimumSource.contains(
                "guard returnKey.waitForExistence(timeout: 10)"
            )
        )
        let preflightFinalFailure =
            "                        XCTFail(\"The visible preflight state was not fully restored and positioned before capture.\")\n" +
                "                        return\n" +
                "                    }"
        XCTAssertEqual(
            preflightMinimumSource.components(
                separatedBy: preflightFinalFailure
            ).count - 1,
            1
        )
        let currentProfileQuickPathPrecededByMinimumFinalGuard =
            preflightFinalFailure + "\n                }\n            }\n        }\n" +
                currentProfilePreflightQuickPathGate
        XCTAssertEqual(
            uiSource.components(
                separatedBy: currentProfileQuickPathPrecededByMinimumFinalGuard
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
        XCTAssertEqual(keyboardHelperSource.utf8.count, 4_642)
        XCTAssertEqual(
            Data(keyboardHelperSource.utf8).sha256,
            "66F70CC92E6E0EB967845B2407F6F018386B24C8CB97C59C6A6BAFDFF5C08A28"
        )

        let keyboardSnapshotHelperStart =
            "    @MainActor\n" +
                "    private func keyboardSnapshotTreeIsFullyInertOffApp("
        let keyboardSnapshotHelperEnd =
            "\n\n    @MainActor\n" +
                "    private func keyboardIsAbsentOrInertOffApp("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: keyboardSnapshotHelperStart
            ).count - 1,
            1
        )
        guard let keyboardSnapshotHelperStartRange = uiSource.range(
            of: keyboardSnapshotHelperStart
        ), let keyboardSnapshotHelperEndRange = uiSource.range(
            of: keyboardSnapshotHelperEnd,
            range: keyboardSnapshotHelperStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the shared passive keyboard snapshot helper")
            return
        }
        let keyboardSnapshotHelperSource = String(
            uiSource[
                keyboardSnapshotHelperStartRange.lowerBound..<keyboardSnapshotHelperEndRange.lowerBound
            ]
        )
        XCTAssertEqual(keyboardSnapshotHelperSource.utf8.count, 1_414)
        XCTAssertEqual(
            Data(keyboardSnapshotHelperSource.utf8).sha256,
            "B21B236F52CDA9BEE865D20A435F09C60F2BD97D248C3B61E03048C487CF4084"
        )
        let keyboardSnapshotHelperContracts = [
            "        keyboard: XCUIElement,",
            "        descendants: XCUIElementQuery,",
            "        descendantCount: Int,",
            "        keyCount: Int,",
            "        applicationFrame: CGRect",
            "        guard let keyboardSnapshot = try? keyboard.snapshot() else {",
            "        var descendantSnapshots: [any XCUIElementSnapshot] = []",
            "        func appendDescendantSnapshots(",
            "            from snapshot: any XCUIElementSnapshot",
            "            for child in snapshot.children {",
            "                descendantSnapshots.append(child)",
            "                appendDescendantSnapshots(from: child)",
            "        appendDescendantSnapshots(from: keyboardSnapshot)",
            "        let snapshotKeyCount = descendantSnapshots.filter {",
            "            $0.elementType == .key",
            "        let focusedDescendantCount = descendants.matching(",
            #"                format: "hasKeyboardFocus == true""#,
            "        return descendantSnapshots.count == descendantCount",
            "            && snapshotKeyCount == keyCount",
            "            && descendantSnapshots.allSatisfy { snapshot in",
            "                let snapshotFrame = snapshot.frame",
            "                    && snapshotFrame.minY >= applicationFrame.maxY",
            "            && focusedDescendantCount == 0",
        ]
        for contract in keyboardSnapshotHelperContracts {
            XCTAssertTrue(
                keyboardSnapshotHelperSource.contains(contract),
                contract
            )
        }
        for (fragment, count) in [
            ("keyboard.snapshot()", 1),
            ("snapshot.children", 1),
            ("appendDescendantSnapshots", 3),
            ("descendantSnapshots.count", 1),
            ("snapshotKeyCount", 2),
            ("elementType == .key", 1),
            ("hasKeyboardFocus == true", 1),
            ("descendants.matching(", 1),
            ("focusedDescendantCount", 2),
            ("allSatisfy { snapshot in", 1),
            ("snapshot.frame", 1),
            ("snapshotFrame.minY >= applicationFrame.maxY", 1),
            ("focusedDescendantCount == 0", 1),
        ] {
            XCTAssertEqual(
                keyboardSnapshotHelperSource.components(
                    separatedBy: fragment
                ).count - 1,
                count,
                fragment
            )
        }
        for prohibitedKeyboardTreeForm in [
            "keyboardDescendantElements",
            "keyboardKeyElements",
            "isWhollyOffAppAndInert",
            "allElementsBoundByIndex",
            "hasKeyboardFocus == true OR hittable == true",
            "hittable == true",
            "isHittable",
            "interactiveDescendantCount",
        ] {
            XCTAssertFalse(
                keyboardSnapshotHelperSource.contains(prohibitedKeyboardTreeForm),
                prohibitedKeyboardTreeForm
            )
        }

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
            7
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
        XCTAssertEqual(passiveKeyboardHelperSource.utf8.count, 1_992)
        XCTAssertEqual(
            Data(passiveKeyboardHelperSource.utf8).sha256,
            "2FC52BA367EF6E10CA1095E4F61D08C9680E98888EB60D997CA9184654B86F1D"
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
            "        let focusIsAbsent = NSPredicate(\n" +
                #"            format: "hasKeyboardFocus == false""# + "\n" +
                "        )",
            "        let keyboardFocusIsAbsent = focusIsAbsent.evaluate(with: keyboard)",
            "        let keyboardTreeIsEmpty =\n" +
                "            keyboardDescendantCount == 0\n" +
                "            && keyboardKeyCount == 0",
            "        let keyboardTreeIsNonemptyAndInert =\n" +
                "            keyboardDescendantCount > 0\n" +
                "            && keyboardKeyCount > 0\n" +
                "            && keyboardKeyCount <= keyboardDescendantCount\n" +
                "            && keyboardSnapshotTreeIsFullyInertOffApp(\n" +
                "                keyboard: keyboard,\n" +
                "                descendants: keyboardDescendants,\n" +
                "                descendantCount: keyboardDescendantCount,\n" +
                "                keyCount: keyboardKeyCount,\n" +
                "                applicationFrame: applicationFrame\n" +
                "            )",
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
            ("matching: .any", 1),
            ("let keyboardKeys = keyboard.keys", 1),
            ("focusIsAbsent", 2),
            ("keyboardFocusIsAbsent", 2),
            ("keyboardSnapshotTreeIsFullyInertOffApp(", 1),
            ("keyboardTreeIsEmpty", 2),
            ("keyboardTreeIsNonemptyAndInert", 2),
            ("keyboardDescendantCount == 0", 1),
            ("keyboardKeyCount == 0", 1),
            ("keyboardDescendantCount > 0", 1),
            ("keyboardKeyCount > 0", 1),
            ("keyboardKeyCount <= keyboardDescendantCount", 1),
            ("return false", 2),
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
            "keyboardDescendantElements",
            "keyboardKeyElements",
            "isWhollyOffAppAndInert",
            "allElementsBoundByIndex",
            "allSatisfy(",
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
                "                let focusIsAbsent = NSPredicate(\n" +
                #"                    format: "hasKeyboardFocus == false""# + "\n" +
                "                )\n" +
                "                let keyboardFocusIsAbsent = focusIsAbsent.evaluate(with: keyboard)\n" +
                "                let keyboardTreeIsEmpty =\n" +
                "                    keyboardDescendantCount == 0\n" +
                "                    && keyboardKeyCount == 0\n" +
                "                let keyboardTreeIsNonemptyAndInert =\n" +
                "                    keyboardDescendantCount > 0\n" +
                "                    && keyboardKeyCount > 0\n" +
                "                    && keyboardKeyCount <= keyboardDescendantCount\n" +
                "                    && keyboardSnapshotTreeIsFullyInertOffApp(\n" +
                "                        keyboard: keyboard,\n" +
                "                        descendants: keyboardDescendants,\n" +
                "                        descendantCount: keyboardDescendantCount,\n" +
                "                        keyCount: keyboardKeyCount,\n" +
                "                        applicationFrame: postSwipeApplicationFrame\n" +
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
            "let focusIsAbsent = NSPredicate(",
            #"format: "hasKeyboardFocus == false""#,
            "focusIsAbsent.evaluate(with: keyboard)",
            "keyboardSnapshotTreeIsFullyInertOffApp(",
            "let keyboardTreeIsEmpty =",
            "let keyboardTreeIsNonemptyAndInert =",
            "postSwipeKeyboardFrame.minY >= postSwipeApplicationFrame.maxY",
            "keyboardDescendantCount == 0",
            "keyboardKeyCount == 0",
            "keyboardDescendantCount > 0",
            "keyboardKeyCount > 0",
            "keyboardKeyCount <= keyboardDescendantCount",
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
        for staleKeyboardTreeForm in [
            "keyboardDescendantElements",
            "keyboardKeyElements",
            "isWhollyOffAppAndInert",
            "allElementsBoundByIndex",
            "allSatisfy("
        ] {
            XCTAssertFalse(
                passiveKeyboardHelperSource.contains(staleKeyboardTreeForm),
                staleKeyboardTreeForm
            )
            XCTAssertFalse(
                keyboardHelperSource.contains(staleKeyboardTreeForm),
                staleKeyboardTreeForm
            )
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
            "focusIsAbsent": 2,
            "keyboardFocusIsAbsent": 2,
            "keyboardSnapshotTreeIsFullyInertOffApp(": 1,
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
                "    private func keyboardSnapshotTreeIsFullyInertOffApp("
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
        XCTAssertEqual(multilineHelperSource.utf8.count, 12_512)
        XCTAssertEqual(
            Data(multilineHelperSource.utf8).sha256,
            "4054F7E02F879E7A3647BB799720180F13C2F935F9BB7E19B3399E596004BC88"
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
            "(field.elementType == .textField || field.elementType == .textView)",
            "!field.identifier.isEmpty",
            "expectedRouteExists",
            "expectedApplicationState == .runningForeground",
            #"let expectedValue = String(describing: field.value ?? "")"#,
            "let fieldScrollViews = app.scrollViews.containing(",
            "field.elementType,",
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
        let multilineQuickPathLocks = [
            "if field.elementType == .textView {",
            "let quickPathIntroductionViews = app.descendants(",
            "matching: .other",
            #"identifier: "UIContinuousPathIntroductionView""#,
            "let quickPathIntroductionCount =",
            "if quickPathIntroductionCount > 0 {",
            "let quickPathIntroductionView =",
            "let quickPathButtons =",
            "quickPathIntroductionView.descendants(",
            "matching: .button",
            "let quickPathStaticTexts =",
            "matching: .staticText",
            "let quickPathButtonCount = quickPathButtons.count",
            "let quickPathStaticTextCount = quickPathStaticTexts.count",
            "quickPathButtons.firstMatch",
            "let quickPathFirstStaticText =",
            "quickPathStaticTexts.element(boundBy: 0)",
            "let quickPathSecondStaticText =",
            "quickPathStaticTexts.element(boundBy: 1)",
            "quickPathIntroductionCount == 1",
            "quickPathButtonCount == 1",
            "quickPathStaticTextCount == 2",
            #"let quickPathReturnKey = keyboard.buttons["Return"]"#,
            #"format: "hasKeyboardFocus == true""#,
            "let expectedApplicationFrame = app.frame",
            "let expectedRouteFrame = route.frame",
            "let expectedFieldFrame = field.frame",
            "let expectedFieldScrollViewFrame = fieldScrollView.frame",
            "let expectedKeyboardFrame = keyboard.frame",
            "let expectedClearedValidationExists =",
            "let frameIsValid: (CGRect) -> Bool = { frame in",
            "quickPathIntroductionView.elementType == .other",
            "quickPathContinueButton.elementType == .button",
            "quickPathContinueButton.identifier.isEmpty",
            "quickPathContinueButton.label.trimmingCharacters(",
            "quickPathContinueButton.isEnabled",
            "quickPathContinueButton.isHittable",
            "quickPathFirstStaticText.elementType == .staticText",
            "quickPathFirstStaticText.identifier.isEmpty",
            "quickPathFirstStaticText.label.trimmingCharacters(",
            "quickPathSecondStaticText.elementType == .staticText",
            "quickPathSecondStaticText.identifier.isEmpty",
            "quickPathSecondStaticText.label.trimmingCharacters(",
            "quickPathReturnKey.elementType == .button",
            #"quickPathReturnKey.identifier == "Return""#,
            #"quickPathReturnKey.label.lowercased() == "return""#,
            "!quickPathReturnKey.isHittable",
            "fieldFocusPredicate.evaluate(with: field)",
            "!expectedClearedValidationExists",
            "frameIsValid(quickPathIntroductionView.frame)",
            "frameIsValid(quickPathContinueButton.frame)",
            "frameIsValid(quickPathFirstStaticText.frame)",
            "frameIsValid(quickPathSecondStaticText.frame)",
            "frameIsValid(quickPathReturnKey.frame)",
            "expectedApplicationFrame.contains(",
            "quickPathIntroductionView.frame.contains(",
            "expectedKeyboardFrame.contains(",
            "let buttonLabel = quickPathContinueButton.label",
            "let firstLabel = quickPathFirstStaticText.label",
            "let secondLabel = quickPathSecondStaticText.label",
            "let firstIsActionTitle = firstLabel == buttonLabel",
            "let secondIsActionTitle = secondLabel == buttonLabel",
            "firstIsActionTitle != secondIsActionTitle",
            "let actionTitle = firstIsActionTitle",
            "let tutorialText = firstIsActionTitle",
            "let actionTitleFrame = actionTitle.frame",
            "let tutorialFrame = tutorialText.frame",
            "let buttonFrame = quickPathContinueButton.frame",
            "actionTitleFrame.intersects(buttonFrame)",
            "tutorialText.label != buttonLabel",
            "tutorialFrame.maxY <= actionTitleFrame.minY",
            "tutorialFrame.maxY <= buttonFrame.minY",
            "!tutorialFrame.intersects(actionTitleFrame)",
            "!tutorialFrame.intersects(buttonFrame)",
            "The multiline TextView QuickPath tutorial is incomplete or state changed before dismissal.",
            "let expectedReturnFrame = quickPathReturnKey.frame",
            "quickPathContinueButton.tap()",
            "quickPathIntroductionView.waitForNonExistence(",
            "quickPathIntroductionViews.count == 0",
            "quickPathButtons.count == 0",
            "quickPathStaticTexts.count == 0",
            "quickPathReturnKey.isHittable",
            "field.elementType == .textView",
            "app.frame == expectedApplicationFrame",
            "route.frame == expectedRouteFrame",
            "field.frame == expectedFieldFrame",
            "fieldScrollView.frame",
            "== expectedFieldScrollViewFrame",
            "keyboard.frame == expectedKeyboardFrame",
            "quickPathReturnKey.frame == expectedReturnFrame",
            "The multiline TextView QuickPath tutorial did not dismiss with state preserved.",
        ]
        for lock in multilineQuickPathLocks {
            XCTAssertTrue(multilineHelperSource.contains(lock), lock)
        }
        guard let quickPathCardinalityBranchRange = multilineHelperSource.range(
            of: "if quickPathIntroductionCount > 0 {"
        ),
              let quickPathExactCardinalityRange = multilineHelperSource.range(
                of: "guard quickPathIntroductionCount == 1,\n" +
                    "                      quickPathButtonCount == 1,\n" +
                    "                      quickPathStaticTextCount == 2,"
              ),
              let quickPathFirstPropertyRange = multilineHelperSource.range(
                of: "quickPathIntroductionView.exists"
              ),
              let quickPathFinalFrameValidityRange = multilineHelperSource.range(
                of: "frameIsValid(quickPathReturnKey.frame)"
              ),
              let quickPathFirstGeometryRange = multilineHelperSource.range(
                of: "expectedApplicationFrame.contains("
              ),
              let quickPathRoleSelectionRange = multilineHelperSource.range(
                of: "let buttonLabel = quickPathContinueButton.label"
              ) else {
            XCTFail("Missing cardinality-before-property or frame-before-role ordering")
            return
        }
        XCTAssertLessThan(
            quickPathCardinalityBranchRange.lowerBound,
            quickPathExactCardinalityRange.lowerBound
        )
        XCTAssertLessThan(
            quickPathExactCardinalityRange.lowerBound,
            quickPathFirstPropertyRange.lowerBound
        )
        XCTAssertLessThan(
            quickPathFinalFrameValidityRange.lowerBound,
            quickPathFirstGeometryRange.lowerBound
        )
        XCTAssertLessThan(
            quickPathFirstGeometryRange.lowerBound,
            quickPathRoleSelectionRange.lowerBound
        )
        guard let actionableScrollViewRange = multilineHelperSource.range(
            of: "guard fieldScrollView.exists, fieldScrollView.isHittable else {"
        ),
              let quickPathBranchRange = multilineHelperSource.range(
                of: "if field.elementType == .textView {"
              ),
              let quickPathTapRange = multilineHelperSource.range(
                of: "quickPathContinueButton.tap()"
              ),
              let quickPathWaitRange = multilineHelperSource.range(
                of: "quickPathIntroductionView.waitForNonExistence("
              ),
              let multilineSwipeRange = multilineHelperSource.range(
                of: "fieldScrollView.swipeUp()"
              ) else {
            XCTFail("Missing ordered multiline QuickPath handling")
            return
        }
        XCTAssertLessThan(
            actionableScrollViewRange.lowerBound,
            quickPathBranchRange.lowerBound
        )
        XCTAssertLessThan(quickPathBranchRange.lowerBound, quickPathTapRange.lowerBound)
        XCTAssertLessThan(quickPathTapRange.lowerBound, quickPathWaitRange.lowerBound)
        XCTAssertLessThan(quickPathWaitRange.lowerBound, multilineSwipeRange.lowerBound)
        XCTAssertEqual(
            multilineHelperSource.components(separatedBy: "fieldScrollView.swipeUp()").count - 1,
            1
        )
        XCTAssertEqual(
            multilineHelperSource.components(separatedBy: "timeout: 10").count - 1,
            3
        )
        for (fragment, count) in [
            ("field.exists", 3),
            ("route.exists", 4),
            ("app.state", 4),
            ("expectedRouteExists", 5),
            ("expectedApplicationState", 5),
            (#"String(describing: field.value ?? "")"#, 4),
            ("keyboard.waitForNonExistence(timeout: 10)", 1),
            ("fieldScrollViews.count == 1", 3),
            ("field.elementType", 5),
            ("field.elementType,", 1),
            (".textField", 1),
            (".textView", 3),
            ("quickPathIntroductionViews.count", 2),
            ("quickPathButtons.count", 2),
            ("quickPathStaticTexts.count", 2),
            ("quickPathIntroductionView.descendants(", 2),
            ("element(boundBy:", 2),
            ("fieldFocusPredicate.evaluate(with: field)", 2),
            ("quickPathContinueButton.tap()", 1),
            (".tap()", 1),
            ("XCTFail(", 7),
            ("\n                return\n", 1),
            ("\n            return\n", 4),
            ("\n                    return\n", 2),
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
            "        guard keyboard.exists,\n" +
                "              field.exists,\n" +
                "              field.elementType == .textField,\n",
            "        guard keyboard.exists,\n" +
                "              field.exists,\n" +
                "              field.elementType == .textView,\n",
            "            .textField,",
            "            .textView,",
            "(field.elementType == .textView || field.elementType == .textField)",
            #"quickPathReturnKey.tap()"#,
            #"keyboard.buttons["Return"].tap()"#,
            ".coordinate(",
            ".press(",
            "Thread.sleep",
            "CGRect(",
            "tolerance",
            "epsilon",
            "automationShard",
            "deviceProfileID",
            "locale",
            #""Speed up your typing by sliding your finger across the letters to compose a word.""#,
            #"let quickPathContinueLabel = "Continue""#,
            "quickPathTutorialLabel",
            "quickPathContinueLabel",
            "quickPathTutorialTexts",
            "quickPathContinueButtons",
            "app.staticTexts.matching(",
            "app.buttons.matching(",
            "format: \"label == %@\"",
            "folding(",
            "diacriticInsensitive",
            "precomposedStringWithCanonicalMapping",
            "decomposedStringWithCanonicalMapping",
            "label CONTAINS",
            "label BEGINSWITH",
            ".swipeDown()",
            "app.swipeUp()",
            "for _ in",
            "while ",
            "performAccessibilityAudit",
            "printJSONLine",
            "S10_4_CANDIDATE",
            "S10_4_AX",
            "S10_4_CONTRAST",
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
        XCTAssertEqual(workEditingPositioningSource.utf8.count, 17_661)
        XCTAssertEqual(
            Data(workEditingPositioningSource.utf8).sha256,
            "9A3A66DC493DB1ABCE1787524CBC17E76FB11EC3D4B436EC87B3CF2A8153E009"
        )

        for workEditingDiagnosticResidue in [
            "workEditingDiagnostic",
            "emitWorkEditingPositioningDiagnostic",
            "S10_4_WORK_EDITING_POSITIONING_DIAGNOSTIC",
            "S10_4_WORK_EDITING_POSITIONING_DIAGNOSTIC_COUNT",
            #""elementTypeRawValue""#,
            #""elementTypeDescription""#,
            #""sampleOrdinal""#,
            #""elapsedMilliseconds""#,
            #""queries":"#,
            "XCTAttachment(",
            ".lifetime = .keepAlways",
            "throw AutomationConfigurationError.invalid(",
            "S10.4 AX-text Record-work editing positioning diagnostic",
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingDiagnosticResidue
                ).count - 1,
                0,
                workEditingDiagnosticResidue
            )
        }

        let workEditingAXTextGate =
            "        let workEditingAXTextEnabled =\n" +
                #"            automationShard?.shardID == "s10.4.current.ax-text""#
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingAXTextGate
            ).count - 1,
            1
        )
        let workEditingPassiveBindings =
            "        let workHelperTexts = app.staticTexts.matching(\n" +
                #"            NSPredicate(format: "label == %@", workHelperLabel)"# + "\n" +
                "        )\n" +
                "        let workScrollViews = app.scrollViews.containing(\n" +
                "            .image,\n" +
                #"            identifier: "s5.1.work.photo""# + "\n" +
                "        )\n" +
                "        let workNavigationBars = app.navigationBars.matching(\n" +
                #"            identifier: "Record work""# + "\n" +
                "        )"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingPassiveBindings
            ).count - 1,
            1
        )
        let workEditingPassiveAXBindings =
            "        let workPreviewImages = app.images.matching(\n" +
                #"            NSPredicate(format: "identifier == %@", "s5.1.work.photo")"# + "\n" +
                "        )\n" +
                "        let workEditingTabBars = app.tabBars\n" +
                "        let workPreviewImage = workPreviewImages.firstMatch\n" +
                "        let workEditingTabBar = workEditingTabBars.firstMatch"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingPassiveAXBindings
            ).count - 1,
            1
        )
        for (workEditingIdentityLock, count) in [
            ("workHelperTexts.count == 1", 5),
            ("workPreviewImages.count == 1", 1),
            ("workScrollViews.count == 1", 5),
            ("workNavigationBars.count == 1", 5),
            ("workEditingTabBars.count == 1", 1),
            ("workHelper.exists", 5),
            ("workPreviewImage.exists", 1),
            ("workScrollView.exists", 4),
            ("workNavigationBar.exists", 4),
            ("workEditingTabBar.exists", 1),
            ("workPreview.exists", 2),
            ("app.state == .runningForeground", 3),
            ("workHelper.elementType == .staticText", 1),
            ("workHelper.identifier.isEmpty", 1),
            ("workHelper.label == workHelperLabel", 1),
            (#"(workHelper.value as? String) == """#, 1),
            ("workPreviewImage.elementType == .image", 1),
            (#"workPreviewImage.identifier == "s5.1.work.photo""#, 1),
            ("workPreviewImage.label == workHelperLabel", 1),
            (#"(workPreviewImage.value as? String) == """#, 1),
            ("workScrollView.elementType == .scrollView", 1),
            (#"workScrollView.identifier == "s5.1.work.screen""#, 1),
            (#"workScrollView.label == """#, 1),
            (#"(workScrollView.value as? String) == """#, 1),
            ("workNavigationBar.elementType == .navigationBar", 1),
            (#"workNavigationBar.identifier == "Record work""#, 1),
            (#"workNavigationBar.label == """#, 1),
            (#"(workNavigationBar.value as? String) == """#, 1),
            ("workEditingTabBar.elementType == .tabBar", 1),
            (#"workEditingTabBar.identifier == """#, 1),
            (#"workEditingTabBar.label == "Tab Bar""#, 1),
            (#"(workEditingTabBar.value as? String) == """#, 1),
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingIdentityLock
                ).count - 1,
                count,
                workEditingIdentityLock
            )
        }

        let workEditingFrameValidator =
            "        let workEditingFrameIsValid: (CGRect) -> Bool = { frame in\n" +
                "            !frame.isNull\n" +
                "                && !frame.isEmpty\n" +
                "                && frame.origin.x.isFinite\n" +
                "                && frame.origin.y.isFinite\n" +
                "                && frame.size.width.isFinite\n" +
                "                && frame.size.height.isFinite\n" +
                "        }"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingFrameValidator
            ).count - 1,
            1
        )
        let workEditingInitialFrames =
            "            let initialApplicationFrame = app.frame\n" +
                "            let initialNavigationFrame = workNavigationBar.frame\n" +
                "            let initialScrollRawFrame = workScrollView.frame\n" +
                "            let initialTabFrame = workEditingTabBar.frame\n" +
                "            let initialHelperFrame = workHelper.frame\n" +
                "            let initialPreviewFrame = workPreviewImage.frame"
        let workEditingInitialScrollAndSafeTop =
            "                let initialScrollFrame = initialScrollRawFrame.intersection(\n" +
                "                    initialApplicationFrame\n" +
                "                )\n" +
                "                if workEditingFrameIsValid(initialScrollFrame) {\n" +
                "                    let initialSafeTop = max(\n" +
                "                        initialScrollFrame.minY,\n" +
                "                        initialNavigationFrame.maxY\n" +
                "                    ) + verticalInset"
        let workEditingInitialDisjointProof =
            "                    let requiredHelperDownwardMovement =\n" +
                "                        initialSafeTop - initialHelperFrame.minY\n" +
                "                    let previewRoomToTabTop =\n" +
                "                        initialTabFrame.minY - initialPreviewFrame.minY\n" +
                "                    let exactSeparation =\n" +
                "                        initialPreviewFrame.minY - initialHelperFrame.maxY\n" +
                "                    initialHelperToPreviewSeparation = exactSeparation\n" +
                "                    workEditingInitialSeparation =\n" +
                "                        requiredHelperDownwardMovement > 0\n" +
                "                            && previewRoomToTabTop > 0\n" +
                "                            && requiredHelperDownwardMovement >= previewRoomToTabTop\n" +
                "                            && exactSeparation > 0\n" +
                "                    workEditingInitialProof =\n" +
                "                        workEditingInitialSeparation"
        let workEditingInitialFailClosed =
            "            guard workEditingInitialProof else {\n" +
                #"                XCTFail("Record-work editing AX-text rigid composition proof failed.")"# + "\n" +
                "                return\n" +
                "            }"
        for workEditingInitialLock in [
            workEditingInitialFrames,
            workEditingInitialScrollAndSafeTop,
            workEditingInitialDisjointProof,
            workEditingInitialFailClosed,
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingInitialLock
                ).count - 1,
                1,
                workEditingInitialLock
            )
        }
        guard let workEditingInitialFramesRange =
                workEditingPositioningSource.range(of: workEditingInitialFrames),
              let workEditingInitialScrollRange =
                workEditingPositioningSource.range(
                    of: workEditingInitialScrollAndSafeTop,
                    range:
                        workEditingInitialFramesRange.upperBound
                        ..< workEditingPositioningSource.endIndex
                ),
              let workEditingInitialProofRange =
                workEditingPositioningSource.range(
                    of: workEditingInitialDisjointProof,
                    range:
                        workEditingInitialScrollRange.upperBound
                        ..< workEditingPositioningSource.endIndex
                ),
              let workEditingInitialFailRange =
                workEditingPositioningSource.range(
                    of: workEditingInitialFailClosed,
                    range:
                        workEditingInitialProofRange.upperBound
                        ..< workEditingPositioningSource.endIndex
                ) else {
            XCTFail("Missing ordered live Record-work AX-text initial proof")
            return
        }
        XCTAssertLessThan(
            workEditingInitialFramesRange.lowerBound,
            workEditingInitialScrollRange.lowerBound
        )
        XCTAssertLessThan(
            workEditingInitialScrollRange.lowerBound,
            workEditingInitialProofRange.lowerBound
        )
        XCTAssertLessThan(
            workEditingInitialProofRange.lowerBound,
            workEditingInitialFailRange.lowerBound
        )

        let workEditingLiveRecomputation =
            "            let scrollFrame = workScrollView.frame\n" +
                "            let applicationFrame = app.frame\n" +
                "            let navigationFrame = workNavigationBar.frame\n" +
                "            let helperFrame = workHelper.frame\n" +
                "            let previewFrame = workPreviewImage.frame"
        let workEditingLiveViewport =
            "            if rawFramesAreValid {\n" +
                "                liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                "            }\n" +
                "            let liveFramesAreValid =\n" +
                "                rawFramesAreValid && workEditingFrameIsValid(liveScrollFrame)"
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
                "                  recognizedMinimum <= recognizedMaximum else {"
        for workEditingGestureGeometryLock in [
            workEditingLiveRecomputation,
            workEditingLiveViewport,
            workEditingPositiveInterval,
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingGestureGeometryLock
                ).count - 1,
                1,
                workEditingGestureGeometryLock
            )
        }

        let workEditingGestureCaptureStart =
            "            let helperMinYBeforeDrag = helperFrame.minY\n" +
                "            let previewMinYBeforeDrag = previewFrame.minY"
        let workEditingGestureDelivery =
            "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )"
        let workEditingGestureCaptureEnd =
            "            let observedHelperFrame = workHelper.frame\n" +
                "            let observedPreviewFrame = workPreviewImage.frame"
        let workEditingObservedFrameValidity =
            "            let observedCommonFramesAreValid =\n" +
                "                workEditingFrameIsValid(observedHelperFrame)\n" +
                "            let observedAXFramesAreValid =\n" +
                "                workEditingFrameIsValid(observedPreviewFrame)\n" +
                "            let observedFramesAreValid =\n" +
                "                observedCommonFramesAreValid\n" +
                "                    && (!workEditingAXTextEnabled || observedAXFramesAreValid)"
        let workEditingGestureProofEnd =
            "                provenGestureCount += 1"
        for workEditingGestureLock in [
            workEditingGestureCaptureStart,
            workEditingGestureDelivery,
            workEditingGestureCaptureEnd,
            workEditingObservedFrameValidity,
            workEditingGestureProofEnd,
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingGestureLock
                ).count - 1,
                1,
                workEditingGestureLock
            )
        }
        guard let workEditingGestureCaptureStartRange =
                workEditingPositioningSource.range(of: workEditingGestureCaptureStart),
              let workEditingGestureDeliveryRange =
                workEditingPositioningSource.range(
                    of: workEditingGestureDelivery,
                    range:
                        workEditingGestureCaptureStartRange.upperBound
                        ..< workEditingPositioningSource.endIndex
                ),
              let workEditingGestureCaptureEndRange =
                workEditingPositioningSource.range(
                    of: workEditingGestureCaptureEnd,
                    range:
                        workEditingGestureDeliveryRange.upperBound
                        ..< workEditingPositioningSource.endIndex
                ),
              let workEditingGestureProofEndRange =
                workEditingPositioningSource.range(
                    of: workEditingGestureProofEnd,
                    range:
                        workEditingGestureCaptureEndRange.upperBound
                        ..< workEditingPositioningSource.endIndex
                ) else {
            XCTFail("Missing ordered Record-work helper/photo gesture proof")
            return
        }
        XCTAssertLessThan(
            workEditingGestureCaptureStartRange.lowerBound,
            workEditingGestureDeliveryRange.lowerBound
        )
        XCTAssertLessThan(
            workEditingGestureDeliveryRange.lowerBound,
            workEditingGestureCaptureEndRange.lowerBound
        )
        XCTAssertLessThan(
            workEditingGestureCaptureEndRange.lowerBound,
            workEditingGestureProofEndRange.lowerBound
        )
        let workEditingGestureCaptureAdjacency =
            workEditingGestureCaptureStart + "\n"
                + workEditingGestureDelivery + "\n"
                + workEditingGestureCaptureEnd
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingGestureCaptureAdjacency
            ).count - 1,
            1
        )
        let workEditingPerGestureProofSource = String(
            workEditingPositioningSource[
                workEditingGestureCaptureStartRange.lowerBound
                    ..< workEditingGestureProofEndRange.upperBound
            ]
        )
        XCTAssertEqual(
            workEditingPerGestureProofSource.components(
                separatedBy: ".frame"
            ).count - 1,
            2
        )
        for prohibitedPerGestureFrame in [
            "app.frame",
            "workScrollView.frame",
            "workNavigationBar.frame",
            "workEditingTabBar.frame",
        ] {
            XCTAssertFalse(
                workEditingPerGestureProofSource.contains(prohibitedPerGestureFrame),
                prohibitedPerGestureFrame
            )
        }
        let workEditingEqualPositiveMovement =
            "                guard let observedHelperDownwardMovement =\n" +
                "                        observedHelperDownwardMovement,\n" +
                "                      let observedPreviewDownwardMovement =\n" +
                "                        observedPreviewDownwardMovement,\n" +
                "                      observedHelperDownwardMovement > 0,\n" +
                "                      observedPreviewDownwardMovement > 0,\n" +
                "                      observedHelperDownwardMovement\n" +
                "                        == observedPreviewDownwardMovement else {"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingEqualPositiveMovement
            ).count - 1,
            1
        )
        for (workEditingGestureProvenanceLock, count) in [
            ("        var provenGestureCount = 0", 1),
            ("        for _ in 0..<4 {", 1),
            ("                provenGestureCount += 1", 1),
            ("                && provenGestureCount >= 1", 1),
            ("                && provenGestureCount <= 4", 1),
            ("workScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingGestureProvenanceLock
                ).count - 1,
                count,
                workEditingGestureProvenanceLock
            )
        }

        let workEditingFinalSeparation =
            "                    finalHelperToPreviewSeparation =\n" +
                "                        finalPreviewFrame.minY - finalHelperFrame.maxY"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingFinalSeparation
            ).count - 1,
            1
        )
        let workEditingFinalFrameProof =
            "        let finalApplicationFrame = app.frame\n" +
                "        let finalNavigationFrame = workNavigationBar.frame\n" +
                "        let finalScrollRawFrame = workScrollView.frame\n" +
                "        let finalHelperFrame = workHelper.frame\n" +
                "        let finalPreviewFrame = workPreviewImage.frame\n" +
                "        let finalTabFrame = workEditingTabBar.frame\n" +
                "        let finalCommonFramesAreValid =\n" +
                "            workEditingFrameIsValid(finalApplicationFrame)\n" +
                "                && workEditingFrameIsValid(finalNavigationFrame)\n" +
                "                && workEditingFrameIsValid(finalScrollRawFrame)\n" +
                "                && workEditingFrameIsValid(finalHelperFrame)\n" +
                "        let finalAXFramesAreValid =\n" +
                "            workEditingFrameIsValid(finalPreviewFrame)\n" +
                "                && workEditingFrameIsValid(finalTabFrame)\n" +
                "        let finalFramesAreValid =\n" +
                "            finalCommonFramesAreValid\n" +
                "                && (!workEditingAXTextEnabled || finalAXFramesAreValid)"
        let workEditingFinalCompositionProof =
            "        let finalScrollFrameIsValid = workEditingFrameIsValid(finalScrollFrame)\n" +
                "        let finalWorkEditingCompositionIsValid =\n" +
                "            !workEditingAXTextEnabled\n" +
                "                || (finalFramesAreValid\n" +
                "                    && finalScrollFrameIsValid\n" +
                "                    && workEditingComposition())"
        for workEditingFinalProofLock in [
            workEditingFinalFrameProof,
            workEditingFinalCompositionProof,
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingFinalProofLock
                ).count - 1,
                1,
                workEditingFinalProofLock
            )
        }
        let workEditingAXTextFallback =
            "        let workEditingAXTextFallbackAccepted =\n" +
                "            workEditingAXTextEnabled\n" +
                "                && !finalExactPreviewIsHittable\n" +
                "                && !finalWorkPreviewIsHittable\n" +
                "                && workEditingInitialProof\n" +
                "                && initialHelperToPreviewSeparation != nil\n" +
                "                && provenGestureCount >= 1\n" +
                "                && provenGestureCount <= 4\n" +
                "                && finalFramesAreValid\n" +
                "                && finalScrollFrameIsValid\n" +
                "                && finalWorkEditingCompositionIsValid\n" +
                "                && finalHelperToPreviewSeparation\n" +
                "                    == initialHelperToPreviewSeparation\n" +
                "                && finalHelperFrame.maxY < finalTabFrame.minY\n" +
                "                && finalHelperFrame.maxY < finalPreviewFrame.minY\n" +
                "                && finalPreviewFrame.minY > finalTabFrame.minY"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingAXTextFallback
            ).count - 1,
            1
        )
        let workEditingExplicitHittabilityBranches =
            "        let workPreviewHittabilityAccepted: Bool\n" +
                "        if workEditingAXTextEnabled {\n" +
                "            workPreviewHittabilityAccepted =\n" +
                "                finalWorkPreviewIsHittable\n" +
                "                    || workEditingAXTextFallbackAccepted\n" +
                "        } else {\n" +
                "            workPreviewHittabilityAccepted = finalWorkPreviewIsHittable\n" +
                "        }"
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingExplicitHittabilityBranches
            ).count - 1,
            1
        )
        for (workEditingFinalIdentityLock, count) in [
            ("let finalExactPreviewIsHittable = workPreviewImage.isHittable", 1),
            ("let finalWorkPreviewIsHittable = workPreview.isHittable", 1),
            ("finalWorkEditingCompositionIsValid", 3),
            ("finalFramesAreValid", 5),
            ("finalScrollFrameIsValid", 4),
            ("finalHelperFrame.maxY < finalTabFrame.minY", 1),
            ("finalHelperFrame.maxY < finalPreviewFrame.minY", 1),
            ("finalPreviewFrame.minY > finalTabFrame.minY", 1),
            ("finalHelperToPreviewSeparation", 3),
            ("initialHelperToPreviewSeparation", 4),
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingFinalIdentityLock
                ).count - 1,
                count,
                workEditingFinalIdentityLock
            )
        }

        let workEditingFinalFailureAndCapture =
            "              workPreviewHittabilityAccepted else {\n" +
                #"            XCTFail("Record-work editing composition is outside the safe viewport.")"# + "\n" +
                "            return\n" +
                "        }\n" +
                #"        captureBaseline("state.work.editing", in: app)"#
        XCTAssertEqual(
            workEditingPositioningSource.components(
                separatedBy: workEditingFinalFailureAndCapture
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workEditingPositioningSource.components(separatedBy: "XCTFail(").count - 1,
            9
        )
        XCTAssertEqual(
            workEditingPositioningSource.components(separatedBy: "return\n").count - 1,
            9
        )
        for (workEditingMechanicalLock, count) in [
            ("        for _ in 0..<4 {", 1),
            ("workScrollView.coordinate(", 1),
            ("dragStart.press(", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
            (#"captureBaseline("state.work.editing", in: app)"#, 1),
        ] {
            XCTAssertEqual(
                workEditingPositioningSource.components(
                    separatedBy: workEditingMechanicalLock
                ).count - 1,
                count,
                workEditingMechanicalLock
            )
        }
        for prohibitedWorkEditingForm in [
            "finalTabFrame.maxY",
            "finalPreviewFrame.intersection(finalTabFrame)",
            "finalPreviewFrame.intersects(finalTabFrame)",
            "finalTabFrame.intersection(finalPreviewFrame)",
            "finalTabFrame.intersects(finalPreviewFrame)",
            "provenGestureCount == 0",
            "provenGestureCount >= 0",
            "provenGestureCount == 2",
            "observedHelperDownwardMovement >= 0",
            "observedPreviewDownwardMovement >= 0",
            "observedHelperDownwardMovement != observedPreviewDownwardMovement",
            "workEditingAXTextEnabled || finalWorkPreviewIsHittable",
            "finalWorkPreviewIsHittable || workEditingAXTextEnabled",
            "workPreviewHittabilityAccepted = true",
            "CGRect(",
            "epsilon",
            "tolerance",
            "abs(",
            ".tap()",
            ".swipeUp()",
            ".swipeDown()",
            "scroll(",
            "waitForExistence",
            "waitForNonExistence",
            "Thread.sleep",
            "performAccessibilityAudit",
            "XCTAttachment(",
            "printJSONLine(",
            "emitAutomationTaskEvidence",
            "emitAutomationShardReceipt",
        ] {
            XCTAssertFalse(
                workEditingPositioningSource.contains(prohibitedWorkEditingForm),
                prohibitedWorkEditingForm
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
        XCTAssertEqual(workSavingPositioningSource.utf8.count, 24_711)
        XCTAssertEqual(
            Data(workSavingPositioningSource.utf8).sha256,
            "464743BADE9ADBE966BCE93AA8846D4F611E510EBE1F3EF0C2A340C20D6AFE13"
        )
        let workSavingPrimaryNavigationWait =
            #"        let issueScreen = element("s5.1.issue.screen", in: app)"# + "\n" +
                "        XCTAssertTrue(issueScreen.waitForExistence(timeout: 85))\n" +
                #"        let dueStatus = element("s5.1.issue.status", in: app)"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: workSavingPrimaryNavigationWait
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: "issueScreen.waitForExistence(timeout: 85)"
            ).count - 1,
            1
        )

        let workSavingAXTextImportFixtureIdentity =
            "        let workImportFixtureButtons: XCUIElementQuery? = workEditingAXTextEnabled\n" +
                #"            ? app.buttons.matching(identifier: "s5.1.work.import-fixture")"# + "\n" +
                "            : nil\n" +
                "        let workImportFixtureButton = workImportFixtureButtons?.firstMatch"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingAXTextImportFixtureIdentity
            ).count - 1,
            1
        )
        let workSavingAXTextDisabledButtonProof =
            "                    && workImportFixtureButton?.elementType == .button\n" +
                "                    && workImportFixtureButton?.identifier\n" +
                #"                        == "s5.1.work.import-fixture""# + "\n" +
                "                    && workImportFixtureButton?.label == workHelperLabel\n" +
                #"                    && (workImportFixtureButton?.value as? String) == """# + "\n" +
                "                    && workImportFixtureButton?.isEnabled == false"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingAXTextDisabledButtonProof
            ).count - 1,
            1
        )

        let workSavingDisjointFrameValidation =
            "            let ordinaryCommonFramesAreValid =\n" +
                "                !applicationFrame.isNull\n" +
                "                    && !applicationFrame.isEmpty\n" +
                "                    && !navigationFrame.isNull\n" +
                "                    && !navigationFrame.isEmpty\n" +
                "                    && !scrollFrame.isNull\n" +
                "                    && !scrollFrame.isEmpty\n" +
                "                    && !tabBarFrame.isNull\n" +
                "                    && !tabBarFrame.isEmpty\n" +
                "                    && !noteFrame.isNull\n" +
                "                    && !noteFrame.isEmpty\n" +
                "                    && !helperFrame.isNull\n" +
                "                    && !helperFrame.isEmpty\n" +
                "            let savingAXTextCommonFramesAreValid =\n" +
                "                workEditingFrameIsValid(applicationFrame)\n" +
                "                    && workEditingFrameIsValid(navigationFrame)\n" +
                "                    && workEditingFrameIsValid(scrollFrame)\n" +
                "                    && workEditingFrameIsValid(tabBarFrame)\n" +
                "                    && workEditingFrameIsValid(noteFrame)\n" +
                "                    && workEditingFrameIsValid(helperFrame)\n" +
                "            let commonFramesAreValid = workEditingAXTextEnabled\n" +
                "                ? savingAXTextCommonFramesAreValid\n" +
                "                : ordinaryCommonFramesAreValid"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingDisjointFrameValidation
            ).count - 1,
            1
        )
        let workSavingDisjointCompletion =
            "            if (!workEditingAXTextEnabled && ordinaryCompositionIsComplete)\n" +
                "                || savingAXTextCompositionIsComplete {\n" +
                "                break\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingDisjointCompletion
            ).count - 1,
            1
        )

        let workSavingAXTextInterval =
            "            if workEditingAXTextEnabled {\n" +
                "                minimumShift = safeTop - buttonFrame.minY\n" +
                "                maximumShift = min(\n" +
                "                    safeTop - noteFrame.maxY,\n" +
                "                    min(\n" +
                "                        safeTop - helperFrame.maxY,\n" +
                "                        safeBottom - buttonFrame.maxY\n" +
                "                    )\n" +
                "                )\n" +
                "            } else {\n" +
                "                minimumShift = max(\n" +
                "                    safeTop - noteFrame.minY,\n" +
                "                    safeTop - helperFrame.minY\n" +
                "                )\n" +
                "                maximumShift = min(\n" +
                "                    safeBottom - noteFrame.maxY,\n" +
                "                    safeBottom - helperFrame.maxY\n" +
                "                )\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingAXTextInterval
            ).count - 1,
            1
        )
        for exactPlannerLock in [
            "                if workEditingAXTextEnabled,\n" +
                "                   maximumShift < -receiverCapacity {\n" +
                "                    dragDistance = -receiverCapacity",
            "                    dragDistance = workEditingAXTextEnabled\n" +
                "                        ? recognizedMinimum\n" +
                "                        : recognizedMaximum",
            "                    dragDistance = workEditingAXTextEnabled\n" +
                "                        ? recognizedMaximum\n" +
                "                        : recognizedMinimum",
            "                } else if workEditingAXTextEnabled,\n" +
                "                          minimumShift > receiverCapacity {\n" +
                "                    dragDistance = receiverCapacity",
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: exactPlannerLock
                ).count - 1,
                1,
                exactPlannerLock
            )
        }
        let workSavingNoReversal =
            "            if workEditingAXTextEnabled {\n" +
                "                let gestureDirection: CGFloat = dragDistance > 0 ? 1 : -1\n" +
                "                if let savingAXTextGestureDirection {\n" +
                "                    guard gestureDirection == savingAXTextGestureDirection else {\n" +
                #"                        XCTFail("Record-work saving AX-text gesture reversed direction.")"# + "\n" +
                "                        return\n" +
                "                    }\n" +
                "                } else {\n" +
                "                    savingAXTextGestureDirection = gestureDirection\n" +
                "                }\n" +
                "            }"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingNoReversal
            ).count - 1,
            1
        )

        let workSavingSoleAction =
            "            dragStart.press(\n" +
                "                forDuration: 0.2,\n" +
                "                thenDragTo: dragEnd,\n" +
                "                withVelocity: .slow,\n" +
                "                thenHoldForDuration: 0.2\n" +
                "            )"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingSoleAction
            ).count - 1,
            1
        )
        let workSavingFourSignedMovers =
            "            guard observedNoteShift * dragDistance > 0,\n" +
                "                  observedHelperShift * dragDistance > 0,\n" +
                "                  savingAXTextPrimaryFramesAreValid,\n" +
                "                  savingAXTextCoMovementIsValid,\n" +
                "                  savingAXTextObservedOrderingIsValid else {"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingFourSignedMovers
            ).count - 1,
            1
        )
        for signedAXTextMover in [
            "observedNoteShift * dragDistance > 0",
            "observedHelperShift * dragDistance > 0",
            "observedPreviewShift * dragDistance > 0",
            "observedButtonShift * dragDistance > 0",
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: signedAXTextMover
                ).count - 1,
                1,
                signedAXTextMover
            )
        }

        let workSavingFinalDisjointAcceptance =
            "              (workSavingOrdinaryCompositionAccepted\n" +
                "                || workSavingAXTextAlternateCompositionAccepted) else {"
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: workSavingFinalDisjointAcceptance
            ).count - 1,
            1
        )
        for finalAXTextLock in [
            "&& provenSavingGestureCount >= 1",
            "&& provenSavingGestureCount <= 4",
            "&& savingAXTextGestureDirection != nil",
            "&& savingFinalNoteFrame.maxY <= savingFinalSafeTop",
            "&& savingFinalHelperFrame.maxY <= savingFinalSafeTop",
            "&& savingFinalButtonFrame.minY >= savingFinalSafeTop",
            "&& savingFinalButtonFrame.maxY <= savingFinalSafeBottom",
            "&& savingFinalNoteFrame.maxY < savingFinalHelperFrame.minY",
            "&& savingFinalHelperFrame.maxY < savingFinalButtonFrame.minY",
            "&& savingFinalButtonFrame.maxY < savingFinalPhotoFrame.minY",
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: finalAXTextLock
                ).count - 1,
                1,
                finalAXTextLock
            )
        }
        XCTAssertEqual(
            workSavingPositioningSource.components(
                separatedBy: "&& workImportFixtureButton?.isHittable == true"
            ).count - 1,
            2
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
            ("workHelper.exists", 4),
            ("workScrollView.exists", 3),
            ("workNavigationBar.exists", 3),
            ("workPreview.exists", 4),
            ("progress.exists", 4),
            ("workImportFixtureButtons?.count == 1", 5),
            ("workPreviewImages.count == 1", 3),
            ("workImportFixtureButton?.exists == true", 4),
            ("workImportFixtureButton?.elementType == .button", 4),
            ("workImportFixtureButton?.identifier", 4),
            ("workImportFixtureButton?.label == workHelperLabel", 4),
            (#"(workImportFixtureButton?.value as? String) == """#, 4),
            ("workImportFixtureButton?.isEnabled == false", 4),
            ("workEditingComposition()", 2),
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: workSavingCardinalityLock
                ).count - 1,
                count,
                workSavingCardinalityLock
            )
        }
        for (workSavingInvariant, count) in [
            ("for _ in 0..<4", 1),
            ("dragStart.press(", 1),
            ("press(", 1),
            ("coordinate(", 1),
            ("waitForExistence", 1),
            ("captureBaseline(", 1),
            ("performAccessibilityAudit(", 0),
            ("ContrastAuditExceptionSignature", 0),
            ("XCTAttachment(", 0),
            ("printJSONLine(", 0),
            ("attachCandidate(", 0),
            ("epsilon", 0),
            ("tolerance", 0),
            ("abs(", 0),
            ("app.swipe", 0),
            ("workScrollView.swipe", 0),
            ("Thread.sleep", 0),
            ("sleep(", 0),
            ("XCTExpectFailure", 0),
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: workSavingInvariant
                ).count - 1,
                count,
                workSavingInvariant
            )
        }
        for retiredWorkSavingEquality in [
            "observedPreviewShift == observedHelperShift",
            "savingInitialHelperToPreviewSeparation",
            "savingFinalHelperToPreviewSeparation",
        ] {
            XCTAssertEqual(
                workSavingPositioningSource.components(
                    separatedBy: retiredWorkSavingEquality
                ).count - 1,
                0,
                retiredWorkSavingEquality
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
                "    private func positionSignDetailTimeZoneForAXText("
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

        let captureBaselineStart =
            "    @MainActor\n" +
                "    private func captureBaseline("
        let issueRecheckDuePositioningHelperStart =
            "    @MainActor\n" +
                "    private func positionIssueRecheckDueDescriptionForAXText(\n" +
                "        in app: XCUIApplication\n" +
                "    ) -> Bool {"
        let issueRecheckDuePositioningHelperEnd =
            "\n    private func isActive("
        guard let captureBaselineStartRange = uiSource.range(
            of: captureBaselineStart
        ), let issueRecheckDuePositioningHelperStartRange = uiSource.range(
            of: issueRecheckDuePositioningHelperStart,
            range: captureBaselineStartRange.upperBound ..< uiSource.endIndex
        ), let issueRecheckDuePositioningHelperEndRange = uiSource.range(
            of: issueRecheckDuePositioningHelperEnd,
            range: issueRecheckDuePositioningHelperStartRange.upperBound ..<
                uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded captureBaseline or AX-text issue recheck-due positioning source")
            return
        }
        let restoredCaptureBaselineEnd = uiSource.index(
            issueRecheckDuePositioningHelperStartRange.lowerBound,
            offsetBy: -2
        )
        let restoredCaptureBaselineSource = String(
            uiSource[
                captureBaselineStartRange.lowerBound ..<
                    restoredCaptureBaselineEnd
            ]
        )
        let issueRecheckDuePositioningHelperSource = String(
            uiSource[
                issueRecheckDuePositioningHelperStartRange.lowerBound ..<
                    issueRecheckDuePositioningHelperEndRange.lowerBound
            ]
        )
        XCTAssertEqual(restoredCaptureBaselineSource.utf8.count, 7_901)
        XCTAssertEqual(
            Data(restoredCaptureBaselineSource.utf8).sha256,
            "371C419756DF1F86C30BD576938A5089F74616379C790C79089C23A052760CB6"
        )
        XCTAssertEqual(issueRecheckDuePositioningHelperSource.utf8.count, 23_849)
        XCTAssertEqual(
            Data(issueRecheckDuePositioningHelperSource.utf8).sha256,
            "A9D52569212661CD4419ECBF4804DDFDA04187EA2F4BF133387807AF6150AC53"
        )
        let normalEligibleExceptionsBinding =
            "            let eligibleExceptions = " +
                "Self.contrastAuditExceptionSignatures.filter {"
        XCTAssertEqual(
            restoredCaptureBaselineSource.components(
                separatedBy: "        do {\n" + normalEligibleExceptionsBinding
            ).count - 1,
            1
        )

        let issueRecheckDueRouteStart =
            #"        let issueScreen = element("s5.1.issue.screen", in: app)"#
        let issueRecheckDueBaseline =
            #"        captureBaseline("state.issue.recheck-due", in: app)"#
        guard let issueRecheckDueRouteStartRange = uiSource.range(
            of: issueRecheckDueRouteStart
        ), let issueRecheckDueBaselineRange = uiSource.range(
            of: issueRecheckDueBaseline,
            range: issueRecheckDueRouteStartRange.upperBound ..< uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text issue recheck-due route")
            return
        }
        let issueRecheckDueRouteSource = String(
            uiSource[
                issueRecheckDueRouteStartRange.lowerBound ..<
                    issueRecheckDueBaselineRange.upperBound
            ]
        )
        XCTAssertEqual(issueRecheckDueRouteSource.utf8.count, 705)
        XCTAssertEqual(
            Data(issueRecheckDueRouteSource.utf8).sha256,
            "D88EB267A8597F2465581047BDB44D2ECCEF9615F1B355346FE6AB19BF9A3EF7"
        )
        let issueRecheckDuePositioningGate =
            #"        if automationShard?.shardID == "s10.4.current.ax-text" {"#
        let issueRecheckDuePositioningGuard =
            "            guard positionIssueRecheckDueDescriptionForAXText(in: app) else {\n" +
                "                throw AutomationConfigurationError.invalid(\n" +
                "                    \"S10.4 AX-text issue recheck-due positioning failed\"\n" +
                "                )\n" +
                "            }"
        let issueRecheckDuePositioningAdjacency =
            #"        assertLocalizedLabel(dueStatus, equals: "Attention: Recheck due")"# +
                "\n" +
                issueRecheckDuePositioningGate + "\n" +
                issueRecheckDuePositioningGuard + "\n" +
                "        }\n" +
                issueRecheckDueBaseline
        XCTAssertEqual(
            issueRecheckDueRouteSource.components(
                separatedBy: issueRecheckDuePositioningAdjacency
            ).count - 1,
            1
        )
        for routeLock in [
            "positionIssueRecheckDueDescriptionForAXText(in: app)",
            "S10.4 AX-text issue recheck-due positioning failed",
            issueRecheckDueBaseline,
        ] {
            XCTAssertEqual(
                issueRecheckDueRouteSource.components(
                    separatedBy: routeLock
                ).count - 1,
                1,
                routeLock
            )
        }

        let issueRecheckDueDescriptionPredicate =
            "        let descriptionValuePredicate = NSPredicate(\n" +
                #"            format: "label == %@","# + "\n" +
                #"            "Replaced failed power supply""# + "\n" +
                "        )"
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: issueRecheckDueDescriptionPredicate
            ).count - 1,
            1
        )
        let issueRecheckDueQueryLocks = [
            "        let issueScreens = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s5.1.issue.screen""# + "\n" +
                "        )",
            "        let issueScrollViews = app.scrollViews.containing(\n" +
                "            descriptionValuePredicate\n" +
                "        )",
            "        let issueNavigationBars = app.navigationBars.matching(\n" +
                #"            identifier: "Recheck due""# + "\n" +
                "        )",
            "        let tabBars = app.tabBars",
            "        let startRecheckButtons = app.buttons.matching(\n" +
                #"            identifier: "s5.2.issue.start-recheck""# + "\n" +
                "        )",
            "        let workRecords = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s5.1.issue.work-record""# + "\n" +
                "        )",
            "        let workDates = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s5.1.issue.work-date""# + "\n" +
                "        )",
            "        let workDescriptions = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s5.1.issue.work-description""# + "\n" +
                "        )",
            "        let workDescriptionsContainingValue = workDescriptions.containing(\n" +
                "            descriptionValuePredicate\n" +
                "        )",
            "        let descriptionValueTexts = app.staticTexts.matching(\n" +
                "            descriptionValuePredicate\n" +
                "        )",
            "        let workPhotos = app.images.matching(\n" +
                #"            identifier: "s5.1.issue.work-photo""# + "\n" +
                "        )",
        ]
        XCTAssertEqual(issueRecheckDueQueryLocks.count, 11)
        for queryLock in issueRecheckDueQueryLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: queryLock
                ).count - 1,
                1,
                queryLock
            )
        }
        let issueRecheckDueBindingLocks = [
            "        let issueScreen = issueScreens.firstMatch",
            "        let issueScrollView = issueScrollViews.firstMatch",
            "        let issueNavigationBar = issueNavigationBars.firstMatch",
            "        let tabBar = tabBars.firstMatch",
            "        let startRecheckButton = startRecheckButtons.firstMatch",
            "        let workRecord = workRecords.firstMatch",
            "        let workDate = workDates.firstMatch",
            "        let workDescription = workDescriptions.firstMatch",
            "        let descriptionValueText = descriptionValueTexts.firstMatch",
            "        let workPhoto = workPhotos.firstMatch",
        ]
        XCTAssertEqual(issueRecheckDueBindingLocks.count, 10)
        for bindingLock in issueRecheckDueBindingLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: bindingLock
                ).count - 1,
                1,
                bindingLock
            )
        }
        let issueRecheckDueCardinalityLocks = [
            "                && issueScreens.count == 1",
            "                && issueScrollViews.count == 1",
            "                && issueNavigationBars.count == 1",
            "                && tabBars.count == 1",
            "                && startRecheckButtons.count == 1",
            "                && workRecords.count == 1",
            "                && workDates.count == 1",
            "                && workDescriptions.count == 1",
            "                && workDescriptionsContainingValue.count == 1",
            "                && descriptionValueTexts.count == 1",
            "                && workPhotos.count == 1",
        ]
        XCTAssertEqual(issueRecheckDueCardinalityLocks.count, 11)
        for cardinalityLock in issueRecheckDueCardinalityLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: cardinalityLock
                ).count - 1,
                1,
                cardinalityLock
            )
        }
        for (bindingCountLock, expectedCount) in [
            (".firstMatch", 10),
            ("        let hasExactIdentity: () -> Bool = {", 1),
            ("        let hasExactRoute: () -> Bool = {", 1),
            ("hasExactIdentity()", 4),
            ("hasExactRoute()", 1),
        ] {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: bindingCountLock
                ).count - 1,
                expectedCount,
                bindingCountLock
            )
        }

        let issueRecheckDueIdentityLocks = [
            "                && issueScreen.exists",
            "                && issueScreen.elementType == .scrollView",
            #"                && issueScreen.identifier == "s5.1.issue.screen""#,
            "                && issueScrollView.exists",
            "                && issueScrollView.elementType == .scrollView",
            #"                && issueScrollView.identifier == "s5.1.issue.screen""#,
            "                && issueNavigationBar.exists",
            "                && issueNavigationBar.elementType == .navigationBar",
            #"                && issueNavigationBar.identifier == "Recheck due""#,
            "                && tabBar.exists",
            "                && tabBar.elementType == .tabBar",
            #"                && tabBar.label == "Tab Bar""#,
            "                && startRecheckButton.exists",
            "                && startRecheckButton.elementType == .button",
            #"                && startRecheckButton.identifier == "s5.2.issue.start-recheck""#,
            #"                && startRecheckButton.label == "Start recheck""#,
            #"                && (startRecheckButton.value as? String) == """#,
            "                && workRecord.exists",
            "                && workRecord.elementType == .other",
            #"                && workRecord.identifier == "s5.1.issue.work-record""#,
            "                && workDate.exists",
            "                && workDate.elementType == .staticText",
            #"                && workDate.identifier == "s5.1.issue.work-date""#,
            "                && workDescription.exists",
            "                && workDescription.elementType == .staticText",
            #"                && workDescription.identifier == "s5.1.issue.work-description""#,
            #"                    == "Short description, Replaced failed power supply""#,
            "                && descriptionValueText.exists",
            "                && descriptionValueText.elementType == .staticText",
            "                && descriptionValueText.identifier.isEmpty",
            #"                && descriptionValueText.label == "Replaced failed power supply""#,
            "                && workPhoto.exists",
            "                && workPhoto.elementType == .image",
            #"                && workPhoto.identifier == "s5.1.issue.work-photo""#,
            #"                    == "Add one optional photo showing the work performed.""#,
        ]
        for identityLock in issueRecheckDueIdentityLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: identityLock
                ).count - 1,
                1,
                identityLock
            )
        }
        let issueRecheckDueIdentityClosureStart =
            "        let hasExactIdentity: () -> Bool = {"
        let issueRecheckDueRouteClosureStart =
            "        let hasExactRoute: () -> Bool = {"
        guard let issueRecheckDueIdentityClosureStartRange =
                issueRecheckDuePositioningHelperSource.range(
                    of: issueRecheckDueIdentityClosureStart
                ),
              let issueRecheckDueRouteClosureStartRange =
                issueRecheckDuePositioningHelperSource.range(
                    of: issueRecheckDueRouteClosureStart,
                    range: issueRecheckDueIdentityClosureStartRange.upperBound ..<
                        issueRecheckDuePositioningHelperSource.endIndex
                ),
              let issueRecheckDueInitialRouteGuardRange =
                issueRecheckDuePositioningHelperSource.range(
                    of: "        guard hasExactRoute() else {",
                    range: issueRecheckDueRouteClosureStartRange.upperBound ..<
                        issueRecheckDuePositioningHelperSource.endIndex
                ) else {
            XCTFail("Missing split issue recheck-due identity and route closures")
            return
        }
        let issueRecheckDueIdentityClosureSource = String(
            issueRecheckDuePositioningHelperSource[
                issueRecheckDueIdentityClosureStartRange.lowerBound ..<
                    issueRecheckDueRouteClosureStartRange.lowerBound
            ]
        )
        let issueRecheckDueRouteClosureSource = String(
            issueRecheckDuePositioningHelperSource[
                issueRecheckDueRouteClosureStartRange.lowerBound ..<
                    issueRecheckDueInitialRouteGuardRange.lowerBound
            ]
        )
        XCTAssertEqual(
            issueRecheckDueIdentityClosureSource.components(
                separatedBy: ".frame"
            ).count - 1,
            0
        )
        XCTAssertEqual(
            issueRecheckDueIdentityClosureSource.components(
                separatedBy: ".contains("
            ).count - 1,
            0
        )
        for routeCompositionLock in [
            "            return hasExactIdentity()\n" +
                "                && isValidFrame(app.frame)",
            "                && isValidFrame(startRecheckFrame)",
            "                && screenFrame == scrollFrame",
            "                && recordFrame.contains(dateFrame)",
            "                && recordFrame.contains(descriptionFrame)",
            "                && recordFrame.contains(photoFrame)",
            "                && dateFrame.maxY < descriptionFrame.minY",
            "                && descriptionFrame.maxY < photoFrame.minY",
        ] {
            XCTAssertEqual(
                issueRecheckDueRouteClosureSource.components(
                    separatedBy: routeCompositionLock
                ).count - 1,
                1,
                routeCompositionLock
            )
        }

        let issueRecheckDueFrameValidationLock =
            "        let isValidFrame: (CGRect) -> Bool = { frame in\n" +
                "            !frame.isNull\n" +
                "                && !frame.isEmpty\n" +
                "                && !frame.isInfinite\n" +
                "                && frame.origin.x.isFinite\n" +
                "                && frame.origin.y.isFinite\n" +
                "                && frame.size.width.isFinite\n" +
                "                && frame.size.height.isFinite\n" +
                "        }"
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: issueRecheckDueFrameValidationLock
            ).count - 1,
            1
        )
        let issueRecheckDuePreAttemptIdentityLock =
            "        for _ in 0..<4 {\n" +
                "            guard hasExactIdentity() else {\n" +
                "                XCTFail(\"AX-text issue recheck-due positioning route changed.\")\n" +
                "                return false\n" +
                "            }\n" +
                "            let applicationFrame = app.frame"
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: issueRecheckDuePreAttemptIdentityLock
            ).count - 1,
            1
        )
        let issueRecheckDueFrameLocks: [(String, Int)] = [
            ("            let applicationFrame = app.frame", 1),
            ("            let screenFrame = issueScreen.frame", 2),
            ("            let scrollFrame = issueScrollView.frame", 2),
            ("            let navigationFrame = issueNavigationBar.frame", 1),
            ("            let tabFrame = tabBar.frame", 1),
            ("            let startRecheckFrame = startRecheckButton.frame", 2),
            ("            let recordFrame = workRecord.frame", 2),
            ("            let dateFrame = workDate.frame", 2),
            ("            let descriptionFrame = workDescription.frame", 2),
            ("            let valueFrame = descriptionValueText.frame", 2),
            ("            let photoFrame = workPhoto.frame", 2),
            ("                && isValidFrame(startRecheckFrame)", 2),
            ("            let liveFramesAreValid = isValidFrame(applicationFrame)", 1),
            ("            var liveScrollFrame = CGRect.null", 1),
            (
                "            if liveFramesAreValid {\n" +
                    "                liveScrollFrame = scrollFrame.intersection(applicationFrame)\n" +
                    "            }",
                1
            ),
            ("            guard liveFramesAreValid,", 1),
            ("                  isValidFrame(liveScrollFrame),", 1),
        ]
        for (frameLock, expectedCount) in issueRecheckDueFrameLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: frameLock
                ).count - 1,
                expectedCount,
                frameLock
            )
        }
        guard let issueRecheckDueValidityRange =
                issueRecheckDuePositioningHelperSource.range(
                    of: "            let liveFramesAreValid = isValidFrame(applicationFrame)"
                ),
              let issueRecheckDueIntersectionRange =
                issueRecheckDuePositioningHelperSource.range(
                    of: "                liveScrollFrame = scrollFrame.intersection(applicationFrame)",
                    range: issueRecheckDueValidityRange.upperBound ..<
                        issueRecheckDuePositioningHelperSource.endIndex
                ),
              let issueRecheckDueArithmeticRange =
                issueRecheckDuePositioningHelperSource.range(
                    of: "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)",
                    range: issueRecheckDueIntersectionRange.upperBound ..<
                        issueRecheckDuePositioningHelperSource.endIndex
                ) else {
            XCTFail("Missing issue recheck-due frame-validity ordering")
            return
        }
        XCTAssertLessThan(
            issueRecheckDueValidityRange.lowerBound,
            issueRecheckDueIntersectionRange.lowerBound
        )
        XCTAssertLessThan(
            issueRecheckDueIntersectionRange.lowerBound,
            issueRecheckDueArithmeticRange.lowerBound
        )
        let issueRecheckDueAggregateGuardLock =
            "            guard liveFramesAreValid,\n" +
                "                  isValidFrame(liveScrollFrame),\n" +
                "                  screenFrame == scrollFrame,\n" +
                "                  recordFrame.contains(dateFrame),\n" +
                "                  recordFrame.contains(descriptionFrame),\n" +
                "                  recordFrame.contains(photoFrame),\n" +
                "                  dateFrame.maxY < descriptionFrame.minY,\n" +
                "                  descriptionFrame.maxY < photoFrame.minY else {\n" +
                "                XCTFail(\"AX-text issue recheck-due positioning geometry is invalid.\")\n" +
                "                return false\n" +
                "            }"
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: issueRecheckDueAggregateGuardLock
            ).count - 1,
            1
        )
        for removedIssueRecheckDueDiagnosticOrProxyForm in [
            "                && descriptionFrame.contains(valueFrame)",
            "                  descriptionFrame.contains(valueFrame),",
            "                    && finalDescriptionFrame.contains(finalValueFrame)",
            "recordFrame.contains(startRecheckFrame)",
            "finalRecordFrame.contains(finalStartRecheckFrame)",
            "photoFrame.maxY < startRecheckFrame.minY",
            "finalPhotoFrame.maxY < finalStartRecheckFrame.minY",
            "S10_4_AX_TEXT_ISSUE_RECHECK_DUE_LIVE_GEOMETRY_DIAGNOSTIC",
            "diagnostic",
            "diagnosticAttemptIndex",
            "relationResults",
            "failedRelations",
            "allRelationsPass",
            "applicationFrameIsValid",
            "screenFrameIsValid",
            "scrollFrameIsValid",
            "navigationFrameIsValid",
            "tabFrameIsValid",
            "recordFrameIsValid",
            "dateFrameIsValid",
            "descriptionFrameIsValid",
            "valueFrameIsValid",
            "photoFrameIsValid",
            "liveScrollFrameIsValid",
            "screenEqualsScroll",
            "recordContainsDate",
            "recordContainsDescription",
            "recordContainsPhoto",
            "descriptionContainsValue",
            "dateBeforeDescription",
            "descriptionBeforePhoto",
            "identityPassed",
            "completedGestureCount",
            "previousPostGestureMinY",
            "finiteNumber",
            "optionalFiniteNumber",
            "frameObject",
            "printJSONLine",
            "NSNull",
            "JSONSerialization",
            "automationShard",
            "[(String, Bool)]",
            "compactMap { relation in",
            #""shardID": automationShard"#,
            #""frames": ["#,
            "live geometry diagnostic completed nonaccepting",
        ] {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: removedIssueRecheckDueDiagnosticOrProxyForm
                ).count - 1,
                0,
                removedIssueRecheckDueDiagnosticOrProxyForm
            )
        }
        for prohibitedIssueRecheckDueToleranceOrFallbackForm in [
            "tolerance",
            "epsilon",
            "round(",
            ".rounded(",
            ".integral",
            ".insetBy(",
            ".frame(width:",
            ".frame(height:",
            "fixedFrame",
            "fixed-frame",
            "fallback",
            "CGRect(x:",
        ] {
            XCTAssertFalse(
                issueRecheckDuePositioningHelperSource.contains(
                    prohibitedIssueRecheckDueToleranceOrFallbackForm
                ),
                prohibitedIssueRecheckDueToleranceOrFallbackForm
            )
        }

        let issueRecheckDueGeometryLocks = [
            "        let verticalInset: CGFloat = 16",
            "        let receiverInset: CGFloat = 24",
            "        let minimumGestureDistance: CGFloat = 44",
            "        for _ in 0..<4 {",
            "            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)",
            "            let liveBottom = min(\n" +
                "                liveScrollFrame.maxY,\n" +
                "                min(applicationFrame.maxY, tabFrame.minY)\n" +
                "            )",
            "            let safeTop = liveTop + verticalInset",
            "            let safeBottom = liveBottom - verticalInset",
            "            let receiverTop = liveTop + receiverInset",
            "            let receiverBottom = liveBottom - receiverInset",
            "            let receiverLeft = liveScrollFrame.minX + receiverInset",
            "            let receiverRight = liveScrollFrame.maxX - receiverInset",
            "            let receiverCapacity = receiverBottom - receiverTop",
            "            let minimumShift = max(\n" +
                "                safeTop - startRecheckFrame.minY,\n" +
                "                max(\n" +
                "                    safeTop - dateFrame.minY,\n" +
                "                    max(\n" +
                "                        safeTop - descriptionFrame.minY,\n" +
                "                        safeTop - valueFrame.minY\n" +
                "                    )\n" +
                "                )\n" +
                "            )",
            "            let maximumShift = min(\n" +
                "                safeBottom - startRecheckFrame.maxY,\n" +
                "                min(\n" +
                "                    safeBottom - dateFrame.maxY,\n" +
                "                    min(\n" +
                "                        safeBottom - descriptionFrame.maxY,\n" +
                "                        safeBottom - valueFrame.maxY\n" +
                "                    )\n" +
                "                )\n" +
                "            )",
            "            let startRecheckIsContained =\n" +
                "                startRecheckFrame.minY >= safeTop\n" +
                "                && startRecheckFrame.maxY <= safeBottom",
            "            let targetCompositionIsSafe = startRecheckIsContained\n" +
                "                && dateIsContained\n" +
                "                && descriptionIsContained\n" +
                "                && valueIsContained\n" +
                "                && startRecheckButton.isHittable",
            "                  startRecheckFrame.height <= safeBottom - safeTop,",
            "                  minimumShift <= maximumShift,",
            "                  targetCompositionIsSafe || maximumShift < 0 else {",
            "            if targetCompositionIsSafe { break }",
            "            if maximumShift >= -receiverCapacity {",
            "                let recognizedMinimum = max(\n" +
                "                    minimumShift,\n" +
                "                    -receiverCapacity\n" +
                "                )",
            "                let recognizedMaximum = min(\n" +
                "                    maximumShift,\n" +
                "                    -minimumGestureDistance\n" +
                "                )",
            "                guard recognizedMinimum <= recognizedMaximum else {",
            "                dragDistance = recognizedMaximum",
            "                let stagedDistance = max(\n" +
                "                    -receiverCapacity,\n" +
                "                    maximumShift + minimumGestureDistance\n" +
                "                )",
            "                guard stagedDistance <= -minimumGestureDistance else {",
            "                dragDistance = stagedDistance",
            "                  dragDistance < 0,",
            "                  abs(dragDistance) >= minimumGestureDistance else {",
        ]
        for geometryLock in issueRecheckDueGeometryLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: geometryLock
                ).count - 1,
                1,
                geometryLock
            )
        }
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: "                && startRecheckButton.isHittable"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: "                dragDistance = recognizedMinimum"
            ).count - 1,
            0
        )

        let issueRecheckDueReceiverLocks = [
            "            let receiverFrame = CGRect(\n" +
                "                x: receiverLeft,\n" +
                "                y: receiverTop,\n" +
                "                width: receiverRight - receiverLeft,\n" +
                "                height: receiverBottom - receiverTop\n" +
                "            )",
            "            let startPoint = CGPoint(x: receiverRight, y: receiverBottom)",
            "            let endPoint = CGPoint(\n" +
                "                x: receiverRight,\n" +
                "                y: receiverBottom + dragDistance\n" +
                "            )",
            "                  startPoint.x >= receiverFrame.minX,",
            "                  startPoint.x <= receiverFrame.maxX,",
            "                  startPoint.y >= receiverFrame.minY,",
            "                  startPoint.y <= receiverFrame.maxY,",
            "                  endPoint.x >= receiverFrame.minX,",
            "                  endPoint.x <= receiverFrame.maxX,",
            "                  endPoint.y >= receiverFrame.minY,",
            "                  endPoint.y <= receiverFrame.maxY,",
            "                  liveScrollFrame.contains(startPoint),",
            "                  liveScrollFrame.contains(endPoint),",
            "                  !startRecheckFrame.contains(startPoint),",
            "                  !startRecheckFrame.contains(endPoint),",
            "                  !dateFrame.contains(startPoint),",
            "                  !dateFrame.contains(endPoint),",
            "                  !descriptionFrame.contains(startPoint),",
            "                  !descriptionFrame.contains(endPoint),",
            "                  !valueFrame.contains(startPoint),",
            "                  !valueFrame.contains(endPoint),",
            "                  !photoFrame.contains(startPoint),",
            "                  !photoFrame.contains(endPoint) else {",
            "            let scrollOrigin = issueScrollView.coordinate(\n" +
                "                withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "            )",
            "                    dx: startPoint.x - scrollFrame.minX,",
            "                    dy: startPoint.y - scrollFrame.minY",
            "                    dx: endPoint.x - scrollFrame.minX,",
            "                    dy: endPoint.y - scrollFrame.minY",
            "                forDuration: 0.2,",
            "                withVelocity: .slow,",
            "                thenHoldForDuration: 0.2",
        ]
        for receiverLock in issueRecheckDueReceiverLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: receiverLock
                ).count - 1,
                1,
                receiverLock
            )
        }
        for (gestureLock, count) in [
            (".coordinate(", 1),
            (".press(", 1),
            ("thenDragTo:", 1),
            ("forDuration: 0.2", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: gestureLock
                ).count - 1,
                count,
                gestureLock
            )
        }

        let issueRecheckDueProgressLocks = [
            "        var previousStartRecheckMinYAfterDrag: CGFloat?",
            "        var previousDateMinYAfterDrag: CGFloat?",
            "        var previousDescriptionMinYAfterDrag: CGFloat?",
            "        var previousValueMinYAfterDrag: CGFloat?",
            "        var previousPhotoMinYAfterDrag: CGFloat?",
            "            let startRecheckBeforeDrag = startRecheckFrame.minY",
            "            let dateBeforeDrag = dateFrame.minY",
            "            let descriptionBeforeDrag = descriptionFrame.minY",
            "            let valueBeforeDrag = valueFrame.minY",
            "            let photoBeforeDrag = photoFrame.minY",
            "            let startRecheckAfterDrag = startRecheckButton.frame",
            "            let dateAfterDrag = workDate.frame",
            "            let descriptionAfterDrag = workDescription.frame",
            "            let valueAfterDrag = descriptionValueText.frame",
            "            let photoAfterDrag = workPhoto.frame",
            "            let movedFramesAreValid = isValidFrame(startRecheckAfterDrag)",
            "            var observedStartRecheckShift: CGFloat?",
            "                observedStartRecheckShift =\n" +
                "                    startRecheckAfterDrag.minY - startRecheckBeforeDrag",
            "                observedDateShift = dateAfterDrag.minY - dateBeforeDrag",
            "                observedDescriptionShift =",
            "                observedValueShift = valueAfterDrag.minY - valueBeforeDrag",
            "                observedPhotoShift = photoAfterDrag.minY - photoBeforeDrag",
            "            guard let observedStartRecheckShift,",
            "                  observedStartRecheckShift * dragDistance > 0,",
            "                  observedDateShift * dragDistance > 0,",
            "                  observedDescriptionShift * dragDistance > 0,",
            "                  observedValueShift * dragDistance > 0,",
            "                  observedPhotoShift * dragDistance > 0 else {",
            "            if let previousStartRecheckMinYAfterDrag,",
            "                guard startRecheckAfterDrag.minY\n" +
                "                        < previousStartRecheckMinYAfterDrag,",
            "                      dateAfterDrag.minY < previousDateMinYAfterDrag,",
            "                      descriptionAfterDrag.minY",
            "                        < previousDescriptionMinYAfterDrag,",
            "                      valueAfterDrag.minY < previousValueMinYAfterDrag,",
            "                      photoAfterDrag.minY < previousPhotoMinYAfterDrag else {",
            "            previousStartRecheckMinYAfterDrag = startRecheckAfterDrag.minY",
            "            previousDateMinYAfterDrag = dateAfterDrag.minY",
            "            previousDescriptionMinYAfterDrag = descriptionAfterDrag.minY",
            "            previousValueMinYAfterDrag = valueAfterDrag.minY",
            "            previousPhotoMinYAfterDrag = photoAfterDrag.minY",
        ]
        for progressLock in issueRecheckDueProgressLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: progressLock
                ).count - 1,
                1,
                progressLock
            )
        }
        let issueRecheckDuePostGestureIdentityLock =
            "            guard hasExactIdentity() else {\n" +
                "                XCTFail(\"AX-text issue recheck-due route changed after positioning.\")\n" +
                "                return false\n" +
                "            }\n" +
                "            let startRecheckAfterDrag = startRecheckButton.frame"
        XCTAssertEqual(
            issueRecheckDuePositioningHelperSource.components(
                separatedBy: issueRecheckDuePostGestureIdentityLock
            ).count - 1,
            1
        )

        let issueRecheckDueFinalLocks = [
            "        guard hasExactIdentity() else {\n" +
                "            XCTFail(\"AX-text issue recheck-due final route is invalid.\")\n" +
                "            return false\n" +
                "        }\n" +
                "        let finalApplicationFrame = app.frame",
            "        let finalApplicationFrame = app.frame",
            "        let finalScreenFrame = issueScreen.frame",
            "        let finalScrollFrame = issueScrollView.frame",
            "        let finalNavigationFrame = issueNavigationBar.frame",
            "        let finalTabFrame = tabBar.frame",
            "        let finalStartRecheckFrame = startRecheckButton.frame",
            "        let finalRecordFrame = workRecord.frame",
            "        let finalDateFrame = workDate.frame",
            "        let finalDescriptionFrame = workDescription.frame",
            "        let finalValueFrame = descriptionValueText.frame",
            "        let finalPhotoFrame = workPhoto.frame",
            "        let finalFramesAreValid = isValidFrame(finalApplicationFrame)",
            "            && isValidFrame(finalStartRecheckFrame)",
            "            && finalScreenFrame == finalScrollFrame",
            "        var finalCompositionIsSafe = false",
            "            let finalLiveScrollFrame = finalScrollFrame.intersection(",
            "                    && finalRecordFrame.contains(finalDateFrame)",
            "                    && finalRecordFrame.contains(finalDescriptionFrame)",
            "                    && finalRecordFrame.contains(finalPhotoFrame)",
            "                    && finalDateFrame.maxY < finalDescriptionFrame.minY",
            "                    && finalDescriptionFrame.maxY < finalPhotoFrame.minY",
            "                    && finalStartRecheckFrame.minY >= finalSafeTop",
            "                    && finalStartRecheckFrame.maxY <= finalSafeBottom",
            "                    && finalDateFrame.minY >= finalSafeTop",
            "                    && finalDateFrame.maxY <= finalSafeBottom",
            "                    && finalDescriptionFrame.minY >= finalSafeTop",
            "                    && finalDescriptionFrame.maxY <= finalSafeBottom",
            "                    && finalValueFrame.minY >= finalSafeTop",
            "                    && finalValueFrame.maxY <= finalSafeBottom",
            "                    && startRecheckButton.isHittable",
            "                    && workDate.isHittable",
            "                    && workDescription.isHittable",
            "                    && descriptionValueText.isHittable",
            "        guard finalCompositionIsSafe else {",
            "        return true",
        ]
        for finalLock in issueRecheckDueFinalLocks {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: finalLock
                ).count - 1,
                1,
                finalLock
            )
        }

        let issueRecheckDueFailureMessages = [
            "AX-text issue recheck-due positioning bindings are ambiguous.",
            "AX-text issue recheck-due positioning route changed.",
            "AX-text issue recheck-due positioning geometry is invalid.",
            "AX-text issue recheck-due composition has no supported upward interval.",
            "AX-text issue recheck-due direct interval is not recognizable.",
            "AX-text issue recheck-due staged remainder is not recognizable.",
            "AX-text issue recheck-due drag direction is invalid.",
            "AX-text issue recheck-due drag receiver is obstructed.",
            "AX-text issue recheck-due route changed after positioning.",
            "AX-text issue recheck-due gesture made no signed progress.",
            "AX-text issue recheck-due positioning reversed direction.",
            "AX-text issue recheck-due final route is invalid.",
            "AX-text issue recheck-due final composition is unsafe.",
        ]
        var issueRecheckDueFailureSearchStart =
            issueRecheckDuePositioningHelperSource.startIndex
        for failureMessage in issueRecheckDueFailureMessages {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: failureMessage
                ).count - 1,
                1,
                failureMessage
            )
            guard let failureRange =
                    issueRecheckDuePositioningHelperSource.range(
                        of: failureMessage,
                        range: issueRecheckDueFailureSearchStart ..<
                            issueRecheckDuePositioningHelperSource.endIndex
                    ) else {
                XCTFail("Missing ordered issue recheck-due positioning failure")
                return
            }
            issueRecheckDueFailureSearchStart = failureRange.upperBound
        }
        XCTAssertEqual(issueRecheckDueFailureMessages.count, 13)
        for (failureLock, count) in [
            ("XCTFail(", 13),
            ("return false", 13),
            ("return true", 1),
        ] {
            XCTAssertEqual(
                issueRecheckDuePositioningHelperSource.components(
                    separatedBy: failureLock
                ).count - 1,
                count,
                failureLock
            )
        }

        for prohibitedIssueRecheckDuePositioningForm in [
            ".tap(",
            ".swipe",
            "scroll(",
            "waitForExistence",
            ".typeText(",
            "Thread.sleep",
            "sleep(",
            "performAccessibilityAudit",
            "XCTAttachment",
            "ContrastAuditExceptionSignature",
            "contrastAuditExceptionSignatures",
            "automationContrastExceptions",
            "captureBaseline(",
            "attachCandidate(",
            #"prefix: "S10_4_AX_STATE""#,
            #"prefix: "S10_4_CONTRAST""#,
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "S10_4_RETENTION",
            "maximumShift > 0",
            "minimumShift > 0",
            "observedDirection",
            "positionedDirection",
            "CGRect(x:",
        ] {
            XCTAssertFalse(
                issueRecheckDuePositioningHelperSource.contains(
                    prohibitedIssueRecheckDuePositioningForm
                ),
                prohibitedIssueRecheckDuePositioningForm
            )
        }
        for prohibitedIssueRecheckDueRouteForm in [
            ".tap(",
            ".swipe",
            ".coordinate(",
            ".press(",
            "thenDragTo:",
            "scroll(",
            "performAccessibilityAudit",
            "XCTAttachment",
            "printJSONLine",
            "NSNull",
            "diagnostic",
            "return",
        ] {
            XCTAssertFalse(
                issueRecheckDueRouteSource.contains(
                    prohibitedIssueRecheckDueRouteForm
                ),
                prohibitedIssueRecheckDueRouteForm
            )
        }

        for removedIssueRecheckDueDiagnosticForm in [
            "diagnoseAXTextIssueRecheckDueContrast",
            "S10_4_AX_TEXT_ISSUE_RECHECK_DUE_CONTRAST_",
            "S10.4 AX-text Issue recheck-due contrast diagnostic",
            "S10.4 AX-text issue recheck-due contrast diagnostic completed nonaccepting",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedIssueRecheckDueDiagnosticForm
                ).count - 1,
                0,
                removedIssueRecheckDueDiagnosticForm
            )
            XCTAssertEqual(
                restoredCaptureBaselineSource.components(
                    separatedBy: removedIssueRecheckDueDiagnosticForm
                ).count - 1,
                0,
                removedIssueRecheckDueDiagnosticForm
            )
        }

        let recheckPreflightDiagnosticRouteStart =
            "        startRecheck.tap()"
        let recheckPreflightDiagnosticRouteEnd =
            #"        captureBaseline("state.recheck-preflight.ready", in: app)"#
        guard let recheckPreflightDiagnosticRouteStartRange = uiSource.range(
            of: recheckPreflightDiagnosticRouteStart
        ), let recheckPreflightDiagnosticRouteEndRange = uiSource.range(
            of: recheckPreflightDiagnosticRouteEnd,
            range: recheckPreflightDiagnosticRouteStartRange.upperBound ..<
                uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text recheck-preflight diagnostic route")
            return
        }
        let recheckPreflightDiagnosticRouteSource = String(
            uiSource[
                recheckPreflightDiagnosticRouteStartRange.lowerBound ..<
                    recheckPreflightDiagnosticRouteEndRange.upperBound
            ]
        )
        XCTAssertEqual(recheckPreflightDiagnosticRouteSource.utf8.count, 484)
        XCTAssertEqual(
            Data(recheckPreflightDiagnosticRouteSource.utf8).sha256,
            "8199E8AC0DD2B674C3464901AE41B9CBED639B7AC63E6C752A2B20C9CE9B15CE"
        )
        let recheckPreflightDiagnosticRouteLock =
            "        startRecheck.tap()\n" +
                #"        XCTAssertTrue(element("s3.preflight.screen", in: app)"# +
                "\n" +
                "            .waitForExistence(timeout: 20))\n" +
                "        if let shard = automationShard,\n" +
                #"           shard.shardID == "s10.4.current.ax-text" {"# +
                "\n" +
                "            try diagnoseAXTextRecheckPreflightContrast(\n" +
                "                in: app,\n" +
                "                shard: shard,\n" +
                #"                stateID: "state.recheck-preflight.ready""# +
                "\n" +
                "            )\n" +
                "        }\n" +
                recheckPreflightDiagnosticRouteEnd
        XCTAssertEqual(
            recheckPreflightDiagnosticRouteSource.components(
                separatedBy: recheckPreflightDiagnosticRouteLock
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recheckPreflightDiagnosticRouteSource.components(
                separatedBy: "diagnoseAXTextRecheckPreflightContrast("
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recheckPreflightDiagnosticRouteSource.components(
                separatedBy: #"state.recheck-preflight.ready"#
            ).count - 1,
            2
        )

        let recheckPreflightDiagnosticHelperStart =
            "    @MainActor\n" +
                "    private func diagnoseAXTextRecheckPreflightContrast(\n" +
                "        in app: XCUIApplication,\n" +
                "        shard: AutomationShard,\n" +
                "        stateID: String\n" +
                "    ) throws {"
        guard let recheckPreflightDiagnosticHelperStartRange = uiSource.range(
            of: recheckPreflightDiagnosticHelperStart
        ), let recheckPreflightDiagnosticHelperEndRange = uiSource.range(
            of: captureBaselineStart,
            range: recheckPreflightDiagnosticHelperStartRange.upperBound ..<
                uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded AX-text recheck-preflight diagnostic helper")
            return
        }
        let recheckPreflightDiagnosticHelperEnd = uiSource.index(
            recheckPreflightDiagnosticHelperEndRange.lowerBound,
            offsetBy: -2
        )
        let recheckPreflightDiagnosticHelperSource = String(
            uiSource[
                recheckPreflightDiagnosticHelperStartRange.lowerBound ..<
                    recheckPreflightDiagnosticHelperEnd
            ]
        )
        XCTAssertEqual(recheckPreflightDiagnosticHelperSource.utf8.count, 7_839)
        XCTAssertEqual(
            Data(recheckPreflightDiagnosticHelperSource.utf8).sha256,
            "1F3725710D07A5FB510619721605D05A247A81FD70645F8AB94F9A21409C1F4D"
        )

        let recheckPreflightDiagnosticQueryDeclarations = [
            "        let preflightScreens = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s3.preflight.screen""# + "\n" +
                "        )",
            "        let preflightScrollViews = app.scrollViews.containing(\n" +
                "            .textField,\n" +
                #"            identifier: "s3.preflight.time-zone""# + "\n" +
                "        )",
            "        let beforeYouBeginStaticTexts = app.staticTexts.matching(\n" +
                "            NSPredicate(\n" +
                #"                format: "label == %@","# + "\n" +
                #"                "Before you begin""# + "\n" +
                "            )\n" +
                "        )",
            "        let navigationBars = app.navigationBars",
            "        let tabBars = app.tabBars",
            "        let beginControls = app.descendants(matching: .any).matching(\n" +
                #"            identifier: "s3.preflight.begin""# + "\n" +
                "        )",
        ]
        XCTAssertEqual(recheckPreflightDiagnosticQueryDeclarations.count, 6)
        for queryDeclaration in recheckPreflightDiagnosticQueryDeclarations {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: queryDeclaration
                ).count - 1,
                1,
                queryDeclaration
            )
        }
        let recheckPreflightDiagnosticQueryTuples = [
            #"            ("preflightScreens", preflightScreens),"#,
            #"            ("preflightScrollViews", preflightScrollViews),"#,
            #"            ("beforeYouBeginStaticTexts", beforeYouBeginStaticTexts),"#,
            #"            ("navigationBars", navigationBars),"#,
            #"            ("tabBars", tabBars),"#,
            #"            ("beginControls", beginControls),"#,
        ]
        XCTAssertEqual(recheckPreflightDiagnosticQueryTuples.count, 6)
        for queryTuple in recheckPreflightDiagnosticQueryTuples {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: queryTuple
                ).count - 1,
                1,
                queryTuple
            )
        }
        for diagnosticEnumerationLock in [
            "            let count = query.count",
            "            for index in 0..<count {",
            "                    diagnosticElementObject(query.element(boundBy: index))",
            #"                "count": count,"#,
            #"                "elements": elements,"#,
            "        for (name, query) in diagnosticQueries {",
            "            diagnosticQueryObjects[name] = diagnosticQueryObject(query)",
        ] {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: diagnosticEnumerationLock
                ).count - 1,
                1,
                diagnosticEnumerationLock
            )
        }
        for diagnosticNodeField in [
            #"                "exists": element.exists,"#,
            #"                "isHittable": element.isHittable,"#,
            #"                "isEnabled": element.isEnabled,"#,
            #"                "identifier": element.identifier,"#,
            #"                "label": element.label,"#,
            #"                "value": valueObject,"#,
            #"                "elementTypeRawValue": element.elementType.rawValue,"#,
            #"                "elementTypeDescription": String(describing: element.elementType),"#,
            #"                "frame": self.auditFrameObject(element.frame),"#,
        ] {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: diagnosticNodeField
                ).count - 1,
                1,
                diagnosticNodeField
            )
        }
        let recheckPreflightDiagnosticNullableValueSerializer =
            "            let valueObject: Any\n" +
                "            if let value = element.value as? String {\n" +
                "                valueObject = value\n" +
                "            } else {\n" +
                "                valueObject = NSNull()\n" +
                "            }"
        XCTAssertEqual(
            recheckPreflightDiagnosticHelperSource.components(
                separatedBy: recheckPreflightDiagnosticNullableValueSerializer
            ).count - 1,
            1
        )
        for diagnosticContextField in [
            "\n" + #"            "shardID": shard.shardID,"#,
            #"            "requirementID": shard.requirementID,"#,
            "\n" + #"            "deviceProfileID": shard.deviceProfileID,"#,
            "\n" + #"            "stateID": stateID,"#,
            #"            "elapsedMilliseconds": diagnosticElapsedMilliseconds,"#,
            #"            "applicationState": String(describing: app.state),"#,
            #"            "applicationStateRawValue": app.state.rawValue,"#,
            #"            "isRunningForeground": app.state == .runningForeground,"#,
            #"            "applicationFrame": auditFrameObject(app.frame),"#,
            #"            "queries": diagnosticQueryObjects,"#,
        ] {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: diagnosticContextField
                ).count - 1,
                1,
                diagnosticContextField
            )
        }
        for diagnosticIssueField in [
            #"                    "ordinal": observedIssueCount,"#,
            #"                    "auditTypeRawValue": String(issue.auditType.rawValue),"#,
            #"                    "compactDescription": issue.compactDescription,"#,
            #"                    "detailedDescription": issue.detailedDescription,"#,
            #"                    "elementIdentifier": elementIdentifier,"#,
            #"                    "elementLabel": elementLabel,"#,
            #"                    "elementType": elementType,"#,
            #"                    "elementFrame": elementFrame,"#,
            #"                    "applicationFrame": self.auditFrameObject(app.frame),"#,
            #"                    "auditedElement": auditedElementObject,"#,
        ] {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: diagnosticIssueField
                ).count - 1,
                1,
                diagnosticIssueField
            )
        }
        let recheckPreflightDiagnosticNilIssueElementSerializer =
            "            } else {\n" +
                "                auditedElementObject = NSNull()\n" +
                "                elementIdentifier = NSNull()\n" +
                "                elementLabel = NSNull()\n" +
                "                elementType = NSNull()\n" +
                "                elementFrame = NSNull()\n" +
                "            }"
        XCTAssertEqual(
            recheckPreflightDiagnosticHelperSource.components(
                separatedBy: recheckPreflightDiagnosticNilIssueElementSerializer
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recheckPreflightDiagnosticHelperSource.components(
                separatedBy: "NSNull()"
            ).count - 1,
            6
        )
        for (diagnosticCardinalityLock, expectedCount) in [
            ("XCTAttachment(", 4),
            (".lifetime = .keepAlways", 4),
            ("        add(", 4),
            ("try app.performAccessibilityAudit(for: .contrast)", 1),
            ("            return true", 1),
            ("return false", 0),
            (#""observedIssueCount": observedIssueCount"#, 1),
            (#""auditedElementCount": diagnosticAuditedElements.count"#, 1),
        ] {
            XCTAssertEqual(
                recheckPreflightDiagnosticHelperSource.components(
                    separatedBy: diagnosticCardinalityLock
                ).count - 1,
                expectedCount,
                diagnosticCardinalityLock
            )
        }

        let recheckPreflightDiagnosticOrderedFragments = [
            "S10_4_AX_TEXT_RECHECK_PREFLIGHT_CONTRAST_CONTEXT_DIAGNOSTIC",
            "        let appScreenshotAttachment = XCTAttachment(",
            "        let appTreeAttachment = XCTAttachment(string: app.debugDescription)",
            "        let contextData = try JSONSerialization.data(",
            "        let contextAttachment = XCTAttachment(",
            "        try app.performAccessibilityAudit(for: .contrast) { issue in",
            "S10_4_AX_TEXT_RECHECK_PREFLIGHT_CONTRAST_ISSUE_DIAGNOSTIC",
            "        for (index, auditedElement) in diagnosticAuditedElements.enumerated() {",
            "S10_4_AX_TEXT_RECHECK_PREFLIGHT_CONTRAST_COUNT_DIAGNOSTIC",
            "        throw AutomationConfigurationError.invalid(",
        ]
        var recheckPreflightDiagnosticSearchStart =
            recheckPreflightDiagnosticHelperSource.startIndex
        for orderedFragment in recheckPreflightDiagnosticOrderedFragments {
            guard let orderedRange = recheckPreflightDiagnosticHelperSource.range(
                of: orderedFragment,
                range: recheckPreflightDiagnosticSearchStart ..<
                    recheckPreflightDiagnosticHelperSource.endIndex
            ) else {
                XCTFail("Missing ordered recheck-preflight diagnostic fragment: \(orderedFragment)")
                return
            }
            recheckPreflightDiagnosticSearchStart = orderedRange.upperBound
        }
        let recheckPreflightDiagnosticTerminal =
            "        throw AutomationConfigurationError.invalid(\n" +
                "            \"S10.4 AX-text recheck-preflight contrast diagnostic completed nonaccepting observedIssueCount=\\(observedIssueCount)\"\n" +
                "        )\n" +
                "    }"
        XCTAssertTrue(
            recheckPreflightDiagnosticHelperSource.hasSuffix(
                recheckPreflightDiagnosticTerminal
            )
        )
        for prohibitedRecheckPreflightDiagnosticForm in [
            ".tap(",
            ".swipe",
            ".coordinate(",
            ".press(",
            "thenDragTo:",
            "scroll(",
            ".typeText(",
            "waitForExistence",
            "waitForNonExistence",
            "Thread.sleep",
            "sleep(",
            "CGRect(",
            "count ==",
            ".firstMatch",
            ".filter",
            "matchingExceptions",
            "eligibleExceptions",
            "contrastAuditExceptionSignatures",
            "automationContrastExceptions",
            "automationAXTreeDigests",
            #"prefix: "S10_4_AX_STATE""#,
            #"prefix: "S10_4_CONTRAST""#,
            "S10_4_CANDIDATE",
            "S10_4_TASK",
            "S10_4_SHARD_RECEIPT",
            "S10_4_RETENTION",
            "captureBaseline(",
            "attachCandidate(",
        ] {
            XCTAssertFalse(
                recheckPreflightDiagnosticHelperSource.contains(
                    prohibitedRecheckPreflightDiagnosticForm
                ),
                prohibitedRecheckPreflightDiagnosticForm
            )
        }

        for removedAXTextWorkSavingContrastDiagnostic in [
            "diagnoseAXTextWorkSavingContrast",
            "S10_4_AX_TEXT_WORK_SAVING_CONTRAST_",
            "S10.4 AX-text Record-work saving contrast diagnostic",
            #"if shard.shardID == "s10.4.current.ax-text","# + "\n" +
                #"               stateID == "state.work.saving" {"#,
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedAXTextWorkSavingContrastDiagnostic
                ).count - 1,
                0,
                removedAXTextWorkSavingContrastDiagnostic
            )
            XCTAssertEqual(
                restoredCaptureBaselineSource.components(
                    separatedBy: removedAXTextWorkSavingContrastDiagnostic
                ).count - 1,
                0,
                removedAXTextWorkSavingContrastDiagnostic
            )
        }
        for removedReduceMotionWorkSavingDiagnosticForm in [
            "diagnoseReduceMotionWorkSavingContrast",
            "S10_4_REDUCE_MOTION_WORK_SAVING_CONTEXT_DIAGNOSTIC",
            "S10_4_REDUCE_MOTION_WORK_SAVING_ISSUE_DIAGNOSTIC",
            "S10_4_REDUCE_MOTION_WORK_SAVING_COUNT_DIAGNOSTIC",
            "S10.4 s10.4.current.reduce-motion Record-work saving contrast diagnostic",
            "S10.4 reduce-motion Record-work saving contrast diagnostic completed nonaccepting",
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
                separatedBy: #"stateID: "state.issue.recheck-due""#
            ).count - 1,
            1
        )
        XCTAssertEqual(
            contrastAuthoritySource.components(
                separatedBy: "ContrastAuditExceptionSignature("
            ).count - 1,
            16
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
            byteCount: 14_935,
            sha256: "AE8A857D879ACC66D3B422259A09D6811C4FBBEE36884EFAD584795E804AE275"
        )
        let recordWorkSource = try text(recordWorkSourcePath)
        let recordWorkSavingPresentationSelection =
            "        let minimumSavingPresentationNanoseconds: UInt64 =\n" +
                "            usesImportedFixtureForUITest\n" +
                "                ? (photos.isEmpty ? 45_000_000_000 : 75_000_000_000)\n" +
                "                : 5_000_000_000"
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: recordWorkSavingPresentationSelection
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "45_000_000_000"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "75_000_000_000"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "30_000_000_000"
            ).count - 1,
            0
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "15_000_000_000"
            ).count - 1,
            0
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: ": 5_000_000_000"
            ).count - 1,
            1
        )
        let recordWorkSavingCoordinatorOrder =
            "        Task {\n" +
                "            let minimumSavingPresentation = Task<Void, Never> {\n" +
                "                try? await Task.sleep(\n" +
                "                    nanoseconds: minimumSavingPresentationNanoseconds\n" +
                "                )\n" +
                "            }\n" +
                "            do {\n" +
                "                let issue = try await coordinator.saveWork("
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: recordWorkSavingCoordinatorOrder
            ).count - 1,
            1
        )
        let recordWorkSavingCompletionOrder =
            "                )\n" +
                "                await minimumSavingPresentation.value\n" +
                "                isSaving = false\n" +
                "                onComplete(issue)\n" +
                "            } catch {\n" +
                "                await minimumSavingPresentation.value\n" +
                "                isSaving = false\n" +
                "                showsFailure = true"
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: recordWorkSavingCompletionOrder
            ).count - 1,
            1
        )
        XCTAssertEqual(
            recordWorkSource.components(
                separatedBy: "await minimumSavingPresentation.value"
            ).count - 1,
            2
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
            byteCount: 17_370,
            sha256: "B4A7FDD087CCBE4B0644EA81184209CDEADC960176D5C61CE851A5145FDA0782"
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
                14_935,
                "AE8A857D879ACC66D3B422259A09D6811C4FBBEE36884EFAD584795E804AE275",
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
            "if !runsAXTextDeleteConfirmationDiagnostic\n" +
                "            && !runsMinimumDoubleLengthDeleteComposition {",
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
        let doubleLengthGateStart =
            "        let runsMinimumDoubleLengthDeleteComposition ="
        let doubleLengthGateEnd =
            "        let runsAXTextDeleteConfirmationDiagnostic ="
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthGateStart).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: doubleLengthGateEnd).count - 1,
            1
        )
        guard let doubleLengthGateStartRange = uiSource.range(
            of: doubleLengthGateStart
        ), let doubleLengthGateEndRange = uiSource.range(
            of: doubleLengthGateEnd,
            range: doubleLengthGateStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the minimum double-length positioning gate source slice")
            return
        }
        let doubleLengthGateSource = String(
            uiSource[
                doubleLengthGateStartRange.lowerBound..<doubleLengthGateEndRange.lowerBound
            ]
        )
        XCTAssertEqual(doubleLengthGateSource.utf8.count, 4_992)
        XCTAssertEqual(
            Data(doubleLengthGateSource.utf8).sha256,
            "DD07155F3ED487F3EA95C2D251CD5A1A5B8CF9C2BC3906106D7C1B7C2DAB8998"
        )
        let doubleLengthGateContracts = [
            "        let runsMinimumDoubleLengthDeleteComposition =\n" +
                "            automationShard?.shardID == \"s10.4.minimum.double-length\"",
            "        if runsMinimumDoubleLengthDeleteComposition {",
            "            let messageScrollViews = app.scrollViews.containing(\n" +
                "                .staticText,\n" +
                "                identifier: \"s6.1.delete.message\"\n" +
                "            )",
            "            let cancelScrollViews = app.scrollViews.containing(\n" +
                "                .button,\n" +
                "                identifier: \"s6.1.delete.cancel\"\n" +
                "            )",
            "            let confirmScrollViews = app.scrollViews.containing(\n" +
                "                .button,\n" +
                "                identifier: \"s6.1.delete.confirm\"\n" +
                "            )",
            "            let siteScrollViews = app.scrollViews.containing(\n" +
                "                .staticText,\n" +
                "                identifier: \"s2.sign-detail.site-label\"\n" +
                "            )",
            "                  messageScrollViews.count == 1,\n" +
                "                  cancelScrollViews.count == 1,\n" +
                "                  confirmScrollViews.count == 1,\n" +
                "                  siteScrollViews.count == 1,",
            "                  messageScrollViews.firstMatch.identifier == detail.identifier,\n" +
                "                  cancelScrollViews.firstMatch.identifier == detail.identifier,\n" +
                "                  confirmScrollViews.firstMatch.identifier == detail.identifier,\n" +
                "                  siteScrollViews.firstMatch.identifier == detail.identifier else {",
            "            let dragInset: CGFloat = 24",
            "            let minimumVisibleIntersection: CGFloat = 44",
            "            for _ in 0..<4 {",
            "                let viewportTop = detail.frame.minY",
            "                let viewportBottom = detail.frame.maxY",
            "                let messageFrame = deleteMessage.frame",
            "                let cancelFrame = cancelDelete.frame",
            "                let confirmFrame = confirmDelete.frame",
            "                let minimumShift = max(",
            "                let maximumShift = min(",
            "                      minimumShift <= maximumShift else {",
            "                if minimumShift <= 0 && maximumShift >= 0 { break }",
            "                let targetDistance = maximumShift < 0\n" +
                "                    ? minimumShift\n" +
                "                    : maximumShift",
            "                let maximumGestureDistance = viewportBottom\n" +
                "                    - viewportTop\n" +
                "                    - 2 * dragInset",
            "                guard maximumGestureDistance >= minimumVisibleIntersection,\n" +
                "                      abs(targetDistance) >= minimumVisibleIntersection else {",
            "                let dragDistance = targetDistance > 0\n" +
                "                    ? min(targetDistance, maximumGestureDistance)\n" +
                "                    : max(targetDistance, -maximumGestureDistance)",
            "                let scrollOrigin = detail.coordinate(\n" +
                "                    withNormalizedOffset: CGVector(dx: 0, dy: 0)\n" +
                "                )",
            "                dragStart.press(\n" +
                "                    forDuration: 0.2,\n" +
                "                    thenDragTo: dragEnd,\n" +
                "                    withVelocity: .slow,\n" +
                "                    thenHoldForDuration: 0.2\n" +
                "                )",
        ]
        for contract in doubleLengthGateContracts {
            XCTAssertTrue(
                doubleLengthGateSource.contains(contract),
                contract
            )
        }
        for (fragment, count) in [
            ("runsMinimumDoubleLengthDeleteComposition", 2),
            ("app.scrollViews.containing(", 4),
            ("firstMatch.identifier == detail.identifier", 4),
            ("app.state == .runningForeground", 2),
            ("dragInset", 4),
            ("minimumVisibleIntersection", 7),
            ("for _ in 0..<4", 1),
            ("viewportTop", 6),
            ("viewportBottom", 6),
            ("messageFrame", 3),
            ("cancelFrame", 3),
            ("confirmFrame", 5),
            ("minimumShift", 4),
            ("maximumShift", 5),
            ("maximumGestureDistance", 4),
            ("detail.coordinate(", 1),
            ("withNormalizedOffset: CGVector(dx: 0, dy: 0)", 1),
            ("press(", 1),
            ("forDuration: 0.2", 1),
            ("thenDragTo:", 1),
            ("withVelocity: .slow", 1),
            ("thenHoldForDuration: 0.2", 1),
        ] {
            XCTAssertEqual(
                doubleLengthGateSource.components(separatedBy: fragment).count - 1,
                count,
                fragment
            )
        }
        for prohibitedDoubleLengthGateForm in [
            "tap(",
            "swipe",
            "scroll(",
            "sleep",
            "wait(",
            "XCTAttachment",
            "printJSONLine",
            "captureBaseline(",
            "throw AutomationConfigurationError.invalid",
            "diagnosticElementObject",
            "diagnosticQueryObject",
            "S10_4_DOUBLE_LENGTH_DELETE_DIAGNOSTIC",
            "diagnosticPreferredContainsZero",
            "diagnosticFallbackContainsZero",
            "diagnosticTargetDistance",
            "diagnosticQueryObjects",
        ] {
            XCTAssertFalse(
                doubleLengthGateSource.contains(prohibitedDoubleLengthGateForm),
                prohibitedDoubleLengthGateForm
            )
        }

        let doubleLengthFinalGateStart =
            "        if runsMinimumDoubleLengthDeleteComposition {\n" +
                "            let finalViewportFrame = detail.frame"
        let doubleLengthFinalGateEnd =
            "\n        captureBaseline(deleteConfirmationStateID, in: app)"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: doubleLengthFinalGateStart
            ).count - 1,
            1
        )
        guard let doubleLengthFinalGateStartRange = uiSource.range(
            of: doubleLengthFinalGateStart
        ), let doubleLengthFinalGateEndRange = uiSource.range(
            of: doubleLengthFinalGateEnd,
            range: doubleLengthFinalGateStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the minimum double-length final gate source slice")
            return
        }
        let doubleLengthFinalGateSource = String(
            uiSource[
                doubleLengthFinalGateStartRange.lowerBound..<doubleLengthFinalGateEndRange.lowerBound
            ]
        )
        XCTAssertEqual(doubleLengthFinalGateSource.utf8.count, 1_924)
        XCTAssertEqual(
            Data(doubleLengthFinalGateSource.utf8).sha256,
            "569209FA78D3C972FA0E2DBE7F946D651406842734143609FCD7462605056F83"
        )
        let doubleLengthFinalGateContracts = [
            "        if runsMinimumDoubleLengthDeleteComposition {\n" +
                "            let finalViewportFrame = detail.frame",
            "            let finalMessageIntersection = deleteMessage.frame.intersection(\n" +
                "                finalViewportFrame\n" +
                "            )",
            "            let finalCancelFrame = cancelDelete.frame",
            "            let finalConfirmFrame = confirmDelete.frame",
            "            let finalConfirmIntersection = finalConfirmFrame.intersection(\n" +
                "                finalViewportFrame\n" +
                "            )",
            "            guard app.state == .runningForeground,\n",
            "                  !finalMessageIntersection.isNull,\n" +
                "                  finalMessageIntersection.height >= 44,\n" +
                "                  finalCancelFrame.minY >= finalViewportFrame.minY,\n" +
                "                  finalCancelFrame.maxY <= finalViewportFrame.maxY,\n" +
                "                  finalConfirmFrame.midY >= finalViewportFrame.minY,\n" +
                "                  finalConfirmFrame.midY <= finalViewportFrame.maxY,\n" +
                "                  !finalConfirmIntersection.isNull,\n" +
                "                  finalConfirmIntersection.height >= 44,\n" +
                "                  cancelDelete.isHittable,\n" +
                "                  confirmDelete.isHittable else {",
            #"                    "Minimum double-length delete composition is not usable.""#,
        ]
        for contract in doubleLengthFinalGateContracts {
            XCTAssertTrue(
                doubleLengthFinalGateSource.contains(contract),
                contract
            )
        }
        for (fragment, count) in [
            ("runsMinimumDoubleLengthDeleteComposition", 1),
            ("app.scrollViews.containing(", 4),
            ("app.state == .runningForeground", 1),
            ("finalViewportFrame", 7),
            ("finalMessageIntersection", 3),
            ("finalCancelFrame", 3),
            ("finalConfirmFrame", 4),
            ("finalConfirmIntersection", 3),
            ("!finalMessageIntersection.isNull", 1),
            ("finalMessageIntersection.height >= 44", 1),
            ("finalCancelFrame.minY >= finalViewportFrame.minY", 1),
            ("finalCancelFrame.maxY <= finalViewportFrame.maxY", 1),
            ("finalConfirmFrame.midY >= finalViewportFrame.minY", 1),
            ("finalConfirmFrame.midY <= finalViewportFrame.maxY", 1),
            ("!finalConfirmIntersection.isNull", 1),
            ("finalConfirmIntersection.height >= 44", 1),
            ("cancelDelete.isHittable", 1),
            ("confirmDelete.isHittable", 1),
        ] {
            XCTAssertEqual(
                doubleLengthFinalGateSource.components(separatedBy: fragment).count - 1,
                count,
                fragment
            )
        }
        for prohibitedDoubleLengthFinalGateForm in [
            "tap(",
            "swipe",
            "scroll(",
            "sleep",
            "wait(",
            "XCTAttachment",
            "printJSONLine",
            "captureBaseline(",
            "throw AutomationConfigurationError.invalid",
            "diagnosticElementObject",
            "diagnosticQueryObject",
            "S10_4_DOUBLE_LENGTH_DELETE_DIAGNOSTIC",
        ] {
            XCTAssertFalse(
                doubleLengthFinalGateSource.contains(prohibitedDoubleLengthFinalGateForm),
                prohibitedDoubleLengthFinalGateForm
            )
        }
        let unchangedDeleteCaptureAndActionOrder =
            "        captureBaseline(deleteConfirmationStateID, in: app)\n" +
                "        assertControl(cancelDelete, label: \"Cancel\")\n" +
                "        cancelDelete.tap()\n" +
                "        XCTAssertTrue(detail.waitForExistence(timeout: 20))"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: unchangedDeleteCaptureAndActionOrder
            ).count - 1,
            1
        )
        for removedDoubleLengthDiagnosticResidue in [
            "S10_4_DOUBLE_LENGTH_DELETE_DIAGNOSTIC",
            "diagnosticTargetDistanceObject",
            "S10.4 minimum double-length delete-confirmation diagnostic",
            "S10.4 double-length delete diagnostic",
            "appScreenshot.name = \"S10.4 double-length delete diagnostic app\"",
            "appTree.name = \"S10.4 double-length delete diagnostic tree\"",
            "detailScreenshot.name = \"S10.4 double-length delete diagnostic detail\"",
            "messageScreenshot.name = \"S10.4 double-length delete diagnostic message\"",
        ] {
            XCTAssertEqual(
                uiSource.components(
                    separatedBy: removedDoubleLengthDiagnosticResidue
                ).count - 1,
                0,
                removedDoubleLengthDiagnosticResidue
            )
        }

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
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT",
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-ISSUE-RECHECK-DUE-SECTION-APPEARS-DARK",
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
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier Short description field label whose frozen public frame intersects native Record work navigation chrome and is not hittable, while the separate identified Short description validation node is fully visible, hittable, and rendered with primaryText; the audit-owned crop confirms the issue is limited to that chrome-overlapped composition, and the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the lower North Campus label whose frozen public node frame intersects native bottom chrome after bounded positioning makes the header safe and hittable and moves the Visit composite below the application; an exact remaining positive ScrollView drag is unrecognized with zero measured header, lower-label, and Visit movement, while ReportsRootView already renders the label with primaryText; the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the Reports-index North Campus label whose frozen public frame intersects native bottom tab chrome even though ReportsRootView already renders it with primaryText; the audit-owned crop confirms the issue is limited to that chrome-overlapped composition, and the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the Reports-index Visit label whose frozen public frame begins inside native bottom tab chrome, extends below the 402x874 application frame, and is not hittable even though ReportsRootView already renders it with primaryText; the audit-owned crop confirms the issue is limited to that chrome-clipped composition, and the exception is limited to the frozen public issue signature.",
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Section appears dark header whose frozen public frame intersects the native Recheck due navigation material in the AX-text issue-recheck-due state even though IssueDetailView renders it with primaryText; exact live geometry proves no rigid ScrollView shift can simultaneously place that header and the required Start recheck and saved-work composition clear of native top and bottom chrome, and the exception is limited to the frozen public issue signature.",
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
            10
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
            ("state.work.validation-error", 1),
            ("state.issue.recheck-due", 1),
            ("state.report-history.ready", 1),
            ("state.reports-index.ready", 2),
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
            16
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: #"issueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            16
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-"#
            ).count - 1,
            32
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"owner: "palatis3""#).count - 1,
            16
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionOwner: "palatis3""#)
                .count - 1,
            16
        )
        XCTAssertEqual(
            uiSource.components(separatedBy: #"expiresAt: "2026-11-20""#).count - 1,
            16
        )
        XCTAssertEqual(
            workflowSource.components(separatedBy: #"exceptionExpiresAt: "2026-11-20""#)
                .count - 1,
            16
        )

        let signatureLocks = [
            #"taskID: "report_comprehension""#,
            #"taskID: "one_handed_start""#,
            #"taskID: "history_recovery""#,
            #"taskID: "work_and_recheck""#,
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
            #"issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT""#,
            #"issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION""#,
            #"shardID: "s10.4.current.default-light""#,
            #"shardID: "s10.4.current.increased-contrast""#,
            #"shardID: "s10.4.current.reduce-motion""#,
            #"shardID: "s10.4.current.differentiate-without-color""#,
            #"shardID: "s10.4.current.reduce-transparency""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.report-history.ready""#,
            #"stateID: "state.reports-index.ready""#,
            #"stateID: "state.work.validation-error""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"elementIdentifier: "s4.5.correction.header""#,
            #"elementLabel: "Correct report""#,
            #"elementLabel: "Short description""#,
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
            "y: 775.33333333333337",
            "height: 63.333333333333258",
            "y: 850.66666666666663",
            "width: 85.333333333333329",
            "height: 51.333333333333485",
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
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT""#,
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION""#,
            #"shardID: "s10.4.current.default-light""#,
            #"shardID: "s10.4.current.increased-contrast""#,
            #"shardID: "s10.4.current.reduce-motion""#,
            #"shardID: "s10.4.current.differentiate-without-color""#,
            #"shardID: "s10.4.current.reduce-transparency""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.report-history.ready""#,
            #"stateID: "state.reports-index.ready""#,
            #"stateID: "state.work.validation-error""#,
            #"stateID: "state.report-correction.validation-error""#,
            #"elementIdentifier: "s4.5.correction.header""#,
            #"elementLabel: "Correct report""#,
            #"elementLabel: "Short description""#,
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
            "y: 775.33333333333337",
            "height: 63.333333333333258",
            "y: 850.66666666666663",
            "width: 85.333333333333329",
            "height: 51.333333333333485",
            "y: -34.333333333333343",
            "width: 298.33333333333331",
            "height: 86.333333333333343",
            "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        for lock in workflowSignatureLocks {
            XCTAssertTrue(workflowSource.contains(lock), lock)
        }

        let workValidationExceptionID =
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION"
        let workValidationExceptionRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier Short description field label whose frozen public frame intersects native Record work navigation chrome and is not hittable, while the separate identified Short description validation node is fully visible, hittable, and rendered with primaryText; the audit-owned crop confirms the issue is limited to that chrome-overlapped composition, and the exception is limited to the frozen public issue signature."
        let workValidationUIAuthority =
            "        ContrastAuditExceptionSignature(\n" +
                "            issueID: \"\(workValidationExceptionID)\",\n" +
                #"            shardID: "s10.4.current.ax-text","# + "\n" +
                #"            stateID: "state.work.validation-error","# + "\n" +
                #"            taskID: "work_and_recheck","# + "\n" +
                #"            owner: "palatis3","# + "\n" +
                #"            expiresAt: "2026-11-20","# + "\n" +
                "            rationale: \"\(workValidationExceptionRationale)\",\n" +
                #"            auditTypeRawValue: "1","# + "\n" +
                #"            compactDescription: "Contrast failed","# + "\n" +
                #"            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","# + "\n" +
                #"            elementIdentifier: "","# + "\n" +
                #"            elementLabel: "Short description","# + "\n" +
                #"            elementTypeDescription: "XCUIElementType(rawValue: 48)","# + "\n" +
                "            elementFrame: CGRect(\n" +
                "                x: 30.333333333333332,\n" +
                "                y: 36.666666666666686,\n" +
                "                width: 333.66666666666663,\n" +
                "                height: 51.333333333333314\n" +
                "            ),\n" +
                "            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)\n" +
                "        ),"
        let workValidationWorkflowAuthority =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.work.validation-error","# + "\n" +
                #"                taskID: "work_and_recheck","# + "\n" +
                "                exceptionIssueID: \"\(workValidationExceptionID)\",\n" +
                #"                exceptionOwner: "palatis3","# + "\n" +
                #"                exceptionExpiresAt: "2026-11-20","# + "\n" +
                "                exceptionRationale: \"\(workValidationExceptionRationale)\",\n" +
                "                ignoredAuditIssues: [\n" +
                "                  {\n" +
                #"                    auditTypeRawValue: "1","# + "\n" +
                #"                    compactDescription: "Contrast failed","# + "\n" +
                #"                    detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","# + "\n" +
                #"                    elementIdentifier: "","# + "\n" +
                #"                    elementLabel: "Short description","# + "\n" +
                #"                    elementType: "XCUIElementType(rawValue: 48)","# + "\n" +
                "                    elementFrame: {\n" +
                "                      x: 30.333333333333332,\n" +
                "                      y: 36.666666666666686,\n" +
                "                      width: 333.66666666666663,\n" +
                "                      height: 51.333333333333314\n" +
                "                    },\n" +
                "                    applicationFrame: {x: 0, y: 0, width: 402, height: 874}\n" +
                "                  }\n" +
                "                ]\n" +
                "              },"
        let workValidationWorkflowTuple =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.work.validation-error","# + "\n" +
                #"                taskID: "work_and_recheck","# + "\n" +
                "                exceptionIssueID: \"\(workValidationExceptionID)\"\n" +
                "              },"
        for (source, authority, label) in [
            (uiSource, workValidationUIAuthority, "work-validation UI authority"),
            (
                workflowSource,
                workValidationWorkflowAuthority,
                "work-validation workflow authority"
            ),
            (
                workflowSource,
                workValidationWorkflowTuple,
                "work-validation workflow tuple"
            ),
        ] {
            XCTAssertEqual(
                source.components(separatedBy: authority).count - 1,
                1,
                label
            )
            let missing = source.replacingOccurrences(of: authority, with: "")
            XCTAssertEqual(
                missing.components(separatedBy: authority).count - 1,
                0,
                label
            )
            let duplicated = source.replacingOccurrences(
                of: authority,
                with: authority + authority
            )
            XCTAssertEqual(
                duplicated.components(separatedBy: authority).count - 1,
                2,
                label
            )
        }
        let workValidationUIFieldMutations = [
            (
                "duplicate issue ID",
                workValidationExceptionID,
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.work.validation-error", "state.work.editing"),
            ("wrong task", "work_and_recheck", "one_handed_start"),
            ("wrong owner", #"owner: "palatis3""#, #"owner: "unknown""#),
            ("expired", #"expiresAt: "2026-11-20""#, #"expiresAt: "2026-08-21""#),
            (
                "broad rationale",
                workValidationExceptionRationale,
                "Native navigation overlap."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            ("wrong identifier", #"elementIdentifier: """#, #"elementIdentifier: "unexpected""#),
            (
                "wrong label",
                #"elementLabel: "Short description""#,
                #"elementLabel: "Description""#
            ),
            (
                "wrong type",
                #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
                #"elementTypeDescription: "XCUIElementType(rawValue: 49)""#
            ),
            (
                "wrong x",
                "                x: 30.333333333333332,",
                "                x: 30.333333333333333,"
            ),
            (
                "wrong y",
                "                y: 36.666666666666686,",
                "                y: 36.666666666666687,"
            ),
            (
                "wrong width",
                "                width: 333.66666666666663,",
                "                width: 333.66666666666664,"
            ),
            (
                "wrong height",
                "                height: 51.333333333333314",
                "                height: 51.333333333333315"
            ),
            (
                "wrong application frame",
                "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
                "applicationFrame: CGRect(x: 0, y: 0, width: 401, height: 874)"
            ),
        ]
        let workValidationWorkflowFieldMutations = [
            (
                "duplicate issue ID",
                workValidationExceptionID,
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.work.validation-error", "state.work.editing"),
            ("wrong task", "work_and_recheck", "one_handed_start"),
            (
                "wrong owner",
                #"exceptionOwner: "palatis3""#,
                #"exceptionOwner: "unknown""#
            ),
            (
                "expired",
                #"exceptionExpiresAt: "2026-11-20""#,
                #"exceptionExpiresAt: "2026-08-21""#
            ),
            (
                "broad rationale",
                workValidationExceptionRationale,
                "Native navigation overlap."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            ("wrong identifier", #"elementIdentifier: """#, #"elementIdentifier: "unexpected""#),
            (
                "wrong label",
                #"elementLabel: "Short description""#,
                #"elementLabel: "Description""#
            ),
            (
                "wrong type",
                #"elementType: "XCUIElementType(rawValue: 48)""#,
                #"elementType: "XCUIElementType(rawValue: 49)""#
            ),
            (
                "wrong x",
                "                      x: 30.333333333333332,",
                "                      x: 30.333333333333333,"
            ),
            (
                "wrong y",
                "                      y: 36.666666666666686,",
                "                      y: 36.666666666666687,"
            ),
            (
                "wrong width",
                "                      width: 333.66666666666663,",
                "                      width: 333.66666666666664,"
            ),
            (
                "wrong height",
                "                      height: 51.333333333333314",
                "                      height: 51.333333333333315"
            ),
            (
                "wrong application frame",
                "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
                "applicationFrame: {x: 0, y: 0, width: 401, height: 874}"
            ),
        ]
        for (source, authority, mutations) in [
            (uiSource, workValidationUIAuthority, workValidationUIFieldMutations),
            (
                workflowSource,
                workValidationWorkflowAuthority,
                workValidationWorkflowFieldMutations
            ),
        ] {
            for (label, original, mutation) in mutations {
                XCTAssertTrue(authority.contains(original), label)
                let mutatedAuthority = authority.replacingOccurrences(
                    of: original,
                    with: mutation
                )
                XCTAssertNotEqual(mutatedAuthority, authority, label)
                let mutatedSource = source.replacingOccurrences(
                    of: authority,
                    with: mutatedAuthority
                )
                XCTAssertEqual(
                    mutatedSource.components(separatedBy: authority).count - 1,
                    0,
                    label
                )
            }
        }
        let workValidationUIPublicFieldLines = [
            #"            auditTypeRawValue: "1","#,
            #"            compactDescription: "Contrast failed","#,
            #"            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","#,
            #"            elementIdentifier: "","#,
            #"            elementLabel: "Short description","#,
            #"            elementTypeDescription: "XCUIElementType(rawValue: 48)","#,
            "            elementFrame: CGRect(",
            "            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
        ]
        let workValidationWorkflowPublicFieldLines = [
            #"                    auditTypeRawValue: "1","#,
            #"                    compactDescription: "Contrast failed","#,
            #"                    detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","#,
            #"                    elementIdentifier: "","#,
            #"                    elementLabel: "Short description","#,
            #"                    elementType: "XCUIElementType(rawValue: 48)","#,
            "                    elementFrame: {",
            "                    applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        for (authority, fields) in [
            (workValidationUIAuthority, workValidationUIPublicFieldLines),
            (
                workValidationWorkflowAuthority,
                workValidationWorkflowPublicFieldLines
            ),
        ] {
            for field in fields {
                XCTAssertEqual(
                    authority.components(separatedBy: field).count - 1,
                    1,
                    field
                )
                let missingField = authority.replacingOccurrences(of: field, with: "")
                XCTAssertFalse(missingField.contains(authority), field)
                let duplicatedField = authority.replacingOccurrences(
                    of: field,
                    with: field + "\n" + field
                )
                XCTAssertFalse(duplicatedField.contains(authority), field)
            }
        }
        XCTAssertFalse(
            restoredCaptureBaselineSource.contains(workValidationExceptionID)
        )
        XCTAssertFalse(
            restoredCaptureBaselineSource.contains(workValidationExceptionRationale)
        )

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

        let reportsIndexNorthRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the Reports-index North Campus label whose frozen public frame intersects native bottom tab chrome even though ReportsRootView already renders it with primaryText; the audit-owned crop confirms the issue is limited to that chrome-overlapped composition, and the exception is limited to the frozen public issue signature."
        let reportsIndexVisitRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the Reports-index Visit label whose frozen public frame begins inside native bottom tab chrome, extends below the 402x874 application frame, and is not hittable even though ReportsRootView already renders it with primaryText; the audit-owned crop confirms the issue is limited to that chrome-clipped composition, and the exception is limited to the frozen public issue signature."

        let reportsIndexNorthUIAuthorityStart =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS","#
        let reportsIndexVisitUIAuthorityStart =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT","#
        let reportsIndexVisitUIAuthorityEnd =
            #"            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-FEEDBACK-PRIVACY","#
        guard let reportsIndexNorthUIStartRange = uiSource.range(
            of: reportsIndexNorthUIAuthorityStart
        ), let reportsIndexVisitUIStartRange = uiSource.range(
            of: reportsIndexVisitUIAuthorityStart,
            range: reportsIndexNorthUIStartRange.upperBound..<uiSource.endIndex
        ), let reportsIndexVisitUIEndRange = uiSource.range(
            of: reportsIndexVisitUIAuthorityEnd,
            range: reportsIndexVisitUIStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the exact Reports-index UI contrast authorities")
            return
        }
        let reportsIndexNorthUIAuthority = String(
            uiSource[
                reportsIndexNorthUIStartRange.lowerBound ..<
                    reportsIndexVisitUIStartRange.lowerBound
            ]
        )
        let reportsIndexVisitUIAuthority = String(
            uiSource[
                reportsIndexVisitUIStartRange.lowerBound ..<
                    reportsIndexVisitUIEndRange.lowerBound
            ]
        )
        let reportsIndexSignatureBlockStart =
            "        ContrastAuditExceptionSignature(\n" +
                reportsIndexNorthUIAuthorityStart
        let reportsIndexSignatureBlockEnd =
            "        ContrastAuditExceptionSignature(\n" +
                reportsIndexVisitUIAuthorityEnd
        guard let reportsIndexSignatureBlockStartRange = uiSource.range(
            of: reportsIndexSignatureBlockStart
        ), let reportsIndexSignatureBlockEndRange = uiSource.range(
            of: reportsIndexSignatureBlockEnd,
            range: reportsIndexSignatureBlockStartRange.upperBound..<uiSource.endIndex
        ) else {
            XCTFail("Missing the bounded Reports-index signature block")
            return
        }
        let reportsIndexSignatureBlock = String(
            uiSource[
                reportsIndexSignatureBlockStartRange.lowerBound ..<
                    reportsIndexSignatureBlockEndRange.lowerBound
            ]
        )
        XCTAssertEqual(reportsIndexSignatureBlock.utf8.count, 2_745)
        XCTAssertEqual(
            Data(reportsIndexSignatureBlock.utf8).sha256,
            "0E80FA4D20DF2B05E19AD8647B43420A11C79391B183D9790811705831996A01"
        )
        let reportsIndexNorthUILocks = [
            #"issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.reports-index.ready""#,
            #"taskID: "report_comprehension""#,
            #"owner: "palatis3""#,
            #"expiresAt: "2026-11-20""#,
            "rationale: \"" + reportsIndexNorthRationale + "\"",
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: """#,
            #"elementLabel: "North Campus""#,
            #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: CGRect(\n" +
                "                x: 32,\n" +
                "                y: 775.33333333333337,\n" +
                "                width: 329.33333333333331,\n" +
                "                height: 63.333333333333258\n" +
                "            )",
            "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
        ]
        let reportsIndexVisitUILocks = [
            #"issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.reports-index.ready""#,
            #"taskID: "report_comprehension""#,
            #"owner: "palatis3""#,
            #"expiresAt: "2026-11-20""#,
            "rationale: \"" + reportsIndexVisitRationale + "\"",
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: """#,
            #"elementLabel: "Visit""#,
            #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: CGRect(\n" +
                "                x: 32,\n" +
                "                y: 850.66666666666663,\n" +
                "                width: 85.333333333333329,\n" +
                "                height: 51.333333333333485\n" +
                "            )",
            "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
        ]
        for lock in reportsIndexNorthUILocks {
            XCTAssertEqual(
                reportsIndexNorthUIAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for lock in reportsIndexVisitUILocks {
            XCTAssertEqual(
                reportsIndexVisitUIAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let reportsIndexNorthWorkflowAuthorityStart =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.reports-index.ready","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS","#
        let reportsIndexVisitWorkflowAuthorityStart =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.reports-index.ready","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT","#
        let reportsIndexVisitWorkflowAuthorityEnd =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.check-preflight.ready","# + "\n" +
                #"                taskID: "one_handed_start","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION","#
        guard let reportsIndexNorthWorkflowStartRange = workflowSource.range(
            of: reportsIndexNorthWorkflowAuthorityStart
        ), let reportsIndexVisitWorkflowStartRange = workflowSource.range(
            of: reportsIndexVisitWorkflowAuthorityStart,
            range: reportsIndexNorthWorkflowStartRange.upperBound..<workflowSource.endIndex
        ), let reportsIndexVisitWorkflowEndRange = workflowSource.range(
            of: reportsIndexVisitWorkflowAuthorityEnd,
            range: reportsIndexVisitWorkflowStartRange.upperBound..<workflowSource.endIndex
        ) else {
            XCTFail("Missing the exact Reports-index workflow contrast authorities")
            return
        }
        let reportsIndexNorthWorkflowAuthority = String(
            workflowSource[
                reportsIndexNorthWorkflowStartRange.lowerBound ..<
                    reportsIndexVisitWorkflowStartRange.lowerBound
            ]
        )
        let reportsIndexVisitWorkflowAuthority = String(
            workflowSource[
                reportsIndexVisitWorkflowStartRange.lowerBound ..<
                    reportsIndexVisitWorkflowEndRange.lowerBound
            ]
        )
        let unitRangeOperator = "." + ".<"
        let correctedUnitRangeLocks = [
            "reportsIndexNorthUIStartRange.lowerBound " + unitRangeOperator + "\n" +
                "                    reportsIndexVisitUIStartRange.lowerBound",
            "reportsIndexVisitUIStartRange.lowerBound " + unitRangeOperator + "\n" +
                "                    reportsIndexVisitUIEndRange.lowerBound",
            "reportsIndexSignatureBlockStartRange.lowerBound " + unitRangeOperator + "\n" +
                "                    reportsIndexSignatureBlockEndRange.lowerBound",
            "reportsIndexNorthWorkflowStartRange.lowerBound " + unitRangeOperator + "\n" +
                "                    reportsIndexVisitWorkflowStartRange.lowerBound",
            "reportsIndexVisitWorkflowStartRange.lowerBound " + unitRangeOperator + "\n" +
                "                    reportsIndexVisitWorkflowEndRange.lowerBound",
        ]
        let staleUnitRangeLocks = [
            "reportsIndexNorthUIStartRange.lowerBound\n" +
                "                    " + unitRangeOperator +
                "reportsIndexVisitUIStartRange.lowerBound",
            "reportsIndexVisitUIStartRange.lowerBound\n" +
                "                    " + unitRangeOperator +
                "reportsIndexVisitUIEndRange.lowerBound",
            "reportsIndexSignatureBlockStartRange.lowerBound\n" +
                "                    " + unitRangeOperator +
                "reportsIndexSignatureBlockEndRange.lowerBound",
            "reportsIndexNorthWorkflowStartRange.lowerBound\n" +
                "                    " + unitRangeOperator +
                "reportsIndexVisitWorkflowStartRange.lowerBound",
            "reportsIndexVisitWorkflowStartRange.lowerBound\n" +
                "                    " + unitRangeOperator +
                "reportsIndexVisitWorkflowEndRange.lowerBound",
        ]
        for lock in correctedUnitRangeLocks {
            XCTAssertEqual(unitSource.components(separatedBy: lock).count - 1, 1, lock)
        }
        for staleLock in staleUnitRangeLocks {
            XCTAssertEqual(
                unitSource.components(separatedBy: staleLock).count - 1,
                0,
                staleLock
            )
        }
        let reportsIndexNorthWorkflowLocks = [
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.reports-index.ready""#,
            #"taskID: "report_comprehension""#,
            #"exceptionOwner: "palatis3""#,
            #"exceptionExpiresAt: "2026-11-20""#,
            "exceptionRationale: \"" + reportsIndexNorthRationale + "\"",
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: """#,
            #"elementLabel: "North Campus""#,
            #"elementType: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: {\n" +
                "                      x: 32,\n" +
                "                      y: 775.33333333333337,\n" +
                "                      width: 329.33333333333331,\n" +
                "                      height: 63.333333333333258\n" +
                "                    }",
            "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        let reportsIndexVisitWorkflowLocks = [
            #"exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT""#,
            #"shardID: "s10.4.current.ax-text""#,
            #"stateID: "state.reports-index.ready""#,
            #"taskID: "report_comprehension""#,
            #"exceptionOwner: "palatis3""#,
            #"exceptionExpiresAt: "2026-11-20""#,
            "exceptionRationale: \"" + reportsIndexVisitRationale + "\"",
            #"auditTypeRawValue: "1""#,
            #"compactDescription: "Contrast failed""#,
            #"detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode""#,
            #"elementIdentifier: """#,
            #"elementLabel: "Visit""#,
            #"elementType: "XCUIElementType(rawValue: 48)""#,
            "elementFrame: {\n" +
                "                      x: 32,\n" +
                "                      y: 850.66666666666663,\n" +
                "                      width: 85.333333333333329,\n" +
                "                      height: 51.333333333333485\n" +
                "                    }",
            "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
        ]
        for lock in reportsIndexNorthWorkflowLocks {
            XCTAssertEqual(
                reportsIndexNorthWorkflowAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for lock in reportsIndexVisitWorkflowLocks {
            XCTAssertEqual(
                reportsIndexVisitWorkflowAuthority.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }

        let reportsIndexNorthWorkflowTuple =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.reports-index.ready","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS""# + "\n" +
                "              },"
        let reportsIndexVisitWorkflowTuple =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.reports-index.ready","# + "\n" +
                #"                taskID: "report_comprehension","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT""# + "\n" +
                "              },"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reportsIndexNorthWorkflowTuple
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: reportsIndexVisitWorkflowTuple
            ).count - 1,
            1
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy:
                    reportsIndexNorthWorkflowTuple + "\n" +
                        reportsIndexVisitWorkflowTuple
            ).count - 1,
            1
        )

        for (source, authority, label) in [
            (uiSource, reportsIndexNorthUIAuthority, "North Campus UI authority"),
            (uiSource, reportsIndexVisitUIAuthority, "Visit UI authority"),
            (
                workflowSource,
                reportsIndexNorthWorkflowAuthority,
                "North Campus workflow authority"
            ),
            (
                workflowSource,
                reportsIndexVisitWorkflowAuthority,
                "Visit workflow authority"
            ),
        ] {
            XCTAssertEqual(
                source.components(separatedBy: authority).count - 1,
                1,
                label
            )
            let missing = source.replacingOccurrences(of: authority, with: "")
            XCTAssertEqual(
                missing.components(separatedBy: authority).count - 1,
                0,
                label
            )
            let duplicated = source.replacingOccurrences(
                of: authority,
                with: authority + authority
            )
            XCTAssertEqual(
                duplicated.components(separatedBy: authority).count - 1,
                2,
                label
            )
        }

        let reportsIndexNorthUIFieldMutations = [
            (
                "duplicate issue ID",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.reports-index.ready", "state.report-history.ready"),
            ("wrong task", "report_comprehension", "history_recovery"),
            ("wrong owner", #"owner: "palatis3""#, #"owner: "unknown""#),
            ("expired", #"expiresAt: "2026-11-20""#, #"expiresAt: "2026-08-21""#),
            (
                "wrong rationale",
                reportsIndexNorthRationale,
                "Incorrect reports-index exception rationale."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            ("wrong identifier", #"elementIdentifier: """#, #"elementIdentifier: "unexpected""#),
            ("wrong label", #"elementLabel: "North Campus""#, #"elementLabel: "South Campus""#),
            (
                "wrong type",
                #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
                #"elementTypeDescription: "XCUIElementType(rawValue: 49)""#
            ),
            ("wrong x", "                x: 32,", "                x: 31,"),
            (
                "wrong y",
                "                y: 775.33333333333337,",
                "                y: 775.33333333333338,"
            ),
            (
                "wrong width",
                "                width: 329.33333333333331,",
                "                width: 329.33333333333332,"
            ),
            (
                "wrong height",
                "                height: 63.333333333333258",
                "                height: 63.333333333333259"
            ),
            (
                "wrong app frame",
                "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
                "applicationFrame: CGRect(x: 0, y: 0, width: 401, height: 874)"
            ),
        ]
        let reportsIndexVisitUIFieldMutations = [
            (
                "duplicate issue ID",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.reports-index.ready", "state.report-history.ready"),
            ("wrong task", "report_comprehension", "history_recovery"),
            ("wrong owner", #"owner: "palatis3""#, #"owner: "unknown""#),
            ("expired", #"expiresAt: "2026-11-20""#, #"expiresAt: "2026-08-21""#),
            (
                "wrong rationale",
                reportsIndexVisitRationale,
                "Incorrect reports-index exception rationale."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            ("wrong identifier", #"elementIdentifier: """#, #"elementIdentifier: "unexpected""#),
            ("wrong label", #"elementLabel: "Visit""#, #"elementLabel: "Stage""#),
            (
                "wrong type",
                #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
                #"elementTypeDescription: "XCUIElementType(rawValue: 49)""#
            ),
            ("wrong x", "                x: 32,", "                x: 31,"),
            (
                "wrong y",
                "                y: 850.66666666666663,",
                "                y: 850.66666666666664,"
            ),
            (
                "wrong width",
                "                width: 85.333333333333329,",
                "                width: 85.333333333333330,"
            ),
            (
                "wrong height",
                "                height: 51.333333333333485",
                "                height: 51.333333333333486"
            ),
            (
                "wrong app frame",
                "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
                "applicationFrame: CGRect(x: 0, y: 0, width: 401, height: 874)"
            ),
        ]
        for (label, original, mutation) in reportsIndexNorthUIFieldMutations {
            XCTAssertTrue(reportsIndexNorthUIAuthority.contains(original), label)
            let mutatedAuthority = reportsIndexNorthUIAuthority.replacingOccurrences(
                of: original,
                with: mutation
            )
            XCTAssertNotEqual(
                mutatedAuthority,
                reportsIndexNorthUIAuthority,
                label
            )
            XCTAssertFalse(mutatedAuthority.contains(original), label)
        }
        for (label, original, mutation) in reportsIndexVisitUIFieldMutations {
            XCTAssertTrue(reportsIndexVisitUIAuthority.contains(original), label)
            let mutatedAuthority = reportsIndexVisitUIAuthority.replacingOccurrences(
                of: original,
                with: mutation
            )
            XCTAssertNotEqual(
                mutatedAuthority,
                reportsIndexVisitUIAuthority,
                label
            )
            XCTAssertFalse(mutatedAuthority.contains(original), label)
        }

        let reportsIndexNorthWorkflowFieldMutations = [
            (
                "duplicate issue ID",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.reports-index.ready", "state.report-history.ready"),
            ("wrong task", "report_comprehension", "history_recovery"),
            (
                "wrong owner",
                #"exceptionOwner: "palatis3""#,
                #"exceptionOwner: "unknown""#
            ),
            (
                "expired",
                #"exceptionExpiresAt: "2026-11-20""#,
                #"exceptionExpiresAt: "2026-08-21""#
            ),
            (
                "wrong rationale",
                reportsIndexNorthRationale,
                "Incorrect reports-index exception rationale."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            ("wrong identifier", #"elementIdentifier: """#, #"elementIdentifier: "unexpected""#),
            ("wrong label", #"elementLabel: "North Campus""#, #"elementLabel: "South Campus""#),
            (
                "wrong type",
                #"elementType: "XCUIElementType(rawValue: 48)""#,
                #"elementType: "XCUIElementType(rawValue: 49)""#
            ),
            ("wrong x", "                      x: 32,", "                      x: 31,"),
            (
                "wrong y",
                "                      y: 775.33333333333337,",
                "                      y: 775.33333333333338,"
            ),
            (
                "wrong width",
                "                      width: 329.33333333333331,",
                "                      width: 329.33333333333332,"
            ),
            (
                "wrong height",
                "                      height: 63.333333333333258",
                "                      height: 63.333333333333259"
            ),
            (
                "wrong app frame",
                "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
                "applicationFrame: {x: 0, y: 0, width: 401, height: 874}"
            ),
        ]
        let reportsIndexVisitWorkflowFieldMutations = [
            (
                "duplicate issue ID",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT",
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.reports-index.ready", "state.report-history.ready"),
            ("wrong task", "report_comprehension", "history_recovery"),
            (
                "wrong owner",
                #"exceptionOwner: "palatis3""#,
                #"exceptionOwner: "unknown""#
            ),
            (
                "expired",
                #"exceptionExpiresAt: "2026-11-20""#,
                #"exceptionExpiresAt: "2026-08-21""#
            ),
            (
                "wrong rationale",
                reportsIndexVisitRationale,
                "Incorrect reports-index exception rationale."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            ("wrong identifier", #"elementIdentifier: """#, #"elementIdentifier: "unexpected""#),
            ("wrong label", #"elementLabel: "Visit""#, #"elementLabel: "Stage""#),
            (
                "wrong type",
                #"elementType: "XCUIElementType(rawValue: 48)""#,
                #"elementType: "XCUIElementType(rawValue: 49)""#
            ),
            ("wrong x", "                      x: 32,", "                      x: 31,"),
            (
                "wrong y",
                "                      y: 850.66666666666663,",
                "                      y: 850.66666666666664,"
            ),
            (
                "wrong width",
                "                      width: 85.333333333333329,",
                "                      width: 85.333333333333330,"
            ),
            (
                "wrong height",
                "                      height: 51.333333333333485",
                "                      height: 51.333333333333486"
            ),
            (
                "wrong app frame",
                "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
                "applicationFrame: {x: 0, y: 0, width: 401, height: 874}"
            ),
        ]
        for (label, original, mutation) in reportsIndexNorthWorkflowFieldMutations {
            XCTAssertTrue(reportsIndexNorthWorkflowAuthority.contains(original), label)
            let mutatedAuthority = reportsIndexNorthWorkflowAuthority.replacingOccurrences(
                of: original,
                with: mutation
            )
            XCTAssertNotEqual(
                mutatedAuthority,
                reportsIndexNorthWorkflowAuthority,
                label
            )
            XCTAssertFalse(mutatedAuthority.contains(original), label)
        }
        for (label, original, mutation) in reportsIndexVisitWorkflowFieldMutations {
            XCTAssertTrue(reportsIndexVisitWorkflowAuthority.contains(original), label)
            let mutatedAuthority = reportsIndexVisitWorkflowAuthority.replacingOccurrences(
                of: original,
                with: mutation
            )
            XCTAssertNotEqual(
                mutatedAuthority,
                reportsIndexVisitWorkflowAuthority,
                label
            )
            XCTAssertFalse(mutatedAuthority.contains(original), label)
        }

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

        let issueRecheckDueExceptionID =
            "S10.4-XCUI-CONTRAST-FP-AX-TEXT-ISSUE-RECHECK-DUE-SECTION-APPEARS-DARK"
        let issueRecheckDueExceptionRationale =
            "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Section appears dark header whose frozen public frame intersects the native Recheck due navigation material in the AX-text issue-recheck-due state even though IssueDetailView renders it with primaryText; exact live geometry proves no rigid ScrollView shift can simultaneously place that header and the required Start recheck and saved-work composition clear of native top and bottom chrome, and the exception is limited to the frozen public issue signature."
        let issueRecheckDueUIAuthority =
            "        ContrastAuditExceptionSignature(\n" +
                "            issueID: \"\(issueRecheckDueExceptionID)\",\n" +
                #"            shardID: "s10.4.current.ax-text","# + "\n" +
                #"            stateID: "state.issue.recheck-due","# + "\n" +
                #"            taskID: "work_and_recheck","# + "\n" +
                #"            owner: "palatis3","# + "\n" +
                #"            expiresAt: "2026-11-20","# + "\n" +
                "            rationale: \"\(issueRecheckDueExceptionRationale)\",\n" +
                #"            auditTypeRawValue: "1","# + "\n" +
                #"            compactDescription: "Contrast failed","# + "\n" +
                #"            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","# + "\n" +
                #"            elementIdentifier: "s5.1.issue.header","# + "\n" +
                #"            elementLabel: "Section appears dark","# + "\n" +
                #"            elementTypeDescription: "XCUIElementType(rawValue: 48)","# + "\n" +
                "            elementFrame: CGRect(\n" +
                "                x: 32,\n" +
                "                y: 42.666666666666657,\n" +
                "                width: 330,\n" +
                "                height: 141.66666666666669\n" +
                "            ),\n" +
                "            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)\n" +
                "        ),"
        let issueRecheckDueWorkflowAuthority =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.issue.recheck-due","# + "\n" +
                #"                taskID: "work_and_recheck","# + "\n" +
                "                exceptionIssueID: \"\(issueRecheckDueExceptionID)\",\n" +
                #"                exceptionOwner: "palatis3","# + "\n" +
                #"                exceptionExpiresAt: "2026-11-20","# + "\n" +
                "                exceptionRationale: \"\(issueRecheckDueExceptionRationale)\",\n" +
                "                ignoredAuditIssues: [\n" +
                "                  {\n" +
                #"                    auditTypeRawValue: "1","# + "\n" +
                #"                    compactDescription: "Contrast failed","# + "\n" +
                #"                    detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode","# + "\n" +
                #"                    elementIdentifier: "s5.1.issue.header","# + "\n" +
                #"                    elementLabel: "Section appears dark","# + "\n" +
                #"                    elementType: "XCUIElementType(rawValue: 48)","# + "\n" +
                "                    elementFrame: {\n" +
                "                      x: 32,\n" +
                "                      y: 42.666666666666657,\n" +
                "                      width: 330,\n" +
                "                      height: 141.66666666666669\n" +
                "                    },\n" +
                "                    applicationFrame: {x: 0, y: 0, width: 402, height: 874}\n" +
                "                  }\n" +
                "                ]\n" +
                "              },"
        let issueRecheckDueWorkflowTuple =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.issue.recheck-due","# + "\n" +
                #"                taskID: "work_and_recheck","# + "\n" +
                "                exceptionIssueID: \"\(issueRecheckDueExceptionID)\"\n" +
                "              },"
        let issueRecheckDueWorkflowTupleOrder =
            "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.check-preflight.ready","# + "\n" +
                #"                taskID: "one_handed_start","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-BEFORE-YOU-BEGIN""# + "\n" +
                "              },\n" +
                "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.check-preflight.ready","# + "\n" +
                #"                taskID: "one_handed_start","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION""# + "\n" +
                "              },\n" +
                issueRecheckDueWorkflowTuple + "\n" +
                "              {\n" +
                #"                shardID: "s10.4.current.ax-text","# + "\n" +
                #"                stateID: "state.new-sign.editing","# + "\n" +
                #"                taskID: "one_handed_start","# + "\n" +
                #"                exceptionIssueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-CUSTOMER-SITE-NAME""# + "\n" +
                "              },"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: issueRecheckDueWorkflowTupleOrder
            ).count - 1,
            1
        )
        for (source, authority, label) in [
            (uiSource, issueRecheckDueUIAuthority, "issue-recheck UI authority"),
            (
                workflowSource,
                issueRecheckDueWorkflowAuthority,
                "issue-recheck workflow authority"
            ),
            (
                workflowSource,
                issueRecheckDueWorkflowTuple,
                "issue-recheck workflow tuple"
            ),
        ] {
            XCTAssertEqual(
                source.components(separatedBy: authority).count - 1,
                1,
                label
            )
            XCTAssertEqual(
                source.replacingOccurrences(of: authority, with: "")
                    .components(separatedBy: authority).count - 1,
                0,
                label
            )
            XCTAssertEqual(
                source.replacingOccurrences(
                    of: authority,
                    with: authority + authority
                ).components(separatedBy: authority).count - 1,
                2,
                label
            )
        }
        let issueRecheckDueUIFieldMutations = [
            (
                "duplicate issue ID",
                issueRecheckDueExceptionID,
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.issue.recheck-due", "state.issue.resolved"),
            ("wrong task", "work_and_recheck", "one_handed_start"),
            ("wrong owner", #"owner: "palatis3""#, #"owner: "unknown""#),
            ("expired", #"expiresAt: "2026-11-20""#, #"expiresAt: "2026-08-21""#),
            (
                "broad rationale",
                issueRecheckDueExceptionRationale,
                "Native navigation overlap."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            (
                "wrong identifier",
                #"elementIdentifier: "s5.1.issue.header""#,
                #"elementIdentifier: "s5.1.issue.status""#
            ),
            (
                "wrong label",
                #"elementLabel: "Section appears dark""#,
                #"elementLabel: "Recheck due""#
            ),
            (
                "wrong type",
                #"elementTypeDescription: "XCUIElementType(rawValue: 48)""#,
                #"elementTypeDescription: "XCUIElementType(rawValue: 49)""#
            ),
            ("wrong x", "                x: 32,", "                x: 33,"),
            (
                "wrong y",
                "                y: 42.666666666666657,",
                "                y: 42.666666666666658,"
            ),
            ("wrong width", "                width: 330,", "                width: 331,"),
            (
                "wrong height",
                "                height: 141.66666666666669",
                "                height: 141.6666666666667"
            ),
            (
                "wrong application frame",
                "applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)",
                "applicationFrame: CGRect(x: 0, y: 0, width: 401, height: 874)"
            ),
        ]
        let issueRecheckDueWorkflowFieldMutations = [
            (
                "duplicate issue ID",
                issueRecheckDueExceptionID,
                "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION"
            ),
            ("wrong shard", "s10.4.current.ax-text", "s10.4.current.default-light"),
            ("wrong state", "state.issue.recheck-due", "state.issue.resolved"),
            ("wrong task", "work_and_recheck", "one_handed_start"),
            (
                "wrong owner",
                #"exceptionOwner: "palatis3""#,
                #"exceptionOwner: "unknown""#
            ),
            (
                "expired",
                #"exceptionExpiresAt: "2026-11-20""#,
                #"exceptionExpiresAt: "2026-08-21""#
            ),
            (
                "broad rationale",
                issueRecheckDueExceptionRationale,
                "Native navigation overlap."
            ),
            ("wrong audit type", #"auditTypeRawValue: "1""#, #"auditTypeRawValue: "2""#),
            (
                "wrong compact",
                #"compactDescription: "Contrast failed""#,
                #"compactDescription: "Contrast passed""#
            ),
            (
                "wrong detailed",
                "Contrast failed for SwiftUI.AccessibilityNode",
                "Contrast failed for another node"
            ),
            (
                "wrong identifier",
                #"elementIdentifier: "s5.1.issue.header""#,
                #"elementIdentifier: "s5.1.issue.status""#
            ),
            (
                "wrong label",
                #"elementLabel: "Section appears dark""#,
                #"elementLabel: "Recheck due""#
            ),
            (
                "wrong type",
                #"elementType: "XCUIElementType(rawValue: 48)""#,
                #"elementType: "XCUIElementType(rawValue: 49)""#
            ),
            ("wrong x", "                      x: 32,", "                      x: 33,"),
            (
                "wrong y",
                "                      y: 42.666666666666657,",
                "                      y: 42.666666666666658,"
            ),
            ("wrong width", "                      width: 330,", "                      width: 331,"),
            (
                "wrong height",
                "                      height: 141.66666666666669",
                "                      height: 141.6666666666667"
            ),
            (
                "wrong application frame",
                "applicationFrame: {x: 0, y: 0, width: 402, height: 874}",
                "applicationFrame: {x: 0, y: 0, width: 401, height: 874}"
            ),
        ]
        for (label, from, to) in issueRecheckDueUIFieldMutations {
            let mutation = issueRecheckDueUIAuthority.replacingOccurrences(
                of: from,
                with: to
            )
            XCTAssertNotEqual(mutation, issueRecheckDueUIAuthority, label)
            XCTAssertEqual(
                uiSource.components(separatedBy: mutation).count - 1,
                0,
                label
            )
        }
        for (label, from, to) in issueRecheckDueWorkflowFieldMutations {
            let mutation = issueRecheckDueWorkflowAuthority.replacingOccurrences(
                of: from,
                with: to
            )
            XCTAssertNotEqual(mutation, issueRecheckDueWorkflowAuthority, label)
            XCTAssertEqual(
                workflowSource.components(separatedBy: mutation).count - 1,
                0,
                label
            )
        }

        let failClosedHandlerLocks = [
            "private var automationContrastExceptions: [String: [ContrastAuditExceptionSignature]] = [:]",
            "let eligibleExceptions = Self.contrastAuditExceptionSignatures.filter {",
            "let stateIssueLimit =",
            #"shard.shardID == "s10.4.current.ax-text""#,
            #"stateID == "state.check-preflight.ready""#,
            #"|| stateID == "state.reports-index.ready""#,
            #") ? 2 : 1"#,
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
        let exactContrastEligibilityFilter =
            "            let eligibleExceptions = " +
                "Self.contrastAuditExceptionSignatures.filter {\n" +
                "                $0.shardID == shard.shardID && $0.stateID == stateID\n" +
                "            }"
        XCTAssertEqual(
            restoredCaptureBaselineSource.components(
                separatedBy: exactContrastEligibilityFilter
            ).count - 1,
            1
        )
        for (label, mutation) in [
            (
                "broad shard-only exception filter",
                exactContrastEligibilityFilter.replacingOccurrences(
                    of: " && $0.stateID == stateID",
                    with: ""
                )
            ),
            (
                "broad state-only exception filter",
                exactContrastEligibilityFilter.replacingOccurrences(
                    of: "$0.shardID == shard.shardID && ",
                    with: ""
                )
            ),
        ] {
            XCTAssertNotEqual(mutation, exactContrastEligibilityFilter, label)
            let mutatedUI = uiSource.replacingOccurrences(
                of: exactContrastEligibilityFilter,
                with: mutation
            )
            XCTAssertEqual(
                mutatedUI.components(
                    separatedBy: exactContrastEligibilityFilter
                ).count - 1,
                0,
                label
            )
        }
        let exactAXTwoIssueStateLimit =
            "            let stateIssueLimit =\n" +
                #"                shard.shardID == "s10.4.current.ax-text""# + "\n" +
                "                && (\n" +
                #"                    stateID == "state.check-preflight.ready""# + "\n" +
                #"                        || stateID == "state.reports-index.ready""# + "\n" +
                "                ) ? 2 : 1"
        XCTAssertEqual(
            restoredCaptureBaselineSource.components(
                separatedBy: exactAXTwoIssueStateLimit
            ).count - 1,
            1
        )
        XCTAssertFalse(
            exactAXTwoIssueStateLimit.contains(
                #"stateID == "state.issue.recheck-due""#
            )
        )
        for (label, mutation) in [
            (
                "broadened AX state issue limit",
                exactAXTwoIssueStateLimit.replacingOccurrences(
                    of: #"shard.shardID == "s10.4.current.ax-text""#,
                    with: "true"
                )
            ),
            (
                "wrong AX state issue limit",
                exactAXTwoIssueStateLimit.replacingOccurrences(
                    of: ") ? 2 : 1",
                    with: ") ? 3 : 1"
                )
            ),
            (
                "missing Reports-index two-issue state",
                exactAXTwoIssueStateLimit.replacingOccurrences(
                    of: "\n" +
                        #"                        || stateID == "state.reports-index.ready""#,
                    with: ""
                )
            ),
        ] {
            XCTAssertNotEqual(mutation, exactAXTwoIssueStateLimit, label)
            let mutatedUI = uiSource.replacingOccurrences(
                of: exactAXTwoIssueStateLimit,
                with: mutation
            )
            XCTAssertEqual(
                mutatedUI.components(
                    separatedBy: exactAXTwoIssueStateLimit
                ).count - 1,
                0,
                label
            )
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
            #"taskIssueLimit = 3"#,
            #"taskStateLimit = 2"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.report-history.ready","# + "\n" +
                #"                    "state.reports-index.ready","# + "\n" +
                #"                ]"#,
            #"case ("s10.4.current.ax-text", "work_and_recheck")"#,
            #"permittedExceptionStateIDs = ["# + "\n" +
                #"                    "state.issue.recheck-due","# + "\n" +
                #"                    "state.work.validation-error","# + "\n" +
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
            3
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
        let axReportComprehensionTaskExceptionBound =
            #"            case ("s10.4.current.ax-text", "report_comprehension"):"# +
                "\n" +
                "                taskIssueLimit = 3\n" +
                "                taskStateLimit = 2\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.report-history.ready","# +
                "\n" +
                #"                    "state.reports-index.ready","# +
                "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: axReportComprehensionTaskExceptionBound
            ).count - 1,
            1
        )
        for (label, mutation) in [
            (
                "AX report task issue expansion",
                axReportComprehensionTaskExceptionBound.replacingOccurrences(
                    of: "taskIssueLimit = 3",
                    with: "taskIssueLimit = 4"
                )
            ),
            (
                "AX report task state expansion",
                axReportComprehensionTaskExceptionBound.replacingOccurrences(
                    of: "taskStateLimit = 2",
                    with: "taskStateLimit = 3"
                )
            ),
            (
                "AX report task missing Reports-index state",
                axReportComprehensionTaskExceptionBound.replacingOccurrences(
                    of: #"                    "state.reports-index.ready","# + "\n",
                    with: ""
                )
            ),
        ] {
            XCTAssertNotEqual(mutation, axReportComprehensionTaskExceptionBound, label)
            let mutatedUI = uiSource.replacingOccurrences(
                of: axReportComprehensionTaskExceptionBound,
                with: mutation
            )
            XCTAssertEqual(
                mutatedUI.components(
                    separatedBy: axReportComprehensionTaskExceptionBound
                ).count - 1,
                0,
                label
            )
        }
        let axWorkAndRecheckTaskExceptionBound =
            #"            case ("s10.4.current.ax-text", "work_and_recheck"):"# +
                "\n" +
                "                taskIssueLimit = 2\n" +
                "                taskStateLimit = 2\n" +
                "                permittedExceptionStateIDs = [\n" +
                #"                    "state.issue.recheck-due","# + "\n" +
                #"                    "state.work.validation-error","# + "\n" +
                "                ]"
        XCTAssertEqual(
            uiSource.components(
                separatedBy: axWorkAndRecheckTaskExceptionBound
            ).count - 1,
            1
        )
        let staleAXWorkAndRecheckTaskExceptionBound =
            #"            case ("s10.4.current.ax-text", "work_and_recheck"):"# +
                "\n" +
                "                taskIssueLimit = 1\n" +
                "                taskStateLimit = 1\n" +
                #"                permittedExceptionStateIDs = ["state.work.validation-error"]"#
        XCTAssertEqual(
            uiSource.components(
                separatedBy: staleAXWorkAndRecheckTaskExceptionBound
            ).count - 1,
            0
        )
        for (label, mutation) in [
            (
                "AX work task issue contraction",
                axWorkAndRecheckTaskExceptionBound.replacingOccurrences(
                    of: "taskIssueLimit = 2",
                    with: "taskIssueLimit = 1"
                )
            ),
            (
                "AX work task state contraction",
                axWorkAndRecheckTaskExceptionBound.replacingOccurrences(
                    of: "taskStateLimit = 2",
                    with: "taskStateLimit = 1"
                )
            ),
            (
                "AX work task extra state",
                axWorkAndRecheckTaskExceptionBound.replacingOccurrences(
                    of: #"                    "state.issue.recheck-due","#,
                    with:
                        #"                    "state.issue.recheck-due","# + "\n" +
                        #"                    "state.work.editing","#
                )
            ),
            (
                "AX work task missing issue-recheck state",
                axWorkAndRecheckTaskExceptionBound.replacingOccurrences(
                    of: #"                    "state.issue.recheck-due","# + "\n",
                    with: ""
                )
            ),
            (
                "AX work task missing validation state",
                axWorkAndRecheckTaskExceptionBound.replacingOccurrences(
                    of: #"                    "state.work.validation-error","# + "\n",
                    with: ""
                )
            ),
        ] {
            XCTAssertNotEqual(mutation, axWorkAndRecheckTaskExceptionBound, label)
            let mutatedUI = uiSource.replacingOccurrences(
                of: axWorkAndRecheckTaskExceptionBound,
                with: mutation
            )
            XCTAssertEqual(
                mutatedUI.components(
                    separatedBy: axWorkAndRecheckTaskExceptionBound
                ).count - 1,
                0,
                label
            )
        }
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
            #"length == 16"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 14"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 16"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 11"#,
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
            #"| (.ignoredAuditIssues[0] | tojson)] | unique | length) == 10"#,
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
                #"                     and $taskID == "report_comprehension" then 3"#,
            #"and $taskID == "work_and_recheck" then 2"#,
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
            #"($matchedAuthorities | length) > 8"#,
            #"($matchedExceptionStateIDs | length) > 6"#,
            #"stateIssueLimit($shardID; $stateID)"#,
            #"and $stateID == "state.check-preflight.ready" then 2"#,
            #"and $stateID == "state.new-sign.editing" then 1"#,
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $stateID == "state.report-history.ready" then 1"#,
            #"and $stateID == "state.reports-index.ready" then 2"#,
            #"and $stateID == "state.work.validation-error" then 1"#,
            #"and $stateID == "state.issue.recheck-due" then 1"#,
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
        let exactWorkflowAuthorityFilter =
            "                ($authorities\n" +
                "                  | map(select(\n" +
                "                      .shardID == $row.shardID\n" +
                "                      and .stateID == $row.stateID\n" +
                "                    ))) as $eligible"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: exactWorkflowAuthorityFilter
            ).count - 1,
            2
        )
        for (label, mutation) in [
            (
                "broad workflow shard-only authority filter",
                exactWorkflowAuthorityFilter.replacingOccurrences(
                    of: "\n                      and .stateID == $row.stateID",
                    with: ""
                )
            ),
            (
                "broad workflow state-only authority filter",
                exactWorkflowAuthorityFilter.replacingOccurrences(
                    of: ".shardID == $row.shardID\n                      and ",
                    with: ""
                )
            ),
        ] {
            XCTAssertNotEqual(mutation, exactWorkflowAuthorityFilter, label)
            let mutatedWorkflow = workflowSource.replacingOccurrences(
                of: exactWorkflowAuthorityFilter,
                with: mutation
            )
            XCTAssertEqual(
                mutatedWorkflow.components(
                    separatedBy: exactWorkflowAuthorityFilter
                ).count - 1,
                0,
                label
            )
        }
        let workflowAuthorityCardinality =
            "            length == 16\n" +
                "            and ([.[] | [.shardID, .stateID] | join(\"|\")] | unique | length) == 14\n" +
                "            and ([.[].exceptionIssueID] | unique | length) == 16\n" +
                "            and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 11"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: workflowAuthorityCardinality
            ).count - 1,
            1
        )
        for (label, mutation) in [
            (
                "authority count contraction",
                workflowAuthorityCardinality.replacingOccurrences(
                    of: "length == 16",
                    with: "length == 15"
                )
            ),
            (
                "authority pair contraction",
                workflowAuthorityCardinality.replacingOccurrences(
                    of: "unique | length) == 14",
                    with: "unique | length) == 13"
                )
            ),
            (
                "authority issue contraction",
                workflowAuthorityCardinality.replacingOccurrences(
                    of: "exceptionIssueID] | unique | length) == 16",
                    with: "exceptionIssueID] | unique | length) == 15"
                )
            ),
            (
                "authority signature contraction",
                workflowAuthorityCardinality.replacingOccurrences(
                    of: "tojson)] | unique | length) == 11",
                    with: "tojson)] | unique | length) == 10"
                )
            ),
        ] {
            XCTAssertNotEqual(mutation, workflowAuthorityCardinality, label)
            let mutatedWorkflow = workflowSource.replacingOccurrences(
                of: workflowAuthorityCardinality,
                with: mutation
            )
            XCTAssertEqual(
                mutatedWorkflow.components(
                    separatedBy: workflowAuthorityCardinality
                ).count - 1,
                0,
                label
            )
        }
        let staleWorkflowAuthorityCardinality =
            "            length == 12\n" +
                "            and ([.[] | [.shardID, .stateID] | join(\"|\")] | unique | length) == 11\n" +
                "            and ([.[].exceptionIssueID] | unique | length) == 12\n" +
                "            and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 7"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: staleWorkflowAuthorityCardinality
            ).count - 1,
            0
        )
        let staleI235WorkflowAuthorityCardinality =
            "            length == 14\n" +
                "            and ([.[] | [.shardID, .stateID] | join(\"|\")] | unique | length) == 12\n" +
                "            and ([.[].exceptionIssueID] | unique | length) == 14\n" +
                "            and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 9"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: staleI235WorkflowAuthorityCardinality
            ).count - 1,
            0
        )
        let workflowHeaderSharedOneAndNonHeaderTen =
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
                "              | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 10"
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: workflowHeaderSharedOneAndNonHeaderTen
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
                #"                     and (($matchedAuthorities | length) > 8"# + "\n" +
                #"                       or ($matchedExceptionStateIDs | length) > 6) then"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowAggregateBound).count - 1,
            1
        )
        let axWorkflowTaskIssueBound =
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 3"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowTaskIssueBound).count - 1,
            1
        )
        let axWorkflowTaskIssueFunctionBound =
                #"              def taskIssueLimit($shardID; $taskID):"# + "\n" +
                #"                if $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                   and $taskID == "one_handed_start" then 3"# + "\n" +
                #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "report_comprehension" then 3"# + "\n" +
                #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "work_and_recheck" then 2"#
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
                #"                     and $taskID == "report_comprehension" then 2"# + "\n" +
                #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $taskID == "work_and_recheck" then 2"#
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
        let axWorkflowReportsIndexStateIssueBound =
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $stateID == "state.reports-index.ready" then 2"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: axWorkflowReportsIndexStateIssueBound
            ).count - 1,
            1
        )
        let axWorkflowWorkValidationStateIssueBound =
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $stateID == "state.work.validation-error" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: axWorkflowWorkValidationStateIssueBound
            ).count - 1,
            1
        )
        let axWorkflowIssueRecheckDueStateIssueBound =
            #"                elif $shardID == "s10.4.current.ax-text""# + "\n" +
                #"                     and $stateID == "state.issue.recheck-due" then 1"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: axWorkflowIssueRecheckDueStateIssueBound
            ).count - 1,
            1
        )
        let axWorkflowGroupedStateIssueBound =
            #"                     if $shard == "s10.4.current.ax-text""# + "\n" +
                #"                        and (.[0].stateID == "state.check-preflight.ready""# + "\n" +
                #"                          or .[0].stateID == "state.reports-index.ready") then 2"#
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: axWorkflowGroupedStateIssueBound
            ).count - 1,
            1
        )
        let axWorkflowDownstreamBound =
            #"                      elif $shard == "s10.4.current.ax-text" then"# + "\n" +
                #"                        ($matchedAuthorities | length) <= 8"# + "\n" +
                #"                        and ($matchedExceptionStateIDs | length) <= 6"#
        XCTAssertEqual(
            workflowSource.components(separatedBy: axWorkflowDownstreamBound).count - 1,
            1
        )
        let axWorkflowLimitMutations = [
            (
                "AX task issue limit expansion",
                axWorkflowTaskIssueFunctionBound,
                axWorkflowTaskIssueFunctionBound.replacingOccurrences(
                    of: #"and $taskID == "report_comprehension" then 3"#,
                    with: #"and $taskID == "report_comprehension" then 4"#
                )
            ),
            (
                "AX task state limit expansion",
                axWorkflowTaskStateFunctionBound,
                axWorkflowTaskStateFunctionBound.replacingOccurrences(
                    of: #"and $taskID == "report_comprehension" then 2"#,
                    with: #"and $taskID == "report_comprehension" then 3"#
                )
            ),
            (
                "AX work task issue limit contraction",
                axWorkflowTaskIssueFunctionBound,
                axWorkflowTaskIssueFunctionBound.replacingOccurrences(
                    of: #"and $taskID == "work_and_recheck" then 2"#,
                    with: #"and $taskID == "work_and_recheck" then 1"#
                )
            ),
            (
                "AX work task state limit contraction",
                axWorkflowTaskStateFunctionBound,
                axWorkflowTaskStateFunctionBound.replacingOccurrences(
                    of: #"and $taskID == "work_and_recheck" then 2"#,
                    with: #"and $taskID == "work_and_recheck" then 1"#
                )
            ),
            (
                "AX issue-recheck state issue limit expansion",
                axWorkflowIssueRecheckDueStateIssueBound,
                axWorkflowIssueRecheckDueStateIssueBound.replacingOccurrences(
                    of: "then 1",
                    with: "then 2"
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
                "AX Reports-index state issue limit expansion",
                axWorkflowReportsIndexStateIssueBound,
                axWorkflowReportsIndexStateIssueBound.replacingOccurrences(
                    of: "then 2",
                    with: "then 3"
                )
            ),
            (
                "AX work-validation state issue limit expansion",
                axWorkflowWorkValidationStateIssueBound,
                axWorkflowWorkValidationStateIssueBound.replacingOccurrences(
                    of: "then 1",
                    with: "then 2"
                )
            ),
            (
                "AX work-validation extra state",
                axWorkflowWorkValidationStateIssueBound,
                axWorkflowWorkValidationStateIssueBound.replacingOccurrences(
                    of: #"$stateID == "state.work.validation-error""#,
                    with:
                        #"($stateID == "state.work.editing" or $stateID == "state.work.validation-error")"#
                )
            ),
            (
                "AX grouped Reports-index state limit removal",
                axWorkflowGroupedStateIssueBound,
                axWorkflowGroupedStateIssueBound.replacingOccurrences(
                    of: "\n" +
                        #"                          or .[0].stateID == "state.reports-index.ready""#,
                    with: ""
                )
            ),
            (
                "AX aggregate limit expansion",
                axWorkflowAggregateBound,
                axWorkflowAggregateBound
                    .replacingOccurrences(of: "> 8", with: "> 9")
                    .replacingOccurrences(of: "> 6", with: "> 7")
            ),
            (
                "AX downstream limit expansion",
                axWorkflowDownstreamBound,
                axWorkflowDownstreamBound
                    .replacingOccurrences(of: "<= 8", with: "<= 9")
                    .replacingOccurrences(of: "<= 6", with: "<= 7")
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
            "            length == 15\n" +
                "            and ([.[] | [.shardID, .stateID] | join(\"|\")] | unique | length) == 13\n" +
                "            and ([.[].exceptionIssueID] | unique | length) == 15\n" +
                "            and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 10",
            #"length == 7"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 6"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 7"#,
            #"and ([.[] | [.shardID, .stateID] | join("|")] | unique | length) == 4"#,
            #"and ([.[].exceptionIssueID] | unique | length) == 5"#,
            #"and ([.[] | (.ignoredAuditIssues[0] | tojson)] | unique | length) == 5"#,
            #"($matchedAuthorities | length) > 2"#,
            #"($matchedAuthorities | length) > 6"#,
            #"($matchedAuthorities | length) > 7"#,
            #"($matchedExceptionStateIDs | length) > 5"#,
            #"($matchedExceptionStateIDs | length) > 4"#,
            #"($matchedAuthorities | length) <= 6"#,
            #"($matchedAuthorities | length) <= 7"#,
            #"($matchedExceptionStateIDs | length) <= 5"#,
            #"and $taskID == "work_and_recheck" then 1"#,
            #"and $stateID == "state.issue.recheck-due" then 2"#,
            #"($matchedExceptionStateIDs | length) <= 4"#,
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
            20
        )
        XCTAssertEqual(
            workflowSource.components(
                separatedBy: #"taskID: "work_and_recheck""#
            ).count - 1,
            4
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

    func testMinimumOSCameraDeniedLegacyTabCorrectionIsNarrowAndDiagnosticFree() throws {
        let captureSource = try text(
            "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift"
        )
        let uiSource = try text(
            "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift"
        )

        func boundedSource(
            _ source: String,
            from start: String,
            before end: String,
            label: String
        ) throws -> String {
            let startRange = try XCTUnwrap(
                source.range(of: start),
                "Missing \(label) start"
            )
            let endRange = try XCTUnwrap(
                source.range(
                    of: end,
                    range: startRange.upperBound..<source.endIndex
                ),
                "Missing \(label) end"
            )
            return String(source[startRange.lowerBound..<endRange.lowerBound])
        }

        func assertOrdered(
            _ fragments: [String],
            in source: String,
            label: String
        ) throws {
            var searchStart = source.startIndex
            for fragment in fragments {
                let range = try XCTUnwrap(
                    source.range(
                        of: fragment,
                        range: searchStart..<source.endIndex
                    ),
                    "Missing ordered \(label): \(fragment)"
                )
                searchStart = range.upperBound
            }
        }

        let rootBodySource = try boundedSource(
            captureSource,
            from: "    var body: some View {",
            before: "    private var captureScroll: some View {",
            label: "CaptureStep root body"
        )
        let captureRouteSource = try boundedSource(
            captureSource,
            from: "    private var captureScroll: some View {",
            before: "\n\nprivate struct CaptureTabBarVisibility: ViewModifier {",
            label: "CaptureStep route"
        )
        let modifierStart = try XCTUnwrap(
            captureSource.range(
                of: "private struct CaptureTabBarVisibility: ViewModifier {"
            )
        )
        let modifierSource = String(captureSource[modifierStart.lowerBound...])

        let legacyPredicate = "usesImportedCaptureFixturesForUITest"
        let rootModifierCall =
            "        .modifier(\n" +
                "            CaptureTabBarVisibility(\n" +
                "                hidesOnLegacyOS: " + legacyPredicate + "\n" +
                "            )\n" +
                "        )"
        let rootModifierAdjacency =
            "            } else {\n" +
                "                captureScroll\n" +
                "            }\n" +
                "        }\n" +
                rootModifierCall + "\n" +
                "        .navigationBarTitleDisplayMode(.inline)"
        XCTAssertEqual(
            rootBodySource.components(
                separatedBy: rootModifierAdjacency
            ).count - 1,
            1
        )
        XCTAssertEqual(
            captureSource.components(
                separatedBy: rootModifierCall
            ).count - 1,
            1
        )
        XCTAssertFalse(
            captureRouteSource.contains("CaptureTabBarVisibility"),
            "The modifier must remain on the active-check root."
        )

        let exactModifier =
            "private struct CaptureTabBarVisibility: ViewModifier {\n" +
                "    let hidesOnLegacyOS: Bool\n\n" +
                "    @ViewBuilder\n" +
                "    func body(content: Content) -> some View {\n" +
                "        if #available(iOS 26.0, *) {\n" +
                "            content.toolbar(.hidden, for: .tabBar)\n" +
                "        } else if hidesOnLegacyOS {\n" +
                "            content.toolbar(.hidden, for: .tabBar)\n" +
                "        } else {\n" +
                "            content\n" +
                "        }\n" +
                "    }\n" +
                "}\n"
        XCTAssertEqual(modifierSource, exactModifier)
        XCTAssertEqual(
            captureSource.components(
                separatedBy: "CaptureTabBarVisibility"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            captureSource.components(
                separatedBy: "hidesOnLegacyOS"
            ).count - 1,
            3
        )
        XCTAssertEqual(
            modifierSource.components(
                separatedBy: "content.toolbar(.hidden, for: .tabBar)"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            modifierSource.components(
                separatedBy: "if #available(iOS 26.0, *)"
            ).count - 1,
            1
        )
        XCTAssertFalse(rootBodySource.contains(".toolbar(.hidden, for: .tabBar)"))

        let legacyTruthTable: [
            (usesFixtures: Bool, status: CameraAuthorizationStatus?, hides: Bool)
        ] = [
            (false, nil, false),
            (false, .notDetermined, false),
            (false, .authorized, false),
            (false, .denied, false),
            (false, .restricted, false),
            (true, nil, true),
            (true, .notDetermined, true),
            (true, .authorized, true),
            (true, .denied, true),
            (true, .restricted, true),
        ]
        for row in legacyTruthTable {
            let hidesOnLegacyOS = row.usesFixtures
            XCTAssertEqual(hidesOnLegacyOS, row.hides)
        }

        let unconditionalLegacyModifier =
            "private struct CaptureTabBarVisibility: ViewModifier {\n" +
                "    let hidesOnLegacyOS: Bool\n\n" +
                "    @ViewBuilder\n" +
                "    func body(content: Content) -> some View {\n" +
                "        if #available(iOS 26.0, *) {\n" +
                "            content.toolbar(.hidden, for: .tabBar)\n" +
                "        } else {\n" +
                "            content.toolbar(.hidden, for: .tabBar)\n" +
                "        }\n" +
                "    }\n" +
                "}\n"
        let productMutations: [(String, String, String)] = [
            (
                "all iOS 18 sessions hidden",
                exactModifier,
                exactModifier.replacingOccurrences(
                    of: "iOS 26.0",
                    with: "iOS 18.0"
                )
            ),
            (
                "unconditional legacy hiding",
                exactModifier,
                unconditionalLegacyModifier
            ),
            (
                "constant true legacy hiding",
                rootModifierCall,
                rootModifierCall.replacingOccurrences(
                    of: legacyPredicate,
                    with: "true"
                )
            ),
            (
                "constant false legacy hiding",
                rootModifierCall,
                rootModifierCall.replacingOccurrences(
                    of: legacyPredicate,
                    with: "false"
                )
            ),
            (
                "stale fixture-and-status gate",
                rootModifierCall,
                rootModifierCall.replacingOccurrences(
                    of: legacyPredicate,
                    with:
                        "usesImportedCaptureFixturesForUITest\n" +
                        "                    && " +
                        "(cameraStatus == .denied || cameraStatus == .restricted)"
                )
            ),
            (
                "status-only legacy hiding",
                rootModifierCall,
                rootModifierCall.replacingOccurrences(
                    of: legacyPredicate,
                    with: "(cameraStatus == .denied || cameraStatus == .restricted)"
                )
            ),
            (
                "disjunctive fixture gate",
                rootModifierCall,
                rootModifierCall.replacingOccurrences(
                    of: legacyPredicate,
                    with:
                        "usesImportedCaptureFixturesForUITest\n" +
                        "                    || " +
                        "(cameraStatus == .denied || cameraStatus == .restricted)"
                )
            ),
            (
                "inverted fixture gate",
                rootModifierCall,
                rootModifierCall.replacingOccurrences(
                    of: "usesImportedCaptureFixturesForUITest",
                    with: "!usesImportedCaptureFixturesForUITest"
                )
            ),
        ]
        for (label, canonical, mutation) in productMutations {
            XCTAssertTrue(captureSource.contains(canonical), label)
            XCTAssertNotEqual(canonical, mutation, label)
            XCTAssertFalse(captureSource.contains(mutation), label)
        }

        let nonthrowingCallChainLocks = [
            "        completeVisibleIssueCheck(in: app)",
            "    private func completeVisibleIssueCheck(in app: XCUIApplication) {",
            "        recoverCameraDenialAndResume(in: app)",
            "    private func recoverCameraDenialAndResume(in app: XCUIApplication) {",
        ]
        for lock in nonthrowingCallChainLocks {
            XCTAssertEqual(
                uiSource.components(separatedBy: lock).count - 1,
                1,
                lock
            )
        }
        for throwingForm in [
            "        try completeVisibleIssueCheck(in: app)",
            "        try? completeVisibleIssueCheck(in: app)",
            "        try! completeVisibleIssueCheck(in: app)",
            "    private func completeVisibleIssueCheck(in app: XCUIApplication) throws {",
            "        try recoverCameraDenialAndResume(in: app)",
            "        try? recoverCameraDenialAndResume(in: app)",
            "        try! recoverCameraDenialAndResume(in: app)",
            "    private func recoverCameraDenialAndResume(in app: XCUIApplication) throws {",
        ] {
            XCTAssertEqual(
                uiSource.components(separatedBy: throwingForm).count - 1,
                0,
                throwingForm
            )
        }

        let exactTopRouteCallChain =
            "        assertLightFirstSignValidationAndCreation(in: app)\n" +
                "        completeVisibleIssueCheck(in: app)\n" +
                "        assertFirstReceiptAndReport(in: app)"
        let exactCaptureRouteCallChain =
            "        captureBaseline(\"state.capture.wide-ready\", in: app)\n" +
                "        recoverCameraDenialAndResume(in: app)\n\n" +
                "        acceptImportedPhoto("
        XCTAssertEqual(
            uiSource.components(
                separatedBy: exactTopRouteCallChain
            ).count - 1,
            1
        )
        XCTAssertEqual(
            uiSource.components(
                separatedBy: exactCaptureRouteCallChain
            ).count - 1,
            1
        )

        let cameraRecoveryStart =
            "    @MainActor\n" +
                "    private func recoverCameraDenialAndResume(in app: XCUIApplication) {"
        let cameraRecoveryEnd =
            "\n\n    @MainActor\n" +
                "    private func recoverInjectedPDFFailureAtXXXL(in app: XCUIApplication) {"
        let cameraRecoverySource = try boundedSource(
            uiSource,
            from: cameraRecoveryStart,
            before: cameraRecoveryEnd,
            label: "camera-denied recovery"
        )
        let denialInstructionAndBaseline =
            "        assertUnidentifiedLocalizedLabel(\n" +
                "            \"Choose a photo, open Settings, or leave this check incomplete and return later.\",\n" +
                "            in: app\n" +
                "        )\n" +
                "        captureBaseline(\"state.capture.camera-denied\", in: app)"
        XCTAssertEqual(
            cameraRecoverySource.components(
                separatedBy: denialInstructionAndBaseline
            ).count - 1,
            1
        )
        XCTAssertEqual(
            cameraRecoverySource.components(
                separatedBy: "captureBaseline(\"state.capture.camera-denied\", in: app)"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            cameraRecoverySource.components(
                separatedBy: "automationShard?"
            ).count - 1,
            0
        )
        try assertOrdered(
            [
                "        let takePhoto = element(\"s3.capture.take-photo\", in: app)",
                "        scroll(takePhoto, in: app)",
                "        assertControl(takePhoto, label: \"Take photo\")",
                "        takePhoto.tap()",
                "        let settings = element(\"s3.capture.open-settings\", in: app)",
                "        XCTAssertTrue(settings.waitForExistence(timeout: 15))",
                "        assertLocalizedLabel(settings, equals: \"Open Settings\")",
                denialInstructionAndBaseline,
                "        let cannotComplete = element(\"s3.capture.cannot-complete\", in: app)",
                "        scroll(cannotComplete, in: app)",
                "        assertControl(cannotComplete, label: \"Cannot complete\")",
                "        cannotComplete.tap()",
                "        XCTAssertTrue(element(\"s3.outcome.screen\", in: app)",
                "        let couldNotVerify = element(\"s3.outcome.could-not-verify\", in: app)",
                "        assertLocalizedValue(couldNotVerify, equals: \"Selected\")",
                "        app.terminate()",
                "        app.launch()",
                "        XCTAssertTrue(element(\"s3.capture.screen\", in: app)",
                "        let heading = element(\"s3.capture.heading\", in: app)",
                "            equals: \"1 of 2 · Wide view\",",
            ],
            in: cameraRecoverySource,
            label: "unchanged camera-denied route"
        )

        let removedDiagnosticGate =
            "        if automationShard?.shardID == \"s10.4.minimum.minimum-os\",\n" +
                "           automationShard?.deviceProfileID == \"iphone-se-3-ios-18.0-minimum\" {\n" +
                "            try diagnoseMinimumOSCameraDeniedContrast(in: app)\n" +
                "        }"
        let removedI247DiagnosticForms = [
            "diagnoseMinimumOSCameraDeniedContrast",
            "S10_4_MINIMUM_CAMERA_DENIED_",
            "let shard = automationShard!",
            "firstAuditedElementScreenshot",
            "performAccessibilityAudit(for: .contrast) { [self] issue in",
            "captureRouteAttachment",
            "S10.4 minimum-OS camera-denied contrast diagnostic",
            "Capture-route element was absent during the minimum-OS camera-denied contrast diagnostic.",
            "No audited element screenshot was available during the minimum-OS camera-denied contrast diagnostic.",
            "S10.4 minimum-OS camera-denied contrast diagnostic completed nonaccepting",
            removedDiagnosticGate,
        ]
        for removedForm in removedI247DiagnosticForms {
            XCTAssertEqual(
                uiSource.components(separatedBy: removedForm).count - 1,
                0,
                removedForm
            )
        }

        let reversedDeniedOrder =
            "        captureBaseline(\"state.capture.camera-denied\", in: app)\n" +
                "        assertUnidentifiedLocalizedLabel("
        XCTAssertFalse(
            cameraRecoverySource.contains(reversedDeniedOrder),
            "The strict baseline must remain immediately after the denial instruction."
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
