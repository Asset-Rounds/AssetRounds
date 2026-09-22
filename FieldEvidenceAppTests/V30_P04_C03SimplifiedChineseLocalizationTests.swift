import Foundation
import XCTest
import PDFKit
@testable import FieldEvidenceApp

/// Locale-exclusive draft resources. Native execution and professional review
/// remain separate gates; loading these files does not activate a shipping locale.
final class V30_P04_C03SimplifiedChineseLocalizationTests: XCTestCase {
    func testAllSimplifiedChineseLanesPreserveEnglishKeysAndTypedResourceStructure() throws {
        let fixture = try load("FieldEvidenceAppTests/Fixtures/V30/Locales/zh-Hans.json")
        let expected = try XCTUnwrap(fixture["laneCounts"] as? [String: Int])
        let source = try load("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let english = try XCTUnwrap(source["strings"] as? [String: [String: Any]])
        var allKeys = Set<String>()
        for lane in ["app", "report", "accessibility"] {
            let catalog = try load("FieldEvidenceApp/Resources/Globalization/zh-Hans.\(lane).json")
            XCTAssertEqual(catalog["locale"] as? String, "zh-Hans")
            XCTAssertEqual(catalog["status"] as? String, "DRAFT_NONSHIPPING")
            XCTAssertEqual(catalog["machineAssisted"] as? Bool, true)
            let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
            XCTAssertEqual(strings.count, expected[lane])
            for (key, entry) in strings {
                XCTAssertTrue(allKeys.insert(key).inserted, "Duplicate lane key: \(key)")
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
                XCTAssertEqual(Set(localizations.keys), Set(["en", "zh-Hans"]))
                let en = try XCTUnwrap(localizations["en"])
                let es = try XCTUnwrap(localizations["zh-Hans"])
                try assertParallel(en, es, key)
                if let baseline = english[key]?["localizations"] as? [String: Any],
                   let baselineEnglish = baseline["en"] as? [String: Any] {
                    XCTAssertTrue(NSDictionary(dictionary: en).isEqual(to: baselineEnglish), key)
                }
            }
        }
        XCTAssertEqual(allKeys.count, fixture["sourceCount"] as? Int)
        XCTAssertTrue(Set(english.keys).isSubset(of: allKeys))
    }

    func testSimplifiedChineseRegionalPreferencesResolveToTheSameBaseResource() throws {
        for profile in ["zh-Hans-US", "zh-Hans-CN"] {
            let resolution = SystemLanguageResolverV1().resolve(
                preferredLanguageIdentifiers: [profile], declaredLocalizationIdentifiers: ["en", "zh-Hans"])
            XCTAssertEqual(resolution.effectiveLanguage.rawValue, "zh-Hans")
            XCTAssertEqual(resolution.resourceIdentifier, "zh-Hans")
            XCTAssertEqual(resolution.provenance, .baseLanguageResource)
            let fallback = SystemLanguageResolverV1().resolve(
                preferredLanguageIdentifiers: [profile], declaredLocalizationIdentifiers: ["en"])
            XCTAssertEqual(fallback.effectiveLanguage, .english)
            XCTAssertEqual(fallback.provenance, .englishFallback)
        }
        let otherScript = SystemLanguageResolverV1().resolve(
            preferredLanguageIdentifiers: ["zh-Hant-US"],
            declaredLocalizationIdentifiers: ["en", "zh-Hans"])
        XCTAssertEqual(otherScript.effectiveLanguage, .english)
        XCTAssertEqual(otherScript.provenance, .englishFallback)
    }

    func testSimplifiedChineseProfilesRoundTripFormattingWithoutChangingCanonicalValues() throws {
        let canonicalDate = try LocaleGregorianDateV1(year: 2026, month: 9, day: 22)
        let time = try LocaleWallTimeV1(hour: 14, minute: 5, second: 9)
        let amount = try XCTUnwrap(Decimal(string: "12345.625", locale: Locale(identifier: "en_US_POSIX")))
        for profile in ["zh-Hans-US", "zh-Hans-CN"] {
            let formatting = try FormattingLocaleProfileV1(localeIdentifier: profile,
                ianaTimeZoneIdentifier: "America/New_York", calendar: .gregorian,
                numberingSystem: .latin, units: .usCustomary)
            let service = try LocaleFormattingServiceV1(profile: formatting)
            XCTAssertEqual(try service.parseDecimal(service.formatDecimal(amount)), amount)
            XCTAssertEqual(try service.parseDisplayedWallTime(service.displayWallTime(time)), time)
            XCTAssertFalse(service.displayGregorianDate(canonicalDate).isEmpty)
            XCTAssertEqual(canonicalDate.canonicalString, "2026-09-22")
            XCTAssertEqual(try service.preservedPhone("+1 212 555 0100"), "+1 212 555 0100")
            let address = ["123 Example St", "Synthetic City, NY 10001"]
            XCTAssertEqual(try service.preservedAddressLines(address), address)
        }
    }

    @MainActor
    func testSimplifiedChineseCriticalCopyKeepsConfirmationTokenAndPermissionPurpose() throws {
        let strings = try catalogStrings("accessibility")
        let erase = try direct(strings, "v30.critical.erase-confirmation")
        XCTAssertEqual(String(format: erase, locale: Locale(identifier: "zh-Hans-US"), EraseAllService.requiredConfirmation),
                       "输入 ERASE 以确认。")
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"] {
            let value = try direct(strings, key)
            XCTAssertFalse(value.isEmpty)
            XCTAssertTrue(value.contains("iPhone"))
        }
        let denied = try direct(strings, "v30.critical.failure.permission-denied")
        XCTAssertTrue(denied.contains("拒绝"))
        XCTAssertTrue(denied.contains("替代"))
        XCTAssertFalse(LocalizedSyncStatePresentationV1.remoteSyncUnavailable.permitsSuccessAnnouncement)
    }

