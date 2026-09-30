import Darwin
import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23EraseUnadmittedControlObservationTests: XCTestCase {
    @MainActor
    func testAbsentRootAndEmptyRootAreObservedWithoutCreatingOrRepairing() throws {
        let fixture = try Fixture()
        let erase = fixture.support.appendingPathComponent("FieldEvidenceErase")

        let absent = fixture.observer()
        try absent.requireAbsent()
        XCTAssertEqual(absent.status, .absentAndClosed)
        XCTAssertEqual(absent.closeErrors, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: erase.path))

        try FileManager.default.createDirectory(at: erase, withIntermediateDirectories: false)
        let before = try identity(erase)
        let empty = fixture.observer()
        try empty.requireAbsent()
        XCTAssertEqual(empty.status, .absentAndClosed)
        XCTAssertEqual(empty.closeErrors, [])
        XCTAssertEqual(try identity(erase), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: erase.path), [])
    }

    @MainActor
    func testCanonicalPendingAndUnknownEntriesRefuseWithExactBytesAndInodes() throws {
        for name in ["erase.json", ".erase.json.next", "preparation.json",
                     ".preparation.json.next", "unexpected-control"] {
            let fixture = try Fixture()
            let erase = fixture.support.appendingPathComponent("FieldEvidenceErase")
            try FileManager.default.createDirectory(at: erase, withIntermediateDirectories: false)
            let leaf = erase.appendingPathComponent(name)
            let bytes = Data([0x00, 0xff, 0x27, 0x73, 0x10])
            try bytes.write(to: leaf)
            let rootBefore = try identity(erase)
            let leafBefore = try identity(leaf)
            let observer = fixture.observer()

            XCTAssertThrowsError(try observer.requireAbsent()) {
                XCTAssertEqual($0 as? EraseUnadmittedControlObservationV1.Failure,
                               .controlsPresent)
            }
            XCTAssertEqual(observer.status, .refused)
            try observer.closeAfterRefusal()
            XCTAssertEqual(observer.status, .refusedAndClosed)
            XCTAssertEqual(observer.closeErrors, [])
            XCTAssertEqual(try identity(erase), rootBefore)
            XCTAssertEqual(try identity(leaf), leafBefore)
            XCTAssertEqual(try Data(contentsOf: leaf), bytes)
        }
    }

    @MainActor
    func testHostileRootAndLeafRefuseWithoutFollowingOrRepairing() throws {
        let fixture = try Fixture()
        let target = fixture.container.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let targetLeaf = target.appendingPathComponent("sentinel")
        let bytes = Data([0xde, 0xad, 0xbe, 0xef])
        try bytes.write(to: targetLeaf)
        let erase = fixture.support.appendingPathComponent("FieldEvidenceErase")
        try FileManager.default.createSymbolicLink(at: erase, withDestinationURL: target)
        let rootLinkBefore = try identity(erase)
        let targetBefore = try identity(targetLeaf)
        let hostileRoot = fixture.observer()
        XCTAssertThrowsError(try hostileRoot.requireAbsent())
        try hostileRoot.closeAfterRefusal()
        XCTAssertEqual(try identity(erase), rootLinkBefore)
        XCTAssertEqual(try identity(targetLeaf), targetBefore)
        XCTAssertEqual(try Data(contentsOf: targetLeaf), bytes)

        try FileManager.default.removeItem(at: erase)
        try FileManager.default.createDirectory(at: erase, withIntermediateDirectories: false)
        let leaf = erase.appendingPathComponent("erase.json")
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: targetLeaf)
        let leafBefore = try identity(leaf)
        let hostileLeaf = fixture.observer()
        XCTAssertThrowsError(try hostileLeaf.requireAbsent()) {
            XCTAssertEqual($0 as? EraseUnadmittedControlObservationV1.Failure,
                           .controlsPresent)
        }
        try hostileLeaf.closeAfterRefusal()
        XCTAssertEqual(try identity(leaf), leafBefore)
        XCTAssertEqual(try Data(contentsOf: targetLeaf), bytes)
    }

    @MainActor
    func testExpectedSourceIdentityCannotBeReplacedByReturnPath() throws {
        let fixture = try Fixture()
        let moved = fixture.container.appendingPathComponent("original-support")
        try FileManager.default.moveItem(at: fixture.support, to: moved)
        try FileManager.default.createDirectory(at: fixture.support,
                                                withIntermediateDirectories: false)
        let replacement = try identity(fixture.support)
        let observer = fixture.observer()
        XCTAssertThrowsError(try observer.requireAbsent()) {
            XCTAssertEqual($0 as? EraseUnadmittedControlObservationV1.Failure,
                           .invalidIdentity)
        }
        try observer.closeAfterRefusal()
        XCTAssertEqual(observer.status, .refusedAndClosed)
        XCTAssertEqual(try identity(fixture.support), replacement)
        XCTAssertEqual(try identity(moved), fixture.sourceIdentity)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.support.appendingPathComponent("FieldEvidenceErase").path))
    }

    @MainActor
    private final class Fixture {
        // A failed closedir/close has unknown physical ownership. Keep every
        // actual owner and directory reachable through host termination, even
        // when the test itself throws before its normal assertions finish.
        private static var retained: [Fixture] = []
        let container: URL
        let support: URL
        let sourceIdentity: Identity
        private var observations: [EraseUnadmittedControlObservationV1] = []

        init() throws {
            container = FileManager.default.temporaryDirectory
                .appendingPathComponent("unadmitted-erase-controls-\(UUID().uuidString)")
            support = container.appendingPathComponent("support")
            try FileManager.default.createDirectory(at: support,
                                                    withIntermediateDirectories: true)
            sourceIdentity = try V23EraseUnadmittedControlObservationTests.identity(support)
            Self.retained.append(self)
            FileHandle.standardError.write(Data((
                "V23_UNADMITTED_OBSERVER_RETAINED_V3 root=\(container.path) " +
                "retention=until-host-termination\n").utf8))
        }

        func observer() -> EraseUnadmittedControlObservationV1 {
            let observation = EraseUnadmittedControlObservationV1(
                applicationSupportURL: support,
                expectedSourceSupportIdentity: StoreApplicationSupportIdentity(
                    device: sourceIdentity.device, inode: sourceIdentity.inode))
            observations.append(observation) // Retain before requireAbsent opens.
            return observation
        }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let type: mode_t
    }

    private static func identity(_ url: URL) throws -> Identity {
        var value = stat()
        guard Darwin.lstat(url.path, &value) == 0 else { throw CocoaError(.fileReadUnknown) }
        return Identity(device: value.st_dev, inode: value.st_ino,
                        type: value.st_mode & S_IFMT)
    }

    private func identity(_ url: URL) throws -> Identity { try Self.identity(url) }
}
