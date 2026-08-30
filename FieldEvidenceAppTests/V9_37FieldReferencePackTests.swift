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
        provenance: FieldReferenceProvenanceV1? = nil
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
            mutationID: try mutation(mutationSlot)
        )
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
