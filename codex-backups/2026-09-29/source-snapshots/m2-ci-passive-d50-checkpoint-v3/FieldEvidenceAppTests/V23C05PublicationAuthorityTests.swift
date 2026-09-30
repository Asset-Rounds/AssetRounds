import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23C05PublicationAuthorityTests: XCTestCase {
    @MainActor
    func testOriginalC05PublicationAuthorityBindsExactWriterRegistryAndEpoch() throws {
        let root = try makeApplicationSupport(label: "c05-publication-authority")
        let pin = V23C05OwnerPin(root: root)
        V23C05HostLifetime.pins.append(pin)
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        pin.session = session
        let epoch = try factory.currentGenerationEpoch()
        XCTAssertEqual(session.generationEpoch, epoch)
        let registry = try factory.makeGenerationLeaseRegistry()
        pin.registry = registry
        let writer = try registry.acquireHandle(epoch: epoch, role: .writer)
        pin.writer = writer
        let foreignRegistry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        pin.foreignRegistry = foreignRegistry
        let counter = V23C05PublicationEffectCounter()
        let job = try ResumableLocalJobV1(
            workspaceID: UUID(), kind: .render,
            immutableInputSHA256: String(repeating: "a", count: 64),
            stagingRelativePath: "c05-authority/render",
            generationEpoch: epoch,
            createdAt: Date(timeIntervalSinceReferenceDate: 230_205),
            checkpoint: LocalJobCheckpointV1(
                nextChunkIndex: 0, completedUnitCount: 0, totalUnitCount: 1)
        )

        let adapter = try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writer, expectedEpoch: epoch)
        XCTAssertEqual(try adapter.publish(job: job) {
            counter.increment()
            return .absent
        }, .absent)
        XCTAssertEqual(counter.value, 1)

        // A second registry over the same physical root is not this writer's
        // retained owner. It cannot create a publication adapter.
        XCTAssertThrowsError(try foreignRegistry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writer, expectedEpoch: epoch)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        let wrongEpoch = try GenerationEpochV1(
            generationID: UUID(),
            generationManifestSHA256: epoch.generationManifestSHA256)
        XCTAssertThrowsError(try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writer, expectedEpoch: wrongEpoch)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .wrongLeaseRole)
        }
        let staleWriter = try registry.acquireHandle(epoch: wrongEpoch, role: .writer)
        pin.staleWriter = staleWriter
        XCTAssertThrowsError(try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: staleWriter, expectedEpoch: wrongEpoch)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .staleGeneration)
        }
        try staleWriter.close()

        try writer.close()
        XCTAssertThrowsError(try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writer, expectedEpoch: epoch)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .leaseNotActive)
        }
        XCTAssertThrowsError(try adapter.publish(job: job) {
            counter.increment()
            return .absent
        }) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .leaseNotActive)
        }
        XCTAssertEqual(counter.value, 1)
        let retainedSourceReader = try XCTUnwrap(session.readerLeaseToken)
        try registry.validateActive(retainedSourceReader, requiredRole: .reader)
        XCTAssertEqual(try registry.activeEpochs(), Set([epoch]))
        XCTAssertThrowsError(try registry.validateActive(
            writer.token, requiredRole: .writer)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .leaseNotActive)
        }
        XCTAssertThrowsError(try registry.validateActive(
            staleWriter.token, requiredRole: .writer)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .leaseNotActive)
        }
    }

    #if DEBUG
    @MainActor
    func testOriginalC05PublicationCloseUncertaintyPermanentlyRefusesEffect() throws {
        let root = try makeApplicationSupport(label: "c05-uncertain-close")
        let pin = V23C05OwnerPin(root: root)
        V23C05HostLifetime.pins.append(pin)
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        pin.session = session
        let epoch = try factory.currentGenerationEpoch()
        let registry = try factory.makeGenerationLeaseRegistry()
        pin.registry = registry
        let writer = try registry.acquireHandle(epoch: epoch, role: .writer)
        pin.writer = writer
        let adapter = try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writer, expectedEpoch: epoch)
        let counter = V23C05PublicationEffectCounter()
        let job = try ResumableLocalJobV1(
            workspaceID: UUID(), kind: .render,
            immutableInputSHA256: String(repeating: "b", count: 64),
            stagingRelativePath: "c05-uncertain/render",
            generationEpoch: epoch,
            createdAt: Date(timeIntervalSinceReferenceDate: 230_206),
            checkpoint: LocalJobCheckpointV1(
                nextChunkIndex: 0, completedUnitCount: 0, totalUnitCount: 1)
        )
        registry.injectLocalJobPublicationCloseFailureOnceForTesting()
        XCTAssertThrowsError(try adapter.publish(job: job) {
            counter.increment()
            return .absent
        }) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        XCTAssertEqual(counter.value, 0)
        XCTAssertThrowsError(try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writer, expectedEpoch: epoch)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        XCTAssertThrowsError(try adapter.publish(job: job) {
            counter.increment()
            return .absent
        }) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        XCTAssertEqual(counter.value, 0)
        // The exact opened descriptor, registry, writer, session and root stay
        // host-retained. A failed close is not converted to a deinit proof.
    }
    #endif

    @MainActor
    private func makeApplicationSupport(label: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23C05PublicationAuthorityTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

private final class V23C05PublicationEffectCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@MainActor
private final class V23C05OwnerPin {
    let root: URL
    var session: StoreGenerationSession?
    var registry: GenerationLeaseRegistryV1?
    var foreignRegistry: GenerationLeaseRegistryV1?
    var writer: GenerationLeaseHandleV1?
    var staleWriter: GenerationLeaseHandleV1?
    init(root: URL) { self.root = root }
}

@MainActor
private enum V23C05HostLifetime {
    static var pins: [V23C05OwnerPin] = []
}
