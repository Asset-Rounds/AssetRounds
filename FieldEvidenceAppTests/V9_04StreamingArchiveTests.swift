import CryptoKit
import Darwin
import XCTest

@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_04StreamingArchiveTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45StreamingArchiveCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityBoundsCanonicalSnapshotBytes() {
        XCTAssertEqual(AssetLabelCanonicalCodecV1.maximumCanonicalByteCount, 16 * 1_024 * 1_024)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion, 33)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies.count, 1)
    }
}

private final class C30EvidenceContextAnchorV9_04StreamingArchive: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_04StreamingArchiveTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV9_04G01GoldenDeterministicRepeatAndLegacyV4Dispatch() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let staging = root.appendingPathComponent("staging")
        let output = root.appendingPathComponent("output")
        try makeDirectories(source, output)
        try makeProtectedStaging(staging)
        let entries = try makeEntries(in: source)
        let ids = UUIDSequence()
        let service = StreamingArchiveService(limits: limits(), makeOperationID: ids.next)
        let first = output.appendingPathComponent("first.fieldrecordbackup")
        let second = output.appendingPathComponent("second.fieldrecordbackup")

        let firstReceipt = try service.write(.init(entries: entries, stagingDirectoryURL: staging), to: first)
        let secondReceipt = try service.write(.init(entries: Array(entries.reversed()), stagingDirectoryURL: staging), to: second)
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
        XCTAssertEqual(firstReceipt.archiveSHA256, secondReceipt.archiveSHA256)
        XCTAssertEqual(firstReceipt.index.entries.map(\.path), ["manifest.json", "records.json"])
        XCTAssertTrue(try StreamingArchiveService.hasFormatMagic(at: first))

        let extractionURL = output.appendingPathComponent("extracted")
        let extraction = try service.extract(first, to: extractionURL)
        XCTAssertEqual(extraction.archiveSHA256, firstReceipt.archiveSHA256)
        XCTAssertEqual(try Data(contentsOf: extractionURL.appendingPathComponent("records.json")), Data("{\"records\":[]}".utf8))

        let legacy = output.appendingPathComponent("Legacy.fieldrecordbackup")
        try Data("legacy-v4-directory-reader-dispatch".utf8).write(to: legacy)
        XCTAssertFalse(try StreamingArchiveService.hasFormatMagic(at: legacy))
    }

    func testV9_04A01AlternateBoundedMemoryMaximumFixture() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let staging = root.appendingPathComponent("staging")
        let output = root.appendingPathComponent("output")
        try makeDirectories(source, output)
        try makeProtectedStaging(staging)
        let payload = Data(repeating: 0x5a, count: 4_096)
        let sourceURL = source.appendingPathComponent("records.json")
        try payload.write(to: sourceURL)
        let tight = limits(entryCount: 1, entryBytes: 4_096, aggregateBytes: 4_096, bufferBytes: 4_096)
        let service = StreamingArchiveService(limits: tight, makeOperationID: UUIDSequence().next)
        let entry = try writeEntry(path: "records.json", source: sourceURL, data: payload)
        var writeStorage = [Int64]()
        let archive = output.appendingPathComponent("maximum.fieldrecordbackup")
        let receipt = try service.write(
            .init(entries: [entry], stagingDirectoryURL: staging),
            to: archive,
            storageCheck: { writeStorage.append($0) }
        )
        XCTAssertEqual(receipt.index.uncompressedPayloadByteCount, 4_096)
        XCTAssertEqual(writeStorage, [10_240])
        var extractStorage = [Int64]()
        _ = try service.extract(
            archive,
            to: output.appendingPathComponent("maximum-extracted"),
            storageCheck: { extractStorage.append($0) }
        )
        XCTAssertEqual(extractStorage, [4_096])

        let tooMany = output.appendingPathComponent("too-many.fieldrecordbackup")
        assertFailure(.invalidPlan) {
            _ = try service.write(.init(entries: [entry, entry], stagingDirectoryURL: staging), to: tooMany)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tooMany.path))
        let over = try writeEntry(path: "records.json", source: sourceURL, data: payload, declaredBytes: 4_097)
        assertFailure(.invalidPlan) {
            _ = try service.write(.init(entries: [over], stagingDirectoryURL: staging), to: output.appendingPathComponent("over.fieldrecordbackup"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
    }

    func testV9_04H01HostilePathLinkBombTamperAndUnicodeCollisionCorpus() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let staging = root.appendingPathComponent("staging")
        let output = root.appendingPathComponent("output")
        try makeDirectories(source, output)
        try makeProtectedStaging(staging)
        let data = Data("{}".utf8)
        let file = source.appendingPathComponent("payload")
        try data.write(to: file)
        let service = StreamingArchiveService(limits: limits(), makeOperationID: UUIDSequence().next)

        for path in ["/records.json", "../records.json", "media\\evil.jpg", "media/%2f.jpg", "a/b/c", "re\u{301}cords.json"] {
            assertFailure(.hostilePath) {
                _ = try service.write(.init(entries: [try self.writeEntry(path: path, source: file, data: data)], stagingDirectoryURL: staging), to: output.appendingPathComponent(UUID().uuidString))
            }
        }
        let duplicate = try writeEntry(path: "records.json", source: file, data: data)
        assertFailure(.duplicatePath) {
            _ = try service.write(.init(entries: [duplicate, duplicate], stagingDirectoryURL: staging), to: output.appendingPathComponent("duplicate"))
        }
        let mediaUpper = try writeEntry(path: "media/63000000-0000-0000-0000-000000000001.jpg", source: file, data: data, mime: "image/jpeg")
        let mediaLower = try writeEntry(path: "media/63000000-0000-0000-0000-000000000001.JPG", source: file, data: data, mime: "image/jpeg")
        assertFailure(.hostilePath) {
            _ = try service.write(.init(entries: [mediaUpper, mediaLower], stagingDirectoryURL: staging), to: output.appendingPathComponent("case"))
        }

        let symlink = source.appendingPathComponent("symlink")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
        assertAnyFailure {
            _ = try service.write(.init(entries: [try self.writeEntry(path: "records.json", source: symlink, data: data)], stagingDirectoryURL: staging), to: output.appendingPathComponent("symlink"))
        }
        let hardlink = source.appendingPathComponent("hardlink")
        try FileManager.default.linkItem(at: file, to: hardlink)
        assertAnyFailure {
            _ = try service.write(.init(entries: [try self.writeEntry(path: "records.json", source: hardlink, data: data)], stagingDirectoryURL: staging), to: output.appendingPathComponent("hardlink"))
        }
        try FileManager.default.removeItem(at: hardlink)
        let special = source.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: special, withIntermediateDirectories: false)
        assertAnyFailure {
            _ = try service.write(.init(entries: [try self.writeEntry(path: "records.json", source: special, data: data)], stagingDirectoryURL: staging), to: output.appendingPathComponent("special"))
        }

        let valid = output.appendingPathComponent("valid.fieldrecordbackup")
        _ = try service.write(.init(entries: [duplicate], stagingDirectoryURL: staging), to: valid)
        var tampered = try Data(contentsOf: valid)
        tampered[tampered.index(before: tampered.endIndex)] ^= 0xff
        let tamperedURL = output.appendingPathComponent("tampered.fieldrecordbackup")
        try tampered.write(to: tamperedURL)
        assertFailure(.contentMismatch) { _ = try service.extract(tamperedURL, to: output.appendingPathComponent("tampered-out")) }

        let bomb = output.appendingPathComponent("bomb.fieldrecordbackup")
        let zeroDigest = String(repeating: "0", count: 64)
        try makeArchive(
            at: bomb,
            index: StreamingArchiveIndexV1(
                archiveSchemaVersion: 1,
                entries: [StreamingArchiveEntryV1(
                    path: "records.json",
                    mimeType: "application/json",
                    compression: .zlib,
                    storedByteCount: 1,
                    uncompressedByteCount: 101,
                    storedSHA256: zeroDigest,
                    contentSHA256: zeroDigest
                )],
                storedPayloadByteCount: 1,
                uncompressedPayloadByteCount: 101
            ),
            payload: Data([0])
        )
        assertFailure(.unsupportedFormat) { _ = try service.extract(bomb, to: output.appendingPathComponent("bomb-out")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("bomb-out").path))
    }

    func testV9_04I01InterruptionCancellationPermissionLowStorageAndChangingSource() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let staging = root.appendingPathComponent("staging")
        let output = root.appendingPathComponent("output")
        try makeDirectories(source, output)
        try makeProtectedStaging(staging)
        let data = Data(repeating: 0x31, count: 16_384)
        let file = source.appendingPathComponent("records")
        try data.write(to: file)
        let entry = try writeEntry(path: "records.json", source: file, data: data)
        let service = StreamingArchiveService(limits: limits(entryBytes: 32_768, aggregateBytes: 32_768), makeOperationID: UUIDSequence().next)

        assertFailure(.cancelled) {
            _ = try service.write(.init(entries: [entry], stagingDirectoryURL: staging), to: output.appendingPathComponent("cancel-before"), cancellation: .init { throw StreamingArchiveFailureV1.cancelled })
        }
        var checkpoints = 0
        assertFailure(.cancelled) {
            _ = try service.write(.init(entries: [entry], stagingDirectoryURL: staging), to: output.appendingPathComponent("cancel-during"), cancellation: .init {
                checkpoints += 1
                if checkpoints == 3 { throw StreamingArchiveFailureV1.cancelled }
            })
        }
        assertFailure(.insufficientStorage) {
            _ = try service.write(.init(entries: [entry], stagingDirectoryURL: staging), to: output.appendingPathComponent("low-storage"), storageCheck: { _ in throw StreamingArchiveFailureV1.insufficientStorage })
        }
        let denied = source.appendingPathComponent("permission-denied")
        try data.write(to: denied)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: denied.path) }
        assertAnyFailure {
            _ = try service.write(.init(entries: [try self.writeEntry(path: "records.json", source: denied, data: data)], stagingDirectoryURL: staging), to: output.appendingPathComponent("permission"))
        }
        let changed = try writeEntry(path: "records.json", source: file, data: data, declaredBytes: Int64(data.count - 1))
        assertFailure(.sourceChanged) {
            _ = try service.write(.init(entries: [changed], stagingDirectoryURL: staging), to: output.appendingPathComponent("changed"))
        }
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
    }

    func testV9_04R01RecoveryWriterInvalidationPreservesLegacyReaderAndStaging() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let staging = root.appendingPathComponent("staging")
        let output = root.appendingPathComponent("output")
        try makeDirectories(source, output)
        try makeProtectedStaging(staging)
        let data = Data("{\"records\":[]}".utf8)
        let file = source.appendingPathComponent("records")
        try data.write(to: file)
        let entry = try writeEntry(path: "records.json", source: file, data: data)
        let service = StreamingArchiveService(limits: limits(), makeOperationID: UUIDSequence().next)
        let invalidated = output.appendingPathComponent("invalidated.fieldrecordbackup")
        assertFailure(.cancelled) {
            _ = try service.write(.init(entries: [entry], stagingDirectoryURL: staging), to: invalidated, cancellation: .init { throw StreamingArchiveFailureV1.cancelled })
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidated.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])

        let retry = output.appendingPathComponent("retry.fieldrecordbackup")
        let repeatURL = output.appendingPathComponent("repeat.fieldrecordbackup")
        _ = try service.write(.init(entries: [entry], stagingDirectoryURL: staging), to: retry)
        _ = try service.write(.init(entries: [entry], stagingDirectoryURL: staging), to: repeatURL)
        XCTAssertEqual(try Data(contentsOf: retry), try Data(contentsOf: repeatURL))
        let recovered = output.appendingPathComponent("recovered")
        _ = try service.extract(retry, to: recovered)
        XCTAssertEqual(try Data(contentsOf: recovered.appendingPathComponent("records.json")), data)
        let legacy = output.appendingPathComponent("Legacy.fieldrecordbackup")
        try Data("legacy-v4".utf8).write(to: legacy)
        XCTAssertFalse(try StreamingArchiveService.hasFormatMagic(at: legacy))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
    }
}

