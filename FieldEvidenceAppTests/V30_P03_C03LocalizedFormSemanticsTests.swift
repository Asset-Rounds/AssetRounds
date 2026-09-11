import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V30P03C03LocalizedFormSemanticsTests: XCTestCase {
    func testFormSemanticsRegistryContainsEightTypedEnglishFallbacksAcrossSixUILocales() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let registry = try BundledLocalizationCatalogV1.formSemanticsRegistry()

        XCTAssertEqual(fixture.cardID, "V30-P03-C03")
        XCTAssertEqual(fixture.uiLocales, ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"])
        XCTAssertEqual(
            fixture.formSemantics.map(\.key),
            LocalizedFormSemanticsMessageKeyV1.allCases.map(\.rawValue)
        )
        XCTAssertEqual(
            registry.definitions.filter { $0.key.rawValue.hasPrefix("v30.form-semantics.") }.count,
            8
        )

        for expected in fixture.formSemantics {
            let key = try XCTUnwrap(LocalizedFormSemanticsMessageKeyV1(rawValue: expected.key))
            XCTAssertEqual(BundledLocalizationCatalogV1.formSemanticsEnglish(key), expected.english)
            for locale in fixture.uiLocales {
                XCTAssertEqual(
                    BundledLocalizationCatalogV1.formSemanticsText(
                        key,
                        bundle: Bundle(for: Self.self),
                        locale: Locale(identifier: locale)
                    ),
                    expected.english,
                    locale
                )
            }
        }
    }

    func testArchiveBoundAuthoredTextChoiceOrderAndCanonicalBytesStayExact() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let archive = try V30P03C03FormTestSupport.archive()
        let fact = V30P03C03FormTestSupport.choiceFact(fixture: fixture, required: true)
        let field = try V30P03C03FormTestSupport.choiceField(fixture: fixture)
        let release = try V30P03C03FormTestSupport.release(
            facts: [fact], archive: archive, fixture: fixture
        )
        let releaseBytes = try SurveyDefinitionCanonicalCodecV1.encode(release)
        let response = try BoundResponseValueV1(
            fieldID: field.fieldID,
            value: .singleOption("choice.alpha")
        )
        let responseBytes = try ResponseValueCanonicalCodecV1.encode(response.value)
        let expected = fixture.authored.label
        let key = try LocalizationKeyV1(fixture.authored.key)

        XCTAssertEqual(
            try archive.keyRegistry().definition(for: key).englishDefaultValue,
            expected
        )
        XCTAssertEqual(Data(expected.utf8).count, fixture.authored.labelUTF8ByteCount)
        XCTAssertTrue(expected.unicodeScalars.contains { $0.value == 0x2192 })

        for locale in fixture.uiLocales {
            let coordinator = try V30P03C03FormTestSupport.coordinator(
                uiLocale: locale,
                formatLocale: "en-US"
            )
            let projection = try coordinator.project(
                release: release,
                fact: fact,
                field: field,
                archive: archive
            )
            XCTAssertEqual(Data(projection.label.utf8), Data(expected.utf8), locale)
            XCTAssertEqual(Data(projection.accessibilityLabel.utf8), Data(expected.utf8), locale)
            XCTAssertEqual(Data(try XCTUnwrap(projection.helpText).utf8), Data(expected.utf8), locale)
            XCTAssertEqual(projection.requirement?.state, .required, locale)
            XCTAssertEqual(projection.choices.map(\.choiceID), fixture.choiceIDsInCanonicalOrder, locale)
            XCTAssertEqual(projection.choices.map(\.label), [expected, expected], locale)
            XCTAssertEqual(try SurveyDefinitionCanonicalCodecV1.encode(release), releaseBytes, locale)
            XCTAssertEqual(try ResponseValueCanonicalCodecV1.encode(response.value), responseBytes, locale)
        }

        let mismatched = try V30P03C03FormTestSupport.release(
            facts: [fact],
            localizationDigest: String(repeating: "f", count: 64),
            fixture: fixture
        )
        XCTAssertThrowsError(try V30P03C03FormTestSupport.coordinator(
            uiLocale: "en", formatLocale: "en-US"
        ).project(release: mismatched, fact: fact, field: field, archive: archive))
    }


    func testArchiveRejectsForgedV30DefaultAndParameterizedKeyWithoutArguments() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let sourceArchive = try V30P03C03FormTestSupport.archive()
        let registry = try V30EnglishCatalogRegistryV1.registry()
        let forgedRegistry = try V30P03C03FormTestSupport.registry(
            replacingEnglishDefaultFor: fixture.authored.key,
            with: "Forged selected-key default"
        )
        let forgedArchive = try V30P03C03FormTestSupport.archive(registry: forgedRegistry)
        let fact = V30P03C03FormTestSupport.choiceFact(fixture: fixture, required: true)
        let field = try V30P03C03FormTestSupport.choiceField(fixture: fixture)
        let forgedRelease = try V30P03C03FormTestSupport.release(
            facts: [fact], archive: forgedArchive, fixture: fixture
        )
        let coordinator = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "en", formatLocale: "en-US"
        )

        XCTAssertNotEqual(
            try forgedRegistry.definition(for: LocalizationKeyV1(fixture.authored.key)).englishDefaultValue,
            try sourceArchive.keyRegistry().definition(for: LocalizationKeyV1(fixture.authored.key)).englishDefaultValue
        )
        V30P03C03FormTestSupport.assertFailure(.sourceCatalogMismatch) {
            try coordinator.project(
                release: forgedRelease,
                fact: fact,
                field: field,
                archive: forgedArchive
            )
        }

        let argumentRegistry = try V30P03C03FormTestSupport.registry(
            replacingArgumentsFor: fixture.authored.key,
            with: [.init(name: "count", shape: .integerPlural)],
            pluralCategories: ["one", "other"]
        )
        let argumentArchive = try V30P03C03FormTestSupport.archive(registry: argumentRegistry)
        let argumentRelease = try V30P03C03FormTestSupport.release(
            facts: [fact], archive: argumentArchive, fixture: fixture
        )
        V30P03C03FormTestSupport.assertFailure(.unsupportedCatalogMessage) {
            try coordinator.project(
                release: argumentRelease,
                fact: fact,
                field: field,
                archive: argumentArchive
            )
        }

        let nfdSource = try V30P03C03FormTestSupport.sourceCatalog(
            replacingEnglishValueFor: "common.done",
            with: "Cafe\u{301}"
        )
        let nfcRegistry = try V30P03C03FormTestSupport.registry(
            replacingEnglishDefaultFor: "common.done",
            with: "Café"
        )
        let nfdArchive = try V30P03C03FormTestSupport.archive(
            sourceCatalog: nfdSource,
            registry: nfcRegistry
        )
        let nfdInstruction = V30P03C03FormTestSupport.fact(
            "fact.nfd",
            payload: .instruction,
            required: false,
            localizationKey: "common.done"
        )
        let nfdRelease = try V30P03C03FormTestSupport.release(
            facts: [nfdInstruction], archive: nfdArchive, fixture: fixture
        )
        V30P03C03FormTestSupport.assertFailure(.sourceCatalogMismatch) {
            try coordinator.project(
                release: nfdRelease,
                fact: nfdInstruction,
                archive: nfdArchive
            )
        }

        let matchingNFDRegistry = try V30P03C03FormTestSupport.registry(
            replacingEnglishDefaultFor: "common.done",
            with: "Cafe\u{301}"
        )
        let exactNFDArchive = try V30P03C03FormTestSupport.archive(
            sourceCatalog: nfdSource,
            registry: matchingNFDRegistry
        )
        let exactNFDRelease = try V30P03C03FormTestSupport.release(
            facts: [nfdInstruction], archive: exactNFDArchive, fixture: fixture
        )
        let exactNFDProjection = try coordinator.project(
            release: exactNFDRelease,
            fact: nfdInstruction,
            archive: exactNFDArchive
        )
        XCTAssertEqual(
            Data(exactNFDProjection.label.utf8),
            Data("Cafe\u{301}".utf8)
        )
    }

    func testResponseRequirementChoiceAndCanonicalValidatorsRemainAuthoritative() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let archive = try V30P03C03FormTestSupport.archive()
        let requiredFact = V30P03C03FormTestSupport.choiceFact(fixture: fixture, required: true)
        let optionalFact = V30P03C03FormTestSupport.choiceFact(
            factID: "fact.optional",
            fixture: fixture,
            required: false
        )
        let requiredField = try V30P03C03FormTestSupport.choiceField(fixture: fixture)
        let optionalField = try V30P03C03FormTestSupport.choiceField(
            factID: optionalFact.factID,
            minimum: 0,
            fixture: fixture
        )
        let optionalRelease = try V30P03C03FormTestSupport.release(
            facts: [optionalFact], archive: archive, fixture: fixture
        )
        let coordinator = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "ko", formatLocale: "en-US"
        )

        XCTAssertEqual(
            try coordinator.project(
                release: optionalRelease,
                fact: optionalFact,
                field: optionalField,
                archive: archive
            ).requirement?.state,
            .optional
        )

        let missing = try BoundResponseValueV1(fieldID: requiredField.fieldID, value: .noValue)
        XCTAssertEqual(
            coordinator.validate(response: missing, against: requiredField).messageKey,
            .missingRequiredResponse
        )
        XCTAssertThrowsError(try ResponseFieldValidatorV1.validate(missing, against: requiredField))

        let invalid = try BoundResponseValueV1(
            fieldID: requiredField.fieldID,
            value: .singleOption("foreign")
        )
        XCTAssertEqual(
            coordinator.validate(response: invalid, against: requiredField).messageKey,
            .invalidSelection
        )
        XCTAssertThrowsError(try ResponseFieldValidatorV1.validate(invalid, against: requiredField))

        let requiredRelease = try V30P03C03FormTestSupport.release(
            facts: [requiredFact], archive: archive, fixture: fixture
        )
        let sameFactOptionalField = try V30P03C03FormTestSupport.choiceField(
            factID: requiredFact.factID,
            minimum: 0,
            fixture: fixture
        )
        XCTAssertThrowsError(try coordinator.project(
            release: requiredRelease,
            fact: requiredFact,
            field: sameFactOptionalField,
            archive: archive
        ))

        let differentChoices = try V30P03C03FormTestSupport.choiceField(
            factID: requiredFact.factID,
            allowedOptionIDs: ["choice.alpha"],
            fixture: fixture
        )
        XCTAssertThrowsError(try coordinator.project(
            release: requiredRelease,
            fact: requiredFact,
            field: differentChoices,
            archive: archive
        ))
    }

    func testInstructionAndRepeatGroupRemainFieldlessAndDoNotEmitRequirementCopy() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let archive = try V30P03C03FormTestSupport.archive()
        let instruction = V30P03C03FormTestSupport.fact(
            "fact.instruction",
            payload: .instruction,
            required: false
        )
        let child = V30P03C03FormTestSupport.fact(
            "fact.child",
            payload: .instruction,
            required: false
        )
        let repeatGroup = V30P03C03FormTestSupport.fact(
            "fact.repeat",
            payload: .repeatableGroup(try .init(
                groupID: "repeat.c03",
                childFactIDs: ["fact.child"],
                minimum: 0,
                maximum: 1
            )),
            required: false
        )
        let release = try V30P03C03FormTestSupport.release(
            facts: [instruction, child, repeatGroup],
            archive: archive,
            fixture: fixture
        )
        let coordinator = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "es", formatLocale: "en-US"
        )

        for fact in [instruction, repeatGroup] {
            let projection = try coordinator.project(release: release, fact: fact, archive: archive)
            XCTAssertNil(projection.requirement)
            XCTAssertTrue(projection.choices.isEmpty)
        }
    }

    func testLocaleFormattingIsIndependentFromUILanguageAndCanonicalValueUnit() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let archive = try V30P03C03FormTestSupport.archive()
        let fact = V30P03C03FormTestSupport.choiceFact(fixture: fixture, required: true)
        let field = try V30P03C03FormTestSupport.choiceField(fixture: fixture)
        let release = try V30P03C03FormTestSupport.release(
            facts: [fact], archive: archive, fixture: fixture
        )
        let enUI = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "en", formatLocale: "en-US"
        )
        let koUI = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "ko", formatLocale: "en-US"
        )
        let formattedLocale = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "en", formatLocale: "es-ES"
        )
        let canonicalDecimal = Decimal(string: fixture.numeric.canonicalText)!
        let formatted = try enUI.formatDecimal(canonicalDecimal)

        let englishProjection = try enUI.project(
            release: release, fact: fact, field: field, archive: archive
        )
        let koreanProjection = try koUI.project(
            release: release, fact: fact, field: field, archive: archive
        )
        let esFormatProjection = try formattedLocale.project(
            release: release, fact: fact, field: field, archive: archive
        )
        XCTAssertEqual(englishProjection.requirement?.text, koreanProjection.requirement?.text)
        XCTAssertEqual(englishProjection.label, koreanProjection.label)
        XCTAssertEqual(formatted, try koUI.formatDecimal(canonicalDecimal))
        XCTAssertEqual(englishProjection.label, esFormatProjection.label)
        XCTAssertEqual(englishProjection.requirement?.text, esFormatProjection.requirement?.text)
        XCTAssertEqual(
            try LocaleFormattingServiceV1(profile: V30P03C03FormTestSupport.profile("en-US"))
                .parseDecimal(formatted),
            canonicalDecimal
        )
        XCTAssertFalse(try enUI.formatLength(Decimal(12), canonicalUnit: .meters).isEmpty)

        let decimalField = try V30P03C03FormTestSupport.decimalField(fixture: fixture)
        let outOfRange = try BoundResponseValueV1(
            fieldID: decimalField.fieldID,
            value: .decimal(try .init(mantissa: 2_000, scale: 2))
        )
        XCTAssertEqual(enUI.validate(response: outOfRange, against: decimalField).messageKey, .invalidNumber)
        XCTAssertThrowsError(try LocaleFormattingServiceV1(
            profile: V30P03C03FormTestSupport.profile("en-US")
        ).parseDecimal(fixture.numeric.unsupportedOrAmbiguousInput))

        let measurementField = try V30P03C03FormTestSupport.measurementField(fixture: fixture)
        let invalidUnit = try BoundResponseValueV1(
            fieldID: measurementField.fieldID,
            value: .measurement(try .init(
                enteredValue: .init(mantissa: 1, scale: 0),
                enteredUnitID: fixture.numeric.wrongUnitID,
                precisionScale: 0,
                uncertaintyCanonical: nil,
                source: .manualEntry,
                captureMethodID: "manual"
            ))
        )
        XCTAssertEqual(enUI.validate(response: invalidUnit, against: measurementField).messageKey, .invalidUnit)
        XCTAssertThrowsError(try ResponseFieldValidatorV1.validate(invalidUnit, against: measurementField))
    }

    func testReleasedVisibilityConditionAndWorkflowGraphRemainCanonical() throws {
        let fixture = try V30P03C03FormTestSupport.loadFixture()
        let archive = try V30P03C03FormTestSupport.archive()
        let gate = V30P03C03FormTestSupport.choiceFact(
            factID: "fact.aaa-gate",
            fixture: fixture,
            required: true
        )
        let condition = SurveyVisibilityExpressionV1.predicate(.init(
            factID: gate.factID,
            expectedValue: .singleOption("choice.alpha")
        ))
        let dependent = V30P03C03FormTestSupport.choiceFact(
            fixture: fixture,
            required: true,
            visibility: condition
        )
        let release = try V30P03C03FormTestSupport.release(
            facts: [gate, dependent], archive: archive, fixture: fixture
        )
        let coordinator = try V30P03C03FormTestSupport.coordinator(
            uiLocale: "en", formatLocale: "en-US"
        )

        XCTAssertTrue(coordinator.validateConditions(in: release).isValid)
        XCTAssertEqual(
            try coordinator.project(release: release, fact: dependent, archive: archive).visibility,
            condition
        )
        XCTAssertNoThrow(try WorkflowGraphValidatorV1.validate(
            V30P03C03FormTestSupport.workflow(fieldID: dependent.factID)
        ))
    }
}

