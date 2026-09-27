import Darwin
import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23UnadmittedEraseReturnRouteTests: XCTestCase {
    @MainActor
    func testGenuineNoAdmissionReturnsSameWriterAndAuthenticatedRestartPublishesIt() async throws {
        let fixture = try await Fixture.start("return")
        let original = fixture.coordinator
        let writer = original.workspaceWriter
        let revision = try writer.currentRevision()
        let history = try writer.sourceMutationHistorySnapshot()
        let summary = try BackupRestoreService.currentSummary(
            modelContext: original.modelContext,
            generationRootURL: original.generationRootURL)
        let eraseRoot = fixture.support.appendingPathComponent("FieldEvidenceErase")
        XCTAssertFalse(FileManager.default.fileExists(atPath: eraseRoot.path))

        let ticket = try await fixture.router.beginEraseOperation(
            coordinator: original, accessGate: fixture.gate)
        XCTAssertEqual(fixture.router.recoveryBootstrapState, .checking)
        try fixture.router.cancelUnadmittedErase(ticket)
        XCTAssertEqual(fixture.router.recoveryBootstrapState, .checking)
        XCTAssertTrue(original.workspaceWriter === writer)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertEqual(try BackupRestoreService.currentSummary(
            modelContext: original.modelContext,
            generationRootURL: original.generationRootURL), summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eraseRoot.path))

        // The existing prepared-startup path must use a current gate token and
        // publish the retained actual owner, including normal commerce setup.
        try await fixture.router.startIfNeeded(accessGate: fixture.gate)
        guard case .ready(let republished, _, _) = fixture.router.route else {
            return XCTFail("Authenticated ordinary startup did not republish")
        }
        XCTAssertTrue(republished === original)
        XCTAssertTrue(republished.workspaceWriter === writer)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertEqual(try BackupRestoreService.currentSummary(
            modelContext: original.modelContext,
            generationRootURL: original.generationRootURL), summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eraseRoot.path))
        XCTAssertThrowsError(try fixture.router.cancelUnadmittedErase(ticket)) {
            XCTAssertEqual($0 as? AppAccessContractFailureV1, .staleAttempt)
        }
    }

    @MainActor
    func testPresentPendingControlRefusesReturnWithoutChangingControlOrWriter() async throws {
        let fixture = try await Fixture.start("pending")
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let history = try writer.sourceMutationHistorySnapshot()
        let ticket = try await fixture.router.beginEraseOperation(
            coordinator: fixture.coordinator, accessGate: fixture.gate)
        let eraseRoot = fixture.support.appendingPathComponent("FieldEvidenceErase")
        try FileManager.default.createDirectory(at: eraseRoot,
                                                withIntermediateDirectories: false)
        let pending = eraseRoot.appendingPathComponent(".erase.json.next")
        let bytes = Data([0x00, 0xff, 0x77, 0x24])
        try bytes.write(to: pending)
        let rootBefore = try Identity(at: eraseRoot)
        let pendingBefore = try Identity(at: pending)

        XCTAssertThrowsError(try fixture.router.cancelUnadmittedErase(ticket))
        XCTAssertEqual(fixture.router.recoveryBootstrapState, .checking)
        XCTAssertTrue(fixture.coordinator.workspaceWriter === writer)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertEqual(try Identity(at: eraseRoot), rootBefore)
        XCTAssertEqual(try Identity(at: pending), pendingBefore)
        XCTAssertEqual(try Data(contentsOf: pending), bytes)
        // The retained operation/root remain available to the actual recovery
        // owner; the test never deletes or repairs the ambiguous control.
    }

    @MainActor
    func testRelockedEpochRefusesReturnAndPreservesOriginalWriter() async throws {
        let fixture = try await Fixture.start("relocked")
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let history = try writer.sourceMutationHistorySnapshot()
        let ticket = try await fixture.router.beginEraseOperation(
            coordinator: fixture.coordinator, accessGate: fixture.gate)
        await fixture.gate.lock(reason: .interrupted)

        XCTAssertThrowsError(try fixture.router.cancelUnadmittedErase(ticket))
        XCTAssertEqual(fixture.router.recoveryBootstrapState, .checking)
        XCTAssertTrue(fixture.coordinator.workspaceWriter === writer)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.support
            .appendingPathComponent("FieldEvidenceErase").path))
    }

    @MainActor
    func testGenuineIssuedAuthorityWithoutReservationCannotReturn() async throws {
        let fixture = try await Fixture.start("issued")
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let history = try writer.sourceMutationHistorySnapshot()
        let ticket = try await fixture.router.beginEraseOperation(
            coordinator: fixture.coordinator, accessGate: fixture.gate)
        let operation = try fixture.router.eraseRetirementOperation(for: ticket)
        var issued = false
        let service = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches, temporaryDirectoryURL: fixture.temporary,
            privateSystemDiscoveryIndex: nil,
            admitErase: { subject in
                // The real service mints its subject; this callback obtains
                // the Router's actual permit, then stops before gate reserve.
                let permit = try await fixture.router.eraseAdmissionAuthorization(
                    ticket, subject: subject)
                XCTAssertNotNil(permit)
                issued = permit != nil
                throw StopAfterRealAuthority.issued
            })
        let configured = try fixture.router.configureEraseService(service,
            operation: operation)
        fixture.retain(configured)
        do {
            _ = try await configured.erase(confirmation: "ERASE",
                coordinator: fixture.coordinator,
                diagnosticsStore: fixture.diagnostics,
                operation: operation, activate: { _ in
                    XCTFail("No replacement session may be activated")
                })
            XCTFail("The test must stop at genuine admission authorization")
        } catch StopAfterRealAuthority.issued {
            XCTAssertTrue(issued)
        }
        XCTAssertTrue(issued)
        XCTAssertThrowsError(try fixture.router.cancelUnadmittedErase(ticket)) {
            XCTAssertEqual($0 as? AppAccessContractFailureV1, .staleAttempt)
        }
        XCTAssertTrue(fixture.coordinator.workspaceWriter === writer)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.support
            .appendingPathComponent("FieldEvidenceErase").path))
    }

    private enum StopAfterRealAuthority: Error { case issued }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let type: mode_t

        init(at url: URL) throws {
            var value = stat()
            guard Darwin.lstat(url.path, &value) == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            device = value.st_dev
            inode = value.st_ino
            type = value.st_mode & S_IFMT
        }
    }

    @MainActor
    private final class Fixture {
        private static var retained: [Fixture] = []
        private static var provisionalOwners: [(URL, StartupRouter, AppAccessGateV1)] = []
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let router: StartupRouter
        let gate: AppAccessGateV1
        let coordinator: StoreSessionCoordinator
        let diagnostics: DiagnosticsStore
        private var retainedServices: [EraseAllService] = []

        private init(root: URL, support: URL, caches: URL, temporary: URL,
            router: StartupRouter, gate: AppAccessGateV1,
            coordinator: StoreSessionCoordinator, diagnostics: DiagnosticsStore) {
            self.root = root
            self.support = support
            self.caches = caches
            self.temporary = temporary
            self.router = router
            self.gate = gate
            self.coordinator = coordinator
            self.diagnostics = diagnostics
        }

        static func start(_ label: String) async throws -> Fixture {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("unadmitted-router-\(label)-\(UUID().uuidString)")
            let support = root.appendingPathComponent("Library/Application Support")
            let caches = root.appendingPathComponent("Library/Caches")
            let temporary = root.appendingPathComponent("tmp")
            for url in [support, caches, temporary] {
                try FileManager.default.createDirectory(at: url,
                                                        withIntermediateDirectories: true)
            }
            let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
                authentication: UnadmittedReturnAuthentication(),
                clock: SystemApplicationClock(), identifiers: SystemApplicationIDSource())
            let runtime = StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } })
            let router = StartupRouter(applicationSupportURL: support,
                entitlementRuntime: runtime)
            // Retain the owner and root before startup can allocate anything.
            provisionalOwners.append((root, router, gate))
            guard await gate.authenticate(trigger: .unlock) == .authenticated else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try router.bindStartupAccessGate(gate)
            try await router.startIfNeeded(accessGate: gate)
            guard case .ready(let coordinator, let diagnostics, _) = router.route else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let fixture = Fixture(root: root, support: support, caches: caches,
                temporary: temporary, router: router, gate: gate,
                coordinator: coordinator, diagnostics: diagnostics)
            // An uncertain source/descriptor must remain owned. Retain every
            // actual root and owner through host termination in all outcomes.
            retained.append(fixture)
            FileHandle.standardError.write(Data((
                "V23_UNADMITTED_ROUTER_RETAINED_V1 root=\(root.path) " +
                "retention=until-host-termination\n").utf8))
            return fixture
        }

        func retain(_ service: EraseAllService) { retainedServices.append(service) }
    }
}

private actor UnadmittedReturnAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1)
        -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}