    func testSimplifiedChineseReviewBundleKeepsDraftAndStorefrontBoundaries() throws {
        let bundle = try load("docs/design/v30/locales/zh-Hans/V30P04C03ReviewPacketV1.json")
        XCTAssertEqual(bundle["status"] as? String, "DRAFT_NONSHIPPING")
        XCTAssertEqual(bundle["linguisticAcceptance"] as? Bool, false)
        let packet = try XCTUnwrap(bundle["reviewPacket"] as? [String: Any])
        XCTAssertEqual(packet["status"] as? String, "DRAFT_NONSHIPPING")
        XCTAssertEqual(packet["machineAssisted"] as? Bool, true)
        XCTAssertTrue(packet["candidateTuple"] is NSNull)
        XCTAssertTrue(packet["receipt"] is NSNull)
        let metadata = try XCTUnwrap(bundle["metadataDraft"] as? [String: Any])
        XCTAssertEqual(metadata["appStoreLanguage"] as? String, "Chinese (Simplified)")
        XCTAssertEqual(metadata["storefront"] as? String, "US")
        XCTAssertEqual(metadata["publicationAuthorized"] as? Bool, false)
    }

    func testChineseAuthoredInputAndDerivedSearchPreserveSourceAndStableIdentity() throws {
        let fixture = try load("FieldEvidenceAppTests/Fixtures/V30/Locales/zh-Hans.json")
        let qualification = try XCTUnwrap(fixture["cjkQualification"] as? [String: Any])
        let cases = try XCTUnwrap(qualification["inputCases"] as? [[String: String]])
        for item in cases {
            let text = try XCTUnwrap(item["text"])
            let bytes = Data(text.utf8)
            let restored = try UnicodeEvidenceSafetyV1.validatedUTF8(bytes)
            XCTAssertEqual(Data(restored.utf8), bytes)
            try UnicodeEvidenceSafetyV1.requireExactSource(before: text, after: restored)
            let encoded = try JSONEncoder().encode(text)
            XCTAssertEqual(Data(try JSONDecoder().decode(String.self, from: encoded).utf8), bytes)
        }
        let search = try XCTUnwrap(qualification["search"] as? [String: Any])
        let source = try XCTUnwrap(search["source"] as? String)
        let normalized = try GlobalizedSearchNormalizationServiceV1.normalizeProjectionText(source)
        XCTAssertEqual(normalized.normalizedText, source)
        XCTAssertEqual(normalized.cjkRunCount, 1)
        XCTAssertEqual(normalized.cjkChunkCount, 1)
        XCTAssertEqual(normalized.tokens, [source])
        let query = try XCTUnwrap(search["query"] as? String)
        let nonMatch = try XCTUnwrap(search["nonMatchingQuery"] as? String)
        XCTAssertEqual(try GlobalizedSearchNormalizationServiceV1.normalizeQuery(query).tokens, [query])
        XCTAssertTrue(normalized.normalizedText.contains(query))
        XCTAssertFalse(normalized.normalizedText.contains(nonMatch))
        XCTAssertFalse(source.contains(" "))
        let stableIDs = try XCTUnwrap(search["stableIDs"] as? [String])
        XCTAssertTrue(GlobalizedSearchNormalizationServiceV1.displayPrecedes(
            lhsDisplay: source, lhsStableID: stableIDs[0], lhsKind: .asset,
            rhsDisplay: source, rhsStableID: stableIDs[1], rhsKind: .asset,
            localeIdentifier: "zh-Hans-US"))
        XCTAssertFalse(GlobalizedSearchNormalizationServiceV1.displayPrecedes(
            lhsDisplay: source, lhsStableID: stableIDs[1], lhsKind: .asset,
            rhsDisplay: source, rhsStableID: stableIDs[0], rhsKind: .asset,
            localeIdentifier: "zh-Hans-US"))
        // Exact input/storage checks do not stand in for real keyboard marked text.
        let pending = try XCTUnwrap(qualification["pendingManualChecks"] as? [[String: Any]])
        XCTAssertTrue(pending.allSatisfy { $0["status"] as? String == "NOT_EXECUTED" })
    }