private final class C27V904StreamingTypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorLimitsV1.maximumInputBytes, 1_024)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension V9_04StreamingArchiveTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.backupEligibility, "SUBSEQUENT_BACKUPS_ONLY")
    }
}

private extension V9_04StreamingArchiveTests {
    final class UUIDSequence {
        private var value = 0
        func next() -> UUID {
            value += 1
            return UUID(uuidString: String(format: "64000000-0000-0000-0000-%012d", value))!
        }
    }

    func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func makeDirectories(_ urls: URL...) throws {
        for url in urls { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
    }

    func makeProtectedStaging(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: url)
    }

    func limits(entryCount: Int = 8, entryBytes: Int64 = 65_536, aggregateBytes: Int64 = 131_072, bufferBytes: Int = 4_096) -> StreamingArchiveLimitsV1 {
        .init(
            maximumIndexByteCount: 2_048,
            maximumEntryCount: entryCount,
            maximumPathUTF8ByteCount: 512,
            maximumStoredEntryByteCount: entryBytes,
            maximumUncompressedEntryByteCount: entryBytes,
            maximumStoredAggregateByteCount: aggregateBytes,
            maximumUncompressedAggregateByteCount: aggregateBytes,
            maximumCompressionRatio: 100,
            bufferByteCount: bufferBytes,
            stagingReserveByteCount: 0
        )
    }

