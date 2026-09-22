import Foundation
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V30P03C06SharePrintLabelTests: XCTestCase {
    func testSixLanguageFixturesPreserveAuthoredUTF8AndExactAttachment() async throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.cardID, "V30-P03-C06")
        XCTAssertEqual(fixture.languages, ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"])
        let language = try ReportLanguageControlPolicyV1.resolve(requested: .english)
        for tag in fixture.languages {
            let surfaces = GlobalizedSharePrintLabelSurfacesV1(appLanguage: try .init(tag))
            for item in fixture.authored {
                XCTAssertEqual(item.text.utf8.count, item.utf8ByteCount)
                let bytes = Data(item.text.utf8)
                let delivery = makeDelivery(bytes: bytes, title: item.text, documentLanguage: language)
                let payload = ReportSharePayload(delivery: delivery, surfaces: surfaces)
                XCTAssertTrue(payload.presentation.subject.contains(item.text))
                XCTAssertTrue(Data(payload.presentation.body.utf8).starts(with: bytes))
                XCTAssertEqual(payload.itemProvider.suggestedName, delivery.filename)
                XCTAssertEqual(payload.itemProvider.registeredTypeIdentifiers, [UTType.pdf.identifier])
                let loaded: Data = try await withCheckedThrowingContinuation { continuation in
                    payload.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                    }
                }
                XCTAssertEqual(loaded, bytes)
                XCTAssertEqual(KernelCanonicalHashV1.sha256(loaded), delivery.pdfSHA256)
                XCTAssertEqual(delivery.documentLanguage, language)
            }
        }
    }

    func testPublicActivityMetadataCarriesSummaryWithoutAnotherAttachmentOrOutcome() throws {
        let delivery = makeDelivery(bytes: Data([1, 2, 3]), title: "工厂 / e\u{301} / %@")
        let payload = ReportSharePayload(delivery: delivery)
        let configuration = payload.activityConfiguration()
        XCTAssertEqual(configuration.metadataProvider?(.title) as? String, payload.presentation.subject)
        XCTAssertEqual(configuration.metadataProvider?(.messageBody) as? String, payload.presentation.body)
        XCTAssertNil(configuration.metadataProvider?(.linkPresentationMetadata))
        XCTAssertTrue(payload.presentation.body.contains(delivery.title))
        XCTAssertTrue(payload.presentation.documentLanguage.contains("not recorded"))
    }

    func testHistoricDeliveryDoesNotInferDocumentLanguageFromAppLanguageOrGenerationIntent() throws {
        let request = try ReportLanguageRenderRequestV1(
            selection: ReportLanguageControlPolicyV1.resolve(requested: .init("ko"), confirmsEnglishFallback: true),
            requestedFormatting: .init(localeIdentifier: "de-DE", ianaTimeZoneIdentifier: "UTC",
                                       calendar: .gregorian, numberingSystem: .latin, units: .metric)
        )
        let historic = ReportDeliveryValue(reportID: UUID(), pdfSHA256: String(repeating: "a", count: 64),
                                          pdfData: Data([1]), filename: "fixed.pdf", title: "用户文字", subtitle: "Nguồn",
                                          detailLines: [], languageRequest: request)
        XCTAssertNil(historic.documentLanguage)
        let english = GlobalizedSharePrintLabelSurfacesV1(appLanguage: .english)
        let unknown = GlobalizedShareDeliveryCoordinatorV1.report(historic, surfaces: english)
        XCTAssertEqual(unknown.documentLanguage, english.documentLanguage(nil))
        let confirmed = english.documentLanguage(request.selection)
        XCTAssertTrue(confirmed.contains("English fallback confirmed"))
        XCTAssertFalse(confirmed.contains("not recorded"))
        XCTAssertTrue(confirmed.contains("Korean"))
    }

    func testDeliveryEqualityIncludesRecordedLanguageButExcludesCurrentPresentationPreferences() throws {
        let id = UUID()
        let exact = try ReportLanguageControlPolicyV1.resolve(requested: .english)
        let fallback = try ReportLanguageControlPolicyV1.resolve(requested: .init("ko"), confirmsEnglishFallback: true)
        func delivery(_ language: ReportLanguageSelectionV1?, locale: String = "en-US") -> ReportDeliveryValue {
            .init(reportID: id, pdfSHA256: String(repeating: "a", count: 64), pdfData: Data([1]),
                  filename: "same.pdf", title: "Same", subtitle: "Source", detailLines: [],
                  formattingLocale: Locale(identifier: locale), documentLanguage: language)
        }
        XCTAssertNotEqual(delivery(nil), delivery(exact))
        XCTAssertNotEqual(delivery(exact), delivery(fallback))
        XCTAssertEqual(delivery(exact), delivery(exact, locale: "ko-KR"))
    }

    func testInjectedResourceLanguageControlsChromeAndPositionalTemplatesWithoutTranslatingArguments() throws {
        let bundle = try resourceFixture()
        let surfaces = GlobalizedSharePrintLabelSurfacesV1(bundle: bundle, appLanguage: try .init("es"))
        XCTAssertEqual(surfaces.shareOrPrint, "ES SHARE PRINT")
        XCTAssertEqual(surfaces.reportSubject(title: "e\u{301} %@ 工厂"), "ES e\u{301} %@ 工厂")
        XCTAssertEqual(surfaces.reportBody(title: "标题", subtitle: "موقع", documentLanguage: "FROZEN"), "موقع | 标题 | FROZEN")
        XCTAssertEqual(surfaces.audience(.customerSafe), "ES CUSTOMER")
        XCTAssertEqual(surfaces.label(.claimBoundary), "ES NO PRINT OR DELIVERY CLAIM")
        XCTAssertEqual(surfaces.doNotDeploy, "ES DO NOT DEPLOY")
        XCTAssertEqual(surfaces.documentLanguage(nil), "ES LANGUAGE UNRECORDED")
    }

    func testLocalizedFeedbackDraftKeepsConsentAndExactReviewedDiagnosticAttachment() async throws {
        let prepared = try await DiagnosticExportService(
            counters: { .zero }, metricKit: { nil },
            app: { .init(build: "42", version: "1.2.3") },
            device: { .init(model: "iPhone", osVersion: "26.2") },
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        ).prepare()
        let surfaces = GlobalizedSharePrintLabelSurfacesV1(bundle: try resourceFixture(), appLanguage: try .init("es"))
        let attached = try FeedbackMailDraftBuilderV1.make(configuration: .uiTestFixture, diagnostic: prepared,
                                                          attachmentChoice: .attach, surfaces: surfaces)
        let detached = try FeedbackMailDraftBuilderV1.make(configuration: .uiTestFixture, diagnostic: prepared,
                                                          attachmentChoice: .doNotAttach, surfaces: surfaces)
        XCTAssertEqual(attached.subject, "ES FEEDBACK")
        XCTAssertEqual(attached.body, "ES 26.2 / iPhone / 42 / 1.2.3")
        XCTAssertEqual(attached.body, detached.body)
        XCTAssertEqual(attached.attachments.first?.data, prepared.canonicalData)
        XCTAssertEqual(attached.recipients, ["support@example.invalid"])
        XCTAssertTrue(detached.attachments.isEmpty)
        let invalid = PreparedDiagnosticExportV1(value: prepared.value, canonicalData: prepared.canonicalData + Data([32]))
        XCTAssertThrowsError(try FeedbackMailDraftBuilderV1.make(configuration: .uiTestFixture, diagnostic: invalid,
                                                                attachmentChoice: .attach, surfaces: surfaces))
    }

    private func makeDelivery(bytes: Data, title: String, documentLanguage: ReportLanguageSelectionV1? = nil) -> ReportDeliveryValue {
        .init(reportID: UUID(), pdfSHA256: KernelCanonicalHashV1.sha256(bytes), pdfData: bytes,
              filename: "report-fixed.pdf", title: title, subtitle: "原文 / authored",
              detailLines: [], documentLanguage: documentLanguage)
    }

    private struct Fixture: Decodable {
        struct Authored: Decodable { let text: String; let utf8ByteCount: Int }
        let cardID: String
        let languages: [String]
        let authored: [Authored]
    }

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/Share/globalized-share-print-label-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Synthetic resource-routing evidence only, not a shipping translation or
    /// linguistic acceptance. The bundle is isolated from application resources.
    private func resourceFixture() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("c06-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("es.lproj"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let info: [String: Any] = ["CFBundleIdentifier": "test.c06.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "es"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        let values = [
            "v30.share.action.share-or-print": "ES SHARE PRINT",
            "v30.share.report.subject": "ES %@",
            "v30.share.report.body": "%2$@ | %1$@ | %3$@",
            "v30.share.audience.customer-safe": "ES CUSTOMER",
            "v30.share.document-language.unrecorded": "ES LANGUAGE UNRECORDED",
            "v30.share.labels.do-not-deploy": "ES DO NOT DEPLOY",
            "asset_label.claim_boundary": "ES NO PRINT OR DELIVERY CLAIM",
            "feedback.mail.subject": "ES FEEDBACK",
            "feedback.mail.body_template": "ES %4$@ / %3$@ / %2$@ / %1$@"
        ]
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("es.lproj/Localizable.strings"))
        return try XCTUnwrap(Bundle(url: root))
    }
}