enum V30P03C03FormTestSupport {
    struct Fixture: Decodable {
        struct Message: Decodable {
            let key: String
            let english: String
        }

        struct Authored: Decodable {
            let key: String
            let label: String
            let labelUTF8ByteCount: Int
        }

        struct Numeric: Decodable {
            let canonicalMantissa: Int64
            let canonicalScale: Int
            let canonicalText: String
            let unsupportedOrAmbiguousInput: String
            let allowedUnitID: String
            let wrongUnitID: String
        }

        let schemaVersion: Int
        let cardID: String
        let uiLocales: [String]
        let formSemantics: [Message]
        let authored: Authored
        let choiceIDsInCanonicalOrder: [String]
        let numeric: Numeric
        let packageReleaseID: String
        let workflowSHA256: String
        let factID: String
    }

    static func assertFailure(
        _ expected: LocalizedFormSemanticsFailureV1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? LocalizedFormSemanticsFailureV1,
                expected,
                file: file,
                line: line
            )
        }
    }

    static func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/Forms/localized-form-semantics-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func profile(_ locale: String) throws -> FormattingLocaleProfileV1 {
        try .init(
            localeIdentifier: locale,
            ianaTimeZoneIdentifier: "America/New_York",
            calendar: .gregorian,
            numberingSystem: .latin,
            units: .metric
        )
    }

    static func coordinator(
        uiLocale: String,
        formatLocale: String
    ) throws -> LocalizedFormSemanticsCoordinatorV1 {
        try .init(
            profile: profile(formatLocale),
            bundle: Bundle(for: V30P03C03LocalizedFormSemanticsTests.self),
            locale: Locale(identifier: uiLocale)
        )
    }

    static func archive(
        sourceCatalog: Data? = nil,
        registry: LocalizationKeyRegistryV1? = nil
    ) throws -> V30CatalogReleaseArchiveV1 {
        let source: Data
        if let sourceCatalog {
            source = sourceCatalog
        } else {
            source = try self.sourceCatalog()
        }
        let selectedRegistry: LocalizationKeyRegistryV1
        if let registry {
            selectedRegistry = registry
        } else {
            selectedRegistry = try V30EnglishCatalogRegistryV1.registry()
        }
        let locales = LocalizationLocaleManifestV1.shippingV1()
        return try BundledLocalizationCatalogV1.loadInheritedRelease(
            sourceCatalogBytes: source,
            registryBytes: LocalizationContractCanonicalCodecV1.encode(selectedRegistry),
            localeManifestBytes: LocalizationContractCanonicalCodecV1.encode(locales)
        ).archive
    }

    static func sourceCatalog(
        replacingEnglishValueFor rawKey: String? = nil,
        with replacement: String? = nil
    ) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let original = try Data(contentsOf: root.appendingPathComponent(
            "FieldEvidenceApp/Resources/Localizable.xcstrings"
        ))
        guard let rawKey, let replacement else { return original }
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        var strings = try XCTUnwrap(document["strings"] as? [String: Any])
        var entry = try XCTUnwrap(strings[rawKey] as? [String: Any])
        var localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        var english = try XCTUnwrap(localizations["en"] as? [String: Any])
        var unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
        unit["value"] = replacement
        english["stringUnit"] = unit
        localizations["en"] = english
        entry["localizations"] = localizations
        strings[rawKey] = entry
        document["strings"] = strings
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    static func registry(
        replacingEnglishDefaultFor rawKey: String,
        with replacement: String
    ) throws -> LocalizationKeyRegistryV1 {
        try registry { definition in
            guard definition.key.rawValue == rawKey else { return definition }
            return LocalizationKeyDefinitionV1(
                key: definition.key,
                meaningID: definition.meaningID,
                translatorComment: definition.translatorComment,
                englishDefaultValue: replacement,
                arguments: definition.arguments,
                requiredEnglishPluralCategories: definition.requiredEnglishPluralCategories,
                state: definition.state,
                deprecatedFallbackKey: definition.deprecatedFallbackKey
            )
        }
    }

    static func registry(
        replacingArgumentsFor rawKey: String,
        with arguments: [LocalizationArgumentV1],
        pluralCategories: [String]
    ) throws -> LocalizationKeyRegistryV1 {
        try registry { definition in
            guard definition.key.rawValue == rawKey else { return definition }
            return LocalizationKeyDefinitionV1(
                key: definition.key,
                meaningID: definition.meaningID,
                translatorComment: definition.translatorComment,
                englishDefaultValue: definition.englishDefaultValue,
                arguments: arguments,
                requiredEnglishPluralCategories: pluralCategories,
                state: definition.state,
                deprecatedFallbackKey: definition.deprecatedFallbackKey
            )
        }
    }

    private static func registry(
        transform: (LocalizationKeyDefinitionV1) -> LocalizationKeyDefinitionV1
    ) throws -> LocalizationKeyRegistryV1 {
        let inherited = try V30EnglishCatalogRegistryV1.registry()
        return try LocalizationKeyRegistryV1(definitions: inherited.definitions.map(transform))
    }

    static func fact(
        _ id: String,
        payload: SurveyFactPayloadV1,
        required: Bool,
        visibility: SurveyVisibilityExpressionV1? = nil,
        localizationKey: String = "v30.parts-stock.work-entry-description"
    ) -> FactDefinitionV1 {
        FactDefinitionV1(
            factID: id,
            labelLocalizationKey: localizationKey,
            accessibilityLabelLocalizationKey: localizationKey,
            helpLocalizationKey: localizationKey,
            required: required,
            defaultValue: nil,
            visibility: visibility,
            payload: payload
        )
    }

    static func choiceFact(
        factID: String? = nil,
        fixture: Fixture,
        required: Bool,
        visibility: SurveyVisibilityExpressionV1? = nil
    ) -> FactDefinitionV1 {
        fact(
            factID ?? fixture.factID,
            payload: .singleChoice([
                .init(
                    choiceID: "choice.alpha",
                    labelLocalizationKey: "v30.parts-stock.work-entry-description",
                    accessibilityLabelLocalizationKey: "v30.parts-stock.work-entry-description"
                ),
                .init(
                    choiceID: "choice.omega",
                    labelLocalizationKey: "v30.parts-stock.work-entry-description",
                    accessibilityLabelLocalizationKey: "v30.parts-stock.work-entry-description"
                ),
            ]),
            required: required,
            visibility: visibility
        )
    }

    static func choiceField(
        factID: String? = nil,
        minimum: Int = 1,
        allowedOptionIDs: [String]? = nil,
        fixture: Fixture
    ) throws -> ResponseFieldDefinitionV1 {
        try .init(
            fieldID: factID ?? fixture.factID,
            packageReleaseID: fixture.packageReleaseID,
            workflowSHA256: fixture.workflowSHA256,
            valueKind: .singleOption,
            cardinality: .init(minimum: minimum, maximum: 1),
            allowedOptionIDs: allowedOptionIDs ?? fixture.choiceIDsInCanonicalOrder
        )
    }

    static func decimalField(fixture: Fixture) throws -> ResponseFieldDefinitionV1 {
        try .init(
            fieldID: "fact.decimal",
            packageReleaseID: fixture.packageReleaseID,
            workflowSHA256: fixture.workflowSHA256,
            valueKind: .decimal,
            cardinality: .init(minimum: 0, maximum: 1),
            minimumNumericValue: .init(mantissa: 0, scale: 0),
            maximumNumericValue: .init(mantissa: 1_500, scale: 2)
        )
    }

    static func measurementField(fixture: Fixture) throws -> ResponseFieldDefinitionV1 {
        try .init(
            fieldID: "fact.measurement",
            packageReleaseID: fixture.packageReleaseID,
            workflowSHA256: fixture.workflowSHA256,
            valueKind: .measurement,
            cardinality: .init(minimum: 0, maximum: 1),
            measurementDimension: .length,
            allowedUnitIDs: [fixture.numeric.allowedUnitID],
            maximumPrecisionScale: 2
        )
    }

    static func release(
        facts: [FactDefinitionV1],
        archive: V30CatalogReleaseArchiveV1? = nil,
        localizationDigest: String? = nil,
        fixture: Fixture
    ) throws -> SurveyDefinitionReleaseV1 {
        let workspace = WorkspaceID(
            rawValue: UUID(uuidString: "c0330000-0000-4000-8000-000000000001")!
        )
        let reference = try LocalActorReferenceV1(
            actorReferenceID: UUID(uuidString: "c0330000-0000-4000-8000-000000000002")!,
            workspaceID: workspace,
            displayName: "C03 author"
        )
        let actor = try ActorSnapshotV1(
            snapshotID: UUID(uuidString: "c0330000-0000-4000-8000-000000000003")!,
            workspaceID: workspace,
            actor: reference,
            responsibility: .recordedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: Date(timeIntervalSince1970: 1_800_033_000)
        )
        let digest: String
        if let localizationDigest {
            digest = localizationDigest
        } else {
            digest = try XCTUnwrap(archive?.descriptor.legacyRelease.releaseSHA256)
        }

        return try .init(
            releaseID: UUID(uuidString: "c0330000-0000-4000-8000-000000000004")!,
            workspaceID: workspace,
            definitionID: UUID(uuidString: "c0330000-0000-4000-8000-000000000005")!,
            activityKind: .survey,
            ownerPackageID: "c03.form.package",
            sections: [.init(
                sectionID: "section.c03",
                titleLocalizationKey: "common.done",
                accessibilityHeadingLocalizationKey: "common.done",
                ordinal: 0,
                facts: facts.sorted { $0.factID < $1.factID }
            )],
            completionRules: [.init(
                ruleID: "complete",
                expression: .allRequiredVisibleFactsAnswered,
                failureLocalizationKey: "common.done"
            )],
            claimsProfile: .init(
                profileID: "claims.c03",
                activityKind: .survey,
                allowedClaimKeys: [],
                forbiddenClaimKeys: ["approval"],
                limitationLocalizationKeys: ["common.done"]
            ),
            reportProjection: .init(
                projectionID: "report.c03",
                projectionVersion: "1",
                headingLocalizationKey: "common.done",
                emptyValueLocalizationKey: "common.done",
                sectionIDs: ["section.c03"],
                includedFactIDs: facts.map(\.factID).sorted()
            ),
            localizationReleaseSHA256: digest,
            revision: 1,
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "c0330000-0000-4000-8000-000000000006")!
            ),
            authoredBy: actor,
            authoredAt: Date(timeIntervalSince1970: 1_800_033_001)
        )
    }

    static func workflow(fieldID: String) throws -> WorkflowDefinitionV1 {
        try .init(
            workflowID: "c03.workflow",
            entryNodeID: "node.fact",
            declaredFieldIDs: [fieldID],
            nodes: [
                try .init(
                    nodeID: "node.fact",
                    kind: .fact,
                    localizationKey: "common.done",
                    fieldID: fieldID,
                    outgoingNodeIDs: ["node.done"]
                ),
                try .init(
                    nodeID: "node.done",
                    kind: .terminal,
                    localizationKey: "common.done",
                    outgoingNodeIDs: []
                ),
            ]
        )
    }
}
