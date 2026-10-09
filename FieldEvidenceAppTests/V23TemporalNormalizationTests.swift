import Foundation
import XCTest
import Darwin

@testable import FieldEvidenceApp

final class V23TemporalNormalizationTests: XCTestCase {
    // These tests establish actual registry/directory-lock behavior only.
    // They do not mint canonical normalization or content deletion authority.
    func testProducerActivityRetainsSharedExclusionUntilLastIndependentHandleCloses() throws {
        let root = try makeRoot()
        var fixtureCleanupAllowed = true
        defer { if fixtureCleanupAllowed { try? FileManager.default.removeItem(at: root) } }
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
        var exclusiveCloseStarted = false
        defer {
            if !exclusiveCloseStarted {
                exclusiveCloseStarted = true
                do { try closeNormalizationActivityChecked(exclusive, onUncertain: { fixtureCleanupAllowed = false }) }
                catch { XCTFail("EX checked cleanup failed: \(error)") }
            }
        }
        try registry.validateTemporalNormalizationActivity(exclusive, retainedWriter: writer)
        // Ordinary validation enters G through SH; the retained EX-specific
        // census above is the live-writer proof while normalization owns EX.
        XCTAssertThrowsError(try registry.validateActive(writer, requiredRole: .writer)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
        }
        exclusiveCloseStarted = true
        try closeNormalizationActivityChecked(exclusive, onUncertain: { fixtureCleanupAllowed = false })
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
        var fixtureCleanupAllowed = true
        defer { if fixtureCleanupAllowed { try? FileManager.default.removeItem(at: root) } }
        let owner = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let observer = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        try withIndependentMutationLockChallenge(at: root, onUncertain: { fixtureCleanupAllowed = false }) {
            requireContended, requireAvailable in
            // First bind the independent descriptor challenge to Registry's
            // actual G. Mere availability of another file is insufficient.
            try owner.withExclusiveGenerationMutationLock {
                try requireContended()
            }
            let exclusive = try owner.acquireTemporalNormalizationActivity(retainedWriter: nil)
            var exclusiveCloseStarted = false
            defer {
                if !exclusiveCloseStarted {
                    exclusiveCloseStarted = true
                    do { try closeNormalizationActivityChecked(exclusive, onUncertain: { fixtureCleanupAllowed = false }) }
                    catch { XCTFail("EX checked cleanup failed: \(error)") }
                }
            }
            XCTAssertThrowsError(try observer.acquire(epoch: makeProtocolEpoch(), role: .reader)) {
                XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
            }
            try owner.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil)
            // Both independently opened descriptions take actual G while EX
            // remains live, with peer contention and checked unlock controls.
            try requireAvailable()
            try owner.validateTemporalNormalizationActivity(exclusive, retainedWriter: nil)
            exclusiveCloseStarted = true
            try closeNormalizationActivityChecked(exclusive, onUncertain: { fixtureCleanupAllowed = false })
        }
        // Reader registration changes the census and therefore takes SH. Its
        // positive acquisition/validation/release follows checked EX release.
        let reader = try observer.acquire(epoch: makeProtocolEpoch(), role: .reader)
        try observer.validateActive(reader, requiredRole: .reader)
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

    // A failed existing checked-close call can leave an ambiguous live EX.
    // Keep that actual owner until process end, so deinit cannot retry it.
    private final class UncertainNormalizationActivities: @unchecked Sendable {
        private let lock = NSLock()
        private var activities: [GenerationTemporalActivityHandleV1] = []

        func retain(_ activity: GenerationTemporalActivityHandleV1) {
            lock.lock()
            defer { lock.unlock() }
            activities.append(activity)
        }
    }

    private static let uncertainNormalizationActivities = UncertainNormalizationActivities()

