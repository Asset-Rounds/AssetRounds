import CryptoKit
import Foundation
import XCTest

final class S10_3BrandMigrationTests: XCTestCase {
    private let productionPaths = [
        "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
        "FieldEvidenceApp/App/LaunchView.swift",
        "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
        "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
        "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
        "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
        "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
        "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
        "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
        "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
        "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
        "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
        "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
        "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
        "FieldEvidenceApp/Features/Sample/PackSampleView.swift",
        "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
        "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
        "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
        "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
        "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
        "FieldEvidenceApp/Features/Signs/NewSignView.swift",
        "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
        "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
        "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
        "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
    ]

    private let expectedComponentTypes = [
        "AssetRoundsScreenFoundation",
        "AssetRoundsPrimaryAction",
        "AssetRoundsSecondaryAction",
        "AssetRoundsDestructiveAction",
        "AssetRoundsEvidenceCard",
        "AssetRoundsPhotoCapture",
        "AssetRoundsStateLabel",
        "AssetRoundsEmptyState",
        "AssetRoundsReportBrandHeader",
    ]

    func testExactFrozenInventoryMapsAllSixtySevenStatesToTheMigrationEnvelope() throws {
        let activation = try json("docs/design/s10/s10-activation.json")
        let card = try XCTUnwrap(
            try rows(activation, "cards").first {
                ($0["card_id"] as? String) == "S10.3"
            }
        )
        XCTAssertEqual(card["product_file_cap"] as? Int, 26)
        XCTAssertEqual(card["test_file_cap"] as? Int, 2)
        XCTAssertEqual(
            try strings(card, "allowed_paths"),
            productionPaths + [
                "FieldEvidenceAppTests/S10_3BrandMigrationTests.swift",
                "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift",
            ]
        )

        let inventory = try json("docs/design/s10/s10-screen-state-inventory.json")
        XCTAssertEqual(
            try strings(inventory, "migration_order"),
            [
                "migration.signs",
                "migration.check",
                "migration.reports",
                "migration.work-recheck",
                "migration.settings-data-rights",
                "migration.commerce",
            ]
        )
        let routes = try rows(inventory, "routes")
        let states = try routes.flatMap { try rows($0, "states") }
        let stateIDs = try states.map { try string($0, "state_id") }
        let migrationOrder = try strings(inventory, "migration_order")
        XCTAssertEqual(stateIDs.count, 67)
        XCTAssertEqual(Set(stateIDs).count, 67)

        let authorized = Set(productionPaths)
        for route in routes {
            let routeID = try string(route, "route_id")
            let slice = try string(route, "migration_slice_id")
            XCTAssertTrue(migrationOrder.contains(slice))
            let sources = try strings(route, "source_paths")
            XCTAssertFalse(sources.isEmpty)
            XCTAssertTrue(
                sources.contains { authorized.contains($0) },
                "Route has no S10.3-authorized migrated source: \(routeID)"
            )
            for source in sources {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: repositoryRoot.appendingPathComponent(source).path
                    ),
                    source
                )
            }
        }

        let uiPath = "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift"
        let statePattern = try NSRegularExpression(
            pattern: #"state\.[a-z0-9.-]+"#
        )
        func visitedIDs(in uiSource: String) -> [String] {
            let range = NSRange(uiSource.startIndex..<uiSource.endIndex, in: uiSource)
            return statePattern.matches(in: uiSource, range: range)
                .compactMap { match -> String? in
                    guard let matchRange = Range(match.range, in: uiSource) else {
                        return nil
                    }
                    return String(uiSource[matchRange])
                }
        }
        // Card-time fact (owner decision A): the S10.3 product-head UI source named exactly
        // the 67 inventory states once each. S10.4 grew that file into the lab harness, so
        // the exact count is proven on the committed S10.3 history (S10CardHistoryV1).
        let historicalVisitedIDs = try visitedIDs(in: historicalText(uiPath))
        XCTAssertEqual(historicalVisitedIDs.count, 67)
        XCTAssertEqual(Set(historicalVisitedIDs), Set(stateIDs))
        // Enduring fact: the live UI source still visits every one of the 67 states.
        let liveVisitedIDs = try Set(visitedIDs(in: text(uiPath)))
        XCTAssertTrue(
            Set(stateIDs).isSubset(of: liveVisitedIDs),
            "Live S10.3 UI source no longer visits: \(Set(stateIDs).subtracting(liveVisitedIDs).sorted())"
        )
    }

    func testAllReleasedSourcesUseTheClosedBrandSystemWithoutVisualForks() throws {
        let sources = try productionPaths.map { path in
            (path, try text(path))
        }
        let combined = sources.map(\.1).joined(separator: "\n")

        // Card-time state (owner decision A): at the S10.3 product head no migrated source
        // used the legacy Worklight button styles. The accepted S10.4 automated lab then
        // re-owned them for non-Button controls (Menu, NavigationLink, PhotosPicker) with the
        // exact per-file counts S10_4AutomatedBrandLabTests pins. They are admitted only at
        // those closed owners and counts; every other legacy fragment stays forbidden.
        let worklightButtonStyleOwners: [String: (primary: Int, secondary: Int)] = [
            // Accepted S10.4 owners (product head 0adebd7), unchanged at accepted main.
            "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift": (0, 1),
            "FieldEvidenceApp/Features/Issues/RecordWorkView.swift": (0, 1),
            "FieldEvidenceApp/Features/Reports/ReportsRootView.swift": (1, 3),
            "FieldEvidenceApp/Features/Shell/AppShellView.swift": (0, 2),
            // V23 C43 (a0fae03) completed-work More menu: same Menu precedent as the
            // ReportsRootView filters. Not S10-accepted; human visual review remains due.
            "FieldEvidenceApp/Features/Issues/IssueDetailView.swift": (0, 1),
        ]
        for (path, source) in sources {
            let owner = worklightButtonStyleOwners[path] ?? (primary: 0, secondary: 0)
            XCTAssertEqual(
                source.components(separatedBy: "WorklightPrimaryButtonStyle").count - 1,
                owner.primary,
                "Worklight primary button style outside its closed owner count: \(path)"
            )
            XCTAssertEqual(
                source.components(separatedBy: "WorklightSecondaryButtonStyle").count - 1,
                owner.secondary,
                "Worklight secondary button style outside its closed owner count: \(path)"
            )
        }
        XCTAssertTrue(Set(worklightButtonStyleOwners.keys).isSubset(of: Set(productionPaths)))

        let forbiddenFragments = [
            "WorklightCard",
            "WorklightStatusBadge",
            "DesignTokens.Colors",
            "DesignTokens.Control",
            "DesignTokens.Spacing.small",
            "DesignTokens.Spacing.medium",
            "DesignTokens.Spacing.large",
            "DesignTokens.Spacing.extraLarge",
            "DesignTokens.Spacing.cardPadding",
            ".font(.custom",
            ".glassEffect",
            ".ultraThinMaterial",
            ".thinMaterial",
            ".regularMaterial",
            ".thickMaterial",
            ".scaledToFill()",
            ".aspectRatio(contentMode: .fill)",
        ]
        for fragment in forbiddenFragments {
            XCTAssertFalse(
                combined.contains(fragment),
                "Found untracked legacy/ad hoc presentation fragment: \(fragment)"
            )
        }

        for component in expectedComponentTypes {
            XCTAssertTrue(
                combined.contains(component),
                "Accepted component role was not adopted: \(component)"
            )
        }
        for (path, source) in sources {
            XCTAssertTrue(
                source.contains("AssetRounds")
                    || source.contains("DesignTokens.SemanticColors"),
                "Released source did not adopt the shared brand system: \(path)"
            )
        }

        XCTAssertTrue(combined.contains("DesignTokens.Typography.screenTitle"))
        XCTAssertTrue(combined.contains("DesignTokens.Typography.primaryBody"))
        XCTAssertTrue(combined.contains("DesignTokens.Spacing.space8"))
        XCTAssertTrue(combined.contains("DesignTokens.Spacing.space16"))
        XCTAssertTrue(combined.contains("DesignTokens.Target.minimumInteractiveHeight"))
        XCTAssertTrue(combined.contains("DesignTokens.SemanticColors.workBackground"))
        XCTAssertTrue(combined.contains("DesignTokens.SemanticColors.primaryAction"))
        XCTAssertTrue(combined.contains("DesignTokens.SemanticColors.completed"))
        XCTAssertTrue(combined.contains("DesignTokens.SemanticColors.warning"))
        XCTAssertTrue(combined.contains("DesignTokens.SemanticColors.error"))
        XCTAssertTrue(combined.contains("kind: .unavailable"))
        XCTAssertTrue(combined.contains("kind: .selected"))
    }

    func testCopyIdentifiersImportsAndNativeBehaviorAuthorityStayFrozen() throws {
        let importDigest = try sourceDigest { source in
            source.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
        }
        // Re-pinned for the V23 Phase 1 candidate (base d2c1c4b). History: the S10.4-era pin
        // 22CBACD7…2535 (as of commit 4ade197) held through accepted main b1d04ae; V23 added
        // `import UIKit` to FieldEvidenceAppApp.swift. The exact added/removed imports and
        // literals per file are recorded in docs/design/v23/integration/s10-3-copy-freeze-delta-v23.json.
        XCTAssertEqual(
            importDigest,
            "F718F0601EE8B4D441A27519075934F787DF868D435FFD7ED167C654C8C116F5",
            "Presentation-only migration changed the dependency/import surface"
        )

        let literalPattern = try NSRegularExpression(
            pattern: #""(?:\\.|[^"\\])*""#
        )
        let literalDigest = try sourceDigest { source in
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            return literalPattern.matches(in: source, range: range)
                .compactMap { match -> String? in
                    guard let matchRange = Range(match.range, in: source) else {
                        return nil
                    }
                    return String(source[matchRange])
                }
        }
        // Re-pinned for the V23 Phase 1 candidate. History: 1FC7F5B8…2D26 (as of commit 4ade197)
        // was already stale at accepted main b1d04ae (5CDFCFAA…2E44) because the accepted
        // S10.4 DEBUG recheck-navigation observer added 23 SignsRootView literals. V23 then
        // renamed the Signs tab to Assets and added Today and Work (commit aa0dc10, required
        // by BLUEPRINT:9654) and added durable capture, C43 response, Reports and erase copy.
        // Phase 1 UI tests then added the DEBUG-only local-auth UI-test hook literals to
        // FieldEvidenceAppApp.swift (B67BFF5F…C95B before that edit). Maintenance support and
        // salvage (owner decisions 14 and 18) then added the maintenance "View diagnostics" and
        // "Save photos and reports" copy (F776F6B2…52EF held at 779b21f1); the per-file delta is in
        // the same JSON record.
        XCTAssertEqual(
            literalDigest,
            "D6638A7571332E437BDFCC92004E80F49111FF3A2E251B721DC0087638B6B8BA",
            "Released copy, accessibility identifiers, symbols, or fixed product facts drifted"
        )
        let delta = try json("docs/design/v23/integration/s10-3-copy-freeze-delta-v23.json")
        let deltaDigests = try XCTUnwrap(delta["digests"] as? [String: Any])
        for (key, expected) in [
            ("s10_3_imports", importDigest),
            ("s10_3_literals", literalDigest),
        ] {
            let candidate = try XCTUnwrap(
                (deltaDigests[key] as? [String: Any])?["candidate"] as? [String: Any],
                key
            )
            XCTAssertEqual(candidate["sha256"] as? String, expected, key)
        }

        let allSources = try productionPaths.map { try text($0) }.joined(separator: "\n")
        XCTAssertFalse(allSources.contains("AppStore.sync()"))
        XCTAssertFalse(allSources.contains("mailto:"))
        XCTAssertFalse(allSources.contains("scaledToFill"))
        XCTAssertFalse(allSources.contains("aspectRatio(contentMode: .fill)"))
    }

    func testCardTimeRecordsAreTheCommittedS10History() throws {
        try S10CardHistoryV1.assertBoundToCommittedHistory(
            card: .migration,
            repositoryRoot: repositoryRoot
        )
    }

    func testSelectorAndPredecessorEvidenceRemainExactAndUnpromoted() throws {
        // Card-time state (owner decision A): the selector and the predecessor token document
        // resolve to the committed S10.3 product-head history (selector git blob 3e4f27a2;
        // token document = the S10.2 receipt-recorded blob D52B72B8…B476). The visual
        // baselines remain immutable-blank and are still checked live below.
        let selector = #"{"schemaVersion":1,"taskID":"S10.3","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S10_3BrandMigrationTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S10_3BrandMigrationUITests"]}"# + "\n"
        XCTAssertEqual(try data("Scripts/ci-selection.json"), Data(selector.utf8))

        let tokens = try json("docs/design/s10/s10-token-coverage.json")
        XCTAssertEqual(tokens["document_status"] as? String, "components_implemented")
        XCTAssertEqual(
            tokens["component_system_product_head"] as? String,
            "28c5851a432db026251012de1e396a5896c9f91f"
        )
        XCTAssertEqual(
            tokens["migration_product_head"] as? String,
            "REQUIRED_AFTER_S10_MIGRATION"
        )
        XCTAssertEqual(tokens["untracked_visual_constant_count"] as? Int, 16)
        let components = try rows(tokens, "components")
        XCTAssertEqual(components.count, 9)
        XCTAssertTrue(components.allSatisfy { ($0["status"] as? String) == "PASS" })
        let coverage = try rows(tokens, "coverage")
        XCTAssertEqual(coverage.count, 67)
        XCTAssertTrue(coverage.allSatisfy { ($0["status"] as? String) == "NOT_RUN" })

        let visual = try json("docs/design/s10/s10-visual-regression.json")
        let baselines = try rows(visual, "baselines")
        XCTAssertEqual(baselines.count, 67)
        XCTAssertTrue(baselines.allSatisfy {
            ($0["baseline_review_status"] as? String) == "APPROVED"
                && ($0["baseline_reviewer"] as? String) == "palatis3"
                && ($0["candidate_product_head"] as? String) == ""
                && ($0["candidate_screenshot_path"] as? String) == ""
                && ($0["candidate_sha256"] as? String) == ""
                && ($0["result"] as? String) == "NOT_RUN"
        })
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // Owner decision A (2026-09-25): only these card-time paths resolve to the committed
    // S10.3 history; every other read, including the live UI source, stays live.
    private let cardTimePaths: Set<String> = [
        "Scripts/ci-selection.json",
        "docs/design/s10/s10-token-coverage.json",
    ]

    private func data(_ relativePath: String) throws -> Data {
        if cardTimePaths.contains(relativePath),
           let historical = try S10CardHistoryV1.data(
               card: .migration,
               path: relativePath,
               repositoryRoot: repositoryRoot
           ) {
            return historical
        }
        return try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func historicalText(_ relativePath: String) throws -> String {
        let bytes = try XCTUnwrap(
            try S10CardHistoryV1.data(
                card: .migration,
                path: relativePath,
                repositoryRoot: repositoryRoot
            ),
            relativePath
        )
        return String(decoding: bytes, as: UTF8.self)
    }

    private func text(_ relativePath: String) throws -> String {
        String(decoding: try data(relativePath), as: UTF8.self)
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data(relativePath))
        return try XCTUnwrap(value as? [String: Any], relativePath)
    }

    private func rows(
        _ value: [String: Any],
        _ key: String
    ) throws -> [[String: Any]] {
        try XCTUnwrap(value[key] as? [[String: Any]], key)
    }

    private func string(_ value: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(value[key] as? String, key)
    }

    private func strings(_ value: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(value[key] as? [String], key)
    }

    private func sourceDigest(
        values: (String) throws -> [String]
    ) throws -> String {
        var canonical = ""
        for path in productionPaths {
            canonical += path + "\n"
            canonical += try values(text(path)).joined(separator: "\n")
            canonical += "\n"
        }
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }
}
