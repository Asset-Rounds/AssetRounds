import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V30P02C02UnicodeEvidenceSafetyTests: XCTestCase {
    func testFixtureCoversFixedUTF8IdentityAndBidiDiagnosticsWithoutNormalization() throws {
        let fixture = try unicodeFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertFalse(fixture.cases.isEmpty)

        for item in fixture.cases {
            let identity = UnicodeEvidenceSafetyV1.identity(of: item.source)
            XCTAssertEqual(identity.utf8SHA256, item.utf8SHA256, item.id)
            XCTAssertEqual(identity.utf8ByteCount, item.utf8ByteCount, item.id)
            XCTAssertEqual(identity.scalarCount, item.scalarCount, item.id)
            XCTAssertEqual(identity.graphemeCount, item.graphemeCount, item.id)
            XCTAssertEqual(
                identity.directionalControls,
                item.directionalControls.map {
                    UnicodeDirectionalControlV1(
                        scalarOffset: $0.scalarOffset,
                        scalarValue: $0.scalarValue
                    )
                },
                item.id
            )
            let decoded = try UnicodeEvidenceSafetyV1.validatedUTF8(Data(item.source.utf8))
            XCTAssertEqual(Array(decoded.utf8), Array(item.source.utf8), item.id)
        }

        let isolate = try fixture.case(named: "bidi-isolate")
        XCTAssertEqual(
            UnicodeEvidenceSafetyV1.identity(of: isolate.source).directionalControls,
            [
                .init(scalarOffset: 3, scalarValue: 0x2067),
                .init(scalarOffset: 8, scalarValue: 0x2069),
            ]
        )
    }

    func testExactSourceDistinguishesCanonicalEquivalentNFCAndNFD() throws {
        let nfc = try unicodeFixture().case(named: "nfc-accent").source
        let nfd = try unicodeFixture().case(named: "nfd-accent").source

        XCTAssertEqual(nfc, nfd)
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))
        XCTAssertNotEqual(
            UnicodeEvidenceSafetyV1.identity(of: nfc).utf8SHA256,
            UnicodeEvidenceSafetyV1.identity(of: nfd).utf8SHA256
        )
        XCTAssertThrowsError(
            try UnicodeEvidenceSafetyV1.requireExactSource(before: nfc, after: nfd)
        ) { error in
            XCTAssertEqual(error as? UnicodeEvidenceSafetyFailureV1, .changedSource)
        }
    }

    func testValidatedUTF8RejectsInvalidSequencesAndPreservesEmptyAndRawHostileText() throws {
        for bytes: [UInt8] in [
            [0xc3, 0x28],
            [0xe2, 0x28, 0xa1],
            [0xf0, 0x28, 0x8c, 0xbc],
            [0xed, 0xa0, 0x80],
            [0xe2, 0x82],
        ] {
            XCTAssertThrowsError(try UnicodeEvidenceSafetyV1.validatedUTF8(Data(bytes))) { error in
                XCTAssertEqual(error as? UnicodeEvidenceSafetyFailureV1, .invalidUTF8)
            }
        }

        XCTAssertEqual(try UnicodeEvidenceSafetyV1.validatedUTF8(Data()), "")
        let hostile = try unicodeFixture().case(named: "all-bidi-controls").source
        let recovered = try UnicodeEvidenceSafetyV1.validatedUTF8(Data(hostile.utf8))
        XCTAssertEqual(Array(recovered.utf8), Array(hostile.utf8))
        XCTAssertEqual(
            UnicodeEvidenceSafetyV1.identity(of: recovered).directionalControls.count,
            12
        )
        let authoredFEFFAndNull = try unicodeFixture().case(named: "authored-feff-and-null").source
        let rawRecovered = try UnicodeEvidenceSafetyV1.validatedUTF8(Data(authoredFEFFAndNull.utf8))
        XCTAssertEqual(Array(rawRecovered.utf8), Array(authoredFEFFAndNull.utf8))
    }

    func testRealContactImportAndReviewedCaptionCanonicalRoundTripsPreserveUTF8Bytes() throws {
        let workspaceID = WorkspaceID(rawValue: uuid("c0200000-0000-4000-8000-000000000001"))
        let instant = Date(timeIntervalSince1970: 1_788_000_000)
        let mutationID = try MutationIDV1(rawValue: uuid("c0200000-0000-4000-8000-000000000002"))
        let party = try ServicePartyReferenceV1(
            partyID: uuid("c0200000-0000-4000-8000-000000000003"),
            workspaceID: workspaceID,
            kind: .organization,
            displayName: "現場 👩‍🔧",
            provenance: .locallyRecorded,
            state: .effective,
            effectiveAt: instant,
            revision: 1,
            mutationID: mutationID
        )
        let contactText = "موقع\u{2067}@مثال.测试"
        let contact = try ServiceContactPointV1(
            contactPointID: uuid("c0200000-0000-4000-8000-000000000004"),
            workspaceID: workspaceID,
            party: party,
            kind: .email,
            label: .work,
            displayValue: contactText,
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: instant,
            revision: 1,
            mutationID: try MutationIDV1(rawValue: uuid("c0200000-0000-4000-8000-000000000005"))
        )
        let decodedContact = try OperationalContactCanonicalCodecV1.decode(
            ServiceContactPointV1.self,
            from: try OperationalContactCanonicalCodecV1.data(contact)
        )
        XCTAssertEqual(Array(decodedContact.displayValue.utf8), Array(contactText.utf8))

        let fileName = "现场-👩‍🔧-보고서.pdf"
        let sourceFile = try ImportSourceFileV1(
            schemaID: "UNICODE_EVIDENCE_V1",
            schemaVersion: 1,
            fileName: fileName,
            orderIndex: 0,
            byteCount: 64,
            sha256: String(repeating: "a", count: 64)
        )
        let decodedSourceFile = try OperationalContactCanonicalCodecV1.decode(
            ImportSourceFileV1.self,
            from: try OperationalContactCanonicalCodecV1.data(sourceFile)
        )
        XCTAssertEqual(Array(decodedSourceFile.fileName.utf8), Array(fileName.utf8))

        let actor = try LocalActorReferenceV1(
            actorReferenceID: uuid("c0200000-0000-4000-8000-000000000006"),
            workspaceID: workspaceID,
            displayName: "검토자 🧾"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: uuid("c0200000-0000-4000-8000-000000000007"),
            workspaceID: workspaceID,
            actor: actor,
            responsibility: .reviewedBy,
            displayNameAtTime: actor.displayName,
            capturedAt: instant
        )
        let captionText = try unicodeFixture().case(named: "filename").source
        let caption = try EvidenceReviewedCaptionV1(
            text: captionText,
            provenance: .importedThenReviewed,
            reviewer: reviewer,
            reviewedAt: instant
        )
        let decodedCaption = try EvidenceMetadataCanonicalCodecV1.decode(
            EvidenceReviewedCaptionV1.self,
            from: try EvidenceMetadataCanonicalCodecV1.data(caption)
        )
        XCTAssertEqual(Array(decodedCaption.text.utf8), Array(captionText.utf8))
    }

    @MainActor
    func testEvidenceBundleStorePreservesRawNonUTF8OriginalBytes() async throws {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "V30-C02-binary-\(UUID().uuidString)", isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let session = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()

        let workspaceID = WorkspaceID(rawValue: uuid("c0200000-0000-4000-8000-000000000010"))
        let bytes = Data([0x00, 0xff, 0xc3, 0x28, 0x80, 0x0a]) + Data("现场 evidence".utf8)
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: KernelCanonicalHashV1.sha256(bytes)
        )
        let request = try DraftImmutableContentWriteRequestV1(
            workspaceID: workspaceID,
            contentID: "unicode-binary-original",
            digest: digest,
            byteLength: Int64(bytes.count),
            mediaType: "application/octet-stream",
            mutationID: try MutationIDV1(rawValue: uuid("c0200000-0000-4000-8000-000000000011")),
            createdAt: "2026-09-10T00:00:00.000Z"
        )
        let store = EvidenceBundleStore(generationRootURL: session.generationRootURL)
        let receipt = try await store.persistImmutableOriginal(bytes: bytes, request: request)
        XCTAssertFalse(receipt.reusedExistingBytes)

        let reference = try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: request.contentID,
            byteLength: Int64(bytes.count),
            mediaType: request.mediaType,
            digests: try ContentDigestSetV1([digest]),
            byteRole: .immutableOriginal,
            createdAt: request.createdAt
        )
        let readback = try await store.readEvidenceDerivativeSource(reference)
        XCTAssertEqual(readback, bytes)
        XCTAssertEqual(Array(readback), Array(bytes))
    }

    @MainActor
    func testEraseRemovesUnicodeWriterPersistedRowsAndOriginalBytesAfterColdRecovery() async throws {
        let harness = try await makeEraseHarness()
        defer { cleanup(harness) }
        let coordinator = harness.coordinator
        let oldOriginalURL = try await persistUnicodeErasePayload(in: coordinator)

        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: harness.bundleIdentifier,
            makeUUID: sequence([
                uuid("c0200000-0000-4000-8000-000000000024"),
                uuid("c0200000-0000-4000-8000-000000000025"),
            ])
        )
        let outcome = try await service.erase(
            confirmation: "ERASE",
            coordinator: coordinator,
            diagnosticsStore: harness.diagnostics
        ) { session in
            coordinator.activate(session: session)
        }
        XCTAssertFalse(outcome.cleanupDeferred)
        XCTAssertFalse(fileManager.fileExists(atPath: oldOriginalURL.path))
        XCTAssertEqual(
            try outcome.session.modelContext.fetchCount(FetchDescriptor<Site>()),
            0
        )
        XCTAssertEqual(
            try outcome.session.modelContext.fetchCount(FetchDescriptor<Asset>()),
            0
        )

        let coldSession = try StoreGenerationFactory(applicationSupportURL: harness.support)
            .openOrBootstrapCurrent()
        XCTAssertEqual(try coldSession.modelContext.fetchCount(FetchDescriptor<Site>()), 0)
        XCTAssertEqual(try coldSession.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertFalse(fileManager.fileExists(atPath: oldOriginalURL.path))
    }

    private let fileManager = FileManager.default

    private func unicodeFixture() throws -> UnicodeFixtureV1 {
        try JSONDecoder().decode(
            UnicodeFixtureV1.self,
            from: Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/V30/Unicode/unicode-evidence-hostile-cases-v1.json"))
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    @MainActor
    private func persistUnicodeErasePayload(
        in coordinator: StoreSessionCoordinator
    ) async throws -> URL {
        let siteID = uuid("c0200000-0000-4000-8000-000000000020")
        let assetID = uuid("c0200000-0000-4000-8000-000000000021")
        let placementMutationID = try MutationIDV1(
            rawValue: uuid("c0200000-0000-4000-8000-000000000022")
        )
        let placementEventID = uuid("c0200000-0000-4000-8000-000000000023")
        let placementEpisodeID = try PhysicalPlacementEpisodeIDV1(
            rawValue: uuid("c0200000-0000-4000-8000-000000000024")
        )
        let siteLabel = "موقع 现场 👩‍🔧"
        let siteAddressNote = "ملاحظة: e\u{301}vidence"
        let assetLabel = "자산 🇺🇸 1️⃣"
        let writer = coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            writerInstanceID: revision.writerInstanceID,
            workspaceRevision: revision.revision,
            entityRevisions: [
                try .init(identity: .init(kind: .asset, id: assetID), revision: 0),
                try .init(identity: .init(kind: .assetPlacementEvent, id: placementEventID), revision: 0),
                try .init(identity: .init(kind: .site, id: siteID), revision: 0),
            ]
        )
        let pack = SignPack.illuminatedSignV1
        let mutationID = try MutationIDV1(rawValue: uuid("c0200000-0000-4000-8000-000000000025"))
        _ = try writer.execute(WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expected,
            command: .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID,
                    label: siteLabel,
                    address: siteAddressNote,
                    timeZoneID: "Asia/Seoul"
                ),
                assetID: assetID,
                assetLabel: assetLabel,
                packID: pack.packID,
                packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_788_000_020),
                initialPlacementMutationID: placementMutationID,
                initialPlacementEventID: placementEventID,
                initialPhysicalEpisodeID: placementEpisodeID
            ))
        ))
        XCTAssertNotNil(try writer.durableReceipt(mutationID: mutationID))

        let persistedSite = try XCTUnwrap(
            coordinator.modelContext.fetch(FetchDescriptor<Site>(
                predicate: #Predicate { $0.id == siteID }
            )).first
        )
        let persistedAsset = try XCTUnwrap(
            coordinator.modelContext.fetch(FetchDescriptor<Asset>(
                predicate: #Predicate { $0.id == assetID }
            )).first
        )
        XCTAssertEqual(Array(persistedSite.label.utf8), Array(siteLabel.utf8))
        XCTAssertEqual(Array((persistedSite.address ?? "").utf8), Array(siteAddressNote.utf8))
        XCTAssertEqual(Array(persistedAsset.label.utf8), Array(assetLabel.utf8))

        let originalBytes = Data([0x00, 0xff, 0xc3, 0x28]) + Data(siteLabel.utf8)
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: KernelCanonicalHashV1.sha256(originalBytes)
        )
        let originalRequest = try DraftImmutableContentWriteRequestV1(
            workspaceID: coordinator.workspaceIdentity.workspaceID,
            contentID: "erase-unicode-original",
            digest: digest,
            byteLength: Int64(originalBytes.count),
            mediaType: "application/octet-stream",
            mutationID: try MutationIDV1(rawValue: uuid("c0200000-0000-4000-8000-000000000026")),
            createdAt: "2026-09-10T00:00:00.000Z"
        )
        let oldOriginalURL = coordinator.generationRootURL
            .appendingPathComponent(originalRequest.relativePath)
        _ = try await EvidenceBundleStore(generationRootURL: coordinator.generationRootURL)
            .persistImmutableOriginal(bytes: originalBytes, request: originalRequest)
        XCTAssertEqual(try Data(contentsOf: oldOriginalURL), originalBytes)
        return oldOriginalURL
    }

    @MainActor
    private func makeEraseHarness() async throws -> EraseHarness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V30-C02-erase-\(UUID().uuidString)", isDirectory: true
        )
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        await diagnostics.prepare()
        let defaultsSuiteName = "V30-C02-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        let bundleIdentifier = "com.palatis3.fieldrecord"
        defaults.setPersistentDomain(["unicode-erase": true], forName: bundleIdentifier)
        return EraseHarness(
            root: root,
            support: support,
            caches: caches,
            temporary: temporary,
            coordinator: StoreSessionCoordinator(session: session),
            diagnostics: diagnostics,
            defaults: defaults,
            defaultsSuiteName: defaultsSuiteName,
            bundleIdentifier: bundleIdentifier
        )
    }

    @MainActor
    private func cleanup(_ harness: EraseHarness) {
        harness.defaults.removePersistentDomain(forName: harness.bundleIdentifier)
        harness.defaults.removePersistentDomain(forName: harness.defaultsSuiteName)
        // StoreSessionCoordinator retains an active SwiftData container through
        // test teardown, so the platform owns final temporary-root cleanup.
    }

    private func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }
}