    private func closeNormalizationActivityChecked(_ activity: GenerationTemporalActivityHandleV1,
        onUncertain: () -> Void) throws {
        do { try activity.closeCheckedForMaintenance() }
        catch {
            onUncertain()
            Self.uncertainNormalizationActivities.retain(activity)
            throw error
        }
    }

    // This private fixture owns only its read-only descriptions of the real
    // named G file. It grants no normalization, lease or deletion authority.
    private struct MutationLockFact: Equatable {
        let device: dev_t
        let inode: ino_t
        let links: nlink_t
        let mode: mode_t
        let owner: uid_t
        let group: gid_t
        let byteCount: off_t
        let metadata: [Int64]

        init(_ information: stat) {
            device = information.st_dev
            inode = information.st_ino
            links = information.st_nlink
            mode = information.st_mode
            owner = information.st_uid
            group = information.st_gid
            byteCount = information.st_size
            // Access time can change through these observations. All other
            // physical metadata below must remain equal across the challenge.
            metadata = [Int64(information.st_flags), Int64(information.st_gen),
                Int64(information.st_blocks), Int64(information.st_blksize),
                Int64(information.st_birthtimespec.tv_sec), Int64(information.st_birthtimespec.tv_nsec),
                Int64(information.st_mtimespec.tv_sec), Int64(information.st_mtimespec.tv_nsec),
                Int64(information.st_ctimespec.tv_sec), Int64(information.st_ctimespec.tv_nsec)]
        }
    }

    private func mutationLockFailure(_ stage: String, _ savedErrno: Int32 = 0) -> NSError {
        NSError(domain: "V23TemporalNormalizationTests.PhysicalG", code: Int(savedErrno),
            userInfo: [NSLocalizedDescriptionKey: stage + " errno=" + String(savedErrno)])
    }