    func makeEntries(in source: URL) throws -> [StreamingArchiveWriteEntryV1] {
        let manifest = Data("{\"entries\":[]}".utf8)
        let records = Data("{\"records\":[]}".utf8)
        let manifestURL = source.appendingPathComponent("manifest")
        let recordsURL = source.appendingPathComponent("records")
        try manifest.write(to: manifestURL)
        try records.write(to: recordsURL)
        return [
            try writeEntry(path: "records.json", source: recordsURL, data: records),
            try writeEntry(path: "manifest.json", source: manifestURL, data: manifest)
        ]
    }

    func writeEntry(path: String, source: URL, data: Data, declaredBytes: Int64? = nil, mime: String = "application/json") throws -> StreamingArchiveWriteEntryV1 {
        let sourceRoot = source.deletingLastPathComponent()
        return .init(
            path: path,
            mimeType: mime,
            sourceRootURL: sourceRoot,
            sourceRelativePath: source.lastPathComponent,
            expectedSourceRootIdentity: try sourceRootIdentity(at: sourceRoot),
            expectedUncompressedByteCount: declaredBytes ?? Int64(data.count),
            expectedContentSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            compression: .stored
        )
    }

    func sourceRootIdentity(at url: URL) throws -> StreamingArchiveRootIdentityV1 {
        let descriptor = Darwin.open(url.standardizedFileURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StreamingArchiveFailureV1.ioFailure }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw StreamingArchiveFailureV1.ioFailure
        }
        return StreamingArchiveRootIdentityV1(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    func assertFailure(_ expected: StreamingArchiveFailureV1, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? StreamingArchiveFailureV1, expected, file: file, line: line)
        }
    }

    func assertAnyFailure(file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line)
    }

    func makeArchive(at url: URL, index value: StreamingArchiveIndexV1, payload: Data) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let index = try encoder.encode(value)
        var archive = StreamingArchiveFormatV1.magic
        appendBigEndian(UInt16(1), to: &archive)
        appendBigEndian(UInt16(0), to: &archive)
        appendBigEndian(UInt64(index.count), to: &archive)
        archive.append(Data(SHA256.hash(data: index)))
        archive.append(index)
        archive.append(payload)
        try archive.write(to: url)
    }

    func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
}

