import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Injected test observations, never a capability claim about a shipping OS.
enum V30AssistedInputTestSupport {
    static func environment(build: String = "FIXTURE_OS_BUILD", device: String = "FIXTURE_DEVICE",
                            app: String = "FIXTURE_APP:1") throws -> AssistedInputEnvironmentV1 {
        try .init(operatingSystemVersion: "26.2", operatingSystemBuild: build,
                  deviceModel: device, applicationBuild: app, isSimulator: true)
    }
    static func available(_ query: AssistedInputCapabilityQueryV1, revision: String) throws -> AssistedInputCapabilityObservationV1 {
        try .init(query: query, supportedLocaleIdentifiers: query.localeIdentifiers,
                  onDevice: .available, online: .unobserved, implementationRevision: revision)
    }
}

final class V30P03C07AssistedInputCapabilityTests: XCTestCase {
    func testLocaleMatrixIsObservedPerInvocationAndDoesNotInferSupportFromTranslation() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/AssistedInput/assisted-input-capability-cases-v1.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.cardID, "V30-P03-C07")
        XCTAssertFalse(fixture.shippingCapabilityClaims)
        XCTAssertEqual(fixture.locales, ["en-US", "es-US", "zh-Hans-CN", "zh-Hant-TW", "vi-VN", "ko-KR"])
        let environment = try V30AssistedInputTestSupport.environment()
        for locale in fixture.locales {
            for kind in AssistedInputKindV1.allCases {
                let query = try AssistedInputCapabilityQueryV1(kind: kind, localeIdentifiers: [locale],
                                                              providerRelease: "fixture:1", environment: environment)
                XCTAssertEqual(evaluate(query, nil), .unobserved)
                let observed = try V30AssistedInputTestSupport.available(query, revision: "fixture-only")
                XCTAssertEqual(evaluate(query, observed), .availableOnDevice)
                XCTAssertEqual(AssistedInputCapabilityCoordinatorV1.evaluate(query: query, observation: observed,
                    currentEnvironment: environment, featureEnabled: false), .featureDisabled)
                let translatedLabelsChanged = try AssistedInputCapabilityQueryV1(kind: kind, localeIdentifiers: [locale],
                    providerRelease: "fixture:1", environment: environment)
                XCTAssertEqual(evaluate(translatedLabelsChanged, observed), .staleObservation)
            }
        }
    }

    func testOnlineOnlyUnknownAndUnsupportedLocaleNeverEnableOfflineOperation() throws {
        let query = try makeQuery()
        let online = try AssistedInputCapabilityObservationV1(query: query, supportedLocaleIdentifiers: ["en-US"],
            onDevice: .unavailable, online: .available, implementationRevision: "fixture")
        XCTAssertEqual(evaluate(query, online), .onlineOnly)
        XCTAssertFalse(evaluate(query, online).mayStartOnDevice)
        let unknown = try AssistedInputCapabilityObservationV1(query: query, supportedLocaleIdentifiers: ["en-US"],
            onDevice: .unobserved, online: .unobserved, implementationRevision: "fixture")
        XCTAssertEqual(evaluate(query, unknown), .unobserved)
        let unknownOffline = try AssistedInputCapabilityObservationV1(query: query, supportedLocaleIdentifiers: ["en-US"],
            onDevice: .unobserved, online: .available, implementationRevision: "fixture")
        XCTAssertEqual(evaluate(query, unknownOffline), .unobserved, "Unknown offline support is not proof of online-only support")
        let otherRegion = try AssistedInputCapabilityObservationV1(query: query, supportedLocaleIdentifiers: ["en-GB", "en"],
            onDevice: .available, online: .unobserved, implementationRevision: "fixture")
        XCTAssertEqual(evaluate(query, otherRegion), .unsupportedLocale)
    }

    func testEnvironmentProviderKindAndLocaleChangesInvalidateObservation() throws {
        let query = try makeQuery()
        let observation = try V30AssistedInputTestSupport.available(query, revision: "fixture")
        for environment in [try V30AssistedInputTestSupport.environment(build: "OTHER_OS_BUILD"),
                            try V30AssistedInputTestSupport.environment(device: "OTHER_DEVICE"),
                            try V30AssistedInputTestSupport.environment(app: "OTHER_APP:2")] {
            XCTAssertEqual(AssistedInputCapabilityCoordinatorV1.evaluate(query: query, observation: observation,
                currentEnvironment: environment, featureEnabled: true), .staleObservation)
        }
        for changed in [
            try AssistedInputCapabilityQueryV1(invocationID: query.invocationID, kind: .dictation,
                localeIdentifiers: query.localeIdentifiers, providerRelease: query.providerRelease, environment: query.environment),
            try AssistedInputCapabilityQueryV1(invocationID: query.invocationID, kind: query.kind,
                localeIdentifiers: ["en-GB"], providerRelease: query.providerRelease, environment: query.environment),
            try AssistedInputCapabilityQueryV1(invocationID: query.invocationID, kind: query.kind,
                localeIdentifiers: query.localeIdentifiers, providerRelease: "fixture:2", environment: query.environment)
        ] { XCTAssertEqual(evaluate(changed, observation), .staleObservation) }
    }

    func testIncompleteAndDuplicateScopeCannotBecomeEvidence() throws {
        XCTAssertThrowsError(try V30AssistedInputTestSupport.environment(build: ""))
        XCTAssertThrowsError(try AssistedInputCapabilityQueryV1(kind: .ocr, localeIdentifiers: [],
            providerRelease: "fixture", environment: V30AssistedInputTestSupport.environment()))
        XCTAssertThrowsError(try AssistedInputCapabilityQueryV1(kind: .ocr, localeIdentifiers: ["en-US", "en-US"],
            providerRelease: "fixture", environment: V30AssistedInputTestSupport.environment()))
        let query = try makeQuery()
        XCTAssertThrowsError(try AssistedInputCapabilityObservationV1(query: query, supportedLocaleIdentifiers: ["en-US"],
            onDevice: .available, online: .unobserved, implementationRevision: ""))
    }

    private func makeQuery() throws -> AssistedInputCapabilityQueryV1 {
        try .init(kind: .ocr, localeIdentifiers: ["en-US"], providerRelease: "fixture:1",
                  environment: V30AssistedInputTestSupport.environment())
    }
    private func evaluate(_ query: AssistedInputCapabilityQueryV1, _ observation: AssistedInputCapabilityObservationV1?) -> AssistedInputCapabilityDispositionV1 {
        AssistedInputCapabilityCoordinatorV1.evaluate(query: query, observation: observation,
                                                       currentEnvironment: query.environment, featureEnabled: true)
    }
    private struct Fixture: Decodable {
        let cardID: String
        let locales: [String]
        let shippingCapabilityClaims: Bool
    }
}
