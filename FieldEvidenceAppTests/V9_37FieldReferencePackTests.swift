import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_37FieldReferencePackTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45FieldReferenceCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityPinsTemplateIdentityByRevisionAndDigest() throws {
        let value = try AssetLabelTemplateReferenceV1(
            templateID: "reference-pack-label",
            revision: 7,
            templateSHA256: String(repeating: "b", count: 64)
        )
        XCTAssertEqual(value.revision, 7)
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(value.templateSHA256))
    }
}

private final class C30EvidenceContextAnchorV9_37FieldReferencePack: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private enum C23FieldReferenceTestFailure: Error, Equatable {
    case interrupted
    case readbackInterrupted
    case writerInterrupted
}

private struct C23ProductionClock: ApplicationClock {
    func now() -> Date { C23FieldReferenceTestSupport.fixedDate.addingTimeInterval(10) }
}

private actor C23ProductionAuthentication: LocalAuthenticationClient {
    private(set) var count = 0
    func availability() -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        count += 1
        return .authenticated
    }
    func cancel(attemptID: UUID) {}
}

@MainActor private final class C23ProductionHarness {
    let root: URL
    let store: StoreGenerationSession
    let session: StoreSessionCoordinator
    let gate: AppAccessGateV1
    let authentication = C23ProductionAuthentication()
    let ledger: OwnedStorageLedgerV1
    let actor: ActorSnapshotV1

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("C23-production-\(UUID().uuidString)", isDirectory: true)
        store = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        session = try StoreSessionCoordinator(validatingSession: store)
        gate = AppAccessGateV1(setting: .absentDisabled, authentication: authentication,
            clock: C23ProductionClock(), identifiers: SystemApplicationIDSource())
        ledger = try OwnedStorageLedgerV1(applicationSupportURL: root, capacityProvider: { _ in 1_000_000_000 })
        let reference = try LocalActorReferenceV1(actorReferenceID: C23FieldReferenceTestSupport.id(900),
            workspaceID: store.workspaceID, displayName: "Synthetic reference recorder")
        actor = try .init(snapshotID: C23FieldReferenceTestSupport.id(901), workspaceID: store.workspaceID,
            actor: reference, responsibility: .recordedBy, displayNameAtTime: reference.displayName,
            capturedAt: C23FieldReferenceTestSupport.fixedDate)
        _ = try session.workspaceWriter.execute(.applyPartyAccountability(.appendActorSnapshot(actor)),
            mutationID: C23FieldReferenceTestSupport.mutation(902))
    }

    func lifecycle(ledger: OwnedStorageLedgerV1? = nil) -> ProductionFieldReferencePackLifecycleV1 {
        .init(session: session, accessGate: gate, clock: C23ProductionClock(),
            ownedStorageLedger: ledger ?? self.ledger, expectedApplicationSupportURL: root)
    }

    @discardableResult
    func appendPacket(version: UInt64 = 1) throws -> WorkPacketManifestV1 {
        let value = try WorkPacketManifestV1(manifestID: C23FieldReferenceTestSupport.id(1000 + Int(version)),
            packetID: C23FieldReferenceTestSupport.id(200), packetVersion: version, workspaceID: store.workspaceID,
            items: [.init(itemID: "reference-work", kind: .inspection, expectedRevision: 1,
                itemSHA256: C23FieldReferenceTestSupport.digest())], packageReleases: [],
            creationBasis: .explicitLocalSelection, creator: actor, createdAt: C23FieldReferenceTestSupport.fixedDate,
            mutationID: C23FieldReferenceTestSupport.mutation(1100 + Int(version)))
        let mutation = try WorkPacketMutationV1(workspaceID: store.workspaceID, expectedRevision: 0,
            mutationID: value.mutationID, postImage: .appendManifest(value))
        _ = try session.workspaceWriter.execute(.applyWorkPacket(mutation), mutationID: mutation.mutationID)
        return value
    }

    func content(_ plan: FieldReferenceImportPlanV1) async throws -> [FieldReferenceImportedContentV1.Entry] {
        try await EvidenceBundleStore(generationRootURL: session.generationRootURL)
            .readFieldReferenceContent(XCTUnwrap(plan.release.importedContent))
    }

    func close() {
        try? session.invalidateAndReleaseWriter()
        try? FileManager.default.removeItem(at: root)
    }
}

