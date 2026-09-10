import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P01C08CatalogReleaseIntegrityTests: XCTestCase {
    func testInheritedCatalogLoadsOfflineWithUnchangedLegacyReceipt() throws {
        let input = try inputs()
        let expected = try LocalizationCatalogReleaseV1.make(
            sourceCatalog: input.source, registry: input.keys, localeManifest: input.locales
        )
        let loaded = try BundledLocalizationCatalogV1.loadInheritedRelease(
            sourceCatalogBytes: input.source, registryBytes: input.keys,
            localeManifestBytes: input.locales
        )
        XCTAssertEqual(loaded.archive.descriptor.legacyRelease, expected)
        XCTAssertEqual(loaded.archive.sourceCatalog, input.source)
        XCTAssertEqual(loaded.archive.registry, input.keys)
        XCTAssertEqual(loaded.archive.localeManifest, input.locales)
        XCTAssertEqual(loaded.archive.descriptor.qualification, .inheritedEnglish)
        XCTAssertEqual(loaded.effectiveLanguage, .english)
        XCTAssertEqual(loaded.fallback, .exact)
        XCTAssertFalse(loaded.finalAcceptanceClaimed)
        XCTAssertNil(loaded.archive.descriptor.candidateHead)
        XCTAssertNil(loaded.archive.descriptor.reviewerReference)
        XCTAssertFalse(BundledLocalizationCatalogV1.runtimeDownloadsAllowed)
    }

    func testDescriptorAndAllPayloadsRejectTampering() throws {
        let original = try archive()
        let encoded = try LocalizationContractCanonicalCodecV1.encode(original.descriptor)
        let decoded = try JSONDecoder().decode(V30CatalogReleaseDescriptorV1.self, from: encoded)
        try decoded.validate()
        XCTAssertEqual(decoded, original.descriptor)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["maximumReaderSchemaVersion"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(
            V30CatalogReleaseDescriptorV1.self, from: JSONSerialization.data(withJSONObject: object)
        ))
        for part in 0..<3 {
            var data = [original.sourceCatalog, original.registry, original.localeManifest]
            data[part].append(32)
            XCTAssertThrowsError(try V30CatalogReleaseArchiveV1(
                descriptor: original.descriptor, sourceCatalog: data[0],
                registry: data[1], localeManifest: data[2]
            ))
        }
    }

    func testUpgradeRollbackAndHistoricalLookupKeepExactOldBytes() throws {
        let first = try archive()
        let second = try archive(revision: 2, previous: first.descriptor, revisedText: true)
        // The archive bundle need not be ordered. References establish lineage.
        var store = try LocalizationCatalogReleaseStoreV1(archives: [second, first, first])
        try store.activate(releaseID: first.descriptor.releaseID, readerVersion: 1)
        try store.activate(releaseID: second.descriptor.releaseID, readerVersion: 1)
        XCTAssertEqual(try resolved(store).archive, second)
        XCTAssertEqual(try store.historical(releaseID: first.descriptor.releaseID, readerVersion: 1), first)
        XCTAssertNotEqual(first.sourceCatalog, second.sourceCatalog)
        XCTAssertNotEqual(first.descriptor.releaseID, second.descriptor.releaseID)
        XCTAssertThrowsError(try store.activate(releaseID: first.descriptor.releaseID, readerVersion: 1))
        XCTAssertEqual(try resolved(store).archive, second)
        try store.rollback(to: first.descriptor.releaseID, readerVersion: 1)
        XCTAssertEqual(try resolved(store).archive, first)
        XCTAssertEqual(try store.historical(releaseID: second.descriptor.releaseID, readerVersion: 1), second)
    }

    func testMissingHistoryConflictingRevisionAndIncompatibleReaderFailClosed() throws {
        let first = try archive()
        let second = try archive(revision: 2, previous: first.descriptor, revisedText: true)
        XCTAssertThrowsError(try LocalizationCatalogReleaseStoreV1(archives: [second]))
        let fork = try archive(revision: 3, previous: first.descriptor)
        XCTAssertThrowsError(try LocalizationCatalogReleaseStoreV1(archives: [first, second, fork])) {
            XCTAssertEqual($0 as? V30CatalogStoreFailureV1, .incompatibleTransition)
        }
        let conflicting = try archive(revisedText: true)
        XCTAssertThrowsError(try LocalizationCatalogReleaseStoreV1(archives: [first, conflicting]))
        var store = try LocalizationCatalogReleaseStoreV1(archives: [first, second])
        try store.activate(releaseID: first.descriptor.releaseID, readerVersion: 1)
        XCTAssertThrowsError(try store.activate(releaseID: second.descriptor.releaseID, readerVersion: 99))
        XCTAssertEqual(try resolved(store).archive, first)
        let missing = try V30CatalogReleaseIDV1(digest: String(repeating: "a", count: 64), revision: 1)
        XCTAssertThrowsError(try store.historical(releaseID: missing, readerVersion: 1))
        XCTAssertThrowsError(try store.rollback(to: missing, readerVersion: 1))
        XCTAssertEqual(try resolved(store).archive, first)
    }

    func testFallbackIsExplicitAndHistoricalReadsNeverSubstituteEnglish() throws {
        let original = try archive()
        var store = try LocalizationCatalogReleaseStoreV1(archives: [original])
        try store.activate(releaseID: original.descriptor.releaseID, readerVersion: 1)
        let missingLanguage = try AppLanguageTagV1(XCTUnwrap(try fixture()["requestedMissingLanguage"] as? String))
        XCTAssertThrowsError(try store.resolve(
            family: original.descriptor.family, requestedLanguage: missingLanguage,
            readerVersion: 1, allowsEnglishFallback: false
        ))
        let fallback = try store.resolve(
            family: original.descriptor.family, requestedLanguage: missingLanguage,
            readerVersion: 1, allowsEnglishFallback: true
        )
        XCTAssertEqual(fallback.requestedLanguage, missingLanguage)
        XCTAssertEqual(fallback.effectiveLanguage, .english)
        XCTAssertEqual(fallback.fallback, .englishRequestedLanguageUnavailable)
        XCTAssertEqual(fallback.archive, original)
        XCTAssertFalse(fallback.finalAcceptanceClaimed)
        XCTAssertThrowsError(try store.resolve(
            family: original.descriptor.family, requestedLanguage: missingLanguage,
            readerVersion: 99, allowsEnglishFallback: true
        ))
    }

    func testChangedKeyMeaningAndPrematureReviewerBindingCannotBeAccepted() throws {
        let first = try archive()
        let second = try archive(revision: 2, previous: first.descriptor)
        let keys = try first.keyRegistry()
        var definitions = keys.definitions
        let old = definitions.removeFirst()
        definitions.append(LocalizationKeyDefinitionV1(
            key: old.key, meaningID: "different.meaning", translatorComment: old.translatorComment,
            englishDefaultValue: old.englishDefaultValue, arguments: old.arguments,
            requiredEnglishPluralCategories: old.requiredEnglishPluralCategories,
            state: old.state, deprecatedFallbackKey: old.deprecatedFallbackKey
        ))
        let changed = try LocalizationKeyRegistryV1(definitions: definitions)
        XCTAssertThrowsError(try second.descriptor.validateSuccessor(
            of: first.descriptor, keyRegistry: changed, previousKeyRegistry: keys
        ))
        XCTAssertThrowsError(try V30CatalogReleaseDescriptorV1(
            family: first.descriptor.family, revision: 1, language: .english,
            minimumReaderSchemaVersion: 1, maximumReaderSchemaVersion: 1, sourceSchemaVersion: 1,
            sourceRevision: "fixture-source-1", termbaseRevision: "fixture-terms-1",
            qualification: .provisionalFixture, legacyRelease: first.descriptor.legacyRelease,
            reviewerReference: "not-approved"
        ))
    }

    func testUnsupportedSchemaAndRecomputedMalformedContentStillFail() throws {
        let input = try inputs()
        let badSource = Data(#"{"version":"1.0","sourceLanguage":"en","strings":{}}"#.utf8)
        let legacy = try LocalizationCatalogReleaseV1.make(
            sourceCatalog: badSource, registry: input.keys, localeManifest: input.locales
        )
        XCTAssertThrowsError(try V30CatalogReleaseArchiveV1(
            descriptor: legacy.v30InheritedDescriptor(), sourceCatalog: badSource,
            registry: input.keys, localeManifest: input.locales
        ))
        let first = try archive()
        XCTAssertThrowsError(try V30CatalogReleaseDescriptorV1(
            schemaVersion: 2, family: first.descriptor.family, revision: 1, language: .english,
            minimumReaderSchemaVersion: 1, maximumReaderSchemaVersion: 1, sourceSchemaVersion: 1,
            sourceRevision: "fixture", termbaseRevision: "fixture",
            qualification: .provisionalFixture, legacyRelease: first.descriptor.legacyRelease
        ))
        let futureSource = try V30CatalogReleaseDescriptorV1(
            family: first.descriptor.family, revision: 1, language: .english,
            minimumReaderSchemaVersion: 1, maximumReaderSchemaVersion: 1, sourceSchemaVersion: 2,
            sourceRevision: "fixture", termbaseRevision: "fixture",
            qualification: .provisionalFixture, legacyRelease: first.descriptor.legacyRelease
        )
        XCTAssertThrowsError(try V30CatalogReleaseArchiveV1(
            descriptor: futureSource, sourceCatalog: first.sourceCatalog,
            registry: first.registry, localeManifest: first.localeManifest
        ))
    }

    private func resolved(_ store: LocalizationCatalogReleaseStoreV1) throws -> V30CatalogResolutionV1 {
        try store.resolve(
            family: XCTUnwrap(try fixture()["family"] as? String), requestedLanguage: .english,
            readerVersion: 1, allowsEnglishFallback: false
        )
    }

    private func archive(
        revision: Int = 1, previous: V30CatalogReleaseDescriptorV1? = nil, revisedText: Bool = false
    ) throws -> V30CatalogReleaseArchiveV1 {
        let input = try inputs(revisedText: revisedText)
        let legacy = try LocalizationCatalogReleaseV1.make(
            sourceCatalog: input.source, registry: input.keys, localeManifest: input.locales
        )
        let descriptor = try V30CatalogReleaseDescriptorV1(
            family: XCTUnwrap(try fixture()["family"] as? String), revision: revision, language: .english,
            minimumReaderSchemaVersion: 1, maximumReaderSchemaVersion: 1, sourceSchemaVersion: 1,
            sourceRevision: "fixture-source-\(revision)", termbaseRevision: "fixture-terms-1",
            qualification: .provisionalFixture, legacyRelease: legacy,
            supersedesReleaseID: previous?.releaseID
        )
        return try V30CatalogReleaseArchiveV1(
            descriptor: descriptor, sourceCatalog: input.source,
            registry: input.keys, localeManifest: input.locales
        )
    }

    private func inputs(revisedText: Bool = false) throws -> (source: Data, keys: Data, locales: Data) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var source = try Data(contentsOf: root.appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings"))
        var registry = try BundledLocalizationCatalogV1.registry()
        if revisedText {
            let replacement = try XCTUnwrap(try fixture()["replacementDoneText"] as? String)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
            var strings = try XCTUnwrap(object["strings"] as? [String: Any])
            var entry = try XCTUnwrap(strings["common.done"] as? [String: Any])
            var localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            var english = try XCTUnwrap(localizations["en"] as? [String: Any])
            var unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            unit["value"] = replacement
            english["stringUnit"] = unit
            localizations["en"] = english
            entry["localizations"] = localizations
            strings["common.done"] = entry
            object["strings"] = strings
            source = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            registry = try LocalizationKeyRegistryV1(definitions: registry.definitions.map { old in
                guard old.key.rawValue == "common.done" else { return old }
                return LocalizationKeyDefinitionV1(
                    key: old.key, meaningID: old.meaningID, translatorComment: old.translatorComment,
                    englishDefaultValue: replacement, arguments: old.arguments,
                    requiredEnglishPluralCategories: old.requiredEnglishPluralCategories,
                    state: old.state, deprecatedFallbackKey: old.deprecatedFallbackKey
                )
            })
        }
        return (
            source, try LocalizationContractCanonicalCodecV1.encode(registry),
            try LocalizationContractCanonicalCodecV1.encode(LocalizationLocaleManifestV1.shippingV1())
        )
    }

    private func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/CatalogRelease/catalog-release-cases-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
