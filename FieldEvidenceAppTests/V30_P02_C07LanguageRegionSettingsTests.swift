import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class V30P02C07LanguageRegionSettingsTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSettingsLabelsResolveEnglishDefaultsWithoutRawKeys() {
        for key in GlobalizationSettingsLocalizationKeyV1.allCases {
            let value = BundledLocalizationCatalogV1.globalizationSettingsLocalized(
                key, locale: Locale(identifier: "en")
            )
            XCTAssertEqual(value, key.englishDefaultValue)
            XCTAssertNotEqual(value, key.rawValue)
            XCTAssertFalse(value.isEmpty)
        }
    }

    func testReportLanguagePolicyRequiresConfirmationForEveryNonEnglishRequest() throws {
        XCTAssertEqual(
            Set(ReportLanguageControlPolicyV1.requestableLanguages.map(\.rawValue)),
            ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
        )
        for language in ReportLanguageControlPolicyV1.requestableLanguages {
            if language == .english {
                XCTAssertEqual(
                    try ReportLanguageControlPolicyV1.resolve(requested: language),
                    try ReportLanguageSelectionV1(
                        requestedLanguage: .english,
                        effectiveLanguage: .english,
                        fallback: .exact
                    )
                )
            } else {
                XCTAssertThrowsError(try ReportLanguageControlPolicyV1.resolve(requested: language)) {
                    XCTAssertEqual($0 as? ReportLanguageControlFailureV1, .englishConfirmationRequired)
                }
                let confirmed = try ReportLanguageControlPolicyV1.resolve(
                    requested: language,
                    confirmsEnglishFallback: true
                )
                XCTAssertEqual(confirmed.requestedLanguage, language)
                XCTAssertEqual(confirmed.effectiveLanguage, .english)
                XCTAssertEqual(confirmed.fallback, .englishWithUserConfirmation)
            }
        }
        let forged = try JSONDecoder().decode(
            ReportLanguageSelectionV1.self,
            from: Data("{\"requestedLanguage\":{\"rawValue\":\"fr\"},\"effectiveLanguage\":{\"rawValue\":\"fr\"},\"fallback\":\"EXACT\"}".utf8)
        )
        XCTAssertThrowsError(try ReportLanguageControlPolicyV1.validateForCurrentRenderer(forged))
        let invalidExactKorean = try ReportLanguageSelectionV1(
            requestedLanguage: try AppLanguageTagV1("ko"),
            effectiveLanguage: try AppLanguageTagV1("ko"),
            fallback: .exact
        )
        XCTAssertThrowsError(
            try ReportLanguageControlPolicyV1.validateForCurrentRenderer(invalidExactKorean)
        ) { XCTAssertEqual($0 as? ReportLanguageControlFailureV1, .unavailableReportLanguage) }
    }

    @MainActor
    func testPreferencePersistsConfirmedChoicePreservesFormattingAndResetsOrErases() throws {
        let suite = "V30P02C07-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = PreferencesAdapterV1(defaults: defaults)
        let defaultCoordinator = ReportLanguageCoordinatorV1(preferences: adapter)
        XCTAssertThrowsError(
            try defaultCoordinator.makeRenderRequest(effectiveAppLanguage: try AppLanguageTagV1("es"))
        )
        XCTAssertEqual(
            try defaultCoordinator.makeRenderRequest(effectiveAppLanguage: .english).selection.fallback,
            .exact
        )
        XCTAssertEqual(
            try defaultCoordinator.makeRenderRequest(
                effectiveAppLanguage: try AppLanguageTagV1("es"), confirmsEnglishFallback: true
            ).selection.fallback,
            .englishWithUserConfirmation
        )
        XCTAssertNil(try defaultCoordinator.loadPreference().reportLanguage)
        let formatting = try FormattingLocaleProfileV1(
            localeIdentifier: "es-MX", ianaTimeZoneIdentifier: "America/Chicago",
            calendar: .gregorian, numberingSystem: .latin, units: .metric
        )
        try adapter.writeGlobalizationPresentationPreference(
            .init(formatting: formatting), operationID: UUID()
        )
        let coordinator = ReportLanguageCoordinatorV1(preferences: adapter)
        let spanish = try AppLanguageTagV1("es")
        let saved = try coordinator.save(
            requested: spanish, confirmsEnglishFallback: true, operationID: UUID()
        )
        XCTAssertEqual(saved.formatting, formatting)
        XCTAssertEqual(saved.reportLanguage?.requestedLanguage, spanish)
        XCTAssertEqual(saved.reportLanguage?.effectiveLanguage, .english)

        let relaunched = ReportLanguageCoordinatorV1(
            preferences: PreferencesAdapterV1(defaults: defaults)
        )
        XCTAssertEqual(try relaunched.loadPreference(), saved)
        XCTAssertEqual(
            try relaunched.makeRenderRequest(effectiveAppLanguage: try AppLanguageTagV1("ko")).selection,
            try ReportLanguageControlPolicyV1.resolve(requested: spanish, confirmsEnglishFallback: true)
        )

        let beforeUnconfirmed = try adapter.readGlobalizationPresentationPreference()
        XCTAssertThrowsError(try coordinator.save(requested: try AppLanguageTagV1("ko"), operationID: UUID()))
        XCTAssertEqual(try adapter.readGlobalizationPresentationPreference(), beforeUnconfirmed)

        let defaulted = try coordinator.useAppLanguageDefault(operationID: UUID())
        XCTAssertNil(defaulted.reportLanguage)
        XCTAssertEqual(defaulted.formatting, formatting)
        XCTAssertThrowsError(
            try coordinator.makeRenderRequest(effectiveAppLanguage: try AppLanguageTagV1("ko"))
        )

        let descriptor = try GlobalizationDevicePreferenceV1.descriptor()
        try adapter.reset(descriptors: [descriptor], operationID: UUID())
        XCTAssertEqual(try adapter.readGlobalizationPresentationPreference(), GlobalizationDevicePreferenceV1.logicalDefault)
        _ = try coordinator.save(requested: spanish, confirmsEnglishFallback: true, operationID: UUID())
        try adapter.erase(descriptors: [descriptor], operationID: UUID())
        XCTAssertEqual(try adapter.readGlobalizationPresentationPreference(), GlobalizationDevicePreferenceV1.logicalDefault)
    }

    @MainActor
    func testSaveIsIdempotentAndRejectsConflictingOperationWithoutChangingCurrentPreference() throws {
        let suite = "V30P02C07-idempotency-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = PreferencesAdapterV1(defaults: defaults)
        let coordinator = ReportLanguageCoordinatorV1(preferences: adapter)
        let operationID = UUID()
        let first = try coordinator.save(
            requested: try AppLanguageTagV1("vi"), confirmsEnglishFallback: true, operationID: operationID
        )
        XCTAssertEqual(
            try coordinator.save(
                requested: try AppLanguageTagV1("vi"), confirmsEnglishFallback: true, operationID: operationID
            ),
            first
        )
        XCTAssertThrowsError(
            try coordinator.save(requested: .english, operationID: operationID)
        ) { XCTAssertEqual($0 as? PreferencesAdapterFailureV1, .conflictingOperation) }
        XCTAssertEqual(try adapter.readGlobalizationPresentationPreference(), first)
    }

    @MainActor
    func testCoordinatorPropagatesReadAndWriteFailures() throws {
        let preference = GlobalizationDevicePreferenceV1.logicalDefault
        let readFailure = ReportLanguageCoordinatorV1(
            preferences: FailingGlobalizationPreferences(preference: preference, failsRead: true)
        )
        XCTAssertThrowsError(try readFailure.loadPreference())
        let writeFailure = ReportLanguageCoordinatorV1(
            preferences: FailingGlobalizationPreferences(preference: preference, failsWrite: true)
        )
        XCTAssertThrowsError(try writeFailure.save(requested: .english, operationID: UUID()))
        XCTAssertEqual(try writeFailure.loadPreference(), preference)
    }
    func testLanguageFormattingAuthoredReportAndJurisdictionAxesRemainIndependent() throws {
        let spanish = try AppLanguageTagV1("es")
        let formatting = try FormattingLocaleProfileV1(
            localeIdentifier: "ko-KR", ianaTimeZoneIdentifier: "Asia/Seoul",
            calendar: .gregorian, numberingSystem: .latin, units: .metric
        )
        let report = try ReportLanguageControlPolicyV1.resolve(
            requested: spanish, confirmsEnglishFallback: true
        )
        let axes = GlobalizationAxisSetV1(
            appLanguage: spanish,
            formatting: formatting,
            authoredContentLanguage: try AuthoredContentLanguageV1.declared("zh-Hant"),
            reportLanguage: report,
            storefrontCountry: .unitedStates,
            projectJurisdiction: try .init(countryCode: "US", subdivisionCode: "CA")
        )
        XCTAssertEqual(axes.appLanguage, spanish)
        XCTAssertEqual(axes.formatting.localeIdentifier, "ko-KR")
        XCTAssertEqual(axes.authoredContentLanguage, .known("zh-Hant"))
        XCTAssertEqual(axes.reportLanguage.effectiveLanguage, .english)
        XCTAssertEqual(axes.projectJurisdiction.stableIdentifier, "US-CA")
        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.backupIncludesAxisPreferences)
        XCTAssertNoThrow(try GlobalizationCanonicalIdentityBoundaryV1.validateNoCanonicalIdentityMutation([]))
    }
    @MainActor
    func testFreshRequestedLanguageDoesNotChangeSnapshotOrCachedPDFAndHistoricalLoadsDoNotInferIntent() async throws {
        let harness = try await makeDeliveryHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let originalSnapshot = try Data(contentsOf: harness.snapshotURL)
        let originalPDF = try Data(contentsOf: harness.pdfURL)
        let originalHash = try XCTUnwrap(harness.report.pdfSHA256)
        try resetToPending(harness)

        let request = try ReportLanguageRenderRequestV1(
            selection: try ReportLanguageControlPolicyV1.resolve(
                requested: try AppLanguageTagV1("es"), confirmsEnglishFallback: true
            ),
            requestedFormatting: try FormattingLocaleProfileV1(
                localeIdentifier: "es-MX", ianaTimeZoneIdentifier: "America/Chicago",
                calendar: .gregorian, numberingSystem: .latin, units: .metric
            )
        )
        let delivery = try ReportDeliveryCoordinator(
            modelContext: harness.context, generationRootURL: harness.session.generationRootURL
        )
        guard case let .ready(fresh) = try delivery.prepareFinalizedReport(
            id: harness.report.id, languageRequest: request
        ) else { return XCTFail("Fresh report render must be ready") }
        guard case let .ready(repeated) = try delivery.prepareFinalizedReport(
            id: harness.report.id, languageRequest: request
        ) else { return XCTFail("Ready report must load on repeated preparation") }
        let loaded = try delivery.loadReadyReport(id: harness.report.id)
        XCTAssertEqual(fresh.languageRequest, request)
        XCTAssertNil(repeated.languageRequest)
        XCTAssertNil(loaded.languageRequest)
        XCTAssertEqual(fresh, repeated, "Transient intent cannot alter delivery identity")
        XCTAssertEqual(repeated, loaded)
        XCTAssertEqual(try Data(contentsOf: harness.snapshotURL), originalSnapshot)
        XCTAssertEqual(try Data(contentsOf: harness.pdfURL), originalPDF)
        XCTAssertEqual(try XCTUnwrap(harness.report.pdfSHA256), originalHash)
        XCTAssertEqual(fresh.pdfSHA256, originalHash)
    }

    @MainActor
    private func makeDeliveryHarness() async throws -> DeliveryHarness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let observed = Date(timeIntervalSince1970: 1_768_800_000)
        let site = Site(id: UUID(), label: "C07 Site", address: "10 Main", timeZoneID: "America/New_York", createdAt: observed)
        let asset = Asset(id: UUID(), siteID: site.id, packID: pack.packID, packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion, label: "C07 Asset", createdAt: observed)
        context.insert(site); context.insert(asset); try context.save()
        let checks = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        checks.configureCapture(generationRootURL: session.generationRootURL)
        _ = try checks.beginCheck(assetID: asset.id, timeZoneID: nil, isTimeZoneConfirmed: false, afterDarkAccepted: true, safePositionAccepted: true, observedAt: observed)
        for (seed, offset) in [(UInt8(31), 1.0), (UInt8(79), 2.0)] {
            let candidate = try await checks.importCandidate(assetID: asset.id, sourceData: try png(seed), createdAt: observed.addingTimeInterval(offset))
            _ = try await checks.accept(candidate: candidate, assetID: asset.id)
        }
        let reportID = UUID()
        let result = try await checks.finalize(assetID: asset.id, selection: .noVisibleIssue, completedAt: observed.addingTimeInterval(10), snapshotCreatedAt: observed.addingTimeInterval(11), sourceApp: SourceAppSnapshotV1(build: "42", version: "1.0"), identifiers: FinalizationIdentifiers(mutationID: UUID(), packetID: UUID(), stableRootID: UUID(), reportID: reportID, issueID: nil))
        guard case .ready = try checks.prepareReportDelivery(result: result) else { throw C07ReportFixtureFailure.reportNotReady }
        let report = try XCTUnwrap(context.fetch(FetchDescriptor<Report>()).first)
        return DeliveryHarness(applicationSupportURL: support, session: session, context: context, report: report)
    }

    @MainActor
    private func resetToPending(_ harness: DeliveryHarness) throws {
        try fileManager.removeItem(at: harness.pdfURL)
        harness.report.pdfState = ReportPDFState.pending.rawValue
        harness.report.pdfRelativePath = nil
        harness.report.pdfSHA256 = nil
        try harness.context.save()
    }

    private func png(_ seed: UInt8) throws -> Data {
        let width = 48, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = seed &+ UInt8(truncatingIfNeeded: x)
                pixels[index + 1] = seed &+ UInt8(truncatingIfNeeded: y)
                pixels[index + 2] = seed &+ UInt8(truncatingIfNeeded: x ^ y)
                pixels[index + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw C07ReportFixtureFailure.couldNotCreateImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw C07ReportFixtureFailure.couldNotCreateImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw C07ReportFixtureFailure.couldNotCreateImage }
        return output as Data
    }
}