extension V9_04StreamingArchiveTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV904StreamingArchiveTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension V9_04StreamingArchiveTests {
    func testV23P03C42StreamingArchivePreservesTypedCanonicalReceiptsWithinBounds() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try makeDirectories(source, output)
        try makeProtectedStaging(staging)

        let values = [
            try CompositeAreaSafetyArchetypeV1.run(),
            try ControllerZoneDistributionArchetypeV1.run(),
        ]
        let bytes = try values.enumerated().map { offset, value in
            let data = try CrossMarketCanonicalV1.data(value)
            try data.write(to: source.appendingPathComponent("receipt-\(offset)"))
            return data
        }
        let entries = try bytes.enumerated().map { offset, data in
            try writeEntry(
                path: "c42-receipt-\(offset).json",
                source: source.appendingPathComponent("receipt-\(offset)"),
                data: data
            )
        }
        let service = StreamingArchiveService(
            limits: limits(entryBytes: 131_072, aggregateBytes: 262_144),
            makeOperationID: UUIDSequence().next
        )
        let archive = output.appendingPathComponent("c42.fieldrecordbackup")
        let written = try service.write(
            .init(entries: entries, stagingDirectoryURL: staging),
            to: archive
        )
        let extractionRoot = output.appendingPathComponent("extracted", isDirectory: true)
        let extracted = try service.extract(archive, to: extractionRoot)

        XCTAssertEqual(extracted.archiveSHA256, written.archiveSHA256)
        XCTAssertEqual(written.index.entries.map(\.path), ["c42-receipt-0.json", "c42-receipt-1.json"])
        for (offset, expected) in values.enumerated() {
            let archivedBytes = try Data(
                contentsOf: extractionRoot.appendingPathComponent("c42-receipt-\(offset).json")
            )
            XCTAssertEqual(archivedBytes, bytes[offset])
            XCTAssertEqual(
                try CrossMarketCanonicalV1.decode(ModelRunReceiptV1.self, from: archivedBytes),
                expected
            )
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
    }
}

