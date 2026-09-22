import Foundation
import PDFKit
import XCTest
@testable import FieldEvidenceApp

final class V30P03C08GlobalizedCatalogReplayTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let reportID = UUID(uuidString: "29000000-0000-0000-0000-000000000001")!

    func testStoredUnicodeSourceAndPDFStayByteExactWithUnavailableResources() throws {
        for item in try fixture().cases {
            let source = Data(item.text.utf8)
            let result = try render(source)
            let before = result.pdf.data
            let observed = try observe(source: source, pdf: before)
            XCTAssertEqual(observed.sourceSHA256, KernelCanonicalHashV1.sha256(source))
            XCTAssertEqual(observed.outputSHA256, result.receipt.outputSHA256)
            XCTAssertEqual(observed.metadata?.fonts, result.receipt.fonts)
            XCTAssertEqual(observed.metadata?.language, result.receipt.language)
            XCTAssertTrue(observed.sourceBindingVerified)
            XCTAssertTrue(observed.limitations.contains(.historicalFontUnavailable))
            XCTAssertTrue(observed.limitations.contains(.rendererEnvironmentUnavailable))
            XCTAssertTrue(observed.limitations.contains(.documentCatalogReferenceNotRecorded))
            XCTAssertFalse(observed.regenerationVerified)
            XCTAssertEqual(result.pdf.data, before)
            XCTAssertEqual(try observe(source: source, pdf: before), observed)
        }
    }

    func testExactFontAndRendererObservationsStillDoNotClaimRegeneration() throws {
        let source = Data("AR-29 / 客户原文".utf8)
        let result = try render(source)
        let resources = GlobalizedReplayResourcesV1(fonts: result.receipt.fonts,
            rendererID: result.receipt.rendererID, rendererVersion: result.receipt.rendererVersion,
            operatingSystemBuild: result.receipt.operatingSystemBuild)
        let observed = try observe(source: source, pdf: result.pdf.data, resources: resources)
        XCTAssertFalse(observed.limitations.contains(.historicalFontUnavailable))
        XCTAssertFalse(observed.limitations.contains(.rendererEnvironmentUnavailable))
        XCTAssertTrue(observed.limitations.contains(.regenerationNotVerified))
        XCTAssertFalse(observed.regenerationVerified)
    }

    func testReboundSourceOrCapturedTimeCannotBorrowHistoricalBinding() throws {
        let source = Data("Original source".utf8)
        let pdf = try render(source).pdf.data
        let rebound = try observe(source: Data("Changed source".utf8), pdf: pdf)
        XCTAssertFalse(rebound.sourceBindingVerified)
        XCTAssertTrue(rebound.limitations.contains(.historicalSourceBindingUnavailable))
        XCTAssertEqual(rebound.metadata?.sourceSHA256, KernelCanonicalHashV1.sha256(source))
        let differentTime = try GlobalizedCatalogReplayAdapterV1.artifact(reportID: reportID,
            source: source, sourceSHA256: KernelCanonicalHashV1.sha256(source),
            createdAt: createdAt.addingTimeInterval(1), pdf: pdf,
            outputSHA256: KernelCanonicalHashV1.sha256(pdf))
        XCTAssertFalse(differentTime.sourceBindingVerified)
        XCTAssertThrowsError(try GlobalizedCatalogReplayAdapterV1.artifact(reportID: reportID,
            source: source, sourceSHA256: KernelCanonicalHashV1.sha256(source), createdAt: createdAt,
            pdf: pdf + Data([0]), outputSHA256: KernelCanonicalHashV1.sha256(pdf)))
        XCTAssertThrowsError(try GlobalizedCatalogReplayAdapterV1.artifact(reportID: reportID,
            source: source + Data([0]), sourceSHA256: KernelCanonicalHashV1.sha256(source),
            createdAt: createdAt, pdf: pdf, outputSHA256: KernelCanonicalHashV1.sha256(pdf)))
    }

    func testMalformedCurrentMetadataIsNotDowngradedToLegacy() throws {
        let source = Data("Saved document".utf8)
        let pdf = try render(source).pdf.data
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        var attributes = document.documentAttributes ?? [:]
        attributes[.keywordsAttribute] = GlobalizedDocumentPDFMetadataV1.prefix + "broken"
        document.documentAttributes = attributes
        XCTAssertThrowsError(try observe(source: source, pdf: XCTUnwrap(document.dataRepresentation())))
    }

    func testLegacyPDFRetainsBytesAndExplicitlyUnknownReplayProvenance() throws {
        let source = Data("Legacy snapshot".utf8)
        let document = try XCTUnwrap(PDFDocument(data: render(source).pdf.data))
        var attributes = document.documentAttributes ?? [:]
        attributes[.creatorAttribute] = "historical-renderer"
        attributes.removeValue(forKey: .keywordsAttribute)
        document.documentAttributes = attributes
        let legacy = try XCTUnwrap(document.dataRepresentation())
        let observation = try observe(source: source, pdf: legacy)
        XCTAssertNil(observation.metadata)
        XCTAssertEqual(observation.limitations, [.legacyArtifactHasNoReplayProvenance, .regenerationNotVerified])
        XCTAssertEqual(observation.outputSHA256, KernelCanonicalHashV1.sha256(legacy))
    }

    func testHistoricalCatalogUsesExactDigestAndExplicitReaderCompatibility() throws {
        let archive = try inheritedArchive()
        let digest = archive.descriptor.legacyRelease.releaseSHA256
        let exact = try GlobalizedCatalogReplayAdapterV1.catalog(ownerID: "survey:fixture",
            digest: digest, resources: .init(catalogs: [archive]))
        XCTAssertEqual(exact.resolvedReleaseID, archive.descriptor.releaseID)
        XCTAssertNil(exact.limitation)
        let incompatible = try GlobalizedCatalogReplayAdapterV1.catalog(ownerID: "survey:fixture",
            digest: digest, resources: .init(catalogs: [archive], readerVersion: Int.max))
        XCTAssertEqual(incompatible.limitation, .historicalCatalogReaderIncompatible)
        let missing = try GlobalizedCatalogReplayAdapterV1.catalog(ownerID: "survey:fixture",
            digest: String(repeating: "a", count: 64), resources: .init(catalogs: [archive]))
        XCTAssertEqual(missing.limitation, .historicalCatalogUnavailable)
        XCTAssertNil(missing.resolvedReleaseID)
        XCTAssertEqual(try GlobalizedCatalogReplayAdapterV1.catalog(ownerID: "survey:fixture",
            digest: digest, resources: .init()).limitation, .historicalCatalogUnavailable)
    }

    func testSearchCompletionRequiresRestoredGenerationAndCanonicalRevision() throws {
        let source = try SearchSourceRevisionV1(workspaceID: UUID(), generationID: UUID(), commitRevision: 29)
        let inventory = GlobalizedCatalogReplayInventoryV1(recordsSHA256: String(repeating: "a", count: 64),
            catalogs: [], artifacts: [], unrenderedReportIDs: [])
        let restored = GlobalizedRestoreReplayObservationV1(inventory: inventory,
            searchSource: source, searchRebuildRequired: true)
        let completed = SearchIndexRebuildResultV1(disposition: .absentBuild, source: source,
            indexedRecordCount: 1, resumedFromCheckpoint: false)
        XCTAssertFalse(try completed.completingGlobalizedRestore(restored).searchRebuildRequired)
        for stale in [try SearchSourceRevisionV1(workspaceID: source.workspaceID, generationID: UUID(), commitRevision: 29),
                      try SearchSourceRevisionV1(workspaceID: source.workspaceID, generationID: source.generationID, commitRevision: 28)] {
            XCTAssertThrowsError(try SearchIndexRebuildResultV1(disposition: .current, source: stale,
                indexedRecordCount: 1, resumedFromCheckpoint: false).completingGlobalizedRestore(restored))
        }
        XCTAssertTrue(restored.searchRebuildRequired)
        let legacy = GlobalizedRestoreReplayObservationV1(inventory: inventory,
            searchSource: nil, searchRebuildRequired: true)
        XCTAssertTrue(legacy.searchRevisionUnavailable)
        XCTAssertTrue(legacy.searchRebuildRequired)
        XCTAssertThrowsError(try completed.completingGlobalizedRestore(legacy))
    }

    private func observe(source: Data, pdf: Data, resources: GlobalizedReplayResourcesV1 = .init()) throws -> GlobalizedArtifactReplayObservationV1 {
        try GlobalizedCatalogReplayAdapterV1.artifact(reportID: reportID, source: source,
            sourceSHA256: KernelCanonicalHashV1.sha256(source), createdAt: createdAt,
            pdf: pdf, outputSHA256: KernelCanonicalHashV1.sha256(pdf), resources: resources)
    }

    private func render(_ source: Data) throws -> GlobalizedDocumentRenderResultV1 {
        let request = try GlobalizedDocumentRenderRequestV1(
            language: .init(requestedLanguage: .english, effectiveLanguage: .english, fallback: .exact),
            formatting: .init(localeIdentifier: "en-US", ianaTimeZoneIdentifier: "UTC",
                calendar: .gregorian, numberingSystem: .latin, units: .metric), paperSize: .usLetter)
        return try GlobalizedAccessibleDocumentRendererV1().render(
            elements: [try .init(semanticID: "report.body", role: .paragraph, text: String(decoding: source, as: UTF8.self))],
            sourceSHA256: KernelCanonicalHashV1.sha256(source), sourceCreatedAt: createdAt, request: request)
    }

    private func inheritedArchive() throws -> V30CatalogReleaseArchiveV1 {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try BundledLocalizationCatalogV1.loadInheritedRelease(
            sourceCatalogBytes: Data(contentsOf: root.appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")),
            registryBytes: LocalizationContractCanonicalCodecV1.encode(BundledLocalizationCatalogV1.registry()),
            localeManifestBytes: LocalizationContractCanonicalCodecV1.encode(LocalizationLocaleManifestV1.shippingV1())).archive
    }

    private struct Fixture: Decodable {
        struct Case: Decodable { let language: String; let text: String }
        let cases: [Case]
    }
    private func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/Backup/globalized-catalog-replay-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}
