import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S6_5ReplacementUnionTests: XCTestCase {
    private let fileManager = FileManager.default
    private let replacementAt = Date(timeIntervalSince1970: 1_786_710_000)

    func testPureRuleCreatesOnlyCurrentOnlyTombstonesAndRejectsCollisions() throws {
        let currentA = packet(
            id: uuid(10), root: uuid(11), currentRecord: uuid(12), created: 100
        )
        let currentB = packet(
            id: uuid(20), root: uuid(21), currentRecord: uuid(22), created: 200
        )
        let incomingB = packet(
            id: uuid(20), root: uuid(21), currentRecord: uuid(23), created: 200
        )
        let incomingC = packet(
            id: uuid(30), root: uuid(31), currentRecord: uuid(32), created: 300
        )

        let plan = try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentA, currentB],
                incomingPackets: [incomingB, incomingC],
                replacementAt: replacementAt
            )
        )
        XCTAssertEqual(plan.currentOnlyTombstones, [
            packet(
                id: uuid(10), root: uuid(11), currentRecord: nil,
                created: 100, deleted: replacementAt.timeIntervalSince1970
            ),
        ])
        XCTAssertEqual(
            plan.packetsAfter.first(where: { $0.id == incomingB.id }),
            incomingB
        )
        XCTAssertEqual(
            Set(plan.consumedEvaluationRootIDs),
            Set([uuid(11), uuid(21), uuid(31)])
        )

        let wrongRoot = packet(
            id: currentA.id,
            root: uuid(99),
            currentRecord: uuid(98),
            created: 100
        )
        XCTAssertThrowsError(try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentA],
                incomingPackets: [wrongRoot],
                replacementAt: replacementAt
            )
        ))

        let wrongID = packet(
            id: uuid(97),
            root: currentA.stableRootID,
            currentRecord: uuid(96),
            created: 100
        )
        XCTAssertThrowsError(try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentA],
                incomingPackets: [wrongID],
                replacementAt: replacementAt
            )
        ))
        XCTAssertThrowsError(try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentB, currentA],
                incomingPackets: [incomingC],
                replacementAt: replacementAt
            )
        ))
    }

    @MainActor
    func testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot() async throws {
        let root = try makeRoot("golden")
        defer { try? fileManager.removeItem(at: root) }
        let current = try await makeLiveHarness(
            root: root,
            name: "current",
            base: 1,
            label: "Current sign",
            observedAt: Date(timeIntervalSince1970: 1_786_708_000)
        )
        let incoming = try await makeLiveHarness(
            root: root,
            name: "incoming",
            base: 101,
            label: "Restored sign",
            observedAt: Date(timeIntervalSince1970: 1_786_709_000)
        )
        let package = try exportPackage(incoming, root: root, name: "incoming")
        let sourceBefore = try fileTree(package)
        let validated = try importPackage(package, into: current.session, stageID: uuid(190))
        let oldID = current.session.generationID

        let service = try BackupRestoreService(
            applicationSupportURL: current.support,
            now: { self.replacementAt },
            makeUUID: sequence([uuid(191), uuid(192)])
        )
        let restored = try await service.restore(
            validatedPackage: validated,
            currentModelContext: current.session.modelContext,
            currentGenerationID: oldID,
            currentGenerationRootURL: current.session.generationRootURL,
            mode: .replaceExisting
        )

        XCTAssertEqual(try current.factory.currentGenerationID(), restored.generationID)
        XCTAssertEqual(try current.factory.retiredGenerationIDs(), [oldID])
        XCTAssertEqual(
            try restored.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
            ["Restored sign"]
        )
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Report>()), 1)
        let packets = try restored.modelContext.fetch(FetchDescriptor<Packet>())
        XCTAssertEqual(
            Set(packets.map(\.stableRootID)),
            Set([current.rootID, incoming.rootID])
        )
        let currentTombstone = try XCTUnwrap(
            packets.first(where: { $0.stableRootID == current.rootID })
        )
        XCTAssertEqual(currentTombstone.id, current.packetID)
        XCTAssertNil(currentTombstone.currentRecordID)
        XCTAssertEqual(currentTombstone.contentDeletedAt, replacementAt)
        XCTAssertEqual(currentTombstone.createdAt, current.packetCreatedAt)
        let incomingLive = try XCTUnwrap(
            packets.first(where: { $0.stableRootID == incoming.rootID })
        )
        XCTAssertEqual(incomingLive.id, incoming.packetID)
        XCTAssertNotNil(incomingLive.currentRecordID)
        XCTAssertNil(incomingLive.contentDeletedAt)
        XCTAssertEqual(
            try BackupRestoreService.currentSummary(
                modelContext: restored.modelContext,
                generationRootURL: restored.generationRootURL
            ).consumedRootCount,
            2
        )
        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: current.support.appendingPathComponent(
                "FieldEvidenceRestore/restore.json"
            ).path
        ))
        XCTAssertEqual(try fileTree(package), sourceBefore)
        XCTAssertTrue(fileManager.fileExists(
            atPath: current.factory.installedGenerationURL(id: oldID).path
        ))

        let reopened = try current.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, restored.generationID)
        XCTAssertEqual(
            Set(try reopened.modelContext.fetch(FetchDescriptor<Packet>()).map(\.stableRootID)),
            Set([current.rootID, incoming.rootID])
        )
    }

    @MainActor
    func testCancelRemovesOnlyOwnedStageAndDirtyCurrentFailsClosed() async throws {
        let root = try makeRoot("cancel")
        defer { try? fileManager.removeItem(at: root) }
        let current = try await makeLiveHarness(
            root: root, name: "current", base: 201, label: "Current sign",
            observedAt: Date(timeIntervalSince1970: 1_786_708_000)
        )
        let incoming = try await makeLiveHarness(
            root: root, name: "incoming", base: 301, label: "Incoming sign",
            observedAt: Date(timeIntervalSince1970: 1_786_709_000)
        )
        let package = try exportPackage(incoming, root: root, name: "incoming")
        let packageBefore = try fileTree(package)
        let currentBefore = try fileTree(current.session.generationRootURL)
        let pointerBefore = try Data(contentsOf: current.support.appendingPathComponent(
            "FieldEvidenceData/current.json"
        ))
        let validated = try importPackage(package, into: current.session, stageID: uuid(390))

        try BackupImportService(
            generationRootURL: current.session.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).discard(validated)

        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        XCTAssertEqual(try fileTree(package), packageBefore)
        XCTAssertEqual(try fileTree(current.session.generationRootURL), currentBefore)
        XCTAssertEqual(
            try Data(contentsOf: current.support.appendingPathComponent(
                "FieldEvidenceData/current.json"
            )),
            pointerBefore
        )
        XCTAssertEqual(try current.factory.currentGenerationID(), current.session.generationID)
        XCTAssertFalse(fileManager.fileExists(atPath: current.support.appendingPathComponent(
            "FieldEvidenceRestore/restore.json"
        ).path))

        let site = try XCTUnwrap(
            try current.session.modelContext.fetch(FetchDescriptor<Site>()).first
        )
        site.label = "Unsaved current edit"
        XCTAssertThrowsError(try BackupRestoreService.currentSummary(
            modelContext: current.session.modelContext,
            generationRootURL: current.session.generationRootURL
        )) { error in
            XCTAssertEqual(
                error as? BackupRestoreServiceError,
                .contextHasChanges
            )
        }
        current.session.modelContext.rollback()
    }

    @MainActor
    func testPacketCollisionFailsBeforeGenerationOrJournalMutation() async throws {
        let root = try makeRoot("collision")
        defer { try? fileManager.removeItem(at: root) }
        let current = try await makeLiveHarness(
            root: root, name: "current", base: 401, label: "Current sign",
            observedAt: Date(timeIntervalSince1970: 1_786_708_000),
            packetIDOverride: uuid(501)
        )
        let incoming = try await makeLiveHarness(
            root: root, name: "incoming", base: 501, label: "Incoming sign",
            observedAt: Date(timeIntervalSince1970: 1_786_709_000)
        )
        let package = try exportPackage(incoming, root: root, name: "incoming")
        let validated = try importPackage(package, into: current.session, stageID: uuid(590))
        let supportBefore = try fileTree(current.support)
        let service = try BackupRestoreService(
            applicationSupportURL: current.support,
            now: { self.replacementAt },
            makeUUID: sequence([uuid(591), uuid(592)])
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: current.session.modelContext,
                currentGenerationID: current.session.generationID,
                currentGenerationRootURL: current.session.generationRootURL,
                mode: .replaceExisting
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
        }
        XCTAssertEqual(try fileTree(current.support), supportBefore)
        XCTAssertEqual(try current.factory.currentGenerationID(), current.session.generationID)
        XCTAssertFalse(fileManager.fileExists(atPath: current.support.appendingPathComponent(
            "FieldEvidenceRestore/restore.json"
        ).path))
        try BackupImportService(
            generationRootURL: current.session.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).discard(validated)
    }

    @MainActor
    func testRecoveryPreservesReplacementUnionAcrossEveryJournalPhase() async throws {
        let cases: [(point: BackupRestoreFailurePoint, keepsOld: Bool)] = [
            (.afterPreparedWrite, true),
            (.afterGenerationInstall, false),
            (.afterPointerSwitch, false),
            (.afterNewGenerationValidation, false),
        ]

        for (index, value) in cases.enumerated() {
            let root = try makeRoot("recovery-\(index)")
            defer { try? fileManager.removeItem(at: root) }
            let current = try await makeLiveHarness(
                root: root,
                name: "current",
                base: 601 + index * 20,
                label: "Current sign \(index)",
                observedAt: Date(timeIntervalSince1970: 1_786_708_000)
            )
            let incoming = try await makeLiveHarness(
                root: root,
                name: "incoming",
                base: 701 + index * 20,
                label: "Incoming sign \(index)",
                observedAt: Date(timeIntervalSince1970: 1_786_709_000)
            )
            let package = try exportPackage(incoming, root: root, name: "incoming")
            let validated = try importPackage(
                package,
                into: current.session,
                stageID: uuid(790 + index)
            )
            let oldID = current.session.generationID
            let service = try BackupRestoreService(
                applicationSupportURL: current.support,
                now: { self.replacementAt },
                makeUUID: sequence([uuid(800 + index * 2), uuid(801 + index * 2)]),
                failureInjection: BackupRestoreFailureInjection(
                    failOnceAt: value.point
                )
            )

            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(
                    validatedPackage: validated,
                    currentModelContext: current.session.modelContext,
                    currentGenerationID: oldID,
                    currentGenerationRootURL: current.session.generationRootURL,
                    mode: .replaceExisting
                )
            } verify: { error in
                XCTAssertEqual(
                    error as? BackupRestoreServiceError,
                    .injectedFailure
                )
            }

            let recovery = try BackupRestoreService(
                applicationSupportURL: current.support,
                now: { self.replacementAt }
            )
            let recovered: StoreGenerationSession?
            do {
                recovered = try recovery.reconcileAtStartup()
            } catch {
                XCTFail("Recovery failed at \(value.point): \(error)")
                continue
            }
            let active = try current.factory.openOrBootstrapCurrent()
            if value.keepsOld {
                XCTAssertNil(recovered)
                XCTAssertEqual(active.generationID, oldID)
                XCTAssertEqual(
                    try active.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
                    ["Current sign \(index)"]
                )
                XCTAssertEqual(
                    Set(try active.modelContext.fetch(FetchDescriptor<Packet>())
                        .map(\.stableRootID)),
                    Set([current.rootID])
                )
            } else {
                XCTAssertEqual(recovered?.generationID, active.generationID)
                XCTAssertNotEqual(active.generationID, oldID)
                XCTAssertEqual(
                    try active.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
                    ["Incoming sign \(index)"]
                )
                XCTAssertEqual(
                    Set(try active.modelContext.fetch(FetchDescriptor<Packet>())
                        .map(\.stableRootID)),
                    Set([current.rootID, incoming.rootID])
                )
            }
            XCTAssertFalse(fileManager.fileExists(
                atPath: current.support.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                ).path
            ))
        }
    }
}

