import XCTest
@testable import FieldEvidenceApp

#if DEBUG && targetEnvironment(simulator)
final class V30P02C06PseudoLocalizationHarnessTests: XCTestCase {
    override func tearDown() {
        TestOnlyPseudoLocalizationDiagnosticsV1.reset()
        super.tearDown()
    }

    func testLaunchConfigurationRequiresBothUniqueGatesAndParsesEverySupportedMatrixValue() throws {
        XCTAssertNil(try V30PseudoLocalizationLaunchConfigurationV1.parse(arguments: []))

        for profile in V30PseudoLocalizationLaunchConfigurationV1.Profile.allCases {
            for dynamicType in V30PseudoLocalizationLaunchConfigurationV1.DynamicType.allCases {
                for appearance in V30PseudoLocalizationLaunchConfigurationV1.Appearance.allCases {
                    for contrast in V30PseudoLocalizationLaunchConfigurationV1.Contrast.allCases {
                        XCTAssertEqual(
                            try V30PseudoLocalizationLaunchConfigurationV1.parse(
                                arguments: V30PseudoLocalizationHarnessTestSupportV1.arguments(
                                    profile: profile,
                                    dynamicType: dynamicType,
                                    appearance: appearance,
                                    contrast: contrast
                                )
                            ),
                            V30PseudoLocalizationHarnessTestSupportV1.configuration(
                                profile: profile,
                                dynamicType: dynamicType,
                                appearance: appearance,
                                contrast: contrast
                            )
                        )
                    }
                }
            }
        }

        assertParseError(
            .partialActivation,
            arguments: [V30PseudoLocalizationLaunchConfigurationV1.harnessArgument]
        )
        assertParseError(
            .partialActivation,
            arguments: [V30PseudoLocalizationLaunchConfigurationV1.profileArgument, "en-XA"]
        )
        assertParseError(
            .duplicateOption,
            arguments: [V30PseudoLocalizationLaunchConfigurationV1.harnessArgument]
                + V30PseudoLocalizationHarnessTestSupportV1.arguments()
        )
        assertParseError(
            .duplicateOption,
            arguments: [V30PseudoLocalizationLaunchConfigurationV1.uiTestingArgument]
                + V30PseudoLocalizationHarnessTestSupportV1.arguments()
        )
        assertParseError(
            .unknownOption,
            arguments: V30PseudoLocalizationHarnessTestSupportV1.arguments()
                + ["--v30-p02-c06-unrecognized"]
        )
        assertParseError(
            .duplicateOption,
            arguments: V30PseudoLocalizationHarnessTestSupportV1.arguments()
                + [V30PseudoLocalizationLaunchConfigurationV1.profileArgument, "en-XA"]
        )
        assertParseError(
            .missingValue,
            arguments: [
                V30PseudoLocalizationLaunchConfigurationV1.harnessArgument,
                V30PseudoLocalizationLaunchConfigurationV1.uiTestingArgument,
                V30PseudoLocalizationLaunchConfigurationV1.profileArgument,
            ]
        )
        assertParseError(
            .invalidValue,
            arguments: replacing(
                V30PseudoLocalizationHarnessTestSupportV1.arguments(),
                valueAfter: V30PseudoLocalizationLaunchConfigurationV1.contrastArgument,
                with: "unreadable"
            )
        )
    }

    func testPseudoTransformsHaveExactStableExpansionAndProtectedTokenOrder() {
        XCTAssertEqual(
            render(profile: .enXA, english: V30PseudoLocalizationHarnessTestSupportV1.fixedSource),
            V30PseudoLocalizationHarnessTestSupportV1.expectedAccented
        )
        let long = render(
            profile: .enXL,
            english: V30PseudoLocalizationHarnessTestSupportV1.fixedSource
        )
        XCTAssertEqual(long, V30PseudoLocalizationHarnessTestSupportV1.expectedLong)
        XCTAssertGreaterThanOrEqual(
            long.utf8.count,
            V30PseudoLocalizationHarnessTestSupportV1.fixedSource.utf8.count
                * V30PseudoLocalizationHarnessTestSupportV1.longExpansionMinimumMultiplier
        )

        let protectedSource = "A %@ B %1$@ C %lld D %2$lld E %% F {assetID} G"
        for profile in V30PseudoLocalizationLaunchConfigurationV1.Profile.allCases {
            let first = render(profile: profile, english: protectedSource)
            let second = render(profile: profile, english: protectedSource)
            XCTAssertEqual(Array(first.utf8), Array(second.utf8), profile.rawValue)
            assertProtectedTokenOrderAndMultiplicity(in: first, profile: profile)
        }
    }

    func testPseudoTransformsPreserveRequiredUnicodeGraphemeByteSequences() {
        let nfd = "e\u{301}"
        let decomposedHangul = "\u{1112}\u{1161}\u{11AB}"
        let family = "👨‍👩‍👧‍👦"
        let worker = "👩🏽‍🔧"
        let cjk = "中文"
        let arabic = "العربية"
        let clusters = [nfd, decomposedHangul, family, worker, cjk, arabic]
        let source = clusters.joined(separator: " • ")
        XCTAssertEqual(Array(nfd.utf8), [0x65, 0xCC, 0x81])
        XCTAssertEqual(Array(decomposedHangul.utf8), [
            0xE1, 0x84, 0x92, 0xE1, 0x85, 0xA1, 0xE1, 0x86, 0xAB,
        ])

        for profile in V30PseudoLocalizationLaunchConfigurationV1.Profile.allCases {
            let output = render(profile: profile, english: source)
            let expectedOccurrences = profile == .enXL ? 2 : 1
            for cluster in clusters {
                let ranges = output.ranges(of: cluster)
                XCTAssertEqual(ranges.count, expectedOccurrences, "\(profile.rawValue): \(cluster)")
                for range in ranges {
                    XCTAssertEqual(
                        Array(output[range].utf8),
                        Array(cluster.utf8),
                        "\(profile.rawValue): \(cluster)"
                    )
                }
            }
        }
    }

