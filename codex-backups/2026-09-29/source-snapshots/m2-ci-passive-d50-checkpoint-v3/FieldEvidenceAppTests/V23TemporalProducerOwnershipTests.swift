import CryptoKit
import Darwin
import Foundation
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23TemporalProducerOwnershipTests: XCTestCase {
    // These are actual physical lifetime witnesses, not a canonical cleanup
    // authorization or evidence that every app producer has been inventoried.
    func testIndependentRetainedPhysicalChildBlocksCrossInstanceExclusion() throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let parent = try OwnedStorageProducerActivityV1.acquire(applicationSupportURL: support)
        let child = try parent.retain()
        parent.close()
        try child.requireApplicationSupport(support)
        try assertExclusive(support, available: false)
        let other = try OwnedStorageProducerActivityV1.acquire(applicationSupportURL: support)
        child.close()
        try assertExclusive(support, available: false)
        other.close()
        try assertExclusive(support, available: true)
        XCTAssertThrowsError(try child.retain())
    }

    @MainActor
    func testCancelledDetachedWorkerAndCatchTailKeepActualSessionProducerOwned() async throws {
        let support = try makeSupport()
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let owner = try StoreSessionCoordinator(validatingSession: session)
        let generationRoot = session.generationRootURL
        let media = EvidenceBundleStore(generationRootURL: generationRoot)
        let bytes = Data("detached producer preparation".utf8)
        let request = try immutableRequest(bytes)
        let preparationIdentity = NSObject()
        let preparationOwner = ObjectIdentifier(preparationIdentity)
        let started = Gate(), workerExit = Gate(), caught = Gate(), catchExit = Gate()
        let task = Task<Void, Error> { @MainActor in
            do {
                try await owner.withTemporalProducer {
                    let resource = try owner.retainTemporalProducerResource()
                    defer { resource.close() }
                    let worker = Task<Void, Error>.detached {
                        do {
                            try resource.requireActive(forGenerationRoot: generationRoot)
                            let prepared = try await media.prepareImmutableOriginal(bytes: bytes,
                                request: request, owner: preparationOwner)
                            defer { withExtendedLifetime(prepared) {} }
                            await started.open()
                            await workerExit.wait()
                            throw CancellationError()
                        } catch {
                            // A real preparation failure must reach the test,
                            // not strand its deterministic start handshake.
                            await started.open()
                            throw error
                        }
                    }
                    do {
                        try await withTaskCancellationHandler(operation: { try await worker.value },
                                                              onCancel: { worker.cancel() })
                    } catch {
                        await caught.open()
                        await catchExit.wait()
                        throw error
                    }
                }
            } catch {
                await started.open(); await caught.open()
                throw error
            }
        }
        await started.wait()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: generationRoot.path)
            .filter { $0.hasPrefix(".immutable-") }.count, 1, "Detached preparation reached its retained private file")
        task.cancel()
        XCTAssertThrowsError(try owner.invalidateAndReleaseWriter())
        await workerExit.open()
        await caught.wait()
        XCTAssertThrowsError(try owner.invalidateAndReleaseWriter(), "A returned worker does not settle its catch tail")
        await catchExit.open()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        try owner.invalidateAndReleaseWriter()
        try FileManager.default.removeItem(at: support)
    }

    func testActualImmutablePreparationRetainsPhysicalExclusionThroughPrivateCleanup() async throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let root = support.appendingPathComponent("FieldEvidenceData/generations/\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = EvidenceBundleStore(generationRootURL: root)
        let bytes = Data("retained-immutable-content".utf8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: .init(rawValue: UUID()),
            contentID: "producer-lifetime", digest: .init(algorithm: .sha256, hexadecimalValue: digest),
            byteLength: Int64(bytes.count), mediaType: "application/octet-stream",
            mutationID: .init(rawValue: UUID()), createdAt: "2026-09-27T00:00:00Z")
        let identity = NSObject()
        var prepared: EvidenceBundleStore.PreparedImmutableOriginal? = try await store.prepareImmutableOriginal(
            bytes: bytes, request: request, owner: ObjectIdentifier(identity))
        XCTAssertNotNil(prepared)
        try assertExclusive(support, available: false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".immutable-") }.count, 1)
        prepared = nil
        try assertExclusive(support, available: true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".immutable-") }.isEmpty)
    }

    @MainActor
    func testEscapedCandidateCopyRetainsActualSessionAndStagedMediaUntilTerminalRemoval() async throws {
        let support = try makeSupport()
        let generation = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let owner = try StoreSessionCoordinator(validatingSession: generation)
        let store = EvidenceBundleStore(generationRootURL: generation.generationRootURL)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let bytes = try XCTUnwrap(image.pngData())
        let normalized = try MediaNormalizerV1().normalize(bytes)
        let candidate = try await owner.withTemporalProducer {
            let lifetime = try CaptureCandidateProducerLifetimeV1(generationRootURL: generation.generationRootURL,
                session: .current(try owner.retainTemporalProducerResource()))
            let id = UUID()
            let staged = try await store.stage(evidenceID: id, normalized: normalized)
            return CaptureCandidate(id: id, recordID: UUID(), purposeKey: "test-capture", createdAt: Date(),
                previewJPEG: normalized.originalJPEG, stagedBundle: staged, producerLifetime: lifetime)
        }
        let escapedCopy = candidate
        XCTAssertEqual(candidate, escapedCopy, "Equality retains the incumbent metadata semantics")
        XCTAssertThrowsError(try owner.invalidateAndReleaseWriter())
        try assertExclusive(support, available: false)
        try await escapedCopy.producerLifetime.withCurrentProducer(for: owner) {
            try await store.discardStaging(evidenceID: escapedCopy.id)
        }
        escapedCopy.producerLifetime.finish()
        try assertExclusive(support, available: true)
        try owner.invalidateAndReleaseWriter()
        try FileManager.default.removeItem(at: support)
    }

    func testCancelledLeaseDoesNotDrainEscapedWritableSourceSink() async throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let store = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now },
                                               capacityProvider: { _ in Int64.max / 4 })
        let lease = try await store.acquireScratchLease(.init(leaseID: UUID(), purpose: .source,
            owner: .source, ownerOperationID: UUID(), requestedByteCount: 16,
            createdAt: now, expiresAt: now.addingTimeInterval(600)))
        let sink = try await store.makeEncryptedPortableEnvelopeStreamingScratch(
            named: "retained.bin", lease: lease, maximumByteCount: 16)
        let concrete = try XCTUnwrap(sink as? EncryptedPortableEnvelopeProtectedFileScratchV1)
        try sink.prepareForStreamingWrite(expectedByteCount: 1)
        try await store.releaseScratchLease(lease, terminal: .cancelled)
        try assertExclusive(support, available: false, "Lease cancellation is not descriptor drainage")
        concrete.closeResource()
        XCTAssertThrowsError(try sink.prepareForStreamingWrite(expectedByteCount: 1))
        XCTAssertThrowsError(try sink.appendStreamingBytes(Data([1])))
        try assertExclusive(support, available: true)
    }

    func testIndependentScratchInstanceCannotAcquireWhileActualSupportIsExclusive() async throws {
        let support = try makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let first = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now },
                                               capacityProvider: { _ in Int64.max / 4 })
        let second = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now },
                                                capacityProvider: { _ in Int64.max / 4 })
        let descriptor = Darwin.open(support.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let request = try ScratchDataLeaseRequestV1(leaseID: UUID(), purpose: .source, owner: .source,
            ownerOperationID: UUID(), requestedByteCount: 16, createdAt: now, expiresAt: now.addingTimeInterval(600))
        for store in [first, second] {
            do { _ = try await store.acquireScratchLease(request); XCTFail("Shared physical root is exclusively owned") }
            catch { }
        }
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        let lease = try await second.acquireScratchLease(request)
        try await second.releaseScratchLease(lease, terminal: .cancelled)
    }

    @MainActor
    func testActualNormalizationExclusionRejectsOrdinaryWriterRead() async throws {
        let support = try makeSupport()
        let generation = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let owner = try StoreSessionCoordinator(validatingSession: generation)
        _ = try owner.workspaceWriter.currentRevision()
        let exclusion = try await owner.drainTemporalProducersForNormalization()
        try exclusion.revalidate()
        XCTAssertThrowsError(try owner.workspaceWriter.currentRevision(),
                             "An ordinary writer read must not bypass the actual exclusive owner")
        try exclusion.closeForMaintenance()
        XCTAssertThrowsError(try owner.workspaceWriter.currentRevision())
        try FileManager.default.removeItem(at: support)
    }

    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            opened = true
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private func immutableRequest(_ bytes: Data) throws -> DraftImmutableContentWriteRequestV1 {
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return try .init(workspaceID: .init(rawValue: UUID()), contentID: "detached-producer",
            digest: .init(algorithm: .sha256, hexadecimalValue: digest), byteLength: Int64(bytes.count),
            mediaType: "application/octet-stream", mutationID: .init(rawValue: UUID()),
            createdAt: "2026-09-27T00:00:00Z")
    }

    private func makeSupport() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("V23-ProducerOwnership-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func assertExclusive(_ root: URL, available: Bool, _ message: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer { Darwin.close(descriptor) }
        let result = flock(descriptor, LOCK_EX | LOCK_NB)
        let failure = errno
        if result == 0 { flock(descriptor, LOCK_UN) }
        XCTAssertEqual(result == 0, available, message, file: file, line: line)
        if !available { XCTAssertEqual(failure, EWOULDBLOCK, file: file, line: line) }
    }
}