extension S6_5ReplacementUnionTests {
    func testV23P03C18RegistryPointerBindsPromotionReceiptIdentity() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c185")!)
        let receiptID = UUID(uuidString: "c1850000-0000-4000-8000-000000000001")!
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: UUID(uuidString: "c1850000-0000-4000-8000-000000000002")!,
            workspaceID: workspaceID,
            packageID: "com.field-evidence.c18.replacement",
            activeReleaseRecordID: UUID(uuidString: "c1850000-0000-4000-8000-000000000003")!,
            promotionReceiptID: receiptID,
            activePackageReleaseID: String(repeating: "a", count: 64),
            activeReleaseRecordSHA256: String(repeating: "b", count: 64),
            revision: 1,
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "c1850000-0000-4000-8000-000000000004")!
            )
        )
        XCTAssertNoThrow(try pointer.validate())
        XCTAssertEqual(pointer.promotionReceiptID, receiptID)
    }
}

extension S6_5ReplacementUnionTests {
    func testV23P03C36ReplacementRecordRetainsCanonicalOperationalIdentity() {
        let id=UUID(),workspaceID=UUID(),bytes=Data("canonical-draft".utf8)
        let record=V16BackupFieldDraftRecordV1(kind:.checkpoint,id:id,workspaceID:workspaceID,revision:7,canonicalData:bytes)
        XCTAssertEqual(record,V16BackupFieldDraftRecordV1(kind:.checkpoint,id:id,workspaceID:workspaceID,revision:7,canonicalData:bytes))
        XCTAssertNotEqual(record.kind,.discardReceipt)
    }
}

