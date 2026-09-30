import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23WholeSignSharedOwnerTests: XCTestCase {
    @MainActor private static var retainedServices: [WholeSignDeletionService] = []

    @MainActor
    private struct Fixture {
        let root: URL
        let support: URL
        let owner: V23EraseOperationHarnessV1
        let coordinator: StoreSessionCoordinator

        static func start(_ label: String) async throws -> Self {
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("whole-sign-shared-owner-\(label)-\(UUID().uuidString)")
            let support = root.appendingPathComponent("Library/Application Support")
            for directory in [support,
                              root.appendingPathComponent("Library/Caches"),
                              root.appendingPathComponent("tmp")] {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
            }
            let runtime = StoreKitEntitlementRuntimeV1(
                initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } })
            let owner = V23EraseOperationHarnessV1(
                retainingRoot: root, applicationSupportURL: support,
                runtime: runtime,
                profileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
            let (coordinator, _) = try await owner.startOriginalOwner()
            return Self(root: root, support: support, owner: owner,
                        coordinator: coordinator)
        }

        func createFirstSign() throws -> UUID {
            let siteID = UUID(), assetID = UUID(), mutationID = UUID()
            _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "Shared-owner site",
                    address: nil, timeZoneID: nil),
                assetID: assetID,
                assetLabel: "Shared-owner asset",
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                createdAt: Date(),
                initialPlacementMutationID: try MutationIDV1(rawValue: mutationID),
                initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
            )), mutationID: try MutationIDV1(rawValue: mutationID))
            return assetID
        }

        func ledger() throws -> DeletionLedgerV2 {
            try DeletionLedgerStore(context: coordinator.modelContext).snapshot()
        }
    }

    @MainActor
    func testLiveDeleteUsesPublishedWriterAndProducesRealAssetTombstone() async throws {
        let fixture = try await Fixture.start("delete")
        let assetID = try fixture.createFirstSign()
        let writer = fixture.coordinator.workspaceWriter
        let dependencies = try fixture.coordinator.packageLifecycleDependencies()
        let before = try fixture.ledger()
        XCTAssertFalse(before.entries.contains {
            $0.identity.kind == .asset && $0.identity.id == assetID
        })

        let service = try WholeSignDeletionService(
            modelContext: fixture.coordinator.modelContext,
            lifecycleDependencies: dependencies,
            storeSession: fixture.coordinator)
        Self.retainedServices.append(service)
        XCTAssertTrue(fixture.coordinator.workspaceWriter === writer)
        let outcome = try await service.delete(assetID: assetID)

        XCTAssertEqual(outcome.assetID, assetID)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<Asset>()), 0)
        XCTAssertTrue(try fixture.ledger().entries.contains {
            $0.identity.kind == .asset && $0.identity.id == assetID
        })
        XCTAssertTrue(fixture.coordinator.workspaceWriter === writer)
        try MutationJournalStoreV1(
            modelContext: fixture.coordinator.modelContext,
            identity: fixture.coordinator.workspaceIdentity,
            generationID: fixture.coordinator.generationID,
            allowStateBootstrap: false).validateAll()
    }

    @MainActor
    func testDirectSharedCommitWithoutAdmittedProducerRefusesBeforeBody() async throws {
        let fixture = try await Fixture.start("direct-commit")
        let dependencies = try fixture.coordinator.packageLifecycleDependencies()
        let fence = try fixture.coordinator.wholeSignDeletionSharedFence(
            expectedContext: fixture.coordinator.modelContext,
            dependencies: dependencies)
        var entered = false
        XCTAssertThrowsError(try fixture.coordinator.withWholeSignDeletionCommit(
            expectedContext: fixture.coordinator.modelContext,
            dependencies: dependencies,
            expectedFence: fence
        ) {
            entered = true
        }) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        XCTAssertFalse(entered)
    }

    @MainActor
    func testForeignContextAndWriterRefuseBeforeDeletionEffects() async throws {
        let original = try await Fixture.start("original")
        let foreign = try await Fixture.start("foreign")
        _ = try original.createFirstSign()
        let originalDependencies = try original.coordinator.packageLifecycleDependencies()
        let foreignDependencies = try foreign.coordinator.packageLifecycleDependencies()
        let before = try original.ledger()
        let revision = try original.coordinator.workspaceWriter.currentRevision()

        XCTAssertThrowsError(try WholeSignDeletionService(
            modelContext: foreign.coordinator.modelContext,
            lifecycleDependencies: originalDependencies,
            storeSession: original.coordinator)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .staleGeneration)
        }
        XCTAssertThrowsError(try WholeSignDeletionService(
            modelContext: original.coordinator.modelContext,
            lifecycleDependencies: foreignDependencies,
            storeSession: original.coordinator)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .staleGeneration)
        }
        XCTAssertEqual(try original.coordinator.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try original.ledger(), before)
        XCTAssertEqual(try original.coordinator.modelContext.fetchCount(
            FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testClosedOriginalWriterRefusesSharedDeletionWithoutLedgerChange() async throws {
        let fixture = try await Fixture.start("stale")
        let assetID = try fixture.createFirstSign()
        let dependencies = try fixture.coordinator.packageLifecycleDependencies()
        let service = WholeSignDeletionService(
            modelContext: fixture.coordinator.modelContext,
            lifecycleDependencies: dependencies)
        Self.retainedServices.append(service)
        let before = try fixture.ledger()
        try fixture.coordinator.invalidateAndReleaseWriter()

        do {
            _ = try await service.delete(assetID: assetID)
            XCTFail("Closed writer authorized a deletion")
        } catch {
            XCTAssertTrue(error is GenerationLeaseRegistryFailureV1
                || error as? WholeSignDeletionServiceError == .invalidGeneration)
        }
        XCTAssertEqual(try fixture.ledger(), before)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testAdmittedProducerDrainsBeforeOriginalEraseCanCaptureWriter() async throws {
        let fixture = try await Fixture.start("producer-drain")
        _ = try fixture.createFirstSign()
        let before = try fixture.ledger()
        let producerGate = ProducerGate()
        let producer = Task<Void, Error> { @MainActor in
            try await fixture.coordinator.withTemporalProducer {
                await producerGate.enterAndWait()
            }
        }
        await producerGate.waitUntilEntered()
        do {
            _ = try await fixture.owner.router.beginEraseOperation(
                coordinator: fixture.coordinator,
                accessGate: fixture.owner.accessGate)
            XCTFail("Router captured a writer with an admitted producer")
        } catch {
            XCTAssertEqual(error as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        XCTAssertEqual(try fixture.ledger(), before)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<Asset>()), 1)
        producerGate.release()
        try await producer.value
        let ticket = try await fixture.owner.router.beginEraseOperation(
            coordinator: fixture.coordinator,
            accessGate: fixture.owner.accessGate)
        try fixture.owner.router.cancelUnadmittedErase(ticket)
        try await fixture.owner.router.startIfNeeded(accessGate: fixture.owner.accessGate)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try fixture.ledger(), before)
    }

    @MainActor
    func testEraseCaptureRefusesDeletionUntilExactAuthenticatedReturn() async throws {
        let fixture = try await Fixture.start("return")
        let assetID = try fixture.createFirstSign()
        let dependencies = try fixture.coordinator.packageLifecycleDependencies()
        let service = try WholeSignDeletionService(
            modelContext: fixture.coordinator.modelContext,
            lifecycleDependencies: dependencies,
            storeSession: fixture.coordinator)
        Self.retainedServices.append(service)
        let writer = fixture.coordinator.workspaceWriter
        let before = try fixture.ledger()
        let revision = try writer.currentRevision()
        let ticket = try await fixture.owner.router.beginEraseOperation(
            coordinator: fixture.coordinator,
            accessGate: fixture.owner.accessGate)
        do {
            _ = try await service.delete(assetID: assetID)
            XCTFail("A captured Erase source admitted new Whole Sign deletion")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .invalidGeneration)
        }
        XCTAssertEqual(try fixture.ledger(), before)
        XCTAssertEqual(try writer.currentRevision(), revision)

        try fixture.owner.router.cancelUnadmittedErase(ticket)
        do {
            _ = try await service.delete(assetID: assetID)
            XCTFail("An unadmitted return reopened deletion before authenticated publication")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .invalidGeneration)
        }
        XCTAssertEqual(try fixture.ledger(), before)
        try await fixture.owner.router.startIfNeeded(accessGate: fixture.owner.accessGate)
        guard case let .ready(republished, _, _) = fixture.owner.router.route else {
            return XCTFail("The exact original writer was not republished")
        }
        XCTAssertTrue(republished === fixture.coordinator)
        XCTAssertTrue(republished.workspaceWriter === writer)
        let outcome = try await service.delete(assetID: assetID)
        XCTAssertEqual(outcome.assetID, assetID)
        XCTAssertTrue(try fixture.ledger().entries.contains {
            $0.identity.kind == .asset && $0.identity.id == assetID
        })
    }

    @MainActor
    func testForeignAndRelockedEraseReturnCannotReopenDeletion() async throws {
        let fixture = try await Fixture.start("refused-return")
        let foreign = try await Fixture.start("foreign-return")
        let assetID = try fixture.createFirstSign()
        let before = try fixture.ledger()
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let service = try WholeSignDeletionService(
            modelContext: fixture.coordinator.modelContext,
            lifecycleDependencies: fixture.coordinator.packageLifecycleDependencies(),
            storeSession: fixture.coordinator)
        Self.retainedServices.append(service)
        let ticket = try await fixture.owner.router.beginEraseOperation(
            coordinator: fixture.coordinator,
            accessGate: fixture.owner.accessGate)
        let foreignTicket = try await foreign.owner.router.beginEraseOperation(
            coordinator: foreign.coordinator,
            accessGate: foreign.owner.accessGate)
        XCTAssertThrowsError(try fixture.owner.router.cancelUnadmittedErase(foreignTicket)) {
            XCTAssertEqual($0 as? AppAccessContractFailureV1, .staleAttempt)
        }
        await fixture.owner.accessGate.lock(reason: .interrupted)
        XCTAssertThrowsError(try fixture.owner.router.cancelUnadmittedErase(ticket))
        do {
            _ = try await service.delete(assetID: assetID)
            XCTFail("A foreign or uncertain return reopened deletion")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .invalidGeneration)
        }
        XCTAssertEqual(try fixture.ledger(), before)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    private final class ProducerGate {
        private var entered = false
        private var released = false
        private var enteredWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func enterAndWait() async {
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
            guard !released else { return }
            await withCheckedContinuation { releaseWaiter = $0 }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { enteredWaiter = $0 }
        }

        func release() {
            released = true
            releaseWaiter?.resume()
            releaseWaiter = nil
        }
    }
}