    func testChineseBodyShapesPaginatesAndExtractsWithEnglishChromeBoundary() throws {
        let fixture = try load("FieldEvidenceAppTests/Fixtures/V30/Locales/zh-Hans.json")
        let qualification = try XCTUnwrap(fixture["cjkQualification"] as? [String: Any])
        let layout = try XCTUnwrap(qualification["layout"] as? [String: Any])
        let paragraph = try XCTUnwrap(layout["paragraph"] as? String)
        let repeatCount = try XCTUnwrap(layout["repeatCount"] as? Int)
        let body = String(repeating: paragraph + "\n", count: repeatCount)
        let source = Data(body.utf8)
        let elements = [try GlobalizedDocumentElementV1(
            semanticID: "zh-hans.authored-body", role: .paragraph, text: body)]
        for paper in [LocalePaperSizeV1.usLetter, .a4] {
            let formatting = try FormattingLocaleProfileV1(localeIdentifier: "zh-Hans-US",
                ianaTimeZoneIdentifier: "America/New_York", calendar: .gregorian,
                numberingSystem: .latin, units: .usCustomary)
            // Chinese authored content exercises shaping; Chinese report chrome
            // awaits P04-C07 integration and exact-candidate qualification.
            let request = try GlobalizedDocumentRenderRequestV1(
                language: .init(requestedLanguage: .english, effectiveLanguage: .english, fallback: .exact),
                formatting: formatting, paperSize: paper)
            let result = try GlobalizedAccessibleDocumentRendererV1().render(
                elements: elements, sourceSHA256: KernelCanonicalHashV1.sha256(source),
                sourceCreatedAt: Date(timeIntervalSince1970: 1_800_000_000), request: request)
            let document = try XCTUnwrap(PDFDocument(data: result.pdf.data))
            XCTAssertGreaterThanOrEqual(document.pageCount, 2)
            let extracted = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            XCTAssertTrue(extracted.contains(paragraph))
            XCTAssertFalse(extracted.contains("?"))
            XCTAssertTrue(try GlobalizedAccessibleDocumentRendererV1.readLogicalText(from: result.pdf.data).contains(body))
            XCTAssertEqual(result.receipt.orderedSemanticIDs, ["zh-hans.authored-body"])
            XCTAssertEqual(result.receipt.language.effectiveLanguage, .english)
            XCTAssertTrue(result.receipt.pendingExternalQualification)
            XCTAssertTrue(result.receipt.nativeFontEmbeddingObserved)
            for font in result.receipt.fonts where font.embedding == .outlineSubset {
                XCTAssertEqual(font.os2FsType & 0x0302, 0)
            }
            for item in result.pdf.inspection.pages.flatMap({ $0 }) {
                XCTAssertTrue(result.pdf.inspection.contentRect.insetBy(dx: -0.01, dy: -0.01).contains(item.rect))
            }
            try result.receipt.validate()
        }
    }

    private func assertParallel(_ english: [String: Any], _ chinese: [String: Any], _ key: String) throws {
        if key.hasSuffix(".plural") {
            XCTAssertEqual(Set(chinese.keys), Set(["other"]), key)
            let enOther = try XCTUnwrap(english["other"] as? [String: Any])
            let targetOther = try XCTUnwrap(chinese["other"] as? [String: Any])
            try assertParallel(enOther, targetOther, key + ".other")
            return
        }
        XCTAssertEqual(Set(english.keys), Set(chinese.keys), key)
        for (field, value) in english {
            if field == "stringUnit" {
                let en = try XCTUnwrap(value as? [String: String])
                let es = try XCTUnwrap(chinese[field] as? [String: String])
                let source = try XCTUnwrap(en["value"])
                let target = try XCTUnwrap(es["value"])
                XCTAssertEqual(es["state"], "needs_review", key)
                XCTAssertFalse(target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                XCTAssertFalse(target.contains("\u{FFFD}"), key)
                XCTAssertEqual(try tokens(source), try tokens(target), key)
            } else if let en = value as? [String: Any] {
                let chineseChild = try XCTUnwrap(chinese[field] as? [String: Any])
                try assertParallel(en, chineseChild, key + "." + field)
            } else {
                XCTAssertTrue((value as? NSObject)?.isEqual(chinese[field]) == true, key + "." + field)
            }
        }
    }

    private func tokens(_ value: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:@|lld|llu|ld|lu|d|u|f)|%#@[A-Za-z_][A-Za-z0-9_]*@|%arg|%%"#)
        let text = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range) }.sorted()
    }

    private func catalogStrings(_ lane: String) throws -> [String: [String: Any]] {
        try XCTUnwrap(load("FieldEvidenceApp/Resources/Globalization/zh-Hans.\(lane).json")["strings"] as? [String: [String: Any]])
    }

    private func direct(_ strings: [String: [String: Any]], _ key: String) throws -> String {
        let localizations = try XCTUnwrap(strings[key]?["localizations"] as? [String: [String: Any]])
        let unit = try XCTUnwrap(localizations["zh-Hans"]?["stringUnit"] as? [String: String])
        return try XCTUnwrap(unit["value"])
    }

    private func load(_ relative: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(relative))) as? [String: Any])
    }
}