private extension S6_5ReplacementUnionTests {
    struct LiveHarness {
        let support: URL
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
        let packetID: UUID
        let rootID: UUID
        let packetCreatedAt: Date
    }

    struct FileFact: Equatable {
        let path: String
        let bytes: Data
    }

    enum FixtureError: Error { case invalid }

    @MainActor
    func makeLiveHarness(
        root: URL,
        name: String,
        base: Int,
        label: String,
        observedAt: Date,
        packetIDOverride: UUID? = nil
    ) async throws -> LiveHarness {
        let support = root.appendingPathComponent("\(name)-support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let siteID = uuid(base)
        let assetID = uuid(base + 1)
        context.insert(Site(
            id: siteID,
            label: "\(label) site",
            address: nil,
            timeZoneID: "America/New_York",
            createdAt: observedAt.addingTimeInterval(-10)
        ))
        context.insert(Asset(
            id: assetID,
            siteID: siteID,
            packID: pack.packID,
            packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            label: label,
            createdAt: observedAt.addingTimeInterval(-9)
        ))
        try context.save()

        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        _ = try coordinator.beginCheck(
            assetID: assetID,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: observedAt
        )
        let wide = try await coordinator.importCandidate(
            assetID: assetID,
            sourceData: try makePNG(seed: UInt8(truncatingIfNeeded: base)),
            createdAt: observedAt.addingTimeInterval(1)
        )
        _ = try await coordinator.accept(candidate: wide, assetID: assetID)
        let close = try await coordinator.importCandidate(
            assetID: assetID,
            sourceData: try makePNG(seed: UInt8(truncatingIfNeeded: base + 17)),
            createdAt: observedAt.addingTimeInterval(2)
        )
        _ = try await coordinator.accept(candidate: close, assetID: assetID)
        let packetID = packetIDOverride ?? uuid(base + 3)
        let rootID = uuid(base + 4)
        let result = try await coordinator.finalize(
            assetID: assetID,
            selection: .noVisibleIssue,
            completedAt: observedAt.addingTimeInterval(5),
            snapshotCreatedAt: observedAt.addingTimeInterval(6),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(
                mutationID: uuid(base + 2),
                packetID: packetID,
                stableRootID: rootID,
                reportID: uuid(base + 5),
                issueID: nil
            )
        )
        guard case .ready = try coordinator.prepareReportDelivery(result: result) else {
            throw FixtureError.invalid
        }
        let packet = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Packet>()).first
        )
        return LiveHarness(
            support: support,
            factory: factory,
            session: session,
            packetID: packetID,
            rootID: rootID,
            packetCreatedAt: packet.createdAt
        )
    }

    @MainActor
    func exportPackage(
        _ harness: LiveHarness,
        root: URL,
        name: String
    ) throws -> URL {
        let destination = root.appendingPathComponent("\(name)-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_709_500) },
            appVersion: { "4.0" },
            appBuild: { "42" }
        )
        let preview = try exporter.prepare()
        return try exporter.export(previewID: preview.id, to: destination)
    }

    @MainActor
    func importPackage(
        _ package: URL,
        into session: StoreGenerationSession,
        stageID: UUID
    ) throws -> ValidatedV4BackupPackageV1 {
        try BackupImportService(
            generationRootURL: session.generationRootURL,
            makeUUID: { stageID },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
    }

    func packet(
        id: UUID,
        root: UUID,
        currentRecord: UUID?,
        created: TimeInterval,
        deleted: TimeInterval? = nil
    ) -> V4BackupPacketDTO {
        V4BackupPacketDTO(
            id: id,
            schemaVersion: 1,
            stableRootID: root,
            currentRecordID: currentRecord,
            evaluationCounted: true,
            contentDeletedAt: deleted.map { Date(timeIntervalSince1970: $0) },
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    func makeRoot(_ name: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_5-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(
            format: "65000000-0000-0000-0000-%012d",
            suffix
        ))!
    }

    func fileTree(_ root: URL) throws -> [FileFact] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw FixtureError.invalid }
        var facts: [FileFact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(
                root.standardizedFileURL.path.count + 1
            ))
            facts.append(FileFact(path: relative, bytes: try Data(contentsOf: url)))
        }
        return facts.sorted { $0.path < $1.path }
    }

    func makePNG(seed: UInt8) throws -> Data {
        let width = 48
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = seed &+ UInt8(truncatingIfNeeded: index / 4)
            pixels[index + 1] = seed &+ 17
            pixels[index + 2] = seed &+ 43
            pixels[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { throw FixtureError.invalid }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw FixtureError.invalid }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.invalid
        }
        return output as Data
    }

    @MainActor
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        verify: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}

extension S6_5ReplacementUnionTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
