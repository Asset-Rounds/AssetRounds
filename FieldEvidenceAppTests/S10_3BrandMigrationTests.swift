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

        let uiSource = try text(
            "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift"
        )
        let statePattern = try NSRegularExpression(
            pattern: #"state\.[a-z0-9.-]+"#
        )
        let range = NSRange(uiSource.startIndex..<uiSource.endIndex, in: uiSource)
        let visitedIDs = statePattern.matches(in: uiSource, range: range)
            .compactMap { match -> String? in
                guard let matchRange = Range(match.range, in: uiSource) else {
                    return nil
                }
                return String(uiSource[matchRange])
            }
        XCTAssertEqual(visitedIDs.count, 67)
        XCTAssertEqual(Set(visitedIDs), Set(stateIDs))
    }

    func testAllReleasedSourcesUseTheClosedBrandSystemWithoutVisualForks() throws {
        let sources = try productionPaths.map { path in
            (path, try text(path))
        }
        let combined = sources.map(\.1).joined(separator: "\n")

        let forbiddenFragments = [
            "WorklightCard",
            "WorklightStatusBadge",
            "WorklightPrimaryButtonStyle",
            "WorklightSecondaryButtonStyle",
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
        XCTAssertEqual(
            importDigest,
            "22CBACD7A96A1F16BD28263D4F7C9F33AE72C03AA116B0AC0B8A2C4CA86E2535",
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
        XCTAssertEqual(
            literalDigest,
            "1FC7F5B8D24E0B2F0A1111A4F21495C40CA3A306A708EB3CA0CAE0760A562D26",
            "Released copy, accessibility identifiers, symbols, or fixed product facts drifted"
        )

        let allSources = try productionPaths.map { try text($0) }.joined(separator: "\n")
        XCTAssertFalse(allSources.contains("AppStore.sync()"))
        XCTAssertFalse(allSources.contains("mailto:"))
        XCTAssertFalse(allSources.contains("scaledToFill"))
        XCTAssertFalse(allSources.contains("aspectRatio(contentMode: .fill)"))
    }

    func testSelectorAndPredecessorEvidenceRemainExactAndUnpromoted() throws {
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