private final class C33TemporalEvidenceAnchorV904StreamingArchive: XCTestCase {
    func testC33V904StreamingArchiveCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "streaming.temporal-content-bytes",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "streaming.temporal-content-bytes",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV904StreamingArchive: XCTestCase {
    func testC32V904StreamingArchiveCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .packet,
            fieldID: "archive.stream-boundary",
            value: .text("accepted receipt export only")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .packet,
            fieldID: "archive.stream-boundary",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}

private final class C48PortableReviewV904ArchiveTests: XCTestCase {
    func testC48ArchiveFilesAreProtectedAndExcludedFromBackup() throws {
        try PortableExchangeProtectedFilePolicyV2.validate()
        XCTAssertEqual(PortableExchangeProtectedFilePolicyV2.directoryKind, .portableExchangeDirectory)
        XCTAssertEqual(PortableExchangeProtectedFilePolicyV2.sessionKind, .portableExchangeSessionFile)
        XCTAssertEqual(PortableExchangeProtectedFilePolicyV2.journalKind, .portableExchangeJournalFile)
        XCTAssertEqual(PortableExchangeProtectedFilePolicyV2.quarantineKind, .portableExchangeQuarantineFile)
    }
}
private final class C46V904StreamingArchiveCompatibilityTests: XCTestCase {
    func testC46StreamingArchiveKeepsContactValueRestricted() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "streaming-archive",
            kind: .phone,
            handoff: .call,
            slot: 46004
        )
    }
}
private final class C49WorkResourceStreamingArchiveBoundaryTests: XCTestCase {
    func testStreamingArchiveCarriesFrozenSnapshotNotLivePartLink() { XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference) }
}

private final class C50IncumbentFileExchangeV904StreamingArchiveTests: XCTestCase {
    func testAdapterScratchAndQuarantineAreNotBackupMembers() {
        XCTAssertTrue(
            C50IncumbentFileExchangeStreamingArchiveBoundaryV1.validate(
                recordsSchemaVersion: C49BackupEnrollmentV1.recordsSchemaVersion
            )
        )
        XCTAssertEqual(C50IncumbentFileExchangeStreamingArchiveBoundaryV1.adapterSourceMemberCount, 0)
        XCTAssertEqual(C50IncumbentFileExchangeStreamingArchiveBoundaryV1.adapterQuarantineMemberCount, 0)
        XCTAssertEqual(C50IncumbentFileExchangeStreamingArchiveBoundaryV1.profileSelectionMemberCount, 0)
        XCTAssertFalse(C50IncumbentFileExchangeStreamingArchiveServiceBoundaryV1.routesAdapterFilesThroughBackupArchiveWriter)
        XCTAssertFalse(C50IncumbentFileExchangeStreamingArchiveServiceBoundaryV1.routesBackupArchiveMembersThroughAdapterParser)
        XCTAssertTrue(C50IncumbentFileExchangeStreamingArchiveServiceBoundaryV1.unknownAdapterShapedArchiveMembersFailClosed)
    }
}

extension C45StreamingArchiveCompatibilityTests {
    func testV23P03C51StreamingArchiveResumesAtRecordBoundaries() {
        XCTAssertTrue(
            ScheduleStreamingArchivePolicyV1.recordsSchemaVersion == 26
                && ScheduleStreamingArchivePolicyV1.interruptionResumesAtCanonicalRecordBoundary
                && ScheduleStreamingArchivePolicyV1
                    .calendarOverrideBasisClosureUsesExistingRecordKinds
                && !ScheduleStreamingArchivePolicyV1.notificationStateIsTruth
                && !ScheduleStreamingArchivePolicyV1.partialClosureMayPublish
        )
    }
}

extension V9_04StreamingArchiveTests {
    func testV23P03C34StreamingArchiveExcludesDeviceOperationalSceneState() {
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        XCTAssertFalse(lifecycle.backupIncluded)
        XCTAssertFalse(lifecycle.exportIncluded)
        XCTAssertFalse(lifecycle.reportIncluded)
        XCTAssertFalse(lifecycle.journalIncluded)
        XCTAssertTrue(lifecycle.eraseClears)
    }
}
