import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P01C06SystemLanguageResolutionTests: XCTestCase {
    func testObservedEnglishResourceDoesNotHideFallbackEvidence() {
        let result = SystemLanguageResolverV1().resolve(
            observedLocalizationIdentifiers: ["en"],
            preferredLanguageIdentifiers: ["es-MX"],
            declaredLocalizationIdentifiers: ["en"]
        )
        XCTAssertEqual(result.effectiveLanguage, .english)
        XCTAssertEqual(result.provenance, .englishFallback)
        XCTAssertEqual(result.fallbackDiagnostic?.usedEnglishFallback, true)
    }

    func testSystemSelectedNonEnglishResourceIsNotLabeledEnglishFallback() {
        let result = SystemLanguageResolverV1().resolve(
            observedLocalizationIdentifiers: ["es"],
            preferredLanguageIdentifiers: ["en"],
            declaredLocalizationIdentifiers: ["en", "es"]
        )
        XCTAssertEqual(result.effectiveLanguage.rawValue, "es")
        XCTAssertEqual(result.provenance, .systemSelectedResource)
        XCTAssertNil(result.fallbackDiagnostic)
    }

    func testInjectedSystemLanguageCasesRespectExactBaseAndEnglishFallback() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 8)
        let resolver = SystemLanguageResolverV1()

        for item in cases {
            let resolution = resolver.resolve(
                preferredLanguageIdentifiers: try XCTUnwrap(item["preferences"] as? [String]),
                declaredLocalizationIdentifiers: try XCTUnwrap(item["declaredResources"] as? [String])
            )
            XCTAssertEqual(resolution.effectiveLanguage.rawValue, item["expectedLanguage"] as? String)
            XCTAssertEqual(resolution.resourceIdentifier, item["expectedResource"] as? String)
            XCTAssertEqual(
                resolution.provenance.rawValue,
                item["expectedProvenance"] as? String
            )
        }
    }

    func testFallbackDiagnosticsArePrivacySafeAndDoNotReturnRawKeys() throws {
        let resolver = SystemLanguageResolverV1()
        let privatePreference = "es-MX-x-private-user"
        let resolution = resolver.resolve(
            preferredLanguageIdentifiers: [privatePreference],
            declaredLocalizationIdentifiers: ["en"]
        )

        XCTAssertEqual(resolution.effectiveLanguage, .english)
        XCTAssertEqual(resolution.resourceIdentifier, "en")
        XCTAssertEqual(resolution.provenance, .englishFallback)
        XCTAssertEqual(resolution.fallbackDiagnostic?.usedEnglishFallback, true)
        XCTAssertEqual(resolution.fallbackDiagnostic?.provenance, .englishFallback)

        let encoded = try JSONEncoder().encode(resolution)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedText.contains(privatePreference))
        XCTAssertFalse(encodedText.contains("common.action.done"))
    }

    func testExactResolutionHasNoFallbackDiagnostic() {
        let resolution = SystemLanguageResolverV1().resolve(
            preferredLanguageIdentifiers: ["es"],
            declaredLocalizationIdentifiers: ["en", "es"]
        )
        XCTAssertEqual(resolution.provenance, .exactDeclaredResource)
        XCTAssertNil(resolution.fallbackDiagnostic)
    }

    func testFallbackDiagnosticPersistsOnlyPrivacySafeFieldsAndCanBeCleared() throws {
        let suiteName = "V30-P01-C06-fallback-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let adapter = PreferencesAdapterV1(defaults: defaults)
        let diagnostic = EffectiveLanguageFallbackDiagnosticV1(provenance: .englishFallback)

        try adapter.recordGlobalizationFallback(diagnostic)
        XCTAssertEqual(try adapter.readGlobalizationFallback(), diagnostic)

        let storedData = try XCTUnwrap(
            defaults.dictionaryRepresentation().values.compactMap { $0 as? Data }.first
        )
        let storedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: storedData) as? [String: Any]
        )
        XCTAssertEqual(Set(storedObject.keys), ["provenance", "usedEnglishFallback"])
        XCTAssertEqual(storedObject["provenance"] as? String, "ENGLISH_FALLBACK")
        XCTAssertEqual(storedObject["usedEnglishFallback"] as? Bool, true)

        let storedText = try XCTUnwrap(String(data: storedData, encoding: .utf8))
        XCTAssertFalse(storedText.contains("es-MX-x-private-user"))
        XCTAssertFalse(storedText.contains("common.action.done"))
        XCTAssertFalse(storedText.localizedCaseInsensitiveContains("customer"))

        try adapter.recordGlobalizationFallback(nil)
        XCTAssertNil(try adapter.readGlobalizationFallback())
        XCTAssertTrue(defaults.dictionaryRepresentation().values.compactMap { $0 as? Data }.isEmpty)
    }

    private func loadFixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/LanguageResolution/system-language-cases-v1.json")
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(fixture["schema"] as? String, "V30SystemLanguageResolutionCasesV1")
        XCTAssertEqual(fixture["cardID"] as? String, "V30-P01-C06")
        let provisional = try XCTUnwrap(fixture["provisional"] as? [String: Any])
        XCTAssertEqual(provisional["finalCredit"] as? Bool, false)
        XCTAssertEqual(provisional["nativeEvidence"] as? String, "NOT_EXECUTED_NO_NATIVE_CREDIT")
        return fixture
    }
}
