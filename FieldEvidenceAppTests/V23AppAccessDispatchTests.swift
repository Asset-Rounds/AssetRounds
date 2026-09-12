import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23AppAccessDispatchTests: XCTestCase {
    func testConcreteAndExistentialReadEntriesUseTheAtomicProductionPermit() async throws {
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: DispatchAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let port: any AppAccessGatePortV1 = gate
        let initialState = await gate.currentState()
        XCTAssertEqual(initialState, .locked(reason: .coldLaunch))
        for surface in [AppAccessContentReadSurfaceV1.render, .startupRecovery] {
            do {
                _ = try await gate.requireContentAccess(for: surface)
                XCTFail("Concrete read opened locked content")
            } catch {
                XCTAssertEqual(error as? AppAccessContentReadFailureV1,
                    .denied(surface: surface, state: .locked(reason: .coldLaunch)))
            }
            do {
                _ = try await port.requireContentAccess(for: surface)
                XCTFail("Existential read opened locked content")
            } catch {
                XCTAssertEqual(error as? AppAccessContentReadFailureV1,
                    .denied(surface: surface, state: .locked(reason: .coldLaunch)))
            }
        }
        let outcome = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(outcome, .authenticated)
        for surface in [AppAccessContentReadSurfaceV1.render, .startupRecovery] {
            let concrete = try await gate.requireContentAccess(for: surface)
            let existential = try await port.requireContentAccess(for: surface)
            XCTAssertEqual(concrete, existential)
            guard case .unlockedForeground = concrete.state else {
                return XCTFail("Production permit must retain its authenticated foreground session")
            }
            XCTAssertEqual(concrete.surface, surface)
        }
    }

    func testRepairAuthenticationCannotUseCompatibilityDispatchToOpenContent() async throws {
        let gate = AppAccessGateV1(setting: .corruptOrAmbiguous,
            authentication: DispatchAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let outcome = await gate.authenticate(trigger: .repairConfiguration)
        XCTAssertEqual(outcome, .authenticated)
        let proof = try await gate.configurationAuthenticationToken()
        try await gate.validateConfigurationAuthentication(proof)
        let port: any AppAccessGatePortV1 = gate
        do {
            _ = try await gate.requireContentAccess(for: .startupRecovery)
            XCTFail("Repair proof opened ordinary startup content")
        } catch {
            XCTAssertEqual(error as? AppAccessContentReadFailureV1,
                .denied(surface: .startupRecovery, state: .configurationUnknownLocked))
        }
        do {
            _ = try await port.requireContentAccess(for: .startupRecovery)
            XCTFail("Repair proof opened content through the protocol")
        } catch {
            XCTAssertEqual(error as? AppAccessContentReadFailureV1,
                .denied(surface: .startupRecovery, state: .configurationUnknownLocked))
        }
    }
}

private actor DispatchAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}
