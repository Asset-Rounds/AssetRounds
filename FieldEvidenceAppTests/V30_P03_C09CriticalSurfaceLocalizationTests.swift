import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P03C09CriticalSurfaceLocalizationTests: XCTestCase {
    func testEveryFailureHasDistinctRegisteredCopyWithoutChangingItsAction() throws {
        let registry = try BundledLocalizationCatalogV1.criticalSurfaceRegistry()
        try registry.validate()
        let english = CriticalSurfaceLocalizationRegistryV1(languageLocale: Locale(identifier: "en"))
        var messages = Set<String>()
        for code in OperationalFailureCodeV1.allCases {
            let failure = try recovery(code)
            let presentation = try CriticalSurfaceRecoveryCoordinatorV1.presentation(for: failure, strings: english)
            let key = try LocalizationKeyV1(CriticalSurfaceLocalizationRegistryV1.failureKey(code))
            let definition = try registry.definition(for: key)
            XCTAssertFalse(definition.englishDefaultValue.isEmpty)
            XCTAssertFalse(definition.translatorComment.isEmpty)
            XCTAssertFalse(presentation.message.hasPrefix("v30."))
            XCTAssertEqual(presentation.failure, failure)
            XCTAssertEqual(presentation.message, definition.englishDefaultValue)
            messages.insert(presentation.message)
        }
        XCTAssertEqual(messages.count, OperationalFailureCodeV1.allCases.count)
    }

    func testSyntheticLanguageResourcesChangeCopyButPreserveRecoveryIdentityAndActions() throws {
        for language in try fixture().languages {
            let bundle = try resourceFixture(language)
            let strings = CriticalSurfaceLocalizationRegistryV1(bundle: bundle, languageLocale: Locale(identifier: language))
            for code in OperationalFailureCodeV1.allCases {
                let failure = try recovery(code)
                let presentation = try CriticalSurfaceRecoveryCoordinatorV1.presentation(for: failure, strings: strings)
                XCTAssertEqual(presentation.message, "FIXTURE \(language) \(code.rawValue)")
                XCTAssertEqual(presentation.failure, failure)
                XCTAssertEqual(presentation.primaryActionKey,
                    CriticalSurfaceRecoveryCoordinatorV1.actionKey(failure.primaryAction))
                XCTAssertEqual(presentation.helpKey, failure.helpTopic.flatMap(CriticalSurfaceRecoveryCoordinatorV1.helpKey))
            }
        }
    }

    func testLocalizedTemplatesCanReorderStatusAndDetailWithoutLosingContext() throws {
        let strings = CriticalSurfaceLocalizationRegistryV1(bundle: try resourceFixture("es"), languageLocale: Locale(identifier: "es"))
        XCTAssertEqual(strings.status(label: "État", state: "未完成"), "未完成 | État")
        XCTAssertEqual(strings.messageWithDetail(message: "Restore failed", detail: "请解锁 iPhone"), "请解锁 iPhone — Restore failed")
    }

    @MainActor
    func testEraseInstructionsKeepTheExactAuthorityTokenInEveryLanguage() throws {
        XCTAssertEqual(EraseAllService.requiredConfirmation, "ERASE")
        for language in try fixture().languages {
            let strings = CriticalSurfaceLocalizationRegistryV1(bundle: try resourceFixture(language), languageLocale: Locale(identifier: language))
            XCTAssertEqual(strings.eraseInstructions(token: EraseAllService.requiredConfirmation), "FIXTURE \(language) [ERASE]")
        }
        let source = try String(contentsOf: repositoryRoot.appendingPathComponent("FieldEvidenceApp/Features/Settings/EraseAllView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Text(verbatim: EraseAllService.requiredConfirmation)"))
        XCTAssertTrue(source.contains("guard confirmation == EraseAllService.requiredConfirmation"))
    }

    func testPermissionCatalogExactlyCoversDeclaredPromptsAndExistingCapabilities() throws {
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from:
            Data(contentsOf: repositoryRoot.appendingPathComponent("FieldEvidenceApp/Info.plist")), format: nil) as? [String: Any])
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with:
            Data(contentsOf: repositoryRoot.appendingPathComponent("FieldEvidenceApp/InfoPlist.xcstrings"))) as? [String: Any])
        let entries = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let declared = Set(info.keys.filter { $0.hasSuffix("UsageDescription") })
        XCTAssertEqual(declared, Set(CriticalPermissionPurposeV1.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(entries.keys), declared)
        let capabilities = try CapabilityPermissionMatrixV1.current()
        for purpose in CriticalPermissionPurposeV1.allCases {
            let entry = try XCTUnwrap(entries[purpose.rawValue] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            XCTAssertEqual(unit["value"] as? String, info[purpose.rawValue] as? String)
            XCTAssertEqual(unit["value"] as? String, purpose.english)
            for capability in purpose.capabilities {
                let descriptor = try capabilities.descriptor(for: capability)
                XCTAssertEqual(descriptor.purposeStringKey, purpose.rawValue)
                XCTAssertEqual(descriptor.requestTiming, .explicitUserInitiatedFeatureBoundary)
            }
        }
    }

    func testCriticalSurfaceExistingKeysResolveToBundledCatalogEntries() throws {
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with:
            Data(contentsOf: repositoryRoot.appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings"))) as? [String: Any])
        let entries = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let input = try fixture()
        XCTAssertEqual(input.surfaces.count, 13)
        for surface in input.surfaces {
            XCTAssertFalse(surface.keys.isEmpty, surface.path)
            for key in surface.keys { XCTAssertNotNil(entries[key], "\(surface.path): \(key)") }
        }
    }

    func testNotificationAndSettingsCopyDoesNotGrantCapabilityOrChangeRecoveryState() throws {
        XCTAssertFalse(ScheduleNotificationCapabilityBoundaryV1.permissionIsCanonicalScheduleTruth)
        XCTAssertFalse(ScheduleRestoreIdentityPolicyV1.notificationStateRestoredAsTruth)
        let denied = try recovery(.permissionDenied)
        for language in try fixture().languages {
            let presentation = try CriticalSurfaceRecoveryCoordinatorV1.presentation(for: denied,
                strings: .init(bundle: try resourceFixture(language), languageLocale: Locale(identifier: language)))
            XCTAssertEqual(presentation.failure.primaryAction, .openSettings)
            XCTAssertEqual(presentation.failure.fallbackAction, .cancel)
            XCTAssertEqual(presentation.failure.helpTopic, denied.helpTopic)
            XCTAssertEqual(presentation.primaryActionKey, .actionOpenSettings)
            XCTAssertFalse(LocalizedSyncStatePresentationV1.remoteSyncUnavailable.permitsSuccessAnnouncement)
            XCTAssertFalse(LocalizedSyncStatePresentationV1.restore(.failed).permitsSuccessAnnouncement)
        }
    }

    private func recovery(_ code: OperationalFailureCodeV1) throws -> RecoveryFailurePresentationV1 {
        try .init(failure: .init(code: code, occurredAt: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private struct Fixture: Decodable {
        struct Surface: Decodable { let path: String; let keys: [String] }
        let languages: [String]
        let surfaces: [Surface]
    }
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: repositoryRoot.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V30/CriticalSurfaces/critical-surface-cases-v1.json")))
    }

    /// Synthetic routing fixtures, not translations or shipping locale claims.
    private func resourceFixture(_ language: String) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("c09-\(UUID().uuidString).bundle")
        let resource = root.appendingPathComponent("\(language).lproj")
        try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let info: [String: Any] = ["CFBundleIdentifier": "test.c09.\(UUID().uuidString)",
            "CFBundleDevelopmentRegion": language, "CFBundleLocalizations": [language]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        var values = Dictionary(uniqueKeysWithValues: OperationalFailureCodeV1.allCases.map {
            (CriticalSurfaceLocalizationRegistryV1.failureKey($0), "FIXTURE \(language) \($0.rawValue)")
        })
        values["v30.critical.status-with-label"] = "%2$@ | %1$@"
        values["v30.critical.message-with-detail"] = "%2$@ — %1$@"
        values["v30.critical.erase-confirmation"] = "FIXTURE \(language) [%@]"
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            .write(to: resource.appendingPathComponent("Localizable.strings"))
        return try XCTUnwrap(Bundle(url: root))
    }
}
