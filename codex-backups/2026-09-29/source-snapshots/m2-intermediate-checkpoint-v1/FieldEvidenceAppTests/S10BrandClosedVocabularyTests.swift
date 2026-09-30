import Foundation
import XCTest

/// V23 Phase 1 brand guard over the 26 S10.3-migrated sources and the V23 shell surfaces:
/// button styles, tints, colours and design tokens come only from the closed S10 design
/// system (DesignTokens S10 roles and AssetRounds components). It extends the S10_3
/// forbidden-token approach from a deny list to a closed vocabulary, so a new legacy token,
/// raw colour, shorthand style or unlisted Worklight button-style owner fails here.
final class S10BrandClosedVocabularyTests: XCTestCase {
    private static let migratedPaths = [
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

    private static let v23ShellPaths = [
        "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "FieldEvidenceApp/Features/Shell/ProductionWorkRootViewV1.swift",
        "FieldEvidenceApp/Features/Shell/ProductionMyDayRootViewV1.swift",
        "FieldEvidenceApp/Features/Accountability/CompletedWorkDetailViewV1.swift",
        "FieldEvidenceApp/Features/Accountability/SignoffResponseHistoryViewV1.swift",
        // Phase 1 critical-journey editor (Work -> Completed work -> detail -> More -> Record
        // approval response); no Worklight button-style admission.
        "FieldEvidenceApp/Features/Accountability/SignoffEnrollmentView.swift",
    ]

    private static var scopedPaths: [String] {
        migratedPaths + v23ShellPaths.filter { !migratedPaths.contains($0) }
    }

    /// The S10 token roles (DesignTokens.tokenIDs) by namespace and Swift member name. The
    /// pre-S10 compatibility namespaces (Colors, Control) and spacing aliases (unit, small,
    /// medium, large, extraLarge, cardPadding) are outside the vocabulary.
    private static let tokenVocabulary: [String: Set<String>] = [
        "SemanticColors": [
            "workBackground", "groupedBackground", "elevatedSurface", "primaryText",
            "secondaryText", "tertiaryText", "separator", "primaryAction", "brandHeading",
            "completed", "warning", "error", "unavailable", "selected", "disabled",
        ],
        "Typography": [
            "screenTitle", "sectionHeading", "primaryBody", "secondaryBody", "fieldLabel",
            "supportingCaption", "numericOrTimestamp",
        ],
        "Spacing": ["space4", "space8", "space12", "space16", "space20", "space24", "space32"],
        "Radius": ["compact", "standard", "prominent"],
        "Stroke": ["standard", "selected"],
        "Target": ["minimumInteractiveWidth", "minimumInteractiveHeight", "minimumInteractive"],
        "Environment": ["minimumSupportedIOSMajorVersion"],
    ]

    /// The legacy Worklight button styles are admitted only at these exact owners and counts.
    private static let worklightButtonStyleOwners: [String: (primary: Int, secondary: Int)] = [
        // Accepted S10.4 owners (Menu, NavigationLink and PhotosPicker controls that the
        // AssetRounds action components cannot wrap), pinned by S10_4AutomatedBrandLabTests.
        "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift": (0, 1),
        "FieldEvidenceApp/Features/Issues/RecordWorkView.swift": (0, 1),
        "FieldEvidenceApp/Features/Reports/ReportsRootView.swift": (1, 3),
        "FieldEvidenceApp/Features/Shell/AppShellView.swift": (0, 2),
        // V23 additions, not S10-accepted; each needs human visual review before release.
        // C43 completed-work More menu (same Menu precedent as the ReportsRootView filters).
        "FieldEvidenceApp/Features/Issues/IssueDetailView.swift": (0, 1),
        // Work root Refresh button: a plain Button, so AssetRoundsSecondaryAction is the S10
        // component; tracked as noncritical visual polish.
        "FieldEvidenceApp/Features/Shell/ProductionWorkRootViewV1.swift": (0, 1),
    ]

    private static let admittedButtonStyles: Set<String> = [
        ".plain", "WorklightPrimaryButtonStyle()", "WorklightSecondaryButtonStyle()",
    ]

    private static let forbiddenFragments = [
        "WorklightCard", "WorklightStatusBadge", "UIColor", ".foregroundColor(",
        ".accentColor(", ".colorMultiply(", ".font(.custom", ".glassEffect",
        ".ultraThinMaterial", ".thinMaterial", ".regularMaterial", ".thickMaterial",
    ]

    /// Colour-bearing modifiers: every argument must name an S10 semantic colour and no
    /// shorthand style such as `.red`, `.secondary` or `.tint`.
    private static let colourModifiers = [
        "foregroundStyle", "background", "tint", "fill", "stroke", "strokeBorder", "border",
        "listRowBackground", "listRowSeparatorTint", "shadow", "toolbarBackground",
    ]

    func testScopedSourcesUseOnlyTheClosedS10StylingVocabulary() throws {
        XCTAssertEqual(Self.migratedPaths.count, 26)
        XCTAssertEqual(Set(Self.scopedPaths).count, 31)
        XCTAssertTrue(Set(Self.worklightButtonStyleOwners.keys).isSubset(of: Set(Self.scopedPaths)))
        for path in Self.scopedPaths {
            XCTAssertEqual(try Self.violations(in: text(path), path: path), [], path)
        }
    }

    func testClosedVocabularyRejectsTheC43LegacyTokenAndOtherForks() throws {
        let issuePath = "FieldEvidenceApp/Features/Issues/IssueDetailView.swift"
        let otherPath = "FieldEvidenceApp/Features/Reports/ReportFailureView.swift"
        // The exact C43 (a0fae03) More-menu label before this correction.
        let c43Drift =
            "                            Label(\"More\", systemImage: \"ellipsis.circle\")\n" +
            "                                .frame(\n" +
            "                                    maxWidth: .infinity,\n" +
            "                                    minHeight: DesignTokens.Control.minimumHitSize\n" +
            "                                )\n" +
            "                        }\n" +
            "                        .buttonStyle(WorklightSecondaryButtonStyle())\n"
        XCTAssertEqual(
            try Self.violations(in: c43Drift, path: issuePath),
            ["token DesignTokens.Control.minimumHitSize"]
        )
        XCTAssertEqual(
            try Self.violations(
                in: c43Drift.replacingOccurrences(
                    of: "DesignTokens.Control.minimumHitSize",
                    with: "DesignTokens.Target.minimumInteractiveHeight"
                ),
                path: issuePath
            ),
            []
        )

        let hostile: [(String, String)] = [
            (".foregroundStyle(DesignTokens.Colors.primaryText)", "token DesignTokens.Colors.primaryText"),
            (".padding(DesignTokens.Spacing.medium)", "token DesignTokens.Spacing.medium"),
            (".background(DesignTokens.Colors.canvas)", "token DesignTokens.Colors.canvas"),
            ("WorklightCard {\n}", "fragment WorklightCard"),
            (".foregroundStyle(.secondary)", "colour foregroundStyle(.secondary)"),
            (".tint(.blue)", "colour tint(.blue)"),
            (".background(Color.red)", "colour background(Color.red)"),
            (".fill(Color(red: 1, green: 0, blue: 0))", "colour fill(Color(red: 1, green: 0, blue: 0))"),
            (".buttonStyle(.borderedProminent)", "buttonStyle .borderedProminent"),
            (".buttonStyle(WorklightSecondaryButtonStyle())", "Worklight secondary count 1 != 0"),
            (".foregroundColor(DesignTokens.SemanticColors.primaryText)", "fragment .foregroundColor("),
            ("let tint = UIColor.systemTeal", "fragment UIColor"),
        ]
        for (fragment, expected) in hostile {
            let observed = try Self.violations(in: fragment, path: otherPath)
            XCTAssertTrue(observed.contains(expected), "\(fragment) -> \(observed)")
        }
        for accepted in [
            ".foregroundStyle(DesignTokens.SemanticColors.primaryText)",
            ".foregroundStyle(isError ? DesignTokens.SemanticColors.error : DesignTokens.SemanticColors.secondaryText)",
            ".stroke(DesignTokens.SemanticColors.separator, lineWidth: DesignTokens.Stroke.standard)",
            ".tint(DesignTokens.SemanticColors.primaryAction)",
            ".buttonStyle(.plain)",
            "AssetRoundsEvidenceCard {\n}",
            ".frame(minWidth: DesignTokens.Target.minimumInteractiveWidth)",
        ] {
            XCTAssertEqual(try Self.violations(in: accepted, path: otherPath), [], accepted)
        }
    }

    // MARK: - Vocabulary rules

    static func violations(in source: String, path: String) throws -> [String] {
        var found = [String]()

        let tokenPattern = try NSRegularExpression(
            pattern: #"DesignTokens\.([A-Za-z]+)(?:\.([A-Za-z][A-Za-z0-9]*))?"#
        )
        for match in tokenPattern.matches(in: source, range: fullRange(source)) {
            let token = substring(source, match.range)
            let namespace = substring(source, match.range(at: 1))
            let member: String? = match.range(at: 2).location == NSNotFound
                ? nil
                : substring(source, match.range(at: 2))
            guard let members = tokenVocabulary[namespace],
                  let member,
                  members.contains(member)
            else {
                found.append("token \(token)")
                continue
            }
        }

        for fragment in forbiddenFragments where source.contains(fragment) {
            found.append("fragment \(fragment)")
        }
        let rawColour = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])Color\s*[.(]"#)
        if rawColour.firstMatch(in: source, range: fullRange(source)) != nil {
            found.append("colour literal Color")
        }

        for argument in arguments(of: "buttonStyle", in: source)
        where !admittedButtonStyles.contains(argument) {
            found.append("buttonStyle \(argument)")
        }
        let owner = worklightButtonStyleOwners[path] ?? (primary: 0, secondary: 0)
        let primary = source.components(separatedBy: "WorklightPrimaryButtonStyle").count - 1
        let secondary = source.components(separatedBy: "WorklightSecondaryButtonStyle").count - 1
        if primary != owner.primary {
            found.append("Worklight primary count \(primary) != \(owner.primary)")
        }
        if secondary != owner.secondary {
            found.append("Worklight secondary count \(secondary) != \(owner.secondary)")
        }

        let shorthand = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_\)\]])\.[a-z][A-Za-z0-9]*"#)
        for modifier in colourModifiers {
            for argument in arguments(of: modifier, in: source) {
                let namesSemanticColour = argument.contains("DesignTokens.SemanticColors.")
                let usesShorthand = shorthand.firstMatch(
                    in: argument,
                    range: fullRange(argument)
                ) != nil
                let exactTint = modifier != "tint" || argument.range(
                    of: #"^DesignTokens\.SemanticColors\.[A-Za-z]+$"#,
                    options: .regularExpression
                ) != nil
                if !namesSemanticColour || usesShorthand || !exactTint {
                    found.append("colour \(modifier)(\(argument))")
                }
            }
        }
        return found
    }

    /// The balanced argument text of every `.<modifier>(` call, whitespace-collapsed.
    private static func arguments(of modifier: String, in source: String) -> [String] {
        var result = [String]()
        let marker = ".\(modifier)("
        var searchStart = source.startIndex
        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            var depth = 1
            var index = markerRange.upperBound
            var inString = false
            var previous: Character = " "
            while index < source.endIndex, depth > 0 {
                let character = source[index]
                if character == "\"", previous != "\\" {
                    inString.toggle()
                } else if !inString {
                    if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                    }
                }
                previous = character
                if depth > 0 {
                    index = source.index(after: index)
                }
            }
            let argument = source[markerRange.upperBound..<index]
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            result.append(argument)
            searchStart = index < source.endIndex ? source.index(after: index) : source.endIndex
        }
        return result
    }

    private static func fullRange(_ value: String) -> NSRange {
        NSRange(value.startIndex..<value.endIndex, in: value)
    }

    private static func substring(_ value: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: value) else { return "" }
        return String(value[swiftRange])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        String(
            decoding: try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath)),
            as: UTF8.self
        )
    }
}