private enum C07ReportFixtureFailure: Error {
    case couldNotCreateImage
    case reportNotReady
}

@MainActor
private struct DeliveryHarness {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let context: ModelContext
    let report: Report
    var snapshotURL: URL { session.generationRootURL.appendingPathComponent(report.snapshotRelativePath) }
    var pdfURL: URL { session.generationRootURL.appendingPathComponent("pdfs/\(report.id.uuidString.lowercased()).pdf") }
}
private struct FailingGlobalizationPreferences: GlobalizationPresentationPreferencesPortV1 {
    enum Failure: Error { case read, write }

    let preference: GlobalizationPresentationPreferenceV1
    let failsRead: Bool
    let failsWrite: Bool

    init(
        preference: GlobalizationPresentationPreferenceV1,
        failsRead: Bool = false,
        failsWrite: Bool = false
    ) {
        self.preference = preference
        self.failsRead = failsRead
        self.failsWrite = failsWrite
    }

    func readGlobalizationPresentationPreference() throws -> GlobalizationPresentationPreferenceV1 {
        if failsRead { throw Failure.read }
        return preference
    }

    func updateGlobalizationReportLanguage(
        _ selection: ReportLanguageSelectionV1?, operationID: UUID
    ) throws -> GlobalizationPresentationPreferenceV1 {
        if failsWrite { throw Failure.write }
        return try preference.replacingReportLanguage(selection)
    }
}