    func testResolverCountersTrackStateTransitionsAggregateUnknownsAndReset() {
        let configuration = V30PseudoLocalizationHarnessTestSupportV1.configuration()
        TestOnlyPseudoLocalizationDiagnosticsV1.reset()
        XCTAssertEqual(snapshot(), .init(resolvedCount: 0, unresolvedKeyCount: 0, unexpectedFallbackCount: 0))

        _ = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.title",
            english: "Field inspection ready",
            configuration: configuration
        )
        _ = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.title",
            english: "Field inspection ready",
            configuration: configuration
        )
        XCTAssertEqual(snapshot(), .init(resolvedCount: 1, unresolvedKeyCount: 0, unexpectedFallbackCount: 0))

        let fallback = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.fallbackProbe",
            english: "Field inspection ready",
            configuration: configuration
        )
        XCTAssertEqual(fallback, "Fallback probe")
        XCTAssertEqual(snapshot(), .init(resolvedCount: 1, unresolvedKeyCount: 0, unexpectedFallbackCount: 1))

        XCTAssertEqual(
            TestOnlyPseudoLocalizationResolverV1.render(
                semanticID: "pseudo.title",
                english: "",
                configuration: configuration
            ),
            "[unresolved test string]"
        )
        XCTAssertEqual(snapshot(), .init(resolvedCount: 0, unresolvedKeyCount: 1, unexpectedFallbackCount: 1))

        _ = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.title",
            english: "Field inspection ready",
            configuration: configuration
        )
        XCTAssertEqual(snapshot(), .init(resolvedCount: 1, unresolvedKeyCount: 0, unexpectedFallbackCount: 1))

        let unknownKeys = ["not.a.shipping.localization.key", "another.unknown.key"]
        for key in unknownKeys + unknownKeys {
            let unresolved = TestOnlyPseudoLocalizationResolverV1.render(
                semanticID: key,
                english: "Must not be used as a fallback label",
                configuration: configuration
            )
            XCTAssertEqual(unresolved, "[unresolved test string]")
            XCTAssertFalse(unresolved.contains(key))
        }
        XCTAssertEqual(snapshot(), .init(resolvedCount: 1, unresolvedKeyCount: 1, unexpectedFallbackCount: 1))

        TestOnlyPseudoLocalizationDiagnosticsV1.reset()
        XCTAssertEqual(snapshot(), .init(resolvedCount: 0, unresolvedKeyCount: 0, unexpectedFallbackCount: 0))
    }

    func testC06PseudoProfilesRemainTestOnlyAndNeverBecomeShippingLocales() {
        let manifest = LocalizationLocaleManifestV1.shippingV1()
        let harnessProfiles = Set(
            V30PseudoLocalizationLaunchConfigurationV1.Profile.allCases.map(\.rawValue)
        )
        XCTAssertTrue(harnessProfiles.isSubset(of: Set(manifest.testOnlyPseudoLocaleIdentifiers)))
        XCTAssertTrue(harnessProfiles.isDisjoint(with: Set(manifest.shippingRuntimeLanguages)))
        XCTAssertFalse(TestOnlyPseudoLocaleV1.shippingEnabled)
        XCTAssertFalse(PackageEvolutionLocalizationPolicyV1.pseudoLocalesMayShip)
    }

    private func render(
        profile: V30PseudoLocalizationLaunchConfigurationV1.Profile,
        english: String
    ) -> String {
        TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.summary",
            english: english,
            configuration: V30PseudoLocalizationHarnessTestSupportV1.configuration(profile: profile)
        )
    }

    private func snapshot() -> TestOnlyPseudoLocalizationDiagnosticSnapshotV1 {
        TestOnlyPseudoLocalizationDiagnosticsV1.snapshot()
    }

    private func assertProtectedTokenOrderAndMultiplicity(
        in value: String,
        profile: V30PseudoLocalizationLaunchConfigurationV1.Profile,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lowerBound = value.startIndex
        for token in V30PseudoLocalizationHarnessTestSupportV1.orderedProtectedTokens {
            let ranges = value.ranges(of: token)
            XCTAssertEqual(ranges.count, 1, "\(profile.rawValue): \(token)", file: file, line: line)
            guard let range = ranges.first else { continue }
            XCTAssertGreaterThanOrEqual(
                range.lowerBound,
                lowerBound,
                "\(profile.rawValue): \(token)",
                file: file,
                line: line
            )
            lowerBound = range.upperBound
        }
    }

    private func assertParseError(
        _ expected: V30PseudoLocalizationLaunchConfigurationV1.ParseError,
        arguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try V30PseudoLocalizationLaunchConfigurationV1.parse(arguments: arguments),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? V30PseudoLocalizationLaunchConfigurationV1.ParseError, expected)
        }
    }

    private func replacing(_ arguments: [String], valueAfter option: String, with replacement: String) -> [String] {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return arguments
        }
        var result = arguments
        result[index + 1] = replacement
        return result
    }
}

private extension String {
    func ranges(of needle: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var searchStart = startIndex
        while let range = range(of: needle, range: searchStart..<endIndex) {
            result.append(range)
            searchStart = range.upperBound
        }
        return result
    }
}
#endif