enum C23FieldReferenceTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2300000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func digest(_ byte: Character = "a") -> String {
        String(repeating: byte, count: 64)
    }

    static func workspaceString(_ workspaceID: WorkspaceID) -> String {
        workspaceID.rawValue.uuidString.lowercased()
    }

    struct ContentFixture: Equatable, Sendable {
        let reference: ContentReferenceV1
        let locator: ContentLocatorV1
        let bytes: Data
    }

    static func content(
        workspaceID: WorkspaceID,
        index: Int
    ) throws -> ContentFixture {
        let contentID = String(format: "c23.reference.%03d", index)
        let bytes = Data("C23 immutable original \(contentID)".utf8)
        let observed = try ContentIntegrityV1.observe(
            workspaceID: workspaceString(workspaceID),
            contentID: contentID,
            data: bytes,
            mediaType: "text/plain"
        )
        guard let digest = observed.digests.digest(for: .sha256) else {
            throw FieldReferencePackFailureV1.invalidDigest
        }
        let reference = try ContentReferenceV1(
            workspaceID: workspaceString(workspaceID),
            contentID: contentID,
            byteLength: Int64(bytes.count),
            mediaType: "text/plain",
            digests: observed.digests,
            byteRole: .immutableOriginal,
            createdAt: "2026-01-01T00:00:00Z"
        )
        let locator = try ContentLocatorV1(
            locatorID: "c23-locator-\(index)",
            workspaceID: workspaceString(workspaceID),
            contentID: contentID,
            locatorRevision: 1,
            contentDigest: digest,
            expectedByteLength: Int64(bytes.count)
        )
        return ContentFixture(reference: reference, locator: locator, bytes: bytes)
    }

    static func contents(
        workspaceID: WorkspaceID,
        count: Int = 2
    ) throws -> [ContentFixture] {
        try (1...count).map { try content(workspaceID: workspaceID, index: $0) }
    }

    static func manifest(
        workspaceID: WorkspaceID,
        contents: [ContentFixture],
        revision: Int = 1
    ) throws -> ContentManifestV1 {
        let entries = try contents.map { item in
            guard let digest = item.reference.digests.digest(for: .sha256) else {
                throw FieldReferencePackFailureV1.invalidDigest
            }
            return try ContentManifestEntryV1(
                contentID: item.reference.contentID,
                expectedByteLength: item.reference.byteLength,
                mediaType: item.reference.mediaType,
                digest: digest,
                expectedLocatorRevision: item.locator.locatorRevision,
                requiredForOpen: true
            )
        }
        return try ContentManifestV1(
            manifestID: "c23.reference-manifest",
            workspaceID: workspaceString(workspaceID),
            manifestRevision: revision,
            entries: entries.sorted { $0.contentID < $1.contentID }
        )
    }

    static func provenance(
        kind: FieldReferenceProvenanceKindV1 = .synthetic,
        scope: FieldReferenceLicenseScopeV1 = .localUseOnly,
        notice: String? = nil
    ) throws -> FieldReferenceProvenanceV1 {
        try FieldReferenceProvenanceV1(
            kind: kind,
            sourceName: "C23 deterministic field references",
            sourceReleaseIdentifier: "c23.reference.corpus.v1",
            licenseScope: scope,
            licenseNotice: notice
        )
    }

    static func release(
        workspaceID: WorkspaceID,
        contents: [ContentFixture],
        releaseID: UUID? = nil,
        disposition: FieldReferenceReleaseDispositionV1 = .active,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        supersedesReleaseID: UUID? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 10,
        provenance: FieldReferenceProvenanceV1? = nil,
        importedContent: FieldReferenceImportedContentV1? = nil
    ) throws -> FieldReferenceReleaseV1 {
        try FieldReferenceReleaseV1(
            releaseID: releaseID ?? id(2),
            workspaceID: workspaceID,
            referencePackID: "c23.field-reference-pack",
            kind: .specification,
            semanticVersion: revision == 1 ? "1.0.0" : "1.0.1",
            provenance: provenance ?? self.provenance(),
            manifest: try manifest(workspaceID: workspaceID, contents: contents),
            releaseDisposition: disposition,
            issuedAt: fixedDate,
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            supersedesReleaseID: supersedesReleaseID,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            importedContent: importedContent
        )
    }

    static func productionPlan(workspaceID: WorkspaceID, index: Int = 91) throws -> FieldReferenceImportPlanV1 {
        let original = try content(workspaceID: workspaceID, index: index)
        let observed = try ContentIntegrityV1.observe(workspaceID: original.reference.workspaceID,
            contentID: original.reference.contentID, data: original.bytes,
            mediaType: original.reference.mediaType, algorithms: [.sha256, .sha512])
        let reference = try ContentReferenceV1(workspaceID: original.reference.workspaceID,
            contentID: original.reference.contentID, byteLength: original.reference.byteLength,
            mediaType: original.reference.mediaType, digests: observed.digests,
            byteRole: .immutableOriginal, createdAt: original.reference.createdAt)
        let locator = try EvidenceBundleStore.fieldReferenceLocator(for: reference)
        let metadata = try FieldReferenceImportedContentV1(entries: [.init(reference: reference, locator: locator)])
        let release = try release(workspaceID: workspaceID,
            contents: [.init(reference: reference, locator: locator, bytes: original.bytes)],
            importedContent: metadata)
        return try .init(release: release, items: [.init(reference: reference, locator: locator, bytes: original.bytes)])
    }

    static func binding(
        workspaceID: WorkspaceID,
        release: FieldReferenceReleaseV1,
        subjectID: UUID? = nil,
        subjectRevision: UInt64 = 1,
        subjectState: FieldReferenceSubjectStateV1 = .active,
        supersedesBindingID: UUID? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 20
    ) throws -> FieldReferenceBindingV1 {
        try FieldReferenceBindingV1(
            bindingID: id(3 + Int(revision)),
            workspaceID: workspaceID,
            subjectKind: .workPacket,
            subjectID: subjectID ?? id(200),
            subjectRevision: subjectRevision,
            subjectState: subjectState,
            release: release,
            boundAt: fixedDate.addingTimeInterval(2),
            supersedesBindingID: supersedesBindingID,
            revision: revision,
            mutationID: try mutation(mutationSlot)
        )
    }

    static func plan(
        workspaceID: WorkspaceID,
        contents: [ContentFixture],
        release: FieldReferenceReleaseV1? = nil
    ) throws -> FieldReferenceImportPlanV1 {
        let release = try release ?? self.release(workspaceID: workspaceID, contents: contents)
        let items = try contents.map {
            try FieldReferenceImportItemV1(
                reference: $0.reference,
                locator: $0.locator,
                bytes: $0.bytes
            )
        }
        return try FieldReferenceImportPlanV1(release: release, items: items)
    }

    static func receipt(
        mutationID: MutationIDV1,
        postImageSHA256: String,
        receiptByte: Character = "e"
    ) throws -> FieldReferenceWriteReceiptV1 {
        try FieldReferenceWriteReceiptV1(
            mutationID: mutationID,
            postImageSHA256: postImageSHA256,
            canonicalMutationReceiptSHA256: digest(receiptByte)
        )
    }

    static func lifecycleOperations(
        plan: FieldReferenceImportPlanV1,
        release: FieldReferenceReleaseV1,
        binding: FieldReferenceBindingV1,
        interruption: @escaping @Sendable (FieldReferenceInterruptionPointV1) async throws -> Void = { _ in }
    ) -> FieldReferencePackLifecycleOperationsV1 {
        FieldReferencePackLifecycleOperationsV1(
            persist: { _ in },
            validateReadback: { _ in },
            readinessInputs: { _, _, evaluatedAt in
                FieldReferenceReadinessInputsV1(
                    references: plan.items.map(\.reference),
                    locators: plan.items.map(\.locator),
                    knownSupersededReleaseIDs: [],
                    evaluatedAt: evaluatedAt,
                    policy: .exactLocalContentV1,
                    protectedDataAvailable: true
                )
            },
            discardIfUnbound: { _ in },
            acceptedRelease: { _ in nil },
            appendRelease: { value in
                try receipt(mutationID: value.mutationID, postImageSHA256: value.releaseSHA256)
            },
            acceptedBinding: { _, _ in nil },
            appendBinding: { value, _ in
                try receipt(mutationID: value.mutationID, postImageSHA256: value.bindingSHA256)
            },
            interruption: interruption
        )
    }

    static func decodedCorpus() throws -> C23FieldReferenceCorpus {
        let url = try XCTUnwrap(
            Bundle(for: V9_37FieldReferencePackTests.self).url(
                forResource: "V22P03C23FieldReferencePackCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/FieldReferences"
            ) ?? Bundle(for: V9_37FieldReferencePackTests.self).url(
                forResource: "V22P03C23FieldReferencePackCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(C23FieldReferenceCorpus.self, from: Data(contentsOf: url))
    }
}

actor C23FieldReferenceContentStore: FieldReferenceContentAuthorityV1 {
    private var plans: [UUID: FieldReferenceImportPlanV1] = [:]
    private let failPersist: Bool
    private let failReadback: Bool
    private let failReadiness: Bool
    private let protectedDataAvailable: Bool
    private let knownSuccessorReleaseIDs: Set<UUID>
    private var persistCount = 0
    private var discardCount = 0

    init(
        failPersist: Bool = false,
        failReadback: Bool = false,
        failReadiness: Bool = false,
        protectedDataAvailable: Bool = true,
        knownSuccessorReleaseIDs: Set<UUID> = []
    ) {
        self.failPersist = failPersist
        self.failReadback = failReadback
        self.failReadiness = failReadiness
        self.protectedDataAvailable = protectedDataAvailable
        self.knownSuccessorReleaseIDs = knownSuccessorReleaseIDs
    }

    func seed(_ plan: FieldReferenceImportPlanV1) {
        plans[plan.release.releaseID] = plan
    }

    func persist(_ plan: FieldReferenceImportPlanV1) async throws {
        if failPersist { throw C23FieldReferenceTestFailure.interrupted }
        plans[plan.release.releaseID] = plan
        persistCount += 1
    }

    func validateReadback(_ plan: FieldReferenceImportPlanV1) async throws {
        if failReadback { throw C23FieldReferenceTestFailure.readbackInterrupted }
        guard plans[plan.release.releaseID] == plan else {
            throw FieldReferencePackFailureV1.missingContent
        }
    }

    func readinessInputs(
        release: FieldReferenceReleaseV1,
        binding: FieldReferenceBindingV1,
        evaluatedAt: Date
    ) async throws -> FieldReferenceReadinessInputsV1 {
        if failReadiness { throw C23FieldReferenceTestFailure.interrupted }
        let plan = plans[release.releaseID]
        return FieldReferenceReadinessInputsV1(
            references: plan?.items.map(\.reference) ?? [],
            locators: plan?.items.map(\.locator) ?? [],
            knownSupersededReleaseIDs: knownSuccessorReleaseIDs,
            evaluatedAt: evaluatedAt,
            policy: .exactLocalContentV1,
            protectedDataAvailable: protectedDataAvailable
        )
    }

    func discardIfUnbound(_ plan: FieldReferenceImportPlanV1) async throws {
        plans.removeValue(forKey: plan.release.releaseID)
        discardCount += 1
    }

    func counts() -> (persist: Int, discard: Int) {
        (persistCount, discardCount)
    }
}

actor C23FieldReferenceWriter: FieldReferencePackWritingV1 {
    private var releaseReceipts: [UUID: FieldReferenceWriteReceiptV1] = [:]
    private var bindingReceipts: [UUID: FieldReferenceWriteReceiptV1] = [:]
    private let wrongReleaseReceipt: Bool
    private let failBindingAppend: Bool
    private var releaseAppendCount = 0
    private var bindingAppendCount = 0

    init(wrongReleaseReceipt: Bool = false, failBindingAppend: Bool = false) {
        self.wrongReleaseReceipt = wrongReleaseReceipt
        self.failBindingAppend = failBindingAppend
    }

    func acceptedReleaseReceipt(for release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1? {
        releaseReceipts[release.releaseID]
    }

    func appendRelease(_ release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1 {
        if let existing = releaseReceipts[release.releaseID] { return existing }
        releaseAppendCount += 1
        let mutationID = wrongReleaseReceipt
            ? try C23FieldReferenceTestSupport.mutation(999)
            : release.mutationID
        let receipt = try C23FieldReferenceTestSupport.receipt(
            mutationID: mutationID,
            postImageSHA256: release.releaseSHA256
        )
        releaseReceipts[release.releaseID] = receipt
        return receipt
    }

    func acceptedBindingReceipt(
        for binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1
    ) async throws -> FieldReferenceWriteReceiptV1? {
        bindingReceipts[binding.bindingID]
    }

    func appendBinding(
        _ binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1
    ) async throws -> FieldReferenceWriteReceiptV1 {
        if failBindingAppend { throw C23FieldReferenceTestFailure.writerInterrupted }
        if let existing = bindingReceipts[binding.bindingID] { return existing }
        bindingAppendCount += 1
        let receipt = try C23FieldReferenceTestSupport.receipt(
            mutationID: binding.mutationID,
            postImageSHA256: binding.bindingSHA256
        )
        bindingReceipts[binding.bindingID] = receipt
        return receipt
    }

    func counts() -> (release: Int, binding: Int) {
        (releaseAppendCount, bindingAppendCount)
    }
}

struct C23FieldReferenceCorpus: Decodable {
    struct Selector: Decodable {
        let id: String
        let selector: String
        let focus: String
    }

    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let evidenceIDs: [String]
    let evidenceSelectors: [Selector]
    let referenceKinds: [String]
    let provenanceKinds: [String]
    let licenseScopes: [String]
    let releaseDispositions: [String]
    let subjectKinds: [String]
    let subjectStates: [String]
    let availabilityStates: [String]
    let interruptionBoundaries: [String]
    let hostileCases: [String]
    let lifecycleConsumers: [String]
    let privacyExclusions: [String]
    let forbiddenClaims: [String]
    let immutableOriginals: Bool
    let externalCopyAvailabilityClaimed: Bool
    let runtimeFetchingAllowed: Bool
    let drmOrAccountRequired: Bool
    let currentProjectionPersistent: Bool
    let noSecondWriter: Bool
    let noSecondStore: Bool
}

@MainActor
final class V9_37FieldReferencePackTests: XCTestCase {
    func testProductionImportAndWorkPacketBindingKeepOriginalReceiptsAcrossColdRetry() async throws {
        let h = try C23ProductionHarness()
        defer { h.close() }
        let packet = try h.appendPacket()
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: h.store.workspaceID)
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: h.store.workspaceID,
            release: plan.release, subjectID: packet.packetID, subjectRevision: packet.packetVersion)
        let writer = h.session.workspaceWriter
        let before = try writer.sourceMutationHistorySnapshot()
        let lifecycle = h.lifecycle()
        let imported = try await lifecycle.importRelease(plan)
        let bound = try await lifecycle.bind(binding, to: plan.release)
        XCTAssertEqual(imported.postImageSHA256, plan.release.releaseSHA256)
        XCTAssertEqual(bound.postImageSHA256, binding.bindingSHA256)
        let originalImport = try XCTUnwrap(writer.fieldReferenceReceipt(for: .importRelease(plan.release)))
        let originalBinding = try XCTUnwrap(writer.fieldReferenceReceipt(for: .bind(value: binding, release: plan.release)))
        XCTAssertEqual(imported.canonicalMutationReceiptSHA256, try originalImport.canonicalSHA256())
        XCTAssertEqual(bound.canonicalMutationReceiptSHA256, try originalBinding.canonicalSHA256())
        let history = try writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(history.receipts.count, before.receipts.count + 2)
        let cold = h.lifecycle()
        let importRetry = try await cold.importRelease(plan)
        let bindingRetry = try await cold.bind(binding, to: plan.release)
        XCTAssertEqual(importRetry, imported)
        XCTAssertEqual(bindingRetry, bound)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertEqual(try writer.fieldReferenceReceipt(for: .importRelease(plan.release)), originalImport)
        XCTAssertEqual(try writer.fieldReferenceReceipt(for: .bind(value: binding, release: plan.release)), originalBinding)
        let readback = try await h.content(plan)
        XCTAssertEqual(readback, plan.release.importedContent?.entries)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        XCTAssertEqual(h.ledger.snapshot().reservedByteCount, 0)
        try await cold.discardIfUnbound(plan)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        let retained = try await h.content(plan)
        XCTAssertEqual(retained, readback)

        _ = try h.appendPacket(version: 2)
        let advanced = try writer.sourceMutationHistorySnapshot()
        do {
            _ = try await cold.bind(binding, to: plan.release)
            XCTFail("An original receipt cannot authorize binding against a later packet revision")
        } catch { XCTAssertEqual(error as? FieldReferencePackFailureV1, .staleBinding) }
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), advanced)
        let successor = try C23FieldReferenceTestSupport.binding(workspaceID: h.store.workspaceID,
            release: plan.release, subjectID: packet.packetID, subjectRevision: 2,
            supersedesBindingID: binding.bindingID, revision: 2, mutationSlot: 21)
        let next = try await cold.bind(successor, to: plan.release)
        XCTAssertEqual(next.postImageSHA256, successor.bindingSHA256)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 1)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceBindingRow>()), 2)
        let authCalls = await h.authentication.count
        XCTAssertEqual(authCalls, 0)
    }

    #if DEBUG
    func testProductionImportAndBindingRecoverLostRepliesAndRecheckBytesBeforeBinding() async throws {
        let h = try C23ProductionHarness()
        defer { h.close() }
        let packet = try h.appendPacket()
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: h.store.workspaceID)
        let lifecycle = h.lifecycle()
        lifecycle.interruptionForTesting = { point in
            if point == .afterReleaseBeforeReturn { throw C23FieldReferenceTestFailure.writerInterrupted }
        }
        do {
            _ = try await lifecycle.importRelease(plan)
            XCTFail("Lost import reply must preserve its interruption")
        } catch { XCTAssertEqual(error as? C23FieldReferenceTestFailure, .writerInterrupted) }
        let writer = h.session.workspaceWriter
        let original = try XCTUnwrap(writer.fieldReferenceReceipt(for: .importRelease(plan.release)))
        let importedHistory = try writer.sourceMutationHistorySnapshot()
        let recovered = try await h.lifecycle().importRelease(plan)
        XCTAssertEqual(recovered.canonicalMutationReceiptSHA256, try original.canonicalSHA256())
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), importedHistory)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: h.store.workspaceID,
            release: plan.release, subjectID: packet.packetID)
        let item = plan.items[0]
        let target = h.session.generationRootURL.appendingPathComponent("content/\(item.reference.workspaceID)/\(item.reference.contentID)/original.bin")
        lifecycle.interruptionForTesting = { point in
            if point == .afterReadinessBeforeBinding {
                var corrupt = item.bytes; corrupt[0] ^= 1
                try corrupt.write(to: target)
            }
        }
        do {
            _ = try await lifecycle.bind(binding, to: plan.release)
            XCTFail("A prior readiness calculation cannot hide subsequent byte corruption")
        } catch { XCTAssertEqual(error as? ContentIntegrityFailureV1, .digestMismatch) }
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), importedHistory)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceBindingRow>()), 0)
        try item.bytes.write(to: target)
        lifecycle.interruptionForTesting = { point in
            if point == .afterBindingBeforeReturn { throw C23FieldReferenceTestFailure.writerInterrupted }
        }
        do {
            _ = try await lifecycle.bind(binding, to: plan.release)
            XCTFail("Lost binding reply must preserve its interruption")
        } catch { XCTAssertEqual(error as? C23FieldReferenceTestFailure, .writerInterrupted) }
        let originalBinding = try XCTUnwrap(writer.fieldReferenceReceipt(for: .bind(value: binding, release: plan.release)))
        let boundHistory = try writer.sourceMutationHistorySnapshot()
        let retry = try await h.lifecycle().bind(binding, to: plan.release)
        XCTAssertEqual(retry.canonicalMutationReceiptSHA256, try originalBinding.canonicalSHA256())
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), boundHistory)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceBindingRow>()), 1)
        let bytes = try await h.content(plan)
        XCTAssertEqual(bytes, plan.release.importedContent?.entries)
    }

    func testProductionImportReleasesReservationsAndRetainsUnprovedContentOnInterruption() async throws {
        let h = try C23ProductionHarness()
        defer { h.close() }
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: h.store.workspaceID)
        let before = try h.session.workspaceWriter.sourceMutationHistorySnapshot()
        let lowStorage = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in 1 })
        do {
            _ = try await h.lifecycle(ledger: lowStorage).importRelease(plan)
            XCTFail("Import must honor real storage admission before writing")
        } catch {
            guard case .insufficientCapacity? = error as? OwnedStorageLedgerFailureV1 else {
                return XCTFail("Unexpected admission failure: \(error)")
            }
        }
        XCTAssertEqual(try h.session.workspaceWriter.sourceMutationHistorySnapshot(), before)
        let absent = try await h.content(plan)
        XCTAssertTrue(absent.isEmpty)
        XCTAssertEqual(lowStorage.snapshot().activeReservationCount, 0)
        let lifecycle = h.lifecycle()
        lifecycle.interruptionForTesting = { point in
            if point == .afterContentReadbackBeforeRelease { throw C23FieldReferenceTestFailure.interrupted }
        }
        do {
            _ = try await lifecycle.importRelease(plan)
            XCTFail("Injected interruption must preserve its original failure")
        } catch { XCTAssertEqual(error as? C23FieldReferenceTestFailure, .interrupted) }
        XCTAssertEqual(try h.session.workspaceWriter.sourceMutationHistorySnapshot(), before)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        XCTAssertEqual(h.ledger.snapshot().reservedByteCount, 0)
        let unbound = try await h.content(plan)
        XCTAssertEqual(unbound, plan.release.importedContent?.entries)
        do {
            try await lifecycle.discardIfUnbound(plan)
            XCTFail("Absent C23 binding does not prove global deletion authority")
        } catch { XCTAssertEqual(error as? ProductionFieldReferenceLifecycleFailureV1, .cleanupDeferred) }
        let retained = try await h.content(plan)
        XCTAssertEqual(retained, unbound)
        lifecycle.interruptionForTesting = nil
        _ = try await lifecycle.importRelease(plan)
        try await lifecycle.discardIfUnbound(plan)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 1)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        let published = try await h.content(plan)
        XCTAssertEqual(published, unbound)
    }

    func testProductionImportAndBindingRejectRevokedOriginalTokenAndChangedPacketSource() async throws {
        let h = try C23ProductionHarness()
        defer { h.close() }
        let packet = try h.appendPacket()
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: h.store.workspaceID)
        let before = try h.session.workspaceWriter.sourceMutationHistorySnapshot()
        let lifecycle = h.lifecycle(), gate = h.gate
        lifecycle.interruptionForTesting = { point in
            if point == .afterContentReadbackBeforeRelease {
                await gate.sceneBecameInactive()
                await gate.sceneBecameActive()
            }
        }
        do {
            _ = try await lifecycle.importRelease(plan)
            XCTFail("Reenabled access cannot revive the original operation token")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        XCTAssertEqual(try h.session.workspaceWriter.sourceMutationHistorySnapshot(), before)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        let retained = try await h.content(plan)
        XCTAssertEqual(retained, plan.release.importedContent?.entries)
        lifecycle.interruptionForTesting = nil
        _ = try await lifecycle.importRelease(plan)
        let imported = try h.session.workspaceWriter.sourceMutationHistorySnapshot()
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: h.store.workspaceID,
            release: plan.release, subjectID: packet.packetID)
        lifecycle.interruptionForTesting = { point in
            if point == .afterReadinessBeforeBinding {
                try await MainActor.run { _ = try h.appendPacket(version: 2) }
            }
        }
        do {
            _ = try await lifecycle.bind(binding, to: plan.release)
            XCTFail("Binding cannot publish after its observed packet frontier changes")
        } catch { XCTAssertEqual(error as? ProductionFieldReferenceLifecycleFailureV1, .sourcesChanged) }
        let changed = try h.session.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertEqual(changed.receipts.count, imported.receipts.count + 1)
        XCTAssertNil(try h.session.workspaceWriter.fieldReferenceReceipt(for: .bind(value: binding, release: plan.release)))
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceBindingRow>()), 0)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 1)
        let after = try await h.content(plan)
        XCTAssertEqual(after, retained)
    }

    func testProductionImportRetirementKeepsBytesUnboundAndRequiresFreshCurrentSession() async throws {
        let h = try C23ProductionHarness()
        defer { h.close() }
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: h.store.workspaceID)
        let lifecycle = h.lifecycle()
        let oldWriter = h.session.workspaceWriter
        let before = try oldWriter.sourceMutationHistorySnapshot()
        lifecycle.interruptionForTesting = { point in
            if point == .afterContentReadbackBeforeRelease {
                try await MainActor.run { try h.session.invalidateAndReleaseWriter() }
            }
        }
        do {
            _ = try await lifecycle.importRelease(plan)
            XCTFail("Retired writer must not publish the imported release")
        } catch { XCTAssertEqual(error as? WorkspaceMutationFailureV1, .writerInvalidated) }
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 0)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        let orphan = try await h.content(plan)
        XCTAssertEqual(orphan, plan.release.importedContent?.entries)
        try h.session.activateValidating(session: h.store)
        XCTAssertFalse(oldWriter === h.session.workspaceWriter)
        XCTAssertEqual(try h.session.workspaceWriter.sourceMutationHistorySnapshot(), before)
        lifecycle.interruptionForTesting = nil
        do {
            _ = try await lifecycle.importRelease(plan)
            XCTFail("An old session composition must not borrow a replacement writer")
        } catch { XCTAssertEqual(error as? ProductionFieldReferenceLifecycleFailureV1, .sessionChanged) }
        let fresh = h.lifecycle()
        let imported = try await fresh.importRelease(plan)
        XCTAssertEqual(imported.postImageSHA256, plan.release.releaseSHA256)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 1)
        let restored = try await h.content(plan)
        XCTAssertEqual(restored, orphan)
    }
    #endif

    func testProductionImportRejectsDanglingCanonicalPacketMembershipBeforeWriting() async throws {
        let h = try C23ProductionHarness()
        defer { h.close() }
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: h.store.workspaceID)
        let missing = try WorkPacketManifestV1(manifestID: C23FieldReferenceTestSupport.id(1200),
            packetID: C23FieldReferenceTestSupport.id(1201), packetVersion: 1, workspaceID: h.store.workspaceID,
            items: [.init(itemID: "unretained-packet-item", kind: .inspection, expectedRevision: 1,
                itemSHA256: C23FieldReferenceTestSupport.digest())], packageReleases: [],
            creationBasis: .explicitLocalSelection, creator: h.actor, createdAt: C23FieldReferenceTestSupport.fixedDate,
            mutationID: C23FieldReferenceTestSupport.mutation(1202))
        let holder = try ActorSnapshotV1(snapshotID: C23FieldReferenceTestSupport.id(1203), workspaceID: h.store.workspaceID,
            actor: h.actor.actor, responsibility: .assignedTo, displayNameAtTime: h.actor.displayNameAtTime,
            capturedAt: C23FieldReferenceTestSupport.fixedDate)
        let claim = try WorkItemClaimV1(claimID: C23FieldReferenceTestSupport.id(1204), workspaceID: h.store.workspaceID,
            manifest: .init(missing), item: .init(manifest: missing, item: missing.items[0]),
            holder: holder, claimSequence: 1, claimedAt: C23FieldReferenceTestSupport.fixedDate,
            mutationID: C23FieldReferenceTestSupport.mutation(1205))
        let context = h.session.modelContext
        let before = try h.session.workspaceWriter.sourceMutationHistorySnapshot()
        let count = try context.fetchCount(FetchDescriptor<MutationReceiptRow>())
        // Deliberate corrupt-source fixture: no canonical writer can append a
        // claim for an unretained manifest. Admission must not filter it away.
        let row = try WorkItemClaimRow(claim)
        context.insert(row)
        try context.save()
        do {
            _ = try await h.lifecycle().importRelease(plan)
            XCTFail("Dangling canonical packet membership must stop import")
        } catch { XCTAssertEqual(error as? ProductionFieldReferenceLifecycleFailureV1, .sourcesChanged) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MutationReceiptRow>()), count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 0)
        let absent = try await h.content(plan)
        XCTAssertTrue(absent.isEmpty)
        XCTAssertEqual(h.ledger.snapshot().activeReservationCount, 0)
        context.delete(row)
        try context.save()
        XCTAssertEqual(try h.session.workspaceWriter.sourceMutationHistorySnapshot(), before)
    }

    func testImportedReleaseMetadataIsClosedAndSurvivesCanonicalRebinding() throws {
        let workspace = C23FieldReferenceTestSupport.workspace()
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: workspace)
        let release = plan.release, metadata = try XCTUnwrap(release.importedContent)
        XCTAssertEqual(FieldReferenceReleaseV1.schemaVersion, 1)
        XCTAssertEqual(release.schemaVersion, 2)
        XCTAssertEqual(metadata.entries[0].reference.digests.values.map(\.algorithm), [.sha256, .sha512])
        let encoded = try FieldReferencePackCanonicalCodecV1.encode(release)
        XCTAssertEqual(try FieldReferencePackCanonicalCodecV1.decode(FieldReferenceReleaseV1.self, from: encoded), release)
        XCTAssertEqual(try FieldReferenceReleaseRow(release).value(), release)
        try release.validateContent(references: plan.items.map(\.reference), locators: plan.items.map(\.locator))
        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            change(&object)
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        let bad: [Data] = try [
            mutated { $0["schemaVersion"] = 1 },
            mutated { $0["schemaVersion"] = 99 },
            mutated { $0.removeValue(forKey: "importedContent") },
            mutated { $0["importedContent"] = NSNull() },
            mutated { $0["unknown"] = true },
            mutated { value in
                var payload = value["importedContent"] as! [String: Any]
                payload["schemaVersion"] = 99; value["importedContent"] = payload
            },
            mutated { value in
                var payload = value["importedContent"] as! [String: Any]
                payload["unknown"] = true; value["importedContent"] = payload
            },
            mutated { value in
                var payload = value["importedContent"] as! [String: Any]
                var entries = payload["entries"] as! [[String: Any]]
                entries[0]["unknown"] = true; payload["entries"] = entries; value["importedContent"] = payload
            }
        ]
        for bytes in bad {
            XCTAssertThrowsError(try FieldReferencePackCanonicalCodecV1.decode(FieldReferenceReleaseV1.self, from: bytes))
        }
        let legacy = try C23FieldReferenceTestSupport.release(workspaceID: workspace,
            contents: plan.items.map { .init(reference: $0.reference, locator: $0.locator, bytes: $0.bytes) })
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertNil(legacy.importedContent)
        // Frozen pre-import-metadata wire shape: this fixture intentionally has
        // no knowledge of the new optional payload or its production encoder.
        struct LegacyWire: Encodable {
            let schemaVersion = 1
            let releaseID: UUID; let workspaceID: WorkspaceID; let referencePackID: String
            let kind: FieldReferenceKindV1; let semanticVersion: String; let provenance: FieldReferenceProvenanceV1
            let manifest: ContentManifestV1; let manifestSHA256: String
            let releaseDisposition: FieldReferenceReleaseDispositionV1; let issuedAt: Date
            let expiresAt: Date?; let revokedAt: Date?; let supersedesReleaseID: UUID?
            let revision: UInt64; let mutationID: MutationIDV1; let releaseSHA256: String
            init(_ v: FieldReferenceReleaseV1) {
                releaseID = v.releaseID; workspaceID = v.workspaceID; referencePackID = v.referencePackID
                kind = v.kind; semanticVersion = v.semanticVersion; provenance = v.provenance
                manifest = v.manifest; manifestSHA256 = v.manifestSHA256; releaseDisposition = v.releaseDisposition
                issuedAt = v.issuedAt; expiresAt = v.expiresAt; revokedAt = v.revokedAt
                supersedesReleaseID = v.supersedesReleaseID; revision = v.revision; mutationID = v.mutationID
                releaseSHA256 = v.releaseSHA256
            }
        }
        let oldEncoder = JSONEncoder()
        oldEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        oldEncoder.dateEncodingStrategy = .millisecondsSince1970
        let expectedLegacyBytes = try oldEncoder.encode(LegacyWire(legacy))
        let legacyBytes = try FieldReferencePackCanonicalCodecV1.encode(legacy)
        XCTAssertEqual(legacyBytes, expectedLegacyBytes)
        var oldBasis = try XCTUnwrap(JSONSerialization.jsonObject(with: expectedLegacyBytes) as? [String: Any])
        oldBasis.removeValue(forKey: "releaseSHA256")
        let oldBasisBytes = try JSONSerialization.data(withJSONObject: oldBasis,
            options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertEqual(legacy.releaseSHA256, KernelCanonicalHashV1.sha256(oldBasisBytes))
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyBytes) as? [String: Any])
        XCTAssertNil(legacyObject["importedContent"])
        XCTAssertNotEqual(legacy.releaseSHA256, release.releaseSHA256)
        XCTAssertEqual(try FieldReferencePackCanonicalCodecV1.decode(FieldReferenceReleaseV1.self, from: legacyBytes), legacy)
        let destination = C23FieldReferenceTestSupport.workspace(902)
        let reboundMetadata = try metadata.rebound(to: destination)
        let manifest = try C23FieldReferenceTestSupport.manifest(workspaceID: destination,
            contents: zip(reboundMetadata.entries, plan.items).map {
                .init(reference: $0.0.reference, locator: $0.0.locator, bytes: $0.1.bytes)
            })
        let rebound = try release.rebound(to: destination, manifest: manifest)
        XCTAssertEqual(rebound.importedContent, reboundMetadata)
        XCTAssertEqual(rebound.releaseID, release.releaseID)
        XCTAssertEqual(rebound.mutationID, release.mutationID)
        XCTAssertEqual(reboundMetadata.entries[0].reference.digests, metadata.entries[0].reference.digests)
        XCTAssertEqual(reboundMetadata.entries[0].reference.createdAt, metadata.entries[0].reference.createdAt)
        XCTAssertEqual(reboundMetadata.entries[0].locator.locatorID, metadata.entries[0].locator.locatorID)
        XCTAssertEqual(reboundMetadata.entries[0].locator.locatorRevision, 0)
        XCTAssertNotEqual(rebound.releaseSHA256, release.releaseSHA256)
        XCTAssertEqual(try release.rebound(to: workspace, manifest: release.manifest), release)
        XCTAssertFalse(FieldReferenceRetentionV1.mayExportBytes(rebound))
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: workspace, release: release)
        let reboundBinding = try binding.rebound(to: destination, release: rebound)
        try reboundBinding.validate(release: rebound)
        XCTAssertFalse(FieldReferenceRetentionV1.mayDiscardRelease(rebound, bindings: [reboundBinding]))
    }

    func testImportedMetadataBoundsAndFullReferenceEqualityRejectManifestOnlySubstitution() throws {
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: C23FieldReferenceTestSupport.workspace())
        let entry = try XCTUnwrap(plan.release.importedContent?.entries.first)
        XCTAssertThrowsError(try FieldReferenceImportedContentV1(entries: []))
        XCTAssertThrowsError(try FieldReferenceImportedContentV1(entries: [entry, entry]))
        let boundedEntries = try (0..<257).map { index -> FieldReferenceImportedContentV1.Entry in
            let reference = try ContentReferenceV1(workspaceID: entry.reference.workspaceID,
                contentID: String(format: "bounded-entry-%03d", index), byteLength: entry.reference.byteLength,
                mediaType: entry.reference.mediaType, digests: entry.reference.digests,
                byteRole: .immutableOriginal, createdAt: entry.reference.createdAt)
            return try .init(reference: reference, locator: EvidenceBundleStore.fieldReferenceLocator(for: reference))
        }
        XCTAssertEqual(try FieldReferenceImportedContentV1(entries: Array(boundedEntries.prefix(256))).entries.count, 256)
        XCTAssertThrowsError(try FieldReferenceImportedContentV1(entries: boundedEntries))
        let prior = entry.reference
        let changedDate = try ContentReferenceV1(workspaceID: prior.workspaceID, contentID: prior.contentID,
            byteLength: prior.byteLength, mediaType: prior.mediaType, digests: prior.digests,
            byteRole: prior.byteRole, createdAt: "2026-01-02T00:00:00Z")
        // The manifest alone cannot see createdAt, secondary digests or locator identity.
        try plan.release.manifest.validateOpenability(references: [changedDate], locators: [entry.locator])
        XCTAssertThrowsError(try plan.release.validateContent(references: [changedDate], locators: [entry.locator]))
        let shaOnly = try ContentReferenceV1(workspaceID: prior.workspaceID, contentID: prior.contentID,
            byteLength: prior.byteLength, mediaType: prior.mediaType,
            digests: ContentDigestSetV1([XCTUnwrap(prior.digests.digest(for: .sha256))]),
            byteRole: prior.byteRole, createdAt: prior.createdAt)
        XCTAssertThrowsError(try plan.release.validateContent(references: [shaOnly], locators: [entry.locator]))
        let wrongLocator = try ContentLocatorV1(locatorID: "different-owned-locator",
            workspaceID: prior.workspaceID, contentID: prior.contentID, locatorRevision: 0,
            contentDigest: entry.locator.contentDigest, expectedByteLength: prior.byteLength)
        XCTAssertThrowsError(try plan.release.validateContent(references: [prior], locators: [wrongLocator]))
        let huge = try ContentReferenceV1(workspaceID: prior.workspaceID, contentID: "huge-content",
            byteLength: FieldReferenceImportedContentV1.maximumBytes + 1, mediaType: prior.mediaType,
            digests: prior.digests, byteRole: .immutableOriginal, createdAt: prior.createdAt)
        XCTAssertThrowsError(try EvidenceBundleStore.fieldReferenceLocator(for: huge))
        let half = FieldReferenceImportedContentV1.maximumBytes / 2 + 1
        let entries = try ["bounded-a", "bounded-b"].map { id -> FieldReferenceImportedContentV1.Entry in
            let reference = try ContentReferenceV1(workspaceID: prior.workspaceID, contentID: id,
                byteLength: half, mediaType: prior.mediaType, digests: prior.digests,
                byteRole: .immutableOriginal, createdAt: prior.createdAt)
            return try .init(reference: reference, locator: EvidenceBundleStore.fieldReferenceLocator(for: reference))
        }
        XCTAssertThrowsError(try FieldReferenceImportedContentV1(entries: entries))
    }

    func testPhysicalImportedContentColdReadbackChecksAllDigestsAndOwnedFileIdentity() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("C23-content-\(UUID().uuidString)", isDirectory: true)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let root = session.generationRootURL
        defer { try? FileManager.default.removeItem(at: support) }
        let workspace = session.workspaceID
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: workspace)
        let metadata = try XCTUnwrap(plan.release.importedContent), item = plan.items[0]
        let store = EvidenceBundleStore(generationRootURL: root)
        let absent = try await store.readFieldReferenceContent(metadata)
        XCTAssertTrue(absent.isEmpty)
        let first = try await store.persistFieldReferenceItem(item, workspaceID: workspace, mutationID: plan.release.mutationID)
        XCTAssertFalse(first.reusedExistingBytes)
        let retry = try await store.persistFieldReferenceItem(item, workspaceID: workspace, mutationID: plan.release.mutationID)
        XCTAssertTrue(retry.reusedExistingBytes)
        let cold = EvidenceBundleStore(generationRootURL: root)
        let readback = try await cold.readFieldReferenceContent(metadata)
        XCTAssertEqual(readback, metadata.entries)
        let target = root.appendingPathComponent("content/\(item.reference.workspaceID)/\(item.reference.contentID)/original.bin")
        let original = try Data(contentsOf: target)
        XCTAssertEqual(original, item.bytes)
        var changed = original; changed[0] ^= 1
        try changed.write(to: target)
        await XCTAssertThrowsErrorAsync { _ = try await cold.readFieldReferenceContent(metadata) }
        try original.write(to: target)
        let repaired = try await cold.readFieldReferenceContent(metadata)
        XCTAssertEqual(repaired, metadata.entries)
        let badDigests = try ContentDigestSetV1([
            XCTUnwrap(item.reference.digests.digest(for: .sha256)),
            .init(algorithm: .sha512, hexadecimalValue: String(repeating: "0", count: 128))])
        let wrong = try ContentReferenceV1(workspaceID: item.reference.workspaceID,
            contentID: item.reference.contentID, byteLength: item.reference.byteLength,
            mediaType: item.reference.mediaType, digests: badDigests,
            byteRole: .immutableOriginal, createdAt: item.reference.createdAt)
        let forged = try FieldReferenceImportedContentV1(entries: [.init(reference: wrong, locator: item.locator)])
        await XCTAssertThrowsErrorAsync { _ = try await cold.readFieldReferenceContent(forged) }
        let held = target.deletingLastPathComponent().appendingPathComponent("held-original.bin")
        try FileManager.default.moveItem(at: target, to: held)
        let missing = try await cold.readFieldReferenceContent(metadata)
        XCTAssertTrue(missing.isEmpty)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: held)
        await XCTAssertThrowsErrorAsync { _ = try await cold.readFieldReferenceContent(metadata) }
        try FileManager.default.removeItem(at: target)
        try FileManager.default.linkItem(at: held, to: target)
        await XCTAssertThrowsErrorAsync { _ = try await cold.readFieldReferenceContent(metadata) }
        try FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: held, to: target)
        let restored = try await cold.readFieldReferenceContent(metadata)
        XCTAssertEqual(restored, metadata.entries)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testBoundFieldReferenceByteOwnerRejectsReplacementRootBeforeWriting() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("C23-bound-content-\(UUID().uuidString)", isDirectory: true)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let root = session.generationRootURL
        let held = support.appendingPathComponent("held-original-generation", isDirectory: true)
        var moved = false
        defer {
            if moved {
                try? FileManager.default.removeItem(at: root)
                try? FileManager.default.moveItem(at: held, to: root)
            }
            try? FileManager.default.removeItem(at: support)
        }
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: session.workspaceID)
        let metadata = try XCTUnwrap(plan.release.importedContent)
        let identity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        let content = EvidenceBundleStore(generationRootURL: root, expectedGenerationRootIdentity: identity)
        try FileManager.default.moveItem(at: root, to: held)
        moved = true
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            _ = try await content.persistFieldReferenceItem(plan.items[0],
                workspaceID: session.workspaceID, mutationID: plan.release.mutationID)
            XCTFail("A substituted directory must receive no imported bytes")
        } catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .generationRootInvalid) }
        do {
            _ = try await content.readFieldReferenceContent(metadata)
            XCTFail("A bound content read cannot acquire a substituted root")
        } catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .generationRootInvalid) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: held.appendingPathComponent("content").path))
        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: held, to: root)
        moved = false
        XCTAssertEqual(try ReportPDFAnchoredFile.rootIdentity(at: root), identity)
        _ = try await content.persistFieldReferenceItem(plan.items[0],
            workspaceID: session.workspaceID, mutationID: plan.release.mutationID)
        let actual = try await content.readFieldReferenceContent(metadata)
        XCTAssertEqual(actual, metadata.entries)
    }

    func testCurrentWriterFieldReferenceRetryPreservesReceiptAndRejectsCorruptionAndRetirement() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("C23-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
        let fixture = try await WorkCanonicalCurrentRouteFixtureV1.make(applicationSupportURL: support,
            pack: .illuminatedSignV1, workPhotoData: nil)
        defer { try? fixture.close(); try? FileManager.default.removeItem(at: support) }
        let writer = fixture.storeCoordinator.workspaceWriter
        let workspace = fixture.storeCoordinator.workspaceID
        let plan = try C23FieldReferenceTestSupport.productionPlan(workspaceID: workspace)
        let bridge = WorkspaceWriterFieldReferenceBridgeV1(writer: writer)
        let absent = try await bridge.acceptedReleaseReceipt(for: plan.release)
        XCTAssertNil(absent)
        let before = try writer.currentRevision()
        let first = try await bridge.appendRelease(plan.release)
        let original = try XCTUnwrap(writer.fieldReferenceReceipt(for: .importRelease(plan.release)))
        XCTAssertEqual(original.expectedRevision.workspaceRevision, before.revision)
        XCTAssertEqual(original.resultingRevision.workspaceRevision, before.revision + 1)
        XCTAssertEqual(original.expectedRevision.generationID, fixture.storeCoordinator.generationID)
        XCTAssertEqual(first.canonicalMutationReceiptSHA256, try original.canonicalSHA256())
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: workspace, release: plan.release)
        let bound = try await bridge.appendBinding(binding, release: plan.release)
        let history = try writer.sourceMutationHistorySnapshot()
        let revision = try writer.currentRevision()
        let retry = try await bridge.appendRelease(plan.release)
        let query = try await bridge.acceptedReleaseReceipt(for: plan.release)
        let bindingRetry = try await bridge.appendBinding(binding, release: plan.release)
        XCTAssertEqual(retry, first)
        XCTAssertEqual(query, first)
        XCTAssertEqual(bindingRetry, bound)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.fieldReferenceReceipt(for: .importRelease(plan.release)), original)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<FieldReferenceBindingRow>()), 1)
        let row = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<MutationReceiptRow>())
            .first { $0.mutationID == plan.release.mutationID.rawValue })
        let originalBytes = row.receiptData
        row.receiptData = Data("corrupt canonical receipt".utf8)
        try fixture.context.save()
        XCTAssertThrowsError(try writer.fieldReferenceReceipt(for: .importRelease(plan.release)))
        row.receiptData = originalBytes
        try fixture.context.save()
        XCTAssertEqual(try writer.fieldReferenceReceipt(for: .importRelease(plan.release)), original)
        let conflicting = try C23FieldReferenceTestSupport.release(workspaceID: workspace,
            contents: plan.items.map { .init(reference: $0.reference, locator: $0.locator, bytes: $0.bytes) },
            provenance: C23FieldReferenceTestSupport.provenance(scope: .citationAllowed),
            importedContent: plan.release.importedContent)
        XCTAssertEqual(conflicting.mutationID, plan.release.mutationID)
        XCTAssertNotEqual(conflicting.releaseSHA256, plan.release.releaseSHA256)
        XCTAssertThrowsError(try writer.fieldReferenceReceipt(for: .importRelease(conflicting))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        let quarantined = try writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(quarantined.receipts, history.receipts)
        XCTAssertEqual(quarantined.entityRevisions, history.entityRevisions)
        XCTAssertEqual(quarantined.workspaceRevision, history.workspaceRevision)
        XCTAssertEqual(quarantined.lastLocalSequence, history.lastLocalSequence)
        XCTAssertEqual(quarantined.quarantines.count, history.quarantines.count + 1)
        XCTAssertEqual(row.receiptData, originalBytes)
        XCTAssertThrowsError(try writer.commitFieldReference(.importRelease(plan.release))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        writer.invalidate()
        XCTAssertThrowsError(try writer.fieldReferenceReceipt(for: .importRelease(plan.release))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        do {
            _ = try await bridge.acceptedReleaseReceipt(for: plan.release)
            XCTFail("retired writer must reject bridge read")
        } catch {
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
    }

    func testImportItemVerifiesActualBytesAndEveryDeclaredDigest() async throws {
        let workspace = C23FieldReferenceTestSupport.workspace()
        let original = try C23FieldReferenceTestSupport.content(workspaceID: workspace, index: 91)
        let observed = try ContentIntegrityV1.observe(workspaceID: original.reference.workspaceID,
            contentID: original.reference.contentID, data: original.bytes,
            mediaType: original.reference.mediaType, algorithms: [.sha256, .sha512])
        func reference(_ digests: ContentDigestSetV1) throws -> ContentReferenceV1 {
            try .init(workspaceID: original.reference.workspaceID,
                contentID: original.reference.contentID, byteLength: original.reference.byteLength,
                mediaType: original.reference.mediaType, digests: digests,
                byteRole: original.reference.byteRole, createdAt: original.reference.createdAt)
        }
        let dual = try reference(observed.digests)
        let item = try FieldReferenceImportItemV1(reference: dual, locator: original.locator,
            bytes: original.bytes)
        XCTAssertEqual(item.bytes, original.bytes)
        XCTAssertEqual(item.reference.digests.values.map(\.algorithm), [.sha256, .sha512])
        var tampered = original.bytes
        tampered[0] ^= 1
        XCTAssertEqual(tampered.count, original.bytes.count)
        XCTAssertThrowsError(try FieldReferenceImportItemV1(reference: dual, locator: original.locator,
            bytes: tampered)) { XCTAssertEqual($0 as? ContentIntegrityFailureV1, .digestMismatch) }
        XCTAssertThrowsError(try FieldReferenceImportItemV1(reference: dual, locator: original.locator,
            bytes: Data(original.bytes.dropLast()))) {
            XCTAssertEqual($0 as? ContentIntegrityFailureV1, .byteLengthMismatch)
        }
        let badSecondary = try ContentDigestSetV1([
            XCTUnwrap(observed.digests.digest(for: .sha256)),
            .init(algorithm: .sha512, hexadecimalValue: String(repeating: "0", count: 128)),
        ])
        XCTAssertThrowsError(try FieldReferenceImportItemV1(reference: reference(badSecondary),
            locator: original.locator, bytes: original.bytes)) {
            XCTAssertEqual($0 as? ContentIntegrityFailureV1, .digestMismatch)
        }
        for wrongWorkspace in [false, true] {
            let wrong = try ContentLocatorV1(locatorID: original.locator.locatorID,
                workspaceID: wrongWorkspace ? C23FieldReferenceTestSupport.workspaceString(
                    C23FieldReferenceTestSupport.workspace(2)) : dual.workspaceID,
                contentID: wrongWorkspace ? dual.contentID : "c23.wrong-content",
                locatorRevision: original.locator.locatorRevision,
                contentDigest: original.locator.contentDigest,
                expectedByteLength: original.locator.expectedByteLength)
            XCTAssertThrowsError(try FieldReferenceImportItemV1(reference: dual, locator: wrong,
                bytes: original.bytes)) {
                XCTAssertEqual($0 as? ContentIntegrityFailureV1,
                    wrongWorkspace ? .wrongWorkspace : .missingContent)
            }
        }
        let contents = [C23FieldReferenceTestSupport.ContentFixture(reference: dual,
            locator: original.locator, bytes: original.bytes)]
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspace, contents: contents)
        let plan = try FieldReferenceImportPlanV1(release: release, items: [item])
        let contentStore = C23FieldReferenceContentStore(), writer = C23FieldReferenceWriter()
        let coordinator = FieldReferencePackCoordinatorV1(content: contentStore, writer: writer)
        let first = try await coordinator.importRelease(plan)
        let retry = try await coordinator.importRelease(plan)
        XCTAssertEqual(first, retry)
        try await contentStore.validateReadback(plan)
        let contentCounts = await contentStore.counts(), writerCounts = await writer.counts()
        XCTAssertEqual(contentCounts.persist, 1)
        XCTAssertEqual(contentCounts.discard, 0)
        XCTAssertEqual(writerCounts.release, 1)
        XCTAssertEqual(writerCounts.binding, 0)
        XCTAssertEqual(plan.items[0].bytes, original.bytes)
    }

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
    func testV23P03C23G01FieldReferenceReleaseAndBindingAreCanonicalAndOffline() async throws {
        let corpus = try C23FieldReferenceTestSupport.decodedCorpus()
        XCTAssertEqual(corpus.schema, "V22P03C23FieldReferencePackCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C23")
        XCTAssertEqual(corpus.records, 21)
        XCTAssertEqual(corpus.recordsSchemaVersion, 21)
        XCTAssertEqual(corpus.persistentSchemaVersion, 22)
        XCTAssertEqual(corpus.persistentModelCount, PersistentSchemaV22.models.count)
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), corpus.evidenceIDs)
        XCTAssertEqual(corpus.referenceKinds, FieldReferenceKindV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.provenanceKinds, FieldReferenceProvenanceKindV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.licenseScopes, FieldReferenceLicenseScopeV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.releaseDispositions, FieldReferenceReleaseDispositionV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.subjectKinds, FieldReferenceSubjectKindV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.subjectStates, FieldReferenceSubjectStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.availabilityStates, FieldReferenceAvailabilityV1.allCases.map(\.rawValue))
        XCTAssertEqual(PersistentSchemaV22.versionIdentifier, Schema.Version(22, 0, 0))
        XCTAssertTrue(corpus.immutableOriginals)
        XCTAssertFalse(corpus.externalCopyAvailabilityClaimed)
        XCTAssertFalse(corpus.runtimeFetchingAllowed)
        XCTAssertFalse(corpus.drmOrAccountRequired)
        XCTAssertFalse(corpus.currentProjectionPersistent)
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
        XCTAssertEqual(FieldReferencePackLifecycleV1.persistentFamilies.count, 2)
        XCTAssertEqual(FieldReferencePackLifecycleV1.stagingPersistence, "DERIVED_ONLY")
        XCTAssertFalse(FieldReferencePackLifecycleV1.runtimeFetchingAllowed)
        XCTAssertFalse(FieldReferencePackLifecycleV1.drmOrAccountRequired)
        XCTAssertFalse(FieldReferencePackLifecycleV1.currentProjectionPersistent)
        XCTAssertEqual(FieldReferencePackLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")

        let workspaceID = C23FieldReferenceTestSupport.workspace()
        let contents = try C23FieldReferenceTestSupport.contents(workspaceID: workspaceID)
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspaceID, contents: contents)
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: workspaceID, release: release)
        try release.validateContent(
            references: contents.map(\.reference),
            locators: contents.map(\.locator)
        )
        try binding.validate(release: release)
        let closure = FieldReferenceLifecycleClosureV1(
            release: release,
            binding: binding,
            references: contents.map(\.reference),
            locators: contents.map(\.locator)
        )
        XCTAssertEqual(
            try closure.validate(checkedAt: C23FieldReferenceTestSupport.fixedDate).availability,
            .readyOffline
        )
        XCTAssertEqual(
            try FieldReferencePackCanonicalCodecV1.decode(
                FieldReferenceReleaseV1.self,
                from: FieldReferencePackCanonicalCodecV1.encode(release)
            ),
            release
        )
        XCTAssertEqual(
            try FieldReferencePackCanonicalCodecV1.decode(
                FieldReferenceBindingV1.self,
                from: FieldReferencePackCanonicalCodecV1.encode(binding)
            ),
            binding
        )

        let plan = try C23FieldReferenceTestSupport.plan(
            workspaceID: workspaceID,
            contents: contents,
            release: release
        )
        let contentStore = C23FieldReferenceContentStore()
        let writer = C23FieldReferenceWriter()
        let coordinator = FieldReferencePackCoordinatorV1(content: contentStore, writer: writer)
        let importReceipt = try await coordinator.importRelease(plan)
        XCTAssertEqual(importReceipt.mutationID, release.mutationID)
        XCTAssertEqual(importReceipt.postImageSHA256, release.releaseSHA256)
        let bindReceipt = try await coordinator.bind(binding, to: release)
        XCTAssertEqual(bindReceipt.mutationID, binding.mutationID)
        XCTAssertEqual(bindReceipt.postImageSHA256, binding.bindingSHA256)
        let writerCounts = await writer.counts()
        XCTAssertEqual(writerCounts.release, 1)
        XCTAssertEqual(writerCounts.binding, 1)
    }

    func testV23P03C23A01AvailabilityExpiryRevocationSupersessionAndCodecAreExplicit() throws {
        let workspaceID = C23FieldReferenceTestSupport.workspace()
        let contents = try C23FieldReferenceTestSupport.contents(workspaceID: workspaceID)
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspaceID, contents: contents)
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: workspaceID, release: release)
        let references = contents.map(\.reference)
        let locators = contents.map(\.locator)

        let ready = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            references: references,
            locators: locators,
            knownSuccessorReleaseIDs: [],
            checkedAt: C23FieldReferenceTestSupport.fixedDate
        )
        XCTAssertEqual(ready.availability, .readyOffline)
        XCTAssertTrue(ready.missingContentIDs.isEmpty)

        let missing = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            references: [],
            locators: [],
            knownSuccessorReleaseIDs: [],
            checkedAt: C23FieldReferenceTestSupport.fixedDate
        )
        XCTAssertEqual(missing.availability, .missingBytes)
        XCTAssertEqual(missing.missingContentIDs, contents.map(\.reference.contentID).sorted())

        let expiring = try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            expiresAt: C23FieldReferenceTestSupport.fixedDate.addingTimeInterval(10)
        )
        let expiredBinding = try C23FieldReferenceTestSupport.binding(workspaceID: workspaceID, release: expiring)
        let expired = try FieldReferenceOfflineReadinessV1(
            release: expiring,
            binding: expiredBinding,
            references: references,
            locators: locators,
            knownSuccessorReleaseIDs: [],
            checkedAt: C23FieldReferenceTestSupport.fixedDate.addingTimeInterval(10)
        )
        XCTAssertEqual(expired.availability, .expired)

        let revoked = try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            disposition: .revoked,
            revokedAt: C23FieldReferenceTestSupport.fixedDate.addingTimeInterval(5)
        )
        XCTAssertThrowsError(try C23FieldReferenceTestSupport.binding(workspaceID: workspaceID, release: revoked))
        let revokedReadiness = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            references: references,
            locators: locators,
            knownSuccessorReleaseIDs: [],
            knownRevokedReleaseIDs: [release.releaseID],
            checkedAt: C23FieldReferenceTestSupport.fixedDate.addingTimeInterval(6)
        )
        XCTAssertEqual(revokedReadiness.availability, .revoked)

        let superseded = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            references: references,
            locators: locators,
            knownSuccessorReleaseIDs: [release.releaseID],
            checkedAt: C23FieldReferenceTestSupport.fixedDate
        )
        XCTAssertEqual(superseded.availability, .superseded)

        let protectedUnavailable = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            references: references,
            locators: locators,
            knownSuccessorReleaseIDs: [],
            checkedAt: C23FieldReferenceTestSupport.fixedDate,
            protectedDataAvailable: false
        )
        XCTAssertEqual(protectedUnavailable.availability, .protectedDataUnavailable)

        let wrongDigest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: C23FieldReferenceTestSupport.digest("b")
        )
        let badLocator = try ContentLocatorV1(
            locatorID: "c23-locator-bad",
            workspaceID: contents[0].locator.workspaceID,
            contentID: contents[0].locator.contentID,
            locatorRevision: 1,
            contentDigest: wrongDigest,
            expectedByteLength: contents[0].locator.expectedByteLength
        )
        let unavailable = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            references: references,
            locators: [badLocator, contents[1].locator],
            knownSuccessorReleaseIDs: [],
            checkedAt: C23FieldReferenceTestSupport.fixedDate
        )
        XCTAssertEqual(unavailable.availability, .unavailable)
        let staleLocator = try ContentLocatorV1(
            locatorID: "c23-locator-stale",
            workspaceID: contents[0].locator.workspaceID,
            contentID: contents[0].locator.contentID,
            locatorRevision: 0,
            contentDigest: try XCTUnwrap(contents[0].reference.digests.digest(for: .sha256)),
            expectedByteLength: contents[0].locator.expectedByteLength
        )
        XCTAssertThrowsError(try release.manifest.validateOpenability(
            references: references,
            locators: [staleLocator, contents[1].locator]
        ))

        let restricted = try C23FieldReferenceTestSupport.provenance(
            kind: .licensed,
            scope: .restricted,
            notice: "Local-use license only"
        )
        XCTAssertEqual(restricted.licenseScope, .restricted)
        XCTAssertFalse(restricted.authorityClaimed)
        let restrictedRelease = try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            provenance: restricted
        )
        XCTAssertThrowsError(try FieldReferenceCitationV1(release: restrictedRelease))
        XCTAssertEqual(
            try FieldReferenceCitationV1(release: release).referencePackID,
            release.referencePackID
        )
        XCTAssertThrowsError(try FieldReferenceProvenanceV1(
            kind: .licensed,
            sourceName: "C23 deterministic field references",
            sourceReleaseIdentifier: "c23.reference.corpus.v1",
            licenseScope: .restricted
        ))

        var nonCanonical = try FieldReferencePackCanonicalCodecV1.encode(release)
        nonCanonical.append(0x20)
        XCTAssertThrowsError(try FieldReferencePackCanonicalCodecV1.decode(
            FieldReferenceReleaseV1.self,
            from: nonCanonical
        ))
        XCTAssertThrowsError(try FieldReferenceReleaseV1(
            releaseID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            workspaceID: workspaceID,
            referencePackID: "c23.field-reference-pack",
            kind: .specification,
            semanticVersion: "1.0.0",
            provenance: try C23FieldReferenceTestSupport.provenance(),
            manifest: release.manifest,
            issuedAt: C23FieldReferenceTestSupport.fixedDate,
            mutationID: try C23FieldReferenceTestSupport.mutation(11)
        ))
    }

    func testV23P03C23H01ForgedBytesWrongBindingsAndFinalizedSuccessorsFailClosed() throws {
        let workspaceID = C23FieldReferenceTestSupport.workspace()
        let contents = try C23FieldReferenceTestSupport.contents(workspaceID: workspaceID)
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspaceID, contents: contents)
        let plan = try C23FieldReferenceTestSupport.plan(
            workspaceID: workspaceID,
            contents: contents,
            release: release
        )

        var forgedBytes = contents[0].bytes
        forgedBytes.append(0x21)
        XCTAssertThrowsError(try FieldReferenceImportItemV1(
            reference: contents[0].reference,
            locator: contents[0].locator,
            bytes: forgedBytes
        ))

        let otherWorkspace = C23FieldReferenceTestSupport.workspace(999)
        XCTAssertThrowsError(try FieldReferenceBindingV1(
            bindingID: C23FieldReferenceTestSupport.id(400),
            workspaceID: otherWorkspace,
            subjectKind: .workPacket,
            subjectID: C23FieldReferenceTestSupport.id(200),
            subjectRevision: 1,
            subjectState: .active,
            release: release,
            boundAt: C23FieldReferenceTestSupport.fixedDate,
            mutationID: try C23FieldReferenceTestSupport.mutation(401)
        ))

        let otherRelease = try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            releaseID: C23FieldReferenceTestSupport.id(402),
            mutationSlot: 403
        )
        let binding = try C23FieldReferenceTestSupport.binding(
            workspaceID: workspaceID,
            release: release,
            mutationSlot: 404
        )
        XCTAssertThrowsError(try binding.validate(release: otherRelease))

        let canonicalInputs = FieldReferenceReadinessInputsV1(
            references: contents.map(\.reference),
            locators: contents.map(\.locator),
            evaluatedAt: binding.boundAt,
            policy: .exactLocalContentV1,
            protectedDataAvailable: true
        )
        let canonicalReadiness = try FieldReferenceOfflineReadinessV1(
            release: release,
            binding: binding,
            inputs: canonicalInputs
        )
        let foreignContents = try C23FieldReferenceTestSupport.contents(workspaceID: otherWorkspace)
        let foreignInputs = FieldReferenceReadinessInputsV1(
            references: foreignContents.map(\.reference),
            locators: foreignContents.map(\.locator),
            evaluatedAt: binding.boundAt,
            policy: .exactLocalContentV1,
            protectedDataAvailable: true
        )
        XCTAssertThrowsError(try canonicalReadiness.validate(
            recomputedFrom: foreignInputs,
            release: release,
            binding: binding
        ))
        let staleInputs = FieldReferenceReadinessInputsV1(
            references: canonicalInputs.references,
            locators: canonicalInputs.locators,
            evaluatedAt: binding.boundAt.addingTimeInterval(-1),
            policy: .exactLocalContentV1,
            protectedDataAvailable: true
        )
        XCTAssertThrowsError(try canonicalReadiness.validate(
            recomputedFrom: staleInputs,
            release: release,
            binding: binding
        ))
        let forgedInputs = FieldReferenceReadinessInputsV1(
            references: canonicalInputs.references,
            locators: canonicalInputs.locators,
            knownSupersededReleaseIDs: [release.releaseID],
            evaluatedAt: binding.boundAt,
            policy: .exactLocalContentV1,
            protectedDataAvailable: true
        )
        XCTAssertThrowsError(try canonicalReadiness.validate(
            recomputedFrom: forgedInputs,
            release: release,
            binding: binding
        ))

        XCTAssertThrowsError(try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            revision: 2,
            mutationSlot: 405
        ))
        let releaseSuccessor = try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            releaseID: C23FieldReferenceTestSupport.id(500),
            supersedesReleaseID: release.releaseID,
            revision: 2,
            mutationSlot: 501
        )
        try releaseSuccessor.validateSuccessor(of: release)
        let reusedMutationSuccessor = try C23FieldReferenceTestSupport.binding(
            workspaceID: workspaceID,
            release: release,
            subjectID: binding.subjectID,
            subjectRevision: 2,
            supersedesBindingID: binding.bindingID,
            revision: 2,
            mutationSlot: 404
        )
        XCTAssertThrowsError(try reusedMutationSuccessor.validateSuccessor(of: binding, release: release))

        let finalized = try C23FieldReferenceTestSupport.binding(
            workspaceID: workspaceID,
            release: release,
            subjectID: binding.subjectID,
            subjectState: .finalized,
            mutationSlot: 406
        )
        let finalizedSuccessor = try C23FieldReferenceTestSupport.binding(
            workspaceID: workspaceID,
            release: release,
            subjectID: finalized.subjectID,
            subjectRevision: 2,
            supersedesBindingID: finalized.bindingID,
            revision: 2,
            mutationSlot: 407
        )
        XCTAssertThrowsError(try finalizedSuccessor.validateSuccessor(of: finalized, release: release))

        let releaseRow = try FieldReferenceReleaseRow(release)
        releaseRow.releaseSHA256 = C23FieldReferenceTestSupport.digest("z")
        XCTAssertThrowsError(try releaseRow.value())
        let bindingRow = try FieldReferenceBindingRow(binding, release: release)
        bindingRow.bindingSHA256 = C23FieldReferenceTestSupport.digest("z")
        XCTAssertThrowsError(try bindingRow.value(release: release))
        XCTAssertEqual(plan.items.count, release.manifest.entries.count)

        var forgedProvenance = try JSONSerialization.jsonObject(
            with: FieldReferencePackCanonicalCodecV1.encode(C23FieldReferenceTestSupport.provenance())
        ) as! [String: Any]
        forgedProvenance["authorityClaimed"] = true
        let forgedProvenanceData = try JSONSerialization.data(
            withJSONObject: forgedProvenance,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let decodedForgedProvenance = try FieldReferencePackCanonicalCodecV1.decode(
            FieldReferenceProvenanceV1.self,
            from: forgedProvenanceData
        )
        XCTAssertThrowsError(try decodedForgedProvenance.validate())
    }

    func testV23P03C23I01ImportAndBindInterruptionRecoverWithoutPartialCanonicalState() async throws {
        let workspaceID = C23FieldReferenceTestSupport.workspace()
        let contents = try C23FieldReferenceTestSupport.contents(workspaceID: workspaceID)
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspaceID, contents: contents)
        let plan = try C23FieldReferenceTestSupport.plan(
            workspaceID: workspaceID,
            contents: contents,
            release: release
        )
        let binding = try C23FieldReferenceTestSupport.binding(
            workspaceID: workspaceID,
            release: release
        )
        let interruptionPoints: [FieldReferenceInterruptionPointV1] = [
            .afterContentReadbackBeforeRelease,
            .afterReleaseBeforeReturn,
            .afterReadinessBeforeBinding,
            .afterBindingBeforeReturn
        ]
        for point in interruptionPoints {
            let adapter = FieldReferencePackLifecycleAdapterV1(
                operations: C23FieldReferenceTestSupport.lifecycleOperations(
                    plan: plan,
                    release: release,
                    binding: binding,
                    interruption: { observed in
                        if observed.rawValue == point.rawValue {
                            throw C23FieldReferenceTestFailure.interrupted
                        }
                    }
                )
            )
            let coordinator = FieldReferencePackCoordinatorV1(content: adapter, writer: adapter)
            if point.rawValue == FieldReferenceInterruptionPointV1.afterContentReadbackBeforeRelease.rawValue || point.rawValue == FieldReferenceInterruptionPointV1.afterReleaseBeforeReturn.rawValue {
                await XCTAssertThrowsErrorAsync {
                    _ = try await coordinator.importRelease(plan)
                }
            } else {
                await XCTAssertThrowsErrorAsync {
                    _ = try await coordinator.bind(binding, to: release)
                }
            }
        }

        let persistFailureStore = C23FieldReferenceContentStore(failPersist: true)
        let persistCoordinator = FieldReferencePackCoordinatorV1(
            content: persistFailureStore,
            writer: C23FieldReferenceWriter()
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await persistCoordinator.importRelease(plan)
        }
        let persistFailureCounts = await persistFailureStore.counts()
        XCTAssertEqual(persistFailureCounts.discard, 1)

        let readbackFailureStore = C23FieldReferenceContentStore(failReadback: true)
        let readbackCoordinator = FieldReferencePackCoordinatorV1(
            content: readbackFailureStore,
            writer: C23FieldReferenceWriter()
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await readbackCoordinator.importRelease(plan)
        }
        let readbackCounts = await readbackFailureStore.counts()
        XCTAssertEqual(readbackCounts.persist, 1)
        XCTAssertEqual(readbackCounts.discard, 1)

        let writerFailureStore = C23FieldReferenceContentStore()
        let writerFailureCoordinator = FieldReferencePackCoordinatorV1(
            content: writerFailureStore,
            writer: C23FieldReferenceWriter(wrongReleaseReceipt: true)
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await writerFailureCoordinator.importRelease(plan)
        }
        let writerFailureCounts = await writerFailureStore.counts()
        XCTAssertEqual(writerFailureCounts.discard, 1)

        let contentStore = C23FieldReferenceContentStore()
        let writer = C23FieldReferenceWriter()
        let coordinator = FieldReferencePackCoordinatorV1(content: contentStore, writer: writer)
        let first = try await coordinator.importRelease(plan)
        let second = try await coordinator.importRelease(plan)
        XCTAssertEqual(first, second)
        let contentCounts = await contentStore.counts()
        let writerRetryCounts = await writer.counts()
        XCTAssertEqual(contentCounts.persist, 1)
        XCTAssertEqual(writerRetryCounts.release, 1)

        let bindFirst = try await coordinator.bind(binding, to: release)
        let bindSecond = try await coordinator.bind(binding, to: release)
        XCTAssertEqual(bindFirst, bindSecond)
        let bindingRetryCounts = await writer.counts()
        XCTAssertEqual(bindingRetryCounts.binding, 1)

        let bindFailureContent = C23FieldReferenceContentStore(failReadiness: true)
        await bindFailureContent.seed(plan)
        let bindFailureWriter = C23FieldReferenceWriter()
        let bindFailureCoordinator = FieldReferencePackCoordinatorV1(
            content: bindFailureContent,
            writer: bindFailureWriter
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await bindFailureCoordinator.bind(binding, to: release)
        }
        let bindFailureCounts = await bindFailureWriter.counts()
        XCTAssertEqual(bindFailureCounts.binding, 0)
    }

    func testV23P03C23R01V22BackupRestoreExportReplayAndRetentionRemainBounded() throws {
        let workspaceID = C23FieldReferenceTestSupport.workspace()
        let contents = try C23FieldReferenceTestSupport.contents(workspaceID: workspaceID)
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspaceID, contents: contents)
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: workspaceID, release: release)
        let releaseData = try FieldReferencePackCanonicalCodecV1.encode(release)
        let bindingData = try FieldReferencePackCanonicalCodecV1.encode(binding)
        let releaseRecord = V22BackupFieldReferenceRecordV1(
            kind: .release,
            id: release.releaseID,
            workspaceID: workspaceID.rawValue,
            revision: release.revision,
            canonicalData: releaseData
        )
        let bindingRecord = V22BackupFieldReferenceRecordV1(
            kind: .binding,
            id: binding.bindingID,
            workspaceID: workspaceID.rawValue,
            revision: binding.revision,
            canonicalData: bindingData
        )
        let records = V4BackupRecordsV1(
            fieldReferences: [bindingRecord, releaseRecord],
            assets: [],
            evidenceFiles: [],
            issues: [],
            packets: [],
            recordsSchemaVersion: 21,
            reports: [],
            sites: [],
            workflowRecords: []
        )
        let encoded = try BackupCanonicalEncoderV1().encodeRecords(records)
        let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded.data)
        XCTAssertEqual(decoded.fieldReferences, [bindingRecord, releaseRecord])
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(
            V4BackupRecordsV1(
                fieldReferences: [releaseRecord, releaseRecord],
                assets: [],
                evidenceFiles: [],
                issues: [],
                packets: [],
                recordsSchemaVersion: 21,
                reports: [],
                sites: [],
                workflowRecords: []
            )
        ))

        let releaseRow = try FieldReferenceReleaseRow(release)
        let bindingRow = try FieldReferenceBindingRow(binding, release: release)
        XCTAssertEqual(try releaseRow.value(), release)
        XCTAssertEqual(try bindingRow.value(release: release), binding)
        XCTAssertEqual(PersistentSchemaV22.models.count, PersistentSchemaV21.models.count + 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV21.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV21.stages.count, 1)
        XCTAssertNoThrow(try V22FieldReferenceImportBoundaryV1.validate(persistent: 22, records: 21))
        XCTAssertThrowsError(try V22FieldReferenceImportBoundaryV1.validate(persistent: 21, records: 20))

        let destination = C23FieldReferenceTestSupport.workspace(900)
        let destinationContents = try C23FieldReferenceTestSupport.contents(workspaceID: destination)
        let reboundRelease = try release.rebound(
            to: destination,
            manifest: try C23FieldReferenceTestSupport.manifest(
                workspaceID: destination,
                contents: destinationContents
            )
        )
        XCTAssertEqual(reboundRelease.releaseID, release.releaseID)
        XCTAssertEqual(reboundRelease.mutationID, release.mutationID)
        XCTAssertEqual(reboundRelease.workspaceID, destination)
        let reboundBinding = try binding.rebound(to: destination, release: reboundRelease)
        XCTAssertEqual(reboundBinding.bindingID, binding.bindingID)
        XCTAssertEqual(reboundBinding.releaseID, reboundRelease.releaseID)
        try reboundBinding.validate(release: reboundRelease)

        XCTAssertEqual(FieldReferencePackLifecycleV1.persistentFamilies, [
            "FieldReferenceReleaseV1", "FieldReferenceBindingV1"
        ])
        XCTAssertEqual(FieldReferencePackLifecycleV1.stagingPersistence, "DERIVED_ONLY")
        XCTAssertFalse(FieldReferencePackLifecycleV1.runtimeFetchingAllowed)
        XCTAssertFalse(FieldReferencePackLifecycleV1.currentProjectionPersistent)
        XCTAssertFalse(FieldReferencePackLifecycleV1.drmOrAccountRequired)
        XCTAssertEqual(FieldReferencePackLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertFalse(FieldReferenceRetentionV1.mayDiscardRelease(release, bindings: [binding]))
        XCTAssertTrue(FieldReferenceRetentionV1.mayDiscardRelease(release, bindings: []))
        XCTAssertFalse(FieldReferenceRetentionV1.mayExportBytes(release))
        let exportableRelease = try C23FieldReferenceTestSupport.release(
            workspaceID: workspaceID,
            contents: contents,
            provenance: try C23FieldReferenceTestSupport.provenance(
                kind: .licensed,
                scope: .citationAndExportAllowed,
                notice: "Citation and export permitted"
            )
        )
        XCTAssertTrue(FieldReferenceRetentionV1.mayExportBytes(exportableRelease))
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: @escaping () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("expected error", file: file, line: line)
        } catch {
            XCTAssertTrue(true, file: file, line: line)
        }
    }
}
private final class C31LightingAnchorV937FieldReferencePackTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV937FieldReferencePack: XCTestCase {
    func testC33V937FieldReferencePackCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "reference-pack.temporal-source-link",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "reference-pack.temporal-source-link",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV937FieldReferencePack: XCTestCase {
    func testC32V937FieldReferencePackCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .fieldReferenceBinding,
            fieldID: "field-reference.package-expiry",
            value: .text("pack-bound field proposal")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .fieldReferenceBinding,
            fieldID: "field-reference.package-expiry",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V937PackCompatibilityTests: XCTestCase {
    func testC46ReferencePackCannotPrefillOperationalContact() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "reference-pack",
            kind: .email,
            handoff: .email,
            slot: 46037
        )
    }
}
