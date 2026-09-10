import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P02C01EnglishCatalogNormalizationTests: XCTestCase {
    func testActualCatalogPreservesEveryInheritedEntryAndDeclaresEveryAddition() throws {
        let source = try sourceCatalog()
        let strings = try catalogStrings(source)
        let audit = try auditObject()
        let inherited = try XCTUnwrap(audit["inheritedEntries"] as? [String: Any])
        XCTAssertFalse(inherited.isEmpty)
        for (key, expected) in inherited {
            let actualEntry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let expectedEntry = try XCTUnwrap(expected as? [String: Any], key)
            XCTAssertEqual(actualEntry as NSDictionary, expectedEntry as NSDictionary, key)
        }
        let additions = V30EnglishCatalogRegistryV1.messages
        XCTAssertFalse(additions.isEmpty)
        XCTAssertEqual(Set(additions.map(\.key)).count, additions.count)
        XCTAssertEqual(Set(strings.keys), Set(inherited.keys).union(additions.map(\.key)))
        let registry = try V30EnglishCatalogRegistryV1.registry()
        try registry.validateSuccessor(of: BundledLocalizationCatalogV1.registry())
        try V30EnglishCatalogRegistryV1.validateSourceCatalog(source)
        for message in additions {
            let entry = try XCTUnwrap(strings[message.key] as? [String: Any], message.key)
            try message.validateCatalogEntry(entry)
        }
    }

    func testLegacyPublicationAndAdditiveAuditRetainTheirRegistryBoundaries() throws {
        let source = try sourceCatalog()
        let legacy = try LegacyLocalizationAccessibilityAllowlistV1(entries: [])
        let inherited = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: source, legacy: legacy
        )
        guard case let .complete(oldKeys, _, oldLegacy, _, oldReceipt) = inherited else {
            return XCTFail("The legacy selection must produce one complete declaration")
        }
        XCTAssertEqual(oldKeys, try BundledLocalizationCatalogV1.registry())
        XCTAssertEqual(oldLegacy, legacy)
        let newKeys = try V30EnglishCatalogRegistryV1.registry()
        try newKeys.validateSuccessor(of: oldKeys)
        let locales = try LocalizationContractCanonicalCodecV1.encode(
            LocalizationLocaleManifestV1.shippingV1()
        )
        XCTAssertEqual(oldReceipt.release, try LocalizationCatalogReleaseV1.make(
            sourceCatalog: source,
            registry: LocalizationContractCanonicalCodecV1.encode(oldKeys), localeManifest: locales
        ))
        XCTAssertFalse(oldReceipt.persistentWriteOccurred)
        // The additive registry is an English-source audit. A content-bearing
        // V30 release/candidate binding remains owned by P04-C07.
        XCTAssertFalse(V30EnglishCatalogRegistryV1.finalLocaleAcceptanceClaimed)
        XCTAssertFalse(BundledLocalizationCatalogV1.runtimeDownloadsAllowed)
    }

    func testBothPluralBranchesRejectTypeCardinalityAndCategoryTampering() throws {
        let message = try XCTUnwrap(
            V30EnglishCatalogRegistryV1.messages.first { $0.englishPluralOne != nil }
        )
        let source = try sourceCatalog()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        let strings = try catalogStrings(source)
        for category in ["one", "other"] {
            for replacement in ["%@ wrong type", "%lld plus %lld extra", "missing count"] {
                var changedStrings = strings
                var entry = try XCTUnwrap(strings[message.key] as? [String: Any])
                var localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
                var english = try XCTUnwrap(localizations["en"] as? [String: Any])
                var variations = try XCTUnwrap(english["variations"] as? [String: Any])
                var plural = try XCTUnwrap(variations["plural"] as? [String: Any])
                plural[category] = ["stringUnit": ["state": "translated", "value": replacement]]
                variations["plural"] = plural
                english["variations"] = variations
                localizations["en"] = english
                entry["localizations"] = localizations
                changedStrings[message.key] = entry
                var changedRoot = root
                changedRoot["strings"] = changedStrings
                let bytes = try JSONSerialization.data(withJSONObject: changedRoot)
                XCTAssertThrowsError(try V30EnglishCatalogRegistryV1.validateSourceCatalog(bytes))
                XCTAssertThrowsError(try BundledLocalizationCatalogV1.publish(
                    sourceCatalogBytes: bytes,
                    legacy: LegacyLocalizationAccessibilityAllowlistV1(entries: [])
                ))
            }
        }
        var entry = try XCTUnwrap(strings[message.key] as? [String: Any])
        entry["comment"] = ""
        XCTAssertThrowsError(try message.validateCatalogEntry(entry))
        entry = try XCTUnwrap(strings[message.key] as? [String: Any])
        entry["localizations"] = ["en": ["stringUnit": ["state": "translated", "value": message.englishDefault]]]
        XCTAssertThrowsError(try message.validateCatalogEntry(entry))
    }

    func testNamedArgumentsRejectWrongTypesMissingValuesMixedPositionsAndPrivacy() throws {
        let arguments = [
            V30EnglishArgumentV1(name: "name", kind: .text, privacy: .authoredSource, occurrences: 1),
            V30EnglishArgumentV1(name: "count", kind: .integer, privacy: .aggregateCount, occurrences: 1),
        ]
        try contract("%@ has %lld recorded checks", arguments: arguments).validate()
        try contract("%2$lld checks are recorded for %1$@", arguments: arguments).validate()
        for invalid in ["%@ has %@ checks", "%@ has checks", "%@ %lld %lld", "%2$lld %@", "%3$lld %1$@", "%n"] {
            XCTAssertThrowsError(try contract(invalid, arguments: arguments).validate(), invalid)
        }
        let plural = V30EnglishArgumentV1(
            name: "count", kind: .pluralCount, privacy: .authoredSource, occurrences: 1
        )
        XCTAssertThrowsError(try contract("%lld checks", arguments: [plural], one: "%lld check").validate())
        XCTAssertThrowsError(try contract("%lld checks", arguments: [
            .init(name: "count", kind: .pluralCount, privacy: .aggregateCount, occurrences: 1),
        ]).validate())
        XCTAssertThrowsError(try V30EnglishMessageContractV1(
            key: "This is mutable English text", englishDefault: "Test",
            translatorComment: comment, arguments: [], englishPluralOne: nil
        ).validate())
        XCTAssertThrowsError(try V30EnglishMessageContractV1(
            key: "v30.test.message", englishDefault: "Test",
            translatorComment: "No context", arguments: [], englishPluralOne: nil
        ).validate())
    }

    func testCompiledEnglishPluralsAndIndependentNumericPresentation() {
        let english = Locale(identifier: "en-US")
        let frenchNumbers = Locale(identifier: "fr-FR")
        for (count, expected) in [(0, "0 photos"), (1, "1 photo"), (2, "2 photos")] {
            XCTAssertEqual(BundledLocalizationCatalogV1.v30BackupExportPhotoCount(
                count: count, languageLocale: english, formattingLocale: frenchNumbers
            ), expected)
        }
        let formatter = NumberFormatter()
        formatter.locale = frenchNumbers
        formatter.numberStyle = .decimal
        let expectedNumber = formatter.string(from: 1_234)!
        XCTAssertEqual(BundledLocalizationCatalogV1.v30BackupExportPhotoCount(
            count: 1_234, languageLocale: english, formattingLocale: frenchNumbers
        ), expectedNumber + " photos")

        for unresolved in 0...2 {
            for resolved in 0...2 {
                let unresolvedNoun = unresolved == 1 ? "finding" : "findings"
                let resolvedNoun = resolved == 1 ? "finding" : "findings"
                XCTAssertEqual(BundledLocalizationCatalogV1.v30PunchReviewFindingCounts(
                    unresolvedCount: unresolved, resolvedCount: resolved,
                    languageLocale: english, formattingLocale: english
                ), "\(unresolved) unresolved \(unresolvedNoun), \(resolved) resolved \(resolvedNoun).")
            }
        }
        XCTAssertEqual(BundledLocalizationCatalogV1.v30AssetImportValidatedPreview(
            rowCount: 1, commandCount: 2, atomicity: "ATOMIC",
            languageLocale: english, formattingLocale: english
        ), "Validated 1 synthetic row, 2 commands, ATOMIC")
    }

    func testTypedNumericRunsPreserveAuthoredTextReorderingAndRepeatedBindings() {
        let authored = "1,234 %2$lld e\u{301} \u{202E}source 📷"
        func marked(_ value: String, index: Int) -> AttributedString {
            var text = AttributedString(value)
            text.replacementIndex = index
            return text
        }
        var message = marked("9", index: 2)
        message += AttributedString(" / ")
        message += marked(authored, index: 1)
        message += AttributedString(" / ")
        message += marked("9", index: 2)
        XCTAssertEqual(BundledLocalizationCatalogV1.v30ApplyingNumericPresentation(
            message, replacements: [2: "٩"]
        ), "٩ / " + authored + " / ٩")

        let english = Locale(identifier: "en-US")
        let formatter = NumberFormatter()
        formatter.locale = english
        formatter.numberStyle = .decimal
        let exactLargeCount = formatter.string(from: NSNumber(value: Int64.max))!
        XCTAssertEqual(BundledLocalizationCatalogV1.v30AssetImportSourceByteCount(
            byteCount: Int64.max, sha256: authored,
            languageLocale: english, formattingLocale: english
        ), exactLargeCount + " bytes · SHA-256 " + authored)
    }

    func testEverySubstitutionRejectsWrongBindingMissingBranchAndUnexpectedFormat() throws {
        let strings = try catalogStrings(sourceCatalog())
        let messages = V30EnglishCatalogRegistryV1.messages.filter { !$0.substitutions.isEmpty }
        XCTAssertFalse(messages.isEmpty)
        for message in messages {
            let entry = try XCTUnwrap(strings[message.key] as? [String: Any])
            try message.validateCatalogEntry(entry)
            for substitution in message.substitutions {
                for mutation in ["wrongIndex", "wrongType", "missingOne", "missingOther", "wrongLeaf", "extraCategory"] {
                    var changed = entry
                    var locales = try XCTUnwrap(entry["localizations"] as? [String: Any])
                    var en = try XCTUnwrap(locales["en"] as? [String: Any])
                    var substitutions = try XCTUnwrap(en["substitutions"] as? [String: Any])
                    var leaf = try XCTUnwrap(substitutions[substitution.name] as? [String: Any])
                    var variations = try XCTUnwrap(leaf["variations"] as? [String: Any])
                    var plural = try XCTUnwrap(variations["plural"] as? [String: Any])
                    switch mutation {
                    case "wrongIndex": leaf["argNum"] = message.arguments.count + 1
                    case "wrongType": leaf["formatSpecifier"] = "@"
                    case "missingOne": plural.removeValue(forKey: "one")
                    case "missingOther": plural.removeValue(forKey: "other")
                    case "wrongLeaf": plural["one"] = ["stringUnit": ["state": "translated", "value": "%arg %@"]]
                    default: plural["few"] = plural["other"]
                    }
                    variations["plural"] = plural
                    leaf["variations"] = variations
                    substitutions[substitution.name] = leaf
                    en["substitutions"] = substitutions
                    locales["en"] = en
                    changed["localizations"] = locales
                    XCTAssertThrowsError(try message.validateCatalogEntry(changed), message.key + ": " + mutation)
                }
            }
        }
        let count = V30EnglishArgumentV1(name: "count", kind: .pluralCount, privacy: .aggregateCount, occurrences: 1)
        for index in [Int.min, 0, 2] {
            XCTAssertThrowsError(try V30EnglishMessageContractV1(
                key: "v30.test.invalid_substitution", englishDefault: "%1$lld checks",
                translatorComment: comment, arguments: [count], englishPluralOne: nil,
                englishSubstitutionFormat: "%#@count@", substitutions: [
                    .init(name: "count", argumentIndex: index, englishOne: "%arg check", englishOther: "%arg checks"),
                ]
            ).validate())
        }
    }

    func testLiteralDispositionAuditNamesExactFilesAndKeepsDeferredPermissionGapVisible() throws {
        let audit = try auditObject()
        XCTAssertEqual(audit["cardID"] as? String, "V30-P02-C01")
        XCTAssertEqual(audit["finalCredit"] as? Bool, false)
        let files = try XCTUnwrap(audit["sourceFiles"] as? [[String: Any]])
        XCTAssertEqual(files.count, 47)
        XCTAssertEqual(Set(files.compactMap { $0["path"] as? String }).count, files.count)
        let allowedDispositions: Set<String> = [
            "DNT_CONFIRMATION_TOKEN", "EXISTING_TYPED_CATALOG", "FORMAT_LITERAL",
            "MACHINE_IDENTIFIER", "SYMBOL_OR_FORMAT",
        ]
        var literalIDs = Set<String>()
        var literalCount = 0
        for file in files {
            let path = try XCTUnwrap(file["path"] as? String)
            XCTAssertTrue(path.hasPrefix("FieldEvidenceApp/"))
            let bytes = try Data(contentsOf: root.appendingPathComponent(path))
            let normalized = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                KernelCanonicalHashV1.sha256(Data(normalized.utf8)),
                file["normalizedSourceSHA256"] as? String, path
            )
            let dispositions = try XCTUnwrap(file["literalDispositions"] as? [[String: Any]], path)
            XCTAssertEqual(dispositions.count, file["literalCount"] as? Int, path)
            for literal in dispositions {
                let id = try XCTUnwrap(literal["id"] as? String)
                XCTAssertTrue(literalIDs.insert(id).inserted, id)
                XCTAssertTrue(allowedDispositions.contains(try XCTUnwrap(literal["disposition"] as? String)), id)
                XCTAssertFalse((literal["reason"] as? String ?? "").isEmpty, id)
                let rawToken = try XCTUnwrap(literal["rawToken"] as? String)
                XCTAssertTrue(normalized.contains(rawToken), id)
                XCTAssertEqual(KernelCanonicalHashV1.sha256(Data(rawToken.utf8)), literal["rawTokenSha256"] as? String, id)
            }
            literalCount += dispositions.count
        }
        let summary = try XCTUnwrap(audit["summary"] as? [String: Any])
        XCTAssertEqual(literalCount, summary["remainingLiteralCount"] as? Int)
        XCTAssertEqual(summary["unresolvedCurrentFileLiterals"] as? Int, 0)
        let deferred = try XCTUnwrap(audit["deferredSurfaces"] as? [[String: Any]])
        let permission = try XCTUnwrap(deferred.first { $0["surface"] as? String == "SYSTEM_PERMISSION_RESOURCES" })
        XCTAssertEqual(permission["ownerCard"] as? String, "V30-P03-C09")
        XCTAssertEqual(permission["normalizedByThisCard"] as? Bool, false)
        XCTAssertFalse((permission["reason"] as? String ?? "").isEmpty)
    }

    private func contract(
        _ text: String, arguments: [V30EnglishArgumentV1], one: String? = nil
    ) -> V30EnglishMessageContractV1 {
        V30EnglishMessageContractV1(
            key: "v30.test.complete_message", englishDefault: text,
            translatorComment: comment, arguments: arguments, englishPluralOne: one
        )
    }

    private var comment: String {
        "Screen: test review. Meaning: recorded checks for a supplied name. Role: complete status. Arguments: name is authored text; count is an aggregate. Plural/select: none. Accessibility: spoken status. Screenshot: test review status; no screenshot acceptance claimed."
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sourceCatalog() throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings"))
    }

    private func catalogStrings(_ bytes: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        return try XCTUnwrap(object["strings"] as? [String: Any])
    }

    private func auditObject() throws -> [String: Any] {
        let url = root.appendingPathComponent("FieldEvidenceAppTests/Fixtures/V30/EnglishCatalog/english-catalog-audit-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
