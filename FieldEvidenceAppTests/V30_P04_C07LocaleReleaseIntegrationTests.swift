import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Authored on Windows; execution requires the later authorized native route.
final class V30_P04_C07LocaleReleaseIntegrationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }
    private func object(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(path)) as? [String: Any])
    }
    private func strings(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(object(path)["strings"] as? [String: Any])
    }
    private func simpleCohort(source: String, target: String) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: V30ProvisionalCatalogIntegrationV1.languages.map { language in
            (language, ["stringUnit": ["state": language == "en" ? "translated" : "needs_review",
                                       "value": language == "en" ? source : target]] as Any)
        })
    }

    func testSixLocaleCatalogsAreClosedAndDraftLanesAreUnchanged() throws {
        let appPath = "FieldEvidenceApp/Resources/Localizable.xcstrings"
        let infoPath = "FieldEvidenceApp/InfoPlist.xcstrings"
        try V30ProvisionalCatalogIntegrationV1.validateCatalog(data(appPath), permissionCatalog: false)
        try V30ProvisionalCatalogIntegrationV1.validateCatalog(data(infoPath), permissionCatalog: true)
        let app = try strings(appPath), info = try strings(infoPath)
        XCTAssertEqual(app.count, 3_209); XCTAssertEqual(info.count, 3)
        let merged = app.merging(info) { _, _ in XCTFail("Duplicate table key"); return NSNull() }
        for language in V30ProvisionalCatalogIntegrationV1.languages.dropFirst() {
            var seen = Set<String>()
            for lane in ["app", "report", "accessibility"] {
                let catalog = try strings("FieldEvidenceApp/Resources/Globalization/\(language).\(lane).json")
                XCTAssertTrue(seen.isDisjoint(with: catalog.keys)); seen.formUnion(catalog.keys)
                for (key, raw) in catalog {
                    let expected = try XCTUnwrap((raw as? [String: Any])?["localizations"] as? [String: Any])
                    let actual = try XCTUnwrap((merged[key] as? [String: Any])?["localizations"] as? [String: Any])
                    XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual[language]!, options: .sortedKeys),
                                   try JSONSerialization.data(withJSONObject: expected[language]!, options: .sortedKeys), key)
                    XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual["en"]!, options: .sortedKeys),
                                   try JSONSerialization.data(withJSONObject: expected["en"]!, options: .sortedKeys), key)
                }
            }
            XCTAssertEqual(seen, Set(merged.keys))
        }
    }

    func testPartialExtraMixedLocaleAndOrphanKeysFailClosed() throws {
        var rootObject = try object("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let original = try XCTUnwrap(rootObject["strings"] as? [String: Any])
        let key = try XCTUnwrap(original.keys.sorted().first)
        for mode in ["missing", "extra", "englishOnly", "orphan"] {
            var changed = original
            var entry = try XCTUnwrap(changed[key] as? [String: Any])
            var localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            if mode == "missing" { localizations.removeValue(forKey: "ko") }
            if mode == "extra" { localizations["fr"] = localizations["es"] }
            if mode == "englishOnly" { localizations = ["en": localizations["en"]!] }
            entry["localizations"] = localizations; changed[key] = entry
            if mode == "orphan" { changed["v30.unknown.integration-key"] = changed.removeValue(forKey: key) }
            rootObject["strings"] = changed
            XCTAssertThrowsError(try V30ProvisionalCatalogIntegrationV1.validateCatalog(
                JSONSerialization.data(withJSONObject: rootObject), permissionCatalog: false), mode)
        }
    }

    func testArgumentOrderTypeMultiplicityAndDraftStateArePreserved() throws {
        try V30ProvisionalCatalogIntegrationV1.validateLocalizations(simpleCohort(source: "%@ %lld", target: "%2$lld %1$@"))
        for target in ["%lld %@", "%1$@ %2$@", "%1$@", "%1$@ %2$lld %2$lld", "%@ %2$lld", "%q", ""] {
            XCTAssertThrowsError(try V30ProvisionalCatalogIntegrationV1.validateLocalizations(
                simpleCohort(source: "%@ %lld", target: target)), target)
        }
        var approved = simpleCohort(source: "Label", target: "Label")
        approved["es"] = ["stringUnit": ["state": "translated", "value": "Label"]]
        XCTAssertThrowsError(try V30ProvisionalCatalogIntegrationV1.validateLocalizations(approved))
    }

    func testPluralAndNamedSubstitutionMetadataCannotDrift() throws {
        let app = try strings("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let entry = try XCTUnwrap(app.values.compactMap { $0 as? [String: Any] }.first { entry in
            (((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])?["substitutions"] != nil)
        })
        let original = try XCTUnwrap(entry["localizations"] as? [String: Any])
        try V30ProvisionalCatalogIntegrationV1.validateLocalizations(original)
        for mode in ["argument", "category", "host"] {
            var cohort = original
            var korean = try XCTUnwrap(cohort["ko"] as? [String: Any])
            var substitutions = try XCTUnwrap(korean["substitutions"] as? [String: Any])
            let name = try XCTUnwrap(substitutions.keys.sorted().first)
            var substitution = try XCTUnwrap(substitutions[name] as? [String: Any])
            if mode == "argument" { substitution["argNum"] = 12 }
            if mode == "category" {
                var variations = try XCTUnwrap(substitution["variations"] as? [String: Any])
                var plural = try XCTUnwrap(variations["plural"] as? [String: Any])
                plural["one"] = plural["other"]; variations["plural"] = plural; substitution["variations"] = variations
            }
            substitutions[name] = substitution; korean["substitutions"] = substitutions
            if mode == "host" { korean["stringUnit"] = ["state": "needs_review", "value": "Missing argument"] }
            cohort["ko"] = korean
            XCTAssertThrowsError(try V30ProvisionalCatalogIntegrationV1.validateLocalizations(cohort), mode)
        }
    }

    func testBoundReleaseCatalogBytesAndNoQualificationPromotion() throws {
        let release = try object("docs/design/v30/translation/V30ProvisionalLocalizationCatalogReleaseV1.json")
        var payload = try XCTUnwrap(release["binding"] as? [String: Any])
        let decode: ([String: Any]) throws -> V30ProvisionalLocaleReleaseBindingV1 = { object in
            try JSONDecoder().decode(V30ProvisionalLocaleReleaseBindingV1.self,
                                     from: JSONSerialization.data(withJSONObject: object))
        }
        let binding = try decode(payload)
        let app = try data("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let info = try data("FieldEvidenceApp/InfoPlist.xcstrings")
        try binding.validateCatalogs(app: app, permissions: info)
        XCTAssertThrowsError(try binding.validateCatalogs(app: app + Data([32]), permissions: info))
        for field in ["nativeCredit", "professionalReviewCredit", "finalAcceptance", "releaseCredit"] {
            payload[field] = true
            XCTAssertThrowsError(try decode(payload).validate(), field)
            payload[field] = false
        }
        payload["languages"] = ["en", "es"]
        XCTAssertThrowsError(try decode(payload).validate())
        XCTAssertEqual(LocalizationLocaleManifestV1.shippingV1().shippingRuntimeLanguages, ["en"])
    }

    func testCompiledBundleStaticLabelsAndEnglishFallback() throws {
        let bundle = Bundle.main
        let key = "common.done"
        let entry = try XCTUnwrap(try strings("FieldEvidenceApp/Resources/Localizable.xcstrings")[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        for language in V30ProvisionalCatalogIntegrationV1.languages {
            XCTAssertNotNil(bundle.path(forResource: language, ofType: "lproj"), language)
            let branch = try XCTUnwrap(localizations[language] as? [String: Any])
            let unit = try XCTUnwrap(branch["stringUnit"] as? [String: Any])
            XCTAssertEqual(BundledLocalizationCatalogV1.localizedStatic(key: key, english: "Done", language: language, bundle: bundle),
                           unit["value"] as? String)
        }
        XCTAssertEqual(BundledLocalizationCatalogV1.localizedStatic(key: "v30.missing.test-only", english: "Fallback", language: "ko", bundle: bundle), "Fallback")
        XCTAssertEqual(BundledLocalizationCatalogV1.localizedStatic(key: key, english: "Done", language: "fr", bundle: bundle), "Done")
    }

    func testInheritedSourceDefectsRemainExplicitAndBlockFinalAcceptance() throws {
        let matrix = try object("docs/design/v30/verification/V30P04C07LocaleIntegrationMatrixV1.json")
        XCTAssertEqual(matrix["finalAcceptance"] as? Bool, false)
        let defects = try XCTUnwrap(matrix["sourceDefects"] as? [[String: Any]])
        XCTAssertEqual(Set(defects.compactMap { $0["key"] as? String }), Set(V30ProvisionalCatalogIntegrationV1.inheritedSourceDefectKeys))
        XCTAssertTrue(defects.allSatisfy { $0["finalAcceptanceBlocked"] as? Bool == true })
    }
}