private struct UnicodeFixtureV1: Decodable {
    let schemaVersion: Int
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let source: String
        let utf8SHA256: String
        let utf8ByteCount: Int
        let scalarCount: Int
        let graphemeCount: Int
        let directionalControls: [DirectionalControl]
    }

    struct DirectionalControl: Decodable {
        let scalarOffset: Int
        let scalarValue: UInt32
    }

    func `case`(named id: String) throws -> Case {
        try XCTUnwrap(cases.first { $0.id == id }, "Missing fixture case: \(id)")
    }
}

@MainActor
private final class EraseHarness {
    let root: URL
    let support: URL
    let caches: URL
    let temporary: URL
    let coordinator: StoreSessionCoordinator
    let diagnostics: DiagnosticsStore
    let defaults: UserDefaults
    let defaultsSuiteName: String
    let bundleIdentifier: String

    init(
        root: URL,
        support: URL,
        caches: URL,
        temporary: URL,
        coordinator: StoreSessionCoordinator,
        diagnostics: DiagnosticsStore,
        defaults: UserDefaults,
        defaultsSuiteName: String,
        bundleIdentifier: String
    ) {
        self.root = root
        self.support = support
        self.caches = caches
        self.temporary = temporary
        self.coordinator = coordinator
        self.diagnostics = diagnostics
        self.defaults = defaults
        self.defaultsSuiteName = defaultsSuiteName
        self.bundleIdentifier = bundleIdentifier
    }
}