    private func mutationLockFact(_ descriptor: Int32) throws -> MutationLockFact {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw mutationLockFailure("fstat", errno)
        }
        return MutationLockFact(information)
    }

    private func mutationLockBytes(_ descriptor: Int32, byteCount: off_t) throws -> Data {
        guard byteCount >= 0,
              byteCount <= off_t(GenerationLeaseRegistryV1.maximumControlFileBytes) else {
            throw mutationLockFailure("G content bound")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < Int(byteCount) {
            let count = min(buffer.count, Int(byteCount) - data.count)
            let returned = buffer.withUnsafeMutableBytes {
                Darwin.pread(descriptor, $0.baseAddress, count, off_t(data.count))
            }
            guard returned > 0, returned <= count else {
                throw mutationLockFailure("G content read", errno)
            }
            data.append(contentsOf: buffer.prefix(returned))
        }
        var extra: UInt8 = 0
        guard Darwin.pread(descriptor, &extra, 1, byteCount) == 0 else {
            throw mutationLockFailure("G exact content length", errno)
        }
        return data
    }

    private func withCheckedMutationLock(_ descriptor: Int32,
        _ operation: () throws -> Void) throws {
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw mutationLockFailure("G nonblocking acquisition", errno)
        }
        var firstError: Error?
        do { try operation() } catch { firstError = error }
        // One attempt even if the body failed. No defer or retry can repeat an
        // ambiguous unlock, and cleanup cannot replace the body's first error.
        let returned = flock(descriptor, LOCK_UN)
        let savedErrno = errno
        if returned != 0 {
            let failure = mutationLockFailure("G checked unlock", savedErrno)
            if firstError == nil { firstError = failure }
            else { XCTFail("secondary G unlock failure: \(failure)") }
        }
        if let firstError { throw firstError }
    }

    private func requireMutationLockContention(_ descriptor: Int32) throws {
        let returned = flock(descriptor, LOCK_EX | LOCK_NB)
        let savedErrno = errno
        if returned == 0 {
            // Unexpected success still owns a real lock and must dispose of it
            // once before reporting that the contention control failed.
            let unlocked = flock(descriptor, LOCK_UN)
            let unlockErrno = errno
            if unlocked != 0 { XCTFail("unexpected G acquisition unlock errno=\(unlockErrno)") }
            throw mutationLockFailure("expected G contention, acquired instead")
        }
        guard returned == -1, savedErrno == EWOULDBLOCK || savedErrno == EAGAIN else {
            throw mutationLockFailure("expected G contention refusal", savedErrno)
        }
    }

    private func withIndependentMutationLockChallenge(at root: URL, onUncertain: () -> Void,
        _ operation: (_ requireContended: () throws -> Void,
                      _ requireAvailable: () throws -> Void) throws -> Void) throws {
        var descriptors: [Int32] = []
        var bindings: [(descriptor: Int32, parent: Int32, name: String, fact: MutationLockFact)] = []
        var firstError: Error?
        func openNamed(_ parent: Int32, _ name: String, directory: Bool) throws -> Int32 {
            let flags = O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (directory ? O_DIRECTORY : 0)
            let descriptor = Darwin.openat(parent, name, flags)
            guard descriptor >= 0 else { throw mutationLockFailure("open named " + name, errno) }
            descriptors.append(descriptor) // Retain before any subsequent throw.
            let fact = try mutationLockFact(descriptor)
            guard fact.mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
                  directory ? fact.links > 0 : fact.links == 1 else {
                throw mutationLockFailure("named object type/link count " + name)
            }
            bindings.append((descriptor, parent, name, fact))
            return descriptor
        }
        do {
            let rootDescriptor = try openNamed(AT_FDCWD, root.path, directory: true)
            let operations = try openNamed(rootDescriptor, "FieldEvidenceOperations", directory: true)
            let leases = try openNamed(operations, "generation-leases", directory: true)
            let holder = try openNamed(leases, "mutation.lock", directory: false)
            let contender = try openNamed(leases, "mutation.lock", directory: false)
            guard holder != contender,
                  try mutationLockFact(holder) == mutationLockFact(contender) else {
                throw mutationLockFailure("independent G descriptions name different objects")
            }
            let originalFact = try mutationLockFact(holder)
            let originalBytes = try mutationLockBytes(holder, byteCount: originalFact.byteCount)
            func verify() throws {
                for binding in bindings {
                    var named = stat()
                    guard Darwin.fstatat(binding.parent, binding.name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
                        throw mutationLockFailure("G named reproof " + binding.name, errno)
                    }
                    guard MutationLockFact(named) == binding.fact,
                          try mutationLockFact(binding.descriptor) == binding.fact else {
                        throw mutationLockFailure("G held/named object changed " + binding.name)
                    }
                }
                guard try mutationLockBytes(holder, byteCount: originalFact.byteCount) == originalBytes,
                      try mutationLockBytes(contender, byteCount: originalFact.byteCount) == originalBytes,
                      try mutationLockFact(holder) == originalFact,
                      try mutationLockFact(contender) == originalFact else {
                    throw mutationLockFailure("G physical content changed")
                }
            }
            try verify()
            try operation({
                try verify()
                try requireMutationLockContention(contender)
                try verify()
            }, {
                try verify()
                try withCheckedMutationLock(holder) {
                    try verify()
                    try requireMutationLockContention(contender)
                    try verify()
                }
                try verify()
                try withCheckedMutationLock(contender) {
                    try verify()
                    try requireMutationLockContention(holder)
                    try verify()
                }
                try verify()
            })
            try verify()
        } catch { firstError = error }
        // Every opened description receives exactly one checked close attempt,
        // including partial construction and failure paths; no numeric FD retry.
        for descriptor in descriptors.reversed() {
            let returned = Darwin.close(descriptor)
            let savedErrno = errno
            if returned != 0 {
                onUncertain()
                let failure = mutationLockFailure("G checked close", savedErrno)
                if firstError == nil { firstError = failure }
                else { XCTFail("secondary G close failure: \(failure)") }
            }
        }
        if let firstError { throw firstError }
    }
}
