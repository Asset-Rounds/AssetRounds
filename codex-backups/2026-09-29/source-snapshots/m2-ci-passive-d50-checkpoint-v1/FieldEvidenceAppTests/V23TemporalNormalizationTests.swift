import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23TemporalNormalizationTests: XCTestCase {
    // These tests establish actual registry/directory-lock behavior only.
    // They do not mint canonical normalization or content deletion authority.
    func testProducerActivityRetainsSharedExclusionUntilLastIndependentHandleCloses() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let writer = try registry.acquire(epoch: makeProtocolEpoch(), role: .writer)
        defer { try? registry.release(writer) }
        let first = try registry.acquireTemporalProducerActivity(writer: writer)
        defer { first.close() }
        let second = try registry.acquireTemporalProducerActivity(writer: writer)
        defer { second.close() }
        XCTAssertThrowsError(try registry.acquireTemporalNormalizationActivity(retainedWriter: writer))
        first.close()
        try registry.validateTemporalProducerActivity(second, writer: writer)
        XCTAssertThrowsError(try registry.acquireTemporalNormalizationActivity(retainedWriter: writer))
        second.close()
        let exclusive = try registry.acquireTemporalNormalizationActivity(retainedWriter: writer)
        defer { exclusive.close() }
        try registry.validateTemporalNormalizationActivity(exclusive, retainedWriter: writer)
        try registry.validateActive(writer, requiredRole: .writer)
    }

    func testExclusiveActivityRejectsProducerAndWriterAdmissionWithoutChangingRegistryBytes() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let writer = try registry.acquire(epoch: makeProtocolEpoch(), role: .writer)
        defer { try? registry.release(writer) }
        // Construct the second real owner before the target registry byte
        // observation; its acquisition effects are not normalization effects.
        let foreign = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let control = root.appendingPathComponent("FieldEvidenceOperations/generation-leases/registry.json")
        let before = try Data(contentsOf: control)
        let exclusive = try registry.acquireTemporalNormalizationActivity(retainedWriter: writer)
        defer { exclusive.close() }
        XCTAssertThrowsError(try registry.acquireTemporalProducerActivity(writer: writer))
        XCTAssertThrowsError(try foreign.acquire(epoch: writer.epoch, role: .writer))
        XCTAssertThrowsError(try registry.acquire(epoch: writer.epoch, role: .writer))
        XCTAssertEqual(try Data(contentsOf: control), before)
        exclusive.close()
        let producer = try registry.acquireTemporalProducerActivity(writer: writer)
        producer.close()
        let admitted = try foreign.acquire(epoch: writer.epoch, role: .writer)
        try foreign.release(admitted)
        XCTAssertEqual(try Data(contentsOf: control), before)
    }

    func testNoWriterNormalizationRefusesAnIdleForeignWriter() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let observer = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let owner = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let writer = try owner.acquire(epoch: makeProtocolEpoch(), role: .writer)
        defer { try? owner.release(writer) }
        XCTAssertThrowsError(try observer.acquireTemporalNormalizationActivity(retainedWriter: nil))
        XCTAssertThrowsError(try observer.acquireTemporalNormalizationActivity(retainedWriter: writer))
        try owner.validateActive(writer, requiredRole: .writer)
        try owner.release(writer)
        let exclusive = try observer.acquireTemporalNormalizationActivity(retainedWriter: nil)
        defer { exclusive.close() }
        try observer.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil)
    }

    func testClosedActivityAndWrongRegistryCannotRevalidateAsLiveOwnership() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let other = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let exclusive = try owner.acquireTemporalNormalizationActivity(retainedWriter: nil)
        defer { exclusive.close() }
        XCTAssertThrowsError(try other.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil))
        try owner.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil)
        exclusive.close()
        exclusive.close()
        XCTAssertThrowsError(try owner.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil))
        let next = try other.acquireTemporalNormalizationActivity(retainedWriter: nil)
        next.close()
    }

    func testExclusiveActivityDoesNotRetainGenerationMutationLock() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let observer = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let exclusive = try owner.acquireTemporalNormalizationActivity(retainedWriter: nil)
        defer { exclusive.close() }
        // An independently opened registry takes actual G and registers a
        // reader while activity EX remains held. No sleep/timing inference.
        let reader = try observer.acquire(epoch: makeProtocolEpoch(), role: .reader)
        try observer.validateActive(reader, requiredRole: .reader)
        try owner.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil)
        try observer.release(reader)
    }

    func testM1ObservationDoesNotCreateAbsentNamespace() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let observed = try TemporalOperationalJournalObservationV1.prepare(generationRootURL: root)
        XCTAssertFalse(observed.namespaceExists)
        XCTAssertTrue(observed.published.isEmpty)
        XCTAssertNil(observed.pending)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), before)
    }

    func testM1ObservationIncludesFinishedAndPreservesMalformedSibling() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try observationReservation()
        let store = try observationStore(root, reservation)
        try await store.prepare(reservation)
        try await store.transition(reservation, to: .finished)
        let namespace = root.appendingPathComponent("operational/temporal-evidence-promotion-v1")
        let path = namespace.appendingPathComponent(reservation.workspaceID.rawValue.uuidString.lowercased() + ".json")
        let before = try Data(contentsOf: path)
        let observed = try TemporalOperationalJournalObservationV1.prepare(generationRootURL: root)
        XCTAssertTrue(observed.namespaceExists)
        XCTAssertEqual(observed.published.count, 1)
        XCTAssertEqual(observed.published.first?.canonicalData, before)
        XCTAssertEqual(observed.published.first?.promotions.first?.state, .finished)
        XCTAssertEqual(try Data(contentsOf: path), before)
        let unknown = namespace.appendingPathComponent("legacy-random-temp")
        let unknownBytes = Data("unknown publication retained".utf8)
        try unknownBytes.write(to: unknown)
        let names = try FileManager.default.contentsOfDirectory(atPath: namespace.path).sorted()
        XCTAssertThrowsError(try TemporalOperationalJournalObservationV1.prepare(generationRootURL: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: namespace.path).sorted(), names)
        XCTAssertEqual(try Data(contentsOf: unknown), unknownBytes)
        XCTAssertEqual(try Data(contentsOf: path), before)
    }

    func testM1ObservationDistinguishesPendingSuccessorFromPublishedWinnerWithoutRecoveryEffects() async throws {
        for boundary in [TemporalEvidenceOperationalPublicationBoundaryV2.durablePayload, .published] {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let reservation = try observationReservation()
            let store = try observationStore(root, reservation, boundary: boundary)
            do { try await store.prepare(reservation); XCTFail("expected actual publication boundary interruption") }
            catch ObservationStop.boundary { }
            let namespace = root.appendingPathComponent("operational/temporal-evidence-promotion-v1")
            let names = try FileManager.default.contentsOfDirectory(atPath: namespace.path).sorted()
            let slot = try XCTUnwrap(names.first { $0.hasPrefix(".tp2-") })
            let children = try FileManager.default.contentsOfDirectory(atPath: namespace.appendingPathComponent(slot).path)
            let observed = try TemporalOperationalJournalObservationV1.prepare(generationRootURL: root)
            let pending = try XCTUnwrap(observed.pending)
            XCTAssertEqual(pending.directoryName, slot)
            switch (boundary, pending.state) {
            case (.durablePayload, .unpublishedComplete):
                XCTAssertTrue(observed.published.isEmpty)
                XCTAssertEqual(pending.completePayload?.promotions, [reservation])
            case (.published, .published):
                XCTAssertEqual(observed.published.first?.promotions, [reservation])
                XCTAssertNil(pending.completePayload)
            default: XCTFail("incorrect winner classification")
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: namespace.path).sorted(), names)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: namespace.appendingPathComponent(slot).path), children)
        }
    }

    private enum ObservationStop: Error { case boundary, unexpectedContentPort }

    private func observationReservation() throws -> TemporalEvidencePromotionReservationV1 {
        let now = Date(timeIntervalSince1970: 1_820_000_000)
        let mutation = try MutationIDV1(rawValue: UUID()), leaseID = UUID()
        let request = try CapabilityScratchLeaseRequestV1(leaseID: leaseID, operationID: mutation.rawValue,
            purpose: .capture, requestedByteCount: 1024, createdAt: now, expiresAt: now.addingTimeInterval(60))
        let lease = CapabilityScratchLeaseV1(leaseID: leaseID, purpose: .capture,
            relativeDirectory: "capture-" + leaseID.uuidString.lowercased())
        let digest = String(repeating: "a", count: 64)
        let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: lease,
            mutationID: mutation, contentID: "observation-test", contentSHA256: digest)
        return try .init(workspaceID: WorkspaceID(rawValue: UUID()), mutationID: mutation,
            contentID: "observation-test", contentSHA256: digest, binding: binding, state: .prepared)
    }

    private func observationStore(_ root: URL, _ reservation: TemporalEvidencePromotionReservationV1,
                                  boundary: TemporalEvidenceOperationalPublicationBoundaryV2? = nil)
        throws -> TemporalEvidencePromotionRecoveryFileAdapterV1 {
        try .init(generationRootURL: root, workspaceID: reservation.workspaceID,
            publicationBoundary: { if $0 == boundary { throw ObservationStop.boundary } },
            verify: { _, _, _ in throw ObservationStop.unexpectedContentPort },
            remove: { _, _, _ in throw ObservationStop.unexpectedContentPort })
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23TemporalNormalizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeProtocolEpoch() throws -> GenerationEpochV1 {
        try .init(generationID: UUID(), generationManifestSHA256: String(repeating: "a", count: 64))
    }
}
